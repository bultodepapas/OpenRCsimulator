#!/usr/bin/env python3
"""Create a reproducible AV-09 current-solver, same-command-tape sensitivity pair."""
from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "app"
DEFAULT_CANDIDATE = APP / "data" / "aircraft" / "sebart_avanti_s_a200.json"
GENERATOR = ROOT / "research" / "avanti-s" / "av06" / "derive_physics.py"
TAPE_SCRIPT = ROOT / "research" / "avanti-s" / "av09-flaps" / "record_tape.gd"
PROBE_SCRIPT = ROOT / "research" / "avanti-s" / "av09-flaps" / "polar_probe.gd"
REFINE_REPLAY_SCRIPT = ROOT / "research" / "avanti-s" / "av09-flaps" / "refine_replay.gd"
FLIGHT_LOG = ROOT / "tools" / "flight_log" / "flight_log.py"
PRECHANGE_ROOT = ROOT / "docs" / "research" / "avanti-flaps" / "AV-09" / "evidence-2026-10-15" / "historical_prechange"
if not (PRECHANGE_ROOT / "sebart_avanti_s_a200.orfl").is_file():
    PRECHANGE_ROOT = ROOT / "tmp" / "av09-flaps-baseline"  # First capture, before evidence is retained.
PRECHANGE_LOG = PRECHANGE_ROOT / "sebart_avanti_s_a200.orfl"
PRECHANGE_MODEL = PRECHANGE_ROOT / "aircraft-before.json"
PRECHANGE_EXPORT = PRECHANGE_ROOT / "export"
PRECHANGE_EXACT = PRECHANGE_ROOT / "exact"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run(name: str, command: list[str], cwd: Path = ROOT, timeout: float = 600.0) -> None:
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
    )
    (CURRENT_OUT / f"{name}.log").write_text(result.stdout, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"{name} failed with exit code {result.returncode}; see {CURRENT_OUT / (name + '.log')}\n{result.stdout}")


