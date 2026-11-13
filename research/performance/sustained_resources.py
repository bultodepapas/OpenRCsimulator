#!/usr/bin/env python3
"""Reduce checked process telemetry to the interior of a validated live flight.

This is an offline research reader. It neither launches the game nor changes any
performance or native-admission gate. The saved checked report remains the owner
of the telemetry attachment; paths are rebased only through its original layout.
"""
from __future__ import annotations

import argparse
from bisect import bisect_left, bisect_right
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from research.performance import native_summary as native
from tools.godot import macos_host_state as host
from tools.godot import perfetto_export as perfetto

FORMAT = "openrc-sustained-process-resources v1"
MAX_RESOURCE_BYTES = 32 * 1024 * 1024
MAX_CLOCK_DRIFT_MS = 50.0
CPU_FIELDS = ("cpu_user_seconds", "cpu_system_seconds")
EDGE_WINDOW_SECONDS = 300


class WindowUnavailable(ValueError):
    """The requested interior has insufficient polls or simulation progress."""


def _read(path: Path, limit: int) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"missing or linked evidence: {path}")
    with path.open("rb") as source:
        data = source.read(limit + 1)
    if not data or len(data) > limit:
        raise ValueError(f"empty or oversized evidence: {path}")
    return data


def _json(data: bytes) -> dict[str, Any]:
    value = json.loads(data.decode("utf-8"), parse_constant=native._reject_constant,
                       object_pairs_hook=native._unique_object)
    if not isinstance(value, dict):
        raise ValueError("evidence must be a JSON object")
    return value


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _finite(value: Any) -> bool:
    return type(value) in (int, float) and math.isfinite(value)


def _checked_hierarchy(run: Path, checked: dict[str, Any]) -> Path:
    """Map the original absolute parent to this copy, never rewrite a receipt."""
    declared = checked.get("report")
    if not isinstance(declared, str) or "\\" in declared:
        raise ValueError("checked report must declare an absolute POSIX path")
    p = PurePosixPath(declared)
    if not p.is_absolute() or ".." in p.parts or p.name != "report.json":
        raise ValueError("checked report path is not an absolute report.json")
    if len(p.parts) < 5 or p.parent.parent.name != "checks":
        raise ValueError("checked report is outside the original checks hierarchy")
    if re.fullmatch(r"godot-[A-Za-z0-9_-]+", p.parent.name) is None:
        raise ValueError("checked capture directory has an invalid name")
    frame = PurePosixPath(str(checked.get("_frame_path", "")))
    if not frame.is_absolute() or ".." in frame.parts or frame.name != run.name or frame.parent != p.parent.parent.parent:
        raise ValueError("frame and checked report do not share their original run directory")
    if checked.get("log") != str(p.parent / "engine.log"):
        raise ValueError("checked log is outside its original capture directory")
    directory = run.parent / "checks" / p.parent.name
    if directory.is_symlink() or directory.parent.is_symlink():
        raise ValueError("checked capture hierarchy must not contain symbolic links")
    return directory


def _verify_process(report: dict[str, Any], resources: dict[str, Any], checked: dict[str, Any]) -> None:
    pid = report.get("pid")
    if type(pid) is not int or pid <= 0 or resources.get("pid") != pid:
        raise ValueError("frame and sampled process PID mismatch")
    if resources.get("identity_status") != "verified":
        raise ValueError("sampled process identity was not verified throughout")
    created = resources.get("process_create_time")
    if not _finite(created) or created <= 0:
        raise ValueError("process creation time is missing")
    try:
        stamp = datetime.fromisoformat(checked["started_utc"])
        if stamp.tzinfo is None:
            raise ValueError("timestamp has no timezone")
        started = stamp.timestamp()
        resource_start = resources["clock"]["start"]["unix_usec"] / 1_000_000
    except (KeyError, TypeError, ValueError, OverflowError) as error:
        raise ValueError("process creation-time context is invalid") from error
    # psutil creation times and UTC anchors are system estimates, not attestation.
    if not started - 1 <= created <= resource_start + 1:
        raise ValueError("process creation time does not fit this launch and sampling start")


