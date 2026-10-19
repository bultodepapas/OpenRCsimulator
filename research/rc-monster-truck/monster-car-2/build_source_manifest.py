#!/usr/bin/env python3
"""Generate both Monster Car 2 source manifests from their pinned inputs."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[3]
SOURCE_DELIVERY = Path("assets/source-deliveries/monster-car-2")
OUTPUTS = (
    Path("assets/vehicles/monster-car-2/source-manifest.json"),
    Path("app/assets/vehicles/monster-car-2/source-manifest.json"),
)
FILES = (
    (SOURCE_DELIVERY / "monster_truck_nitro_1.blend", "user-supplied Blender source"),
    (SOURCE_DELIVERY / "monster_truck_nitro_1.glb", "user-supplied main visual GLB"),
    (SOURCE_DELIVERY / "monster_truck_colisiones_1.glb", "user-supplied collision GLB"),
    (SOURCE_DELIVERY / "datos_simulacion_1.json", "user-supplied simulation spec"),
    (
        Path("research/rc-monster-truck/monster-car-2/visual_bake.py"),
        "authored rig bake generator",
    ),
    (Path("assets/vehicles/monster-car-2/visual_rig.bin"), "derived authored transform table"),
    (Path("assets/vehicles/monster-car-2/visual_rig.json"), "derived authored transform manifest"),
)


def build_manifest() -> dict:
    entries = []
    for path, role in FILES:
        payload = (ROOT / path).read_bytes()
        entries.append(
            {
                "path": path.as_posix(),
                "role": role,
                "bytes": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
            }
        )
    return {
        "schema": "openrc-monster-car-2-source-manifest-v1",
        "hash": "SHA-256",
        "files": entries,
    }


def encode(document: dict) -> bytes:
    return (json.dumps(document, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="compare both generated manifests without writing",
    )
    args = parser.parse_args()
    try:
        expected = encode(build_manifest())
        if args.check:
            for relative in OUTPUTS:
                target = ROOT / relative
                if not target.is_file() or target.read_bytes() != expected:
                    print(f"stale source manifest: {relative}", file=sys.stderr)
                    return 1
            print("Monster Car 2 source manifests are current")
            return 0
        for relative in OUTPUTS:
            target = ROOT / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(expected)
        print("Monster Car 2 source manifests generated")
        return 0
    except OSError as exc:
        print(f"source manifest generation failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
