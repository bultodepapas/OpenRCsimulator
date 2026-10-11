#!/usr/bin/env python3
"""Independent checks for the EL2a powered-exhaustion FlightSession probe."""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

RATES = [120, 240, 480, 960]
EXPECTED_Q = {"4s": 0.20, "6s": 0.12}
END_TIME = 0.05
LEDGER_TOL_J = 1e-7
EVENT_TOL_S = 1e-12
EVENT_RESIDUAL_TOL_C = 1e-10


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def chemical_work_j(row: dict) -> float:
    """Exact ∫OCV dQ for the fixtures' two-knot linear OCV curves."""
    points = row["ocv_points"]  # [SOC0, V0, SOC1, V1]
    require(len(points) == 4 and points[0] == 0.0 and points[2] == 1.0,
            f"{row['pack']}: expected declared two-knot OCV fixture")
    q = row["event_start_charge_c"]
    capacity_c = 3600.0 * row["capacity_ah"]
    return points[1] * q + (points[3] - points[1]) * q * q / (2.0 * capacity_c)


def quaternion_angle(a: list[float], b: list[float]) -> float:
    # State stores [position, velocity, quaternion(wxyz), body rates].
    dot = abs(sum(x * y for x, y in zip(a[6:10], b[6:10])))
    return 2.0 * math.acos(max(-1.0, min(1.0, dot)))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    RESULTS, OUT = args.results.resolve(), args.output.resolve()
    data = json.loads(RESULTS.read_text())
    require(data["format"] == "el2-powered-parity-v1" and data.get("instrumented") is True,
            "expected the instrumented powered-parity probe")
    require(data["rates_hz"] == RATES, "the probe did not run all requested rates")
    require(data["end_time_s"] == END_TIME, "unexpected common comparison horizon")
    require(data["failures"] == [], "GDScript reported failures: " + repr(data["failures"]))
    require(len(data["rows"]) == 8, "expected 2 packs × 4 timestep rates")

    rows: dict[tuple[str, int], dict] = {}
    for row in data["rows"]:
        pack, hz = row["pack"], row["hz"]
        rows[(pack, hz)] = row
        require(row["ok"] and row["all_finite"], f"{pack} {hz}: failed finite accepted-tick checks")
        require(row["steps"] == round(END_TIME * hz) and row["end_time_s"] == END_TIME,
                f"{pack} {hz}: did not reach the shared 50 ms endpoint")
        q0 = EXPECTED_Q[pack]
        require(row["event_start_charge_c"] == q0, f"{pack} {hz}: wrong checkpoint charge")
        require(row["configured_initial_charge_c"] > q0, f"{pack} {hz}: fixture charge was not lowered")
        require(row["pre_event_point"]["duty"] == 1.0,
                f"{pack} {hz}: pre-event point was not full duty")
        require(row["pre_event_point"]["remaining_charge_c"] == q0
                and row["pre_event_point"]["motor_current_a"] > 0.0
                and row["pre_event_point"]["pack_current_a"] > 0.0,
                f"{pack} {hz}: near-empty pre-event state did not motor with positive pack current")
        loaded = row["loaded_trim_point"]
        require(loaded["remaining_charge_c"] == row["configured_initial_charge_c"]
                and loaded["motor_current_a"] > 0.0,
                f"{pack} {hz}: loaded/trimmed starting-point evidence is malformed")
        end = row["endpoint_point"]
        require(row["charge_c"] == 0.0 and end["remaining_charge_c"] == 0.0
                and end["soc"] == 0.0 and end["exhausted"],
                f"{pack} {hz}: endpoint did not commit exact Q=0")
        require(end["consumed_charge_c"] + end["remaining_charge_c"] == row["configured_initial_charge_c"],
                f"{pack} {hz}: session-derived consumed-charge budget does not close")
        require(end["mode"] == "exhausted" and end["bus_voltage_v"] == 0.0,
                f"{pack} {hz}: exhausted supply mode or bus voltage is wrong")
        for field in ("motor_current_a", "motor_bus_current_a", "battery_current_a",
                      "auxiliary_current_a", "pack_current_a", "pack_terminal_power_w",
                      "energy_rate_j_per_s", "pack_loss_w"):
            require(end[field] == 0.0, f"{pack} {hz}: exhausted pack left {field} connected")
        require(row["terminal_energy_j"] > 0.0 and row["pack_heat_j"] > 0.0,
                f"{pack} {hz}: powered event failed to accumulate terminal energy and heat")
        events = row["events"]
        require(len(events) == 1 and events[0]["type"] == "battery_exhausted",
                f"{pack} {hz}: unexpected event sequence {events!r}")
        event = events[0]
        require(0.0 < event["time_s"] < END_TIME, f"{pack} {hz}: event is outside the interval")
        require(event["time_error_bound_s"] <= EVENT_TOL_S
                and abs(event["charge_residual_c"]) <= EVENT_RESIDUAL_TOL_C,
                f"{pack} {hz}: event residual/bracket exceeded its reported bound")
        require(row["event_tick"] >= 1 and row["event_step_usec"] > 0
                and row["event_tick_wall_usec"] > 0,
                f"{pack} {hz}: actual exhaustion tick timing was not captured")
        # The API's cumulative consumed_charge_c is referenced to the configured 95% start.
        # The independent event-local chemistry budget starts at the manually injected checkpoint Q0.
        chemistry = chemical_work_j(row)
        ledger_error = chemistry - row["terminal_energy_j"] - row["pack_heat_j"]
        require(abs(ledger_error) <= LEDGER_TOL_J,
                f"{pack} {hz}: independent chemical-energy ledger error {ledger_error} J")
        row["chemical_work_j"] = chemistry
        row["chemical_ledger_error_j"] = ledger_error

    require(len(rows) == 8, "duplicate or missing fixture/rate rows")
    refinement: list[dict] = []
    for pack in EXPECTED_Q:
        reference = rows[(pack, 960)]
        ref_body = reference["body_state"]
        for hz in RATES:
            row = rows[(pack, hz)]
            body = row["body_state"]
            refinement.append({
                "pack": pack,
                "hz": hz,
                "event_time_s": row["events"][0]["time_s"],
                "event_tick": row["event_tick"],
                "event_localization_wall_ms": row["event_step_usec"] / 1000.0,
                "whole_event_tick_wall_ms": row["event_tick_wall_usec"] / 1000.0,
                "event_time_delta_vs_960_s": abs(row["events"][0]["time_s"] - reference["events"][0]["time_s"]),
                "rotor_rpm_delta_vs_960": abs(row["rotor_rpm"] - reference["rotor_rpm"]),
                "max_body_rate_delta_vs_960_rad_s": max(abs(body[i] - ref_body[i]) for i in range(10, 13)),
                "max_body_velocity_delta_vs_960_m_s": max(abs(body[i] - ref_body[i]) for i in range(3, 6)),
                "attitude_delta_vs_960_rad": quaternion_angle(body, ref_body),
                "terminal_energy_delta_vs_960_j": abs(row["terminal_energy_j"] - reference["terminal_energy_j"]),
                "pack_heat_delta_vs_960_j": abs(row["pack_heat_j"] - reference["pack_heat_j"]),
                "chemical_ledger_error_j": row["chemical_ledger_error_j"],
            })
    verified = {
        "format": "el2-powered-exhaustion-verified-v1",
        "source_results": str(RESULTS),
        "independent_chemical_budget": "exact integral of each fixture's declared two-knot linear OCV curve over the injected event-start charge Q0",
        "refinement_reference": "960 Hz FlightSession endpoint at the shared 50 ms horizon; convergence diagnostic, not an exact oracle",
        "cases_passed": len(rows),
        "ledger_tolerance_j": LEDGER_TOL_J,
        "rows": [rows[key] for key in sorted(rows)],
        "refinement": refinement,
    }
    OUT.write_text(json.dumps(verified, indent=2) + "\n")
    print("PASS: 8 powered FlightSession exhaustion cases; exact Q=0, disconnected loads, finite accepted state, positive E/H, chemical ledger.")
    print("Shared endpoint: 50 ms; 960 Hz is reported as a convergence reference, not exact truth.")
    print("pack  Hz  t_event(s)  event_tick  event_call(ms)  tick(ms)  |Δrpm|  max|Δω|  |ΔE|  |ΔH|")
    for r in refinement:
        print(f"{r['pack']:>2} {r['hz']:4d} {r['event_time_s']:.12f} {r['event_tick']:10d} "
              f"{r['event_localization_wall_ms']:13.3f} {r['whole_event_tick_wall_ms']:9.3f} "
              f"{r['rotor_rpm_delta_vs_960']:.3g} {r['max_body_rate_delta_vs_960_rad_s']:.3g} "
              f"{r['terminal_energy_delta_vs_960_j']:.3g} {r['pack_heat_delta_vs_960_j']:.3g}")
    print(f"Wrote {OUT}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise
