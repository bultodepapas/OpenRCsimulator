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


def _pair_binder():
    spec = importlib.util.spec_from_file_location("nk3_package_macos_engine_pair", HERE / "macos_engine_pair.py")
    if spec is None or spec.loader is None:
        raise ValueError("Mac research engine-pair verifier is unavailable")
    pair = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pair)
    return pair


def _research_pair(godot: Path, selection: dict | None, pair_selection: dict | None) -> dict | None:
    """Bind the retained original intakes, never an unverified manifest or receipt alone."""
    if selection is None and pair_selection is None:
        return None
    if not isinstance(selection, dict) or not isinstance(pair_selection, dict) \
            or set(pair_selection) != {"template_intake", "pair_receipt", "export_template", "pins"} \
            or any(not isinstance(value, (Path, str)) or not str(value) for value in pair_selection.values()):
        raise ValueError("Research engine and all four pair inputs must be supplied together")
    if not isinstance(selection.get("receipt"), str) or not isinstance(selection.get("archive"), str) \
            or not isinstance(selection.get("patches"), list) \
            or any(not isinstance(path, str) for path in selection["patches"]):
        raise ValueError("Research engine selection lacks original ordered intake inputs")
    binder = _pair_binder()
    pins = binder._path(pair_selection["pins"])
    before = binder._snapshot(pins, binder.MAX_JSON)
    expected = binder._json(pins)
    result = binder.bind(archive=Path(selection["archive"]), editor_intake=Path(selection["receipt"]).parent,
                         template_intake=Path(pair_selection["template_intake"]),
                         patches=[Path(path) for path in selection["patches"]],
                         pair_receipt=Path(pair_selection["pair_receipt"]),
                         export_template=Path(pair_selection["export_template"]), godot=godot,
                         selection=selection, expected=expected)
    if binder._snapshot(pins, binder.MAX_JSON) != before:
        raise ValueError("Independent engine-pair pins changed during verification")
    return result


def _match_research_pair(pair: dict, row: dict, selection: dict) -> None:
    """Join the producer's result to the independently reverified installed editor row."""
    engine = row.get("engine")
    provenance = engine.get("research_engine") if isinstance(engine, dict) else None
    patches = provenance.get("ordered_patches") if isinstance(provenance, dict) else None
    if not isinstance(pair, dict) or not isinstance(provenance, dict) or not isinstance(patches, list) \
            or provenance.get("scope") != "source-editor-local-custom-engine-research-v1" \
            or provenance.get("selection") != selection or provenance.get("runtime_version") != row.get("engine_version") \
            or engine.get("sha256") != row.get("engine_sha256") or pair.get("editor_sha256") != row.get("engine_sha256") \
            or pair.get("editor_receipt_sha256") != provenance.get("build_receipt_sha256") \
            or pair.get("source_archive_sha256") != provenance.get("source_archive_sha256") \
            or pair.get("source_catalog_sha256") != provenance.get("source_catalog_sha256") \
            or not all(isinstance(patch, dict) for patch in patches) \
            or pair.get("patch_sha256") != [patch.get("sha256") for patch in patches]:
        raise ValueError("Verified pair differs from the installed research editor provenance")


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


