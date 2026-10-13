"""Regressions for stable generated hay-bale IDs and lake-bank clearance."""
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
        self.assertEqual(len(rows), 7)
        self.assertTrue(all(row[0] < 0.0 for row in rows), "saplings should stay behind the club, away from the north approach")
        gaps = [place.bank_footprint_clearance(row[0], row[1], place.SAPLING_FOOTPRINT_RADIUS_M, self.bank)
                for row in rows]
        self.assertTrue(all(gap + 1e-9 >= place.SAPLING_LAKE_CLEARANCE_M for gap in gaps), min(gaps))


if __name__ == "__main__":
    unittest.main()
