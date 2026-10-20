"""Linear-theory inverted push from a measured trim gradient (no data files read).

Run: python3 -I inverted_push.py
In body axes, inverted level flight needs CL_body = -CL. With
Cm = Cm0 + Cm_CL*CL + Cm_de*de (linear), Cm0 cancels in the difference, so the
push from the upright trim at the same speed is |Δδe| = 2 * CL * |dδe/dCL|.
Thrust-line and slipstream terms at equal power also cancel; non-linear Cm(α),
negative-stall proximity and elevator-effectiveness asymmetry do not.
Sim masses are the inventory sums of app/data/aircraft/*.json at HEAD fbf6e97b (read-only); sim pushes are
quoted from docs/research/flight-dynamics/power-climb-2026-10-19/trim-practice-comparison.md (FT-05).
"""
import math

RHO, G = 1.225, 9.80665


def cl(m, S, V):
    return 2 * m * G / (RHO * S * V * V)


print("| Airframe | speed (m/s) | CL | dδe/dCL (deg) | predicted push 2·CL·dδe/dCL (deg) | simulator push (FT-05) |")
print("| --- | ---: | ---: | --- | --- | --- |")
rows = [
    ("Ultra Stick 25e (Thor), measured gradient", 1.90, 0.32, 17.0, (3.8, 7.5), "–"),
    ("Ultra Stick 120 (Baldr), nominal CG, measured", 7.41, 0.77, 23.0, (7.9, 12.1), "–"),
    ("Ultra Stick 120 (Baldr), aft CG, measured", 7.41, 0.77, 23.0, (5.2, 7.2), "–"),
    ("Sim Ugly Stik (2.88 kg), gradient from FT-05 sweep", 2.879, 0.4645, 19.6, (5.2, 5.9), "1.2"),
    ("Sim Extra 300S (3.58 kg)", 3.578, 0.48, 24.6, (7.6, 8.7), "2.4"),
    ("Sim P-51D 1/4 (21.5 kg)", 21.5, 1.3725, 34.9, (4.5, 5.1), "1.6"),
    ("Sim Ventage Jet (11.44 kg)", 11.439, 0.7023, 43.9, (5.5, 6.3), "1.3"),
    ("Sim Timber (2.19 kg)", 2.19, 0.327, 18.1, (14.0, 19.0), "8.8"),
]
for name, m, S, V, (lo, hi), sim in rows:
    c = cl(m, S, V)
    print(f"| {name} | {V:.1f} | {c:.2f} | {lo:.1f}–{hi:.1f} | {2*c*lo:.1f}–{2*c*hi:.1f} | {sim} |")
