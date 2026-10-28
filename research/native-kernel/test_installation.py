#!/usr/bin/env python3
"""Exercise NK-3 manual loading in disposable projects with a built Linux library.

This is a loader regression, not a physics or release qualification. It needs the
pinned editor and an existing NK-3 build; no installation into app/ is performed.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC = importlib.util.spec_from_file_location("nk3_install_test_builder", HERE / "build.py")
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)

TEST_SCRIPT = '''extends SceneTree
const Stage := preload("res://sim/native_stage.gd")

func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    var expectation: String = args[0]
    var expected_reason: String = args[1] if args.size() > 1 else ""
    var preloaded := ClassDB.class_exists("OpenRCNativeKernel")
    var early_status := -1
    if expectation == "preloaded" and not preloaded:
        early_status = GDExtensionManager.load_extension(Stage.EXTENSION_PATH)
    var status: Dictionary = Stage.library_status()
    var again: Dictionary = Stage.library_status()
    var loaded := ClassDB.class_exists("OpenRCNativeKernel")
    var ok := not preloaded and status == again
    if expectation == "ok":
        ok = ok and status.ok and loaded
        var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Stage.RECEIPT_PATH))
        for invalid: Variant in [null, {}, [], true, "1", 1.5]:
            var bad_envelope: Dictionary = receipt.duplicate(true)
            bad_envelope.abi_version = invalid
            var bad_row: Dictionary = receipt.duplicate(true)
            bad_row.platforms.linux.abi_version = invalid
            ok = ok and Stage._platform_row(bad_envelope).is_empty() and Stage._platform_row(bad_row).is_empty()
        var float_abi: Dictionary = receipt.duplicate(true)
        float_abi.abi_version = 2.0
        float_abi.platforms.linux.abi_version = 2.0
        ok = ok and not Stage._platform_row(float_abi).is_empty()
    elif expectation == "preloaded":
        ok = ok and early_status == 0 and loaded and not status.ok and expected_reason in str(status.reason)
    else:
        ok = ok and not loaded and not status.ok and expected_reason in str(status.reason)
    print("NK3_LOADER_TEST ok=%s initial=%s loaded=%s status=%s" % [ok, preloaded, loaded, status])
    quit(0 if ok else 1)
'''

QUALIFICATION_HOST_SCRIPT = '''extends SceneTree
const Qualification := preload("res://tools/native_qualification.gd")

func _initialize() -> void:
    var host := Qualification.new()
    root.add_child(host)
    host.start(PackedStringArray(["--quick-flight", "--native-qualification=" + OS.get_cmdline_user_args()[0]]))
'''


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy_preload_dependencies(project: Path, roots: tuple[str, ...]) -> None:
    """Stage the real fixed diagnostics' static resources into the disposable project."""
    app = ROOT / "app"
    pending = list(roots)
    copied = set()
    while pending:
        relative = pending.pop()
        if relative in copied:
            continue
        source = app / relative
        if not source.is_file():
            raise ValueError(f"Missing qualification dependency: {source}")
        destination = project / relative
        if not destination.is_file():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        copied.add(relative)
        if source.suffix == ".gd":
            pending.extend(re.findall(r'''preload\(\s*["']res://([^"']+)["']''', source.read_text()))


def checked(project: Path, engine: Path, checks: Path, label: str, args: list[str], marker: str = "",
            extra_markers: tuple[str, ...] = (), timeout: int = 30, user_data: Path = None) -> None:
    command = [sys.executable, str(ROOT / "tools/godot/run_checked.py"), "--out-dir", str(checks),
               "--timeout", str(timeout), "--label", label]
    for required in (marker, *extra_markers):
        if required: command += ["--require-text", required]
    command += ["--", str(engine), "--headless", "--path", str(project), "--audio-driver", "Dummy", *args]
    environment = dict(os.environ, XDG_DATA_HOME=str(user_data)) if user_data is not None else None
    completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               timeout=timeout + 10, env=environment)
    if completed.returncode:
        raise RuntimeError(f"{label} failed ({completed.returncode}):\n{completed.stdout}\n{completed.stderr}")


