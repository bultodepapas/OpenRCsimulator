#!/usr/bin/env python3
"""AV-06 sensitivity: how the Avanti's key numbers move with each uncertain input of inputs.json.

Re-runs derive_physics.py in memory (nothing is written) with one input changed at a time and prints a Markdown table
(stall speed, maximum level speed, static margin at the flight CG, roll rate at the manual's normal rate, climb rate).
    python3 research/avanti-s/av06/sensitivity.py
"""
import copy
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = (HERE / "derive_physics.py").read_text()
BASE = json.load(open(HERE / "inputs.json"))


def run(inputs):
    ns = {"__name__": "av06_sensitivity", "__file__": str(HERE / "derive_physics.py"), "IN_OVERRIDE": inputs}
    exec(compile(SRC, "derive_physics.py", "exec"), ns)
    v0 = 40.0
    swing = math.radians(0.5 * (30 + 25))
    p = -ns["Clda"] * swing / ns["Clp"] * 2 * v0 / ns["b"]
    # The derivation re-balances every case onto the manual CG; a fuel change on a built airplane does not, so the
    # fuel cases report where the CG goes from the baseline balance (the tank sits ahead of the CG).
    return {"stall": ns["Vs"], "vmax": ns["V_max"], "sm": ns["sm"], "roll40": abs(math.degrees(p)), "roc": ns["roc"], "mass": ns["mass"],
            "x_np": ns["x_np"], "mac": ns["mac"], "fuel": ns["fuel_kg"], "x_fuel": ns["fpos"][0], "cg": ns["cg"][0]}


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


cases = [
    ("baseline", BASE),
    ("wing area 0.78 m2 (+11 %)", with_("airframe.wing_area", {"value": 0.78, "unit": "m2", "kind": "estimated", "source": "sweep"})),
    ("wing area 0.85 m2 (sibling scaling, +21 %)", with_("airframe.wing_area", {"value": 0.85, "unit": "m2", "kind": "estimated", "source": "sweep"})),
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
rows = ["| Case | Mass (kg) | CG (mm) | Stall (m/s) | Vmax (m/s) | SM at CG (% MAC) | Roll at 40 m/s, D/R 50 % (°/s) | Climb at start (m/s) |", "| --- | --- | --- | --- | --- | --- | --- | --- |"]
base = run(BASE)
for name, inputs in cases:
    r = run(inputs)
    cg = r["cg"]
    sm = r["sm"]
    mass = r["mass"]
    if name in ("full tank (3.2 l)", "empty tank"):
        dm = r["fuel"] - base["fuel"]
        cg = (base["mass"] * base["cg"] + dm * base["x_fuel"]) / (base["mass"] + dm)
        sm = 100 * (base["x_np"] - cg) / base["mac"]
        mass = base["mass"] + dm
    rows.append(f"| {name} | {mass:.2f} | {cg * 1000:.0f} | {r['stall']:.1f} | {r['vmax']:.1f} | {sm:.1f} | {r['roll40']:.0f} | {r['roc']:.1f} |")
print("\n".join(rows))
