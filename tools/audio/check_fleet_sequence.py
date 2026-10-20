#!/usr/bin/env python3
"""Run and quantitatively summarize native AUD-15 lifecycle WAV captures.

The Godot harness creates a real FlightSession and uses WASAPI AudioEffectCapture;
this wrapper deliberately runs one native audio process at a time.
"""

from __future__ import annotations

import argparse
import array
import json
import math
import os
import subprocess
import sys
import time
import wave
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
GODOT_DEFAULT = ROOT / ".tools" / "Godot_v4.7.2-stable_win64_console.exe"
HARNESS = Path("..") / "tools" / "audio" / "fleet_sequence.gd"
BANKS_MANIFEST = ROOT / "app" / "assets" / "audio" / "powertrains" / "BANKS.json"
EXPECTED_STAGES_FIXED = ["off", "start", "idle", "taxi", "takeoff", "flight", "landing", "rollout", "shutdown"]
EXPECTED_STAGES_ROTOR = ["off", "start", "ground_idle", "spinup", "takeoff", "flight", "landing", "settle", "shutdown"]


def run_capture(godot: Path, aircraft: str, output: Path, timeout: float) -> dict[str, Any]:
    command = [
        str(godot), "--headless", "--path", "app", "--audio-driver", "WASAPI", "--max-fps", "60",
        "--script", str(HARNESS), "--", f"--aircraft={aircraft}", f"--out={output.resolve()}",
        "--fps=60", "--scenery=off",
    ]
    started = time.monotonic()
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    elapsed = time.monotonic() - started
    log = output.with_suffix(".log")
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(result.stdout + result.stderr, encoding="utf-8")
    return {"command": command, "exit_code": result.returncode, "wall_seconds": elapsed, "log": str(log)}


def list_aircraft(godot: Path) -> list[str]:
    command = [str(godot), "--headless", "--path", "app", "--audio-driver", "WASAPI",
               "--script", str(HARNESS), "--", "--list"]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError(f"catalog listing failed ({result.returncode}):\n{result.stdout}\n{result.stderr}")
    ids = [line.split("=", 1)[1].strip() for line in result.stdout.splitlines()
           if line.startswith("FLEET_AIRCRAFT_ID=")]
    if len(ids) != 9 or len(set(ids)) != len(ids):
        raise RuntimeError(f"expected 8 fixed-wing plus the active helicopter; got {ids!r}")
    return ids


def wav_samples(path: Path) -> tuple[dict[str, Any], array.array]:
    with wave.open(str(path), "rb") as wav:
        if wav.getnchannels() != 2 or wav.getsampwidth() != 2 or wav.getcomptype() != "NONE":
            raise ValueError(f"{path}: expected uncompressed stereo PCM16")
        rate = wav.getframerate()
        frames = wav.getnframes()
        pcm = wav.readframes(frames)
    values = array.array("h")
    values.frombytes(pcm)
    if sys.byteorder != "little":
        values.byteswap()
    if len(values) != frames * 2:
        raise ValueError(f"{path}: header says {frames} frames but read {len(values) // 2}")
    return {"rate_hz": rate, "frames": frames, "seconds": frames / rate,
            "channels": 2, "bits": 16, "bytes": len(pcm)}, values


def pcm_metrics(values: array.array, rate: int, stages: list[list[Any]]) -> dict[str, Any]:
    frame_count = len(values) // 2
    intervals: list[tuple[str, int, int]] = []
    measured_stages = stages[:-1] if len(stages) > 1 and str(stages[-1][1]) == "done" else stages
    for index, entry in enumerate(measured_stages):
        start = max(0, round(float(entry[0]) * rate))
        end_s = float(measured_stages[index + 1][0]) if index + 1 < len(measured_stages) else frame_count / rate
        end = min(frame_count, max(start, round(end_s * rate)))
        intervals.append((str(entry[1]), start, end))
    stage_acc = {name: {"frames": 0, "sum_sq": 0.0, "peak": 0.0, "clipped_samples": 0,
                        "max_step": 0.0, "steps_over_0_8": 0} for name, _, _ in intervals}
    total_sq = 0.0
    peak = 0.0
    clipped = 0
    max_step = 0.0
    steps_over = 0
    previous_l: int | None = None
    previous_r: int | None = None
    stage_cursor = 0
    current_stage = intervals[0][0] if intervals else ""
    for frame in range(frame_count):
        while stage_cursor + 1 < len(intervals) and frame >= intervals[stage_cursor][2]:
            stage_cursor += 1
            current_stage = intervals[stage_cursor][0]
        left = int(values[frame * 2])
        right = int(values[frame * 2 + 1])
        a = max(abs(left), abs(right)) / 32768.0
        peak = max(peak, a)
        total_sq += (left * left + right * right) / (32768.0 * 32768.0)
        clipped_here = int(abs(left) >= 32767) + int(abs(right) >= 32767)
        clipped += clipped_here
        step = max(abs(left - previous_l), abs(right - previous_r)) / 32768.0 if previous_l is not None else 0.0
        max_step = max(max_step, step)
        step_hit = int(step >= 0.8)
        steps_over += step_hit
        if current_stage in stage_acc:
            row = stage_acc[current_stage]
            row["frames"] += 1
            row["sum_sq"] += (left * left + right * right) / (32768.0 * 32768.0)
            row["peak"] = max(float(row["peak"]), a)
            row["clipped_samples"] += clipped_here
            row["max_step"] = max(float(row["max_step"]), step)
            row["steps_over_0_8"] += step_hit
        previous_l, previous_r = left, right
    rms = math.sqrt(total_sq / max(2 * frame_count, 1))
    for name, row in stage_acc.items():
        count = max(int(row["frames"]), 1)
        row["rms_dbfs"] = dbfs(math.sqrt(float(row["sum_sq"]) / (count * 2)))
        row["peak_dbfs"] = dbfs(float(row["peak"]))
        del row["sum_sq"]
    return {"peak_linear": peak, "peak_dbfs": dbfs(peak), "rms_linear": rms, "rms_dbfs": dbfs(rms),
            "clipped_samples": clipped, "max_adjacent_frame_step": max_step, "steps_over_0_8": steps_over,
            "stage_pcm": stage_acc}


