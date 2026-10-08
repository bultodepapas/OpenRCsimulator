#!/usr/bin/env python3
"""Analytic and process checks for VAL-6a; all data below are synthetic."""
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


def fixture(method="bifilar", tare=False):
    q = {}
    def put(key, value, unit, u=0.0):
        q[key] = dict(value=value, unit=unit, u=u, kind="synthetic", source="Analytic test fixture, not a measurement")
        return key
    g = put("gravity", 9.80665, "m/s^2")
    # Uniform 1.2 x 0.2 m plank, 2 kg. Rig mass 0.5 kg, I_cg=0.01 kg*m^2.
    obj_mass, obj_i, obj_h = 2.0, 2.0*(1.2**2+0.2**2)/12, 0.4
    rig_mass, rig_i, rig_h = (0.5, 0.01, 0.15) if tare else (0.0, 0.0, 0.0)
    ml = obj_mass + rig_mass
    spacing = put("spacing", 0.6, "m", 0.001)
    length = put("length", 2.0, "m", 0.002)
    def run(prefix, mass, inertia, h):
        out = {"mass": put(prefix+"_mass", mass, "kg", 0.001), "cycles": 20}
        if method == "bifilar":
            period = math.sqrt(16*math.pi**2*2.0*inertia/(mass*9.80665*0.6**2))
            out.update(spacing=spacing, length=length)
        else:
            period = math.sqrt(4*math.pi**2*inertia/(mass*9.80665*h))
            out["height"] = put(prefix+"_height", h, "m", 0.001)
        out["elapsed"] = put(prefix+"_elapsed", 20*period, "s", 0.02)
        return out
    if method == "bifilar":
        loaded = run("loaded", ml, obj_i+rig_i, 0)
        empty = run("tare", rig_mass, rig_i, 0) if tare else None
    else:
        loaded = run("loaded", ml, obj_i+obj_mass*obj_h**2+rig_i+rig_mass*rig_h**2, (obj_mass*obj_h+rig_mass*rig_h)/ml)
        empty = run("tare", rig_mass, rig_i+rig_mass*rig_h**2, rig_h) if tare else None
    return dict(format=r.FORMAT, evidence="synthetic", configuration="Synthetic uniform plank; no aircraft measurements",
                gravity=g, quantities=q, experiments=[dict(id=method, axis="Iyy" if method=="compound" else "Izz", method=method,
                loaded=loaded, tare=empty, notes="Ideal small-amplitude fixture; tare stays on the same axis",
                plank=dict(dimension_a=put("plank_a", 1.2, "m", 0.001), dimension_b=put("plank_b", 0.2, "m", 0.001), source="Uniform rectangular prism about central normal axis"))])


def result(doc):
    return r.Reduction(doc).report()["experiments"][0]


