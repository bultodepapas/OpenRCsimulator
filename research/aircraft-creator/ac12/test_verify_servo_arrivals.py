"""Independent known answers for the campaign's binary-row metric cross-check."""
import math
import unittest

from verify_servo_arrivals import differences, unambiguous_gate


class MetricOracleTests(unittest.TestCase):
    def row(self):
        row = [0.] * 17
        row[6] = 1.
        return row

    def test_translation_rates_telemetry_and_charge(self):
        a, b = self.row(), self.row()
        b[0:3] = [3., 4., 0.]
        b[10] = math.radians(2.)
        b[13:17] = [.05, 20., .2, 2.]
        a[16] = 1.
        result = differences([tuple(a)] * 1440, [tuple(b)] * 1440)
        self.assertEqual(result["position_m"], 5.)
        self.assertAlmostEqual(result["rates_dps"], 2.)
        self.assertEqual(result["airspeed_mps"], .05)
        self.assertEqual(result["rotor_rpm"], 20.)
        self.assertEqual(result["current_a"], .2)
        self.assertEqual(result["charge_fraction"], .5)

    def test_known_quarter_turn_and_signed_equivalence(self):
        a, b = self.row(), self.row()
        b[6:10] = [math.sqrt(.5), 0., 0., math.sqrt(.5)]
        self.assertAlmostEqual(differences([tuple(a)]*1440, [tuple(b)]*1440)["attitude_deg"], 90.)
        b[6:10] = [-1., 0., 0., 0.]
        self.assertEqual(differences([tuple(a)]*1440, [tuple(b)]*1440)["attitude_deg"], 0.)

    def test_incomplete_grid_cannot_be_compared(self):
        a = [tuple(self.row())] * 1440
        with self.assertRaises(ValueError):
            differences(a, a[:-1])

    def test_floor_disagreement_cannot_produce_a_pass(self):
        with self.assertRaises(ValueError):
            unambiguous_gate("attitude_deg", (.995e-7, 2e-7), (1.001e-7, 2e-7))

    def test_ratio_and_tolerance_boundaries_remain_ambiguous(self):
        for values in ((.001, .00075), (.05, .025)):
            with self.subTest(values=values), self.assertRaises(ValueError):
                unambiguous_gate("position_m", values, values)

    def test_stable_pass_and_failure_keep_registered_verdict(self):
        self.assertTrue(unambiguous_gate("position_m", (.001, .00025), (.001, .00025)))
        self.assertFalse(unambiguous_gate("position_m", (.001, .001), (.001, .001)))
        self.assertFalse(unambiguous_gate("position_m", (.2, .05), (.2, .05)))


if __name__ == "__main__":
    unittest.main()
