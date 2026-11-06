#!/usr/bin/env python3
"""Source-derived Extra 300S reference arithmetic; no simulator runs or tuning.

Usage: python3 calculate_extra.py [--source-root /path/to/checkout] [--out /path/result.json]
The default output is next to this script, and the default input is the audited
round-2 checkout. The hashes in the result bind every inspected source file.
"""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path


HERE = Path(__file__).resolve().parent
DEFAULT_SOURCE = HERE.parents[1] / "round2" / "source"
OZ_IN_KG = 0.028349523125
FEET_IN_M = 0.3048
KINEMATIC_VISCOSITY_M2_S = 1.5e-5  # explicit illustrative assumption


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def constant(text, name):
    match = re.search(r"^const " + re.escape(name) + r"\s*:=\s*([0-9.]+)\s*$", text, re.M)
    if not match:
        raise ValueError(f"Cannot resolve GDScript {name}")
    return float(match.group(1))


def calculate(root):
    paths = {
        "aircraft": "app/data/aircraft/gp_extra_300s_60.json",
        "geometry": "assets/aircraft/extra-300s-60/geometry.json",
        "fuel_registry": "app/data/fuels/openrc-fuel-registry.json",
        "live_app": "app/main.gd",
        "session": "app/sim/flight_session.gd",
        "commands": "app/input/commands.gd",
        "controller_profile": "app/input/controller_profile.gd",
        "simulation": "app/sim/simulation.gd",
        "atmosphere": "app/physics/atmosphere.gd",
    }
    hashes = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in paths.values()}
    aircraft = read_json(root / paths["aircraft"])
    geometry = read_json(root / paths["geometry"])
    registry = read_json(root / paths["fuel_registry"])
    app = (root / paths["live_app"]).read_text(encoding="utf-8")
    session = (root / paths["session"]).read_text(encoding="utf-8")
    profile = (root / paths["controller_profile"]).read_text(encoding="utf-8")
    simulation = (root / paths["simulation"]).read_text(encoding="utf-8")
    atmosphere = (root / paths["atmosphere"]).read_text(encoding="utf-8")
    app_match = re.search(r'var rates := str\(args\.get\("rates",\s*"([^"]+)"\)\)', app)
    technical_match = re.search(r'^var rate_profile\s*:=\s*"([^"]+)"', session, re.M)
    if not app_match or not technical_match:
        raise ValueError("Could not resolve app and technical rate defaults")
    if (app_match.group(1), technical_match.group(1)) != ("sport", "full"):
        raise ValueError("Rate defaults changed; inspect profile semantics before using this calculation")
    gravity_match = re.search(r"^var gravity\s*:=\s*([0-9.]+)\s*$", simulation, re.M)
    density_match = re.search(r"^const SEA_LEVEL_DENSITY_KGM3:\s*float\s*=\s*([0-9.]+)\s*$", atmosphere, re.M)
    if not gravity_match or not density_match:
        raise ValueError("Cannot resolve gravity or reference density")
    gravity = float(gravity_match.group(1))
    air_density = float(density_match.group(1))

    tanks = aircraft["fuel_system"]["tanks"]
    if len(tanks) != 1:
        raise ValueError("This calculation is limited to the stock single-tank Extra")
    tank = tanks[0]
    inventory = aircraft["inventory"]
    liquid_id = tank["liquid_inventory_id"]
    matches = [item for item in inventory if item["id"] == liquid_id]
    if len(matches) != 1:
        raise ValueError("Main tank liquid inventory is not unique")
    if any(item["mass"]["unit"] != "kg" for item in inventory):
        raise ValueError("Unexpected inventory mass units")
    if tank["capacity"]["unit"] != "l":
        raise ValueError("Unexpected tank capacity unit")
    blend = registry["blends"][tank["fuel"]]
    fractions = blend["volume_fractions"]
    if not math.isclose(math.fsum(fractions.values()), 1.0, abs_tol=1e-12):
        raise ValueError("Fuel blend fractions do not sum to one")
    density = math.fsum(float(fraction) * float(registry["components"][component]["density"]["value"])
                        for component, fraction in fractions.items())
    capacity_fuel = float(tank["capacity"]["value"]) * 0.001 * density
    reference_fuel = float(matches[0]["mass"]["value"])
    if not math.isclose(capacity_fuel, reference_fuel, rel_tol=1e-12, abs_tol=1e-15):
        raise ValueError("Reference liquid inventory and capacity are not the same full tank")
    dry = math.fsum(float(item["mass"]["value"]) for item in inventory if item["id"] != liquid_id)
    full = dry + capacity_fuel
    quarter = dry + 0.25 * capacity_fuel
    reference = aircraft["reference"]
    area = float(reference["wing_area"]["value"])
    span = float(reference["wing_span"]["value"])
    root_chord = float(reference["root_chord"]["value"])
    tip_chord = float(reference["tip_chord"]["value"])
    taper = tip_chord / root_chord
    mac = (2.0 / 3.0) * root_chord * (1.0 + taper + taper * taper) / (1.0 + taper)
    if not math.isclose(mac, float(geometry["wing"]["reference"]["mac"]), abs_tol=0.0001):
        raise ValueError("Derived MAC disagrees with the geometry reference")

    controls = aircraft["controls"]
    expo = constant(profile, "DEFAULT_EXPO")
    deadzone = constant(profile, "DEFAULT_DEADZONE")
    out_controls = {}
    for axis in ("aileron", "elevator", "rudder"):
        maximum = float(controls["max_throw"][axis]["value"])
        normal_fraction = float(controls["rates"]["normal"][axis]["value"])
        model_expo = float(controls["rates"]["normal"][axis + "_expo"]["value"])
        sport_fraction = 1.0 if axis == "aileron" else normal_fraction
        device_field = {"aileron": None, "elevator": "pitch_scale", "rudder": "yaw_scale"}[axis]
        device_scale = float(controls.get("gamepad", {}).get(device_field, {}).get("value", 1.0)) if device_field else 1.0
        edge_gain = (1.0 - expo) / (1.0 - deadzone)
        out_controls[axis] = {
            "max_throw_deg": maximum,
            "normal_rate_fraction": normal_fraction,
            "normal_max_throw_deg": maximum * normal_fraction,
            "sport_max_throw_deg": maximum * sport_fraction,
            "gamepad_device_scale": device_scale,
            "normal_aircraft_expo": model_expo,
            "aircraft_expo_center_derivative": 1.0 - model_expo,
            "keyboard_or_joystick_sport_center_derivative_deg_per_unit": maximum * sport_fraction * (1.0 - model_expo),
            "keyboard_or_joystick_normal_center_derivative_deg_per_unit": maximum * normal_fraction * (1.0 - model_expo),
            "default_gamepad_sport_derivative_just_outside_deadzone_deg_per_unit": maximum * sport_fraction * device_scale * edge_gain,
            "default_gamepad_normal_derivative_just_outside_deadzone_deg_per_unit": maximum * normal_fraction * device_scale * edge_gain,
        }
    oz_per_sqft_per_kg_per_m2 = FEET_IN_M ** 2 / OZ_IN_KG
    return {
        "format": "extra-300s-source-math-v1",
        "aircraft_id": aircraft["id"],
        "source_sha256": hashes,
        "interpretation": "Algebra from authored model inputs only; no flight run or measured handling target.",
        "assumptions": {
            "kinematic_viscosity_m2_s": KINEMATIC_VISCOSITY_M2_S,
            "reference_air_density_kg_m3": air_density,
            "gravity_m_s2": gravity,
            "stall_ratio": "level, same density, area, CLmax and power effects",
            "knife_edge": "idealized 90-degree steady-level force balance; side force alone supports weight, no vertical thrust or wing lift",
            "rate_slopes": "zero trim, unsaturated steady commands; no servo dynamics or device response lag",
            "fuel": "one reference-full main tank, no separate line, fixed dry inventory",
        },
        "geometry": {"wing_area_m2": area, "wing_span_m": span,
                     "coefficient_reference_chord_m": float(reference["mean_chord"]["value"]),
                     "mac_m_from_tapered_wing": mac,
                     "mac_m_geometry_rounded": float(geometry["wing"]["reference"]["mac"])},
        "mass_kg": {"dry_empty_tank": dry, "full_tank": full, "quarter_tank": quarter,
                    "full_fuel": capacity_fuel, "quarter_fuel": 0.25 * capacity_fuel},
        "fuel_blend_density_kg_m3": density,
        "wing_loading_oz_per_ft2": {"dry": dry / area * oz_per_sqft_per_kg_per_m2,
                                     "full": full / area * oz_per_sqft_per_kg_per_m2,
                                     "quarter": quarter / area * oz_per_sqft_per_kg_per_m2},
        "full_over_dry_stall_speed_ratio_fixed_clmax": math.sqrt(full / dry),
        "dry_over_full_stall_speed_ratio_fixed_clmax": math.sqrt(dry / full),
        "reynolds_by_airspeed_mps_using_mac": {
            str(v): v * mac / KINEMATIC_VISCOSITY_M2_S for v in (11, 22)},
        "ideal_knife_edge_required_abs_cy_by_airspeed_mps": {
            str(v): full * gravity / (0.5 * air_density * v * v * area) for v in (15, 22)},
        "control_rates": out_controls,
        "sport_over_normal_aileron_travel_ratio": 1.0 / out_controls["aileron"]["normal_rate_fraction"],
        "default_gamepad_expo": {"expo": expo, "deadzone": deadzone,
            "expo_only_derivative_at_rescaled_center": 1.0 - expo,
            "complete_conditioner_derivative_at_raw_center": 0.0 if deadzone > 0.0 else 1.0 - expo,
            "complete_conditioner_derivative_just_outside_deadzone": (1.0 - expo) / (1.0 - deadzone)},
        "rate_profile_defaults": {"live_app": app_match.group(1), "standalone_technical_session": technical_match.group(1),
            "sport": "full aileron; normal elevator and rudder", "normal": "manual-derived low-rate travel",
            "radio_transmitter": "own transmitter shaping; simulator aircraft rate profile bypassed"},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--out", type=Path, default=HERE / "extra_source_math.json")
    args = parser.parse_args()
    result = calculate(args.source_root.resolve())
    args.out.write_text(json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
