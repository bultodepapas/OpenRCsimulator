#!/usr/bin/env python3
"""Mutation checks for the native experiment's evidence comparator (no engine needed)."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("smooth_runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class EvidenceComparison(unittest.TestCase):
    def setUp(self):
        self.reference = {"format": "openrc-e0b6p-swirl-cost v1", "rows": []}
        for regime in ("forward", "stall", "static", "spin", "reverse_fade", "reverse_off"):
            for swirl in (0.0, 0.4):
                self.reference["rows"].append({
                    "regime": regime, "swirl_factor": swirl, "median_us": 300.0,
                    "batches_us": [300.0] * 5,
                    "boundaries": [{"state": [0.0] * 13, "aux": [0.0] * 14, "continuous": []}
                                   for _ in range(240)]})

    def test_identical_passes(self):
        report = runner.compare_trajectories(self.reference, copy.deepcopy(self.reference))
        self.assertTrue(all(row["exact_boundaries"] for row in report["rows"]))

    def test_nonfinite_and_excess_error_fail(self):
        for value in (float("nan"), float("inf"), 1e-8, True, "0"):
            with self.subTest(value=value):
                changed = copy.deepcopy(self.reference)
                changed["rows"][0]["boundaries"][100]["state"][3] = value
                with self.assertRaises(RuntimeError):
                    runner.compare_trajectories(self.reference, changed)

    def test_missing_and_truncated_boundaries_fail(self):
        for key in ("state", "aux", "continuous"):
            changed = copy.deepcopy(self.reference)
            del changed["rows"][0]["boundaries"][100][key]
            with self.assertRaises(RuntimeError):
                runner.compare_trajectories(self.reference, changed)
        changed = copy.deepcopy(self.reference)
        changed["rows"][0]["boundaries"].pop()
        with self.assertRaises(RuntimeError):
            runner.compare_trajectories(self.reference, changed)

    def test_both_empty_body_arrays_cannot_pass(self):
        for key in ("state", "aux"):
            changed = copy.deepcopy(self.reference)
            changed["rows"][0]["boundaries"][0][key] = []
            with self.assertRaises(RuntimeError):
                runner.compare_trajectories(changed, changed)

    def test_native_requires_actual_kernel_calls(self):
        good = {"native": 100, "kernel_calls": 50, "legacy": 0, "refused": 0}
        runner._ensure_routes({"native_route_counts": good}, "native", require_native=True)
        for key, value in (("kernel_calls", 0), ("native", 0), ("refused", 1), ("legacy", 1)):
            changed = good | {key: value}
            with self.assertRaises(RuntimeError):
                runner._ensure_routes({"native_route_counts": changed}, "native", require_native=True)

    def test_duplicate_roster_is_rejected_even_on_both_sides(self):
        changed = copy.deepcopy(self.reference)
        changed["rows"][1] = copy.deepcopy(changed["rows"][0])
        with self.assertRaises(RuntimeError):
            runner.compare_trajectories(changed, changed)


if __name__ == "__main__":
    unittest.main()
