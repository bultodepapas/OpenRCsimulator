"""Geometric regressions for LU-28: clearance, connected accesses and depth source."""
import hashlib
import json
import math
import unittest

import bake_countryside as bake


def distance(point, path):
    return math.dist(point, bake.nearest_on_path(point, path))


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
