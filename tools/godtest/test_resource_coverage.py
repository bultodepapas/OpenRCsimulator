"""Tests for GOD TEST's raw process-resource temporal coverage gate."""
from __future__ import annotations

import copy
from pathlib import Path
import sys
import unittest
from types import SimpleNamespace
from unittest import mock

from resource_coverage import (validate_resource_owner_clock, validate_resource_required_fields,
                               validate_resource_timing)

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def resource_report():
    """A typical complete sampler report, including its actual v1 clock shape."""
    required = ("rss_bytes", "cpu_user_seconds", "cpu_system_seconds", "virtual_memory_available_bytes")
    samples = []
    for index, elapsed in enumerate((0.020, 1.022, 2.024)):
        samples.append({
            "elapsed_seconds": elapsed,
            "poll_overhead_usec": 4_000,
            "rss_bytes": 100_000 + index * 100,
            "cpu_user_seconds": 1.0 + index * 0.4,
            "cpu_system_seconds": 0.2 + index * 0.1,
            "virtual_memory_available_bytes": 20_000_000,
            "field_status": {field: "ok" for field in required},
        })
    return {
        "format": "openrc-resource-samples v1",
        "clock": {
            "source": "python_perf_counter",
            "origin_usec": 100_000_000,
            "start": {"monotonic_usec": 100_005_000, "unix_usec": 1_768_000_000_005_000,
                      "uncertainty_usec": 20_000},
            "end": {"monotonic_usec": 102_500_000, "unix_usec": 1_768_000_002_500_000,
                    "uncertainty_usec": 20_000},
        },
        "interval_seconds": 1.0,
        "max_samples": 4000,
        "sample_count": len(samples),
        "samples": samples,
        "required_coverage": "complete",
        "required_field_counts": {field: len(samples) for field in required},
        "stop_reason": "caller_finished",
        "capped": False,
    }


def owner_receipt():
    return {"monitoring_started_perf_counter_s": 99.99,
            "resource_observation": {"clock_domain": "python_perf_counter", "start_requested_usec": 99_990_000,
                                     "stop_requested_usec": 102_499_000, "finish_returned_usec": 102_501_000,
                                     "interval_seconds": 1, "max_samples": 4000}}


def set_times(report, elapsed_seconds, *, end_seconds, overhead_usec=4_000):
    report["samples"] = [dict(report["samples"][0], elapsed_seconds=elapsed,
                              poll_overhead_usec=overhead_usec) for elapsed in elapsed_seconds]
    report["sample_count"] = len(report["samples"])
    report["clock"]["end"]["monotonic_usec"] = report["clock"]["origin_usec"] + round(end_seconds * 1_000_000)


