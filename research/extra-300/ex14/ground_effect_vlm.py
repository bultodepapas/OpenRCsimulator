#!/usr/bin/env python3
"""EX-14e: wing and tail ground effect of the Extra 300S .60 from the P-51's image-method Weissinger vortex lattice.

Reuses research/p51/p51-20/ground_effect_vlm.py unchanged (Biot-Savart horseshoes with ground images, solve, the
runtime law and its least-squares fit): only the planform it solves is replaced by the Extra's, read from
assets/aircraft/extra-300s-60/geometry.json (straight tapered wing, no dihedral, incidence or washout, on the chord
plane y -0.0525 m; the stabilizer quarter-chord line at y 0.0262 m, just above the thrust line). No fuselage, no
rolled-up wake, as for the P-51. x = (height of the aero reference point above the ground) / span.

    python3 research/extra-300/ex14/ground_effect_vlm.py           # prints the table and writes vlm_ground_effect.json
    python3 research/extra-300/ex14/ground_effect_vlm.py --check   # fails if vlm_ground_effect.json is stale
"""
import importlib.util
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
VLM = ROOT / "research/p51/p51-20/ground_effect_vlm.py"
GEOMETRY = ROOT / "assets/aircraft/extra-300s-60/geometry.json"
OUT = Path(__file__).resolve().with_name("vlm_ground_effect.json")

spec = importlib.util.spec_from_file_location("p51_ground_effect_vlm", VLM)
vlm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vlm)  # builds the P-51 panels; the Extra's replace them below

g = json.load(open(GEOMETRY))
W, T = g["wing"], g["tail"]
semi = W["span"] / 2
cr, ct = W["root_chord"], W["tip_chord"]
z_root = W["chord_plane_y"]
if W["dihedral_deg"] != 0.0 or W["incidence_deg"] != 0.0:
    raise ValueError("EX-14e: this planform builder assumes the Extra's flat, untwisted wing")


def chord(y):
    return cr + (ct - cr) * abs(y) / semi


def le_x(y):
    return W["le_z_root"] + (W["le_z_tip"] - W["le_z_root"]) * abs(y) / semi


edges = [-semi * math.cos(math.pi * k / (2 * vlm.N_SIDE)) for k in range(vlm.N_SIDE + 1)]
edges = edges + [-e for e in reversed(edges[:-1])]
panels = []
for y0, y1 in zip(edges, edges[1:]):
    ym = 0.5 * (y0 + y1)
    a = [le_x(y0) + 0.25 * chord(y0), y0, z_root]
    b = [le_x(y1) + 0.25 * chord(y1), y1, z_root]
    cp = [le_x(ym) + 0.75 * chord(ym), ym, z_root]
    panels.append({"a": a, "b": b, "cp": cp, "n": [0.0, 0.0, 1.0], "dy": y1 - y0, "dz": 0.0})
tail = {"stab_half_span": T["stab_half_span"], "stab_root_le_z": T["stab_root_le_z"], "stab_tip_le_z": T["stab_tip_le_z"],
        "stab_root_chord": T["elevator_root_corner"][1] - T["stab_root_le_z"],
        "stab_tip_chord": T["elevator_tip_te_z"] - T["stab_tip_le_z"], "stab_y": T["stab_y"]}
# The shared solver reads these module globals; nothing else of the P-51 planform remains in use.
vlm.panels, vlm.W, vlm.T, vlm.chord = panels, {"span": W["span"]}, tail, chord


def main():
    free = vlm.solve(None)
    rows = []
    for x in vlm.HEIGHTS:
        r = vlm.solve(z_root - x * W["span"])
        rows.append({"x": x, "cl_ratio_same_alpha": r["CL"] / free["CL"],
                     "cdi_ratio_same_cl": (r["CDi"] / r["CL"] ** 2) / (free["CDi"] / free["CL"] ** 2),
                     "tail_downwash_ratio_per_lift": (r["eps"] / r["CL"]) / (free["eps"] / free["CL"])})
    c_i, e_i, rms_i = vlm.fit([(r["x"], r["cdi_ratio_same_cl"]) for r in rows if r["x"] <= 1.5])
    c_t, e_t, rms_t = vlm.fit([(r["x"], r["tail_downwash_ratio_per_lift"]) for r in rows if r["x"] <= 1.5])
    raymer = [abs(vlm.law(r["x"], 33.0, 1.5) - r["cdi_ratio_same_cl"]) for r in rows if r["x"] <= 0.25]
    out = {
        "generator": "research/extra-300/ex14/ground_effect_vlm.py",
        "solver": "research/p51/p51-20/ground_effect_vlm.py",
        "geometry": "assets/aircraft/extra-300s-60/geometry.json",
        "method": f"image-method Weissinger VLM, {2 * vlm.N_SIDE} cosine-spaced panels, alpha {math.degrees(vlm.ALPHA):.1f} deg, ground plane parallel to the free stream, x = aero-reference-point height / span; no fuselage",
        "free_air": {"CL": free["CL"], "CLa_per_rad": free["CL"] / vlm.ALPHA, "e_trefftz": free["CL"] ** 2 / (math.pi * W["span"] ** 2 / free["area"] * free["CDi"]),
                     "tail_downwash_per_CL": free["eps"] / free["CL"]},
        "rows": rows,
        "fit_induced": {"coefficient": c_i, "exponent": e_i, "rms": rms_i, "range": "x 0.06-1.5, faded runtime law"},
        "fit_tail": {"coefficient": c_t, "exponent": e_t, "rms": rms_t, "range": "x 0.06-1.5, faded runtime law"},
        "raymer_33_1.5_faded_max_abs_error_to_x_0.25": max(raymer),
    }
    text = json.dumps(out, indent=2) + "\n"
    if "--check" in sys.argv:
        if not OUT.exists() or not vlm.same(json.loads(OUT.read_text()), json.loads(text)):
            print(f"stale: {OUT}")
            return 1
        print("current")
        return 0
    OUT.write_text(text)
    print(f"free air CL {free['CL']:.4f} (CLa {free['CL'] / vlm.ALPHA:.3f}/rad), e {out['free_air']['e_trefftz']:.3f}, tail eps/CL {free['eps'] / free['CL']:.4f} rad")
    print("   x    CL/CLinf  CDi/CDinf(CL)  eps/eps_inf per lift")
    for r in rows:
        print(f"{r['x']:5.2f}   {r['cl_ratio_same_alpha']:.4f}    {r['cdi_ratio_same_cl']:.4f}        {r['tail_downwash_ratio_per_lift']:.4f}")
    print(f"induced fit c {c_i:.3f} e {e_i:.4f} rms {rms_i:.4f}; Raymer 33/1.5 max |error| to 0.25: {max(raymer):.4f}")
    print(f"tail fit    c {c_t:.3f} e {e_t:.4f} rms {rms_t:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
