from __future__ import annotations

import json
import math
import subprocess
import sys
import unittest
from pathlib import Path
from typing import Any

from tail_rotor import PARAMETER_KEYS, evaluate, prepare


HERE = Path(__file__).resolve().parent
ORACLE_PATH = HERE / "tail_rotor_oracle.json"
ORACLE = json.loads(ORACLE_PATH.read_text(encoding="utf-8"))


def _case(name: str) -> dict[str, Any]:
    return next(item for item in ORACLE["cases"] if item["name"] == name)


def _inputs(
    *,
    omega: float = 167.0,
    main_vi: float = 4.2,
    velocity: tuple[float, float, float] = (0.0, 0.0, 0.0),
    rates: tuple[float, float, float] = (0.0, 0.0, 0.0),
    collective: float = 0.075,
) -> dict[str, Any]:
    return {
        "omega_main_rad_s": omega,
        "main_induced_velocity_m_s": main_vi,
        "cg_air_velocity_body_frd_m_s": list(velocity),
        "body_rates_body_frd_rad_s": list(rates),
        "tail_collective_rad": collective,
    }


def _assert_tree_close(
    case: unittest.TestCase, actual: Any, expected: Any, path: str = "output"
) -> None:
    if isinstance(expected, dict):
        case.assertIsInstance(actual, dict, path)
        case.assertEqual(set(actual), set(expected), path)
        for key, value in expected.items():
            _assert_tree_close(case, actual[key], value, f"{path}.{key}")
    elif isinstance(expected, list):
        case.assertIsInstance(actual, (tuple, list), path)
        case.assertEqual(len(actual), len(expected), path)
        for index, (got, want) in enumerate(zip(actual, expected)):
            _assert_tree_close(case, got, want, f"{path}[{index}]")
    elif isinstance(expected, float):
        case.assertIsInstance(actual, (int, float), path)
        case.assertTrue(
            math.isclose(float(actual), expected, rel_tol=2.0e-12, abs_tol=2.0e-13),
            f"{path}: {actual!r} != {expected!r}",
        )
    else:
        case.assertEqual(actual, expected, path)


def _source_momentum_ct(
    parameters: dict[str, Any],
    collective: float,
    advance: float,
    normal_flow: float,
) -> float:
    """Independent bisection of source Eqs. 4-5 for derivative checks."""
    lift = parameters["blade_lift_curve_slope_per_rad"]
    sigma = (
        parameters["rotor_blade_count"]
        * parameters["blade_chord_m"]
        / (math.pi * parameters["tail_rotor_radius_m"])
    )
    eta = parameters["wake_efficiency"]
    mean = 1.0 / 3.0 + advance * advance / 2.0

    def blade_ct(lam: float) -> float:
        return lift * sigma / 2.0 * (
            collective * mean + (normal_flow - lam) / 2.0
        )

    def residual(lam: float) -> float:
        return (
            2.0
            * eta
            * lam
            * math.hypot(advance, lam - normal_flow)
            - blade_ct(lam)
        )

    lower = 0.0
    upper = max(1.0, 2.0 * abs(collective) * mean + 2.0 * abs(normal_flow))
    while residual(upper) < 0.0:
        upper *= 2.0
    for _ in range(120):
        midpoint = (lower + upper) * 0.5
        if residual(midpoint) > 0.0:
            upper = midpoint
        else:
            lower = midpoint
    return blade_ct((lower + upper) * 0.5)


