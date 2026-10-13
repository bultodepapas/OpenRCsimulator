#!/usr/bin/env python3
"""Independent standard-library reference and deterministic Godot oracle vectors."""

from __future__ import annotations

import argparse
import json
import math
import random
from pathlib import Path
from typing import Any


ORACLE_SCHEMA = "openrc-glow-kernel-oracle-v1"
RANDOM_SEED = 20261013
OUTPUT_FIELDS = (
    "indicated_torque_nm",
    "mechanical_torque_nm",
    "pumping_torque_nm",
    "valve_torque_nm",
    "shaft_torque_nm",
    "delivered_fuel_kg_s",
    "burned_fuel_kg_s",
    "unburned_fuel_kg_s",
    "fuel_input_power_w",
    "chemical_power_w",
    "indicated_power_w",
    "mechanical_loss_w",
    "pumping_loss_w",
    "valve_loss_w",
    "cycle_work_j",
    "air_charge_kg_cycle",
    "cycle_frequency_hz",
    "opportunity_frequency_hz",
    "firing_frequency_hz",
)


def _empty(message: str) -> dict[str, Any]:
    return {"ok": False, "message": message, **{key: 0.0 for key in OUTPUT_FIELDS}}


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _scalar(parameters: dict[str, Any], key: str, lower: float, lower_inclusive: bool,
            upper: float, upper_inclusive: bool) -> float:
    if key not in parameters:
        raise ValueError(f"{key} is required")
    raw = parameters[key]
    if not _is_number(raw):
        raise ValueError(f"{key} must be numeric")
    value = float(raw)
    if not math.isfinite(value):
        raise ValueError(f"{key} must be finite")
    if (value < lower if lower_inclusive else value <= lower):
        raise ValueError(f"{key} is below its allowed range")
    if (value > upper if upper_inclusive else value >= upper):
        raise ValueError(f"{key} is above its allowed range")
    return value


def _sample(parameters: dict[str, Any], key: str, query: float, lower_y: float,
            lower_inclusive: bool, upper_y: float, upper_inclusive: bool) -> float:
    if key not in parameters:
        raise ValueError(f"{key} is required")
    table = parameters[key]
    if not isinstance(table, list) or len(table) < 4 or len(table) % 2:
        raise ValueError(f"{key} must contain at least two x/y pairs")
    pairs: list[tuple[float, float]] = []
    previous_x = -1.0
    for index in range(0, len(table), 2):
        raw_x, raw_y = table[index], table[index + 1]
        if not _is_number(raw_x) or not _is_number(raw_y):
            raise ValueError(f"{key} knots must be numeric")
        x, y = float(raw_x), float(raw_y)
        if not math.isfinite(x) or x < 0.0:
            raise ValueError(f"{key} x values must be finite and nonnegative")
        if index and x <= previous_x:
            raise ValueError(f"{key} x values must increase strictly")
        if not math.isfinite(y):
            raise ValueError(f"{key} y values must be finite")
        if (y < lower_y if lower_inclusive else y <= lower_y):
            raise ValueError(f"{key} y value is below its allowed range")
        if (y > upper_y if upper_inclusive else y >= upper_y):
            raise ValueError(f"{key} y value is above its allowed range")
        pairs.append((x, y))
        previous_x = x
    if not math.isfinite(query) or query < 0.0:
        raise ValueError(f"{key} query must be finite and nonnegative")
    if query < pairs[0][0] or query > pairs[-1][0]:
        raise ValueError(f"{key} does not cover the query")
    for (x0, y0), (x1, y1) in zip(pairs, pairs[1:]):
        if query <= x1:
            portion = (query - x0) / (x1 - x0)
            return y0 + (y1 - y0) * portion
    return pairs[-1][1]


