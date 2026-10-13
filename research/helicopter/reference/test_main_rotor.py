"""Numerical, sign, domain and oracle checks for the HELI-05 rotor reference."""

from __future__ import annotations

import json
import math
from pathlib import Path
import subprocess
import sys
import unittest
from collections.abc import Mapping

from main_rotor import evaluate, prepare
import make_main_rotor_oracle as oracle


HERE = Path(__file__).resolve().parent
ORACLE_PATH = HERE / "main_rotor_oracle.json"


def _oracle_document() -> dict:
    return json.loads(ORACLE_PATH.read_text(encoding="utf-8"))


def _case(name: str) -> dict:
    return next(case for case in _oracle_document()["cases"] if case["name"] == name)


def _inputs(
    *,
    omega: float = 167.0,
    vi: float = 0.0,
    velocity: tuple[float, float, float] = (0.0, 0.0, 0.0),
    rates: tuple[float, float, float] = (0.0, 0.0, 0.0),
    theta: float = 0.0,
    forward: float = 0.0,
    right: float = 0.0,
    a1: float = 0.0,
    b1: float = 0.0,
) -> dict:
    return {
        "omega_rad_s": omega,
        "induced_velocity_m_s": vi,
        "hub_velocity_relative_to_air_body_frd_m_s": list(velocity),
        "body_rates_body_frd_rad_s": list(rates),
        "collective_pitch_75_rad": theta,
        "cyclic_forward_rad": forward,
        "cyclic_right_rad": right,
        "a1_rad": a1,
        "b1_rad": b1,
    }


def _assert_nested_close(test: unittest.TestCase, actual, expected, places: int = 10) -> None:
    if isinstance(expected, Mapping):
        test.assertEqual(set(actual), set(expected))
        for key in expected:
            _assert_nested_close(test, actual[key], expected[key], places)
    elif isinstance(expected, list):
        test.assertEqual(len(actual), len(expected))
        for actual_item, expected_item in zip(actual, expected):
            _assert_nested_close(test, actual_item, expected_item, places)
    elif isinstance(expected, float):
        test.assertAlmostEqual(float(actual), expected, places=places)
    else:
        test.assertEqual(actual, expected)


