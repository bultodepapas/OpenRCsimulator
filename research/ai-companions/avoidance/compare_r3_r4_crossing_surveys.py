#!/usr/bin/env python3
"""Compare retained R3 candidate and R4 production 20-second calm crossings."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from typing import Any


EXPECTED_CASES = {
    "seed-20261020-crossing-right",
    "seed-20261021-crossing-left",
}
EXPECTED_R3_PILOT_SHA256 = "1c512e4bdc0c606cc575397dfe8e1d6fe3e8bf6b9bc0894bd20ce11366d47eb8"
EXPECTED_R4_PILOT_SHA256 = "363942b4b7d67f85333233f0c6000890ca984e5b76a8ccabe7973f70218259ed"
EXPECTED_PROBE_SHA256 = "d00004590c5793ba743f56b3d129a248d35fa085186e576d33f0ac9a2e832cc4"
EXPECTED_COLLISION_IDENTITY = "fb2be395cc783b3910f5eb2c5fcdef4936c36ea90bd8d25466d818f2b89743ae"
EXPECTED_LAKE_IDENTITY = "bcc3774dc2ef339bac49aaec42b6a47b6b6d1104470d9fff35db242f6ab61efa"
EXPECTED_SAMPLES_PER_GROUP = 201
NON_NUMERIC_COLUMNS = {
    "case", "seed", "circuit_direction", "tick", "role", "avoidance_active",
    "recovering_clearance",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def read_trajectory(path: Path) -> tuple[list[str], dict[tuple[str, str, int], dict[str, str]]]:
    rows: dict[tuple[str, str, int], dict[str, str]] = {}
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        header = list(reader.fieldnames or [])
        for row in reader:
            key = (row["case"], row["role"], int(row["tick"]))
            if key in rows:
                raise ValueError(f"duplicate trajectory row in {path}: {key}")
            rows[key] = row
    return header, rows


def delta_summary(values: list[float]) -> dict[str, Any]:
    absolute = sorted(abs(value) for value in values)
    p95_index = min(len(absolute) - 1, math.ceil(0.95 * len(absolute)) - 1)
    return {
        "compared_values": len(values),
        "different_values": sum(value != 0.0 for value in values),
        "mean_delta_r4_minus_r3": sum(values) / len(values),
        "rms_delta": math.sqrt(sum(value * value for value in values) / len(values)),
        "max_abs_delta": max(absolute),
        "p95_abs_delta": absolute[p95_index],
        "minimum_delta": min(values),
        "maximum_delta": max(values),
    }


def compare(r3_report_path: Path, r3_csv_path: Path, r4_report_path: Path, r4_csv_path: Path) -> dict[str, Any]:
    r3 = read_json(r3_report_path)
    r4 = read_json(r4_report_path)
    failures: list[str] = []

    for label, report, expected_pilot in (
        ("R3 candidate", r3, EXPECTED_R3_PILOT_SHA256),
        ("R4 production", r4, EXPECTED_R4_PILOT_SHA256),
    ):
        if report.get("recording_mode") != "crossings":
            failures.append(f"{label} recording mode is not crossings")
        if report.get("weather") != "calm":
            failures.append(f"{label} survey is not calm weather")
        if report.get("seconds") != 20 or report.get("requested_ticks") != 4800:
            failures.append(f"{label} survey is not the same bounded 20-second run")
        if not report.get("valid_complete_runs"):
            failures.append(f"{label} survey includes invalid or incomplete runs")
        if not report.get("deterministic_repeat", {}).get("exact_state_command_match"):
            failures.append(f"{label} deterministic repeat is not exact")
        if report.get("pilot_source_sha256") != expected_pilot:
            failures.append(f"{label} pilot source hash differs from its frozen identity")
        if report.get("probe_source_sha256") != EXPECTED_PROBE_SHA256:
            failures.append(f"{label} probe source differs from the retained common probe")
        if report.get("separation_gate_m") != 30.0:
            failures.append(f"{label} separation gate differs from the retained 30 m threshold")

    for identity in ("field_id", "collision_identity", "lake_identity", "probe_source_sha256"):
        if r3.get(identity) != r4.get(identity):
            failures.append(f"shared fixture identity differs: {identity}")
    if r3.get("collision_identity") != EXPECTED_COLLISION_IDENTITY:
        failures.append("shared collision-world identity differs from the frozen fixture")
    if r3.get("lake_identity") != EXPECTED_LAKE_IDENTITY:
        failures.append("shared lake identity differs from the frozen fixture")

    r3_cases = {str(case.get("case_id", "")): case for case in r3.get("cases", []) if isinstance(case, dict)}
    r4_cases = {str(case.get("case_id", "")): case for case in r4.get("cases", []) if isinstance(case, dict)}
    if set(r3_cases) != EXPECTED_CASES:
        failures.append(f"R3 case set differs from expected pair: {sorted(r3_cases)}")
    if set(r4_cases) != EXPECTED_CASES:
        failures.append(f"R4 case set differs from expected pair: {sorted(r4_cases)}")

    case_comparisons: dict[str, dict[str, Any]] = {}
    for case_id in sorted(EXPECTED_CASES & set(r3_cases) & set(r4_cases)):
        old = r3_cases[case_id]
        new = r4_cases[case_id]
        if not old.get("valid_run") or not old.get("complete") or not old.get("separation_gate_passed"):
            failures.append(f"R3 candidate {case_id} did not complete and pass separation")
        if not new.get("valid_run") or not new.get("complete") or not new.get("separation_gate_passed"):
            failures.append(f"R4 production {case_id} did not complete and pass separation")
        if old.get("ticks") != 4800 or new.get("ticks") != 4800:
            failures.append(f"case tick count differs from 4,800 for {case_id}")
        old_exogenous = old.get("exogenous_player", {})
        new_exogenous = new.get("exogenous_player", {})
        if not isinstance(old_exogenous, dict) or not old_exogenous.get("valid_run") or not old_exogenous.get("complete"):
            failures.append(f"R3 candidate exogenous player did not complete for {case_id}")
        if not isinstance(new_exogenous, dict) or not new_exogenous.get("valid_run") or not new_exogenous.get("complete"):
            failures.append(f"R4 production exogenous player did not complete for {case_id}")
        if not isinstance(old_exogenous, dict) or not old_exogenous.get("initial_spawn_matches_coupled_spec"):
            failures.append(f"R3 candidate exogenous spawn differs from coupled player for {case_id}")
        if not isinstance(new_exogenous, dict) or not new_exogenous.get("initial_spawn_matches_coupled_spec"):
            failures.append(f"R4 production exogenous spawn differs from coupled player for {case_id}")
        spawn_equal = old.get("player_initial_spawn_spec") == new.get("player_initial_spawn_spec")
        if not spawn_equal:
            failures.append(f"player spawn spec differs between sources for {case_id}")
        old_min = old.get("min_separation_to_player_m")
        new_min = new.get("min_separation_to_player_m")
        if type(old_min) not in (int, float) or float(old_min) < 30.0:
            failures.append(f"R3 candidate {case_id} is below the unchanged 30 m separation gate")
        if type(new_min) not in (int, float) or float(new_min) < 30.0:
            failures.append(f"R4 production {case_id} is below the unchanged 30 m separation gate")
        old_height = old.get("initial_commanded_target_height_m")
        new_height = new.get("initial_commanded_target_height_m")
        old_nominal_flag = old.get("initial_target_height_matches_nominal")
        new_nominal_flag = new.get("initial_target_height_matches_nominal")
        if type(old_nominal_flag) is not bool or type(new_nominal_flag) is not bool:
            failures.append(f"nominal-target diagnostic flag is missing for {case_id}")
        expected_height = new.get("expected_initial_target_height_m")
        target_height_error = new.get("initial_target_height_error_m")
        if type(new_height) not in (int, float) or type(expected_height) not in (int, float) \
                or type(target_height_error) not in (int, float):
            failures.append(f"R4 nominal-target diagnostic values are missing for {case_id}")
        case_comparisons[case_id] = {
            "r3_valid_complete": bool(old.get("valid_run") and old.get("complete")),
            "r4_valid_complete": bool(new.get("valid_run") and new.get("complete")),
            "r3_separation_gate_passed": old.get("separation_gate_passed"),
            "r4_separation_gate_passed": new.get("separation_gate_passed"),
            "r3_min_separation_to_player_m": old_min,
            "r4_min_separation_to_player_m": new_min,
            "delta_min_separation_r4_minus_r3_m": (
                float(new_min) - float(old_min) if old_min is not None and new_min is not None else None
            ),
            "player_initial_spawn_spec_equal": spawn_equal,
            "r3_initial_commanded_target_height_m": old_height,
            "r4_initial_commanded_target_height_m": new_height,
            "delta_initial_target_height_r4_minus_r3_m": (
                float(new_height) - float(old_height)
                if old_height is not None and new_height is not None else None
            ),
            "r3_initial_target_height_matches_nominal": old_nominal_flag,
            "r4_initial_target_height_matches_nominal": new_nominal_flag,
            "r4_expected_initial_target_height_m": expected_height,
            "r4_initial_target_height_error_m": target_height_error,
        }

    r3_header, r3_rows = read_trajectory(r3_csv_path)
    r4_header, r4_rows = read_trajectory(r4_csv_path)
    header_equal = r3_header == r4_header
    common_keys = set(r3_rows) & set(r4_rows)
    missing_r4 = sorted(set(r3_rows) - set(r4_rows))
    missing_r3 = sorted(set(r4_rows) - set(r3_rows))
    if not header_equal:
        failures.append("trajectory CSV headers differ")
    if missing_r4 or missing_r3:
        failures.append("trajectory CSV row keys are not fully aligned")

    expected_groups = {(case_id, role) for case_id in EXPECTED_CASES for role in ("ai", "player")}
    actual_groups = {(case_id, role) for case_id, role, _tick in common_keys}
    if actual_groups != expected_groups:
        failures.append(f"trajectory groups differ from expected AI/player pair: {sorted(actual_groups)}")

    columns = [column for column in r3_header if column not in NON_NUMERIC_COLUMNS]
    by_group: dict[str, dict[str, Any]] = {}
    aggregate: dict[str, list[float]] = {column: [] for column in columns}
    for case_id, role in sorted(expected_groups):
        aligned_keys = sorted(key for key in common_keys if key[0] == case_id and key[1] == role)
        if len(aligned_keys) != EXPECTED_SAMPLES_PER_GROUP:
            failures.append(
                f"trajectory row count for {case_id}/{role} is {len(aligned_keys)}, "
                f"expected {EXPECTED_SAMPLES_PER_GROUP}"
            )
        group_deltas: dict[str, list[float]] = {column: [] for column in columns}
        categorical_mismatches: dict[str, int] = {}
        for key in aligned_keys:
            old = r3_rows[key]
            new = r4_rows[key]
            for column in ("circuit_direction", "avoidance_active", "recovering_clearance"):
                if old[column] != new[column]:
                    categorical_mismatches[column] = categorical_mismatches.get(column, 0) + 1
            for column in columns:
                left = old[column].strip()
                right = new[column].strip()
                if not left and not right:
                    continue
                if not left or not right:
                    categorical_mismatches[f"blank_mismatch:{column}"] = (
                        categorical_mismatches.get(f"blank_mismatch:{column}", 0) + 1
                    )
                    continue
                delta = float(right) - float(left)
                if not math.isfinite(delta):
                    raise ValueError(f"nonfinite trajectory delta in {case_id}/{role}/{column}")
                group_deltas[column].append(delta)
                aggregate[column].append(delta)
        by_group[f"{case_id}/{role}"] = {
            "row_count": len(aligned_keys),
            "categorical_mismatches": categorical_mismatches,
            "numeric_deltas": {
                column: delta_summary(values)
                for column, values in group_deltas.items()
                if values
            },
        }

    return {
        "format": "afc-04-r4-r3-calm-crossing-comparison-v1",
        "comparison_valid": not failures,
        "failures": failures,
        "weather": {"r3": r3.get("weather"), "r4": r4.get("weather"), "matched": r3.get("weather") == r4.get("weather")},
        "source_identities": {
            "r3_candidate_pilot_sha256": r3.get("pilot_source_sha256"),
            "r4_production_pilot_sha256": r4.get("pilot_source_sha256"),
            "common_probe_sha256": r4.get("probe_source_sha256"),
            "controller_source_changed": r3.get("pilot_source_sha256") != r4.get("pilot_source_sha256"),
            "world_identities_equal": all(r3.get(key) == r4.get(key) for key in ("field_id", "collision_identity", "lake_identity")),
        },
        "case_comparisons": case_comparisons,
        "trajectory": {
            "r3_csv": str(r3_csv_path.resolve()),
            "r3_csv_sha256": sha256(r3_csv_path),
            "r3_data_rows": len(r3_rows),
            "r4_csv": str(r4_csv_path.resolve()),
            "r4_csv_sha256": sha256(r4_csv_path),
            "r4_data_rows": len(r4_rows),
            "header_equal": header_equal,
            "matched_key_rows": len(common_keys),
            "missing_r4_keys": [list(key) for key in missing_r4[:20]],
            "missing_r3_keys": [list(key) for key in missing_r3[:20]],
            "groups": by_group,
            "aggregate_numeric_deltas": {
                column: delta_summary(values)
                for column, values in aggregate.items()
                if values
            },
        },
        "reports": {
            "r3_candidate": {
                "path": str(r3_report_path.resolve()),
                "sha256": sha256(r3_report_path),
                "classification": r3.get("classification"),
                "deterministic_repeat_exact": r3.get("deterministic_repeat", {}).get("exact_state_command_match"),
            },
            "r4_production": {
                "path": str(r4_report_path.resolve()),
                "sha256": sha256(r4_report_path),
                "classification": r4.get("classification"),
                "deterministic_repeat_exact": r4.get("deterministic_repeat", {}).get("exact_state_command_match"),
            },
        },
        "target_height_interpretation": (
            "Retain R4's initial_target_height_matches_nominal=false flags as reported diagnostics. "
            "The R4 local-terrain clearance floor raises the target above nominal 35 m; its exact "
            "per-route value is included above. This comparison does not call the result equivalent."
        ),
        "scope_note": (
            "The two reports share calm weather, probe, route seeds, field, collision world and lake. "
            "Differences are observed source/version deltas for these fixtures, not a claim of universal "
            "R2 equivalence or physical validation."
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--r3-report", type=Path, required=True)
    parser.add_argument("--r3-csv", type=Path, required=True)
    parser.add_argument("--r4-report", type=Path, required=True)
    parser.add_argument("--r4-csv", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    output = args.out.expanduser().resolve()
    if output.exists():
        parser.error("output path must be new")
    result = compare(args.r3_report, args.r3_csv, args.r4_report, args.r4_csv)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(result, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps({
        "out": str(output),
        "comparison_valid": result["comparison_valid"],
        "failures": result["failures"],
        "matched_trajectory_rows": result["trajectory"]["matched_key_rows"],
    }, sort_keys=True))
    return 0 if result["comparison_valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
