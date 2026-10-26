"""Check AUD-16 native bench signals; these gates do not replace listening."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import string
from pathlib import Path
import wave

import numpy as np


def read_wave(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as wav:
        if wav.getnchannels() != 2 or wav.getsampwidth() != 2:
            raise ValueError(f"Expected stereo PCM16: {path}")
        rate = wav.getframerate()
        pcm = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").reshape(-1, 2)
    return pcm.astype(np.float64) / 32768.0, rate


def rms_db(samples: np.ndarray) -> float:
    return 20 * np.log10(max(float(np.sqrt(np.mean(samples ** 2))), 1e-12)) if samples.size else -240.0


def finite_positive(value: object) -> bool:
    try:
        number = float(value)
    except (TypeError, ValueError, OverflowError):
        return False
    return math.isfinite(number) and number > 0.0


def is_sha256(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(char in string.hexdigits for char in value)


def check_bookkeeping(report: dict, stages: list[dict], failures: list[str]) -> None:
    bookkeeping = report.get("capture_bookkeeping")
    if not isinstance(bookkeeping, dict):
        failures.append("Capture frame bookkeeping is missing")
        return
    fields = ("pushed_frames", "recorded_frames", "flushed_frames", "truncated_frames",
              "overflow_discarded_frames", "unaccounted_pushed_frames")
    if any(not isinstance(bookkeeping.get(field), int) or bookkeeping[field] < 0 for field in fields):
        failures.append("Capture frame bookkeeping contains invalid counts")
        return
    if not isinstance(bookkeeping.get("buffer_length_frames"), int) or bookkeeping["buffer_length_frames"] <= 0:
        failures.append("Capture ring-buffer length is missing or invalid")
    final = bookkeeping.get("final")
    initial = bookkeeping.get("initial")
    if not isinstance(initial, dict) or not isinstance(final, dict):
        failures.append("Capture counter endpoints are missing")
        return
    endpoint_fields = ("pushed_frames", "discarded_frames")
    if any(not isinstance(initial.get(field), int) or not isinstance(final.get(field), int)
           for field in endpoint_fields):
        failures.append("Capture counter endpoints contain invalid counts")
        return
    if not isinstance(initial.get("available_frames"), int) or initial["available_frames"] < 0:
        failures.append("Capture initial buffer count is missing or invalid")
        return
    pushed = bookkeeping["pushed_frames"]
    recorded = bookkeeping["recorded_frames"]
    flushed = bookkeeping["flushed_frames"]
    truncated = bookkeeping["truncated_frames"]
    overflow = bookkeeping["overflow_discarded_frames"]
    pending = final.get("available_frames_after_flush")
    if not isinstance(pending, int) or pending < 0:
        failures.append("Capture final buffer count is missing or invalid")
        return
    unaccounted = pushed - recorded - flushed - truncated - pending
    if unaccounted != bookkeeping["unaccounted_pushed_frames"] or unaccounted != 0:
        failures.append("Capture pushed/recorded/flushed frame counts do not balance")
    if pending != 0:
        failures.append("Capture buffer was not empty after final drain")
    if truncated != 0:
        failures.append("Capture exceeded the staged PCM memory bound")
    if recorded != sum(int(stage.get("frames", 0)) for stage in stages):
        failures.append("Capture bookkeeping recorded-frame count differs from stages")
    if overflow != report.get("discarded_frames"):
        failures.append("Capture bookkeeping overflow count differs from report")
    stage_boundary_flushed = sum(int(stage.get("flushed_frames_before_stage", 0)) for stage in stages)
    cleanup_flushed = final.get("flushed_frames")
    if not isinstance(cleanup_flushed, int) or stage_boundary_flushed + cleanup_flushed != flushed:
        failures.append("Capture flushed-frame count differs from stage and cleanup counts")
    pending_before_flush = final.get("available_frames_before_flush")
    if (not isinstance(cleanup_flushed, int) or not isinstance(pending_before_flush, int)
            or cleanup_flushed != pending_before_flush):
        failures.append("Capture cleanup buffer count differs from flushed frames")
    if final["pushed_frames"] - initial["pushed_frames"] != pushed:
        failures.append("Capture pushed-frame endpoints do not match their delta")
    if final["discarded_frames"] - initial["discarded_frames"] != overflow:
        failures.append("Capture overflow endpoints do not match their delta")
    if not report.get("capture_effect_removed", False):
        failures.append("Capture effect was not removed after recording")


def analyze(directory: Path) -> dict:
    report = json.loads((directory / "report.json").read_text(encoding="utf-8"))
    failures: list[str] = []
    profiles: dict[str, dict] = {}
    recordings: dict[tuple[str, str], tuple[np.ndarray, int]] = {}
    stages = report["stage_results"]
    if report["driver"].lower() == "dummy":
        failures.append("Dummy driver cannot qualify signal output")
    capture_wall = report.get("capture_wall_seconds")
    scripted_wall = report.get("scripted_wall_seconds")
    captured_seconds = report.get("captured_seconds")
    if not finite_positive(capture_wall):
        failures.append("Capture wall time is missing, non-finite, or non-positive")
    if not finite_positive(scripted_wall):
        failures.append("Scripted wall time is missing, non-finite, or non-positive")
    elif finite_positive(capture_wall) and abs(float(capture_wall) - float(scripted_wall)) > 1e-6:
        failures.append("Capture wall time differs from scripted wall-time total")
    if not finite_positive(captured_seconds):
        failures.append("Captured PCM duration is missing, non-finite, or non-positive")
    if (report.get("discarded_frames", 0)
            or not finite_positive(capture_wall)
            or not finite_positive(captured_seconds)
            or abs(float(captured_seconds) - float(capture_wall)) > 0.12):
        failures.append("Capture timing/drop gate failed")
    check_bookkeeping(report, stages, failures)
    if not is_sha256(report.get("probe_sha256")):
        failures.append("Capture probe source hash is missing or invalid")
    bookkeeping = report.get("capture_bookkeeping")
    if not isinstance(bookkeeping, dict):
        bookkeeping = {}
    memory_limit_seconds = bookkeeping.get("staged_capture_memory_limit_seconds")
    if not finite_positive(memory_limit_seconds):
        failures.append("Staged PCM memory bound is missing or invalid")
    elif finite_positive(report.get("mix_rate_hz")):
        recorded_frames = bookkeeping.get("recorded_frames")
        if (isinstance(recorded_frames, int) and recorded_frames >= 0
                and recorded_frames / float(report["mix_rate_hz"]) > float(memory_limit_seconds)):
            failures.append("Staged PCM exceeded its declared memory bound")
    if len(stages) != 40:
        failures.append("Expected ten stages for each of four profile combinations")
    total_wave_seconds = 0.0
    for stage in stages:
        profile, name = stage["profile"], stage["name"]
        samples, rate = read_wave(directory / profile / (name + ".wav"))
        recordings[profile, name] = samples, rate
        if rate > 0:
            stage_seconds = len(samples) / rate
            total_wave_seconds += stage_seconds
            stage_wall = stage.get("wall_seconds")
            if not finite_positive(stage_wall):
                failures.append(f"{profile}/{name}: stage wall time is missing or invalid")
            elif abs(stage_seconds - float(stage_wall)) > 0.12:
                failures.append(f"{profile}/{name}: captured stage duration differs from wall time by over 120 ms")
        if len(samples) != stage["frames"] or rate != stage["mix_rate_hz"]:
            failures.append(f"{profile}/{name}: captured shape differs from report")
        if samples.size and np.max(np.abs(samples)) >= 1.0 - 1.0 / 32768.0:
            failures.append(f"{profile}/{name}: full-scale PCM rail")
        if stage["max_motion_voice_count"] > 6 or stage["max_event_voice_count"] > 2:
            failures.append(f"{profile}/{name}: voice cap exceeded")
        if stage["timed_out"]:
            failures.append(f"{profile}/{name}: stage timed out")
        profiles.setdefault(profile, {})[name] = {"rms_dbfs": rms_db(samples)}
    if finite_positive(capture_wall) and abs(total_wave_seconds - float(capture_wall)) > 0.12:
        failures.append("Native PCM stage WAVs differ from capture wall time by over 120 ms")
    for profile, measurements in profiles.items():
        def segment(name: str, start: float, end: float | None = None) -> np.ndarray:
            samples, rate = recordings[profile, name]
            return samples[int(start * rate):int(end * rate) if end is not None else None]

        # Exclude source retirement and native mixer latency at stage boundaries.
        for name, start, end in [("idle", 0.25, None), ("engine_mask_0", 0.25, None),
                ("near_far_listener_camera_motion", 0.75, 0.98),
                ("pause_reset_rewind_detach_reattach_configure", 0.44, 0.51)]:
            silence = segment(name, start, end)
            peak = float(np.max(np.abs(silence))) if silence.size else 1.0
            measurements[name]["settled_peak_linear"] = peak
            if peak > 1.0 / 32768.0:
                failures.append(f"{profile}/{name}: settled interval is not silent")
        half = rms_db(segment("engine_mask_05", 0.15, 0.65))
        full = rms_db(segment("engine_mask_1", 0.15, 0.65))
        measurements["mask_reduction_db"] = full - half
        if not 4.0 <= full - half <= 8.0:
            failures.append(f"{profile}: half-amplitude mask did not reduce output by about 6 dB")
        large = measurements["servo_large_fast"]["rms_dbfs"]
        small = measurements["servo_small_slow"]["rms_dbfs"]
        measurements["large_minus_small_db"] = large - small
        if large - small < 1.0:
            failures.append(f"{profile}: rapid full travel did not exceed the small correction")
    return {"format": "openrc-mechanical-signal-checks-v1", "passed": not failures,
        "report_sha256": hashlib.sha256((directory / "report.json").read_bytes()).hexdigest(),
        "checker_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "capture_wall_seconds": float(capture_wall) if finite_positive(capture_wall) else None,
        "stage_wav_seconds": total_wave_seconds,
        "probe_sha256": report.get("probe_sha256"),
        "capture_bookkeeping": report.get("capture_bookkeeping"),
        "measurements": profiles, "failures": failures,
        "scope": "Native signal, silence, masks and pool bounds; no perceptual click, repetition or realism certification."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = analyze(args.directory)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
