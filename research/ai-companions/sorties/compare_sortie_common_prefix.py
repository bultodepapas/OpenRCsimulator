"""Compare every CSV cell through the shared final tick of two exact replays."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import sys
from typing import Any


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_replay(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("complete") is not True or value.get("solver_changed") is not False:
        raise ValueError(f"{path}: exact replay must be complete with solver_changed=false")
    for key in ("first_tick", "final_tick", "rows"):
        if type(value.get(key)) is not int:
            raise ValueError(f"{path}: replay report lacks integer {key}")
    if value["rows"] <= 0 or value["final_tick"] - value["first_tick"] + 1 != value["rows"]:
        raise ValueError(f"{path}: replay tick range and row count disagree")
    solver = value.get("baseline_solver_sha256")
    if not isinstance(solver, str) or len(solver) != 64 or value.get("current_solver_sha256") != solver:
        raise ValueError(f"{path}: exact replay solver identities disagree")
    return value


def compare(args: argparse.Namespace) -> dict[str, Any]:
    baseline_report_path = Path(args.baseline_replay).resolve()
    candidate_report_path = Path(args.candidate_replay).resolve()
    baseline_report = read_replay(baseline_report_path)
    candidate_report = read_replay(candidate_report_path)
    if baseline_report["baseline_solver_sha256"] != candidate_report["baseline_solver_sha256"]:
        raise ValueError("baseline and candidate exact replays use different solver identities")
    first_tick = max(baseline_report["first_tick"], candidate_report["first_tick"])
    if baseline_report["first_tick"] != candidate_report["first_tick"]:
        raise ValueError("baseline and candidate exact replays start at different ticks")
    common_final_tick = min(baseline_report["final_tick"], candidate_report["final_tick"])
    prefix_rows = common_final_tick - first_tick + 1
    if prefix_rows <= 0:
        raise ValueError("baseline and candidate exact replays have no common tick prefix")

    baseline_path = Path(args.baseline_csv).resolve()
    candidate_path = Path(args.candidate_csv).resolve()
    compared_rows = 0
    mismatched_cells = 0
    mismatched_rows = 0
    first_difference: dict[str, Any] | None = None
    with baseline_path.open("r", encoding="utf-8", newline="") as baseline_file, \
            candidate_path.open("r", encoding="utf-8", newline="") as candidate_file:
        baseline = csv.DictReader(baseline_file)
        candidate = csv.DictReader(candidate_file)
        if baseline.fieldnames is None or candidate.fieldnames != baseline.fieldnames:
            raise ValueError("baseline and candidate CSV headers differ")
        columns = baseline.fieldnames
        for row_index in range(prefix_rows):
            baseline_row = next(baseline, None)
            candidate_row = next(candidate, None)
            if baseline_row is None or candidate_row is None:
                raise ValueError(f"CSV ended before common-prefix row {row_index + 1}")
            expected_tick = first_tick + row_index
            try:
                baseline_tick = int(str(baseline_row["tick"]))
                candidate_tick = int(str(candidate_row["tick"]))
            except (KeyError, TypeError, ValueError) as error:
                raise ValueError(f"invalid tick at common-prefix row {row_index + 1}") from error
            if baseline_tick != expected_tick or candidate_tick != expected_tick:
                raise ValueError(
                    f"tick alignment failed at row {row_index + 1}: "
                    f"expected {expected_tick}, got {baseline_tick}/{candidate_tick}"
                )
            row_mismatches = 0
            for column in columns:
                left = baseline_row.get(column)
                right = candidate_row.get(column)
                if left != right:
                    row_mismatches += 1
                    mismatched_cells += 1
                    if first_difference is None:
                        first_difference = {
                            "tick": expected_tick,
                            "column": column,
                            "baseline": left,
                            "candidate": right,
                        }
            mismatched_rows += int(row_mismatches > 0)
            compared_rows += 1

    return {
        "format": "afc09-sortie-common-prefix-comparison-v1",
        "status": "identical" if mismatched_cells == 0 else "different",
        "comparison_scope": "Exact string comparison of every CSV column through min(baseline final tick, candidate final tick); no suffix comparison.",
        "baseline_csv": str(baseline_path),
        "baseline_csv_sha256": sha256(baseline_path),
        "candidate_csv": str(candidate_path),
        "candidate_csv_sha256": sha256(candidate_path),
        "baseline_replay": str(baseline_report_path),
        "baseline_replay_sha256": sha256(baseline_report_path),
        "candidate_replay": str(candidate_report_path),
        "candidate_replay_sha256": sha256(candidate_report_path),
        "solver_sha256": baseline_report["baseline_solver_sha256"],
        "first_tick": first_tick,
        "baseline_final_tick": baseline_report["final_tick"],
        "candidate_final_tick": candidate_report["final_tick"],
        "common_final_tick": common_final_tick,
        "common_prefix_rows": prefix_rows,
        "compared_rows": compared_rows,
        "column_count": len(columns),
        "mismatched_rows": mismatched_rows,
        "mismatched_cells": mismatched_cells,
        "first_difference": first_difference,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-csv", required=True)
    parser.add_argument("--candidate-csv", required=True)
    parser.add_argument("--baseline-replay", required=True)
    parser.add_argument("--candidate-replay", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    try:
        result = compare(args)
        output = Path(args.out).resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(result, stream, indent=2, sort_keys=True, allow_nan=False)
            stream.write("\n")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "identical" else 1


if __name__ == "__main__":
    raise SystemExit(main())
