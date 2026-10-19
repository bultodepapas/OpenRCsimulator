#!/usr/bin/env python3
"""Reduce an r3 frame report + FRAME-R3 trace to bounded JSON evidence."""

from __future__ import annotations

import argparse
import bisect
import json
import math
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
	with path.open("r", encoding="utf-8-sig") as stream:
		value = json.load(stream)
	if not isinstance(value, dict):
		raise ValueError(f"expected JSON object: {path}")
	return value


def number(value: Any) -> float | None:
	if isinstance(value, bool) or not isinstance(value, (int, float)):
		return None
	result = float(value)
	return result if math.isfinite(result) else None


def quantile(sorted_values: list[float], fraction: float) -> float | None:
	if not sorted_values:
		return None
	position = (len(sorted_values) - 1) * fraction
	low = math.floor(position)
	high = math.ceil(position)
	if low == high:
		return sorted_values[low]
	return sorted_values[low] * (high - position) + sorted_values[high] * (position - low)


def stats(values: list[Any], scale: float = 1.0, digits: int = 3) -> dict[str, Any]:
	clean = sorted(v * scale for value in values if (v := number(value)) is not None)
	if not clean:
		return {"n": 0, "p50": None, "p95": None, "p99": None, "max": None}
	return {
		"n": len(clean),
		"p50": round(quantile(clean, 0.50) or 0.0, digits),
		"p95": round(quantile(clean, 0.95) or 0.0, digits),
		"p99": round(quantile(clean, 0.99) or 0.0, digits),
		"max": round(clean[-1], digits),
	}


def value_range(rows: list[dict[str, Any]], key: str, digits: int = 3) -> dict[str, Any]:
	values = [v for row in rows if (v := number(row.get(key))) is not None]
	if not values:
		return {"n": 0, "min": None, "max": None}
	return {"n": len(values), "min": round(min(values), digits), "max": round(max(values), digits)}


def frame_rows(report: dict[str, Any]) -> list[dict[str, Any]]:
	durations = report.get("frame_wall_usec")
	if not isinstance(durations, list):
		deltas = report.get("frame_deltas_s")
		durations = [v * 1_000_000.0 for v in deltas] if isinstance(deltas, list) else []
	ends = report.get("frame_end_monotonic_usec")
	if not isinstance(ends, list):
		ends = []
	start = number(report.get("actual_sample_start_monotonic_usec"))
	end = number(report.get("actual_sample_end_monotonic_usec"))
	rows: list[dict[str, Any]] = []
	for index, raw_duration in enumerate(durations):
		duration = number(raw_duration)
		stamp = number(ends[index]) if index < len(ends) else None
		if duration is None or duration <= 0:
			continue
		if stamp is not None and ((start is not None and stamp < start) or (end is not None and stamp > end)):
			continue
		rows.append({
			"frame_row_index": index,
			"frame_end_usec": int(stamp) if stamp is not None else None,
			"wall_usec": duration,
			"wall_ms": duration / 1000.0,
		})
	return rows


def nearest_by(rows: list[dict[str, Any]], key: str, target: int) -> tuple[dict[str, Any] | None, int | None]:
	eligible = [(int(value), row) for row in rows if (value := number(row.get(key))) is not None and value > 0]
	if not eligible:
		return None, None
	values = [item[0] for item in eligible]
	index = bisect.bisect_left(values, target)
	choices = [i for i in (index - 1, index) if 0 <= i < len(eligible)]
	best = min(choices, key=lambda i: abs(values[i] - target))
	stamp, row = eligible[best]
	return row, stamp - target


def main_span_fields(row: dict[str, Any]) -> dict[str, Any]:
	return {
		field: row.get(field)
		for field in (
			"main_total_usec", "main_world_usec", "main_audio_usec", "main_panel_usec",
			"main_pose_usec", "main_hud_usec", "main_overlay_usec", "main_other_usec",
		)
		if field in row
	}


