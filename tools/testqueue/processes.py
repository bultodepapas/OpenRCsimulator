"""Per-attempt process ownership for the local test queue.

Windows uses a non-inheritable, kill-on-close Job Object.  A Python launch
gate cannot start the requested command until it has been assigned to the job.
The job handle is deliberately never passed to any child.

POSIX uses a new session with a retained leader.  Its PID stays reserved until
cleanup, so a group signal cannot target a later process group with a reused
PID.  This is weaker than a Windows job: descendants can escape with setsid or
setpgid, process-table visibility is required, and a stopped/killed leader or a
leaked control-pipe writer can defeat crash cleanup.  It is for cooperative
foreground test runners, not containment of hostile code.  Uncertain cleanup
raises rather than reporting success.  No persistent adoption is provided.
"""

from __future__ import annotations

import os
from pathlib import Path
import signal
import subprocess
import sys
import time


_CLEANUP_SECONDS = 8.0

# -I -S prevents Python environment/site hooks from executing before the gate.
# On Windows the gate itself waits for the command, so its exit code is the
# requested command's status.  The job continues to count orphaned children.
_WINDOWS_GATE = r"""
import sys
if sys.stdin.buffer.read(1) != b'1':
    sys.exit(125)
import subprocess
try:
    process = subprocess.Popen(sys.argv[1:], stdin=subprocess.DEVNULL, close_fds=True)
    sys.exit(process.wait())
except OSError as exc:
    print('Could not launch command: ' + str(exc), file=sys.stderr, flush=True)
    sys.exit(127)
"""

# The POSIX gate holds the session leader open even after its child exits.  The
# status pipe is independent of the log and is never inherited by the command.
_POSIX_GATE = r"""
import os
import sys
if os.read(0, 1) != b'1':
    sys.exit(125)
import select
import signal
import subprocess
status_fd = int(sys.argv[1])
signal.signal(signal.SIGTERM, signal.SIG_IGN)
def restore_term():
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
try:
    child = subprocess.Popen(sys.argv[2:], stdin=subprocess.DEVNULL,
                             close_fds=True, preexec_fn=restore_term)
except OSError as exc:
    print('Could not launch command: ' + str(exc), file=sys.stderr, flush=True)
    os.write(status_fd, b'127\n')
    os.close(status_fd)
    child = None
while True:
    if child is not None:
        status = child.poll()
        if status is not None:
            os.write(status_fd, (str(status) + '\n').encode('ascii'))
            os.close(status_fd)
            child = None
    if select.select([0], [], [], 0.05)[0]:
        command = os.read(0, 1)
        if command == b'q':
            sys.exit(0)
        if not command:
            os.killpg(os.getpgrp(), signal.SIGKILL)
"""


