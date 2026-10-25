#!/usr/bin/env python3
"""Build the pinned, Vulkan-only FidelityFX runtime used by the native trial."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SDK_ARCHIVE = "fidelityfx-1.1.4.zip"
SDK_SHA256 = "9a19e1f20bf269163f052186ed563209c5a1d0f7b1cf7e567e643dee6cc61179"
ENGINE_DIR = "godot-135dff3887a3d2ccf45cafbd9bdffa7b718e1e76"
GENERATOR = "Visual Studio 18 2026"


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(command: list[str], *, env: dict[str, str] | None = None, capture: bool = False) -> str:
    result = subprocess.run(command, env=env, check=True, text=True,
                            capture_output=capture)
    return result.stdout.strip() if capture else ""


def verify_source(cache: Path, sdk: Path) -> dict:
    archive = cache / SDK_ARCHIVE
    stamp = cache / (SDK_ARCHIVE + ".extracted")
    if not archive.is_file() or sha256(archive) != SDK_SHA256:
        raise RuntimeError(f"Missing or unpinned FidelityFX source archive: {archive}")
    if not stamp.is_file() or stamp.read_text(encoding="utf-8").strip() != SDK_SHA256:
        raise RuntimeError(f"Missing or stale extraction receipt: {stamp}")
    if not (sdk / "ffx-api/CMakeLists.txt").is_file():
        raise RuntimeError(f"Pinned FidelityFX tree is incomplete: {sdk}")
    return {"archive": SDK_ARCHIVE, "archive_sha256": SDK_SHA256,
            "sdk_version": "1.1.4", "fsr3_upscaler": "3.1.4"}


def apply_fidelityfx_patch(sdk: Path) -> str:
    git = shutil.which("git")
    if not git:
        raise RuntimeError("Git is required to apply the pinned FidelityFX patch")
    patch = HERE / "fidelityfx.patch"
    patch_env = dict(os.environ, GIT_CEILING_DIRECTORIES=str(sdk.parent))
    check = subprocess.run([git, "apply", "--check", str(patch)], cwd=sdk,
                           env=patch_env, capture_output=True)
    if check.returncode == 0:
        subprocess.run([git, "apply", str(patch)], cwd=sdk, env=patch_env, check=True)
    else:
        reverse = subprocess.run([git, "apply", "--reverse", "--check", str(patch)],
                                 cwd=sdk, env=patch_env, capture_output=True)
        if reverse.returncode:
            reason = check.stderr.decode(errors="replace")
            raise RuntimeError("FidelityFX source does not match the pinned patch; use a fresh SDK extract.\n" + reason)
    shader = (sdk / "sdk/include/FidelityFX/gpu/fsr3upscaler/ffx_fsr3upscaler_callbacks_glsl.h").read_text(encoding="utf-8")
    backend = (sdk / "sdk/src/backends/vk/ffx_vk.cpp").read_text(encoding="utf-8")
    if "binding = FSR3UPSCALER_BIND_UAV_LUMA_HISTORY, rgba16f)" not in shader:
        raise RuntimeError("FSR3 luma-history shader fix did not land")
    if "range.aspectMask |= VK_IMAGE_ASPECT_STENCIL_BIT;" not in backend:
        raise RuntimeError("FSR3 stencil barrier fix did not land")
    return sha256(patch)


def find_visual_studio() -> tuple[Path, Path, str]:
    vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Microsoft Visual Studio/Installer/vswhere.exe"
    if not vswhere.is_file():
        raise RuntimeError("Visual Studio 2026 and vswhere.exe are required")
    install = run([str(vswhere), "-latest", "-products", "*", "-property", "installationPath"], capture=True)
    version = run([str(vswhere), "-latest", "-products", "*", "-property", "installationVersion"], capture=True)
    tools = Path(install) / "VC/Tools/MSVC"
    toolsets = sorted((path for path in tools.iterdir() if path.is_dir()),
                      key=lambda path: tuple(int(part) for part in re.findall(r"\d+", path.name)),
                      reverse=True)
    lib = next((path / "bin/Hostx64/x64/lib.exe" for path in toolsets
                if (path / "bin/Hostx64/x64/lib.exe").is_file()), None)
    if not lib:
        raise RuntimeError("Visual Studio's x64 MSVC librarian was not found")
    return vswhere, lib, version


def make_vulkan_import_library(cache: Path, build_dir: Path) -> dict:
    loader = Path(os.environ.get("WINDIR", r"C:\Windows")) / "System32/vulkan-1.dll"
    engine_headers = cache / ENGINE_DIR / "thirdparty/vulkan/include"
    core_header = engine_headers / "vulkan/vulkan_core.h"
    if not loader.is_file() or not core_header.is_file():
        raise RuntimeError("Need the system Vulkan loader and pinned engine Vulkan headers")
    header_text = core_header.read_text(encoding="utf-8", errors="replace")
    version = re.search(r"VK_HEADER_VERSION_COMPLETE\s+VK_MAKE_API_VERSION\(0,\s*(\d+),\s*(\d+),\s*VK_HEADER_VERSION\)", header_text)
    header_revision = re.search(r"#define\s+VK_HEADER_VERSION\s+(\d+)", header_text)
    if (not version or not header_revision or
            (int(version.group(1)), int(version.group(2)), int(header_revision.group(1))) < (1, 3, 250)):
        raise RuntimeError("Pinned Vulkan headers do not meet FidelityFX's Vulkan 1.3.250 minimum")

    readobj = shutil.which("llvm-readobj")
    if not readobj:
        raise RuntimeError("llvm-readobj is required to read the installed Vulkan loader exports")
    _, librarian, visual_studio_version = find_visual_studio()
    exports_text = run([readobj, "--coff-exports", str(loader)], capture=True)
    exports = sorted(set(re.findall(r"^\s+Name: ([^\r\n]+)$", exports_text, re.MULTILINE)))
    required = {"vkGetInstanceProcAddr", "vkEnumerateDeviceExtensionProperties",
                "vkGetPhysicalDeviceMemoryProperties"}
    if len(exports) < 100 or not required.issubset(exports):
        raise RuntimeError("The installed Vulkan loader export table is incomplete")

    build_dir.mkdir(parents=True, exist_ok=True)
    definition = build_dir / "vulkan-1.def"
    import_library = build_dir / "vulkan-1.lib"
    definition_text = "LIBRARY vulkan-1.dll\nEXPORTS\n" + "".join(f"  {name}\n" for name in exports)
    if not definition.is_file() or definition.read_text(encoding="ascii") != definition_text:
        definition.write_text(definition_text, encoding="ascii")
    identity = {"loader": sha256(loader), "librarian": sha256(librarian), "definition": sha256(definition)}
    import_receipt_path = build_dir / "vulkan-import-receipt.json"
    previous = json.loads(import_receipt_path.read_text(encoding="utf-8")) if import_receipt_path.is_file() else {}
    if not import_library.is_file() or previous.get("inputs") != identity or previous.get("sha256") != sha256(import_library):
        run([str(librarian), "/nologo", f"/def:{definition}", "/machine:x64", f"/out:{import_library}"])
        import_receipt_path.write_text(json.dumps({"inputs": identity, "sha256": sha256(import_library)}, indent=2) + "\n", encoding="utf-8")
    if not import_library.is_file():
        raise RuntimeError("MSVC did not create the Vulkan import library")
    version_info = run(["powershell", "-NoProfile", "-Command",
                        f"(Get-Item -LiteralPath '{str(loader).replace(chr(39), chr(39) * 2)}').VersionInfo.FileVersion"], capture=True)
    return {"loader": str(loader), "loader_file_version": version_info,
            "loader_sha256": sha256(loader), "headers": str(engine_headers),
            "vulkan_headers_version": f"{version.group(1)}.{version.group(2)}.{header_revision.group(1)}",
            "vulkan_core_header_sha256": sha256(core_header),
            "import_library": str(import_library), "import_library_sha256": sha256(import_library),
            "msvc_librarian": str(librarian), "msvc_librarian_sha256": sha256(librarian),
            "visual_studio_version": visual_studio_version,
            "export_count": len(exports), "llvm_readobj": run([readobj, "--version"], capture=True)}


def build_runtime(cache: Path, jobs: int = 4) -> tuple[Path, dict]:
    if os.name != "nt":
        raise RuntimeError("The FidelityFX API build currently targets Windows/Vulkan")
    if not 1 <= jobs <= 4:
        raise ValueError("jobs must be between 1 and 4")
    cache = cache.resolve()
    sdk = cache / "FidelityFX-SDK-1.1.4"
    source = verify_source(cache, sdk)
    patch_hash = apply_fidelityfx_patch(sdk)
    build_dir = cache / "fidelityfx-native-build"
    cmake = shutil.which("cmake")
    if not cmake:
        raise RuntimeError("CMake 3.23 or newer is required")
    cmake_version = run([cmake, "--version"], capture=True).splitlines()[0]
    match = re.search(r"([0-9]+)\.([0-9]+)\.([0-9]+)", cmake_version)
    if not match or tuple(map(int, match.groups())) < (3, 23, 0):
        raise RuntimeError(f"CMake 3.23 or newer is required; found {cmake_version}")
    help_text = run([cmake, "--help"], capture=True)
    if GENERATOR not in help_text:
        raise RuntimeError(f"Installed CMake does not support the {GENERATOR} generator")

    vulkan = make_vulkan_import_library(cache, build_dir)
    compiler_dir = sdk / "sdk/tools/binary_store"
    ffx_sc = compiler_dir / "FidelityFX_SC.exe"
    glslang = compiler_dir / "glslangValidator.exe"
    if not ffx_sc.is_file() or not glslang.is_file():
        raise RuntimeError("Pinned FidelityFX shader compiler assets are missing")
    build_env = dict(os.environ)
    build_env["PATH"] = str(compiler_dir) + os.pathsep + build_env.get("PATH", "")

    cmake_build = build_dir / "cmake"
    configure = [cmake, "-S", str(sdk / "ffx-api"), "-B", str(cmake_build),
                 "-G", GENERATOR, "-A", "x64", "-DFFX_API_BACKEND=VK_X64",
                 f"-DVulkan_INCLUDE_DIR={vulkan['headers']}",
                 f"-DVulkan_LIBRARY={vulkan['import_library']}"]
    print("Configuring pinned FidelityFX Vulkan runtime", flush=True)
    run(configure, env=build_env)
    print(f"Building amd_fidelityfx_vk with {jobs} jobs", flush=True)
    run([cmake, "--build", str(cmake_build), "--config", "Release",
         "--target", "amd_fidelityfx_vk", "--parallel", str(jobs)], env=build_env)

    dll = sdk / "ffx-api/bin/amd_fidelityfx_vk.dll"
    if not dll.is_file():
        raise RuntimeError(f"Build completed without the expected runtime DLL: {dll}")
    toolchain = {"cmake": cmake_version, "generator": GENERATOR,
                 "visual_studio_version": vulkan["visual_studio_version"],
                 "cmake_sdk_documented_range": "3.23-3.30; current version is recorded above",
                 "configuration": "Release", "jobs": jobs,
                 "shader_compiler": str(ffx_sc), "shader_compiler_sha256": sha256(ffx_sc),
                 "glslang": str(glslang), "glslang_sha256": sha256(glslang)}
    receipt = {"source": source, "patch_sha256": patch_hash,
               "vulkan": vulkan, "toolchain": toolchain,
               "effects": ["FSR3 Upscaler 3.1.4", "Optical Flow", "Frame Interpolation"],
               "runtime_dll": str(dll), "runtime_dll_sha256": sha256(dll)}
    receipt_path = build_dir / "fidelityfx-runtime-receipt.json"
    receipt["receipt"] = str(receipt_path)
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return dll, receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / ".tools/advanced-rendering")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--prepare-only", action="store_true",
                        help="verify source, apply the patch, and prepare the Vulkan import library")
    args = parser.parse_args()
    if not 1 <= args.jobs <= 4:
        parser.error("--jobs must be between 1 and 4")
    cache = args.cache.resolve()
    if args.prepare_only:
        sdk = cache / "FidelityFX-SDK-1.1.4"
        source = verify_source(cache, sdk)
        patch_hash = apply_fidelityfx_patch(sdk)
        vulkan = make_vulkan_import_library(cache, cache / "fidelityfx-native-build")
        print(json.dumps({"source": source, "patch_sha256": patch_hash, "vulkan": vulkan}, indent=2))
        return 0
    dll, receipt = build_runtime(cache, args.jobs)
    print(f"Built {dll}\nReceipt: {receipt['receipt']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