def trace_join(frame_row: dict[str, Any], trace_rows: list[dict[str, Any]]) -> dict[str, Any]:
	target = frame_row.get("frame_end_usec")
	if target is None:
		return {"status": "no frame-end monotonic timestamp"}
	main_row, main_delta = nearest_by(trace_rows, "main_end_usec", int(target))
	sample_row, sample_delta = nearest_by(trace_rows, "usec", int(target))
	return {
		"method": "nearest monotonic timestamps; frame index is not used to align observers",
		"main_callback": None if main_row is None else {
			"trace_elapsed_s": main_row.get("elapsed_s"),
			"signed_trace_minus_frame_usec": main_delta,
			"main_spans_usec": main_span_fields(main_row),
		},
		"observer_interval": None if sample_row is None else {
			"trace_elapsed_s": sample_row.get("elapsed_s"),
			"signed_trace_minus_frame_usec": sample_delta,
			"paused": sample_row.get("paused"),
			"focused": sample_row.get("focused"),
			"physics_callbacks": sample_row.get("physics_callbacks"),
			"physics_tick_count": sample_row.get("physics_tick_count"),
			"physics_total_usec": sample_row.get("physics_total_usec"),
			"physics_max_usec": sample_row.get("physics_max_usec"),
			"render_last_frame": {
				"setup_cpu_ms_latest": sample_row.get("render_setup_cpu_ms"),
				"viewport_cpu_ms_previous_render_frame": sample_row.get("render_cpu_ms"),
				"viewport_gpu_ms_previous_render_frame": sample_row.get("render_gpu_ms"),
			},
			"performance_monitors_lagged_context": {
				"process_usec": sample_row.get("process_monitor_usec_lagged"),
				"physics_process_usec": sample_row.get("physics_monitor_usec_lagged"),
				"nodes": sample_row.get("nodes_monitor"),
				"resources": sample_row.get("resources_monitor"),
				"orphans": sample_row.get("orphans_monitor"),
			},
		},
	}


