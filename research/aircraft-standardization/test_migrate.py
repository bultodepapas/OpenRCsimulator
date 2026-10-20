#!/usr/bin/env python3
"""Focused structural and numeric checks for the AS-02 migration."""
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from migrate import (  # noqa: E402
    CONVENTION_ID,
    FORMAT_V1,
    FORMAT_V2,
    KNOWN_FILES,
    LEGACY_ROTATION,
    POLICIES,
    ROTATION_V2,
    _numeric_leaves,
    _validate_v2_source,
    legacy_input,
    numeric_parity,
    upgrade,
)


def fixture(name: str) -> dict:
    source = json.loads((ROOT / "app/data/aircraft" / name).read_text(encoding="utf-8"))
    # AS-02's historic jet had no wheel contacts. AV-09 is separately tested as
    # an explicit v2 extension, not retrospectively invented by v1 migration.
    if source.get("capabilities", {}).get("gear") == "retractable_tricycle":
        source.pop("landing_gear")
    return legacy_input(source)


class AircraftMigration(unittest.TestCase):
    def test_current_extra_finite_glow_v2_is_idempotent(self):
        source = json.loads((ROOT / "app/data/aircraft/gp_extra_300s_60.json").read_text(encoding="utf-8"))
        self.assertEqual(upgrade(source), source)
        self.assertEqual(source["capabilities"]["energy"], "finite_glow_fuel")
        self.assertEqual(source["propulsion"]["engine"]["glow_installation"],
                         "res://data/glow/extra_61fx_2t.json")

    def test_current_finite_turbine_v2_is_idempotent_with_historical_v1_gear_policy(self):
        source = json.loads((ROOT / "app/data/aircraft/sebart_avanti_s_a200.json").read_text(encoding="utf-8"))
        self.assertEqual(upgrade(source), source)
        self.assertEqual(source["capabilities"]["flaps"], "simulated")
        self.assertEqual(source["flaps"]["max_angle_deg"]["value"], 50.0)
        self.assertEqual(source["capabilities"]["energy"], "finite_liquid_fuel")
        self.assertEqual(POLICIES[source["id"]]["gear"], "locked_up")
        self.assertEqual(POLICIES[source["id"]]["gear_contacts"], 0)
        bad = deepcopy(source)
        del bad["landing_gear"]["contacts"][0]["retraction_path"]
        with self.assertRaisesRegex(ValueError, "contact paths"):
            upgrade(bad)
        bad_flaps = deepcopy(source)
        bad_flaps["capabilities"]["flaps"] = "not_simulated"
        with self.assertRaisesRegex(ValueError, "flaps data requires"):
            upgrade(bad_flaps)

    def test_current_finite_gasoline_v2_is_idempotent_with_historical_v1_gear_policy(self):
        source = json.loads((ROOT / "app/data/aircraft/p51d_mustang_120.json").read_text(encoding="utf-8"))
        self.assertEqual(upgrade(source), source)
        self.assertEqual(source["capabilities"]["flaps"], "simulated")
        self.assertEqual(source["capabilities"]["energy"], "finite_liquid_fuel")
        self.assertEqual(POLICIES[source["id"]]["gear"], "locked_down_taildragger")
        incomplete = deepcopy(source)
        del incomplete["flaps"]["aerodynamic_gain"]
        with self.assertRaisesRegex(ValueError, "complete flaps module"):
            upgrade(incomplete)
        bad_flaps = deepcopy(source)
        bad_flaps["capabilities"]["flaps"] = "not_simulated"
        with self.assertRaisesRegex(ValueError, "flaps data requires"):
            upgrade(bad_flaps)

    def test_finite_current_routes_keep_explicit_historical_v1_projection(self):
        expected = {
            "gp_extra_300s_60.json": "finite_glow_fuel",
            "p51d_mustang_120.json": "finite_liquid_fuel",
            "sebart_avanti_s_a200.json": "finite_liquid_fuel",
        }
        for name, energy in expected.items():
            with self.subTest(name=name):
                source = json.loads((ROOT / "app/data/aircraft" / name).read_text(encoding="utf-8"))
                self.assertEqual(source["capabilities"]["energy"], energy)
                historical = legacy_input(source)
                self.assertEqual(historical["format"], FORMAT_V1)
                self.assertNotIn("capabilities", historical)
                # This is a version projection for historical research tools, not a production-loader fallback.
                self.assertIn("fuel_system", historical)
                if name != "gp_extra_300s_60.json":
                    self.assertIn("fuel_consumption", historical["propulsion"])

    def test_empty_tank_projection_uses_full_inventory_cg_for_v1(self):
        source = json.loads(
            (ROOT / "app/data/aircraft/stik_glow_61fx_2t.json").read_text(encoding="utf-8")
        )
        original = deepcopy(source)
        historical = legacy_input(source)
        inventory = historical["inventory"]
        total_mass = sum(item["mass"]["value"] for item in inventory)
        expected = [
            sum(item["mass"]["value"] * item["position"]["value"][axis] for item in inventory)
            / total_mass
            for axis in range(3)
        ]
        for actual, wanted in zip(historical["balance"]["plan_cg"]["value"], expected):
            self.assertAlmostEqual(actual, wanted, places=14)
        self.assertEqual(historical["balance"]["plan_cg"]["kind"], "derived")
        self.assertEqual(
            historical["balance"]["plan_cg"]["source"],
            "v1 compatibility projection: full inventory CG",
        )
        self.assertEqual(source, original, "legacy projection must not mutate its v2 source")

    def test_legacy_projection_preserves_malformed_plan_cg(self):
        source = json.loads(
            (ROOT / "app/data/aircraft/stik_glow_61fx_2t.json").read_text(encoding="utf-8")
        )
        malformed_values = [
            "bad-vector", [0.0, 0.0], [0.0, 0.0, float("nan")],
            [0.0, 0.0, 3.0], [0.0, 0.0, 10 ** 500],
        ]
        for malformed_value in malformed_values:
            with self.subTest(value=malformed_value):
                case = deepcopy(source)
                evidence = case["balance"]["plan_cg"]
                evidence["value"] = malformed_value
                original_evidence = deepcopy(evidence)
                projected = legacy_input(case)
                self.assertEqual(projected["balance"]["plan_cg"], original_evidence)

        for malformed_field, malformed_value in (
            ("kind", "unsupported"), ("source", None), ("source", "\t\n"),
        ):
            with self.subTest(field=malformed_field):
                case = deepcopy(source)
                evidence = case["balance"]["plan_cg"]
                evidence[malformed_field] = malformed_value
                original_evidence = deepcopy(evidence)
                projected = legacy_input(case)
                self.assertEqual(projected["balance"]["plan_cg"], original_evidence)

    def test_legacy_projection_removes_v2_physical_identity_metadata(self) -> None:
        source = json.loads(
            (ROOT / "app/data/aircraft/turbo_lumber_evolution.json").read_text(encoding="utf-8")
        )
        original = deepcopy(source)
        self.assertEqual(source["physical_identity_version"], 1)
        self.assertIn("id", source["propulsion"])
        self.assertIn("id", source["inventory"][0])

        legacy = legacy_input(source)

        self.assertEqual(source, original, "legacy projection must not mutate its v2 source")
        self.assertEqual(legacy["format"], FORMAT_V1)
        self.assertNotIn("physical_identity_version", legacy)
        self.assertNotIn("crash_hull_ids", legacy)
        self.assertNotIn("flaps", legacy)
        self.assertNotIn("id", legacy["propulsion"])
        self.assertTrue(all("id" not in item for item in legacy["inventory"]))
        self.assertTrue(all("id" not in contact for contact in legacy["landing_gear"]["contacts"]))
        self.assertNotIn("surface_ids", legacy["controls"])

    def test_all_known_v1_configs_upgrade_idempotently_with_numeric_parity(self) -> None:
        for name in KNOWN_FILES:
            with self.subTest(name=name):
                raw = fixture(name)
                self.assertEqual(raw["format"], FORMAT_V1)
                original = deepcopy(raw)
                upgraded = upgrade(raw)
                self.assertEqual(raw, original, "upgrade must not mutate caller input")
                self.assertEqual(upgraded["format"], FORMAT_V2)
                self.assertEqual(upgraded["convention_id"], CONVENTION_ID)
                self.assertEqual(upgrade(upgraded), upgraded)
                self.assertIsNot(upgrade(upgraded), upgraded)

                report = numeric_parity(raw, upgraded)
                self.assertEqual(report["numeric_differences"], 0)
                self.assertEqual(report["source_numeric_leaves"], report["preserved_numeric_leaves"])
                self.assertGreaterEqual(report["added_numeric_leaves"], 0)
                for value in report["preserved_values"]:
                    self.assertEqual(value["before"], value["after"])

                policy = POLICIES[raw["id"]]
                self.assertEqual(upgraded["capabilities"]["gear"], policy["gear"])
                self.assertEqual(upgraded["capabilities"]["energy"], policy["energy"])
                self.assertIn("level_speed", upgraded["start"])
                if policy.get("rotation"):
                    self.assertEqual(upgraded["propulsion"]["propeller"]["rotation"], ROTATION_V2)
                else:
                    self.assertNotIn("rotation", upgraded["propulsion"].get("propeller", {}))

                legacy = legacy_input(upgraded)
                self.assertEqual(legacy["format"], FORMAT_V1)
                self.assertNotIn("convention_id", legacy)
                self.assertNotIn("capabilities", legacy)
                if policy.get("rotation"):
                    self.assertEqual(legacy["propulsion"]["propeller"]["rotation"], LEGACY_ROTATION)
                old_numeric = _numeric_leaves(raw)
                returned_numeric = _numeric_leaves(legacy)
                for path, value in old_numeric.items():
                    self.assertEqual(returned_numeric.get(path), value, path)

    def test_unknown_id_format_and_legacy_conflicts_fail_closed(self) -> None:
        raw = fixture(KNOWN_FILES[0])
        unknown = deepcopy(raw)
        unknown["id"] = "new-aircraft"
        with self.assertRaisesRegex(ValueError, "no AS-02 migration policy"):
            upgrade(unknown)

        unsupported = deepcopy(raw)
        unsupported["format"] = "openrc-aircraft v3"
        with self.assertRaisesRegex(ValueError, "expected .*openrc-aircraft v1"):
            upgrade(unsupported)

        wrong_rotation = deepcopy(raw)
        wrong_rotation["propulsion"]["propeller"]["rotation"] = "counterclockwise_from_rear"
        with self.assertRaisesRegex(ValueError, "unrecognized tractor rotation"):
            upgrade(wrong_rotation)

        conflicting_cladot = deepcopy(raw)
        conflicting_cladot["aero"].setdefault("reference_coefficients", {})["CLadot"] = {
            "value": 99.0, "unit": "1/rad", "kind": "estimated", "source": "conflict"
        }
        with self.assertRaisesRegex(ValueError, "conflicting CLadot"):
            upgrade(conflicting_cladot)

    def test_legacy_omissions_become_only_the_reviewed_explicit_defaults(self) -> None:
        raw = fixture("jensen_ugly_stik_60.json")
        raw["propulsion"].pop("kind")
        raw["start"].pop("level_speed")
        raw["inventory"][0].pop("size")
        raw["landing_gear"]["contacts"][0].pop("max_steering")

        migrated = upgrade(raw)
        self.assertEqual(migrated["propulsion"]["kind"], "glow_prop")
        self.assertEqual(migrated["start"]["level_speed"]["value"], 15.0)
        self.assertEqual(migrated["inventory"][0]["size"]["value"], [0, 0, 0])
        self.assertEqual(migrated["landing_gear"]["contacts"][0]["max_steering"]["value"], 0)
        parity = numeric_parity(raw, migrated)
        self.assertEqual(parity["numeric_differences"], 0)
        self.assertGreater(parity["added_numeric_leaves"], 0)

    def test_v2_conflicts_are_rejected_without_mutation(self) -> None:
        migrated = upgrade(fixture(KNOWN_FILES[0]))
        cases = []

        bad_caps = deepcopy(migrated)
        bad_caps["capabilities"]["gear"] = "retractable"
        cases.append((bad_caps, "capabilities"))

        bad_rotation = deepcopy(migrated)
        bad_rotation["propulsion"]["propeller"]["rotation"] = LEGACY_ROTATION
        cases.append((bad_rotation, "unrecognized tractor rotation"))

        bad_format = deepcopy(migrated)
        bad_format["format"] = "openrc-aircraft v3"
        cases.append((bad_format, "expected .*openrc-aircraft v1"))

        active_cladot = deepcopy(migrated)
        active_cladot["aero"]["coefficients"]["CLadot"] = {"value": 0.0}
        cases.append((active_cladot, "inert CLadot"))

        missing_cladot = deepcopy(migrated)
        del missing_cladot["aero"]["reference_coefficients"]["CLadot"]
        cases.append((missing_cladot, "missing inert aero.reference_coefficients.CLadot"))

        for raw, message in cases:
            with self.subTest(message=message):
                original = deepcopy(raw)
                with self.assertRaisesRegex(ValueError, message):
                    upgrade(raw)
                self.assertEqual(raw, original)

    def test_check_requires_v2_source_instead_of_upgrading_v1_in_memory(self) -> None:
        raw = fixture(KNOWN_FILES[0])
        with self.assertRaisesRegex(ValueError, "source format is 'openrc-aircraft v1'"):
            _validate_v2_source(raw, Path(KNOWN_FILES[0]))
        upgraded = upgrade(raw)
        self.assertEqual(_validate_v2_source(upgraded, Path(KNOWN_FILES[0])), upgraded)

        with tempfile.TemporaryDirectory() as temp_name:
            input_dir = Path(temp_name)
            (input_dir / KNOWN_FILES[0]).write_text(json.dumps(raw), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(Path(__file__).with_name("migrate.py")), "--check-known", "--input-dir", str(input_dir)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("source format is 'openrc-aircraft v1'", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
