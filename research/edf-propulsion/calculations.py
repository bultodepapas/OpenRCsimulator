#!/usr/bin/env python3
"""Reproduce EDF planning arithmetic; no Godot/runtime or hardware validation.

Only Python's standard library is required. Values and their provenance are in
docs/research/edf-propulsion/physics-and-sources.md and repository-audit.md.
Print JSON to stdout, or compare against the committed report with --check.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "docs/research/edf-propulsion/calculations.json"
BASE = "57abea025f62b20233ca281d58d2acbee4ab8b8e"


def audit_oracles() -> dict:
    """Independent analytic fixtures; deliberately not an EDF implementation."""
    locked, rotor, body_w, spin, moment, shaft_net = 2.0, 0.5, 3.0, 4.0, 2.0, 3.0
    body_accel = (moment - shaft_net) / (locked - rotor)
    spin_accel = shaft_net / rotor - body_accel
    body_energy = 0.5 * locked * body_w**2
    cross_energy = rotor * spin * body_w
    relative_energy = 0.5 * rotor * spin**2
    body_power = locked * body_w * body_accel
    cross_power = rotor * (spin_accel * body_w + spin * body_accel)
    relative_power = rotor * spin * spin_accel
    work_rate = moment * body_w + shaft_net * spin

    current, r0, r1, tau, rc_v = 1.0, 0.1, 1.0, 1.0, 0.5
    capacitance = tau / r1
    rc_rate = (r1 * current - rc_v) / tau
    drop_power = current * (r0 * current + rc_v)
    dissipation = current**2 * r0 + rc_v**2 / r1
    storage_rate = capacitance * rc_v * rc_rate

    def rk4_amplification(z: float) -> float:
        return 1.0 + z + z*z/2.0 + z**3/6.0 + z**4/24.0

    exact = math.exp(-2.0)
    refinement = []
    for substeps in (1, 2, 4, 8):
        value = rk4_amplification(-2.0 / substeps)**substeps
        refinement.append({"comparison_hz": 240 * substeps,
                           "steps_over_one_240hz_tick": substeps,
                           "value": value, "absolute_error": abs(value - exact),
                           "relative_error": abs(value - exact) / exact})

    stop_locked, stop_rotor, initial_spin, stop_torque = 0.06, 0.01, 0.04, -0.2
    stop_body_accel = -stop_torque / (stop_locked - stop_rotor)
    stop_spin_accel = stop_torque / stop_rotor - stop_body_accel
    stop_time = -initial_spin / stop_spin_accel
    stop_body_rate = stop_body_accel * stop_time
    initial_energy = 0.5 * stop_rotor * initial_spin**2
    final_energy = 0.5 * stop_locked * stop_body_rate**2

    return {
        "scope": "Synthetic analytic oracles and deliberately invalid examples; no Godot execution or measured hardware parameters.",
        "locked_inertia_energy": {
            "locked_inertia_kg_m2": locked, "rotor_inertia_kg_m2": rotor,
            "body_rate_rad_s": body_w, "relative_spin_rad_s": spin,
            "external_moment_nm": moment, "net_shaft_torque_nm": shaft_net,
            "body_acceleration_rad_s2": body_accel,
            "relative_spin_acceleration_rad_s2": spin_accel,
            "body_energy_j": body_energy, "coupling_energy_j": cross_energy,
            "relative_rotor_energy_j": relative_energy,
            "total_energy_j": body_energy + cross_energy + relative_energy,
            "energy_rate_w": body_power + cross_power + relative_power,
            "independent_work_rate_w": work_rate,
            "power_residual_omitting_cross_term_w": body_power + relative_power - work_rate,
        },
        "windmill_passivity_counterexample": {
            "uniform_air_relative_speed_mps": 20.0, "relative_spin_rad_s": 100.0,
            "signed_fan_load_nm": -1.0, "invalid_axial_force_n": -1.0,
            "invalid_aerodynamic_power_w": -1.0 * 20.0 - (-1.0 * 100.0),
            "comparison_axial_force_n": -6.0,
            "comparison_aerodynamic_power_w": -6.0 * 20.0 - (-1.0 * 100.0),
            "scope": "Zero body rate, complete quasi-steady isolated installation, uniform ambient air, no fluid storage, external heat, mass injection or omitted energy flux; positive result violates passivity. A nonpositive result alone does not prove realism.",
        },
        "fixed_parameter_rc_storage": {
            "current_a": current, "r0_ohm": r0, "r1_ohm": r1,
            "tau_s": tau, "rc_voltage_v": rc_v, "capacitance_f": capacitance,
            "ocv_minus_terminal_power_w": drop_power,
            "dissipation_w": dissipation, "polarization_energy_rate_w": storage_rate,
            "balance_residual_w": drop_power - dissipation - storage_rate,
            "scope": "Fixed parameters only; variable tau/R requires parameter-work terms for an exact storage interpretation.",
        },
        "stable_but_inaccurate_rk4": {
            "decay_rate_per_s": 480.0, "horizon_s": 1.0 / 240.0,
            "initial_value": 1.0, "exact_value": exact, "refinement": refinement,
            "scope": "A stable 240 Hz step and improving refinement do not establish a predeclared production-step error budget.",
        },
        "within_tick_rotor_stop": {
            "locked_inertia_kg_m2": stop_locked, "rotor_inertia_kg_m2": stop_rotor,
            "initial_body_rate_rad_s": 0.0, "initial_relative_spin_rad_s": initial_spin,
            "net_internal_torque_before_stop_nm": stop_torque, "external_moment_nm": 0.0,
            "relative_spin_acceleration_rad_s2": stop_spin_accel,
            "exact_stop_time_s": stop_time,
            "unlocalized_full_tick_trial_spin_rad_s": initial_spin + stop_spin_accel / 240.0,
            "accepted_relative_spin_after_stop_rad_s": 0.0,
            "body_rate_after_stop_rad_s": stop_body_rate,
            "initial_angular_momentum_kg_m2_s": stop_rotor * initial_spin,
            "final_angular_momentum_kg_m2_s": stop_locked * stop_body_rate,
            "initial_energy_j": initial_energy, "final_energy_j": final_energy,
            "internal_work_to_stop_j": stop_torque * 0.5 * initial_spin * stop_time,
            "scope": "Constant moving-side torque until stop, then a feasible static hold. Negative trial speed is a locator probe, never an accepted reverse-spin state.",
        },
        "spatial_station_flow": {
            "datum_air_velocity_body_mps": [20.0, 1.0, 0.0],
            "body_rate_rad_s": [0.4, 0.3, 2.0], "station_arm_body_m": [1.0, -0.2, 0.1],
            "station_minus_datum_wind_body_mps": [1.0, 0.5, -0.2],
            "omega_cross_arm_mps": [0.3 * 0.1 - 2.0 * (-0.2),
                                     2.0 * 1.0 - 0.4 * 0.1,
                                     0.4 * (-0.2) - 0.3 * 1.0],
            "expected_local_air_velocity_body_mps": [19.43, 2.46, -0.18],
            "scope": "Point kinematics only; not finite-disc aerodynamic validation.",
        },
    }


def calculate() -> dict:
    nominal_cell_v, series, usable_fraction = 3.7, 14, 0.8
    bus_v = nominal_cell_v * series
    # Published configuration ranges are not paired operating points. The high
    # input power is used only for the explicitly hypothetical energy budget.
    fans = [
        ("DS-98 / DSM6036-600", 128.0, 98.0, 9.0, 7000.0, 28500.0),
        ("DS-130 / DSM7857-470", 152.0, 130.0, 14.0, 12000.0, 20000.0),
        ("DS-215 / DSM10066-290", 195.0, 215.0, 20.0, 15600.0, 14000.0),
    ]
    surrogate_exit_diameter_m = 0.072
    surrogate_exit_area_m2 = math.pi * surrogate_exit_diameter_m**2 / 4.0
    cases = []
    for name, diameter_mm, swept_cm2, capacity_ah, power_w, rpm in fans:
        swept_m2 = swept_cm2 / 10000.0
        nominal_wh = bus_v * capacity_ah
        cases.append({
            "configuration": name,
            "casing_inside_diameter_mm": diameter_mm,
            "fan_swept_area_cm2": swept_cm2,
            "hypothetical_14s_capacity_ah": capacity_ah,
            "constant_electrical_input_w": power_w,
            "nominal_voltage_v": bus_v,
            "nominal_energy_wh": nominal_wh,
            "nominal_current_a": power_w / bus_v,
            "time_at_80pct_nominal_energy_min": 60.0 * usable_fraction * nominal_wh / power_w,
            "unobstructed_exit_diameter_at_85pct_fsa_mm": 1000.0 * math.sqrt(4.0 * 0.85 * swept_m2 / math.pi),
            "unobstructed_exit_diameter_at_100pct_fsa_mm": 1000.0 * math.sqrt(4.0 * swept_m2 / math.pi),
            "surrogate_72mm_exit_area_over_fsa": surrogate_exit_area_m2 / swept_m2,
            "casing_based_tip_mach_upper_bound_proxy_at_listed_rpm_and_a340": math.pi * (rpm / 60.0) * (diameter_mm / 1000.0) / 340.0,
        })

    # Immutable baseline inventory values, not a measured EDF build.
    original_mass_kg = 11.438578
    removed = {"engine_main": 1.08, "turbine_accessories": 0.3,
               "thrust_tube": 0.35, "fuel_tank": 0.3,
               "fuel_flight": 1.29628, "ballast_reference": 0.062298}
    retained_kg = original_mass_kg - sum(removed.values())

    # Direct-law defect arithmetic: existing Avanti mass-flow first two rows.
    n0, m0, n1, m1 = 20000.0, 0.02987, 30000.0, 0.04481
    slope = (m1 - m0) / (n1 - n0)
    intercept = m0 - slope * n0
    rpm_probe = 1.0
    flow_probe = m0 + (rpm_probe - n0) * slope
    static_thrust_probe = 0.171 * rpm_probe / 20000.0
    installed = 0.92 * static_thrust_probe
    gross_probe = flow_probe * math.sqrt((installed / flow_probe)**2)

    # Independent analytic cooling example: RK4 stability polynomial vs exp.
    dt, cooling_w_per_k, capacity_j_per_k = 1.0 / 240.0, 720.0, 1.0
    z = -dt * cooling_w_per_k / capacity_j_per_k
    amplification = 1.0 + z + z*z/2.0 + z**3/6.0 + z**4/24.0
    ambient_k, excess_k = 298.15, 0.1

    return {
        "format": "openrc-edf-research-calculations-v2",
        "baseline_commit": BASE,
        "externally_audited_research_commit": "719c3cc6b8e3ac32d2f62e08b6df9b646925361f",
        "scope": "Planning arithmetic and analytic counterexamples only; no runtime, flight, fit, or hardware qualification.",
        "energy_assumptions": {"cell_nominal_v": nominal_cell_v, "series": series,
                               "nominal_energy_fraction": usable_fraction,
                               "voltage_sag_losses_auxiliaries_and_cutoff_included": False},
        "tip_mach_proxy_scope": "Tangential-only casing proxy at a fixed 340 m/s acoustic speed, assuming blades fit within it; not a helical relative-flow bound. Actual blade-tip diameter and local acoustic speed are not identified.",
        "fan_scenarios": cases,
        "mass_accounting": {
            "baseline_inventory_kg": original_mass_kg,
            "proposed_removed_items_kg": removed,
            "retained_inventory_kg": retained_kg,
            "illustrative_two_6s10ah_tattu_pack_mass_kg": 2.0 * 1.357,
            "incomplete_128mm_conversion_subtotal_kg": retained_kg + 1.25 + 2.0 * 1.357,
            "conflicting_specification_two_pack_mass_kg": 2.0 * 1.296,
            "incomplete_subtotal_with_conflicting_specification_mass_kg": retained_kg + 1.25 + 2.0 * 1.296,
            "pack_source_conflict": "Description says 1357 g; specification table says 1296 g, 60 A continuous and 90 A pulse. Neither mass identifies an approved high-current EDF supply.",
            "omissions": "New ESC, ducts, wiring, mounting changes and revised balance; bundled receiver/ECU/avionics masses remain unresolved. This is not EDF all-up mass.",
        },
        "turbine_direct_law_counterexample": {
            "rpm": rpm_probe, "density_kg_m3": 1.225, "axial_velocity_mps": 0.0,
            "extrapolated_mass_flow_kg_s": flow_probe,
            "mass_flow_zero_rpm": -intercept / slope,
            "computed_gross_thrust_n": gross_probe,
            "scope": "Algebra using accepted table rows; normal-flight reachability and engine execution not established.",
        },
        "battery_thermal_admission_counterexample": {
            "mass_kg": 0.01, "specific_heat_j_per_kg_k": 100.0,
            "cooling_w_per_k": cooling_w_per_k, "thermal_capacity_j_per_k": capacity_j_per_k,
            "dt_s": dt, "lambda_dt": z, "rk4_amplification": amplification,
            "exact_amplification": math.exp(z),
            "initial_temperature_k": ambient_k + excess_k,
            "rk4_temperature_after_one_step_k": ambient_k + excess_k * amplification,
            "exact_temperature_after_one_step_k": ambient_k + excess_k * math.exp(z),
            "scope": "Scalar bounds and missing guard term verified in source; no admitted complete flight fixture was executed.",
        },
        "external_audit_oracles": audit_oracles(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Compare numeric report with the committed JSON.")
    args = parser.parse_args()
    result = calculate()
    if args.check:
        expected = json.loads(REPORT.read_text(encoding="utf-8"))

        def same(a, b):
            if isinstance(a, dict) and isinstance(b, dict):
                return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
            if isinstance(a, list) and isinstance(b, list):
                return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
            if type(a) in (int, float) and type(b) in (int, float):
                return math.isfinite(a) and math.isfinite(b) and math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-12)
            return type(a) is type(b) and a == b

        if not same(result, expected):
            raise SystemExit("EDF research arithmetic differs from calculations.json")
        print("EDF research arithmetic matches calculations.json (not runtime or physical validation).")
    else:
        print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
