"""Experimental, host-local transport for one isolated headless checked job.

The caller transfers a tar archive into ``ROOT/incoming`` first.  The public
actions read one JSON object from stdin and return one JSON object on stdout.
The root must be the *same local filesystem path* for every pool client on a
host.  This is cooperative admission, not a sandbox or native qualification.
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path, PurePosixPath
import platform
import re
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import time

PROTOCOL = 1
LIMIT = 1024 * 1024
RESERVE = 512 * 1024 * 1024
MAX_ARCHIVE = 128 * 1024**3
MAX_FILES = 300_000
START_GRACE = 30.0
RETENTION_MAX_BYTES = 16 * 1024**3
RETENTION_MAX_SECONDS = 30.0
ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,127}\Z")
SCRIPT = re.compile(r"res://(?:tests|tools)/[A-Za-z0-9_./-]+\.gd\Z")
TIMING = re.compile(r"(?:^|[/_.-])(?:bench(?:mark)?|perf(?:ormance)?|profile|timing|latency|soak|stress|memory)(?:[/_.-]|$)", re.I)


class Refused(Exception):
    def __init__(self, message, code="INVALID"):
        super().__init__(message)
        self.code = code


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode("ascii")


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".pending")
    with temporary.open("wb") as stream:
        stream.write(encode(value) + b"\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    if os.name == "posix":
        fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


TERMINAL_WRITE_ATTEMPTS = 6
TERMINAL_WRITE_DELAY = 0.25
JOURNAL_RETRY_SECONDS = 1.0


def publish_observation(path, value):
    """Post-start journal: True once durable. Failure never touches the owned child."""
    try:
        write_json(path, value)
        return True
    except (OSError, ValueError, TypeError):
        return False


def publish_terminal(path, value):
    """Ordered bounded retries; the caller keeps the host lock until this returns.

    If every attempt fails, the last durable record (RUNNING) stays in place and
    a later status observation quarantines it. Capacity is never released early.
    """
    for attempt in range(TERMINAL_WRITE_ATTEMPTS):
        try:
            return write_json(path, value)
        except OSError:
            if attempt + 1 == TERMINAL_WRITE_ATTEMPTS:
                raise
            time.sleep(TERMINAL_WRITE_DELAY * 2 ** attempt)


def read_json(path):
    with Path(path).open(encoding="utf-8") as stream:
        return json.load(stream)


class Lock:
    """Never remove this file: its persistent inode is the host lock."""
    def __init__(self, path):
        self.stream = Path(path).open("a+b")
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
                fcntl.flock(self.stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self.stream.close()
            raise Refused("host pool is busy", "BUSY")

    def close(self):
        self.stream.close()


def job_path(root, identifier):
    if not isinstance(identifier, str) or not ID.fullmatch(identifier):
        raise Refused("request_id must be a safe opaque token")
    return root / "jobs" / identifier


def state_path(root, identifier):
    return job_path(root, identifier) / "state.json"


def _retention_supported():
    """Fail closed when descriptor-relative, no-follow operations are unavailable."""
    return (os.name == "posix" and hasattr(os, "O_NOFOLLOW") and hasattr(os, "O_DIRECTORY")
            and all(fn in os.supports_dir_fd for fn in (os.open, os.stat, os.link, os.unlink, os.rename))
            and all(fn in os.supports_follow_symlinks for fn in (os.stat, os.link)))


def _retention_identity(info):
    return (info.st_dev, info.st_ino, info.st_mode)


def _retention_fingerprint(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns)


def _retention_open_dir(name, *, parent=None):
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    return os.open(name, flags, dir_fd=parent)


def _retention_open_file(name, parent):
    flags = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NONBLOCK", 0)
    fd = os.open(name, flags, dir_fd=parent)
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise Refused("retention target or backup is not a regular file")
    return fd


def _retention_entry_matches(parent, name, fd, *, full=False):
    entry = os.stat(name, dir_fd=parent, follow_symlinks=False)
    opened = os.fstat(fd)
    compare = _retention_fingerprint if full else _retention_identity
    if compare(entry) != compare(opened):
        raise Refused("retention path changed: " + str(name))


def _retention_hash(fd, deadline, max_bytes):
    before = os.fstat(fd)
    if not stat.S_ISREG(before.st_mode) or before.st_size > max_bytes:
        raise Refused("retention file exceeds the hash budget or is not regular")
    os.lseek(fd, 0, os.SEEK_SET)
    checksum = hashlib.sha256()
    total = 0
    while True:
        if time.monotonic() >= deadline:
            raise Refused("retention hash deadline exceeded")
        block = os.read(fd, 1024 * 1024)
        if time.monotonic() >= deadline:
            raise Refused("retention hash deadline exceeded")
        if not block:
            break
        total += len(block)
        if total > max_bytes:
            raise Refused("retention file exceeds the hash budget")
        checksum.update(block)
    if total != before.st_size or _retention_fingerprint(before) != _retention_fingerprint(os.fstat(fd)):
        raise Refused("retention file changed while hashing")
    return checksum.hexdigest(), before


def _retention_read_state(directory):
    fd = _retention_open_file("state.json", directory)
    try:
        info = os.fstat(fd)
        if info.st_size > 16 * 1024 * 1024:
            raise Refused("retention journal is too large")
        chunks = []
        while block := os.read(fd, 1024 * 1024):
            chunks.append(block)
            if sum(map(len, chunks)) > 16 * 1024 * 1024:
                raise Refused("retention journal is too large")
        _retention_entry_matches(directory, "state.json", fd, full=True)
        return json.loads(b"".join(chunks))
    finally:
        os.close(fd)


def _retention_write_state(directory, state):
    """Publish state through this open directory and fsync its replacement."""
    temporary = ".retention-state-" + secrets.token_hex(16) + ".pending"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    fd = os.open(temporary, flags, 0o600, dir_fd=directory)
    published = False
    try:
        data = memoryview(encode(state) + b"\n")
        while data:
            written = os.write(fd, data)
            if written <= 0:
                raise OSError("short retention journal write")
            data = data[written:]
        os.fsync(fd)
        os.rename(temporary, "state.json", src_dir_fd=directory, dst_dir_fd=directory)
        published = True
        os.fsync(directory)
    finally:
        identity = _retention_identity(os.fstat(fd))
        os.close(fd)
        if not published:
            # Remove only the unpublished inode created by this invocation. A
            # rename that succeeded before raising has no temporary name left.
            try:
                entry = os.stat(temporary, dir_fd=directory, follow_symlinks=False)
                if _retention_identity(entry) == identity:
                    os.unlink(temporary, dir_fd=directory)
                    os.fsync(directory)
            except (OSError, ValueError):
                pass


def _reclaim_success_input_locked(root, identifier, *, max_bytes=RETENTION_MAX_BYTES,
                                  max_seconds=RETENTION_MAX_SECONDS, expected_payload_sha256=None):
    """Reclaim only a confirmed successful job's redundant input archive.

    The caller owns pool.lock. Directory FDs prevent following substituted links
    outside the private queue tree; checks refuse detected changes. POSIX cannot
    make the final name check and unlink atomic against arbitrary same-user
    writers. This boundary assumes cooperating queue-directory ownership and a
    process tree already proved stopped. Time limits are cooperative: a single
    blocked filesystem call can exceed them.
    """
    if not _retention_supported():
        return {"state": "SKIPPED", "reason": "descriptor-relative no-follow operations unavailable"}
    if (type(max_bytes) is not int or max_bytes < 0 or type(max_seconds) not in (int, float)
            or not math.isfinite(max_seconds) or max_seconds <= 0):
        raise ValueError("invalid retention budget")
    if (expected_payload_sha256 is not None and
            (not isinstance(expected_payload_sha256, str)
             or not re.fullmatch(r"[0-9a-f]{64}", expected_payload_sha256))):
        raise Refused("expected payload SHA-256 must be a lowercase digest")
    job_path(Path(root), identifier)  # Validate the identifier before opening paths.
    root = Path(os.path.abspath(root))
    if Path(os.path.realpath(root)) != root:
        raise Refused("retention root must be a canonical non-link path")
    deadline = time.monotonic() + max_seconds
    state = None
    intent = False
    directory = None
    with contextlib.ExitStack() as stack:
        def opened(fd):
            stack.callback(os.close, fd)
            return fd
        root_fd = opened(_retention_open_dir(str(root)))
        jobs_fd = opened(_retention_open_dir("jobs", parent=root_fd))
        directory = opened(_retention_open_dir(identifier, parent=jobs_fd))
        incoming_fd = opened(_retention_open_dir("incoming", parent=root_fd))

        def check_directories():
            if _retention_identity(os.stat(root, follow_symlinks=False)) != _retention_identity(os.fstat(root_fd)):
                raise Refused("retention root changed")
            _retention_entry_matches(root_fd, "jobs", jobs_fd)
            _retention_entry_matches(jobs_fd, identifier, directory)
            _retention_entry_matches(root_fd, "incoming", incoming_fd)

        check_directories()
        state = _retention_read_state(directory)
        if not isinstance(state, dict) or state.get("request_id") != identifier:
            raise Refused("retention journal has the wrong request identity")
        request = validate_request(state.get("request"))
        if request["request_id"] != identifier or state.get("payload_sha256") != hashlib.sha256(encode(request)).hexdigest():
            raise Refused("retention request identity differs from the journal")
        if expected_payload_sha256 is not None and not secrets.compare_digest(state["payload_sha256"], expected_payload_sha256):
            raise Refused("retention payload SHA-256 does not match the durable request", "CONFLICT")
        if (state.get("state"), state.get("outcome"), state.get("evidence"), state.get("cleanup")) != (
                "FINISHED", "PASSED", "COMPLETE", "CONFIRMED"):
            return {"state": "SKIPPED", "reason": "attempt is not a confirmed complete success"}
        archive = request["archive"]
        archive_path = Path(archive["path"])
        if archive_path.parent != root / "incoming" or archive_path.name in ("", ".", ".."):
            raise Refused("retention backup is outside the queue incoming directory")
        expected = archive["sha256"]
        previous = state.get("storage_cleanup") or {}
        if not isinstance(previous, dict):
            raise Refused("invalid retention journal")
        if previous.get("state") in {"RECLAIMED", "ABSENT_AFTER_INTENT"}:
            return previous
        intent = previous.get("state") == "PENDING" and previous.get("phase") == "UNLINK"
        anchor_name = "retained-input.tar"
        anchor_created = False
        anchor = None
        try:
            try:
                target = opened(_retention_open_file("input.tar", directory))
            except FileNotFoundError:
                if not intent or previous.get("sha256") != expected or previous.get("retained_anchor") != anchor_name:
                    raise Refused("job input is missing without a durable unlink intent")
                # An intent plus an absent name does not prove who removed it, or
                # that the unlink was durable before a crash. Keep that distinction.
                anchor = opened(_retention_open_file(anchor_name, directory))
                anchor_digest, _ = _retention_hash(anchor, deadline, max_bytes)
                if anchor_digest != expected:
                    raise Refused("retained archive anchor changed")
                _retention_entry_matches(directory, anchor_name, anchor, full=True)
                os.fsync(anchor)
                check_directories()
                os.fsync(directory)
                state["storage_cleanup"] = {**previous, "state": "ABSENT_AFTER_INTENT", "phase": "UNRESOLVED",
                                            "logical_bytes_removed": None,
                                            "reason": "input absent after durable intent; deletion could not be witnessed"}
                _retention_write_state(directory, state)
                return state["storage_cleanup"]

            target_initial = os.fstat(target)
            if target_initial.st_nlink != 1:
                raise Refused("job input has unexpected hard links")
            if intent and previous.get("target_identity") != list(_retention_fingerprint(target_initial)):
                raise Refused("job input changed since the durable unlink intent")
            backup = opened(_retention_open_file(archive_path.name, incoming_fd))
            backup_digest, backup_initial = _retention_hash(backup, deadline, max_bytes)
            target_digest, target_before = _retention_hash(target, deadline, max_bytes)
            if backup_digest != expected or target_digest != expected:
                raise Refused("job input or retained incoming archive digest differs")
            if _retention_identity(target_before) == _retention_identity(backup_initial):
                raise Refused("job input is not an independent archive copy")
            _retention_entry_matches(incoming_fd, archive_path.name, backup, full=True)
            _retention_entry_matches(directory, "input.tar", target, full=True)
            check_directories()
            try:
                os.link(archive_path.name, anchor_name, src_dir_fd=incoming_fd, dst_dir_fd=directory,
                        follow_symlinks=False)
                anchor_created = True
            except FileExistsError:
                pass
            anchor = opened(_retention_open_file(anchor_name, directory))
            _retention_entry_matches(incoming_fd, archive_path.name, backup, full=True)
            _retention_entry_matches(directory, anchor_name, anchor, full=True)
            same_inode = _retention_identity(os.fstat(backup)) == _retention_identity(os.fstat(anchor))
            if not same_inode:
                if anchor_created:
                    raise Refused("retained archive anchor does not pin the verified incoming archive")
                # A previous crash may have left a valid pinned archive before
                # its intent was published, while incoming was atomically replaced.
                anchor_digest, anchor_before = _retention_hash(anchor, deadline, max_bytes)
                if anchor_digest != expected:
                    raise Refused("existing retained archive anchor digest differs")
            # Linking changes ctime/link count. Hash once more after the link so
            # a concurrent in-place mutation cannot hide in that metadata change.
            backup_digest, backup_before = _retention_hash(backup, deadline, max_bytes)
            if backup_digest != expected:
                raise Refused("retained incoming archive changed during pinning")
            if same_inode:
                anchor_before = os.fstat(anchor)
            os.fsync(anchor)
            os.fsync(directory)  # The retained link must survive before input removal.
            _retention_entry_matches(incoming_fd, archive_path.name, backup, full=True)
            _retention_entry_matches(directory, anchor_name, anchor, full=True)
            if _retention_fingerprint(os.fstat(backup)) != _retention_fingerprint(backup_before):
                raise Refused("retained incoming archive changed after fsync")
            if _retention_fingerprint(os.fstat(anchor)) != _retention_fingerprint(anchor_before):
                raise Refused("retained archive anchor changed after fsync")
            _retention_entry_matches(directory, "input.tar", target, full=True)
            if _retention_fingerprint(os.fstat(target)) != _retention_fingerprint(target_before):
                raise Refused("job input changed before unlink intent")
            check_directories()
            if not intent:
                state["storage_cleanup"] = {"state": "PENDING", "phase": "UNLINK", "sha256": expected,
                    "retained_anchor": anchor_name, "target_identity": list(_retention_fingerprint(target_before)),
                    "logical_bytes_removed": None, "size_semantics": "logical bytes; physical space is not guaranteed"}
                _retention_write_state(directory, state)
                intent = True
            # Revalidate after journal I/O, immediately before deleting the name.
            check_directories()
            _retention_entry_matches(incoming_fd, archive_path.name, backup, full=True)
            _retention_entry_matches(directory, anchor_name, anchor, full=True)
            _retention_entry_matches(directory, "input.tar", target, full=True)
            if (_retention_fingerprint(os.fstat(target)) != _retention_fingerprint(target_before)
                    or _retention_fingerprint(os.fstat(backup)) != _retention_fingerprint(backup_before)
                    or _retention_fingerprint(os.fstat(anchor)) != _retention_fingerprint(anchor_before)):
                raise Refused("retention inputs changed after intent")
            os.unlink("input.tar", dir_fd=directory)
            os.fsync(directory)
            state["storage_cleanup"] = {**state["storage_cleanup"], "state": "RECLAIMED", "phase": "DONE",
                                        "logical_bytes_removed": target_before.st_size}
            _retention_write_state(directory, state)
            return state["storage_cleanup"]
        except (OSError, Refused, ValueError) as error:
            # Do not overwrite a durable intent after a failed unlink/result
            # publication. A later explicit retry can inspect the original state.
            try:
                check_directories()
                current = _retention_read_state(directory)
                prior = current.get("storage_cleanup") or {}
                if anchor_created and not intent and not (
                        prior.get("state") == "PENDING" and prior.get("phase") == "UNLINK"):
                    # The anchor was created here and never became part of a
                    # durable unlink intent. The already-open backup identifies
                    # it even if opening the new anchor itself failed.
                    _retention_entry_matches(directory, anchor_name, anchor if anchor is not None else backup)
                    os.unlink(anchor_name, dir_fd=directory)
                    os.fsync(directory)
                if prior.get("state") == "RECLAIMED":
                    # A final rename can be visible even though its directory
                    # fsync failed. Restore an unresolved receipt if possible.
                    current["storage_cleanup"] = {**prior, "state": "PENDING", "phase": "UNLINK",
                                                  "logical_bytes_removed": None, "last_error": str(error)[:500]}
                    _retention_write_state(directory, current)
                    return {"state": "PENDING", "reason": str(error)}
                if prior.get("state") == "PENDING" and prior.get("phase") == "UNLINK":
                    current["storage_cleanup"] = {**prior, "last_error": str(error)[:500]}
                elif intent:
                    # An unresolved unlink must never be reported as retained
                    # merely because publication of its result failed.
                    pending = state.get("storage_cleanup") or previous
                    current["storage_cleanup"] = {**pending, "state": "PENDING", "phase": "UNLINK",
                                                  "logical_bytes_removed": None, "last_error": str(error)[:500]}
                else:
                    current["storage_cleanup"] = {"state": "SKIPPED", "reason": str(error)[:500],
                                                  "logical_bytes_removed": 0}
                _retention_write_state(directory, current)
            except (OSError, Refused, ValueError):
                pass
            return {"state": "PENDING" if intent else "SKIPPED", "reason": str(error)}


def reclaim_success_input(root, identifier, *, max_bytes=RETENTION_MAX_BYTES,
                          max_seconds=RETENTION_MAX_SECONDS, expected_payload_sha256=None):
    """Retry storage cleanup for one confirmed success, without starting a job."""
    if not _retention_supported():
        if expected_payload_sha256 is not None:
            raise Refused("descriptor-relative no-follow operations unavailable", "UNSUPPORTED")
        return {"state": "SKIPPED", "reason": "descriptor-relative no-follow operations unavailable"}
    import fcntl
    root = Path(os.path.abspath(root))
    if Path(os.path.realpath(root)) != root:
        raise Refused("retention root must be a canonical non-link path")
    root_fd = _retention_open_dir(str(root))
    lock_fd = None
    try:
        flags = os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
        lock_fd = os.open("pool.lock", flags, 0o600, dir_fd=root_fd)
        if not stat.S_ISREG(os.fstat(lock_fd).st_mode):
            raise Refused("retention lock is not a regular file")
        _retention_entry_matches(root_fd, "pool.lock", lock_fd)
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise Refused("host pool is busy", "BUSY") from error
        return _reclaim_success_input_locked(root, identifier, max_bytes=max_bytes, max_seconds=max_seconds,
                                             expected_payload_sha256=expected_payload_sha256)
    finally:
        if lock_fd is not None:
            os.close(lock_fd)
        os.close(root_fd)


def authority_enrolled():
    override = os.environ.get("OPENRC_TESTQUEUE_ROOT")
    default = (Path(os.environ.get("PROGRAMDATA", r"C:\ProgramData")) / "OpenRC" / "testqueue"
               if os.name == "nt" else Path("/var/tmp/openrc-testqueue"))
    roots = [default] + ([Path(override).expanduser()] if override else [])
    return bool(os.environ.get("OPENRC_TESTQUEUE_CONTEXT")) or any((p / "enrollment.json").is_file() for p in roots)


def validate_request(request):
    required = {"request_id", "preset", "archive", "engine_path", "options"}
    if not isinstance(request, dict) or not required <= set(request) or set(request) - required - {"expected_engine_sha256"}:
        raise Refused("run requires request_id, preset, archive, engine_path and options")
    identifier = request["request_id"]
    if not isinstance(identifier, str) or not ID.fullmatch(identifier):
        raise Refused("invalid request_id")
    if request["preset"] != "checked":
        raise Refused("only checked jobs are supported")
    archive = request["archive"]
    if (not isinstance(archive, dict) or set(archive) != {"path", "sha256"}
            or not isinstance(archive["path"], str) or not Path(archive["path"]).is_absolute()
            or not isinstance(archive["sha256"], str) or not re.fullmatch(r"[0-9a-f]{64}", archive["sha256"])):
        raise Refused("archive needs an absolute path and lowercase SHA-256")
    if not isinstance(request["engine_path"], str) or not Path(request["engine_path"]).is_absolute():
        raise Refused("engine_path must be absolute")
    expected_engine = request.get("expected_engine_sha256")
    if expected_engine is not None and (not isinstance(expected_engine, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_engine)):
        raise Refused("expected_engine_sha256 must be a lowercase SHA-256")
    options = request["options"]
    if not isinstance(options, dict) or set(options) - {"script", "require", "timeout", "headless", "workload", "settings", "argv"}:
        raise Refused("unsupported checked options")
    script = options.get("script")
    if (not isinstance(script, str) or not SCRIPT.fullmatch(script) or ".." in PurePosixPath(script[6:]).parts
            or TIMING.search(script)):
        raise Refused("checked script must be a non-performance test/tool res:// path")
    if options.get("headless", True) is not True or options.get("workload", "auto") not in ("auto", "functional") or options.get("argv", []) != []:
        raise Refused("only headless functional or unclassified checked jobs are supported")
    markers = options.get("require", [])
    if (not isinstance(markers, list) or len(markers) > 128 or any(not isinstance(s, str) or not s
            or len(s) > 4096 or "\n" in s or "\r" in s or "\0" in s for s in markers)):
        raise Refused("invalid completion markers")
    timeout = options.get("timeout", 600)
    if type(timeout) not in (int, float) or not math.isfinite(timeout) or not 1 <= timeout <= 21600:
        raise Refused("timeout must be between 1 and 21600 seconds")
    settings = options.get("settings", {})
    if not isinstance(settings, dict) or set(settings) - {"max_log_bytes", "warnings_as_errors", "label"}:
        raise Refused("unsupported checked settings")
    if ("max_log_bytes" in settings and (type(settings["max_log_bytes"]) is not int or not 1 <= settings["max_log_bytes"] <= 64 * 1024**2)
            or "warnings_as_errors" in settings and type(settings["warnings_as_errors"]) is not bool
            or "label" in settings and (not isinstance(settings["label"], str) or len(settings["label"]) > 128)):
        raise Refused("invalid checked settings")
    return request


def public_status(state):
    return {k: v for k, v in state.items() if k != "request"}


def scan(root):
    states = []
    for path in (root / "jobs").glob("*/state.json"):
        try:
            state = read_json(path)
            if state.get("state") in ("STARTING", "RUNNING", "UNKNOWN"):
                states.append(state)
        except (OSError, ValueError):
            # A damaged journal is not permission to admit another process.
            states.append({"state": "UNKNOWN", "request_id": path.parent.name, "error": "unreadable journal"})
    return states


def status(root, identifier):
    path = state_path(root, identifier)
    if not path.is_file():
        raise Refused("request not found", "NOT_FOUND")
    state = read_json(path)
    if state.get("state") in ("STARTING", "RUNNING"):
        try:
            lock = Lock(root / "pool.lock")
        except Refused:
            return public_status(state)
        try:
            state = read_json(path)
            expired = state.get("state") == "RUNNING" or (state.get("state") == "STARTING" and time.time() - state.get("accepted_at", 0) >= START_GRACE)
            if expired:
                state.update(state="UNKNOWN", cleanup="UNCONFIRMED", error="supervisor disappeared; host is quarantined")
                try:
                    write_json(path, state)
                except OSError as error:
                    # The durable RUNNING/STARTING record already keeps the host
                    # quarantined; report the truthful observation, not a crash.
                    state["error"] += f"; quarantine record not persisted ({error})"
        finally:
            lock.close()
    return public_status(state)


def probe(root, request):
    if not isinstance(request, dict) or set(request) - {"engine_path"}:
        raise Refused("probe accepts only engine_path")
    engine_path = request.get("engine_path")
    engine = {"path": engine_path, "available": False}
    if engine_path is not None:
        if not isinstance(engine_path, str) or not Path(engine_path).is_absolute():
            raise Refused("engine_path must be absolute")
        path = Path(engine_path)
        engine["available"] = path.is_file() and (os.name == "nt" or os.access(path, os.X_OK))
        if engine["available"]:
            engine["sha256"] = digest(path)
    usage = shutil.disk_usage(root)
    memory = (None, None)
    try:
        import psutil
        vm = psutil.virtual_memory()
        memory = (vm.available, vm.total)
    except ImportError:
        pass
    if memory == (None, None) and sys.platform.startswith("linux"):
        try:
            fields = {}
            for line in Path("/proc/meminfo").read_text(encoding="ascii").splitlines():
                key, separator, value = line.partition(":")
                if separator and key in {"MemAvailable", "MemTotal"}:
                    fields[key] = int(value.split()[0]) * 1024
            memory = (fields.get("MemAvailable"), fields.get("MemTotal"))
        except (OSError, ValueError, IndexError):
            pass
    try:
        load = list(os.getloadavg())
    except (AttributeError, OSError):
        load = None
    states = scan(root)
    busy = False
    try:
        lock = Lock(root / "pool.lock")
        lock.close()
    except Refused:
        busy = True
    if not busy:
        # Make a lost supervisor visible as quarantine even to probe-only callers.
        for item in states:
            if item["state"] in ("STARTING", "RUNNING"):
                status(root, item["request_id"])
        states = scan(root)
    system, machine = platform.system(), platform.machine()
    capabilities = [system.lower(), machine.lower()]
    if os.name == "posix":
        capabilities[0:0] = ["checked", "headless"]
    return {"protocol": PROTOCOL,
            "host": {"hostname": platform.node(), "system": system, "release": platform.release(),
                     "machine": machine, "python": platform.python_version()},
            "capabilities": capabilities,
            "capacity": {"cpu_count": os.cpu_count(), "load_average": load, "free_bytes": usage.free,
                         "total_bytes": usage.total, "free_memory_bytes": memory[0], "total_memory_bytes": memory[1]},
            "engine": engine, "admission": {"enrolled": authority_enrolled(), "busy": busy or bool(states),
                                            "quarantined": any(s["state"] == "UNKNOWN" for s in states),
                                            "active_request_id": states[0].get("request_id") if states else None}}


def launch(root, request):
    request = validate_request(request)
    identifier = request["request_id"]
    path = state_path(root, identifier)
    payload_sha = hashlib.sha256(encode(request)).hexdigest()
    # Recovery does not require the original archive or a live supervisor.
    if path.is_file():
        previous = read_json(path)
        if previous.get("payload_sha256") != payload_sha:
            raise Refused("request_id already belongs to different inputs", "CONFLICT")
        return status(root, identifier)
    if authority_enrolled():
        raise Refused("host has an enrolled testqueue; submit to that authority", "ENROLLED")
    lock = Lock(root / "pool.lock")
    try:
        if path.is_file():
            previous = read_json(path)
            if previous.get("payload_sha256") != payload_sha:
                raise Refused("request_id already belongs to different inputs", "CONFLICT")
            return public_status(previous)
        if scan(root):
            raise Refused("unresolved or unknown job quarantines this host", "QUARANTINED")
        incoming = (root / "incoming").resolve()
        archive = Path(request["archive"]["path"])
        if archive.is_symlink() or archive.resolve().parent != incoming or not archive.is_file():
            raise Refused("archive must be a regular file directly inside incoming")
        engine = Path(request["engine_path"])
        if not engine.is_file() or (os.name != "nt" and not os.access(engine, os.X_OK)):
            raise Refused("engine is unavailable or not executable")
        directory = job_path(root, identifier)
        directory.mkdir(parents=True, exist_ok=False)
        state = {"protocol": PROTOCOL, "request_id": identifier, "state": "STARTING", "request": request,
                 "payload_sha256": payload_sha, "accepted_at": time.time(), "cleanup": "UNCONFIRMED",
                 "evidence": "INCOMPLETE", "output": str(directory)}
        write_json(path, state)
        # Hidden private console on Windows (never DETACHED_PROCESS): descendants
        # inherit it instead of opening visible console windows.
        flags = (subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW) if os.name == "nt" else 0
        with (directory / "supervisor.log").open("ab") as log:
            subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "_supervise", "--root", str(root), "--request-id", identifier],
                             stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                             close_fds=True, start_new_session=os.name != "nt", creationflags=flags)
        return public_status(state)
    finally:
        lock.close()


def safe_name(name):
    if not name or name.startswith("/") or "\\" in name or ":" in name or any(ord(c) < 32 for c in name):
        raise Refused("unsafe archive path")
    name = name.rstrip("/")
    parts = name.split("/")
    if (any(p in ("", ".", "..") or p.endswith((".", " ")) for p in parts)
            or parts[0] not in {"app", "assets", "tools", "research"}
            or ".godot" in parts or "__pycache__" in parts):
        raise Refused("unsupported archive path: " + name)
    # Avoid device names and collisions across Windows/macOS/Linux.
    if any(re.fullmatch(r"(?i)(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?", p) for p in parts):
        raise Refused("reserved archive path")
    return name


def extract_archive(archive, destination):
    destination = Path(destination)
    destination.mkdir(exist_ok=False)
    inventory, seen, total = {}, set(), 0
    with tarfile.open(archive, "r:*") as tar:
        members = tar.getmembers()
        if len(members) > MAX_FILES:
            raise Refused("archive has too many entries")
        for member in members:
            name = safe_name(member.name)
            key = name.casefold()
            if key in seen or not (member.isfile() or member.isdir()):
                raise Refused("archive contains duplicate, link or special entry")
            seen.add(key)
            if member.isfile():
                if member.size < 0:
                    raise Refused("invalid archive member size")
                total += member.size
                if total > MAX_ARCHIVE:
                    raise Refused("archive expansion limit exceeded")
        if shutil.disk_usage(destination).free < total + RESERVE:
            raise Refused("insufficient disk for extraction and reserve")
        for member in members:
            name = safe_name(member.name)
            target = destination.joinpath(*name.split("/"))
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            source = tar.extractfile(member)
            if source is None:
                raise Refused("archive member is unreadable")
            h, size = hashlib.sha256(), 0
            with source, target.open("xb") as output:
                while block := source.read(1024 * 1024):
                    size += len(block)
                    h.update(block)
                    output.write(block)
            if size != member.size:
                raise Refused("truncated archive member")
            if os.name != "nt":
                target.chmod(member.mode & 0o777)
            inventory[name] = {"size": size, "sha256": h.hexdigest()}
    return inventory


def verify_source(destination, inventory):
    """Re-read the materialized bytes and refuse missing or unexpected files."""
    destination = Path(destination)
    seen = set()
    for path in destination.rglob("*"):
        if path.is_symlink():
            raise Refused("materialized source contains a link")
        if path.is_file():
            name = path.relative_to(destination).as_posix()
            expected = inventory.get(name)
            if expected is None or path.stat().st_size != expected["size"] or digest(path) != expected["sha256"]:
                raise Refused("materialized source differs from archive: " + name)
            seen.add(name)
        elif not path.is_dir():
            raise Refused("materialized source contains a special file")
    if seen != set(inventory):
        raise Refused("materialized source is missing archive files")


def isolate_project(source, identifier):
    path = source / "app/project.godot"
    original = path.read_bytes()
    for match in re.finditer(rb"(?m)^[ \t]*(?:application/)?config/use_custom_user_dir[ \t]*=[ \t]*([^\r\n]*)", original):
        if not re.fullmatch(rb"false[ \t]*(?:;.*)?", match.group(1), re.I):
            raise Refused("a custom Godot user directory cannot be isolated by project name")
    # Distinct names isolate macOS user://, where APPDATA/XDG alone do not.
    replacement = ('config/name="OpenRC pool ' + identifier + '"').encode("ascii")
    data, count = re.subn(rb'(?m)^config/name="[^"\r\n]*"', lambda _: replacement, original)
    if count != 1:
        raise Refused("project name cannot be isolated unambiguously")
    path.write_bytes(data)
    return {"path": "app/project.godot", "original_sha256": hashlib.sha256(original).hexdigest(),
            "isolated_sha256": hashlib.sha256(data).hexdigest(), "project_name": "OpenRC pool " + identifier}


def external_engine_present(engine):
    if os.name == "nt":
        # The pool deliberately leaves Windows admission to the enrolled worker.
        raise Refused("native Windows execution belongs to the existing testqueue authority")
    result = subprocess.run(["ps", "-A", "-o", "comm="], text=True, capture_output=True, check=True, timeout=10)
    base = Path(engine).name.lower()
    for line in result.stdout.splitlines():
        name = Path(line.strip()).name.lower()
        if name and (name == base or "godot" in name):
            return True
    return False


def execute_stage(root, directory, state, stage, deadline):
    # The agent runtime is pinned separately from the source archive.
    if time.monotonic() >= deadline:
        return {"ok": False, "complete": False, "reason": "timeout"}
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from tools.testqueue.processes import OwnedProcess
    source = directory / "source"
    env = {k: v for k, v in os.environ.items() if not k.startswith(("OPENRC_TESTQUEUE_", "OPENRC_DEBUG_"))}
    profile, tmp = directory / "profile", directory / "temp"
    profile.mkdir(exist_ok=True)
    tmp.mkdir(exist_ok=True)
    env.update(APPDATA=str(profile), LOCALAPPDATA=str(profile), XDG_DATA_HOME=str(profile),
               XDG_CONFIG_HOME=str(profile / "config"), XDG_CACHE_HOME=str(profile / "cache"),
               TMP=str(tmp), TEMP=str(tmp), TMPDIR=str(tmp))
    process = OwnedProcess([sys.executable, str(Path(__file__).resolve()), "_invoke", "--root", str(root),
                            "--request-id", state["request_id"], "--stage", stage],
                           cwd=source, env=env, log=directory / (stage + "-runner.log"))
    # A previous stage's closed process must never be attributed to this stage.
    state.pop("process", None)
    state.update(state="RUNNING", stage=stage, dispatch_at=time.time())
    write_json(directory / "state.json", state)
    started = False
    timed_out = False
    code = None
    try:
        process.start()
        started = True
        state["process"] = process.identity
        # Storage failure after creation is an observation fault: the child stays
        # owned and the absolute monotonic deadline below remains in force. Only
        # this single supervisor thread writes the live dict, so newest wins.
        journaled = publish_observation(directory / "state.json", state)
        retry_at = time.monotonic() + JOURNAL_RETRY_SECONDS
        while process.alive():
            code = process.poll()
            now = time.monotonic()
            if now >= deadline or (code is not None and code != 0):
                timed_out = now >= deadline
                process.terminate()
                break
            if not journaled and now >= retry_at:
                journaled = publish_observation(directory / "state.json", state)
                retry_at = time.monotonic() + JOURNAL_RETRY_SECONDS
            time.sleep(0.1)
        code = process.poll()
        process.close()
        started = False
    except BaseException:
        if started:
            try:
                process.close()
            except Exception as error:
                raise RuntimeError("process cleanup was not confirmed") from error
        else:
            # A failed launch can have dispatched before it reported an identity.
            raise RuntimeError("process start or cleanup was not confirmed")
        raise
    # Teardown is proved here. Result I/O faults are evidence gaps, never
    # uncertainty about the process tree.
    if timed_out:
        return {"ok": False, "complete": False, "reason": "timeout"}
    result_path = directory / (stage + "-result.json")
    if code != 0 or not result_path.is_file():
        return {"ok": False, "complete": False, "reason": "runner_exit", "exit_code": code}
    try:
        return read_json(result_path)
    except (OSError, ValueError):
        return {"ok": False, "complete": False, "reason": "result_unreadable"}


def invoke(root, identifier, stage):
    directory = job_path(root, identifier)
    state = read_json(directory / "state.json")
    request = state["request"]
    source = directory / "source"
    path = source / "tools/godot/run_checked.py"
    spec = importlib.util.spec_from_file_location("openrc_remote_checked_runner", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # run_checked normally makes a new POSIX session.  Keep its subprocesses
    # in the retained OwnedProcess group so ordinary descendants are witnessed.
    if os.name == "posix":
        original = subprocess.Popen
        def contained_popen(*args, **kwargs):
            if kwargs.get("start_new_session"):
                kwargs["start_new_session"] = False
            return original(*args, **kwargs)
        subprocess.Popen = contained_popen
        def stop_direct(process):
            try:
                process.kill()
                process.wait(timeout=10)
                return ""
            except (OSError, subprocess.SubprocessError) as error:
                return str(error)
        module.stop_process = stop_direct
    command = [request["engine_path"], "--headless", "--path", str(source / "app"), "--audio-driver", "Dummy"]
    options = request["options"]
    if stage == "import":
        command.append("--import")
        kwargs = {"required": [], "label": "import"}
    elif stage == "check":
        command += ["--script", options["script"]]
        kwargs = {"required": options.get("require", []), **options.get("settings", {})}
    else:
        raise Refused("invalid internal stage")
    # The supervisor owns the stricter total deadline and verified cleanup.
    result = module.run_checked(command, directory / stage, timeout=options.get("timeout", 600) + 60, **kwargs)
    write_json(directory / (stage + "-result.json"), result)
    return 0


def artifact_inventory(directory):
    items = {}
    for name in ("source-inventory.json", "import-result.json", "check-result.json", "import-runner.log", "check-runner.log"):
        path = directory / name
        if path.is_file():
            items[name] = {"sha256": digest(path), "size": path.stat().st_size}
    for folder in ("import", "check"):
        base = directory / folder
        if base.exists():
            for path in base.rglob("*"):
                if path.is_file() and not path.is_symlink():
                    items[path.relative_to(directory).as_posix()] = {"sha256": digest(path), "size": path.stat().st_size}
    return items


def verify_result(directory, stage, result, request):
    """Bind a claimed checked verdict to its actual report and engine log."""
    if not isinstance(result, dict) or result.get("complete") is not True:
        return
    if result.get("format") != "openrc-godot-check v1" or type(result.get("ok")) is not bool:
        raise Refused("invalid checked runner verdict")
    base = (directory / stage).resolve()
    paths = []
    for field in ("report", "log"):
        value = result.get(field)
        if not isinstance(value, str):
            raise Refused("checked runner omitted " + field)
        path = Path(value)
        if path.is_symlink() or not path.is_file() or base not in path.resolve().parents:
            raise Refused("checked runner evidence is outside its owned stage")
        paths.append(path)
    if paths[0].stat().st_size > 2 * 1024**2 or paths[1].stat().st_size > 64 * 1024**2:
        raise Refused("checked evidence exceeds its size limit")
    if read_json(paths[0]) != result or digest(paths[1]) != result.get("log_sha256"):
        raise Refused("checked report or engine log differs from its verdict")
    options = request["options"]
    markers = [] if stage == "import" else options.get("require", [])
    expected = [request["engine_path"], "--headless", "--path", str(directory / "source/app"), "--audio-driver", "Dummy"]
    expected += ["--import"] if stage == "import" else ["--script", options["script"]]
    if result.get("command") != expected or result.get("required_text") != markers:
        raise Refused("checked report describes a different command or markers")
    if result["ok"] and (result.get("exit_code") != 0 or result.get("process_exit") != 0):
        raise Refused("successful checked verdict has a failing process exit")
    if result["ok"]:
        if result.get("missing_required_text") != [] or result.get("counts", {}).get("error") != 0:
            raise Refused("successful checked verdict contains diagnostics or missing markers")
        text = paths[1].read_text(encoding="utf-8", errors="replace")
        text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
        if any(marker not in text for marker in markers):
            raise Refused("checked log does not contain its required markers")


def supervise(root, identifier):
    path = state_path(root, identifier)
    deadline = time.monotonic() + START_GRACE
    while True:
        try:
            lock = Lock(root / "pool.lock")
            break
        except Refused:
            if time.monotonic() >= deadline:
                return 1
            time.sleep(0.05)
    state = read_json(path)
    directory = path.parent
    started = False
    try:
        if state.get("state") != "STARTING":
            return 1
        request = validate_request(state["request"])
        if authority_enrolled():
            raise Refused("host enrolled before launch")
        source_archive = Path(request["archive"]["path"])
        copied = directory / "input.tar"
        if shutil.disk_usage(directory).free < source_archive.stat().st_size + RESERVE:
            raise Refused("insufficient disk for archive and reserve")
        with source_archive.open("rb") as src, copied.open("xb") as dst:
            shutil.copyfileobj(src, dst, 1024 * 1024)
            dst.flush()
            os.fsync(dst.fileno())
        if digest(copied) != request["archive"]["sha256"]:
            raise Refused("transferred archive SHA-256 differs")
        source = directory / "source"
        files = extract_archive(copied, source)
        verify_source(source, files)
        write_json(directory / "source-inventory.json", {"archive_sha256": request["archive"]["sha256"], "files": files})
        transformation = isolate_project(source, identifier)
        if not (source / "tools/godot/run_checked.py").is_file() or not (source / "app" / request["options"]["script"][6:]).is_file():
            raise Refused("snapshot is missing the checked runner or requested script")
        if external_engine_present(request["engine_path"]):
            raise Refused("external Godot process detected; it was not touched")
        state.update(host={"hostname": platform.node(), "system": platform.system(), "machine": platform.machine()},
                     engine={"path": request["engine_path"], "sha256": digest(request["engine_path"])},
                     transformation=transformation, source_inventory_sha256=digest(directory / "source-inventory.json"))
        expected_engine = request.get("expected_engine_sha256")
        if expected_engine is not None and state["engine"]["sha256"] != expected_engine:
            raise Refused("engine SHA-256 differs from the selected host probe")
        end = time.monotonic() + request["options"].get("timeout", 600)
        started = True
        imported = execute_stage(root, directory, state, "import", end)
        verify_result(directory, "import", imported, request)
        state["import"] = imported
        if digest(request["engine_path"]) != state["engine"]["sha256"]:
            raise Refused("engine executable changed during import")
        result = execute_stage(root, directory, state, "check", end) if imported.get("ok") is True and imported.get("complete") is True else None
        if result is not None:
            verify_result(directory, "check", result, request)
        state["checked"] = result
        if digest(request["engine_path"]) != state["engine"]["sha256"]:
            raise Refused("engine executable changed during the attempt")
        complete = bool(imported.get("complete") is True and result and result.get("complete") is True)
        ok = bool(complete and imported.get("ok") is True and result.get("ok") is True)
        state.update(state="FINISHED", outcome="PASSED" if ok else "TEST_FAILED" if complete else "INFRA_FAILED",
                     cleanup="CONFIRMED", evidence="COMPLETE" if complete else "INCOMPLETE",
                     artifacts=artifact_inventory(directory), finished_at=time.time())
        if ok:
            state["storage_cleanup"] = ({"state": "PENDING", "phase": "PREPARING", "logical_bytes_removed": None}
                                        if _retention_supported() else
                                        {"state": "SKIPPED", "reason": "descriptor-relative no-follow operations unavailable",
                                         "logical_bytes_removed": 0})
    except Exception as error:
        uncertain = started and ("not confirmed" in str(error))
        state.update(state="UNKNOWN" if uncertain else "FINISHED", outcome="INFRA_FAILED",
                     cleanup="UNCONFIRMED" if uncertain else "CONFIRMED", evidence="INCOMPLETE",
                     error=f"{type(error).__name__}: {error}", finished_at=time.time())
    finally:
        try:
            # FINISHED and its process-cleanup receipt must be durable before
            # reclaiming storage or releasing the host lock. Readers may observe
            # storage cleanup pending.
            publish_terminal(path, state)
            if (state.get("state"), state.get("outcome"), state.get("evidence"), state.get("cleanup")) == (
                    "FINISHED", "PASSED", "COMPLETE", "CONFIRMED") and _retention_supported():
                try:
                    _reclaim_success_input_locked(root, identifier)
                except (OSError, Refused, ValueError):
                    # The already-published execution outcome remains valid;
                    # unresolved cleanup is visible in its separate field.
                    pass
        finally:
            lock.close()
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("probe", "run", "status", "reclaim-input", "_supervise", "_invoke"))
    parser.add_argument("--root", required=True)
    parser.add_argument("--request-id")
    parser.add_argument("--stage")
    args = parser.parse_args()
    root = Path(args.root).expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    (root / "jobs").mkdir(exist_ok=True)
    (root / "incoming").mkdir(exist_ok=True)
    if args.action == "_supervise":
        return supervise(root, args.request_id)
    if args.action == "_invoke":
        return invoke(root, args.request_id, args.stage)
    request = None
    try:
        raw = sys.stdin.buffer.read(LIMIT + 1)
        if len(raw) > LIMIT:
            raise Refused("request too large")
        request = json.loads(raw or b"{}")
        if args.action == "probe":
            result = probe(root, request)
        elif args.action == "run":
            result = launch(root, request)
        elif args.action == "reclaim-input":
            if (not isinstance(request, dict) or set(request) != {"request_id", "payload_sha256"}
                    or not isinstance(request.get("request_id"), str) or not ID.fullmatch(request["request_id"])
                    or not isinstance(request.get("payload_sha256"), str)
                    or not re.fullmatch(r"[0-9a-f]{64}", request["payload_sha256"])):
                raise Refused("reclaim-input requires request_id and lowercase payload_sha256")
            result = reclaim_success_input(root, request["request_id"], expected_payload_sha256=request["payload_sha256"])
        else:
            if not isinstance(request, dict) or set(request) != {"request_id"}:
                raise Refused("status requires request_id")
            result = status(root, request["request_id"])
        print(json.dumps({"ok": True, "result": result}, allow_nan=False))
        return 0
    except Exception as error:
        print(json.dumps({"ok": False, "protocol": PROTOCOL,
                          "request_id": request.get("request_id") if isinstance(request, dict) else None,
                          "code": getattr(error, "code", "ERROR"), "error": str(error)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
