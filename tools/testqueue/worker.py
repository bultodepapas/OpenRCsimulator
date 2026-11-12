"""Persistent host-local coordinator and worker, with fail-closed recovery."""
from __future__ import annotations

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
from .presets import claims, validate
from .store import Store


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
    def __init__(self, root: Path, repo: Path, engine: Path, *, slots: int = 1, fixture=False):
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
        self.store = Store(self.root)
        self.auth = secrets.token_hex(32)
        self.contexts: dict[str, tuple[str, str]] = {}
        self.active: dict[str, object] = {}
        self.stopping = threading.Event()
        self.draining = False
        self.reservation = None
        self._occupancy_cache = None
        self.fixture = fixture
        self.capacities = {"rendered": 1, "headless": slots, "cpu": slots + 1, "memory": slots + 1}
        self.host_id = self._host_id()
        self.engine_identity = {} if fixture else self._engine_identity()

    def _host_id(self):
        path = self.root / "host.json"
        if path.exists():
            return json.loads(path.read_text())["id"]
        identity = uuid.uuid4().hex
        write_json(path, {"id": identity, "hostname": socket.gethostname(), "created": time.time()})
        return identity

    def _external_conflicts(self, *, refresh=False):
        now = time.monotonic()
        if refresh or self._occupancy_cache is None or now - self._occupancy_cache[0] >= 1:
            self._occupancy_cache = (now, set(external_simulators()))
        managed = set()
        for process in self.active.values():
            if process is not None:
                managed.update(process.pids())
        return self._occupancy_cache[1] - managed

    def _engine_identity(self):
        if not self.engine.is_file():
            raise ValueError("engine executable is missing")
        pin = (self.repo / "app/get-godot.sh").read_text(encoding="utf-8")
        import re
        # Exact official build identifier comes from the tested revision, not a moving stable alias.
        versions = re.findall(r'4\.[0-9]+\.[A-Za-z0-9.]+\.official\.[0-9a-f]+', pin)
        observed = subprocess.check_output([str(self.engine), "--version"], timeout=15, text=True).strip()
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

    def dispatch(self, request: dict):
        if not hmac.compare_digest(str(request.get("auth", "")), self.auth):
            raise ValueError("invalid worker authority")
        operation = request.get("operation")
        with self.lock:
            if operation == "hosts":
                return {"id": self.host_id, "platform": platform.system().lower(), "architecture": platform.machine(),
                        "engine": self.engine_identity, "worker_version": VERSION, "observed_at": time.time(),
                        "condition": "DRAINING" if self.draining else "READY", "reservation": ({key: value for key, value in self.reservation.items() if key != "secret"} if self.reservation else None),
                        "capacities": self.capacities, "claims": [dict(row) for row in self.store.db.execute("SELECT * FROM claims")],
                        "qualified": [], "adapter": "windows-local-experimental" if os.name == "nt" else "UNSUPPORTED",
                        "remote_hosts": "UNVERIFIED", "physical_parent": "UNVERIFIED"}
            if operation in {"status", "result"}:
                return self.store.get(request["job"])
            if operation == "list":
                return [self.store.get(row[0]) for row in self.store.db.execute("SELECT id FROM jobs ORDER BY submitted DESC LIMIT 100")]
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
                if self.store.db.execute("SELECT 1 FROM claims WHERE resource='rendered' LIMIT 1").fetchone():
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
        if operation == "bridge":
            return self.bridge(request)
        if operation == "submit":
            return self.submit(request)
        raise ValueError("unknown worker operation")

    def _validate_context(self, context: str, scope: str):
        attempt, _, secret = context.partition(":")
        grant = self.contexts.get(attempt)
        if not grant or not hmac.compare_digest(grant[1], secret):
            raise ValueError("invalid or stale inherited attempt capability")
        status = self.store.get(grant[0])
        if status["state"] not in {"RUNNING", "CLEANING"}:
            raise ValueError("attempt is no longer executable")
        if scope not in {"headless", "rendered", "control"}:
            raise ValueError("invalid operation scope")
        if scope == "rendered" and status["payload"]["options"]["headless"]:
            raise ValueError("headless grant cannot start rendered work")
        return {"job": grant[0], "attempt": attempt}

    def submit(self, request):
        preset, options = request["preset"], validate(request["preset"], request.get("options", {}))
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
        from .snapshots import verify
        manifest = verify(snapshot)
        if manifest.get("ok") is False:
            raise ValueError("snapshot verification failed: " + str(manifest))
        receipt = json.loads((snapshot / "manifest.json").read_text(encoding="utf-8"))
        if Path(receipt["source_root"]).resolve() != source:
            raise ValueError("snapshot source does not match the submitted history source")
        if preset in {"suite", "ci", "capture"} and not {"app", "tools", "research", "assets", "site", "docs", ".github"}.issubset(receipt.get("scope", [])):
            raise ValueError("preset requires a full repository snapshot; use its admitted entry point")
        if not self.fixture:
            pin = (snapshot / "source/app/get-godot.sh").read_text(encoding="utf-8")
            self._check_engine_pin(pin, self.engine_identity)
        receipt = {key: value for key, value in receipt.items() if key in {"commit", "source_digest", "manifest_digest", "scope", "limitations", "adapter_digests"}}
        payload = {"preset": preset, "options": options, "owner": owner, "platform": target,
                   "snapshot": str(snapshot), "source": str(source), "manifest": receipt,
                   "environment": request.get("environment", {})}
        allowed_environment = {"OPENRC_TEST_PART", "OPENRC_UNIT_SHARDS", "OPENRC_UNIT_SHARD", "OPENRC_PARSE_WITH_UNITS"}
        if set(payload["environment"]) - allowed_environment or any(not isinstance(value, str) for value in payload["environment"].values()):
            raise ValueError("only suite partition environment can be submitted")
        with self.lock:
            result = self.store.submit(request["request_id"], payload, request["request_secret"])
        return result

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

    def schedule(self):
        while not self.stopping.wait(0.1):
            try:
                with self.lock:
                    if self.draining:
                        continue
                    for row in self.store.db.execute("SELECT id FROM jobs WHERE state='QUEUED' ORDER BY submitted").fetchall():
                        job = row[0]
                        status = self.store.get(job)
                        options, preset = status["payload"]["options"], status["payload"]["preset"]
                        reason = ""
                        if not self.fixture and os.name != "nt":
                            reason = "UNSUPPORTED_ADAPTER: native containment not qualified"
                        elif not options["headless"] and self.reservation:
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
                        from .processes import host_identity
                        attempt = self.store.allocate(job, claims(preset, options), self.capacities,
                                                      {"process": host_identity(), "host": self.host_id})
                        if attempt:
                            # Register before the thread starts: a cancel/restart cannot
                            # see a free slot after durable dispatch intent.
                            self.active[attempt] = None
                            threading.Thread(target=self.execute, args=(job, attempt), daemon=True).start()
            except Exception as error:
                with self.lock, self.store.db:
                    self.store.event(None, "SCHEDULER_ERROR", {"error": str(error)})

    def execute(self, job: str, attempt: str):
        from .processes import OwnedProcess, host_identity
        directory = self.root / "attempts" / attempt
        process = None
        start_attempted = False
        cleanup_attempted = False
        cleanup_verified = False
        data = {"host": self.host_id, "worker_version": VERSION, "engine": self.engine_identity,
                "attempt": attempt, "started": time.time(), "cleanup": "UNCONFIRMED", "evidence": "INCOMPLETE"}
        try:
            data["process"] = host_identity()
            directory.mkdir(parents=True, exist_ok=False)
            with self.lock:
                status = self.store.get(job)
                payload = status["payload"]
                if status["canceled"]:
                    data.update(cleanup="CONFIRMED", outcome="CANCELED", finished=time.time())
                    self.store.update(job, attempt, "FINISHED", data)
                    return
            from .snapshots import verify
            def canceled_before_start():
                with self.lock:
                    return bool(self.store.db.execute("SELECT canceled FROM jobs WHERE id=?", (job,)).fetchone()[0])
            report = verify(Path(payload["snapshot"]), canceled=canceled_before_start)
            receipt = json.loads((Path(payload["snapshot"]) / "manifest.json").read_text(encoding="utf-8"))
            if (not report["ok"] or report["source_digest"] != payload["manifest"]["source_digest"]
                    or receipt.get("manifest_digest") != payload["manifest"].get("manifest_digest")):
                raise ValueError("queued snapshot changed or failed verification")
            # Each attempt has its own writable project/import cache. Never execute
            # against the immutable source store or another job's .godot directory.
            source = directory / "source"
            required_bytes = sum(item["size"] for item in receipt["files"].values())
            if shutil.disk_usage(directory).free < required_bytes + 512 * 1024 * 1024:
                raise ValueError("INSUFFICIENT_SPACE for isolated attempt and reserve")
            def copy_owned_file(original, target):
                if canceled_before_start():
                    raise RuntimeError("CANCELED during preparation")
                return shutil.copy2(original, target)
            shutil.copytree(Path(payload["snapshot"]) / "source", source, copy_function=copy_owned_file)
            shutil.copy2(Path(payload["snapshot"]) / "manifest.json", directory / "manifest.json")
            copied = verify(directory, canceled=canceled_before_start)
            copied_receipt = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
            if (not copied["ok"] or copied["source_digest"] != payload["manifest"]["source_digest"]
                    or copied_receipt.get("manifest_digest") != payload["manifest"].get("manifest_digest")):
                raise ValueError("materialized inputs changed or failed verification")
            if not self.fixture:
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
                   if not key.startswith(("OPENRC_DEBUG_", "OPENRC_TESTQUEUE_"))}
            env.update(payload["environment"])
            env.update(OPENRC_TESTQUEUE_CONTEXT=context, OPENRC_TESTQUEUE_ROOT=str(self.root),
                       OPENRC_GODOT=str(self.engine), APPDATA=str(profile), XDG_DATA_HOME=str(profile),
                       XDG_CONFIG_HOME=str(profile / "config"), XDG_CACHE_HOME=str(profile / "cache"),
                       TEMP=str(temporary), TMP=str(temporary), TMPDIR=str(temporary),
                       OPENRC_CHECK_OUT=str(directory / "checks"), OPENRC_EXPECTED_CHECK_OUT=str(directory / "expected"))
            write_json(directory / "request.json", payload)
            command = [sys.executable, str(source / "tools/testqueue/adapter.py"), str(directory)]
            process = OwnedProcess(command, cwd=source, env=env, log=directory / "worker.log")
            with self.lock:
                if self.store.get(job)["canceled"]:
                    data.update(cleanup="CONFIRMED", outcome="CANCELED", finished=time.time())
                    self.store.update(job, attempt, "FINISHED", data)
                    return
                if not self.fixture and not payload["options"]["headless"] and not desktop_ready():
                    raise RuntimeError("GUI_LOCKED_OR_UNAVAILABLE before process start")
                if not self.fixture and self._external_conflicts(refresh=True):
                    raise RuntimeError("EXTERNAL_SIMULATOR appeared during preparation; no process started")
                self.contexts[attempt] = (job, secret)
                # Persist the dispatch before spawning. A crash in start is UNKNOWN.
                self.store.update(job, attempt, "RUNNING", data)
                start_attempted = True
                process.start()
                self.active[attempt] = process
                data["process"] = process.identity
                self.store.update(job, attempt, "RUNNING", data)
            deadline = time.monotonic() + payload["options"]["timeout"]
            reason = None
            next_desktop_check = time.monotonic() + 1
            while process.alive():
                with self.lock:
                    canceled = bool(self.store.get(job)["canceled"])
                    ready = directory / "ready.json"
                    if ready.exists() and "session" not in data:
                        private_session = json.loads(ready.read_text(encoding="utf-8"))
                        data["session"] = {key: value for key, value in private_session.items() if key != "token"}
                        self.store.update(job, attempt, "RUNNING", data)
                lost_desktop = False
                if not self.fixture and not payload["options"]["headless"] and time.monotonic() >= next_desktop_check:
                    lost_desktop = not desktop_ready()
                    next_desktop_check = time.monotonic() + 1
                if canceled or time.monotonic() >= deadline or lost_desktop:
                    reason = "CANCELED" if canceled else "INFRA_FAILED" if lost_desktop else "TIMED_OUT"
                    if lost_desktop:
                        data["session_failure"] = "GUI_LOCKED_OR_UNAVAILABLE"
                    with self.lock:
                        self.store.update(job, attempt, "CLEANING", data)
                    if (directory / "ready.json").exists():
                        self._graceful_stop(directory)
                    process.terminate()
                    break
                time.sleep(0.1)
            code = process.poll()
            cleanup_attempted = True
            process.close()  # verifies all owned descendants, not just launcher exit
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
            with self.lock:
                self.store.update(job, attempt, "FINISHED", data)
        except Exception as error:
            data["error"] = str(error)
            try:
                if not cleanup_verified and (cleanup_attempted or (start_attempted and process.identity is None)):
                    raise RuntimeError("prior start/cleanup did not establish process-tree teardown")
                if not cleanup_verified and process is not None and start_attempted:
                    cleanup_attempted = True
                    process.close()
                with self.lock:
                    canceled = bool(self.store.get(job)["canceled"])
                data.update(cleanup="CONFIRMED", outcome="CANCELED" if canceled else "INFRA_FAILED", evidence="INCOMPLETE", finished=time.time())
                state = "FINISHED"
            except Exception as cleanup_error:
                data["cleanup_error"] = str(cleanup_error)
                state = "UNKNOWN"
            with self.lock:
                self.store.update(job, attempt, state, data)
        finally:
            with self.lock:
                self.contexts.pop(attempt, None)
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
