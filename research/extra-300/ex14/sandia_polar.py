#!/usr/bin/env python3
"""EX-14h evidence only: Sandia section polars for the Extra's wing by the Avanti AV-17-R2 policy.

Not used by the generator; it rebuilds the rejected candidates of the EX-14h comparison
(docs/research/extra-300-realism/EX-14/README.md#ex-14h--post-stall-wing-polar). The kit plan's rib 2D (drawn actual
size) measures 12.9 % thick, between NACA 0012 and 0015. Rows are Sheldahl & Klimas, SAND80-2114 (1981), Re 360,000,
10-30 deg, transcribed from the page images of references/rc-aero-data/sheldahl-klimas-1981-sand80-2114-symmetric-
airfoils-180deg.pdf (SHA-256 af5cb8e9...): NACA 0012 Table 2, printed p. 19 (PDF p. 22); NACA 0015 Table 3, printed
p. 33 (PDF p. 36). Both tables are hybrid (computed pre-stall, extended post-stall), not all measured.

The policy is research/avanti-s/av17-r2/build_polar.py's, imported for its induced-map mirror: CL scale = CL_max x
(finite strip slope / CLa) / source CLmax; angle scale = CL scale x (0.11 x 180/pi) / strip slope; profile CD = CD0 +
source CD - source CD at 8 deg; inverse-Kirchhoff attached fraction; CD90 flat-plate rows at 45-90 deg. Source rows whose
mapped angle passes 40 deg are dropped (the table must stay below the 45 deg flat-plate row). A thickness between the
two sections interpolates the rows linearly.

    python3 -I research/extra-300/ex14/sandia_polar.py <aircraft.json> <thickness 0.12-0.15> <out.json>
"""
import importlib.util
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
_spec = importlib.util.spec_from_file_location("avanti_polar", ROOT / "research/avanti-s/av17-r2/build_polar.py")
avanti = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(avanti)

MAX_MAPPED_DEG = 40.0
# [angle deg, CL, CD] at Re 360,000.
NACA_0012 = [[10, .9811, .0184], [11, .9132, .0204], [12, .4832, .0217], [13, .2759, .0222], [14, .2893, .1060],
             [15, .3306, .1900], [16, .3792, .2100], [17, .4455, .2310], [18, .5047, .2520], [19, .5591, .2740],
             [20, .6120, .2970], [21, .6643, .3200], [22, .7179, .3440], [23, .7715, .3690], [24, .8246, .3940],
             [25, .8780, .4200], [26, .9313, .4460], [27, .9846, .4730], [30, .9150, .5700]]
NACA_0015 = [[10, .9440, .0191], [11, .9572, .0211], [12, .9285, .0233], [13, .8562, .0257], [14, .7483, .0283],
             [15, .6350, .0312], [16, .5384, .1240], [17, .4851, .2170], [18, .4782, .2380], [19, .4908, .2600],
             [20, .5247, .2820], [21, .5616, .3050], [22, .6045, .3290], [23, .6528, .3540], [24, .7015, .3790],
             [25, .7511, .4050], [26, .8055, .4320], [27, .8788, .4600], [30, .8550, .5700]]
CD_AT_8_DEG = {0.12: .0153, 0.15: .0157}


def section(thickness):
    """Rows and the CD at 8 deg for a thickness between 0.12 and 0.15 (linear in thickness)."""
    if not 0.12 <= thickness <= 0.15:
        raise ValueError("thickness must lie between 0.12 (NACA 0012) and 0.15 (NACA 0015)")
    w = (thickness - 0.12) / 0.03
    rows = [[a, (1 - w) * c12 + w * c15, (1 - w) * d12 + w * d15] for (a, c12, d12), (_, c15, d15) in zip(NACA_0012, NACA_0015)]
    return rows, (1 - w) * CD_AT_8_DEG[0.12] + w * CD_AT_8_DEG[0.15]


def build(data, thickness):
    rows, cd8 = section(thickness)
    slope, offset = avanti._finite_wing_line(data)
    aero = data["aero"]
    cl_max, cla = aero["envelope"]["CL_max"]["value"], aero["coefficients"]["CLa"]["value"]
    cd0, cd90 = aero["coefficients"]["CD0"]["value"], aero["envelope"]["CD90"]["value"]
    scale = cl_max * (slope / cla) / max(row[1] for row in rows)
    angle_factor = scale * (0.11 * 180.0 / math.pi) / slope
    branches = {}
    for name, side in (("positive", 1.0), ("negative", -1.0)):
        values = [8.0, slope * math.radians(8.0) + side * offset, cd0, 1.0]
        fraction = 1.0
        for angle, cl, cd in rows:
            if angle * angle_factor > MAX_MAPPED_DEG:
                continue
            root = max(0.0, 2.0 * math.sqrt(cl / (0.11 * angle)) - 1.0)
            fraction = min(fraction, root * root)
            values += [angle * angle_factor, cl * scale, cd0 + cd - cd8, fraction]
        for angle in (45.0, 60.0, 75.0, 90.0):
            lift, drag = avanti.HIGH_ANGLE_FLAT_PLATE_FACTORS[angle]
            values += [angle, cd90 * lift, cd0 + cd90 * drag, 0.0]
        branches[name] = values
    return branches, scale, angle_factor


def main():
    source, thickness, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
    data = json.loads(Path(source).read_text())
    data["aero"].pop("wing_polar", None)
    branches, scale, angle_factor = build(data, thickness)
    note = f"EX-14h evidence-only Sandia candidate, t/c {thickness} (research/extra-300/ex14/sandia_polar.py)"
    data["aero"]["wing_polar"] = {"method": avanti.METHOD, "basis": avanti.BASIS, **{
        name: {"value": values, "unit": "deg, 1, 1, 1", "kind": "estimated", "source": note} for name, values in branches.items()}}
    Path(out).write_text(json.dumps(data, indent=1) + "\n")
    print(f"t/c {thickness}: CL scale {scale:.4f}, angle scale {angle_factor:.4f}")


if __name__ == "__main__":
    main()
