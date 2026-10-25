#!/usr/bin/env python3
"""GP-07b: derive the Ugly Stik crash hull from its drawn model, so physics touches the ground where the airframe does.

The 2026-10 hull had 8 hand-placed points from the plan. GP-07a measured the drawn model sinking up to 104 mm into flat
ground before any of them touched (wing tip leading/trailing edges, tail skid, elevator tips, engine), and a fin-top
point 89 mm above the drawn fin, so an inverted Stik rested on a phantom fin. This generator reads the drawn model's
convex hulls (hull_coverage_dump.gd), takes each named feature as the drawn point furthest along a stated direction
within a stated part, mirrors left/right features, skips a feature closer than MIN_SPACING_M to an earlier one (points
bunched on one spot multiply its contact stiffness and damping), and drops features strictly inside the hull of the
others. The wheels do not count for that pruning: scenery collisions (posts, rails) test the hull alone, so the belly
stays. It refuses a hull that lets the drawn airframe sink deeper than TOLERANCE_M into flat ground (hull and wheels)
or SCENERY_TOLERANCE_M into a flat obstacle face (hull alone) in any of 6000 attitudes, or that bunches more than
MAX_CLUSTER points within the damping onset of one contact plane (propeller blades excepted: the disc is the E3d2
strike test). The legacy probe ids keep their meaning on their corrected points. Points on control surfaces sit at
neutral; a deflected trailing edge moves 1-5 cm off them (rudder most).

Usage:
  python3 research/ground-physics/gp07/derive_stik_hull.py [--dump tmp/gp07/stik-dump.json] [--check | --write]
Without --dump it runs the Godot dump itself (app/get-godot.sh, headless, about 3 s).
--write updates crash_hull, crash_hull_components and crash_hull_ids in the base Stik and the four synthetic electric
fixtures; then run research/glow-engines/build_installations.py (glow variants inherit the base) and
research/fuel-systems/FUEL-05/relabel_synthetic.py --check.
"""
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
import hull_coverage  # noqa: E402

AIRCRAFT_ID = "jensen-das-ugly-stik-60"
TARGETS = ["jensen_ugly_stik_60.json"] + ["synthetic_stik_electric_%s.json" % s for s in ("4s", "6s", "4s_battery", "6s_battery")]
TOLERANCE_M = 0.012
SCENERY_TOLERANCE_M = 0.015
MIN_SPACING_M = 0.02
# Contact damping is sized per point (hull_contact.gd: 2·ζ·ω on the point's smallest effective mass, 0.35 per tick at
# ζ 0.7, ω 60 rad/s, 240 Hz); n points at full damping on one spot give n·0.35, against RK4's real-axis limit 2.78.
MAX_CLUSTER = 5
CLUSTER_DEPTH_M = 0.004
# Landing-gear parts are covered by the wheel contacts; their round-wheel shape is GP-06 decision D2, reported only.
GEAR_PARTS = ("wheel_left_pivot", "wheel_right_pivot", "nose_steering_pivot", "main_gear_structure")
DIRECTIONS = 6000
SOURCE = (
    "GP-07b (research/ground-physics/gp07/derive_stik_hull.py): body points where the drawn Stik meets flat ground, "
    "read from the built visual model's convex hulls (hull_coverage_dump.gd) as the drawn point furthest along a stated "
    "direction inside a named part: wing tip leading edge, bottom and top crest, outer edge and aileron trailing edge "
    "(2.9 deg drawn dihedral), elevator trailing-edge tips, fin top, rudder top/trailing/bottom edges, tail skid, "
    "fuselage bottom corners, cylinder head and top of the side-mounted O.S. 61, propeller nut ({names}). Features "
    "closer than {spacing_mm:.0f} mm to an earlier one or strictly inside the hull of the others are dropped. Coverage "
    "over %d attitudes: the drawn airframe sinks at most {max_mm} mm into flat ground before a hull point or wheel "
    "touches, {scenery_mm} mm into a flat obstacle face before a hull point does (propeller blades excepted: E3d2 strike "
    "disc; the drawn wheels' round rims up to {wheel_mm} mm: GP-06 D2); control-surface points sit at neutral. "
    "Replaces the 2026-10 plan estimate (8 points; up to 104 mm). The wheels are landing_gear contacts, not hull "
    "points: a wheel on the ground is a landing, a leg pushed past its travel is a crash"
) % DIRECTIONS

