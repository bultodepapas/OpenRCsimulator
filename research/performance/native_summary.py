#!/usr/bin/env python3
"""Validate and summarize VQ-01b native frame-time reports.

This reducer checks collection integrity, active-flight eligibility, and the
declared pacing policy separately. It does not establish aircraft, pilot, or
hardware acceptance. When recorded, installed lake-reflection mode must be
consistent across a campaign; this is not a render-quality qualification.
"""

from __future__ import annotations

import argparse
from array import array
import hashlib
import json
import math
import re
import sys
import uuid
from pathlib import Path
from typing import Any, Sequence

try:
    from .session_baseline import percentile_nearest_rank
except ImportError:  # Direct execution adds this directory to sys.path.
    from session_baseline import percentile_nearest_rank


FORMAT = "openrc-frametimes v2"
STREAM_FORMAT = "openrc-frametimes v3"
STREAM_DATA_FORMAT = "openrc-frame-stream v1"
STREAM_MAX_BYTES = 268_435_456
STREAM_MAX_FRAMES = 1_000_000
STREAM_CHUNK_FRAMES = 512
STREAM_MAX_LINE_BYTES = 8 * 1024 * 1024
STREAM_MAX_RETAINED_ARRAY_BYTES = 128 * 1024 * 1024
MAX_REPORT_BYTES = 128 * 1024 * 1024
MAX_LOG_BYTES = 64 * 1024 * 1024
SUMMARY_FORMAT = "openrc-native-frame-summary v1"
BENCHMARK_ROUTE = "benchmark-input-circuit"
BENCHMARK_HEALTH_FORMAT = "openrc-benchmark-health v1"
MAX_BENCHMARK_HEALTH_BYTES = 4 * 1024 * 1024
MAX_BENCHMARK_CHECK_BYTES = 1024 * 1024
MAX_BENCHMARK_SOURCES = 8192
MAX_BENCHMARK_SAMPLES = 4096
BENCHMARK_REQUIRED_SOURCES = frozenset({
    "research/performance/sustained_flight.gd", "research/performance/sustained_input.gd",
    "res://ai/companions/pilot.gd", "res://ai/companions/circuit_controller.gd",
    "res://ai/companions/observation_airdata.gd", "res://input/commands.gd", "res://spec.gd",
    "res://data/aircraft/jensen_ugly_stik_60.json", "res://data/fields/default.json", "res://data/fields/lake.json",
    "res://statistics/fixed_wing_adapter.gd", "res://physics/ground_terrain.gd",
    "res://main.gd", "res://sim/flight_session.gd", "res://sim/simulation.gd",
    "res://render/frame_samples.gd", "res://project.godot", "res://render/reconstruction.gd",
    "res://render/cloud_shadow_map.gd", "res://render/cloud_shader_variants.gd", "res://render/cloud_shadow_map.gdshader",
    "res://render/cloud_shadow_map.gdshaderinc", "res://render/cloud_field.gdshaderinc",
    "res://render/sky.gdshader", "res://render/ground.gdshader",
})
BENCHMARK_SOURCE_SCOPE = "application-visible-tree-v1"
BENCHMARK_RECONSTRUCTION = {
    "native": ("native", 1.0),
    "fsr2_native": ("fsr2", 1.0), "fsr2_85": ("fsr2", 0.85),
    "fsr2_quality": ("fsr2", 2 / 3), "fsr2_balanced": ("fsr2", 1 / 1.7),
    "fsr2_performance": ("fsr2", 0.5),
    "fsr3_native": ("fsr3", 1.0), "fsr3_85": ("fsr3", 0.85),
    "fsr3_quality": ("fsr3", 2 / 3), "fsr3_balanced": ("fsr3", 1 / 1.7),
    "fsr3_performance": ("fsr3", 0.5),
    "dlss_native": ("dlss", 1.0), "dlss_quality": ("dlss", 2 / 3),
    "dlss_balanced": ("dlss", 1 / 1.7), "dlss_performance": ("dlss", 0.5),
    "metalfx_spatial_85": ("metalfx_spatial", 0.85),
    "metalfx_spatial_quality": ("metalfx_spatial", 2 / 3),
    "metalfx_temporal_native": ("metalfx_temporal", 1.0),
    "metalfx_temporal_85": ("metalfx_temporal", 0.85),
    "metalfx_temporal_quality": ("metalfx_temporal", 2 / 3),
}
BENCHMARK_PROVENANCE_SOURCES = frozenset({
    "res://main.gd", "res://sim/flight_session.gd", "res://sim/simulation.gd",
    "res://render/frame_samples.gd", "res://input/commands.gd", "res://spec.gd",
    "res://data/aircraft/jensen_ugly_stik_60.json", "res://data/fields/default.json", "res://data/fields/lake.json",
    "res://physics/ground_terrain.gd",
})
BENCHMARK_VIOLATIONS = frozenset({
    "tick_discontinuity", "nonfinite", "input_ownership", "crash", "fault", "pause",
    "hold", "contact", "prop_strike", "pilot_failure", "focus_loss", "observation_overflow",
})
BENCHMARK_FORCED_OPTIONS = {
    "aircraft": "jensen-das-ugly-stik-60", "start": "airborne", "rates": "full",
    "weather": "calm", "landscape": "club_field", "companions": "0",
    "physics-backend": "gdscript_reference",
}
BENCHMARK_INTERNAL_OPTIONS = frozenset({
    "frametimes", "frametimes-stream", "t", "warmup", "case", "sustained-receipt",
    "sustained-hash", "sustained-observation", "sustained-diagnostic-ticks",
    "sustained-render-scale", "sustained-msaa", "sustained-reconstruction",
})
# DT-MAC-03b attribution sweep options consumed by the fixture (receipt scenario.render_override).
BENCHMARK_RENDER_OVERRIDE_OPTIONS = {"sustained-render-scale": "scaling_3d_scale", "sustained-msaa": "msaa_3d",
                                     "sustained-reconstruction": "reconstruction"}
BENCHMARK_REJECTED_OPTIONS = frozenset({
    "quick-flight", "scripted", "trace", "capture", "visual_pose", "visual_distance", "visual_elevation",
    "visual_azimuth", "hide_airplane", "experimental-aircraft-data", "electric-demo", "weather-file", "wind-speed",
    "wind-from", "gust-speed", "gust-up", "gust-duration", "gust-period", "gust-delay", "alt", "fuel",
    "flight-log", "shaft-integrator", "failure-seed", "failures", "catastrophic", "out-of-trim", "battery",
    "companions-seed", "native-qualification", "flight-log-cli", "case",
})
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
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(float(value))
    except OverflowError:
        return False


def _is_int(value: Any) -> bool:
    return type(value) is int


def _reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON value {value} is forbidden")


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def _read_bounded(path: Path, maximum: int) -> bytes:
    with path.open("rb") as stream:
        data = stream.read(maximum + 1)
    if len(data) > maximum:
        raise ValueError(f"input exceeds the {maximum}-byte limit")
    return data


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


def _array_numbers(value: Any, label: str, errors: list[str], *, positive: bool = False) -> Sequence[float] | None:
    if not isinstance(value, (list, array)):
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
        if not isinstance(value, array):
            result.append(number)
    return value if isinstance(value, array) else result


def _array_ints(value: Any, label: str, errors: list[str], *, positive: bool = False) -> Sequence[int] | None:
    if not isinstance(value, (list, array)):
        errors.append(f"{label} must be an array")
        return None
    result: list[int] = []
    for index, item in enumerate(value):
        if not _is_int(item) or item < (1 if positive else 0):
            qualifier = "positive" if positive else "non-negative"
            errors.append(f"{label}[{index}] must be a {qualifier} integer")
            continue
        if not isinstance(value, array):
            result.append(item)
    return value if isinstance(value, array) else result


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

    # Optional for historical reports. Endpoint context cannot establish pause
    # history or replace the raw tick/time and simulation.paused gates.
    if "session_at_report" in report:
        endpoint = report["session_at_report"]
        if not isinstance(endpoint, dict):
            errors.append("session_at_report must be an object")
        else:
            if not isinstance(endpoint.get("scope"), str) or not endpoint["scope"].strip():
                errors.append("session_at_report.scope must be a non-empty string")
            if not isinstance(endpoint.get("pause_reason"), str):
                errors.append("session_at_report.pause_reason must be a string")
            holds = endpoint.get("holds")
            if not isinstance(holds, list) or any(not isinstance(hold, str) for hold in holds):
                errors.append("session_at_report.holds must be an array of strings")
            for key in ("crashed", "window_focused"):
                if type(endpoint.get(key)) is not bool:
                    errors.append(f"session_at_report.{key} must be a boolean")

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


