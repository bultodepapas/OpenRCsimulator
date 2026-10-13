"""Build the independent known-answer oracle for the HELI-05 rotor slice.

This generator deliberately does not import `main_rotor.py`; its compact
equations are a second implementation used to catch transcription errors.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
ORACLE_PATH = HERE / "main_rotor_oracle.json"
FORMAT = "openrc-main-rotor-oracle-v1"

PARAMETERS: dict[str, Any] = {
    "rho_kg_m3": 1.225,
    "rotor_radius_m": 0.775,
    "blade_chord_m": 0.058,
    "rotor_blade_count": 2,
    "blade_lift_curve_slope_per_rad": 5.5,
    "blade_section_cd0": 0.024,
    "thrust_coefficient_max": 0.0055,
    "blade_flapping_inertia_kg_m2": 0.038,
    "gamma_flybar": 0.8,
    "flapback_k_mu": 0.2,
    "omega_nominal_rad_s": 167.0,
    "cyclic_longitudinal_gain_nominal_rad_per_rad": 4.2,
    "cyclic_lateral_gain_nominal_rad_per_rad": 4.2,
    "hub_spring_stiffness_nm_per_rad": 54.0,
    "hub_position_body_frd_m": [0.0, 0.0, -0.235],
    "rotation_sense": 1,
}


def _base_inputs(
    omega: float,
    vi: float,
    velocity: tuple[float, float, float],
    rates: tuple[float, float, float] = (0.0, 0.0, 0.0),
    theta: float = 0.1,
    forward: float = 0.0,
    right: float = 0.0,
    a1: float = 0.0,
    b1: float = 0.0,
) -> dict[str, Any]:
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


def build_cases() -> list[dict[str, Any]]:
    omega = PARAMETERS["omega_nominal_rad_s"]
    radius = PARAMETERS["rotor_radius_m"]
    omega_radius = omega * radius
    sigma = (
        PARAMETERS["rotor_blade_count"]
        * PARAMETERS["blade_chord_m"]
        / (math.pi * radius)
    )
    lift = PARAMETERS["blade_lift_curve_slope_per_rad"]
    # Independently choose a hover CT that generates 8.2 kg times standard
    # gravity. Invert Eq. 5 to set collective; Eq. 6 is inactive for this case.
    hover_thrust = 8.2 * 9.81
    hover_ct = hover_thrust / (
        PARAMETERS["rho_kg_m3"] * omega_radius**2 * math.pi * radius**2
    )
    hover_vi = 4.2
    hover_lambda = hover_vi / omega_radius
    hover_theta = 3.0 * (hover_ct / (lift * sigma / 2.0) + hover_lambda / 2.0)

    # Set the ideal thrust coefficient to zero in a small cross-flow state;
    # its torque therefore isolates the constant-section profile term.
    profile_vi = 3.1
    profile_mu = 12.0 / omega_radius
    profile_mu_z = -0.5 / omega_radius
    profile_lambda = profile_vi / omega_radius
    profile_theta = ((profile_lambda - profile_mu_z) / 2.0) / (
        1.0 / 3.0 + profile_mu**2 / 2.0
    )

    return [
        {
            "name": "hover_8_2kg_analytic_thrust",
            "inputs": _base_inputs(omega, hover_vi, (0.0, 0.0, 0.0), theta=hover_theta),
        },
        {
            "name": "forward_flight_identified_range",
            "inputs": _base_inputs(
                omega,
                4.2,
                (15.0, 2.0, -1.2),
                rates=(0.11, -0.07, 0.02),
                theta=0.14,
                forward=0.025,
                right=-0.012,
                a1=-0.045,
                b1=0.032,
            ),
        },
        {
            "name": "backward_flow_sign_inference",
            "inputs": _base_inputs(
                omega,
                3.6,
                (-10.0, 0.8, 0.5),
                rates=(-0.04, 0.06, 0.01),
                theta=0.11,
                forward=0.01,
                right=0.015,
                a1=0.02,
                b1=-0.03,
            ),
        },
        {
            "name": "pure_sideflow_zero_axial_gradient",
            "inputs": _base_inputs(
                omega,
                3.4,
                (0.0, 8.0, -0.25),
                rates=(0.02, -0.01, 0.0),
                theta=0.09,
                right=0.02,
                a1=0.01,
                b1=-0.015,
            ),
        },
        {
            "name": "zero_thrust_profile_torque_7_over_3",
            "inputs": _base_inputs(
                omega,
                profile_vi,
                (12.0, 0.0, -0.5),
                theta=profile_theta,
            ),
        },
        {
            "name": "positive_thrust_hard_clamp",
            "inputs": _base_inputs(omega, 3.0, (0.0, 0.0, 0.0), theta=1.0),
        },
        {
            "name": "negative_thrust_hard_clamp",
            "inputs": _base_inputs(omega, 3.0, (0.0, 0.0, 0.0), theta=-1.0),
        },
        {
            "name": "forward_flow_algebraic_outside_identified_range",
            "inputs": _base_inputs(
                omega,
                3.5,
                (35.0, 0.0, 0.0),
                theta=0.13,
                a1=0.02,
            ),
        },
        {
            "name": "flap_angle_beyond_small_angle_range",
            "inputs": _base_inputs(
                omega,
                3.5,
                (4.0, 1.0, 0.0),
                theta=0.12,
                a1=0.2,
                b1=-0.1,
            ),
        },
        {
            "name": "stopped_rotor_inactive_disk_closure",
            "inputs": _base_inputs(
                0.0,
                3.0,
                (6.0, -2.0, 0.5),
                rates=(0.1, -0.1, 0.05),
                theta=0.2,
                forward=0.03,
                right=-0.02,
                a1=0.1,
                b1=-0.1,
            ),
        },
    ]


def _cross(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def independent_expected(inputs: dict[str, Any]) -> dict[str, Any]:
    """A compact duplicate derivation, independent of the reference module."""
    p = PARAMETERS
    omega = inputs["omega_rad_s"]
    vi = inputs["induced_velocity_m_s"]
    theta = inputs["collective_pitch_75_rad"]
    a1 = inputs["a1_rad"]
    b1 = inputs["b1_rad"]
    velocity = tuple(inputs["hub_velocity_relative_to_air_body_frd_m_s"])
    rates = tuple(inputs["body_rates_body_frd_rad_s"])
    sigma = p["rotor_blade_count"] * p["blade_chord_m"] / (math.pi * p["rotor_radius_m"])
    lock = (
        p["rho_kg_m3"]
        * p["blade_chord_m"]
        * p["blade_lift_curve_slope_per_rad"]
        * p["rotor_radius_m"] ** 4
        / p["blade_flapping_inertia_kg_m2"]
    )
    bare_tau = 16.0 / (lock * p["omega_nominal_rad_s"])

    if omega == 0.0:
        zero = (0.0, 0.0, 0.0)
        return {
            "rotor_active": False,
            "theta0_rad": theta,
            "solidity": sigma,
            "lambda0": None,
            "induced_velocity_m_s": None,
            "inflow_input_kind": "induced_velocity_m_s",
            "inflow_input_value": vi,
            "mu_x": None,
            "mu_y": None,
            "mu_z": None,
            "mu": None,
            "within_identified_advance_ratio": False,
            "within_small_flap_angle_range": abs(a1) < math.radians(10)
            and abs(b1) < math.radians(10),
            "lock_number": lock,
            "bare_flap_time_constant_nominal_s": bare_tau,
            "thrust_coefficient_ideal": None,
            "thrust_coefficient": None,
            "thrust_n": 0.0,
            "torque_coefficient": None,
            "torque_nm": 0.0,
            "thrust_normal_body_frd": zero,
            "force_body_frd_n": zero,
            "hub_arm_moment_body_frd_nm": zero,
            "flap_spring_moment_body_frd_nm": zero,
            "reaction_torque_moment_body_frd_nm": zero,
            "moment_body_frd_nm": zero,
            "effective_flap_time_constant_s": None,
            "flap_rate_a1_rad_s": 0.0,
            "flap_rate_b1_rad_s": 0.0,
        }

    radius = p["rotor_radius_m"]
    tip_speed = omega * radius
    lam = vi / tip_speed
    mux, muy, muz = (component / tip_speed for component in velocity)
    mu = math.hypot(mux, muy)
    factor = 1.0 - mu * mu / 2.0
    if factor <= 0.0:
        raise ValueError("fixture outside Eq. 27 domain")
    ct0 = (p["blade_lift_curve_slope_per_rad"] * sigma / 2.0) * (
        theta * (1.0 / 3.0 + mu * mu / 2.0) + (muz - lam) / 2.0
    )
    ct = min(p["thrust_coefficient_max"], max(-p["thrust_coefficient_max"], ct0))
    dynamic = p["rho_kg_m3"] * tip_speed * tip_speed * math.pi * radius * radius
    thrust = ct * dynamic
    cq = ct * (lam - muz) + p["blade_section_cd0"] * sigma / 8.0 * (
        1.0 + 7.0 / 3.0 * mu * mu
    )
    torque = cq * dynamic * radius

    raw_normal = (-math.sin(a1), math.sin(b1), -math.cos(a1) * math.cos(b1))
    norm = math.sqrt(sum(value * value for value in raw_normal))
    normal = tuple(value / norm for value in raw_normal)
    force = tuple(thrust * value for value in normal)
    arm = _cross(tuple(p["hub_position_body_frd_m"]), force)
    spring = (
        p["hub_spring_stiffness_nm_per_rad"] * b1,
        p["hub_spring_stiffness_nm_per_rad"] * a1,
        0.0,
    )
    reaction = (0.0, 0.0, -p["rotation_sense"] * torque)
    moment = tuple(arm[i] + spring[i] + reaction[i] for i in range(3))

    gradient_x = 2.0 * p["flapback_k_mu"] * (4.0 * theta / 3.0 - lam)
    sign_forward = (velocity[0] > 0.0) - (velocity[0] < 0.0)
    gradient_z = (
        p["flapback_k_mu"]
        * 16.0
        * mu**2
        / (factor * (8.0 * mu + p["blade_lift_curve_slope_per_rad"] * sigma))
        * sign_forward
    )
    tau = 16.0 / (p["gamma_flybar"] * omega)
    gain_factor = (omega / p["omega_nominal_rad_s"]) ** 2
    rate_a = (
        -rates[1]
        - a1
        + gradient_x * mux
        + gradient_z * muz
        - p["cyclic_longitudinal_gain_nominal_rad_per_rad"]
        * gain_factor
        * inputs["cyclic_forward_rad"]
    ) / tau
    rate_b = (
        -rates[0]
        - b1
        + gradient_x * muy
        + p["cyclic_lateral_gain_nominal_rad_per_rad"]
        * gain_factor
        * inputs["cyclic_right_rad"]
    ) / tau

    return {
        "rotor_active": True,
        "theta0_rad": theta,
        "solidity": sigma,
        "lambda0": lam,
        "induced_velocity_m_s": vi,
        "inflow_input_kind": "induced_velocity_m_s",
        "inflow_input_value": vi,
        "mu_x": mux,
        "mu_y": muy,
        "mu_z": muz,
        "mu": mu,
        "within_identified_advance_ratio": mu < 0.15,
        "within_small_flap_angle_range": abs(a1) < math.radians(10)
        and abs(b1) < math.radians(10),
        "lock_number": lock,
        "bare_flap_time_constant_nominal_s": bare_tau,
        "thrust_coefficient_ideal": ct0,
        "thrust_coefficient": ct,
        "thrust_n": thrust,
        "torque_coefficient": cq,
        "torque_nm": torque,
        "thrust_normal_body_frd": normal,
        "force_body_frd_n": force,
        "hub_arm_moment_body_frd_nm": arm,
        "flap_spring_moment_body_frd_nm": spring,
        "reaction_torque_moment_body_frd_nm": reaction,
        "moment_body_frd_nm": moment,
        "effective_flap_time_constant_s": tau,
        "flap_rate_a1_rad_s": rate_a,
        "flap_rate_b1_rad_s": rate_b,
    }


def _rounded(value: Any) -> Any:
    if isinstance(value, float):
        result = round(value, 12)
        return 0.0 if result == 0.0 else result
    if isinstance(value, tuple):
        return [_rounded(component) for component in value]
    if isinstance(value, list):
        return [_rounded(component) for component in value]
    if isinstance(value, dict):
        return {key: _rounded(component) for key, component in value.items()}
    return value


def build_oracle() -> dict[str, Any]:
    cases = []
    for spec in build_cases():
        cases.append({
            "name": spec["name"],
            "inputs": spec["inputs"],
            "expected": _rounded(independent_expected(spec["inputs"])),
        })
    return {"format": FORMAT, "parameters": PARAMETERS, "cases": cases}


def render() -> str:
    return json.dumps(build_oracle(), indent=2, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="check the committed oracle without writing")
    args = parser.parse_args()
    expected = render()
    if args.check:
        if not ORACLE_PATH.exists() or ORACLE_PATH.read_text(encoding="utf-8") != expected:
            print(f"oracle check: FAILED ({ORACLE_PATH.name} is stale)")
            return 1
        print(f"oracle check: OK ({ORACLE_PATH.name})")
        return 0
    ORACLE_PATH.write_text(expected, encoding="utf-8", newline="\n")
    print(f"wrote {ORACLE_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