# (id, label, part prefix, direction in the LE frame [x_aft, y_right, z_up], mirrored). Directions are for the right
# side; a mirrored feature also yields its left twin ("{s}" -> left/right, y of the direction negated).
FEATURES = [
    ("probe_wing_{s}_tip", "{s}_wing_tip", "wing_frame_{s}/wing_{s}_3", (0.0, 0.2, -1.0), True),
    ("probe_wing_{s}_le", "{s}_wing_tip", "wing_frame_{s}/wing_{s}_3", (-1.0, 0.2, 0.0), True),
    ("probe_wing_{s}_top", "{s}_wing_tip", "wing_frame_{s}/wing_{s}_3", (0.0, 0.2, 1.0), True),
    ("probe_wing_{s}_top_front", "{s}_wing_tip", "wing_frame_{s}/wing_{s}_3", (-0.25, 0.2, 1.0), True),
    ("probe_wing_{s}_le_top", "{s}_wing_tip", "wing_frame_{s}/wing_{s}_3", (-1.0, 0.2, 1.0), True),
    ("probe_wing_{s}_le_bottom", "{s}_wing_tip", "wing_frame_{s}/wing_{s}_3", (-1.0, 0.2, -1.0), True),
    ("probe_wing_{s}_outer", "{s}_wing_tip", "wing_frame_{s}/wing_{s}_3", (0.0, 1.0, 0.0), True),
    ("probe_wing_{s}_te", "{s}_wing_tip", "wing_frame_{s}/aileron_{s}_hinge/aileron_{s}", (1.0, 1.0, 0.0), True),
    ("probe_stabilizer_{s}_le", "{s}_stab_tip", "stab", (-0.3, 1.0, 0.0), True),
    ("probe_stabilizer_{s}_tip", "{s}_stab_tip", "elevator_hinge/elevator", (0.0, 1.0, 0.0), True),
    ("probe_fin_top", "fin_top", "fin", (0.0, 0.0, 1.0), False),
    ("probe_fin_top_le", "fin_top", "fin", (-1.0, 0.0, 1.0), False),
    ("probe_rudder_top_te", "fin_top", "rudder_hinge/rudder", (1.0, 0.0, 1.0), False),
    ("probe_rudder_te", "tail_end", "rudder_hinge/rudder", (1.0, 0.0, 0.0), False),
    ("probe_tail_end", "tail_end", "rudder_hinge/rudder", (1.0, 0.0, -1.0), False),
    ("probe_tail_skid", "tail_end", "tail_skid", (0.0, 0.0, -1.0), False),
    ("probe_fuselage_tail_bottom", "belly", "fuselage", (1.0, 0.0, -1.0), False),
    ("probe_nose_bottom_{s}", "nose", "fuselage", (-1.0, 1.0, -1.0), True),
    ("probe_nose_top_{s}", "nose", "fuselage", (-1.0, 1.0, 1.0), True),
    ("probe_belly_{s}", "belly", "fuselage", (0.0, 1.0, -1.0), True),
    ("probe_belly_main", "belly", "fuselage", (0.0, 0.0, -1.0), False),
    ("probe_engine_head", "engine", "engine_assembly", (-1.0, 1.0, 1.0), False),
    ("probe_engine_top", "engine", "engine_assembly", (0.0, 0.0, 1.0), False),
    ("probe_engine_front_top", "engine", "engine_assembly", (-0.8, -0.2, 1.0), False),
    ("probe_engine_front_bottom", "engine", "engine_assembly", (-1.0, 0.0, -1.0), False),
    ("probe_spinner_tip", "spinner", "propeller/engine_drive_front", (-1.0, 0.0, 0.0), False),
]
# A feature whose every direction stays this far inside the others' hull is redundant on flat ground.
INSIDE_M = 0.001
# Hull points are drawn points, so none may stand off the drawing by more than rounding.
FLOAT_M = 0.001