def active_flight_reasons(report: dict[str, Any], derived: dict[str, Any], policy: dict[str, Any],
                          *, benchmark_eligible: bool = False) -> list[str]:
    reasons: list[str] = []
    if report.get("route") != "live-input" and not (
        report.get("route") == BENCHMARK_ROUTE and benchmark_eligible
    ):
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


def rendering_gate(report: dict[str, Any]) -> dict[str, Any]:
    """Keep collection integrity separate from evidence that rendering progressed."""
    observation = report.get("render_progress")
    if not isinstance(observation, dict):
        return {"status": "unknown", "eligible": False, "reason": "render progress was not recorded"}
    status = observation.get("status")
    if status != "observed":
        return {"status": status if isinstance(status, str) else "unknown", "eligible": False,
                "reason": "render progress was not established"}
    fields = ("sample_intervals", "frames_drawn_at_start", "frames_drawn_first", "frames_drawn_last", "frames_drawn_delta",
              "undrawable_samples", "counter_resets", "no_draw_intervals")
    if (any(not _is_int(observation.get(key)) or observation[key] < 0 for key in fields)
            or not _is_int(report.get("frames")) or report["frames"] < 1
            or report.get("display_server") in (None, "", "headless")):
        return {"status": "invalid", "eligible": False, "reason": "render progress evidence is malformed"}
    intervals = report["frames"]
    before_first = observation["frames_drawn_at_start"]
    first = observation["frames_drawn_first"]
    last = observation["frames_drawn_last"]
    if (observation["sample_intervals"] != intervals or last < first or first < before_first
            or observation["frames_drawn_delta"] != last - before_first
            or last - before_first < intervals or observation["undrawable_samples"] != 0
            or observation["counter_resets"] != 0 or observation["no_draw_intervals"] != 0):
        return {"status": "invalid", "eligible": False, "reason": "render progress counters are inconsistent"}
    # A v3 report retains all endpoint metrics even when the stream reader only
    # materializes simulation arrays. A v2 report has the arrays themselves.
    metrics = report.get("raw_metrics")
    keys = ("render_frames_drawn", "render_interval_draws", "render_interval_counter_reset", "render_window_drawable",
            "render_counter_resets", "render_no_draw_intervals", "render_undrawable_samples")
    if (not isinstance(metrics, dict) or any(not isinstance(metrics.get(key), (list, array))
            or len(metrics[key]) != report["frames"] for key in keys)):
        return {"status": "invalid", "eligible": False, "reason": "render progress samples are missing"}
    start = {key: metrics[key][0] for key in keys}
    end = {key: metrics[key][-1] for key in keys}
    if (any(not _is_number(point.get(key)) or not float(point[key]).is_integer() or point[key] < 0
            for point in (start, end) for key in keys)
            or int(start["render_frames_drawn"]) != first or int(end["render_frames_drawn"]) != last
            or first - int(start["render_interval_draws"]) != before_first
            or start["render_window_drawable"] != 1 or end["render_window_drawable"] != 1
            or start["render_counter_resets"] != end["render_counter_resets"]
            or start["render_no_draw_intervals"] != end["render_no_draw_intervals"]
            or start["render_undrawable_samples"] != end["render_undrawable_samples"]):
        return {"status": "invalid", "eligible": False, "reason": "render progress does not match sample endpoints"}
    draws = metrics["render_frames_drawn"]
    if (any(not _is_number(value) or value < 0 or not float(value).is_integer()
            for key in keys for value in metrics[key])
            or any(value != 1 for value in metrics["render_window_drawable"])
            or any(value <= 0 for value in metrics["render_interval_draws"])
            or any(value != 0 for value in metrics["render_interval_counter_reset"])
            or any(value != start["render_counter_resets"] for value in metrics["render_counter_resets"])
            or any(value != start["render_no_draw_intervals"] for value in metrics["render_no_draw_intervals"])
            or any(value != start["render_undrawable_samples"] for value in metrics["render_undrawable_samples"])
            or any(right - left != interval for left, right, interval in
                   zip(draws, draws[1:], metrics["render_interval_draws"][1:]))):
        return {"status": "invalid", "eligible": False, "reason": "render progress did not continue throughout the sample"}
    return {"status": status, "eligible": True,
            "reason": "render-server progress observed; actual presentation is not measured"}


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