def run(godot: Path, library: Path, stage: Path, keep: bool = False) -> None:
    if not godot.is_file() or not library.is_file() or not stage.is_file():
        raise SystemExit("The pinned Linux editor, NK-3 library and stage script are required; build NK-3 first.")
    (ROOT / "tmp").mkdir(exist_ok=True)
    temporary_directory = (contextlib.nullcontext(tempfile.mkdtemp(prefix="nk3-installation-test-", dir=ROOT / "tmp"))
                           if keep else tempfile.TemporaryDirectory(prefix="nk3-installation-test-", dir=ROOT / "tmp"))
    with temporary_directory as temporary:
        scratch = Path(temporary)
        if keep: print(f"Retained disposable installation fixture: {scratch}", flush=True)
        # The executable-adjacent copy is a positive control for the old any-path hash check.
        engine = scratch / "engine/Godot"
        engine.parent.mkdir()
        os.link(godot.resolve(), engine)
        shutil.copy2(library, engine.parent / "libopenrc_native_kernel.so")
        base = scratch / "base"
        shutil.copytree(ROOT / "app/sim", base / "sim")
        shutil.copy2(stage, base / "sim/native_stage.gd")
        shutil.copytree(ROOT / "app/app_state", base / "app_state")
        shutil.copytree(ROOT / "app/physics", base / "physics")
        shutil.copytree(ROOT / "app/data", base / "data")
        shutil.copytree(ROOT / "app/failures", base / "failures")
        shutil.copytree(ROOT / "app/input", base / "input")
        shutil.copytree(ROOT / "app/scenery", base / "scenery")
        (base / "tools").mkdir()
        shutil.copy2(ROOT / "app/tools/native_qualification.gd", base / "tools/native_qualification.gd")
        (base / "tests").mkdir()
        tests = ("test_native_stage.gd", "test_native_session.gd", "test_native_replay.gd",
                 "test_native_helicopter_session.gd", "test_heli_restore_radio.gd")
        for test in tests:
            shutil.copy2(ROOT / "app/tests" / test, base / "tests" / test)
        copy_preload_dependencies(base, ("tools/native_qualification.gd", *("tests/" + test for test in tests)))
        (base / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="NK3 loader test"\n'
            '[physics]\ncommon/physics_ticks_per_second=240\n')
        (base / "test.gd").write_text(TEST_SCRIPT)
        (base / "qualification_host.gd").write_text(QUALIFICATION_HOST_SCRIPT)
        (base / "proof.txt").write_text("verified source\n")
        native = base / "native/kernel"
        native.mkdir(parents=True)
        (native / ".gdignore").touch()
        (native / "openrc_native_kernel.gdextension").write_text(builder.APP_DESCRIPTOR)
        shutil.copy2(library, native / "libopenrc_native_kernel.so")
        row = {"backend_version": builder.BACKEND_VERSION, "abi_version": builder.ABI_VERSION,
               "binary_sha256": digest(library), "source_sha256": "a" * 64, "lock_sha256": "b" * 64,
               "engine_version": builder.pinned_engine_identity()[0], "engine_sha256": digest(godot),
               "mirrored_sources": {"app/proof.txt": digest(base / "proof.txt")}}
        receipt = {"format": builder.RECEIPT_FORMAT, "backend": "native",
                   "backend_version": builder.BACKEND_VERSION, "abi_version": builder.ABI_VERSION,
                   "platforms": {"linux": row}}
        (native / "build-receipt.json").write_text(json.dumps(receipt))
        checks = scratch / "checks"
        checked(base, engine, checks, "import", ["--import"])
        for mode, marker in (("stage", "NK3_NATIVE_STAGE_NATIVE verdict=pass"),
                             ("lifecycle", "NK3_NATIVE_SESSION_NATIVE verdict=pass"),
                             ("replay", "NK3_NATIVE_REPLAY_NATIVE verdict=pass"),
                             ("helicopter", "NK3_NATIVE_HELICOPTER_NATIVE verdict=pass"),
                             ("helicopter-radio", "NK3_NATIVE_HELICOPTER_RADIO_NATIVE verdict=pass")):
            checked(base, engine, checks, "qualification-" + mode,
                    ["--script", str(base / "qualification_host.gd"), "--", mode],
                    "NATIVE_QUALIFICATION preloaded=false",
                    (f"NATIVE_QUALIFICATION mode={mode} verdict=pass", marker),
                    timeout=120, user_data=scratch / "user-data")
            print(f"PASS native {mode} qualification host")
        cases = {
            "valid": ("ok", ""),
            "missing-receipt": ("refuse", "not installed"),
            "invalid-receipt": ("refuse", "receipt is malformed"),
            "invalid-json-receipt": ("refuse", "receipt is malformed"),
            "invalid-envelope-abi": ("refuse", "receipt is malformed"),
            "invalid-platform-abi": ("refuse", "receipt is malformed"),
            "invalid-source-digest": ("refuse", "receipt is malformed"),
            "invalid-source-path": ("refuse", "receipt is malformed"),
            "missing-binary": ("refuse", "binary"),
            "wrong-binary-with-matching-alternate": ("refuse", "binary"),
            "wrong-engine": ("refuse", "exact verified Godot"),
            "wrong-source": ("refuse", "mirrored source differs"),
            "alternate-descriptor-path": ("refuse", "descriptor"),
            "extra-feature-key": ("refuse", "descriptor"),
            "extra-dependencies": ("refuse", "descriptor"),
            "wrong-entry-symbol": ("refuse", "descriptor"),
            "malformed-descriptor": ("refuse", "descriptor"),
            "preloaded-class": ("preloaded", "before verification"),
            "migrated-cache": ("ok", ""),
        }
        for name, (expectation, reason) in cases.items():
            project = scratch / name
            shutil.copytree(base, project)
            fixture = project / "native/kernel"
            descriptor = fixture / "openrc_native_kernel.gdextension"
            lib = fixture / "libopenrc_native_kernel.so"
            receipt_path = fixture / "build-receipt.json"
            record = json.loads(receipt_path.read_text())
            if name == "missing-receipt":
                receipt_path.unlink()
            elif name == "invalid-receipt":
                record["format"] = "wrong-receipt"
            elif name == "invalid-envelope-abi":
                record["abi_version"] = {}
            elif name == "invalid-platform-abi":
                record["platforms"]["linux"]["abi_version"] = {}
            elif name == "invalid-source-digest":
                record["platforms"]["linux"]["mirrored_sources"]["app/proof.txt"] = "invalid"
            elif name == "invalid-source-path":
                record["platforms"]["linux"]["mirrored_sources"] = {"app/../proof.txt": "a" * 64}
            elif name == "missing-binary":
                lib.unlink()
            elif name == "wrong-binary-with-matching-alternate":
                lib.write_bytes(b"incorrect binary")
            elif name == "wrong-engine":
                record["platforms"]["linux"]["engine_sha256"] = "0" * 64
            elif name == "wrong-source":
                (project / "proof.txt").write_text("changed source\n")
            elif name == "alternate-descriptor-path":
                descriptor.write_text(builder.APP_DESCRIPTOR.replace("libopenrc_native_kernel.so", "alternate.so"))
            elif name == "extra-feature-key":
                descriptor.write_text(builder.APP_DESCRIPTOR + 'linux.x86_64.debug = "res://native/kernel/alternate.so"\n')
            elif name == "extra-dependencies":
                descriptor.write_text(builder.APP_DESCRIPTOR + '\n[dependencies]\nlinux.x86_64 = {"libother.so": ""}\n')
            elif name == "wrong-entry-symbol":
                descriptor.write_text(builder.APP_DESCRIPTOR.replace("openrc_native_kernel_library_init", "other_init"))
            elif name == "malformed-descriptor":
                descriptor.write_text("[configuration\n")
            elif name == "migrated-cache":
                registry = project / ".godot/extension_list.cfg"
                registry.write_text("res://native/kernel/openrc_native_kernel.gdextension\n")
                builder.prepare_manual_loading(project, fixture)
            if name == "invalid-json-receipt":
                receipt_path.write_text("{")
            elif receipt_path.exists():
                receipt_path.write_text(json.dumps(record))
            checked(project, engine, checks, name,
                    ["--script", str(project / "test.gd"), "--", expectation, reason], "NK3_LOADER_TEST ok=true")
            print(f"PASS {name}")
    print(f"NK3 installation: {len(cases)} checked loader cases passed")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT / ".tools/Godot_v4.8-beta1_linux.x86_64")
    parser.add_argument("--library", type=Path, default=ROOT / "tmp/native-kernel/lib/libopenrc_native_kernel.so")
    parser.add_argument("--stage", type=Path, default=ROOT / "app/sim/native_stage.gd",
                        help="stage script under test; a draft can stay outside app/")
    parser.add_argument("--keep", action="store_true", help="retain the disposable project and checked-run logs under tmp/")
    args = parser.parse_args()
    run(args.godot, args.library, args.stage, args.keep)


if __name__ == "__main__":
    main()
