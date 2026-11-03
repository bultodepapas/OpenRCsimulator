#!/usr/bin/env python3
"""Export bounded OpenRC performance captures as legacy Perfetto JSON traces.

The trace contains wall-time frame intervals and sampled counter tracks. It does
not turn frame intervals into CPU slices or infer missing measurements.
"""
from __future__ import annotations

import argparse
from array import array
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import sys
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

try:
    from research.performance.native_summary import (
        STREAM_FORMAT, STREAM_MAX_BYTES, STREAM_MAX_FRAMES,
        _hydrate_stream_report, validate_native_report,
    )
except ImportError:  # Direct execution from a source checkout.
    from native_summary import (  # type: ignore[no-redef]
        STREAM_FORMAT, STREAM_MAX_BYTES, STREAM_MAX_FRAMES,
        _hydrate_stream_report, validate_native_report,
    )


DEFAULT_MAX_INPUT_BYTES = 320 * 1024 * 1024
MAX_INPUT_BYTES = 1024 * 1024 * 1024
MAX_JSON_BYTES = 256 * 1024 * 1024
DEFAULT_MAX_EVENTS = 500_000
MAX_EVENTS = 1_000_000
MAX_FRAME_SAMPLES = 120_000
MAX_RESOURCE_SAMPLES = 10_000
MAX_SAFE_INTEGER = (1 << 53) - 1
UNCERTAINTY_FLOOR_USEC = 20_000
RAW_UPTIME_DOMAIN = "darwin_mach_absolute_time"
RAW_UPTIME_MAX_INTERVAL_USEC = 100_000


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


class _StreamFrames(dict):
    """A strictly validated v3 pair, hydrated as compact arrays for export."""

    def __init__(self, report: dict[str, Any], stream_info: dict[str, Any]):
        super().__init__(report)
        self.stream_info = stream_info


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
_ALLOWED_FIELD_STATUSES = {
    "ok", "disabled", "insufficient_samples", "insufficient_elapsed_time",
    "dependency_unavailable", "counter_reset", "unsupported", "unknown",
    "invalid", "denied", "process_unavailable", "unavailable", "error",
}
_ENGINE_FRAME_METRICS = {"fps_monitor", "sim_tick", "sim_time_s", "invalid_value_count"}
_REQUIRED_RESOURCE_FIELDS = ("rss_bytes", "cpu_user_seconds", "cpu_system_seconds",
                             "virtual_memory_available_bytes")


def _strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON value {value} is forbidden")


def _read_json(path: Path, byte_limit: int) -> tuple[dict[str, Any], int, str]:
    # The larger aggregate allowance is for a streamed sidecar, not an
    # unbounded JSON document that would expand dramatically when parsed.
    byte_limit = min(byte_limit, MAX_JSON_BYTES)
    try:
        before = path.stat()
        if not stat.S_ISREG(before.st_mode):
            raise SourceError(f"source {path} must be a regular file")
        if before.st_size > byte_limit:
            raise BudgetError(f"combined source input exceeds the {byte_limit}-byte limit")
        flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NONBLOCK", 0)
        descriptor = os.open(path, flags)
        with os.fdopen(descriptor, "rb") as stream:
            current = os.fstat(stream.fileno())
            if not stat.S_ISREG(current.st_mode):
                raise SourceError(f"source {path} must be a regular file")
            if current.st_size > byte_limit:
                raise BudgetError(f"combined source input exceeds the {byte_limit}-byte limit")
            data = stream.read(byte_limit + 1)
    except ExportError:
        raise
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
    return value, len(data), hashlib.sha256(data).hexdigest()


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
        report_path = Path(frames_path)
        frames, consumed, report_sha256 = _read_json(report_path, max_input_bytes)
        if frames.get("format") == STREAM_FORMAT:
            stream = frames.get("stream")
            if not isinstance(stream, dict) or stream.get("file") != report_path.name + ".frames.jsonl":
                raise SourceError("stream file must be the report's same-directory sibling")
            remaining = max_input_bytes - consumed
            expected_bytes = stream.get("bytes")
            if type(expected_bytes) is int and expected_bytes > remaining:
                raise BudgetError(f"combined source input exceeds the {max_input_bytes}-byte limit")
            try:
                hydrated, stream_info = _hydrate_stream_report(
                    frames, report_path, include_metrics=True,
                    max_input_bytes=min(remaining, STREAM_MAX_BYTES),
                )
            except (OSError, UnicodeError, ValueError, TypeError, OverflowError, RecursionError, RuntimeError) as error:
                raise SourceError(f"frame stream failed validation: {error}") from error
            consumed += stream_info["bytes"]
            frames = _StreamFrames(hydrated, {**stream_info, "report_sha256": report_sha256})
    if resources_path is not None:
        resources, read, _resource_sha256 = _read_json(Path(resources_path), max_input_bytes - consumed)
        consumed += read
    return frames, resources


def _is_number(value: Any) -> bool:
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(float(value))
    except (OverflowError, TypeError, ValueError):
        return False


def _safe_integer(value: Any, label: str, *, positive: bool = False) -> int:
    if type(value) is not int or value < (1 if positive else 0) or value > MAX_SAFE_INTEGER:
        qualifier = "positive" if positive else "non-negative"
        raise SourceError(f"{label} must be a {qualifier} safe integer")
    return value


def _nonempty_string(value: Any, label: str, *, max_length: int = 256) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > max_length:
        raise SourceError(f"{label} must be a non-empty string of at most {max_length} characters")
    return value


def _metadata_string(value: Any, limit: int = 256) -> str | None:
    return value[:limit] if isinstance(value, str) else None


