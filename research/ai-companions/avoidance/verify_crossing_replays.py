#!/usr/bin/env python3
"""Verify complete exact replays and unchanged player tapes for AFC crossings."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def verify(baseline_dir: Path, candidate_dir: Path, replay_root: Path) -> dict[str, Any]:
    records = {"baseline": baseline_dir, "candidate": candidate_dir}
    recorded: dict[str, dict[str, Any]] = {}
    replayed: dict[str, dict[str, Any]] = {}
    failures: list[str] = []
    for label, run_dir in records.items():
        run_report = read_json(run_dir / "report.json")
        if not run_report.get("valid_complete_runs", False):
            failures.append(f"{label} encounter report is not valid and complete")
        if not run_report.get("deterministic_repeat", {}).get("exact_state_command_match", False):
            failures.append(f"{label} recorded crossing repeat is not exact")
        for log in sorted(run_dir.glob("*.orfl")):
            stem = log.stem
            replay_dir = replay_root / f"{label}-{stem}"
            replay = read_json(replay_dir / "replay.json")
            csv_path = replay_dir / "flight.csv"
            expected_log_hash = sha256(log)
            if replay.get("status") != "ok" or replay.get("mode") != "exact":
                failures.append(f"{label}/{stem} did not pass exact replay")
            if replay.get("complete") is not True or replay.get("solver_changed") is not False:
                failures.append(f"{label}/{stem} replay is incomplete or solver changed")
            if int(replay.get("rows", -1)) != 4801:
                failures.append(f"{label}/{stem} replay row count is not 4,801")
            if replay.get("source_sha256") != expected_log_hash:
                failures.append(f"{label}/{stem} replay source hash differs from ORFL")
            recorded[f"{label}/{stem}"] = {
                "orfl": str(log.resolve()),
                "orfl_sha256": expected_log_hash,
                "survey_pilot_sha256": run_report.get("pilot_source_sha256", ""),
                "survey_probe_sha256": run_report.get("probe_source_sha256", ""),
            }
            replayed[f"{label}/{stem}"] = {
                "replay_json": str((replay_dir / "replay.json").resolve()),
                "status": replay.get("status"),
                "mode": replay.get("mode"),
                "complete": replay.get("complete"),
                "solver_changed": replay.get("solver_changed"),
                "rows": replay.get("rows"),
                "source_sha256": replay.get("source_sha256"),
                "flight_csv": str(csv_path.resolve()),
                "flight_csv_sha256": sha256(csv_path),
                "solver_sha256": replay.get("current_solver_sha256"),
            }

    parity: dict[str, Any] = {}
    case_ids = ("seed-20261020-crossing-right", "seed-20261021-crossing-left")
    roles = ("player-coupled", "player-exogenous")
    for case_id in case_ids:
        base_case = next(item for item in read_json(baseline_dir / "report.json")["cases"]
                         if item["case_id"] == case_id)
        candidate_case = next(item for item in read_json(candidate_dir / "report.json")["cases"]
                              if item["case_id"] == case_id)
        if base_case.get("player_initial_spawn_spec") != candidate_case.get("player_initial_spawn_spec"):
            failures.append(f"{case_id} baseline/candidate player spawn specs differ")
        for role in roles:
            base_replay = replayed[f"baseline/{case_id}-{role}"]
            candidate_replay = replayed[f"candidate/{case_id}-{role}"]
            byte_equal = base_replay["flight_csv_sha256"] == candidate_replay["flight_csv_sha256"]
            if not byte_equal:
                failures.append(f"{case_id} {role} baseline/candidate flight CSV differs")
            parity[f"{case_id}/{role}"] = {
                "baseline_csv_sha256": base_replay["flight_csv_sha256"],
                "candidate_csv_sha256": candidate_replay["flight_csv_sha256"],
                "byte_identical": byte_equal,
                "same_player_spawn_spec": base_case.get("player_initial_spawn_spec")
                == candidate_case.get("player_initial_spawn_spec"),
            }
    return {
        "format": "afc-crossing-replay-verification-v1",
        "baseline_report": str((baseline_dir / "report.json").resolve()),
        "baseline_report_sha256": sha256(baseline_dir / "report.json"),
        "candidate_report": str((candidate_dir / "report.json").resolve()),
        "candidate_report_sha256": sha256(candidate_dir / "report.json"),
        "replay_count": len(replayed),
        "all_exact_complete_solver_unchanged": len(replayed) == 12 and not failures,
        "player_tape_parity": parity,
        "recorded_logs": recorded,
        "exact_replays": replayed,
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--replays", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error("output path must be new")
    result = verify(args.baseline, args.candidate, args.replays)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"out": str(args.out.resolve()), "replay_count": result["replay_count"],
                      "all_exact": result["all_exact_complete_solver_unchanged"],
                      "failures": result["failures"]}, sort_keys=True))
    return 0 if result["all_exact_complete_solver_unchanged"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
