"""RCV-04a: run the real headless bench; verify traces and refusal semantics."""
from __future__ import annotations

import csv
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "research/rc-monster-truck/run_suspension_bench.gd"
PROFILE = ROOT / "research/rc-monster-truck/suspension_bench.json"


class SuspensionCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = os.environ.get("OPENRC_TEST_GODOT") or subprocess.check_output(
            [str(ROOT / "app/get-godot.sh")], text=True).strip()
        cls.work = tempfile.TemporaryDirectory(prefix="openrc-rcv-")
        cls.directory = Path(cls.work.name)

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def run_engine(self, arguments, success=True):
        result = subprocess.run(
            [self.engine, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "app"),
             "--script", str(RUNNER), "--", *arguments],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)
        log = result.stdout + result.stderr
        self.assertEqual(result.returncode == 0, success, log)
        self.assertNotRegex(log, r"(?m)^(?:SCRIPT |SHADER )ERROR:")
        if success:
            self.assertNotRegex(log, r"(?m)^ERROR:")
        return log

    def trace(self, scenario, name=None, hz=240):
        path = self.directory / ((name or scenario) + ".csv")
        self.run_engine(["--scenario=" + scenario, "--duration=1", f"--hz={hz}", "--out=" + str(path)])
        metadata = json.loads(path.with_suffix(".json").read_text(encoding="utf-8"))
        with path.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        self.assertTrue(metadata["complete"])
        self.assertEqual(metadata["hz"], hz)
        self.assertEqual(metadata["substeps_per_tick"], 2)
        self.assertEqual(metadata["scenario"], scenario)
        self.assertEqual(metadata["sample_count"], hz + 1)
        self.assertEqual(metadata["finite_sample_count"], hz + 1)
        self.assertEqual(len(rows), hz + 1)
        self.assertEqual(metadata["profile_sha256"], hashlib.sha256(PROFILE.read_bytes()).hexdigest())
        self.assertEqual(metadata["csv_sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(metadata["profile_id"], "rcv-quarter-car-synthetic-v1")
        for index, row in enumerate(rows):
            for key, value in row.items():
                if key != "in_contact":
                    self.assertTrue(math.isfinite(float(value)), (key, value))
            self.assertAlmostEqual(float(row["time_s"]), index / hz, places=9)
            self.assertGreaterEqual(float(row["tire_force_n"]), 0.0)
            self.assertGreaterEqual(float(row["dissipation_w"]), 0.0)
            self.assertIn(row["in_contact"], ("false", "true"))
        return path, rows, metadata

    def test_three_experiments_and_provenance(self):
        for scenario in ("release", "drop", "bump"):
            with self.subTest(scenario=scenario):
                _, rows, metadata = self.trace(scenario)
                if scenario == "drop":
                    self.assertEqual(rows[0]["in_contact"], "false")
                    self.assertGreater(metadata["contact_sample_count"], 0)
                    self.assertLess(metadata["contact_sample_count"], len(rows))
                if scenario == "bump":
                    self.assertGreater(max(float(r["road_height_m"]) for r in rows), 0.0049)
                    self.assertEqual(float(rows[0]["road_height_m"]), 0.0)
                    self.assertEqual(float(rows[-1]["road_height_m"]), 0.0)
                else:
                    self.assertTrue(all(float(r["road_height_m"]) == 0.0 for r in rows))

    def test_repeated_run_preserves_trace_bytes(self):
        a, _, _ = self.trace("drop", "repeat-a")
        b, _, _ = self.trace("drop", "repeat-b")
        self.assertEqual(a.read_bytes(), b.read_bytes())

    def test_refinement_rates(self):
        for hz in (480, 960, 1920):
            with self.subTest(hz=hz):
                self.trace("release", f"release-{hz}", hz)

    def test_invalid_options_do_not_create_success_artifacts(self):
        cases = [[], ["--hz=0"], ["--hz=241"], ["--duration=0"], ["--duration=nan"],
                 ["--duration=inf"], ["--duration=-1"], ["--duration=31"],
                 ["--duration=0.001"], ["--duration=1e-15"], ["--scenario=aircraft"], ["--unknown=value"],
                 ["--hz=240", "--hz=480"]]
        for index, args in enumerate(cases):
            with self.subTest(args=args):
                path = self.directory / f"invalid-{index}.csv"
                options = args + (["--out=" + str(path)] if index else [])
                self.run_engine(options, success=False)
                self.assertFalse(path.exists())
                self.assertFalse(path.with_suffix(".json").exists())

    def test_invalid_profile_is_refused_before_export(self):
        for index, contents in enumerate(("{", "[]", '{"format":"openrc-suspension-bench"}')):
            bad = self.directory / f"bad-{index}.json"
            bad.write_text(contents, encoding="utf-8")
            path = self.directory / f"bad-output-{index}.csv"
            self.run_engine(["--profile=" + str(bad), "--out=" + str(path)], success=False)
            self.assertFalse(path.exists())
            self.assertFalse(path.with_suffix(".json").exists())

    def test_output_cannot_replace_profile(self):
        profile = self.directory / "protected.json"
        original = PROFILE.read_bytes()
        profile.write_bytes(original)
        self.run_engine(["--profile=" + str(profile), "--out=" + str(profile.with_suffix(".csv"))], success=False)
        self.assertEqual(profile.read_bytes(), original)
        self.assertFalse(profile.with_suffix(".csv").exists())


if __name__ == "__main__":
    unittest.main()
