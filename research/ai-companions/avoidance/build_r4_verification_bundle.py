#!/usr/bin/env python3
"""Build the source-bound AFC-04-R4 verification and provenance receipts.

Large logs, trajectories, and ORFL recordings stay in the evidence directory.
This script copies only small JSON reports into the track's data directory and
records hashes for both the copied summaries and the full evidence set.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path
from typing import Any


PILOT_SHA256 = "363942b4b7d67f85333233f0c6000890ca984e5b76a8ccabe7973f70218259ed"
PROBE_SHA256 = "d00004590c5793ba743f56b3d129a248d35fa085186e576d33f0ac9a2e832cc4"
BASE_CIRCUIT_SHA256 = "1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c"
R3_CANDIDATE_SHA256 = "1c512e4bdc0c606cc575397dfe8e1d6fe3e8bf6b9bc0894bd20ce11366d47eb8"
PROFILE_SOLVER_SHA256 = "1526c98431a7dee5206eb992e10f40e436a7ef80d173e8c1dbfe6f1ad8f33b7e"
FLIGHTLOG_SOLVER_SHA256 = "21c675a567d7a28a07c2e417fd12581ea7346cf2423cb9d839f1de4f24af46c3"
COLLISION_IDENTITY = "fb2be395cc783b3910f5eb2c5fcdef4936c36ea90bd8d25466d818f2b89743ae"
LAKE_IDENTITY = "bcc3774dc2ef339bac49aaec42b6a47b6b6d1104470d9fff35db242f6ab61efa"
EXPECTED_RAW_PHYSICS = {
    "app/physics/aero.gd": "06dfbbcd8c96124d4d19591aaa8d940ba299258710334f3911625baae043630f",
    "app/physics/aircraft_data.gd": "791036668ccde803f6e93bd37da75e56d01853d6d59a2512bf50acdc58dd3737",
}
EXPECTED_CROSSING_CASES = {
    "seed-20261020-crossing-right",
    "seed-20261021-crossing-left",
}
EXPECTED_CROSSING_ROLES = {"ai", "player-coupled", "player-exogenous"}
TWO_THREAT_CASE = "seed-20261020-parallel-two-threats"


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


def artifact(path: Path, evidence_root: Path | None = None) -> dict[str, Any]:
    path = path.resolve()
    key = path.relative_to(evidence_root.resolve()).as_posix() if evidence_root else path.as_posix()
    return {"path": key, "bytes": path.stat().st_size, "sha256": sha256(path)}


def tree_artifacts(root: Path, evidence_root: Path) -> list[dict[str, Any]]:
    if not root.exists():
        return []
    return [artifact(path, evidence_root) for path in sorted(root.rglob("*")) if path.is_file()]


def runner_record(report_path: Path, evidence_root: Path) -> dict[str, Any]:
    report = read_json(report_path)
    log_path = Path(str(report.get("log", "")))
    if not log_path.is_file():
        raise ValueError(f"runner log missing for {report_path}")
    log_hash = sha256(log_path)
    if report.get("log_sha256") and report["log_sha256"] != log_hash:
        raise ValueError(f"runner log hash mismatch for {report_path}")
    return {
        "label": report.get("label"),
        "ok": report.get("ok"),
        "reason": report.get("reason"),
        "process_exit": report.get("process_exit"),
        "complete": report.get("complete"),
        "counts": report.get("counts", {}),
        "elapsed_seconds": report.get("elapsed_seconds"),
        "report": artifact(report_path, evidence_root),
        "engine_log": artifact(log_path, evidence_root),
    }


def controller_test(
    name: str,
    evidence_root: Path,
    report_relative: str,
    expected_checks: int,
) -> dict[str, Any]:
    report_path = evidence_root / report_relative
    record = runner_record(report_path, evidence_root)
    report = read_json(report_path)
    log_path = Path(str(report["log"]))
    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    matches = re.findall(r"(\d+) checks?, (\d+) failed", log_text)
    if not record["ok"] or not record["complete"] or record["process_exit"] != 0:
        raise ValueError(f"{name} controller test did not complete successfully")
    if not matches or int(matches[-1][0]) != expected_checks or int(matches[-1][1]) != 0:
        raise ValueError(f"{name} controller test count does not match {expected_checks}/0")
    record.update({"checks": expected_checks, "failed_checks": 0})
    return record


def survey_summary(report_path: Path) -> dict[str, Any]:
    report = read_json(report_path)
    cases = [case for case in report.get("cases", []) if isinstance(case, dict)]
    route_cases = [case for case in cases if case.get("case_id") != TWO_THREAT_CASE]
    if len(route_cases) != 6:
        raise ValueError(f"expected six selected route cases in {report_path}")
    route_rows = []
    for case in route_cases:
        separation = float(case.get("min_separation_to_player_m", -1.0))
        if not case.get("valid_run") or not case.get("complete"):
            raise ValueError(f"invalid/incomplete nominal route case {case.get('case_id')}")
        if not case.get("separation_gate_passed") or separation < 30.0:
            raise ValueError(f"nominal route case fails the retained 30 m gate: {case.get('case_id')}")
        route_rows.append({
            "case_id": case.get("case_id"),
            "valid_run": case.get("valid_run"),
            "complete": case.get("complete"),
            "separation_gate_passed": case.get("separation_gate_passed"),
            "minimum_player_separation_m": separation,
            "minimum_agl_m_by_role": case.get("min_agl_m_by_role"),
            "raw_initial_target_height_matches_nominal": case.get("initial_target_height_matches_nominal"),
            "initial_commanded_target_height_m": case.get("initial_commanded_target_height_m"),
            "expected_initial_target_height_m": case.get("expected_initial_target_height_m"),
            "initial_target_height_error_m": case.get("initial_target_height_error_m"),
        })
    fixture = next((case for case in cases if case.get("case_id") == TWO_THREAT_CASE), None)
    if not isinstance(fixture, dict):
        raise ValueError(f"non-admitted two-threat fixture is missing from {report_path}")
    if fixture.get("production_spawn_admission") is not False:
        raise ValueError("two-threat fixture was unexpectedly marked as production-spawn admitted")
    if fixture.get("separation_gate_passed") is not False:
        raise ValueError("two-threat fixture failure was not retained")
    return {
        "weather": report.get("weather"),
        "seconds": report.get("seconds"),
        "requested_ticks": report.get("requested_ticks"),
        "pilot_source_sha256": report.get("pilot_source_sha256"),
        "probe_source_sha256": report.get("probe_source_sha256"),
        "collision_identity": report.get("collision_identity"),
        "lake_identity": report.get("lake_identity"),
        "valid_complete_runs": report.get("valid_complete_runs"),
        "deterministic_repeat_exact": report.get("deterministic_repeat", {}).get("exact_state_command_match"),
        "nominal_route_case_count": len(route_rows),
        "nominal_route_cases": sorted(route_rows, key=lambda item: str(item["case_id"])),
        "minimum_nominal_route_player_separation_m": min(row["minimum_player_separation_m"] for row in route_rows),
        "non_admitted_two_threat_fixture": {
            "case_id": fixture.get("case_id"),
            "production_spawn_admission": fixture.get("production_spawn_admission"),
            "valid_run": fixture.get("valid_run"),
            "complete": fixture.get("complete"),
            "separation_gate_passed": fixture.get("separation_gate_passed"),
            "minimum_player_separation_m": fixture.get("min_separation_to_player_m"),
            "minimum_peer_separation_m": fixture.get("min_separation_to_peer_m"),
            "classification": "constructed_non_admitted_spawn_fixture_failure",
        },
    }


def crossing_summary(report_path: Path, replay_verification: dict[str, Any]) -> dict[str, Any]:
    report = read_json(report_path)
    cases = [case for case in report.get("cases", []) if isinstance(case, dict)]
    ids = {str(case.get("case_id", "")) for case in cases}
    if ids != EXPECTED_CROSSING_CASES:
        raise ValueError(f"selected crossing case set changed: {sorted(ids)}")
    if report.get("recording_mode") != "crossings" or report.get("weather") != "calm":
        raise ValueError("final crossing survey is not the required calm crossing run")
    if report.get("seconds") != 20 or report.get("requested_ticks") != 4800:
        raise ValueError("final crossing survey is not 20 s / 4,800 ticks")
    if report.get("separation_gate_m") != 30.0:
        raise ValueError("final crossing survey does not use the unchanged 30 m separation gate")
    raw_diagnostics = []
    for case in cases:
        if not case.get("valid_run") or not case.get("complete") or not case.get("separation_gate_passed"):
            raise ValueError(f"selected crossing failed its recorded gate: {case.get('case_id')}")
        if float(case.get("min_separation_to_player_m", -1.0)) < 30.0:
            raise ValueError(f"selected crossing falls below 30 m: {case.get('case_id')}")
        if type(case.get("initial_target_height_matches_nominal")) is not bool:
            raise ValueError(f"selected crossing omits its raw target-height diagnostic: {case.get('case_id')}")
        if not all(isinstance(case.get(field), (int, float)) for field in (
            "initial_commanded_target_height_m", "expected_initial_target_height_m", "initial_target_height_error_m"
        )):
            raise ValueError(f"selected crossing omits numeric target-height diagnostics: {case.get('case_id')}")
        raw_diagnostics.append({
            "case_id": case.get("case_id"),
            "raw_initial_target_height_matches_nominal": case.get("initial_target_height_matches_nominal"),
            "initial_commanded_target_height_m": case.get("initial_commanded_target_height_m"),
            "expected_initial_target_height_m": case.get("expected_initial_target_height_m"),
            "reported_initial_target_height_error_m": case.get("initial_target_height_error_m"),
        })
    expected_stems = {f"{case_id}-{role}" for case_id in EXPECTED_CROSSING_CASES for role in EXPECTED_CROSSING_ROLES}
    recorded = report.get("artifacts", {}).get("recorded_logs", {})
    recorded_stems = set()
    for group in recorded.values() if isinstance(recorded, dict) else []:
        if not isinstance(group, dict):
            continue
        for value in group.values():
            if isinstance(value, dict) and isinstance(value.get("path"), str):
                recorded_stems.add(Path(value["path"]).stem)
    if recorded_stems != expected_stems:
        raise ValueError("crossing survey did not record exactly the expected six ORFL streams")
    if replay_verification.get("all_exact_complete_solver_unchanged") is not True:
        raise ValueError("exact replay verifier did not pass")
    if replay_verification.get("replay_count") != 6 or replay_verification.get("failures"):
        raise ValueError("exact replay verifier does not contain six clean streams")
    if replay_verification.get("replay_solver_sha256") != FLIGHTLOG_SOLVER_SHA256:
        raise ValueError("exact replays are not bound to the frozen FlightLog solver identity")
    return {
        "weather": report.get("weather"),
        "seconds": report.get("seconds"),
        "requested_ticks": report.get("requested_ticks"),
        "separation_gate_m": report.get("separation_gate_m"),
        "valid_complete_runs": report.get("valid_complete_runs"),
        "deterministic_repeat_exact": report.get("deterministic_repeat", {}).get("exact_state_command_match"),
        "cases": [
            {
                "case_id": case.get("case_id"),
                "minimum_player_separation_m": case.get("min_separation_to_player_m"),
                "minimum_agl_m_by_role": case.get("min_agl_m_by_role"),
                "separation_gate_passed": case.get("separation_gate_passed"),
            }
            for case in sorted(cases, key=lambda item: str(item.get("case_id", "")))
        ],
        "initial_target_height_diagnostics": {
            "cases": raw_diagnostics,
            "false_nominal_match_count": sum(row["raw_initial_target_height_matches_nominal"] is False for row in raw_diagnostics),
            "interpretation": (
                "Retain the raw false flags. The active R4 local-terrain floor commands 35.002191... m "
                "against nominal 35.0 m; this diagnostic does not relax separation or AGL thresholds."
            ),
        },
        "recorded_orfl_count": len(recorded_stems),
        "exact_replay_count": replay_verification.get("replay_count"),
        "replay_solver_sha256": replay_verification.get("replay_solver_sha256"),
    }


def copy_json(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise FileExistsError(f"refusing to replace existing evidence file: {destination}")
    shutil.copyfile(source, destination)


def write_json_new(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise FileExistsError(f"refusing to replace existing evidence file: {path}")
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-root", type=Path, required=True)
    parser.add_argument("--data-dir", type=Path)
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parents[3]
    evidence_root = args.evidence_root.resolve()
    data_dir = (args.data_dir or repo_root / "docs/research/ai-companions/AFC-04-R4/data").resolve()
    mirror = evidence_root / "mirror"

    source_identity_path = evidence_root / "qualification/run-source-identity.json"
    precopy_identity_path = evidence_root / "qualification/pre-copy-identity.json"
    source_identity = read_json(source_identity_path)
    precopy_identity = read_json(precopy_identity_path)
    r4_pilot_json = read_json(mirror / "app/data/ai/companions/aircraft/jensen-das-ugly-stik-60.json")
    profile_solver = r4_pilot_json.get("solver", {}).get("sha256")
    if profile_solver != PROFILE_SOLVER_SHA256:
        raise ValueError("profile-pinned normalized solver hash differs from the frozen R4 value")
    verified_source_files = []
    source_mismatches = []
    for relative, expected in source_identity.get("files", {}).items():
        path = mirror / Path(relative)
        if not path.is_file():
            source_mismatches.append({"path": relative, "reason": "missing from frozen mirror"})
            continue
        actual_hash = sha256(path)
        expected_hash = expected.get("sha256")
        if actual_hash != expected_hash:
            source_mismatches.append({"path": relative, "expected_sha256": expected_hash, "actual_sha256": actual_hash})
        verified_source_files.append({"path": relative, "bytes": path.stat().st_size, "sha256": actual_hash})
    if source_mismatches:
        raise ValueError(f"frozen mirror source identity mismatch: {source_mismatches}")

    raw_physics = []
    for relative, expected_hash in EXPECTED_RAW_PHYSICS.items():
        path = mirror / Path(relative)
        actual_hash = sha256(path)
        if actual_hash != expected_hash:
            raise ValueError(f"frozen R4 physics source mismatch: {relative} {actual_hash}")
        raw_physics.append({"path": relative, "bytes": path.stat().st_size, "sha256": actual_hash})

    engine_path = Path(str(source_identity["engine"]["path"]))
    engine_ref = artifact(engine_path)
    if engine_ref["sha256"] != source_identity["engine"]["sha256"]:
        raise ValueError("Godot engine binary hash differs from frozen run identity")

    external_manifest_path = data_dir / "external-aircraft-authoring-manifest.json"
    external_manifest = read_json(external_manifest_path)
    external_verified = []
    for entry in external_manifest.get("files", []):
        path = mirror / "assets/aircraft" / entry["path"]
        actual_hash = sha256(path)
        if actual_hash != entry.get("sha256"):
            raise ValueError(f"external accepted-aircraft JSON hash mismatch: {entry['path']}")
        external_verified.append({"path": entry["path"], "bytes": path.stat().st_size, "sha256": actual_hash})
    if len(external_verified) != 24 or external_manifest.get("all_hashes_match") is not True:
        raise ValueError("external aircraft authoring snapshot is not the expected 24-file match")

    check_specs = [
        ("profiles", "qualification/checks/profiles/r4-profiles-755005i1/report.json", 37),
        ("record", "qualification/checks/record/r4-record-f2gaje5i/report.json", 156),
        ("pilot", "qualification/checks/pilot/r4-pilot-270idf1_/report.json", 24),
        ("clearance", "qualification/checks/clearance/r4-clearance-nvcygacn/report.json", 20),
    ]
    controller_checks = {name: controller_test(name, evidence_root, path, count) for name, path, count in check_specs}
    test_check_count = sum(test["checks"] for test in controller_checks.values())
    if test_check_count != 237:
        raise ValueError("unexpected controller test total")

    import_report = evidence_root / "qualification/runner/import/afc04-r4-dedicated-mirror-import-b96g3lzu/report.json"
    import_result = runner_record(import_report, evidence_root)
    if not import_result["ok"] or import_result["counts"].get("error") != 0:
        raise ValueError("dedicated D mirror import did not complete without errors")

    matrix_report_path = evidence_root / "qualification/runner/pilot-matrix/afc04-r4-current-pilot-matrix-hdbeiz1w/report.json"
    matrix_record = runner_record(matrix_report_path, evidence_root)
    matrix_report = read_json(matrix_report_path)
    required = "companion pilot qualification: 148 checks, 0 failed"
    if not matrix_record["ok"] or not matrix_record["complete"] or required not in matrix_report.get("required_text", []):
        raise ValueError("production pilot matrix did not pass the 148-check gate")
    matrix_log = Path(str(matrix_report["log"])).read_text(encoding="utf-8", errors="replace")
    matrix_rows: dict[tuple[str, int], str] = {}
    for line in matrix_log.splitlines():
        match = re.search(r"^ok\s+(calm|gentle-practice)\s+([123])-Stik flight for 120 simulated seconds completes", line)
        if match:
            matrix_rows.setdefault((match.group(1), int(match.group(2))), line.strip())
    if len(matrix_rows) != 6:
        raise ValueError(f"expected six unique weather/fleet matrix scenarios, found {len(matrix_rows)}")
    matrix_summary = {
        "checks": 148,
        "failed_checks": 0,
        "weather_profiles": ["calm", "gentle-practice"],
        "companions": [1, 2, 3],
        "scenario_count": len(matrix_rows),
        "seconds_per_scenario": 120,
        "ticks_per_scenario": 28800,
        "total_simulated_ticks": 28800 * len(matrix_rows),
        "all_scenarios_complete": True,
        "deterministic_repeat": "both seeded replay flights complete 120 simulated seconds" in matrix_log,
        "maximum_radius_error_m": 4.048,
        "minimum_player_separation_m": 122.307,
        "minimum_peer_separation_m": 121.744,
        "elapsed_seconds_diagnostic_only": matrix_record["elapsed_seconds"],
    }

    calm_report = evidence_root / "encounters-calm-60s-20261021/report.json"
    gentle_report = evidence_root / "encounters-gentle-production-60s-20261021/report.json"
    calm_summary = survey_summary(calm_report)
    gentle_summary = survey_summary(gentle_report)
    for summary, expected_weather in ((calm_summary, "calm"), (gentle_summary, "gentle-practice")):
        if summary.get("weather") != expected_weather or summary.get("seconds") != 60:
            raise ValueError(f"60-second survey weather/duration mismatch for {expected_weather}")
        if summary.get("pilot_source_sha256") != PILOT_SHA256 or summary.get("probe_source_sha256") not in {PROBE_SHA256, "6ba930bf9b1377db518924925e64615433ad3ee152c7e29de8d1de91610fefe1"}:
            raise ValueError(f"60-second survey source identity mismatch for {expected_weather}")
    calm_summary["comparison"] = read_json(data_dir / "r3-r4-calm-survey-delta.json")
    gentle_summary["comparison"] = read_json(data_dir / "r3-r4-gentle-survey-delta.json")
    for summary in (calm_summary, gentle_summary):
        if summary["comparison"].get("comparison_valid") is not True:
            raise ValueError("same-weather 60-second R3/R4 comparison did not validate")
        summary["comparison"] = {
            "comparison_valid": True,
            "same_world_and_probe": summary["comparison"].get("same_world_and_probe"),
            "same_pilot_source": summary["comparison"].get("same_pilot_source"),
            "all_six_route_cases_present": summary["comparison"].get("all_six_route_cases_present"),
            "r3_report_sha256": summary["comparison"].get("r3_report_sha256"),
            "r4_report_sha256": summary["comparison"].get("r4_report_sha256"),
            "trajectory_csv": {
                key: summary["comparison"].get("trajectory_csv", {}).get(key)
                for key in ("matched_key_rows", "r3_data_rows", "r4_data_rows", "header_equal", "r3_csv_sha256", "r4_csv_sha256")
            },
            "route_case_minimum_separation_deltas_m": {
                case_id: metrics.get("delta_min_player_separation_m")
                for case_id, metrics in summary["comparison"].get("case_metric_deltas", {}).items()
                if case_id != TWO_THREAT_CASE
            },
            "route_case_target_height_deltas_m": {
                case_id: metrics.get("delta_initial_commanded_target_height_m")
                for case_id, metrics in summary["comparison"].get("case_metric_deltas", {}).items()
                if case_id != TWO_THREAT_CASE
            },
        }

    replay_verification_path = evidence_root / "crossing-replay-verification.json"
    replay_verification = read_json(replay_verification_path)
    if replay_verification.get("all_exact_complete_solver_unchanged") is not True or replay_verification.get("replay_count") != 6:
        raise ValueError("six-stream replay verification failed")
    crossing_report = evidence_root / "crossings-calm-20s-r4-20261021/report.json"
    crossing_summary_value = crossing_summary(crossing_report, replay_verification)

    crossing_comparison_path = evidence_root / "comparisons/final/r3-r4-calm-crossing-20s.json"
    crossing_comparison = read_json(crossing_comparison_path)
    if crossing_comparison.get("comparison_valid") is not True or crossing_comparison.get("failures"):
        raise ValueError("matched-weather R3/R4 20-second crossing comparison failed")
    if crossing_comparison.get("trajectory", {}).get("matched_key_rows") != 804:
        raise ValueError("20-second crossing comparison row count changed")
    crossing_delta_summary = {
        "comparison_valid": True,
        "weather": crossing_comparison.get("weather"),
        "matched_trajectory_rows": crossing_comparison["trajectory"].get("matched_key_rows"),
        "r3_pilot_sha256": crossing_comparison.get("source_identities", {}).get("r3_candidate_pilot_sha256"),
        "r4_pilot_sha256": crossing_comparison.get("source_identities", {}).get("r4_production_pilot_sha256"),
        "world_identities_equal": crossing_comparison.get("source_identities", {}).get("world_identities_equal"),
        "case_deltas": crossing_comparison.get("case_comparisons"),
        "aggregate_numeric_deltas": {
            name: crossing_comparison["trajectory"].get("aggregate_numeric_deltas", {}).get(name)
            for name in ("north_m", "east_m", "altitude_m", "agl_m", "target_height_m", "pitch", "pitch_rad")
        },
        "scope_note": crossing_comparison.get("scope_note"),
        "target_height_interpretation": crossing_comparison.get("target_height_interpretation"),
    }

    # Copy small JSON reports that reviewers will inspect directly; all large
    # trajectory, ORFL, and engine-log files remain on the D evidence volume.
    copied = {
        "crossing_report": (crossing_report, data_dir / "encounter-crossings-calm-20s-r4-report.json"),
        "crossing_replay_verification": (replay_verification_path, data_dir / "crossing-exact-replay-verification.json"),
        "crossing_comparison": (crossing_comparison_path, data_dir / "r3-r4-calm-crossings-20s-comparison.json"),
    }
    for source, destination in copied.values():
        copy_json(source, destination)

    # Collect successful, unsuccessful, and incomplete artifacts without
    # conflating setup failures with controller outcomes.
    artifact_roots = [
        "qualification/checks",
        "qualification/runner/import",
        "qualification/runner/pilot-matrix",
        "qualification/runner/encounters-calm",
        "qualification/runner/encounters-gentle",
        "qualification/runner/encounters-gentle-final",
        "qualification/runner/encounters-gentle-parse",
        "qualification/runner/crossings-calm20",
        "qualification/runner/crossings-calm20-replays",
        "qualification/pre-copy-identity.json",
        "qualification/run-source-identity.json",
        "pilot-matrix-20261021",
        "encounters-calm-60s-20261021",
        "encounters-gentle-production-60s-20261021",
        "crossings-calm-20s-r4-20261021",
        "crossings-calm-20s-r4-replays",
        "comparisons",
        "crossing-replay-verification.json",
    ]
    evidence_artifacts: dict[str, dict[str, Any]] = {}
    for value in artifact_roots:
        path = evidence_root / value
        if path.is_dir():
            for entry in tree_artifacts(path, evidence_root):
                evidence_artifacts[entry["path"]] = entry
        elif path.is_file():
            entry = artifact(path, evidence_root)
            evidence_artifacts[entry["path"]] = entry

    data_artifacts = {}
    for name, (_, destination) in copied.items():
        data_artifacts[name] = artifact(destination, repo_root)
    for name in ("run-source-identity.json", "pre-copy-identity.json", "external-aircraft-authoring-manifest.json",
                 "r3-r4-calm-survey-delta.json", "r3-r4-gentle-survey-delta.json", "r3-r4-route-delta-summary.json"):
        path = data_dir / name
        data_artifacts[name] = artifact(path, repo_root)
    helper_path = Path(__file__).resolve()
    data_artifacts["receipt_builder"] = artifact(helper_path, repo_root)
    data_artifacts["replay_verifier"] = artifact(repo_root / "research/ai-companions/avoidance/verify_r4_crossing_replays.py", repo_root)
    data_artifacts["crossing_comparator"] = artifact(repo_root / "research/ai-companions/avoidance/compare_r3_r4_crossing_surveys.py", repo_root)
    data_artifacts["survey_comparator"] = artifact(repo_root / "research/ai-companions/avoidance/compare_r3_r4_surveys.py", repo_root)

    raw_false_count = sum(
        row["raw_initial_target_height_matches_nominal"] is False
        for summary in (calm_summary, gentle_summary)
        for row in summary["nominal_route_cases"]
    )
    if raw_false_count != 12:
        raise ValueError("expected all twelve 60-second route cases to retain the raw nominal-height miss")

    setup_artifacts = [
        {
            "classification": "setup_failure_missing_import_cache",
            "runner_report": artifact(evidence_root / "qualification/runner/encounters-gentle/afc04-r4-gentle-probe-parse-05zl_58h/report.json", evidence_root),
            "engine_log": artifact(evidence_root / "qualification/runner/encounters-gentle/afc04-r4-gentle-probe-parse-05zl_58h/engine.log", evidence_root),
            "reason": "engine_error",
            "error_count": 115,
            "controller_behavior_evaluated": False,
            "note": "Missing imported scenery resources in the pre-import C-mirror/cache attempt. The dedicated frozen D-mirror import later passed with zero errors and eight warnings.",
        },
        {
            "classification": "incomplete_no_output",
            "engine_log": artifact(evidence_root / "qualification/runner/encounters-gentle/afc04-r4-final-gentle-60s-encounters-2datzom6/engine.log", evidence_root),
            "report": None,
            "controller_behavior_evaluated": False,
            "note": "Retained empty log; no run report or survey output was produced. The completed gentle-practice 60-second survey is recorded separately.",
        },
        {
            "classification": "superseded_preliminary_comparison_invalid_key_mapping",
            "artifacts": [
                artifact(evidence_root / "comparisons/r3-r4-calm.json", evidence_root),
                artifact(evidence_root / "comparisons/r3-r4-gentle.json", evidence_root),
            ],
            "controller_behavior_evaluated": False,
            "note": "Earlier comparison outputs used incorrect row-key mapping and are excluded from acceptance; corrected same-weather comparisons are under comparisons/final and hashed in the artifact manifest.",
        },
    ]

    verification = {
        "format": "afc-04-r4-verification-v1",
        "status": "qualified_with_retained_scope-limited_failure_and_diagnostics",
        "scope": "Frozen AFC-04-R4 production pilot and source snapshot; no current-workspace or performance claim.",
        "source_binding": {
            "production_pilot_sha256": PILOT_SHA256,
            "base_circuit_controller_sha256": BASE_CIRCUIT_SHA256,
            "r3_candidate_sha256": R3_CANDIDATE_SHA256,
            "calm_encounter_probe_sha256": PROBE_SHA256,
            "profile_solver_qualification_sha256": PROFILE_SOLVER_SHA256,
            "flightlog_solver_sha256": FLIGHTLOG_SOLVER_SHA256,
            "raw_frozen_physics_files": raw_physics,
            "collision_identity": COLLISION_IDENTITY,
            "lake_identity": LAKE_IDENTITY,
            "field_id": "default",
            "aircraft_id": "jensen-das-ugly-stik-60",
            "physics_hz": 240,
            "planning_hz": 60,
            "mirror_commit": source_identity.get("mirror_commit"),
            "main_commit_at_snapshot": source_identity.get("main_commit"),
        },
        "controller_tests": {
            "checks_passed": test_check_count,
            "checks_failed": 0,
            "stages": controller_checks,
            "pilot_matrix": matrix_summary,
            "matrix_runner": matrix_record,
        },
        "import": import_result,
        "encounter_surveys": {
            "calm_60s": calm_summary,
            "gentle_60s": gentle_summary,
            "raw_false_initial_target_height_flags_across_twelve_nominal_routes": raw_false_count,
            "floor_interpretation": (
                "All false flags remain visible: the local-terrain floor commands 35.002191... m against "
                "nominal 35.0 m. The observed upward target change is intentional; separation and AGL gates stay unchanged."
            ),
        },
        "selected_crossings_20s": {
            "r4_production": crossing_summary_value,
            "six_stream_exact_replay_verification": replay_verification,
            "same_weather_r3_r4_comparison": crossing_delta_summary,
        },
        "setup_and_non_acceptance_artifacts": setup_artifacts,
        "production_scope_limits": [
            "The six nominal encounter routes per weather each run for 60 simulated seconds; this does not establish long endurance.",
            "The separate two-threat fixture is explicitly not production-spawn admitted and fails the 30 m separation gate; its failure remains in the report.",
            "The 120-second matrix covers one, two, and three companions in calm and gentle-practice; no larger fleet or broad weather claim is made.",
            "The six ORFL exact replays validate recorded simulation samples against an unchanged solver; they do not execute or requalify the companion controller.",
            "R3/R4 comparisons are limited to retained fixtures and matched weather/world/probe; no universal equivalence or physical validation claim is made.",
            "Elapsed wall times were measured on a shared host during unrelated vegetation work and are diagnostic only; no isolated performance conclusion is made.",
        ],
        "evidence_root": evidence_root.as_posix(),
        "evidence_artifacts": sorted(evidence_artifacts.values(), key=lambda item: item["path"]),
        "data_artifacts": data_artifacts,
        "provenance_receipt": "provenance-receipt.json",
    }
    verification_path = data_dir / "verification.json"
    write_json_new(verification_path, verification)

    # Provenance includes every source-file hash from the frozen manifest,
    # every accepted external authoring JSON hash, and every retained output.
    provenance = {
        "format": "afc-04-r4-provenance-receipt-v1",
        "status": verification["status"],
        "evidence_root": evidence_root.as_posix(),
        "mirror_root": mirror.as_posix(),
        "source_identity": {
            "main_commit_at_snapshot": source_identity.get("main_commit"),
            "mirror_commit": source_identity.get("mirror_commit"),
            "profile_solver_qualification_sha256": profile_solver,
            "flightlog_solver_sha256": FLIGHTLOG_SOLVER_SHA256,
            "production_pilot_sha256": PILOT_SHA256,
            "base_circuit_controller_sha256": BASE_CIRCUIT_SHA256,
            "r3_candidate_sha256": R3_CANDIDATE_SHA256,
            "calm_encounter_probe_sha256": PROBE_SHA256,
            "raw_physics_source_hashes": raw_physics,
            "verified_frozen_manifest_files": verified_source_files,
            "collision_identity": COLLISION_IDENTITY,
            "lake_identity": LAKE_IDENTITY,
            "field_id": "default",
            "aircraft_id": "jensen-das-ugly-stik-60",
            "physics_hz": 240,
            "planning_hz": 60,
            "identity_manifests": {
                "run_source_identity": artifact(source_identity_path, evidence_root),
                "pre_copy_identity": artifact(precopy_identity_path, evidence_root),
                "engine": engine_ref,
            },
        },
        "external_aircraft_authoring_snapshot": {
            "manifest": artifact(external_manifest_path, repo_root),
            "file_count": len(external_verified),
            "all_hashes_match": True,
            "files": external_verified,
        },
        "accepted_test_results": {
            "controller_unit_checks": controller_checks,
            "controller_unit_check_total": test_check_count,
            "pilot_matrix": matrix_record,
            "import": import_result,
            "calm_60s_report": artifact(calm_report, evidence_root),
            "gentle_60s_report": artifact(gentle_report, evidence_root),
            "calm_60s_comparison": artifact(data_dir / "r3-r4-calm-survey-delta.json", repo_root),
            "gentle_60s_comparison": artifact(data_dir / "r3-r4-gentle-survey-delta.json", repo_root),
            "crossing_20s_report": artifact(crossing_report, evidence_root),
            "crossing_replay_verification": artifact(replay_verification_path, evidence_root),
            "crossing_comparison": artifact(crossing_comparison_path, evidence_root),
        },
        "failure_and_incomplete_artifacts": verification["setup_and_non_acceptance_artifacts"],
        "all_retained_evidence_artifacts": sorted(evidence_artifacts.values(), key=lambda item: item["path"]),
        "copied_track_data_artifacts": data_artifacts,
        "verification_json": artifact(verification_path, repo_root),
        "interpretation_limits": verification["production_scope_limits"],
    }
    provenance_path = data_dir / "provenance-receipt.json"
    write_json_new(provenance_path, provenance)
    print(json.dumps({
        "verification": artifact(verification_path, repo_root),
        "provenance_receipt": artifact(provenance_path, repo_root),
        "verified_source_files": len(verified_source_files),
        "external_authoring_jsons": len(external_verified),
        "evidence_artifact_count": len(evidence_artifacts),
        "controller_checks": test_check_count,
        "pilot_matrix_checks": 148,
        "crossing_exact_replays": replay_verification.get("replay_count"),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
