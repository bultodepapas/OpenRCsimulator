#!/usr/bin/env python3
"""SCENERY-PLAN: offline layout of the default field's scenery -> app/data/scenery/default.json (openrc-scenery v1).

Stdlib only, integers and hashes only (no RNG), so every run writes the same bytes; CI can run it with --check.
The layout follows the owner's reference photo (compact club on the pilot's side) inside the distance profile of
scenery report 03, and puts landmarks where the pilot can actually see them: it rebuilds the L6b treeline's own tree
heights (render/treeline.gd identity) and the skyline they draw from the pilot's eye, then picks low-skyline azimuths.

    python3 tools/scenery/place.py [--check] [--report]
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIELD = ROOT / "app/data/fields/default.json"
OUT = ROOT / "app/data/scenery/default.json"
EYE_M = 1.7


def q(value, unit, kind, source):
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def h01(*xs):
    """Integer hash -> [0, 1), stable across platforms."""
    h = 2166136261
    for x in xs:
        for b in int(x).to_bytes(8, "little", signed=True):
            h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    h ^= h >> 15
    h = (h * 2246822519) & 0xFFFFFFFF
    h ^= h >> 13
    return (h & 0xFFFF) / 65536.0


def tree_height(north, east):
    """render/treeline.gd identity(): the same integer recipe, so heights match the GPU's."""
    qn = int(round(north * 4.0)) + 2400
    qe = int(round(east * 4.0)) + 2400
    h = (qn * 7381 + qe * 19391 + 6113) % 65521
    h = (h * 25173 + 13849) % 65521
    return 12.0 + 13.0 * (h % 1024) / 1023.0


def load_field():
    field = json.loads(FIELD.read_text())
    trees = [o for o in field["objects"] if o["type"] == "treeline"][0]["positions"]["value"]
    runway = [s for s in field["surfaces"] if s["id"] == field["runway"]][0]
    return field, [(float(p[0]), float(p[1])) for p in trees], runway


def skyline(trees, step_deg=0.5):
    """Max elevation angle (deg) of the treeline per azimuth bin, crowns ~0.3 x height wide (estimated)."""
    bins = [0.0] * int(360 / step_deg)
    for n, e in trees:
        r = math.hypot(n, e)
        h = tree_height(n, e)
        el = math.degrees(math.atan2(h - EYE_M, r))
        az = math.degrees(math.atan2(e, n)) % 360
        half = math.degrees(math.asin(min(1.0, 0.3 * h / r)))
        a = az - half
        while a <= az + half:
            i = int((a % 360) / step_deg) % len(bins)
            bins[i] = max(bins[i], el)
            a += step_deg * 0.5
    return bins, step_deg


def sky_at(sky, az):
    bins, step = sky
    return bins[int((az % 360) / step) % len(bins)]


def clear_of_trees(trees, n, e, radius):
    return all((n - tn) ** 2 + (e - te) ** 2 >= radius ** 2 for tn, te in trees)


def polar(r, az_deg):
    a = math.radians(az_deg)
    return r * math.cos(a), r * math.sin(a)


def grid(x, step=0.25):
    return round(round(x / step) * step, 2)


