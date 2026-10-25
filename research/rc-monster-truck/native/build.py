#!/usr/bin/env python3
"""Build, parity-check, and optionally stage the isolated ground-vehicle GDExtension."""

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


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHARED_BUILDER = ROOT / "research/native-slipstream/build.py"
SPEC = importlib.util.spec_from_file_location("openrc_locked_gdextension_build", SHARED_BUILDER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load shared GDExtension builder: {SHARED_BUILDER}")
locked = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(locked)

# Reuse the pinned SCons/godot-cpp bootstrap while keeping all RCV artifacts isolated.
locked.LOCK_PATH = HERE / "toolchain-lock.json"
locked.TOOL_ROOT = ROOT / ".tools/native-ground-vehicle"
locked.SOURCES = HERE / "src"


def expected_library_name(platform: str) -> str:
    if platform == "windows":
        return "openrc_ground_vehicle.dll"
    return "libopenrc_ground_vehicle.so"


def godot_executable(root: Path, explicit: Path | None, platform: str) -> Path:
    if explicit is not None:
        return explicit.resolve()
    if platform == "windows":
        return root / ".tools/Godot_v4.8-beta1_win64_console.exe"
    return root / ".tools/Godot_v4.8-beta1_linux.x86_64"


def extension_descriptor(library_prefix: str) -> str:
    return (
        '[configuration]\n'
        'entry_symbol = "openrc_ground_vehicle_library_init"\n'
        'compatibility_minimum = "4.7"\n'
        'reloadable = false\n\n'
        '[libraries]\n'
        f'windows = "{library_prefix}openrc_ground_vehicle.dll"\n'
        f'linux = "{library_prefix}libopenrc_ground_vehicle.so"\n'
    )


def _run_godot(godot: Path, args: list[str], root: Path, timeout_seconds: int = 300) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(godot), *args],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout_seconds,
        check=False,
    )


_GODOT_ERROR_LINE = re.compile(
    r"^\s*(?:SCRIPT ERROR:|SHADER ERROR:|ERROR:|FATAL:|Parse Error:|Compile Error:|Failed to load script\b)"
)


