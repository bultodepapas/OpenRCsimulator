"""Independent arithmetic over retained audit results; no simulation writes."""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/research/physics-audit-2026-10-14"


def read(relative: str):
    return json.loads((OUT / relative).read_text(encoding="utf-8"))


def main() -> None:
    session = read("session/session-results.json")
    edges = read("propulsion-edges.json")
    summary = {"flights": [], "replays": {}, "static_control_checks": [], "crossflow_jumps": [], "aero_spanwise_limits": [], "isa_comparison": []}
    for aircraft in read("aero-edges.json")["aircraft"]:
        for epsilon in (1e-2, 1e-4, 1e-6, 1e-9):
            pair = [row for row in aircraft["rows"] if row["epsilon_mps"] == epsilon]
            delta = [pair[1]["total_loads_n_nm"][i] - pair[0]["total_loads_n_nm"][i] for i in range(6)]
            mass = next(row["mass_kg"] for row in session["aircraft"] if ("stik" in aircraft["id"]) == (row["name"] == "stik"))
            summary["aero_spanwise_limits"].append({"aircraft_id": aircraft["id"], "epsilon_mps": epsilon,
                "velocity_separation_mps": math.sqrt(2) * epsilon, "delta_loads_n_nm": delta,
                "side_acceleration_difference_g": abs(delta[1]) / (mass * 9.80665)})
    for aircraft in session["aircraft"]:
        for case in aircraft["flights"]:
            brief = {key: value for key, value in case.items() if key not in {"samples", "final_state"}}
            brief["aircraft"] = aircraft["name"]
            if case["axis"] != "neutral":
                axis = ["roll", "pitch", "yaw"].index(case["axis"])
                first = next(sample for sample in case["samples"] if sample["tick"] > 126)
                brief["initial_axis_rate_rad_s"] = first["state"][10 + axis]
                brief["initial_response_matches_pilot_sign"] = first["state"][10 + axis] * case["direction"] > 0.0
            summary["flights"].append(brief)
        rows = aircraft["static_control_authority"]
        for speed in (0.0, 5.0, 15.0, 29.0):
            for axis in ("elevator", "rudder"):
                pair = [row for row in rows if row["speed_mps"] == speed and row["control"] == axis]
                change = [pair[1]["delta_loads_n_nm"][i] - pair[0]["delta_loads_n_nm"][i] for i in range(6)]
                summary["static_control_checks"].append({"aircraft": aircraft["name"], "speed_mps": speed,
                    "control": axis, "change_of_control_authority_due_to_full_rpm_n_nm": change,
                    "maximum_absolute_difference": max(map(abs, change))})
        name = aircraft["name"]
        replay = read(f"session/{name}-exact/replay.json")
        summary["replays"][name] = {key: replay.get(key) for key in ("complete", "rows", "solver_changed", "error", "dt_s", "baseline_solver_sha256", "current_solver_sha256")}
    for rpm in (44000, 154000):
        for axis in (1, 2):
            rows = [row for row in edges["crossflow_join"] if row["rpm"] == rpm and row["flow_mps"][axis] == 20]
            at_zero = next(row for row in rows if row["flow_mps"][0] == 0)
            for epsilon in (1e-6, 1e-3):
                at_positive = next(row for row in rows if row["flow_mps"][0] == epsilon)
                jump = [at_positive["loads_n_nm"][i] - at_zero["loads_n_nm"][i] for i in range(6)]
                summary["crossflow_jumps"].append({"rpm": rpm, "transverse_axis": axis, "epsilon_mps": epsilon, "jump_n_nm": jump})
    # Hydrostatic dry standard atmosphere with the source constants already used by atmosphere.gd.
    # This comparison is conditional on a standard day; it is not a weather measurement.
    for altitude in (50.0, 500.0, 1000.0):
        geopotential = 6356766.0 * altitude / (6356766.0 + altitude)
        temperature = 288.15 - 0.0065 * geopotential
        pressure = 101325.0 * (temperature / 288.15) ** (9.80665 / (287.05287 * 0.0065))
        rho = pressure / (287.05287 * temperature)
        summary["isa_comparison"].append({"geometric_altitude_m": altitude, "isa_rho_kg_m3": rho,
            "runtime_uniform_rho_kg_m3": 1.225, "runtime_force_overestimate_at_same_coefficients_percent": 100 * (1.225 / rho - 1),
            "real_standard_day_stall_speed_increase_percent": 100 * (math.sqrt(1.225 / rho) - 1)})
    summary["flight_count"] = len(summary["flights"])
    summary["completed_flights"] = sum(row["completed"] for row in summary["flights"])
    summary["control_sign_checks_passed"] = sum(row.get("initial_response_matches_pilot_sign", False) for row in summary["flights"])
    (OUT / "lead-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print({key: summary[key] for key in ("flight_count", "completed_flights", "control_sign_checks_passed", "replays", "isa_comparison")})


if __name__ == "__main__":
    main()
