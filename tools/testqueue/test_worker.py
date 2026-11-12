"""Local scheduling and lifecycle checks using real owned fake processes.

These fixtures do not launch Godot or qualify a graphical platform adapter.
"""
from __future__ import annotations

import json
import os
from contextlib import closing
from pathlib import Path
import sqlite3
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock
import uuid

from tools.testqueue import processes, snapshots
from tools.testqueue.worker import Worker


_ADAPTER = r'''
import json
import os
from pathlib import Path
import subprocess
import sys
import time

directory = Path(sys.argv[1])
root = Path(os.environ["OPENRC_TESTQUEUE_ROOT"])
request = json.loads((directory / "request.json").read_text(encoding="utf-8"))
owner = request["owner"]
start = time.monotonic_ns()
(directory / "started.json").write_text(json.dumps({"time": start, "pid": os.getpid(),
    "source": os.getcwd(), "profile": os.environ["APPDATA"], "temp": os.environ["TEMP"]}))

if owner.startswith("rendered-"):
    until = time.monotonic() + 15
    while not (directory / "probe-attached").exists() and time.monotonic() < until:
        time.sleep(0.02)

if owner.startswith("orphan"):
    child = r"""import json,sys,time
from pathlib import Path
d = Path(sys.argv[1])
(d / 'child-start.json').write_text(json.dumps({'time': time.monotonic_ns()}))
until = time.monotonic() + 20
while not (d / 'release-child').exists() and time.monotonic() < until:
    time.sleep(0.02)
(d / 'child-end.json').write_text(json.dumps({'time': time.monotonic_ns()}))
"""
    subprocess.Popen([sys.executable, "-c", child, str(directory)], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    until = time.monotonic() + 5
    while not (directory / "child-start.json").exists() and time.monotonic() < until:
        time.sleep(0.02)
    (directory / "verdict.json").write_text(json.dumps({"ok": True, "complete": True}))
    (directory / "launcher-returning").write_text("yes")
    sys.exit(0)

if owner.startswith("headless"):
    (root / (owner + ".ready")).write_text("yes")
    until = time.monotonic() + 8
    while len(list(root.glob("headless-*.ready"))) < 2 and time.monotonic() < until:
        time.sleep(0.02)
    (directory / "barrier.json").write_text(json.dumps({"joined": len(list(root.glob("headless-*.ready"))) >= 2}))
    time.sleep(0.25)
elif owner.startswith("long"):
    time.sleep(30)
else:
    time.sleep(0.3)

(directory / "ended.json").write_text(json.dumps({"time": time.monotonic_ns()}))
if not owner.startswith("no-verdict"):
    (directory / "verdict.json").write_text(json.dumps({"ok": not owner.startswith("bad-verdict"), "complete": True}))
'''


def wait_until(predicate, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.025)
    raise AssertionError("timed out waiting for fixture state")


class WorkerFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-worker-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        self.repo.mkdir()
        self._git("init", "-q")
        self._git("config", "user.name", "Queue Fixture")
        self._git("config", "user.email", "queue@example.invalid")
        self._write("app/project.godot", "[application]\n")
        self._write("tools/testqueue/adapter.py", _ADAPTER)
        self._git("add", ".")
        self._git("commit", "-qm", "fixture")
        self.snapshot = self.base / "frozen"
        snapshots.capture(self.repo, self.snapshot, scope=("app", "tools"))
        self.worker = Worker(self.base / "worker", self.repo, Path(sys.executable), slots=2, fixture=True)
        self.handles = []
        self.scheduler = threading.Thread(target=self.worker.schedule, daemon=True)
        self.scheduler.start()
        self.addCleanup(self._stop)

    def _git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], stderr=subprocess.PIPE)

    def _write(self, name, content):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def _call(self, operation, **args):
        return self.worker.dispatch({"auth": self.worker.auth, "operation": operation, **args})

    def _submit(self, owner, *, headless=False):
        result = self._call("submit", owner=owner, preset="debug-session", options={"headless": headless, "timeout": 40},
                            source=str(self.repo), snapshot=str(self.snapshot),
                            request_id=uuid.uuid4().hex, request_secret=uuid.uuid4().hex)
        self.handles.append(result)
        return result

    def _status(self, job):
        return self._call("status", job=job)

    def _finish(self, job, timeout=25):
        return wait_until(lambda: (status if (status := self._status(job))["state"] in {"FINISHED", "UNKNOWN"} else None), timeout)

    def _directory(self, job):
        status = self._status(job)
        return self.worker.root / "attempts" / status["attempts"][-1]["id"] if status["attempts"] else None

    def _stop(self):
        self.worker.draining = False
        # Release only this fixture's held child and cancel its own outstanding jobs.
        for directory in (self.worker.root / "attempts").glob("*"):
            if (directory / "child-start.json").exists():
                (directory / "release-child").write_text("cleanup")
        for submitted in self.handles:
            try:
                if self._status(submitted["job"])["state"] not in {"FINISHED", "UNKNOWN"}:
                    self._call("cancel", handle=submitted["handle"])
            except (OSError, ValueError):
                pass
        deadline = time.monotonic() + 12
        while self.worker.active and time.monotonic() < deadline:
            time.sleep(0.05)
        self.worker.stopping.set()
        self.scheduler.join(timeout=3)
        self.worker.store.db.close()
        self.worker.singleton.close()

    def test_five_rendered_owners_never_overlap(self):
        submissions = [self._submit(f"rendered-{index}") for index in range(5)]
        handles = {}
        if os.name == "nt":
            import ctypes
            from ctypes import wintypes
            kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
            kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
            kernel32.OpenProcess.restype = wintypes.HANDLE
            kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
            kernel32.CloseHandle.restype = wintypes.BOOL
            kernel32.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
            kernel32.GetProcessTimes.restype = wintypes.BOOL
            kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
            kernel32.WaitForSingleObject.restype = wintypes.DWORD

        def attach_started_processes():
            for item in submissions:
                if item["job"] in handles:
                    continue
                directory = self._directory(item["job"])
                if directory is None or not (directory / "started.json").exists():
                    continue
                try:
                    started = json.loads((directory / "started.json").read_text())
                except (OSError, json.JSONDecodeError):
                    continue
                if os.name == "nt":
                    # Retain the kernel handle after exit so process creation and
                    # exit FILETIMEs bound the full actual fixture lifetime.
                    handle = kernel32.OpenProcess(0x00100000 | 0x1000, False, started["pid"])
                    self.assertTrue(handle, f"cannot open fixture PID {started['pid']}")
                    self.addCleanup(kernel32.CloseHandle, handle)
                    handles[item["job"]] = handle
                else:
                    handles[item["job"]] = None
                (directory / "probe-attached").write_text("ready")
            return len(handles) == len(submissions)

        wait_until(attach_started_processes, timeout=30)
        statuses = [self._finish(item["job"]) for item in submissions]
        self.assertTrue(all(status.get("outcome") == "PASSED" for status in statuses), statuses)
        intervals = []
        for status in statuses:
            directory = self.worker.root / "attempts" / status["attempt"]
            if os.name == "nt":
                handle = handles[status["id"]]
                self.assertEqual(kernel32.WaitForSingleObject(handle, 5000), 0)
                creation, exit_time, kernel, user = (wintypes.FILETIME() for _ in range(4))
                self.assertTrue(kernel32.GetProcessTimes(handle, ctypes.byref(creation), ctypes.byref(exit_time),
                                                         ctypes.byref(kernel), ctypes.byref(user)))
                start = (creation.dwHighDateTime << 32) | creation.dwLowDateTime
                end = (exit_time.dwHighDateTime << 32) | exit_time.dwLowDateTime
            else:
                start = json.loads((directory / "started.json").read_text())["time"]
                end = json.loads((directory / "ended.json").read_text())["time"]
            intervals.append((start, end))
        intervals.sort()
        self.assertEqual(len(intervals), 5)
        for previous, following in zip(intervals, intervals[1:]):
            self.assertLessEqual(previous[1], following[0], intervals)

    def test_exited_launcher_keeps_rendered_claim_while_child_lives(self):
        first = self._submit("orphan-owner")
        directory = wait_until(lambda: (candidate if (candidate := self._directory(first["job"]))
                               and (candidate / "child-start.json").exists() else None))
        wait_until(lambda: (directory / "launcher-returning").exists())
        second = self._submit("next-owner")
        attempt = self._status(first["job"])["attempts"][-1]["id"]

        def launcher_exited():
            with self.worker.lock:
                process = self.worker.active.get(attempt)
                return process is not None and process.poll() == 0 and process.alive()

        wait_until(launcher_exited)
        self.assertEqual(self._status(first["job"])["state"], "RUNNING")
        self.assertEqual(self._status(second["job"])["state"], "QUEUED")
        self.assertFalse((directory / "child-end.json").exists())
        (directory / "release-child").write_text("release")
        first_status = self._finish(first["job"])
        second_status = self._finish(second["job"])
        self.assertEqual(first_status.get("outcome"), "PASSED", first_status)
        self.assertEqual(second_status.get("outcome"), "PASSED", second_status)
        ended = json.loads((directory / "child-end.json").read_text())["time"]
        later = self.worker.root / "attempts" / second_status["attempt"] / "started.json"
        self.assertLessEqual(ended, json.loads(later.read_text())["time"])

    def test_two_headless_jobs_overlap_with_independent_writable_state(self):
        jobs = [self._submit(f"headless-{index}", headless=True) for index in range(2)]
        statuses = [self._finish(item["job"]) for item in jobs]
        self.assertTrue(all(status.get("outcome") == "PASSED" for status in statuses), statuses)
        observations = []
        ends = []
        for status in statuses:
            directory = self.worker.root / "attempts" / status["attempt"]
            self.assertTrue(json.loads((directory / "barrier.json").read_text())["joined"])
            observations.append(json.loads((directory / "started.json").read_text()))
            ends.append(json.loads((directory / "ended.json").read_text())["time"])
        self.assertLess(max(item["time"] for item in observations), min(ends))
        for key in ("source", "profile", "temp"):
            self.assertEqual(len({item[key] for item in observations}), 2, key)

    def test_queued_and_running_cancellation_and_ownership(self):
        self.worker.draining = True
        queued = self._submit("queued-owner")
        with self.assertRaisesRegex(ValueError, "handle"):
            self._call("cancel", handle=queued["job"] + ":wrong")
        self.assertEqual(self._status(queued["job"])["state"], "QUEUED")
        self._call("cancel", handle=queued["handle"])
        canceled = self._status(queued["job"])
        self.assertEqual(canceled["state"], "FINISHED")
        self.assertEqual(canceled["canceled"], 1)
        self.assertEqual(canceled["attempts"], [])
        with closing(sqlite3.connect(self.worker.root / "queue.sqlite3")) as connection:
            self.assertEqual(connection.execute("SELECT state,canceled FROM jobs WHERE id=?", (queued["job"],)).fetchone(),
                             ("FINISHED", 1))
        self.worker.draining = False
        running = self._submit("long-owner")
        wait_until(lambda: (directory if (directory := self._directory(running["job"]))
                   and (directory / "started.json").exists() else None))
        self._call("cancel", handle=running["handle"])
        finished = self._finish(running["job"])
        self.assertEqual(finished.get("outcome"), "CANCELED", finished)
        self.assertEqual(finished.get("cleanup"), "CONFIRMED", finished)
        self.assertEqual(finished["canceled"], 1)

    def test_changed_submitted_snapshot_never_executes(self):
        self.worker.draining = True
        job = self._submit("must-not-execute")
        (self.snapshot / "source/app/project.godot").write_text("changed after submission")
        self.worker.draining = False
        status = self._finish(job["job"])
        self.assertEqual(status.get("outcome"), "INFRA_FAILED", status)
        self.assertIn("snapshot", status.get("error", ""))
        self.assertFalse((self.worker.root / "attempts" / status["attempt"] / "started.json").exists())

    def test_zero_exit_without_successful_verdict_does_not_pass(self):
        missing = self._submit("no-verdict")
        bad = self._submit("bad-verdict")
        missing_status = self._finish(missing["job"])
        bad_status = self._finish(bad["job"])
        self.assertEqual(missing_status.get("runner_exit_code"), 0, missing_status)
        self.assertEqual(missing_status.get("outcome"), "INFRA_FAILED", missing_status)
        self.assertEqual(bad_status.get("runner_exit_code"), 0, bad_status)
        self.assertEqual(bad_status.get("outcome"), "TEST_FAILED", bad_status)

    def test_uncertain_cleanup_keeps_claim_and_never_passes(self):
        real_close = processes.OwnedProcess.close

        def report_uncertain(process):
            # Stop this owned fixture safely, then inject loss of cleanup proof.
            real_close(process)
            raise RuntimeError("injected cleanup uncertainty")

        with mock.patch.object(processes.OwnedProcess, "close", new=report_uncertain):
            first = self._submit("uncertain-owner")
            result = self._finish(first["job"])
        self.assertEqual(result["state"], "UNKNOWN", result)
        self.assertNotEqual(result.get("outcome"), "PASSED")
        self.assertNotEqual(result.get("cleanup"), "CONFIRMED")
        second = self._submit("blocked-owner")
        blocked = wait_until(lambda: (status if (status := self._status(second["job"]))["reason"].startswith("RESOURCE_BUSY") else None))
        self.assertEqual(blocked["state"], "QUEUED")
        with self.worker.lock:
            claims = self.worker.store.db.execute("SELECT resource FROM claims WHERE attempt=?", (result["attempt"],)).fetchall()
        self.assertIn("rendered", {row[0] for row in claims})

    def test_canceled_preparation_acknowledges_nonexecution(self):
        self.worker.draining = True
        accepted = self._submit("cancel-materialization")
        attempt = self.worker.store.allocate(accepted["job"], {"rendered": 1}, {"rendered": 1})
        real_copy = shutil.copytree

        def cancel_at_copy(original, target, **options):
            with self.worker.lock:
                self.worker.store.cancel(accepted["job"])
            return real_copy(original, target, **options)

        with mock.patch("tools.testqueue.worker.shutil.copytree", side_effect=cancel_at_copy), mock.patch.object(processes, "OwnedProcess") as process:
            self.worker.execute(accepted["job"], attempt)
        process.assert_not_called()
        status = self._status(accepted["job"])
        self.assertEqual(status.get("outcome"), "CANCELED", status)
        self.assertEqual(status.get("cleanup"), "CONFIRMED")
        self.assertEqual(self.worker.store.db.execute("SELECT COUNT(*) FROM claims").fetchone()[0], 0)

    def test_external_simulator_appearing_during_preparation_prevents_start(self):
        self.worker.draining = True
        accepted = self._submit("late-external", headless=True)
        attempt = self.worker.store.allocate(accepted["job"], {"headless": 1}, {"headless": 1})
        self.worker.fixture = False
        self.worker.engine_identity = {"binaries_sha256": {}}
        with mock.patch("tools.testqueue.worker.external_simulators", return_value=[98765]), mock.patch.object(processes, "OwnedProcess") as process:
            self.worker.execute(accepted["job"], attempt)
        process.return_value.start.assert_not_called()
        status = self._status(accepted["job"])
        self.assertEqual(status.get("outcome"), "INFRA_FAILED", status)
        self.assertEqual(status.get("cleanup"), "CONFIRMED")
        self.assertIn("EXTERNAL_SIMULATOR", status["error"])


if __name__ == "__main__":
    unittest.main()
