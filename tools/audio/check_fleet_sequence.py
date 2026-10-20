#!/usr/bin/env python3
"""Run and quantitatively summarize native AUD-15 lifecycle WAV captures.

The Godot harness creates a real FlightSession and uses WASAPI AudioEffectCapture;
this wrapper deliberately runs one native audio process at a time.
"""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import os
import re
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
SOURCE_IDENTITY_PATHS = [
    "app/main.gd",
    "app/helicopter_main.gd",
    "app/app_state/aircraft_catalog.gd",
    "app/physics/rotorcraft_data.gd",
    "app/sim/flight_session.gd",
    "app/sim/helicopter_flight_session.gd",
    "app/sim/simulation.gd",
    "app/input/commands.gd",
    "app/audio/flight_audio.gd",
    "app/audio/helicopter_audio.gd",
    "app/audio/soundscape.gd",
    "app/audio/powertrain_audio.gd",
    "app/audio/glow_audio_pump.gd",
    "app/audio/ground_audio.gd",
    "app/audio/ground_audio_model.gd",
    "app/sim/landing_maneuver.gd",
    "app/scenery/takeoff_pilot.gd",
    "app/physics/ground_start.gd",
    "app/physics/rotorcraft/ground_start.gd",
    "app/physics/rotorcraft/skid_contact.gd",
    "app/physics/rotorcraft/lifecycle.gd",
    "app/physics/rotorcraft/flight_dynamics.gd",
    "app/physics/rotorcraft/simulation_step_adapter.gd",
    "app/physics/rotorcraft/drive.gd",
    "app/physics/rotorcraft/main_rotor_stage.gd",
    "research/landing/e3c2a/circuit_pilot.gd",
    "research/landing/e3c2a/circuit_driver.gd",
    "research/flight-test/pilot.gd",
    "tools/audio/straight_flight_pilot.gd",
    "tools/audio/helicopter_sequence_pilot.gd",
    "research/helicopter/ground_start/cycles.gd",
    "app/assets/audio/powertrains/BANKS.json",
    "app/assets/audio/powertrains/manifest.json",
    "app/assets/audio/landing_gear/manifest.json",
    "tools/audio/fleet_sequence.gd",
    "tools/audio/check_fleet_sequence.py",
]


def source_identity() -> dict[str, str | None]:
    identity: dict[str, str | None] = {}
    for relative in SOURCE_IDENTITY_PATHS:
        path = ROOT / relative
        identity[relative] = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
    return identity


def source_identity_complete(identity: dict[str, str | None]) -> bool:
    return all(identity.get(relative) is not None for relative in SOURCE_IDENTITY_PATHS)


def existing_capture_is_reusable(output: Path) -> bool:
    analysis_path = output.with_suffix(".analysis.json")
    if not analysis_path.is_file() or not output.with_suffix(".json").is_file() or not output.with_suffix(".wav").is_file():
        return False
    try:
        analysis = json.loads(analysis_path.read_text(encoding="utf-8"))
        process = analysis.get("capture_process", {})
        identity = analysis.get("source_identity", {})
        return (process.get("exit_code") == 0 and process.get("source_files_unchanged") is True and
                process.get("source_identity_complete") is True and
                identity.get("before") == identity.get("after") == source_identity() and
                all(value is True for value in analysis.get("checks", {}).values()))
    except (OSError, ValueError, AttributeError):
        return False


