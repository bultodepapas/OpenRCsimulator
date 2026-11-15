"""Behavioral counterexamples for the research contract, not GPU benchmarks."""

from dataclasses import replace
import math
import random
import unittest

from drs_reference import Controller, Ladder, Level, Sample, Tuning, legal_ladder, nominal_extent


# These binary-exact scalars make the hand-calculated extents unambiguous.
SCALES = (0.875, 0.9375, 1.0)
EXPECTED = ((1680, 945), (1800, 1012), (1920, 1080))
LADDER = legal_ladder((1920, 1080), SCALES, (1632, 918), (1920, 1080))
FAST = Tuning(minimum_samples=3, window_ms=40, maximum_samples=8, high_windows=2,
              down_dwell_ms=100, up_dwell_ms=200, recovery_ms=200,
              max_gap_ms=50)


class Feed:
    """A deterministic synthetic completed-frame source; never wall-clock timed."""

    def __init__(self, tuning=FAST, ladder=LADDER):
        self.controller = Controller(ladder, 7, ladder.levels[-1], tuning=tuning)
        self.time = 0.0
        self.sequence = 0

    def sample(self, gpu_ms=20.0, **changes):
        self.time += 20
        self.sequence += 1
        row = Sample(self.sequence, self.controller.generation,
                     self.controller.confirmed.size, self.time, gpu_ms)
        return replace(row, **changes)

    def send(self, gpu_ms=20.0, *, gpu_limited=True, blocked_reason="", **changes):
        row = self.sample(gpu_ms, **changes)
        return self.controller.step(row, self.time, gpu_limited=gpu_limited,
                                    blocked_reason=blocked_reason)

    def block(self, value=20.0, count=3):
        result = None
        for _ in range(count):
            result = self.send(value)
        return result

    def lower(self):
        self.block()
        result = self.block()
        assert result.state == "propose", result
        return result.change

    def accept(self, change):
        return self.controller.acknowledge(change, self.controller.generation + 1,
                                           change.target.size, self.time, accepted=True)


class ExtentContracts(unittest.TestCase):
    def test_hand_calculated_1080p_extents(self):
        self.assertEqual(tuple(level.size for level in LADDER.levels), EXPECTED)
        self.assertEqual(nominal_extent((1920, 1080), 0.85), (1632, 918))
        self.assertEqual(nominal_extent((1920, 1080), 0.5), (960, 540))

    def test_odd_output_does_not_round_a_floor_up(self):
        # ceil(1919*.85), ceil(1079*.85) is (1632,918), not truncation's pair.
        self.assertEqual(nominal_extent((1919, 1079), 0.85), (1631, 917))
        with self.assertRaises(ValueError):
            legal_ladder((1919, 1079), (0.85,), (1632, 918), (1919, 1079))

    def test_independent_axis_rounding_cannot_invent_scalar(self):
        # 86/101..87/101 and 44/51..45/51 have no intersection.
        self.assertGreater(44 / 51, 87 / 101)
        with self.assertRaises(ValueError):
            legal_ladder((101, 51), (0.85, 0.86, 0.865, 0.87), (86, 44), (86, 44))

    def test_duplicate_pixel_sizes_emit_one_level(self):
        result = legal_ladder((100, 100), (0.501, 0.505, 0.509), (50, 50), (100, 100))
        self.assertEqual(len(result.levels), 1)
        self.assertEqual(result.levels[0].size, (50, 50))

    def test_alignment_and_saved_ceiling_are_hard_limits(self):
        result = legal_ladder((1920, 1080), SCALES, (1600, 900), (1800, 1012), (2, 2))
        self.assertEqual(tuple(level.size for level in result.levels), ((1800, 1012),))
        with self.assertRaises(ValueError):
            legal_ladder((1920, 1080), SCALES, (1632, 918), (1280, 720))

    def test_invalid_inputs_and_unbounded_ladders_rejected(self):
        for scale in (True, 0, -1, math.inf, math.nan, 2, 10**1000):
            with self.subTest(scale=str(scale)[:20]), self.assertRaises(ValueError):
                nominal_extent((1920, 1080), scale)
        for size in ((0, 1080), (True, 1080), (1920.0, 1080), (20000, 1080)):
            with self.subTest(size=size), self.assertRaises(ValueError):
                nominal_extent(size, 1.0)
        with self.assertRaises(ValueError):
            legal_ladder((1920, 1080), tuple([1.0] * 33), (1, 1), (1920, 1080))

    def test_forged_ladder_and_unobserved_initial_choice_rejected(self):
        forged = replace(LADDER, levels=(Level(0.5, (1, 1)), Level(0.8, (2, 2))))
        with self.assertRaises(ValueError):
            Controller(forged, 7, Level(0.8, (2, 2)))
        with self.assertRaises(ValueError):
            Controller(LADDER, 7, Level(1.0, (1280, 720)))

    def test_equal_pixel_extents_cannot_hide_exceeding_saved_scalar(self):
        requested = legal_ladder((1920, 1080), (0.85,), (1632, 918), (1632, 918))
        higher = legal_ladder((1920, 1080), (0.8501,), (1632, 918), (1632, 918))
        self.assertEqual(requested.levels[0].size, higher.levels[0].size)
        with self.assertRaises(ValueError):
            Controller(higher, 7, requested.levels[0])
        ceiling = legal_ladder((1920, 1080), (0.85, 0.8501), (1632, 918), (1632, 918))
        self.assertEqual(ceiling.levels[0], higher.levels[0])

    def test_one_legal_level_is_static(self):
        single = legal_ladder((1920, 1080), (0.875,), (1632, 918), (1680, 945))
        feed = Feed(ladder=single)
        result = feed.block(count=30)
        self.assertEqual(result.reason, "one_legal_extent_is_static")
        self.assertFalse(result.restore_fixed)
        self.assertIsNone(feed.controller.pending)