def _validate_inputs(rpm: float, admission: float, mixture: float,
                     density: float, firing_fraction: float) -> tuple[float, ...]:
    values = (rpm, admission, mixture, density, firing_fraction)
    if any(not _is_number(value) or not math.isfinite(float(value)) for value in values):
        raise ValueError("operating inputs must be finite numbers")
    rpm, admission, mixture, density, firing_fraction = map(float, values)
    if rpm < 0.0:
        raise ValueError("rpm must be finite and nonnegative")
    if not 0.0 <= admission <= 1.0:
        raise ValueError("admission must be finite and in [0, 1]")
    if mixture < 0.0:
        raise ValueError("mixture must be finite and nonnegative")
    if density <= 0.0:
        raise ValueError("dry_density_kg_m3 must be finite and positive")
    if not 0.0 <= firing_fraction <= 1.0:
        raise ValueError("firing_fraction must be finite and in [0, 1]")
    return rpm, admission, mixture, density, firing_fraction


def _common_parameters(parameters: dict[str, Any]) -> tuple[float, float, float, float]:
    if not isinstance(parameters, dict):
        raise ValueError("parameters must be an object")
    displacement = _scalar(parameters, "displacement_m3", 0.0, False, math.inf, True)
    oil_fraction = _scalar(parameters, "oil_fraction", 0.0, True, 1.0, False)
    afr = _scalar(parameters, "stoich_air_fuel_ratio", 0.0, False, math.inf, True)
    lhv = _scalar(parameters, "fuel_lhv_j_kg", 0.0, False, math.inf, True)
    return displacement, oil_fraction, afr, lhv


def _finish(result: dict[str, Any]) -> dict[str, Any]:
    if any(not math.isfinite(float(result[key])) for key in OUTPUT_FIELDS):
        return _empty("calculation produced a nonfinite output")
    result["ok"] = True
    result["message"] = ""
    return result


def two_stroke(rpm: float, admission: float, mixture: float, dry_density_kg_m3: float,
               parameters: dict[str, Any], running: bool = True,
               firing_fraction: float = 1.0) -> dict[str, Any]:
    """Reference the two-stroke kernel equations using scalar math only."""
    try:
        rpm, admission, mixture, density, firing_fraction = _validate_inputs(
            rpm, admission, mixture, dry_density_kg_m3, firing_fraction
        )
        displacement, oil_fraction, afr, lhv = _common_parameters(parameters)
        delivery = _sample(parameters, "delivery_ratio", rpm, 0.0, True, math.inf, True)
        trapping = _sample(parameters, "trapping_efficiency", rpm, 0.0, True, 1.0, True)
        scavenge_pressure = _sample(parameters, "scavenge_pressure_pa", rpm, 0.0, True, math.inf, True)
        mechanical_table = parameters
        mechanical = _sample(mechanical_table, "mechanical_torque_nm", rpm, 0.0, True, math.inf, True)
        combustion_efficiency = _sample(parameters, "combustion_efficiency", mixture, 0.0, True, 1.0, True)
        indicated_efficiency = _sample(parameters, "indicated_efficiency", rpm, 0.0, True, 1.0, True)
    except (TypeError, ValueError, OverflowError) as exc:
        return _empty(str(exc))

    cycle_hz = rpm / 60.0
    opportunity_hz = cycle_hz
    omega = 2.0 * math.pi * rpm / 60.0
    delivered_air_cycle = density * displacement * admission * delivery
    air_charge_cycle = delivered_air_cycle * trapping
    indicated_torque = 0.0
    mechanical_torque = mechanical if rpm > 0.0 else 0.0
    pumping_torque = (
        scavenge_pressure * displacement * delivery * admission / (2.0 * math.pi)
        if rpm > 0.0 else 0.0
    )
    delivered_fuel = burned_fuel = fuel_input_power = chemical_power = 0.0
    indicated_power = cycle_work = firing_hz = 0.0

    if running and rpm > 0.0:
        gross_premix_cycle = delivered_air_cycle * mixture / afr / (1.0 - oil_fraction)
        gross_combustible_cycle = gross_premix_cycle * (1.0 - oil_fraction)
        combustible_trapped_cycle = gross_combustible_cycle * trapping
        oxygen_limited_cycle = air_charge_cycle / afr
        burned_cycle = min(combustible_trapped_cycle, oxygen_limited_cycle)
        burned_cycle *= combustion_efficiency * firing_fraction
        delivered_fuel = gross_premix_cycle * opportunity_hz
        burned_fuel = burned_cycle * opportunity_hz
        if burned_cycle > 0.0:
            firing_hz = opportunity_hz * firing_fraction
        fuel_input_power = gross_combustible_cycle * opportunity_hz * lhv
        chemical_power = burned_fuel * lhv
        cycle_work = burned_cycle * lhv * indicated_efficiency
        indicated_torque = cycle_work / (2.0 * math.pi)
        indicated_power = indicated_torque * omega

    result = {
        "ok": False,
        "message": "",
        "indicated_torque_nm": indicated_torque,
        "mechanical_torque_nm": mechanical_torque,
        "pumping_torque_nm": pumping_torque,
        "valve_torque_nm": 0.0,
        "shaft_torque_nm": indicated_torque - mechanical_torque - pumping_torque,
        "delivered_fuel_kg_s": delivered_fuel,
        "burned_fuel_kg_s": burned_fuel,
        "unburned_fuel_kg_s": delivered_fuel - burned_fuel,
        "fuel_input_power_w": fuel_input_power,
        "chemical_power_w": chemical_power,
        "indicated_power_w": indicated_power,
        "mechanical_loss_w": mechanical_torque * omega,
        "pumping_loss_w": pumping_torque * omega,
        "valve_loss_w": 0.0,
        "cycle_work_j": cycle_work,
        "air_charge_kg_cycle": air_charge_cycle,
        "cycle_frequency_hz": cycle_hz,
        "opportunity_frequency_hz": opportunity_hz,
        "firing_frequency_hz": firing_hz,
    }
    return _finish(result)


