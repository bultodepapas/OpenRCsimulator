"""Disk observations use the execution volume and cannot grant unknown capacity."""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from tools.testqueue import pool as pool_module, worker as worker_module
from tools.testqueue.pool_policy import plan
from tools.testqueue import test_worker as worker_fixtures


class PoolStorageCapacityTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-volume-probe-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name).resolve()
        config = root / "config.json"
        config.write_text(json.dumps({"state_root": str(root / "coordinator"),
                                      "hosts": [{"id": "local", "local": True}]}))
        self.pool = pool_module.Pool(config)
        self.current = {"platform": "windows", "claims": [], "condition": "READY", "reservation": None,
                        "engine": {"version": "fixture"}}
        self.psutil = SimpleNamespace(virtual_memory=lambda: SimpleNamespace(available=8 * 1024**3),
                                      cpu_percent=lambda **kwargs: 0)

    def probe(self):
        with patch.dict(sys.modules, {"psutil": self.psutil}), \
                patch.object(pool_module, "rpc", return_value=self.current), \
                patch.object(pool_module.shutil, "disk_usage", side_effect=AssertionError("coordinator volume queried")):
            return self.pool.probe_host(self.pool.hosts[0])

    def test_uses_reported_attempt_volume_instead_of_coordinator(self):
        self.current["storage"] = {"available": True, "path": "D:/OpenRC/attempts", "free_bytes": 123456}
        result = self.probe()
        self.assertEqual(result["free_disk_bytes"], 123456)
        self.assertEqual(result["storage"]["path"], "D:/OpenRC/attempts")

    def test_older_unavailable_and_malformed_capacity_is_ineligible(self):
        variants = [None, {}, {"available": False, "free_bytes": 10**12},
                    {"available": True, "free_bytes": None}, {"available": True, "free_bytes": True},
                    {"available": True, "free_bytes": -1}, {"available": True, "free_bytes": "10000"}]
        for storage in variants:
            with self.subTest(storage=storage):
                if storage is None:
                    self.current.pop("storage", None)
                else:
                    self.current["storage"] = storage
                result = self.probe()
                self.assertTrue(result["online"])
                self.assertIsNone(result["free_disk_bytes"])
                decision = plan({"platform": "windows", "workload": "headless", "source_bytes": 1}, [result])
                self.assertIsNone(decision["selected"])
                self.assertIn("DISK_UNKNOWN", str(decision))


class WorkerStorageCapacityTests(unittest.TestCase):
    def setUp(self):
        self.fixture = worker_fixtures.WorkerFixture(methodName="runTest")
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def test_worker_reports_attempt_volume_and_missing_directory_parent(self):
        worker = self.fixture.worker
        attempts = worker.root / "attempts"
        with patch.object(worker_module.shutil, "disk_usage", return_value=SimpleNamespace(total=1000, used=700, free=300)) as usage:
            status = self.fixture._call("hosts")
            self.assertEqual(status["storage"]["free_bytes"], 300)
            usage.assert_called_once_with(worker.root)
            attempts.mkdir()
            usage.reset_mock()
            status = self.fixture._call("hosts")
            self.assertEqual(status["storage"]["path"], str(attempts))
            usage.assert_called_once_with(attempts)

    def test_unavailable_volume_is_explicitly_unknown(self):
        for failure in [OSError("volume unavailable"), PermissionError("capacity denied")]:
            with self.subTest(error=type(failure).__name__), \
                    patch.object(worker_module.shutil, "disk_usage", side_effect=failure):
                status = self.fixture._call("hosts")
            self.assertFalse(status["storage"]["available"])
            self.assertIsNone(status["storage"]["free_bytes"])
            self.assertIn(str(failure), status["storage"]["error"])

    def test_capacity_query_does_not_hold_admission_lock(self):
        entered, release = threading.Event(), threading.Event()
        errors = []

        def slow_capacity(_path):
            entered.set()
            if not release.wait(5):
                raise OSError("fixture release missing")
            return SimpleNamespace(total=1000, used=700, free=300)

        def request():
            try:
                self.fixture._call("hosts")
            except BaseException as error:
                errors.append(error)

        with patch.object(worker_module.shutil, "disk_usage", side_effect=slow_capacity):
            thread = threading.Thread(target=request)
            thread.start()
            try:
                self.assertTrue(entered.wait(3))
                acquired = self.fixture.worker.lock.acquire(timeout=0.5)
                self.assertTrue(acquired, "slow capacity query held the admission lock")
                if acquired:
                    self.fixture.worker.lock.release()
            finally:
                release.set()
                thread.join(5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])

    def test_preparation_failure_retains_discoverable_owned_directory(self):
        with patch.object(worker_module.shutil, "copytree", side_effect=OSError("fixture disk full")):
            accepted = self.fixture._submit("fixture-failed-prepare", headless=True)
            status = self.fixture._finish(accepted["job"])
        self.assertEqual(status["outcome"], "INFRA_FAILED")
        self.assertEqual(status["cleanup"], "CONFIRMED")
        self.assertEqual(status["evidence"], "INCOMPLETE")
        self.assertTrue(Path(status["output"]).is_dir())
        self.assertEqual(Path(status["output"]), self.fixture._directory(accepted["job"]))
        self.assertNotIn("artifacts", status)


if __name__ == "__main__":
    unittest.main()
