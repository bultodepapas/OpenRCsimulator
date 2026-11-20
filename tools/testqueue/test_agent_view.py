"""Agent-facing fleet, compact status, list and one-call run (TQ-05-F1)."""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.testqueue import agent_view, pool_mcp


def _row(phase, platform="windows", candidates=None, **extra):
    row = {"phase": phase, "request_id": "j-" + phase.lower(),
           "input": {"script": "res://tests/test_x.gd", "platform": platform}, **extra}
    if candidates is not None:
        row["status"] = {"decision": {"candidates": candidates, "selected": None}, "state": "WAITING"}
    return row


def _cand(host, *reasons):
    return {"host": host, "eligible": not reasons, "reasons": list(reasons), "score": None}


class WaitReasonTests(unittest.TestCase):
    def test_codes_and_platform_alternative(self):
        mismatch = "PLATFORM_MISMATCH: requires windows"
        self.assertEqual(agent_view._wait_reason(_row("WAITING", candidates=[_cand("linux", mismatch)]), "windows")["code"],
                         "NO_HOST_FOR_PLATFORM")
        offline = agent_view._wait_reason(_row("WAITING", candidates=[_cand("windows", "OFFLINE"),
                                                                       _cand("linux", mismatch)]), "windows")
        self.assertEqual(offline["code"], "NO_ONLINE_HOST_FOR_PLATFORM")
        self.assertIn("linux", offline["alternative"])
        busy = agent_view._wait_reason(_row("WAITING", candidates=[
            _cand("windows", "BUSY: an unmanaged simulator is running on this desktop")]), "windows")
        self.assertEqual((busy["code"], list(busy["hosts"])), ("HOST_BUSY", ["windows"]))
        disk = agent_view._wait_reason(_row("WAITING", candidates=[_cand("windows", "INSUFFICIENT_DISK: 1 < 2 bytes")]),
                                       "windows")
        self.assertEqual(disk["code"], "DISK")
        self.assertEqual(agent_view._wait_reason(_row("WAITING"), "windows"), {"code": "QUEUED_IN_BATCH"})
        retry = agent_view._wait_reason(_row("RETRY_WAIT", first_error="lock busy"), "windows")
        self.assertEqual((retry["code"], retry["detail"]), ("RETRY_WAIT", "lock busy"))

    def test_summary_next_action_names_the_wait(self):
        stopped = {"supervisor_active": True, "supervisor": {"state": "RUNNING"}, "result": "INCOMPLETE"}
        none = _row("WAITING", candidates=[_cand("linux", "PLATFORM_MISMATCH: requires darwin")], platform="darwin")
        self.assertIn("cannot start", pool_mcp.summarize({**stopped, "jobs": [none]})["next_action"])
        off = _row("WAITING", candidates=[_cand("angel", "OFFLINE")], platform="darwin")
        summary = pool_mcp.summarize({**stopped, "jobs": [off]})
        self.assertIn("offline", summary["next_action"])
        self.assertEqual(summary["waiting"], {"NO_ONLINE_HOST_FOR_PLATFORM": 1})
        queued = pool_mcp.summarize({**stopped, "jobs": [_row("WAITING")]})
        self.assertEqual(queued["next_action"], "poll sim_test_status")


