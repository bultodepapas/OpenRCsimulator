#!/usr/bin/env python3
"""Build the prepared-model adapter with the repository's locked native toolchain."""
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
NATIVE = ROOT / "research/propwash/e0b6p/native"
ORIGINAL = NATIVE / "src/smooth_wake_extension.cpp"
KERNEL = NATIVE / "src/smooth_wake_kernel.hpp"
SNIPPET = HERE / "native_extension.inc"
OUTPUT_ROOT = ROOT / ".tools/native-prepared"
LOCKED_BUILDER = ROOT / "research/native-slipstream/build.py"
TOOLCHAIN_LOCK = ROOT / "research/native-slipstream/toolchain-lock.json"
LOCKED_BUILDER_IMPORT_SHA256 = hashlib.sha256(LOCKED_BUILDER.read_bytes()).hexdigest()
SPEC = importlib.util.spec_from_file_location("gate_p_build", LOCKED_BUILDER)
locked = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(locked)


def digest(path: Path) -> str:
	return hashlib.sha256(path.read_bytes()).hexdigest()


def library_name(platform: str) -> str:
	baseline = locked.expected_library_name(platform)
	if baseline.count("openrc_slipstream") != 1:
		raise RuntimeError(f"Unexpected locked library name: {baseline}")
	return baseline.replace("openrc_slipstream", "openrc_prepared_wake")


def candidate_source(original: bytes, snippet: bytes) -> bytes:
	marker = b"class OpenRCSmoothWake final : public godot::RefCounted {"
	if original.count(marker) != 1:
		raise RuntimeError("The native extension class marker changed; review this experiment before rebuilding")
	return original.split(marker, maxsplit=1)[0] + snippet


def snapshot_inputs() -> tuple[dict[Path, bytes], dict[str, dict[str, str]]]:
	paths = (ORIGINAL, KERNEL, SNIPPET, Path(__file__).resolve(), LOCKED_BUILDER, TOOLCHAIN_LOCK)
	contents = {path: path.read_bytes() for path in paths}
	if hashlib.sha256(contents[LOCKED_BUILDER]).hexdigest() != LOCKED_BUILDER_IMPORT_SHA256:
		raise RuntimeError("The locked builder changed while this process was starting; retry the build")
	manifest = {
		"original_binding": {"path": str(ORIGINAL.relative_to(ROOT)), "sha256": hashlib.sha256(contents[ORIGINAL]).hexdigest()},
		"kernel_header": {"path": str(KERNEL.relative_to(ROOT)), "sha256": hashlib.sha256(contents[KERNEL]).hexdigest()},
		"prepared_snippet": {"path": str(SNIPPET.relative_to(ROOT)), "sha256": hashlib.sha256(contents[SNIPPET]).hexdigest()},
		"build_script": {"path": str(Path(__file__).resolve().relative_to(ROOT)), "sha256": hashlib.sha256(contents[Path(__file__).resolve()]).hexdigest()},
		"locked_builder": {"path": str(LOCKED_BUILDER.relative_to(ROOT)), "sha256": hashlib.sha256(contents[LOCKED_BUILDER]).hexdigest()},
		"toolchain_lock": {"path": str(TOOLCHAIN_LOCK.relative_to(ROOT)), "sha256": hashlib.sha256(contents[TOOLCHAIN_LOCK]).hexdigest()},
	}
	return contents, manifest


def verify_inputs_unchanged(contents: dict[Path, bytes], generated_source: Path, expected_candidate: bytes,
		generated_header: Path, expected_header: bytes) -> None:
	changed = [str(path.relative_to(ROOT)) for path, initial in contents.items()
		if not path.is_file() or path.read_bytes() != initial]
	if changed:
		raise RuntimeError("Build inputs changed during compilation: " + ", ".join(changed))
	if generated_source.read_bytes() != expected_candidate:
		raise RuntimeError("Generated candidate source changed during compilation")
	if generated_header.read_bytes() != expected_header:
		raise RuntimeError("Generated kernel header changed during compilation")