if os.name == "nt":
    import ctypes
    from ctypes import wintypes
    import uuid

    _kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _ntdll = ctypes.WinDLL("ntdll", use_last_error=True)
    _SIZE_T = ctypes.c_size_t
    _HANDLE = wintypes.HANDLE
    _DWORD = wintypes.DWORD

    class _BASIC_LIMIT(ctypes.Structure):
        _fields_ = [("process_time", ctypes.c_longlong),
                    ("job_time", ctypes.c_longlong), ("flags", _DWORD),
                    ("min_working_set", _SIZE_T), ("max_working_set", _SIZE_T),
                    ("active_limit", _DWORD), ("affinity", _SIZE_T),
                    ("priority", _DWORD), ("scheduling", _DWORD)]

    class _IO_COUNTERS(ctypes.Structure):
        _fields_ = [(name, ctypes.c_ulonglong) for name in (
            "read_ops", "write_ops", "other_ops", "read_bytes", "write_bytes", "other_bytes")]

    class _EXTENDED_LIMIT(ctypes.Structure):
        _fields_ = [("basic", _BASIC_LIMIT), ("io", _IO_COUNTERS),
                    ("process_memory", _SIZE_T), ("job_memory", _SIZE_T),
                    ("peak_process_memory", _SIZE_T), ("peak_job_memory", _SIZE_T)]

    class _ACCOUNTING(ctypes.Structure):
        _fields_ = [("total_user", ctypes.c_longlong), ("total_kernel", ctypes.c_longlong),
                    ("period_user", ctypes.c_longlong), ("period_kernel", ctypes.c_longlong),
                    ("page_faults", _DWORD), ("total_processes", _DWORD),
                    ("active_processes", _DWORD), ("terminated_processes", _DWORD)]

    class _BOOT_ENVIRONMENT(ctypes.Structure):
        _fields_ = [("identifier", ctypes.c_ubyte * 16), ("firmware_type", _DWORD),
                    ("boot_flags", ctypes.c_ulonglong)]

    _kernel32.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
    _kernel32.CreateJobObjectW.restype = _HANDLE
    _kernel32.SetInformationJobObject.argtypes = [_HANDLE, ctypes.c_int, ctypes.c_void_p, _DWORD]
    _kernel32.SetInformationJobObject.restype = wintypes.BOOL
    _kernel32.AssignProcessToJobObject.argtypes = [_HANDLE, _HANDLE]
    _kernel32.AssignProcessToJobObject.restype = wintypes.BOOL
    _kernel32.QueryInformationJobObject.argtypes = [_HANDLE, ctypes.c_int, ctypes.c_void_p,
                                                    _DWORD, ctypes.POINTER(_DWORD)]
    _kernel32.QueryInformationJobObject.restype = wintypes.BOOL
    _kernel32.TerminateJobObject.argtypes = [_HANDLE, wintypes.UINT]
    _kernel32.TerminateJobObject.restype = wintypes.BOOL
    _kernel32.CloseHandle.argtypes = [_HANDLE]
    _kernel32.CloseHandle.restype = wintypes.BOOL
    _kernel32.GetProcessTimes.argtypes = [_HANDLE, ctypes.POINTER(wintypes.FILETIME),
                                           ctypes.POINTER(wintypes.FILETIME),
                                           ctypes.POINTER(wintypes.FILETIME),
                                           ctypes.POINTER(wintypes.FILETIME)]
    _kernel32.GetProcessTimes.restype = wintypes.BOOL
    _ntdll.NtQuerySystemInformation.argtypes = [ctypes.c_int, ctypes.c_void_p, _DWORD,
                                                ctypes.POINTER(_DWORD)]
    _ntdll.NtQuerySystemInformation.restype = ctypes.c_long

    def _wincheck(result):
        if not result:
            raise ctypes.WinError(ctypes.get_last_error())
        return result

    def _windows_boot():
        info = _BOOT_ENVIRONMENT()
        result = _ntdll.NtQuerySystemInformation(90, ctypes.byref(info), ctypes.sizeof(info), None)
        if result != 0:
            raise OSError(f"Cannot obtain Windows boot identity (NTSTATUS {result:#x})")
        return str(uuid.UUID(bytes_le=bytes(info.identifier)))

    def _windows_creation(process):
        creation, exit_time, kernel, user = (wintypes.FILETIME() for _ in range(4))
        _wincheck(_kernel32.GetProcessTimes(int(process._handle), ctypes.byref(creation),
                                            ctypes.byref(exit_time), ctypes.byref(kernel),
                                            ctypes.byref(user)))
        return (creation.dwHighDateTime << 32) | creation.dwLowDateTime


def _posix_boot():
    boot_id = Path("/proc/sys/kernel/random/boot_id")
    if boot_id.is_file():
        return boot_id.read_text(encoding="ascii").strip()
    # macOS and BSD expose a stable boot-time value through sysctl.
    result = subprocess.run(["sysctl", "-n", "kern.boottime"], capture_output=True,
                            text=True, timeout=2, check=True)
    if not result.stdout.strip():
        raise RuntimeError("Cannot obtain POSIX boot identity")
    return result.stdout.strip()


def _posix_creation(pid):
    stat = Path(f"/proc/{pid}/stat")
    if stat.is_file():
        # comm may contain spaces and parentheses; fields after its last ')' start at state.
        return int(stat.read_text(encoding="ascii").rsplit(")", 1)[1].split()[19])
    result = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True,
                            text=True, timeout=2, check=True)
    if not result.stdout.strip():
        raise RuntimeError("Cannot obtain process creation identity")
    return result.stdout.strip()