def run_dump(out_path):
    godot = subprocess.run([str(ROOT / "app/get-godot.sh")], capture_output=True, text=True, check=True).stdout.strip()
    subprocess.run([sys.executable, str(ROOT / "tools/godot/run_checked.py"), "--timeout", "300", "--", godot, "--headless",
                    "--path", str(ROOT / "app"), "--script", str(HERE / "hull_coverage_dump.gd"), "--",
                    "--aircraft=" + AIRCRAFT_ID, "--out=" + str(out_path)], check=True, capture_output=True, text=True)


def drawn_parts(dump):
    cg = dump["cg_le"]
    return {p["path"]: np.stack([cg[0] - np.asarray(p["points"]).reshape(-1, 3)[:, 0],
                                 np.asarray(p["points"]).reshape(-1, 3)[:, 1] + cg[1],
                                 cg[2] - np.asarray(p["points"]).reshape(-1, 3)[:, 2]], axis=1) for p in dump["parts"]}


def extract(parts, prefix, direction):
    pts = [v for k, v in parts.items() if k == prefix or k.startswith(prefix + "/")]
    if not pts:
        raise SystemExit("GP-07b: no drawn part '%s' (did the model change? update FEATURES)" % prefix)
    pts = np.concatenate(pts)
    u = np.asarray(direction, float)
    u /= np.linalg.norm(u)
    return pts[int(np.argmax(pts @ u))]


def features(parts):
    out = []
    for fid, label, prefix, direction, mirrored in FEATURES:
        sides = [("left", -1.0), ("right", 1.0)] if mirrored else [("", 1.0)]
        for side, sign in sides:
            d = (direction[0], sign * direction[1], direction[2])
            p = extract(parts, prefix.format(s=side), d)
            # + 0.0 turns a rounded -0.0 into 0.0: a signed zero does not survive every JSON round trip bit for bit.
            out.append({"id": fid.format(s=side), "label": label.format(s=side),
                        "point": [round(float(v), 4) + 0.0 for v in p]})
    return out


def coverage(dump, points_le):
    """Worst sinks of the drawn airframe into flat ground (hull and wheels) and into an obstacle face (hull alone),
    of the drawn gear, the worst float, the largest bunch of hull points near one contact plane, and each hull point's
    support margin against the other hull points."""
    cg = dump["cg_le"]
    dirs = hull_coverage.fibonacci_sphere(DIRECTIONS)
    parts = [p for p in dump["parts"] if not p["path"].startswith(hull_coverage.EXCLUDED_PARTS)]
    hull_proj = hull_coverage.le_to_body(points_le, cg) @ dirs.T
    gear = np.asarray([g["position"] for g in dump["gear"]], float).reshape(-1, 3)
    hull_max = hull_proj.max(axis=0)
    phys_max = np.maximum(hull_max, (gear @ dirs.T).max(axis=0)) if len(gear) else hull_max
    ground = {True: (-np.inf, ""), False: (-np.inf, "")}
    scenery = (-np.inf, "")
    drawn_max = np.full(len(dirs), -np.inf)
    for part in parts:
        proj = (np.asarray(part["points"]).reshape(-1, 3) @ dirs.T).max(axis=0)
        drawn_max = np.maximum(drawn_max, proj)
        is_gear = part["path"].startswith(GEAR_PARTS)
        gap = float((proj - phys_max).max())
        if gap > ground[is_gear][0]:
            ground[is_gear] = (gap, part["path"])
        if not is_gear and float((proj - hull_max).max()) > scenery[0]:
            scenery = (float((proj - hull_max).max()), part["path"])
    margins = [float((hull_proj[i] - np.delete(hull_proj, i, axis=0).max(axis=0)).max()) for i in range(len(hull_proj))]
    cluster = int((hull_proj >= hull_max - CLUSTER_DEPTH_M).sum(axis=0).max())
    return {"gap": ground[False][0], "part": ground[False][1], "wheel_gap": ground[True][0],
            "scenery_gap": scenery[0], "scenery_part": scenery[1], "float": float((phys_max - drawn_max).max()),
            "cluster": cluster, "margins": margins}


