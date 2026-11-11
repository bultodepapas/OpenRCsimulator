#!/usr/bin/env python3
"""DR-10/11/13: deterministic generator of the experimental openrc-fpv5 x1 candidate (openrc-multirotor v1).

Reads sources.json (manufacturer-reported, estimated and borrowed inputs), derives the static rotor/motor fit,
the mass/CG/locked inertia, geometry, hover balance, contact constants and diagnostics, and writes one strict
JSON document. Standard library only; output is byte-deterministic (sorted keys, repr floats, LF, UTF-8).

    python derive.py                 write the candidate to app/data/multirotors/openrc-fpv5-x1.json
    python derive.py --out PATH      write it elsewhere
    python derive.py --check         regenerate in memory and compare with the existing file; never writes

Nothing here is measured by this project. The numbers are estimates and vendor rows, not a validated aircraft.
"""
import argparse
import hashlib
import json
import math
import os
import sys

GENERATOR = "research/drone-racing/openrc-fpv5-x1/derive.py"
GENERATOR_VERSION = "1"
FORMAT = "openrc-multirotor v1"
G0 = 9.80665  # standard gravity, the same constant as the multirotor plant
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
SOURCES = os.path.join(HERE, "sources.json")
DEFAULT_OUT = os.path.join(ROOT, "app", "data", "multirotors", "openrc-fpv5-x1.json")
RPM_TO_RAD_S = 2.0 * math.pi / 60.0
# Betaflight quad-X order: 1 rear-right, 2 front-right, 3 rear-left, 4 front-left; spin +1 = CCW from above.
ROTOR_LAYOUT = [(1, -1.0, 1.0, -1), (2, 1.0, 1.0, 1), (3, -1.0, -1.0, 1), (4, 1.0, -1.0, -1)]


def q(value, unit, kind, note):
    return {"value": value, "unit": unit, "kind": kind, "source": "%s: %s" % (kind, note)}


def src(entry):
    return q(entry["value"], entry["unit"], entry["class"], entry["note"])


def solve4(a, b):
    """Gaussian elimination with partial pivoting (the loader uses the same order)."""
    m = [list(a[r]) + [b[r]] for r in range(4)]
    for c in range(4):
        p = c
        for r in range(c + 1, 4):
            if abs(m[r][c]) > abs(m[p][c]):
                p = r
        m[c], m[p] = m[p], m[c]
        for r in range(c + 1, 4):
            f = m[r][c] / m[c][c]
            for k in range(c, 5):
                m[r][k] -= f * m[c][k]
    x = [0.0] * 4
    for r in range(3, -1, -1):
        s = m[r][4]
        for k in range(r + 1, 4):
            s -= m[r][k] * x[k]
        x[r] = s / m[r][r]
    return x


def static_speed(d, volts, kv, r, i0, kq):
    """Kt*((d*V - w/Kv)/R - I0) = kQ*w^2 with Kt = 1/Kv; the nonnegative root."""
    kt = 1.0 / kv
    b = kt / (kv * r)
    c = kt * (d * volts / r - i0)
    if c <= 0.0:
        return 0.0
    return (-b + math.sqrt(b * b + 4.0 * kq * c)) / (2.0 * kq)


def own_inertia(mass, shape):
    t = shape["type"]
    if t == "point":
        return [0.0] * 6
    if t == "box":
        a, b, c = shape["size"]["value"]
        return [mass * (b * b + c * c) / 12.0, mass * (a * a + c * c) / 12.0, mass * (a * a + b * b) / 12.0, 0.0, 0.0, 0.0]
    if t == "axisymmetric_z":
        tr = shape["transverse_inertia"]["value"]
        return [tr, tr, shape["axial_inertia"]["value"], 0.0, 0.0, 0.0]
    raise ValueError("unknown shape " + t)


def mass_properties(components):
    """Total mass, CG from the datum and the locked inertia about the CG ([Jxx, Jyy, Jzz, Jxy, Jxz, Jyz] matrix entries)."""
    mass = 0.0
    first = [0.0, 0.0, 0.0]
    for c in components:
        m = c["mass"]["value"]
        p = c["position"]["value"]
        mass += m
        for k in range(3):
            first[k] += m * p[k]
    cg = [first[0] / mass, first[1] / mass, first[2] / mass]
    j = [0.0] * 6
    for c in components:
        m = c["mass"]["value"]
        p = c["position"]["value"]
        o = own_inertia(m, c["shape"])
        dx, dy, dz = p[0] - cg[0], p[1] - cg[1], p[2] - cg[2]
        j[0] += o[0] + m * (dy * dy + dz * dz)
        j[1] += o[1] + m * (dx * dx + dz * dz)
        j[2] += o[2] + m * (dx * dx + dy * dy)
        j[3] += o[3] - m * dx * dy
        j[4] += o[4] - m * dx * dz
        j[5] += o[5] - m * dy * dz
    return mass, cg, j