def _raw_uptime_interval(clock: dict[str, Any], label: str) -> dict[str, Any] | None:
    """Validate the two opt-in offset brackets for one producer clock.

    The bounds map producer monotonic microseconds to Darwin raw uptime. The
    same offset must be possible at both endpoints; UTC is not used here.
    """
    start, end = clock.get("start"), clock.get("end")
    if not isinstance(start, dict) or not isinstance(end, dict):
        raise SourceError(f"{label} clock anchors are missing")
    present = ["raw_uptime" in anchor for anchor in (start, end)]
    if not any(present):
        return None
    if not all(present):
        raise SourceError(f"{label} raw uptime anchors are incomplete")
    source = clock.get("source")
    if source not in ("godot_ticks_usec", "python_perf_counter", "clock_gettime(CLOCK_UPTIME_RAW)"):
        raise SourceError(f"{label} raw uptime clock source is incompatible")
    bounds: list[tuple[int, int]] = []
    helpers: list[str] = []
    for endpoint, anchor in (("start", start), ("end", end)):
        raw = anchor["raw_uptime"]
        if not isinstance(raw, dict) or raw.get("status") != "available" or raw.get("domain") != RAW_UPTIME_DOMAIN:
            raise SourceError(f"{label} {endpoint} raw uptime anchor is unavailable or has an incompatible domain")
        lower, upper = raw.get("offset_lower_usec"), raw.get("offset_upper_usec")
        if (type(lower) is not int or type(upper) is not int
                or not -MAX_SAFE_INTEGER <= lower <= upper <= MAX_SAFE_INTEGER
                or upper - lower > RAW_UPTIME_MAX_INTERVAL_USEC):
            raise SourceError(f"{label} {endpoint} raw uptime offset interval is invalid or too wide")
        if source == "clock_gettime(CLOCK_UPTIME_RAW)" and (lower != 0 or upper != 0):
            raise SourceError(f"{label} raw uptime clock must have zero offset")
        if source == "godot_ticks_usec":
            digest = raw.get("helper_sha256")
            if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
                raise SourceError(f"{label} {endpoint} raw uptime helper identity is missing or invalid")
            helpers.append(digest)
        bounds.append((lower, upper))
    if helpers and helpers[0] != helpers[1]:
        raise SourceError(f"{label} raw uptime helper identity changed between anchors")
    lower = max(bound[0] for bound in bounds)
    upper = min(bound[1] for bound in bounds)
    if lower > upper:
        raise SourceError(f"{label} raw uptime offset intervals do not overlap")
    midpoint = (lower + upper) // 2
    result = {"lower_usec": lower, "upper_usec": upper, "offset_usec": midpoint,
              "uncertainty_usec": max(midpoint - lower, upper - midpoint)}
    if helpers:
        result["helper_sha256"] = helpers[0]
    return result


