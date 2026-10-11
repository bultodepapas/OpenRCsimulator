#!/usr/bin/env python3
"""Independent EL2 battery-state and principal-axis rotor qualification."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import subprocess
from importlib.metadata import version
from pathlib import Path

import numpy as np
from scipy.integrate import solve_ivp


PINNED = {"numpy": "1.26.4", "scipy": "1.11.4"}
SAMPLE_HZ = (120, 240, 480, 960)
TAU = 2.0 * math.pi

# Synthetic qualification data only. OCV is one affine segment over the entire
# SOC domain, so these smooth runs do not cross a curve knot.
MOTOR = {
    "kv_rpm_per_volt": 800.0,
    "resistance_ohm": 0.06,
    "no_load_current_a": 1.0,
}
PACK = {
    "capacity_ah": 1.0,
    "resistance_ohm": 0.012,
    "auxiliary_current_a": 0.25,
    "ocv_points": [[0.0, 10.5], [1.0, 12.6]],
}
LOCKED_INERTIA = 0.004
ROTOR_INERTIA = 0.0001
J_CARRIER = LOCKED_INERTIA - ROTOR_INERTIA
DUTY = 0.7
INITIAL_OMEGA = 20.0
INITIAL_SOC = 0.85
SMOOTH_HORIZON_S = 0.5

# A short source-off case makes the event occur inside the final fixed tick at
# all four rates. Its small capacity is deliberate and carries no pack claim.
AUX_EVENT_PACK = {
    "capacity_ah": 0.05,
    "resistance_ohm": 0.004,
    "auxiliary_current_a": 13.0,
    "ocv_points": [[0.0, 10.0], [1.0, 12.6]],
}
AUX_EVENT_INITIAL_SOC = 0.05
AUX_EVENT_RPM = 1500.0

PROBE = Path(__file__).with_name("scalar_probe.gd")
PRODUCTION_PATHS = (
    "physics/electric_battery_step.gd",
    "physics/electric_supply.gd",
    "physics/electric_motor.gd",
    "physics/rotor_coupling.gd",
    "physics/integrator.gd",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def close(actual: float, expected: float, absolute: float, relative: float = 0.0) -> bool:
    return math.isfinite(actual) and abs(actual - expected) <= absolute + relative * abs(expected)


def capacity_c(pack: dict) -> float:
    return float(pack["capacity_ah"]) * 3600.0


def ocv_from_charge(charge_c: float, pack: dict) -> float:
    """Linear OCV(SOC), independently expressed in remaining coulombs."""
    points = pack["ocv_points"]
    (soc_lo, v_lo), (soc_hi, v_hi) = points
    require(soc_lo == 0.0 and soc_hi == 1.0, "oracle fixture must span SOC [0,1]")
    soc = charge_c / capacity_c(pack)
    return v_lo + (v_hi - v_lo) * soc


def chemical_energy_removed(charge_start_c: float, charge_end_c: float, pack: dict) -> float:
    """Exact integral of OCV dQdrawn for a linear full-range OCV curve."""
    c_capacity = capacity_c(pack)
    (soc0, v_low), (soc1, v_high) = pack["ocv_points"]
    require(soc0 == 0.0 and soc1 == 1.0, "chemical integral expects endpoint knots at 0 and 1")
    slope = (v_high - v_low) / c_capacity
    # OCV(C) = Vlow + slope*C; discharge moves from Cstart down to Cend.
    return v_low * (charge_start_c - charge_end_c) \
        + 0.5 * slope * (charge_start_c * charge_start_c - charge_end_c * charge_end_c)


def algebraic_supply(omega: float, charge_c: float, duty: float, pack: dict,
                     enabled: bool = True) -> dict:
    """Scalar statement of EL2a's positive-current solve; no production calls."""
    rpm = omega * 60.0 / TAU
    soc = charge_c / capacity_c(pack)
    ocv = ocv_from_charge(charge_c, pack)
    d = duty if enabled else 0.0
    rp = float(pack["resistance_ohm"])
    iaux = float(pack["auxiliary_current_a"])
    rm = MOTOR["resistance_ohm"]
    kv = MOTOR["kv_rpm_per_volt"]
    back_emf_v = rpm / kv
    denominator = rm + d * d * rp
    numerator = d * (ocv - rp * iaux) - back_emf_v
    motor_current = max(numerator / denominator, 0.0) if d > 0.0 else 0.0
    pack_current = d * motor_current + iaux
    bus_voltage = ocv - rp * pack_current
    kt = 60.0 / (TAU * kv)
    shaft_torque = kt * (motor_current - MOTOR["no_load_current_a"]) if omega > 0.0 else 0.0
    return {
        "soc": soc,
        "ocv_v": ocv,
        "motor_current_a": motor_current,
        "pack_current_a": pack_current,
        "bus_voltage_v": bus_voltage,
        "shaft_torque_nm": shaft_torque,
        "pack_terminal_power_w": bus_voltage * pack_current,
        "pack_heat_rate_w": rp * pack_current * pack_current,
    }


