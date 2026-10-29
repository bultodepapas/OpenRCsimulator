#!/usr/bin/env python3
"""Create a bounded offline diagnosis of one native frame-time report and log.

This report summarizes observations. It does not qualify active flight, identify
causality, or establish GPU hardware performance.
"""

from __future__ import annotations

import argparse
from array import array
import hashlib
import heapq
import json
import math
import re
import sys
import tempfile
from pathlib import Path
from typing import Any, Sequence


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

try:
    from .native_summary import STREAM_FORMAT, STREAM_MAX_BYTES, _hydrate_stream_report, validate_native_report
except ImportError:  # Direct execution puts this directory, not its parent, on sys.path.
    from native_summary import STREAM_FORMAT, STREAM_MAX_BYTES, _hydrate_stream_report, validate_native_report

from tools.godot.run_checked import inspect_log


FORMAT = "openrc-frame-diagnosis v1"
DEFAULT_BUDGET_MS = 16.667
DEFAULT_TOP = 10
DEFAULT_MAX_INPUT_BYTES = 64 * 1024 * 1024
MAX_TOP = 1000
MAX_INPUT_BYTES = 1024 * 1024 * 1024
COPY_CHUNK_BYTES = 64 * 1024

CONTEXT_METRICS = (
    "process_time_s",
    "physics_process_time_s",
    "physics_step_usec",
    "draw_calls",
    "primitives",
    "object_count",
    "node_count",
    "physics_3d_active_objects",
    "physics_3d_collision_pairs",
    "observer_poll_usec",
    "invalid_value_count",
    "render_cpu_ms",
    "frame_setup_cpu_ms",
)
MEMORY_METRICS = (
    "memory_static_bytes",
    "render_video_memory_bytes",
    "render_texture_memory_bytes",
    "render_buffer_memory_bytes",
    "resource_count",
    "orphan_node_count",
)
IDENTITY_FIELDS = (
    "case_id",
    "route",
    "aircraft_id",
    "preset",
    "backend",
    "adapter",
    "api",
    "godot",
    "os",
    "window",
    "vsync",
    "render_settings",
)
GENERAL_HINTS = [
    "Frame-budget observations describe wall intervals and do not qualify active flight.",
    "When present, render_cpu_ms and render_gpu_ms are root-viewport context. Render timing may be delayed or describe a previous render frame, so same-index values do not prove the cause of a wall-frame hitch.",
    "A render_gpu_ms value of zero is unavailable_or_zero, not evidence of zero GPU cost.",
    "Observer-reported invalid numeric readings are preserved as an explicit measurement issue; sanitized zero values must not be treated as valid measurements.",
    "Memory start/end/max deltas describe this sample only and do not establish a memory leak.",
    "This report does not establish GPU hardware acceptance or causal attribution.",
    "Optional source frame_diagnostics metadata is preserved separately; observer polls and capability scopes are not counted as measured sample frames.",
]


class InputReadError(ValueError):
    def __init__(self, message: str, *, bytes_read: int = 0):
        super().__init__(message)
        self.bytes_read = bytes_read


class InputLimitError(InputReadError):
    """Raised when the combined report, stream and log exceed the byte cap."""


class ReportReadError(InputReadError):
    """Malformed report carrying the bytes consumed before parsing failed."""

    def __init__(self, message: str, *, bytes_read: int):
        super().__init__(message)
        self.bytes_read = bytes_read


def _reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON value {value} is forbidden")


def parse_byte_limit(raw: str) -> int:
    """Parse a positive byte count with optional B, KB/MB/GB or KiB/MiB/GiB."""
    match = re.fullmatch(r"\s*(\d+)\s*([A-Za-z]*)\s*", raw)
    if not match:
        raise argparse.ArgumentTypeError("expected a positive byte count such as 64MiB")
    units = {
        "": 1,
        "B": 1,
        "KB": 1000,
        "MB": 1000**2,
        "GB": 1000**3,
        "KIB": 1024,
        "MIB": 1024**2,
        "GIB": 1024**3,
    }
    unit = match.group(2).upper()
    if unit not in units:
        raise argparse.ArgumentTypeError(f"unsupported byte unit {unit!r}")
    value = int(match.group(1)) * units[unit]
    if value <= 0 or value > MAX_INPUT_BYTES:
        raise argparse.ArgumentTypeError(f"input limit must be between 1 byte and {MAX_INPUT_BYTES} bytes")
    return value