def dbfs(value: float) -> float:
    return 20.0 * math.log10(max(value, 1e-12))


def source_loop_metrics() -> list[dict[str, Any]]:
    manifest = json.loads(BANKS_MANIFEST.read_text(encoding="utf-8"))
    rows: list[dict[str, Any]] = []
    for family, entries in manifest.items():
        for entry in entries:
            asset = ROOT / "app" / "assets" / "audio" / "powertrains" / entry["file"]
            with wave.open(str(asset), "rb") as source:
                if source.getsampwidth() != 2 or source.getcomptype() != "NONE":
                    raise ValueError(f"{asset}: expected uncompressed PCM16 source")
                channels = source.getnchannels()
                rate = source.getframerate()
                frames = source.getnframes()
                source_pcm = source.readframes(frames)
            values = array.array("h")
            values.frombytes(source_pcm)
            if sys.byteorder != "little":
                values.byteswap()
            if channels < 1 or len(values) != frames * channels:
                raise ValueError(f"{asset}: invalid channel/frame count")
            if not values:
                continue
            first = [int(values[channel]) for channel in range(channels)]
            last = [int(values[-channels + channel]) for channel in range(channels)]
            endpoint_delta = max(abs(last[channel] - first[channel]) for channel in range(channels)) / 32768.0
            max_inner_step = 0.0
            p99_inner_steps: list[float] = []
            # Asset files are short; include interior adjacent-frame gaps as a seam baseline.
            for frame in range(1, frames):
                a = max(abs(int(values[frame * channels + channel] - values[(frame - 1) * channels + channel]))
                        for channel in range(channels)) / 32768.0
                max_inner_step = max(max_inner_step, a)
                p99_inner_steps.append(a)
            p99_inner_steps.sort()
            p99 = p99_inner_steps[min(len(p99_inner_steps) - 1, round((len(p99_inner_steps) - 1) * 0.99))] if p99_inner_steps else 0.0
            rows.append({"family": family, "file": str(asset.relative_to(ROOT)).replace("\\", "/"),
                         "role": entry.get("role"), "rpm": entry.get("rpm"), "rate_hz": rate,
                         "source_frames": frames, "source_seconds": frames / rate,
                         "first_to_last_gap": endpoint_delta, "interior_step_p99": p99,
                         "interior_step_max": max_inner_step,
                         "meaning": "Raw source loop-end-to-start sample gap; installed 64-frame guard supplies resampler continuation but does not claim a perceptual seam verdict."})
    return rows


