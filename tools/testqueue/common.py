"""Small local protocol shared by the CLI, launch adapters and worker."""
from __future__ import annotations

import contextlib
import json
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
    temporary.replace(path)


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


def rpc(operation: str, *, root: Path | None = None, timeout: float = 30, **payload):
    root = root or state_root()
    try:
        endpoint = json.loads((root / "endpoint.json").read_text(encoding="utf-8"))
        if endpoint.get("version") != VERSION:
            raise ValueError("testqueue protocol version mismatch")
        request = {"operation": operation, "auth": endpoint["auth"], **payload}
        with socket.create_connection(("127.0.0.1", endpoint["port"]), timeout=timeout) as connection:
            connection.settimeout(timeout)
            connection.sendall((json.dumps(request, allow_nan=False) + "\n").encode())
            with connection.makefile("rb") as stream:
                line = stream.readline(LIMIT + 1)
        if len(line) > LIMIT:
            raise ValueError("testqueue response exceeds protocol limit")
        response = json.loads(line)
    except (OSError, KeyError, json.JSONDecodeError) as error:
        raise RuntimeError(f"testqueue worker unavailable at {root}; start testctl serve ({error})") from error
    if not response.get("ok"):
        raise ValueError(response.get("error", "testqueue request refused"))
    return response["result"]


def inherited(scope: str) -> bool:
    """An environment string alone is never admission: ask the live authority."""
    context = os.environ.get("OPENRC_TESTQUEUE_CONTEXT")
    if not context:
        return False
    rpc("validate", context=context, scope=scope)
    return True


def wait(job: str, *, root: Path | None = None, timeout: float = 600, ready: bool = False):
    deadline = time.monotonic() + timeout
    while True:
        result = rpc("status", root=root, job=job)
        if result["state"] == "FINISHED" or (ready and result.get("session")):
            return result
        if time.monotonic() >= deadline:
            return result  # leaving a waiter never cancels work
        time.sleep(0.2)
