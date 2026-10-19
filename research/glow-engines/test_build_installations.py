"""FUEL-01a: the glow installation generator selects inventory records by id, not array position."""
from __future__ import annotations

import json
import sys
import types
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_installations  # noqa: E402

EDITED_IDS = ("item_engine_main", "item_muffler_main", "item_propeller_main", "item_fuel_main",
              "item_balance_mass_virtual")


BASE_ID = json.loads((build_installations.ROOT / "app/data/aircraft/jensen_ugly_stik_60.json")
                     .read_text(encoding="utf-8-sig"))["id"]


def _reordering_json() -> types.SimpleNamespace:
    """json stand-in that reverses the base Stik inventory as it is read."""
    def loads(text: str):
        value = json.loads(text)
        if isinstance(value, dict) and value.get("id") == BASE_ID and "inventory" in value:
            value["inventory"] = list(reversed(value["inventory"]))
        return value
    return types.SimpleNamespace(loads=loads, dumps=json.dumps)


def _by_id(raw: dict) -> dict:
    return {item["id"]: item for item in raw["inventory"]}


class InventoryIdentityTests(unittest.TestCase):
    def test_reordered_donor_inventory_edits_the_same_records(self) -> None:
        for two, fx61 in ((True, False), (False, False), (True, True)):
            with self.subTest(two=two, fx61=fx61):
                install = build_installations.installation(two, 12, 6 if fx61 else 7 if two else 6, fx61=fx61)
                normal = build_installations.aircraft(two, install, fx61=fx61)
                with mock.patch.object(build_installations, "json", _reordering_json()):
                    reordered = build_installations.aircraft(two, install, fx61=fx61)
                self.assertNotEqual([i["id"] for i in normal["inventory"]],
                                    [i["id"] for i in reordered["inventory"]])
                a, b = _by_id(normal), _by_id(reordered)
                for identity in EDITED_IDS[:-1]:
                    self.assertEqual(a[identity], b[identity], identity)
                self.assertEqual(b["item_fuel_main"].get("energy_source"), "glow_fuel")
                self.assertEqual(b["item_fuel_main"]["name"], "usable glow premix")
                # Only the virtual ballast depends on summation order; it must agree to rounding.
                for key in ("mass", "position"):
                    va = a["item_balance_mass_virtual"][key]["value"]
                    vb = b["item_balance_mass_virtual"][key]["value"]
                    for x, y in zip(va if isinstance(va, list) else [va], vb if isinstance(vb, list) else [vb]):
                        self.assertAlmostEqual(x, y, delta=1e-12 * max(1.0, abs(x)))


def _inventory_cg(raw: dict) -> list[float]:
    mass = sum(i["mass"]["value"] for i in raw["inventory"])
    return [sum(i["mass"]["value"] * i["position"]["value"][k] for i in raw["inventory"]) / mass for k in range(3)]


class DatumTests(unittest.TestCase):
    def test_every_variant_keeps_the_base_hub_about_its_own_datum(self) -> None:
        """thrust_line_offset is datum-relative: the tank and engine move the datum, never the hub."""
        base = json.loads((build_installations.ROOT / "app/data/aircraft/jensen_ugly_stik_60.json")
                          .read_text(encoding="utf-8-sig"))
        hub = [c + o for c, o in zip(_inventory_cg(base), base["propulsion"]["propeller"]["thrust_line_offset"]["value"])]
        variants = [raw for path, raw in build_installations.outputs().items() if path.parent.name == "aircraft"]
        self.assertEqual(len(variants), 5)
        for raw in variants:
            with self.subTest(aircraft=raw["id"]):
                offset = raw["propulsion"]["propeller"]["thrust_line_offset"]["value"]
                for k, (c, o) in enumerate(zip(_inventory_cg(raw), offset)):
                    self.assertAlmostEqual(c + o, hub[k], delta=1e-11)
                # The full tank sits ahead of the dry balance point, so the datum is ahead of the plan CG.
                self.assertLess(_inventory_cg(raw)[0], raw["balance"]["plan_cg"]["value"][0])


if __name__ == "__main__":
    unittest.main()
