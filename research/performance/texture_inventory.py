#!/usr/bin/env python3
"""Build a read-only, review-oriented inventory of Godot texture imports.

This intentionally reads headers and text metadata only. It does not decode image
pixels, alter imports, or decide whether an import setting is correct.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import re
import struct
import sys
from pathlib import Path
from typing import Any, BinaryIO


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
JPEG_SOF_MARKERS = {
    0xC0,
    0xC1,
    0xC2,
    0xC3,
    0xC5,
    0xC6,
    0xC7,
    0xC9,
    0xCA,
    0xCB,
    0xCD,
    0xCE,
    0xCF,
}
GLB_MAGIC = b"glTF"
GLB_JSON_CHUNK = 0x4E4F534A
GLB_BIN_CHUNK = 0x004E4942
GLB_MAX_JSON_CHUNK = 16 * 1024 * 1024
GLB_IMAGE_HASH_CHUNK_SIZE = 64 * 1024
GLB_MAX_IMAGE_HASH_BYTES = 512 * 1024 * 1024
GLB_MAX_TOTAL_IMAGE_HASH_BYTES = 512 * 1024 * 1024
GLB_MAX_JPEG_HEADER_BYTES = 4 * 1024 * 1024
EXCLUDED_DIRS = {".godot", "captures"}
TEXTURE_IMPORT_SUFFIX = ".import"


def _parse_godot_value(raw: str) -> Any:
    """Parse the scalar/list subset commonly used in Godot import sidecars."""

    value = raw.strip()
    if not value:
        return ""
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if lowered in {"null", "nil"}:
        return None
    try:
        return ast.literal_eval(value)
    except (SyntaxError, ValueError):
        # Godot has values such as Vector2(...) and multiline dictionaries that
        # Python cannot parse. Preserve their source spelling as evidence.
        return value


def parse_import_text(text: str) -> dict[str, dict[str, Any]]:
    """Parse sectioned ``.import`` text without requiring Godot or configparser.

    Unknown fields are retained. Incomplete or malformed lines are ignored so
    partial metadata remains inspectable instead of aborting a whole scan.
    """

    sections: dict[str, dict[str, Any]] = {}
    current_section: str | None = None
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith((";", "#")):
            continue
        if line.startswith("[") and line.endswith("]") and len(line) > 2:
            current_section = line[1:-1].strip()
            sections.setdefault(current_section, {})
            continue
        if current_section is None or "=" not in line:
            continue
        key, raw_value = line.split("=", 1)
        key = key.strip()
        if not key:
            continue
        sections[current_section][key] = _parse_godot_value(raw_value)
    return sections


def _image_result(
    image_format: str,
    status: str,
    *,
    reason: str | None = None,
    **metadata: Any,
) -> dict[str, Any]:
    result: dict[str, Any] = {"format": image_format, "status": status}
    result.update(metadata)
    if reason:
        result["reason"] = reason
    return result


def parse_png_header(data: bytes) -> dict[str, Any]:
    """Read PNG dimensions, bit depth, and stored color type from a header."""

    if len(data) < 8:
        return _image_result("PNG", "unreadable", reason="truncated signature")
    if data[:8] != PNG_SIGNATURE:
        return _image_result("PNG", "unreadable", reason="invalid signature")
    if len(data) < 33:
        return _image_result("PNG", "unreadable", reason="truncated IHDR")
    chunk_length = struct.unpack(">I", data[8:12])[0]
    if data[12:16] != b"IHDR" or chunk_length != 13:
        return _image_result("PNG", "unreadable", reason="missing or invalid IHDR")
    width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", data[16:29]
    )
    if width == 0 or height == 0:
        return _image_result("PNG", "unreadable", reason="zero-sized image")
    layout_by_type = {
        0: ("grayscale", 1),
        2: ("RGB", 3),
        3: ("indexed", None),
        4: ("grayscale+alpha", 2),
        6: ("RGBA", 4),
    }
    layout, channels = layout_by_type.get(color_type, ("unknown", None))
    return _image_result(
        "PNG",
        "parsed",
        width=width,
        height=height,
        bit_depth=bit_depth,
        color_type=color_type,
        channel_layout=layout,
        channel_count=channels,
        interlaced=bool(interlace),
        header_crc_checked=False,
        note=(
            "Indexed PNG channel count depends on its palette and optional transparency."
            if color_type == 3
            else None
        ),
    )


def _read_exact(stream: BinaryIO, size: int) -> bytes | None:
    data = stream.read(size)
    return data if len(data) == size else None


def parse_jpeg_header(stream: BinaryIO) -> dict[str, Any]:
    """Read JPEG dimensions by walking marker lengths, without reading pixels."""

    if _read_exact(stream, 2) != b"\xff\xd8":
        return _image_result("JPEG", "unreadable", reason="invalid or truncated SOI")
    while True:
        byte = stream.read(1)
        if not byte:
            return _image_result("JPEG", "unreadable", reason="no frame header before end of file")
        if byte != b"\xff":
            return _image_result("JPEG", "unreadable", reason="invalid marker prefix")
        marker_byte = stream.read(1)
        while marker_byte == b"\xff":
            marker_byte = stream.read(1)
        if not marker_byte:
            return _image_result("JPEG", "unreadable", reason="truncated marker")
        marker = marker_byte[0]
        if marker == 0x00:
            return _image_result("JPEG", "unreadable", reason="stuffed byte outside image data")
        if marker in {0xD8, 0xD9, 0x01} or 0xD0 <= marker <= 0xD7:
            if marker == 0xD9:
                return _image_result("JPEG", "unreadable", reason="end marker before frame header")
            continue
        segment_length_raw = _read_exact(stream, 2)
        if segment_length_raw is None:
            return _image_result("JPEG", "unreadable", reason="truncated segment length")
        segment_length = struct.unpack(">H", segment_length_raw)[0]
        if segment_length < 2:
            return _image_result("JPEG", "unreadable", reason="invalid segment length")
        payload_length = segment_length - 2
        if marker in JPEG_SOF_MARKERS:
            payload = _read_exact(stream, payload_length)
            if payload is None or len(payload) < 6:
                return _image_result("JPEG", "unreadable", reason="truncated frame header")
            precision = payload[0]
            height, width = struct.unpack(">HH", payload[1:5])
            channels = payload[5]
            if width == 0 or height == 0:
                return _image_result("JPEG", "unreadable", reason="zero-sized image")
            layout = {1: "grayscale", 3: "RGB", 4: "CMYK"}.get(channels, "multi-channel")
            return _image_result(
                "JPEG",
                "parsed",
                width=width,
                height=height,
                bit_depth=precision,
                channel_layout=layout,
                channel_count=channels,
            )
        if marker == 0xDA:
            return _image_result("JPEG", "unreadable", reason="scan data began before a frame header")
        try:
            stream.seek(payload_length, 1)
        except (OSError, ValueError):
            return _image_result("JPEG", "unreadable", reason="could not skip marker payload")
        if stream.tell() < 0:
            return _image_result("JPEG", "unreadable", reason="invalid marker offset")


def inspect_source_image(path: Path) -> dict[str, Any]:
    """Inspect a PNG/JPEG header, or report an explicit unsupported/skipped state."""

    suffix = path.suffix.lower()
    if suffix == ".png":
        try:
            with path.open("rb") as stream:
                header = stream.read(33)
        except OSError as error:
            return _image_result("PNG", "unreadable", reason=f"source read failed: {error}")
        return parse_png_header(header)
    if suffix in {".jpg", ".jpeg"}:
        try:
            with path.open("rb") as stream:
                return parse_jpeg_header(stream)
        except OSError as error:
            return _image_result("JPEG", "unreadable", reason=f"source read failed: {error}")
    return _image_result(
        suffix.lstrip(".").upper() or "UNKNOWN",
        "unsupported",
        reason="header parser is limited to PNG and JPEG",
    )


def _relative_posix(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def _is_excluded(relative_path: Path) -> bool:
    return any(part.lower() in EXCLUDED_DIRS for part in relative_path.parts)


def _iter_files(root: Path, suffixes: set[str] | None = None):
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix().lower()):
        if not path.is_file():
            continue
        try:
            relative = path.relative_to(root)
        except ValueError:
            continue
        if _is_excluded(relative):
            continue
        if suffixes is None or path.suffix.lower() in suffixes:
            yield path


def _within_root(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except (OSError, ValueError):
        return False


def _source_path_for_import(sidecar: Path, deps: dict[str, Any], app_root: Path) -> tuple[Path | None, str]:
    source = deps.get("source_file")
    if isinstance(source, str) and source:
        source_value = source.replace("\\", "/")
        if source_value.startswith("res://"):
            candidate = app_root.joinpath(*Path(source_value[6:]).parts)
        else:
            candidate = Path(source_value)
            if not candidate.is_absolute():
                candidate = app_root / candidate
        if _within_root(candidate, app_root):
            return candidate, source_value
        return None, source_value
    candidate = sidecar.with_suffix("")
    if _within_root(candidate, app_root):
        return candidate, _relative_posix(candidate, app_root)
    return None, _relative_posix(sidecar, app_root)


def _compression_and_import_flags(sections: dict[str, dict[str, Any]]) -> dict[str, Any]:
    params = sections.get("params", {})
    remap = sections.get("remap", {})
    deps = sections.get("deps", {})
    return {
        "importer": remap.get("importer"),
        "resource_type": remap.get("type"),
        "source_file": deps.get("source_file"),
        "compression": {
            "mode": params.get("compress/mode"),
            "high_quality": params.get("compress/high_quality"),
            "lossy_quality": params.get("compress/lossy_quality"),
            "uastc_level": params.get("compress/uastc_level"),
            "rdo_quality_loss": params.get("compress/rdo_quality_loss"),
            "hdr_compression": params.get("compress/hdr_compression"),
            "detect_3d_compress_to": params.get("detect_3d/compress_to"),
        },
        "mipmaps": {
            "generate": params.get("mipmaps/generate"),
            "limit": params.get("mipmaps/limit"),
        },
        "processing": {
            "normal_map_mode": params.get("compress/normal_map"),
            "channel_pack": params.get("compress/channel_pack"),
            "size_limit": params.get("process/size_limit"),
            "normal_map_invert_y": params.get("process/normal_map_invert_y"),
            "hdr_as_srgb": params.get("process/hdr_as_srgb"),
            "premultiplied_alpha": params.get("process/premult_alpha"),
        },
        "color_space": {
            "source_color_hint": "reported per shader sampler when available",
            "hdr_as_srgb_import_flag": params.get("process/hdr_as_srgb"),
            "status": "not inferred from importer metadata alone",
        },
        "raw_params": {key: params[key] for key in sorted(params)},
    }


def _parse_shader_samplers(text: str) -> list[dict[str, Any]]:
    without_comments = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    without_comments = re.sub(r"//[^\r\n]*", "", without_comments)
    declaration = re.compile(
        r"\buniform\s+(sampler(?:2D|2DArray|3D|Cube|CubeArray|ExternalOES|2DMS))\s+"
        r"([A-Za-z_]\w*)(?:\s*\[[^\]]+\])?"
        r"(?:\s*:\s*(?P<hints>[^;=]+))?"
        r"(?:\s*=\s*(?P<initializer>[^;]+))?\s*;"
    )
    samplers = []
    for match in declaration.finditer(without_comments):
        sampler_type, name = match.group(1), match.group(2)
        raw_hints = match.group("hints") or ""
        hints = sorted(set(re.findall(r"\b[A-Za-z_]\w*\b", raw_hints)))
        filter_hints = sorted(hint for hint in hints if hint.startswith("filter_"))
        repeat_hints = sorted(hint for hint in hints if hint.startswith("repeat_"))
        normal_hints = sorted(hint for hint in hints if hint in {"hint_normal", "normal"})
        samplers.append(
            {
                "name": name,
                "type": sampler_type,
                "hint_tokens": hints,
                "color_space_hint": "source_color" if "source_color" in hints else "unspecified",
                "normal_hint": bool(normal_hints),
                "normal_hints": normal_hints,
                "filter_hints": filter_hints,
                "repeat_hints": repeat_hints,
            }
        )
    return sorted(samplers, key=lambda item: (item["name"], item["type"], item["hint_tokens"]))


def _read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        try:
            return path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return None


def _resource_path(raw: str) -> str | None:
    value = raw.replace("\\", "/")
    if not value.startswith("res://"):
        return None
    value = value.split("::", 1)[0].rstrip(",)]}")
    return value


def _app_path_from_resource(resource: str, app_root: Path) -> Path | None:
    if not resource.startswith("res://"):
        return None
    candidate = app_root.joinpath(*Path(resource[6:]).parts)
    return candidate if _within_root(candidate, app_root) else None


EXT_RESOURCE_RE = re.compile(r"\[ext_resource\s+([^\]]*)\]", re.MULTILINE)
QUOTED_ATTR_RE = re.compile(r"([A-Za-z_]\w*)\s*=\s*\"((?:\\.|[^\"])*)\"")
EXT_USE_RE = re.compile(r"\bExtResource\s*\(\s*\"([^\"]+)\"\s*\)")
RESOURCE_STRING_RE = re.compile(r"res://[^\s\"']+")


def _material_uses(relative_path: str, text: str, shader_lookup: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    ext_resources: dict[str, dict[str, str]] = {}
    for match in EXT_RESOURCE_RE.finditer(text):
        attrs = dict(QUOTED_ATTR_RE.findall(match.group(1)))
        if attrs.get("id"):
            ext_resources[attrs["id"]] = attrs
    shader_ids = {
        resource_id
        for resource_id, attrs in ext_resources.items()
        if attrs.get("type") == "Shader"
    }
    shader_assignments = re.findall(
        r"\bshader\s*=\s*ExtResource\s*\(\s*\"([^\"]+)\"\s*\)", text
    )
    context_unknown = len(shader_assignments) > 1
    active_shader_id = shader_assignments[0] if len(shader_assignments) == 1 else None
    shader_path = None
    if active_shader_id in shader_ids and not context_unknown:
        shader_path = _resource_path(ext_resources[active_shader_id].get("path", ""))
    elif active_shader_id and active_shader_id in ext_resources and not context_unknown:
        shader_path = _resource_path(ext_resources[active_shader_id].get("path", ""))
    shader_samplers = {
        sampler["name"]: sampler
        for sampler in shader_lookup.get(shader_path or "", {}).get("samplers", [])
    }

    uses: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str]] = set()
    for resource_path in RESOURCE_STRING_RE.findall(text):
        normalized = _resource_path(resource_path)
        if not normalized:
            continue
        key = (relative_path, normalized, "resource_string")
        if key in seen:
            continue
        seen.add(key)
        uses.append(
            {
                "consumer_path": relative_path,
                "resource_path": normalized,
                "usage_kind": "resource_string",
            }
        )

    for property_name, resource_id in re.findall(
        r"^\s*([A-Za-z_]\w*(?:/[A-Za-z_]\w*)*)\s*=\s*ExtResource\s*\(\s*\"([^\"]+)\"\s*\)",
        text,
        flags=re.MULTILINE,
    ):
        if property_name == "shader":
            continue
        attrs = ext_resources.get(resource_id)
        if not attrs:
            continue
        texture_path = _resource_path(attrs.get("path", ""))
        if not texture_path:
            continue
        sampler_name = property_name.rsplit("/", 1)[-1]
        sampler = shader_samplers.get(sampler_name)
        binding_key = (relative_path, texture_path, property_name)
        if binding_key in seen:
            continue
        seen.add(binding_key)
        uses.append(
            {
                "consumer_path": relative_path,
                "resource_path": texture_path,
                "usage_kind": "material_binding",
                "property": property_name,
                "sampler": sampler_name,
                "shader_path": shader_path,
                "shader_context": "unknown_multiple_shader_assignments" if context_unknown else ("single_shader_assignment" if shader_path else "unknown"),
                "sampler_hints": sampler,
            }
        )
    return sorted(uses, key=lambda item: (item["resource_path"], item["consumer_path"], item["usage_kind"], item.get("property", "")))


def _adjacent_provenance(source_path: Path, app_root: Path) -> list[str]:
    markers = ("license", "licence", "notice", "copying", "copyright", "provenance", "credit")
    found: set[str] = set()
    parent = source_path.parent
    while _within_root(parent, app_root):
        try:
            for candidate in parent.iterdir():
                if not candidate.is_file():
                    continue
                if any(marker in candidate.name.lower() for marker in markers):
                    found.add(_relative_posix(candidate, app_root))
        except OSError:
            pass
        if parent.resolve() == app_root.resolve():
            break
        parent = parent.parent
    return sorted(found)


def _rgba8_reference_bytes(width: int, height: int, mipmaps: bool) -> int:
    total = 0
    current_width, current_height = width, height
    while True:
        total += current_width * current_height * 4
        if not mipmaps or (current_width == 1 and current_height == 1):
            return total
        current_width = max(1, current_width // 2)
        current_height = max(1, current_height // 2)


def _nonnegative_integer(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


class _BoundedStream:
    """Expose a bounded view of a seekable stream to header parsers."""

    def __init__(self, stream: BinaryIO, start: int, length: int):
        self._stream = stream
        self._start = start
        self._length = length
        self._position = 0

    def read(self, size: int = -1) -> bytes:
        if size is None or size < 0:
            size = self._length - self._position
        size = min(size, self._length - self._position)
        if size <= 0:
            return b""
        self._stream.seek(self._start + self._position)
        data = self._stream.read(size)
        self._position += len(data)
        return data

    def seek(self, offset: int, whence: int = 0) -> int:
        if whence == 0:
            position = offset
        elif whence == 1:
            position = self._position + offset
        elif whence == 2:
            position = self._length + offset
        else:
            raise ValueError("invalid whence")
        if position < 0 or position > self._length:
            raise ValueError("seek outside bounded image payload")
        self._position = position
        return position

    def tell(self) -> int:
        return self._position


def _hash_stream_range(
    stream: BinaryIO, start: int, length: int, hash_budget: int
) -> tuple[str | None, str]:
    if length > min(GLB_MAX_IMAGE_HASH_BYTES, hash_budget):
        return None, "skipped_size_limit"
    digest = hashlib.sha256()
    stream.seek(start)
    remaining = length
    while remaining:
        data = stream.read(min(GLB_IMAGE_HASH_CHUNK_SIZE, remaining))
        if not data:
            return None, "unreadable_truncated_payload"
        digest.update(data)
        remaining -= len(data)
    return digest.hexdigest(), "hashed"


def _glb_material_roles(document: dict[str, Any]) -> dict[int, list[dict[str, Any]]]:
    """Resolve exact glTF 2.0 core material texture references to image indices."""

    role_definitions = (
        (
            "pbrMetallicRoughness.baseColorTexture",
            "base_color",
            ["R", "G", "B", "A"],
            [
                {"channels": ["R", "G", "B"], "meaning": "base color", "color_space": "sRGB"},
                {"channels": ["A"], "meaning": "alpha", "color_space": "linear"},
            ],
        ),
        (
            "pbrMetallicRoughness.metallicRoughnessTexture",
            "metallic_roughness",
            ["G", "B"],
            [
                {"channels": ["G"], "meaning": "roughness", "color_space": "linear"},
                {"channels": ["B"], "meaning": "metallic", "color_space": "linear"},
            ],
        ),
        (
            "normalTexture",
            "normal",
            ["R", "G", "B"],
            [{"channels": ["R", "G", "B"], "meaning": "tangent-space normal", "color_space": "linear"}],
        ),
        (
            "occlusionTexture",
            "occlusion",
            ["R"],
            [{"channels": ["R"], "meaning": "occlusion", "color_space": "linear"}],
        ),
        (
            "emissiveTexture",
            "emissive",
            ["R", "G", "B"],
            [{"channels": ["R", "G", "B"], "meaning": "emissive", "color_space": "sRGB"}],
        ),
    )

    textures = document.get("textures", [])
    if not isinstance(textures, list):
        textures = []
    image_indices_by_texture: dict[int, list[int]] = {}
    for texture_index, texture in enumerate(textures):
        if not isinstance(texture, dict):
            continue
        image_index = texture.get("source")
        if _nonnegative_integer(image_index):
            image_indices_by_texture[texture_index] = [image_index]

    materials = document.get("materials", [])
    if not isinstance(materials, list):
        materials = []
    roles_by_image: dict[int, list[dict[str, Any]]] = {}
    for material_index, material in enumerate(materials):
        if not isinstance(material, dict):
            continue
        for property_path, role, channels, semantics in role_definitions:
            if property_path.startswith("pbrMetallicRoughness."):
                pbr = material.get("pbrMetallicRoughness")
                texture_info = pbr.get(property_path.split(".", 1)[1]) if isinstance(pbr, dict) else None
            else:
                texture_info = material.get(property_path)
            if not isinstance(texture_info, dict):
                continue
            texture_index = texture_info.get("index")
            if not _nonnegative_integer(texture_index):
                continue
            for image_index in image_indices_by_texture.get(texture_index, []):
                roles_by_image.setdefault(image_index, []).append(
                    {
                        "material_index": material_index,
                        "material_name": material.get("name"),
                        "texture_index": texture_index,
                        "property": property_path,
                        "role": role,
                        "channels": list(channels),
                        "declared_color_semantics": [dict(item) for item in semantics],
                    }
                )

    for uses in roles_by_image.values():
        uses.sort(key=lambda item: (item["material_index"], item["texture_index"], item["property"], item["role"]))
    return roles_by_image


def _summarize_glb_color_semantics(roles: list[dict[str, Any]]) -> dict[str, Any]:
    by_channel: dict[str, dict[str, set[str]]] = {}
    for role in roles:
        for semantic in role["declared_color_semantics"]:
            for channel in semantic["channels"]:
                by_channel.setdefault(channel, {}).setdefault(semantic["color_space"], set()).add(role["role"])
    channel_semantics = []
    conflicts = []
    for channel in sorted(by_channel):
        spaces = by_channel[channel]
        ordered_spaces = sorted(spaces)
        channel_semantics.append(
            {
                "channel": channel,
                "color_spaces": ordered_spaces,
                "roles": sorted({role for values in spaces.values() for role in values}),
            }
        )
        if len(ordered_spaces) > 1:
            conflicts.append(
                {
                    "channel": channel,
                    "color_spaces": ordered_spaces,
                    "roles": sorted({role for values in spaces.values() for role in values}),
                }
            )
    distinct_roles = sorted({role["role"] for role in roles})
    role_reuse = len(distinct_roles) > 1
    return {
        "status": "ambiguous" if conflicts or role_reuse else ("declared" if channel_semantics else "not_declared_by_core_material_refs"),
        "channel_semantics": channel_semantics,
        "conflicts": conflicts,
        "roles": distinct_roles,
        "role_reuse": role_reuse,
        "scope": "exact glTF 2.0 core material references only; image profiles and extension references are not inspected",
    }


def _buffer0_for_glb(document: dict[str, Any], bin_chunk: tuple[int, int] | None) -> dict[str, Any]:
    buffers = document.get("buffers")
    if not isinstance(buffers, list) or not buffers:
        return {"status": "unavailable", "reason": "GLB has no buffer 0 metadata"}
    buffer0 = buffers[0]
    if not isinstance(buffer0, dict):
        return {"status": "unavailable", "reason": "buffer 0 metadata is not an object"}
    byte_length = buffer0.get("byteLength")
    if not _nonnegative_integer(byte_length):
        return {"status": "unavailable", "reason": "buffer 0 byteLength is not a non-negative integer"}
    if "uri" in buffer0:
        return {"status": "unavailable", "reason": "buffer 0 has a URI; external or data URI buffers are not read"}
    if bin_chunk is None:
        return {"status": "unavailable", "reason": "buffer 0 has no GLB BIN chunk"}
    bin_offset, bin_length = bin_chunk
    if bin_length < byte_length or bin_length > byte_length + 3:
        return {"status": "invalid", "reason": "BIN chunk length does not match buffer 0 byteLength and GLB padding"}
    return {
        "status": "available",
        "byte_length": byte_length,
        "bin_offset": bin_offset,
        "bin_length": bin_length,
    }


def _inspect_buffer_view_image(
    stream: BinaryIO,
    image: dict[str, Any],
    buffer_views: Any,
    buffer0: dict[str, Any],
    hash_budget: int,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "inspection": "UNINSPECTED",
        "header": None,
        "header_status": "uninspected",
        "payload_sha256": None,
        "hash_status": "not_attempted",
    }
    if "uri" in image:
        result["reason"] = "image defines both uri and bufferView"
        return result
    buffer_view_index = image.get("bufferView")
    if not _nonnegative_integer(buffer_view_index):
        result["reason"] = "image bufferView is not a non-negative integer"
        return result
    if not isinstance(buffer_views, list) or buffer_view_index >= len(buffer_views):
        result["reason"] = "image bufferView index is outside the bufferViews array"
        return result
    view = buffer_views[buffer_view_index]
    if not isinstance(view, dict):
        result["reason"] = "image bufferView metadata is not an object"
        return result
    if "byteStride" in view or "target" in view:
        result["reason"] = "image bufferView defines forbidden byteStride or target metadata"
        return result
    buffer_index = view.get("buffer")
    if not _nonnegative_integer(buffer_index):
        result["reason"] = "image bufferView buffer is not a non-negative integer"
        return result
    if buffer_index != 0:
        result["reason"] = f"image bufferView uses buffer {buffer_index}; only GLB buffer 0 is inspected"
        return result
    if buffer0.get("status") != "available":
        result["reason"] = buffer0.get("reason", "GLB buffer 0 is unavailable")
        return result
    byte_offset = view.get("byteOffset", 0)
    byte_length = view.get("byteLength")
    if not _nonnegative_integer(byte_offset):
        result["reason"] = "image bufferView byteOffset is not a non-negative integer"
        return result
    if not _nonnegative_integer(byte_length) or byte_length == 0:
        result["reason"] = "image bufferView byteLength is not a positive integer"
        return result
    buffer_length = buffer0["byte_length"]
    bin_length = buffer0["bin_length"]
    if byte_offset + byte_length > buffer_length:
        result["reason"] = "image bufferView range exceeds buffer 0 byteLength"
        return result
    if byte_offset + byte_length > bin_length:
        result["reason"] = "image bufferView range exceeds the GLB BIN chunk"
        return result
    mime_type = image.get("mimeType")
    if not isinstance(mime_type, str):
        result["reason"] = "bufferView image is missing a string mimeType"
        return result
    mime_type = mime_type.strip().lower()
    image_format = {"image/png": "PNG", "image/jpeg": "JPEG"}.get(mime_type)
    if image_format is None:
        result["reason"] = f"unsupported embedded image MIME type: {mime_type or '(empty)'}"
        return result
    payload_start = buffer0["bin_offset"] + byte_offset
    if image_format == "PNG":
        stream.seek(payload_start)
        header_bytes = stream.read(min(33, byte_length))
        header = parse_png_header(header_bytes)
    else:
        header_scan_length = min(byte_length, GLB_MAX_JPEG_HEADER_BYTES)
        header = parse_jpeg_header(_BoundedStream(stream, payload_start, header_scan_length))
    digest, hash_status = _hash_stream_range(stream, payload_start, byte_length, hash_budget)
    result.update(
        {
            "inspection": "INSPECTED" if hash_status == "hashed" else "PARTIAL",
            "header": header,
            "header_status": header["status"],
            "payload_bytes": byte_length,
            "payload_sha256": digest,
            "hash_status": hash_status,
        }
    )
    if hash_status != "hashed":
        result["reason"] = "payload SHA-256 was not completed within the configured image/GLB byte limit or could not be read"
    return result


def _parse_glb(path: Path, relative_path: str) -> dict[str, Any]:
    result: dict[str, Any] = {
        "path": relative_path,
        "status": "unparsed",
        "embedded_image_count": None,
        "external_image_count": None,
        "invalid_image_count": None,
        "images": [],
        "external_images": [],
        "invalid_images": [],
        "inspection": "UNINSPECTED",
    }
    try:
        file_size = path.stat().st_size
        with path.open("rb") as stream:
            header = _read_exact(stream, 12)
            if header is None:
                result["reason"] = "truncated GLB header"
                return result
            magic, version, declared_length = struct.unpack("<4sII", header)
            if magic != GLB_MAGIC or version != 2:
                result["reason"] = "not a GLB 2 container"
                return result
            if declared_length < 20 or declared_length != file_size:
                result["reason"] = "declared GLB length does not match the file length"
                return result
            position = 12
            json_bytes: bytes | None = None
            bin_chunk: tuple[int, int] | None = None
            chunk_index = 0
            while position < declared_length:
                if declared_length - position < 8:
                    result["reason"] = "truncated GLB chunk header"
                    return result
                stream.seek(position)
                chunk_header = _read_exact(stream, 8)
                if chunk_header is None:
                    result["reason"] = "truncated GLB chunk header"
                    return result
                chunk_length, chunk_type = struct.unpack("<II", chunk_header)
                data_offset = position + 8
                chunk_end = data_offset + chunk_length
                if chunk_length % 4:
                    result["reason"] = "GLB chunk length is not 4-byte aligned"
                    return result
                if chunk_end > declared_length:
                    result["reason"] = "GLB chunk exceeds declared GLB length"
                    return result
                if chunk_index == 0 and chunk_type != GLB_JSON_CHUNK:
                    result["reason"] = "first chunk is not JSON"
                    return result
                if chunk_type == GLB_JSON_CHUNK:
                    if json_bytes is not None or chunk_index != 0:
                        result["reason"] = "GLB contains a duplicate or misplaced JSON chunk"
                        return result
                    if chunk_length > GLB_MAX_JSON_CHUNK:
                        result["reason"] = "JSON chunk exceeds the bounded metadata limit"
                        return result
                    stream.seek(data_offset)
                    json_bytes = _read_exact(stream, chunk_length)
                    if json_bytes is None:
                        result["reason"] = "truncated JSON chunk"
                        return result
                elif chunk_type == GLB_BIN_CHUNK:
                    if bin_chunk is not None:
                        result["reason"] = "GLB contains more than one BIN chunk"
                        return result
                    if chunk_index != 1:
                        result["reason"] = "GLB BIN chunk is not the second chunk"
                        return result
                    bin_chunk = (data_offset, chunk_length)
                position = chunk_end
                chunk_index += 1
            if position != declared_length or json_bytes is None:
                result["reason"] = "GLB chunk sequence does not cover the declared file length"
                return result
            document = json.loads(json_bytes.decode("utf-8").rstrip("\x00 \t\r\n"))
            if not isinstance(document, dict):
                result["reason"] = "GLB JSON root is not an object"
                return result
            images = document.get("images", [])
            if not isinstance(images, list):
                images = []
            buffer_views = document.get("bufferViews", [])
            buffer0 = _buffer0_for_glb(document, bin_chunk)
            roles_by_image = _glb_material_roles(document)
            image_records: list[dict[str, Any]] = []
            external_records: list[dict[str, Any]] = []
            invalid_records: list[dict[str, Any]] = []
            embedded_count = external_count = invalid_count = 0
            remaining_hash_budget = GLB_MAX_TOTAL_IMAGE_HASH_BYTES
            for index, image in enumerate(images):
                if not isinstance(image, dict):
                    invalid_count += 1
                    invalid_records.append(
                        {
                            "index": index,
                            "source_kind": "invalid",
                            "embedded": False,
                            "inspection": "UNINSPECTED",
                            "reason": "image entry is not an object",
                            "material_roles": roles_by_image.get(index, []),
                            "declared_color_semantics": _summarize_glb_color_semantics(roles_by_image.get(index, [])),
                        }
                    )
                    continue
                has_buffer_view = "bufferView" in image
                uri = image.get("uri")
                is_data_uri = isinstance(uri, str) and uri.startswith("data:")
                is_external_uri = isinstance(uri, str) and bool(uri) and not is_data_uri
                embedded = has_buffer_view or is_data_uri
                if embedded:
                    embedded_count += 1
                    source_kind = "bufferView" if has_buffer_view else "data_uri"
                    inspected = (
                        _inspect_buffer_view_image(
                            stream, image, buffer_views, buffer0, remaining_hash_budget
                        )
                        if has_buffer_view
                        else {
                            "inspection": "UNINSPECTED",
                            "header": None,
                            "header_status": "uninspected",
                            "payload_sha256": None,
                            "hash_status": "not_attempted",
                            "reason": "data URI image payload inspection is unsupported",
                        }
                    )
                    if inspected.get("hash_status") == "hashed":
                        remaining_hash_budget -= inspected.get("payload_bytes", 0)
                elif is_external_uri:
                    external_count += 1
                    source_kind = "external_uri"
                    inspected = {
                        "inspection": "UNINSPECTED",
                        "header": None,
                        "header_status": "uninspected",
                        "payload_sha256": None,
                        "hash_status": "not_attempted",
                        "reason": "external image URI was not read; no network access was attempted",
                    }
                else:
                    invalid_count += 1
                    source_kind = "invalid"
                    invalid_reason = (
                        "image uri is not a non-empty string"
                        if "uri" in image
                        else "image has neither a bufferView nor a non-empty URI"
                    )
                    inspected = {
                        "inspection": "UNINSPECTED",
                        "header": None,
                        "header_status": "uninspected",
                        "payload_sha256": None,
                        "hash_status": "not_attempted",
                        "reason": invalid_reason,
                    }
                roles = roles_by_image.get(index, [])
                image_record = {
                    "index": index,
                    "name": image.get("name"),
                    "mime_type": image.get("mimeType"),
                    "source_kind": source_kind,
                    "embedded": embedded,
                    "material_roles": roles,
                    "declared_color_semantics": _summarize_glb_color_semantics(roles),
                    **inspected,
                }
                if has_buffer_view:
                    image_record["buffer_view"] = image.get("bufferView")
                elif is_data_uri:
                    image_record["uri_kind"] = "data_uri"
                elif is_external_uri:
                    image_record["uri_kind"] = "external_uri"
                if embedded:
                    image_records.append(image_record)
                elif source_kind == "external_uri":
                    external_records.append(image_record)
                else:
                    invalid_records.append(image_record)
    except (OSError, UnicodeError, json.JSONDecodeError, RecursionError, struct.error) as error:
        result["reason"] = f"GLB metadata read failed: {error}"
        return result
    result.update(
        {
            "status": "parsed",
            "embedded_image_count": embedded_count,
            "external_image_count": external_count,
            "invalid_image_count": invalid_count,
            "images": image_records,
            "external_images": external_records,
            "invalid_images": invalid_records,
            "buffer0": buffer0,
            "inspection": "supported PNG/JPEG bufferView headers and SHA-256 inspected where valid; pixels and runtime import behavior are unqualified",
        }
    )
    return result


def build_inventory(app_root: Path) -> dict[str, Any]:
    """Scan a Godot app directory without changing files or importing assets."""

    app_root = app_root.resolve()
    if not app_root.is_dir():
        raise NotADirectoryError(f"app root is not a directory: {app_root}")

    shader_lookup: dict[str, dict[str, Any]] = {}
    for path in _iter_files(app_root, {".gdshader", ".gdshaderinc"}):
        text = _read_text(path)
        if text is None:
            continue
        relative = _relative_posix(path, app_root)
        shader_lookup["res://" + relative] = {
            "path": relative,
            "samplers": _parse_shader_samplers(text),
        }
    shaders = [shader_lookup[key] for key in sorted(shader_lookup)]

    resource_uses: list[dict[str, Any]] = []
    for path in _iter_files(app_root, {".tres", ".tscn"}):
        text = _read_text(path)
        if text is None:
            continue
        resource_uses.extend(_material_uses(_relative_posix(path, app_root), text, shader_lookup))
    resource_uses.sort(
        key=lambda item: (
            item["resource_path"],
            item["consumer_path"],
            item["usage_kind"],
            item.get("property", ""),
        )
    )

    uses_by_resource: dict[str, list[dict[str, Any]]] = {}
    for use in resource_uses:
        uses_by_resource.setdefault(use["resource_path"], []).append(use)

    texture_entries: list[dict[str, Any]] = []
    non_texture_imports = 0
    import_sidecars = list(_iter_files(app_root, {".import"}))
    for sidecar in import_sidecars:
        sidecar_relative = _relative_posix(sidecar, app_root)
        text = _read_text(sidecar)
        sections = parse_import_text(text or "")
        flags = _compression_and_import_flags(sections)
        if flags.get("importer") != "texture":
            non_texture_imports += 1
            continue
        source_path, source_name = _source_path_for_import(sidecar, sections.get("deps", {}), app_root)
        exists = bool(source_path and source_path.is_file())
        if source_path and exists:
            source_relative = _relative_posix(source_path, app_root)
            image_info = inspect_source_image(source_path)
            try:
                source_size = source_path.stat().st_size
            except OSError:
                source_size = None
        else:
            source_relative = source_name.replace("\\", "/")
            image_info = _image_result(
                Path(source_name).suffix.lstrip(".").upper() or "UNKNOWN",
                "unreadable",
                reason="source file is missing or outside the app root",
            )
            source_size = None
        resource_key = "res://" + source_relative if not source_relative.startswith("res://") else source_relative
        texture_uses = uses_by_resource.get(resource_key, [])
        candidates: list[dict[str, Any]] = []
        for use in texture_uses:
            sampler = use.get("sampler_hints")
            if not isinstance(sampler, dict):
                continue
            if sampler.get("normal_hint") and flags["processing"].get("normal_map_mode") in (None, 0, "0"):
                candidates.append(
                    {
                        "candidate": "normal_sampler_without_import_normal_mode",
                        "consumer_path": use["consumer_path"],
                        "sampler": sampler.get("name"),
                        "evidence": "shader declares hint_normal while import normal_map is absent or zero",
                        "interpretation": "manual review candidate; custom shader and engine import behavior may make this intentional",
                    }
                )
            mip_filter = any("mipmap" in hint for hint in sampler.get("filter_hints", []))
            if mip_filter and flags["mipmaps"].get("generate") is False:
                candidates.append(
                    {
                        "candidate": "mipmap_filter_without_generated_mipmaps",
                        "consumer_path": use["consumer_path"],
                        "sampler": sampler.get("name"),
                        "evidence": "shader requests a mipmap filter while import metadata disables mip generation",
                        "interpretation": "manual review candidate; imported resource behavior and use may be intentional",
                    }
                )
        candidates.sort(key=lambda item: (item["candidate"], item["consumer_path"], item["sampler"]))
        dimensions = image_info.get("width"), image_info.get("height")
        mipmaps = flags["mipmaps"].get("generate") is True
        reference_bytes = None
        if image_info.get("status") == "parsed" and dimensions[0] and dimensions[1]:
            reference_bytes = _rgba8_reference_bytes(dimensions[0], dimensions[1], mipmaps)
        material_uses = [use for use in texture_uses if use["usage_kind"] == "material_binding"]
        consumer_paths = sorted({use["consumer_path"] for use in texture_uses})
        texture_entries.append(
            {
                "source": source_relative,
                "import_sidecar": sidecar_relative,
                "source_exists": exists,
                "source_bytes": source_size,
                "source_image": image_info,
                "import": flags,
                "memory_reference": {
                    "rgba8_uncompressed_bytes": reference_bytes,
                    "mipmaps_assumed": mipmaps,
                    "status": "theoretical reference only; not a resident-memory measurement",
                    "limitations": "does not model GPU block compression, driver format selection, tiling, or runtime copies",
                },
                "consumer_paths": consumer_paths,
                "material_uses": material_uses,
                "provenance_paths": (
                    [_relative_posix(sidecar, app_root)]
                    + (_adjacent_provenance(source_path, app_root) if source_path and exists else [])
                ),
                "review_candidates": candidates,
            }
        )
    texture_entries.sort(key=lambda item: (item["source"].lower(), item["source"], item["import_sidecar"]))

    glb_entries = [_parse_glb(path, _relative_posix(path, app_root)) for path in _iter_files(app_root, {".glb"})]
    glb_entries.sort(key=lambda item: item["path"].lower())
    embedded_count = sum(entry["embedded_image_count"] or 0 for entry in glb_entries)
    coverage_gaps = []
    for entry in glb_entries:
        if entry["status"] != "parsed":
            coverage_gaps.append(
                {
                    "path": entry["path"],
                    "gap": "GLB image metadata unavailable; embedded payload coverage is UNINSPECTED",
                    "reason": entry.get("reason"),
                }
            )
            continue
        all_images = entry["images"] + entry["external_images"] + entry["invalid_images"]
        for image in all_images:
            if image.get("embedded") and image.get("inspection") != "INSPECTED":
                coverage_gaps.append(
                    {
                        "path": entry["path"],
                        "image_index": image["index"],
                        "gap": "embedded image header/hash inspection is incomplete",
                        "inspection": image.get("inspection"),
                        "reason": image.get("reason"),
                    }
                )
            elif image.get("embedded") and image.get("header_status") != "parsed":
                coverage_gaps.append(
                    {
                        "path": entry["path"],
                        "image_index": image["index"],
                        "gap": "embedded image header could not be parsed",
                        "reason": (image.get("header") or {}).get("reason"),
                    }
                )
            elif image.get("source_kind") == "external_uri":
                coverage_gaps.append(
                    {
                        "path": entry["path"],
                        "image_index": image["index"],
                        "gap": "external image URI is UNINSPECTED; no network access was attempted",
                    }
                )
            elif image.get("source_kind") == "invalid":
                coverage_gaps.append(
                    {
                        "path": entry["path"],
                        "image_index": image["index"],
                        "gap": "image source metadata is invalid",
                        "reason": image.get("reason"),
                    }
                )
        if entry["embedded_image_count"]:
            coverage_gaps.append(
                {
                    "path": entry["path"],
                    "gap": "pixel decode and runtime import/transcode/color-space behavior are not qualified",
                    "embedded_image_count": entry["embedded_image_count"],
                    "headers_parsed": sum(
                        image.get("embedded") and image.get("header_status") == "parsed"
                        for image in entry["images"]
                    ),
                    "payloads_hashed": sum(
                        image.get("embedded") and image.get("hash_status") == "hashed"
                        for image in entry["images"]
                    ),
                }
            )

    parsed_sources = sum(entry["source_image"]["status"] == "parsed" for entry in texture_entries)
    unreadable_sources = sum(entry["source_image"]["status"] == "unreadable" for entry in texture_entries)
    unsupported_sources = sum(entry["source_image"]["status"] == "unsupported" for entry in texture_entries)
    return {
        "schema_version": 1,
        "tool": "research/performance/texture_inventory.py",
        "scope": {
            "app_root": ".",
            "read_only": True,
            "excluded_directories": [".godot", "captures"],
            "image_inspection": "source PNG/JPEG headers; GLB PNG/JPEG bufferView headers and streamed SHA-256 where supported; no pixel decode or import mutation",
            "color_space_policy": "source_color and normal hints are reported from shaders; exact glTF core material roles declare texture channel semantics; embedded image profiles are not inspected",
            "candidate_policy": "review_candidates are nonblocking prompts, never automatic import errors",
        },
        "summary": {
            "import_sidecars": len(import_sidecars),
            "texture_imports": len(texture_entries),
            "non_texture_imports": non_texture_imports,
            "source_images_parsed": parsed_sources,
            "source_images_unreadable": unreadable_sources,
            "source_images_unsupported": unsupported_sources,
            "shaders": len(shaders),
            "shader_sampler_declarations": sum(len(shader["samplers"]) for shader in shaders),
            "material_resource_uses": len(resource_uses),
            "glb_files": len(glb_entries),
            "embedded_glb_images_counted_from_json": embedded_count,
            "embedded_glb_images_inspected": sum(
                image.get("embedded") and image.get("inspection") == "INSPECTED"
                for entry in glb_entries
                for image in entry["images"]
            ),
            "embedded_glb_image_headers_parsed": sum(
                image.get("embedded") and image.get("header_status") == "parsed"
                for entry in glb_entries
                for image in entry["images"]
            ),
            "embedded_glb_image_payloads_hashed": sum(
                image.get("embedded") and image.get("hash_status") == "hashed"
                for entry in glb_entries
                for image in entry["images"]
            ),
            "external_glb_images_counted": sum(entry["external_image_count"] or 0 for entry in glb_entries),
            "invalid_glb_image_entries": sum(entry["invalid_image_count"] or 0 for entry in glb_entries),
            "coverage_gaps": len(coverage_gaps),
            "review_candidate_count": sum(len(entry["review_candidates"]) for entry in texture_entries),
        },
        "textures": texture_entries,
        "shaders": shaders,
        "resource_uses": resource_uses,
        "glb_coverage": glb_entries,
        "coverage_gaps": coverage_gaps,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="Godot app directory")
    parser.add_argument("--out", required=True, type=Path, help="new JSON report path")
    args = parser.parse_args(argv)
    if args.out.exists():
        parser.error(f"output already exists; choose a new file: {args.out}")
    try:
        inventory = build_inventory(args.app)
    except (OSError, NotADirectoryError) as error:
        parser.error(str(error))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(inventory, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