class Physics(unittest.TestCase):
    def test_uniform_plank_both_methods_with_and_without_tare(self):
        for method in ("bifilar", "compound"):
            for tare in (False, True):
                with self.subTest(method=method, tare=tare):
                    out = result(fixture(method, tare))
                    self.assertAlmostEqual(out["effective_cg_inertia"]["value"], 2*(1.2**2+0.2**2)/12, places=14)
                    self.assertAlmostEqual(out["object_mass"]["value"], 2.0)
                    self.assertTrue(out["plank"]["within_3_percent_nominal"])
                    if method == "compound":
                        self.assertAlmostEqual(out["object_cg_below_pivot"]["value"], 0.4)

    def test_uncertainty_gradients_against_finite_differences(self):
        # Covers shared g, D and L; loaded/tare masses and heights; parallel-axis subtraction;
        # correlated mass in the plank reference and different dimensions.
        for method in ("bifilar", "compound"):
            for tare in (False, True):
                doc = fixture(method, tare)
                for q in doc["quantities"].values():
                    q["u"] = 0.001
                out = result(doc)
                for path in (("effective_cg_inertia",), ("plank", "relative_difference")):
                    def pick(o):
                        for key in path:
                            o = o[key]
                        return o
                    estimate = pick(out)
                    numeric_variance = 0.0
                    for key, quantity in doc["quantities"].items():
                        step = quantity["value"] * 1e-5
                        plus, minus = copy.deepcopy(doc), copy.deepcopy(doc)
                        plus["quantities"][key]["value"] += step
                        minus["quantities"][key]["value"] -= step
                        derivative = (pick(result(plus))["value"]-pick(result(minus))["value"])/(2*step)
                        expected = derivative*quantity["u"]
                        actual = estimate["standard_uncertainty_contributions"].get(key, 0.0)
                        with self.subTest(method=method, tare=tare, path=path, quantity=key):
                            self.assertAlmostEqual(actual, expected, delta=2e-9)
                        numeric_variance += expected**2
                    self.assertAlmostEqual(estimate["u"], math.sqrt(numeric_variance), delta=2e-9)

    def test_full_spacing_squared_and_timing_squared(self):
        base = fixture()
        inertia = result(base)["effective_cg_inertia"]["value"]
        for key in ("spacing", "loaded_elapsed"):
            doc = copy.deepcopy(base)
            doc["quantities"][key]["value"] *= 2
            self.assertAlmostEqual(result(doc)["effective_cg_inertia"]["value"], inertia*4)

    def test_shared_geometry_uncertainty_is_not_independent_tare_error(self):
        doc = fixture(tare=True)
        for key, q in doc["quantities"].items():
            q["u"] = 0.001 if key == "spacing" else 0
        out = result(doc)["effective_cg_inertia"]
        self.assertAlmostEqual(out["u"], 2*out["value"]*0.001/0.6)

    def test_compound_height_sensitivity_vanishes_at_radius_of_gyration(self):
        doc = fixture("compound")
        q = doc["quantities"]
        h = math.sqrt((1.2**2+0.2**2)/12)
        q["loaded_height"]["value"] = h
        q["loaded_elapsed"]["value"] = 20*math.sqrt(8*math.pi**2*h/9.80665)
        contribution = result(doc)["effective_cg_inertia"]["standard_uncertainty_contributions"]["loaded_height"]
        self.assertAlmostEqual(contribution, 0.0, places=15)
        self.assertTrue(result(doc)["stationary_height_warning"])

    def test_net_pivot_result_is_preserved_before_cg_shift(self):
        out = result(fixture("compound", True))
        self.assertAlmostEqual(out["net_swing_axis_inertia"]["value"], 2*(1.2**2+0.2**2)/12 + 2*0.4**2)
        self.assertIn("unresolved", out["cg_estimate_definition"])

    def test_bifilar_tare_geometry_change_is_refused(self):
        for dimension in ("spacing", "length"):
            doc = fixture(tare=True)
            doc["quantities"]["different"] = copy.deepcopy(doc["quantities"][dimension])
            doc["quantities"]["different"]["value"] *= 1.1
            doc["experiments"][0]["tare"][dimension] = "different"
            with self.assertRaisesRegex(ValueError, "same spacing"):
                result(doc)

    def test_bad_plank_agreement_is_a_report_not_software_failure(self):
        doc = fixture()
        doc["quantities"]["loaded_elapsed"]["value"] *= 1.1
        out = result(doc)["plank"]
        self.assertFalse(out["within_3_percent_nominal"])
        self.assertAlmostEqual(out["relative_difference"]["value"], 0.21)

    def test_two_compound_offsets_recover_same_inertia(self):
        for height in (0.2, 0.4, 0.8):
            doc = fixture("compound")
            inertia = 2*(1.2**2+0.2**2)/12
            doc["quantities"]["loaded_height"]["value"] = height
            doc["quantities"]["loaded_elapsed"]["value"] = 20*math.sqrt(4*math.pi**2*(inertia+2*height**2)/(2*9.80665*height))
            self.assertAlmostEqual(result(doc)["effective_cg_inertia"]["value"], inertia, places=14)

    def test_elapsed_and_cycle_count_describe_full_period(self):
        doc = fixture()
        baseline = result(doc)["effective_cg_inertia"]
        doc["experiments"][0]["loaded"]["cycles"] *= 2
        doc["quantities"]["loaded_elapsed"]["value"] *= 2
        doc["quantities"]["loaded_elapsed"]["u"] *= 2
        self.assertEqual(result(doc)["effective_cg_inertia"], baseline)

    def test_large_uncertainty_is_explicit(self):
        doc = fixture()
        doc["quantities"]["loaded_elapsed"]["u"] = 100
        self.assertTrue(result(doc)["uncertainty_reaches_zero"])