def run_capture(godot: Path, aircraft: str, output: Path, timeout: float, wall_timeout: float,
                continuous: bool = False, continuous_straight: bool = False,
                continuous_helicopter: bool = False,
                post_landing_soak: float = 0.0) -> dict[str, Any]:
    command = [
        str(godot), "--headless", "--path", "app", "--audio-driver", "WASAPI", "--max-fps", "60",
        "--script", str(HARNESS), "--", f"--aircraft={aircraft}", f"--out={output.resolve()}",
        "--fps=60", "--scenery=off", f"--wall-timeout={wall_timeout:g}",
    ]
    if continuous:
        command.append("--continuous")
    if continuous_straight:
        command.append("--continuous-straight")
    if continuous_helicopter:
        command.append("--continuous-helicopter")
    if post_landing_soak > 0.0:
        command.append(f"--post-landing-soak={post_landing_soak:g}")
    source_before = source_identity()
    started = time.monotonic()
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    elapsed = time.monotonic() - started
    source_after = source_identity()
    log = output.with_suffix(".log")
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(result.stdout + result.stderr, encoding="utf-8")
    return {"command": command, "exit_code": result.returncode, "wall_seconds": elapsed, "log": str(log),
            "source_identity_before": source_before, "source_identity_after": source_after,
            "source_files_unchanged": source_before == source_after,
            "source_identity_complete": source_identity_complete(source_before) and source_identity_complete(source_after)}


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


def pcm_metrics(values: array.array, rate: int, stages: list[dict[str, Any]]) -> dict[str, Any]:
    frame_count = len(values) // 2
    intervals: list[tuple[str, int, int]] = []
    measured_stages = stages[:-1] if len(stages) > 1 and str(stages[-1].get("stage")) == "done" else stages
    for index, entry in enumerate(measured_stages):
        start = max(0, round(float(entry["time_s"]) * rate))
        end_s = float(stages[index + 1]["time_s"]) if index + 1 < len(stages) else frame_count / rate
        end = min(frame_count, max(start, round(end_s * rate)))
        intervals.append((str(entry["stage"]), start, end))
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


def configured_physics_hz() -> float:
    project = ROOT / "app" / "project.godot"
    match = re.search(r"(?m)^common/physics_ticks_per_second=(\d+)\s*$",
                      project.read_text(encoding="utf-8"))
    return float(match.group(1)) if match else 0.0


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
        acc = stages.setdefault(stage, {"rows": 0, "engine_gain_rows": 0, "engine_gain_sum": 0.0, "engine_gain_peak": 0.0,
                                        "gear_roll_sum": 0.0, "gear_roll_peak": 0.0,
                                        "touchdown_player_frames": 0, "contact_slot_peak": 0})
        acc["rows"] += 1
        engine_available = bool(values.get("engine_gain_available", "engine_gain_model" in values))
        engine = float(values.get("engine_gain_model", 0.0))
        gear = float(values.get("gear_roll_gain_model_sum", 0.0))
        if engine_available:
            acc["engine_gain_rows"] += 1
            acc["engine_gain_sum"] += engine
            acc["engine_gain_peak"] = max(acc["engine_gain_peak"], engine)
        acc["gear_roll_sum"] += gear
        acc["gear_roll_peak"] = max(acc["gear_roll_peak"], gear)
        acc["touchdown_player_frames"] += int(values.get("gear_touchdown_players", 0) > 0)
        acc["contact_slot_peak"] = max(acc["contact_slot_peak"], int(values.get("gear_contact_slots", 0)))
    for row in stages.values():
        row["engine_gain_mean"] = row["engine_gain_sum"] / row["engine_gain_rows"] if row["engine_gain_rows"] else None
        row["engine_gain_peak"] = row["engine_gain_peak"] if row["engine_gain_rows"] else None
        row["gear_roll_gain_mean"] = row["gear_roll_sum"] / max(row["rows"], 1)
        del row["engine_gain_sum"], row["gear_roll_sum"]
    return {"by_stage": stages,
            "meaning": "Engine normalized level and gear roll level are runtime model diagnostics. Both route to the aircraft bus; these estimates do not isolate PCM energy or establish acoustic dominance."}