def mix_diagnostics(report: dict[str, Any]) -> dict[str, Any]:
    stages: dict[str, dict[str, Any]] = {}
    for row in report.get("samples", []):
        stage = str(row.get("stage", "unknown"))
        values = row.get("audio_mix", {})
        acc = stages.setdefault(stage, {"rows": 0, "engine_gain_sum": 0.0, "engine_gain_peak": 0.0,
                                        "gear_roll_sum": 0.0, "gear_roll_peak": 0.0,
                                        "touchdown_player_frames": 0, "contact_slot_peak": 0})
        acc["rows"] += 1
        engine = float(values.get("engine_gain_model", 0.0))
        gear = float(values.get("gear_roll_gain_model_sum", 0.0))
        acc["engine_gain_sum"] += engine
        acc["engine_gain_peak"] = max(acc["engine_gain_peak"], engine)
        acc["gear_roll_sum"] += gear
        acc["gear_roll_peak"] = max(acc["gear_roll_peak"], gear)
        acc["touchdown_player_frames"] += int(values.get("gear_touchdown_players", 0) > 0)
        acc["contact_slot_peak"] = max(acc["contact_slot_peak"], int(values.get("gear_contact_slots", 0)))
    for row in stages.values():
        row["engine_gain_mean"] = row["engine_gain_sum"] / max(row["rows"], 1)
        row["gear_roll_gain_mean"] = row["gear_roll_sum"] / max(row["rows"], 1)
        del row["engine_gain_sum"], row["gear_roll_sum"]
    return {"by_stage": stages,
            "meaning": "Engine normalized level and gear roll level are runtime model diagnostics. Both route to the aircraft bus; these estimates do not isolate PCM energy or establish acoustic dominance."}


