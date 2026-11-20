"""Legacy receipts release a host only with nonexecution proof (or operator confirmation)."""
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

from tools.testqueue import pool as pool_module
from tools.testqueue.pool import Pool, RemoteRefusal


class PoolReconcileTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-reconcile-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        config = root / "config.json"
        config.write_text(json.dumps({"state_root": str(root / "pool"), "hosts": [
            {"id": "windows", "local": True},
            {"id": "mac", "ssh": "mac", "python": "python3", "root": "/r", "agent": "/a", "engine": "/e"}]}))
        self.pool = Pool(config)
        (self.pool.root / "jobs").mkdir(parents=True)

    def receipt(self, identifier, host, state="NOT_DISPATCHED", **extra):
        value = {"request_id": identifier, "host": host, "state": state, "created": 1.0, **extra}
        (self.pool.root / "jobs" / (identifier + ".json")).write_text(json.dumps(value))

    def stored(self, identifier):
        return json.loads((self.pool.root / "jobs" / (identifier + ".json")).read_text())

    def busy(self):
        return {item["id"]: item["busy"] for item in self.pool._reserve([{"id": "windows", "busy": False},
                                                                         {"id": "mac", "busy": False}])}

    def test_local_tombstone_releases_the_host_and_status_stays_final(self):
        self.receipt("local1", "windows", request={"request_id": "local1", "request_secret": "s"})
        self.assertTrue(self.busy()["windows"])
        with patch.object(pool_module, "rpc", return_value={"canceled": True}) as rpc:
            result = self.pool.reconcile("local1")
        rpc.assert_called_once_with("cancel_submission", request_id="local1", request_secret="s")
        self.assertEqual((result["state"], result["outcome"]), ("FINISHED", "NOT_DISPATCHED"))
        self.assertEqual(self.stored("local1")["state"], "CANCELED_BEFORE_DISPATCH")
        self.assertFalse(self.busy()["windows"])
        with patch.object(pool_module, "rpc", side_effect=AssertionError("no authority call")):
            self.assertEqual(self.pool.status("local1")["outcome"], "NOT_DISPATCHED")

    def test_local_request_that_was_accepted_is_never_released(self):
        self.receipt("local2", "windows", request={"request_id": "local2", "request_secret": "s"})
        with patch.object(pool_module, "rpc", return_value={"canceled": True, "job": "j1"}), \
                self.assertRaisesRegex(ValueError, "accepted"):
            self.pool.reconcile("local2")
        self.assertEqual(self.stored("local2")["state"], "SUBMISSION_UNCONFIRMED")  # still reserving
        self.receipt("local3", "windows")
        with self.assertRaisesRegex(ValueError, "no request credential"):
            self.pool.reconcile("local3")

    def test_remote_absence_needs_operator_confirmation_and_presence_is_refused(self):
        self.receipt("remote1", "mac")
        absent = RemoteRefusal("request not found", "NOT_FOUND")
        with patch.object(self.pool, "remote", side_effect=absent):
            with self.assertRaisesRegex(ValueError, "operator-confirm"):
                self.pool.reconcile("remote1")
            self.assertTrue(self.busy()["mac"])
            self.assertEqual(self.pool.reconcile("remote1", operator_confirm=True)["outcome"], "NOT_DISPATCHED")
        self.assertFalse(self.busy()["mac"])
        self.assertEqual(self.stored("remote1")["state"], "OPERATOR_RECONCILED_ABSENT")
        self.receipt("remote2", "mac")
        with patch.object(self.pool, "remote", return_value={"state": "RUNNING"}), \
                self.assertRaisesRegex(ValueError, "knows this request"):
            self.pool.reconcile("remote2", operator_confirm=True)
        with patch.object(self.pool, "remote", side_effect=RuntimeError("ssh: connection refused")), \
                self.assertRaisesRegex(ValueError, "absence was not observed"):
            self.pool.reconcile("remote2", operator_confirm=True)
        self.assertEqual(self.stored("remote2")["state"], "SUBMISSION_UNCONFIRMED")  # still reserving
        self.receipt("done1", "mac", state="SUBMITTED")
        with self.assertRaisesRegex(ValueError, "not reconcilable"):
            self.pool.reconcile("done1", operator_confirm=True)


class PoolCircuitTests(PoolReconcileTests):
    def finished(self, identifier, host, outcome, created, source="src", **status):
        self.receipt(identifier, host, state="SUBMITTED", created=time.time() - 100 + created, source_digest=source,
                     last_status={"state": "FINISHED", "outcome": outcome, **status})

    def circuit(self, source="src"):
        return {item["id"]: item.get("busy_reason") for item in self.pool._circuit(
            [{"id": "windows", "busy": False}, {"id": "mac", "busy": False}], source)}

    def test_consecutive_infra_failures_open_only_that_host_and_source(self):
        self.finished("a1", "mac", "PASSED", 1)
        self.finished("a2", "mac", "INFRA_FAILED", 2)
        self.assertIsNone(self.circuit()["mac"])
        self.finished("a3", "mac", "INFRA_FAILED", 3)
        self.finished("w1", "windows", "INFRA_FAILED", 3)
        reasons = self.circuit()
        self.assertIn("CIRCUIT_OPEN", reasons["mac"])
        self.assertIsNone(reasons["windows"])
        self.assertIsNone(self.circuit(source="other")["mac"])
        self.finished("a4", "mac", "TEST_FAILED", 4)  # a real test result closes it
        self.assertIsNone(self.circuit()["mac"])

    def test_host_transient_refusals_do_not_open_the_circuit(self):
        """TQ-05-F0.4: the host's own state says nothing about the source."""
        self.finished("t1", "mac", "INFRA_FAILED", 1, error="Refused: external Godot process detected; it was not touched")
        self.finished("t2", "mac", "INFRA_FAILED", 2, error="Refused: insufficient disk for archive and reserve")
        self.assertIsNone(self.circuit()["mac"])

    def test_open_circuit_half_opens_after_the_retry_interval(self):
        self.finished("o1", "mac", "INFRA_FAILED", 1)
        self.finished("o2", "mac", "INFRA_FAILED", 2)
        self.assertIn("CIRCUIT_OPEN", self.circuit()["mac"])
        with patch.object(self.pool, "CIRCUIT_RETRY_SECONDS", 50):
            self.assertIsNone(self.circuit()["mac"])  # newest failure is ~98 s old: one more attempt may run


if __name__ == "__main__":
    unittest.main()
