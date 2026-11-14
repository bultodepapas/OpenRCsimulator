"""Boundaries between the existing checked API and admitted focused scripts."""
import contextlib
import io
import json
import os
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

from tools.testqueue import common, integration, presets


class CheckedAdmissionTests(unittest.TestCase):
    def test_repeated_recovery_failure_keeps_original_receipt_and_never_submits(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            request = dict(preset="debug-session", source=str(root), options=presets.validate("debug-session", {"argv": []}),
                           request_id="original", request_secret="s" * 32)
            receipt = common.submission_receipt(root, request)
            with patch.dict(os.environ, {"OPENRC_TESTQUEUE_SUBMISSION": str(receipt)}, clear=True), \
                    patch.object(integration, "state_root", return_value=root), \
                    patch.object(integration, "rpc", side_effect=RuntimeError("lost recovery reply")) as rpc, \
                    patch.object(integration, "submit") as submit:
                for _ in range(2):
                    with self.assertRaisesRegex(RuntimeError, "lost recovery reply"):
                        integration.open_debug([], root)
                    self.assertEqual(os.environ["OPENRC_TESTQUEUE_SUBMISSION"], str(receipt))
                self.assertEqual([call.args[0] for call in rpc.call_args_list], ["recover", "recover"])
                submit.assert_not_called()

    def test_research_launch_requires_both_actual_scope_and_exclusive_grant(self):
        with patch.object(common, "enabled", return_value=False), patch.object(common, "inherited") as inherited:
            common.require_exclusive("rendered")
            inherited.assert_not_called()
        for values in ([False], [True, False]):
            with self.subTest(values=values), patch.object(common, "enabled", return_value=True), \
                    patch.object(common, "inherited", side_effect=values):
                with self.assertRaisesRegex(ValueError, "exclusive inherited attempt"):
                    common.require_exclusive("rendered")
        with patch.object(common, "enabled", return_value=True), patch.object(common, "inherited", return_value=True) as inherited:
            common.require_exclusive("rendered")
            self.assertEqual([call.args[0] for call in inherited.call_args_list], ["rendered", "performance"])
        with patch.object(common, "enabled", return_value=True), patch.object(common, "inherited", side_effect=RuntimeError("worker unavailable")):
            with self.assertRaisesRegex(RuntimeError, "worker unavailable"):
                common.require_exclusive("headless")

    def test_second_session_cannot_queue_behind_its_own_live_client(self):
        with patch.dict("os.environ", {"OPENRC_TESTQUEUE_HANDLE": "owned:secret"}), patch.object(integration, "rpc", return_value={"state": "RUNNING"}), patch.object(integration, "submit") as submit:
            with self.assertRaisesRegex(ValueError, "already owns"):
                integration.open_debug([], Path.cwd())
        submit.assert_not_called()

    def test_pending_session_is_owned_until_canceled_and_cannot_be_duplicated(self):
        accepted = {"job": "owned", "handle": "owned:secret"}
        pending = {"state": "QUEUED", "reason": "RESOURCE_BUSY"}
        finished = {"id": "owned", "state": "FINISHED", "cleanup": "CONFIRMED"}
        output, diagnostics = io.StringIO(), io.StringIO()
        with patch.dict(os.environ, {"OPENRC_DEBUG_BRIDGE": "12345"}, clear=True), \
                patch.object(integration, "submit", return_value=accepted) as submit, \
                patch.object(integration, "wait", side_effect=[pending, finished]) as wait, \
                patch.object(integration, "rpc", side_effect=[pending, {"id": "owned"}]) as rpc, \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(diagnostics):
            self.assertEqual(integration.open_debug([], Path.cwd(), wait_timeout=0), 0)
            self.assertEqual(os.environ["OPENRC_TESTQUEUE_HANDLE"], accepted["handle"])
            self.assertNotIn("OPENRC_DEBUG_BRIDGE", os.environ)
            with self.assertRaisesRegex(ValueError, "already owns"):
                integration.open_debug([], Path.cwd())
            self.assertEqual(integration.close_debug(), 0)
        launch_result = json.loads(output.getvalue().splitlines()[0])
        self.assertEqual(json.loads(diagnostics.getvalue())["handle"], accepted["handle"])
        self.assertTrue(launch_result["ok"])
        self.assertEqual(launch_result["state"], "QUEUED")
        self.assertFalse(launch_result["ready"])
        self.assertEqual(launch_result["handle"], accepted["handle"])
        submit.assert_called_once()
        self.assertEqual(wait.call_args_list[0].kwargs, {"timeout": 0, "ready": True})
        self.assertEqual(rpc.call_args_list[1].args, ("cancel",))
        self.assertEqual(rpc.call_args_list[1].kwargs, {"handle": accepted["handle"]})

    def test_session_ownership_survives_wait_failure(self):
        accepted = {"job": "owned", "handle": "owned:secret"}
        diagnostics = io.StringIO()
        with patch.dict(os.environ, {}, clear=True), patch.object(integration, "submit", return_value=accepted), \
                patch.object(integration, "wait", side_effect=RuntimeError("worker unavailable")), \
                contextlib.redirect_stderr(diagnostics):
            with self.assertRaisesRegex(RuntimeError, "worker unavailable"):
                integration.open_debug([], Path.cwd())
            self.assertEqual(os.environ["OPENRC_TESTQUEUE_HANDLE"], accepted["handle"])
        self.assertEqual(json.loads(diagnostics.getvalue())["handle"], accepted["handle"])

    def test_finished_or_unknown_session_is_not_reported_as_ready(self):
        accepted = {"job": "owned", "handle": "owned:secret"}
        for state in ("FINISHED", "UNKNOWN"):
            with self.subTest(state=state), patch.dict(os.environ, {}, clear=True), \
                    patch.object(integration, "submit", return_value=accepted), \
                    patch.object(integration, "wait", return_value={"state": state, "session": {"port": 4567}}), \
                    contextlib.redirect_stdout(io.StringIO()) as output, contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(integration.open_debug([], Path.cwd()), 1)
                self.assertNotIn("OPENRC_DEBUG_BRIDGE", os.environ)
                self.assertEqual(os.environ["OPENRC_TESTQUEUE_HANDLE"], accepted["handle"])
                self.assertFalse(json.loads(output.getvalue().splitlines()[-1])["ok"])

    def test_ready_session_and_status_keep_the_owning_handle(self):
        accepted = {"job": "owned", "handle": "owned:secret"}
        ready = {"state": "RUNNING", "session": {"port": 4567}}
        with patch.dict(os.environ, {}, clear=True), patch.object(integration, "submit", return_value=accepted), \
                patch.object(integration, "wait", return_value=ready), \
                patch.object(integration, "rpc", return_value={**ready, "payload": {"secret": "not for status"}}), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(integration.open_debug([], Path.cwd()), 0)
            self.assertEqual(os.environ["OPENRC_DEBUG_BRIDGE"], "4567")
            self.assertEqual(integration.debug_status(), {**accepted, **ready, "ready": True})

    def test_cancel_requested_session_is_not_reported_as_ready(self):
        accepted = {"job": "owned", "handle": "owned:secret"}
        stopping = {"state": "RUNNING", "session": {"port": 4567}, "canceled": 1}
        with patch.dict(os.environ, {}, clear=True), patch.object(integration, "submit", return_value=accepted), \
                patch.object(integration, "wait", return_value=stopping), \
                patch.object(integration, "rpc", return_value=stopping), \
                contextlib.redirect_stdout(io.StringIO()) as output, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(integration.open_debug([], Path.cwd()), 0)
            self.assertFalse(json.loads(output.getvalue())["ready"])
            self.assertNotIn("OPENRC_DEBUG_BRIDGE", os.environ)
            self.assertFalse(integration.debug_status()["ready"])

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
