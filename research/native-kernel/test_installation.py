#!/usr/bin/env python3
"""Exercise NK-3 manual loading in disposable projects with a built Linux library.

This is a loader regression, not a physics or release qualification. It needs the
pinned editor and an existing NK-3 build; no installation into app/ is performed.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
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
    elif expectation == "preloaded":
        ok = ok and early_status == 0 and loaded and not status.ok and expected_reason in str(status.reason)
    else:
        ok = ok and not loaded and not status.ok and expected_reason in str(status.reason)
    print("NK3_LOADER_TEST ok=%s initial=%s loaded=%s status=%s" % [ok, preloaded, loaded, status])
    quit(0 if ok else 1)
'''


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked(project: Path, engine: Path, checks: Path, label: str, args: list[str], marker: str = "") -> None:
    command = [sys.executable, str(ROOT / "tools/godot/run_checked.py"), "--out-dir", str(checks),
               "--timeout", "30", "--label", label]
    if marker:
        command += ["--require-text", marker]
    command += ["--", str(engine), "--headless", "--path", str(project), "--audio-driver", "Dummy", *args]
    completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=40)
    if completed.returncode:
        raise RuntimeError(f"{label} failed ({completed.returncode}):\n{completed.stdout}\n{completed.stderr}")


def run(godot: Path, library: Path, stage: Path) -> None:
    if not godot.is_file() or not library.is_file() or not stage.is_file():
        raise SystemExit("The pinned Linux editor, NK-3 library and stage script are required; build NK-3 first.")
    (ROOT / "tmp").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="nk3-installation-test-", dir=ROOT / "tmp") as temporary:
        scratch = Path(temporary)
        # The executable-adjacent copy is a positive control for the old any-path hash check.
        engine = scratch / "engine/Godot"
        engine.parent.mkdir()
        os.link(godot.resolve(), engine)
        shutil.copy2(library, engine.parent / "libopenrc_native_kernel.so")
        base = scratch / "base"
        (base / "sim").mkdir(parents=True)
        shutil.copy2(stage, base / "sim/native_stage.gd")
        shutil.copytree(ROOT / "app/physics", base / "physics")
        (base / "project.godot").write_text('config_version=5\n[application]\nconfig/name="NK3 loader test"\n')
        (base / "test.gd").write_text(TEST_SCRIPT)
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
        cases = {
            "valid": ("ok", ""),
            "missing-receipt": ("refuse", "not installed"),
            "invalid-receipt": ("refuse", "receipt is malformed"),
            "missing-binary": ("refuse", "binary"),
            "wrong-binary-with-matching-alternate": ("refuse", "binary"),
            "wrong-engine": ("refuse", "exact verified Godot"),
            "wrong-source": ("refuse", "mirrored source differs"),
            "alternate-descriptor-path": ("refuse", "descriptor"),
            "extra-feature-key": ("refuse", "descriptor"),
            "extra-dependencies": ("refuse", "descriptor"),
            "wrong-entry-symbol": ("refuse", "descriptor"),
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
            elif name == "migrated-cache":
                registry = project / ".godot/extension_list.cfg"
                registry.write_text("res://native/kernel/openrc_native_kernel.gdextension\n")
                builder.prepare_manual_loading(project, fixture)
            if receipt_path.exists():
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
    args = parser.parse_args()
    run(args.godot, args.library, args.stage)


if __name__ == "__main__":
    main()