class ResourceTimingTests(unittest.TestCase):
    def test_actual_sampler_report_is_accepted(self):
        from tools.godot.resource_samples import ResourceSampler

        process = mock.Mock()
        process.create_time.return_value = 1234.5
        process.is_running.return_value = True
        process.status.return_value = "running"
        process.memory_info.return_value = SimpleNamespace(rss=4096, vms=8192)
        process.cpu_times.return_value = SimpleNamespace(user=1.0, system=0.5)
        process.io_counters.return_value = SimpleNamespace(read_bytes=10, write_bytes=20,
                                                          read_count=1, write_count=2)
        backend = mock.Mock()
        backend.Process.return_value = process
        backend.virtual_memory.return_value = SimpleNamespace(total=1024, available=512, percent=50.0)
        backend.swap_memory.return_value = SimpleNamespace(used=100, total=200)
        now = [100.0]
        with mock.patch("tools.godot.resource_samples.time.perf_counter", side_effect=lambda: now[0]):
            sampler = ResourceSampler(44, interval=1.0, max_samples=4000, backend=backend)
            self.assertTrue(sampler.poll())
            now[0] += 1.0
            self.assertTrue(sampler.poll())
            now[0] += 0.1
            report = sampler.finish()
        self.assertEqual(report["required_coverage"], "complete")
        self.assertEqual(validate_resource_timing(report)["status"], "complete")
        self.assertEqual(validate_resource_required_fields(report)["status"], "complete")
        receipt = {"monitoring_started_perf_counter_s": 100.0,
                   "resource_observation": {"clock_domain": "python_perf_counter",
                                            "start_requested_usec": 100_000_000,
                                            "stop_requested_usec": 101_100_000,
                                            "finish_returned_usec": 101_100_000,
                                            "interval_seconds": 1, "max_samples": 4000}}
        self.assertEqual(validate_resource_owner_clock(report, receipt)["status"], "complete")

    def test_realistic_complete_report_has_computed_conservative_gaps(self):
        result = validate_resource_timing(resource_report())
        self.assertEqual(result["status"], "complete", result)
        self.assertEqual(result["reasons"], [])
        self.assertEqual(result["gap_limit_usec"], 3_250_000)
        self.assertEqual(result["bounds"], {"origin_usec": 100_000_000, "start_anchor_usec": 100_005_000,
                                             "end_anchor_usec": 102_500_000})
        self.assertEqual(result["first_sample_delay_usec"], 20_000)
        self.assertEqual(result["max_inter_sample_gap_usec"], 1_006_000)
        self.assertEqual(result["last_sample_gap_usec"], 480_000)
        self.assertEqual(result["max_poll_duration_usec"], 4_000)

    def test_each_gap_fails_independently(self):
        scenarios = (
            ((4.0, 5.0, 6.0), 6.1, "first_observation_delayed"),
            ((0.02, 1.02, 5.0), 5.1, "inter_sample_gap"),
            ((0.02, 1.02, 2.02), 6.0, "last_observation_too_early"),
        )
        for times, end, reason in scenarios:
            with self.subTest(reason=reason):
                report = resource_report()
                set_times(report, times, end_seconds=end)
                result = validate_resource_timing(report)
                self.assertEqual(result["status"], "incomplete", result)
                self.assertEqual(result["reasons"], [reason])

    def test_reading_can_fall_anywhere_in_a_slow_poll(self):
        report = resource_report()
        set_times(report, (2.0, 3.4), end_seconds=3.5, overhead_usec=10_000)
        report["samples"][0]["poll_overhead_usec"] = 1_900_000
        result = validate_resource_timing(report)
        self.assertEqual(result["status"], "incomplete", result)
        self.assertEqual(result["max_inter_sample_gap_usec"], 3_300_000)
        self.assertEqual(result["reasons"], ["inter_sample_gap"])

    def test_exact_limit_is_inclusive_and_one_microsecond_more_is_not(self):
        for second, status in ((3.26, "complete"), (3.260001, "incomplete")):
            with self.subTest(second=second):
                report = resource_report()
                set_times(report, (0.01, second), end_seconds=second, overhead_usec=0)
                result = validate_resource_timing(report)
                self.assertEqual(result["status"], status, result)
                self.assertEqual(result["max_inter_sample_gap_usec"], round((second - 0.01) * 1_000_000))

    def test_clock_and_sampler_origin_are_not_interchangeable(self):
        report = resource_report()
        report["clock"]["start"]["monotonic_usec"] += 3_500_000
        set_times(report, (3.52, 4.52), end_seconds=4.53)
        result = validate_resource_timing(report)
        self.assertEqual(result["first_sample_delay_usec"], 3_520_000)
        self.assertEqual(result["reasons"], ["first_observation_delayed"])

    def test_too_few_samples_and_clockless_legacy_artifact_fail_closed(self):
        report = resource_report()
        set_times(report, (0.02,), end_seconds=0.03)
        result = validate_resource_timing(report)
        self.assertEqual(result["status"], "incomplete")
        self.assertEqual(result["reasons"], ["fewer_than_two_samples"])
        report = resource_report()
        del report["clock"]
        result = validate_resource_timing(report)
        self.assertEqual(result["status"], "unavailable")
        self.assertEqual(result["reasons"], ["clock_unavailable"])
        self.assertEqual(validate_resource_timing(None)["status"], "unavailable")

    def test_corrupt_or_missing_anchors_are_rejected(self):
        changes = (
            (lambda c: c.update(origin_usec=True), "invalid_clock_origin"),
            (lambda c: c.update(source="utc"), "invalid_clock_source"),
            (lambda c: c["start"].update(monotonic_usec=99_000_000), "invalid_clock_bounds"),
            (lambda c: c["end"].update(monotonic_usec=100_000_000), "invalid_clock_bounds"),
            (lambda c: c["end"].update(monotonic_usec=100_010_000), "sample_after_end_anchor"),
            (lambda c: c["start"].update(uncertainty_usec=True), "invalid_clock_anchor"),
            (lambda c: c["start"].update(uncertainty_usec=19_999), "invalid_clock_anchor"),
            (lambda c: c["end"].update(unix_usec=float("nan")), "invalid_clock_anchor"),
            (lambda c: c["start"].pop("monotonic_usec"), "clock_anchor_unavailable"),
        )
        for change, reason in changes:
            with self.subTest(reason=reason):
                report = resource_report()
                change(report["clock"])
                result = validate_resource_timing(report)
                self.assertNotEqual(result["status"], "complete", result)
                self.assertEqual(result["reasons"], [reason])

    def test_invalid_numbers_and_structures_do_not_crash_or_pass(self):
        for invalid in (True, None, "1", float("nan"), float("inf"), -1, 10**1000):
            with self.subTest(interval=repr(invalid)[:20]):
                report = resource_report()
                report["interval_seconds"] = invalid
                self.assertEqual(validate_resource_timing(report)["status"], "incomplete")
            with self.subTest(elapsed=repr(invalid)[:20]):
                report = resource_report()
                report["samples"][1]["elapsed_seconds"] = invalid
                self.assertNotEqual(validate_resource_timing(report)["status"], "complete")
        for invalid in (True, 1.0, -1, None, "4000"):
            with self.subTest(overhead=invalid):
                report = resource_report()
                report["samples"][1]["poll_overhead_usec"] = invalid
                self.assertEqual(validate_resource_timing(report)["reasons"], ["invalid_sample_timing"])
        report = resource_report()
        report["sample_count"] = True
        self.assertEqual(validate_resource_timing(report)["reasons"], ["sample_count_mismatch"])
        report = resource_report()
        report["samples"] = [None] * 10_001
        report["sample_count"] = len(report["samples"])
        report["max_samples"] = 10_000
        self.assertEqual(validate_resource_timing(report)["reasons"], ["invalid_sample_limit"])

    def test_sample_times_and_poll_brackets_must_be_ordered(self):
        cases = (
            (lambda r: r["samples"][1].update(elapsed_seconds=0.02), "sample_times_not_increasing"),
            (lambda r: r["samples"][1].update(elapsed_seconds=0.021, poll_overhead_usec=4_000), "overlapping_polls"),
            (lambda r: r["samples"][0].update(poll_overhead_usec=21_000), "poll_before_origin"),
            (lambda r: r["samples"][0].update(poll_overhead_usec=16_000), "poll_before_start_anchor"),
        )
        for change, reason in cases:
            with self.subTest(reason=reason):
                report = resource_report()
                change(report)
                result = validate_resource_timing(report)
                self.assertEqual(result["status"], "incomplete", result)
                self.assertEqual(result["reasons"], [reason])

    def test_clock_rounding_is_allowed_but_real_boundary_crossing_is_not(self):
        report = resource_report()
        set_times(report, (0.005, 0.01), end_seconds=0.01, overhead_usec=0)
        report["samples"][0]["poll_overhead_usec"] = 2
        report["samples"][1]["elapsed_seconds"] = 0.010001
        self.assertEqual(validate_resource_timing(report)["status"], "complete")
        report["samples"][1]["elapsed_seconds"] = 0.010002
        self.assertEqual(validate_resource_timing(report)["reasons"], ["sample_after_end_anchor"])

    def test_timing_is_separate_from_required_fields_and_utc_correlation(self):
        report = resource_report()
        report["required_coverage"] = "partial"
        report["samples"][0]["cpu_user_seconds"] = None
        # Wall-clock adjustments do not change the perf_counter duration.
        report["clock"]["end"]["unix_usec"] = report["clock"]["start"]["unix_usec"] - 3_000_000
        before = copy.deepcopy(report)
        self.assertEqual(validate_resource_timing(report)["status"], "complete")
        self.assertEqual(report, before)


