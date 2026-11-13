#!/usr/bin/env python3
"""Stage verified NK-3 export inputs and bind the final Linux executable to its sidecars.

Preparation validates the existing oracle receipts. Finalization creates a private
candidate; the exact executable still needs package qualification before delivery.
"""
from __future__ import annotations

import argparse
import fnmatch
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
    "test_native_helicopter_session.gd": ROOT / "app/tests/test_native_helicopter_session.gd",
    "test_heli_restore_radio.gd": ROOT / "app/tests/test_heli_restore_radio.gd",
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
MAC_MANIFEST_FORMAT = "openrc-macos-native-kernel-package-v1"
MAC_MANIFEST = ROOT / "app/native/kernel/package-macos.json"
MAC_QUALIFICATION = {name: QUALIFICATION[name] for name in
                     ("session_probe.gd", "test_native_stage.gd", "test_native_session.gd", "test_native_replay.gd")}
MAC_DESCRIPTOR = (
    "; DT-MAC packaged stage; loaded explicitly after embedded identity verification.\n"
    "[configuration]\n"
    'entry_symbol = "openrc_native_kernel_library_init"\n'
    'compatibility_minimum = "4.7"\n'
    "reloadable = false\n\n"
    "[libraries]\n"
    'macos.arm64 = "../Frameworks/libopenrc_native_kernel.dylib"\n'
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


def _mac_builder():
    spec = importlib.util.spec_from_file_location("nk3_package_macos_builder", HERE / "build_macos.py")
    if spec is None or spec.loader is None:
        raise ValueError("Mac native builder is unavailable")
    mac = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mac)
    return mac


def _validate_mac_cited_evidence(root: Path, cited: object, candidate: dict, mutant: dict, mac) -> None:
    """Revalidate the installed receipt's exact reports, never substitute newer runs."""
    roster = mac.verification_roster()
    if not isinstance(cited, dict) or set(cited) != set(roster):
        raise ValueError("Mac installation evidence roster is missing, extra or malformed")
    cache = {}
    runner = mac._runner()
    for key, pattern in roster.items():
        record = cited[key]
        if not isinstance(record, dict) or set(record) != {"results", "results_sha256", "verdict", "compared"}:
            raise ValueError(f"Malformed Mac installation evidence citation: {key}")
        name = record["results"]
        expected_hash = record["results_sha256"]
        is_mutant = key == "negative_control"
        if (not isinstance(name, str) or not name or "/" in name or "\\" in name
                or any(ord(char) < 32 or ord(char) == 127 for char in name)
                or Path(name).name != name or not fnmatch.fnmatchcase(name, pattern)
                or ("_mutant" in name) != is_mutant
                or not isinstance(expected_hash, str) or len(expected_hash) != 64
                or any(char not in "0123456789abcdef" for char in expected_hash)
                or record["verdict"] != ("fail" if is_mutant else "pass")
                or type(record["compared"]) is not int or record["compared"] <= 0):
            raise ValueError(f"Invalid Mac installation evidence citation: {key}")
        path = root / name
        if path.is_symlink() or not path.is_file() or path.resolve().parent != root:
            raise ValueError(f"Missing or redirected cited Mac evidence: {key}")
        before = sha(path)
        if before != expected_hash:
            raise ValueError(f"Cited Mac evidence changed: {key}")
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                raise ValueError("report is not an object")
            mac._check_oracle_identity(data, path, key, mutant if is_mutant else candidate, cache, runner)
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
            raise ValueError(f"Cited Mac evidence refused ({key}): {error}") from error
        total = data.get("total")
        if not isinstance(total, dict) or type(total.get("compared")) is not int \
                or total["compared"] != record["compared"] or sha(path) != before:
            raise ValueError(f"Cited Mac evidence count or bytes changed: {key}")


