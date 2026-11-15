#!/usr/bin/env python3
"""Focused arithmetic/domain checks, not simulator or aircraft validation."""

import copy
import json
import math
from pathlib import Path
import unittest

import reference_study as study


class ReferenceStudyTests(unittest.TestCase):
    def setUp(self):
        self.doc = study.load(study.INPUT.read_bytes())

    def test_independent_simple_reference(self):
        # n=1, D=2, rho=1, Ct=1/8, Cp=1/4 gives T=2 and P=8.
        values = {"span": 2, "wing_area": 2, "density": 1, "kinematic_viscosity": 0.5,
                  "gravity": 8, "prop_diameter": 2, "prop_rpm": 60, "prop_ct": 0.125,
                  "prop_cp": 0.25, "prop_inertia": 0.5, "roll_rate": 180,
                  "perpendicular_body_rate": 90}
        for key, value in values.items():
            self.doc["quantities"][key].update(value=value, kind="estimated", source="Chosen algebra fixture; not source observations")
        self.doc["scenarios"]["airspeed"]["values"] = [0, 4]
        self.doc["scenarios"]["mass"]["values"] = [1]
        out = study.calculate(self.doc)
        prop = out["static_prop_reference"]["values"]
        self.assertEqual(prop["thrust_n"], 2)
        self.assertEqual(prop["shaft_power_w"], 8)
        self.assertAlmostEqual(prop["shaft_torque_nm"], 4 / math.pi)
        self.assertAlmostEqual(prop["ideal_disc_speed_m_s"], 1 / math.sqrt(math.pi))
        self.assertAlmostEqual(prop["prop_angular_momentum_nms"], math.pi)
        self.assertAlmostEqual(prop["gyro_coupling_magnitude_nm"], math.pi ** 2 / 2)
        self.assertEqual(out["mass_sensitivity"]["values"][0]["constant_ct_balance_rpm"], 120)
        flow = out["reference_flow"]["values"][1]
        self.assertEqual(flow["reynolds_reference_chord"], 8)
        self.assertEqual(flow["dynamic_pressure_pa"], 8)
        self.assertEqual(flow["axial_advance_ratio"], 2)

    def test_reference_point_round_trip_with_existing_measurement_reducer(self):
        # Independent owner's Ct/Cp reduction of synthetic dimensional loads.
        import importlib.util
        path = Path(__file__).resolve().parents[1] / "validation/static-prop/reduce.py"
        spec = importlib.util.spec_from_file_location("static_prop", path)
        reducer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(reducer)
        fixture = json.loads(path.with_name("example.synthetic.json").read_bytes())
        prop = study.calculate(self.doc)["static_prop_reference"]["values"]
        run = fixture["runs"][0]
        for key, value in {"thrust": prop["thrust_n"], "torque": prop["shaft_torque_nm"],
                           "rpm": 5000, "diameter": 0.7112, "density": 1.225}.items():
            run[key].update(value=value, u=0)
        fixture["runs"] = [run]
        result = reducer.reduce_document(fixture)
        derived = result["runs"][0]["outputs"]
        self.assertAlmostEqual(derived["ct"]["value"], 0.0816)
        self.assertAlmostEqual(derived["cp"]["value"], 0.0264)
        self.assertAlmostEqual(derived["ideal_static_disc_power"]["value"], prop["ideal_disc_power_w"])

    def test_rpm_scaling(self):
        first = study.calculate(self.doc)["static_prop_reference"]["values"]
        self.doc["quantities"]["prop_rpm"].update(value=10000, kind="estimated", source="Deliberate algebra-only RPM scaling; not a supported propeller operating point")
        second = study.calculate(self.doc)["static_prop_reference"]["values"]
        for key, ratio in {"thrust_n": 4, "shaft_power_w": 8, "shaft_torque_nm": 4,
                           "ideal_disc_speed_m_s": 2, "prop_spin_energy_j": 4,
                           "prop_angular_momentum_nms": 2}.items():
            self.assertAlmostEqual(second[key] / first[key], ratio)

    def test_zero_speed_and_zero_delay_are_not_regularized(self):
        out = study.calculate(self.doc)
        still = out["reference_flow"]["values"][0]
        self.assertIsNone(still["roll_reduced_rate"])
        self.assertIsNone(still["pitch_reduced_rate"])
        self.assertIsNone(still["reference_chord_advection_s"])
        self.assertEqual(still["dynamic_pressure_pa"], 0)
        self.assertEqual(still["axial_advance_ratio"], 0)
        self.assertEqual(out["pure_delay"]["values"][0]["phase_deg"], 0)
        self.assertFalse(out["physical_acceptance"])

    def test_delay_known_answer(self):
        self.doc["scenarios"]["frequency"]["values"] = [2]
        self.doc["scenarios"]["delay"]["values"] = [50]
        self.assertEqual(study.calculate(self.doc)["pure_delay"]["values"][0]["phase_deg"], -36)

    def test_invalid_inputs_rejected(self):
        for value in [True, "5000", 0, -1, float("nan"), float("inf")]:
            candidate = copy.deepcopy(self.doc)
            candidate["quantities"]["prop_rpm"]["value"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                study.calculate(candidate)
        self.doc["quantities"]["prop_diameter"]["unit"] = "in"
        with self.assertRaises(ValueError):
            study.calculate(self.doc)

    def test_duplicate_json_and_unknown_fields_rejected(self):
        with self.assertRaises(ValueError):
            study.load(b'{"format": 1, "format": 2}')
        self.doc["aircraft_id"] = "aeris_120"
        with self.assertRaises(ValueError):
            study.calculate(self.doc)

    def test_malformed_kind_and_source_claim_boundary(self):
        self.doc["quantities"]["prop_rpm"]["kind"] = []
        with self.assertRaises(ValueError):
            study.calculate(self.doc)
        self.doc["quantities"]["prop_rpm"].update(kind="estimated", value=10000,
            source="Algebra-only scenario; coefficients unchanged, not an operating recommendation")
        result = study.calculate(self.doc)
        self.assertEqual(result["static_prop_reference"]["evidence"], "illustrative_algebra")
        self.assertIn("not authenticated", result["static_prop_reference"]["limitation"])
        self.assertNotIn("S06 manufacturer-simulated static point", result["static_prop_reference"]["limitation"])


if __name__ == "__main__":
    unittest.main()