def min_clearance(hubs, diameters):
    best = math.inf
    for i in range(len(hubs)):
        for k in range(i + 1, len(hubs)):
            d = math.sqrt(sum((hubs[i][n] - hubs[k][n]) ** 2 for n in range(3)))
            best = min(best, d - 0.5 * (diameters[i] + diameters[k]))
    return best


def fit(rows, kv_rpm, half_step):
    omega = [row["rpm"] * RPM_TO_RAD_S for row in rows]
    thrust = [row["thrust_g"] * 1.0e-3 * G0 for row in rows]
    torque = [float(row["torque_displayed_n_m"]) for row in rows]
    w2 = [w * w for w in omega]
    s44 = sum(x * x for x in w2)
    kt = sum(t * x for t, x in zip(thrust, w2)) / s44
    kq = sum(t * x for t, x in zip(torque, w2)) / s44
    kq_unc = half_step * sum(w2) / s44
    loo = [kt_other * w2[i] - thrust[i] for i, kt_other in ((0, thrust[1] / w2[1]), (1, thrust[0] / w2[0]))]
    kv = kv_rpm * RPM_TO_RAD_S
    top = rows[1]
    r = (top["voltage_v"] - omega[1] / kv) / top["current_a"]
    low = rows[0]
    implied_duty = (omega[0] / kv + low["current_a"] * r) / low["voltage_v"]
    return {
        "omega": omega, "thrust": thrust, "torque": torque, "kt": kt, "kq": kq, "kq_unc": kq_unc,
        "thrust_residual": [kt * x - t for t, x in zip(thrust, w2)],
        "torque_residual": [kq * x - t for t, x in zip(torque, w2)],
        "loo": loo, "kv": kv, "r": r, "implied_duty": implied_duty,
    }