def verified_mac_install(tool_root: Path, godot: Path) -> dict:
    """Revalidate the exact signed candidate and all required source-oracle evidence."""
    mac = _mac_builder()
    root = tool_root.resolve()
    tmp = (ROOT / "tmp").resolve()
    if root == tmp or not root.is_relative_to(tmp):
        raise ValueError("Mac tool root must be inside this checkout's tmp/")
    lock = mac.locked.load_lock()
    toolchain = mac.host_toolchain()
    engine = mac.godot_identity(godot, lock)
    identity = mac._identity()
    candidate = mac.validate_build(root, False, identity, toolchain, engine, lock)
    mutant = mac.validate_build(root, True, identity, toolchain, engine, lock)
    mac.validate_signing_pair(candidate, mutant)
    if candidate["binary_sha256"] == mutant["binary_sha256"] \
            or candidate["extension_api_sha256"] != mutant["extension_api_sha256"]:
        raise ValueError("Mac candidate and negative control are not distinct compatible builds")
    directory = builder.APP_DESTINATION
    expected_directory = ROOT / "app/native/kernel"
    if directory.absolute() != expected_directory.absolute() or directory.is_symlink() \
            or directory.parent.is_symlink() or directory.resolve() != directory.absolute():
        raise ValueError("Mac installation directory is redirected or unexpected")
    ignore = directory / ".gdignore"
    receipt_path = directory / "build-receipt-macos.json"
    descriptor = directory / "openrc_native_kernel_macos.gdextension"
    library = directory / "libopenrc_native_kernel.dylib"
    license_path = directory / "LICENSE.godot-cpp.md"
    verified_license = root / "work/candidate/dependencies/godot-cpp/LICENSE.md"
    for path in (ignore, receipt_path, descriptor, library, license_path, verified_license):
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Missing or redirected Mac installation input: {path}")
    if sha(license_path) != sha(verified_license):
        raise ValueError("Installed godot-cpp licence differs from the verified dependency")
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    if not isinstance(receipt, dict) or receipt.get("format") != builder.RECEIPT_FORMAT \
            or receipt.get("backend") != "native" or receipt.get("backend_version") != builder.BACKEND_VERSION \
            or type(receipt.get("abi_version")) is not int or receipt["abi_version"] != builder.ABI_VERSION \
            or not isinstance(receipt.get("platforms"), dict):
        raise ValueError("Mac installation receipt envelope is invalid")
    row = receipt["platforms"].get("macos")
    required = {"platform": "macos", "architecture": "arm64", "backend": "native",
                "backend_version": builder.BACKEND_VERSION, "abi_version": builder.ABI_VERSION,
                "qualification_scope": mac.SOURCE_SCOPE, "binary_sha256": candidate["binary_sha256"],
                "source_sha256": identity["source_sha256"], "lock_sha256": identity["lock_sha256"],
                "mirrored_sources": identity["reference_sources_sha256"], "runtime_os_version": toolchain["os_version"],
                "runtime_os_build": toolchain["os_build"], "engine_version": mac._engine_display(engine["version"]),
                "engine_sha256": engine["sha256"]}
    if not isinstance(row, dict) or any(row.get(key) != value for key, value in required.items()) \
            or type(row.get("abi_version")) is not int or sha(library) != candidate["binary_sha256"] \
            or descriptor.read_text(encoding="utf-8") != mac.SOURCE_DESCRIPTOR:
        raise ValueError("Mac installation differs from the verified source build or evidence")
    _validate_mac_cited_evidence(root, row.get("verification"), candidate, mutant, mac)
    return receipt


def _mac_manifest(tool_root: Path, godot: Path) -> dict:
    receipt = verified_mac_install(tool_root, godot)
    return {"format": MAC_MANIFEST_FORMAT, "platform": "macos", "architecture": "arm64",
            "engine_version": receipt["platforms"]["macos"]["engine_version"], "native_receipt": receipt,
            "solver_sha256": solver_identity(), "license_sha256": sha(builder.APP_DESTINATION / "LICENSE.godot-cpp.md"),
            "qualification_sources": {name: sha(path) for name, path in MAC_QUALIFICATION.items()}}