def _hydrate_stream_report(report: dict[str, Any], report_path: Path, *, include_metrics: bool = False,
                           max_input_bytes: int = STREAM_MAX_BYTES) -> tuple[dict[str, Any], dict[str, Any]]:
    """Read a bounded v3 stream, validate every chunk, and reuse the v2 numerical checks.

    The default retains five compact numeric arrays for exact percentiles and
    simulation checks. Diagnosis can request all metrics, subject to an explicit
    retained-array ceiling. Other values are validated as chunks arrive. Frame,
    byte and line limits are enforced before allocation and during reading.
    """
    if report.get("version") != 3 or type(report.get("version")) is not int:
        raise ValueError("stream report version must be integer 3")
    if not isinstance(report.get("capture_id"), str):
        raise ValueError("stream report capture_id must be a string")
    if (not _is_number(report.get("sample_s")) or not 0 < report["sample_s"] <= 3600
            or not _is_number(report.get("warmup_s")) or not 0 <= report["warmup_s"] <= 3600):
        raise ValueError("stream sample or warm-up duration exceeds the supported bounds")
    if (report.get("raw_metrics") != {} or any(report.get(key) != [] for key in
            ("frame_deltas_s", "frame_wall_usec", "frame_end_monotonic_usec", "engine_frame_deltas_s"))):
        raise ValueError("stream report must not embed conflicting frame arrays")
    stream = report.get("stream")
    if not isinstance(stream, dict):
        raise ValueError("stream metadata must be an object")
    filename = stream.get("file")
    if filename != report_path.name + ".frames.jsonl":
        raise ValueError("stream file must be the report's same-directory sibling")
    path = report_path.with_name(filename)
    if path.is_symlink():
        raise ValueError("stream file must not be a symbolic link")
    if type(stream.get("complete")) is not bool or stream["complete"] is not True:
        raise ValueError("stream is marked incomplete")
    expected_bytes = stream.get("bytes")
    expected_chunks = stream.get("chunks")
    expected_frames = stream.get("frames")
    max_frames = report.get("max_frames")
    if not _is_int(max_input_bytes) or not 0 <= max_input_bytes <= STREAM_MAX_BYTES:
        raise ValueError("stream input byte budget is invalid")
    if not _is_int(expected_bytes) or not 1 <= expected_bytes <= min(STREAM_MAX_BYTES, max_input_bytes):
        raise ValueError("stream byte count is invalid or exceeds the hard limit")
    if not _is_int(expected_chunks) or expected_chunks < 1:
        raise ValueError("stream chunk count must be positive")
    if not _is_int(expected_frames) or not 1 <= expected_frames <= STREAM_MAX_FRAMES:
        raise ValueError("stream frame count is invalid or exceeds the hard limit")
    if not _is_int(max_frames) or not expected_frames <= max_frames <= STREAM_MAX_FRAMES:
        raise ValueError("stream frame retention limit is invalid")
    if report.get("frames") != expected_frames or type(report.get("frames")) is not int:
        raise ValueError("report frame count must match stream frame count")
    if stream.get("chunk_frames") != STREAM_CHUNK_FRAMES or stream.get("max_bytes") != STREAM_MAX_BYTES:
        raise ValueError("stream bounds do not match the supported format")
    for key in ("rejected_frames", "unstored_frames", "write_calls", "write_total_usec", "write_max_usec"):
        if not _is_int(stream.get(key)) or stream[key] < 0:
            raise ValueError(f"stream {key} must be a non-negative integer")
    if stream["rejected_frames"] or stream["unstored_frames"]:
        raise ValueError("a complete stream cannot have rejected or unstored frames")
    if stream["write_calls"] != expected_chunks + 2 or stream["write_total_usec"] < stream["write_max_usec"]:
        raise ValueError("stream write timing counters are inconsistent")
    if not isinstance(stream.get("write_timing_scope"), str) or not stream["write_timing_scope"].strip():
        raise ValueError("stream write timing scope is missing")
    if path.stat().st_size != expected_bytes:
        raise ValueError("stream byte count does not match the file")
    expected_hash = stream.get("sha256")
    if not isinstance(expected_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_hash):
        raise ValueError("stream SHA-256 is missing or invalid")

    wall = array("q")
    ends = array("q")
    deltas = array("d")
    ticks = array("d")
    times = array("d")
    retained_metrics: dict[str, array] = {"sim_tick": ticks, "sim_time_s": times}
    digest = hashlib.sha256()
    bytes_read = 0
    chunks = 0
    names: set[str] | None = None
    first_metrics: dict[str, float] | None = None
    last_metrics: dict[str, float] | None = None
    previous_end: int | None = None
    previous_chunk_frames = STREAM_CHUNK_FRAMES
    header_seen = False
    trailer_seen = False
    max_int64 = (1 << 63) - 1

    with path.open("rb") as source:
        while True:
            # One byte of look-ahead detects growth after the initial stat without
            # reading an unbounded line or exceeding the caller's budget by more.
            read_limit = min(STREAM_MAX_LINE_BYTES + 1, max_input_bytes - bytes_read + 1)
            line = source.readline(read_limit)
            if not line:
                break
            bytes_read += len(line)
            if bytes_read > min(STREAM_MAX_BYTES, max_input_bytes) or len(line) > STREAM_MAX_LINE_BYTES:
                raise ValueError("stream input exceeds a byte or line limit")
            if not line.endswith(b"\n"):
                raise ValueError("stream ends with a truncated record")
            digest.update(line)
            record = json.loads(line.decode("utf-8"), parse_constant=_reject_constant,
                                object_pairs_hook=_unique_object)
            if not isinstance(record, dict):
                raise ValueError("stream record must be an object")
            kind = record.get("type")
            if not header_seen:
                if (kind != "header" or record.get("format") != STREAM_DATA_FORMAT
                        or type(record.get("version")) is not int or record["version"] != 1):
                    raise ValueError("stream header is invalid")
                if (record.get("capture_id") != report.get("capture_id")
                        or record.get("chunk_frames") != STREAM_CHUNK_FRAMES
                        or record.get("max_frames") != max_frames
                        or record.get("max_bytes") != STREAM_MAX_BYTES
                        or record.get("sample_s") != report.get("sample_s")
                        or record.get("warmup_s") != report.get("warmup_s")):
                    raise ValueError("stream header does not match the report")
                header_seen = True
                continue
            if trailer_seen:
                raise ValueError("stream contains data after its trailer")
            if kind == "trailer":
                if (record.get("complete") is not True or record.get("failure") != ""
                        or record.get("chunks") != chunks or record.get("frames") != len(wall)):
                    raise ValueError("stream trailer is incomplete or inconsistent")
                trailer_seen = True
                continue
            if kind != "chunk":
                raise ValueError("unexpected stream record type")
            count = record.get("frames")
            if (not _is_int(count) or not 1 <= count <= STREAM_CHUNK_FRAMES
                    or previous_chunk_frames != STREAM_CHUNK_FRAMES
                    or record.get("sequence") != chunks or type(record.get("sequence")) is not int
                    or record.get("start_frame") != len(wall) or type(record.get("start_frame")) is not int):
                raise ValueError("stream chunk sequence, size, or start frame is invalid")
            if len(wall) + count > expected_frames:
                raise ValueError("stream contains more frames than declared")
            chunk_wall = record.get("wall_usec")
            chunk_ends = record.get("end_usec")
            engine = record.get("engine_delta_s")
            metrics = record.get("metrics")
            if (not isinstance(chunk_wall, list) or len(chunk_wall) != count
                    or not isinstance(chunk_ends, list) or len(chunk_ends) != count
                    or not isinstance(engine, list) or len(engine) != count
                    or not isinstance(metrics, dict)):
                raise ValueError("stream chunk arrays do not match its frame count")
            keys = set(metrics)
            if (len(keys) > 64 or any(not isinstance(key, str) or not 1 <= len(key) <= 128 for key in keys)
                    or not {"sim_tick", "sim_time_s"}.issubset(keys)):
                raise ValueError("stream metric names are invalid or omit simulation metrics")
            if names is None:
                names = keys
                progress_keys = {"render_frames_drawn", "render_interval_draws", "render_interval_counter_reset",
                                 "render_window_drawable", "render_counter_resets", "render_no_draw_intervals",
                                 "render_undrawable_samples"} & keys
                retained_count = len(keys) if include_metrics else 2 + len(progress_keys)
                if expected_frames * (3 + retained_count) * 8 > STREAM_MAX_RETAINED_ARRAY_BYTES:
                    raise ValueError("stream would exceed the retained numeric-array memory limit")
                if include_metrics:
                    for key in keys - retained_metrics.keys():
                        retained_metrics[key] = array("d")
                else:
                    for key in progress_keys:
                        retained_metrics[key] = array("d")
            elif keys != names:
                raise ValueError("stream metric schema changed between chunks")
            for key, values in metrics.items():
                if not isinstance(values, list) or len(values) != count or any(not _is_number(value) for value in values):
                    raise ValueError(f"stream metric {key!r} has invalid or missing samples")
            if any(not _is_number(value) or value < 0 for value in engine):
                raise ValueError("stream engine deltas must be finite and non-negative")
            for index in range(count):
                interval = chunk_wall[index]
                endpoint = chunk_ends[index]
                if (not _is_int(interval) or not 0 < interval <= max_int64
                        or not _is_int(endpoint) or not 0 < endpoint <= max_int64):
                    raise ValueError("stream wall intervals and endpoints must be positive int64 values")
                if previous_end is not None and endpoint - interval != previous_end:
                    raise ValueError("stream wall intervals are not contiguous")
                wall.append(interval)
                ends.append(endpoint)
                deltas.append(interval / 1_000_000.0)
                previous_end = endpoint
            for key, values in retained_metrics.items():
                values.extend(float(value) for value in metrics[key])
            if first_metrics is None:
                first_metrics = {key: values[0] for key, values in metrics.items()}
            last_metrics = {key: values[-1] for key, values in metrics.items()}
            previous_chunk_frames = count
            chunks += 1

    if not header_seen or not trailer_seen:
        raise ValueError("stream is missing its header or completion trailer")
    if bytes_read != expected_bytes or digest.hexdigest() != expected_hash:
        raise ValueError("stream byte count or SHA-256 does not match the report")
    if chunks != expected_chunks or len(wall) != expected_frames:
        raise ValueError("stream chunk or frame count does not match the report")
    endpoints = report.get("sample_endpoints")
    if not isinstance(endpoints, dict) or endpoints.get("first") != first_metrics or endpoints.get("last") != last_metrics:
        raise ValueError("stream sample endpoints do not match the report")
    if (report.get("actual_sample_start_monotonic_usec") != ends[0] - wall[0]
            or report.get("actual_sample_end_monotonic_usec") != ends[-1]):
        raise ValueError("stream sample clock boundaries do not match the report")

    hydrated = dict(report)
    hydrated.update(format=FORMAT, version=2, frame_deltas_s=deltas,
                    frame_wall_usec=wall, frame_end_monotonic_usec=ends,
                    raw_metrics=retained_metrics)
    return hydrated, {"file": filename, "bytes": bytes_read, "sha256": digest.hexdigest(),
                      "chunks": chunks, "frames": len(wall),
                      "write_calls": stream["write_calls"], "write_total_usec": stream["write_total_usec"],
                      "write_max_usec": stream["write_max_usec"], "write_timing_scope": stream["write_timing_scope"]}


