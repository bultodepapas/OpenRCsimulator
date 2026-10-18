#!/usr/bin/env python3
"""Reduce OpenRC grass quality capture/profile manifests using only Python's stdlib."""

from __future__ import annotations

import argparse
import json
import math
import statistics
import struct
import sys
import zlib
from pathlib import Path
from typing import Any


FORMAT = "openrc-grass-quality v1"
CAPTURE_CASES = ("pilot_runway_edge", "low_near_grass", "overhead", "zoom_far")
WIND_GROUPS = ("calm", "wind_x_positive", "wind_x_negative")


class EvidenceError(Exception):
    """An input manifest or image cannot support the requested reduction."""


def read_manifest(path: Path) -> dict[str, Any]:
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EvidenceError(f"cannot read manifest {path}: {error}") from error
    if not isinstance(manifest, dict) or manifest.get("format") != FORMAT:
        raise EvidenceError(f"{path} is not a {FORMAT} manifest")
    manifest["_manifest_path"] = str(path.resolve())
    manifest["_manifest_dir"] = str(path.resolve().parent)
    return manifest


def manifest_image_path(manifest: dict[str, Any], capture: dict[str, Any]) -> Path:
    image_name = capture.get("image")
    if not isinstance(image_name, str) or not image_name:
        raise EvidenceError(f"capture {capture.get('id')} has no image path")
    return Path(manifest["_manifest_dir"]) / image_name


def decode_png(path: Path) -> tuple[int, int, bytes]:
    """Decode the 8-bit PNG formats Godot emits into tightly packed RGBA bytes."""
    try:
        data = path.read_bytes()
    except OSError as error:
        raise EvidenceError(f"cannot read image {path}: {error}") from error
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise EvidenceError(f"{path} is not a PNG image")

    position = 8
    width = height = bit_depth = color_type = interlace = None
    compressed = bytearray()
    palette: bytes | None = None
    transparency: bytes | None = None
    while position + 12 <= len(data):
        chunk_length = struct.unpack_from(">I", data, position)[0]
        position += 4
        chunk_type = data[position : position + 4]
        position += 4
        chunk_end = position + chunk_length
        if chunk_end + 4 > len(data):
            raise EvidenceError(f"{path} contains a truncated PNG chunk")
        chunk_data = data[position:chunk_end]
        expected_crc = struct.unpack_from(">I", data, chunk_end)[0]
        actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        if expected_crc != actual_crc:
            raise EvidenceError(f"{path} has a PNG checksum error in {chunk_type!r}")
        position = chunk_end + 4
        if chunk_type == b"IHDR":
            if len(chunk_data) != 13:
                raise EvidenceError(f"{path} has an invalid PNG header")
            width, height, bit_depth, color_type, _compression, _filter, interlace = struct.unpack(
                ">IIBBBBB", chunk_data
            )
        elif chunk_type == b"PLTE":
            palette = bytes(chunk_data)
        elif chunk_type == b"tRNS":
            transparency = bytes(chunk_data)
        elif chunk_type == b"IDAT":
            compressed.extend(chunk_data)
        elif chunk_type == b"IEND":
            break

    if width is None or height is None or width <= 0 or height <= 0:
        raise EvidenceError(f"{path} has no valid PNG dimensions")
    if bit_depth != 8 or interlace != 0:
        raise EvidenceError(f"{path} must be 8-bit, non-interlaced PNG; got depth={bit_depth}, interlace={interlace}")
    channels_by_type = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
    channels = channels_by_type.get(color_type)
    if channels is None:
        raise EvidenceError(f"{path} uses unsupported PNG color type {color_type}")
    if color_type == 3 and (palette is None or len(palette) % 3 != 0):
        raise EvidenceError(f"{path} is indexed PNG without a valid palette")

    row_bytes = width * channels
    try:
        filtered = zlib.decompress(compressed)
    except zlib.error as error:
        raise EvidenceError(f"cannot decompress PNG pixels from {path}: {error}") from error
    if len(filtered) != height * (row_bytes + 1):
        raise EvidenceError(f"{path} has a PNG data length inconsistent with its dimensions")

    rows: list[bytearray] = []
    source_offset = 0
    previous = bytearray(row_bytes)
    for _row_index in range(height):
        filter_type = filtered[source_offset]
        source_offset += 1
        scanline = bytearray(filtered[source_offset : source_offset + row_bytes])
        source_offset += row_bytes
        if filter_type > 4:
            raise EvidenceError(f"{path} uses unknown PNG row filter {filter_type}")
        for index in range(row_bytes):
            left = scanline[index - channels] if index >= channels else 0
            above = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            elif filter_type == 4:
                predictor = paeth_predictor(left, above, upper_left)
            else:
                predictor = 0
            scanline[index] = (scanline[index] + predictor) & 0xFF
        rows.append(scanline)
        previous = scanline

    rgba = bytearray(width * height * 4)
    output_offset = 0
    for row in rows:
        if color_type == 6:
            rgba[output_offset : output_offset + width * 4] = row
            output_offset += width * 4
        elif color_type == 2:
            for index in range(0, len(row), 3):
                rgba[output_offset : output_offset + 4] = bytes((row[index], row[index + 1], row[index + 2], 255))
                output_offset += 4
        elif color_type == 0:
            for gray in row:
                rgba[output_offset : output_offset + 4] = bytes((gray, gray, gray, 255))
                output_offset += 4
        elif color_type == 4:
            for index in range(0, len(row), 2):
                gray, alpha = row[index], row[index + 1]
                rgba[output_offset : output_offset + 4] = bytes((gray, gray, gray, alpha))
                output_offset += 4
        else:  # Indexed color type 3.
            assert palette is not None
            for palette_index in row:
                color_offset = palette_index * 3
                if color_offset + 3 > len(palette):
                    raise EvidenceError(f"{path} refers to a missing palette entry")
                alpha = transparency[palette_index] if transparency is not None and palette_index < len(transparency) else 255
                rgba[output_offset : output_offset + 4] = bytes(
                    (palette[color_offset], palette[color_offset + 1], palette[color_offset + 2], alpha)
                )
                output_offset += 4
    return width, height, bytes(rgba)


