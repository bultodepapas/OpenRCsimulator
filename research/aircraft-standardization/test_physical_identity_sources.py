"""Metadata-only parity checks for authored physical identities in aircraft JSON."""

from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

from physical_identity import validate_physical_identity  # noqa: E402


# SHA-256 of canonical JSON after removing only the identity module. These were
# captured from the pre-identity fleet and Glow APC snapshots; arrays and every
# non-identity value remain in the canonical serialization.
BASELINE_SHA256 = {
    "jensen_ugly_stik_60.json": "37f88602b128f0b1e719998cdd5926b41a4bed7f570caebafc7f1ea962f27fa3",
    "stik_glow_55ax_2t.json": "e8921fec4ba813dad11c55293f6289ff65e340f35f4142abca96f9bcbf66bb2e",
    "stik_glow_fs64v_4t.json": "4f19ebbc82944b14c711d0ed542e36adf20150dc62eb5188b50a4ace7ce9f8a5",
    "gp_extra_300s_60.json": "90c2b2bfc570a1382c3094b318ce53eab79c24777a32f10cdbd37af9df50d3b7",
    "p51d_mustang_120.json": "cc86c692505fded48a33625c9b3f4dc68a0b8fe50bb30b2f9e88f67eed7b0ce4",
    "sebart_avanti_s_a200.json": "703d72fb68e78d88603d62585d16ba96eec0880ff653100bdd43a12c86b81172",
    "turbo_lumber_evolution.json": "b19690809eb57a33ccc9c035e0a654d7d7b58d31b17217b411cdb1c338e9c4e7",
    "stik_glow_55ax_2t_apc_13x6.json": "7bacab888137161ba197c7b0815caa71e182137266da3ab93c8da2743e7ad061",
    "stik_glow_fs64v_4t_apc_13x6.json": "518c915d30fd6579e124e3a4459f03ee38dcb4ba8b80a3aa7815bd576e0f4871",
}


def _without_identity(data: dict[str, Any]) -> dict[str, Any]:
    result = json.loads(json.dumps(data))
    result.pop("physical_identity_version", None)
    for item in result.get("inventory", []):
        item.pop("id", None)
    for contact in result.get("landing_gear", {}).get("contacts", []):
        contact.pop("id", None)
    result.pop("crash_hull_ids", None)
    result.get("propulsion", {}).pop("id", None)
    result.get("controls", {}).pop("surface_ids", None)
    return result


def _canonical_hash(data: dict[str, Any]) -> str:
    encoded = json.dumps(
        _without_identity(data),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


class PhysicalIdentitySourceTests(unittest.TestCase):
    def test_catalog_and_glow_outputs_keep_all_non_identity_data(self) -> None:
        aircraft_dir = ROOT / "app/data/aircraft"
        self.assertEqual(len(BASELINE_SHA256), 9)
        for filename, expected_hash in BASELINE_SHA256.items():
            with self.subTest(aircraft=filename):
                data = json.loads((aircraft_dir / filename).read_text(encoding="utf-8"))
                validate_physical_identity(data)
                self.assertEqual(_canonical_hash(data), expected_hash)

    def test_onboarding_template_has_complete_module(self) -> None:
        template = ROOT / "research/aircraft-standardization/template/openrc-aircraft-v2.template.json"
        data = json.loads(template.read_text(encoding="utf-8"))
        validate_physical_identity(data)

    def test_synthetic_electric_regression_fixtures_remain_idless(self) -> None:
        fixtures = sorted((ROOT / "app/data/aircraft").glob("synthetic_stik_electric_*.json"))
        self.assertEqual(len(fixtures), 4)
        for path in fixtures:
            with self.subTest(fixture=path.name):
                data = json.loads(path.read_text(encoding="utf-8"))
                self.assertNotIn("physical_identity_version", data)

    def test_float_version_and_gearless_aircraft_are_supported(self) -> None:
        data = {
            "physical_identity_version": 1.0,
            "inventory": [{"id": "engine_main"}],
            "crash_hull": {"value": [[0.0, 0.0, 0.0]]},
            "crash_hull_ids": ["probe_nose"],
            "propulsion": {"id": "propulsion_main"},
            "controls": {
                "surface_ids": {
                    "aileron_left": "surface_aileron_left",
                    "aileron_right": "surface_aileron_right",
                    "elevator": "surface_elevator",
                    "rudder": "surface_rudder",
                }
            },
        }
        validate_physical_identity(data)

    def test_version_rejects_bool_and_id_rejects_trailing_newline(self) -> None:
        data = {
            "physical_identity_version": True,
            "inventory": [{"id": "engine_main"}],
            "landing_gear": {"contacts": []},
            "crash_hull": {"value": []},
            "crash_hull_ids": [],
            "propulsion": {"id": "propulsion_main"},
            "controls": {
                "surface_ids": {
                    "aileron_left": "surface_aileron_left",
                    "aileron_right": "surface_aileron_right",
                    "elevator": "surface_elevator",
                    "rudder": "surface_rudder",
                }
            },
        }
        with self.assertRaisesRegex(ValueError, "physical_identity_version"):
            validate_physical_identity(data)
        data["physical_identity_version"] = 1
        data["inventory"][0]["id"] = "engine_main\n"
        with self.assertRaisesRegex(ValueError, "invalid ID"):
            validate_physical_identity(data)

    def test_identity_is_unique_across_all_groups(self) -> None:
        data = {
            "physical_identity_version": 1,
            "inventory": [{"id": "engine_main"}],
            "landing_gear": {"contacts": [{"id": "engine_main"}]},
            "crash_hull": {"value": []},
            "crash_hull_ids": [],
            "propulsion": {"id": "propulsion_main"},
            "controls": {
                "surface_ids": {
                    "aileron_left": "surface_aileron_left",
                    "aileron_right": "surface_aileron_right",
                    "elevator": "surface_elevator",
                    "rudder": "surface_rudder",
                }
            },
        }
        with self.assertRaisesRegex(ValueError, "duplicates"):
            validate_physical_identity(data)


if __name__ == "__main__":
    unittest.main()
