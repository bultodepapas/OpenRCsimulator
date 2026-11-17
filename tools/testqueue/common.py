"""Small local protocol shared by the CLI, launch adapters and worker."""
from __future__ import annotations

import contextlib
import json
import math
import os
from pathlib import Path
import socket
import time
import re

VERSION = 1
LIMIT = 4 * 1024 * 1024


def enabled() -> bool:
    return bool(os.environ.get("OPENRC_TESTQUEUE_CONTEXT")) or (state_root() / "enrollment.json").is_file()


def state_root() -> Path:
    override = os.environ.get("OPENRC_TESTQUEUE_ROOT")
    if override:
        return Path(override).expanduser().resolve()
    if os.name == "nt":
        return Path(os.environ.get("PROGRAMDATA", r"C:\ProgramData")) / "OpenRC" / "testqueue"
    return Path("/var/tmp/openrc-testqueue")


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".pending")
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(value, stream, sort_keys=True, indent=2, allow_nan=False)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    with contextlib.suppress(OSError):
        temporary.chmod(0o600)
    # Windows refuses to replace a file another process is reading (for example
    # a cached MCP status read). Readers are brief, so retry for about 2 s.
    for attempt in range(12):
        try:
            temporary.replace(path)
            return
        except PermissionError:
            if os.name != "nt" or attempt == 11:
                raise
            time.sleep(min(0.4, 0.01 * 2 ** attempt))


def submission_receipt(root: Path, request: dict) -> Path:
    identifier = request["request_id"]
    if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", identifier) or ".." in identifier:
        raise ValueError("request_id must be a safe opaque token")
    path = root / "submissions" / (identifier + ".json")
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        if json.loads(path.read_text(encoding="utf-8")) != request:
            raise ValueError("submission receipt already exists with different inputs or credentials")
        return path
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump(request, stream, sort_keys=True, allow_nan=False)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    return path