def benchmark_health(report_path: Path, report_bytes: bytes | None, report: dict[str, Any],
                     stream: dict[str, Any] | None) -> dict[str, Any]:
    """Validate the separate, bounded circuit observer receipt for this frame stream.

    A receipt is evidence from the benchmark owner, not a signature or evidence
    of a pilot, the Home-to-Fly route, a release package or physical validation.
    """
    path = report_path.with_name("health-" + report_path.name)
    reasons: list[str] = []
    receipt_bytes: bytes | None = None
    receipt: Any = None
    try:
        if path.is_symlink():
            raise ValueError("health receipt must not be a symbolic link")
        receipt_bytes = _read_bounded(path, MAX_BENCHMARK_HEALTH_BYTES)
        receipt = json.loads(receipt_bytes.decode("utf-8"), parse_constant=_reject_constant,
                             object_pairs_hook=_unique_object)
        if not isinstance(receipt, dict):
            raise ValueError("health receipt must be an object")
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError, RecursionError) as error:
        reasons.append(f"health receipt is unreadable or malformed: {error}")

    if isinstance(receipt, dict):
        pending = [receipt]
        while pending:
            item = pending.pop()
            if isinstance(item, float) and not math.isfinite(item):
                reasons.append("health receipt contains a non-finite number")
                break
            if isinstance(item, dict):
                pending.extend(item.values())
            elif isinstance(item, list):
                pending.extend(item)
        if receipt.get("format") != BENCHMARK_HEALTH_FORMAT or receipt.get("route") != BENCHMARK_ROUTE:
            reasons.append("health format or route is incorrect")
        for key in ("complete", "timing_complete", "frame_collection_complete", "timing_eligible", "source_unchanged",
                    "frame_capture_id_matches"):
            if receipt.get(key) is not True:
                reasons.append(f"health {key} must be true")
        if (receipt.get("diagnostic_complete") is not False or receipt.get("observer_off_control_complete") is not False
                or type(receipt.get("frame_exit_code")) is not int or receipt["frame_exit_code"] != 0
                or receipt.get("failure") != ""):
            reasons.append("health must describe a successful timing run without a failure")
        dwell = receipt.get("dwell_after_frame_seal_s")
        if not _is_number(dwell) or dwell < 2.5:
            reasons.append("health must retain the process for at least 2.5 seconds after frame seal")
        capture_id = report.get("capture_id")
        if (not isinstance(capture_id, str) or not capture_id.strip() or len(capture_id) > 128
                or receipt.get("capture_id") != capture_id):
            reasons.append("health capture ID does not match the frame report")
        else:
            try:
                if str(uuid.UUID(capture_id)) != capture_id:
                    raise ValueError("noncanonical UUID")
            except ValueError:
                reasons.append("health capture ID is not a canonical UUID")
        expected_report_hash = _sha256_bytes(report_bytes) if report_bytes is not None else None
        declared_frame = receipt.get("frame_report")
        if (receipt.get("report") != report_path.name or not isinstance(declared_frame, str)
                or not declared_frame or declared_frame.replace("\\", "/").rsplit("/", 1)[-1] != report_path.name):
            reasons.append("health frame report name does not match")
        if (expected_report_hash is None or receipt.get("report_sha256") != expected_report_hash
                or receipt.get("frame_report_sha256") != expected_report_hash):
            reasons.append("health frame report SHA-256 does not match")
        if (report.get("format") != STREAM_FORMAT or stream is None
                or receipt.get("frame_stream_sha256") != stream.get("sha256")):
            reasons.append("health requires the matching validated v3 frame stream")

        sources = receipt.get("source_sha256")
        if receipt.get("source_scope") != BENCHMARK_SOURCE_SCOPE:
            reasons.append("health lacks the complete visible application source-tree identity")
        provenance = report.get("code_provenance")
        provenance = provenance.get("source_sha256") if isinstance(provenance, dict) else None
        valid_sources = isinstance(sources, dict) and 1 <= len(sources) <= MAX_BENCHMARK_SOURCES
        if valid_sources:
            valid_sources = all(
                isinstance(key, str) and 1 <= len(key) <= 512
                and all(char.isprintable() for char in key)
                and isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None
                for key, value in sources.items()
            )
        if not valid_sources:
            reasons.append("health source identities are missing, malformed or exceed their bounds")
        else:
            if not BENCHMARK_REQUIRED_SOURCES.issubset(sources):
                reasons.append("health omits required benchmark or runtime source identities")
            if (not isinstance(provenance, dict)
                    or not BENCHMARK_PROVENANCE_SOURCES.issubset(provenance)
                    or any(sources.get(key) != provenance.get(key) for key in BENCHMARK_PROVENANCE_SOURCES)
                    or any(value != provenance[key] for key, value in sources.items() if key in provenance)):
                reasons.append("health runtime source identities do not match frame provenance")
            identity = "".join(f"{key}:{sources[key]}\n" for key in sorted(sources))
            identity_hash = hashlib.sha256(identity.encode("utf-8")).hexdigest()
            if report.get("case_id") != f"{BENCHMARK_ROUTE}-{identity_hash}":
                reasons.append("health source identities are not bound to the frame case ID")

        scenario = receipt.get("scenario")
        if not isinstance(scenario, dict):
            reasons.append("health scenario identity is missing")
            scenario = {}
        if (scenario.get("aircraft_id") != report.get("aircraft_id")
                or scenario.get("aircraft_id") != "jensen-das-ugly-stik-60"
                or scenario.get("field_id") != "default" or scenario.get("seed") != 20261021
                or type(scenario.get("seed")) is not int or scenario.get("start_choice") != "airborne"
                or not _is_number(scenario.get("trim_speed_m_s"))
                or scenario.get("trim_speed_m_s") != 15.0 or scenario.get("rate_profile") != "full"
                or not _is_number(scenario.get("trim_throttle")) or not 0 <= scenario.get("trim_throttle", -1) <= 1
                or type(scenario.get("physics_hz")) is not int or scenario.get("physics_hz") != 240
                or type(scenario.get("control_update_ticks")) is not int or scenario.get("control_update_ticks") != 4
                or scenario.get("input_enabled") is not True or scenario.get("physics_enabled") is not True
                or scenario.get("external_driver_enabled") is not False
                or scenario.get("fixed_fps_diagnostic") is not False
                or scenario.get("observation_mode") != "on"
                or type(scenario.get("state_input_hashing")) is not bool
                or not isinstance(scenario.get("weather"), dict) or not scenario["weather"]):
            reasons.append("health scenario does not identify the declared automatic circuit workload")
        if not _effective_render_matches(scenario, report):
            reasons.append("health requested and observed rendering configuration is missing, changed or inconsistent")
        if not _cloud_observations_valid(scenario):
            reasons.append("health cloud modes, consumer readiness or density variant are missing or inconsistent")
        arguments = scenario.get("arguments")
        if (not isinstance(arguments, list) or not 1 <= len(arguments) <= 128
                or any(not isinstance(arg, str) or not arg.startswith("--") or len(arg) > 4096 for arg in arguments)):
            reasons.append("health scenario arguments are missing or malformed")
            arguments = []
        if ([arg for arg in arguments if arg.startswith("--case=")] != ["--case=" + str(report.get("case_id", ""))]
                or [arg for arg in arguments if arg.startswith("--frametimes=")] != ["--frametimes=" + str(declared_frame)]
                or arguments.count("--frametimes-stream") != 1):
            reasons.append("health scenario arguments do not match the frame capture")
        weather = scenario.get("weather")
        if (not isinstance(weather, dict) or weather.get("format") != "openrc-weather v1"
                or any(not _is_number(weather.get(key)) or weather[key] != 0
                       for key in ("speed_mps", "gust_mps", "gust_up_mps"))):
            reasons.append("health scenario does not identify calm weather")
        stage = scenario.get("stage_backend")
        stage_identity = stage.get("identity") if isinstance(stage, dict) else None
        if (not isinstance(stage, dict) or stage.get("requested") != "gdscript_reference"
                or stage.get("reason") != "" or not isinstance(stage_identity, dict)
                or stage_identity.get("backend") != "gdscript_reference"):
            reasons.append("health scenario does not identify the reference physics backend")
        solver = scenario.get("solver_identity")
        checkpoint = scenario.get("initial_checkpoint_sha256")
        if (not isinstance(solver, dict) or solver.get("kind") != "source-tree-v1"
                or not isinstance(solver.get("sha256"), str)
                or re.fullmatch(r"[0-9a-f]{64}", solver["sha256"]) is None
                or not isinstance(checkpoint, str) or re.fullmatch(r"[0-9a-f]{64}", checkpoint) is None):
            reasons.append("health scenario lacks source-tree solver or initial checkpoint identity")

        observation = receipt.get("observation")
        if not isinstance(observation, dict):
            reasons.append("health observation is missing")
            observation = {}
        for key in ("physics_enabled_throughout", "input_enabled_throughout",
                    "external_driver_disabled_throughout", "automatic_callbacks_throughout"):
            if observation.get(key) is not True:
                reasons.append(f"health observation.{key} must be true")
        for key in ("start_monotonic_usec", "end_monotonic_usec", "start_tick", "end_tick",
                    "accepted_ticks", "input_reads", "observer_calls"):
            value = observation.get(key)
            if not _is_int(value) or value < 0:
                reasons.append(f"health observation.{key} must be a non-negative integer")
        start_tick, end_tick = observation.get("start_tick"), observation.get("end_tick")
        if (_is_int(start_tick) and _is_int(end_tick)
                and (start_tick != 0 or end_tick <= start_tick
                     or any(observation.get(key) != end_tick - start_tick
                            for key in ("accepted_ticks", "input_reads", "observer_calls")))):
            reasons.append("health must observe every accepted tick and input from tick zero")
        start_usec, end_usec = observation.get("start_monotonic_usec"), observation.get("end_monotonic_usec")
        sample_start = report.get("actual_sample_start_monotonic_usec")
        sample_end = report.get("actual_sample_end_monotonic_usec")
        clock = report.get("clock")
        clock_start = clock.get("start", {}).get("monotonic_usec") if isinstance(clock, dict) and isinstance(clock.get("start"), dict) else None
        clock_end = clock.get("end", {}).get("monotonic_usec") if isinstance(clock, dict) and isinstance(clock.get("end"), dict) else None
        if (not all(_is_int(value) for value in (start_usec, end_usec, clock_start, clock_end,
                                                 sample_start, sample_end))
                or not 0 <= start_usec <= clock_start <= sample_start < sample_end <= clock_end <= end_usec):
            reasons.append("health observation does not bracket the full frame capture clock")
        simulation, measured = report.get("simulation"), report.get("measured_simulation")
        if (not isinstance(simulation, dict) or not isinstance(measured, dict)
                or not all(_is_int(value) for value in (start_tick, end_tick, simulation.get("start_tick"),
                                                        simulation.get("end_tick"), measured.get("start_tick"),
                                                        measured.get("end_tick")))
                or not start_tick <= simulation["start_tick"] <= measured["start_tick"]
                <= measured["end_tick"] <= simulation["end_tick"] <= end_tick):
            reasons.append("health observation does not bracket the full frame capture ticks")

        violations = receipt.get("violations")
        if (not isinstance(violations, dict) or set(violations) != BENCHMARK_VIOLATIONS
                or any(not _is_int(value) or value != 0 for value in violations.values())):
            reasons.append("health violation counters must all be present and zero")
        endpoint = report.get("session_at_report")
        if (not isinstance(endpoint, dict) or endpoint.get("crashed") is not False
                or endpoint.get("holds") != [] or endpoint.get("pause_reason") != ""
                or endpoint.get("window_focused") is not True):
            reasons.append("frame report endpoint is crashed, held, paused, unfocused or unavailable")

        health = receipt.get("health")
        if (not isinstance(health, dict) or not _is_int(end_tick)
                or any(type(health.get(key)) is not int or health.get(key) != end_tick
                       for key in ("accepted_ticks", "input_reads", "observer_calls"))
                or type(health.get("last_read_tick")) is not int or health.get("last_read_tick") != end_tick - 1
                or type(health.get("pilot_updates")) is not int or health.get("pilot_updates") != (end_tick + 3) // 4
                or health.get("pilot_failure") != ""
                or not _is_number(health.get("min_altitude_m"))
                or not _is_number(health.get("min_ground_clearance_m")) or health["min_ground_clearance_m"] <= 0
                or not _is_number(health.get("max_abs_radius_error_m")) or health["max_abs_radius_error_m"] < 0):
            reasons.append("health input, pilot or sampled route coverage is inconsistent")

        checkpoints = receipt.get("checkpoints")
        if scenario.get("state_input_hashing") is True:
            if not isinstance(checkpoints, list) or not 1 <= len(checkpoints) <= 1000 or not _is_int(end_tick):
                reasons.append("health state/input checkpoint coverage is missing or exceeds its bound")
            else:
                next_tick = 1
                for point in checkpoints:
                    if (not isinstance(point, dict) or point.get("start_tick") != next_tick
                            or not _is_int(point.get("start_tick")) or not _is_int(point.get("end_tick"))
                            or point["end_tick"] < next_tick or point["end_tick"] > end_tick
                            or point["end_tick"] - next_tick + 1 > 6000
                            or not isinstance(point.get("sha256"), str)
                            or re.fullmatch(r"[0-9a-f]{64}", point["sha256"]) is None
                            or (point["end_tick"] - next_tick + 1 < 6000 and point.get("partial") is not True)
                            or (point["end_tick"] - next_tick + 1 == 6000 and point.get("partial", False) is not False)
                            or (point["end_tick"] < end_tick and point["end_tick"] - next_tick + 1 != 6000)):
                        reasons.append("health state/input checkpoint coverage is invalid")
                        break
                    next_tick = point["end_tick"] + 1
                else:
                    if next_tick != end_tick + 1:
                        reasons.append("health state/input checkpoints do not cover all accepted ticks")
        elif checkpoints != []:
            reasons.append("health must not claim checkpoints when state/input hashing is disabled")
        samples = health.get("samples_1hz") if isinstance(health, dict) else None
        if not isinstance(samples, list) or not 2 <= len(samples) <= MAX_BENCHMARK_SAMPLES:
            reasons.append("health diagnostic samples are missing or exceed their bound")
        else:
            previous_tick: int | None = None
            for sample in samples:
                if not isinstance(sample, dict):
                    reasons.append("health diagnostic sample must be an object")
                    break
                tick = sample.get("tick")
                values = [sample.get(key) for key in ("time_s", "north_m", "east_m", "altitude_m",
                                                        "ground_clearance_m", "radius_error_m")]
                if (not _is_int(tick) or tick < 0 or not _is_number(tick) or not all(_is_number(value) for value in values)
                        or values[4] <= 0 or not _close(float(values[0]), tick / 240.0, tolerance=1e-6)
                        or (previous_tick is not None and not 0 < tick - previous_tick <= 240)):
                    reasons.append("health diagnostic samples have invalid values or tick coverage")
                    break
                previous_tick = tick
            else:
                if samples[0]["tick"] != start_tick or samples[-1]["tick"] != end_tick:
                    reasons.append("health diagnostic samples do not cover observation endpoints")

    return {
        "receipt": path.name,
        "receipt_sha256": _sha256_bytes(receipt_bytes) if receipt_bytes is not None else None,
        "eligible": not reasons,
        "reasons": reasons,
        "source_identity_sha256": identity_hash if isinstance(receipt, dict) and valid_sources else None,
        "declared_frame_path": declared_frame if isinstance(receipt, dict) and isinstance(declared_frame, str) else None,
        "scenario": ({**{key: scenario.get(key) for key in (
            "aircraft_id", "field_id", "seed", "start_choice", "trim_speed_m_s", "trim_throttle", "rate_profile",
            "weather", "stage_backend", "physics_hz", "control_update_ticks", "initial_checkpoint_sha256",
            "solver_identity", "input_enabled", "physics_enabled", "external_driver_enabled", "fixed_fps_diagnostic",
            "observation_mode", "state_input_hashing", "render_override",
            "collision_world_identity", "lake_identity", "checkpoint_configuration",
        )}, "effective_render": scenario["effective_render"]["start"],
            "cloud_cache": _canonical_cloud(scenario["cloud_cache"]["start"]),
            "cloud_density_bounds": scenario["cloud_density_bounds"]["start"],
            "arguments": [arg for arg in arguments if not arg.startswith(("--frametimes=", "--case="))]}
            if isinstance(receipt, dict) and not reasons else None),
        "scope": "technical benchmark circuit; not normal product-route, package or pilot acceptance",
    }