def verified_mac_install(tool_root: Path, godot: Path, research_engine: dict | None = None,
                         toolchain_profile: str | None = None) -> dict:
    """Revalidate the exact signed candidate and all required source-oracle evidence."""
    mac = _mac_builder()
    root = tool_root.resolve()
    tmp = (ROOT / "tmp").resolve()
    if root == tmp or not root.is_relative_to(tmp):
        raise ValueError("Mac tool root must be inside this checkout's tmp/")
    lock = mac.locked.load_lock()
    toolchain = mac.host_toolchain(toolchain_profile) if toolchain_profile is not None else mac.host_toolchain()
    engine = mac.godot_identity(godot, lock, research_engine) if research_engine is not None else mac.godot_identity(godot, lock)
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
                "engine_sha256": engine["sha256"], "engine": engine}
    if not isinstance(row, dict) or any(row.get(key) != value for key, value in required.items()) \
            or type(row.get("abi_version")) is not int or sha(library) != candidate["binary_sha256"] \
            or descriptor.read_text(encoding="utf-8") != mac.SOURCE_DESCRIPTOR:
        raise ValueError("Mac installation differs from the verified source build or evidence")
    mac.require_matching_toolchains(row.get("toolchain"), toolchain)
    mac.require_matching_toolchains(candidate.get("toolchain"), toolchain)
    mac.require_matching_toolchains(mutant.get("toolchain"), toolchain)
    _validate_mac_cited_evidence(root, row.get("verification"), candidate, mutant, mac)
    final_toolchain = mac.host_toolchain(toolchain_profile) if toolchain_profile is not None else mac.host_toolchain()
    if final_toolchain != toolchain:
        raise ValueError("Mac toolchain changed during installation verification")
    if research_engine is not None and mac.godot_identity(godot, lock, research_engine) != engine:
        raise ValueError("Research engine provenance changed during installation verification")
    return receipt


def _mac_manifest(tool_root: Path, godot: Path, research_engine: dict | None = None,
                  toolchain_profile: str | None = None, *, pair_selection: dict | None = None) -> dict:
    if (research_engine is None) != (pair_selection is None):
        raise ValueError("Research engine and pair inputs must be supplied together")
    receipt = (verified_mac_install(tool_root, godot, research_engine, toolchain_profile) if toolchain_profile is not None
               else verified_mac_install(tool_root, godot, research_engine) if research_engine is not None
               else verified_mac_install(tool_root, godot))
    manifest = {"format": MAC_MANIFEST_FORMAT, "platform": "macos", "architecture": "arm64",
                "engine_version": receipt["platforms"]["macos"]["engine_version"], "native_receipt": receipt,
                "solver_sha256": solver_identity(), "license_sha256": sha(builder.APP_DESTINATION / "LICENSE.godot-cpp.md"),
                "qualification_sources": {name: sha(path) for name, path in MAC_QUALIFICATION.items()}}
    if research_engine is not None:
        pair = _research_pair(godot, research_engine, pair_selection)
        _match_research_pair(pair, receipt["platforms"]["macos"], research_engine)
        manifest["engine_pair"] = pair
        binder = _pair_binder()
        plugin = binder._path(ROOT / "app/addons/native_kernel/export_plugin.gd")
        manifest["export_plugin_sha256"] = binder._snapshot(plugin, binder.MAX_PATCH)[1]
        checked_runner = binder._path(ROOT / "tools/godot/run_checked.py")
        manifest["export_runner_sha256"] = binder._snapshot(checked_runner, binder.MAX_PATCH)[1]
    return manifest


