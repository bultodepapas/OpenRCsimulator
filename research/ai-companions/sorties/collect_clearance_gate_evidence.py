"""Bind AFC-09 R2 gate-only outcomes to their retained run/replay receipts."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


SOLVER_SHA256 = "21c675a567d7a28a07c2e417fd12581ea7346cf2423cb9d839f1de4f24af46c3"
PILOT_SHA256 = "ab03aa2ff54061e0a4110ccedacfac4369c8491fcafe1411637fd9caedb08395"
AIRCRAFT_SHA256 = "5ef239c6c0470d6870bf72656cfb12795833764b0bd57c7d93bc17f790bd2007"
ORIGINAL_DRIVER_SHA256 = "b8902dee829422974d9020781e7bd629c4d30145147aecc6b3c5f2f246fc8b6d"
CASE_MAP = (
    ("east-calm", "east", "calm", 0),
    ("east-headwind-s20261015", "east", "headwind", 20261015),
    ("east-north-crosswind-s20261025", "east", "north_crosswind_0p5", 20261025),
    ("east-south-crosswind-s20261027", "east", "south_crosswind_0p5", 20261027),
    ("west-calm", "west", "calm", 0),
    ("west-headwind-s20261039", "west", "headwind", 20261039),
    ("west-north-crosswind-s20261044", "west", "north_crosswind_0p5", 20261044),
    ("west-south-crosswind-s20261051", "west", "south_crosswind_0p5", 20261051),
)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def find_runner_report(directory: Path) -> Path:
    matches = sorted(directory.rglob("report.json"))
    if len(matches) != 1:
        raise ValueError(f"expected one run_checked report under {directory}, found {len(matches)}")
    return matches[0]


def artifact(path: Path, base: Path) -> dict[str, Any]:
    try:
        relative_path: str | None = str(path.resolve().relative_to(base.resolve()))
    except ValueError:
        relative_path = None
    return {"path": str(path), "relative_to_evidence_root": relative_path, "sha256": digest(path), "bytes": path.stat().st_size}


def case_record(name: str, direction: str, profile: str, seed: int,
                evidence_root: Path, r1_case: dict[str, Any], candidate_driver_hash: str,
                harness_hash: str) -> dict[str, Any]:
    case_root = evidence_root / "cases" / name
    candidate_report_path = case_root / "candidate-report.json"
    candidate_orfl = case_root / "candidate.orfl"
    candidate = read_json(candidate_report_path)
    flight_receipt_path = find_runner_report(case_root / "runner")
    flight_receipt = read_json(flight_receipt_path)
    replay_path = case_root / "exact" / "replay.json"
    csv_path = case_root / "exact" / "flight.csv"
    replay = read_json(replay_path)
    replay_receipt_path = find_runner_report(case_root / "exact" / "runner")
    replay_receipt = read_json(replay_receipt_path)
    comparison_path = case_root / "common-prefix.json"
    comparison = read_json(comparison_path)
    old_csv = Path(r1_case["exact_replay"]["numeric_flight_csv"]["path"])
    old_replay_path = old_csv.parent / "replay.json"
    old_orfl_path = Path(r1_case["raw_orfl"]["path"])
    candidate_orfl_hash = digest(candidate_orfl)
    candidate_csv_hash = digest(csv_path)
    old_csv_hash = digest(old_csv)
    old_replay_hash = digest(old_replay_path)
    old_orfl_hash = digest(old_orfl_path)

    if candidate.get("driver_source_sha256") != candidate_driver_hash:
        raise ValueError(f"{name}: run references a different candidate driver")
    if candidate.get("test_harness_source_sha256") != harness_hash:
        raise ValueError(f"{name}: run references a different test harness")
    if candidate.get("pilot_sha256") != PILOT_SHA256:
        raise ValueError(f"{name}: pilot identity differs from the selected C5e pilot")
    if candidate.get("aircraft_input_sha256") != AIRCRAFT_SHA256:
        raise ValueError(f"{name}: aircraft input identity differs from the R1 source")
    if candidate.get("solver_sha256") != SOLVER_SHA256:
        raise ValueError(f"{name}: solver identity differs from the frozen R1 solver")
    if replay.get("source_sha256") != candidate_orfl_hash:
        raise ValueError(f"{name}: exact replay is not bound to the retained candidate ORFL")
    if replay.get("status") != "ok" or replay.get("complete") is not True or replay.get("solver_changed") is not False:
        raise ValueError(f"{name}: candidate exact replay is incomplete or changed solver")
    if replay.get("current_solver_sha256") != SOLVER_SHA256:
        raise ValueError(f"{name}: exact replay used a different solver")
    if replay.get("rows") != replay.get("final_tick", -1) - replay.get("first_tick", 0) + 1:
        raise ValueError(f"{name}: exact replay row count does not cover its tick interval")
    if replay_receipt.get("exit_code") != 0 or replay_receipt.get("complete") is not True:
        raise ValueError(f"{name}: candidate exact replay run_checked receipt did not pass")
    if comparison.get("status") != "identical" or comparison.get("mismatched_cells") != 0:
        raise ValueError(f"{name}: common-prefix CSV comparison is not identical")
    if comparison.get("candidate_final_tick") != replay.get("final_tick"):
        raise ValueError(f"{name}: common-prefix comparison candidate tick differs from replay")
    if comparison.get("baseline_final_tick") != r1_case["exact_replay"]["final_tick"]:
        raise ValueError(f"{name}: common-prefix baseline tick differs from the retained R1 exact replay")
    if comparison.get("common_final_tick") != min(comparison.get("baseline_final_tick", -1), comparison.get("candidate_final_tick", -1)):
        raise ValueError(f"{name}: common-prefix comparison did not stop at the smaller final tick")
    if comparison.get("common_prefix_rows") != comparison.get("common_final_tick", -1) - comparison.get("first_tick", 0) + 1:
        raise ValueError(f"{name}: common-prefix row count does not cover its declared tick interval")
    if comparison.get("baseline_csv_sha256") != old_csv_hash or old_csv_hash != r1_case["exact_replay"]["numeric_flight_csv"]["sha256"]:
        raise ValueError(f"{name}: common-prefix baseline CSV is not the retained R1 exact replay")
    if comparison.get("candidate_csv_sha256") != candidate_csv_hash:
        raise ValueError(f"{name}: common-prefix candidate CSV is not the retained candidate exact replay")
    if comparison.get("baseline_replay_sha256") != old_replay_hash or old_replay_hash != r1_case["exact_replay"]["replay_report"]["sha256"]:
        raise ValueError(f"{name}: common-prefix baseline replay report is not the retained R1 exact replay")
    if comparison.get("candidate_replay_sha256") != digest(replay_path):
        raise ValueError(f"{name}: common-prefix candidate replay report is not the retained exact replay")
    if comparison.get("solver_sha256") != SOLVER_SHA256:
        raise ValueError(f"{name}: common-prefix comparison used a different solver")
    if old_orfl_hash != r1_case["raw_orfl"]["sha256"]:
        raise ValueError(f"{name}: retained R1 ORFL does not match its recorded hash")
    if flight_receipt.get("process_exit") not in (0, 1):
        raise ValueError(f"{name}: flight run has an unexpected exit status")
    if flight_receipt.get("complete") is not True:
        raise ValueError(f"{name}: flight runner did not finish collecting its result")
    if candidate.get("start_error") or flight_receipt.get("counts", {}).get("error", 0) != 0:
        raise ValueError(f"{name}: candidate run has a setup or engine error")
    if candidate.get("checks") != 26 or flight_receipt.get("process_exit") != (1 if candidate.get("failures") else 0):
        raise ValueError(f"{name}: gate harness count or process exit does not match the retained candidate report")

    entry = r1_case["approach_entry"]
    approach_tas = float(entry["airspeed_mps"])
    candidate_clear_pass = candidate.get("candidate_clearance_gate_pass") is True
    historical_22_pass = r1_case.get("full_22_gate_pass") is True
    accepted = historical_22_pass and candidate_clear_pass
    # R1's stored display path contains `\\neplay.json` from an escaped-path
    # serialization typo. We resolve the sibling file and above require the
    # retained SHA-256 and common-prefix receipt to match it.
    return {
        "case_id": name,
        "direction": direction,
        "weather_profile": profile,
        "turbulence_seed": seed,
        "historical_r1": {
            "original_22_gate_pass": historical_22_pass,
            "failed_check_count": r1_case.get("failed_check_count"),
            "failure_class": r1_case.get("failure_class"),
            "failure_summary": r1_case.get("failure_summary"),
            "approach_entry_tas_mps": approach_tas,
            "approach_tas_at_or_below_12_5_mps": approach_tas <= 12.5,
            "original_orfl": artifact(Path(r1_case["raw_orfl"]["path"]), evidence_root),
            "original_exact_csv": artifact(old_csv, evidence_root),
            "original_replay_report": artifact(old_replay_path, evidence_root),
        },
        "candidate_r2": {
            "complete": candidate.get("complete") is True,
            "full_clear_gate_pass": candidate_clear_pass,
            "approach_entry_readiness": candidate.get("approach_entry_readiness", {}),
            "start_error": candidate.get("start_error", ""),
            "error": candidate.get("error", ""),
            "tick_count": candidate.get("tick_count"),
            "duration_s": candidate.get("duration_s"),
            "legacy_wheel_only_vacated": candidate.get("legacy_runway_vacated"),
            "legacy_wheel_only_vacate_elapsed_s": candidate.get("legacy_vacate_time_s"),
            "full_clear_vacate_elapsed_s": candidate.get("vacate_time_s"),
            "vacate_timeout": candidate.get("vacate_timeout"),
            "current_full_footprint_clear": candidate.get("vacate_full_footprint_clear"),
            "current_all_wheels_down": candidate.get("vacate_all_wheels_down"),
            "current_all_anchors_stiction": candidate.get("vacate_all_anchors"),
            "clear_dwell_s": candidate.get("vacate_clear_dwell_s"),
            "clear_reset_count": candidate.get("vacate_clear_reset_count"),
            "minimum_runway_e_end_margin_m": candidate.get("vacate_min_lateral_footprint_margin_m"),
            "corridor_violation": candidate.get("vacate_lateral_footprint_violation"),
            "endpoint": candidate.get("vacate_end", {}),
            "damage": candidate.get("terminal_damage"),
            "sim_fault": candidate.get("sim_fault"),
            "harness_checks": candidate.get("checks"),
            "harness_failures": candidate.get("failures", []),
            "harness_ok": candidate.get("ok"),
            "runtime_source_identity": {
                key: candidate.get(key)
                for key in (
                    "aircraft_input_sha256",
                    "collision_setup_source_sha256",
                    "collision_world_source_sha256",
                    "field_collision_sha256",
                    "field_source_sha256",
                    "flight_session_source_sha256",
                    "ground_start_source_sha256",
                    "landing_maneuver_source_sha256",
                    "lake_identity",
                    "lake_source_sha256",
                    "pilot_sha256",
                    "solver_sha256",
                    "weather_config_sha256",
                )
            },
            "full_sortie_accepted_under_r1_plus_r2": accepted,
            "raw_orfl": artifact(candidate_orfl, evidence_root),
            "raw_report": artifact(candidate_report_path, evidence_root),
            "flight_run_checked": {
                "exit_code": flight_receipt.get("exit_code"),
                "process_exit": flight_receipt.get("process_exit"),
                "reason": flight_receipt.get("reason"),
                "complete": flight_receipt.get("complete"),
                "counts": flight_receipt.get("counts", {}),
                "diagnostics": flight_receipt.get("diagnostics", []),
                "elapsed_seconds": flight_receipt.get("elapsed_seconds"),
                "report": artifact(flight_receipt_path, evidence_root),
                "engine_log": artifact(Path(flight_receipt["log"]), evidence_root),
            },
            "exact_replay": {
                "complete": replay.get("complete"),
                "solver_changed": replay.get("solver_changed"),
                "rows": replay.get("rows"),
                "first_tick": replay.get("first_tick"),
                "final_tick": replay.get("final_tick"),
                "solver_sha256": replay.get("current_solver_sha256"),
                "report": artifact(replay_path, evidence_root),
                "csv": artifact(csv_path, evidence_root),
                "run_checked": artifact(replay_receipt_path, evidence_root),
                "engine_log": artifact(Path(replay_receipt["log"]), evidence_root),
            },
            "common_prefix": {
                "status": comparison.get("status"),
                "comparison_scope": comparison.get("comparison_scope"),
                "baseline_final_tick": comparison.get("baseline_final_tick"),
                "candidate_final_tick": comparison.get("candidate_final_tick"),
                "common_final_tick": comparison.get("common_final_tick"),
                "rows": comparison.get("common_prefix_rows"),
                "columns": comparison.get("column_count"),
                "mismatched_rows": comparison.get("mismatched_rows"),
                "mismatched_cells": comparison.get("mismatched_cells"),
                "report": artifact(comparison_path, evidence_root),
            },
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--r1-verification", required=True)
    parser.add_argument("--evidence-root", required=True)
    parser.add_argument("--candidate-driver", required=True)
    parser.add_argument("--test-harness", required=True)
    parser.add_argument("--state-check-script", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    r1_path = Path(args.r1_verification).resolve()
    evidence_root = Path(args.evidence_root).resolve()
    driver_path = Path(args.candidate_driver).resolve()
    harness_path = Path(args.test_harness).resolve()
    state_check_script = Path(args.state_check_script).resolve()
    readiness_classifier = harness_path.with_name("approach_entry_readiness.gd")
    run_checked_script = Path(__file__).resolve().parents[3] / "tools" / "godot" / "run_checked.py"
    driver_hash = digest(driver_path)
    harness_hash = digest(harness_path)
    if driver_hash == ORIGINAL_DRIVER_SHA256:
        raise ValueError("candidate driver is identical to the original driver")
    original_driver_path = driver_path.with_name("external_sortie_driver.gd")
    if digest(original_driver_path) != ORIGINAL_DRIVER_SHA256:
        raise ValueError("the original historical driver no longer matches the R1 source hash")

    r1 = read_json(r1_path)
    selected = []
    for name, direction, profile, seed in CASE_MAP:
        matches = [case for case in r1["cases"] if case.get("direction") == direction
                   and case.get("weather_profile") == profile and case.get("turbulence_seed") == seed]
        if len(matches) != 1:
            raise ValueError(f"R1 verification has {len(matches)} matches for {name}")
        selected.append(case_record(name, direction, profile, seed, evidence_root,
                                    matches[0], driver_hash, harness_hash))

    check_reports = []
    for relative in ("state-checks", "state-checks-default"):
        check_report_path = find_runner_report(evidence_root / relative)
        check_report = read_json(check_report_path)
        log_path = Path(check_report["log"])
        log_text = log_path.read_text(encoding="utf-8", errors="replace")
        expected_driver = "external_sortie_driver_candidate_taxi.gd" if relative.endswith("default") else "external_sortie_driver_candidate_clearance.gd"
        expected_marker = f"AFC-09 taxi exit clearance (C:/DEVELOPMENT/OpenRCsimulator/research/ai-companions/sorties/{expected_driver}): 21 checks, 0 failed"
        if check_report.get("exit_code") != 0 or expected_marker not in log_text:
            raise ValueError(f"{relative}: the 21-check receipt did not pass against {expected_driver}")
        check_reports.append({
            "driver": expected_driver,
            "checks": 21,
            "failed": 0,
            "run_checked": artifact(check_report_path, evidence_root),
            "engine_log": artifact(log_path, evidence_root),
        })

    output = Path(args.out).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    document = {
        "format": "afc09-clearance-gate-r2-verification-v1",
        "scope": "Research-only C5e gate qualification. Flight commands, taxi commands, physics, aircraft data, and the historical R1 22 gates were unchanged.",
        "result": {
            "case_count": len(selected),
            "r1_original_22_gate_passes": sum(case["historical_r1"]["original_22_gate_pass"] for case in selected),
            "r2_full_clear_gate_passes": sum(case["candidate_r2"]["full_clear_gate_pass"] for case in selected),
            "combined_full_sortie_acceptances": sum(case["candidate_r2"]["full_sortie_accepted_under_r1_plus_r2"] for case in selected),
            "combined_acceptance_rule": "R1 original 22 gates pass and R2 current full gear+hull clearance gate passes; all selected candidate ORFLs also exact-replay unchanged and have identical all-column CSVs over their common tick prefixes.",
            "common_prefix_comparisons_identical": sum(case["candidate_r2"]["common_prefix"]["status"] == "identical" for case in selected),
            "common_prefix_rows_total": sum(case["candidate_r2"]["common_prefix"]["rows"] for case in selected),
        },
        "source_identity": {
            "frozen_app_mirror": "D:/OpenRCsimulator-AFC-work/evidence/avoidance/AFC-04-R4/mirror/app",
            "candidate_driver": {"path": str(driver_path), "sha256": driver_hash},
            "original_driver": {"path": str(original_driver_path), "sha256": ORIGINAL_DRIVER_SHA256},
            "test_harness": {"path": str(harness_path), "sha256": harness_hash},
            "pilot": {"path": "C:/DEVELOPMENT/OpenRCsimulator/tmp/afc04-isolated/research/ai-companions/sorties/circuit_pilot_candidate_c5e.gd", "sha256": PILOT_SHA256},
            "aircraft_input_sha256": AIRCRAFT_SHA256,
            "solver_sha256": SOLVER_SHA256,
            "state_check_script": {"path": str(state_check_script), "sha256": digest(state_check_script)},
            "approach_readiness_classifier": {"path": str(readiness_classifier), "sha256": digest(readiness_classifier)},
            "common_prefix_comparator": {"path": str(Path(__file__).resolve().with_name("compare_sortie_common_prefix.py")), "sha256": digest(Path(__file__).resolve().with_name("compare_sortie_common_prefix.py"))},
            "run_checked_script": {"path": str(run_checked_script), "sha256": digest(run_checked_script)},
            "evidence_collector": {"path": str(Path(__file__).resolve()), "sha256": digest(Path(__file__).resolve())},
            "r1_verification": artifact(r1_path, r1_path.parents[2]),
        },
        "unit_checks": check_reports,
        "cases": selected,
    }
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(document, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")
    print(json.dumps(document["result"], indent=2, sort_keys=True))
    print(f"Wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
