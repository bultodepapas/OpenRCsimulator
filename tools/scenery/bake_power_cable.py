"""Extract a normalized, thin cable profile from the credited rope-bridge GLB.

This keeps one downloaded rope component's vertices and triangle topology. It
does not generate a curve or mesh. Ring centers carry the source sag profile;
radial directions are retained while their radius is made independently
scalable at runtime.
"""
from __future__ import annotations

import hashlib
import argparse
import json
import math
import struct
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/landscape/power-lines/rope-bridge-jeremyeyring.glb"
OUTPUT = ROOT / "app/data/scenery/power_cable.json"
EXPECTED_SHA256 = "b7265d3fb24261844e61eefd02aa831c44a538a860e8606655300712787f35ef"
RADIUS_M = 0.025
SOURCE_METRES_PER_UNIT = 1.0e-6


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        raise ValueError(f"Not a GLB file: {path}")
    version, total_length = struct.unpack_from("<II", data, 4)
    if version != 2 or total_length != len(data):
        raise ValueError("Expected a complete glTF 2.0 binary file")
    document = None
    binary = None
    offset = 12
    while offset < len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset : offset + chunk_length]
        offset += chunk_length
        if chunk_type == 0x4E4F534A:
            document = json.loads(chunk.decode("utf-8").rstrip(" \t\r\n\0"))
        elif chunk_type == 0x004E4942:
            binary = chunk
    if document is None or binary is None:
        raise ValueError("GLB needs JSON and BIN chunks")
    return document, binary


def accessor_values(document: dict, binary: bytes, accessor_index: int) -> list:
    accessor = document["accessors"][accessor_index]
    view = document["bufferViews"][accessor["bufferView"]]
    if view.get("buffer", 0) != 0:
        raise ValueError("Only the source GLB's embedded buffer is supported")
    component = accessor["componentType"]
    component_format = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}.get(component)
    component_size = {5121: 1, 5123: 2, 5125: 4, 5126: 4}.get(component)
    if component_format is None:
        raise ValueError(f"Unsupported accessor component type: {component}")
    type_width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}.get(accessor["type"])
    if type_width is None:
        raise ValueError(f"Unsupported accessor type: {accessor['type']}")
    width = type_width * component_size
    stride = view.get("byteStride", width)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    values = []
    for index in range(accessor["count"]):
        row = struct.unpack_from("<" + component_format * type_width, binary, start + index * stride)
        values.append(row[0] if type_width == 1 else row)
    return values


def components(indices: list[int]) -> list[tuple[set[int], list[tuple[int, int, int]]]]:
    parent: dict[int, int] = {}

    def find(vertex: int) -> int:
        parent.setdefault(vertex, vertex)
        while parent[vertex] != vertex:
            parent[vertex] = parent[parent[vertex]]
            vertex = parent[vertex]
        return vertex

    def union(left: int, right: int) -> None:
        left_root, right_root = find(left), find(right)
        if left_root != right_root:
            parent[right_root] = left_root

    faces = [tuple(indices[i : i + 3]) for i in range(0, len(indices), 3)]
    for a, b, c in faces:
        union(a, b)
        union(a, c)
    grouped_vertices: dict[int, set[int]] = defaultdict(set)
    grouped_faces: dict[int, list[tuple[int, int, int]]] = defaultdict(list)
    for face in faces:
        root = find(face[0])
        grouped_vertices[root].update(face)
        grouped_faces[root].append(face)
    return [(grouped_vertices[root], grouped_faces[root]) for root in grouped_faces]


