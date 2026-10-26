"""Focused regression fixtures for the two native audio capture checkers."""
from __future__ import annotations

import copy
import json
import math
import tempfile
import unittest
import wave
from pathlib import Path

import numpy as np

import check_captures
import check_mechanical_capture


LIVE_FRAMES = 480
MIX_RATE = 48_000
STAGE_NAMES = (
    "idle",
    "servo_small_slow",
    "servo_large_fast",
    "simultaneous_servos",
    "gear_extension_reversal_interruption_endpoint",
    "near_far_listener_camera_motion",
    "engine_mask_0",
    "engine_mask_05",
    "engine_mask_1",
    "pause_reset_rewind_detach_reattach_configure",
)
PROFILES = ("standard_electric", "standard_pneumatic", "high_torque_electric", "high_torque_pneumatic")


def write_wave(path: Path, pcm: np.ndarray, rate: int = MIX_RATE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(pcm.astype("<i2", copy=False).tobytes())


def frame_bookkeeping(recorded: int, *, flushed: int = 0) -> dict:
    pushed = recorded + flushed
    return {
        "buffer_length_frames": MIX_RATE,
        "initial": {"pushed_frames": 0, "discarded_frames": 0, "available_frames": 0},
        "final": {
            "pushed_frames": pushed,
            "discarded_frames": 0,
            "available_frames_before_flush": flushed,
            "flushed_frames": flushed,
            "available_frames_after_flush": 0,
        },
        "pushed_frames": pushed,
        "recorded_frames": recorded,
        "flushed_frames": flushed,
        "truncated_frames": 0,
        "overflow_discarded_frames": 0,
        "unaccounted_pushed_frames": 0,
    }


class CaptureCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tempdir = tempfile.TemporaryDirectory(prefix="openrc-audio-checks-")
        cls.root = Path(cls.tempdir.name)
        cls.live_prefix = cls.root / "gameplay"
        cls._write_live_fixture()
        cls.mechanical_dir = cls.root / "mechanical"
        cls._write_mechanical_fixture()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tempdir.cleanup()

    @classmethod
    def _write_live_fixture(cls) -> None:
        pcm = np.full((LIVE_FRAMES, 2), 3000, dtype="<i2")
        write_wave(cls.live_prefix.with_suffix(".wav"), pcm)
        peak_dbfs = 20.0 * math.log10(3000.0 / 32768.0)
        report = {
            "format": "openrc-audio-gameplay-v1",
            "arguments": {"wildlife-review": True},
            "driver": "WASAPI",
            "display": "headless",
            "requested_fps": 60,
            "aircraft": "fixture-aircraft",
            "frames": LIVE_FRAMES,
            "mix_rate": MIX_RATE,
            "captured_seconds": LIVE_FRAMES / MIX_RATE,
            "capture_wall_seconds": LIVE_FRAMES / MIX_RATE,
            "capture_effect_removed": True,
            "capture_bookkeeping": frame_bookkeeping(LIVE_FRAMES),
            "probe_sha256": "a" * 64,
            "finite_samples": True,
            "peak_dbfs": peak_dbfs,
            "rms_dbfs": peak_dbfs,
            "discarded_frames": 0,
            "soundscape_update_p95_us": 100,
            "soundscape_update_max_us": 200,
            "soundscape_timing_sample_count": 1,
            "distance_min_m": 1.0,
            "distance_max_m": 10.0,
            "events": [],
            "final_paused": False,
            "final_tick": 10,
            "wildlife_events": [{"species": "songbird", "variant": "one"}],
        }
        cls.live_report = report
        cls._write_json(cls.live_prefix.with_suffix(".json"), report)

    @classmethod
    def _write_mechanical_fixture(cls) -> None:
        stages: list[dict] = []
        samples = 0
        for profile in PROFILES:
            for name in STAGE_NAMES:
                amplitude = {
                    "idle": 0,
                    "servo_small_slow": 1000,
                    "servo_large_fast": 3000,
                    "simultaneous_servos": 2000,
                    "gear_extension_reversal_interruption_endpoint": 2000,
                    "near_far_listener_camera_motion": 2000,
                    "engine_mask_0": 0,
                    "engine_mask_05": 1000,
                    "engine_mask_1": 2000,
                    "pause_reset_rewind_detach_reattach_configure": 2000,
                }[name]
                pcm = np.zeros((MIX_RATE, 2), dtype="<i2")
                if name == "near_far_listener_camera_motion":
                    pcm[: MIX_RATE // 2] = amplitude
                elif name == "pause_reset_rewind_detach_reattach_configure":
                    pcm[: int(0.4 * MIX_RATE)] = amplitude
                elif amplitude:
                    pcm[:] = amplitude
                write_wave(cls.mechanical_dir / profile / f"{name}.wav", pcm)
                samples += len(pcm)
                stages.append({
                    "profile": profile,
                    "name": name,
                    "frames": len(pcm),
                    "mix_rate_hz": MIX_RATE,
                    "wall_seconds": 1.0,
                    "max_motion_voice_count": 0,
                    "max_event_voice_count": 0,
                    "timed_out": False,
                    "flushed_frames_before_stage": 0,
                })
        report = {
            "format": "openrc-mechanical-audio-staged-probe-v1",
            "driver": "WASAPI",
            "mix_rate_hz": MIX_RATE,
            "captured_seconds": samples / MIX_RATE,
            "capture_wall_seconds": 40.0,
            "scripted_wall_seconds": 40.0,
            "discarded_frames": 0,
            "capture_effect_removed": True,
            "probe_sha256": "b" * 64,
            "capture_bookkeeping": frame_bookkeeping(samples),
            "stage_results": stages,
        }
        report["capture_bookkeeping"]["staged_capture_memory_limit_seconds"] = 60.0
        cls.mechanical_report = report
        cls._write_json(cls.mechanical_dir / "report.json", report)

    @staticmethod
    def _write_json(path: Path, value: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, allow_nan=True), encoding="utf-8")

    def _write_live_report(self, report: dict) -> None:
        self._write_json(self.live_prefix.with_suffix(".json"), report)

    def _write_mechanical_report(self, report: dict) -> None:
        self._write_json(self.mechanical_dir / "report.json", report)

    def test_valid_gameplay_fixture_passes(self) -> None:
        self._write_live_report(copy.deepcopy(self.live_report))
        result = check_captures.analyze(self.live_prefix)
        self.assertTrue(result["passed"], result["failures"])
        self.assertEqual(result["capture_bookkeeping"]["unaccounted_pushed_frames"], 0)
        self.assertEqual(len(result["checker_sha256"]), 64)

    def test_gameplay_wall_time_must_be_finite_and_positive(self) -> None:
        for wall in (None, float("nan"), 0.0, -1.0):
            with self.subTest(wall=wall):
                report = copy.deepcopy(self.live_report)
                if wall is None:
                    report.pop("capture_wall_seconds")
                else:
                    report["capture_wall_seconds"] = wall
                self._write_live_report(report)
                result = check_captures.analyze(self.live_prefix)
                self.assertFalse(result["passed"])
                self.assertIn("capture wall time is missing, non-finite, or non-positive", result["failures"])

    def test_gameplay_bookkeeping_and_sample_finiteness_are_gated(self) -> None:
        report = copy.deepcopy(self.live_report)
        report["capture_bookkeeping"]["unaccounted_pushed_frames"] = 1
        report["finite_samples"] = False
        self._write_live_report(report)
        result = check_captures.analyze(self.live_prefix)
        self.assertFalse(result["passed"])
        self.assertIn("capture pushed/recorded/flushed frame counts do not balance", result["failures"])
        self.assertIn("capture contains non-finite samples", result["failures"])

    def test_valid_mechanical_fixture_passes(self) -> None:
        self._write_mechanical_report(copy.deepcopy(self.mechanical_report))
        result = check_mechanical_capture.analyze(self.mechanical_dir)
        self.assertTrue(result["passed"], result["failures"])
        self.assertEqual(result["stage_wav_seconds"], 40.0)
        self.assertEqual(len(result["checker_sha256"]), 64)

    def test_mechanical_wall_time_must_be_finite_and_positive(self) -> None:
        for wall in (None, float("nan"), 0.0, -1.0):
            with self.subTest(wall=wall):
                report = copy.deepcopy(self.mechanical_report)
                if wall is None:
                    report.pop("capture_wall_seconds")
                else:
                    report["capture_wall_seconds"] = wall
                self._write_mechanical_report(report)
                result = check_mechanical_capture.analyze(self.mechanical_dir)
                self.assertFalse(result["passed"])
                self.assertIn("Capture wall time is missing, non-finite, or non-positive", result["failures"])

    def test_mechanical_unbalanced_bookkeeping_fails(self) -> None:
        report = copy.deepcopy(self.mechanical_report)
        report["capture_bookkeeping"]["unaccounted_pushed_frames"] = 1
        self._write_mechanical_report(report)
        result = check_mechanical_capture.analyze(self.mechanical_dir)
        self.assertFalse(result["passed"])
        self.assertIn("Capture pushed/recorded/flushed frame counts do not balance", result["failures"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
