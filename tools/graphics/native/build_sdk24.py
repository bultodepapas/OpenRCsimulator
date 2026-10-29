#!/usr/bin/env python3
"""Build an isolated Windows/Vulkan AMD SDK 2.4 upscaling candidate.

Reuses the pinned native engine and patch stack. Does not replace the default
SDK 1.1.4 build, its binaries, or the production engine. Frame generation is off.
"""
from __future__ import annotations

import argparse
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
import uuid

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build as native_build
import sdk24

ROOT = native_build.ROOT
DEFAULT_CACHE = ROOT / ".tools/advanced-rendering-fsr24"
DEFAULT_INTAKE = ROOT / ".tools/advanced-rendering-sdk24-intake"
SDK24_ENGINE_PATCHES = ("sdk24_vulkan_features.patch",)
ADAPTER_FILES = {
    "fsr3.h": "servers/rendering/renderer_rd/effects/fsr3.h",
    "fsr3.cpp": "servers/rendering/renderer_rd/effects/fsr3.cpp",
    "fsr3_prepare.glsl": "servers/rendering/renderer_rd/shaders/effects/fsr3_prepare.glsl",
}
HEADER_ROOTS = ("thirdparty/amd-fsr-sdk24", "thirdparty/streamline/include")
if (Path(native_build.__file__).resolve() != (HERE / "build.py").resolve() or
        Path(sdk24.__file__).resolve() != (HERE / "sdk24.py").resolve()):
    raise RuntimeError("Native build helpers were imported from an unexpected directory")
IMPORT_IDENTITIES = {
    name: native_build.sha256(path) for name, path in (
        ("build.py", Path(native_build.__file__)),
        ("sdk24.py", Path(sdk24.__file__)),
        ("build_sdk24.py", Path(__file__)),
    )
}


def freeze_integration() -> tuple[dict[str, bytes], dict[str, str]]:
    names = (*native_build.ENGINE_PATCHES, *SDK24_ENGINE_PATCHES, *ADAPTER_FILES, "sdk24.py", "build_sdk24.py", "build.py")
    if len(set(names)) != len(names):
        raise RuntimeError("Duplicate integration source name")
    frozen = {name: (HERE / name).read_bytes() for name in names}
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in frozen.items()}
    if any(hashes[name] != digest for name, digest in IMPORT_IDENTITIES.items()):
        raise RuntimeError("A build helper changed after import; restart preparation")
    return frozen, hashes


def verify_integration(expected: dict[str, str]) -> None:
    for name, digest in expected.items():
        path = HERE / name
        if not path.is_file() or native_build.sha256(path) != digest:
            raise RuntimeError(f"Integration source changed during preparation or build: {name}")


def patched_paths(frozen: dict[str, bytes]) -> set[str]:
    paths = set()
    for name in (*native_build.ENGINE_PATCHES, *SDK24_ENGINE_PATCHES):
        text = frozen[name].decode("utf-8").replace("\r\n", "\n")
        for path in re.findall(r"^\+\+\+ b/(.+)$", text, re.MULTILINE):
            if Path(path).is_absolute() or ".." in Path(path).parts or "\\" in path or ":" in path:
                raise RuntimeError(f"Unsafe engine patch path: {path}")
            paths.add(path)
    return paths


def apply_frozen_engine_patches(engine: Path, archive: Path, snapshot: Path) -> None:
    # Load a private copy so build.apply_engine_patches reads the frozen patches
    # without changing the imported build module or another caller's globals.
    spec = importlib.util.spec_from_file_location("openrc_frozen_native_build", snapshot / "build.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load frozen native build helper")
    frozen_build = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(frozen_build)
    if (frozen_build.COMMIT != native_build.COMMIT or
            tuple(frozen_build.ENGINE_PATCHES) != tuple(native_build.ENGINE_PATCHES)):
        raise RuntimeError("Native build helper changed after import; restart preparation")
    frozen_build.ENGINE_PATCHES = (*frozen_build.ENGINE_PATCHES, *SDK24_ENGINE_PATCHES)
    frozen_build.apply_engine_patches(engine, archive)