def _validate_resource_series(resources: dict[str, Any]) -> list[dict[str, Any]]:
    _, _, info = perfetto._validate_resources(resources)
    if not info["required_coverage_validated"]:
        raise ValueError("required-channel coverage receipt is absent")
    if (resources.get("capped") is not False or resources.get("stop_reason") != "caller_finished"
            or resources.get("coverage") not in ("sampled", "partial")
            or resources.get("errors_truncated") is not False):
        raise ValueError("resource sampling stopped early, was capped, or has truncated errors")
    if resources.get("identity_status") != "verified":
        raise ValueError("resource process identity is not verified")
    interval = resources.get("interval_seconds")
    maximum = resources.get("max_samples")
    if (not _finite(interval) or not 0.1 <= interval <= 60
            or type(maximum) is not int or not 2 <= maximum <= 10000):
        raise ValueError("resource sampling bounds are invalid")
    samples = resources["samples"]
    if len(samples) < 2 or len(samples) >= maximum:
        raise ValueError("insufficient samples or exhausted resource sample budget")
    sources = resources.get("tool_source_sha256")
    if (not isinstance(sources, dict) or any(not isinstance(sources.get(name), str)
            or re.fullmatch(r"[0-9a-f]{64}", sources[name]) is None
            for name in ("run_checked.py", "resource_samples.py"))):
        raise ValueError("resource sampler source identities are missing or invalid")
    resets = resources.get("summary", {}).get("counter_resets")
    if not isinstance(resets, list) or any(field in resets for field in CPU_FIELDS):
        raise ValueError("CPU counter resets are present or unknown")
    for error in resources.get("errors", []):
        field, code = str(error.get("field", "")), str(error.get("code", ""))
        if (field in CPU_FIELDS or any(s in (field + " " + code).lower()
                for s in ("identity", "process", "clock", "cpu", "pid"))):
            raise ValueError("resource sampler recorded a CPU, identity or clock error")
    previous = None
    for sample in samples:
        overhead = sample.get("poll_overhead_usec")
        if type(overhead) is not int or not 0 <= overhead <= interval * 1_000_000:
            raise ValueError("resource poll duration is missing or exceeds its interval")
        for field in CPU_FIELDS:
            value = sample.get(field)
            if sample.get("field_status", {}).get(field) != "ok" or not _finite(value) or value < 0:
                raise ValueError(f"required CPU channel {field} is unavailable")
            if previous is not None and value < previous[field]:
                raise ValueError(f"required CPU counter {field} decreased")
        previous = sample
    return samples


