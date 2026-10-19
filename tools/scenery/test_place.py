"""Regressions for the generated field layout, planted trees, and lake-bank clearance."""
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

    def test_bales_keep_group_count_and_source_order(self):
        group = next(item for item in self.data["groups"] if item["id"] == "hay-bales")
        rows = group["placements"]["value"]
        source = place.original_hay_bales()
        self.assertEqual(group["prefab"], "round_bale")
        self.assertEqual(len(rows), 34)
        self.assertEqual([row[2] for row in rows], [row[2] for row in source])

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

    def test_tree_placement_count_stays_flat_and_sapling_mix_keeps_one_common_tree_1(self):
        tree_groups = [group for group in self.data["groups"] if group.get("prefab") in ("shade_tree", "sapling")]
        tree_count = sum(len(group["placements"]["value"]) for group in tree_groups)
        self.assertEqual(tree_count, 17)

        group = next(item for item in tree_groups if item["id"] == "saplings")
        choices = place.vegetation_alias_choices("sapling")
        seed = place.loader_seed(group["id"]) & 0x7FFFFFFF
        resolved = [choices[((seed + index * 7919) & 0x7FFFFFFF) % len(choices)]
                    for index in range(len(group["placements"]["value"]))]
        self.assertEqual(resolved.count("common_tree_1"), 1)


if __name__ == "__main__":
    unittest.main()