def aux_event_reference() -> dict:
    """Exact source-off, aux-only discharge and final partial fixed tick."""
    initial_charge = AUX_EVENT_INITIAL_SOC * capacity_c(AUX_EVENT_PACK)
    current = AUX_EVENT_PACK["auxiliary_current_a"]
    event_time = initial_charge / current
    chemical_j = chemical_energy_removed(initial_charge, 0.0, AUX_EVENT_PACK)
    heat_j = AUX_EVENT_PACK["resistance_ohm"] * current * current * event_time
    terminal_j = chemical_j - heat_j
    initial_omega = AUX_EVENT_RPM * TAU / 60.0
    kt = 60.0 / (TAU * MOTOR["kv_rpm_per_volt"])
    coupled_factor = LOCKED_INERTIA / (ROTOR_INERTIA * J_CARRIER)
    omega_dot = -kt * MOTOR["no_load_current_a"] * coupled_factor
    final_omega = initial_omega + omega_dot * event_time
    final_body_rate = -ROTOR_INERTIA / LOCKED_INERTIA * (final_omega - initial_omega)
    points = []
    for hz in SAMPLE_HZ:
        ticks = math.ceil(event_time * hz - 1e-13)
        prior_tick_time = (ticks - 1) / hz
        final_tick_dt = event_time - prior_tick_time
        endpoint_time = ticks / hz
        points.append({
            "hz": hz,
            "ticks_to_event": ticks,
            "event_time_s": event_time,
            "fixed_tick_endpoint_s": endpoint_time,
            "final_tick_duration_s": final_tick_dt,
            "final_tick_fraction": final_tick_dt * hz,
            "endpoint_omega_rad_s": initial_omega + omega_dot * endpoint_time,
            "endpoint_body_rate_x_rad_s": -ROTOR_INERTIA / LOCKED_INERTIA
                * (initial_omega + omega_dot * endpoint_time - initial_omega),
        })
    return {
        "initial_charge_c": initial_charge,
        "capacity_c": capacity_c(AUX_EVENT_PACK),
        "initial_soc": AUX_EVENT_INITIAL_SOC,
        "initial_ocv_v": ocv_from_charge(initial_charge, AUX_EVENT_PACK),
        "event_time_s": event_time,
        "initial_omega_rad_s": initial_omega,
        "final_omega_rad_s": final_omega,
        "final_rpm": final_omega * 60.0 / TAU,
        "final_body_rate_x_rad_s": final_body_rate,
        "stop_time_s": initial_omega / (-omega_dot),
        "momentum_x_kg_m2_s": ROTOR_INERTIA * initial_omega,
        "final_charge_c": 0.0,
        "final_soc": 0.0,
        "chemical_energy_removed_j": chemical_j,
        "terminal_energy_j": terminal_j,
        "pack_heat_j": heat_j,
        "energy_balance_residual_j": chemical_j - terminal_j - heat_j,
        "points": points,
        "equation": "Cdot=-Iaux; t*=C0/Iaux; Echem=integral_C*^C0 OCV(C/Ccapacity)dC; H=Rpack*Iaux^2*t*; Eterminal=Echem-H",
    }


