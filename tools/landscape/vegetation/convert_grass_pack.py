#!/usr/bin/env python3
"""Extract two pinned LOLIPOP grass tufts from the supplied Sketchfab glTF.

The converter preserves source triangle topology, UVs, texture pixels and
material maps. It removes gallery placement, bakes the source Z-up to glTF
Y-up basis into vertex data, and exports one identity-root glTF per variant.
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


ARCHIVE_NAME = "grass_pack_lowpoly_game-ready.zip"
ARCHIVE_BYTES = 4_571_974
ARCHIVE_SHA256 = "304b2ea5c62f6dc635dc5d895534d5bd3812d58e25815d43fcd5ff7783a65fe4"
SOURCE_RELATIVE = Path("assets/landscape/vegetation/source/lolipop_grass_2026")
DERIVED_RELATIVE = Path("assets/landscape/vegetation/derived/lolipop_grass_2026")
SOURCE_GLTF = "scene.gltf"
SOURCE_BUFFER = "scene.bin"
MANIFEST_NAME = "conversion_manifest.json"
MANIFEST_FORMAT = "openrc-grass-pack-conversion-manifest v1"
SOURCE_URL = "https://sketchfab.com/3d-models/grass-pack-lowpoly-game-ready-422f42f618d342c6958b02613dc57403"
LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"
BLENDER_INSPECTION_VERSION = "5.2.2 LTS"

# Source file hashes include the exact archive, its extracted files and the
# project attribution notice. The extracted files remain independently
# checked so the conversion does not depend on the ZIP library's behavior.
SOURCE_INPUTS = {
    "archive/grass_pack_lowpoly_game-ready.zip": ARCHIVE_SHA256,
    "LICENSE_GRASS.txt": "397715d253b1dd51299bb6cc785e634e4a106b89e6541d6cefcf905ffa5ee4a7",
    "license.txt": "6bfbc67cf495ad6d324df9256675343561092b87520b8c37b5620521441b3fc9",
    "scene.bin": "13684814e25dc9cf086c371f7cd8912b14e904089ea3195972ba993bbeadede4",
    "scene.gltf": "d862ac8e5cead51dc5155375903482a231c2afd1c6df65f28433bb014e04eac6",
    "textures/Checker_mat_baseColor.png": "129cd15feabe9ba45abb6a490d2e3f12692a351e72b195812d492d3c17f9c924",
    "textures/Grass_Mat_baseColor.png": "d91b2ab204902e84c76400201849254da0ab41dd6b109fa2ad7bc4017ebe3927",
    "textures/Grass_Mat_metallicRoughness.png": "85ed0c78f7303c5015431c8818a88018e1be3ee14d201b9b3c6f1c7c755ccb93",
    "textures/Grass_Mat_normal.png": "2f83a76ee2defa4e214f139cdca684eba5b346a6d93ff6a65decbf929567856b",
    "textures/Man_ref_baseColor.png": "924e3651cb55114c611a4202173af071e0ed7866af0818ff6288dd2cc4ad084f",
    "textures/Tall_grass_Mat_baseColor.png": "518b9973a47534a896d1a5d41f8cb2363dd5a80a013946d5cf3703134d684405",
    "textures/Tall_grass_Mat_metallicRoughness.png": "7bb6c00839b46f1189de0a6c3ef887f7954dd4e2e8b0872e6ebe91468302754e",
    "textures/Tall_grass_Mat_normal.png": "853befe53647d63a04d7e799716f50d8476ed8d634eaed9b573f4a2670815911",
}

ORIGINAL_ARCHIVE_ENTRIES = [
    "license.txt",
    "scene.bin",
    "scene.gltf",
    "textures/Checker_mat_baseColor.png",
    "textures/Grass_Mat_baseColor.png",
    "textures/Grass_Mat_metallicRoughness.png",
    "textures/Grass_Mat_normal.png",
    "textures/Man_ref_baseColor.png",
    "textures/Tall_grass_Mat_baseColor.png",
    "textures/Tall_grass_Mat_metallicRoughness.png",
    "textures/Tall_grass_Mat_normal.png",
]

VARIANTS = [
    {
        "id": "grass_lolipop_small",
        "source_name": "Grass main fresh.002_Grass_Mat_0",
        "source_material": "Grass_Mat",
        "triangles": 26,
        "vertices": 37,
        "gltf": "grass_lolipop_small.gltf",
        "texture_stem": "grass_lolipop_small",
    },
    {
        "id": "grass_lolipop_tall",
        "source_name": "Grass tall low.001_Tall_grass_Mat_0",
        "source_material": "Tall_grass_Mat",
        "triangles": 20,
        "vertices": 30,
        "gltf": "grass_lolipop_tall.gltf",
        "texture_stem": "grass_lolipop_tall",
    },
]

# The ancestor matrices in the pinned Sketchfab file resolve to this proper
# rotation, plus per-item gallery translation and floating-point FBX residue.
# It maps source Z-up mesh coordinates to the required glTF Y-up coordinates.
Z_UP_TO_GLTF_Y_UP = (
    (1.0, 0.0, 0.0),
    (0.0, 0.0, 1.0),
    (0.0, -1.0, 0.0),
)

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
    if archive.stat().st_size != ARCHIVE_BYTES:
        raise SystemExit(f"Source archive byte count changed: {archive.stat().st_size}")
    if sha256_file(archive) != ARCHIVE_SHA256:
        raise SystemExit("Source archive SHA-256 changed")
    return records


def identity4() -> list[list[float]]:
    return [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]


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
    nodes = document.get("nodes", [])
    parents: dict[int, int] = {}
    for parent_index, node in enumerate(nodes):
        for child in node.get("children", []):
            if child in parents:
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
        result = multiply4(result, node_matrix(nodes[index]))
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


def pack_values(values: list[tuple[int | float, ...]], component_type: int) -> bytes:
    fmt = COMPONENT_FORMAT[component_type]
    flattened = [component for value in values for component in value]
    if not flattened:
        return b""
    return struct.pack("<" + fmt * len(flattened), *flattened)


def transform_vector(value: tuple[int | float, ...], attr_name: str) -> tuple[float, ...]:
    x, y, z = (float(value[index]) for index in range(3))
    rotated = (x, z, -y)
    if attr_name == "TANGENT":
        if len(value) != 4:
            raise SystemExit("TANGENT accessor must be VEC4")
        return (*rotated, float(value[3]))
    if len(value) != 3:
        raise SystemExit(f"{attr_name} accessor must be VEC3")
    return rotated


def bounds(values: list[tuple[int | float, ...]], dimensions: int) -> dict[str, list[float]]:
    minimum = [min(float(value[axis]) for value in values) for axis in range(dimensions)]
    maximum = [max(float(value[axis]) for value in values) for axis in range(dimensions)]
    return {"min": minimum, "max": maximum, "size": [maximum[i] - minimum[i] for i in range(dimensions)]}


def assert_baked_transform(world: list[list[float]], source_name: str) -> tuple[list[float], float]:
    max_basis_error = max(
        abs(world[row][column] - Z_UP_TO_GLTF_Y_UP[row][column])
        for row in range(3)
        for column in range(3)
    )
    if max_basis_error > 1e-4:
        raise SystemExit(f"Unexpected source axis transform for {source_name}: error={max_basis_error}")
    gallery_translation = [float(world[row][3]) for row in range(3)]
    if abs(gallery_translation[1]) > 1e-4 or abs(gallery_translation[2]) > 1e-4:
        raise SystemExit(f"Unexpected non-gallery source translation for {source_name}: {gallery_translation}")
    return gallery_translation, max_basis_error


def remap_material_textures(
    source_document: dict[str, Any], material: dict[str, Any], texture_stem: str
) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], dict[str, bytes]]:
    textures = source_document.get("textures", [])
    images = source_document.get("images", [])
    samplers = source_document.get("samplers", [])
    texture_index_map: dict[int, int] = {}
    image_index_map: dict[int, int] = {}
    sampler_index_map: dict[int, int] = {}
    output_textures: list[dict[str, Any]] = []
    output_images: list[dict[str, Any]] = []
    output_samplers: list[dict[str, Any]] = []
    output_files: dict[str, bytes] = {}

    texture_fields: list[tuple[dict[str, Any], str]] = []
    pbr = material.get("pbrMetallicRoughness", {})
    if isinstance(pbr.get("baseColorTexture"), dict):
        texture_fields.append((pbr["baseColorTexture"], "basecolor"))
    if isinstance(pbr.get("metallicRoughnessTexture"), dict):
        texture_fields.append((pbr["metallicRoughnessTexture"], "mrao"))
    for key, semantic in (("normalTexture", "normal"), ("occlusionTexture", "mrao")):
        if isinstance(material.get(key), dict):
            texture_fields.append((material[key], semantic))

    image_semantic: dict[int, str] = {}
    for texture_info, semantic in texture_fields:
        old_texture_index = int(texture_info["index"])
        old_texture = textures[old_texture_index]
        old_image_index = int(old_texture["source"])
        image_semantic.setdefault(old_image_index, semantic)

    for old_image_index, semantic in sorted(image_semantic.items()):
        old_image = copy.deepcopy(images[old_image_index])
        uri = old_image.get("uri")
        if not isinstance(uri, str) or "bufferView" in old_image:
            raise SystemExit(f"Expected external source image URI at index {old_image_index}")
        source_name = Path(uri.replace("\\", "/")).name
        output_name = f"{texture_stem}_{semantic}.png"
        output_path = f"textures/{output_name}"
        old_image.pop("bufferView", None)
        old_image["uri"] = output_path
        image_index_map[old_image_index] = len(output_images)
        output_images.append(old_image)
        output_files[output_path] = (source_document["_source_dir"] / "textures" / source_name).read_bytes()

    for _, texture_info in sorted(
        ((int(info["index"]), info) for info, _ in texture_fields), key=lambda item: item[0]
    ):
        old_texture_index = int(texture_info["index"])
        if old_texture_index in texture_index_map:
            continue
        old_texture = copy.deepcopy(textures[old_texture_index])
        old_image_index = int(old_texture["source"])
        old_texture["source"] = image_index_map[old_image_index]
        if "sampler" in old_texture:
            old_sampler_index = int(old_texture["sampler"])
            if old_sampler_index not in sampler_index_map:
                sampler_index_map[old_sampler_index] = len(output_samplers)
                output_samplers.append(copy.deepcopy(samplers[old_sampler_index]))
            old_texture["sampler"] = sampler_index_map[old_sampler_index]
        texture_index_map[old_texture_index] = len(output_textures)
        output_textures.append(old_texture)

    remapped_material = copy.deepcopy(material)
    pbr = remapped_material.get("pbrMetallicRoughness", {})
    for info in [pbr.get("baseColorTexture"), pbr.get("metallicRoughnessTexture"), remapped_material.get("normalTexture"), remapped_material.get("occlusionTexture")]:
        if isinstance(info, dict):
            info["index"] = texture_index_map[int(info["index"])]
    remapped_material["alphaMode"] = "MASK"
    remapped_material["alphaCutoff"] = 0.5
    remapped_material["doubleSided"] = True
    remapped_material["name"] = f"{texture_stem}_PBR"
    return remapped_material, output_textures, output_images, output_samplers, output_files


def source_variant(document: dict[str, Any], source_buffer: bytes, config: dict[str, Any]) -> tuple[dict[str, Any], dict[str, bytes], dict[str, Any]]:
    meshes = document.get("meshes", [])
    mesh_matches = [index for index, mesh in enumerate(meshes) if mesh.get("name") == config["source_name"]]
    if len(mesh_matches) != 1:
        raise SystemExit(f"Expected one source mesh named {config['source_name']}; found {len(mesh_matches)}")
    source_mesh_index = mesh_matches[0]
    source_mesh = meshes[source_mesh_index]
    primitives = source_mesh.get("primitives", [])
    if len(primitives) != 1:
        raise SystemExit(f"Source mesh {config['source_name']} must have one primitive")
    source_primitive = primitives[0]
    source_material_index = int(source_primitive["material"])
    source_material = document["materials"][source_material_index]
    if source_material.get("name") != config["source_material"]:
        raise SystemExit(f"Unexpected material on {config['source_name']}: {source_material.get('name')}")

    node_matches = [index for index, node in enumerate(document.get("nodes", [])) if node.get("mesh") == source_mesh_index]
    if len(node_matches) != 1:
        raise SystemExit(f"Expected one mesh node for {config['source_name']}; found {len(node_matches)}")
    world, node_chain = node_world_transform(document, node_matches[0])
    gallery_translation, basis_error = assert_baked_transform(world, config["source_name"])

    output_buffer = bytearray()
    output_views: list[dict[str, Any]] = []
    output_accessors: list[dict[str, Any]] = []
    accessor_remap: dict[int, int] = {}
    proof: dict[str, Any] = {"source_to_baked_max_abs_error": {}, "source_bounds_z_up_m": {}, "bounds_y_up_m": {}}
    output_attributes: dict[str, int] = {}

    def append_accessor(source_accessor_index: int, attr_name: str) -> int:
        if source_accessor_index in accessor_remap:
            return accessor_remap[source_accessor_index]
        source_accessor = document["accessors"][source_accessor_index]
        values = accessor_values(document, source_buffer, source_accessor_index)
        out_values = values
        if attr_name in ("POSITION", "NORMAL", "TANGENT"):
            out_values = [transform_vector(value, attr_name) for value in values]
            proof["source_to_baked_max_abs_error"][attr_name.lower()] = 0.0
        if attr_name == "POSITION":
            proof["source_bounds_z_up_m"] = bounds(values, 3)
            proof["bounds_y_up_m"] = bounds(out_values, 3)

        component_type = int(source_accessor["componentType"])
        payload = pack_values(out_values, component_type)
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
            dimensions = COMPONENTS[out_accessor["type"]]
            value_bounds = bounds(out_values, dimensions)
            out_accessor["min"] = value_bounds["min"]
            out_accessor["max"] = value_bounds["max"]
        output_accessor_index = len(output_accessors)
        output_accessors.append(out_accessor)
        accessor_remap[source_accessor_index] = output_accessor_index
        return output_accessor_index

    for attribute_name, source_accessor_index in source_primitive["attributes"].items():
        output_attributes[attribute_name] = append_accessor(int(source_accessor_index), attribute_name)
    output_indices = append_accessor(int(source_primitive["indices"]), "indices")
    index_values = accessor_values(document, source_buffer, int(source_primitive["indices"]))
    triangles = len(index_values) // 3
    vertices = int(document["accessors"][source_primitive["attributes"]["POSITION"]]["count"])
    if len(index_values) % 3 or triangles != config["triangles"] or vertices != config["vertices"]:
        raise SystemExit(f"Unexpected source geometry for {config['source_name']}: {vertices} vertices, {triangles} triangles")

    remapped_material, output_textures, output_images, output_samplers, texture_files = remap_material_textures(
        document, source_material, config["texture_stem"]
    )
    source_material_base = source_material.get("pbrMetallicRoughness", {}).get("baseColorTexture", {})
    source_base_image_index = document["textures"][int(source_material_base["index"])]["source"]
    source_base_name = Path(document["images"][int(source_base_image_index)]["uri"]).name
    source_base_bytes = (document["_source_dir"] / "textures" / source_base_name).read_bytes()
    if not source_base_bytes:
        raise SystemExit(f"Empty base-color map for {config['source_name']}")
    if not output_images or output_images[0].get("uri") != f"textures/{config['texture_stem']}_basecolor.png":
        raise SystemExit(f"Base-color map ordering changed for {config['source_name']}")

    primitive = copy.deepcopy(source_primitive)
    primitive["attributes"] = output_attributes
    primitive["indices"] = output_indices
    primitive["material"] = 0
    output_mesh = {"name": config["id"], "primitives": [primitive]}

    used_extensions = sorted(
        set(document.get("extensionsUsed", []))
        & set((remapped_material.get("extensions") or {}).keys())
    )
    output_document: dict[str, Any] = {
        "asset": {
            "version": "2.0",
            "generator": "OpenRCsimulator convert_grass_pack.py",
            "extras": copy.deepcopy(document.get("asset", {}).get("extras", {})),
        },
        "scene": 0,
        "scenes": [{"name": config["id"], "nodes": [0]}],
        "nodes": [{"name": config["id"], "mesh": 0}],
        "meshes": [output_mesh],
        "materials": [remapped_material],
        "textures": output_textures,
        "images": output_images,
        "samplers": output_samplers,
        "buffers": [{"uri": f"{config['id']}.bin", "byteLength": len(output_buffer)}],
        "bufferViews": output_views,
        "accessors": output_accessors,
    }
    if used_extensions:
        output_document["extensionsUsed"] = used_extensions
    required_extensions = sorted(set(document.get("extensionsRequired", [])) & set(used_extensions))
    if required_extensions:
        output_document["extensionsRequired"] = required_extensions
    json_bytes = (json.dumps(output_document, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    files = {config["gltf"]: json_bytes, f"{config['id']}.bin": bytes(output_buffer), **texture_files}
    metadata = {
        "id": config["id"],
        "source_name": config["source_name"],
        "gltf": config["gltf"],
        "triangles": triangles,
        "vertices": vertices,
        "surfaces": 1,
        "source_material": config["source_material"],
        "source_mesh_index": source_mesh_index,
        "source_node_index": node_matches[0],
        "source_node_chain": [document["nodes"][index].get("name", str(index)) for index in node_chain],
        "source_gallery_translation_y_up_m": gallery_translation,
        "source_linear_basis_max_abs_residual": basis_error,
        "source_bounds_z_up_m": proof["source_bounds_z_up_m"],
        "bounds_y_up_m": proof["bounds_y_up_m"],
        "source_to_baked_max_abs_error": proof["source_to_baked_max_abs_error"],
        "material": {
            "name": remapped_material["name"],
            "base_color": f"textures/{config['texture_stem']}_basecolor.png",
            "metallic_roughness_occlusion": f"textures/{config['texture_stem']}_mrao.png",
            "normal": f"textures/{config['texture_stem']}_normal.png",
            "alpha_mode": "MASK",
            "alpha_cutoff": 0.5,
            "double_sided": True,
        },
    }
    validate_output_document(output_document, config)
    return output_document, files, metadata


def validate_output_document(document: dict[str, Any], config: dict[str, Any]) -> None:
    nodes = document.get("nodes", [])
    meshes = document.get("meshes", [])
    materials = document.get("materials", [])
    if len(nodes) != 1 or len(meshes) != 1 or len(materials) != 1:
        raise SystemExit(f"{config['id']} must export one identity node, mesh and material")
    if any(key in nodes[0] for key in ("matrix", "translation", "rotation", "scale")):
        raise SystemExit(f"{config['id']} node must not have transforms")
    if nodes[0].get("mesh") != 0:
        raise SystemExit(f"{config['id']} root node does not reference mesh zero")
    primitives = meshes[0].get("primitives", [])
    if len(primitives) != 1 or primitives[0].get("material") != 0:
        raise SystemExit(f"{config['id']} must contain one material primitive")
    material = materials[0]
    if material.get("alphaMode") != "MASK" or material.get("doubleSided") is not True:
        raise SystemExit(f"{config['id']} material must be double-sided MASK")
    if abs(float(material.get("alphaCutoff", 0.0)) - 0.5) > 1e-7:
        raise SystemExit(f"{config['id']} alpha cutoff must remain 0.5")
    index_accessor = document["accessors"][primitives[0]["indices"]]
    if int(index_accessor["count"]) // 3 != config["triangles"]:
        raise SystemExit(f"{config['id']} triangle count changed")
    if int(document["accessors"][primitives[0]["attributes"]["POSITION"]]["count"]) != config["vertices"]:
        raise SystemExit(f"{config['id']} vertex count changed")
    base_texture_index = material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    base_image = document["images"][document["textures"][base_texture_index]["source"]]
    if not base_image.get("uri", "").endswith("_basecolor.png"):
        raise SystemExit(f"{config['id']} base-color texture does not preserve source alpha map")


def build_outputs(source_dir: Path) -> tuple[dict[str, bytes], list[dict[str, Any]]]:
    document = json.loads((source_dir / SOURCE_GLTF).read_text(encoding="utf-8"))
    document["_source_dir"] = source_dir
    source_buffers = document.get("buffers", [])
    if len(source_buffers) != 1 or source_buffers[0].get("uri") != SOURCE_BUFFER:
        raise SystemExit("Expected the pinned source glTF to reference scene.bin")
    source_buffer = (source_dir / SOURCE_BUFFER).read_bytes()
    if len(source_buffer) != int(source_buffers[0]["byteLength"]):
        raise SystemExit("Source scene.bin length differs from scene.gltf")

    files: dict[str, bytes] = {}
    metadata: list[dict[str, Any]] = []
    for config in VARIANTS:
        _, variant_files, variant_metadata = source_variant(document, source_buffer, config)
        for relative, contents in variant_files.items():
            if relative in files and files[relative] != contents:
                raise SystemExit(f"Derived output path collision: {relative}")
            files[relative] = contents
        metadata.append(variant_metadata)
    return files, metadata


def output_records(files: dict[str, bytes]) -> list[dict[str, Any]]:
    return [
        {"path": path, "bytes": len(contents), "sha256": sha256_bytes(contents)}
        for path, contents in sorted(files.items())
    ]


def build_manifest(source_dir: Path, files: dict[str, bytes], variants: list[dict[str, Any]]) -> dict[str, Any]:
    input_list = input_records(source_dir)
    outputs = output_records(files)
    return {
        "format": MANIFEST_FORMAT,
        "asset_id": "grass_lolipop_pack",
        "source": {
            "name": "Grass pack (lowpoly, game-ready)",
            "creator": "LOLIPOP (@lolipop_1707)",
            "url": SOURCE_URL,
            "license": "CC BY 4.0",
            "license_url": LICENSE_URL,
            "license_notice": "assets/landscape/vegetation/source/lolipop_grass_2026/LICENSE_GRASS.txt",
            "archive": {"name": ARCHIVE_NAME, "bytes": ARCHIVE_BYTES, "sha256": ARCHIVE_SHA256},
            "original_entries": ORIGINAL_ARCHIVE_ENTRIES,
            "source_axis": "Z-up",
        },
        "variants": variants,
        "inputs": input_list,
        "outputs": outputs,
        "toolchain": {
            "converter": "tools/landscape/vegetation/convert_grass_pack.py",
            "converter_sha256": sha256_file(Path(__file__).resolve()),
            "python": platform.python_version(),
            "blender_inspection": BLENDER_INSPECTION_VERSION,
        },
        "conversion": {
            "geometry_created": False,
            "decimation": False,
            "method": "selected the supplied fresh small and low tall mesh variants; removed source gallery translations; baked the source Z-up to glTF Y-up basis into positions, normals and tangents; repacked the original accessor values without changing indices or UVs; copied the relevant source texture files unchanged; changed the grass material from BLEND to double-sided MASK with alphaCutoff 0.5",
            "source_to_gltf_axis_mapping": "(x, y, z) -> (x, z, -y)",
            "origin": "source mesh-local stem-ground origin retained at (0, 0, 0); source gallery translations removed",
            "source_maps": "RGBA base color including alpha, metallic-roughness-occlusion, and tangent-space normal maps copied byte-for-byte",
            "source_node_policy": "one glTF mesh node with identity transform per variant",
            "triangles_preserved": True,
            "uv_sets_preserved": ["TEXCOORD_0", "TEXCOORD_1"],
            "vertex_colors": "source glTF meshes do not contain COLOR_0",
        },
    }


def check_conversion(source_dir: Path, output_dir: Path) -> None:
    inputs = input_records(source_dir)
    manifest_path = output_dir / MANIFEST_NAME
    if not manifest_path.is_file():
        raise SystemExit(f"Conversion manifest missing: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("format") != MANIFEST_FORMAT:
        raise SystemExit("Unknown grass conversion manifest format")
    if manifest.get("inputs") != inputs:
        raise SystemExit("Pinned source file list or hashes differ from the conversion manifest")
    if manifest.get("source", {}).get("archive", {}).get("sha256") != ARCHIVE_SHA256:
        raise SystemExit("Source archive hash in conversion manifest changed")
    if manifest.get("source", {}).get("license") != "CC BY 4.0":
        raise SystemExit("Grass license in conversion manifest changed")
    generated, variants = build_outputs(source_dir)
    expected_manifest = build_manifest(source_dir, generated, variants)
    if manifest.get("variants") != variants:
        raise SystemExit("Selected source variants or geometry facts differ from the conversion manifest")
    if manifest.get("outputs") != expected_manifest["outputs"]:
        raise SystemExit("Derived output paths or hashes differ from the conversion manifest")
    for relative, content in generated.items():
        path = output_dir / Path(relative)
        if not path.is_file() or path.read_bytes() != content:
            raise SystemExit(f"Derived output differs from deterministic conversion: {relative}")
    if manifest.get("toolchain", {}).get("converter_sha256") != expected_manifest["toolchain"]["converter_sha256"]:
        raise SystemExit("Converter source hash differs from the conversion manifest")
    print(json.dumps({"check": "ok", "manifest": str(manifest_path), "variants": len(variants), "outputs": len(generated)}, indent=2))


def convert(source_dir: Path, output_dir: Path) -> None:
    input_list = input_records(source_dir)
    files, variants = build_outputs(source_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    for relative, contents in sorted(files.items()):
        path = output_dir / Path(relative)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
    manifest = build_manifest(source_dir, files, variants)
    if manifest["inputs"] != input_list:
        raise SystemExit("Pinned source inputs changed during conversion")
    manifest_path = output_dir / MANIFEST_NAME
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"manifest": str(manifest_path), "variants": variants, "outputs": manifest["outputs"]}, indent=2))


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
