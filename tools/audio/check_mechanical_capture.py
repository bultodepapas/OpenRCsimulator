"""Check AUD-16 native bench signals; these gates do not replace listening."""
from __future__ import annotations

import argparse
import hashlib
import json
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


def analyze(directory: Path) -> dict:
    report = json.loads((directory / "report.json").read_text(encoding="utf-8"))
    failures: list[str] = []
    profiles: dict[str, dict] = {}
    recordings: dict[tuple[str, str], tuple[np.ndarray, int]] = {}
    stages = report["stage_results"]
    if report["driver"].lower() == "dummy":
        failures.append("Dummy driver cannot qualify signal output")
    if report["discarded_frames"] or abs(report["captured_seconds"] - report["scripted_wall_seconds"]) > 0.12:
        failures.append("Capture timing/drop gate failed")
    if len(stages) != 40:
        failures.append("Expected ten stages for each of four profile combinations")
    for stage in stages:
        profile, name = stage["profile"], stage["name"]
        samples, rate = read_wave(directory / profile / (name + ".wav"))
        recordings[profile, name] = samples, rate
        if len(samples) != stage["frames"] or rate != stage["mix_rate_hz"]:
            failures.append(f"{profile}/{name}: captured shape differs from report")
        if np.max(np.abs(samples)) >= 1.0 - 1.0 / 32768.0:
            failures.append(f"{profile}/{name}: full-scale PCM rail")
        if stage["max_motion_voice_count"] > 6 or stage["max_event_voice_count"] > 2:
            failures.append(f"{profile}/{name}: voice cap exceeded")
        if stage["timed_out"]:
            failures.append(f"{profile}/{name}: stage timed out")
        profiles.setdefault(profile, {})[name] = {"rms_dbfs": rms_db(samples)}
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
