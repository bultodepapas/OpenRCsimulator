"""Batch call boundaries distinguish safe retries from ambiguous dispatch."""
from contextlib import ExitStack
import errno
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.testqueue.test_pool import verified_fixture

from tools.testqueue import pool as transport, snapshots
from tools.testqueue.common import write_json
from tools.testqueue.pool_batch import run_batch


PASS = {"state": "FINISHED", "outcome": "PASSED", "cleanup": "CONFIRMED", "evidence": "COMPLETE"}


class SubmissionBoundaryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-submission-boundary-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.config = self.root / "config.json"
        write_json(self.config, {"state_root": str(self.root / "pool"),
                                 "hosts": [{"id": "windows", "local": True}]})
        self.pool = transport.Pool(self.config)
        self.snapshot = self.root / "snapshot"
        write_json(self.snapshot / "manifest.json", {"source_root": str(self.root),
                   "source_digest": "fixture", "files": {}})
        self.manifest = self.root / "batch.json"
        write_json(self.manifest, {"snapshot": str(self.snapshot),
                                  "jobs": [{"script": "res://tests/test_fixture.gd"}]})
        self.state = self.root / "batch-state.json"

    def run_case(self, timeout=1):
        return run_batch(self.pool, self.config, self.manifest, self.state,
                         timeout=timeout, poll_interval=0.005)

    def admitted(self):
        stack = ExitStack()
        stack.enter_context(patch("tools.testqueue.pool.verify", side_effect=verified_fixture))
        stack.enter_context(patch.object(self.pool, "probe", return_value=[]))
        stack.enter_context(patch("tools.testqueue.pool.plan", return_value={"selected": "windows"}))
        rpc = stack.enter_context(patch("tools.testqueue.pool.rpc", return_value={"job": "original"}))
        stack.enter_context(patch.object(self.pool, "status", return_value=PASS))
        stack.enter_context(patch.object(self.pool, "collect", side_effect=lambda identifier:
                           {"pool_job": identifier, "pool_outcome": "PASSED"}))
        return stack, rpc

    def test_transient_lock_failure_retries_same_id_with_backoff(self):
        original = transport.acquire_lock
        calls = []
        def acquire(path, *args, **kwargs):
            if path.name == "dispatch.lock":
                calls.append(path)
                if len(calls) == 1:
                    raise transport.PoolLockTimeout("injected transient dispatch contention")
            return original(path, *args, **kwargs)
        stack, rpc = self.admitted()
        with stack, patch.object(transport, "acquire_lock", side_effect=acquire), \
                patch("tools.testqueue.pool_batch.RETRY_INITIAL_SECONDS", 0.5):
            first = self.run_case(timeout=0.1)
            row = first["jobs"][0]
            self.assertEqual(row["phase"], "RETRY_WAIT")
            self.assertEqual(row["submission_attempts"], 1)
            rpc.assert_not_called()
            result = self.run_case(timeout=2)
        self.assertEqual(result["result"], "PASSED")
        self.assertEqual(result["jobs"][0]["request_id"], row["request_id"])
        self.assertEqual(result["jobs"][0]["submission_attempts"], 2)
        self.assertIn("transient dispatch", result["jobs"][0]["first_error"])
        self.assertEqual(rpc.call_count, 1)

    def test_preflight_io_failure_can_recover_without_execution_retry(self):
        with patch.object(snapshots, "_file_stat", side_effect=OSError(errno.EIO, "injected read failure")):
            failure = snapshots.verify(self.snapshot)
        self.assertEqual(failure["failure_kind"], "IO")
        stack, rpc = self.admitted()
        with stack, patch.object(transport, "verify", side_effect=[failure, verified_fixture(self.snapshot)]), \
                patch("tools.testqueue.pool_batch.RETRY_INITIAL_SECONDS", 0.01):
            result = self.run_case()
        self.assertEqual(result["result"], "PASSED")
        self.assertEqual(result["jobs"][0]["submission_attempts"], 2)
        self.assertEqual(rpc.call_count, 1)

    def test_invalid_input_rejects_call_without_claiming_global_cleanup(self):
        with patch.object(self.pool, "probe") as probe, patch.object(transport, "rpc") as rpc:
            result = self.run_case()
        row = result["jobs"][0]
        self.assertEqual(result["result"], "FAILED")
        self.assertEqual(row["phase"], "REJECTED")
        self.assertEqual(row["status"]["state"], "REJECTED")
        self.assertNotIn("cleanup", row["status"])
        self.assertFalse((self.pool.root / "jobs" / (row["request_id"] + ".json")).exists())
        probe.assert_not_called()
        rpc.assert_not_called()
        with patch.object(self.pool, "submit") as submit:
            repeated = self.run_case()
        submit.assert_not_called()
        self.assertEqual(repeated["jobs"][0]["first_error"], row["first_error"])

    def test_crash_at_call_boundary_with_missing_receipt_never_resubmits(self):
        with patch.object(self.pool, "submit", side_effect=SystemExit("crash after possible dispatch")):
            with self.assertRaises(SystemExit):
                self.run_case()
        saved = json.loads(self.state.read_text())
        self.assertEqual(saved["version"], 2)
        self.assertEqual(saved["jobs"][0]["phase"], "SUBMITTING")
        (self.snapshot / "manifest.json").unlink()
        with patch.object(self.pool, "submit") as submit, patch.object(transport, "rpc") as rpc:
            result = self.run_case()
        submit.assert_not_called()
        rpc.assert_not_called()
        self.assertEqual(result["jobs"][0]["phase"], "BLOCKED")
        self.assertEqual(result["jobs"][0]["request_id"], saved["jobs"][0]["request_id"])

    def test_generic_submit_error_is_not_safe_retry_or_rejection(self):
        with patch.object(self.pool, "submit", side_effect=ValueError("possibly accepted before this error")) as submit:
            first = self.run_case()
            second = self.run_case()
        submit.assert_called_once()
        self.assertEqual(first["jobs"][0]["phase"], "BLOCKED")
        self.assertEqual(second["jobs"][0]["phase"], "BLOCKED")
        self.assertIn("possibly accepted", second["jobs"][0]["first_error"])

    def test_legacy_waiting_row_is_observed_without_fresh_submission(self):
        with patch.object(self.pool, "submit", return_value={"state": "WAITING"}):
            state = self.run_case(timeout=0.02)
        state["version"] = 1
        write_json(self.state, state)
        with patch.object(self.pool, "submit") as submit:
            result = self.run_case()
        submit.assert_not_called()
        self.assertEqual(result["version"], 2)
        self.assertEqual(result["migrated_from_version"], 1)
        self.assertEqual(result["jobs"][0]["phase"], "BLOCKED")

    def test_interrupted_rejection_response_is_not_inferred_from_receipt_absence(self):
        original = self.pool.submit
        def reject_then_crash(*args, **kwargs):
            try:
                original(*args, **kwargs)
            except transport.SubmissionRejected:
                raise SystemExit("lost preflight refusal") from None
        with patch.object(self.pool, "submit", side_effect=reject_then_crash):
            with self.assertRaises(SystemExit):
                self.run_case()
        with patch.object(self.pool, "submit") as submit:
            result = self.run_case()
        submit.assert_not_called()
        self.assertEqual(result["jobs"][0]["status"]["state"], "UNKNOWN")


if __name__ == "__main__":
    unittest.main()
