#!/usr/bin/env python3
"""Reproducible, opt-in Windows/Vulkan DLSS + FSR 3.1 engine experiment (VQ-07d).

Does not change the production engine pin or install export templates globally.
Requires Python 3.11+, SCons 4.10.1, Git and Visual Studio C++ build tools.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
COMMIT = "135dff3887a3d2ccf45cafbd9bdffa7b718e1e76"
ARCHIVES = (
    ("godot-nvidia.zip", f"https://codeload.github.com/NVIDIA-RTX/godot/zip/{COMMIT}",
     "8f9d9604270ccca92d14cc57afca142079476cbe050e0486a90b84da17ce907a", f"godot-{COMMIT}"),
    ("fidelityfx-1.1.4.zip", "https://codeload.github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/zip/refs/tags/v1.1.4",
     "9a19e1f20bf269163f052186ed563209c5a1d0f7b1cf7e567e643dee6cc61179", "FidelityFX-SDK-1.1.4"),
    ("streamline-2.11.1.zip", "https://github.com/NVIDIA-RTX/Streamline/releases/download/v2.11.1/streamline-sdk-v2.11.1.zip",
     "0c1d562e59557434cabfb8997157cb8c04fc7d23f077c8bdf5260975b73dfb89", "streamline-2.11.1"),
)


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def fetch(cache: Path, spec: tuple[str, str, str, str]) -> Path:
    name, url, expected, directory = spec
    archive = cache / name
    if not archive.is_file():
        temporary = archive.with_suffix(".download")
        print(f"Downloading {url}", flush=True)
        urllib.request.urlretrieve(url, temporary)
        if sha256(temporary) != expected:
            raise RuntimeError(f"SHA-256 mismatch: {temporary}")
        temporary.replace(archive)
    if sha256(archive) != expected:
        raise RuntimeError(f"SHA-256 mismatch: {archive}")
    destination = cache / directory
    stamp = cache / (name + ".extracted")
    if not stamp.is_file():
        # Streamline ships files at the ZIP root, unlike GitHub source archives.
        extraction_root = destination if name.startswith("streamline") else cache
        with zipfile.ZipFile(archive) as package:
            for member in package.infolist():
                resolved = (extraction_root / member.filename).resolve()
                if not resolved.is_relative_to(extraction_root.resolve()):
                    raise RuntimeError(f"Unsafe archive member: {member.filename}")
            package.extractall(extraction_root)
        stamp.write_text(expected + "\n", encoding="utf-8")
    return destination


def prepare(cache: Path, jobs: int = 4, prepare_only: bool = False) -> tuple[Path, dict]:
    cache.mkdir(parents=True, exist_ok=True)
    engine, amd, nvidia = (fetch(cache, spec) for spec in ARCHIVES)
    # Only accept the pristine pinned tree or this exact patch already applied.
    common = ["git", "apply"]
    patch_env = dict(os.environ, GIT_CEILING_DIRECTORIES=str(engine.parent))
    for patch_name in ("engine.patch", "vulkan_validation.patch", "dlss_validation.patch", "shutdown_thread.patch", "load_token_lifetime.patch", "reflection_atlas_lifetime.patch", "buffer_write_sync.patch", "dlss_frame_lifecycle.patch"):
        patch = HERE / patch_name
        check = subprocess.run(common + ["--check", str(patch)], cwd=engine, env=patch_env, capture_output=True)
        if check.returncode == 0:
            subprocess.run(common + [str(patch)], cwd=engine, env=patch_env, check=True)
        else:
            reverse = subprocess.run(common + ["--reverse", "--check", str(patch)], cwd=engine, env=patch_env, capture_output=True)
            if reverse.returncode:
                raise RuntimeError(f"Engine sources do not match {patch_name}; use a new --cache directory.\n" + check.stderr.decode(errors="replace"))
    for name in ("fsr3.h", "fsr3.cpp"):
        shutil.copy2(HERE / name, engine / "servers/rendering/renderer_rd/effects" / name)
    shutil.copy2(HERE / "fsr3_prepare.glsl", engine / "servers/rendering/renderer_rd/shaders/effects/fsr3_prepare.glsl")
    shutil.copytree(amd / "ffx-api/include/ffx_api", engine / "thirdparty/amd-fsr3/ffx_api", dirs_exist_ok=True)
    # The SDK handshake and public structures must match the shipped runtime.
    shutil.copytree(nvidia / "include", engine / "thirdparty/streamline/include", dirs_exist_ok=True)
    binaries = engine / "bin"
    binaries.mkdir(exist_ok=True)
    from build_fidelityfx import apply_fidelityfx_patch, build_runtime
    if prepare_only:
        fidelityfx_receipt = {"built": False, "patch_sha256": apply_fidelityfx_patch(amd)}
        runtime_files = []
    else:
        amd_runtime, fidelityfx_receipt = build_runtime(cache, min(jobs, 4))
        runtime_files = [amd_runtime]
    runtime_files += sorted((nvidia / "bin/x64").glob("*.dll"))
    for source in runtime_files:
        shutil.copy2(source, binaries / source.name)
    licenses = binaries / "licenses"
    licenses.mkdir(exist_ok=True)
    shutil.copy2(engine / "LICENSE.txt", licenses / "Godot-LICENSE.txt")
    shutil.copy2(ROOT / "LICENSE", licenses / "OpenRC-LICENSE.txt")
    shutil.copy2(amd / "LICENSE.txt", licenses / "FidelityFX-LICENSE.txt")
    shutil.copy2(nvidia / "license.txt", licenses / "Streamline-LICENSE.txt")
    shutil.copy2(nvidia / "3rd-party-licenses.md", licenses / "Streamline-third-party.md")
    for source in (nvidia / "bin/x64").glob("*.license.txt"):
        shutil.copy2(source, licenses / source.name)
    receipt = {
        "experimental": True, "production_engine_unchanged": "4.7.2-stable",
        "godot_repository": "https://github.com/NVIDIA-RTX/godot", "godot_commit": COMMIT,
        "fidelityfx_sdk": "1.1.4", "fsr_upscaler": "3.1.4", "streamline": "2.11.1",
        "platform": "windows", "graphics_api": "vulkan", "frame_generation_enabled": False,
        "sources": {name: digest for name, _, digest, _ in ARCHIVES},
        "integration": {name: sha256(HERE / name) for name in ("engine.patch", "vulkan_validation.patch", "dlss_validation.patch", "shutdown_thread.patch", "load_token_lifetime.patch", "reflection_atlas_lifetime.patch", "buffer_write_sync.patch", "dlss_frame_lifecycle.patch", "fidelityfx.patch", "build_fidelityfx.py", "fsr3.h", "fsr3.cpp", "fsr3_prepare.glsl")},
        "streamline_headers": {source.name: sha256(source) for source in sorted((nvidia / "include").glob("*.h"))},
        "fidelityfx_runtime_build": fidelityfx_receipt,
        "runtime": {source.name: sha256(source) for source in runtime_files},
    }
    return engine, receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / ".tools/advanced-rendering")
    parser.add_argument("--target", choices=("editor", "template_debug", "template_release"), default="editor")
    parser.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("This experimental runtime package currently targets Windows/Vulkan.")
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    engine, receipt = prepare(args.cache.resolve(), args.jobs, args.prepare_only)
    if not args.prepare_only:
        import SCons
        if SCons.__version__ != "4.10.1":
            raise RuntimeError("Install the pinned build tool: python -m pip install scons==4.10.1")
        command = [sys.executable, "-m", "SCons", "platform=windows", f"target={args.target}",
                   "arch=x86_64", "d3d12=no", "angle=no", "accesskit=no", "winrt=no",
                   "use_streamline=yes", "debug_symbols=no", f"-j{args.jobs}"]
        receipt["build_command"] = command
        print("Building " + str(engine), flush=True)
        subprocess.run(command, cwd=engine, check=True)
        executable = engine / "bin" / f"godot.windows.{args.target}.x86_64.exe"
        receipt["executable"] = str(executable)
        receipt["executable_sha256"] = sha256(executable)
        receipt["version"] = subprocess.check_output([str(executable), "--version"], text=True).strip()
    receipt_path = engine / "bin" / ("openrc-prepare.json" if args.prepare_only else f"openrc-{args.target}-build.json")
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"Receipt: {receipt_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
