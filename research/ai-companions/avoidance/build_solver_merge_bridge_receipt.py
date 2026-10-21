#!/usr/bin/env python3
"""Build the AFC-02 2f4 solver-merge bridge receipt from retained evidence."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
from typing import Any


REPOSITORY = Path(__file__).resolve().parents[3]
EVIDENCE = Path(r"D:\OpenRCsimulator-AFC-work\evidence\avoidance\solver-merge-bridge-20261021")
R4_EVIDENCE = Path(r"D:\OpenRCsimulator-AFC-work\evidence\avoidance\AFC-04-R4")
R4_APP = R4_EVIDENCE / "mirror" / "app"
ISOLATED_APP = EVIDENCE / "isolated-merged" / "app"
BASE_IDENTITY = "1526c98431a7dee5206eb992e10f40e436a7ef80d173e8c1dbfe6f1ad8f33b7e"
MERGED_IDENTITY = "2f4f35c04c837e89c5317412991046cd097dd3c9f501e9697702e94a6cff4bfa"
BASE_FLIGHT_LOG_ID = "21c675a567d7a28a07c2e417fd12581ea7346cf2423cb9d839f1de4f24af46c3"
MERGED_FLIGHT_LOG_ID = "8213b759c5bd746369c57cb76bfa38f21f004532bcf4d8cc9b3a1fa44fca89dd"
EXPECTED_CHANGES = [
    "res://physics/aero.gd",
    "res://physics/aircraft_data.gd",
    "res://physics/glow/installation.gd",
    "res://physics/glow/propeller.gd",
    "res://physics/trim.gd",
]
REPLAY_STEMS = [
    "seed-20261020-crossing-right-ai",
    "seed-20261020-crossing-right-player-coupled",
    "seed-20261020-crossing-right-player-exogenous",
    "seed-20261021-crossing-left-ai",
    "seed-20261021-crossing-left-player-coupled",
    "seed-20261021-crossing-left-player-exogenous",
]
FIXTURE_FILES = [
    "data/aircraft/jensen_ugly_stik_60.json",
    "data/aircraft/stik_glow_61fx_2t.json",
    "data/glow/stik_61fx_2t.json",
    "ai/companions/pilot.gd",
    "ai/companions/circuit_controller.gd",
    "data/ai/companions/aircraft/jensen-das-ugly-stik-60.json",
    "data/ai/companions/fields/club-default.json",
    "data/fields/default.json",
    "data/fields/lights.json",
    "data/scenery/default.json",
    "scenery/collision_world.gd",
    "scenery/scenery_loader.gd",
    "scenery/scenery.gd",
    "tools/flight_log_cli.gd",
]


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def artifact(path: Path, base: Path) -> dict[str, Any]:
    return {"path": path.relative_to(base).as_posix(), "bytes": path.stat().st_size, "sha256": sha256(path)}


def runner_for(label: str) -> dict[str, Any]:
    reports = [read_json(path) for path in EVIDENCE.rglob("report.json") if "runner" in path.parts]
    report = next((item for item in reports if item.get("label") == label), None)
    if report is None:
        raise ValueError(f"missing runner report for {label}")
    report_path = Path(str(report["report"]))
    log_path = Path(str(report["log"]))
    return {
        "label": label,
        "ok": report.get("ok"),
        "reason": report.get("reason"),
        "process_exit": report.get("process_exit"),
        "elapsed_seconds": report.get("elapsed_seconds"),
        "command": report.get("command"),
        "report": artifact(report_path, EVIDENCE),
        "engine_log": artifact(log_path, EVIDENCE),
        "diagnostics": report.get("diagnostics", []),
        "missing_required_text": report.get("missing_required_text", []),
    }


def state_sha(state: list[float]) -> str:
    encoded = json.dumps(state, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def rowwise_csv_comparison(baseline: Path, candidate: Path) -> dict[str, Any]:
    with baseline.open("r", encoding="utf-8", newline="") as stream:
        base_rows = list(csv.reader(stream))
    with candidate.open("r", encoding="utf-8", newline="") as stream:
        candidate_rows = list(csv.reader(stream))
    if not base_rows or not candidate_rows or base_rows[0] != candidate_rows[0]:
        raise ValueError(f"CSV headers differ: {baseline} vs {candidate}")
    if len(base_rows) != len(candidate_rows):
        raise ValueError(f"CSV row counts differ: {baseline} vs {candidate}")
    if any(len(row) != len(base_rows[0]) for row in base_rows + candidate_rows):
        raise ValueError(f"CSV column count differs from its header: {baseline} vs {candidate}")
    different_cells = sum(
        left != right
        for left_row, right_row in zip(base_rows[1:], candidate_rows[1:])
        for left, right in zip(left_row, right_row)
    )
    return {
        "baseline_csv": artifact(baseline, R4_EVIDENCE.parent),
        "candidate_csv": artifact(candidate, EVIDENCE),
        "rows_including_header": len(base_rows),
        "byte_identical": baseline.read_bytes() == candidate.read_bytes(),
        "different_cell_count": different_cells,
        "comparison": "CSV rows compared column-by-column; numeric changes would be counted as different cells.",
    }


def build_receipt(output_dir: Path) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    source_manifest_path = EVIDENCE / "source-manifest.json"
    source_manifest = read_json(source_manifest_path)
    copied_manifest = output_dir / "source-manifest.json"
    if copied_manifest.exists() and sha256(copied_manifest) != sha256(source_manifest_path):
        raise ValueError(f"refusing to replace a different source manifest: {copied_manifest}")
    if not copied_manifest.exists():
        copied_manifest.write_bytes(source_manifest_path.read_bytes())

    if source_manifest.get("baseline", {}).get("sha256") != BASE_IDENTITY:
        raise ValueError("source manifest baseline identity changed")
    if source_manifest.get("candidate", {}).get("sha256") != MERGED_IDENTITY:
        raise ValueError("source manifest candidate identity changed")
    if source_manifest.get("baseline", {}).get("source_count") != 133 or source_manifest.get("candidate", {}).get("source_count") != 133:
        raise ValueError("source manifest source count changed")
    if source_manifest.get("normalized_source_changes") != EXPECTED_CHANGES:
        raise ValueError("source manifest changed-source set differs from the reviewed five-file bridge")
    if source_manifest.get("missing_from_candidate") or source_manifest.get("added_to_candidate"):
        raise ValueError("source manifests have different file sets")

    changed_sources = []
    source_notes = {
        "res://physics/aero.gd": "Adds fuselage side force and crossflow drag from body_cy_beta and body_crossflow_area; both optional inputs are absent from the accepted legacy Jensen Stik.",
        "res://physics/aircraft_data.gd": "Loads and validates body_cy_beta and body_crossflow_area; both optional inputs are absent from the accepted legacy Jensen Stik.",
        "res://physics/glow/installation.gd": "Adds optional signed zero_lift_angle_rad installation data; that quantity is absent from both inspected Stik files.",
        "res://physics/glow/propeller.gd": "Offsets propeller section angle by the optional zero-lift angle; the bridge fixtures have no zero-lift input.",
        "res://physics/trim.gd": "Bounds modern Glow level-trim line search and snaps reached throttle bounds; exercised as a branch control on the modern Stik trim probe.",
    }
    for path in EXPECTED_CHANGES:
        changed_sources.append({
            "path": path,
            "baseline": source_manifest["baseline"]["files"][path],
            "merged": source_manifest["candidate"]["files"][path],
            "review_note": source_notes[path],
        })

    fixtures = []
    for relative in FIXTURE_FILES:
        base_path = R4_APP / relative
        candidate_path = ISOLATED_APP / relative
        base_hash = sha256(base_path)
        candidate_hash = sha256(candidate_path)
        fixtures.append({
            "path": relative.replace("\\", "/"),
            "baseline_sha256": base_hash,
            "candidate_sha256": candidate_hash,
            "equal": base_hash == candidate_hash,
            "bytes": base_path.stat().st_size,
        })
        if base_hash != candidate_hash:
            raise ValueError(f"bridge fixture changed outside the five-source overlay: {relative}")

    exact_path = REPOSITORY / "docs/research/ai-companions/AFC-04-R4/data/crossing-exact-replay-verification.json"
    exact = read_json(exact_path)
    if exact.get("replay_count") != 6 or exact.get("failures"):
        raise ValueError("retained R4 exact replay receipt is not the expected six-stream passing baseline")

    replays = []
    for stem in REPLAY_STEMS:
        exact_replay = exact["replays"][stem]
        baseline_csv = Path(exact_replay["flight_csv"])
        baseline_orfl = Path(exact_replay["orfl"])
        if sha256(baseline_csv) != exact_replay["flight_csv_sha256"]:
            raise ValueError(f"retained exact baseline CSV hash differs from its receipt: {stem}")
        if sha256(baseline_orfl) != exact_replay["orfl_sha256"]:
            raise ValueError(f"retained ORFL hash differs from its receipt: {stem}")
        candidate_dir = EVIDENCE / "candidate-replays" / stem
        candidate_report_path = candidate_dir / "replay.json"
        candidate_csv = candidate_dir / "flight.csv"
        candidate_report = read_json(candidate_report_path)
        if (candidate_report.get("status") != "ok" or candidate_report.get("mode") != "candidate"
                or candidate_report.get("complete") is not True or candidate_report.get("solver_changed") is not True
                or candidate_report.get("rows") != 4801
                or candidate_report.get("baseline_solver_sha256") != BASE_FLIGHT_LOG_ID
                or candidate_report.get("current_solver_sha256") != MERGED_FLIGHT_LOG_ID):
            raise ValueError(f"same-tape candidate replay failed its status/identity checks: {stem}")
        comparison = rowwise_csv_comparison(baseline_csv, candidate_csv)
        if not comparison["byte_identical"] or comparison["different_cell_count"] != 0:
            raise ValueError(f"same-tape output changed for {stem}; review actual deltas before acceptance")
        label = f"solver-merge-candidate-{stem}"
        replays.append({
            "stem": stem,
            "input_orfl": artifact(baseline_orfl, R4_EVIDENCE.parent),
            "input_orfl_sha256_from_r4_receipt": exact_replay["orfl_sha256"],
            "reused_exact_baseline": {
                "mode": exact_replay["mode"],
                "status": exact_replay["status"],
                "complete": exact_replay["complete"],
                "solver_changed": exact_replay["solver_changed"],
                "baseline_solver_sha256": exact_replay["baseline_solver_sha256"],
                "current_solver_sha256": exact_replay["current_solver_sha256"],
                "csv": artifact(baseline_csv, R4_EVIDENCE.parent),
                "report": artifact(Path(exact_replay["replay_json"]), R4_EVIDENCE.parent),
            },
            "merged_candidate": {
                "mode": candidate_report["mode"],
                "status": candidate_report["status"],
                "complete": candidate_report["complete"],
                "solver_changed": candidate_report["solver_changed"],
                "baseline_solver_sha256": candidate_report["baseline_solver_sha256"],
                "current_solver_sha256": candidate_report["current_solver_sha256"],
                "rows": candidate_report["rows"],
                "csv": artifact(candidate_csv, EVIDENCE),
                "report": artifact(candidate_report_path, EVIDENCE),
                "runner": runner_for(label),
            },
            "comparison": comparison,
        })

    trim_baseline_path = EVIDENCE / "trim" / "baseline.json"
    trim_merged_path = EVIDENCE / "trim" / "merged.json"
    trim_pilot_path = EVIDENCE / "trim" / "merged-with-baseline-pilot.json"
    trim_baseline = read_json(trim_baseline_path)
    trim_merged = read_json(trim_merged_path)
    trim_pilot = read_json(trim_pilot_path)
    if trim_baseline.get("solver_sha256") != BASE_FLIGHT_LOG_ID or trim_merged.get("solver_sha256") != MERGED_FLIGHT_LOG_ID:
        raise ValueError("trim probe FlightLog identities do not match the retained source snapshots")
    if trim_baseline.get("aircraft") != trim_merged.get("aircraft"):
        raise ValueError("trim or initial-state values changed between baseline and merged source sets")
    if trim_pilot.get("external_pilot", {}).get("sha256") != "363942b4b7d67f85333233f0c6000890ca984e5b76a8ccabe7973f70218259ed":
        raise ValueError("the external frozen R4 pilot did not load from the merged solver fixture")
    trim_models = []
    for base_model, merged_model in zip(trim_baseline["aircraft"], trim_merged["aircraft"]):
        trim_models.append({
            "model_id": base_model["model_id"],
            "speed_mps": base_model["V"],
            "baseline_trim_ok": base_model["trim_ok"],
            "merged_trim_ok": merged_model["trim_ok"],
            "trim_results_identical": base_model == merged_model,
            "iterations": base_model["iterations"],
            "residual": base_model["residual"],
            "throttle": base_model["throttle"],
            "rpm": base_model["rpm"],
            "thrust": base_model["thrust"],
            "bounded_glow_trim_branch_active": base_model["bounded_glow_trim_branch_active"],
            "modern_glow_installation_present": base_model["modern_glow_installation_present"],
            "zero_lift_angle_rad": base_model["zero_lift_angle_rad"],
            "initial_state_components": len(base_model["initial_state"]),
            "initial_state": base_model["initial_state"],
            "initial_state_json_sha256": state_sha(base_model["initial_state"]),
            "initial_state_identical": base_model["initial_state"] == merged_model["initial_state"],
        })
    if any(not item["trim_results_identical"] or not item["initial_state_identical"] for item in trim_models):
        raise ValueError("trim comparison did not match exactly")

    closed_loop_baseline_path = EVIDENCE / "closed-loop" / "baseline" / "report.json"
    closed_loop_candidate_path = EVIDENCE / "closed-loop" / "isolated-merged" / "report.json"
    closed_loop_excluded_path = EVIDENCE / "closed-loop" / "merged" / "report.json"
    closed_baseline = read_json(closed_loop_baseline_path)
    closed_candidate = read_json(closed_loop_candidate_path)
    closed_excluded = read_json(closed_loop_excluded_path)
    for key in ("collision_identity", "lake_identity", "field_id", "pilot_source_sha256", "probe_source_sha256"):
        if closed_baseline.get(key) != closed_candidate.get(key):
            raise ValueError(f"isolated closed-loop fixture identity changed: {key}")
    if closed_candidate.get("collision_identity") != "fb2be395cc783b3910f5eb2c5fcdef4936c36ea90bd8d25466d818f2b89743ae":
        raise ValueError("isolated candidate does not use the R4 collision fixture")
    if closed_candidate.get("lake_identity") != "bcc3774dc2ef339bac49aaec42b6a47b6b6d1104470d9fff35db242f6ab61efa":
        raise ValueError("isolated candidate does not use the R4 lake fixture")
    if closed_candidate.get("pilot_source_sha256") != "363942b4b7d67f85333233f0c6000890ca984e5b76a8ccabe7973f70218259ed":
        raise ValueError("closed-loop fixture pilot does not match the frozen R4 pilot")
    if not closed_candidate.get("valid_complete_runs") or not closed_candidate.get("deterministic_repeat", {}).get("exact_state_command_match"):
        raise ValueError("isolated merged closed-loop probe is incomplete or nondeterministic")
    if not closed_candidate.get("separation_gate_passed_for_all_cases"):
        raise ValueError("isolated merged closed-loop run fails its retained separation gate")
    base_by_id = {case["case_id"]: case for case in closed_baseline["cases"]}
    candidate_cases = []
    for candidate_case in closed_candidate["cases"]:
        baseline_case = base_by_id[candidate_case["case_id"]]
        if candidate_case["state_command_sha256"] != baseline_case["state_command_sha256"]:
            raise ValueError("closed-loop state/command digest changed for " + candidate_case["case_id"])
        fields = ["min_separation_to_player_m", "min_agl_m_by_role", "initial_target_height_matches_nominal", "initial_commanded_target_height_m"]
        if any(candidate_case.get(key) != baseline_case.get(key) for key in fields):
            raise ValueError("closed-loop survey metrics changed for " + candidate_case["case_id"])
        candidate_cases.append({
            "case_id": candidate_case["case_id"],
            "ticks": candidate_case["ticks"],
            "state_command_sha256": candidate_case["state_command_sha256"],
            "minimum_player_separation_m": candidate_case["min_separation_to_player_m"],
            "minimum_agl_m_by_role": candidate_case["min_agl_m_by_role"],
            "expected_initial_target_height_m": candidate_case["expected_initial_target_height_m"],
            "initial_commanded_target_height_m": candidate_case["initial_commanded_target_height_m"],
            "initial_target_height_error_m": candidate_case["initial_target_height_error_m"],
            "initial_target_height_matches_nominal": candidate_case["initial_target_height_matches_nominal"],
            "separation_gate_passed": candidate_case["separation_gate_passed"],
        })
    baseline_trajectory = EVIDENCE / "closed-loop" / "baseline" / "trajectory.csv"
    candidate_trajectory = EVIDENCE / "closed-loop" / "isolated-merged" / "trajectory.csv"
    if baseline_trajectory.read_bytes() != candidate_trajectory.read_bytes():
        raise ValueError("baseline and isolated merged closed-loop trajectories differ")

    failed_runner = runner_for("stik-trim-baseline")
    failed_merged_runner = runner_for("stik-trim-merged")
    retry_runners = [runner_for("stik-trim-baseline-r2"), runner_for("stik-trim-merged-r2")]
    if failed_runner["ok"] or failed_merged_runner["ok"] or not all(item["ok"] for item in retry_runners):
        raise ValueError("trim probe parse failure/corrected retry evidence changed")

    excluded_world = {
        "classification": "superseded_environment_mismatch",
        "report": artifact(closed_loop_excluded_path, EVIDENCE),
        "trajectory_csv": artifact(EVIDENCE / "closed-loop" / "merged" / "trajectory.csv", EVIDENCE),
        "collision_identity": closed_excluded.get("collision_identity"),
        "r4_collision_identity": closed_baseline.get("collision_identity"),
        "lake_identity": closed_excluded.get("lake_identity"),
        "r4_lake_identity": closed_baseline.get("lake_identity"),
        "excluded_reason": "The whole current-main clone carried unrelated scenery/collision-source changes. Its collision-world identity differs from R4, so this run is not used as a same-world solver comparison. It is retained as a setup diagnostic.",
        "verified_world_file_differences": [
            {
                "path": "data/scenery/default.json",
                "r4_sha256": "46c64bf12dc5ae886189cb574773f0b90fab158614e77969c1eee789e9db4900",
                "full_clone_sha256": "f871d9917cdd7d240c173651b6a75a2083c1363006c4546e24ae7b0bf2b4264e",
            },
            {
                "path": "scenery/collision_world.gd",
                "r4_sha256": "2313378ba9f20ca38f2767785f40f3f14c15443875e094e5e19f8c3866b5161f",
                "full_clone_sha256": "54c7d9002897abcf2875b35c0b0ecaaefb67b38f7fb99b25be1c2879658a9d44",
            },
            {
                "path": "scenery/scenery_loader.gd",
                "r4_sha256": "e602586cf055cf9bd9725bf150e22f77f64145573d3c234bb91a6f715606ebfd",
                "full_clone_sha256": "7b07f2ecc47ffed2ef4d1ce7ca552f58bb14625666df30c6105ca017a682f541",
            },
            {
                "path": "scenery/scenery.gd",
                "r4_sha256": "04fa2029e7f45994c814e22ee6f1641af98ba88b3ae33c7f59c491dc39da919b",
                "full_clone_sha256": "a40ffb1932aa8cb61483e111412b9f807b1b3ef2ee74372c95464eb98431292c",
            },
        ],
        "runner": runner_for("solver-merge-closed-loop-merged"),
    }

    inventory = []
    excluded_app = (EVIDENCE / "isolated-merged" / "app").resolve()
    for path in sorted(EVIDENCE.rglob("*")):
        if not path.is_file():
            continue
        try:
            path.resolve().relative_to(excluded_app)
            continue
        except ValueError:
            pass
        inventory.append(artifact(path, EVIDENCE))

    r4_profile_path = ISOLATED_APP / "data/ai/companions/aircraft/jensen-das-ugly-stik-60.json"
    r4_profile = read_json(r4_profile_path)
    if r4_profile.get("solver", {}).get("sha256") != BASE_IDENTITY:
        raise ValueError("frozen R4 profile no longer demonstrates the intended stale-source admission boundary")

    receipt = {
        "format": "openrc-companion-solver-merge-bridge v1",
        "step": "AFC-02-R2",
        "date_utc": "2026-10-21",
        "engine": "Godot 4.7.2-stable.official.ed1daf0bf Windows console",
        "physics_hz": 240,
        "purpose": "Bridge the full five-file merged physics source identity from frozen AFC-04-R4 using same-tape replays, controlled Stik trim probes, and a same-world closed-loop fixture override.",
        "result": "The accepted legacy Jensen Stik has identical trims, initial state, six same-tape candidate CSVs, and six closed-loop encounter state/command traces across the five-source overlay. This is a narrow applicability bridge; profile admission and physical validation are not established by this receipt.",
        "source_sets": {
            "baseline": {"app": str(R4_APP), "normalized_source_count": 133, "normalized_source_identity": BASE_IDENTITY, "flight_log_solver_identity": BASE_FLIGHT_LOG_ID},
            "candidate": {"app": str(ISOLATED_APP), "normalized_source_count": 133, "normalized_source_identity": MERGED_IDENTITY, "flight_log_solver_identity": MERGED_FLIGHT_LOG_ID},
            "normalization": "utf8-lf",
            "source_directories": ["physics", "sim", "failures"],
            "normalized_changed_source_files": changed_sources,
            "source_manifest": {
                "evidence_path": str(source_manifest_path),
                "evidence_bytes": source_manifest_path.stat().st_size,
                "evidence_sha256": sha256(source_manifest_path),
                "repository_copy": "source-manifest.json",
                "repository_copy_sha256": sha256(copied_manifest),
            },
            "isolated_app_construction": "Full app tree copied from the immutable R4 mirror; only the five listed physics source files were overlaid from the root-owned 2f4f35c04c837e89c5317412991046cd097dd3c9f501e9697702e94a6cff4bfa source snapshot. No app source/data writes were made during verification.",
            "unchanged_fixture_files": fixtures,
            "flight_log_identity_note": "FlightLog solver identity (21c675… / 8213b7…) is its own source fingerprint scope and must not be confused with the profile loader's normalized 133-file identity (1526… / 2f4…).",
            "research_and_runtime_scripts": [
                {"path": "research/ai-companions/avoidance/solver_merge_stik_trim_probe.gd", "sha256": sha256(REPOSITORY / "research/ai-companions/avoidance/solver_merge_stik_trim_probe.gd")},
                {"path": "research/ai-companions/avoidance/solver_merge_source_manifest.py", "sha256": sha256(REPOSITORY / "research/ai-companions/avoidance/solver_merge_source_manifest.py")},
                {"path": "research/ai-companions/avoidance/build_solver_merge_bridge_receipt.py", "sha256": sha256(Path(__file__).resolve())},
                {"path": "app/tools/flight_log_cli.gd", "sha256": sha256(REPOSITORY / "app/tools/flight_log_cli.gd")},
                {"path": "D evidence/closed-loop-probe/encounter_probe.gd", "sha256": sha256(EVIDENCE / "closed-loop-probe/encounter_probe.gd")},
            ],
        },
        "accepted_companion_and_profile_boundary": {
            "accepted_aircraft_id": "jensen-das-ugly-stik-60",
            "accepted_aircraft_data_path": "res://data/aircraft/jensen_ugly_stik_60.json",
            "accepted_aircraft_data_sha256": fixtures[0]["baseline_sha256"],
            "accepted_aircraft_profile_path": "res://data/ai/companions/aircraft/jensen-das-ugly-stik-60.json",
            "accepted_aircraft_profile_sha256": fixtures[4]["baseline_sha256"],
            "frozen_profile_solver_pin": BASE_IDENTITY,
            "candidate_profile_admission": "Not tested by this isolated bridge. Its frozen R4 profile still pins 1526…f33b7e, so it is stale for the candidate 2f4f35…cff4bfa normalized identity. The closed-loop survey intentionally overrides the pilot source and does not call qualification-profile admission.",
            "scope": "Only the accepted jensen-das-ugly-stik-60 companion is in scope. The modern stik-glow-61fx-2t is only a trim-line-search branch control.",
        },
        "trim_and_initial_state_comparison": {
            "method": "Trim.solve(level, 15.0 m/s) with unchanged aircraft JSON on each source snapshot; compare all returned trim fields and all 13 initial-state components.",
            "baseline_report": artifact(trim_baseline_path, EVIDENCE),
            "merged_report": artifact(trim_merged_path, EVIDENCE),
            "frozen_pilot_load_report": artifact(trim_pilot_path, EVIDENCE),
            "frozen_pilot_load": trim_pilot["external_pilot"],
            "baseline_flight_log_solver_identity": trim_baseline["solver_sha256"],
            "merged_flight_log_solver_identity": trim_merged["solver_sha256"],
            "aircraft": trim_models,
            "interpretation": "Legacy Jensen has no modern Glow installation and does not activate the bounded modern-Glow trim branch. Modern Stik activates that branch; both model trims and initial states still match exactly in this specific level-trim case. zero_lift_angle_rad is absent on both, so the new propeller offset is not exercised.",
            "runner_checks": [
                failed_runner,
                failed_merged_runner,
                *retry_runners,
                runner_for("test-external-baseline-pilot-load"),
            ],
        },
        "same_tape_replay_comparison": {
            "method": "Reuse the six retained calm 20-second R4 ORFLs and their exact baseline replay CSVs. Run flight_log_cli.gd in explicit --candidate mode on the 2f4 isolated app; this is post-conditioning baseline state plus recorded input tape, without pilot/controller adaptation or a new trim.",
            "retained_r4_exact_receipt": {
                "repository_path": "docs/research/ai-companions/AFC-04-R4/data/crossing-exact-replay-verification.json",
                "bytes": exact_path.stat().st_size,
                "sha256": sha256(exact_path),
            },
            "baseline_solver_identity": BASE_FLIGHT_LOG_ID,
            "merged_current_solver_identity": MERGED_FLIGHT_LOG_ID,
            "all_candidate_reports_complete": True,
            "all_candidate_reports_solver_changed": True,
            "all_six_candidate_csvs_byte_identical_to_retained_exact_baseline": True,
            "replays": replays,
            "interpretation": "The same-tape CSV parity is scoped to these six recordings. Candidate reports correctly say solver_changed=true despite byte-identical outputs; the affected optional data branches are absent or inactive for this accepted model and tape.",
        },
        "closed_loop_fixture_comparison": {
            "method": "Rerun the bounded six-stream calm crossing probe using the frozen R4 pilot SHA on both source snapshots. Candidate app is the five-file overlay on the immutable R4 world. This is a fixture-level controller rerun with an external pilot override, not profile admission.",
            "probe_source_sha256": closed_candidate["probe_source_sha256"],
            "pilot_source_sha256": closed_candidate["pilot_source_sha256"],
            "pilot_resource": closed_candidate["pilot_resource"],
            "collision_identity": closed_candidate["collision_identity"],
            "lake_identity": closed_candidate["lake_identity"],
            "field_id": closed_candidate["field_id"],
            "baseline_report": artifact(closed_loop_baseline_path, EVIDENCE),
            "merged_report": artifact(closed_loop_candidate_path, EVIDENCE),
            "baseline_runner": runner_for("solver-merge-closed-loop-baseline"),
            "merged_runner": runner_for("solver-merge-closed-loop-isolated-candidate"),
            "baseline_trajectory_csv": artifact(baseline_trajectory, EVIDENCE),
            "merged_trajectory_csv": artifact(candidate_trajectory, EVIDENCE),
            "trajectory_csv_byte_identical": True,
            "baseline_valid_complete_runs": closed_baseline["valid_complete_runs"],
            "merged_valid_complete_runs": closed_candidate["valid_complete_runs"],
            "baseline_deterministic_repeat": closed_baseline["deterministic_repeat"],
            "merged_deterministic_repeat": closed_candidate["deterministic_repeat"],
            "separation_gate_m": closed_candidate["separation_gate_m"],
            "separation_gate_passed_for_all_cases": closed_candidate["separation_gate_passed_for_all_cases"],
            "cases": candidate_cases,
            "raw_target_height_diagnostic": "Both case flags initial_target_height_matches_nominal=false are retained. The local-terrain floor commands 35.002191… m against nominal 35.0 m (about 2.191 mm); no separation or AGL threshold is relaxed.",
            "qualification_claimed": closed_candidate.get("qualification_claimed"),
            "excluded_full_clone_run": excluded_world,
        },
        "failed_or_superseded_attempts": [
            {
                "classification": "trim_probe_parse_setup_failure",
                "baseline_runner": failed_runner,
                "merged_runner": failed_merged_runner,
                "reason": "The first probe edit had an empty for-block at line 71 (expected indented block). Both runs exited 1 before executing a simulation; corrected reruns are separately retained and passed.",
            },
            {
                "classification": "environment_mismatch_excluded",
                "runner": excluded_world["runner"],
                "report": excluded_world["report"],
                "collision_identity": excluded_world["collision_identity"],
                "r4_collision_identity": excluded_world["r4_collision_identity"],
                "reason": excluded_world["excluded_reason"],
            },
        ],
        "limits": [
            "This receipt is a source-applicability and behavior bridge, not physical validation or release qualification.",
            "No production qualification profile was updated or admitted in this isolated fixture; the profile remains pinned to 1526…f33b7e.",
            "The six ORFL candidate replays are open-loop same-tape comparisons. They do not run the companion controller.",
            "The closed-loop report uses frozen pilot 363942…259ed via explicit fixture override; it does not prove candidate profile loading or controller behavior under the root-owned new pilot.",
            "The optional body-side-force inputs, modern Glow installation, and zero-lift-angle fields are absent from the accepted legacy Jensen Stik. The modern Stik trim result is only a narrow branch control.",
            "No new moving-traffic/performance/long-endurance claim is made by this bridge.",
        ],
        "artifact_inventory": {
            "evidence_root": str(EVIDENCE),
            "includes": "All retained bridge evidence files under the D evidence root, including failed runner logs/reports and superseded full-clone outputs; excludes only the copied isolated app tree, whose 133 source hashes are in source-manifest.json.",
            "files": inventory,
        },
    }

    output_path = output_dir / "receipt.json"
    output_path.write_text(json.dumps(receipt, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=REPOSITORY / "docs/research/ai-companions/AFC-02/solver-merge-2f4f35c0")
    args = parser.parse_args()
    receipt = build_receipt(args.output_dir.resolve())
    print(json.dumps({
        "receipt": str((args.output_dir.resolve() / "receipt.json")),
        "artifact_count": len(receipt["artifact_inventory"]["files"]),
        "same_tape_candidate_replays": len(receipt["same_tape_replay_comparison"]["replays"]),
        "trim_controls": len(receipt["trim_and_initial_state_comparison"]["aircraft"]),
        "normalized_source_identity": receipt["source_sets"]["candidate"]["normalized_source_identity"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