def _cloud_observations_valid(scenario: dict[str, Any]) -> bool:
    observed = scenario.get("cloud_cache")
    bounds = scenario.get("cloud_density_bounds")
    if not isinstance(observed, dict) or observed.get("stable") is not True:
        return False
    start = observed.get("start")
    if (not isinstance(start, dict) or start != observed.get("end")
            or not _is_int(start.get("generation")) or start["generation"] < 0):
        return False
    initial, final = observed.get("initial_generations"), observed.get("final_generations")
    if (not isinstance(initial, dict) or not isinstance(final, dict)
            or "first_change" not in observed or observed["first_change"] is not None
            or any(type(initial.get(key)) is not int or initial[key] != start["generation"]
                   for key in ("previous_frame", "before_snapshot", "after_snapshot"))
            or any(type(final.get(key)) is not int or final[key] != start["generation"]
                   for key in ("before_snapshot", "after_snapshot"))):
        return False
    env, requested, effective = (start.get(key) for key in ("environment", "requested", "effective"))
    consumers, required, seeds = (start.get(key) for key in ("consumers", "required_seeds", "seeds"))
    if (not all(isinstance(value, dict) for value in (env, requested, effective, consumers, required))
            or not isinstance(seeds, list) or len(seeds) > 4
            or set(env) != {"global", "ground", "sky"}
            or any(value not in ("", "0", "1") for value in env.values())):
        return False
    by_seed: dict[int, dict[str, Any]] = {}
    for row in seeds:
        if (not isinstance(row, dict) or not _is_int(row.get("seed")) or row["seed"] in by_seed
                or row.get("status") not in ("pending", "ready", "failed")
                or not _is_int(row.get("attempts")) or not 1 <= row["attempts"] <= 2
                or not isinstance(row.get("failure"), str)):
            return False
        by_seed[row["seed"]] = row
    for mode in ("ground", "sky"):
        raw = env[mode] or env["global"]
        if raw not in ("0", "1") or requested.get(mode) is not (raw == "1"):
            return False
        rows, ids = consumers.get(mode), required.get(mode)
        if (not isinstance(rows, list) or len(rows) > 8192 or not isinstance(ids, list)
                or any(not _is_int(seed) for seed in ids) or sorted(set(ids)) != ids):
            return False
        if effective.get(mode) != ("ready" if raw == "1" else "disabled"):
            return False
        if raw == "1" and not rows:
            return False
        actual_seeds = set()
        for row in rows:
            if (not isinstance(row, dict) or not _is_int(row.get("seed"))
                    or row.get("status") != ("ready" if raw == "1" else "disabled")
                    or row.get("enabled") is not (raw == "1")):
                return False
            actual_seeds.add(row["seed"])
            if raw == "1":
                tile = by_seed.get(row["seed"], {})
                if tile.get("status") != "ready" or tile.get("failure") != "":
                    return False
        if sorted(actual_seeds) != ids:
            return False
    if not isinstance(bounds, dict) or bounds.get("stable") is not True:
        return False
    setting = bounds.get("start")
    if not isinstance(setting, dict) or setting != bounds.get("end"):
        return False
    value = setting.get("requested")
    return (value in ("", "off", "three", "two_three")
            and setting.get("effective") == (value if value in ("three", "two_three") else "off")
            and setting.get("bound") == setting.get("effective")
            and setting.get("scope") == "sky density and analytic relief fallback"
            and setting.get("qualified") is False)


