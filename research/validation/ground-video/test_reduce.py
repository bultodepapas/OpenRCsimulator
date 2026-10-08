#!/usr/bin/env python3
"""Known-answer, covariance, malformed-input and process checks for VAL-8a."""
import copy
import csv
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
SPEC = importlib.util.spec_from_file_location("ground_video_reduce", HERE / "reduce.py")
REDUCER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REDUCER)


def fixture():
    return json.loads((HERE / "example.synthetic.json").read_bytes()), (HERE / "example.synthetic.csv").read_bytes()


def covariance(a, b):
    aa, bb = a["standard_uncertainty_contributions"], b["standard_uncertainty_contributions"]
    return math.fsum(value * bb.get(key, 0) for key, value in aa.items())


class ReductionTests(unittest.TestCase):
    def setUp(self):
        self.campaign, self.csv = fixture()

    def whole(self, campaign=None, csv=None):
        return REDUCER.reduce(campaign or self.campaign, csv or self.csv)["intervals"][-1]

    def test_known_answer_and_not_inclusive_frame_count(self):
        result = self.whole()
        self.assertEqual(result["delta_frames"], 1200)
        self.assertEqual(result["duration"]["value"], 5)
        self.assertEqual(result["distance"]["value"], 30)
        self.assertEqual(result["average_ground_speed"]["value"], 6)
        self.assertEqual(result["warnings"], [])

    def test_rational_capture_rate(self):
        self.campaign["video"].update(capture_fps_num=30000, capture_fps_den=1001)
        self.assertEqual(self.whole()["duration"]["value"], 1200*1001/30000)
        self.campaign["video"].update(capture_fps_num=240, capture_fps_den=1)
        self.csv = self.csv.replace(b"1320", b"820").replace(b"720", b"170")
        self.assertAlmostEqual(self.whole()["duration"]["value"], 700/240)

    def test_closed_form_independent_uncertainty(self):
        result = self.whole()
        t_var = 2*(0.5/240)**2 + (5*0.001)**2
        d_var = 2*0.03**2 + (30*0.002)**2
        v_var = d_var/25 + 36*t_var/25
        for key, variance in (("duration", t_var), ("distance", d_var), ("average_ground_speed", v_var)):
            self.assertAlmostEqual(result[key]["u"]**2, variance, places=14)

    def test_translation_and_frame_origin_cancel(self):
        transformed = self.csv.replace(b"120,", b"220,").replace(b"720,", b"820,").replace(b"1320,", b"1420,")
        transformed = transformed.replace(b",-5,", b",995,").replace(b",10,", b",1010,").replace(b",25,", b",1025,")
        before, after = self.whole(), self.whole(csv=transformed)
        for key in ("duration", "distance", "average_ground_speed"):
            self.assertEqual(before[key], after[key])

    def test_reverse_direction_and_correlation_transform(self):
        self.csv = self.csv.replace(b",0\n", b",0.6\n")
        reverse = self.csv.replace(b",-5,", b",5,").replace(b",10,", b",-10,").replace(b",25,", b",-25,").replace(b",0.6\n", b",-0.6\n")
        before, after = self.whole(), self.whole(csv=reverse)
        self.assertEqual(after["signed_displacement_m"], -before["signed_displacement_m"])
        for key in ("duration", "distance", "average_ground_speed"):
            self.assertEqual(before[key]["value"], after[key]["value"])
            self.assertEqual(before[key]["u"], after[key]["u"])

    def test_correlated_position_frame_picks(self):
        baseline = self.whole()["average_ground_speed"]["u"]**2
        self.csv = self.csv.replace(b",0\n", b",0.75\n")
        result = self.whole()
        # Direct two-endpoint covariance expansion, independently of whitening.
        correction = 2*2*(6/1200)*(-1/5)*0.75*0.5*0.03
        self.assertAlmostEqual(result["average_ground_speed"]["u"]**2, baseline+correction, places=14)
        self.assertAlmostEqual(covariance(result["duration"], result["distance"]), 2/240*0.75*0.5*0.03)

    def test_shared_event_and_calibration_covariance(self):
        a, b, whole = REDUCER.reduce(self.campaign, self.csv)["intervals"]
        # Middle pick cancels in a+b; shared calibration contributes once on full span.
        self.assertAlmostEqual(covariance(a["duration"], b["duration"]), -(0.5/240)**2+(2.5*0.001)**2)
        self.assertAlmostEqual(covariance(a["distance"], b["distance"]), -0.03**2+(15*0.002)**2)
        for metric in ("duration", "distance"):
            summed = a[metric]["u"]**2+b[metric]["u"]**2+2*covariance(a[metric], b[metric])
            self.assertAlmostEqual(summed, whole[metric]["u"]**2, places=14)

    def test_calibration_does_not_average_away(self):
        events = self.csv.replace(b",0.5,", b",0,").replace(b",0.03,", b",0,")
        result = self.whole(csv=events)
        self.assertEqual(result["duration"]["u"], 0.005)
        self.assertEqual(result["distance"]["u"], 0.06)
        self.assertAlmostEqual(result["average_ground_speed"]["u"], 6*math.hypot(0.001, 0.002))

    def test_seeded_monte_carlo_uncertainty(self):
        self.csv = self.csv.replace(b",0\n", b",0.6\n")
        expected = self.whole()
        randomizer = random.Random(814)
        samples = {"duration": [], "distance": [], "average_ground_speed": []}
        for _ in range(25000):
            z0, z1, w0, w1, clock, scale = (randomizer.gauss(0, 1) for _ in range(6))
            n = 1200+0.5*(z1-z0)
            delta = (30+0.03*(0.6*(z1-z0)+0.8*(w1-w0)))*(1+0.002*scale)
            t = n/(240*(1+0.001*clock))
            for key, value in (("duration", t), ("distance", delta), ("average_ground_speed", delta/t)):
                samples[key].append(value)
        for key in samples:
            self.assertAlmostEqual(statistics.stdev(samples[key])/expected[key]["u"], 1, delta=0.025)

    def test_large_uncertainty_is_flagged_not_confidence_claim(self):
        self.campaign["video"]["fps_relative_u"] = 0.2
        self.campaign["survey"]["scale_relative_u"] = 0.2
        self.assertEqual(len(self.whole()["warnings"]), 2)

    def test_combined_timing_uncertainty_warning(self):
        self.campaign["video"]["fps_relative_u"] = 0.08
        events = self.csv.replace(b",0.5,", b",68,")
        self.assertEqual(len(self.whole(csv=events)["warnings"]), 1)

    def test_derived_overflow_and_underflow_refused(self):
        for changes in ((b",-5,", b",-1e308,", b",25,", b",1e308,"),
                        (b",-5,", b",0,", b",25,", b",5e-324,")):
            raw = self.csv.replace(changes[0], changes[1]).replace(changes[2], changes[3])
            with self.assertRaises(ValueError):
                self.whole(csv=raw)

    def test_zero_uncertainties_and_perfect_correlation(self):
        for rho in (-1, 1):
            result = self.whole(csv=self.csv.replace(b",0\n", f",{rho}\n".encode()))
            self.assertTrue(math.isfinite(result["average_ground_speed"]["u"]))
        self.campaign["video"]["fps_relative_u"] = 0
        self.campaign["survey"]["scale_relative_u"] = 0
        result = self.whole(csv=self.csv.replace(b",0.5,", b",0,").replace(b",0.03,", b",0,"))
        self.assertTrue(all(result[key]["u"] == 0 for key in ("duration", "distance", "average_ground_speed")))

    def test_bad_campaigns(self):
        for path, value in [
            (("format",), "v2"), (("evidence",), "estimated"), (("aircraft",), ""),
            (("video", "capture_fps_num"), True), (("video", "capture_fps_den"), 0),
            (("video", "capture_fps_num"), 240.0), (("video", "capture_fps_num"), 2**54),
            (("video", "fps_relative_u"), float("nan")), (("video", "fps_relative_u"), -1),
            (("video", "constant_capture_cadence_verified"), False),
            (("video", "constant_capture_cadence_verified"), 1),
            (("survey", "scale_relative_u"), "0.01"), (("survey", "scale_relative_u"), True),
            (("survey", "ground_positions_verified"), False),
            (("survey", "independent_event_residuals"), False), (("survey", "axis_datum"), ""),
            (("intervals",), []), (("intervals",), [{"id": "x"}]),
            (("video", "sha256"), "x"), (("evidence",), "measured"),
        ]:
            with self.subTest(path=path, value=value):
                c = copy.deepcopy(self.campaign)
                node = c
                for key in path[:-1]:
                    node = node[key]
                node[path[-1]] = value
                with self.assertRaises(ValueError):
                    REDUCER.reduce(c, self.csv)

    def test_invalid_intervals(self):
        for patch in ({"start": "missing"}, {"end": "start"}, {"start": "end", "end": "start"}, {"definition": ""}, {"id": "first_segment"}):
            c = copy.deepcopy(self.campaign)
            c["intervals"][-1].update(patch)
            with self.subTest(patch=patch), self.assertRaises(ValueError):
                REDUCER.reduce(c, self.csv)

    def test_invalid_csv(self):
        variants = [self.csv.replace(b"frame_u", b"u"), self.csv.replace(b"frame_u", b"frame"),
                    self.csv.replace(b"1320", b"1500"), self.csv.replace(b"720", b"120"),
                    self.csv.replace(b"start,120", b"start,120.0"), self.csv.replace(b"end,", b"start,"),
                    self.csv.replace(b",0.5,", b",nan,"), self.csv.replace(b",0.03,", b",-1,"),
                    self.csv.replace(b",0\n", b",2\n"), self.csv.replace(b",0\n", b",0,extra\n"),
                    self.csv.replace(b",0\n", b"\n"), self.csv.replace(b",25,", b",-5,"),
                    self.csv.replace(b",25,", b",1e309,"), self.csv.replace(b"120,", b"-1,"),
                    self.csv.splitlines(keepends=True)[0]]
        for raw in variants:
            with self.subTest(raw=raw), self.assertRaises((ValueError, csv.Error)):
                REDUCER.reduce(self.campaign, raw)

    def test_strict_json(self):
        for data in (b'{"a":1,"a":2}', b'{"a":NaN}', b'{"a":Infinity}'):
            with self.assertRaises(ValueError):
                REDUCER.load_json(data)


