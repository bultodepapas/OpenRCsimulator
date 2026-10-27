#!/usr/bin/env python3
"""Build the NK-3 native stage-evaluator components with the repository's pinned native toolchain.

Reuses research/native-slipstream/build.py (SCons wheel + godot-cpp bootstrap) the way
research/native-math-spike/build.py does. Every output stays under the ignored tmp/native-kernel/:
the library, a runtime-loadable .gdextension descriptor and build-receipt.json.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SHARED_BUILDER = ROOT / "research/native-slipstream/build.py"
SPEC = importlib.util.spec_from_file_location("openrc_locked_gdextension_build", SHARED_BUILDER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load shared GDExtension builder: {SHARED_BUILDER}")
locked = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(locked)

TOOL_ROOT = ROOT / "tmp/native-kernel"
locked.LOCK_PATH = HERE / "toolchain-lock.json"
locked.TOOL_ROOT = TOOL_ROOT
locked.SOURCES = HERE / "src"
NAME = "openrc_native_kernel"
# GDScript sources whose current HEAD arithmetic the port mirrors, operation by operation (identity only:
# the oracle, not this hash, establishes bit identity against whatever app/ holds at run time).
REFERENCE_SOURCES = [
    "app/physics/math3d.gd", "app/physics/ground_terrain.gd", "app/physics/lake_surface.gd",
    "app/physics/ground_wheels.gd", "app/physics/ground_contact.gd", "app/physics/air_data.gd",
    "app/physics/ground_effect.gd", "app/physics/aero.gd", "app/physics/propulsion.gd", "app/physics/dynamics.gd",
    "app/physics/hull_contact.gd", "app/physics/wind_field.gd", "app/sim/environment.gd", "app/sim/flight_session.gd",
    "app/sim/simulation.gd",
]
LIBM_SYMBOLS = {"sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sqrt", "pow", "exp", "log",
                "sinh", "cosh", "tanh", "fmod", "floor", "sincos"}
# Floating-point policy: NK-1 flags plus the pow shim's asm barrier (no -fno-builtin needed; checked below).
EXTRA_FLAGS = ["-std=c++17"]
# Stage contract identity; must equal nk_kernel.cpp kBackendVersion/kAbi and app/sim/native_stage.gd.
BACKEND_VERSION = "openrc-native-kernel-stage-v1"
ABI_VERSION = 1
RECEIPT_FORMAT = "openrc-native-kernel-receipt"
APP_DESTINATION = ROOT / "app/native/kernel"
# Oracle runs an install must cite: same binary, same mirrored sources, verdict pass (results under TOOL_ROOT).
VERIFICATIONS = {"stage_oracle": "stage-*.json", "trajectory": "trajectory-*.json"}
MIN_TRAJECTORY_TICKS = 960


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def libm_imports(binary: Path) -> list[str]:
    """Undefined libm symbols with their glibc symbol versions (objdump -T)."""
    output = subprocess.run(["objdump", "-T", str(binary)], check=True, text=True, capture_output=True).stdout
    found = []
    for line in output.splitlines():
        parts = line.split()
        if "*UND*" in parts and parts[-1] in LIBM_SYMBOLS:
            found.append(f"{parts[-1]}@{parts[-2].strip('()')}")
    return sorted(found)


def source_digest() -> str:
    digest = hashlib.sha256()
    for path in sorted([*locked.SOURCES.glob("*.cpp"), *locked.SOURCES.glob("*.hpp")]):
        digest.update(path.name.encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def mirrored_sources() -> dict[str, str]:
    return {name: sha256_file(ROOT / name) for name in REFERENCE_SOURCES}


def find_verification(key: str, pattern: str, binary_sha256: str, sources: dict[str, str]) -> dict:
    """Newest passing oracle run of `pattern` for exactly this binary and these mirrored sources."""
    for path in sorted(TOOL_ROOT.glob(pattern), reverse=True):
        if "_mutant" in path.name:
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if data.get("verdict") != "pass" or data.get("build_receipt", {}).get("binary_sha256") != binary_sha256:
            continue
        seen = {name.replace("res://", "app/", 1): value for name, value in data.get("sources", {}).items()}
        if any(seen.get(name) != value for name, value in sources.items()):
            continue
        if key == "trajectory":
            cases = data.get("trajectories", {})
            if not cases or any(int(case.get("ticks_requested", 0)) < MIN_TRAJECTORY_TICKS for case in cases.values()):
                continue
        return {"results": path.name, "results_sha256": sha256_file(path), "verdict": "pass",
                "compared": data.get("total", {}).get("compared", 0)}
    raise SystemExit(
        f"--install-app needs a passing {key} run ({pattern} in {TOOL_ROOT}) for binary {binary_sha256[:12]} and the "
        f"current mirrored sources; run: python3 research/native-kernel/run.py --script "
        f"{'stage_oracle.gd' if key == 'stage_oracle' else 'trajectory.gd --option ticks=960'}")


def install_app() -> int:
    """Stage the verified Linux build under the ignored app/native/kernel/ (library, descriptor, receipt, licence)."""
    lock = locked.load_lock()
    build_receipt_path = TOOL_ROOT / "build-receipt.json"
    library = TOOL_ROOT / f"lib/lib{NAME}.so"
    if not build_receipt_path.is_file() or not library.is_file():
        raise SystemExit("No build in tmp/native-kernel; run build.py first.")
    built = json.loads(build_receipt_path.read_text(encoding="utf-8"))
    if built.get("mutant") or built.get("binary_sha256") != sha256_file(library):
        raise SystemExit("The staged library does not match its build receipt (or is the mutant).")
    if built.get("source_sha256") != source_digest():
        raise SystemExit("Native sources changed since the build; rebuild first.")
    sources = mirrored_sources()
    verification = {key: find_verification(key, pattern, built["binary_sha256"], sources)
                    for key, pattern in VERIFICATIONS.items()}
    record = {
        "platform": "linux", "architecture": "x86_64", "backend": "native", "backend_version": BACKEND_VERSION,
        "abi_version": ABI_VERSION, "binary_sha256": built["binary_sha256"], "source_sha256": built["source_sha256"],
        "lock_sha256": built["lock_sha256"], "builder_sha256": sha256_file(Path(__file__)),
        "shared_builder_sha256": built["shared_builder_sha256"], "godot_cpp_commit": built["godot_cpp_commit"],
        "compiler_version": built["compiler_version"], "cxxflags_appended": built["cxxflags_appended"],
        "libm_imports": built["libm_imports"], "repository_head": built["repository_head"],
        "mirrored_sources": sources, "verification": verification,
    }
    receipt = {"format": RECEIPT_FORMAT, "backend": "native", "backend_version": BACKEND_VERSION,
               "abi_version": ABI_VERSION, "platforms": {"linux": record}}
    destination = APP_DESTINATION
    if not destination.resolve().is_relative_to((ROOT / "app").resolve()):
        raise SystemExit(f"Refusing to install native output outside app/: {destination}")
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(library, destination / library.name)
    (destination / f"{NAME}.gdextension").write_text(
        "; NK-3 native stage, installed by research/native-kernel/build.py --install-app; loaded only by\n"
        "; app/sim/native_stage.gd after it verifies build-receipt.json.\n"
        "[configuration]\n"
        f'entry_symbol = "{NAME}_library_init"\n'
        'compatibility_minimum = "4.7"\n'
        "reloadable = false\n\n"
        "[libraries]\n"
        f'linux.x86_64 = "res://native/kernel/lib{NAME}.so"\n', encoding="utf-8")
    (destination / "build-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                                    encoding="utf-8")
    licence = locked.ensure_godot_cpp(lock) / "LICENSE.md"
    if not licence.is_file():
        raise SystemExit(f"Pinned godot-cpp licence not found at {licence}")
    shutil.copy2(licence, destination / "LICENSE.godot-cpp.md")
    print(json.dumps(receipt, indent=2, sort_keys=True))
    print(f"Installed the verified Linux native stage under {destination}.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=4, help="SCons jobs (at most 4 on the shared VM)")
    parser.add_argument("--mutant", action="store_true",
                        help="negative control: build with -DNK_MUTATION (deliberate operation-order changes) as a "
                             "separate *_mutant library the oracle must reject")
    parser.add_argument("--install-app", action="store_true",
                        help="install the existing verified build into the ignored app/native/kernel/ (no rebuild); "
                             "requires passing stage-oracle and trajectory runs for this binary and these sources")
    args = parser.parse_args()
    if args.install_app:
        if args.mutant:
            parser.error("--install-app never installs the mutant")
        return install_app()
    variant = "_mutant" if args.mutant else ""
    library_name = NAME + variant
    library = TOOL_ROOT / f"lib/lib{library_name}.so"
    descriptor = TOOL_ROOT / f"{library_name}.gdextension"
    if not 1 <= args.jobs <= 4:
        parser.error("--jobs must be between 1 and 4")
    if locked.host_platform_name() != "linux" or locked.host_arch_name() != "x86_64":
        raise SystemExit("The NK-3 research build is Linux x86_64 only.")
    lock = locked.load_lock()
    platform_lock = lock["linux"]
    compiler_version = locked.run(["g++", "-dumpfullversion", "-dumpversion"], capture=True).strip()
    if compiler_version != platform_lock["compiler_version"]:
        raise SystemExit(f"Expected locked g++ {platform_lock['compiler_version']}, got {compiler_version}.")
    if shutil.disk_usage(ROOT).free < 6 * 1024**3:
        raise SystemExit("Less than 6 GB free; refusing to build.")

    scons = locked.ensure_scons(lock)
    godot_cpp = locked.ensure_godot_cpp(lock)
    build_dir = TOOL_ROOT / f"build/linux-x86_64-template_release{variant}"
    build_dir.mkdir(parents=True, exist_ok=True)
    profile = lock["godot_cpp"]["build_profile"]
    profile_content = json.dumps(profile["content"], sort_keys=True, separators=(",", ":")) + "\n"
    if hashlib.sha256(profile_content.encode("utf-8")).hexdigest() != profile["sha256"]:
        raise SystemExit("Build profile SHA-256 mismatch.")
    profile_path = build_dir / "build_profile.json"
    profile_path.write_text(profile_content, encoding="utf-8")

    sconstruct = locked.sconstruct_text(godot_cpp, locked.SOURCES, build_dir / "lib", profile_path,
                                        lock["godot"]["extension_api"])
    default_fp = 'env.Append(CXXFLAGS=["-fno-fast-math", "-ffp-contract=off"])'
    flags = [*platform_lock["floating_point_flags"], *platform_lock["exception_flags"], *EXTRA_FLAGS,
             *(["-DNK_MUTATION=1"] if args.mutant else [])]
    if sconstruct.count(default_fp) != 1 or sconstruct.count("openrc_slipstream") != 1:
        raise SystemExit("Shared SConstruct template changed; update this adapter.")
    sconstruct = sconstruct.replace(default_fp, f"env.Append(CXXFLAGS={json.dumps(flags)})")
    (build_dir / "SConstruct").write_text(sconstruct.replace("openrc_slipstream", library_name), encoding="utf-8")
    env = dict(os.environ, CC="gcc", CXX="g++")
    log_path = TOOL_ROOT / f"build{variant}.log"
    with log_path.open("w", encoding="utf-8") as log:
        result = subprocess.run([*scons, "-C", str(build_dir), f"-j{args.jobs}", "platform=linux", "arch=x86_64",
                                 "target=template_release", "verbose=yes"], env=env, stdout=log,
                                stderr=subprocess.STDOUT, text=True)
    if result.returncode != 0:
        tail = log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-40:]
        print("\n".join(tail))
        raise SystemExit(f"SCons failed ({result.returncode}); full log: {log_path}")

    built = build_dir / f"lib/lib{library_name}.so"
    if not built.is_file():
        raise SystemExit(f"SCons finished without producing {built}.")
    library.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(built, library)
    imports = libm_imports(library)
    if not any(entry.startswith("pow@") for entry in imports):
        raise SystemExit("libm pow is not imported: a literal exponent was folded; check the pow shim barrier.")
    descriptor.write_text(
        "; NK-3 research descriptor, generated by research/native-kernel/build.py; loaded at run time only.\n"
        "[configuration]\n"
        f'entry_symbol = "{NAME}_library_init"\n'
        'compatibility_minimum = "4.7"\n'
        "reloadable = false\n\n"
        "[libraries]\n"
        f'linux.x86_64 = "lib/lib{library_name}.so"\n', encoding="utf-8")
    receipt = {
        "library": str(library.relative_to(ROOT)),
        "descriptor": str(descriptor.relative_to(ROOT)),
        "mutant": args.mutant,
        "binary_sha256": sha256_file(library),
        "source_sha256": source_digest(),
        "backend_version": BACKEND_VERSION,
        "abi_version": ABI_VERSION,
        "lock_sha256": sha256_file(locked.LOCK_PATH),
        "builder_sha256": sha256_file(Path(__file__)),
        "shared_builder_sha256": sha256_file(SHARED_BUILDER),
        "godot_cpp_commit": locked.run(["git", "rev-parse", "HEAD"], cwd=godot_cpp, capture=True).strip(),
        "scons_wheel_sha256": lock["scons"]["wheel_sha256"],
        "compiler_version": compiler_version,
        "cxxflags_appended": flags,
        "target": "template_release",
        "libm_imports": imports,
        "repository_head": locked.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture=True).strip(),
        "reference_sources_sha256": mirrored_sources(),
    }
    (TOOL_ROOT / f"build-receipt{variant}.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                                   encoding="utf-8")
    print(json.dumps(receipt, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
