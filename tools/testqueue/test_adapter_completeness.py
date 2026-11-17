"""Regression checks for the checked adapter's completion evidence.

Runs without Godot or a queue: request I/O and the checked runner are mocked.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from tools.godot import run_checked

from tools.testqueue import adapter


class CheckedCompletionTests(unittest.TestCase):
    def adapter_result(self, runner_results, *, need_import):
        request = {
            "preset": "checked",
            "options": {"headless": True, "argv": [], "script": "res://tests/test_sample.gd",
                        "timeout": 90, "require": ["COMPLETE"]},
        }
        manifest = {"import_files": [] if need_import else ["cached.import"]}

        def read_file(path, *args, **kwargs):
            if path.name == "request.json":
                return json.dumps(request)
            if path.name == "manifest.json":
                return json.dumps(manifest)
            raise AssertionError(f"unexpected file read: {path}")

        with patch.object(Path, "read_text", read_file), \
                patch.object(adapter, "inherited", return_value=True), \
                patch.object(adapter, "prepare_history"), \
                patch.object(adapter, "write_json") as save, \
                patch.object(run_checked, "run_checked", side_effect=runner_results) as runner, \
                patch.dict(os.environ, {"OPENRC_GODOT": "/fixture/godot"}):
            code = adapter.main(Path("/owned-attempt"))
        save.assert_called_once()
        self.assertEqual(save.call_args.args[0], Path("/owned-attempt/verdict.json"))
        return code, save.call_args.args[1], runner.call_args_list

    def test_failed_or_incomplete_import_is_not_a_completed_check(self):
        reports = (
            {"ok": False, "complete": True, "reason": "engine_error", "log": "/imports/error.log"},
            {"ok": False, "complete": False, "reason": "timeout", "log": "/imports/timeout.log"},
            {"ok": True, "complete": False, "reason": "inconsistent", "log": "/imports/partial.log"},
        )
        for imported in reports:
            with self.subTest(imported=imported):
                code, verdict, calls = self.adapter_result([imported], need_import=True)
                self.assertNotEqual(code, 0)
                self.assertIs(verdict["ok"], False)
                self.assertIs(verdict["complete"], False)
                self.assertEqual(verdict["import_verdict"], imported)
                self.assertNotIn("checked", verdict)
                self.assertEqual(len(calls), 1)
                self.assertIn("--import", calls[0].args[0])

    def test_interrupted_check_remains_incomplete_and_retains_report(self):
        for reason in ("timeout", "log_limit", "runner_error"):
            with self.subTest(reason=reason):
                checked = {"ok": False, "complete": False, "reason": reason, "log": "/checks/partial.log"}
                code, verdict, calls = self.adapter_result([checked], need_import=False)
                self.assertNotEqual(code, 0)
                self.assertIs(verdict["ok"], False)
                self.assertIs(verdict["complete"], False)
                self.assertEqual(verdict["checked"], checked)
                self.assertEqual(len(calls), 1)
                self.assertIn("--script", calls[0].args[0])

    def test_complete_failed_check_remains_a_completed_failure(self):
        imported = {"ok": True, "complete": True, "reason": "passed"}
        checked = {"ok": False, "complete": True, "reason": "missing_required_text"}
        code, verdict, calls = self.adapter_result([imported, checked], need_import=True)
        self.assertNotEqual(code, 0)
        self.assertIs(verdict["ok"], False)
        self.assertIs(verdict["complete"], True)
        self.assertEqual(verdict["checked"], checked)
        self.assertEqual(len(calls), 2)
        self.assertIn("--import", calls[0].args[0])
        self.assertIn("--script", calls[1].args[0])

    def test_complete_pass_is_unchanged(self):
        checked = {"ok": True, "complete": True, "reason": "passed"}
        code, verdict, calls = self.adapter_result([checked], need_import=False)
        self.assertEqual(code, 0)
        self.assertIs(verdict["ok"], True)
        self.assertIs(verdict["complete"], True)
        self.assertEqual(verdict["checked"], checked)
        self.assertEqual(len(calls), 1)

    def test_inconsistent_or_malformed_check_cannot_be_reported_as_passed(self):
        reports = (
            {"ok": True, "complete": False},
            {"ok": True},
            {"ok": "yes", "complete": True},
        )
        for checked in reports:
            with self.subTest(checked=checked):
                code, verdict, _ = self.adapter_result([checked], need_import=False)
                self.assertNotEqual(code, 0)
                self.assertIs(verdict["ok"], False)
                self.assertIs(verdict["complete"], False)
                self.assertEqual(verdict["checked"], checked)


if __name__ == "__main__":
    unittest.main()
