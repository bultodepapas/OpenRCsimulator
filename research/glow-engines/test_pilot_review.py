"""Focused tests for the NITRO-03 pilot protocol generator."""

import copy
import json
import tempfile
import unittest
from collections import defaultdict
from pathlib import Path

import pilot_review


class PilotReviewTests(unittest.TestCase):
    def test_seeded_schedule_is_stable_and_different_seeds_change_order(self):
        first = pilot_review.build_protocol(741)
        second = pilot_review.build_protocol(741)
        other = pilot_review.build_protocol(742)
        self.assertEqual(first, second)
        self.assertNotEqual(
            [
                (trial["operator_only"]["family"], trial["maneuver_id"], trial["repetition"],
                 trial["operator_only"]["audio_condition"])
                for trial in first["operator_schedule"]
            ],
            [
                (trial["operator_only"]["family"], trial["maneuver_id"], trial["repetition"],
                 trial["operator_only"]["audio_condition"])
                for trial in other["operator_schedule"]
            ],
        )
        self.assertEqual(first["randomization"]["algorithm"],
                         "SplitMix64, unsigned 64-bit arithmetic, Fisher-Yates shuffle")

    def test_schedule_has_exact_family_maneuver_condition_and_repeat_coverage(self):
        review = pilot_review.build_protocol(9)
        trials = review["operator_schedule"]
        self.assertEqual(len(trials), 48)
        pairs = defaultdict(list)
        counts = defaultdict(int)
        for trial in trials:
            operator = trial["operator_only"]
            pairs[operator["pair_id"]].append(operator["audio_condition"])
            counts[(operator["family"], trial["maneuver_id"], trial["repetition"],
                    operator["audio_condition"])] += 1
        self.assertEqual(len(pairs), 24)
        self.assertTrue(all(sorted(conditions) == ["audio_on", "muted"]
                            for conditions in pairs.values()))
        self.assertEqual(set(family for family, _, _, _ in counts), {"glow_2t", "glow_4t"})
        for family in ("glow_2t", "glow_4t"):
            for maneuver in (item["id"] for item in pilot_review.MANEUVERS):
                for repetition in (1, 2):
                    for condition in ("audio_on", "muted"):
                        self.assertEqual(counts[(family, maneuver, repetition, condition)], 1)

    def test_condition_order_is_counterbalanced_inside_each_family(self):
        review = pilot_review.build_protocol(20261013)
        first_conditions = defaultdict(list)
        for trial in review["operator_schedule"]:
            operator = trial["operator_only"]
            if operator["condition_order_within_pair"] == 1:
                first_conditions[operator["family"]].append(operator["audio_condition"])
        self.assertEqual(len(first_conditions["glow_2t"]), 12)
        self.assertEqual(len(first_conditions["glow_4t"]), 12)
        for family, conditions in first_conditions.items():
            self.assertEqual(conditions.count("audio_on"), 6, family)
            self.assertEqual(conditions.count("muted"), 6, family)

    def test_exact_profiles_props_and_source_hashes_are_recorded(self):
        review = pilot_review.build_protocol(17)
        two = review["families"]["glow_2t"]
        four = review["families"]["glow_4t"]
        self.assertEqual(two["profile"]["id"], "os_max_55ax_candidate")
        self.assertEqual(two["propeller"]["build_id"], "max55ax_apc_sport_12x7")
        self.assertEqual(four["profile"]["id"], "os_fs_64v_candidate")
        self.assertEqual(four["propeller"]["build_id"], "fs64v_master_airscrew_k_14x6")
        for config in (two, four):
            for artifact in ("profile", "installation", "aircraft_data"):
                self.assertRegex(config[artifact]["sha256"], r"^[0-9a-f]{64}$")
            self.assertEqual(config["fuel"]["candidate_profile_blend_volume_fraction"], {
                "methanol": 0.72,
                "nitromethane": 0.1,
                "castor_oil": 0.18,
            })

    def test_pilot_cards_do_not_leak_profile_or_audio_condition(self):
        review = pilot_review.build_protocol(18)
        self.assertEqual(len(review["pilot_cards"]), len(review["operator_schedule"]))
        forbidden = {"family", "catalog_id", "profile_id", "propeller_build_id", "audio_condition"}
        for card in review["pilot_cards"]:
            self.assertFalse(forbidden.intersection(card))
        self.assertEqual(review["blinding"]["audio_condition"].split()[0], "Audio-on")

    def test_template_is_not_performed_and_validator_rejects_false_completion(self):
        review = pilot_review.build_protocol(20)
        self.assertEqual(review["status"], "not_performed")
        self.assertTrue(all(trial["operator_result"]["run_status"] == "not_run"
                            for trial in review["operator_schedule"]))
        self.assertEqual(pilot_review.validate_review(review), [])
        claimed = copy.deepcopy(review)
        claimed["status"] = "complete"
        errors = pilot_review.validate_review(claimed)
        self.assertTrue(any("incomplete trial" in error for error in errors))
        self.assertTrue(any("trace provenance" in error for error in errors))
        self.assertTrue(any("experienced pilot" in error for error in errors))

    def test_not_performed_template_cannot_contain_fabricated_ratings(self):
        review = pilot_review.build_protocol(21)
        review["operator_schedule"][0]["pilot_response"]["confidence_1_to_7"] = 7
        errors = pilot_review.validate_review(review)
        self.assertTrue(any("contains pilot responses" in error for error in errors))

    def test_seed_range_is_checked(self):
        with self.assertRaises(ValueError):
            pilot_review.build_protocol(-1)
        with self.assertRaises(ValueError):
            pilot_review.build_protocol(1 << 64)

    def test_cli_generates_operator_record_and_separate_masked_cards(self):
        with tempfile.TemporaryDirectory() as directory:
            operator_path = Path(directory) / "operator.json"
            cards_path = Path(directory) / "pilot-cards.json"
            result = pilot_review.main([
                "--seed", "81", "--out", str(operator_path),
                "--pilot-cards-out", str(cards_path),
            ])
            self.assertEqual(result, 0)
            operator = json.loads(operator_path.read_text(encoding="utf-8"))
            cards = json.loads(cards_path.read_text(encoding="utf-8"))
            self.assertEqual(operator["status"], "not_performed")
            self.assertEqual(len(cards["cards"]), 48)
            self.assertEqual(len(pilot_review.validate_review(operator)), 0)
            forbidden = {"family", "catalog_id", "profile_id", "propeller_build_id", "audio_condition"}
            for card in cards["cards"]:
                self.assertFalse(forbidden.intersection(card))


if __name__ == "__main__":
    unittest.main(verbosity=2)
