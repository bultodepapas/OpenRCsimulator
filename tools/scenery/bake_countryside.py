"""LU-28: bounded agricultural parcels and connected roads for the Club plain.

Reuses downloaded ground photographs at runtime. Layout is an artistic estimate,
not map/survey data. Geometry follows the existing visual horizon exactly at
sampled vertices; it does not introduce physical terrain or road friction.
"""
import argparse
import bisect
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "app/data/scenery/countryside.json"
FIELD = ROOT / "app/data/fields/default.json"
SCENERY = ROOT / "app/data/scenery/default.json"
HORIZON = ROOT / "app/data/fields/horizon.json"
KINDS = {"crop": 0, "soil": 1, "highway": 2, "road": 3, "track": 4, "yard": 5}
PALETTE = ["#687242", "#8c8248", "#536638", "#99884e", "#716648", "#5e713e"]
HIGHWAY = [(-2200, 700), (-1400, 820), (-950, 860), (-430, 950),
           (-120, 940), (350, 960), (600, 930), (1000, 970),
           (1400, 1250), (1900, 1700)]
RURAL = [(-930, -1100), (-930, -880), (-720, -870), (-680, -850), (-680, -350),
         (-610, 100), (-450, 650), (-430, 950)]


def color(hex_color):
    return [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]


def nearest_on_path(point, path):
    candidates = []
    for a, b in zip(path, path[1:]):
        delta = [b[i] - a[i] for i in range(2)]
        fraction = max(0, min(1, sum((point[i] - a[i]) * delta[i] for i in range(2))
                              / sum(d * d for d in delta)))
        candidates.append(tuple(a[i] + delta[i] * fraction for i in range(2)))
    return min(candidates, key=lambda p: math.dist(point, p))


def horizon_sampler():
    profile = json.loads(HORIZON.read_text())
    radii = [r / 1000 for r in profile["radii_mm"]]
    heights = profile["heights_q"]
    count = profile["azimuth_samples"]

    def sample(n, e):
        radius = math.hypot(n, e)
        if radius <= radii[0] or radius >= radii[-1]:
            return 0.0
        angle = math.atan2(e, n) % math.tau
        col = int(angle / math.tau * count)
        # Locate the actual chord, not its circumscribed circle, near ring boundaries.
        projected_radius = radius * math.cos(angle - (col + 0.5) * math.tau / count)
        scaled_radii = [r * math.cos(math.pi / count) for r in radii]
        row = max(0, min(len(radii) - 2, bisect.bisect_right(scaled_radii, projected_radius) - 1))

        def point(r, c):
            a = c * math.tau / count
            return (radii[r] * math.cos(a), radii[r] * math.sin(a), heights[r][c % count] / 256)

        a, b = point(row, col), point(row, col + 1)
        c, d = point(row + 1, col), point(row + 1, col + 1)
        for p, q, r in ((a, c, b), (b, c, d)):
            denominator = (q[1] - r[1]) * (p[0] - r[0]) + (r[0] - q[0]) * (p[1] - r[1])
            u = ((q[1] - r[1]) * (n - r[0]) + (r[0] - q[0]) * (e - r[1])) / denominator
            v = ((r[1] - p[1]) * (n - r[0]) + (p[0] - r[0]) * (e - r[1])) / denominator
            if min(u, v, 1 - u - v) >= -1e-7:
                return u * p[2] + v * q[2] + (1 - u - v) * r[2]
        raise ValueError(f"Point outside located visual horizon cell: {n}, {e}")

    return sample


