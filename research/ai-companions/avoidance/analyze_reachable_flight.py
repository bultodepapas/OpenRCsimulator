#!/usr/bin/env python3
"""Compare tick-zero reachable-pilot clearance prediction with flown trajectories.

The flight CSV is sampled at 10 Hz. This computes both the sampled minimum and
the exact minimum of the piecewise-linear reconstruction between adjacent CSV
samples; it does not claim to reconstruct the 240 Hz physics path between them.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any

EVENT = re.compile(r"AFC_REACHABLE_INITIAL\s+(\{.*\})")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_initial_predictions(path: Path) -> list[dict[str, Any]]:
    predictions: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = EVENT.search(line)
        if match:
            predictions.append(json.loads(match.group(1)))
    return predictions


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


def point_distance(a: dict[str, float], b: dict[str, float]) -> float:
    return math.dist(
        (a["north_m"], a["east_m"], a["altitude_m"]),
        (b["north_m"], b["east_m"], b["altitude_m"]),
    )


def synchronized_minimum(
    a_rows: list[dict[str, float]],
    b_rows: list[dict[str, float]],
    horizon_s: float,
) -> dict[str, float]:
    """Minimum synchronized pair distance over piecewise-linear tracks."""
    if len(a_rows) != len(b_rows) or len(a_rows) < 2:
        raise ValueError("paired tracks must have equal sample counts >= 2")
    best = {"distance_m": math.inf, "time_s": math.nan}
    previous_time = -math.inf
    for a0, b0, a1, b1 in zip(a_rows, b_rows, a_rows[1:], b_rows[1:]):
        if abs(a0["time_s"] - b0["time_s"]) > 1e-9 or abs(a1["time_s"] - b1["time_s"]) > 1e-9:
            raise ValueError("paired tracks are not synchronized")
        t0 = a0["time_s"]
        t1 = min(a1["time_s"], horizon_s)
        if t0 >= horizon_s or t1 <= t0:
            break
        duration = a1["time_s"] - t0
        frac1 = (t1 - t0) / duration
        r0 = [a0[k] - b0[k] for k in ("north_m", "east_m", "altitude_m")]
        r1_full = [a1[k] - b1[k] for k in ("north_m", "east_m", "altitude_m")]
        delta = [(r1_full[i] - r0[i]) * frac1 for i in range(3)]
        delta_sq = sum(value * value for value in delta)
        u = 0.0 if delta_sq == 0.0 else max(0.0, min(1.0, -sum(r0[i] * delta[i] for i in range(3)) / delta_sq))
        r_min = [r0[i] + u * delta[i] for i in range(3)]
        distance = math.sqrt(sum(value * value for value in r_min))
        time_s = t0 + u * (t1 - t0)
        if distance < best["distance_m"]:
            best = {"distance_m": distance, "time_s": time_s}
        previous_time = t0
    if not math.isfinite(best["distance_m"]):
        raise ValueError(f"no paired samples before {horizon_s}s (last={previous_time})")
    return best


def sampled_minimum(
    a_rows: list[dict[str, float]],
    b_rows: list[dict[str, float]],
    horizon_s: float,
) -> dict[str, float]:
    best = {"distance_m": math.inf, "time_s": math.nan}
    for a, b in zip(a_rows, b_rows):
        if a["time_s"] > horizon_s:
            break
        distance = point_distance(a, b)
        if distance < best["distance_m"]:
            best = {"distance_m": distance, "time_s": a["time_s"]}
    return best


def analyze(report_path: Path, trajectory_path: Path, engine_log_path: Path,
            horizon_s: float) -> dict[str, Any]:
    report = json.loads(report_path.read_text(encoding="utf-8"))
    predictions = read_initial_predictions(engine_log_path)
    report_cases = report["cases"]
    if len(predictions) < len(report_cases):
        raise ValueError(f"initial event count {len(predictions)} < report case count {len(report_cases)}")
    # The encounter probe repeats its final two-threat fixture to certify
    # deterministic command/state identity. The repeat has no separate CSV
    # track, so require its initial diagnostic to match the original exactly.
    extras = predictions[len(report_cases):]
    if any(extra != predictions[-1] for extra in extras):
        raise ValueError("extra initial events are not identical deterministic fixture repeats")
    predictions = predictions[:len(report_cases)]
    tracks = read_tracks(trajectory_path)
    cases: list[dict[str, Any]] = []
    for report_case, prediction in zip(report_cases, predictions):
        case_id = str(report_case["case_id"])
        role_tracks = tracks.get(case_id)
        if role_tracks is None:
            raise ValueError(f"missing CSV case {case_id}")
        if "ai" not in role_tracks:
            raise ValueError(f"missing AI track for {case_id}: {sorted(role_tracks)}")
        ai_rows = role_tracks["ai"]
        other_minima: dict[str, Any] = {}
        for other_role in sorted(role for role in role_tracks if role != "ai"):
            other_rows = role_tracks[other_role]
            pred_key = "selected_peer_min_m" if other_role == "peer" else "selected_player_min_m"
            predicted = prediction.get(pred_key)
            sampled = sampled_minimum(ai_rows, other_rows, horizon_s)
            linear = synchronized_minimum(ai_rows, other_rows, horizon_s)
            full_sampled = sampled_minimum(ai_rows, other_rows, math.inf)
            full_linear = synchronized_minimum(ai_rows, other_rows, math.inf)
            other_minima[other_role] = {
                "predicted_8s_minimum_m": predicted,
                "actual_8s_sampled_minimum_m": sampled["distance_m"],
                "actual_8s_sampled_time_s": sampled["time_s"],
                "actual_8s_piecewise_linear_minimum_m": linear["distance_m"],
                "actual_8s_piecewise_linear_time_s": linear["time_s"],
                "prediction_minus_actual_piecewise_linear_m": (
                    float(predicted) - linear["distance_m"] if predicted is not None else None
                ),
                "actual_full_sampled_minimum_m": full_sampled["distance_m"],
                "actual_full_piecewise_linear_minimum_m": full_linear["distance_m"],
                "report_tick_minimum_m": report_case["min_separation_to_peer_m"]
                if other_role == "peer" else report_case["min_separation_to_player_m"],
                "sample_interval_s": round(ai_rows[1]["time_s"] - ai_rows[0]["time_s"], 9),
            }
        cases.append({
            "case_id": case_id,
            "other_minima": other_minima,
            "predictor_tick": prediction.get("tick"),
            "selected_bank_deg": prediction.get("selected_bank_deg"),
            "initial_threat_count": prediction.get("threat_count"),
        })
    return {
        "format": "afc-reachable-predictor-vs-flown-v1",
        "horizon_s": horizon_s,
        "continuity_method": "exact minimum on each synchronized straight-line segment between paired 10 Hz CSV samples",
        "limitation": "The 10 Hz piecewise-linear reconstruction is not the exact 240 Hz simulation path; the candidate's 0.25 s prediction samples are also not a continuous bound.",
        "source_files": {
            "survey_report": {"path": str(report_path.resolve()), "sha256": sha256(report_path)},
            "trajectory_csv": {"path": str(trajectory_path.resolve()), "sha256": sha256(trajectory_path)},
            "engine_log": {"path": str(engine_log_path.resolve()), "sha256": sha256(engine_log_path)},
        },
        "cases": cases,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--trajectory", type=Path, required=True)
    parser.add_argument("--engine-log", type=Path, required=True)
    parser.add_argument("--horizon-s", type=float, default=8.0)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = analyze(args.report, args.trajectory, args.engine_log, args.horizon_s)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(args.out.resolve()),
        "cases": len(result["cases"]),
        "worst_prediction_minus_actual_m": min(
            (measurement["prediction_minus_actual_piecewise_linear_m"]
             for item in result["cases"] for measurement in item["other_minima"].values()
             if measurement["prediction_minus_actual_piecewise_linear_m"] is not None),
            default=None,
        ),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