def _godot_error_lines(output: str) -> list[str]:
    return [line for line in output.splitlines() if _GODOT_ERROR_LINE.search(line)]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def source_digest() -> str:
    digest = hashlib.sha256()
    for path in sorted((HERE / "src").glob("*.cpp")) + sorted((HERE / "src").glob("*.hpp")):
        digest.update(path.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def refresh_receipt(platform: str, library: Path, platform_lock: dict, lock: dict) -> dict:
    platform_root = locked.TOOL_ROOT
    platform_root.mkdir(parents=True, exist_ok=True)
    compiler_identity = {
        "windows": {
            "visual_studio_version": lock["windows"]["visual_studio_version"],
            "compiler_toolset": lock["windows"]["compiler_toolset"],
            "sdk_version": lock["windows"]["sdk_version"],
        },
        "linux": {"compiler_version": lock["linux"]["compiler_version"]},
    }[platform]
    toolchain_input = {
        "lock_sha256": sha256_file(HERE / "toolchain-lock.json"),
        "platform": platform,
        "architecture": "x86_64",
        "compiler": compiler_identity,
        "floating_point_flags": platform_lock["floating_point_flags"],
        "exception_flags": platform_lock["exception_flags"],
        "scons_builder_sha256": sha256_file(SHARED_BUILDER),
        "godot_cpp_commit": lock["godot_cpp"]["commit"],
    }
    toolchain_digest = hashlib.sha256(
        (json.dumps(toolchain_input, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    ).hexdigest()
    record = {
        "platform": platform,
        "architecture": "x86_64",
        "backend": "native",
        "backend_version": lock["backend_version"],
        "abi_version": lock["native_abi_version"],
        "solver_version": lock["solver_version"],
        "source_sha256": source_digest(),
        "toolchain_sha256": toolchain_digest,
        "binary_sha256": sha256_file(library),
        "toolchain": compiler_identity,
        "floating_point_flags": platform_lock["floating_point_flags"],
        "exception_flags": platform_lock["exception_flags"],
    }
    (platform_root / f"build-receipt.{platform}.json").write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    platforms = {}
    generic = platform_root / "build-receipt.json"
    if generic.is_file():
        try:
            old = json.loads(generic.read_text(encoding="utf-8"))
            if isinstance(old.get("platforms"), dict):
                platforms.update(old["platforms"])
        except (json.JSONDecodeError, OSError):
            pass
    platforms[platform] = record
    combined = {
        "format": "openrc-ground-vehicle-native-receipt",
        "backend": "native",
        "backend_version": lock["backend_version"],
        "abi_version": lock["native_abi_version"],
        "solver_version": lock["solver_version"],
        "platforms": platforms,
    }
    generic.write_text(json.dumps(combined, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return record


def stage_app_native(lock: dict) -> None:
    source_hash = source_digest()
    staged: dict[str, dict] = {}
    for platform in ("windows", "linux"):
        library = locked.TOOL_ROOT / expected_library_name(platform)
        receipt = locked.TOOL_ROOT / f"build-receipt.{platform}.json"
        if not library.is_file() or not receipt.is_file():
            raise SystemExit(
                "--install-app requires both verified Windows and Linux x86_64 builds in "
                f"{locked.TOOL_ROOT}; missing {platform}. Build each platform first."
            )
        record = json.loads(receipt.read_text(encoding="utf-8"))
        if record.get("source_sha256") != source_hash or record.get("backend_version") != lock["backend_version"]:
            raise SystemExit(f"The {platform} native build is stale for current sources; rebuild it before installation.")
        if record.get("binary_sha256") != sha256_file(library):
            raise SystemExit(f"The {platform} native binary no longer matches its build receipt.")
        staged[platform] = record

    destination = ROOT / "app/native/ground_vehicle"
    if not destination.resolve().is_relative_to((ROOT / "app").resolve()):
        raise SystemExit(f"Refusing to install native output outside app/: {destination}")
    destination.mkdir(parents=True, exist_ok=True)
    for platform in ("windows", "linux"):
        shutil.copy2(locked.TOOL_ROOT / expected_library_name(platform), destination / expected_library_name(platform))
    descriptor = extension_descriptor("res://native/ground_vehicle/")
    (destination / "openrc_ground_vehicle.gdextension").write_text(descriptor, encoding="utf-8")
    receipt = {
        "format": "openrc-ground-vehicle-native-receipt",
        "backend": "native",
        "backend_version": lock["backend_version"],
        "abi_version": lock["native_abi_version"],
        "solver_version": lock["solver_version"],
        "platforms": staged,
    }
    (destination / "build-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    dependency_license = locked.ensure_godot_cpp(lock) / "LICENSE.md"
    if not dependency_license.is_file():
        raise SystemExit(f"Pinned godot-cpp license not found at {dependency_license}")
    shutil.copy2(dependency_license, destination / "LICENSE.godot-cpp.md")
    print(f"Installed Windows and Linux native outputs with receipt and godot-cpp license under {destination}.")


def check_windows_toolchain(lock: dict) -> None:
    expected = lock["windows"]
    actual_toolset = os.environ.get("VCToolsVersion", "").rstrip("\\/")
    actual_sdk = os.environ.get("WindowsSDKVersion", "").rstrip("\\/")
    if actual_toolset != expected["compiler_toolset"] or actual_sdk != expected["sdk_version"]:
        raise SystemExit(
            "Windows build requires the locked Visual Studio developer environment "
            f"(MSVC {expected['compiler_toolset']}, SDK {expected['sdk_version']}); "
            f"got MSVC {actual_toolset or 'unset'}, SDK {actual_sdk or 'unset'}. "
            "Run from the matching x64 Native Tools prompt."
        )
    if shutil.which("cl.exe") is None or shutil.which("link.exe") is None:
        raise SystemExit("MSVC cl.exe and link.exe must be available on PATH from the developer prompt.")


def run_smoke_test(library: Path, godot_arg: Path | None, lock: dict) -> None:
    godot = godot_executable(ROOT, godot_arg, locked.host_platform_name())
    if not godot.is_file():
        raise SystemExit("Pinned Godot console executable not found; pass --godot PATH to run the load smoke test.")

    version_result = _run_godot(godot, ["--version"], ROOT, timeout_seconds=30)
    version = version_result.stdout.strip().splitlines()[-1] if version_result.stdout.strip() else ""
    if version_result.returncode:
        raise SystemExit(f"Could not query pinned Godot version:\n{version_result.stdout}")
    if version != lock["godot"]["version"]:
        raise SystemExit(f"Expected Godot {lock['godot']['version']}, got {version}.")

    project = locked.TOOL_ROOT / "smoke_project"
    project.mkdir(parents=True, exist_ok=True)
    shutil.copy2(library, project / library.name)
    receipt_source = locked.TOOL_ROOT / "build-receipt.json"
    if receipt_source.is_file():
        receipt_destination = project / "native/ground_vehicle/build-receipt.json"
        receipt_destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(receipt_source, receipt_destination)
    (project / "project.godot").write_text(
        'config_version=5\n\n[application]\nconfig/name="OpenRC native float64 smoke test"\n',
        encoding="utf-8",
    )
    (project / "openrc_ground_vehicle.gdextension").write_text(
        extension_descriptor("res://"), encoding="utf-8"
    )
    (project / "verify.gd").write_text(
        'extends SceneTree\n\n'
        'func _initialize() -> void:\n'
        '\tGDExtensionManager.load_extension("res://openrc_ground_vehicle.gdextension")\n'
        '\tif not ClassDB.class_exists("OpenRCGroundVehicleNative"):\n'
        '\t\tpush_error("Native ground-vehicle probe class did not load")\n'
        '\t\tquit(1)\n'
        '\t\treturn\n'
        '\tvar probe: Object = ClassDB.instantiate("OpenRCGroundVehicleNative")\n'
        '\tvar info: Dictionary = probe.abi_info()\n'
        '\tif int(info.get("float_bytes", 0)) != 8 or not bool(info.get("ieee754", false)):\n'
        '\t\tpush_error("Native probe does not report IEEE-754 float64")\n'
        '\t\tquit(1)\n'
        '\t\treturn\n'
        '\tif int(info.get("abi_version", 0)) != 1 or str(info.get("solver_version", "")) != "openrc-ground-vehicle-dynamics-rk4-v5":\n'
        '\t\tpush_error("Native ABI/solver identity mismatch")\n'
        '\t\tquit(1)\n'
        '\t\treturn\n'
        '\tvar identity: Dictionary = probe.backend_identity()\n'
        '\tif identity.get("backend") != "native" or str(identity.get("binary_sha256", "")).length() != 64:\n'
        '\t\tpush_error("Native runtime receipt identity is missing: " + str(identity))\n'
        '\t\tquit(1)\n'
        '\t\treturn\n'
        '\tvar input := PackedFloat64Array([0.0, 0.12345678901234568, -9.80665, 1.0e-200])\n'
        '\tvar output: PackedFloat64Array = probe.echo_float64(input)\n'
        '\tif output != input:\n'
        '\t\tpush_error("PackedFloat64Array round-trip changed values")\n'
        '\t\tquit(1)\n'
        '\t\treturn\n'
        '\tprint("OPENRC_NATIVE_FLOAT64_SMOKE_OK")\n'
        '\tquit(0)\n',
        encoding="utf-8",
    )
    result = _run_godot(godot, ["--headless", "--path", str(project), "--script", "res://verify.gd"], ROOT)
    if result.returncode or "OPENRC_NATIVE_FLOAT64_SMOKE_OK" not in result.stdout:
        raise SystemExit(f"Native extension load/float64 smoke test failed:\n{result.stdout}")
    print("Verified GDExtension load and PackedFloat64Array round-trip.")


def _copy_tree_files(source_root: Path, project: Path, relative_paths: list[str]) -> None:
    for relative in relative_paths:
        source = source_root / relative
        destination = project / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def run_parity_test(library: Path, godot_arg: Path | None, lock: dict) -> None:
    godot = godot_executable(ROOT, godot_arg, locked.host_platform_name())
    if not godot.is_file():
        raise SystemExit("Pinned Godot executable not found for native parity test.")
    project = locked.TOOL_ROOT / "parity_project"
    resolved = project.resolve()
    if not resolved.is_relative_to(locked.TOOL_ROOT.resolve()):
        raise SystemExit(f"Refusing to clear parity project outside tool root: {resolved}")
    if project.exists():
        shutil.rmtree(project)
    project.mkdir(parents=True)
    (project / "project.godot").write_text(
        'config_version=5\n\n[application]\nconfig/name="OpenRC native ground vehicle parity"\n',
        encoding="utf-8",
    )
    shutil.copy2(library, project / library.name)
    (project / "openrc_ground_vehicle.gdextension").write_text(
        extension_descriptor("res://"), encoding="utf-8"
    )
    _copy_tree_files(ROOT / "app", project, [
        "physics/math3d.gd",
        "physics/rigid_body.gd",
        "physics/integrator.gd",
        "physics/generalized_coordinates.gd",
        "physics/ground_terrain.gd",
        "physics/lake_surface.gd",
        "physics/ground_vehicle/vehicle_dynamics.gd",
        "physics/ground_vehicle/vehicle_environment.gd",
        "physics/ground_vehicle/vehicle_data.gd",
        "physics/ground_vehicle/course.gd",
        "data/lake_loader.gd",
        "data/fields/lake.json",
        "data/vehicles/ground/mt8_bisonte.json",
        "data/ground_vehicle/practice.json",
    ])
    shutil.copy2(HERE / "parity_harness.gd", project / "parity_harness.gd")
    receipt_source = locked.TOOL_ROOT / "build-receipt.json"
    if receipt_source.is_file():
        receipt_destination = project / "native/ground_vehicle/build-receipt.json"
        receipt_destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(receipt_source, receipt_destination)
    result = _run_godot(godot, ["--headless", "--path", str(project), "--script", "res://parity_harness.gd"], ROOT)
    platform = locked.host_platform_name()
    receipt_path = locked.TOOL_ROOT / f"build-receipt.{platform}.json"
    receipt = json.loads(receipt_path.read_text(encoding="utf-8")) if receipt_path.is_file() else {}
    engine_debug = any("engine_debug=true" in line for line in result.stdout.splitlines())
    log_header = {
        "platform": platform,
        "godot_version": lock["godot"]["version"],
        "engine_debug_build": engine_debug,
        "extension_target": "template_release",
        "source_sha256": receipt.get("source_sha256", ""),
        "toolchain_sha256": receipt.get("toolchain_sha256", ""),
        "binary_sha256": receipt.get("binary_sha256", ""),
    }
    log_path = locked.TOOL_ROOT / f"parity-{platform}-latest.log"
    log_path.write_text(
        json.dumps(log_header, indent=2, sort_keys=True) + "\n\n" + result.stdout,
        encoding="utf-8",
    )
    error_lines = _godot_error_lines(result.stdout)
    if result.returncode or error_lines or "OPENRC_NATIVE_PARITY_OK" not in result.stdout:
        reasons = []
        if result.returncode:
            reasons.append(f"Godot exited with status {result.returncode}")
        if error_lines:
            reasons.append("Godot reported errors: " + " | ".join(error_lines))
        if "OPENRC_NATIVE_PARITY_OK" not in result.stdout:
            reasons.append("parity success marker is missing")
        raise SystemExit(
            f"Native/GDScript parity harness failed ({'; '.join(reasons)}). Full output: {log_path}\n"
            f"{result.stdout}"
        )
    for line in result.stdout.strip().splitlines():
        if line.startswith(("OPENRC_NATIVE_EVAL_PROFILE", "OPENRC_NATIVE_LAKE_PARITY", "OPENRC_NATIVE_LAKE_PROFILE", "OPENRC_NATIVE_PARITY_OK")):
            print(line)
    print(f"Retained parity stdout and build hashes at {log_path}.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--godot", type=Path, help="pinned Godot executable for smoke and parity checks")
    parser.add_argument("--skip-smoke", action="store_true", help="build only; skip loading the extension in Godot")
    parser.add_argument("--skip-parity", action="store_true", help="skip the evaluator parity harness")
    parser.add_argument("--install-app", action="store_true", help="stage matched Windows/Linux outputs under app/native/ground_vehicle")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")

    lock = locked.load_lock()
    platform = locked.host_platform_name()
    arch = locked.host_arch_name()
    if arch != "x86_64":
        raise SystemExit("This research prototype currently supports x86_64 only.")
    if platform not in ("windows", "linux"):
        raise SystemExit("This research prototype currently supports Windows and Linux x86_64 only.")

    build_env = os.environ.copy()
    if platform == "windows":
        check_windows_toolchain(lock)
        platform_lock = lock["windows"]
    else:
        platform_lock = lock["linux"]
        compiler_version = locked.run(["g++", "-dumpfullversion", "-dumpversion"], capture=True).strip()
        if compiler_version != platform_lock["compiler_version"]:
            raise SystemExit(f"Expected locked g++ {platform_lock['compiler_version']}, got {compiler_version}.")
        build_env.update(CC="gcc", CXX="g++")

    scons = locked.ensure_scons(lock)
    dependency = locked.ensure_godot_cpp(lock)
    build_dir = locked.TOOL_ROOT / "build" / f"{platform}-{arch}-template_release"
    build_dir.mkdir(parents=True, exist_ok=True)
    profile = lock["godot_cpp"]["build_profile"]
    profile_content = json.dumps(profile["content"], sort_keys=True, separators=(",", ":")) + "\n"
    profile_digest = hashlib.sha256(profile_content.encode("utf-8")).hexdigest()
    if profile_digest != profile["sha256"]:
        raise SystemExit(f"Build profile SHA-256 mismatch: expected {profile['sha256']}, got {profile_digest}.")

    profile_path = build_dir / "build_profile.json"
    profile_path.write_text(profile_content, encoding="utf-8")
    output_dir = build_dir / "lib"
    sconstruct = locked.sconstruct_text(
        dependency, locked.SOURCES, output_dir, profile_path, lock["godot"]["extension_api"]
    )
    exception_flag = platform_lock["exception_flags"][0]
    if platform == "windows":
        default_fp = 'env.Append(CXXFLAGS=["/fp:strict"])'
        adapted_flags = f'env.Append(CXXFLAGS=["/fp:strict", "{exception_flag}"])'
    else:
        default_fp = 'env.Append(CXXFLAGS=["-fno-fast-math", "-ffp-contract=off"])'
        adapted_flags = (
            'env.Append(CXXFLAGS=["-fno-fast-math", "-ffp-contract=off", '
            f'"{exception_flag}"])'
        )
    if sconstruct.count(default_fp) != 1:
        raise SystemExit(f"Shared SConstruct floating-point policy changed for {platform}.")
    sconstruct = sconstruct.replace(default_fp, adapted_flags)
    if sconstruct.count("openrc_slipstream") != 1:
        raise SystemExit("Shared SConstruct template changed; update the isolated target-name adapter.")
    (build_dir / "SConstruct").write_text(sconstruct.replace("openrc_slipstream", "openrc_ground_vehicle"), encoding="utf-8")

    locked.run(
        [
            *scons,
            "-C",
            str(build_dir),
            f"-j{args.jobs}",
            f"platform={platform}",
            f"arch={arch}",
            "target=template_release",
        ],
        env=build_env,
    )

    built_library = build_dir / "lib" / expected_library_name(platform)
    if not built_library.is_file():
        raise SystemExit(f"SCons finished without producing {built_library}.")
    output = args.output or locked.TOOL_ROOT / expected_library_name(platform)
    if not output.is_absolute():
        output = ROOT / output
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(built_library, output)
    print(f"Built research-only {output} ({platform}/{arch}, {platform_lock['floating_point_flags']}).")
    refresh_receipt(platform, output, platform_lock, lock)
    if not args.skip_smoke:
        run_smoke_test(output, args.godot, lock)
    if not args.skip_parity:
        run_parity_test(output, args.godot, lock)
    if args.install_app:
        stage_app_native(lock)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