def four_stroke(rpm: float, admission: float, mixture: float, dry_density_kg_m3: float,
                parameters: dict[str, Any], running: bool = True,
                firing_fraction: float = 1.0) -> dict[str, Any]:
    """Reference the four-stroke kernel equations using scalar math only."""
    try:
        rpm, admission, mixture, density, firing_fraction = _validate_inputs(
            rpm, admission, mixture, dry_density_kg_m3, firing_fraction
        )
        displacement, oil_fraction, afr, lhv = _common_parameters(parameters)
        volumetric_efficiency = _sample(parameters, "volumetric_efficiency", rpm, 0.0, False, math.inf, True)
        intake_drop = _scalar(parameters, "intake_pressure_drop_pa", 0.0, True, math.inf, True)
        mechanical = _sample(parameters, "mechanical_torque_nm", rpm, 0.0, True, math.inf, True)
        combustion_efficiency = _sample(parameters, "combustion_efficiency", mixture, 0.0, True, 1.0, True)
        indicated_efficiency = _sample(parameters, "indicated_efficiency", rpm, 0.0, True, 1.0, True)
        pumping_pressure = _sample(parameters, "pumping_pressure_pa", rpm, 0.0, True, math.inf, True)
        valve = _sample(parameters, "valve_torque_nm", rpm, 0.0, True, math.inf, True)
    except (TypeError, ValueError, OverflowError) as exc:
        return _empty(str(exc))

    cycle_hz = rpm / 120.0
    opportunity_hz = cycle_hz
    omega = 2.0 * math.pi * rpm / 60.0
    air_charge_cycle = density * displacement * admission * volumetric_efficiency
    indicated_torque = 0.0
    mechanical_torque = mechanical if rpm > 0.0 else 0.0
    valve_torque = valve if rpm > 0.0 else 0.0
    pumping_work = (pumping_pressure + intake_drop * (1.0 - admission)) * displacement
    pumping_torque = pumping_work / (4.0 * math.pi) if rpm > 0.0 else 0.0
    delivered_fuel = burned_fuel = fuel_input_power = chemical_power = 0.0
    indicated_power = cycle_work = firing_hz = 0.0

    if running and rpm > 0.0:
        gross_premix_cycle = air_charge_cycle * mixture / afr / (1.0 - oil_fraction)
        gross_combustible_cycle = gross_premix_cycle * (1.0 - oil_fraction)
        stoich_fuel_cycle = air_charge_cycle / afr
        burned_cycle = min(gross_combustible_cycle, stoich_fuel_cycle)
        burned_cycle *= combustion_efficiency * firing_fraction
        delivered_fuel = gross_premix_cycle * opportunity_hz
        burned_fuel = burned_cycle * opportunity_hz
        if burned_cycle > 0.0:
            firing_hz = opportunity_hz * firing_fraction
        fuel_input_power = gross_combustible_cycle * opportunity_hz * lhv
        chemical_power = burned_fuel * lhv
        cycle_work = burned_cycle * lhv * indicated_efficiency
        indicated_torque = cycle_work / (4.0 * math.pi)
        indicated_power = indicated_torque * omega

    result = {
        "ok": False,
        "message": "",
        "indicated_torque_nm": indicated_torque,
        "mechanical_torque_nm": mechanical_torque,
        "pumping_torque_nm": pumping_torque,
        "valve_torque_nm": valve_torque,
        "shaft_torque_nm": indicated_torque - mechanical_torque - pumping_torque - valve_torque,
        "delivered_fuel_kg_s": delivered_fuel,
        "burned_fuel_kg_s": burned_fuel,
        "unburned_fuel_kg_s": delivered_fuel - burned_fuel,
        "fuel_input_power_w": fuel_input_power,
        "chemical_power_w": chemical_power,
        "indicated_power_w": indicated_power,
        "mechanical_loss_w": mechanical_torque * omega,
        "pumping_loss_w": pumping_torque * omega,
        "valve_loss_w": valve_torque * omega,
        "cycle_work_j": cycle_work,
        "air_charge_kg_cycle": air_charge_cycle,
        "cycle_frequency_hz": cycle_hz,
        "opportunity_frequency_hz": opportunity_hz,
        "firing_frequency_hz": firing_hz,
    }
    return _finish(result)