def pcm_clock_diagnostics(report: dict[str, Any], rate_hz: int, wav_frames: int) -> dict[str, Any]:
    series: list[dict[str, Any]] = []
    for kind, rows in (("event", report.get("events", [])), ("telemetry", report.get("samples", []))):
        for row in rows:
            clock = row.get("pcm_clock") if isinstance(row, dict) else None
            if not isinstance(clock, dict):
                continue
            series.append({"kind": kind, "stage": row.get("stage"),
                           "wall_elapsed_s": float(clock.get("wall_elapsed_s", row.get("t", row.get("time_s", 0.0)))),
                           "master_captured_frames": int(clock.get("master_captured_frames", 0)),
                           "premaster_captured_frames": int(clock.get("premaster_captured_frames", 0)),
                           "master_frame_lag_ms": float(clock.get("master_frame_lag_ms", 0.0)),
                           "premaster_frame_lag_ms": float(clock.get("premaster_frame_lag_ms", 0.0))})
    series.sort(key=lambda row: (row["wall_elapsed_s"], row["kind"]))
    telemetry = [row for row in series if row["kind"] == "telemetry"]
    lag_values = [float(row["master_frame_lag_ms"]) for row in telemetry]
    slope_ms_per_s: float | None = None
    if len(telemetry) >= 2:
        times = [float(row["wall_elapsed_s"]) for row in telemetry]
        mean_t = sum(times) / len(times)
        mean_lag = sum(lag_values) / len(lag_values)
        variance_t = sum((value - mean_t) ** 2 for value in times)
        if variance_t > 1e-12:
            slope_ms_per_s = sum((times[i] - mean_t) * (lag_values[i] - mean_lag)
                                 for i in range(len(times))) / variance_t
    final = report.get("pcm_clock", {})
    if not isinstance(final, dict):
        final = {}
    final_wall = float(final.get("wall_elapsed_s", report.get("duration_s", 0.0)))
    expected_frames = round(final_wall * rate_hz)
    final_lag_ms = 1000.0 * (expected_frames - wav_frames) / max(rate_hz, 1)
    return {"mix_rate_hz": rate_hz, "sample_count": len(telemetry),
            "first_master_lag_ms": lag_values[0] if lag_values else None,
            "last_master_lag_ms": lag_values[-1] if lag_values else None,
            "min_master_lag_ms": min(lag_values) if lag_values else None,
            "max_master_lag_ms": max(lag_values) if lag_values else None,
            "master_lag_slope_ms_per_s": slope_ms_per_s,
            "final_report_wall_elapsed_s": final_wall,
            "wav_seconds": wav_frames / max(rate_hz, 1),
            "final_wav_minus_wall_ms": 1000.0 * (wav_frames / max(rate_hz, 1) - final_wall),
            "final_expected_minus_wav_frames": expected_frames - wav_frames,
            "final_expected_minus_wav_ms": final_lag_ms,
            "series": series,
            "meaning": "Cumulative AudioEffectCapture frames compared with wall-clock expected mix frames. This can localize accumulating capture-clock loss or a discrete gap; it is not measured hardware output latency."}


