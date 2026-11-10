"""BL-02: generate the accepted `openrc-airship v1` data for the generic RC blimp.

Inputs (authoritative):
  assets/aircraft/rc-blimp-5m/geometry.json      measured from the owner's model (Blender exporter)
  research/rc-airship/design/rc-blimp-5m.json     authored engineering estimates and design choices
Output:
  app/data/airships/rc-blimp-5m.json              runtime data read by app/physics/airship/airship_data.gd

Usage: python research/rc-airship/build_data.py [--check]
--check regenerates in memory and fails if the committed output differs. Also prints the static lift budget.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GEOMETRY = ROOT / "assets/aircraft/rc-blimp-5m/geometry.json"
DESIGN = ROOT / "research/rc-airship/design/rc-blimp-5m.json"
OUTPUT = ROOT / "app/data/airships/rc-blimp-5m.json"
RHO_REFERENCE = 1.225
GRAVITY = 9.80665
ROTOR_IDS = ["port", "starboard", "stern_axial", "stern_lateral"]
VECTOR_FOR_ROTOR = {"port": "port", "starboard": "starboard", "stern_axial": "stern", "stern_lateral": ""}
GLB_NODES = {
    "vector_port": "vector_port_hinge", "vector_starboard": "vector_starboard_hinge", "vector_stern": "vector_stern_hinge",
    "fin_dorsal": "rudder_dorsal_hinge", "fin_port": "fin_port_hinge", "fin_starboard": "fin_starboard_hinge",
    "rotor_port": "rotor_port", "rotor_starboard": "rotor_starboard",
    "rotor_stern_axial": "rotor_stern_axial", "rotor_stern_lateral": "rotor_stern_lateral",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def q(value, unit: str, kind: str, source: str) -> dict:
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def measured(value, unit: str, what: str) -> dict:
    return q(value, unit, "measured", f"{what}; geometry.json measured from the owner's model scaled to a 5.0 m envelope")


def r6(v):
    if isinstance(v, list):
        return [r6(x) for x in v]
    return round(float(v), 6)


def unit(v):
    n = math.sqrt(sum(x * x for x in v))
    return [x / n for x in v]


def add(a, b):
    return [a[i] + b[i] for i in range(3)]


def rotate_about(v, k, angle):
    c, s = math.cos(angle), math.sin(angle)
    kv = [k[1] * v[2] - k[2] * v[1], k[2] * v[0] - k[0] * v[2], k[0] * v[1] - k[1] * v[0]]
    kd = sum(k[i] * v[i] for i in range(3)) * (1.0 - c)
    return [v[i] * c + kv[i] * s + k[i] * kd for i in range(3)]


def resample(profile: list, count: int) -> list:
    """Linear resampling of the nose-to-tail [x, r] profile at `count` equally spaced stations (ends kept)."""
    x0, x1 = profile[0][0], profile[-1][0]
    out = []
    j = 0
    for i in range(count):
        x = x0 + (x1 - x0) * i / (count - 1)
        while j < len(profile) - 2 and profile[j + 1][0] > x:
            j += 1
        (xa, ra), (xb, rb) = profile[j], profile[j + 1]
        f = 0.0 if xa == xb else (x - xa) / (xb - xa)
        out.append([x, max(0.0, ra + f * (rb - ra))])
    return out


def anchors(geometry: dict) -> dict:
    out = {}
    g = geometry["gondola"]
    out["gondola_center"] = [(g["min_m"][i] + g["max_m"][i]) / 2.0 for i in range(3)]
    for rotor_id in ROTOR_IDS:
        out["rotor:" + rotor_id] = geometry["rotors"][rotor_id]["hub_m"]
    for vector_id, v in geometry["vectors"].items():
        out["vector:" + vector_id] = v["pivot_m"]
    hinges = []
    for fin_id, f in geometry["fins"].items():
        out["fin:" + fin_id] = f["centroid_m"]
        hinges.append(f["hinge_point_m"])
    out["fin_hinges_mean"] = [sum(h[i] for h in hinges) / len(hinges) for i in range(3)]
    gear = [geometry["gear"][k]["contact_point_m"] for k in ("front", "rear")]
    out["gear_mean"] = [sum(p[i] for p in gear) / 2.0 for i in range(3)]
    return out


def build() -> tuple[dict, dict]:
    geometry = json.loads(GEOMETRY.read_text(encoding="utf-8"))
    design = json.loads(DESIGN.read_text(encoding="utf-8"))
    env = geometry["envelope"]
    a = anchors(geometry)
    measured_profile = sorted(([float(x), float(r)] for x, r in env["radius_profile"]), key=lambda p: -p[0])
    profile = resample(measured_profile, 41)
    data = {
        "format": "openrc-airship v1",
        "id": design["id"],
        "name": design["name"],
        "status": "experimental",
        "provenance": {
            "generator": "research/rc-airship/build_data.py",
            "geometry_sha256": sha256(GEOMETRY),
            "design_sha256": sha256(DESIGN),
            "notes": design["notes"],
        },
        "envelope": {
            "length": measured(r6(env["envelope_length_m"] if "envelope_length_m" in env else geometry["envelope_length_m"]), "m", "Envelope length (5.0 m by definition)"),
            "max_diameter": measured(r6(env["max_diameter_m"]), "m", "Maximum envelope diameter"),
            "volume": measured(r6(env["volume_m3"]), "m^3", "Closed envelope volume"),
            "centroid": measured(r6(env["centroid_m"]), "m", "Envelope volume centroid (centre of buoyancy)"),
            "surface_area": measured(r6(env["surface_area_m2"]), "m^2", "Envelope surface area"),
            "areal_mass": design["envelope_areal_mass"],
            "radius_profile": measured(r6(profile), "m", "Equivalent radius sqrt(A/pi) of envelope cross-sections"),
        },
        "gas": design["gas"],
        "hull_aero": design["hull_aero"],
        "added_mass": design["added_mass"],
        "fins": [],
        "gondola": {
            "min": measured(r6(geometry["gondola"]["min_m"]), "m", "Gondola bounds"),
            "max": measured(r6(geometry["gondola"]["max_m"]), "m", "Gondola bounds"),
            "drag_coefficient": design["gondola_drag_coefficient"],
        },
        "vectors": [],
        "rotors": [],
        "battery": design["battery"],
        "masses": [],
        "ballast": {},
        "contacts": {},
        "mixer": dict(design["mixer"]),
    }
    fd = design["fins"]
    for fin_id in ("dorsal", "port", "starboard"):
        f = geometry["fins"][fin_id]
        normal = unit(f["normal"])
        te = f["te_dir_at_plus_10deg"]
        te_sign = 1.0 if sum(te[i] * normal[i] for i in range(3)) >= 0.0 else -1.0
        span_dir = unit(f["span_dir"])
        # Remove any residual non-orthogonality between the measured span and normal.
        dot = sum(span_dir[i] * normal[i] for i in range(3))
        span_dir = unit([span_dir[i] - dot * normal[i] for i in range(3)])
        data["fins"].append({
            "id": fin_id,
            "area_fixed": measured(r6(f["fixed_area_m2"]), "m^2", f"Fin {fin_id} fixed planform"),
            "area_moving": measured(r6(f["moving_area_m2"]), "m^2", f"Fin {fin_id} moving planform"),
            "centroid": measured(r6(f["centroid_m"]), "m", f"Fin {fin_id} planform centroid"),
            "normal": measured(r6(normal), "1", f"Fin {fin_id} plane normal"),
            "span_dir": measured(r6(span_dir), "1", f"Fin {fin_id} span direction"),
            "span": measured(r6(f["span_m"]), "m", f"Fin {fin_id} span"),
            "mean_chord": measured(r6(f["mean_chord_m"]), "m", f"Fin {fin_id} mean chord"),
            "te_sign": q(te_sign, "1", "derived", f"Sign of the trailing-edge displacement along the normal for +CTRL (geometry te_dir_at_plus_10deg)"),
            "travel": fd["travel"],
            "servo_response_time": fd["servo_response_time"],
            "servo_max_rate": fd["servo_max_rate"],
            "lift_slope_scale": fd["lift_slope_scale"],
            "skin_drag_coefficient": fd["skin_drag_coefficient"],
            "crossflow_drag_coefficient": fd["crossflow_drag_coefficient"],
        })
    for vector_id in ("port", "starboard", "stern"):
        v = geometry["vectors"][vector_id]
        spec = design["vectors"]["stern" if vector_id == "stern" else "side"]
        data["vectors"].append({
            "id": vector_id,
            "pivot": measured(r6(v["pivot_m"]), "m", f"Vector {vector_id} pivot"),
            "axis": measured(r6(unit(v["axis"])), "1", f"Vector {vector_id} rotation axis (positive CTRL right-handed)"),
            "travel": measured(r6(v["travel_deg"]), "deg", f"Vector {vector_id} rig travel"),
            "servo_response_time": spec["servo_response_time"],
            "servo_max_rate": spec["servo_max_rate"],
        })
    rd = design["rotors"]
    for rotor_id in ROTOR_IDS:
        r = geometry["rotors"][rotor_id]
        spec = rd[rotor_id]
        slip = unit(r["axis_rest"])
        thrust = [-x for x in slip]
        data["rotors"].append({
            "id": rotor_id,
            "vector": VECTOR_FOR_ROTOR[rotor_id],
            "hub": measured(r6(r["hub_m"]), "m", f"Rotor {rotor_id} hub"),
            "thrust_axis_rest": q(r6(thrust), "1", "derived", f"Opposite of the measured slipstream axis of rotor {rotor_id} at vector 0"),
            "radius": measured(r6(r["radius_m"]), "m", f"Rotor {rotor_id} blade-tip radius"),
            "rotation_sense": q(spec["rotation_sense"], "1", "design", rd["source"]),
            "static_thrust_max": q(spec["static_thrust_max"], "N", "estimate", rd["source"]),
            "pitch_speed": q(spec["pitch_speed"], "m/s", "estimate", rd["source"]),
            "reverse_efficiency": q(spec["reverse_efficiency"], "1", "estimate", rd["source"]),
            "torque_ratio": q(spec["torque_ratio"], "m", "estimate", rd["source"]),
            "max_shaft_power": q(spec["max_shaft_power"], "W", "estimate", rd["source"]),
            "motor_efficiency": q(spec["motor_efficiency"], "1", "estimate", rd["source"]),
            "response_time": q(spec["response_time"], "s", "estimate", rd["source"]),
        })
    for item in design["masses"]:
        position = add(a[item["anchor"]], item["offset"])
        data["masses"].append({"id": item["id"], "mass": q(item["mass"], "kg", "estimate", item["source"]),
            "position": q(r6(position), "m", "derived", f"Anchor {item['anchor']} + design offset")})
    b = design["ballast"]
    data["ballast"] = {"position": q(r6(add(a[b["anchor"]], b["offset"])), "m", "derived", f"Anchor {b['anchor']} + design offset"),
        "max_mass": b["max_mass"], "default_heaviness": b["default_heaviness"]}
    c = design["contacts"]
    gear = []
    for gear_id in ("front", "rear"):
        g = geometry["gear"][gear_id]
        gear.append({"id": gear_id, "point": measured(r6(g["contact_point_m"]), "m", f"{gear_id} wheel lowest point"),
            "stiffness": c["gear_stiffness"], "damping": c["gear_damping"], "mu_roll": c["gear_mu_roll"], "mu_side": c["gear_mu_side"]})
    hull_points, prop_points = [], []
    for w in geometry["collision_witnesses"]:
        if w["part"].startswith("gear"):
            continue  # the wheels are their own compliant gear contacts; never count them twice
        (prop_points if w["part"].startswith("prop") or w["part"].startswith("rotor") else hull_points).append(r6(w["point_m"]))
    data["contacts"] = {"gear": gear,
        "hull_points": measured(hull_points[:64], "m", "Envelope, fin and gondola collision witnesses"),
        "prop_points": measured(prop_points[:64], "m", "Propeller disc extremes at vector 0"),
        "hull_stiffness": c["hull_stiffness"], "hull_damping": c["hull_damping"], "hull_mu": c["hull_mu"],
        "impact_speed_limit": c["impact_speed_limit"]}
    # Stern vector on pitch: use the stern vector on the stick direction whose thrust at full travel pushes the
    # tail down (+z, nose up) for back stick; derived from the measured rig.
    stern = geometry["vectors"]["stern"]
    axial = geometry["rotors"]["stern_axial"]
    full = rotate_about([-x for x in unit(axial["axis_rest"])], unit(stern["axis"]), math.radians(stern["travel_deg"][1]))
    data["mixer"]["stern_vector_on_pitch"] = q(1.0 if full[2] > 0.0 else -1.0, "1", "derived",
        "+1: stern thrust at full vector points down (back stick, nose up); -1: up (forward stick, nose down)")
    data["presentation"] = {
        "frame": "GLB in Godot axes (nose -Z, right +X, up +Y), origin = physics datum O",
        "bindings": {},
        "disc_radius": {},
    }
    nodes = {n["name"]: n for n in geometry["glb_nodes"]} if isinstance(geometry["glb_nodes"], list) else geometry["glb_nodes"]
    for key, node_name in GLB_NODES.items():
        node = nodes[node_name]
        data["presentation"]["bindings"][key] = {"node": node_name, "local_axis": r6(unit(node["local_axis"])), "sign": 1.0}
    for rotor_id in ROTOR_IDS:
        data["presentation"]["disc_radius"]["rotor_" + rotor_id] = r6(geometry["rotors"][rotor_id]["radius_m"])
    report = budget(data)
    report.update(trim_ballast(data, design["ballast"]["trim_range_x"], report["ballast_for_default_kg"]))
    return data, report


def trim_ballast(data: dict, trim_range: dict, ballast_kg: float) -> dict:
    """Slide the ballast along its keel line so the default weigh-off puts the CG under the CB (zero static pitch).

    Mirrors the reader: helium and shell are distributed over the profile strips shifted to the measured CB.
    """
    env = data["envelope"]
    profile = env["radius_profile"]["value"]
    cb_x = env["centroid"]["value"][0]
    strips = []
    raw_v = raw_x = shell_len = 0.0
    for (x0, r0), (x1, r1) in zip(profile, profile[1:]):
        dx = abs(x1 - x0)
        vol = math.pi * 0.5 * (r0 * r0 + r1 * r1) * dx
        ring = 2.0 * math.pi * 0.5 * (r0 + r1) * math.hypot(dx, r1 - r0)
        strips.append((0.5 * (x0 + x1), vol, ring))
        raw_v += vol
        raw_x += vol * 0.5 * (x0 + x1)
        shell_len += ring
    shift = cb_x - raw_x / raw_v
    gas = data["gas"]["density"]["value"] * env["volume"]["value"] * data["gas"]["fill_fraction"]["value"]
    shell = env["areal_mass"]["value"] * env["surface_area"]["value"]
    mass = moment = 0.0
    for xm, vol, ring in strips:
        piece = gas * vol / raw_v + shell * ring / shell_len
        mass += piece
        moment += piece * (xm + shift)
    for item in data["masses"]:
        mass += item["mass"]["value"]
        moment += item["mass"]["value"] * item["position"]["value"][0]
    lo, hi = trim_range["value"]
    wanted = (cb_x * (mass + ballast_kg) - moment) / ballast_kg
    x = min(max(wanted, lo), hi)
    position = data["ballast"]["position"]["value"]
    data["ballast"]["position"] = q(r6([x, position[1], position[2]]), "m", "derived",
        f"Keel position solved by build_data.py for CG under CB at the default weigh-off (requested x {wanted:.3f} m, keel range {lo}..{hi} m)")
    cg_x = (moment + ballast_kg * x) / (mass + ballast_kg)
    return {"ballast_x_m": x, "ballast_x_requested_m": wanted, "cg_x_m": cg_x, "cb_x_m": cb_x, "trim_residual_m": cg_x - cb_x}


def budget(data: dict) -> dict:
    volume = data["envelope"]["volume"]["value"]
    shell = data["envelope"]["areal_mass"]["value"] * data["envelope"]["surface_area"]["value"]
    gas = data["gas"]["density"]["value"] * volume * data["gas"]["fill_fraction"]["value"]
    items = sum(m["mass"]["value"] for m in data["masses"])
    displaced = RHO_REFERENCE * volume
    ballast_neutral = displaced - shell - gas - items
    return {"volume_m3": volume, "displaced_kg": displaced, "helium_kg": gas, "envelope_kg": shell, "items_kg": items,
        "ballast_for_neutral_kg": ballast_neutral,
        "ballast_for_default_kg": ballast_neutral + data["ballast"]["default_heaviness"]["value"],
        "max_ballast_kg": data["ballast"]["max_mass"]["value"]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data, report = build()
    text = json.dumps(data, indent=1, ensure_ascii=False) + "\n"
    print(json.dumps(report, indent=1))
    if report["ballast_for_neutral_kg"] < 0.05 or report["ballast_for_default_kg"] > report["max_ballast_kg"] \
            or abs(report["trim_residual_m"]) > 0.02:
        print("lift budget infeasible: adjust the design inventory", file=sys.stderr)
        return 2
    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != text:
            print(f"{OUTPUT.relative_to(ROOT)} is stale; regenerate", file=sys.stderr)
            return 1
        print("up to date")
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
