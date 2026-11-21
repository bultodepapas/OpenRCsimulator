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
        "format": "openrc-edf-research-calculations-v1",
        "baseline_commit": BASE,
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
