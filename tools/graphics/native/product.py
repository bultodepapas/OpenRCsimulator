#!/usr/bin/env python3
"""Prepare and package the current Windows NVIDIA application with the pinned engine.

The disposable snapshot has its own import cache. Source and output receipts protect
previous snapshots and deliveries from accidental replacement of unknown edits.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
import build as native_build
import package as trial_package

sys.path.insert(0, str(ROOT / "tools/godot"))
from run_checked import run_checked

SNAPSHOT = ROOT / "tmp/nvidia-product"
OUTPUT = ROOT / "dist/windows-nvidia"
CHECKS = ROOT / "tmp/godot-checks/nvidia-product"
SNAPSHOT_FORMAT = "openrc-nvidia-product-snapshot v1"
PACKAGE_FORMAT = "openrc-nvidia-product-package v1"
SNAPSHOT_RECEIPT = "snapshot-receipt.json"
PACKAGE_RECEIPT = "package-receipt.json"
IMPORT_BASELINE = "import-baseline"
ENGINE = ROOT / ".tools/advanced-rendering" / f"godot-{native_build.COMMIT}" / "bin"
DEADLINE: float | None = None


def time_left(limit: float = 900) -> float:
    if DEADLINE is None:
        return limit
    remaining = DEADLINE - time.monotonic()
    if remaining <= 0:
        raise RuntimeError("product preparation exceeded its 20-minute deadline")
    return min(limit, remaining)


def sha(path: Path) -> str:
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def git(*arguments: str) -> bytes:
    return subprocess.check_output(["git", *arguments], cwd=ROOT)


def safe_relative(name: str, prefix: str | None = None) -> PurePosixPath:
    path = PurePosixPath(name)
    if (not name or "\\" in name or ":" in name or path.is_absolute() or any(part in (".", "..") for part in path.parts)
            or (prefix and path.parts[0] != prefix)):
        raise RuntimeError(f"unsafe source or receipt path: {name!r}")
    return path


def is_link(path: Path) -> bool:
    """Also refuse Windows junctions on Python versions predating Path.is_junction."""
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    return stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & 0x400)


def source_path(name: str) -> Path:
    relative = safe_relative(name)
    source = ROOT.joinpath(*relative.parts)
    if not source.resolve().is_relative_to(ROOT.resolve()):
        raise RuntimeError(f"source escapes repository: {name}")
    for parent in (source, *source.parents):
        if parent == ROOT.parent:
            break
        if is_link(parent):
            raise RuntimeError(f"linked source is not supported: {parent}")
    return source


def listed_app_files() -> list[str]:
    names = git("ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "app/")
    result = sorted({name.decode("utf-8") for name in names.split(b"\0") if name})
    for name in result:
        safe_relative(name, "app")
    # Tracked deletions are part of the worktree state and are not recreated.
    return [name for name in result if source_path(name).is_file()]


def external_proof_files(app: Path) -> list[str]:
    """Mirror the aircraft export plugin's authoring/dependency source set."""
    names: set[str] = set()
    manifests = sorted((app / "data/aircraft_models").glob("*.json"))
    if not manifests:
        raise RuntimeError("no aircraft model manifests found")
    for manifest in manifests:
        model = json.loads(manifest.read_text(encoding="utf-8"))
        records = [model["source_registry"], model["geometry"]["source"]]
        records.extend(model.get("authoring_sources", []))
        records.extend(model.get("dependencies", []))
        for record in records:
            name = record.get("path", "")
            if not isinstance(name, str) or not name:
                raise RuntimeError(f"invalid aircraft proof path in {manifest}")
            if name.startswith("res://"):
                continue
            safe_relative(name, "assets")
            names.add(name)
    return sorted(names)


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"invalid receipt: {path}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"receipt is not an object: {path}")
    return value