def _read_report(path: Path, limit: int) -> tuple[dict[str, Any], bytes, str]:
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise InputLimitError(f"combined input exceeds the {limit}-byte limit", bytes_read=len(data))
    digest = hashlib.sha256(data).hexdigest()
    try:
        report = json.loads(data.decode("utf-8"), parse_constant=_reject_constant)
    except (UnicodeError, json.JSONDecodeError, ValueError, RecursionError, OverflowError, TypeError) as error:
        raise ReportReadError(f"report is unreadable or malformed: {error}", bytes_read=len(data)) from error
    if not isinstance(report, dict):
        raise ReportReadError("report must be a JSON object", bytes_read=len(data))
    return report, data, digest


def _copy_log_bounded(path: Path, destination: Path, limit: int) -> tuple[int, str]:
    digest = hashlib.sha256()
    copied = 0
    with path.open("rb") as source, destination.open("wb") as target:
        while True:
            read_size = min(COPY_CHUNK_BYTES, limit - copied + 1)
            block = source.read(read_size)
            if not block:
                break
            if copied + len(block) > limit:
                raise InputLimitError(f"combined input exceeds the {limit}-byte limit", bytes_read=copied + len(block))
            target.write(block)
            digest.update(block)
            copied += len(block)
    return copied, digest.hexdigest()


def _validate_report(report: dict[str, Any]) -> tuple[list[str], dict[str, Any] | None]:
    try:
        errors, derived = validate_native_report(report)
    except (RecursionError, OverflowError, TypeError, ValueError) as error:
        return [f"report validation failed safely: {error}"], None
    raw_metrics = report.get("raw_metrics")
    if isinstance(raw_metrics, dict):
        for key in (*CONTEXT_METRICS, "render_gpu_ms", *MEMORY_METRICS):
            values = raw_metrics.get(key)
            if isinstance(values, (list, array)) and any(isinstance(value, (int, float)) and value < 0 for value in values):
                errors.append(f"raw_metrics.{key} must not contain negative values")
        invalid_counts = raw_metrics.get("invalid_value_count")
        if isinstance(invalid_counts, (list, array)) and any(
            isinstance(value, (int, float)) and (value < 0 or not float(value).is_integer())
            for value in invalid_counts
        ):
            errors.append("raw_metrics.invalid_value_count must contain non-negative integer-valued samples")
    return errors, derived


def _source_metadata(report: dict[str, Any]) -> dict[str, Any]:
    metadata = {key: report[key] for key in IDENTITY_FIELDS if key in report}
    if "frame_diagnostics" in report:
        metadata["frame_diagnostics"] = report["frame_diagnostics"]
    # Invalid source metadata must not prevent publication of its invalid verdict.
    try:
        json.dumps(metadata, allow_nan=False)
    except (ValueError, OverflowError, RecursionError):
        return {"omitted": "source metadata contains invalid or excessively nested values"}
    return metadata