def sdk_pin(receipt: dict, path: str) -> str:
    try:
        digest = receipt["pinned_files"][path]["sha256"]
    except (KeyError, TypeError) as error:
        raise RuntimeError(f"SDK intake receipt lacks a file pin: {path}") from error
    if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise RuntimeError(f"Invalid SDK intake file pin: {path}")
    return digest


def verify_file(path: Path, expected: str, label: str) -> None:
    if not path.is_file() or native_build.sha256(path) != expected:
        raise RuntimeError(f"{label} hash mismatch: {path}")


def verify_copied_tree(source: Path, destination: Path, *, sdk_root: Path | None = None,
                       sdk_receipt: dict | None = None) -> set[str]:
    sources = {p.relative_to(source).as_posix(): p for p in source.rglob("*") if p.is_file()}
    staged = {p.relative_to(destination).as_posix(): p for p in destination.rglob("*") if p.is_file()}
    if sdk_root is not None and sdk_receipt is not None:
        prefix = source.relative_to(sdk_root).as_posix() + "/"
        expected_names = {name.removeprefix(prefix) for name in sdk_receipt["pinned_files"] if name.startswith(prefix)}
        if not expected_names or set(sources) != expected_names:
            raise RuntimeError(f"SDK header tree no longer matches intake receipt: {source}")
    if set(sources) != set(staged):
        raise RuntimeError(f"Staged header tree differs from source: {destination}")
    for rel, src in sources.items():
        expected = (sdk_pin(sdk_receipt, src.relative_to(sdk_root).as_posix())
                    if sdk_root is not None and sdk_receipt is not None else native_build.sha256(src))
        verify_file(staged[rel], expected, "Staged header")
    return set(staged)


def preserve_previous_receipts(engine: Path) -> None:
    # A failed or interrupted rebuild must not leave an old receipt beside a
    # modified executable. Preserve each previous receipt as evidence first.
    names = ("openrc-sdk24-prepare.json", "openrc-editor-build.json",
             "openrc-template_debug-build.json", "openrc-template_release-build.json")
    for name in names:
        previous = engine / "bin" / name
        if previous.exists():
            if not previous.is_file() or previous.is_symlink():
                raise RuntimeError(f"Unsafe existing build receipt: {previous}")
            archive = ROOT / "tmp/fsr-sdk24-build-receipts"
            archive.mkdir(parents=True, exist_ok=True)
            saved = archive / f"{previous.stem}-{uuid.uuid4().hex}.json"
            previous.rename(saved)
            print(f"Preserved previous receipt: {saved}", flush=True)


def verify_build_inputs(engine: Path, receipt: dict) -> None:
    verify_integration(receipt["integration"])
    for rel, digest in receipt["engine_source"].items():
        verify_file(engine / rel, digest, "Engine source")
    for prefix in HEADER_ROOTS:
        expected = {name for name in receipt["engine_source"] if name.startswith(prefix + "/")}
        directory = engine / prefix
        actual = {p.relative_to(engine).as_posix() for p in directory.rglob("*") if p.is_file()}
        if actual != expected:
            raise RuntimeError(f"Staged header tree changed during preparation or build: {directory}")
    for name, digest in receipt["runtime"].items():
        verify_file(engine / "bin" / name, digest, "Staged runtime")
    for name, digest in receipt["licenses"].items():
        verify_file(engine / "bin/licenses" / name, digest, "Staged license or notice")