def reduce(report: dict[str, Any], trace: dict[str, Any]) -> dict[str, Any]:
	frame_samples = frame_rows(report)
	trace_samples = trace.get("samples", [])
	if not isinstance(trace_samples, list):
		trace_samples = []
	trace_rows = [row for row in trace_samples if isinstance(row, dict)]
	warmup_s = number(trace.get("warmup_s"))
	if warmup_s is None:
		warmup_s = number(report.get("actual_warmup_s")) or number(report.get("warmup_s")) or 0.0
	postwarm_trace = [row for row in trace_rows if (number(row.get("elapsed_s")) or 0.0) >= warmup_s]
	frame_top = sorted(frame_samples, key=lambda row: row["wall_usec"], reverse=True)[:5]
	for row in frame_top:
		row["trace_join"] = trace_join(row, trace_rows)

	active_rows = [
		row for row in postwarm_trace
		if row.get("focused") is True and row.get("paused") is False
		and row.get("fault") in (None, "") and row.get("crash_active") is not True
	]
	active_wall_usec = sum(max(0.0, number(row.get("wall_delta_usec")) or 0.0) for row in active_rows)
	active_ticks = sum(max(0, int(number(row.get("physics_tick_count")) or 0)) for row in active_rows)
	active_callbacks = sum(max(0, int(number(row.get("physics_callbacks")) or 0)) for row in active_rows)
	physics_hz = number(report.get("simulation", {}).get("physics_ticks_per_second")) if isinstance(report.get("simulation"), dict) else None
	physics_hz = physics_hz or 240.0
	expected_ticks = active_wall_usec / 1_000_000.0 * physics_hz
	active_tick_ratio = active_ticks / expected_ticks if expected_ticks > 0 else None

	initial = trace.get("initial_route", {}) if isinstance(trace.get("initial_route"), dict) else {}
	final = trace.get("final_route", {}) if isinstance(trace.get("final_route"), dict) else {}
	violations = trace.get("route_violations", [])
	if not isinstance(violations, list):
		violations = []
	controls_unchanged = all(row.get("control_state_matches_start") is True for row in postwarm_trace)
	input_stayed_disabled = all(row.get("input_enabled") is False for row in postwarm_trace)
	crash_seen = any(row.get("crash_active") is True for row in postwarm_trace) or bool(final.get("crash"))
	fault_seen = any(bool(row.get("fault")) for row in postwarm_trace) or bool(final.get("fault"))
	active_sample_count = len(active_rows)
	setup_valid = (
		initial.get("tick_before_input_disable") == 0
		and initial.get("input_disabled_before_first_physics") is True
		and initial.get("input_enabled") is False
		and initial.get("physics_enabled") is True
		and initial.get("sim_paused") is False
		and initial.get("scripted_flight_mode") is False
		and initial.get("scripted_frametimes_mode") is False
	)
	steady_flight_usable = setup_valid and not violations and controls_unchanged and input_stayed_disabled \
		and not crash_seen and not fault_seen and active_sample_count > 0

	timed_fields = {
		"observer_wall_delta_ms": ("wall_delta_usec", 1 / 1000.0),
		"main_total_ms": ("main_total_usec", 1 / 1000.0),
		"main_world_ms": ("main_world_usec", 1 / 1000.0),
		"main_audio_ms": ("main_audio_usec", 1 / 1000.0),
		"main_panel_ms": ("main_panel_usec", 1 / 1000.0),
		"main_pose_ms": ("main_pose_usec", 1 / 1000.0),
		"main_hud_ms": ("main_hud_usec", 1 / 1000.0),
		"main_overlay_ms": ("main_overlay_usec", 1 / 1000.0),
		"main_other_ms": ("main_other_usec", 1 / 1000.0),
		"physics_step_total_per_observer_interval_ms": ("physics_total_usec", 1 / 1000.0),
		"physics_largest_step_per_observer_interval_ms": ("physics_max_usec", 1 / 1000.0),
		"render_setup_cpu_latest_ms": ("render_setup_cpu_ms", 1.0),
		"render_viewport_cpu_previous_frame_ms": ("render_cpu_ms", 1.0),
		"render_viewport_gpu_previous_frame_ms": ("render_gpu_ms", 1.0),
	}
	timings = {
		label: stats([row.get(field) for row in postwarm_trace], scale)
		for label, (field, scale) in timed_fields.items()
	}
	monitor_ranges = {
		"static_memory_bytes": value_range(postwarm_trace, "static_memory_monitor", 0),
		"video_memory_bytes": value_range(postwarm_trace, "video_memory_monitor", 0),
		"nodes": value_range(postwarm_trace, "nodes_monitor", 0),
		"resources": value_range(postwarm_trace, "resources_monitor", 0),
		"orphan_nodes": value_range(postwarm_trace, "orphans_monitor", 0),
	}

	return {
		"format": "openrc-frame-stall-reduction v1",
		"inputs": {
			"frame_report": report.get("format"),
			"trace": trace.get("format"),
			"trace_source_freeze_sha256": trace.get("source_freeze_sha256"),
		},
		"validity": {
			"fixed_trim_route_setup_valid": setup_valid,
			"controls_unchanged_postwarmup": controls_unchanged,
			"input_stayed_disabled_postwarmup": input_stayed_disabled,
			"route_violations": violations[:10],
			"focused_unpaused_noncrash_samples": active_sample_count,
			"crash_seen": crash_seen,
			"fault_seen": fault_seen,
			"steady_flight_usable": steady_flight_usable,
			"pause_event_count": len(trace.get("pause_events", [])) if isinstance(trace.get("pause_events"), list) else None,
			"focus_event_count": len(trace.get("focus_events", [])) if isinstance(trace.get("focus_events"), list) else None,
		},
		"window": {
			"warmup_s": round(warmup_s, 3),
			"postwarm_frame_rows": len(frame_samples),
			"postwarm_trace_rows": len(postwarm_trace),
			"frame_report_complete": report.get("complete"),
			"frame_report_failure": report.get("failure"),
		},
		"frame_wall_ms": stats([row["wall_ms"] for row in frame_samples]),
		"trace_timed_spans": timings,
		"physics_cadence": {
			"physics_hz": physics_hz,
			"focused_unpaused_wall_s": round(active_wall_usec / 1_000_000.0, 3),
			"tick_count": active_ticks,
			"callback_count": active_callbacks,
			"expected_ticks_wall_times_hz": round(expected_ticks, 2),
			"observed_to_expected_ratio": round(active_tick_ratio, 4) if active_tick_ratio is not None else None,
		},
		"scene_and_memory_ranges": monitor_ranges,
		"top_hitches": [
			{
				"frame_row_index": row["frame_row_index"],
				"frame_end_monotonic_usec": row["frame_end_usec"],
				"wall_ms": round(row["wall_ms"], 3),
				"trace_join": row.get("trace_join"),
			}
			for row in frame_top
		],
		"alignment_notes": {
			"trace_join": "Top frame stalls join by nearest monotonic timestamps (Main callback end and observer sample separately), never by frame index. Signed timestamp deltas are retained.",
			"render_cpu_gpu": "RenderingServer viewport CPU/GPU values report the last rendered frame at the observer sample; they are one completed-render sample behind that read point and exclude script/physics time.",
			"render_setup": "get_frame_setup_time_cpu is reported as the latest shared server value and is not treated as an exact per-frame callback span.",
			"performance_monitors": "TIME_PROCESS, TIME_PHYSICS_PROCESS and scene/resource counts are lagged contextual monitors, not timestamp-exact attribution.",
			"loads_audio": "The probe measures Main's existing audio-update span and resource/object counts; it does not capture audio-thread time or file/resource-load events.",
		},
	}


def main() -> None:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--frame", type=Path, required=True, help="Main --frametimes JSON report")
	parser.add_argument("--trace", type=Path, required=True, help="FRAME-R3 .trace.json observer output")
	parser.add_argument("--out", type=Path, help="write summary JSON here; defaults to stdout")
	args = parser.parse_args()
	result = reduce(load_json(args.frame), load_json(args.trace))
	encoded = json.dumps(result, indent=2, sort_keys=True) + "\n"
	if args.out:
		if args.out.exists():
			parser.error(f"refusing to overwrite output: {args.out}")
		args.out.parent.mkdir(parents=True, exist_ok=True)
		args.out.write_text(encoded, encoding="utf-8")
	else:
		print(encoded, end="")


if __name__ == "__main__":
	main()
