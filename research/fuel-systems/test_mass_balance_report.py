"""FUEL-01e/FUEL-03: the mass/balance report's declared, empty and full states on a fixture with a fuel_system."""
from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fuel_registry  # noqa: E402
import mass_balance_report as report  # noqa: E402

STIK = report.AIRCRAFT_DIR / "jensen_ugly_stik_60.json"
NO_TANKS = "turbo_lumber_evolution.json"  # electric: no fuel system
GLOW = "stik_glow_61fx_2t.json"  # FUEL-05a: declares a 350 cc tank


def _q(value, unit):
    return {"value": value, "unit": unit, "kind": "estimated", "source": "test fixture"}


class MassBalanceReportTests(unittest.TestCase):
    def test_full_state_uses_capacity_times_registry_density(self) -> None:
        raw = copy.deepcopy(json.loads(STIK.read_text(encoding="utf-8-sig")))
        raw.pop("fuel_system", None)  # FUEL-05f: replace the base Stik's own tank with the 0.225 l fixture
        raw["fuel_system"] = {"tanks": [{"id": "main_tank", "fuel": "glow_10n_18castor",
            "liquid_inventory_id": "item_fuel_main", "shell_inventory_id": "item_fuel_tank",
            "capacity": _q(0.225, "l"), "unusable": _q(0.005, "l"), "pickup": "clunk", "feed": "suction_muffler"}]}
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, STIK.name).write_text(json.dumps(raw), encoding="utf-8")
            saved = report.AIRCRAFT_DIR
            report.AIRCRAFT_DIR = Path(directory)
            try:
                rows = report.aircraft_rows()
            finally:
                report.AIRCRAFT_DIR = saved
        self.assertEqual(len(rows), 1)
        states = rows[0]["states"]
        capacity_kg = 0.225e-3 * fuel_registry.blend_density("glow_10n_18castor")
        self.assertAlmostEqual(states["full"]["mass_kg"], states["empty"]["mass_kg"] + capacity_kg, delta=2e-6)
        # The tank sits ahead of the CG: full is forward of declared, empty aft; margins order the same way.
        self.assertLess(states["full"]["cg_m"][0], states["declared"]["cg_m"][0])
        self.assertGreater(states["empty"]["cg_m"][0], states["declared"]["cg_m"][0])
        self.assertGreater(states["full"]["static_margin_pct_mac"], states["empty"]["static_margin_pct_mac"])

    def test_full_state_only_where_tanks_are_declared(self) -> None:
        rows = {row["file"]: row for row in report.aircraft_rows()}
        self.assertNotIn("full", rows[NO_TANKS]["states"])
        self.assertEqual(rows[NO_TANKS]["balance_fuel_state"], "as_inventory")
        glow = rows[GLOW]
        self.assertEqual(glow["balance_fuel_state"], "empty_tanks")
        # FUEL-05a starts full, so the declared state is the full state.
        self.assertEqual(glow["states"]["full"]["mass_kg"], glow["states"]["declared"]["mass_kg"])


if __name__ == "__main__":
    unittest.main()