def select_component(document: dict, binary: bytes) -> tuple[list[tuple[float, float, float]], list[int], dict]:
    mesh = next(mesh for mesh in document["meshes"] if mesh.get("name") == "Object.4-Mesh")
    primitive = next(
        primitive
        for primitive in mesh["primitives"]
        if document["materials"][primitive["material"]].get("name") == "rope"
    )
    positions = accessor_values(document, binary, primitive["attributes"]["POSITION"])
    indices = accessor_values(document, binary, primitive["indices"])
    indices = [int(index) for index in indices]
    candidates = []
    for vertex_ids, faces in components(indices):
        if len(vertex_ids) != 81 or len(faces) != 128:
            continue
        xs = [positions[index][0] for index in vertex_ids]
        mean_y = sum(positions[index][1] for index in vertex_ids) / len(vertex_ids)
        if mean_y <= 0 or min(xs) <= 0:
            continue
        candidates.append((max(xs) - min(xs), vertex_ids, faces))
    if not candidates:
        raise ValueError("Could not find a positive-X, positive-Y 81-vertex, 128-face rope component")
    # The longest of the matching positive-side handrails is the full side span.
    _, vertex_ids, faces = max(candidates, key=lambda candidate: candidate[0])
    return positions, indices, {"vertices": vertex_ids, "faces": faces, "mesh": mesh["name"]}


