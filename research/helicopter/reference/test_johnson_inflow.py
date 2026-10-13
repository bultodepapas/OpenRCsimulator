"""Independent known-answer checks for the Johnson inflow reference."""

from __future__ import annotations

import math
from pathlib import Path
import subprocess
import sys
import unittest

from johnson_inflow import hayden_ground_factor, normalized, target


HERE = Path(__file__).resolve().parent


def _ratio(z: float, x: float = 0.0, **kwargs: float) -> float:
    result = normalized(z, x, **kwargs)
    if not result["ok"]:
        raise AssertionError(result.get("error", "reference failed"))
    return float(result["ratio"])


class MomentumKnownAnswers(unittest.TestCase):
    def test_hover_and_axial_climb_closed_forms(self) -> None:
        # At x=0,z=0, v^2=1. For z=1, v(v+1)=1.
        self.assertAlmostEqual(_ratio(0.0), 1.0, places=13)
        self.assertAlmostEqual(
            _ratio(1.0), (math.sqrt(5.0) - 1.0) / 2.0, places=13
        )

    def test_forward_hover_closed_form(self) -> None:
        # At z=0,x=1: v^2(1+v^2)=1.
        expected = math.sqrt((math.sqrt(5.0) - 1.0) / 2.0)
        self.assertAlmostEqual(_ratio(0.0, 1.0), expected, places=13)

    def test_windmill_branch_is_the_low_momentum_root(self) -> None:
        # For z=-2.5,x=0 on the windmill branch, v*(2.5-v)=1.
        self.assertAlmostEqual(_ratio(-2.5), 0.5, places=13)

    def test_baseline_cubic_satisfies_independent_endpoint_constraints(self) -> None:
        # Table 4 gives A=(-1.5, v=2) on the normal branch and
        # B=(-2.1, v=(2.1-sqrt(2.1^2-4))/2) on the windmill branch.
        z_a, v_a, slope_a = -1.5, 2.0, -0.8
        z_b = -2.1
        v_b = (2.1 - math.sqrt(2.1 * 2.1 - 4.0)) / 2.0

        # Independently form q(z)=p(z)/z, a quadratic. This avoids using the
        # reference's momentum root solver or cubic coefficient routine.
        q_a = v_a / z_a
        q_prime_a = (slope_a - q_a) / z_a
        q_b = v_b / z_b
        q_curve = (q_b - q_a - q_prime_a * (z_b - z_a)) / (z_b - z_a) ** 2
        z = -1.8
        q_z = q_a + q_prime_a * (z - z_a) + q_curve * (z - z_a) ** 2
        expected = z * q_z

        self.assertAlmostEqual(_ratio(z, instability=0.0), expected, places=12)
        self.assertAlmostEqual(_ratio(z_a, instability=0.0), v_a, places=12)
        self.assertAlmostEqual(_ratio(z_b, instability=0.0), v_b, places=12)


class JohnsonTable4KnownAnswers(unittest.TestCase):
    def test_vrs_n_and_x_targets_and_suppression(self) -> None:
        # At x=0 the N and X stability points are unshifted. Table 4 defines
        # z+v=.85 at N and z+v=1.25 at X.
        self.assertAlmostEqual(_ratio(-0.45, instability=0.0), 1.25, places=12)
        self.assertAlmostEqual(_ratio(-0.45, instability=1.0), 1.30, places=12)
        self.assertAlmostEqual(_ratio(-0.45, instability=0.5), 1.275, places=12)
        self.assertAlmostEqual(_ratio(-1.5, instability=0.0), 2.0, places=12)
        self.assertAlmostEqual(_ratio(-1.5, instability=1.0), 2.75, places=12)
        self.assertAlmostEqual(_ratio(-1.5, instability=0.5), 2.375, places=12)

    def test_vrs_is_zero_at_join_points(self) -> None:
        for z in (-0.2, -2.0):
            self.assertAlmostEqual(
                _ratio(z, instability=0.0),
                _ratio(z, instability=1.0),
                places=12,
            )

    def test_loss_factor_multiplies_the_final_induced_velocity(self) -> None:
        self.assertAlmostEqual(
            _ratio(-0.45, instability=1.0, loss=1.2),
            1.3 * 1.2,
            places=12,
        )

    def test_literal_table3_baseline_cutoff_has_a_small_crossflow_jump(self) -> None:
        # The B-to-A cubic is only endpoint-matched before Table 3 switches to
        # momentum theory at C. Pin this source-law seam for integration review.
        z = -1.428
        left = _ratio(z, 0.75 - 1.0e-9, instability=0.0)
        right = _ratio(z, 0.75 + 1.0e-9, instability=0.0)
        self.assertAlmostEqual(left, 1.31603547024, places=10)
        self.assertAlmostEqual(right, 1.31962823890, places=10)
        self.assertAlmostEqual(left - right, -0.00359276866, places=10)

    def test_literal_table3_vrs_outer_limit_has_a_large_jump(self) -> None:
        # At M the VRS increment is disabled. The published boundary slopes
        # do not taper with the increment amplitude, leaving finite outer
        # segment corrections as x approaches M from below.
        cases = (
            (-1.3, 1.14508296835, 1.00539832760),
            (-0.7, 0.89880059144, 1.00289100744),
        )
        for z, left_expected, right_expected in cases:
            with self.subTest(vz=z):
                left = _ratio(z, 0.95 - 1.0e-10)
                right = _ratio(z, 0.95 + 1.0e-10)
                self.assertAlmostEqual(left, left_expected, places=10)
                self.assertAlmostEqual(right, right_expected, places=10)
                self.assertGreater(abs(left - right), 0.1)