class TailRotorOracle(unittest.TestCase):
    def test_all_known_answer_cases_match(self) -> None:
        base_parameters = dict(ORACLE["parameters"])
        for item in ORACLE["cases"]:
            with self.subTest(case=item["name"]):
                parameters = dict(base_parameters)
                parameters.update(item["parameter_overrides"])
                output = evaluate(prepare(parameters), item["inputs"])
                _assert_tree_close(self, output, item["expected"])

    def test_eta_one_hover_matches_printed_analytic_eq_9_and_10(self) -> None:
        parameters = dict(ORACLE["parameters"])
        parameters["wake_efficiency"] = 1.0
        model = prepare(parameters)
        output = evaluate(model, _inputs(velocity=(0.0, 0.0, 0.0)))
        lam = output["trim_lambda"]
        a = parameters["blade_lift_curve_slope_per_rad"]
        sigma = model["solidity"]
        denominator = 16.0 * lam + a * sigma
        expected_normal_slope = 2.0 * a * sigma * lam / denominator
        expected_collective_slope = (8.0 / 3.0) * a * sigma * lam / denominator
        self.assertAlmostEqual(
            output["thrust_normal_flow_slope"], expected_normal_slope, places=14
        )
        self.assertAlmostEqual(
            output["thrust_collective_slope_per_rad"],
            expected_collective_slope,
            places=14,
        )
        anchor = ORACLE["equation_anchors"]
        self.assertAlmostEqual(
            anchor["thrust_normal_flow_slope"],
            anchor["expected_thrust_normal_flow_slope"],
            places=14,
        )
        self.assertAlmostEqual(
            anchor["thrust_collective_slope_per_rad"],
            anchor["expected_thrust_collective_slope_per_rad"],
            places=14,
        )

    def test_implicit_slopes_match_independent_finite_differences(self) -> None:
        parameters = dict(ORACLE["parameters"])
        model = prepare(parameters)
        state = _inputs(velocity=(6.0, 0.0, 0.0), collective=parameters["trim_collective_rad"])
        output = evaluate(model, state)
        advance = output["advance_ratio"]
        delta = parameters["trim_collective_rad"]
        epsilon = 1.0e-5

        plus_delta = _source_momentum_ct(parameters, delta + epsilon, advance, 0.0)
        minus_delta = _source_momentum_ct(parameters, delta - epsilon, advance, 0.0)
        finite_difference_delta = (plus_delta - minus_delta) / (2.0 * epsilon)

        plus_normal = _source_momentum_ct(parameters, delta, advance, epsilon)
        minus_normal = _source_momentum_ct(parameters, delta, advance, -epsilon)
        finite_difference_normal = (plus_normal - minus_normal) / (2.0 * epsilon)

        self.assertAlmostEqual(
            output["thrust_collective_slope_per_rad"],
            finite_difference_delta,
            delta=2.0e-9,
        )
        self.assertAlmostEqual(
            output["thrust_normal_flow_slope"],
            finite_difference_normal,
            delta=2.0e-9,
        )

    def test_wake_ramp_boundaries_and_signed_reverse_speed(self) -> None:
        model = prepare(dict(ORACLE["parameters"]))
        vi = 4.2
        gi = model["wake_gi"]
        gf = model["wake_gf"]
        at_lower = evaluate(
            model, _inputs(velocity=(gi * vi, 0.0, 0.0), main_vi=vi)
        )
        at_middle = evaluate(
            model,
            _inputs(velocity=((gi + gf) * 0.5 * vi, 0.0, 0.0), main_vi=vi),
        )
        at_upper = evaluate(
            model, _inputs(velocity=(gf * vi, 0.0, 0.0), main_vi=vi)
        )
        reverse = evaluate(model, _inputs(velocity=(-8.0, 0.0, 0.0), main_vi=vi))
        no_downwash = evaluate(
            model, _inputs(velocity=(8.0, 0.0, vi), main_vi=vi)
        )
        self.assertEqual(at_lower["wake_factor"], 0.0)
        self.assertAlmostEqual(at_middle["wake_factor"], 0.75, places=14)
        self.assertEqual(at_upper["wake_factor"], 1.5)
        self.assertEqual(reverse["wake_factor"], 0.0)
        self.assertEqual(no_downwash["wake_factor"], 0.0)

    def test_body_rates_use_source_hub_offset_signs(self) -> None:
        parameters = dict(ORACLE["parameters"])
        model = prepare(parameters)
        velocity = (5.0, 0.5, -0.1)
        rates = (0.2, 0.3, -0.15)
        output = evaluate(
            model, _inputs(velocity=velocity, rates=rates, collective=0.12)
        )
        expected_vertical = (
            velocity[2]
            + parameters["hub_distance_aft_m"] * rates[1]
            - output["wake_factor"] * 4.2
        )
        expected_normal = (
            velocity[1]
            - parameters["hub_distance_aft_m"] * rates[2]
            + parameters["hub_height_above_cg_m"] * rates[0]
        )
        self.assertAlmostEqual(
            output["in_plane_velocity_m_s"],
            math.hypot(velocity[0], expected_vertical),
            places=14,
        )
        self.assertAlmostEqual(
            output["normal_velocity_m_s"], expected_normal, places=14
        )
        force = output["force_body_frd_n"]
        hub_moment = (
            -parameters["hub_height_above_cg_m"] * output["thrust_n"],
            0.0,
            parameters["hub_distance_aft_m"] * output["thrust_n"],
        )
        moment = output["moment_body_frd_nm"]
        self.assertAlmostEqual(force[1], -output["thrust_n"], places=14)
        self.assertAlmostEqual(moment[0], hub_moment[0], places=14)
        self.assertAlmostEqual(moment[2], hub_moment[2], places=14)
        self.assertAlmostEqual(
            moment[1], -output["torque_nm"], places=14
        )
        self.assertEqual(
            output["loads"],
            force + moment,
        )

    def test_blockage_and_positive_negative_caps(self) -> None:
        parameters = dict(ORACLE["parameters"])
        model = prepare(parameters)
        expected_blockage = 1.0 - 0.75 * parameters["vertical_fin_area_m2"] / (
            math.pi * parameters["tail_rotor_radius_m"] ** 2
        )
        self.assertAlmostEqual(model["blockage_factor"], expected_blockage, places=14)

        for name, sign in (("positive_thrust_cap", 1.0), ("negative_thrust_cap", -1.0)):
            output = evaluate(model, _case(name)["inputs"])
            with self.subTest(case=name):
                self.assertTrue(output["thrust_limited"])
                self.assertAlmostEqual(
                    output["thrust_coefficient"],
                    sign * parameters["thrust_coefficient_max"],
                    places=14,
                )
                expected_thrust = (
                    output["thrust_coefficient"]
                    * output["blockage_factor"]
                    * parameters["rho_kg_m3"]
                    * output["tip_speed_m_s"] ** 2
                    * math.pi
                    * parameters["tail_rotor_radius_m"] ** 2
                )
                self.assertAlmostEqual(output["thrust_n"], expected_thrust, places=12)

    def test_spin_reflection_changes_only_shaft_reaction_torque(self) -> None:
        positive = evaluate(
            prepare(dict(ORACLE["parameters"])), _case("spin_positive")["inputs"]
        )
        reversed_parameters = dict(ORACLE["parameters"])
        reversed_parameters["rotation_sense"] = -1
        negative = evaluate(
            prepare(reversed_parameters), _case("spin_negative")["inputs"]
        )
        self.assertEqual(positive["tail_omega_rad_s"], negative["tail_omega_rad_s"])
        self.assertEqual(positive["force_body_frd_n"], negative["force_body_frd_n"])
        self.assertAlmostEqual(
            positive["moment_body_frd_nm"][0],
            negative["moment_body_frd_nm"][0],
            places=14,
        )
        self.assertAlmostEqual(
            positive["moment_body_frd_nm"][2],
            negative["moment_body_frd_nm"][2],
            places=14,
        )
        self.assertAlmostEqual(
            positive["moment_body_frd_nm"][1],
            -negative["moment_body_frd_nm"][1],
            places=14,
        )
        self.assertAlmostEqual(positive["torque_nm"], negative["torque_nm"], places=14)

    def test_stopped_tail_has_zero_loads_and_keeps_wake_diagnostic(self) -> None:
        model = prepare(dict(ORACLE["parameters"]))
        output = evaluate(model, _case("stopped_tail_with_live_wake")["inputs"])
        self.assertFalse(output["rotor_active"])
        self.assertGreater(output["wake_factor"], 0.0)
        for key in (
            "advance_ratio",
            "normal_flow_ratio",
            "trim_lambda",
            "trim_ct",
            "thrust_collective_slope_per_rad",
            "thrust_normal_flow_slope",
            "thrust_coefficient_ideal",
            "thrust_coefficient",
            "torque_coefficient",
        ):
            self.assertIsNone(output[key], key)
        self.assertEqual(output["induced_velocity_m_s"], 0.0)
        self.assertEqual(output["loads"], (0.0, 0.0, 0.0, 0.0, 0.0, 0.0))


