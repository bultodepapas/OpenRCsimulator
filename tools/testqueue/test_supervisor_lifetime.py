"""Supervisors outlive their client, stop with a reason and are resumed unattended (TQ-05-F2)."""
from __future__ import annotations

import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from tools.testqueue import pool_mcp as api
from tools.testqueue import watchdog
from tools.testqueue.common import write_json


def _rows(*phases):
    return [{"request_id": f"j{index}", "phase": phase, "status": {"state": "UNKNOWN" if phase == "BLOCKED" else None}}
            for index, phase in enumerate(phases)]


class ProgressTests(unittest.TestCase):
    def setUp(self):
        self.now = [0.0]
        self.progress = api.Progress(clock=lambda: self.now[0])

    def test_change_resets_and_blocked_rows_stop_after_the_quiet_window(self):
        self.assertIsNone(self.progress.observe(_rows("DONE", "BLOCKED")))
        self.now[0] = api.STUCK_SECONDS - 1
        self.assertIsNone(self.progress.observe(_rows("DONE", "BLOCKED")))
        self.now[0] = api.STUCK_SECONDS + 1
        stop = self.progress.observe(_rows("DONE", "BLOCKED"))
        self.assertIn("blocked", stop["detail"])
        self.assertEqual(stop["blocked_jobs"], ["j1"])
        self.assertIn("never resubmit", stop["action"])

    def test_running_work_is_not_stuck_but_idle_limit_still_applies(self):
        self.progress.observe(_rows("BLOCKED", "TRACKING"))
        self.now[0] = api.STUCK_SECONDS * 2
        self.assertIsNone(self.progress.observe(_rows("BLOCKED", "TRACKING")))
        self.now[0] = api.IDLE_SECONDS + 1
        stop = self.progress.observe(_rows("BLOCKED", "TRACKING"))
        self.assertIn("nothing was cancelled", stop["detail"])

    def test_any_change_keeps_observing(self):
        self.progress.observe(_rows("WAITING"))
        self.now[0] = api.IDLE_SECONDS + 5
        self.assertIsNone(self.progress.observe(_rows("TRACKING")))


class SupervisorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        source = self.root / "source"
        (source / "app").mkdir(parents=True)
        (source / "app/project.godot").write_text("config_version=5")
        self.config = self.root / "config.json"
        write_json(self.config, {"state_root": str(self.root / "pool"), "hosts": []})
        with patch.object(api, "_start"):
            api.launch("blocked1", [{"script": "res://tests/test_math3d.gd"}], source, config=self.config)
        self.directory = self.root / "pool/mcp/blocked1"

    def test_blocked_batch_stops_with_needs_operator_instead_of_polling_forever(self):
        rows = _rows("BLOCKED")
        with patch.object(api.Pool, "snapshot", return_value=self.root / "frozen"), \
                patch.object(api, "run_batch", return_value={"result": "INCOMPLETE", "jobs": rows}) as batch, \
                patch.object(api, "STUCK_SECONDS", 0), patch.object(api, "SUPERVISOR_PAUSE_SECONDS", 0):
            api.supervise(self.directory)
        self.assertEqual(batch.call_count, 2)  # first sight records the state, the unchanged second stops
        state = api._read(self.directory / "supervisor.json")
        self.assertEqual(state["state"], "NEEDS_OPERATOR")
        summary = api.status("blocked1", config=self.config)["summary"]
        self.assertTrue(summary["next_action"].startswith("needs attention"))
        # The watchdog leaves it for an operator.
        self.assertEqual(watchdog.plan(api.Pool(self.config), max_age_hours=24)["resume"], [])

    def test_watchdog_resumes_recent_dead_supervisors_only(self):
        write_json(self.directory / "manifest.json", {"snapshot": "x", "jobs": []})
        write_json(self.directory / "supervisor.json", {"state": "RUNNING", "updated_at": time.time()})
        pool = api.Pool(self.config)
        self.assertEqual([item["request_id"] for item in watchdog.plan(pool, max_age_hours=24)["resume"]], ["blocked1"])
        old = time.time() - 48 * 3600
        for name in ("manifest.json", "supervisor.json", "request.json"):
            os.utime(self.directory / name, (old, old))
        planned = watchdog.plan(pool, max_age_hours=24)
        self.assertEqual((planned["resume"], [item["request_id"] for item in planned["stale"]]), ([], ["blocked1"]))
        with patch.object(api, "_start") as start:
            report = watchdog.run_once(self.config, max_age_hours=100)
        start.assert_called_once()
        self.assertEqual(report["results"], [{"request_id": "blocked1", "resumed": True}])

    def test_watchdog_skips_errors_and_caps_repeated_resumes(self):
        write_json(self.directory / "manifest.json", {"snapshot": "x", "jobs": []})
        write_json(self.directory / "supervisor.json", {"state": "ERROR", "error": "batch inputs changed"})
        self.assertEqual(watchdog.plan(api.Pool(self.config), max_age_hours=24)["resume"], [])
        write_json(self.directory / "supervisor.json", {"state": "RUNNING"})
        with patch.object(api, "_start") as start:
            for _ in range(watchdog.MAX_RESUMES_PER_DAY + 2):
                report = watchdog.run_once(self.config)
        self.assertEqual(start.call_count, watchdog.MAX_RESUMES_PER_DAY)
        self.assertIn("left for an operator", report["results"][0]["error"])

    def test_watchdog_dry_run_and_finished_batches_start_nothing(self):
        write_json(self.directory / "manifest.json", {"snapshot": "x", "jobs": []})
        with patch.object(api, "_start") as start:
            watchdog.run_once(self.config, dry_run=True)
            write_json(self.directory / "batch.json", {"result": "PASSED", "jobs": []})
            watchdog.run_once(self.config)
        start.assert_not_called()