class Singleton:
    """Persistent inode; never unlink a lock file to recover a crashed worker."""

    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.stream = path.open("a+b")
        try:
            if os.name == "nt":
                import msvcrt
                self.stream.seek(0)
                if not self.stream.read(1):
                    self.stream.write(b"0")
                    self.stream.flush()
                self.stream.seek(0)
                msvcrt.locking(self.stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BaseException:
            self.stream.close()
            raise

    def close(self):
        self.stream.close()


class HostSingleton:
    """One enrolled Windows authority even when callers choose different roots."""

    def __init__(self, host: str):
        self.handle = None
        if os.name == "nt":
            import ctypes
            from ctypes import wintypes
            self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
            self.kernel.CreateMutexW.argtypes = [ctypes.c_void_p, wintypes.BOOL, wintypes.LPCWSTR]
            self.kernel.CreateMutexW.restype = wintypes.HANDLE
            self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
            self.kernel.CloseHandle.restype = wintypes.BOOL
            self.handle = self.kernel.CreateMutexW(None, True, "Global\\OpenRC-Testqueue-" + host)
            if not self.handle:
                raise ctypes.WinError(ctypes.get_last_error())
            if ctypes.get_last_error() == 183:
                self.close()
                raise RuntimeError("another enrolled worker already owns this physical Windows host")

    def close(self):
        if self.handle:
            self.kernel.CloseHandle(self.handle)
            self.handle = None


class RpcDeadlineExceeded(TimeoutError):
    """The total RPC observation deadline expired; remote work is unaffected."""


class RpcStepTimeout(TimeoutError):
    """A socket step hit its own cap before the total observation deadline."""


class ObservationTimeout(TimeoutError):
    """A waiter ran out of time before obtaining any status observation."""

    def __init__(self, message: str, *, reason: str = "DEADLINE_EXPIRED"):
        super().__init__(message)
        self.reason = reason


def _deadline_call(deadline: float, timeout: float, action):
    """Run one socket step within the remaining monotonic budget."""
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise RpcDeadlineExceeded("RPC deadline expired; remote outcome may be unknown")
    deadline_limited = remaining <= timeout
    try:
        result = action(min(timeout, remaining))
    except socket.timeout as error:
        if deadline_limited or time.monotonic() >= deadline:
            raise RpcDeadlineExceeded("RPC deadline expired; remote outcome may be unknown") from error
        raise RpcStepTimeout("RPC socket step timed out before observation deadline") from error
    if time.monotonic() >= deadline:
        raise RpcDeadlineExceeded("RPC deadline expired; remote outcome may be unknown")
    return result


def rpc(operation: str, *, root: Path | None = None, timeout: float = 30,
        deadline: float | None = None, **payload):
    """Call the local authority; an optional deadline bounds socket steps, not filesystem I/O."""
    if deadline is not None:
        if (not isinstance(deadline, (int, float)) or isinstance(deadline, bool)
                or not isinstance(timeout, (int, float)) or isinstance(timeout, bool)):
            raise ValueError("RPC deadline and timeout must be finite; timeout must be positive")
        try:
            deadline, timeout = float(deadline), float(timeout)
        except OverflowError:
            raise ValueError("RPC deadline and timeout must be finite; timeout must be positive") from None
        if not math.isfinite(deadline) or not math.isfinite(timeout) or timeout <= 0:
            raise ValueError("RPC deadline and timeout must be finite; timeout must be positive")
        _deadline_call(deadline, timeout, lambda _timeout: None)
    root = root or state_root()
    try:
        endpoint = json.loads((root / "endpoint.json").read_text(encoding="utf-8"))
        if endpoint.get("version") != VERSION:
            raise ValueError("testqueue protocol version mismatch")
        request = {"operation": operation, "auth": endpoint["auth"], **payload}
        encoded = (json.dumps(request, allow_nan=False) + "\n").encode()
        if deadline is None:
            with socket.create_connection(("127.0.0.1", endpoint["port"]), timeout=timeout) as connection:
                connection.settimeout(timeout)
                connection.sendall(encoded)
                with connection.makefile("rb") as stream:
                    line = stream.readline(LIMIT + 1)
        else:
            address = ("127.0.0.1", endpoint["port"])
            with contextlib.ExitStack() as cleanup:
                def connect(budget):
                    # A numeric IPv4 address avoids hostname lookup and a loop
                    # over multiple full-budget connection attempts.
                    connection = cleanup.enter_context(socket.socket(socket.AF_INET, socket.SOCK_STREAM))
                    connection.settimeout(budget)
                    connection.connect(address)
                    return connection
                connection = _deadline_call(deadline, timeout, connect)
                def send(budget):
                    connection.settimeout(budget)
                    connection.sendall(encoded)
                _deadline_call(deadline, timeout, send)
                line = bytearray()
                while len(line) <= LIMIT:
                    def receive(budget):
                        connection.settimeout(budget)
                        return connection.recv(min(65536, LIMIT + 1 - len(line)))
                    chunk = _deadline_call(deadline, timeout, receive)
                    if not chunk:
                        break
                    before_newline, marker, _rest = chunk.partition(b"\n")
                    line.extend(before_newline + marker)
                    if marker:
                        break
        if len(line) > LIMIT:
            raise ValueError("testqueue response exceeds protocol limit")
        response = json.loads(line)
    except (RpcDeadlineExceeded, RpcStepTimeout):
        raise
    except (OSError, KeyError, json.JSONDecodeError) as error:
        raise RuntimeError(f"testqueue worker unavailable at {root}; start testctl serve ({error})") from error
    if not response.get("ok"):
        if response.get("code") == "WORKER_BUSY":
            # Same meaning as a socket step timeout: nothing changed; observe again.
            raise RpcStepTimeout(response.get("error", "worker busy"))
        raise ValueError(response.get("error", "testqueue request refused"))
    return response["result"]


def inherited(scope: str) -> bool:
    """An environment string alone is never admission: ask the live authority."""
    context = os.environ.get("OPENRC_TESTQUEUE_CONTEXT")
    if not context:
        return False
    rpc("validate", context=context, scope=scope)
    return True


def require_exclusive(scope: str) -> None:
    """Research launchers have no standalone adapter on enrolled hosts."""
    if enabled() and (not inherited(scope) or not inherited("performance")):
        raise ValueError("enrolled research launches require an exclusive inherited attempt with " + scope + " scope; standalone execution is unsupported")


def validate_wait_timeout(timeout: float) -> float:
    """Reject invalid observer budgets before a caller performs any actions."""
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)):
        raise ValueError("observation timeout must be a finite nonnegative number")
    try:
        value = float(timeout)
    except OverflowError:
        raise ValueError("observation timeout must be a finite nonnegative number") from None
    if not math.isfinite(value) or value < 0:
        raise ValueError("observation timeout must be a finite nonnegative number")
    return value


def wait(job: str, *, root: Path | None = None, timeout: float = 600, ready: bool = False):
    """Observe until ready or timeout; return only a real last observation, never cancel work.

    If no observation was obtained, raise ObservationTimeout with the original job ID.
    On timeout after a nonterminal observation, retain it with a wait_observation
    marker; a socket-step cap and the total deadline have distinct reasons.
    """
    timeout = validate_wait_timeout(timeout)
    deadline = time.monotonic() + timeout
    if not math.isfinite(deadline):
        raise ValueError("observation timeout is too large")
    last = None

    def timed_out(reason, error=None):
        if last is not None:
            return {**last, "wait_observation": {"state": "STALE", "reason": reason}}
        raise ObservationTimeout(f"no status observation for job {job} before observation timeout; retry status",
                                 reason=reason) from error

    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return timed_out("DEADLINE_EXPIRED")
        try:
            result = rpc("status", root=root, job=job, deadline=deadline)
        except RpcDeadlineExceeded as error:
            return timed_out("DEADLINE_EXPIRED", error)
        except RpcStepTimeout as error:
            return timed_out("RPC_STEP_TIMEOUT", error)
        last = result
        if result["state"] in {"FINISHED", "UNKNOWN"} or (ready and result["state"] == "RUNNING" and result.get("session")):
            return result
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return timed_out("DEADLINE_EXPIRED")
        time.sleep(min(0.2, remaining))
