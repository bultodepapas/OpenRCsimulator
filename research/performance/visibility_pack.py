#!/usr/bin/env python3
"""Validate synthetic visibility captures and package lossless APNG clips.

The packager checks capture integrity and pixel-preserving animation output. It
does not infer human visibility or report CPU/render performance.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import sys
import tempfile
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any, Sequence

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover - installation is environment-owned
    Image = None  # type: ignore[assignment,misc]
    _PIL_IMPORT_ERROR: ImportError | None = exc
else:
    _PIL_IMPORT_ERROR = None


ROUTE = "synthetic-visibility-motion"
SUMMARY_FORMAT = "openrc-visibility-apng-summary v1"
DEFAULT_FRAME_COUNT = 90
MAX_FRAME_COUNT = 600
MAX_FPS = 60
MAX_WIDTH = 1920
MAX_HEIGHT = 1080
TIME_TOLERANCE_S = 1e-9
SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-fA-F]{40}$")


def _is_int(value: Any) -> bool:
    return type(value) is int


def _is_number(value: Any) -> bool:
    return type(value) in (int, float) and math.isfinite(float(value))


def _reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON value {value} is forbidden")


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r} is forbidden")
        result[key] = value
    return result


def _finite_tree(value: Any, label: str = "manifest") -> list[str]:
    errors: list[str] = []
    if isinstance(value, float) and not math.isfinite(value):
        errors.append(f"{label} must be finite")
    elif isinstance(value, dict):
        for key, child in value.items():
            errors.extend(_finite_tree(child, f"{label}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            errors.extend(_finite_tree(child, f"{label}[{index}]"))
    return errors


def _read_manifest(root: Path) -> tuple[list[str], dict[str, Any] | None, bytes | None]:
    manifest_path = root / "manifest.json"
    try:
        raw = manifest_path.read_bytes()
    except OSError as exc:
        return [f"could not read manifest.json: {exc}"], None, None
    try:
        manifest = json.loads(
            raw.decode("utf-8"),
            parse_constant=_reject_constant,
            object_pairs_hook=_reject_duplicate_keys,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        return [f"manifest.json is invalid JSON: {exc}"], None, raw
    if not isinstance(manifest, dict):
        return ["manifest.json must contain a JSON object"], None, raw
    return [], manifest, raw


def _string_field(container: dict[str, Any], key: str, errors: list[str], label: str) -> str | None:
    value = container.get(key)
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{label}.{key} must be a non-empty string")
        return None
    return value


def _number_field(container: dict[str, Any], key: str, errors: list[str], label: str) -> float | None:
    value = container.get(key)
    if not _is_number(value):
        errors.append(f"{label}.{key} must be a finite number")
        return None
    return float(value)


def _number_array(
    container: dict[str, Any],
    key: str,
    size: int,
    errors: list[str],
    label: str,
) -> list[float] | None:
    value = container.get(key)
    if not isinstance(value, list):
        errors.append(f"{label}.{key} must be an array of {size} finite numbers")
        return None
    if len(value) != size:
        errors.append(f"{label}.{key} must contain exactly {size} numbers")
    parsed: list[float] = []
    valid = True
    for index, item in enumerate(value):
        if not _is_number(item):
            errors.append(f"{label}.{key}[{index}] must be a finite number")
            valid = False
        else:
            parsed.append(float(item))
    return parsed if valid and len(parsed) == size else None


def _validate_expected_frame_count(expected_frame_count: int | None) -> None:
    if expected_frame_count is None:
        return
    if not _is_int(expected_frame_count) or not 1 <= expected_frame_count <= MAX_FRAME_COUNT:
        raise ValueError(f"expected_frame_count must be an integer from 1 to {MAX_FRAME_COUNT}")


def _safe_png_path(root: Path, value: Any, errors: list[str], label: str) -> Path | None:
    if not isinstance(value, str) or not value:
        errors.append(f"{label}.png must be a non-empty relative path")
        return None
    if "\x00" in value or "\\" in value:
        errors.append(f"{label}.png must use a safe forward-slash relative path")
        return None

    posix_path = PurePosixPath(value)
    windows_path = PureWindowsPath(value)
    if (
        posix_path.is_absolute()
        or windows_path.is_absolute()
        or windows_path.drive
        or windows_path.root
        or any(part in ("", ".", "..") for part in value.split("/"))
        or any(part == ".." for part in windows_path.parts)
    ):
        errors.append(f"{label}.png must stay inside the capture folder")
        return None
    if posix_path.suffix.lower() != ".png":
        errors.append(f"{label}.png must refer to a PNG file")
        return None

    candidate = root.joinpath(*posix_path.parts)
    try:
        resolved_root = root.resolve(strict=True)
        resolved_candidate = candidate.resolve(strict=True)
        resolved_candidate.relative_to(resolved_root)
    except (OSError, ValueError):
        errors.append(f"{label}.png is missing or escapes the capture folder")
        return None
    if not resolved_candidate.is_file():
        errors.append(f"{label}.png is not a file")
        return None
    return resolved_candidate


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _load_png(path: Path) -> tuple[tuple[int, int], bytes, bool]:
    if Image is None:
        raise RuntimeError(f"Pillow is required: {_PIL_IMPORT_ERROR}")
    with Image.open(path) as image:
        if image.format != "PNG":
            raise ValueError("file is not encoded as PNG")
        if getattr(image, "n_frames", 1) != 1:
            raise ValueError("each capture frame must be a single-image PNG")
        image.load()
        rgba = image.convert("RGBA")
        try:
            pixels = rgba.tobytes()
            opaque = rgba.getchannel("A").getextrema() == (255, 255)
        finally:
            rgba.close()
        return image.size, pixels, opaque


def validate_capture(
    capture_dir: str | Path,
    expected_frame_count: int | None = DEFAULT_FRAME_COUNT,
) -> tuple[list[str], dict[str, Any] | None]:
    """Validate a schema-1 capture and return errors plus reusable file details.

    The default expected frame count is 90. Pass a different count for a
    deliberately sized capture, or ``None`` to use only the manifest count.
    A successful result includes the manifest, resolved source paths, hashes,
    and normalized pixel hashes for packaging.
    """
    _validate_expected_frame_count(expected_frame_count)
    root = Path(capture_dir)
    if not root.is_dir():
        return ["capture_dir must be an existing directory"], None
    try:
        root = root.resolve(strict=True)
    except OSError as exc:
        return [f"could not resolve capture directory: {exc}"], None

    errors, manifest, raw_manifest = _read_manifest(root)
    if manifest is None or raw_manifest is None:
        return errors, None
    errors.extend(_finite_tree(manifest))

    schema_version = manifest.get("schema_version")
    if not _is_int(schema_version) or schema_version != 1:
        errors.append("schema_version must be integer 1")

    fps_value = manifest.get("fps")
    fps: int | None = None
    if not _is_int(fps_value) or not 1 <= fps_value <= MAX_FPS:
        errors.append(f"fps must be an integer from 1 to {MAX_FPS}")
    else:
        fps = fps_value

    width_value = manifest.get("width")
    width: int | None = None
    if not _is_int(width_value) or not 1 <= width_value <= MAX_WIDTH:
        errors.append(f"width must be an integer from 1 to {MAX_WIDTH}")
    else:
        width = width_value

    height_value = manifest.get("height")
    height: int | None = None
    if not _is_int(height_value) or not 1 <= height_value <= MAX_HEIGHT:
        errors.append(f"height must be an integer from 1 to {MAX_HEIGHT}")
    else:
        height = height_value

    frame_count_value = manifest.get("frame_count")
    frame_count: int | None = None
    if not _is_int(frame_count_value) or not 1 <= frame_count_value <= MAX_FRAME_COUNT:
        errors.append(f"frame_count must be an integer from 1 to {MAX_FRAME_COUNT}")
    else:
        frame_count = frame_count_value
        if expected_frame_count is not None and frame_count != expected_frame_count:
            errors.append(f"frame_count must equal expected count {expected_frame_count}")

    source_commit = manifest.get("source_commit")
    if not isinstance(source_commit, str) or COMMIT_RE.fullmatch(source_commit) is None:
        errors.append("source_commit must be a 40-character hexadecimal commit id")

    case_id = _string_field(manifest, "case_id", errors, "manifest")
    aircraft_id = _string_field(manifest, "aircraft_id", errors, "manifest")
    if manifest.get("view") != "pilot":
        errors.append("view must equal 'pilot'")
    if type(manifest.get("auto_zoom")) is not bool:
        errors.append("auto_zoom must be a boolean")
    manual_zoom = _number_field(manifest, "manual_zoom", errors, "manifest")
    if manual_zoom is not None and manual_zoom <= 0:
        errors.append("manual_zoom must be positive")
    if manifest.get("route") != ROUTE:
        errors.append(f"route must equal {ROUTE!r}")

    frames = manifest.get("frames")
    if not isinstance(frames, list):
        errors.append("frames must be an array")
        frames = []
    if frame_count is not None and len(frames) != frame_count:
        errors.append("frames array length must equal frame_count")

    frame_paths: list[Path] = []
    source_frame_hashes: list[str] = []
    pixel_hashes: list[str] = []
    first_pixel_data: bytes | None = None
    pixel_motion = False
    requires_alpha = False
    path_keys: set[Path] = set()
    for index, frame in enumerate(frames):
        label = f"frames[{index}]"
        if not isinstance(frame, dict):
            errors.append(f"{label} must be an object")
            continue

        frame_index = frame.get("index")
        if not _is_int(frame_index) or frame_index != index:
            errors.append(f"{label}.index must equal sequential index {index}")

        time_s = _number_field(frame, "time_s", errors, label)
        if fps is not None and time_s is not None and not math.isclose(
            time_s, index / fps, rel_tol=0.0, abs_tol=TIME_TOLERANCE_S
        ):
            errors.append(f"{label}.time_s must equal index / fps")

        png_path = _safe_png_path(root, frame.get("png"), errors, label)
        if png_path is not None:
            if png_path in path_keys:
                errors.append(f"{label}.png duplicates an earlier frame path")
            path_keys.add(png_path)

        declared_hash = frame.get("sha256")
        if not isinstance(declared_hash, str) or SHA256_RE.fullmatch(declared_hash) is None:
            errors.append(f"{label}.sha256 must be a 64-character hexadecimal digest")
        elif png_path is not None:
            try:
                actual_hash = _sha256_file(png_path)
                if actual_hash.lower() != declared_hash.lower():
                    errors.append(f"{label}.sha256 does not match the PNG file")
                source_frame_hashes.append(actual_hash)
            except OSError as exc:
                errors.append(f"{label}.png could not be hashed: {exc}")

        distance_m = _number_field(frame, "distance_m", errors, label)
        if distance_m is not None and distance_m <= 0:
            errors.append(f"{label}.distance_m must be positive")
        fov_deg = _number_field(frame, "fov_deg", errors, label)
        if fov_deg is not None and not 0 < fov_deg < 180:
            errors.append(f"{label}.fov_deg must be greater than 0 and less than 180")
        projected_span_px = _number_field(frame, "projected_span_px", errors, label)
        if projected_span_px is not None and projected_span_px <= 0:
            errors.append(f"{label}.projected_span_px must be positive")
        for key in ("yaw_deg", "pitch_deg", "roll_deg"):
            _number_field(frame, key, errors, label)
        _number_array(frame, "position_ned", 3, errors, label)
        cg_screen_px = _number_array(frame, "cg_screen_px", 2, errors, label)
        if cg_screen_px is not None and width is not None and height is not None:
            cg_x, cg_y = cg_screen_px
            if not (0 <= cg_x < width and 0 <= cg_y < height):
                errors.append(f"{label}.cg_screen_px must be inside image bounds [0, width) x [0, height)")
        _number_array(frame, "camera_transform", 12, errors, label)
        if "bbox_px" in frame:
            bbox_px = _number_array(frame, "bbox_px", 4, errors, label)
            if bbox_px is not None and width is not None and height is not None:
                bbox_x, bbox_y, bbox_width, bbox_height = bbox_px
                if bbox_width <= 0 or bbox_height <= 0:
                    errors.append(f"{label}.bbox_px width and height must be positive")
                elif (
                    bbox_x < -1e-3
                    or bbox_y < -1e-3
                    or bbox_x + bbox_width > width + 1e-3
                    or bbox_y + bbox_height > height + 1e-3
                ):
                    errors.append(f"{label}.bbox_px must be inside image bounds within 0.001 px")

        if png_path is not None and width is not None and height is not None:
            try:
                image_size, pixels, opaque = _load_png(png_path)
                if image_size != (width, height):
                    errors.append(f"{label}.png dimensions {image_size} do not match manifest {(width, height)}")
                frame_paths.append(png_path)
                pixel_hashes.append(hashlib.sha256(pixels).hexdigest())
                if first_pixel_data is None:
                    first_pixel_data = pixels
                elif pixels != first_pixel_data:
                    pixel_motion = True
                requires_alpha = requires_alpha or not opaque
            except (OSError, ValueError, RuntimeError) as exc:
                errors.append(f"{label}.png could not be decoded: {exc}")

    if pixel_hashes and not pixel_motion:
        errors.append("capture has no actual pixel motion across frames")
    if len(pixel_hashes) != len(frames):
        # Detailed per-frame errors above explain the failed image entries.
        pass

    if errors:
        return errors, None

    assert fps is not None and width is not None and height is not None and frame_count is not None
    assert case_id is not None and aircraft_id is not None
    return [], {
        "manifest": manifest,
        "manifest_sha256": hashlib.sha256(raw_manifest).hexdigest(),
        "frame_paths": frame_paths,
        "source_frame_sha256": source_frame_hashes,
        "pixel_sha256": pixel_hashes,
        "requires_alpha": requires_alpha,
        "fps": fps,
        "width": width,
        "height": height,
        "frame_count": frame_count,
    }


def _rounded_millisecond_boundary(frame_index: int, fps: int) -> int:
    return round(frame_index * 1000 / fps)


def _frame_durations_ms(frame_count: int, fps: int) -> list[int]:
    return [
        _rounded_millisecond_boundary(index + 1, fps) - _rounded_millisecond_boundary(index, fps)
        for index in range(frame_count)
    ]


def _verify_apng(
    clip_path: Path,
    frame_paths: list[Path],
    durations_ms: list[int],
) -> list[str]:
    if Image is None:
        return [f"Pillow is required: {_PIL_IMPORT_ERROR}"]
    errors: list[str] = []
    expected_count = len(frame_paths)
    try:
        with Image.open(clip_path) as clip:
            if clip.format != "PNG" or not getattr(clip, "is_animated", False):
                return ["packaged clip is not an animated PNG"]
            actual_count = getattr(clip, "n_frames", 1)
            if actual_count != expected_count:
                errors.append(
                    f"APNG frame count is {actual_count}, expected {expected_count}; "
                    "Pillow may have merged or dropped input frames"
                )
            if actual_count == expected_count:
                actual_durations: list[float] = []
                for index, source_path in enumerate(frame_paths):
                    clip.seek(index)
                    actual_pixels = clip.convert("RGBA").tobytes()
                    with Image.open(source_path) as source:
                        source.load()
                        expected_pixels = source.convert("RGBA").tobytes()
                    if actual_pixels != expected_pixels:
                        errors.append(f"APNG frame {index} pixels differ from the input PNG")
                    duration_value = clip.info.get("duration")
                    if not _is_number(duration_value):
                        errors.append(f"APNG frame {index} has no finite duration")
                    else:
                        actual_duration = float(duration_value)
                        actual_durations.append(actual_duration)
                        if not math.isclose(actual_duration, durations_ms[index], rel_tol=0.0, abs_tol=1e-6):
                            errors.append(
                                f"APNG frame {index} duration is {actual_duration} ms, "
                                f"expected {durations_ms[index]} ms"
                            )
                expected_total = sum(durations_ms)
                actual_total = sum(actual_durations)
                if len(actual_durations) == expected_count and not math.isclose(
                    actual_total, expected_total, rel_tol=0.0, abs_tol=1e-6
                ):
                    errors.append(f"APNG duration sum is {actual_total} ms, expected {expected_total} ms")
    except (OSError, ValueError) as exc:
        errors.append(f"packaged APNG could not be decoded: {exc}")
    return errors


def _range(values: list[float]) -> dict[str, float]:
    return {"min": min(values), "max": max(values)}


def package_capture(
    capture_dir: str | Path,
    output_dir: str | Path,
    expected_frame_count: int | None = DEFAULT_FRAME_COUNT,
) -> dict[str, Any]:
    """Validate a capture and write a blinded, verified ``clip.png`` package.

    The destination directory must not exist. The returned dictionary is also
    written as ``summary.json`` inside the package.
    """
    _validate_expected_frame_count(expected_frame_count)
    output = Path(output_dir).expanduser().absolute()
    if output.exists() or output.is_symlink():
        raise ValueError(f"output directory already exists: {output}")

    errors, details = validate_capture(capture_dir, expected_frame_count)
    if errors or details is None:
        joined = "\n".join(f"- {error}" for error in errors)
        raise ValueError(f"capture validation failed:\n{joined}")

    source_root = Path(capture_dir).resolve(strict=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    resolved_parent = output.parent.resolve(strict=True)
    resolved_output = resolved_parent / output.name
    try:
        resolved_output.relative_to(source_root)
    except ValueError:
        pass
    else:
        raise ValueError("output directory must be outside the capture folder")

    if Image is None:
        raise RuntimeError(f"Pillow is required: {_PIL_IMPORT_ERROR}")

    manifest = details["manifest"]
    frame_count = details["frame_count"]
    fps = details["fps"]
    durations_ms = _frame_durations_ms(frame_count, fps)
    temporary_path = Path(tempfile.mkdtemp(prefix=f".{output.name}.tmp-", dir=resolved_parent))
    try:
        images = []
        try:
            for frame_path in details["frame_paths"]:
                with Image.open(frame_path) as source:
                    source.load()
                    images.append(source.convert("RGBA" if details["requires_alpha"] else "RGB"))

            clip_path = temporary_path / "clip.png"
            # Alternating NONE/PREVIOUS disposal prevents Pillow from merging
            # adjacent identical frames. SOURCE blend and the full logical
            # canvas preserve transparent and opaque pixels exactly.
            disposal = [0 if index % 2 == 0 else 2 for index in range(frame_count)]
            images[0].save(
                clip_path,
                format="PNG",
                save_all=True,
                append_images=images[1:],
                duration=durations_ms,
                loop=0,
                disposal=disposal,
                blend=[0] * frame_count,
                optimize=False,
            )
        finally:
            for image in images:
                image.close()

        verification_errors = _verify_apng(clip_path, details["frame_paths"], durations_ms)
        if verification_errors:
            raise ValueError("APNG verification failed:\n" + "\n".join(f"- {error}" for error in verification_errors))

        frame_hashes: list[str] = []
        for frame_path in details["frame_paths"]:
            _size, pixels, _opaque = _load_png(frame_path)
            frame_hashes.append(hashlib.sha256(pixels).hexdigest())
        fov = [float(frame["fov_deg"]) for frame in manifest["frames"]]
        distance = [float(frame["distance_m"]) for frame in manifest["frames"]]
        projected_span = [float(frame["projected_span_px"]) for frame in manifest["frames"]]
        summary: dict[str, Any] = {
            "format": SUMMARY_FORMAT,
            "clip": "clip.png",
            "input_manifest_sha256": details["manifest_sha256"],
            "output_sha256": _sha256_file(clip_path),
            "frame_count": frame_count,
            "fps": fps,
            "width": details["width"],
            "height": details["height"],
            "duration_ms": sum(durations_ms),
            "frame_hashes": frame_hashes,
            "source_frame_sha256": details["source_frame_sha256"],
            "ranges": {
                "fov_deg": _range(fov),
                "distance_m": _range(distance),
                "projected_span_px": _range(projected_span),
            },
            "scope": "capture integrity and lossless packaging; no CPU or render performance result",
        }
        (temporary_path / "summary.json").write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if resolved_output.exists() or resolved_output.is_symlink():
            raise ValueError(f"output directory already exists: {resolved_output}")
        temporary_path.rename(resolved_output)
        return summary
    except Exception:
        shutil.rmtree(temporary_path, ignore_errors=True)
        raise


def _positive_count(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be an integer") from exc
    if not 1 <= parsed <= MAX_FRAME_COUNT:
        raise argparse.ArgumentTypeError(f"must be from 1 to {MAX_FRAME_COUNT}")
    return parsed


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="capture folder containing manifest.json")
    parser.add_argument("--out", required=True, type=Path, help="new package directory to create")
    parser.add_argument(
        "--frame-count",
        type=_positive_count,
        default=DEFAULT_FRAME_COUNT,
        help=f"expected frame count (default: {DEFAULT_FRAME_COUNT})",
    )
    args = parser.parse_args(argv)
    try:
        summary = package_capture(args.input, args.out, args.frame_count)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
