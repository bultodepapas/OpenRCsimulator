#!/usr/bin/env python3
"""EL1d scalar momentum, work and stop-event checks on a synthetic fixture."""
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
HZ = (120, 240, 480, 960)
MOTOR = {"kv_rpm_per_volt": 800.0, "resistance_ohm": 0.06, "no_load_current_a": 1.0}
J_LOCKED = 0.004
J_ROTOR = 0.0001
J_CARRIER = J_LOCKED - J_ROTOR
V_BUS = 6.0
DUTY = 0.85
OMEGA0 = 20.0
HORIZON_S = 0.1
STOP_OMEGA0 = 45.0
TAU = 2.0 * math.pi
PROBE = Path(__file__).with_name("scalar_probe.gd")
PRODUCTION_PATHS = (
    "physics/electric_motor.gd",
    "physics/rotor_coupling.gd",
    "physics/electric_stop.gd",
    "physics/integrator.gd",
    "physics/rigid_body.gd",
)


def close(actual: float, expected: float, absolute: float, relative: float = 0.0) -> bool:
    return math.isfinite(actual) and abs(actual - expected) <= absolute + relative * abs(expected)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def fixture_matches(observed: dict) -> None:
    require(observed["motor"] == MOTOR, "Godot probe motor fixture changed")
    expected = {
        "locked_inertia_kg_m2": J_LOCKED,
        "relative_rotor_inertia_kg_m2": J_ROTOR,
        "carrier_inertia_kg_m2": J_CARRIER,
        "bus_voltage_v": V_BUS,
        "duty": DUTY,
        "smooth_initial_omega_rad_s": OMEGA0,
        "smooth_horizon_s": HORIZON_S,
        "stop_initial_omega_rad_s": STOP_OMEGA0,
    }
    for key, value in expected.items():
        actual = observed.get(key)
        matched = close(float(actual), value, 1e-15) if isinstance(value, float) else actual == value
        require(matched, f"Godot probe fixture changed: {key}")
    require(observed["axis_body"] == [1.0, 0.0, 0.0], "fixture must stay on one principal axis")


def independent_reference() -> dict:
    """Solve the scalar motor/rotor equations, without production coupling code."""
    kv = MOTOR["kv_rpm_per_volt"]
    resistance = MOTOR["resistance_ohm"]
    no_load_current = MOTOR["no_load_current_a"]
    kt = 60.0 / (TAU * kv)
    # With one principal axis, no external moment, and J=Jcarrier+Jrotor:
    # H = J*w + Jr*Omega is constant; Jcarrier*Omega_dot/J = Q/Jr.
    coupled_factor = J_LOCKED / (J_ROTOR * J_CARRIER)

    def port(omega: float) -> tuple[float, float, float, float, float, float]:
        current = (DUTY * V_BUS - kt * omega) / resistance
        torque = kt * (current - no_load_current)
        bus_power = V_BUS * DUTY * current
        copper_power = resistance * current * current
        rotational_loss_power = kt * no_load_current * omega
        shaft_power = torque * omega
        return current, torque, bus_power, copper_power, rotational_loss_power, shaft_power

    def rhs(_at: float, state: np.ndarray) -> list[float]:
        omega, _bus_energy, _copper_energy, _rotational_energy, _shaft_work = state
        _current, torque, bus_power, copper_power, rotational_loss, shaft_power = port(float(omega))
        return [coupled_factor * torque, bus_power, copper_power, rotational_loss, shaft_power]

    solve = solve_ivp(
        rhs,
        (0.0, HORIZON_S),
        [OMEGA0, 0.0, 0.0, 0.0, 0.0],
        method="DOP853",
        rtol=2e-13,
        atol=[2e-13, 2e-13, 2e-13, 2e-13, 2e-13],
        max_step=0.001,
    )
    require(solve.success and solve.status == 0 and solve.t[-1] == HORIZON_S,
            "independent DOP853 integration did not reach the smooth endpoint")
    require(np.isfinite(solve.y).all(), "independent reference returned a nonfinite value")

    q_intercept = kt * (DUTY * V_BUS / resistance - no_load_current)
    q_slope = kt * kt / resistance
    decay_rate = coupled_factor * q_slope
    omega_steady = q_intercept / q_slope
    omega_exact = omega_steady + (OMEGA0 - omega_steady) * math.exp(-decay_rate * HORIZON_S)
    require(close(float(solve.y[0, -1]), omega_exact, 2e-10),
            "independent DOP853 result disagrees with the scalar closed form")
    current_final = port(omega_exact)[0]
    require(current_final > no_load_current > 0.0,
            "smooth fixture crossed the motoring / static-friction branch")

    stop_accel_rad_s2 = kt * no_load_current * coupled_factor
    stop_time_s = STOP_OMEGA0 / stop_accel_rad_s2
    return {
        "kt_nm_per_a": kt,
        "coupled_factor_s_per_kg_m2": coupled_factor,
        "q_intercept_nm": q_intercept,
        "q_slope_nms": q_slope,
        "decay_rate_per_s": decay_rate,
        "steady_relative_speed_rad_s": omega_steady,
        "smooth_endpoint": {
            "omega_rad_s": omega_exact,
            "body_rate_x_rad_s": -J_ROTOR / J_LOCKED * (omega_exact - OMEGA0),
            "bus_energy_j": float(solve.y[1, -1]),
            "copper_energy_j": float(solve.y[2, -1]),
            "rotational_loss_energy_j": float(solve.y[3, -1]),
            "shaft_work_j": float(solve.y[4, -1]),
        },
        "smooth_reference_method": "SciPy DOP853 on scalar equations, checked against analytic exponential",
        "smooth_reference_rhs": [
            "Q = kt * ((duty*V - kt*Omega)/R - I0)",
            "Omega_dot = (Jlocked/(Jrotor*Jcarrier))*Q",
            "w_dot = -(Jrotor/Jlocked)*Omega_dot from Hdot=0",
            "Ebus_dot = V*duty*I; Ecopper_dot=R*I^2; Erot_dot=kt*I0*Omega; Eshaft_dot=Q*Omega",
        ],
        "stop_time_s": stop_time_s,
        "stop_rhs": "Omega_dot = -(kt*I0)*Jlocked/(Jrotor*Jcarrier); t_stop=Omega0/(-Omega_dot)",
        "stop_final_body_rate_x_rad_s": J_ROTOR / J_LOCKED * STOP_OMEGA0,
        "solve_ivp_evaluations": int(solve.nfev),
    }


