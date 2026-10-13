"""Focused checks for the inference-only glow calibration report."""
from __future__ import annotations

import importlib.util
import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "calibration_report", Path(__file__).with_name("calibration_report.py")
)
assert SPEC is not None and SPEC.loader is not None
calibration_report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(calibration_report)


class ActuatorDiskBoundTests(unittest.TestCase):
    def test_static_ideal_disk_power_and_clear_acceptance_refusal(self) -> None:
        thrust_n = 10.0
        diameter_m = 0.3
        density = 1.225
        area = math.pi * diameter_m**2 / 4.0
        ideal_speed = math.sqrt(thrust_n / (2.0 * density * area))
        ideal_power = thrust_n * ideal_speed

        accepted = calibration_report.actuator_disk_power_bound(
            thrust_n, 1.1 * ideal_power, 0.0, diameter_m, density
        )
        refused = calibration_report.actuator_disk_power_bound(
            thrust_n, 0.9 * ideal_power, 0.0, diameter_m, density
        )

        self.assertAlmostEqual(accepted["ideal_shaft_power_lower_bound_w"], ideal_power)
        self.assertEqual(accepted["status"], "accepted")
        self.assertTrue(accepted["passed"])
        self.assertEqual(refused["status"], "refused_impossible_positive_thrust_load")
        self.assertFalse(refused["passed"])
        margin_shortfall = calibration_report.actuator_disk_power_bound(
            thrust_n, 1.02 * ideal_power, 0.0, diameter_m, density
        )
        self.assertEqual(margin_shortfall["status"], "refused_below_required_power_margin")
        self.assertTrue(margin_shortfall["physical_ideal_bound_passed"])
        self.assertFalse(margin_shortfall["passed"])
        self.assertEqual(
            refused["source"], calibration_report.NASA_PROPELLER_THRUST_URL
        )

    def test_nonpositive_thrust_is_outside_positive_thrust_bound(self) -> None:
        result = calibration_report.actuator_disk_power_bound(
            -1.0, 100.0, 10.0, 0.3, 1.225
        )
        self.assertEqual(result["status"], "not_applicable_nonpositive_thrust")
        self.assertFalse(result["checked"])


class GeneratedInstallationAuditTests(unittest.TestCase):
    def test_4t_report_reads_current_generated_section_and_runtime_cap(self) -> None:
        profile_path = (
            ROOT / "app" / "data" / "glow" / "os_fs_64v_candidate.json"
        )
        generated = calibration_report.report(profile_path)
        self.assertEqual(generated["format"], "openrc-glow-inference-audit v2")
        self.assertEqual(
            generated["paired_propeller_inference"]["common_section_assumptions"]["induced_drag"],
            0.075,
        )
        for prop in generated["paired_propeller_inference"]["propellers"]:
            inputs = calibration_report.installation_inputs(prop["configuration_id"])
            self.assertEqual(prop["section_assumptions"], inputs["section"])
            self.assertEqual(prop["installation_source"]["sha256"], inputs["sha256"])
            self.assertEqual(
                prop["engine_rpm_guidance"]["generated_aircraft_max_rpm_static_field"],
                inputs["runtime_static_rpm_cap"],
            )
            audit = prop["actuator_disk_power_bound_map_audit"]
            self.assertEqual(audit["grid"]["sample_count"], 3000)
            self.assertEqual(audit["status"], "PASS")
            self.assertEqual(audit["refused_positive_thrust_sample_count"], 0)
            self.assertGreaterEqual(audit["minimum_positive_thrust_power_ratio"], 1.05)

    def test_reports_exclude_refused_positive_thrust_roots(self) -> None:
        for profile_name in [
            "os_max_55ax_candidate.json",
            "os_fs_64v_candidate.json",
        ]:
            with self.subTest(profile=profile_name):
                generated = calibration_report.report(
                    ROOT / "app" / "data" / "glow" / profile_name
                )
                for prop in generated["paired_propeller_inference"]["propellers"]:
                    for scenario in prop["static_and_advancing_full_admission_predictions"]:
                        for root in scenario["nominal_all_roots"]:
                            bound = root["actuator_disk_power_bound"]
                            if root["thrust_n"] > 0.0:
                                self.assertTrue(bound["checked"])
                                self.assertTrue(bound["passed"])
                                self.assertGreaterEqual(
                                    bound["shaft_to_ideal_power_ratio"], 1.05
                                )
                        for refusal in scenario["nominal_rejected_by_ideal_power_screen"]:
                            self.assertEqual(
                                refusal["decision"],
                                "refused by the required 5% ideal-power screen; excluded from candidate prediction and sensitivity extrema",
                            )
                        envelope = scenario["assumption_envelope"]
                        for refusal in envelope["ideal_power_screen_refusals"]:
                            self.assertEqual(
                                refusal["decision"],
                                "refused by the required 5% ideal-power screen; excluded from candidate prediction and sensitivity extrema",
                            )
                            self.assertNotEqual(refusal["sensitivity_case"], "nominal")
                if profile_name == "os_max_55ax_candidate.json":
                    anchor = generated["single_point_propeller_anchor_inference"]
                    self.assertEqual(
                        anchor["static_balance_roots_rejected_by_ideal_power_screen"], []
                    )
                    for root in anchor["static_balance_roots_after_chord_fit"]:
                        self.assertTrue(root["actuator_disk_power_bound"]["passed"])
                    second_prop = anchor["second_recommended_prop_scenario"]
                    self.assertEqual(second_prop["static_candidate_rejected_balance_roots"], [])
                    self.assertTrue(second_prop["static_candidate_root_screen"])


if __name__ == "__main__":
    unittest.main()
