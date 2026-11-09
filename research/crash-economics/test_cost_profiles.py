"""Discriminating authoring checks; mutations are disposable in-memory copies."""
import copy
import json
import unittest
from pathlib import Path
from unittest.mock import patch

import build_profiles
import build_runtime


class CostProfileTests(unittest.TestCase):
    def test_generated_and_registered_modes(self):
        document = build_profiles.build()
        self.assertEqual(build_profiles.render(document), (build_profiles.ROOT / build_profiles.OUTPUT).read_bytes())
        self.assertEqual(11, len(document["aircraft"]))
        for aircraft_id in ("stik-electric-6s", "turbo-lumber-evolution", "moonrunner-x99"):
            self.assertEqual(2, len(document["aircraft"][aircraft_id]["source_hashes"]))

    def mutate_source(self, mutate, message):
        original = build_runtime._read_json

        def read(path):
            value, raw = original(path)
            if path == build_profiles.ROOT / build_profiles.SOURCE:
                value = copy.deepcopy(value)
                mutate(value)
            return value, raw

        with patch.object(build_runtime, "_read_json", read):
            with self.assertRaisesRegex(ValueError, message):
                build_profiles.build()

    def test_duplicate_wing_cannot_be_billed_as_new_child(self):
        def mutate(doc):
            profile = doc["aircraft"]["turbo-lumber-evolution"]
            duplicate = copy.deepcopy(profile["components"][0])
            duplicate["id"] = "second_whole_wing"
            profile["components"].append(duplicate)
        self.mutate_source(mutate, "shared parent")

    def test_arbitrary_offer_not_a_vendor_price(self):
        def mutate(doc):
            doc["aircraft"]["turbo-lumber-evolution"]["components"][0]["offer_id"] = "made-up-offer"
        self.mutate_source(mutate, "offer/price differs")

    def test_omitted_route_refused(self):
        self.mutate_source(lambda doc: doc["aircraft"].pop("gp-extra-300s-60"), "every fixed-wing")

    def test_geometry_change_requires_review_even_if_ids_match(self):
        original = Path.read_bytes
        target = build_profiles.ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"

        def read(path):
            raw = original(path)
            if path == target:
                value = json.loads(raw)
                value["crash_hull"]["value"][0][0] += 0.001
                return (json.dumps(value) + "\n").encode()
            return raw

        with patch.object(Path, "read_bytes", read):
            with self.assertRaisesRegex(ValueError, "installation changed"):
                build_profiles.build()

    def test_pack_change_requires_review(self):
        original = Path.read_bytes
        target = build_profiles.ROOT / "app/data/aircraft/battery/turbo_lumber_evolution_4s_pack.json"

        def read(path):
            raw = original(path)
            return raw + b"\n" if path == target else raw

        with patch.object(Path, "read_bytes", read):
            with self.assertRaisesRegex(ValueError, "installation changed"):
                build_profiles.build()


if __name__ == "__main__":
    unittest.main()
