"""MCP pool durability and nonblocking boundary tests; no real host needed."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.testqueue import pool_mcp as api
from tools.testqueue.collection import FORMAT as COLLECTION_FORMAT
from tools.testqueue.common import Singleton, write_json


class PoolMcpTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / "source"
        (self.source / "app").mkdir(parents=True)
        (self.source / "app/project.godot").write_text("config_version=5")
        self.config = self.root / "config.json"
        write_json(self.config, {"state_root": str(self.root / "pool"), "hosts": []})
        # Not in the routing registry, so the caller-OS default applies (TQ-07-D2).
        self.jobs = [{"script": "res://tests/test_fixture_unrouted.gd"}]
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

    def test_unrelated_config_edit_keeps_launch_and_recovery_working(self):
        # TQ-07-A1: rows bind their own destination, so editing the pool
        # configuration (here an unrelated key) no longer strands the request.
        with patch.object(api, "_start"):
            self.launch()
        original = (self.directory / "request.json").read_bytes()
        value = api._read(self.config)
        value["changed"] = True
        write_json(self.config, value)
        with patch.object(api, "_start") as start:
            self.launch()  # same request, still idempotent
            api.recover("test1", config=self.config)
        start.assert_called()
        self.assertEqual(original, (self.directory / "request.json").read_bytes())
        other = self.root / "other-config.json"
        write_json(other, value)
        with patch.object(api, "_start") as start, self.assertRaisesRegex(ValueError, "different pool configuration"):
            api.recover("test1", config=other)
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

    def test_status_summary_is_compact_actionable_and_cached(self):
        passed = {"state": "FINISHED", "outcome": "PASSED", "evidence": "COMPLETE", "cleanup": "CONFIRMED"}
        failed = {**passed, "outcome": "TEST_FAILED"}
        collection = lambda job, outcome: {"pool_job": job, "pool_outcome": outcome, "diagnostic_only": False,
                                           "collection_format": COLLECTION_FORMAT,
                                           "report": f"/e/{job}/report.json", "log": f"/e/{job}/engine.log"}
        rows = [{"request_id": "a", "input": {"script": "res://tests/a.gd"}, "phase": "DONE",
                 "status": passed, "collection": collection("a", "PASSED")},
                {"request_id": "b", "input": {"script": "res://tests/b.gd"}, "phase": "DONE",
                 "status": failed, "collection": collection("b", "TEST_FAILED")},
                {"request_id": "c", "input": {"script": "res://tests/c.gd"}, "phase": "TRACKING",
                 "status": {"state": "RUNNING"}},
                {"request_id": "d", "input": {"script": "res://tests/d.gd"}, "phase": "WAITING"},
                {"request_id": "e", "input": {"script": "res://tests/e.gd"}, "phase": "BLOCKED",
                 "status": {"state": "UNKNOWN", "error": "lost link"}}]
        pool = api.Pool(self.config)
        write_json(pool.root / "history.json", {"linux": {"res://tests/c.gd": {"samples": [12, 14, 13]}},
                                                "mac": {"res://tests/c.gd": 40, "res://tests/d.gd": 3}})
        incomplete = {"result": "INCOMPLETE", "jobs": rows, "supervisor": {"state": "WAITING"},
                      "supervisor_active": True}
        summary = api.summarize(incomplete, pool)
        self.assertEqual({key: summary[key] for key in ("total", "passed", "failed", "running", "queued", "blocked")},
                         {"total": 5, "passed": 1, "failed": 1, "running": 1, "queued": 1, "blocked": 1})
        self.assertEqual([item["request_id"] for item in summary["attention"]], ["b", "e"])
        self.assertEqual(summary["attention"][0]["log"], "/e/b/engine.log")
        self.assertEqual(summary["next_action"], "poll sim_test_status")
        # Blocked rows never execute again: only queued/running medians count.
        self.assertEqual(summary["pending_test_seconds_serial"], 16)
        self.assertEqual(summary["unmeasured_pending_tests"], 0)
        self.assertEqual(summary["suggested_poll_seconds"], 3)
        # A live supervisor reobserves by itself; recovery is only for a stopped one.
        live_recovery = {**incomplete, "recovery_required": True}
        self.assertEqual(api.summarize(live_recovery, pool)["next_action"], "poll sim_test_status")
        stopped = {**incomplete, "supervisor_active": False}
        self.assertIn("sim_test_recover", api.summarize(stopped, pool)["next_action"])
        self.assertIn("sim_test_recover", api.summarize({**stopped, "supervisor": {}, "recovery_required": True},
                                                        pool)["next_action"])
        accepted = api.summarize({**stopped, "supervisor": {"state": "ACCEPTED"}}, pool)["next_action"]
        self.assertTrue(accepted.startswith("poll") and "30 s" in accepted)
        interrupted = {**stopped, "jobs": [], "supervisor": {"state": "SNAPSHOTTING"}}
        self.assertIn("new request_id", api.summarize(interrupted, pool)["next_action"])
        frozen = {**interrupted, "source_frozen": True}
        self.assertIn("sim_test_recover", api.summarize(frozen, pool)["next_action"])
        self.assertIn("inspect attention", api.summarize({**stopped, "result": "FAILED"}, pool)["next_action"])
        rejected = {"request_id": "r", "input": {"script": "res://tests/r.gd"}, "phase": "REJECTED",
                    "status": {"state": "REJECTED", "error": "invalid script"}}
        summary = api.summarize({**stopped, "result": "FAILED", "jobs": [rejected]}, pool)
        self.assertEqual((summary["rejected"], summary["attention"][0]["error"]), (1, "invalid script"))
        summary = api.summarize({"result": "PASSED", "jobs": rows[:1], "supervisor_active": False}, pool)
        self.assertEqual((summary["result"], summary["passed"], summary["attention"]), ("PASSED", 1, []))
        self.assertNotIn("suggested_poll_seconds", summary)

        # The real status call carries the summary without remote operations.
        with patch.object(api, "_start"):
            self.launch()
        write_json(self.directory / "batch.json", {"result": "INCOMPLETE", "snapshot": "s", "jobs": rows[2:]})
        with patch.object(api.Pool, "status") as remote, patch.object(api.Pool, "probe") as probe:
            summary = api.status("test1", config=self.config)["summary"]
        remote.assert_not_called()
        probe.assert_not_called()
        self.assertEqual((summary["running"], summary["queued"], summary["blocked"]), (1, 1, 1))

    def test_status_puts_summary_first_and_explains_unknown_ids(self):
        with patch.object(api, "_start"):
            self.launch()
        self.assertEqual(list(api.status("test1", config=self.config))[:2], ["request_id", "summary"])
        for call in (api.status, api.recover):
            with self.subTest(call=call.__name__), self.assertRaisesRegex(ValueError, "unknown request_id"):
                call("missing1", config=self.config)

    def test_interrupted_snapshot_and_blocked_only_batches_get_terminal_advice(self):
        with patch.object(api, "_start"):
            self.launch()
        write_json(self.directory / "supervisor.json",
                   {"state": "ERROR", "error": "snapshot preparation was interrupted; no tests dispatched"})
        self.assertIn("new request_id", api.status("test1", config=self.config)["summary"]["next_action"])
        with patch.object(api, "_start") as start, self.assertRaisesRegex(ValueError, "new request_id"):
            api.recover("test1", config=self.config)
        start.assert_not_called()
        blocked = {"request_id": "x", "input": {"script": "res://tests/x.gd"}, "phase": "BLOCKED",
                   "status": {"state": "UNKNOWN"}}
        for active in (True, False):
            summary = api.summarize({"result": "INCOMPLETE", "jobs": [blocked], "supervisor_active": active,
                                     "supervisor": {"state": "WAITING"}, "source_frozen": True})
            expected = "blocked rows" if active else "sim_test_recover"
            self.assertIn(expected, summary["next_action"])

    def test_supervisor_survives_a_brief_liveness_probe_of_its_lock(self):
        with patch.object(api, "_start"):
            self.launch()
        probe = Singleton(self.directory / "worker.lock")
        import threading
        threading.Timer(0.3, probe.close).start()
        with patch.object(api.Pool, "snapshot", return_value=self.root / "frozen"), \
                patch.object(api, "run_batch", return_value={"result": "PASSED"}) as batch:
            api.supervise(self.directory)
        batch.assert_called_once()

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
