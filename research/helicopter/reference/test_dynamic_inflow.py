"""Independent numerical checks for the dimensional dynamic-inflow reference."""

from __future__ import annotations

import json
import math
from pathlib import Path
import subprocess
import sys
import unittest

from dynamic_inflow import derivative, evaluate, lag_time_constant
from johnson_inflow import normalized
import make_dynamic_oracle as oracle


HERE = Path(__file__).resolve().parent
ORACLE_PATH = HERE / "dynamic_oracle.json"


def _fixture(name: str) -> dict:
    return next(item for item in oracle.build_fixtures() if item["name"] == name)


def _max_error_against_dense(
    fixture: dict,
    step_s: float,
    split: bool,
    reference: list[float],
) -> float:
    quarter_step = oracle.BASE_TICK_S / 4.0
    actual = oracle.rk4_trajectory(fixture, step_s, split_events=split)
    stride = round(step_s / quarter_step)
    return max(
        abs(state - reference[index * stride])
        for index, (_, state) in enumerate(actual)
    )


class DimensionalLagLaw(unittest.TestCase):
    def test_zero_rotor_speed_has_finite_residual_wake_decay(self) -> None:
        # Omega is deliberately absent from the dimensional RHS. With zero
        # effective flow, the explicit velocity floor sets a finite tau.
        radius = 0.7
        floor = 0.2
        tau = lag_time_constant(radius, 0.0, floor)
        result = derivative(0.5, 0.0, radius, 0.0, floor)
        self.assertTrue(result["ok"], result)
        self.assertTrue(math.isfinite(float(result["tau_s"])))
        self.assertAlmostEqual(float(result["tau_s"]), tau, places=15)
        self.assertAlmostEqual(float(result["rate_mps2"]), -0.5 / tau, places=14)
        self.assertGreater(tau, 0.0)

        stopped = evaluate(0.5, 0.0, 1.225, radius, 0.0, 0.0, floor)
        self.assertTrue(stopped["ok"], stopped)
        self.assertTrue(math.isfinite(float(stopped["rate_mps2"])))
        self.assertTrue(math.isfinite(float(stopped["tau_s"])))
        self.assertLess(float(stopped["rate_mps2"]), 0.0)

    def test_feedback_effective_flow_is_sign_symmetric(self) -> None:
        positive = evaluate(
            3.0, 80.4, 1.225, 0.7, -1.5, 2.0, 0.25, instability=0.6
        )
        negative = evaluate(
            -3.0, -80.4, 1.225, 0.7, 1.5, 2.0, 0.25, instability=0.6
        )
        self.assertTrue(positive["ok"], positive)
        self.assertTrue(negative["ok"], negative)
        self.assertAlmostEqual(
            float(positive["effective_speed_mps"]),
            float(negative["effective_speed_mps"]),
            places=14,
        )
        self.assertAlmostEqual(float(positive["tau_s"]), float(negative["tau_s"]), places=14)
        self.assertAlmostEqual(
            float(positive["target_mps"]), -float(negative["target_mps"]), places=12
        )
        self.assertAlmostEqual(
            float(positive["rate_mps2"]), -float(negative["rate_mps2"]), places=12
        )

    def test_bad_flow_inputs_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            lag_time_constant(0.7, 0.0, 0.0)
        self.assertFalse(derivative(1.0, 0.0, 0.7, -0.1, 0.25)["ok"])
        self.assertFalse(evaluate(0.0, 80.4, 1.225, 0.7, 0.0, -1.0, 0.25)["ok"])
        self.assertFalse(derivative(math.inf, 0.0, 0.7, 1.0, 0.25)["ok"])


