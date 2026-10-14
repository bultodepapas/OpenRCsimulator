#!/usr/bin/env python3
"""Regression tests for tools/ci/scope.py using disposable local Git repositories."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Optional


SCOPE_SCRIPT = Path(__file__).with_name("scope.py").resolve()


class ScopeHelperTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        self._git("init", "-q")
        self._git("config", "user.name", "CI Scope Test")
        self._git("config", "user.email", "ci-scope@example.invalid")
        self._write("README.md", "baseline\n")
        self.base = self._commit("baseline")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _git(self, *args: str, cwd: Optional[Path] = None) -> str:
        result = subprocess.run(
            ["git", *args],
            cwd=cwd or self.repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return result.stdout.strip()

    def _write(self, path: str, content: str = "change\n") -> None:
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def _commit(self, message: str) -> str:
        self._git("add", "--all")
        self._git("commit", "-q", "-m", message)
        return self._git("rev-parse", "HEAD")

    def _run_scope(
        self,
        *,
        event: str = "push",
        ref: str = "refs/heads/main",
        base: Optional[str] = None,
        head: Optional[str] = None,
        cwd: Optional[Path] = None,
    ) -> subprocess.CompletedProcess:
        argv = [sys.executable, str(SCOPE_SCRIPT), "--event", event, "--ref", ref]
        if base is not None:
            argv.extend(["--base", base])
        if head is not None:
            argv.extend(["--head", head])
        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        return subprocess.run(
            argv,
            cwd=cwd or self.repo,
            env=env,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

    def _assert_decision(self, expected: str, **kwargs: object) -> None:
        result = self._run_scope(**kwargs)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, expected + "\n")
        self.assertEqual(result.stderr, "")

    def test_docs_only_diff_including_spaces_skips_app(self) -> None:
        self._write("research notes/flight guide.md")
        head = self._commit("docs only")
        self._assert_decision("app=false", base=self.base, head=head)

    def test_pull_request_docs_only_skips_app(self) -> None:
        self._write("docs/pr guide.md")
        head = self._commit("pull request docs")
        self._assert_decision(
            "app=false", event="pull_request", base=self.base, head=head,
        )

    def test_empty_diff_skips_app(self) -> None:
        self._assert_decision("app=false", base=self.base, head=self.base)

    def test_runtime_change_runs_app(self) -> None:
        self._write("app/sim/flight session.gd")
        head = self._commit("runtime")
        self._assert_decision("app=true", base=self.base, head=head)

    def test_workflow_change_runs_app(self) -> None:
        self._write(".github/workflows/ci.yml")
        head = self._commit("workflow")
        self._assert_decision("app=true", base=self.base, head=head)

    def test_mixed_docs_and_runtime_runs_app(self) -> None:
        self._write("docs/release notes.md")
        self._write("app/main.gd")
        head = self._commit("mixed")
        self._assert_decision("app=true", base=self.base, head=head)

    def test_code_renamed_to_markdown_still_runs_app(self) -> None:
        self._write("app/sim/trace.gd")
        base = self._commit("runtime source")
        (self.repo / "docs").mkdir()
        self._git("mv", "app/sim/trace.gd", "docs/trace.md")
        head = self._commit("move source into docs")
        self._assert_decision("app=true", base=base, head=head)

    def test_non_markdown_suffix_runs_app(self) -> None:
        self._write("docs/notes.md.bak")
        head = self._commit("not a markdown suffix")
        self._assert_decision("app=true", base=self.base, head=head)

    def test_tag_and_manual_events_force_app_without_git_access(self) -> None:
        with tempfile.TemporaryDirectory() as empty_dir:
            cwd = Path(empty_dir)
            self._assert_decision(
                "app=true", event="push", ref="refs/tags/v9.9.9",
                base="invalid-base", head="invalid-head", cwd=cwd,
            )
            self._assert_decision(
                "app=true", event="workflow_dispatch", ref="refs/heads/main",
                base="invalid-base", head="invalid-head", cwd=cwd,
            )

    def test_unsupported_event_forces_app_without_git_access(self) -> None:
        with tempfile.TemporaryDirectory() as empty_dir:
            self._assert_decision(
                "app=true", event="schedule", base="invalid-base", head="invalid-head",
                cwd=Path(empty_dir),
            )

    def test_missing_or_all_zero_base_forces_app_without_git_access(self) -> None:
        with tempfile.TemporaryDirectory() as empty_dir:
            cwd = Path(empty_dir)
            self._assert_decision("app=true", event="push", head="invalid-head", cwd=cwd)
            self._assert_decision(
                "app=true", event="push", base="0" * 40, head="invalid-head", cwd=cwd,
            )

    def test_missing_head_forces_app_without_git_access(self) -> None:
        with tempfile.TemporaryDirectory() as empty_dir:
            self._assert_decision(
                "app=true", event="push", base=self.base, cwd=Path(empty_dir),
            )

    def test_invalid_revisions_fail_nonzero_without_scope_output(self) -> None:
        valid_head = self.base
        for base, head in [("missing-base-revision", valid_head), (self.base, "missing-head-revision")]:
            with self.subTest(base=base, head=head):
                result = self._run_scope(base=base, head=head)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("CI scope check failed:", result.stderr)

    def test_git_failure_fails_nonzero_without_scope_output(self) -> None:
        with tempfile.TemporaryDirectory() as empty_dir:
            result = self._run_scope(base=self.base, head=self.base, cwd=Path(empty_dir))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("CI scope check failed:", result.stderr)

    def test_revision_option_injection_fails_nonzero(self) -> None:
        result = self._run_scope(base="--help", head=self.base)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