class CompactStatusTests(unittest.TestCase):
    def test_failed_row_carries_cause_markers_and_flagged_log_lines(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "engine.log"
            log.write_text("start\nok 1\nFAIL thing: expected 2 got 3\nSUMMARY 5 checks, 1 failures\n", encoding="utf-8")
            row = {"phase": "DONE", "request_id": "j1", "input": {"script": "res://tests/a.gd", "platform": "darwin"},
                   "status": {"outcome": "TEST_FAILED", "pool_host": "angela"},
                   "collection": {"log": str(log), "report": "r.json", "reason": "process_exit",
                                  "missing_required_text": ["0 failures"], "elapsed_seconds": 1.94}}
            item = agent_view.compact_row(row)
        self.assertEqual((item["host"], item["outcome"], item["seconds"], item["why"]),
                         ("angela", "TEST_FAILED", 1.9, "process_exit"))
        self.assertEqual(item["log_tail"], ["FAIL thing: expected 2 got 3", "SUMMARY 5 checks, 1 failures"])
        self.assertEqual(item["missing_markers"], ["0 failures"])
        passed = agent_view.compact_row({"phase": "DONE", "request_id": "j2", "input": {"script": "b"},
                                         "status": {"outcome": "PASSED"}, "collection": {"log": str(log)}})
        self.assertNotIn("log_tail", passed)

    def test_compact_status_is_small_and_keeps_top_level_result(self):
        rows = [_row("WAITING") for _ in range(40)]
        full = {"request_id": "x", "result": "INCOMPLETE", "summary": {"result": "INCOMPLETE", "attention": [1, 2]},
                "jobs": rows, "supervisor": {"state": "RUNNING", "updated_at": 1}, "supervisor_active": True}
        view = agent_view.compact_status(full)
        self.assertEqual(list(view)[:2], ["request_id", "summary"])
        self.assertEqual(view["result"], "INCOMPLETE")
        self.assertNotIn("attention", view["summary"])
        self.assertNotIn("waiting", view["tests"][0])
        self.assertLess(len(json.dumps(view)), 6000)
        frozen = agent_view.compact_status({"request_id": "y", "summary": {}, "jobs": [],
                                            "request_jobs": [{"script": "s", "platform": "linux"}]})
        self.assertEqual(frozen["tests"], [{"script": "s", "platform": "linux", "phase": "NOT_FROZEN"}])


class FakePool:
    def __init__(self, root):
        self.root, self.probes = Path(root), 0
        (self.root / "jobs").mkdir(parents=True)

    def probe(self):
        self.probes += 1
        return [{"id": "windows", "platform": "windows", "online": True, "busy": True, "busy_code": "EXTERNAL_SIMULATOR",
                 "free_disk_bytes": 9e10, "free_memory_bytes": 3e10, "cores": 24, "load": 1.234},
                {"id": "linux", "platform": "linux", "online": True, "busy": False, "free_disk_bytes": 2e10,
                 "cores": 12, "load": 0.1},
                {"id": "angel", "online": False, "reason": "ssh timed out"}]


class FleetTests(unittest.TestCase):
    def test_cache_refresh_and_hints(self):
        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(agent_view, "godot_processes", return_value=[{"pid": 7, "managed": False}]):
            pool = FakePool(tmp)
            (pool.root / "jobs" / "a.json").write_text(json.dumps(
                {"host": "linux", "state": "SUBMITTED", "last_status": {"state": "RUNNING"}}), encoding="utf-8")
            first = agent_view.fleet(pool)
            again = agent_view.fleet(pool)
            self.assertEqual(pool.probes, 1)
            agent_view.fleet(pool, refresh=True)
            self.assertEqual(pool.probes, 2)
        hosts = {host["id"]: host for host in first["hosts"]}
        self.assertEqual(hosts["windows"]["busy_code"], "EXTERNAL_SIMULATOR")
        self.assertEqual(hosts["linux"]["pool_jobs_active"], 1)
        self.assertEqual(hosts["angel"], {"id": "angel", "platform": None, "online": False,
                                          "offline_reason": "ssh timed out"})
        self.assertGreaterEqual(again["age_seconds"], 0)
        self.assertTrue(any("idle now: linux=linux" in hint for hint in first["hints"]))
        self.assertTrue(any("unmanaged" in hint for hint in first["hints"]))


class RunTests(unittest.TestCase):
    def test_run_generates_id_waits_and_returns_final_result(self):
        views = iter([{"summary": {"result": "INCOMPLETE", "next_action": "poll"}, "supervisor_active": True},
                      {"summary": {"result": "PASSED", "next_action": "none"}, "supervisor_active": False}])
        with patch.object(pool_mcp, "launch") as launch, \
                patch.object(pool_mcp, "status", side_effect=lambda *a, **k: dict(next(views))), \
                patch.object(pool_mcp, "RUN_POLL_SECONDS", 0.01):
            view = pool_mcp.run([{"script": "res://tests/test_math3d.gd"}], wait_s=5)
        request_id = launch.call_args.args[0]
        self.assertTrue(request_id.startswith("run-"))
        self.assertEqual(view["summary"]["result"], "PASSED")
        self.assertNotIn("note", view)

    def test_run_timeout_observes_only_and_bounds_wait(self):
        with patch.object(pool_mcp, "launch"), \
                patch.object(pool_mcp, "status", return_value={"summary": {"result": "INCOMPLETE", "next_action": "poll"},
                                                               "supervisor_active": True}), \
                patch.object(pool_mcp, "RUN_POLL_SECONDS", 0.01):
            started = time.monotonic()
            view = pool_mcp.run([{"script": "s"}], request_id="mine", wait_s=0.05)
            self.assertLess(time.monotonic() - started, 2)
        self.assertIn("never cancels", view["note"])
        for bad in (-1, 301, "10"):
            with self.assertRaises(ValueError):
                pool_mcp.run([{"script": "s"}], wait_s=bad)

    def test_run_stops_waiting_when_supervisor_died(self):
        stopped = {"summary": {"result": "INCOMPLETE", "next_action": "sim_test_recover with the same request_id"},
                   "supervisor_active": False}
        with patch.object(pool_mcp, "launch"), patch.object(pool_mcp, "status", return_value=dict(stopped)) as status:
            pool_mcp.run([{"script": "s"}], wait_s=30)
        self.assertEqual(status.call_count, 1)


class ListTests(unittest.TestCase):
    def test_newest_first_with_results(self):
        with tempfile.TemporaryDirectory() as tmp:
            pool = FakePool(tmp)
            for index, (name, result) in enumerate((("old", "FAILED"), ("new", "PASSED"))):
                directory = pool.root / "mcp" / name
                directory.mkdir(parents=True)
                (directory / "request.json").write_text(json.dumps({"jobs": [{"script": "s"}]}), encoding="utf-8")
                (directory / "batch.json").write_text(json.dumps({"result": result, "jobs": [
                    {"phase": "DONE", "status": {"outcome": "PASSED"}}]}), encoding="utf-8")
                stamp = time.time() - 100 + index * 50
                import os
                os.utime(directory, (stamp, stamp))
            listed = agent_view.list_requests(pool, 10)
        self.assertEqual([(item["request_id"], item["result"], item["passed"]) for item in listed],
                         [("new", "PASSED", 1), ("old", "FAILED", 1)])


class SnapshotRetryTests(unittest.TestCase):
    """TQ-05-F0.2: concurrent edits in the shared checkout no longer kill a request."""

    def setUp(self):
        from tools.testqueue.pool import Pool
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        config = root / "config.json"
        config.write_text(json.dumps({"state_root": str(root / "state"), "hosts": [{"id": "windows", "local": True}]}))
        self.pool = Pool(config)
        self.pool.SNAPSHOT_BACKOFF_SECONDS = 0

    def test_retries_changed_source_and_removes_only_own_partial(self):
        targets = []

        def capture(_source, target, **_):
            targets.append(target)
            target.mkdir()
            (target / "partial").write_text("x")
            if len(targets) < 3:
                raise ValueError("source changed during snapshot: app/x.gd")

        with patch("tools.testqueue.pool.capture", side_effect=capture):
            result = self.pool.snapshot(self.temp.name)
        self.assertEqual(result, targets[-1])
        self.assertEqual([target.exists() for target in targets], [False, False, True])

    def test_other_failures_and_exhaustion_raise_and_keep_evidence(self):
        def broken(_source, target, **_):
            target.mkdir()
            raise ValueError("snapshot needs 1 bytes plus a 2-byte free reserve")

        with patch("tools.testqueue.pool.capture", side_effect=broken) as capture, self.assertRaises(ValueError):
            self.pool.snapshot(self.temp.name)
        self.assertEqual(capture.call_count, 1)

        def always(_source, target, **_):
            raise ValueError("source changed during snapshot: app/y.gd")

        with patch("tools.testqueue.pool.capture", side_effect=always) as capture, self.assertRaises(ValueError):
            self.pool.snapshot(self.temp.name)
        self.assertEqual(capture.call_count, self.pool.SNAPSHOT_ATTEMPTS)

    def test_bytecode_paths_are_never_frozen(self):
        from tools.testqueue.snapshots import _bytecode
        self.assertTrue(_bytecode("tools/godot/__pycache__/run_checked.cpython-311.pyc"))
        self.assertTrue(_bytecode("tools/x.pyo"))
        self.assertFalse(_bytecode("tools/godot/run_checked.py"))
        self.assertFalse(_bytecode("app/pycache_notes.gd"))

    def test_failed_freeze_says_resubmit_not_recover(self):
        summary = pool_mcp.summarize({"supervisor_active": False, "source_frozen": False, "jobs": [],
                                      "supervisor": {"state": "ERROR", "error": "source changed during snapshot: a"}})
        self.assertTrue(summary["next_action"].startswith("source freeze failed"))
        self.assertIn("new request_id", summary["next_action"])


if __name__ == "__main__":
    unittest.main()
