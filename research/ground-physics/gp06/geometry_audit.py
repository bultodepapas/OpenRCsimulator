#!/usr/bin/env python3
"""GP-06 geometry audit, step 2: landing-gear design metrics from geometry_dump.gd output.

Body axes x forward, y right, z down about the inventory CG; pitch nose-up positive. Point contacts and vertical
spring loads only (no tyre forces, aerodynamics or thrust). Reference rules are full-size design guidance (Raymer,
Aircraft Design: A Conceptual Approach, ch. 11; Currey, Aircraft Landing Gear Design, ch. 3), quoted for context and
not as RC acceptance limits.

    python3 research/ground-physics/gp06/geometry_audit.py <dump.json> [--json <metrics.json>]
"""
import argparse
import json
import math

G = 9.80665


def rotate(v, theta, phi=0.0):
    """Body vector to level-earth axes (x fwd, y right, z down) after roll phi then pitch theta (nose up)."""
    x, y, z = v
    y1, z1 = y * math.cos(phi) - z * math.sin(phi), y * math.sin(phi) + z * math.cos(phi)
    return (x * math.cos(theta) + z1 * math.sin(theta), y1, -x * math.sin(theta) + z1 * math.cos(theta))


def rest(contacts, mass):
    """Static spring equilibrium: CG height h above the ground and pitch theta (Newton on force and pitch moment)."""
    mains = [c for c in contacts if c["name"].startswith("main")][0]["position"]
    other = [c for c in contacts if not c["name"].startswith("main")][0]["position"]
    theta = math.atan((mains[2] - other[2]) / (mains[0] - other[0]))
    h = min(rotate(c["position"], theta)[2] for c in contacts) - 0.01

    def residual(h, theta):
        force = moment = 0.0
        for c in contacts:
            x, _, z = rotate(c["position"], theta)
            if z > h:
                load = c["stiffness"] * (z - h)
                force += load
                moment += load * x
        return force - mass * G, moment

    for _ in range(100):
        r0 = residual(h, theta)
        e = 1e-7
        a, b = residual(h + e, theta), residual(h, theta + e)
        j = [[(a[0] - r0[0]) / e, (b[0] - r0[0]) / e], [(a[1] - r0[1]) / e, (b[1] - r0[1]) / e]]
        det = j[0][0] * j[1][1] - j[0][1] * j[1][0]
        dh = (-r0[0] * j[1][1] + r0[1] * j[0][1]) / det
        dt = (-j[0][0] * r0[1] + j[1][0] * r0[0]) / det
        h, theta = h + dh, theta + dt
        if abs(dh) < 1e-12 and abs(dt) < 1e-12:
            break
    loads = [max(0.0, c["stiffness"] * (rotate(c["position"], theta)[2] - h)) for c in contacts]
    return h, theta, loads


def disc_bottom(hub, axis, radius, theta):
    """Depth below the CG of the propeller disc's lowest point at pitch theta."""
    h, a = rotate(hub, theta), rotate(axis, theta)
    along = a[2]
    p = (-along * a[0], -along * a[1], 1.0 - along * a[2])
    length = math.sqrt(sum(v * v for v in p))
    return h[2] + radius * p[2] / length


