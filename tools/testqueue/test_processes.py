"""Process ownership checks using real fake runners, without a shell."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import processes
from processes import OwnedProcess


def wait_for(predicate, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.025)
    raise AssertionError("Timed out waiting for process state")


def runner_with_orphan(ready):
    child = (
        "import os,time; from pathlib import Path; "
        f"Path({str(ready)!r}).write_text(str(os.getpid())); "
        "time.sleep(60)"
    )
    return (
        "import subprocess,sys,time; from pathlib import Path; "
        f"subprocess.Popen([sys.executable, '-c', {child!r}], stdin=subprocess.DEVNULL, "
        "stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); "
        f"p=Path({str(ready)!r}); "
        "\nwhile not p.exists(): time.sleep(0.01)\n"
    )


class ProcessFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc queue process ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def owned(self, code, *args):
        process = OwnedProcess([sys.executable, "-c", code, *args], self.root,
                               os.environ.copy(), self.root / "attempt log.txt")
        self.addCleanup(process.close)
        process.start()
        return process

    def test_exit_status_identity_and_space_containing_arguments(self):
        process = self.owned("import sys; print(sys.argv[1], flush=True); sys.exit(7)",
                             "argument with spaces")
        self.assertEqual(wait_for(lambda: process.poll() == 7), True)
        wait_for(lambda: not process.alive())
        self.assertEqual(process.identity["pid"], process.pid)
        self.assertTrue(process.identity["creation"])
        self.assertTrue(process.identity["boot"])
        self.assertIn("argument with spaces", process.log.read_text())
        process.close()
        process.close()

    def test_orphan_descendant_stays_owned_and_unrelated_process_survives(self):
        unrelated = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
        self.addCleanup(lambda: unrelated.poll() is None and unrelated.kill())
        self.addCleanup(lambda: unrelated.poll() is not None or unrelated.wait(timeout=5))
        ready = self.root / "orphan ready.txt"
        process = self.owned(runner_with_orphan(ready))
        wait_for(lambda: ready.exists())
        wait_for(lambda: process.poll() == 0)
        self.assertTrue(process.alive(), "the launcher exited but its child is still running")
        started = time.monotonic()
        process.terminate()
        self.assertLess(time.monotonic() - started, 10)
        self.assertFalse(process.alive())
        self.assertIsNone(unrelated.poll(), "cleanup must leave unrelated processes alone")
        unrelated.terminate()
        unrelated.wait(timeout=5)

    def test_missing_command_is_recorded_as_failure(self):
        process = OwnedProcess([str(self.root / "missing executable")], self.root,
                               os.environ.copy(), self.root / "attempt log.txt")
        self.addCleanup(process.close)
        process.start()
        wait_for(lambda: process.poll() == 127)
        wait_for(lambda: not process.alive())
        self.assertIn("Could not launch command", process.log.read_text())

    def test_existing_log_is_not_overwritten(self):
        log = self.root / "attempt log.txt"
        log.write_text("preserve me")
        process = OwnedProcess([sys.executable, "-c", "pass"], self.root, os.environ.copy(), log)
        with self.assertRaises(FileExistsError):
            process.start()
        self.assertEqual(log.read_text(), "preserve me")

    def test_supervisor_crash_kills_orphan(self):
        ready = self.root / "orphan ready.txt"
        control = self.root / "supervisor ready.json"
        log = self.root / "supervisor attempt.log"
        supervisor_code = (
            "import json,os,sys,time; from pathlib import Path; "
            f"sys.path.insert(0, {str(Path(__file__).resolve().parent)!r}); "
            "from processes import OwnedProcess; "
            f"p=OwnedProcess([sys.executable, '-c', {runner_with_orphan(ready)!r}], "
            f"Path({str(self.root)!r}), os.environ.copy(), Path({str(log)!r})); "
            "p.start(); "
            "\nwhile p.poll() is None: time.sleep(0.02)\n"
            f"Path({str(control)!r}).write_text(json.dumps(p.identity)); "
            "time.sleep(60)"
        )
        supervisor = subprocess.Popen([sys.executable, "-c", supervisor_code],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: supervisor.poll() is None and supervisor.kill())
        self.addCleanup(lambda: supervisor.poll() is not None or supervisor.wait(timeout=5))
        wait_for(lambda: control.exists() and ready.exists())
        child_pid = int(ready.read_text())
        if os.name == "nt":
            import ctypes
            from ctypes import wintypes
            kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
            kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
            kernel32.OpenProcess.restype = wintypes.HANDLE
            kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
            kernel32.WaitForSingleObject.restype = wintypes.DWORD
            kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
            handle = kernel32.OpenProcess(0x00100000, False, child_pid)  # SYNCHRONIZE
            self.assertTrue(handle)
            try:
                supervisor.kill()
                supervisor.wait(timeout=5)
                self.assertEqual(kernel32.WaitForSingleObject(handle, 8000), 0)
            finally:
                kernel32.CloseHandle(handle)
        else:
            # A pidfd remains tied to the original child across PID reuse.
            if not hasattr(os, "pidfd_open"):
                self.skipTest("crash check requires a stable process handle on this POSIX host")
            import select
            fd = os.pidfd_open(child_pid)
            try:
                supervisor.kill()
                supervisor.wait(timeout=5)
                poller = select.poll()
                poller.register(fd, select.POLLIN)
                self.assertTrue(poller.poll(8000), "orphan outlived the supervisor")
            finally:
                os.close(fd)

    @unittest.skipUnless(os.name == "nt", "Windows Job Object behavior")
    def test_job_handle_is_not_inheritable(self):
        import ctypes
        from ctypes import wintypes
        process = self.owned("import time; time.sleep(60)")
        flags = wintypes.DWORD()
        get_flags = processes._kernel32.GetHandleInformation
        get_flags.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
        get_flags.restype = wintypes.BOOL
        self.assertTrue(get_flags(process._job, ctypes.byref(flags)))
        self.assertEqual(flags.value & 1, 0)

    @unittest.skipUnless(os.name == "nt", "Windows Job Object behavior")
    def test_assignment_failure_never_runs_command(self):
        marker = self.root / "must not run"
        code = f"from pathlib import Path; Path({str(marker)!r}).write_text('ran')"
        process = OwnedProcess([sys.executable, "-c", code], self.root, os.environ.copy(),
                               self.root / "attempt log.txt")
        with mock.patch.object(processes._kernel32, "AssignProcessToJobObject", return_value=0):
            with self.assertRaises(OSError):
                process.start()
        self.assertIsNotNone(process._process.returncode)
        self.assertFalse(marker.exists())

    @unittest.skipUnless(os.name == "posix", "POSIX process-group behavior")
    def test_forced_kill_of_term_ignoring_process_is_bounded(self):
        ready = self.root / "ignoring term"
        code = ("import signal,time; from pathlib import Path; "
                "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                f"Path({str(ready)!r}).write_text('ready'); time.sleep(60)")
        process = self.owned(code)
        wait_for(ready.exists)
        started = time.monotonic()
        process.terminate()
        self.assertLess(time.monotonic() - started, 10)
        self.assertFalse(process.alive())


if __name__ == "__main__":
    unittest.main()