def build():
    field, trees, runway = load_field()
    sky = skyline(trees)
    safety = runway["center_north"]["value"] - runway["width_north_south"]["value"] / 2
    groups = []
    report = []

    def inst(gid, zone, prefabs, rows, kind, source):
        rows = [[grid(n), grid(e), round(hd % 360, 1)] for n, e, hd in rows]
        g = {"id": gid, "type": "instances", "zone": zone, "collides": False}
        if len(prefabs) == 1:
            g["prefab"] = prefabs[0]
        else:
            g["prefabs"] = prefabs
        g["placements"] = q(rows, "m, m, deg", kind, source)
        groups.append(g)

    photo = "Owner's reference photo, laid out to satisfy the `photo` profile (scenery report 03); positions estimated"
    # --- the club, behind the pilot (south) ---
    inst("pit-shelters", "pits", ["pit_shelter"], [(-18.5, -31.0, 0), (-18.5, 31.0, 0)], "estimated",
         photo + "; two shelters toward each runway end, open to the field")
    inst("pavilion", "club", ["pavilion"], [(-22.0, 0.0, 0)], "estimated", photo + "; central white pavilion, veranda to the field")
    inst("club-sign", "club", ["club_sign"], [(-15.5, -9.5, 0)], "estimated", "Beside the pavilion, readable from the pilot line")
    inst("flagpole", "club", ["flagpole"], [(-16.0, 8.5, 315)], "estimated", "Flag streams NE: the field's breeze from the SW (sun side, estimated)")
    inst("picnic", "spectators", ["picnic_table"], [(-24.5, -9.5, 90), (-28.0, -9.0, 85), (-24.5, 9.8, 90), (-28.2, 10.4, 95)],
         "estimated", "Beside the pavilion, as at most club fields")
    inst("benches", "spectators", ["bench"], [(-16.5, -14.0, 0), (-16.5, -11.0, 0), (-16.5, 11.5, 0), (-16.5, 14.5, 0)],
         "estimated", "Spectator benches between the shelters and the pavilion, facing the field")
    inst("shed", "club", ["shed"], [(-40.5, -33.5, 90)], "estimated", photo + "; small shed by the van")
    club_trees = [(-49.0, -22.0), (-52.5, -13.0), (-48.5, -4.0), (-53.0, 4.5), (-49.5, 12.0), (-31.5, -9.0), (-32.0, 10.5), (-28.0, -52.0), (-29.0, 52.0), (-44.0, -40.0)]
    inst("shade-trees", "club", ["shade_tree"], [(n, e, h01(n, e) * 360) for n, e in club_trees], "estimated",
         photo + "; shade-tree clump behind the car row")
    bushes = [(-19.8, -6.4), (-24.5, -6.3), (-19.8, 6.4), (-24.8, 6.3), (-15.5, -20.5), (-15.5, 20.0)]
    inst("bushes", "club", ["bush"], [(n, e, h01(e, n) * 360) for n, e in bushes], "estimated", "Planting around the pavilion")
    clumps = [(-15.4, -5.0 + i * 1.1) for i in range(4)] + [(-15.4, 1.8 + i * 1.1) for i in range(3)]
    inst("flower-border", "club", ["flower_clump"], [(n, e, h01(n * 10, e * 10) * 360) for n, e in clumps], "estimated",
         "Flower border in front of the veranda")
    # people: one other pilot on the line, people in the pits, spectators on benches and by the veranda
    inst("pilots", "pilot_line", ["person_pilot"], [(0.0, -13.0, 5), (-0.5, 16.0, 350)], "estimated", "Other pilots on the flight line")
    inst("pits-people", "pits", ["person_standing"], [(-19.0, -38.5, 160), (-18.8, -25.5, 20), (-18.6, 25.0, 340), (-19.2, 37.5, 200), (-16.8, -33.0, 0)],
         "estimated", "Club members in the pits")
    inst("seated", "spectators", ["person_sitting"], [(-16.5, -14.0, 0), (-16.5, 11.5, 0), (-16.5, 14.5, 0)], "estimated", "Spectators on the benches")
    inst("veranda-people", "club", ["person_standing"], [(-17.4, -2.6, 10), (-17.8, 1.4, 350), (-16.4, 4.2, 30)], "estimated", "On the veranda steps")
    # parked fleet under the shelters, noses toward the field
    groups.append({"id": "fleet", "type": "fleet", "zone": "pits", "collides": False,
                   "aircraft": ["jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"],
                   "placements": q([[-17.6, -38.0, 15.0, 0], [-17.6, -24.0, 350.0, 1], [-17.8, 24.0, 10.0, 2], [-17.6, 38.5, 345.0, 3]],
                                   "m, m, deg, index", "estimated", "Under the pit shelters, as in the photo")})
    # the car row: nose-in toward the trees (BMFA: park near trees or a hedge), with one empty bay
    cars = []
    for i in range(10):
        if i == 6:
            continue
        cars.append((-38.0 + (h01(i, 3) - 0.5) * 0.4, -21.0 + i * 2.6 + (h01(i, 4) - 0.5) * 0.3, 180 + (h01(i, 5) - 0.5) * 8))
    cars += [(-41.0, -28.5, 95), (-37.5, -31.0, 200)]
    inst("cars", "parking", ["car_sedan", "car_hatch", "car_suv", "car_sport"], cars, "estimated",
         photo + "; 2.6 m bays (SC-01 photo estimate)")
    groups.append({"id": "car-park", "type": "patch", "zone": "parking", "surface": "gravel", "collides": False,
                   "points": q([[-33.5, -24.0], [-33.5, 5.5], [-35.0, 7.0], [-42.5, 7.0], [-43.5, 5.5], [-43.5, -34.5], [-42.0, -36.0], [-35.0, -36.0], [-33.5, -34.0]],
                               "m", "estimated", "Gravel strip under the car row")})
    # access track: through the treeline's designed SSW gap (azimuth 210 deg, tools/trees/place.py GAPS)
    track = [(-38.0, -36.5), (-46.0, -46.0), (-62.0, -55.0), (-100.0, -70.0)]
    for r in range(150, 701, 50):
        track.append(polar(r, 210.0))
    for n, e in track[3:]:
        assert clear_of_trees(trees, n, e, 6.0), (n, e)
    groups.append({"id": "access-track", "type": "track", "zone": "countryside", "surface": "dirt", "collides": False,
                   "width": q(3.2, "m", "estimated", "Single-lane farm track"),
                   "points": q([[grid(n), grid(e)] for n, e in track], "m", "estimated", "Through the L6b SSW gap (az 210 deg)")})
    # --- the countryside, in front ---
    bales = []
    for row in range(6):
        for k in range(8):
            n = 80.0 + row * 24.0 + (h01(row, k, 1) - 0.5) * 6.0
            e = 70.0 + k * 18.0 + (h01(row, k, 2) - 0.5) * 8.0 + (row % 2) * 9.0
            if h01(row, k, 3) < 0.78:
                bales.append((n, e, h01(row, k, 4) * 360))
    inst("hay-bales", "flight_box", ["round_bale"], bales, "estimated", "Round bales along mown rows (SC-12: the in-flight scale cue)")
    hedge = [[242.0, -300.0], [243.5, -150.0], [241.5, 40.0], [242.0, 58.0]]
    hedge2 = [[242.0, 72.0], [244.0, 180.0], [242.5, 300.0]]
    for gid, pts in (("hedge-north-w", hedge), ("hedge-north-e", hedge2)):
        groups.append({"id": gid, "type": "hedge", "zone": "countryside", "collides": False,
                       "height": q(1.8, "m", "estimated", "Field hedgerow"), "width": q(1.6, "m", "estimated", "Field hedgerow"),
                       "points": q(pts, "m", "estimated", "Just beyond the AMA flight box (229 m past the safety line)")})
    groups.append({"id": "fence-north", "type": "fence", "zone": "countryside", "style": "wire", "collides": False,
                   "points": q([[239.5, -300.0], [239.5, 300.0]], "m", "estimated", "Post-and-wire boundary in front of the hedge")})
    # paddock in the tree-free east corridor (no trees within 56 m of the runway's centre line, tools/trees/place.py)
    pad = [[-20.0, 330.0], [60.0, 330.0], [60.0, 440.0], [-20.0, 440.0], [-20.0, 330.0]]
    for n, e in pad:
        assert clear_of_trees(trees, n, e, 6.0)
    groups.append({"id": "paddock-fence", "type": "fence", "zone": "countryside", "style": "rail", "collides": False,
                   "points": q(pad, "m", "estimated", "Paddock outside the flight box's side (AMA: 305 m)")})
    animals = []
    for i in range(9):
        n = -10.0 + 64.0 * h01(i, 11)
        e = 342.0 + 86.0 * h01(i, 12)
        animals.append((n, e, h01(i, 13) * 360))
    inst("cows", "countryside", ["cow"], animals[:5], "estimated", "Grazing cattle (SC-14)")
    inst("sheep", "countryside", ["sheep"], animals[5:], "estimated", "A few sheep (SC-14)")
    inst("bale-stacks", "countryside", ["bale_stack"], [(-34.0, 318.0, 90), (-31.0, 321.5, 0)], "estimated", "Big square bales by the paddock gate")
    inst("tractor", "countryside", ["tractor"], [(-27.0, 326.0, 250)], "estimated", "A tractor by the bale stacks")
    # farmstead through the NNE gap (az 30 deg), beyond the treeline ring
    fn, fe = polar(690.0, 30.0)
    farm = [(fn, fe, 205.0, "barn"), (fn + 14.0, fe + 6.0, 0.0, "silo"), (fn - 6.0, fe - 24.0, 200.0, "farmhouse"), (fn - 12.0, fe + 4.0, 120.0, "tractor")]
    for n, e, hd, prefab in farm:
        inst("farm-" + prefab, "horizon" if math.hypot(n, e) >= 1000 else "countryside", [prefab], [(n, e, hd)], "estimated",
             "Farmstead seen through the treeline's NNE gap (az 30 deg)")
    # --- horizon landmarks where the skyline is low ---
    def lowest(az0, az1):
        best = None
        a = az0
        while a <= az1:
            s = max(sky_at(sky, a + d) for d in (-1.0, -0.5, 0.0, 0.5, 1.0))
            if best is None or s < best[1]:
                best = (a, s)
            a += 0.5
        return best
    v_az, v_sky = lowest(262.0, 300.0)
    vn, ve = polar(2100.0, v_az)
    village = [(vn, ve, 0.0, "church")]
    for i in range(7):
        a = v_az + (h01(i, 21) - 0.5) * 5.0
        r = 2100.0 + (h01(i, 22) - 0.5) * 260.0
        n, e = polar(r, a)
        village.append((n, e, h01(i, 23) * 360, "village_house"))
    inst("church", "horizon", ["church"], [village[0][:3]], "estimated", "Village church in the low-skyline west sector")
    inst("village", "horizon", ["village_house"], [v[:3] for v in village[1:]], "estimated", "Village around the church")
    t_az, t_sky = lowest(70.0, 110.0)
    turbines = []
    for i in range(4):
        n, e = polar(3900.0 + i * 220.0, t_az - 6.0 + i * 4.0)
        turbines.append((n, e, 250.0))
    inst("turbines", "horizon", ["turbine"], turbines, "estimated", "Wind farm in the east corridor; rotors face the SW breeze (and the pilot)")
    p_az, p_sky = lowest(88.0, 100.0)
    pylons = []
    for i in range(5):
        n, e = polar(1250.0 + i * 90.0, p_az - 3.0 + i * 1.5)
        pylons.append((n, e, p_az + 90.0))
    inst("pylons", "horizon", ["pylon"], pylons, "estimated", "Transmission line in the tree-free east corridor, in front of the wind farm")
    # --- wildflower cushions (SC-16): sizes >= d/386 m so each covers >= 2 px where it stands (report 02) ---
    flowers = []
    def strip(n0, n1, e0, e1, count, salt, min_size):
        """Clustered, like real meadow flowers: patch centres, then cushions spread around each (integers only)."""
        patches = max(1, count // 14)
        for i in range(count):
            c = i % patches
            cn = n0 + (n1 - n0) * h01(c, salt, 7)
            ce = e0 + (e1 - e0) * h01(c, salt, 8)
            spread = 0.6 + 2.4 * h01(c, salt, 9) * max(1.0, (n1 - n0) / 8.0)
            n = min(n1, max(n0, cn + (h01(i, salt, 1) + h01(i, salt, 4) - 1.0) * spread))
            e = min(e1, max(e0, ce + (h01(i, salt, 2) + h01(i, salt, 5) - 1.0) * spread * 1.6))
            d = max(1.0, math.hypot(n, e))
            size = max(min_size, d / 386.0) * (1.0 + 0.6 * h01(i, salt, 3))
            flowers.append([grid(n, 0.05), grid(e, 0.05), round(min(1.0, size), 3)])
    strip(22.0, 26.0, -70.0, 70.0, 700, 1, 0.18)    # beyond the runway's far edge
    strip(2.0, 7.5, -45.0, 45.0, 650, 2, 0.14)      # the grass between the pilot line and the runway
    strip(-14.0, -11.0, -46.0, 46.0, 420, 3, 0.14)  # in front of the pits
    strip(28.0, 62.0, -90.0, 90.0, 900, 4, 0.24)     # meadow patches in front
    strip(232.0, 238.0, -280.0, 280.0, 300, 5, 0.6) # the uncut margin along the boundary (gov.uk hay-meadow practice)
    groups.append({"id": "wildflowers", "type": "flowers", "zone": "countryside", "collides": False,
                   "positions": q(flowers, "m, m, size m", "derived", "tools/scenery/place.py strips; sizes >= d/386 m (scenery report 02)")})
    report += [("village/church", v_az, v_sky, 32.0, 2100.0), ("turbines", t_az, t_sky, 121.0, 4000.0),
               ("pylons", p_az, p_sky, 30.0, 1400.0), ("farmstead silo", 30.0, sky_at(sky, 30.0), 15.0, 705.0)]
    data = {
        "format": "openrc-scenery v1",
        "field": field["id"],
        "theme": "temperate",
        "generator": "tools/scenery/place.py",
        "profile": {
            "name": "photo",
            "pits_min_behind_m": q(13.7, "m", "manual", "AMA 2010: pit line a minimum of 45 ft behind the safety line (report 03)"),
            "spectators_min_behind_m": q(19.8, "m", "manual", "AMA 2010: spectator line a minimum of 65 ft (report 03)"),
            "parking_min_behind_m": q(24.4, "m", "manual", "AMA 2010: parking a minimum of 80 ft (report 03); the photo's compact car row (O-7)"),
            "pits_min_from_centreline_m": q(30.0, "m", "manual", "BMFA handbook 11.2(c): pits >= 30 m from the take-off and landing path"),
            "flight_box_depth_m": q(229.0, "m", "manual", "AMA 2022 sport field: 750 ft beyond the safety line"),
            "flight_box_half_width_m": q(305.0, "m", "manual", "AMA 2022 sport field: 1,000 ft each side"),
            "flight_box_max_height_m": q(1.5, "m", "estimated", "SCENERY-PLAN height rule: only low props in the flight box"),
            "approach_slope": q(0.05, "1", "borrowed", "ICAO Annex 14 code-1 approach surface 1:20, an analogy, not an RC rule"),
            "tree_clearance_m": q(3.0, "m", "estimated", "Keeps props off the L6b tree cards' trunks"),
            "runway_margin_m": q(3.0, "m", "estimated", "Keeps props off the runway edge"),
        },
        "groups": groups,
    }
    return data, report, sky


def dumps(data):
    text = json.dumps(data, indent=1, ensure_ascii=False)
    # one row of numbers per line: keeps the file short and diffable
    return re.sub(r"\[\s+([-0-9.,\s]+?)\s+\]", lambda m: "[" + ", ".join(x.strip() for x in m.group(1).split(",")) + "]", text) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="fail if the committed file differs from a fresh layout")
    ap.add_argument("--report", action="store_true", help="print landmark visibility against the treeline skyline")
    a = ap.parse_args()
    data, report, _ = build()
    text = dumps(data)
    if a.report:
        for name, az, sky_el, height, dist in report:
            top = math.degrees(math.atan2(height - EYE_M, dist))
            print(f"{name:16s} az {az:6.1f}  skyline {sky_el:5.2f} deg  top {top:5.2f} deg  {'VISIBLE' if top > sky_el else 'hidden'}")
    if a.check:
        if not OUT.exists() or OUT.read_text() != text:
            print(f"{OUT} differs from a fresh layout: run tools/scenery/place.py", file=sys.stderr)
            sys.exit(1)
        print("scenery layout matches the committed file")
        return
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT)}: {len(data['groups'])} groups")


if __name__ == "__main__":
    main()
