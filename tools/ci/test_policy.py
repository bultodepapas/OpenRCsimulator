"""Exercise selection against real disposable Git history and job outcomes."""
import copy
import json
from pathlib import Path
import re
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

        self.base = self.commit("docs/TOOLS.md", "tool guide")
        self.git("update-index", "--chmod=+x", "docs/TOOLS.md")
        self.git("commit", "-qm", "executable guide")
        raw = self.git("diff", "--raw", "-z", self.base, "HEAD").split("\0")
        self.assertEqual(raw[0].split()[:2], [":100644", "100755"])
        self.assertEqual(raw[0].split()[-1], "M")
        self.assertTrue(all(self.receipt()["recommended"].values()))
        self.assertIn("mode change, executable addition", self.receipt()["reason"])

    def test_safe_document_replaced_by_symlink_forces_full_union(self):
        self.base = self.commit("docs/TOOLS.md", "regular guide")
        result = subprocess.run(["git", "-C", str(self.root), "hash-object", "-w", "--stdin"],
                                input=b"../AGENTS.md", stdout=subprocess.PIPE, check=True)
        self.git("update-index", "--cacheinfo", f"120000,{result.stdout.decode().strip()},docs/TOOLS.md")
        self.git("commit", "-qm", "symlink guide")
        self.assertTrue(all(self.receipt()["recommended"].values()))

    def executable_base(self, path):
        # Index modes make the fixture portable to hosts without executable bits.
        # Preserve the explicit mode when commit() stages the next content edit.
        self.git("config", "core.fileMode", "false")
        self.commit(path, "before")
        self.git("update-index", "--chmod=+x", path)
        self.git("commit", "-qm", "existing executable")
        self.base = self.git("rev-parse", "HEAD")

    def test_executable_content_change_uses_path_scope_and_keeps_shadow_gates(self):
        for path, expected in (
                ("prototypes/stage0/three/build.sh", dict(production=False, prototype=True, site=False)),
                ("site/build.sh", dict(production=False, prototype=False, site=True)),
                ("app/export.sh", dict(production=True, prototype=True, site=True))):
            with self.subTest(path=path):
                self.executable_base(path)
                sha = self.commit(path, "after")
                raw = self.git("diff", "--raw", "-z", self.base, sha).split("\0")
                self.assertEqual(raw[0].split()[:2], [":100755", "100755"])
                self.assertEqual(raw[0].split()[-1], "M")
                self.assertEqual(raw[1:], [path, ""])
                receipt = self.receipt(sha)
                self.assertEqual(receipt["reason"], "changed paths")
                self.assertEqual(receipt["recommended"], expected)
                self.assertEqual(receipt["paths"], [path])
                for job in (*policy.PRODUCTION, "three", "export"):
                    self.assertTrue(receipt["required"][job], job)
                self.assertEqual(receipt["required"]["site"], expected["site"])
                self.validate(receipt)
                for field, value in (("base", sha), ("reason", "empty comparison"),
                                     ("required", {**receipt["required"], "app": False})):
                    changed = copy.deepcopy(receipt)
                    changed[field] = value
                    with self.subTest(field=field), self.assertRaises(ValueError):
                        self.validate(changed)

    def test_added_executable_and_removed_executable_mode_keep_full_scope(self):
        path = "prototypes/stage0/three/build.sh"
        self.git("config", "core.fileMode", "false")
        file = self.root / path
        file.parent.mkdir(parents=True)
        file.write_text("build", encoding="utf-8")
        self.git("add", "--", path)
        self.git("update-index", "--chmod=+x", path)
        self.git("commit", "-qm", "added executable")
        self.assertTrue(all(self.receipt()["recommended"].values()))
        self.assertIn("mode change, executable addition", self.receipt()["reason"])
        self.base = self.git("rev-parse", "HEAD")
        self.git("update-index", "--chmod=-x", path)
        self.git("commit", "-qm", "removed executable mode")
        self.assertTrue(all(self.receipt()["recommended"].values()))
        self.assertIn("mode change, executable addition", self.receipt()["reason"])

    def test_executable_replaced_by_gitlink_keeps_full_scope(self):
        path = "prototypes/stage0/three/build.sh"
        self.executable_base(path)
        self.git("update-index", "--cacheinfo", f"160000,{self.base},{path}")
        self.git("commit", "-qm", "gitlink replaces executable")
        self.assertTrue(all(self.receipt()["recommended"].values()))

    def test_later_executable_change_cannot_override_earlier_deletion(self):
        deleted = "docs/TOOLS.md"
        executable = "prototypes/stage0/three/build.sh"
        self.commit(deleted, "guide")
        self.executable_base(executable)
        self.git("rm", "--", deleted)
        sha = self.commit(executable, "after")
        raw = self.git("diff", "--raw", "-z", self.base, sha).split("\0")
        self.assertEqual(raw[1::2], [deleted, executable])
        self.assertEqual(raw[0].split()[-1], "D")
        self.assertEqual(raw[2].split()[:2], [":100755", "100755"])
        self.assertEqual(raw[2].split()[-1], "M")
        self.assertTrue(all(self.receipt(sha)["recommended"].values()))

    def test_pr_executable_content_change_recomputes_against_merge_parents(self):
        path = "prototypes/stage0/three/build.sh"
        self.executable_base(path)
        original = self.git("branch", "--show-current")
        self.git("checkout", "-qb", "fixture-executable")
        head = self.commit(path, "after")
        self.git("checkout", "-q", original)
        self.git("merge", "--no-ff", "-qm", "fixture merge", "fixture-executable")
        merge = self.git("rev-parse", "HEAD")
        payload = {"number": 1, "pull_request": {"base": {"sha": self.base}, "head": {"sha": head}}}
        receipt = self.receipt(merge, event="pull_request", ref="refs/pull/1/merge", payload=payload)
        self.assertEqual(receipt["reason"], "changed paths")
        self.assertEqual(receipt["recommended"], dict(production=False, prototype=True, site=False))
        self.assertTrue(all(receipt["required"][job] for job in (*policy.PRODUCTION, "three")))
        self.assertFalse(receipt["required"]["export"])
        self.assertFalse(receipt["required"]["site"])
        needs = {name: {"result": "success"} for name in ("scope", *policy.JOBS)}
        needs["site"]["result"] = needs["export"]["result"] = "skipped"
        policy.verify(receipt, needs, self.root, merge, "pull_request", "refs/pull/1/merge", payload)
        for field, value in (("head", merge), ("base", head),
                             ("required", {**receipt["required"], "visuals": False})):
            changed = copy.deepcopy(receipt)
            changed[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                policy.validate(changed, self.root, merge, "pull_request", "refs/pull/1/merge", payload)

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
                    ":100644 100644 a b M\0docs/TOOLS.md",
                    ":100755 100755 a b M\0../escape\0",
                    ":100755 100755 a b M\0docs/TOOLS.md"):
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

    def test_macos_native_gate_is_required_and_cannot_be_removed_or_skipped(self):
        receipt = self.receipt(self.commit("app/change.gd", "runtime"))
        self.assertIn("native-kernel-macos", policy.PRODUCTION)
        self.assertIs(receipt["required"].get("native-kernel-macos"), True)
        needs = {name: {"result": "success"} for name in ("scope", *policy.JOBS)}
        self.verify(receipt, needs)
        for outcome in ("failure", "cancelled", "skipped", None):
            with self.subTest(outcome=outcome), self.assertRaises(ValueError):
                broken = copy.deepcopy(needs)
                broken["native-kernel-macos"]["result"] = outcome
                self.verify(receipt, broken)
        del needs["native-kernel-macos"]
        with self.assertRaises(ValueError):
            self.verify(receipt, needs)
        receipt["required"]["native-kernel-macos"] = False
        with self.assertRaises(ValueError):
            self.validate(receipt)

    def test_workflow_calls_macos_gate_and_always_includes_it_in_required(self):
        workflow = (Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        jobs = dict(re.findall(r"^  ([\w-]+):\n(.*?)(?=^  [\w-]+:|\Z)", workflow, re.M | re.S))
        gate = jobs["native-kernel-macos"]
        self.assertRegex(gate, r"(?m)^    needs: scope$")
        self.assertRegex(gate, r"(?m)^    if: needs\.scope\.outputs\.app == 'true'$")
        self.assertRegex(gate, r"(?m)^    uses: \./\.github/workflows/native-macos\.yml$")
        self.assertNotRegex(gate, r"(?m)^\s*continue-on-error:")
        required = jobs["required"]
        self.assertRegex(required, r"(?m)^    if: always\(\)$")
        needs = re.search(r"(?m)^    needs: \[([^\]]+)\]$", required)
        self.assertIsNotNone(needs)
        self.assertIn("native-kernel-macos", [name.strip() for name in needs.group(1).split(",")])

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
