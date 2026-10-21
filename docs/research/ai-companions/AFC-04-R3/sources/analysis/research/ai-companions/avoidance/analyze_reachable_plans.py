#!/usr/bin/env python3
"""Compare reachable-pilot prediction traces with flown paths during each held plan.

The analyzer stops a plan's comparison at the next retarget/release. Actual
positions are reconstructed from the encounter probe's 10 Hz CSV using straight
segments; this is a diagnostic of distance prediction over observed constant-plan
windows, not a physical safety bound or reconstruction of the 240 Hz path. The
probe does not log the complete own-aircraft state used at each prediction, so
own-position forecast error is intentionally not reconstructed here.
"""

from __future__ import annotations

import argparse
import bisect
import csv
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any

EVENT = re.compile(r"(AFC_REACHABLE_INITIAL|AFC_REACHABLE_PLAN|AFC_REACHABLE_MANEUVER)\s+(\{.*\})")
ROLE_BY_THREAT = {"player": "player", "companion-peer": "peer"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_event_groups(path: Path) -> list[dict[str, Any]]:
    """Group controller events by flight, using each new tick-zero hold as a boundary."""
    groups: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = EVENT.search(line)
        if not match:
            continue
        kind, raw = match.groups()
        event = json.loads(raw)
        if kind == "AFC_REACHABLE_MANEUVER":
            if event.get("action") == "hold" and int(event.get("tick", -1)) == 0:
                if current is not None:
                    groups.append(current)
                current = {"initial": None, "plans": [], "maneuvers": []}
            if current is None:
                current = {"initial": None, "plans": [], "maneuvers": []}
            current["maneuvers"].append(event)
        elif kind == "AFC_REACHABLE_INITIAL":
            if current is not None and current["initial"] is not None:
                groups.append(current)
                current = {"initial": None, "plans": [], "maneuvers": []}
            if current is None:
                current = {"initial": None, "plans": [], "maneuvers": []}
            current["initial"] = event
            current["plans"].append({"kind": "initial", "event": event})
        else:
            if current is None:
                current = {"initial": None, "plans": [], "maneuvers": []}
            current["plans"].append({"kind": "retarget", "event": event})
    if current is not None:
        groups.append(current)
    return groups


def read_tracks(path: Path) -> dict[str, dict[str, list[dict[str, float]]]]:
    tracks: dict[str, dict[str, list[dict[str, float]]]] = {}
    with path.open(newline="", encoding="utf-8") as source:
        for row in csv.DictReader(source):
            case = row["case"]
            role = row["role"]
            tracks.setdefault(case, {}).setdefault(role, []).append({
                "time_s": float(row["time_s"]),
                "north_m": float(row["north_m"]),
                "east_m": float(row["east_m"]),
                "altitude_m": float(row["altitude_m"]),
            })
    for roles in tracks.values():
        for rows in roles.values():
            rows.sort(key=lambda item: item["time_s"])
    return tracks


def position_at(rows: list[dict[str, float]], time_s: float) -> tuple[float, float, float] | None:
    times = [row["time_s"] for row in rows]
    if not rows or time_s < times[0] - 1e-9 or time_s > times[-1] + 1e-9:
        return None
    right = bisect.bisect_left(times, time_s)
    if right < len(rows) and abs(times[right] - time_s) <= 1e-9:
        row = rows[right]
        return row["north_m"], row["east_m"], row["altitude_m"]
    if right == 0 or right >= len(rows):
        return None
    first, second = rows[right - 1], rows[right]
    fraction = (time_s - first["time_s"]) / (second["time_s"] - first["time_s"])
    return tuple(first[key] + fraction * (second[key] - first[key])
                 for key in ("north_m", "east_m", "altitude_m"))


def pair_distance_at(a_rows: list[dict[str, float]], b_rows: list[dict[str, float]],
                     time_s: float) -> float | None:
    a, b = position_at(a_rows, time_s), position_at(b_rows, time_s)
    if a is None or b is None:
        return None
    return math.dist(a, b)


def synchronized_piecewise_minimum(
    a_rows: list[dict[str, float]], b_rows: list[dict[str, float]], start_s: float, end_s: float,
) -> dict[str, float] | None:
    """Exact relative-vector minimum on paired straight segments in the clipped interval."""
    if len(a_rows) != len(b_rows) or len(a_rows) < 2:
        raise ValueError("paired tracks must have equal sample counts >= 2")
    best = {"distance_m": math.inf, "time_s": math.nan}
    for a0, b0, a1, b1 in zip(a_rows, b_rows, a_rows[1:], b_rows[1:]):
        if (abs(a0["time_s"] - b0["time_s"]) > 1e-9
                or abs(a1["time_s"] - b1["time_s"]) > 1e-9):
            raise ValueError("paired tracks are not synchronized")
        t0 = max(start_s, a0["time_s"])
        t1 = min(end_s, a1["time_s"])
        if t1 <= t0:
            continue
        duration = a1["time_s"] - a0["time_s"]
        f0, f1 = (t0 - a0["time_s"]) / duration, (t1 - a0["time_s"]) / duration
        r0: list[float] = []
        r1: list[float] = []
        for key in ("north_m", "east_m", "altitude_m"):
            a_start = a0[key] + f0 * (a1[key] - a0[key])
            a_end = a0[key] + f1 * (a1[key] - a0[key])
            b_start = b0[key] + f0 * (b1[key] - b0[key])
            b_end = b0[key] + f1 * (b1[key] - b0[key])
            r0.append(a_start - b_start)
            r1.append(a_end - b_end)
        delta = [r1[i] - r0[i] for i in range(3)]
        denominator = sum(value * value for value in delta)
        u = 0.0 if denominator <= 0.0 else max(
            0.0, min(1.0, -sum(r0[i] * delta[i] for i in range(3)) / denominator))
        relative = [r0[i] + u * delta[i] for i in range(3)]
        distance = math.sqrt(sum(value * value for value in relative))
        if distance < best["distance_m"]:
            best = {"distance_m": distance, "time_s": t0 + u * (t1 - t0)}
    return best if math.isfinite(best["distance_m"]) else None


def _event_tick(event: dict[str, Any]) -> int:
    value = event.get("tick")
    if not isinstance(value, int) or value < 0:
        raise ValueError(f"invalid controller event tick: {value!r}")
    return value


def _trace_for_role(event: dict[str, Any], role: str) -> tuple[str, list[float]] | None:
    for trace in event.get("predicted_threat_distance_traces", []):
        threat_id = str(trace.get("id", ""))
        if ROLE_BY_THREAT.get(threat_id) == role:
            values = [float(value) for value in trace.get("distance_m", [])]
            if not values or any(not math.isfinite(value) for value in values):
                raise ValueError(f"invalid predicted distance trace for {threat_id}")
            return threat_id, values
    return None


def analyze(report_path: Path, trajectory_path: Path, engine_log_path: Path,
            candidate_path: Path, parent_path: Path, ticks_per_second: int = 240,
            prediction_step_s: float = 0.25) -> dict[str, Any]:
    report = json.loads(report_path.read_text(encoding="utf-8"))
    groups = read_event_groups(engine_log_path)
    if len(groups) < len(report["cases"]):
        raise ValueError(f"controller flight groups {len(groups)} < report case count {len(report['cases'])}")
    for extra in groups[len(report["cases"]):]:
        if extra.get("initial") != groups[len(report["cases"]) - 1].get("initial"):
            raise ValueError("extra controller group is not an identical deterministic repeat")
    tracks = read_tracks(trajectory_path)
    case_results: list[dict[str, Any]] = []
    for report_case, group in zip(report["cases"], groups):
        case_id = str(report_case["case_id"])
        role_tracks = tracks.get(case_id, {})
        if "ai" not in role_tracks:
            raise ValueError(f"missing AI trajectory for {case_id}")
        plans = group.get("plans", [])
        maneuvers = group.get("maneuvers", [])
        plan_results: list[dict[str, Any]] = []
        for plan_index, plan in enumerate(plans):
            event = plan["event"]
            start_tick = _event_tick(event)
            next_plan_tick = _event_tick(plans[plan_index + 1]["event"]) if plan_index + 1 < len(plans) else math.inf
            release_ticks = [
                _event_tick(item) for item in maneuvers
                if item.get("action") == "release" and _event_tick(item) > start_tick
            ]
            end_tick = min(next_plan_tick, min(release_ticks, default=math.inf),
                           start_tick + int(round(8.0 * ticks_per_second)))
            start_s, end_s = start_tick / ticks_per_second, end_tick / ticks_per_second
            threat_results: list[dict[str, Any]] = []
            for role, other_rows in sorted(role_tracks.items()):
                if role == "ai":
                    continue
                selected = _trace_for_role(event, role)
                if selected is None:
                    continue
                threat_id, predicted = selected
                ai_rows = role_tracks["ai"]
                overlap_start = max(start_s, ai_rows[0]["time_s"], other_rows[0]["time_s"])
                overlap_end = min(end_s, ai_rows[-1]["time_s"], other_rows[-1]["time_s"])
                if overlap_end < overlap_start:
                    continue
                sample_residuals: list[dict[str, float]] = []
                for index, predicted_distance in enumerate(predicted):
                    predicted_time = start_s + index * prediction_step_s
                    if predicted_time < overlap_start - 1e-9 or predicted_time > overlap_end + 1e-9:
                        continue
                    actual_distance = pair_distance_at(ai_rows, other_rows, predicted_time)
                    if actual_distance is not None:
                        sample_residuals.append({
                            "time_s": predicted_time,
                            "predicted_m": predicted_distance,
                            "actual_m": actual_distance,
                            "predicted_minus_actual_m": predicted_distance - actual_distance,
                        })
                actual_minimum = synchronized_piecewise_minimum(
                    ai_rows, other_rows, overlap_start, overlap_end)
                if not sample_residuals or actual_minimum is None:
                    continue
                forecast_minimum = min(row["predicted_m"] for row in sample_residuals)
                residual_values = [row["predicted_minus_actual_m"] for row in sample_residuals]
                threat_results.append({
                    "threat_id": threat_id,
                    "role": role,
                    "overlap_start_s": overlap_start,
                    "overlap_end_s": overlap_end,
                    "overlap_duration_s": overlap_end - overlap_start,
                    "matched_prediction_sample_count": len(sample_residuals),
                    "prediction_minus_actual_at_samples_m": {
                        "minimum": min(residual_values),
                        "maximum": max(residual_values),
                        "maximum_overestimate": max(0.0, max(residual_values)),
                        "maximum_underestimate_magnitude": max(0.0, -min(residual_values)),
                    },
                    "prediction_sample_minimum_m": forecast_minimum,
                    "actual_piecewise_linear_minimum_m": actual_minimum["distance_m"],
                    "actual_piecewise_linear_minimum_time_s": actual_minimum["time_s"],
                    "sampled_forecast_minimum_minus_actual_minimum_m":
                        forecast_minimum - actual_minimum["distance_m"],
                    "sample_residuals": sample_residuals,
                })
            plan_results.append({
                "selection_kind": plan["kind"],
                "start_tick": start_tick,
                "end_tick_exclusive": None if not math.isfinite(end_tick) else int(end_tick),
                "start_s": start_s,
                "planned_comparison_end_s": None if not math.isfinite(end_s) else end_s,
                "selected_bank_deg": event.get("selected_bank_deg"),
                "held_bank_deg": event.get("held_bank_deg"),
                "wind_ned_m_s": event.get("prediction_wind_ned_m_s"),
                "air_speed_m_s": event.get("prediction_air_speed_m_s"),
                "maneuver_transitions": [item for item in maneuvers
                    if start_tick <= _event_tick(item) <= end_tick],
                "threats": threat_results,
            })
        case_results.append({
            "case_id": case_id,
            "separation_gate_passed": report_case.get("separation_gate_passed"),
            "minimum_player_separation_m": report_case.get("min_separation_to_player_m"),
            "maneuvers": group.get("maneuvers", []),
            "plans": plan_results,
        })
    residuals = [
        row["predicted_minus_actual_m"]
        for case in case_results for plan in case["plans"] for threat in plan["threats"]
        for row in threat["sample_residuals"]
    ]
    return {
        "format": "afc-reachable-plan-vs-flown-v1",
        "tick_rate_hz": ticks_per_second,
        "prediction_sample_step_s": prediction_step_s,
        "actual_reconstruction": "synchronized straight-line interpolation between paired 10 Hz CSV samples; minimum computed continuously on each clipped relative segment",
        "scope": "Each selected forecast is compared only until the next logged retarget/release and for at most its 8 s horizon.",
        "limitation": "Observed residuals include flight-dynamics response, wind/model error, and 10 Hz trajectory reconstruction. They are not a worst-case prediction bound, continuous 240 Hz path, or terrain/static-obstacle clearance result.",
        "overall_sample_residuals_m": {
            "count": len(residuals),
            "minimum": min(residuals) if residuals else None,
            "maximum": max(residuals) if residuals else None,
            "maximum_overestimate": max(0.0, max(residuals)) if residuals else None,
            "maximum_underestimate_magnitude": max(0.0, -min(residuals)) if residuals else None,
        },
        "source_files": {
            "survey_report": {"path": str(report_path.resolve()), "sha256": sha256(report_path)},
            "trajectory_csv": {"path": str(trajectory_path.resolve()), "sha256": sha256(trajectory_path)},
            "engine_log": {"path": str(engine_log_path.resolve()), "sha256": sha256(engine_log_path)},
            "candidate": {"path": str(candidate_path.resolve()), "sha256": sha256(candidate_path)},
            "parent_pilot": {"path": str(parent_path.resolve()), "sha256": sha256(parent_path)},
        },
        "cases": case_results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--trajectory", type=Path, required=True)
    parser.add_argument("--engine-log", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--parent-pilot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = analyze(args.report, args.trajectory, args.engine_log, args.candidate, args.parent_pilot)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(args.out.resolve()),
        "cases": len(result["cases"]),
        "plans": sum(len(item["plans"]) for item in result["cases"]),
        "sample_residuals": result["overall_sample_residuals_m"]["count"],
        "maximum_overestimate_m": result["overall_sample_residuals_m"]["maximum_overestimate"],
        "maximum_underestimate_magnitude": result["overall_sample_residuals_m"]["maximum_underestimate_magnitude"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
