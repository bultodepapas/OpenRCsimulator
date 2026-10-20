#!/usr/bin/env python3
"""Export bounded OpenRC performance captures as legacy Perfetto JSON traces.

The trace contains wall-time frame intervals and sampled counter tracks. It does
not turn frame intervals into CPU slices or infer missing measurements.
"""
from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import sys
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

try:
    from research.performance.native_summary import validate_native_report
except ImportError:  # Direct execution from a source checkout.
    from native_summary import validate_native_report  # type: ignore[no-redef]


DEFAULT_MAX_INPUT_BYTES = 64 * 1024 * 1024
MAX_INPUT_BYTES = 256 * 1024 * 1024
DEFAULT_MAX_EVENTS = 500_000
MAX_EVENTS = 1_000_000
MAX_FRAME_SAMPLES = 120_000
MAX_RESOURCE_SAMPLES = 10_000
MAX_SAFE_INTEGER = (1 << 53) - 1
UNCERTAINTY_FLOOR_USEC = 20_000


class ExportError(ValueError):
    """An input or export error with the intended CLI status."""

    def __init__(self, message: str, *, exit_code: int):
        super().__init__(message)
        self.exit_code = exit_code


class SourceError(ExportError):
    def __init__(self, message: str):
        super().__init__(message, exit_code=1)


class BudgetError(ExportError):
    def __init__(self, message: str):
        super().__init__(message, exit_code=2)


_FRAME_METRICS: dict[str, str] = {
    "fps_monitor": "frames/s",
    "sim_tick": "ticks",
    "sim_time_s": "s",
    "process_time_s": "s",
    "physics_process_time_s": "s",
    "physics_step_usec": "us",
    "draw_calls": "calls",
    "primitives": "primitives",
    "object_count": "objects",
    "node_count": "nodes",
    "physics_3d_active_objects": "objects",
    "physics_3d_collision_pairs": "pairs",
    "observer_poll_usec": "us",
    "invalid_value_count": "count",
    "render_cpu_ms": "ms",
    "render_gpu_ms": "ms",
    "frame_setup_cpu_ms": "ms",
    "memory_static_bytes": "bytes",
    "render_video_memory_bytes": "bytes",
    "render_texture_memory_bytes": "bytes",
    "render_buffer_memory_bytes": "bytes",
    "resource_count": "resources",
    "orphan_node_count": "nodes",
}
assert len(_FRAME_METRICS) <= 32

_RESOURCE_METRICS: dict[str, tuple[str, str]] = {
    "rss_bytes": ("process", "bytes"),
    "vms_bytes": ("process", "bytes"),
    "cpu_user_seconds": ("process", "s"),
    "cpu_system_seconds": ("process", "s"),
    "cpu_percent": ("process", "percent"),
    "num_threads": ("process", "threads"),
    "io_read_bytes": ("process", "bytes"),
    "io_write_bytes": ("process", "bytes"),
    "io_read_count": ("process", "operations"),
    "io_write_count": ("process", "operations"),
    "virtual_memory_total_bytes": ("system", "bytes"),
    "virtual_memory_available_bytes": ("system", "bytes"),
    "virtual_memory_percent": ("system", "percent"),
    "swap_used_bytes": ("system", "bytes"),
    "swap_total_bytes": ("system", "bytes"),
}
_INTEGER_RESOURCE_FIELDS = {
    "rss_bytes", "vms_bytes", "num_threads", "io_read_bytes", "io_write_bytes",
    "io_read_count", "io_write_count", "virtual_memory_total_bytes",
    "virtual_memory_available_bytes", "swap_used_bytes", "swap_total_bytes",
}
_VOLUME_FIELDS = ("free_bytes", "total_bytes")
_ALLOWED_COVERAGE = {"sampled", "partial", "no_samples", "capped"}
_ALLOWED_MEASUREMENT_STATUS = {"ok", "partial", "unavailable"}


def _strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON value {value} is forbidden")


def _read_json(path: Path, byte_limit: int) -> tuple[dict[str, Any], int]:
    try:
        with path.open("rb") as stream:
            data = stream.read(byte_limit + 1)
    except OSError as error:
        raise SourceError(f"cannot read source {path}: {error}") from error
    if len(data) > byte_limit:
        raise BudgetError(f"combined source input exceeds the {byte_limit}-byte limit")
    try:
        value = json.loads(
            data.decode("utf-8"),
            parse_constant=_reject_constant,
            object_pairs_hook=_strict_object,
        )
    except (UnicodeError, json.JSONDecodeError, ValueError, RecursionError, OverflowError, TypeError) as error:
        raise SourceError(f"source {path} is unreadable or malformed: {error}") from error
    if not isinstance(value, dict):
        raise SourceError(f"source {path} must contain a JSON object")
    return value, len(data)


def read_sources(*, frames_path: Path | None = None, resources_path: Path | None = None,
                 max_input_bytes: int = DEFAULT_MAX_INPUT_BYTES) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    if type(max_input_bytes) is not int or not 1 <= max_input_bytes <= MAX_INPUT_BYTES:
        raise BudgetError(f"max_input_bytes must be between 1 and {MAX_INPUT_BYTES}")
    if frames_path is None and resources_path is None:
        raise BudgetError("provide at least one of --frames or --resources")
    if frames_path is not None and resources_path is not None:
        try:
            same_source = Path(frames_path).resolve() == Path(resources_path).resolve()
        except OSError:
            same_source = Path(frames_path) == Path(resources_path)
        if same_source:
            raise SourceError("--frames and --resources must refer to different files")

    frames = resources = None
    consumed = 0
    if frames_path is not None:
        frames, consumed = _read_json(Path(frames_path), max_input_bytes)
    if resources_path is not None:
        resources, read = _read_json(Path(resources_path), max_input_bytes - consumed)
        consumed += read
    return frames, resources


def _is_number(value: Any) -> bool:
    return type(value) in (int, float) and math.isfinite(float(value))


def _safe_integer(value: Any, label: str, *, positive: bool = False) -> int:
    if type(value) is not int or value < (1 if positive else 0) or value > MAX_SAFE_INTEGER:
        qualifier = "positive" if positive else "non-negative"
        raise SourceError(f"{label} must be a {qualifier} safe integer")
    return value


def _nonempty_string(value: Any, label: str, *, max_length: int = 256) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > max_length:
        raise SourceError(f"{label} must be a non-empty string of at most {max_length} characters")
    return value


