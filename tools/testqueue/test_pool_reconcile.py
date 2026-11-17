"""Legacy receipts release a host only with nonexecution proof (or operator confirmation)."""
import json
from pathlib import Path
import tempfile
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


if __name__ == "__main__":
    unittest.main()
