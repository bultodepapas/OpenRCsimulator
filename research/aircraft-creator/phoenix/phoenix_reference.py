"""Phoenix's own steady performance for every fixed-wing model of a local installation (IAQ T1, research only).

Applies the formulas decoded from the Phoenix 6.0 scripts (docs/research/aircraft-creator/
phoenix-flight-model-2026-11-20.md) to each model's definition and its airfoil polars: static thrust, thrust
at speed, the steady drag build-up (section drag of every surface, induced drag with Phoenix's 0.85 span
efficiency, fuselage drag 0.75 on the frontal area), the stall speed from the main wing's polar peak and the
maximum level speed. It is a steady, wash-free estimate of what Phoenix would show, to compare OpenRC's flight
cards against; Phoenix's engine-side wing details (Lift/Dihedral tuning form, stall severity) are approximated.

    python3 research/aircraft-creator/phoenix/phoenix_reference.py "<PhoenixRC folder>" --out <file.json> [--only name]

Point it only at a local installation; never commit its output.
"""
import argparse
import glob
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inspect_luac as L  # noqa: E402

RHO = 1.225
G = 9.80665
EFFICIENCY = 0.85
FUSELAGE_CD = 0.75
BLADE_FACTOR = {2: 1.0, 3: 1.3, 4: 1.54, 5: 1.85, 6: 2.06}
PROP_ZERO_THRUST = 1.6  # x pitch speed
TURBINE_LOSS_PER_MPS = 0.01


def text(value):
    return value.decode("latin-1") if isinstance(value, bytes) else str(value)


def num(value, fallback=float("nan")):
    return float(value) if isinstance(value, (int, float)) and math.isfinite(float(value)) else fallback


def polars(install):
    out = {}
    for path in glob.glob(os.path.join(install, "resources", "airfoils", "*.sim")):
        try:
            assigned = L.summarize(path)["assigned"]
        except Exception:  # noqa: BLE001
            continue
        for value in assigned.values():
            if isinstance(value, dict) and isinstance(value.get("coefficients"), list):
                c = value["coefficients"]
                rows = [(float(c[i]), float(c[i + 1]), float(c[i + 2])) for i in range(0, len(c) - 2, 3)]
                out[text(value.get("name"))] = sorted(rows)
    return out


def interp(rows, alpha):
    for (a0, l0, d0), (a1, l1, d1) in zip(rows, rows[1:]):
        if a0 <= alpha <= a1:
            f = (alpha - a0) / (a1 - a0) if a1 > a0 else 0.0
            return l0 + f * (l1 - l0), d0 + f * (d1 - d0)
    return (rows[-1][1], rows[-1][2]) if alpha > rows[-1][0] else (rows[0][1], rows[0][2])


def section_at_lift(rows, cl):
    """Section drag at the attached-branch angle giving `cl` (0..peak), and the peak lift."""
    attached = [r for r in rows if -10.0 <= r[0] <= 25.0]
    peak = max(attached, key=lambda r: r[1])
    best = None
    for (a0, l0, d0), (a1, l1, d1) in zip(attached, attached[1:]):
        if a1 > peak[0]:
            break
        if (l0 - cl) * (l1 - cl) <= 0 and l1 != l0:
            f = (cl - l0) / (l1 - l0)
            best = d0 + f * (d1 - d0)
            break
    return best if best is not None else peak[2], peak[1]


def model_of(tree):
    if isinstance(tree, dict):
        if "airfoils" in tree and "attributes" in tree:
            return tree
        for value in tree.values():
            found = model_of(value)
            if found:
                return found
    if isinstance(tree, list):
        for value in tree:
            found = model_of(value)
            if found:
                return found
    return None


