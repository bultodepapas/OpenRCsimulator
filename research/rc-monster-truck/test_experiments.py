"""Process-level runner and analyzer contract checks for RCV research traces."""
from __future__ import annotations

import csv
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "research/rc-monster-truck/run_experiments.gd"
ANALYZER = ROOT / "research/rc-monster-truck/analyze_recording.py"
VEHICLE = ROOT / "app/data/vehicles/ground/mt8_bisonte.json"
COURSE = ROOT / "app/data/ground_vehicle/practice.json"


class GroundVehicleExperimentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.engine = os.environ.get("OPENRC_TEST_GODOT") or os.environ.get("GODOT")
        if not cls.engine:
            result = subprocess.run(
                [str(ROOT / "app/get-godot.sh")],
                cwd=ROOT / "app",
                check=True,
                capture_output=True,
                text=True,
            )
            cls.engine = result.stdout.strip().splitlines()[-1]
        cls.work = tempfile.TemporaryDirectory(prefix="openrc-ground-experiments-")
        cls.directory = Path(cls.work.name)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.work.cleanup()

    def run_engine(self, arguments: list[str], *, success: bool = True) -> str:
        result = subprocess.run(
            [self.engine, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "app"),
             "--script", str(RUNNER), "--", *arguments],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=180,
        )
        log = result.stdout + result.stderr
        self.assertEqual(result.returncode == 0, success, log)
        self.assertNotRegex(log, r"(?m)^(?:SCRIPT |SHADER )ERROR:")
        if success:
            self.assertNotRegex(log, r"(?m)^ERROR:")
        return log

    def trace(self, scenario: str, stem: str, duration: str = "1") -> tuple[Path, list[dict[str, str]], dict]:
        path = self.directory / f"{stem}.csv"
        self.run_engine([f"--scenario={scenario}", f"--duration={duration}", f"--output={path}"])
        metadata = json.loads(path.with_suffix(".json").read_text(encoding="utf-8"))
        with path.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        self.assertTrue(metadata["complete"])
        self.assertEqual(metadata["status"], "complete")
        self.assertEqual(metadata["public_hz"], 240)
        self.assertTrue(metadata["solver_version"].startswith("openrc-ground-vehicle-dynamics-"))
        self.assertEqual(metadata["substeps_per_tick"], 1)
        self.assertEqual(metadata["scenario"], scenario)
        self.assertEqual(metadata["sample_count"], len(rows))
        self.assertEqual(metadata["finite_sample_count"], len(rows))
        self.assertEqual(metadata["csv_sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(metadata["vehicle_identity"]["sha256"], hashlib.sha256(VEHICLE.read_bytes()).hexdigest())
        self.assertEqual(metadata["course_identity"]["sha256"], hashlib.sha256(COURSE.read_bytes()).hexdigest())
        self.assertIn("replay", metadata["commands"])
        self.assertIn("braking_surface_comparison", metadata["commands"])
        by_run: dict[str, list[dict[str, str]]] = {}
        for row in rows:
            by_run.setdefault(row["run_id"], []).append(row)
            self.assertIn(row["airborne"], ("true", "false"))
            for name, value in row.items():
                if (
                    name not in {"run_id", "scenario", "surface_id", "airborne", "road_surface_id", "sample_index"}
                    and not name.startswith("wheel_contact_")
                    and not name.startswith("hull_contact_")
                ):
                    self.assertTrue(math.isfinite(float(value)), (name, value))
        expected = int(float(duration) * 240) + 1
        for run_rows in by_run.values():
            self.assertEqual(len(run_rows), expected)
            for index, row in enumerate(run_rows):
                self.assertEqual(int(row["sample_index"]), index)
                self.assertAlmostEqual(float(row["time_s"]), index / 240, places=9)
        return path, rows, metadata

    def analyze(self, path: Path, *, success: bool = True) -> tuple[subprocess.CompletedProcess[str], Path]:
        report_path = path.with_suffix(".analysis.json")
        result = subprocess.run(
            [sys.executable, "-B", str(ANALYZER), str(path), "--output", str(report_path)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result, report_path

    def test_three_scenarios_export_complete_provenanced_traces(self) -> None:
        for scenario in ("braking", "bump", "drop"):
            with self.subTest(scenario=scenario):
                path, rows, metadata = self.trace(scenario, scenario)
                if scenario == "braking":
                    self.assertEqual([run["surface_id"] for run in metadata["runs"]], ["asphalt", "gravel", "grass", "slippery"])
                    self.assertEqual(len({run["initial_speed_m_per_s"] for run in metadata["runs"]}), 1)
                elif scenario == "bump":
                    self.assertGreater(max(float(row["road_height_m"]) for row in rows), 0.01)
                else:
                    self.assertEqual(rows[0]["airborne"], "true")
                    self.assertGreater(metadata["runs"][0]["airborne_sample_count"], 0)
                _, report_path = self.analyze(path)
                report = json.loads(report_path.read_text(encoding="utf-8"))
                self.assertEqual(report["status"], "complete")
                self.assertEqual(report["scenario"], scenario)
                if scenario == "braking":
                    check = report["independent_analysis"]
                    self.assertTrue(check["same_initial_speed_verified"])
                    self.assertTrue(check["same_controls_verified"])
                    self.assertEqual(check["ordered_by_estimated_effective_mu_low_to_high"], ["slippery", "grass", "gravel", "asphalt"])
                    self.assertTrue(all(trial["ideal_coulomb_stop_distance_m"] > 0.0 for trial in check["trials"]))
                if scenario == "drop":
                    check = report["independent_analysis"]
                    self.assertEqual(check["check"], "pass")
                    self.assertLessEqual(check["free_flight_sample_count"], metadata["runs"][0]["airborne_sample_count"])
                    self.assertLess(check["maximum_ballistic_height_error_m"], 1e-8)
                    self.assertLess(check["maximum_ballistic_vertical_velocity_error_m_per_s"], 1e-7)
                    self.assertIn("system center of mass", check["analysis_limit"])
                if scenario == "bump":
                    self.assertLessEqual(report["independent_analysis"]["maximum_road_height_reconstruction_error_m"], 1e-10)

    def test_rollover_release_compares_two_angles_and_records_over_center_witness(self) -> None:
        path, rows, metadata = self.trace("rollover", "rollover", duration="3")
        self.assertEqual([run["initial_roll_angle_deg"] for run in metadata["runs"]], [35.0, 55.0, 75.0])
        reference = metadata["rigid_tipping_reference"]
        self.assertLess(35.0, reference["critical_tilt_angle_deg"])
        self.assertLess(reference["critical_tilt_angle_deg"], 55.0)
        sphere_reference = metadata["spherical_tire_center_reference"]
        self.assertLess(55.0, sphere_reference["estimated_sign_change_angle_deg"])
        self.assertLess(sphere_reference["estimated_sign_change_angle_deg"], 75.0)
        self.assertTrue(all(run["controls"] == {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": False} for run in metadata["runs"]))
        for run in metadata["runs"]:
            run_rows = [row for row in rows if row["run_id"] == run["run_id"]]
            initial_roll = float(run_rows[0]["roll_euler_rad"])
            self.assertAlmostEqual(math.degrees(initial_roll), run["initial_roll_angle_deg"], places=7)
        _, report_path = self.analyze(path)
        report = json.loads(report_path.read_text(encoding="utf-8"))
        analysis = report["independent_analysis"]
        self.assertTrue(analysis["angle_pair_straddles_rigid_reference"])
        self.assertTrue(analysis["over_center_witness_exceeds_spherical_reference"])
        self.assertTrue(analysis["observed_behavior_is_qualitative"])
        trials = analysis["neutral_release_trials"]
        self.assertEqual([run["relation_to_rigid_reference"] for run in trials], ["below", "above", "above"])
        self.assertEqual([run["relation_to_spherical_tire_center_reference"] for run in trials], ["below", "below", "above"])
        self.assertEqual(report["solver_version"], metadata["solver_version"])
        for run in trials[:2]:
            self.assertGreaterEqual(run["maximum_absolute_roll_deg"], run["initial_tilt_deg"] - 1e-5)
            self.assertEqual(run["final_wheel_contacts_fl_fr_rl_rr"], [True, True, True, True])
            self.assertIsNotNone(run["first_four_wheel_contact_time_s"])
            self.assertLess(abs(run["final_roll_deg"]), 1.0)
        witness = trials[2]
        self.assertEqual(witness["initial_tilt_deg"], 75.0)
        self.assertIsNotNone(witness["first_hull_contact_time_s"])
        self.assertGreater(witness["maximum_hull_probes_in_contact"], 0)
        self.assertGreater(witness["maximum_absolute_roll_deg"], 90.0)
        self.assertTrue(witness["final_is_inverted"])
        self.assertLess(witness["final_body_down_world_ned_z"], 0.0)
        self.assertEqual(sum(witness["final_wheel_contacts_fl_fr_rl_rr"]), 1)

    def test_repeated_bump_recording_bytes_are_deterministic(self) -> None:
        first, _, _ = self.trace("bump", "bump-repeat-a")
        second, _, _ = self.trace("bump", "bump-repeat-b")
        self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_invalid_options_refuse_exports(self) -> None:
        cases = [
            [],
            ["--scenario=unknown", "--output=" + str(self.directory / "invalid-0.csv")],
            ["--scenario=drop", "--scenario=bump", "--output=" + str(self.directory / "invalid-1.csv")],
            ["--scenario=drop", "--duration=nan", "--output=" + str(self.directory / "invalid-2.csv")],
            ["--scenario=roll", "--output=" + str(self.directory / "invalid-3.csv")],
            ["--scenario=drop", "--unknown=yes", "--output=" + str(self.directory / "invalid-4.csv")],
            ["--scenario=drop", "--output=" + str(self.directory / "invalid-5.csv"), "--output=" + str(self.directory / "invalid-5.csv")],
            ["--scenario=drop", "--duration=0", "--output=" + str(self.directory / "invalid-6.csv")],
            ["--scenario=drop", "--duration=1.001", "--output=" + str(self.directory / "invalid-7.csv")],
            ["--scenario=drop", "--output=" + str(self.directory / "bad-extension.txt")],
        ]
        for index, arguments in enumerate(cases):
            with self.subTest(arguments=arguments):
                self.run_engine(arguments, success=False)
                for path in self.directory.glob(f"invalid-{index}.*"):
                    self.assertFalse(path.exists())
        self.assertFalse((self.directory / "bad-extension.txt").exists())

    def test_runner_refuses_to_replace_existing_outputs(self) -> None:
        path = self.directory / "preserve.csv"
        sidecar = path.with_suffix(".json")
        path.write_bytes(b"csv marker")
        sidecar.write_bytes(b"json marker")
        self.run_engine(["--scenario=drop", "--output=" + str(path)], success=False)
        self.assertEqual(path.read_bytes(), b"csv marker")
        self.assertEqual(sidecar.read_bytes(), b"json marker")

    def test_analyzer_refuses_csv_tampering(self) -> None:
        path, _, _ = self.trace("drop", "tampered-drop")
        path.write_bytes(path.read_bytes() + b"\n")
        result, _ = self.analyze(path, success=False)
        self.assertIn("CSV SHA-256", result.stderr)


if __name__ == "__main__":
    unittest.main()