def _window(frames: dict[str, Any], resources: dict[str, Any], samples: list[dict[str, Any]],
            *, bounds: tuple[int, int] | None = None) -> dict[str, Any]:
    frame_clock = perfetto._frame_clock(frames)
    resource_clock = perfetto._resource_clock(resources)
    if frame_clock is None or resource_clock is None:
        raise ValueError("frame/resource clocks are unavailable")
    clock, frame_offset, resource_offset = perfetto._combined_clock(frame_clock, resource_clock, MAX_CLOCK_DRIFT_MS)
    margin = clock["combined_uncertainty_usec"] + clock["max_clock_drift_usec"] + 2
    ends, walls = frames["frame_end_monotonic_usec"], frames["frame_wall_usec"]
    perfetto._check_clock_coverage(frame_clock, ends[0] - walls[0], ends[-1], "frame", MAX_CLOCK_DRIFT_MS)
    times = [resource_clock["origin_usec"] + round(s["elapsed_seconds"] * 1_000_000) for s in samples]
    perfetto._check_clock_coverage(resource_clock, times[0], times[-1], "resource", MAX_CLOCK_DRIFT_MS)
    aligned = [t + resource_offset for t in times]
    starts = [t - s["poll_overhead_usec"] - 1 for t, s in zip(aligned, samples)]
    finishes = [t + 1 for t in aligned]
    full_start, full_end = ends[0] - walls[0] + frame_offset, ends[-1] + frame_offset
    if finishes[0] + margin > full_start or starts[-1] - margin < full_end:
        raise ValueError("resource polls do not bracket the complete measured flight")
    frame_start, frame_end = full_start, full_end
    if bounds is not None:
        if (not isinstance(bounds, tuple) or len(bounds) != 2
                or any(type(value) is not int for value in bounds)
                or not full_start <= bounds[0] < bounds[1] <= full_end):
            raise ValueError("requested bounds are outside the measured frame window")
        frame_start, frame_end = bounds
    max_gap = max(b - a for a, b in zip(aligned, aligned[1:]))
    gap_limit = round(max(2 * resources["interval_seconds"], resources["interval_seconds"] + .25) * 1_000_000)
    if max_gap > gap_limit:
        raise ValueError("resource poll gap exceeds the bounded coverage allowance")
    eligible = [i for i in range(len(samples)) if starts[i] - margin >= frame_start and finishes[i] + margin <= frame_end]
    if len(eligible) < 2:
        raise WindowUnavailable("fewer than two resource polls lie wholly inside flight")
    first, last = eligible[0], eligible[-1]
    first_frame = bisect_left(ends, finishes[first] + margin - frame_offset)
    last_frame = bisect_right(ends, starts[last] - margin - frame_offset) - 1
    if not 0 <= first_frame < last_frame < len(ends):
        raise WindowUnavailable("resource endpoints do not enclose a matched simulation interval")
    sim = frames["raw_metrics"]["sim_time_s"]
    ticks = frames["raw_metrics"]["sim_tick"]
    sim_seconds = sim[last_frame] - sim[first_frame]
    if not _finite(sim_seconds) or sim_seconds <= 0 or ticks[last_frame] <= ticks[first_frame]:
        raise WindowUnavailable("matched simulation interval does not advance")
    selected = samples[first:last + 1]
    cpu = sum(samples[last][field] - samples[first][field] for field in CPU_FIELDS)
    wall = (aligned[last] - aligned[first]) / 1_000_000
    wall_min = (starts[last] - finishes[first]) / 1_000_000
    wall_max = (finishes[last] - starts[first]) / 1_000_000
    if wall_min <= 0:
        raise WindowUnavailable("resource poll intervals overlap")
    return {"first_index": first, "last_index": last, "samples": selected,
            "clock": clock, "margin_usec": margin, "frame_bounds_usec": [frame_start, frame_end],
            "poll_start_usec": starts[first], "poll_end_usec": finishes[last],
            "first_poll_end_usec": finishes[first], "last_poll_start_usec": starts[last],
            "selected_timestamps_usec": [aligned[first], aligned[last]], "max_poll_gap_usec": max_gap,
            "poll_overhead_usec": [samples[first]["poll_overhead_usec"], samples[last]["poll_overhead_usec"]],
            "requested_poll_interval_seconds": resources["interval_seconds"],
            "omitted_frame_start_usec_upper_bound": finishes[first] + margin - frame_start,
            "omitted_frame_end_usec_upper_bound": frame_end - starts[last] + margin,
            "selected_wall_fraction_of_frame_window": (aligned[last] - aligned[first]) / (frame_end - frame_start),
            "gap_limit_usec": gap_limit, "cpu_core_seconds": cpu, "wall_seconds": wall,
            "wall_seconds_poll_bracket": [wall_min, wall_max],
            "simulation_seconds": sim_seconds, "simulation_ticks": ticks[last_frame] - ticks[first_frame],
            "frame_indices": [first_frame, last_frame],
            "frame_times_usec": [ends[first_frame] + frame_offset, ends[last_frame] + frame_offset],
            "matched_frame_start_lag_usec": ends[first_frame] + frame_offset - aligned[first],
            "matched_frame_end_lead_usec": aligned[last] - ends[last_frame] - frame_offset}


