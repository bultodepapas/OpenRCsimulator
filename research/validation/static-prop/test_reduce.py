#!/usr/bin/env python3
"""VAL-7a analytic, contract and CLI tests; all fixtures are synthetic."""
import copy
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import reduce as r

HERE = Path(__file__).resolve().parent


def fixture():
    values = {"thrust": 4.6875, "rpm": 6000, "diameter": 0.25, "density": 1.2, "torque": 0.1}
    run = {name: {"value": value, "unit": r.UNITS[name], "u": value*0.001, "kind": "synthetic",
                  "source": "Invented analytic fixture; not aircraft measurements"} for name, value in values.items()}
    run.update(id="with-torque", notes="Matched idealized static operating point; corrected net thrust and shaft torque")
    return {"format": "openrc-static-prop v1", "evidence": "synthetic", "configuration": "Synthetic 0.25 m propeller; no real engine or aircraft",
            "static_conditions_confirmed": True, "runs": [run]}


def outputs(doc):
    return r.reduce_document(doc)["runs"][0]["outputs"]


class Physics(unittest.TestCase):
    def test_analytic_point(self):
        out = outputs(fixture())
        # n=100 revolutions/s; rho*n²*D⁴=46.875 N.
        self.assertAlmostEqual(out["ct"]["value"], 0.1, places=14)
        self.assertAlmostEqual(out["shaft_power"]["value"], 20*math.pi, places=12)
        self.assertAlmostEqual(out["cp"]["value"], 20*math.pi / 1171.875, places=14)
        disc_area = math.pi * 0.125**2
        vi = math.sqrt(4.6875/(2*1.2*disc_area))
        self.assertAlmostEqual(out["ideal_static_disc_power"]["value"], 4.6875*vi, places=12)
        self.assertAlmostEqual(out["static_figure_of_merit"]["value"], 4.6875*vi/(20*math.pi), places=14)

    def test_no_torque_does_not_invent_power_or_efficiency(self):
        doc = fixture()
        doc["runs"][0]["torque"] = None
        out = outputs(doc)
        for key in ("shaft_power", "cp", "static_figure_of_merit"):
            self.assertIsNone(out[key])
        self.assertAlmostEqual(out["ct"]["value"], 0.1)
        self.assertGreater(out["ideal_static_disc_power"]["value"], 0)

    def test_dimensional_similarity(self):
        baseline = outputs(fixture())
        for density_factor, rpm_factor, diameter_factor in ((2, 1, 1), (1, 2, 1), (1, 1, 2), (0.7, 1.3, 0.8)):
            doc = fixture()
            run = doc["runs"][0]
            factors = {"density": density_factor, "rpm": rpm_factor, "diameter": diameter_factor,
                       "thrust": density_factor*rpm_factor**2*diameter_factor**4,
                       "torque": density_factor*rpm_factor**2*diameter_factor**5}
            for key, factor in factors.items():
                run[key]["value"] *= factor
                run[key]["u"] *= factor
            out = outputs(doc)
            for key in ("ct", "cp", "static_figure_of_merit"):
                self.assertAlmostEqual(out[key]["value"], baseline[key]["value"], places=13)
                self.assertAlmostEqual(out[key]["u"], baseline[key]["u"], places=13)
            power_factor = density_factor*rpm_factor**3*diameter_factor**5
            self.assertAlmostEqual(out["shaft_power"]["value"], baseline["shaft_power"]["value"]*power_factor, places=10)

    def test_uncertainty_has_known_relative_weights(self):
        out = outputs(fixture())
        weights = {"ct": math.sqrt(22), "cp": math.sqrt(31), "shaft_power": math.sqrt(2),
                   "ideal_static_disc_power": math.sqrt(3.5), "static_figure_of_merit": math.sqrt(5.5)}
        for key, weight in weights.items():
            self.assertAlmostEqual(out[key]["u"]/out[key]["value"], weight*0.001, places=14)

    def test_analytic_sensitivities_against_finite_differences(self):
        doc = fixture()
        out = outputs(doc)
        for quantity, q in doc["runs"][0].items():
            if quantity not in r.UNITS:
                continue
            step = q["value"]*1e-5
            plus, minus = copy.deepcopy(doc), copy.deepcopy(doc)
            plus["runs"][0][quantity]["value"] += step
            minus["runs"][0][quantity]["value"] -= step
            hi, lo = outputs(plus), outputs(minus)
            for name, estimate in out.items():
                numerical = (hi[name]["value"] - lo[name]["value"])/(2*step)*q["u"]
                analytic = estimate["standard_uncertainty_contributions"].get(quantity, 0)
                with self.subTest(quantity=quantity, output=name):
                    self.assertAlmostEqual(analytic, numerical, delta=1e-9)

    def test_fom_uncertainty_cancels_shared_density_and_diameter_correctly(self):
        # FM = sqrt(2/pi) * Ct**1.5 / Cp. Treating Ct and Cp as independent
        # would badly overstate rho/D uncertainty because both reuse these inputs.
        doc = fixture()
        for name in r.UNITS:
            doc["runs"][0][name]["u"] = 0
        doc["runs"][0]["density"]["u"] = 0.012
        doc["runs"][0]["diameter"]["u"] = 0.0025
        out = outputs(doc)
        fom = out["static_figure_of_merit"]
        self.assertAlmostEqual(fom["value"], math.sqrt(2/math.pi)*out["ct"]["value"]**1.5/out["cp"]["value"])
        self.assertAlmostEqual(fom["u"]/fom["value"], math.hypot(0.005, 0.01))

    def test_above_unity_fom_is_reported_without_clamping(self):
        doc = fixture()
        doc["runs"][0]["torque"]["value"] = 0.001
        report = r.reduce_document(doc)["runs"][0]
        self.assertGreater(report["outputs"]["static_figure_of_merit"]["value"], 1)
        self.assertTrue(any("exceeds 1" in message for message in report["diagnostics"]))

    def test_large_uncertainty_is_visible(self):
        doc = fixture()
        doc["runs"][0]["rpm"]["u"] = 6000
        self.assertTrue(any("poorly resolved" in text for text in r.reduce_document(doc)["runs"][0]["diagnostics"]))


