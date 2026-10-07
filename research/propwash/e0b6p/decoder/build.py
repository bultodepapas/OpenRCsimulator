#!/usr/bin/env python3
"""Build isolated double-/single-lookup wake libraries for an in-process comparison."""
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
SOURCE = HERE.parent / "native/src"
OUTPUT = ROOT / ".tools/native-decoder"
SPEC = importlib.util.spec_from_file_location("locked_builder", ROOT / "research/native-slipstream/build.py")
locked = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(locked)


def variants(source: str) -> tuple[str, str]:
    """Accept either retained implementation; reconstruct only the three measured readers."""
    baseline = source
    candidate = source
    for name, output_type, expression in (
        ("read_number", "double", "read_number(dictionary.get(key, godot::Variant()), out)"),
        ("read_vec3", "Vec3", "read_packed(dictionary.get(key, godot::Variant()), out.data(), out.size())"),
        ("read_pair", "Pair", "read_packed(dictionary.get(key, godot::Variant()), out.data(), out.size())"),
    ):
        signature = f"bool {name}(const godot::Dictionary &dictionary, const char *key, {output_type} &out) {{\n"
        slow = signature + f"\treturn dictionary.has(key) && {expression};\n}}"
        fast = signature + f"\treturn {expression};\n}}"
        if source.count(slow) + source.count(fast) != 1:
            raise RuntimeError(f"Required reader changed: {name}; review this experiment")
        baseline = baseline.replace(fast, slow)
        candidate = candidate.replace(slow, fast)
    return baseline, candidate


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=2)
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
            raise RuntimeError(f"Compiler differs from lock: {version}")
        env.update(CC="gcc", CXX="g++")
    scons = locked.ensure_scons(lock)
    dependency = locked.ensure_godot_cpp(lock)
    original = SOURCE / "smooth_wake_extension.cpp"
    baseline, candidate = variants(original.read_text())
    profile = lock["godot_cpp"]["build_profile"]
    profile_text = json.dumps(profile["content"], sort_keys=True, separators=(",", ":")) + "\n"
    assert hashlib.sha256(profile_text.encode()).hexdigest() == profile["sha256"]
    manifest = {"format": "openrc-e0b6p-decoder-build v1", "source_sha256": digest(original),
                "header_sha256": digest(SOURCE / "smooth_wake_kernel.hpp"), "variants": {}}
    for label, source in (("baseline", baseline), ("candidate", candidate)):
        if label == "candidate":
            # Only registration identifiers differ; both evaluators can coexist in one process.
            source = source.replace("OpenRCSmoothWake", "OpenRCSmoothWakeCandidate")
            source = source.replace("openrc_smooth_wake", "openrc_smooth_wake_candidate")
        root = OUTPUT / label
        src = root / "src"
        src.mkdir(parents=True, exist_ok=True)
        cpp = src / original.name
        cpp.write_text(source)
        shutil.copy2(SOURCE / "smooth_wake_kernel.hpp", src / "smooth_wake_kernel.hpp")
        build = root / f"{platform}-{arch}"
        build.mkdir(parents=True, exist_ok=True)
        profile_path = build / "build_profile.json"
        profile_path.write_text(profile_text)
        (build / "SConstruct").write_text(locked.sconstruct_text(
            dependency, src, build / "lib", profile_path, lock["godot"]["extension_api"]))
        locked.run([*scons, "-C", str(build), f"-j{args.jobs}", f"platform={platform}",
                    f"arch={arch}", "target=template_release"], env=env)
        name = locked.expected_library_name(platform)
        library = root / name
        shutil.copy2(build / "lib" / name, library)
        manifest["variants"][label] = {"source_sha256": digest(cpp), "library": str(library),
                                       "library_sha256": digest(library)}
    (OUTPUT / "build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built decoder comparison: {OUTPUT / 'build.json'}")


if __name__ == "__main__":
    main()