class RequiredFieldCoverageTests(unittest.TestCase):
    def test_recomputes_complete_fields_and_ignores_optional_failures(self):
        report = resource_report()
        report.update(measurement_status="partial", errors=[{"field": "io_counters"}])
        report["summary"] = {"counter_resets": ["io_read_bytes"]}
        report["samples"][1].update(io_read_bytes=None, cpu_percent=None)
        report["samples"][1]["field_status"]["io_read_bytes"] = "unsupported"
        result = validate_resource_required_fields(report)
        self.assertEqual(result["status"], "complete", result)
        self.assertEqual(set(result["required_field_counts"].values()), {3})

    def test_complete_label_does_not_hide_missing_or_corrupt_fields(self):
        required = ("rss_bytes", "cpu_user_seconds", "cpu_system_seconds", "virtual_memory_available_bytes")
        for field in required:
            for invalid in (None, True, -1, float("nan"), float("inf"), 10**1000):
                with self.subTest(field=field, invalid=repr(invalid)[:20]):
                    report = resource_report()
                    report["samples"][1][field] = invalid
                    self.assertEqual(validate_resource_required_fields(report)["reasons"], ["invalid_required_field"])
            with self.subTest(field=field, status="error"):
                report = resource_report()
                report["samples"][1]["field_status"][field] = "error"
                self.assertEqual(validate_resource_required_fields(report)["reasons"], ["required_field_not_ok"])
            with self.subTest(field=field, missing=True):
                report = resource_report()
                del report["samples"][1][field]
                self.assertEqual(validate_resource_required_fields(report)["status"], "unavailable")
        for field in ("rss_bytes", "virtual_memory_available_bytes"):
            with self.subTest(field=field, fractional=True):
                report = resource_report()
                report["samples"][1][field] = 1.5
                self.assertEqual(validate_resource_required_fields(report)["reasons"], ["invalid_required_field"])

    def test_counter_reset_cap_and_stop_invariants_are_checked(self):
        cases = (
            (lambda r: r["samples"][1].update(cpu_user_seconds=0), "cpu_counter_decreased"),
            (lambda r: r["samples"][1].update(cpu_system_seconds=0), "cpu_counter_decreased"),
            (lambda r: r.update(summary={"counter_resets": ["cpu_system_seconds"]}), "cpu_counter_reset_reported"),
            (lambda r: r.update(capped=True), "sample_limit_reached"),
            (lambda r: r.update(max_samples=3), "sample_limit_reached"),
            (lambda r: r.update(capped=0), "invalid_cap_status"),
            (lambda r: r.update(stop_reason="process_exited"), "sampler_did_not_finish_cleanly"),
            (lambda r: r.update(required_coverage="partial"), "producer_required_coverage_incomplete"),
            (lambda r: r.update(sample_count=True), "sample_count_mismatch"),
            (lambda r: r["required_field_counts"].update(rss_bytes=True), "required_field_count_mismatch"),
            (lambda r: r["required_field_counts"].update(cpu_system_seconds=2), "required_field_count_mismatch"),
        )
        for change, reason in cases:
            with self.subTest(reason=reason):
                report = resource_report()
                change(report)
                result = validate_resource_required_fields(report)
                self.assertEqual(result["status"], "incomplete", result)
                self.assertEqual(result["reasons"], [reason])

    def test_missing_old_metadata_and_too_few_rows_do_not_pass(self):
        report = resource_report()
        del report["required_field_counts"]
        self.assertEqual(validate_resource_required_fields(report)["status"], "unavailable")
        report = resource_report()
        report["samples"] = report["samples"][:1]
        report["sample_count"] = 1
        self.assertEqual(validate_resource_required_fields(report)["reasons"], ["fewer_than_two_samples"])