class FeedbackContracts(unittest.TestCase):
    def test_default_policy_has_independent_expected_transition(self):
        # 50 Hz synthetic arrivals: each default 120-sample window spans 2380ms.
        # Window ends 2400,4800,7200; the first two cannot meet the 5000ms dwell.
        feed = Feed(tuning=Tuning())
        changes = []
        for _ in range(360):
            decision = feed.send(20)
            if decision.change:
                changes.append((feed.time, decision.change.target.size))
        self.assertEqual(changes, [(7200.0, (1800, 1012))])
        self.assertEqual(feed.controller.confirmed.size, (1920, 1080))

    def test_one_spike_does_not_trigger_reduction(self):
        feed = Feed(tuning=Tuning())
        for index in range(600):
            result = feed.send(100 if index == 80 else 14)
            self.assertIsNone(result.change)
        self.assertEqual(feed.controller.confirmed.size, (1920, 1080))

    def test_equal_durations_with_distinct_ids_are_distinct_evidence(self):
        feed = Feed()
        change = feed.lower()
        self.assertEqual(change.target.size, (1800, 1012))

    def test_duplicate_polls_do_not_complete_a_window(self):
        feed = Feed()
        sample = feed.sample()
        feed.controller.step(sample, feed.time, gpu_limited=True)
        for now in (21, 22, 30, 40, 60, 100):
            result = feed.controller.step(sample, now, gpu_limited=True)
            self.assertEqual(result.reason, "duplicate_or_out_of_order")
        self.assertEqual(feed.controller.window_count, 1)
        self.assertIsNone(feed.controller.pending)

    def test_duplicate_cannot_refresh_its_timestamp_or_evade_expiry(self):
        feed = Feed()
        sample = feed.sample()
        feed.controller.step(sample, feed.time, gpu_limited=True)
        duplicate = replace(sample, recorded_ms=121)
        result = feed.controller.step(duplicate, 121, gpu_limited=True)
        self.assertEqual(result.reason, "fresh_feedback_expired")
        self.assertTrue(result.restore_fixed)

    def test_out_of_order_sample_cannot_rewrite_evidence(self):
        feed = Feed()
        feed.send()
        feed.send()
        before = (feed.controller.window_count, feed.controller.above_high, feed.controller.below_low)
        old = Sample(1, 7, (1920, 1080), 59, 1)
        result = feed.controller.step(old, 60, gpu_limited=True)
        self.assertEqual(result.reason, "duplicate_or_out_of_order")
        self.assertEqual((feed.controller.window_count, feed.controller.above_high,
                          feed.controller.below_low), before)

    def test_missing_and_invalid_feedback_retires_epoch(self):
        cases = (
            {"completed_id": None}, {"completed_id": True}, {"completed_id": -1},
            {"recorded_ms": None}, {"recorded_ms": math.nan}, {"recorded_ms": math.inf},
            {"recorded_ms": 10**1000}, {"recorded_ms": -1}, {"recorded_ms": 200},
            {"gpu_ms": None}, {"gpu_ms": 0}, {"gpu_ms": -1}, {"gpu_ms": math.inf},
            {"gpu_ms": math.nan}, {"gpu_ms": True}, {"gpu_ms": 10**1000},
            {"generation": 6}, {"generation": True}, {"size": (1280, 720)},
        )
        for fields in cases:
            with self.subTest(fields=str(fields)[:100]):
                feed = Feed()
                result = feed.send(**fields)
                self.assertEqual(result.state, "suspended")
                self.assertTrue(result.restore_fixed)
                self.assertIsNone(feed.block().change)
                self.assertTrue(feed.controller.fault)

    def test_unknown_sample_and_stale_sample_are_not_gpu_headroom(self):
        c = Feed().controller
        self.assertTrue(c.step(None, 20, gpu_limited=True).restore_fixed)
        feed = Feed()
        feed.time = 200
        result = feed.send(recorded_ms=0)
        self.assertEqual(result.reason, "sample_age_invalid")
        self.assertTrue(result.restore_fixed)

    def test_cpu_or_pacing_evidence_cannot_degrade_resolution(self):
        feed = Feed()
        for _ in range(50):
            result = feed.send(40, gpu_limited=False)
            self.assertIsNone(result.change)
            self.assertFalse(result.restore_fixed)
        self.assertEqual(feed.controller.confirmed.size, (1920, 1080))
        self.assertEqual(feed.controller.window_count, 0)

    def test_pause_loading_reset_and_preview_require_fixed_handoff(self):
        for reason in ("paused", "minimized", "loading", "history_pending", "preview", "provider_lost"):
            with self.subTest(reason=reason):
                feed = Feed()
                result = feed.send(blocked_reason=reason)
                self.assertEqual(result.reason, reason)
                self.assertTrue(result.restore_fixed)
                self.assertIsNone(feed.block().change)

    def test_large_recording_gap_resets_high_window_streak(self):
        feed = Feed()
        feed.block()
        self.assertEqual(feed.controller.high_count, 1)
        feed.time += 100
        result = feed.block()
        self.assertEqual(feed.controller.high_count, 1)
        self.assertIsNone(result.change)

    def test_backward_recording_clock_and_process_clock_fail_closed(self):
        feed = Feed()
        feed.send()
        self.assertTrue(feed.send(recorded_ms=20).restore_fixed)
        feed = Feed()
        sample = feed.sample()
        feed.controller.step(sample, 20, gpu_limited=True)
        self.assertTrue(feed.controller.step(sample, 19, gpu_limited=True).restore_fixed)

    def test_threshold_equality_is_deadband(self):
        for value in (12.5, 15.0):  # .75 and .90 of the explicit 60Hz budget.
            with self.subTest(value=value):
                feed = Feed()
                result = feed.block(value, count=60)
                self.assertEqual(result.reason, "deadband")
                self.assertIsNone(feed.controller.pending)

    def test_high_rate_feedback_uses_bounded_counters(self):
        feed = Feed(tuning=Tuning())
        c = feed.controller
        for index in range(1, 20001):
            now = index * 0.25
            result = c.step(Sample(index, 7, (1920, 1080), now, 14), now, gpu_limited=True)
            self.assertLessEqual(c.window_count, c.tuning.maximum_samples)
            self.assertIsNone(result.change)
            self.assertFalse(c.fault)

    def test_periodic_240hz_cost_cannot_alias_away(self):
        # For either phase, full-window p90 is 4ms > .9*(1000/240)=3.75ms.
        # Taking every second frame can miss this; all unique frames must count.
        for phase in (0, 1):
            with self.subTest(phase=phase):
                c = Feed(tuning=Tuning(target_fps=240)).controller
                proposals = []
                for index in range(1, 2001):
                    now = index * (1000 / 240)
                    gpu = 2.0 if (index + phase) % 2 == 0 else 4.0
                    result = c.step(Sample(index, 7, (1920, 1080), now, gpu), now,
                                    gpu_limited=True)
                    if result.change:
                        proposals.append((now, result.change.target.size))
                        break
                self.assertEqual(len(proposals), 1)
                self.assertGreaterEqual(proposals[0][0], 6000)
                self.assertLess(proposals[0][0], 6100)
                self.assertEqual(proposals[0][1], (1800, 1012))

    def test_exact_nearest_rank_threshold_decisions(self):
        # Ten values: one high outlier is rank 10, two include rank 9 (p90).
        tuning = replace(FAST, minimum_samples=10, maximum_samples=20, window_ms=180)
        for highs, expected in ((1, False), (2, True)):
            with self.subTest(highs=highs):
                feed = Feed(tuning=tuning)
                result = None
                for _ in range(2):
                    for index in range(10):
                        result = feed.send(20 if index < highs else 14)
                self.assertEqual(result.change is not None, expected)

    def test_pathological_sample_count_retires_instead_of_growing(self):
        c = Feed(tuning=replace(FAST, maximum_samples=3)).controller
        for index in range(1, 5):
            result = c.step(Sample(index, 7, (1920, 1080), index, 14), index, gpu_limited=True)
        self.assertEqual(result.reason, "window_capacity_contract_failed")
        self.assertTrue(result.restore_fixed)

    def test_noise_within_deadband_does_not_pump_scale(self):
        feed = Feed()
        rng = random.Random(704)
        for _ in range(1000):
            result = feed.send(rng.uniform(12.6, 14.9))
            self.assertIsNone(result.change)
        self.assertEqual(feed.controller.confirmed.size, (1920, 1080))

    def test_target_and_window_parameters_reject_unknown_or_unbounded_values(self):
        for value in (0, -1, math.nan, math.inf, True, 1e-320, 10**1000):
            with self.subTest(value=str(value)[:20]), self.assertRaises(ValueError):
                Tuning(target_fps=value)
        for values in ({"maximum_samples": 1_000_001}, {"minimum_samples": 1}, {"high_windows": 0},
                       {"up_ratio": 0.95}, {"max_age_ms": 0}):
            with self.subTest(values=values), self.assertRaises(ValueError):
                Tuning(**values)


