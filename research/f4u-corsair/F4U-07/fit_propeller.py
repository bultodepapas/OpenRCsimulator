#!/usr/bin/env python3
"""F4U-07: calibrate the blade-element propeller model (P51-06 bem.py) for the Corsair's 30x18 three-blade.

No manufacturer table exists for a 30x18 three-blade. The fit takes two factors (effective pitch, chord scale) from
Mejzlik's 32x18 2-blade (mejzlik_32x18.json: the high-pitch radial-engine blade) together with the P-51's 26x12
2- and 3-blade tables (research/p51/p51-06/mejzlik_26x12.json: the blade-count transfer), over J <= 0.76 with errors
relative to each table's static values, on the P-51 blade planform as derive_physics.py uses it. Writes
prop_calibration.json, which derive_physics.py reads.

    python research/f4u-corsair/F4U-07/fit_propeller.py           # writes prop_calibration.json
    python research/f4u-corsair/F4U-07/fit_propeller.py --check   # fails if the file is stale
"""
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "research/p51/p51-06"))
from bem import bem_tables  # noqa: E402

IN = 0.0254
OUT = HERE / "prop_calibration.json"
J_FIT = 0.76
planform = json.loads((ROOT / "assets/aircraft/p51d-mustang-120/geometry.json").read_text(encoding="utf-8"))["propeller"]["blade"]["chord_fraction_of_radius"]
tables = {}
for path, size in ((HERE / "mejzlik_32x18.json", None), (ROOT / "research/p51/p51-06/mejzlik_26x12.json", (26.0, 12.0))):
    for name, d in json.loads(path.read_text(encoding="utf-8"))["props"].items():
        dia, pitch = size or (d["diameter_in"], d["pitch_in"])
        tables[name] = {"D": dia * IN, "P": pitch * IN, "blades": d["blades"], "rows": list(zip(d["J"], d["Ct"], d["Cp"]))}


def lerp(rows, x):
    return next((a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0]) for a, b in zip(rows, rows[1:]) if a[0] <= x <= b[0]), rows[-1][1])


def residuals(kp, kc, names):
    out = []
    for name in names:
        t = tables[name]
        ct, cp = bem_tables(t["D"], t["P"], t["blades"], planform, 90.0, kp, kc, j_max=1.0)
        ct0, cp0 = t["rows"][0][1], t["rows"][0][2]
        for j, ctm, cpm in t["rows"]:
            if j <= J_FIT:
                out += [(lerp(ct, j) - ctm) / ct0, (lerp(cp, j) - cpm) / cp0]
    return out


rms = lambda r: math.sqrt(sum(e * e for e in r) / len(r))
names = list(tables)
best = min((rms(residuals(kp, kc, names)), kp, kc) for kp in [1.1 + 0.1 * i for i in range(8)] for kc in [0.4 + 0.1 * i for i in range(8)])
e, kp, kc = best
step = 0.05
while step > 0.002:
    moved = False
    for dkp, dkc in ((step, 0), (-step, 0), (0, step), (0, -step)):
        e2 = rms(residuals(kp + dkp, kc + dkc, names))
        if e2 < e:
            e, kp, kc, moved = e2, kp + dkp, kc + dkc, True
    if not moved:
        step /= 2
rows = {}
for name, t in tables.items():
    ct, cp = bem_tables(t["D"], t["P"], t["blades"], planform, 90.0, kp, kc, j_max=1.0)
    rows[name] = [[j, round(lerp(ct, j), 4), ctm, round(lerp(cp, j), 4), cpm] for j, ctm, cpm in t["rows"]]
ct3, cp3 = bem_tables(30 * IN, 18 * IN, 3, planform, 90.0, kp, kc)
out = {
    "source": "research/f4u-corsair/F4U-07/fit_propeller.py: bem.py fitted to Mejzlik 32x18 2B (mejzlik_32x18.json) and 26x12 2B/3B (research/p51/p51-06/mejzlik_26x12.json), J <= %.2f" % J_FIT,
    "pitch_factor": round(kp, 4), "chord_factor": round(kc, 4), "rms_relative_error": round(e, 4),
    "rms_per_table": {name: round(rms(residuals(kp, kc, [name])), 4) for name in names},
    "check_rows_J_ct_bem_ct_mejzlik_cp_bem_cp_mejzlik": rows,
    "30x18_3B_static": {"Ct": ct3[0][1], "Cp": cp3[0][1]},
}
text = json.dumps(out, indent=1) + "\n"
if "--check" in sys.argv:
    if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
        sys.exit("prop_calibration.json is stale: run fit_propeller.py")
    print("prop_calibration.json is up to date")
else:
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(json.dumps({k: v for k, v in out.items() if k != "check_rows_J_ct_bem_ct_mejzlik_cp_bem_cp_mejzlik"}))
