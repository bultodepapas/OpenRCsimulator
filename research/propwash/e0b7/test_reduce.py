#!/usr/bin/env python3
"""Known-answer, provenance, malformed-input and process checks for E0b7."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("e0b7_reduce", HERE / "reduce.py")
REDUCER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REDUCER)


def synthetic_campaign():
    return json.loads((HERE / "example.synthetic.json").read_bytes())


def reading(sample, channel):
    return sample[channel]


def measured_fixture(root):
    """Build a provenance plumbing fixture from fake bytes, never real evidence."""
    campaign = synthetic_campaign()
    campaign["evidence"] = "measured"
    raw_dir = root / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)
    for index, run in enumerate(campaign["runs"]):
        for sample in run["samples"]:
            for reading_value in sample.values():
                reading_value["kind"] = "measured"
                reading_value["source"] = "Test-only fake measurement fixture; no aircraft observation."
        raw_path = raw_dir / f"source-{index}.bin"
        raw_path.write_bytes(f"fake raw bytes for test run {index}".encode())
        run["raw_sources"] = [{
            "path": f"raw/{raw_path.name}",
            "sha256": hashlib.sha256(raw_path.read_bytes()).hexdigest(),
        }]
    return campaign


def sample_at(campaign, run_id, index):
    return next(run for run in campaign["runs"] if run["id"] == run_id)["samples"][index]


class ReductionTests(unittest.TestCase):
    def setUp(self):
        self.campaign = synthetic_campaign()
        self.temporary = tempfile.TemporaryDirectory(prefix="openrc-e0b7-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_analytic_endpoint_deltas_and_absolute_bound_sum(self):
        report = REDUCER.reduce(self.campaign, self.root)
        nose = next(run for run in report["runs"] if run["id"] == "nose_unloading-calibration")
        load = nose["channels"]["nose_load"]["delta"]
        self.assertEqual(load, {
            "value": -4.0, "bound": 0.2, "unit": "N", "kind": "derived",
            "interval": [-4.2, -3.8],
        })
        clearance = nose["channels"]["nose_clearance"]["delta"]
        self.assertEqual(clearance["value"], 0.01)
        self.assertAlmostEqual(clearance["bound"], 0.004)
        self.assertAlmostEqual(clearance["interval"][0], 0.006)
        self.assertAlmostEqual(clearance["interval"][1], 0.014)
        self.assertEqual(nose["channels"]["nose_load"]["sampled_min"], 0)
        self.assertEqual(nose["channels"]["nose_load"]["sampled_max"], 4)
        self.assertEqual(nose["channels"]["nose_load"]["sampled_envelope"], [-0.1, 4.1])
        self.assertTrue(nose["resolved_endpoint_load_decrease"])

    def test_near_zero_load_decrease_is_unresolved(self):
        control = REDUCER.reduce(self.campaign, self.root)
        control_nose = next(run for run in control["runs"] if run["id"] == "nose_unloading-calibration")
        self.assertTrue(control_nose["resolved_endpoint_load_decrease"])

        campaign = copy.deepcopy(self.campaign)
        sample_at(campaign, "nose_unloading-calibration", 2)["nose_load"]["value"] = 3.95
        report = REDUCER.reduce(campaign, self.root)
        nose = next(run for run in report["runs"] if run["id"] == "nose_unloading-calibration")
        interval = nose["channels"]["nose_load"]["delta"]["interval"]
        self.assertLess(interval[0], 0)
        self.assertGreater(interval[1], 0)
        self.assertFalse(nose["resolved_endpoint_load_decrease"])

    def test_interior_transient_changes_sampled_extrema_not_endpoint_delta(self):
        baseline = REDUCER.reduce(self.campaign, self.root)
        baseline_nose = next(run for run in baseline["runs"] if run["id"] == "nose_unloading-calibration")
        baseline_delta = baseline_nose["channels"]["nose_load"]["delta"]

        campaign = copy.deepcopy(self.campaign)
        sample_at(campaign, "nose_unloading-calibration", 1)["nose_load"]["value"] = 10
        report = REDUCER.reduce(campaign, self.root)
        nose = next(run for run in report["runs"] if run["id"] == "nose_unloading-calibration")
        self.assertEqual(nose["channels"]["nose_load"]["delta"], baseline_delta)
        self.assertEqual(nose["channels"]["nose_load"]["sampled_min"], 0)
        self.assertEqual(nose["channels"]["nose_load"]["sampled_max"], 10)
        self.assertEqual(nose["channels"]["nose_load"]["sampled_envelope"], [-0.1, 10.1])

    def test_original_campaign_is_retained_in_report(self):
        report = REDUCER.reduce(self.campaign, self.root)
        self.assertEqual(report["inputs"], self.campaign)

    def test_all_three_maneuvers_are_reduced_and_covered(self):
        report = REDUCER.reduce(self.campaign, self.root)
        maneuvers = {run["maneuver"] for run in report["runs"]}
        self.assertEqual(maneuvers, {"nose_unloading", "taxi_blip", "takeoff_swing"})
        self.assertEqual(set(report["coverage"]["calibration"]), maneuvers)
        self.assertEqual(set(report["coverage"]["held_out"]), maneuvers)
        self.assertFalse(report["physical_acceptance"])

    def test_partial_campaign_coverage_reports_only_present_maneuvers(self):
        campaign = copy.deepcopy(self.campaign)
        campaign["runs"] = [campaign["runs"][0], campaign["runs"][4]]
        report = REDUCER.reduce(campaign, self.root)
        self.assertEqual(report["coverage"], {
            "calibration": ["nose_unloading"],
            "held_out": ["taxi_blip"],
        })

    def test_heading_delta_uses_declared_unwrapped_values(self):
        report = REDUCER.reduce(self.campaign, self.root)
        taxi = next(run for run in report["runs"] if run["id"] == "taxi_blip-calibration")
        delta = taxi["channels"]["heading"]["delta"]
        self.assertEqual(delta["value"], 4)
        self.assertAlmostEqual(delta["bound"], 0.4)
        self.assertAlmostEqual(delta["interval"][0], 3.6)
        self.assertAlmostEqual(delta["interval"][1], 4.4)

    def test_clearance_bounds_overlapping_zero_do_not_resolve_separation(self):
        report = REDUCER.reduce(self.campaign, self.root)
        nose = next(run for run in report["runs"] if run["id"] == "nose_unloading-calibration")
        self.assertEqual(nose["resolved_clearance_sample_indices"], [2])
        self.assertLessEqual(
            reading(sample_at(self.campaign, "nose_unloading-calibration", 1), "nose_clearance")["value"]
            - reading(sample_at(self.campaign, "nose_unloading-calibration", 1), "nose_clearance")["bound"],
            0,
        )

    def test_measured_campaign_requires_verified_original_bytes(self):
        campaign = measured_fixture(self.root)
        report = REDUCER.reduce(campaign, self.root)
        self.assertEqual(report["evidence"], "measured")
        self.assertEqual(len(report["verified_sources"]), len(campaign["runs"]))
        for run in campaign["runs"]:
            source = run["raw_sources"][0]
            self.assertEqual(report["verified_sources"][source["path"]], source["sha256"])

        source = campaign["runs"][0]["raw_sources"][0]
        source_path = self.root / source["path"]
        original_bytes = source_path.read_bytes()
        source_path.unlink()
        with self.assertRaisesRegex(ValueError, "missing original source"):
            REDUCER.reduce(campaign, self.root)
        source_path.write_bytes(original_bytes)
        source_path.write_bytes(original_bytes + b" changed after reduction")
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            REDUCER.reduce(campaign, self.root)
        source_path.write_bytes(original_bytes)

        missing = copy.deepcopy(campaign)
        missing["runs"][0]["raw_sources"] = []
        with self.assertRaises(ValueError):
            REDUCER.reduce(missing, self.root)

        mismatched = copy.deepcopy(campaign)
        mismatched["runs"][0]["raw_sources"][0]["sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            REDUCER.reduce(mismatched, self.root)

    def test_synthetic_readings_cannot_be_labeled_measured(self):
        campaign = measured_fixture(self.root)
        campaign["runs"][0]["samples"][0]["rpm"]["kind"] = "synthetic"
        with self.assertRaisesRegex(ValueError, "evidence kind"):
            REDUCER.reduce(campaign, self.root)

        campaign = synthetic_campaign()
        campaign["runs"][0]["samples"][0]["rpm"]["kind"] = "measured"
        with self.assertRaises(ValueError):
            REDUCER.reduce(campaign, self.root)

    def test_measured_campaign_accepts_derived_reading_kinds(self):
        campaign = measured_fixture(self.root)
        campaign["runs"][0]["samples"][0]["rpm"]["kind"] = "derived"
        report = REDUCER.reduce(campaign, self.root)
        self.assertEqual(report["inputs"]["runs"][0]["samples"][0]["rpm"]["kind"], "derived")

    def test_absolute_and_parent_traversal_source_paths_are_refused(self):
        measured = measured_fixture(self.root)
        original_path = measured["runs"][0]["raw_sources"][0]["path"]
        absolute_path = str((self.root / original_path).resolve())
        for invalid_path in (absolute_path, "../outside.bin"):
            campaign = copy.deepcopy(measured)
            campaign["runs"][0]["raw_sources"][0]["path"] = invalid_path
            with self.subTest(path=invalid_path), self.assertRaisesRegex(ValueError, "relative"):
                REDUCER.reduce(campaign, self.root)

    def test_split_rejects_shared_trial_identity_across_roles(self):
        campaign = synthetic_campaign()
        calibration = next(run for run in campaign["runs"] if run["role"] == "calibration")
        held_out = next(run for run in campaign["runs"] if run["role"] == "held_out")
        held_out["independent_trial"] = calibration["independent_trial"]
        with self.assertRaisesRegex(ValueError, "leakage"):
            REDUCER.reduce(campaign, self.root)

    def test_split_rejects_same_source_bytes_at_different_paths(self):
        campaign = measured_fixture(self.root)
        calibration, held_out = campaign["runs"][0], campaign["runs"][-1]
        first = calibration["raw_sources"][0]
        second = held_out["raw_sources"][0]
        self.assertNotEqual(first["path"], second["path"])
        first_bytes = (self.root / first["path"]).read_bytes()
        (self.root / second["path"]).write_bytes(first_bytes)
        second["sha256"] = hashlib.sha256(first_bytes).hexdigest()
        with self.assertRaisesRegex(ValueError, "leakage"):
            REDUCER.reduce(campaign, self.root)

    def test_malformed_types_units_nonfinite_order_and_unknown_fields(self):
        mutations = []

        def mutate(path, value):
            campaign = copy.deepcopy(self.campaign)
            node = campaign
            for key in path[:-1]:
                node = node[key]
            node[path[-1]] = value
            mutations.append((path, campaign))

        mutate(("runs", 0, "samples", 0, "throttle", "value"), True)
        mutate(("runs", 0, "samples", 0, "rpm", "value"), "2000")
        mutate(("runs", 0, "samples", 0, "nose_load", "bound"), -0.1)
        mutate(("runs", 0, "samples", 0, "nose_load", "unit"), "kg")
        mutate(("runs", 0, "samples", 0, "rpm", "value"), float("nan"))
        mutate(("runs", 0, "samples", 0, "rpm", "bound"), float("inf"))
        mutate(("runs", 0, "samples", 1, "t", "value"), 0.01)
        mutate(("runs", 0, "samples", 1, "t", "value"), -1)
        mutate(("runs", 0, "samples", 0, "extra"), {"value": 3})
        mutate(("runs", 0, "samples", 0, "rpm", "extra"), "unknown")
        mutate(("unexpected",), True)

        for path, campaign in mutations:
            with self.subTest(path=path), self.assertRaises((ValueError, TypeError)):
                REDUCER.reduce(campaign, self.root)

        for raw in (b'{"a":1,"a":2}', b'{"a":NaN}', b'{"a":Infinity}'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                REDUCER.load(raw)

    def test_difference_overflow_is_refused(self):
        campaign = copy.deepcopy(self.campaign)
        taxi = next(run for run in campaign["runs"] if run["id"] == "taxi_blip-calibration")
        taxi["samples"][0]["heading"]["bound"] = 1e308
        taxi["samples"][-1]["heading"]["bound"] = 1e308
        with self.assertRaisesRegex(ValueError, "overflow"):
            REDUCER.reduce(campaign, self.root)


class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="openrc-e0b7-cli-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.raw_dir = self.root / "raw"
        self.raw_dir.mkdir()
        self.reducer = self.root / "reduce.py"
        shutil.copy2(HERE / "reduce.py", self.reducer)
        self.campaign_path = self.root / "campaign.json"
        self.output_path = self.root / "report.json"
        self.campaign = measured_fixture(self.root)
        self.campaign_bytes = (json.dumps(self.campaign, sort_keys=True, indent=2) + "\n").encode()
        self.campaign_path.write_bytes(self.campaign_bytes)

    def run_cli(self, *arguments):
        return subprocess.run(
            [sys.executable, str(self.reducer), str(self.campaign_path), *map(str, arguments)],
            capture_output=True,
            timeout=10,
        )

    def test_deterministic_json_and_exact_input_hashes(self):
        first, second = self.run_cli(), self.run_cli()
        self.assertEqual(first.returncode, 0, first.stderr.decode())
        self.assertEqual(first.stdout, second.stdout)
        report = json.loads(first.stdout)
        expected = {
            "campaign": hashlib.sha256(self.campaign_path.read_bytes()).hexdigest(),
            "reducer": hashlib.sha256(self.reducer.read_bytes()).hexdigest(),
        }
        self.assertEqual(report["input_sha256"], expected)
        written = self.run_cli("--output", self.output_path)
        self.assertEqual(written.returncode, 0, written.stderr.decode())
        self.assertEqual(self.output_path.read_bytes(), first.stdout)

    def test_cli_failure_preserves_existing_output(self):
        self.output_path.write_bytes(b"previous report\n")
        self.campaign["format"] = "unsupported"
        self.campaign_path.write_text(json.dumps(self.campaign))
        before = self.output_path.read_bytes()
        result = self.run_cli("--output", self.output_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"E0b7:", result.stderr)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(self.output_path.read_bytes(), before)

    def test_output_aliases_campaign_raw_and_reducer(self):
        sources = [
            self.campaign_path,
            self.root / self.campaign["runs"][0]["raw_sources"][0]["path"],
            self.reducer,
        ]
        for source in sources:
            original = source.read_bytes()
            for kind in ("direct", "symlink", "hardlink"):
                alias = self.root / "output-alias"
                alias.unlink(missing_ok=True)
                if kind == "symlink":
                    alias.symlink_to(source)
                elif kind == "hardlink":
                    os.link(source, alias)
                else:
                    alias = source
                with self.subTest(source=source.name, kind=kind):
                    result = self.run_cli("--output", alias)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(b"aliases", result.stderr)
                    self.assertEqual(source.read_bytes(), original)


if __name__ == "__main__":
    unittest.main(verbosity=2)
