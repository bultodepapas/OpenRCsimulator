"""Source provenance and reproducibility for the experimental preset."""
import json
import unittest
from derive import ROOT, derive, hx700_derive_module, schema_for_profiles

class Preset(unittest.TestCase):
    def test_generated_preset(self):
        self.assertEqual(json.loads((ROOT / "app/data/aircraft/xcell_60_research.json").read_text()), derive())

    def test_generated_hx700_profile_is_independent_and_laboratory_only(self):
        hx700 = hx700_derive_module().derive()
        artifact = json.loads((ROOT / "app/data/aircraft/hx700_electric_3d_experimental.json").read_text())
        self.assertEqual(artifact, hx700)
        self.assertEqual(hx700["id"], "hx700-electric-3d-experimental")
        self.assertEqual(hx700["release_state"], "laboratory_only")
        self.assertNotIn("trainer", hx700["capabilities"])
        self.assertNotEqual(hx700["id"], derive()["id"])
        self.assertEqual(hx700["body"]["mass_kg"]["value"], 5.2)
        self.assertEqual(hx700["body"]["mass_kg"]["kind"], "estimated")
        self.assertEqual(hx700["main_rotor"]["omega_nominal_rad_s"]["value"], 2100 * 2 * 3.141592653589793 / 60)
        self.assertEqual(hx700["tail_rotor"]["tail_to_main_speed_ratio"]["value"], 4.92307710647583)
        self.assertNotEqual(hx700["tail_rotor"]["tail_to_main_speed_ratio"]["value"],
                            derive()["tail_rotor"]["tail_to_main_speed_ratio"]["value"])
        self.assertEqual(hx700["shaft_elements"][1]["speed_ratio"]["value"],
                         hx700["tail_rotor"]["tail_to_main_speed_ratio"]["value"])
        self.assertEqual(hx700["electronics"]["controller_law"], "openrc-fbl-body-rate-electronics-v1")
        self.assertEqual(hx700["electronics"]["curves_by_mode"]["3d"]["pitch"]["value"],
                         [-1.0, -0.5, 0.0, 0.5, 1.0])

        def visit(node):
            if isinstance(node, dict) and "value" in node:
                self.assertEqual(set(node), {"value", "unit", "kind", "source"})
                self.assertTrue(node["unit"] and node["source"])
                self.assertIn(node["kind"], ["manual", "measured", "borrowed", "estimated", "derived"])
                if node["kind"] == "measured":
                    self.fail("HX-700 candidate must not present unverified physical values as measured")
            elif isinstance(node, dict):
                for value in node.values():
                    visit(value)
            elif isinstance(node, list):
                for value in node:
                    visit(value)

        visit(hx700)

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
        hx700 = hx700_derive_module().derive()
        schema = schema_for_profiles([derive(), hx700])
        generated = json.loads((ROOT / "app/data/schema/openrc-rotorcraft-v2.schema.json").read_text())
        self.assertEqual(generated, {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "openrc-rotorcraft-v2",
            **schema,
        })
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(schema["properties"]["vehicle"], {"const": "rotorcraft"})
        self.assertEqual(schema["properties"]["id"]["enum"],
                         ["xcell-60-research", "hx700-electric-3d-experimental"])
        self.assertEqual(len(schema["properties"]["electronics"]["oneOf"]), 2)
        self.assertEqual(schema["properties"]["release_state"], {"const": "laboratory_only"})
        hx700_branch = schema["oneOf"][1]
        self.assertIn("release_state", hx700_branch["required"])
        self.assertEqual(hx700_branch["properties"]["release_state"], {"const": "laboratory_only"})
        self.assertEqual(schema["properties"]["main_rotor"]["properties"]["rotor_radius_m"]["properties"]["unit"], {"const": "m"})

if __name__ == "__main__":
    unittest.main()
