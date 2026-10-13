from __future__ import annotations

import json
import math
import unittest
from pathlib import Path

from reference import (
    OUTPUT_FIELDS,
    ORACLE_SCHEMA,
    RANDOM_SEED,
    _four_parameters,
    _two_parameters,
    build_cases,
    four_stroke,
    two_stroke,
)


ORACLE_PATH = Path(__file__).with_name("oracle.json")


class GlowKernelReferenceTests(unittest.TestCase):
    def assertClose(self, actual: float, expected: float, *, rel: float = 2e-12) -> None:
        self.assertTrue(math.isfinite(actual))
        self.assertLessEqual(abs(actual - expected), max(1e-22, abs(expected) * rel))

    def test_two_stroke_analytic_mass_energy_and_cycle_work(self) -> None:
        result = two_stroke(6000.0, 0.5, 0.8, 1.0, _two_parameters())
        self.assertTrue(result["ok"], result["message"])
        self.assertClose(result["air_charge_kg_cycle"], 5.0e-6)
        self.assertClose(result["delivered_fuel_kg_s"], 8.888888888888889e-5)
        self.assertClose(result["burned_fuel_kg_s"], 3.2e-5)
        self.assertClose(result["fuel_input_power_w"], 80.0)
        self.assertClose(result["chemical_power_w"], 32.0)
        self.assertClose(result["cycle_work_j"], 0.16)
        self.assertClose(result["indicated_torque_nm"], 0.16 / (2.0 * math.pi))
        self.assertClose(result["indicated_power_w"], 16.0)
        self.assertClose(result["pumping_loss_w"], 1.0)

    def test_four_stroke_analytic_mass_energy_and_720_degree_work(self) -> None:
        result = four_stroke(6000.0, 0.8, 1.0, 1.0, _four_parameters(), True, 0.5)
        self.assertTrue(result["ok"], result["message"])
        air_cycle = 1.0e-4 * 0.8
        premix_cycle = air_cycle / 10.0 / 0.9
        burned_cycle = air_cycle / 10.0 * 0.5 * 0.5
        cycle_hz = 50.0
        work = burned_cycle * 1000.0 * 0.25
        self.assertClose(result["air_charge_kg_cycle"], air_cycle)
        self.assertClose(result["delivered_fuel_kg_s"], premix_cycle * cycle_hz)
        self.assertClose(result["burned_fuel_kg_s"], burned_cycle * cycle_hz)
        self.assertClose(result["cycle_work_j"], work)
        self.assertClose(result["indicated_torque_nm"], work / (4.0 * math.pi))
        self.assertClose(result["indicated_power_w"], work * cycle_hz)
        self.assertClose(result["firing_frequency_hz"], 25.0)

    def test_port_scavenge_work_and_four_stroke_valve_pump_terms_are_separate(self) -> None:
        cases = {case["id"]: case for case in build_cases()}
        port = cases["two_stroke_port_loss"]["expected"]
        valve_pump = cases["four_stroke_valve_and_pump_loss"]["expected"]
        port_work = 600.0 * 1.0e-5 * 2.0 * 0.75
        self.assertClose(port["pumping_torque_nm"], port_work / (2.0 * math.pi))
        self.assertEqual(port["valve_torque_nm"], 0.0)
        four_stroke_pump_work = (130.0 + 40.0 * (1.0 - 0.75)) * 1.0e-4
        self.assertClose(valve_pump["pumping_torque_nm"], four_stroke_pump_work / (4.0 * math.pi))
        self.assertClose(valve_pump["valve_torque_nm"], 0.003)
        self.assertClose(valve_pump["valve_loss_w"], 0.003 * 2.0 * math.pi * 100.0)

    def test_gross_premix_mass_and_energy_conservation(self) -> None:
        valid = [case for case in build_cases() if case["expected"]["ok"]]
        self.assertGreaterEqual(len(valid), 32)
        for case in valid:
            with self.subTest(case=case["id"]):
                expected = case["expected"]
                parameters = case["parameters"]
                self.assertClose(
                    expected["delivered_fuel_kg_s"],
                    expected["burned_fuel_kg_s"] + expected["unburned_fuel_kg_s"],
                )
                self.assertClose(
                    expected["fuel_input_power_w"],
                    expected["delivered_fuel_kg_s"]
                    * (1.0 - parameters["oil_fraction"])
                    * parameters["fuel_lhv_j_kg"],
                )
                self.assertClose(
                    expected["chemical_power_w"],
                    expected["burned_fuel_kg_s"] * parameters["fuel_lhv_j_kg"],
                )

    def test_zero_charge_cut_completion_and_frequency_guards(self) -> None:
        cases = {case["id"]: case for case in build_cases()}
        for identifier in (
            "two_stroke_zero_admission", "two_stroke_zero_mixture",
            "two_stroke_zero_completion", "four_stroke_zero_admission",
            "four_stroke_zero_mixture", "four_stroke_zero_completion",
        ):
            with self.subTest(case=identifier):
                result = cases[identifier]["expected"]
                self.assertTrue(result["ok"])
                self.assertEqual(result["firing_frequency_hz"], 0.0)
                self.assertEqual(result["cycle_work_j"], 0.0)
                self.assertEqual(result["indicated_torque_nm"], 0.0)
        self.assertEqual(cases["two_stroke_zero_admission"]["expected"]["delivered_fuel_kg_s"], 0.0)
        self.assertEqual(cases["two_stroke_zero_mixture"]["expected"]["delivered_fuel_kg_s"], 0.0)
        self.assertGreater(cases["two_stroke_zero_completion"]["expected"]["delivered_fuel_kg_s"], 0.0)
        for identifier in ("two_stroke_cut", "four_stroke_cut"):
            result = cases[identifier]["expected"]
            self.assertEqual(result["delivered_fuel_kg_s"], 0.0)
            self.assertEqual(result["burned_fuel_kg_s"], 0.0)
            self.assertEqual(result["firing_frequency_hz"], 0.0)

    def test_stopped_cut_and_endpoint_cases_retain_family_specific_losses(self) -> None:
        cases = {case["id"]: case for case in build_cases()}
        for family in ("two_stroke", "four_stroke"):
            stopped = cases[f"{family}_stopped"]["expected"]
            self.assertTrue(stopped["ok"])
            self.assertEqual(stopped["mechanical_loss_w"], 0.0)
            self.assertEqual(stopped["pumping_loss_w"], 0.0)
            cut = cases[f"{family}_cut"]["expected"]
            self.assertTrue(cut["ok"])
            self.assertGreater(cut["mechanical_loss_w"], 0.0)
            self.assertGreater(cut["pumping_loss_w"], 0.0)
        for identifier in (
            "two_stroke_lower_bound", "two_stroke_upper_bound",
            "four_stroke_lower_bound", "four_stroke_upper_bound",
        ):
            self.assertTrue(cases[identifier]["expected"]["ok"], identifier)
        self.assertFalse(cases["two_stroke_unsupported_rpm"]["expected"]["ok"])
        self.assertFalse(cases["four_stroke_unsupported_mixture"]["expected"]["ok"])
        closed_four = cases["four_stroke_zero_admission"]["expected"]
        self.assertGreater(closed_four["pumping_torque_nm"], 0.0)
        self.assertGreater(closed_four["valve_torque_nm"], 0.0)

    def test_seeded_parameter_vectors_are_stable_and_present_in_json(self) -> None:
        first = build_cases()
        second = build_cases()
        self.assertEqual(first, second)
        random_cases = [case for case in first if "_random_" in case["id"]]
        self.assertEqual(len(random_cases), 16)
        document = json.loads(ORACLE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(document["schema"], ORACLE_SCHEMA)
        self.assertEqual(document["random_seed"], RANDOM_SEED)
        self.assertEqual(document["cases"], first)
        self.assertEqual(set(document["cases"][0]["expected"]) - {"ok", "message"}, set(OUTPUT_FIELDS))

    def test_invalid_operating_queries_return_finite_zero_outputs(self) -> None:
        failed = (
            two_stroke(-1.0, 0.5, 0.8, 1.0, _two_parameters()),
            two_stroke(6000.0, 0.5, 0.8, 0.0, _two_parameters()),
            four_stroke(6000.0, 0.5, 0.8, 0.0, _four_parameters()),
        )
        for result in failed:
            self.assertFalse(result["ok"])
            self.assertTrue(result["message"])
            self.assertTrue(all(math.isfinite(result[field]) and result[field] == 0.0 for field in OUTPUT_FIELDS))


if __name__ == "__main__":
    unittest.main()