def smooth_reference() -> dict:
    """DOP853 solution of independently written scalar motor/rotor/battery ODEs."""
    c_capacity = capacity_c(PACK)
    charge0 = INITIAL_SOC * c_capacity
    kt = 60.0 / (TAU * MOTOR["kv_rpm_per_volt"])
    carrier = J_CARRIER
    factor = LOCKED_INERTIA / (ROTOR_INERTIA * carrier)
    body_ratio = ROTOR_INERTIA / LOCKED_INERTIA

    def rhs(_time_s: float, state: np.ndarray) -> np.ndarray:
        omega, _body_rate, charge, _terminal_energy, _heat, _shaft_work = state
        point = algebraic_supply(float(omega), float(charge), DUTY, PACK, True)
        omega_rate = factor * point["shaft_torque_nm"]
        body_rate = -body_ratio * omega_rate
        return np.asarray([
            omega_rate,
            body_rate,
            -point["pack_current_a"],
            point["pack_terminal_power_w"],
            point["pack_heat_rate_w"],
            point["shaft_torque_nm"] * omega,
        ], dtype=np.float64)

    solve = solve_ivp(
        rhs,
        (0.0, SMOOTH_HORIZON_S),
        [INITIAL_OMEGA, 0.0, charge0, 0.0, 0.0, 0.0],
        method="DOP853",
        rtol=2e-13,
        atol=np.asarray([2e-13, 2e-13, 2e-11, 2e-11, 2e-11, 2e-11]),
        max_step=0.001,
        dense_output=True,
    )
    require(solve.success and solve.status == 0 and solve.t[-1] == SMOOTH_HORIZON_S,
            "independent DOP853 did not reach the smooth endpoint")
    require(np.isfinite(solve.y).all(), "DOP853 returned a nonfinite smooth state")

    sample_times = np.linspace(0.0, SMOOTH_HORIZON_S, 201)
    sample_states = solve.sol(sample_times)
    require(np.isfinite(sample_states).all(), "DOP853 dense solution returned a nonfinite state")
    min_motor_current = math.inf
    min_torque = math.inf
    min_charge = math.inf
    min_soc = math.inf
    for omega, _body_rate, charge, *_rest in sample_states.T:
        point = algebraic_supply(float(omega), float(charge), DUTY, PACK, True)
        min_motor_current = min(min_motor_current, point["motor_current_a"])
        min_torque = min(min_torque, point["shaft_torque_nm"])
        min_charge = min(min_charge, float(charge))
        min_soc = min(min_soc, point["soc"])
    require(min_motor_current > 0.0 and min_torque > 0.0 and min_charge > 0.0,
            "smooth fixture crossed a motor, rotor-stop or battery-exhaustion branch")
    require(0.0 < min_soc < INITIAL_SOC, "smooth fixture left the open SOC interval")

    omega, body_rate, charge, terminal_j, heat_j, shaft_work_j = map(float, solve.y[:, -1])
    chemical_j = chemical_energy_removed(charge0, charge, PACK)
    momentum0 = ROTOR_INERTIA * INITIAL_OMEGA
    momentum = LOCKED_INERTIA * body_rate + ROTOR_INERTIA * omega
    kinetic0 = 0.5 * ROTOR_INERTIA * INITIAL_OMEGA * INITIAL_OMEGA
    kinetic = 0.5 * LOCKED_INERTIA * body_rate * body_rate \
        + ROTOR_INERTIA * body_rate * omega + 0.5 * ROTOR_INERTIA * omega * omega
    return {
        "initial_charge_c": charge0,
        "capacity_c": c_capacity,
        "final_time_s": SMOOTH_HORIZON_S,
        "endpoint": {
            "omega_rad_s": omega,
            "body_rate_x_rad_s": body_rate,
            "remaining_charge_c": charge,
            "soc": charge / c_capacity,
            "terminal_energy_j": terminal_j,
            "pack_heat_j": heat_j,
            "chemical_energy_removed_j": chemical_j,
            "shaft_work_j": shaft_work_j,
            "kinetic_energy_j": kinetic,
            "momentum_x_kg_m2_s": momentum,
        },
        "budgets": {
            "momentum_drift_kg_m2_s": momentum - momentum0,
            "battery_energy_residual_j": chemical_j - terminal_j - heat_j,
            "mechanical_work_residual_j": (kinetic - kinetic0) - shaft_work_j,
        },
        "branch_margins": {
            "minimum_motor_current_a": min_motor_current,
            "minimum_shaft_torque_nm": min_torque,
            "minimum_remaining_charge_c": min_charge,
            "minimum_soc": min_soc,
        },
        "method": "SciPy 1.11.4 DOP853, independently written scalar source, axial rotor and pack equations",
        "rhs": [
            "Im=max((d*(OCV(C/Ccap)-Rpack*Iaux)-rpm/Kv)/(Rm+d^2*Rpack),0)",
            "Ipack=d*Im+Iaux; Vbus=OCV-Rpack*Ipack",
            "Qsource=kt*(Im-I0); Omegadot=Jlocked/(Jrotor*Jcarrier)*Qsource",
            "body_rate_dot=-(Jrotor/Jlocked)*Omegadot from constant axial H",
            "Cdot=-Ipack; Eterminal_dot=Vbus*Ipack; Hpack_dot=Rpack*Ipack^2",
        ],
        "solver_evaluations": int(solve.nfev),
        "solver_rtol": 2e-13,
        "solver_atol": [2e-13, 2e-13, 2e-11, 2e-11, 2e-11, 2e-11],
        "solver_max_step_s": 0.001,
        "dense_branch_check_points": int(sample_times.size),
    }


