#!/usr/bin/env python3
"""Reproducible research-only reference calculations for the Open RC drone plan.

Run: python3 validation/reference_oracles.py
Writes reference_oracles.json next to this script and prints that complete report.
Only Python's standard library is used. The expected constants below were prepared
independently from the equations and are not measurements of an aircraft.

Actual-rate target: Betaflight 4.5.2, commit
024f8e13d4e642eb6a380308685b9ea3aa3ef1a2, src/main/fc/rc.c.
The remaining models and their numerical parameters are synthetic fixtures. A
passing result establishes arithmetic and conventions, not simulation behavior,
hardware fidelity, or equivalence to a complete Betaflight flight controller.
"""

import hashlib
import json
import math
from pathlib import Path
import sys


HERE = Path(__file__).resolve().parent
REPORT_PATH = HERE / "reference_oracles.json"
REL_TOL = 1e-10
ABS_TOL = 1e-10


def compare(actual, expected, path="root"):
    """Return mismatch descriptions, using fixed expected values and tolerances."""
    problems = []
    if isinstance(expected, bool):
        if actual is not expected:
            problems.append(f"{path}: {actual!r} != {expected!r}")
    elif isinstance(expected, (int, float)):
        if (isinstance(actual, bool) or not isinstance(actual, (int, float))
                or not math.isfinite(actual)
                or not math.isclose(actual, expected, rel_tol=REL_TOL, abs_tol=ABS_TOL)):
            problems.append(f"{path}: {actual!r} != {expected!r}")
    elif isinstance(expected, list):
        if not isinstance(actual, list) or len(actual) != len(expected):
            problems.append(f"{path}: list shape differs")
        else:
            for i, (a, e) in enumerate(zip(actual, expected)):
                problems.extend(compare(a, e, f"{path}[{i}]"))
    elif isinstance(expected, dict):
        if not isinstance(actual, dict) or set(actual) != set(expected):
            problems.append(f"{path}: dictionary keys differ")
        else:
            for key in expected:
                problems.extend(compare(actual[key], expected[key], f"{path}.{key}"))
    elif actual != expected:
        problems.append(f"{path}: {actual!r} != {expected!r}")
    return problems


def actual_rate(x, center_dps, max_dps, expo, limit_dps):
    if not -1.0 <= x <= 1.0 or not 0.0 <= expo <= 1.0:
        raise ValueError("stick/expo outside the stated rate-curve domain")
    delta = max(0.0, max_dps - center_dps)
    rate = center_dps * x + delta * abs(x) * (expo * x**5 + (1.0 - expo) * x)
    return max(-limit_dps, min(rate, limit_dps))


def matvec(matrix, vector):
    return [sum(a * b for a, b in zip(row, vector)) for row in matrix]


def solve_square(matrix, rhs):
    """Gaussian elimination with partial pivoting, independent of the known f."""
    n = len(rhs)
    augmented = [list(row) + [value] for row, value in zip(matrix, rhs)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(augmented[r][col]))
        if abs(augmented[pivot][col]) < 1e-14:
            raise ValueError("singular wrench matrix")
        augmented[col], augmented[pivot] = augmented[pivot], augmented[col]
        p = augmented[col][col]
        for j in range(col, n + 1):
            augmented[col][j] /= p
        for r in range(n):
            if r == col:
                continue
            factor = augmented[r][col]
            for j in range(col, n + 1):
                augmented[r][j] -= factor * augmented[col][j]
    return [augmented[i][n] for i in range(n)]


def make_wrench_matrix(hubs, spins, kappa):
    return [
        [1.0 for _ in hubs],
        [-hub[1] for hub in hubs],
        [hub[0] for hub in hubs],
        [spin * kappa for spin in spins],
    ]


def solve_bus(voc, pack_resistance, aux_current, loads):
    """Enumerate active sets of the ideal averaged one-quadrant DC model.

    load = (effective duty, back EMF in V, motor equivalent R in ohm, enabled).
    At exact branch equality choose the inactive side. d is bridge duty, not a
    DShot number, pilot throttle, stator-phase current, or asserted ESC protocol.
    """
    candidates = []
    for mask in range(1 << len(loads)):
        active = [i for i in range(len(loads)) if (mask >> i) & 1]
        if any(not loads[i][3] or loads[i][0] == 0.0 for i in active):
            continue
        numerator = voc - pack_resistance * aux_current
        denominator = 1.0
        for i in active:
            duty, emf, resistance, _enabled = loads[i]
            numerator += pack_resistance * duty * emf / resistance
            denominator += pack_resistance * duty * duty / resistance
        voltage = numerator / denominator
        if voltage <= 0.0:
            continue
        implied_active = [i for i, (d, e, _r, enabled) in enumerate(loads)
                          if enabled and d > 0.0 and d * voltage > e]
        if active != implied_active:
            continue
        currents = [max(0.0, (d * voltage - e) / r) if enabled and d > 0.0 else 0.0
                    for d, e, r, enabled in loads]
        pack_current = aux_current + sum(loads[i][0] * currents[i]
                                         for i in range(len(loads)))
        candidates.append({
            "bus_voltage_v": voltage,
            "motor_current_a": currents,
            "pack_current_a": pack_current,
            "active_indices": active,
        })
    if len(candidates) != 1:
        raise ValueError(f"expected one valid bus active set; found {len(candidates)}")
    return candidates[0]


