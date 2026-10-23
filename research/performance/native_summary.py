#!/usr/bin/env python3
"""Validate and summarize VQ-01b native frame-time reports.

This reducer checks collection integrity, active-flight eligibility, and the
declared pacing policy separately. It does not establish aircraft, pilot, or
hardware acceptance. When recorded, installed lake-reflection mode must be
consistent across a campaign; this is not a render-quality qualification.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any, Sequence

try:
    from .session_baseline import percentile_nearest_rank
except ImportError:  # Direct execution adds this directory to sys.path.
    from session_baseline import percentile_nearest_rank


FORMAT = "openrc-frametimes v2"
SUMMARY_FORMAT = "openrc-native-frame-summary v1"
DEFAULT_POLICY = {
    "p95_max_ms": 18.0,
    "p99_max_ms": 25.0,
    "simulation_wall_ratio_min": 0.99,
    "simulation_wall_ratio_max": 1.01,
    "active_nonadvancing_interval_max_usec": 250_000,
    "minimum_warmup_s": 10.0,
    "minimum_sample_s": 60.0,
    "minimum_runs": 3,
}
ENGINE_ERROR_RE = re.compile(r"\b(?:SCRIPT\s+)?ERROR(?:\s*:|\b)", re.IGNORECASE)


def _is_number(value: Any) -> bool:
    return type(value) in (int, float) and math.isfinite(float(value))


def _is_int(value: Any) -> bool:
    return type(value) is int


def _reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON value {value} is forbidden")


def _finite_tree(value: Any, path: str = "report") -> list[str]:
    errors: list[str] = []
    if isinstance(value, float) and not math.isfinite(value):
        errors.append(f"{path} must be finite")
    elif isinstance(value, dict):
        for key, child in value.items():
            errors.extend(_finite_tree(child, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            errors.extend(_finite_tree(child, f"{path}[{index}]"))
    return errors


def _finite_field(container: dict[str, Any], key: str, errors: list[str], label: str) -> float | None:
    value = container.get(key)
    if not _is_number(value):
        errors.append(f"{label}.{key} must be a finite number")
        return None
    return float(value)


def _array_numbers(value: Any, label: str, errors: list[str], *, positive: bool = False) -> list[float] | None:
    if not isinstance(value, list):
        errors.append(f"{label} must be an array")
        return None
    result: list[float] = []
    for index, item in enumerate(value):
        if not _is_number(item):
            errors.append(f"{label}[{index}] must be a finite number")
            continue
        number = float(item)
        if positive and number <= 0:
            errors.append(f"{label}[{index}] must be positive")
        result.append(number)
    return result


def _array_ints(value: Any, label: str, errors: list[str], *, positive: bool = False) -> list[int] | None:
    if not isinstance(value, list):
        errors.append(f"{label} must be an array")
        return None
    result: list[int] = []
    for index, item in enumerate(value):
        if not _is_int(item) or item < (1 if positive else 0):
            qualifier = "positive" if positive else "non-negative"
            errors.append(f"{label}[{index}] must be a {qualifier} integer")
            continue
        result.append(item)
    return result


def _close(left: float, right: float, *, tolerance: float = 1e-6) -> bool:
    return math.isclose(left, right, rel_tol=0.0, abs_tol=tolerance)


LAKE_REFLECTION_MODES = {"absent", "probe", "planar"}


def _lake_reflection_settings(report: dict[str, Any]) -> tuple[bool, Any]:
    render_settings = report.get("render_settings")
    if not isinstance(render_settings, dict) or "lake_reflections" not in render_settings:
        return False, None
    return True, render_settings["lake_reflections"]


def _lake_reflection_mode(report: dict[str, Any]) -> str | None:
    present, settings = _lake_reflection_settings(report)
    if not present or not isinstance(settings, dict):
        return None
    mode = settings.get("mode")
    return mode if isinstance(mode, str) and mode in LAKE_REFLECTION_MODES else None


def _validate_lake_reflection_settings(report: dict[str, Any], errors: list[str]) -> None:
    if "render_settings" in report and not isinstance(report["render_settings"], dict):
        errors.append("render_settings must be an object")
        return
    present, settings = _lake_reflection_settings(report)
    if not present:
        # Historical reports did not record the installed lake reflection path.
        return
    label = "render_settings.lake_reflections"
    if not isinstance(settings, dict):
        errors.append(f"{label} must be an object")
        return

    requested = settings.get("requested")
    if not isinstance(requested, str):
        errors.append(f"{label}.requested must be a string")
    elif requested != requested.strip().lower():
        errors.append(f"{label}.requested must be normalized to lowercase without surrounding whitespace")

    mode = settings.get("mode")
    if not isinstance(mode, str) or mode not in LAKE_REFLECTION_MODES:
        errors.append(f"{label}.mode must be one of absent, probe, or planar")

    active = settings.get("planar_active_at_report")
    if type(active) is not bool:
        errors.append(f"{label}.planar_active_at_report must be a boolean")

    size = settings.get("capture_size_at_report")
    if not isinstance(size, list) or len(size) != 2:
        errors.append(f"{label}.capture_size_at_report must contain exactly two integers")
    elif any(type(dimension) is not int or dimension < 0 for dimension in size):
        errors.append(f"{label}.capture_size_at_report dimensions must be non-negative integers")
    else:
        zero_size = size == [0, 0]
        positive_size = size[0] > 0 and size[1] > 0
        if not zero_size and not positive_size:
            errors.append(f"{label}.capture_size_at_report must be [0, 0] or two positive dimensions")
        if active is True and (mode != "planar" or not positive_size):
            errors.append(f"{label}.planar_active_at_report requires planar mode and a positive capture size")
        if mode in ("absent", "probe") and (active is not False or not zero_size):
            errors.append(f"{label} non-planar mode requires inactive reflection and capture size [0, 0]")


def validate_native_report(report: Any) -> tuple[list[str], dict[str, Any] | None]:
    """Validate v2 structure and derive values from the raw samples."""
    if not isinstance(report, dict):
        return ["report must be a JSON object"], None

    errors = _finite_tree(report)
    if report.get("format") != FORMAT:
        errors.append(f"format must be {FORMAT!r}")
    version = report.get("version")
    if not _is_int(version) or version != 2:
        errors.append("version must be integer 2")

    complete = report.get("complete")
    if type(complete) is not bool:
        errors.append("complete must be a boolean")
    elif not complete:
        errors.append("report is marked incomplete")
    failure = report.get("failure")
    if not isinstance(failure, str):
        errors.append("failure must be a string")
    elif complete is True and failure:
        errors.append("complete report must have an empty failure string")

    for key in ("route", "case_id", "aircraft_id", "preset", "backend"):
        value = report.get(key)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{key} must be a non-empty string")

    # Additive v2 metadata: unknown in historical reports, never inferred as uncapped.
    if "max_fps" in report and (not _is_int(report["max_fps"]) or report["max_fps"] < 0):
        errors.append("max_fps must be a non-negative integer")
    if "vsync_mode" in report:
        mode = report["vsync_mode"]
        if not _is_int(mode) or mode not in (0, 1, 2, 3):
            errors.append("vsync_mode must be an integer from 0 through 3")
        elif "vsync" in report and (type(report["vsync"]) is not bool or report["vsync"] != (mode != 0)):
            errors.append("vsync must agree with vsync_mode")

    _validate_lake_reflection_settings(report, errors)

    input_enabled = report.get("input_enabled")
    if type(input_enabled) is not bool:
        errors.append("input_enabled must be a boolean")

    frames = report.get("frames")
    if not _is_int(frames) or frames < 1:
        errors.append("frames must be a positive integer")
        frames = None

    deltas = _array_numbers(report.get("frame_deltas_s"), "frame_deltas_s", errors, positive=True)
    wall_usec = _array_ints(report.get("frame_wall_usec"), "frame_wall_usec", errors, positive=True)
    frame_ends = _array_ints(report.get("frame_end_monotonic_usec"), "frame_end_monotonic_usec", errors, positive=True)
    for label, array in (("frame_deltas_s", deltas), ("frame_wall_usec", wall_usec), ("frame_end_monotonic_usec", frame_ends)):
        if frames is not None and array is not None and len(array) != frames:
            errors.append(f"{label} length must equal frames")

    if frame_ends is not None and any(right <= left for left, right in zip(frame_ends, frame_ends[1:])):
        errors.append("frame_end_monotonic_usec must be strictly increasing")
    if wall_usec is not None and frame_ends is not None and len(wall_usec) == len(frame_ends):
        for index in range(1, len(wall_usec)):
            if wall_usec[index] != frame_ends[index] - frame_ends[index - 1]:
                errors.append(f"frame_wall_usec[{index}] must match consecutive monotonic endpoints")
                break
    if deltas is not None and wall_usec is not None and len(deltas) == len(wall_usec):
        for index, (delta_s, delta_usec) in enumerate(zip(deltas, wall_usec)):
            if not _close(delta_s, delta_usec / 1_000_000.0, tolerance=1.1e-6):
                errors.append(f"frame_deltas_s[{index}] does not match frame_wall_usec")
                break

    raw_metrics = report.get("raw_metrics")
    raw_ticks: list[float] | None = None
    raw_times: list[float] | None = None
    if not isinstance(raw_metrics, dict):
        errors.append("raw_metrics must be an object")
    else:
        if "sim_tick" not in raw_metrics or "sim_time_s" not in raw_metrics:
            errors.append("raw_metrics must include sim_tick and sim_time_s")
        for key, samples in raw_metrics.items():
            parsed = _array_numbers(samples, f"raw_metrics.{key}", errors)
            if frames is not None and parsed is not None and len(parsed) != frames:
                errors.append(f"raw_metrics.{key} length must equal frames")
            if key == "sim_tick":
                raw_ticks = parsed
                if parsed is not None and any(not float(value).is_integer() for value in parsed):
                    errors.append("raw_metrics.sim_tick values must be integer-valued")
            elif key == "sim_time_s":
                raw_times = parsed

    if raw_ticks is not None and any(right < left for left, right in zip(raw_ticks, raw_ticks[1:])):
        errors.append("raw_metrics.sim_tick must not decrease")
    if raw_times is not None and any(right < left for left, right in zip(raw_times, raw_times[1:])):
        errors.append("raw_metrics.sim_time_s must not decrease")

    measured = report.get("measured_simulation")
    measured_start_time = measured_end_time = None
    measured_start_tick = measured_end_tick = measured_ticks = None
    if not isinstance(measured, dict):
        errors.append("measured_simulation must be an object")
    else:
        scope = measured.get("scope")
        if not isinstance(scope, str) or not scope.strip():
            errors.append("measured_simulation.scope must be a non-empty string")
        measured_start_time = _finite_field(measured, "start_time_s", errors, "measured_simulation")
        measured_end_time = _finite_field(measured, "end_time_s", errors, "measured_simulation")
        for key in ("start_tick", "end_tick", "ticks"):
            value = measured.get(key)
            if not _is_int(value) or value < 0:
                errors.append(f"measured_simulation.{key} must be a non-negative integer")
        measured_start_tick = measured.get("start_tick") if _is_int(measured.get("start_tick")) else None
        measured_end_tick = measured.get("end_tick") if _is_int(measured.get("end_tick")) else None
        measured_ticks = measured.get("ticks") if _is_int(measured.get("ticks")) else None
        if measured_start_tick is not None and measured_end_tick is not None and measured_ticks is not None:
            if measured_ticks != measured_end_tick - measured_start_tick:
                errors.append("measured_simulation.ticks must equal end_tick - start_tick")

    if raw_ticks and raw_times and measured_start_tick is not None and measured_end_tick is not None:
        if measured_start_tick != int(raw_ticks[0]) or measured_end_tick != int(raw_ticks[-1]):
            errors.append("measured_simulation start/end ticks must match the raw sample endpoints")
    if raw_times and measured_start_time is not None and measured_end_time is not None:
        if not _close(measured_start_time, raw_times[0]) or not _close(measured_end_time, raw_times[-1]):
            errors.append("measured_simulation start/end times must match the raw sample endpoints")

    simulation = report.get("simulation")
    paused: bool | None = None
    physics_enabled: bool | None = None
    fault: str | None = None
    tick_hz: int | None = None
    if not isinstance(simulation, dict):
        errors.append("simulation must be an object")
    else:
        paused_value = simulation.get("paused")
        if type(paused_value) is not bool:
            errors.append("simulation.paused must be a boolean")
        else:
            paused = paused_value
        physics_value = simulation.get("physics_enabled")
        if type(physics_value) is not bool:
            errors.append("simulation.physics_enabled must be a boolean")
        else:
            physics_enabled = physics_value
        fault_value = simulation.get("fault")
        if not isinstance(fault_value, str):
            errors.append("simulation.fault must be a string")
        else:
            fault = fault_value
        rate = simulation.get("physics_ticks_per_second")
        if not _is_int(rate) or rate <= 0:
            errors.append("simulation.physics_ticks_per_second must be a positive integer")
        else:
            tick_hz = rate
            if rate != 240:
                errors.append("simulation.physics_ticks_per_second must equal 240")

    sample_s = _finite_field(report, "sample_s", errors, "report")
    warmup_s = _finite_field(report, "warmup_s", errors, "report")
    actual_sample_s = _finite_field(report, "actual_sample_s", errors, "report")
    wall_seconds = _finite_field(report, "wall_seconds", errors, "report")
    seconds = _finite_field(report, "seconds", errors, "report")
    actual_warmup_s = _finite_field(report, "actual_warmup_s", errors, "report")
    if sample_s is not None and sample_s <= 0:
        errors.append("sample_s must be positive")
    if warmup_s is not None and warmup_s < 0:
        errors.append("warmup_s must be non-negative")
    if actual_warmup_s is not None and actual_warmup_s < 0:
        errors.append("actual_warmup_s must be non-negative")
    if deltas is not None and deltas:
        total_s = sum(deltas)
        for key, value in (("actual_sample_s", actual_sample_s), ("wall_seconds", wall_seconds), ("seconds", seconds)):
            if value is not None and not _close(value, total_s, tolerance=max(1e-6, len(deltas) * 1e-12)):
                errors.append(f"{key} must equal the sum of frame_deltas_s")
        if sample_s is not None and total_s + 1e-6 < sample_s:
            errors.append("raw frame sample is shorter than sample_s")
        if sample_s is not None and total_s - deltas[-1] > sample_s + 1e-6:
            errors.append("raw frame sample exceeds sample_s by more than one frame")

    frame_ms = report.get("frame_ms")
    derived_frame_ms: dict[str, float] | None = None
    if not isinstance(frame_ms, dict):
        errors.append("frame_ms must be an object")
    else:
        for key in ("p50", "p95", "p99", "max"):
            _finite_field(frame_ms, key, errors, "frame_ms")
    if deltas:
        derived_frame_ms = {
            f"p{percentile}": float(percentile_nearest_rank([value * 1000.0 for value in deltas], percentile))
            for percentile in (50, 95, 99)
        }
        derived_frame_ms["max"] = max(deltas) * 1000.0
        if isinstance(frame_ms, dict):
            for key, expected in derived_frame_ms.items():
                reported = frame_ms.get(key)
                if _is_number(reported) and not _close(float(reported), expected, tolerance=1e-5):
                    errors.append(f"frame_ms.{key} does not match the raw frame samples")

    derived: dict[str, Any] | None = None
    if (
        deltas and wall_usec and frame_ends and raw_ticks and raw_times
        and measured_ticks is not None and measured_start_time is not None and measured_end_time is not None
        and tick_hz is not None
    ):
        wall_span_s = (frame_ends[-1] - frame_ends[0]) / 1_000_000.0 if len(frame_ends) > 1 else 0.0
        sim_span_s = raw_times[-1] - raw_times[0]
        tick_span = int(raw_ticks[-1]) - int(raw_ticks[0])
        simulation_wall_ratio = sim_span_s / wall_span_s if wall_span_s > 0 else None
        tick_wall_ratio = (tick_span / float(tick_hz)) / wall_span_s if wall_span_s > 0 else None
        no_progress_usec = 0
        max_no_progress_usec = 0
        if len(frame_ends) > 1:
            for index in range(1, min(len(frame_ends), len(raw_ticks))):
                interval_usec = frame_ends[index] - frame_ends[index - 1]
                if raw_ticks[index] <= raw_ticks[index - 1]:
                    no_progress_usec += interval_usec
                    max_no_progress_usec = max(max_no_progress_usec, no_progress_usec)
                else:
                    no_progress_usec = 0
        derived = {
            "frame_ms": derived_frame_ms,
            "sample_wall_span_excluding_first_interval_s": wall_span_s,
            "sample_simulation_span_s": sim_span_s,
            "sample_simulation_ticks": tick_span,
            "simulation_wall_ratio": simulation_wall_ratio,
            "tick_wall_ratio": tick_wall_ratio,
            "max_frame_interval_usec": max(wall_usec),
            "max_nonadvancing_interval_usec": max_no_progress_usec,
        }
        if measured_ticks != tick_span:
            errors.append("measured_simulation.ticks must match raw sim_tick endpoint difference")
        if not _close(measured_end_time - measured_start_time, sim_span_s):
            errors.append("measured_simulation elapsed time must match raw sim_time_s endpoints")
        if not _close(sim_span_s, tick_span / float(tick_hz), tolerance=1e-6):
            errors.append("raw sim_time_s span must match sim_tick span / physics tick rate")

    return errors, derived


def active_flight_reasons(report: dict[str, Any], derived: dict[str, Any], policy: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    if report.get("route") != "live-input":
        reasons.append("route is not live-input")
    if report.get("input_enabled") is not True:
        reasons.append("input is disabled")
    simulation = report.get("simulation")
    if not isinstance(simulation, dict):
        reasons.append("simulation state is unavailable")
        simulation = {}
    if simulation.get("physics_enabled") is not True:
        reasons.append("simulation physics is disabled")
    if simulation.get("paused") is not False:
        reasons.append("simulation was paused")
    if simulation.get("fault") != "":
        reasons.append("simulation reported a fault")
    if derived.get("sample_simulation_ticks", 0) <= 0 or derived.get("sample_simulation_span_s", 0.0) <= 0:
        reasons.append("simulation did not advance during the measured sample")
    if derived.get("max_nonadvancing_interval_usec", 0) > policy["active_nonadvancing_interval_max_usec"]:
        reasons.append("simulation did not advance for more than 250 ms")
    return reasons


def pacing_gate(derived: dict[str, Any], policy: dict[str, Any]) -> dict[str, Any]:
    values = derived["frame_ms"]
    ratio = derived["simulation_wall_ratio"]
    p95_pass = values["p95"] <= policy["p95_max_ms"]
    p99_pass = values["p99"] <= policy["p99_max_ms"]
    ratio_pass = ratio is not None and policy["simulation_wall_ratio_min"] <= ratio <= policy["simulation_wall_ratio_max"]
    return {
        "p95_max_ms": policy["p95_max_ms"],
        "p95_pass": p95_pass,
        "p99_max_ms": policy["p99_max_ms"],
        "p99_pass": p99_pass,
        "simulation_wall_ratio_min": policy["simulation_wall_ratio_min"],
        "simulation_wall_ratio_max": policy["simulation_wall_ratio_max"],
        "simulation_wall_ratio_pass": ratio_pass,
        "pass": p95_pass and p99_pass and ratio_pass,
    }


def duration_gate(report: dict[str, Any], policy: dict[str, Any]) -> dict[str, Any]:
    """Keep short smoke captures out of the sustained-performance result."""
    requested_warmup = report.get("warmup_s")
    requested_sample = report.get("sample_s")
    actual_warmup = report.get("actual_warmup_s")
    reasons: list[str] = []
    if not _is_number(requested_warmup):
        reasons.append("requested warm-up duration is unavailable")
    elif requested_warmup < policy["minimum_warmup_s"]:
        reasons.append(f"requested warm-up is shorter than {policy['minimum_warmup_s']:g} s")
    if not _is_number(requested_sample):
        reasons.append("requested sample duration is unavailable")
    elif requested_sample < policy["minimum_sample_s"]:
        reasons.append(f"requested sample is shorter than {policy['minimum_sample_s']:g} s")
    if not _is_number(actual_warmup):
        reasons.append("actual warm-up duration is unavailable")
    elif _is_number(requested_warmup) and actual_warmup + 1e-6 < requested_warmup:
        reasons.append("actual warm-up is shorter than requested")
    return {
        "minimum_warmup_s": policy["minimum_warmup_s"],
        "minimum_sample_s": policy["minimum_sample_s"],
        "requested_warmup_s": requested_warmup if _is_number(requested_warmup) else None,
        "requested_sample_s": requested_sample if _is_number(requested_sample) else None,
        "actual_warmup_s": actual_warmup if _is_number(actual_warmup) else None,
        "eligible": not reasons,
        "reasons": reasons,
    }


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _log_error_lines(log_text: str) -> list[str]:
    clean = re.sub(r"\x1b\[[0-9;]*m", "", log_text)
    return [line.strip() for line in clean.splitlines() if ENGINE_ERROR_RE.search(line)]


def _decode_log(log_bytes: bytes) -> str:
    if log_bytes.startswith((b"\xff\xfe", b"\xfe\xff")):
        return log_bytes.decode("utf-16")
    if log_bytes.startswith(b"\xef\xbb\xbf"):
        return log_bytes.decode("utf-8-sig")
    return log_bytes.decode("utf-8")


def summarize_run(report_path: Path, policy: dict[str, Any]) -> dict[str, Any]:
    report_bytes: bytes | None = None
    log_bytes: bytes | None = None
    report: dict[str, Any] | None = None
    errors: list[str] = []
    report_format: str | None = None
    log_path = report_path.with_suffix(".log")

    try:
        report_bytes = report_path.read_bytes()
        report = json.loads(report_bytes.decode("utf-8"), parse_constant=_reject_constant)
        if isinstance(report, dict):
            value = report.get("format")
            report_format = value if isinstance(value, str) else None
        else:
            errors.append("report must be a JSON object")
            report = None
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        errors.append(f"report is unreadable or malformed: {error}")

    engine_errors: list[str] = []
    log_decode_error: str | None = None
    try:
        log_bytes = log_path.read_bytes()
        try:
            log_text = _decode_log(log_bytes)
        except UnicodeError as error:
            log_decode_error = f"matching log encoding is invalid: {error}"
            log_text = log_bytes.decode("utf-8", errors="replace")
        engine_errors = _log_error_lines(log_text)
    except OSError as error:
        errors.append(f"matching log is unavailable: {error}")
    if log_decode_error:
        errors.append(log_decode_error)
    if engine_errors:
        errors.append("matching log contains Godot ERROR output")

    derived: dict[str, Any] | None = None
    if report is not None:
        schema_errors, derived = validate_native_report(report)
        errors.extend(schema_errors)

    collection_valid = not errors
    active_reasons: list[str] = []
    pacing: dict[str, Any] | None = None
    duration: dict[str, Any] | None = None
    if report is not None and derived is not None:
        active_reasons = active_flight_reasons(report, derived, policy)
        pacing = pacing_gate(derived, policy)
        duration = duration_gate(report, policy)
    else:
        active_reasons.append("active-flight status cannot be derived from an invalid report")
        duration = {
            "minimum_warmup_s": policy["minimum_warmup_s"],
            "minimum_sample_s": policy["minimum_sample_s"],
            "requested_warmup_s": None,
            "requested_sample_s": None,
            "actual_warmup_s": None,
            "eligible": False,
            "reasons": ["duration eligibility cannot be derived from an invalid report"],
        }

    lake_reflection_mode = _lake_reflection_mode(report) if report is not None else None
    active_qualifier = collection_valid and not active_reasons
    if not collection_valid and "collection is invalid" not in active_reasons:
        active_reasons.append("collection is invalid")
    performance_pass = bool(
        collection_valid and active_qualifier and duration and duration["eligible"]
        and pacing and pacing["pass"]
    )
    return {
        "report": report_path.name,
        "report_format": report_format,
        "report_sha256": _sha256_bytes(report_bytes) if report_bytes is not None else None,
        "log": log_path.name,
        "log_sha256": _sha256_bytes(log_bytes) if log_bytes is not None else None,
        "engine_errors": engine_errors,
        "collection_valid": collection_valid,
        "collection_reasons": errors,
        "active_flight_qualifier": active_qualifier,
        "active_flight_reasons": active_reasons,
        "duration_eligibility": duration,
        "metrics": derived,
        "pacing_gate": pacing,
        "pacing_configuration": {
            "max_fps": report.get("max_fps") if report is not None else None,
            "vsync_mode": report.get("vsync_mode") if report is not None else None,
        },
        "lake_reflection_configuration": (
            {"mode": lake_reflection_mode} if lake_reflection_mode is not None else None
        ),
        "performance_pass": performance_pass,
        "hardware_acceptance": "not_claimed",
    }


def _write_json(path: Path, value: Any) -> None:
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")
    temporary.replace(path)


def summarize_directory(input_dir: Path, output_file: Path, policy: dict[str, Any] | None = None) -> tuple[dict[str, Any], int]:
    policy = dict(DEFAULT_POLICY if policy is None else policy)
    input_dir = input_dir.resolve()
    output_file = output_file.resolve()
    if not input_dir.is_dir():
        raise ValueError(f"input must be a directory: {input_dir}")
    if output_file.exists():
        raise ValueError(f"output must be a new file: {output_file}")
    reports = sorted(input_dir.glob("run-*.json"), key=lambda item: item.name.casefold())
    runs = [summarize_run(path, policy) for path in reports]
    if not reports:
        failures = ["no run-*.json reports found"]
    else:
        failures = []
    collection_valid = bool(runs) and all(run["collection_valid"] for run in runs)
    minimum_runs = policy["minimum_runs"]
    campaign_reasons: list[str] = []
    if len(runs) < minimum_runs:
        campaign_reasons.append(f"campaign has fewer than {minimum_runs} runs")
    if runs and not all(run["performance_pass"] for run in runs):
        campaign_reasons.append("one or more runs failed an individual performance gate")
    configurations = [run["pacing_configuration"] for run in runs]
    configuration_consistent = bool(configurations) and all(item == configurations[0] for item in configurations)
    configuration_complete = bool(configurations) and all(
        item["max_fps"] is not None and item["vsync_mode"] is not None for item in configurations
    )
    legacy_configuration = bool(configurations) and all(
        item["max_fps"] is None and item["vsync_mode"] is None for item in configurations
    )
    if configurations and not configuration_consistent:
        campaign_reasons.append("runs have different or mixed known/unknown FPS caps or VSync modes")
    if configurations and not configuration_complete and not legacy_configuration:
        campaign_reasons.append("non-legacy pacing configuration requires both FPS cap and VSync mode")

    lake_reflection_configurations = [run["lake_reflection_configuration"] for run in runs]
    lake_reflection_configuration_consistent = bool(lake_reflection_configurations) and all(
        item == lake_reflection_configurations[0] for item in lake_reflection_configurations
    )
    lake_reflection_configuration_complete = bool(lake_reflection_configurations) and all(
        item is not None for item in lake_reflection_configurations
    )
    legacy_lake_reflection_configuration = bool(lake_reflection_configurations) and all(
        item is None for item in lake_reflection_configurations
    )
    if lake_reflection_configurations and not lake_reflection_configuration_consistent:
        campaign_reasons.append(
            "runs have different or mixed known/unknown installed lake reflection modes"
        )
    performance_pass = (
        len(runs) >= minimum_runs and all(run["performance_pass"] for run in runs)
        and configuration_consistent and (configuration_complete or legacy_configuration)
        and lake_reflection_configuration_consistent
        and (lake_reflection_configuration_complete or legacy_lake_reflection_configuration)
    )
    summary = {
        "format": SUMMARY_FORMAT,
        "complete": True,
        "input_pattern": "run-*.json with same-stem .log files",
        "policy": policy,
        "hardware_acceptance": "not claimed; this reducer evaluates report integrity and declared software pacing gates only",
        "collection_valid": collection_valid,
        "collection_valid_count": sum(run["collection_valid"] for run in runs),
        "active_flight_qualifier_count": sum(run["active_flight_qualifier"] for run in runs),
        "duration_eligible_count": sum(bool(run["duration_eligibility"] and run["duration_eligibility"]["eligible"]) for run in runs),
        "performance_pass": performance_pass,
        "pacing_configuration_consistent": configuration_consistent,
        "pacing_configuration_complete": configuration_complete,
        "lake_reflection_configuration_consistent": lake_reflection_configuration_consistent,
        "lake_reflection_configuration_complete": lake_reflection_configuration_complete,
        "performance_pass_count": sum(run["performance_pass"] for run in runs),
        "run_count": len(runs),
        "minimum_runs": minimum_runs,
        "campaign_reasons": campaign_reasons,
        "failures": failures,
        "runs": runs,
    }
    output_file.parent.mkdir(parents=True, exist_ok=True)
    _write_json(output_file, summary)
    exit_code = 0 if collection_valid and performance_pass and not failures else 1
    return summary, exit_code


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="directory containing run-*.json and same-stem logs")
    parser.add_argument("--out", type=Path, required=True, help="new summary JSON path")
    parser.add_argument("--p95-max-ms", type=float, default=DEFAULT_POLICY["p95_max_ms"])
    parser.add_argument("--p99-max-ms", type=float, default=DEFAULT_POLICY["p99_max_ms"])
    parser.add_argument("--ratio-min", type=float, default=DEFAULT_POLICY["simulation_wall_ratio_min"])
    parser.add_argument("--ratio-max", type=float, default=DEFAULT_POLICY["simulation_wall_ratio_max"])
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    policy = {
        **DEFAULT_POLICY,
        "p95_max_ms": args.p95_max_ms,
        "p99_max_ms": args.p99_max_ms,
        "simulation_wall_ratio_min": args.ratio_min,
        "simulation_wall_ratio_max": args.ratio_max,
    }
    for key, value in policy.items():
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            parser.error(f"{key} must be finite")
    if type(policy["minimum_runs"]) is not int or policy["minimum_runs"] < 1:
        parser.error("minimum_runs must be a positive integer")
    if policy["p95_max_ms"] <= 0 or policy["p99_max_ms"] <= 0:
        parser.error("p95 and p99 limits must be positive")
    if policy["minimum_warmup_s"] < 0 or policy["minimum_sample_s"] <= 0:
        parser.error("minimum warm-up must be non-negative and minimum sample must be positive")
    if policy["simulation_wall_ratio_min"] <= 0 or policy["simulation_wall_ratio_max"] < policy["simulation_wall_ratio_min"]:
        parser.error("simulation wall ratio limits must satisfy 0 < minimum <= maximum")
    try:
        summary, status = summarize_directory(args.input, args.out, policy)
    except (OSError, ValueError) as error:
        print(f"native frame summary: {error}", file=sys.stderr)
        return 1
    print(
        f"native frame summary: {summary['run_count']} runs, "
        f"{summary['collection_valid_count']} collection-valid, "
        f"{summary['performance_pass_count']} performance-pass; "
        f"report {args.out.resolve()}"
    )
    return status


if __name__ == "__main__":
    raise SystemExit(main())