def _frame_context(raw_metrics: dict[str, Any], index: int,
                   render_timing_available: bool | None) -> dict[str, Any]:
    context = {key: raw_metrics[key][index] for key in CONTEXT_METRICS if key in raw_metrics}
    ticks = raw_metrics.get("sim_tick", [])
    times = raw_metrics.get("sim_time_s", [])
    context["sim_tick"] = int(ticks[index])
    context["sim_tick_delta"] = int(ticks[index]) - int(ticks[index - 1]) if index > 0 else None
    context["sim_time_s"] = times[index]
    context["sim_time_delta_s"] = float(times[index]) - float(times[index - 1]) if index > 0 else None

    gpu_values = raw_metrics.get("render_gpu_ms")
    if gpu_values is None:
        context["render_gpu_ms_reported"] = None
        context["render_gpu_ms"] = None
        context["render_gpu_ms_interpretation"] = "not_reported"
    else:
        gpu_value = float(gpu_values[index])
        context["render_gpu_ms_reported"] = gpu_value
        contradictory = gpu_value > 0.0 and render_timing_available is False
        context["render_gpu_ms"] = gpu_value if gpu_value > 0.0 and not contradictory else None
        if contradictory:
            context["render_gpu_ms_interpretation"] = "contradictory_timing_unavailable"
        else:
            context["render_gpu_ms_interpretation"] = "positive_sample" if gpu_value > 0.0 else "unavailable_or_zero"
    return context


def _memory_trends(raw_metrics: dict[str, Any]) -> dict[str, Any]:
    trends: dict[str, Any] = {}
    for key in MEMORY_METRICS:
        values = raw_metrics.get(key)
        if values is None:
            continue
        start = float(values[0])
        end = float(values[-1])
        maximum = float(max(values))
        trends[key] = {
            "start": start,
            "end": end,
            "max": maximum,
            "end_delta": end - start,
            "max_delta_from_start": maximum - start,
        }
    return trends


def _burst_record(start: int, end: int, frame_ms: list[float], frame_ends: list[int],
                  wall_usec: list[int], origin_usec: int, budget_ms: float) -> dict[str, Any]:
    selected = frame_ms[start : end + 1]
    return {
        "start_frame_index": start,
        "end_frame_index": end,
        "start_frame_number": start + 1,
        "end_frame_number": end + 1,
        "frame_count": end - start + 1,
        "start_ms": (frame_ends[start] - wall_usec[start] - origin_usec) / 1000.0,
        "end_ms": (frame_ends[end] - origin_usec) / 1000.0,
        "duration_ms": sum(selected),
        "peak_frame_ms": max(selected),
        "total_excess_ms": sum(max(0.0, value - budget_ms) for value in selected),
    }