def stage_spans(sample_rows: list[dict[str, Any]], physics_hz: float) -> dict[str, Any]:
    by_stage: dict[str, dict[str, Any]] = {}
    for row in sample_rows:
        name = str(row.get("stage", "unknown"))
        epoch = int(row.get("session_epoch", 0))
        key = f"{name}@epoch{epoch}"
        tick = int(row.get("tick", -1))
        accepted_time = row.get("sim_time_s")
        if accepted_time is None and tick >= 0 and physics_hz > 0.0:
            accepted_time = tick / physics_hz
        span = by_stage.setdefault(key, {"stage": name, "session_epoch": epoch,
                                          "rows": 0, "wall_start_s": float(row.get("t", 0.0)),
                                          "wall_end_s": float(row.get("t", 0.0)),
                                          "tick_min": tick, "tick_max": tick,
                                          "sequence_time_min_s": float(row.get("sequence_time_s", 0.0)),
                                          "sequence_time_max_s": float(row.get("sequence_time_s", 0.0)),
                                          "sim_time_min_s": accepted_time, "sim_time_max_s": accepted_time})
        span["rows"] += 1
        span["wall_end_s"] = float(row.get("t", span["wall_end_s"]))
        span["sequence_time_min_s"] = min(float(span["sequence_time_min_s"]), float(row.get("sequence_time_s", span["sequence_time_min_s"])))
        span["sequence_time_max_s"] = max(float(span["sequence_time_max_s"]), float(row.get("sequence_time_s", span["sequence_time_max_s"])))
        if tick >= 0:
            span["tick_min"] = min(int(span["tick_min"]), tick) if int(span["tick_min"]) >= 0 else tick
            span["tick_max"] = max(int(span["tick_max"]), tick)
        if accepted_time is not None:
            value = float(accepted_time)
            span["sim_time_min_s"] = value if span["sim_time_min_s"] is None else min(float(span["sim_time_min_s"]), value)
            span["sim_time_max_s"] = value if span["sim_time_max_s"] is None else max(float(span["sim_time_max_s"]), value)
    return {"physics_ticks_per_second": physics_hz, "by_stage": by_stage,
            "meaning": "Each observed phase is reported per session epoch so fixture resets do not merge unrelated tick/time ranges. Wall spans use monotonic capture time; sequence spans advance from accepted FlightSession ticks."}


