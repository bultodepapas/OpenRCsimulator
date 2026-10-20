"""Download and export Poly Haven's Old Tyre for RC trackside dressing.

Download the pinned 1K glTF package once with CPython:
    python tools/landscape/export_track_tyre.py --download-source

Rebuild the Godot GLB with Blender 5.2.2:
    blender --background --factory-startup --python tools/landscape/export_track_tyre.py

The supplier mesh, UVs and PBR maps are unchanged. This script only packs the
official glTF package into a single runtime GLB and records its measurements.
"""

from __future__ import annotations

import hashlib
import json
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/source-deliveries/old-tyre-polyhaven"
MANIFEST = SOURCE / "source-manifest.json"
OUTPUT = ROOT / "app/assets/landscape/track-tyre/old-tyre-1k.glb"
ASSET_ID = "old_tyre"
API_INFO = f"https://api.polyhaven.com/info/{ASSET_ID}"
API_FILES = f"https://api.polyhaven.com/files/{ASSET_ID}"
EXPECTED_FILES_HASH = "8b7362724dd9d54081fe99703e32f434f75d1f0e"
EXPECTED_SOURCE_TRIANGLES = 2880
EXPECTED_DIMENSIONS_MM = (600.0, 165.0, 600.0)


def _fetch(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "Mozilla/5.0 OpenRCsimulator asset intake"})
    with urlopen(request, timeout=60) as response:
        return response.read()


