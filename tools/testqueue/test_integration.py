"""Boundaries between the existing checked API and admitted focused scripts."""
from pathlib import Path
import unittest
from unittest.mock import patch

from tools.testqueue import integration


class CheckedAdmissionTests(unittest.TestCase):
    def test_second_session_cannot_queue_behind_its_own_live_client(self):
        with patch.dict("os.environ", {"OPENRC_TESTQUEUE_HANDLE": "owned:secret"}), patch.object(integration, "rpc", return_value={"state": "RUNNING"}), patch.object(integration, "submit") as submit:
            with self.assertRaisesRegex(ValueError, "already owns"):
                integration.open_debug([], Path.cwd())
        submit.assert_not_called()

    def run_checked(self, command):
        return integration.checked(command, timeout=90, required=["complete"], max_log_bytes=4096,
                                   warnings_as_errors=True, label="fixture")

    def test_focused_api_preserves_checked_verdict_and_constraints(self):
        engine = str(Path("Godot.exe").resolve())
        source = Path("fixture/app").resolve()
        report = {"ok": True, "report": "isolated/report.json"}
        with patch.object(integration, "rpc", return_value={"engine": {"path": engine}}), patch.object(integration, "submit", return_value={"job": "owned"}) as submit, patch.object(integration, "wait", return_value={"outcome": "PASSED", "runner_verdict": {"checked": report}}):
            result = self.run_checked([engine, "--headless", "--path", str(source), "--script", "res://tests/test_simulation.gd"])
        self.assertEqual(result, report)
        self.assertEqual(submit.call_args.args[2], source.parent)
        options = submit.call_args.args[1]
        self.assertTrue(options["headless"])
        self.assertEqual(options["settings"]["max_log_bytes"], 4096)
        self.assertTrue(options["settings"]["warnings_as_errors"])

    def test_external_app_inputs_are_rejected_before_submission(self):
        engine = str(Path("Godot.exe").resolve())
        with patch.object(integration, "rpc", return_value={"engine": {"path": engine}}), patch.object(integration, "submit") as submit:
            with self.assertRaises(ValueError):
                self.run_checked([engine, "--path", "app", "--", "--headless"])
        submit.assert_not_called()

    def test_successful_runner_cannot_hide_failed_cleanup_or_collection(self):
        engine = str(Path("Godot.exe").resolve())
        with patch.object(integration, "rpc", return_value={"engine": {"path": engine}}), patch.object(integration, "submit", return_value={"job": "owned"}), patch.object(integration, "wait", return_value={"outcome": "INFRA_FAILED", "runner_verdict": {"checked": {"ok": True}}}):
            with self.assertRaisesRegex(ValueError, "orchestration outcome"):
                self.run_checked([engine, "--headless", "--path", "app", "--script", "res://tests/test_simulation.gd"])


if __name__ == "__main__":
    unittest.main()
