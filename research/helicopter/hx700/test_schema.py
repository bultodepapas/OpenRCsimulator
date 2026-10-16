"""Validate the generated HX-700 profile against the rotorcraft v2 schema."""
import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[3]
SCHEMA_PATH = ROOT / "app/data/schema/openrc-rotorcraft-v2.schema.json"
CANDIDATE_PATH = ROOT / "app/data/aircraft/hx700_electric_3d_experimental.json"


class HX700SchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        cls.candidate = json.loads(CANDIDATE_PATH.read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(cls.schema)
        cls.validator = Draft202012Validator(cls.schema)

    def test_generated_candidate_validates(self):
        self.validator.validate(self.candidate)

    def test_quantity_requires_source(self):
        candidate = copy.deepcopy(self.candidate)
        del candidate["body"]["mass_kg"]["source"]

        self.assertFalse(self.validator.is_valid(candidate))

    def test_quantity_rejects_unsupported_evidence_kind(self):
        candidate = copy.deepcopy(self.candidate)
        candidate["main_rotor"]["rotor_radius_m"]["kind"] = "calibrated_guess"

        self.assertFalse(self.validator.is_valid(candidate))

    def test_quantity_rejects_invalid_units(self):
        candidate = copy.deepcopy(self.candidate)
        candidate["main_rotor"]["rotor_radius_m"]["unit"] = "mm"

        self.assertFalse(self.validator.is_valid(candidate))


if __name__ == "__main__":
    unittest.main()
