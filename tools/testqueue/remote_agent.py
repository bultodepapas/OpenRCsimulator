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
# Optional capabilities a coordinator may rely on; an older agent lacks the list.
FEATURES = ("identity", "fence", "unjournaled-resume", "import-budget", "launch-order", "recover-boot", "describe",
            "content-store")
# A checked job's project import runs under this budget, before and apart from
# the job's own timeout, which bounds the check (TQ-07-A8).
IMPORT_BUDGET_SECONDS = 900
# TQ-07-A9b: each stage's process identity is durable before its gate is
# released, so a RUNNING record without one proves the command never ran.
LAUNCH_ORDER = "identity-before-release"
# TQ-07-A9d: a supervisor waits this long for the host lock (a storage sweep
# holds it for one job at a time) instead of giving up after START_GRACE.
SUPERVISOR_LOCK_WAIT = 600.0
# TQ-07-A9e: space released just before the terminal journal on a full disk.
TERMINAL_RESERVE_BYTES = 1024 * 1024
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
# GPU lane (TQ-06): an operator-declared ``<root>/graphics.json`` lets a host run
# ``workload: graphics`` checks on its real GPU under a per-job headless Wayland
# compositor. The import stage stays headless.
GRAPHICS_CONFIG = "graphics.json"
RENDERING_DRIVERS = ("vulkan", "opengl3")
GRAPHICS_RESOLUTION = "1920x1080"
SOFTWARE_RENDERER = re.compile(r"llvmpipe|lavapipe|softpipe|swrast|software rasterizer", re.I)
DEVICE_LINE = re.compile(r"^(?:Vulkan|OpenGL)\b.* - Using Device\b.*$", re.M)
POSIX = os.name == "posix"


def checked_command(engine, app, options, stage):
    """The exact engine argv for a checked stage; collection verifies the same list."""
    if stage == "check" and options.get("workload") == "graphics":
        command = [engine, "--path", app, "--audio-driver", "Dummy", "--display-driver", "wayland",
                   "--rendering-driver", options["rendering_driver"], "--resolution", GRAPHICS_RESOLUTION]
    else:
        command = [engine, "--headless", "--path", app, "--audio-driver", "Dummy"]
    return command + (["--import"] if stage == "import" else ["--script", options["script"]])


def graphics_config(root):
    """Return this host's declared GPU lane when it is usable now, else None."""
    try:
        value = read_json(Path(root) / GRAPHICS_CONFIG)
    except (OSError, ValueError):
        return None
    if (not isinstance(value, dict) or value.get("compositor") != "weston-headless"
            or not isinstance(value.get("gpu"), str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,39}", value["gpu"])
            or not isinstance(value.get("adapter"), str) or not 3 <= len(value["adapter"]) <= 128
            or not isinstance(value.get("render_node"), str)
            or not re.fullmatch(r"/dev/dri/renderD[0-9]{3}", value["render_node"])):
        return None
    if not POSIX or not os.access(value["render_node"], os.R_OK | os.W_OK) or not shutil.which("weston"):
        return None
    return value