def _canonical_cloud(snapshot: dict[str, Any]) -> dict[str, Any]:
    """Compare workload identity, excluding process-local counters and old, unused tiles."""
    required = set(snapshot["required_seeds"]["ground"] + snapshot["required_seeds"]["sky"])
    return {"environment": snapshot["environment"], "requested": snapshot["requested"],
            "effective": snapshot["effective"], "required_seeds": snapshot["required_seeds"],
            "consumers": {mode: sorted(snapshot["consumers"][mode], key=lambda row: (row["seed"], row["status"], row["enabled"]))
                          for mode in ("ground", "sky")},
            "seeds": [{"seed": row["seed"], "status": row["status"]} for row in snapshot["seeds"]
                      if row["seed"] in required]}


def _effective_render_matches(scenario: dict[str, Any], report: dict[str, Any]) -> bool:
    """Require the selected policy and viewport to agree throughout the measured sample."""
    observation = scenario.get("effective_render")
    if (not isinstance(observation, dict) or observation.get("stable") is not True
            or not _is_int(observation.get("samples")) or observation["samples"] < 2):
        return False
    start, end = observation.get("start"), observation.get("end")
    if not isinstance(start, dict) or start != end:
        return False
    policy = start.get("reconstruction")
    settings = report.get("render_settings")
    reported_policy = settings.get("reconstruction") if isinstance(settings, dict) else None
    if not isinstance(policy, dict) or not isinstance(reported_policy, dict):
        return False
    backend_status = reported_policy.get("backend")
    if backend_status is not None and (not isinstance(backend_status, dict)
                                       or backend_status.get("backend_failed", False) is not False):
        return False
    override = scenario.get("render_override")
    if override is not None and not isinstance(override, dict):
        return False
    override = override or {}
    requested_mode = override.get("reconstruction", "native")
    if not isinstance(requested_mode, str):
        return False
    mode = requested_mode
    if requested_mode == "auto":
        mode = policy.get("auto_selected")
        if mode not in ("native", "metalfx_spatial_85", "metalfx_spatial_quality"):
            return False
        auto_size, window_size = policy.get("auto_output_size"), start.get("window_size_property")
        visible = start.get("visible_rect_size")
        if (not isinstance(auto_size, list) or len(auto_size) != 2
                or any(type(value) is not int or value <= 0 or not _is_number(value) for value in auto_size)
                or window_size != auto_size
                or not isinstance(window_size, list) or len(window_size) != 2
                or any(type(value) is not int or value <= 0 for value in window_size)
                or not isinstance(visible, list) or len(visible) != 2
                or any(not _is_number(value) or value <= 0 for value in visible)):
            return False
        output_scope = reported_policy.get("output_size_scope")
        reported_output = reported_policy.get("output_size")
        if "output_size_scope" not in reported_policy:
            # Older receipts called the logical canvas size output_size.
            if "logical_canvas_size" in reported_policy or "nominal_3d_size_scope" in reported_policy:
                return False
            reported_visible = reported_output
        elif output_scope == "viewport_render_target_estimate_v1":
            reported_visible = reported_policy.get("logical_canvas_size")
            nominal = reported_policy.get("nominal_3d_size")
            reported_scale = reported_policy.get("scale")
            if (not isinstance(reported_output, list) or len(reported_output) != 2
                    or any(type(value) is not int or value <= 0 for value in reported_output)
                    or reported_output != auto_size
                    or reported_policy.get("nominal_3d_size_scope") != "scaled_viewport_estimate_not_sdk_execution"
                    or not isinstance(nominal, list) or len(nominal) != 2
                    or any(type(value) is not int or value <= 0 for value in nominal)
                    or not _is_number(reported_scale) or not 0.1 <= reported_scale <= 2.0
                    or any(not _is_number(pixels * reported_scale) for pixels in reported_output)
                    or any(value != max(1, int(pixels * reported_scale))
                           for value, pixels in zip(nominal, reported_output))):
                return False
        else:
            return False
        if (not isinstance(reported_visible, list) or len(reported_visible) != 2
                or any(not _is_number(value) or value <= 0 for value in reported_visible)
                or any(not _close(a, b, tolerance=1e-6) for a, b in zip(visible, reported_visible))):
            return False
    if mode not in BENCHMARK_RECONSTRUCTION:
        return False
    provider, nominal_scale = BENCHMARK_RECONSTRUCTION[mode]
    temporal = provider not in ("native", "metalfx_spatial")
    scale = override.get("scaling_3d_scale", nominal_scale)
    requested_msaa = override.get("msaa_3d", 2)
    if (not _is_number(scale) or not 0.25 <= scale <= 1.0
            or (provider != "native" and not _close(scale, nominal_scale, tolerance=2e-6))
            or type(requested_msaa) is not int or not 0 <= requested_msaa <= 3
            or (temporal and "msaa_3d" in override and requested_msaa != 0)):
        return False
    expected_msaa = 0 if temporal else requested_msaa
    mode_constant = "SCALING_3D_MODE_BILINEAR" if provider == "native" else "SCALING_3D_MODE_" + provider.upper()
    if (start.get("backend") != report.get("backend")
            or start.get("driver") != report.get("rendering_driver")
            or not isinstance(start.get("backend"), str) or not start["backend"]
            or not isinstance(start.get("driver"), str) or not start["driver"]
            or type(start.get("scaling_3d_mode")) is not int or start["scaling_3d_mode"] < 0
            or start.get("scaling_3d_mode_constant") != mode_constant
            or type(start.get("provider_mode_id")) is not int or start["provider_mode_id"] != start["scaling_3d_mode"]
            or (provider == "native" and start["scaling_3d_mode"] != 0)
            or (provider != "native" and start["scaling_3d_mode"] == 0)
            or not _is_number(start.get("scaling_3d_scale"))
            or not _close(start["scaling_3d_scale"], scale, tolerance=2e-6)
            or type(start.get("msaa_3d")) is not int or start["msaa_3d"] != expected_msaa):
        return False
    if (policy.get("requested") != requested_mode or policy.get("selected") != mode
            or policy.get("effective") != mode or policy.get("requested_provider") != provider
            or policy.get("provider") != provider or policy.get("effective_provider") != provider
            or policy.get("provider_available") is not True or policy.get("fallback") is not False
            or policy.get("fallback_reason") != "" or policy.get("temporal") is not temporal
            or policy.get("execution_status") != "policy_selected"
            or type(policy.get("scaling_3d_mode")) is not int
            or policy.get("scaling_3d_mode") != start["scaling_3d_mode"]
            or not _is_number(policy.get("scale")) or not _close(policy["scale"], scale, tolerance=2e-6)
            or type(policy.get("msaa_3d")) is not int or policy.get("msaa_3d") != expected_msaa
            or type(settings.get("scaling_3d_mode")) is not int or type(settings.get("msaa_3d")) is not int
            or not _is_number(settings.get("scaling_3d_scale"))):
        return False
    return all(settings.get(key) == start[key] for key in ("scaling_3d_mode", "scaling_3d_scale", "msaa_3d")) \
        and all(reported_policy.get(key) == value for key, value in policy.items())