def download_source() -> None:
    info = json.loads(_fetch(API_INFO))
    files = json.loads(_fetch(API_FILES))
    if info.get("files_hash") != EXPECTED_FILES_HASH:
        raise RuntimeError("Poly Haven file catalog changed; review the source before updating")
    if info.get("authors") != {"MP": "All"} or info.get("polycount") != EXPECTED_SOURCE_TRIANGLES:
        raise RuntimeError("Poly Haven author or mesh triangle count changed")
    if any(abs(float(a) - b) > 0.01 for a, b in zip(info["dimensions"], EXPECTED_DIMENSIONS_MM)):
        raise RuntimeError("Poly Haven model dimensions changed")

    selected = files["gltf"]["1k"]["gltf"]
    wanted = {"old_tyre.bin", "textures/old_tyre_diff_1k.jpg",
              "textures/old_tyre_arm_1k.jpg", "textures/old_tyre_nor_gl_1k.jpg"}
    if set(selected["include"]) != wanted:
        raise RuntimeError("Poly Haven glTF dependencies changed")
    entries = [("gltf/old_tyre_1k.gltf", selected)]
    entries += [("gltf/" + name, selected["include"][name]) for name in sorted(wanted)]
    records = []
    for relative, spec in entries:
        data = _fetch(spec["url"])
        md5 = hashlib.md5(data).hexdigest()  # Supplier verification token.
        if len(data) != spec["size"] or md5 != spec["md5"]:
            raise RuntimeError(f"Source size/hash mismatch: {relative}")
        destination = SOURCE / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        records.append({"path": relative, "source_url": spec["url"],
                        "bytes": len(data), "source_md5": md5,
                        "sha256": hashlib.sha256(data).hexdigest()})
    manifest = {
        "asset": "Old Tyre", "asset_id": ASSET_ID, "author": "MP",
        "asset_url": "https://polyhaven.com/a/old_tyre",
        "license": "CC0 1.0 Universal", "license_url": "https://polyhaven.com/license",
        "api_info_url": API_INFO, "api_files_url": API_FILES,
        "api_files_hash": EXPECTED_FILES_HASH,
        "downloaded_utc": datetime.now(timezone.utc).isoformat(),
        "source_dimensions_mm": info["dimensions"],
        "source_triangles": info["polycount"], "files": records,
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Downloaded {len(records)} official files into {SOURCE}")


def check_source() -> dict:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest["api_files_hash"] != EXPECTED_FILES_HASH:
        raise RuntimeError("Source manifest API hash mismatch")
    for entry in manifest["files"]:
        path = SOURCE / entry["path"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            raise RuntimeError(f"Source hash mismatch: {path}")
    return manifest


def check_runtime() -> None:
    manifest = check_source()
    data = OUTPUT.read_bytes()
    if hashlib.sha256(data).hexdigest() != manifest["runtime_derivative"]["sha256"]:
        raise RuntimeError("Runtime GLB hash mismatch")
    if data[:4] != b"glTF" or struct.unpack_from("<I", data, 8)[0] != len(data):
        raise RuntimeError("Invalid GLB header")
    json_length = struct.unpack_from("<I", data, 12)[0]
    runtime = json.loads(data[20:20 + json_length])
    bin_offset = 20 + json_length
    bin_length = struct.unpack_from("<I", data, bin_offset)[0]
    binary = data[bin_offset + 8:bin_offset + 8 + bin_length]
    source = json.loads((SOURCE / "gltf/old_tyre_1k.gltf").read_text(encoding="utf-8"))

    if len(runtime["nodes"]) != 1 or any(k in runtime["nodes"][0] for k in
            ("translation", "rotation", "scale", "matrix")):
        raise RuntimeError("Runtime tyre has an unexpected node transform")
    primitive = runtime["meshes"][0]["primitives"][0]
    source_primitive = source["meshes"][0]["primitives"][0]
    for attribute in ("POSITION", "TEXCOORD_0"):
        count = runtime["accessors"][primitive["attributes"][attribute]]["count"]
        original = source["accessors"][source_primitive["attributes"][attribute]]["count"]
        if count != original:
            raise RuntimeError(f"Runtime {attribute} count changed: {count} != {original}")
    index_count = runtime["accessors"][primitive["indices"]]["count"]
    if index_count != EXPECTED_SOURCE_TRIANGLES * 3:
        raise RuntimeError(f"Runtime triangle count changed: {index_count // 3}")
    bounds = runtime["accessors"][primitive["attributes"]["POSITION"]]
    if any(abs((hi - lo) - dimension) > 0.00001 for lo, hi, dimension in
            zip(bounds["min"], bounds["max"], (0.6, 0.6, 0.165))):
        raise RuntimeError(f"Runtime AABB changed: {bounds['min']} .. {bounds['max']}")

    expected_maps = {entry["sha256"] for entry in manifest["files"]
                     if entry["path"].endswith(".jpg")}
    actual_maps = set()
    for entry in runtime["images"]:
        view = runtime["bufferViews"][entry["bufferView"]]
        first = view.get("byteOffset", 0)
        actual_maps.add(hashlib.sha256(binary[first:first + view["byteLength"]]).hexdigest())
    if actual_maps != expected_maps:
        raise RuntimeError("Runtime GLB changed one or more supplier texture files")
    print(json.dumps({"status": "ok", "triangles": index_count // 3,
                      "aabb_min_m": bounds["min"], "aabb_max_m": bounds["max"],
                      "node_transform": "identity", "embedded_original_maps": len(actual_maps)}))


def export() -> None:
    import bpy  # Only available in Blender.

    if bpy.app.version[:3] != (5, 2, 2):
        raise RuntimeError(f"Expected Blender 5.2.2, found {bpy.app.version_string}")
    manifest = check_source()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE / "gltf/old_tyre_1k.gltf"))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError(f"Expected one supplier tyre mesh, found {len(meshes)}")
    tyre = meshes[0]
    triangle_count = sum(len(face.vertices) - 2 for face in tyre.data.polygons)
    if triangle_count != EXPECTED_SOURCE_TRIANGLES:
        raise RuntimeError(f"Unexpected supplier geometry: {triangle_count} triangles")
    if len(tyre.data.uv_layers) != 1 or len(tyre.data.materials) != 1:
        raise RuntimeError("Expected one UV map and one PBR material")

    # Godot imports the glTF Y-up frame. Keep supplier axes and scale exactly.
    bpy.ops.object.select_all(action="DESELECT")
    tyre.select_set(True)
    bpy.context.view_layer.objects.active = tyre
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB",
                              use_selection=True, export_tangents=True,
                              export_image_format="AUTO")
    manifest["runtime_derivative"] = {
        "path": OUTPUT.relative_to(ROOT).as_posix(),
        "export_script": "tools/landscape/export_track_tyre.py",
        "blender_version": bpy.app.version_string,
        "source_mesh": tyre.name, "source_vertices": len(tyre.data.vertices),
        "triangles": triangle_count,
        "embedded_maps": ["diffuse", "normal_gl", "arm"],
        "sha256": hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Exported {OUTPUT}: {triangle_count} triangles")


if __name__ == "__main__":
    if "--download-source" in sys.argv:
        download_source()
    elif "--check" in sys.argv:
        check_runtime()
    else:
        export()
