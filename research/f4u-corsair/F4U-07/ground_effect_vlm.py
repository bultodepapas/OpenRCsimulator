#!/usr/bin/env python3
"""F4U-07: ground-effect constants for the inverted-gull Corsair wing (image-method Weissinger VLM).

Same method and runtime law as the P-51's research/p51/p51-20/ground_effect_vlm.py, but the planform is the measured
one in assets/aircraft/f4u-corsair-250/geometry-r59.json: chord, leading edge, chord-plane height and incidence per
station, so the gull's low inner wing and its local dihedral enter every panel. The aero reference point is the root
chord plane on the centreline, as derive_physics.py writes it; x = its height above the ground / span.

    python research/f4u-corsair/F4U-07/ground_effect_vlm.py           # writes vlm_ground_effect.json
    python research/f4u-corsair/F4U-07/ground_effect_vlm.py --check   # fails if the file is stale
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GEOMETRY = ROOT / "assets/aircraft/f4u-corsair-250/geometry-r59.json"
OUT = Path(__file__).resolve().with_name("vlm_ground_effect.json")
N_SIDE = 40
ALPHA = math.radians(4.0)
FAR = 1.0e3
HEIGHTS = [0.06, 0.08, 0.10, 0.12, 0.15, 0.20, 0.25, 0.30, 0.40, 0.50, 0.75, 1.00, 1.50]
FADE_SPAN_RATIO = 2.0  # app/physics/ground_effect.gd

g = json.load(open(GEOMETRY))
WS, SS = g["wing_sections"], g["stabilizer_sections"]
SEMI = g["hull"]["wing_tip"][1]
SPAN = 2 * SEMI


def median_filter(values, half=3):
    return [sorted(values[max(0, i - half):i + half + 1])[len(values[max(0, i - half):i + half + 1]) // 2] for i in range(len(values))]


ys = [r["station"] for r in WS] + [SEMI]
chords = [r["chord"] for r in WS] + [0.0]
le_xs = [r["le"][0] for r in WS] + [WS[-1]["le"][0] + 0.5 * WS[-1]["chord"]]
zs = [r["mid"][2] for r in WS] + [WS[-1]["mid"][2]]
incs = median_filter([math.radians(r["incidence_deg"]) for r in WS]) + [math.radians(WS[-1]["incidence_deg"])]
Z_ARP = WS[0]["mid"][2]


def interp(y, values):
    y = abs(y)
    if y <= ys[0]:
        return values[0]
    for k in range(len(ys) - 1):
        if ys[k] <= y <= ys[k + 1]:
            t = (y - ys[k]) / (ys[k + 1] - ys[k])
            return values[k] + t * (values[k + 1] - values[k])
    return values[-1]


chord = lambda y: interp(y, chords)
le_x = lambda y: interp(y, le_xs)
z_of = lambda y: interp(y, zs)
twist = lambda y: interp(y, incs)

edges = [-SEMI * math.cos(math.pi * k / (2 * N_SIDE)) for k in range(N_SIDE + 1)]
edges = edges + [-e for e in reversed(edges[:-1])]
panels = []
for y0, y1 in zip(edges, edges[1:]):
    ym = 0.5 * (y0 + y1)
    a = [le_x(y0) + 0.25 * chord(y0), y0, z_of(y0)]
    b = [le_x(y1) + 0.25 * chord(y1), y1, z_of(y1)]
    cp = [le_x(ym) + 0.75 * chord(ym), ym, z_of(ym)]
    dih = math.atan2(b[2] - a[2], abs(y1 - y0)) * (1.0 if ym > 0 else -1.0)  # local dihedral, positive tip-up
    side = 1.0 if ym > 0 else -1.0
    th = twist(ym)
    normal = [math.sin(th), -side * math.cos(th) * math.sin(dih), math.cos(th) * math.cos(dih)]
    panels.append({"a": a, "b": b, "cp": cp, "n": normal, "dy": y1 - y0, "dz": b[2] - a[2], "c": chord(ym)})

stab_points = []
for r in SS[::max(1, len(SS) // 5)]:
    for s in (-1.0, 1.0):
        stab_points.append([r["le"][0] + 0.25 * r["chord"], s * r["station"], r["mid"][2]])


def segment(p, a, b):
    r1 = [p[i] - a[i] for i in range(3)]
    r2 = [p[i] - b[i] for i in range(3)]
    cx = [r1[1] * r2[2] - r1[2] * r2[1], r1[2] * r2[0] - r1[0] * r2[2], r1[0] * r2[1] - r1[1] * r2[0]]
    c2 = sum(v * v for v in cx)
    n1, n2 = math.sqrt(sum(v * v for v in r1)), math.sqrt(sum(v * v for v in r2))
    if c2 < 1e-14 or n1 < 1e-10 or n2 < 1e-10:
        return [0.0, 0.0, 0.0]
    r0 = [b[i] - a[i] for i in range(3)]
    k = (sum(r0[i] * r1[i] for i in range(3)) / n1 - sum(r0[i] * r2[i] for i in range(3)) / n2) / (4 * math.pi * c2)
    return [k * v for v in cx]


def horseshoe(p, pan, ground, bound=True):
    far = FAR * SPAN
    a, b = pan["a"], pan["b"]
    legs = [([a[0] + far, a[1], a[2]], a), (b, [b[0] + far, b[1], b[2]])] + ([(a, b)] if bound else [])
    v = [0.0, 0.0, 0.0]
    for s, e in legs:
        w = segment(p, s, e)
        v = [v[i] + w[i] for i in range(3)]
        if ground is not None:
            m = lambda q: [q[0], q[1], 2 * ground - q[2]]
            w = segment(p, m(s), m(e))
            v = [v[i] - w[i] for i in range(3)]
    return v


def solve(ground):
    n = len(panels)
    U = [math.cos(ALPHA), 0.0, math.sin(ALPHA)]
    A = [[sum(horseshoe(pi["cp"], pj, ground)[k] * pi["n"][k] for k in range(3)) for pj in panels] for pi in panels]
    rhs = [-sum(U[k] * pi["n"][k] for k in range(3)) for pi in panels]
    m = [A[i] + [rhs[i]] for i in range(n)]
    for p in range(n):
        piv = max(range(p, n), key=lambda i: abs(m[i][p]))
        m[p], m[piv] = m[piv], m[p]
        for i in range(p + 1, n):
            f = m[i][p] / m[p][p]
            if f:
                row_p = m[p]
                m[i] = [m[i][j] - f * row_p[j] for j in range(n + 1)]
    gam = [0.0] * n
    for i in reversed(range(n)):
        gam[i] = (m[i][n] - sum(m[i][j] * gam[j] for j in range(i + 1, n))) / m[i][i]
    area = sum(p["c"] * abs(p["dy"]) for p in panels)
    lift = sum(gam[i] * p["dy"] for i, p in enumerate(panels))
    CL = 2 * lift / area
    # Trefftz-plane induced drag. The P-51 tool reads the trailing legs at each bound-vortex midpoint (half the far
    # wake), which holds only for a straight, unswept bound line; this wing's quarter-chord line is kinked and its tip
    # swept, so the legs are read 100 spans downstream, where they act as infinite 2-D vortices, and halved.
    drag = 0.0
    x_trefftz = 100.0 * SPAN
    for i, pi in enumerate(panels):
        mid = [x_trefftz, 0.5 * (pi["a"][1] + pi["b"][1]), 0.5 * (pi["a"][2] + pi["b"][2])]
        w = [0.0, 0.0, 0.0]
        for j, pj in enumerate(panels):
            v = horseshoe(mid, pj, ground, bound=False)
            w = [w[k] + gam[j] * v[k] for k in range(3)]
        drag -= 0.5 * gam[i] * sum(w[k] * pi["n"][k] for k in range(3)) * math.hypot(pi["dy"], pi["dz"])
    CDi = 2 * drag / area
    eps = []
    for pt in stab_points:
        w = [0.0, 0.0, 0.0]
        for j, pj in enumerate(panels):
            v = horseshoe(pt, pj, ground)
            w = [w[q] + gam[j] * v[q] for q in range(3)]
        eps.append(-(w[2] * math.cos(ALPHA) - w[0] * math.sin(ALPHA)))
    return {"CL": CL, "CDi": CDi, "eps": sum(eps) / len(eps), "area": area}


def law(x, c, e):
    if x >= FADE_SPAN_RATIO:
        return 1.0
    t = c * x ** e
    u = x / FADE_SPAN_RATIO
    return 1.0 - (1.0 - t / (1 + t)) * (1.0 - u * u * (3.0 - 2.0 * u))


def fit(points):
    best = None
    c_lo, c_hi, e_lo, e_hi = 1.0, 200.0, 0.5, 3.0
    for _ in range(6):
        for i in range(41):
            c = c_lo * (c_hi / c_lo) ** (i / 40)
            for j in range(41):
                e = e_lo + (e_hi - e_lo) * j / 40
                s = sum((law(x, c, e) - y) ** 2 for x, y in points)
                if best is None or s < best[0]:
                    best = (s, c, e)
        _, c, e = best
        c_lo, c_hi = c / 1.5, c * 1.5
        span_e = (e_hi - e_lo) / 8
        e_lo, e_hi = max(0.3, e - span_e), e + span_e
    return best[1], best[2], math.sqrt(best[0] / len(points))


def same(a, b, rel=1e-9):
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k], rel) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y, rel) for x, y in zip(a, b))
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
        return abs(a - b) <= rel * max(1.0, abs(a), abs(b))
    return a == b


def main():
    free = solve(None)
    rows = []
    for x in HEIGHTS:
        r = solve(Z_ARP - x * SPAN)
        rows.append({"x": x, "cl_ratio_same_alpha": r["CL"] / free["CL"],
                     "cdi_ratio_same_cl": (r["CDi"] / r["CL"] ** 2) / (free["CDi"] / free["CL"] ** 2),
                     "tail_downwash_ratio_per_lift": (r["eps"] / r["CL"]) / (free["eps"] / free["CL"])})
    c_i, e_i, rms_i = fit([(r["x"], r["cdi_ratio_same_cl"]) for r in rows])
    c_t, e_t, rms_t = fit([(r["x"], r["tail_downwash_ratio_per_lift"]) for r in rows])
    out = {
        "generator": "research/f4u-corsair/F4U-07/ground_effect_vlm.py",
        "geometry": "assets/aircraft/f4u-corsair-250/geometry-r59.json",
        "method": f"image-method Weissinger VLM, {2 * N_SIDE} cosine-spaced panels on the measured gull planform (chord, leading edge, chord-plane height, median-filtered incidence), alpha {math.degrees(ALPHA):.1f} deg, ground parallel to the free stream, x = root-chord-plane height / span; no fuselage",
        "aero_reference_height_m": Z_ARP,
        "free_air": {"CL": free["CL"], "CLa_per_rad": free["CL"] / ALPHA, "area": free["area"],
                     "e_trefftz": free["CL"] ** 2 / (math.pi * SPAN ** 2 / free["area"] * free["CDi"]),
                     "tail_downwash_per_CL": free["eps"] / free["CL"]},
        "rows": rows,
        "fit_induced": {"coefficient": c_i, "exponent": e_i, "rms": rms_i, "range": "x 0.06-1.5, faded runtime law"},
        "fit_tail": {"coefficient": c_t, "exponent": e_t, "rms": rms_t, "range": "x 0.06-1.5, faded runtime law"},
    }
    text = json.dumps(out, indent=2) + "\n"
    if "--check" in sys.argv:
        if not OUT.exists() or not same(json.loads(OUT.read_text()), json.loads(text)):
            print(f"stale: {OUT}")
            return 1
        print("current")
        return 0
    OUT.write_text(text)
    print(f"free air CL {free['CL']:.4f} (CLa {free['CL'] / ALPHA:.3f}/rad), e {out['free_air']['e_trefftz']:.3f}, tail eps/CL {free['eps'] / free['CL']:.4f}")
    for r in rows:
        print(f"{r['x']:5.2f}   {r['cl_ratio_same_alpha']:.4f}    {r['cdi_ratio_same_cl']:.4f}        {r['tail_downwash_ratio_per_lift']:.4f}")
    print(f"induced fit c {c_i:.3f} e {e_i:.4f} rms {rms_i:.4f}; tail fit c {c_t:.3f} e {e_t:.4f} rms {rms_t:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
