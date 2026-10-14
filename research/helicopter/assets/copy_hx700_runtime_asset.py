#!/usr/bin/env python3
"""Copy the reviewed, static HX-700 GLB into the source and runtime asset trees.

The Blender inventory/export step remains authoritative. This script only installs
its .tools preview into the two checked-in asset locations and verifies both inputs.
It never opens or writes the supplied .blend file.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SOURCE_BLEND = REPO_ROOT / "Helicopter 3d acrobatic" / "HX-700_Helicoptero_RC.blend"
DEFAULT_PREVIEW = REPO_ROOT / ".tools" / "heli25" / "hx700-preview.glb"
DESTINATIONS = (
    REPO_ROOT / "assets" / "aircraft" / "hx-700" / "hx-700.glb",
    REPO_ROOT / "app" / "assets" / "aircraft" / "hx-700" / "hx-700.glb",
)
EXPECTED_SOURCE_SHA256 = "cc2301bbc4fd6aa84474fb0a33de37fe721fd2ecab6e806ceafbcc6953a795cb"
EXPECTED_PREVIEW_SHA256 = "88424432c8cbfbc7c7278aa9c72e2188e138aa3551c2c1cf815494db281ce764"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def copy_verified(source: Path, destination: Path, replace: bool) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        current = sha256(destination)
        if current == EXPECTED_PREVIEW_SHA256:
            return
        if not replace:
            raise FileExistsError(
                f"Refusing to replace {destination}; pass --replace after reviewing the new GLB."
            )
    shutil.copyfile(source, destination)
    if sha256(destination) != EXPECTED_PREVIEW_SHA256:
        raise IOError(f"Copied GLB hash mismatch: {destination}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path, default=DEFAULT_PREVIEW)
    parser.add_argument("--replace", action="store_true", help="replace a differing installed GLB")
    args = parser.parse_args()

    source = SOURCE_BLEND.resolve(strict=True)
    preview = args.preview.resolve(strict=True)
    if sha256(source) != EXPECTED_SOURCE_SHA256:
        raise SystemExit("Supplied HX-700 Blender source hash changed; repeat the source audit first.")
    if sha256(preview) != EXPECTED_PREVIEW_SHA256:
        raise SystemExit("Preview GLB hash differs from the reviewed static export.")
    try:
        preview.relative_to((REPO_ROOT / ".tools").resolve())
    except ValueError as error:
        raise SystemExit("Preview input must stay under the ignored repository .tools directory.") from error

    for destination in DESTINATIONS:
        copy_verified(preview, destination, args.replace)
        print(f"{destination.relative_to(REPO_ROOT)}  {sha256(destination)}  {destination.stat().st_size} bytes")
    if sha256(source) != EXPECTED_SOURCE_SHA256:
        raise SystemExit("Supplied Blender source changed during the copy step.")
    print(f"source unchanged  {EXPECTED_SOURCE_SHA256}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
