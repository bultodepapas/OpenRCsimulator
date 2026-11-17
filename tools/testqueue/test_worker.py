"""Local scheduling and lifecycle checks using real owned fake processes.

These fixtures do not launch Godot or qualify a graphical platform adapter.
"""
from __future__ import annotations

import contextlib
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
from types import SimpleNamespace

from tools.testqueue import processes, snapshots, worker as worker_module
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
    "source": os.getcwd(), "profile": os.environ["APPDATA"], "temp": os.environ["TEMP"],
    "import_timeout": os.environ.get("OPENRC_IMPORT_TIMEOUT")}))

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
    failed = owner.endswith("-failed")
    (directory / "verdict.json").write_text(json.dumps({"ok": not failed, "complete": True}))
    (directory / "launcher-returning").write_text("yes")
    sys.exit(7 if failed else 0)

if owner.startswith(("headless", "capture-shared")):
    (root / ("parallel-" + owner + ".ready")).write_text("yes")
    until = time.monotonic() + 8
    while len(list(root.glob("parallel-*.ready"))) < 2 and time.monotonic() < until:
        time.sleep(0.02)
    (directory / "barrier.json").write_text(json.dumps({"joined": len(list(root.glob("parallel-*.ready"))) >= 2}))
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
        self.worker = Worker(self.base / "worker", self.repo, Path(sys.executable), slots=2, capture_slots=2, fixture=True)
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

    @contextlib.contextmanager
    def _owned_view(self):
        """Stable view of owned processes: the worker's lock order, storage first."""
        with self.worker.lock, self.worker._process_lock:
            yield

    def _call(self, operation, **args):
        return self.worker.dispatch({"auth": self.worker.auth, "operation": operation, **args})

    def _submit(self, owner, *, headless=False, capture=False, timeout=40):
        preset = "aircraft-screenshot" if capture else "checked" if headless else "debug-session"
        options = {"headless": headless, "timeout": timeout}
        if capture:
            options["aircraft"] = "fixture-plane"
        elif headless:
            options.update(script="res://tests/test_fixture.gd", workload="functional")
        result = self._call("submit", owner=owner, preset=preset, options=options,
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

    def test_suite_import_timeout_is_bounded_before_admission(self):
        # Keep this isolated authority drained: these requests must never launch an adapter.
        self.worker.draining = True
        full_snapshot = self.base / "full-scope"
        snapshots.capture(self.repo, full_snapshot, scope=("app", "tools", "research", "assets", "site", "docs", ".github"))

        def submit(value, preset="suite"):
            return self._call("submit", owner="timeout-fixture", preset=preset, options={},
                              source=str(self.repo), snapshot=str(full_snapshot),
                              request_id=uuid.uuid4().hex, request_secret=uuid.uuid4().hex,
                              environment={"OPENRC_IMPORT_TIMEOUT": value})

        for preset in ("suite", "ci"):
            for value in ("1", "600", "1800", "0001"):
                with self.subTest(preset=preset, value=value):
                    accepted = submit(value, preset)
                    self.assertEqual(self._status(accepted["job"])["payload"]["environment"]["OPENRC_IMPORT_TIMEOUT"], value)
                    self._call("cancel", handle=accepted["handle"])
        for value in ("", "0", "1801", "10000", "-1", "1.0", "1e2", "９", "9" * 10000):
            with self.subTest(value=value[:12]):
                with self.assertRaisesRegex(ValueError, "OPENRC_IMPORT_TIMEOUT"):
                    submit(value)
        with self.assertRaisesRegex(ValueError, "only suite partition environment"):
            submit("600", "debug-session")

    def test_suite_timeout_comes_from_the_recorded_request_not_worker_environment(self):
        full_snapshot = self.base / "full-scope"
        snapshots.capture(self.repo, full_snapshot, scope=("app", "tools", "research", "assets", "site", "docs", ".github"))
        with mock.patch.dict(os.environ, {"OPENRC_IMPORT_TIMEOUT": "1800"}):
            for supplied, expected in (({}, None), ({"OPENRC_IMPORT_TIMEOUT": "123"}, "123")):
                with self.subTest(supplied=supplied):
                    accepted = self._call("submit", owner="timeout-fixture", preset="suite", options={"timeout": 20},
                                          source=str(self.repo), snapshot=str(full_snapshot), environment=supplied,
                                          request_id=uuid.uuid4().hex, request_secret=uuid.uuid4().hex)
                    self.handles.append(accepted)
                    status = self._finish(accepted["job"])
                    self.assertEqual(status.get("outcome"), "PASSED", status)
                    directory = self.worker.root / "attempts" / status["attempt"]
                    started = json.loads((directory / "started.json").read_text(encoding="utf-8"))
                    self.assertEqual(started["import_timeout"], expected)
                    self.assertEqual(status["payload"]["environment"], supplied)

    @unittest.skipUnless(os.name == "nt", "Windows materialized file attributes")
    def test_materialization_preserves_frozen_windows_attributes(self):
        # A destination directory can inherit different indexing attributes from
        # the immutable source store. Both file choices must survive copytree.
        expected = {}
        for name, attributes in (("indexed", 0x20), ("not-indexed", 0x2020)):
            relative = f"app/{name}.gd"
            self._write(relative, "unchanged source bytes\n")
            path = self.repo / relative
            metadata = path.stat()
            snapshots._set_metadata(path, SimpleNamespace(
                st_atime_ns=metadata.st_atime_ns, st_mtime_ns=metadata.st_mtime_ns,
                st_mode=metadata.st_mode, st_file_attributes=attributes))
            expected[relative] = attributes
        self.snapshot = self.base / "frozen-attributes"
        manifest = snapshots.capture(self.repo, self.snapshot, scope=("app", "tools"))
        for relative, attributes in expected.items():
            self.assertEqual(manifest["files"][relative]["windows_attributes"], attributes)
        result = self._finish(self._submit("metadata")['job'])
        self.assertEqual(result["outcome"], "PASSED", result)
        self.assertEqual(result["cleanup"], "CONFIRMED", result)
        directory = self.worker.root / "attempts" / result["attempts"][-1]["id"]
        for relative, attributes in expected.items():
            self.assertEqual((directory / "source" / relative).stat().st_file_attributes, attributes)
        self.assertTrue(snapshots.verify(directory)["ok"])

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
            with self._owned_view():
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
        self._assert_parallel_attempts(jobs)

    def test_two_studio_capture_jobs_overlap_with_independent_writable_state(self):
        jobs = [self._submit(f"capture-shared-{index}", capture=True) for index in range(2)]
        self._assert_parallel_attempts(jobs)

    def test_studio_capture_and_functional_check_can_overlap(self):
        jobs = [self._submit("capture-shared-0", capture=True), self._submit("headless-0", headless=True)]
        self._assert_parallel_attempts(jobs)

    def _assert_parallel_attempts(self, jobs):
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

    def test_expected_snapshot_identity_rejects_replacement_and_preserves_recovery(self):
        self.worker.draining = True
        original = json.loads((self.snapshot / "manifest.json").read_text(encoding="utf-8"))
        self._write("app/project.godot", "[application]\nconfig/name=\"replacement\"\n")
        replacement = self.base / "replacement"
        other = snapshots.capture(self.repo, replacement, scope=("app", "tools"))
        self.assertNotEqual(original["source_digest"], other["source_digest"])
        request = dict(owner="expected-identity", preset="debug-session", options={}, source=str(self.repo),
                       snapshot=str(self.snapshot), request_id=uuid.uuid4().hex, request_secret=uuid.uuid4().hex,
                       expected_source_digest=original["source_digest"],
                       expected_manifest_digest=original["manifest_digest"])
        rejected = {**request, "snapshot": str(replacement)}
        with self.assertRaisesRegex(ValueError, "SNAPSHOT_MISMATCH"):
            self._call("submit", **rejected)
        self.assertIsNone(self._call("recover", request_id=request["request_id"], request_secret=request["request_secret"]))
        for field in ("expected_source_digest", "expected_manifest_digest"):
            for bad in (None, "", "A" * 64, "z" * 64, "0" * 63, 123):
                with self.subTest(field=field, bad=bad), self.assertRaisesRegex(ValueError, field):
                    self._call("submit", **{**request, field: bad})
        accepted = self._call("submit", **request)
        self.handles.append(accepted)
        self.assertEqual(self._call("submit", **request), accepted)
        with self.assertRaisesRegex(ValueError, "SNAPSHOT_MISMATCH"):
            self._call("submit", **rejected)
        receipt = self.snapshot / "manifest.json"
        unavailable = self.snapshot / "manifest.unavailable"
        receipt.rename(unavailable)
        try:
            recovered = self._call("recover", request_id=request["request_id"], request_secret=request["request_secret"])
        finally:
            unavailable.rename(receipt)
        self.assertEqual(recovered, {key: accepted[key] for key in ("job", "handle")})
        self.assertEqual(self._status(accepted["job"])["payload"]["manifest"]["source_digest"], original["source_digest"])

    def test_submit_uses_verified_object_when_receipt_is_swapped_after_verification(self):
        self.worker.draining = True
        original_bytes = (self.snapshot / "manifest.json").read_bytes()
        original = json.loads(original_bytes)
        self._write("app/project.godot", "[application]\nconfig/name=\"replacement\"\n")
        replacement = self.base / "replacement"
        snapshots.capture(self.repo, replacement, scope=("app", "tools"))
        replacement_bytes = (replacement / "manifest.json").read_bytes()
        real_verify = snapshots.verify

        def verify_then_swap(path, **kwargs):
            result = real_verify(path, **kwargs)
            (Path(path) / "manifest.json").write_bytes(replacement_bytes)
            return result

        request = dict(owner="receipt-race", preset="debug-session", options={}, source=str(self.repo),
                       snapshot=str(self.snapshot), request_id=uuid.uuid4().hex, request_secret=uuid.uuid4().hex,
                       expected_source_digest=original["source_digest"],
                       expected_manifest_digest=original["manifest_digest"])
        try:
            with mock.patch.object(snapshots, "verify", side_effect=verify_then_swap):
                accepted = self._call("submit", **request)
            recorded = self._status(accepted["job"])["payload"]["manifest"]
            self.assertEqual(recorded["manifest_digest"], original["manifest_digest"])
            self.assertEqual(recorded["source_digest"], original["source_digest"])
        finally:
            (self.snapshot / "manifest.json").write_bytes(original_bytes)
        self.assertEqual(self._call("recover", request_id=request["request_id"], request_secret=request["request_secret"])["job"], accepted["job"])

    def test_forged_scope_with_copied_digest_strings_cannot_widen_admission(self):
        self.worker.draining = True
        path = self.snapshot / "manifest.json"
        original_bytes = path.read_bytes()
        forged = json.loads(original_bytes)
        forged["scope"] = ["app", "tools", "research", "assets", "site", "docs", ".github"]
        real_verify = snapshots.verify

        def verify_then_forge(snapshot, **kwargs):
            report = real_verify(snapshot, **kwargs)
            path.write_text(json.dumps(forged), encoding="utf-8")
            return report

        request = dict(owner="forged-scope", preset="suite", options={}, source=str(self.repo),
                       snapshot=str(self.snapshot), request_id=uuid.uuid4().hex, request_secret=uuid.uuid4().hex)
        try:
            with mock.patch.object(snapshots, "verify", side_effect=verify_then_forge):
                with self.assertRaisesRegex(ValueError, "full repository snapshot"):
                    self._call("submit", **request)
            self.assertFalse(real_verify(self.snapshot)["ok"])
        finally:
            path.write_bytes(original_bytes)
        self.assertIsNone(self._call("recover", request_id=request["request_id"], request_secret=request["request_secret"]))

    def test_engine_pin_policy_read_is_bound_to_the_verified_file(self):
        self.worker.draining = True
        self._write("app/get-godot.sh", "ENGINE_VERSION=original\n")
        self.snapshot = self.base / "pin-snapshot"
        snapshots.capture(self.repo, self.snapshot, scope=("app", "tools"))
        path = self.snapshot / "source/app/get-godot.sh"
        original = path.read_bytes()
        metadata = path.stat()
        real_verify = snapshots.verify

        def verify_then_swap(snapshot, **kwargs):
            report = real_verify(snapshot, **kwargs)
            path.write_bytes(b"ENGINE_VERSION=substituted\n")
            return report

        try:
            with mock.patch.object(self.worker, "fixture", False), \
                    mock.patch.object(snapshots, "verify", side_effect=verify_then_swap), \
                    mock.patch.object(self.worker, "_check_engine_pin") as check_pin:
                with self.assertRaisesRegex(ValueError, "policy input differs"):
                    self._submit("substituted-pin", headless=True)
                check_pin.assert_not_called()
        finally:
            path.write_bytes(original)
            os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
        self.assertTrue(snapshots.verify(self.snapshot)["ok"])

    def test_replacing_queued_snapshot_with_another_valid_snapshot_never_executes(self):
        self.worker.draining = True
        accepted = self._submit("queued-snapshot-replacement")
        recorded = self._status(accepted["job"])["payload"]["manifest"]
        self._write("app/project.godot", "[application]\nconfig/name=\"replacement\"\n")
        replacement = self.base / "replacement"
        replacement_receipt = snapshots.capture(self.repo, replacement, scope=("app", "tools"))
        self.assertNotEqual(recorded["source_digest"], replacement_receipt["source_digest"])
        shutil.rmtree(self.snapshot)
        replacement.rename(self.snapshot)
        self.assertTrue(snapshots.verify(self.snapshot)["ok"])
        fixture_identity = {"host": str(uuid.uuid4()), "boot": "fixture-boot"}
        with mock.patch.object(processes, "host_identity", return_value=fixture_identity), \
                mock.patch.object(processes.subprocess, "Popen") as popen:
            self.worker.draining = False
            status = self._finish(accepted["job"])
        popen.assert_not_called()
        self.assertEqual(status["state"], "FINISHED", status)
        self.assertEqual(status["outcome"], "INFRA_FAILED", status)
        self.assertEqual(status["cleanup"], "CONFIRMED", status)
        self.assertIn("snapshot", status["error"])
        with self.worker.lock:
            self.assertEqual(self.worker.store.db.execute("SELECT COUNT(*) FROM claims").fetchone()[0], 0)

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

    def test_cleanup_uncertainty_and_failed_unknown_write_fence_compatible_work(self):
        self.worker.draining = True
        first = self._submit("cleanup-storage-failure", headless=True)
        real_close = processes.OwnedProcess.close
        real_event = self.worker.store.event
        fail_unknown, unknown_write = threading.Event(), threading.Event()
        fail_unknown.set()

        def lose_cleanup_proof(process):
            real_close(process)
            raise RuntimeError("injected cleanup uncertainty")

        def fail_unknown_event(job, event, data=None):
            if event == "UNKNOWN" and fail_unknown.is_set():
                unknown_write.set()
                raise sqlite3.OperationalError("injected UNKNOWN journal failure")
            return real_event(job, event, data)

        with mock.patch.object(processes.OwnedProcess, "close", new=lose_cleanup_proof), \
                mock.patch.object(self.worker.store, "event", side_effect=fail_unknown_event), \
                mock.patch.object(threading, "excepthook"):
            self.worker.draining = False
            self.assertTrue(unknown_write.wait(10))
            second = self._submit("fits-without-global-quarantine", headless=True)
            time.sleep(0.35)
            status = self._status(first["job"])
            self.assertEqual(status["state"], "RUNNING", status)
            self.assertNotEqual(status.get("cleanup"), "CONFIRMED", status)
            self.assertEqual(self._status(second["job"])["attempts"], [])
            host = self._call("hosts")
            self.assertEqual(host["condition"], "DEGRADED", host)
            self.assertEqual(host["pending_quarantines"], 1)
            with self.worker.lock:
                self.assertGreater(self.worker.store.db.execute(
                    "SELECT COUNT(*) FROM claims WHERE attempt=?", (status["attempt"],)).fetchone()[0], 0)
                self.assertGreater(self.worker.capacities["headless"], self.worker.store.db.execute(
                    "SELECT COALESCE(SUM(amount),0) FROM claims WHERE resource='headless'").fetchone()[0])
            fail_unknown.clear()
            result = self._finish(first["job"])
            self.assertEqual(result["state"], "UNKNOWN", result)
            self.assertNotEqual(result.get("cleanup"), "CONFIRMED", result)
            blocked = wait_until(lambda: (item if (item := self._status(second["job"]))["reason"].startswith("RESOURCE_BUSY") else None))
            self.assertEqual(blocked["attempts"], [])
            self.assertEqual(self._call("hosts")["pending_quarantines"], 0)

    def _check_execution_thread_start_failure(self, *, after_spawn):
        self.worker.draining = True
        first = self._submit("thread-start-failure", headless=True)
        gate_entered, spawned = threading.Event(), []
        real_start = threading.Thread.start
        real_allowed = worker_module._LaunchGate.allowed

        def observe_gate(gate):
            gate_entered.set()
            return real_allowed(gate)

        def fail_start(thread):
            if thread.name.startswith("openrc-attempt-"):
                if after_spawn:
                    real_start(thread)
                    spawned.append(thread)
                    if not gate_entered.wait(5):
                        raise AssertionError("spawned thread did not reach the launch gate")
                raise RuntimeError("injected execution thread start failure")
            return real_start(thread)

        fixture_identity = {"host": str(uuid.uuid4()), "boot": "fixture-boot"}
        with mock.patch.object(processes, "host_identity", return_value=fixture_identity), \
                mock.patch.object(processes.subprocess, "Popen") as popen, \
                mock.patch.object(worker_module._LaunchGate, "allowed", new=observe_gate), \
                mock.patch.object(threading.Thread, "start", new=fail_start):
            self.worker.draining = False
            result = self._finish(first["job"])
        popen.assert_not_called()
        if after_spawn:
            self.assertTrue(gate_entered.is_set(), "spawned thread did not enter the launch gate")
        for thread in spawned:
            thread.join(timeout=5)
            self.assertFalse(thread.is_alive())
        self.assertEqual(result["state"], "FINISHED", result)
        self.assertEqual(result["outcome"], "INFRA_FAILED", result)
        self.assertEqual(result["launch"], "NOT_CREATED", result)
        self.assertEqual(result["nonlaunch"], "CONFIRMED", result)
        self.assertEqual(result["cleanup"], "CONFIRMED", result)
        self.assertFalse((self.worker.root / "attempts" / result["attempt"]).exists())
        with self.worker.lock:
            self.assertEqual(self.worker.store.db.execute("SELECT COUNT(*) FROM claims").fetchone()[0], 0)
        later = self._submit("after-thread-start-failure", headless=True)
        self.assertEqual(self._finish(later["job"])["outcome"], "PASSED")

    def test_thread_start_error_proves_nonlaunch(self):
        self._check_execution_thread_start_failure(after_spawn=False)

    def test_thread_start_then_error_denies_the_spawned_thread(self):
        self._check_execution_thread_start_failure(after_spawn=True)

    def test_thread_start_failure_fences_until_nonlaunch_is_durable(self):
        self.worker.draining = True
        first = self._submit("thread-start-journal-failure", headless=True)
        fail_write, write_attempted, gate_entered = threading.Event(), threading.Event(), threading.Event()
        fail_write.set()
        real_start, real_event = threading.Thread.start, self.worker.store.event
        real_allowed, real_process_start = worker_module._LaunchGate.allowed, processes.OwnedProcess.start
        injected, process_starts = [], []
        failed_writes = []

        def observe_gate(gate):
            gate_entered.set()
            return real_allowed(gate)

        def fail_first_start(thread):
            if thread.name.startswith("openrc-attempt-") and not injected:
                injected.append(thread)
                real_start(thread)
                if not gate_entered.wait(5):
                    raise AssertionError("spawned thread did not reach the launch gate")
                raise RuntimeError("injected execution thread start failure")
            return real_start(thread)

        def observe_process_start(process):
            process_starts.append(process.log.parent.name)
            return real_process_start(process)

        def fail_nonlaunch_event(job, event, data=None):
            if event == "FINISHED" and data.get("nonlaunch") == "CONFIRMED" and fail_write.is_set():
                failed_writes.append(job)
                write_attempted.set()
                raise sqlite3.OperationalError("injected nonlaunch journal failure")
            return real_event(job, event, data)

        with mock.patch.object(worker_module._LaunchGate, "allowed", new=observe_gate), \
                mock.patch.object(processes.OwnedProcess, "start", new=observe_process_start), \
                mock.patch.object(threading.Thread, "start", new=fail_first_start), \
                mock.patch.object(self.worker.store, "event", side_effect=fail_nonlaunch_event):
            self.worker.draining = False
            self.assertTrue(write_attempted.wait(5))
            self.assertTrue(gate_entered.is_set(), "spawned thread did not enter the launch gate")
            second = self._submit("after-nonlaunch-journal-recovery", headless=True)
            wait_until(lambda: len(failed_writes) >= 2, timeout=5)
            held = self._status(first["job"])
            self.assertEqual(held["state"], "DISPATCHING", held)
            self.assertNotEqual(held.get("cleanup"), "CONFIRMED", held)
            self.assertEqual(self._status(second["job"])["attempts"], [])
            self.assertEqual(process_starts, [])
            self.assertEqual(self._call("hosts")["pending_quarantines"], 1)
            with self.worker.lock:
                self.assertGreater(self.worker.store.db.execute(
                    "SELECT COUNT(*) FROM claims WHERE attempt=?", (held["attempts"][-1]["id"],)).fetchone()[0], 0)
                self.assertGreater(self.worker.capacities["headless"], self.worker.store.db.execute(
                    "SELECT COALESCE(SUM(amount),0) FROM claims WHERE resource='headless'").fetchone()[0])
            fail_write.clear()
            result = self._finish(first["job"])
            self.assertEqual(result["state"], "FINISHED", result)
            self.assertEqual(result["outcome"], "INFRA_FAILED", result)
            self.assertEqual(result["nonlaunch"], "CONFIRMED", result)
            self.assertEqual(result["cleanup"], "CONFIRMED", result)
            self.assertEqual(self._finish(second["job"])["outcome"], "PASSED")
            self.assertEqual(len(process_starts), 1)
            self.assertNotEqual(process_starts[0], held["attempts"][-1]["id"])
            self.assertEqual(self._call("hosts")["pending_quarantines"], 0)
        injected[0].join(timeout=5)
        self.assertFalse(injected[0].is_alive())

    def test_log_failure_proves_nonlaunch_and_next_job_runs(self):
        self.worker.draining = True
        first = self._submit("log-failure")
        real_open = Path.open

        def fail_worker_log(path, *args, **kwargs):
            if path.name == "worker.log":
                raise PermissionError("injected log open failure")
            return real_open(path, *args, **kwargs)

        fixture_identity = {"host": str(uuid.uuid4()), "boot": "fixture-boot"}
        with mock.patch.object(processes, "host_identity", return_value=fixture_identity), \
                mock.patch.object(Path, "open", new=fail_worker_log), \
                mock.patch.object(processes.subprocess, "Popen") as popen:
            self.worker.draining = False
            result = self._finish(first["job"])
        popen.assert_not_called()
        self.assertEqual(result["state"], "FINISHED", result)
        self.assertEqual(result["outcome"], "INFRA_FAILED", result)
        self.assertEqual(result["cleanup"], "CONFIRMED", result)
        self.assertEqual(result["launch"], "NOT_CREATED", result)
        self.assertEqual(result["nonlaunch"], "CONFIRMED", result)
        with self.worker.lock:
            self.assertEqual(self.worker.store.db.execute("SELECT COUNT(*) FROM claims").fetchone()[0], 0)
        second = self._submit("after-log-failure")
        following = self._finish(second["job"])
        self.assertEqual(following.get("outcome"), "PASSED", following)

    def test_lost_creation_result_even_with_receipt_exception_quarantines(self):
        self.worker.draining = True
        first = self._submit("uncertain-create")
        created = []
        real_popen = processes.subprocess.Popen

        def create_then_raise(*args, **kwargs):
            created.append(real_popen(*args, **kwargs))
            # An exception type can also escape from inside process creation;
            # it must not impersonate this adapter's pre-create receipt.
            raise processes.ProcessNotStartedError("injected lost creation result")

        def cleanup_owned_gates():
            for gate in created:
                if gate.stdin and not gate.stdin.closed:
                    gate.stdin.close()
                try:
                    gate.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    gate.kill()
                    gate.wait(timeout=5)

        self.addCleanup(cleanup_owned_gates)
        fixture_identity = {"host": str(uuid.uuid4()), "boot": "fixture-boot"}
        with mock.patch.object(processes, "host_identity", return_value=fixture_identity), \
                mock.patch.object(processes.subprocess, "Popen", side_effect=create_then_raise) as popen:
            self.worker.draining = False
            result = self._finish(first["job"])
        popen.assert_called_once()
        self.assertEqual(len(created), 1)
        self.assertIsNone(created[0].poll(), "the task-owned gate is still alive")
        self.assertEqual(result["state"], "UNKNOWN", result)
        self.assertEqual(result["launch"], "CREATION_UNCERTAIN", result)
        self.assertNotEqual(result.get("nonlaunch"), "CONFIRMED", result)
        self.assertNotEqual(result.get("cleanup"), "CONFIRMED", result)
        second = self._submit("blocked-after-uncertain-create")
        blocked = wait_until(lambda: (status if (status := self._status(second["job"]))["reason"].startswith("RESOURCE_BUSY") else None))
        self.assertEqual(blocked["state"], "QUEUED", blocked)
        self.assertEqual(blocked["attempts"], [])
        with self.worker.lock:
            self.assertGreater(self.worker.store.db.execute("SELECT COUNT(*) FROM claims WHERE attempt=?", (result["attempt"],)).fetchone()[0], 0)

    def test_lost_start_ack_after_identity_does_not_release_claims(self):
        self.worker.draining = True
        first = self._submit("long-ambiguous-start")
        started = []
        real_start = processes.OwnedProcess.start

        def lose_ack(process):
            real_start(process)
            started.append(process)
            raise RuntimeError("injected lost launch acknowledgement")

        def cleanup_owned_process():
            for process in started:
                process.close()

        self.addCleanup(cleanup_owned_process)
        with mock.patch.object(processes.OwnedProcess, "start", new=lose_ack):
            self.worker.draining = False
            result = self._finish(first["job"])
        self.assertEqual(len(started), 1)
        self.assertIsNotNone(started[0].identity)
        self.assertEqual(result["state"], "UNKNOWN", result)
        self.assertEqual(result["launch"], "CREATION_UNCERTAIN", result)
        self.assertNotEqual(result.get("cleanup"), "CONFIRMED", result)
        second = self._submit("blocked-after-lost-ack")
        blocked = wait_until(lambda: (status if (status := self._status(second["job"]))["reason"].startswith("RESOURCE_BUSY") else None))
        self.assertEqual(blocked["state"], "QUEUED", blocked)
        self.assertEqual(blocked["attempts"], [])
        with self.worker.lock:
            self.assertGreater(self.worker.store.db.execute("SELECT COUNT(*) FROM claims WHERE attempt=?", (result["attempt"],)).fetchone()[0], 0)

    def test_ambiguous_start_fences_admission_before_unknown_is_recorded(self):
        self.worker.draining = True
        first = self._submit("uncertain-race", headless=True)
        handling, release = threading.Event(), threading.Event()

        class PausedStartError(RuntimeError):
            def __str__(self):
                handling.set()
                if not release.wait(5):
                    raise RuntimeError("test did not release exception handling")
                return "injected ambiguous start"

        try:
            with mock.patch.object(processes.OwnedProcess, "start", side_effect=PausedStartError()):
                self.worker.draining = False
                self.assertTrue(handling.wait(5))
                second = self._submit("would-fit-before-quarantine", headless=True)
                time.sleep(0.35)
                self.assertEqual(self._status(first["job"])["state"], "RUNNING")
                self.assertEqual(self._status(second["job"])["attempts"], [])
                host = self._call("hosts")
                self.assertEqual(host["condition"], "DEGRADED", host)
                self.assertEqual(host["pending_quarantines"], 1)
        finally:
            release.set()
        result = self._finish(first["job"])
        self.assertEqual(result["state"], "UNKNOWN", result)
        blocked = wait_until(lambda: (status if (status := self._status(second["job"]))["reason"].startswith("RESOURCE_BUSY") else None))
        self.assertEqual(blocked["state"], "QUEUED", blocked)
        self.assertEqual(blocked["attempts"], [])

    def test_start_thread_exit_is_persisted_as_unknown(self):
        self.worker.draining = True
        first = self._submit("uncertain-thread-exit", headless=True)
        with mock.patch.object(processes.OwnedProcess, "start", side_effect=SystemExit("injected start exit")):
            self.worker.draining = False
            result = self._finish(first["job"])
        self.assertEqual(result["state"], "UNKNOWN", result)
        self.assertEqual(result["launch"], "CREATION_UNCERTAIN", result)
        second = self._submit("blocked-after-start-exit", headless=True)
        blocked = wait_until(lambda: (status if (status := self._status(second["job"]))["reason"].startswith("RESOURCE_BUSY") else None))
        self.assertEqual(blocked["attempts"], [])

    def test_failed_unknown_write_blocks_admission_until_quarantine_is_durable(self):
        self.worker.draining = True
        first = self._submit("uncertain-write", headless=True)
        fail_writes, attempted = threading.Event(), threading.Event()
        fail_writes.set()
        real_update = self.worker.store.update

        def fail_unknown(job, attempt, state, data):
            if state == "UNKNOWN" and fail_writes.is_set():
                attempted.set()
                raise sqlite3.OperationalError("injected quarantine write failure")
            return real_update(job, attempt, state, data)

        # The execute thread's failed write is expected; the pending record is
        # retried by the existing scheduler while new admission stays fenced.
        with mock.patch.object(processes.OwnedProcess, "start", side_effect=RuntimeError("injected ambiguous start")), \
                mock.patch.object(self.worker.store, "update", side_effect=fail_unknown), \
                mock.patch.object(threading, "excepthook"):
            self.worker.draining = False
            self.assertTrue(attempted.wait(5))
            second = self._submit("blocked-until-durable", headless=True)
            degraded = wait_until(lambda: (host if (host := self._call("hosts"))["condition"] == "DEGRADED" else None))
            self.assertEqual(degraded["pending_quarantines"], 1, degraded)
            self.assertEqual(self._status(second["job"])["attempts"], [])
            fail_writes.clear()
            result = self._finish(first["job"])
            self.assertEqual(result["state"], "UNKNOWN", result)
            blocked = wait_until(lambda: (status if (status := self._status(second["job"]))["reason"].startswith("RESOURCE_BUSY") else None))
            self.assertEqual(blocked["attempts"], [])
            self.assertEqual(self._call("hosts")["pending_quarantines"], 0)

    def test_preallocated_attempt_waits_before_launch_during_quarantine(self):
        self.worker.draining = True
        first = self._submit("preallocated-uncertain", headless=True)
        second = self._submit("preallocated-waiting", headless=True)
        with self.worker.lock:
            attempts = []
            for submission in (first, second):
                resources = self._status(submission["job"])["scheduling"]["resources"]
                attempt = self.worker.store.allocate(submission["job"], resources, self.worker.capacities)
                self.assertIsNotNone(attempt)
                self.worker.active[attempt] = None
                attempts.append(attempt)

        handling, release, second_started = threading.Event(), threading.Event(), threading.Event()
        real_start = processes.OwnedProcess.start

        class PausedStartError(RuntimeError):
            def __str__(self):
                handling.set()
                if not release.wait(5):
                    raise RuntimeError("test did not release exception handling")
                return "injected ambiguous start"

        def controlled_start(process):
            if process.log.parent.name == attempts[0]:
                raise PausedStartError()
            second_started.set()
            return real_start(process)

        threads = []
        try:
            with mock.patch.object(processes.OwnedProcess, "start", new=controlled_start):
                first_thread = threading.Thread(target=self.worker.execute, args=(first["job"], attempts[0]))
                threads.append(first_thread)
                first_thread.start()
                self.assertTrue(handling.wait(5))
                second_thread = threading.Thread(target=self.worker.execute, args=(second["job"], attempts[1]))
                threads.append(second_thread)
                second_thread.start()
                directory = self.worker.root / "attempts" / attempts[1]
                wait_until(lambda: (directory / "request.json").exists())
                time.sleep(0.3)
                self.assertFalse(second_started.is_set())
                self.assertEqual(self._status(second["job"])["state"], "DISPATCHING")
                release.set()
                self.assertEqual(self._finish(first["job"])["state"], "UNKNOWN")
                time.sleep(0.2)
                self.assertFalse(second_started.is_set())
                self._call("cancel", handle=second["handle"])
                canceled = self._finish(second["job"])
                self.assertEqual(canceled.get("outcome"), "CANCELED", canceled)
                self.assertEqual(canceled.get("cleanup"), "CONFIRMED", canceled)
                self.assertFalse(second_started.is_set())
        finally:
            release.set()
            for thread in threads:
                thread.join(timeout=5)

    def test_scheduler_recovers_after_operation_and_diagnostic_both_fail(self):
        live = self._submit("long-scheduler", headless=True)
        directory = wait_until(lambda: (candidate if (candidate := self._directory(live["job"]))
                               and (candidate / "started.json").exists() else None))
        original = self._status(live["job"])
        attempt = original["attempt"]
        with self._owned_view():
            owned = self.worker.active[attempt]
            original_claims = self.worker.store.db.execute("SELECT resource,amount FROM claims WHERE attempt=? ORDER BY resource", (attempt,)).fetchall()
            self.assertTrue(owned.alive())
        initial = wait_until(lambda: (host if (host := self._call("hosts"))["condition"] == "READY" else None))
        self.assertIsNotNone(initial["scheduler"]["last_dispatch"])
        failures, diagnostics, recovery_attempts = threading.Event(), threading.Event(), threading.Event()
        fail_schedule, fail_storage = threading.Event(), threading.Event()
        fail_schedule.set()
        fail_storage.set()
        real_schedule_once = self.worker.schedule_once
        real_event = self.worker.store.event

        def scheduler_failure():
            if fail_schedule.is_set():
                failures.set()
                raise sqlite3.OperationalError("injected scheduler storage failure")
            return real_schedule_once()

        def diagnostic_failure(job, event, data=None):
            if event in {"SCHEDULER_ERROR", "SCHEDULER_RECOVERY_CHECK"} and fail_storage.is_set():
                if event == "SCHEDULER_ERROR":
                    diagnostics.set()
                else:
                    recovery_attempts.set()
                raise sqlite3.OperationalError("injected diagnostic storage failure")
            return real_event(job, event, data)

        with mock.patch.object(self.worker, "schedule_once", side_effect=scheduler_failure), \
                mock.patch.object(self.worker.store, "event", side_effect=diagnostic_failure):
            self.assertTrue(failures.wait(5))
            self.assertTrue(diagnostics.wait(5))
            degraded = wait_until(lambda: (host if (host := self._call("hosts"))["scheduler"]["diagnostic_error"] else None))
            self.assertEqual(degraded["condition"], "DEGRADED", degraded)
            self.assertEqual(degraded["scheduler"]["state"], "DEGRADED", degraded)
            self.assertEqual(degraded["scheduler"]["thread_id"], initial["scheduler"]["thread_id"])
            self.assertIn("diagnostic storage failure", degraded["scheduler"]["diagnostic_error"])
            later = self._submit("after-scheduler-fault", headless=True)
            # The scheduler operation can now succeed, but a read-only scan is
            # not enough to advertise recovery while durable writes still fail.
            fail_schedule.clear()
            self.assertTrue(recovery_attempts.wait(5))
            self.assertEqual(self._call("hosts")["condition"], "DEGRADED")
            self.assertEqual(self._status(later["job"])["state"], "QUEUED")
            self.assertTrue(self.scheduler.is_alive())
            with self._owned_view():
                self.assertIs(self.worker.active[attempt], owned)
                self.assertTrue(owned.alive())
                self.assertEqual(self.worker.store.db.execute("SELECT resource,amount FROM claims WHERE attempt=? ORDER BY resource", (attempt,)).fetchall(), original_claims)
            fail_storage.clear()
        recovered = wait_until(lambda: (host if (host := self._call("hosts"))["condition"] == "READY" else None))
        self.assertEqual(recovered["scheduler"]["thread_id"], initial["scheduler"]["thread_id"])
        self.assertGreater(recovered["scheduler"]["last_heartbeat"], degraded["scheduler"]["last_heartbeat"])
        self.assertEqual(self._finish(later["job"])["outcome"], "PASSED")
        with self._owned_view():
            self.assertIs(self.worker.active[attempt], owned)
            self.assertTrue(owned.alive())
        self.assertTrue((directory / "started.json").exists())

    def test_stale_scheduler_is_degraded_without_starting_another(self):
        ready = wait_until(lambda: (host if (host := self._call("hosts"))["condition"] == "READY" else None))
        entered, release = threading.Event(), threading.Event()
        schedule_once = self.worker.schedule_once

        def hold_pass():
            entered.set()
            if not release.wait(5):
                raise RuntimeError("test did not release scheduler")
            schedule_once()

        try:
            with mock.patch.object(self.worker, "schedule_once", side_effect=hold_pass):
                self.assertTrue(entered.wait(5))
                with self.worker._scheduler_lock:
                    self.worker._scheduler_last_success_monotonic = time.monotonic() - 31
                stale = self._call("hosts")
                self.assertEqual(stale["condition"], "DEGRADED", stale)
                self.assertEqual(stale["scheduler"]["state"], "STALE", stale)
                self.assertEqual(stale["scheduler"]["thread_id"], ready["scheduler"]["thread_id"])
                with self.assertRaisesRegex(RuntimeError, "already started"):
                    self.worker.schedule()
        finally:
            release.set()
        recovered = wait_until(lambda: (host if (host := self._call("hosts"))["condition"] == "READY" else None))
        self.assertEqual(recovered["scheduler"]["thread_id"], ready["scheduler"]["thread_id"])

    def test_exited_scheduler_cannot_advertise_ready_or_be_duplicated(self):
        wait_until(lambda: (host if (host := self._call("hosts"))["condition"] == "READY" else None))
        with mock.patch.object(self.worker, "schedule_once", side_effect=SystemExit("injected thread exit")):
            self.scheduler.join(timeout=5)
        self.assertFalse(self.scheduler.is_alive())
        host = self._call("hosts")
        self.assertEqual(host["condition"], "DEGRADED", host)
        self.assertEqual(host["scheduler"]["state"], "STOPPED", host)
        with self.assertRaisesRegex(RuntimeError, "already started"):
            self.worker.schedule()

    def test_unavailable_claim_inventory_does_not_advertise_ready(self):
        wait_until(lambda: (host if (host := self._call("hosts"))["condition"] == "READY" else None))
        with self.worker.lock, mock.patch.object(self.worker.store, "db") as db:
            db.execute.side_effect = sqlite3.OperationalError("injected unavailable inventory")
            host = self._call("hosts")
        self.assertEqual(host["condition"], "DEGRADED", host)
        self.assertIsNone(host["claims"])
        self.assertIn("unavailable inventory", host["inventory_error"])
        self.assertEqual(host["scheduler"]["state"], "DEGRADED")

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

    def test_failed_adapter_cleans_its_surviving_child(self):
        accepted = self._submit("orphan-failed")
        status = self._finish(accepted["job"])
        self.assertEqual(status.get("outcome"), "TEST_FAILED", status)
        self.assertEqual(status.get("runner_exit_code"), 7)
        self.assertEqual(status.get("cleanup"), "CONFIRMED")
        directory = self.worker.root / "attempts" / status["attempt"]
        self.assertTrue((directory / "child-start.json").exists())
        self.assertFalse((directory / "child-end.json").exists())

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

    def test_operator_abandonment_requires_ownership_drain_and_absent_orphan(self):
        self.worker.draining = True
        accepted = self._submit("orphan")
        attempt = self.worker.store.allocate(accepted["job"], {"exclusive": 1}, {"exclusive": 1})
        self.worker.store.update(accepted["job"], attempt, "UNKNOWN", {"process": {"fixture": True}})
        with mock.patch.object(processes, "orphan_absent", return_value=True):
            with self.assertRaisesRegex(ValueError, "handle"):
                self._call("abandon", handle=accepted["job"] + ":wrong", reason="owner request")
            self.worker.draining = False
            with self.assertRaisesRegex(ValueError, "drained"):
                self._call("abandon", handle=accepted["handle"], reason="owner request")
            self.worker.draining = True
            for registry in (self.worker.active, self.worker.contexts):
                registry[attempt] = None
                with self.assertRaisesRegex(ValueError, "supervisor thread"):
                    self._call("abandon", handle=accepted["handle"], reason="owner request")
                registry.pop(attempt)
        with mock.patch.object(processes, "orphan_absent", return_value=False):
            with self.assertRaisesRegex(ValueError, "absence"):
                self._call("abandon", handle=accepted["handle"], reason="owner request")
        self.assertEqual(self._status(accepted["job"])["state"], "UNKNOWN")
        with mock.patch.object(processes, "orphan_absent", return_value=True):
            result = self._call("abandon", handle=accepted["handle"], reason="owner request")
        self.assertEqual(result["state"], "FINISHED")
        self.assertEqual(result["cleanup"], "UNCONFIRMED")
        self.assertEqual(result["outcome"], "INFRA_FAILED")

    def test_operator_abandonment_cannot_bypass_a_pending_attempt_journal(self):
        self.worker.draining = True
        accepted = self._submit("orphan-pending")
        with self.worker.lock:
            attempt = self.worker.store.allocate(accepted["job"], {"exclusive": 1}, {"exclusive": 1})
            data = {"process": {"fixture": True}, "cleanup": "UNCONFIRMED"}
            self.worker.store.update(accepted["job"], attempt, "UNKNOWN", data)
            with mock.patch.object(processes, "orphan_absent", return_value=True) as probe:
                registries = ((self.worker._unresolved_attempts, {attempt}),
                              (self.worker._pending_unknown, {attempt: (accepted["job"], data)}),
                              (self.worker._pending_nonlaunch, {attempt: (accepted["job"], data)}),
                              (self.worker._pending_journal, {attempt: (accepted["job"], "RUNNING", data)}),
                              (self.worker._closing, {attempt}))
                for registry, entry in registries:
                    registry.update(entry)
                    try:
                        with self.assertRaisesRegex(ValueError, "pending attempt journals"):
                            self._call("abandon", handle=accepted["handle"], reason="operator request")
                        self.assertTrue(self.worker.store.db.execute("SELECT 1 FROM claims WHERE attempt=?", (attempt,)).fetchone())
                        self.assertEqual(self._status(accepted["job"])["state"], "UNKNOWN")
                    finally:
                        registry.clear()
                probe.assert_not_called()

    def test_queued_studio_job_is_rechecked_after_authority_upgrade(self):
        self.worker.draining = True
        self._write("tools/readme/capture_aircraft.gd", "# old reviewed studio script\n")
        self.snapshot = self.base / "studio-snapshot"
        snapshots.capture(self.repo, self.snapshot, scope=("app", "tools"))
        accepted = self._submit("queued-studio", capture=True)
        attempt = self.worker.store.allocate(accepted["job"], {"rendered": 1}, {"rendered": 1})
        self.worker.studio_adapter_identity = self.worker._studio_identity(self.repo)
        self.worker.studio_adapter_identity["tools/testqueue/adapter.py"] = "upgraded-authority"
        self.worker.fixture = False
        self.worker.engine_identity = {"binaries_sha256": {}}
        with mock.patch.object(processes, "OwnedProcess") as process:
            self.worker.execute(accepted["job"], attempt)
        process.assert_not_called()
        status = self._status(accepted["job"])
        self.assertEqual(status.get("outcome"), "INFRA_FAILED")
        self.assertIn("ADAPTER_MISMATCH", status.get("error", ""))
        self.assertEqual(status.get("cleanup"), "CONFIRMED")

    # TQ-04 continuity: storage is observation, not ownership.

    def test_post_start_journal_failure_keeps_the_owned_process_running(self):
        # The 16 November reproduction tore this healthy process down and
        # reported INFRA_FAILED. The same injection must now leave it alone.
        real_update = self.worker.store.update
        injected = threading.Event()

        def fail_owned_journal_once(job, attempt, state, data):
            if state == "RUNNING" and data.get("launch") == "CREATED_OWNED" and not injected.is_set():
                injected.set()
                raise sqlite3.OperationalError("injected post-start journal failure")
            return real_update(job, attempt, state, data)

        with mock.patch.object(self.worker.store, "update", side_effect=fail_owned_journal_once):
            accepted = self._submit("poststart-storage", headless=True)
            result = self._finish(accepted["job"])
        self.assertTrue(injected.is_set())
        self.assertEqual(result["state"], "FINISHED", result)
        self.assertEqual(result.get("outcome"), "PASSED", result)
        self.assertEqual(result.get("cleanup"), "CONFIRMED", result)
        self.assertEqual(result.get("evidence"), "COMPLETE", result)
        self.assertNotIn("error", result)
        directory = self.worker.root / "attempts" / result["attempt"]
        self.assertTrue((directory / "ended.json").exists(), "owned workload did not complete normally")
        self.assertEqual(self._call("hosts")["pending_journals"], 0)

    def test_hard_deadline_is_enforced_while_the_monitor_hangs_in_storage(self):
        # A call that hangs (rather than fails) inside the CREATED_OWNED journal,
        # while holding the worker lock, must not suspend the admitted budget.
        real_update = self.worker.store.update
        hung, release = threading.Event(), threading.Event()
        self.addCleanup(release.set)

        def hang_owned_journal(job, attempt, state, data):
            if state == "RUNNING" and data.get("launch") == "CREATED_OWNED" and not hung.is_set():
                hung.set()
                release.wait(30)
            return real_update(job, attempt, state, data)

        with mock.patch.object(self.worker.store, "update", side_effect=hang_owned_journal):
            accepted = self._submit("long-hung-journal", headless=True, timeout=2)
            self.assertTrue(hung.wait(15))
            began = time.monotonic()
            with self.worker._process_lock:
                attempt, owned = next((key, value) for key, value in self.worker.active.items() if value is not None)
            directory = self.worker.root / "attempts" / attempt
            host_started = time.monotonic()
            host = self._call("hosts")
            self.assertLess(time.monotonic() - host_started, 3.0)
            self.assertEqual(host["condition"], "DEGRADED", host)

            def stopped():
                with self.worker._process_lock:
                    return not owned.alive()

            # Deadline (2 s from creation) plus termination, while the monitor
            # thread is still blocked inside storage holding the worker lock.
            wait_until(stopped, timeout=8)
            self.assertLess(time.monotonic() - began, 7.0)
            self.assertFalse(release.is_set())
            self.assertFalse((directory / "ended.json").exists())
            release.set()
            result = self._finish(accepted["job"])
        self.assertEqual(result["state"], "FINISHED", result)
        self.assertEqual(result.get("outcome"), "TIMED_OUT", result)
        self.assertEqual(result.get("cleanup"), "CONFIRMED", result)

    def test_hard_deadline_and_teardown_do_not_wait_for_a_stalled_journal(self):
        accepted = self._submit("long-stalled-storage", headless=True, timeout=3)
        directory = wait_until(lambda: (candidate if (candidate := self._directory(accepted["job"]))
                                        and (candidate / "started.json").exists() else None))
        observed_start = time.monotonic()
        attempt = directory.name
        held, release = threading.Event(), threading.Event()

        def hold_storage_lock():
            # Stand-in for a hung SQLite call that owns the worker lock.
            with self.worker.lock:
                held.set()
                release.wait(20)

        holder = threading.Thread(target=hold_storage_lock, daemon=True)
        holder.start()
        self.addCleanup(release.set)
        self.assertTrue(held.wait(5))
        try:
            began = time.monotonic()
            host = self._call("hosts")
            self.assertLess(time.monotonic() - began, 3.0)
            self.assertEqual(host["condition"], "DEGRADED", host)
            self.assertIsNone(host["claims"])
            self.assertIn("worker lock unavailable", host["inventory_error"])
            # The admitted 3 s budget expires and teardown completes while the
            # journal stays stalled; bound the overshoot, not just eventuality.
            wait_until(lambda: attempt not in self.worker.active, timeout=15)
            self.assertLess(time.monotonic() - observed_start, 3.0 + 4.0)
            self.assertFalse((directory / "ended.json").exists())
            self.assertTrue(holder.is_alive())
        finally:
            release.set()
            holder.join(5)
        result = self._finish(accepted["job"])
        self.assertEqual(result["state"], "FINISHED", result)
        self.assertEqual(result.get("outcome"), "TIMED_OUT", result)
        self.assertEqual(result.get("cleanup"), "CONFIRMED", result)
        self.assertEqual(self.worker.store.db.execute(
            "SELECT COUNT(*) FROM claims WHERE attempt=?", (attempt,)).fetchone()[0], 0)

    def test_failed_terminal_journal_keeps_claims_and_the_real_verdict(self):
        real_update = self.worker.store.update
        failing = threading.Event()
        failing.set()

        def fail_terminal(job, attempt, state, data):
            if state == "FINISHED" and failing.is_set():
                raise sqlite3.OperationalError("injected terminal journal failure")
            return real_update(job, attempt, state, data)

        with mock.patch.object(self.worker.store, "update", side_effect=fail_terminal):
            first = self._submit("terminal-storage", headless=True)
            directory = wait_until(lambda: (candidate if (candidate := self._directory(first["job"]))
                                            and (candidate / "ended.json").exists() else None))
            attempt = directory.name
            wait_until(lambda: attempt not in self.worker.active and attempt not in self.worker.contexts)
            host = wait_until(lambda: (item if (item := self._call("hosts"))["pending_journals"] == 1 else None))
            self.assertEqual(host["condition"], "DEGRADED", host)
            self.assertIn("injected terminal journal failure", host["journal_errors"][attempt])
            second = self._submit("after-terminal-storage", headless=True)
            time.sleep(0.5)
            # Capacity is not released before the verdict is durable, and the
            # scheduler retries that journal before any new allocation.
            self.assertNotEqual(self._status(first["job"])["state"], "FINISHED")
            self.assertGreater(self.worker.store.db.execute(
                "SELECT COUNT(*) FROM claims WHERE attempt=?", (attempt,)).fetchone()[0], 0)
            self.assertEqual(self._status(second["job"])["attempts"], [])
            failing.clear()
            result = self._finish(first["job"])
            later = self._finish(second["job"])
        self.assertEqual(result["state"], "FINISHED", result)
        self.assertEqual(result.get("outcome"), "PASSED", result)
        self.assertEqual(result.get("evidence"), "COMPLETE", result)
        self.assertNotIn("error", result)
        self.assertEqual(later.get("outcome"), "PASSED", later)
        wait_until(lambda: self._call("hosts")["pending_journals"] == 0)


if __name__ == "__main__":
    unittest.main()