class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="openrc-val8a-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        campaign, events = fixture()
        self.campaign = self.root / "campaign.json"
        self.events = self.root / "events.csv"
        self.output = self.root / "output.json"
        self.campaign.write_text(json.dumps(campaign))
        self.events.write_bytes(events)

    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(HERE/"reduce.py"), str(self.campaign), str(self.events), *map(str, args)],
                              capture_output=True, timeout=10)

    def test_determinism_exact_input_hashes_and_stdout(self):
        first, second = self.run_cli(), self.run_cli()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, second.stdout)
        report = json.loads(first.stdout)
        for key, path in (("campaign", self.campaign), ("events_csv", self.events), ("reducer", HERE/"reduce.py")):
            self.assertEqual(report["input_sha256"][key], hashlib.sha256(path.read_bytes()).hexdigest())
        self.campaign.write_bytes(self.campaign.read_bytes()+b"\n")
        changed = json.loads(self.run_cli().stdout)
        self.assertNotEqual(report["input_sha256"]["campaign"], changed["input_sha256"]["campaign"])
        self.assertEqual(report["intervals"], changed["intervals"])
        self.assertEqual(self.run_cli("--output", self.output).returncode, 0)
        self.assertEqual(json.loads(self.output.read_bytes()), changed)

    def test_failure_preserves_report(self):
        self.output.write_bytes(b"previous report")
        self.events.write_bytes(b"invalid")
        result = self.run_cli("--output", self.output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"VAL-8a:", result.stderr)
        self.assertEqual(self.output.read_bytes(), b"previous report")
        self.assertEqual(result.stdout, b"")

    def test_input_aliases_including_hardlinks(self):
        for source in (self.campaign, self.events, HERE/"reduce.py"):
            before = source.read_bytes()
            for kind in ("direct", "symlink", "hardlink"):
                alias = self.root / "alias"
                alias.unlink(missing_ok=True)
                if kind == "symlink":
                    alias.symlink_to(source)
                elif kind == "hardlink":
                    os.link(source, alias)
                else:
                    alias = source
                with self.subTest(source=source, kind=kind):
                    result = self.run_cli("--output", alias)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(b"aliases", result.stderr)
                    self.assertEqual(source.read_bytes(), before)

    def test_measured_clip_identity_required_and_checked(self):
        # Byte fixture verifies provenance plumbing; it is deliberately not real video.
        video = self.root/"clip-fixture.bin"
        video.write_bytes(b"synthetic video identity fixture")
        c = json.loads(self.campaign.read_bytes())
        c["evidence"] = "measured"
        c["video"]["sha256"] = hashlib.sha256(video.read_bytes()).hexdigest()
        self.campaign.write_text(json.dumps(c))
        self.assertNotEqual(self.run_cli().returncode, 0)
        good = self.run_cli("--video", video)
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertEqual(json.loads(good.stdout)["input_sha256"]["video"], c["video"]["sha256"])
        self.assertNotEqual(self.run_cli("--video", video, "--output", video).returncode, 0)
        video.write_bytes(b"changed")
        result = self.run_cli("--video", video)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"SHA-256 mismatch", result.stderr)

    def test_unexpected_video_and_write_failure(self):
        self.assertNotEqual(self.run_cli("--video", self.events).returncode, 0)
        self.assertNotEqual(self.run_cli("--output", self.root/"missing"/"report.json").returncode, 0)
        self.assertNotEqual(self.run_cli("--output", self.root).returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
