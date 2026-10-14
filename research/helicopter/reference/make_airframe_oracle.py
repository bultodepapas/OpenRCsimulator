"""Build independent known-answer cases for the passive airframe kernel.

The formula implementation here uses only Python's standard library and does
not import `airframe.py`; it can therefore catch shared implementation drift.
"""

from __future__ import annotations

import argparse
import json
from math import copysign, fsum, hypot
from pathlib import Path
from typing import Any, Sequence


ORACLE_PATH = Path(__file__).with_name("airframe_oracle.json")
LAW = "openrc-passive-rotorcraft-airframe-v1"

PARAMETERS: dict[str, Any] = {
    "rho_kg_m3": 1.2,
    "fuselage_drag_area_body_m2": [0.5, 0.8, 0.4],
    "fuselage_cp_body_frd_m": [0.17, -0.03, 0.04],
    "vertical_fin_area_m2": 0.12,
    "vertical_fin_lift_curve_slope_per_rad": 2.2,
    "vertical_fin_cp_body_frd_m": [-1.1, 0.03, -0.08],
    "horizontal_tail_area_m2": 0.16,
    "horizontal_tail_lift_curve_slope_per_rad": 3.1,
    "horizontal_tail_cp_body_frd_m": [-0.85, 0.0, -0.11],
}

ZERO: tuple[float, float, float] = (0.0, 0.0, 0.0)


def add(left: Sequence[float], right: Sequence[float]) -> tuple[float, float, float]:
    return tuple(left[index] + right[index] for index in range(3))  # type: ignore[return-value]


def subtract(left: Sequence[float], right: Sequence[float]) -> tuple[float, float, float]:
    return tuple(left[index] - right[index] for index in range(3))  # type: ignore[return-value]


def cross(left: Sequence[float], right: Sequence[float]) -> tuple[float, float, float]:
    return (
        left[1] * right[2] - left[2] * right[1],
        left[2] * right[0] - left[0] * right[2],
        left[0] * right[1] - left[1] * right[0],
    )


def dot(left: Sequence[float], right: Sequence[float]) -> float:
    return fsum(left[index] * right[index] for index in range(3))


def case_inputs(
    *,
    cg: Sequence[float] = ZERO,
    rates: Sequence[float] = ZERO,
    fuselage_wake: Sequence[float] = ZERO,
    fin_wake: Sequence[float] = ZERO,
    tail_wake: Sequence[float] = ZERO,
) -> dict[str, list[float]]:
    return {
        "cg_air_velocity_body_frd_m_s": list(cg),
        "body_rates_body_frd_rad_s": list(rates),
        "fuselage_wake_velocity_body_frd_m_s": list(fuselage_wake),
        "vertical_fin_wake_velocity_body_frd_m_s": list(fin_wake),
        "horizontal_tail_wake_velocity_body_frd_m_s": list(tail_wake),
    }


def _surface_force(
    kind: str,
    velocity: Sequence[float],
) -> tuple[tuple[float, float, float], float, float, bool]:
    ux, uy, uz = velocity
    rho = PARAMETERS["rho_kg_m3"]
    if kind == "vertical_fin":
        area = PARAMETERS["vertical_fin_area_m2"]
        slope = PARAMETERS["vertical_fin_lift_curve_slope_per_rad"]
        dynamic_area = 0.5 * rho * area
        ideal = -dynamic_area * (slope * hypot(ux, uz) + abs(uy)) * uy
        cap = dynamic_area * dot(velocity, velocity)
        actual = copysign(min(abs(ideal), cap), ideal)
        return (0.0, actual, 0.0), ideal, actual, abs(ideal) > cap

    area = PARAMETERS["horizontal_tail_area_m2"]
    slope = PARAMETERS["horizontal_tail_lift_curve_slope_per_rad"]
    dynamic_area = 0.5 * rho * area
    ideal = -dynamic_area * (slope * abs(ux) + abs(uz)) * uz
    cap = dynamic_area * (ux * ux + uz * uz)
    actual = copysign(min(abs(ideal), cap), ideal)
    return (0.0, 0.0, actual), ideal, actual, abs(ideal) > cap