def analyze_capture(aircraft: str, output: Path, command_info: dict[str, Any]) -> dict[str, Any]:
    json_path = output.with_suffix(".json")
    wav_path = output.with_suffix(".wav")
    report = json.loads(json_path.read_text(encoding="utf-8"))
    wav, values = wav_samples(wav_path)
    events = report.get("events", [])
    observed_stages = [{"stage": str(row.get("stage", "")), "time_s": float(row.get("time_s", 0.0))}
                       for row in events if isinstance(row, dict)]
    pcm = pcm_metrics(values, wav["rate_hz"], observed_stages)
    route_mode = str(report.get("route_mode", "staged-presentation"))
    continuous_mode = route_mode == "continuous"
    continuous_straight = str(report.get("route", "")) == "continuous-ft-card-v5-straight-ahead"
    continuous_helicopter = str(report.get("route", "")) == "continuous-heli20-ground-hover-cycle"
    expected = (list(report.get("expected_stage_order", [])) if continuous_mode else
                (EXPECTED_STAGES_ROTOR if report.get("vehicle") == "rotorcraft" else EXPECTED_STAGES_FIXED))
    schedule = report.get("initial_stage_schedule", [])
    actual = [str(entry[1]) for entry in schedule]
    event_stages = [str(row.get("stage")) for row in events]
    required_stages = expected if continuous_mode else (actual[:-1] if actual and actual[-1] == "done" else actual)
    ordered_events = [stage for stage in event_stages if stage != "done"]
    sample_rows = report.get("samples", [])
    route_failure = report.get("route_failure", {})
    route_crash = bool(route_failure.get("crash_observed")) or any(bool(row.get("crash")) for row in sample_rows)
    route_fault = bool(route_failure.get("fault_observed")) or any(bool(row.get("fault")) for row in sample_rows)
    physics_hz = float(report.get("physics_ticks_per_second") or configured_physics_hz())
    premaster = report.get("premaster", {})
    glow_generator = report.get("glow_generator", {})
    source_is_glow_generator = bool(report.get("audio_source", {}).get("fallback"))
    running_rpm_seen = any(bool(row.get("running")) and float(row.get("rpm", 0.0)) > 100.0 for row in sample_rows)
    godot_log_path = output.with_suffix(".log")
    godot_log = godot_log_path.read_text(encoding="utf-8", errors="replace") if godot_log_path.is_file() else ""
    godot_log_errors = [line.strip() for line in godot_log.splitlines()
                        if any(marker in line.lower() for marker in ("error:", "script error:", "parse error",
                                                                      "failed to load script", "fleet sequence startup refused"))]
    useful_signal = pcm["peak_dbfs"] > -70.0 and running_rpm_seen
    premaster_finite = (not bool(premaster.get("invalid_sample_seen"))
                        if "invalid_sample_seen" in premaster else None)
    premaster_below_unity = (int(premaster.get("over_unity_samples", -1)) == 0
                             if "over_unity_samples" in premaster else None)
    if source_is_glow_generator and not glow_generator:
        generator_source_health = None
    elif source_is_glow_generator:
        generator_source_health = (bool(glow_generator.get("skip_counter_supported")) and
                                   int(glow_generator.get("positive_skip_delta_sum", -1)) == 0)
    else:
        generator_source_health = True
    source_files_unchanged = command_info.get("source_files_unchanged")
    aircraft_identity = report.get("aircraft_identity", {})
    if report.get("vehicle") == "rotorcraft":
        input_sha = str(aircraft_identity.get("input_sha256", ""))
        identity_hashes_valid = (len(input_sha) == 64 and
                                 all(character in "0123456789abcdef" for character in input_sha.lower()) and
                                 aircraft_identity.get("identity_contract") == "rotorcraft-input-and-law-v1" and
                                 bool(aircraft_identity.get("model_law")) and
                                 bool(aircraft_identity.get("lifecycle_law")) and
                                 aircraft_identity.get("launch_choice") == "ground" and
                                 isinstance(aircraft_identity.get("accepted_weather"), dict) and
                                 bool(aircraft_identity.get("pad")))
    else:
        input_sha = str(aircraft_identity.get("input_file_sha256", ""))
        semantic_sha = str(aircraft_identity.get("semantic_data_sha256", ""))
        identity_hashes_valid = (len(input_sha) == 64 and len(semantic_sha) == 64 and
                                 all(character in "0123456789abcdef" for character in input_sha.lower()) and
                                 all(character in "0123456789abcdef" for character in semantic_sha.lower()))
    checks = {
        "source_identity_complete_during_capture": command_info.get("source_identity_complete"),
        "source_files_unchanged_during_capture": source_files_unchanged,
        "native_wasapi": report.get("driver") == "WASAPI",
        "stereo_pcm16": wav["channels"] == 2 and wav["bits"] == 16,
        "duration_matches_wall_clock": abs(wav["seconds"] - float(report.get("duration_s", 0.0))) <= 0.12,
        "no_capture_overrun": int(report.get("pcm_wav", {}).get("discarded_frames", -1)) == 0,
        "no_premaster_capture_overrun": int(report.get("premaster", {}).get("discarded_frames", -1)) == 0,
        "frame_count_matches_report": wav["frames"] == int(report.get("pcm_wav", {}).get("captured_frames", -1)),
        "finite_pcm": not bool(report.get("pcm_wav", {}).get("invalid_sample_seen", True)),
        "no_pcm_clipping": pcm["clipped_samples"] == 0,
        "useful_signal_and_running_rpm": useful_signal,
        "aircraft_data_identity_recorded": identity_hashes_valid,
        "premaster_finite": premaster_finite,
        "no_premaster_overunity": premaster_below_unity,
        "no_script_or_parse_errors": not godot_log_errors,
        "timeline_complete": (ordered_events == expected if continuous_mode else
                              required_stages == expected and all(stage in event_stages for stage in expected)),
        "glow_generator_counter_clean_when_applicable": generator_source_health,
    }
    liftoff = bool(report.get("actual_liftoff_observed"))
    touchdown = bool(report.get("actual_contact_after_landing_stage"))
    rollout = bool(report.get("rollout_or_settle_contact_observed"))
    contact_sequence_complete = liftoff and touchdown and (rollout or report.get("vehicle") == "rotorcraft")
    no_route_failure = not route_crash and not route_fault
    staged_landing = bool(report.get("staged_landing_fixture"))
    staged_flight = bool(report.get("staged_flight_fixture"))
    live_contact_sequence_complete = contact_sequence_complete and no_route_failure and not staged_landing and not staged_flight
    continuous_flight_qualified = (continuous_mode and bool(report.get("continuous_route_completed")) and
                                   live_contact_sequence_complete and int(report.get("session_epochs", 0)) == 1 and
                                   checks["timeline_complete"])
    analysis = {
        "format": "openrc-audio-fleet-analysis-v1", "aircraft": aircraft,
        "wav": {**wav, "path": str(wav_path.resolve())}, "pcm": pcm,
        "lifecycle": {"vehicle": report.get("vehicle"), "route": report.get("route"), "route_mode": route_mode,
                      "audio_source": report.get("audio_source"), "timeline": actual,
                      "expected_stage_order": expected, "continuous_pilot": report.get("continuous_pilot"),
                      "continuous_takeoff_pilot": report.get("continuous_takeoff_pilot"),
                      "continuous_takeoff_handoff": report.get("continuous_takeoff_handoff"),
                      "continuous_takeoff_separated": report.get("continuous_takeoff_separated"),
                      "continuous_takeoff_timeout_reached": report.get("continuous_takeoff_timeout_reached"),
                      "continuous_route_kind": report.get("continuous_route_kind"),
                      "continuous_pilot_status": report.get("continuous_pilot_status"),
                      "continuous_pilot_failure_reason": report.get("continuous_pilot_failure_reason"),
                      "sequence_interrupted_by_pilot_failure": report.get("sequence_interrupted_by_pilot_failure"),
                      "continuous_post_landing_soak_s": report.get("continuous_post_landing_soak_s"),
                      "continuous_post_landing_soak_elapsed_s": report.get("continuous_post_landing_soak_elapsed_s"),
                      "continuous_control_semantics": report.get("continuous_control_semantics"),
                      "aircraft_identity": aircraft_identity,
                      "continuous_route_completed": report.get("continuous_route_completed"),
                      "events": report.get("events", []), "actual_runway_takeoff_observed": report.get("actual_runway_takeoff_observed"),
                      "actual_liftoff_observed": report.get("actual_liftoff_observed"),
                      "actual_rotor_liftoff_observed": report.get("actual_rotor_liftoff_observed"),
                      "actual_contact_after_landing_stage": report.get("actual_contact_after_landing_stage"),
                      "rollout_or_settle_contact_observed": report.get("rollout_or_settle_contact_observed"),
                      "staged_landing_fixture": report.get("staged_landing_fixture"),
                      "staged_flight_fixture": staged_flight,
                      "staged_flight_fixture_message": report.get("staged_flight_fixture_message"),
                      "landing_fixture_message": report.get("landing_fixture_message"),
                      "route_failure": route_failure,
                      "accepted_sequence_s": report.get("accepted_sequence_s"),
                      "wall_timeout_reached": report.get("wall_timeout_reached"),
                      "sequence_interrupted_by_route_failure": report.get("sequence_interrupted_by_route_failure"),
                      "contact_summary_at_end": report.get("contacts"), "notes": report.get("notes", []),
                      "fault_or_crash_observed_in_telemetry": route_fault or route_crash,
                      "fault_at_end": report.get("fault"), "crash_at_end": report.get("crash"),
                      "live_contact_sequence_complete_without_route_failure": live_contact_sequence_complete,
                      "continuous_flight_qualified": continuous_flight_qualified,
                      "continuous_flight_exclusion_reason": ("this was a staged-presentation capture, not a continuous route" if not continuous_mode else
                                                              "continuous pilot route did not report completion" if not report.get("continuous_route_completed") else
                                                              "runway flight was replaced by a staged airborne fixture" if staged_flight else
                                                              "landing approach fixture resets fixed-wing session" if staged_landing else
                                                              "route crash or simulation fault observed" if not no_route_failure else
                                                              "liftoff, landing contact, or rollout/settle not observed" if not contact_sequence_complete else "qualified")},
        "accepted_stage_spans": stage_spans(sample_rows, physics_hz),
        "glow_generator": glow_generator,
        "pcm_clock": pcm_clock_diagnostics(report, wav["rate_hz"], wav["frames"]),
        "godot_log_errors": godot_log_errors,
        "mix_diagnostics": mix_diagnostics(report), "checks": checks,
        "capture_process": command_info,
        "source_identity": {"before": command_info.get("source_identity_before"),
                            "after": command_info.get("source_identity_after"),
                            "files": SOURCE_IDENTITY_PATHS},
        "limitations": (("This continuous helicopter route reuses the HELI-20 X-Cell ground-start, spool, bounded hover, touchdown, collective reduction, coast, and disarm sequence in one FlightSession. Its identity uses the exact rotorcraft input-byte SHA-256 plus the recorded rotorcraft model/lifecycle laws, start, pad, weather, and hashed runtime sources; the loader defines no semantic-data hash. It is limited to xcell-60-research and does not claim wheeled taxi or rollout. Software evidence is not physical validation, and aircraft/ground audio remain on a shared bus." if continuous_helicopter else
                       "This continuous straight route uses the research FT-card-v5 takeoff, climb, approach, flare, and rollout laws in one FlightSession. It lands straight ahead on clear terrain beyond the runway; it is not a runway-return circuit. Software evidence is not physical validation, and the aircraft/ground audio remain on a shared bus." if continuous_straight else
                       "This continuous run uses the Stik-tuned TakeoffPilot until observed gear separation, then the experimental E3c2a circuit pilot in one FlightSession; neither pilot is generalized to other aircraft. It remains software evidence, not physical validation. Engine and gear share the aircraft bus, so diagnostics do not isolate their PCM energy.") if continuous_mode else
                       "The run is production adapter PCM from a deterministic presentation/control tape, not an uninterrupted flight. Fixed-wing approach is staged after the live runway section, and an airborne segment can also be staged if the runway pilot does not lift off. Reported liftoff/contact flags require observed session contacts; engine/gear balance is represented by normalized model diagnostics because both share the aircraft bus. Software PCM metrics do not establish human hearing, speaker response, or real-aircraft acoustic fidelity."),
    }
    analysis_path = output.with_suffix(".analysis.json")
    analysis_path.write_text(json.dumps(analysis, indent=2), encoding="utf-8")
    return analysis


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=GODOT_DEFAULT)
    parser.add_argument("--out-dir", type=Path, default=ROOT / "tmp" / "audio-aud15" / "fleet-v2")
    parser.add_argument("--aircraft", action="append", help="limit to one or more IDs; default is all active aircraft")
    parser.add_argument("--continuous", action="store_true", help="run one Stik-family capture with a takeoff-to-E3c2a pilot handoff and no session reset")
    parser.add_argument("--continuous-straight", action="store_true", help="run one fixed-wing FT-card-v5 straight-ahead takeoff-to-terrain-landing route without a session reset")
    parser.add_argument("--continuous-helicopter", action="store_true", help="run the X-Cell HELI-20 ground-start/hover/touchdown/coast cycle in one session")
    parser.add_argument("--post-landing-soak", type=float, default=0.0, help="accepted seconds to keep the completed straight-ahead route alive on rollout before shutdown")
    parser.add_argument("--reuse-existing", action="store_true", help="reuse an existing JSON+WAV pair after validating it")
    parser.add_argument("--timeout", type=float, default=420.0, help="outer wall timeout per aircraft; should exceed --wall-timeout")
    parser.add_argument("--wall-timeout", type=float, default=360.0, help="maximum wall seconds for the accepted-tick sequence")
    parser.add_argument("--analyze-only", action="store_true", help="analyze existing JSON+WAV captures without launching Godot")
    args = parser.parse_args()
    continuous_modes = (args.continuous, args.continuous_straight, args.continuous_helicopter)
    if sum(continuous_modes) > 1:
        parser.error("choose only one continuous pilot mode")
    if args.post_landing_soak < 0.0 or (args.post_landing_soak > 0.0 and not args.continuous_straight):
        parser.error("--post-landing-soak must be nonnegative and requires --continuous-straight")
    if any(continuous_modes) and (not args.aircraft or len(args.aircraft) != 1):
        parser.error("a continuous pilot mode requires exactly one explicit --aircraft ID")
    if args.continuous_helicopter and args.aircraft != ["xcell-60-research"]:
        parser.error("--continuous-helicopter is limited to --aircraft=xcell-60-research")
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
            reusable = args.reuse_existing and existing_capture_is_reusable(output)
            if args.analyze_only or reusable:
                if analysis_path := output.with_suffix(".analysis.json"):
                    if analysis_path.is_file():
                        prior_analysis = json.loads(analysis_path.read_text(encoding="utf-8"))
                        process_info = dict(prior_analysis.get("capture_process", process_info))
                process_info["reused"] = True
            else:
                process_info = run_capture(godot, aircraft, output, args.timeout, args.wall_timeout,
                                           args.continuous, args.continuous_straight,
                                           args.continuous_helicopter, args.post_landing_soak)
                print(f"  native process exit={process_info['exit_code']} wall={process_info['wall_seconds']:.1f}s log={process_info['log']}", flush=True)
            if not json_path.is_file() or not wav_path.is_file():
                raise FileNotFoundError(f"expected report and WAV at {json_path} and {wav_path}")
            analysis = analyze_capture(aircraft, output, process_info)
            checks = analysis["checks"]
            capture_valid = process_info.get("exit_code", 0) == 0 and all(value is True for value in checks.values())
            lifecycle = analysis["lifecycle"]
            liftoff = bool(lifecycle.get("actual_liftoff_observed"))
            touchdown = bool(lifecycle.get("actual_contact_after_landing_stage"))
            rollout = bool(lifecycle.get("rollout_or_settle_contact_observed"))
            contact_sequence_complete = liftoff and touchdown and (rollout or lifecycle.get("vehicle") == "rotorcraft")
            continuous_flight_qualified = bool(lifecycle.get("continuous_flight_qualified"))
            failed = failed or not capture_valid
            results.append({"aircraft": aircraft, "capture_valid": capture_valid,
                            "live_contact_sequence_complete_without_route_failure": lifecycle.get("live_contact_sequence_complete_without_route_failure"),
                            "continuous_flight_qualified": continuous_flight_qualified,
                            "route_mode": lifecycle.get("route_mode"),
                            "continuous_route_kind": lifecycle.get("continuous_route_kind"),
                            "aircraft_identity": lifecycle.get("aircraft_identity"),
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
                            "route_failure": lifecycle.get("route_failure"),
                            "accepted_sequence_s": lifecycle.get("accepted_sequence_s"),
                            "wall_timeout_reached": lifecycle.get("wall_timeout_reached"),
                            "sequence_interrupted_by_route_failure": lifecycle.get("sequence_interrupted_by_route_failure"),
                            "unmeasured_checks": [name for name, value in checks.items() if value is None],
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
                 "all_live_contact_sequences_complete_without_route_failure": len(results) == 9 and all(bool(row.get("live_contact_sequence_complete_without_route_failure")) for row in results),
                 "all_continuous_flights_qualified": len(results) == 9 and all(bool(row.get("continuous_flight_qualified")) for row in results),
                  "continuous_mode": any(continuous_modes),
                 "source_loop_metrics": source_loop_metrics(), "results": results,
                 "meaning": "Audio capture validity covers measured native driver, file, useful signal, logs, timeline, and PCM gates. A null check is explicitly unmeasured and is listed per aircraft; this does not count as positive evidence. Contact-sequence observations require liftoff, landing contact, and fixed-wing rollout or rotorcraft settle with no route failure. Continuous-flight qualification also excludes staged landing fixtures."}
    summary_path = out_dir / "fleet_summary.json"
    summary_path.write_text(json.dumps(aggregate, indent=2), encoding="utf-8")
    print(f"fleet summary: {summary_path}", flush=True)
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
