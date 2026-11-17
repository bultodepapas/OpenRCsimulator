"""Persistent host-local coordinator and worker, with fail-closed recovery."""
from __future__ import annotations

import copy
import hashlib
import hmac
import json
import os
from pathlib import Path
import platform
import secrets
import shutil
import socket
import socketserver
import subprocess
import sys
import threading
import time
import uuid

from .common import LIMIT, VERSION, Singleton, HostSingleton, write_json
from .presets import scheduling, validate
from .store import StaleTransition, Store


_SCHEDULER_INTERVAL = 0.1
_SCHEDULER_MAX_BACKOFF = 5.0
_SCHEDULER_STALE_SECONDS = 30.0
# Owned execution never waits indefinitely for the storage/admission lock. A
# busy or hung journal delays observation and journaling, not ownership,
# cancellation of an already observed request, or the admitted hard deadline.
_OBSERVATION_LOCK_SECONDS = 0.5
_MONITOR_LOCK_SECONDS = 0.05     # per-pass waits inside the 0.1 s monitor loop
_FINAL_OBSERVATION_SECONDS = 5.0  # terminal cancel attribution is not time-critical
_JOURNAL_RETRY_SECONDS = 1.0
_PROCESS_LOCK_SECONDS = 0.2
_HOSTS_LOCK_SECONDS = 1.0
_CAPACITY_SECONDS = 1.0


class _OwnershipBusy(RuntimeError):
    """Occupancy cannot be observed now; never evidence that a host is free."""


class _LaunchGate:
    """One-way scheduler decision: a started thread cannot execute while pending."""

    def __init__(self):
        self._lock = threading.Lock()
        self._resolved = threading.Event()
        self._decision = None

    def resolve(self, allowed):
        with self._lock:
            if self._decision is not None:
                raise RuntimeError("attempt launch decision already made")
            self._decision = allowed
            self._resolved.set()

    def allowed(self):
        self._resolved.wait()
        return self._decision is True


def sha256(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def external_simulators() -> list[int]:
    """Read-only occupancy probe. An unavailable probe blocks rendered admission."""
    if os.name != "nt":
        raise RuntimeError("native process containment has not been qualified on this platform")
    completed = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True, text=True, timeout=10,
                               creationflags=subprocess.CREATE_NO_WINDOW)
    if completed.returncode:
        raise RuntimeError("cannot inspect external simulator occupancy")
    import csv
    return [int(row[1]) for row in csv.reader(completed.stdout.splitlines())
            if len(row) > 1 and "godot" in row[0].lower() and row[1].isdigit()]


def desktop_ready() -> bool:
    """Native worker must run in an active logged-in session on Default desktop."""
    if os.name != "nt":
        return False
    import ctypes
    from ctypes import wintypes
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    user = ctypes.WinDLL("user32", use_last_error=True)
    wts = ctypes.WinDLL("wtsapi32", use_last_error=True)
    kernel.ProcessIdToSessionId.argtypes = [wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
    kernel.ProcessIdToSessionId.restype = wintypes.BOOL
    session = wintypes.DWORD()
    if not kernel.ProcessIdToSessionId(os.getpid(), ctypes.byref(session)) or session.value == 0:
        return False
    wts.WTSQuerySessionInformationW.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.c_int, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(wintypes.DWORD)]
    wts.WTSQuerySessionInformationW.restype = wintypes.BOOL
    wts.WTSFreeMemory.argtypes = [ctypes.c_void_p]
    buffer, size = ctypes.c_void_p(), wintypes.DWORD()
    if not wts.WTSQuerySessionInformationW(None, session, 8, ctypes.byref(buffer), ctypes.byref(size)):
        return False
    try:
        if size.value < 4 or ctypes.cast(buffer, ctypes.POINTER(ctypes.c_int))[0] != 0:
            return False
    finally:
        wts.WTSFreeMemory(buffer)
    user.OpenInputDesktop.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    user.OpenInputDesktop.restype = wintypes.HANDLE
    user.GetUserObjectInformationW.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
    user.GetUserObjectInformationW.restype = wintypes.BOOL
    user.CloseDesktop.argtypes = [wintypes.HANDLE]
    handle = user.OpenInputDesktop(0, False, 1)
    if not handle:
        return False
    try:
        name, needed = ctypes.create_unicode_buffer(256), wintypes.DWORD()
        return bool(user.GetUserObjectInformationW(handle, 2, name, ctypes.sizeof(name), ctypes.byref(needed))) and name.value.casefold() == "default"
    finally:
        user.CloseDesktop(handle)