def write_receipt(path: Path, receipt: dict) -> None:
    """Publish only a complete receipt, without replacing another process's file."""
    handle, temporary_name = tempfile.mkstemp(prefix="sdk24-receipt-", suffix=".tmp", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(handle, "w", encoding="utf-8", newline="\n") as output:
            json.dump(receipt, output, indent=2)
            output.write("\n")
        os.link(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def validate_cache(cache: Path) -> Path:
    cache = cache.resolve()
    baseline = (ROOT / ".tools/advanced-rendering").resolve()
    if cache == baseline or cache.is_relative_to(baseline) or baseline.is_relative_to(cache):
        raise ValueError("SDK 2.4 requires a cache separate from the existing native engine")
    return cache


def prepare(cache: Path, intake: Path) -> tuple[Path, dict]:
    cache = validate_cache(cache)
    intake = intake.resolve()
    if cache == intake or cache.is_relative_to(intake) or intake.is_relative_to(cache):
        raise ValueError("Engine cache and immutable SDK intake must not overlap")
    frozen, integration = freeze_integration()
    source, sdk_receipt = sdk24.prepare(intake)
    cache.mkdir(parents=True, exist_ok=True)
    # Reuse verified downloads when available, never the mutable extracted sources.
    specs = (native_build.ARCHIVES[0], native_build.ARCHIVES[2])
    engine_hint = cache / specs[0][3]
    preserve_previous_receipts(engine_hint)
    for spec in specs:
        cached = ROOT / ".tools/advanced-rendering" / spec[0]
        target = cache / spec[0]
        if not target.exists() and cached.is_file() and native_build.sha256(cached) == spec[2]:
            shutil.copy2(cached, target)
    engine, nvidia = (native_build.fetch(cache, spec) for spec in specs)
    if engine.resolve() != engine_hint.resolve():
        raise RuntimeError("Unexpected extracted engine location")
    with tempfile.TemporaryDirectory(prefix="sdk24-integration-", dir=cache) as temporary:
        snapshot = Path(temporary)
        for name, data in frozen.items():
            (snapshot / name).write_bytes(data)
        apply_frozen_engine_patches(engine, cache / specs[0][0], snapshot)
        for name, target in ADAPTER_FILES.items():
            shutil.copy2(snapshot / name, engine / target)
            verify_file(engine / target, integration[name], "Staged integration source")
    kit = source / "Kits/FidelityFX"
    headers = engine / "thirdparty/amd-fsr-sdk24"
    # Preserve AMD's relative includes and original bytes.
    shutil.copytree(kit / "api/include", headers / "api/include", dirs_exist_ok=True)
    shutil.copytree(kit / "upscalers/include", headers / "upscalers/include", dirs_exist_ok=True)
    streamline_headers = engine / "thirdparty/streamline/include"
    shutil.copytree(nvidia / "include", streamline_headers, dirs_exist_ok=True)
    api_names = verify_copied_tree(kit / "api/include", headers / "api/include", sdk_root=source, sdk_receipt=sdk_receipt)
    upscaler_names = verify_copied_tree(kit / "upscalers/include", headers / "upscalers/include", sdk_root=source, sdk_receipt=sdk_receipt)
    expected_headers = {f"api/include/{name}" for name in api_names} | {f"upscalers/include/{name}" for name in upscaler_names}
    actual_headers = {p.relative_to(headers).as_posix() for p in headers.rglob("*") if p.is_file()}
    if actual_headers != expected_headers:
        raise RuntimeError(f"Staged SDK header tree contains unexpected files: {headers}")
    verify_copied_tree(nvidia / "include", streamline_headers)
    binaries = engine / "bin"
    binaries.mkdir(exist_ok=True)
    runtime_files = [kit / "signedbin" / name for name in
                     ("amd_fidelityfx_loader_vk.dll", "amd_fidelityfx_upscaler_vk.dll")]
    runtime_files += sorted((nvidia / "bin/x64").glob("*.dll"))
    for source_file in runtime_files:
        shutil.copy2(source_file, binaries / source_file.name)
    runtime = {}
    for source_file in runtime_files:
        expected = (sdk_pin(sdk_receipt, source_file.relative_to(source).as_posix())
                    if source_file.is_relative_to(source) else native_build.sha256(source_file))
        verify_file(binaries / source_file.name, expected, "Staged runtime")
        runtime[source_file.name] = expected
    licenses = binaries / "licenses"
    licenses.mkdir(exist_ok=True)
    license_files = [(engine / "LICENSE.txt", "Godot-LICENSE.txt"),
                     (ROOT / "LICENSE", "OpenRC-LICENSE.txt"),
                     (source / "docs/license.md", "AMD-FSR-SDK-2.4-LICENSE.md"),
                     (kit / "docs/license.md", "AMD-FidelityFX-kit-LICENSE.md"),
                     (source / "3rdpartynotice.md", "AMD-FSR-SDK-2.4-third-party.md"),
                     (nvidia / "license.txt", "Streamline-LICENSE.txt"),
                     (nvidia / "3rd-party-licenses.md", "Streamline-third-party.md")]
    license_files += [(p, p.name) for p in (nvidia / "bin/x64").glob("*.license.txt")]
    for source_file, name in license_files:
        shutil.copy2(source_file, licenses / name)
        expected = (sdk_pin(sdk_receipt, source_file.relative_to(source).as_posix())
                    if source_file.is_relative_to(source) else native_build.sha256(source_file))
        verify_file(licenses / name, expected, "Staged license or notice")
    engine_paths = patched_paths(frozen) | set(ADAPTER_FILES.values())
    for directory in (headers, streamline_headers):
        engine_paths.update(p.relative_to(engine).as_posix() for p in directory.rglob("*") if p.is_file())
    engine_source = {rel: native_build.sha256(engine / rel) for rel in sorted(engine_paths)}
    receipt = {
        "experimental": True, "production_engine_unchanged": "4.8-beta1",
        "godot_repository": "https://github.com/NVIDIA-RTX/godot", "godot_commit": native_build.COMMIT,
        "fidelityfx_sdk": "2.4.0", "fsr_upscaler": "runtime_queried",
        "bundled_upscalers": ["3.1.6", "4.1.2"], "streamline": "2.11.1",
        "platform": "windows", "graphics_api": "vulkan", "frame_generation_enabled": False,
        "sdk_intake": sdk_receipt,
        "sources": {name: digest for name, _, digest, _ in specs},
        "integration": integration,
        "engine_source": engine_source,
        "amd_headers": {p.relative_to(headers).as_posix(): native_build.sha256(p)
                        for p in sorted(headers.rglob("*")) if p.is_file()},
        "streamline_headers": {p.name: native_build.sha256(p) for p in sorted((nvidia / "include").glob("*.h"))},
        "runtime": runtime,
        "licenses": {p.name: native_build.sha256(p) for p in sorted(licenses.iterdir()) if p.is_file()},
    }
    verify_build_inputs(engine, receipt)
    return engine, receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--intake", type=Path, default=DEFAULT_INTAKE)
    parser.add_argument("--target", choices=("editor", "template_debug", "template_release"), default="editor")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    if os.name != "nt" or args.jobs < 1:
        parser.error("Windows and a positive job count are required")
    engine, receipt = prepare(args.cache, args.intake)
    verify_build_inputs(engine, receipt)
    if not args.prepare_only:
        import SCons
        if SCons.__version__ != "4.10.1":
            raise RuntimeError("Install the pinned scons==4.10.1 build tool")
        command = [sys.executable, "-m", "SCons", "platform=windows", f"target={args.target}",
                   "arch=x86_64", "d3d12=no", "angle=no", "accesskit=no", "winrt=no",
                   "use_streamline=yes", "debug_symbols=no", f"-j{args.jobs}"]
        receipt["build_command"] = command
        subprocess.run(command, cwd=engine, check=True)
        verify_build_inputs(engine, receipt)
        executable = engine / "bin" / f"godot.windows.{args.target}.x86_64.exe"
        receipt["executable"] = str(executable)
        receipt["executable_sha256"] = native_build.sha256(executable)
        receipt["version"] = subprocess.check_output([str(executable), "--version"], text=True).strip()
        verify_file(executable, receipt["executable_sha256"], "Built executable")
        verify_build_inputs(engine, receipt)
    path = engine / "bin" / ("openrc-sdk24-prepare.json" if args.prepare_only else f"openrc-{args.target}-build.json")
    write_receipt(path, receipt)
    print(f"Receipt: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
