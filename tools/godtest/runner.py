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
        return subprocess.check_output(["git", *args], cwd=ROOT, timeout=30)
    commit = git("rev-parse", "HEAD").decode().strip()
    status = git("status", "--porcelain=v1", "-z").decode(errors="replace").split("\0")
    listed = git("ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "app", "tools/godtest", "research/performance/godtest").decode(errors="strict").split("\0")
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
            if (ROOT / relative).is_file(): listed.append(relative.as_posix())
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
        if any(parent.is_symlink() or (hasattr(parent, "is_junction") and parent.is_junction()) for parent in [path, *path.parents] if parent != ROOT.parent):
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
        expected = file_hash(source)
        shutil.copy2(source, target)
        if file_hash(target) != expected or file_hash(source) != expected:
            raise ValueError(f"source changed during snapshot: {relative}; retry in a fresh run directory")
        frozen[relative] = expected
    # The pilot reuses this existing research input conversion helper.
    relative = "research/performance/sustained_input.gd"
    source, target = ROOT / relative, destination / relative
    expected = file_hash(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    if file_hash(target) != expected:
        raise ValueError("input helper changed during snapshot")
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


def run(manifest: dict, output: Path | None = None, *, godot: str | None = None, resources: bool = False, snapshot: dict | None = None) -> tuple[Path, dict]:
    from tools.testqueue.common import enabled, inherited
    if enabled() and not inherited("rendered"):
        raise ValueError("GOD TEST on an enrolled host requires the admitted godtest.py CLI or inherited attempt")
    validate(manifest)
    if sys.platform == "darwin":
        raise ValueError("Mac profile isolation requires the existing isolated-project workflow; this runner has not qualified it")
    path = (output or ROOT / "tmp/godtest" / f"{manifest['id']}-{time.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:8]}").resolve()
    if path.exists():
        raise ValueError(f"output must be new: {path}")
    path.mkdir(parents=True)
    requested = dict(manifest)
    manifest = dict(manifest, output_dir=str(path))
    validate(manifest, resolved=True)
    write_json(path / "manifest.requested.json", requested)
    write_json(path / "manifest.resolved.json", manifest)
    before = source_identity()
    write_json(path / "identity.before.json", before)
    if snapshot is None:
        print("  freezing current source and prepared imports", flush=True)
        snapshot = freeze_inputs(path, before)
    else:
        print("  verifying shared frozen suite inputs", flush=True)
        if check_frozen(snapshot):
            raise ValueError("shared suite inputs changed")
        write_json(path / "snapshot.json", snapshot)
    bridge = _bridge()
    launcher = ["--app", str(Path(snapshot["root"]) / "app"), "--out", str(path / "bridge"), "--profile", str(path / "profile"), "--resolution", f"{manifest['resolution'][0]}x{manifest['resolution'][1]}", "--timeout", str(min(180, manifest["timeout_s"]))]
    if manifest["headless"]:
        launcher.append("--headless")
    capture = {"state": "starting", "launch_to_bridge_s": None, "failure": "", "shutdown": {}, "host": dict(platform=platform.platform(), machine=platform.machine()), "resource_scope": "after bridge readiness; does not cover whole startup"}
    capture["resource_sampling"] = resources
    capture["orchestrator_sources"] = ORCHESTRATOR_SOURCES
    sampler = None
    launch = {}
    launched = False
    timed_out = False
    interrupted = False
    engine_path = Path(godot).resolve() if godot else Path(bridge.godot()).resolve()
    capture["engine_files"] = {str(engine_path): file_hash(engine_path)}
    direct = Path(str(engine_path).replace("_console.exe", ".exe"))
    if direct != engine_path and direct.is_file():
        capture["engine_files"][str(direct)] = file_hash(direct)
    launch_began = time.monotonic()
    child_env = {"OPENRC_GODTEST_CONFIG": str(path / "manifest.resolved.json"), "OPENRC_SCENE_DETAIL": manifest["scene_detail"], "OPENRC_DEBUG_BRIDGE": None, "OPENRC_DIAGNOSTIC_CAPTURE_ID": path.name}
    if godot:
        executable = Path(godot).resolve()
        if not executable.is_file():
            raise ValueError(f"engine not found: {executable}")
        child_env["OPENRC_GODOT"] = str(executable)
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
        if resources:
            from tools.godot.resource_samples import ResourceSampler
            sampler = ResourceSampler(int(launch["pid"]), interval=1, max_samples=4000)
        deadline = launch_began + float(manifest["timeout_s"]) + 10
        last_phase = None
        while not (path / "runtime.json").exists():
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
            write_json(path / "resources.json", sampler.finish())
        if launched:
            with environment({"OPENRC_DEBUG_BRIDGE": launch["port"]}):
                status, stopped = _call(bridge.stop, [])
                if status or not stopped.get("stopped"):
                    status, stopped = _call(bridge.stop, ["--force"])
                capture["shutdown"] = dict(stopped, command_status=status)
        capture["elapsed_wall_s"] = time.monotonic() - launch_began
        log = path / "bridge/engine.log"
        if log.is_file():
            capture["log"] = inspect_log(log, ["GOD_TEST_FINISHED"], max_chars=32 * 1024 * 1024)
        after = source_identity()
        write_json(path / "identity.after.json", after)
        capture["working_tree_changed"] = before["digest"] != after["digest"]
        capture["changed_frozen_files"] = check_frozen(snapshot)
        capture["source_changed"] = bool(capture["changed_frozen_files"])
        write_json(path / "execution.json", capture)
    if interrupted:
        raise KeyboardInterrupt
    return path, capture
