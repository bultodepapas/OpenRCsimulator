#!/usr/bin/env python3
"""AV-06 sensitivity: move one uncertain input at a time and print a Markdown table.

Fuel rows represent fuel burn in the baseline reference build: its inventory, ballast, geometry, and propulsion
installation stay fixed while fuel mass changes at the declared tank position. Other rows retain the original
AV-06 behavior of re-running the derivation with that one input changed. Fuel performance is a fixed-build
static-polar estimate; it does not include CG-dependent trim drag.

    python3 research/avanti-s/av06/sensitivity.py
"""
import copy
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = (HERE / "derive_physics.py").read_text()
BASE = json.loads((HERE / "inputs.json").read_text())


def run(inputs):
    """Compute the AV-06 derivation in memory without writing generated files."""
    ns = {"__name__": "av06_sensitivity", "__file__": str(HERE / "derive_physics.py"), "IN_OVERRIDE": inputs}
    exec(compile(SRC, "derive_physics.py", "exec"), ns)
    swing = math.radians(0.5 * (30 + 25))
    p = -ns["Clda"] * swing / ns["Clp"] * 2 * 40.0 / ns["b"]
    return {
        "stall": ns["Vs"],
        "vmax": ns["V_max"],
        "sm": ns["sm"],
        "roll40": abs(math.degrees(p)),
        "roc": ns["roc"],
        "mass": ns["mass"],
        "x_np": ns["x_np"],
        "mac": ns["mac"],
        "cg": list(ns["cg"]),
        "fuel": ns["fuel_kg"],
        "fuel_pos": ns["le"](*ns["fpos"]),
        # Inputs and constants needed to evaluate fuel changes against this same built reference airframe.
        "rho": ns["RHO"],
        "g": ns["G0"],
        "area": ns["S"],
        "reference_length": ns["c_ref_output"],
        "cl_max": ns["CL_max"],
        "cd0": ns["CD0"],
        "k_ind": ns["k_ind"],
        "v_start": ns["V_start"],
        "span": ns["b"],
        "thrust_rows": ns["thrust_rows"],
        "mass_flow_rows": ns["mflow_rows"],
        "ram_jet_rows": ns["T"]["ram_jet"]["value"],
        "installed_factor": ns["k_inst"],
        "ram_flow": ns["v"]("turbine.ram_flow"),
        "max_rpm": ns["n_max"],
        "clda": ns["Clda"],
        "clp": ns["Clp"],
        "cyb_v": ns["CYb_v"],
        "z_v": ns["z_v"],
        "fin_cy": ns["fin_cy"],
    }


def with_(path, value):
    d = copy.deepcopy(BASE)
    node = d
    keys = path.split(".")
    for k in keys[:-1]:
        node = node[k]
    if isinstance(node.get(keys[-1]), dict) and "value" in node[keys[-1]]:
        node[keys[-1]]["value"] = value
    else:
        node[keys[-1]] = value
    return d


def with_wing_area(area):
    """Keep the serialized coefficient reference length consistent with a swept wing area."""
    inputs = with_("airframe.wing_area", {
        "value": area,
        "unit": "m2",
        "kind": "estimated",
        "source": "sensitivity sweep",
    })
    c_ref = inputs["airframe"]["coefficient_reference_length"]
    c_ref["value"] = area / inputs["airframe"]["span"]["value"]
    c_ref["kind"] = "derived"
    c_ref["source"] = "Sensitivity sweep: geometric wing area / span (S/b)"
    return inputs