def paeth_predictor(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    left_distance = abs(estimate - left)
    above_distance = abs(estimate - above)
    diagonal_distance = abs(estimate - upper_left)
    if left_distance <= above_distance and left_distance <= diagonal_distance:
        return left
    if above_distance <= diagonal_distance:
        return above
    return upper_left


def compare_pixels(first: tuple[int, int, bytes], second: tuple[int, int, bytes]) -> dict[str, Any]:
    width_a, height_a, pixels_a = first
    width_b, height_b, pixels_b = second
    if (width_a, height_a) != (width_b, height_b):
        raise EvidenceError(f"image sizes differ: {width_a}x{height_a} versus {width_b}x{height_b}")
    histogram = [0] * 256
    sum_error = 0
    max_error = 0
    changed_pixels = 0
    pixel_count = width_a * height_a
    for offset in range(0, len(pixels_a), 4):
        changed = False
        for channel in range(4):
            error = abs(pixels_a[offset + channel] - pixels_b[offset + channel])
            histogram[error] += 1
            sum_error += error
            max_error = max(max_error, error)
            changed = changed or error != 0
        if changed:
            changed_pixels += 1
    channel_count = len(pixels_a)
    rank_95 = max(1, math.ceil(channel_count * 0.95))
    running = 0
    p95_error = 0
    for error, count in enumerate(histogram):
        running += count
        if running >= rank_95:
            p95_error = error
            break
    return {
        "width": width_a,
        "height": height_a,
        "exact_pixels_match": changed_pixels == 0,
        "mean_absolute_channel_error_0_255": sum_error / channel_count if channel_count else 0.0,
        "p95_absolute_channel_error_0_255": p95_error,
        "max_absolute_channel_error_0_255": max_error,
        "changed_pixel_fraction": changed_pixels / pixel_count if pixel_count else 0.0,
        "changed_pixels": changed_pixels,
        "pixel_count": pixel_count,
    }


def capture_map(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    captures = manifest.get("captures")
    if not isinstance(captures, list):
        raise EvidenceError(f"{manifest['_manifest_path']} has no capture list")
    result: dict[str, dict[str, Any]] = {}
    for capture in captures:
        if not isinstance(capture, dict) or not isinstance(capture.get("id"), str):
            raise EvidenceError(f"{manifest['_manifest_path']} contains an invalid capture record")
        if capture["id"] in result:
            raise EvidenceError(f"duplicate capture id {capture['id']} in {manifest['_manifest_path']}")
        result[capture["id"]] = capture
    return result


def verify_repeat_images(manifest: dict[str, Any], captures: dict[str, dict[str, Any]]) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    for group in WIND_GROUPS:
        comparisons = [(f"clock_{group}_t0", f"clock_{group}_t1024")]
        if group == "calm":
            comparisons.extend(
                [
                    ("clock_calm_t0", "clock_calm_t1"),
                    ("clock_calm_t0", "clock_calm_t1_repeat"),
                ]
            )
        else:
            comparisons.append((f"clock_{group}_t1", f"clock_{group}_t1_repeat"))
        for first_id, second_id in comparisons:
            if first_id not in captures or second_id not in captures:
                checks.append({"first": first_id, "second": second_id, "exact_pixels_match": False, "error": "required repeat case is missing"})
                continue
            first_record = captures[first_id]
            second_record = captures[second_id]
            first_pixels = decode_png(manifest_image_path(manifest, first_record))
            second_pixels = decode_png(manifest_image_path(manifest, second_record))
            metrics = compare_pixels(first_pixels, second_pixels)
            checks.append(
                {
                    "first": first_id,
                    "second": second_id,
                    "first_image_sha256": first_record.get("image_sha256"),
                    "second_image_sha256": second_record.get("image_sha256"),
                    **metrics,
                }
            )
    return {
        "checks": checks,
        "all_exact_pixels_match": bool(checks) and all(item.get("exact_pixels_match") is True for item in checks),
    }


def capture_input_comparison(baseline: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    keys = (
        "field_id",
        "field_sha256",
        "seed",
        "quality_requested",
        "quality_actual",
        "renderer_method",
        "renderer_driver",
        "renderer_adapter",
        "viewport",
        "viewport_msaa_3d",
    )
    differences = {
        key: {"baseline": baseline.get(key), "candidate": candidate.get(key)}
        for key in keys
        if baseline.get(key) != candidate.get(key)
    }
    return {"matched": not differences, "differences": differences}


def run_capture_compare(args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    baseline = read_manifest(Path(args.baseline))
    candidate = read_manifest(Path(args.candidate))
    if baseline.get("mode") != "capture" or candidate.get("mode") != "capture":
        raise EvidenceError("capture comparison requires two capture-mode manifests")
    baseline_captures = capture_map(baseline)
    candidate_captures = capture_map(candidate)
    missing_candidate = sorted(set(baseline_captures) - set(candidate_captures))
    missing_baseline = sorted(set(candidate_captures) - set(baseline_captures))
    if missing_candidate or missing_baseline:
        raise EvidenceError(f"capture IDs differ; candidate missing={missing_candidate}, baseline missing={missing_baseline}")
    required_missing = [case for case in CAPTURE_CASES if case not in baseline_captures]
    expected_motion = [f"motion_{wind}_{step:02d}" for wind in WIND_GROUPS for step in range(12)]
    required_missing.extend(case for case in expected_motion if case not in baseline_captures)
    if required_missing:
        raise EvidenceError(f"capture set is incomplete: missing {required_missing}")

    image_comparisons = []
    for case_id in sorted(baseline_captures):
        baseline_record = baseline_captures[case_id]
        candidate_record = candidate_captures[case_id]
        baseline_pixels = decode_png(manifest_image_path(baseline, baseline_record))
        candidate_pixels = decode_png(manifest_image_path(candidate, candidate_record))
        image_comparisons.append(
            {
                "id": case_id,
                "baseline_image_sha256": baseline_record.get("image_sha256"),
                "candidate_image_sha256": candidate_record.get("image_sha256"),
                **compare_pixels(baseline_pixels, candidate_pixels),
            }
        )

    baseline_identity = baseline.get("scene_identity", {})
    candidate_identity = candidate.get("scene_identity", {})
    geometry_match = baseline_identity.get("mesh_hash") == candidate_identity.get("mesh_hash")
    instances_match = baseline_identity.get("instance_hash") == candidate_identity.get("instance_hash")
    baseline_repeats = verify_repeat_images(baseline, baseline_captures)
    candidate_repeats = verify_repeat_images(candidate, candidate_captures)
    material_only_geometry_preserved = geometry_match and instances_match
    report = {
        "format": "openrc-grass-quality-comparison v1",
        "comparison_kind": "paired capture manifests",
        "baseline_manifest": baseline["_manifest_path"],
        "candidate_manifest": candidate["_manifest_path"],
        "capture_inputs": capture_input_comparison(baseline, candidate),
        "ground_probe": {
            "baseline": baseline.get("ground_probe"),
            "candidate": candidate.get("ground_probe"),
            "baseline_scope": baseline.get("ground_probe_scope"),
            "candidate_scope": candidate.get("ground_probe_scope"),
        },
        "geometry_comparison": {
            "baseline_mesh_hash": baseline_identity.get("mesh_hash"),
            "candidate_mesh_hash": candidate_identity.get("mesh_hash"),
            "mesh_hashes_match": geometry_match,
            "baseline_instance_hash": baseline_identity.get("instance_hash"),
            "candidate_instance_hash": candidate_identity.get("instance_hash"),
            "instance_hashes_match": instances_match,
            "material_only_geometry_preserved": material_only_geometry_preserved,
            "baseline_material_hash": baseline_identity.get("material_hash"),
            "candidate_material_hash": candidate_identity.get("material_hash"),
        },
        "repeat_image_verification": {"baseline": baseline_repeats, "candidate": candidate_repeats},
        "image_differences": image_comparisons,
        "visual_assessment": "owner review is required; image metrics do not establish appearance acceptance",
        "overall_qualification": "not established by this reducer; complete-session and target-hardware gates remain separate",
    }
    checks_ok = (
        report["capture_inputs"]["matched"]
        and baseline_repeats["all_exact_pixels_match"]
        and candidate_repeats["all_exact_pixels_match"]
    )
    if args.material_only:
        checks_ok = checks_ok and material_only_geometry_preserved
    return report, 0 if checks_ok else 1


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, math.ceil(fraction * len(ordered)) - 1)
    return ordered[index]


def profile_metrics(manifest: dict[str, Any]) -> dict[str, Any]:
    profile = manifest.get("profile")
    if not isinstance(profile, dict):
        raise EvidenceError(f"{manifest['_manifest_path']} has no profile record")
    samples = profile.get("samples")
    if not isinstance(samples, list) or not samples:
        raise EvidenceError(f"{manifest['_manifest_path']} has no raw profile samples")
    columns = ("wall_interval_ms", "viewport_cpu_ms", "viewport_gpu_ms")
    metrics: dict[str, Any] = {}
    for column in columns:
        values: list[float] = []
        for sample in samples:
            if not isinstance(sample, dict):
                continue
            value = sample.get(column)
            if isinstance(value, (int, float)) and math.isfinite(float(value)) and float(value) >= 0:
                values.append(float(value))
        available = bool(values)
        if column == "viewport_gpu_ms" and values and all(value == 0.0 for value in values):
            available = False
        metrics[column] = {
            "available": available,
            "sample_count": len(values) if available else 0,
            "p50": percentile(values, 0.50) if available else None,
            "p95": percentile(values, 0.95) if available else None,
            "p99": percentile(values, 0.99) if available else None,
            "unit": "ms per frame interval" if column == "wall_interval_ms" else "ms per viewport frame",
        }
    return {
        "manifest": manifest["_manifest_path"],
        "variant": manifest.get("variant"),
        "pair": manifest.get("pair"),
        "quality": manifest.get("quality_actual"),
        "ground_probe": manifest.get("ground_probe"),
        "field_sha256": manifest.get("field_sha256"),
        "renderer_adapter": manifest.get("renderer_adapter"),
        "view_id": profile.get("view_id"),
        "requested_warmup_s": profile.get("requested_warmup_s"),
        "actual_warmup_s": profile.get("actual_warmup_s"),
        "requested_sample_duration_s": profile.get("requested_sample_duration_s"),
        "actual_sample_duration_s": profile.get("actual_sample_duration_s"),
        "sample_count": len(samples),
        "qualification_minimum_met": bool(profile.get("qualification_minimum_met", False)),
        "metrics": metrics,
    }


def run_profile_compare(args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    paths = [Path(path) for path in args.manifests]
    if len(paths) != 10:
        raise EvidenceError("profile reduction requires 10 manifests in baseline,candidate order for five alternating pairs")
    manifests = [read_manifest(path) for path in paths]
    expected_labels = [label for _ in range(5) for label in ("baseline", "candidate")]
    reduced: list[dict[str, Any]] = []
    for index, (manifest, label) in enumerate(zip(manifests, expected_labels)):
        if manifest.get("mode") != "profile":
            raise EvidenceError(f"{manifest['_manifest_path']} is not a profile manifest")
        if manifest.get("variant") != label:
            raise EvidenceError(f"manifest {index + 1} must be {label}; found {manifest.get('variant')!r}")
        if int(manifest.get("pair", 0)) != index // 2 + 1:
            raise EvidenceError(f"manifest {index + 1} has a pair number out of alternating order")
        reduced.append(profile_metrics(manifest))

    pair_reports = []
    compatibility_keys = ("quality", "ground_probe", "field_sha256", "renderer_adapter", "view_id")
    mismatches: list[dict[str, Any]] = []
    for pair_index in range(5):
        baseline = reduced[pair_index * 2]
        candidate = reduced[pair_index * 2 + 1]
        pair_mismatch = {
            key: {"baseline": baseline.get(key), "candidate": candidate.get(key)}
            for key in compatibility_keys
            if baseline.get(key) != candidate.get(key)
        }
        if pair_mismatch:
            mismatches.append({"pair": pair_index + 1, "differences": pair_mismatch})
        deltas: dict[str, Any] = {}
        for metric_name in ("wall_interval_ms", "viewport_cpu_ms", "viewport_gpu_ms"):
            deltas[metric_name] = {}
            for quantile in ("p50", "p95", "p99"):
                before = baseline["metrics"][metric_name][quantile]
                after = candidate["metrics"][metric_name][quantile]
                deltas[metric_name][quantile] = after - before if before is not None and after is not None else None
        pair_reports.append(
            {
                "pair": pair_index + 1,
                "baseline": baseline,
                "candidate": candidate,
                "candidate_minus_baseline_ms": deltas,
            }
        )

    delta_summary: dict[str, Any] = {}
    for metric_name in ("wall_interval_ms", "viewport_cpu_ms", "viewport_gpu_ms"):
        delta_summary[metric_name] = {}
        for quantile in ("p50", "p95", "p99"):
            values = [
                pair["candidate_minus_baseline_ms"][metric_name][quantile]
                for pair in pair_reports
                if pair["candidate_minus_baseline_ms"][metric_name][quantile] is not None
            ]
            delta_summary[metric_name][quantile] = {
                "available_pairs": len(values),
                "median_pair_delta_ms": statistics.median(values) if values else None,
                "min_pair_delta_ms": min(values) if values else None,
                "max_pair_delta_ms": max(values) if values else None,
            }
    minimums_met = all(run["qualification_minimum_met"] for run in reduced)
    report = {
        "format": "openrc-grass-quality-comparison v1",
        "comparison_kind": "five alternating baseline/candidate profile pairs",
        "paired_protocol_order": [manifest.get("variant") for manifest in manifests],
        "profile_input_mismatches": mismatches,
        "runs": reduced,
        "pairs": pair_reports,
        "candidate_minus_baseline_delta_summary": delta_summary,
        "qualification_minimum_met_for_all_runs": minimums_met,
        "qualification_statement": "profile-only comparison; full-session, target-hardware, input-tape and total visual-budget qualification are not established",
    }
    complete = not mismatches and minimums_met
    return report, 0 if complete else 1


def write_report(path: Path, report: dict[str, Any]) -> None:
    path = path.resolve()
    if path.exists():
        raise EvidenceError(f"refusing to overwrite existing report: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    capture = subparsers.add_parser("capture", help="compare one paired image capture set")
    capture.add_argument("baseline", help="baseline manifest.json")
    capture.add_argument("candidate", help="candidate manifest.json")
    capture.add_argument("--out", required=True, help="new JSON report path")
    capture.add_argument("--material-only", action="store_true", help="return failure if mesh or instance hashes changed")
    profile = subparsers.add_parser("profile", help="reduce ten alternating profile manifests")
    profile.add_argument("manifests", nargs="+", help="five baseline,candidate manifest pairs in run order")
    profile.add_argument("--out", required=True, help="new JSON report path")
    return parser


def main() -> int:
    args = make_parser().parse_args()
    try:
        if args.command == "capture":
            report, exit_code = run_capture_compare(args)
        else:
            report, exit_code = run_profile_compare(args)
        write_report(Path(args.out), report)
        print(json.dumps({"report": str(Path(args.out).resolve()), "exit_code": exit_code}, indent=2))
        return exit_code
    except EvidenceError as error:
        print(f"quality_compare: {error}", file=sys.stderr)
        return 2
    except (OSError, TypeError, ValueError, KeyError, IndexError) as error:
        print(f"quality_compare: invalid evidence: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
