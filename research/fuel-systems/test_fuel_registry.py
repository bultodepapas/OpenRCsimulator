"""FUEL-02: the Python registry reader agrees with the hand sums the GDScript test uses."""
from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fuel_registry  # noqa: E402


class FuelRegistryTests(unittest.TestCase):
    def test_blend_densities_are_volume_weighted_sums(self) -> None:
        expected = {
            "glow_10n_18castor": 0.72 * 792.0 + 0.10 * 1137.0 + 0.18 * 961.0,
            "gasoline_premix_40_1": (40.0 * 745.0 + 862.0) / 41.0,
            "kerosene_5pct_turbine_oil": 0.95 * 800.0 + 0.05 * 1003.5,
        }
        registry = fuel_registry.load()
        self.assertEqual(set(registry["blends"]), set(expected))
        for blend_id, value in expected.items():
            self.assertAlmostEqual(fuel_registry.blend_density(blend_id, registry), value, delta=1e-9)

    def test_fraction_sum_and_missing_slope_are_refused(self) -> None:
        registry = fuel_registry.load()
        bad = copy.deepcopy(registry)
        bad["blends"]["glow_10n_18castor"]["volume_fractions"]["methanol_aiaa_2016"] = 0.71
        with self.assertRaises(ValueError):
            fuel_registry.blend_density("glow_10n_18castor", bad)
        shifted = copy.deepcopy(registry)
        shifted["blends"]["glow_10n_18castor"]["reference_temperature"]["value"] = 288.15
        with self.assertRaises(ValueError):  # nitromethane has no slope
            fuel_registry.blend_density("glow_10n_18castor", shifted)

    def test_source_string_names_the_registry(self) -> None:
        self.assertIn("glow_10n_18castor (856.92 kg/m3", fuel_registry.blend_source("glow_10n_18castor"))


if __name__ == "__main__":
    unittest.main()