class OwnedProcess:
    """A single command and its owned descendants; methods are not thread-safe.

    ``pid`` and ``identity`` describe the non-shell launch gate, whose lifetime
    anchors ownership. ``poll()`` returns the requested command's exit status.
    ``alive()`` asks whether any owned command process is still running, even
    after the command's root has exited. ``terminate()`` waits for the tree to
    stop. ``close()`` also releases handles and is idempotent after success.
    Start a new instance for each attempt and call ``close()`` in a finally.
    """

    def __init__(self, command: list[str], cwd: Path, env: dict, log: Path):
        if not command or not all(isinstance(arg, str) for arg in command):
            raise ValueError("command must be a nonempty list of strings")
        self.command = list(command)
        self.cwd = Path(cwd)
        self.env = dict(env)
        self.log = Path(log)
        self.pid = None
        self.identity = None
        self._process = None
        self._log_file = None
        self._job = None
        self._status_fd = None
        self._status_data = b""
        self._status = None
        self._closed = False
        self._posix_killed = False

    def start(self):
        if self._process is not None or self._closed:
            raise RuntimeError("attempt already started or closed")
        self._log_file = self.log.open("xb")
        status_write = None
        try:
            if os.name == "nt":
                self._job = _wincheck(_kernel32.CreateJobObjectW(None, None))
                limits = _EXTENDED_LIMIT()
                limits.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
                _wincheck(_kernel32.SetInformationJobObject(self._job, 9, ctypes.byref(limits),
                                                             ctypes.sizeof(limits)))
                args = [sys.executable, "-I", "-S", "-c", _WINDOWS_GATE, *self.command]
                self._process = subprocess.Popen(args, cwd=self.cwd, env=self.env,
                                                 stdin=subprocess.PIPE, stdout=self._log_file,
                                                 stderr=subprocess.STDOUT, close_fds=True)
                _wincheck(_kernel32.AssignProcessToJobObject(self._job, int(self._process._handle)))
                creation, boot = _windows_creation(self._process), _windows_boot()
            elif os.name == "posix":
                self._status_fd, status_write = os.pipe()
                os.set_blocking(self._status_fd, False)
                args = [sys.executable, "-I", "-S", "-c", _POSIX_GATE,
                        str(status_write), *self.command]
                self._process = subprocess.Popen(args, cwd=self.cwd, env=self.env,
                                                 stdin=subprocess.PIPE, stdout=self._log_file,
                                                 stderr=subprocess.STDOUT, close_fds=True,
                                                 pass_fds=(status_write,), start_new_session=True)
                os.close(status_write)
                status_write = None
                creation, boot = _posix_creation(self._process.pid), _posix_boot()
            else:
                raise RuntimeError(f"Unsupported process containment platform: {os.name}")
            self.pid = self._process.pid
            self.identity = {"pid": self.pid, "creation": creation, "boot": boot}
            self._process.stdin.write(b"1")
            self._process.stdin.flush()
        except BaseException:
            if status_write is not None:
                os.close(status_write)
            self._abort_start()
            raise

    def _abort_start(self):
        """Close the gate on failed startup and do not claim successful cleanup."""
        failure = None
        if self._process is not None:
            if self._process.stdin:
                self._process.stdin.close()
            # The command has not been released unless the last write itself failed;
            # kill the assigned job in either case, then verify before closing.
            try:
                if os.name == "nt" and self._job:
                    _wincheck(_kernel32.TerminateJobObject(self._job, 1))
                else:
                    self._process.kill()
                self._process.wait(timeout=3)
                if os.name == "nt" and self._job and self._windows_active():
                    raise RuntimeError("Startup cleanup left processes in the job")
            except (OSError, subprocess.TimeoutExpired, RuntimeError) as exc:
                failure = exc
        if self._job:
            if not _kernel32.CloseHandle(self._job):
                failure = ctypes.WinError(ctypes.get_last_error())
            self._job = None
        if self._status_fd is not None:
            os.close(self._status_fd)
            self._status_fd = None
        self._log_file.close()
        self._closed = True
        if failure:
            raise RuntimeError("Could not verify cleanup after failed start") from failure

    def _require_started(self):
        if self._process is None or self._closed:
            raise RuntimeError("attempt is not running or has been closed")

    def _windows_active(self):
        info = _ACCOUNTING()
        _wincheck(_kernel32.QueryInformationJobObject(self._job, 1, ctypes.byref(info),
                                                       ctypes.sizeof(info), None))
        return info.active_processes

    def _posix_members(self, timeout=2):
        # ps -A exposes all processes visible to this user.  If process-table
        # visibility is restricted, even successful enumeration is not a sandbox.
        result = subprocess.run(["ps", "-A", "-o", "pid=", "-o", "pgid=", "-o", "stat="],
                                capture_output=True, text=True, timeout=max(0.01, timeout),
                                check=True)
        members, anchor = [], None
        for line in result.stdout.splitlines():
            fields = line.split()
            if len(fields) != 3:
                raise RuntimeError("Cannot interpret POSIX process table")
            pid, pgid, state = int(fields[0]), int(fields[1]), fields[2]
            if pid == self.pid:
                anchor = (pgid, state)
            elif pgid == self.pid and not state.startswith("Z"):
                members.append(pid)
        if anchor is None or anchor[0] != self.pid:
            raise RuntimeError("Lost the POSIX session leader; ownership is uncertain")
        if anchor[1].startswith("Z") and not self._posix_killed:
            raise RuntimeError("POSIX session leader exited unexpectedly")
        return members

    def poll(self):
        self._require_started()
        if os.name == "nt":
            return self._process.poll()
        if self._status is None:
            try:
                data = os.read(self._status_fd, 128)
            except BlockingIOError:
                return None
            self._status_data += data
            if b"\n" in self._status_data:
                try:
                    self._status = int(self._status_data.split(b"\n", 1)[0])
                except ValueError as exc:
                    raise RuntimeError("Invalid process exit status from session leader") from exc
            elif not data:
                raise RuntimeError("Session leader exited without a command status")
        return self._status

    def alive(self):
        self._require_started()
        if os.name == "nt":
            return self._windows_active() != 0
        members = self._posix_members()
        if members:
            return True
        if self._posix_killed:
            return False
        return self.poll() is None

    def terminate(self):
        """Stop and verify this attempt's contained processes within eight seconds."""
        self._require_started()
        deadline = time.monotonic() + _CLEANUP_SECONDS
        if os.name == "nt":
            if self._windows_active():
                _wincheck(_kernel32.TerminateJobObject(self._job, 1))
            while self._windows_active():
                if time.monotonic() >= deadline:
                    raise TimeoutError("Windows job did not become empty")
                time.sleep(0.02)
            return
        if not self.alive():
            return
        os.killpg(self.pid, signal.SIGTERM)
        # Keep the unreaped leader's PID reserved even after SIGKILL.  Never
        # call Popen.poll/wait until the group is verified empty.
        force_at = deadline - 3.0
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("POSIX process group did not become empty")
            members = self._posix_members(timeout=min(1.0, remaining))
            if not members and (self._posix_killed or self.poll() is not None):
                return
            if not self._posix_killed and time.monotonic() >= force_at:
                os.killpg(self.pid, signal.SIGKILL)
                self._posix_killed = True
            time.sleep(min(0.03, max(0, deadline - time.monotonic())))

    def close(self):
        if self._closed:
            return
        if self._process is None:
            self._closed = True
            return
        failure = None
        try:
            self.terminate()
            if os.name == "posix" and not self._posix_killed:
                self._process.stdin.write(b"q")
                self._process.stdin.flush()
            self._process.wait(timeout=1)
        except BaseException as exc:
            failure = exc
        finally:
            if self._process.stdin:
                self._process.stdin.close()
            if self._job:
                if not _kernel32.CloseHandle(self._job) and failure is None:
                    failure = ctypes.WinError(ctypes.get_last_error())
                self._job = None
            if self._status_fd is not None:
                os.close(self._status_fd)
                self._status_fd = None
            self._log_file.close()
            self._closed = True
        if failure:
            raise RuntimeError("Could not verify process cleanup") from failure
