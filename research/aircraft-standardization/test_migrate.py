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
    return legacy_input(json.loads((ROOT / "app/data/aircraft" / name).read_text(encoding="utf-8")))


class AircraftMigration(unittest.TestCase):
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