class OracleTrajectories(unittest.TestCase):
    def test_hover_target_step_matches_exact_exponential(self) -> None:
        fixture = _fixture("hover_target_step")
        profile = fixture["profile"]
        constants = fixture["constants"]
        switch_s = float(profile["step_time_s"])
        controls = profile["after"]
        equilibrium = evaluate(
            0.0,
            controls["thrust_n"],
            constants["density_kg_m3"],
            constants["radius_m"],
            controls["climb_mps"],
            controls["crossflow_mps"],
            constants["velocity_floor_mps"],
        )
        self.assertTrue(equilibrium["ok"], equilibrium)
        tau = lag_time_constant(
            constants["radius_m"],
            constants["fixed_effective_speed_mps"],
            constants["velocity_floor_mps"],
        )
        sample_times = [
            index * oracle.SAMPLE_STRIDE_TICKS * oracle.BASE_TICK_S
            for index in range(oracle.SAMPLE_COUNT)
        ]
        states = oracle.dense_trajectory(fixture, sample_times)
        for time_s, state in zip(sample_times, states):
            expected = (
                0.0
                if time_s <= switch_s
                else float(equilibrium["target_mps"])
                * (1.0 - math.exp(-(time_s - switch_s) / tau))
            )
            self.assertAlmostEqual(state, expected, places=13)

        document = json.loads(ORACLE_PATH.read_text(encoding="utf-8"))
        stored = next(item for item in document["fixtures"] if item["name"] == fixture["name"])
        self.assertEqual(len(stored["samples"]), oracle.SAMPLE_COUNT)
        for entry, expected in zip(stored["samples"], states):
            self.assertAlmostEqual(entry["expected_vi_mps"], expected, places=11)
            self.assertAlmostEqual(
                entry["expected_lambda"],
                expected / (constants["omega_rad_s"] * constants["radius_m"]),
                places=11,
            )

        output_times = [index * oracle.BASE_TICK_S for index in range(33)]
        reference = oracle.dense_trajectory(fixture, output_times)
        unsplit = oracle.rk4_trajectory(fixture, oracle.BASE_TICK_S)
        split = oracle.rk4_trajectory(
            fixture, oracle.BASE_TICK_S, split_events=True
        )
        unsplit_error = max(
            abs(actual - expected)
            for (_, actual), expected in zip(unsplit, reference)
        )
        split_error = max(
            abs(actual - expected)
            for (_, actual), expected in zip(split, reference)
        )
        self.assertGreater(unsplit_error, oracle.ERROR_TOLERANCE_MPS)
        self.assertLess(split_error, oracle.ERROR_TOLERANCE_MPS)

        document = json.loads(ORACLE_PATH.read_text(encoding="utf-8"))
        stored_step = next(
            item for item in document["fixtures"] if item["name"] == fixture["name"]
        )
        event = stored_step["event_splits"][0]
        self.assertEqual(event["event_kind"], "forcing_step")
        self.assertEqual(event["time_s"], 0.0173)

    def test_source_law_seams_stay_literal_and_have_one_sided_targets(self) -> None:
        c_left = normalized(-1.428, 0.75 - 1.0e-9, instability=0.0)
        c_right = normalized(-1.428, 0.75 + 1.0e-9, instability=0.0)
        m_left = normalized(-1.3, 0.95 - 1.0e-10, instability=1.0)
        m_right = normalized(-1.3, 0.95 + 1.0e-10, instability=1.0)
        for value in (c_left, c_right, m_left, m_right):
            self.assertTrue(value["ok"], value)
        self.assertAlmostEqual(float(c_left["ratio"]), 1.31603547024, places=10)
        self.assertAlmostEqual(float(c_right["ratio"]), 1.31962823890, places=10)
        self.assertAlmostEqual(float(m_left["ratio"]), 1.14508296835, places=10)
        self.assertAlmostEqual(float(m_right["ratio"]), 1.00539832760, places=10)

        document = json.loads(ORACLE_PATH.read_text(encoding="utf-8"))
        fixture_map = {item["name"]: item for item in document["fixtures"]}
        for name, direction, boundary in (
            ("C_increasing", "increasing", "C"),
            ("C_decreasing", "decreasing", "C"),
            ("M_increasing", "increasing", "M"),
            ("M_decreasing", "decreasing", "M"),
        ):
            event = fixture_map[name]["event_splits"][0]
            self.assertEqual(event["direction"], direction)
            self.assertEqual(event["boundary"], boundary)
            self.assertIn("epsilon_normalized", event)
            self.assertNotEqual(
                event["left_limit_target_mps"], event["right_limit_target_mps"]
            )

    def test_rk4_refinement_and_known_time_splits_are_quantified(self) -> None:
        base = oracle.BASE_TICK_S
        tolerance = oracle.ERROR_TOLERANCE_MPS
        sweep_names = ("C_increasing", "C_decreasing", "M_increasing", "M_decreasing")
        errors: dict[str, dict[str, float]] = {}
        for name in sweep_names:
            fixture = _fixture(name)
            quarter_step = base / 4.0
            reference = oracle.dense_trajectory(
                fixture,
                [
                    index * quarter_step
                    for index in range(round(fixture["duration_s"] / quarter_step) + 1)
                ],
            )
            errors[name] = {
                "h": _max_error_against_dense(fixture, base, False, reference),
                "h2": _max_error_against_dense(fixture, base / 2.0, False, reference),
                "h4": _max_error_against_dense(fixture, base / 4.0, False, reference),
                "split": _max_error_against_dense(fixture, base, True, reference),
            }
            result = errors[name]
            self.assertLess(result["h2"], result["h"])
            self.assertLess(result["h4"], result["h2"])
            self.assertLess(result["split"], result["h"] * 0.2)

        worst_h = max(result["h"] for result in errors.values())
        worst_h4 = max(result["h4"] for result in errors.values())
        worst_split = max(result["split"] for result in errors.values())
        self.assertGreater(worst_h, tolerance)
        self.assertLess(worst_h4, tolerance)
        # Known-time seam splits improve the error substantially but the M
        # decreasing case narrowly misses 1e-3 m/s; keep the gate open.
        self.assertGreater(worst_split, tolerance)
        self.assertLess(worst_split, 1.2e-3)

        feedback = _fixture("feedback_flow_ramp")
        quarter_step = base / 4.0
        reference = oracle.dense_trajectory(
            feedback,
            [
                index * quarter_step
                for index in range(round(feedback["duration_s"] / quarter_step) + 1)
            ],
        )
        feedback_error = _max_error_against_dense(feedback, base, False, reference)
        self.assertLess(feedback_error, tolerance)

    def test_local_quarters_resolve_known_seams_without_relaxing_raw_gate(self) -> None:
        base = oracle.BASE_TICK_S
        tolerance = oracle.ERROR_TOLERANCE_MPS
        sweep_names = ("C_increasing", "C_decreasing", "M_increasing", "M_decreasing")
        worst_local = 0.0
        for name in sweep_names:
            fixture = _fixture(name)
            quarter_step = base / 4.0
            times = [
                index * quarter_step
                for index in range(round(fixture["duration_s"] / quarter_step) + 1)
            ]
            reference = oracle.dense_trajectory(fixture, times)
            actual = oracle.rk4_trajectory(
                fixture, base, split_events=True, local_quarters=True
            )
            stride = round(base / quarter_step)
            error = max(
                abs(state - reference[index * stride])
                for index, (_, state) in enumerate(actual)
            )
            worst_local = max(worst_local, error)
            self.assertLess(error, tolerance, name)

        # Raw 240 Hz RK4 still fails. The local procedure qualifies only when
        # supplied the fixture's exact seam time; it does not imply runtime
        # state-dependent event detection is ready.
        document = json.loads(ORACLE_PATH.read_text(encoding="utf-8"))
        qualification = document["qualification"]
        self.assertFalse(
            qualification["all_integrated_fixtures"]["rk4_240hz_unsplit"][
                "passes_1e-3_mps"
            ]
        )
        self.assertTrue(
            qualification["source_seam_sweeps"]["rk4_240hz_local_quarters"][
                "passes_1e-3_mps"
            ]
        )
        self.assertLessEqual(worst_local, tolerance)

    def test_dense_reference_is_converged_for_worst_seam_and_feedback(self) -> None:
        quarter_step = oracle.BASE_TICK_S / 4.0
        times = [index * quarter_step for index in range(129)]
        for name in ("M_decreasing", "feedback_flow_ramp"):
            with self.subTest(fixture=name):
                fixture = _fixture(name)
                reference = oracle.dense_trajectory(fixture, times, 1.0e-5)
                finer = oracle.dense_trajectory(fixture, times, 5.0e-6)
                self.assertLess(
                    max(abs(a - b) for a, b in zip(reference, finer)), 1.0e-6
                )

    def test_oracle_is_reproducible_and_compact(self) -> None:
        document = json.loads(ORACLE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(document["format"], "openrc-dynamic-inflow-oracle-v1")
        self.assertLessEqual(len(document["fixtures"]), 6)
        self.assertLessEqual(document["sample_count"], 110)
        result = subprocess.run(
            [sys.executable, str(HERE / "make_dynamic_oracle.py"), "--check"],
            cwd=HERE,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

