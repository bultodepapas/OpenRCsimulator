"""NITRO-06: the Python carburettor mirror reproduces the GDScript known-answer values and its invariants."""
from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import carburetor as carb  # noqa: E402


class CarburetorTests(unittest.TestCase):
    def test_constants(self) -> None:
        self.assertAlmostEqual(carb.CRITICAL_RATIO, 0.5282817877171742, places=15)
        self.assertAlmostEqual(carb.PSI_CHOKED, 0.6847314563772704, places=15)

    def test_flow_function_known_answers(self) -> None:
        for r, expected in [(0.3, 1.0), (0.6, 0.988585008850183), (0.8, 0.818804239195763),
                            (0.9, 0.617148313960041), (0.99, 0.205426085356801), (1.0, 0.0)]:
            self.assertAlmostEqual(carb.flow_function(r), expected, places=12)
        values = [carb.flow_function(0.5 + 0.005 * i) for i in range(101)]
        self.assertTrue(all(b <= a + 1e-15 for a, b in zip(values, values[1:])))

    def test_charge_ratio_known_answers(self) -> None:
        for y, expected in [(0.1, 0.1), (0.3, 0.3), (0.6, 0.594218413575806), (1.0, 0.807458329555176),
                            (2.0, 0.944416909333698), (5.0, 0.990703797849156), (20.0, 0.999414247311794)]:
            self.assertAlmostEqual(carb.charge_ratio(y), expected, places=12)
        r = carb.charge_ratio(1.3)
        self.assertAlmostEqual(r, 1.3 * carb.flow_function(r), places=13)
        self.assertAlmostEqual(carb.demand_ratio_for_charge(r), 1.3, places=11)
        self.assertTrue(math.isnan(carb.charge_ratio(-1.0)))

    def test_lens_and_idle_offset(self) -> None:
        for u, expected in [(0.0, 1.0), (0.25, 0.685037642474293), (0.5, 0.391002218955771),
                            (0.75, 0.144293612814388), (0.9, 0.037386073468499), (1.0, 0.0)]:
            self.assertAlmostEqual(carb.lens_fraction(u), expected, places=12)
        for idle in [0.002, 0.01, 0.05, 0.3, 0.9]:
            self.assertAlmostEqual(carb.lens_fraction(carb.idle_offset(idle)), idle, places=12)
        u = carb.idle_offset(0.01)
        self.assertAlmostEqual(carb.opening(0.0, u), 0.01, places=12)
        self.assertEqual(carb.opening(1.0, u), 1.0)
        self.assertAlmostEqual(carb.opening(0.5, u, 0.5), carb.lens_fraction(u * math.sqrt(0.5)), places=15)
        self.assertAlmostEqual(carb.opening(0.0, u, 0.5), 0.01, places=12)
        self.assertTrue(math.isnan(carb.opening(0.5, u, 0.0)))

    def test_admission_limits(self) -> None:
        capacity = carb.capacity_m3_s(2.03e-5)
        self.assertAlmostEqual(capacity, 2.03e-5 * carb.PSI_CHOKED * math.sqrt(carb.R_AIR * carb.T_REFERENCE_K), places=18)
        displacement = 9.95e-6
        for rpm in [1000.0, 5000.0, 12000.0]:
            self.assertEqual(carb.admission(1.0, rpm, 0.9, displacement, 1.0, capacity), 1.0)
        self.assertEqual(carb.admission(0.01, 0.0, 0.9, displacement, 1.0, capacity), 1.0)
        low = carb.admission(0.01, 3000.0, 0.6, displacement, 1.0, capacity)
        high = carb.admission(0.01, 9000.0, 0.6, displacement, 1.0, capacity)
        x_low = carb.demand_m3_s(3000.0, 0.6, displacement, 1.0) / capacity
        x_high = carb.demand_m3_s(9000.0, 0.6, displacement, 1.0) / capacity
        self.assertAlmostEqual(low / high, 3.0 * carb.charge_ratio(1.0 / x_high) / carb.charge_ratio(1.0 / x_low), places=12)
        self.assertAlmostEqual(carb.demand_m3_s(6000.0, 0.8, 1.0e-5, 2.0), 0.5 * 1.0e-5 * 0.8 * 100.0, places=18)

    def test_sample_table(self) -> None:
        table = [[0.0, 0.45], [2000.0, 0.55], [4000.0, 0.66]]
        self.assertEqual(carb.sample_table(table, -1.0), 0.45)
        self.assertAlmostEqual(carb.sample_table(table, 1000.0), 0.5, places=15)
        self.assertEqual(carb.sample_table(table, 9000.0), 0.66)


if __name__ == "__main__":
    unittest.main()
