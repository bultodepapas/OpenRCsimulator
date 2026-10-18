"""Record, exact-preflight, and replay complete runway tapes beside each grass route."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
GDSCRIPT = str(ROOT / "tools/grass/check_state_invariance.gd")
RUNWAY_RECORDINGS = {
    "stik_runway_current": "stik",
    "p51_runway_current": "p51",
}
RC_VEHICLE_IDS = ("mt8-bisonte", "monster-car-2")
GRASS_RUNTIME_SOURCE_PATHS = (
    "tools/grass/check_state_invariance.py",
    "tools/grass/check_state_invariance.gd",
    "app/render/field.gd",
    "app/render/grass_quality.gd",
    "app/render/ground.gd",
    "app/render/ground.gdshader",
    "app/render/near_grass.gd",
    "app/render/landscape_upgrade/scenery_grass_mask.gd",
    "app/scenery/imported_near_grass.gd",
    "app/scenery/imported_grass_material.gd",
    "app/scenery/imported_grass.gdshader",
    "app/scenery/imported_vegetation.gd",
)
EXPECTED_COUNTS = {
    "default": {"grass_common_short": 67, "grass_common_tall": 42, "grass_wispy_tall": 41},
    "enhanced": {"grass_common_short": 100, "grass_common_tall": 30, "grass_wispy_tall": 20},
}
IDENTITY_FIELDS = (
    "checkpoint_sha256",
    "aircraft_path",
    "aircraft_identity",
    "configuration",
    "engine",
    "dt_s",
    "baseline_solver_sha256",
    "current_solver_sha256",
    "ground_field_id",
    "ground_surfaces",
    "ground_description",
    "collision_world_identity",
    "lake_id",
)


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as source:
        value = json.load(source)
    if not isinstance(value, dict):
        raise ValueError(f"Expected JSON object in {path}")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_no_engine_errors(*paths: Path) -> None:
    for path in paths:
        if not path.is_file():
            continue
        content = path.read_text(encoding="utf-8", errors="replace")
        if "ERROR:" in content or "SCRIPT ERROR:" in content:
            raise RuntimeError(f"Godot reported an engine/script error; inspect {path}.")


def preflight_tape(name: str, spec: dict[str, Path]) -> dict[str, Any]:
    log_path = ROOT / spec["log"]
    report_path = ROOT / spec["baseline_report"]
    if not log_path.is_file() or not report_path.is_file():
        raise FileNotFoundError(f"Recorded tape or its exact-preflight report is missing for {name}.")
    baseline = load_json(report_path)
    expected = {
        "format": "openrc-flight-log-report v1",
        "status": "ok",
        "mode": "exact",
        "complete": True,
        "solver_changed": False,
        "error": "",
    }
    for field, value in expected.items():
        if baseline.get(field) != value:
            raise ValueError(f"{name} exact-preflight report has {field}={baseline.get(field)!r}, expected {value!r}.")
    if baseline.get("baseline_solver_sha256") != baseline.get("current_solver_sha256"):
        raise ValueError(f"{name} exact-preflight report has mismatched solver identities.")
    source_hash = sha256(log_path)
    if source_hash != baseline.get("source_sha256"):
        raise ValueError(f"{name} ORFL hash does not match its exact-preflight report.")
    if int(baseline.get("rows", 0)) < 2 or int(baseline.get("final_tick", -1)) < int(baseline.get("first_tick", 0)):
        raise ValueError(f"{name} exact-preflight report has no complete multi-tick sample range.")

    if name.startswith("stik_"):
        metadata = baseline.get("metadata", {})
        if metadata.get("aircraft") != "jensen-das-ugly-stik-60 (res://data/aircraft/jensen_ugly_stik_60.json)" \
                or metadata.get("launch_choice") != "runway" \
                or metadata.get("launch_field_id") != "default" \
                or "spring-damper gear contacts" not in str(metadata.get("ground", "")):
            raise ValueError("Stik tape is no longer the expected complete default-field flight.")
    if name.startswith("p51_"):
        metadata = baseline.get("metadata", {})
        if metadata.get("launch_choice") != "runway" or metadata.get("launch_field_id") != "default" \
                or "point contacts" not in str(metadata.get("ground", "")):
            raise ValueError("P-51 fresh tape is no longer the recorded default-field runway gear-contact fixture.")
    return {
        "log": log_path,
        "baseline_report_path": report_path,
        "baseline_report": baseline,
        "source_sha256": source_hash,
        "scenario_evidence": spec.get("scenario_evidence", {}),
    }


def run_one(
    godot: Path,
    out: Path,
    tape_name: str,
    mode: str,
    tape: dict[str, Any],
    timeout: int,
) -> dict[str, Any]:
    run_dir = out / tape_name / mode
    run_dir.mkdir(parents=True, exist_ok=False)
    csv_path = run_dir / "exact.csv"
    report_path = run_dir / "replay.json"
    stdout_path = run_dir / "godot.log"
    environment = os.environ.copy()
    environment["OPENRC_GRASS_QUALITY"] = "enhanced" if mode == "enhanced" else ""
    environment["OPENRC_SCENERY"] = "on"
    environment["OPENRC_SCENERY_QUALITY"] = "high"
    environment["OPENRC_SCENERY_AUDIO"] = "off"
    environment["OPENRC_SCENERY_BIRDS"] = "off"
    environment["OPENRC_SCENERY_FILE"] = "res://data/scenery/default.json"
    environment["OPENRC_TREE_WIND"] = "off"
    command = [
        str(godot),
        "--headless",
        "--path",
        str(ROOT / "app"),
        "--audio-driver",
        "Dummy",
        "--script",
        GDSCRIPT,
        "--",
        f"--mode={mode}",
        f"--log={tape['log']}",
        f"--csv={csv_path}",
        f"--report={report_path}",
    ]
    with stdout_path.open("w", encoding="utf-8", newline="") as stdout:
        process = subprocess.run(
            command,
            cwd=ROOT,
            env=environment,
            stdout=stdout,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
    if not report_path.is_file():
        raise RuntimeError(f"{tape_name}/{mode} produced no report (exit {process.returncode}); see {stdout_path}.")
    report = load_json(report_path)
    require_no_engine_errors(stdout_path)
    if process.returncode != 0 or report.get("status") != "ok":
        raise RuntimeError(
            f"{tape_name}/{mode} did not pass (exit {process.returncode}): "
            f"{report.get('error', 'unknown error')}; see {stdout_path}."
        )
    renderer = report.get("renderer", {})
    replay = report.get("replay", {})
    rcv = report.get("rc_ground_vehicle", {})
    expected_selector = "enhanced" if mode == "enhanced" else ""
    if renderer.get("enhanced") is not (mode == "enhanced") or renderer.get("selector") != expected_selector:
        raise ValueError(f"{tape_name}/{mode} did not observe the requested grass selector.")
    if renderer.get("scene_tree_initialized") is not True or renderer.get("field_built_in_same_process_as_replay") is not True:
        raise ValueError(f"{tape_name}/{mode} did not initialize the production field in the replay process.")
    if renderer.get("scenery_file_explicit") is not True:
        raise ValueError(f"{tape_name}/{mode} did not load the bundled production scenery layout explicitly.")
    if renderer.get("tree_only_objects_omitted_for_headless_probe") != 1 \
            or renderer.get("tree_only_object_types_omitted") != ["treeline"] \
            or renderer.get("tree_branch_omission_scope") != \
            "one default-field treeline object passed to Treeline.build; field surfaces and flight cues remain present":
        raise ValueError(f"{tape_name}/{mode} skipped a field branch outside the documented headless tree-only scope.")
    if renderer.get("material_route_ok") is not True or renderer.get("gpu_frame_rendered") is not False:
        raise ValueError(f"{tape_name}/{mode} renderer material contract failed or reported a GPU frame.")
    if renderer.get("near_grass_counts_by_asset") != EXPECTED_COUNTS[mode]:
        raise ValueError(f"{tape_name}/{mode} effective imported-grass allocation differs from its expected profile.")
    if renderer.get("rough_grass_photo_enabled") is not (mode == "enhanced"):
        raise ValueError(f"{tape_name}/{mode} did not observe the expected ground material selector effect.")
    rc_vehicles = rcv.get("vehicles", {})
    if rcv.get("vehicle_ids") != list(RC_VEHICLE_IDS) \
            or tuple(sorted(rc_vehicles)) != tuple(sorted(RC_VEHICLE_IDS)) \
            or rcv.get("native_backend_used") is not False \
            or rcv.get("backend") != "gdscript_reference":
        raise ValueError(f"{tape_name}/{mode} RC session recorder/replay contract did not pass on the GDScript CPU backend.")
    for vehicle_id in RC_VEHICLE_IDS:
        vehicle = rc_vehicles[vehicle_id]
        if vehicle.get("vehicle_id") != vehicle_id \
                or vehicle.get("checkpoint_control_tape_replay_exact") is not True \
                or vehicle.get("recording_complete") is not True \
                or vehicle.get("native_backend_used") is not False \
                or vehicle.get("backend") != "gdscript_reference":
            raise ValueError(f"{tape_name}/{mode} RC vehicle {vehicle_id} did not pass exact recorder/checkpoint replay.")
    if replay.get("source_sha256") != tape["source_sha256"]:
        raise ValueError(f"{tape_name}/{mode} replay report references a different source tape.")
    if replay.get("complete") is not True or replay.get("mode") != "exact" or replay.get("solver_changed") is not False:
        raise ValueError(f"{tape_name}/{mode} did not produce complete exact replay on the recorded solver.")
    baseline = tape["baseline_report"]
    if replay.get("baseline_solver_sha256") != baseline.get("baseline_solver_sha256"):
        raise ValueError(f"{tape_name}/{mode} baseline solver identity differs from its exact-preflight report.")
    if not csv_path.is_file() or len(csv_path.read_bytes().splitlines()) != int(replay.get("rows", 0)) + 1:
        raise ValueError(f"{tape_name}/{mode} exact CSV is absent or has incomplete row coverage.")
    return {
        "report_path": report_path,
        "csv_path": csv_path,
        "stdout_path": stdout_path,
        "report": report,
        "csv_sha256": sha256(csv_path),
    }


def capture_runway(godot: Path, out: Path, aircraft_kind: str, tape_name: str, timeout: int) -> dict[str, Any]:
    capture_dir = out / f"{tape_name}_capture"
    capture_dir.mkdir(parents=True, exist_ok=False)
    log_path = capture_dir / f"{aircraft_kind}-runway-current.orfl"
    record_report_path = capture_dir / "recording.json"
    record_log_path = capture_dir / "godot-record.log"
    environment = os.environ.copy()
    environment["OPENRC_GRASS_QUALITY"] = ""
    environment["OPENRC_SCENERY"] = "on"
    environment["OPENRC_SCENERY_QUALITY"] = "high"
    environment["OPENRC_SCENERY_AUDIO"] = "off"
    environment["OPENRC_SCENERY_BIRDS"] = "off"
    environment["OPENRC_SCENERY_FILE"] = "res://data/scenery/default.json"
    environment["OPENRC_TREE_WIND"] = "off"
    command = [
        str(godot),
        "--headless",
        "--path",
        str(ROOT / "app"),
        "--audio-driver",
        "Dummy",
        "--script",
        GDSCRIPT,
        "--",
        f"--capture-runway={aircraft_kind}",
        f"--log={log_path}",
        f"--report={record_report_path}",
    ]
    with record_log_path.open("w", encoding="utf-8", newline="") as stdout:
        process = subprocess.run(
            command,
            cwd=ROOT,
            env=environment,
            stdout=stdout,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
    if not record_report_path.is_file():
        raise RuntimeError(f"{aircraft_kind} capture produced no report (exit {process.returncode}); see {record_log_path}.")
    recording_report = load_json(record_report_path)
    require_no_engine_errors(record_log_path)
    if process.returncode != 0 or recording_report.get("status") != "ok":
        raise RuntimeError(
            f"{aircraft_kind} capture failed (exit {process.returncode}): {recording_report.get('error', 'unknown error')}; "
            f"see {record_log_path}."
        )
    recording = recording_report.get("recording", {})
    if recording.get("complete") is not True or recording.get("launch_choice") != "runway" \
            or recording.get("ground_field_id") != "default" \
            or not recording.get("initial_contact_indices"):
        raise ValueError(f"{aircraft_kind} recorder did not produce a complete default-field runway contact checkpoint.")

    replay_dir = capture_dir / "exact-preflight"
    replay_log_path = capture_dir / "godot-replay.log"
    replay_command = [
        sys.executable,
        str(ROOT / "tools/flight_log/flight_log.py"),
        "replay",
        str(log_path),
        "--godot",
        str(godot),
        "--out",
        str(replay_dir),
        "--timeout",
        str(timeout),
    ]
    with replay_log_path.open("w", encoding="utf-8", newline="") as stdout:
        replay_process = subprocess.run(
            replay_command,
            cwd=ROOT,
            env=environment,
            stdout=stdout,
            stderr=subprocess.STDOUT,
            timeout=timeout + 60,
            check=False,
        )
    exact_report_path = replay_dir / "replay.json"
    if replay_process.returncode != 0 or not exact_report_path.is_file():
        raise RuntimeError(f"{aircraft_kind} current-solver exact replay failed; see {replay_log_path}.")
    exact_report = load_json(exact_report_path)
    require_no_engine_errors(replay_log_path, replay_dir / "godot.log")
    if exact_report.get("status") != "ok" or exact_report.get("complete") is not True \
            or exact_report.get("mode") != "exact" or exact_report.get("solver_changed") is not False \
            or exact_report.get("source_sha256") != recording.get("source_sha256") \
            or exact_report.get("current_solver_sha256") != recording.get("solver_sha256"):
        raise ValueError(f"Fresh {aircraft_kind} tape did not pass complete exact replay with unchanged recorder/source identities.")
    return {
        "log": log_path,
        "baseline_report": exact_report,
        "scenario_evidence": {
            "path": str(record_report_path.relative_to(ROOT)).replace("\\", "/"),
            "capture_kind": recording.get("capture_kind"),
            "purpose": recording.get("purpose"),
            "aircraft_kind": recording.get("aircraft_kind"),
            "initial_contact_indices": recording.get("initial_contact_indices"),
            "final_contact_indices": recording.get("final_contact_indices"),
            "initial_gear_compressions_m": recording.get("initial_gear_compressions_m"),
            "launch_ground_anchors": recording.get("launch_ground_anchors"),
            "complete": recording.get("complete"),
            "rows": recording.get("rows"),
            "solver_sha256": recording.get("solver_sha256"),
        },
        "source_sha256": recording.get("source_sha256"),
    }


def _grass_runtime_source_hashes() -> dict[str, str]:
    hashes: dict[str, str] = {}
    for relative in GRASS_RUNTIME_SOURCE_PATHS:
        path = ROOT / relative
        if not path.is_file():
            raise FileNotFoundError(f"Grass runtime source is missing: {relative}")
        hashes[relative] = sha256(path)
    return hashes


def _run_with_grass_source_bracket(args: argparse.Namespace, report: dict[str, Any]) -> dict[str, Any]:
    godot = args.godot.resolve()
    if not godot.is_file():
        raise FileNotFoundError(f"Godot console executable not found: {godot}")
    out = args.out.resolve()
    if out.exists():
        raise FileExistsError(f"Refusing to overwrite output directory: {out}")
    out.mkdir(parents=True)
    report.update({
        "format": "openrc-grass-state-invariance-report v1",
        "status": "error",
        "error": "Not complete",
        "godot": str(godot),
        "execution": "headless CPU-only process; actual Field.build materials inspected; no GPU frame rendered",
        "tapes": {},
    })
    tapes: dict[str, dict[str, Any]] = {}
    for tape_name, aircraft_kind in RUNWAY_RECORDINGS.items():
        source_path = out / f"{tape_name}_capture" / f"{aircraft_kind}-runway-current.orfl"
        report["tapes"][tape_name] = {
            "capture_status": "recording",
            "capture_kind": "existing FlightLog API; scripted fixed-step runway recording",
            "aircraft_kind": aircraft_kind,
            "source": str(source_path.relative_to(ROOT)).replace("\\", "/"),
            "purpose": "software state/contact invariance only; not physical or owner flight acceptance",
        }
        fresh = capture_runway(godot, out, aircraft_kind, tape_name, args.timeout)
        tapes[tape_name] = preflight_tape(tape_name, {
            "log": fresh["log"],
            "baseline_report": fresh["log"].parent / "exact-preflight" / "replay.json",
            "scenario_evidence": fresh["scenario_evidence"],
        })
        exact = tapes[tape_name]
        report["tapes"][tape_name].update({
            "capture_status": "recorded and complete exact-preflight passed",
            "source_sha256": exact["source_sha256"],
            "exact_preflight": {
                "path": str(exact["baseline_report_path"].relative_to(ROOT)).replace("\\", "/"),
                "format": exact["baseline_report"].get("format"),
                "complete": exact["baseline_report"].get("complete"),
                "mode": exact["baseline_report"].get("mode"),
                "rows": exact["baseline_report"].get("rows"),
                "first_tick": exact["baseline_report"].get("first_tick"),
                "final_tick": exact["baseline_report"].get("final_tick"),
                "solver_sha256": exact["baseline_report"].get("baseline_solver_sha256"),
                "scenario_evidence": exact.get("scenario_evidence", {}),
            },
        })
    for tape_name, tape in tapes.items():
        results: dict[str, dict[str, Any]] = {}
        report["tapes"][tape_name]["grass_mode_runs"] = {}
        for mode in ("default", "enhanced"):
            report["tapes"][tape_name]["grass_mode_runs"][mode] = {"status": "running"}
            results[mode] = run_one(godot, out, tape_name, mode, tape, args.timeout)
            report["tapes"][tape_name]["grass_mode_runs"][mode] = {
                "status": "complete exact replay",
                "rows": results[mode]["report"]["replay"].get("rows"),
                "csv_sha256": results[mode]["csv_sha256"],
                "report": str(results[mode]["report_path"].relative_to(out)).replace("\\", "/"),
            }
        default_report = results["default"]["report"]["replay"]
        enhanced_report = results["enhanced"]["report"]["replay"]
        if default_report.get("rows") != enhanced_report.get("rows") \
                or default_report.get("first_tick") != enhanced_report.get("first_tick") \
                or default_report.get("final_tick") != enhanced_report.get("final_tick"):
            raise ValueError(f"{tape_name} replay tick ranges differ between grass modes.")
        for identity in IDENTITY_FIELDS:
            if default_report.get(identity) != enhanced_report.get(identity):
                raise ValueError(f"{tape_name} mode identity differs in {identity}.")
        default_rcv = results["default"]["report"]["rc_ground_vehicle"]
        enhanced_rcv = results["enhanced"]["report"]["rc_ground_vehicle"]
        for vehicle_id in RC_VEHICLE_IDS:
            default_vehicle = default_rcv["vehicles"][vehicle_id]
            enhanced_vehicle = enhanced_rcv["vehicles"][vehicle_id]
            for identity in ("state_damage_controls_events_sha256", "recorded_samples_sha256", "checkpoint_sha256"):
                if default_vehicle.get(identity) != enhanced_vehicle.get(identity):
                    raise ValueError(f"RC {vehicle_id} recorder/state/control-tape identity differs between grass modes in {identity}.")
        default_bytes = results["default"]["csv_path"].read_bytes()
        enhanced_bytes = results["enhanced"]["csv_path"].read_bytes()
        if default_bytes != enhanced_bytes:
            raise ValueError(f"{tape_name} exact replay CSV differs between default and enhanced grass.")
        report["tapes"][tape_name].update({
            "state_invariance": "byte-identical exact replay",
            "csv_sha256": results["default"]["csv_sha256"],
            "rows": default_report["rows"],
            "first_tick": default_report["first_tick"],
            "final_tick": default_report["final_tick"],
            "source_configuration_identity": {key: default_report.get(key) for key in IDENTITY_FIELDS},
            "solver_changed": False,
            "rc_ground_vehicle_state_invariance": "byte-identical GDScript session recording and checkpoint/control-tape replay",
            "rc_ground_vehicle": default_rcv,
            "renderer": {
                mode: results[mode]["report"]["renderer"]
                for mode in ("default", "enhanced")
            },
            "files": {
                mode: {
                    "csv": str(results[mode]["csv_path"].relative_to(out)).replace("\\", "/"),
                    "report": str(results[mode]["report_path"].relative_to(out)).replace("\\", "/"),
                    "log": str(results[mode]["stdout_path"].relative_to(out)).replace("\\", "/"),
                }
                for mode in ("default", "enhanced")
            },
        })
    report["status"] = "ok"
    report["error"] = ""
    return report


def run(args: argparse.Namespace, report: dict[str, Any]) -> dict[str, Any]:
    before = _grass_runtime_source_hashes()
    report["grass_runtime_source_identity"] = {
        "capture_scope": "narrow grass route runtime and checker source files, bracketed around capture, exact preflight, and paired replay",
        "before_sha256": before,
    }
    try:
        result = _run_with_grass_source_bracket(args, report)
    except Exception as error:
        after = _grass_runtime_source_hashes()
        unchanged = before == after
        report["grass_runtime_source_identity"].update({"after_sha256": after, "unchanged": unchanged})
        if not unchanged:
            raise RuntimeError("Grass runtime source hashes changed during the state-invariance run; result rejected.") from error
        raise
    after = _grass_runtime_source_hashes()
    unchanged = before == after
    report["grass_runtime_source_identity"].update({"after_sha256": after, "unchanged": unchanged})
    if not unchanged:
        report["status"] = "error"
        report["error"] = "Grass runtime source hashes changed during the state-invariance run; result rejected."
        raise RuntimeError(report["error"])
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True, help="Godot 4.7.2 console executable")
    parser.add_argument("--out", type=Path, required=True, help="new output directory; existing paths are refused")
    parser.add_argument("--timeout", type=int, default=900, help="per-process timeout in seconds (default: 900)")
    args = parser.parse_args()
    out = args.out.resolve()
    out_existed_before_run = out.exists()
    report: dict[str, Any] = {
        "format": "openrc-grass-state-invariance-report v1",
        "status": "error",
        "error": "Not complete",
        "godot": str(args.godot.resolve()),
        "execution": "headless CPU-only process; actual Field.build materials inspected; no GPU frame rendered",
        "tapes": {},
    }
    try:
        run(args, report)
        print("PASS: both fresh complete exact-preflighted tapes replay byte-identically in default and enhanced grass modes.")
        result = 0
    except (FileNotFoundError, FileExistsError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        report["status"] = "error"
        report["error"] = str(error)
        print(f"FAIL: {error}", file=sys.stderr)
        result = 1
    if not out_existed_before_run and out.exists() and out.is_dir():
        summary = out / "summary.json"
        if not summary.exists():
            summary.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    raise SystemExit(main())