def _benchmark_arguments_match(user: list[str], scenario: dict[str, Any], report: dict[str, Any]) -> bool:
    """Reconcile the checked command with the options forwarded by the fixture."""
    def parse(arguments: list[str]) -> tuple[dict[str, str | None], list[tuple[str, str]]] | None:
        options: dict[str, str | None] = {}
        ordered: list[tuple[str, str]] = []
        for argument in arguments:
            if not isinstance(argument, str) or not argument.startswith("--"):
                return None
            key, separator, value = argument[2:].partition("=")
            if not key or key in options:
                return None
            options[key] = value if separator else None
            ordered.append((key, argument))
        return options, ordered

    scene_arguments = scenario.get("arguments")
    if not isinstance(scene_arguments, list):
        return False
    parsed_user, parsed_scene = parse(user), parse(scene_arguments)
    if parsed_user is None or parsed_scene is None:
        return False
    requested, user_order = parsed_user
    effective, scene_order = parsed_scene
    for key, expected in BENCHMARK_FORCED_OPTIONS.items():
        if effective.get(key) != expected or (key in requested and requested[key] != expected):
            return False
    if (any(key in requested for key in BENCHMARK_REJECTED_OPTIONS | {"sustained-diagnostic-ticks"})
            or any(key in effective for key in ("case", "frametimes", "sustained-receipt", "sustained-hash",
                                               "sustained-observation", "sustained-diagnostic-ticks"))
            or ("sustained-observation" in requested and requested["sustained-observation"] != "on")
            or ("sustained-hash" in requested and requested["sustained-hash"] is not None)
            or scenario.get("state_input_hashing") is not ("sustained-hash" in requested)
            or ("frametimes-stream" in requested and requested["frametimes-stream"] is not None)
            or "frametimes-stream" not in effective or effective["frametimes-stream"] is not None):
        return False
    if not _render_override_matches(requested, scenario.get("render_override")):
        return False
    for option, default, report_key in (("t", 1800.0, "sample_s"), ("warmup", 30.0, "warmup_s")):
        try:
            if option in requested and requested[option] is None:
                return False
            actual = float(requested[option]) if option in requested else default
            planned = float(effective[option]) if option in effective and effective[option] is not None else math.nan
        except (TypeError, ValueError, OverflowError):
            return False
        if (not math.isfinite(actual) or not math.isfinite(planned)
                or not _is_number(report.get(report_key)) or not _close(actual, planned, tolerance=1e-9)
                or not _close(actual, float(report[report_key]), tolerance=1e-9)):
            return False
    ignore = BENCHMARK_INTERNAL_OPTIONS | BENCHMARK_FORCED_OPTIONS.keys()
    return ([raw for key, raw in user_order if key not in ignore]
            == [raw for key, raw in scene_order if key not in ignore])


def _render_override_matches(requested: dict[str, str | None], recorded: Any) -> bool:
    """The checked command and the fixture receipt must name the same sweep override."""
    expected: dict[str, float | int] = {}
    for option, field in BENCHMARK_RENDER_OVERRIDE_OPTIONS.items():
        if option not in requested:
            continue
        raw = requested[option]
        if field == "reconstruction":
            if not isinstance(raw, str) or not raw:
                return False
            expected[field] = raw
            continue
        try:
            expected[field] = float(raw) if field == "scaling_3d_scale" else int(raw)  # type: ignore[arg-type]
        except (TypeError, ValueError, OverflowError):
            return False
    if not expected:
        return recorded is None
    if not isinstance(recorded, dict) or set(recorded) != set(expected):
        return False
    for field, value in expected.items():
        actual = recorded[field]
        if field == "reconstruction":
            if actual != value:
                return False
        elif field == "msaa_3d":
            if type(actual) is not int or actual != value:
                return False
        elif not _is_number(actual) or not _close(float(actual), float(value), tolerance=1e-9):
            return False
    return True


def benchmark_checked_runner(report_path: Path, report: dict[str, Any], log_bytes: bytes | None,
                             declared_frame_path: str | None, scenario: dict[str, Any] | None) -> dict[str, Any]:
    """Verify the owning checked launch, including options hidden from Godot scripts."""
    path = report_path.with_name("checked-" + report_path.name)
    reasons: list[str] = []
    receipt_bytes: bytes | None = None
    receipt: Any = None
    try:
        if path.is_symlink():
            raise ValueError("checked receipt must not be a symbolic link")
        receipt_bytes = _read_bounded(path, MAX_BENCHMARK_CHECK_BYTES)
        receipt = json.loads(receipt_bytes.decode("utf-8"), parse_constant=_reject_constant,
                             object_pairs_hook=_unique_object)
        if not isinstance(receipt, dict):
            raise ValueError("checked receipt must be an object")
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError, RecursionError) as error:
        reasons.append(f"checked receipt is unreadable or malformed: {error}")

    if isinstance(receipt, dict):
        if (receipt.get("format") != "openrc-godot-check v1" or receipt.get("complete") is not True
                or receipt.get("ok") is not True or receipt.get("reason") != "passed"
                or type(receipt.get("exit_code")) is not int or receipt["exit_code"] != 0
                or type(receipt.get("process_exit")) is not int or receipt["process_exit"] != 0):
            reasons.append("checked invocation did not complete successfully")
        capture_id = report.get("capture_id")
        if not isinstance(capture_id, str) or not capture_id or receipt.get("capture_id") != capture_id:
            reasons.append("checked invocation capture ID does not match")
        if log_bytes is None or receipt.get("log_sha256") != _sha256_bytes(log_bytes):
            reasons.append("checked invocation log SHA-256 does not match")
        command = receipt.get("command")
        if (not isinstance(command, list) or not 1 <= len(command) <= 256
                or any(not isinstance(token, str) or not token or len(token) > 4096 for token in command)
                or "--" not in command):
            reasons.append("checked invocation command is missing or malformed")
        else:
            split = command.index("--")
            engine, user = command[:split], command[split + 1:]
            forbidden = {"--fixed-fps", "--write-movie", "--time-scale", "--frame-delay", "--disable-render-loop"}
            if any(token.partition("=")[0] in forbidden for token in engine):
                reasons.append("checked invocation uses a non-real-time or artificial engine option")
            if any(token.partition("=")[0] == "--gpu-profile" for token in engine):
                reasons.append("GPU profiling is diagnostic and ineligible for performance acceptance")
            if any(token.partition("=")[0] == "--headless"
                   or token in ("--display-driver=headless", "--rendering-driver=dummy")
                   or (token in ("--display-driver", "--rendering-driver") and index + 1 < len(engine)
                       and engine[index + 1] == ("headless" if token == "--display-driver" else "dummy"))
                   for index, token in enumerate(engine)):
                reasons.append("checked invocation uses a headless display")
            for option, field in (("--rendering-method", "backend"), ("--rendering-driver", "rendering_driver")):
                values: list[str] = []
                for index, token in enumerate(engine):
                    if token.startswith(option + "="):
                        values.append(token.partition("=")[2])
                    elif token == option:
                        values.append(engine[index + 1] if index + 1 < len(engine) else "")
                if (len(values) != 1 or not values[0] or values[0].startswith("--")
                        or values[0] != report.get(field)):
                    reasons.append(f"checked invocation must explicitly match the effective {option[2:]}")
            script_paths = []
            for index, token in enumerate(engine):
                if token == "--script" and index + 1 < len(engine):
                    script_paths.append(engine[index + 1])
                elif token.startswith("--script="):
                    script_paths.append(token.partition("=")[2])
            script_path = script_paths[0].replace("\\", "/") if len(script_paths) == 1 else ""
            script_suffix = "research/performance/sustained_flight.gd"
            if script_path != script_suffix and not script_path.endswith("/" + script_suffix):
                reasons.append("checked invocation did not use the benchmark script")

            def targets(option: str) -> list[str]:
                return [token[len(option):].replace("\\", "/") for token in user if token.startswith(option)]

            frame_targets = targets("--frametimes=")
            if (not isinstance(declared_frame_path, str) or len(frame_targets) != 1
                    or frame_targets[0] != declared_frame_path.replace("\\", "/")
                    or frame_targets[0].rsplit("/", 1)[-1] != report_path.name):
                reasons.append("checked invocation frame output does not match the report")
            health_targets = targets("--sustained-receipt=")
            frame_directory = frame_targets[0].rpartition("/")[0] if len(frame_targets) == 1 else ""
            expected_health = (frame_directory + "/" if frame_directory else "") + "health-" + report_path.name
            if health_targets != [expected_health]:
                reasons.append("checked invocation health output does not match the report")
            if not isinstance(scenario, dict):
                reasons.append("checked invocation workload reconciliation unavailable because benchmark health scenario is ineligible")
            elif not _benchmark_arguments_match(user, scenario, report):
                reasons.append("checked invocation workload arguments do not match the benchmark scenario")

    return {
        "receipt": path.name,
        "receipt_sha256": _sha256_bytes(receipt_bytes) if receipt_bytes is not None else None,
        "eligible": not reasons,
        "reasons": reasons,
    }


