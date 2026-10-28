"""F4U JSON generation must preserve the checkout bytes used by dependent hashes."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "research/f4u-corsair/F4U-07/derive_physics.py"
AIRCRAFT = "app/data/aircraft/f4u_corsair_250.json"


class GeneratedIdentity(unittest.TestCase):
    def test_generated_bytes_match_fresh_checkout_and_check_rejects_lf(self):
        with tempfile.TemporaryDirectory(prefix="openrc-f4u-generation-") as directory:
            temp = Path(directory)
            output = temp / "output"
            report = temp / "report"
            source = temp / "source"
            output.mkdir()
            report.mkdir()
            source.mkdir()
            env = os.environ.copy()
            env.update(OPENRC_AIRCRAFT_OUTPUT_DIR=str(output), OPENRC_AIRCRAFT_REPORT_DIR=str(report),
                       PYTHONDONTWRITEBYTECODE="1")

            def generate(*args):
                return subprocess.run([sys.executable, str(SCRIPT), *args], cwd=ROOT, env=env,
                                      text=True, capture_output=True, timeout=60)

            result = generate()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            generated = output / "f4u_corsair_250.json"
            actual = generated.read_bytes()
            for relative in (Path(".gitattributes"), Path(AIRCRAFT)):
                destination = source / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, destination)

            def git(cwd, *args):
                return subprocess.run(["git", "-c", "user.name=F4U checkout test", "-c",
                                       "user.email=f4u-checkout-test@localhost", *args],
                                      cwd=cwd, check=True, capture_output=True, text=True)

            git(source, "init", "--quiet")
            git(source, "add", ".")
            git(source, "commit", "--quiet", "-m", "Disposable F4U checkout fixture")
            for mode in ("false", "true"):
                checkout = temp / ("checkout-" + mode)
                git(temp, "-c", "core.autocrlf=" + mode, "clone", "--quiet", str(source), str(checkout))
                self.assertEqual(actual, (checkout / AIRCRAFT).read_bytes(), mode)
            self.assertIn(b"\r\n", actual)
            self.assertNotIn(b"\n", actual.replace(b"\r\n", b""))
            result = generate("--check")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            generated.write_bytes(actual.replace(b"\r\n", b"\n"))
            result = generate("--check")
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("stale: f4u_corsair_250.json", result.stderr)


if __name__ == "__main__":
    unittest.main()