def fixture_payload() -> dict:
    return {
        "motor": MOTOR,
        "smooth_pack": PACK,
        "smooth_duty": DUTY,
        "smooth_initial_soc": INITIAL_SOC,
        "smooth_initial_omega_rad_s": INITIAL_OMEGA,
        "smooth_horizon_s": SMOOTH_HORIZON_S,
        "locked_inertia_kg_m2": LOCKED_INERTIA,
        "relative_rotor_inertia_kg_m2": ROTOR_INERTIA,
        "carrier_inertia_kg_m2": J_CARRIER,
        "aux_event_pack": AUX_EVENT_PACK,
        "aux_event_initial_soc": AUX_EVENT_INITIAL_SOC,
        "aux_event_rpm": AUX_EVENT_RPM,
        "axis_body": [1.0, 0.0, 0.0],
        "rates_hz": list(SAMPLE_HZ),
    }


def fixture_matches(observed: dict) -> None:
    def matches(actual: object, expected: object) -> bool:
        if isinstance(expected, bool):
            return actual is expected
        if isinstance(expected, (int, float)) and not isinstance(expected, bool):
            return isinstance(actual, (int, float)) and not isinstance(actual, bool) \
                and close(float(actual), float(expected), 1e-15)
        if isinstance(expected, dict):
            return isinstance(actual, dict) and actual.keys() == expected.keys() \
                and all(matches(actual[key], value) for key, value in expected.items())
        if isinstance(expected, list):
            return isinstance(actual, list) and len(actual) == len(expected) \
                and all(matches(a, e) for a, e in zip(actual, expected))
        return actual == expected

    require(matches(observed, fixture_payload()),
            "Godot probe fixture differs from the pinned independent fixture")