def _validate_clock(value: Any, expected_source: str, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise SourceError(f"{label}.clock must be an object")
    source = value.get("source")
    if source != expected_source:
        raise SourceError(f"{label}.clock.source must be {expected_source!r}")
    origin = _safe_integer(value.get("origin_usec"), f"{label}.clock.origin_usec")
    anchors: dict[str, dict[str, int]] = {}
    for endpoint in ("start", "end"):
        raw = value.get(endpoint)
        if not isinstance(raw, dict):
            raise SourceError(f"{label}.clock.{endpoint} must be an object")
        monotonic = _safe_integer(raw.get("monotonic_usec"), f"{label}.clock.{endpoint}.monotonic_usec")
        unix = _safe_integer(raw.get("unix_usec"), f"{label}.clock.{endpoint}.unix_usec", positive=True)
        uncertainty = _safe_integer(raw.get("uncertainty_usec"), f"{label}.clock.{endpoint}.uncertainty_usec")
        anchors[endpoint] = {
            "monotonic_usec": monotonic,
            "unix_usec": unix,
            "uncertainty_usec": uncertainty,
        }
    if anchors["end"]["monotonic_usec"] <= anchors["start"]["monotonic_usec"]:
        raise SourceError(f"{label}.clock monotonic anchors must increase")
    if anchors["end"]["unix_usec"] <= anchors["start"]["unix_usec"]:
        raise SourceError(f"{label}.clock wall-clock anchors must increase")
    return {"source": source, "origin_usec": origin, **anchors}


def _frame_clock(report: dict[str, Any]) -> dict[str, Any] | None:
    if "clock" not in report:
        return None
    return _validate_clock(report["clock"], "godot_ticks_usec", "frames")


def _resource_clock(report: dict[str, Any]) -> dict[str, Any] | None:
    if "clock" not in report:
        return None
    return _validate_clock(report["clock"], "python_perf_counter", "resources")


def _capture_id(report: dict[str, Any], label: str) -> str | None:
    if "capture_id" not in report:
        return None
    return _nonempty_string(report.get("capture_id"), f"{label}.capture_id")


def _validate_frames(report: dict[str, Any]) -> tuple[dict[str, Any], bool, dict[str, Any] | None]:
    if report.get("format") != "openrc-frametimes v2":
        raise SourceError("frame source format must be 'openrc-frametimes v2'")
    count = report.get("frames")
    if type(count) is not int or not 1 <= count <= MAX_FRAME_SAMPLES:
        raise SourceError(f"frames must be an integer between 1 and {MAX_FRAME_SAMPLES}")
    for key in ("frame_deltas_s", "frame_wall_usec", "frame_end_monotonic_usec"):
        values = report.get(key)
        if not isinstance(values, list) or len(values) != count:
            raise SourceError(f"{key} must contain exactly {count} samples")
    raw_metrics = report.get("raw_metrics")
    if not isinstance(raw_metrics, dict):
        raise SourceError("raw_metrics must be an object")
    for key, values in raw_metrics.items():
        if not isinstance(key, str) or not isinstance(values, list) or len(values) != count:
            raise SourceError(f"raw_metrics.{key} must contain exactly {count} samples")

    _capture_id(report, "frames")
    _frame_clock(report)
    partial = report.get("complete") is False
    validation_report = report
    if partial:
        # validate_native_report correctly rejects incomplete reports. Validate
        # the retained prefix as complete on a shallow copy, removing only that
        # explicit completeness error and its dependent failure-text constraint.
        validation_report = dict(report)
        validation_report["complete"] = True
        validation_report["failure"] = ""
    errors, derived = validate_native_report(validation_report)
    if partial:
        errors = [error for error in errors if error != "report is marked incomplete"]
    if errors or derived is None:
        preview = "; ".join(errors[:8]) if errors else "native frame validation produced no derived data"
        raise SourceError(f"frame source failed native validation: {preview}")
    return report, partial, derived


def _finite_nonnegative(value: Any, label: str) -> int | float:
    if not _is_number(value) or float(value) < 0:
        raise SourceError(f"{label} must be finite and non-negative")
    return value


def _validate_resources(report: dict[str, Any]) -> tuple[dict[str, Any], bool, dict[str, Any]]:
    if report.get("format") != "openrc-resource-samples v1":
        raise SourceError("resource source format must be 'openrc-resource-samples v1'")
    _capture_id(report, "resources")
    _resource_clock(report)
    samples = report.get("samples")
    if not isinstance(samples, list) or len(samples) > MAX_RESOURCE_SAMPLES:
        raise SourceError(f"resource samples must be an array of at most {MAX_RESOURCE_SAMPLES} items")
    sample_count = report.get("sample_count")
    if type(sample_count) is not int or sample_count != len(samples):
        raise SourceError("sample_count must equal the number of samples")
    coverage = report.get("coverage")
    if coverage not in _ALLOWED_COVERAGE:
        raise SourceError("resource coverage must be sampled, partial, no_samples, or capped")
    measurement_status = report.get("measurement_status")
    if measurement_status not in _ALLOWED_MEASUREMENT_STATUS:
        raise SourceError("resource measurement_status must be ok, partial, or unavailable")
    if (coverage == "no_samples") != (sample_count == 0):
        raise SourceError("no_samples coverage must agree with an empty samples array")
    if coverage == "capped" and report.get("capped") is not True:
        raise SourceError("capped coverage requires capped=true")
    if type(report.get("error_count")) is not int or report["error_count"] < 0:
        raise SourceError("resource error_count must be a non-negative integer")
    if type(report.get("capped")) is not bool:
        raise SourceError("resource capped must be a boolean")

    previous_elapsed = -1.0
    common_volume_paths: list[str] | None = None
    status_counts: dict[str, dict[str, int]] = {}
    normalized_samples: list[dict[str, Any]] = []
    partial = coverage != "sampled" or measurement_status != "ok" or report["error_count"] > 0
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            raise SourceError(f"samples[{index}] must be an object")
        elapsed = _finite_nonnegative(sample.get("elapsed_seconds"), f"samples[{index}].elapsed_seconds")
        elapsed_float = float(elapsed)
        if elapsed_float <= previous_elapsed:
            raise SourceError("resource elapsed_seconds must be strictly increasing")
        previous_elapsed = elapsed_float
        statuses = sample.get("field_status")
        if not isinstance(statuses, dict):
            raise SourceError(f"samples[{index}].field_status must be an object")

        values: dict[str, int | float] = {}
        for field in _RESOURCE_METRICS:
            if field not in sample or field not in statuses:
                raise SourceError(f"samples[{index}] is missing {field} or its field_status")
            status = statuses[field]
            if not isinstance(status, str) or not status:
                raise SourceError(f"samples[{index}].field_status.{field} must be a non-empty string")
            bucket = status_counts.setdefault(field, {})
            bucket[status] = bucket.get(status, 0) + 1
            value = sample[field]
            if status == "ok":
                value = _finite_nonnegative(value, f"samples[{index}].{field}")
                if field in _INTEGER_RESOURCE_FIELDS and type(value) is not int:
                    raise SourceError(f"samples[{index}].{field} must be an integer byte/count value")
                values[field] = value
            elif value is not None and not _is_number(value):
                raise SourceError(f"samples[{index}].{field} must be numeric or null when status is {status!r}")

        volumes = sample.get("volumes")
        if not isinstance(volumes, list) or len(volumes) > 8:
            raise SourceError(f"samples[{index}].volumes must be an array of at most 8 entries")
        volume_paths = []
        normalized_volumes = []
        for volume_index, volume in enumerate(volumes):
            if not isinstance(volume, dict):
                raise SourceError(f"samples[{index}].volumes[{volume_index}] must be an object")
            volume_path = _nonempty_string(volume.get("path"), f"samples[{index}].volumes[{volume_index}].path", max_length=4096)
            volume_paths.append(volume_path)
            normalized_volume: dict[str, Any] = {"path": volume_path, "values": {}}
            for field in _VOLUME_FIELDS:
                status_key = f"volume[{volume_index}].{field}"
                if field not in volume or status_key not in statuses:
                    raise SourceError(f"samples[{index}].volumes[{volume_index}] is missing {field} or {status_key}")
                status = statuses[status_key]
                if not isinstance(status, str) or not status:
                    raise SourceError(f"samples[{index}].field_status.{status_key} must be a non-empty string")
                bucket = status_counts.setdefault(status_key, {})
                bucket[status] = bucket.get(status, 0) + 1
                value = volume[field]
                if status == "ok":
                    value = _finite_nonnegative(value, f"samples[{index}].volumes[{volume_index}].{field}")
                    if type(value) is not int:
                        raise SourceError(f"samples[{index}].volumes[{volume_index}].{field} must be an integer")
                    normalized_volume["values"][field] = value
                elif value is not None and not _is_number(value):
                    raise SourceError(f"samples[{index}].volumes[{volume_index}].{field} must be numeric or null when status is {status!r}")
            normalized_volumes.append(normalized_volume)
        if common_volume_paths is None:
            common_volume_paths = volume_paths
        elif volume_paths != common_volume_paths:
            raise SourceError("volume paths and order must remain stable across resource samples")

        normalized_samples.append({
            "elapsed_seconds": elapsed_float,
            "values": values,
            "volumes": normalized_volumes,
        })

    return report, partial, {
        "coverage": coverage,
        "measurement_status": measurement_status,
        "sample_count": sample_count,
        "error_count": report["error_count"],
        "capped": report["capped"],
        "stop_reason": report.get("stop_reason") if isinstance(report.get("stop_reason"), str) else None,
        "status_counts": status_counts,
        "volume_paths": common_volume_paths or [],
        "samples": normalized_samples,
    }


def _effective_uncertainty(anchor: dict[str, int]) -> int:
    return max(anchor["uncertainty_usec"], UNCERTAINTY_FLOOR_USEC)


def _combined_clock(frame_clock: dict[str, Any], resource_clock: dict[str, Any],
                    max_clock_drift_ms: float) -> tuple[dict[str, Any], int, int]:
    max_drift_usec = int(round(max_clock_drift_ms * 1000.0))
    frame_offset_start = frame_clock["start"]["unix_usec"] - frame_clock["start"]["monotonic_usec"]
    resource_offset_start = resource_clock["start"]["unix_usec"] - resource_clock["start"]["monotonic_usec"]
    frame_offset_end = frame_clock["end"]["unix_usec"] - frame_clock["end"]["monotonic_usec"]
    resource_offset_end = resource_clock["end"]["unix_usec"] - resource_clock["end"]["monotonic_usec"]
    frame_drift = abs(frame_offset_end - frame_offset_start)
    resource_drift = abs(resource_offset_end - resource_offset_start)
    combined_uncertainty = max(
        _effective_uncertainty(frame_clock["start"]) + _effective_uncertainty(resource_clock["start"]),
        _effective_uncertainty(frame_clock["end"]) + _effective_uncertainty(resource_clock["end"]),
    )
    allowed = combined_uncertainty + max_drift_usec
    if frame_drift > allowed or resource_drift > allowed:
        raise SourceError(
            f"combined clock anchor drift exceeds allowance: frame={frame_drift} us, "
            f"resources={resource_drift} us, allowed={allowed} us"
        )
    metadata = {
        "mode": "aligned_utc",
        "alignment": "each monotonic timeline mapped by its start UNIX-minus-monotonic offset",
        "uncertainty_floor_usec": UNCERTAINTY_FLOOR_USEC,
        "combined_uncertainty_usec": combined_uncertainty,
        "max_clock_drift_usec": max_drift_usec,
        "frame_offset_start_usec": frame_offset_start,
        "resource_offset_start_usec": resource_offset_start,
        "frame_offset_end_usec": frame_offset_end,
        "resource_offset_end_usec": resource_offset_end,
        "frame_offset_drift_usec": frame_drift,
        "resource_offset_drift_usec": resource_drift,
        "allowed_drift_usec": allowed,
    }
    return metadata, frame_offset_start, resource_offset_start


def _chrome_timestamp(value: int, label: str) -> int:
    if type(value) is not int or value < 0 or value > MAX_SAFE_INTEGER:
        raise SourceError(f"{label} would not be a safe non-negative JSON integer")
    return value


def _make_event(events: list[dict[str, Any]], event: dict[str, Any], limit: int) -> None:
    if len(events) >= limit:
        raise BudgetError(f"trace would exceed the {limit}-event limit")
    events.append(event)


def _metadata_event(args: dict[str, Any]) -> dict[str, Any]:
    return {"pid": 1, "tid": 1, "ph": "M", "name": "capture_metadata", "args": args}


def build_trace(*, frames: dict[str, Any] | None = None, resources: dict[str, Any] | None = None,
                frame_source: str = "frames.json", resource_source: str = "resources.json",
                max_events: int = DEFAULT_MAX_EVENTS, max_clock_drift_ms: float = 50.0) -> tuple[list[dict[str, Any]], bool]:
    """Validate sources and build Chrome JSON events; return events and partial flag."""
    if frames is None and resources is None:
        raise BudgetError("provide at least one source")
    if type(max_events) is not int or not 1 <= max_events <= MAX_EVENTS:
        raise BudgetError(f"max_events must be between 1 and {MAX_EVENTS}")
    if (type(max_clock_drift_ms) not in (int, float) or not math.isfinite(float(max_clock_drift_ms))
            or not 0 <= float(max_clock_drift_ms) <= 1000):
        raise BudgetError("max_clock_drift_ms must be finite and between 0 and 1000")

    normalized_frames = None
    frame_partial = False
    frame_derived = None
    if frames is not None:
        normalized_frames, frame_partial, frame_derived = _validate_frames(frames)
    normalized_resources = None
    resource_partial = False
    resource_info = None
    if resources is not None:
        normalized_resources, resource_partial, resource_info = _validate_resources(resources)

    capture_id: str | None = None
    frame_clock = _frame_clock(normalized_frames) if normalized_frames is not None else None
    resource_clock = _resource_clock(normalized_resources) if normalized_resources is not None else None
    clock_metadata: dict[str, Any]
    frame_offset = resource_offset = 0
    if normalized_frames is not None and normalized_resources is not None:
        frame_id = _capture_id(normalized_frames, "frames")
        resource_id = _capture_id(normalized_resources, "resources")
        if not frame_id or not resource_id or frame_id != resource_id:
            raise SourceError("combined frame/resource sources require the same non-empty capture_id")
        if frame_clock is None or resource_clock is None:
            raise SourceError("combined sources require valid clock anchors in both reports")
        capture_id = frame_id
        clock_metadata, frame_offset, resource_offset = _combined_clock(
            frame_clock, resource_clock, float(max_clock_drift_ms)
        )
        frame_frame_starts = [int(end) - int(wall) for end, wall in zip(
            normalized_frames["frame_end_monotonic_usec"], normalized_frames["frame_wall_usec"]
        )]
        frame_first_utc = frame_frame_starts[0] + frame_offset
        resource_samples = resource_info["samples"]
        if resource_samples:
            resource_first_utc = resource_clock["origin_usec"] + int(round(resource_samples[0]["elapsed_seconds"] * 1_000_000)) + resource_offset
        else:
            resource_first_utc = None
        zero_utc = min(frame_first_utc, resource_first_utc) if resource_first_utc is not None else frame_first_utc
        clock_metadata["zero_utc_usec"] = _safe_integer(zero_utc, "combined trace zero_utc_usec")
        clock_metadata["frame_clock"] = frame_clock
        clock_metadata["resource_clock"] = resource_clock
    elif normalized_frames is not None:
        capture_id = _capture_id(normalized_frames, "frames")
        frame_starts = [int(end) - int(wall) for end, wall in zip(
            normalized_frames["frame_end_monotonic_usec"], normalized_frames["frame_wall_usec"]
        )]
        frame_offset = -frame_starts[0]
        clock_metadata = {
            "mode": "relative_frame_timeline",
            "origin": "first frame interval start",
            "source_clock_anchors_present": frame_clock is not None,
        }
    else:
        capture_id = _capture_id(normalized_resources, "resources")
        resource_offset = 0
        clock_metadata = {
            "mode": "relative_resource_timeline",
            "origin": "resource sampler elapsed_seconds",
            "source_clock_anchors_present": resource_clock is not None,
        }

    events: list[dict[str, Any]] = []
    process_name = "OpenRC simulator performance capture"
    _make_event(events, {"pid": 1, "tid": 1, "ph": "M", "name": "process_name", "args": {"name": process_name}}, max_events)
    if normalized_frames is not None:
        _make_event(events, {"pid": 1, "tid": 1, "ph": "M", "name": "thread_name", "args": {"name": "Frame wall time and diagnostics"}}, max_events)
    if normalized_resources is not None:
        _make_event(events, {"pid": 1, "tid": 2, "ph": "M", "name": "thread_name", "args": {"name": "Process and system samples"}}, max_events)

    sources: dict[str, Any] = {}
    issues: list[str] = []
    if normalized_frames is not None:
        raw_metrics = normalized_frames["raw_metrics"]
        frame_diagnostics = normalized_frames.get("frame_diagnostics")
        gpu_available = (
            frame_diagnostics.get("render_timing_available")
            if isinstance(frame_diagnostics, dict) and type(frame_diagnostics.get("render_timing_available")) is bool
            else None
        )
        gpu_values = raw_metrics.get("render_gpu_ms")
        gpu_zero_count = sum(value == 0 for value in gpu_values) if isinstance(gpu_values, list) else 0
        gpu_positive_count = sum(value > 0 for value in gpu_values) if isinstance(gpu_values, list) else 0
        gpu_contradictory = gpu_available is False and gpu_positive_count > 0
        frame_metrics = [key for key in raw_metrics if key in _FRAME_METRICS]
        unknown_metrics = [key for key in raw_metrics if key not in _FRAME_METRICS]
        frame_gaps = normalized_frames.get("failure", "")
        if frame_partial:
            issues.append(f"frame capture is incomplete: {str(frame_gaps)[:500] or 'retained prefix'}")
        if unknown_metrics:
            issues.append("unexported frame metrics: " + ", ".join(unknown_metrics[:32]))
        if gpu_contradictory:
            issues.append("positive GPU timer samples conflict with render_timing_available=false; GPU counters omitted")
        sources["frames"] = {
            "file": Path(frame_source).name,
            "format": normalized_frames["format"],
            "complete": normalized_frames["complete"],
            "frame_count": normalized_frames["frames"],
            "route": normalized_frames.get("route"),
            "case_id": normalized_frames.get("case_id"),
            "backend": normalized_frames.get("backend"),
            "raw_metric_names": frame_metrics,
            "unknown_metric_names": unknown_metrics[:32],
            "gpu_timer": {
                "timing_available": gpu_available,
                "zero_samples": gpu_zero_count,
                "positive_samples": gpu_positive_count,
                "interpretation": (
                    "contradictory_timing_unavailable" if gpu_contradictory else
                    "positive_samples_with_zero_sentinels" if gpu_positive_count and gpu_zero_count else
                    "measured_positive_samples" if gpu_positive_count else
                    "unavailable_or_zero" if gpu_values is not None else "not_reported"
                ),
            },
            "frame_diagnostics": {
                key: frame_diagnostics[key]
                for key in ("enabled", "headless", "render_timing_available", "viewport_scope")
                if isinstance(frame_diagnostics, dict) and key in frame_diagnostics
            },
        }
        if isinstance(frame_diagnostics, dict):
            for issue in frame_diagnostics.get("issues", []) if isinstance(frame_diagnostics.get("issues"), list) else []:
                if isinstance(issue, str) and issue:
                    issues.append("frame diagnostic: " + issue[:500])

        frame_starts = [int(end) - int(wall) for end, wall in zip(
            normalized_frames["frame_end_monotonic_usec"], normalized_frames["frame_wall_usec"]
        )]
        for index, (start, end, wall) in enumerate(zip(
                frame_starts, normalized_frames["frame_end_monotonic_usec"], normalized_frames["frame_wall_usec"])):
            if normalized_resources is not None:
                start_utc = start + frame_offset
                end_utc = int(end) + frame_offset
                base = clock_metadata["zero_utc_usec"]
                ts = _chrome_timestamp(start_utc - base, f"frames[{index}].ts")
            else:
                ts = _chrome_timestamp(start + frame_offset, f"frames[{index}].ts")
            duration = _safe_integer(int(wall), f"frames[{index}].dur", positive=True)
            args: dict[str, Any] = {"frame_index": index}
            if "sim_tick" in raw_metrics:
                args["sim_tick"] = raw_metrics["sim_tick"][index]
            if "sim_time_s" in raw_metrics:
                args["sim_time_s"] = raw_metrics["sim_time_s"][index]
            _make_event(events, {
                "pid": 1, "tid": 1, "ts": ts, "dur": duration,
                "ph": "X", "cat": "frame", "name": "frame wall interval", "args": args,
            }, max_events)

        for key in frame_metrics:
            values = raw_metrics[key]
            if key == "render_gpu_ms" and (gpu_contradictory or gpu_positive_count == 0):
                continue
            unit = _FRAME_METRICS[key]
            track = f"frame.{key} [{unit}]"
            for index, value in enumerate(values):
                if key == "render_gpu_ms" and value == 0:
                    continue
                end = int(normalized_frames["frame_end_monotonic_usec"][index])
                if normalized_resources is not None:
                    base = clock_metadata["zero_utc_usec"]
                    timestamp = end + frame_offset - base
                else:
                    timestamp = end + frame_offset
                _make_event(events, {
                    "pid": 1, "tid": 1, "ts": _chrome_timestamp(timestamp, f"{track}[{index}].ts"),
                    "ph": "C", "name": track, "cat": "frame_metric", "args": {"value": value},
                }, max_events)

    if normalized_resources is not None:
        report = normalized_resources
        if resource_partial:
            issues.append(
                f"resource capture coverage={resource_info['coverage']}, measurement_status={resource_info['measurement_status']}"
            )
        if resource_info["error_count"]:
            issues.append(f"resource sampler reported {resource_info['error_count']} error(s)")
        for field, (scope, unit) in _RESOURCE_METRICS.items():
            for index, sample in enumerate(resource_info["samples"]):
                if field not in sample["values"]:
                    continue
                elapsed_usec = int(round(sample["elapsed_seconds"] * 1_000_000))
                if normalized_frames is not None:
                    monotonic = resource_clock["origin_usec"] + elapsed_usec
                    timestamp = monotonic + resource_offset - clock_metadata["zero_utc_usec"]
                else:
                    timestamp = elapsed_usec
                track = f"resource.{scope}.{field} [{unit}]"
                _make_event(events, {
                    "pid": 1, "tid": 2, "ts": _chrome_timestamp(timestamp, f"samples[{index}].{field}.ts"),
                    "ph": "C", "name": track, "cat": "resource_metric",
                    "args": {"value": sample["values"][field]},
                }, max_events)
        for volume_index, volume_path in enumerate(resource_info["volume_paths"]):
            for field in _VOLUME_FIELDS:
                status_key = f"volume[{volume_index}].{field}"
                track = f"resource.volume[{volume_index}].{field} [bytes]"
                for index, sample in enumerate(resource_info["samples"]):
                    value = sample["volumes"][volume_index]["values"].get(field)
                    if value is None:
                        continue
                    elapsed_usec = int(round(sample["elapsed_seconds"] * 1_000_000))
                    if normalized_frames is not None:
                        monotonic = resource_clock["origin_usec"] + elapsed_usec
                        timestamp = monotonic + resource_offset - clock_metadata["zero_utc_usec"]
                    else:
                        timestamp = elapsed_usec
                    _make_event(events, {
                        "pid": 1, "tid": 2, "ts": _chrome_timestamp(timestamp, f"samples[{index}].{status_key}.ts"),
                        "ph": "C", "name": track, "cat": "resource_metric", "args": {"value": value},
                    }, max_events)
        sources["resources"] = {
            "file": Path(resource_source).name,
            "format": report["format"],
            "coverage": resource_info["coverage"],
            "measurement_status": resource_info["measurement_status"],
            "sample_count": resource_info["sample_count"],
            "error_count": resource_info["error_count"],
            "capped": resource_info["capped"],
            "stop_reason": resource_info["stop_reason"],
            "field_status_counts": resource_info["status_counts"],
            "volume_paths": resource_info["volume_paths"],
        }
        source_errors = report.get("errors")
        if isinstance(source_errors, list):
            for error in source_errors[:20]:
                if isinstance(error, dict):
                    status = error.get("status")
                    field = error.get("field")
                    message = error.get("message")
                    if all(isinstance(part, str) for part in (status, field, message)):
                        issues.append(f"resource {status} {field}: {message[:300]}")

    metadata = {
        "capture_id": capture_id,
        "sources": sources,
        "source_issues": issues[:64],
        "clock": clock_metadata,
        "frame_intervals": "wall-time X slices; duration is frame_wall_usec, not CPU time",
        "counter_units": "unit labels are included in each counter track name",
        "unknown_values": "omitted or represented by source status; unavailable values are never replaced with zero",
        "gpu_timer": "zero is unavailable_or_zero; zero-valued GPU counter samples are omitted",
        "trace_event_count_before_metadata": len(events),
    }
    _make_event(events, _metadata_event(metadata), max_events)
    partial = frame_partial or resource_partial
    return events, partial


def _validate_cli_budgets(max_input_bytes: int, max_events: int, max_clock_drift_ms: float) -> None:
    if type(max_input_bytes) is not int or not 1 <= max_input_bytes <= MAX_INPUT_BYTES:
        raise BudgetError(f"--max-input-bytes must be between 1 and {MAX_INPUT_BYTES}")
    if type(max_events) is not int or not 1 <= max_events <= MAX_EVENTS:
        raise BudgetError(f"--max-events must be between 1 and {MAX_EVENTS}")
    if (type(max_clock_drift_ms) not in (int, float) or not math.isfinite(float(max_clock_drift_ms))
            or not 0 <= float(max_clock_drift_ms) <= 1000):
        raise BudgetError("--max-clock-drift-ms must be finite and between 0 and 1000")


def _write_new_trace(path: Path, events: list[dict[str, Any]]) -> None:
    created = False
    try:
        with path.open("x", encoding="utf-8", newline="\n") as stream:
            created = True
            json.dump(events, stream, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
            stream.write("\n")
    except (OSError, TypeError, ValueError, OverflowError, RecursionError) as error:
        if created:
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass
        raise BudgetError(f"cannot create trace output {path}: {error}") from error


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=Path, help="openrc-frametimes v2 JSON report")
    parser.add_argument("--resources", type=Path, help="openrc-resource-samples v1 JSON report")
    parser.add_argument("--out", type=Path, required=True, help="new Perfetto-compatible Chrome JSON trace path")
    parser.add_argument("--max-input-bytes", type=int, default=DEFAULT_MAX_INPUT_BYTES,
                        help="combined input byte budget (default 64 MiB, maximum 256 MiB)")
    parser.add_argument("--max-events", type=int, default=DEFAULT_MAX_EVENTS,
                        help="trace event budget (default 500000, maximum 1000000)")
    parser.add_argument("--max-clock-drift-ms", type=float, default=50.0,
                        help="maximum combined anchor drift allowance (0–1000 ms; default 50)")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.frames is None and args.resources is None:
            raise BudgetError("provide at least one of --frames or --resources")
        _validate_cli_budgets(args.max_input_bytes, args.max_events, args.max_clock_drift_ms)
        frames, resources = read_sources(
            frames_path=args.frames,
            resources_path=args.resources,
            max_input_bytes=args.max_input_bytes,
        )
        events, partial = build_trace(
            frames=frames,
            resources=resources,
            frame_source=str(args.frames) if args.frames else "frames.json",
            resource_source=str(args.resources) if args.resources else "resources.json",
            max_events=args.max_events,
            max_clock_drift_ms=args.max_clock_drift_ms,
        )
        _write_new_trace(args.out, events)
    except ExportError as error:
        print(f"perfetto_export: {error}", file=sys.stderr)
        return error.exit_code
    except OSError as error:
        print(f"perfetto_export: output error: {error}", file=sys.stderr)
        return 2
    print(f"wrote {len(events)} Perfetto events to {args.out}")
    if partial:
        print("perfetto_export: source capture is partial; exported retained prefix", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
