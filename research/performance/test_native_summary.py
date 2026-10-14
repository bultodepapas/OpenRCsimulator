from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

try:
    from .native_summary import (
        DEFAULT_POLICY,
        active_flight_reasons,
        duration_gate,
        summarize_directory,
        summarize_run,
        validate_native_report,
    )
except ImportError:  # Also support direct execution from this directory.
    from native_summary import (
        DEFAULT_POLICY,
        active_flight_reasons,
        duration_gate,
        summarize_directory,
        summarize_run,
        validate_native_report,
    )


SHORT_POLICY = {
    **DEFAULT_POLICY,
    "minimum_warmup_s": 0.0,
    "minimum_sample_s": 0.0375,
    "minimum_runs": 1,
}


def valid_report(
    *,
    interval_usec: int = 12_500,
    ticks_per_frame: int = 3,
    ticks: list[int] | None = None,
    times: list[float] | None = None,
    sample_s: float | None = None,
    warmup_s: float = 0.0,
    actual_warmup_s: float = 0.0,
    route: str = "live-input",
    input_enabled: bool = True,
    paused: bool = False,
) -> dict:
    frame_count = len(ticks) if ticks is not None else 4
    deltas_s = [interval_usec / 1_000_000.0] * frame_count
    wall_usec = [interval_usec] * frame_count
    frame_ends = [1_000_000 + interval_usec * index for index in range(frame_count)]
    if ticks is None:
        ticks = [240 + ticks_per_frame * index for index in range(frame_count)]
    if times is None:
        times = [tick / 240.0 for tick in ticks]
    total_s = sum(deltas_s)
    if sample_s is None:
        sample_s = total_s - deltas_s[-1]
    frame_ms = interval_usec / 1000.0
    return {
        "format": "openrc-frametimes v2",
        "version": 2,
        "complete": True,
        "failure": "",
        "route": route,
        "case_id": route,
        "aircraft_id": "jensen-das-ugly-stik-60",
        "preset": "current-default",
        "backend": "gl_compatibility",
        "input_enabled": input_enabled,
        "frames": frame_count,
        "frame_deltas_s": deltas_s,
        "frame_wall_usec": wall_usec,
        "frame_end_monotonic_usec": frame_ends,
        "frame_ms": {
            "p50": frame_ms,
            "p95": frame_ms,
            "p99": frame_ms,
            "max": frame_ms,
        },
        "sample_s": sample_s,
        "warmup_s": warmup_s,
        "actual_sample_s": total_s,
        "actual_warmup_s": actual_warmup_s,
        "wall_seconds": total_s,
        "seconds": total_s,
        "raw_metrics": {
            "fps_monitor": [80.0] * frame_count,
            "sim_tick": [float(tick) for tick in ticks],
            "sim_time_s": times,
        },
        "measured_simulation": {
            "scope": "first sampled frame end through last sampled frame end; excludes the first sampled interval",
            "start_tick": ticks[0],
            "end_tick": ticks[-1],
            "ticks": ticks[-1] - ticks[0],
            "start_time_s": times[0],
            "end_time_s": times[-1],
        },
        "simulation": {
            "physics_ticks_per_second": 240,
            "physics_enabled": True,
            "paused": paused,
            "fault": "",
        },
    }


def sustained_report() -> dict:
    # 3,601 samples cover 60.0012 s between first and last frame ends. The
    # extra first sampled interval follows the logger's endpoint convention.
    report = valid_report(
        interval_usec=16_667,
        ticks_per_frame=4,
        ticks=[240 + 4 * index for index in range(3_601)],
        warmup_s=10.0,
        actual_warmup_s=10.1,
        sample_s=60.0012,
    )
    return report


def write_run(directory: Path, name: str, report: dict, log_text: str = "Godot clean\n") -> Path:
    report_path = directory / f"{name}.json"
    report_path.write_text(json.dumps(report, allow_nan=True), encoding="utf-8")
    report_path.with_suffix(".log").write_text(log_text, encoding="utf-8")
    return report_path


