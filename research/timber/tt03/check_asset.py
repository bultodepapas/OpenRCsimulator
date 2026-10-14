#!/usr/bin/env python3
"""TT-03: prove that the runtime Timber asset is the r2 delivery, byte for byte, and that every generated
artifact describes the same bytes.

Checks (all must hold):
  * app/assets/aircraft/turbo-lumber-evolution/timber.glb has the GLB SHA-256 of source-manifest.json (TT-01);
  * its LICENSE.txt is the delivery's LICENSE.txt (same hash) until decision D1 replaces it;
  * the committed timber.glb.import sidecar exists, imports as a PackedScene and points at the GLB;
  * mesh-measurements.json, geometry.json and timber_geometry.gd carry the same GLB hash / visual revision;
  * timber_model.gd's VISUAL_REVISION equals the manifest's visual revision.

    python3 research/timber/tt03/check_asset.py --check
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ASSET_DIR = ROOT / "app/assets/aircraft/turbo-lumber-evolution"
SOURCE_DIR = ROOT / "assets/aircraft/turbo-lumber-evolution"
MODEL = ROOT / "app/aircraft/timber_model.gd"
GEOMETRY_GD = ROOT / "app/aircraft/timber_geometry.gd"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    problems = []
    manifest = json.loads((SOURCE_DIR / "source-manifest.json").read_text(encoding="utf-8"))
    delivery = ROOT / manifest["delivery_root"]
    delivery_revision = manifest["delivery_revision"]
    glb_hash = manifest["key_files"]["glb"]["sha256"]
    revision = manifest["visual_revision"]
    glb = ASSET_DIR / "timber.glb"
    if not glb.exists():
        problems.append("missing %s" % glb.relative_to(ROOT))
    elif sha256(glb) != glb_hash:
        problems.append("timber.glb is not the %s export (sha256 %s != manifest %s)"
                        % (delivery_revision, sha256(glb), glb_hash))
    license_copy = ASSET_DIR / "LICENSE.txt"
    license_source = delivery / manifest["key_files"]["license"]["path"]
    if not license_copy.exists() or sha256(license_copy) != sha256(license_source):
        problems.append("LICENSE.txt in the app differs from the delivery's LICENSE.txt")
    sidecar = ASSET_DIR / "timber.glb.import"
    if not sidecar.exists():
        problems.append("missing committed sidecar timber.glb.import")
    else:
        text = sidecar.read_text(encoding="utf-8")
        if 'type="PackedScene"' not in text or 'source_file="res://assets/aircraft/turbo-lumber-evolution/timber.glb"' not in text:
            problems.append("timber.glb.import does not import the GLB as a PackedScene")
    measurements = json.loads((SOURCE_DIR / "mesh-measurements.json").read_text(encoding="utf-8"))
    if measurements["glb_sha256"] != glb_hash:
        problems.append("mesh-measurements.json measured another GLB")
    geometry = json.loads((SOURCE_DIR / "geometry.json").read_text(encoding="utf-8"))
    if geometry["revision"] != revision or geometry["inputs"]["glb_sha256"] != glb_hash:
        problems.append("geometry.json revision/hash differ from the manifest")
    if GEOMETRY_GD.exists():
        if ('(revision %s)' % revision) not in GEOMETRY_GD.read_text(encoding="utf-8").splitlines()[0]:
            problems.append("timber_geometry.gd header names another revision")
    else:
        problems.append("missing app/aircraft/timber_geometry.gd")
    if MODEL.exists():
        match = re.search(r'VISUAL_REVISION\s*:=\s*"([^"]+)"', MODEL.read_text(encoding="utf-8"))
        if not match or match.group(1) != revision:
            problems.append("timber_model.gd VISUAL_REVISION differs from the manifest (%s)" % revision)
    else:
        problems.append("missing app/aircraft/timber_model.gd")
    if problems:
        sys.exit("Timber asset check failed:\n  " + "\n  ".join(problems))
    print("Timber asset: timber.glb = %s export %s, licence copied, sidecar present, generated artifacts at revision %s"
          % (delivery_revision, glb_hash[:12], revision))


if __name__ == "__main__":
    main()
