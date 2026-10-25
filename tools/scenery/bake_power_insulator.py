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
import os
import shutil
import struct
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/landscape/power-lines/insulator-source.glb"
OUTPUT = ROOT / "app/data/scenery/power_insulator.json"
EXPECTED_SHA256 = "4bea57ed1194b14ed629b89a3db82782174dc2c29b2bb62143ae4ac2c1e8ef84"
OUTPUT_HEIGHT_M = 1.1
OUTPUT_WIDTH_X_M = 0.30
OUTPUT_DEPTH_Z_M = 0.30
TARGET_TRIANGLES = 300

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

GODOT_DECIMATOR = r'''extends SceneTree

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Expected input JSON, output JSON, and target triangle count")
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not parsed is Dictionary:
		push_error("Could not parse insulator mesh input JSON")
		quit(2)
		return
	var data: Dictionary = parsed
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(0, data.positions.size(), 3):
		vertices.append(Vector3(data.positions[i], data.positions[i + 1], data.positions[i + 2]))
		normals.append(Vector3(data.normals[i], data.normals[i + 1], data.normals[i + 2]))
	for index in data.triangles:
		indices.append(index)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var imported := ImporterMesh.from_mesh(mesh)
	imported.generate_lods(25.0, 60.0, [])
	var target := int(args[2])
	var best_indices := indices
	var best_distance := absi(indices.size() / 3 - target)
	var lod_counts: Array[int] = []
	for lod in imported.get_surface_lod_count(0):
		var candidate: PackedInt32Array = imported.get_surface_lod_indices(0, lod)
		var count := candidate.size() / 3
		lod_counts.append(count)
		var distance := absi(count - target)
		if candidate.size() >= 12 and distance < best_distance:
			best_distance = distance
			best_indices = candidate
	var output := {
		"triangles": Array(best_indices),
		"lod_triangle_counts": lod_counts,
		"godot_version": Engine.get_version_info()["string"],
	}
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		push_error("Could not write decimated insulator indices")
		quit(2)
		return
	file.store_string(JSON.stringify(output))
	quit()
'''


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