def analyze_frames(report: dict[str, Any], derived: dict[str, Any], budget_ms: float, top: int) -> dict[str, Any]:
    wall_usec = [int(value) for value in report["frame_wall_usec"]]
    frame_ends = [int(value) for value in report["frame_end_monotonic_usec"]]
    frame_ms = [value / 1000.0 for value in wall_usec]
    count = len(frame_ms)
    origin_usec = frame_ends[0] - wall_usec[0]
    over = [value > budget_ms for value in frame_ms]
    over_count = sum(over)
    total_excess_ms = sum(max(0.0, value - budget_ms) for value in frame_ms)

    burst_count = 0
    burst_heap: list[tuple[tuple[float, int, int], dict[str, Any]]] = []
    start: int | None = None

    def keep_burst(first: int, last: int) -> None:
        nonlocal burst_count
        burst_count += 1
        item = _burst_record(first, last, frame_ms, frame_ends, wall_usec, origin_usec, budget_ms)
        rank = (float(item["peak_frame_ms"]), int(item["frame_count"]), -int(first))
        entry = (rank, item)
        if len(burst_heap) < top:
            heapq.heappush(burst_heap, entry)
        elif rank > burst_heap[0][0]:
            heapq.heapreplace(burst_heap, entry)

    for index, is_over in enumerate(over):
        if is_over and start is None:
            start = index
        elif not is_over and start is not None:
            keep_burst(start, index - 1)
            start = None
    if start is not None:
        keep_burst(start, count - 1)

    top_indices = heapq.nlargest(top, range(count), key=lambda index: (frame_ms[index], -index))
    raw_metrics: dict[str, Any] = report["raw_metrics"]
    frame_diagnostics = report.get("frame_diagnostics")
    render_timing_available = (
        frame_diagnostics.get("render_timing_available")
        if isinstance(frame_diagnostics, dict)
        and type(frame_diagnostics.get("render_timing_available")) is bool
        else None
    )
    top_frames = []
    for index in top_indices:
        start_usec = frame_ends[index] - wall_usec[index]
        top_frames.append({
            "frame_index": index,
            "frame_number": index + 1,
            "start_ms": (start_usec - origin_usec) / 1000.0,
            "end_ms": (frame_ends[index] - origin_usec) / 1000.0,
            "frame_ms": frame_ms[index],
            "over_budget": over[index],
            "context": _frame_context(raw_metrics, index, render_timing_available),
        })

    burst_items = [item for _rank, item in sorted(burst_heap, key=lambda entry: entry[0], reverse=True)]
    gpu_values = raw_metrics.get("render_gpu_ms")
    if gpu_values is None:
        gpu_status = {"reported": False, "measured_positive_samples": 0, "zero_samples": 0,
                      "contradictory_positive_samples": 0, "interpretation": "not_reported"}
    else:
        positive_count = sum(float(value) > 0.0 for value in gpu_values)
        zero_count = sum(float(value) == 0.0 for value in gpu_values)
        contradictory_count = positive_count if render_timing_available is False else 0
        available_positive_count = positive_count - contradictory_count
        gpu_status = {
            "reported": True,
            "measured_positive_samples": available_positive_count,
            "zero_samples": zero_count,
            "contradictory_positive_samples": contradictory_count,
            "interpretation": (
                "invalid_positive_samples_with_timing_unavailable" if contradictory_count
                else "positive_samples_with_zero_sentinels" if available_positive_count
                else "unavailable_or_zero"
            ),
        }
    gpu_status["scope"] = (
        frame_diagnostics.get("viewport_scope", "unknown")
        if isinstance(frame_diagnostics, dict) else "unknown"
    )
    gpu_status["timing_available"] = render_timing_available

    return {
        "budget_ms": budget_ms,
        "budget_comparison": "strictly greater than budget; equality is within budget",
        "frame_count": count,
        "frame_ms_nearest_rank": derived["frame_ms"],
        "over_budget_count": over_count,
        "over_budget_share": over_count / count,
        "over_budget_share_percent": 100.0 * over_count / count,
        "total_excess_ms": total_excess_ms,
        "over_budget_burst_count": burst_count,
        "over_budget_bursts": {
            "returned": len(burst_items),
            "truncated": burst_count > len(burst_items),
            "items": burst_items,
        },
        "top_frames": top_frames,
        "render_gpu_ms_status": gpu_status,
        "memory_sample_trends": _memory_trends(raw_metrics),
    }


def _diagnostic_hint(diagnostic: dict[str, Any]) -> str:
    if diagnostic.get("severity") == "warning":
        return "Informational Godot warning; inspect the supplied context. A warning alone does not invalidate this diagnosis."
    if diagnostic.get("kind") == "SHADER ERROR":
        return "Shader error makes the source log invalid; the log/frame timing coincidence does not establish hitch causality."
    if diagnostic.get("kind") == "SCRIPT ERROR":
        return "Script error makes the source log invalid; use the source location and context to investigate."
    return "Godot error makes the source log invalid; use the source location and context to investigate."


