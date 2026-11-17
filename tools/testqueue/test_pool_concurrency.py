"""Concurrent pool clients must preserve a single job's durable receipt."""
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

from tools.testqueue.test_pool import verified_fixture

from tools.testqueue.pool import Pool


class PoolConcurrencyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-pool-concurrency-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        config = self.root / "config.json"
        config.write_text(json.dumps({"state_root": str(self.root / "state"),
                                      "hosts": [{"id": "windows", "local": True}]}))
        self.pool = Pool(config)
        self.snapshot = self.root / "snapshot"
        self.snapshot.mkdir()
        (self.snapshot / "manifest.json").write_text(json.dumps({
            "source_root": str(self.root), "source_digest": "fixture", "files": {}}))

    def _thread(self, function):
        result = {}
        started = threading.Event()

        def run():
            started.set()
            try:
                result["value"] = function()
            except BaseException as error:
                result["error"] = error

        thread = threading.Thread(target=run, daemon=True)
        thread.start()
        self.assertTrue(started.wait(5), "client thread did not start")
        return thread, result

    def _join(self, thread, result):
        thread.join(10)
        self.assertFalse(thread.is_alive(), "pool operation did not finish")
        if "error" in result:
            raise result["error"]
        return result["value"]

    def test_status_waits_for_submission_receipt_to_be_finalized(self):
        submitting = threading.Event()
        release = threading.Event()
        queried = threading.Event()

        def rpc(operation, **request):
            if operation == "submit":
                submitting.set()
                if not release.wait(5):
                    raise RuntimeError("fixture timed out")
                return {"job": "local-job", "handle": "local-job:owner"}
            if operation == "recover":
                queried.set()
                return {"job": "local-job"}
            if operation == "status":
                return {"state": "RUNNING", "payload": {"manifest": {"source_digest": "fixture"}}}
            raise AssertionError(operation)

        with patch("tools.testqueue.pool.verify", side_effect=verified_fixture), \
                patch.object(self.pool, "probe", return_value=[]), \
                patch("tools.testqueue.pool.plan", return_value={"selected": "windows"}), \
                patch("tools.testqueue.pool.rpc", side_effect=rpc):
            submit_thread, submitted = self._thread(lambda: self.pool.submit(
                self.snapshot, "res://tests/test_math3d.gd", request_id="samejob"))
            self.assertTrue(submitting.wait(5), "submission did not reach the authority")
            status_thread, observed = self._thread(lambda: self.pool.status("samejob"))
            try:
                self.assertFalse(queried.wait(0.3), "status raced the unfinished submission")
            finally:
                release.set()
                submit_thread.join(10)
                status_thread.join(10)
            self._join(submit_thread, submitted)
            self.assertEqual(self._join(status_thread, observed)["state"], "RUNNING")
        receipt = json.loads((self.pool.root / "jobs" / "samejob.json").read_text())
        self.assertEqual(receipt["state"], "SUBMITTED")
        self.assertEqual(receipt["accepted"]["job"], "local-job")
        self.assertEqual(receipt["last_status"]["state"], "RUNNING")

    def test_status_waits_for_recovery_and_recovery_does_not_deadlock(self):
        path = self.pool.root / "jobs" / "samejob.json"
        path.parent.mkdir()
        path.write_text(json.dumps({"host": "windows", "state": "SUBMISSION_UNCONFIRMED",
                                    "request": {"request_id": "samejob", "request_secret": "s" * 32}}))
        recovering = threading.Event()
        release = threading.Event()
        queried = threading.Event()
        identity_calls = []

        def rpc(operation, **request):
            if operation == "recover":
                identity_calls.append(request["request_id"])
                if len(identity_calls) == 1:
                    recovering.set()
                    if not release.wait(5):
                        raise RuntimeError("fixture timed out")
                else:
                    queried.set()
                return {"job": "local-job", "handle": "local-job:owner"}
            if operation == "status":
                return {"state": "RUNNING"}
            raise AssertionError(operation)

        with patch("tools.testqueue.pool.rpc", side_effect=rpc):
            recover_thread, recovered = self._thread(lambda: self.pool.recover("samejob"))
            self.assertTrue(recovering.wait(5), "recovery did not reach the authority")
            status_thread, observed = self._thread(lambda: self.pool.status("samejob"))
            try:
                self.assertFalse(queried.wait(0.3), "status raced the unfinished recovery")
            finally:
                release.set()
                recover_thread.join(10)
                status_thread.join(10)
            self.assertEqual(self._join(recover_thread, recovered)["state"], "RUNNING")
            self.assertEqual(self._join(status_thread, observed)["state"], "RUNNING")
        receipt = json.loads(path.read_text())
        self.assertEqual(receipt["state"], "SUBMITTED")
        self.assertEqual(receipt["accepted"]["job"], "local-job")
        self.assertEqual(receipt["last_status"]["state"], "RUNNING")


if __name__ == "__main__":
    unittest.main()
