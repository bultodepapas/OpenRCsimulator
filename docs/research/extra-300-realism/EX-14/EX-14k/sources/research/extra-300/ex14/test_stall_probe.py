"""Reject ambiguous stall-probe inputs before creating evidence or starting a flight."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = Path(__file__).with_name("stall_probe.gd")
GODOT = os.environ.get("GODOT", str(ROOT / ".tools" / (
    "Godot_v4.8-beta2_win64_console.exe" if os.name == "nt" else "Godot_v4.8-beta2_linux.x86_64")))
APP = ROOT / "app"


class ProbeCLI(unittest.TestCase):
    def refused(self, arguments, message):
        if not Path(GODOT).is_file():
            self.skipTest("Pass --godot for the pinned engine")
        with tempfile.TemporaryDirectory(prefix="extra-stall-cli-", dir=ROOT / "tmp") as folder:
            directory = Path(folder).resolve()
            self.assertEqual(directory.parent, (ROOT / "tmp").resolve())
            output = directory / "evidence"
            result = subprocess.run([GODOT, "--headless", "--path", str(APP), "--audio-driver", "Dummy",
                "--script", str(SCRIPT), "--", "--case=normal/hands_off", "--out=" + str(output)] + arguments,
                capture_output=True, text=True, encoding="utf-8", timeout=30)
            log = result.stdout + result.stderr
            self.assertEqual(result.returncode, 2, log)
            self.assertIn(message, log)
            self.assertNotIn("SCRIPT ERROR:", log)
            self.assertNotIn("ERROR:", log)
            self.assertFalse(output.exists(), log)

    def test_invalid_hold_is_refused_before_output(self):
        for value in ("-1", "0", "0.1", "6", "nan", "nonsense"):
            with self.subTest(value=value):
                self.refused(["--hold=" + value], "Expected --hold in")

    def test_unknown_rudder_policy_is_refused(self):
        self.refused(["--rudder=ball_typo"], "--rudder=hands_off|neutral_surface|ball")

    def test_misspelled_option_cannot_silently_run_the_default(self):
        self.refused(["--ruder=ball"], "Unknown argument")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=GODOT)
    parser.add_argument("--app", type=Path, default=APP)
    args, remaining = parser.parse_known_args()
    GODOT = str(Path(args.godot).resolve())
    APP = args.app.resolve()
    unittest.main(argv=[sys.argv[0]] + remaining)
