#!/usr/bin/env python3
"""VAL-3 contract and actual-engine mutation tests; never modify app/ or published reports."""
import contextlib
import copy
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import dashboard as d


class ReferenceContract(unittest.TestCase):
    def setUp(self):
        self.ref = d.references()[0]

    def test_imports_have_explicit_unknowns_and_bands(self):
        refs = d.references()
        self.assertEqual({r["id"] for r in refs}, {"us120", "us25e"})
        for ref in refs:
            self.assertEqual(len(ref["rows"]), 5)
            for row in ref["rows"]:
                self.assertIsNone(row["uncertainty"])
                self.assertIsNone(row["used_for_tuning"])
                self.assertEqual(row["band"] is None, row["metric"].endswith("zeta"))

    def test_invalid_reference_values(self):
        for value in (True, False, None, "16.33", 0, -1, float("inf"), float("nan")):
            with self.subTest(value=value):
                ref = copy.deepcopy(self.ref)
                ref["rows"][0]["value"] = value
                with self.assertRaises(ValueError):
                    d.validate_reference(ref)

    def test_missing_unknown_duplicate_and_mislabeled_fields(self):
        mutations = [
            lambda r: r.pop("conditions"),
            lambda r: r.update(unknown=1),
            lambda r: r["rows"].append(copy.deepcopy(r["rows"][0])),
            lambda r: r["rows"][0].update(unit="Hz"),
            lambda r: r["rows"][0].update(kind="guessed"),
            lambda r: r["rows"][0].update(used_for_tuning=0),
            lambda r: r["rows"][0].update(uncertainty=0.15),
            lambda r: r["rows"][0].update(source_locator=""),
            lambda r: r["rows"][0]["band"].update(relative=True),
            lambda r: r["rows"][0]["band"].update(relative=1),
            lambda r: r["rows"][0]["band"].update(kind="measured"),
            lambda r: r["source"].update(status="verified"),
            lambda r: r["conditions"].update(throttle=1.1),
            lambda r: r["conditions"].update(span_m=0),
            lambda r: r["conditions"].update(wind_mps=-1),
            lambda r: r["comparison"].update(method="unknown"),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                ref = copy.deepcopy(self.ref)
                mutate(ref)
                with self.assertRaises(ValueError):
                    d.validate_reference(ref)

    def test_json_rejects_duplicate_keys_and_nonfinite_constants(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"bad.json"
            for value in ('{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}', '{"a":-Infinity}'):
                path.write_text(value)
                with self.assertRaises(ValueError):
                    d.strict_load(path)

    def test_missing_airframe_or_metric_is_not_a_complete_dashboard(self):
        ref = copy.deepcopy(self.ref)
        ref["rows"].pop()
        with self.assertRaises(ValueError):
            d.validate_reference(ref)
        with tempfile.TemporaryDirectory() as directory:
            here = Path(directory)
            (here/"references").mkdir()
            (here/"references/only.json").write_text(json.dumps(self.ref))
            with patch.object(d, "HERE", here), self.assertRaisesRegex(ValueError, "both US120 and 25e"):
                d.references()


class ComparisonContract(unittest.TestCase):
    def test_band_endpoints_and_unstable_mode(self):
        ref = copy.deepcopy(d.references()[0])
        ref["rows"] = [dict(ref["rows"][2], value=10)]
        for sim, status in ((9, "IN BAND"), (11, "IN BAND"), (8.999, "OUTSIDE"), (11.001, "OUTSIDE"), (-10, "OUTSIDE")):
            rows = d.comparisons([ref], {"cases": {ref["id"]: {"roll_rate": sim}}})
            self.assertEqual(rows[0]["status"], status)

    def test_reduced_frequency_uses_each_airframes_length_and_speed(self):
        ref = copy.deepcopy(d.references()[1])
        ref["conditions"].update(chord_m=2, span_m=6, speed_mps=10)
        ref["rows"] = [dict(row, value=4) for row in ref["rows"]]
        samples = {"chord_m": 1, "span_m": 3, "cases": {ref["id"]: {"speed_mps": 5, **{metric: 4 for metric in d.UNITS}}}}
        rows = {r["metric"]: r for r in d.comparisons([ref], samples)}
        self.assertAlmostEqual(rows["sp_wn"]["reference"], 0.4)
        self.assertAlmostEqual(rows["roll_rate"]["reference"], 1.2)
        self.assertAlmostEqual(rows["dr_wn"]["sim"], 1.2)
        for row in rows.values():
            self.assertAlmostEqual(row["ratio"], 1)
        self.assertEqual(rows["sp_zeta"]["reference"], 4)
        self.assertEqual(rows["sp_zeta"]["status"], "UNASSESSED")


class ReportIntegrity(unittest.TestCase):
    def test_freshness_covers_data_code_and_reference_edits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            here = root/"research/validation"
            here.mkdir(parents=True)
            inventory = d.fingerprint()
            for relative in inventory:
                target = root/relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((d.ROOT/relative).read_bytes())
            with patch.object(d, "ROOT", root), patch.object(d, "HERE", here):
                self.assertEqual(d.fingerprint(), inventory)
                for relative in ("app/physics/flight_modes.gd", "app/data/aircraft/jensen_ugly_stik_60.json", "research/validation/references/us120.json", "research/validation/collect.gd"):
                    target = root/relative
                    original = target.read_bytes()
                    target.write_bytes(original+b"\n")
                    self.assertNotEqual(d.fingerprint(), inventory)
                    target.write_bytes(original)
                added = root/"app/physics/future/module.gd"
                added.parent.mkdir()
                added.write_text("extends RefCounted\n")
                self.assertIn("app/physics/future/module.gd", d.fingerprint())

    def test_stale_missing_and_tampered_outputs_fail_without_writes(self):
        doc = {"rows": [{"status": "OUTSIDE"}]}
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            with self.assertRaises(ValueError):
                d.publish(doc, "test\n", check=True, directory=directory)
            d.publish(doc, "test\n", directory=directory)
            d.publish(doc, "test\n", check=True, directory=directory)
            for name in ("snapshot.json", "dashboard.md"):
                path = directory/name
                original = path.read_bytes()
                path.write_text("tampered\n")
                with self.assertRaises(ValueError):
                    d.publish(doc, "test\n", check=True, directory=directory)
                self.assertEqual(path.read_text(), "tampered\n")
                path.write_bytes(original)
            with self.assertRaises(ValueError):
                d.publish({"rows": []}, "test\n", check=True, directory=directory)

    def test_failed_replace_preserves_previous_file_and_cleans_temporary(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"dashboard.md"
            path.write_text("previous\n")
            with patch.object(d.os, "replace", side_effect=OSError("injected disk failure")):
                with self.assertRaises(OSError):
                    d.atomic_write(path, "replacement\n")
            self.assertEqual(path.read_text(), "previous\n")
            self.assertEqual(list(Path(directory).iterdir()), [path])

    def test_collection_failure_never_publishes(self):
        for failure in (ValueError("engine error"), subprocess.TimeoutExpired("godot", 60)):
            with patch.object(d, "build", side_effect=failure), patch.object(d, "publish") as publish, patch("sys.argv", ["dashboard.py"]), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(d.main(), 1)
                publish.assert_not_called()

    def test_concurrent_input_change_aborts(self):
        with patch.object(d, "fingerprint", side_effect=[{"hash": "before"}, {"hash": "after"}]), patch.object(d, "collect", return_value={}):
            with self.assertRaisesRegex(ValueError, "inputs changed"):
                d.build(refs=[])

    def test_engine_zero_exit_with_error_or_no_samples_is_failure(self):
        for output in ("SCRIPT ERROR: failure\n", "ERROR: failure\n", "Godot started but never wrote samples\n"):
            with patch.object(d.subprocess, "check_output", return_value="/fake/godot"), patch.object(d.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout=output)):
                with self.assertRaises(ValueError):
                    d.collect(d.references())


class EngineIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.before = d.fingerprint()
        cls.refs = d.references()
        cls.baseline = d.collect(cls.refs)
        cls.mutated = d.collect(cls.refs, clp_scale=2)

    def test_ten_finite_rows_and_separate_software_regression(self):
        rows = d.comparisons(self.refs, self.baseline)
        self.assertEqual(len(rows), 10)
        self.assertTrue(all(d.number(row["ratio"]) for row in rows))
        regression = self.baseline["regression_15_mps"]
        self.assertEqual(len(regression["actual"]), 9)
        for actual, expected in zip(regression["actual"], regression["expected"]):
            self.assertLessEqual(abs(actual-expected), abs(expected)*regression["relative_tolerance"])

    def test_equal_nominal_cl(self):
        ref = next(r for r in self.refs if r["id"] == "us25e")
        c = ref["conditions"]
        expected = 2*c["mass_kg"]*d.G/(d.RHO*c["speed_mps"]**2*c["area_m2"])
        self.assertAlmostEqual(self.baseline["cases"][ref["id"]]["lift_coefficient"], expected, places=12)

    def test_clp_mutation_is_visible_against_actual_references(self):
        before = d.comparisons(self.refs, self.baseline)
        after = d.comparisons(self.refs, self.mutated)
        for old, new in zip(before, after):
            if old["metric"] == "roll_rate":
                self.assertEqual(old["status"], "OUTSIDE")  # Existing discrepancy, not a green baseline.
                self.assertEqual(new["status"], "OUTSIDE")
                self.assertGreater(new["ratio"], old["ratio"]*1.8)

    def test_synthetic_matching_roll_reference_turns_green_to_red(self):
        # Verification fixture ONLY: never published as independent evidence.
        refs = copy.deepcopy(self.refs)
        for ref in refs:
            row = next(row for row in ref["rows"] if row["metric"] == "roll_rate")
            row["value"] = self.baseline["cases"][ref["id"]]["roll_rate"]
            if ref["comparison"]["method"] == "same_cl_reduced":
                case, c = self.baseline["cases"][ref["id"]], ref["conditions"]
                row["value"] *= self.baseline["span_m"]/(2*case["speed_mps"])/(c["span_m"]/(2*c["speed_mps"]))
            ref["rows"] = [row]
        self.assertEqual([r["status"] for r in d.comparisons(refs, self.baseline)], ["IN BAND"]*2)
        self.assertEqual([r["status"] for r in d.comparisons(refs, self.mutated)], ["OUTSIDE"]*2)

    def test_mutation_does_not_write_model_or_sources(self):
        self.assertEqual(d.fingerprint(), self.before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
