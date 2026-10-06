#!/usr/bin/env python3
"""P51-06: calibrate the blade-element propeller model (bem.py) on Mejzlik's 26x12 tables.

Fits two factors (effective pitch, chord scale) to the 2-blade and the 3-blade 26x12 together, with the kit's
blade planform from geometry.json, over the thrusting range J <= 0.76, weighting Ct and Cp by their static values.
The fitted model then predicts the 4-blade 26x12 used on the model (no 4-blade gas datasheet exists). Writes
calibration.json, which derive_physics.py reads.

    python3 research/p51/p51-06/fit_mejzlik.py
"""
import json
import math
from pathlib import Path

from bem import bem_tables

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
g = json.load(open(ROOT / "assets/aircraft/p51d-mustang-120/geometry.json"))
P = g["propeller"]
planform = P["blade"]["chord_fraction_of_radius"]
ref = json.load(open(HERE / "mejzlik_26x12.json"))["props"]
J_FIT = 0.76


def lerp(rows, x):
    return next((a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0]) for a, b in zip(rows, rows[1:]) if a[0] <= x <= b[0]), rows[-1][1])


def errors(kp, kc):
    out = []
    for name, d in ref.items():
        ct, cp = bem_tables(P["diameter"], P["pitch"], d["blades"], planform, 90.0, kp, kc, j_max=1.0)
        for j, ctm, cpm in zip(d["J"], d["Ct"], d["Cp"]):
            if j <= J_FIT:
                out.append((lerp(ct, j) - ctm) / d["Ct"][0])
                out.append((lerp(cp, j) - cpm) / d["Cp"][0])
    return math.sqrt(sum(e * e for e in out) / len(out))


best = (1e9, 1.0, 1.0)
for kp in [1.2 + 0.1 * i for i in range(9)]:
    for kc in [0.5 + 0.1 * i for i in range(9)]:
        e = errors(kp, kc)
        best = min(best, (e, kp, kc))
step = 0.05
e, kp, kc = best
while step > 0.002:
    moved = False
    for dkp, dkc in ((step, 0), (-step, 0), (0, step), (0, -step)):
        e2 = errors(kp + dkp, kc + dkc)
        if e2 < e:
            e, kp, kc, moved = e2, kp + dkp, kc + dkc, True
    if not moved:
        step /= 2
rows = {}
for name, d in ref.items():
    ct, cp = bem_tables(P["diameter"], P["pitch"], d["blades"], planform, 90.0, kp, kc, j_max=1.0)
    rows[name] = [[j, round(lerp(ct, j), 4), ctm, round(lerp(cp, j), 4), cpm] for j, ctm, cpm in zip(d["J"], d["Ct"], d["Cp"])]
ct4, cp4 = bem_tables(P["diameter"], P["pitch"], 4, planform, 90.0, kp, kc)
out = {
    "source": "research/p51/p51-06/fit_mejzlik.py: bem.py fitted to Mejzlik 26x12 2B and 3B (mejzlik_26x12.json), J <= %.2f" % J_FIT,
    "pitch_factor": round(kp, 4), "chord_factor": round(kc, 4), "rms_relative_error": round(e, 4),
    "check_rows_J_ct_bem_ct_mejzlik_cp_bem_cp_mejzlik": rows,
    "four_blade_static": {"Ct": ct4[0][1], "Cp": cp4[0][1]},
}
(HERE / "calibration.json").write_text(json.dumps(out, indent=1) + "\n")
print(json.dumps({k: v for k, v in out.items() if k != "check_rows_J_ct_bem_ct_mejzlik_cp_bem_cp_mejzlik"}))
for name, r in rows.items():
    print(name)
    for row in r:
        print("  J %.3f  Ct %.4f vs %.4f   Cp %.4f vs %.4f" % tuple(row))