def resolve_godot(explicit_path: str | None) -> Path:
    candidates = [explicit_path, os.environ.get("GODOT"), shutil.which("godot")]
    candidates.extend(
        str(ROOT / relative)
        for relative in (
            ".tools/Godot_v4.8-beta1_win64_console.exe",
            ".tools/Godot_v4.8-beta1_linux.x86_64",
        )
    )
    for candidate in candidates:
        if not candidate:
            continue
        executable = Path(candidate).expanduser()
        if not executable.is_file():
            continue
        result = subprocess.run(
            [str(executable), "--version"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        version = (result.stdout or result.stderr).strip().splitlines()
        if result.returncode == 0 and version and version[0] == "4.8.beta1.official.4d10419ca":
            return executable.resolve()
    raise FileNotFoundError(
        "Pinned Godot 4.8-beta1 is required for meshoptimizer reduction. Pass --godot PATH, "
        "set GODOT, or run app/get-godot.sh to place its pinned binary in .tools."
    )


def decimate_with_godot(
    positions: list[float], normals: list[float], triangles: list[int], godot: Path
):
    """Select the closest meshoptimizer LOD to the target using pinned Godot."""
    input_data = {"positions": positions, "normals": normals, "triangles": triangles}
    with tempfile.TemporaryDirectory(prefix="openrc_power_insulator_") as temporary:
        temporary_path = Path(temporary)
        input_path = temporary_path / "insulator-input.json"
        output_path = temporary_path / "insulator-lod.json"
        script_path = temporary_path / "reduce_insulator.gd"
        input_path.write_text(json.dumps(input_data, separators=(",", ":")), encoding="utf-8")
        script_path.write_text(GODOT_DECIMATOR, encoding="utf-8")
        result = subprocess.run(
            [
                str(godot),
                "--headless",
                "--path",
                str(ROOT / "app"),
                "--script",
                str(script_path),
                "--",
                str(input_path),
                str(output_path),
                str(TARGET_TRIANGLES),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        if result.returncode != 0 or not output_path.is_file():
            raise RuntimeError(
                "Godot meshoptimizer LOD generation failed:\n"
                f"{result.stdout}\n{result.stderr}"
            )
        reduction = json.loads(output_path.read_text(encoding="utf-8"))

    selected = [int(index) for index in reduction["triangles"]]
    if len(selected) % 3:
        raise ValueError("Godot returned an incomplete triangle list")
    if not selected or min(selected) < 0 or max(selected) >= len(positions) // 3:
        raise ValueError("Godot returned out-of-range LOD indices")

    # Compact the vertex streams to the LOD's referenced source vertices while
    # preserving the original position/normal values and deterministic order.
    used = sorted(set(selected))
    remap = {source_index: output_index for output_index, source_index in enumerate(used)}
    compact_positions = [positions[index * 3 + axis] for index in used for axis in range(3)]
    compact_normals = [normals[index * 3 + axis] for index in used for axis in range(3)]
    compact_triangles = [remap[index] for index in selected]
    retained_component_sizes = sorted(
        (len(faces) for _vertices, faces in connected_components(compact_triangles)),
        reverse=True,
    )
    metadata = {
        "method": "Godot ImporterMesh.generate_lods (meshoptimizer)",
        "godot_version": reduction["godot_version"],
        "target_triangles": TARGET_TRIANGLES,
        "lod_triangle_counts": reduction["lod_triangle_counts"],
        "source_triangles": len(triangles) // 3,
        "output_triangles": len(compact_triangles) // 3,
        "source_vertices": len(positions) // 3,
        "output_vertices": len(used),
        "output_component_triangle_counts": retained_component_sizes,
    }
    return compact_positions, compact_normals, compact_triangles, metadata


def fit_decimated_envelope(positions: list[float], normals: list[float]):
    """Restore the authored attachment envelope after the LOD drops extrema."""
    vertices = [positions[i : i + 3] for i in range(0, len(positions), 3)]
    bounds = [[min(v[axis] for v in vertices), max(v[axis] for v in vertices)] for axis in range(3)]
    sizes = [pair[1] - pair[0] for pair in bounds]
    target_sizes = [OUTPUT_WIDTH_X_M, OUTPUT_HEIGHT_M, OUTPUT_DEPTH_Z_M]
    if any(size <= 1e-12 for size in sizes):
        raise ValueError(f"Decimated insulator has degenerate bounds: {bounds}")
    scales = [target_sizes[axis] / sizes[axis] for axis in range(3)]
    centers = [(pair[0] + pair[1]) * 0.5 for pair in bounds]
    fitted_positions = []
    fitted_normals = []
    for index, vertex in enumerate(vertices):
        fitted_positions.extend(
            (
                round((vertex[0] - centers[0]) * scales[0], 9),
                round((vertex[1] - bounds[1][1]) * scales[1], 9),
                round((vertex[2] - centers[2]) * scales[2], 9),
            )
        )
        normal = normals[index * 3 : index * 3 + 3]
        transformed = tuple(normal[axis] / scales[axis] for axis in range(3))
        length = math.sqrt(sum(value * value for value in transformed))
        if length < 1e-12:
            raise ValueError(f"Degenerate decimated normal at vertex {index}")
        fitted_normals.extend(round(value / length, 9) for value in transformed)
    return fitted_positions, fitted_normals, {
        "input_bounds_m": [[round(value, 9) for value in pair] for pair in bounds],
        "axis_scales": [round(value, 9) for value in scales],
        "output_bounds_m": [
            [-OUTPUT_WIDTH_X_M * 0.5, OUTPUT_WIDTH_X_M * 0.5],
            [-OUTPUT_HEIGHT_M, 0.0],
            [-OUTPUT_DEPTH_Z_M * 0.5, OUTPUT_DEPTH_Z_M * 0.5],
        ],
    }


def build_data(document: dict, binary: bytes, digest: str, godot: Path) -> dict:
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
    source_mesh_vertices = len(ordered_source_ids)
    source_mesh_triangles = len(output_triangles) // 3
    output_positions, output_normals, output_triangles, reduction = decimate_with_godot(
        output_positions, output_normals, output_triangles, godot
    )
    output_positions, output_normals, lod_fit = fit_decimated_envelope(
        output_positions, output_normals
    )

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
            "post_lod_envelope_fit": lod_fit,
        },
        "measurements": {
            "source_vertices": source_mesh_vertices,
            "source_triangles": source_mesh_triangles,
            "output_vertices": reduction["output_vertices"],
            "output_triangles": reduction["output_triangles"],
            "source_height_m": round(source_height, 9),
            "output_height_m": OUTPUT_HEIGHT_M,
            "output_width_x_m": OUTPUT_WIDTH_X_M,
            "output_depth_z_m": OUTPUT_DEPTH_Z_M,
        },
        "reduction": reduction,
        "positions": output_positions,
        "normals": output_normals,
        "triangles": output_triangles,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify generated data matches the saved JSON")
    parser.add_argument("--godot", help="path to the pinned Godot 4.8-beta1 executable")
    args = parser.parse_args()
    digest = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    if digest != EXPECTED_SHA256:
        raise SystemExit(f"Source SHA-256 mismatch: expected {EXPECTED_SHA256}, got {digest}")
    godot = resolve_godot(args.godot)
    document, binary = read_glb(SOURCE)
    data = build_data(document, binary, digest, godot)
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
        f"{action} {OUTPUT.relative_to(ROOT)}: {data['measurements']['output_vertices']} vertices, "
        f"{data['measurements']['output_triangles']} triangles "
        f"(from {data['measurements']['source_triangles']}), "
        f"{data['selection']['component_count']} source components, "
        f"{len(data['reduction']['output_component_triangle_counts'])} retained shells"
    )
    print(
        f"Source bounds {data['selection']['source_bounds_mesh_local_m']}; "
        f"output dimensions {OUTPUT_WIDTH_X_M} × {OUTPUT_HEIGHT_M} × {OUTPUT_DEPTH_Z_M} m"
    )


if __name__ == "__main__":
    main()