def assess(model, library):
    attributes = model.get("attributes") or {}
    physical = attributes.get("Physical") or {}
    tuning = attributes.get("Fine_tuning") or {}
    weight = num(physical.get("Weight")) * G
    surfaces = []
    for airfoil in model.get("airfoils") or []:
        if not isinstance(airfoil, dict):
            continue
        at = airfoil.get("attributes") or {}
        length = num(at.get("Length"), 0.0)
        chord = 0.5 * (num(at.get("Root_chord"), 0.0) + num(at.get("Tip_chord"), 0.0))
        sides = 2 if num(airfoil.get("isMirrored"), 0) == 1 else 1
        area = length * chord * sides
        if area <= 0:
            continue
        surfaces.append({"name": text(airfoil.get("name", "")), "airfoil": text(at.get("Airfoil", "")), "area": area,
                         "span": length * sides, "vertical": abs(num(at.get("Dihedral"), 0.0)) > 60.0})
    lifting = [s for s in surfaces if not s["vertical"]]
    if not lifting or not math.isfinite(weight):
        return {"status": "no wing or weight"}
    main = max(lifting, key=lambda s: s["area"])
    wings = [s for s in lifting if s["area"] >= 0.6 * main["area"]]
    wing_area = sum(s["area"] for s in wings)
    aspect = main["span"] ** 2 / main["area"]
    rows = library.get(main["airfoil"])
    if not rows:
        return {"status": "main-wing polar missing", "airfoil": main["airfoil"]}
    lift_tuning = num(tuning.get("Lift"), 100.0) / 100.0
    _, peak = section_at_lift(rows, 0.0)
    cl_max = peak * lift_tuning
    stall = math.sqrt(2.0 * weight / (RHO * wing_area * cl_max))
    frontal = num((physical.get("Fuselage_drag_area") or {}).get("frontal"), 0.0)
    thrust_tuning = num(tuning.get("Thrust"), 100.0) / 100.0
    units = []
    for unit in model.get("propulsion") or []:
        if not isinstance(unit, dict):
            continue
        at = unit.get("attributes") or {}
        if text(unit.get("type")) == "propeller":
            pitch, diameter, rpm = num(at.get("Pitch")), num(at.get("Diameter")), num(at.get("Max_RPM"))
            if all(math.isfinite(v) and v > 0 for v in (pitch, diameter, rpm)):
                blades = int(num(at.get("Blade_count"), 2))
                static = pitch * diameter ** 3 * rpm ** 2 / 20000.0 * BLADE_FACTOR.get(blades, 1.0) * thrust_tuning
                # Commanded RPM = Idle_RPM + throttle^Throttle_Curve × (Max_RPM − Idle_RPM) (airplane.sim).
                idle, curve = num(at.get("Idle_RPM"), 0.0), num(at.get("Throttle_Curve"), 1.0)
                half = (idle + 0.5 ** curve * (rpm - idle)) / rpm
                units.append(("propeller", static, PROP_ZERO_THRUST * rpm / 60.0 * pitch, half * half, half))
        elif text(unit.get("type")) == "turbine":
            static = num(at.get("Max_Thrust"), 0.0) * thrust_tuning
            if static > 0:
                idle_share = num(at.get("Idle_Thrust"), 0.0) * thrust_tuning / static
                units.append(("turbine", static, 1.0 / TURBINE_LOSS_PER_MPS, idle_share + 0.5 * (1.0 - idle_share), 1.0))

    def thrust(v, half=False):
        # Half throttle: a propeller's static thrust × (RPM share)², its zero-thrust speed × the RPM share; a
        # turbine's thrust at half its speed range, the same momentum loss.
        return sum(u[1] * (u[3] if half else 1.0) * max(0.0, 1.0 - v / (u[2] * (u[4] if half else 1.0))) for u in units)

    def drag(v):
        q = 0.5 * RHO * v * v
        cl = weight / (q * wing_area) / lift_tuning
        wing_cd, _ = section_at_lift(rows, min(cl, peak * 0.98))
        total = wing_cd * wing_area + (lift_tuning * cl) ** 2 / (math.pi * aspect * EFFICIENCY) * wing_area
        for s in surfaces:
            if s in wings:
                continue
            other = library.get(s["airfoil"])
            total += (min(r[2] for r in other if abs(r[0]) <= 8.0) if other else 0.01) * s["area"]
        return q * (total + FUSELAGE_CD * frontal)

    vmax = None
    v = stall * 1.05
    while v < 200.0 and units:
        if thrust(v) <= drag(v):
            vmax = v
            break
        v += 0.1
    half_speeds = [x / 10.0 for x in range(int(stall * 10.5), 2000) if units and thrust(x / 10.0, True) >= drag(x / 10.0)]
    static = thrust(0.0)
    return {"status": "ok", "mass_kg": round(weight / G, 3), "wing_area_m2": round(wing_area, 4), "aspect_ratio": round(aspect, 2),
            "airfoil": main["airfoil"], "cl_max": round(cl_max, 3), "stall_speed_mps": round(stall, 2),
            "static_thrust_n": round(static, 2), "thrust_to_weight": round(static / weight, 3) if weight else None,
            "max_level_speed_mps": round(vmax, 1) if vmax else None,
            "half_throttle_level_mps": [half_speeds[0], half_speeds[-1]] if half_speeds else None, "propulsion": [u[0] for u in units],
            "fuselage_drag_area_m2": round(FUSELAGE_CD * frontal, 5)}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("install")
    parser.add_argument("--out", required=True)
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    library = polars(args.install)
    rows = {}
    root = os.path.join(args.install, "resources", "objects", "aircraft")
    for family in ("fixedWing", "gliders"):
        for path in sorted(glob.glob(os.path.join(root, family, "**", "*.mod"), recursive=True)):
            name = os.path.splitext(os.path.basename(path))[0]
            if args.only and args.only.lower() not in name.lower():
                continue
            model = model_of(L.summarize(path)["assigned"])
            rows[name] = assess(model, library) if model else {"status": "no model"}
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump({"format": "openrc-phoenix-reference-v1", "models": rows}, handle, indent=1)
    ok = [r for r in rows.values() if r.get("status") == "ok"]
    print("models %d, assessed %d" % (len(rows), len(ok)))


if __name__ == "__main__":
    main()
