#!/usr/bin/env python3
"""A120-00: reproducible scalar reference arithmetic; never writes aircraft data."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import tempfile


ROOT = Path(__file__).resolve().parent
INPUT = ROOT / "reference-inputs.json"
OUTPUT = ROOT / "reference-study.json"
QUANTITIES = {
    "span": "m", "wing_area": "m^2", "density": "kg/m^3",
    "kinematic_viscosity": "m^2/s", "gravity": "m/s^2",
    "prop_diameter": "m", "prop_rpm": "rpm", "prop_ct": "1",
    "prop_cp": "1", "prop_inertia": "kg*m^2", "roll_rate": "deg/s",
    "perpendicular_body_rate": "deg/s",
}
SCENARIOS = {"mass": "kg", "airspeed": "m/s", "frequency": "Hz", "delay": "ms"}
KINDS = {"manual", "borrowed", "estimated", "derived"}


def fields(obj, expected, where):
    if not isinstance(obj, dict) or set(obj) != set(expected):
        raise ValueError(f"{where}: expected exactly {sorted(expected)}")


def number(value, where, allow_zero=False):
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError(f"{where}: finite number required")
    if value < 0 or (value == 0 and not allow_zero):
        raise ValueError(f"{where}: {'nonnegative' if allow_zero else 'positive'} required")
    return value


def nonempty(value, where):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{where}: nonempty text required")


def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate key: {key}")
        result[key] = value
    return result


def load(raw):
    return json.loads(raw, object_pairs_hook=unique_keys,
                      parse_constant=lambda s: (_ for _ in ()).throw(ValueError(s)))


def validate(doc):
    fields(doc, {"format", "scope", "runtime_audit_commit", "quantities", "scenarios", "references"}, "input")
    if doc["format"] != "aeris120-reference-study-inputs v1":
        raise ValueError("unsupported input format")
    for name in ("scope", "runtime_audit_commit"):
        nonempty(doc[name], name)
    fields(doc["quantities"], QUANTITIES, "quantities")
    fields(doc["scenarios"], SCENARIOS, "scenarios")
    for group, units, key in (("quantities", QUANTITIES, "value"), ("scenarios", SCENARIOS, "values")):
        for name, unit in units.items():
            item = doc[group][name]
            fields(item, {key, "unit", "kind", "source"}, name)
            if item["unit"] != unit or not isinstance(item["kind"], str) or item["kind"] not in KINDS:
                raise ValueError(f"{name}: wrong unit or unsupported evidence kind")
            nonempty(item["source"], f"{name}.source")
            values = item[key] if key == "values" else [item[key]]
            if not isinstance(values, list) or not values:
                raise ValueError(f"{name}: nonempty list required")
            for value in values:
                number(value, name, name in {"airspeed", "delay", "roll_rate", "perpendicular_body_rate"})
            if len(set(values)) != len(values):
                raise ValueError(f"{name}: repeated scenario")
    if not isinstance(doc["references"], dict) or not doc["references"]:
        raise ValueError("references required")
    for key, value in doc["references"].items():
        nonempty(key, "reference id")
        nonempty(value, key)


def group(values, inputs, limitation):
    return {"kind": "derived", "evidence": "illustrative_algebra",
            "input_keys": inputs, "limitation": limitation, "values": values}


def calculate(doc):
    validate(doc)
    q = {name: item["value"] for name, item in doc["quantities"].items()}
    s = {name: item["values"] for name, item in doc["scenarios"].items()}
    b, area, rho = q["span"], q["wing_area"], q["density"]
    chord, diameter, n = area / b, q["prop_diameter"], q["prop_rpm"] / 60
    omega = 2 * math.pi * n
    disc_area = math.pi * diameter ** 2 / 4
    thrust = q["prop_ct"] * rho * n ** 2 * diameter ** 4
    power = q["prop_cp"] * rho * n ** 3 * diameter ** 5
    torque = power / omega
    vi = math.sqrt(thrust / (2 * rho * disc_area))
    h = q["prop_inertia"] * omega
    geometry = group({"reference_chord_m": chord, "aspect_ratio": b ** 2 / area,
                      "disc_area_m2": disc_area, "diameter_to_span": diameter / b},
                     ["span", "wing_area", "prop_diameter"],
                     "S/b is a coefficient reference chord, not measured MAC. Diameter/span is not washed area.")
    prop = group({"rpm": q["prop_rpm"], "thrust_n": thrust, "shaft_power_w": power,
                  "shaft_torque_nm": torque, "ideal_disc_speed_m_s": vi,
                  "ideal_far_wake_speed_m_s": 2 * vi,
                  "ideal_far_wake_radius_m": diameter / (2 * math.sqrt(2)),
                  "ideal_disc_power_w": thrust * vi,
                  "prop_angular_momentum_nms": h,
                  "prop_spin_energy_j": 0.5 * q["prop_inertia"] * omega ** 2,
                  "gyro_coupling_magnitude_nm": math.radians(q["perpendicular_body_rate"]) * h},
                 ["density", "prop_diameter", "prop_rpm", "prop_ct", "prop_cp", "prop_inertia", "perpendicular_body_rate"],
                 "Arithmetic at the supplied Ct/Cp, RPM, diameter and density, not an installed engine run. Source strings are declarations: edited values are not authenticated by this calculator. Transferring coefficients across RPM or propellers requires separate evidence. Ideal steady open-flow disc/far-wake quantities exclude swirl and installation; neither predicts wing/tail velocity. Prop-only inertia excludes other rotating parts. Gyro is a coupling term for the specified perpendicular body rate, not net moment or angular acceleration.")
    mass_rows = []
    for mass in s["mass"]:
        weight = mass * q["gravity"]
        rpm_balance = q["prop_rpm"] * math.sqrt(weight / thrust)
        mass_rows.append({"mass_kg": mass, "wing_loading_kg_m2": mass / area,
                          "reference_point_thrust_to_weight": thrust / weight,
                          "constant_ct_balance_rpm": rpm_balance})
    masses = group(mass_rows, ["mass", "wing_area", "gravity", "density", "prop_diameter", "prop_ct", "prop_rpm"],
                   "Chosen mass cases, not weighed AERIS. Constant-Ct T=mg uses the supplied coefficient at every RPM without a validated RPM range; no engine torque balance, installed RPM, control authority, hover margin or stability is established.")
    flow_rows = []
    for speed in s["airspeed"]:
        flow_rows.append({"speed_m_s": speed, "reynolds_reference_chord": speed * chord / q["kinematic_viscosity"],
                          "dynamic_pressure_pa": 0.5 * rho * speed ** 2,
                          "reference_chord_advection_s": chord / speed if speed else None,
                          "roll_reduced_rate": math.radians(q["roll_rate"]) * b / (2 * speed) if speed else None,
                          "pitch_reduced_rate": math.radians(q["perpendicular_body_rate"]) * chord / (2 * speed) if speed else None,
                          "axial_advance_ratio": speed / (n * diameter)})
    flow = group(flow_rows, ["airspeed", "span", "wing_area", "density", "kinematic_viscosity", "roll_rate", "perpendicular_body_rate", "prop_rpm", "prop_diameter"],
                 "Uniform reference-speed arithmetic only. Reduced rates/advection are undefined at zero speed and retained as null. Pitch row treats the chosen perpendicular rate as pitch. J assumes shaft-aligned forward inflow; no Ct/Cp extrapolation along J or near-hover aerodynamic prediction is made.")
    delay = group([{"frequency_hz": f, "delay_ms": d, "phase_deg": -360 * f * d / 1000}
                   for f in s["frequency"] for d in s["delay"]], ["frequency", "delay"],
                  "Phase of an isolated linear pure delay for chosen sinusoids; not full control-loop phase, measured latency, pilot bandwidth or an acceptance budget.")
    return {"format": "aeris120-reference-study-result v1", "physical_acceptance": False,
            "aircraft_data_export": False, "geometry": geometry, "static_prop_reference": prop,
            "mass_sensitivity": masses, "reference_flow": flow, "pure_delay": delay}


def report(raw):
    doc = load(raw)
    result = calculate(doc)
    result["inputs"] = doc
    result["identity"] = {"input_sha256": hashlib.sha256(raw).hexdigest(),
                          "calculator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    return (json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", action="store_true", help="compare the stored research result with recomputation")
    modes.add_argument("--write", action="store_true", help="regenerate only reference-study.json beside this script")
    args = parser.parse_args()
    try:
        encoded = report(INPUT.read_bytes())
        if args.check:
            if not OUTPUT.exists() or OUTPUT.read_bytes() != encoded:
                raise ValueError("reference-study.json is missing or stale; inspect inputs, then regenerate with --write")
            print("Reference arithmetic and identities match; no physical validation claimed.")
        elif args.write:
            if OUTPUT.is_symlink() or (OUTPUT.exists() and (os.path.samefile(OUTPUT, INPUT) or os.path.samefile(OUTPUT, Path(__file__)))):
                raise ValueError("refusing an output alias")
            with tempfile.NamedTemporaryFile(dir=ROOT, prefix=".reference-", delete=False) as stream:
                temporary = Path(stream.name)
                try:
                    stream.write(encoded)
                    stream.close()
                    temporary.replace(OUTPUT)
                finally:
                    temporary.unlink(missing_ok=True)
            print("Wrote reference-study.json (illustrative algebra only).")
        else:
            sys.stdout.buffer.write(encoded)
    except (ValueError, OSError, OverflowError, ZeroDivisionError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
