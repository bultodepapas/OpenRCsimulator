#!/usr/bin/env python3
"""Independent scalar checks for A36 R6; no production Python/GDScript imports.

Propeller power is checked from the authored coefficient tables and dimensional
definitions. The flap oracle is conditional algebra: reported wing wakes are
inputs, not independently measured/validated circulation. Neither is flight
calibration. The interior-interval example is validator-design arithmetic only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path


def record(path: Path, marker: str) -> dict:
    lines = [line[len(marker):] for line in path.read_text().splitlines()
             if line.startswith(marker)]
    if len(lines) != 1:
        raise ValueError(f"expected exactly one {marker!r} record in {path}")
    return json.loads(lines[0])


def near(actual: float, expected: float, tolerance: float = 2e-10) -> None:
    assert math.isfinite(actual) and math.isfinite(expected)
    assert abs(actual - expected) <= tolerance * max(1.0, abs(expected)), (actual, expected)


def linear(rows: list[list[float]], x: float) -> float:
    # The witnesses are inside the authored table. No extrapolation is needed.
    assert rows[0][0] <= x <= rows[-1][0]
    for (a, fa), (b, fb) in zip(rows, rows[1:]):
        if a <= x <= b:
            return fa + (fb - fa) * (x - a) / (b - a)
    raise AssertionError("missing interpolation interval")


def flap_oracle(path: Path) -> dict:
    data = record(path, "R6_FLAP_JSON ")
    assert data["failures"] == 0 and len(data["admissions"]) == 3
    assert all(row["ok"] and not row["errors"] for row in data["admissions"])
    rows = []
    for case in data["cases"]:
        if case["alpha_deg"] != 0.0 or case["ground_effect_requested"]:
            continue
        x, speed = case["oracle_inputs"], case["speed_mps"]
        a_clean = x["tail_free_incidence"] - math.atan2(
            x["tail_downwash_gain"] * case["clean_wake_mps"], speed)
        a_flap = x["tail_free_incidence"] - math.atan2(
            x["tail_downwash_gain"] * case["flapped_wake_mps"], speed)
        assert max(abs(a_clean), abs(a_flap)) < x["tail_linear_limit_rad"]
        assert case["clean_blend_nan"] == case["clean_blend_held"] == 0.0

        def drag_coefficient(angle: float) -> float:
            return (x["tail_cd0"] + x["tail_k"] * (x["tail_free_slope"] * angle)**2
                    + x["tail_cd90"] * math.sin(angle)**2)

        delta_fx = (0.5 * x["rho"] * speed**2 * x["tail_area"]
                    * (drag_coefficient(a_flap) - drag_coefficient(a_clean)))
        tail_arm_z = -(x["tail_position_le"][2] - x["cg_le"][2])
        expected = [delta_fx, 0.0, 0.0, 0.0, tail_arm_z * delta_fx, 0.0]
        for field in ("held_minus_static", "dynamics_held_minus_static"):
            for actual, wanted in zip(case[field], expected):
                near(actual, wanted)
        rows.append({"aircraft": case["aircraft"], "speed_mps": speed,
                     "flap_deg": case["flap_deg"], "tail_angle_clean_rad": a_clean,
                     "tail_angle_flapped_rad": a_flap, "expected_delta": expected,
                     "max_error": max(abs(a-b) for a, b in
                                      zip(case["held_minus_static"], expected))})
    assert len(rows) == 15
    for aircraft in {row["aircraft"] for row in rows}:
        speeds = {row["speed_mps"]: row for row in rows
                  if row["aircraft"] == aircraft and row["flap_deg"] == 10.0}
        for speed, row in speeds.items():
            near(row["expected_delta"][0] / speed**2,
                 speeds[20.0]["expected_delta"][0] / 400.0)
        tiny = next(row for row in rows if row["aircraft"] == aircraft
                    and row["flap_deg"] == 0.0001)
        assert abs(tiny["expected_delta"][0]) < abs(speeds[20.0]["expected_delta"][0]) / 1000
    return {"scope": "conditional tail-drag algebra and lever-arm identity; wake is an input",
            "checked_cases": len(data["cases"]), "godot_assertions": data["checks"],
            "oracle_cases": rows}


def propeller_oracle(path: Path, project: Path, natural: bool) -> dict:
    marker = "R6_NATURAL_TRIM " if natural else "R6_COMPONENT "
    sample = record(path, marker)
    name = "r6_custom_trim.json" if natural else "r6_custom_power.json"
    aircraft = json.loads((project / name).read_bytes())
    prop = aircraft["propulsion"]["propeller"]
    diameter, n = prop["diameter"]["value"], sample["rpm"] / 60.0
    density, speed = sample["rho"], sample["speed_mps"]
    advance_ratio = speed / (n * diameter)
    near(sample["j"], advance_ratio)
    ct = linear(prop["ct_table"]["value"], advance_ratio)
    cp = linear(prop["cp_table"]["value"], advance_ratio)
    thrust = density * n**2 * diameter**4 * ct
    shaft_power = density * n**3 * diameter**5 * cp
    work = thrust * speed
    area = math.pi * diameter**2 / 4.0
    ideal_disk = thrust * (speed + math.sqrt(speed**2 + 2 * thrust / (density * area))) / 2
    near(sample["thrust_n"], thrust)
    near(sample["shaft_power_w"], shaft_power)
    near(sample["thrust_work_w"] if natural else sample["body_force_work_w"], work)
    near(sample["ideal_disk_w"], ideal_disk)
    assert thrust > 0 and shaft_power > 0 and work > shaft_power
    if natural:
        assert sample["rate_radps"] == [0.0, 0.0, 0.0]
        assert sample["final_tick"] == sample["initial_tick"] + 1 and not sample["fault"]
        accepted = sample
    else:
        stock = json.loads((project / "data/aircraft/turbo_lumber_evolution.json").read_bytes())
        stock_cp = linear(stock["propulsion"]["propeller"]["cp_table"]["value"], advance_ratio)
        stock_power = density * n**3 * diameter**5 * stock_cp
        near(sample["stock_shaft_power_w"], stock_power)
        assert stock_power > ideal_disk
        session = record(path, "R6_SESSION ")
        assert session["stage_ok"] and session["checkpoint_accepted"]
        assert session["final_tick"] == session["initial_tick"] + 1 and not session["fault"]
        accepted = session
    near(sample["shaft_power_w"], sample["torque_nm"] * n * 2 * math.pi)
    assert accepted["backend"]["backend"] == "gdscript_reference"
    for field, source in (("custom_identity", name),
                          ("stock_identity", "data/aircraft/turbo_lumber_evolution.json")):
        assert accepted[field]["sha256"] == hashlib.sha256((project / source).read_bytes()).hexdigest()
    return {"fixture": name, "advance_ratio": advance_ratio, "ct": ct, "cp": cp,
            "thrust_n": thrust, "shaft_power_w": shaft_power, "thrust_work_w": work,
            "efficiency": work / shaft_power, "power_deficit_w": work - shaft_power,
            "ideal_axial_disk_w": ideal_disk,
            "scope": ("normal setup, initial component point and accepted tick; oblique flow, not integrated work"
                      if natural else "axis-aligned component, accepted constructed checkpoint and tick; not integrated work")}


def interior_interval_oracle() -> dict:
    ct = [[0.2, 0.005], [0.8, 0.0035]]
    cp = [[0.2, 0.00108], [0.8, 0.00282]]
    def ideal_cp(j: float) -> float:
        lift = linear(ct, j)
        return lift * (j + math.sqrt(j*j + 8*lift/math.pi)) / 2
    endpoints = [linear(cp, j) - ideal_cp(j) for j in (0.2, 0.8)]
    middle = linear(cp, 0.5) - 0.5 * linear(ct, 0.5)
    assert all(g > 0.0 for g in endpoints) and middle < 0.0
    return {"scope": "independent validator-design example, no complete-aircraft admission claim",
            "ct": ct, "cp": cp, "endpoint_ideal_disk_margins": endpoints,
            "interior_J": 0.5, "interior_power_margin": middle,
            "implication": "even ideal-disk-admissible knots do not certify linear interpolants"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flap-log", type=Path, required=True)
    parser.add_argument("--power-log", type=Path, required=True)
    parser.add_argument("--trim-log", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    args = parser.parse_args()
    result = {"flap": flap_oracle(args.flap_log),
              "propeller_minimal": propeller_oracle(args.power_log, args.project, False),
              "propeller_normal_trim": propeller_oracle(args.trim_log, args.project, True),
              "interpolation": interior_interval_oracle(), "ok": True}
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
