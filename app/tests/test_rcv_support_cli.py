"""RCV-04b: exercise the real four-corner support bench CLI and CSV export."""
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
RUNNER = ROOT / "research/rc-monster-truck/run_support_bench.gd"
PROFILE = ROOT / "research/rc-monster-truck/support_bench.json"
CORNERS = ("fl", "fr", "rl", "rr")
STATE_COLUMNS = (
    "z_m",
    "roll_rad",
    "pitch_rad",
    "zu_fl_m",
    "zu_fr_m",
    "zu_rl_m",
    "zu_rr_m",
    "vz_m_per_s",
    "roll_rate_rad_per_s",
    "pitch_rate_rad_per_s",
    "vu_fl_m_per_s",
    "vu_fr_m_per_s",
    "vu_rl_m_per_s",
    "vu_rr_m_per_s",
)
QUANTITIES = (
    "road_m",
    "tire_n",
    "spring_n",
    "spring_compression_m",
    "tire_compression_m",
    "contact",
)
CSV_COLUMNS = (
    ("time_s",)
    + STATE_COLUMNS
    + tuple(f"{corner}_{quantity}" for corner in CORNERS for quantity in QUANTITIES)
    + ("energy_j", "damper_loss_w")
)


class SupportCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        configured = os.environ.get("OPENRC_TEST_GODOT")
        cls.engine = configured or subprocess.check_output(
            [str(ROOT / "app/get-godot.sh")], text=True
        ).strip()
        cls.work = tempfile.TemporaryDirectory(prefix="openrc-support-")
        cls.directory = Path(cls.work.name)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.work.cleanup()

    def run_engine(self, arguments: list[str], success: bool = True) -> str:
        result = subprocess.run(
            [
                self.engine,
                "--headless",
                "--audio-driver",
                "Dummy",
                "--path",
                str(ROOT / "app"),
                "--script",
                str(RUNNER),
                "--",
                *arguments,
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        log = result.stdout + result.stderr
        self.assertEqual(result.returncode == 0, success, log)
        self.assertNotRegex(log, r"(?m)^(?:SCRIPT |SHADER )ERROR:")
        if success:
            self.assertNotRegex(log, r"(?m)^ERROR:")
        return log

    def trace(
        self,
        name: str,
        scenario: str | None = "heave",
        hz: int | None = 240,
        duration: float | None = 1.0,
        timing: bool | None = None,
        profile: Path | None = None,
    ) -> tuple[Path, list[dict[str, str]], dict[str, object]]:
        path = self.directory / f"{name}.csv"
        args: list[str] = []
        if scenario is not None:
            args.append(f"--scenario={scenario}")
        if hz is not None:
            args.append(f"--hz={hz}")
        if duration is not None:
            args.append(f"--duration={duration:g}")
        if profile is not None:
            args.append(f"--profile={profile}")
        args.append(f"--out={path}")
        if timing is not None:
            args.append(f"--timing={'true' if timing else 'false'}")
        self.run_engine(args)

        metadata_path = path.with_suffix(".json")
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            self.assertEqual(reader.fieldnames, list(CSV_COLUMNS))
            rows = list(reader)

        resolved_scenario = scenario or "heave"
        resolved_hz = hz or 240
        resolved_duration = duration if duration is not None else 2.0
        expected_samples = round(resolved_duration * resolved_hz) + 1
        self.assertTrue(metadata["complete"])
        self.assertEqual(metadata["model"], "linear-seven-dof-unilateral-tires-v1")
        self.assertEqual(metadata["state_order"], list(STATE_COLUMNS))
        self.assertEqual(metadata["scenario"], resolved_scenario)
        self.assertEqual(metadata["hz"], resolved_hz)
        self.assertEqual(metadata["substeps_per_tick"], 2)
        self.assertAlmostEqual(metadata["duration_s"], resolved_duration)
        self.assertEqual(metadata["sample_count"], expected_samples)
        self.assertEqual(len(rows), expected_samples)
        self.assertEqual(
            metadata["profile_sha256"],
            hashlib.sha256((profile or PROFILE).read_bytes()).hexdigest(),
        )
        self.assertEqual(metadata["csv_sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(metadata["profile_id"], "rcv-four-corner-synthetic-v1")
        self.assertEqual(len(STATE_COLUMNS), 14)

        contact_counts = [0, 0, 0, 0]
        peak_tire_loads = [0.0, 0.0, 0.0, 0.0]
        for index, row in enumerate(rows):
            self.assertEqual(set(row), set(CSV_COLUMNS))
            for key, value in row.items():
                self.assertTrue(math.isfinite(float(value)), (key, value))
            self.assertAlmostEqual(float(row["time_s"]), index / resolved_hz, places=9)
            self.assertGreaterEqual(float(row["damper_loss_w"]), 0.0)
            for corner_index, corner in enumerate(CORNERS):
                tire_load = float(row[f"{corner}_tire_n"])
                self.assertGreaterEqual(tire_load, 0.0, (corner, index, tire_load))
                contact = float(row[f"{corner}_contact"])
                self.assertIn(contact, (0.0, 1.0))
                contact_counts[corner_index] += int(contact)
                peak_tire_loads[corner_index] = max(peak_tire_loads[corner_index], tire_load)
        self.assertEqual(metadata["contact_sample_counts"], contact_counts)
        for actual, expected in zip(metadata["peak_sampled_tire_load_n"], peak_tire_loads, strict=True):
            self.assertAlmostEqual(actual, expected, delta=1e-12)
        self.assertEqual(metadata["timing"]["enabled"], timing is True)
        return path, rows, metadata

    def test_all_five_scenarios_export_finite_four_corner_rows(self) -> None:
        results = {}
        for scenario in ("heave", "roll", "pitch", "front_left_bump", "drop"):
            with self.subTest(scenario=scenario):
                results[scenario] = self.trace(scenario, scenario=scenario)

        _, heave_rows, _ = results["heave"]
        self.assertLess(max(abs(float(row["roll_rad"])) for row in heave_rows), 1e-12)
        self.assertLess(max(abs(float(row["pitch_rad"])) for row in heave_rows), 1e-12)

        _, roll_rows, _ = results["roll"]
        self.assertAlmostEqual(float(roll_rows[0]["roll_rad"]), 0.01, places=14)
        _, pitch_rows, _ = results["pitch"]
        self.assertAlmostEqual(float(pitch_rows[0]["pitch_rad"]), 0.01, places=14)

        _, bump_rows, _ = results["front_left_bump"]
        bump_index = round(0.3 * 240)
        bump = bump_rows[bump_index]
        self.assertAlmostEqual(float(bump["time_s"]), 0.3, places=12)
        self.assertGreater(float(bump["fl_road_m"]), 0.0024)
        self.assertGreater(float(bump["roll_rad"]), 0.0)
        self.assertLess(float(bump["pitch_rad"]), 0.0)

        _, drop_rows, drop_metadata = results["drop"]
        self.assertTrue(all(float(drop_rows[0][f"{corner}_contact"]) == 0.0 for corner in CORNERS))
        self.assertTrue(any(any(float(row[f"{corner}_contact"]) == 1.0 for corner in CORNERS) for row in drop_rows))
        self.assertTrue(any(count > 0 for count in drop_metadata["contact_sample_counts"]))

    def test_default_rate_duration_and_scenario(self) -> None:
        _, rows, metadata = self.trace(
            "defaults", scenario=None, hz=None, duration=None, timing=None
        )
        self.assertEqual(metadata["scenario"], "heave")
        self.assertEqual(metadata["hz"], 240)
        self.assertEqual(metadata["duration_s"], 2.0)
        self.assertEqual(len(rows), 481)

    def test_refinement_rates_export_expected_sample_counts(self) -> None:
        for hz in (480, 960, 1920):
            with self.subTest(hz=hz):
                self.trace(f"heave-{hz}", scenario="heave", hz=hz, duration=1.0)

    def test_repeat_and_timing_modes_preserve_csv_bytes(self) -> None:
        first, _, _ = self.trace("repeat-a", scenario="drop")
        second, _, _ = self.trace("repeat-b", scenario="drop")
        self.assertEqual(first.read_bytes(), second.read_bytes())

        baseline, _, _ = self.trace("timing-off", scenario="front_left_bump", timing=False)
        measured, _, metadata = self.trace("timing-on", scenario="front_left_bump", timing=True)
        self.assertEqual(baseline.read_bytes(), measured.read_bytes())
        self.assertEqual(metadata["timing"]["warmup_ticks"], 240)
        self.assertEqual(metadata["timing"]["measured_ticks"], 240)
        self.assertIn(metadata["timing"]["unit"], ("microseconds", "us"))

    def test_invalid_options_refuse_without_success_artifacts(self) -> None:
        invalid = (
            ("missing-out", ["--scenario=heave"], False),
            ("unknown-option", ["--unknown=value"], True),
            ("unknown-scenario", ["--scenario=aircraft"], True),
            ("duplicate-option", ["--hz=240", "--hz=480"], True),
            ("zero-hz", ["--hz=0"], True),
            ("unsupported-hz", ["--hz=241"], True),
            ("fractional-hz", ["--hz=240.0"], True),
            ("zero-duration", ["--duration=0"], True),
            ("negative-duration", ["--duration=-1"], True),
            ("nan-duration", ["--duration=nan"], True),
            ("infinite-duration", ["--duration=inf"], True),
            ("negative-infinite-duration", ["--duration=-inf"], True),
            ("fractional-duration", ["--duration=0.001"], True),
            ("tiny-duration", ["--duration=1e-15"], True),
            ("oversize-duration", ["--duration=31"], True),
        )
        for name, args, add_output in invalid:
            with self.subTest(case=name):
                path = self.directory / f"invalid-{name}.csv"
                command = list(args)
                if add_output:
                    command.append(f"--out={path}")
                self.run_engine(command, success=False)
                self.assertFalse(path.exists())
                self.assertFalse(path.with_suffix(".json").exists())

    def test_malformed_profiles_refuse_without_export(self) -> None:
        malformed = ("{", "[]", '{"format":"openrc-support-bench"}')
        for index, contents in enumerate(malformed):
            with self.subTest(index=index):
                profile = self.directory / f"bad-profile-{index}.json"
                profile.write_text(contents, encoding="utf-8")
                output = self.directory / f"bad-profile-output-{index}.csv"
                self.run_engine([f"--profile={profile}", f"--out={output}"], success=False)
                self.assertFalse(output.exists())
                self.assertFalse(output.with_suffix(".json").exists())

    def test_output_cannot_replace_profile_or_existing_artifacts(self) -> None:
        protected_profile = self.directory / "protected-profile.json"
        profile_bytes = PROFILE.read_bytes()
        protected_profile.write_bytes(profile_bytes)
        profile_csv = protected_profile.with_suffix(".csv")
        self.run_engine(
            [f"--profile={protected_profile}", f"--out={profile_csv}"], success=False
        )
        self.assertEqual(protected_profile.read_bytes(), profile_bytes)
        self.assertFalse(profile_csv.exists())

        existing_csv = self.directory / "existing-csv.csv"
        csv_bytes = b"preserve existing CSV bytes\n"
        existing_csv.write_bytes(csv_bytes)
        self.run_engine([f"--out={existing_csv}"], success=False)
        self.assertEqual(existing_csv.read_bytes(), csv_bytes)
        self.assertFalse(existing_csv.with_suffix(".json").exists())

        existing_sidecar = self.directory / "existing-sidecar.json"
        sidecar_bytes = b"preserve existing sidecar bytes\n"
        existing_sidecar.write_bytes(sidecar_bytes)
        sidecar_csv = existing_sidecar.with_suffix(".csv")
        self.run_engine([f"--out={sidecar_csv}"], success=False)
        self.assertEqual(existing_sidecar.read_bytes(), sidecar_bytes)
        self.assertFalse(sidecar_csv.exists())

    def test_small_angle_envelope_failure_has_no_success_sidecar(self) -> None:
        profile = self.directory / "low-roll-inertia.json"
        data = json.loads(PROFILE.read_text(encoding="utf-8"))
        data["parameters"]["roll_inertia_kg_m2"]["value"] = 1e-5
        profile.write_text(json.dumps(data, allow_nan=False), encoding="utf-8")
        output = self.directory / "small-angle-failure.csv"
        log = self.run_engine(
            [
                "--scenario=roll",
                "--duration=1",
                "--hz=240",
                f"--profile={profile}",
                f"--out={output}",
            ],
            success=False,
        )
        self.assertIn("nonfinite state or small-angle envelope exceeded", log)
        self.assertFalse(output.with_suffix(".json").exists())


if __name__ == "__main__":
    unittest.main()