class HaydenAndDimensionalTarget(unittest.TestCase):
    def test_hayden_factor_uses_far_field_unity_correction(self) -> None:
        h = 1.0
        expected = 0.9926 / (0.9926 + 0.03794 * (2.0 / h) ** 2)
        self.assertAlmostEqual(hayden_ground_factor(h), expected, places=14)
        self.assertAlmostEqual(hayden_ground_factor(1.0e12), 1.0, places=13)

    def test_ground_height_floor(self) -> None:
        self.assertEqual(hayden_ground_factor(0.0), hayden_ground_factor(0.5))
        self.assertEqual(hayden_ground_factor(0.2), hayden_ground_factor(0.5))

    def test_target_hover_scale_and_ground_factor(self) -> None:
        result = target(100.0, 1.225, 1.0, 0.0, 0.0, height_over_radius=1.0)
        self.assertTrue(result["ok"], result)
        hover = math.sqrt(100.0 / (2.0 * 1.225 * math.pi))
        factor = 0.9926 / (0.9926 + 0.03794 * 4.0)
        self.assertAlmostEqual(float(result["hover"]), hover, places=13)
        self.assertAlmostEqual(float(result["ground_factor"]), factor, places=14)
        self.assertAlmostEqual(float(result["velocity"]), hover * factor, places=12)

    def test_signed_thrust_symmetry_without_ground_effect(self) -> None:
        positive = target(
            80.4, 1.225, 0.7, 3.2, 1.7, height_over_radius=-1.0
        )
        negative = target(
            -80.4, 1.225, 0.7, -3.2, 1.7, height_over_radius=-1.0
        )
        self.assertTrue(positive["ok"], positive)
        self.assertTrue(negative["ok"], negative)
        self.assertAlmostEqual(
            float(positive["velocity"]),
            -float(negative["velocity"]),
            places=12,
        )

    def test_hayden_guard_is_upright_only(self) -> None:
        negative = target(
            -100.0, 1.225, 1.0, 0.0, 0.0, height_over_radius=0.5
        )
        disabled = target(
            -100.0, 1.225, 1.0, 0.0, 0.0, height_over_radius=-1.0
        )
        self.assertTrue(negative["ok"], negative)
        self.assertTrue(disabled["ok"], disabled)
        self.assertEqual(negative["ground_factor"], 1.0)
        self.assertAlmostEqual(negative["velocity"], disabled["velocity"], places=13)


class OracleAndDomain(unittest.TestCase):
    def test_oracle_is_reproducible(self) -> None:
        result = subprocess.run(
            [sys.executable, str(HERE / "make_oracle.py"), "--check"],
            cwd=HERE,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_invalid_model_domain_is_reported(self) -> None:
        self.assertFalse(normalized(0.0, 0.0, instability=1.01)["ok"])
        self.assertFalse(normalized(0.0, 0.0, loss=0.0)["ok"])
        self.assertFalse(target(100.0, -1.0, 1.0, 0.0, 0.0)["ok"])


if __name__ == "__main__":
    unittest.main()