def prepare_macos(tool_root: Path, godot: Path, research_engine: dict | None = None,
                  toolchain_profile: str | None = None, *, pair_selection: dict | None = None) -> dict:
    manifest = _mac_manifest(tool_root, godot, research_engine, toolchain_profile, pair_selection=pair_selection)
    if MAC_MANIFEST.is_symlink():
        raise ValueError("Mac manifest path is redirected")
    with MAC_MANIFEST.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(manifest, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")
    return {"manifest": str(MAC_MANIFEST), "manifest_sha256": sha(MAC_MANIFEST)}


def stage_macos(bundle: Path, tool_root: Path, godot: Path, research_engine: dict | None = None,
                toolchain_profile: str | None = None, *, pair_selection: dict | None = None) -> dict:
    """Stage exact previously verified bytes before outer app signing; never re-sign the dylib."""
    if bundle.is_symlink() or not bundle.is_dir() or not bundle.name.endswith(".app"):
        raise ValueError("Mac destination must be a real .app directory")
    if research_engine is not None:
        _pair_binder()._path(bundle, directory=True)
    if MAC_MANIFEST.is_symlink() or not MAC_MANIFEST.is_file():
        raise ValueError("Missing or redirected Mac package manifest")
    binder = _pair_binder() if research_engine is not None else None
    manifest_before = binder._snapshot(MAC_MANIFEST, binder.MAX_JSON) if binder is not None else None
    manifest = binder._json(MAC_MANIFEST) if binder is not None else json.loads(MAC_MANIFEST.read_text(encoding="utf-8"))
    current_manifest = lambda: _mac_manifest(tool_root, godot, research_engine, toolchain_profile,
                                             pair_selection=pair_selection)
    if manifest != current_manifest():
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
    if manifest != current_manifest() or (binder is not None and binder._snapshot(MAC_MANIFEST, binder.MAX_JSON) != manifest_before):
        raise ValueError("Mac package inputs changed during staging")
    return {"library": str(library), "library_sha256": sha(library), "descriptor": str(descriptor),
            "descriptor_sha256": sha(descriptor), "manifest_sha256": sha(MAC_MANIFEST),
            "license_sha256": sha(license_file)}


def verify_macos_export(bundle: Path, tool_root: Path, godot: Path, research_engine: dict | None = None,
                        toolchain_profile: str | None = None, *, pair_selection: dict | None = None) -> dict:
    """Revalidate a staged bundle at the caller's final receipt boundary; write nothing."""
    if bundle.is_symlink() or not bundle.is_dir() or not bundle.name.endswith(".app") \
            or MAC_MANIFEST.is_symlink() or not MAC_MANIFEST.is_file():
        raise ValueError("Missing or redirected Mac bundle or package manifest")
    if research_engine is not None:
        _pair_binder()._path(bundle, directory=True)
    binder = _pair_binder() if research_engine is not None else None
    manifest_before = binder._snapshot(MAC_MANIFEST, binder.MAX_JSON) if binder is not None else None
    before = manifest_before[1] if binder is not None else sha(MAC_MANIFEST)
    manifest = binder._json(MAC_MANIFEST) if binder is not None else json.loads(MAC_MANIFEST.read_text(encoding="utf-8"))
    current = lambda: _mac_manifest(tool_root, godot, research_engine, toolchain_profile,
                                    pair_selection=pair_selection)
    if not isinstance(manifest, dict) or manifest != current():
        raise ValueError("Mac package inputs changed since preparation")
    contents = bundle / "Contents"
    frameworks, resources = contents / "Frameworks", contents / "Resources"
    if any(path.is_symlink() or not path.is_dir() for path in (contents, frameworks, resources)):
        raise ValueError("Mac staged package paths are missing or redirected")
    library = frameworks / "libopenrc_native_kernel.dylib"
    descriptor = resources / "openrc_native_kernel_macos.gdextension"
    license_file = resources / "LICENSE.godot-cpp.md"
    if any(path.is_symlink() or not path.is_file() for path in (library, descriptor, license_file)) \
            or sha(library) != manifest["native_receipt"]["platforms"]["macos"]["binary_sha256"] \
            or descriptor.read_text(encoding="utf-8") != MAC_DESCRIPTOR \
            or sha(license_file) != manifest["license_sha256"]:
        raise ValueError("Staged Mac native package files differ from preparation")
    library_sha, descriptor_sha, license_sha = sha(library), sha(descriptor), sha(license_file)
    executable_binding = None
    if binder is not None:
        # The checked export report identifies an invocation and target path;
        # prove that the current app's executable still derives from the exact
        # independently selected template, including after application signing.
        if not isinstance(pair_selection, dict) or not isinstance(pair_selection.get("template_intake"), (str, Path)) \
                or not isinstance(manifest.get("engine_pair"), dict):
            raise ValueError("Research export is missing its independently verified pair")
        macos = binder._path(contents / "MacOS", directory=True)
        entries = list(macos.iterdir())
        if any(entry.is_symlink() for entry in entries):
            raise ValueError("Mac export executable directory contains a symbolic link")
        executables = [entry for entry in entries if entry.is_file()]
        if len(executables) != 1:
            raise ValueError("Mac export must contain exactly one executable")
        template = binder._path(Path(pair_selection["template_intake"]) /
                                "build-source-template_release/bin/godot.macos.template_release.arm64")
        executable_binding = binder.verify_export_executable(
            template, binder._path(executables[0]), manifest["engine_pair"].get("template_sha256"))
    if sha(MAC_MANIFEST) != before or (binder is not None and binder._snapshot(MAC_MANIFEST, binder.MAX_JSON) != manifest_before) \
            or manifest != current() \
            or any(path.is_symlink() or not path.is_file() for path in (library, descriptor, license_file)) \
            or (sha(library), sha(descriptor), sha(license_file)) != (library_sha, descriptor_sha, license_sha):
        raise ValueError("Mac package inputs changed during final revalidation")
    result = {"manifest_sha256": before, "library_sha256": library_sha,
              "descriptor_sha256": descriptor_sha, "license_sha256": license_sha}
    if "engine_pair" in manifest:
        result["engine_pair"] = manifest["engine_pair"]
        result["export_runner_sha256"] = manifest["export_runner_sha256"]
        result["executable_binding"] = executable_binding
    return result


def _mac_release_tool():
    path = ROOT / "tools/release/macos_reference_receipt.py"
    spec = importlib.util.spec_from_file_location("nk3_package_macos_release", path)
    if spec is None or spec.loader is None:
        raise ValueError("Mac native receipt tool is unavailable")
    release = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(release)
    return release


def _checked_macos_export(report_path: Path, bundle: Path, pair: dict, runner_sha256: str) -> dict:
    """Re-read the checked export report and its bounded log, including both plugin callbacks."""
    binder = _pair_binder()
    report_path = binder._path(report_path)
    bundle = binder._path(bundle, directory=True)
    before = binder._snapshot(report_path, binder.MAX_JSON)
    report = binder._json(report_path)
    markers = [f"OPENRC_MAC_PAIR_EXPORT_{phase} {pair['editor_sha256']} {pair['export_template_sha256']}"
               for phase in ("BEGIN", "END")]
    if (report.get("format") != "openrc-godot-check v1" or report.get("ok") is not True
            or report.get("complete") is not True or type(report.get("process_exit")) is not int
            or report["process_exit"] != 0 or type(report.get("exit_code")) is not int
            or report["exit_code"] != 0 or report.get("reason") != "passed"
            or report.get("required_text") != markers or report.get("missing_required_text") != []
            or not isinstance(report.get("counts"), dict) or type(report["counts"].get("error")) is not int
            or report["counts"]["error"] != 0
            or report.get("report") != str(report_path)):
        raise ValueError("Checked Mac export report is incomplete or did not pass both pair markers")
    log = binder._path(report.get("log"))
    if log.parent != report_path.parent or log.name != "engine.log":
        raise ValueError("Checked Mac export log is outside the report directory")
    log_before = binder._snapshot(log, 16 * 1024 * 1024)
    if log_before[1] != report.get("log_sha256") or type(report.get("log_bytes")) is not int \
            or report["log_bytes"] != log_before[0][3]:
        raise ValueError("Checked Mac export log identity differs")
    runner_path = binder._path(ROOT / "tools/godot/run_checked.py")
    runner_before = binder._snapshot(runner_path, binder.MAX_PATCH)
    if runner_before[1] != runner_sha256:
        raise ValueError("Checked export log inspector differs from package preparation")
    spec = importlib.util.spec_from_file_location("nk3_package_checked_export_runner", runner_path)
    if spec is None or spec.loader is None:
        raise ValueError("Checked export log inspector is unavailable")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    inspected = runner.inspect_log(log, markers, max_chars=16 * 1024 * 1024)
    lines = [runner.ANSI.sub("", line) for line in log.read_text(encoding="utf-8", errors="replace").splitlines()]
    if inspected["counts"] != report["counts"] or inspected["counts"]["error"] != 0 \
            or inspected["missing_required_text"] or any(lines.count(marker) != 1 for marker in markers) \
            or lines.index(markers[0]) >= lines.index(markers[1]):
        raise ValueError("Checked Mac export log has errors or lacks ordered pair callbacks")
    command = report.get("command")
    if not isinstance(command, list) or any(not isinstance(arg, str) or not arg for arg in command) \
            or not command or command.count("--export-release") != 1 or command.count("--path") != 1 \
            or any(flag in command for flag in ("--script", "-s", "--export-debug", "--export-pack", "--export-patch")):
        raise ValueError("Checked process is not one explicit release export")
    index, project_index = command.index("--export-release"), command.index("--path")
    if index + 3 != len(command) or project_index + 1 >= index or not command[index + 1] \
            or not Path(command[index + 2]).is_absolute() \
            or not Path(command[project_index + 1]).is_absolute() \
            or binder._path(command[index + 2], directory=True) != bundle \
            or binder._path(command[project_index + 1], directory=True) != binder._path(ROOT / "app", directory=True):
        raise ValueError("Checked export names a different project or bundle")
    editor = binder._path(command[0])
    editor_before = binder._snapshot(editor, binder.MAX_BINARY)
    if editor_before[1] != pair["editor_sha256"]:
        raise ValueError("Checked export used a different editor")
    if binder._snapshot(report_path, binder.MAX_JSON) != before \
            or binder._snapshot(log, 16 * 1024 * 1024) != log_before \
            or binder._snapshot(editor, binder.MAX_BINARY) != editor_before \
            or binder._snapshot(runner_path, binder.MAX_PATCH) != runner_before:
        raise ValueError("Checked export evidence changed during validation")
    return {"report_sha256": before[1], "log_sha256": log_before[1], "editor_sha256": editor_before[1]}


def finalize_research_macos(bundle: Path, tool_root: Path, godot: Path, research_engine: dict | None,
                            toolchain_profile: str | None = None, *, pair_selection: dict | None = None,
                            checked_export_report: Path | None = None) -> dict:
    """Bracket the existing native receipt producer with exact pair/bundle revalidation."""
    if research_engine is None or pair_selection is None or checked_export_report is None:
        raise ValueError("Research finalization requires an explicit editor, pair and checked export report")
    before = verify_macos_export(bundle, tool_root, godot, research_engine, toolchain_profile,
                                 pair_selection=pair_selection)
    checked = _checked_macos_export(checked_export_report, bundle, before["engine_pair"],
                                    before["export_runner_sha256"])
    release = _mac_release_tool()
    destination = bundle.with_name(bundle.name + release.NATIVE_SUFFIX)
    if destination.exists() or destination.is_symlink():
        raise FileExistsError(f"Native receipt already exists: {destination}")
    created = release.create_native(bundle, MAC_MANIFEST)
    if created != destination or created.is_symlink() or not created.is_file():
        raise ValueError("Native receipt producer returned an unexpected path")
    identity = created.stat()
    digest = sha(created)
    try:
        after = verify_macos_export(bundle, tool_root, godot, research_engine, toolchain_profile,
                                    pair_selection=pair_selection)
        current = created.stat()
        if after != before or _checked_macos_export(checked_export_report, bundle, before["engine_pair"],
                                                    before["export_runner_sha256"]) != checked \
                or created.is_symlink() or not created.is_file() \
                or (current.st_dev, current.st_ino, current.st_size, current.st_mtime_ns) != \
                   (identity.st_dev, identity.st_ino, identity.st_size, identity.st_mtime_ns) \
                or sha(created) != digest:
            raise ValueError("Mac package or native receipt changed during finalization")
    except Exception as error:
        # Remove only the exact newly created regular file, never a replacement.
        if not created.is_symlink() and created.is_file():
            current = created.stat()
            if (current.st_dev, current.st_ino, current.st_size, current.st_mtime_ns) == \
                    (identity.st_dev, identity.st_ino, identity.st_size, identity.st_mtime_ns) \
                    and sha(created) == digest:
                created.unlink()
            else:
                raise ValueError(f"Finalization failed and the changed native receipt was retained: {created}") from error
        elif created.is_symlink():
            raise ValueError(f"Finalization failed and the redirected native receipt was retained: {created}") from error
        raise
    return {"receipt": str(created), "receipt_sha256": digest, "manifest_sha256": before["manifest_sha256"],
            "engine_pair": before["engine_pair"], "executable_binding": before["executable_binding"],
            "checked_export": checked}


class _Once(argparse.Action):
    def __call__(self, parser, namespace, value, option_string=None):
        if getattr(namespace, self.dest, None) is not None:
            parser.error(f"{option_string} may be specified only once")
        setattr(namespace, self.dest, value)


def _add_pair_arguments(parser: argparse.ArgumentParser) -> None:
    group = parser.add_argument_group("paired research-engine inputs")
    for flag in ("template-intake", "receipt", "export-template", "binding-pins"):
        group.add_argument("--pair-" + flag, action=_Once, type=Path)


def _pair_selection_from_args(args: argparse.Namespace, research_engine: dict | None) -> dict | None:
    names = ("pair_template_intake", "pair_receipt", "pair_export_template", "pair_binding_pins")
    values = [getattr(args, name, None) for name in names]
    if research_engine is None and not any(value is not None for value in values):
        return None
    if research_engine is None or any(value is None for value in values):
        raise ValueError("Research engine and all four pair inputs must be supplied together")
    return dict(zip(("template_intake", "pair_receipt", "export_template", "pins"), values))


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
    _mac_builder().engine_policy.add_arguments(mac_prepare)
    _mac_builder().add_toolchain_arguments(mac_prepare)
    _add_pair_arguments(mac_prepare)
    mac_stage = commands.add_parser("stage-macos")
    mac_stage.add_argument("--bundle", type=Path, required=True)
    mac_stage.add_argument("--tool-root", type=Path, required=True)
    mac_stage.add_argument("--godot", type=Path, required=True)
    _mac_builder().engine_policy.add_arguments(mac_stage)
    _mac_builder().add_toolchain_arguments(mac_stage)
    _add_pair_arguments(mac_stage)
    mac_verify = commands.add_parser("verify-macos-export")
    mac_verify.add_argument("--bundle", type=Path, required=True)
    mac_verify.add_argument("--tool-root", type=Path, required=True)
    mac_verify.add_argument("--godot", type=Path, required=True)
    _mac_builder().engine_policy.add_arguments(mac_verify)
    _mac_builder().add_toolchain_arguments(mac_verify)
    _add_pair_arguments(mac_verify)
    mac_final = commands.add_parser("finalize-research-macos")
    mac_final.add_argument("--bundle", type=Path, required=True)
    mac_final.add_argument("--tool-root", type=Path, required=True)
    mac_final.add_argument("--godot", type=Path, required=True)
    mac_final.add_argument("--checked-export-report", type=Path, required=True)
    _mac_builder().engine_policy.add_arguments(mac_final)
    _mac_builder().add_toolchain_arguments(mac_final)
    _add_pair_arguments(mac_final)
    args = parser.parse_args()
    if args.command == "prepare": result = prepare()
    elif args.command == "finalize": result = finalize(args.executable, args.template)
    else:
        selection = _mac_builder().engine_policy.selection_from_args(args)
        pair_selection = _pair_selection_from_args(args, selection)
        if args.command == "prepare-macos":
            result = prepare_macos(args.tool_root, args.godot, selection, args.toolchain_profile,
                                   pair_selection=pair_selection)
        elif args.command == "stage-macos":
            result = stage_macos(args.bundle, args.tool_root, args.godot, selection, args.toolchain_profile,
                                 pair_selection=pair_selection)
        elif args.command == "verify-macos-export":
            result = verify_macos_export(args.bundle, args.tool_root, args.godot, selection, args.toolchain_profile,
                                         pair_selection=pair_selection)
        else:
            result = finalize_research_macos(args.bundle, args.tool_root, args.godot, selection, args.toolchain_profile,
                                             pair_selection=pair_selection, checked_export_report=args.checked_export_report)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
