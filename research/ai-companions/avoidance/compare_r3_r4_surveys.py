#!/usr/bin/env python3
"""Quantify AFC-04 R3 candidate versus R4 production encounter survey changes."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from typing import Any


ROUTE_CASES = {
    "seed-20261020-head-on",
    "seed-20261020-crossing-left",
    "seed-20261020-crossing-right",
    "seed-20261021-head-on",
    "seed-20261021-crossing-left",
    "seed-20261021-crossing-right",
}
NON_ADMITTED_CASES = {"seed-20261020-parallel-two-threats"}
ROUTE_ROW_KEYS = ("seed", "case", "role", "tick")
NON_NUMERIC_COLUMNS = {"case", "seed", "circuit_direction", "tick", "time_s", "role",
                       "avoidance_active", "recovering_clearance"}


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


def flatten_numbers(value: Any, prefix: str = "") -> dict[str, int | float]:
    result: dict[str, int | float] = {}
    if isinstance(value, dict):
        for key, child in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            result.update(flatten_numbers(child, path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            path = f"{prefix}[{index}]"
            result.update(flatten_numbers(child, path))
    elif type(value) in (int, float) and math.isfinite(float(value)):
        result[prefix] = value
    return result


def compare_case_metrics(old: dict[str, Any], new: dict[str, Any]) -> dict[str, Any]:
    old_numbers = flatten_numbers(old)
    new_numbers = flatten_numbers(new)
    keys = sorted(set(old_numbers) | set(new_numbers))
    changed = []
    for key in keys:
        if key not in old_numbers or key not in new_numbers:
            changed.append({"field": key, "r3": old_numbers.get(key), "r4": new_numbers.get(key),
                            "change": "field_added_or_removed"})
        elif old_numbers[key] != new_numbers[key]:
            changed.append({"field": key, "r3": old_numbers[key], "r4": new_numbers[key],
                            "delta_r4_minus_r3": float(new_numbers[key]) - float(old_numbers[key])})
    return {
        "r3_numeric_field_count": len(old_numbers),
        "r4_numeric_field_count": len(new_numbers),
        "changed_numeric_fields": changed,
        "unchanged_numeric_field_count": len(set(old_numbers) & set(new_numbers)) - sum(
            1 for item in changed if item.get("change") is None
        ),
        "r3_valid_run": old.get("valid_run"),
        "r4_valid_run": new.get("valid_run"),
        "r3_complete": old.get("complete"),
        "r4_complete": new.get("complete"),
        "r3_player_separation_gate": old.get("separation_gate_passed"),
        "r4_player_separation_gate": new.get("separation_gate_passed"),
        "r3_min_player_separation_m": old.get("min_separation_to_player_m"),
        "r4_min_player_separation_m": new.get("min_separation_to_player_m"),
        "delta_min_player_separation_m": (
            float(new["min_separation_to_player_m"]) - float(old["min_separation_to_player_m"])
            if old.get("min_separation_to_player_m") is not None
            and new.get("min_separation_to_player_m") is not None else None
        ),
        "r3_initial_commanded_target_height_m": old.get("initial_commanded_target_height_m"),
        "r4_initial_commanded_target_height_m": new.get("initial_commanded_target_height_m"),
        "delta_initial_commanded_target_height_m": (
            float(new["initial_commanded_target_height_m"])
            - float(old["initial_commanded_target_height_m"])
            if old.get("initial_commanded_target_height_m") is not None
            and new.get("initial_commanded_target_height_m") is not None else None
        ),
        "r3_state_command_sha256": old.get("state_command_sha256"),
        "r4_state_command_sha256": new.get("state_command_sha256"),
        "state_command_hash_equal": old.get("state_command_sha256") == new.get("state_command_sha256"),
    }


def trajectory_rows(path: Path) -> tuple[list[str], dict[tuple[str, str, str, int], dict[str, str]]]:
    rows: dict[tuple[str, str, str, int], dict[str, str]] = {}
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        header = list(reader.fieldnames or [])
        for row in reader:
            key = (row["seed"], row["case"], row["role"], int(row["tick"]))
            if key in rows:
                raise ValueError(f"duplicate trajectory row in {path}: {key}")
            rows[key] = row
    return header, rows


def csv_deltas(old_path: Path, new_path: Path) -> dict[str, Any]:
    old_header, old_rows = trajectory_rows(old_path)
    new_header, new_rows = trajectory_rows(new_path)
    header_equal = old_header == new_header
    common_keys = set(old_rows) & set(new_rows)
    missing_old = sorted(set(old_rows) - set(new_rows))
    missing_new = sorted(set(new_rows) - set(old_rows))
    summary: dict[str, Any] = {
        "r3_csv": str(old_path.resolve()),
        "r3_csv_sha256": sha256(old_path),
        "r3_data_rows": len(old_rows),
        "r4_csv": str(new_path.resolve()),
        "r4_csv_sha256": sha256(new_path),
        "r4_data_rows": len(new_rows),
        "header_equal": header_equal,
        "r3_header": old_header,
        "r4_header": new_header,
        "matched_key_rows": len(common_keys),
        "missing_r4_keys": [list(key) for key in missing_old[:20]],
        "missing_r3_keys": [list(key) for key in missing_new[:20]],
        "route_groups": {},
        "non_admitted_fixture_groups": {},
        "route_aggregate_numeric": {},
    }
    if not header_equal:
        return summary

    numeric = [column for column in old_header if column not in NON_NUMERIC_COLUMNS]
    groups: dict[tuple[str, str, str], list[tuple[dict[str, str], dict[str, str]]]] = {}
    for key in sorted(common_keys):
        seed, case, role, _tick = key
        group_key = (seed, case, role)
        groups.setdefault(group_key, []).append((old_rows[key], new_rows[key]))

    aggregate: dict[str, list[float]] = {column: [] for column in numeric}
    for (seed, case, role), aligned in groups.items():
        metrics: dict[str, Any] = {
            "row_count": len(aligned),
            "categorical_mismatches": {},
            "numeric_deltas": {},
        }
        if case in {key.rsplit("-", 1)[-1] for key in ROUTE_CASES}:
            # Case and seed are split in the CSV, so recover the report case ID.
            case_id = f"seed-{seed}-{case}"
            group_out = summary["route_groups"] if case_id in ROUTE_CASES else summary["non_admitted_fixture_groups"]
        else:
            case_id = f"seed-{seed}-{case}"
            group_out = summary["route_groups"] if case_id in ROUTE_CASES else summary["non_admitted_fixture_groups"]
        for column in ("circuit_direction", "avoidance_active", "recovering_clearance"):
            mismatches = sum(1 for left, right in aligned if left[column] != right[column])
            if mismatches:
                metrics["categorical_mismatches"][column] = mismatches
        for column in numeric:
            deltas: list[float] = []
            for left, right in aligned:
                a, b = left[column].strip(), right[column].strip()
                if not a and not b:
                    continue
                if not a or not b:
                    continue
                delta = float(b) - float(a)
                if not math.isfinite(delta):
                    raise ValueError(f"nonfinite trajectory delta in {case_id}/{role}/{column}")
                deltas.append(delta)
            aggregate[column].extend(deltas)
            if deltas:
                absolute = sorted(abs(value) for value in deltas)
                p95_index = min(len(absolute) - 1, math.ceil(0.95 * len(absolute)) - 1)
                metrics["numeric_deltas"][column] = {
                    "compared_values": len(deltas),
                    "different_values": sum(value != 0.0 for value in deltas),
                    "mean_delta_r4_minus_r3": sum(deltas) / len(deltas),
                    "rms_delta": math.sqrt(sum(value * value for value in deltas) / len(deltas)),
                    "max_abs_delta": max(absolute),
                    "p95_abs_delta": absolute[p95_index],
                    "minimum_delta": min(deltas),
                    "maximum_delta": max(deltas),
                }
        group_out[f"{case_id}/{role}"] = metrics

    for column, deltas in aggregate.items():
        if deltas:
            summary["route_aggregate_numeric"][column] = {
                "compared_values": len(deltas),
                "different_values": sum(value != 0.0 for value in deltas),
                "mean_delta_r4_minus_r3": sum(deltas) / len(deltas),
                "rms_delta": math.sqrt(sum(value * value for value in deltas) / len(deltas)),
                "max_abs_delta": max(abs(value) for value in deltas),
                "minimum_delta": min(deltas),
                "maximum_delta": max(deltas),
            }
    return summary


def compare(r3_dir: Path, r4_dir: Path) -> dict[str, Any]:
    r3_dir, r4_dir = r3_dir.resolve(), r4_dir.resolve()
    r3_report_path, r4_report_path = r3_dir / "report.json", r4_dir / "report.json"
    r3, r4 = read_json(r3_report_path), read_json(r4_report_path)
    r3_by_id = {str(item.get("case_id")): item for item in r3.get("cases", []) if isinstance(item, dict)}
    r4_by_id = {str(item.get("case_id")): item for item in r4.get("cases", []) if isinstance(item, dict)}
    r3_cases, r4_cases = set(r3_by_id), set(r4_by_id)
    all_ids = sorted(r3_cases | r4_cases)
    case_metrics: dict[str, Any] = {}
    for case_id in all_ids:
        if case_id not in r3_by_id or case_id not in r4_by_id:
            case_metrics[case_id] = {"missing_from_r3": case_id not in r3_by_id,
                                     "missing_from_r4": case_id not in r4_by_id}
            continue
        case_metrics[case_id] = compare_case_metrics(r3_by_id[case_id], r4_by_id[case_id])

    r3_context = {key: r3.get(key) for key in
                  ("weather", "seconds", "requested_ticks", "pilot_source_sha256", "probe_source_sha256",
                   "collision_identity", "lake_identity", "valid_complete_runs",
                   "separation_gate_passed_for_all_cases")}
    r4_context = {key: r4.get(key) for key in
                  ("weather", "seconds", "requested_ticks", "pilot_source_sha256", "probe_source_sha256",
                   "collision_identity", "lake_identity", "valid_complete_runs",
                   "separation_gate_passed_for_all_cases")}
    return {
        "format": "afc-04-r3-r4-encounter-survey-delta-v1",
        "comparison_scope": "Same seeded six nominal route cases and separate constructed two-threat fixture; R3 retained candidate versus R4 production pilot.",
        "equivalence_claimed": False,
        "terrain_floor_interpretation": "Compare reported target-height and trajectory deltas; attribute them to the intentional local-terrain floor only where the recorded target-height data supports that interpretation.",
        "r3_report": str(r3_report_path),
        "r3_report_sha256": sha256(r3_report_path),
        "r4_report": str(r4_report_path),
        "r4_report_sha256": sha256(r4_report_path),
        "r3_context": r3_context,
        "r4_context": r4_context,
        "same_world_and_probe": (
            r3.get("collision_identity") == r4.get("collision_identity")
            and r3.get("lake_identity") == r4.get("lake_identity")
            and r3.get("probe_source_sha256") == r4.get("probe_source_sha256")
        ),
        "same_pilot_source": r3.get("pilot_source_sha256") == r4.get("pilot_source_sha256"),
        "route_case_ids": sorted((r3_cases & r4_cases) & ROUTE_CASES),
        "non_admitted_case_ids": sorted((r3_cases & r4_cases) & NON_ADMITTED_CASES),
        "missing_case_ids": {"r3": sorted(r4_cases - r3_cases), "r4": sorted(r3_cases - r4_cases)},
        "case_metric_deltas": case_metrics,
        "trajectory_csv": csv_deltas(r3_dir / "trajectory.csv", r4_dir / "trajectory.csv"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--r3-dir", type=Path, required=True)
    parser.add_argument("--r4-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    output = args.out.expanduser().resolve()
    if output.exists():
        parser.error("output path must be new")
    result = compare(args.r3_dir, args.r4_dir)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(result, stream, indent=2, sort_keys=True)
        stream.write("\n")
    trajectory = result["trajectory_csv"]
    summary = {
        "out": str(output),
        "same_world_and_probe": result["same_world_and_probe"],
        "same_pilot_source": result["same_pilot_source"],
        "r3_rows": trajectory["r3_data_rows"],
        "r4_rows": trajectory["r4_data_rows"],
        "matched_rows": trajectory["matched_key_rows"],
        "route_aggregate_numeric": trajectory["route_aggregate_numeric"],
    }
    print(json.dumps(summary, sort_keys=True))
    return 0 if result["same_world_and_probe"] and not result["missing_case_ids"]["r3"] \
        and not result["missing_case_ids"]["r4"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
