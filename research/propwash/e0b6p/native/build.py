#!/usr/bin/env python3
"""Build the research-only smooth wake with the existing locked Gate-P toolchain."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SPEC = importlib.util.spec_from_file_location("gate_p_build", ROOT / "research/native-slipstream/build.py")
locked = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(locked)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    lock = locked.load_lock()
    platform = locked.host_platform_name()
    arch = locked.host_arch_name()
    env = os.environ.copy()
    if platform == "linux":
        version = locked.run(["g++", "-dumpfullversion", "-dumpversion"], capture=True).strip()
        if version != lock["linux"]["compiler_version"]:
            raise SystemExit(f"Expected locked g++ {lock['linux']['compiler_version']}, got {version}")
        env.update(CC="gcc", CXX="g++")
    scons = locked.ensure_scons(lock)
    dependency = locked.ensure_godot_cpp(lock)
    build = ROOT / ".tools/native-smooth-wake" / f"{platform}-{arch}"
    build.mkdir(parents=True, exist_ok=True)
    profile = lock["godot_cpp"]["build_profile"]
    content = json.dumps(profile["content"], sort_keys=True, separators=(",", ":")) + "\n"
    if hashlib.sha256(content.encode()).hexdigest() != profile["sha256"]:
        raise SystemExit("Locked build profile hash mismatch")
    profile_path = build / "build_profile.json"
    profile_path.write_text(content)
    (build / "SConstruct").write_text(locked.sconstruct_text(
        dependency, HERE / "src", build / "lib", profile_path, lock["godot"]["extension_api"]))
    locked.run([*scons, "-C", str(build), f"-j{args.jobs}", f"platform={platform}",
                f"arch={arch}", "target=template_release"], env=env)
    name = locked.expected_library_name(platform)
    output = (args.output or ROOT / ".tools/native-smooth-wake" / name).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(build / "lib" / name, output)
    print(f"Built research-only {output}")


if __name__ == "__main__":
    main()