def analyze_capture(aircraft: str, output: Path, command_info: dict[str, Any]) -> dict[str, Any]:
    json_path = output.with_suffix(".json")
    wav_path = output.with_suffix(".wav")
    report = json.loads(json_path.read_text(encoding="utf-8"))
    wav, values = wav_samples(wav_path)
    stages = report.get("initial_stage_schedule", [])
    pcm = pcm_metrics(values, wav["rate_hz"], stages)
    expected = EXPECTED_STAGES_ROTOR if report.get("vehicle") == "rotorcraft" else EXPECTED_STAGES_FIXED
    actual = [str(entry[1]) for entry in stages]
    event_stages = [str(row.get("stage")) for row in report.get("events", [])]
    required_stages = actual[:-1] if actual and actual[-1] == "done" else actual
    sample_rows = report.get("samples", [])
    route_crash = any(bool(row.get("crash")) for row in sample_rows)
    route_fault = any(bool(row.get("fault")) for row in sample_rows)
    checks = {
        "native_wasapi": report.get("driver") == "WASAPI",
        "stereo_pcm16": wav["channels"] == 2 and wav["bits"] == 16,
        "duration_matches_wall_clock": abs(wav["seconds"] - float(report.get("duration_s", 0.0))) <= 0.12,
        "no_capture_overrun": int(report.get("pcm_wav", {}).get("discarded_frames", -1)) == 0,
        "no_premaster_capture_overrun": int(report.get("premaster", {}).get("discarded_frames", -1)) == 0,
        "frame_count_matches_report": wav["frames"] == int(report.get("pcm_wav", {}).get("captured_frames", -1)),
        "finite_pcm": not bool(report.get("pcm_wav", {}).get("invalid_sample_seen", True)),
        "no_pcm_clipping": pcm["clipped_samples"] == 0,
        "timeline_complete": required_stages == expected and all(stage in event_stages for stage in expected),
    }
    analysis = {
        "format": "openrc-audio-fleet-analysis-v1", "aircraft": aircraft,
        "wav": {**wav, "path": str(wav_path.resolve())}, "pcm": pcm,
        "lifecycle": {"vehicle": report.get("vehicle"), "route": report.get("route"),
                      "audio_source": report.get("audio_source"), "timeline": actual,
                      "events": report.get("events", []), "actual_runway_takeoff_observed": report.get("actual_runway_takeoff_observed"),
                      "actual_liftoff_observed": report.get("actual_liftoff_observed"),
                      "actual_rotor_liftoff_observed": report.get("actual_rotor_liftoff_observed"),
                      "actual_contact_after_landing_stage": report.get("actual_contact_after_landing_stage"),
                      "rollout_or_settle_contact_observed": report.get("rollout_or_settle_contact_observed"),
                      "staged_landing_fixture": report.get("staged_landing_fixture"),
                      "landing_fixture_message": report.get("landing_fixture_message"),
                      "contact_summary_at_end": report.get("contacts"), "notes": report.get("notes", []),
                      "fault_or_crash_observed_in_telemetry": route_fault or route_crash,
                      "fault_at_end": report.get("fault"), "crash_at_end": report.get("crash")},
        "mix_diagnostics": mix_diagnostics(report), "checks": checks,
        "capture_process": command_info,
        "limitations": "The run is production adapter PCM from a deterministic presentation/control tape, not an uninterrupted certified flight. Fixed-wing approach is staged after the live runway section. Reported liftoff/contact flags require observed session contacts; engine/gear balance is represented by normalized model diagnostics because both share the aircraft bus. Software PCM metrics do not establish human hearing, speaker response, or real-aircraft acoustic fidelity.",
    }
    analysis_path = output.with_suffix(".analysis.json")
    analysis_path.write_text(json.dumps(analysis, indent=2), encoding="utf-8")
    return analysis


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=GODOT_DEFAULT)
    parser.add_argument("--out-dir", type=Path, default=ROOT / "tmp" / "audio-aud15" / "fleet")
    parser.add_argument("--aircraft", action="append", help="limit to one or more IDs; default is all active aircraft")
    parser.add_argument("--reuse-existing", action="store_true", help="reuse an existing JSON+WAV pair after validating it")
    parser.add_argument("--timeout", type=float, default=150.0, help="wall timeout per aircraft; default allows slow native machines")
    parser.add_argument("--analyze-only", action="store_true", help="analyze existing JSON+WAV captures without launching Godot")
    args = parser.parse_args()
    godot = args.godot.resolve()
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    ids = args.aircraft or list_aircraft(godot)
    if args.aircraft:
        active_ids = set(list_aircraft(godot))
        unknown = [item for item in ids if item not in active_ids]
        if unknown:
            parser.error(f"unknown or inactive aircraft IDs: {unknown}")
    results: list[dict[str, Any]] = []
    failed = False
    for index, aircraft in enumerate(ids, start=1):
        output = out_dir / aircraft
        json_path = output.with_suffix(".json")
        wav_path = output.with_suffix(".wav")
        print(f"[{index}/{len(ids)}] {aircraft}", flush=True)
        process_info: dict[str, Any] = {"exit_code": 0, "wall_seconds": 0.0, "reused": False}
        try:
            if not args.analyze_only and not (args.reuse_existing and json_path.is_file() and wav_path.is_file()):
                process_info = run_capture(godot, aircraft, output, args.timeout)
                print(f"  native process exit={process_info['exit_code']} wall={process_info['wall_seconds']:.1f}s log={process_info['log']}", flush=True)
            else:
                process_info["reused"] = True
            if not json_path.is_file() or not wav_path.is_file():
                raise FileNotFoundError(f"expected report and WAV at {json_path} and {wav_path}")
            analysis = analyze_capture(aircraft, output, process_info)
            checks = analysis["checks"]
            capture_valid = process_info.get("exit_code", 0) == 0 and all(checks.values())
            lifecycle = analysis["lifecycle"]
            liftoff = bool(lifecycle.get("actual_liftoff_observed"))
            touchdown = bool(lifecycle.get("actual_contact_after_landing_stage"))
            rollout = bool(lifecycle.get("rollout_or_settle_contact_observed"))
            lifecycle_complete = liftoff and touchdown and (rollout or lifecycle.get("vehicle") == "rotorcraft")
            failed = failed or not capture_valid
            results.append({"aircraft": aircraft, "capture_valid": capture_valid,
                            "live_lifecycle_observed_complete": lifecycle_complete,
                            "audio_source": analysis["lifecycle"]["audio_source"],
                            "duration_s": analysis["wav"]["seconds"],
                            "peak_dbfs": analysis["pcm"]["peak_dbfs"],
                            "clipped_samples": analysis["pcm"]["clipped_samples"],
                            "max_step": analysis["pcm"]["max_adjacent_frame_step"],
                            "takeoff": lifecycle.get("actual_runway_takeoff_observed"),
                            "liftoff": liftoff,
                            "touchdown": analysis["lifecycle"]["actual_contact_after_landing_stage"],
                            "rollout": analysis["lifecycle"]["rollout_or_settle_contact_observed"],
                            "route_fault_or_crash": lifecycle["fault_or_crash_observed_in_telemetry"],
                            "checks": checks, "analysis": str(output.with_suffix(".analysis.json"))})
            print("  summary " + json.dumps(results[-1], separators=(",", ":")), flush=True)
        except (subprocess.SubprocessError, OSError, ValueError, KeyError, json.JSONDecodeError, RuntimeError) as exc:
            failed = True
            result = {"aircraft": aircraft, "capture_valid": False, "error": str(exc), "capture_process": process_info}
            results.append(result)
            print("  ERROR " + json.dumps(result), flush=True)
    aggregate = {"format": "openrc-audio-fleet-batch-v1", "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                 "godot": str(godot), "driver_requested": "WASAPI", "aircraft_count": len(ids),
                 "all_audio_captures_valid": not failed and len(results) == len(ids),
                 "all_live_lifecycles_observed_complete": len(results) == 9 and all(bool(row.get("live_lifecycle_observed_complete")) for row in results),
                 "source_loop_metrics": source_loop_metrics(), "results": results,
                 "meaning": "Audio capture validity covers native driver, file, timeline, and PCM gates. Complete-flight observations separately require observed liftoff, landing contact, and fixed-wing rollout or rotorcraft settle; the staged approach is identified explicitly."}
    summary_path = out_dir / "fleet_summary.json"
    summary_path.write_text(json.dumps(aggregate, indent=2), encoding="utf-8")
    print(f"fleet summary: {summary_path}", flush=True)
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