class NativeReportValidationTests(unittest.TestCase):
    def test_valid_report_uses_frame_endpoints_for_simulation_wall_ratio(self):
        report = valid_report()
        errors, derived = validate_native_report(report)

        self.assertEqual(errors, [])
        self.assertIsNotNone(derived)
        self.assertAlmostEqual(derived["sample_wall_span_excluding_first_interval_s"], 0.0375)
        self.assertAlmostEqual(derived["sample_simulation_span_s"], 0.0375)
        self.assertAlmostEqual(derived["simulation_wall_ratio"], 1.0)
        # Summing all frame deltas would include the first, deliberately
        # excluded interval and report a misleading 0.75 ratio here.
        self.assertNotAlmostEqual(derived["simulation_wall_ratio"], 0.0375 / 0.05)

    def test_boolean_values_are_not_accepted_as_counts_or_numbers(self):
        report = valid_report()
        report["version"] = True
        report["frames"] = True
        report["input_enabled"] = 1
        report["simulation"]["paused"] = 0
        report["raw_metrics"]["sim_tick"][1] = True

        errors, _ = validate_native_report(report)
        joined = "\n".join(errors)
        self.assertIn("version must be integer 2", joined)
        self.assertIn("frames must be a positive integer", joined)
        self.assertIn("input_enabled must be a boolean", joined)
        self.assertIn("simulation.paused must be a boolean", joined)
        self.assertIn("raw_metrics.sim_tick[1] must be a finite number", joined)

    def test_non_finite_json_is_rejected_when_summarizing(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report_path = root / "run-1.json"
            report = valid_report()
            report["raw_metrics"]["sim_time_s"][2] = float("nan")
            write_run(root, "run-1", report)

            summary = summarize_run(report_path, SHORT_POLICY)

        self.assertFalse(summary["collection_valid"])
        self.assertTrue(any("non-finite JSON value" in reason for reason in summary["collection_reasons"]))
        self.assertIsNotNone(summary["report_sha256"])
        self.assertIsNotNone(summary["log_sha256"])

    def test_truncated_raw_metric_arrays_are_rejected(self):
        report = valid_report()
        report["raw_metrics"]["fps_monitor"].pop()
        errors, _ = validate_native_report(report)
        self.assertTrue(any("raw_metrics.fps_monitor length must equal frames" in error for error in errors))

    def test_incomplete_report_is_invalid_even_with_a_partial_sample(self):
        report = valid_report()
        report["complete"] = False
        report["failure"] = "paused during capture"
        report["frames"] = 3
        for key in ("frame_deltas_s", "frame_wall_usec", "frame_end_monotonic_usec"):
            report[key].pop()
        for values in report["raw_metrics"].values():
            values.pop()
        errors, _ = validate_native_report(report)
        self.assertIn("report is marked incomplete", errors)

    def test_non_monotonic_frame_endpoints_are_rejected(self):
        report = valid_report()
        report["frame_end_monotonic_usec"][2] = report["frame_end_monotonic_usec"][1]
        errors, _ = validate_native_report(report)
        self.assertTrue(any("strictly increasing" in error for error in errors))


class NativeRunClassificationTests(unittest.TestCase):
    def test_complete_paused_run_is_collection_valid_but_not_active_flight(self):
        paused = valid_report(ticks=[240] * 4, times=[1.0] * 4, paused=True)
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = write_run(Path(temp_dir), "run-1", paused)
            summary = summarize_run(report_path, SHORT_POLICY)

        self.assertTrue(summary["collection_valid"])
        self.assertFalse(summary["active_flight_qualifier"])
        self.assertIn("simulation was paused", summary["active_flight_reasons"])
        self.assertIn("simulation did not advance during the measured sample", summary["active_flight_reasons"])
        self.assertFalse(summary["performance_pass"])

    def test_scripted_route_and_disabled_input_do_not_qualify(self):
        for report, expected_reason in (
            (valid_report(route="scripted"), "route is not live-input"),
            (valid_report(input_enabled=False), "input is disabled"),
        ):
            with self.subTest(expected_reason=expected_reason), tempfile.TemporaryDirectory() as temp_dir:
                report_path = write_run(Path(temp_dir), "run-1", report)
                summary = summarize_run(report_path, SHORT_POLICY)

            self.assertTrue(summary["collection_valid"])
            self.assertFalse(summary["active_flight_qualifier"])
            self.assertIn(expected_reason, summary["active_flight_reasons"])

    def test_long_nonadvancing_run_is_disqualified(self):
        report = valid_report(
            interval_usec=130_000,
            ticks=[240, 240, 240, 249],
            times=[1.0, 1.0, 1.0, 1.0375],
        )
        errors, derived = validate_native_report(report)
        self.assertEqual(errors, [])
        self.assertGreater(derived["max_nonadvancing_interval_usec"], 250_000)
        reasons = active_flight_reasons(report, derived, SHORT_POLICY)
        self.assertIn("simulation did not advance for more than 250 ms", reasons)

    def test_engine_error_in_log_invalidates_collection_and_is_retained(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = write_run(
                Path(temp_dir),
                "run-1",
                valid_report(),
                "Godot Engine v4.7.2\nSCRIPT ERROR: fixture failure\nExit code: 0\n",
            )
            summary = summarize_run(report_path, SHORT_POLICY)

        self.assertFalse(summary["collection_valid"])
        self.assertEqual(summary["engine_errors"], ["SCRIPT ERROR: fixture failure"])
        self.assertTrue(any("contains Godot ERROR output" in reason for reason in summary["collection_reasons"]))
        self.assertIn("collection is invalid", summary["active_flight_reasons"])

    def test_utf16_bom_log_still_exposes_engine_errors(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report_path = root / "run-1.json"
            report_path.write_text(json.dumps(valid_report()), encoding="utf-8")
            report_path.with_suffix(".log").write_bytes("ERROR: encoded failure\n".encode("utf-16"))
            summary = summarize_run(report_path, SHORT_POLICY)

        self.assertFalse(summary["collection_valid"])
        self.assertEqual(summary["engine_errors"], ["ERROR: encoded failure"])

    def test_short_smoke_is_collection_valid_but_fails_default_duration_gate(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = write_run(Path(temp_dir), "run-1", valid_report())
            summary = summarize_run(report_path, DEFAULT_POLICY)

        self.assertTrue(summary["collection_valid"])
        self.assertTrue(summary["active_flight_qualifier"])
        self.assertFalse(summary["duration_eligibility"]["eligible"])
        self.assertIn("requested warm-up is shorter than 10 s", summary["duration_eligibility"]["reasons"])
        self.assertIn("requested sample is shorter than 60 s", summary["duration_eligibility"]["reasons"])
        self.assertFalse(summary["performance_pass"])

    def test_actual_warmup_must_reach_requested_warmup(self):
        report = valid_report(warmup_s=10.0, actual_warmup_s=9.0)
        errors, _ = validate_native_report(report)
        self.assertEqual(errors, [])
        duration = duration_gate(report, DEFAULT_POLICY)
        self.assertFalse(duration["eligible"])
        self.assertIn("actual warm-up is shorter than requested", duration["reasons"])

    def test_pacing_failure_remains_distinct_from_active_flight_and_collection(self):
        report = valid_report(interval_usec=25_000, ticks_per_frame=6)
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = write_run(Path(temp_dir), "run-1", report)
            summary = summarize_run(report_path, SHORT_POLICY)

        self.assertTrue(summary["collection_valid"])
        self.assertTrue(summary["active_flight_qualifier"])
        self.assertTrue(summary["duration_eligibility"]["eligible"])
        self.assertFalse(summary["pacing_gate"]["p95_pass"])
        self.assertTrue(summary["pacing_gate"]["p99_pass"])
        self.assertFalse(summary["performance_pass"])

    def test_sustained_60_second_run_can_pass_individually(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = write_run(Path(temp_dir), "run-1", sustained_report())
            summary = summarize_run(report_path, DEFAULT_POLICY)

        self.assertTrue(summary["collection_valid"])
        self.assertTrue(summary["active_flight_qualifier"])
        self.assertTrue(summary["duration_eligibility"]["eligible"])
        self.assertTrue(summary["pacing_gate"]["pass"])
        self.assertTrue(summary["performance_pass"])

    def test_campaign_requires_three_individually_passing_runs(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report = sustained_report()
            write_run(root, "run-1", report)
            one_run_summary, one_run_status = summarize_directory(root, root / "one-run-summary.json")

            self.assertTrue(one_run_summary["runs"][0]["performance_pass"])
            self.assertFalse(one_run_summary["performance_pass"])
            self.assertEqual(one_run_status, 1)
            self.assertIn("campaign has fewer than 3 runs", one_run_summary["campaign_reasons"])

            write_run(root, "run-2", report)
            write_run(root, "run-3", report)
            three_run_summary, three_run_status = summarize_directory(root, root / "three-run-summary.json")

        self.assertEqual(three_run_summary["run_count"], 3)
        self.assertEqual(three_run_summary["performance_pass_count"], 3)
        self.assertTrue(three_run_summary["performance_pass"])
        self.assertEqual(three_run_status, 0)

    def test_campaign_writes_report_and_refuses_to_overwrite(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            write_run(root, "run-1", valid_report())
            output = root / "summary.json"
            summary, status = summarize_directory(root, output)
            self.assertTrue(output.is_file())
            self.assertTrue(summary["collection_valid"])  # the smoke report is validly collected
            self.assertEqual(status, 1)  # duration and run-count gates still fail
            with self.assertRaises(ValueError):
                summarize_directory(root, output)


if __name__ == "__main__":
    unittest.main()
