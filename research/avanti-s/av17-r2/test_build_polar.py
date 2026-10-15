from __future__ import annotations

import copy
import json
import math
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_polar as build_polar_module
from build_polar import DEFAULT_AIRCRAFT, METHOD, SOURCE_TRANSCRIPTION, _finite_wing_line, build_polar


def _load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _rows(quantity: dict) -> list[list[float]]:
    values = quantity["value"]
    return [values[index : index + 4] for index in range(0, len(values), 4)]


class CandidatePolarTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.aircraft = _load_json(DEFAULT_AIRCRAFT)
        cls.polar = build_polar(cls.aircraft)
        cls.transcription = _load_json(SOURCE_TRANSCRIPTION)

    def test_closed_object_and_two_evidence_quantities(self):
        self.assertEqual(set(self.polar), {"method", "basis", "positive", "negative"})
        self.assertEqual(self.polar["method"], METHOD)
        self.assertEqual(self.polar["basis"], "finite-wing-strip-reference")
        for side in ("positive", "negative"):
            quantity = self.polar[side]
            self.assertEqual(set(quantity), {"value", "unit", "kind", "source"})
            self.assertEqual(quantity["unit"], "deg, 1, 1, 1")
            self.assertEqual(quantity["kind"], "estimated")
            self.assertIn(self.transcription["source"]["pdf_sha256"], quantity["source"])
            self.assertIn(self.transcription["source"]["pdf_url"], quantity["source"])
            self.assertIn("does not identify the Avanti S airfoil", quantity["source"])
            self.assertIn("not all measured", quantity["source"])
            self.assertIn("not measured separation", quantity["source"])

    def test_exact_signed_attached_8_degree_anchor_includes_offset(self):
        slope, offset = _finite_wing_line(self.aircraft)
        self.assertGreater(abs(offset), 1e-8)
        # Python mirror cross-checked with AircraftData._induced_map through Godot 4.7.2.
        self.assertAlmostEqual(slope, 4.236283082716884, delta=1e-9)
        self.assertAlmostEqual(offset, -0.00299688529980005, delta=1e-9)
        expected_positive = slope * math.radians(8.0) + offset
        expected_negative = slope * math.radians(8.0) - offset
        positive = _rows(self.polar["positive"])[0]
        negative = _rows(self.polar["negative"])[0]
        self.assertEqual(positive[0], 8.0)
        self.assertEqual(negative[0], 8.0)
        self.assertAlmostEqual(positive[1], expected_positive, delta=1e-12)
        self.assertAlmostEqual(negative[1], expected_negative, delta=1e-12)
        self.assertEqual(positive[2:], [self.aircraft["aero"]["coefficients"]["CD0"]["value"], 1.0])
        self.assertEqual(negative[2:], [self.aircraft["aero"]["coefficients"]["CD0"]["value"], 1.0])

    def test_transcription_rows_and_candidate_policy_are_explicit(self):
        expected_angles = list(range(10, 28)) + [30]
        self.assertEqual([row[0] for row in self.transcription["rows"]], expected_angles)
        self.assertEqual(self.transcription["source"]["pdf_sha256"], "af5cb8e9f564121155014b7c88d3b41ef75cd0655bcdc41690cd4f5b6b38bb97")
        self.assertIn("build_polar.py::build_polar", self.transcription["builder"])
        self.assertTrue(self.transcription["source"]["pdf_url"].startswith("https://www.osti.gov/"))
        self.assertNotIn(".tools", json.dumps(self.transcription))
        policy = self.transcription["candidate_policy"]
        self.assertIn("not a measured Avanti polar", policy["classification"])
        self.assertIn("not measured separation", policy["attached_fraction"]["note"])
        self.assertIn("not all measured", self.transcription["source"]["transcription_note"])

    def test_angles_fractions_and_drag_are_finite_and_passive(self):
        cd0 = self.aircraft["aero"]["coefficients"]["CD0"]["value"]
        cd90 = self.aircraft["aero"]["envelope"]["CD90"]["value"]
        for side in ("positive", "negative"):
            rows = _rows(self.polar[side])
            self.assertEqual(len(rows), 24)
            for index, row in enumerate(rows):
                angle, cl, cd, fraction = row
                self.assertTrue(all(math.isfinite(value) for value in row))
                self.assertGreaterEqual(angle, 8.0)
                self.assertGreaterEqual(cl, 0.0)
                self.assertGreaterEqual(cd, cd0 - 1e-12)
                self.assertLessEqual(cd, 3.0)
                self.assertGreaterEqual(fraction, 0.0)
                self.assertLessEqual(fraction, 1.0)
                if index:
                    self.assertGreater(angle, rows[index - 1][0])
                    self.assertLessEqual(fraction, rows[index - 1][3])
            self.assertEqual(rows[-1], [90.0, 0.0, cd0 + cd90, 0.0])

    def test_high_angle_rows_follow_the_existing_flat_plate_law(self):
        cd0 = self.aircraft["aero"]["coefficients"]["CD0"]["value"]
        cd90 = self.aircraft["aero"]["envelope"]["CD90"]["value"]
        for side in ("positive", "negative"):
            rows = _rows(self.polar[side])[-4:]
            for row, angle in zip(rows, (45.0, 60.0, 75.0, 90.0)):
                radians = math.radians(angle)
                expected_cl = 0.5 * cd90 * math.sin(2.0 * radians) if angle < 90.0 else 0.0
                expected_cd = cd0 + cd90 * math.sin(radians) ** 2
                self.assertEqual(row[0], angle)
                self.assertAlmostEqual(row[1], expected_cl, delta=1e-15)
                self.assertAlmostEqual(row[2], expected_cd, delta=1e-15)
                self.assertEqual(row[3], 0.0)

    def test_high_angle_rows_are_independent_of_one_ulp_sine_drift(self):
        cd0 = self.aircraft["aero"]["coefficients"]["CD0"]["value"]
        cd90 = self.aircraft["aero"]["envelope"]["CD90"]["value"]
        original_sin = math.sin

        def legacy_rows(sine):
            rows = []
            for angle in (45.0, 60.0, 75.0, 90.0):
                radians = math.radians(angle)
                lift = 0.5 * cd90 * sine(2.0 * radians) if angle < 90.0 else 0.0
                drag = cd0 + cd90 * sine(radians) ** 2
                rows.append([angle, lift, drag])
            return rows

        legacy_before = legacy_rows(original_sin)

        def next_sine(value):
            return math.nextafter(original_sin(value), math.inf)

        with patch("build_polar.math.sin", side_effect=next_sine):
            perturbed = build_polar(self.aircraft)
            legacy_after = legacy_rows(build_polar_module.math.sin)

        self.assertEqual(perturbed, self.polar)
        self.assertTrue(all(before != after for before, after in zip(legacy_before, legacy_after)))

    def test_builder_is_deterministic_and_does_not_mutate_input(self):
        untouched = copy.deepcopy(self.aircraft)
        first = build_polar(self.aircraft)
        second = build_polar(self.aircraft)
        self.assertEqual(first, second)
        self.assertEqual(self.aircraft, untouched)

    def test_rejects_non_v2_and_invalid_taper(self):
        with self.assertRaises(ValueError):
            build_polar({"format": "openrc-aircraft v1"})
        bad = copy.deepcopy(self.aircraft)
        bad["reference"]["tip_chord"]["value"] = 1.0
        with self.assertRaisesRegex(ValueError, "tip <= root"):
            build_polar(bad)


if __name__ == "__main__":
    unittest.main()
