"""TQ-07-A10: a worker restart settles what is already proved and reports the rest.

Before this, opening the store turned every in-flight attempt into UNKNOWN and
any UNKNOWN stopped all admission until a person reconciled it or rebooted, while
``hosts`` still answered READY.
"""
from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

from tools.testqueue.store import Store
from tools.testqueue.worker import Worker


class RestartRecoveryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-restart-")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.root = self.base / "authority"
        self.root.mkdir()
        (self.base / "repo").mkdir()

    def test_restart_settles_only_proved_attempts_and_reports_the_rest(self):
        store = Store(self.root)
        jobs = {name: store.submit(name, {"owner": name, "preset": "checked"}, "s" * 32)["job"]
                for name in ("prelaunch", "admission", "launched", "rebooted")}
        prelaunch = store.allocate(jobs["prelaunch"], {"headless": 1}, {"headless": 1})
        admission = store.allocate(jobs["admission"], {"rendered": 1}, {"rendered": 1})
        # A checked attempt waiting for an external simulator journals DISPATCHING twice.
        store.update(jobs["admission"], admission, "DISPATCHING", {"stage": "admission", "reason_code": "EXTERNAL_SIMULATOR"})
        launched = store.allocate(jobs["launched"], {"cpu": 1}, {"cpu": 1})
        # The launch fence: RUNNING with CREATION_UNCERTAIN precedes process creation.
        store.update(jobs["launched"], launched, "RUNNING", {"launch": "CREATION_UNCERTAIN"})
        rebooted = store.allocate(jobs["rebooted"], {"memory": 1}, {"memory": 1})
        store.update(jobs["rebooted"], rebooted, "RUNNING",
                     {"launch": "CREATED_OWNED", "process": {"pid": 5, "host": "h", "boot": "before"}})
        store.db.close()

        worker = Worker(self.root, self.base / "repo", Path(sys.executable), fixture=True)
        self.addCleanup(worker.singleton.close)
        self.addCleanup(worker.store.db.close)
        self.assertEqual(sorted(worker.quarantined_attempts()), sorted([prelaunch, admission, launched, rebooted]))
        with mock.patch("tools.testqueue.processes.confirm_stopped",
                        side_effect=lambda identity: identity.get("boot") == "before"):
            settled = {item["attempt"]: item["proof"] for item in worker.recover_after_restart()}

        self.assertEqual(set(settled), {prelaunch, admission, rebooted})
        self.assertIn("launch fence", settled[prelaunch])
        self.assertIn("rebooted", settled[rebooted])
        for name in ("prelaunch", "admission"):
            status = worker.store.get(jobs[name])
            self.assertEqual((status["state"], status["launch"], status["nonlaunch"], status["reason_code"]),
                             ("FINISHED", "NOT_CREATED", "CONFIRMED", "WORKER_RESTART"))
        self.assertEqual(worker.store.get(jobs["launched"])["state"], "UNKNOWN")  # creation uncertain: stays
        self.assertEqual(worker.quarantined_attempts(), [launched])
        hosts = worker._hosts({"available": False})
        self.assertEqual((hosts["condition"], hosts["quarantined_attempts"]), ("QUARANTINED", [launched]))
        claims = {row["attempt"] for row in worker.store.db.execute("SELECT attempt FROM claims")}
        self.assertEqual(claims, {launched})  # proved attempts released their resources

    def test_an_unreadable_launch_event_keeps_the_quarantine(self):
        store = Store(self.root)
        job = store.submit("odd", {"owner": "odd"}, "s" * 32)["job"]
        attempt = store.allocate(job, {"headless": 1}, {"headless": 1})
        with store.db:
            store.db.execute("INSERT INTO events(at,job,event,data) VALUES(0,?, 'RUNNING', '{broken')", (job,))
        store.db.close()
        worker = Worker(self.root, self.base / "repo", Path(sys.executable), fixture=True)
        self.addCleanup(worker.singleton.close)
        self.addCleanup(worker.store.db.close)
        self.assertEqual(worker.recover_after_restart(), [])
        self.assertEqual(worker.quarantined_attempts(), [attempt])


if __name__ == "__main__":
    unittest.main()