def check_auxiliary_only(raw: list[dict], reference: dict) -> dict:
    require([point.get("hz") for point in raw] == list(SAMPLE_HZ), "aux-only rates changed")
    checked = []
    expected_by_rate = {point["hz"]: point for point in reference["points"]}
    for point in raw:
        hz = point["hz"]
        expected = expected_by_rate[hz]
        require(point.get("ok") is True, f"aux-only fixture failed at {hz} Hz")
        require(point.get("event_count") == 1, f"exhaustion should fire exactly once at {hz} Hz")
        require(point.get("event_kind") == "battery_exhausted", f"wrong event identity at {hz} Hz")
        require(point.get("source_enabled") is False, "aux-only fixture must keep the motor source off")
        require(point.get("ticks_to_event") == expected["ticks_to_event"],
                f"wrong exhaustion tick count at {hz} Hz")
        require(close(float(point["event_time_s"]), reference["event_time_s"], 2e-12),
                f"exhaustion time error at {hz} Hz")
        require(float(point["event_time_error_bound_s"]) <= 1e-12,
                f"event locator did not report a bounded time bracket at {hz} Hz")
        require(abs(float(point["event_charge_residual_c"])) <= 1e-10,
                f"event locator did not report a bounded charge residual at {hz} Hz")
        require(close(float(point["final_time_s"]), expected["fixed_tick_endpoint_s"], 2e-12),
                f"accepted state missed the fixed tick endpoint at {hz} Hz")
        require(close(float(point["final_tick_duration_s"]), expected["final_tick_duration_s"], 2e-12),
                f"wrong final partial tick at {hz} Hz")
        require(0.0 < float(point["final_tick_fraction"]) < 1.0,
                f"fixture did not exercise an interior final tick at {hz} Hz")
        require(abs(float(point["remaining_charge_c"])) <= 2e-12,
                f"remaining charge did not project to zero at {hz} Hz")
        require(abs(float(point["soc"])) <= 2e-15, f"SOC did not reach zero at {hz} Hz")
        endpoint_rpm = expected["endpoint_omega_rad_s"] * 60.0 / TAU
        require(close(float(point["final_rpm"]), endpoint_rpm, 2e-8),
                f"source-off bearing-loss RPM error at the fixed tick endpoint at {hz} Hz")
        require(close(float(point["final_body_rate_x_rad_s"]),
                      expected["endpoint_body_rate_x_rad_s"], 2e-10),
                f"source-off body-rate error at the fixed tick endpoint at {hz} Hz")
        momentum_error = float(point["momentum_x_kg_m2_s"]) - reference["momentum_x_kg_m2_s"]
        require(abs(momentum_error) <= 1e-12, f"source-off rotor/body momentum drift at {hz} Hz")
        require(float(point["final_rpm"]) > 0.0 and reference["stop_time_s"] > reference["event_time_s"],
                f"source-off rotor stopped before the battery event at {hz} Hz")
        require(close(float(point["terminal_energy_j"]), reference["terminal_energy_j"], 2e-9),
                f"terminal energy error at {hz} Hz")
        require(close(float(point["pack_heat_j"]), reference["pack_heat_j"], 2e-10),
                f"pack heat error at {hz} Hz")
        require(abs(float(point["battery_energy_residual_j"])) <= 2e-9,
                f"aux-only chemical/terminal/heat budget does not close at {hz} Hz")
        require(abs(float(point["post_event_pack_current_a"])) <= 1e-14,
                f"exhausted pack still supplies current at {hz} Hz")
        require(abs(float(point["post_event_motor_current_a"])) <= 1e-14,
                f"exhausted pack still supplies motor current at {hz} Hz")
        kt = 60.0 / (TAU * MOTOR["kv_rpm_per_volt"])
        require(close(float(point["post_event_shaft_torque_nm"]),
                      -kt * MOTOR["no_load_current_a"], 2e-14),
                f"source-off bearing loss disappeared after exhaustion at {hz} Hz")
        require(close(float(point["post_event_remaining_charge_c"]), 0.0, 2e-12),
                f"post-event charge changed at {hz} Hz")
        require(close(float(point["post_event_terminal_energy_j"]), reference["terminal_energy_j"], 2e-9),
                f"exhausted pack added terminal energy after the event at {hz} Hz")
        require(close(float(point["post_event_pack_heat_j"]), reference["pack_heat_j"], 2e-10),
                f"exhausted pack added ohmic heat after the event at {hz} Hz")
        checked.append({
            "hz": hz,
            "ticks_to_event": expected["ticks_to_event"],
            "event_time_error_s": float(point["event_time_s"]) - reference["event_time_s"],
            "event_time_error_bound_s": float(point["event_time_error_bound_s"]),
            "event_charge_residual_c": float(point["event_charge_residual_c"]),
            "fixed_tick_endpoint_s": float(point["final_time_s"]),
            "final_tick_duration_s": float(point["final_tick_duration_s"]),
            "final_tick_fraction": float(point["final_tick_fraction"]),
            "final_rpm_error": float(point["final_rpm"]) - endpoint_rpm,
            "body_rate_error_rad_s": float(point["final_body_rate_x_rad_s"])
                - reference["final_body_rate_x_rad_s"],
            "momentum_drift_kg_m2_s": momentum_error,
            "terminal_energy_error_j": float(point["terminal_energy_j"]) - reference["terminal_energy_j"],
            "pack_heat_error_j": float(point["pack_heat_j"]) - reference["pack_heat_j"],
            "battery_energy_residual_j": float(point["battery_energy_residual_j"]),
            "event_count": point["event_count"],
        })
    return {"points": checked, "expected": reference}