def _flat_table(*pairs: tuple[float, float]) -> list[float]:
    return [coordinate for pair in pairs for coordinate in pair]


def _two_parameters() -> dict[str, Any]:
    return {
        "displacement_m3": 1.0e-5,
        "oil_fraction": 0.1,
        "stoich_air_fuel_ratio": 10.0,
        "fuel_lhv_j_kg": 1.0e6,
        "mechanical_torque_nm": _flat_table((0.0, 0.01), (12000.0, 0.01)),
        "combustion_efficiency": _flat_table((0.0, 0.8), (2.0, 0.8)),
        "indicated_efficiency": _flat_table((0.0, 0.5), (12000.0, 0.5)),
        "delivery_ratio": _flat_table((0.0, 2.0), (12000.0, 2.0)),
        "trapping_efficiency": _flat_table((0.0, 0.5), (12000.0, 0.5)),
        "scavenge_pressure_pa": _flat_table((0.0, 1000.0), (12000.0, 1000.0)),
    }


def _four_parameters() -> dict[str, Any]:
    return {
        "displacement_m3": 1.0e-4,
        "oil_fraction": 0.1,
        "stoich_air_fuel_ratio": 10.0,
        "fuel_lhv_j_kg": 1000.0,
        "mechanical_torque_nm": _flat_table((0.0, 0.01), (12000.0, 0.01)),
        "combustion_efficiency": _flat_table((0.0, 0.5), (2.0, 0.5)),
        "indicated_efficiency": _flat_table((0.0, 0.25), (12000.0, 0.25)),
        "volumetric_efficiency": _flat_table((0.0, 1.0), (12000.0, 1.0)),
        "pumping_pressure_pa": _flat_table((0.0, 100.0), (12000.0, 100.0)),
        "intake_pressure_drop_pa": 50.0,
        "valve_torque_nm": _flat_table((0.0, 0.001), (12000.0, 0.001)),
    }