def device_line(log_text):
    """The engine's first ``... Using Device ...`` line; it precedes any script output."""
    lines = DEVICE_LINE.findall(re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", log_text))
    return lines[0].strip()[:300] if lines else None


def driver_matches(line, driver):
    return line.startswith("Vulkan" if driver == "vulkan" else "OpenGL")


def gpu_verdict(log_text, config, driver):
    """Accept a rendered check only when the engine used the declared GPU and driver."""
    line = device_line(log_text)
    if line is None:
        return {"ok": False, "reason": "no_device_line", "device": None}
    if SOFTWARE_RENDERER.search(line):
        return {"ok": False, "reason": "software_renderer", "device": line}
    if config["adapter"] not in line:
        return {"ok": False, "reason": "unexpected_adapter", "device": line}
    if not driver_matches(line, driver):
        return {"ok": False, "reason": "unexpected_driver", "device": line}
    return {"ok": True, "device": line, "gpu": config["gpu"], "rendering_driver": driver}


class TeardownUnconfirmed(RuntimeError):
    """A stage's process start or teardown could not be proved; quarantine the host."""


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
    try:
        encode(value)
    except ValueError:
        # A runner result with NaN/Infinity cannot be encoded strictly. Replace
        # only the offending fields; cleanup stays, a pass cannot survive it.
        for key in list(value):
            try:
                encode(value[key])
            except ValueError:
                value[key] = {"ok": False, "complete": False, "reason": "not_serializable"}
                value["evidence"] = "INCOMPLETE"
                if value.get("outcome") == "PASSED":
                    value["outcome"] = "INFRA_FAILED"
    for attempt in range(TERMINAL_WRITE_ATTEMPTS):
        try:
            return write_json(path, value)
        except OSError:
            if attempt + 1 == TERMINAL_WRITE_ATTEMPTS:
                raise
            time.sleep(TERMINAL_WRITE_DELAY * 2 ** attempt)


def journal_before_release(path, value):
    """Durably record a gated stage's identity; bounded retries (TQ-07-A9b).

    Nothing runs while this retries: the gate holds its command until released.
    """
    for attempt in range(TERMINAL_WRITE_ATTEMPTS):
        try:
            write_json(path, value)
            return True
        except (OSError, ValueError, TypeError):
            if attempt + 1 < TERMINAL_WRITE_ATTEMPTS:
                time.sleep(TERMINAL_WRITE_DELAY * 2 ** attempt)
    return False


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


def fence_path(root, identifier):
    job_path(root, identifier)  # same validation as a job ID
    return root / "fences" / (identifier + ".json")


def _sync_directory(path):
    if os.name == "posix":
        fd = os.open(path, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def machine_id():
    """A digest of the operating system's machine identifier, or None (TQ-07-A1).

    Only the digest leaves the host. Containers report their own identifier.
    """
    raw = None
    try:
        if sys.platform.startswith("linux"):
            for name in ("/etc/machine-id", "/var/lib/dbus/machine-id"):
                try:
                    raw = Path(name).read_text(encoding="ascii").strip() or None
                except (OSError, UnicodeDecodeError):
                    continue
                if raw:
                    break
        elif sys.platform == "darwin":
            output = subprocess.run(["/usr/sbin/ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
                                    capture_output=True, text=True, timeout=5).stdout
            match = re.search(r'"IOPlatformUUID"\s*=\s*"([0-9A-Fa-f-]{8,64})"', output)
            raw = match.group(1) if match else None
        elif os.name == "nt":
            import winreg
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Cryptography") as key:
                raw = str(winreg.QueryValueEx(key, "MachineGuid")[0]) or None
    except (OSError, ValueError, subprocess.SubprocessError):
        raw = None
    return hashlib.sha256(("openrc-machine-v1:" + raw).encode("utf-8")).hexdigest()[:32] if raw else None


def store_id(root):
    """A random identity for this job store, created once (TQ-07-A1).

    It changes when the store is wiped and recreated, so a coordinator cannot
    read "request not found" from a new store as proof about the old one.
    """
    path = Path(root) / "store-id.json"
    try:
        value = read_json(path)
        if isinstance(value, dict) and isinstance(value.get("store_id"), str) and re.fullmatch(r"[0-9a-f]{32}", value["store_id"]):
            return value["store_id"]
    except (OSError, ValueError):
        pass
    candidate = {"store_id": secrets.token_hex(16), "created_at": time.time()}
    try:
        with path.open("xb") as stream:
            stream.write(encode(candidate) + b"\n")
            stream.flush()
            os.fsync(stream.fileno())
    except FileExistsError:
        value = read_json(path)  # a concurrent creator won; a damaged file stays visible as an error
        if not isinstance(value, dict) or not isinstance(value.get("store_id"), str):
            raise Refused("store-id.json is damaged; inspect it before using this store", "CONFLICT")
        return value["store_id"]
    try:
        _sync_directory(path.parent)
    except OSError:
        pass  # best effort: a lost identity only makes later settlement refuse, never succeed wrongly
    return candidate["store_id"]


def host_identity(root):
    return {"machine_id": machine_id(), "store_id": store_id(root)}


def _discard_unjournaled_job(directory):
    """Remove a job directory whose launch died before its journal (TQ-07-A9a).

    The launcher holds the host lock from before ``mkdir`` until after it starts
    the supervisor and writes ``state.json`` first, so under that lock a
    directory without a journal was never accepted. Anything unexpected inside
    it is kept for inspection.
    """
    if directory.is_symlink() or not directory.is_dir():
        raise Refused("job path is not a plain directory; inspect it", "CONFLICT")
    entries = list(directory.iterdir())
    if any(entry.name != "state.json.pending" or entry.is_symlink() or not entry.is_file() for entry in entries):
        raise Refused("an unjournaled job directory has unexpected contents; inspect it", "CONFLICT")
    for entry in entries:
        entry.unlink()
    directory.rmdir()
    _sync_directory(directory.parent)


def fence(root, request):
    """Durably promise that a request ID will never run here, unless it already did (TQ-07-A2).

    ``fence`` writes its tombstone, then looks for the job directory; ``run``
    creates the job directory, then looks for the tombstone. Whatever the
    interleaving, at least one sees the other, so a request is never both
    fenced and launched. Returns FENCED, KNOWN (with the job's status), or
    refuses BUSY while a launch may still be in flight.
    """
    if not isinstance(request, dict) or set(request) != {"request_id"}:
        raise Refused("fence requires request_id")
    identifier = request["request_id"]
    directory = job_path(root, identifier)
    journal = state_path(root, identifier)
    identity = host_identity(root)

    def known():
        return {"request_id": identifier, "state": "KNOWN", "identity": identity, "status": status(root, identifier)}

    if journal.is_file():
        return known()
    tombstone = fence_path(root, identifier)
    tombstone.parent.mkdir(exist_ok=True)
    # A tombstone is never removed: another fencer may already have answered
    # FENCED on the strength of it. Beside a journaled job it is inert, because
    # both ``fence`` and ``run`` answer from the journal first.
    try:
        with tombstone.open("xb") as stream:
            stream.write(encode({"request_id": identifier, "fenced_at": time.time(), "identity": identity}) + b"\n")
            stream.flush()
            os.fsync(stream.fileno())
    except FileExistsError:
        pass
    _sync_directory(tombstone.parent)  # the tombstone must be durable before anyone relies on it
    fenced = {"request_id": identifier, "state": "FENCED", "identity": identity}
    if not directory.exists():
        return fenced
    if journal.is_file():
        return known()
    try:
        lock = Lock(root / "pool.lock")
    except Refused:
        raise Refused("a launch of this request may still be in flight; observe it again later", "BUSY")
    try:
        if journal.is_file():
            return known()
        _discard_unjournaled_job(directory)  # CONFLICT keeps the evidence; the tombstone still holds
        return fenced
    finally:
        lock.close()


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
        if "archive" not in request:
            return {"state": "SKIPPED", "logical_bytes_removed": 0,
                    "reason": "content-store job: no input archive was copied"}
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
    required = {"request_id", "preset", "engine_path", "options"}
    if (not isinstance(request, dict) or not required <= set(request)
            or set(request) - required - {"expected_engine_sha256", "archive", "source_manifest"}
            or ("archive" in request) == ("source_manifest" in request)):
        raise Refused("run requires request_id, preset, engine_path, options and exactly one of archive "
                      "or source_manifest")
    identifier = request["request_id"]
    if not isinstance(identifier, str) or not ID.fullmatch(identifier):
        raise Refused("invalid request_id")
    if request["preset"] != "checked":
        raise Refused("only checked jobs are supported")
    if "archive" in request:
        archive = request["archive"]
        if (not isinstance(archive, dict) or set(archive) != {"path", "sha256"}
                or not isinstance(archive["path"], str) or not Path(archive["path"]).is_absolute()
                or not isinstance(archive["sha256"], str) or not re.fullmatch(r"[0-9a-f]{64}", archive["sha256"])):
            raise Refused("archive needs an absolute path and lowercase SHA-256")
    else:
        manifest = request["source_manifest"]
        if not isinstance(manifest, dict) or set(manifest) != {"sha256"} or not DIGEST.fullmatch(str(manifest["sha256"])):
            raise Refused("source_manifest needs a lowercase SHA-256")
    if not isinstance(request["engine_path"], str) or not Path(request["engine_path"]).is_absolute():
        raise Refused("engine_path must be absolute")
    expected_engine = request.get("expected_engine_sha256")
    if expected_engine is not None and (not isinstance(expected_engine, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_engine)):
        raise Refused("expected_engine_sha256 must be a lowercase SHA-256")
    options = request["options"]
    if not isinstance(options, dict) or set(options) - {"script", "require", "timeout", "headless", "workload", "settings", "argv", "rendering_driver"}:
        raise Refused("unsupported checked options")
    script = options.get("script")
    if (not isinstance(script, str) or not SCRIPT.fullmatch(script) or ".." in PurePosixPath(script[6:]).parts
            or TIMING.search(script)):
        raise Refused("checked script must be a non-performance test/tool res:// path")
    if options.get("argv", []) != []:
        raise Refused("checked jobs take no extra engine arguments")
    if options.get("workload") == "graphics":
        if options.get("headless") is not False or options.get("rendering_driver") not in RENDERING_DRIVERS:
            raise Refused("graphics checks need headless false and rendering_driver vulkan or opengl3")
    elif (options.get("headless", True) is not True or options.get("workload", "auto") not in ("auto", "functional")
            or "rendering_driver" in options):
        raise Refused("only headless functional, unclassified or graphics checked jobs are supported")
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
            # The host lock is free, so no supervisor holds this job.
            nonlaunch = None
            if state.get("state") == "STARTING" and type(state.get("supervisor_pid")) is int:
                if time.time() - state.get("accepted_at", 0) < START_GRACE or supervisor_alive(state, identifier):
                    return public_status(state)
                try:
                    helpers_gone = _posix_group_absent(state["supervisor_pid"])
                except (OSError, RuntimeError, subprocess.SubprocessError):
                    helpers_gone = False
                if not helpers_gone:
                    # A preparation helper (an import-cache copy) of the dead
                    # supervisor still runs; observe again once it ends.
                    return public_status(state)
                # STARTING is written before any stage, and every stage records
                # RUNNING before creating a process; supervise re-checks STARTING
                # under this lock, so a late supervisor cannot start one now.
                nonlaunch = "the supervisor ended before any stage process was created and left no helper"
            elif state.get("state") == "RUNNING" and state.get("launch_order") == LAUNCH_ORDER \
                    and not isinstance(state.get("process"), dict):
                # TQ-07-A9b: the identity is journaled before the gate is released.
                nonlaunch = ("the supervisor ended before releasing the " + str(state.get("stage") or "stage")
                             + " gate; that command never ran")
            if nonlaunch is not None:
                # An earlier stage (the import) may have run and been torn down;
                # then the claim is about this stage only.
                earlier = isinstance(state.get("import"), dict) and state.get("stage") != "import"
                if state.get("reason_code"):
                    state["previous_reason_code"] = state["reason_code"]
                state.update(state="FINISHED", outcome="INFRA_FAILED", cleanup="CONFIRMED", evidence="INCOMPLETE",
                             nonlaunch_stage=state.get("stage") or "preparation", error=nonlaunch,
                             reason_code="SUPERVISOR_LOST", finished_at=time.time())
                if not earlier:
                    state.update(launch="NOT_CREATED", nonlaunch="CONFIRMED")
            elif state.get("state") == "STARTING" and time.time() - state.get("accepted_at", 0) < START_GRACE:
                return public_status(state)
            elif state.get("state") in ("STARTING", "RUNNING"):
                state.update(state="UNKNOWN", cleanup="UNCONFIRMED", error="supervisor disappeared; host is quarantined")
            try:
                write_json(path, state)
            except OSError as error:
                # The durable RUNNING/STARTING record already keeps the host
                # quarantined; report the truthful observation, not a crash.
                state["error"] = str(state.get("error", "")) + f"; record not persisted ({error})"
        finally:
            lock.close()
    return public_status(state)


def supervisor_alive(state, identifier):
    """Whether the recorded supervisor of this job is still running (TQ-07-A9d)."""
    pid = state.get("supervisor_pid")
    if type(pid) is not int or pid <= 0 or os.name != "posix":
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass  # exists under another account: compare its command line below
    except OSError:
        return False
    try:
        command = subprocess.run(["ps", "-p", str(pid), "-o", "command="], capture_output=True,
                                 text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return True  # cannot tell: never settle a job whose supervisor may be waiting
    return "_supervise" in command and identifier in command


HARDWARE_CACHE_SECONDS = 24 * 3600
RUNTIME_FILES = ("remote_agent.py", "processes.py", "common.py")


def _run_text(argv, timeout=5):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def _arch():
    machine = platform.machine().lower()
    return {"amd64": "x86_64", "x64": "x86_64", "aarch64": "arm64"}.get(machine, machine)


def runtime_identity():
    """Digests of the agent's own deployed files (TQ-07-B1/B4)."""
    here = Path(__file__).resolve().parent
    files = {}
    for name in RUNTIME_FILES:
        try:
            files[name] = digest(here / name)
        except OSError:
            files[name] = None
    combined = hashlib.sha256(encode(files)).hexdigest()
    return {"files": files, "digest": combined}


def _hardware(root):
    """Slow, stable facts, cached under the root for a day. Every value may be None."""
    path = Path(root) / "hardware.json"
    try:
        cached = read_json(path)
        if isinstance(cached, dict) and time.time() - cached.get("observed_at", 0) < HARDWARE_CACHE_SECONDS:
            return cached
    except (OSError, ValueError):
        pass
    facts = {"observed_at": time.time(), "os": platform.system().lower(), "os_release": platform.release(),
             "arch": _arch(), "cpu_model": None, "physical_cores": None, "logical_cores": os.cpu_count(),
             "memory_total_bytes": None, "gpus": []}
    if sys.platform == "darwin":
        facts["os_version"] = _run_text(["sw_vers", "-productVersion"]).strip() or None
        facts["cpu_model"] = _run_text(["sysctl", "-n", "machdep.cpu.brand_string"]).strip() or None
        cores = _run_text(["sysctl", "-n", "hw.physicalcpu"]).strip()
        facts["physical_cores"] = int(cores) if cores.isdigit() else None
        memory = _run_text(["sysctl", "-n", "hw.memsize"]).strip()
        facts["memory_total_bytes"] = int(memory) if memory.isdigit() else None
        text = _run_text(["system_profiler", "SPDisplaysDataType"], timeout=15)
        facts["gpus"] = [line.split(":", 1)[1].strip() for line in text.splitlines()
                         if line.strip().startswith("Chipset Model:")]
    elif sys.platform.startswith("linux"):
        try:
            info = Path("/proc/cpuinfo").read_text(encoding="utf-8", errors="replace")
            names = [line.split(":", 1)[1].strip() for line in info.splitlines() if line.startswith("model name")]
            facts["cpu_model"] = names[0] if names else None
            cores = {(line.split(":", 1)[1].strip()) for line in info.splitlines() if line.startswith("core id")}
            sockets = {(line.split(":", 1)[1].strip()) for line in info.splitlines() if line.startswith("physical id")}
            facts["physical_cores"] = len(cores) * max(1, len(sockets)) if cores else None
        except OSError:
            pass
        try:
            for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
                if line.startswith("PRETTY_NAME="):
                    facts["os_version"] = line.split("=", 1)[1].strip('"')
        except OSError:
            pass
        for node in sorted(Path("/sys/class/drm").glob("renderD*")) if Path("/sys/class/drm").is_dir() else []:
            try:
                vendor = (node / "device/vendor").read_text().strip()
                device = (node / "device/device").read_text().strip()
                facts["gpus"].append(f"{node.name} {vendor}:{device}")
            except OSError:
                continue
    try:
        write_json(path, facts)
    except OSError:
        pass
    return facts


def _volatile(root):
    """Facts that change between probes. Every value may be None."""
    facts = {"clock": time.time(), "uptime_seconds": None, "boot": None, "power": None, "session": None,
             "memory_available_bytes": None, "inodes_free": None}
    try:
        runtime = str(Path(__file__).resolve().parents[2])
        if runtime not in sys.path:
            sys.path.insert(0, runtime)
        from tools.testqueue.processes import host_identity as process_identity
        facts["boot"] = process_identity().get("boot")
    except Exception:
        pass
    try:
        stats = os.statvfs(root)
        facts["inodes_free"] = stats.f_favail
    except (AttributeError, OSError):
        pass
    if sys.platform == "darwin":
        boot = re.search(r"sec\s*=\s*(\d+)", _run_text(["sysctl", "-n", "kern.boottime"]))
        facts["uptime_seconds"] = round(time.time() - int(boot.group(1))) if boot else None
        battery = _run_text(["pmset", "-g", "batt"])
        percent = re.search(r"(\d+)%", battery)
        facts["power"] = {"source": "ac" if "AC Power" in battery else "battery" if "Battery Power" in battery else None,
                          "battery_percent": int(percent.group(1)) if percent else None}
        thermal = _run_text(["pmset", "-g", "therm"])
        facts["power"]["thermal_warning"] = None if not thermal else ("No thermal warning level has been recorded" not in thermal
                                                                     and "CPU_Speed_Limit \t= 100" not in thermal)
        user = _run_text(["stat", "-f", "%Su", "/dev/console"]).strip()
        facts["session"] = {"console_user": user if user and user != "root" else None}
        pages = _run_text(["vm_stat"])
        size = re.search(r"page size of (\d+) bytes", pages)
        free = sum(int(value) for key, value in re.findall(r"Pages (free|inactive|speculative):\s+(\d+)", pages))
        if size:
            facts["memory_available_bytes"] = free * int(size.group(1))
    elif sys.platform.startswith("linux"):
        try:
            facts["uptime_seconds"] = round(float(Path("/proc/uptime").read_text().split()[0]))
        except (OSError, ValueError, IndexError):
            pass
        supplies = Path("/sys/class/power_supply")
        if supplies.is_dir():
            online = [p for p in supplies.glob("*/online")]
            capacity = [p for p in supplies.glob("*/capacity")]
            try:
                on_ac = any(p.read_text().strip() == "1" for p in online) if online else None
                facts["power"] = {"source": "ac" if on_ac or not capacity else "battery",
                                  "battery_percent": int(capacity[0].read_text().strip()) if capacity else None}
            except (OSError, ValueError):
                pass
    return facts


def _caches(root):
    """What this host already holds, so placement need not charge a transfer for it."""
    incoming = sorted(path.name[:-4] for path in (Path(root) / "incoming").glob("*.tar")
                      if re.fullmatch(r"[0-9a-f]{64}\.tar", path.name))
    engines = {}
    base = Path(root) / IMPORT_CACHE
    for directory in sorted(base.iterdir()) if base.is_dir() else []:
        meta = {}
        try:
            meta = read_json(directory / "cache.json")
        except (OSError, ValueError):
            pass
        engines[directory.name] = {key: meta.get(key) for key in ("files", "bytes", "published_at", "source_job")
                                   if isinstance(meta, dict) and key in meta}
    store = None
    try:
        bounds = read_json(Path(root) / CACHE_BOUNDS)
        last = bounds.get("store") if isinstance(bounds, dict) else None
        if isinstance(last, dict) and "bytes_after" in last:
            store = {"entries": last.get("entries", 0) - last.get("removed", 0), "bytes": last["bytes_after"],
                     "budget": last.get("budget"), "measured_at": bounds.get("at")}
    except (OSError, ValueError):
        pass
    return {"incoming_archives": incoming, "import_cache_engines": engines, "content_store": store}


def describe_host(root, states):
    """TQ-07-B1: one self-description for scheduling; unknown is None, never a guess."""
    hardware = _hardware(root)
    return {"runtime": runtime_identity(), "hardware": hardware, "volatile": _volatile(root),
            "caches": _caches(root),
            "slots": {"headless": 1, "running": [state.get("request_id") for state in states
                                                 if state.get("state") in ("STARTING", "RUNNING")],
                      "unknown": [state.get("request_id") for state in states if state.get("state") == "UNKNOWN"]}}


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
    try:
        description = describe_host(root, states)
    except Exception as error:  # a self-description fault never hides the host
        description = {"error": f"{type(error).__name__}: {error}"[:200]}
    if memory[0] is None:
        memory = ((description.get("volatile") or {}).get("memory_available_bytes"),
                  (description.get("hardware") or {}).get("memory_total_bytes"))
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
        graphics = graphics_config(root)
        if graphics:
            capabilities += ["graphics", "gpu:" + graphics["gpu"]]
    admission = {"enrolled": authority_enrolled(), "busy": busy or bool(states),
                 "quarantined": any(s["state"] == "UNKNOWN" for s in states),
                 "active_request_id": states[0].get("request_id") if states else None}
    if os.name == "posix" and engine["available"] and not admission["busy"] and not admission["enrolled"]:
        try:
            if external_engine_present(engine_path):
                admission.update(busy=True, busy_code="EXTERNAL_SIMULATOR", busy_reason="External Godot is running")
        except (OSError, subprocess.SubprocessError) as error:
            admission.update(busy=True, busy_code="OCCUPANCY_UNKNOWN", busy_reason=f"Godot process probe failed: {error}")
    return {"protocol": PROTOCOL, "features": list(FEATURES), "identity": host_identity(root),
            "description": description,
            "host": {"hostname": platform.node(), "system": system, "release": platform.release(),
                     "machine": machine, "python": platform.python_version()},
            "capabilities": capabilities,
            "capacity": {"cpu_count": os.cpu_count(), "load_average": load, "free_bytes": usage.free,
                         "total_bytes": usage.total, "free_memory_bytes": memory[0], "total_memory_bytes": memory[1]},
            "engine": engine, "admission": admission}


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
    if fence_path(root, identifier).is_file():
        raise Refused("this request was fenced and will never run here", "FENCED")
    if authority_enrolled():
        raise Refused("host has an enrolled testqueue; submit to that authority", "ENROLLED")
    if request["options"].get("workload") == "graphics" and graphics_config(root) is None:
        raise Refused("this host has no usable GPU lane (graphics.json, render node, weston)")
    lock = Lock(root / "pool.lock")
    try:
        if path.is_file():
            previous = read_json(path)
            if previous.get("payload_sha256") != payload_sha:
                raise Refused("request_id already belongs to different inputs", "CONFLICT")
            return public_status(previous)
        if scan(root):
            raise Refused("unresolved or unknown job quarantines this host", "QUARANTINED")
        if "archive" in request:
            incoming = (root / "incoming").resolve()
            archive = Path(request["archive"]["path"])
            if archive.is_symlink() or archive.resolve().parent != incoming or not archive.is_file():
                raise Refused("archive must be a regular file directly inside incoming")
        else:
            # TQ-07-E4a: every file the job needs must already be in the store.
            missing = store_missing(root, read_source_manifest(root, request["source_manifest"]["sha256"]))
            if missing:
                # Typed, before any job exists: the coordinator re-sends and runs the same ID.
                raise Refused(f"the content store lacks {len(missing)} file(s) of this source; upload them first",
                              "STORE_MISSING")
        engine = Path(request["engine_path"])
        if not engine.is_file() or (os.name != "nt" and not os.access(engine, os.X_OK)):
            raise Refused("engine is unavailable or not executable")
        directory = job_path(root, identifier)
        if directory.exists():
            # Under this lock a directory without a journal is a launch that died
            # before writing it; it was never accepted (TQ-07-A9a).
            _discard_unjournaled_job(directory)
        directory.mkdir(parents=True, exist_ok=False)
        if fence_path(root, identifier).is_file():
            # The other half of the fence handshake: the tombstone won.
            directory.rmdir()
            raise Refused("this request was fenced and will never run here", "FENCED")
        state = {"protocol": PROTOCOL, "request_id": identifier, "state": "STARTING", "request": request,
                 "payload_sha256": payload_sha, "accepted_at": time.time(), "cleanup": "UNCONFIRMED",
                 "evidence": "INCOMPLETE", "output": str(directory)}
        write_json(path, state)
        # Hidden private console on Windows (never DETACHED_PROCESS): descendants
        # inherit it instead of opening visible console windows.
        flags = (subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW) if os.name == "nt" else 0
        with (directory / "supervisor.log").open("ab") as log:
            supervisor = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "_supervise", "--root", str(root), "--request-id", identifier],
                                          stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                          close_fds=True, start_new_session=os.name != "nt", creationflags=flags)
        try:
            # TQ-07-A9d: status can tell a supervisor still waiting for the lock
            # from a dead one. Advisory: without it the start grace applies.
            pid = getattr(supervisor, "pid", None)
            if type(pid) is int:
                state["supervisor_pid"] = pid
                write_json(path, state)
        except OSError:
            pass
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


STORE = "store"
DIGEST = re.compile(r"[0-9a-f]{64}\Z")
MAX_STORE_REQUEST_DIGESTS = 400_000
# TQ-07-G3: the store is least-recently-used above its budget, pruned down to
# the target. One full snapshot is about 1 GiB, so several commits' variants fit.
STORE_BUDGET_BYTES = 4 * 1024 ** 3
STORE_PRUNE_TARGET_BYTES = 3 * 1024 ** 3
# An entry used this recently is never pruned. store-have refreshes every entry
# it reports present, and an upload plus run takes far less than this, so a
# prune between a coordinator's transfer and its run cannot undercut the run.
STORE_RECENT_SECONDS = 3600
IMPORT_CACHE_IDLE_SECONDS = 14 * 86400


def _mark_used(path):
    """Refresh a cache entry's mtime: the prune's least-recently-used order."""
    try:
        os.utime(path)
    except OSError:
        pass  # a stale mark only makes the entry an earlier prune candidate


def store_path(root, sha256):
    if not isinstance(sha256, str) or not DIGEST.fullmatch(sha256):
        raise Refused("store digests are lowercase SHA-256")
    return Path(root) / STORE / sha256[:2] / sha256


def store_have(root, request):
    """Which of these content digests the store lacks (TQ-07-E4a).

    Every present entry is marked used, so the coordinator can rely on it
    until its run starts (see ``STORE_RECENT_SECONDS``).
    """
    if not isinstance(request, dict) or set(request) != {"digests"} or not isinstance(request["digests"], list) \
            or len(request["digests"]) > MAX_STORE_REQUEST_DIGESTS:
        raise Refused("store-have requires a list of digests")
    missing = []
    for sha in dict.fromkeys(request["digests"]):
        path = store_path(root, sha)
        try:
            os.utime(path)  # the presence test and the use mark are one call (G3 review)
        except FileNotFoundError:
            missing.append(sha)
        except OSError:
            if not path.is_file():  # present but unmarkable still counts as present
                missing.append(sha)
    return {"missing": missing, "asked": len(request["digests"])}


def store_put(root, stream):
    """Add content-addressed files from a tar stream; each member's name is its SHA-256.

    Every member is hashed while written to a private temporary and published by
    atomic rename only when its digest matches its name, so a broken or partial
    upload never leaves a wrong file under a digest.
    """
    stored = skipped = size = 0
    with tarfile.open(fileobj=stream, mode="r|") as bundle:
        for member in bundle:
            if not member.isfile() or not DIGEST.fullmatch(member.name):
                raise Refused("store-put accepts regular members named by their SHA-256")
            target = store_path(root, member.name)
            if target.is_file():
                _mark_used(target)
                skipped += 1
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            if shutil.disk_usage(target.parent).free < member.size + RESERVE:
                raise Refused("insufficient disk for the content store and reserve")
            temporary = target.with_name(target.name + "." + secrets.token_hex(6) + ".pending")
            source = bundle.extractfile(member)
            h = hashlib.sha256()
            try:
                with source, temporary.open("xb") as output:
                    while block := source.read(1024 * 1024):
                        h.update(block)
                        output.write(block)
                    output.flush()
                    os.fsync(output.fileno())
                if h.hexdigest() != member.name:
                    raise Refused("uploaded bytes differ from their digest " + member.name)
                os.replace(temporary, target)
            finally:
                if temporary.exists():
                    temporary.unlink()
            stored += 1
            size += member.size
    return {"stored": stored, "already_present": skipped, "bytes": size}


def prune_store(root, protected, *, budget=None, target=None, recent=None, now=None):
    """Remove least-recently-used store entries while the store exceeds its budget (TQ-07-G3).

    Called under the host lock, so no job is materializing. An entry in
    ``protected`` (named by an unfinished job's manifest) or used within
    ``recent`` seconds is kept even if the store stays over budget. Every entry
    is a reproducible cache: a later transfer sends a missing one again.
    """
    budget = STORE_BUDGET_BYTES if budget is None else budget
    target = STORE_PRUNE_TARGET_BYTES if target is None else target
    recent = STORE_RECENT_SECONDS if recent is None else recent
    base = Path(root) / STORE
    now = time.time() if now is None else now
    entries, total = [], 0
    for path in base.glob("*/*") if base.is_dir() else []:
        if not DIGEST.fullmatch(path.name) or path.parent.name != path.name[:2]:
            continue  # upload temporaries are swept by age elsewhere
        try:
            info = path.lstat()
        except OSError:
            continue
        if not stat.S_ISREG(info.st_mode):
            continue
        total += info.st_size
        entries.append((info.st_mtime, path.name, info.st_size, path))
    removed = freed = kept_recent = failed = 0
    if total > budget:
        for mtime, name, size, path in sorted(entries):
            if total - freed <= target:
                break
            if name in protected:
                continue
            try:
                # Re-read the mark: store-have may have used this entry since the scan.
                if now - path.lstat().st_mtime < recent:
                    kept_recent += 1
                    continue
                path.unlink()
            except FileNotFoundError:
                continue
            except OSError:
                failed += 1  # one unremovable entry never stops the prune
                continue
            removed += 1
            freed += size
    return {"entries": len(entries), "bytes": total, "budget": budget, "removed": removed,
            "bytes_removed": freed, "bytes_after": total - freed, "kept_recent": kept_recent,
            "protected": len(protected), "failed": failed}


def prune_import_caches(root, keep, *, idle=None, now=None):
    """Remove import caches of engines no job has used for ``idle`` seconds (TQ-07-G3).

    Called under the host lock, so nothing seeds or publishes meanwhile. The
    most recently used engine's cache is always kept, as is any engine in
    ``keep`` (an unfinished job's). A removed cache only makes the next import
    of that engine cold.
    """
    idle = IMPORT_CACHE_IDLE_SECONDS if idle is None else idle
    base = Path(root) / IMPORT_CACHE
    now = time.time() if now is None else now
    caches = []
    for directory in base.iterdir() if base.is_dir() else []:
        if directory.is_symlink() or not directory.is_dir() or not DIGEST.fullmatch(directory.name):
            continue
        marker = directory / "cache.json"
        try:
            used = marker.stat().st_mtime if marker.is_file() else directory.stat().st_mtime
        except OSError:
            continue
        caches.append((used, directory))
    removed, failed, freed = [], [], 0
    newest = max(caches, key=lambda item: item[0])[1] if caches else None
    for used, directory in caches:
        if directory == newest or directory.name in keep or now - used < idle:
            continue
        size = _tree_stats(directory)[1]
        try:
            imported = directory / "imported"
            if imported.is_dir() and not imported.is_symlink():
                # Move it aside first, so an interrupted removal is never seeded as a cache.
                os.rename(imported, directory / ("old-prune-" + secrets.token_hex(4)))
            shutil.rmtree(directory)
        except OSError:
            failed.append(directory.name)
            continue
        freed += size
        removed.append(directory.name)
    return {"engines": len(caches), "removed": sorted(removed), "bytes_removed": freed, "failed": sorted(failed)}


def read_source_manifest(root, sha256):
    """The file map a content-store job materializes, verified against its digest."""
    path = store_path(root, sha256)
    try:
        data = path.read_bytes()
    except OSError:
        raise Refused("source manifest is not in the store; upload it first", "STORE_MISSING") from None
    if hashlib.sha256(data).hexdigest() != sha256:
        raise Refused("stored source manifest differs from its digest")
    value = json.loads(data)
    files = value.get("files") if isinstance(value, dict) else None
    if not isinstance(files, dict) or len(files) > MAX_FILES:
        raise Refused("source manifest has no valid file map")
    for name, entry in files.items():
        safe_name(name)
        if (not isinstance(entry, dict) or set(entry) != {"size", "sha256"} or type(entry["size"]) is not int
                or entry["size"] < 0 or not DIGEST.fullmatch(str(entry["sha256"]))):
            raise Refused("source manifest entry is invalid: " + name)
    return files


def store_missing(root, files):
    return sorted({entry["sha256"] for entry in files.values() if not store_path(root, entry["sha256"]).is_file()})


def materialize_from_store(root, files, destination):
    """Build a job's private source tree from the store (copies, never links: Godot writes files)."""
    destination = Path(destination)
    destination.mkdir(exist_ok=False)
    seen, total = set(), 0
    for name, entry in files.items():
        key = safe_name(name).casefold()
        if key in seen:
            raise Refused("source manifest has a duplicate path: " + name)
        seen.add(key)
        total += entry["size"]
        if total > MAX_ARCHIVE:
            raise Refused("source expansion limit exceeded")
    if shutil.disk_usage(destination).free < total + RESERVE:
        raise Refused("insufficient disk for the job's source and reserve")
    for name, entry in sorted(files.items()):
        target = destination.joinpath(*safe_name(name).split("/"))
        target.parent.mkdir(parents=True, exist_ok=True)
        stored = store_path(root, entry["sha256"])
        h = hashlib.sha256()
        with stored.open("rb") as source, target.open("xb") as output:
            while block := source.read(1024 * 1024):
                h.update(block)
                output.write(block)
        if h.hexdigest() != entry["sha256"]:
            # A damaged store entry heals: removed here, it is reported missing and
            # uploaded again by the next job instead of failing every later one.
            try:
                stored.unlink()
            except OSError:
                pass
            raise Refused("store entry " + entry["sha256"] + " was damaged and has been removed; the next job uploads it again")
    return {name: {"size": entry["size"], "sha256": entry["sha256"]} for name, entry in files.items()}


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


NATIVE_ARCHITECTURES = {"x86_64", "x86_32", "arm64", "arm32", "rv64", "universal", "wasm32"}


def _platform_tags():
    system = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}.get(platform.system(), platform.system().lower())
    machine = platform.machine().lower()
    machine = {"aarch64": "arm64", "amd64": "x86_64"}.get(machine, machine)
    return system, machine


def _extension_applies(key, system, machine):
    """Godot feature-tag match for one [libraries] key, e.g. ``macos.arm64`` or ``linux.debug``."""
    tags = key.strip().strip('"').split(".")
    if not tags or tags[0] != system:
        return False
    architectures = [tag for tag in tags[1:] if tag in NATIVE_ARCHITECTURES]
    return all(tag in {machine, "universal"} for tag in architectures)


def adapt_native_extensions(source):
    """Drop installed GDExtension descriptors that have no library for this host (TQ-05).

    ``app/native/`` holds git-ignored binaries built and installed per platform on
    the coordinator. A Windows/Linux descriptor shipped to a Mac makes Godot's
    import scan log errors, so every Mac import failed although the app itself
    selects its GDScript reference there. A native checkout on this host would
    not contain the descriptor; removing it reproduces that. Tracked descriptors
    elsewhere are never touched.
    """
    system, machine = _platform_tags()
    removed = []
    base = Path(source) / "app/native"
    for descriptor in sorted(base.rglob("*.gdextension")) if base.is_dir() else []:
        keys, section = [], None
        for line in descriptor.read_text(encoding="utf-8", errors="replace").splitlines():
            stripped = line.strip()
            if stripped.startswith("["):
                section = stripped
            elif section == "[libraries]" and "=" in stripped and not stripped.startswith(";"):
                keys.append(stripped.split("=", 1)[0])
        if any(_extension_applies(key, system, machine) for key in keys):
            continue
        relative = descriptor.relative_to(source).as_posix()
        descriptor.unlink()
        uid = descriptor.with_name(descriptor.name + ".uid")
        if uid.is_file():
            uid.unlink()
        removed.append({"path": relative, "libraries": sorted(key.strip() for key in keys)})
    return {"platform": f"{system}.{machine}", "removed_extensions": removed}


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


IMPORT_CACHE = "import-cache"


def _tree_stats(path):
    files = size = 0
    for current, _dirs, names in os.walk(path):
        for name in names:
            try:
                info = os.lstat(os.path.join(current, name))
            except OSError:
                continue
            if stat.S_ISREG(info.st_mode):
                files += 1
                size += info.st_size
    return files, size


def _clone_tree(source, destination, timeout):
    """Copy a tree, as a copy-on-write clone where the filesystem supports it.

    Never hard links: Godot rewrites imported files in place, which would
    change a shared inode.
    """
    commands = {"darwin": ["cp", "-cR"], "linux": ["cp", "-a", "--reflink=auto"]}
    command = commands.get(sys.platform)
    if command:
        try:
            subprocess.run(command + [str(source), str(destination)], check=True, timeout=timeout,
                           capture_output=True)
            return
        except (OSError, subprocess.SubprocessError):
            if destination.exists():
                shutil.rmtree(destination, ignore_errors=True)
    shutil.copytree(source, destination, symlinks=True)


def seed_import_cache(root, source, engine_sha256):
    """Start the import from this host's last good ``.godot/imported`` (TQ-05-F3.4).

    Godot revalidates every imported asset against its source md5 and
    reimports what changed. Only ``imported/`` is seeded, so the class, UID
    and filesystem caches are always rebuilt from this job's own source.
    """
    cache = Path(root) / IMPORT_CACHE / engine_sha256 / "imported"
    target = Path(source) / "app/.godot/imported"
    if not cache.is_dir():
        return {"seeded": False, "reason": "no cache for this engine yet"}
    if target.exists():
        return {"seeded": False, "reason": "workspace already has imports"}
    files, size = _tree_stats(cache)
    if shutil.disk_usage(source).free < size + RESERVE:
        return {"seeded": False, "reason": "insufficient disk for the import cache copy"}
    started = time.monotonic()
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        _clone_tree(cache, target, 600)
    except BaseException:
        shutil.rmtree(target, ignore_errors=True)  # a partial seed would only slow Godot down; start cold
        raise
    meta = read_json(cache.parent / "cache.json") if (cache.parent / "cache.json").is_file() else {}
    _mark_used(cache.parent / "cache.json")  # recently used engines keep their cache (TQ-07-G3)
    return {"seeded": True, "files": files, "bytes": size, "seconds": round(time.monotonic() - started, 2),
            "from_job": meta.get("job")}


def publish_import_cache(root, source, engine_sha256, identifier):
    """Keep this job's verified-good imports for the next job on this host.

    Called only after a complete, successful import, while this supervisor
    holds the host's pool lock, so there is a single writer.
    """
    imported = Path(source) / "app/.godot/imported"
    if not imported.is_dir():
        return {"published": False, "reason": "import produced no cache"}
    base = Path(root) / IMPORT_CACHE / engine_sha256
    base.mkdir(parents=True, exist_ok=True)
    for leftover in list(base.glob("staging-*")) + list(base.glob("old-*")):
        shutil.rmtree(leftover, ignore_errors=True)  # from an interrupted earlier publication
    files, size = _tree_stats(imported)
    if shutil.disk_usage(base).free < size + RESERVE:
        return {"published": False, "reason": "insufficient disk"}
    staging, old, current = base / ("staging-" + identifier), base / ("old-" + identifier), base / "imported"
    _clone_tree(imported, staging, 600)
    if current.exists():
        os.rename(current, old)
    os.rename(staging, current)
    write_json(base / "cache.json", {"job": identifier, "published_at": time.time(), "files": files, "bytes": size})
    shutil.rmtree(old, ignore_errors=True)
    return {"published": True, "files": files, "bytes": size}


def external_engine_present(engine):
    if os.name == "nt":
        # The pool deliberately leaves Windows admission to the enrolled worker.
        raise Refused("native Windows execution belongs to the existing testqueue authority")
    result = subprocess.run(["ps", "-A", "-o", "comm="], text=True, capture_output=True, check=True, timeout=10)
    if not result.stdout.strip():
        raise OSError("process table observation was empty")
    base = Path(engine).name.lower()
    for line in result.stdout.splitlines():
        name = Path(line.strip()).name.lower()
        if name and (name == base or "godot" in name):
            return True
    return False


def wait_for_engine(directory, state, request):
    """Keep the original exclusive grant while an external simulator uses the host."""
    engine = request["engine_path"]
    if not external_engine_present(engine):
        return
    deadline = time.monotonic() + request["options"].get("timeout", 600)
    state.update(stage="admission", reason_code="EXTERNAL_SIMULATOR",
                 reason="Waiting for external Godot before starting the checked runner",
                 admission_wait_started_at=time.time())
    write_json(directory / "state.json", state)
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            state.update(launch="NOT_CREATED", nonlaunch="CONFIRMED")
            raise Refused("EXTERNAL_SIMULATOR admission wait expired before process start", "EXTERNAL_SIMULATOR")
        time.sleep(min(1.0, remaining))
        if time.monotonic() < deadline and not external_engine_present(engine):
            if authority_enrolled() or digest(engine) != state["engine"]["sha256"]:
                raise Refused("host enrollment or engine changed during admission wait")
            if time.monotonic() < deadline and not external_engine_present(engine):
                break
    state["admission_wait_finished_at"] = time.time()
    for field in ("stage", "reason", "reason_code"):
        state.pop(field)


def execute_stage(root, directory, state, stage, deadline):
    # The agent runtime is pinned separately from the source archive.
    if time.monotonic() >= deadline:
        return {"ok": False, "complete": False, "reason": "timeout"}
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from tools.testqueue.processes import OwnedProcess, ProcessNotStartedError
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
    state.update(state="RUNNING", stage=stage, dispatch_at=time.time(), launch_order=LAUNCH_ORDER)
    write_json(directory / "state.json", state)
    started = False
    timed_out = False
    code = None
    try:
        # TQ-07-A9b: create the gated process, make its identity durable, and only
        # then release the gate. A record without an identity proves nothing ran.
        process.start(release=False)
        started = True
        state["process"] = process.identity
        if not journal_before_release(directory / "state.json", state):
            process.close_unreleased()  # the gate never released its command; teardown witnessed
            started = False
            state.pop("process", None)
            return {"ok": False, "complete": False, "reason": "journal_unavailable_before_release"}
        process.release()
        journaled = True
        retry_at = time.monotonic() + JOURNAL_RETRY_SECONDS
        unobserved = 0
        while True:
            code = process.poll()
            now = time.monotonic()
            if now >= deadline or (code is not None and code != 0):
                timed_out = now >= deadline
                process.terminate()
                break
            try:
                alive = process.alive()
            except (subprocess.TimeoutExpired, OSError):
                # TQ-07-A9c: a slow process listing is a missing observation, not a
                # reason to tear down healthy work; the deadline above still holds.
                unobserved += 1
                time.sleep(min(2.0, 0.1 * 2 ** min(unobserved, 5)))
                continue
            unobserved = 0
            if not alive:
                break
            if not journaled and now >= retry_at:
                journaled = publish_observation(directory / "state.json", state)
                retry_at = time.monotonic() + JOURNAL_RETRY_SECONDS
            time.sleep(0.1)
        code = process.poll()
        process.close()
        started = False
    except BaseException as failure:
        if started:
            try:
                if getattr(process, "released", True):
                    process.close()
                else:
                    process.close_unreleased()  # its command never ran (TQ-07-A9b)
            except Exception as error:
                raise TeardownUnconfirmed("process cleanup was not confirmed") from error
        elif not (isinstance(failure, ProcessNotStartedError) and process.nonlaunch_confirmed is True):
            # A failed launch can have dispatched before it reported an identity.
            # Only this adapter's own pre-create receipt proves nothing ran.
            raise TeardownUnconfirmed("process start or cleanup was not confirmed") from failure
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
    options = request["options"]
    if stage == "import":
        kwargs = {"required": [], "label": "import"}
    elif stage == "check":
        kwargs = {"required": options.get("require", []), **options.get("settings", {})}
    else:
        raise Refused("invalid internal stage")
    command = checked_command(request["engine_path"], str(source / "app"), options, stage)
    if stage != "check" or options.get("workload") != "graphics":
        # The supervisor owns the stricter per-stage deadline and verified cleanup.
        budget = IMPORT_BUDGET_SECONDS if stage == "import" else options.get("timeout", 600)
        result = module.run_checked(command, directory / stage, timeout=budget + 60, **kwargs)
        write_json(directory / (stage + "-result.json"), result)
        return 0
    config = graphics_config(root)
    if config is None:
        raise Refused("this host's GPU lane became unusable before the check")
    compositor = start_compositor(directory)
    try:
        if compositor is None:
            result = {"ok": False, "complete": False, "reason": "compositor_unavailable"}
        else:
            result = module.run_checked(command, directory / stage, timeout=options.get("timeout", 600) + 60, **kwargs)
    finally:
        stop_compositor(compositor)
    # The supervisor derives the GPU verdict from the verified engine log.
    write_json(directory / (stage + "-result.json"), result)
    return 0


def start_compositor(directory):
    """Start a private headless Wayland compositor for one rendered check.

    It stays in the stage's owned process group, so the supervisor's teardown
    proof covers it. Returns None when it does not come up within 15 s.
    """
    import tempfile
    # A fixed short parent: Unix socket paths are limited to 107 bytes and the
    # job's TMPDIR can be longer.
    runtime = Path(tempfile.mkdtemp(prefix="openrc-wl-", dir="/tmp" if os.path.isdir("/tmp") else None))
    os.chmod(runtime, 0o700)
    env = {k: v for k, v in os.environ.items() if k not in ("DISPLAY", "WAYLAND_DISPLAY")}
    env["XDG_RUNTIME_DIR"] = str(runtime)
    log = open(directory / "check-compositor.log", "wb")
    try:
        # kiosk-shell starts no helper clients; --no-config ignores any weston.ini.
        process = subprocess.Popen(["weston", "--no-config", "--backend=headless", "--renderer=gl", "--shell=kiosk",
                                    "--width=1920", "--height=1080", "--socket=wl-0", "--idle-time=0"],
                                   stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, env=env)
    except OSError:
        log.close()
        shutil.rmtree(runtime, ignore_errors=True)
        return None
    handle = {"process": process, "log": log, "runtime": runtime}
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline and process.poll() is None and not (runtime / "wl-0").exists():
        time.sleep(0.1)
    if process.poll() is not None or not (runtime / "wl-0").exists():
        stop_compositor(handle)
        return None
    os.environ.pop("DISPLAY", None)
    os.environ.update(XDG_RUNTIME_DIR=str(runtime), WAYLAND_DISPLAY="wl-0")
    return handle


def stop_compositor(handle):
    if not handle:
        return
    process = handle["process"]
    try:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
    finally:
        handle["log"].close()
        shutil.rmtree(handle["runtime"], ignore_errors=True)


def artifact_inventory(directory):
    items = {}
    for name in ("source-inventory.json", "import-result.json", "check-result.json", "import-runner.log", "check-runner.log",
                 "check-gpu.json", "check-compositor.log"):
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
    expected = checked_command(request["engine_path"], str(directory / "source/app"), options, stage)
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


def reserve_path(root, identifier):
    job_path(root, identifier)
    return root / "reserves" / identifier


def make_terminal_reserve(root, identifier):
    """Hold a little disk for the terminal journal (TQ-07-A9e); best effort.

    Kept outside the job directory so it is never inventoried as evidence.
    """
    try:
        path = reserve_path(root, identifier)
        path.parent.mkdir(exist_ok=True)
        with path.open("wb") as stream:
            stream.write(b"\0" * TERMINAL_RESERVE_BYTES)
            stream.flush()
            os.fsync(stream.fileno())
    except (OSError, Refused):
        pass


def release_terminal_reserve(root, identifier):
    try:
        reserve_path(root, identifier).unlink()
    except (OSError, Refused):
        pass


def supervise(root, identifier):
    path = state_path(root, identifier)
    # A storage sweep holds the host lock for one job at a time; wait for it
    # rather than leaving a never-started job behind (TQ-07-A9d).
    deadline = time.monotonic() + SUPERVISOR_LOCK_WAIT
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
    make_terminal_reserve(root, identifier)
    try:
        if state.get("state") != "STARTING":
            return 1
        request = validate_request(state["request"])
        if authority_enrolled():
            raise Refused("host enrolled before launch")
        source = directory / "source"
        if "source_manifest" in request:
            # TQ-07-E4a: the source comes from the content store; only missing
            # files ever crossed the network.
            manifest_sha = request["source_manifest"]["sha256"]
            files = materialize_from_store(root, read_source_manifest(root, manifest_sha), source)
            verify_source(source, files)
            write_json(directory / "source-inventory.json", {"manifest_sha256": manifest_sha, "files": files})
            state["input_mode"] = "content-store"
        else:
            source_archive = Path(request["archive"]["path"])
            copied = directory / "input.tar"
            try:
                # A hard link pins the verified inode without a second copy: incoming
                # archives are published by atomic replace, never rewritten in place.
                os.link(source_archive, copied)
                state["input_link"] = True
            except OSError:
                if shutil.disk_usage(directory).free < source_archive.stat().st_size + RESERVE:
                    raise Refused("insufficient disk for archive and reserve")
                with source_archive.open("rb") as src, copied.open("xb") as dst:
                    shutil.copyfileobj(src, dst, 1024 * 1024)
                    dst.flush()
                    os.fsync(dst.fileno())
            if digest(copied) != request["archive"]["sha256"]:
                raise Refused("transferred archive SHA-256 differs")
            files = extract_archive(copied, source)
            verify_source(source, files)
            write_json(directory / "source-inventory.json", {"archive_sha256": request["archive"]["sha256"], "files": files})
        transformation = isolate_project(source, identifier)
        state["native_adaptation"] = adapt_native_extensions(source)
        if not (source / "tools/godot/run_checked.py").is_file() or not (source / "app" / request["options"]["script"][6:]).is_file():
            raise Refused("snapshot is missing the checked runner or requested script")
        state.update(host={"hostname": platform.node(), "system": platform.system(), "machine": platform.machine()},
                     engine={"path": request["engine_path"], "sha256": digest(request["engine_path"])},
                     transformation=transformation, source_inventory_sha256=digest(directory / "source-inventory.json"))
        expected_engine = request.get("expected_engine_sha256")
        if expected_engine is not None and state["engine"]["sha256"] != expected_engine:
            raise Refused("engine SHA-256 differs from the selected host probe")
        # Seeding happens before the test budget starts and never fails the job.
        try:
            state["import_cache"] = seed_import_cache(root, source, state["engine"]["sha256"])
        except Exception as error:
            state["import_cache"] = {"seeded": False, "error": f"{type(error).__name__}: {error}"[:300]}
        # Preparation has no engine subprocess. Recheck occupancy at dispatch.
        # status/probe inspect the saved state without waiting for this slot.
        wait_for_engine(directory, state, request)
        started = True
        # TQ-07-A8: the import has its own budget; the job's timeout bounds the
        # check alone. A cold import used to consume the 90 s test budget.
        imported = execute_stage(root, directory, state, "import", time.monotonic() + IMPORT_BUDGET_SECONDS)
        verify_result(directory, "import", imported, request)
        state["import"] = imported
        if imported.get("reason") == "timeout":
            state["reason_code"] = "IMPORT_TIMEOUT"
        if digest(request["engine_path"]) != state["engine"]["sha256"]:
            raise Refused("engine executable changed during import")
        end = time.monotonic() + request["options"].get("timeout", 600)
        result = execute_stage(root, directory, state, "check", end) if imported.get("ok") is True and imported.get("complete") is True else None
        if (result or {}).get("reason") == "timeout":
            state["reason_code"] = "CHECK_TIMEOUT"
        if result is not None:
            verify_result(directory, "check", result, request)
        state["checked"] = result
        if digest(request["engine_path"]) != state["engine"]["sha256"]:
            raise Refused("engine executable changed during the attempt")
        if imported.get("ok") is True and imported.get("complete") is True:
            # After the check, so publication never consumes the test budget.
            try:
                state["import_cache"] = {**(state.get("import_cache") or {}),
                                         **publish_import_cache(root, source, state["engine"]["sha256"], identifier)}
            except Exception as error:
                state["import_cache"] = {**(state.get("import_cache") or {}), "published": False,
                                         "publish_error": f"{type(error).__name__}: {error}"[:300]}
        complete = bool(imported.get("complete") is True and result and result.get("complete") is True)
        if request["options"].get("workload") == "graphics":
            # A rendered check proves nothing unless it ran on the declared GPU:
            # a software or unexpected adapter is a host fault, not a test result.
            # The verdict comes from the engine log verify_result already bound.
            config = graphics_config(root)
            if not complete:
                reason = (result or {}).get("reason") or (imported.get("reason") if imported else None) or "incomplete"
                state["gpu"] = {"ok": False, "reason": reason, "device": None}
            elif config is None:
                state["gpu"] = {"ok": False, "reason": "gpu_lane_unavailable", "device": None}
            else:
                state["gpu"] = gpu_verdict(Path(result["log"]).read_text(encoding="utf-8", errors="replace"),
                                           config, request["options"]["rendering_driver"])
            write_json(directory / "check-gpu.json", state["gpu"])
            if state["gpu"].get("ok") is not True:
                complete = False
                state["error"] = "GPU lane: " + str(state["gpu"].get("reason"))
        ok = bool(complete and imported.get("ok") is True and result.get("ok") is True)
        state.update(state="FINISHED", outcome="PASSED" if ok else "TEST_FAILED" if complete else "INFRA_FAILED",
                     cleanup="CONFIRMED", evidence="COMPLETE" if complete else "INCOMPLETE",
                     artifacts=artifact_inventory(directory), finished_at=time.time())
        if ok:
            state["storage_cleanup"] = ({"state": "SKIPPED", "logical_bytes_removed": 0,
                                         "reason": "job input is a hard link to the verified incoming archive; no redundant copy"}
                                        if state.get("input_link") else
                                        {"state": "SKIPPED", "logical_bytes_removed": 0,
                                         "reason": "content-store job: no input archive was copied"}
                                        if state.get("input_mode") == "content-store" else
                                        {"state": "PENDING", "phase": "PREPARING", "logical_bytes_removed": None}
                                        if _retention_supported() else
                                        {"state": "SKIPPED", "reason": "descriptor-relative no-follow operations unavailable",
                                         "logical_bytes_removed": 0})
    except Exception as error:
        uncertain = started and isinstance(error, TeardownUnconfirmed)
        state.update(state="UNKNOWN" if uncertain else "FINISHED", outcome="INFRA_FAILED",
                     cleanup="UNCONFIRMED" if uncertain else "CONFIRMED", evidence="INCOMPLETE",
                     error=f"{type(error).__name__}: {error}", finished_at=time.time())
    finally:
        try:
            # FINISHED and its process-cleanup receipt must be durable before
            # reclaiming storage or releasing the host lock. Readers may observe
            # storage cleanup pending. The reserve goes first so a full disk can
            # still take this record (TQ-07-A9e).
            release_terminal_reserve(root, identifier)
            publish_terminal(path, state)
            if (state.get("state"), state.get("outcome"), state.get("evidence"), state.get("cleanup")) == (
                    "FINISHED", "PASSED", "COMPLETE", "CONFIRMED") and _retention_supported() \
                    and (state.get("storage_cleanup") or {}).get("state") == "PENDING":
                try:
                    _reclaim_success_input_locked(root, identifier)
                except (OSError, Refused, ValueError):
                    # The already-published execution outcome remains valid;
                    # unresolved cleanup is visible in its separate field.
                    pass
            # Bound the caches after every job, while this lock is held anyway, so
            # the store never grows until placement refuses the host for disk.
            try:
                bound_caches_locked(root, scan(root))
            except Exception:
                pass  # caches are reproducible; the next job or gc-incoming retries
        finally:
            lock.close()
    return 0


def _posix_group_absent(leader):
    """True when no process has the recorded gate as its PID or process group."""
    result = subprocess.run(["ps", "-A", "-o", "pid=,pgid="], capture_output=True, text=True, timeout=10, check=True)
    rows = [line.split() for line in result.stdout.splitlines() if line.strip()]
    if not rows:
        raise RuntimeError("process table observation was empty")
    return not any(len(fields) >= 2 and str(leader) in fields[:2] for fields in rows)


def _operator_request(request, fields):
    if (not isinstance(request, dict) or set(request) != fields or request.get("operator_confirm") is not True
            or not isinstance(request.get("request_id"), str) or not ID.fullmatch(request["request_id"])):
        raise Refused("operator action requires request_id and operator_confirm: true")


def reconcile_unknown(root, request):
    """Operator release of an UNKNOWN job whose process group is proved gone.

    Proof is a reboot since the recorded boot, or (same boot) a free host lock,
    meaning no supervisor is alive, and no process left in the recorded gate's
    PID or process group. Missing identity is never proof.
    """
    _operator_request(request, {"request_id", "operator_confirm"})
    path = state_path(root, request["request_id"])
    lock = Lock(root / "pool.lock")
    try:
        state = read_json(path)
        if state.get("state") != "UNKNOWN":
            raise Refused("only an UNKNOWN job can be reconciled", "CONFLICT")
        process = state.get("process")
        if not isinstance(process, dict):
            raise Refused("no recorded process identity; teardown cannot be proved", "CONFLICT")
        runtime = str(Path(__file__).resolve().parents[2])  # pinned agent runtime, as in execute_stage
        if runtime not in sys.path:
            sys.path.insert(0, runtime)
        from tools.testqueue.processes import confirm_stopped
        if confirm_stopped({"host": process.get("host"), "boot": process.get("boot")}):
            proof = "host rebooted since the recorded boot"
        else:
            leader = process.get("pid")
            if type(leader) is not int or leader <= 1:
                raise Refused("recorded process identity has no usable PID", "CONFLICT")
            if not _posix_group_absent(leader):
                raise Refused("recorded process group still has members; not released", "CONFLICT")
            proof = f"host lock free and no process in PID/PGID {leader} (same boot)"
        state.update(state="FINISHED", outcome="INFRA_FAILED", cleanup="CONFIRMED", evidence="INCOMPLETE",
                     reconciliation={"proof": proof, "operator_confirmed": True, "at": time.time(),
                                     "previous_error": state.get("error")},
                     finished_at=time.time())
        publish_terminal(path, state)
        return public_status(state)
    finally:
        lock.close()


def _group_proved_absent(pid):
    if type(pid) is not int or pid <= 1:
        return False
    try:
        return _posix_group_absent(pid)
    except (OSError, RuntimeError, subprocess.SubprocessError):
        return False


def recover_boot(root, request):
    """Settle every UNKNOWN job whose recorded boot ended (TQ-07-A9f).

    The coordinator calls this for a host that returns. A reboot since the
    recorded process identity is the one proof accepted without an operator;
    same-boot evidence keeps the operator ``reconcile`` path.
    """
    if not isinstance(request, dict) or request:
        raise Refused("recover-boot takes an empty request")
    runtime = str(Path(__file__).resolve().parents[2])  # pinned agent runtime, as in execute_stage
    if runtime not in sys.path:
        sys.path.insert(0, runtime)
    from tools.testqueue.processes import confirm_stopped
    lock = Lock(root / "pool.lock")
    try:
        settled, kept = [], []
        for path in sorted((root / "jobs").glob("*/state.json")):
            try:
                state = read_json(path)
            except (OSError, ValueError):
                kept.append(path.parent.name)
                continue
            if state.get("state") != "UNKNOWN":
                continue
            process = state.get("process")
            if isinstance(process, dict) and confirm_stopped({"host": process.get("host"), "boot": process.get("boot")}) \
                    and _group_proved_absent(process.get("pid")):
                # macOS derives its boot identity from kern.boottime, which can
                # shift without a reboot; unattended settlement therefore also
                # needs the recorded process group gone, as a real reboot ensures.
                state.update(state="FINISHED", outcome="INFRA_FAILED", cleanup="CONFIRMED", evidence="INCOMPLETE",
                             reason_code="HOST_REBOOTED",
                             reconciliation={"proof": "host rebooted since the recorded boot", "automatic": True,
                                             "at": time.time(), "previous_error": state.get("error")},
                             finished_at=time.time())
                publish_terminal(path, state)
                settled.append(path.parent.name)
            else:
                kept.append(path.parent.name)
        return {"settled": settled, "still_unknown": kept}
    finally:
        lock.close()


def _tree_bytes(path):
    total = 0
    for base, _, files in os.walk(path):
        for name in files:
            with contextlib.suppress(OSError):
                total += os.lstat(os.path.join(base, name)).st_size
    return total


RECLAIMABLE_FAILURES = frozenset({"TEST_FAILED", "TIMED_OUT", "INFRA_FAILED"})
RESIDUE_SAMPLE = 20


def _failure_reclaim_supported():
    # Pool hosts are macOS and Linux. Windows unlink fails on read-only files and
    # its rmtree is not descriptor-based, so a Windows remote keeps failures.
    return os.name != "nt"


def _reclaim_reproducible(directory, state):
    """Remove only bytes a failed job can regenerate; keep everything the run made.

    Deleted: the job's input archive copies, Godot's import cache
    (``source/app/.godot``), Python bytecode caches and every extracted source
    file whose size and SHA-256 still match the job's own verified inventory.
    Retained as residue: any other file under ``source`` (written or changed by
    the run, for example by ``isolate_project``), plus the job record, logs,
    stage outputs and profile outside ``source``. Each step is idempotent, so a
    retry after an interrupted sweep only finishes the same removal.
    """
    removed = {"files": 0, "bytes": 0}
    names = []

    def unlink(path):
        info = os.lstat(path)
        os.unlink(path)
        removed["files"] += 1
        removed["bytes"] += info.st_size

    for name in ("input.tar", "retained-input.tar"):
        target = directory / name
        if target.is_symlink():
            raise Refused(f"{name} is a link; not removed", "CONFLICT")
        if target.is_file():
            unlink(target)
            names.append(name)
    source = directory / "source"
    if source.is_symlink():
        raise Refused("source is a link; not removed", "CONFLICT")
    retained = {"files": 0, "bytes": 0, "sample": []}
    if not source.is_dir():
        return names, removed, retained
    imports = source / "app" / ".godot"
    if imports.is_symlink():
        raise Refused("source/app/.godot is a link; not removed", "CONFLICT")
    if imports.is_dir():
        removed["bytes"] += _tree_bytes(imports)
        shutil.rmtree(imports)  # descriptor-based on POSIX; does not follow links
        names.append("source/app/.godot")
    inventory = {}
    inventory_path = directory / "source-inventory.json"
    if (inventory_path.is_file() and not inventory_path.is_symlink()
            and digest(inventory_path) == state.get("source_inventory_sha256")):
        files = read_json(inventory_path).get("files")
        inventory = files if isinstance(files, dict) else {}
    for base, dirs, files in os.walk(source, topdown=False):
        for name in files:
            path = Path(base) / name
            relative = path.relative_to(source).as_posix()
            info = os.lstat(path)
            expected = inventory.get(relative)
            reproducible = stat.S_ISREG(info.st_mode) and (
                path.parent.name == "__pycache__" and name.endswith(".pyc")
                or isinstance(expected, dict) and expected.get("size") == info.st_size
                and expected.get("sha256") == digest(path))
            if reproducible:
                unlink(path)
            else:
                retained["files"] += 1
                retained["bytes"] += info.st_size
                if len(retained["sample"]) < RESIDUE_SAMPLE:
                    retained["sample"].append(relative)
        for name in dirs:
            with contextlib.suppress(OSError):
                os.rmdir(Path(base) / name)  # only empty directories; a link is never followed
    with contextlib.suppress(OSError):
        os.rmdir(source)
    if removed["files"] or not source.exists():
        names.append("source (inventory-verified files)")
    return names, removed, retained


def collect_garbage(root, request):
    """Remove reproducible input copies of one collected, finished job.

    The coordinator calls this only after verifying its own collected evidence.
    A PASSED/COMPLETE/CONFIRMED job loses its whole extracted source and archive
    copies. A finished failure with confirmed cleanup (TEST_FAILED, TIMED_OUT,
    INFRA_FAILED) loses only what ``_reclaim_reproducible`` proves it can
    regenerate; files the run wrote are retained. The job record, logs, reports
    and stage outputs always stay; UNKNOWN or unconfirmed jobs are never touched.
    """
    if (not isinstance(request, dict) or set(request) != {"request_id", "payload_sha256", "operator_confirm"}
            or request.get("operator_confirm") is not True
            or not isinstance(request.get("payload_sha256"), str)
            or not re.fullmatch(r"[0-9a-f]{64}", request["payload_sha256"])):
        raise Refused("gc requires request_id, lowercase payload_sha256 and operator_confirm: true")
    _operator_request({key: request[key] for key in ("request_id", "operator_confirm")},
                      {"request_id", "operator_confirm"})
    directory = job_path(root, request["request_id"])
    path = directory / "state.json"
    lock = Lock(root / "pool.lock")
    try:
        state = read_json(path)
        if state.get("payload_sha256") != request["payload_sha256"]:
            raise Refused("payload identity differs from the collected job", "CONFLICT")
        if (state.get("state") == "FINISHED" and state.get("cleanup") == "CONFIRMED"
                and state.get("outcome") in RECLAIMABLE_FAILURES):
            if (state.get("storage_gc") or {}).get("state") == "RECLAIMED":
                return {"request_id": request["request_id"], **state["storage_gc"]}
            if state.get("reconciliation"):
                # An operator-reconciled UNKNOWN attempt keeps its only forensic copy.
                raise Refused("an operator-reconciled attempt keeps its source", "CONFLICT")
            if not _failure_reclaim_supported():
                raise Refused("failure reclamation needs POSIX unlink semantics", "UNSUPPORTED")
            # Durable intent first: an interrupted sweep is visible and a retry finishes it.
            state["storage_gc"] = {"state": "PENDING", "at": time.time(),
                                   "scope": "reproducible inputs of a finished failure; run residue retained"}
            publish_terminal(path, state)
            names, removed, retained = _reclaim_reproducible(directory, state)
            state["storage_gc"] = {"state": "RECLAIMED", "removed": names, "logical_bytes_removed": removed["bytes"],
                                   "files_removed": removed["files"], "retained_residue": retained, "at": time.time(),
                                   "scope": "reproducible inputs of a finished failure; run residue retained"}
            publish_terminal(path, state)
            return {"request_id": request["request_id"], "removed": names,
                    "logical_bytes_removed": removed["bytes"], "retained_residue": retained}
        if (state.get("state"), state.get("outcome"), state.get("evidence"), state.get("cleanup")) != (
                "FINISHED", "PASSED", "COMPLETE", "CONFIRMED"):
            raise Refused("only a finished job with confirmed cleanup (PASSED with complete evidence, "
                          "or TEST_FAILED/TIMED_OUT/INFRA_FAILED) is collected", "CONFLICT")
        removed, names = 0, []
        for name in ("source", "input.tar", "retained-input.tar"):
            target = directory / name
            if target.is_symlink():
                raise Refused(f"{name} is a link; not removed", "CONFLICT")
            if target.is_dir():
                removed += _tree_bytes(target)
                shutil.rmtree(target)  # descriptor-based on POSIX; does not follow links
                names.append(name)
            elif target.is_file():
                removed += target.stat().st_size
                target.unlink()
                names.append(name)
        state["storage_gc"] = {"state": "RECLAIMED", "removed": names, "logical_bytes_removed": removed,
                               "at": time.time(), "scope": "source and archive copies after verified collection"}
        publish_terminal(path, state)
        return {"request_id": request["request_id"], "removed": names, "logical_bytes_removed": removed}
    finally:
        lock.close()


def collect_incoming(root, request, *, min_age=3600):
    """Remove cached incoming archives that no unfinished job uses.

    Archives are content-addressed caches: a later dispatch re-uploads a
    missing one. Uploads in progress (.pending) and recent files are kept.
    """
    if not isinstance(request, dict) or set(request) != {"operator_confirm"} or request["operator_confirm"] is not True:
        raise Refused("gc-incoming requires operator_confirm: true")
    lock = Lock(root / "pool.lock")
    try:
        unfinished = scan(root)
        if any(not isinstance(state.get("request"), dict) for state in unfinished):
            raise Refused("an unfinished job's archive is unknown; nothing removed", "CONFLICT")
        active = {str((state["request"].get("archive") or {}).get("sha256")) for state in unfinished}
        removed, files = 0, []
        now = time.time()
        for path in sorted((root / "incoming").iterdir()):
            if (path.is_symlink() or not path.is_file() or not re.fullmatch(r"[0-9a-f]{64}\.tar", path.name)
                    or path.name[:-4] in active or now - path.stat().st_mtime < min_age):
                continue
            removed += path.stat().st_size
            path.unlink()
            files.append(path.name)
        # Temporaries of an interrupted store upload (TQ-07-E4a review); a live
        # upload publishes or removes its own within the hour.
        for path in sorted((root / STORE).glob("*/*.pending")) if (root / STORE).is_dir() else []:
            if path.is_symlink() or not path.is_file() or now - path.stat().st_mtime < min_age:
                continue
            removed += path.stat().st_size
            path.unlink()
        # Terminal reserves a lost supervisor left behind (TQ-07-A9e). Under this
        # lock no supervisor runs, so only an unfinished job's reserve is kept.
        reserves = 0
        live = {state.get("request_id") for state in unfinished}
        for path in sorted((root / "reserves").glob("*")) if (root / "reserves").is_dir() else []:
            if path.is_symlink() or not path.is_file() or path.name in live:
                continue
            removed += path.stat().st_size
            path.unlink()
            reserves += 1
        try:
            bounds = bound_caches_locked(root, unfinished)
        except Exception as error:  # what was already removed above is still reported
            text = f"{type(error).__name__}: {error}"[:300]
            bounds = {"store": {"skipped": text}, "import_caches": {"skipped": text}}
        removed += bounds["store"].get("bytes_removed", 0) + bounds["import_caches"].get("bytes_removed", 0)
        return {"removed_files": len(files), "removed_reserves": reserves, "logical_bytes_removed": removed,
                "store": bounds["store"], "import_caches": bounds["import_caches"]}
    finally:
        lock.close()


CACHE_BOUNDS = "cache-bounds.json"


def bound_caches_locked(root, unfinished):
    """Keep the content store and import caches within their bounds (TQ-07-G3).

    The caller holds the host lock. An unfinished job keeps every file its
    manifest names and its engine's import cache. A job whose request or
    manifest cannot be read leaves those unknown, so nothing is pruned. The
    report is kept in ``cache-bounds.json`` for the probe.
    """
    protected, engines, request_unknown, manifest_unknown = set(), set(), False, False
    for state in unfinished:
        request = state.get("request")
        if not isinstance(request, dict):
            request_unknown = True
            continue
        for engine in ((state.get("engine") or {}).get("sha256"), request.get("expected_engine_sha256")):
            if isinstance(engine, str):
                engines.add(engine)
        manifest = (request.get("source_manifest") or {}).get("sha256")
        if manifest is None:
            continue
        protected.add(manifest)
        try:
            protected.update(entry["sha256"] for entry in read_source_manifest(root, manifest).values())
        except (Refused, OSError, ValueError):
            manifest_unknown = True
    if request_unknown or manifest_unknown:
        why = "an unfinished job's " + ("request" if request_unknown else "source manifest") + " is unreadable"
        store = {"skipped": why + "; the store is kept whole"}
    else:
        store = prune_store(root, protected)
    import_caches = ({"skipped": "an unfinished job's request is unreadable; its engine is unknown"}
                     if request_unknown else prune_import_caches(root, engines))
    report = {"store": store, "import_caches": import_caches}
    if "skipped" not in store:
        try:
            write_json(Path(root) / CACHE_BOUNDS, {**report, "at": time.time()})
        except OSError:
            pass  # the probe then shows an older store size; pruning itself already happened
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("probe", "run", "status", "fence", "recover-boot", "store-have",
                                           "store-put", "reclaim-input", "reconcile", "gc", "gc-incoming",
                                           "_supervise", "_invoke"))
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
        if args.action == "store-put":
            # A tar stream of content-addressed files, not a JSON request (TQ-07-E4a).
            print(json.dumps({"ok": True, "result": store_put(root, sys.stdin.buffer)}, allow_nan=False))
            return 0
        raw = sys.stdin.buffer.read(LIMIT + 1)
        if len(raw) > LIMIT:
            raise Refused("request too large")
        request = json.loads(raw or b"{}")
        if args.action == "probe":
            result = probe(root, request)
        elif args.action == "run":
            result = launch(root, request)
        elif args.action == "fence":
            result = fence(root, request)
        elif args.action == "recover-boot":
            result = recover_boot(root, request)
        elif args.action == "store-have":
            result = store_have(root, request)
        elif args.action == "reclaim-input":
            if (not isinstance(request, dict) or set(request) != {"request_id", "payload_sha256"}
                    or not isinstance(request.get("request_id"), str) or not ID.fullmatch(request["request_id"])
                    or not isinstance(request.get("payload_sha256"), str)
                    or not re.fullmatch(r"[0-9a-f]{64}", request["payload_sha256"])):
                raise Refused("reclaim-input requires request_id and lowercase payload_sha256")
            result = reclaim_success_input(root, request["request_id"], expected_payload_sha256=request["payload_sha256"])
        elif args.action == "reconcile":
            result = reconcile_unknown(root, request)
        elif args.action == "gc":
            result = collect_garbage(root, request)
        elif args.action == "gc-incoming":
            result = collect_incoming(root, request)
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
