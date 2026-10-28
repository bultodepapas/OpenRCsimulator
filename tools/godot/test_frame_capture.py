"""Optional real-engine regression for frame diagnostics and retained failure prefixes."""
import json
import os
from pathlib import Path
import tempfile
import unittest

from run_checked import run_checked
from research.performance.frame_diagnose import diagnose
from research.performance.native_summary import DEFAULT_POLICY, summarize_run


@unittest.skipUnless(os.environ.get("OPENRC_TEST_GODOT"), "set OPENRC_TEST_GODOT for actual engine checks")
class FrameCaptureTests(unittest.TestCase):
    def capture(self, directory, *options):
        root = Path(directory)
        report = root / "frames.json"
        command = [os.environ["OPENRC_TEST_GODOT"], "--headless", "--path",
                   str(Path(__file__).resolve().parents[2] / "app"), "--audio-driver", "Dummy",
                   "--max-fps", "60", "--", "--scripted", f"--frametimes={report}",
                   "--warmup=0", "--t=0.08", *options]
        # A full scene plus provenance hashing can exceed 90 s on a cold WSL
        # Windows-mounted checkout; this is a functional check, not a speed gate.
        checked = run_checked(command, root / "checked", timeout=180)
        self.assertTrue(report.is_file(), checked)
        frames = json.loads(report.read_text(encoding="utf-8"))
        self.assertEqual(frames["capture_id"], checked["capture_id"])
        clock = frames["clock"]
        self.assertEqual(clock["source"], "godot_ticks_usec")
        self.assertEqual(clock["origin_usec"], 0)
        if frames["format"] == "openrc-frametimes v3":
            self.assertLessEqual(clock["start"]["monotonic_usec"], frames["actual_sample_start_monotonic_usec"])
            self.assertGreaterEqual(clock["end"]["monotonic_usec"], frames["actual_sample_end_monotonic_usec"])
        else:
            self.assertLessEqual(clock["start"]["monotonic_usec"], frames["frame_end_monotonic_usec"][0])
            self.assertGreaterEqual(clock["end"]["monotonic_usec"], frames["frame_end_monotonic_usec"][-1])
        self.assertGreaterEqual(clock["start"]["uncertainty_usec"], 20000)
        return checked, frames

    def test_disabled_diagnostics_add_no_observer_metrics(self):
        with tempfile.TemporaryDirectory(prefix="openrc-frames-off-") as directory:
            checked, report = self.capture(directory)
            self.assertTrue(checked["ok"], checked)
            self.assertTrue(report["complete"])
            self.assertEqual(report["frame_diagnostics"], {"enabled": False})
            self.assertNotIn("render_gpu_ms", report["raw_metrics"])

    def test_headless_diagnostic_capture_is_finite_and_explicit(self):
        with tempfile.TemporaryDirectory(prefix="openrc-frames-on-") as directory:
            checked, report = self.capture(directory, "--frame-diagnostics")
            self.assertTrue(checked["ok"], checked)
            self.assertTrue(report["complete"])
            self.assertIn("render_gpu_ms", report["raw_metrics"])
            self.assertTrue(all(v == 0 for v in report["raw_metrics"]["render_gpu_ms"]))
            for values in report["raw_metrics"].values():
                self.assertEqual(len(values), report["frames"])
            self.assertIn("headless", json.dumps(report["frame_diagnostics"]).lower())

    def test_frame_limit_retains_incomplete_prefix_and_fails(self):
        with tempfile.TemporaryDirectory(prefix="openrc-frames-limit-") as directory:
            checked, report = self.capture(directory, "--frame-diagnostics", "--frametimes-max-frames=2", "--t=1")
            self.assertFalse(checked["ok"])
            self.assertEqual(checked["process_exit"], 1)
            self.assertFalse(report["complete"])
            self.assertEqual(report["frames"], 2)
            self.assertEqual(report["max_frames"], 2)
            self.assertIn("retention limit", report["failure"])
            self.assertTrue(all(len(v) == 2 for v in report["raw_metrics"].values()))

    def test_real_stream_is_verified_by_native_reducer(self):
        with tempfile.TemporaryDirectory(prefix="openrc-frames-stream-") as directory:
            root = Path(directory)
            checked, report = self.capture(directory, "--frametimes-stream", "--frame-diagnostics", "--t=0.3")
            self.assertTrue(checked["ok"], checked)
            self.assertEqual(report["format"], "openrc-frametimes v3")
            self.assertTrue(report["complete"])
            self.assertTrue(report["stream"]["complete"])
            (root / "frames.log").write_bytes((Path(checked["report"]).parent / "engine.log").read_bytes())
            policy = {**DEFAULT_POLICY, "minimum_warmup_s": 0.0, "minimum_sample_s": 0.1, "minimum_runs": 1}
            result = summarize_run(root / "frames.json", policy)
            self.assertTrue(result["collection_valid"], result["collection_reasons"])
            self.assertEqual(result["stream"]["frames"], report["frames"])
            self.assertFalse(result["active_flight_qualifier"])  # scripted is not a pilot flight
            diagnosis = diagnose(root / "frames.json", root / "frames.log")
            self.assertTrue(diagnosis["valid"], diagnosis["validity_reasons"])
            self.assertEqual(diagnosis["observations"]["frame_count"], report["frames"])

    def test_stream_frame_limit_keeps_a_rejected_prefix(self):
        with tempfile.TemporaryDirectory(prefix="openrc-frames-stream-cap-") as directory:
            checked, report = self.capture(directory, "--frametimes-stream", "--frametimes-max-frames=2", "--t=1")
            self.assertFalse(checked["ok"])
            self.assertFalse(report["complete"])
            self.assertEqual(report["frames"], 2)
            self.assertFalse(report["stream"]["complete"])
            records = [json.loads(line) for line in
                       (Path(directory) / report["stream"]["file"]).read_text(encoding="utf-8").splitlines()]
            self.assertEqual(records[-1]["type"], "trailer")
            self.assertFalse(records[-1]["complete"])


if __name__ == "__main__":
    unittest.main()
