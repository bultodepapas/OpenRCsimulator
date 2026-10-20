"""Extract one mint pin-insulator assembly from the credited CC0 pole GLB.

The source is a single textured mesh. This tool keeps the source triangle
components inside the audited positive-X crossarm-insulator envelope; it does
not create or fill any geometry. The stored source mesh has metre units.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/landscape/power-lines/insulator-source.glb"
OUTPUT = ROOT / "app/data/scenery/power_insulator.json"
EXPECTED_SHA256 = "4bea57ed1194b14ed629b89a3db82782174dc2c29b2bb62143ae4ac2c1e8ef84"
OUTPUT_HEIGHT_M = 1.1
OUTPUT_WIDTH_X_M = 0.30
OUTPUT_DEPTH_Z_M = 0.30

# The base-color atlas inspection locates the mint-glass pin on the positive-X
# side of the crossarm. Select all its small connected hardware/glass pieces,
# excluding broad line stubs, by this fixed source-space envelope.
PIN_ENVELOPE = {
    "min_x": 0.90,
    "max_x": 1.12,
    "min_y": 8.50,
    "max_y": 8.78,
    "min_z": 0.10,
    "max_z": 0.30,
    "max_x_extent": 0.30,
    "max_z_extent": 0.30,
}
EXPECTED_COMPONENTS = 47
EXPECTED_VERTICES = 1192
EXPECTED_TRIANGLES = 1488


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


def read_accessor(document: dict, binary: bytes, accessor_index: int) -> list:
    accessor = document["accessors"][accessor_index]
    view = document["bufferViews"][accessor["bufferView"]]
    if view.get("buffer", 0) != 0:
        raise ValueError("Only the source GLB's embedded buffer is supported")
    component_type = accessor["componentType"]
    component_format = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}.get(component_type)
    component_size = {5121: 1, 5123: 2, 5125: 4, 5126: 4}.get(component_type)
    if component_format is None:
        raise ValueError(f"Unsupported accessor component type: {component_type}")
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}.get(accessor["type"])
    if width is None:
        raise ValueError(f"Unsupported accessor type: {accessor['type']}")
    stride = view.get("byteStride", width * component_size)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    result = []
    for index in range(accessor["count"]):
        row = struct.unpack_from("<" + component_format * width, binary, start + index * stride)
        result.append(row[0] if width == 1 else row)
    return result


def connected_components(indices: list[int]) -> list[tuple[set[int], list[tuple[int, int, int]]]]:
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
    vertices_by_root: dict[int, set[int]] = defaultdict(set)
    faces_by_root: dict[int, list[tuple[int, int, int]]] = defaultdict(list)
    for face in faces:
        root = find(face[0])
        vertices_by_root[root].update(face)
        faces_by_root[root].append(face)
    return [(vertices_by_root[root], faces_by_root[root]) for root in faces_by_root]


def bounds_for(vertices: set[int], positions: list[tuple[float, float, float]]) -> list[tuple[float, float]]:
    return [
        (min(positions[index][axis] for index in vertices), max(positions[index][axis] for index in vertices))
        for axis in range(3)
    ]


def select_pin_components(positions: list[tuple[float, float, float]], indices: list[int]):
    selected = []
    for vertex_ids, faces in connected_components(indices):
        bounds = bounds_for(vertex_ids, positions)
        x_bounds, y_bounds, z_bounds = bounds
        if (
            x_bounds[0] >= PIN_ENVELOPE["min_x"]
            and x_bounds[1] <= PIN_ENVELOPE["max_x"]
            and y_bounds[0] >= PIN_ENVELOPE["min_y"]
            and y_bounds[1] <= PIN_ENVELOPE["max_y"]
            and z_bounds[0] >= PIN_ENVELOPE["min_z"]
            and z_bounds[1] <= PIN_ENVELOPE["max_z"]
            and x_bounds[1] - x_bounds[0] <= PIN_ENVELOPE["max_x_extent"]
            and z_bounds[1] - z_bounds[0] <= PIN_ENVELOPE["max_z_extent"]
        ):
            selected.append((vertex_ids, faces, bounds))
    return selected


def build_data(document: dict, binary: bytes, digest: str) -> dict:
    mesh = next(mesh for mesh in document["meshes"] if mesh.get("name") == "power-pole_body")
    if len(mesh["primitives"]) != 1:
        raise ValueError("Expected the retained source mesh's single primitive")
    primitive = mesh["primitives"][0]
    if primitive.get("mode", 4) != 4:
        raise ValueError("Expected triangle-list source geometry")
    positions = read_accessor(document, binary, primitive["attributes"]["POSITION"])
    normals = read_accessor(document, binary, primitive["attributes"]["NORMAL"])
    indices = [int(index) for index in read_accessor(document, binary, primitive["indices"])]
    if len(positions) != len(normals):
        raise ValueError("Source position and normal accessors differ in size")

    selected = select_pin_components(positions, indices)
    source_vertices = set().union(*(vertices for vertices, _faces, _bounds in selected)) if selected else set()
    source_faces = [face for _vertices, faces, _bounds in selected for face in faces]
    if (len(selected), len(source_vertices), len(source_faces)) != (
        EXPECTED_COMPONENTS,
        EXPECTED_VERTICES,
        EXPECTED_TRIANGLES,
    ):
        raise ValueError(
            "Insulator source extraction changed: "
            f"components={len(selected)}, vertices={len(source_vertices)}, triangles={len(source_faces)}"
        )

    source_bounds = bounds_for(source_vertices, positions)
    x_center = (source_bounds[0][0] + source_bounds[0][1]) * 0.5
    y_base, y_tip = source_bounds[1]
    z_center = (source_bounds[2][0] + source_bounds[2][1]) * 0.5
    source_height = y_tip - y_base
    source_width_x = source_bounds[0][1] - source_bounds[0][0]
    source_depth_z = source_bounds[2][1] - source_bounds[2][0]
    if source_height <= 0:
        raise ValueError("Selected pin insulator has no positive source height")
    scale_x = OUTPUT_WIDTH_X_M / source_width_x
    scale_y = OUTPUT_HEIGHT_M / source_height
    scale_z = OUTPUT_DEPTH_Z_M / source_depth_z

    ordered_source_ids = sorted(source_vertices)
    output_index = {source_id: index for index, source_id in enumerate(ordered_source_ids)}
    output_positions = []
    output_normals = []
    for source_id in ordered_source_ids:
        x, y, z = positions[source_id]
        nx, ny, nz = normals[source_id]
        output_positions.extend(
            (
                round((x - x_center) * scale_x, 9),
                round(-(y - y_base) * scale_y, 9),
                round((z - z_center) * scale_z, 9),
            )
        )
        # Apply the inverse-transpose of diag(scale_x, -scale_y, scale_z).
        transformed_normal = (nx / scale_x, -ny / scale_y, nz / scale_z)
        length = math.sqrt(sum(value * value for value in transformed_normal))
        if length < 1e-12:
            raise ValueError(f"Degenerate source normal at vertex {source_id}")
        output_normals.extend(round(value / length, 9) for value in transformed_normal)

    # Keep each GLB triangle's order. Reflecting Y reverses handedness, so the
    # resulting faces already use the clockwise convention expected by Godot.
    output_triangles = []
    for a, b, c in source_faces:
        output_triangles.extend((output_index[a], output_index[b], output_index[c]))

    root_node = next(node for node in document["nodes"] if node.get("mesh") == 0)
    translation = root_node.get("translation", [0.0, 0.0, 0.0])
    return {
        "format": "openrc-power-insulator-profile-v1",
        "source": {
            "asset": "insulator-source.glb",
            "title": "Power Pole",
            "author": "Grab3D / Cozy Construction Kit",
            "url": "https://grab3d.com/models/city/power-pole/",
            "license": "CC0 1.0 Universal",
            "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
            "license_text_file": "assets/landscape/power-lines/insulator-source-license.txt",
            "retrieved_utc": "2026-10-20",
            "sha256": digest,
        },
        "source_mesh": mesh["name"],
        "source_material": document["materials"][primitive["material"]]["name"],
        "selection": {
            "description": "Mint pin insulator on the positive-X crossarm, selected as original index-connected components by its audited source-space envelope; broad line-stub components are excluded.",
            "component_count": len(selected),
            "source_bounds_mesh_local_m": [[round(a, 9), round(b, 9)] for a, b in source_bounds],
            "source_node_translation_m": [round(value, 9) for value in translation],
            "source_base_y_m": round(y_base, 9),
            "source_tip_y_m": round(y_tip, 9),
        },
        "transform": {
            "source_axes": {"horizontal_x": "+X", "vertical_y": "+Y", "depth_z": "+Z"},
            "source_units": "metres",
            "output_attachment": "source lower/base face centered in XZ at [0,0,0]",
            "output_top_y_m": 0.0,
            "output_tip_y_m": -OUTPUT_HEIGHT_M,
            "axis_scales": [round(scale_x, 9), round(scale_y, 9), round(scale_z, 9)],
            "non_uniform_fit": True,
            "vertical_flip": True,
            "triangle_order": "source indices retained; Y reflection changes handedness to Godot clockwise",
        },
        "measurements": {
            "source_vertices": len(ordered_source_ids),
            "source_triangles": len(source_faces),
            "source_height_m": round(source_height, 9),
            "output_height_m": OUTPUT_HEIGHT_M,
            "output_width_x_m": OUTPUT_WIDTH_X_M,
            "output_depth_z_m": OUTPUT_DEPTH_Z_M,
        },
        "positions": output_positions,
        "normals": output_normals,
        "triangles": output_triangles,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify generated data matches the saved JSON")
    args = parser.parse_args()
    digest = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    if digest != EXPECTED_SHA256:
        raise SystemExit(f"Source SHA-256 mismatch: expected {EXPECTED_SHA256}, got {digest}")
    document, binary = read_glb(SOURCE)
    data = build_data(document, binary, digest)
    output_text = json.dumps(data, separators=(",", ":")) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != output_text:
            raise SystemExit(f"Generated data differs from {OUTPUT.relative_to(ROOT)}")
        action = "Verified"
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(output_text, encoding="utf-8")
        action = "Wrote"
    print(
        f"{action} {OUTPUT.relative_to(ROOT)}: {data['measurements']['source_vertices']} vertices, "
        f"{data['measurements']['source_triangles']} triangles, {data['selection']['component_count']} components"
    )
    print(
        f"Source bounds {data['selection']['source_bounds_mesh_local_m']}; "
        f"output dimensions {OUTPUT_WIDTH_X_M} × {OUTPUT_HEIGHT_M} × {OUTPUT_DEPTH_Z_M} m"
    )


if __name__ == "__main__":
    main()
