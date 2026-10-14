"""D6e-R1: independent stick-fixed neutral point of the Jensen Ugly Stik from its own planform (wing + horizontal tail).

Horseshoe vortex lattice, bound leg at panel quarter chord, control point at three-quarter chord, trailing legs to +inf aft.
Frame: the aircraft JSON's le frame (x aft from the wing LE, y right, z up). Planar small-angle boundary condition.
No fuselage, propeller normal force or slipstream: each is expected to move the neutral point forward by a few % chord.
Geometry: wing 1.524 x 0.3048 m (720 sq in plan title block); stabilizer LE 0.7694 m, chord 0.1834 m, span 0.5588 m
from assets/aircraft/ugly-stik-60/geometry.json; wing 0.07 m above the thrust line, tail 0.0456 m below it.

Usage: python research/flight-dynamics/climb-trim/vlm_neutral_point.py
"""
import numpy as np

PLAN_CG = 0.394  # research/d1/jensen_plan_cg.py: 4.76 in aft of the LE on a 12.07 in chord


def _segment(points, a, b):
    r1, r2, r0 = points - a, points - b, b - a
    cross = np.cross(r1, r2)
    c2 = np.sum(cross * cross, axis=-1)
    with np.errstate(divide="ignore", invalid="ignore"):
        k = (np.sum(r0 * r1, axis=-1) / np.linalg.norm(r1, axis=-1)
             - np.sum(r0 * r2, axis=-1) / np.linalg.norm(r2, axis=-1)) / (4 * np.pi * c2)
    k[c2 < 1e-12] = 0.0
    return cross * k[..., None]


def _trailing(points, a):
    r = points - a
    d = np.array([1.0, 0.0, 0.0])
    cross = np.cross(d, r)
    c2 = np.sum(cross * cross, axis=-1)
    with np.errstate(divide="ignore", invalid="ignore"):
        k = (1.0 + np.sum(d * r, axis=-1) / np.linalg.norm(r, axis=-1)) / (4 * np.pi * c2)
    k[c2 < 1e-12] = 0.0
    return cross * k[..., None]


def _surface(le_x, span, chord, z, n_span, n_chord):
    ys = 0.5 * span * (1 - np.cos(np.linspace(0, np.pi, n_span + 1))) - 0.5 * span
    panels = []
    for j in range(n_span):
        for i in range(n_chord):
            fa, fm = (i + 0.25) / n_chord, (i + 0.75) / n_chord
            panels.append((np.array([le_x + fa * chord, ys[j], z]), np.array([le_x + fa * chord, ys[j + 1], z]),
                           np.array([le_x + fm * chord, 0.5 * (ys[j] + ys[j + 1]), z])))
    return panels


def _solve(panels, alpha=1e-3):
    a = np.array([p[0] for p in panels])
    b = np.array([p[1] for p in panels])
    c = np.array([p[2] for p in panels])
    aic = np.zeros((len(panels), len(panels)))
    for k in range(len(panels)):
        aic[:, k] = (_segment(c, a[k], b[k]) + _trailing(c, b[k]) - _trailing(c, a[k]))[:, 2]
    gamma = np.linalg.solve(aic, -np.sin(alpha) * np.ones(len(panels)))
    return gamma * (b[:, 1] - a[:, 1]), 0.5 * (a[:, 0] + b[:, 0])


def neutral_point(tail_le=0.7694, tail_chord=0.1834, tail_span=0.5588, gap=0.116, eta=1.0,
                  span=1.524, chord=0.3048, area=0.4645, alpha=1e-3):
    wing = _surface(0.0, span, chord, 0.07, 40, 6)
    lift, x = _solve(wing + _surface(tail_le, tail_span, tail_chord, 0.07 - gap, 20, 4), alpha)
    lift[len(wing):] *= eta
    wing_alone, wing_x = _solve(wing, alpha)
    cla = 2 * lift.sum() / (area * alpha)
    return {"neutral_point": (lift * x).sum() / lift.sum() / chord, "wing_ac": (wing_alone * wing_x).sum() / wing_alone.sum() / chord,
            "CLa_wing": 2 * wing_alone.sum() / (area * alpha), "CLa_total": cla}


if __name__ == "__main__":
    base = neutral_point()
    print({k: round(float(v), 4) for k, v in base.items()})
    for label, kwargs in [("baseline", {}), ("tail quarter chord at model position 0.8409", {"tail_le": 0.8409 - 0.25 * 0.1834}),
                          ("tail efficiency 0.9", {"eta": 0.9}), ("tail efficiency 0.85", {"eta": 0.85}),
                          ("wing-tail gap 0.06 m", {"gap": 0.06}), ("wing-tail gap 0.18 m", {"gap": 0.18}),
                          ("tail chord 0.171 m (area/span)", {"tail_chord": 0.171})]:
        r = neutral_point(**kwargs)
        margin = r["neutral_point"] - PLAN_CG
        print(f"{label:45s} NP={r['neutral_point'] * 100:5.1f}% chord  margin at plan CG={margin * 100:+5.1f}%  "
              f"Cma_cg={-margin * r['CLa_total']:+.3f}/rad")
    print("model: Cma=-0.723 about an ARP at the plan CG, CLa=4.58 -> implied NP at", round((PLAN_CG + 0.723 / 4.58) * 100, 1), "% chord")
