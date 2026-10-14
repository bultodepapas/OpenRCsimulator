#!/usr/bin/env python3
"""Copy the reviewed, static HX-700 GLB into the source and runtime asset trees.

The Blender inventory/export step remains authoritative. This script only installs
its .tools preview into the two checked-in asset locations and verifies both inputs.
It never opens or writes the supplied .blend file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SOURCE_BLEND = REPO_ROOT / "Helicopter 3d acrobatic" / "HX-700_Helicoptero_RC.blend"
DEFAULT_PREVIEW = REPO_ROOT / ".tools" / "heli25" / "hx700-preview.glb"
DEFAULT_PROFILES = REPO_ROOT / ".tools" / "heli25" / "hx700-rotor-profiles.json"
MANIFEST = REPO_ROOT / "assets" / "aircraft" / "hx-700" / "source-manifest.json"
GLB_DESTINATIONS = (
    REPO_ROOT / "assets" / "aircraft" / "hx-700" / "hx-700.glb",
    REPO_ROOT / "app" / "assets" / "aircraft" / "hx-700" / "hx-700.glb",
)
PROFILE_DESTINATIONS = (
    REPO_ROOT / "assets" / "aircraft" / "hx-700" / "rotor_profiles.json",
    REPO_ROOT / "app" / "assets" / "aircraft" / "hx-700" / "rotor_profiles.json",
)
EXPECTED_SOURCE_SHA256 = "cc2301bbc4fd6aa84474fb0a33de37fe721fd2ecab6e806ceafbcc6953a795cb"
EXPECTED_PREVIEW_SHA256 = "88424432c8cbfbc7c7278aa9c72e2188e138aa3551c2c1cf815494db281ce764"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def copy_verified(source: Path, destination: Path, replace: bool, expected_hash: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        current = sha256(destination)
        if current == expected_hash:
            return
        if not replace:
            raise FileExistsError(
                f"Refusing to replace {destination}; pass --replace after reviewing the new GLB."
            )
    shutil.copyfile(source, destination)
    if sha256(destination) != expected_hash:
        raise IOError(f"Copied asset hash mismatch: {destination}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path, default=DEFAULT_PREVIEW)
    parser.add_argument("--profiles", type=Path, default=DEFAULT_PROFILES)
    parser.add_argument("--replace", action="store_true", help="replace a differing installed GLB")
    args = parser.parse_args()

    source = SOURCE_BLEND.resolve(strict=True)
    preview = args.preview.resolve(strict=True)
    profiles = args.profiles.resolve(strict=True)
    if sha256(source) != EXPECTED_SOURCE_SHA256:
        raise SystemExit("Supplied HX-700 Blender source hash changed; repeat the source audit first.")
    if sha256(preview) != EXPECTED_PREVIEW_SHA256:
        raise SystemExit("Preview GLB hash differs from the reviewed static export.")
    for artifact in (preview, profiles):
        try:
            artifact.relative_to((REPO_ROOT / ".tools").resolve())
        except ValueError as error:
            raise SystemExit("Export inputs must stay under the ignored repository .tools directory.") from error
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    runtime_asset = manifest.get("runtime_asset", {})
    profile_info = runtime_asset.get("rotor_profiles", {})
    if runtime_asset.get("sha256") != EXPECTED_PREVIEW_SHA256:
        raise SystemExit("Source manifest GLB hash is not the reviewed static export.")
    expected_profile_hash = profile_info.get("sha256")
    if not expected_profile_hash or sha256(profiles) != expected_profile_hash:
        raise SystemExit("Rotor profile hash does not match source-manifest.json.")
    profile_payload = json.loads(profiles.read_text(encoding="utf-8"))
    if profile_payload.get("schema") != profile_info.get("schema") \
            or profile_payload.get("algorithm") != profile_info.get("algorithm") \
            or profile_payload.get("source_glb_sha256") != EXPECTED_PREVIEW_SHA256:
        raise SystemExit("Rotor profile metadata is not bound to the reviewed GLB.")
    if profiles.stat().st_size != profile_info.get("size_bytes"):
        raise SystemExit("Rotor profile size does not match source-manifest.json.")

    for destination in GLB_DESTINATIONS:
        copy_verified(preview, destination, args.replace, EXPECTED_PREVIEW_SHA256)
        print(f"{destination.relative_to(REPO_ROOT)}  {sha256(destination)}  {destination.stat().st_size} bytes")
    for destination in PROFILE_DESTINATIONS:
        copy_verified(profiles, destination, args.replace, expected_profile_hash)
        print(f"{destination.relative_to(REPO_ROOT)}  {sha256(destination)}  {destination.stat().st_size} bytes")
    if sha256(source) != EXPECTED_SOURCE_SHA256:
        raise SystemExit("Supplied Blender source changed during the copy step.")
    print(f"source unchanged  {EXPECTED_SOURCE_SHA256}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
