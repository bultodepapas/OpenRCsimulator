"""MCP pool durability and nonblocking boundary tests; no real host needed."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.testqueue import pool_mcp as api
from tools.testqueue.common import Singleton, write_json


class PoolMcpTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        (self.source / "app").mkdir(parents=True)
        (self.source / "app/project.godot").write_text("config_version=5")
        self.config = self.root / "config.json"
        write_json(self.config, {"state_root": str(self.root / "pool"), "hosts": []})
        self.jobs = [{"script": "res://tests/test_math3d.gd"}]
        self.directory = self.root / "pool/mcp/test1"

    def launch(self, **kwargs):
        return api.launch("test1", self.jobs, self.source, config=self.config, **kwargs)

    def test_launch_is_local_and_idempotent_across_clients(self):
        with patch.object(api, "_start") as start, patch.object(api.Pool, "snapshot") as snapshot, \
                patch.object(api.Pool, "submit") as submit, patch.object(api.platform, "system", return_value="Windows"):
            first = self.launch()
            lock = Singleton(self.directory / "worker.lock")
            try:
                second = self.launch()
            finally:
                lock.close()
        start.assert_called_once_with(self.directory)
        snapshot.assert_not_called()
        submit.assert_not_called()
        self.assertEqual(first["request_id"], second["request_id"])
        self.assertFalse(first["source_frozen"])
        saved = api._read(self.directory / "request.json")
        self.assertEqual(saved["jobs"][0]["platform"], "windows")
        with patch.object(api, "_start") as start:
            with self.assertRaisesRegex(ValueError, "different inputs"):
                api.launch("test1", [{**self.jobs[0], "platform": "any"}], self.source, config=self.config)
        start.assert_not_called()

    def test_lost_reply_before_spawn_retries_durable_request(self):
        with patch.object(api, "_start", side_effect=OSError("spawn failed")):
            with self.assertRaises(OSError):
                self.launch()
        original = (self.directory / "request.json").read_bytes()
        with patch.object(api, "_start") as start:
            self.launch()
        start.assert_called_once()
        self.assertEqual(original, (self.directory / "request.json").read_bytes())
        (self.directory / "supervisor.json").unlink()
        with patch.object(api, "_start") as start:
            self.launch()
        start.assert_called_once()

    def test_invalid_jobs_and_tokens_never_launch(self):
        invalid = [[], [{"script": "oops"}], [{**self.jobs[0], "require": "bad"}],
                   [{**self.jobs[0], "platform": "other"}], [{**self.jobs[0], "host": []}],
                   [{"script": "res://tests/bench_physics.gd"}], [None]]
        with patch.object(api, "_start") as start:
            for jobs in invalid:
                with self.subTest(jobs=jobs), self.assertRaises(ValueError):
                    api.launch("test1", jobs, self.source, config=self.config)
            with self.assertRaises(ValueError):
                api.launch("../escape", self.jobs, self.source, config=self.config)
        start.assert_not_called()

    def test_status_no_remote_operations_and_live_lock(self):
        with patch.object(api, "_start"):
            self.launch()
        lock = Singleton(self.directory / "worker.lock")
        try:
            with patch.object(api.Pool, "status") as remote, patch.object(api, "_start") as start:
                result = api.status("test1", config=self.config)
            self.assertTrue(result["supervisor_active"])
            remote.assert_not_called()
            start.assert_not_called()
        finally:
            lock.close()
        self.assertFalse(api.status("test1", config=self.config)["supervisor_active"])

    def test_recover_complete_failure_does_not_spawn(self):
        with patch.object(api, "_start"):
            self.launch()
        write_json(self.directory / "batch.json", {"result": "FAILED", "snapshot": "original", "jobs": []})
        with patch.object(api, "_start") as start:
            self.assertEqual(api.recover("test1", config=self.config)["result"], "FAILED")
        start.assert_not_called()

    def test_config_change_blocks_recovery(self):
        with patch.object(api, "_start"):
            self.launch()
        value = api._read(self.config)
        value["changed"] = True
        write_json(self.config, value)
        with patch.object(api, "_start") as start, self.assertRaisesRegex(ValueError, "configuration changed"):
            api.recover("test1", config=self.config)
        start.assert_not_called()

    def test_supervisor_freezes_once_and_resumes_original_manifest(self):
        with patch.object(api, "_start"):
            self.launch()
        snapshot = self.root / "frozen"
        with patch.object(api.Pool, "snapshot", return_value=snapshot) as freeze, \
                patch.object(api, "run_batch", return_value={"result": "PASSED"}) as batch:
            api.supervise(self.directory)
            api.supervise(self.directory)
        freeze.assert_called_once_with(self.source)
        self.assertEqual(batch.call_count, 2)
        self.assertEqual(api._read(self.directory / "manifest.json")["snapshot"], str(snapshot))
        self.assertEqual(api._read(self.directory / "supervisor.json")["result"], "PASSED")

    def test_interrupted_freeze_does_not_capture_different_source(self):
        with patch.object(api, "_start"):
            self.launch()
        write_json(self.directory / "supervisor.json", {"state": "SNAPSHOTTING"})
        with patch.object(api.Pool, "snapshot") as freeze, patch.object(api, "run_batch") as batch:
            api.supervise(self.directory)
        freeze.assert_not_called()
        batch.assert_not_called()
        self.assertIn("new request_id", api._read(self.directory / "supervisor.json")["error"])

    def test_duplicate_worker_cannot_dispatch(self):
        with patch.object(api, "_start"):
            self.launch()
        lock = Singleton(self.directory / "worker.lock")
        try:
            with patch.object(api.Pool, "snapshot") as freeze:
                api.supervise(self.directory)
            freeze.assert_not_called()
        finally:
            lock.close()


if __name__ == "__main__":
    unittest.main()
