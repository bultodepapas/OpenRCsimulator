"""Mutation and byte-freshness checks for the MT8 data generator."""
from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "research/rc-monster-truck/build_vehicle_data.py"
CHECKED_IN = ROOT / "app/data/vehicles/ground/mt8_bisonte.json"


class VehicleDataGeneratorTests(unittest.TestCase):
    def run_generator(self, *args: str, success: bool = True) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [sys.executable, "-B", str(GENERATOR), *args],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_checked_in_data_matches_generator_and_uses_lf(self) -> None:
        before = CHECKED_IN.stat().st_mtime_ns
        self.run_generator("--check")
        after = CHECKED_IN.stat().st_mtime_ns
        data = CHECKED_IN.read_bytes()
        self.assertEqual(before, after, "--check must not rewrite the accepted data")
        self.assertNotIn(b"\r\n", data, "generated JSON must use LF on every platform")
        self.assertTrue(data.endswith(b"\n"))

    def test_check_refuses_mutated_output_without_repairing_it(self) -> None:
        with tempfile.TemporaryDirectory(prefix="openrc-vehicle-generator-") as temp:
            output = Path(temp) / "changed.json"
            mutated = b'{"edited_by_test": true}\n'
            output.write_bytes(mutated)
            before = output.stat().st_mtime_ns
            result = self.run_generator("--check", "--out", str(output), success=False)
            after = output.stat().st_mtime_ns
            self.assertIn("stale generated vehicle data", result.stderr)
            self.assertEqual(output.read_bytes(), mutated)
            self.assertEqual(before, after, "check mode must not repair or touch mutated output")

    def test_generator_output_is_byte_identical_to_checked_in_file(self) -> None:
        with tempfile.TemporaryDirectory(prefix="openrc-vehicle-generator-") as temp:
            output = Path(temp) / "generated.json"
            self.run_generator("--out", str(output))
            self.assertEqual(output.read_bytes(), CHECKED_IN.read_bytes())


if __name__ == "__main__":
    unittest.main()
