"""Optional real-engine regression for frame diagnostics and retained failure prefixes."""
import json
import os
from pathlib import Path
import tempfile
import unittest

from run_checked import run_checked


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
        return checked, json.loads(report.read_text(encoding="utf-8"))

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


if __name__ == "__main__":
    unittest.main()
