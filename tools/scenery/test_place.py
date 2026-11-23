"""Regressions for the generated field layout, planted trees, and lake-bank clearance."""
import json
import math
import unittest

from tools.scenery import place


class SceneryPlaceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data, _, _ = place.build()
        cls.bank = place.lake_bank_polygon()

    def test_generated_default_matches_its_source(self):
        self.assertEqual(place.dumps(self.data), place.OUT.read_text())

    def test_club_driveway_and_property_edges(self):
        groups = {g["id"]: g for g in self.data["groups"]}
        def points(name):
            return groups[name]["points"]["value"]

        hinge, latch = points("club-entrance")
        hedge = points("club-perimeter")
        self.assertEqual((hedge[0], hedge[-1]), (hinge, latch))
        drive = points("access-track")
        self.assertTrue(any(place._segments_intersect(a, b, hinge, latch) for a, b in zip(drive, drive[1:])))
        shoulder = groups["access-track"]["width"]["value"] / 2
        for post in (hinge, latch):
            self.assertGreater(min(place._point_segment_distance(post, a, b) for a, b in zip(drive, drive[1:])),
                               shoulder + 0.5)
        for a, b in zip(hedge, hedge[1:]):
            self.assertTrue(all(not place._segments_intersect(a, b, c, d) for c, d in zip(drive, drive[1:])))
        self.assertGreater(min(hinge[0] - hedge[1][0], latch[0] - hedge[-2][0]), 5.0)
        self.assertGreater(math.dist(hedge[1], hedge[-2]), 2 * math.dist(hinge, latch))
        for name in ("lane-side-pasture", "north-hay-meadow", "east-grazing-lot"):
            corners = points(name)
            self.assertEqual(len(corners), 4)
            self.assertGreaterEqual(sum(c in hedge for c in corners), 2)
            turns = [place._cross(corners[i-2], corners[i-1], corners[i]) for i in range(4)]
            self.assertTrue(all(t > 0 for t in turns) or all(t < 0 for t in turns), name)

    def test_forage_rows_share_the_hedge_and_pasture_wire(self):
        groups = {g["id"]: g for g in self.data["groups"]}
        crop = groups["south-forage-crop"]
        corners = crop["points"]["value"]
        self.assertEqual(crop["surface"], "row_crop")
        self.assertTrue(all(p in groups["club-perimeter"]["points"]["value"] for p in corners[:2]))
        self.assertEqual([corners[0], corners[-1]], groups["lane-side-wire"]["points"]["value"][:2])
        boundary = groups["forage-boundary-wire"]["points"]["value"]
        self.assertEqual(boundary[:2], [corners[3], corners[2]])
        self.assertAlmostEqual(math.dist(boundary[-1], corners[1]), 6.0, places=2)
        _, trees, _ = place.load_field()
        self.assertFalse(any(place._point_in_polygon(tree[:2], corners) for tree in trees))

    def test_stock_trails_and_gates_connect_the_pastures(self):
        groups = {g["id"]: g for g in self.data["groups"]}
        def points(name):
            return groups[name]["points"]["value"]

        for name, gate_name in [("lane-stock-trail", "lane-stock-gate"),
                                ("paddock-stock-trail", "paddock-stock-gate")]:
            hinge, latch = points(gate_name)
            route = points(name)
            midpoint = [(x + y) / 2 for x, y in zip(hinge, latch)]
            self.assertEqual(groups[gate_name]["style"], "stock_gate")
            self.assertAlmostEqual(min(math.dist(p, midpoint) for p in route), 0, places=3)
            for post in (hinge, latch):
                clearance = min(place._point_segment_distance(post, a, b) for a, b in zip(route, route[1:]))
                self.assertGreater(clearance, groups[name]["width"]["value"] / 2 + 0.15)
            for fence in groups.values():
                if fence["type"] not in ("hedge", "fence") or fence["id"] == gate_name:
                    continue
                line = fence["points"]["value"]
                self.assertFalse(any(place._segments_intersect(a, b, c, d)
                                     for a, b in zip(route, route[1:]) for c, d in zip(line, line[1:])),
                                 f"{name} crosses {fence['id']}")
        self.assertTrue(place._point_in_polygon(points("lane-stock-trail")[-1], points("lane-side-pasture")))
        self.assertTrue(place._point_in_polygon(points("paddock-stock-trail")[0], points("east-grazing-lot")))
        for group in ["cows", "sheep"]:
            for n, e, _ in groups[group]["placements"]["value"]:
                self.assertTrue(place._point_in_polygon((n, e), points("home-paddock")))

    def test_bales_keep_group_count_and_source_order(self):
        group = next(item for item in self.data["groups"] if item["id"] == "hay-bales")
        rows = group["placements"]["value"]
        source = place.original_hay_bales()
        self.assertEqual(group["prefab"], "round_bale")
        self.assertEqual(len(rows), 34)
        self.assertEqual([row[2] for row in rows], [row[2] for row in source])

    def test_boundary_trees_keep_the_lane_gate_and_flight_box_clear(self):
        groups = {g["id"]: g for g in self.data["groups"]}
        _, trees, runway = place.load_field()
        safety_n = runway["center_north"]["value"] - runway["width_north_south"]["value"] * 0.5
        flight_box_end = safety_n + self.data["profile"]["flight_box_depth_m"]["value"]
        drive = groups["access-track"]["points"]["value"]
        half_lane = groups["access-track"]["width"]["value"] * 0.5
        hinge, latch = groups["club-entrance"]["points"]["value"]
        catalog = json.loads((place.ROOT / "app/assets/landscape/vegetation/catalog.json").read_text())
        assets = {a["id"]: a for a in catalog["assets"]}
        triangles = 0
        for name, species, boundary in [
            ("gate-maple", "maple_tree", "club-perimeter"),
            ("young-boundary-tree", "landscapelab_pine", "lane-side-wire"),
            ("hay-meadow-shade", "landscapelab_quercus", "hedge-north-w"),
        ]:
            group = groups[name]
            self.assertEqual(len(group["placements"]["value"]), 1)
            n, e, _ = group["placements"]["value"][0]
            prefab = group["prefab"]
            choices = place.vegetation_alias_choices(prefab)
            self.assertEqual(choices[(place.loader_seed(name) & 0x7FFFFFFF) % len(choices)], species)
            triangles += assets[species]["source_triangles"]
            # Conservative loader footprint covers all headings and normal tree-size variation.
            radius = math.hypot(18, 18) / 2 if prefab == "shade_tree" else math.hypot(3, 3.1) / 2
            self.assertGreater(min(place._point_segment_distance((n, e), a, b) for a, b in zip(drive, drive[1:])),
                               half_lane + radius)
            self.assertGreater(place._point_segment_distance((n, e), hinge, latch), radius)
            self.assertTrue(n + radius < safety_n or n - radius > flight_box_end)
            self.assertTrue(place.clear_of_trees(trees, n, e, radius + place.TREE_CLEARANCE_M))
            edge = groups[boundary]["points"]["value"]
            self.assertLess(min(place._point_segment_distance((n, e), a, b) for a, b in zip(edge, edge[1:])), 10)
        self.assertLessEqual(triangles, 17500)  # remaining near-vegetation source allowance

    def test_bales_have_two_metre_footprint_clearance_from_lake_bank(self):
        rows = next(item for item in self.data["groups"] if item["id"] == "hay-bales")["placements"]["value"]
        gaps = [place.bale_bank_clearance(row[0], row[1], self.bank) for row in rows]
        self.assertTrue(all(gap + 1e-9 >= place.BALE_LAKE_CLEARANCE_M for gap in gaps), min(gaps))
        fixed, moved = place.relocate_hay_bales()
        self.assertEqual(fixed, rows)
        self.assertTrue(moved)

    def test_legacy_procedural_flower_cushions_are_not_generated(self):
        self.assertFalse(any(item["id"] == "wildflowers" for item in self.data["groups"]))

    def test_downloaded_saplings_stay_clear_of_the_bank_and_north_approach(self):
        group = next(item for item in self.data["groups"] if item["id"] == "saplings")
        rows = group["placements"]["value"]
        self.assertEqual(group["prefab"], "sapling")
        self.assertEqual(group["zone"], "club")
        self.assertEqual(len(rows), 4)
        self.assertEqual([(row[0], row[1]) for row in rows],
                         [(-66.0, -32.0), (-66.0, -22.0), (-66.0, -2.0), (-66.0, 18.0)])
        self.assertTrue(all(row[0] < 0.0 for row in rows), "saplings should stay behind the club, away from the north approach")
        gaps = [place.bank_footprint_clearance(row[0], row[1], place.SAPLING_FOOTPRINT_RADIUS_M, self.bank)
                for row in rows]
        self.assertTrue(all(gap + 1e-9 >= place.SAPLING_LAKE_CLEARANCE_M for gap in gaps), min(gaps))

    def test_maples_are_distributed_to_farm_edge_and_southwest_forest(self):
        groups = [group for group in self.data["groups"] if group["id"].startswith("maple-")]
        self.assertEqual(len(groups), 3)
        by_position = {}
        shade_choices = place.vegetation_alias_choices("shade_tree")
        for group in groups:
            self.assertEqual(group["prefab"], "shade_tree")
            self.assertEqual(group["zone"], "countryside")
            rows = group["placements"]["value"]
            self.assertEqual(len(rows), 1)
            seed = place.loader_seed(group["id"]) & 0x7FFFFFFF
            self.assertEqual(shade_choices[seed % len(shade_choices)], "maple_tree")
            by_position[(rows[0][0], rows[0][1])] = group

        farm = {(555.0, 295.0), (580.0, 280.0)}
        forest = (-480.0, -770.0)
        self.assertEqual(set(by_position), farm | {forest})
        self.assertGreater(math.dist((555.0, 295.0), (580.0, 280.0)), 25.0)
        self.assertGreater(min(math.dist(forest, point) for point in farm), 800.0)

        _, trees, _runway = place.load_field()
        for north, east in by_position:
            self.assertTrue(place.clear_of_trees(trees, north, east, 15.75),
                            "Maple should clear the existing treeline and its 3 m buffer")

    def test_original_tree_placement_count_and_sapling_mix(self):
        tree_groups = [group for group in self.data["groups"]
                       if group["id"] in ("shade-trees", "saplings") or group["id"].startswith("maple-")]
        tree_count = sum(len(group["placements"]["value"]) for group in tree_groups)
        self.assertEqual(tree_count, 17)

        group = next(item for item in tree_groups if item["id"] == "saplings")
        choices = place.vegetation_alias_choices("sapling")
        seed = place.loader_seed(group["id"]) & 0x7FFFFFFF
        resolved = [choices[((seed + index * 7919) & 0x7FFFFFFF) % len(choices)]
                    for index in range(len(group["placements"]["value"]))]
        self.assertCountEqual(resolved, ["landscapelab_quercus2", "landscapelab_pine"] * 2)


if __name__ == "__main__":
    unittest.main()
