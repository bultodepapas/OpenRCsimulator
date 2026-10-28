#!/usr/bin/env python3
"""Stage verified NK-3 export inputs and bind the final Linux executable to its sidecars.

Preparation validates the existing oracle receipts. Finalization creates a private
candidate; the exact executable still needs package qualification before delivery.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC = importlib.util.spec_from_file_location("nk3_package_builder", HERE / "build.py")
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)
MANIFEST_FORMAT = "openrc-native-kernel-package v1"
ARTIFACT_FORMAT = "openrc-native-kernel-package-artifact v1"
MANIFEST = ROOT / "app/native/kernel/package.json"
QUALIFICATION = {
    "session_probe.gd": ROOT / "research/performance/session_probe.gd",
    "test_native_stage.gd": ROOT / "app/tests/test_native_stage.gd",
    "test_native_session.gd": ROOT / "app/tests/test_native_session.gd",
    "test_native_replay.gd": ROOT / "app/tests/test_native_replay.gd",
}
DESCRIPTOR = (
    "; NK-3 packaged stage; loaded explicitly after embedded identity verification.\n"
    "[configuration]\n"
    'entry_symbol = "openrc_native_kernel_library_init"\n'
    'compatibility_minimum = "4.7"\n'
    "reloadable = false\n\n"
    "[libraries]\n"
    'linux.x86_64 = "libopenrc_native_kernel.so"\n'
)


def sha(path: Path) -> str:
    # Stream large embedded-PCK executables; keep the toolchain's Python 3.9 minimum.
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def solver_identity() -> str:
    digest = hashlib.sha256()
    paths = [("res://" + path.relative_to(ROOT / "app").as_posix(), path)
             for directory in ("physics", "sim", "failures")
             for path in (ROOT / "app" / directory).rglob("*.gd")]
    paths.sort(key=lambda entry: entry[0])
    if not paths:
        raise ValueError("solver source set is empty")
    for resource, path in paths:
        digest.update(resource.encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def verified_install() -> dict:
    receipt = json.loads((builder.APP_DESTINATION / "build-receipt.json").read_text())
    if not isinstance(receipt, dict) or receipt.get("format") != builder.RECEIPT_FORMAT \
            or receipt.get("backend") != "native" or receipt.get("backend_version") != builder.BACKEND_VERSION \
            or type(receipt.get("abi_version")) is not int or receipt["abi_version"] != builder.ABI_VERSION \
            or not isinstance(receipt.get("platforms"), dict):
        raise ValueError("native installation receipt envelope is invalid")
    row = receipt["platforms"].get("linux")
    if not isinstance(row, dict) or row.get("platform") != "linux" or row.get("architecture") != "x86_64" \
            or row.get("backend") != "native" or row.get("backend_version") != builder.BACKEND_VERSION \
            or type(row.get("abi_version")) is not int or row["abi_version"] != builder.ABI_VERSION \
            or not isinstance(row.get("verification"), dict):
        raise ValueError("native installation Linux receipt row is invalid")
    library = builder.APP_DESTINATION / f"lib{builder.NAME}.so"
    if sha(library) != row.get("binary_sha256") or builder.source_digest() != row.get("source_sha256"):
        raise ValueError("native library or C++ sources differ from the installation receipt")
    if sha(HERE / "toolchain-lock.json") != row.get("lock_sha256"):
        raise ValueError("native toolchain lock differs from the installation receipt")
    sources = builder.mirrored_sources()
    if row.get("mirrored_sources") != sources:
        raise ValueError("mirrored sources changed; qualify and reinstall before exporting")
    engine_version, engine_sha = builder.pinned_engine_identity()
    if row.get("engine_version") != engine_version or row.get("engine_sha256") != engine_sha:
        raise ValueError("export editor differs from the verified editor")
    for kind, pattern in builder.VERIFICATIONS.items():
        current = builder.find_verification(kind, pattern, row["binary_sha256"], sources)
        if current != row["verification"].get(kind):
            raise ValueError("installation does not cite the current " + kind + " verification")
    return receipt


def prepare() -> dict:
    receipt = verified_install()
    manifest = {
        "format": MANIFEST_FORMAT, "platform": "linux", "architecture": "x86_64",
        "engine_version": receipt["platforms"]["linux"]["engine_version"],
        "native_receipt": receipt, "solver_sha256": solver_identity(),
        "qualification_sources": {name: sha(path) for name, path in QUALIFICATION.items()},
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return {"manifest": str(MANIFEST), "manifest_sha256": sha(MANIFEST)}


def finalize(executable: Path, template: Path) -> dict:
    executable = executable.resolve(strict=True)
    template = template.resolve(strict=True)
    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("format") != MANIFEST_FORMAT or manifest.get("native_receipt") != verified_install():
        raise ValueError("prepared package inputs are stale")
    if manifest.get("solver_sha256") != solver_identity() or manifest.get("qualification_sources") != {
            name: sha(path) for name, path in QUALIFICATION.items()}:
        raise ValueError("solver or diagnostic sources changed during export")
    destination = executable.parent / "native/kernel"
    if destination.exists() or destination.is_symlink() or (executable.parent / "native").is_symlink() \
            or destination.resolve() != executable.parent / "native/kernel":
        raise ValueError("package sidecar directory must not be redirected")
    destination.mkdir(parents=True, exist_ok=False)
    library = f"lib{builder.NAME}.so"
    shutil.copy2(builder.APP_DESTINATION / library, destination / library)
    if sha(destination / library) != manifest["native_receipt"]["platforms"]["linux"]["binary_sha256"]:
        raise ValueError("native library changed during package staging")
    shutil.copy2(builder.APP_DESTINATION / "LICENSE.godot-cpp.md", destination / "LICENSE.godot-cpp.md")
    (destination / f"{builder.NAME}.gdextension").write_text(DESCRIPTOR)
    artifact = {"format": ARTIFACT_FORMAT, "executable_sha256": sha(executable),
                "manifest_sha256": sha(MANIFEST), "template_sha256": sha(template),
                "editor_sha256": manifest["native_receipt"]["platforms"]["linux"]["engine_sha256"],
                "native_binary_sha256": sha(destination / library)}
    (destination / "package-receipt.json").write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n")
    return artifact


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("prepare")
    final = commands.add_parser("finalize")
    final.add_argument("--executable", type=Path, required=True)
    final.add_argument("--template", type=Path, required=True)
    args = parser.parse_args()
    result = prepare() if args.command == "prepare" else finalize(args.executable, args.template)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