def first_hit(hull, names, pivot, sag, theta_of, phi_of, steps):
    """First angle (deg) at which a hull point reaches the ground while the body turns about `pivot` contacts."""
    for k in range(steps):
        angle = k * 0.05
        theta, phi = theta_of(angle), phi_of(angle)
        ground = max(rotate(p, theta, phi)[2] for p in pivot) - sag
        for i in range(0, len(hull), 3):
            if rotate(hull[i:i + 3], theta, phi)[2] >= ground:
                return angle, names[i // 3] if names else str(i // 3)
    return None, None


def audit(aircraft_id, a):
    contacts, mass, hull, names = a["contacts"], a["mass_kg"], a["hull"], a["hull_components"]
    tricycle = any(c["name"] == "nose" for c in contacts)
    mains = [c for c in contacts if c["name"].startswith("main")]
    third = [c for c in contacts if not c["name"].startswith("main")][0]
    h, theta, loads = rest(contacts, mass)
    out = {"tricycle": tricycle, "mass_kg": mass, "rest_cg_height_m": h, "rest_pitch_deg": math.degrees(theta),
           "contacts": []}
    for c, n in zip(contacts, loads):
        share = n / G
        out["contacts"].append({
            "name": c["name"], "load_share": n / (mass * G), "static_sag_m": n / c["stiffness"],
            "sag_over_travel": n / c["stiffness"] / c["max_compression"],
            "zeta_on_static_share": c["damping"] / (2 * math.sqrt(c["stiffness"] * share)) if share > 0 else None,
            "frequency_hz": math.sqrt(c["stiffness"] / share) / (2 * math.pi) if share > 0 else None,
            "wheel_radius_m": c["wheel_radius"]})
    mx, mz = mains[0]["position"][0], mains[0]["position"][2]
    out["mains_angle_level_deg"] = math.degrees(math.atan2(mx, mz))  # + ahead of the CG
    xr, _, zr = rotate(mains[0]["position"], theta)
    out["mains_angle_rest_deg"] = math.degrees(math.atan2(xr, zr))
    if not tricycle:
        out["nose_over_decel_g_level"] = math.tan(math.radians(out["mains_angle_level_deg"]))
    # Overturn angle (Currey): CG height over its ground distance to the main/third-wheel edge, at rest.
    pm, pt = rotate(mains[1]["position"], theta), rotate(third["position"], theta)
    ex, ey = pt[0] - pm[0], pt[1] - pm[1]
    edge = abs(ex * (0.0 - pm[1]) - ey * (0.0 - pm[0])) / math.hypot(ex, ey)
    out["overturn_angle_deg"] = math.degrees(math.atan2(h, edge))
    clearances = sorted((h - rotate(hull[i:i + 3], theta)[2], names[i // 3] if names else str(i // 3))
                        for i in range(0, len(hull), 3))
    out["lowest_hull_clearance_at_rest"] = [{"component": n, "clearance_m": c} for c, n in clearances[:3]]
    prop = a["propeller"]
    if prop.get("diameter"):
        off = prop["offset"]
        hub, axis, radius = (-off[0], off[1], -off[2]), prop.get("axis", [1.0, 0.0, 0.0]), prop["diameter"] / 2
        out["prop_clearance_rest_m"] = h - disc_bottom(hub, axis, radius, theta)
        if not tricycle:
            sag = loads[0] / mains[0]["stiffness"]
            out["prop_clearance_tail_up_m"] = (mz - sag) - disc_bottom(hub, axis, radius, 0.0)
    sag = loads[0] / mains[0]["stiffness"]
    pivots = [c["position"] for c in mains]
    if tricycle:
        angle, part = first_hit(hull, names, pivots, sag, math.radians, lambda _: 0.0, 1200)
        out["tail_strike_pitch_deg"], out["tail_strike_part"] = angle, part
    angle, part = first_hit(hull, names, pivots, sag, lambda _: 0.0, math.radians, 1800)
    out["wingtip_strike_bank_on_mains_deg"], out["wingtip_strike_part"] = angle, part
    env, aero = a["envelope"], a["aero"]
    out["stall_onset_alpha_deg"] = math.degrees(env["a1"])
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("dump")
    parser.add_argument("--json")
    args = parser.parse_args()
    dump = json.load(open(args.dump, encoding="utf-8"))
    metrics = {k: audit(k, v) for k, v in dump["aircraft"].items()}
    for k, m in metrics.items():
        print(f"{k}: {'tricycle' if m['tricycle'] else 'taildragger'}, {m['mass_kg']:.3f} kg, rest pitch "
              f"{m['rest_pitch_deg']:+.2f} deg, CG {1000 * m['rest_cg_height_m']:.0f} mm")
        for c in m["contacts"]:
            print(f"  {c['name']:10s} load {100 * c['load_share']:5.1f} %  sag {1000 * c['static_sag_m']:5.1f} mm "
                  f"({100 * c['sag_over_travel']:3.0f} % of travel)  zeta {c['zeta_on_static_share']:.2f}  "
                  f"f {c['frequency_hz']:.1f} Hz")
        line = f"  mains {m['mains_angle_level_deg']:+.1f} deg level / {m['mains_angle_rest_deg']:+.1f} deg at rest (+ ahead)"
        if not m["tricycle"]:
            line += f"; nose-over at {m['nose_over_decel_g_level']:.2f} g tail up"
        print(line + f"; overturn {m['overturn_angle_deg']:.1f} deg")
        print("  rest clearances: " + ", ".join(f"{c['component']} {1000 * c['clearance_m']:.0f} mm"
                                                for c in m["lowest_hull_clearance_at_rest"]))
        extra = []
        if "prop_clearance_rest_m" in m:
            extra.append(f"prop {1000 * m['prop_clearance_rest_m']:.0f} mm at rest")
        if "prop_clearance_tail_up_m" in m:
            extra.append(f"{1000 * m['prop_clearance_tail_up_m']:.0f} mm tail up")
        if m["tricycle"]:
            extra.append(f"tail strike {m['tail_strike_pitch_deg']} deg ({m['tail_strike_part']})")
        extra.append(f"wingtip at {m['wingtip_strike_bank_on_mains_deg']} deg bank ({m['wingtip_strike_part']})")
        extra.append(f"stall onset alpha {m['stall_onset_alpha_deg']:.1f} deg")
        print("  " + "; ".join(extra))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump({"format": "openrc-gp06-geometry-audit v1", "aircraft": metrics}, handle, indent=2)
            handle.write("\n")


if __name__ == "__main__":
    main()