class MainRotorOracle(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.document = _oracle_document()
        cls.model = prepare(cls.document["parameters"])

    def test_independent_oracle_cases_match_reference(self) -> None:
        self.assertEqual(
            set(self.document), {"format", "parameters", "cases"}
        )
        self.assertEqual(self.document["format"], oracle.FORMAT)
        for case in self.document["cases"]:
            with self.subTest(case=case["name"]):
                self.assertEqual(set(case), {"name", "inputs", "expected"})
                actual = evaluate(self.model, case["inputs"])
                _assert_nested_close(self, actual, case["expected"])

    def test_analytic_lock_and_two_distinct_flap_time_scales(self) -> None:
        # Table 1 values give Lock≈3.71 and bare 16/(Lock Ωnom)≈25.8 ms.
        self.assertAlmostEqual(self.model["lock_number"], 3.71, places=2)
        self.assertAlmostEqual(
            self.model["bare_flap_time_constant_nominal_s"], 0.0258, places=4
        )
        effective_flybar_tau = 16.0 / (
            self.document["parameters"]["gamma_flybar"]
            * self.document["parameters"]["omega_nominal_rad_s"]
        )
        self.assertAlmostEqual(effective_flybar_tau, 0.11976047904191617, places=14)
        self.assertGreater(
            effective_flybar_tau,
            4.0 * self.model["bare_flap_time_constant_nominal_s"],
        )

    def test_hover_collective_closes_independent_weight_anchor(self) -> None:
        output = evaluate(
            self.model, _case("hover_8_2kg_analytic_thrust")["inputs"]
        )
        self.assertAlmostEqual(output["thrust_n"], 8.2 * 9.81, places=10)
        self.assertLess(abs(output["thrust_coefficient"]), self.model["thrust_coefficient_max"])

    def test_profile_drag_anchor_uses_constant_cd0_and_seven_thirds(self) -> None:
        output = evaluate(
            self.model, _case("zero_thrust_profile_torque_7_over_3")["inputs"]
        )
        self.assertAlmostEqual(output["thrust_n"], 0.0, places=10)
        expected_cq = (
            self.model["blade_section_cd0"]
            * output["solidity"]
            / 8.0
            * (1.0 + 7.0 / 3.0 * output["mu"] ** 2)
        )
        self.assertAlmostEqual(output["torque_coefficient"], expected_cq, places=14)
        alternate_465 = (
            self.model["blade_section_cd0"]
            * output["solidity"]
            / 8.0
            * (1.0 + 4.65 * output["mu"] ** 2)
        )
        self.assertNotAlmostEqual(output["torque_coefficient"], alternate_465, places=12)

    def test_hard_thrust_clamp_is_symmetric_and_torque_uses_clamped_ct(self) -> None:
        positive = evaluate(
            self.model, _case("positive_thrust_hard_clamp")["inputs"]
        )
        negative = evaluate(
            self.model, _case("negative_thrust_hard_clamp")["inputs"]
        )
        limit = self.model["thrust_coefficient_max"]
        self.assertGreater(positive["thrust_coefficient_ideal"], limit)
        self.assertLess(negative["thrust_coefficient_ideal"], -limit)
        self.assertEqual(positive["thrust_coefficient"], limit)
        self.assertEqual(negative["thrust_coefficient"], -limit)
        for output in (positive, negative):
            expected_cq = output["thrust_coefficient"] * (
                output["lambda0"] - output["mu_z"]
            ) + self.model["blade_section_cd0"] * output["solidity"] / 8.0 * (
                1.0 + 7.0 / 3.0 * output["mu"] ** 2
            )
            self.assertAlmostEqual(output["torque_coefficient"], expected_cq, places=14)

    def test_cyclic_signs_and_lateral_substitution(self) -> None:
        forward = evaluate(self.model, _inputs(forward=0.02))
        right = evaluate(self.model, _inputs(right=0.02))
        self.assertLess(forward["flap_rate_a1_rad_s"], 0.0)
        self.assertGreater(right["flap_rate_b1_rad_s"], 0.0)

        theta = 0.09
        vi = 3.4
        velocity = (0.0, 8.0, -0.25)
        lateral = evaluate(
            self.model, _inputs(vi=vi, velocity=velocity, theta=theta)
        )
        tip_speed = 167.0 * self.model["rotor_radius_m"]
        lam = vi / tip_speed
        mu_y = velocity[1] / tip_speed
        d_a_d_mu_x = 2.0 * self.model["flapback_k_mu"] * (
            4.0 * theta / 3.0 - lam
        )
        # With u=0, the Eq. 27 derivative is zero; Eq. 26 substitution leaves
        # the positive d_a/d_mu_x * mu_y term in dot(b1).
        tau = 16.0 / (self.model["gamma_flybar"] * 167.0)
        expected_b_rate = d_a_d_mu_x * mu_y / tau
        self.assertAlmostEqual(
            lateral["flap_rate_a1_rad_s"], 0.0, places=14
        )
        self.assertAlmostEqual(
            lateral["flap_rate_b1_rad_s"], expected_b_rate, places=13
        )

    def test_body_rate_terms_are_outside_the_lumped_time_constant(self) -> None:
        output = evaluate(
            self.model,
            _inputs(rates=(0.2, -0.3, 0.0)),
        )
        # Source Eqs. 17–18 use -p/-q directly in rad/s, outside the 1/tau
        # aerodynamic-state bracket.
        self.assertAlmostEqual(output["flap_rate_a1_rad_s"], 0.3, places=14)
        self.assertAlmostEqual(output["flap_rate_b1_rad_s"], -0.2, places=14)

    def test_backward_flow_sign_inference_and_identified_range_flags(self) -> None:
        forward_state = _inputs(
            vi=3.6,
            velocity=(10.0, 0.8, 0.5),
            theta=0.11,
            a1=0.02,
        )
        backward_state = dict(forward_state)
        backward_state["hub_velocity_relative_to_air_body_frd_m_s"] = [
            -10.0,
            0.8,
            0.5,
        ]
        forward = evaluate(self.model, forward_state)
        backward = evaluate(self.model, backward_state)
        self.assertTrue(forward["within_identified_advance_ratio"])
        self.assertTrue(backward["within_identified_advance_ratio"])
        self.assertNotAlmostEqual(
            forward["flap_rate_a1_rad_s"], backward["flap_rate_a1_rad_s"], places=8
        )
        outside = evaluate(
            self.model,
            _case("forward_flow_algebraic_outside_identified_range")["inputs"],
        )
        self.assertFalse(outside["within_identified_advance_ratio"])
        self.assertTrue(outside["rotor_active"])

    def test_flap_angle_flag_does_not_suppress_algebraic_loads(self) -> None:
        output = evaluate(
            self.model,
            _case("flap_angle_beyond_small_angle_range")["inputs"],
        )
        self.assertFalse(output["within_small_flap_angle_range"])
        self.assertTrue(math.isfinite(output["thrust_n"]))
        normal = output["thrust_normal_body_frd"]
        self.assertAlmostEqual(math.sqrt(sum(component**2 for component in normal)), 1.0, places=14)

    def test_force_arm_spring_and_reaction_moments_are_separate(self) -> None:
        output = evaluate(
            self.model,
            _inputs(vi=4.0, theta=0.12, a1=0.04, b1=0.03),
        )
        arm = output["hub_arm_moment_body_frd_nm"]
        spring = output["flap_spring_moment_body_frd_nm"]
        reaction = output["reaction_torque_moment_body_frd_nm"]
        total = output["moment_body_frd_nm"]
        self.assertGreater(spring[0], 0.0)
        self.assertGreater(spring[1], 0.0)
        self.assertAlmostEqual(spring[0], 54.0 * 0.03, places=14)
        self.assertAlmostEqual(spring[1], 54.0 * 0.04, places=14)
        self.assertAlmostEqual(reaction[2], -output["torque_nm"], places=14)
        for index in range(3):
            self.assertAlmostEqual(
                total[index], arm[index] + spring[index] + reaction[index], places=13
            )

    def test_lambda_input_is_explicit_and_matches_dimensional_vi(self) -> None:
        dimensional = _inputs(
            vi=4.2, velocity=(15.0, 2.0, -1.2), theta=0.14, a1=-0.045, b1=0.032
        )
        ratio = dict(dimensional)
        vi = ratio.pop("induced_velocity_m_s")
        ratio["lambda0"] = vi / (ratio["omega_rad_s"] * self.model["rotor_radius_m"])
        dimensional_result = evaluate(self.model, dimensional)
        ratio_result = evaluate(self.model, ratio)
        for key in (
            "thrust_n",
            "torque_nm",
            "flap_rate_a1_rad_s",
            "flap_rate_b1_rad_s",
        ):
            self.assertAlmostEqual(dimensional_result[key], ratio_result[key], places=13)
        self.assertEqual(ratio_result["inflow_input_kind"], "lambda0")

    def test_stopped_rotor_has_no_azimuth_averaged_load_or_conversion(self) -> None:
        stopped = _inputs(omega=0.0, vi=3.0, velocity=(6.0, -2.0, 0.5), a1=0.1, b1=-0.1)
        output = evaluate(self.model, stopped)
        self.assertFalse(output["rotor_active"])
        self.assertIsNone(output["lambda0"])
        self.assertIsNone(output["induced_velocity_m_s"])
        self.assertIsNone(output["effective_flap_time_constant_s"])
        self.assertEqual(output["thrust_n"], 0.0)
        self.assertEqual(output["torque_nm"], 0.0)
        self.assertEqual(output["force_body_frd_n"], (0.0, 0.0, 0.0))
        self.assertEqual(output["moment_body_frd_nm"], (0.0, 0.0, 0.0))
        self.assertEqual(output["flap_rate_a1_rad_s"], 0.0)
        self.assertEqual(output["flap_rate_b1_rad_s"], 0.0)

        lambda_input = dict(stopped)
        lambda_input.pop("induced_velocity_m_s")
        lambda_input["lambda0"] = 0.4
        ratio_result = evaluate(self.model, lambda_input)
        self.assertIsNone(ratio_result["lambda0"])
        self.assertIsNone(ratio_result["induced_velocity_m_s"])
        self.assertEqual(ratio_result["inflow_input_value"], 0.4)


class MainRotorValidation(unittest.TestCase):
    def setUp(self) -> None:
        self.parameters = dict(oracle.PARAMETERS)

    def test_prepare_requires_exact_finite_physical_parameter_domain(self) -> None:
        with self.assertRaises(ValueError):
            prepare({key: value for key, value in self.parameters.items() if key != "rho_kg_m3"})
        unknown = dict(self.parameters, aircraft_default=1.0)
        with self.assertRaises(ValueError):
            prepare(unknown)
        for key, invalid in (
            ("rho_kg_m3", True),
            ("rotor_radius_m", math.nan),
            ("blade_chord_m", -0.1),
            ("blade_section_cd0", -0.01),
            ("thrust_coefficient_max", 0.0),
            ("gamma_flybar", math.inf),
            ("rotor_blade_count", 2.5),
            ("rotation_sense", 0),
        ):
            candidate = dict(self.parameters)
            candidate[key] = invalid
            with self.subTest(key=key), self.assertRaises(ValueError):
                prepare(candidate)
        candidate = dict(self.parameters)
        candidate["hub_position_body_frd_m"] = [0.0, math.inf, 0.0]
        with self.assertRaises(ValueError):
            prepare(candidate)

    def test_evaluate_rejects_malformed_nonfinite_and_out_of_domain_inputs(self) -> None:
        model = prepare(self.parameters)
        base = _inputs()
        malformed = dict(base)
        malformed.pop("induced_velocity_m_s")
        malformed["lambda0"] = 0.0
        malformed["induced_velocity_m_s"] = 0.0
        with self.assertRaises(ValueError):
            evaluate(model, malformed)
        for key, invalid in (
            ("omega_rad_s", -1.0),
            ("omega_rad_s", math.inf),
            ("induced_velocity_m_s", math.nan),
            ("collective_pitch_75_rad", math.pi / 2.0 + 1.0e-8),
            ("cyclic_forward_rad", -math.pi),
            ("a1_rad", math.inf),
        ):
            candidate = dict(base)
            candidate[key] = invalid
            with self.subTest(key=key, value=invalid), self.assertRaises(ValueError):
                evaluate(model, candidate)
        candidate = dict(base)
        candidate["hub_velocity_relative_to_air_body_frd_m_s"] = [math.nan, 0.0, 0.0]
        with self.assertRaises(ValueError):
            evaluate(model, candidate)
        candidate = dict(base)
        candidate["hub_velocity_relative_to_air_body_frd_m_s"] = [
            167.0 * 0.775 * math.sqrt(2.0),
            0.0,
            0.0,
        ]
        with self.assertRaisesRegex(ValueError, "Eq. 27 algebraic domain"):
            evaluate(model, candidate)

    def test_prepared_parameters_are_read_only_and_model_shape_is_checked(self) -> None:
        model = prepare(self.parameters)
        with self.assertRaises(TypeError):
            model["rho_kg_m3"] = 1.0  # type: ignore[index]
        corrupted = dict(model)
        corrupted["lock_number"] += 1.0
        with self.assertRaises(ValueError):
            evaluate(corrupted, _inputs())

    def test_oracle_generator_is_reproducible_and_does_not_import_reference(self) -> None:
        generator_source = (HERE / "make_main_rotor_oracle.py").read_text(encoding="utf-8")
        self.assertNotIn("import main_rotor", generator_source)
        self.assertNotIn("from main_rotor", generator_source)
        completed = subprocess.run(
            [sys.executable, str(HERE / "make_main_rotor_oracle.py"), "--check"],
            cwd=HERE,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)


if __name__ == "__main__":
    unittest.main()
