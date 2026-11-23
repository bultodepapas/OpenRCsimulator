"""Geometric regressions for LU-28: clearance, connected accesses and depth source."""
import hashlib
import json
import math
import unittest

import bake_countryside as bake


def distance(point, path):
    return math.dist(point, bake.nearest_on_path(point, path))


def segment_distance(a, b, c, d):
    def cross(u, v):
        return u[0] * v[1] - u[1] * v[0]
    ab = (b[0] - a[0], b[1] - a[1])
    cd = (d[0] - c[0], d[1] - c[1])
    ac = (c[0] - a[0], c[1] - a[1])
    denominator = cross(ab, cd)
    if abs(denominator) > 1e-12:
        t, u = cross(ac, cd) / denominator, cross(ac, ab) / denominator
        if 0 <= t <= 1 and 0 <= u <= 1:
            return 0.0
    return min(distance(a, [c, d]), distance(b, [c, d]),
               distance(c, [a, b]), distance(d, [a, b]))


def triangles_touch(a, b):
    def contains(triangle, p):
        signs = [(q[0] - r[0]) * (p[1] - r[1]) - (q[1] - r[1]) * (p[0] - r[0])
                 for q, r in zip(triangle, triangle[1:] + triangle[:1])]
        return min(signs) >= -1e-6 or max(signs) <= 1e-6
    return (any(contains(a, p) for p in b) or any(contains(b, p) for p in a)
            or any(segment_distance(p, q, r, s) < 1e-6
                   for p, q in zip(a, a[1:] + a[:1]) for r, s in zip(b, b[1:] + b[:1])))


class CountrysideTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(bake.OUTPUT.read_bytes())
        cls.roads = {r["id"]: r for r in cls.data["roads"]}
        field = json.loads(bake.FIELD.read_text())
        cls.trees = [p[:2] for obj in field["objects"] if obj["type"] == "treeline"
                     for p in obj["positions"]["value"]]

    def test_retained_sources_and_reproducible_bake(self):
        self.assertEqual(bake.generate(), bake.OUTPUT.read_bytes())
        for path, expected in self.data["source_sha256"].items():
            self.assertEqual(hashlib.sha256((bake.ROOT / path).read_bytes()).hexdigest(), expected)

    def test_roads_clear_existing_trunks(self):
        for road in self.roads.values():
            clearance = min(distance(tree, road["centerline_ne_m"]) for tree in self.trees)
            self.assertGreater(clearance - road["width_m"] / 2, 3, road["id"])

    def test_all_accesses_join_a_road(self):
        joins = [("village-road", "divided-highway"), ("club-link", "village-road"),
                 ("old-farm-link", "divided-highway"), ("east-farm-link", "old-farm-link")]
        for child, parent in joins:
            self.assertLess(distance(self.roads[child]["centerline_ne_m"][-1],
                                     self.roads[parent]["centerline_ne_m"]),
                            self.roads[parent]["width_m"] / 2, child)
        for road in self.roads.values():
            if road["id"].startswith("house-drive-"):
                self.assertLess(distance(road["centerline_ne_m"][0],
                                         self.roads["village-road"]["centerline_ne_m"]), .001)
        self.assertEqual(self.roads["west-village-road"]["centerline_ne_m"][0],
                         self.roads["village-road"]["centerline_ne_m"][0])

    def road_triangles(self, road):
        result = []
        for key, (start, end) in road["mesh_ranges"].items():
            cell = self.data["cells"][key]
            for i in range(start, end, 3):
                verts = [cell["vertices"][j] for j in cell["indices"][i:i + 3]]
                result.append((sum(v[3] for v in verts) / 3, [(-v[2], v[0]) for v in verts]))
        return result

    def test_actual_rut_ribbons_connect_at_access_mouths(self):
        joins = [("club-link", "village-road"), ("old-farm-link", "divided-highway"),
                 ("east-farm-link", "old-farm-link"), ("wheat-field-entry", "old-farm-link"),
                 ("maize-field-entry", "old-farm-link")]
        joins += [(r, "village-road") for r in self.roads if r.startswith("house-drive-")]
        for child, parent in joins:
            parent_triangles = [t for _, t in self.road_triangles(self.roads[parent])]
            child_triangles = self.road_triangles(self.roads[child])
            for sign in (-1, 1):
                self.assertTrue(any(triangles_touch(t, p) for cross, t in child_triangles if cross * sign > 0
                                    for p in parent_triangles), (child, parent, sign))

    def test_farm_accesses_fit_open_gates(self):
        # First outward crossing must fit the gate including the road shoulder.
        for name, e, low, high in [("old-farm-link", 374, 603, 616),
                                   ("east-farm-link", 685, 732, 744)]:
            road = self.roads[name]
            crossings = [a[0] + (b[0] - a[0]) * (e - a[1]) / (b[1] - a[1])
                         for a, b in zip(road["centerline_ne_m"], road["centerline_ne_m"][1:])
                         if a[1] <= e < b[1]]
            self.assertTrue(crossings)
            self.assertGreater(crossings[0] - road["width_m"] / 2, low)
            self.assertLess(crossings[0] + road["width_m"] / 2, high)

    def test_field_entries_join_road_and_stop_in_clear_headlands(self):
        scenery = json.loads(bake.SCENERY.read_text())
        fences = [g["points"]["value"] for g in scenery["groups"] if g["type"] == "fence"]
        entries = [r for r in self.roads.values() if "parcel_index" in r]
        self.assertEqual({r["id"] for r in entries}, {"wheat-field-entry", "maize-field-entry"})
        for road in entries:
            path = road["centerline_ne_m"]
            self.assertLess(distance(path[0], self.roads[road["parent_road"]]["centerline_ne_m"]), .001)
            parcel = self.data["parcels"][road["parcel_index"]]
            n0, e0, n1, e1 = parcel["bounds_ne_m"]
            north, east = path[-1]
            radius = road["width_m"] / 2
            # The complete width fits the named field and remains in its headland.
            self.assertTrue(n0 + radius <= north <= n1 - radius)
            self.assertTrue(e0 + radius <= east <= e1 - radius)
            self.assertLessEqual(min(north - n0, n1 - north) + radius, parcel["headland_m"])
            for a, b in zip(path, path[1:]):
                for fence in fences:
                    for c, d in zip(fence, fence[1:]):
                        self.assertGreater(segment_distance(a, b, c[:2], d[:2]), radius + .5, road["id"])

    def test_field_uvs_keep_parent_row_length_across_cells_and_orientations(self):
        self.assertEqual({p["row_axis"] for p in self.data["parcels"]}, {0, 1})
        self.assertTrue({"wheat", "maize", "pasture", "stubble", "soil", "wheat_harvest"}
                        <= {p["cover"] for p in self.data["parcels"]})
        for parcel in self.data["parcels"]:
            n0, e0, n1, e1 = parcel["bounds_ne_m"]
            rotated = parcel["row_axis"] == 0
            row_length = e1 - e0 if rotated else n1 - n0
            matched = 0
            along = []
            for cell in self.data["cells"].values():
                for i in range(0, len(cell["vertices"]), 4):
                    quad = cell["vertices"][i:i + 4]
                    north = -sum(v[2] for v in quad) / 4
                    east = sum(v[0] for v in quad) / 4 - (north - (n0 + n1) / 2) * parcel["shear"]
                    if quad[0][5] != parcel["kind"] or not (n0 < north < n1 and e0 < east < e1):
                        continue
                    for v in quad:
                        n = -v[2]
                        e = v[0] - (n - (n0 + n1) / 2) * parcel["shear"]
                        self.assertAlmostEqual(v[3], n - n0 if rotated else e - e0, delta=.001)
                        self.assertAlmostEqual(v[4], e - e0 if rotated else n - n0, delta=.001)
                        self.assertAlmostEqual(v[6], row_length, delta=.001)
                        along.append(v[4])
                    matched += 1
            self.assertGreater(matched, 0, parcel)
            # Both true field ends are present; cell boundaries never reset their UV.
            self.assertAlmostEqual(min(along), 0, delta=.001)
            self.assertAlmostEqual(max(along), row_length, delta=.001)
        harvested = [p for p in self.data["parcels"] if p["cover"] == "wheat_harvest"]
        self.assertEqual(len(harvested), 1)
        self.assertLess(harvested[0]["headland_m"], harvested[0]["harvested_length_m"])
        n0, e0, n1, e1 = harvested[0]["bounds_ne_m"]
        row_length = e1 - e0 if harvested[0]["row_axis"] == 0 else n1 - n0
        self.assertLess(harvested[0]["harvested_length_m"], row_length - harvested[0]["headland_m"])
        for parcel in self.data["parcels"]:
            n0, e0, n1, e1 = parcel["bounds_ne_m"]
            length = e1 - e0 if parcel["row_axis"] == 0 else n1 - n0
            style = self.data["surface_style"]
            expected = 0 if parcel["cover"] == "pasture" else min(style["headland_m"], length * style["headland_fraction"])
            self.assertEqual(parcel["headland_m"], expected)
            if parcel["cover"] == "wheat_harvest":
                self.assertEqual(parcel["harvested_length_m"], style["harvested_length_m"])

    def test_geometry_budget_winding_and_flight_area(self):
        self.assertLessEqual(len(self.data["cells"]), 40)
        count = 0
        for cell in self.data["cells"].values():
            verts, indices = cell["vertices"], cell["indices"]
            for v in verts:
                self.assertTrue(all(math.isfinite(x) for x in v))
                self.assertGreater(math.hypot(v[0], v[2]), 400, "Protected club/flight area")
            for i in range(0, len(indices), 3):
                a, b, c = [verts[j] for j in indices[i:i + 3]]
                cross = (b[2]-a[2])*(c[0]-a[0])-(b[0]-a[0])*(c[2]-a[2])
                self.assertLess(cross, -1e-7, "Upward clockwise non-degenerate triangles")
                count += 1
        self.assertEqual(count, self.data["triangles"])
        self.assertLessEqual(count, 14000)

    def test_vertices_follow_retained_visual_horizon(self):
        sample = bake.horizon_sampler()
        for cell in self.data["cells"].values():
            for v in cell["vertices"]:
                offset = v[1] - sample(-v[2], v[0])
                self.assertGreater(offset, .04)
                self.assertLess(offset, .10)
        self.assertIs(self.data["physical_terrain"], False)

    def test_crop_rows_clear_trunks_after_shear(self):
        for parcel in self.data["parcels"]:
            n0, e0, n1, e1 = parcel["bounds_ne_m"]
            for n, e in self.trees:
                unsheared_e = e - (n - (n0+n1)/2) * parcel["shear"]
                self.assertFalse(n0 - 3 < n < n1 + 3 and e0 - 3 < unsheared_e < e1 + 3,
                                 "Crop rows overlap an existing trunk")


if __name__ == "__main__":
    unittest.main()
