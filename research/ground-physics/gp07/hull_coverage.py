#!/usr/bin/env python3
"""GP-07a hull coverage, step 2: how deep can the drawn airframe sink into flat ground before a physics contact touches?

Reads hull_coverage_dump.gd's output (visible mesh-part convex hulls, crash_hull points and gear contacts, all in body
FRD about the CG). For each of N ground-down directions d on the unit sphere the ground first touches the point with the
largest d·p. gap(d) = max over drawn points − max over physics points: positive means the drawn airframe is already
`gap` metres inside the ground when physics first responds (visible clipping); negative means physics touches while the
drawing is still above the ground (a visible float). Propeller blades are left out: the propeller disc is a strike
test (E3d2), not a contact force, and the blade angle in the dump is arbitrary.

--candidate <json> evaluates a proposed hull ({"points": [[x_aft, y_right, z_up] in the LE frame...]}) instead of the
data's crash_hull. --greedy <tol_m> lists the drawn support points a greedy cover would add until every gap ≤ tol.

Run: python3 research/ground-physics/gp07/hull_coverage.py tmp/gp07/stik-dump.json [--candidate c.json] [--greedy 0.01]
"""
import argparse
import json
import math

import numpy as np

EXCLUDED_PARTS = ("propeller/propeller_blades",)


def fibonacci_sphere(n):
    i = np.arange(n) + 0.5
    phi = np.arccos(1.0 - 2.0 * i / n)
    theta = math.pi * (1.0 + 5.0 ** 0.5) * i
    return np.stack([np.cos(theta) * np.sin(phi), np.sin(theta) * np.sin(phi), np.cos(phi)], axis=1)


def le_to_body(points_le, cg):
    p = np.asarray(points_le, dtype=float).reshape(-1, 3)
    return np.stack([cg[0] - p[:, 0], p[:, 1] - cg[1], cg[2] - p[:, 2]], axis=1)


def attitude_of(d):
    """Pitch and roll (deg) of a body whose body-frame ground-down direction is d (yaw is irrelevant on flat ground)."""
    pitch = math.degrees(math.asin(max(-1.0, min(1.0, -d[0]))))
    roll = math.degrees(math.atan2(d[1], d[2]))
    return pitch, roll


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("--candidate", help="JSON with points [[x_aft, y_right, z_up], ...] in the LE frame (replaces crash_hull)")
    ap.add_argument("--directions", type=int, default=6000)
    ap.add_argument("--greedy", type=float, default=None, help="tolerance (m) for a greedy support-point cover")
    ap.add_argument("--json", help="write the summary as JSON here")
    ap.add_argument("--exclude", action="append", default=[],
                    help="also leave out parts whose node path contains this text (repeatable; e.g. propeller on "
                         "imported models, whose blades sit under other node names)")
    args = ap.parse_args()

    dump = json.load(open(args.dump))
    cg = dump["cg_le"]
    tags, drawn = [], []
    for part in dump["parts"]:
        if part["path"].startswith(EXCLUDED_PARTS) or any(text in part["path"] for text in args.exclude):
            continue
        pts = np.asarray(part["points"], dtype=float).reshape(-1, 3)
        drawn.append(pts)
        tags += [part["path"]] * len(pts)
    drawn = np.concatenate(drawn)
    tags = np.asarray(tags)

    hull = np.asarray(dump["hull"], dtype=float).reshape(-1, 3)
    labels = list(dump["hull_components"])
    if args.candidate:
        cand = json.load(open(args.candidate))
        hull = le_to_body(cand["points"], cg)
        labels = cand.get("labels", ["candidate_%d" % i for i in range(len(hull))])
    gear = np.asarray([g["position"] for g in dump["gear"]], dtype=float).reshape(-1, 3)
    physics = np.concatenate([hull, gear]) if len(gear) else hull
    physics_names = labels + ["gear:" + g["name"] for g in dump["gear"]]

    dirs = fibonacci_sphere(args.directions)
    vis = drawn @ dirs.T  # (points, directions)
    vis_max = vis.max(axis=0)
    vis_arg = vis.argmax(axis=0)
    phys = physics @ dirs.T
    phys_max = phys.max(axis=0)
    phys_arg = phys.argmax(axis=0)
    gap = vis_max - phys_max

    def summary(gap, phys_arg):
        order = np.argsort(-gap)
        worst = []
        seen = set()
        for k in order:
            part = tags[vis_arg[k]]
            if part in seen:
                continue
            seen.add(part)
            pitch, roll = attitude_of(dirs[k])
            worst.append({"part": part, "gap_mm": round(1000 * gap[k], 1), "pitch_deg": round(pitch, 1),
                          "roll_deg": round(roll, 1), "physics_contact": physics_names[phys_arg[k]],
                          "drawn_point_le": [round(v, 4) for v in [cg[0] - drawn[vis_arg[k]][0], drawn[vis_arg[k]][1] + cg[1], cg[2] - drawn[vis_arg[k]][2]]]})
            if len(worst) >= 15:
                break
        floats = np.argsort(gap)[:5]
        return {
            "directions": int(len(gap)),
            "max_penetration_mm": round(1000 * float(gap.max()), 1),
            "share_over_10mm": round(float((gap > 0.010).mean()), 3),
            "share_over_25mm": round(float((gap > 0.025).mean()), 3),
            "share_over_50mm": round(float((gap > 0.050).mean()), 3),
            "max_float_mm": round(-1000 * float(gap.min()), 1),
            "worst_parts": worst,
            "worst_floats": [{"physics_contact": physics_names[phys_arg[k]], "float_mm": round(-1000 * gap[k], 1),
                              "pitch_deg": round(attitude_of(dirs[k])[0], 1), "roll_deg": round(attitude_of(dirs[k])[1], 1)}
                             for k in floats],
        }

    result = {"aircraft": dump["aircraft"], "hull_points": int(len(hull)), "baseline": summary(gap, phys_arg)}

    if args.greedy is not None:
        added = []
        cur = phys_max.copy()
        for _ in range(64):
            g = vis_max - cur
            k = int(np.argmax(g))
            if g[k] <= args.greedy:
                break
            p = drawn[vis_arg[k]]
            added.append({"part": str(tags[vis_arg[k]]), "gap_mm": round(1000 * g[k], 1),
                          "point_le": [round(cg[0] - p[0], 4), round(p[1] + cg[1], 4), round(cg[2] - p[2], 4)]})
            cur = np.maximum(cur, dirs @ p)
        result["greedy"] = {"tolerance_mm": 1000 * args.greedy, "added": added,
                            "max_penetration_after_mm": round(1000 * float((vis_max - cur).max()), 1)}

    text = json.dumps(result, indent=1)
    if args.json:
        open(args.json, "w").write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