def build(args: argparse.Namespace) -> None:
	if not ORIGINAL.is_file() or not KERNEL.is_file() or not SNIPPET.is_file():
		raise SystemExit("The original native sources or prepared adapter snippet are missing")
	contents, source_manifest = snapshot_inputs()
	lock = json.loads(contents[TOOLCHAIN_LOCK])
	platform = locked.host_platform_name()
	arch = locked.host_arch_name()
	env = os.environ.copy()
	compiler_version = None
	if platform == "linux":
		compiler_version = locked.run(["g++", "-dumpfullversion", "-dumpversion"], capture=True).strip()
		if compiler_version != lock["linux"]["compiler_version"]:
			raise SystemExit(f"Expected locked g++ {lock['linux']['compiler_version']}, got {compiler_version}")
		env.update(CC="gcc", CXX="g++")

	# These are the existing pinned SCons and godot-cpp caches used by the baseline build.
	scons = locked.ensure_scons(lock)
	dependency = locked.ensure_godot_cpp(lock)
	generated_root = OUTPUT_ROOT / "src"
	generated_root.mkdir(parents=True, exist_ok=True)
	candidate = generated_root / "smooth_wake_prepared.cpp"
	candidate_bytes = candidate_source(contents[ORIGINAL], contents[SNIPPET])
	candidate.write_bytes(candidate_bytes)
	generated_header = generated_root / KERNEL.name
	generated_header.write_bytes(contents[KERNEL])

	profile = lock["godot_cpp"]["build_profile"]
	profile_text = json.dumps(profile["content"], sort_keys=True, separators=(",", ":")) + "\n"
	profile_sha256 = hashlib.sha256(profile_text.encode()).hexdigest()
	if profile_sha256 != profile["sha256"]:
		raise SystemExit("Locked build profile hash mismatch")
	build_root = OUTPUT_ROOT / f"{platform}-{arch}"
	build_root.mkdir(parents=True, exist_ok=True)
	profile_path = build_root / "build_profile.json"
	profile_path.write_text(profile_text, encoding="utf-8")
	sconstruct = locked.sconstruct_text(
		dependency, generated_root, build_root / "lib", profile_path, lock["godot"]["extension_api"])
	if sconstruct.count('"openrc_slipstream"') != 1:
		raise RuntimeError("Locked SConstruct library-name marker changed; review before building")
	(build_root / "SConstruct").write_text(sconstruct.replace('"openrc_slipstream"', '"openrc_prepared_wake"'),
			encoding="utf-8")
	locked.run([*scons, "-C", str(build_root), f"-j{args.jobs}", f"platform={platform}",
			f"arch={arch}", "target=template_release"], env=env)

	name = library_name(platform)
	output = (args.output or OUTPUT_ROOT / name).resolve()
	output.parent.mkdir(parents=True, exist_ok=True)
	verify_inputs_unchanged(contents, candidate, candidate_bytes, generated_header, contents[KERNEL])
	temporary_output = output.with_name(f".{output.name}.tmp-{os.getpid()}")
	try:
		shutil.copy2(build_root / "lib" / name, temporary_output)
		verify_inputs_unchanged(contents, candidate, candidate_bytes, generated_header, contents[KERNEL])
		library_sha256 = digest(temporary_output)
		os.replace(temporary_output, output)
	finally:
		temporary_output.unlink(missing_ok=True)

	manifest = {
		"format": "openrc-e0b6p-prepared-model-build v1",
		"toolchain": {
			"platform": platform,
			"architecture": arch,
			"compiler_version": compiler_version,
			"godot_cpp_commit": lock["godot_cpp"]["commit"],
			"godot_extension_api": lock["godot"]["extension_api"],
			"build_profile_sha256": profile_sha256,
		},
		"sources": source_manifest | {
			"generated_candidate": {"path": str(candidate.relative_to(ROOT)), "sha256": hashlib.sha256(candidate_bytes).hexdigest()},
		},
		"library": {"path": str(output), "sha256": library_sha256},
	}
	verify_inputs_unchanged(contents, candidate, candidate_bytes, generated_header, contents[KERNEL])
	manifest_path = OUTPUT_ROOT / "build.json"
	temporary_manifest = manifest_path.with_name(f".{manifest_path.name}.tmp-{os.getpid()}")
	try:
		temporary_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
		verify_inputs_unchanged(contents, candidate, candidate_bytes, generated_header, contents[KERNEL])
		os.replace(temporary_manifest, manifest_path)
	finally:
		temporary_manifest.unlink(missing_ok=True)
	print(f"Built prepared-model candidate: {output}")
	print(f"Build manifest: {manifest_path}")


def main() -> None:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--jobs", type=int, default=2)
	parser.add_argument("--output", type=Path)
	args = parser.parse_args()
	if args.jobs < 1:
		parser.error("--jobs must be positive")
	OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
	build_lock = OUTPUT_ROOT / ".build.lock"
	try:
		build_lock.mkdir()
	except FileExistsError as error:
		raise SystemExit(f"A prepared-model build lock exists at {build_lock}; wait for the active build or inspect/remove a stale lock") from error
	try:
		(build_lock / "owner.txt").write_text(f"pid={os.getpid()}\n", encoding="utf-8")
		build(args)
	finally:
		shutil.rmtree(build_lock, ignore_errors=True)


if __name__ == "__main__":
	main()
