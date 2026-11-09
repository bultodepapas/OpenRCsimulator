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

    def test_missing_common_prop_followup_is_not_silent_pending(self):
        self.mutate_source(lambda doc: doc["aircraft"]["jensen-das-ugly-stik-60"]["propeller_followups"].pop(), "follow-up coverage")

    def test_legacy_multi_target_requires_independent_rules(self):
        def mutate(doc):
            profile = doc["aircraft"]["sebart-avanti-s-a200-p100rx"]
            zone = next(z for z in profile["zones"] if z["probe_id"] == "probe_belly_station_plus_six")
            zone["component_responses"].pop("engine_main")
        self.mutate_source(mutate, "per-component responses")

    def test_local_service_cannot_fall_back_to_free(self):
        def mutate(doc):
            profile = doc["aircraft"]["jensen-das-ugly-stik-60"]
            profile["zones"][0]["response"]["service_minor_by_component"] = {}
        self.mutate_source(mutate, "service allowance")

    def test_purchase_quantities_are_strict_integers(self):
        def mutate(doc):
            package = doc["aircraft"]["jensen-das-ugly-stik-60"]["packages"][0]
            package["component_quantities"]["airframe_wing"] = True
        self.mutate_source(mutate, "expected an integer")

    def test_labor_scope_is_explicit_for_every_part(self):
        self.mutate_source(lambda doc: doc["aircraft"]["jensen-das-ugly-stik-60"]["labor_policy"]["minutes_by_component"].pop("propeller"), "every financial component")

    def test_avanti_power_prices_have_disjoint_declared_coverage(self):
        profile = build_profiles.build()["aircraft"]["sebart-avanti-s-a200-p100rx"]
        rows = {c["id"]: c for c in profile["components"]}
        self.assertEqual(278000, rows["engine_main"]["unit_minor"])
        self.assertEqual(40000, rows["turbine_accessories"]["unit_minor"])
        self.assertEqual("price_proxy", rows["engine_main"]["price_basis"])
        self.assertIn("Excludes the standard turbine control", rows["turbine_accessories"]["notes"])
        self.assertEqual(["engine_main", "turbine_accessories"], profile["shared_parent_children"]["turbine_accessories"])

    def test_severe_grouped_followups_do_not_use_unreachable_thresholds(self):
        document = build_profiles.build()
        for aircraft, component in (("p51d-mustang-120", "muffler_pair"), ("f4u-corsair-250", "throttle_choke_servos")):
            follow = next(r for r in document["aircraft"][aircraft]["propeller_followups"] if r["component_id"] == component)
            self.assertEqual(45.0, follow["replace_speed_mps"])
            self.assertEqual(20000.0, follow["replace_rpm"])

    def test_moonrunner_adapter_and_mount_have_disjoint_declared_coverage(self):
        profile = build_profiles.build()["aircraft"]["moonrunner-x99"]
        rows = {c["id"]: c for c in profile["components"]}
        self.assertEqual(["motor_main", "propeller_main"], profile["shared_parent_children"]["propeller_main"])
        self.assertIn("propeller_main", rows["motor_main"]["physical_inventory_ids"])
        self.assertIn("blade only", rows["propeller_main"]["notes"])
        self.assertIn("excludes the metal X mount", rows["motor_mount"]["notes"])

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