class ApplyContracts(unittest.TestCase):
    def test_proposal_is_not_an_observed_apply(self):
        feed = Feed()
        change = feed.lower()
        self.assertEqual(change.source_generation, 7)
        self.assertEqual(feed.controller.confirmed.size, (1920, 1080))
        self.assertEqual(feed.send().reason, "apply_pending")
        self.assertEqual(feed.controller.confirmed.size, (1920, 1080))
        self.assertEqual(feed.accept(change).state, "accepted")
        self.assertEqual(feed.controller.generation, 8)
        self.assertEqual(feed.controller.confirmed.size, (1800, 1012))

    def test_one_rung_per_change_and_floor_miss_is_visible(self):
        feed = Feed()
        self.assertEqual(feed.accept(feed.lower()).state, "accepted")
        self.assertEqual(feed.controller.confirmed.size, (1800, 1012))
        self.assertEqual(feed.accept(feed.lower()).state, "accepted")
        self.assertEqual(feed.controller.confirmed.size, (1680, 945))
        self.assertEqual(feed.block(count=12).reason, "floor_target_miss")
        self.assertIsNone(feed.controller.pending)

    def test_slow_recovery_respects_ceiling_and_hysteresis(self):
        feed = Feed()
        feed.accept(feed.lower())
        for _ in range(9):
            self.assertIsNone(feed.send(10).change)
        result = feed.block(10)
        self.assertEqual(result.change.target.size, (1920, 1080))
        feed.accept(result.change)
        self.assertEqual(feed.block(10, 30).reason, "at_user_ceiling")

    def test_reduction_dwell_restarts_after_observed_apply(self):
        tuning = replace(FAST, down_dwell_ms=300)
        feed = Feed(tuning=tuning)
        for _ in range(14):
            self.assertIsNone(feed.send().change)
        change = feed.send().change
        self.assertIsNotNone(change)
        feed.accept(change)
        for _ in range(14):
            self.assertIsNone(feed.send().change)
        self.assertIsNotNone(feed.send().change)

    def test_foreign_and_copied_tokens_do_not_acknowledge_current_apply(self):
        first, second = Feed(), Feed()
        old, current = first.lower(), second.lower()
        self.assertEqual(old.request_id, current.request_id)
        for invalid in (old, replace(current)):
            result = second.controller.acknowledge(invalid, 8, (1800, 1012), 120, accepted=True)
            self.assertEqual(result.state, "ignored")
            self.assertFalse(result.restore_fixed)
        self.assertEqual(second.accept(current).state, "accepted")

    def test_failed_or_unverified_apply_requests_immediate_fixed_restore(self):
        for values in ({"accepted": False}, {"generation": 7}, {"generation": True},
                       {"observed": (1280, 720)}):
            with self.subTest(values=values):
                feed = Feed()
                change = feed.lower()
                args = dict(generation=8, observed=(1800, 1012), now_ms=120, accepted=True)
                args.update(values)
                result = feed.controller.acknowledge(change, **args)
                self.assertTrue(result.restore_fixed)
                self.assertEqual(feed.controller.confirmed.size, (1920, 1080))
                self.assertIsNone(feed.block().change)

    def test_timeout_requires_no_future_sample_to_request_restore(self):
        feed = Feed()
        change = feed.lower()
        result = feed.controller.acknowledge(change, 8, (1800, 1012), 1120, accepted=True)
        self.assertEqual(result.reason, "apply_timeout")
        self.assertTrue(result.restore_fixed)

    def test_timeout_is_also_detected_while_polling(self):
        feed = Feed()
        feed.lower()
        result = feed.controller.step(None, 1120, gpu_limited=True)
        self.assertEqual(result.reason, "apply_timeout")
        self.assertTrue(result.restore_fixed)

    def test_pending_change_cannot_survive_pause_or_settings_revert(self):
        feed = Feed()
        change = feed.lower()
        result = feed.send(blocked_reason="settings_revert")
        self.assertTrue(result.restore_fixed)
        self.assertTrue(feed.accept(change).restore_fixed)
        self.assertEqual(feed.controller.confirmed.size, (1920, 1080))

    def test_reduced_stale_epoch_cannot_revive_after_fixed_restore(self):
        feed = Feed()
        change = feed.lower()
        feed.accept(change)
        result = feed.send(completed_id=None)
        self.assertTrue(result.restore_fixed)
        self.assertIsNone(feed.block().change)
        self.assertTrue(feed.controller.acknowledge(change, 9, (1920, 1080), feed.time,
                                                  accepted=True).restore_fixed)
        # A separate owner confirms fixed restoration and creates a fresh epoch.
        fresh = Controller(LADDER, 9, Level(1.0, (1920, 1080)), started_ms=feed.time, tuning=FAST)
        row = Sample(1000, 9, (1920, 1080), feed.time + 20, 20)
        self.assertEqual(fresh.step(row, feed.time + 20, gpu_limited=True).state, "warming")


if __name__ == "__main__":
    unittest.main()