def check_smooth(raw: list[dict], reference: dict) -> dict:
    require([point.get("hz") for point in raw] == list(SAMPLE_HZ), "smooth rates changed")
    expected = reference["endpoint"]
    budgets = {
        "omega_rad_s": ("final_omega_rad_s", 2e-3),
        "body_rate_x_rad_s": ("final_body_rate_x_rad_s", 5e-5),
        "remaining_charge_c": ("remaining_charge_c", 2e-3),
        "soc": ("soc", 1e-6),
        "terminal_energy_j": ("terminal_energy_j", 2e-3),
        "pack_heat_j": ("pack_heat_j", 2e-3),
    }
    checks = []
    state_errors: dict[str, list[float]] = {name: [] for name in budgets}
    for point in raw:
        hz = point["hz"]
        require(point.get("ok") is True, f"smooth fixture failed at {hz} Hz")
        require(point.get("steps") == int(round(SMOOTH_HORIZON_S * hz)),
                f"smooth integration step count changed at {hz} Hz")
        require(close(float(point["final_time_s"]), SMOOTH_HORIZON_S, 2e-14),
                f"smooth run did not reach the requested endpoint at {hz} Hz")
        require(point.get("exhaustion_events") == 0, f"unexpected battery exhaustion at {hz} Hz")
        require(point.get("stop_events") == 0, f"unexpected rotor stop at {hz} Hz")
        require(point.get("motor_current_positive_throughout") is True,
                f"smooth fixture left the positive-current branch at {hz} Hz")
        require(point.get("ocv_knot_crossings") == 0, f"smooth fixture crossed an OCV knot at {hz} Hz")
        for label, (observed_key, tolerance) in budgets.items():
            actual = float(point[observed_key])
            error = actual - expected[label]
            state_errors[label].append(abs(error))
            require(abs(error) <= tolerance,
                    f"{label} error {error:g} exceeds {tolerance:g} at {hz} Hz")
        expected_momentum = ROTOR_INERTIA * INITIAL_OMEGA
        momentum_error = float(point["momentum_x_kg_m2_s"]) - expected_momentum
        require(abs(momentum_error) <= 1e-12, f"axial angular momentum drift at {hz} Hz")
        chemical = chemical_energy_removed(reference["initial_charge_c"],
                                           float(point["remaining_charge_c"]), PACK)
        battery_residual = chemical - float(point["terminal_energy_j"]) - float(point["pack_heat_j"])
        require(abs(battery_residual) <= 2e-5, f"chemical/terminal/heat budget does not close at {hz} Hz")
        checks.append({
            "hz": hz,
            "steps": point["steps"],
            "final_time_s": point["final_time_s"],
            "reference_error": {
                label: float(point[key]) - expected[label]
                for label, (key, _limit) in budgets.items()
            },
            "absolute_momentum_drift_kg_m2_s": momentum_error,
            "chemical_energy_residual_j": battery_residual,
        })
    # Report refinement orders as diagnostics. The accepted criterion is each
    # state-specific error budget; OCV-knot cases must not inherit a global RK4 order claim.
    orders: dict[str, list[float | None]] = {}
    for label, errors in state_errors.items():
        values: list[float | None] = []
        for coarse, fine in zip(errors, errors[1:]):
            values.append(math.log(coarse / fine, 2.0) if coarse > 0.0 and fine > 0.0 else None)
        orders[label] = values
    return {
        "points": checks,
        "absolute_error_budgets": {label: spec[1] for label, spec in budgets.items()},
        "observed_orders_diagnostic_only": orders,
        "expected": reference,
    }


