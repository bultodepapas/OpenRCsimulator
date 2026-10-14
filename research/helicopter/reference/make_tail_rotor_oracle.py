"""Build the independent known-answer oracle for the HELI-06 tail slice.

This file deliberately does not import `tail_rotor.py`. Its equations are a
second implementation used to catch transcription errors in the reference and
native kernels.
"""

from __future__ import annotations

import argparse
import difflib
import json
import math
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
ORACLE_PATH = HERE / "tail_rotor_oracle.json"
FORMAT = "openrc-tail-rotor-oracle-v1"

# Explicit test profile from Gavrilets et al. Table 1 plus the article's
# standard-density test context. eta=.9 is published for the main-rotor Eq. 4;
# applying it to tail trim-slope derivation is an explicit inferred transfer.
PARAMETERS: dict[str, Any] = {
    "rho_kg_m3": 1.225,
    "main_rotor_radius_m": 0.775,
    "tail_rotor_radius_m": 0.13,
    "blade_chord_m": 0.029,
    "rotor_blade_count": 2,
    "blade_lift_curve_slope_per_rad": 5.0,
    "blade_section_cd0": 0.024,
    "thrust_coefficient_max": 0.05,
    "tail_to_main_speed_ratio": 4.66,
    "hub_distance_aft_m": 0.91,
    "hub_height_above_cg_m": 0.08,
    "vertical_fin_area_m2": 0.012,
    "trim_collective_rad": 0.1,
    "wake_efficiency": 0.9,
    "rotation_sense": 1,
}


def _prepare(parameters: dict[str, Any]) -> dict[str, Any]:
    result = dict(parameters)
    radius = parameters["tail_rotor_radius_m"]
    result["solidity"] = (
        parameters["rotor_blade_count"] * parameters["blade_chord_m"]
        / (math.pi * radius)
    )
    result["blockage_factor"] = 1.0 - 0.75 * parameters[
        "vertical_fin_area_m2"
    ] / (math.pi * radius**2)
    result["wake_gi"] = (
        parameters["hub_distance_aft_m"]
        - parameters["main_rotor_radius_m"]
        - radius
    ) / parameters["hub_height_above_cg_m"]
    result["wake_gf"] = (
        parameters["hub_distance_aft_m"]
        - parameters["main_rotor_radius_m"]
        + radius
    ) / parameters["hub_height_above_cg_m"]
    return result


def _wake(model: dict[str, Any], inputs: dict[str, Any]) -> float:
    u, _, w = inputs["cg_air_velocity_body_frd_m_s"]
    denominator = inputs["main_induced_velocity_m_s"] - w
    if inputs["main_induced_velocity_m_s"] <= w or denominator <= 0.0:
        return 0.0
    ratio = u / denominator
    if ratio <= model["wake_gi"]:
        return 0.0
    if ratio >= model["wake_gf"]:
        return 1.5
    return 1.5 * (ratio - model["wake_gi"]) / (
        model["wake_gf"] - model["wake_gi"]
    )


def _trim_and_slopes(
    model: dict[str, Any], advance: float
) -> tuple[float, float, float, float]:
    sigma = model["solidity"]
    lift = model["blade_lift_curve_slope_per_rad"]
    efficiency = model["wake_efficiency"]
    trim = model["trim_collective_rad"]
    mean = 1.0 / 3.0 + 0.5 * advance * advance
    forcing = 0.5 * lift * sigma * trim * mean
    blade_linear = 0.25 * lift * sigma

    def residual(value: float) -> float:
        speed = math.sqrt(advance * advance + value * value)
        return 2.0 * efficiency * value * speed + blade_linear * value - forcing

    lower = 0.0
    upper = 2.0 * trim * mean
    for _ in range(96):
        midpoint = (lower + upper) * 0.5
        if residual(midpoint) > 0.0:
            upper = midpoint
        else:
            lower = midpoint
    lam = (lower + upper) * 0.5
    speed = math.sqrt(advance * advance + lam * lam)
    d_lambda = 2.0 * efficiency * (advance * advance + 2.0 * lam * lam) / speed
    e_lambda = -2.0 * efficiency * lam * lam / speed
    denominator = d_lambda + blade_linear
    trim_ct = 0.5 * lift * sigma * (trim * mean - 0.5 * lam)
    dct_ddelta = 0.5 * lift * sigma * mean * d_lambda / denominator
    dct_dmuz = 0.25 * lift * sigma * (d_lambda + e_lambda) / denominator
    return lam, trim_ct, dct_ddelta, dct_dmuz


