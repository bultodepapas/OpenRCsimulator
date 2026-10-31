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
                                payload if payload is not None else self.push(sha, base, ref))

    def push(self, sha, base=None, ref="refs/heads/main"):
        return {"before": self.base if base is None else base, "after": sha,
                "ref": ref, "deleted": False}

    def verify(self, receipt, needs, payload=None):
        return policy.verify(receipt, needs, self.root, receipt["sha"], "push", "refs/heads/main",
                             payload if payload is not None else self.push(receipt["sha"]))

    def validate(self, receipt, payload=None):
        return policy.validate(receipt, self.root, receipt["sha"], "push", "refs/heads/main",
                               payload if payload is not None else self.push(receipt["sha"]))

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

    def test_safe_document_deletion_and_mode_change_force_full_union(self):
        self.base = self.commit("AGENTS.md", "existing")
        self.git("rm", "AGENTS.md")
        self.git("commit", "-qm", "delete")
        deleted = self.receipt()
        self.assertEqual(deleted["paths"], ["AGENTS.md"])
        self.assertTrue(all(deleted["recommended"].values()))

        self.base = self.git("rev-parse", "HEAD")
        self.commit("docs/TOOLS.md", "tool guide")
        self.git("update-index", "--chmod=+x", "docs/TOOLS.md")
        self.git("commit", "-qm", "executable guide")
        self.assertTrue(all(self.receipt()["recommended"].values()))

    def test_safe_document_replaced_by_symlink_forces_full_union(self):
        self.base = self.commit("docs/TOOLS.md", "regular guide")
        result = subprocess.run(["git", "-C", str(self.root), "hash-object", "-w", "--stdin"],
                                input=b"../AGENTS.md", stdout=subprocess.PIPE, check=True)
        self.git("update-index", "--cacheinfo", f"120000,{result.stdout.decode().strip()},docs/TOOLS.md")
        self.git("commit", "-qm", "symlink guide")
        self.assertTrue(all(self.receipt()["recommended"].values()))

    def test_nul_delimited_spaces_and_unicode(self):
        self.commit("site/archivo con espacio ñ.txt", "content")
        self.assertEqual(self.receipt()["paths"], ["site/archivo con espacio ñ.txt"])

    def test_missing_zero_and_unknown_bases_never_skip(self):
        sha = self.commit("docs/TOOLS.md", "docs")
        for base in ("", "0" * 40, "f" * 40, "--help"):
            with self.subTest(base=base):
                receipt = self.receipt(sha, payload=self.push(sha, base))
                self.assertTrue(all(receipt["recommended"].values()))

    def test_empty_diff_and_wrong_push_metadata_force_full(self):
        self.assertTrue(all(self.receipt()["recommended"].values()))
        self.assertTrue(all(self.receipt(payload={"before": self.base, "after": "f" * 40})["recommended"].values()))

    def test_missing_or_mismatched_push_identity_forces_full(self):
        sha = self.commit("docs/TOOLS.md", "docs")
        valid = self.push(sha)
        for field, value in (("ref", "refs/heads/other"), ("after", "f" * 40),
                             ("deleted", True), ("deleted", None)):
            payload = {**valid, field: value}
            with self.subTest(field=field, value=value):
                self.assertTrue(all(self.receipt(sha, payload=payload)["recommended"].values()))

    def test_malformed_pr_metadata_forces_full(self):
        sha = self.commit("docs/TOOLS.md", "docs")
        for payload in ({}, {"number": 1, "pull_request": "bad"},
                        {"number": 1, "pull_request": {"base": "bad", "head": {}}},
                        {"number": True, "pull_request": {"base": {"sha": self.base}, "head": {"sha": sha}}}):
            with self.subTest(payload=payload):
                receipt = self.receipt(sha, event="pull_request", ref="refs/pull/1/merge", payload=payload)
                self.assertTrue(all(receipt["recommended"].values()))

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
        payload = {"number": 1, "pull_request": {"base": {"sha": self.base}, "head": {"sha": head}}}
        receipt = self.receipt(event="pull_request", ref="refs/pull/1/merge", payload=payload)
        self.assertFalse(receipt["recommended"]["production"])
        self.assertEqual(receipt["head"], head)
        self.assertEqual(receipt["base"], self.base)
        payload["pull_request"]["base"]["sha"] = "f" * 40
        self.assertTrue(all(self.receipt(event="pull_request", ref="refs/pull/1/merge", payload=payload)["recommended"].values()))

    def test_depth_two_pr_checkout_retains_both_merge_parents(self):
        original = self.git("branch", "--show-current")
        self.git("checkout", "-qb", "fixture-feature")
        head = self.commit("docs/TOOLS.md", "pr")
        self.git("checkout", "-q", original)
        self.git("merge", "--no-ff", "-qm", "fixture merge", "fixture-feature")
        merge = self.git("rev-parse", "HEAD")
        clone = self.root.parent / (self.root.name + "-pr")
        self.addCleanup(lambda: __import__("shutil").rmtree(clone, ignore_errors=True))
        subprocess.run(["git", "clone", "-q", "--depth=2", self.root.as_uri(), str(clone)], check=True)
        payload = {"number": 1, "pull_request": {"base": {"sha": self.base}, "head": {"sha": head}}}
        receipt = policy.selection(clone, "pull_request", "refs/pull/1/merge", merge, payload)
        self.assertEqual(receipt["base"], self.base)
        self.assertEqual(receipt["head"], head)
        self.assertFalse(receipt["recommended"]["production"])

    def test_diff_execution_error_is_fatal(self):
        sha = self.commit("docs/TOOLS.md", "docs")
        real = policy.git
        def broken(root, *args):
            if args[0] == "diff":
                raise subprocess.CalledProcessError(1, "git diff")
            return real(root, *args)
        with patch.object(policy, "git", broken), self.assertRaises(subprocess.CalledProcessError):
            self.receipt(sha)

    def test_malformed_git_diff_is_fatal(self):
        sha = self.commit("docs/TOOLS.md", "docs")
        real = policy.git
        for raw in ("not a raw diff\0doc\0", ":100644 100644 a b M\0../escape\0",
                    ":100644 100644 a b M\0docs/TOOLS.md"):
            def broken(root, *args):
                return raw if args[0] == "diff" else real(root, *args)
            with self.subTest(raw=raw), patch.object(policy, "git", broken), self.assertRaises(ValueError):
                self.receipt(sha)

    def test_changed_receipt_cannot_choose_a_favorable_comparison_base(self):
        self.commit("app/physics.gd", "code")
        favorable_base = self.git("rev-parse", "HEAD")
        sha = self.commit("docs/TOOLS.md", "docs")
        falsified = self.receipt(sha, base=favorable_base)
        self.assertFalse(falsified["recommended"]["production"])
        with self.assertRaises(ValueError):
            self.validate(falsified)

    def test_fetch_uses_event_base_even_if_receipt_is_forged(self):
        sha = self.commit("docs/TOOLS.md", "docs")
        event_base = "f" * 40
        payload = self.push(sha, event_base)
        forged = self.receipt(sha, payload=payload)
        forged["base"] = "a" * 40
        fetched = []
        real = policy.git

        def no_history(root, *args):
            if args[0] == "cat-file":
                raise subprocess.CalledProcessError(1, args)
            if args[0] == "fetch":
                fetched.append(args[-1])
                raise subprocess.CalledProcessError(1, args)
            return real(root, *args)

        with patch.object(policy, "git", no_history), self.assertRaises(ValueError):
            policy.validate(forged, self.root, sha, "push", "refs/heads/main", payload, fetch=True)
        self.assertEqual(fetched, [event_base])

    def test_shallow_checkout_fetches_only_the_event_base(self):
        sha = self.commit("docs/TOOLS.md", "docs")
        clone = self.root.parent / (self.root.name + "-shallow")
        self.addCleanup(lambda: __import__("shutil").rmtree(clone, ignore_errors=True))
        subprocess.run(["git", "clone", "-q", "--depth=1", self.root.as_uri(), str(clone)], check=True)
        receipt = policy.selection(clone, "push", "refs/heads/main", sha, self.push(sha), fetch=True)
        self.assertEqual(receipt["base"], self.base)
        self.assertEqual(receipt["paths"], ["docs/TOOLS.md"])
        self.assertFalse(receipt["recommended"]["production"])

    def test_every_required_job_failure_cancellation_and_skip_is_fatal(self):
        receipt = self.receipt(self.commit("app/change.gd", "runtime"))
        needs = {name: {"result": "success"} for name in ("scope", *policy.JOBS)}
        self.verify(receipt, needs)
        for name in needs:
            for outcome in ("failure", "cancelled", "skipped", None):
                with self.subTest(name=name, outcome=outcome):
                    broken = copy.deepcopy(needs)
                    broken[name]["result"] = outcome
                    with self.assertRaises(ValueError):
                        self.verify(receipt, broken)

    def test_intentional_site_skip_and_no_export_on_pr(self):
        receipt = self.receipt(self.commit("docs/TOOLS.md", "docs"))
        needs = {name: {"result": "success"} for name in ("scope", *policy.JOBS)}
        needs["site"]["result"] = "skipped"
        self.verify(receipt, needs)

    def test_invalid_needs_shape_is_fatal(self):
        receipt = self.receipt(self.commit("docs/TOOLS.md", "docs"))
        needs = {name: {"result": "success"} for name in ("scope", *policy.JOBS)}
        needs["app"] = "success"
        with self.assertRaises(ValueError):
            self.verify(receipt, needs)

    def test_corrupt_receipts_fail(self):
        receipt = self.receipt(self.commit("docs/TOOLS.md", "docs"))
        for key, value in (("format", "unknown"), ("mode", "active"), ("sha", "f" * 40),
                           ("policy_sha256", "f" * 64), ("required", {}), ("paths", ["../bad"])):
            broken = copy.deepcopy(receipt)
            broken[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate(broken)
        needs = {name: {"result": "success"} for name in ("scope", *policy.JOBS)}
        del needs["app"]
        with self.assertRaises(ValueError):
            self.verify(receipt, needs)


if __name__ == "__main__":
    unittest.main()