@unittest.skipUnless(os.name == "nt", "Windows Job Object behavior")
class JobBreakawayTests(unittest.TestCase):
    """A supervisor started from inside a kill-on-close job survives the job's closure."""

    PARENT = r"""
import ctypes, sys, time
from ctypes import wintypes
sys.path.insert(0, sys.argv[1])
k32 = ctypes.WinDLL("kernel32", use_last_error=True)
class BASIC(ctypes.Structure):
    _fields_ = [("a", ctypes.c_int64), ("b", ctypes.c_int64), ("LimitFlags", wintypes.DWORD),
                ("c", ctypes.c_size_t), ("d", ctypes.c_size_t), ("e", wintypes.DWORD), ("f", ctypes.c_size_t),
                ("g", wintypes.DWORD), ("h", wintypes.DWORD)]
class EXT(ctypes.Structure):
    _fields_ = [("Basic", BASIC), ("Io", ctypes.c_uint64 * 6), ("m", ctypes.c_size_t * 4)]
k32.CreateJobObjectW.restype = wintypes.HANDLE
k32.GetCurrentProcess.restype = wintypes.HANDLE
k32.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
k32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
job = k32.CreateJobObjectW(None, None)
info = EXT(); info.Basic.LimitFlags = 0x2000 | 0x800  # KILL_ON_JOB_CLOSE | BREAKAWAY_OK
assert k32.SetInformationJobObject(job, 9, ctypes.byref(info), ctypes.sizeof(info)), ctypes.get_last_error()
assert k32.AssignProcessToJobObject(job, k32.GetCurrentProcess()), ctypes.get_last_error()
from tools.testqueue.pool_mcp import spawn_background
import subprocess
# Use the actual interpreter so a Windows virtualenv launcher cannot stand in
# for either child when the outer test checks its lifetime.
child = [sys._base_executable, "-c", "import time; time.sleep(60)"]
# Keep the parent result pipe independent of both child lifetimes.
plain = subprocess.Popen(child, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
with open(sys.argv[2], "ab") as log:
    escaped = spawn_background(child, log)
print(plain.pid, escaped.pid, flush=True)
"""

    def test_breakaway_child_survives_kill_on_close(self):
        import psutil
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / "parent.py"
            script.write_text(self.PARENT, encoding="utf-8")
            output = subprocess.run([sys._base_executable, str(script), str(Path(__file__).resolve().parents[2]),
                                     str(Path(tmp) / "log.txt")], capture_output=True, text=True, timeout=60)
            self.assertEqual(output.returncode, 0, output.stderr)
            plain, escaped = map(int, output.stdout.split())
            try:
                try:
                    psutil.Process(plain).wait(timeout=10)
                except psutil.NoSuchProcess:
                    pass
                except psutil.TimeoutExpired:
                    self.fail("job closure should kill a child that stayed in the job")
                self.assertTrue(psutil.pid_exists(escaped), "breakaway child must survive the job")
            finally:
                for pid in (plain, escaped):
                    try:
                        process = psutil.Process(pid)
                        process.kill()
                        process.wait(10)
                    except psutil.Error:
                        pass


if __name__ == "__main__":
    unittest.main()