def _evaluate(parameters: dict[str, Any], inputs: dict[str, Any]) -> dict[str, Any]:
    model = _prepare(parameters)
    u, v, w = inputs["cg_air_velocity_body_frd_m_s"]
    p, q, r = inputs["body_rates_body_frd_rad_s"]
    ltr = model["hub_distance_aft_m"]
    htr = model["hub_height_above_cg_m"]
    wake = _wake(model, inputs)
    vertical_flow = w + ltr * q - wake * inputs["main_induced_velocity_m_s"]
    in_plane_speed = math.hypot(u, vertical_flow)
    normal_speed = v - ltr * r + htr * p
    main_speed = inputs["omega_main_rad_s"]
    tail_omega_mag = model["tail_to_main_speed_ratio"] * main_speed
    # This output is the positive speed magnitude; rotation_sense is applied
    # only to the shaft reaction moment.
    tail_omega = tail_omega_mag
    tip = tail_omega_mag * model["tail_rotor_radius_m"]

    def stopped_result() -> dict[str, Any]:
        return {
            "tail_omega_rad_s": 0.0,
            "tip_speed_m_s": 0.0,
            "wake_factor": wake,
            "in_plane_velocity_m_s": in_plane_speed,
            "normal_velocity_m_s": normal_speed,
            "advance_ratio": None,
            "normal_flow_ratio": None,
            "trim_lambda": None,
            "trim_ct": None,
            "thrust_collective_slope_per_rad": None,
            "thrust_normal_flow_slope": None,
            "thrust_coefficient_ideal": None,
            "thrust_coefficient": None,
            "torque_coefficient": None,
            "induced_velocity_m_s": 0.0,
            "thrust_n": 0.0,
            "torque_nm": 0.0,
            "blockage_factor": model["blockage_factor"],
            "force_body_frd_n": [0.0, 0.0, 0.0],
            "moment_body_frd_nm": [0.0, 0.0, 0.0],
            "loads": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            "rotor_active": False,
            "thrust_limited": False,
        }

    if main_speed == 0.0:
        return stopped_result()

    advance = in_plane_speed / tip
    normal_ratio = normal_speed / tip
    trim_lambda, trim_ct, slope_delta, slope_normal = _trim_and_slopes(
        model, advance
    )
    mean = 1.0 / 3.0 + 0.5 * advance * advance
    ct_ideal = slope_delta * inputs["tail_collective_rad"] + slope_normal * normal_ratio
    ct = max(-model["thrust_coefficient_max"], min(model["thrust_coefficient_max"], ct_ideal))
    limited = abs(ct_ideal) > model["thrust_coefficient_max"]

    # Source Eq. 50: use capped CT before the blockage multiplier. The linear
    # force law uses actual collective as printed in Eq. 47.
    lam = normal_ratio - 2.0 * (
        2.0 * ct / (model["blade_lift_curve_slope_per_rad"] * model["solidity"])
        - inputs["tail_collective_rad"] * mean
    )
    induced = lam * tip
    radius = model["tail_rotor_radius_m"]
    area = math.pi * radius * radius
    dynamic = model["rho_kg_m3"] * tip * tip * area
    thrust = model["blockage_factor"] * dynamic * ct
    cq = ct * (lam - normal_ratio) + (
        model["blade_section_cd0"] * model["solidity"] / 8.0
    ) * (1.0 + 7.0 * advance * advance / 3.0)
    torque = cq * dynamic * radius
    force = [0.0, -thrust, 0.0]
    moment = [
        -htr * thrust,
        -model["rotation_sense"] * torque,
        ltr * thrust,
    ]
    loads = force + moment
    return {
        "tail_omega_rad_s": tail_omega,
        "tip_speed_m_s": tip,
        "wake_factor": wake,
        "in_plane_velocity_m_s": in_plane_speed,
        "normal_velocity_m_s": normal_speed,
        "advance_ratio": advance,
        "normal_flow_ratio": normal_ratio,
        "trim_lambda": trim_lambda,
        "trim_ct": trim_ct,
        "thrust_collective_slope_per_rad": slope_delta,
        "thrust_normal_flow_slope": slope_normal,
        "thrust_coefficient_ideal": ct_ideal,
        "thrust_coefficient": ct,
        "torque_coefficient": cq,
        "induced_velocity_m_s": induced,
        "thrust_n": thrust,
        "torque_nm": torque,
        "blockage_factor": model["blockage_factor"],
        "force_body_frd_n": force,
        "moment_body_frd_nm": moment,
        "loads": loads,
        "rotor_active": True,
        "thrust_limited": limited,
    }


