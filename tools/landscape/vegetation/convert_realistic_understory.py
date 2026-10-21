#!/usr/bin/env python3
"""Stage source-faithful Poly Haven fern and flower glTF candidates.

The converter extracts one supplied mesh node from each 1K glTF. It keeps the
selected mesh, accessor references, source binary buffer, UVs, normals and
positions unchanged, removing only the source gallery translation. Poly Haven
supplies the diffuse and 16-bit alpha maps separately, so the derived diffuse
image mechanically packs the original RGB with a linearly scaled 8-bit alpha.
The Flower Empodium candidate deliberately changes BLEND to MASK at 0.5; the
source material remains unchanged in the source intake.

This is an offline staging pipeline. It does not import into Godot, add runtime
placement, or claim visual qualification.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import math
import platform
import struct
import sys
from pathlib import Path, PurePosixPath
from typing import Any

from PIL import Image, __version__ as PILLOW_VERSION


SOURCE_RELATIVE = Path("assets/landscape/vegetation/source/realistic_understory_2026")
DERIVED_RELATIVE = Path("assets/landscape/vegetation/derived/realistic_understory_2026")
DOWNLOAD_MANIFEST = SOURCE_RELATIVE / "download_manifest.json"
SOURCE_NOTICE = SOURCE_RELATIVE / "SOURCE_LICENSE.md"
CC0_LEGALCODE = SOURCE_RELATIVE / "CC0-1.0-legalcode.en.html"
CONVERSION_MANIFEST = "conversion_manifest.json"
MANIFEST_FORMAT = "openrc-realistic-understory-conversion v1"
POLYHAVEN_LICENSE_URL = "https://polyhaven.com/license"
CC0_LICENSE_URL = "https://creativecommons.org/publicdomain/zero/1.0/"

PINNED_SOURCE_SHA256 = {
    "fern_02/fern_02_1k.gltf": "33974295ee19670af4877705fc7d91f33f42d6302f0d44a625e072271223031f",
    "fern_02/fern_02.bin": "fe1abb762bcbbc7ad9e86925c8080437a62add257d9280e9142fdc85c226e64c",
    "fern_02/textures/fern_02_diff_1k.jpg": "a828a6e7b4c01c826911e2eac4b3afc7457dab7b3b392a31c681ed88b7d50029",
    "fern_02/textures/fern_02_alpha_1k.png": "ea3c64284c7ebdeedf484d2d816eae92825ec526140c3bb83859ddc7a64001f9",
    "fern_02/textures/fern_02_nor_gl_1k.jpg": "45bce132c6e96a0864bc89ab5da51361ab3f4afa83a6669ae499ab5ca811f621",
    "fern_02/textures/fern_02_arm_1k.jpg": "ebfb5d76ce9cbdaec20bcd22dce9b755f0b1b8650ef29ca13555e3e6961025d7",
    "flower_empodium/flower_empodium_1k.gltf": "3f39d6b7dba6de81014f5ce41e43ac1204a45bfe146cbb425515103c4c5e9798",
    "flower_empodium/flower_empodium.bin": "32256fa72adcf06602f5d80d1b98d2042c546bb3c65aa81a871ffbe22c834a5c",
    "flower_empodium/textures/flower_empodium_diff_1k.jpg": "eca8de7f24d5612d918ddd02339698f9c44b00ad5a9d2fb61d6acda267786129",
    "flower_empodium/textures/flower_empodium_alpha_1k.png": "41aa40a0f570160ca64e8d99e49b4eecdc852158a6b021545831f0d654b0529e",
    "flower_empodium/textures/flower_empodium_nor_gl_1k.jpg": "c752bc6905810e552816189c7e157d111bb9b64402eab9625271a5b4fad4c1ab",
    "flower_empodium/textures/flower_empodium_arm_1k.jpg": "5b49a907dbd98d4d421992ce38ab17db35ed79451af062104efe5bc3e437a852",
}
CC0_LEGALCODE_SHA256 = "b43732f4c1463b087cf10d4daf8d8766514b2bf8f21bc5ef50905f95be227726"

VARIANTS: list[dict[str, Any]] = [
    {
        "id": "polyhaven_fern_02_a",
        "source_id": "polyhaven_fern_02",
        "source_asset": "fern_02",
        "source_name": "fern_02_a",
        "source_mesh_name": "Plane.006",
        "source_page": "https://polyhaven.com/a/fern_02",
        "role": "herb",
        "expected_triangles": 784,
        "source_material_mode": "MASK",
        "output_material_mode": "MASK",
        "output_alpha_cutoff": 0.5,
        "source_gltf": "fern_02/fern_02_1k.gltf",
        "source_node_name": "fern_02_a",
        "source_bin": "fern_02/fern_02.bin",
        "source_diffuse": "fern_02/textures/fern_02_diff_1k.jpg",
        "source_alpha": "fern_02/textures/fern_02_alpha_1k.png",
        "source_normal": "fern_02/textures/fern_02_nor_gl_1k.jpg",
        "source_arm": "fern_02/textures/fern_02_arm_1k.jpg",
        "output_gltf": "fern_02_a.gltf",
        "output_bin": "fern_02_a.bin",
        "output_diffuse": "textures/fern_02_a_base_color_alpha_1k.png",
        "output_normal": "textures/fern_02_a_nor_gl_1k.jpg",
        "output_arm": "textures/fern_02_a_arm_1k.jpg",
        "output_mesh_lod": {
            "source_supplied": False,
            "godot_import_generate": True,
            "note": "The selected fern node is a supplied clump variant, not a named LOD level.",
        },
    },
    {
        "id": "polyhaven_flower_empodium_a",
        "source_id": "polyhaven_flower_empodium",
        "source_asset": "flower_empodium",
        "source_name": "flower_empodium_a_LOD0",
        "source_mesh_name": "Plane.040",
        "source_page": "https://polyhaven.com/a/flower_empodium",
        "role": "flower",
        "expected_triangles": 758,
        "source_material_mode": "BLEND",
        "output_material_mode": "MASK",
        "output_alpha_cutoff": 0.5,
        "source_gltf": "flower_empodium/flower_empodium_1k.gltf",
        "source_node_name": "flower_empodium_a_LOD0",
        "source_bin": "flower_empodium/flower_empodium.bin",
        "source_diffuse": "flower_empodium/textures/flower_empodium_diff_1k.jpg",
        "source_alpha": "flower_empodium/textures/flower_empodium_alpha_1k.png",
        "source_normal": "flower_empodium/textures/flower_empodium_nor_gl_1k.jpg",
        "source_arm": "flower_empodium/textures/flower_empodium_arm_1k.jpg",
        "output_gltf": "flower_empodium_a.gltf",
        "output_bin": "flower_empodium_a.bin",
        "output_diffuse": "textures/flower_empodium_a_base_color_alpha_1k.png",
        "output_normal": "textures/flower_empodium_a_nor_gl_1k.jpg",
        "output_arm": "textures/flower_empodium_a_arm_1k.jpg",
        "output_mesh_lod": {
            "source_supplied": True,
            "source_lod": "LOD0",
            "imported_supplied_levels": ["LOD0"],
            "alternate_source_lods_included": [],
            "godot_import_generate": True,
            "note": "The selected open-flower source node is labeled LOD0; no alternate level is present in this glTF.",
        },
    },
]

COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
COMPONENT_FORMAT = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}
COMPONENT_BYTES = {5121: 1, 5123: 2, 5125: 4, 5126: 4}


class ConversionError(RuntimeError):
    """The source intake or derived candidate does not match its contract."""


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


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=repo_root())
    parser.add_argument("--source-dir", type=Path, default=None)
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--check", action="store_true", help="verify pinned sources and staged outputs without writing")
    return parser.parse_args(argv)


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ConversionError(f"could not read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ConversionError(f"expected a JSON object in {path}")
    return value


def output_path(output_root: Path, relative: str) -> Path:
    safe = PurePosixPath(relative)
    if safe.is_absolute() or any(part in ("", ".", "..") for part in safe.parts):
        raise ConversionError(f"unsafe generated path: {relative!r}")
    root = output_root.resolve()
    target = root.joinpath(*safe.parts)
    try:
        target.resolve().relative_to(root)
    except ValueError as exc:
        raise ConversionError(f"generated path escapes output root: {relative!r}") from exc
    return target


def source_path(source_root: Path, relative: str) -> Path:
    safe = PurePosixPath(relative)
    if safe.is_absolute() or any(part in ("", ".", "..") for part in safe.parts):
        raise ConversionError(f"unsafe source path: {relative!r}")
    root = source_root.resolve()
    path = root.joinpath(*safe.parts)
    try:
        path.resolve().relative_to(root)
    except ValueError as exc:
        raise ConversionError(f"source path escapes intake root: {relative!r}") from exc
    return path


def verify_download_receipt(source_root: Path, repo: Path) -> list[dict[str, Any]]:
    manifest_path = repo / DOWNLOAD_MANIFEST
    if not manifest_path.is_file():
        raise ConversionError(f"missing source download receipt: {manifest_path}")
    try:
        receipt = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ConversionError(f"invalid source download receipt: {exc}") from exc
    if not isinstance(receipt, list):
        raise ConversionError("source download receipt must be a JSON list")
    by_key: dict[tuple[str, str], dict[str, Any]] = {}
    for item in receipt:
        if not isinstance(item, dict):
            raise ConversionError("source download receipt contains a non-object entry")
        by_key[(str(item.get("asset", "")), str(item.get("path", "")))] = item

    for relative, expected in PINNED_SOURCE_SHA256.items():
        asset, local_path = relative.split("/", 1)
        entry = by_key.get((asset, local_path))
        if entry is None:
            raise ConversionError(f"download receipt is missing {relative}")
        path = source_path(source_root, relative)
        if not path.is_file():
            raise ConversionError(f"required source input missing: {path}")
        data = path.read_bytes()
        actual_sha = sha256_bytes(data)
        if actual_sha != expected:
            raise ConversionError(f"pinned source SHA-256 mismatch for {relative}: {actual_sha}")
        if entry.get("sha256") != actual_sha or int(entry.get("size_bytes", -1)) != len(data):
            raise ConversionError(f"download receipt does not match source bytes: {relative}")
        expected_md5 = entry.get("api_md5")
        if expected_md5:
            actual_md5 = hashlib.md5(data).hexdigest()
            if actual_md5 != str(expected_md5).lower():
                raise ConversionError(f"Poly Haven API MD5 mismatch for {relative}: {actual_md5}")

    legalcode = repo / CC0_LEGALCODE
    if not legalcode.is_file() or sha256_file(legalcode) != CC0_LEGALCODE_SHA256:
        raise ConversionError("retained CC0 legal code is missing or changed")
    return receipt


def input_records(source_root: Path, repo: Path) -> list[dict[str, Any]]:
    relative_paths = set(PINNED_SOURCE_SHA256)
    relative_paths.update(
        f"{asset}/{name}"
        for asset in ("fern_02", "flower_empodium")
        for name in ("polyhaven_info.json", "polyhaven_files.json")
    )
    records: list[dict[str, Any]] = []
    for relative in sorted(relative_paths):
        path = source_path(source_root, relative)
        if not path.is_file():
            raise ConversionError(f"required provenance input missing: {path}")
        data = path.read_bytes()
        records.append({
            "path": path.relative_to(repo).as_posix(),
            "bytes": len(data),
            "sha256": sha256_bytes(data),
        })
    for path in (repo / SOURCE_NOTICE, repo / CC0_LEGALCODE, repo / DOWNLOAD_MANIFEST):
        if not path.is_file():
            raise ConversionError(f"required license/source receipt missing: {path}")
        data = path.read_bytes()
        records.append({
            "path": path.relative_to(repo).as_posix(),
            "bytes": len(data),
            "sha256": sha256_bytes(data),
        })
    return sorted(records, key=lambda item: item["path"].lower())


def read_accessor_values(document: dict[str, Any], binary: bytes, accessor_index: int) -> list[tuple[int | float, ...]]:
    accessors = document.get("accessors", [])
    if accessor_index < 0 or accessor_index >= len(accessors):
        raise ConversionError(f"accessor index is out of range: {accessor_index}")
    accessor = accessors[accessor_index]
    if "sparse" in accessor or accessor.get("normalized", False):
        raise ConversionError(f"unsupported sparse or normalized accessor: {accessor_index}")
    view_index = int(accessor.get("bufferView", -1))
    views = document.get("bufferViews", [])
    if view_index < 0 or view_index >= len(views):
        raise ConversionError(f"accessor {accessor_index} has no usable buffer view")
    view = views[view_index]
    if int(view.get("buffer", 0)) != 0:
        raise ConversionError(f"accessor {accessor_index} references a non-primary buffer")
    component_type = int(accessor.get("componentType", 0))
    component_format = COMPONENT_FORMAT.get(component_type)
    component_bytes = COMPONENT_BYTES.get(component_type)
    component_count = COMPONENTS.get(str(accessor.get("type", "")))
    if component_format is None or component_bytes is None or component_count is None:
        raise ConversionError(f"unsupported accessor type at index {accessor_index}")
    element_bytes = component_bytes * component_count
    stride = int(view.get("byteStride", element_bytes))
    if stride < element_bytes:
        raise ConversionError(f"invalid byte stride for accessor {accessor_index}")
    start = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    values: list[tuple[int | float, ...]] = []
    row_format = "<" + component_format * component_count
    for row in range(int(accessor.get("count", 0))):
        offset = start + row * stride
        if offset < 0 or offset + element_bytes > len(binary):
            raise ConversionError(f"accessor {accessor_index} reads past the source buffer")
        value = struct.unpack_from(row_format, binary, offset)
        if any(not math.isfinite(float(component)) for component in value):
            raise ConversionError(f"accessor {accessor_index} contains a non-finite value")
        values.append(value)
    return values


def bounds(values: list[tuple[int | float, ...]], width: int) -> tuple[list[float], list[float]]:
    if not values or any(len(value) < width for value in values):
        raise ConversionError("cannot compute bounds from an empty or malformed accessor")
    minimum = [min(float(value[axis]) for value in values) for axis in range(width)]
    maximum = [max(float(value[axis]) for value in values) for axis in range(width)]
    return minimum, maximum


def round_values(values: list[float]) -> list[float]:
    return [round(value, 6) for value in values]


def image_alpha_bytes(alpha_image: Image.Image) -> tuple[bytes, dict[str, Any]]:
    if alpha_image.mode not in ("I;16", "I;16L", "I;16B"):
        raise ConversionError(f"expected a 16-bit grayscale alpha PNG; found mode {alpha_image.mode}")
    values = alpha_image.get_flattened_data()
    if len(values) != alpha_image.width * alpha_image.height:
        raise ConversionError("alpha map pixel count does not match its dimensions")
    if any(int(value) < 0 or int(value) > 65535 for value in values):
        raise ConversionError("alpha map contains values outside the unsigned 16-bit range")
    scaled = bytes((int(value) * 255 + 32767) // 65535 for value in values)
    histogram = [0] * 256
    for value in scaled:
        histogram[value] += 1
    total = len(scaled)
    fractional = sum(histogram[1:255])
    cutoff = sum(histogram[128:])
    stats = {
        "source_bit_depth": 16,
        "output_bit_depth": 8,
        "source_mode": alpha_image.mode,
        "width": alpha_image.width,
        "height": alpha_image.height,
        "pixel_count": total,
        "scaling": "round-nearest: output = floor((input * 255 + 32767) / 65535)",
        "fractional_alpha_pixel_count": fractional,
        "fractional_alpha_fraction": round(fractional / total, 8),
        "pixels_at_or_above_mask_cutoff_0_5": cutoff,
        "mask_coverage_fraction": round(cutoff / total, 8),
    }
    return scaled, stats


def packed_diffuse_png(diffuse_path: Path, alpha_path: Path) -> tuple[bytes, dict[str, Any]]:
    try:
        with Image.open(diffuse_path) as diffuse_source, Image.open(alpha_path) as alpha_source:
            diffuse = diffuse_source.convert("RGB")
            if diffuse.size != alpha_source.size:
                raise ConversionError(
                    f"diffuse/alpha dimensions differ: {diffuse.size} versus {alpha_source.size}"
                )
            alpha_bytes, alpha_stats = image_alpha_bytes(alpha_source)
            alpha = Image.frombytes("L", diffuse.size, alpha_bytes)
            rgba = Image.merge("RGBA", (*diffuse.split(), alpha))
            output = io.BytesIO()
            rgba.save(output, format="PNG", compress_level=9, optimize=False)
            return output.getvalue(), alpha_stats
    except OSError as exc:
        raise ConversionError(f"could not decode source diffuse/alpha map: {exc}") from exc


def texture_image_index(document: dict[str, Any], texture_index: int, label: str) -> int:
    textures = document.get("textures", [])
    if texture_index < 0 or texture_index >= len(textures):
        raise ConversionError(f"{label} texture index is invalid")
    source_index = textures[texture_index].get("source")
    if source_index is None:
        raise ConversionError(f"{label} texture has no image source")
    images = document.get("images", [])
    if int(source_index) < 0 or int(source_index) >= len(images):
        raise ConversionError(f"{label} image index is invalid")
    return int(source_index)


def select_material_images(document: dict[str, Any], material_index: int) -> dict[str, int]:
    materials = document.get("materials", [])
    if material_index < 0 or material_index >= len(materials):
        raise ConversionError(f"primitive material index is invalid: {material_index}")
    material = materials[material_index]
    pbr = material.get("pbrMetallicRoughness", {})
    base = pbr.get("baseColorTexture", {})
    normal = material.get("normalTexture", {})
    arm = pbr.get("metallicRoughnessTexture", {})
    for label, slot in (("base color", base), ("normal", normal), ("ARM", arm)):
        if "index" not in slot:
            raise ConversionError(f"source material is missing its {label} texture")
    return {
        "base_color": texture_image_index(document, int(base["index"]), "base color"),
        "normal": texture_image_index(document, int(normal["index"]), "normal"),
        "arm": texture_image_index(document, int(arm["index"]), "ARM"),
    }


def source_document(source_root: Path, variant: dict[str, Any]) -> tuple[dict[str, Any], bytes, int, int, dict[str, Any]]:
    gltf_path = source_path(source_root, variant["source_gltf"])
    document = read_json(gltf_path)
    if document.get("asset", {}).get("version") != "2.0":
        raise ConversionError(f"{variant['id']} source is not glTF 2.0")
    node_matches = [
        (index, node)
        for index, node in enumerate(document.get("nodes", []))
        if node.get("name") == variant["source_node_name"]
    ]
    if len(node_matches) != 1:
        raise ConversionError(f"expected one source node named {variant['source_node_name']}")
    node_index, node = node_matches[0]
    if "mesh" not in node or node.get("children"):
        raise ConversionError(f"source node {node.get('name')} is not a direct mesh leaf")
    for transform in ("matrix", "rotation", "scale"):
        if transform in node:
            raise ConversionError(f"source node has unsupported {transform} transform")
    if "translation" in node:
        translation = [float(value) for value in node["translation"]]
        if len(translation) != 3:
            raise ConversionError("source gallery translation must have three values")
    else:
        translation = [0.0, 0.0, 0.0]
    mesh_index = int(node["mesh"])
    meshes = document.get("meshes", [])
    if mesh_index < 0 or mesh_index >= len(meshes):
        raise ConversionError("source node references a missing mesh")
    mesh = meshes[mesh_index]
    if mesh.get("name") != variant["source_mesh_name"]:
        raise ConversionError(
            f"source mesh name changed: expected {variant['source_mesh_name']}, found {mesh.get('name')}"
        )
    primitives = mesh.get("primitives", [])
    if len(primitives) != 1:
        raise ConversionError(f"source mesh must contain one primitive, found {len(primitives)}")
    primitive = primitives[0]
    attrs = primitive.get("attributes", {})
    for semantic in ("POSITION", "NORMAL", "TEXCOORD_0"):
        if semantic not in attrs:
            raise ConversionError(f"source mesh is missing {semantic}")
    if primitive.get("mode", 4) != 4:
        raise ConversionError("source primitive is not a triangle list")
    if "indices" not in primitive or "material" not in primitive:
        raise ConversionError("source primitive must retain indexed geometry and one material")

    buffers = document.get("buffers", [])
    if len(buffers) != 1 or buffers[0].get("uri") != Path(variant["source_bin"]).name:
        raise ConversionError("source glTF must use its one retained external binary buffer")
    binary_path = source_path(source_root, variant["source_bin"])
    binary = binary_path.read_bytes()
    if len(binary) != int(buffers[0].get("byteLength", -1)):
        raise ConversionError(f"source buffer byte length mismatch for {variant['id']}")

    position_index = int(attrs["POSITION"])
    normal_index = int(attrs["NORMAL"])
    uv_index = int(attrs["TEXCOORD_0"])
    index_index = int(primitive["indices"])
    positions = read_accessor_values(document, binary, position_index)
    normals = read_accessor_values(document, binary, normal_index)
    uvs = read_accessor_values(document, binary, uv_index)
    indices = read_accessor_values(document, binary, index_index)
    if not positions or len(positions) != len(normals) or len(positions) != len(uvs):
        raise ConversionError(f"source position/normal/UV counts do not match for {variant['id']}")
    if any(len(value) != 3 for value in positions + normals) or any(len(value) != 2 for value in uvs):
        raise ConversionError(f"source attribute accessor dimensions are malformed for {variant['id']}")
    if len(indices) % 3 != 0:
        raise ConversionError(f"source index count is not divisible by three for {variant['id']}")
    triangle_count = len(indices) // 3
    if triangle_count != variant["expected_triangles"]:
        raise ConversionError(
            f"source triangle count changed for {variant['id']}: {triangle_count}"
        )
    if any(int(index[0]) >= len(positions) for index in indices):
        raise ConversionError(f"source index exceeds its position accessor for {variant['id']}")
    uv_min, uv_max = bounds(uvs, 2)
    if min(uv_min) < -0.01 or max(uv_max) > 1.01:
        raise ConversionError(f"source UV0 falls outside the inspected atlas for {variant['id']}")

    material_index = int(primitive["material"])
    material_images = select_material_images(document, material_index)
    material = document["materials"][material_index]
    if material.get("alphaMode", "OPAQUE") != variant["source_material_mode"]:
        raise ConversionError(
            f"source alpha mode changed for {variant['id']}: {material.get('alphaMode')}"
        )
    if material.get("doubleSided") is not True:
        raise ConversionError(f"source material is no longer double-sided for {variant['id']}")
    if variant["source_material_mode"] == "MASK" and float(material.get("alphaCutoff", 0.5)) != 0.5:
        raise ConversionError(f"source MASK cutoff changed for {variant['id']}")
    for image_index in material_images.values():
        image = document.get("images", [])[image_index]
        if "uri" not in image or "bufferView" in image:
            raise ConversionError("source material images must use external URIs")

    geometry = {
        "source_node_index": node_index,
        "source_mesh_index": mesh_index,
        "source_gallery_translation_m": translation,
        "source_material_index": material_index,
        "material_images": material_images,
        "vertex_count": len(positions),
        "triangle_count": triangle_count,
        "primitive_accessors": {
            "POSITION": position_index,
            "NORMAL": normal_index,
            "TEXCOORD_0": uv_index,
            "indices": index_index,
        },
        "uv0_min": round_values(uv_min),
        "uv0_max": round_values(uv_max),
        "positions": positions,
        "position_bounds": bounds(positions, 3),
    }
    return document, binary, node_index, mesh_index, geometry


def source_metadata(source_root: Path, asset_id: str) -> dict[str, Any]:
    return read_json(source_path(source_root, f"{asset_id}/polyhaven_info.json"))


def source_file_record(repo: Path, relative: str) -> dict[str, Any]:
    path = repo / PurePosixPath(relative)
    data = path.read_bytes()
    return {"path": relative, "bytes": len(data), "sha256": sha256_bytes(data)}


def round_bounds(position_bounds: tuple[list[float], list[float]]) -> dict[str, Any]:
    minimum, maximum = position_bounds
    size = [maximum[index] - minimum[index] for index in range(3)]
    height = size[1]
    return {
        "source_bounds_m": {
            "min": round_values(minimum),
            "max": round_values(maximum),
            "size": round_values(size),
            "height": round(height, 6),
            "ground_offset": round(-minimum[1], 6),
        },
        "grounded_bounds_m": {
            "min": [round(minimum[0], 6), 0.0, round(minimum[2], 6)],
            "max": [round(maximum[0], 6), round(height, 6), round(maximum[2], 6)],
            "size": [round(size[0], 6), round(height, 6), round(size[2], 6)],
        },
    }


def build_variant(
    source_root: Path,
    output_root: Path,
    repo: Path,
    variant: dict[str, Any],
) -> tuple[dict[Path, bytes], dict[str, Any]]:
    document, binary, node_index, mesh_index, geometry = source_document(source_root, variant)
    source_node = document["nodes"][node_index]
    source_mesh = document["meshes"][mesh_index]
    material_index = geometry["source_material_index"]
    material_images = geometry["material_images"]

    input_diffuse = source_path(source_root, variant["source_diffuse"])
    input_alpha = source_path(source_root, variant["source_alpha"])
    packed_png, alpha_stats = packed_diffuse_png(input_diffuse, input_alpha)
    output_files: dict[str, bytes] = {
        variant["output_bin"]: binary,
        variant["output_diffuse"]: packed_png,
        variant["output_normal"]: source_path(source_root, variant["source_normal"]).read_bytes(),
        variant["output_arm"]: source_path(source_root, variant["source_arm"]).read_bytes(),
    }

    output_document = copy.deepcopy(document)
    selected_node = copy.deepcopy(source_node)
    selected_node.pop("translation", None)
    selected_node["mesh"] = 0
    output_document["nodes"] = [selected_node]
    output_document["meshes"] = [copy.deepcopy(source_mesh)]
    output_document["scenes"] = [copy.deepcopy(document.get("scenes", [{"nodes": [node_index]}])[0])]
    output_document["scenes"][0]["nodes"] = [0]
    output_document["scene"] = 0
    output_document["buffers"][0]["uri"] = Path(variant["output_bin"]).name

    image_uris = {
        material_images["base_color"]: variant["output_diffuse"],
        material_images["normal"]: variant["output_normal"],
        material_images["arm"]: variant["output_arm"],
    }
    if len(image_uris) != 3:
        raise ConversionError(f"expected three unique source images for {variant['id']}")
    for index, uri in image_uris.items():
        image = output_document["images"][index]
        image["uri"] = uri
        image["mimeType"] = "image/png" if index == material_images["base_color"] else "image/jpeg"

    output_material = output_document["materials"][material_index]
    output_material["alphaMode"] = variant["output_material_mode"]
    if variant["output_material_mode"] == "MASK":
        output_material["alphaCutoff"] = float(variant["output_alpha_cutoff"])
    else:
        output_material.pop("alphaCutoff", None)

    # The selected material was the only material in the source; retaining its
    # original index avoids touching the material or texture binding tables.
    if len(output_document.get("materials", [])) != 1 or material_index != 0:
        raise ConversionError(f"source material table changed for {variant['id']}")
    if len(output_document["meshes"][0].get("primitives", [])) != 1:
        raise ConversionError(f"selected mesh did not retain one source primitive for {variant['id']}")
    if output_document["meshes"][0] != source_mesh:
        raise ConversionError(f"selected source mesh changed during extraction for {variant['id']}")
    if len(output_document["nodes"]) != 1 or output_document["nodes"][0].get("mesh") != 0:
        raise ConversionError(f"output scene is not a single selected mesh for {variant['id']}")
    if any(key in output_document["nodes"][0] for key in ("translation", "rotation", "scale", "matrix")):
        raise ConversionError(f"output node still contains a gallery transform for {variant['id']}")
    if output_files[variant["output_bin"]] != source_path(source_root, variant["source_bin"]).read_bytes():
        raise ConversionError(f"output binary differs from supplier buffer for {variant['id']}")

    gltf_bytes = (json.dumps(output_document, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    output_files[variant["output_gltf"]] = gltf_bytes
    output_records = [
        {"path": relative, "bytes": len(data), "sha256": sha256_bytes(data)}
        for relative, data in sorted(output_files.items())
    ]
    output_by_path = {record["path"]: record for record in output_records}
    root_derived = DERIVED_RELATIVE.as_posix()
    model_source_entry = f"{root_derived}/{variant['output_gltf']}"
    dependency_paths = [f"{root_derived}/{relative}" for relative in sorted(output_files)]
    texture_records = [
        {"uri": uri, "source_entry": f"{root_derived}/{uri}"}
        for uri in (variant["output_diffuse"], variant["output_normal"], variant["output_arm"])
    ]
    metadata = source_metadata(source_root, variant["source_asset"])
    source_material = document["materials"][material_index]
    mode_change = variant["source_material_mode"] != variant["output_material_mode"]
    material_alpha = {
        "source_alpha_mode": variant["source_material_mode"],
        "output_alpha_mode": variant["output_material_mode"],
        "source_alpha_cutoff": source_material.get("alphaCutoff"),
        "output_alpha_cutoff": variant["output_alpha_cutoff"],
        "double_sided": bool(source_material.get("doubleSided", False)),
        "alpha_source": variant["source_alpha"],
        "alpha_packing": alpha_stats,
        "mode_change": (
            "Source BLEND changed to MASK at 0.5 to assess foliage alpha scissor and avoid blended overdraw; "
            "fractional coverage below the cutoff is discarded. This staged candidate is not visually qualified."
            if mode_change
            else "Source MASK mode and cutoff are retained."
        ),
    }
    bounds_record = round_bounds(geometry["position_bounds"])
    accessors = output_document["accessors"]
    position_accessor = accessors[geometry["primitive_accessors"]["POSITION"]]
    uv_accessor = accessors[geometry["primitive_accessors"]["TEXCOORD_0"]]
    source_geometry = {
        "source_node_index": geometry["source_node_index"],
        "source_mesh_index": geometry["source_mesh_index"],
        "source_mesh_name": variant["source_mesh_name"],
        "source_gallery_translation_m": geometry["source_gallery_translation_m"],
        "output_node_transform": "identity; supplier side-by-side gallery translation removed",
        "source_accessor_indices": geometry["primitive_accessors"],
        "vertex_count": geometry["vertex_count"],
        "source_triangles": geometry["triangle_count"],
        "uv0_min": geometry["uv0_min"],
        "uv0_max": geometry["uv0_max"],
        "position_accessor_min": position_accessor.get("min"),
        "position_accessor_max": position_accessor.get("max"),
        "uv_accessor_count": uv_accessor.get("count"),
        "geometry_policy": "supplier primitive and source binary bytes preserved exactly; no modeling, retopology, decimation or vertex edit",
    }
    conversion_proof = f"{root_derived}/proofs/{variant['id']}.json"
    variant_record = {
        "id": variant["id"],
        "source_id": variant["source_id"],
        "source_name": variant["source_name"],
        "role": variant["role"],
        "runtime_model_relative_path": f"models/realistic_understory_2026/{Path(variant['output_gltf']).name}",
        "scene": f"res://assets/landscape/vegetation/models/realistic_understory_2026/{Path(variant['output_gltf']).name}",
        "source_entry": model_source_entry,
        "source_sha256": output_by_path[variant["output_gltf"]]["sha256"],
        "source_dependency_sha256": {
            f"{root_derived}/{record['path']}": record["sha256"]
            for record in output_records
            if record["path"] != variant["output_gltf"]
        },
        "source_conversion_proof": conversion_proof,
        "source_conversion_proof_sha256": "pending",
        "source_format": "glTF 2.0",
        "source_triangles": geometry["triangle_count"],
        "source_surfaces": len(source_mesh["primitives"]),
        "source_materials": len({primitive.get("material") for primitive in source_mesh["primitives"]}),
        **bounds_record,
        "textures": texture_records,
        "dependencies": dependency_paths,
        "source_geometry": source_geometry,
        "material_alpha": material_alpha,
        "lod": variant["output_mesh_lod"],
        "visual_qualification": "Not performed; staged source candidate only.",
        "source_metadata": {
            "title": metadata.get("name"),
            "authors": metadata.get("authors", {}),
            "publisher_polycount": metadata.get("polycount"),
            "publisher_dimensions": metadata.get("dimensions"),
        },
    }
    proof_inputs = [
        {
            "path": (SOURCE_RELATIVE / relative).as_posix(),
            "bytes": source_path(source_root, relative).stat().st_size,
            "sha256": sha256_file(source_path(source_root, relative)),
        }
        for relative in (
            variant["source_gltf"], variant["source_bin"], variant["source_diffuse"],
            variant["source_alpha"], variant["source_normal"], variant["source_arm"],
        )
    ]
    proof_payload = {
        "format": "openrc-vegetation-conversion-proof v1",
        "candidate_id": variant["id"],
        "source_id": variant["source_id"],
        "source_page": variant["source_page"],
        "license": "CC0-1.0",
        "source_inputs": proof_inputs,
        "selected_geometry": source_geometry,
        "material_alpha": material_alpha,
        "bounds": bounds_record,
        "lod": variant["output_mesh_lod"],
        "outputs": output_records,
        "conversion_policy": [
            "retain the selected supplier mesh primitive and binary buffer bytes",
            "remove only the gallery node translation",
            "pack the supplier 16-bit grayscale alpha into the supplier diffuse RGB as RGBA8",
            "preserve supplied normal and ARM texture bytes",
            "no modeling, retopology, decimation, vertex edits or texture painting",
        ],
    }
    proof_bytes = (json.dumps(proof_payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")
    variant_record["source_conversion_proof_sha256"] = sha256_bytes(proof_bytes)
    proof_relative = f"proofs/{variant['id']}.json"
    output_files[proof_relative] = proof_bytes
    return {output_path(output_root, relative): data for relative, data in output_files.items()}, variant_record


def manifest_bytes_for(
    repo: Path,
    inputs: list[dict[str, Any]],
    outputs: list[dict[str, Any]],
    variants: list[dict[str, Any]],
) -> bytes:
    fern_info = read_json(repo / SOURCE_RELATIVE / "fern_02" / "polyhaven_info.json")
    flower_info = read_json(repo / SOURCE_RELATIVE / "flower_empodium" / "polyhaven_info.json")
    source_records = []
    for asset_id, info, source_id, title, url in (
        ("fern_02", fern_info, "polyhaven_fern_02", "Fern 02", "https://polyhaven.com/a/fern_02"),
        ("flower_empodium", flower_info, "polyhaven_flower_empodium", "Flower Empodium", "https://polyhaven.com/a/flower_empodium"),
    ):
        source_records.append({
            "id": source_id,
            "title": title,
            "authors": info.get("authors", {}),
            "url": url,
            "license": "CC0-1.0",
            "license_url": CC0_LICENSE_URL,
            "license_statement_url": POLYHAVEN_LICENSE_URL,
            "license_evidence": (SOURCE_RELATIVE / "SOURCE_LICENSE.md").as_posix(),
            "api_info": (SOURCE_RELATIVE / asset_id / "polyhaven_info.json").as_posix(),
            "api_files": (SOURCE_RELATIVE / asset_id / "polyhaven_files.json").as_posix(),
        })
    manifest = {
        "format": MANIFEST_FORMAT,
        "retrieved": "2026-10-20",
        "source_policy": "Supplier source files remain unchanged; only staged derivatives are written.",
        "tool": {
            "script": Path(__file__).relative_to(repo).as_posix(),
            "script_sha256": sha256_file(Path(__file__).resolve()),
            "python": platform.python_version(),
            "pillow": PILLOW_VERSION,
            "texture_encoding": "PNG RGBA8, Pillow PNG compress_level 9, optimize false",
        },
        "sources": source_records,
        "inputs": inputs,
        "outputs": outputs,
        "variants": variants,
        "staging_limits": [
            "No mesh modeling, retopology, decimation, vertex edits or texture painting.",
            "No Godot import, runtime placement, GPU capture, performance claim or visual qualification.",
            "Flower Empodium uses a recorded BLEND-to-MASK adaptation at alpha cutoff 0.5; native visual review remains required.",
        ],
    }
    return (json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")


def build_outputs(repo: Path, source_root: Path, output_root: Path) -> dict[Path, bytes]:
    if PILLOW_VERSION != "12.3.0":
        raise ConversionError(f"Pillow 12.3.0 is pinned for deterministic texture packing; found {PILLOW_VERSION}")
    verify_download_receipt(source_root, repo)
    inputs = input_records(source_root, repo)
    all_outputs: dict[Path, bytes] = {}
    variants: list[dict[str, Any]] = []
    for variant in VARIANTS:
        output_files, variant_record = build_variant(source_root, output_root, repo, variant)
        for path, data in output_files.items():
            if path in all_outputs:
                raise ConversionError(f"candidate output collision: {path}")
            all_outputs[path] = data
        variants.append(variant_record)
    output_records = [
        {
            "path": path.relative_to(output_root.resolve()).as_posix(),
            "bytes": len(data),
            "sha256": sha256_bytes(data),
        }
        for path, data in sorted(all_outputs.items(), key=lambda item: item[0].as_posix().lower())
    ]
    manifest_data = manifest_bytes_for(repo, inputs, output_records, variants)
    manifest_path = output_path(output_root, CONVERSION_MANIFEST)
    all_outputs[manifest_path] = manifest_data
    return all_outputs


def write_if_changed(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and path.read_bytes() == data:
        return
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(data)
    temporary.replace(path)


def check_outputs(expected: dict[Path, bytes]) -> None:
    failures: list[str] = []
    for path, expected_bytes in expected.items():
        if not path.is_file():
            failures.append(f"missing output: {path}")
            continue
        actual = path.read_bytes()
        if actual != expected_bytes:
            failures.append(f"output differs: {path}")
    if failures:
        raise ConversionError("\n".join(failures))


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    repo = args.repo_root.resolve()
    source_root = args.source_dir or (repo / SOURCE_RELATIVE)
    if not source_root.is_absolute():
        source_root = repo / source_root
    source_root = source_root.resolve()
    output_root = args.output_dir or (repo / DERIVED_RELATIVE)
    if not output_root.is_absolute():
        output_root = repo / output_root
    output_root = output_root.resolve()
    try:
        output_root.relative_to(repo)
    except ValueError as exc:
        raise ConversionError("output directory must remain under the repository root") from exc
    expected = build_outputs(repo, source_root, output_root)
    if args.check:
        check_outputs(expected)
    else:
        for path, data in expected.items():
            write_if_changed(path, data)
    variants = [f"{entry['id']}={entry['source_triangles']} tri" for entry in json.loads(
        expected[output_path(output_root, CONVERSION_MANIFEST)].decode("utf-8")
    )["variants"]]
    action = "verified" if args.check else "staged"
    print(f"{action} {len(variants)} source-faithful vegetation candidates: {', '.join(variants)}")
    print(f"output={output_root}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ConversionError as exc:
        print(f"vegetation conversion failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
