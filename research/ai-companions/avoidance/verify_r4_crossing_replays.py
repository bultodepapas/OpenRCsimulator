#!/usr/bin/env python3
"""Verify every exact replay from one AFC-04-R4 selected-crossing survey."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
from typing import Any


EXPECTED_CASES = {
    "seed-20261020-crossing-right",
    "seed-20261021-crossing-left",
}
EXPECTED_ROLES = {"ai", "player-coupled", "player-exogenous"}
EXPECTED_ROWS = 4801
EXPECTED_PILOT_SHA256 = "363942b4b7d67f85333233f0c6000890ca984e5b76a8ccabe7973f70218259ed"
EXPECTED_PROBE_SHA256 = "d00004590c5793ba743f56b3d129a248d35fa085186e576d33f0ac9a2e832cc4"
EXPECTED_COLLISION_IDENTITY = "fb2be395cc783b3910f5eb2c5fcdef4936c36ea90bd8d25466d818f2b89743ae"
EXPECTED_LAKE_IDENTITY = "bcc3774dc2ef339bac49aaec42b6a47b6b6d1104470d9fff35db242f6ab61efa"


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


def count_csv_rows(path: Path) -> int:
    with path.open("r", encoding="utf-8", newline="") as stream:
        rows = csv.reader(stream)
        next(rows, None)  # Header.
        return sum(1 for _ in rows)


def verify(survey_dir: Path, replay_root: Path) -> dict[str, Any]:
    survey_dir = survey_dir.resolve()
    replay_root = replay_root.resolve()
    survey_path = survey_dir / "report.json"
    survey = read_json(survey_path)
    failures: list[str] = []
    pilot_hash = str(survey.get("pilot_source_sha256", ""))
    probe_hash = str(survey.get("probe_source_sha256", ""))

    if survey.get("recording_mode") != "crossings":
        failures.append("survey recording mode is not crossings")
    if survey.get("seconds") != 20 or survey.get("requested_ticks") != 4800:
        failures.append("survey is not the bounded 20-second crossing run")
    if survey.get("separation_gate_m") != 30.0:
        failures.append("survey separation gate is not the retained 30 m threshold")
    if not survey.get("valid_complete_runs", False):
        failures.append("survey includes an invalid or incomplete run")
    if not survey.get("deterministic_repeat", {}).get("exact_state_command_match", False):
        failures.append("survey deterministic repeat is not exact")
    if len(pilot_hash) != 64 or len(probe_hash) != 64:
        failures.append("pilot or probe SHA-256 is missing")
    if pilot_hash != EXPECTED_PILOT_SHA256:
        failures.append("survey pilot source does not match the frozen AFC-04-R4 pilot")
    if probe_hash != EXPECTED_PROBE_SHA256:
        failures.append("survey probe source does not match the retained calm encounter probe")
    if survey.get("weather") != "calm":
        failures.append("20-second crossing survey is not in calm weather")
    if survey.get("collision_identity") != EXPECTED_COLLISION_IDENTITY:
        failures.append("survey collision-world identity differs from the frozen fixture")
    if survey.get("lake_identity") != EXPECTED_LAKE_IDENTITY:
        failures.append("survey lake identity differs from the frozen fixture")

    cases = survey.get("cases", [])
    case_ids = {str(case.get("case_id", "")) for case in cases if isinstance(case, dict)}
    if case_ids != EXPECTED_CASES:
        failures.append(f"selected crossing cases differ from expected set: {sorted(case_ids)}")
    case_status: dict[str, dict[str, Any]] = {}
    target_height_diagnostics: list[dict[str, Any]] = []
    for case in cases:
        if not isinstance(case, dict):
            failures.append("survey contains a malformed case record")
            continue
        case_id = str(case.get("case_id", "unknown"))
        case_status[case_id] = {
            "valid_run": case.get("valid_run"),
            "complete": case.get("complete"),
            "separation_gate_passed": case.get("separation_gate_passed"),
            "min_separation_to_player_m": case.get("min_separation_to_player_m"),
            "min_agl_m_by_role": case.get("min_agl_m_by_role"),
            "initial_target_height_matches_nominal": case.get("initial_target_height_matches_nominal"),
            "initial_commanded_target_height_m": case.get("initial_commanded_target_height_m"),
            "expected_initial_target_height_m": case.get("expected_initial_target_height_m"),
            "initial_target_height_error_m": case.get("initial_target_height_error_m"),
        }
        if not case.get("valid_run") or not case.get("complete"):
            failures.append(f"{case_id} controller encounter is invalid or incomplete")
        if not case.get("separation_gate_passed"):
            failures.append(f"{case_id} does not pass the reported player-separation gate")
        min_separation = case.get("min_separation_to_player_m")
        if type(min_separation) not in (int, float) or float(min_separation) < 30.0:
            failures.append(f"{case_id} minimum player separation is below the unchanged 30 m gate")
        nominal_match = case.get("initial_target_height_matches_nominal")
        commanded_height = case.get("initial_commanded_target_height_m")
        expected_height = case.get("expected_initial_target_height_m")
        height_error = case.get("initial_target_height_error_m")
        if type(nominal_match) is not bool:
            failures.append(f"{case_id} omits the initial-target nominal-match diagnostic")
        if not all(isinstance(value, (int, float)) for value in (commanded_height, expected_height, height_error)):
            failures.append(f"{case_id} omits numeric initial-target height diagnostics")
        else:
            target_height_diagnostics.append({
                "case_id": case_id,
                "raw_initial_target_height_matches_nominal": nominal_match,
                "commanded_initial_target_height_m": commanded_height,
                "expected_initial_target_height_m": expected_height,
                "reported_error_m": height_error,
                "observed_delta_commanded_minus_nominal_m": float(commanded_height) - float(expected_height),
                "classification": (
                    "intentional_floor_diagnostic_miss"
                    if nominal_match is False
                    else "nominal_target_match"
                ),
            })
        exogenous = case.get("exogenous_player", {})
        if not isinstance(exogenous, dict) or not exogenous.get("valid_run") or not exogenous.get("complete"):
            failures.append(f"{case_id} exogenous player run is invalid or incomplete")
        if isinstance(exogenous, dict) and not exogenous.get("initial_spawn_matches_coupled_spec"):
            failures.append(f"{case_id} exogenous player spawn differs from the coupled spawn")

    expected_stems = {
        f"{case_id}-{role}"
        for case_id in EXPECTED_CASES
        for role in EXPECTED_ROLES
    }
    logs = sorted(survey_dir.glob("*.orfl"))
    log_by_stem = {path.stem: path for path in logs}
    if set(log_by_stem) != expected_stems:
        failures.append(
            f"recorded ORFL set differs from expected six: "
            f"missing={sorted(expected_stems - set(log_by_stem))}, "
            f"extra={sorted(set(log_by_stem) - expected_stems)}"
        )

    recorded = survey.get("artifacts", {}).get("recorded_logs", {})
    recorded_by_stem: dict[str, dict[str, Any]] = {}
    if isinstance(recorded, dict):
        for group in recorded.values():
            if not isinstance(group, dict):
                continue
            for artifact in group.values():
                if isinstance(artifact, dict) and isinstance(artifact.get("path"), str):
                    recorded_by_stem[Path(artifact["path"]).stem] = artifact

    replays: dict[str, dict[str, Any]] = {}
    for stem in sorted(expected_stems):
        log = log_by_stem.get(stem)
        if log is None:
            continue
        log_hash = sha256(log)
        manifest_entry = recorded_by_stem.get(stem, {})
        if Path(str(manifest_entry.get("path", ""))).resolve() != log:
            failures.append(f"{stem} path does not match the survey's recorded-log manifest")
        if manifest_entry.get("sha256") != log_hash:
            failures.append(f"{stem} hash does not match the survey's recorded-log manifest")

        replay_dir = replay_root / stem
        replay_path = replay_dir / "replay.json"
        csv_path = replay_dir / "flight.csv"
        if not replay_path.is_file() or not csv_path.is_file():
            failures.append(f"{stem} exact replay artifacts are missing")
            continue
        replay = read_json(replay_path)
        if replay.get("status") != "ok" or replay.get("mode") != "exact":
            failures.append(f"{stem} did not complete in exact mode")
        if replay.get("complete") is not True or replay.get("solver_changed") is not False:
            failures.append(f"{stem} replay is incomplete or solver identity changed")
        if replay.get("rows") != EXPECTED_ROWS:
            failures.append(f"{stem} replay row count is not {EXPECTED_ROWS}")
        if count_csv_rows(csv_path) != replay.get("rows"):
            failures.append(f"{stem} replay CSV row count differs from the report")
        if replay.get("source_sha256") != log_hash:
            failures.append(f"{stem} replay source hash differs from the ORFL")
        baseline_solver = replay.get("baseline_solver_sha256")
        current_solver = replay.get("current_solver_sha256")
        if not baseline_solver or baseline_solver != current_solver:
            failures.append(f"{stem} baseline and replay solver hashes differ")
        replays[stem] = {
            "orfl": str(log),
            "orfl_sha256": log_hash,
            "replay_json": str(replay_path),
            "replay_json_sha256": sha256(replay_path),
            "flight_csv": str(csv_path),
            "flight_csv_sha256": sha256(csv_path),
            "csv_rows": count_csv_rows(csv_path),
            "status": replay.get("status"),
            "mode": replay.get("mode"),
            "complete": replay.get("complete"),
            "solver_changed": replay.get("solver_changed"),
            "baseline_solver_sha256": baseline_solver,
            "current_solver_sha256": current_solver,
            "rows": replay.get("rows"),
            "source_sha256": replay.get("source_sha256"),
        }

    replay_solver_hashes = {
        str(item["current_solver_sha256"])
        for item in replays.values()
        if item.get("current_solver_sha256")
    }
    if len(replay_solver_hashes) != 1:
        failures.append("exact replays do not share one frozen solver fingerprint")

    exact_passed = len(replays) == len(expected_stems) and not failures
    return {
        "format": "afc-04-r4-crossing-exact-replay-verification-v1",
        "survey_report": str(survey_path),
        "survey_report_sha256": sha256(survey_path),
        "pilot_source_sha256": pilot_hash,
        "probe_source_sha256": probe_hash,
        "weather": survey.get("weather"),
        "collision_identity": survey.get("collision_identity"),
        "lake_identity": survey.get("lake_identity"),
        "survey_case_status": case_status,
        "initial_target_height_diagnostics": {
            "cases": target_height_diagnostics,
            "raw_false_flag_count": sum(
                item["raw_initial_target_height_matches_nominal"] is False
                for item in target_height_diagnostics
            ),
            "acceptance_note": (
                "A false nominal-match flag is retained as a diagnostic miss. The R4 local-terrain "
                "clearance floor intentionally raises the active target above the nominal 35 m; "
                "this is reported separately and does not relax separation or AGL gates."
            ),
        },
        "replay_solver_sha256": next(iter(replay_solver_hashes), None),
        "expected_orfl_count": len(expected_stems),
        "replay_count": len(replays),
        "all_exact_complete_solver_unchanged": exact_passed,
        "failures": failures,
        "replays": replays,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--survey-dir", type=Path, required=True)
    parser.add_argument("--replays", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    output = args.out.expanduser().resolve()
    if output.exists():
        parser.error("output path must be new")
    result = verify(args.survey_dir, args.replays)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(result, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps({
        "out": str(output),
        "replay_count": result["replay_count"],
        "all_exact": result["all_exact_complete_solver_unchanged"],
        "failures": result["failures"],
    }, sort_keys=True))
    return 0 if result["all_exact_complete_solver_unchanged"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