def _metric(samples: list[dict[str, Any]], field: str) -> dict[str, Any]:
    statuses = [sample.get("field_status", {}).get(field, "missing") for sample in samples]
    if not all(status == "ok" for status in statuses):
        return {"status": "unknown", "statuses": sorted(set(statuses)), "start": None, "end": None,
                "end_minus_start": None, "sampled_min": None, "sampled_peak": None}
    values = [sample[field] for sample in samples]
    return {"status": "ok", "start": values[0], "end": values[-1],
            "end_minus_start": values[-1] - values[0], "sampled_min": min(values), "sampled_peak": max(values)}


def _host_context(directory: Path, checked: dict[str, Any], report: dict[str, Any],
                  window: dict[str, Any], retained: dict[Path, str]) -> dict[str, Any]:
    receipt = checked.get("host_state")
    unknown = {"status": "unknown", "thermal": None, "low_power": None, "power_source": None,
               "memory_pressure": {"initial": "unknown", "events": None}}
    if receipt is None:
        if window["clock"]["mode"] == "aligned_raw_uptime":
            raise ValueError("raw uptime alignment requires the checked host helper and sleep evidence")
        return unknown
    if not isinstance(receipt, dict) or receipt.get("file") != "host-state.jsonl":
        raise ValueError("host attachment receipt is invalid")
    path = directory / "host-state.jsonl"
    raw = _read(path, host.MAX_BYTES)
    if receipt.get("bytes") != len(raw) or receipt.get("sha256") != _sha(raw):
        raise ValueError("host attachment differs from its original receipt")
    retained[path] = _sha(raw)
    observed = host.validate_stream(raw, report["capture_id"], report["pid"])
    for key, value in observed.items():
        if receipt.get(key) != value:
            raise ValueError(f"host receipt disagrees with validated stream: {key}")
    if (receipt.get("capture_id") != report["capture_id"] or receipt.get("helper_exit") != 0
            or receipt.get("identity_checks") != "stable_at_prelaunch_postlaunch_and_stop"
            or receipt.get("identity_errors") != []):
        raise ValueError("host helper identity or lifecycle is incomplete")
    helper = receipt.get("helper_sha256")
    if not isinstance(helper, str) or not re.fullmatch(r"[0-9a-f]{64}", helper):
        raise ValueError("host helper digest is missing")
    if window["clock"]["mode"] == "aligned_raw_uptime":
        if window["clock"]["frame_raw_offset"].get("helper_sha256") != helper:
            raise ValueError("frame clock helper differs from checked host helper")
        if observed.get("sleep_check", {}).get("within_tolerance") is not True:
            raise ValueError("host sleep/clock continuity evidence is missing")
    else:
        return {**unknown, "reason": "host raw-uptime timestamps are not joined to this UTC alignment"}
    rows = [json.loads(line) for line in raw.splitlines()]
    low, high = window["first_poll_end_usec"], window["last_poll_start_usec"]
    margin = window["margin_usec"]
    outer_low, outer_high = window["poll_start_usec"] - margin, window["poll_end_usec"] + margin
    snapshots = [r for r in rows if r.get("type") == "snapshot"
                 and r["query_start_usec"] >= low + margin and r["query_end_usec"] <= high - margin]
    state_events = [r for r in rows if r.get("type") == "event" and r.get("source") in ("thermal", "low_power")]
    def certainly_inside(row: dict[str, Any]) -> bool:
        return row["query_start_usec"] >= low + margin and row["query_end_usec"] <= high - margin
    def possibly_inside(row: dict[str, Any]) -> bool:
        return row["query_end_usec"] >= outer_low and row["query_start_usec"] <= outer_high
    definite_state = [row for row in state_events if certainly_inside(row)]
    uncertain_state = [row for row in state_events if possibly_inside(row) and not certainly_inside(row)]
    brackets = (observed["first_snapshot_usec"] <= outer_low
                and observed["last_snapshot_usec"] >= outer_high
                and observed["pressure_ready_usec"] <= outer_low)
    result: dict[str, Any] = {"status": "complete" if observed["coverage"] == "complete" and brackets else "partial",
                              "stream_coverage": observed["coverage"], "brackets_selected_interval": brackets,
                              "stream_snapshot_bounds_usec": [observed["first_snapshot_usec"], observed["last_snapshot_usec"]],
                              "stream_max_snapshot_gap_usec": observed["max_snapshot_gap_usec"],
                              "snapshots_in_window": len(snapshots),
                              "sleep_check": observed.get("sleep_check"),
                              "limitations": ("host-wide snapshots/events; pressure initially unknown and OS event loss "
                                              "unknown; nominal thermal may be the platform fallback")}
    for field in ("thermal", "low_power", "power_source"):
        observations = snapshots + (definite_state if field != "power_source" else [])
        statuses = sorted({r[field]["status"] for r in observations})
        values = sorted({r[field]["value"] for r in observations if r[field]["status"] == "available"})
        result[field] = {"status": "ok" if snapshots and statuses == ["available"] else "unknown",
                         "values": values if snapshots and statuses == ["available"] else None,
                         "observed_statuses": statuses}
    def state_summary(row: dict[str, Any]) -> dict[str, Any]:
        return {key: row[key] for key in ("source", "monotonic_usec", "query_start_usec", "query_end_usec",
                                          "thermal", "low_power")}
    result["state_transitions"] = {"events": [state_summary(row) for row in definite_state],
                                   "boundary_uncertain_events": [state_summary(row) for row in uncertain_state]}
    pressure = [r for r in rows if r.get("type") == "event" and r.get("source") == "memory_pressure"]
    events = [r for r in pressure if low + margin <= r["monotonic_usec"] <= high - margin]
    uncertain = [r for r in pressure if outer_low <= r["monotonic_usec"] <= outer_high and r not in events]
    def pressure_summary(row: dict[str, Any]) -> dict[str, Any]:
        return {"monotonic_usec": row["monotonic_usec"], "flags": row["flags"]}
    result["memory_pressure"] = {"initial": "unknown", "events": [pressure_summary(row) for row in events],
                                 "boundary_uncertain_events": [pressure_summary(row) for row in uncertain],
                                 "os_coalesced_or_dropped": None}
    return result