def build(sources_bytes):
    s = json.loads(sources_bytes.decode("utf-8"))
    inp = s["inputs"]
    build_info = s["build"]
    rows = s["motor_rows"]["rows"]
    f = fit(rows, inp["motor_kv"]["value"], inp["torque_display_half_step"]["value"])
    i0 = inp["no_load_current"]["value"]
    kappa = f["kq"] / f["kt"]
    diag = inp["motor_diagonal"]["value"]
    half = diag / (2.0 * math.sqrt(2.0))
    diameter = inp["prop_diameter"]["value"]
    j_rotor = inp["rotor_inertia"]["value"]

    # Mass inventory in the frame datum: centre of the hub plane, FRD axes (x forward, y right, z down).
    components = []
    for item in s["mass_items"]:
        shape = {"type": item["shape"]["type"]}
        if shape["type"] == "box":
            shape["size"] = q(item["shape"]["size"], "m", item["class"], "inertia box (full lengths x, y, z) of " + item["id"])
        components.append({"id": item["id"], "mass": q(item["mass"], "kg", item["class"], item["note"]),
            "position": q(item["position"], "m", item["class"], item["note"]), "shape": shape})
    motor = inp["motor_mass"]
    below = inp["motor_centroid_below_hub"]["value"]
    prop = inp["prop_mass"]
    hub_datum = {}
    for rid, sx, sy, _spin in ROTOR_LAYOUT:
        hub_datum[rid] = [sx * half, sy * half, 0.0]
    for rid, _sx, _sy, _spin in ROTOR_LAYOUT:
        h = hub_datum[rid]
        components.append({"id": "motor_%d" % rid, "mass": src(motor),
            "position": q([h[0], h[1], below], "m", "derived",
                "hub x/y of rotor %d on the %.3f m square-X diagonal (estimated), centroid %.3f m below the hub plane (estimated)" % (rid, diag, below)),
            "shape": {"type": "point"}})
    for rid, _sx, _sy, _spin in ROTOR_LAYOUT:
        h = hub_datum[rid]
        components.append({"id": "prop_%d" % rid, "rotor_id": rid, "mass": src(prop),
            "position": q(list(h), "m", "derived", "hub of rotor %d on the %.3f m square-X diagonal (estimated)" % (rid, diag)),
            "shape": {"type": "axisymmetric_z",
                "axial_inertia": q(j_rotor, "kg*m^2", "borrowed", "rotating prop plus bell about the spin axis, equal to the rotor inertia (lab fixture Plant.research_quad(), DR-01); counted once here"),
                "transverse_inertia": q(0.5 * j_rotor, "kg*m^2", "derived", "half the axial inertia (perpendicular-axis theorem for a planar rotor averaged over a turn)")}})
    mass, cg, inertia = mass_properties(components)
    weight = mass * G0

    def rel(p):
        return [p[0] - cg[0], p[1] - cg[1], p[2] - cg[2]]

    hubs = {rid: rel(hub_datum[rid]) for rid in hub_datum}
    rotors = []
    for rid, _sx, _sy, spin in ROTOR_LAYOUT:
        rotors.append({
            "id": rid, "spin": spin,
            "hub_frd": q(hubs[rid], "m", "derived", "hub of rotor %d from the computed CG (square-X diagonal %.3f m, estimated)" % (rid, diag)),
            "axis": q([0.0, 0.0, -1.0], "1", "estimated", "fixed parallel thrust axis up (body -z); no motor tilt modelled"),
            "diameter": src(inp["prop_diameter"]),
            "inertia": src(inp["rotor_inertia"]),
            "prop": "T-Motor F5146 (5.1 in, 4.6 in pitch, tri-blade)",
            "motor": "F50 2150 KV",
        })
    clearance = min_clearance([hubs[r] for r, *_ in ROTOR_LAYOUT], [diameter] * 4)

    # Hover equilibrium: B f = [m g, 0, 0, 0], B columns [1, -y, x, s*kappa] (static quadratic law, FPV/03 section 2).
    b = [[1.0] * 4, [-hubs[r][1] for r, *_ in ROTOR_LAYOUT], [hubs[r][0] for r, *_ in ROTOR_LAYOUT],
        [spin * kappa for *_, spin in ROTOR_LAYOUT]]
    hover = solve4(b, [weight, 0.0, 0.0, 0.0])
    hover_max = max(hover)
    hover_speed = math.sqrt(hover_max / f["kt"])

    bat = s["battery"]
    cells = bat["cells"]["value"]
    ocv_points = [[p[0], p[1] * cells] for p in bat["cell_ocv"]["value"]]
    v_full = ocv_points[-1][1]
    v_low = [p[1] for p in ocv_points if p[0] > 0.1][0]
    pt = s["powertrain"]
    idle = pt["idle_command"]["value"]
    top = pt["max_command"]["value"]
    w_max = static_speed(top, v_full, f["kv"], f["r"], i0, f["kq"])
    t_max = f["kt"] * w_max * w_max
    w_low = static_speed(top, v_low, f["kv"], f["r"], i0, f["kq"])
    w_idle = static_speed(idle, v_full, f["kv"], f["r"], i0, f["kq"])
    w_row = static_speed(1.0, rows[1]["voltage_v"], f["kv"], f["r"], i0, f["kq"])
    hover_command = f["r"] / v_full * (f["kq"] * hover_speed * hover_speed * f["kv"] + i0) + hover_speed / (f["kv"] * v_full)
    max_speed = f["kv"] * v_full * top

    con = s["contacts"]
    depth = con["foot_depth"]["value"]
    sag = con["static_sag"]["value"]
    zeta = con["heave_damping_ratio"]["value"]
    k_total = weight / sag
    k_foot = k_total / 4.0
    c_foot = 2.0 * zeta * math.sqrt(k_total * mass) / 4.0
    feet = [rel([hub_datum[r][0], hub_datum[r][1], depth]) for r, *_ in ROTOR_LAYOUT]
    z_low = max(p[2] for p in feet)
    n_low = sum(1 for p in feet if p[2] == z_low)
    rest_height = z_low - weight / (n_low * k_foot)
    hull_height = con["prop_hull_height"]["value"]
    hull = [rel([hub_datum[r][0], hub_datum[r][1], -hull_height]) for r, *_ in ROTOR_LAYOUT]
    battery_item = [c for c in s["mass_items"] if c["id"] == "battery"][0]
    bp = battery_item["position"]
    hull.append(rel([bp[0], bp[1], bp[2] - 0.5 * battery_item["shape"]["size"][2]]))
    cam = s["camera"]
    mount = [cam["forward_of_cg"]["value"], -cg[1], -cam["above_hub_plane"]["value"] - cg[2]]

    rows_note = "F50 rows 50% and 100% (sources.json motor_rows, manufacturer-reported)"
    fit_note = "least-squares fit through the origin against Omega^2 over " + rows_note
    diagnostics = {
        "fit_method": "k_T, k_Q: least squares through the origin of T and displayed Q against Omega^2 over both rows; R = (V - Omega/Kv)/I at the 100% row (lumps ESC and wiring loss); thrust = grams * 1e-3 * 9.80665",
        "fit_kt_n_s2": f["kt"], "fit_kq_n_m_s2": f["kq"], "fit_kq_display_uncertainty_n_m_s2": f["kq_unc"],
        "fit_omega_rad_s": f["omega"], "fit_thrust_reported_n": f["thrust"],
        "fit_thrust_residual_n": f["thrust_residual"], "fit_torque_residual_n_m": f["torque_residual"],
        "fit_leave_one_out_thrust_residual_n": f["loo"],
        "fit_kv_rad_s_per_v": f["kv"], "fit_resistance_ohm": f["r"],
        "fit_row100_static_speed_model_rad_s": w_row, "fit_row100_static_thrust_model_n": f["kt"] * w_row * w_row,
        "fit_row50_implied_duty": f["implied_duty"],
        "mass_kg": mass, "cg_from_datum_m": cg, "inertia_kg_m2": inertia,
        "effective_yaw_inertia_kg_m2": inertia[2] - 4.0 * j_rotor,
        "min_prop_clearance_m": clearance, "zero_gap_square_x_diagonal_m": math.sqrt(2.0) * diameter,
        "hover_thrusts_n": hover, "hover_thrust_per_rotor_n": hover_max, "hover_speed_rad_s": hover_speed,
        "hover_command_full_charge": hover_command,
        "idle_thrust_full_charge_n": f["kt"] * w_idle * w_idle,
        "static_max_speed_rad_s": w_max, "static_max_thrust_per_rotor_n": t_max,
        "static_max_thrust_low_charge_n": f["kt"] * w_low * w_low,
        "thrust_to_weight": 4.0 * t_max / weight,
        "rest_height_m": rest_height, "stiffness_per_foot_n_per_m": k_foot, "damping_per_foot_n_s_per_m": c_foot,
    }

    ctl = s["controller"]
    doc = {
        "format": FORMAT,
        "identity": {"family": build_info["family"], "variant": build_info["variant"], "name": build_info["name"],
            "status": build_info["status"]},
        "capabilities": list(build_info["capabilities"]),
        "provenance": {
            "generator": GENERATOR, "generator_version": GENERATOR_VERSION,
            "sources": "research/drone-racing/openrc-fpv5-x1/sources.json",
            "sources_sha256": hashlib.sha256(sources_bytes).hexdigest(),
            "notes": "Experimental product candidate built from estimates, borrowed lab-fixture values and vendor-reported static rows. Nothing in this file is measured by this project or validated against flight data. Regenerate with derive.py; never hand-edit.",
            "references": dict(sorted(s["references"].items())),
            "derived_diagnostics": diagnostics,
        },
        "mass_inventory": {
            "datum": "centre of the hub plane, FRD axes (x forward, y right, z down); positions in metres",
            "components": components,
        },
        "rotors": rotors,
        "rotor_law": {
            "law": build_info["rotor_law"],
            "thrust_coefficient": q(f["kt"], "N*s^2", "derived", "k_T, " + fit_note + "; residuals in provenance.derived_diagnostics"),
            "torque_coefficient": q(f["kq"], "N*m*s^2", "derived", "k_Q, " + fit_note + " of the displayed torque (0.01 N*m display step, about +-%.1f%% coefficient uncertainty)" % (100.0 * f["kq_unc"] / f["kq"])),
            "rotor_drag": src(inp["rotor_drag"]),
            "max_speed": q(max_speed, "rad/s", "derived", "no-load ceiling Kv * full-charge pack OCV * max command; the fitted rows only reach %.1f rad/s, above that the static law is extrapolated" % f["omega"][1]),
        },
        "airframe": {"drag_areas": src(inp["airframe_drag_areas"])},
        "powertrain": {
            "law": build_info["powertrain_law"],
            "kv": q(f["kv"], "rad/s/V", "derived", "2150 rpm/V motor designation (manufacturer-reported) converted to rad/s/V"),
            "resistance": q(f["r"], "ohm", "derived", "(V - Omega/Kv)/I at the F50 100% row (manufacturer-reported); lumps motor, ESC and wiring loss at an assumed full bridge duty"),
            "no_load_current": src(inp["no_load_current"]),
            "braking": pt["braking"]["value"],
            "idle_command": src(pt["idle_command"]),
            "max_command": src(pt["max_command"]),
        },
        "battery": {
            "cells": src(bat["cells"]), "capacity": src(bat["capacity"]),
            "ocv_points": q(ocv_points, "V", "derived", "pack open-circuit voltage (soc, volts) = generic per-cell LiPo rest curve (estimated, not identified for a product) times %d cells" % cells),
            "resistance": src(bat["resistance"]), "auxiliary_current": src(bat["auxiliary_current"]),
            "initial_soc": src(bat["initial_soc"]),
        },
        "controller": {
            "law": build_info["controller_law"],
            "sample_rate": src(ctl["sample_rate"]),
            "kp": src(ctl["kp"]), "ki": src(ctl["ki"]), "kd": src(ctl["kd"]), "i_max": src(ctl["i_max"]),
            "kaw": src(ctl["kaw"]), "tau_limit": src(ctl["tau_limit"]),
            "gyro_lpf": src(ctl["gyro_lpf"]), "dterm_lpf": src(ctl["dterm_lpf"]),
            "kff": src(ctl["kff"]), "setpoint_lpf": src(ctl["setpoint_lpf"]),
            "angle": {"max_tilt": src(ctl["angle_max_tilt"]), "gain": src(ctl["angle_gain"]), "rate_limit": src(ctl["angle_rate_limit"])},
            "arm_low_throttle": src(ctl["arm_low_throttle"]),
            "allocator_weights": src(ctl["allocator_weights"]),
            "throttle_rate": src(ctl["throttle_rate"]),
        },
        "contacts": {
            "feet": q(feet, "m", "derived", "four feet at the hub x/y, %.3f m below the hub plane (estimated), from the computed CG" % depth),
            "stiffness_per_foot": q(k_foot, "N/m", "derived", "total vertical stiffness m*g/%.3f m static sag (estimated) shared by four feet" % sag),
            "damping_per_foot": q(c_foot, "N*s/m", "derived", "total damping 2*%.2f*sqrt(k_total*m) for the heave damping ratio (estimated) shared by four feet" % zeta),
            "friction": src(con["friction"]),
            "hull": q(hull, "m", "derived", "crash points from the computed CG: four prop-disc centres %.3f m above the hub plane and the top of the battery (estimated geometry)" % hull_height),
            "crash_speed": src(con["crash_speed"]),
            "rotor_strike_speed": src(con["rotor_strike_speed"]),
        },
        "camera": {
            "mount": q(mount, "m", "derived", "FPV camera %.3f m forward of the CG and %.3f m above the hub plane (estimated starting point, not a calibration), from the computed CG" % (cam["forward_of_cg"]["value"], cam["above_hub_plane"]["value"])),
            "tilt": src(cam["tilt"]), "hfov": src(cam["hfov"]),
        },
        "start": {
            "mode": "ground_rest", "armed": False,
            "rest_height": q(rest_height, "m", "derived", "CG height above flat ground with the lowest feet at static sag (estimated stiffness and geometry)"),
        },
    }
    return doc


def render(doc):
    return (json.dumps(doc, indent=1, sort_keys=True, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")


def read_sources():
    with open(SOURCES, "rb") as fh:
        data = fh.read()
    # Hash the LF form so a CRLF working tree yields the same identity.
    return data.replace(b"\r\n", b"\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default=DEFAULT_OUT, help="output path (default: the app data file)")
    parser.add_argument("--check", action="store_true", help="compare regenerated bytes with --out; never writes")
    args = parser.parse_args(argv)
    out = render(build(read_sources()))
    if args.check:
        try:
            with open(args.out, "rb") as fh:
                existing = fh.read().replace(b"\r\n", b"\n")
        except OSError as exc:
            print("check failed: cannot read %s: %s" % (args.out, exc), file=sys.stderr)
            return 1
        if existing != out:
            print("check failed: %s differs from the regenerated candidate" % args.out, file=sys.stderr)
            return 1
        print("check ok: %s (%d bytes)" % (args.out, len(out)))
        return 0
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "wb") as fh:
        fh.write(out)
    print("wrote %s (%d bytes)" % (args.out, len(out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
