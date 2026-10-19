#!/usr/bin/env python3
"""Airframe lift and drag polar of each aircraft in a flight-test run, beside measured RC-class polars.

Usage: python research/flight-test/polar_fit.py <out dir> [aircraft ...]
Reads profile.json from flight_test.gd (card v3 or later). From the static `aero_sweep` (production loads, neutral
controls, no propeller) it reports CL at α 0, the lift slope from α 0 to 5°, and a least-squares fit over α -5..10° of
CD = CDmin + K (CL - CL_md)², with e = 1/(π A K). The offset CL_md matters: a cambered wing's least drag is not at CL 0,
and a symmetric fit then returns e > 1. From the idle `glide` cases it reports the flown drag coefficient
CD = CL tan γ, with CL = W cos γ / (q S) at ρ 1.225 kg/m³, and its excess over the fitted airframe polar: the idle
propeller and trim drag together.

References (other airframes; sources in docs/research/flight-dynamics/rc-aero-data-sources.md):
- NASA FASER (Ultra Stick 120, A 4.78) wind tunnel, Ritchie 2013 table 4.3: CL0 0.113, CLα 0.0762/deg.
- Southampton FliTePlat (5.5 kg twin, A 7.87) wind tunnel, Weishäupl et al. 2024 table 2: CD0 0.0503, K 0.0764 (e 0.53),
  CL0 0.257, CLα 0.1122/deg; stationary propellers add 0.01-0.03 to CD.
"""
import json
import math
import sys
from pathlib import Path

RHO = 1.225
G = 9.80665
FIT_ALPHAS = (-5.0, 0.0, 5.0, 10.0)
REFERENCES = [
    "| FASER tunnel (Ultra Stick 120) | 4.8 | 0.113 | 0.0762 | – | – | – | – | – |",
    "| FliTePlat tunnel (Southampton) | 7.9 | 0.257 | 0.1122 | 0.0503 (CD0) | 0 | 0.0764 | 0.53 | stopped props +0.01–0.03 |",
]


def solve(matrix, vector):
    """Gaussian elimination with partial pivoting for a small dense system."""
    m = [row[:] + [v] for row, v in zip(matrix, vector)]
    n = len(m)
    for i in range(n):
        pivot = max(range(i, n), key=lambda r: abs(m[r][i]))
        m[i], m[pivot] = m[pivot], m[i]
        for r in range(n):
            if r != i:
                f = m[r][i] / m[i][i]
                m[r] = [a - f * b for a, b in zip(m[r], m[i])]
    return [m[i][n] / m[i][i] for i in range(n)]


def polar(sweep):
    rows = {row["alpha_deg"]: row for row in sweep if row["case"].startswith("alpha")}
    points = [(rows[a]["cl_lift"], rows[a]["cd"]) for a in FIT_ALPHAS]
    basis = [[1.0, cl, cl * cl] for cl, _ in points]
    normal = [[sum(b[i] * b[j] for b in basis) for j in range(3)] for i in range(3)]
    rhs = [sum(b[i] * cd for b, (_, cd) in zip(basis, points)) for i in range(3)]
    c0, c1, c2 = solve(normal, rhs)
    cl_md = -c1 / (2.0 * c2)
    return {"cl0": rows[0.0]["cl_lift"], "cla": (rows[5.0]["cl_lift"] - rows[0.0]["cl_lift"]) / 5.0,
            "cd_min": c0 - c1 * c1 / (4.0 * c2), "cl_md": cl_md, "k": c2}


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1])
    names = sys.argv[2:] or sorted(d.name for d in out.iterdir() if (d / "profile.json").exists())
    print("| Aircraft | A | CL at α 0 | CLα (/deg) | CDmin | CL at CDmin | K | e | Idle glide: CL / flown CD / excess |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for name in names:
        if not (out / name / "profile.json").exists():
            sys.exit(f"no profile.json for {name} in {out}")
        profile = json.loads((out / name / "profile.json").read_text())
        results = profile["results"]
        if "aero_sweep" not in results:
            print(f"| {name} | – | – | – | – | – | – | – | no aero_sweep (card before v3) |")
            continue
        area, span = float(profile["wing_area_m2"]), float(profile["span_m"])
        aspect = span * span / area
        p = polar(results["aero_sweep"]["table"])
        glides = []
        for row in results.get("glide", {}).get("table", []):
            if row["vertical_speed_mps"] >= 0.0:
                glides.append(f"{row['case']} no descent")
                continue
            gamma = math.radians(-row["path_angle_deg"])
            q = 0.5 * RHO * row["speed_mps"] ** 2
            cl = float(profile["mass_kg"]) * G * math.cos(gamma) / (q * area)
            cd = cl * math.tan(gamma)
            excess = cd - (p["cd_min"] + p["k"] * (cl - p["cl_md"]) ** 2)
            glides.append(f"{row['case']} {cl:.2f}/{cd:.3f}/{excess:+.3f}")
        print(f"| {name} | {aspect:.1f} | {p['cl0']:.3f} | {p['cla']:.4f} | {p['cd_min']:.4f} | {p['cl_md']:.2f} | {p['k']:.4f} | "
              f"{1.0 / (math.pi * aspect * p['k']):.2f} | {'; '.join(glides) or '–'} |")
    for line in REFERENCES:
        print(line)


if __name__ == "__main__":
    main()
