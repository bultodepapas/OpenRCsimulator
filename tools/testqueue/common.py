"""Small local protocol shared by the CLI, launch adapters and worker."""
from __future__ import annotations

import contextlib
import json
import os
from pathlib import Path
import socket
import time

VERSION = 1
LIMIT = 4 * 1024 * 1024


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
