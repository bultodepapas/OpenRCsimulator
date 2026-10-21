#!/usr/bin/env python3
"""Build a pinned Quaternius vegetation library with a narrow runtime color repair."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from io import BytesIO
from pathlib import Path, PurePosixPath, PureWindowsPath
import struct
import sys
from zipfile import BadZipFile, ZipFile


ROOT = Path(__file__).resolve().parents[3]
ARCHIVE = ROOT / "assets/landscape/vegetation/source/quaternius_stylized_nature_megakit_standard.zip"
SOURCE_LICENSE = ROOT / "assets/landscape/vegetation/source/License_Standard.txt"
RUNTIME = ROOT / "app/assets/landscape/vegetation"
RUNTIME_MODELS = RUNTIME / "models"
RUNTIME_LICENSE = RUNTIME / "LICENSE.txt"
RUNTIME_CATALOG = RUNTIME / "catalog.json"

ARCHIVE_SHA256 = "298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9"
ARCHIVE_BYTES = 104_088_529
LICENSE_ENTRY = "License_Standard.txt"
LICENSE_SHA256 = "120710e542c3ebaf83856c4eb55b4a1e680593b39302eba7fdc5d942dfe78c58"
SOURCE_URL = "https://quaternius.itch.io/stylized-nature-megakit"
SOURCE_UPLOAD_ID = "11055123"
RETRIEVED = "2026-10-13"

CROPS_ARCHIVE = ROOT / "assets/landscape/vegetation/source/quaternius_lowpoly_crops_cc0.zip"
CROPS_ARCHIVE_SHA256 = "48de7f1e092750a3832501e79d1463abeec8218c76090fc4b81fa8dfccacdb52"
CROPS_ARCHIVE_BYTES = 13_368_975
CROPS_SOURCE_URL = "https://opengameart.org/content/lowpoly-crops-pack"
CROPS_SOURCE_ENTRY_PREFIX = "Nature Crops Pack - Jan 2020/OBJ/"
CROPS_NOTICE = ROOT / "assets/landscape/vegetation/source/Quaternius_Crops_CC0.txt"

REED_ARCHIVE = ROOT / "assets/landscape/vegetation/source/aredon_lowpoly_reed_cc0.zip"
REED_ARCHIVE_SHA256 = "03fd4f90d92618090829bac1152e4280327edb179139ae3f0c66542af31b89bd"
REED_ARCHIVE_BYTES = 140_207
REED_SOURCE_URL = "https://opengameart.org/content/lowpoly-reed"
REED_NOTICE = ROOT / "assets/landscape/vegetation/source/Aredon_Reed_CC0.txt"

OAK_SOURCE_DIR = ROOT / "assets/landscape/vegetation/source/opengameart_oak_tree_lod_2026"
OAK_ARCHIVE = OAK_SOURCE_DIR / "quercus_A_packed_v1_0.zip"
OAK_ARCHIVE_BYTES = 2_222_050
OAK_ARCHIVE_SHA256 = "496f250c29eb1f56e391e55989530028e156ae43a3d1eb9f52ab09aa1bccbebf"
OAK_BLEND_ENTRY = "quercus_A_packed_v1.blend"
OAK_BLEND = OAK_SOURCE_DIR / OAK_BLEND_ENTRY
OAK_BLEND_BYTES = 2_856_188
OAK_BLEND_SHA256 = "3b32573acd4e8eb5b7e0a96aa363932ec785a854d6e8c71f56f29b10f5abd37c"
OAK_CONVERSION_DIR = OAK_SOURCE_DIR / "gltf/lod0"
OAK_CONVERSION_PROOF = OAK_SOURCE_DIR / "CONVERSION-PROOF-LOD0.json"
OAK_CONVERSION_PROOF_BYTES = 4_573
OAK_CONVERSION_PROOF_SHA256 = "2a3b0c2d6e4bd940c53cdf4bee5af31ff9753b3b77b032962867a3fa89f72014"
OAK_LICENSE_SOURCE = OAK_SOURCE_DIR / "LICENSE_OAK.txt"
OAK_LICENSE_BYTES = 2_245
OAK_LICENSE_SHA256 = "1be8dab83f4107623eeba4d77e3d66091068e839e1a8b688ea1bf867c2b43e40"
OAK_LICENSE_OUTPUT = "LICENSE_OAK.txt"
OAK_SOURCE_URL = "https://opengameart.org/content/oak-tree"
OAK_DOWNLOAD_URL = "https://opengameart.org/sites/default/files/quercus_A_packed_v1_0.zip"
OAK_LICENSE_URL = "https://creativecommons.org/licenses/by-sa/3.0/"
OAK_AUTHOR = "lauris71"
OAK_RETRIEVED = "2026-10-18"
OAK_CONVERSION_FILES = (
    {
        "entry": "oak_lod0.gltf",
        "bytes": 1_970,
        "sha256": "03f2c728f1b21f52d3278ee7abf81b91cf135d4cc4e4bc819e1b5a26b41491d7",
    },
    {
        "entry": "oak_lod0.bin",
        "bytes": 341_388,
        "sha256": "61e23239d35d78f84693d15350b90961cc42185aac16660df0a4416668cfd93c",
    },
    {
        "entry": "Quercus_A_1024.png",
        "bytes": 1_623_204,
        "sha256": "2f3b85071d918bc7ca69b7cc65e726d6fea4f5a3540ef67a8b930eb0f6bb4015",
    },
)
OAK_GLTF_ENTRY = "glTF/oak_lod0.gltf"
OAK_ASSET_ID = "oak_tree"
OAK_SOURCE_ID = "opengameart_oak_tree_lod_2026"
OAK_DESCRIPTION = "Oak tree, supplier LOD0"

MAPLE_SOURCE_DIR = ROOT / "assets/landscape/vegetation/source/lolipop_maple_2026"
MAPLE_DERIVED_DIR = ROOT / "assets/landscape/vegetation/derived/lolipop_maple_2026"
MAPLE_MANIFEST = MAPLE_DERIVED_DIR / "conversion_manifest.json"
MAPLE_GLTF = "maple_large_3_lod1.gltf"

LANDSCAPELAB_SOURCE_DIR = ROOT / "assets/landscape/vegetation/source/landscapelab_tree_2026"
LANDSCAPELAB_DERIVED_DIR = ROOT / "assets/landscape/vegetation/derived/landscapelab_tree_2026"
LANDSCAPELAB_MANIFEST = LANDSCAPELAB_DERIVED_DIR / "conversion_manifest.json"
LANDSCAPELAB_MANIFEST_SHA256 = "520a6362a8e354ef6571ea754fe45b98baf4fa355dcebd5a7aec21ee44f8ae82"
LANDSCAPELAB_REVISION = "dfdde034c3547f9876967653d98827bd5348e52e"
# Runtime notice path; its source is the four-tree library notice named by the manifest.
LANDSCAPELAB_NOTICE = "LICENSE_LANDSCAPELAB.txt"
LANDSCAPELAB_NOTICE_SOURCE = "LICENSE_LANDSCAPELAB_LIBRARY.txt"
LANDSCAPELAB_ASSETS = {
    "landscapelab_quercus": {
        "source_name": "Quercus",
        "filename": "quercus.glb",
        "runtime_subdir": "quercus",
        "bytes": 7_389_596,
        "sha256": "d4fb683939a0a6e28fb1ff409cbc73c306207f093bfcb40110ff1fe79fabbd1e",
        "triangles": 7_016,
        "surfaces": 2,
    },
    "landscapelab_pine": {
        "source_name": "Pine",
        "filename": "pine_joined.glb",
        "runtime_subdir": "pine",
        "bytes": 6_788_748,
        "sha256": "74d3d4d0f541522163b1e4d24931e76640df6fdd758db0f963d109faf1a9bcf8",
        "triangles": 4_246,
        "surfaces": 2,
    },
    "landscapelab_fagus": {
        "source_name": "Fagus",
        "filename": "Fagus.glb",
        "runtime_subdir": "fagus",
        "bytes": 7_239_640,
        "sha256": "32542974981ccdbb3cf984e3c8bc1c1d87524fbc08589a69ed2658aba9619cff",
        "triangles": 9_312,
        "surfaces": 2,
    },
    "landscapelab_quercus2": {
        "source_name": "Quercus 2",
        "filename": "quercus2.glb",
        "runtime_subdir": "quercus2",
        "bytes": 7_286_744,
        "sha256": "e668ac1f03de63f1222754798802fae06620c3c0cac9993869bcaa87d33e0c6d",
        "triangles": 11_144,
        "surfaces": 2,
    },
}

UNDERSTORY_SOURCE_DIR = ROOT / "assets/landscape/vegetation/source/realistic_understory_2026"
UNDERSTORY_DERIVED_DIR = ROOT / "assets/landscape/vegetation/derived/realistic_understory_2026"
UNDERSTORY_MANIFEST = UNDERSTORY_DERIVED_DIR / "conversion_manifest.json"
UNDERSTORY_MANIFEST_SHA256 = "ab4ea6f54327eb4e8501c90c472a0ca71be8e8a9ab1ed5eeaa12a62c4dd93514"
UNDERSTORY_NOTICE = "LICENSE_UNDERSTORY.txt"
UNDERSTORY_ASSETS = {
    "polyhaven_fern_02_a": {
        "source_id": "polyhaven_fern_02",
        "source_name": "fern_02_a",
        "role": "herb",
        "triangles": 784,
        "sha256": "a0159c5a44a58a520d4e366deddfa1630326a8f91e068233d30ed8bd67acfda1",
    },
    "polyhaven_flower_empodium_a": {
        "source_id": "polyhaven_flower_empodium",
        "source_name": "flower_empodium_a_LOD0",
        "role": "flower",
        "triangles": 758,
        "sha256": "3b310bc6483f6c0e3131bb47ec406c1fe14324e5fc06dddbacaaeb590831c88e",
    },
}

SOURCE_NOTICES = {
    CROPS_NOTICE: (
        "Downloaded source: LowPoly Crops Pack\n"
        "Author: Quaternius\n"
        f"Source page: {CROPS_SOURCE_URL}\n"
        "License: CC0 1.0 Universal (license shown on the OpenGameArt source page).\n"
        "Original archive: quaternius_lowpoly_crops_cc0.zip\n"
        f"Retrieved: {RETRIEVED}\n"
        f"Bytes: {CROPS_ARCHIVE_BYTES}\n"
        f"SHA-256: {CROPS_ARCHIVE_SHA256}\n"
        "Selected files are copied byte-for-byte from the archive's OBJ directory.\n"
    ).encode("utf-8"),
    REED_NOTICE: (
        "Downloaded source: LowPoly Reed\n"
        "Author: Aredon\n"
        f"Source page: {REED_SOURCE_URL}\n"
        "License: CC0 Public Domain (license shown on the OpenGameArt source page).\n"
        "Original archive: aredon_lowpoly_reed_cc0.zip\n"
        f"Retrieved: {RETRIEVED}\n"
        f"Bytes: {REED_ARCHIVE_BYTES}\n"
        f"SHA-256: {REED_ARCHIVE_SHA256}\n"
        "Selected OBJ and MTL files are copied byte-for-byte from the archive.\n"
    ).encode("utf-8"),
}

# These are direct glTF mesh exports from the Standard archive. The pipeline
# preserves their geometry and source files; only runtime tree COLOR_0 buffer
# values within the reviewed float tolerance may be derived below.
ASSETS = (
    ("common_tree_1", "CommonTree_1", "tree", "mature broadleaf tree"),
    ("common_tree_2", "CommonTree_2", "tree", "fuller branching broadleaf tree"),
    ("common_tree_3", "CommonTree_3", "tree", "upright broadleaf tree"),
    ("common_tree_4", "CommonTree_4", "tree", "sparse crown broadleaf tree"),
    ("pine_1", "Pine_1", "tree", "mature pine tree"),
    ("pine_2", "Pine_2", "tree", "broad-cone pine tree"),
    ("pine_3", "Pine_3", "tree", "open-lower-trunk pine tree"),
    ("bush_common", "Bush_Common", "shrub", "leafy shrub"),
    ("bush_common_flowers", "Bush_Common_Flowers", "shrub", "flowering shrub"),
    ("grass_common_short", "Grass_Common_Short", "grass", "short meadow grass clump"),
    ("grass_common_tall", "Grass_Common_Tall", "grass", "tall meadow grass clump"),
    ("grass_wispy_tall", "Grass_Wispy_Tall", "grass", "wispy tall grass clump"),
    ("fern_1", "Fern_1", "herb", "fern"),
    ("flower_3_group", "Flower_3_Group", "flower", "flower group, family 3"),
    ("flower_4_group", "Flower_4_Group", "flower", "flower group, family 4"),
    ("clover_1", "Clover_1", "flower", "clover groundcover"),
)

CROP_ASSETS = (
    ("corn_4", "Corn_4", "mature corn plant"),
    ("wheat_4", "Wheat_4", "mature wheat stalk"),
)

REED_ASSETS = (
    ("reed_aredon", "reed", "low-poly reed clump"),
)

TREE_COLOR_OVERSHOOT_LIMIT = 1.0002
TREE_COLOR_DERIVATION_METHOD = (
    "Clamp finite float COLOR_0 components above 1 and at or below 1.0002 to 1; "
    "reject negative, non-finite, over-limit, or unsupported color accessors."
)


class BuildError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def archive_path(value: str) -> str:
    """Accept only a safe, archive-relative POSIX path."""
    parsed = PurePosixPath(value)
    windows = PureWindowsPath(value)
    if (
        parsed.is_absolute()
        or windows.drive
        or windows.root
        or not parsed.parts
        or any(part in ("", ".", "..") for part in parsed.parts)
        or ":" in value
    ):
        raise BuildError(f"unsafe archive path: {value!r}")
    if "\\" in value or "\x00" in value:
        raise BuildError(f"unsafe archive path: {value!r}")
    return parsed.as_posix()


def read_member(archive: ZipFile, name: str) -> bytes:
    safe_name = archive_path(name)
    try:
        return archive.read(safe_name)
    except KeyError as exc:
        raise BuildError(f"missing source archive member: {safe_name}") from exc


def read_oak_conversion_proof() -> tuple[bytes, dict]:
    if not OAK_CONVERSION_PROOF.is_file():
        raise BuildError(f"missing pinned oak LOD0 conversion proof: {OAK_CONVERSION_PROOF}")
    proof_bytes = OAK_CONVERSION_PROOF.read_bytes()
    if (
        len(proof_bytes) != OAK_CONVERSION_PROOF_BYTES
        or sha256_bytes(proof_bytes) != OAK_CONVERSION_PROOF_SHA256
    ):
        raise BuildError("oak LOD0 conversion proof changed from its reviewed pin")
    try:
        proof = json.loads(proof_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BuildError(f"invalid JSON in oak LOD0 conversion proof: {exc}") from exc

    conversion = proof.get("conversion", {})
    if (
        proof.get("format") != "openrc-oak-conversion-proof v2"
        or conversion.get("source_object_count") != 36
        or conversion.get("source_vertex_count_sum") != 4_407
        or conversion.get("baked_vertex_count") != 4_407
        or conversion.get("source_polygon_count_sum") != 2_791
        or conversion.get("baked_polygon_count") != 2_791
        or conversion.get("source_triangulated_triangle_count") != 5_303
        or conversion.get("baked_triangulated_triangle_count") != 5_303
        or conversion.get("source_material_names") != ["M_Quercus"]
        or conversion.get("triangles_preserved") is not True
        or conversion.get("polygons_preserved") is not True
        or conversion.get("custom_loop_normals") is not True
        or conversion.get("decimation") is not False
        or conversion.get("geometry_created") is not False
    ):
        raise BuildError("oak LOD0 conversion proof does not match the reviewed source contract")

    inputs = proof.get("inputs", {})
    if (
        inputs.get("archive", {}).get("sha256") != OAK_ARCHIVE_SHA256
        or inputs.get("blend", {}).get("sha256") != OAK_BLEND_SHA256
    ):
        raise BuildError("oak conversion proof does not pin the reviewed original inputs")

    material_mapping = proof.get("material_mapping", {})
    if (
        material_mapping.get("alpha_mode") != "BLEND"
        or material_mapping.get("glTF_metallic_factor") != 0.0
        or material_mapping.get("glTF_roughness_factor") != 1.0
        or material_mapping.get("source_legacy_specular_intensity") != 0.0
        or "Godot 4.7 ignores it" not in material_mapping.get("specular_note", "")
    ):
        raise BuildError("oak material mapping proof does not match the reviewed matte BLEND import")

    loop_errors = conversion.get("max_source_to_baked_error", {})
    if loop_errors.get("world_position_m") != 0.0 or loop_errors.get("uv_unitless") != 0.0:
        raise BuildError("oak LOD0 conversion proof reports changed source positions or UVs")

    proof_outputs = {
        item.get("path"): (item.get("bytes"), item.get("sha256"))
        for item in proof.get("outputs", [])
    }
    expected_outputs = {
        item["entry"]: (item["bytes"], item["sha256"])
        for item in OAK_CONVERSION_FILES
    }
    if proof_outputs != expected_outputs:
        raise BuildError("oak LOD0 conversion proof output hashes do not match the pinned files")
    return proof_bytes, proof


def read_oak_license() -> bytes:
    if not OAK_LICENSE_SOURCE.is_file():
        raise BuildError(f"missing oak attribution/license notice: {OAK_LICENSE_SOURCE}")
    license_bytes = OAK_LICENSE_SOURCE.read_bytes()
    if len(license_bytes) != OAK_LICENSE_BYTES or sha256_bytes(license_bytes) != OAK_LICENSE_SHA256:
        raise BuildError("oak attribution/license notice changed from its reviewed pin")
    return license_bytes


def open_oak_conversion_archive() -> ZipFile:
    """Verify pinned oak inputs/exports and expose the separate glTF files in memory."""
    if not OAK_ARCHIVE.is_file():
        raise BuildError(f"missing pinned oak source archive: {OAK_ARCHIVE}")
    if OAK_ARCHIVE.stat().st_size != OAK_ARCHIVE_BYTES or sha256_file(OAK_ARCHIVE) != OAK_ARCHIVE_SHA256:
        raise BuildError("oak source archive does not match the pinned OpenGameArt download")
    if not OAK_BLEND.is_file():
        raise BuildError(f"missing extracted oak source blend: {OAK_BLEND}")
    blend_bytes = OAK_BLEND.read_bytes()
    if len(blend_bytes) != OAK_BLEND_BYTES or sha256_bytes(blend_bytes) != OAK_BLEND_SHA256:
        raise BuildError("extracted oak source blend does not match the pinned archive member")
    try:
        with ZipFile(OAK_ARCHIVE) as original_archive:
            archived_blend = read_member(original_archive, OAK_BLEND_ENTRY)
    except BadZipFile as exc:
        raise BuildError(f"oak source archive is not a valid ZIP: {exc}") from exc
    if archived_blend != blend_bytes:
        raise BuildError("extracted oak blend differs from the original downloaded archive member")
    read_oak_conversion_proof()
    read_oak_license()

    conversion_buffer = BytesIO()
    with ZipFile(conversion_buffer, "w") as conversion_archive:
        for item in OAK_CONVERSION_FILES:
            source_path = OAK_CONVERSION_DIR / item["entry"]
            if not source_path.is_file():
                raise BuildError(f"missing pinned oak conversion output: {source_path}")
            data = source_path.read_bytes()
            if len(data) != item["bytes"] or sha256_bytes(data) != item["sha256"]:
                raise BuildError(f"oak conversion output changed from its pin: {source_path}")
            conversion_archive.writestr(f"glTF/{archive_path(item['entry'])}", data)
    conversion_buffer.seek(0)
    return ZipFile(conversion_buffer)


def gltf_metadata(archive: ZipFile, source_name: str, gltf_bytes: bytes) -> dict:
    try:
        gltf = json.loads(gltf_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BuildError(f"invalid JSON in glTF {source_name}: {exc}") from exc

    triangles = 0
    surfaces = 0
    material_indices: set[int] = set()
    minimum = [float("inf"), float("inf"), float("inf")]
    maximum = [float("-inf"), float("-inf"), float("-inf")]
    for mesh in gltf.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            surfaces += 1
            index = primitive.get("indices")
            if index is not None:
                accessors = gltf.get("accessors", [])
                if index >= len(accessors):
                    raise BuildError(f"{source_name}: primitive index accessor {index} is missing")
                count = accessors[index].get("count", 0)
            else:
                position = primitive.get("attributes", {}).get("POSITION")
                accessors = gltf.get("accessors", [])
                if position is None or position >= len(accessors):
                    raise BuildError(f"{source_name}: primitive has no usable index or position accessor")
                count = accessors[position].get("count", 0)
            if count % 3 != 0:
                raise BuildError(f"{source_name}: triangle index count {count} is not divisible by three")
            triangles += count // 3

            material = primitive.get("material")
            if material is not None:
                material_indices.add(material)
            position_index = primitive.get("attributes", {}).get("POSITION")
            if position_index is None or position_index >= len(accessors):
                raise BuildError(f"{source_name}: primitive has no usable position accessor")
            bounds = accessors[position_index]
            if len(bounds.get("min", [])) < 3 or len(bounds.get("max", [])) < 3:
                raise BuildError(f"{source_name}: position accessor has no 3D bounds")
            for axis in range(3):
                minimum[axis] = min(minimum[axis], float(bounds["min"][axis]))
                maximum[axis] = max(maximum[axis], float(bounds["max"][axis]))

    if triangles <= 0 or surfaces <= 0 or any(minimum[axis] >= maximum[axis] for axis in range(3)):
        raise BuildError(f"{source_name}: glTF has no measurable triangle geometry")

    height = maximum[1] - minimum[1]
    grounded_minimum = [minimum[0], 0.0, minimum[2]]
    grounded_maximum = [maximum[0], height, maximum[2]]

    textures: list[dict] = []
    for image in gltf.get("images", []):
        uri = image.get("uri")
        if not isinstance(uri, str):
            raise BuildError(f"{source_name}: embedded or missing image URIs are unsupported")
        uri = archive_path(uri)
        textures.append({"uri": uri, "source_entry": f"glTF/{uri}"})

    buffers: list[str] = []
    for buffer in gltf.get("buffers", []):
        uri = buffer.get("uri")
        if not isinstance(uri, str):
            raise BuildError(f"{source_name}: embedded or missing buffer URIs are unsupported")
        buffers.append(archive_path(uri))

    model_base = PurePosixPath(source_name).parent
    dependencies = [source_name]
    dependencies.extend((model_base / buffer).as_posix() for buffer in buffers)
    dependencies.extend((model_base / item["uri"]).as_posix() for item in textures)

    # The source pack uses direct mesh nodes. Refuse transforms that would make
    # raw accessor bounds differ from the imported scene's local bounds.
    for node in gltf.get("nodes", []):
        if "mesh" in node and any(key in node for key in ("matrix", "translation", "rotation", "scale")):
            raise BuildError(f"{source_name}: transformed mesh node requires explicit bounds review")

    return {
        "source_triangles": triangles,
        "source_surfaces": surfaces,
        "source_materials": len(material_indices),
        "source_bounds_m": {
            "min": [round(value, 6) for value in minimum],
            "max": [round(value, 6) for value in maximum],
            "size": [round(maximum[axis] - minimum[axis], 6) for axis in range(3)],
            "height": round(height, 6),
            "ground_offset": round(-minimum[1], 6),
        },
        "grounded_bounds_m": {
            "min": [round(value, 6) for value in grounded_minimum],
            "max": [round(value, 6) for value in grounded_maximum],
            "size": [round(grounded_maximum[axis] - grounded_minimum[axis], 6) for axis in range(3)],
        },
        "textures": sorted(textures, key=lambda item: item["uri"].lower()),
        "dependencies": sorted(set(dependencies), key=str.lower),
    }


def derive_tree_color_buffer(
    source_name: str,
    gltf_bytes: bytes,
    buffer_bytes: bytes,
    buffer_index: int,
) -> tuple[bytes, dict]:
    """Repair only the reviewed float COLOR_0 overshoot in a runtime tree buffer."""
    try:
        gltf = json.loads(gltf_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BuildError(f"invalid JSON in glTF {source_name}: {exc}") from exc

    buffers = gltf.get("buffers", [])
    if buffer_index >= len(buffers) or buffer_index < 0:
        raise BuildError(f"{source_name}: tree buffer index is missing")
    declared_buffer_bytes = buffers[buffer_index].get("byteLength")
    if not isinstance(declared_buffer_bytes, int) or declared_buffer_bytes != len(buffer_bytes):
        raise BuildError(
            f"{source_name}: tree buffer byteLength does not match its source member"
        )
    if gltf.get("animations") or gltf.get("skins"):
        raise BuildError(f"{source_name}: animated or skinned tree buffers are unsupported")

    accessors = gltf.get("accessors", [])
    buffer_views = gltf.get("bufferViews", [])
    color_indices: set[int] = set()
    other_indices: set[int] = set()
    for mesh in gltf.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if primitive.get("targets"):
                raise BuildError(f"{source_name}: morph-target tree buffers are unsupported")
            attributes = primitive.get("attributes", {})
            for semantic, index in attributes.items():
                if not isinstance(index, int) or index < 0 or index >= len(accessors):
                    raise BuildError(f"{source_name}: invalid accessor for {semantic}")
                (color_indices if semantic == "COLOR_0" else other_indices).add(index)
            index_accessor = primitive.get("indices")
            if index_accessor is not None:
                if not isinstance(index_accessor, int) or index_accessor < 0 or index_accessor >= len(accessors):
                    raise BuildError(f"{source_name}: invalid primitive index accessor")
                other_indices.add(index_accessor)
    if not color_indices:
        raise BuildError(f"{source_name}: tree has no COLOR_0 accessor to inspect")
    if color_indices & other_indices:
        raise BuildError(f"{source_name}: COLOR_0 accessor is reused by another semantic")

    # Also protect unreferenced accessors: no unrelated accessor may share bytes
    # with a color range that this derivation would touch.
    other_indices.update(set(range(len(accessors))) - color_indices)
    patch_offsets: set[int] = set()
    source_color_values: dict[int, float] = {}
    for accessor_index in sorted(color_indices):
        accessor = accessors[accessor_index]
        if accessor.get("componentType") != 5126 or accessor.get("type") not in ("VEC3", "VEC4"):
            raise BuildError(f"{source_name}: COLOR_0 accessor must use FLOAT VEC3/VEC4")
        if accessor.get("normalized") or accessor.get("sparse"):
            raise BuildError(f"{source_name}: normalized or sparse COLOR_0 is unsupported")
        view_index = accessor.get("bufferView")
        if not isinstance(view_index, int) or view_index < 0 or view_index >= len(buffer_views):
            raise BuildError(f"{source_name}: COLOR_0 accessor has no valid bufferView")
        view = buffer_views[view_index]
        if view.get("buffer") != buffer_index:
            raise BuildError(f"{source_name}: COLOR_0 accessor points to another buffer")
        count = accessor.get("count")
        if not isinstance(count, int) or count <= 0:
            raise BuildError(f"{source_name}: COLOR_0 accessor has invalid count")
        components = 3 if accessor["type"] == "VEC3" else 4
        element_bytes = components * 4
        stride = view.get("byteStride", element_bytes)
        view_offset = view.get("byteOffset", 0)
        accessor_offset = accessor.get("byteOffset", 0)
        view_length = view.get("byteLength")
        if (
            not isinstance(stride, int)
            or stride < element_bytes
            or stride % 4 != 0
            or not isinstance(view_offset, int)
            or not isinstance(accessor_offset, int)
            or view_offset < 0
            or accessor_offset < 0
            or not isinstance(view_length, int)
            or view_length < 0
            or view_offset + view_length > len(buffer_bytes)
            or accessor_offset % 4 != 0
        ):
            raise BuildError(f"{source_name}: invalid COLOR_0 bufferView layout")
        first = view_offset + accessor_offset
        if first + (count - 1) * stride + element_bytes > view_offset + view_length:
            raise BuildError(f"{source_name}: COLOR_0 accessor exceeds its bufferView")
        for element in range(count):
            for component in range(components):
                offset = first + element * stride + component * 4
                value = struct.unpack_from("<f", buffer_bytes, offset)[0]
                if not math.isfinite(value) or value < 0.0 or value > TREE_COLOR_OVERSHOOT_LIMIT:
                    raise BuildError(
                        f"{source_name}: COLOR_0 value outside reviewed range at byte {offset}: {value!r}"
                    )
                if offset in source_color_values:
                    raise BuildError(f"{source_name}: overlapping COLOR_0 component ranges")
                source_color_values[offset] = value
                if value > 1.0:
                    patch_offsets.add(offset)

    for accessor_index in sorted(other_indices):
        accessor = accessors[accessor_index]
        view_index = accessor.get("bufferView")
        if view_index is None:
            continue
        if not isinstance(view_index, int) or view_index < 0 or view_index >= len(buffer_views):
            raise BuildError(f"{source_name}: non-color accessor has invalid bufferView")
        view = buffer_views[view_index]
        if view.get("buffer") != buffer_index:
            continue
        start = view.get("byteOffset", 0)
        length = view.get("byteLength")
        if not isinstance(start, int) or not isinstance(length, int) or start < 0 or length < 0:
            raise BuildError(f"{source_name}: non-color accessor has invalid bufferView bounds")
        end = start + length
        if any(start < offset + 4 and offset < end for offset in patch_offsets):
            raise BuildError(f"{source_name}: COLOR_0 patch overlaps non-color accessor storage")

    runtime_bytes = bytearray(buffer_bytes)
    for offset in patch_offsets:
        struct.pack_into("<f", runtime_bytes, offset, 1.0)
    result = bytes(runtime_bytes)
    return result, {
        "method": TREE_COLOR_DERIVATION_METHOD,
        "derivation_count": len(patch_offsets),
        "source_buffer_sha256": sha256_bytes(buffer_bytes),
        "runtime_buffer_sha256": sha256_bytes(result),
    }


def obj_metadata(source_name: str, obj_bytes: bytes) -> dict:
    try:
        source_text = obj_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise BuildError(f"invalid UTF-8 in OBJ {source_name}: {exc}") from exc

    vertices: list[tuple[float, float, float]] = []
    triangles = 0
    material_names: set[str] = set()
    material_libraries: set[str] = set()
    for line_number, line in enumerate(source_text.splitlines(), start=1):
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "v":
            if len(fields) < 4:
                raise BuildError(f"{source_name}:{line_number}: malformed vertex")
            try:
                vertices.append((float(fields[1]), float(fields[2]), float(fields[3])))
            except ValueError as exc:
                raise BuildError(f"{source_name}:{line_number}: nonnumeric vertex") from exc
        elif fields[0] == "f":
            if len(fields) < 4:
                raise BuildError(f"{source_name}:{line_number}: face has fewer than three vertices")
            triangles += len(fields) - 3
        elif fields[0] == "usemtl" and len(fields) > 1:
            material_names.add(fields[1])
        elif fields[0] == "mtllib" and len(fields) > 1:
            material_libraries.update(archive_path(name) for name in fields[1:])

    if not vertices or triangles <= 0:
        raise BuildError(f"{source_name}: OBJ has no measurable triangle geometry")
    if not material_libraries:
        raise BuildError(f"{source_name}: OBJ is missing its MTL material library")

    minimum = [min(vertex[axis] for vertex in vertices) for axis in range(3)]
    maximum = [max(vertex[axis] for vertex in vertices) for axis in range(3)]
    if any(minimum[axis] >= maximum[axis] for axis in range(3)):
        raise BuildError(f"{source_name}: OBJ has degenerate 3D bounds")
    height = maximum[1] - minimum[1]
    grounded_minimum = [minimum[0], 0.0, minimum[2]]
    grounded_maximum = [maximum[0], height, maximum[2]]

    return {
        "source_triangles": triangles,
        "source_surfaces": max(1, len(material_names)),
        "source_materials": len(material_names),
        "source_bounds_m": {
            "min": [round(value, 6) for value in minimum],
            "max": [round(value, 6) for value in maximum],
            "size": [round(maximum[axis] - minimum[axis], 6) for axis in range(3)],
            "height": round(height, 6),
            "ground_offset": round(-minimum[1], 6),
        },
        "grounded_bounds_m": {
            "min": [round(value, 6) for value in grounded_minimum],
            "max": [round(value, 6) for value in grounded_maximum],
            "size": [round(grounded_maximum[axis] - grounded_minimum[axis], 6) for axis in range(3)],
        },
        "material_libraries": sorted(material_libraries, key=str.lower),
    }


def catalog_for(
    archive: ZipFile,
    crops_archive: ZipFile,
    reed_archive: ZipFile,
    oak_archive: ZipFile,
) -> tuple[dict, dict[str, bytes]]:
    license_bytes = read_member(archive, LICENSE_ENTRY)
    if sha256_bytes(license_bytes) != LICENSE_SHA256:
        raise BuildError("embedded Standard license hash does not match the pinned CC0 evidence")

    pending_files: dict[str, bytes] = {"LICENSE.txt": license_bytes}
    file_origins: dict[str, str] = {"LICENSE.txt": LICENSE_ENTRY}
    source_member_bytes: dict[str, bytes] = {}
    assets: list[dict] = []
    for asset_id, model_name, role, description in ASSETS:
        source_entry = f"glTF/{model_name}.gltf"
        gltf_bytes = read_member(archive, source_entry)
        metadata = gltf_metadata(archive, source_entry, gltf_bytes)
        runtime_scene = f"res://assets/landscape/vegetation/models/{model_name}.gltf"
        file_entries = list(metadata["dependencies"])
        tree_buffer_entry: str | None = None
        tree_buffer_index: int | None = None
        tree_buffer_derivation: dict | None = None
        if role == "tree":
            try:
                tree_gltf = json.loads(gltf_bytes)
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise BuildError(f"invalid JSON in glTF {source_entry}: {exc}") from exc
            tree_buffers = tree_gltf.get("buffers", [])
            if len(tree_buffers) != 1 or not isinstance(tree_buffers[0].get("uri"), str):
                raise BuildError(f"{source_entry}: expected exactly one external tree buffer")
            tree_buffer_index = 0
            tree_buffer_entry = (
                PurePosixPath(source_entry).parent
                / archive_path(tree_buffers[0]["uri"])
            ).as_posix()
            if tree_buffer_entry not in file_entries:
                raise BuildError(f"{source_entry}: tree buffer is absent from dependency list")

        for entry in file_entries:
            if entry not in source_member_bytes:
                source_member_bytes[entry] = read_member(archive, entry)
            relative = PurePosixPath(entry).relative_to("glTF")
            runtime_path = f"models/{relative.as_posix()}"
            runtime_bytes = source_member_bytes[entry]
            if role == "tree" and entry == tree_buffer_entry:
                assert tree_buffer_index is not None
                runtime_bytes, tree_buffer_derivation = derive_tree_color_buffer(
                    source_entry,
                    gltf_bytes,
                    source_member_bytes[entry],
                    tree_buffer_index,
                )
                tree_buffer_derivation = {
                    **tree_buffer_derivation,
                    "path": runtime_path,
                    "source_entry": entry,
                }
            pending_files[runtime_path] = runtime_bytes
            file_origins[runtime_path] = entry

        asset_record = {
            "id": asset_id,
            "source_id": "quaternius_standard",
            "source_name": model_name,
            "description": description,
            "role": role,
            "scene": runtime_scene,
            "source_entry": source_entry,
            "source_sha256": sha256_bytes(gltf_bytes),
            "source_format": "glTF 2.0",
            **metadata,
            "lod": {"source_supplied": False, "godot_import_generate": True},
        }
        if role == "tree":
            if tree_buffer_derivation is None:
                raise BuildError(f"{source_entry}: tree color buffer derivation did not run")
            asset_record["buffer_derivation"] = tree_buffer_derivation
        assets.append(asset_record)

    def add_obj_family(
        source_archive: ZipFile,
        source_id: str,
        source_prefix: str,
        runtime_subdir: str,
        family_assets: tuple[tuple[str, str, str], ...],
        role: str,
    ) -> None:
        for asset_id, model_name, description in family_assets:
            source_entry = f"{source_prefix}{model_name}.obj"
            obj_bytes = read_member(source_archive, source_entry)
            metadata = obj_metadata(source_entry, obj_bytes)
            parent = PurePosixPath(source_entry).parent
            dependency_entries = [source_entry]
            for material_library in metadata["material_libraries"]:
                dependency_entries.append((parent / material_library).as_posix())

            runtime_dir = f"models/additional/{runtime_subdir}"
            runtime_mesh = f"res://assets/landscape/vegetation/{runtime_dir}/{model_name}.obj"
            source_hashes: dict[str, str] = {"mesh": sha256_bytes(obj_bytes)}
            for entry in dependency_entries:
                data = obj_bytes if entry == source_entry else read_member(source_archive, entry)
                runtime_name = PurePosixPath(entry).name
                runtime_path = f"{runtime_dir}/{runtime_name}"
                pending_files[runtime_path] = data
                file_origins[runtime_path] = entry
                if entry != source_entry:
                    source_hashes[runtime_name] = sha256_bytes(data)

            assets.append(
                {
                    "id": asset_id,
                    "source_id": source_id,
                    "source_name": model_name,
                    "description": description,
                    "role": role,
                    "mesh": runtime_mesh,
                    "source_entry": source_entry,
                    "source_sha256": sha256_bytes(obj_bytes),
                    "source_dependency_sha256": source_hashes,
                    "source_format": "Wavefront OBJ",
                    "source_material_format": "Wavefront MTL",
                    **metadata,
                    "lod": {"source_supplied": False, "godot_import_generate": False},
                }
            )

    add_obj_family(
        crops_archive,
        "quaternius_crops",
        CROPS_SOURCE_ENTRY_PREFIX,
        "quaternius_crops",
        CROP_ASSETS,
        "crop",
    )
    add_obj_family(
        reed_archive,
        "aredon_reed",
        "",
        "aredon_reed",
        REED_ASSETS,
        "reed",
    )

    oak_gltf_bytes = read_member(oak_archive, OAK_GLTF_ENTRY)
    oak_metadata = gltf_metadata(oak_archive, OAK_GLTF_ENTRY, oak_gltf_bytes)
    oak_source_dir = OAK_CONVERSION_DIR.relative_to(ROOT).as_posix()
    oak_runtime_dir = "models/oak_tree"
    oak_source_hashes: dict[str, str] = {}
    for entry in oak_metadata["dependencies"]:
        source_bytes = read_member(oak_archive, entry)
        relative = PurePosixPath(entry).relative_to("glTF")
        runtime_path = f"{oak_runtime_dir}/{relative.as_posix()}"
        source_path = f"{oak_source_dir}/{relative.as_posix()}"
        pending_files[runtime_path] = source_bytes
        file_origins[runtime_path] = source_path
        oak_source_hashes[source_path] = sha256_bytes(source_bytes)

    oak_source_entry = f"{oak_source_dir}/oak_lod0.gltf"
    oak_license_bytes = read_oak_license()
    pending_files[OAK_LICENSE_OUTPUT] = oak_license_bytes
    file_origins[OAK_LICENSE_OUTPUT] = OAK_LICENSE_SOURCE.relative_to(ROOT).as_posix()

    oak_textures = [
        {
            **texture,
            "source_entry": f"{oak_source_dir}/{PurePosixPath(texture['uri']).as_posix()}",
        }
        for texture in oak_metadata["textures"]
    ]
    oak_dependencies = [
        f"{oak_source_dir}/{PurePosixPath(entry).relative_to('glTF').as_posix()}"
        for entry in oak_metadata["dependencies"]
    ]
    oak_source_metadata = {
        **oak_metadata,
        "textures": sorted(oak_textures, key=lambda item: item["uri"].lower()),
        "dependencies": sorted(set(oak_dependencies), key=str.lower),
    }
    oak_proof_bytes, oak_proof = read_oak_conversion_proof()
    oak_conversion = oak_proof["conversion"]
    oak_material = oak_conversion["source_material_names"][0]
    assets.append(
        {
            "id": OAK_ASSET_ID,
            "source_id": OAK_SOURCE_ID,
            "source_name": "Quercus_A_LOD0",
            "description": OAK_DESCRIPTION,
            "role": "tree",
            "scene": f"res://assets/landscape/vegetation/{oak_runtime_dir}/oak_lod0.gltf",
            "source_entry": oak_source_entry,
            "source_sha256": sha256_bytes(oak_gltf_bytes),
            "source_dependency_sha256": oak_source_hashes,
            "source_format": "glTF 2.0 converted from the licensed Blender LOD0",
            "source_lod": "LOD0 only; supplier LOD1 and LOD2 are excluded",
            "source_material_names": [oak_material],
            "source_conversion_proof_sha256": sha256_bytes(oak_proof_bytes),
            **oak_source_metadata,
            "lod": {
                "source_supplied": True,
                "source_lod": "LOD0",
                "imported_supplied_levels": ["LOD0"],
                "alternate_source_lods_included": [],
                "godot_import_generate": True,
            },
        }
    )

    file_records = [
        {
            "path": runtime_path,
            "source_entry": file_origins[runtime_path],
            "bytes": len(data),
            "sha256": sha256_bytes(data),
        }
        for runtime_path, data in sorted(pending_files.items(), key=lambda item: item[0].lower())
    ]

    source_records = [
        {
            "id": "quaternius_standard",
            "title": "Quaternius Stylized Nature MegaKit Standard",
            "author": "Quaternius",
            "url": SOURCE_URL,
            "upload_id": SOURCE_UPLOAD_ID,
            "archive": "assets/landscape/vegetation/source/quaternius_stylized_nature_megakit_standard.zip",
            "archive_bytes": ARCHIVE_BYTES,
            "archive_sha256": ARCHIVE_SHA256,
            "license": "CC0-1.0, embedded License_Standard.txt",
            "license_sha256": LICENSE_SHA256,
            "license_evidence": "assets/landscape/vegetation/source/License_Standard.txt",
        },
        {
            "id": "quaternius_crops",
            "title": "LowPoly Crops Pack",
            "author": "Quaternius",
            "url": CROPS_SOURCE_URL,
            "archive": "assets/landscape/vegetation/source/quaternius_lowpoly_crops_cc0.zip",
            "archive_bytes": CROPS_ARCHIVE_BYTES,
            "archive_sha256": CROPS_ARCHIVE_SHA256,
            "license": "CC0-1.0, as shown on the OpenGameArt source page",
            "license_evidence": CROPS_NOTICE.relative_to(ROOT).as_posix(),
        },
        {
            "id": "aredon_reed",
            "title": "LowPoly Reed",
            "author": "Aredon",
            "url": REED_SOURCE_URL,
            "archive": "assets/landscape/vegetation/source/aredon_lowpoly_reed_cc0.zip",
            "archive_bytes": REED_ARCHIVE_BYTES,
            "archive_sha256": REED_ARCHIVE_SHA256,
            "license": "CC0-1.0, as shown on the OpenGameArt source page",
            "license_evidence": REED_NOTICE.relative_to(ROOT).as_posix(),
        },
        {
            "id": OAK_SOURCE_ID,
            "title": "Oak tree, supplier LOD0",
            "author": OAK_AUTHOR,
            "url": OAK_SOURCE_URL,
            "download_url": OAK_DOWNLOAD_URL,
            "retrieved": OAK_RETRIEVED,
            "archive": OAK_ARCHIVE.relative_to(ROOT).as_posix(),
            "archive_bytes": OAK_ARCHIVE_BYTES,
            "archive_sha256": OAK_ARCHIVE_SHA256,
            "source_blend": OAK_BLEND.relative_to(ROOT).as_posix(),
            "source_blend_bytes": OAK_BLEND_BYTES,
            "source_blend_sha256": OAK_BLEND_SHA256,
            "license": "CC BY-SA 3.0",
            "license_url": OAK_LICENSE_URL,
            "license_evidence": OAK_LICENSE_SOURCE.relative_to(ROOT).as_posix(),
            "license_sha256": sha256_bytes(oak_license_bytes),
            "conversion_proof": OAK_CONVERSION_PROOF.relative_to(ROOT).as_posix(),
            "conversion_proof_bytes": len(oak_proof_bytes),
            "conversion_proof_sha256": sha256_bytes(oak_proof_bytes),
            "conversion": {
                "tool": "Blender 5.2.2 LTS; Khronos glTF Blender I/O v5.2.40",
                "source_method": oak_conversion["method"],
                "source_parts_joined": oak_conversion["source_object_count"],
                "source_triangles": oak_conversion["source_triangulated_triangle_count"],
                "baked_triangles": oak_conversion["baked_triangulated_triangle_count"],
                "max_source_to_baked_loop_error": oak_conversion["max_source_to_baked_error"],
                "material_mapping": oak_proof["material_mapping"],
                "outputs": [
                    {
                        "path": f"{oak_source_dir}/{item['path']}",
                        "bytes": item["bytes"],
                        "sha256": item["sha256"],
                    }
                    for item in oak_proof["outputs"]
                ],
            },
        },
    ]

    catalog = {
        "format": "openrc-imported-vegetation v1",
        "source": {
            "title": "Quaternius Stylized Nature MegaKit Standard",
            "author": "Quaternius",
            "url": SOURCE_URL,
            "upload_id": SOURCE_UPLOAD_ID,
            "retrieved": RETRIEVED,
            "archive": "assets/landscape/vegetation/source/quaternius_stylized_nature_megakit_standard.zip",
            "archive_bytes": ARCHIVE_BYTES,
            "archive_sha256": ARCHIVE_SHA256,
            "license": "CC0-1.0, embedded License_Standard.txt",
            "license_sha256": LICENSE_SHA256,
        },
        "sources": source_records,
        "import": {
            "format": "glTF 2.0 and Wavefront OBJ/MTL",
            "geometry_policy": (
                "original source archives are preserved; Quaternius runtime tree buffers clamp only "
                "finite float COLOR_0 values in (1, 1.0002] to 1; oak LOD0 joins the 36 source "
                "parts while preserving positions and UVs exactly and normals within the conversion proof"
            ),
            "lod_policy": "Godot 4.7.2 ResourceImporterScene automatic mesh LODs enabled for glTF assets; the oak source contributes LOD0 only, with supplier LOD1/LOD2 excluded; Wavefront OBJ assets use supplied geometry",
            "shared_material_policy": (
                "original Quaternius glTF materials and textures are preserved; the oak legacy "
                "M_Quercus material maps its packed atlas to Principled BSDF base color with "
                "roughness 1.0 and BLEND alpha, as recorded in the conversion proof; Godot "
                "4.7.2 imports metallic_specular at its native 0.5 default; OBJ/MTL diffuse materials "
                "are preserved; shared source files are extracted once"
            ),
        },
        "counts": {
            "trees": sum(item["role"] == "tree" for item in assets),
            "shrubs": sum(item["role"] == "shrub" for item in assets),
            "grass_and_herbs": sum(item["role"] in ("grass", "herb") for item in assets),
            "flowers": sum(item["role"] == "flower" for item in assets),
            "crops": sum(item["role"] == "crop" for item in assets),
            "reeds": sum(item["role"] == "reed" for item in assets),
            "total_assets": len(assets),
            "source_triangles_one_of_each": sum(
                item["source_triangles"] for item in assets
            ),
        },
        "files": file_records,
        "assets": assets,
    }
    add_maple(catalog, pending_files)
    add_landscapelab_tree_pack(catalog, pending_files)
    add_realistic_understory_pack(catalog, pending_files)
    add_converted_plant_pack(catalog, pending_files, "lolipop_grass_2026",
        {"grass_lolipop_small": 26, "grass_lolipop_tall": 20}, "LICENSE_GRASS.txt",
        "grass", "LOLIPOP", "Grass pack (lowpoly, game-ready)")
    add_converted_plant_pack(catalog, pending_files, "dasy_forest_2026",
        {"forest_leafy_shrub": 144}, "LICENSE_FOREST.txt", "shrub", "dasy444",
        "A forest (3) with a road at night for game — selected shrub")
    return catalog, pending_files


def add_landscapelab_tree_pack(catalog: dict, library_files: dict[str, bytes]) -> None:
    """Install the pinned, self-contained LandscapeLab tree GLBs byte-for-byte."""
    if not LANDSCAPELAB_MANIFEST.is_file():
        raise BuildError(f"missing LandscapeLab tree conversion manifest: {LANDSCAPELAB_MANIFEST}")
    manifest_bytes = LANDSCAPELAB_MANIFEST.read_bytes()
    if sha256_bytes(manifest_bytes) != LANDSCAPELAB_MANIFEST_SHA256:
        raise BuildError("LandscapeLab tree conversion manifest changed from its reviewed pin")
    try:
        manifest = json.loads(manifest_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BuildError(f"invalid LandscapeLab tree conversion manifest: {exc}") from exc

    source = manifest.get("source", {})
    if (
        manifest.get("format") != "openrc-landscapelab-vegetation-conversion v1"
        or manifest.get("geometry_created") is not False
        or source.get("revision") != LANDSCAPELAB_REVISION
        or source.get("license") != "CC BY-SA 4.0"
    ):
        raise BuildError("LandscapeLab tree conversion manifest does not match its reviewed source contract")

    manifest_assets = manifest.get("assets", [])
    if [item.get("id") for item in manifest_assets] != list(LANDSCAPELAB_ASSETS):
        raise BuildError("LandscapeLab tree manifest must contain the reviewed Quercus, Pine, Fagus and Quercus 2 assets")

    readme_rel = source.get("license_evidence")
    notice_rel = source.get("runtime_notice")
    expected_source_prefix = LANDSCAPELAB_SOURCE_DIR.relative_to(ROOT).as_posix() + "/"
    if (
        not isinstance(readme_rel, str)
        or not readme_rel.startswith(expected_source_prefix)
        or notice_rel != expected_source_prefix + LANDSCAPELAB_NOTICE_SOURCE
    ):
        raise BuildError("LandscapeLab license evidence must remain inside its pinned source directory")
    readme_path = output_path(ROOT, readme_rel)
    notice_path = output_path(ROOT, notice_rel)
    if (
        not readme_path.is_file()
        or readme_path.stat().st_size != source.get("license_evidence_bytes")
        or sha256_file(readme_path) != source.get("license_evidence_sha256")
        or not notice_path.is_file()
        or notice_path.stat().st_size != source.get("runtime_notice_bytes")
        or sha256_file(notice_path) != source.get("runtime_notice_sha256")
    ):
        raise BuildError("LandscapeLab license evidence or runtime notice changed from its manifest")

    source_prefix = LANDSCAPELAB_DERIVED_DIR.relative_to(ROOT).as_posix()
    descriptions = {
        "landscapelab_quercus": "Mature broadleaf Quercus tree",
        "landscapelab_pine": "Mature pine tree",
        "landscapelab_fagus": "Mature broadleaf beech tree (Fagus)",
        "landscapelab_quercus2": "Young open-grown oak tree (Quercus)",
    }
    for item in manifest_assets:
        asset_id = item["id"]
        expected = LANDSCAPELAB_ASSETS[asset_id]
        filename = expected["filename"]
        source_rel = item.get("source_entry")
        derived_rel = item.get("derived_path")
        if (
            item.get("source_name") != expected["source_name"]
            or item.get("source_bytes") != expected["bytes"]
            or item.get("derived_bytes") != expected["bytes"]
            or item.get("source_sha256") != expected["sha256"]
            or item.get("derived_sha256") != expected["sha256"]
            or item.get("source_triangles") != expected["triangles"]
            or item.get("source_surfaces") != expected["surfaces"]
            or not isinstance(source_rel, str)
            or source_rel != LANDSCAPELAB_SOURCE_DIR.relative_to(ROOT).as_posix() + "/" + filename
            or derived_rel != filename
            or item.get("dependencies") != []
        ):
            raise BuildError(f"LandscapeLab tree manifest entry changed from its reviewed pin: {asset_id}")

        asset_license = item.get("asset_license_evidence")
        if asset_license is not None:
            license_rel = asset_license.get("path") if isinstance(asset_license, dict) else None
            if not isinstance(license_rel, str) or not license_rel.startswith(expected_source_prefix):
                raise BuildError(f"LandscapeLab asset license evidence must remain inside its source directory: {asset_id}")
            license_path = output_path(ROOT, license_rel)
            if (
                not license_path.is_file()
                or license_path.stat().st_size != asset_license.get("bytes")
                or sha256_file(license_path) != asset_license.get("sha256")
            ):
                raise BuildError(f"LandscapeLab asset license evidence changed from its manifest: {asset_id}")

        source_path = output_path(ROOT, source_rel)
        derived_path = output_path(LANDSCAPELAB_DERIVED_DIR, derived_rel)
        if (
            not source_path.is_file()
            or not derived_path.is_file()
            or source_path.stat().st_size != expected["bytes"]
            or derived_path.stat().st_size != expected["bytes"]
        ):
            raise BuildError(f"missing or truncated LandscapeLab GLB for {asset_id}")
        source_bytes = source_path.read_bytes()
        derived_bytes = derived_path.read_bytes()
        if (
            sha256_bytes(source_bytes) != expected["sha256"]
            or sha256_bytes(derived_bytes) != expected["sha256"]
            or source_bytes != derived_bytes
        ):
            raise BuildError(f"LandscapeLab runtime GLB is not the pinned byte-for-byte source: {asset_id}")

        runtime_path = (
            "models/landscapelab_tree_2026/"
            + expected["runtime_subdir"]
            + "/"
            + filename
        )
        library_files[runtime_path] = derived_bytes
        catalog["files"].append({
            "path": runtime_path,
            "source_entry": source_prefix + "/" + filename,
            "bytes": len(derived_bytes),
            "sha256": expected["sha256"],
        })
        catalog_asset = {
            "id": asset_id,
            "source_id": "landscapelab_tree_2026",
            "source_name": expected["source_name"],
            "description": descriptions[asset_id],
            "role": "tree",
            "scene": "res://assets/landscape/vegetation/" + runtime_path,
            "source_entry": source_prefix + "/" + filename,
            "source_sha256": expected["sha256"],
            "source_git_blob_sha1": item["git_blob_sha1"],
            "source_upstream_path": item["upstream_path"],
            "source_format": "glTF 2.0 binary (GLB)",
            "source_conversion_proof_sha256": LANDSCAPELAB_MANIFEST_SHA256,
            "source_triangles": item["source_triangles"],
            "source_surfaces": item["source_surfaces"],
            "source_materials": item["source_materials"],
            "source_material_names": item["source_material_names"],
            "source_material_conventions": item["source_material_conventions"],
            "source_bounds_m": item["source_bounds_m"],
            # Every pinned GLB already has its root at ground level. Keep
            # the same catalog bounds contract as the other supplied plants.
            "grounded_bounds_m": item["source_bounds_m"],
            "normalized_bounds_1m": item["normalized_bounds_1m"],
            "embedded_images": item["embedded_images"],
            "dependencies": [],
            "extensions_used": item["extensions_used"],
            "source_node_transform": item["source_node_transform"],
            "conversion": item["conversion"],
            "lod": {"source_supplied": False, "godot_import_generate": True},
        }
        if asset_license is not None:
            catalog_asset["asset_license_evidence"] = asset_license
        catalog["assets"].append(catalog_asset)

    notice_bytes = notice_path.read_bytes()
    library_files[LANDSCAPELAB_NOTICE] = notice_bytes
    catalog["files"].append({
        "path": LANDSCAPELAB_NOTICE,
        "source_entry": notice_rel,
        "bytes": len(notice_bytes),
        "sha256": sha256_bytes(notice_bytes),
    })
    catalog["sources"].append({
        "id": "landscapelab_tree_2026",
        "title": "LandscapeLab Assets — Quercus, Quercus 2, Fagus and Pine",
        "author": "LandscapeLab Assets contributors",
        "url": source["repository"],
        "revision": LANDSCAPELAB_REVISION,
        "license": "CC BY-SA 4.0",
        "license_url": source["license_url"],
        "license_evidence": readme_rel,
        "license_sha256": source["license_evidence_sha256"],
        "runtime_notice": notice_rel,
        "runtime_notice_sha256": source["runtime_notice_sha256"],
        "conversion_proof": LANDSCAPELAB_MANIFEST.relative_to(ROOT).as_posix(),
        "conversion_proof_sha256": LANDSCAPELAB_MANIFEST_SHA256,
        "source": source,
    })
    catalog["counts"]["trees"] += len(LANDSCAPELAB_ASSETS)
    catalog["counts"]["total_assets"] += len(LANDSCAPELAB_ASSETS)
    catalog["counts"]["source_triangles_one_of_each"] += sum(
        item["triangles"] for item in LANDSCAPELAB_ASSETS.values()
    )
    catalog["files"].sort(key=lambda item: item["path"].lower())
    catalog["import"]["geometry_policy"] += "; LandscapeLab trees preserve supplied GLBs byte-for-byte, with source-grounded bounds and 1 m normalization metadata"
    catalog["import"]["shared_material_policy"] += "; LandscapeLab materials and embedded textures are preserved byte-for-byte, including their source MASK foliage conventions"


def add_realistic_understory_pack(catalog: dict, library_files: dict[str, bytes]) -> None:
    """Install the verified Poly Haven fern and flower derivatives and their shared CC0 notice."""
    if not UNDERSTORY_MANIFEST.is_file():
        raise BuildError(f"missing realistic understory conversion manifest: {UNDERSTORY_MANIFEST}")
    manifest_bytes = UNDERSTORY_MANIFEST.read_bytes()
    if sha256_bytes(manifest_bytes) != UNDERSTORY_MANIFEST_SHA256:
        raise BuildError("realistic understory conversion manifest changed from its reviewed pin")
    try:
        manifest = json.loads(manifest_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BuildError(f"invalid realistic understory conversion manifest: {exc}") from exc
    if manifest.get("format") != "openrc-realistic-understory-conversion v1":
        raise BuildError("realistic understory manifest format changed from its reviewed contract")

    def verify_records(records: list[dict], base: Path, label: str) -> dict[str, bytes]:
        verified: dict[str, bytes] = {}
        for item in records:
            relative = item.get("path")
            if not isinstance(relative, str) or relative in verified:
                raise BuildError(f"invalid or duplicate {label} path in understory manifest: {relative!r}")
            path = output_path(base, relative)
            if not path.is_file() or path.stat().st_size != item.get("bytes"):
                raise BuildError(f"missing or truncated understory {label}: {path}")
            data = path.read_bytes()
            if sha256_bytes(data) != item.get("sha256"):
                raise BuildError(f"understory {label} hash differs from its manifest: {path}")
            verified[relative] = data
        return verified

    inputs = manifest.get("inputs")
    outputs = manifest.get("outputs")
    variants = manifest.get("variants")
    sources = manifest.get("sources")
    if not all(isinstance(value, list) for value in (inputs, outputs, variants, sources)):
        raise BuildError("realistic understory manifest is missing input/output/source/variant lists")
    input_bytes = verify_records(inputs, ROOT, "source input")
    output_bytes = verify_records(outputs, UNDERSTORY_DERIVED_DIR, "derived output")

    expected_ids = list(UNDERSTORY_ASSETS)
    if [item.get("id") for item in variants] != expected_ids:
        raise BuildError("understory manifest must contain the reviewed fern and Empodium variants")
    source_by_id = {item.get("id"): item for item in sources}
    if set(source_by_id) != {item["source_id"] for item in UNDERSTORY_ASSETS.values()}:
        raise BuildError("understory manifest source records do not match the selected Poly Haven assets")

    derived_prefix = UNDERSTORY_DERIVED_DIR.relative_to(ROOT).as_posix() + "/"
    runtime_prefix = "models/realistic_understory_2026/"
    for variant in variants:
        asset_id = variant["id"]
        expected = UNDERSTORY_ASSETS[asset_id]
        runtime_model = variant.get("runtime_model_relative_path")
        expected_model = runtime_prefix + (
            "fern_02_a.gltf" if asset_id == "polyhaven_fern_02_a" else "flower_empodium_a.gltf"
        )
        if (
            variant.get("source_id") != expected["source_id"]
            or variant.get("source_name") != expected["source_name"]
            or variant.get("role") != expected["role"]
            or variant.get("source_triangles") != expected["triangles"]
            or variant.get("source_surfaces") != 1
            or variant.get("source_materials") != 1
            or variant.get("source_sha256") != expected["sha256"]
            or runtime_model != expected_model
            or variant.get("scene") != "res://assets/landscape/vegetation/" + expected_model
            or variant.get("source_format") != "glTF 2.0"
        ):
            raise BuildError(f"understory variant changed from its reviewed candidate contract: {asset_id}")

        proof_path = variant.get("source_conversion_proof")
        proof_rel = (
            PurePosixPath(proof_path).relative_to(UNDERSTORY_DERIVED_DIR.relative_to(ROOT).as_posix()).as_posix()
            if isinstance(proof_path, str)
            else ""
        )
        proof_bytes = output_bytes.get(proof_rel)
        if (
            not proof_bytes
            or sha256_bytes(proof_bytes) != variant.get("source_conversion_proof_sha256")
        ):
            raise BuildError(f"understory conversion proof changed from its manifest: {asset_id}")

        dependencies = variant.get("dependencies")
        dependency_hashes = variant.get("source_dependency_sha256")
        source_entry = variant.get("source_entry")
        if not isinstance(dependencies, list) or not isinstance(dependency_hashes, dict):
            raise BuildError(f"understory dependencies are missing for {asset_id}")
        if source_entry not in dependencies or source_entry != derived_prefix + expected_model.removeprefix(runtime_prefix):
            raise BuildError(f"understory model source path changed from its reviewed contract: {asset_id}")

        expected_dependency_hashes: dict[str, str] = {}
        for dependency in dependencies:
            if not isinstance(dependency, str) or not dependency.startswith(derived_prefix):
                raise BuildError(f"understory dependency escapes its derived directory: {dependency!r}")
            relative = dependency[len(derived_prefix):]
            data = output_bytes.get(relative)
            if data is None:
                raise BuildError(f"understory dependency is absent from the output receipt: {dependency}")
            digest = sha256_bytes(data)
            if dependency != source_entry:
                expected_dependency_hashes[dependency] = digest
            runtime_path = runtime_prefix + relative
            if runtime_path not in library_files:
                library_files[runtime_path] = data
                catalog["files"].append({
                    "path": runtime_path,
                    "source_entry": dependency,
                    "bytes": len(data),
                    "sha256": digest,
                })
        if dependency_hashes != expected_dependency_hashes:
            raise BuildError(f"understory dependency hashes do not match the output receipt: {asset_id}")

        source = source_by_id[expected["source_id"]]
        license_evidence = source.get("license_evidence")
        license_input = input_bytes.get(license_evidence) if isinstance(license_evidence, str) else None
        if source.get("license") != "CC0-1.0" or not license_input:
            raise BuildError(f"understory license evidence is missing for {asset_id}")

        catalog["assets"].append({
            "id": asset_id,
            "source_id": expected["source_id"],
            "source_name": expected["source_name"],
            "description": "Downloaded " + source["title"] + " candidate",
            "role": expected["role"],
            "scene": variant["scene"],
            "source_entry": source_entry,
            "source_sha256": expected["sha256"],
            "source_dependency_sha256": dependency_hashes,
            "source_format": variant["source_format"],
            "source_conversion_proof": proof_path,
            "source_conversion_proof_sha256": variant["source_conversion_proof_sha256"],
            "source_triangles": variant["source_triangles"],
            "source_surfaces": variant["source_surfaces"],
            "source_materials": variant["source_materials"],
            "source_bounds_m": variant["source_bounds_m"],
            "grounded_bounds_m": variant["grounded_bounds_m"],
            "source_geometry": variant["source_geometry"],
            "material_alpha": variant["material_alpha"],
            "textures": variant["textures"],
            "dependencies": dependencies,
            "lod": variant["lod"],
            "source_metadata": variant["source_metadata"],
            "visual_qualification": variant["visual_qualification"],
        })

    notice_rel = "assets/landscape/vegetation/source/realistic_understory_2026/SOURCE_LICENSE.md"
    notice_bytes = input_bytes.get(notice_rel)
    if notice_bytes is None:
        raise BuildError("understory runtime license notice is missing from the source receipt")
    library_files[UNDERSTORY_NOTICE] = notice_bytes
    catalog["files"].append({
        "path": UNDERSTORY_NOTICE,
        "source_entry": notice_rel,
        "bytes": len(notice_bytes),
        "sha256": sha256_bytes(notice_bytes),
    })

    for source in sources:
        evidence = source["license_evidence"]
        evidence_bytes = input_bytes.get(evidence)
        proof_variant = next(item for item in variants if item["source_id"] == source["id"])
        catalog["sources"].append({
            "id": source["id"],
            "title": source["title"],
            "author": ", ".join(source.get("authors", {})),
            "url": source["url"],
            "license": source["license"],
            "license_url": source["license_url"],
            "license_statement_url": source["license_statement_url"],
            "license_evidence": evidence,
            "license_sha256": sha256_bytes(evidence_bytes) if evidence_bytes is not None else None,
            "runtime_notice": notice_rel,
            "runtime_notice_sha256": sha256_bytes(notice_bytes),
            "conversion_proof": proof_variant["source_conversion_proof"],
            "conversion_proof_sha256": proof_variant["source_conversion_proof_sha256"],
            "source": source,
        })

    catalog["counts"]["total_assets"] += len(UNDERSTORY_ASSETS)
    catalog["counts"]["grass_and_herbs"] += sum(
        item["role"] in ("grass", "herb") for item in UNDERSTORY_ASSETS.values()
    )
    catalog["counts"]["flowers"] += sum(item["role"] == "flower" for item in UNDERSTORY_ASSETS.values())
    catalog["counts"]["source_triangles_one_of_each"] += sum(
        item["triangles"] for item in UNDERSTORY_ASSETS.values()
    )
    catalog["files"].sort(key=lambda item: item["path"].lower())
    catalog["import"]["geometry_policy"] += "; Poly Haven fern and flower derivatives preserve selected source mesh primitives and binary geometry while removing only gallery transforms"
    catalog["import"]["shared_material_policy"] += "; understory textures preserve supplier maps; fern MASK 0.5 is retained and Flower Empodium BLEND is staged as MASK 0.5 with alpha packing recorded"


def add_converted_plant_pack(catalog: dict, library_files: dict[str, bytes], source_id: str,
                             expected: dict[str, int], notice_name: str, role: str,
                             author: str, title: str) -> None:
    """Install reviewed supplied plant meshes after verifying their complete receipts."""
    source = ROOT / "assets/landscape/vegetation/source" / source_id
    derived = ROOT / "assets/landscape/vegetation/derived" / source_id
    proof = derived / "conversion_manifest.json"
    proof_bytes = proof.read_bytes()
    manifest = json.loads(proof_bytes)
    for key, base in (("inputs", source), ("outputs", derived)):
        for item in manifest[key]:
            path = output_path(base, item["path"])
            if not path.is_file() or path.stat().st_size != item["bytes"] or sha256_file(path) != item["sha256"]:
                raise BuildError(f"{source_id} {key} changed: {path}")
    files = {item["path"]: output_path(derived, item["path"]).read_bytes() for item in manifest["outputs"]}
    buffer = BytesIO()
    with ZipFile(buffer, "w") as archive:
        for name, data in files.items():
            archive.writestr("glTF/" + archive_path(name), data)
    buffer.seek(0)
    prefix = derived.relative_to(ROOT).as_posix()
    if {v["id"]: v["triangles"] for v in manifest["variants"]} != expected:
        raise BuildError(f"{source_id} must retain the reviewed variant counts: {expected}")
    installed: set[str] = set()
    with ZipFile(buffer) as archive:
        for variant in manifest["variants"]:
            name, asset_id = variant["gltf"], variant["id"]
            metadata = gltf_metadata(archive, "glTF/" + name, files[name])
            if metadata["source_triangles"] != expected[asset_id] or metadata["source_surfaces"] != 1:
                raise BuildError(f"grass source topology changed: {asset_id}")
            dependencies = [PurePosixPath(p).relative_to("glTF").as_posix() for p in metadata["dependencies"]]
            for dependency in dependencies:
                runtime_path = "models/" + source_id + "/" + dependency
                if runtime_path in installed:
                    continue
                installed.add(runtime_path)
                data = files[dependency]
                library_files[runtime_path] = data
                catalog["files"].append({"path": runtime_path, "source_entry": prefix + "/" + dependency,
                                         "bytes": len(data), "sha256": sha256_bytes(data)})
            metadata["dependencies"] = [prefix + "/" + p for p in dependencies]
            for texture in metadata["textures"]:
                texture["source_entry"] = prefix + "/" + texture["uri"]
            catalog["assets"].append({"id": asset_id, "source_id": source_id,
                "source_name": variant["source_name"], "description": "Downloaded " + role, "role": role,
                "scene": "res://assets/landscape/vegetation/models/" + source_id + "/" + name,
                "source_entry": prefix + "/" + name, "source_sha256": sha256_bytes(files[name]),
                "source_dependency_sha256": {prefix + "/" + p: sha256_bytes(files[p]) for p in dependencies},
                "source_format": "glTF 2.0", "source_conversion_proof_sha256": sha256_bytes(proof_bytes),
                **metadata, "lod": {"source_supplied": False, "godot_import_generate": True}})
    notice = source / notice_name
    notice_bytes = notice.read_bytes()
    library_files[notice.name] = notice_bytes
    catalog["files"].append({"path": notice.name, "source_entry": notice.relative_to(ROOT).as_posix(),
                             "bytes": len(notice_bytes), "sha256": sha256_bytes(notice_bytes)})
    catalog["sources"].append({"id": source_id, "title": title,
        "author": author, "url": manifest["source"]["url"], "license": "CC BY 4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "license_evidence": notice.relative_to(ROOT).as_posix(), "license_sha256": sha256_bytes(notice_bytes),
        "conversion_proof": proof.relative_to(ROOT).as_posix(), "conversion_proof_sha256": sha256_bytes(proof_bytes),
        "source": manifest["source"]})
    catalog["counts"]["total_assets"] += len(expected)
    catalog["counts"]["grass_and_herbs" if role == "grass" else "shrubs"] += len(expected)
    catalog["counts"]["source_triangles_one_of_each"] += sum(expected.values())
    catalog["files"].sort(key=lambda item: item["path"].lower())


def add_maple(catalog: dict, library_files: dict[str, bytes]) -> None:
    """Include the reviewed supplier LOD1; verify every retained input and output."""
    manifest_bytes = MAPLE_MANIFEST.read_bytes()
    manifest = json.loads(manifest_bytes)
    for key, base in (("inputs", MAPLE_SOURCE_DIR), ("outputs", MAPLE_DERIVED_DIR)):
        for item in manifest[key]:
            path = output_path(base, item["path"])
            if not path.is_file() or path.stat().st_size != item["bytes"] or sha256_file(path) != item["sha256"]:
                raise BuildError(f"maple {key} changed from conversion manifest: {path}")
    output_files = {item["path"]: (MAPLE_DERIVED_DIR / item["path"]).read_bytes()
                    for item in manifest["outputs"]}
    buffer = BytesIO()
    with ZipFile(buffer, "w") as archive:
        for name, data in output_files.items():
            archive.writestr("glTF/" + archive_path(name), data)
    buffer.seek(0)
    with ZipFile(buffer) as archive:
        metadata = gltf_metadata(archive, "glTF/" + MAPLE_GLTF, output_files[MAPLE_GLTF])
    if metadata["source_triangles"] != 5541 or metadata["source_surfaces"] != 2:
        raise BuildError("maple conversion must preserve supplier large_3 LOD1: 5,541 triangles, two surfaces")
    source_prefix = MAPLE_DERIVED_DIR.relative_to(ROOT).as_posix()
    dependencies = [PurePosixPath(entry).relative_to("glTF").as_posix() for entry in metadata["dependencies"]]
    for name in dependencies:
        runtime_path = "models/maple_tree/" + name
        data = output_files[name]
        library_files[runtime_path] = data
        catalog["files"].append({"path": runtime_path, "source_entry": source_prefix + "/" + name,
                                 "bytes": len(data), "sha256": sha256_bytes(data)})
    notice = MAPLE_SOURCE_DIR / "LICENSE_MAPLE.txt"
    notice_bytes = notice.read_bytes()
    library_files[notice.name] = notice_bytes
    catalog["files"].append({"path": notice.name, "source_entry": notice.relative_to(ROOT).as_posix(),
                             "bytes": len(notice_bytes), "sha256": sha256_bytes(notice_bytes)})
    metadata["dependencies"] = [source_prefix + "/" + name for name in dependencies]
    for texture in metadata["textures"]:
        texture["source_entry"] = source_prefix + "/" + texture["uri"]
    catalog["assets"].append({
        "id": "maple_tree", "source_id": "lolipop_maple_2026", "source_name": "Acer_large_3_LOD1",
        "description": "Mature broadleaf maple, supplier LOD1", "role": "tree",
        "scene": "res://assets/landscape/vegetation/models/maple_tree/" + MAPLE_GLTF,
        "source_entry": source_prefix + "/" + MAPLE_GLTF,
        "source_sha256": sha256_bytes(output_files[MAPLE_GLTF]),
        "source_dependency_sha256": {source_prefix + "/" + name: sha256_bytes(output_files[name]) for name in dependencies},
        "source_format": "glTF 2.0 converted from supplier FBX",
        "source_conversion_proof_sha256": sha256_bytes(manifest_bytes),
        **metadata,
        "lod": {"source_supplied": True, "source_lod": "LOD1", "imported_supplied_levels": ["LOD1"],
                "alternate_source_lods_included": [], "godot_import_generate": True},
    })
    catalog["sources"].append({
        "id": "lolipop_maple_2026", "title": "Maple Trees Pack", "author": "LOLIPOP",
        "url": "https://sketchfab.com/3d-models/maple-trees-pack-lowpoly-game-ready-lods-b5d2833c258f4054a01ee2b4ef85adf0",
        "license": "CC BY 4.0", "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "license_evidence": notice.relative_to(ROOT).as_posix(), "license_sha256": sha256_bytes(notice_bytes),
        "conversion_proof": MAPLE_MANIFEST.relative_to(ROOT).as_posix(),
        "conversion_proof_sha256": sha256_bytes(manifest_bytes), "source": manifest["source"],
    })
    catalog["counts"]["trees"] += 1
    catalog["counts"]["total_assets"] += 1
    catalog["counts"]["source_triangles_one_of_each"] += 5541
    catalog["files"].sort(key=lambda item: item["path"].lower())
    catalog["import"]["geometry_policy"] += "; maple preserves supplied large_3 LOD1 topology and bakes only its source transform"
    catalog["import"]["shared_material_policy"] += "; maple uses the source bark/leaf PBR maps with masked double-sided foliage; its conversion manifest records channel mapping"


def write_if_changed(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() == data:
        return
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(data)
    temporary.replace(path)


def output_path(output_root: Path, relative: str) -> Path:
    """Resolve a generated relative path and refuse to write outside its root."""
    safe_relative = archive_path(relative)
    root = output_root.resolve()
    target = root.joinpath(*PurePosixPath(safe_relative).parts)
    try:
        target.resolve().relative_to(root)
    except ValueError as exc:
        raise BuildError(f"generated path escapes output root: {relative!r}") from exc
    return target


def expected_outputs(
    catalog: dict,
    library_files: dict[str, bytes],
    output_root: Path,
    *,
    write_source_evidence: bool,
) -> dict[Path, bytes]:
    expected = {
        output_path(output_root, relative): data
        for relative, data in library_files.items()
    }
    expected[output_path(output_root, "catalog.json")] = (
        json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"
    ).encode("utf-8")
    if write_source_evidence:
        expected[SOURCE_LICENSE] = library_files["LICENSE.txt"]
        expected.update(SOURCE_NOTICES)
    return expected


def display_path(path: Path) -> str:
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify archive and generated files without writing")
    parser.add_argument(
        "--output-root",
        type=Path,
        help=(
            "write the generated library here instead of app/assets/landscape/vegetation; "
            "relative paths are resolved from the repository root"
        ),
    )
    args = parser.parse_args(argv)
    output_root = args.output_root or RUNTIME
    if not output_root.is_absolute():
        output_root = ROOT / output_root
    output_root = output_root.resolve()

    pinned_archives = (
        (ARCHIVE, ARCHIVE_BYTES, ARCHIVE_SHA256, "Quaternius Standard"),
        (CROPS_ARCHIVE, CROPS_ARCHIVE_BYTES, CROPS_ARCHIVE_SHA256, "Quaternius crops"),
        (REED_ARCHIVE, REED_ARCHIVE_BYTES, REED_ARCHIVE_SHA256, "Aredon reed"),
        (OAK_ARCHIVE, OAK_ARCHIVE_BYTES, OAK_ARCHIVE_SHA256, "OpenGameArt oak"),
    )
    for archive_path_value, expected_bytes, expected_hash, label in pinned_archives:
        if not archive_path_value.is_file():
            raise BuildError(f"missing pinned {label} source archive: {archive_path_value}")
        archive_size = archive_path_value.stat().st_size
        archive_hash = sha256_file(archive_path_value)
        if archive_size != expected_bytes or archive_hash != expected_hash:
            raise BuildError(
                f"{label} source archive does not match the pinned upload: "
                f"bytes={archive_size}, sha256={archive_hash}"
            )

    try:
        with ZipFile(ARCHIVE) as archive, ZipFile(CROPS_ARCHIVE) as crops_archive, ZipFile(
            REED_ARCHIVE
        ) as reed_archive, open_oak_conversion_archive() as oak_archive:
            catalog, runtime_files = catalog_for(
                archive,
                crops_archive,
                reed_archive,
                oak_archive,
            )
    except BadZipFile as exc:
        raise BuildError(f"source archive is not a valid ZIP: {exc}") from exc

    expected = expected_outputs(
        catalog,
        runtime_files,
        output_root,
        write_source_evidence=args.output_root is None,
    )

    if args.check:
        errors: list[str] = []
        for path, expected_bytes in expected.items():
            if not path.is_file():
                errors.append(f"missing generated file: {display_path(path)}")
                continue
            actual = path.read_bytes()
            if actual != expected_bytes:
                errors.append(f"generated file differs: {display_path(path)}")
        if errors:
            raise BuildError("\n".join(errors))
    else:
        for path, data in expected.items():
            write_if_changed(path, data)
    print(
        f"{len(catalog['assets'])} imported vegetation assets, "
        f"{catalog['counts']['source_triangles_one_of_each']:,} source triangles, "
        f"{len(catalog['files'])} verified runtime files; "
        f"{len(pinned_archives)} pinned source archives verified; "
        f"output={display_path(output_root)}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BuildError as exc:
        print(f"vegetation build failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