def generate():
    field = json.loads(FIELD.read_text())
    scenery = json.loads(SCENERY.read_text())
    trees = [p[:2] for obj in field["objects"] if obj["type"] == "treeline"
             for p in obj["positions"]["value"]]
    height = horizon_sampler()
    cells = {}
    parcels = []
    roads = []

    def quad(points, uvs, kind, width, tint, lift):
        centre_n = sum(p[0] for p in points) / 4
        centre_e = sum(p[1] for p in points) / 4
        key = f"{math.floor(centre_n / 600)}_{math.floor(centre_e / 600)}"
        cell = cells.setdefault(key, {"vertices": [], "indices": []})
        start = len(cell["vertices"])
        for (n, e), (u, v) in zip(points, uvs):
            # [render xyz, UV metres, material kind/width, RGB]; normals are up.
            cell["vertices"].append([round(e, 4), round(height(n, e) + lift, 4), round(-n, 4),
                                     round(u, 4), round(v, 4), kind, width, *[round(c, 5) for c in tint]])
        # Correct both input orientations; Godot front faces are clockwise.
        p, q, r = cell["vertices"][start:start + 3]
        cross_y = (q[2] - p[2]) * (r[0] - p[0]) - (q[0] - p[0]) * (r[2] - p[2])
        order = [0, 2, 1, 0, 3, 2] if cross_y > 0 else [0, 1, 2, 0, 2, 3]
        cell["indices"].extend(start + i for i in order)

    def rectangle(bounds, kind, tint, lift=0.045, rotate=False, shear=0.0, pivot=None):
        n0, e0, n1, e1 = bounds
        pivot = (n0 + n1) / 2 if pivot is None else pivot
        rows, cols = math.ceil((n1 - n0) / 32), math.ceil((e1 - e0) / 32)
        for row in range(rows):
            a, b = n0 + (n1 - n0) * row / rows, n0 + (n1 - n0) * (row + 1) / rows
            for col in range(cols):
                c, d = e0 + (e1 - e0) * col / cols, e0 + (e1 - e0) * (col + 1) / cols
                points = [(a, c), (b, c), (b, d), (a, d)]
                uvs = [(n - n0, e - e0) if rotate else (e - e0, n - n0) for n, e in points]
                points = [(n, e + (n - pivot) * shear) for n, e in points]
                quad(points, uvs, kind, e1 - e0, tint, lift)

    # Keep the club, lake, flight box and wooded ring intact. Fields occupy clear
    # outer land; a margin avoids painting crop rows through existing tree trunks.
    compounds = [(540, 265, 635, 385), (720, 590, 825, 700), (-745, -940, -620, -420),
                 (640, 440, 695, 485), (840, 590, 900, 650)]
    for ni, n in enumerate(range(-1200, 1201, 220)):
        for ei, e in enumerate(range(-1200, 1201, 220)):
            n0, e0 = n + 12, e + 12
            n1, e1 = n + 202 - ((ni * 13 + ei * 7) % 4) * 9, e + 202 - ((ni + ei) % 3) * 8
            near_n = 0 if n0 < 0 < n1 else min(abs(n0), abs(n1))
            near_e = 0 if e0 < 0 < e1 else min(abs(e0), abs(e1))
            if math.hypot(near_n, near_e) < 450 or max(math.hypot(a, b) for a in (n0, n1) for b in (e0, e1)) > 1440:
                continue
            if any(n0 - 12 < tn < n1 + 12 and e0 - 12 < te < e1 + 12 for tn, te in trees):
                continue
            if any(n0 < a1 and n1 > a0 and e0 < b1 and e1 > b0 for a0, b0, a1, b1 in compounds):
                continue
            index = (ni * 7 + ei * 11) % len(PALETTE)
            kind = KINDS["soil"] if index == 4 else KINDS["crop"]
            bounds = [n0, e0, n1, e1]
            shear = [-0.075, 0.035, 0.08, -0.025][(ni * 3 + ei) % 4]
            pivot = (n0 + n1) / 2
            rectangle(bounds, kind, color(PALETTE[index]), rotate=(ni + ei) % 2 == 0, shear=shear)
            # Narrow grass headlands and dark drainage margins form readable boundaries.
            rectangle([n0 - 2, e0, n0, e1], 0, color("#394729"), rotate=True, shear=shear, pivot=pivot)
            rectangle([n0, e0 - 2, n1, e0], 0, color("#435033"), shear=shear, pivot=pivot)
            parcels.append({"bounds_ne_m": bounds, "kind": kind, "row_axis": (ni + ei) % 2, "shear": shear})
    for bounds, tint in [([630, 280, 780, 430], "#8c8248"), ([470, 380, 550, 540], "#536638")]:
        assert not any(bounds[0] - 10 < n < bounds[2] + 10 and bounds[1] - 10 < e < bounds[3] + 10 for n, e in trees)
        rectangle(bounds, 0, color(tint))
        parcels.append({"bounds_ne_m": bounds, "kind": 0, "row_axis": 1, "shear": 0})
    berry_bed = [647, 447, 661, 462]
    rectangle(berry_bed, 1, color("#716648"))
    parcels.append({"bounds_ne_m": berry_bed, "kind": 1, "row_axis": 1, "shear": 0})

    def route(name, points, width, kind, tint, lift=0.085):
        # Bound corner cuts in metres so smoothing cannot pull a long straight
        # away from a driveway or gate. Keep junction endpoints unchanged.
        path = [points[0]]
        for a, b, c in zip(points, points[1:], points[2:]):
            ab, bc = math.dist(a, b), math.dist(b, c)
            cut = min(width * 2, ab * .2, bc * .2)
            entry = tuple(b[i] + (a[i] - b[i]) * cut / ab for i in range(2))
            leave = tuple(b[i] + (c[i] - b[i]) * cut / bc for i in range(2))
            path.append(entry)
            for step in range(1, 7):
                t = step / 6
                path.append(tuple((1 - t) ** 2 * entry[i] + 2 * (1 - t) * t * b[i]
                                  + t * t * leave[i] for i in range(2)))
        path.append(points[-1])
        # Bound chord lengths for depth precision and the existing horizon relief.
        dense = [path[0]]
        for a, b in zip(path, path[1:]):
            steps = max(1, math.ceil(math.dist(a, b) / 12))
            dense.extend([(a[0] + (b[0] - a[0]) * i / steps, a[1] + (b[1] - a[1]) * i / steps)
                         for i in range(1, steps + 1)])
        edges = []
        distance = 0.0
        for i, point in enumerate(dense):
            a, b = dense[max(0, i - 1)], dense[min(len(dense) - 1, i + 1)]
            length = math.dist(a, b)
            normal = (-(b[1] - a[1]) / length, (b[0] - a[0]) / length)
            if i:
                distance += math.dist(dense[i - 1], point)
            edges.append(([(point[0] + normal[0] * side * width / 2,
                            point[1] + normal[1] * side * width / 2) for side in (-1, 1)], distance))
        for a, b in zip(edges, edges[1:]):
            quad([a[0][0], b[0][0], b[0][1], a[0][1]],
                 [(-width / 2, a[1]), (-width / 2, b[1]), (width / 2, b[1]), (width / 2, a[1])],
                 kind, width, tint, lift)
        roads.append({"id": name, "kind": kind, "width_m": width,
                      "points_ne_m": points, "length_m": round(distance, 2),
                      "centerline_ne_m": [[round(n, 4), round(e, 4)] for n, e in dense]})
        return dense

    # Surface order/lifts keep junctions legible without stacked alpha or decals.
    route("divided-highway", HIGHWAY, 28, 2, color("#515351"), 0.075)
    village_path = route("village-road", RURAL, 6.5, 3, color("#61625c"), 0.085)
    route("west-village-road", [RURAL[0], (-950, -1200), (-600, -1550),
                               (-300, -1850), (-180, -2060)], 6.5, 3, color("#61625c"), 0.085)
    route("club-link", [(-606.25, -350), (-680, -350)], 4, 4, color("#948772"), 0.07)
    route("old-farm-link", [(609, 360), (609, 400), (575, 450), (560, 700),
                           (560, 850), (600, 930)], 4, 4, color("#948772"), 0.08)
    route("east-farm-link", [(738, 670), (738, 690), (720, 690), (610, 680),
                            (560, 700)], 4, 4, color("#948772"), 0.08)
    rectangle([578, 300, 625, 374], 5, color("#8a8474"), lift=0.095)
    rectangle([732, 600, 818, 685], 5, color("#8a8474"), lift=0.095)
    for group in scenery["groups"]:
        if group["id"] == "countryside-hamlet":
            for i, (n, e, _) in enumerate(group["placements"]["value"]):
                join = nearest_on_path((-680, e), village_path)
                route(f"house-drive-{i}", [join, (n, e)], 3.2, 4, color("#938a76"))
                rectangle([n - 9, e - 9, n + 9, e + 9], 5, color("#8b8778"), lift=0.09)
    triangles = sum(len(c["indices"]) // 3 for c in cells.values())
    assert len(parcels) >= 20, "Layout unexpectedly lost most agricultural parcels"
    assert triangles < 14000 and len(cells) <= 40, "Countryside exceeded static geometry budget"
    return (json.dumps({
        "format": "openrc-countryside v1", "generator": "tools/scenery/bake_countryside.py",
        "source": "Art-directed agricultural layout; estimated metres; existing visual horizon",
        "physical_terrain": False,
        "source_sha256": {str(p.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in (FIELD, SCENERY, HORIZON)},
        "parcels": parcels, "roads": roads, "triangles": triangles, "cells": cells,
    }, separators=(",", ":")) + "\n").encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    data = generate()
    if args.check:
        if args.output.read_bytes() != data:
            raise SystemExit("Countryside geometry is stale or edited")
        print("Countryside geometry matches retained field, scenery and horizon")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(data)
        result = json.loads(data)
        print(f"Wrote {len(result['parcels'])} parcels, {len(result['roads'])} routes, "
              f"{len(result['cells'])} cells, {result['triangles']} triangles ({len(data)} bytes)")


if __name__ == "__main__":
    main()
