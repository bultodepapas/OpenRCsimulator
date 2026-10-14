from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

try:
    from .session_baseline import (
        alternating_observer_order,
        parse_probe_file,
        percentile_nearest_rank,
        reduce_pair,
        validate_probe_report,
    )
except ImportError:  # Also support direct execution from this directory.
    from session_baseline import (
        alternating_observer_order,
        parse_probe_file,
        percentile_nearest_rank,
        reduce_pair,
        validate_probe_report,
    )


def valid_report(observer: bool = True) -> dict:
    tick = [3, 4, 5, 6, 7]
    return {
        "format": "openrc-session-cost v1",
        "complete": True,
        "failure": "",
        "aircraft_id": "jensen-das-ugly-stik-60",
        "case_id": "trim",
        "observer": observer,
        "requested": {"warmup_ticks": 4, "sample_ticks": 5},
        "completed": {"warmup_ticks": 4, "sample_ticks": 5},
        "tick_usec": tick if observer else [],
        "input_usec": [1, 1, 2, 2, 3] if observer else [],
        "simulation_usec": [2, 3, 3, 4, 4] if observer else [],
        "measured_wall_usec": 500 if observer else 450,
        "fingerprint": "a" * 64,
        "final_tick": 9,
        "input_reads": 9,
        "setup_usec": {"data_load": 100, "aircraft_setup": 200},
        "machine": {
            "os": "Windows",
            "processor": "Example CPU",
            "logical_cpu_count": 8,
            "architecture": "x86_64",
            "godot": "4.7.2-stable (official)",
        },
        "world": {"identity": "field-sha256", "proxies": 128, "lake_identity": "lake-sha256", "field": "default"},
        "tick_hz": 240,
        "scope": "deterministic complete-session CPU probe",
    }


class ProbeReportValidationTests(unittest.TestCase):
    def test_complete_observer_on_and_off_reports_validate(self):
        for observer in (True, False):
            with self.subTest(observer=observer):
                self.assertEqual(validate_probe_report(valid_report(observer)), [])

    def test_incomplete_probe_is_retained_as_a_valid_failure_but_rejected_for_pairing(self):
        report = valid_report()
        report.update({
            "complete": False,
            "failure": "fixture paused on failed attempted tick",
            "requested": {"warmup_ticks": 1, "sample_ticks": 5},
            "completed": {"warmup_ticks": 1, "sample_ticks": 2},
            # The third timing is the failed attempted tick; completed excludes it.
            "tick_usec": [3, 4, 5],
            "input_usec": [1, 1, 2],
            "simulation_usec": [2, 3, 3],
            "final_tick": 4,
            "input_reads": 4,
        })

        self.assertEqual(validate_probe_report(report, allow_incomplete=True), [])
        errors = validate_probe_report(report)
        self.assertTrue(any("probe reported incomplete" in error for error in errors))

    def test_truncated_complete_samples_are_rejected(self):
        report = valid_report()
        for key in ("tick_usec", "input_usec", "simulation_usec"):
            report[key] = report[key][:-1]
        errors = validate_probe_report(report)
        self.assertTrue(any("must match requested sample ticks" in error for error in errors))

    def test_incomplete_report_cannot_omit_a_completed_timing_sample(self):
        report = valid_report()
        report.update({
            "complete": False,
            "failure": "stopped",
            "requested": {"warmup_ticks": 4, "sample_ticks": 5},
            "completed": {"warmup_ticks": 4, "sample_ticks": 3},
            "tick_usec": [3, 4],
            "input_usec": [1, 1],
            "simulation_usec": [2, 3],
            "final_tick": 7,
            "input_reads": 7,
        })
        errors = validate_probe_report(report, allow_incomplete=True)
        self.assertTrue(any("completed samples or one failed attempt" in error for error in errors))

    def test_boolean_values_are_not_accepted_as_integer_counts(self):
        mutations = (
            ("requested", "sample_ticks", True),
            ("completed", "warmup_ticks", False),
            ("machine", "logical_cpu_count", True),
        )
        for parent, key, value in mutations:
            report = valid_report()
            report[parent][key] = value
            with self.subTest(parent=parent, key=key):
                self.assertTrue(validate_probe_report(report))

    def test_observer_and_complete_must_be_real_booleans(self):
        for key, value in (("observer", 1), ("complete", 1)):
            report = valid_report()
            report[key] = value
            with self.subTest(key=key):
                self.assertTrue(any(key + " must be a boolean" in error for error in validate_probe_report(report)))

    def test_invalid_tick_decomposition_and_final_tick_are_rejected(self):
        report = valid_report()
        report["simulation_usec"][2] += 1
        report["final_tick"] = 10
        errors = validate_probe_report(report)
        self.assertTrue(any("tick_usec[2]" in error for error in errors))
        self.assertTrue(any("final_tick" in error for error in errors))

    def test_timing_samples_cannot_exceed_the_measured_outer_loop(self):
        report = valid_report()
        report["measured_wall_usec"] = 24
        errors = validate_probe_report(report)
        self.assertTrue(any("sum(tick_usec)" in error for error in errors))

    def test_empty_identity_on_complete_run_is_rejected(self):
        report = valid_report()
        report["world"]["identity"] = ""
        self.assertTrue(any("world.identity" in error for error in validate_probe_report(report)))

    def test_truncated_json_and_json_nan_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "probe.json"
            path.write_text("{\"format\":", encoding="utf-8")
            report, error = parse_probe_file(path)
            self.assertIsNone(report)
            self.assertIn("malformed", error)

            path.write_text('{"format":"openrc-session-cost v1","value":NaN}', encoding="utf-8")
            report, error = parse_probe_file(path)
            self.assertIsNone(report)
            self.assertIn("non-finite", error)

    def test_nested_non_finite_value_is_rejected(self):
        report = valid_report()
        report["machine"]["temperature"] = float("inf")
        self.assertTrue(any("must be finite" in error for error in validate_probe_report(report)))


