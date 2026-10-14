"""Standard-library checks for the passive local-flow airframe reference."""

from __future__ import annotations

import copy
import json
import math
import subprocess
import sys
import unittest
from pathlib import Path
from typing import Any

import airframe


HERE = Path(__file__).resolve().parent
ORACLE_PATH = HERE / "airframe_oracle.json"
GENERATOR_PATH = HERE / "make_airframe_oracle.py"


def assert_tree_close(test: unittest.TestCase, actual: Any, expected: Any, path: str) -> None:
    if isinstance(expected, bool) or expected is None or isinstance(expected, str):
        test.assertEqual(actual, expected, path)
    elif isinstance(expected, (int, float)):
        test.assertIsInstance(actual, (int, float), path)
        test.assertTrue(
            math.isclose(float(actual), float(expected), rel_tol=2e-13, abs_tol=2e-13),
            f"{path}: {actual!r} != {expected!r}",
        )
    elif isinstance(expected, (list, tuple)):
        test.assertIsInstance(actual, (list, tuple), path)
        test.assertEqual(len(actual), len(expected), path)
        for index, (actual_item, expected_item) in enumerate(zip(actual, expected)):
            assert_tree_close(test, actual_item, expected_item, f"{path}[{index}]")
    elif isinstance(expected, dict):
        test.assertEqual(set(actual), set(expected), path)
        for key, expected_item in expected.items():
            assert_tree_close(test, actual[key], expected_item, f"{path}.{key}")
    else:
        test.fail(f"unsupported expected oracle value at {path}: {type(expected).__name__}")


class AirframeOracleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.oracle = json.loads(ORACLE_PATH.read_text(encoding="utf-8"))
        cls.model = airframe.prepare(cls.oracle["parameters"])
        cls.cases = {
            case["name"]: case for case in cls.oracle["cases"]
        }

    def evaluate_case(self, name: str) -> dict[str, Any]:
        case = self.cases[name]
        return airframe.evaluate(self.model, case["inputs"])

    def test_independent_oracle_all_cases(self) -> None:
        self.assertEqual(self.oracle["format"], "openrc-airframe-oracle-v1")
        self.assertEqual(self.oracle["law"], airframe.LAW)
        for case in self.oracle["cases"]:
            with self.subTest(case=case["name"]):
                result = airframe.evaluate(self.model, case["inputs"])
                assert_tree_close(self, result, case["expected"], case["name"])

    def test_oracle_is_fresh_from_independent_generator(self) -> None:
        result = subprocess.run(
            [sys.executable, str(GENERATOR_PATH), "--check"],
            cwd=HERE.parents[2],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_prepare_is_flat_read_only_and_detached(self) -> None:
        parameters = copy.deepcopy(self.oracle["parameters"])
        prepared = airframe.prepare(parameters)
        parameters["fuselage_drag_area_body_m2"][0] = 99.0
        parameters["fuselage_cp_body_frd_m"][0] = 99.0
        self.assertEqual(prepared["fuselage_drag_area_body_m2"], (0.5, 0.8, 0.4))
        self.assertEqual(prepared["fuselage_cp_body_frd_m"], (0.17, -0.03, 0.04))
        self.assertEqual(prepared["law"], "openrc-passive-rotorcraft-airframe-v1")
        self.assertEqual(set(prepared), airframe.PARAMETER_KEYS | {"law"})
        with self.assertRaises(TypeError):
            prepared["rho_kg_m3"] = 2.0  # type: ignore[index]
        with self.assertRaises(TypeError):
            prepared["fuselage_drag_area_body_m2"][0] = 2.0  # type: ignore[index]

    def test_prepare_requires_complete_finite_nonnegative_profile(self) -> None:
        parameters = self.oracle["parameters"]
        with self.assertRaises(ValueError):
            airframe.prepare({key: value for key, value in parameters.items() if key != "rho_kg_m3"})
        with self.assertRaises(ValueError):
            airframe.prepare({**parameters, "aircraft_default": True})
        for field, bad_value in (
            ("rho_kg_m3", 0.0),
            ("vertical_fin_area_m2", -0.1),
            ("horizontal_tail_lift_curve_slope_per_rad", -0.1),
            ("fuselage_drag_area_body_m2", [0.1, -0.1, 0.1]),
            ("fuselage_cp_body_frd_m", [0.0, math.inf, 0.0]),
            ("vertical_fin_cp_body_frd_m", [0.0, math.nan, 0.0]),
            ("horizontal_tail_cp_body_frd_m", [0.0, 0.0]),
            ("rho_kg_m3", True),
        ):
            with self.subTest(field=field, bad_value=bad_value):
                with self.assertRaises(ValueError):
                    airframe.prepare({**parameters, field: bad_value})

    def test_evaluate_requires_complete_finite_inputs_and_prepared_model(self) -> None:
        case = self.cases["zero_flow_rest"]
        inputs = case["inputs"]
        with self.assertRaises(ValueError):
            airframe.evaluate(self.model, {key: value for key, value in inputs.items() if key != "body_rates_body_frd_rad_s"})
        with self.assertRaises(ValueError):
            airframe.evaluate(self.model, {**inputs, "unmodeled_wake": [0.0, 0.0, 0.0]})
        bad_inputs = dict(inputs)
        bad_inputs["fuselage_wake_velocity_body_frd_m_s"] = [0.0, math.nan, 0.0]
        with self.assertRaises(ValueError):
            airframe.evaluate(self.model, bad_inputs)
        forged = dict(self.model)
        forged["law"] = "other-law"
        with self.assertRaises(ValueError):
            airframe.evaluate(forged, inputs)
        with self.assertRaises(ValueError):
            airframe.evaluate(dict(self.model), inputs)

    def test_zero_flow_is_zero_load(self) -> None:
        result = self.evaluate_case("zero_flow_rest")
        self.assertEqual(result["loads"], (0.0,) * 6)
        self.assertEqual(result["relative_power_w"], 0.0)
        self.assertEqual(result["body_air_power_w"], 0.0)
        self.assertEqual(result["wake_power_w"], 0.0)

    def test_fuselage_drag_matches_diagonal_quadratic_law(self) -> None:
        result = self.evaluate_case("three_axis_fuselage_and_surface_drag")
        velocity = (3.0, -4.0, 12.0)
        speed = 13.0
        areas = self.oracle["parameters"]["fuselage_drag_area_body_m2"]
        expected = tuple(-0.5 * 1.2 * areas[i] * velocity[i] * speed for i in range(3))
        assert_tree_close(self, result["fuselage_force_body_frd_n"], expected, "fuselage drag")
        self.assertLessEqual(result["fuselage_relative_power_w"], 0.0)

    def test_full_point_velocity_uses_all_three_body_rates(self) -> None:
        result = self.evaluate_case("full_three_axis_body_rate_point_flow")
        expected_fin_relative_air = (1.112, 1.376, 2.676)
        assert_tree_close(
            self,
            result["vertical_fin_relative_air_m_s"],
            expected_fin_relative_air,
            "vertical fin point flow",
        )

    def test_yaw_and_pitch_rates_are_damped_at_offset_surfaces(self) -> None:
        yaw = self.evaluate_case("pure_yaw_rate_fin_damping")
        yaw_rate = self.cases["pure_yaw_rate_fin_damping"]["inputs"]["body_rates_body_frd_rad_s"][2]
        self.assertGreater(yaw["vertical_fin_force_body_frd_n"][1], 0.0)
        self.assertLess(yaw["vertical_fin_moment_body_frd_nm"][2] * yaw_rate, 0.0)

        pitch = self.evaluate_case("pure_pitch_rate_tail_damping")
        pitch_rate = self.cases["pure_pitch_rate_tail_damping"]["inputs"]["body_rates_body_frd_rad_s"][1]
        self.assertLess(pitch["horizontal_tail_force_body_frd_n"][2], 0.0)
        self.assertLess(pitch["horizontal_tail_moment_body_frd_nm"][1] * pitch_rate, 0.0)

    def test_force_caps_preserve_the_ideal_force_sign(self) -> None:
        fin = self.evaluate_case("vertical_fin_force_cap")
        self.assertTrue(fin["vertical_fin_limited"])
        self.assertLess(fin["vertical_fin_force_ideal_n"], 0.0)
        self.assertLess(fin["vertical_fin_force_n"], 0.0)
        self.assertGreater(fin["vertical_fin_force_n"], fin["vertical_fin_force_ideal_n"])
        fin_cap = 0.5 * 1.2 * 0.12 * (1.0**2 + 20.0**2)
        self.assertAlmostEqual(abs(fin["vertical_fin_force_n"]), fin_cap)

        tail = self.evaluate_case("horizontal_tail_force_cap")
        self.assertTrue(tail["horizontal_tail_limited"])
        self.assertLess(tail["horizontal_tail_force_ideal_n"], 0.0)
        self.assertLess(tail["horizontal_tail_force_n"], 0.0)
        self.assertGreater(tail["horizontal_tail_force_n"], tail["horizontal_tail_force_ideal_n"])
        tail_cap = 0.5 * 1.2 * 0.16 * (1.0**2 + 20.0**2)
        self.assertAlmostEqual(abs(tail["horizontal_tail_force_n"]), tail_cap)

        reverse = self.evaluate_case("reverse_surface_force_caps")
        self.assertTrue(reverse["vertical_fin_limited"])
        self.assertTrue(reverse["horizontal_tail_limited"])
        self.assertGreater(reverse["vertical_fin_force_ideal_n"], 0.0)
        self.assertGreater(reverse["vertical_fin_force_n"], 0.0)
        self.assertGreater(reverse["horizontal_tail_force_ideal_n"], 0.0)
        self.assertGreater(reverse["horizontal_tail_force_n"], 0.0)

    def test_backward_flow_force_directions(self) -> None:
        result = self.evaluate_case("backward_and_reverse_vertical_flow")
        self.assertGreater(result["fuselage_force_body_frd_n"][0], 0.0)
        self.assertGreater(result["vertical_fin_force_body_frd_n"][1], 0.0)
        self.assertGreater(result["horizontal_tail_force_body_frd_n"][2], 0.0)

    def test_relative_passivity_and_wake_power_identity(self) -> None:
        for case in self.oracle["cases"]:
            with self.subTest(case=case["name"]):
                result = airframe.evaluate(self.model, case["inputs"])
                for prefix in ("fuselage", "vertical_fin", "horizontal_tail"):
                    self.assertLessEqual(result[f"{prefix}_relative_power_w"], 2e-13)
                    self.assertAlmostEqual(
                        result[f"{prefix}_body_air_power_w"],
                        result[f"{prefix}_relative_power_w"] + result[f"{prefix}_wake_power_w"],
                        delta=2e-12,
                    )
                    force = result[f"{prefix}_force_body_frd_n"]
                    moment = result[f"{prefix}_moment_body_frd_nm"]
                    cg = case["inputs"]["cg_air_velocity_body_frd_m_s"]
                    rates = case["inputs"]["body_rates_body_frd_rad_s"]
                    wrench_power = sum(force[i] * cg[i] + moment[i] * rates[i] for i in range(3))
                    self.assertAlmostEqual(
                        result[f"{prefix}_body_air_power_w"], wrench_power, delta=2e-12
                    )
                self.assertLessEqual(result["relative_power_w"], 2e-13)

        wake = self.evaluate_case("wake_power_transfer_to_body")
        self.assertLess(wake["relative_power_w"], 0.0)
        self.assertGreater(wake["wake_power_w"], 0.0)
        self.assertGreater(wake["body_air_power_w"], 0.0)
        self.assertAlmostEqual(
            wake["body_air_power_w"],
            wake["relative_power_w"] + wake["wake_power_w"],
            delta=2e-12,
        )


if __name__ == "__main__":
    unittest.main()
