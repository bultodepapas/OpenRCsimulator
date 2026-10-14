#!/usr/bin/env python3
"""Build selected night-lighting runtime assets from the retained free sources.

Only Python's standard library and the pinned Pillow version are used. Source files
are read-only inputs; generated files are written under app/assets/landscape/night-lighting.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path
from typing import Any
from zipfile import ZipFile

try:
    import PIL
    from PIL import Image
except ImportError as exc:  # pragma: no cover - environment setup message
    raise SystemExit("Pillow is required; install tools/night-lighting/requirements.txt") from exc


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "assets" / "landscape" / "night-lighting"
RUNTIME_ROOT = ROOT / "app" / "assets" / "landscape" / "night-lighting"
SOURCE_MANIFEST = json.loads((SOURCE_ROOT / "PROVENANCE.json").read_text(encoding="utf-8"))
SOURCE_FILES = {entry["file"]: entry for entry in SOURCE_MANIFEST["files"]}

LAMP_SOURCE = "source/motion-security-floodlight.glb"
KENNEY_GLB = "source/campfire-pit.glb"
KENNEY_PALETTE = "source/Textures/colormap.png"
FIRE_ZIP = "source/fire-fx-40-frames.zip"

LAMP_PARTS = {
    "body": [0, 4, 5, 6, 7, 8, 14, 16],
    "lens": [2],
}
HOUSING_CENTER_NODE = 0
OPTICAL_AXIS_SOURCE_LOCAL = (0.0, 0.0, 1.0)
FIRE_FRAME_SIZE = (81, 123)
FIRE_COLUMNS = 8
FIRE_ROWS = 10
FIRE_PADDING_PX = 32
FIRE_SETS = (("b", 0), ("f", 40))
PIPELINE_VERSION = "fw67-night-lighting-v1"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_bytes(relative_path: str) -> bytes:
    path = SOURCE_ROOT / relative_path
    entry = SOURCE_FILES.get(relative_path)
    if entry is None:
        raise ValueError(f"{relative_path}: missing source provenance entry")
    data = path.read_bytes()
    if len(data) != int(entry["bytes"]):
        raise ValueError(f"{relative_path}: size differs from retained source ledger")
    actual_hash = sha256(data)
    if actual_hash != entry["sha256"]:
        raise ValueError(f"{relative_path}: SHA-256 differs from retained source ledger")
    return data


def _glb_chunks(data: bytes) -> tuple[dict[str, Any], bytes]:
    if len(data) < 20:
        raise ValueError("GLB is shorter than its header")
    magic, version, total = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or total != len(data):
        raise ValueError("expected a complete glTF 2.0 binary file")
    offset = 12
    document: dict[str, Any] | None = None
    binary: bytes | None = None
    while offset < total:
        length, kind = struct.unpack_from("<I4s", data, offset)
        offset += 8
        chunk = data[offset : offset + length]
        if len(chunk) != length:
            raise ValueError("truncated GLB chunk")
        offset += length
        if kind == b"JSON":
            document = json.loads(chunk.decode("utf-8"))
        elif kind == b"BIN\0":
            binary = chunk
    if document is None or binary is None:
        raise ValueError("GLB needs JSON and BIN chunks")
    return document, binary


def _quat_rotate(q: tuple[float, float, float, float], p: tuple[float, float, float]) -> tuple[float, float, float]:
    x, y, z, w = q
    px, py, pz = p
    # v' = v + 2 * cross(q.xyz, cross(q.xyz, v) + q.w * v)
    cx = y * pz - z * py
    cy = z * px - x * pz
    cz = x * py - y * px
    dx = cx + w * px
    dy = cy + w * py
    dz = cz + w * pz
    return (
        px + 2.0 * (y * dz - z * dy),
        py + 2.0 * (z * dx - x * dz),
        pz + 2.0 * (x * dy - y * dx),
    )


def _node_quaternion(node: dict[str, Any]) -> tuple[float, float, float, float]:
    raw = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    q = tuple(float(v) for v in raw)
    mag = math.sqrt(sum(v * v for v in q))
    if not math.isfinite(mag) or mag <= 0.0:
        raise ValueError(f"node {node.get('name', '?')}: invalid quaternion")
    return tuple(v / mag for v in q)  # type: ignore[return-value]


def _translation(node: dict[str, Any]) -> tuple[float, float, float]:
    values = tuple(float(v) for v in node.get("translation", [0.0, 0.0, 0.0]))
    if len(values) != 3 or not all(math.isfinite(v) for v in values):
        raise ValueError(f"node {node.get('name', '?')}: invalid translation")
    return values  # type: ignore[return-value]


def _scale(node: dict[str, Any]) -> tuple[float, float, float]:
    values = tuple(float(v) for v in node.get("scale", [1.0, 1.0, 1.0]))
    if len(values) != 3 or any(not math.isclose(v, 1.0, abs_tol=1e-7) for v in values):
        raise ValueError(f"node {node.get('name', '?')}: source scales changed; review bake before rebuilding")
    return values  # type: ignore[return-value]


def _rotate_y(p: tuple[float, float, float], angle: float) -> tuple[float, float, float]:
    c = math.cos(angle)
    s = math.sin(angle)
    x, y, z = p
    return (c * x + s * z, y, -s * x + c * z)


def _accessor_values(document: dict[str, Any], binary: bytes, accessor_index: int) -> tuple[list[tuple[float, ...]], dict[str, Any]]:
    accessor = document["accessors"][accessor_index]
    view = document["bufferViews"][accessor["bufferView"]]
    component_type = int(accessor["componentType"])
    type_sizes = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
    component_formats = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}
    if component_type not in component_formats or accessor["type"] not in type_sizes:
        raise ValueError("source accessor uses an unsupported component type")
    component_format = component_formats[component_type]
    component_count = type_sizes[accessor["type"]]
    item_size = struct.calcsize("<" + component_format) * component_count
    stride = int(view.get("byteStride", item_size))
    start = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    values: list[tuple[float, ...]] = []
    for i in range(int(accessor["count"])):
        fields = struct.unpack_from("<" + component_format * component_count, binary, start + i * stride)
        values.append(tuple(float(v) for v in fields))
    return values, accessor


def _primitive_arrays(document: dict[str, Any], binary: bytes, node: dict[str, Any], parent: dict[str, Any], heading: float) -> tuple[list[tuple[float, float, float]], list[tuple[float, float, float]], list[int]]:
    _scale(node)
    _scale(parent)
    mesh = document["meshes"][int(node["mesh"])]
    if len(mesh["primitives"]) != 1 or int(mesh["primitives"][0].get("mode", 4)) != 4:
        raise ValueError(f"node {node.get('name', '?')}: expected one triangle primitive")
    primitive = mesh["primitives"][0]
    position_values, position_accessor = _accessor_values(document, binary, primitive["attributes"]["POSITION"])
    normal_values, _ = _accessor_values(document, binary, primitive["attributes"]["NORMAL"])
    if position_accessor["componentType"] != 5126 or len(position_values) != len(normal_values):
        raise ValueError(f"node {node.get('name', '?')}: unsupported position/normal arrays")
    node_rotation = _node_quaternion(node)
    parent_rotation = _node_quaternion(parent)
    node_translation = _translation(node)
    parent_translation = _translation(parent)
    positions: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    for position, normal in zip(position_values, normal_values):
        local = _quat_rotate(node_rotation, (position[0], position[1], position[2]))
        in_parent = (local[0] + node_translation[0], local[1] + node_translation[1], local[2] + node_translation[2])
        world = _quat_rotate(parent_rotation, in_parent)
        relative = (world[0] + parent_translation[0], world[1] + parent_translation[1], world[2] + parent_translation[2])
        positions.append(_rotate_y(tuple(relative[k] - _PIVOT[k] for k in range(3)), heading))
        n_parent = _quat_rotate(node_rotation, (normal[0], normal[1], normal[2]))
        n_world = _quat_rotate(parent_rotation, n_parent)
        n_out = _rotate_y(n_world, heading)
        length = math.sqrt(sum(v * v for v in n_out))
        if length <= 1e-12:
            raise ValueError(f"node {node.get('name', '?')}: zero normal")
        normals.append((n_out[0] / length, n_out[1] / length, n_out[2] / length))
    if "indices" in primitive:
        index_values, index_accessor = _accessor_values(document, binary, primitive["indices"])
        if index_accessor["type"] != "SCALAR":
            raise ValueError("source indices must be scalar")
        indices = [int(row[0]) for row in index_values]
    else:
        indices = list(range(len(positions)))
    if len(indices) % 3 or any(index < 0 or index >= len(positions) for index in indices):
        raise ValueError(f"node {node.get('name', '?')}: invalid triangle indices")
    return positions, normals, indices


def _bounds(points: list[tuple[float, float, float]]) -> tuple[list[float], list[float]]:
    if not points:
        raise ValueError("cannot calculate bounds for no vertices")
    return (
        [min(point[axis] for point in points) for axis in range(3)],
        [max(point[axis] for point in points) for axis in range(3)],
    )


_PIVOT = (0.0, 0.0, 0.0)


def _append_float_array(binary: bytearray, values: list[tuple[float, ...]], target: int) -> tuple[dict[str, int], int]:
    while len(binary) % 4:
        binary.append(0)
    offset = len(binary)
    for row in values:
        binary.extend(struct.pack("<" + "f" * len(row), *row))
    view_index = _append_view(target, offset, len(binary) - offset)
    return {"view": view_index, "count": len(values)}, offset


_OUTPUT_VIEWS: list[dict[str, int]] = []


def _append_view(target: int, offset: int, length: int) -> int:
    _OUTPUT_VIEWS.append({"buffer": 0, "byteOffset": offset, "byteLength": length, "target": target})
    return len(_OUTPUT_VIEWS) - 1


def build_lamp_head(source: bytes, source_hash: str) -> tuple[bytes, dict[str, Any]]:
    global _PIVOT, _OUTPUT_VIEWS
    document, binary = _glb_chunks(source)
    nodes = document["nodes"]
    scene = document["scenes"][int(document.get("scene", 0))]
    if len(scene.get("nodes", [])) != 1:
        raise ValueError("source floodlight should have exactly one scene root")
    parent = nodes[int(scene["nodes"][0])]
    if not parent.get("children"):
        raise ValueError("source floodlight scene root has no component children")
    housing_node = nodes[HOUSING_CENTER_NODE]
    parent_rotation = _node_quaternion(parent)
    housing_local = _translation(housing_node)
    pivot_rotated = _quat_rotate(parent_rotation, housing_local)
    parent_translation = _translation(parent)
    _PIVOT = tuple(pivot_rotated[k] + parent_translation[k] for k in range(3))

    optical_node = nodes[LAMP_PARTS["lens"][0]]
    optical = _quat_rotate(_node_quaternion(optical_node), OPTICAL_AXIS_SOURCE_LOCAL)
    optical = _quat_rotate(parent_rotation, optical)
    optical_yaw = math.atan2(optical[0], optical[2])
    heading = math.pi - optical_yaw

    combined: dict[str, dict[str, list[Any]]] = {}
    for surface, node_indices in LAMP_PARTS.items():
        merged_positions: list[tuple[float, float, float]] = []
        merged_normals: list[tuple[float, float, float]] = []
        merged_indices: list[int] = []
        for node_index in node_indices:
            node = nodes[node_index]
            if "mesh" not in node:
                raise ValueError(f"selected component node {node_index} no longer contains a mesh")
            positions, normals, indices = _primitive_arrays(document, binary, node, parent, heading)
            base = len(merged_positions)
            merged_positions.extend(positions)
            merged_normals.extend(normals)
            merged_indices.extend(base + index for index in indices)
        combined[surface] = {"positions": merged_positions, "normals": merged_normals, "indices": merged_indices}

    lens_min, lens_max = _bounds(combined["lens"]["positions"])
    lens_center = [(lens_min[i] + lens_max[i]) * 0.5 for i in range(3)]
    all_positions = combined["body"]["positions"] + combined["lens"]["positions"]
    overall_min, overall_max = _bounds(all_positions)
    binary_out = bytearray()
    accessors: list[dict[str, Any]] = []
    meshes: list[dict[str, Any]] = []
    _OUTPUT_VIEWS = []
    for surface_index, surface_name in enumerate(("body", "lens")):
        shape = combined[surface_name]
        position_desc, _ = _append_float_array(binary_out, shape["positions"], 34962)
        position_min, position_max = _bounds(shape["positions"])
        position_accessor = len(accessors)
        accessors.append({"bufferView": position_desc["view"], "componentType": 5126, "count": position_desc["count"], "type": "VEC3", "min": position_min, "max": position_max})
        normal_desc, _ = _append_float_array(binary_out, shape["normals"], 34962)
        normal_accessor = len(accessors)
        accessors.append({"bufferView": normal_desc["view"], "componentType": 5126, "count": normal_desc["count"], "type": "VEC3"})
        while len(binary_out) % 4:
            binary_out.append(0)
        index_offset = len(binary_out)
        binary_out.extend(struct.pack("<" + "I" * len(shape["indices"]), *shape["indices"]))
        index_view = _append_view(34963, index_offset, len(binary_out) - index_offset)
        index_accessor = len(accessors)
        accessors.append({"bufferView": index_view, "componentType": 5125, "count": len(shape["indices"]), "type": "SCALAR", "min": [min(shape["indices"])], "max": [max(shape["indices"])]})
        meshes.append({
            "name": "HousingBody" if surface_index == 0 else "DiffuserLens",
            "primitives": [{"attributes": {"POSITION": position_accessor, "NORMAL": normal_accessor}, "indices": index_accessor, "material": surface_index, "mode": 4}],
        })
    _PIVOT = (0.0, 0.0, 0.0)
    if _OUTPUT_VIEWS[0]["byteLength"] == 0 or _OUTPUT_VIEWS[-1]["byteLength"] == 0:
        raise ValueError("optimized lamp output has an empty surface")
    body_triangles = len(combined["body"]["indices"]) // 3
    lens_triangles = len(combined["lens"]["indices"]) // 3
    # The neutral source adaptation avoids carrying the unused motion sensor's transmission extension into Godot.
    output_document = {
        "asset": {"version": "2.0", "generator": PIPELINE_VERSION},
        "scene": 0,
        "scenes": [{"name": "OneAdjustableLampHead", "nodes": [0]}],
        "nodes": [{"name": "LampHead", "children": [1, 2], "extras": {
            "unit": "m",
            "local_forward": "-Z",
            "origin": "source housing center node 0; fitted to fixture/emitter center",
            "source_sha256": source_hash,
            "conversion": "retain node 0 housing, node 2 lens, nodes 4-8 heat-sink ribs, node 14 bezel and node 16 adjustable arm; bake transforms; batch to housing and lens surfaces",
            "lens_center_local_m": [round(value, 9) for value in lens_center],
        }}, {"name": "HousingAndArm", "mesh": 0}, {"name": "SeparateLens", "mesh": 1}],
        "meshes": meshes,
        "materials": [
            {"name": "FloodHousingNeutralMatte", "pbrMetallicRoughness": {"baseColorFactor": [0.22, 0.24, 0.23, 1.0], "metallicFactor": 0.55, "roughnessFactor": 0.62}, "doubleSided": False},
            {"name": "FloodDiffuserNeutralOpal", "pbrMetallicRoughness": {"baseColorFactor": [0.78, 0.72, 0.59, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.42}, "doubleSided": False},
        ],
        "accessors": accessors,
        "bufferViews": _OUTPUT_VIEWS,
        "buffers": [{"byteLength": len(binary_out)}],
    }
    json_chunk = json.dumps(output_document, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_chunk += b" " * ((-len(json_chunk)) % 4)
    bin_chunk = bytes(binary_out)
    bin_chunk += b"\0" * ((-len(bin_chunk)) % 4)
    total_size = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    output = bytearray(struct.pack("<4sII", b"glTF", 2, total_size))
    output.extend(struct.pack("<I4s", len(json_chunk), b"JSON"))
    output.extend(json_chunk)
    output.extend(struct.pack("<I4s", len(bin_chunk), b"BIN\0"))
    output.extend(bin_chunk)
    metadata = {
        "format": "openrc-asset-derivative v1",
        "pipeline": PIPELINE_VERSION,
        "source": LAMP_SOURCE,
        "source_sha256": source_hash,
        "source_license": "CC0-1.0",
        "output": "lamp-head.glb",
        "output_sha256": sha256(bytes(output)),
        "unit": "m",
        "origin": "center of retained left housing source node 0",
        "local_forward": "-Z",
        "lens_center_local_m": [round(value, 9) for value in lens_center],
        "local_bounds_m": {"min": [round(value, 9) for value in overall_min], "max": [round(value, 9) for value in overall_max]},
        "surface_count": 2,
        "materials": ["FloodHousingNeutralMatte", "FloodDiffuserNeutralOpal"],
        "triangles": {"housing_and_arm": body_triangles, "lens": lens_triangles, "total": body_triangles + lens_triangles},
        "conversion": {
            "source_nodes": {"housing": 0, "lens": 2, "heat_sink_ribs": [4, 5, 6, 7, 8], "bezel": 14, "arm": 16},
            "omitted": "other twin head, motion sensor and wall backplate",
            "source_optical_axis": [round(value, 9) for value in optical],
            "heading_rotation_y_deg": round(math.degrees(heading), 9),
            "baked_transforms": True,
            "surface_batching": "one matte body/arm/ribs/bezel surface plus one separate lens surface",
            "emission": "none; runtime lens glow remains controlled by the lighting renderer",
        },
    }
    return bytes(output), metadata


def build_fire_atlas(source_zip: bytes) -> tuple[bytes, dict[str, Any]]:
    from io import BytesIO

    cell_width = FIRE_FRAME_SIZE[0] + FIRE_PADDING_PX * 2
    cell_height = FIRE_FRAME_SIZE[1] + FIRE_PADDING_PX * 2
    atlas = Image.new("RGBA", (cell_width * FIRE_COLUMNS, cell_height * FIRE_ROWS), (0, 0, 0, 0))
    frame_records = []
    with ZipFile(BytesIO(source_zip)) as archive:
        for set_name, first_index in FIRE_SETS:
            for frame_number in range(1, 41):
                member = f"fire_1_40/fire_1{set_name}_40_{frame_number}.png"
                with archive.open(member) as image_stream:
                    frame = Image.open(image_stream).convert("RGBA")
                if frame.size != FIRE_FRAME_SIZE:
                    raise ValueError(f"{member}: expected 81x123, got {frame.size}")
                index = first_index + frame_number - 1
                col = index % FIRE_COLUMNS
                row = index // FIRE_COLUMNS
                x = col * cell_width
                y = row * cell_height
                # Transparent gutters preserve the source alpha while allowing the color to bleed without dark seams.
                expanded = Image.new("RGBA", (cell_width, cell_height), (0, 0, 0, 0))
                pixels = frame.load()
                expanded_pixels = expanded.load()
                for py in range(frame.height):
                    left = pixels[0, py]
                    right = pixels[frame.width - 1, py]
                    for pad_x in range(FIRE_PADDING_PX):
                        expanded_pixels[pad_x, py + FIRE_PADDING_PX] = (left[0], left[1], left[2], 0)
                        expanded_pixels[FIRE_PADDING_PX + frame.width + pad_x, py + FIRE_PADDING_PX] = (right[0], right[1], right[2], 0)
                for px in range(cell_width):
                    top = expanded_pixels[px, FIRE_PADDING_PX]
                    bottom = expanded_pixels[px, FIRE_PADDING_PX + frame.height - 1]
                    for pad_y in range(FIRE_PADDING_PX):
                        expanded_pixels[px, pad_y] = (top[0], top[1], top[2], 0)
                        expanded_pixels[px, FIRE_PADDING_PX + frame.height + pad_y] = (bottom[0], bottom[1], bottom[2], 0)
                expanded.alpha_composite(frame, (FIRE_PADDING_PX, FIRE_PADDING_PX))
                atlas.alpha_composite(expanded, (x, y))
                frame_records.append({"index": index, "set": set_name, "frame": frame_number, "rect_px": [x + FIRE_PADDING_PX, y + FIRE_PADDING_PX, frame.width, frame.height]})
    output = BytesIO()
    atlas.save(output, format="PNG", optimize=False, compress_level=9)
    atlas_bytes = output.getvalue()
    metadata = {
        "output": "flames-8x10.png",
        "output_sha256": sha256(atlas_bytes),
        "source": FIRE_ZIP,
        "source_sha256": sha256(source_zip),
        "source_author": "Mikodrak (Martin Jelinek)",
        "source_license": "CC0-1.0",
        "frame_count": 80,
        "frame_size_px": list(FIRE_FRAME_SIZE),
        "layout": {"columns": FIRE_COLUMNS, "rows": FIRE_ROWS, "padding_px": FIRE_PADDING_PX, "cell_pitch_px": [cell_width, cell_height], "image_size_px": list(atlas.size), "frame_order": "40 frames fire_1b_40_1…40 then 40 frames fire_1f_40_1…40"},
        "modification": "unmodified downloaded frames placed in an RGBA atlas with transparent padded gutters; no redraw, recolor, scale or resampling",
        "frames": frame_records,
    }
    return atlas_bytes, metadata


def generated_files() -> dict[str, bytes]:
    if PIL.__version__ != "12.3.0":
        raise ValueError(f"Pillow 12.3.0 is required for deterministic atlas output; found {PIL.__version__}")
    lamp_source = source_bytes(LAMP_SOURCE)
    lamp_hash = sha256(lamp_source)
    lamp, lamp_metadata = build_lamp_head(lamp_source, lamp_hash)
    kenney_glb = source_bytes(KENNEY_GLB)
    kenney_texture = source_bytes(KENNEY_PALETTE)
    fire_zip = source_bytes(FIRE_ZIP)
    atlas, atlas_metadata = build_fire_atlas(fire_zip)

    files: dict[str, bytes] = {
        "lamp-head.glb": lamp,
        "campfire-pit.glb": kenney_glb,
        "Textures/colormap.png": kenney_texture,
        "flames-8x10.png": atlas,
        "LICENSES.md": runtime_licenses(),
        "licenses/kenney-survival-kit-LICENSE.txt": (SOURCE_ROOT / "licenses" / "kenney-survival-kit-LICENSE.txt").read_bytes(),
        "licenses/mikodrak-YoudBetterReadMe.txt": (SOURCE_ROOT / "licenses" / "mikodrak-YoudBetterReadMe.txt").read_bytes(),
    }
    manifest: dict[str, Any] = {
        "format": "openrc-asset-derivative v1",
        "track": "FW-67",
        "pipeline": PIPELINE_VERSION,
        "source_manifest": "assets/landscape/night-lighting/PROVENANCE.json",
        "dependencies": {"python": "3.11+", "Pillow": "12.3.0"},
        "assets": {"lamp_head": lamp_metadata, "campfire_base": {
            "source": KENNEY_GLB,
            "source_sha256": sha256(kenney_glb),
            "palette_source": KENNEY_PALETTE,
            "palette_sha256": sha256(kenney_texture),
            "source_author": "Kenney",
            "source_license": "CC0-1.0",
            "output": "campfire-pit.glb",
            "output_sha256": sha256(kenney_glb),
            "scale": 3.6,
            "visual_scale_owner": "campfire helper ScaledVisuals child; campfire root position remains parent-owned",
            "source_bounds_m": {"x": 0.2777686, "y": 0.1090655, "z": 0.2692302},
            "runtime_bounds_m_approx": {"x": 0.999967, "y": 0.392636, "z": 0.969229},
            "ground_origin": "GLB root at local y=0; scaling is parent-side uniform, leaving the ground plane fixed",
            "modification": "unmodified source GLB and palette retained; no non-redistributable pack files included",
        }, "fire_atlas": atlas_metadata},
        "runtime_files": [{"path": path, "sha256": sha256(data), "bytes": len(data)} for path, data in sorted(files.items())],
    }
    files["asset-manifest.json"] = (json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
    return files


def runtime_licenses() -> bytes:
    text = """# Runtime landscape night-lighting assets