def _cases() -> list[dict[str, Any]]:
    common = {
        "omega_main_rad_s": 167.0,
        "main_induced_velocity_m_s": 4.2,
    }

    def inputs(
        velocity: tuple[float, float, float],
        rates: tuple[float, float, float] = (0.0, 0.0, 0.0),
        collective: float = 0.075,
        omega: float = 167.0,
        main_vi: float = 4.2,
    ) -> dict[str, Any]:
        return {
            "omega_main_rad_s": omega,
            "main_induced_velocity_m_s": main_vi,
            "cg_air_velocity_body_frd_m_s": list(velocity),
            "body_rates_body_frd_rad_s": list(rates),
            "tail_collective_rad": collective,
        }

    definitions = [
        (
            "hover_small_collective",
            inputs((0.0, 0.0, 0.0), collective=0.075),
            {},
        ),
        (
            "negative_collective_hover",
            inputs((0.0, 0.0, 0.0), collective=-0.04),
            {},
        ),
        (
            "forward_partial_wake_with_body_rates",
            inputs((8.0, 0.4, 0.2), (0.3, -0.15, 0.2), 0.11),
            {},
        ),
        (
            "reverse_translation_outside_wake",
            inputs((-8.0, 0.3, 0.0), collective=0.1),
            {},
        ),
        (
            "full_forward_wake",
            inputs((16.0, 0.0, 0.0), collective=0.1),
            {},
        ),
        (
            "wake_ramp_midpoint",
            inputs((7.0875, 0.0, 0.0), collective=0.1),
            {},
        ),
        (
            "positive_thrust_cap",
            inputs((0.0, 0.0, 0.0), collective=1.0),
            {},
        ),
        (
            "negative_thrust_cap",
            inputs((0.0, 0.0, 0.0), collective=-1.0),
            {},
        ),
        (
            "off_axis_hub_moments",
            inputs((5.0, 0.5, -0.1), (0.2, 0.3, -0.15), 0.12),
            {},
        ),
        (
            "spin_positive",
            inputs((0.0, 0.0, 0.0), collective=0.075),
            {"rotation_sense": 1},
        ),
        (
            "spin_negative",
            inputs((0.0, 0.0, 0.0), collective=0.075),
            {"rotation_sense": -1},
        ),
        (
            "stopped_tail_with_live_wake",
            inputs((3.0, 0.2, 0.0), (0.1, 0.2, -0.1), 0.1, omega=0.0),
            {},
        ),
        (
            "changed_vertical_and_yaw_flow",
            inputs((6.0, -0.7, 1.0), (-0.25, 0.12, 0.35), 0.085),
            {},
        ),
    ]
    result = []
    for name, state, overrides in definitions:
        case_parameters = dict(PARAMETERS)
        case_parameters.update(overrides)
        result.append(
            {
                "name": name,
                "parameter_overrides": overrides,
                "inputs": state,
                "expected": _evaluate(case_parameters, state),
            }
        )
    return result


def _anchors() -> dict[str, Any]:
    # Printed Eqs. 9-10 give the analytic hover slopes with eta=1. They are
    # checks on the derivative algebra, not the eta=.9 test fixture profile.
    parameters = dict(PARAMETERS)
    parameters["wake_efficiency"] = 1.0
    model = _prepare(parameters)
    lam, ct, slope_delta, slope_normal = _trim_and_slopes(model, 0.0)
    sigma = model["solidity"]
    a = model["blade_lift_curve_slope_per_rad"]
    denominator = 16.0 * lam + a * sigma
    return {
        "source": "Gavrilets et al. Eqs. 9-10, hover, eta=1",
        "trim_lambda": lam,
        "trim_ct": ct,
        "thrust_normal_flow_slope": slope_normal,
        "expected_thrust_normal_flow_slope": 2.0 * a * sigma * lam / denominator,
        "thrust_collective_slope_per_rad": slope_delta,
        "expected_thrust_collective_slope_per_rad": (
            (8.0 / 3.0) * a * sigma * lam / denominator
        ),
    }


def build_oracle() -> dict[str, Any]:
    return {
        "format": FORMAT,
        "parameters": PARAMETERS,
        "equation_anchors": _anchors(),
        "cases": _cases(),
    }


def render_oracle() -> str:
    return json.dumps(build_oracle(), indent=2, sort_keys=True, allow_nan=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the checked-in JSON differs from generated output",
    )
    args = parser.parse_args()
    expected = render_oracle()
    if args.check:
        actual = ORACLE_PATH.read_text(encoding="utf-8") if ORACLE_PATH.exists() else ""
        if actual == expected:
            print("tail rotor oracle is current")
            return 0
        print(
            "".join(
                difflib.unified_diff(
                    actual.splitlines(keepends=True),
                    expected.splitlines(keepends=True),
                    fromfile=str(ORACLE_PATH),
                    tofile="generated",
                )
            ),
            end="",
        )
        return 1
    ORACLE_PATH.write_text(expected, encoding="utf-8", newline="\n")
    print(f"wrote {ORACLE_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

