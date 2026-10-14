#!/usr/bin/env python3
"""Verify/install HELI-25c inspection outputs. No Blender dependency or source writes."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import struct
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
SOURCE = REPO / "NEW HELI/HX-700_Helicoptero_RC_1.blend"
SOURCE_SHA = "1919de349b74286bc36770ab2d7d08f743fd8a4062608d488c7e4e276103725f"
EXPECTED_GLB_SHA = "f5f7de25a586b65b0f77ab17497665cc5f47cc409de6c531cadf490676159e47"
EXPECTED_PROFILE_SHA = "e3a045e3da856cac11c53bb4a417b020d6737769d9c67a0f7370035bd01539d2"
AUTHORED = REPO / "assets/aircraft/hx-700/articulated"
RUNTIME = REPO / "app/assets/aircraft/hx-700/articulated"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def matrix(values):
    if len(values) != 12 or not all(type(v) in (int, float) and math.isfinite(v) for v in values):
        raise ValueError("Invalid affine transform.")
    return [[values[c * 3 + r] for c in range(4)] for r in range(3)] + [[0, 0, 0, 1]]


def multiply(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def verify(directory):
    if sha(SOURCE) != SOURCE_SHA:
        raise ValueError("Source identity differs from HELI-25b.")
    if sha(directory / "hx-700.glb") != EXPECTED_GLB_SHA or sha(directory / "construction.json") != EXPECTED_PROFILE_SHA:
        raise ValueError("Generated asset/profile differs from the reviewed HELI-25c bytes.")
    profile = load(directory / "construction.json")
    reference = load(directory / "neutral-reference.json")
    report = load(directory / "export-report.json")
    if profile["source"]["sha256"] != SOURCE_SHA or reference["source_sha256"] != SOURCE_SHA:
        raise ValueError("Reference/profile source mismatch.")
    if report["glb_sha256"] != EXPECTED_GLB_SHA or report["profile_sha256"] != EXPECTED_PROFILE_SHA or report["flight_admitted"] is not False:
        raise ValueError("Export report identity/purpose mismatch.")
    with (directory / "hx-700.glb").open("rb") as stream:
        magic, version, size = struct.unpack("<4sII", stream.read(12))
        length, kind = struct.unpack("<II", stream.read(8))
        if magic != b"glTF" or version != 2 or size != (directory / "hx-700.glb").stat().st_size or kind != 0x4E4F534A:
            raise ValueError("Malformed GLB header.")
        gltf = json.loads(stream.read(length))
    if any(gltf.get(k) for k in ("animations", "skins", "cameras")):
        raise ValueError("Unexpected animation/camera/skin.")
    if any("uri" in item for key in ("buffers", "images") for item in gltf.get(key, [])):
        raise ValueError("External asset dependency.")
    by_id = {b["id"]: b for b in profile["bindings"]}
    nodes = gltf["nodes"]
    if len(by_id) != 108 or len(nodes) != 108 or len(profile["linkages"]) != 9:
        raise ValueError("Unexpected node/linkage topology.")
    if {b["node"] for b in by_id.values()} != {n["name"] for n in nodes}:
        raise ValueError("Profile/GLB node sets differ.")
    if any(set(n.get("extras", {})) != {"openrc_binding_id", "openrc_binding_role"} for n in nodes):
        raise ValueError("Unqualified Blender control extras escaped filtering.")
    worlds = {}

    def world(ident, visiting=None):
        if ident in worlds:
            return worlds[ident]
        visiting = set() if visiting is None else visiting
        if ident in visiting:
            raise ValueError("Cyclic parent graph.")
        visiting.add(ident)
        row = by_id[ident]
        local = matrix(row["rest_transform"])
        worlds[ident] = multiply(world(row["parent_id"], visiting), local) if row["parent_id"] else local
        visiting.remove(ident)
        return worlds[ident]

    if {r["id"] for r in reference["frames"]} != set(by_id):
        raise ValueError("Source reference frames do not cover the exported hierarchy.")
    max_frame_error = max(abs(world(r["id"])[a][b] - matrix(r["world_transform"])[a][b])
                          for r in reference["frames"] for a in range(3) for b in range(3))
    max_position_error = max(abs(world(r["id"])[a][3] - matrix(r["world_transform"])[a][3])
                             for r in reference["frames"] for a in range(3))
    # glTF omits almost-identity rotations in the source's numerical neutral solve.
    # Bound basis and translation separately; do not call this physical precision.
    if max_frame_error > 5e-6 or max_position_error > 1e-6:
        raise ValueError(f"Source/export rest frames differ: {max_frame_error}")
    max_rod_error = 0.0
    for rod in profile["linkages"]:
        a, b = world(rod["endpoint_a"]), world(rod["endpoint_b"])
        error = abs(math.sqrt(sum((a[i][3] - b[i][3]) ** 2 for i in range(3))) - rod["length_m"])
        max_rod_error = max(max_rod_error, error)
    if max_rod_error > 2e-6:
        raise ValueError(f"Exported rod geometry differs: {max_rod_error}")
    return {"source_unchanged": True, "bindings": len(by_id), "linkages": 9,
            "max_source_basis_error": max_frame_error, "max_source_position_error_m": max_position_error,
            "max_rod_error_m": max_rod_error,
            "glb_sha256": EXPECTED_GLB_SHA, "profile_sha256": EXPECTED_PROFILE_SHA}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated", type=Path)
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    directory = args.generated.resolve() if args.generated else AUTHORED
    proof = verify(directory)
    if args.install:
        directory.relative_to((REPO / ".tools").resolve())
        # Validate all overwrite targets before changing any file.
        copies = [(directory / name, AUTHORED / name) for name in
                  ("hx-700.glb", "construction.json", "neutral-reference.json", "export-report.json")]
        copies += [(directory / name, RUNTIME / name) for name in ("hx-700.glb", "construction.json")]
        for source, dest in copies:
            if dest.exists() and sha(dest) != sha(source):
                raise ValueError(f"Refusing differing installed output: {dest}")
        for source, dest in copies:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, dest)
            if sha(source) != sha(dest):
                raise ValueError("Copy changed bytes: " + str(dest))
    elif not args.generated:
        for name in ("hx-700.glb", "construction.json"):
            if sha(AUTHORED / name) != sha(RUNTIME / name):
                raise ValueError("Authored/runtime copy differs: " + name)
    print(json.dumps(proof, indent=2))


if __name__ == "__main__":
    main()