class ReducerTests(unittest.TestCase):
    def test_direct_reduction_rejects_equal_missing_or_malformed_identities(self):
        for field in ("fingerprint", "machine", "world", "format", "completed"):
            on_report, off_report = valid_report(True), valid_report(False)
            del on_report[field]
            del off_report[field]
            with self.subTest(field=field):
                result = reduce_pair(on_report, off_report)
                self.assertFalse(result["comparable"])
                self.assertIsNone(result["observer_overhead_usec_per_tick"])

    def test_nearest_rank_percentiles(self):
        values = [10, 1, 9, 3, 7, 6, 2, 8, 4, 5]
        self.assertEqual(percentile_nearest_rank(values, 50), 5)
        self.assertEqual(percentile_nearest_rank(values, 95), 10)
        self.assertEqual(percentile_nearest_rank(values, 99), 10)
        self.assertEqual(percentile_nearest_rank(values, 1), 1)

    def test_nearest_rank_rejects_empty_invalid_and_boolean_inputs(self):
        with self.assertRaises(ValueError):
            percentile_nearest_rank([], 50)
        with self.assertRaises(ValueError):
            percentile_nearest_rank([1], 0)
        with self.assertRaises(ValueError):
            percentile_nearest_rank([1], 101)
        with self.assertRaises(ValueError):
            percentile_nearest_rank([True], 50)

    def test_matching_fingerprints_allow_per_tick_observer_overhead(self):
        on_report = valid_report(observer=True)
        off_report = valid_report(observer=False)
        reduced = reduce_pair(on_report, off_report)
        self.assertTrue(reduced["fingerprints_equal"])
        self.assertTrue(reduced["comparable"])
        self.assertEqual(reduced["observer_on_wall_usec_per_tick"], 100)
        self.assertEqual(reduced["observer_off_wall_usec_per_tick"], 90)
        self.assertEqual(reduced["observer_overhead_usec_per_tick"], 10)

    def test_mismatched_fingerprints_never_produce_overhead(self):
        on_report = valid_report(observer=True)
        off_report = valid_report(observer=False)
        off_report["fingerprint"] = "b" * 64
        reduced = reduce_pair(on_report, off_report)
        self.assertFalse(reduced["fingerprints_equal"])
        self.assertFalse(reduced["comparable"])
        self.assertIsNone(reduced["observer_overhead_usec_per_tick"])
        self.assertIn("different fingerprints", reduced["reasons"][0])

    def test_observer_order_alternates(self):
        self.assertEqual(alternating_observer_order(1), ("on", "off"))
        self.assertEqual(alternating_observer_order(2), ("off", "on"))
        self.assertEqual(alternating_observer_order(3), ("on", "off"))
        with self.assertRaises(ValueError):
            alternating_observer_order(0)


if __name__ == "__main__":
    unittest.main()