def summarize_run(report_path: Path, policy: dict[str, Any]) -> dict[str, Any]:
    report_bytes: bytes | None = None
    log_bytes: bytes | None = None
    report: dict[str, Any] | None = None
    errors: list[str] = []
    report_format: str | None = None
    log_path = report_path.with_suffix(".log")

    try:
        report_bytes = _read_bounded(report_path, MAX_REPORT_BYTES)
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
        log_bytes = _read_bounded(log_path, MAX_LOG_BYTES)
        try:
            log_text = _decode_log(log_bytes)
        except UnicodeError as error:
            log_decode_error = f"matching log encoding is invalid: {error}"
            log_text = log_bytes.decode("utf-8", errors="replace")
        engine_errors = _log_error_lines(log_text)
    except (OSError, ValueError) as error:
        errors.append(f"matching log is unavailable: {error}")
    if log_decode_error:
        errors.append(log_decode_error)
    if engine_errors:
        errors.append("matching log contains Godot ERROR output")

    derived: dict[str, Any] | None = None
    stream_evidence: dict[str, Any] | None = None
    if report is not None:
        if report_format == STREAM_FORMAT:
            try:
                hydrated, stream_evidence = _hydrate_stream_report(report, report_path)
                schema_errors, derived = validate_native_report(hydrated)
                errors.extend(schema_errors)
            except (OSError, UnicodeError, ValueError, OverflowError, RecursionError) as error:
                errors.append(f"stream is unreadable or invalid: {error}")
        else:
            schema_errors, derived = validate_native_report(report)
            errors.extend(schema_errors)

    collection_valid = not errors
    benchmark: dict[str, Any] | None = None
    checked_benchmark: dict[str, Any] | None = None
    if report is not None and report.get("route") == BENCHMARK_ROUTE:
        benchmark = benchmark_health(report_path, report_bytes, report, stream_evidence)
        checked_benchmark = benchmark_checked_runner(report_path, report, log_bytes, benchmark["declared_frame_path"],
                                                       benchmark["scenario"])
    active_reasons: list[str] = []
    pacing: dict[str, Any] | None = None
    duration: dict[str, Any] | None = None
    if report is not None and derived is not None:
        active_reasons = active_flight_reasons(
            report, derived, policy,
            benchmark_eligible=bool(benchmark and benchmark["eligible"]
                                    and checked_benchmark and checked_benchmark["eligible"]),
        )
        if benchmark is not None and not benchmark["eligible"]:
            active_reasons.append("benchmark health receipt is ineligible")
        if checked_benchmark is not None and not checked_benchmark["eligible"]:
            active_reasons.append("benchmark checked-runner receipt is ineligible")
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
    rendering = rendering_gate(hydrated if report_format == STREAM_FORMAT and stream_evidence is not None else report) if report is not None else {
        "status": "unknown", "eligible": False, "reason": "report is unavailable"}
    performance_pass = bool(
        collection_valid and active_qualifier and duration and duration["eligible"]
        and pacing and pacing["pass"] and rendering["eligible"]
    )
    return {
        "report": report_path.name,
        "report_format": report_format,
        "report_sha256": _sha256_bytes(report_bytes) if report_bytes is not None else None,
        "capture_id": report.get("capture_id") if report is not None else None,
        "stream": stream_evidence,
        "log": log_path.name,
        "log_sha256": _sha256_bytes(log_bytes) if log_bytes is not None else None,
        "engine_errors": engine_errors,
        "collection_valid": collection_valid,
        "collection_reasons": errors,
        "active_flight_qualifier": active_qualifier,
        "active_flight_reasons": active_reasons,
        "benchmark_health": benchmark,
        "benchmark_checked_runner": checked_benchmark,
        "workload_scope": ("technical-benchmark-circuit" if benchmark is not None else
                           "direct-live-input" if report is not None and report.get("route") == "live-input"
                           else "other-or-unknown"),
        "normal_product_route_qualified": False,
        "session_at_report": report.get("session_at_report") if report is not None else None,
        "duration_eligibility": duration,
        "rendering_eligibility": rendering,
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
    scopes = [run["workload_scope"] for run in runs]
    workload_scope_consistent = bool(scopes) and all(scope == scopes[0] for scope in scopes)
    if scopes and not workload_scope_consistent:
        campaign_reasons.append("runs use different workload routes")
    benchmarks = [run["benchmark_health"] for run in runs]
    benchmark_identity_consistent: bool | None = None
    benchmark_capture_ids_distinct: bool | None = None
    if any(item is not None for item in benchmarks):
        identities = [
            (item.get("source_identity_sha256"), item.get("scenario")) if item is not None else None
            for item in benchmarks
        ]
        benchmark_identity_consistent = bool(identities) and all(
            item is not None and item[0] is not None and item[1] is not None and item == identities[0]
            for item in identities
        )
        if not benchmark_identity_consistent:
            campaign_reasons.append("benchmark source or scenario identities differ or are incomplete")
        capture_ids = [run["capture_id"] for run in runs]
        benchmark_capture_ids_distinct = bool(capture_ids) and all(
            isinstance(capture_id, str) and capture_id for capture_id in capture_ids
        ) and len(set(capture_ids)) == len(capture_ids)
        if not benchmark_capture_ids_distinct:
            campaign_reasons.append("benchmark capture IDs are missing or repeated")
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
        and workload_scope_consistent and benchmark_identity_consistent is not False
        and benchmark_capture_ids_distinct is not False
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
        "workload_scope_consistent": workload_scope_consistent,
        "benchmark_identity_consistent": benchmark_identity_consistent,
        "benchmark_capture_ids_distinct": benchmark_capture_ids_distinct,
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
    parser.add_argument("--minimum-warmup-s", type=float, default=DEFAULT_POLICY["minimum_warmup_s"],
                        help="minimum requested and actual warm-up in seconds (default: 10)")
    parser.add_argument("--minimum-sample-s", type=float, default=DEFAULT_POLICY["minimum_sample_s"],
                        help="minimum requested sample duration in seconds (default: 60)")
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
        "minimum_warmup_s": args.minimum_warmup_s,
        "minimum_sample_s": args.minimum_sample_s,
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