def _case(identifier: str, family: str, rpm: float, admission: float, mixture: float,
          density: float, parameters: dict[str, Any], running: bool = True,
          firing_fraction: float = 1.0) -> dict[str, Any]:
    function = two_stroke if family == "two_stroke" else four_stroke
    result = function(rpm, admission, mixture, density, parameters, running, firing_fraction)
    return {
        "id": identifier,
        "family": family,
        "rpm": rpm,
        "admission": admission,
        "mixture": mixture,
        "dry_density_kg_m3": density,
        "running": running,
        "firing_fraction": firing_fraction,
        "parameters": parameters,
        "expected": result,
    }


def _random_parameters(rng: random.Random, family: str) -> dict[str, Any]:
    rpm_knots = (0.0, 6000.0, 12000.0)
    mixture_knots = (0.0, 1.0, 2.0)
    parameters: dict[str, Any] = {
        "displacement_m3": rng.uniform(1.0e-5, 1.0e-4),
        "oil_fraction": rng.uniform(0.04, 0.22),
        "stoich_air_fuel_ratio": rng.uniform(8.0, 14.0),
        "fuel_lhv_j_kg": rng.uniform(1.0e6, 4.3e7),
        "mechanical_torque_nm": _flat_table(
            *((x, rng.uniform(0.001, 0.04)) for x in rpm_knots)
        ),
        "combustion_efficiency": _flat_table(
            *((x, rng.uniform(0.05, 0.95)) for x in mixture_knots)
        ),
        "indicated_efficiency": _flat_table(
            *((x, rng.uniform(0.12, 0.48)) for x in rpm_knots)
        ),
    }
    if family == "two_stroke":
        parameters.update({
            "delivery_ratio": _flat_table(
                *((x, rng.uniform(0.7, 2.8)) for x in rpm_knots)
            ),
            "trapping_efficiency": _flat_table(
                *((x, rng.uniform(0.18, 0.92)) for x in rpm_knots)
            ),
            "scavenge_pressure_pa": _flat_table(
                *((x, rng.uniform(200.0, 1600.0)) for x in rpm_knots)
            ),
        })
    else:
        parameters.update({
            "volumetric_efficiency": _flat_table(
                *((x, rng.uniform(0.55, 1.25)) for x in rpm_knots)
            ),
            "pumping_pressure_pa": _flat_table(
                *((x, rng.uniform(40.0, 500.0)) for x in rpm_knots)
            ),
            "intake_pressure_drop_pa": rng.uniform(0.0, 180.0),
            "valve_torque_nm": _flat_table(
                *((x, rng.uniform(0.0, 0.01)) for x in rpm_knots)
            ),
        })
    return parameters