def _window_section(frames: dict[str, Any], resources: dict[str, Any], samples: list[dict[str, Any]],
                    directory: Path, checked: dict[str, Any], report: dict[str, Any], retained: dict[Path, str],
                    *, bounds: tuple[int, int] | None = None) -> dict[str, Any]:
    window = _window(frames, resources, samples, bounds=bounds)
    context = _host_context(directory, checked, report, window, retained)
    cpu, wall, sim = window["cpu_core_seconds"], window["wall_seconds"], window["simulation_seconds"]
    selected = window.pop("samples")
    return {"clock": window.pop("clock"), "window": window,
            "cpu": {"core_seconds": cpu, "wall_seconds": wall, "percent_of_one_core": 100 * cpu / wall,
                    "percent_range_from_poll_timing_only": [100 * cpu / window["wall_seconds_poll_bracket"][1],
                                                            100 * cpu / window["wall_seconds_poll_bracket"][0]],
                    "per_matched_simulated_second_estimate": cpu / sim,
                    "simulation_denominator_scope": "frame endpoints strictly inside CPU polls; boundary mismatch retained in window"},
            "process_memory": {"rss_bytes": _metric(selected, "rss_bytes"),
                               "footprint_bytes": {"status": "unknown", "value": None}},
            "host_memory": {key: _metric(selected, key) for key in
                            ("virtual_memory_available_bytes", "virtual_memory_percent", "swap_used_bytes", "swap_total_bytes")},
            "host_state": context}