def fresh_output(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    evidence_root = (ROOT / "docs" / "research" / "avanti-flaps" / "AV-09").resolve()
    if evidence_root not in resolved.parents:
        raise ValueError(f"evidence output must stay under {evidence_root}")
    if resolved.exists():
        raise FileExistsError(f"refusing to overwrite evidence: {resolved}")
    resolved.mkdir(parents=True)
    return resolved


def check_csv_pair(baseline: Path, candidate: Path, flap_aux_index: int) -> dict[str, Any]:
    with baseline.open(newline="", encoding="utf-8-sig") as stream:
        base_reader = csv.DictReader(stream)
        base_fields = base_reader.fieldnames or []
        base_rows = list(base_reader)
    with candidate.open(newline="", encoding="utf-8-sig") as stream:
        candidate_reader = csv.DictReader(stream)
        candidate_fields = candidate_reader.fieldnames or []
        candidate_rows = list(candidate_reader)
    required = {"tick", "t_s", "cmd_roll", "cmd_pitch", "cmd_yaw", "cmd_throttle", "cmd_gear_down", "cmd_wheel_brake", "cmd_flaps", f"aux_{flap_aux_index}"}
    if not required.issubset(base_fields) or not required.issubset(candidate_fields):
        missing = sorted(required - set(base_fields) | required - set(candidate_fields))
        raise ValueError(f"AV-09 paired CSV is missing required columns: {missing}")
    if base_fields != candidate_fields or len(base_rows) != len(candidate_rows) or len(base_rows) < 2:
        raise ValueError("baseline/candidate CSV layout or row count differs")
    commands = ["cmd_roll", "cmd_pitch", "cmd_yaw", "cmd_throttle", "cmd_gear_down", "cmd_wheel_brake", "cmd_flaps"]
    max_flap_fraction_delta = 0.0
    first_flap_tick: int | None = None
    last_flap_tick: int | None = None
    for base, candidate_row in zip(base_rows, candidate_rows, strict=True):
        if base["tick"] != candidate_row["tick"] or base["t_s"] != candidate_row["t_s"]:
            raise ValueError(f"tick/time mismatch at baseline tick {base['tick']}")
        for column in commands:
            if float(base[column]) != float(candidate_row[column]):
                raise ValueError(f"accepted input mismatch at tick {base['tick']} in {column}")
        tick = int(base["tick"])
        base_flap = float(base[f"aux_{flap_aux_index}"])
        candidate_flap = float(candidate_row[f"aux_{flap_aux_index}"])
        max_flap_fraction_delta = max(max_flap_fraction_delta, abs(base_flap - candidate_flap))
        if first_flap_tick is None and max(base_flap, candidate_flap) > 1e-9:
            first_flap_tick = tick
        if max(base_flap, candidate_flap) > 1e-9:
            last_flap_tick = tick
    if first_flap_tick is None or last_flap_tick is None:
        raise ValueError("the paired tape did not record deployed flaps")
    if max_flap_fraction_delta != 0.0:
        raise ValueError(f"flap actuator history differs between paired runs by {max_flap_fraction_delta}")
    return {
        "rows": len(base_rows),
        "first_tick": int(base_rows[0]["tick"]),
        "final_tick": int(base_rows[-1]["tick"]),
        "dt_s": float(base_rows[1]["t_s"]) - float(base_rows[0]["t_s"]),
        "accepted_command_channels_bitwise_numeric_match": True,
        "flap_actual_aux_channel": f"aux_{flap_aux_index}",
        "max_flap_actual_difference": max_flap_fraction_delta,
        "first_nonzero_flap_tick": first_flap_tick,
        "last_nonzero_flap_tick": last_flap_tick,
        "maximum_flap_fraction": max(float(row[f"aux_{flap_aux_index}"]) for row in base_rows),
    }


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def generated_flap_model(path: Path) -> tuple[dict[str, Any], float]:
    document = read_json(path)
    flaps = document.get("flaps")
    if not isinstance(flaps, dict):
        raise ValueError(f"aircraft has no raw flaps block: {path}")
    gain_quantity = flaps.get("aerodynamic_gain")
    if not isinstance(gain_quantity, dict) or not isinstance(gain_quantity.get("value"), (float, int)):
        raise ValueError(f"aircraft lacks a typed flap aerodynamic_gain quantity: {path}")
    return document, float(gain_quantity["value"])


def prove_same_generated_topology(baseline: Path, candidate: Path) -> tuple[float, float]:
    base_doc, base_gain = generated_flap_model(baseline)
    candidate_doc, candidate_gain = generated_flap_model(candidate)
    base_comparable = copy.deepcopy(base_doc)
    candidate_comparable = copy.deepcopy(candidate_doc)
    base_comparable["flaps"].pop("aerodynamic_gain")
    candidate_comparable["flaps"].pop("aerodynamic_gain")
    if base_comparable != candidate_comparable:
        raise ValueError("gain-0 baseline and candidate differ beyond flaps.aerodynamic_gain")
    if base_gain != 0.0 or candidate_gain != 1.0:
        raise ValueError(f"expected generated flap gains 0 and 1; got {base_gain} and {candidate_gain}")
    return base_gain, candidate_gain


def paired_segments(baseline_csv: Path, candidate_csv: Path, tape: dict[str, Any], flap_aux_index: int) -> dict[str, Any]:
    def read_rows(path: Path) -> tuple[list[str], dict[int, dict[str, str]]]:
        with path.open(newline="", encoding="utf-8-sig") as stream:
            reader = csv.DictReader(stream)
            rows = {int(row["tick"]): row for row in reader}
            return list(reader.fieldnames or []), rows

    base_fields, base_by_tick = read_rows(baseline_csv)
    candidate_fields, candidate_by_tick = read_rows(candidate_csv)
    if base_fields != candidate_fields or base_by_tick.keys() != candidate_by_tick.keys():
        raise ValueError("cannot build paired segment summary from unaligned CSVs")
    output: list[dict[str, Any]] = []
    aux_column = f"aux_{flap_aux_index}"
    for segment in tape.get("segments", []):
        first_tick = int(segment["first_tick"])
        last_tick = int(segment["last_tick"])
        start_tick = first_tick - 1
        if start_tick not in base_by_tick or last_tick not in base_by_tick:
            raise ValueError(f"segment {segment.get('name')} is outside the recorded CSV")
        start_base = base_by_tick[start_tick]
        end_base = base_by_tick[last_tick]
        start_candidate = candidate_by_tick[start_tick]
        end_candidate = candidate_by_tick[last_tick]
        interval_ticks = list(range(first_tick, last_tick + 1))

        def number(row: dict[str, str], key: str) -> float:
            return float(row[key])

        endpoint_fields = ["north_m", "east_m", "down_m", "tas_mps", "alpha_rad", "u_mps", "v_mps", "w_mps"]
        base_change = {key: number(end_base, key) - number(start_base, key) for key in endpoint_fields}
        candidate_change = {key: number(end_candidate, key) - number(start_candidate, key) for key in endpoint_fields}
        interval_delta = {key: candidate_change[key] - base_change[key] for key in endpoint_fields}
        loads: dict[str, dict[str, float]] = {}
        for key in ["Fx_N", "Fz_N", "My_Nm"]:
            deltas = [number(candidate_by_tick[tick], key) - number(base_by_tick[tick], key) for tick in interval_ticks]
            loads[key] = {
                "mean_candidate_minus_baseline": sum(deltas) / len(deltas),
                "max_abs_candidate_minus_baseline": max(abs(delta) for delta in deltas),
            }
        output.append({
            "name": segment["name"],
            "first_command_tick": first_tick,
            "last_command_tick": last_tick,
            "duration_s": segment["duration_s"],
            "cmd_flaps": segment["cmd_flaps"],
            "pitch_offset_from_trim_command": segment["pitch_offset_from_trim_command"],
            "loads_time_basis": "Loads are k1 interval-start samples; rows are aligned by tick and loads_t_s.",
            "flap_fraction_start_end": {
                "baseline": [number(start_base, aux_column), number(end_base, aux_column)],
                "candidate": [number(start_candidate, aux_column), number(end_candidate, aux_column)],
            },
            "cumulative_open_loop_endpoint_delta_candidate_minus_baseline": {
                key: number(end_candidate, key) - number(end_base, key) for key in endpoint_fields
            },
            "segment_interval_change_delta_candidate_minus_baseline": interval_delta,
            "aerodynamic_load_delta_candidate_minus_baseline": loads,
        })
    return {
        "interpretation": "Candidate-minus-baseline comparison of one accepted-input tape. Endpoint deltas accumulate earlier open-loop divergence; segment interval-change deltas compare changes during the named segment.",
        "segments": output,
    }


def same_timed_command_plan(first: dict[str, Any], second: dict[str, Any]) -> bool:
    first_plan = [(s["name"], float(s["duration_s"]), float(s["cmd_flaps"]),
        float(s["pitch_offset_from_trim_command"])) for s in first.get("segments", [])]
    second_plan = [(s["name"], float(s["duration_s"]), float(s["cmd_flaps"]),
        float(s["pitch_offset_from_trim_command"])) for s in second.get("segments", [])]
    return bool(first_plan) and first_plan == second_plan


def refinement_analysis(csvs: dict[int, tuple[Path, Path]], tapes: dict[int, dict[str, Any]],
        flap_aux_index: int) -> dict[str, Any]:
    def rows_by_time(path: Path) -> list[dict[str, str]]:
        with path.open(newline="", encoding="utf-8-sig") as stream:
            return list(csv.DictReader(stream))

    rowsets = {rate: (rows_by_time(paths[0]), rows_by_time(paths[1])) for rate, paths in csvs.items()}
    boundary_times: list[tuple[str, float]] = []
    for segment in tapes[240].get("segments", []):
        previous_time = boundary_times[-1][1] if boundary_times else 0.0
        boundary_times.append((str(segment["name"]), previous_time + float(segment["duration_s"])))
    fields = ["north_m", "east_m", "down_m", "tas_mps", "alpha_rad", "u_mps", "v_mps", "w_mps", "Fx_N", "Fz_N", "My_Nm"]
    points: list[dict[str, Any]] = []

    def nearest(rows: list[dict[str, str]], time_s: float) -> dict[str, str]:
        row = min(rows, key=lambda value: abs(float(value["t_s"]) - time_s))
        if abs(float(row["t_s"]) - time_s) > 1e-9:
            raise ValueError(f"no output row within 1 ns of common time {time_s:.9f}s")
        return row

    for name, time_s in boundary_times:
        selected = {rate: (nearest(pair[0], time_s), nearest(pair[1], time_s))
            for rate, pair in rowsets.items()}
        per_rate: dict[str, Any] = {}
        for rate, (base, candidate) in selected.items():
            per_rate[str(rate)] = {
                "time_s": float(candidate["t_s"]),
                "flap_command": float(candidate["cmd_flaps"]),
                "baseline_actual_flap_fraction": float(base[f"aux_{flap_aux_index}"]),
                "candidate_actual_flap_fraction": float(candidate[f"aux_{flap_aux_index}"]),
                "candidate_minus_baseline": {key: float(candidate[key]) - float(base[key]) for key in fields},
                "candidate_state": {key: float(candidate[key]) for key in fields},
            }
        sensitivity_240 = per_rate["240"]["candidate_minus_baseline"]
        sensitivity_480 = per_rate["480"]["candidate_minus_baseline"]
        points.append({
            "name": name,
            "nominal_common_time_s": time_s,
            "candidate_state_480_minus_240": {
                key: per_rate["480"]["candidate_state"][key] - per_rate["240"]["candidate_state"][key]
                for key in fields
            },
            "flap_fraction_candidate_480_minus_240": per_rate["480"]["candidate_actual_flap_fraction"]
                - per_rate["240"]["candidate_actual_flap_fraction"],
            "sensitivity_480_minus_240": {key: sensitivity_480[key] - sensitivity_240[key] for key in fields},
            "rates": per_rate,
        })
    return {
        "method": "Two complete same-solver runs at 240 and 480 Hz use the same physical-time piecewise-constant flap/pitch command schedule; each rate has its own gain-0 source log, complete exact replay, and gain-1 open-loop candidate replay.",
        "interpretation": "Values at common segment-end times show timestep sensitivity of this implementation. The gain-0 model is a software sensitivity control, not a measured clean airplane. This is not physical validation.",
        "command_schedules_match": same_timed_command_plan(tapes[240], tapes[480]),
        "points": points,
    }


def altitude_envelope(path: Path, minimum_agl_m: float = 100.0) -> dict[str, float]:
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise ValueError(f"cannot assess empty trajectory {path}")
    # Trace NED down is positive; the selected flat sea-level runway datum is zero.
    altitudes = [-float(row["down_m"]) for row in rows]
    result = {"minimum_agl_m": min(altitudes), "maximum_agl_m": max(altitudes), "initial_agl_m": altitudes[0]}
    if result["minimum_agl_m"] < minimum_agl_m:
        raise ValueError(f"trajectory {path} violates the {minimum_agl_m:.1f} m minimum AGL evidence margin: {result['minimum_agl_m']:.3f} m")
    return result


def compare_legacy_channels(baseline_csv: Path, candidate_csv: Path) -> dict[str, Any]:
    with baseline_csv.open(newline="", encoding="utf-8-sig") as stream:
        base_reader = csv.DictReader(stream)
        base_fields = base_reader.fieldnames or []
        base_rows = list(base_reader)
    with candidate_csv.open(newline="", encoding="utf-8-sig") as stream:
        candidate_reader = csv.DictReader(stream)
        candidate_fields = candidate_reader.fieldnames or []
        candidate_rows = list(candidate_reader)
    if base_fields != candidate_fields or len(base_rows) != len(candidate_rows):
        raise ValueError("prechange/current-solver clean comparison changed the legacy CSV layout or row count")
    command_columns = [name for name in ["cmd_roll", "cmd_pitch", "cmd_yaw", "cmd_throttle", "cmd_gear_down", "cmd_wheel_brake"] if name in base_fields]
    if not {"tick", "t_s", "cmd_roll", "cmd_pitch", "cmd_yaw", "cmd_throttle"}.issubset(base_fields) or "cmd_flaps" in base_fields:
        raise ValueError("prechange trace should retain the old non-flap command layout")
    for base, candidate in zip(base_rows, candidate_rows, strict=True):
        if base["tick"] != candidate["tick"] or base["t_s"] != candidate["t_s"]:
            raise ValueError(f"prechange/current-solver clean comparison time mismatch at tick {base['tick']}")
        for name in command_columns:
            if float(base[name]) != float(candidate[name]):
                raise ValueError(f"prechange/current-solver accepted command mismatch at tick {base['tick']} in {name}")
    return {"rows": len(base_rows), "layout_matches": True, "accepted_legacy_command_channels_match": command_columns,
        "commands_match_bitwise_numeric": True, "no_flap_column": True}


def main() -> int:
    global CURRENT_OUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "docs" / "research" / "avanti-flaps" / "AV-09" / "evidence-2026-10-15")
    parser.add_argument("--candidate-model", type=Path, default=DEFAULT_CANDIDATE)
    parser.add_argument("--godot", type=Path, default=None)
    parser.add_argument("--timeout", type=float, default=600.0)
    args = parser.parse_args()
    CURRENT_OUT = fresh_output(args.out)
    candidate = args.candidate_model.expanduser().resolve()
    if not candidate.is_file():
        raise FileNotFoundError(f"candidate model does not exist: {candidate}")
    if not GENERATOR.is_file() or not TAPE_SCRIPT.is_file() or not PROBE_SCRIPT.is_file() or not REFINE_REPLAY_SCRIPT.is_file():
        raise FileNotFoundError("AV-09 generator or research scripts are missing")
    if args.godot:
        godot = args.godot.expanduser().resolve()
    elif os.environ.get("GODOT"):
        godot = Path(os.environ["GODOT"]).expanduser().resolve()
    else:
        pinned = ROOT / ".tools" / "Godot_v4.7.2-stable_win64_console.exe"
        godot = pinned if pinned.is_file() else Path(shutil.which("godot") or "")
    if not godot.is_file():
        raise FileNotFoundError("Godot executable not found; pass --godot or set GODOT")

    model_dir = CURRENT_OUT / "models"
    model_dir.mkdir()
    baseline_model = model_dir / "av09_flaps_aero_disabled.json"
    derivation_report = model_dir / "derivation.md"
    run("generate_baseline_model", [
        sys.executable, str(GENERATOR), "--flap-aero-disabled",
        "--output", str(baseline_model), "--report-output", str(derivation_report),
    ])
    if not baseline_model.is_file() or not derivation_report.is_file():
        raise RuntimeError("flap aerodynamic sensitivity model generation did not produce both outputs")
    baseline_gain, candidate_gain = prove_same_generated_topology(baseline_model, candidate)

    recording_dir = CURRENT_OUT / "recording"
    recording_dir.mkdir()
    log_path = recording_dir / "av09_flaps_open_loop.orfl"
    run("record_tape", [
        str(godot), "--headless", "--path", str(APP), "--audio-driver", "Dummy",
        "--script", str(TAPE_SCRIPT), "--",
        f"--out={log_path.as_posix()}", f"--aircraft={baseline_model.as_posix()}", "--physics-ticks=240",
    ])
    tape_manifest = log_path.with_suffix(".manifest.json")
    if not log_path.is_file() or not tape_manifest.is_file():
        raise RuntimeError("Godot tape recorder did not produce its log and manifest")

    def flight_log(name: str, *command: str, timeout: float | None = None) -> None:
        run(name, [sys.executable, str(FLIGHT_LOG), *command], timeout=timeout or args.timeout)

    required_prechange = [PRECHANGE_LOG, PRECHANGE_MODEL, PRECHANGE_EXPORT / "export.json",
        PRECHANGE_EXPORT / "flight.csv", PRECHANGE_EXACT / "replay.json", PRECHANGE_EXACT / "flight.csv"]
    if any(not path.is_file() for path in required_prechange):
        raise FileNotFoundError("the preserved prechange Avanti ORFL, source JSON, export and exact replay are required")
    expected_prechange_model_sha256 = "68d3fd42b28e30bf1dc210b838d945d517f062506749af14f995a5a5f39a83b6"
    if sha256(PRECHANGE_MODEL) != expected_prechange_model_sha256:
        raise ValueError("prechange Avanti source JSON hash does not match the preserved baseline identity")
    if (PRECHANGE_EXPORT / "flight.csv").read_bytes() != (PRECHANGE_EXACT / "flight.csv").read_bytes():
        raise ValueError("prechange baseline exact replay CSV is not identical to its preserved export")
    historical_dir = CURRENT_OUT / "historical_prechange"
    historical_dir.mkdir()
    historical_log = historical_dir / PRECHANGE_LOG.name
    historical_model = historical_dir / PRECHANGE_MODEL.name
    shutil.copy2(PRECHANGE_LOG, historical_log)
    shutil.copy2(PRECHANGE_MODEL, historical_model)
    for source_dir_name in ["export", "exact"]:
        copied_dir = historical_dir / source_dir_name
        copied_dir.mkdir()
        for filename in (["export.json", "flight.csv"] if source_dir_name == "export" else ["replay.json", "flight.csv"]):
            shutil.copy2(PRECHANGE_ROOT / source_dir_name / filename, copied_dir / filename)
    historical_candidate_dir = historical_dir / "current_solver_oldraw_candidate"
    flight_log("prechange_oldraw_candidate_replay", "replay", str(historical_log), "--candidate", str(historical_model),
        "--out", str(historical_candidate_dir), "--godot", str(godot))
    flight_log("prechange_oldraw_compare", "compare", str(historical_dir / "exact" / "flight.csv"),
        str(historical_candidate_dir / "flight.csv"), "--out", str(historical_dir / "current_solver_comparison.json"))
    historical_exact = read_json(historical_dir / "exact" / "replay.json")
    historical_candidate = read_json(historical_candidate_dir / "replay.json")
    historical_comparison = read_json(historical_dir / "current_solver_comparison.json")
    if historical_exact.get("status") != "ok" or not historical_exact.get("complete") \
            or historical_exact.get("mode") != "exact" or historical_exact.get("solver_changed"):
        raise RuntimeError("preserved prechange source must retain its complete exact replay report")
    if historical_candidate.get("status") != "ok" or not historical_candidate.get("complete") \
            or historical_candidate.get("mode") != "candidate" or not historical_candidate.get("solver_changed"):
        raise RuntimeError("prechange source under current solver must be an explicitly solver-changed candidate replay")
    if historical_comparison.get("status") != "ok":
        raise RuntimeError("prechange/current-solver clean comparison failed")
    legacy_command_check = compare_legacy_channels(historical_dir / "exact" / "flight.csv",
        historical_candidate_dir / "flight.csv")
    historical_csv_byte_identical = (historical_dir / "exact" / "flight.csv").read_bytes() == (historical_candidate_dir / "flight.csv").read_bytes()
    if not historical_csv_byte_identical:
        raise RuntimeError("current-solver old-raw clean candidate differs from the preserved prechange exact CSV")
    shutil.copy2(PRECHANGE_ROOT / "verification.json", historical_dir / "prechange_verification.json")
    historical_info = {
        "interpretation": "Preserved before the flap feature, then replayed against the current solver using the same original raw aircraft JSON. The replay is intentionally candidate mode with solver_changed=true; it is a clean-model regression probe, not current-solver exact equivalence.",
        "source_orfl": {"path": str(historical_log.relative_to(ROOT)), "sha256": sha256(historical_log), "bytes": historical_log.stat().st_size},
        "source_aircraft_json": {"path": str(historical_model.relative_to(ROOT)), "sha256": sha256(historical_model)},
        "prechange_exact": {"status": historical_exact.get("status"), "complete": historical_exact.get("complete"),
            "mode": historical_exact.get("mode"), "solver_changed": historical_exact.get("solver_changed"),
            "report_path": "historical_prechange/exact/replay.json", "report_sha256": sha256(historical_dir / "exact" / "replay.json")},
        "current_solver_candidate": {"status": historical_candidate.get("status"), "complete": historical_candidate.get("complete"),
            "mode": historical_candidate.get("mode"), "solver_changed": historical_candidate.get("solver_changed"),
            "report_path": str((historical_candidate_dir / "replay.json").relative_to(ROOT))},
        "comparison": historical_comparison,
        "legacy_layout_and_commands": legacy_command_check,
        "current_solver_candidate_csv_byte_identical_to_prechange_exact": historical_csv_byte_identical,
        "copied_prechange_export_sha256": sha256(historical_dir / "export" / "flight.csv"),
        "copied_prechange_exact_csv_sha256": sha256(historical_dir / "exact" / "flight.csv"),
        "source_json_expected_prechange_sha256": "68d3fd42b28e30bf1dc210b838d945d517f062506749af14f995a5a5f39a83b6",
    }
    (historical_dir / "historical_comparison.json").write_text(
        json.dumps(historical_info, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")

    flight_log("baseline_export", "export", str(log_path), "--out", str(CURRENT_OUT / "baseline_export"), "--godot", str(godot))
    flight_log("baseline_exact_replay", "replay", str(log_path), "--out", str(CURRENT_OUT / "exact_replay"), "--godot", str(godot))
    flight_log("candidate_replay", "replay", str(log_path), "--candidate", str(candidate),
        "--out", str(CURRENT_OUT / "candidate_replay"), "--godot", str(godot))
    flight_log("paired_csv_compare", "compare", str(CURRENT_OUT / "baseline_export" / "flight.csv"),
        str(CURRENT_OUT / "candidate_replay" / "flight.csv"), "--out", str(CURRENT_OUT / "comparison.json"))
    flight_log("baseline_summary", "summarize", str(CURRENT_OUT / "baseline_export" / "flight.csv"),
        "--out", str(CURRENT_OUT / "baseline_summary.json"))
    flight_log("candidate_summary", "summarize", str(CURRENT_OUT / "candidate_replay" / "flight.csv"),
        "--out", str(CURRENT_OUT / "candidate_summary.json"))

    probe_path = CURRENT_OUT / "static_model_probe.json"
    run("static_model_probe", [
        str(godot), "--headless", "--path", str(APP), "--audio-driver", "Dummy",
        "--script", str(PROBE_SCRIPT), "--",
        f"--baseline={baseline_model.as_posix()}", f"--candidate={candidate.as_posix()}",
        f"--out={probe_path.as_posix()}",
    ])

    baseline_report = read_json(CURRENT_OUT / "baseline_export" / "export.json")
    exact_report = read_json(CURRENT_OUT / "exact_replay" / "replay.json")
    candidate_report = read_json(CURRENT_OUT / "candidate_replay" / "replay.json")
    comparison = read_json(CURRENT_OUT / "comparison.json")
    tape = read_json(tape_manifest)
    probe = read_json(probe_path)
    if exact_report.get("status") != "ok" or not exact_report.get("complete") or exact_report.get("mode") != "exact" or exact_report.get("solver_changed"):
        raise RuntimeError("baseline log did not pass complete exact replay with the current solver")
    if candidate_report.get("status") != "ok" or not candidate_report.get("complete") or candidate_report.get("mode") != "candidate" or candidate_report.get("solver_changed"):
        raise RuntimeError("candidate replay must be complete, explicitly candidate-mode, and same-solver")
    flap_metadata = candidate_report.get("metadata", {})
    if flap_metadata.get("flap_law") != "controls.flaps.hinged_trailing_edge.v1" or flap_metadata.get("metadata_schema") != "openrc-flight-meta v9":
        raise RuntimeError("recorded log metadata does not identify the AV-09 flap trace contract")
    csv_check = check_csv_pair(CURRENT_OUT / "baseline_export" / "flight.csv",
        CURRENT_OUT / "candidate_replay" / "flight.csv", int(flap_metadata["flap_aux_index"]))
    if (CURRENT_OUT / "baseline_export" / "flight.csv").read_bytes() != (CURRENT_OUT / "exact_replay" / "flight.csv").read_bytes():
        raise RuntimeError("exact replay CSV differs from the preserved source export")
    segment_analysis_path = CURRENT_OUT / "paired_segment_analysis.json"
    segment_analysis = paired_segments(CURRENT_OUT / "baseline_export" / "flight.csv",
        CURRENT_OUT / "candidate_replay" / "flight.csv", tape, int(flap_metadata["flap_aux_index"]))
    segment_analysis_path.write_text(json.dumps(segment_analysis, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")

    refinement_dir = CURRENT_OUT / "refinement_480hz"
    recording_480 = refinement_dir / "recording"
    recording_480.mkdir(parents=True)
    log_480 = recording_480 / "av09_flaps_open_loop_480hz.orfl"
    run("record_tape_480hz", [
        str(godot), "--headless", "--path", str(APP), "--audio-driver", "Dummy",
        "--script", str(TAPE_SCRIPT), "--",
        f"--out={log_480.as_posix()}", f"--aircraft={baseline_model.as_posix()}", "--physics-ticks=480",
    ])
    tape_480_path = log_480.with_suffix(".manifest.json")
    if not log_480.is_file() or not tape_480_path.is_file():
        raise RuntimeError("480 Hz recorder did not produce its log and manifest")
    tape_480 = read_json(tape_480_path)
    if not same_timed_command_plan(tape, tape_480):
        raise RuntimeError("240 Hz and 480 Hz recorders produced different time-indexed command schedules")
    if abs(float(tape.get("dt_s", 0.0)) * 240.0 - 1.0) > 1e-12 \
            or abs(float(tape_480.get("dt_s", 0.0)) * 480.0 - 1.0) > 1e-12 \
            or int(tape_480.get("ticks", -1)) != 2 * int(tape.get("ticks", -2)):
        raise RuntimeError("timestep refinement logs do not span the same duration at 240/480 Hz")

    exact_480_dir = refinement_dir / "exact_replay"
    candidate_480_dir = refinement_dir / "candidate_replay"
    run("baseline_exact_replay_480hz", [
        str(godot), "--headless", "--path", str(APP), "--audio-driver", "Dummy",
        "--script", str(REFINE_REPLAY_SCRIPT), "--",
        f"--log={log_480.as_posix()}", f"--out={exact_480_dir.as_posix()}",
        "--mode=exact", "--physics-ticks=480",
    ])
    run("candidate_replay_480hz", [
        str(godot), "--headless", "--path", str(APP), "--audio-driver", "Dummy",
        "--script", str(REFINE_REPLAY_SCRIPT), "--",
        f"--log={log_480.as_posix()}", f"--out={candidate_480_dir.as_posix()}",
        f"--candidate={candidate.as_posix()}", "--mode=candidate", "--physics-ticks=480",
    ])
    flight_log("paired_csv_compare_480hz", "compare", str(exact_480_dir / "flight.csv"),
        str(candidate_480_dir / "flight.csv"), "--out", str(refinement_dir / "comparison.json"))
    flight_log("baseline_summary_480hz", "summarize", str(exact_480_dir / "flight.csv"),
        "--out", str(refinement_dir / "baseline_summary.json"))
    flight_log("candidate_summary_480hz", "summarize", str(candidate_480_dir / "flight.csv"),
        "--out", str(refinement_dir / "candidate_summary.json"))
    exact_480_report = read_json(exact_480_dir / "replay.json")
    candidate_480_report = read_json(candidate_480_dir / "replay.json")
    for name, report, mode in [
        ("480 Hz exact baseline", exact_480_report, "exact"),
        ("480 Hz candidate", candidate_480_report, "candidate"),
    ]:
        if report.get("status") != "ok" or not report.get("complete") or report.get("mode") != mode \
                or report.get("solver_changed") or int(report.get("physics_ticks_per_second", 0)) != 480:
            raise RuntimeError(f"{name} must complete at 480 Hz with unchanged solver identity")
    if exact_480_report.get("source_sha256") != sha256(log_480) \
            or candidate_480_report.get("source_sha256") != sha256(log_480):
        raise RuntimeError("480 Hz replay report source hash does not match its recorded ORFL")
    flap_metadata_480 = candidate_480_report.get("metadata", {})
    if flap_metadata_480.get("flap_law") != "controls.flaps.hinged_trailing_edge.v1" \
            or flap_metadata_480.get("metadata_schema") != "openrc-flight-meta v9" \
            or int(flap_metadata_480.get("flap_aux_index", -1)) != int(flap_metadata.get("flap_aux_index", -2)):
        raise RuntimeError("480 Hz replay lost or changed the AV-09 flap trace contract")
    csv_check_480 = check_csv_pair(exact_480_dir / "flight.csv", candidate_480_dir / "flight.csv",
        int(flap_metadata_480["flap_aux_index"]))
    if int(exact_480_report.get("rows", -1)) != csv_check_480["rows"] \
            or int(candidate_480_report.get("rows", -1)) != csv_check_480["rows"]:
        raise RuntimeError("480 Hz replay report and CSV row counts differ")
    if float(tape.get("initial_altitude_m_above_flat_runway_datum", 0.0)) != 500.0 \
            or float(tape_480.get("initial_altitude_m_above_flat_runway_datum", 0.0)) != 500.0:
        raise RuntimeError("both rate logs must start at the declared 500 m runway-datum altitude")
    altitude_margin = {
        "runway_datum_altitude_m": 0.0,
        "minimum_required_agl_m": 100.0,
        "240_hz_gain0": altitude_envelope(CURRENT_OUT / "baseline_export" / "flight.csv"),
        "240_hz_candidate": altitude_envelope(CURRENT_OUT / "candidate_replay" / "flight.csv"),
        "480_hz_gain0": altitude_envelope(exact_480_dir / "flight.csv"),
        "480_hz_candidate": altitude_envelope(candidate_480_dir / "flight.csv"),
        "interpretation": "The tape is a high-altitude open-loop response study above a flat sea-level datum. A 100 m floor is enforced for every baseline and candidate trace; it is not a landing-path experiment.",
    }
    segment_analysis_480 = paired_segments(exact_480_dir / "flight.csv", candidate_480_dir / "flight.csv",
        tape_480, int(flap_metadata_480["flap_aux_index"]))
    segment_analysis_480_path = refinement_dir / "paired_segment_analysis.json"
    segment_analysis_480_path.write_text(json.dumps(segment_analysis_480, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    refinement = refinement_analysis({
        240: (CURRENT_OUT / "baseline_export" / "flight.csv", CURRENT_OUT / "candidate_replay" / "flight.csv"),
        480: (exact_480_dir / "flight.csv", candidate_480_dir / "flight.csv"),
    }, {240: tape, 480: tape_480}, int(flap_metadata["flap_aux_index"]))
    if not refinement.get("command_schedules_match"):
        raise RuntimeError("cannot verify same physical-time input schedule in timestep refinement")
    refinement_path = CURRENT_OUT / "timestep_refinement.json"
    refinement_path.write_text(json.dumps(refinement, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")

    manifest = {
        "evidence_step": "AV-09",
        "created_utc_date": "2026-10-15",
        "scope": "current-solver same-input-tape sensitivity pair; not a clean aircraft calibration or physical validation",
        "source_log": {"path": str(log_path.relative_to(ROOT)), "sha256": sha256(log_path), "bytes": log_path.stat().st_size},
        "tape": tape,
        "models": {
            "same-tape_baseline": {
                "path": str(baseline_model.relative_to(ROOT)), "sha256": sha256(baseline_model),
                "derivation_report": str(derivation_report.relative_to(ROOT)), "derivation_report_sha256": sha256(derivation_report),
                "generator": str(GENERATOR.relative_to(ROOT)), "generator_sha256": sha256(GENERATOR),
                "generator_input": str((ROOT / "research" / "avanti-s" / "av06" / "inputs.json").relative_to(ROOT)),
                "generator_input_sha256": sha256(ROOT / "research" / "avanti-s" / "av06" / "inputs.json"),
                "flap_aerodynamic_gain": baseline_gain,
            },
            "candidate": {"path": str(candidate.relative_to(ROOT)) if ROOT in candidate.parents else str(candidate),
                "sha256": sha256(candidate), "flap_aerodynamic_gain": candidate_gain},
        },
        "engine": exact_report.get("baseline_build", {}).get("engine", "Godot 4.7.2.stable"),
        "dt_s": exact_report.get("dt_s"),
        "solver_sha256": exact_report.get("current_solver_sha256"),
        "solver_changed": {"exact_baseline": exact_report.get("solver_changed"), "candidate": candidate_report.get("solver_changed")},
        "replay": {
            "source_export_rows": baseline_report.get("rows"),
            "baseline_exact": {"status": exact_report.get("status"), "complete": exact_report.get("complete"), "mode": exact_report.get("mode")},
            "candidate": {"status": candidate_report.get("status"), "complete": candidate_report.get("complete"),
                "mode": candidate_report.get("mode"), "comparison_method": candidate_report.get("comparison_method")},
            "paired_csv": csv_check,
            "candidate_comparison": comparison,
        },
        "time_step_refinement": {
            "rates_hz": [240, 480],
            "same_piecewise_constant_time_command_schedule": refinement["command_schedules_match"],
            "source_logs": {
                "240_hz": {"path": str(log_path.relative_to(ROOT)), "sha256": sha256(log_path), "ticks": tape["ticks"], "dt_s": tape["dt_s"]},
                "480_hz": {"path": str(log_480.relative_to(ROOT)), "sha256": sha256(log_480), "ticks": tape_480["ticks"], "dt_s": tape_480["dt_s"]},
            },
            "480_hz_replay": {
                "baseline_exact": {"status": exact_480_report.get("status"), "complete": exact_480_report.get("complete"), "mode": exact_480_report.get("mode"), "solver_changed": exact_480_report.get("solver_changed")},
                "candidate": {"status": candidate_480_report.get("status"), "complete": candidate_480_report.get("complete"), "mode": candidate_480_report.get("mode"), "solver_changed": candidate_480_report.get("solver_changed")},
                "paired_csv": csv_check_480,
            },
            "analysis_path": str(refinement_path.relative_to(ROOT)),
            "analysis_sha256": sha256(refinement_path),
            "paired_480_hz_segment_path": str(segment_analysis_480_path.relative_to(ROOT)),
            "paired_480_hz_segment_sha256": sha256(segment_analysis_480_path),
            "altitude_margin": altitude_margin,
        },
        "static_probe": {"path": str(probe_path.relative_to(ROOT)), "sha256": sha256(probe_path),
            "method": probe.get("method"), "not_physical_validation": probe.get("not_physical_validation")},
        "paired_segment_analysis": {"path": str(segment_analysis_path.relative_to(ROOT)),
            "sha256": sha256(segment_analysis_path), "segments": len(segment_analysis["segments"])},
        "outputs": {
            "source_export": "baseline_export/flight.csv + export.json",
            "exact_replay": "exact_replay/flight.csv + replay.json",
            "candidate_replay": "candidate_replay/flight.csv + replay.json",
            "comparison": "comparison.json",
            "static_model_probe": "static_model_probe.json",
            "paired_segment_analysis": "paired_segment_analysis.json",
            "480_hz_exact_replay": "refinement_480hz/exact_replay/flight.csv + replay.json",
            "480_hz_candidate_replay": "refinement_480hz/candidate_replay/flight.csv + replay.json",
            "480_hz_comparison": "refinement_480hz/comparison.json",
            "240_480_refinement": "timestep_refinement.json",
        },
    }
    manifest_path = CURRENT_OUT / "evidence_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    print(f"AV-09 paired evidence complete: {CURRENT_OUT}")
    print(f"ticks={csv_check['final_tick']}, rows={csv_check['rows']}, max_flap={csv_check['maximum_flap_fraction']:.6f}")
    print(f"solver_changed={exact_report['solver_changed']}, candidate_mode={candidate_report['mode']}")
    print(f"240/480 Hz refinement: {csv_check['final_tick']} / {csv_check_480['final_tick']} ticks; exact replay at both rates")
    return 0


CURRENT_OUT: Path

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileExistsError, FileNotFoundError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"AV-09 evidence capture failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
