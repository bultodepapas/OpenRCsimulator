"""Metadata-only parity checks for authored physical identities in aircraft JSON."""

from __future__ import annotations

import argparse
import json
import sys
import unittest
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

from physical_identity import validate_physical_identity  # noqa: E402


IDENTIFIED_OUTPUTS = (
    "jensen_ugly_stik_60.json",
    "stik_glow_55ax_2t.json",
    "stik_glow_fs64v_4t.json",
    "gp_extra_300s_60.json",
    "p51d_mustang_120.json",
    "sebart_avanti_s_a200.json",
    "turbo_lumber_evolution.json",
    "stik_glow_55ax_2t_apc_13x6.json",
    "stik_glow_fs64v_4t_apc_13x6.json",
)


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


def _diff_paths(before: Any, after: Any, path: str = "") -> list[str]:
    if type(before) is not type(after):
        return [path or "/"]
    if isinstance(before, dict):
        differences = []
        for key in sorted(before.keys() | after.keys()):
            child = f"{path}/{key}"
            if key not in before or key not in after:
                differences.append(child)
            else:
                differences.extend(_diff_paths(before[key], after[key], child))
            if len(differences) >= 20:
                return differences[:20]
        return differences
    if isinstance(before, list):
        differences = []
        if len(before) != len(after):
            differences.append(f"{path}/length")
        for index, (left, right) in enumerate(zip(before, after)):
            differences.extend(_diff_paths(left, right, f"{path}/{index}"))
            if len(differences) >= 20:
                return differences[:20]
        return differences[:20]
    return [] if before == after else [path or "/"]


def audit_baseline(baseline_dir: Path) -> int:
    """Compare identity-stripped generated JSON with a caller-supplied snapshot set."""
    aircraft_dir = ROOT / "app/data/aircraft"
    failures = 0
    for filename in IDENTIFIED_OUTPUTS:
        baseline_path = baseline_dir / filename
        current_path = aircraft_dir / filename
        if not baseline_path.is_file():
            print(f"MISSING baseline: {baseline_path}")
            failures += 1
            continue
        before = json.loads(baseline_path.read_text(encoding="utf-8"))
        after = json.loads(current_path.read_text(encoding="utf-8"))
        differences = _diff_paths(_without_identity(before), _without_identity(after))
        if differences:
            print(f"DIFF {filename}: {', '.join(differences)}")
            failures += 1
        else:
            print(f"SAME {filename}: all non-identity JSON values match")
    return failures


class PhysicalIdentitySourceTests(unittest.TestCase):
    def test_catalog_and_glow_outputs_have_valid_identity_modules(self) -> None:
        aircraft_dir = ROOT / "app/data/aircraft"
        for filename in IDENTIFIED_OUTPUTS:
            with self.subTest(aircraft=filename):
                data = json.loads((aircraft_dir / filename).read_text(encoding="utf-8"))
                validate_physical_identity(data)

    def test_identified_aircraft_json_uses_authored_crlf_bytes(self) -> None:
        aircraft_dir = ROOT / "app/data/aircraft"
        for filename in IDENTIFIED_OUTPUTS:
            with self.subTest(aircraft=filename):
                content = (aircraft_dir / filename).read_bytes()
                self.assertTrue(content.endswith(b"\r\n"))
                self.assertNotIn(b"\n", content.replace(b"\r\n", b""))

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
    argument_parser = argparse.ArgumentParser(description=__doc__)
    argument_parser.add_argument(
        "--baseline-dir",
        type=Path,
        help="optionally audit identity-stripped outputs against JSON snapshots in this directory",
    )
    args, unittest_args = argument_parser.parse_known_args()
    if args.baseline_dir is not None:
        failures = audit_baseline(args.baseline_dir)
        if failures:
            raise SystemExit(f"{failures} identity-stripped baseline comparison(s) differ")
    unittest.main(argv=[sys.argv[0], *unittest_args])