def ground_vehicle_inputs() -> list[str]:
    """Keep the ordinary export's native ground-vehicle source/license gates."""
    spec = importlib.util.spec_from_file_location("openrc_ground_product", ROOT / "research/rc-monster-truck/native/build.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load ground-vehicle receipt validator")
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    lock = builder.locked.load_lock()
    directory = ROOT / "app/native/ground_vehicle"
    receipt = load_json(directory / "build-receipt.json")
    expected = {"format": "openrc-ground-vehicle-native-receipt", "backend": "native",
                "backend_version": lock["backend_version"], "abi_version": lock["native_abi_version"],
                "solver_version": lock["solver_version"]}
    if any(receipt.get(k) != v for k, v in expected.items()) or type(receipt.get("abi_version")) is not int:
        raise RuntimeError("ground-vehicle receipt envelope is invalid")
    platforms = receipt.get("platforms")
    if not isinstance(platforms, dict):
        raise RuntimeError("ground-vehicle receipt has no platform map")
    sources = builder.source_digest()
    names = ["build-receipt.json", "openrc_ground_vehicle.gdextension", "LICENSE.godot-cpp.md"]
    for platform in ("windows", "linux"):
        row = platforms.get(platform)
        builder.validate_platform_receipt(platform, row, lock, sources)
        name = builder.expected_library_name(platform)
        if sha(directory / name) != row.get("binary_sha256"):
            raise RuntimeError(f"ground-vehicle {platform} library differs from its receipt")
        names.append(name)
    descriptor = (directory / "openrc_ground_vehicle.gdextension").read_text(encoding="utf-8").replace("\r\n", "\n")
    if descriptor != builder.extension_descriptor("res://native/ground_vehicle/"):
        raise RuntimeError("ground-vehicle extension descriptor differs from the canonical builder")
    license_file = directory / "LICENSE.godot-cpp.md"
    records = load_json(ROOT / "research/native-slipstream/sources.json").get("sources", [])
    matching = [row for row in records if isinstance(row, dict) and row.get("component") == "godot-cpp bindings"
                and row.get("revision") == lock["godot_cpp"]["commit"]]
    if len(matching) != 1 or not license_file.is_file():
        raise RuntimeError("pinned ground-vehicle godot-cpp license or source record is missing")
    license_digest = hashlib.sha256(license_file.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
    if license_digest != matching[0].get("license_file_sha256"):
        raise RuntimeError("ground-vehicle godot-cpp license differs from its pinned source record")
    uid = directory / "openrc_ground_vehicle.gdextension.uid"
    if uid.is_file():
        names.append(uid.name)
    return ["app/native/ground_vehicle/" + name for name in names]


def write_copy(name: str, destination: Path, files: dict[str, str]) -> None:
    time_left()
    source = source_path(name)
    if not source.is_file():
        raise RuntimeError(f"required source is missing: {name}")
    target = destination.joinpath(*safe_relative(name).parts)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    files[name] = sha(target)
    if sha(source) != files[name]:
        raise RuntimeError(f"source changed while copying: {name}")


def snapshot_project(source: bytes) -> bytes:
    old = b'renderer/rendering_method="gl_compatibility"'
    new = b'renderer/rendering_method="forward_plus"'
    if source.count(old) != 1:
        raise RuntimeError("project.godot has no unique Compatibility renderer setting")
    return source.replace(old, new, 1)


def reject_links(root: Path) -> None:
    if is_link(root):
        raise RuntimeError(f"refusing linked output: {root}")
    for base, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            path = Path(base) / name
            if is_link(path):
                raise RuntimeError(f"refusing linked output entry: {path}")


def remove_owned_tree(path: Path, parent: Path, prefix: str) -> None:
    resolved = path.resolve()
    intended_parent = parent.resolve()
    if (not intended_parent.is_relative_to(ROOT.resolve()) or resolved.parent != intended_parent
            or not path.name.startswith(prefix)):
        raise RuntimeError(f"refusing to remove unexpected temporary tree: {resolved}")
    reject_links(path)
    shutil.rmtree(path)


def tree_files(root: Path, *, ignore_cache: bool = False) -> set[str]:
    actual = set()
    for base, dirs, names in os.walk(root, followlinks=False):
        relative_base = Path(base).relative_to(root)
        if ignore_cache and relative_base == Path("app") and ".godot" in dirs:
            dirs.remove(".godot")
        for name in names:
            actual.add((relative_base / name).as_posix())
    return actual


def unknown_directories(root: Path, names: set[str], *, ignore_cache: bool = False) -> set[str]:
    allowed = set()
    for name in names:
        parent = PurePosixPath(name).parent
        while str(parent) != ".":
            allowed.add(parent.as_posix())
            parent = parent.parent
    found = set()
    for base, dirs, _ in os.walk(root, followlinks=False):
        relative_base = Path(base).relative_to(root)
        if ignore_cache and relative_base == Path("app") and ".godot" in dirs:
            dirs.remove(".godot")
        found.update((relative_base / name).as_posix() for name in dirs)
    return found - allowed


def cache_repair_plan(root: Path, rewrites: dict[str, dict]) -> tuple[Path, bytes, dict] | None:
    """Bind Godot's disposable cache metadata to the restored authoring bytes.

    The imported resources were generated by this engine from those source files;
    this corrects only sidecar identity after the engine dropped unknown settings.
    It makes no claim that this engine implements the dropped settings.
    """
    if not rewrites:
        return None
    cache = root / "app/.godot/editor/filesystem_cache10"
    if not cache.exists():
        return None
    raw = cache.read_bytes()
    try:
        lines = raw.decode("utf-8").splitlines(keepends=True)
    except UnicodeError as error:
        raise RuntimeError("Godot filesystem cache is not UTF-8") from error
    pending = set(rewrites)
    directory = ""
    for index, line in enumerate(lines):
        ending = "\r\n" if line.endswith("\r\n") else "\n" if line.endswith("\n") else ""
        content = line.removesuffix(ending) if ending else line
        if content.startswith("::res://"):
            parts = content.split("::")
            if len(parts) < 3:
                raise RuntimeError("malformed Godot cache directory entry")
            directory = parts[1].removeprefix("res://")
            continue
        parts = content.split("::")
        if len(parts) < 9:
            continue
        name = "app/" + directory + parts[0] + ".import"
        if name not in rewrites:
            continue
        metadata = parts[7].split("<>")
        row = rewrites[name]
        if (name not in pending or len(metadata) < 7 or metadata[5] != row["imported_md5"]
                or not parts[4].isdigit() or int(parts[4]) != row["imported_mtime_ns"] // 1_000_000_000):
            raise RuntimeError(f"Godot cache does not identify the checked import: {name}")
        metadata[5] = row["source_md5"]
        parts[7] = "<>".join(metadata)
        lines[index] = "::".join(parts) + ending
        pending.remove(name)
    if pending:
        raise RuntimeError(f"Godot cache lacks checked import entries: {sorted(pending)[:10]}")
    patched = "".join(lines).encode("utf-8")
    evidence = {"path": "app/.godot/editor/filesystem_cache10", "entries": len(rewrites),
                "before_sha256": hashlib.sha256(raw).hexdigest(), "after_sha256": hashlib.sha256(patched).hexdigest(),
                "meaning": "cache sidecar identities only; unsupported import options are not claimed equivalent"}
    return cache, patched, evidence


def verify_tree(root: Path, receipt_name: str, expected_format: str, *, ignore_cache: bool = False) -> dict:
    if not root.is_dir():
        raise RuntimeError(f"missing output directory: {root}")
    reject_links(root)
    receipt = load_json(root / receipt_name)
    files = receipt.get("files")
    if receipt.get("format") != expected_format or not isinstance(files, dict) or not files:
        raise RuntimeError(f"invalid managed-file receipt: {root / receipt_name}")
    for name, expected in files.items():
        path = root.joinpath(*safe_relative(name).parts)
        if not isinstance(expected, str) or not path.is_file() or sha(path) != expected:
            raise RuntimeError(f"managed file changed or is missing: {path}")
    generated = receipt.get("generated_import_files", {})
    if not isinstance(generated, dict):
        raise RuntimeError(f"invalid generated-file receipt: {root / receipt_name}")
    for name, expected in generated.items():
        path = root.joinpath(*safe_relative(name).parts)
        if name in files or not path.is_file() or not isinstance(expected, str) or sha(path) != expected:
            raise RuntimeError(f"generated import file changed or is missing: {path}")
    actual = tree_files(root, ignore_cache=ignore_cache)
    expected_names = set(files) | set(generated) | {receipt_name}
    if actual != expected_names:
        raise RuntimeError(f"unknown or missing output files under {root}: {sorted(actual ^ expected_names)[:10]}")
    extra_dirs = unknown_directories(root, expected_names, ignore_cache=ignore_cache)
    if extra_dirs:
        raise RuntimeError(f"unknown output directories under {root}: {sorted(extra_dirs)[:10]}")
    return receipt


def receipt_generated_imports(root: Path) -> dict:
    """Record UIDs and restore checked source sidecars changed by this editor."""
    reject_links(root)
    path = root / SNAPSHOT_RECEIPT
    receipt = load_json(path)
    files = receipt.get("files")
    if receipt.get("format") != SNAPSHOT_FORMAT or not isinstance(files, dict):
        raise RuntimeError(f"invalid snapshot receipt: {path}")
    originals = receipt.get("import_originals", {})
    if not isinstance(originals, dict):
        raise RuntimeError("invalid import-originals receipt")
    # This upstream editor predates three newer import settings. It drops only
    # those settings when it rewrites sidecars. Preserve the exact authoring bytes
    # because aircraft proofs deliberately pin selected .import files.
    removed_settings = {"mipmaps/alpha_test_threshold=0.5", "mipmaps/preserve_alpha_test_coverage=false",
                        "mipmaps/preserve_alpha_test_coverage=true", "mesh_library/create_categories_from_hierarchy=false"}
    restores: dict[str, tuple[bytes, int, int]] = {}
    rewrites: dict[str, dict] = {}
    unsupported = []
    new_originals: dict[str, bytes] = {}
    for name, expected in list(files.items()):
        target = root.joinpath(*safe_relative(name).parts)
        if not target.is_file():
            raise RuntimeError(f"source disappeared during import: {target}")
        actual = sha(target)
        if name.startswith("app/") and name.endswith(".import"):
            baseline_name = originals.get(name)
            if baseline_name is None:
                baseline_name = f"{IMPORT_BASELINE}/{name}"
                original_path = source_path(name)
            else:
                safe_relative(baseline_name, IMPORT_BASELINE)
                if files.get(baseline_name) != expected:
                    raise RuntimeError(f"import baseline receipt differs from source: {name}")
                original_path = root.joinpath(*PurePosixPath(baseline_name).parts)
            if not original_path.is_file() or sha(original_path) != expected:
                raise RuntimeError(f"original import sidecar is unavailable or changed: {name}")
            original = original_path.read_bytes()
            if b"mipmaps/preserve_alpha_test_coverage=true" in original:
                unsupported.append({"path": name, "setting": "mipmaps/preserve_alpha_test_coverage=true"})
            if baseline_name not in files:
                originals[name] = baseline_name
                new_originals[baseline_name] = original
            if actual != expected:
                try:
                    before = original.decode("utf-8").splitlines()
                    after = target.read_text(encoding="utf-8").splitlines()
                except UnicodeError as error:
                    raise RuntimeError(f"invalid import sidecar text: {name}") from error
                if [line for line in before if line not in removed_settings] != after:
                    raise RuntimeError(f"import sidecar has unexpected edits: {name}")
                info = target.stat()
                imported = target.read_bytes()
                restores[name] = (original, info.st_atime_ns, info.st_mtime_ns)
                rewrites[name] = {"source_sha256": expected, "imported_sha256": actual,
                                  "source_md5": hashlib.md5(original, usedforsecurity=False).hexdigest(),
                                  "imported_md5": hashlib.md5(imported, usedforsecurity=False).hexdigest(),
                                  "imported_mtime_ns": info.st_mtime_ns}
        elif actual != expected:
            raise RuntimeError(f"source changed during import: {target}")
    old_generated = receipt.get("generated_import_files", {})
    if not isinstance(old_generated, dict):
        raise RuntimeError("invalid generated import receipt")
    for name, expected in old_generated.items():
        target = root.joinpath(*safe_relative(name).parts)
        if name in files or not target.is_file() or not isinstance(expected, str) or sha(target) != expected:
            raise RuntimeError(f"previous generated import file changed: {target}")
    extra = tree_files(root, ignore_cache=True) - set(files) - set(old_generated) - {SNAPSHOT_RECEIPT}
    generated = dict(old_generated)
    for name in sorted(extra):
        target = root.joinpath(*safe_relative(name, "app").parts)
        if not name.endswith((".gd.uid", ".gdshader.uid", ".gdshaderinc.uid", ".gdextension.uid")) or name[:-4] not in files:
            raise RuntimeError(f"unexpected file appeared during import: {target}")
        try:
            uid = target.read_text(encoding="utf-8").strip()
        except (OSError, UnicodeError) as error:
            raise RuntimeError(f"invalid generated UID: {target}") from error
        if not re.fullmatch(r"uid://[a-z0-9]+", uid):
            raise RuntimeError(f"invalid generated UID: {target}")
        generated[name] = sha(target)
    extra_dirs = unknown_directories(root, set(files) | set(generated) | {SNAPSHOT_RECEIPT}, ignore_cache=True)
    if extra_dirs:
        raise RuntimeError(f"unexpected directories appeared during import: {sorted(extra_dirs)[:10]}")
    repair = cache_repair_plan(root, rewrites)
    # All changes are validated before restoring any source byte.
    for name, data in new_originals.items():
        target = root.joinpath(*safe_relative(name).parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        files[name] = hashlib.sha256(data).hexdigest()
    for name, (data, atime, mtime) in restores.items():
        target = root.joinpath(*safe_relative(name).parts)
        target.write_bytes(data)
        os.utime(target, ns=(atime, mtime))
    if repair is not None:
        cache, contents, evidence = repair
        temporary = cache.with_name(cache.name + ".openrc-new")
        if temporary.exists():
            raise RuntimeError(f"unexpected temporary cache file: {temporary}")
        temporary.write_bytes(contents)
        temporary.replace(cache)
        receipt["import_cache_adjustment"] = evidence
    receipt["files"] = files
    receipt["import_originals"] = originals
    receipt["import_sidecar_rewrites"] = rewrites
    receipt["unsupported_import_settings"] = unsupported
    receipt["generated_import_files"] = generated
    path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    verify_tree(root, SNAPSHOT_RECEIPT, SNAPSHOT_FORMAT, ignore_cache=True)
    return receipt


def record_checked_import(report_path: Path) -> None:
    """Adopt an explicitly selected successful import of this exact snapshot/editor."""
    editor, _, _ = verify_engine()
    report_path = report_path.resolve(strict=True)
    report = load_json(report_path)
    command = report.get("command")
    if (report.get("format") != "openrc-godot-check v1" or report.get("ok") is not True
            or report.get("complete") is not True or report.get("exit_code") != 0
            or report.get("process_exit") != 0 or report.get("counts", {}).get("error") != 0
            or not isinstance(command, list) or not all(isinstance(x, str) for x in command)):
        raise RuntimeError("selected import report is not a successful complete checked invocation")
    cwd = Path(str(report.get("cwd", ""))).resolve()
    if cwd != ROOT.resolve() or not command or command.count("--path") != 1 or "--import" not in command or "--headless" not in command:
        raise RuntimeError("selected report is not the expected headless project import")
    project_index = command.index("--path") + 1
    if (project_index >= len(command) or (cwd / command[project_index]).resolve() != (SNAPSHOT / "app").resolve()
            or (cwd / command[0]).resolve() != (ENGINE / "godot.windows.editor.x86_64.exe").resolve()):
        raise RuntimeError("selected import used a different editor or project")
    log = report_path.parent / "engine.log"
    if Path(str(report.get("log", ""))).resolve() != log or not log.is_file() or sha(log) != report.get("log_sha256"):
        raise RuntimeError("selected import log does not match its checked report")
    from datetime import datetime
    from run_checked import inspect_log
    inspection = inspect_log(log, [])
    if inspection["counts"]["error"] or inspection["missing_required_text"]:
        raise RuntimeError("selected import log contains errors")
    try:
        started = datetime.fromisoformat(str(report["started_utc"])).timestamp()
    except (KeyError, ValueError) as error:
        raise RuntimeError("selected import has an invalid start timestamp") from error
    if started + 1 < (SNAPSHOT / SNAPSHOT_RECEIPT).stat().st_mtime:
        raise RuntimeError("selected import predates the snapshot")
    receipt = receipt_generated_imports(SNAPSHOT)
    receipt["import"] = {"report": str(report_path), "report_sha256": sha(report_path),
                         "log_sha256": sha(log), "editor_sha256": editor["executable_sha256"]}
    (SNAPSHOT / SNAPSHOT_RECEIPT).write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Recorded successful import and {len(receipt['generated_import_files'])} generated UID files.", flush=True)


def replace_tree(staging: Path, destination: Path, *, reuse_cache: bool = False) -> None:
    """Replace only a previously verified directory; preserve it on failure."""
    if destination.exists():
        backup = destination.with_name(destination.name + "-previous-" + uuid.uuid4().hex)
        destination.rename(backup)
        old_cache = backup / "app/.godot"
        new_cache = staging / "app/.godot"
        moved_cache = False
        try:
            if reuse_cache and old_cache.is_dir():
                old_cache.rename(new_cache)
                moved_cache = True
            staging.rename(destination)
        except Exception:
            if moved_cache:
                new_cache.rename(old_cache)
            backup.rename(destination)
            raise
        # Both exact roots were chosen by this tool, and links were rejected before rename.
        remove_owned_tree(backup, destination.parent, destination.name + "-previous-")
    else:
        staging.rename(destination)


def prepare_snapshot() -> dict:
    previous: dict = {}
    if SNAPSHOT.exists():
        previous = verify_tree(SNAPSHOT, SNAPSHOT_RECEIPT, SNAPSHOT_FORMAT, ignore_cache=True)
        if (SNAPSHOT / "app/.godot").exists():
            editor, _, _ = verify_engine()
            origin = previous.get("import") or previous.get("cache_origin") or {}
            if origin.get("editor_sha256") != editor["executable_sha256"]:
                raise RuntimeError("unreceipted import cache; supply --import-report for its successful checked import")
    head = git("rev-parse", "HEAD").decode().strip()
    app_files = listed_app_files()
    if not app_files:
        raise RuntimeError("current application source set is empty")
    native_files = ground_vehicle_inputs()
    SNAPSHOT.parent.mkdir(parents=True, exist_ok=True)
    if not SNAPSHOT.parent.resolve().is_relative_to(ROOT.resolve()):
        raise RuntimeError("snapshot parent is outside the repository")
    staging = Path(tempfile.mkdtemp(prefix="nvidia-product-stage-", dir=SNAPSHOT.parent))
    try:
        files: dict[str, str] = {}
        for name in app_files + native_files:
            write_copy(name, staging, files)
        for name in external_proof_files(staging / "app"):
            write_copy(name, staging, files)
        original_project_hash = files["app/project.godot"]
        project = staging / "app/project.godot"
        project.write_bytes(snapshot_project(project.read_bytes()))
        files["app/project.godot"] = sha(project)
        # Recheck the live worktree after copying so concurrent changes fail explicitly.
        if head != git("rev-parse", "HEAD").decode().strip() or listed_app_files() != app_files:
            raise RuntimeError("HEAD or the application file set changed during snapshot; retry")
        for name, snapshot_hash in files.items():
            time_left()
            expected = original_project_hash if name == "app/project.godot" else snapshot_hash
            if not source_path(name).is_file() or sha(source_path(name)) != expected:
                raise RuntimeError(f"source changed during snapshot; retry: {name}")
        import_originals: dict[str, str] = {}
        for name in app_files:
            if name.endswith(".import"):
                baseline_name = f"{IMPORT_BASELINE}/{name}"
                target = staging.joinpath(*PurePosixPath(baseline_name).parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(staging.joinpath(*PurePosixPath(name).parts), target)
                files[baseline_name] = sha(target)
                if files[baseline_name] != files[name]:
                    raise RuntimeError(f"import baseline differs from source: {name}")
                import_originals[name] = baseline_name
        status = git("status", "--porcelain=v1", "-z", "--untracked-files=all").decode("utf-8")
        dirty = bool(status)
        describe = git("describe", "--tags", "--always", "--dirty").decode().strip()
        if dirty and not describe.endswith("-dirty"):
            describe += "-dirty"
        identity = {"commit": head, "commit_date": git("show", "-s", "--format=%cI", "HEAD").decode().strip(),
                    "describe": describe, "dirty": dirty,
                    "status_porcelain": [s for s in status.split("\0") if s]}
        receipt = {"format": SNAPSHOT_FORMAT, "build_identity": identity,
                   "project_override": {"path": "app/project.godot", "setting": "renderer/rendering_method",
                                        "source": "gl_compatibility", "snapshot": "forward_plus",
                                        "source_sha256": original_project_hash, "snapshot_sha256": files["app/project.godot"]},
                   "files": files, "import_originals": import_originals}
        if previous and (SNAPSHOT / "app/.godot").exists():
            origin = previous.get("import") or previous.get("cache_origin")
            receipt["cache_origin"] = {"editor_sha256": origin["editor_sha256"],
                                       "snapshot_receipt_sha256": sha(SNAPSHOT / SNAPSHOT_RECEIPT)}
        (staging / SNAPSHOT_RECEIPT).write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        replace_tree(staging, SNAPSHOT, reuse_cache=True)
        print(f"Prepared current-source snapshot: {SNAPSHOT / 'app'} ({len(files)} files, {head[:12]})", flush=True)
        return receipt
    finally:
        if staging.exists():
            remove_owned_tree(staging, SNAPSHOT.parent, "nvidia-product-stage-")


def verify_engine() -> tuple[dict, dict, list[Path]]:
    editor = load_json(ENGINE / "openrc-editor-build.json")
    template = load_json(ENGINE / "openrc-template_release-build.json")
    integration = {name: sha(HERE / name) for name in trial_package.INTEGRATION}
    sources = {name: digest for name, _, digest, _ in native_build.ARCHIVES}
    shared = ("godot_commit", "version", "fidelityfx_sdk", "fsr_upscaler", "streamline", "platform",
              "graphics_api", "frame_generation_enabled", "sources", "integration", "streamline_headers", "runtime", "fidelityfx_runtime_build")
    for label, receipt in (("editor", editor), ("template_release", template)):
        if receipt.get("experimental") is not True or receipt.get("godot_commit") != native_build.COMMIT:
            raise RuntimeError(f"{label} receipt is not the pinned historical engine build")
        if receipt.get("platform") != "windows" or receipt.get("graphics_api") != "vulkan" or receipt.get("frame_generation_enabled") is not False:
            raise RuntimeError(f"{label} engine platform/backend is invalid")
        if receipt.get("integration") != integration or receipt.get("sources") != sources:
            raise RuntimeError(f"{label} source/integration identities are stale")
        if not isinstance(receipt.get("streamline_headers"), dict) or not receipt["streamline_headers"]:
            raise RuntimeError(f"{label} has no Streamline header hashes")
        if not isinstance(receipt.get("runtime"), dict) or not receipt["runtime"]:
            raise RuntimeError(f"{label} has no runtime hashes")
        executable = ENGINE / ("godot.windows.editor.x86_64.exe" if label == "editor" else "godot.windows.template_release.x86_64.exe")
        if Path(str(receipt.get("executable", ""))).resolve() != executable.resolve() or not executable.is_file() or sha(executable) != receipt.get("executable_sha256"):
            raise RuntimeError(f"{label} executable path/hash differs from receipt")
    if any(editor.get(key) != template.get(key) for key in shared):
        raise RuntimeError("editor and template identities differ")
    for name, expected in editor["runtime"].items():
        if Path(name).name != name or not isinstance(expected, str) or not (ENGINE / name).is_file() or sha(ENGINE / name) != expected:
            raise RuntimeError(f"runtime DLL differs from receipt: {name}")
    licenses = ENGINE / "licenses"
    entries = list(licenses.iterdir())
    if not entries or any(not p.is_file() or p.is_symlink() for p in entries):
        raise RuntimeError("engine license directory is empty or has non-file entries")
    return editor, template, sorted(entries)


def launcher_files() -> dict[str, bytes]:
    launchers = {}
    for name, args in (("OpenRC Simulator.cmd", ""), ("Standard Graphics.cmd", " --rendering-method gl_compatibility")):
        launchers[name] = ("@echo off\r\nsetlocal\r\ncd /d \"%~dp0\"\r\n"
                           f'start "" "%~dp0OpenRC Simulator.exe"{args}\r\nendlocal\r\n').encode("utf-8")
    return launchers


def verify_product() -> dict:
    receipt = verify_tree(OUTPUT, PACKAGE_RECEIPT, PACKAGE_FORMAT)
    for name in ("OpenRC Simulator.exe", "OpenRC Simulator.pck", "OpenRC Simulator.cmd", "Standard Graphics.cmd",
                 SNAPSHOT_RECEIPT, "openrc-editor-build.json", "openrc-template_release-build.json"):
        if not (OUTPUT / name).is_file() or not (OUTPUT / name).stat().st_size:
            raise RuntimeError(f"product required file is missing or empty: {name}")
    snapshot = load_json(OUTPUT / SNAPSHOT_RECEIPT)
    editor = load_json(OUTPUT / "openrc-editor-build.json")
    template = load_json(OUTPUT / "openrc-template_release-build.json")
    if (receipt.get("godot_commit") != native_build.COMMIT or snapshot.get("format") != SNAPSHOT_FORMAT
            or receipt.get("snapshot_sha256") != sha(OUTPUT / SNAPSHOT_RECEIPT)
            or receipt.get("build_identity") != snapshot.get("build_identity")):
        raise RuntimeError("product and current-source snapshot identities do not agree")
    sources = {name: digest for name, _, digest, _ in native_build.ARCHIVES}
    integration = {name: sha(HERE / name) for name in trial_package.INTEGRATION}
    shared = ("godot_commit", "version", "fidelityfx_sdk", "fsr_upscaler", "streamline", "platform",
              "graphics_api", "frame_generation_enabled", "sources", "integration", "streamline_headers", "runtime", "fidelityfx_runtime_build")
    if (editor.get("experimental") is not True or template.get("experimental") is not True
            or editor.get("godot_commit") != native_build.COMMIT or template.get("godot_commit") != native_build.COMMIT
            or editor.get("platform") != "windows" or editor.get("graphics_api") != "vulkan"
            or editor.get("frame_generation_enabled") is not False or editor.get("sources") != sources
            or editor.get("integration") != integration or any(editor.get(key) != template.get(key) for key in shared)
            or receipt.get("sources") != sources or receipt.get("integration") != integration
            or receipt.get("runtime") != editor.get("runtime")):
        raise RuntimeError("product engine receipts do not match the pinned source and integration identities")
    if (receipt.get("editor_sha256") != editor.get("executable_sha256")
            or receipt.get("template_sha256") != template.get("executable_sha256")
            or sha(OUTPUT / "OpenRC Simulator.exe") != template.get("executable_sha256")):
        raise RuntimeError("product executable does not match the release-template receipt")
    runtime = editor.get("runtime")
    if not isinstance(runtime, dict) or not runtime:
        raise RuntimeError("product engine receipt has no runtime DLLs")
    for name, expected in runtime.items():
        if Path(name).name != name or not isinstance(expected, str) or not (OUTPUT / name).is_file() or sha(OUTPUT / name) != expected:
            raise RuntimeError(f"product runtime DLL differs from engine receipt: {name}")
    files = snapshot.get("files")
    if (not isinstance(files, dict) or not (OUTPUT / "openrc_ground_vehicle.dll").is_file()
            or sha(OUTPUT / "openrc_ground_vehicle.dll") != files.get("app/native/ground_vehicle/openrc_ground_vehicle.dll")):
        raise RuntimeError("product ground-vehicle sidecar differs from its source snapshot")
    if not (OUTPUT / "licenses").is_dir() or not list((OUTPUT / "licenses").iterdir()):
        raise RuntimeError("product engine licenses are missing")
    return receipt


def package_product(snapshot: dict) -> dict:
    editor, template, licenses = verify_engine()
    license_hashes = {path.name: sha(path) for path in licenses}
    verify_tree(SNAPSHOT, SNAPSHOT_RECEIPT, SNAPSHOT_FORMAT, ignore_cache=True)
    if OUTPUT.exists():
        verify_tree(OUTPUT, PACKAGE_RECEIPT, PACKAGE_FORMAT)
    identity = snapshot["build_identity"]
    env = {"OPENRC_BUILD_DESCRIBE": identity["describe"], "OPENRC_BUILD_COMMIT": identity["commit"],
           "OPENRC_BUILD_DIRTY": "1" if identity["dirty"] else "0", "OPENRC_BUILD_DATE": identity["commit_date"]}
    old_env = {key: os.environ.get(key) for key in env}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    if not OUTPUT.parent.resolve().is_relative_to(ROOT.resolve()):
        raise RuntimeError("package parent is outside the repository")
    staging = Path(tempfile.mkdtemp(prefix="nvidia-product-export-", dir=OUTPUT.parent))
    try:
        os.environ.update(env)
        executable = ENGINE / "godot.windows.editor.x86_64.exe"
        result = run_checked([str(executable), "--headless", "--path", str(SNAPSHOT / "app"), "--audio-driver", "Dummy", "--import"],
                             CHECKS, timeout=time_left(), label="nvidia-product-import")
        if not result.get("ok"):
            raise RuntimeError(f"application import failed; runner report: {result.get('report')}")
        import_report = result["report"]
        record_checked_import(Path(import_report))
        pack = staging / "OpenRC Simulator.pck"
        result = run_checked([str(executable), "--headless", "--path", str(SNAPSHOT / "app"), "--audio-driver", "Dummy",
                              "--export-pack", "Windows", str(pack)], CHECKS, timeout=time_left(),
                             required=["[ DONE ] savepack"], label="nvidia-product-export")
        if not result.get("ok") or not pack.is_file() or not pack.stat().st_size:
            raise RuntimeError(f"Windows pack export failed; runner report: {result.get('report')}")
        final_editor, final_template, final_licenses = verify_engine()
        if (final_editor != editor or final_template != template
                or {path.name: sha(path) for path in final_licenses} != license_hashes):
            raise RuntimeError("engine, runtime or license inputs changed during export")
        # Check every snapshotted source again after running Godot.
        verify_tree(SNAPSHOT, SNAPSHOT_RECEIPT, SNAPSHOT_FORMAT, ignore_cache=True)
        ground_source = SNAPSHOT / "app/native/ground_vehicle/openrc_ground_vehicle.dll"
        ground_output = staging / "openrc_ground_vehicle.dll"
        if ground_output.exists() and sha(ground_output) != sha(ground_source):
            raise RuntimeError("exported ground-vehicle library differs from its validated receipt")
        if not ground_output.exists():
            shutil.copyfile(ground_source, ground_output)
        shutil.copyfile(ENGINE / "godot.windows.template_release.x86_64.exe", staging / "OpenRC Simulator.exe")
        for name in editor["runtime"]:
            shutil.copyfile(ENGINE / name, staging / name)
        for path in licenses:
            target = staging / "licenses" / path.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
        for name, content in launcher_files().items():
            (staging / name).write_bytes(content)
        for name in ("openrc-editor-build.json", "openrc-template_release-build.json"):
            shutil.copyfile(ENGINE / name, staging / name)
        shutil.copyfile(SNAPSHOT / SNAPSHOT_RECEIPT, staging / SNAPSHOT_RECEIPT)
        files = {path.relative_to(staging).as_posix(): sha(path) for path in staging.rglob("*") if path.is_file()}
        receipt = {"format": PACKAGE_FORMAT, "build_identity": identity, "godot_commit": native_build.COMMIT,
                   "engine_version": editor["version"], "editor_sha256": editor["executable_sha256"],
                   "template_sha256": template["executable_sha256"], "sources": editor["sources"],
                   "integration": editor["integration"], "runtime": editor["runtime"],
                   "snapshot_sha256": files[SNAPSHOT_RECEIPT], "import_report": import_report,
                   "export_report": result["report"], "files": files}
        (staging / PACKAGE_RECEIPT).write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        if OUTPUT.exists():
            verify_tree(OUTPUT, PACKAGE_RECEIPT, PACKAGE_FORMAT)
        replace_tree(staging, OUTPUT)
        print(f"Packaged current-source Windows product: {OUTPUT}", flush=True)
        return receipt
    finally:
        for key, value in old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        if staging.exists():
            remove_owned_tree(staging, OUTPUT.parent, "nvidia-product-export-")


def main() -> int:
    global DEADLINE
    DEADLINE = time.monotonic() + 1200
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--prepare-only", action="store_true", help="snapshot current source without importing or exporting")
    mode.add_argument("--package", action="store_true", help="snapshot, import and package current source (default)")
    parser.add_argument("--verify", action="store_true", help="verify an existing package and its receipt")
    parser.add_argument("--launch", action="store_true", help="launch the existing product with normal user settings")
    parser.add_argument("--import-report", type=Path, help="receipt a successful checked import of the existing snapshot before refreshing it")
    args = parser.parse_args()
    if args.prepare_only and (args.verify or args.launch):
        parser.error("--prepare-only cannot be combined with --verify or --launch")
    if args.package and (args.verify or args.launch):
        parser.error("--package cannot be combined with --verify or --launch")
    if args.import_report and (args.verify or args.launch):
        parser.error("--import-report cannot be combined with --verify or --launch")
    if args.verify or args.launch:
        receipt = verify_product()
        print(f"Verified package {receipt['build_identity']['describe']}: {OUTPUT}", flush=True)
        if args.launch:
            subprocess.Popen([str(OUTPUT / "OpenRC Simulator.exe")], cwd=OUTPUT)
            print("Launched OpenRC Simulator.", flush=True)
        return 0
    if args.import_report:
        record_checked_import(args.import_report)
    snapshot = prepare_snapshot()
    if not args.prepare_only:
        package_product(snapshot)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"NVIDIA product packaging failed: {error}", file=sys.stderr)
        raise SystemExit(1)