class ResourceOwnerClockTests(unittest.TestCase):
    def test_valid_receipt_binds_owner_start_stop_and_config(self):
        result = validate_resource_owner_clock(resource_report(), owner_receipt())
        self.assertEqual(result["status"], "complete", result)
        self.assertEqual(result["gap_limit_usec"], 3_250_000)
        self.assertEqual(result["first_sample_delay_usec"], 30_000)
        self.assertEqual(result["last_sample_gap_usec"], 479_000)
        self.assertEqual(result["reasons"], [])

    def test_missing_and_bad_receipts_fail_closed(self):
        self.assertEqual(validate_resource_owner_clock(resource_report(), {})["status"], "unavailable")
        changes = (
            (lambda r: r.update(clock_domain="unix"), "invalid_owner_clock_domain"),
            (lambda r: r.update(start_requested_usec=True), "invalid_owner_clock_bounds"),
            (lambda r: r.update(start_requested_usec=102_500_000), "invalid_owner_clock_bounds"),
            (lambda r: r.update(finish_returned_usec=102_498_000), "invalid_owner_clock_bounds"),
            (lambda r: r.update(interval_seconds=True), "unsupported_owner_sampling_config"),
            (lambda r: r.update(interval_seconds=60), "unsupported_owner_sampling_config"),
            (lambda r: r.update(max_samples=3999), "unsupported_owner_sampling_config"),
            (lambda r: r.pop("stop_requested_usec"), "owner_clock_unavailable"),
        )
        for change, reason in changes:
            with self.subTest(reason=reason):
                receipt = owner_receipt()
                change(receipt["resource_observation"])
                result = validate_resource_owner_clock(resource_report(), receipt)
                self.assertNotEqual(result["status"], "complete", result)
                self.assertEqual(result["reasons"], [reason])

    def test_artifact_cannot_choose_wider_interval_or_another_cap(self):
        for field, value in (("interval_seconds", 60), ("interval_seconds", True), ("max_samples", 10000),
                             ("max_samples", True)):
            with self.subTest(field=field, value=value):
                report = resource_report()
                report[field] = value
                self.assertEqual(validate_resource_owner_clock(report, owner_receipt())["reasons"],
                                 ["sampler_config_mismatch"])

    def test_owner_lifecycle_must_bracket_real_sampler_anchors(self):
        changes = (
            (lambda o: o.update(start_requested_usec=100_001_000), "sampler_started_before_owner_request"),
            (lambda o: o.update(stop_requested_usec=102_500_100), "sampler_finish_outside_owner_bracket"),
            (lambda o: o.update(stop_requested_usec=102_000_000, finish_returned_usec=102_001_000),
             "sampler_finish_outside_owner_bracket"),
            (lambda o: o.update(stop_requested_usec=102_020_000), "sample_after_owner_stop"),
        )
        for change, reason in changes:
            with self.subTest(reason=reason):
                receipt = owner_receipt()
                del receipt["monitoring_started_perf_counter_s"]
                change(receipt["resource_observation"])
                result = validate_resource_owner_clock(resource_report(), receipt)
                self.assertEqual(result["status"], "incomplete", result)
                self.assertEqual(result["reasons"], [reason])

    def test_owner_start_and_stop_gaps_are_checked_independently(self):
        report = resource_report()
        receipt = owner_receipt()
        receipt["monitoring_started_perf_counter_s"] = 96.0
        receipt["resource_observation"]["start_requested_usec"] = 96_000_000
        result = validate_resource_owner_clock(report, receipt)
        self.assertEqual(validate_resource_timing(report)["status"], "complete")
        self.assertEqual(result["reasons"], ["first_observation_delayed_from_owner_start"])
        report = resource_report()
        receipt = owner_receipt()
        receipt["resource_observation"].update(stop_requested_usec=106_000_000, finish_returned_usec=106_001_000)
        report["clock"]["end"]["monotonic_usec"] = 106_000_000
        result = validate_resource_owner_clock(report, receipt)
        self.assertEqual(result["reasons"], ["last_observation_too_early_for_owner_stop"])
        self.assertEqual(result["last_sample_gap_usec"], 3_980_000)

    def test_recorded_monitoring_start_is_cross_checked_when_present(self):
        for value in (True, None, float("nan"), float("inf"), -1, 95.0):
            with self.subTest(value=value):
                receipt = owner_receipt()
                receipt["monitoring_started_perf_counter_s"] = value
                self.assertEqual(validate_resource_owner_clock(resource_report(), receipt)["reasons"],
                                 ["monitoring_start_mismatch"])
        receipt = owner_receipt()
        receipt["monitoring_started_perf_counter_s"] = 99.990001
        self.assertEqual(validate_resource_owner_clock(resource_report(), receipt)["status"], "complete")


if __name__ == "__main__":
    unittest.main()