class TailRotorValidation(unittest.TestCase):
    def setUp(self) -> None:
        self.parameters = dict(ORACLE["parameters"])
        self.inputs = _inputs()

    def test_prepare_requires_complete_finite_physical_parameters(self) -> None:
        missing = dict(self.parameters)
        missing.pop("wake_efficiency")
        with self.assertRaises(ValueError):
            prepare(missing)
        unknown = dict(self.parameters, hidden_aircraft_default=1.0)
        with self.assertRaises(ValueError):
            prepare(unknown)
        self.assertEqual(set(self.parameters), PARAMETER_KEYS)
        for key, invalid in (
            ("rho_kg_m3", True),
            ("tail_rotor_radius_m", math.nan),
            ("blade_chord_m", -0.02),
            ("blade_section_cd0", -0.01),
            ("thrust_coefficient_max", 0.0),
            ("tail_to_main_speed_ratio", math.inf),
            ("hub_height_above_cg_m", 0.0),
            ("vertical_fin_area_m2", 1.0),
            ("trim_collective_rad", -0.1),
            ("trim_collective_rad", math.pi / 2.0 + 1.0e-8),
            ("wake_efficiency", 1.01),
            ("rotor_blade_count", 3),
            ("rotation_sense", 0),
        ):
            candidate = dict(self.parameters)
            candidate[key] = invalid
            with self.subTest(key=key), self.assertRaises(ValueError):
                prepare(candidate)
        low_solidity_profile = dict(self.parameters)
        low_solidity_profile["blade_chord_m"] = 1.0
        with self.assertRaisesRegex(ValueError, r"solidity must be in \(0, 1\)"):
            prepare(low_solidity_profile)

    def test_evaluate_rejects_invalid_model_and_inputs(self) -> None:
        model = prepare(self.parameters)
        malformed = dict(self.inputs)
        malformed.pop("tail_collective_rad")
        with self.assertRaises(ValueError):
            evaluate(model, malformed)
        extra = dict(self.inputs, unmodeled_default=1.0)
        with self.assertRaises(ValueError):
            evaluate(model, extra)
        for key, invalid in (
            ("omega_main_rad_s", -1.0),
            ("omega_main_rad_s", math.inf),
            ("main_induced_velocity_m_s", math.nan),
            ("tail_collective_rad", math.inf),
            ("tail_collective_rad", math.pi / 2.0 + 1.0e-8),
        ):
            candidate = dict(self.inputs)
            candidate[key] = invalid
            with self.subTest(key=key), self.assertRaises(ValueError):
                evaluate(model, candidate)
        candidate = dict(self.inputs)
        candidate["body_rates_body_frd_rad_s"] = [0.0, math.nan, 0.0]
        with self.assertRaises(ValueError):
            evaluate(model, candidate)
        for velocity in ((1.0e9, 0.0, 0.0), (0.0, 1.0e9, 0.0)):
            candidate = _inputs(velocity=velocity)
            with self.subTest(velocity=velocity), self.assertRaisesRegex(
                ValueError, "numerical guard"
            ):
                evaluate(model, candidate)
        corrupted = dict(model)
        corrupted["blockage_factor"] = 1.0
        with self.assertRaises(ValueError):
            evaluate(corrupted, self.inputs)
        corrupted = dict(model)
        corrupted["law"] = "different-tail-law"
        with self.assertRaises(ValueError):
            evaluate(corrupted, self.inputs)

    def test_prepared_model_is_read_only_and_unsaturated_trim_is_required(self) -> None:
        model = prepare(self.parameters)
        with self.assertRaises(TypeError):
            model["rho_kg_m3"] = 1.0  # type: ignore[index]
        saturated = dict(self.parameters)
        saturated["trim_collective_rad"] = 1.5
        saturated_model = prepare(saturated)
        with self.assertRaisesRegex(ValueError, "trim thrust coefficient reaches the cap"):
            evaluate(saturated_model, self.inputs)

    def test_oracle_generator_is_independent_and_reproducible(self) -> None:
        source = (HERE / "make_tail_rotor_oracle.py").read_text(encoding="utf-8")
        self.assertNotIn("import tail_rotor", source)
        self.assertNotIn("from tail_rotor", source)
        completed = subprocess.run(
            [sys.executable, str(HERE / "make_tail_rotor_oracle.py"), "--check"],
            cwd=HERE,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)

    def test_trim_bracket_scales_before_residual_gate(self) -> None:
        parameters = dict(self.parameters)
        parameters["blade_lift_curve_slope_per_rad"] = 1.0e-100
        model = prepare(parameters)
        tip = 167.0 * parameters["tail_to_main_speed_ratio"] * parameters["tail_rotor_radius_m"]
        for mu in (0.0, 0.1, 0.5):
            output = evaluate(model, _inputs(main_vi=0.0, velocity=(mu * tip, 0.0, 0.0)))
            lam = output["trim_lambda"]
            momentum_ct = 2.0 * parameters["wake_efficiency"] * lam * math.hypot(mu, lam)
            blade_ct = parameters["blade_lift_curve_slope_per_rad"] * model["solidity"] / 2.0 * (
                parameters["trim_collective_rad"] * (1.0 / 3.0 + mu * mu / 2.0) - lam / 2.0)
            self.assertGreater(lam, 0.0)
            self.assertLess(abs(momentum_ct - blade_ct) / blade_ct, 1.0e-12)


if __name__ == "__main__":
    unittest.main()