def _measurement_issues(report: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    raw_metrics = report.get("raw_metrics")
    if not isinstance(raw_metrics, dict):
        return issues

    sampled_invalid_indices: list[int] = []
    invalid_counts = raw_metrics.get("invalid_value_count")
    if isinstance(invalid_counts, (list, array)):
        sampled_invalid_indices = [
            index for index, value in enumerate(invalid_counts)
            if _finite_number(value) and value > 0
        ]

    metadata = report.get("frame_diagnostics")
    if isinstance(metadata, dict):
        total_invalid = metadata.get("invalid_numeric_value_count")
        if _finite_number(total_invalid) and total_invalid > 0:
            if sampled_invalid_indices:
                issues.append(
                    "observer reported invalid numeric readings; sampled frames with invalid values: "
                    + ", ".join(str(index) for index in sampled_invalid_indices[:20])
                    + (" (additional sampled indices omitted)" if len(sampled_invalid_indices) > 20 else "")
                    + f"; run-wide invalid_numeric_value_count={total_invalid:g} may also include warm-up polls"
                )
            else:
                issues.append(
                    f"observer reported invalid_numeric_value_count={total_invalid:g}; this run-wide count may include warm-up polls"
                )
        elif sampled_invalid_indices:
            issues.append(
                "observer reported invalid numeric readings in sampled frames: "
                + ", ".join(str(index) for index in sampled_invalid_indices[:20])
                + (" (additional sampled indices omitted)" if len(sampled_invalid_indices) > 20 else "")
            )
    elif sampled_invalid_indices:
        issues.append(
            "observer reported invalid numeric readings in sampled frames: "
            + ", ".join(str(index) for index in sampled_invalid_indices[:20])
            + (" (additional sampled indices omitted)" if len(sampled_invalid_indices) > 20 else "")
        )

    gpu_values = raw_metrics.get("render_gpu_ms")
    timing_available = metadata.get("render_timing_available") if isinstance(metadata, dict) else None
    if (isinstance(gpu_values, (list, array)) and timing_available is False
            and any(type(value) in (int, float) and value > 0.0 for value in gpu_values)):
        issues.append("positive render_gpu_ms samples contradict frame_diagnostics.render_timing_available=false")
    return issues


def _finite_number(value: Any) -> bool:
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(float(value))
    except (OverflowError, TypeError, ValueError):
        return False


def diagnose(report_path: Path, log_path: Path, *, budget_ms: float = DEFAULT_BUDGET_MS,
             top: int = DEFAULT_TOP, max_input_bytes: int = DEFAULT_MAX_INPUT_BYTES) -> dict[str, Any]:
    """Build one diagnosis while reading no more than the combined input cap."""
    report_path = Path(report_path)
    log_path = Path(log_path)
    if not math.isfinite(budget_ms) or budget_ms <= 0.0:
        raise ValueError("budget_ms must be finite and positive")
    if type(top) is not int or not 1 <= top <= MAX_TOP:
        raise ValueError(f"top must be between 1 and {MAX_TOP}")
    if type(max_input_bytes) is not int or not 1 <= max_input_bytes <= MAX_INPUT_BYTES:
        raise ValueError(f"max_input_bytes must be between 1 and {MAX_INPUT_BYTES}")

    report_errors: list[str] = []
    report: dict[str, Any] | None = None
    report_bytes: bytes | None = None
    report_sha256: str | None = None
    report_bytes_read = 0
    try:
        report, report_bytes, report_sha256 = _read_report(report_path, max_input_bytes)
        report_bytes_read = len(report_bytes)
    except InputReadError as error:
        report_errors.append(str(error))
        report_bytes_read = error.bytes_read
    except (OSError, ValueError, RecursionError, OverflowError, TypeError, RuntimeError) as error:
        report_errors.append(str(error))

    analysis_report = report
    stream_evidence: dict[str, Any] | None = None
    stream_reserved_bytes = 0
    has_stream = report is not None and report.get("format") == STREAM_FORMAT
    remaining_bytes = max(0, max_input_bytes - min(report_bytes_read, max_input_bytes))
    if has_stream:
        analysis_report = None
        stream = report.get("stream")
        declared_bytes = stream.get("bytes") if isinstance(stream, dict) else None
        if type(declared_bytes) is int and 0 < declared_bytes <= remaining_bytes:
            # Reserve the declared size even on a failed read so report + attempted
            # stream + log never exceed the requested combined budget.
            stream_reserved_bytes = declared_bytes
        try:
            analysis_report, stream_evidence = _hydrate_stream_report(
                report, report_path, include_metrics=True, max_input_bytes=min(stream_reserved_bytes, STREAM_MAX_BYTES))
        except (OSError, UnicodeError, ValueError, RecursionError, OverflowError, TypeError) as error:
            report_errors.append(f"stream is unreadable or invalid: {error}")

    validation_errors: list[str] = []
    derived: dict[str, Any] | None = None
    if analysis_report is not None:
        validation_errors, derived = _validate_report(analysis_report)
    measurement_issues = _measurement_issues(analysis_report) if analysis_report is not None else []

    remaining_bytes -= stream_reserved_bytes
    log_errors: list[str] = []
    log_bytes_read = 0
    log_sha256: str | None = None
    log_result: dict[str, Any] = {"counts": {"error": 0, "warning": 0}, "diagnostics": []}
    if report_bytes_read > max_input_bytes:
        log_errors.append("log not read because the report exceeded the combined input limit")
    else:
        try:
            with tempfile.TemporaryDirectory(prefix="openrc-frame-diagnose-") as temp_dir:
                bounded_log = Path(temp_dir) / "input.log"
                log_bytes_read, log_sha256 = _copy_log_bounded(log_path, bounded_log, remaining_bytes)
                log_result = inspect_log(bounded_log, [])
        except (OSError, ValueError, RecursionError, OverflowError, TypeError) as error:
            log_errors.append(str(error))
            if isinstance(error, InputLimitError):
                log_bytes_read = error.bytes_read

    log_diagnostics = []
    for item in log_result.get("diagnostics", []):
        enriched = dict(item)
        enriched["hint"] = _diagnostic_hint(item)
        log_diagnostics.append(enriched)
    log_error_count = int(log_result.get("counts", {}).get("error", 0))

    frame_diagnostics: dict[str, Any] | None = None
    if analysis_report is not None and derived is not None and not validation_errors:
        frame_diagnostics = analyze_frames(analysis_report, derived, budget_ms, top)

    valid = bool(report is not None and not report_errors and not validation_errors and not measurement_issues
                 and not log_errors and log_error_count == 0)
    reasons: list[str] = []
    if report_errors:
        reasons.extend(f"report: {reason}" for reason in report_errors)
    if validation_errors:
        reasons.extend(f"report validation: {reason}" for reason in validation_errors)
    if measurement_issues:
        reasons.extend(f"measurement: {reason}" for reason in measurement_issues)
    if log_errors:
        reasons.extend(f"log: {reason}" for reason in log_errors)
    if log_error_count:
        reasons.append(f"log contains {log_error_count} Godot ERROR record(s)")

    source_metadata = _source_metadata(report) if report is not None else {}
    result = {
        "format": FORMAT,
        "version": 1,
        "valid": valid,
        "validity_reasons": reasons,
        "source": {
            "report": str(report_path.resolve()),
            "report_sha256": report_sha256,
            "report_bytes": len(report_bytes) if report_bytes is not None else None,
            "log": str(log_path.resolve()),
            "log_sha256": log_sha256,
            "log_bytes": log_bytes_read if log_sha256 is not None else None,
            "combined_input_bytes": None if has_stream and stream_evidence is None else
                (len(report_bytes) if report_bytes is not None else min(report_bytes_read, max_input_bytes + 1))
                + (stream_evidence["bytes"] if stream_evidence is not None else 0)
                + (log_bytes_read if log_sha256 is not None else min(log_bytes_read, remaining_bytes + 1)),
            "max_input_bytes": max_input_bytes,
        },
        "source_metadata": source_metadata,
        "report_validation": {"valid": report is not None and not report_errors and not validation_errors,
                              "errors": report_errors + validation_errors},
        "measurement_issues": measurement_issues,
        "measurement_status": "invalid" if measurement_issues else "no_detected_invalid_measurements",
        "measurement_hints": [
            "The observer substitutes zero for invalid numeric readings; any positive invalid-value count invalidates this measurement set.",
            "render_gpu_ms values are interpretable only when the declared timing capability allows them; missing capability metadata means scope is unknown.",
        ],
        "log_validation": {
            "readable": not log_errors,
            "errors": log_errors,
            "counts": log_result.get("counts", {"error": 0, "warning": 0}),
            "diagnostics": log_diagnostics,
            "diagnostics_omitted": max(0, log_error_count + int(log_result.get("counts", {}).get("warning", 0)) - len(log_diagnostics)),
        },
        "observations": frame_diagnostics,
        "interpretation_hints": list(GENERAL_HINTS),
        "claims": {
            "active_flight_qualification": "not_assessed",
            "gpu_hardware_acceptance": "not_claimed",
            "memory_leak": "not_claimed",
            "causal_attribution": "not_established",
        },
    }
    if has_stream:
        result["source"]["stream"] = stream_evidence
    return result


def write_new_json(path: Path, value: dict[str, Any]) -> None:
    """Write exclusively so an existing file or symlink is never replaced."""
    path = Path(path)
    if path.exists() or path.is_symlink():
        raise FileExistsError(f"output must be a new path: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False) + "\n"
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(encoded)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True, help="one openrc-frametimes v2 or v3 JSON report")
    parser.add_argument("--log", type=Path, required=True, help="combined engine log for that report")
    parser.add_argument("--out", type=Path, required=True, help="new openrc-frame-diagnosis JSON path")
    parser.add_argument("--budget-ms", type=float, default=DEFAULT_BUDGET_MS,
                        help=f"wall-frame interval budget in milliseconds (default: {DEFAULT_BUDGET_MS:g})")
    parser.add_argument("--top", type=int, default=DEFAULT_TOP, help=f"maximum top frames/bursts to retain (1..{MAX_TOP})")
    parser.add_argument("--max-input-bytes", type=parse_byte_limit, default=DEFAULT_MAX_INPUT_BYTES,
                        help="combined report+stream+log byte cap; accepts B/KB/MB/GB or KiB/MiB/GiB (default: 64MiB)")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")
        except (AttributeError, OSError, ValueError):
            pass
    parser = build_parser()
    args = parser.parse_args(argv)
    if not math.isfinite(args.budget_ms) or args.budget_ms <= 0.0:
        parser.error("--budget-ms must be finite and positive")
    if not 1 <= args.top <= MAX_TOP:
        parser.error(f"--top must be between 1 and {MAX_TOP}")
    try:
        result = diagnose(args.report, args.log, budget_ms=args.budget_ms,
                          top=args.top, max_input_bytes=args.max_input_bytes)
        write_new_json(args.out, result)
    except (OSError, ValueError, RecursionError, OverflowError, TypeError, RuntimeError) as error:
        print(f"frame diagnose: {error}", file=sys.stderr)
        return 2
    observations = result.get("observations") or {}
    print(
        f"frame diagnosis: {'valid' if result['valid'] else 'invalid'}; "
        f"{observations.get('frame_count', 0)} frames, "
        f"{observations.get('over_budget_count', 0)} over budget, "
        f"{observations.get('over_budget_burst_count', 0)} bursts; "
        f"{result.get('log_validation', {}).get('counts', {}).get('warning', 0)} warnings; "
        f"report {args.out.resolve()}"
    )
    frame_ms = observations.get("frame_ms_nearest_rank")
    if frame_ms:
        print(f"  p95 {frame_ms['p95']:.3f} ms; p99 {frame_ms['p99']:.3f} ms; budget {observations['budget_ms']:.3f} ms")
        for item in observations.get("top_frames", [])[:3]:
            gpu_context = item["context"]
            gpu_value = gpu_context.get("render_gpu_ms")
            gpu_note = (f"GPU {gpu_value:.3f} ms" if gpu_value is not None
                        else f"GPU {gpu_context.get('render_gpu_ms_interpretation', 'unavailable')}")
            print(f"  frame {item['frame_number']} {item['start_ms']:.3f}-{item['end_ms']:.3f} ms: "
                  f"{item['frame_ms']:.3f} ms, {gpu_note}")
    if not result["valid"]:
        for reason in result["validity_reasons"][:5]:
            print(f"  {reason}", file=sys.stderr)
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