def calculate(inputs: dict[str, Any]) -> dict[str, Any]:
    cg = inputs["cg_air_velocity_body_frd_m_s"]
    rates = inputs["body_rates_body_frd_rad_s"]
    values: dict[str, dict[str, Any]] = {}

    for prefix in ("fuselage", "vertical_fin", "horizontal_tail"):
        arm = PARAMETERS[f"{prefix}_cp_body_frd_m"]
        wake = inputs[f"{prefix}_wake_velocity_body_frd_m_s"]
        point_velocity = add(cg, cross(rates, arm))
        velocity = subtract(point_velocity, wake)
        if prefix == "fuselage":
            speed = hypot(*velocity)
            force = tuple(
                -0.5
                * PARAMETERS["rho_kg_m3"]
                * PARAMETERS["fuselage_drag_area_body_m2"][axis]
                * velocity[axis]
                * speed
                for axis in range(3)
            )
            metadata: dict[str, Any] = {}
        else:
            force, ideal, actual, limited = _surface_force(prefix, velocity)
            if prefix == "vertical_fin":
                metadata = {
                    "vertical_fin_force_ideal_n": ideal,
                    "vertical_fin_force_n": actual,
                    "vertical_fin_limited": limited,
                }
            else:
                metadata = {
                    "horizontal_tail_force_ideal_n": ideal,
                    "horizontal_tail_force_n": actual,
                    "horizontal_tail_limited": limited,
                }
        moment = cross(arm, force)
        values[prefix] = {
            "relative_air_m_s": velocity,
            "force_body_frd_n": force,
            "moment_body_frd_nm": moment,
            "relative_power_w": dot(force, velocity),
            "body_air_power_w": dot(force, point_velocity),
            "wake_power_w": dot(force, wake),
            "loads": tuple(force) + tuple(moment),
            **metadata,
        }

    output: dict[str, Any] = {}
    fields = (
        "relative_air_m_s",
        "force_body_frd_n",
        "moment_body_frd_nm",
        "relative_power_w",
        "body_air_power_w",
        "wake_power_w",
    )
    for prefix, component in values.items():
        for field in fields:
            output[f"{prefix}_{field}"] = component[field]
        if prefix == "vertical_fin":
            output.update(
                {
                    "vertical_fin_force_ideal_n": component["vertical_fin_force_ideal_n"],
                    "vertical_fin_force_n": component["vertical_fin_force_n"],
                    "vertical_fin_limited": component["vertical_fin_limited"],
                }
            )
        elif prefix == "horizontal_tail":
            output.update(
                {
                    "horizontal_tail_force_ideal_n": component[
                        "horizontal_tail_force_ideal_n"
                    ],
                    "horizontal_tail_force_n": component["horizontal_tail_force_n"],
                    "horizontal_tail_limited": component["horizontal_tail_limited"],
                }
            )
    for prefix in ("fuselage", "vertical_fin", "horizontal_tail"):
        output[f"{prefix}_loads"] = values[prefix]["loads"]
    output["loads"] = tuple(
        fsum(values[prefix]["loads"][index] for prefix in values)
        for index in range(6)
    )
    for field in ("relative_power_w", "body_air_power_w", "wake_power_w"):
        output[field] = fsum(values[prefix][field] for prefix in values)
    return output


CASES = [
    {
        "name": "zero_flow_rest",
        "inputs": case_inputs(),
    },
    {
        "name": "three_axis_fuselage_and_surface_drag",
        "inputs": case_inputs(cg=(3.0, -4.0, 12.0)),
    },
    {
        "name": "pure_yaw_rate_fin_damping",
        "inputs": case_inputs(rates=(0.0, 0.0, 0.6)),
    },
    {
        "name": "pure_pitch_rate_tail_damping",
        "inputs": case_inputs(rates=(0.0, 0.6, 0.0)),
    },
    {
        "name": "vertical_fin_force_cap",
        "inputs": case_inputs(cg=(1.0, 20.0, 0.0)),
    },
    {
        "name": "horizontal_tail_force_cap",
        "inputs": case_inputs(cg=(1.0, 0.0, 20.0)),
    },
    {
        "name": "reverse_surface_force_caps",
        "inputs": case_inputs(cg=(1.0, -20.0, -20.0)),
    },
    {
        "name": "backward_and_reverse_vertical_flow",
        "inputs": case_inputs(cg=(-12.0, -4.0, -5.0)),
    },
    {
        "name": "full_three_axis_body_rate_point_flow",
        "inputs": case_inputs(
            cg=(1.0, 2.0, 3.0),
            rates=(0.2, -0.3, 0.4),
            fuselage_wake=(0.1, -0.2, 0.3),
            fin_wake=(-0.1, 0.2, 0.0),
            tail_wake=(0.0, 0.0, -0.15),
        ),
    },
    {
        "name": "wake_power_transfer_to_body",
        "inputs": case_inputs(
            cg=(0.0, 0.0, 2.0),
            fuselage_wake=(0.0, 0.0, 4.0),
            fin_wake=(0.0, 0.0, 4.0),
            tail_wake=(0.0, 0.0, 4.0),
        ),
    },
]


def build_oracle() -> dict[str, Any]:
    return {
        "format": "openrc-airframe-oracle-v1",
        "law": LAW,
        "parameters": PARAMETERS,
        "cases": [
            {"name": case["name"], "inputs": case["inputs"], "expected": calculate(case["inputs"])}
            for case in CASES
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the checked-in oracle differs from independent regeneration",
    )
    args = parser.parse_args()
    generated = json.dumps(build_oracle(), indent=2, sort_keys=True) + "\n"
    if args.check:
        actual = ORACLE_PATH.read_text(encoding="utf-8") if ORACLE_PATH.exists() else ""
        if actual != generated:
            raise SystemExit(f"{ORACLE_PATH} is stale; regenerate it without --check")
        return 0
    ORACLE_PATH.write_text(generated, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
