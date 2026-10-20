"""FUEL-01e/FUEL-05-R1 report coverage, states, ranges, qualification and drift behavior."""
from __future__ import annotations

import copy
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fuel_registry  # noqa: E402
import mass_balance_report as report  # noqa: E402

STIK = report.AIRCRAFT_DIR / "jensen_ugly_stik_60.json"
NO_TANKS = "turbo_lumber_evolution.json"
GLOW = "stik_glow_61fx_2t.json"
PACK = "battery/turbo_lumber_evolution_4s_pack.json"


def _q(value, unit):
    return {
        "value": value,
        "unit": unit,
        "kind": "estimated",
        "source": "test fixture",
    }


class MassBalanceReportTests(unittest.TestCase):
    def test_full_state_uses_capacity_times_registry_density(self) -> None:
        raw = copy.deepcopy(json.loads(STIK.read_text(encoding="utf-8-sig")))
        raw["fuel_system"] = {
            "tanks": [
                {
                    "id": "main_tank",
                    "fuel": "glow_10n_18castor",
                    "liquid_inventory_id": "item_fuel_main",
                    "shell_inventory_id": "item_fuel_tank",
                    "capacity": _q(0.225, "l"),
                    "unusable": _q(0.005, "l"),
                    "pickup": "clunk",
                    "feed": "suction_muffler",
                }
            ]
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, STIK.name)
            path.write_text(json.dumps(raw), encoding="utf-8")
            saved = report.AIRCRAFT_DIR
            report.AIRCRAFT_DIR = Path(directory)
            try:
                rows = report.aircraft_rows()
            finally:
                report.AIRCRAFT_DIR = saved
        self.assertEqual(len(rows), 1)
        states = rows[0]["states"]
        capacity_kg = 0.225e-3 * fuel_registry.blend_density("glow_10n_18castor")
        self.assertAlmostEqual(
            states["full"]["mass_kg"],
            states["empty"]["mass_kg"] + capacity_kg,
            delta=2e-6,
        )
        self.assertLess(states["full"]["cg_m"][0], states["declared"]["cg_m"][0])
        self.assertGreater(states["empty"]["cg_m"][0], states["declared"]["cg_m"][0])
        self.assertGreater(
            states["full"]["static_margin_pct_mac"],
            states["empty"]["static_margin_pct_mac"],
        )

    def test_recursive_catalog_and_supported_variant_coverage(self) -> None:
        data = report.report()
        rows = {row["file"]: row for row in data["aircraft"]}
        coverage = data["coverage"]
        self.assertGreaterEqual(len(rows), 15)
        self.assertGreaterEqual(len(coverage["catalog_data_files"]), 9)
        self.assertEqual(coverage["catalog_covered_files"], coverage["catalog_data_files"])
        self.assertEqual(coverage["catalog_missing_files"], [])
        self.assertGreaterEqual(len(coverage["supported_data_variants"]), 6)
        self.assertIn(PACK, rows)
        self.assertEqual(rows[PACK]["catalog_ids"], ["turbo-lumber-evolution"])
        self.assertEqual(rows[PACK]["variant_kind"], "catalog")
        self.assertIn("stik_glow_55ax_2t_apc_13x6.json", rows)
        self.assertEqual(rows["stik_glow_55ax_2t_apc_13x6.json"]["catalog_ids"], [])
        self.assertNotIn("xcell-60-research", [row["id"] for row in rows.values()])

    def test_plan_state_and_declared_range_are_explicit(self) -> None:
        rows = {row["file"]: row for row in report.aircraft_rows()}
        base_stik = rows["jensen_ugly_stik_60.json"]
        extra = rows["gp_extra_300s_60.json"]
        timber = rows[NO_TANKS]
        self.assertEqual(base_stik["balance_fuel_state"], "empty_tanks")
        self.assertEqual(base_stik["plan_cg_state"], "empty")
        self.assertTrue(base_stik["plan_cg_matches_inventory"])
        self.assertEqual(extra["cg_range_check"]["status"], "within")
        self.assertEqual(extra["cg_range_check"]["plan_state"], "empty")
        self.assertAlmostEqual(extra["cg_range_check"]["plan_cg_x_m"], 0.1088)
        self.assertEqual(timber["plan_cg_state"], "declared")
        self.assertEqual(timber["cg_range_check"]["status"], "not_declared")
        self.assertNotIn("full", timber["states"])

    def test_missing_neutral_point_is_visible_but_only_fails_qualification(self) -> None:
        data = report.report()
        synthetic = next(
            row
            for row in data["aircraft"]
            if row["id"] == "synthetic_stik_electric_4s"
        )
        self.assertIsNone(synthetic["neutral_point"])
        self.assertIn("missing_neutral_point", synthetic["flags"])
        self.assertEqual(report.failures(data), [])
        qualification = report.qualification_failures(data)
        self.assertTrue(any("synthetic_stik_electric_4s.json" in line for line in qualification))
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            status = report.main(["--qualify"])
        self.assertEqual(status, 1)
        self.assertIn("QUALIFICATION FAIL", stderr.getvalue())

    def test_declared_range_violation_is_an_ordinary_report_failure(self) -> None:
        data = report.report()
        extra = next(
            row for row in data["aircraft"] if row["id"] == "gp-extra-300s-60"
        )
        extra["cg_range_check"]["status"] = "outside"
        self.assertTrue(
            any("gp_extra_300s_60.json" in line and "outside" in line for line in report.failures(data))
        )

    def test_drift_is_advisory_by_default_and_can_be_gated(self) -> None:
        stored = report.report()
        stored["aircraft"][0]["states"]["declared"]["mass_kg"] += 0.01
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "stored.json")
            path.write_text(json.dumps(stored), encoding="utf-8")
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                default_status = report.main(["--check", str(path)])
            self.assertEqual(default_status, 0)
            self.assertIn("DRIFT", stdout.getvalue())
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                strict_status = report.main(
                    ["--check", str(path), "--fail-on-drift"]
                )
            self.assertEqual(strict_status, 1)
            self.assertIn("FAIL DRIFT", stderr.getvalue())

    def test_full_state_only_where_tanks_are_declared_and_donors_have_ids(self) -> None:
        rows = {row["file"]: row for row in report.aircraft_rows()}
        self.assertNotIn("full", rows[NO_TANKS]["states"])
        self.assertEqual(rows[NO_TANKS]["balance_fuel_state"], "as_inventory")
        glow = rows[GLOW]
        self.assertEqual(glow["balance_fuel_state"], "empty_tanks")
        self.assertEqual(
            glow["states"]["full"]["mass_kg"],
            glow["states"]["declared"]["mass_kg"],
        )
        for filename in (
            "synthetic_stik_electric_4s.json",
            "synthetic_stik_electric_6s.json",
            "synthetic_stik_electric_4s_battery.json",
            "synthetic_stik_electric_6s_battery.json",
        ):
            row = rows[filename]
            donors = row["neutral_donor_items"]
            self.assertEqual(len(donors), 4)
            self.assertEqual(len({item["id"] for item in donors}), 4)
            self.assertTrue(all(item["id"] for item in donors))
            self.assertNotIn("neutral_donor_missing_id:4", row["flags"])


if __name__ == "__main__":
    unittest.main()