def make_profile(document: dict, binary: bytes) -> dict:
    positions, _all_indices, component = select_component(document, binary)
    vertex_ids: set[int] = component["vertices"]
    faces: list[tuple[int, int, int]] = component["faces"]

    # The source has nine cross-sections. Its centerline axis is source X;
    # each ring contains eight unique perimeter positions and one UV seam copy.
    by_ring: list[list[int]] = []
    for vertex_id in sorted(vertex_ids, key=lambda i: (positions[i][0], i)):
        x = positions[vertex_id][0]
        if not by_ring or abs(x - positions[by_ring[-1][0]][0]) > 20_000.0:
            by_ring.append([vertex_id])
        else:
            by_ring[-1].append(vertex_id)
    if len(by_ring) != 9 or any(len(ring) != 9 for ring in by_ring):
        raise ValueError(f"Expected 9 rings of 9 source vertices; got {[len(ring) for ring in by_ring]}")
    ring_centers = []
    for ring in by_ring:
        ring_centers.append(tuple(sum(positions[i][axis] for i in ring) / len(ring) for axis in range(3)))

    start_x, end_x = ring_centers[0][0], ring_centers[-1][0]
    if end_x <= start_x:
        raise ValueError("Selected cable ring centers do not progress along source +X")
    endpoint_z = (ring_centers[0][2] + ring_centers[-1][2]) * 0.5
    lowest_z = min(center[2] for center in ring_centers)
    sag_depth = endpoint_z - lowest_z
    if sag_depth <= 0:
        raise ValueError("Selected rope centerline does not sag below its ends")

    ordered_source_ids = [vertex_id for ring in by_ring for vertex_id in sorted(ring)]
    new_index = {source_id: index for index, source_id in enumerate(ordered_source_ids)}
    vertex_records = []
    for ring_index, ring in enumerate(by_ring):
        cx, cy, cz = ring_centers[ring_index]
        t = 0.0 if ring_index == 0 else (1.0 if ring_index == len(by_ring) - 1 else (cx - start_x) / (end_x - start_x))
        sag = 0.0 if ring_index in (0, len(by_ring) - 1) else (cz - endpoint_z) / sag_depth
        for source_id in sorted(ring):
            _x, y, z = positions[source_id]
            dy, dz = y - cy, z - cz
            radial_length = math.hypot(dy, dz)
            if radial_length < 1e-9:
                raise ValueError("Degenerate source cross-section vertex")
            # Local runtime basis is (along, up, side). Source axes are
            # (along, side, up), so this stores the source direction as
            # (longitudinal, up, side) and excludes small axial offsets.
            radial = [0.0, (dz / radial_length) * RADIUS_M, (dy / radial_length) * RADIUS_M]
            vertex_records.append({"center": [round(t, 9), round(sag, 9), 0.0], "radial": [round(value, 9) for value in radial]})

    # Swapping source Y/Z already reverses handedness, converting glTF's CCW
    # faces to Godot's clockwise order. Reversing indices again points inward.
    triangles = []
    for a, b, c in faces:
        triangles.extend((new_index[a], new_index[b], new_index[c]))

    if len(vertex_records) != 81 or len(triangles) != 128 * 3:
        raise AssertionError("Unexpected extracted topology")
    # Geometry-level check catches the handedness mistake that declarations
    # alone miss. Evaluate a representative 96 m span with 2.3% sag.
    points = [
        [v["center"][0] * 96.0 + v["radial"][0],
         v["center"][1] * 96.0 * 0.023 + v["radial"][1], v["radial"][2]]
        for v in vertex_records
    ]
    for offset in range(0, len(triangles), 3):
        a, b, c = triangles[offset:offset + 3]
        u = [points[c][axis] - points[a][axis] for axis in range(3)]
        v = [points[b][axis] - points[a][axis] for axis in range(3)]
        normal = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
        radial = [sum(vertex_records[i]["radial"][axis] for i in (a, b, c)) for axis in range(3)]
        if sum(normal[axis] * radial[axis] for axis in range(3)) <= 0:
            raise ValueError("Imported cable face points inward")
    profile = {
        "format": "openrc-power-cable-profile-v1",
        "source": {
            "asset": "rope-bridge-jeremyeyring.glb",
            "title": "rope bridge - Free Model By Jeremy Eyring",
            "author": "Jeremy Eyring",
            "url": "https://poly.pizza/m/88e4zjTShuY",
            "license": "Creative Commons Attribution 3.0 (CC BY 3.0)",
            "license_url": "https://creativecommons.org/licenses/by/3.0/",
            "attribution": "Rope Bridge by Jeremy Eyring, licensed under CC BY 3.0.",
            "retrieved_utc": "2026-10-20",
            "sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        },
        "source_mesh": component["mesh"],
        "source_material": "rope",
        "transform": {
            "source_coordinate_axes": {"span": "+X", "side": "+Y", "up": "+Z"},
            "source_metres_per_unit": SOURCE_METRES_PER_UNIT,
            "center": "source ring-center X normalized to [0,1]; source ring-center Z normalized so ends are 0 and the lowest center ring is -1",
            "radial": "source Y/Z cross-section directions mapped to runtime [along, up, side] and normalized to radius_m; source axial offsets are omitted",
            "radius_m": RADIUS_M,
            "godot_clockwise": True,
            "face_order": "source GLB indices retained; the Y/Z axis swap produces Godot clockwise faces",
        },
        "measurements": {
            "source_vertices": 81,
            "source_triangles": 128,
            "centerline_rings": len(by_ring),
            "source_span_m": round((end_x - start_x) * SOURCE_METRES_PER_UNIT, 9),
            "source_centerline_sag_m": round(sag_depth * SOURCE_METRES_PER_UNIT, 9),
            "source_centerline_sag_ratio": round(sag_depth / (end_x - start_x), 9),
            "endpoint_center_z_source_m": round(endpoint_z * SOURCE_METRES_PER_UNIT, 9),
            "lowest_center_z_source_m": round(lowest_z * SOURCE_METRES_PER_UNIT, 9),
        },
        "vertices": vertex_records,
        "triangles": triangles,
    }
    return profile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    digest = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    if digest != EXPECTED_SHA256:
        raise SystemExit(f"Source SHA-256 mismatch: expected {EXPECTED_SHA256}, got {digest}")
    document, binary = read_glb(SOURCE)
    profile = make_profile(document, binary)
    text = json.dumps(profile, separators=(",", ":")) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != text:
            raise SystemExit("Cable profile differs from a fresh source extraction")
        print("Cable profile matches the source extraction; all 128 faces point outward")
        return
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}: {len(profile['vertices'])} vertices, {len(profile['triangles']) // 3} triangles")
    print(f"Centerline span {profile['measurements']['source_span_m']} m; sag ratio {profile['measurements']['source_centerline_sag_ratio']}")


if __name__ == "__main__":
    main()
