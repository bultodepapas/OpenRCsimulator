#!/usr/bin/env python3
"""Build a read-only, review-oriented inventory of Godot texture imports.

This intentionally reads headers and text metadata only. It does not decode image
pixels, alter imports, or decide whether an import setting is correct.
"""

from __future__ import annotations

import argparse
import ast
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
GLB_MAX_JSON_CHUNK = 16 * 1024 * 1024
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


def _parse_glb(path: Path, relative_path: str) -> dict[str, Any]:
    result: dict[str, Any] = {
        "path": relative_path,
        "status": "unparsed",
        "embedded_image_count": None,
        "images": [],
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
            if declared_length < 20 or declared_length > file_size:
                result["reason"] = "invalid or truncated declared length"
                return result
            chunk_header = _read_exact(stream, 8)
            if chunk_header is None:
                result["reason"] = "missing JSON chunk"
                return result
            chunk_length, chunk_type = struct.unpack("<II", chunk_header)
            if chunk_type != GLB_JSON_CHUNK:
                result["reason"] = "first chunk is not JSON"
                return result
            if chunk_length > GLB_MAX_JSON_CHUNK:
                result["reason"] = "JSON chunk exceeds the bounded metadata limit"
                return result
            if stream.tell() + chunk_length > declared_length:
                result["reason"] = "JSON chunk exceeds declared GLB length"
                return result
            json_bytes = _read_exact(stream, chunk_length)
            if json_bytes is None:
                result["reason"] = "truncated JSON chunk"
                return result
        document = json.loads(json_bytes.decode("utf-8").rstrip("\x00 \t\r\n"))
    except (OSError, UnicodeError, json.JSONDecodeError, struct.error) as error:
        result["reason"] = f"GLB metadata read failed: {error}"
        return result
    if not isinstance(document, dict):
        result["reason"] = "GLB JSON root is not an object"
        return result
    images = document.get("images", [])
    if not isinstance(images, list):
        images = []
    embedded = []
    for index, image in enumerate(images):
        if not isinstance(image, dict):
            continue
        uri = image.get("uri")
        embedded_uri = isinstance(uri, str) and uri.startswith("data:")
        if "bufferView" not in image and not embedded_uri:
            continue
        image_metadata = {
            "index": index,
            "name": image.get("name"),
            "mime_type": image.get("mimeType"),
            "inspection": "UNINSPECTED",
        }
        if "bufferView" in image:
            image_metadata["buffer_view"] = image.get("bufferView")
        else:
            image_metadata["uri_kind"] = "data_uri"
        embedded.append(image_metadata)
    result.update(
        {
            "status": "parsed",
            "embedded_image_count": len(embedded),
            "images": embedded,
            "external_image_count": sum(
                1
                for image in images
                if isinstance(image, dict)
                and "uri" in image
                and "bufferView" not in image
                and not (isinstance(image.get("uri"), str) and image["uri"].startswith("data:"))
            ),
            "inspection": "JSON metadata only; embedded image payloads are UNINSPECTED",
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
        elif entry["embedded_image_count"]:
            coverage_gaps.append(
                {
                    "path": entry["path"],
                    "gap": "embedded GLB image payloads are UNINSPECTED; image headers and pixels were not decoded",
                    "embedded_image_count": entry["embedded_image_count"],
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
            "image_inspection": "PNG and JPEG headers only; no pixel decode or import mutation",
            "color_space_policy": "source_color and normal hints are reported from shaders; unspecified is not assumed to mean sRGB",
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