def derive(dump):
    parts = drawn_parts(dump)
    feats = []
    for feature in features(parts):
        near = [f for f in feats if np.linalg.norm(np.subtract(f["point"], feature["point"])) < MIN_SPACING_M]
        if near:
            print("GP-07b: %s is within %.0f mm of %s; skipped" % (feature["id"], 1000 * MIN_SPACING_M, near[0]["id"]))
            continue
        feats.append(feature)
    while True:
        margins = coverage(dump, [f["point"] for f in feats])["margins"]
        inside = [i for i, m in enumerate(margins) if m < -INSIDE_M]
        if not inside:
            break
        # Drop the deepest interior feature first, one at a time (a point can shadow another only while both exist).
        worst = min(inside, key=lambda i: margins[i])
        dropped = feats.pop(worst)
        print("GP-07b: %s is inside the hull by %.1f mm; dropped" % (dropped["id"], -1000 * margins[worst]))
    return feats, coverage(dump, [f["point"] for f in feats])


def render(raw):
    return (json.dumps(raw, indent=2, ensure_ascii=False) + "\n").replace("\n", "\r\n").encode("utf-8")


def apply(raw, feats, cov):
    raw["crash_hull"] = {"value": [f["point"] for f in feats], "unit": "m", "kind": "derived",
                         "source": SOURCE.format(max_mm=round(1000 * cov["gap"], 1), wheel_mm=round(1000 * cov["wheel_gap"], 1),
                                                 scenery_mm=round(1000 * cov["scenery_gap"], 1), spacing_mm=1000 * MIN_SPACING_M,
                                                 names=", ".join(f["id"] for f in feats))}
    raw["crash_hull_components"] = [f["label"] for f in feats]
    raw["crash_hull_ids"] = [f["id"] for f in feats]
    return raw


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dump")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = ap.parse_args()
    if args.dump:
        dump = json.load(open(args.dump))
    else:
        with tempfile.TemporaryDirectory() as tmp:
            run_dump(Path(tmp) / "dump.json")
            dump = json.load(open(Path(tmp) / "dump.json"))
    feats, cov = derive(dump)
    for f in feats:
        print("  %-30s %-15s %s" % (f["id"], f["label"], f["point"]))
    print("GP-07b: %d hull points; the drawn airframe sinks at most %.1f mm into the ground (%s) and %.1f mm into an "
          "obstacle face (%s), the drawn gear %.1f mm (round wheels, GP-06 D2); a hull point floats at most %.1f mm; "
          "at most %d points within %.0f mm of one contact plane"
          % (len(feats), 1000 * cov["gap"], cov["part"], 1000 * cov["scenery_gap"], cov["scenery_part"],
             1000 * cov["wheel_gap"], 1000 * max(0.0, cov["float"]), cov["cluster"], 1000 * CLUSTER_DEPTH_M))
    if cov["gap"] > TOLERANCE_M or cov["scenery_gap"] > SCENERY_TOLERANCE_M or cov["float"] > FLOAT_M \
            or cov["cluster"] > MAX_CLUSTER:
        sys.exit("GP-07b: outside the %.0f mm ground sink, %.0f mm obstacle sink, %.0f mm float or %d-point cluster "
                 "limits; add, move or space a named feature"
                 % (1000 * TOLERANCE_M, 1000 * SCENERY_TOLERANCE_M, 1000 * FLOAT_M, MAX_CLUSTER))
    ids = [f["id"] for f in feats]
    if len(set(ids)) != len(ids):
        sys.exit("GP-07b: duplicate hull ids")
    stale = []
    for name in TARGETS:
        path = ROOT / "app/data/aircraft" / name
        current = path.read_bytes()
        rendered = render(apply(json.loads(current.decode("utf-8")), feats, cov))
        if rendered != current:
            stale.append(name)
            if args.write:
                path.write_bytes(rendered)
    if args.check and stale:
        sys.exit("GP-07b: stale crash hull in " + ", ".join(stale))
    print("GP-07b: " + ("wrote " + ", ".join(stale) if args.write and stale else "aircraft data current" if not stale else "would update " + ", ".join(stale)))


if __name__ == "__main__":
    main()