class Contract(unittest.TestCase):
    def test_bad_quantities(self):
        for field, values in (("value", (0, -1, True, "2", None, math.nan, math.inf)), ("u", (-1, True, "2", None, math.nan, math.inf))):
            for value in values:
                with self.subTest(field=field, value=value):
                    doc = fixture()
                    doc["quantities"]["loaded_mass"][field] = value
                    with self.assertRaises(ValueError):
                        result(doc)

    def test_bad_contract(self):
        changes = [
            lambda d: d.update(extra=1), lambda d: d.pop("configuration"),
            lambda d: d.update(evidence="validated"), lambda d: d.update(evidence="measured"),
            lambda d: d.update(format="future"), lambda d: d.update(experiments=[]),
            lambda d: d["experiments"].append(copy.deepcopy(d["experiments"][0])),
            lambda d: d["experiments"][0].update(axis="Ixz"),
            lambda d: d["experiments"][0].update(method="trifilar"),
            lambda d: d["experiments"][0]["loaded"].update(cycles=True),
            lambda d: d["experiments"][0]["loaded"].update(cycles=20.5),
            lambda d: d["experiments"][0]["loaded"].update(cycles=0),
            lambda d: d["experiments"][0]["loaded"].update(mass="missing"),
            lambda d: d["experiments"][0]["loaded"].update(mass=[]),
            lambda d: d["quantities"]["loaded_mass"].update(unit="g"),
            lambda d: d["quantities"]["loaded_mass"].update(unit="m"),
            lambda d: d["quantities"]["loaded_mass"].update(source=" "),
            lambda d: d["quantities"]["loaded_mass"].update(kind="verified"),
        ]
        for index, change in enumerate(changes):
            with self.subTest(index=index):
                doc = fixture()
                change(doc)
                with self.assertRaises(ValueError):
                    result(doc)

    def test_impossible_tare_and_compound_geometry(self):
        for method, key, value in (("bifilar", "tare_mass", 3), ("bifilar", "tare_elapsed", 1000),
                                   ("compound", "loaded_elapsed", 0.001), ("compound", "tare_height", 3)):
            doc = fixture(method, True)
            doc["quantities"][key]["value"] = value
            with self.subTest(method=method, key=key), self.assertRaises(ValueError):
                result(doc)

    def test_strict_json(self):
        for raw in (b'{"x":1,"x":2}', b'{"x":NaN}', b'{"x":Infinity}', b'{"x":-Infinity}', b'[]', b'null', b'{'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                r.reduce_bytes(raw)

    def test_numerical_overflow_is_rejected(self):
        doc = fixture()
        doc["quantities"]["spacing"]["value"] = 1e308
        with self.assertRaises(ValueError):
            r.reduce_bytes(json.dumps(doc).encode())

    def test_exact_input_hash_and_reproducibility(self):
        raw = json.dumps(fixture()).encode()
        output = r.reduce_bytes(raw)
        self.assertEqual(output, r.reduce_bytes(raw))
        self.assertEqual(output["input_sha256"], hashlib.sha256(raw).hexdigest())
        self.assertNotEqual(output["input_sha256"], r.reduce_bytes(raw+b' ')["input_sha256"])
        self.assertIn("air", " ".join(output["limitations"]))

    def test_cli_success_failure_and_input_preservation(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/"input.json"
            for raw, expected in ((json.dumps(fixture()).encode(), 0), (b'{"x":NaN}', 1), (b'[]', 1)):
                path.write_bytes(raw)
                run = subprocess.run([sys.executable, str(HERE/"reduce.py"), str(path)], capture_output=True, text=True)
                self.assertEqual(run.returncode, expected, run.stderr)
                self.assertEqual(path.read_bytes(), raw)
                if expected:
                    self.assertEqual(run.stdout, "")
                    self.assertIn("failed", run.stderr)
                else:
                    self.assertEqual(json.loads(run.stdout)["evidence"], "synthetic")

    def test_isolated_mutations_are_detected(self):
        source = (HERE/"reduce.py").read_text()
        mutations = (
            ("16 * math.pi**2", "4 * math.pi**2", "Physics.test_uniform_plank_both_methods_with_and_without_tare"),
            ("inertia -= first_moment**2 / mass", "inertia -= 0.0", "Physics.test_uniform_plank_both_methods_with_and_without_tare"),
            ("2*inertia/elapsed", "inertia/elapsed", "Physics.test_uncertainty_gradients_against_finite_differences"),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/"test_reduce.py").write_bytes((HERE/"test_reduce.py").read_bytes())
            for old, new, test in mutations:
                with self.subTest(mutation=old):
                    self.assertEqual(source.count(old), 1 if "16 *" in old or "first_moment" in old else 2)
                    (root/"reduce.py").write_text(source.replace(old, new))
                    run = subprocess.run([sys.executable, "-B", str(root/"test_reduce.py"), test], capture_output=True, text=True)
                    self.assertEqual(run.returncode, 1, run.stderr)
                    self.assertIn("FAIL:", run.stderr)
                    self.assertNotIn("ERROR:", run.stderr)
            (root/"reduce.py").write_text(source)
            run = subprocess.run([sys.executable, "-B", str(root/"test_reduce.py"), "Physics"], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)

    def test_committed_example(self):
        report = r.reduce_bytes((HERE/"synthetic.json").read_bytes())
        self.assertEqual(len(report["experiments"]), 2)
        self.assertTrue(all(exp["plank"]["within_3_percent_nominal"] for exp in report["experiments"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