class Contract(unittest.TestCase):
    def test_invalid_quantity_values(self):
        for name in r.UNITS:
            for key, values in (("value", (0, -1, True, None, "10", math.nan, math.inf)), ("u", (-1, True, None, "1", math.nan, math.inf))):
                for value in values:
                    doc = fixture()
                    doc["runs"][0][name][key] = value
                    with self.subTest(quantity=name, key=key, value=value), self.assertRaises(ValueError):
                        outputs(doc)

    def test_strict_fields_units_and_provenance(self):
        changes = [lambda d: d.update(extra=1), lambda d: d.pop("configuration"),
                   lambda d: d.update(format="future"), lambda d: d.update(configuration=" "),
                   lambda d: d.update(evidence="verified"), lambda d: d.update(evidence="measured"),
                   lambda d: d.update(static_conditions_confirmed=False), lambda d: d.update(static_conditions_confirmed=1),
                   lambda d: d.update(runs=[]), lambda d: d["runs"].append(copy.deepcopy(d["runs"][0])),
                   lambda d: d["runs"][0].pop("torque"), lambda d: d["runs"][0].update(id=[]),
                   lambda d: d["runs"][0].update(notes=""), lambda d: d["runs"][0].update(throttle=0.5),
                   lambda d: d["runs"][0]["rpm"].update(unit="rps"), lambda d: d["runs"][0]["thrust"].update(unit="kgf"),
                   lambda d: d["runs"][0]["thrust"].update(kind="validated"), lambda d: d["runs"][0]["thrust"].update(source="")]
        for i, change in enumerate(changes):
            doc = fixture()
            change(doc)
            with self.subTest(change=i), self.assertRaises(ValueError):
                outputs(doc)

    def test_measured_label_preserves_declared_provenance_without_acceptance(self):
        doc = fixture()
        doc["evidence"] = "measured"
        for key in r.UNITS:
            doc["runs"][0][key]["kind"] = "measured"
        report = r.reduce_document(doc)
        self.assertEqual(report["evidence"], "measured")
        self.assertEqual(report["runs"][0]["outputs"]["ct"]["kind"], "derived")
        self.assertNotIn("validated", report)

    def test_measured_campaign_refuses_estimated_operating_readings(self):
        doc = fixture()
        doc["evidence"] = "measured"
        for key in r.UNITS:
            doc["runs"][0][key]["kind"] = "derived"
        outputs(doc)  # Net readings may be derived from documented measurement/tare corrections.
        for key in ("thrust", "rpm", "torque"):
            for kind in ("estimated", "manual"):
                changed = copy.deepcopy(doc)
                changed["runs"][0][key]["kind"] = kind
                with self.subTest(quantity=key, kind=kind), self.assertRaisesRegex(ValueError, "measurement-derived"):
                    outputs(changed)

    def test_duplicate_keys_nonfinite_and_malformed_json(self):
        for raw in (b'{"a":1,"a":2}', b'{"a":NaN}', b'{"a":Infinity}', b'{"a":-Infinity}', b'null', b'[]', b'{'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                r.reduce_bytes(raw)

    def test_numeric_extremes_fail_cleanly(self):
        for name, value in (("rpm", 1e-300), ("rpm", 1e300), ("diameter", 1e-300),
                            ("diameter", 1e300), ("thrust", 1e300), ("torque", 1e308)):
            doc = fixture()
            doc["runs"][0][name]["value"] = value
            with self.subTest(name=name, value=value), self.assertRaises(ValueError):
                r.reduce_bytes(json.dumps(doc).encode())

    def test_reproducibility_hashes_and_preserved_input(self):
        raw = json.dumps(fixture()).encode()
        before = hashlib.sha256(raw).hexdigest()
        out = r.reduce_bytes(raw)
        self.assertEqual(out, r.reduce_bytes(raw))
        self.assertEqual(out["input"], fixture())
        self.assertEqual(out["input_sha256"], before)
        self.assertEqual(out["reducer_sha256"], hashlib.sha256((HERE/"reduce.py").read_bytes()).hexdigest())
        self.assertNotEqual(out["input_sha256"], r.reduce_bytes(raw+b' ')["input_sha256"])

    def test_cli_success_and_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"input.json"
            for raw, code in ((json.dumps(fixture()).encode(), 0), (b'null', 1), (b'{"a":NaN}', 1)):
                path.write_bytes(raw)
                run = subprocess.run([sys.executable, str(HERE/"reduce.py"), str(path)], capture_output=True, text=True)
                self.assertEqual(run.returncode, code, run.stderr)
                self.assertEqual(path.read_bytes(), raw)
                if code == 0:
                    self.assertEqual(json.loads(run.stdout)["evidence"], "synthetic")
                else:
                    self.assertEqual(run.stdout, "")
                    self.assertIn("failed", run.stderr)
            run = subprocess.run([sys.executable, str(HERE/"reduce.py"), str(path.parent/"missing")], capture_output=True, text=True)
            self.assertEqual(run.returncode, 1)
            self.assertEqual(run.stdout, "")

    def test_example(self):
        out = r.reduce_bytes((HERE/"example.synthetic.json").read_bytes())
        self.assertEqual(len(out["runs"]), 2)
        self.assertIsNone(out["runs"][1]["outputs"]["cp"])

    def test_isolated_formula_mutations(self):
        source = (HERE/"reduce.py").read_text()
        mutations = (
            ('60.0**2, {"thrust"', '1.0, {"thrust"', "Physics.test_analytic_point"),
            ('2*math.pi/60, {"rpm"', '1/60, {"rpm"', "Physics.test_analytic_point"),
            ('exponent * value /', 'value /', "Physics.test_analytic_sensitivities_against_finite_differences"),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/"test_reduce.py").write_bytes((HERE/"test_reduce.py").read_bytes())
            for old, new, test in mutations:
                self.assertEqual(source.count(old), 1)
                (root/"reduce.py").write_text(source.replace(old, new))
                run = subprocess.run([sys.executable, "-B", str(root/"test_reduce.py"), test], capture_output=True, text=True)
                self.assertEqual(run.returncode, 1, run.stderr)
                self.assertIn("FAIL:", run.stderr)
                self.assertNotIn("ERROR:", run.stderr)
            (root/"reduce.py").write_text(source)
            run = subprocess.run([sys.executable, "-B", str(root/"test_reduce.py"), "Physics"], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
