#!/usr/bin/env python3
"""Build the NK-1 math-spike GDExtension with the repository's pinned native toolchain.

Reuses research/native-slipstream/build.py (SCons wheel + godot-cpp bootstrap) exactly as
research/rc-monster-truck/native/build.py does; every output stays under tmp/native-math-spike/.
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

TOOL_ROOT = ROOT / "tmp/native-math-spike"
locked.LOCK_PATH = HERE / "toolchain-lock.json"
locked.TOOL_ROOT = TOOL_ROOT
locked.SOURCES = HERE / "src"
LIBRARY = TOOL_ROOT / "lib/libopenrc_math_spike.so"
LIBM_SYMBOLS = {"sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sqrt", "pow", "exp", "log",
                "sinh", "cosh", "tanh", "fmod", "floor", "sincos"}


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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=4, help="SCons jobs (at most 4 on the shared VM)")
    args = parser.parse_args()
    if not 1 <= args.jobs <= 4:
        parser.error("--jobs must be between 1 and 4")
    if locked.host_platform_name() != "linux" or locked.host_arch_name() != "x86_64":
        raise SystemExit("The NK-1 spike build is Linux x86_64 only.")
    lock = locked.load_lock()
    platform_lock = lock["linux"]
    compiler_version = locked.run(["g++", "-dumpfullversion", "-dumpversion"], capture=True).strip()
    if compiler_version != platform_lock["compiler_version"]:
        raise SystemExit(f"Expected locked g++ {platform_lock['compiler_version']}, got {compiler_version}.")
    if shutil.disk_usage(ROOT).free < 8 * 1024**3:
        raise SystemExit("Less than 8 GB free; refusing to build.")

    scons = locked.ensure_scons(lock)
    godot_cpp = locked.ensure_godot_cpp(lock)
    build_dir = TOOL_ROOT / "build/linux-x86_64-template_release"
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
    flags = [*platform_lock["floating_point_flags"], *platform_lock["exception_flags"]]
    if sconstruct.count(default_fp) != 1 or sconstruct.count("openrc_slipstream") != 1:
        raise SystemExit("Shared SConstruct template changed; update this adapter.")
    sconstruct = sconstruct.replace(default_fp, f"env.Append(CXXFLAGS={json.dumps(flags)})")
    (build_dir / "SConstruct").write_text(sconstruct.replace("openrc_slipstream", "openrc_math_spike"),
                                          encoding="utf-8")
    env = dict(os.environ, CC="gcc", CXX="g++")
    locked.run([*scons, "-C", str(build_dir), f"-j{args.jobs}", "platform=linux", "arch=x86_64",
                "target=template_release", "verbose=yes"], env=env)

    built = build_dir / "lib/libopenrc_math_spike.so"
    if not built.is_file():
        raise SystemExit(f"SCons finished without producing {built}.")
    LIBRARY.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(built, LIBRARY)
    source_digest = hashlib.sha256()
    for path in sorted(locked.SOURCES.glob("*.cpp")):
        source_digest.update(path.name.encode() + b"\0" + path.read_bytes() + b"\0")
    receipt = {
        "library": str(LIBRARY.relative_to(ROOT)),
        "binary_sha256": sha256_file(LIBRARY),
        "source_sha256": source_digest.hexdigest(),
        "lock_sha256": sha256_file(locked.LOCK_PATH),
        "shared_builder_sha256": sha256_file(SHARED_BUILDER),
        "godot_cpp_commit": locked.run(["git", "rev-parse", "HEAD"], cwd=godot_cpp, capture=True).strip(),
        "scons_wheel_sha256": lock["scons"]["wheel_sha256"],
        "compiler_version": compiler_version,
        "cxxflags_appended": flags,
        "target": "template_release",
        "libm_imports": libm_imports(LIBRARY),
    }
    (TOOL_ROOT / "build-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                                   encoding="utf-8")
    print(json.dumps(receipt, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
