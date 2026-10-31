"""Exercise selection against real disposable Git history and job outcomes."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import policy


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-ci-policy-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "user.name", "Fixture")
        self.git("config", "core.autocrlf", "false")
        self.base = self.commit("app/fixture.txt", "base")

    def git(self, *args):
        return policy.git(self.root, *args).strip()

    def commit(self, path, content):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content, encoding="utf-8")
        self.git("add", "--", path)
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def receipt(self, sha=None, base=None, event="push", ref="refs/heads/main", payload=None):
        sha = sha or self.git("rev-parse", "HEAD")
        return policy.selection(self.root, event, ref, sha,
                                payload if payload is not None else {"before": base or self.base, "after": sha})

    def test_safe_docs_recommend_skip_but_shadow_keeps_every_production_gate(self):
        receipt = self.receipt(self.commit("docs/TOOLS.md", "doc"))
        self.assertFalse(receipt["recommended"]["production"])
        for job in (*policy.PRODUCTION, "three", "export"):
            self.assertTrue(receipt["required"][job])

    def test_hashed_readme_and_unknown_markdown_remain_full(self):
        for path in ("assets/source-deliveries/model/README.md", "research/example.md",
                     "docs/research/result.md", "docs/releases/v1.2.3.md", "unknown.md"):
            with self.subTest(path=path):
                self.assertTrue(all(policy.recommend([path]).values()))

    def test_mixed_domains_are_a_union(self):
        for paths in (["site/main.js", "app/main.gd"],
                      ["prototypes/stage0/three/main.ts", "app/main.gd"],
                      ["site/main.js", "prototypes/stage0/three/main.ts"]):
            with self.subTest(paths=paths):
                result = policy.recommend(paths)
                self.assertTrue(result["site"] and result["prototype"])
        self.assertFalse(policy.recommend(["site/main.js"])["production"])

    def test_multicommit_push_does_not_only_examine_latest_commit(self):
        self.commit("app/physics/change.gd", "code")
        receipt = self.receipt(self.commit("docs/TOOLS.md", "docs"))
        self.assertIn("app/physics/change.gd", receipt["paths"])
        self.assertTrue(receipt["recommended"]["production"])

    def test_rename_to_documentation_includes_deleted_code(self):
        self.git("mv", "app/fixture.txt", "AGENTS.md")
        self.git("commit", "-qm", "rename")
        self.assertEqual(self.receipt()["paths"], ["AGENTS.md", "app/fixture.txt"])
        self.assertTrue(self.receipt()["recommended"]["production"])

    def test_nul_delimited_spaces_and_unicode(self):
        self.commit("site/archivo con espacio ñ.txt", "content")
        self.assertEqual(self.receipt()["paths"], ["site/archivo con espacio ñ.txt"])

    def test_missing_zero_and_unknown_bases_never_skip(self):
        sha = self.commit("docs/TOOLS.md", "docs")
        for base in ("", "0" * 40, "f" * 40, "--help"):
            with self.subTest(base=base):
                receipt = self.receipt(sha, payload={"before": base, "after": sha})
                self.assertTrue(all(receipt["recommended"].values()))

    def test_empty_diff_and_wrong_push_metadata_force_full(self):
        self.assertTrue(all(self.receipt()["recommended"].values()))
        self.assertTrue(all(self.receipt(payload={"before": self.base, "after": "f" * 40})["recommended"].values()))

    def test_wrong_checked_source_is_fatal(self):
        with self.assertRaises(ValueError):
            self.receipt("f" * 40)

    def test_tags_manual_and_merge_queue_force_full(self):
        sha = self.commit("docs/TOOLS.md", "docs")
        for event, ref in (("push", "refs/tags/v1.2.3"), ("workflow_dispatch", "refs/heads/main"),
                           ("merge_group", "refs/heads/gh-readonly-queue/main/test")):
            with self.subTest(event=event):
                self.assertTrue(all(self.receipt(sha, event=event, ref=ref)["recommended"].values()))

    def test_pr_compares_actual_merge_parents(self):
        original = self.git("branch", "--show-current")
        self.git("checkout", "-qb", "fixture-feature")
        head = self.commit("docs/TOOLS.md", "pr")
        self.git("checkout", "-q", original)
        self.git("merge", "--no-ff", "-qm", "fixture merge", "fixture-feature")
        payload = {"pull_request": {"base": {"sha": self.base}, "head": {"sha": head}}}
        receipt = self.receipt(event="pull_request", ref="refs/pull/1/merge", payload=payload)
        self.assertFalse(receipt["recommended"]["production"])
        payload["pull_request"]["base"]["sha"] = "f" * 40
        self.assertTrue(all(self.receipt(event="pull_request", ref="refs/pull/1/merge", payload=payload)["recommended"].values()))

    def test_diff_execution_error_is_fatal(self):
        sha = self.commit("docs/TOOLS.md", "docs")
        real = policy.git
        def broken(root, *args):
            if args[0] == "diff":
                raise subprocess.CalledProcessError(1, "git diff")
            return real(root, *args)
        with patch.object(policy, "git", broken), self.assertRaises(subprocess.CalledProcessError):
            self.receipt(sha)

    def test_every_required_job_failure_cancellation_and_skip_is_fatal(self):
        receipt = self.receipt(self.commit("app/change.gd", "runtime"))
        needs = {name: {"result": "success"} for name in ("scope", *policy.JOBS)}
        policy.verify(receipt, needs, receipt["sha"], "push", "refs/heads/main")
        for name in needs:
            for outcome in ("failure", "cancelled", "skipped", None):
                with self.subTest(name=name, outcome=outcome):
                    broken = copy.deepcopy(needs)
                    broken[name]["result"] = outcome
                    with self.assertRaises(ValueError):
                        policy.verify(receipt, broken, receipt["sha"], "push", "refs/heads/main")

    def test_intentional_site_skip_and_no_export_on_pr(self):
        receipt = self.receipt(self.commit("docs/TOOLS.md", "docs"))
        needs = {name: {"result": "success"} for name in ("scope", *policy.JOBS)}
        needs["site"]["result"] = "skipped"
        policy.verify(receipt, needs, receipt["sha"], "push", "refs/heads/main")

    def test_corrupt_receipts_fail(self):
        receipt = self.receipt(self.commit("docs/TOOLS.md", "docs"))
        for key, value in (("format", "unknown"), ("mode", "active"), ("sha", "f" * 40),
                           ("policy_sha256", "f" * 64), ("required", {}), ("paths", ["../bad"])):
            broken = copy.deepcopy(receipt)
            broken[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                policy.validate(broken, receipt["sha"], "push", "refs/heads/main")
        needs = {name: {"result": "success"} for name in ("scope", *policy.JOBS)}
        del needs["app"]
        with self.assertRaises(ValueError):
            policy.verify(receipt, needs, receipt["sha"], "push", "refs/heads/main")


if __name__ == "__main__":
    unittest.main()