def build_cases() -> list[dict[str, Any]]:
    """Return analytic, boundary, loss-separation, and seeded randomized vectors."""
    cases = [
        _case("two_stroke_analytic", "two_stroke", 6000.0, 0.5, 0.8, 1.0, _two_parameters()),
        _case("four_stroke_analytic", "four_stroke", 6000.0, 0.8, 1.0, 1.0, _four_parameters(), firing_fraction=0.5),
        _case("two_stroke_stopped", "two_stroke", 0.0, 0.5, 0.8, 1.0, _two_parameters()),
        _case("four_stroke_stopped", "four_stroke", 0.0, 0.8, 1.0, 1.0, _four_parameters()),
        _case("two_stroke_cut", "two_stroke", 6000.0, 0.5, 0.8, 1.0, _two_parameters(), running=False),
        _case("four_stroke_cut", "four_stroke", 6000.0, 0.8, 1.0, 1.0, _four_parameters(), running=False),
        _case("two_stroke_zero_admission", "two_stroke", 6000.0, 0.0, 0.8, 1.0, _two_parameters()),
        _case("four_stroke_zero_admission", "four_stroke", 6000.0, 0.0, 1.0, 1.0, _four_parameters()),
        _case("two_stroke_zero_mixture", "two_stroke", 6000.0, 0.5, 0.0, 1.0, _two_parameters()),
        _case("four_stroke_zero_mixture", "four_stroke", 6000.0, 0.8, 0.0, 1.0, _four_parameters()),
        _case("two_stroke_zero_completion", "two_stroke", 6000.0, 0.5, 0.8, 1.0,
              {**_two_parameters(), "combustion_efficiency": _flat_table((0.0, 0.0), (2.0, 0.0))}),
        _case("four_stroke_zero_completion", "four_stroke", 6000.0, 0.8, 1.0, 1.0,
              {**_four_parameters(), "combustion_efficiency": _flat_table((0.0, 0.0), (2.0, 0.0))}),
        _case("two_stroke_lower_bound", "two_stroke", 0.0, 0.2, 0.0, 0.9, _two_parameters()),
        _case("two_stroke_upper_bound", "two_stroke", 12000.0, 0.9, 2.0, 1.2, _two_parameters()),
        _case("four_stroke_lower_bound", "four_stroke", 0.0, 0.2, 0.0, 0.9, _four_parameters()),
        _case("four_stroke_upper_bound", "four_stroke", 12000.0, 0.9, 2.0, 1.2, _four_parameters()),
        _case("two_stroke_port_loss", "two_stroke", 6000.0, 0.75, 0.8, 1.1,
              {**_two_parameters(), "scavenge_pressure_pa": _flat_table((0.0, 600.0), (12000.0, 600.0))}),
        _case("four_stroke_valve_and_pump_loss", "four_stroke", 6000.0, 0.75, 1.0, 1.1,
              {**_four_parameters(),
               "pumping_pressure_pa": _flat_table((0.0, 130.0), (12000.0, 130.0)),
               "intake_pressure_drop_pa": 40.0,
               "valve_torque_nm": _flat_table((0.0, 0.003), (12000.0, 0.003))}),
        _case("two_stroke_unsupported_rpm", "two_stroke", 13000.0, 0.5, 0.8, 1.0, _two_parameters()),
        _case("four_stroke_unsupported_mixture", "four_stroke", 6000.0, 0.8, 2.1, 1.0, _four_parameters()),
    ]

    rng = random.Random(RANDOM_SEED)
    for family in ("two_stroke", "four_stroke"):
        for index in range(8):
            parameters = _random_parameters(rng, family)
            rpm = rng.uniform(100.0, 11900.0)
            admission = rng.uniform(0.05, 1.0)
            mixture = rng.uniform(0.0, 2.0)
            density = rng.uniform(0.75, 1.35)
            running = bool(rng.getrandbits(1))
            firing_fraction = rng.uniform(0.0, 1.0)
            cases.append(_case(f"{family}_random_{index:02d}", family, rpm, admission,
                               mixture, density, parameters, running, firing_fraction))
    return cases


def write_oracle(path: Path) -> None:
    document = {
        "schema": ORACLE_SCHEMA,
        "random_seed": RANDOM_SEED,
        "cases": build_cases(),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).with_name("oracle.json"))
    parser.add_argument("--check", action="store_true",
                        help="fail if the committed oracle differs from current deterministic vectors")
    args = parser.parse_args()
    if args.check:
        expected = json.dumps({"schema": ORACLE_SCHEMA, "random_seed": RANDOM_SEED,
                               "cases": build_cases()}, indent=2, allow_nan=False) + "\n"
        actual = args.output.read_text(encoding="utf-8")
        if actual != expected:
            raise SystemExit(f"oracle is stale: {args.output}")
        print(f"{args.output}: {len(build_cases())} vectors current")
    else:
        write_oracle(args.output)
        print(f"wrote {args.output}: {len(build_cases())} vectors")


if __name__ == "__main__":
    main()
