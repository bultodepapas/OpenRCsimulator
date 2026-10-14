"""Source provenance and reproducibility for the experimental preset."""
import json
import unittest
from derive import ROOT, derive, schema_for

class Preset(unittest.TestCase):
    def test_generated_preset(self):
        self.assertEqual(json.loads((ROOT / "app/data/aircraft/xcell_60_research.json").read_text()), derive())

    def test_quantities_have_dimensions_and_evidence(self):
        def visit(node):
            if isinstance(node, dict) and "value" in node:
                self.assertEqual(set(node), {"value", "unit", "kind", "source"})
                self.assertTrue(node["unit"] and node["source"])
                self.assertIn(node["kind"], ["manual", "measured", "borrowed", "estimated", "derived"])
            elif isinstance(node, dict):
                for value in node.values(): visit(value)
            elif isinstance(node, list):
                for value in node: visit(value)
        visit(derive())

    def test_source_aggregate_and_gearing(self):
        data = derive()
        self.assertEqual(data["body"]["mass_kg"]["value"], 8.2)
        self.assertEqual(data["body"]["inertia_kg_m2"]["value"], [.18, .34, .28, 0, 0, 0])
        self.assertEqual(data["shaft_elements"][1]["speed_ratio"]["value"], data["tail_rotor"]["tail_to_main_speed_ratio"]["value"])
        self.assertEqual(data["drive"]["engine_torque_max_nm"]["kind"], "estimated")

    def test_schema_is_vehicle_specific_and_strict(self):
        schema = schema_for(derive())
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(schema["properties"]["vehicle"], {"const": "rotorcraft"})
        self.assertEqual(schema["properties"]["main_rotor"]["properties"]["rotor_radius_m"]["properties"]["unit"], {"const": "m"})

if __name__ == "__main__":
    unittest.main()
