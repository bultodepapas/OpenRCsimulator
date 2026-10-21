#!/usr/bin/env python3
"""Validate and copy the pinned LandscapeLab Quercus and Pine GLBs unchanged."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys


ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / "assets/landscape/vegetation/source/landscapelab_tree_2026"
DERIVED_DIR = ROOT / "assets/landscape/vegetation/derived/landscapelab_tree_2026"
MANIFEST_NAME = "conversion_manifest.json"
REVISION = "dfdde034c3547f9876967653d98827bd5348e52e"
REPOSITORY_URL = "https://github.com/boku-ilen/landscapelab-assets"
COMMIT_URL = f"{REPOSITORY_URL}/tree/{REVISION}"
LICENSE_NAME = "CC BY-SA 4.0"
LICENSE_URL = "https://creativecommons.org/licenses/by-sa/4.0/"
SOURCE_README = "README.md"
SOURCE_README_BYTES = 1_718
SOURCE_README_SHA256 = "87680a80f2fe326c387b1ed79c9a1a043fe0b0ce7e72d7f9ba2efe46c462e276"
SOURCE_LICENSE_NOTICE = "LICENSE_LANDSCAPELAB.txt"
SOURCE_LICENSE_NOTICE_BYTES = 1_038
SOURCE_LICENSE_NOTICE_SHA256 = "f05b5077b3793eb19f9184cbbce49d777d8183aa862af50de9ae1833578f3922"
SOURCE_PREFIX = "assets/landscape/vegetation/source/landscapelab_tree_2026/"
DERIVED_PREFIX = "assets/landscape/vegetation/derived/landscapelab_tree_2026/"
RUNTIME_PREFIX = "models/landscapelab_tree_2026/"

SOURCE_ASSETS = (
    {
        "id": "landscapelab_quercus",
        "source_name": "Quercus",
        "source_path": "quercus.glb",
        "upstream_path": "Natural/Plants/Trees/Quercus/quercus.glb",
        "derived_name": "quercus.glb",
        "source_bytes": 7_389_596,
        "source_sha256": "d4fb683939a0a6e28fb1ff409cbc73c306207f093bfcb40110ff1fe79fabbd1e",
        "git_blob_sha1": "e625adef3ae04e455037c4db4d39d7f486f0a498",
        "triangles": 7_016,
        "surfaces": 2,
        "bounds_min": [-25.538609, 0.0, -26.160007],
        "bounds_max": [26.347387, 59.555878, 24.630487],
    },
    {
        "id": "landscapelab_pine",
        "source_name": "Pine",
        "source_path": "pine_joined.glb",
        "upstream_path": "Natural/Plants/Trees/Pine/pine_joined.glb",
        "derived_name": "pine_joined.glb",
        "source_bytes": 6_788_748,
        "source_sha256": "74d3d4d0f541522163b1e4d24931e76640df6fdd758db0f963d109faf1a9bcf8",
        "git_blob_sha1": "8634899c22a9e4a7bf8d3fc94930ed560d340dd0",
        "triangles": 4_246,
        "surfaces": 2,
        "bounds_min": [-7.928009, 0.0, -8.131644],
        "bounds_max": [7.767775, 41.153725, 7.985003],
    },
)

class ConversionError(RuntimeError):
    """Raised when the pinned source or derived-copy contract fails."""


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_license_notice() -> bytes:
    path = SOURCE_DIR / SOURCE_LICENSE_NOTICE
    if not path.is_file():
        raise ConversionError(f"missing LandscapeLab attribution notice: {path}")
    data = path.read_bytes()
    if len(data) != SOURCE_LICENSE_NOTICE_BYTES or sha256_bytes(data) != SOURCE_LICENSE_NOTICE_SHA256:
        raise ConversionError("LandscapeLab attribution/license notice changed from its reviewed pin")
    return data


def git_blob_sha1(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def _checked_slice(data: bytes, offset: int, length: int, label: str) -> bytes:
    if offset < 0 or length < 0 or offset + length > len(data):
        raise ConversionError(f"{label}: byte range is outside the GLB buffer")
    return data[offset : offset + length]


def _identity_node(gltf: dict) -> None:
    nodes = gltf.get("nodes", [])
    scenes = gltf.get("scenes", [])
    scene_index = gltf.get("scene", 0)
    if len(nodes) != 1 or not scenes or scene_index >= len(scenes):
        raise ConversionError("expected one scene node with an identity transform")
    if scenes[scene_index].get("nodes") != [0] or nodes[0].get("mesh") != 0:
        raise ConversionError("expected the source mesh to be the scene's only root node")
    node = nodes[0]
    identity_values = {
        "matrix": [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0],
        "translation": [0.0, 0.0, 0.0],
        "rotation": [0.0, 0.0, 0.0, 1.0],
        "scale": [1.0, 1.0, 1.0],
    }
    for key, expected in identity_values.items():
        if key in node and node[key] != expected:
            raise ConversionError(f"source node has a non-identity {key} transform")


def _accessor_view(gltf: dict, binary: bytes, accessor_index: int, label: str) -> tuple[dict, dict, int]:
    accessors = gltf.get("accessors", [])
    if not isinstance(accessor_index, int) or accessor_index < 0 or accessor_index >= len(accessors):
        raise ConversionError(f"{label}: accessor index is missing")
    accessor = accessors[accessor_index]
    if "sparse" in accessor or "bufferView" not in accessor:
        raise ConversionError(f"{label}: sparse or implicit accessors are unsupported")
    views = gltf.get("bufferViews", [])
    view_index = accessor["bufferView"]
    if not isinstance(view_index, int) or view_index < 0 or view_index >= len(views):
        raise ConversionError(f"{label}: buffer view is missing")
    view = views[view_index]
    if view.get("buffer", 0) != 0:
        raise ConversionError(f"{label}: accessor refers to a missing GLB buffer")
    view_offset = int(view.get("byteOffset", 0))
    accessor_offset = int(accessor.get("byteOffset", 0))
    return accessor, view, view_offset + accessor_offset


def _position_bounds(gltf: dict, binary: bytes, accessor_index: int, label: str) -> tuple[list[float], list[float], int]:
    accessor, view, start = _accessor_view(gltf, binary, accessor_index, label)
    if accessor.get("componentType") != 5126 or accessor.get("type") != "VEC3":
        raise ConversionError(f"{label}: positions must be float VEC3 values")
    count = accessor.get("count")
    if not isinstance(count, int) or count <= 0:
        raise ConversionError(f"{label}: position accessor is empty")
    stride = int(view.get("byteStride", 12))
    if stride < 12 or stride % 4 != 0:
        raise ConversionError(f"{label}: position byte stride is invalid")
    _checked_slice(binary, start, (count - 1) * stride + 12, label)
    minimum = [math.inf, math.inf, math.inf]
    maximum = [-math.inf, -math.inf, -math.inf]
    for index in range(count):
        values = struct.unpack_from("<3f", binary, start + index * stride)
        for axis, value in enumerate(values):
            if not math.isfinite(value):
                raise ConversionError(f"{label}: position data contains a non-finite value")
            minimum[axis] = min(minimum[axis], value)
            maximum[axis] = max(maximum[axis], value)
    declared_min = accessor.get("min")
    declared_max = accessor.get("max")
    if not isinstance(declared_min, list) or not isinstance(declared_max, list):
        raise ConversionError(f"{label}: position accessor omits declared bounds")
    for axis in range(3):
        if abs(float(declared_min[axis]) - minimum[axis]) > 1e-5:
            raise ConversionError(f"{label}: declared POSITION minimum differs from the data")
        if abs(float(declared_max[axis]) - maximum[axis]) > 1e-5:
            raise ConversionError(f"{label}: declared POSITION maximum differs from the data")
    return minimum, maximum, count


def _validate_indices(gltf: dict, binary: bytes, accessor_index: int, vertex_count: int, label: str) -> int:
    accessor, view, start = _accessor_view(gltf, binary, accessor_index, label)
    if accessor.get("type") != "SCALAR" or accessor.get("componentType") not in (5121, 5123, 5125):
        raise ConversionError(f"{label}: triangle indices must be unsigned scalar values")
    component = {5121: (1, "<B"), 5123: (2, "<H"), 5125: (4, "<I")}[accessor["componentType"]]
    width, unpacker = component
    count = accessor.get("count")
    if not isinstance(count, int) or count <= 0 or count % 3:
        raise ConversionError(f"{label}: triangle index count is invalid")
    stride = int(view.get("byteStride", width))
    if stride < width:
        raise ConversionError(f"{label}: index byte stride is invalid")
    _checked_slice(binary, start, (count - 1) * stride + width, label)
    for index in range(count):
        value = struct.unpack_from(unpacker, binary, start + index * stride)[0]
        if value >= vertex_count:
            raise ConversionError(f"{label}: index {value} exceeds position count {vertex_count}")
    return count // 3


def _embedded_image_records(gltf: dict, binary: bytes) -> list[dict]:
    records: list[dict] = []
    for index, image in enumerate(gltf.get("images", [])):
        if "uri" in image:
            uri = str(image["uri"])
            if not uri.startswith("data:"):
                raise ConversionError(f"image {index} uses an external dependency: {uri}")
            encoded = uri.partition(",")[2]
            import base64

            try:
                image_bytes = base64.b64decode(encoded, validate=True)
            except ValueError as exc:
                raise ConversionError(f"image {index} has an invalid data URI") from exc
        else:
            view_index = image.get("bufferView")
            views = gltf.get("bufferViews", [])
            if not isinstance(view_index, int) or view_index < 0 or view_index >= len(views):
                raise ConversionError(f"image {index} has no embedded buffer view")
            view = views[view_index]
            if view.get("buffer", 0) != 0:
                raise ConversionError(f"image {index} uses a missing GLB buffer")
            image_bytes = _checked_slice(
                binary,
                int(view.get("byteOffset", 0)),
                int(view.get("byteLength", 0)),
                f"image {index}",
            )
        if not image_bytes:
            raise ConversionError(f"image {index} is empty")
        records.append(
            {
                "index": index,
                "name": image.get("name", f"image_{index}"),
                "mime_type": image.get("mimeType", "application/octet-stream"),
                "storage": "glb_embedded",
                "bytes": len(image_bytes),
                "sha256": sha256_bytes(image_bytes),
            }
        )
    return records


def inspect_glb(data: bytes, source_name: str) -> dict:
    if len(data) < 20:
        raise ConversionError(f"{source_name}: GLB header/chunks are truncated")
    magic, version, total_length = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2 or total_length != len(data):
        raise ConversionError(f"{source_name}: expected a complete glTF 2.0 binary container")
    offset = 12
    chunks: list[tuple[int, bytes]] = []
    while offset < total_length:
        if offset + 8 > total_length:
            raise ConversionError(f"{source_name}: truncated GLB chunk header")
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = _checked_slice(data, offset, chunk_length, source_name)
        chunks.append((chunk_type, chunk))
        offset += chunk_length
    json_chunks = [chunk for chunk_type, chunk in chunks if chunk_type == 0x4E4F534A]
    binary_chunks = [chunk for chunk_type, chunk in chunks if chunk_type == 0x004E4942]
    if len(json_chunks) != 1 or len(binary_chunks) != 1:
        raise ConversionError(f"{source_name}: expected one JSON and one BIN chunk")
    try:
        gltf = json.loads(json_chunks[0].decode("utf-8").rstrip("\x00 \t\r\n"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ConversionError(f"{source_name}: invalid GLB JSON: {exc}") from exc
    binary = binary_chunks[0]
    if gltf.get("asset", {}).get("version") != "2.0":
        raise ConversionError(f"{source_name}: asset metadata is not glTF 2.0")
    buffers = gltf.get("buffers", [])
    if len(buffers) != 1 or "uri" in buffers[0]:
        raise ConversionError(f"{source_name}: GLB must have one embedded buffer and no sidecar")
    declared_buffer_bytes = buffers[0].get("byteLength")
    if not isinstance(declared_buffer_bytes, int) or not 0 <= len(binary) - declared_buffer_bytes <= 3:
        raise ConversionError(f"{source_name}: embedded buffer length is inconsistent")
    if any(binary[declared_buffer_bytes:]):
        raise ConversionError(f"{source_name}: GLB binary padding contains nonzero bytes")
    _identity_node(gltf)

    meshes = gltf.get("meshes", [])
    materials = gltf.get("materials", [])
    if len(meshes) != 1 or not materials:
        raise ConversionError(f"{source_name}: expected one joined mesh with source materials")
    triangles = 0
    surfaces = 0
    bounds_min = [math.inf, math.inf, math.inf]
    bounds_max = [-math.inf, -math.inf, -math.inf]
    for primitive_index, primitive in enumerate(meshes[0].get("primitives", [])):
        label = f"{source_name} primitive {primitive_index}"
        if primitive.get("mode", 4) != 4:
            raise ConversionError(f"{label}: only triangle-list surfaces are accepted")
        attributes = primitive.get("attributes", {})
        if "POSITION" not in attributes:
            raise ConversionError(f"{label}: POSITION is missing")
        minimum, maximum, vertex_count = _position_bounds(gltf, binary, attributes["POSITION"], label)
        for axis in range(3):
            bounds_min[axis] = min(bounds_min[axis], minimum[axis])
            bounds_max[axis] = max(bounds_max[axis], maximum[axis])
        if "indices" in primitive:
            triangles += _validate_indices(gltf, binary, primitive["indices"], vertex_count, label)
        else:
            if vertex_count % 3:
                raise ConversionError(f"{label}: non-indexed vertex count is not divisible by three")
            triangles += vertex_count // 3
        material_index = primitive.get("material")
        if not isinstance(material_index, int) or not 0 <= material_index < len(materials):
            raise ConversionError(f"{label}: material reference is missing")
        surfaces += 1
    if triangles <= 0 or surfaces <= 0:
        raise ConversionError(f"{source_name}: no triangle surfaces were found")

    material_records = []
    for index, material in enumerate(materials):
        alpha_mode = material.get("alphaMode", "OPAQUE")
        if alpha_mode not in ("OPAQUE", "MASK", "BLEND"):
            raise ConversionError(f"{source_name}: material {index} has an unknown alpha mode")
        cutoff = material.get("alphaCutoff", 0.5) if alpha_mode == "MASK" else None
        if cutoff is not None and (not math.isfinite(float(cutoff)) or not 0.0 <= float(cutoff) <= 1.0):
            raise ConversionError(f"{source_name}: material {index} alpha cutoff is invalid")
        material_records.append(
            {
                "name": material.get("name", f"material_{index}"),
                "alpha_mode": alpha_mode,
                "alpha_cutoff": round(float(cutoff), 9) if cutoff is not None else None,
                "double_sided": bool(material.get("doubleSided", False)),
            }
        )
    if len(material_records) != 2 or sum(item["alpha_mode"] == "MASK" for item in material_records) != 1:
        raise ConversionError(f"{source_name}: expected one opaque and one masked material")
    if any(item["alpha_mode"] == "MASK" and not item["double_sided"] for item in material_records):
        raise ConversionError(f"{source_name}: the masked foliage material must remain double-sided")

    raw_height = bounds_max[1] - bounds_min[1]
    size = [bounds_max[axis] - bounds_min[axis] for axis in range(3)]
    if raw_height <= 0.0 or abs(bounds_min[1]) > 1e-5:
        raise ConversionError(f"{source_name}: source origin must rest at the ground plane")
    normalized = {
        "min": [round(bounds_min[0] / raw_height, 9), 0.0, round(bounds_min[2] / raw_height, 9)],
        "max": [round(bounds_max[0] / raw_height, 9), 1.0, round(bounds_max[2] / raw_height, 9)],
        "size": [round(size[0] / raw_height, 9), 1.0, round(size[2] / raw_height, 9)],
        "height": 1.0,
        "normalization_scale": round(1.0 / raw_height, 12),
        "ground_offset_after_scale": 0.0,
    }
    declared_image_records = _embedded_image_records(gltf, binary)
    return {
        "source_triangles": triangles,
        "source_surfaces": surfaces,
        "source_materials": len(material_records),
        "source_material_names": [item["name"] for item in material_records],
        "source_material_conventions": material_records,
        "source_bounds_m": {
            "min": [round(value, 6) for value in bounds_min],
            "max": [round(value, 6) for value in bounds_max],
            "size": [round(value, 6) for value in size],
            "height": round(raw_height, 6),
            "ground_offset": round(max(0.0, -bounds_min[1]), 6),
        },
        "normalized_bounds_1m": normalized,
        "embedded_images": declared_image_records,
        "dependencies": [],
        "extensions_used": sorted(gltf.get("extensionsUsed", [])),
        "source_node_transform": "identity; source Y axis is vertical and source origin is grounded",
    }


def _manifest() -> tuple[dict, dict[str, bytes]]:
    readme = (SOURCE_DIR / SOURCE_README).read_bytes()
    if len(readme) != SOURCE_README_BYTES or sha256_bytes(readme) != SOURCE_README_SHA256:
        raise ConversionError("pinned LandscapeLab README/license evidence changed")
    license_notice = read_license_notice()

    assets = []
    outputs: dict[str, bytes] = {}
    for spec in SOURCE_ASSETS:
        source = SOURCE_DIR / spec["source_path"]
        if not source.is_file():
            raise ConversionError(f"missing pinned source GLB: {source}")
        data = source.read_bytes()
        if len(data) != spec["source_bytes"] or sha256_bytes(data) != spec["source_sha256"]:
            raise ConversionError(f"source GLB differs from its pinned revision: {source}")
        if git_blob_sha1(data) != spec["git_blob_sha1"]:
            raise ConversionError(f"source GLB Git blob identity changed: {source}")
        metadata = inspect_glb(data, spec["source_name"])
        if (
            metadata["source_triangles"] != spec["triangles"]
            or metadata["source_surfaces"] != spec["surfaces"]
            or metadata["source_bounds_m"]["min"] != spec["bounds_min"]
            or metadata["source_bounds_m"]["max"] != spec["bounds_max"]
        ):
            raise ConversionError(f"{source}: measured geometry differs from its reviewed facts")
        output_name = spec["derived_name"]
        outputs[output_name] = data
        assets.append(
            {
                "id": spec["id"],
                "source_name": spec["source_name"],
                "source_entry": SOURCE_PREFIX + spec["source_path"],
                "upstream_path": spec["upstream_path"],
                "git_blob_sha1": spec["git_blob_sha1"],
                "source_bytes": len(data),
                "source_sha256": sha256_bytes(data),
                "derived_path": output_name,
                "derived_bytes": len(data),
                "derived_sha256": sha256_bytes(data),
                "conversion": "byte-for-byte GLB copy; no geometry, material, texture, or transform edits",
                **metadata,
            }
        )
    manifest = {
        "format": "openrc-landscapelab-vegetation-conversion v1",
        "source": {
            "repository": REPOSITORY_URL,
            "revision": REVISION,
            "commit_url": COMMIT_URL,
            "license": LICENSE_NAME,
            "license_url": LICENSE_URL,
            "license_evidence": SOURCE_PREFIX + SOURCE_README,
            "license_evidence_bytes": len(readme),
            "license_evidence_sha256": sha256_bytes(readme),
            "runtime_notice": SOURCE_PREFIX + SOURCE_LICENSE_NOTICE,
            "runtime_notice_bytes": len(license_notice),
            "runtime_notice_sha256": sha256_bytes(license_notice),
        },
        "geometry_created": False,
        "method": "retain the pinned self-contained glTF binary unchanged; inspect its accessors and embedded materials/textures",
        "assets": assets,
    }
    return manifest, outputs


def _manifest_bytes(manifest: dict) -> bytes:
    return (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def verified_conversion() -> tuple[dict, bytes, dict[str, bytes]]:
    """Recompute the source receipt and require derived copies to match it exactly."""
    manifest, outputs = _manifest()
    manifest_bytes = _manifest_bytes(manifest)
    manifest_path = DERIVED_DIR / MANIFEST_NAME
    if not manifest_path.is_file() or manifest_path.read_bytes() != manifest_bytes:
        raise ConversionError(f"derived conversion manifest is missing or stale: {manifest_path}")
    for relative, expected in outputs.items():
        path = DERIVED_DIR / relative
        if not path.is_file() or path.read_bytes() != expected:
            raise ConversionError(f"derived GLB is missing or differs from its source: {path}")
    return manifest, manifest_bytes, outputs


def _write_if_changed(path: Path, data: bytes) -> None:
    if path.is_file() and path.read_bytes() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    temporary.replace(path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate without writing derived files")
    parser.add_argument(
        "--output-root",
        type=Path,
        help="write derived GLBs and manifest to a separate directory",
    )
    args = parser.parse_args(argv)
    manifest, outputs = _manifest()
    output_root = args.output_root or DERIVED_DIR
    if not output_root.is_absolute():
        output_root = ROOT / output_root
    output_root = output_root.resolve()
    expected = {output_root / name: data for name, data in outputs.items()}
    expected[output_root / MANIFEST_NAME] = _manifest_bytes(manifest)
    if args.check:
        mismatches = [str(path) for path, data in expected.items() if not path.is_file() or path.read_bytes() != data]
        if mismatches:
            raise ConversionError("derived output differs from the pinned sources: " + ", ".join(mismatches))
    else:
        for path, data in expected.items():
            _write_if_changed(path, data)
    print(
        f"validated {len(manifest['assets'])} unchanged LandscapeLab GLBs: "
        + ", ".join(
            f"{item['id']}={item['source_triangles']:,} triangles/{item['source_surfaces']} surfaces"
            for item in manifest["assets"]
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ConversionError as exc:
        print(f"LandscapeLab vegetation validation failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