class Worker:
    def __init__(self, root: Path, repo: Path, engine: Path, *, slots: int = 1, capture_slots: int = 1, fixture=False):
        if type(slots) is not int or not 1 <= slots <= 8 or type(capture_slots) is not int or not 1 <= capture_slots <= 4:
            raise ValueError("headless slots must be in 1..8 and capture slots in 1..4")
        self.root, self.repo, self.engine = root.resolve(), repo.resolve(), engine.resolve()
        if os.name == "nt":
            import ctypes
            kernel = ctypes.WinDLL("kernel32", use_last_error=True)
            kernel.GetDriveTypeW.argtypes = [ctypes.c_wchar_p]
            kernel.GetDriveTypeW.restype = ctypes.c_uint
            if self.root.drive.startswith("\\\\") or kernel.GetDriveTypeW(self.root.anchor) == 4:
                raise ValueError("SQLite worker state must use a local filesystem, never a network share")
        if self.root == self.repo or self.repo in self.root.parents:
            raise ValueError("worker state must be outside developer checkouts")
        self.root.mkdir(parents=True, exist_ok=True)
        self.singleton = Singleton(self.root / "worker.lock")
        from .processes import host_identity
        self.host_guard = None if fixture else HostSingleton(host_identity()["host"])
        self.lock = threading.RLock()
        # Guards OwnedProcess handle methods (not thread-safe) and ``active``.
        # Lock order: ``lock`` may be held while taking ``_process_lock``; never
        # the reverse. Teardown therefore cannot wait behind a stalled journal.
        self._process_lock = threading.RLock()
        # At most one filesystem capacity observation is in flight; callers
        # share it and stop waiting after _CAPACITY_SECONDS.
        self._capacity_lock = threading.Lock()
        self._capacity_probe: tuple[threading.Thread, dict] | None = None
        self.store = Store(self.root)
        self.auth = secrets.token_hex(32)
        self.contexts: dict[str, tuple[str, str]] = {}
        self.active: dict[str, object] = {}
        self._closing: set[str] = set()
        self._unresolved_attempts: set[str] = set()
        self._pending_unknown: dict[str, tuple[str, dict]] = {}
        self._pending_nonlaunch: dict[str, tuple[str, dict]] = {}
        # Newest unrecorded transition of an owned attempt. Storage failure keeps
        # it here for ordered retry; it never tears down the owned process.
        self._journal_lock = threading.Lock()
        self._pending_journal: dict[str, tuple[str, str, dict]] = {}
        self._journal_errors: dict[str, str] = {}
        self.stopping = threading.Event()
        self._scheduler_lock = threading.Lock()
        self._scheduler_thread = None
        self._scheduler_state = "STARTING"
        self._scheduler_last_success = None
        self._scheduler_last_success_monotonic = None
        self._scheduler_last_dispatch = None
        self._scheduler_error = None
        self._scheduler_diagnostic_error = None
        self._scheduler_needs_storage_check = False
        self._scheduler_fault_version = 0
        self.draining = False
        self.reservation = None
        self._occupancy_cache = None
        self.fixture = fixture
        self.capacities = {"rendered": capture_slots, "headless": slots,
                           "cpu": slots + capture_slots, "memory": slots + capture_slots, "exclusive": 1}
        self.host_id = self._host_id()
        self.engine_identity = {} if fixture else self._engine_identity()
        self.studio_adapter_identity = {} if fixture else self._studio_identity(self.repo)

    def _host_id(self):
        path = self.root / "host.json"
        if path.exists():
            return json.loads(path.read_text())["id"]
        identity = uuid.uuid4().hex
        write_json(path, {"id": identity, "hostname": socket.gethostname(), "created": time.time()})
        return identity

    @staticmethod
    def _studio_identity(root):
        # Bind the Python launch path as well as the GDScript. Added package
        # initializers and shadow modules can execute before an imported module.
        paths = {root / "tools/readme/capture_aircraft.gd"}
        for parent in (root, root / "tools"):
            paths.update(parent.glob("*.py"))
        for parent in (root / "tools/testqueue", root / "tools/godot"):
            paths.update(parent.rglob("*.py"))
        return {path.relative_to(root).as_posix(): sha256(path) for path in sorted(paths)}

    def _verify_studio_adapter(self, source):
        if self._studio_identity(source) != self.studio_adapter_identity:
            raise ValueError("ADAPTER_MISMATCH: parallel aircraft captures require the worker's reviewed Python and studio adapters")

    def _external_conflicts(self, *, refresh=False):
        now = time.monotonic()
        if refresh or self._occupancy_cache is None or now - self._occupancy_cache[0] >= 1:
            self._occupancy_cache = (now, set(external_simulators()))
        managed = set()
        # Callers hold ``lock``; never let them wait out another attempt's
        # teardown. Busy ownership is unknown occupancy, which fails closed.
        if not self._process_lock.acquire(timeout=_PROCESS_LOCK_SECONDS):
            raise _OwnershipBusy("managed process ownership is busy (teardown in progress)")
        try:
            for process in self.active.values():
                if process is not None:
                    managed.update(process.pids())
        finally:
            self._process_lock.release()
        return self._occupancy_cache[1] - managed

    def _engine_identity(self):
        if not self.engine.is_file():
            raise ValueError("engine executable is missing")
        pin = (self.repo / "app/get-godot.sh").read_text(encoding="utf-8")
        import re
        # Exact official build identifier comes from the tested revision, not a moving stable alias.
        versions = re.findall(r'4\.[0-9]+\.[A-Za-z0-9.]+\.official\.[0-9a-f]+', pin)
        observed = subprocess.check_output([str(self.engine), "--version"], timeout=15, text=True, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0).strip()
        if not versions or observed not in versions:
            raise ValueError(f"ENGINE_MISMATCH: {observed}; revision pins {versions}")
        binaries = {self.engine.name: sha256(self.engine)}
        binary_sha512 = {}
        if os.name == "nt" and self.engine.name.endswith("_console.exe"):
            companion = self.engine.with_name(self.engine.name.replace("_console.exe", ".exe"))
            if not companion.is_file():
                raise ValueError("Windows engine companion executable missing")
            binaries[companion.name] = sha256(companion)
        for name in binaries:
            value = hashlib.sha512()
            with (self.engine.parent / name).open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    value.update(chunk)
            binary_sha512[name] = value.hexdigest()
        identity = {"path": str(self.engine), "version": observed, "binaries_sha256": binaries, "binaries_sha512": binary_sha512}
        self._check_engine_pin(pin, identity)
        return identity

    @staticmethod
    def _check_engine_pin(pin, identity):
        import re
        versions = re.findall(r'4\.[0-9]+\.[A-Za-z0-9.]+\.official\.[0-9a-f]+', pin)
        if identity["version"] not in versions:
            raise ValueError("ENGINE_MISMATCH: snapshot pins another engine")
        if os.name == "nt":
            windows = re.search(r'MINGW\*.*?BINARY_SHA512=\(([^)]+)\)', pin, re.S)
            if not windows or set(identity["binaries_sha512"].values()) != set(windows[1].split()):
                raise ValueError("ENGINE_MISMATCH: Windows binary digests do not match snapshot's official pins")

    def _storage_capacity(self):
        """Bounded capacity observation; a stalled volume reports unknown, never free."""
        with self._capacity_lock:
            if self._capacity_probe is None or not self._capacity_probe[0].is_alive():
                box: dict = {}
                def observe():
                    box["value"] = self._observe_storage_capacity()
                thread = threading.Thread(target=observe, name="testqueue-capacity", daemon=True)
                self._capacity_probe = (thread, box)
                thread.start()
            thread, box = self._capacity_probe
        thread.join(_CAPACITY_SECONDS)
        if "value" in box:
            return box["value"]
        return {"available": False, "path": str(self.root / "attempts"), "free_bytes": None,
                "total_bytes": None, "observed_at": time.time(),
                "error": f"filesystem capacity observation still pending after {_CAPACITY_SECONDS:g} s",
                "scope": "attempt filesystem volume; not reserved capacity"}

    def _observe_storage_capacity(self):
        """Observe the materialization volume; unknown is never empty/free."""
        path = self.root / "attempts"
        try:
            if not path.exists():
                path = self.root
            usage = shutil.disk_usage(path)
            if (any(type(value) is not int or value < 0 for value in (usage.total, usage.used, usage.free))
                    or usage.free > usage.total):
                raise ValueError("invalid filesystem capacity observation")
            return {"available": True, "path": str(path), "free_bytes": usage.free,
                    "total_bytes": usage.total, "observed_at": time.time(),
                    "scope": "attempt filesystem volume; not reserved capacity"}
        except (OSError, ValueError, RuntimeError) as error:
            return {"available": False, "path": str(path), "free_bytes": None,
                    "total_bytes": None, "observed_at": time.time(), "error": str(error),
                    "scope": "attempt filesystem volume; not reserved capacity"}

    def dispatch(self, request: dict):
        if not hmac.compare_digest(str(request.get("auth", "")), self.auth):
            raise ValueError("invalid worker authority")
        operation = request.get("operation")
        # Filesystem capacity is advisory and can be slow. Do not hold the
        # admission lock while asking the OS about the attempt volume.
        if operation == "hosts":
            return self._hosts(self._storage_capacity())
        with self.lock:
            if operation in {"status", "result"}:
                return self._status(request["job"])
            if operation == "list":
                return [self._status(row[0]) for row in self.store.db.execute("SELECT id FROM jobs ORDER BY submitted DESC LIMIT 100")]
            if operation == "recover":
                return self.store.recover(request["request_id"], request["request_secret"])
            if operation == "cancel_submission":
                return self.store.cancel_submission(request["request_id"], request["request_secret"])
            if operation == "validate":
                return self._validate_context(request["context"], request["scope"])
            if operation == "authorize":
                job = self.store.authorize(request["handle"])
                status = self.store.get(job)
                if status["state"] not in {"RUNNING", "CLEANING"} or status.get("session", {}).get("port") != request["port"]:
                    raise ValueError("session handle does not own this live port")
                return {"job": job}
            if operation == "cancel":
                job = self.store.authorize(request["handle"])
                self.store.cancel(job)
                return self.store.get(job)
            if operation == "drain":
                self.draining = bool(request["enabled"])
                write_json(self.root / "policy.json", {"draining": self.draining, "reservation": self.reservation})
                return {"draining": self.draining}
            if operation == "reserve":
                if self.reservation:
                    raise ValueError("desktop already reserved")
                if self.store.db.execute("SELECT 1 FROM claims WHERE resource IN ('rendered','exclusive') LIMIT 1").fetchone():
                    raise ValueError("desktop is occupied by a managed attempt")
                token = secrets.token_hex(32)
                self.reservation = {"owner": request["owner"], "secret": token, "since": time.time()}
                write_json(self.root / "policy.json", {"draining": self.draining, "reservation": self.reservation})
                return {"handle": token}
            if operation == "release":
                if not self.reservation or not hmac.compare_digest(self.reservation["secret"], request["handle"]):
                    raise ValueError("reservation handle required")
                self.reservation = None
                write_json(self.root / "policy.json", {"draining": self.draining, "reservation": None})
                return {"released": True}
            if operation == "reconcile":
                return self._reconcile(request)
            if operation == "abandon":
                job = self.store.authorize(request["handle"])
                status = self.store.get(job)
                from .processes import orphan_absent
                if not self.draining or status["state"] != "UNKNOWN":
                    raise ValueError("operator abandonment requires a drained worker and an UNKNOWN attempt")
                if self.active or self.contexts:
                    raise ValueError("attempt still belongs to an executing supervisor thread")
                with self._journal_lock:
                    pending_journals = bool(self._pending_journal)
                if (self._unresolved_attempts or self._pending_unknown or self._pending_nonlaunch
                        or pending_journals or self._closing):
                    raise ValueError("operator abandonment requires pending attempt journals to recover first")
                if self.store.db.execute("SELECT 1 FROM attempts WHERE state IN ('DISPATCHING','RUNNING','CLEANING') LIMIT 1").fetchone():
                    raise ValueError("operator abandonment requires no executing attempts")
                if not orphan_absent(status.get("process")):
                    raise ValueError("recorded gate/job absence cannot be established")
                self.store.abandon(job, request.get("reason"))
                return self.store.get(job)
        if operation == "bridge":
            return self.bridge(request)
        if operation == "submit":
            return self.submit(request)
        raise ValueError("unknown worker operation")

    def _hosts(self, storage):
        """Health snapshot that answers promptly even while storage is stalled."""
        locked = self.lock.acquire(timeout=_HOSTS_LOCK_SECONDS)
        try:
            scheduler = self._scheduler_health()
            inventory_error = None
            if not locked:
                # Do not wait behind a hung journal or scheduler pass. Unknown
                # inventory is never presented as an empty claim set.
                claims = None
                inventory_error = "worker lock unavailable: storage or scheduler is stalled"
            else:
                try:
                    claims = [dict(row) for row in self.store.db.execute("SELECT * FROM claims")]
                except Exception as error:
                    claims, inventory_error = None, str(error)
                    with self._scheduler_lock:
                        self._scheduler_state = "DEGRADED"
                        self._scheduler_error = "claim inventory unavailable: " + inventory_error
                        self._scheduler_needs_storage_check = True
                        self._scheduler_fault_version += 1
                    scheduler = self._scheduler_health()
            with self._journal_lock:
                pending_journals = len(self._pending_journal)
                journal_errors = dict(self._journal_errors)
            condition = ("DRAINING" if self.draining else "READY"
                         if scheduler["state"] == "READY" and inventory_error is None
                         and not self._unresolved_attempts and not pending_journals else "DEGRADED")
            reservation = self.reservation
            return {"id": self.host_id, "platform": platform.system().lower(), "architecture": platform.machine(),
                    "engine": self.engine_identity, "worker_version": VERSION, "observed_at": time.time(),
                    "condition": condition, "scheduler": scheduler, "inventory_error": inventory_error,
                    "storage": storage,
                    "pending_quarantines": len(self._unresolved_attempts),
                    "pending_journals": pending_journals, "journal_errors": journal_errors,
                    "reservation": ({key: value for key, value in reservation.items() if key != "secret"} if reservation else None),
                    "capacities": self.capacities, "claims": claims,
                    "qualified": [], "adapter": "windows-local-experimental" if os.name == "nt" else "UNSUPPORTED",
                    "remote_hosts": "UNVERIFIED", "physical_parent": "UNVERIFIED"}
        finally:
            if locked:
                self.lock.release()

    def _status(self, job):
        status = self.store.get(job)
        payload = status["payload"]
        if "preset" in payload and "headless" in payload.get("options", {}):
            status.setdefault("scheduling", scheduling(payload["preset"], payload["options"]))
        return status

    def _validate_context(self, context: str, scope: str):
        attempt, _, secret = context.partition(":")
        grant = self.contexts.get(attempt)
        if not grant or not hmac.compare_digest(grant[1], secret):
            raise ValueError("invalid or stale inherited attempt capability")
        status = self.store.get(grant[0])
        if status["state"] not in {"RUNNING", "CLEANING"}:
            raise ValueError("attempt is no longer executable")
        if scope not in {"headless", "rendered", "control", "performance"}:
            raise ValueError("invalid operation scope")
        if scope == "performance" and not self.store.db.execute(
                "SELECT 1 FROM claims WHERE attempt=? AND resource='exclusive'", (attempt,)).fetchone():
            raise ValueError("performance operation requires an exclusive attempt")
        if scope == "rendered" and status["payload"]["options"]["headless"]:
            raise ValueError("headless grant cannot start rendered work")
        return {"job": grant[0], "attempt": attempt}

    def submit(self, request):
        preset, options = request["preset"], validate(request["preset"], request.get("options", {}))
        expected_digests = {}
        for key in ("source_digest", "manifest_digest"):
            field = "expected_" + key
            if field in request:
                value = request[field]
                if not isinstance(value, str) or len(value) != 64 or any(char not in "0123456789abcdef" for char in value):
                    raise ValueError(field + " must be a 64-character lowercase hexadecimal digest")
                expected_digests[key] = value
        owner = request.get("owner")
        if not isinstance(owner, str) or not 1 <= len(owner) <= 128:
            raise ValueError("owner is required")
        target = request.get("platform", platform.system().lower())
        if target == "any-qualified" and not self.fixture:
            raise ValueError("NO_QUALIFIED_HOST: experimental adapters require their explicit platform")
        if target not in {platform.system().lower(), "any-qualified"}:
            raise ValueError("UNSUPPORTED_PLATFORM: no qualified worker for " + str(target))
        source = Path(request["source"]).resolve()
        if not (source / "app/project.godot").is_file() or not (source / "tools/testqueue/adapter.py").is_file():
            raise ValueError("source must be an OpenRC checkout with the admitted adapter")
        # Resolve a caller-supplied immutable snapshot before acceptance. A duplicate
        # submission must resolve to these same bytes, not resnapshot a changing tree.
        snapshot = Path(request["snapshot"]).resolve()
        from .snapshots import read_verified_file, verify
        manifest = verify(snapshot, include_manifest=True)
        if manifest.get("ok") is not True:
            raise ValueError("snapshot verification failed: " + str(manifest))
        receipt = manifest["manifest"]
        for key in ("source_digest", "manifest_digest"):
            if key in expected_digests and manifest.get(key) != expected_digests[key]:
                raise ValueError("SNAPSHOT_MISMATCH: " + key + " differs from the accepted request")
        if Path(receipt["source_root"]).resolve() != source:
            raise ValueError("snapshot source does not match the submitted history source")
        if preset in {"suite", "ci", "capture"} and not {"app", "tools", "research", "assets", "site", "docs", ".github"}.issubset(receipt.get("scope", [])):
            raise ValueError("preset requires a full repository snapshot; use its admitted entry point")
        if not self.fixture:
            pin = read_verified_file(snapshot, receipt, "app/get-godot.sh").decode("utf-8")
            self._check_engine_pin(pin, self.engine_identity)
            if preset == "aircraft-screenshot":
                self._verify_studio_adapter(snapshot / "source")
        receipt = {key: value for key, value in receipt.items() if key in {"commit", "source_digest", "manifest_digest", "scope", "limitations", "adapter_digests"}}
        payload = {"preset": preset, "options": options, "owner": owner, "platform": target,
                   "snapshot": str(snapshot), "source": str(source), "manifest": receipt,
                   "environment": request.get("environment", {})}
        allowed_environment = {"OPENRC_TEST_PART", "OPENRC_UNIT_SHARDS", "OPENRC_UNIT_SHARD", "OPENRC_PARSE_WITH_UNITS"}
        if preset in {"suite", "ci"}:
            allowed_environment.add("OPENRC_IMPORT_TIMEOUT")
        if set(payload["environment"]) - allowed_environment or any(not isinstance(value, str) for value in payload["environment"].values()):
            raise ValueError("only suite partition environment can be submitted")
        if "OPENRC_IMPORT_TIMEOUT" in payload["environment"]:
            timeout = payload["environment"]["OPENRC_IMPORT_TIMEOUT"]
            if not 1 <= len(timeout) <= 4 or any(char < "0" or char > "9" for char in timeout) or not 1 <= int(timeout) <= 1800:
                raise ValueError("OPENRC_IMPORT_TIMEOUT must be an integer from 1 to 1800 seconds")
        with self.lock:
            result = self.store.submit(request["request_id"], payload, request["request_secret"])
        return {**result, "scheduling": scheduling(preset, options)}

    def _reconcile(self, request):
        job = self.store.authorize(request["handle"])
        status = self.store.get(job)
        if status["state"] != "UNKNOWN":
            raise ValueError("only UNKNOWN attempts require reconciliation")
        # Do not trust a caller's 'it stopped' flag or a reused PID. The Windows
        # Job Object is named by attempt and remains queryable while it has members.
        from .processes import confirm_stopped
        identity = status.get("process")
        if not identity or not confirm_stopped(identity):
            raise ValueError("cleanup cannot be proved; resource remains quarantined")
        data = {**status["attempts"][-1]["data"], "cleanup": "CONFIRMED", "outcome": "INFRA_FAILED",
                "evidence": "INCOMPLETE", "finished": time.time(), "reconciled": True}
        self.store.update(job, status["attempts"][-1]["id"], "FINISHED", data)
        return self.store.get(job)

    def _scheduler_health(self):
        # A heartbeat is a completed successful scheduler pass, not a promise
        # about any attempt. Use monotonic age so wall-clock shifts cannot renew it.
        with self._scheduler_lock:
            thread = self._scheduler_thread
            age = (None if self._scheduler_last_success_monotonic is None
                   else max(0.0, time.monotonic() - self._scheduler_last_success_monotonic))
            state = self._scheduler_state
            if thread is not None and not thread.is_alive():
                state = "STOPPED"
            elif state == "READY" and (age is None or age > _SCHEDULER_STALE_SECONDS):
                state = "STALE"
            return {"state": state, "thread_id": thread.ident if thread else None,
                    "last_heartbeat": self._scheduler_last_success, "heartbeat_age_seconds": age,
                    "last_dispatch": self._scheduler_last_dispatch,
                    "error": self._scheduler_error, "diagnostic_error": self._scheduler_diagnostic_error}

    def _deadline_watchdog(self, attempt, process, directory, deadline, expired, finished):
        """Enforce one attempt's admitted hard budget without storage or ``lock``.

        The monitor thread can hang inside a journal call; this thread cannot,
        because it touches only the bridge socket and the process lock. It never
        closes handles: the monitor owns close() and the cleanup verdict.
        """
        while not finished.wait(max(0.0, deadline - time.monotonic())):
            if time.monotonic() >= deadline:
                break
        if finished.is_set():
            return
        with self._process_lock:
            try:
                if self.active.get(attempt) is not process or not process.alive():
                    return  # Closed, or ended naturally at the boundary.
            except Exception:
                pass  # Uncertain liveness: enforce the budget anyway.
            expired.set()
        if (directory / "ready.json").exists():
            self._graceful_stop(directory)
        with self._process_lock:
            if self.active.get(attempt) is not process:
                return
            try:
                process.terminate()
            except Exception:
                # The monitor repeats terminate(); its close() decides whether
                # teardown is proved or the attempt is quarantined.
                pass

    def _journal(self, job, attempt, state, data, *, wait=_OBSERVATION_LOCK_SECONDS):
        """Record an owned attempt's newest transition; True once it is durable.

        A failed or lock-blocked write leaves the newest transition pending for
        ordered retry (by its monitor or by the scheduler before any new
        allocation). It never stops the owned process or releases its claims.
        """
        record = (job, state, copy.deepcopy(data))
        with self._journal_lock:
            self._pending_journal[attempt] = record
        return self._flush_journal(attempt, wait=wait)

    def _flush_journal(self, attempt, *, wait=_OBSERVATION_LOCK_SECONDS):
        if not self.lock.acquire(timeout=wait):
            with self._journal_lock:
                if attempt in self._pending_journal:
                    self._journal_errors[attempt] = "worker storage lock busy"
            return False
        try:
            return self._flush_journal_locked(attempt)
        finally:
            self.lock.release()

    def _flush_journal_locked(self, attempt):
        """Caller holds ``lock``; writers are serialized, so newest always lands last."""
        with self._journal_lock:
            record = self._pending_journal.get(attempt)
        if record is None:
            return True
        job, state, data = record
        try:
            self.store.update(job, attempt, state, data)
        except StaleTransition:
            # Superseded by a durable terminal record: nothing left to write.
            with self._journal_lock:
                if self._pending_journal.get(attempt) is record:
                    del self._pending_journal[attempt]
                self._journal_errors.pop(attempt, None)
            return True
        except Exception as error:
            with self._journal_lock:
                self._journal_errors[attempt] = state + ": " + str(error)
            return False
        with self._journal_lock:
            self._journal_errors.pop(attempt, None)
            # A newer transition published meanwhile stays pending for its own write.
            if self._pending_journal.get(attempt) is record:
                del self._pending_journal[attempt]
                return True
        return False

    def _observe_canceled(self, job, *, wait=_OBSERVATION_LOCK_SECONDS):
        """Durable cancel flag, or None when storage cannot be observed now."""
        if not self.lock.acquire(timeout=wait):
            return None
        try:
            row = self.store.db.execute("SELECT canceled FROM jobs WHERE id=?", (job,)).fetchone()
            return bool(row[0]) if row else None
        except Exception:
            return None
        finally:
            self.lock.release()

    def _finalize(self, job, attempt, state, data):
        """Terminal transition; capacity stays claimed until it is durable."""
        if state != "UNKNOWN" and attempt in self._unresolved_attempts:
            # Defence in depth: a fenced attempt never finalizes as proved cleanup.
            data = {**data, "cleanup": "UNCONFIRMED",
                    "cleanup_error": data.get("cleanup_error") or "attempt was fenced as unresolved"}
            state = "UNKNOWN"
        if state != "UNKNOWN":
            self._journal(job, attempt, state, data)
            return
        # Fence before any write. The quarantine record supersedes older
        # pending observations of the same attempt.
        self._unresolved_attempts.add(attempt)
        self._pending_unknown[attempt] = (job, copy.deepcopy(data))
        with self._journal_lock:
            self._pending_journal.pop(attempt, None)
        if not self.lock.acquire(timeout=_OBSERVATION_LOCK_SECONDS):
            return
        try:
            self.store.update(job, attempt, "UNKNOWN", data)
        except Exception as error:
            with self._journal_lock:
                self._journal_errors[attempt] = "UNKNOWN: " + str(error)
        else:
            self._pending_unknown.pop(attempt, None)
            self._unresolved_attempts.discard(attempt)
            with self._journal_lock:
                self._journal_errors.pop(attempt, None)
        finally:
            self.lock.release()

    def schedule(self):
        with self._scheduler_lock:
            if self._scheduler_thread is not None:
                raise RuntimeError("scheduler already started")
            self._scheduler_thread = threading.current_thread()
        delay = _SCHEDULER_INTERVAL
        try:
            while not self.stopping.wait(delay):
                with self._scheduler_lock:
                    needs_storage_check = self._scheduler_needs_storage_check
                    fault_version = self._scheduler_fault_version
                try:
                    if needs_storage_check:
                        # An empty queue scan alone does not prove writes work.
                        with self.lock, self.store.db:
                            self.store.event(None, "SCHEDULER_RECOVERY_CHECK")
                    self.schedule_once()
                except Exception as error:
                    with self._scheduler_lock:
                        self._scheduler_state = "DEGRADED"
                        self._scheduler_error = str(error)
                        self._scheduler_diagnostic_error = None
                        self._scheduler_needs_storage_check = True
                        self._scheduler_fault_version += 1
                    try:
                        with self.lock, self.store.db:
                            self.store.event(None, "SCHEDULER_ERROR", {"error": str(error)})
                    except Exception as diagnostic_error:
                        # Recording the error may fail for the same reason as
                        # scheduling. Keep this loop and its attempt owners alive.
                        with self._scheduler_lock:
                            self._scheduler_diagnostic_error = str(diagnostic_error)
                    delay = min(delay * 2, _SCHEDULER_MAX_BACKOFF)
                else:
                    with self._scheduler_lock:
                        self._scheduler_last_success = time.time()
                        self._scheduler_last_success_monotonic = time.monotonic()
                        # A later inventory fault cannot be cleared by a pass
                        # that started before that fault was observed.
                        if self._scheduler_fault_version == fault_version:
                            self._scheduler_state = "READY"
                            self._scheduler_error = None
                            self._scheduler_diagnostic_error = None
                            self._scheduler_needs_storage_check = False
                    delay = _SCHEDULER_INTERVAL
        finally:
            with self._scheduler_lock:
                self._scheduler_state = "STOPPED"

    def schedule_once(self):
        with self.lock:
            # Make fenced outcomes durable before any new allocation. A denied
            # thread gate proves nonlaunch; failed process cleanup does not.
            for attempt, (job, data) in list(self._pending_unknown.items()):
                # Quarantine is always the newest record of that attempt.
                with self._journal_lock:
                    self._pending_journal.pop(attempt, None)
                try:
                    self.store.update(job, attempt, "UNKNOWN", data)
                except StaleTransition:
                    pass  # Its proved terminal record is already durable.
                self._pending_unknown.pop(attempt, None)
                self._unresolved_attempts.discard(attempt)
                with self._journal_lock:
                    self._journal_errors.pop(attempt, None)
            # Independent nonlaunch releases are not held hostage by another
            # attempt's failing observation journal.
            for attempt, (job, data) in list(self._pending_nonlaunch.items()):
                self.store.update(job, attempt, "FINISHED", data)
                self._pending_nonlaunch.pop(attempt, None)
                self._unresolved_attempts.discard(attempt)
            with self._journal_lock:
                pending = list(self._pending_journal)
            for attempt in pending:
                if not self._flush_journal_locked(attempt):
                    with self._journal_lock:
                        error = self._journal_errors.get(attempt)
                    if error is not None:
                        raise RuntimeError("pending attempt journal " + attempt + " failed: " + error)
            if self._unresolved_attempts:
                return
            if self.draining:
                return
            barrier = None
            rows = self.store.db.execute("SELECT id FROM jobs WHERE state='QUEUED' ORDER BY submitted,rowid").fetchall()
            for row in rows:
                job = row[0]
                status = self.store.get(job)
                options, preset = status["payload"]["options"], status["payload"]["preset"]
                policy = scheduling(preset, options)
                reason = ""
                if barrier:
                    reason = "WAITING_FOR_EXCLUSIVE: " + barrier
                elif not self.fixture and os.name != "nt":
                    reason = "UNSUPPORTED_ADAPTER: native containment not qualified"
                elif self.reservation and (not options["headless"] or policy["mode"] == "exclusive"):
                    reason = "HUMAN_RESERVATION: " + self.reservation["owner"]
                elif not self.fixture and not options["headless"] and not desktop_ready():
                    reason = "GUI_LOCKED_OR_UNAVAILABLE: active user desktop required"
                elif not self.fixture:
                    try:
                        if self._external_conflicts():
                            reason = "EXTERNAL_SIMULATOR: preserve unmanaged process"
                    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                        reason = "OCCUPANCY_UNKNOWN: " + str(error)
                if reason:
                    with self.store.db:
                        self.store.db.execute("UPDATE jobs SET reason=? WHERE id=?", (reason, job))
                    continue
                # Once an eligible exclusive request reaches this point, younger
                # work cannot continually refill slots while its predecessors drain.
                # GUI-ineligible jobs above do not idle otherwise usable headless slots.
                if policy["mode"] == "exclusive":
                    barrier = job
                from .processes import host_identity
                identity = {"process": host_identity(), "host": self.host_id, "scheduling": policy}
                gate = _LaunchGate()
                attempt = self.store.allocate(job, policy["resources"], self.capacities, identity)
                if attempt:
                    self.active[attempt] = None
                    try:
                        thread = threading.Thread(target=self._execute_if_granted, args=(gate, job, attempt),
                                                  name="openrc-attempt-" + attempt, daemon=True)
                        thread.start()
                    except BaseException as error:
                        # start() can raise even after a thread was created. The
                        # target cannot execute until this one-way gate is granted.
                        gate.resolve(False)
                        self.active.pop(attempt, None)
                        self._unresolved_attempts.add(attempt)
                        try:
                            detail = str(error)
                        except BaseException:
                            detail = type(error).__name__
                        data = {**identity, "attempt": attempt, "worker_version": VERSION,
                                "engine": self.engine_identity, "started": time.time(),
                                "finished": time.time(), "launch": "NOT_CREATED", "nonlaunch": "CONFIRMED",
                                "cleanup": "CONFIRMED", "outcome": "INFRA_FAILED", "evidence": "INCOMPLETE",
                                "error": "execution thread start failed: " + detail}
                        self._pending_nonlaunch[attempt] = (job, data)
                        # A failure leaves both the fence and pending transition
                        # intact for this same scheduler to retry after recovery.
                        self.store.update(job, attempt, "FINISHED", data)
                        del self._pending_nonlaunch[attempt]
                        self._unresolved_attempts.discard(attempt)
                        if not isinstance(error, Exception):
                            raise
                        continue
                    gate.resolve(True)
                    with self._scheduler_lock:
                        self._scheduler_last_dispatch = time.time()

    def _execute_if_granted(self, gate, job, attempt):
        if gate.allowed():
            self.execute(job, attempt)

    def _close_process(self, attempt, process, *, job=None, data=None):
        # OwnedProcess handle methods are not thread safe. Serialize teardown with
        # occupancy observation and stop advertising the object before result I/O.
        # Teardown uses the process lock, never the storage/admission lock, so a
        # stalled journal cannot delay it. Launch gates wait on ``_closing``
        # until this teardown is proved or fenced. The durable claim survives
        # until verified cleanup AND a durable terminal journal.
        self._closing.add(attempt)
        try:
            with self._process_lock:
                try:
                    process.close()
                except BaseException as error:
                    # Fence immediately, before any potentially failing DB write.
                    # The regular execute handler journals its detailed UNKNOWN;
                    # a BaseException needs a retryable fallback of its own.
                    self._unresolved_attempts.add(attempt)
                    if not isinstance(error, Exception) and job is not None:
                        self._pending_unknown[attempt] = (job, {**(data or {}),
                            "error": "process cleanup ended without a termination receipt",
                            "cleanup_error": "process-tree teardown was not established"})
                    raise
                finally:
                    self.active.pop(attempt, None)
        finally:
            self._closing.discard(attempt)

    def execute(self, job: str, attempt: str):
        from .processes import OwnedProcess, ProcessNotStartedError, host_identity
        directory = self.root / "attempts" / attempt
        process = None
        start_attempted = False
        start_completed = False
        confirmed_nonlaunch = False
        cleanup_attempted = False
        cleanup_verified = False
        data = {"host": self.host_id, "worker_version": VERSION, "engine": self.engine_identity,
                "attempt": attempt, "started": time.time(), "cleanup": "UNCONFIRMED", "evidence": "INCOMPLETE"}
        expired, finished = threading.Event(), threading.Event()
        try:
            data["process"] = host_identity()
            directory.mkdir(parents=True, exist_ok=False)
            # Discoverability does not imply teardown or complete artifacts.
            # Publish the owned path even when preparation or cleanup fails.
            data["output"] = str(directory)
            with self.lock:
                status = self.store.get(job)
                payload = status["payload"]
                data["scheduling"] = scheduling(payload["preset"], payload["options"])
                if status["canceled"]:
                    data.update(cleanup="CONFIRMED", outcome="CANCELED", finished=time.time())
                    self.store.update(job, attempt, "FINISHED", data)
                    return
            from .snapshots import _file_stat, _set_metadata, verify
            def canceled_before_start():
                with self.lock:
                    return bool(self.store.db.execute("SELECT canceled FROM jobs WHERE id=?", (job,)).fetchone()[0])
            report = verify(Path(payload["snapshot"]), canceled=canceled_before_start, include_manifest=True)
            if (not report["ok"] or any(report.get(key) != payload["manifest"].get(key)
                                        for key in ("source_digest", "manifest_digest"))):
                raise ValueError("queued snapshot changed or failed verification")
            receipt = report["manifest"]
            # Each attempt has its own writable project/import cache. Never execute
            # against the immutable source store or another job's .godot directory.
            source = directory / "source"
            required_bytes = sum(item["size"] for item in receipt["files"].values())
            if shutil.disk_usage(directory).free < required_bytes + 512 * 1024 * 1024:
                raise ValueError("INSUFFICIENT_SPACE for isolated attempt and reserve")
            def copy_owned_file(original, target):
                if canceled_before_start():
                    raise RuntimeError("CANCELED during preparation")
                metadata = _file_stat(Path(original))
                copied = shutil.copy2(original, target)
                # copy2 does not preserve Windows indexing/hidden attributes.
                # Match the frozen receipt before the unchanged strict verifier.
                _set_metadata(Path(copied), metadata)
                return copied
            shutil.copytree(Path(payload["snapshot"]) / "source", source, copy_function=copy_owned_file)
            shutil.copy2(Path(payload["snapshot"]) / "manifest.json", directory / "manifest.json")
            copied = verify(directory, canceled=canceled_before_start)
            if (not copied["ok"] or any(copied.get(key) != payload["manifest"].get(key)
                                        for key in ("source_digest", "manifest_digest"))):
                raise ValueError("materialized inputs changed or failed verification")
            if not self.fixture:
                if payload["preset"] == "aircraft-screenshot":
                    # Queued requests survive upgrades/restarts. Rebind the
                    # materialized launch path to this authority before execution.
                    self._verify_studio_adapter(source)
                for name, expected in self.engine_identity["binaries_sha256"].items():
                    if sha256(self.engine.parent / name) != expected:
                        raise ValueError("ENGINE_MISMATCH: enrolled binary changed")
                if payload["preset"] in {"suite", "capture", "ci", "landscape"}:
                    tools = source / ".tools"
                    tools.mkdir(exist_ok=True)
                    for name in self.engine_identity["binaries_sha256"]:
                        shutil.copy2(self.engine.parent / name, tools / name)
            secret = secrets.token_hex(32)
            context = attempt + ":" + secret
            profile = directory / "profile"
            profile.mkdir()
            temporary = directory / "temp"
            temporary.mkdir()
            env = {key: value for key, value in os.environ.items()
                   if not key.startswith(("OPENRC_DEBUG_", "OPENRC_TESTQUEUE_")) and key != "OPENRC_IMPORT_TIMEOUT"}
            env.update(payload["environment"])
            env.update(OPENRC_TESTQUEUE_CONTEXT=context, OPENRC_TESTQUEUE_ROOT=str(self.root),
                       OPENRC_GODOT=str(self.engine), APPDATA=str(profile), XDG_DATA_HOME=str(profile),
                       XDG_CONFIG_HOME=str(profile / "config"), XDG_CACHE_HOME=str(profile / "cache"),
                       TEMP=str(temporary), TMP=str(temporary), TMPDIR=str(temporary),
                       OPENRC_CHECK_OUT=str(directory / "checks"), OPENRC_EXPECTED_CHECK_OUT=str(directory / "expected"))
            write_json(directory / "request.json", payload)
            command = [sys.executable, str(source / "tools/testqueue/adapter.py"), str(directory)]
            process = OwnedProcess(command, cwd=source, env=env, log=directory / "worker.log")
            while True:
                with self.lock:
                    if self.store.get(job)["canceled"]:
                        data.update(cleanup="CONFIRMED", outcome="CANCELED", finished=time.time())
                        self.store.update(job, attempt, "FINISHED", data)
                        return
                    # A teardown still in progress may yet fail; wait for its proof.
                    quarantined = self._unresolved_attempts or self._closing or self.store.db.execute(
                        "SELECT 1 FROM attempts WHERE state='UNKNOWN' LIMIT 1").fetchone()
                    conflicts = None
                    if not quarantined and not self.fixture:
                        try:
                            conflicts = self._external_conflicts(refresh=True)
                        except _OwnershipBusy:
                            # Another teardown holds process ownership; re-check later.
                            quarantined = True
                    if not quarantined:
                        if not self.fixture and not payload["options"]["headless"] and not desktop_ready():
                            raise RuntimeError("GUI_LOCKED_OR_UNAVAILABLE before process start")
                        if conflicts:
                            raise RuntimeError("EXTERNAL_SIMULATOR appeared during preparation; no process started")
                        self.contexts[attempt] = (job, secret)
                        # Persist uncertainty before crossing the OS creation boundary.
                        data["launch"] = "CREATION_UNCERTAIN"
                        self.store.update(job, attempt, "RUNNING", data)
                        start_attempted = True
                        try:
                            process.start()
                        except BaseException as error:
                            # The exception alone is not proof: it must be the receipt
                            # recorded by this instance after its own pre-create failure.
                            confirmed_nonlaunch = (isinstance(error, ProcessNotStartedError)
                                                   and process.nonlaunch_confirmed is True)
                            if not confirmed_nonlaunch:
                                self._unresolved_attempts.add(attempt)
                                if not isinstance(error, Exception):
                                    # The normal exception handler will not run.
                                    # The scheduler must still persist quarantine.
                                    self._pending_unknown[attempt] = (job, {**data,
                                        "error": "process start ended without a launch receipt",
                                        "cleanup_error": "process-tree teardown was not established"})
                            raise
                        # Arm the admitted hard budget from the creation boundary,
                        # before any journal I/O that could block, hang or fail.
                        deadline = time.monotonic() + payload["options"]["timeout"]
                        start_completed = True
                        with self._process_lock:
                            self.active[attempt] = process
                        # Independent enforcer: even if this thread later hangs in
                        # storage, the owned tree is stopped at the deadline.
                        threading.Thread(target=self._deadline_watchdog,
                                         args=(attempt, process, directory, deadline, expired, finished),
                                         name="openrc-deadline-" + attempt, daemon=True).start()
                        data["launch"] = "CREATED_OWNED"
                        data["process"] = process.identity
                        # From here on, storage failure is an observation fault:
                        # the transition stays pending and the process stays owned.
                        self._journal(job, attempt, "RUNNING", data)
                        break
                # An attempt allocated before quarantine must not cross the gate;
                # it keeps its claims and can still receive owned cancellation.
                if self.stopping.wait(_SCHEDULER_INTERVAL):
                    raise RuntimeError("worker stopped before process start")
            reason = None
            canceled = False
            next_desktop_check = time.monotonic() + 1
            next_journal_retry = time.monotonic() + _JOURNAL_RETRY_SECONDS
            ready = directory / "ready.json"
            while True:
                with self._process_lock:
                    if not process.alive():
                        break
                    root_exit = process.poll()
                # Cancellation is sticky once observed; an unavailable store is
                # neither a cancel request nor a reason to stop healthy work.
                canceled = canceled or self._observe_canceled(job, wait=_MONITOR_LOCK_SECONDS) is True
                if "session" not in data and ready.exists():
                    try:
                        private_session = json.loads(ready.read_text(encoding="utf-8"))
                    except (OSError, ValueError):
                        # Windows can refuse a read during the adapter's atomic
                        # replace. Observe again on the next pass.
                        private_session = None
                    if isinstance(private_session, dict):
                        data["session"] = {key: value for key, value in private_session.items() if key != "token"}
                        self._journal(job, attempt, "RUNNING", data, wait=_MONITOR_LOCK_SECONDS)
                if time.monotonic() >= next_journal_retry:
                    next_journal_retry = time.monotonic() + _JOURNAL_RETRY_SECONDS
                    with self._journal_lock:
                        pending = attempt in self._pending_journal
                    if pending:
                        self._flush_journal(attempt, wait=_MONITOR_LOCK_SECONDS)
                lost_desktop = False
                failed_root = root_exit is not None and root_exit != 0
                if not self.fixture and not payload["options"]["headless"] and time.monotonic() >= next_desktop_check:
                    lost_desktop = not desktop_ready()
                    next_desktop_check = time.monotonic() + 1
                if canceled or expired.is_set() or time.monotonic() >= deadline or lost_desktop or failed_root:
                    if canceled:
                        reason = "CANCELED"
                    elif lost_desktop:
                        reason = "INFRA_FAILED"
                    elif expired.is_set() or time.monotonic() >= deadline:
                        reason = "TIMED_OUT"
                    if lost_desktop:
                        data["session_failure"] = "GUI_LOCKED_OR_UNAVAILABLE"
                    self._journal(job, attempt, "CLEANING", data, wait=_MONITOR_LOCK_SECONDS)
                    if ready.exists():
                        self._graceful_stop(directory)
                    with self._process_lock:
                        process.terminate()
                    break
                time.sleep(0.1)
            if reason is None and expired.is_set():
                # The independent watchdog enforced the admitted deadline.
                reason = "TIMED_OUT"
            with self._process_lock:
                code = process.poll()
            cleanup_attempted = True
            self._close_process(attempt, process, job=job, data=data)
            cleanup_verified = True
            data.update(cleanup="CONFIRMED", runner_exit_code=code, finished=time.time())
            verdict_path = directory / "verdict.json"
            verdict = json.loads(verdict_path.read_text(encoding="utf-8")) if verdict_path.exists() else {}
            data["runner_verdict"] = verdict
            data["outcome"] = reason or ("INFRA_FAILED" if verdict.get("complete") is not True
                                          else "PASSED" if code == 0 and verdict.get("ok") is True else "TEST_FAILED")
            if verdict and verdict.get("complete") is True:
                data["evidence"] = "COMPLETE"
            elif code == 0 and reason is None:
                data["outcome"] = "INFRA_FAILED"
            data["artifacts"] = {path.relative_to(directory).as_posix(): sha256(path) for path in directory.rglob("*")
                                 if path.is_file() and path.relative_to(directory).parts[0] not in {"source", "history", "profile", "temp"}}
            data["output"] = str(directory)
            # A failed terminal write keeps the verdict and claims pending; it
            # can no longer be rewritten as an infrastructure failure below.
            self._finalize(job, attempt, "FINISHED", data)
        except Exception as error:
            data["error"] = str(error)
            try:
                if not cleanup_verified and (cleanup_attempted or (start_attempted and not confirmed_nonlaunch
                                            and (not start_completed or process.identity is None))):
                    raise RuntimeError("prior start/cleanup did not establish process-tree teardown")
                if not cleanup_verified and process is not None and start_attempted and not confirmed_nonlaunch:
                    cleanup_attempted = True
                    self._close_process(attempt, process, job=job, data=data)
                if confirmed_nonlaunch:
                    data.update(launch="NOT_CREATED", nonlaunch="CONFIRMED")
                canceled = self._observe_canceled(job, wait=_FINAL_OBSERVATION_SECONDS) is True
                data.update(cleanup="CONFIRMED", outcome="CANCELED" if canceled else "INFRA_FAILED", evidence="INCOMPLETE", finished=time.time())
                state = "FINISHED"
            except Exception as cleanup_error:
                data["cleanup_error"] = str(cleanup_error)
                state = "UNKNOWN"
            self._finalize(job, attempt, state, data)
        finally:
            finished.set()
            # Revoke the inherited capability without waiting on a stalled journal.
            self.contexts.pop(attempt, None)
            with self._process_lock:
                self.active.pop(attempt, None)

    def bridge(self, request):
        with self.lock:
            job = self.store.authorize(request["handle"])
            status = self.store.get(job)
            if status["state"] != "RUNNING" or not status.get("session"):
                raise ValueError("owning session is not running")
            session = json.loads((self.root / "attempts" / status["attempt"] / "ready.json").read_text())
            if request.get("port") not in (None, session["port"]):
                raise ValueError("session handle does not own this port")
        timeout = min(float(request.get("bridge_timeout", 30)), 600)
        payload = {**request.get("args", {}), "id": 1, "cmd": request["command"], "token": session["token"]}
        with socket.create_connection(("127.0.0.1", session["port"]), timeout=timeout) as connection:
            connection.settimeout(timeout)
            connection.sendall((json.dumps(payload, allow_nan=False) + "\n").encode())
            with connection.makefile("rb") as stream:
                line = stream.readline(LIMIT + 1)
            if len(line) > LIMIT:
                raise ValueError("bridge reply exceeds protocol limit")
            return json.loads(line)

    def _graceful_stop(self, directory):
        try:
            session = json.loads((directory / "ready.json").read_text())
            with socket.create_connection(("127.0.0.1", session["port"]), timeout=2) as connection:
                connection.sendall((json.dumps({"id": 1, "cmd": "quit", "token": session["token"]}) + "\n").encode())
            time.sleep(0.3)
        except (OSError, ValueError, KeyError):
            pass

    def serve(self, port=0):
        worker = self

        class Handler(socketserver.StreamRequestHandler):
            def handle(self):
                self.connection.settimeout(30)
                try:
                    line = self.rfile.readline(LIMIT + 1)
                    if len(line) > LIMIT:
                        raise ValueError("request exceeds protocol limit")
                    response = {"ok": True, "result": worker.dispatch(json.loads(line))}
                except Exception as error:
                    response = {"ok": False, "error": str(error)}
                self.wfile.write((json.dumps(response, allow_nan=False) + "\n").encode())

        class Server(socketserver.ThreadingTCPServer):
            daemon_threads = True
            allow_reuse_address = False

        policy = self.root / "policy.json"
        if policy.exists():
            saved = json.loads(policy.read_text())
            self.draining, self.reservation = saved["draining"], saved["reservation"]
        with Server(("127.0.0.1", port), Handler) as server:
            write_json(self.root / "endpoint.json", {"version": VERSION, "port": server.server_address[1], "auth": self.auth,
                                                      "pid": os.getpid(), "host": self.host_id})
            threading.Thread(target=self.schedule, daemon=True).start()
            try:
                server.serve_forever(poll_interval=0.2)
            finally:
                self.stopping.set()
                self.singleton.close()
                if self.host_guard:
                    self.host_guard.close()
