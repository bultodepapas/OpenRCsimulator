#!/usr/bin/env python3
"""Measure source-pinned reachable-bank forecasts against their flown states.

Forecast samples are matched at their exact 0.25 s / 60-physics-tick offsets.
Each origin is censored only when its bank target changes or releases; a later
forecast origin with the same target is a replan, not a censor boundary. The
output is empirical data for this fixture, never a physical or continuous-time
error bound.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from typing import Any

EVENT_PREFIXES = ("AFC_REACHABLE_TARGET ", "AFC_REACHABLE_FORECAST ")
PHYSICS_HZ = 240
PLAN_TICKS = 4
STEP_TICKS = 60
POINT_COUNT = 33
HORIZON_S = 8.0
EXPECTED_TICKS = 4800
EXPECTED_ROWS = EXPECTED_TICKS + 1
EXPECTED_CASE = "seed-20261020-crossing-right"
TARGET_TOLERANCE_DEG = 1e-5


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def read_engine_events(path: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    targets: list[dict[str, Any]] = []
    forecasts: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8", errors="replace") as stream:
        for line_number, line in enumerate(stream, 1):
            for prefix, destination in ((EVENT_PREFIXES[0], targets), (EVENT_PREFIXES[1], forecasts)):
                index = line.find(prefix)
                if index < 0:
                    continue
                event = json.loads(line[index + len(prefix):].strip())
                if not isinstance(event, dict):
                    raise ValueError(f"non-object trace event at {path}:{line_number}")
                event["_line"] = line_number
                destination.append(event)
                break
    return targets, forecasts


def checked_case(report_path: Path, expected_pilot_sha256: str) -> dict[str, Any]:
    report = read_json(report_path)
    if report.get("process_success") is not True or report.get("valid_complete_runs") is not True:
        raise ValueError(f"encounter probe is incomplete or invalid: {report_path}")
    if report.get("seconds") != 20 or report.get("requested_ticks") != EXPECTED_TICKS:
        raise ValueError(f"run is not the requested 20-second/4,800-tick capture: {report_path}")
    if report.get("recording_mode") != "single_crossing_right":
        raise ValueError(f"run is not the bounded single crossing-right fixture: {report_path}")
    if report.get("pilot_source_sha256") != expected_pilot_sha256:
        raise ValueError(f"pilot source hash mismatch: {report_path}")
    cases = report.get("cases")
    if not isinstance(cases, list) or len(cases) != 1:
        raise ValueError(f"expected exactly one encounter case: {report_path}")
    case = cases[0]
    if case.get("case_id") != EXPECTED_CASE or case.get("complete") is not True \
            or case.get("ticks") != EXPECTED_TICKS or case.get("requested_ticks") != EXPECTED_TICKS:
        raise ValueError(f"crossing-right case is incomplete or mismatched: {report_path}")
    if case.get("pilot_refusal") or case.get("ai_fault") or case.get("ai_crash"):
        raise ValueError(f"pilot fault, refusal, or crash in {report_path}")
    return {"report": report, "case": case}


def check_replay(path: Path, orfl_sha256: str) -> dict[str, Any]:
    report = read_json(path)
    if report.get("mode") != "exact" or report.get("status") != "ok" \
            or report.get("complete") is not True or report.get("solver_changed") is not False:
        raise ValueError(f"exact replay did not complete on the recorded solver: {path}")
    if report.get("rows") != EXPECTED_ROWS or report.get("source_sha256") != orfl_sha256:
        raise ValueError(f"replay rows or ORFL source identity mismatch: {path}")
    if report.get("baseline_solver_sha256") != report.get("current_solver_sha256"):
        raise ValueError(f"replay baseline/current solver hashes differ: {path}")
    return report


def read_flight_csv(path: Path) -> dict[int, dict[str, float]]:
    rows: dict[int, dict[str, float]] = {}
    with path.open("r", newline="", encoding="utf-8") as stream:
        for raw in csv.DictReader(stream):
            tick = int(raw["tick"])
            if tick in rows:
                raise ValueError(f"duplicate simulation tick {tick} in {path}")
            rows[tick] = {
                key: float(raw[key]) for key in
                ("north_m", "east_m", "down_m", "stick_roll",
                 "qw", "qx", "qy", "qz", "p_radps")
            }
    if len(rows) != EXPECTED_ROWS or sorted(rows) != list(range(EXPECTED_ROWS)):
        raise ValueError(f"expected exact consecutive replay rows 0..{EXPECTED_TICKS}: {path}")
    if any(not math.isfinite(value) for row in rows.values() for value in row.values()):
        raise ValueError(f"nonfinite replay data in {path}")
    return rows


def _finite_number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"invalid finite number for {label}: {value!r}")
    return float(value)


def check_event_streams(targets: list[dict[str, Any]], forecasts: list[dict[str, Any]],
                        trace_case: dict[str, Any]) -> None:
    summary = trace_case.get("prediction_flight_trace", {})
    if not isinstance(summary, dict) or summary.get("enabled") is not True:
        raise ValueError("trace candidate did not report its flight trace as enabled")
    if summary.get("capped") is not False:
        raise ValueError("trace candidate hit a bounded trace cap")
    if summary.get("forecast_origin_cap") != 1200 or summary.get("event_cap") != 2400:
        raise ValueError("trace source caps differ from the receipt contract")
    if len(targets) > 1200 or len(forecasts) > 1200 or len(targets) + len(forecasts) > 2400:
        raise ValueError("trace event count exceeded its explicit bounds")
    if summary.get("target_state_events_written") != len(targets) \
            or summary.get("forecast_origins_written") != len(forecasts) \
            or summary.get("total_trace_events_written") != len(targets) + len(forecasts):
        raise ValueError("candidate trace summary does not match the engine log")
    if len(targets) != 1200:
        raise ValueError(f"expected one target-state row per planning tick; observed {len(targets)}")
    expected_ticks = list(range(0, EXPECTED_TICKS, PLAN_TICKS))
    target_ticks = [event.get("tick") for event in targets]
    if target_ticks != expected_ticks:
        raise ValueError("target-state trace does not cover the complete 60 Hz planning grid")
    forecast_ticks = [event.get("tick") for event in forecasts]
    if len(forecast_ticks) != len(set(forecast_ticks)) or any(
            not isinstance(tick, int) or tick not in expected_ticks for tick in forecast_ticks):
        raise ValueError("forecast origins are duplicated or off the 60 Hz planning grid")
    by_tick = {event["tick"]: event for event in targets}
    for event in targets:
        if not isinstance(event.get("target_active"), bool):
            raise ValueError("target event has no boolean active flag")
        _finite_number(event.get("returned_roll_command"), "returned roll command")
        if event["target_active"]:
            _finite_number(event.get("bank_target_deg"), "active bank target")
            if event.get("matches_selected_bank") is not True:
                raise ValueError(f"active bank target differs from selected bank at tick {event['tick']}")
        elif event.get("bank_target_deg") is not None:
            raise ValueError(f"inactive target unexpectedly has a bank target at tick {event['tick']}")
    for event in forecasts:
        tick = event.get("tick")
        if event.get("forecast_id") != tick or event.get("target_active") is not True:
            raise ValueError(f"invalid forecast origin metadata: tick {tick}")
        if abs(_finite_number(event.get("step_s"), "forecast step") - STEP_TICKS / PHYSICS_HZ) > 1e-12 \
                or abs(_finite_number(event.get("horizon_s"), "forecast horizon") - HORIZON_S) > 1e-12:
            raise ValueError(f"forecast step or horizon differs from 0.25 s / 8.0 s at tick {tick}")
        selected_bank = _finite_number(event.get("selected_bank_deg"), "forecast selected bank")
        target_bank = _finite_number(event.get("bank_target_deg"), "forecast bank target")
        path = event.get("predicted_own_positions_ned")
        if not isinstance(path, list) or len(path) != POINT_COUNT * 3:
            raise ValueError(f"forecast at tick {tick} does not contain 33 NED points")
        if any(isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value)
               for value in path):
            raise ValueError(f"forecast at tick {tick} contains a nonfinite coordinate")
        if by_tick[tick].get("target_active") is not True \
                or abs(_finite_number(by_tick[tick].get("bank_target_deg"), "active target bank") - target_bank) > TARGET_TOLERANCE_DEG:
            raise ValueError(f"forecast and applied target record disagree at tick {tick}")
        if abs(selected_bank - target_bank) > TARGET_TOLERANCE_DEG \
                or event.get("matches_selected_bank") is not True:
            raise ValueError(f"selected bank is not the emitted bank target at tick {tick}")


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    location = (len(ordered) - 1) * fraction
    lower = math.floor(location)
    upper = math.ceil(location)
    if lower == upper:
        return ordered[lower]
    portion = location - lower
    return ordered[lower] * (1.0 - portion) + ordered[upper] * portion


def _same_target(first: dict[str, Any], second: dict[str, Any]) -> bool:
    if first["target_active"] != second["target_active"]:
        return False
    if not first["target_active"]:
        return True
    return abs(float(first["bank_target_deg"]) - float(second["bank_target_deg"])) <= TARGET_TOLERANCE_DEG


def summarize_target_transitions(targets: list[dict[str, Any]]) -> dict[str, Any]:
    events: list[dict[str, Any]] = []
    if targets and targets[0]["target_active"]:
        events.append({
            "tick": targets[0]["tick"],
            "kind": "initial_active_target",
            "from_bank_target_deg": None,
            "to_bank_target_deg": targets[0]["bank_target_deg"],
        })
    for previous, current in zip(targets, targets[1:]):
        if _same_target(previous, current):
            continue
        if previous["target_active"] and not current["target_active"]:
            kind = "release"
        elif not previous["target_active"] and current["target_active"]:
            kind = "activation"
        else:
            kind = "bank_target_change"
        events.append({
            "tick": current["tick"],
            "kind": kind,
            "from_bank_target_deg": previous.get("bank_target_deg"),
            "to_bank_target_deg": current.get("bank_target_deg"),
            "held_before": previous["has_held_maneuver"],
            "held_after": current["has_held_maneuver"],
        })
    kinds = ("initial_active_target", "activation", "bank_target_change", "release")
    counts = {kind: sum(event["kind"] == kind for event in events) for kind in kinds}
    return {"counts": counts, "events": events}


def recompute_roll_command(targets: list[dict[str, Any]], actual: dict[int, dict[str, float]]) -> dict[str, Any]:
    checked = 0
    mismatches: list[dict[str, Any]] = []
    for event in targets:
        if not event["target_active"]:
            continue
        state = actual[event["tick"]]
        w, x, y, z = (state[key] for key in ("qw", "qx", "qy", "qz"))
        current_bank = math.atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y))
        expected_roll = 1.8 * (math.radians(float(event["bank_target_deg"])) - current_bank) \
            - 0.35 * state["p_radps"]
        expected_roll = min(max(expected_roll, -1.0), 1.0)
        observed_roll = float(event["returned_roll_command"])
        checked += 1
        if abs(expected_roll - observed_roll) > 1e-8:
            mismatches.append({
                "tick": event["tick"],
                "target_bank_deg": event["bank_target_deg"],
                "current_bank_rad": current_bank,
                "body_roll_rate_rad_s": state["p_radps"],
                "formula_roll": expected_roll,
                "returned_roll": observed_roll,
            })
    return {"checked_active_target_commands": checked,
            "formula_mismatch_count": len(mismatches),
            "formula_mismatches": mismatches[:20]}


def analyze_errors(targets: list[dict[str, Any]], forecasts: list[dict[str, Any]],
                   actual: dict[int, dict[str, float]]) -> dict[str, Any]:
    target_by_tick = {event["tick"]: event for event in targets}
    sorted_forecasts = sorted(forecasts, key=lambda event: event["tick"])
    errors_by_horizon: dict[str, list[float]] = {f"{step / 4:.2f}": [] for step in range(1, 33)}
    horizontal_by_horizon: dict[str, list[float]] = {f"{step / 4:.2f}": [] for step in range(1, 33)}
    vertical_by_horizon: dict[str, list[float]] = {f"{step / 4:.2f}": [] for step in range(1, 33)}
    origin_results: list[dict[str, Any]] = []
    origin_alignment_errors: list[float] = []
    origin_alignment_horizontal: list[float] = []
    origin_alignment_vertical: list[float] = []
    for origin_index, forecast in enumerate(sorted_forecasts):
        origin = int(forecast["tick"])
        start_target = target_by_tick[origin]
        transition_tick: int | None = None
        for tick in sorted(target_by_tick):
            if tick <= origin:
                continue
            if not _same_target(start_target, target_by_tick[tick]):
                transition_tick = tick
                break
        path = forecast["predicted_own_positions_ned"]
        matched_offsets: list[int] = []
        matched_errors: list[float] = []
        matched_horizontal: list[float] = []
        matched_vertical: list[float] = []
        for offset in range(POINT_COUNT):
            actual_tick = origin + offset * STEP_TICKS
            if actual_tick > EXPECTED_TICKS or (transition_tick is not None and actual_tick > transition_tick):
                break
            predicted = path[offset * 3:offset * 3 + 3]
            observed = actual[actual_tick]
            delta_north = predicted[0] - observed["north_m"]
            delta_east = predicted[1] - observed["east_m"]
            delta_down = predicted[2] - observed["down_m"]
            horizontal_error = math.hypot(delta_north, delta_east)
            vertical_error = abs(delta_down)
            error = math.sqrt(horizontal_error * horizontal_error + vertical_error * vertical_error)
            if not math.isfinite(error):
                raise ValueError(f"nonfinite residual from forecast origin {origin}")
            matched_offsets.append(offset)
            matched_errors.append(error)
            matched_horizontal.append(horizontal_error)
            matched_vertical.append(vertical_error)
            if offset == 0:
                origin_alignment_errors.append(error)
                origin_alignment_horizontal.append(horizontal_error)
                origin_alignment_vertical.append(vertical_error)
            else:
                horizon = f"{offset * 0.25:.2f}"
                errors_by_horizon[horizon].append(error)
                horizontal_by_horizon[horizon].append(horizontal_error)
                vertical_by_horizon[horizon].append(vertical_error)
        next_forecast_tick = int(sorted_forecasts[origin_index + 1]["tick"]) \
            if origin_index + 1 < len(sorted_forecasts) else None
        same_target_replan = next_forecast_tick is not None and next_forecast_tick > origin \
            and (transition_tick is None or next_forecast_tick < transition_tick) \
            and _same_target(start_target, target_by_tick[next_forecast_tick])
        origin_results.append({
            "forecast_id": forecast["forecast_id"],
            "origin_tick": origin,
            "bank_target_deg": forecast["bank_target_deg"],
            "next_target_transition_tick": transition_tick,
            "next_forecast_replan_tick": next_forecast_tick,
            "next_replan_kept_same_target": same_target_replan,
            "matched_sample_count_including_origin": len(matched_offsets),
            "matched_horizon_s": max(matched_offsets) * 0.25 if matched_offsets else 0.0,
            "matched_errors_m": matched_errors,
            "matched_horizontal_errors_m": matched_horizontal,
            "matched_vertical_errors_m": matched_vertical,
            "full_8s_horizon_matched": len(matched_offsets) == POINT_COUNT,
            "full_8s_data_available": origin + int(HORIZON_S * PHYSICS_HZ) <= EXPECTED_TICKS,
        })
    horizon_summary: dict[str, Any] = {}
    horizontal_horizon_summary: dict[str, Any] = {}
    vertical_horizon_summary: dict[str, Any] = {}
    for horizon, values in errors_by_horizon.items():
        horizon_summary[horizon] = {
            "sample_count": len(values),
            "max_m": max(values) if values else None,
            "p50_m": percentile(values, 0.50),
            "p95_m": percentile(values, 0.95),
            "p99_m": percentile(values, 0.99),
            "interpretation": "empirical overlapping forecast-origin samples; not a safety bound",
        }
        horizontal_values = horizontal_by_horizon[horizon]
        horizontal_horizon_summary[horizon] = {
            "sample_count": len(horizontal_values),
            "max_m": max(horizontal_values) if horizontal_values else None,
            "p50_m": percentile(horizontal_values, 0.50),
            "p95_m": percentile(horizontal_values, 0.95),
            "p99_m": percentile(horizontal_values, 0.99),
            "interpretation": "empirical overlapping horizontal samples; not a safety bound",
        }
        vertical_values = vertical_by_horizon[horizon]
        vertical_horizon_summary[horizon] = {
            "sample_count": len(vertical_values),
            "max_m": max(vertical_values) if vertical_values else None,
            "p50_m": percentile(vertical_values, 0.50),
            "p95_m": percentile(vertical_values, 0.95),
            "p99_m": percentile(vertical_values, 0.99),
            "interpretation": "empirical absolute down-axis samples; not a safety bound",
        }
    all_errors = [value for item in origin_results for value in item["matched_errors_m"]]
    all_horizontal = [value for item in origin_results for value in item["matched_horizontal_errors_m"]]
    all_vertical = [value for item in origin_results for value in item["matched_vertical_errors_m"]]
    full_data_ceiling = (EXPECTED_TICKS - int(HORIZON_S * PHYSICS_HZ)) // PLAN_TICKS + 1
    return {
        "forecast_origins_emitted": len(forecasts),
        "target_state_events": len(targets),
        "potential_planner_origins": EXPECTED_TICKS // PLAN_TICKS,
        "raw_full_horizon_data_ceiling_origins": full_data_ceiling,
        "full_horizon_data_available_origins": sum(item["full_8s_data_available"] for item in origin_results),
        "full_8s_target_compatible_origins": sum(item["full_8s_horizon_matched"] for item in origin_results),
        "forecasts_followed_by_same_target_replan_before_next_0_25s_sample": sum(
            item["next_replan_kept_same_target"] for item in origin_results),
        "origin_count_with_at_least_one_positive_horizon_sample": sum(
            item["matched_sample_count_including_origin"] > 1 for item in origin_results),
        "maximum_observed_matching_duration_s": max(
            (item["matched_horizon_s"] for item in origin_results), default=0.0),
        "forecast_origin_alignment_residuals_m": {
            "sample_count": len(origin_alignment_errors),
            "first_origin_m": origin_alignment_errors[0] if origin_alignment_errors else None,
            "max_m": max(origin_alignment_errors) if origin_alignment_errors else None,
            "p95_m": percentile(origin_alignment_errors, 0.95),
            "max_horizontal_m": max(origin_alignment_horizontal) if origin_alignment_horizontal else None,
            "max_vertical_m": max(origin_alignment_vertical) if origin_alignment_vertical else None,
        },
        "all_matched_residuals_m": {
            "sample_count_including_origin": len(all_errors),
            "max_m": max(all_errors) if all_errors else None,
            "p50_m": percentile(all_errors, 0.50),
            "p95_m": percentile(all_errors, 0.95),
            "p99_m": percentile(all_errors, 0.99),
        },
        "all_matched_horizontal_residuals_m": {
            "sample_count_including_origin": len(all_horizontal),
            "max_m": max(all_horizontal) if all_horizontal else None,
            "p50_m": percentile(all_horizontal, 0.50),
            "p95_m": percentile(all_horizontal, 0.95),
            "p99_m": percentile(all_horizontal, 0.99),
        },
        "all_matched_vertical_residuals_m": {
            "sample_count_including_origin": len(all_vertical),
            "max_m": max(all_vertical) if all_vertical else None,
            "p50_m": percentile(all_vertical, 0.50),
            "p95_m": percentile(all_vertical, 0.95),
            "p99_m": percentile(all_vertical, 0.99),
        },
        "residuals_by_horizon_s": horizon_summary,
        "horizontal_residuals_by_horizon_s": horizontal_horizon_summary,
        "vertical_residuals_by_horizon_s": vertical_horizon_summary,
        "origins": origin_results,
        "target_transitions_and_releases": summarize_target_transitions(targets),
        "path_error_m_claim": None,
        "path_error_bound_established": False,
        "continuity_or_between_sample_error_measured": False,
    }


def build(trace_engine_log: Path, trace_report_path: Path, trace_flight_csv: Path,
          baseline_report_path: Path, trace_ai_replay_path: Path, trace_player_replay_path: Path,
          baseline_ai_replay_path: Path, baseline_player_replay_path: Path,
          expected_production_pilot_sha256: str, expected_trace_pilot_sha256: str) -> dict[str, Any]:
    traced = checked_case(trace_report_path, expected_trace_pilot_sha256)
    baseline = checked_case(baseline_report_path, expected_production_pilot_sha256)
    t_report, b_report = traced["report"], baseline["report"]
    t_case, b_case = traced["case"], baseline["case"]
    if t_case.get("state_command_sha256") != b_case.get("state_command_sha256"):
        raise ValueError("traced/untraced state+command fingerprints differ")
    for key in ("weather", "field_id", "collision_identity", "lake_identity", "aircraft_id", "requested_ticks"):
        if t_report.get(key) != b_report.get(key):
            raise ValueError(f"traced/untraced fixture mismatch in {key}")
    if t_case.get("player_initial_spawn_spec") != b_case.get("player_initial_spawn_spec"):
        raise ValueError("traced/untraced player initial spawn differs")
    baseline_orfl = b_report["artifacts"]["recorded_logs"][EXPECTED_CASE]
    trace_orfl = t_report["artifacts"]["recorded_logs"][EXPECTED_CASE]
    if set(baseline_orfl) != {"ai", "player"} or set(trace_orfl) != {"ai", "player"}:
        raise ValueError("each paired run must retain exactly AI and coupled-player ORFL streams")
    for label, entries in (("baseline", baseline_orfl), ("traced", trace_orfl)):
        for role, item in entries.items():
            stream_path = Path(item["path"])
            if item.get("verified") is not True or item.get("rows_written") != EXPECTED_ROWS \
                    or item.get("stop_error") != 0 or not stream_path.is_file() \
                    or sha256(stream_path) != item.get("sha256"):
                raise ValueError(f"{label} {role} ORFL is incomplete or its source identity changed")
    replay_specs = [
        (trace_ai_replay_path, trace_orfl["ai"]["sha256"], "traced_ai"),
        (trace_player_replay_path, trace_orfl["player"]["sha256"], "traced_player"),
        (baseline_ai_replay_path, baseline_orfl["ai"]["sha256"], "baseline_ai"),
        (baseline_player_replay_path, baseline_orfl["player"]["sha256"], "baseline_player"),
    ]
    replays = {label: check_replay(path, source_hash)
               for path, source_hash, label in replay_specs}
    solvers = {item["current_solver_sha256"] for item in replays.values()}
    if len(solvers) != 1:
        raise ValueError("four exact replay reports do not share one current solver identity")
    targets, forecasts = read_engine_events(trace_engine_log)
    check_event_streams(targets, forecasts, t_case)
    actual = read_flight_csv(trace_flight_csv)
    target_by_tick = {item["tick"]: item for item in targets}
    command_formula = recompute_roll_command(targets, actual)
    if command_formula["formula_mismatch_count"]:
        raise ValueError("selected bank target to normalized roll response formula does not match ORFL state: "
                         + json.dumps(command_formula["formula_mismatches"][:3]))
    roll_checks = 0
    roll_mismatches: list[dict[str, Any]] = []
    for tick, event in target_by_tick.items():
        expected_roll = float(event["returned_roll_command"])
        for actual_tick in range(tick + 1, min(tick + PLAN_TICKS, EXPECTED_TICKS) + 1):
            roll_checks += 1
            observed_roll = actual[actual_tick]["stick_roll"]
            if abs(expected_roll - observed_roll) > 1e-8:
                roll_mismatches.append({"planning_tick": tick, "flight_tick": actual_tick,
                                        "returned_roll_command": expected_roll,
                                        "orfl_stick_roll": observed_roll})
    if roll_mismatches:
        raise ValueError(f"returned packet roll and ORFL stick_roll differ: {roll_mismatches[:3]}")
    residuals = analyze_errors(targets, forecasts, actual)
    return {
        "format": "afc-04-r6-reachable-bank-prediction-error-v1",
        "classification": "single-fixture empirical measurement; not physical validation or qualification",
        "fixture": {
            "case_id": EXPECTED_CASE,
            "seconds": 20,
            "physics_hz": PHYSICS_HZ,
            "planning_hz": PHYSICS_HZ / PLAN_TICKS,
            "forecast_step_s": 0.25,
            "forecast_horizon_s": HORIZON_S,
            "points_per_origin": POINT_COUNT,
            "trace_event_bounds": {"forecast_origins": 1200, "target_events": 1200,
                                   "combined_events": 2400},
            "baseline_pilot_sha256": expected_production_pilot_sha256,
            "trace_pilot_sha256": expected_trace_pilot_sha256,
            "paired_state_command_sha256": t_case["state_command_sha256"],
            "paired_fingerprint_exact": True,
            "solver_sha256": next(iter(solvers)),
            "world_match": True,
        },
        "command_semantics": {
            "bank_target": "the internal _selected_bank_target_rad passed to the roll response; it is an angle target in radians, not measured aircraft bank",
            "roll_command": "normalized packet.roll control returned by Pilot.command; computed as clamp(1.8 * (bank_target_rad - current_bank_rad) - 0.35 * body_p_radps, -1, 1), not a bank angle",
            "bank_target_formula_recomputed_from_orfl_state": command_formula,
            "orfl_mapping": "each planner packet's returned roll equals ORFL stick_roll at the following 1-4 physics sample rows",
            "returned_roll_to_orfl_comparisons": roll_checks,
            "returned_roll_mismatches": len(roll_mismatches),
            "selected_bank_target_match_failures": 0,
        },
        "inputs": {
            "trace_engine_log": {"path": str(trace_engine_log), "sha256": sha256(trace_engine_log)},
            "trace_report": {"path": str(trace_report_path), "sha256": sha256(trace_report_path)},
            "baseline_report": {"path": str(baseline_report_path), "sha256": sha256(baseline_report_path)},
            "trace_flight_csv": {"path": str(trace_flight_csv), "sha256": sha256(trace_flight_csv)},
            "orfl_streams": {
                f"{run}_{role}": {"path": item["path"], "sha256": item["sha256"],
                                   "rows": item["rows_written"]}
                for run, entries in (("baseline", baseline_orfl), ("traced", trace_orfl))
                for role, item in entries.items()
            },
            "exact_replay_reports": {
                label: {"path": str(path), "sha256": sha256(path),
                        "complete": replays[label]["complete"],
                        "solver_changed": replays[label]["solver_changed"],
                        "rows": replays[label]["rows"],
                        "source_sha256": replays[label]["source_sha256"]}
                for path, _, label in replay_specs
            },
        },
        "prediction_error": residuals,
        "limitations": [
            "The paired flight proves this trace-only candidate preserved state and command fingerprints for this fixture; it does not prove general controller equivalence.",
            "Forecast comparison is only at aligned 0.25-second points while the exact bank target remains active and unchanged. Later forecast origins with that same target are overlapping replans, not censor boundaries.",
            "Origins clipped by a bank target change or release have shorter observed matching horizons; missing full-horizon observations are reported, not imputed.",
            "Residuals are empirical samples from one deterministic 20-second encounter, not worst-case bounds or independent statistical observations.",
            "The 0.25-second predictor polyline and 240-Hz state samples do not bound continuous motion between points. No path_error_m is inferred; StaticTrajectory containment remains uncertified.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--trace-engine-log", type=Path, required=True)
    parser.add_argument("--trace-report", type=Path, required=True)
    parser.add_argument("--trace-flight-csv", type=Path, required=True)
    parser.add_argument("--baseline-report", type=Path, required=True)
    parser.add_argument("--trace-ai-replay", type=Path, required=True)
    parser.add_argument("--trace-player-replay", type=Path, required=True)
    parser.add_argument("--baseline-ai-replay", type=Path, required=True)
    parser.add_argument("--baseline-player-replay", type=Path, required=True)
    parser.add_argument("--production-pilot-sha256", required=True)
    parser.add_argument("--trace-pilot-sha256", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error("output path must be new")
    result = build(args.trace_engine_log, args.trace_report, args.trace_flight_csv,
                   args.baseline_report, args.trace_ai_replay, args.trace_player_replay,
                   args.baseline_ai_replay, args.baseline_player_replay,
                   args.production_pilot_sha256, args.trace_pilot_sha256)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(result, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps({
        "out": str(args.out),
        "paired_fingerprint_exact": result["fixture"]["paired_fingerprint_exact"],
        "forecast_origins": result["prediction_error"]["forecast_origins_emitted"],
        "positive_horizon_origins": result["prediction_error"]["origin_count_with_at_least_one_positive_horizon_sample"],
        "full_8s_target_compatible_origins": result["prediction_error"]["full_8s_target_compatible_origins"],
        "path_error_bound_established": result["prediction_error"]["path_error_bound_established"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