def interpolate(rows, x):
    if x <= rows[0][0]:
        return rows[0][1]
    for (x0, y0), (x1, y1) in zip(rows, rows[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return rows[-1][1]


def net_thrust(reference, speed, rpm):
    """P100 net thrust model used by derive_physics.py, evaluated from baseline installation data."""
    m0 = interpolate(reference["mass_flow_rows"], rpm)
    vj0 = reference["installed_factor"] * interpolate(reference["thrust_rows"], rpm) / m0
    ram_jet = interpolate(reference["ram_jet_rows"], rpm)
    mass_flow = m0 * (1 + reference["ram_flow"] * speed * speed)
    return mass_flow * (math.sqrt(vj0 * vj0 + ram_jet * speed * speed) - speed)


def drag_at(reference, speed, mass):
    dynamic_pressure = 0.5 * reference["rho"] * speed * speed
    lift_coefficient = mass * reference["g"] / (dynamic_pressure * reference["area"])
    return dynamic_pressure * reference["area"] * (reference["cd0"] + reference["k_ind"] * lift_coefficient ** 2)


def fuel_case(reference, inputs):
    """Return a fuel-burn case while holding baseline hardware, ballast, and installation fixed."""
    fuel = inputs["fuel"]
    fuel_mass = fuel["tank_l"]["value"] * fuel["fraction"]["value"] * fuel["density"]["value"]
    delta_fuel = fuel_mass - reference["fuel"]
    mass = reference["mass"] + delta_fuel
    cg = [
        (reference["mass"] * reference["cg"][axis] + delta_fuel * reference["fuel_pos"][axis]) / mass
        for axis in range(3)
    ]
    sm = 100 * (reference["x_np"] - cg[0]) / reference["mac"]
    stall = math.sqrt(2 * mass * reference["g"] / (reference["rho"] * reference["area"] * reference["cl_max"]))

    # The drag polar and thrust map are unchanged; only the aircraft weight in induced drag changes.
    lo, hi = stall, 150.0
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        if net_thrust(reference, mid, reference["max_rpm"]) > drag_at(reference, mid, mass):
            lo = mid
        else:
            hi = mid
    vmax = lo
    roc = (
        net_thrust(reference, reference["v_start"], reference["max_rpm"])
        - drag_at(reference, reference["v_start"], mass)
    ) * reference["v_start"] / (mass * reference["g"])

    # Clp's only CG-dependent term is the vertical-tail contribution through its vertical arm z_v.
    z_v = reference["fin_cy"] - cg[2]
    clp = reference["clp"] - 2 * reference["cyb_v"] * (reference["z_v"] / reference["span"]) ** 2
    clp += 2 * reference["cyb_v"] * (z_v / reference["span"]) ** 2
    swing = math.radians(0.5 * (30 + 25))
    p = -reference["clda"] * swing / clp * 2 * 40.0 / reference["span"]

    result = dict(reference)
    result.update({
        "stall": stall,
        "vmax": vmax,
        "sm": sm,
        "roll40": abs(math.degrees(p)),
        "roc": roc,
        "mass": mass,
        "cg": cg,
        "fuel": fuel_mass,
    })
    return result


cases = [
    ("baseline", BASE),
    ("wing area 0.78 m2 (+11 %)", with_wing_area(0.78)),
    ("wing area 0.85 m2 (sibling scaling, +21 %)", with_wing_area(0.85)),
    ("CL_max 0.75", with_("aero.CL_max", 0.75)),
    ("CL_max 0.95", with_("aero.CL_max", 0.95)),
    ("installed thrust 0.85", with_("turbine.installed_factor", 0.85)),
    ("installed thrust 0.97", with_("turbine.installed_factor", 0.97)),
    ("excrescence factor 1.05", with_("aero.excrescence_factor", 1.05)),
    ("excrescence factor 1.25", with_("aero.excrescence_factor", 1.25)),
    ("Oswald e 0.70", with_("aero.oswald_e", 0.70)),
    ("full tank (3.2 l)", with_("fuel.fraction", 1.0)),
    ("empty tank", with_("fuel.fraction", 0.0)),
]
anchor0 = with_("stability", {"np_anchor": dict(BASE["stability"]["np_anchor"], static_margin=0.0)})
anchor6 = with_("stability", {"np_anchor": dict(BASE["stability"]["np_anchor"], static_margin=0.06)})
cases += [("anchor margin 0 % at 260 mm", anchor0), ("anchor margin 6 % at 260 mm", anchor6)]


def render_rows():
    rows = [
        "Fuel rows are fixed-build static-polar estimates; CG-dependent trim drag is omitted.",
        "| Case | Mass (kg) | CG (mm) | Stall (m/s) | Vmax (m/s) | SM at CG (% MAC) | Roll at 40 m/s, D/R 50 % (°/s) | Climb at start (m/s) |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    base = run(BASE)
    for name, inputs in cases:
        if name == "baseline":
            result = base
        elif name in ("full tank (3.2 l)", "empty tank"):
            result = fuel_case(base, inputs)
        else:
            result = run(inputs)
        rows.append(
            f"| {name} | {result['mass']:.2f} | {result['cg'][0] * 1000:.0f} | {result['stall']:.1f} | "
            f"{result['vmax']:.1f} | {result['sm']:.1f} | {result['roll40']:.0f} | {result['roc']:.1f} |"
        )
    return "\n".join(rows)


if __name__ == "__main__":
    print(render_rows())