def prepare_macos(tool_root: Path, godot: Path) -> dict:
    manifest = _mac_manifest(tool_root, godot)
    if MAC_MANIFEST.is_symlink():
        raise ValueError("Mac manifest path is redirected")
    with MAC_MANIFEST.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(manifest, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")
    return {"manifest": str(MAC_MANIFEST), "manifest_sha256": sha(MAC_MANIFEST)}


def stage_macos(bundle: Path, tool_root: Path, godot: Path) -> dict:
    """Stage exact previously verified bytes before outer app signing; never re-sign the dylib."""
    if bundle.is_symlink() or not bundle.is_dir() or not bundle.name.endswith(".app"):
        raise ValueError("Mac destination must be a real .app directory")
    if MAC_MANIFEST.is_symlink() or not MAC_MANIFEST.is_file():
        raise ValueError("Missing or redirected Mac package manifest")
    manifest = json.loads(MAC_MANIFEST.read_text(encoding="utf-8"))
    if manifest != _mac_manifest(tool_root, godot):
        raise ValueError("Mac package inputs changed since preparation")
    contents = bundle / "Contents"
    destination = contents / "Frameworks"
    resources = contents / "Resources"
    if contents.is_symlink() or not contents.is_dir() or destination.is_symlink() \
            or (destination.exists() and not destination.is_dir()) or resources.is_symlink() or not resources.is_dir():
        raise ValueError("Mac Frameworks or Resources destination is missing or redirected")
    destination.mkdir(exist_ok=True)
    library = destination / "libopenrc_native_kernel.dylib"
    descriptor = resources / "openrc_native_kernel_macos.gdextension"
    license_file = resources / "LICENSE.godot-cpp.md"
    if any(path.exists() or path.is_symlink() for path in (library, descriptor, license_file)):
        raise ValueError("Mac native package target already exists")
    source = builder.APP_DESTINATION / library.name
    with source.open("rb") as src, library.open("xb") as dst:
        shutil.copyfileobj(src, dst, length=1024 * 1024)
    shutil.copystat(source, library)
    if sha(library) != manifest["native_receipt"]["platforms"]["macos"]["binary_sha256"]:
        raise ValueError("Mac native library changed during staging")
    with descriptor.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(MAC_DESCRIPTOR)
    license_source = builder.APP_DESTINATION / license_file.name
    with license_source.open("rb") as src, license_file.open("xb") as dst:
        shutil.copyfileobj(src, dst, length=1024 * 1024)
    if sha(license_file) != manifest["license_sha256"] or sha(license_source) != manifest["license_sha256"]:
        raise ValueError("Mac native licence changed during staging")
    if manifest != _mac_manifest(tool_root, godot):
        raise ValueError("Mac package inputs changed during staging")
    return {"library": str(library), "library_sha256": sha(library), "descriptor": str(descriptor),
            "descriptor_sha256": sha(descriptor), "manifest_sha256": sha(MAC_MANIFEST),
            "license_sha256": sha(license_file)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("prepare")
    final = commands.add_parser("finalize")
    final.add_argument("--executable", type=Path, required=True)
    final.add_argument("--template", type=Path, required=True)
    mac_prepare = commands.add_parser("prepare-macos")
    mac_prepare.add_argument("--tool-root", type=Path, required=True)
    mac_prepare.add_argument("--godot", type=Path, required=True)
    mac_stage = commands.add_parser("stage-macos")
    mac_stage.add_argument("--bundle", type=Path, required=True)
    mac_stage.add_argument("--tool-root", type=Path, required=True)
    mac_stage.add_argument("--godot", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "prepare": result = prepare()
    elif args.command == "finalize": result = finalize(args.executable, args.template)
    elif args.command == "prepare-macos": result = prepare_macos(args.tool_root, args.godot)
    else: result = stage_macos(args.bundle, args.tool_root, args.godot)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
