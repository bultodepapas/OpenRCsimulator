"""Owned debug-bridge launches, bounded supervision and retained source identity."""
from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time
import uuid

from catalog import validate

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.godot.run_checked import inspect_log

ORCHESTRATOR_SOURCES = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in Path(__file__).parent.glob("*.py")}
RESOURCE_SAMPLER_SOURCE_SHA256 = hashlib.sha256((ROOT / "tools/godot/resource_samples.py").read_bytes()).hexdigest()


def write_json(path: Path, value: dict) -> None:
    temporary = path.with_name(path.name + ".pending")
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def read_json(path: Path, limit: int = 32 * 1024 * 1024) -> dict:
    if path.stat().st_size > limit:
        raise ValueError(f"artifact exceeds {limit} bytes: {path.name}")
    result = json.loads(path.read_text(encoding="utf-8"), parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"invalid number {value}")))
    if not isinstance(result, dict):
        raise ValueError(f"artifact must be an object: {path.name}")
    return result


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def source_identity() -> dict:
    def git(*args):
        return subprocess.check_output(["git", *args], cwd=ROOT, timeout=30, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    commit = git("rev-parse", "HEAD").decode().strip()
    status = git("status", "--porcelain=v1", "-z").decode(errors="replace").split("\0")
    listed = git("ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "app", "tools/godtest", "research/performance/godtest").decode(errors="strict").split("\0")
    # The pilot uses this exact shared input conversion helper outside its folder.
    listed.append("research/performance/sustained_input.gd")
    # Installed runtime extensions are intentionally ignored by Git but loaded by
    # the copied extension list. Their exact delivery bytes belong to this workload.
    native_root = ROOT / "app/native"
    if native_root.is_dir():
        listed.extend(path.relative_to(ROOT).as_posix() for path in native_root.rglob("*") if path.is_file())
    # Source-built model validation deliberately reads authoring receipts beside app/.
    # Freeze just those declared files, not Blender/source-delivery archives.
    def collect_authoring(value):
        if isinstance(value, dict):
            for nested in value.values(): collect_authoring(nested)
        elif isinstance(value, list):
            for nested in value: collect_authoring(nested)
        elif isinstance(value, str) and value.startswith("assets/"):
            relative = Path(value)
            if ".." in relative.parts or relative.is_absolute():
                raise ValueError("invalid aircraft authoring path")
            listed.append(relative.as_posix())
    for folder in ("aircraft_models", "aircraft_model_overlays"):
        for manifest in (ROOT / "app/data" / folder).glob("*.json"):
            collect_authoring(json.loads(manifest.read_text(encoding="utf-8")))
    hashes, missing = {}, []
    for name in sorted(set(listed) - {""}):
        path = ROOT / name
        if path.is_symlink() or not path.is_file():
            missing.append(name)
            continue
        # Refuse links/junctions to mutable external resources; do not traverse them.
        # Only links inside the checkout matter; OS links above it (macOS /var) do not.
        inside = [parent for parent in [path, *path.parents] if parent != ROOT and parent.is_relative_to(ROOT)]
        if any(parent.is_symlink() or (hasattr(parent, "is_junction") and parent.is_junction()) for parent in inside):
            missing.append(name)
            continue
        hashes[name] = file_hash(path)
    digest = hashlib.sha256(json.dumps(hashes, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return dict(commit=commit, status=[line for line in status if line], digest=digest, files=hashes, excluded_or_missing=missing,
                scope="visible app/GodTest and declared aircraft authoring inputs; imports are frozen separately", imported_cache_identity="snapshot_receipt")


def freeze_inputs(directory: Path, identity: dict) -> dict:
    """Copy verified bytes, including dirty inputs; never link back into a changing tree.

    Uses the same before/copied-content checks as the graphics preparation tool,
    without that tool's deliberate renderer/project mutations.
    """
    cache = ROOT / "app/.godot"
    cached_files = list((cache / "imported").rglob("*")) if (cache / "imported").exists() else []
    cached_files.extend(cache / name for name in ("uid_cache.bin", "global_script_class_cache.cfg", "extension_list.cfg") if (cache / name).is_file())
    required_bytes = sum((ROOT / relative).stat().st_size for relative in identity["files"])
    required_bytes += sum(path.stat().st_size for path in cached_files if path.is_file())
    reserve_bytes = 512 * 1024 * 1024
    if shutil.disk_usage(directory).free < required_bytes + reserve_bytes:
        raise ValueError(f"snapshot requires {required_bytes} bytes plus a {reserve_bytes}-byte reserve; insufficient free space")
    destination = directory / "source"
    destination.mkdir(exist_ok=False)
    frozen = {}
    for relative, expected in identity["files"].items():
        source, target = ROOT / relative, destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if file_hash(source) != expected:
            raise ValueError(f"source changed after identity collection: {relative}; retry in a fresh run directory")
        shutil.copy2(source, target)
        if file_hash(target) != expected or file_hash(source) != expected:
            raise ValueError(f"source changed during snapshot: {relative}; retry in a fresh run directory")
        frozen[relative] = expected
    imported = {}
    for source in cached_files:
        if source.is_symlink() or (hasattr(source, "is_junction") and source.is_junction()):
            raise ValueError(f"linked import input: {source}")
        if not source.is_file(): continue
        relative = source.relative_to(ROOT).as_posix()
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        expected = file_hash(source)
        shutil.copy2(source, target)
        if file_hash(target) != expected:
            raise ValueError(f"import input changed during copy: {relative}")
        imported[relative] = expected
    if not imported:
        raise ValueError("no prepared Godot import cache; use the existing pinned-engine import workflow first")
    receipt = dict(format="openrc-godtest-source-v1", root=str(destination), files=frozen, imports=imported,
                   imported_digest=hashlib.sha256(json.dumps(imported, sort_keys=True).encode()).hexdigest(),
                   links=False, project_mutated=False,
                   consistency="per-file verified copy; not an atomic filesystem or Git-commit snapshot",
                   source_digest=hashlib.sha256(json.dumps(frozen, sort_keys=True).encode()).hexdigest())
    write_json(directory / "snapshot.json", receipt)
    return receipt


def check_frozen(receipt: dict) -> list[str]:
    if receipt.get("format") != "openrc-godtest-source-v1" or not isinstance(receipt.get("files"), dict) or not isinstance(receipt.get("imports"), dict):
        raise ValueError("unsupported snapshot receipt")
    root = Path(receipt.get("root", ""))
    if not root.is_absolute() or not root.is_dir() or "app/project.godot" not in receipt["files"]:
        raise ValueError("snapshot must identify a complete existing source project")
    changed = []
    resolved_root = root.resolve()
    for relative, expected in {**receipt["files"], **receipt["imports"]}.items():
        if not isinstance(relative, str) or "\\" in relative or Path(relative).is_absolute() or ".." in Path(relative).parts or not isinstance(expected, str) or len(expected) != 64 or any(c not in "0123456789abcdef" for c in expected):
            raise ValueError("invalid snapshot path or digest")
        path = root / relative
        if not path.resolve().is_relative_to(resolved_root):
            raise ValueError("snapshot path escaped its root")
        if not path.is_file() or path.is_symlink() or file_hash(path) != expected:
            changed.append(relative)
    return changed


NATIVE_INSTALLS = {"win32": ("windows", "build-receipt-windows.json", "openrc_native_kernel.dll"),
                   "linux": ("linux", "build-receipt.json", "libopenrc_native_kernel.so")}


def native_install_problem(source_root: Path, host_platform: str | None = None, engine: Path | None = None) -> str:
    """Early hint for a stale native install; not a qualification.

    native_stage.gd refuses the kernel when the engine, binary or any mirrored
    source's raw bytes differ from its receipt, and the flight then silently uses
    the GDScript reference. This repeats only those cheap byte checks; the runtime
    backend receipt stays authoritative. macOS adds a separate world-domain pin,
    so only the runtime check applies there.
    """
    install = NATIVE_INSTALLS.get(host_platform or sys.platform)
    if install is None:
        return ""
    name, receipt_name, binary_name = install
    kernel = source_root / "app/native/kernel"
    try:
        entry = json.loads((kernel / receipt_name).read_text(encoding="utf-8"))["platforms"][name]
        mirrored, binary_sha256, engine_sha256 = entry["mirrored_sources"], entry["binary_sha256"], entry["engine_sha256"]
        if not isinstance(mirrored, dict) or not mirrored:
            raise ValueError("empty mirrored sources")
    except (OSError, ValueError, KeyError, TypeError):
        return f"no readable installed native kernel receipt app/native/kernel/{receipt_name}"
    if not (kernel / binary_name).is_file() or file_hash(kernel / binary_name) != binary_sha256:
        return f"installed native binary does not match app/native/kernel/{receipt_name}"
    if engine is not None:
        # The console wrapper starts the GUI executable that the receipt binds.
        executable = Path(str(engine).replace("_console.exe", ".exe"))
        if not executable.is_file() or file_hash(executable) != engine_sha256:
            return f"native kernel was verified with another Godot executable than {executable.name}"
    changed = sorted(relative for relative, expected in mirrored.items()
                     if not (source_root / relative).is_file() or file_hash(source_root / relative) != expected)
    if changed:
        return f"{len(changed)} mirrored physics source(s) changed since the native build: " + ", ".join(changed[:6])
    return ""


def _bridge():
    spec = importlib.util.spec_from_file_location("godtest_debugctl", ROOT / "tools/debug/debugctl.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@contextlib.contextmanager
def environment(values: dict):
    previous = {key: os.environ.get(key) for key in values}
    try:
        for key, value in values.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = str(value)
        yield
    finally:
        for key, value in previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def _call(function, arguments) -> tuple[int, dict]:
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        status = function(arguments)
    lines = captured.getvalue().splitlines()
    result = {}
    for line in reversed(lines):
        try:
            parsed = json.loads(line)
        except ValueError:
            continue
        if isinstance(parsed, dict):
            result = parsed
            break
    if not result:
        result = {"detail": captured.getvalue()[-4000:]}
    return status, result


def rendering_options(manifest: dict, host_platform: str | None = None) -> dict:
    """Resolve this workload's renderer; actual values are checked after launch."""
    host_platform = host_platform or sys.platform
    method = manifest.get("rendering_method")
    driver = manifest.get("rendering_driver")
    if method == "auto":
        method = "mobile" if host_platform == "darwin" else "forward_plus"
    if driver == "auto":
        driver = "opengl3" if method == "gl_compatibility" else "metal" if host_platform == "darwin" else "vulkan"
    if method == "gl_compatibility" and driver not in (None, "opengl3"):
        raise ValueError("Compatibility requires the OpenGL driver")
    if method in ("mobile", "forward_plus") and driver == "opengl3":
        raise ValueError("Mobile/Forward+ require Vulkan, Metal or D3D12")
    if driver == "metal" and host_platform != "darwin":
        raise ValueError("Metal requires macOS")
    if driver == "d3d12" and host_platform != "win32":
        raise ValueError("D3D12 requires Windows")
    return {key: value for key, value in (("rendering_method", method), ("rendering_driver", driver)) if value}


def campaign_host_identity() -> dict:
    """Reuse the queue's OS identities, retaining only domain-separated hashes."""
    from tools.testqueue.processes import host_identity
    identity = host_identity()
    return {"format": "openrc-godtest-host-v1",
            **{key + "_sha256": hashlib.sha256(("openrc-godtest-" + key + ":" + identity[key]).encode()).hexdigest()
               for key in ("host", "boot")},
            "scope": "OS installation and boot; cloned machine IDs cannot distinguish physical hosts"}


def run(manifest: dict, output: Path | None = None, *, godot: str | None = None, resources: bool = False, snapshot: dict | None = None) -> tuple[Path, dict]:
    from tools.testqueue.common import enabled, inherited
    if enabled() and not inherited("rendered"):
        raise ValueError("GOD TEST on an enrolled host requires the admitted godtest.py CLI or inherited attempt")
    validate(manifest)
    render_options = rendering_options(manifest)
    if manifest.get("require_native") and not manifest["headless"]:
        # Fail before creating, freezing or launching, not after a reference-backend flight.
        stale = native_install_problem(Path(snapshot["root"]) if snapshot else ROOT,
                                       engine=Path(godot or _bridge().godot()).resolve())
        if stale:
            raise ValueError(f"rendered workload requires actual native physics: {stale}; requalify and install the native kernel first (research/native-kernel/README.md)")
    host_identity = campaign_host_identity() if manifest.get("monitor_hardware") else None
    resources = resources or manifest.get("monitor_hardware", False)
    if resources:
        # Fail before freezing/launching when the existing pinned CPU backend is missing.
        from tools.godot.resource_samples import load_backend
        load_backend()
    path = (output or ROOT / "tmp/godtest" / f"{manifest['id']}-{time.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:8]}").resolve()
    if path.exists():
        raise ValueError(f"output must be new: {path}")
    path.mkdir(parents=True)
    requested = dict(manifest)
    manifest = dict(manifest, output_dir=str(path))
    validate(manifest, resolved=True)
    write_json(path / "manifest.requested.json", requested)
    before = source_identity()
    write_json(path / "identity.before.json", before)
    if before.get("excluded_or_missing"):
        raise ValueError("required snapshot inputs are missing or linked: " + ", ".join(before["excluded_or_missing"][:12]) + "; restore the declared authoring inputs in a sparse checkout before running")
    if snapshot is None:
        print("  freezing current source and prepared imports", flush=True)
        snapshot = freeze_inputs(path, before)
    else:
        print("  verifying shared frozen suite inputs", flush=True)
        if check_frozen(snapshot):
            raise ValueError("shared suite inputs changed")
        write_json(path / "snapshot.json", snapshot)
    launch_snapshot = snapshot
    if sys.platform == "darwin":
        from tools.godtest.isolation import prepare_macos_launch
        launch_snapshot = prepare_macos_launch(snapshot, path)
        isolation = launch_snapshot["profile_isolation"]
        manifest.update(isolated_user_dir=isolation["user_dir"], isolated_project_name=isolation["project_name"])
        write_json(path / "launch-snapshot.json", launch_snapshot)
    validate(manifest, resolved=True)
    write_json(path / "manifest.resolved.json", manifest)
    bridge = _bridge()
    launcher = ["--app", str(Path(launch_snapshot["root"]) / "app"), "--out", str(path / "bridge"), "--profile", str(path / "profile"), "--resolution", f"{manifest['resolution'][0]}x{manifest['resolution'][1]}", "--timeout", str(min(180, manifest["timeout_s"]))]
    for key, value in render_options.items():
        launcher += ["--" + key.replace("_", "-"), value]
    if manifest["headless"]:
        launcher.append("--headless")
    capture = {"state": "starting", "launch_to_bridge_s": None, "failure": "", "shutdown": {}, "host": dict(platform=platform.platform(), machine=platform.machine()), "resource_scope": "owner-bracketed process observation after bridge readiness; startup and setup before observer construction are excluded"}
    capture["resource_sampling"] = resources
    capture["gpu_sampling"] = resources
    if host_identity is not None:
        capture["host_identity"] = host_identity
    if resources:
        capture["resource_sampler_source_sha256"] = RESOURCE_SAMPLER_SOURCE_SHA256
    capture["rendering_requested"] = render_options
    capture["profile_isolation"] = launch_snapshot.get("profile_isolation", {"kind": "run_directory"})
    capture["orchestrator_sources"] = ORCHESTRATOR_SOURCES
    watch_requested = manifest.get("watch_frames", False)
    capture["frame_watch"] = {"requested": watch_requested, "status": "not_started" if watch_requested else "not_requested"}
    sampler = None
    gpu_sampler = None
    monitor = None
    launch = {}
    launched = False
    timed_out = False
    interrupted = False
    engine_path = Path(godot).resolve() if godot else Path(bridge.godot()).resolve()
    if not engine_path.is_file():
        raise ValueError(f"engine not found: {engine_path}")
    capture["engine_files"] = {str(engine_path): file_hash(engine_path)}
    capture["engine_command_verified"] = False
    direct = Path(str(engine_path).replace("_console.exe", ".exe"))
    if direct != engine_path and direct.is_file():
        capture["engine_files"][str(direct)] = file_hash(direct)
    launch_began = time.monotonic()
    child_env = {"OPENRC_GODTEST_CONFIG": str(path / "manifest.resolved.json"), "OPENRC_SCENE_DETAIL": manifest["scene_detail"], "OPENRC_DEBUG_BRIDGE": None, "OPENRC_DIAGNOSTIC_CAPTURE_ID": path.name, "OPENRC_GODOT": str(engine_path)}
    try:
        with environment(child_env):
            status, launch = _call(bridge.launch, launcher)
        capture["launch_to_bridge_s"] = time.monotonic() - launch_began
        if status or not launch.get("ok"):
            raise RuntimeError(f"launcher refused: {launch}")
        launched = True
        capture["launch"] = {key: value for key, value in launch.items() if key not in ("token", "use")}
        session = bridge.session_for(int(launch["port"]))
        command = session.get("command", [])
        capture["command"] = command
        capture["engine_command_verified"] = isinstance(command, list) and any(
            isinstance(arg, str) and os.path.normcase(arg) == os.path.normcase(str(engine_path)) for arg in command)
        if not capture["engine_command_verified"]:
            raise RuntimeError("launched command does not identify the pinned engine executable")
        if watch_requested:
            from tools.godtest.frame_monitor import FrameMonitor
            monitor = FrameMonitor(bridge, int(launch["port"]), path, timeout_s=manifest["timeout_s"])
            monitor.start()
        if resources:
            from tools.godot.resource_samples import ResourceSampler
            from tools.godtest.hardware import GpuSampler
            capture["monitoring_started_perf_counter_s"] = time.perf_counter()
            capture["resource_observation"] = {
                "clock_domain": "python_perf_counter", "interval_seconds": 1, "max_samples": 4000,
                "start_requested_usec": round(capture["monitoring_started_perf_counter_s"] * 1_000_000)}
            sampler = ResourceSampler(int(launch["pid"]), interval=1, max_samples=4000, include_threads=True)
            sampler.poll(force=True)
            capture["resource_observation"]["start_returned_usec"] = round(time.perf_counter() * 1_000_000)
            capture["gpu_observation"] = {
                "clock_domain": "python_perf_counter", "interval_seconds": 1, "max_samples": 4000,
                "start_requested_usec": time.perf_counter_ns() // 1000}
            gpu_sampler = GpuSampler(interval=1, max_samples=4000)
            gpu_sampler.start()
            capture["gpu_observation"]["start_returned_usec"] = time.perf_counter_ns() // 1000
        deadline = launch_began + float(manifest["timeout_s"]) + 10
        last_phase = None
        while not (path / "runtime.json").exists():
            if monitor:
                monitor_failure = monitor.early_failure()
                if monitor_failure:
                    raise RuntimeError("frame watch stopped early: " + monitor_failure)
            if not bridge.alive(launch["pid"]):
                raise RuntimeError("application exited before final runtime report")
            if time.monotonic() > deadline:
                timed_out = True
                raise TimeoutError("scenario wall deadline expired")
            if sampler:
                sampler.poll()
            log_path = path / "bridge/engine.log"
            if log_path.exists() and time.monotonic() - launch_began > 2:
                diagnostics = inspect_log(log_path, [], max_chars=32 * 1024 * 1024)
                if diagnostics["counts"]["error"]:
                    raise RuntimeError("engine errors observed; stopping owned run and retaining partial evidence")
            try:
                progress = read_json(path / "progress.json", 65536)
                phase = (progress.get("cycle"), progress.get("phase"))
                if phase != last_phase:
                    print(f"  cycle {phase[0]} · {phase[1] or 'finishing'}", flush=True)
                    last_phase = phase
            except (FileNotFoundError, PermissionError):
                # Progress is advisory; Windows may briefly deny reads while the
                # runtime publishes its replacement. Final data is separate.
                capture["progress_read_retries"] = capture.get("progress_read_retries", 0) + 1
            time.sleep(0.2)
        capture["state"] = "runtime_finished"
    except (OSError, RuntimeError, ValueError, TimeoutError, KeyboardInterrupt) as error:
        interrupted = isinstance(error, KeyboardInterrupt)
        capture["failure"] = f"{type(error).__name__}: {error}"
        capture["state"] = "timeout" if timed_out else "failed"
    finally:
        if sampler:
            try:
                capture["resource_observation"]["stop_requested_usec"] = round(time.perf_counter() * 1_000_000)
                resource_result = sampler.finish()
                capture["resource_observation"]["finish_returned_usec"] = round(time.perf_counter() * 1_000_000)
                write_json(path / "resources.json", resource_result)
                capture["resources_sha256"] = file_hash(path / "resources.json")
            except Exception as error:
                capture["resource_error"] = f"{type(error).__name__}: {error}"
        if resources:
            try:
                capture["resource_sampler_source_changed"] = file_hash(ROOT / "tools/godot/resource_samples.py") != RESOURCE_SAMPLER_SOURCE_SHA256
            except OSError:
                capture["resource_sampler_source_changed"] = None
        if gpu_sampler:
            try:
                capture["gpu_observation"]["stop_requested_usec"] = time.perf_counter_ns() // 1000
                gpu_result = gpu_sampler.stop()
                capture["gpu_observation"]["finish_returned_usec"] = time.perf_counter_ns() // 1000
                write_json(path / "gpu.json", gpu_result)
                capture["gpu_sha256"] = file_hash(path / "gpu.json")
            except Exception as error:
                capture["gpu_error"] = f"{type(error).__name__}: {error}"
        if monitor:
            try:
                capture["frame_watch"] = monitor.stop()
            except Exception as error:
                capture["frame_watch"] = {"requested": True, "status": "incomplete",
                                          "error": f"monitor cleanup: {type(error).__name__}: {error}"}
        elif watch_requested:
            capture["frame_watch"] = {"requested": True, "status": "incomplete",
                                      "error": "frame watch did not start"}
        if watch_requested and capture["frame_watch"].get("status") != "complete" and not capture["failure"]:
            capture["failure"] = "frame watch incomplete: " + str(capture["frame_watch"].get("error"))
            capture["state"] = "failed"
        if launched:
            with environment({"OPENRC_DEBUG_BRIDGE": launch["port"]}):
                status, stopped = _call(bridge.stop, [])
                if status or not stopped.get("stopped"):
                    status, stopped = _call(bridge.stop, ["--force"])
                capture["shutdown"] = dict(stopped, command_status=status)
        if monitor and monitor.thread.is_alive():
            # A socket should have a bounded timeout; tearing down its bridge also
            # unblocks it if the initial join deadline was exceeded.
            monitor.thread.join(3.0)
            capture["frame_watch"]["thread_alive_after_shutdown"] = monitor.thread.is_alive()
        capture["elapsed_wall_s"] = time.monotonic() - launch_began
        log = path / "bridge/engine.log"
        if log.is_file():
            capture["log"] = inspect_log(log, ["GOD_TEST_FINISHED"], max_chars=32 * 1024 * 1024)
        after = source_identity()
        write_json(path / "identity.after.json", after)
        capture["working_tree_changed"] = before["digest"] != after["digest"]
        capture["changed_frozen_files"] = check_frozen(snapshot)
        if launch_snapshot is not snapshot:
            capture["changed_launch_files"] = check_frozen(launch_snapshot)
            capture["changed_frozen_files"] += ["mac-source/" + name for name in capture["changed_launch_files"]]
        capture["source_changed"] = bool(capture["changed_frozen_files"])
        changed_engine = []
        for name, digest in capture["engine_files"].items():
            try:
                if file_hash(Path(name)) != digest:
                    changed_engine.append(name)
            except OSError:
                changed_engine.append(name)
        capture["engine_files_changed"] = changed_engine
        write_json(path / "execution.json", capture)
    if interrupted:
        raise KeyboardInterrupt
    return path, capture
