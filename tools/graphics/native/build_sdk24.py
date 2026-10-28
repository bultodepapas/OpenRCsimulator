#!/usr/bin/env python3
"""Build an isolated Windows/Vulkan AMD SDK 2.4 upscaling candidate.

Reuses the pinned native engine and patch stack. Does not replace the default
SDK 1.1.4 build, its binaries, or the production engine. Frame generation is off.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build as native_build
import sdk24

ROOT = native_build.ROOT
DEFAULT_CACHE = ROOT / ".tools/advanced-rendering-fsr24"
DEFAULT_INTAKE = ROOT / ".tools/advanced-rendering-sdk24-intake"


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
    source, sdk_receipt = sdk24.prepare(intake)
    cache.mkdir(parents=True, exist_ok=True)
    # Reuse verified downloads when available, never the mutable extracted sources.
    specs = (native_build.ARCHIVES[0], native_build.ARCHIVES[2])
    for spec in specs:
        cached = ROOT / ".tools/advanced-rendering" / spec[0]
        target = cache / spec[0]
        if not target.exists() and cached.is_file() and native_build.sha256(cached) == spec[2]:
            shutil.copy2(cached, target)
    engine, nvidia = (native_build.fetch(cache, spec) for spec in specs)
    native_build.apply_engine_patches(engine, cache / specs[0][0])
    for name in ("fsr3.h", "fsr3.cpp"):
        shutil.copy2(HERE / name, engine / "servers/rendering/renderer_rd/effects" / name)
    shutil.copy2(HERE / "fsr3_prepare.glsl", engine / "servers/rendering/renderer_rd/shaders/effects/fsr3_prepare.glsl")
    kit = source / "Kits/FidelityFX"
    headers = engine / "thirdparty/amd-fsr-sdk24"
    # Preserve AMD's relative includes and original bytes.
    shutil.copytree(kit / "api/include", headers / "api/include", dirs_exist_ok=True)
    shutil.copytree(kit / "upscalers/include", headers / "upscalers/include", dirs_exist_ok=True)
    shutil.copytree(nvidia / "include", engine / "thirdparty/streamline/include", dirs_exist_ok=True)
    binaries = engine / "bin"
    binaries.mkdir(exist_ok=True)
    runtime_files = [kit / "signedbin" / name for name in
                     ("amd_fidelityfx_loader_vk.dll", "amd_fidelityfx_upscaler_vk.dll")]
    runtime_files += sorted((nvidia / "bin/x64").glob("*.dll"))
    for source_file in runtime_files:
        shutil.copy2(source_file, binaries / source_file.name)
    runtime = {}
    for source_file in runtime_files:
        expected = native_build.sha256(source_file)
        actual = native_build.sha256(binaries / source_file.name)
        if actual != expected:
            raise RuntimeError(f"Staged runtime hash mismatch: {source_file.name}")
        runtime[source_file.name] = actual
    licenses = binaries / "licenses"
    licenses.mkdir(exist_ok=True)
    for source_file, name in ((engine / "LICENSE.txt", "Godot-LICENSE.txt"),
                              (ROOT / "LICENSE", "OpenRC-LICENSE.txt"),
                              (source / "docs/license.md", "AMD-FSR-SDK-2.4-LICENSE.md"),
                              (kit / "docs/license.md", "AMD-FidelityFX-kit-LICENSE.md"),
                              (source / "3rdpartynotice.md", "AMD-FSR-SDK-2.4-third-party.md"),
                              (nvidia / "license.txt", "Streamline-LICENSE.txt"),
                              (nvidia / "3rd-party-licenses.md", "Streamline-third-party.md")):
        shutil.copy2(source_file, licenses / name)
    for source_file in (nvidia / "bin/x64").glob("*.license.txt"):
        shutil.copy2(source_file, licenses / source_file.name)
    integration = (*native_build.ENGINE_PATCHES, "fsr3.h", "fsr3.cpp", "fsr3_prepare.glsl", "sdk24.py", "build_sdk24.py")
    receipt = {
        "experimental": True, "production_engine_unchanged": "4.8-beta1",
        "godot_repository": "https://github.com/NVIDIA-RTX/godot", "godot_commit": native_build.COMMIT,
        "fidelityfx_sdk": "2.4.0", "fsr_upscaler": "runtime_queried",
        "bundled_upscalers": ["3.1.6", "4.1.2"], "streamline": "2.11.1",
        "platform": "windows", "graphics_api": "vulkan", "frame_generation_enabled": False,
        "sdk_intake": sdk_receipt,
        "sources": {name: digest for name, _, digest, _ in specs},
        "integration": {name: native_build.sha256(HERE / name) for name in integration},
        "amd_headers": {p.relative_to(headers).as_posix(): native_build.sha256(p)
                        for p in sorted(headers.rglob("*")) if p.is_file()},
        "streamline_headers": {p.name: native_build.sha256(p) for p in sorted((nvidia / "include").glob("*.h"))},
        "runtime": runtime,
        "licenses": {p.name: native_build.sha256(p) for p in sorted(licenses.iterdir()) if p.is_file()},
    }
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
    if not args.prepare_only:
        import SCons
        if SCons.__version__ != "4.10.1":
            raise RuntimeError("Install the pinned scons==4.10.1 build tool")
        command = [sys.executable, "-m", "SCons", "platform=windows", f"target={args.target}",
                   "arch=x86_64", "d3d12=no", "angle=no", "accesskit=no", "winrt=no",
                   "use_streamline=yes", "debug_symbols=no", f"-j{args.jobs}"]
        receipt["build_command"] = command
        subprocess.run(command, cwd=engine, check=True)
        executable = engine / "bin" / f"godot.windows.{args.target}.x86_64.exe"
        receipt["executable"] = str(executable)
        receipt["executable_sha256"] = native_build.sha256(executable)
        receipt["version"] = subprocess.check_output([str(executable), "--version"], text=True).strip()
    path = engine / "bin" / ("openrc-sdk24-prepare.json" if args.prepare_only else f"openrc-{args.target}-build.json")
    path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"Receipt: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
