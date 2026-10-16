"""Regression checks for the generated, laboratory-only HX-700 candidate."""
import json
import re
import unittest
from pathlib import Path

from derive import derive


ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / "app/data/aircraft/hx700_electric_3d_experimental.json"
RUNTIME_DATA = ROOT / "app/physics/rotorcraft_data.gd"

EXPECTED_FLIGHT_BLOCKERS = [
    "identified_fbl_rotor_dynamics",
    "achieved_servo_states",
    "freewheel_and_power_off_energy",
    "signed_inversion_envelope",
    "ground_start_lifecycle",
    "HX700_flight_response_validation",
]


class HX700GeneratorTests(unittest.TestCase):
    def test_generated_candidate_remains_laboratory_only(self):
        generated = derive()
        saved = json.loads(OUTPUT.read_text(encoding="utf-8"))

        self.assertEqual(saved, generated)
        self.assertEqual(generated["release_state"], "laboratory_only")
        self.assertIn("Laboratory-only", generated["qualification"])

    def test_legacy_skid_coordinates_remain_provisional_estimates(self):
        points = derive()["skids"]["points_body_frd_m"]

        self.assertEqual(points["value"], [
            0.0974, -0.0858, 0.1098,
            0.0974, 0.0858, 0.1098,
            -0.0974, -0.0858, 0.1098,
            -0.0974, 0.0858, 0.1098,
        ])
        self.assertEqual(points["kind"], "estimated")
        self.assertIn("HELI-25/README.md", points["source"])
        self.assertIn("provisional contact estimates", points["source"])
        self.assertIn("no authored physical CG datum", points["source"])
        self.assertIn("not coordinates derived", points["source"])

    def test_runtime_lab_gate_keeps_all_six_flight_blockers(self):
        source = RUNTIME_DATA.read_text(encoding="utf-8")
        match = re.search(
            r"const HX700_ACCEPTANCE_BLOCKERS: Array = \[(.*?)\]",
            source,
            re.DOTALL,
        )

        self.assertIsNotNone(match)
        blockers = re.findall(r'"([^"]+)"', match.group(1))
        self.assertEqual(blockers, EXPECTED_FLIGHT_BLOCKERS)
        self.assertRegex(
            source,
            r'"missing_capabilities"\s*:\s*HX700_ACCEPTANCE_BLOCKERS\.duplicate\(\)',
        )


if __name__ == "__main__":
    unittest.main()
