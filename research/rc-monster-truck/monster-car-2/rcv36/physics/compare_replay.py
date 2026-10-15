#!/usr/bin/env python3
"""Compare a retained RCV36 same-tape Nitro run against its frozen baseline.

The comparison is complete only when both records are complete exact replays,
the control-tape hashes and exported files match their receipts, and both CSVs
contain the same full state layout at each tick. Solver changes are reported
separately from completeness and from trace equivalence.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from typing import Any

STATE_NAMES = [
    "north_m", "east_m", "down_m", "u_m_per_s", "v_m_per_s", "w_m_per_s",
    "qw", "qx", "qy", "qz", "p_rad_per_s", "q_rad_per_s", "r_rad_per_s",
    "travel_fl_m", "travel_fr_m", "travel_rl_m", "travel_rr_m",
    "travel_rate_fl_m_per_s", "travel_rate_fr_m_per_s", "travel_rate_rl_m_per_s", "travel_rate_rr_m_per_s",
    "wheel_spin_fl_rad_per_s", "wheel_spin_fr_rad_per_s", "wheel_spin_rl_rad_per_s", "wheel_spin_rr_rad_per_s",
    "wheel_angle_fl_rad", "wheel_angle_fr_rad", "wheel_angle_rl_rad", "wheel_angle_rr_rad",
    "steering_right_rad", "steering_rate_right_rad_per_s", "engine_speed_rad_s", "fuel_mass_kg",
]
CONTROL_COLUMNS = ("throttle", "steering", "brake", "reverse")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object in {path}")
    return value


def load_candidate_report(path: Path) -> dict[str, Any]:
    source = path.read_text(encoding="utf-8")
    try:
        value = json.loads(source)
        if isinstance(value, dict):
            return value
    except json.JSONDecodeError:
        pass
    marker = "NITRO_SESSION_EVIDENCE="
    for line in source.splitlines():
        if line.startswith(marker):
            value = json.loads(line[len(marker):])
            if isinstance(value, dict):
                return value
    raise ValueError(f"no session evidence JSON found in {path}")


def read_recording(path: Path) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        first = stream.readline()
        if not first.startswith("# openrc-ground-vehicle-recording v"):
            raise ValueError(f"unexpected recording header in {path}")
        rows = list(csv.DictReader(stream))
    return rows


def state_rows(rows: list[dict[str, Any]], label: str) -> tuple[list[int], list[list[float]], list[dict[str, Any]]]:
    ticks: list[int] = []
    states: list[list[float]] = []
    controls: list[dict[str, Any]] = []
    for row_number, row in enumerate(rows):
        tick = int(row["tick"])
        state = json.loads(row["state_json"])
        if not isinstance(state, list) or len(state) != len(STATE_NAMES):
            raise ValueError(f"{label} row {row_number} has state width {len(state) if isinstance(state, list) else 'invalid'}")
        values = [float(value) for value in state]
        if not all(math.isfinite(value) for value in values):
            raise ValueError(f"{label} row {row_number} contains a non-finite state value")
        ticks.append(tick)
        states.append(values)
        controls.append({
            "throttle": float(row["throttle"]),
            "steering": float(row["steering"]),
            "brake": float(row["brake"]),
            "reverse": row["reverse"].lower() == "true",
        })
    return ticks, states, controls


def same_solver(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return json.dumps(left, sort_keys=True, separators=(",", ":")) == json.dumps(
        right, sort_keys=True, separators=(",", ":")
    )


def compare(args: argparse.Namespace) -> dict[str, Any]:
    baseline_dir = args.baseline_dir.resolve()
    candidate_dir = args.candidate_dir.resolve()
    baseline = load_json(baseline_dir / "baseline.json")
    candidate = load_candidate_report(args.candidate_report.resolve())
    reasons: list[str] = []

    baseline_replay = baseline.get("replay", {})
    baseline_solver = baseline.get("identities", {}).get("solver_identity", {})
    candidate_solver = candidate.get("solver_identity", {})
    solver_changed = not same_solver(baseline_solver, candidate_solver)
    baseline_model = baseline.get("identities", {}).get("vehicle_model", {})
    candidate_model = candidate.get("model_identity", {})
    baseline_course = baseline.get("identities", {}).get("course", {})
    candidate_course = candidate.get("course_identity", {})

    baseline_csv = baseline_dir / str(baseline.get("recording", {}).get("csv_file", ""))
    baseline_meta = baseline_dir / str(baseline.get("recording", {}).get("metadata_file", ""))
    candidate_csv = candidate_dir / "session-candidate.csv"
    candidate_meta = candidate_dir / "session-candidate-recording.json"
    for path in (baseline_csv, baseline_meta, candidate_csv, candidate_meta):
        if not path.is_file():
            reasons.append(f"missing artifact: {path.name}")

    baseline_csv_hash_ok = baseline_csv.is_file() and sha256_file(baseline_csv) == baseline["recording"].get("csv_sha256")
    baseline_meta_hash_ok = baseline_meta.is_file() and sha256_file(baseline_meta) == baseline["recording"].get("metadata_sha256")
    candidate_export = candidate.get("recording_export", {})
    candidate_csv_hash_ok = candidate_csv.is_file() and sha256_file(candidate_csv) == candidate_export.get("csv_sha256")
    candidate_meta_hash_ok = candidate_meta.is_file() and sha256_file(candidate_meta) == candidate_export.get("metadata_sha256")
    if not baseline_csv_hash_ok or not baseline_meta_hash_ok:
        reasons.append("baseline CSV or metadata hash does not match its frozen receipt")
    if not candidate_csv_hash_ok or not candidate_meta_hash_ok:
        reasons.append("candidate CSV or metadata hash does not match the session report")

    try:
        baseline_metadata = load_json(baseline_meta)
        candidate_metadata = load_json(candidate_meta)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        baseline_metadata = {}
        candidate_metadata = {}
        reasons.append(f"metadata could not be read: {error}")

    if baseline_csv.is_file() and candidate_csv.is_file():
        baseline_ticks, baseline_states, baseline_controls = state_rows(read_recording(baseline_csv), "baseline")
        candidate_ticks, candidate_states, candidate_controls = state_rows(read_recording(candidate_csv), "candidate")
    else:
        baseline_ticks, baseline_states, baseline_controls = [], [], []
        candidate_ticks, candidate_states, candidate_controls = [], [], []

    trace_shape_matches = baseline_ticks == candidate_ticks and len(baseline_ticks) > 0
    controls_match = trace_shape_matches and baseline_controls == candidate_controls
    if not trace_shape_matches:
        reasons.append("baseline and candidate sample ticks differ")
    if not controls_match:
        reasons.append("recorded control columns differ between baseline and candidate")

    tape_matches = baseline_replay.get("control_tape_sha256") == candidate.get("control_tape_sha256")
    if not tape_matches:
        reasons.append("control tape hash differs from the frozen baseline")
    if not bool(baseline.get("complete", False)) or not bool(candidate.get("complete", False)):
        reasons.append("baseline or candidate session report is incomplete")
    if not bool(candidate.get("control_replay_exact", False)) \
            or candidate.get("final_state_sha256") != candidate.get("replay_state_sha256"):
        reasons.append("candidate final state does not match its exact replay state")
    if not bool(candidate.get("recording_run_valid", False)):
        reasons.append("candidate recording is marked run_valid=false")
    if baseline_model.get("id") != candidate_model.get("id") or baseline_model.get("sha256") != candidate_model.get("sha256"):
        reasons.append("vehicle model identity differs from the frozen baseline")
    if baseline_course.get("id") != candidate_course.get("id") or baseline_course.get("sha256") != candidate_course.get("sha256"):
        reasons.append("course identity differs from the frozen baseline")
    if len(baseline_ticks) != int(baseline_replay.get("recording_sample_count", -1)):
        reasons.append("baseline CSV sample count differs from the frozen receipt")
    if len(candidate_ticks) != int(candidate.get("recording_sample_count", -1)):
        reasons.append("candidate CSV sample count differs from the session report")
    if baseline_metadata.get("vehicle_id") != "monster-car-2" or candidate_metadata.get("vehicle_id") != "monster-car-2":
        reasons.append("recording metadata has an unexpected vehicle id")
    if baseline_metadata.get("state_layout") != STATE_NAMES or candidate_metadata.get("state_layout") != STATE_NAMES:
        reasons.append("recording metadata does not pin the expected 33-value state layout")
    if baseline_metadata.get("sample_count") != baseline_replay.get("recording_sample_count") \
            or candidate_metadata.get("sample_count") != candidate.get("recording_sample_count"):
        reasons.append("recording metadata sample count differs from its report")
    if bool(candidate_metadata.get("run_valid", False)) != bool(candidate.get("recording_run_valid", False)):
        reasons.append("candidate recording validity differs from the session report")
    if candidate_metadata.get("solver_identity") != candidate_solver:
        reasons.append("candidate recording metadata solver identity differs from the session report")
    if candidate_metadata.get("model_identity", {}).get("sha256") != candidate_model.get("sha256"):
        reasons.append("candidate recording metadata vehicle identity differs from the session report")

    first_divergent_tick: int | None = None
    max_abs_by_state = [0.0] * len(STATE_NAMES)
    sum_squares_by_state = [0.0] * len(STATE_NAMES)
    compared_values = 0
    state_trace_identical = trace_shape_matches
    if trace_shape_matches:
        for row_index, (baseline_state, candidate_state) in enumerate(zip(baseline_states, candidate_states)):
            row_differs = False
            for state_index, (baseline_value, candidate_value) in enumerate(zip(baseline_state, candidate_state)):
                delta = candidate_value - baseline_value
                absolute_delta = abs(delta)
                max_abs_by_state[state_index] = max(max_abs_by_state[state_index], absolute_delta)
                sum_squares_by_state[state_index] += delta * delta
                compared_values += 1
                row_differs = row_differs or delta != 0.0
            if row_differs:
                state_trace_identical = False
                if first_divergent_tick is None:
                    first_divergent_tick = baseline_ticks[row_index]

    rms_by_state = [math.sqrt(total / len(baseline_ticks)) for total in sum_squares_by_state] if baseline_ticks else []
    complete = not reasons and controls_match and tape_matches and trace_shape_matches \
        and baseline_csv_hash_ok and baseline_meta_hash_ok and candidate_csv_hash_ok and candidate_meta_hash_ok
    result = {
        "format": "openrc-monster-car-2-rcv36-physics-replay-comparison-v1",
        "complete": complete,
        "solver_changed": solver_changed,
        "same_control_tape": tape_matches and controls_match,
        "solver_identity": {"baseline": baseline_solver, "candidate": candidate_solver},
        "vehicle_model_identity_matches": baseline_model.get("sha256") == candidate_model.get("sha256"),
        "course_identity_matches": baseline_course.get("sha256") == candidate_course.get("sha256"),
        "exact_candidate_replay": bool(candidate.get("control_replay_exact", False))
            and candidate.get("final_state_sha256") == candidate.get("replay_state_sha256"),
        "state_trace": {
            "sample_count": len(baseline_ticks),
            "state_width": len(STATE_NAMES),
            "identical": state_trace_identical,
            "first_divergent_tick": first_divergent_tick,
            "max_abs_delta_by_state": dict(zip(STATE_NAMES, max_abs_by_state)),
            "rms_delta_by_state": dict(zip(STATE_NAMES, rms_by_state)),
            "compared_scalar_values": compared_values,
        },
        "artifacts": {
            "baseline_csv_sha256_verified": baseline_csv_hash_ok,
            "baseline_metadata_sha256_verified": baseline_meta_hash_ok,
            "candidate_csv_sha256_verified": candidate_csv_hash_ok,
            "candidate_metadata_sha256_verified": candidate_meta_hash_ok,
        },
        "reasons_incomplete": reasons,
    }

    if trace_shape_matches:
        delta_path = candidate_dir / "state-delta.csv"
        with delta_path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(["tick", *[f"delta_{name}" for name in STATE_NAMES]])
            for tick, baseline_state, candidate_state in zip(baseline_ticks, baseline_states, candidate_states):
                writer.writerow([tick, *[candidate_value - baseline_value for baseline_value, candidate_value in zip(baseline_state, candidate_state)]])
        result["artifacts"]["state_delta_csv"] = delta_path.name
        result["artifacts"]["state_delta_csv_sha256"] = sha256_file(delta_path)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-dir", type=Path, required=True, help="directory containing baseline.json and its CSV/metadata")
    parser.add_argument("--candidate-dir", type=Path, required=True, help="directory containing session-candidate.csv and metadata")
    parser.add_argument("--candidate-report", type=Path, required=True, help="session JSON report or verifier log")
    parser.add_argument("--output", type=Path, required=True, help="comparison JSON destination")
    args = parser.parse_args()
    result = compare(args)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
