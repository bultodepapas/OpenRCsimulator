#!/usr/bin/env python3
"""Extract one pinned leafy shrub from dasy444's supplied forest glTF.

The converter keeps the source mesh, UVs, indices, material and image pixels.
It removes only gallery placement, bakes the selected node's linear transform
into the supplied vertices, and emits a standalone glTF with an identity node.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import platform
import struct
from pathlib import Path
from typing import Any


ARCHIVE_NAME = "a_forest_3_with_a_road_at_night_for_game.zip"
ARCHIVE_BYTES = 20_951_847
ARCHIVE_SHA256 = "7a6716d6e691838324e8270ec9c22b5f7793609342db579861626c3c8975bea3"
SOURCE_RELATIVE = Path("assets/landscape/vegetation/source/dasy_forest_2026")
DERIVED_RELATIVE = Path("assets/landscape/vegetation/derived/dasy_forest_2026")
SOURCE_GLTF = "scene.gltf"
SOURCE_BUFFER = "scene.bin"
MANIFEST_NAME = "conversion_manifest.json"
MANIFEST_FORMAT = "openrc-forest-shrub-conversion-manifest v1"
SOURCE_URL = "https://sketchfab.com/3d-models/a-forest-3-with-a-road-at-night-for-game-61f8c7817fe6457fb26e4814cfc48a3f"
LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"

VARIANT = {
    "id": "forest_leafy_shrub",
    "source_name": "3f84aea6648aa6cc5af5f07ee43c6056-no-bg-preview (carve.photos).003_Material_0",
    "source_material": "Material",
    "triangles": 144,
    "vertices": 96,
    "gltf": "forest_leafy_shrub.gltf",
    "texture_stem": "forest_leafy_shrub",
}

SOURCE_INPUTS = {
    "archive/" + ARCHIVE_NAME: ARCHIVE_SHA256,
    "LICENSE_FOREST.txt": "d41803d1376ea56604881809a78a13d51d1ea54f8361460cbad413ab9c35161a",
    "license.txt": "baf54b656b4fe6a746703cdf8565cf8dcbd6feba6cac2657f31f62d0be04fa93",
    "scene.bin": "d325db2e035c2ca1e6b931e4563e7532c532d96fa2552ae8bed9298d26885bc7",
    "scene.gltf": "ea53ed0559e798ca6016a38e80eb7953e8bd125167cbc04ce9fd7bca90a3da6f",
    "textures/Material.003_baseColor.png": "13bbe9b6c0e1f5f32f28a401c34364f37df43b99540354961b9a37cc2f895838",
    "textures/Material.003_normal.png": "c8b99b013c2b9cb6d9c85bb39572516f5da15d5f2a0b4c8bdce8f606ea66c4af",
    "textures/Material.004_baseColor.jpeg": "a870158464a27da3263132678e27eb60fcca06e8992e0cf929328a1fa6af01ba",
    "textures/Material.004_normal.png": "2aab315e02ad0fcb0b336a118bbd2f208bb711d56bbb96262e0ac6b320162c89",
    "textures/Material_baseColor.png": "b9358314f5f6e6ced74736f93de4a6baf69f65732d7eb27128dd5b951bb1823d",
}

ORIGINAL_ARCHIVE_ENTRIES = [
    "license.txt",
    "scene.bin",
    "scene.gltf",
    "textures/Material.003_baseColor.png",
    "textures/Material.003_normal.png",
    "textures/Material.004_baseColor.jpeg",
    "textures/Material.004_normal.png",
    "textures/Material_baseColor.png",
]

COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
COMPONENT_FORMAT = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}
COMPONENT_BYTES = {5121: 1, 5123: 2, 5125: 4, 5126: 4}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=repo_root())
    parser.add_argument("--source-dir", type=Path, default=None)
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--check", action="store_true", help="verify pinned inputs and deterministic derived outputs")
    return parser.parse_args()


def input_records(source_dir: Path, verify: bool = True) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for relative, expected in sorted(SOURCE_INPUTS.items()):
        path = source_dir / Path(relative)
        if not path.is_file():
            raise SystemExit(f"Required pinned source input missing: {path}")
        actual = sha256_file(path)
        if verify and actual != expected:
            raise SystemExit(f"Pinned input SHA-256 mismatch for {relative}: {actual}")
        records.append({"path": relative, "bytes": path.stat().st_size, "sha256": actual})
    archive = source_dir / "archive" / ARCHIVE_NAME
    if archive.stat().st_size != ARCHIVE_BYTES or sha256_file(archive) != ARCHIVE_SHA256:
        raise SystemExit("Pinned source archive size or SHA-256 changed")
    return records


def identity4() -> list[list[float]]:
    return [[1.0 if row == column else 0.0 for column in range(4)] for row in range(4)]


def multiply4(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    return [
        [sum(a[row][k] * b[k][column] for k in range(4)) for column in range(4)]
        for row in range(4)
    ]


def node_matrix(node: dict[str, Any]) -> list[list[float]]:
    matrix = node.get("matrix")
    if matrix is not None:
        if len(matrix) != 16:
            raise SystemExit(f"Invalid glTF matrix on node {node.get('name')}")
        return [[float(matrix[column * 4 + row]) for column in range(4)] for row in range(4)]
    translation = [float(value) for value in node.get("translation", (0.0, 0.0, 0.0))]
    scale = [float(value) for value in node.get("scale", (1.0, 1.0, 1.0))]
    quaternion = [float(value) for value in node.get("rotation", (0.0, 0.0, 0.0, 1.0))]
    if len(translation) != 3 or len(scale) != 3 or len(quaternion) != 4:
        raise SystemExit(f"Invalid glTF TRS on node {node.get('name')}")
    x, y, z, w = quaternion
    rotation = [
        [1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - z * w), 2.0 * (x * z + y * w)],
        [2.0 * (x * y + z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - x * w)],
        [2.0 * (x * z - y * w), 2.0 * (y * z + x * w), 1.0 - 2.0 * (x * x + y * y)],
    ]
    result = identity4()
    for row in range(3):
        for column in range(3):
            result[row][column] = rotation[row][column] * scale[column]
        result[row][3] = translation[row]
    return result


def node_world_transform(document: dict[str, Any], node_index: int) -> tuple[list[list[float]], list[int]]:
    parents: dict[int, int] = {}
    for parent_index, node in enumerate(document.get("nodes", [])):
        for child in node.get("children", []):
            if int(child) in parents:
                raise SystemExit(f"glTF node {child} has multiple parents")
            parents[int(child)] = parent_index
    chain: list[int] = []
    current: int | None = node_index
    while current is not None:
        chain.append(current)
        current = parents.get(current)
    chain.reverse()
    result = identity4()
    for index in chain:
        result = multiply4(result, node_matrix(document["nodes"][index]))
    return result, chain


def accessor_values(document: dict[str, Any], buffer: bytes, accessor_index: int) -> list[tuple[int | float, ...]]:
    accessor = document["accessors"][accessor_index]
    if "sparse" in accessor:
        raise SystemExit(f"Sparse source accessors are unsupported: {accessor_index}")
    view = document["bufferViews"][accessor["bufferView"]]
    component_type = int(accessor["componentType"])
    fmt = COMPONENT_FORMAT.get(component_type)
    component_size = COMPONENT_BYTES.get(component_type)
    component_count = COMPONENTS.get(accessor["type"])
    if fmt is None or component_size is None or component_count is None:
        raise SystemExit(f"Unsupported source accessor type at index {accessor_index}")
    if accessor.get("normalized", False):
        raise SystemExit(f"Normalized source accessor is not expected: {accessor_index}")
    element_size = component_size * component_count
    stride = int(view.get("byteStride", element_size))
    if stride < element_size:
        raise SystemExit(f"Invalid byte stride for source accessor {accessor_index}")
    offset = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    values: list[tuple[int | float, ...]] = []
    for item in range(int(accessor["count"])):
        start = offset + item * stride
        end = start + element_size
        if end > len(buffer):
            raise SystemExit(f"Source accessor {accessor_index} exceeds its binary buffer")
        values.append(struct.unpack_from("<" + fmt * component_count, buffer, start))
    return values


def accessor_bytes(document: dict[str, Any], buffer: bytes, accessor_index: int) -> bytes:
    accessor = document["accessors"][accessor_index]
    view = document["bufferViews"][accessor["bufferView"]]
    component_size = COMPONENT_BYTES.get(int(accessor["componentType"]))
    component_count = COMPONENTS.get(accessor["type"])
    if component_size is None or component_count is None:
        raise SystemExit(f"Unsupported source accessor type at index {accessor_index}")
    element_size = component_size * component_count
    stride = int(view.get("byteStride", element_size))
    if stride < element_size:
        raise SystemExit(f"Invalid byte stride for source accessor {accessor_index}")
    offset = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    chunks = []
    for item in range(int(accessor["count"])):
        start = offset + item * stride
        end = start + element_size
        if end > len(buffer):
            raise SystemExit(f"Source accessor {accessor_index} exceeds its binary buffer")
        chunks.append(buffer[start:end])
    return b"".join(chunks)


def pack_values(values: list[tuple[int | float, ...]], component_type: int) -> bytes:
    flattened = [component for value in values for component in value]
    return struct.pack("<" + COMPONENT_FORMAT[component_type] * len(flattened), *flattened) if flattened else b""


def png_metadata(data: bytes) -> dict[str, int]:
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise SystemExit("Selected source base-color image is not a valid PNG")
    width, height = struct.unpack_from(">II", data, 16)
    bit_depth, color_type = data[24], data[25]
    if (width, height, bit_depth, color_type) != (2048, 2048, 8, 6):
        raise SystemExit(f"Unexpected selected PNG dimensions/format: {(width, height, bit_depth, color_type)}")
    return {"width": width, "height": height, "bit_depth": bit_depth, "color_type": color_type}


def vector3(matrix: list[list[float]], value: tuple[int | float, ...]) -> tuple[float, float, float]:
    return tuple(sum(matrix[row][column] * float(value[column]) for column in range(3)) for row in range(3))


def normalized(value: tuple[float, float, float]) -> tuple[float, float, float]:
    length = math.sqrt(sum(component * component for component in value))
    if length <= 1e-12:
        raise SystemExit("Source normal or tangent contains a zero-length vector")
    return tuple(component / length for component in value)


def bounds(values: list[tuple[int | float, ...]], dimensions: int) -> dict[str, list[float]]:
    minimum = [min(float(value[axis]) for value in values) for axis in range(dimensions)]
    maximum = [max(float(value[axis]) for value in values) for axis in range(dimensions)]
    return {"min": minimum, "max": maximum, "size": [maximum[i] - minimum[i] for i in range(dimensions)]}


def validate_uniform_basis(linear: list[list[float]]) -> tuple[float, float]:
    columns = [[linear[row][column] for row in range(3)] for column in range(3)]
    lengths = [math.sqrt(sum(component * component for component in column)) for column in columns]
    scale = sum(lengths) / 3.0
    if scale <= 0.0 or max(abs(value - scale) for value in lengths) > 1e-5:
        raise SystemExit(f"Selected source transform is not uniform: {lengths}")
    orthogonality_error = max(
        abs(sum(columns[a][i] * columns[b][i] for i in range(3))) / (scale * scale)
        for a in range(3) for b in range(a + 1, 3)
    )
    if orthogonality_error > 1e-5:
        raise SystemExit(f"Selected source transform is not an orthogonal uniform basis: {orthogonality_error}")
    determinant = (
        linear[0][0] * (linear[1][1] * linear[2][2] - linear[1][2] * linear[2][1])
        - linear[0][1] * (linear[1][0] * linear[2][2] - linear[1][2] * linear[2][0])
        + linear[0][2] * (linear[1][0] * linear[2][1] - linear[1][1] * linear[2][0])
    )
    if determinant <= 0.0:
        raise SystemExit(f"Selected source transform reverses orientation: determinant={determinant}")
    return scale, orthogonality_error


def remap_material_textures(
    source_document: dict[str, Any], material: dict[str, Any], texture_stem: str
) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], dict[str, bytes]]:
    texture_index_map: dict[int, int] = {}
    image_index_map: dict[int, int] = {}
    sampler_index_map: dict[int, int] = {}
    output_textures: list[dict[str, Any]] = []
    output_images: list[dict[str, Any]] = []
    output_samplers: list[dict[str, Any]] = []
    output_files: dict[str, bytes] = {}
    texture_fields: list[dict[str, Any]] = []
    pbr = material.get("pbrMetallicRoughness", {})
    for info in (pbr.get("baseColorTexture"), pbr.get("metallicRoughnessTexture"), material.get("normalTexture"), material.get("occlusionTexture"), material.get("emissiveTexture")):
        if isinstance(info, dict):
            texture_fields.append(info)

    for texture_info in texture_fields:
        old_texture_index = int(texture_info["index"])
        old_texture = source_document["textures"][old_texture_index]
        old_image_index = int(old_texture["source"])
        if old_image_index in image_index_map:
            continue
        old_image = copy.deepcopy(source_document["images"][old_image_index])
        uri = old_image.get("uri")
        if not isinstance(uri, str) or "bufferView" in old_image:
            raise SystemExit(f"Expected an external source image URI at index {old_image_index}")
        source_name = Path(uri.replace("\\", "/")).name
        output_name = f"{texture_stem}_basecolor.png"
        output_path = f"textures/{output_name}"
        old_image["uri"] = output_path
        image_index_map[old_image_index] = len(output_images)
        output_images.append(old_image)
        source_path = source_document["_source_dir"] / "textures" / source_name
        output_files[output_path] = source_path.read_bytes()

    for texture_info in texture_fields:
        old_texture_index = int(texture_info["index"])
        if old_texture_index in texture_index_map:
            continue
        old_texture = copy.deepcopy(source_document["textures"][old_texture_index])
        old_texture["source"] = image_index_map[int(old_texture["source"])]
        if "sampler" in old_texture:
            old_sampler_index = int(old_texture["sampler"])
            if old_sampler_index not in sampler_index_map:
                sampler_index_map[old_sampler_index] = len(output_samplers)
                output_samplers.append(copy.deepcopy(source_document["samplers"][old_sampler_index]))
            old_texture["sampler"] = sampler_index_map[old_sampler_index]
        texture_index_map[old_texture_index] = len(output_textures)
        output_textures.append(old_texture)

    remapped_material = copy.deepcopy(material)
    pbr = remapped_material.get("pbrMetallicRoughness", {})
    for info in (pbr.get("baseColorTexture"), pbr.get("metallicRoughnessTexture"), remapped_material.get("normalTexture"), remapped_material.get("occlusionTexture"), remapped_material.get("emissiveTexture")):
        if isinstance(info, dict):
            info["index"] = texture_index_map[int(info["index"])]
    return remapped_material, output_textures, output_images, output_samplers, output_files


def source_variant(document: dict[str, Any], source_buffer: bytes) -> tuple[dict[str, Any], dict[str, bytes], dict[str, Any]]:
    config = VARIANT
    meshes = document.get("meshes", [])
    mesh_matches = [index for index, mesh in enumerate(meshes) if mesh.get("name") == config["source_name"]]
    if len(mesh_matches) != 1:
        raise SystemExit(f"Expected one source mesh named {config['source_name']}; found {len(mesh_matches)}")
    source_mesh_index = mesh_matches[0]
    source_mesh = meshes[source_mesh_index]
    if len(source_mesh.get("primitives", [])) != 1:
        raise SystemExit(f"Source mesh {config['source_name']} must have one primitive")
    source_primitive = source_mesh["primitives"][0]
    if int(source_primitive.get("mode", 4)) != 4 or source_primitive.get("targets"):
        raise SystemExit("Selected source primitive must be triangles without morph targets")
    source_material_index = int(source_primitive["material"])
    source_material = document["materials"][source_material_index]
    if source_material.get("name") != config["source_material"]:
        raise SystemExit(f"Unexpected source material: {source_material.get('name')}")
    if source_material.get("alphaMode") != "BLEND" or source_material.get("doubleSided") is not True:
        raise SystemExit("Selected material's authored BLEND/double-sided settings changed")

    node_matches = [index for index, node in enumerate(document.get("nodes", [])) if node.get("mesh") == source_mesh_index]
    if len(node_matches) != 1:
        raise SystemExit(f"Expected one mesh node for {config['source_name']}; found {len(node_matches)}")
    world, node_chain = node_world_transform(document, node_matches[0])
    linear = [[world[row][column] for column in range(3)] for row in range(3)]
    translation = [world[row][3] for row in range(3)]
    scale, orthogonality_error = validate_uniform_basis(linear)
    if max(abs(value) for value in translation[1:]) > 1e-5 or not 6.52 < abs(translation[0]) < 6.54:
        raise SystemExit(f"Unexpected gallery placement transform: {translation}")

    output_buffer = bytearray()
    output_views: list[dict[str, Any]] = []
    output_accessors: list[dict[str, Any]] = []
    accessor_remap: dict[int, int] = {}
    source_position_bounds: dict[str, Any] = {}
    output_position_bounds: dict[str, Any] = {}
    output_attributes: dict[str, int] = {}
    attribute_payloads: dict[str, bytes] = {}

    def append_accessor(source_accessor_index: int, attr_name: str) -> int:
        if source_accessor_index in accessor_remap:
            return accessor_remap[source_accessor_index]
        source_accessor = document["accessors"][source_accessor_index]
        values = accessor_values(document, source_buffer, source_accessor_index)
        out_values = values
        if attr_name in ("POSITION", "NORMAL", "TANGENT"):
            if attr_name == "POSITION":
                source_position_bounds.update(bounds(values, 3))
            transformed = [vector3(linear, value) for value in values]
            if attr_name == "POSITION":
                out_values = transformed
            else:
                out_values = [normalized(value) for value in transformed]
                if attr_name == "TANGENT":
                    out_values = [(*direction, float(value[3])) for direction, value in zip(out_values, values)]
        component_type = int(source_accessor["componentType"])
        payload = (
            pack_values(out_values, component_type)
            if attr_name in ("POSITION", "NORMAL", "TANGENT")
            else accessor_bytes(document, source_buffer, source_accessor_index)
        )
        if attr_name in ("POSITION", "NORMAL", "TANGENT"):
            unpacked = [
                tuple(struct.unpack_from("<" + COMPONENT_FORMAT[component_type] * len(value), payload, index * len(value) * COMPONENT_BYTES[component_type]))
                for index, value in enumerate(out_values)
            ]
            out_values = unpacked
        while len(output_buffer) % 4:
            output_buffer.append(0)
        view_offset = len(output_buffer)
        output_buffer.extend(payload)
        source_view = document["bufferViews"][source_accessor["bufferView"]]
        target = int(source_view.get("target", 34963 if attr_name == "indices" else 34962))
        output_view_index = len(output_views)
        output_views.append({"buffer": 0, "byteOffset": view_offset, "byteLength": len(payload), "target": target})
        out_accessor = copy.deepcopy(source_accessor)
        out_accessor["bufferView"] = output_view_index
        out_accessor["byteOffset"] = 0
        out_accessor.pop("sparse", None)
        if attr_name in ("POSITION", "NORMAL", "TANGENT"):
            value_bounds = bounds(out_values, COMPONENTS[out_accessor["type"]])
            out_accessor["min"] = value_bounds["min"]
            out_accessor["max"] = value_bounds["max"]
            if attr_name == "POSITION":
                output_position_bounds.update(value_bounds)
        attribute_payloads[attr_name.lower()] = payload
        output_accessor_index = len(output_accessors)
        output_accessors.append(out_accessor)
        accessor_remap[source_accessor_index] = output_accessor_index
        return output_accessor_index

    for attribute_name, source_accessor_index in source_primitive["attributes"].items():
        output_attributes[attribute_name] = append_accessor(int(source_accessor_index), attribute_name)
    output_indices = append_accessor(int(source_primitive["indices"]), "indices")
    source_index_values = accessor_values(document, source_buffer, int(source_primitive["indices"]))
    source_index_bytes = accessor_bytes(document, source_buffer, int(source_primitive["indices"]))
    source_uv_bytes = accessor_bytes(document, source_buffer, int(source_primitive["attributes"]["TEXCOORD_0"]))
    index_values_preserved = attribute_payloads["indices"] == source_index_bytes
    uv_values_preserved = attribute_payloads.get("texcoord_0") == source_uv_bytes
    if not index_values_preserved or not uv_values_preserved:
        raise SystemExit("Non-transformed source index or UV accessor bytes changed")
    triangles = len(source_index_values) // 3
    vertices = int(document["accessors"][source_primitive["attributes"]["POSITION"]]["count"])
    if len(source_index_values) % 3 or triangles != config["triangles"] or vertices != config["vertices"]:
        raise SystemExit(f"Unexpected selected source topology: {vertices} vertices, {triangles} triangles")

    remapped_material, output_textures, output_images, output_samplers, texture_files = remap_material_textures(
        document, source_material, config["texture_stem"]
    )
    base_info = source_material.get("pbrMetallicRoughness", {}).get("baseColorTexture")
    if not isinstance(base_info, dict):
        raise SystemExit("Selected shrub material has no base-color texture")
    base_image_index = int(document["textures"][int(base_info["index"])]["source"])
    base_uri = document["images"][base_image_index].get("uri", "")
    if Path(str(base_uri)).suffix.lower() != ".png":
        raise SystemExit(f"Selected material base-color source is not PNG: {base_uri}")
    source_map = (document["_source_dir"] / "textures" / Path(str(base_uri)).name).read_bytes()
    base_map_metadata = png_metadata(source_map)
    if not source_map or not output_images or output_images[0].get("uri") != f"textures/{config['texture_stem']}_basecolor.png":
        raise SystemExit("Selected material's source base-color map was not retained")

    primitive = copy.deepcopy(source_primitive)
    primitive["attributes"] = output_attributes
    primitive["indices"] = output_indices
    primitive["material"] = 0
    output_document: dict[str, Any] = {
        "asset": {
            "version": "2.0",
            "generator": "OpenRCsimulator convert_forest_shrub.py",
            "extras": copy.deepcopy(document.get("asset", {}).get("extras", {})),
        },
        "scene": 0,
        "scenes": [{"name": config["id"], "nodes": [0]}],
        "nodes": [{"name": config["id"], "mesh": 0}],
        "meshes": [{"name": config["id"], "primitives": [primitive]}],
        "materials": [remapped_material],
        "textures": output_textures,
        "images": output_images,
        "samplers": output_samplers,
        "buffers": [{"uri": f"{config['id']}.bin", "byteLength": len(output_buffer)}],
        "bufferViews": output_views,
        "accessors": output_accessors,
    }
    files = {
        config["gltf"]: (json.dumps(output_document, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8"),
        f"{config['id']}.bin": bytes(output_buffer),
        **texture_files,
    }
    metadata = {
        "id": config["id"],
        "source_name": config["source_name"],
        "source_mesh_index": source_mesh_index,
        "source_node_index": node_matches[0],
        "source_node_chain": [document["nodes"][index].get("name", str(index)) for index in node_chain],
        "source_material": config["source_material"],
        "gltf": config["gltf"],
        "triangles": triangles,
        "vertices": vertices,
        "surfaces": 1,
        "source_gallery_translation_y_up_m": translation,
        "source_linear_basis": linear,
        "source_uniform_scale": scale,
        "source_basis_orthogonality_error": orthogonality_error,
        "source_bounds_mesh_local_m": source_position_bounds,
        "bounds_y_up_m": output_position_bounds,
        "origin": {"mesh_local": [0.0, 0.0, 0.0], "output": [0.0, 0.0, 0.0], "policy": "source mesh-local origin retained; gallery translation removed"},
        "material": {
            "name": remapped_material.get("name"),
            "alpha_mode": remapped_material.get("alphaMode", "OPAQUE"),
            "double_sided": remapped_material.get("doubleSided", False),
            "metallic_factor": remapped_material.get("pbrMetallicRoughness", {}).get("metallicFactor", 1.0),
            "roughness_factor": remapped_material.get("pbrMetallicRoughness", {}).get("roughnessFactor", 1.0),
            "base_color": f"textures/{config['texture_stem']}_basecolor.png",
            "source_base_color_sha256": sha256_bytes(source_map),
            "source_texture_format": base_map_metadata,
        },
        "source_to_output_checks": {
            "vertex_count_preserved": True,
            "triangle_count_preserved": True,
            "index_values_preserved": True,
            "uv_accessor_bytes_preserved": uv_values_preserved,
            "index_accessor_bytes_preserved": index_values_preserved,
            "source_map_bytes_preserved": True,
            "positions_transformed_only_by_source_linear_basis": True,
            "normals_transformed_and_renormalized": True,
        },
    }
    validate_output_document(output_document, config)
    if output_position_bounds["size"][1] < 0.65 or output_position_bounds["size"][1] > 1.0:
        raise SystemExit(f"Selected shrub height is outside the reviewed role band: {output_position_bounds['size'][1]}")
    return output_document, files, metadata


def validate_output_document(document: dict[str, Any], config: dict[str, Any]) -> None:
    if len(document.get("nodes", [])) != 1 or len(document.get("meshes", [])) != 1 or len(document.get("materials", [])) != 1:
        raise SystemExit(f"{config['id']} must export one identity node, mesh and material")
    node = document["nodes"][0]
    if any(key in node for key in ("matrix", "translation", "rotation", "scale")) or node.get("mesh") != 0:
        raise SystemExit(f"{config['id']} output node must be identity and reference mesh zero")
    primitive = document["meshes"][0].get("primitives", [])[0]
    material = document["materials"][0]
    if primitive.get("material") != 0 or primitive.get("mode", 4) != 4:
        raise SystemExit(f"{config['id']} must contain one triangle primitive using material zero")
    if material.get("alphaMode") != "BLEND" or material.get("doubleSided") is not True:
        raise SystemExit(f"{config['id']} must preserve authored BLEND and double-sided material flags")
    if int(document["accessors"][primitive["indices"]]["count"]) // 3 != config["triangles"]:
        raise SystemExit(f"{config['id']} triangle count changed")
    if int(document["accessors"][primitive["attributes"]["POSITION"]]["count"]) != config["vertices"]:
        raise SystemExit(f"{config['id']} vertex count changed")
    base_index = material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    image = document["images"][document["textures"][base_index]["source"]]
    if image.get("uri") != f"textures/{config['texture_stem']}_basecolor.png":
        raise SystemExit(f"{config['id']} base-color texture remapping changed")


def build_outputs(source_dir: Path) -> tuple[dict[str, bytes], list[dict[str, Any]]]:
    document = json.loads((source_dir / SOURCE_GLTF).read_text(encoding="utf-8"))
    document["_source_dir"] = source_dir
    source_buffers = document.get("buffers", [])
    if len(source_buffers) != 1 or source_buffers[0].get("uri") != SOURCE_BUFFER:
        raise SystemExit("Expected the pinned source glTF to reference scene.bin")
    source_buffer = (source_dir / SOURCE_BUFFER).read_bytes()
    if len(source_buffer) != int(source_buffers[0]["byteLength"]):
        raise SystemExit("Source scene.bin length differs from scene.gltf")
    _, files, metadata = source_variant(document, source_buffer)
    return files, [metadata]


def output_records(files: dict[str, bytes]) -> list[dict[str, Any]]:
    return [{"path": path, "bytes": len(data), "sha256": sha256_bytes(data)} for path, data in sorted(files.items())]


def build_manifest(source_dir: Path, files: dict[str, bytes], variants: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "format": MANIFEST_FORMAT,
        "asset_id": "dasy_forest_selected_shrub",
        "source": {
            "name": "a forest (3) with a road at night for game",
            "creator": "dasy444",
            "url": SOURCE_URL,
            "license": "CC BY 4.0",
            "license_url": LICENSE_URL,
            "license_notice": "assets/landscape/vegetation/source/dasy_forest_2026/LICENSE_FOREST.txt",
            "archive": {"name": ARCHIVE_NAME, "bytes": ARCHIVE_BYTES, "sha256": ARCHIVE_SHA256},
            "original_entries": ORIGINAL_ARCHIVE_ENTRIES,
            "selected_mesh_index": 210,
            "selected_mesh_name": VARIANT["source_name"],
        },
        "variants": variants,
        "inputs": input_records(source_dir),
        "outputs": output_records(files),
        "toolchain": {
            "converter": "tools/landscape/vegetation/convert_forest_shrub.py",
            "converter_sha256": sha256_file(Path(__file__).resolve()),
            "python": platform.python_version(),
        },
        "conversion": {
            "geometry_created": False,
            "decimation": False,
            "source_node_chain": "Sketchfab_model > 8487a72de1e44d0180e1c3e69ca9c229.fbx > RootNode > selected gallery object > selected mesh",
            "node_transform": "accumulated source glTF node transforms; removed cumulative gallery translation; baked the complete remaining linear basis into positions and normals",
            "origin": "source mesh-local origin (0, 0, 0) retained; no vertex recentering or grounding offset",
            "source_material": "preserved base-color factor/texture, alphaMode BLEND, doubleSided true, metallicFactor 0 and roughnessFactor 0.8211145618000169",
            "source_map": "the supplied 2048x2048 RGBA base-color map is copied byte-for-byte; its alpha channel contains both transparent and opaque values",
            "topology": "source vertex positions, primitive mode, and index values retained; accessor data repacked into a compact standalone buffer; UV values retained byte-for-byte",
        },
    }


def check_conversion(source_dir: Path, output_dir: Path) -> None:
    input_list = input_records(source_dir)
    manifest_path = output_dir / MANIFEST_NAME
    if not manifest_path.is_file():
        raise SystemExit(f"Conversion manifest missing: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("format") != MANIFEST_FORMAT or manifest.get("inputs") != input_list:
        raise SystemExit("Pinned source file list or input hashes differ from the conversion manifest")
    generated, variants = build_outputs(source_dir)
    expected = build_manifest(source_dir, generated, variants)
    for key in ("variants", "outputs", "source", "conversion"):
        if manifest.get(key) != expected[key]:
            raise SystemExit(f"Conversion manifest {key} differ from the pinned source extraction")
    for relative, content in generated.items():
        path = output_dir / Path(relative)
        if not path.is_file() or path.read_bytes() != content:
            raise SystemExit(f"Derived output differs from deterministic conversion: {relative}")
    if manifest.get("toolchain", {}).get("converter_sha256") != expected["toolchain"]["converter_sha256"]:
        raise SystemExit("Converter source hash differs from the conversion manifest")
    print(json.dumps({"check": "ok", "manifest": str(manifest_path), "variants": len(variants), "outputs": len(generated)}, indent=2))


def convert(source_dir: Path, output_dir: Path) -> None:
    inputs = input_records(source_dir)
    files, variants = build_outputs(source_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    for relative, data in sorted(files.items()):
        path = output_dir / Path(relative)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    manifest = build_manifest(source_dir, files, variants)
    if manifest["inputs"] != inputs:
        raise SystemExit("Pinned source inputs changed during conversion")
    (output_dir / MANIFEST_NAME).write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )
    print(json.dumps({"manifest": str(output_dir / MANIFEST_NAME), "variants": variants, "outputs": manifest["outputs"]}, indent=2))


def main() -> None:
    args = parse_args()
    root = args.repo_root.resolve()
    source_dir = args.source_dir.resolve() if args.source_dir else (root / SOURCE_RELATIVE).resolve()
    output_dir = args.output_dir.resolve() if args.output_dir else (root / DERIVED_RELATIVE).resolve()
    input_records(source_dir)
    if args.check:
        check_conversion(source_dir, output_dir)
        return
    convert(source_dir, output_dir)


if __name__ == "__main__":
    main()
