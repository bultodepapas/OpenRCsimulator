#!/usr/bin/env python3
"""P51-20: wing and tail ground effect of the 1/4-scale P-51D from an image-method Weissinger vortex lattice.

Reads the wing and tail planform from assets/aircraft/p51d-mustang-120/geometry.json (tapered, 5 deg dihedral, linear
washout, swept leading edge). One horseshoe per spanwise panel: bound vortex on the quarter-chord line, control point at
three quarters of the chord, trailing legs downstream parallel to the body axis. The ground is a mirror plane parallel
to the free stream (images with opposite circulation), as in OpenAeroStruct. No fuselage, no rolled-up wake.

Outputs the same-CL induced-drag ratio, the same-alpha lift ratio and the tail downwash ratio per unit wing lift as
functions of x = (height of the aero reference point above the ground) / span, the variable of
app/physics/ground_effect.gd, and fits that module's law sigma = c x^e / (1 + c x^e) to the induced and the tail ratios.

    python research/p51/p51-20/ground_effect_vlm.py            # prints the table and writes vlm_ground_effect.json
    python research/p51/p51-20/ground_effect_vlm.py --check    # fails if vlm_ground_effect.json is stale
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GEOMETRY = ROOT / "assets/aircraft/p51d-mustang-120/geometry.json"
OUT = Path(__file__).resolve().with_name("vlm_ground_effect.json")
N_SIDE = 40          # spanwise panels per side (cosine spacing)
ALPHA = math.radians(4.0)
FAR = 1.0e3          # trailing-leg length in spans (semi-infinite approximation)
HEIGHTS = [0.06, 0.08, 0.10, 0.12, 0.15, 0.20, 0.25, 0.30, 0.40, 0.50, 0.75, 1.00, 1.50]

g = json.load(open(GEOMETRY))
W, T = g["wing"], g["tail"]
semi = W["span"] / 2
cr, ct = W["root_chord"], W["tip_chord"]
dih = math.radians(W["dihedral_deg"])
inc_root = math.radians(W["incidence_deg"])
washout = math.radians(W["washout_deg"])
z_root = W["chord_plane_y"]      # the aero reference point lies on the root chord plane (derive_physics.py)
# Frame: x aft from the root leading edge, y right, z up (the physics le frame).


def chord(y):
    return cr + (ct - cr) * abs(y) / semi


def le_x(y):
    return W["le_z_root"] + (W["le_z_tip"] - W["le_z_root"]) * abs(y) / semi


def twist(y):
    return inc_root - washout * abs(y) / semi


def z_of(y):
    return z_root + abs(y) * math.tan(dih)


edges = [-semi * math.cos(math.pi * k / (2 * N_SIDE)) for k in range(N_SIDE + 1)]
edges = edges + [-e for e in reversed(edges[:-1])]
panels = []
for y0, y1 in zip(edges, edges[1:]):
    ym = 0.5 * (y0 + y1)
    a = [le_x(y0) + 0.25 * chord(y0), y0, z_of(y0)]
    b = [le_x(y1) + 0.25 * chord(y1), y1, z_of(y1)]
    cp = [le_x(ym) + 0.75 * chord(ym), ym, z_of(ym)]
    side = 1.0 if ym > 0 else -1.0
    th = twist(ym)
    normal = [math.sin(th), -side * math.cos(th) * math.sin(dih), math.cos(th) * math.cos(dih)]
    panels.append({"a": a, "b": b, "cp": cp, "n": normal, "dy": y1 - y0, "dz": b[2] - a[2]})


def segment(p, a, b):
    """Velocity at p of a unit-strength straight vortex a -> b (Biot-Savart)."""
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
    """Unit horseshoe (trailing legs from +far to a, a -> b, b to +far) plus its ground image."""
    far = FAR * W["span"]
    a, b = pan["a"], pan["b"]
    a_far, b_far = [a[0] + far, a[1], a[2]], [b[0] + far, b[1], b[2]]
    legs = [(a_far, a), (b, b_far)] + ([(a, b)] if bound else [])
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
    U = [math.cos(ALPHA), 0.0, math.sin(ALPHA)]    # air moving aft and up past the wing at positive alpha
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
    area = sum(0.5 * (chord(p["a"][1]) + chord(p["b"][1])) * abs(p["dy"]) for p in panels)
    lift = sum(gam[i] * p["dy"] for i, p in enumerate(panels))           # per rho U, Kutta-Joukowski on the bound legs
    CL = 2 * lift / area
    # Trefftz-plane induced drag: trailing legs only, normal wash at each bound-vortex midpoint (half the far wake's).
    drag = 0.0
    for i, pi in enumerate(panels):
        mid = [0.5 * (pi["a"][k] + pi["b"][k]) for k in range(3)]
        w = [0.0, 0.0, 0.0]
        for j, pj in enumerate(panels):
            v = horseshoe(mid, pj, ground, bound=False)
            w = [w[k] + gam[j] * v[k] for k in range(3)]
        wn = sum(w[k] * pi["n"][k] for k in range(3))
        drag -= gam[i] * wn * math.hypot(pi["dy"], pi["dz"])
    CDi = 2 * drag / area
    # Tail downwash: mean over the exposed stabilizer quarter-chord line (11 points, root to tip, both sides).
    eps = []
    for k in range(11):
        yt = T["stab_half_span"] * (-1 + 2 * k / 10)
        lam = abs(yt) / T["stab_half_span"]
        xt = T["stab_root_le_z"] + (T["stab_tip_le_z"] - T["stab_root_le_z"]) * lam + 0.25 * (T["stab_root_chord"] + (T["stab_tip_chord"] - T["stab_root_chord"]) * lam)
        pt = [xt, yt, T["stab_y"]]
        w = [0.0, 0.0, 0.0]
        for j, pj in enumerate(panels):
            v = horseshoe(pt, pj, ground)
            w = [w[q] + gam[j] * v[q] for q in range(3)]
        eps.append(-(w[2] * math.cos(ALPHA) - w[0] * math.sin(ALPHA)))   # downwash normal to the free stream
    return {"CL": CL, "CDi": CDi, "eps": sum(eps) / len(eps), "area": area}


FADE_SPAN_RATIO = 2.0  # app/physics/ground_effect.gd


def law(x, c, e):
    """GroundEffect.law(): c x^e / (1 + c x^e), faded C1 to exactly 1 at FADE_SPAN_RATIO (what the runtime applies)."""
    if x >= FADE_SPAN_RATIO:
        return 1.0
    t = c * x ** e
    u = x / FADE_SPAN_RATIO
    return 1.0 - (1.0 - t / (1 + t)) * (1.0 - u * u * (3.0 - 2.0 * u))


def fit(points):
    """Least-squares (c, e) of the module law over (x, sigma) points: coarse grid, then a refined grid."""
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


def main():
    free = solve(None)
    rows = []
    for x in HEIGHTS:
        ground = z_root - x * W["span"]
        r = solve(ground)
        cl_ratio = r["CL"] / free["CL"]
        cdi_same_cl = (r["CDi"] / r["CL"] ** 2) / (free["CDi"] / free["CL"] ** 2)
        tail_per_lift = (r["eps"] / r["CL"]) / (free["eps"] / free["CL"])
        rows.append({"x": x, "cl_ratio_same_alpha": cl_ratio, "cdi_ratio_same_cl": cdi_same_cl, "tail_downwash_ratio_per_lift": tail_per_lift})
    c_i, e_i, rms_i = fit([(r["x"], r["cdi_ratio_same_cl"]) for r in rows if r["x"] <= 1.5])
    c_t, e_t, rms_t = fit([(r["x"], r["tail_downwash_ratio_per_lift"]) for r in rows if r["x"] <= 1.5])
    raymer = [abs(law(r["x"], 33.0, 1.5) - r["cdi_ratio_same_cl"]) for r in rows if r["x"] <= 0.25]
    out = {
        "generator": "research/p51/p51-20/ground_effect_vlm.py",
        "geometry": "assets/aircraft/p51d-mustang-120/geometry.json",
        "method": f"image-method Weissinger VLM, {2 * N_SIDE} cosine-spaced panels, alpha {math.degrees(ALPHA):.1f} deg, ground plane parallel to the free stream, x = aero-reference-point height / span; no fuselage",
        "free_air": {"CL": free["CL"], "CLa_per_rad": free["CL"] / ALPHA, "e_trefftz": free["CL"] ** 2 / (math.pi * W["span"] ** 2 / free["area"] * free["CDi"]),
                     "tail_downwash_per_CL": free["eps"] / free["CL"]},
        "rows": rows,
        "fit_induced": {"coefficient": c_i, "exponent": e_i, "rms": rms_i, "range": "x 0.06-1.5, faded runtime law"},
        "fit_tail": {"coefficient": c_t, "exponent": e_t, "rms": rms_t, "range": "x 0.06-1.5, faded runtime law"},
        "raymer_33_1.5_faded_max_abs_error_to_x_0.25": max(raymer),
    }
    text = json.dumps(out, indent=2) + "\n"
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text() != text:
            print(f"stale: {OUT}")
            return 1
        print("current")
        return 0
    OUT.write_text(text)
    print(f"free air CL {free['CL']:.4f} (CLa {free['CL'] / ALPHA:.3f}/rad), e {out['free_air']['e_trefftz']:.3f}, tail eps/CL {free['eps'] / free['CL']:.4f} rad")
    print("   x    CL/CLinf  CDi/CDinf(CL)  eps/eps_inf per lift")
    for r in rows:
        print(f"{r['x']:5.2f}   {r['cl_ratio_same_alpha']:.4f}    {r['cdi_ratio_same_cl']:.4f}        {r['tail_downwash_ratio_per_lift']:.4f}")
    print(f"induced fit c {c_i:.3f} e {e_i:.4f} rms {rms_i:.4f}; Raymer 33/1.5 max |error| to 0.25: {max(raymer):.4f}")
    print(f"tail fit    c {c_t:.3f} e {e_t:.4f} rms {rms_t:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
