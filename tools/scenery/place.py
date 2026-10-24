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
LAKE = ROOT / "app/data/fields/lake.json"
OUT = ROOT / "app/data/scenery/default.json"
EYE_M = 1.7
BALE_RADIUS_M = math.sqrt(0.6 ** 2 + 0.6 ** 2)  # round_bale's conservative horizontal circumscribed radius
BALE_LAKE_CLEARANCE_M = 2.0
BALE_CENTER_GAP_M = BALE_RADIUS_M * 2.0 + 0.25
SAPLING_FOOTPRINT_RADIUS_M = 2.2
SAPLING_LAKE_CLEARANCE_M = 8.0
TREE_CLEARANCE_M = 3.0


def catalog_fleet_ids():
    """Use the flight selector as authority and validate the parked fleet's independent snapshot subset.

    Parked snapshots are independent of the playable catalog: TT-08 can make an aircraft flyable before the optional
    TT-13b scenery snapshot exists. PREVIEW entries (status = PREVIEW, data = "") are excluded from flyable ids.
    """
    catalog_text = (ROOT / "app/app_state/aircraft_catalog.gd").read_text()
    entries = catalog_text.split("const ENTRIES := [", 1)[1].split("\n]", 1)[0]
    catalog_ids = []
    for block in re.findall(r"\{(.*?)\n\t\}", entries, re.DOTALL):
        ids = re.findall(r'^\s*id\s*=\s*"([^"]+)"', block, re.MULTILINE)
        if not ids:
            continue
        preview = re.search(r"^\s*status\s*=\s*PREVIEW\b", block, re.MULTILINE) or re.search(r'^\s*data\s*=\s*""', block, re.MULTILINE)
        if preview:
            continue
        catalog_ids.append(ids[0])
    models_text = (ROOT / "app/scenery/parked_aircraft.gd").read_text(encoding="utf-8")
    fleet_match = re.search(r"const AIRCRAFT := \{([^}]+)\}", models_text, re.DOTALL)
    if fleet_match is None:
        raise ValueError("app/scenery/parked_aircraft.gd has no AIRCRAFT source map")
    source_ids = [key for key, _value in re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', fleet_match.group(1))]
    if not catalog_ids:
        raise ValueError("app/app_state/aircraft_catalog.gd has no readable catalog ids")
    if not source_ids:
        raise ValueError("parked AIRCRAFT source map must contain at least one snapshot")
    if len(source_ids) != len(set(source_ids)):
        raise ValueError("parked AIRCRAFT source map contains duplicate snapshot ids")
    invalid = sorted(set(source_ids) - set(catalog_ids))
    if invalid:
        raise ValueError("parked fleet snapshot ids must be flyable catalog entries (invalid=%s)" % invalid)
    return source_ids


def catalog_car_sizes():
    """Read the baked render footprints so parking clearance follows model geometry."""
    models_text = (ROOT / "app/scenery/models.gd").read_text()
    sizes = {}
    for model_id in ("car_sedan", "car_hatch", "car_suv", "car_sport"):
        match = re.search(r'^\s*"' + model_id + r'"\s*:\s*\{size = Vector3\(([^,]+),\s*([^,]+),\s*([^)]+)\)',
                          models_text, re.MULTILINE)
        if match is None:
            raise ValueError("app/scenery/models.gd has no footprint for " + model_id)
        sizes[model_id] = (float(match.group(1)), float(match.group(3)))
    return sizes


def loader_seed(text):
    """Mirror scenery_loader.gd's deterministic FNV-1a choice for a multi-prefab group."""
    h = 2166136261
    for byte in text.encode("utf-8"):
        h = ((h ^ byte) * 16777619) & 0xFFFFFFFF
    return h


def vegetation_alias_choices(prefab):
    """Read one runtime vegetation alias list so generated group IDs follow its real ordering."""
    source = (ROOT / "app/scenery/imported_vegetation.gd").read_text(encoding="utf-8")
    match = re.search(r'^\s*"' + re.escape(prefab) + r'"\s*:\s*\[(.*?)\]', source, re.MULTILINE | re.DOTALL)
    if match is None:
        raise ValueError("app/scenery/imported_vegetation.gd has no %s alias list" % prefab)
    choices = re.findall(r'"([^"]+)"', match.group(1))
    if not choices:
        raise ValueError("app/scenery/imported_vegetation.gd has an empty %s alias list" % prefab)
    return choices


def maple_group_id(base):
    """Choose a readable deterministic ID whose shade_tree seed resolves to the downloaded Maple."""
    choices = vegetation_alias_choices("shade_tree")
    if "maple_tree" not in choices:
        raise ValueError("shade_tree alias must include maple_tree for the Maple distribution")
    maple_index = choices.index("maple_tree")
    for suffix in range(1000):
        group_id = "%s-%03d" % (base, suffix)
        group_seed = loader_seed(group_id) & 0x7FFFFFFF
        if group_seed % len(choices) == maple_index:
            return group_id
    raise ValueError("could not find a stable shade_tree group ID resolving to maple_tree")


def car_polygon(north, east, heading_deg, size):
    """The model's XZ footprint transformed by scenery.gd's heading and NED placement."""
    half_width, half_length = size[0] * 0.5, size[1] * 0.5
    angle = math.radians(heading_deg)
    c, s = math.cos(angle), math.sin(angle)
    center_x, center_z = east, -north
    return [(center_x + x * c - z * s, center_z + x * s + z * c)
            for x, z in ((-half_width, -half_length), (half_width, -half_length),
                         (half_width, half_length), (-half_width, half_length))]


def _cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _on_segment(p, a, b):
    return (min(a[0], b[0]) - 1e-9 <= p[0] <= max(a[0], b[0]) + 1e-9
            and min(a[1], b[1]) - 1e-9 <= p[1] <= max(a[1], b[1]) + 1e-9)


def _segments_intersect(a, b, c, d):
    ab_c, ab_d = _cross(a, b, c), _cross(a, b, d)
    cd_a, cd_b = _cross(c, d, a), _cross(c, d, b)
    return ((ab_c * ab_d < 0 and cd_a * cd_b < 0)
            or (abs(ab_c) < 1e-9 and _on_segment(c, a, b))
            or (abs(ab_d) < 1e-9 and _on_segment(d, a, b))
            or (abs(cd_a) < 1e-9 and _on_segment(a, c, d))
            or (abs(cd_b) < 1e-9 and _on_segment(b, c, d)))


def _point_segment_distance(point, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    length2 = dx * dx + dz * dz
    t = max(0.0, min(1.0, ((point[0] - a[0]) * dx + (point[1] - a[1]) * dz) / length2))
    return math.hypot(point[0] - a[0] - t * dx, point[1] - a[1] - t * dz)


def polygon_gap(a, b):
    """Exact Euclidean edge gap between two convex rectangular footprints."""
    for i in range(4):
        for j in range(4):
            if _segments_intersect(a[i], a[(i + 1) % 4], b[j], b[(j + 1) % 4]):
                return 0.0
    return min([_point_segment_distance(point, b[j], b[(j + 1) % 4])
                for point in a for j in range(4)]
               + [_point_segment_distance(point, a[j], a[(j + 1) % 4])
                  for point in b for j in range(4)])


def check_car_clearance(rows, choices, sizes, minimum_gap=0.30, obstacles=()):
    """Refuse overlapping or too-close parked vehicles using the loader's actual chosen models."""
    footprints = []
    for i, row in enumerate(rows):
        model_id = choices[loader_seed("cars/%d" % i) % len(choices)]
        footprints.append((model_id, car_polygon(row[0], row[1], row[2], sizes[model_id])))
    for i, (model_a, polygon_a) in enumerate(footprints):
        for name, polygon_b in obstacles:
            gap = polygon_gap(polygon_a, polygon_b)
            if gap + 1e-6 < minimum_gap:
                raise ValueError("parked car %d (%s) intersects %s clearance: %.3f m" % (i, model_a, name, gap))
        for j in range(i + 1, len(footprints)):
            model_b, polygon_b = footprints[j]
            gap = polygon_gap(polygon_a, polygon_b)
            if gap + 1e-6 < minimum_gap:
                raise ValueError("parked cars %d (%s) and %d (%s) have only %.3f m clearance; need %.2f m" %
                                 (i, model_a, j, model_b, gap, minimum_gap))


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


def clear_of_tree_segment(trees, start, end, radius):
    return all(_point_segment_distance((tn, te), start, end) >= radius for tn, te in trees)


def polar(r, az_deg):
    a = math.radians(az_deg)
    return r * math.cos(a), r * math.sin(a)


def grid(x, step=0.25):
    return round(round(x / step) * step, 2)


def lake_bank_polygon():
    """Read the canonical lake-bank footprint in the field's absolute N/E frame."""
    lake = json.loads(LAKE.read_text())
    origin = lake["origin"]
    north = float(origin["north_m"])
    east = float(origin["east_m"])
    return [(north + float(point[0]), east + float(point[1]))
            for point in lake["bank_offsets_ne_m"]]


def _point_in_polygon(point, polygon):
    """Boundary-inclusive point-in-polygon test in north/east coordinates."""
    if any(_point_segment_distance(point, polygon[i], polygon[(i + 1) % len(polygon)]) <= 1e-9
           for i in range(len(polygon))):
        return True
    north, east = point
    inside = False
    for i, a in enumerate(polygon):
        b = polygon[(i + 1) % len(polygon)]
        if (a[1] > east) != (b[1] > east):
            crossing_north = (b[0] - a[0]) * (east - a[1]) / (b[1] - a[1]) + a[0]
            if north < crossing_north:
                inside = not inside
    return inside


def bank_footprint_clearance(north, east, radius, bank=None):
    """Signed edge gap from a circular conservative footprint to the lake bank."""
    bank = lake_bank_polygon() if bank is None else bank
    center = (north, east)
    edge_distance = min(_point_segment_distance(center, bank[i], bank[(i + 1) % len(bank)])
                        for i in range(len(bank)))
    if _point_in_polygon(center, bank):
        return -(edge_distance + radius)
    return edge_distance - radius


def bale_bank_clearance(north, east, bank=None):
    """Signed edge gap from a round bale's conservative footprint to the lake bank."""
    return bank_footprint_clearance(north, east, BALE_RADIUS_M, bank)


def original_hay_bales():
    """Stable source rows: their sequence defines runtime prop IDs."""
    bales = []
    for row in range(6):
        for k in range(8):
            north = 80.0 + row * 24.0 + (h01(row, k, 1) - 0.5) * 6.0
            east = 70.0 + k * 18.0 + (h01(row, k, 2) - 0.5) * 8.0 + (row % 2) * 9.0
            if h01(row, k, 3) < 0.78:
                bales.append((grid(north), grid(east), round(h01(row, k, 4) * 360.0 % 360.0, 1)))
    return bales


def relocate_hay_bales(rows=None, bank=None):
    """Move only bales whose full footprint is too close to the lake, preserving row order.

    A deterministic quarter-metre expanding grid chooses the nearest bank-safe position
    that also keeps the bale clear of every other bale. Since the caller retains the
    row index, runtime damage/placement IDs do not change.
    """
    bank = lake_bank_polygon() if bank is None else bank
    source = original_hay_bales() if rows is None else rows
    result = [[grid(row[0]), grid(row[1]), round(float(row[2]) % 360.0, 1)] for row in source]
    moved_indices = [i for i, row in enumerate(result)
                     if bale_bank_clearance(row[0], row[1], bank) + 1e-9 < BALE_LAKE_CLEARANCE_M]
    accepted = [tuple((row[0], row[1])) for i, row in enumerate(result) if i not in moved_indices]
    for index in moved_indices:
        original_north, original_east = result[index][0], result[index][1]
        relocated = None
        # Search nearest grid ring first; sorting each ring by distance and then N/E
        # makes ties stable across Python versions and platforms.
        for ring in range(1, 601):
            offsets = []
            for delta in range(-ring, ring + 1):
                offsets.append((delta, -ring))
                offsets.append((delta, ring))
            for delta in range(-ring + 1, ring):
                offsets.append((-ring, delta))
                offsets.append((ring, delta))
            offsets.sort(key=lambda pair: (pair[0] * pair[0] + pair[1] * pair[1], pair[0], pair[1]))
            for dn, de in offsets:
                north = round(original_north + dn * 0.25, 2)
                east = round(original_east + de * 0.25, 2)
                if bale_bank_clearance(north, east, bank) + 1e-9 < BALE_LAKE_CLEARANCE_M:
                    continue
                if any(math.hypot(north - other_n, east - other_e) + 1e-9 < BALE_CENTER_GAP_M
                       for other_n, other_e in accepted):
                    continue
                relocated = (north, east)
                break
            if relocated is not None:
                break
        if relocated is None:
            raise ValueError("could not relocate hay bale %d outside the lake-bank clearance" % index)
        result[index][0], result[index][1] = relocated
        accepted.append(relocated)
    return result, moved_indices


def build():
    field, trees, runway = load_field()
    sky = skyline(trees)
    safety = runway["center_north"]["value"] - runway["width_north_south"]["value"] / 2
    groups = []
    report = []

    def inst(gid, zone, prefabs, rows, kind, source, snap=True):
        if snap:
            rows = [[grid(n), grid(e), round(hd % 360, 1)] for n, e, hd in rows]
        else:
            rows = [[round(n, 2), round(e, 2), round(hd % 360, 1)] for n, e, hd in rows]
        g = {"id": gid, "type": "instances", "zone": zone, "collides": False}
        if len(prefabs) == 1:
            g["prefab"] = prefabs[0]
        else:
            g["prefabs"] = prefabs
        g["placements"] = q(rows, "m, m, deg", kind, source)
        groups.append(g)

    def fence(gid, style, points, source):
        clearance = TREE_CLEARANCE_M + 0.2
        for start, end in zip(points, points[1:]):
            assert clear_of_tree_segment(trees, start, end, clearance), (gid, start, end)
        groups.append({"id": gid, "type": "fence", "zone": "countryside", "style": style, "collides": False,
                       "points": q(points, "m", "estimated", source)})

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
    # Keep the sparse retained plants on their original ground points; three high-poly CommonTree_1
    # row entries move to full-size Maple locations below, away from the runway approach.
    saplings = [(-66.0, -32.0), (-66.0, -22.0), (-66.0, -2.0), (-66.0, 18.0)]
    inst("saplings", "club", ["sapling"], [(n, e, h01(e, n) * 360) for n, e in saplings], "estimated",
         "LU-22 downloaded CommonTree_1/CommonTree_3 saplings behind the club; outside the lake bank and north approach")
    bushes = [(-19.8, -6.4), (-24.5, -6.3), (-19.8, 6.4), (-24.8, 6.3), (-15.5, -20.5), (-15.5, 20.0)]
    inst("bushes", "club", ["bush"], [(n, e, h01(e, n) * 360) for n, e in bushes], "estimated", "Planting around the pavilion")
    clumps = [(-15.4, -5.0 + i * 1.1) for i in range(4)] + [(-15.4, 1.8 + i * 1.1) for i in range(3)]
    inst("flower-border", "club", ["flower_clump"], [(n, e, h01(n * 10, e * 10) * 360) for n, e in clumps], "estimated",
         "Flower border in front of the veranda")
    # people: one other pilot on the line, people in the pits, spectators on benches and by the veranda
    inst("pilots", "pilot_line", ["person_pilot"], [(0.0, -13.0, 5), (-0.5, 16.0, 350)], "estimated", "Other pilots on the flight line")
    inst("pits-people", "pits", ["person_standing"], [(-19.2, 37.5, 200), (-16.8, -33.0, 0)],
         "estimated", "Club members in the pits")
    # SC-HUM-06: members preparing models at the back worktables (top 0.90 m, front edge at north -19.9),
    # facing the table: the west micro-jet bench, the west charger table and the east sport bench.
    inst("pits-workers", "pits", ["person_working"], [(-19.54, -42.6, 180), (-19.54, -38.5, 180), (-19.54, 19.4, 180)],
         "estimated", "Club members preparing models at the pit tables")
    inst("seated", "spectators", ["person_sitting"], [(-16.5, -14.0, 0), (-16.5, 11.5, 0), (-16.5, 14.5, 0)], "estimated", "Spectators on the benches")
    inst("veranda-people", "club", ["person_standing"], [(-17.4, -2.6, 10), (-17.8, 1.4, 350), (-16.4, 4.2, 30)], "estimated", "On the veranda steps")
    # SC-09-R1: service benches and distinct ready bays; the apron stays clear between them.
    # Uniform scales are visual Workshop-style variants, never new flyable configurations.
    fleet_aircraft = catalog_fleet_ids()
    stik, extra, mustang, jet, timber = (fleet_aircraft.index(id) for id in (
        "jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120",
        "sebart-avanti-s-a200-p100rx", "turbo-lumber-evolution"))

    def fleet(gid, rows, purpose, scale=1.0, elevation=0.0, configuration="assembled"):
        groups.append({"id": gid, "type": "fleet", "zone": "pits", "collides": False,
                       "aircraft": fleet_aircraft, "configuration": configuration,
                       "scale": q(scale, "1", "estimated", "Uniform static display scale; " + purpose),
                       "elevation": q(elevation, "m", "derived", "Receiver top: grass 0, slab 0.10, table 0.90, foam 1.12 m"),
                       "placements": q(rows, "m, m, deg, index", "estimated", purpose)})

    fleet("fleet", [(-17.7, -40.3, 352, stik), (-17.6, -24.5, 12, extra),
                    (-17.8, 29.7, 348, mustang), (-17.6, 35.8, 6, jet),
                    (-17.2, 20.6, 355, timber)],
          "Current catalog models in staggered ready bays, between shelter columns and clear of the rear work aisle",
          elevation=0.10)
    fleet("fleet-large-jet", [(-17.5, -48.0, 20, jet)],
          "Large turbine model on the grass at the open west end of the shelter, nose toward the flightline", scale=1.3)
    fleet("fleet-micro-jets", [(-21.4, -48.2, 50, jet), (-17.0, 48.0, 340, jet)],
          "Small sport jets beside the larger ready models with room to carry them to the flightline", scale=0.5)
    fleet("fleet-grass", [(-21.1, 47.9, 15, timber), (-23.8, -29.5, 190, extra)],
          "An electric bush plane and aerobatic model waiting on the mown grass", scale=0.9)
    fleet("fleet-micro-bench", [(-19.9, -42.6, 90, jet)],
          "Micro jet on the empty west end worktable for preflight preparation", scale=0.45, elevation=0.90)
    fleet("fleet-sport-bench", [(-19.9, 19.4, 270, extra)],
          "Small aerobatic model on the empty east end worktable", scale=0.65, elevation=0.90)
    fleet("fleet-service", [(-19.9, -19.6, 90, stik)],
          "Ugly Stik fuselage with its wing removed on the existing paired foam maintenance supports",
          elevation=1.12, configuration="service")
    # Informal gravel parking: a loose, staggered row, an open gap, and canted spaces near the ends.
    # Vehicle positions are estimates; the four existing body styles rotate through the same 11 places.
    cars = [
        (-37.8, -21.0, 181), (-38.5, -17.2, 174), (-37.5, -13.0, 190),
        (-38.2, -8.2, 183), (-37.3, -3.8, 171), (-38.6, 0.5, 192), (-37.6, 4.6, 177),
        (-44.0, -32.4, 96), (-40.6, -25.9, 106), (-44.0, 0.0, 82), (-44.0, 6.5, 101),
    ]
    car_choices = ["car_sedan", "car_hatch", "car_suv", "car_sport"]
    car_rows = [[grid(n), grid(e), round(hd % 360, 1)] for n, e, hd in cars]
    shed_row = next(g for g in groups if g["id"] == "shed")["placements"]["value"][0]
    prefab_text = (ROOT / "app/scenery/prefabs.gd").read_text(encoding="utf-8")
    shed_size = re.search(r'"shed":\s*\{size = Vector3\(([^,]+),\s*([^,]+),\s*([^)]+)\)', prefab_text)
    shed_polygon = car_polygon(*shed_row, (float(shed_size.group(1)), float(shed_size.group(3))))
    check_car_clearance(car_rows, car_choices, catalog_car_sizes(), obstacles=[("shed", shed_polygon)])
    inst("cars", "parking", car_choices, car_rows, "estimated",
         photo + "; informal offset row and canted end spaces (estimated from the reference photo)")
    groups.append({"id": "car-park", "type": "patch", "zone": "parking", "surface": "gravel", "collides": False,
                   "points": q([[-33.5, -24.0], [-33.5, 5.5], [-35.0, 7.0], [-44.5, 7.0], [-45.5, 5.5], [-45.5, -34.5], [-44.0, -36.0], [-35.0, -36.0], [-33.5, -34.0]],
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
    # Quiet pedestrian treads join the existing parking apron, the open central pavilion doorway,
    # and the front bay of the east pits shelter. Both start in the car-park ground batch cell.
    worn_width = q(0.9, "m", "estimated", "Single-person worn-grass connector")
    groups.append({"id": "worn-parking-door", "type": "track", "zone": "countryside", "surface": "worn", "collides": False,
                   "width": worn_width,
                   "points": q([[-33.0, -34.0], [-30.0, -25.0], [-26.0, -16.0], [-23.0, -12.0],
                                [-20.0, -10.0], [-18.0, -12.0], [-13.8, -12.0], [-13.8, -0.25], [-19.0, -0.25]],
                               "m", "estimated", "Worn pedestrian path from the car park to the pavilion's central door")})
    groups.append({"id": "worn-door-pits", "type": "track", "zone": "countryside", "surface": "worn", "collides": False,
                   "width": dict(worn_width),
                   "points": q([[-19.0, -0.25], [-18.5, 3.0], [-17.5, 6.0], [-15.0, 8.0],
                                [-13.8, 9.0], [-13.8, 31.0], [-15.5, 31.0]],
                               "m", "estimated", "Worn pedestrian path around the flower border to the east shelter's open front bay")})
    # --- the countryside, in front ---
    bales, _relocated_bale_indices = relocate_hay_bales()
    inst("hay-bales", "flight_box", ["round_bale"], bales, "estimated",
         "Round bales along mown rows (SC-12); row IDs stay stable while bank-near bales move to 2 m footprint clearance")
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
    # Small southern hamlet facing the countryside rural road; driveways share its layout.
    hamlet = [
        (-650.0, -900.0, 180.0), (-710.0, -835.0, 0.0),
        (-650.0, -770.0, 180.0), (-710.0, -705.0, 0.0),
        (-650.0, -640.0, 180.0), (-710.0, -575.0, 0.0),
        (-650.0, -510.0, 180.0), (-710.0, -455.0, 0.0),
    ]
    inst("countryside-hamlet", "countryside", ["village_house"], hamlet, "estimated",
         "Eight village houses along the rural road south of the club; estimated layout, driveways supplied by the road layout")
    # A second compact yard sits on the eastern rural-road branch; the older NNE farm above stays in place.
    inst("countryside-farm-barn", "countryside", ["barn"], [(780.0, 650.0, 205.0)], "estimated",
         "Secondary small farmyard at the eastern rural-road branch; estimated placement")
    inst("countryside-farmhouse", "countryside", ["farmhouse"], [(750.0, 625.0, 20.0)], "estimated",
         "Farmhouse beside the eastern barn; estimated placement")
    inst("countryside-farm-silo", "countryside", ["silo"], [(795.0, 660.0, 0.0)], "estimated",
         "Silo beside the eastern barn; estimated placement")
    inst("countryside-farm-tractor", "countryside", ["tractor"], [(805.0, 630.0, 250.0)], "estimated",
         "Parked tractor by the eastern farmyard; static scenery placement")
    inst("countryside-farm-bales", "countryside", ["round_bale"],
         [(793.5, 642.0, 0.0), (794.75, 644.25, 0.0), (796.0, 646.5, 0.0)], "estimated",
         "Three small round bales beside the eastern barn")
    # Three-sided farmyard boundaries leave the east-side driveways open; short fence ends mark each gate gap.
    original_fence_source = "Estimated wire fence around the existing farmyard; east-side driveway gate kept open"
    fence("countryside-existing-farm-fence-west-north", "wire",
          [[578.0, 300.0], [625.0, 300.0], [625.0, 374.0]], original_fence_source)
    fence("countryside-existing-farm-fence-south", "wire",
          [[578.0, 300.0], [578.0, 374.0]], original_fence_source)
    fence("countryside-existing-farm-fence-gate-south", "wire",
          [[578.0, 374.0], [603.0, 374.0]], original_fence_source)
    fence("countryside-existing-farm-fence-gate-north", "wire",
          [[616.0, 374.0], [625.0, 374.0]], original_fence_source)
    east_fence_source = "Estimated rail fence around the eastern farmyard; east-side driveway gate kept open"
    fence("countryside-east-farm-fence-west-north", "rail",
          [[732.0, 600.0], [818.0, 600.0], [818.0, 685.0]], east_fence_source)
    fence("countryside-east-farm-fence-south", "rail",
          [[732.0, 600.0], [732.0, 685.0]], east_fence_source)
    fence("countryside-east-farm-fence-gate-north", "rail",
          [[744.0, 685.0], [818.0, 685.0]], east_fence_source)
    # Compact 3 × 4 low berry rows use the existing downloaded shrub, spaced for their crop height.
    orchard = [(n, e, h01(n, e) * 360.0)
               for n in (650.0, 654.0, 658.0) for e in (450.0, 453.0, 456.0, 459.0)]
    for n, e, _heading in orchard:
        assert clear_of_trees(trees, n, e, SAPLING_FOOTPRINT_RADIUS_M + TREE_CLEARANCE_M), (n, e)
    inst("countryside-orchard", "countryside", ["bush"], orchard, "estimated",
         "Twelve existing downloaded forest leafy shrubs arranged in compact low berry rows (~0.7–0.85 m); estimated placement")
    # Four decorative cows occupy a separate 40 × 40 m wire paddock east of the farms.
    cow_paddock = [[850.0, 600.0], [890.0, 600.0], [890.0, 640.0], [850.0, 640.0], [850.0, 600.0]]
    for n, e in ((860.0, 610.0), (860.0, 630.0), (880.0, 610.0), (880.0, 630.0)):
        assert clear_of_trees(trees, n, e, 5.0), (n, e)
    fence("countryside-cows-paddock-fence", "wire", cow_paddock,
          "Estimated wire fence enclosing a small eastern cow paddock")
    inst("countryside-cows", "countryside", ["cow"],
         [(860.0, 610.0, 30.0), (860.0, 630.0, 210.0), (880.0, 610.0, 155.0), (880.0, 630.0, 340.0)],
         "estimated", "Four grazing cows in the small eastern wire paddock")
    # LU-22 downloaded Maples broaden the woodland color beyond the club without adding pines.
    # The stable IDs are chosen against the runtime shade_tree alias so each singleton is a Maple.
    farm_maples = [
        ("maple-farm-south", 555.0, 295.0),
        ("maple-farm-west", 580.0, 280.0),
    ]
    for base, n, e in farm_maples:
        inst(maple_group_id(base), "countryside", ["shade_tree"], [(n, e, h01(n, e) * 360)], "estimated",
             "LU-22 downloaded Maple on the southwest farm edge; irregularly grouped with its neighbor")
    inst(maple_group_id("maple-forest-southwest"), "countryside", ["shade_tree"],
         [(-480.0, -770.0, h01(-480.0, -770.0) * 360)], "estimated",
         "LU-22 downloaded Maple in a southwest forest-edge gap, separated from the farm pair")
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
    # LU-30-R1: closer east line in the low-skyline corridor, beyond the flight box and clear of tree rows.
    pylon_points = [
        (50.0, 650.0), (50.0, 770.0), (50.0, 890.0),
        (50.0, 1010.0), (50.0, 1130.0), (50.0, 1250.0),
        (50.0, 1370.0), (50.0, 1490.0), (50.0, 1610.0),
    ]
    # Local -Z follows the conductors; local X crossarms span the corridor.
    # Endpoint/centered tangents keep neighboring source-mesh sockets aligned.
    pylons = [
        (n, e, math.degrees(math.atan2(
            pylon_points[min(i + 1, len(pylon_points) - 1)][1] - pylon_points[max(0, i - 1)][1],
            pylon_points[min(i + 1, len(pylon_points) - 1)][0] - pylon_points[max(0, i - 1)][0])))
        for i, (n, e) in enumerate(pylon_points)
    ]
    pylon_view = pylon_points[len(pylon_points) // 2]
    p_az = math.degrees(math.atan2(pylon_view[1], pylon_view[0]))
    p_sky = sky_at(sky, p_az)
    p_dist = math.hypot(*pylon_view)
    inst("pylons", "countryside", ["pylon"], pylons, "estimated",
         "Estimated nine-tower east transmission line, clear of the flight box, farm buildings and treelines")
    # LU-23: production meadow and flower instances are downloaded asset batches
    # assembled by botanical_habitats.gd; this source emits no procedural cushions.
    report += [("village/church", v_az, v_sky, 32.0, 2100.0), ("turbines", t_az, t_sky, 121.0, 4000.0),
               ("pylons", p_az, p_sky, 30.0, p_dist), ("farmstead silo", 30.0, sky_at(sky, 30.0), 15.0, 705.0)]
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
            "tree_clearance_m": q(TREE_CLEARANCE_M, "m", "estimated", "Keeps props off the L6b tree cards' trunks"),
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