def run_godot(godot_path: Path, app_path: Path, timeout: float) -> dict:
    command = [str(godot_path.resolve()), "--headless", "--path", str(app_path.resolve()),
               "--audio-driver", "Dummy", "--script", str(PROBE.resolve())]
    process = subprocess.run(command, text=True, capture_output=True, timeout=timeout)
    log = process.stdout + process.stderr
    require(process.returncode == 0, f"Godot probe exited {process.returncode}:\n{log}")
    require(not re.search(r"^(?:SCRIPT |SHADER )?ERROR:", log, re.M), f"Godot logged an error:\n{log}")
    lines = [line[len("EL2_BATTERY_JSON:"):] for line in log.splitlines()
             if line.startswith("EL2_BATTERY_JSON:")]
    require(len(lines) == 1, f"expected one EL2_BATTERY_JSON record, got {len(lines)}")
    return json.loads(lines[0])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--oracle-only", action="store_true",
                        help="write the independent references without launching Godot")
    args = parser.parse_args()
    versions = {name: version(name) for name in PINNED}
    require(versions == PINNED, f"use the pinned research environment {PINNED}, observed {versions}")
    aux_reference = aux_event_reference()
    smooth = smooth_reference()
    if args.oracle_only:
        output = args.output or Path("/tmp/openrc-el2-oracle-reference.json")
        payload = {
            "format": "openrc-el2a-independent-reference-v1",
            "fixture": fixture_payload(),
            "auxiliary_only": aux_reference,
            "smooth": smooth,
            "python_versions": versions,
        }
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(payload, indent=2, allow_nan=False) + "\n")
        print(json.dumps({"ok": True, "oracle_only": True, "output": str(output.resolve()),
                          "aux_event_time_s": aux_reference["event_time_s"],
                          "smooth_endpoint": smooth["endpoint"],
                          "smooth_budgets": smooth["budgets"]}))
        return
    require(args.godot is not None and args.app is not None and args.output is not None,
            "--godot, --app and --output are required unless --oracle-only is set")
    raw = run_godot(args.godot, args.app, args.timeout)
    fixture_matches(raw["fixture"])
    aux_checks = check_auxiliary_only(raw["auxiliary_only"], aux_reference)
    smooth_checks = check_smooth(raw["smooth"], smooth)
    app_path = args.app.resolve()
    source_hashes = {path: hashlib.sha256((app_path / path).read_bytes()).hexdigest()
                     for path in PRODUCTION_PATHS}
    evidence = {
        "format": "openrc-el2a-battery-evidence-v1",
        "status": "synthetic numerical qualification; no aircraft or pack calibration",
        "godot": subprocess.check_output([str(args.godot.resolve()), "--version"], text=True).strip(),
        "python_versions": versions,
        "fixture": raw["fixture"],
        "independent_reference": {"auxiliary_only": aux_reference, "smooth": smooth},
        "checks": {"auxiliary_only": aux_checks, "smooth": smooth_checks},
        "independence": {
            "expected_values": "closed-form linear-OCV charge/energy oracle and SciPy DOP853 scalar equations",
            "production_observation": "Godot EL2 battery event step and coupled principal-axis rotor trajectory",
            "production_sha256": source_hashes,
            "probe_sha256": hashlib.sha256(PROBE.read_bytes()).hexdigest(),
            "verifier_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        },
        "limitations": [
            "Synthetic single-segment OCV and direct-drive motor parameters; no measured pack or motor claim.",
            "Rotor/body oracle is one principal axis with no propeller load or external moment.",
            "The smooth fixture stays on positive motor current and does not cross an OCV knot or stop/exhaustion event.",
            "Aux-only final-tick event is exact for constant auxiliary current; it does not validate a BMS cutoff or weakest-cell model.",
        ],
        "ok": True,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n")
    print(json.dumps({
        "ok": True,
        "output": str(args.output.resolve()),
        "godot": evidence["godot"],
        "aux_event_time_s": aux_reference["event_time_s"],
        "smooth_reference": smooth["endpoint"],
        "smooth_error_orders_diagnostic_only": smooth_checks["observed_orders_diagnostic_only"],
    }))


if __name__ == "__main__":
    main()
