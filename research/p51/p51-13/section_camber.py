#!/usr/bin/env python3
"""P51-13: thin-airfoil zero-lift angle and Cm_ac of the real P-51D sections (NAA/NACA 45-100, UIUC root BL17.5 and
tip BL215 ordinates), from their camber lines instead of a parabolic camber assumption.

Thin-airfoil theory (Abbott & von Doenhoff, eqs. 4.24-4.26) with x = (1 - cos th)/2:
    alpha_0 = -(1/pi) int_0^pi (dz/dx)(cos th - 1) dth,   Cm_c/4 = (1/2) int_0^pi (dz/dx)(cos 2th - cos th) dth
The ordinates are gitignored (references/p51-mustang/airfoils, hashes in references/p51-mustang/index.json); the
results are written to section.json next to this script, which derive_physics.py reads (reproducible from a clone).

    python3 research/p51/p51-13/section_camber.py          # needs the downloaded .dat files
"""
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
AIRFOILS = ROOT / "references/p51-mustang/airfoils"
OUT = Path(__file__).with_name("section.json")


def read_selig(path):
    pts = []
    for line in path.read_text().splitlines()[1:]:
        parts = line.split()
        if len(parts) == 2:
            pts.append((float(parts[0]), float(parts[1])))
    i_le = min(range(len(pts)), key=lambda k: pts[k][0])
    upper = sorted(pts[: i_le + 1])
    lower = sorted(pts[i_le:])
    return upper, lower


def interp(rows, x):
    for (x0, y0), (x1, y1) in zip(rows, rows[1:]):
        if x0 <= x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0) if x1 > x0 else y0
    return rows[-1][1] if x > rows[-1][0] else rows[0][1]


def analyse(name):
    path = AIRFOILS / name
    upper, lower = read_selig(path)
    camber = lambda x: 0.5 * (interp(upper, x) + interp(lower, x))
    thick = lambda x: interp(upper, x) - interp(lower, x)
    n = 4000
    a0 = cm = 0.0
    h = 1e-4
    for k in range(n):
        th = math.pi * (k + 0.5) / n
        x = 0.5 * (1 - math.cos(th))
        slope = (camber(min(x + h, 1.0)) - camber(max(x - h, 0.0))) / (min(x + h, 1.0) - max(x - h, 0.0))
        a0 += slope * (math.cos(th) - 1) * math.pi / n
        cm += slope * (math.cos(2 * th) - math.cos(th)) * math.pi / n
    xs = [i / 1000 for i in range(1001)]
    tmax = max(xs, key=thick)
    cmax = max(xs, key=lambda x: abs(camber(x)))
    return {
        "file": f"references/p51-mustang/airfoils/{name}",
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "thickness": round(thick(tmax), 4), "thickness_x": tmax,
        "camber": round(camber(cmax), 4), "camber_x": cmax,
        "upper_ordinate_1.25pct": round(interp(upper, 0.0125), 4),
        "alpha0_deg": round(math.degrees(-a0 / math.pi), 3),
        "cm_ac": round(0.5 * cm, 4),
    }


out = {
    "source": "research/p51/p51-13/section_camber.py: thin-airfoil integrals over the UIUC P-51D ordinates (m-selig.ae.illinois.edu/ads/coord_database.html)",
    "root": analyse("p51droot-il-selig.dat"),
    "tip": analyse("p51dtip-il-selig.dat"),
}
OUT.write_text(json.dumps(out, indent=2) + "\n")
print(json.dumps(out, indent=2))