def _edge_windows(frames: dict[str, Any], resources: dict[str, Any], samples: list[dict[str, Any]],
                  directory: Path, checked: dict[str, Any], report: dict[str, Any], retained: dict[Path, str],
                  full: dict[str, Any], seconds: int) -> dict[str, Any]:
    """Return disjoint, interior-poll portions of the first and final windows."""
    if type(seconds) is not int or seconds != EDGE_WINDOW_SECONDS:
        raise ValueError("window seconds must be 300")
    full_start, full_end = full["window"]["frame_bounds_usec"]
    span = seconds * 1_000_000
    result: dict[str, Any] = {"requested_seconds": seconds,
                              "measured_flight_seconds": (full_end - full_start) / 1_000_000,
                              "status": "unavailable", "early": None, "final": None}
    if full_end - full_start < 2 * span:
        result["reason"] = "measured flight is shorter than two nonoverlapping requested windows"
        return result
    try:
        early = _window_section(frames, resources, samples, directory, checked, report, retained,
                                bounds=(full_start, full_start + span))
        final = _window_section(frames, resources, samples, directory, checked, report, retained,
                                bounds=(full_end - span, full_end))
    except WindowUnavailable as error:
        result["reason"] = str(error)
        return result
    a, b = early["window"], final["window"]
    if a["poll_end_usec"] + a["margin_usec"] > b["poll_start_usec"] - b["margin_usec"]:
        result["reason"] = "selected early and final polls overlap within their clock uncertainty"
        return result
    result.update(status="available", reason=None, early=early, final=final)
    return result