def _validate_clock(value: Any, expected_source: str, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise SourceError(f"{label}.clock must be an object")
    source = value.get("source")
    if source != expected_source:
        raise SourceError(f"{label}.clock.source must be {expected_source!r}")
    origin = _safe_integer(value.get("origin_usec"), f"{label}.clock.origin_usec")
    anchors: dict[str, dict[str, Any]] = {}
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
        if "raw_uptime" in raw:
            anchors[endpoint]["raw_uptime"] = raw["raw_uptime"]
    if anchors["end"]["monotonic_usec"] <= anchors["start"]["monotonic_usec"]:
        raise SourceError(f"{label}.clock monotonic anchors must increase")
    normalized = {"source": source, "origin_usec": origin, **anchors}
    raw_interval = _raw_uptime_interval(normalized, f"{label}.clock")
    if raw_interval is None and anchors["end"]["unix_usec"] <= anchors["start"]["unix_usec"]:
        raise SourceError(f"{label}.clock wall-clock anchors must increase")
    return normalized


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
    if label == "frames" and report.get("capture_id") == "":
        # Direct engine invocations can lack the runner's capture identity.
        # They remain useful as a standalone relative trace, never as a join.
        return None
    return _nonempty_string(report.get("capture_id"), f"{label}.capture_id")


def _validate_frames(report: dict[str, Any]) -> tuple[dict[str, Any], bool, dict[str, Any] | None]:
    if report.get("format") != "openrc-frametimes v2":
        raise SourceError("frame source format must be 'openrc-frametimes v2'")
    count = report.get("frames")
    stream = isinstance(report, _StreamFrames)
    max_frames = STREAM_MAX_FRAMES if stream else MAX_FRAME_SAMPLES
    if type(count) is not int or not 1 <= count <= max_frames:
        raise SourceError(f"frames must be an integer between 1 and {max_frames}")
    array_types = (list, array) if stream else (list,)
    for key in ("frame_deltas_s", "frame_wall_usec", "frame_end_monotonic_usec"):
        values = report.get(key)
        if not isinstance(values, array_types) or len(values) != count:
            raise SourceError(f"{key} must contain exactly {count} samples")
    raw_metrics = report.get("raw_metrics")
    if not isinstance(raw_metrics, dict):
        raise SourceError("raw_metrics must be an object")
    for key, values in raw_metrics.items():
        if not isinstance(key, str) or not isinstance(values, array_types) or len(values) != count:
            raise SourceError(f"raw_metrics.{key} must contain exactly {count} samples")
        if key in _FRAME_METRICS:
            for index, value in enumerate(values):
                if _is_number(value) and float(value) < 0:
                    raise SourceError(f"raw_metrics.{key}[{index}] must be non-negative")
    invalid_counts = raw_metrics.get("invalid_value_count")
    if invalid_counts is not None:
        for index, value in enumerate(invalid_counts):
            if not _is_number(value) or value < 0 or not float(value).is_integer():
                raise SourceError(f"raw_metrics.invalid_value_count[{index}] must be a non-negative integer")

    _capture_id(report, "frames")
    _frame_clock(report)
    partial = report.get("complete") is False
    try:
        errors, derived = validate_native_report(report)
    except (RecursionError, OverflowError, TypeError, ValueError) as error:
        raise SourceError(f"frame source validation failed safely: {error}") from error
    if partial:
        # Retention caps and interrupted captures can legitimately stop before
        # the requested duration. Every raw-data consistency check still applies.
        prefix_conditions = {"report is marked incomplete", "raw frame sample is shorter than sample_s"}
        errors = [error for error in errors if error not in prefix_conditions]
    if errors or derived is None:
        preview = "; ".join(errors[:8]) if errors else "native frame validation produced no derived data"
        raise SourceError(f"frame source failed native validation: {preview}")
    return report, partial, derived


def _finite_nonnegative(value: Any, label: str) -> int | float:
    if not _is_number(value) or float(value) < 0:
        raise SourceError(f"{label} must be finite and non-negative")
    return value


def validate_required_coverage(report: dict[str, Any]) -> tuple[bool, list[str]]:
    """Check the additive required-channel receipt without upgrading legacy data."""
    if "required_field_counts" not in report:
        return False, []
    errors: list[str] = []
    counts = report.get("required_field_counts")
    samples = report.get("samples")
    if not isinstance(samples, list) or len(samples) > MAX_RESOURCE_SAMPLES:
        return False, ["required coverage samples must be a bounded array"]
    if type(report.get("sample_count")) is not int or report["sample_count"] != len(samples):
        errors.append("required coverage sample_count must match samples")
    if not isinstance(counts, dict) or set(counts) != set(_REQUIRED_RESOURCE_FIELDS):
        errors.append("required_field_counts must contain exactly the required channels")
        counts = {}
    summary = report.get("summary")
    resets = summary.get("counter_resets") if isinstance(summary, dict) else None
    if (not isinstance(resets, list) or len(resets) > 16
            or any(not isinstance(field, str) for field in resets)):
        errors.append("required coverage needs bounded counter_resets")
        resets = []
    actual = {field: 0 for field in _REQUIRED_RESOURCE_FIELDS}
    for index, sample in enumerate(samples):
        statuses = sample.get("field_status") if isinstance(sample, dict) else None
        if not isinstance(statuses, dict):
            errors.append(f"samples[{index}] has no required-channel statuses")
            break
        for field in _REQUIRED_RESOURCE_FIELDS:
            status = statuses.get(field)
            value = sample.get(field)
            if not isinstance(status, str) or status not in _ALLOWED_FIELD_STATUSES or field not in sample:
                errors.append(f"samples[{index}] has invalid {field} status or value")
                break
            if status == "ok":
                if not _is_number(value) or value < 0 or (field in _INTEGER_RESOURCE_FIELDS and type(value) is not int):
                    errors.append(f"samples[{index}] has invalid {field} value")
                    break
                actual[field] += 1
            elif value is not None:
                errors.append(f"samples[{index}] has a value for unavailable {field}")
                break
        if errors:
            break
    if not errors and any(type(counts.get(field)) is not int or counts[field] != actual[field]
                          for field in _REQUIRED_RESOURCE_FIELDS):
        errors.append("required_field_counts do not match sample statuses")
    capped = report.get("capped")
    stop_reason = report.get("stop_reason")
    if type(capped) is not bool or not isinstance(stop_reason, str) or not stop_reason:
        errors.append("required coverage needs capped and stop_reason")
    elif capped != (stop_reason == "sample_limit"):
        errors.append("required coverage cap and stop reason disagree")
    elif not errors:
        expected = ("capped" if capped else "unavailable" if not samples else
                    "complete" if (stop_reason == "caller_finished"
                    and not {"cpu_user_seconds", "cpu_system_seconds"}.intersection(resets) and all(
                        count == len(samples) for count in actual.values())) else "partial")
        if report.get("required_coverage") != expected:
            errors.append(f"required_coverage contradicts samples, cap or stop reason (expected {expected})")
    return not errors, errors


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
    if not isinstance(coverage, str) or coverage not in _ALLOWED_COVERAGE:
        raise SourceError("resource coverage must be sampled, partial, no_samples, or capped")
    measurement_status = report.get("measurement_status")
    if not isinstance(measurement_status, str) or measurement_status not in _ALLOWED_MEASUREMENT_STATUS:
        raise SourceError("resource measurement_status must be ok, partial, or unavailable")
    required_coverage = report.get("required_coverage")
    if required_coverage is not None and (not isinstance(required_coverage, str) or required_coverage not in {
            "complete", "partial", "capped", "unavailable"}):
        raise SourceError("resource required_coverage is unsupported")
    required_verified, required_errors = validate_required_coverage(report)
    if required_errors:
        raise SourceError("resource required coverage is invalid: " + "; ".join(required_errors[:8]))
    if (coverage == "no_samples") != (sample_count == 0):
        raise SourceError("no_samples coverage must agree with an empty samples array")
    if coverage == "capped" and report.get("capped") is not True:
        raise SourceError("capped coverage requires capped=true")
    if type(report.get("error_count")) is not int or not 0 <= report["error_count"] <= MAX_SAFE_INTEGER:
        raise SourceError("resource error_count must be a non-negative safe integer")
    if type(report.get("capped")) is not bool:
        raise SourceError("resource capped must be a boolean")
    if report["capped"] != (coverage == "capped"):
        raise SourceError("resource capped flag must agree with coverage")
    if (sample_count == 0) != (measurement_status == "unavailable"):
        raise SourceError("unavailable measurement status must agree with no_samples coverage")
    errors = report.get("errors")
    if not isinstance(errors, list) or len(errors) > 20:
        raise SourceError("resource errors must be an array of at most 20 entries")
    if type(report.get("errors_truncated")) is not bool:
        raise SourceError("resource errors_truncated must be a boolean")
    if report["error_count"] < len(errors) or report["errors_truncated"] != (report["error_count"] > len(errors)):
        raise SourceError("resource error_count/errors_truncated do not match the bounded errors array")
    for index, error in enumerate(errors):
        if (not isinstance(error, dict)
                or not isinstance(error.get("code"), str) or not 1 <= len(error["code"]) <= 80
                or not isinstance(error.get("field"), str) or not 1 <= len(error["field"]) <= 120
                or not isinstance(error.get("message"), str) or len(error["message"]) > 500):
            raise SourceError(f"resource errors[{index}] must have bounded code, field, and message strings")
    platform = report.get("platform")
    if platform is not None and (not isinstance(platform, str) or len(platform) > 128):
        raise SourceError("resource platform must be a short string")
    scope = report.get("scope")
    if scope is not None:
        if not isinstance(scope, dict) or len(scope) > 12:
            raise SourceError("resource scope must be an object with at most 12 entries")
        if any(not isinstance(key, str) or not isinstance(value, str) or len(value) > 500 for key, value in scope.items()):
            raise SourceError("resource scope values must be bounded strings")

    previous_elapsed = -1.0
    common_volume_paths: list[str] | None = None
    status_counts: dict[str, dict[str, int]] = {}
    normalized_samples: list[dict[str, Any]] = []
    partial = coverage != "sampled" or measurement_status != "ok" or report["error_count"] > 0
    partial = partial or (required_verified and required_coverage != "complete")
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
        if len(statuses) > 80:
            raise SourceError(f"samples[{index}].field_status exceeds the 80-entry schema limit")

        values: dict[str, int | float] = {}
        for field in _RESOURCE_METRICS:
            if field not in sample or field not in statuses:
                raise SourceError(f"samples[{index}] is missing {field} or its field_status")
            status = statuses[field]
            if not isinstance(status, str) or status not in _ALLOWED_FIELD_STATUSES:
                raise SourceError(f"samples[{index}].field_status.{field} must be a non-empty string")
            bucket = status_counts.setdefault(field, {})
            bucket[status] = bucket.get(status, 0) + 1
            value = sample[field]
            if status == "ok":
                value = _finite_nonnegative(value, f"samples[{index}].{field}")
                if field in _INTEGER_RESOURCE_FIELDS and type(value) is not int:
                    raise SourceError(f"samples[{index}].{field} must be an integer byte/count value")
                values[field] = value
            elif value is not None:
                raise SourceError(f"samples[{index}].{field} must be null when status is {status!r}")
            neutral_status = status == "ok" or (status == "disabled" and field == "num_threads")
            neutral_status = neutral_status or (
                status == "insufficient_samples" and field == "cpu_percent" and index == 0
            )
            if not neutral_status:
                partial = True

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
                if not isinstance(status, str) or status not in _ALLOWED_FIELD_STATUSES:
                    raise SourceError(f"samples[{index}].field_status.{status_key} must be a non-empty string")
                bucket = status_counts.setdefault(status_key, {})
                bucket[status] = bucket.get(status, 0) + 1
                value = volume[field]
                if status == "ok":
                    value = _finite_nonnegative(value, f"samples[{index}].volumes[{volume_index}].{field}")
                    if type(value) is not int:
                        raise SourceError(f"samples[{index}].volumes[{volume_index}].{field} must be an integer")
                    normalized_volume["values"][field] = value
                elif value is not None:
                    raise SourceError(f"samples[{index}].volumes[{volume_index}].{field} must be null when status is {status!r}")
                if status != "ok":
                    partial = True
            normalized_volumes.append(normalized_volume)
        if common_volume_paths is None:
            common_volume_paths = volume_paths
        elif volume_paths != common_volume_paths:
            raise SourceError("volume paths and order must remain stable across resource samples")
        expected_status_fields = set(_RESOURCE_METRICS)
        for volume_index in range(len(volumes)):
            expected_status_fields.update(f"volume[{volume_index}].{field}" for field in _VOLUME_FIELDS)
        if set(statuses) != expected_status_fields:
            raise SourceError(f"samples[{index}].field_status does not match the resource sample schema")

        normalized_samples.append({
            "elapsed_seconds": elapsed_float,
            "values": values,
            "volumes": normalized_volumes,
        })

    return report, partial, {
        "coverage": coverage,
        "measurement_status": measurement_status,
        "required_coverage": required_coverage,
        "required_coverage_validated": required_verified,
        "sample_count": sample_count,
        "error_count": report["error_count"],
        "capped": report["capped"],
        "stop_reason": report.get("stop_reason") if isinstance(report.get("stop_reason"), str) else None,
        "status_counts": status_counts,
        "partial_fields": {
            field: dict(statuses)
            for field, statuses in status_counts.items()
            if any(
                status != "ok"
                and not (status == "disabled" and field == "num_threads")
                and not (status == "insufficient_samples" and field == "cpu_percent" and count == 1)
                for status, count in statuses.items()
            )
        },
        "volume_paths": common_volume_paths or [],
        "samples": normalized_samples,
    }


def _effective_uncertainty(anchor: dict[str, int]) -> int:
    return max(anchor["uncertainty_usec"], UNCERTAINTY_FLOOR_USEC)


def _combined_clock(frame_clock: dict[str, Any], resource_clock: dict[str, Any],
                    max_clock_drift_ms: float) -> tuple[dict[str, Any], int, int]:
    max_drift_usec = int(round(max_clock_drift_ms * 1000.0))
    frame_raw = _raw_uptime_interval(frame_clock, "frame")
    resource_raw = _raw_uptime_interval(resource_clock, "resource")
    if (frame_raw is None) != (resource_raw is None):
        raise SourceError("combined raw uptime alignment requires valid anchors from both sources")
    frame_offset_start = frame_clock["start"]["unix_usec"] - frame_clock["start"]["monotonic_usec"]
    resource_offset_start = resource_clock["start"]["unix_usec"] - resource_clock["start"]["monotonic_usec"]
    frame_offset_end = frame_clock["end"]["unix_usec"] - frame_clock["end"]["monotonic_usec"]
    resource_offset_end = resource_clock["end"]["unix_usec"] - resource_clock["end"]["monotonic_usec"]
    frame_drift = abs(frame_offset_end - frame_offset_start)
    resource_drift = abs(resource_offset_end - resource_offset_start)
    if frame_raw is not None and resource_raw is not None:
        if (frame_clock.get("source") != "godot_ticks_usec"
                or resource_clock.get("source") not in ("python_perf_counter", "clock_gettime(CLOCK_UPTIME_RAW)")):
            raise SourceError("combined raw uptime clock sources are incompatible")
        metadata = {
            "mode": "aligned_raw_uptime",
            "domain": RAW_UPTIME_DOMAIN,
            "alignment": "producer monotonic timestamps plus the midpoint of their intersected raw uptime offset intervals",
            "combined_uncertainty_usec": frame_raw["uncertainty_usec"] + resource_raw["uncertainty_usec"],
            "uncertainty_semantics": "sum of conservative integer midpoint errors within endpoint offset intersections",
            "frame_raw_offset": frame_raw,
            "resource_raw_offset": resource_raw,
            "max_clock_drift_usec": 0,
            "utc_offset_drift_diagnostic_usec": {"frame": frame_drift, "resources": resource_drift},
            "utc_used_for_alignment": False,
            "identity_scope": ("offsets are producer declarations; callers must verify the frame helper and engine, "
                               "the resource clock implementation, and any host sleep check"),
        }
        return metadata, frame_raw["offset_usec"], resource_raw["offset_usec"]
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
        "uncertainty_semantics": "anchor uncertainty estimate, not a guaranteed operating-system bound",
        "effective_uncertainty_usec": {
            "frame_start": _effective_uncertainty(frame_clock["start"]),
            "frame_end": _effective_uncertainty(frame_clock["end"]),
            "resource_start": _effective_uncertainty(resource_clock["start"]),
            "resource_end": _effective_uncertainty(resource_clock["end"]),
        },
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


def _check_clock_coverage(clock: dict[str, Any], first_usec: int, last_usec: int,
                          label: str, max_clock_drift_ms: float) -> None:
    start = clock["start"]
    end = clock["end"]
    lower = start["monotonic_usec"] - _effective_uncertainty(start) - int(round(max_clock_drift_ms * 1000.0))
    upper = end["monotonic_usec"] + _effective_uncertainty(end) + int(round(max_clock_drift_ms * 1000.0))
    if first_usec < lower or last_usec > upper:
        raise SourceError(
            f"{label} sample timestamps fall outside their monotonic clock anchors "
            f"(data {first_usec}..{last_usec}, allowed {lower}..{upper})"
        )


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
                max_events: int = DEFAULT_MAX_EVENTS, max_clock_drift_ms: float = 50.0,
                start_frame: int | None = None, end_frame: int | None = None,
                selected_frame_metrics: list[str] | None = None) -> tuple[list[dict[str, Any]], bool]:
    """Validate sources and build Chrome JSON events; return events and partial flag."""
    if frames is None and resources is None:
        raise BudgetError("provide at least one source")
    if type(max_events) is not int or not 1 <= max_events <= MAX_EVENTS:
        raise BudgetError(f"max_events must be between 1 and {MAX_EVENTS}")
    if (type(max_clock_drift_ms) not in (int, float) or not _is_number(max_clock_drift_ms)
            or not 0 <= float(max_clock_drift_ms) <= 1000):
        raise BudgetError("max_clock_drift_ms must be finite and between 0 and 1000")

    normalized_frames = None
    frame_partial = False
    frame_derived = None
    if frames is not None:
        normalized_frames, frame_partial, frame_derived = _validate_frames(frames)
    elif start_frame is not None or end_frame is not None or selected_frame_metrics is not None:
        raise BudgetError("frame selection requires a frame source")
    selection_start = 0
    selection_end = 0
    selected_scope = False
    if normalized_frames is not None:
        frame_count = normalized_frames["frames"]
        selection_start = 0 if start_frame is None else start_frame
        selection_end = frame_count if end_frame is None else end_frame
        if (type(selection_start) is not int or type(selection_end) is not int
                or not 0 <= selection_start < selection_end <= frame_count):
            raise BudgetError(f"frame selection must satisfy 0 <= start < end <= {frame_count}")
        if selected_frame_metrics is not None:
            available = {key for key in normalized_frames["raw_metrics"] if key in _FRAME_METRICS}
            if (not isinstance(selected_frame_metrics, list)
                    or any(not isinstance(key, str) or key not in available for key in selected_frame_metrics)
                    or len(set(selected_frame_metrics)) != len(selected_frame_metrics)):
                raise BudgetError("selected frame metrics must be distinct known metrics present in the source")
            selected_scope = set(selected_frame_metrics) != available
        selected_scope = selected_scope or selection_start != 0 or selection_end != frame_count
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
    trace_zero = 0
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
        _check_clock_coverage(
            frame_clock, frame_frame_starts[0], int(normalized_frames["frame_end_monotonic_usec"][-1]),
            "frame", float(max_clock_drift_ms),
        )
        resource_samples = resource_info["samples"]
        if resource_samples:
            resource_first_monotonic = resource_clock["origin_usec"] + int(round(resource_samples[0]["elapsed_seconds"] * 1_000_000))
            resource_last_monotonic = resource_clock["origin_usec"] + int(round(resource_samples[-1]["elapsed_seconds"] * 1_000_000))
            _check_clock_coverage(
                resource_clock, resource_first_monotonic, resource_last_monotonic,
                "resource", float(max_clock_drift_ms),
            )
        timeline = "raw_uptime" if clock_metadata["mode"] == "aligned_raw_uptime" else "utc"
        frame_first_aligned = frame_frame_starts[0] + frame_offset
        if resource_samples:
            resource_first_aligned = resource_clock["origin_usec"] + int(round(resource_samples[0]["elapsed_seconds"] * 1_000_000)) + resource_offset
            frame_last_aligned = int(normalized_frames["frame_end_monotonic_usec"][-1]) + frame_offset
            resource_last_aligned = resource_clock["origin_usec"] + int(round(resource_samples[-1]["elapsed_seconds"] * 1_000_000)) + resource_offset
            overlap_allowance = clock_metadata["combined_uncertainty_usec"] + clock_metadata["max_clock_drift_usec"]
            if frame_last_aligned + overlap_allowance < resource_first_aligned or resource_last_aligned + overlap_allowance < frame_first_aligned:
                raise SourceError("clock-aligned frame and resource data windows do not overlap within the clock uncertainty allowance")
            clock_metadata[f"frame_data_{timeline}_bounds_usec"] = [frame_first_aligned, frame_last_aligned]
            clock_metadata[f"resource_data_{timeline}_bounds_usec"] = [resource_first_aligned, resource_last_aligned]
            clock_metadata["data_window_overlap_usec"] = max(
                0, min(frame_last_aligned, resource_last_aligned) - max(frame_first_aligned, resource_first_aligned)
            )
            selected_first_aligned = (int(normalized_frames["frame_end_monotonic_usec"][selection_start])
                                      - int(normalized_frames["frame_wall_usec"][selection_start]) + frame_offset)
            selected_last_aligned = int(normalized_frames["frame_end_monotonic_usec"][selection_end - 1]) + frame_offset
            clock_metadata[f"selected_frame_data_{timeline}_bounds_usec"] = [selected_first_aligned, selected_last_aligned]
            clock_metadata["resource_timestamps_bracket_full_frame_window"] = (
                resource_first_aligned <= frame_first_aligned and resource_last_aligned >= frame_last_aligned)
            clock_metadata["resource_timestamps_bracket_selected_frame_window"] = (
                resource_first_aligned <= selected_first_aligned and resource_last_aligned >= selected_last_aligned)
            clock_metadata["resource_time_scope"] = (
                "estimated timestamp endpoints only; uncertainty applies and discrete samples do not prove coverage between samples")
        else:
            resource_first_aligned = None
        trace_zero = (min(frame_first_aligned, resource_first_aligned)
                      if resource_first_aligned is not None else frame_first_aligned)
        trace_zero = _safe_integer(trace_zero, f"combined trace zero_{timeline}_usec")
        clock_metadata[f"zero_{timeline}_usec"] = trace_zero
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
            "frame_clock": frame_clock,
        }
    else:
        capture_id = _capture_id(normalized_resources, "resources")
        resource_offset = 0
        clock_metadata = {
            "mode": "relative_resource_timeline",
            "origin": "resource sampler elapsed_seconds",
            "source_clock_anchors_present": resource_clock is not None,
            "resource_clock": resource_clock,
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
    frame_metric_partial = False
    if normalized_frames is not None:
        raw_metrics = normalized_frames["raw_metrics"]
        frame_diagnostics = normalized_frames.get("frame_diagnostics")
        invalid_counts = raw_metrics.get("invalid_value_count")
        invalid_frame_indexes = {
            index for index, value in enumerate(invalid_counts or []) if float(value) > 0
        }
        gpu_available = (
            frame_diagnostics.get("render_timing_available")
            if isinstance(frame_diagnostics, dict) and type(frame_diagnostics.get("render_timing_available")) is bool
            else None
        )
        gpu_values = raw_metrics.get("render_gpu_ms")
        valid_gpu_values = [
            value for index, value in enumerate(gpu_values)
            if index not in invalid_frame_indexes
        ] if isinstance(gpu_values, (list, array)) else []
        gpu_zero_count = sum(value == 0 for value in valid_gpu_values)
        gpu_positive_count = sum(value > 0 for value in valid_gpu_values)
        gpu_contradictory = gpu_available is False and gpu_positive_count > 0
        available_frame_metrics = [key for key in raw_metrics if key in _FRAME_METRICS]
        frame_metrics = [key for key in available_frame_metrics
                         if selected_frame_metrics is None or key in selected_frame_metrics]
        unknown_metrics = [key for key in raw_metrics if key not in _FRAME_METRICS]
        unknown_metric_names = [str(key)[:128] for key in unknown_metrics[:32]]
        observer_samples_omitted = 0
        frame_metric_partial = bool(invalid_frame_indexes or gpu_contradictory)
        frame_gaps = normalized_frames.get("failure", "")
        if frame_partial:
            issues.append(f"frame capture is incomplete: {str(frame_gaps)[:500] or 'retained prefix'}")
        if unknown_metrics:
            issues.append("unexported frame metrics: " + ", ".join(unknown_metric_names))
        if invalid_frame_indexes:
            issues.append(
                f"observer counter samples omitted for {len(invalid_frame_indexes)} frame(s) "
                "with invalid_value_count > 0"
            )
        if gpu_contradictory:
            issues.append("positive GPU timer samples conflict with render_timing_available=false; GPU counters omitted")
        diagnostics_metadata: dict[str, Any] = {}
        if isinstance(frame_diagnostics, dict):
            for key in ("enabled", "headless", "render_timing_available"):
                if type(frame_diagnostics.get(key)) is bool:
                    diagnostics_metadata[key] = frame_diagnostics[key]
            if isinstance(frame_diagnostics.get("viewport_scope"), str):
                diagnostics_metadata["viewport_scope"] = frame_diagnostics["viewport_scope"][:256]
        sources["frames"] = {
            "file": Path(frame_source).name,
            "format": STREAM_FORMAT if isinstance(normalized_frames, _StreamFrames) else normalized_frames["format"],
            "complete": normalized_frames["complete"],
            "frame_count": normalized_frames["frames"],
            "route": _metadata_string(normalized_frames.get("route")),
            "case_id": _metadata_string(normalized_frames.get("case_id")),
            "backend": _metadata_string(normalized_frames.get("backend")),
            "raw_metric_names": frame_metrics,
            "available_metric_names": available_frame_metrics,
            "unknown_metric_names": unknown_metric_names,
            "unknown_metric_count": len(unknown_metrics),
            "invalid_observer_frame_count": len(invalid_frame_indexes),
            "observer_counter_samples_omitted": 0,
            "gpu_timer": {
                "timing_available": gpu_available,
                "zero_samples": gpu_zero_count,
                "positive_samples": gpu_positive_count,
                "interpretation": (
                    "contradictory_timing_unavailable" if gpu_contradictory else
                    "positive_samples_with_zero_sentinels" if gpu_positive_count and gpu_zero_count else
                    "measured_positive_samples" if gpu_positive_count else
                    "invalid_samples_omitted" if gpu_values is not None and invalid_frame_indexes else
                    "unavailable_or_zero" if gpu_values is not None else "not_reported"
                ),
                "invalid_frames_omitted": len(invalid_frame_indexes),
            },
            "frame_diagnostics": diagnostics_metadata,
            "selection": {
                "kind": "selected" if selected_scope else "full_session",
                "start_frame_inclusive": selection_start,
                "end_frame_exclusive": selection_end,
                "frame_count": selection_end - selection_start,
                "start_monotonic_usec": int(normalized_frames["frame_end_monotonic_usec"][selection_start])
                    - int(normalized_frames["frame_wall_usec"][selection_start]),
                "end_monotonic_usec": int(normalized_frames["frame_end_monotonic_usec"][selection_end - 1]),
                "metric_names": frame_metrics,
                "omitted_metric_names": [key for key in available_frame_metrics if key not in frame_metrics],
                "resource_scope": "all retained resource samples" if normalized_resources is not None else "none",
            },
        }
        if isinstance(normalized_frames, _StreamFrames):
            sources["frames"]["stream"] = normalized_frames.stream_info
        if isinstance(frame_diagnostics, dict):
            for issue in frame_diagnostics.get("issues", []) if isinstance(frame_diagnostics.get("issues"), list) else []:
                if isinstance(issue, str) and issue:
                    issues.append("frame diagnostic: " + issue[:500])

        # Count events before materializing any frame slices. A long capture can
        # exceed the cap by millions; callers must explicitly choose a scope.
        estimated_events = len(events) + 1 + selection_end - selection_start
        selected_invalid = sum(selection_start <= index < selection_end for index in invalid_frame_indexes)
        for key in frame_metrics:
            if key == "render_gpu_ms" and (gpu_contradictory or gpu_positive_count == 0):
                continue
            if key == "render_gpu_ms":
                estimated_events += sum(
                    raw_metrics[key][index] != 0 and index not in invalid_frame_indexes
                    for index in range(selection_start, selection_end))
            else:
                estimated_events += (selection_end - selection_start
                                     - (selected_invalid if key not in _ENGINE_FRAME_METRICS else 0))
        if resource_info is not None:
            estimated_events += sum(len(sample["values"]) + sum(len(volume["values"]) for volume in sample["volumes"])
                                    for sample in resource_info["samples"])
        if estimated_events > max_events:
            raise BudgetError(f"trace would contain {estimated_events} events, exceeding the {max_events}-event limit; "
                              "select a frame window or metrics")

        for index in range(selection_start, selection_end):
            end = normalized_frames["frame_end_monotonic_usec"][index]
            wall = normalized_frames["frame_wall_usec"][index]
            start = int(end) - int(wall)
            if normalized_resources is not None:
                ts = _chrome_timestamp(start + frame_offset - trace_zero, f"frames[{index}].ts")
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
            for index in range(selection_start, selection_end):
                value = values[index]
                if index in invalid_frame_indexes and key not in _ENGINE_FRAME_METRICS:
                    observer_samples_omitted += 1
                    continue
                if key == "render_gpu_ms" and value == 0:
                    continue
                end = int(normalized_frames["frame_end_monotonic_usec"][index])
                if normalized_resources is not None:
                    timestamp = end + frame_offset - trace_zero
                else:
                    timestamp = end + frame_offset
                _make_event(events, {
                    "pid": 1, "tid": 1, "ts": _chrome_timestamp(timestamp, f"{track}[{index}].ts"),
                    "ph": "C", "name": track, "cat": "frame_metric", "args": {"value": value},
                }, max_events)
        sources["frames"]["observer_counter_samples_omitted"] = observer_samples_omitted

    if normalized_resources is not None:
        report = normalized_resources
        if resource_partial:
            issues.append(
                f"resource capture coverage={resource_info['coverage']}, measurement_status={resource_info['measurement_status']}"
            )
        if resource_info["partial_fields"]:
            issues.append("resource fields contain unavailable samples: " + ", ".join(list(resource_info["partial_fields"])[:32]))
        if resource_info["error_count"]:
            issues.append(f"resource sampler reported {resource_info['error_count']} error(s)")
        for field, (scope, unit) in _RESOURCE_METRICS.items():
            for index, sample in enumerate(resource_info["samples"]):
                if field not in sample["values"]:
                    continue
                elapsed_usec = int(round(sample["elapsed_seconds"] * 1_000_000))
                if normalized_frames is not None:
                    monotonic = resource_clock["origin_usec"] + elapsed_usec
                    timestamp = monotonic + resource_offset - trace_zero
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
                        timestamp = monotonic + resource_offset - trace_zero
                    else:
                        timestamp = elapsed_usec
                    _make_event(events, {
                        "pid": 1, "tid": 2, "ts": _chrome_timestamp(timestamp, f"samples[{index}].{status_key}.ts"),
                        "ph": "C", "name": track, "cat": "resource_metric", "args": {"value": value},
                    }, max_events)
        sources["resources"] = {
            "file": Path(resource_source).name,
            "format": report["format"],
            "platform": _metadata_string(report.get("platform"), 128),
            "pid": report.get("pid") if type(report.get("pid")) is int and 0 <= report["pid"] <= MAX_SAFE_INTEGER else None,
            "process_create_time": report.get("process_create_time") if _is_number(report.get("process_create_time")) else None,
            "psutil_version": _metadata_string(report.get("psutil_version"), 64),
            "scope": report.get("scope", {}),
            "coverage": resource_info["coverage"],
            "measurement_status": resource_info["measurement_status"],
            "required_coverage": resource_info["required_coverage"],
            "required_coverage_validated": resource_info["required_coverage_validated"],
            "sample_count": resource_info["sample_count"],
            "error_count": resource_info["error_count"],
            "capped": resource_info["capped"],
            "stop_reason": resource_info["stop_reason"],
            "field_status_counts": resource_info["status_counts"],
            "partial_fields": resource_info["partial_fields"],
            "volume_paths": resource_info["volume_paths"],
        }
        source_errors = report.get("errors")
        if isinstance(source_errors, list):
            for error in source_errors[:20]:
                if isinstance(error, dict):
                    code = error.get("code")
                    field = error.get("field")
                    message = error.get("message")
                    if all(isinstance(part, str) for part in (code, field, message)):
                        issues.append(f"resource {code} {field}: {message[:300]}")

    partial = frame_partial or resource_partial or frame_metric_partial
    metadata = {
        "capture_id": capture_id,
        "complete": not partial and not selected_scope,
        "partial": partial or selected_scope,
        "source_data_complete": not partial,
        "selected_scope_complete": not partial,
        "full_session_timeline": not selected_scope,
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
    return events, partial


def _validate_cli_budgets(max_input_bytes: int, max_events: int, max_clock_drift_ms: float) -> None:
    if type(max_input_bytes) is not int or not 1 <= max_input_bytes <= MAX_INPUT_BYTES:
        raise BudgetError(f"--max-input-bytes must be between 1 and {MAX_INPUT_BYTES}")
    if type(max_events) is not int or not 1 <= max_events <= MAX_EVENTS:
        raise BudgetError(f"--max-events must be between 1 and {MAX_EVENTS}")
    if (type(max_clock_drift_ms) not in (int, float) or not _is_number(max_clock_drift_ms)
            or not 0 <= float(max_clock_drift_ms) <= 1000):
        raise BudgetError("--max-clock-drift-ms must be finite and between 0 and 1000")


def _write_new_trace(path: Path, events: list[dict[str, Any]]) -> None:
    created = False
    identity = None
    try:
        with path.open("x", encoding="utf-8", newline="\n") as stream:
            created = True
            info = os.fstat(stream.fileno())
            identity = (info.st_dev, info.st_ino)
            json.dump(events, stream, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
            stream.write("\n")
    except (OSError, TypeError, ValueError, OverflowError, RecursionError) as error:
        if created and identity is not None:
            try:
                current = os.lstat(path)
                if (current.st_dev, current.st_ino) == identity:
                    path.unlink()
            except OSError:
                pass
        raise BudgetError(f"cannot create trace output {path}: {error}") from error


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=Path, help="openrc-frametimes v2 report or v3 report with sibling sidecar")
    parser.add_argument("--resources", type=Path, help="openrc-resource-samples v1 JSON report")
    parser.add_argument("--out", type=Path, required=True, help="new Perfetto-compatible Chrome JSON trace path")
    parser.add_argument("--max-input-bytes", type=int, default=DEFAULT_MAX_INPUT_BYTES,
                        help="combined input byte budget (default 320 MiB, maximum 1 GiB)")
    parser.add_argument("--max-events", type=int, default=DEFAULT_MAX_EVENTS,
                        help="trace event budget (default 500000, maximum 1000000)")
    parser.add_argument("--max-clock-drift-ms", type=float, default=50.0,
                        help="UTC anchor drift allowance for legacy joins (0–1000 ms; default 50); raw uptime uses offset bounds")
    parser.add_argument("--start-frame", type=int, help="first frame index to export, inclusive (default 0)")
    parser.add_argument("--end-frame", type=int, help="last frame index to export, exclusive (default source count)")
    parser.add_argument("--frame-metric", action="append", choices=sorted(_FRAME_METRICS),
                        help="export this frame metric; repeat to select tracks (default: all known metrics)")
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
            start_frame=args.start_frame,
            end_frame=args.end_frame,
            selected_frame_metrics=args.frame_metric,
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