def check_probe(raw: dict, reference: dict) -> dict:
    fixture_matches(raw["fixture"])
    require([point["hz"] for point in raw["smooth"]] == list(HZ), "smooth sample rates changed")
    require([point["hz"] for point in raw["stop"]] == list(HZ), "stop sample rates changed")

    expected = reference["smooth_endpoint"]
    smooth_points = []
    omega_errors = []
    for point in raw["smooth"]:
        hz = point["hz"]
        require(point["ok"] and point["steps"] == hz // 10, f"invalid smooth run at {hz} Hz")
        require(close(point["time_s"], HORIZON_S, 2e-15), f"wrong smooth duration at {hz} Hz")
        error_omega = abs(point["final_omega_rad_s"] - expected["omega_rad_s"])
        error_body = abs(point["final_body_rate_x_rad_s"] - expected["body_rate_x_rad_s"])
        omega_errors.append(error_omega)
        momentum_error = point["momentum_x_kg_m2_s"] - J_ROTOR * OMEGA0
        port_balance = (point["bus_energy_j"] - point["copper_energy_j"]
                        - point["rotational_loss_energy_j"] - point["shaft_work_j"])
        initial_kinetic = 0.5 * J_ROTOR * OMEGA0 * OMEGA0
        kinetic_change = point["kinetic_energy_j"] - initial_kinetic
        kinetic_work_error = kinetic_change - point["shaft_work_j"]
        reference_errors = {
            "omega_rad_s": error_omega,
            "body_rate_rad_s": error_body,
            "bus_energy_j": abs(point["bus_energy_j"] - expected["bus_energy_j"]),
            "copper_energy_j": abs(point["copper_energy_j"] - expected["copper_energy_j"]),
            "rotational_loss_energy_j": abs(point["rotational_loss_energy_j"] - expected["rotational_loss_energy_j"]),
            "shaft_work_j": abs(point["shaft_work_j"] - expected["shaft_work_j"]),
        }
        require(abs(momentum_error) <= 1e-13, f"momentum drift at {hz} Hz: {momentum_error}")
        require(abs(port_balance) <= 2e-12, f"electrical port work does not close at {hz} Hz: {port_balance}")
        require(abs(kinetic_work_error) <= 0.0004, f"shaft work / coupled kinetic energy does not close at {hz} Hz")
        require(error_omega <= 0.002, f"120-Hz trajectory endpoint exceeds its 0.002 rad/s envelope")
        smooth_points.append({
            "hz": hz,
            "steps": point["steps"],
            "final_omega_rad_s": point["final_omega_rad_s"],
            "reference_error": reference_errors,
            "relative_momentum_error_kg_m2_s": momentum_error,
            "port_energy_closure_error_j": port_balance,
            "kinetic_change_j": kinetic_change,
            "coupled_shaft_work_j": point["shaft_work_j"],
            "kinetic_work_closure_error_j": kinetic_work_error,
            "maximum_quaternion_norm_error": abs(math.sqrt(sum(v * v for v in point["final_quaternion"])) - 1.0),
        })
    require(all(a > b for a, b in zip(omega_errors, omega_errors[1:])),
            f"smooth trajectory did not refine monotonically: {omega_errors}")
    orders = [math.log(omega_errors[i] / omega_errors[i + 1], 2.0) for i in range(len(omega_errors) - 1)]
    require(all(3.8 <= order <= 4.2 for order in orders), f"smooth RK4 observed orders outside [3.8,4.2]: {orders}")

    stop_points = []
    stop_times = []
    for point in raw["stop"]:
        hz = point["hz"]
        require(point["ok"] and point["final_rpm"] == 0.0, f"stop did not project to rest at {hz} Hz")
        time_error = point["event_time_s"] - reference["stop_time_s"]
        momentum_error = point["momentum_x_kg_m2_s"] - J_ROTOR * STOP_OMEGA0
        body_rate_error = point["final_body_rate_x_rad_s"] - reference["stop_final_body_rate_x_rad_s"]
        require(abs(time_error) <= 1e-9, f"stop event time error at {hz} Hz: {time_error}")
        require(abs(momentum_error) <= 2e-13, f"stop projection momentum error at {hz} Hz: {momentum_error}")
        require(abs(body_rate_error) <= 2e-9, f"stop projection body-rate error at {hz} Hz: {body_rate_error}")
        stop_times.append(point["event_time_s"])
        stop_points.append({
            "hz": hz,
            "steps_to_event": point["steps_to_event"],
            "event_time_s": point["event_time_s"],
            "event_time_error_s": time_error,
            "relative_momentum_error_kg_m2_s": momentum_error,
            "body_rate_error_rad_s": body_rate_error,
        })
    stop_spread = max(stop_times) - min(stop_times)
    require(stop_spread <= 5e-12, f"stop event refinement spread exceeded 5e-12 s: {stop_spread}")

    return {
        "smooth": {
            "points": smooth_points,
            "omega_error_rad_s": omega_errors,
            "observed_order": orders,
            "thresholds": {
                "momentum_abs_kg_m2_s": 1e-13,
                "port_energy_abs_j": 2e-12,
                "kinetic_work_abs_j": 4e-4,
                "coarsest_omega_abs_rad_s": 2e-3,
                "observed_order": [3.8, 4.2],
            },
        },
        "stop": {
            "points": stop_points,
            "cross_rate_spread_s": stop_spread,
            "thresholds": {
                "event_time_abs_s": 1e-9,
                "cross_rate_spread_s": 5e-12,
                "projection_momentum_abs_kg_m2_s": 2e-13,
            },
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()
    versions = {name: version(name) for name in PINNED}
    require(versions == PINNED, f"Use pinned research environment {PINNED}, observed {versions}")
    app_path = args.app.resolve()
    godot_path = args.godot.resolve()
    probe_path = PROBE.resolve()
    command = [str(godot_path), "--headless", "--path", str(app_path), "--audio-driver", "Dummy",
               "--script", str(probe_path)]
    process = subprocess.run(command, text=True, capture_output=True, timeout=args.timeout)
    log = process.stdout + process.stderr
    require(process.returncode == 0, f"Godot scalar probe failed (exit {process.returncode}):\n{log}")
    require(not re.search(r"^(?:SCRIPT |SHADER )?ERROR:", log, re.M), f"Godot reported an error:\n{log}")
    lines = [line[len("EL1D_SCALAR_JSON:"):] for line in log.splitlines()
             if line.startswith("EL1D_SCALAR_JSON:")]
    require(len(lines) == 1, f"expected one scalar JSON result; got {len(lines)}")
    production_output = json.loads(lines[0])
    reference = independent_reference()
    checks = check_probe(production_output, reference)
    production_hashes = {
        path: hashlib.sha256((app_path / path).read_bytes()).hexdigest()
        for path in PRODUCTION_PATHS
    }
    evidence = {
        "format": "openrc-el1d-scalar-evidence-v1",
        "status": "synthetic numerical qualification; no aircraft or hardware calibration",
        "godot": subprocess.check_output([str(godot_path), "--version"], text=True).strip(),
        "python_versions": versions,
        "fixture": production_output["fixture"],
        "reference": reference,
        "checks": checks,
        "independence": {
            "expected_values": "Python scalar equations and SciPy DOP853; closed-form exponential cross-check",
            "production_path": "Godot electric motor + rotor response + RK4 + stop event; no production coupling used to calculate expected values",
            "sha256": production_hashes,
            "probe_sha256": hashlib.sha256(probe_path.read_bytes()).hexdigest(),
            "verifier_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        },
        "limitations": [
            "Synthetic direct-drive motor and a single principal axis; no propeller or external moment.",
            "This checks the source/rotor equations and stop numerics, not an aircraft flight or measured motor.",
            "The closed form assumes positive motoring current for the smooth interval and constant I0 loss during coast.",
            "A principal-axis fixture does not independently qualify general tilted-axis gyro coupling; the separate stop unit test covers a tilted momentum projection.",
        ],
        "ok": True,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n")
    print(json.dumps({
        "ok": True,
        "output": str(args.output.resolve()),
        "godot": evidence["godot"],
        "smooth_omega_errors_rad_s": checks["smooth"]["omega_error_rad_s"],
        "smooth_observed_orders": checks["smooth"]["observed_order"],
        "stop_time_s": reference["stop_time_s"],
        "stop_max_error_s": max(abs(point["event_time_error_s"]) for point in checks["stop"]["points"]),
    }))


if __name__ == "__main__":
    main()