Selected originals and derivatives bundled for FW-67. All listed sources are CC0-1.0; the original author notes and source evidence are retained below.

## Lamp head and adjustable floodlight

- Innerscene, Security Motion Floodlight: https://www.innerscene.com/tools/library/3d-parts/security-motion-floodlight-d771cce2
- License: CC0-1.0. The source asset page labels the original model CC0; terms checked 2026-10-13.
- Runtime file: `lamp-head.glb`, adapted from the retained twin original by removing the other head/sensor/backplate, baking the fixture transforms, batching body surfaces, and retaining an independent lens surface. No baked emission or transmission is used.
- Source and derivative hashes are in `asset-manifest.json` and `assets/landscape/night-lighting/PROVENANCE.json`.

## Campfire base and flame atlas

- Kenney, Survival Kit 2.0, `campfire-pit.glb` and `Textures/colormap.png`: https://kenney.nl/assets/survival-kit
- Kenney's original CC0 license is retained at `licenses/kenney-survival-kit-LICENSE.txt`.
- Mikodrak (Martin Jelinek), Fire FX: https://opengameart.org/content/fire-fx-burning-fire-animation
- License: CC0-1.0. The author's unmodified note is retained at `licenses/mikodrak-YoudBetterReadMe.txt`.
- `flames-8x10.png` contains the two original 40-frame PNG sequences at their native 81×123 pixels, packed with transparent gutters. The source ZIP is not shipped.

CC0 legal text: https://creativecommons.org/publicdomain/zero/1.0/legalcode
"""
    return text.encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="compare generated bytes to the checked-in runtime assets without writing")
    args = parser.parse_args()
    expected = generated_files()
    differences = []
    for relative_path, contents in expected.items():
        destination = RUNTIME_ROOT / relative_path
        if args.check:
            if not destination.is_file() or destination.read_bytes() != contents:
                differences.append(relative_path)
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(contents)
    if args.check:
        if differences:
            print("runtime assets differ from deterministic build:", *differences, sep="\n  ", file=sys.stderr)
            return 1
        print(f"night-lighting assets match deterministic build ({len(expected)} files)")
        return 0
    print(f"built {len(expected)} runtime files under {RUNTIME_ROOT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
