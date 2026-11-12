"""Per-attempt process ownership for the local test queue.

Windows uses a non-inheritable, kill-on-close Job Object.  A Python launch
gate cannot start the requested command until it has been assigned to the job.
The job handle is deliberately never passed to any child.  Job notifications
and process-list snapshots are used to retain individual process handles.  A
zero job count is not a termination barrier; if any lifetime member was missed,
cleanup is unknown even when the job reports no active processes.  Windows
jobs contain inherited CreateProcess descendants; a process started by an
external broker such as WMI is not automatically assigned to the job.

POSIX uses a new session with a retained leader.  Its PID stays reserved until
cleanup, so a group signal cannot target a later process group with a reused
PID.  This is weaker than a Windows job: descendants can escape with setsid or
setpgid, process-table visibility is required, and a stopped/killed leader or a
leaked control-pipe writer can defeat crash cleanup.  It is for cooperative
foreground test runners, not containment of hostile code.  Uncertain cleanup
raises rather than reporting success.  After losing the supervisor, neither
platform can prove completion from a same-boot identity alone.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import uuid


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
    import threading
    import winreg

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

    class _COMPLETION_ASSOCIATION(ctypes.Structure):
        _fields_ = [("key", ctypes.c_void_p), ("port", _HANDLE)]

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
    _kernel32.OpenProcess.argtypes = [_DWORD, wintypes.BOOL, _DWORD]
    _kernel32.OpenProcess.restype = _HANDLE
    _kernel32.IsProcessInJob.argtypes = [_HANDLE, _HANDLE, ctypes.POINTER(wintypes.BOOL)]
    _kernel32.IsProcessInJob.restype = wintypes.BOOL
    _kernel32.WaitForSingleObject.argtypes = [_HANDLE, _DWORD]
    _kernel32.WaitForSingleObject.restype = _DWORD
    _kernel32.CreateIoCompletionPort.argtypes = [_HANDLE, _HANDLE, _SIZE_T, _DWORD]
    _kernel32.CreateIoCompletionPort.restype = _HANDLE
    _kernel32.GetQueuedCompletionStatus.argtypes = [_HANDLE, ctypes.POINTER(_DWORD),
                                                   ctypes.POINTER(_SIZE_T),
                                                   ctypes.POINTER(ctypes.c_void_p), _DWORD]
    _kernel32.GetQueuedCompletionStatus.restype = wintypes.BOOL
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

    def _windows_host():
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                            r"SOFTWARE\Microsoft\Cryptography", 0,
                            winreg.KEY_READ | winreg.KEY_WOW64_64KEY) as key:
            value, _ = winreg.QueryValueEx(key, "MachineGuid")
        return str(uuid.UUID(value))

    def _windows_creation_handle(handle):
        creation, exit_time, kernel, user = (wintypes.FILETIME() for _ in range(4))
        _wincheck(_kernel32.GetProcessTimes(handle, ctypes.byref(creation),
                                            ctypes.byref(exit_time), ctypes.byref(kernel),
                                            ctypes.byref(user)))
        return (creation.dwHighDateTime << 32) | creation.dwLowDateTime

    def _windows_creation(process):
        return _windows_creation_handle(int(process._handle))


def _posix_boot():
    boot_id = Path("/proc/sys/kernel/random/boot_id")
    if boot_id.is_file():
        return boot_id.read_text(encoding="ascii").strip()
    # macOS and BSD expose a stable boot-time value through sysctl.
    result = subprocess.run(["sysctl", "-n", "kern.boottime"], capture_output=True,
                            text=True, timeout=2, check=True)
    match = re.search(r"\{\s*sec\s*=\s*(\d+)\s*,\s*usec\s*=\s*(\d+)\s*\}", result.stdout)
    if not match:
        raise RuntimeError("Cannot obtain POSIX boot identity")
    # Exclude the formatted date: timezone changes do not represent a reboot.
    return f"{int(match.group(1))}:{int(match.group(2))}"


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


def host_identity() -> dict:
    """Return the local machine and boot IDs before starting an attempt.

    The machine ID assumes the queue remains on the same installation; cloned
    machine IDs are not suitable for a shared queue between hosts.  Unsupported
    or inaccessible IDs raise rather than creating unprovable evidence.
    """
    if os.name == "nt":
        return {"host": _windows_host(), "boot": _windows_boot()}
    if os.name == "posix":
        machine_id = Path("/etc/machine-id")
        if machine_id.is_file():
            host = str(uuid.UUID(machine_id.read_text(encoding="ascii").strip()))
        elif sys.platform == "darwin":
            result = subprocess.run(["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
                                    capture_output=True, text=True, timeout=2, check=True)
            matches = [line.split('"')[3] for line in result.stdout.splitlines()
                       if '"IOPlatformUUID"' in line and len(line.split('"')) >= 4]
            if len(matches) != 1:
                raise RuntimeError("Cannot obtain macOS machine identity")
            host = str(uuid.UUID(matches[0]))
        else:
            raise RuntimeError("Cannot obtain POSIX machine identity")
        return {"host": host, "boot": _posix_boot()}
    raise RuntimeError(f"Unsupported process containment platform: {os.name}")


def confirm_stopped(identity: dict) -> bool:
    """Return True only if the recorded local machine has since rebooted.

    The identity must be a durable, unchanged result of host_identity() or
    OwnedProcess.start(), produced on the same local machine.  Job absence or
    a zero active count does not prove all process handles have signaled.  A
    lost supervisor cannot recover the per-process handles, so same-boot,
    malformed, inaccessible and foreign-machine identities conservatively
    return False.  False means either still running or unknown.
    """
    if not isinstance(identity, dict):
        return False
    try:
        if not isinstance(identity.get("host"), str) or not isinstance(identity.get("boot"), str):
            return False
        current = host_identity()
        previous_host = str(uuid.UUID(identity["host"]))
        if previous_host != current["host"]:
            return False
        previous_boot = identity["boot"]
        if os.name == "nt" or sys.platform.startswith("linux"):
            previous_boot = str(uuid.UUID(previous_boot))
        elif sys.platform == "darwin":
            match = re.fullmatch(r"(\d+):(\d+)", previous_boot)
            if not match or int(match.group(1)) <= 0 or int(match.group(2)) >= 1000000:
                return False
        else:
            return False
        return previous_boot != current["boot"]
    except (OSError, KeyError, TypeError, ValueError, RuntimeError, subprocess.SubprocessError):
        return False


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
        self._assigned = False
        self._completion_port = None
        self._observer = None
        self._observer_stop = None
        self._observer_error = None
        self._handles = {}
        self._handle_lock = threading.Lock() if os.name == "nt" else None
        self._status_fd = None
        self._status_data = b""
        self._status = None
        self._closed = False
        self._cleanup_error = None
        self._posix_killed = False

    def start(self):
        if self._process is not None or self._closed:
            raise RuntimeError("attempt already started or closed")
        self._log_file = self.log.open("xb")
        status_write = None
        try:
            if os.name == "nt":
                job_name = "Global\\OpenRC-testqueue-" + str(uuid.uuid4())
                ctypes.set_last_error(0)
                self._job = _wincheck(_kernel32.CreateJobObjectW(None, job_name))
                if ctypes.get_last_error() == 183:  # Never adopt an existing name.
                    raise RuntimeError("Unexpected collision creating a process job")
                limits = _EXTENDED_LIMIT()
                limits.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
                _wincheck(_kernel32.SetInformationJobObject(self._job, 9, ctypes.byref(limits),
                                                             ctypes.sizeof(limits)))
                self._completion_port = _wincheck(_kernel32.CreateIoCompletionPort(
                    ctypes.c_void_p(-1), None, 0, 1))
                association = _COMPLETION_ASSOCIATION(1, self._completion_port)
                _wincheck(_kernel32.SetInformationJobObject(self._job, 7,
                                                             ctypes.byref(association),
                                                             ctypes.sizeof(association)))
                self._observer_stop = threading.Event()
                self._observer = threading.Thread(target=self._observe_windows, daemon=True)
                self._observer.start()
                args = [sys.executable, "-I", "-S", "-c", _WINDOWS_GATE, *self.command]
                self._process = subprocess.Popen(args, cwd=self.cwd, env=self.env,
                                                 stdin=subprocess.PIPE, stdout=self._log_file,
                                                 stderr=subprocess.STDOUT, close_fds=True)
                self.pid = self._process.pid
                _wincheck(_kernel32.AssignProcessToJobObject(self._job, int(self._process._handle)))
                self._assigned = True
                self._capture_windows_pid(self.pid)
                creation, boot = _windows_creation(self._process), _windows_boot()
                host = _windows_host()
            elif os.name == "posix":
                self._status_fd, status_write = os.pipe()
                os.set_blocking(self._status_fd, False)
                args = [sys.executable, "-I", "-S", "-c", _POSIX_GATE,
                        str(status_write), *self.command]
                self._process = subprocess.Popen(args, cwd=self.cwd, env=self.env,
                                                 stdin=subprocess.PIPE, stdout=self._log_file,
                                                 stderr=subprocess.STDOUT, close_fds=True,
                                                 pass_fds=(status_write,), start_new_session=True)
                self.pid = self._process.pid
                os.close(status_write)
                status_write = None
                machine = host_identity()
                creation, boot, host = _posix_creation(self._process.pid), machine["boot"], machine["host"]
            else:
                raise RuntimeError(f"Unsupported process containment platform: {os.name}")
            self.pid = self._process.pid
            self.identity = {"pid": self.pid, "creation": creation, "boot": boot, "host": host}
            if os.name == "nt":
                self.identity.update({"kind": "windows-job-v1", "job": job_name, "host": host})
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
            # The command has not been released unless the last write itself failed;
            # kill its entire containment boundary in either case.
            try:
                deadline = time.monotonic() + _CLEANUP_SECONDS
                if os.name == "nt" and self._assigned:
                    _wincheck(_kernel32.TerminateJobObject(self._job, 1))
                    while not self._windows_finished(min(0.15, max(0, deadline - time.monotonic()))):
                        if time.monotonic() >= deadline:
                            raise TimeoutError("Startup job did not become empty")
                        time.sleep(0.02)
                elif os.name == "posix":
                    try:
                        os.killpg(self.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    self._posix_killed = True
                    while self._posix_members(timeout=min(1, max(0.01, deadline - time.monotonic()))):
                        if time.monotonic() >= deadline:
                            raise TimeoutError("Startup group did not become empty")
                        time.sleep(0.02)
                else:
                    self._process.kill()
                self._process.wait(timeout=max(0.01, deadline - time.monotonic()))
            except (OSError, subprocess.TimeoutExpired, RuntimeError, TimeoutError) as exc:
                failure = exc
            if self._process.stdin:
                try:
                    self._process.stdin.close()
                except OSError as exc:
                    failure = failure or exc
        if os.name == "nt":
            try:
                self._stop_windows_observer()
                self._close_windows_process_handles()
            except (OSError, RuntimeError) as exc:
                failure = failure or exc
        if self._job:
            if not _kernel32.CloseHandle(self._job):
                failure = ctypes.WinError(ctypes.get_last_error())
            self._job = None
        if self._status_fd is not None:
            os.close(self._status_fd)
            self._status_fd = None
        if os.name == "nt" and self._process is not None:
            self._process._handle.Close()
        self._log_file.close()
        self._closed = True
        self._cleanup_error = failure
        if failure:
            raise RuntimeError("Could not verify cleanup after failed start") from failure

    def _require_started(self):
        if self._process is None or self._closed:
            raise RuntimeError("attempt is not running or has been closed")

    def _capture_windows_pid(self, pid):
        handle = _kernel32.OpenProcess(0x00100000 | 0x1000, False, pid)
        if not handle:
            return  # Lifetime accounting detects an unobserved member.
        try:
            in_job = wintypes.BOOL()
            if not _kernel32.IsProcessInJob(handle, self._job, ctypes.byref(in_job)) or not in_job.value:
                return
            key = (pid, _windows_creation_handle(handle))
            with self._handle_lock:
                if key not in self._handles:
                    self._handles[key] = handle
                    handle = None
        finally:
            if handle:
                _kernel32.CloseHandle(handle)

    def _observe_windows(self):
        try:
            while not self._observer_stop.is_set():
                message, key, value = _DWORD(), _SIZE_T(), ctypes.c_void_p()
                if _kernel32.GetQueuedCompletionStatus(self._completion_port, ctypes.byref(message),
                                                       ctypes.byref(key), ctypes.byref(value), 50):
                    if message.value == 6 and value.value:  # JOB_OBJECT_MSG_NEW_PROCESS
                        self._capture_windows_pid(value.value)
                elif ctypes.get_last_error() != 258:  # WAIT_TIMEOUT
                    raise ctypes.WinError(ctypes.get_last_error())
        except BaseException as exc:
            with self._handle_lock:
                self._observer_error = exc

    def _stop_windows_observer(self):
        if self._observer_stop:
            self._observer_stop.set()
        if self._observer:
            self._observer.join(timeout=1)
            if self._observer.is_alive():
                raise RuntimeError("Job notification observer did not stop")
            self._observer = None
        if self._completion_port:
            _wincheck(_kernel32.CloseHandle(self._completion_port))
            self._completion_port = None

    def _close_windows_process_handles(self):
        with self._handle_lock:
            handles = list(self._handles.values())
            self._handles.clear()
        for handle in handles:
            _wincheck(_kernel32.CloseHandle(handle))

    def _windows_accounting(self):
        info = _ACCOUNTING()
        _wincheck(_kernel32.QueryInformationJobObject(self._job, 1, ctypes.byref(info),
                                                       ctypes.sizeof(info), None))
        return info

    def _windows_active(self):
        return self._windows_accounting().active_processes

    def _windows_finished(self, settle_seconds=0.15):
        """Use handles plus lifetime accounting; job count alone is insufficient."""
        deadline = time.monotonic() + settle_seconds
        while True:
            for pid in self._windows_pids():
                self._capture_windows_pid(pid)
            accounting = self._windows_accounting()
            with self._handle_lock:
                handles = list(self._handles.values())
                observer_error = self._observer_error
            if observer_error:
                raise RuntimeError("Job notification observer failed") from observer_error
            if accounting.active_processes:
                return False
            if len(handles) > accounting.total_processes:
                raise RuntimeError("Job process accounting is inconsistent")
            if len(handles) == accounting.total_processes:
                for handle in handles:
                    result = _kernel32.WaitForSingleObject(handle, 0)
                    if result == 258:  # WAIT_TIMEOUT
                        return False
                    if result != 0:
                        raise ctypes.WinError(ctypes.get_last_error())
                return True
            if time.monotonic() >= deadline:
                raise RuntimeError("Some job process handles could not be witnessed")
            time.sleep(0.01)

    def pids(self) -> set[int]:
        """Snapshot the process IDs in this job/session; IDs may change immediately."""
        self._require_started()
        if os.name == "posix":
            members = set(self._posix_members())
            if not self._posix_killed:
                members.add(self.pid)
            return members
        pids = self._windows_pids()
        for pid in pids:
            self._capture_windows_pid(pid)
        return pids

    def _windows_pids(self):
        capacity = 16
        while capacity <= 65536:
            # JOBOBJECT_BASIC_PROCESS_ID_LIST has two DWORDs followed by ULONG_PTRs.
            size = 8 + capacity * ctypes.sizeof(_SIZE_T)
            buffer = ctypes.create_string_buffer(size)
            if _kernel32.QueryInformationJobObject(self._job, 3, buffer, size, None):
                count = ctypes.c_uint32.from_buffer(buffer, 4).value
                if count > capacity:
                    raise RuntimeError("Invalid job process list")
                values = (ctypes.c_size_t * count).from_buffer(buffer, 8)
                return set(values)
            if ctypes.get_last_error() != 234:  # ERROR_MORE_DATA
                raise ctypes.WinError(ctypes.get_last_error())
            capacity *= 2
        raise RuntimeError("Job process list exceeds the supported size")

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
            return not self._windows_finished()
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
            for pid in self._windows_pids():
                self._capture_windows_pid(pid)
            if self._windows_active():
                _wincheck(_kernel32.TerminateJobObject(self._job, 1))
            while not self._windows_finished(min(0.15, max(0, deadline - time.monotonic()))):
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
            if self._cleanup_error:
                raise RuntimeError("Previous process cleanup could not be verified") from self._cleanup_error
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
                try:
                    self._process.stdin.close()
                except OSError as exc:
                    failure = failure or exc
            if os.name == "nt":
                try:
                    self._stop_windows_observer()
                    self._close_windows_process_handles()
                except (OSError, RuntimeError) as exc:
                    failure = failure or exc
            if self._job:
                if not _kernel32.CloseHandle(self._job) and failure is None:
                    failure = ctypes.WinError(ctypes.get_last_error())
                self._job = None
            if self._status_fd is not None:
                try:
                    os.close(self._status_fd)
                except OSError as exc:
                    failure = failure or exc
                self._status_fd = None
            if os.name == "nt":
                try:
                    self._process._handle.Close()
                except OSError as exc:
                    failure = failure or exc
            try:
                self._log_file.close()
            except OSError as exc:
                failure = failure or exc
            self._closed = True
            self._cleanup_error = failure
        if failure:
            raise RuntimeError("Could not verify process cleanup") from failure
