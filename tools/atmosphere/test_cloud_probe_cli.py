#!/usr/bin/env python3
"""Cloud checker launcher/CLI regressions; never launch a graphics process."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_cloud_probe as probe


class CloudProbeCliTests(unittest.TestCase):
    def test_windows_rendering_needs_no_unix_launcher(self):
        with patch.object(probe.shutil, "which", side_effect=AssertionError("unexpected Unix dependency")):
            command = probe.render_command(Path("Godot.exe"), Path("app"), windows=True)
        self.assertEqual(command[0], "Godot.exe")
        self.assertNotIn("xvfb-run", command)
        self.assertNotIn("timeout", command)
        self.assertIn("gl_compatibility", command)
        self.assertIn("opengl3", command)

    def test_linux_keeps_xvfb_and_refuses_a_missing_launcher(self):
        with patch.object(probe.shutil, "which", return_value="/usr/bin/xvfb-run"):
            command = probe.render_command(Path("godot"), Path("app"), windows=False)
        self.assertEqual(command[:4], ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"])
        with patch.object(probe.shutil, "which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "xvfb-run is required"):
                probe.render_command(Path("godot"), Path("app"), windows=False)

    def test_real_shared_runner_retains_success_and_zero_exit_shader_errors(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            good_log = root / "good.log"
            report = probe.checked_run([sys.executable, "-c", "print('atlas complete')"],
                                       good_log, dict(os.environ), required_text="atlas complete")
            self.assertTrue(report["ok"])
            self.assertEqual(good_log.read_bytes(), Path(report["log"]).read_bytes())
            with self.assertRaisesRegex(RuntimeError, "engine_error"):
                probe.checked_run([sys.executable, "-c", "print('SHADER ERROR: deliberate fixture')"],
                                  root / "bad.log", dict(os.environ))
            reports = [json.loads(path.read_text()) for path in (root / "checks").glob("*/report.json")]
            self.assertEqual(len(reports), 2)
            self.assertEqual(sum(report["counts"]["error"] for report in reports), 1)

    def test_cleanup_accepts_its_runner_outputs_and_preserves_foreign_files(self):
        parser = argparse.ArgumentParser()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            owned_report = root / "checks" / "run" / "report.json"
            owned_report.parent.mkdir(parents=True)
            owned_report.write_text("{}")
            (root / "engine-version.log").write_text(probe.PINNED_ENGINE_BUILD)
            probe.prepare_output(root, parser)
            self.assertEqual(list(root.iterdir()), [])
            foreign = root / "keep.txt"
            foreign.write_text("user data")
            with self.assertRaises(SystemExit):
                probe.prepare_output(root, parser)
            self.assertEqual(foreign.read_text(), "user data")

    def test_real_cli_rejects_the_wrong_engine_before_any_render(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "app"
            (app / "render").mkdir(parents=True)
            (app / "render" / "cloud_field.gdshaderinc").write_text("// unused fixture\n")
            out = root / "out"
            result = subprocess.run([sys.executable, str(Path(probe.__file__)), "--app", str(app),
                                     "--godot", sys.executable, "--out", str(out)],
                                    capture_output=True, text=True, check=False, timeout=30)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("expected " + probe.PINNED_ENGINE_BUILD, result.stderr)
            self.assertFalse((out / "summary.json").exists())
            self.assertFalse((out / "repeat-1" / "probe.json").exists())
            self.assertEqual(len(list((out / "checks").glob("*/report.json"))), 1)


if __name__ == "__main__":
    unittest.main()
