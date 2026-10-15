#!/usr/bin/env python3
"""Verify packaged Monster Car 2 geometry and authored-rig provenance."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / "assets/vehicles/monster-car-2"
RUNTIME_DIR = ROOT / "app/assets/vehicles/monster-car-2"
SOURCE_ASSET_NAMES = (
    "monster_truck_nitro_1.glb",
    "datos_simulacion_1.json",
    "visual_rig.bin",
    "visual_rig.json",
    "SOURCE.txt",
    "README.md",
    "source-manifest.json",
)
RUNTIME_ASSET_NAMES = (
    "monster_truck_nitro_1.glb",
    "visual_rig.bin",
    "visual_rig.json",
    "SOURCE.txt",
    "source-manifest.json",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--regenerated-prefix",
        type=Path,
        help="optional path prefix for a fresh visual_bake.py .bin/.json output",
    )
    args = parser.parse_args()

    for name in SOURCE_ASSET_NAMES:
        source = SOURCE_DIR / name
        if not source.is_file():
            fail(f"missing packaged source asset {name}")
    for name in RUNTIME_ASSET_NAMES:
        source = SOURCE_DIR / name
        runtime = RUNTIME_DIR / name
        if not runtime.is_file():
            fail(f"missing runtime asset {name}")
        if source.read_bytes() != runtime.read_bytes():
            fail(f"runtime copy differs from packaged source: {name}")
        print(f"OK {name} {sha256(source)}")

    source_manifest_path = SOURCE_DIR / "source-manifest.json"
    source_manifest = json.loads(source_manifest_path.read_text(encoding="utf-8"))
    if source_manifest.get("schema") != "openrc-monster-car-2-source-manifest-v1":
        fail("source manifest has an unsupported schema")
    listed_paths: set[str] = set()
    for entry in source_manifest.get("files", []):
        relative_path = entry.get("path")
        expected_hash = entry.get("sha256")
        expected_size = entry.get("bytes")
        if not isinstance(relative_path, str) or relative_path in listed_paths:
            fail("source manifest has an invalid or duplicate file path")
        listed_paths.add(relative_path)
        source_file = (ROOT / relative_path).resolve()
        if not source_file.is_relative_to(ROOT.resolve()) or not source_file.is_file():
            fail(f"source manifest file is missing or outside the repository: {relative_path}")
        if source_file.stat().st_size != expected_size or sha256(source_file) != expected_hash:
            fail(f"source manifest hash or size mismatch: {relative_path}")
        print(f"OK source manifest {relative_path} {expected_hash}")
    if len(listed_paths) != 7:
        fail("source manifest must list the seven supplied, generator, and derived rig files")

    manifest = json.loads((SOURCE_DIR / "visual_rig.json").read_text(encoding="utf-8"))
    glb_hash = sha256(SOURCE_DIR / "monster_truck_nitro_1.glb")
    spec_hash = sha256(SOURCE_DIR / "datos_simulacion_1.json")
    binary_hash = sha256(SOURCE_DIR / "visual_rig.bin")
    if manifest.get("source_glb_sha256") != glb_hash:
        fail("manifest GLB source hash does not match the packaged GLB")
    if manifest.get("source_spec_sha256") != spec_hash:
        fail("manifest simulation-data hash does not match the packaged JSON")
    if manifest.get("binary_sha256") != binary_hash:
        fail("manifest bake hash does not match visual_rig.bin")

    source_path = manifest.get("source_spec")
    if not isinstance(source_path, str) or Path(source_path).is_absolute():
        fail("manifest source_spec must be a portable repository-relative path")
    expected_path = "assets/vehicles/monster-car-2/datos_simulacion_1.json"
    if source_path.replace("\\", "/") != expected_path:
        fail(f"manifest source_spec must be {expected_path}")

    original_dir = ROOT / "monster car 2"
    for name, expected in (
        ("monster_truck_nitro_1.glb", glb_hash),
        ("datos_simulacion_1.json", spec_hash),
    ):
        original = original_dir / name
        if not original.is_file() or sha256(original) != expected:
            fail(f"packaged source no longer matches supplied original {name}")

    if args.regenerated_prefix is not None:
        fresh_binary = Path(str(args.regenerated_prefix) + ".bin")
        fresh_manifest = Path(str(args.regenerated_prefix) + ".json")
        if not fresh_binary.is_file() or not fresh_manifest.is_file():
            fail("regenerated bake is missing its .bin or .json output")
        fresh_manifest_value = json.loads(fresh_manifest.read_text(encoding="utf-8"))
        if sha256(fresh_binary) != binary_hash:
            fail("regenerated bake binary differs from the packaged bake")
        if fresh_manifest_value != manifest:
            fail("regenerated manifest differs from packaged provenance or bindings")
        print("OK regenerated bake bytes and manifest match the packaged bundle")

    print("Monster Car 2 packaged visual assets verified")


if __name__ == "__main__":
    try:
        main()
    except OSError as exc:
        fail(str(exc))