def reduce_run(run: Path, *, window_seconds: int | None = None) -> dict[str, Any]:
    if window_seconds is not None and (type(window_seconds) is not int or window_seconds != EDGE_WINDOW_SECONDS):
        raise ValueError("window seconds must be 300")
    run = Path(run)
    retained: dict[Path, str] = {}
    def keep(path: Path, limit: int) -> bytes:
        data = _read(path, limit)
        retained[path] = _sha(data)
        return data

    report_bytes = keep(run, native.MAX_REPORT_BYTES)
    report = _json(report_bytes)
    health_path = run.with_name("health-" + run.name)
    checked_path = run.with_name("checked-" + run.name)
    log_path = run.with_suffix(".log")
    health = _json(keep(health_path, native.MAX_BENCHMARK_HEALTH_BYTES))
    checked_bytes = keep(checked_path, native.MAX_BENCHMARK_CHECK_BYTES)
    checked = _json(checked_bytes)
    keep(log_path, native.MAX_LOG_BYTES)
    validation = native.summarize_run(run, native.DEFAULT_POLICY)
    if (not validation.get("collection_valid") or not validation.get("active_flight_qualifier")
            or not validation.get("benchmark_health", {}).get("eligible")
            or not validation.get("benchmark_checked_runner", {}).get("eligible")):
        raise ValueError("flight stream, health or checked-run validation failed")
    if validation.get("report_sha256") != _sha(report_bytes):
        raise ValueError("frame report changed during flight validation")
    checked_for_path = dict(checked, _frame_path=health.get("frame_report"))
    directory = _checked_hierarchy(run, checked_for_path)
    original_path = directory / "report.json"
    original = keep(original_path, native.MAX_BENCHMARK_CHECK_BYTES)
    if original != checked_bytes:
        raise ValueError("run checked receipt differs from original nested checked report")
    original_log = keep(directory / "engine.log", native.MAX_LOG_BYTES)
    if _sha(original_log) != checked.get("log_sha256") or retained[log_path] != _sha(original_log):
        raise ValueError("original and copied engine logs do not match the checked report")
    receipt = checked.get("resources")
    if not isinstance(receipt, dict) or receipt.get("file") != "resources.json" or receipt.get("published") is not True:
        raise ValueError("original checked report lacks published resources")
    resource_path = directory / "resources.json"
    raw = keep(resource_path, MAX_RESOURCE_BYTES)
    if receipt.get("bytes") != len(raw) or receipt.get("sha256") != _sha(raw):
        raise ValueError("resources differ from the original checked receipt")
    resources = _json(raw)
    for key in ("coverage", "required_coverage", "sample_count", "measurement_status", "summary"):
        if receipt.get(key) != resources.get(key):
            raise ValueError(f"resource receipt disagrees on {key}")
    capture_id = report.get("capture_id")
    invocation = resources.get("invocation")
    if (resources.get("capture_id") != capture_id or not isinstance(invocation, dict)
            or invocation.get("capture_id") != capture_id
            or any(invocation.get(k) != checked.get(k) for k in
                   ("command", "cwd", "started_utc", "process_exit", "reason", "log_sha256", "elapsed_seconds"))):
        raise ValueError("resource invocation does not match the original checked report")
    _verify_process(report, resources, checked)
    samples = _validate_resource_series(resources)
    frames, stream = native._hydrate_stream_report(report, run)
    stream_path = run.with_name(stream["file"])
    retained[stream_path] = stream["sha256"]
    section = _window_section(frames, resources, samples, directory, checked, report, retained)
    output = {"capture_id": capture_id, "pid": resources["pid"], "process_create_time": resources["process_create_time"],
              "report": str(run), "report_sha256": _sha(report_bytes), "checked_report_sha256": _sha(original),
              "resources_sha256": _sha(raw), "stream_sha256": stream["sha256"],
              "resource_tool_source_sha256": resources["tool_source_sha256"],
              "flight_identity": {key: report.get(key) for key in
                                  ("case_id", "aircraft_id", "godot", "os", "os_version", "architecture", "adapter",
                                   "backend", "rendering_driver", "window", "warmup_s", "sample_s")},
              "flight_source_identity_sha256": validation["benchmark_health"].get("source_identity_sha256"),
              "capture": {key: resources.get(key) for key in
                          ("coverage", "required_coverage", "measurement_status", "identity_status", "stop_reason",
                           "capped", "sample_count", "error_count", "errors_truncated")},
              "backend": health.get("backend_proof", {}).get("requested", "gdscript_reference"),
              "scope": ("direct whole Godot process including benchmark observation, all process threads; "
                        "excludes runner, sampler, helper, descendants, GPU and energy"),
              **section,
              "limitations": ["CPU is cumulative process user+system time, not callback elapsed time",
                              "CPU denominator uses poll completion timestamps; per-poll overhead and clock margins are retained",
                              "sampled memory peaks can miss brief spikes; host-wide memory is not process attribution",
                              "no GPU, energy, child-process or physical-validation claim"]}
    if window_seconds is not None:
        output["edge_windows"] = _edge_windows(frames, resources, samples, directory, checked, report, retained,
                                               section, window_seconds)
    for path, digest in retained.items():
        limit = native.STREAM_MAX_BYTES if path == stream_path else max(MAX_RESOURCE_BYTES, native.MAX_BENCHMARK_HEALTH_BYTES)
        if _sha(_read(path, limit)) != digest:
            raise ValueError(f"evidence changed during reduction: {path}")
    return output


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, action="append", required=True, help="flight run-N.json; repeat for each run")
    parser.add_argument("--window-seconds", type=int, choices=[EDGE_WINDOW_SECONDS],
                        help="also report the first and final 300 seconds of flights at least 600 seconds long")
    parser.add_argument("--out", type=Path, required=True, help="new JSON output path")
    args = parser.parse_args(argv)
    try:
        runs = [reduce_run(path, window_seconds=args.window_seconds) for path in args.run]
        if len({run["capture_id"] for run in runs}) != len(runs):
            raise ValueError("capture IDs must be distinct")
        result = {"format": FORMAT, "runs": runs, "qualification": "research-only; no admission or performance claim"}
        payload = (json.dumps(result, indent=2, allow_nan=False) + "\n").encode("utf-8")
        with args.out.open("xb") as stream:
            stream.write(payload)
    except (OSError, ValueError, TypeError, KeyError, OverflowError) as error:
        print(f"sustained resource reduction failed: {error}", file=sys.stderr)
        return 1
    print(args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