def celsius_to_kelvin(celsius):
    if celsius < -273.15:
        raise ValueError("temperature is below absolute zero")
    return celsius + 273.15


def main():
    results = []

    def check(name, actual, expected, note):
        failures = compare(actual, expected)
        results.append({"name": name, "passed": not failures, "actual": actual,
                        "expected": expected, "mismatches": failures, "note": note})

    # Expected constants are frozen independently of the calculation functions.
    sticks = [-1.0, -.75, -.5, -.25, 0.0, .25, .5, .75, 1.0]
    check("actual_rates_full_curve_deg_s",
          [actual_rate(x, 200.0, 670.0, .58, 1998.0) for x in sticks],
          [-670.0, -309.554443359375, -153.609375, -62.404052734375,
           0.0, 62.404052734375, 153.609375, 309.554443359375, 670.0],
          "Pinned Actual curve; values at nine signed stick positions.")
    check("actual_zero_expo_is_not_linear",
          actual_rate(.5, 200.0, 670.0, 0.0, 1998.0), 217.5,
          "For zero expo, 0.5 stick does not give half the endpoint rate.")
    check("actual_full_expo_midstick",
          actual_rate(.5, 200.0, 670.0, 1.0, 1998.0), 107.34375,
          "Checks the fifth-power term separately.")
    check("actual_max_below_center_floor",
          [actual_rate(x, 200.0, 100.0, .58, 1998.0) for x in [-1.0, -.5, .5, 1.0]],
          [-200.0, -100.0, 100.0, 200.0],
          "The max-minus-center contribution is floored at zero.")
    check("actual_axis_rate_cap",
          [actual_rate(x, 200.0, 670.0, .58, 500.0) for x in [-1.0, 1.0]],
          [-500.0, 500.0], "A separate per-axis cap binds after the curve.")
    check("actual_deg_to_radians_per_second",
          actual_rate(.5, 200.0, 670.0, .58, 1998.0) * math.pi / 180.0,
          2.6809893556806648, "Convert deg/s to rad/s once at the boundary.")

    hubs = [(-.1, .1), (.1, .1), (-.1, -.1), (.1, -.1)]
    spins = [-1.0, 1.0, 1.0, -1.0]
    matrix = make_wrench_matrix(hubs, spins, .01)
    check("wrench_forward_frd_signs",
          matvec(matrix, [.5, 1.1, 1.3, 1.1]), [4.0, .08, .04, .008],
          "Wrench order is total positive thrust, FRD roll, pitch and yaw.")
    check("wrench_inverse_four_forces",
          solve_square(matrix, [4.0, .08, .04, .008]), [.5, 1.1, 1.3, 1.1],
          "General Gaussian elimination recovers known synthetic motor thrusts.")

    locked_inertia, rotor_inertia, omega, motor_torque = .002, .00001, 1000.0, .1
    alpha_z = motor_torque / (locked_inertia - rotor_inertia)
    rotor_accel = motor_torque / rotor_inertia + alpha_z
    body_l_dot = locked_inertia * alpha_z
    relative_l_dot = -rotor_inertia * rotor_accel
    check("rotor_total_angular_momentum",
          {"alpha_z_rad_s2": alpha_z, "relative_rotor_accel_rad_s2": rotor_accel,
           "body_momentum_rate_nm": body_l_dot, "relative_momentum_rate_nm": relative_l_dot,
           "total_momentum_rate_nm": body_l_dot + relative_l_dot},
          {"alpha_z_rad_s2": 50.25125628140704,
           "relative_rotor_accel_rad_s2": 10050.251256281406,
           "body_momentum_rate_nm": .10050251256281408,
           "relative_momentum_rate_nm": -.10050251256281406,
           "total_momentum_rate_nm": 0.0},
          "One free rotor, no external torque; signs are FRD and thrust axis is -z.")
    cross_energy_rate = alpha_z * (-rotor_inertia * omega)
    relative_energy_rate = rotor_inertia * omega * rotor_accel
    check("rotor_motor_work_with_cross_term",
          {"relative_spin_energy_rate_w": relative_energy_rate,
           "cross_term_rate_w": cross_energy_rate,
           "total_rotational_energy_rate_w": relative_energy_rate + cross_energy_rate,
           "internal_motor_work_w": motor_torque * omega},
          {"relative_spin_energy_rate_w": 100.50251256281406,
           "cross_term_rate_w": -.5025125628140704,
           "total_rotational_energy_rate_w": 100.0, "internal_motor_work_w": 100.0},
          "The body/relative-spin cross term is required for work closure.")

    voc, rp, iaux = 24.0, .05, .2
    identical = [(.5, 8.0, .1, True) for _ in range(4)]
    bus4 = solve_bus(voc, rp, iaux, identical)
    check("shared_bus_four_identical_motors",
          bus4,
          {"bus_voltage_v": 21.326666666666668,
           "motor_current_a": [26.633333333333333] * 4,
           "pack_current_a": 53.46666666666667, "active_indices": [0, 1, 2, 3]},
          "All four DC-equivalent motor loads share one common pack voltage.")
    vb = bus4["bus_voltage_v"]
    im = bus4["motor_current_a"][0]
    ip = bus4["pack_current_a"]
    check("shared_bus_and_motor_energy_balance",
          {"ocv_power_w": voc * ip, "terminal_power_w": vb * ip,
           "pack_resistive_loss_w": rp * ip**2, "aux_power_w": vb * iaux,
           "each_motor_bus_input_w": vb * .5 * im, "each_em_power_w": 8.0 * im,
           "each_motor_copper_loss_w": .1 * im**2},
          {"ocv_power_w": 1283.2, "terminal_power_w": 1140.2657777777778,
           "pack_resistive_loss_w": 142.93422222222222,
           "aux_power_w": 4.265333333333333,
           "each_motor_bus_input_w": 284.0001111111111,
           "each_em_power_w": 213.06666666666666,
           "each_motor_copper_loss_w": 70.93344444444445},
          "Pack source, terminal, heat, auxiliary, motor conversion and copper losses close.")
    mixed_loads = [(.4, 3.0, .1, True), (.5, 7.0, .1, True),
                   (.6, 20.0, .1, True), (0.0, 0.0, .1, False)]
    check("shared_bus_mixed_active_and_coast",
          solve_bus(voc, rp, iaux, mixed_loads),
          {"bus_voltage_v": 21.858921161825726,
           "motor_current_a": [57.4356846473029, 39.29460580912863, 0.0, 0.0],
           "pack_current_a": 42.82157676348548, "active_indices": [0, 1]},
          "Third motor overruns and coasts; fourth is disabled.")
    bus1 = solve_bus(voc, rp, iaux, identical[:1])
    check("one_load_versus_shared_four_loads",
          {"one_load_bus_v": bus1["bus_voltage_v"],
           "one_load_pack_a": bus1["pack_current_a"],
           "four_load_bus_v": bus4["bus_voltage_v"]},
          {"one_load_bus_v": 23.10222222222222,
           "one_load_pack_a": 17.955555555555556,
           "four_load_bus_v": 21.326666666666668},
          "Four isolated single-pack calls would report the wrong bus voltage.")

    diagonal_mm = 152.0
    adjacent_mm = diagonal_mm / math.sqrt(2.0)
    check("fixture_5_0_inch_disc_clearance",
          {"adjacent_hub_spacing_mm": adjacent_mm,
           "signed_disc_clearance_mm": adjacent_mm - 127.0,
           "zero_gap_diagonal_mm": 127.0 * math.sqrt(2.0)},
          {"adjacent_hub_spacing_mm": 107.48023074035521,
           "signed_disc_clearance_mm": -19.51976925964479,
           "zero_gap_diagonal_mm": 179.60512242138307},
          "Coplanar square-X disc envelope; zero gap is not a safety margin.")
    check("fixture_5_1_inch_disc_clearance",
          {"adjacent_hub_spacing_mm": adjacent_mm,
           "signed_disc_clearance_mm": adjacent_mm - 129.54,
           "zero_gap_diagonal_mm": 129.54 * math.sqrt(2.0)},
          {"adjacent_hub_spacing_mm": 107.48023074035521,
           "signed_disc_clearance_mm": -22.05976925964478,
           "zero_gap_diagonal_mm": 183.19722486981073},
          "A nominal 5.1-inch disc is 129.54 mm, not 127 mm.")

    def vertical_fov(hfov_degrees, aspect):
        return math.degrees(2.0 * math.atan(math.tan(math.radians(hfov_degrees) / 2.0) / aspect))

    check("fpv_horizontal_to_vertical_fov",
          {"v_fov_16_9_degrees": vertical_fov(120.0, 16.0 / 9.0),
           "v_fov_4_3_degrees": vertical_fov(120.0, 4.0 / 3.0)},
          {"v_fov_16_9_degrees": 88.50715548032275,
           "v_fov_4_3_degrees": 104.82182106205009},
          "Perspective conversion; actual engine projection needs its own test.")

    frequencies = [20.0, 40.0, 60.0, 80.0]
    sample_period = 1.0 / 240.0
    zoh_phase = [-180.0 * f * sample_period for f in frequencies]
    zoh_db = [20.0 * math.log10(math.sin(math.pi * f * sample_period)
                                / (math.pi * f * sample_period)) for f in frequencies]
    delay_phase = [-360.0 * f * sample_period for f in frequencies]
    check("zoh_240hz_phase_and_magnitude",
          {"phase_degrees": zoh_phase, "magnitude_db": zoh_db,
           "extra_full_tick_phase_degrees": delay_phase},
          {"phase_degrees": [-15.0, -30.0, -45.0, -60.0],
           "magnitude_db": [-.09944792154339814, -.4005723594894283,
                            -.9120975839632401, -1.6499597255724274],
           "extra_full_tick_phase_degrees": [-30.0, -60.0, -90.0, -120.0]},
          "Zero-order hold only; extra delay values exclude the hold's own phase.")

    kv_rpm_per_volt, w, duty, voltage, resistance = 1000.0, 1000.0, .5, 24.0, .1
    kv_si = kv_rpm_per_volt * math.tau / 60.0
    kt = 1.0 / kv_si
    emf = kt * w
    motor_i = (duty * voltage - emf) / resistance
    check("motor_kv_kt_and_ideal_bridge_units",
          {"kv_rad_s_per_v": kv_si, "kt_nm_per_a": kt, "back_emf_v": emf,
           "equivalent_motor_current_a": motor_i, "pack_motor_current_a": duty * motor_i,
           "bus_power_w": voltage * duty * motor_i,
           "em_power_w": kt * motor_i * w, "copper_loss_w": resistance * motor_i**2},
          {"kv_rad_s_per_v": 104.71975511965977, "kt_nm_per_a": .009549296585513721,
           "back_emf_v": 9.549296585513721,
           "equivalent_motor_current_a": 24.50703414486279,
           "pack_motor_current_a": 12.253517072431395,
           "bus_power_w": 294.0844097383535, "em_power_w": 234.0249374806064,
           "copper_loss_w": 60.05947225774707},
          "Kt=1/Kv only in the stated ideal reciprocal DC-equivalent convention; effective bridge duty is not DShot.")
    caught_invalid_temperature = False
    try:
        celsius_to_kelvin(-273.16)
    except ValueError:
        caught_invalid_temperature = True
    check("kelvin_is_absolute_temperature_not_motor_kv",
          {"minus_40_c_in_k": celsius_to_kelvin(-40.0),
           "plus_20_c_in_k": celsius_to_kelvin(20.0),
           "absolute_zero_k": celsius_to_kelvin(-273.15),
           "below_absolute_zero_rejected": caught_invalid_temperature},
          {"minus_40_c_in_k": 233.15, "plus_20_c_in_k": 293.15,
           "absolute_zero_k": 0.0, "below_absolute_zero_rejected": True},
          "Kelvin is K, an absolute temperature; motor Kv is a speed constant in rpm/V.")

    passed = sum(bool(case["passed"]) for case in results)
    report = {
        "schema": "openrc-dr-reference-oracles-v1",
        "scope": "Synthetic software and mathematical reference checks; not physical validation.",
        "rate_source": {"project": "Betaflight", "tag": "4.5.2",
                        "commit": "024f8e13d4e642eb6a380308685b9ea3aa3ef1a2",
                        "path": "src/main/fc/rc.c"},
        "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "tolerances": {"relative": REL_TOL, "absolute": ABS_TOL},
        "total": len(results), "passed": passed, "failed": len(results) - passed,
        "results": results,
    }
    rendered = json.dumps(report, indent=2, allow_nan=False) + "\n"
    REPORT_PATH.write_text(rendered, encoding="utf-8")
    print(f"Reference checks: {passed}/{len(results)} passed, {len(results) - passed} failed")
    print(rendered, end="")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
