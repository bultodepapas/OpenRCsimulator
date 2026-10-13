"""Read and regression-test the generated closed glow installation schema."""
from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import installation_schema  # noqa: E402


class GlowInstallationSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.schema = json.loads(installation_schema.SCHEMA_PATH.read_text(encoding="utf-8"))
        cls.installations = [
            json.loads(path.read_text(encoding="utf-8"))
            for path in installation_schema.INSTALLATION_FILES
        ]

    def test_checked_in_schema_is_generated_schema(self) -> None:
        self.assertEqual(self.schema, installation_schema.schema_document())

    def test_all_generated_installations_validate(self) -> None:
        self.assertEqual(len(self.installations), 4)
        for value in self.installations:
            with self.subTest(family=value["family"], profile=value["profile"]):
                self.assertEqual(installation_schema.validate_instance(value, self.schema), [])

    def test_schema_rejects_missing_starter_prime_quantity(self) -> None:
        value = copy.deepcopy(self.installations[0])
        del value["settings"]["starter_prime_kg"]
        self.assertTrue(installation_schema.validate_instance(value, self.schema))

    def test_schema_rejects_wrong_quantity_unit(self) -> None:
        value = copy.deepcopy(self.installations[0])
        value["settings"]["starter_prime_kg"]["unit"] = "g"
        self.assertTrue(installation_schema.validate_instance(value, self.schema))

    def test_schema_rejects_unsupported_settings(self) -> None:
        value = copy.deepcopy(self.installations[0])
        value["settings"]["unimplemented_module"] = {"enabled": True}
        self.assertTrue(installation_schema.validate_instance(value, self.schema))

    def test_schema_rejects_unbundled_profile_path(self) -> None:
        value = copy.deepcopy(self.installations[0])
        value["profile"] = "res://data/glow/../outside.json"
        self.assertTrue(installation_schema.validate_instance(value, self.schema))

    def test_schema_rejects_out_of_domain_numeric_value(self) -> None:
        value = copy.deepcopy(self.installations[0])
        value["settings"]["starter_prime_kg"]["value"] = 0.01
        self.assertTrue(installation_schema.validate_instance(value, self.schema))

    def test_entire_inventory_propeller_rotates_and_alternatives_change_inertia(self) -> None:
        # Independent inventory closure: a fixed shaft inertia for both props can
        # otherwise make the visual/aerodynamic swap pass while missing dynamics.
        for engine in ['55ax_2t', 'fs64v_4t']:
            inertias = []
            for suffix in ['', '_apc_13x6']:
                path = ROOT/'app/data/aircraft'/('stik_glow_'+engine+suffix+'.json')
                raw = json.loads(path.read_text(encoding='utf-8'))
                prop = next(part for part in raw['inventory']
                            if part['name'].startswith(('APC Sport', 'Master Airscrew')))
                width, height = prop['size']['value'][1:]
                inventory_polar = prop['mass']['value']*(width*width+height*height)/12.
                relative_polar = raw['propulsion']['propeller']['rotating_inertia']['value']
                self.assertGreater(relative_polar, inventory_polar)
                inertias.append(relative_polar)
            self.assertNotEqual(*inertias)
            self.assertGreater(inertias[1] if engine == '55ax_2t' else inertias[0],
                               inertias[0] if engine == '55ax_2t' else inertias[1])


if __name__ == "__main__":
    unittest.main()
