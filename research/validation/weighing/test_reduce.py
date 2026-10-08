#!/usr/bin/env python3
"""Known statics, differential/Monte Carlo uncertainty and CLI failure contracts."""
import copy
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import random
import statistics
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SCRIPT = Path(os.environ.get("OPENRC_WEIGHING_REDUCER", HERE / "reduce.py"))
spec = importlib.util.spec_from_file_location("weighing", SCRIPT)
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


def fixture():
    return json.loads((HERE / "example.synthetic.json").read_bytes())


def exact(doc):
    """Direct unnormalized moment balance, separate from production weighted sum."""
    n = [s["gross"]["value"] - s["tare"]["value"] for s in doc["supports"]]
    m = sum(n)
    return [m, *[sum(w * s[axis]["value"] for w, s in zip(n, doc["supports"])) / m
                  for axis in ("x", "y")]]


def clear_uncertainty(doc):
    for name in ("common_scale_gain", "datum_x", "datum_y"):
        doc[name]["u"] = 0
    for s in doc["supports"]:
        for name in ("gross", "tare", "x", "y", "scale_gain"):
            s[name]["u"] = 0


class WeighingTests(unittest.TestCase):
    def test_known_asymmetric_statics(self):
        result = r.reduce_weighing(fixture())["results"]
        for key, value in (("mass", 2.6), ("cg_x", .32 / 2.6), ("cg_y", -.06 / 2.6)):
            self.assertAlmostEqual(result[key]["value"], value, places=14)
        self.assertEqual(result["mass"]["unit"], "kg")
        self.assertEqual(result["cg_x"]["unit"], "m")

    def test_symmetric_rig_and_axis_sign(self):
        doc = fixture()
        doc["supports"][0]["gross"]["value"] = 1.2
        self.assertEqual(r.reduce_weighing(doc)["results"]["cg_y"]["value"], 0)
        for s in doc["supports"]:
            s["x"]["value"] *= -1
        self.assertAlmostEqual(r.reduce_weighing(doc)["results"]["cg_x"]["value"], -.28 / 2.4)

    def test_tare_offset_invariance(self):
        doc = fixture()
        expected = r.reduce_weighing(doc)
        for s in doc["supports"]:
            s["gross"]["value"] += 2
            s["tare"]["value"] += 2
        result = r.reduce_weighing(doc)
        for key in expected["results"]:
            for field in ("value", "u"):
                self.assertAlmostEqual(result["results"][key][field], expected["results"][key][field], places=14)

    def test_coordinate_translation(self):
        doc = fixture()
        before = r.reduce_weighing(doc)
        for s in doc["supports"]:
            s["x"]["value"] += 7
            s["y"]["value"] -= 3
        after = r.reduce_weighing(doc)
        self.assertAlmostEqual(after["results"]["cg_x"]["value"], before["results"]["cg_x"]["value"] + 7)
        self.assertAlmostEqual(after["results"]["cg_y"]["value"], before["results"]["cg_y"]["value"] - 3)
        for a, b in zip(after["covariance"]["matrix"], before["covariance"]["matrix"]):
            for av, bv in zip(a, b):
                self.assertAlmostEqual(av, bv, places=14)

    def test_shared_gain_cancels_from_cg(self):
        doc = fixture()
        clear_uncertainty(doc)
        doc["common_scale_gain"]["u"] = .01
        out = r.reduce_weighing(doc)["results"]
        self.assertAlmostEqual(out["mass"]["u"], .026)
        self.assertEqual(out["cg_x"]["u"], 0)
        self.assertEqual(out["cg_y"]["u"], 0)
        old = exact(doc)
        for s in doc["supports"]:
            for key in ("gross", "tare"):
                s[key]["value"] *= 1.03
        new = exact(doc)
        self.assertAlmostEqual(new[0], old[0] * 1.03)
        self.assertAlmostEqual(new[1], old[1])
        self.assertAlmostEqual(new[2], old[2])

    def test_shared_datum_is_not_averaged_down(self):
        doc = fixture()
        clear_uncertainty(doc)
        doc["datum_x"]["u"] = .02
        doc["datum_y"]["u"] = .03
        out = r.reduce_weighing(doc)["results"]
        self.assertEqual(out["mass"]["u"], 0)
        self.assertEqual(out["cg_x"]["u"], .02)
        self.assertEqual(out["cg_y"]["u"], .03)

    def test_large_common_gain_does_not_warn_about_cg(self):
        doc = fixture()
        clear_uncertainty(doc)
        doc["common_scale_gain"]["u"] = .2
        out = r.reduce_weighing(doc)
        self.assertEqual(out["warnings"], [])
        self.assertEqual(out["results"]["cg_x"]["u"], 0)

    def test_all_local_sensitivities_against_central_difference(self):
        doc = fixture()
        contributions = r.reduce_weighing(doc)["standard_error_contributions"]
        eps = 1e-5
        for i, s in enumerate(doc["supports"]):
            for key in ("gross", "tare", "x", "y", "scale_gain"):
                plus, minus = copy.deepcopy(doc), copy.deepcopy(doc)
                if key == "scale_gain":
                    for field in ("gross", "tare"):
                        plus["supports"][i][field]["value"] *= 1 + eps
                        minus["supports"][i][field]["value"] *= 1 - eps
                else:
                    plus["supports"][i][key]["value"] += eps
                    minus["supports"][i][key]["value"] -= eps
                numerical = [(a - b) / (2 * eps) * s[key]["u"] for a, b in zip(exact(plus), exact(minus))]
                for actual, expected in zip(contributions[s["id"] + "." + key], numerical):
                    self.assertAlmostEqual(actual, expected, delta=2e-12)

    def test_covariance_against_seeded_monte_carlo(self):
        doc = fixture()
        expected = r.reduce_weighing(doc)["covariance"]["matrix"]
        rng = random.Random(503)
        samples = [[], [], []]
        for _ in range(20000):
            gain = 1 + rng.gauss(0, doc["common_scale_gain"]["u"])
            weights, xs, ys = [], [], []
            for s in doc["supports"]:
                gross = rng.gauss(s["gross"]["value"], s["gross"]["u"])
                tare = rng.gauss(s["tare"]["value"], s["tare"]["u"])
                weights.append((gross - tare) * gain * (1 + rng.gauss(0, s["scale_gain"]["u"])))
                xs.append(rng.gauss(s["x"]["value"], s["x"]["u"]))
                ys.append(rng.gauss(s["y"]["value"], s["y"]["u"]))
            m = sum(weights)
            values = [m, sum(n * x for n, x in zip(weights, xs)) / m + rng.gauss(0, doc["datum_x"]["u"]),
                      sum(n * y for n, y in zip(weights, ys)) / m + rng.gauss(0, doc["datum_y"]["u"])]
            for column, value in zip(samples, values):
                column.append(value)
        for i in range(3):
            self.assertAlmostEqual(statistics.variance(samples[i]) / expected[i][i], 1, delta=.035)
            for j in range(3):
                self.assertAlmostEqual(statistics.covariance(samples[i], samples[j]), expected[i][j],
                                       delta=.035 * math.sqrt(expected[i][i] * expected[j][j]))

    def test_zero_net_support_and_large_uncertainty_warn(self):
        doc = fixture()
        doc["supports"][2]["gross"]["value"] = doc["supports"][2]["tare"]["value"]
        doc["supports"][0]["gross"]["u"] = .4
        self.assertEqual(len(r.reduce_weighing(doc)["warnings"]), 2)

    def test_invalid_inputs(self):
        mutations = [
            lambda d: d.update(format="v2"), lambda d: d.update(evidence="validated"),
            lambda d: d.update(configuration=""), lambda d: d.update(datum=None),
            lambda d: d.update(extra=1), lambda d: d["setup"].update(level=False),
            lambda d: d["setup"].update(level=1), lambda d: d["setup"].update(all_loads_on_scales=False),
            lambda d: d.update(supports=[]), lambda d: d.update(supports=d["supports"][:2]),
            lambda d: d["supports"][1].update(id="left"),
            lambda d: d["supports"][0]["gross"].update(value=-1),
            lambda d: d["supports"][0]["tare"].update(value=100),
            lambda d: d["supports"][0]["x"].update(unit="cm"),
            lambda d: d["supports"][0]["x"].update(source=""),
            lambda d: d["supports"][0]["x"].update(kind="guessed"),
            lambda d: d["supports"][0]["x"].update(u=-.1),
            lambda d: d["common_scale_gain"].update(value=.1),
            lambda d: d["datum_x"].update(value=.1),
            lambda d: d.update(evidence="measured"),
            lambda d: [s["y"].update(value=0) for s in d["supports"]],
            lambda d: [s["gross"].update(value=s["tare"]["value"]) for s in d["supports"]],
        ]
        for bad in (True, "1.2", None, float("nan"), float("inf"), 10**400):
            mutations.append(lambda d, b=bad: d["supports"][0]["x"].update(value=b))
            mutations.append(lambda d, b=bad: d["supports"][0]["x"].update(u=b))
        for i, mutation in enumerate(mutations):
            with self.subTest(i=i):
                doc = fixture()
                mutation(doc)
                with self.assertRaises(ValueError):
                    r.reduce_weighing(doc)

    def test_measured_evidence_preserves_provenance(self):
        doc = fixture()
        doc["evidence"] = "measured"
        for q in [doc[k] for k in ("common_scale_gain", "datum_x", "datum_y")]:
            q["kind"] = "estimated"
        for s in doc["supports"]:
            for name in ("gross", "tare", "x", "y", "scale_gain"):
                s[name]["kind"] = "measured"
        out = r.reduce_weighing(doc)
        self.assertEqual(out["evidence"], "measured")
        self.assertEqual(out["input"], doc)
        self.assertEqual(out["results"]["cg_x"]["kind"], "derived")

    def test_strict_json(self):
        for raw in ('{"x":1,"x":2}', '{"x":NaN}', '{"x":Infinity}', '{"x":-Infinity}', '{'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                r.load(raw)

    def cli(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)], capture_output=True, timeout=10)

    def test_cli_report_reproducibility_and_hashes(self):
        raw = (HERE / "example.synthetic.json").read_bytes()
        with tempfile.TemporaryDirectory() as tmp:
            src, out = Path(tmp) / "input.json", Path(tmp) / "report.json"
            src.write_bytes(raw)
            result = self.cli(src, "--output", out)
            self.assertEqual(result.returncode, 0, result.stderr)
            first = out.read_bytes()
            second = self.cli(src)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(first, second.stdout)
            doc = json.loads(first)
            self.assertEqual(doc["input_sha256"], hashlib.sha256(raw).hexdigest())
            self.assertEqual(doc["reducer_sha256"], hashlib.sha256(SCRIPT.read_bytes()).hexdigest())
            src.write_bytes(raw + b"\n")
            changed = json.loads(self.cli(src).stdout)
            self.assertNotEqual(changed["input_sha256"], doc["input_sha256"])
            self.assertEqual(changed["results"], doc["results"])

    def test_cli_failures_preserve_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, out = Path(tmp) / "input.json", Path(tmp) / "report.json"
            src.write_bytes((HERE / "example.synthetic.json").read_bytes())
            raw = src.read_bytes()
            alias = Path(tmp) / "alias.json"
            alias.hardlink_to(src)
            for output in (src, alias, Path(tmp) / "missing" / "report.json"):
                result = self.cli(src, "--output", output)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(b"Traceback", result.stderr)
                self.assertEqual(src.read_bytes(), raw)
            out.write_text("preserve")
            for bad in (b"{", b"[]", raw.replace(b'"value": 1.4', b'"value": 1e308').replace(b'"u": 0.001', b'"u": 1e308')):
                src.write_bytes(bad)
                result = self.cli(src, "--output", out)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(out.read_text(), "preserve")
                self.assertNotIn(b"Traceback", result.stderr)
            self.assertNotEqual(self.cli(Path(tmp) / "absent.json").returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
