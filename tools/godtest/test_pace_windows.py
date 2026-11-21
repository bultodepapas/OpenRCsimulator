from __future__ import annotations

import json
import math
import unittest

from pace_windows import PaceWindowAccumulator


def rows(ticks, *, phase=0, step_usec=100_000, start_usec=1_000_000,
         paused=None, crashed=None):
    """Create real stream-shaped callback samples with a 240 Hz sim clock."""
    for index, tick in enumerate(ticks):
        yield (phase, step_usec, start_usec + index * step_usec, tick,
               tick / 240 if tick >= 0 else 0, (paused or {}).get(index, 0),
               (crashed or {}).get(index, 0))


def reduce_rows(samples, chunk_size=512):
    accumulator = PaceWindowAccumulator()
    for start in range(0, len(samples), chunk_size):
        for sample in samples[start:start + chunk_size]:
            accumulator.add(*sample)
    return accumulator.finish()


class PaceWindowTests(unittest.TestCase):
    def test_steady_and_observed_zero_are_distinct_from_missing(self):
        steady = reduce_rows(list(rows([24 * n for n in range(101)])))["0"]
        self.assertEqual(steady["status"], "available")
        self.assertEqual(steady["full_windows"], 10)
        self.assertEqual(steady["supported_windows"], 10)
        self.assertEqual(steady["partial_windows"], 0)
        self.assertAlmostEqual(steady["worst_window"]["simulation_wall_ratio"], 1)
        self.assertAlmostEqual(steady["fastest_window"]["simulation_wall_ratio"], 1)
        self.assertAlmostEqual(steady["maximum_lag_seconds"], 0)
        self.assertEqual(steady["supported_window_fraction_of_active_wall"], 1)
        self.assertEqual(steady["phase_boundary_or_first_interval_excluded_wall_seconds"], .1)
        stalled = reduce_rows(list(rows([0] * 11)))["0"]
        self.assertEqual(stalled["status"], "available")
        self.assertEqual(stalled["worst_window"]["simulation_wall_ratio"], 0)
        self.assertEqual(stalled["maximum_lag_seconds"], 1)
        self.assertEqual(stalled["maximum_lag_at_usec"], 2_000_000)

    def test_slow_then_catchup_equal_total_exposes_worst_and_peak(self):
        ticks = [12 * n if n <= 50 else 600 + 36 * (n - 50) for n in range(101)]
        value = reduce_rows(list(rows(ticks)))["0"]
        self.assertEqual(value["status"], "available")
        self.assertAlmostEqual(value["active_sim_seconds"] / value["active_wall_seconds"], 1)
        self.assertAlmostEqual(value["worst_window"]["simulation_wall_ratio"], .5)
        self.assertAlmostEqual(value["fastest_window"]["simulation_wall_ratio"], 1.5)
        self.assertAlmostEqual(value["maximum_lag_seconds"], 2.5)
        self.assertEqual(value["maximum_lag_at_usec"], 6_000_000)
        self.assertEqual(value["worst_window"]["window_start_usec"], 1_000_000)
        self.assertEqual(value["worst_window"]["window_end_usec"], 2_000_000)

    def test_large_epoch_cannot_forge_healthy_sim_time_over_stalled_ticks(self):
        # Only ten ticks pass over one second, but the supplied time claims 1 s.
        # A relative tolerance used to grow large enough to accept this as 1x.
        for base, issue in ((10**12, "simulation_clock_inconsistent"),
                            (10**15, "simulation_clock_insufficient_precision")):
            with self.subTest(base=base):
                accumulator = PaceWindowAccumulator()
                for n in range(11):
                    accumulator.add(0, 100_000, 1_000_000 + n * 100_000,
                                    base + n, base / 240.0 + n / 10, 0, 0)
                value = accumulator.finish()["0"]
                self.assertEqual(value["status"], "unavailable_simulation_clock_discontinuity")
                self.assertIn(issue, value["issues"])
                self.assertIsNone(value["worst_window"])

    def test_real_producer_clock_is_validated_and_pace_uses_tick_deltas(self):
        for base in (0, 160_000, 10**12):
            with self.subTest(base=base):
                accumulator = PaceWindowAccumulator()
                for n in range(11):
                    tick = base + n * 24
                    # Match Simulation.time(): integer tick times float dt.
                    sim_s = tick * (1.0 / 240.0)
                    accumulator.add(0, 100_000, 1_000_000 + n * 100_000, tick, sim_s, 0, 0)
                value = accumulator.finish()["0"]
                self.assertEqual(value["status"], "available", value)
                self.assertEqual(value["active_sim_seconds"], 1)
                self.assertEqual(value["worst_window"]["simulation_wall_ratio"], 1)
                self.assertEqual(value["maximum_lag_seconds"], 0)

    def test_truthful_but_insufficiently_precise_simulation_clock_is_unavailable(self):
        accumulator = PaceWindowAccumulator()
        for n in range(11):
            tick = 10**15 + n * 24
            accumulator.add(0, 100_000, 1_000_000 + n * 100_000,
                            tick, tick * (1.0 / 240.0), 0, 0)
        value = accumulator.finish()["0"]
        self.assertEqual(value["status"], "unavailable_simulation_clock_discontinuity")
        self.assertIn("simulation_clock_insufficient_precision", value["issues"])
        self.assertIsNone(value["worst_window"])

    def test_pause_and_crash_bracket_intervals_and_restart_lag(self):
        ticks = [24 * n if n <= 10 else 240 if n <= 18 else 240 + 24 * (n - 18)
                 for n in range(29)]
        for channel in ("paused", "crashed"):
            with self.subTest(channel=channel):
                holds = {n: 1 for n in range(11, 18)}
                options = {channel: holds}
                value = reduce_rows(list(rows(ticks, **options)))["0"]
                self.assertEqual(value["status"], "unavailable_hold_observed")
                self.assertEqual(value["observed_hold_samples"], 7)
                self.assertEqual(value["hold_excluded_intervals"], 8)
                self.assertAlmostEqual(value["hold_excluded_wall_seconds"], .8)
                self.assertEqual(value["active_segments"], 2)
                self.assertEqual(value["supported_windows"], 2)
                self.assertAlmostEqual(value["maximum_lag_seconds"], 0)

    def test_window_crossing_is_not_split_but_endpoint_lag_is_observed(self):
        accumulator = PaceWindowAccumulator()
        samples = [(0, 100_000, 1_000_000, 0, 0, 0, 0),
                   (0, 400_000, 1_400_000, 96, .4, 0, 0),
                   (0, 400_000, 1_800_000, 192, .8, 0, 0),
                   # 0.4 seconds crosses the 1-second cell boundary. No sim progress.
                   (0, 400_000, 2_200_000, 192, .8, 0, 0),
                   (0, 400_000, 2_600_000, 288, 1.2, 0, 0),
                   (0, 400_000, 3_000_000, 384, 1.6, 0, 0)]
        for sample in samples:
            accumulator.add(*sample)
        value = accumulator.finish()["0"]
        self.assertEqual(value["window_boundary_excluded_intervals"], 1)
        self.assertAlmostEqual(value["window_boundary_excluded_wall_seconds"], .4)
        self.assertAlmostEqual(value["maximum_window_boundary_excluded_seconds"], .4)
        self.assertAlmostEqual(value["maximum_lag_seconds"], .4)
        self.assertEqual(value["maximum_lag_at_usec"], 2_200_000)
        self.assertEqual(value["supported_windows"], 0)
        self.assertEqual(value["status"], "unavailable_insufficient_support")
        self.assertIn("long_window_boundary_exclusion", value["coverage_reasons"])

    def test_good_window_does_not_mask_long_boundary_exclusion_or_missing_windows(self):
        samples = list(rows([24 * n for n in range(11)]))
        # Entire 2-second interval crossing two cells is excluded from the local
        # ratio but its end still demonstrates the incurred accumulated lag.
        samples += [(0, 2_000_000, 4_000_000, 240, 1, 0, 0)]
        samples += list(rows([240 + 24 * n for n in range(1, 11)], start_usec=4_100_000))
        value = reduce_rows(samples)["0"]
        self.assertEqual(value["status"], "unavailable_incomplete_coverage")
        self.assertGreaterEqual(value["supported_windows"], 2)
        self.assertGreaterEqual(value["insufficient_windows"], 1)
        self.assertEqual(value["maximum_window_boundary_excluded_seconds"], 2)
        self.assertEqual(value["maximum_lag_seconds"], 2)
        self.assertIn("unsupported_full_windows", value["coverage_reasons"])
        self.assertIn("long_window_boundary_exclusion", value["coverage_reasons"])
        self.assertAlmostEqual(value["worst_window"]["simulation_wall_ratio"], 1)

    def test_long_crossing_blocks_complete_coverage_even_when_both_cells_have_support(self):
        times_and_ticks = [(1_000_000, 0), (1_450_000, 108), (1_950_000, 228),
                           (2_075_000, 258), (2_550_000, 372), (3_000_000, 480)]
        samples = []
        before = 900_000
        for end, tick in times_and_ticks:
            samples.append((0, end - before, end, tick, tick / 240, 0, 0))
            before = end
        value = reduce_rows(samples)["0"]
        self.assertEqual(value["supported_windows"], 2)
        self.assertEqual(value["insufficient_windows"], 0)
        self.assertGreater(value["supported_window_fraction_of_active_wall"], .9)
        self.assertEqual(value["maximum_window_boundary_excluded_seconds"], .125)
        self.assertEqual(value["coverage_reasons"], ["long_window_boundary_exclusion"])
        self.assertEqual(value["status"], "unavailable_incomplete_coverage")

    def test_one_interval_is_not_a_supported_window(self):
        samples = [(0, 1_000_000, 1_000_000, 0, 0, 0, 0),
                   (0, 1_000_000, 2_000_000, 240, 1, 0, 0)]
        value = reduce_rows(samples)["0"]
        self.assertEqual(value["full_windows"], 1)
        self.assertEqual(value["insufficient_windows"], 1)
        self.assertEqual(value["supported_windows"], 0)
        self.assertIsNone(value["worst_window"])
        self.assertEqual(value["status"], "unavailable_insufficient_support")

    def test_short_phase_and_long_partial_tail_are_inconclusive(self):
        short = reduce_rows(list(rows([24 * n for n in range(9)])))["0"]
        self.assertEqual(short["status"], "unavailable_insufficient_support")
        self.assertIsNone(short["worst_window"])
        self.assertTrue(short["last_partial_window"]["partial"])
        self.assertFalse(short["last_partial_window"]["supported"])
        self.assertEqual(short["last_partial_window"]["segment_end_usec"], 1_800_000)
        tail = reduce_rows(list(rows([24 * n for n in range(19)])))["0"]
        self.assertEqual(tail["supported_windows"], 1)
        self.assertEqual(tail["status"], "unavailable_incomplete_coverage")
        self.assertIn("less_than_90_percent_active_wall_supported", tail["coverage_reasons"])
        self.assertTrue(tail["last_partial_window"]["partial"])

    def test_missing_nonfinite_invalid_and_no_session_are_unavailable(self):
        base = (0, 100_000, 1_000_000, 0, 0, 0, 0)
        for index in range(3, 7):
            for replacement in (None, float("nan"), float("inf"), True):
                sample = list(base)
                sample[index] = replacement
                with self.subTest(index=index, replacement=replacement):
                    value = reduce_rows([tuple(sample)])["0"]
                    expected = "unavailable_missing_channels" if replacement is None else "unavailable_invalid_sample"
                    self.assertEqual(value["status"], expected)
                    self.assertIsNone(value["active_wall_seconds"])
                    self.assertIsNone(value["active_sim_seconds"])
                    self.assertIsNone(value["maximum_lag_seconds"])
                    self.assertIsNone(value["worst_window"])
                    if index in (5, 6):
                        self.assertFalse(value["hold_channels_complete"])
                        self.assertIsNone(value["hold_excluded_intervals"])
                        self.assertIsNone(value["hold_excluded_wall_seconds"])
        no_session = reduce_rows(list(rows([-1, -1])))["0"]
        self.assertEqual(no_session["status"], "unavailable_no_simulation")
        self.assertIsNone(no_session["active_sim_seconds"])
        bad_tick_time = (0, 100_000, 1_000_000, 240, 2, 0, 0)
        bad = reduce_rows([bad_tick_time])["0"]
        self.assertEqual(bad["status"], "unavailable_simulation_clock_discontinuity")
        self.assertIn("simulation_clock_inconsistent", bad["issues"])

    def test_simulation_reset_cannot_join_segment_within_same_phase(self):
        samples = list(rows([24 * n for n in range(11)]))
        samples += list(rows([24 * n for n in range(11)], start_usec=2_100_000))
        value = reduce_rows(samples)["0"]
        self.assertEqual(value["status"], "unavailable_simulation_clock_discontinuity")
        self.assertIn("simulation_clock_regressed", value["issues"])
        self.assertEqual(value["unknown_excluded_intervals"], 1)
        self.assertEqual(value["active_segments"], 2)
        self.assertEqual(value["supported_windows"], 2)

    def test_phase_change_reset_allowed_but_not_linked_across_boundary(self):
        samples = list(rows([24 * n for n in range(11)]))
        samples += list(rows([24 * n for n in range(11)], phase=2, start_usec=2_100_000))
        result = reduce_rows(samples)
        self.assertEqual(set(result), {"0", "2"})
        self.assertEqual(result["0"]["status"], "available")
        self.assertEqual(result["2"]["status"], "available")
        self.assertEqual(result["2"]["phase_boundary_or_first_interval_excluded_wall_seconds"], .1)
        self.assertEqual(result["2"]["active_wall_seconds"], 1)
        self.assertAlmostEqual(result["2"]["maximum_lag_seconds"], 0)

    def test_first_phase_boundary_interval_must_fit_the_exclusion_tolerance(self):
        for boundary, status in ((50_000, "available"), (100_000, "available"),
                                 (100_001, "unavailable_incomplete_coverage"),
                                 (10_000_000, "unavailable_incomplete_coverage")):
            with self.subTest(boundary=boundary):
                accumulator = PaceWindowAccumulator()
                accumulator.add(0, 100_000, 1_000_000, 0, 0, 0, 0)
                first = 1_000_000 + boundary
                accumulator.add(1, boundary, first, 0, 0, 0, 0)
                for n in range(1, 21):
                    accumulator.add(1, 100_000, first + n * 100_000, 24 * n, n / 10, 0, 0)
                value = accumulator.finish()["1"]
                self.assertEqual(value["status"], status, value)
                self.assertEqual(value["active_wall_seconds"], 2)
                self.assertEqual(value["phase_boundary_or_first_interval_excluded_wall_seconds"], boundary / 1_000_000)
                self.assertEqual(value["supported_window_fraction_of_active_wall"], 1)
                self.assertEqual("long_phase_boundary_exclusion" in value["coverage_reasons"], boundary > 100_000)

    def test_clock_phase_reordering_and_lifecycle_are_rejected(self):
        first = (1, 100_000, 1_000_000, 0, 0, 0, 0)
        bad_next = [(1, 100_000, 1_100_001, 24, .1, 0, 0),
                    (1, 100_000, 1_000_000, 24, .1, 0, 0),
                    (0, 100_000, 1_100_000, 24, .1, 0, 0)]
        for second in bad_next:
            with self.subTest(second=second):
                accumulator = PaceWindowAccumulator()
                accumulator.add(*first)
                with self.assertRaises(ValueError):
                    accumulator.add(*second)
        for index in (float("nan"), -1, 10001, 1.5, True):
            with self.subTest(index=index), self.assertRaises(ValueError):
                PaceWindowAccumulator().add(index, *first[1:])
        for clock in (0, -1, float("inf"), True):
            with self.subTest(clock=clock), self.assertRaises(ValueError):
                PaceWindowAccumulator().add(1, clock, 1_000_000, 0, 0, 0, 0)
        accumulator = PaceWindowAccumulator()
        accumulator.add(*first)
        self.assertEqual(accumulator.finish(), accumulator.finish())
        with self.assertRaises(ValueError):
            accumulator.add(1, 100_000, 1_100_000, 24, .1, 0, 0)

    def test_chunking_does_not_change_reduction(self):
        ticks = [12 * n if n <= 50 else 600 + 36 * (n - 50) for n in range(101)]
        samples = list(rows(ticks))
        expected = reduce_rows(samples, 1)
        for chunk_size in (2, 7, 50, 101, 512):
            self.assertEqual(expected, reduce_rows(samples, chunk_size))

    def test_many_windows_and_huge_gap_keep_constant_summary_size(self):
        accumulator = PaceWindowAccumulator()
        for n in range(100_001):
            accumulator.add(0, 500_000, 1_000_000 + n * 500_000,
                            n * 120, n / 2, 0, 0)
        value = accumulator.finish()["0"]
        self.assertEqual(value["supported_windows"], 50_000)
        self.assertLess(len(json.dumps(value)), 4000)
        self.assertEqual(len(accumulator._results), 1)
        # A huge single crossing is also processed arithmetically, not by
        # iterating or allocating one object per missing window.
        accumulator = PaceWindowAccumulator()
        accumulator.add(0, 1, 1, 0, 0, 0, 0)
        accumulator.add(0, 10**15, 10**15 + 1, 0, 0, 0, 0)
        value = accumulator.finish()["0"]
        self.assertEqual(value["full_windows"], 10**9)
        self.assertEqual(value["insufficient_windows"], 10**9)
        self.assertLess(len(json.dumps(value)), 4000)
        self.assertTrue(math.isfinite(value["maximum_lag_seconds"]))


if __name__ == "__main__":
    unittest.main()
