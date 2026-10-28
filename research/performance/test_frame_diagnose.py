from __future__ import annotations

import argparse
import contextlib
import io
import json
import math
import tempfile
import unittest
from pathlib import Path

try:
    from .frame_diagnose import (
        DEFAULT_BUDGET_MS,
        diagnose,
        main,
        parse_byte_limit,
        write_new_json,
    )
    from .session_baseline import percentile_nearest_rank
    from .test_native_summary import sustained_report, valid_report, write_stream_fixture, write_stream_run
except ImportError:  # Also support direct execution from this directory.
    from frame_diagnose import (
        DEFAULT_BUDGET_MS,
        diagnose,
        main,
        parse_byte_limit,
        write_new_json,
    )
    from session_baseline import percentile_nearest_rank
    from test_native_summary import sustained_report, valid_report, write_stream_fixture, write_stream_run


def report_with_intervals(intervals_usec: list[int]) -> dict:
    frame_count = len(intervals_usec)
    ticks = [240 + 3 * index for index in range(frame_count)]
    report = valid_report(ticks=ticks)
    ends = [2_000_000]
    for interval in intervals_usec[1:]:
        ends.append(ends[-1] + interval)
    delta_s = [interval / 1_000_000.0 for interval in intervals_usec]
    frame_ms = [interval / 1000.0 for interval in intervals_usec]
    total_s = sum(delta_s)
    report.update({
        "frames": frame_count,
        "frame_deltas_s": delta_s,
        "frame_wall_usec": intervals_usec,
        "frame_end_monotonic_usec": ends,
        "frame_ms": {
            "p50": percentile_nearest_rank(frame_ms, 50),
            "p95": percentile_nearest_rank(frame_ms, 95),
            "p99": percentile_nearest_rank(frame_ms, 99),
            "max": max(frame_ms),
        },
        "sample_s": total_s - delta_s[-1],
        "actual_sample_s": total_s,
        "wall_seconds": total_s,
        "seconds": total_s,
    })
    metrics = report["raw_metrics"]
    metrics.update({
        "process_time_s": [0.003 + index * 0.0001 for index in range(frame_count)],
        "physics_process_time_s": [0.001] * frame_count,
        "physics_step_usec": [4167] * frame_count,
        "draw_calls": [40 + index for index in range(frame_count)],
        "primitives": [1000 + 10 * index for index in range(frame_count)],
        "render_cpu_ms": [1.0 + index * 0.1 for index in range(frame_count)],
        "frame_setup_cpu_ms": [0.2] * frame_count,
        "render_gpu_ms": [0.0] * frame_count,
        "memory_static_bytes": ([100, 150, 140, 200] + [200] * max(0, frame_count - 4))[:frame_count],
        "render_video_memory_bytes": [1000 + 5 * index for index in range(frame_count)],
        "render_texture_memory_bytes": [500 + 4 * index for index in range(frame_count)],
        "render_buffer_memory_bytes": [500 + index for index in range(frame_count)],
        "resource_count": [10 + index for index in range(frame_count)],
        "orphan_node_count": [index for index in range(frame_count)],
        "observer_poll_usec": [250 + index for index in range(frame_count)],
        "invalid_value_count": [0] * frame_count,
    })
    return report


class FrameDiagnoseTests(unittest.TestCase):
    def test_stream_diagnosis_matches_legacy_and_retains_context(self):
        report = report_with_intervals([16_667, 16_667, 40_000, 16_667])
        legacy = diagnose_report(report)
        with tempfile.TemporaryDirectory() as temp_dir:
            path, _ = write_stream_run(Path(temp_dir), "run", report)
            result = diagnose(path, path.with_suffix(".log"))
        self.assertTrue(result["valid"], result["validity_reasons"])
        self.assertEqual(result["observations"], legacy["observations"])
        self.assertEqual(result["source"]["stream"]["frames"], 4)
        self.assertEqual(result["source"]["combined_input_bytes"],
                         result["source"]["report_bytes"] + result["source"]["stream"]["bytes"]
                         + result["source"]["log_bytes"])

    def test_stream_diagnosis_rejects_bad_path_hash_and_duplicate_chunk(self):
        for fault in ("path", "hash", "duplicate"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as temp_dir:
                path, records = write_stream_run(Path(temp_dir), "run", sustained_report())
                report = json.loads(path.read_text(encoding="utf-8"))
                if fault == "path":
                    report["stream"]["file"] = "../outside.jsonl"
                elif fault == "hash":
                    report["stream"]["sha256"] = "0" * 64
                else:
                    records.insert(2, dict(records[1]))
                    write_stream_fixture(path, report, records)
                path.write_text(json.dumps(report), encoding="utf-8")
                result = diagnose(path, path.with_suffix(".log"))
                self.assertFalse(result["valid"])
                self.assertTrue(any("stream" in reason for reason in result["validity_reasons"]))
                self.assertIsNone(result["observations"])

    def test_stream_diagnosis_counts_sidecar_toward_input_cap(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path, _ = write_stream_run(Path(temp_dir), "run", report_with_intervals([12_000] * 4))
            metadata = json.loads(path.read_text(encoding="utf-8"))
            cap = path.stat().st_size + metadata["stream"]["bytes"] - 1
            result = diagnose(path, path.with_suffix(".log"), max_input_bytes=cap)
        self.assertFalse(result["valid"])
        self.assertTrue(any("stream" in reason and "limit" in reason for reason in result["validity_reasons"]))
        self.assertIsNone(result["observations"])

    def test_stream_diagnosis_enforces_retained_array_memory_limit(self):
        report = report_with_intervals([12_000] * 4)
        with tempfile.TemporaryDirectory() as temp_dir:
            path, records = write_stream_run(Path(temp_dir), "run", report)
            stream_report = json.loads(path.read_text(encoding="utf-8"))
            stream_report["frames"] = 1_000_000
            stream_report["max_frames"] = 1_000_000
            stream_report["stream"]["frames"] = 1_000_000
            records[0]["max_frames"] = 1_000_000
            write_stream_fixture(path, stream_report, records)
            result = diagnose(path, path.with_suffix(".log"))
        self.assertFalse(result["valid"])
        self.assertTrue(any("memory limit" in reason for reason in result["validity_reasons"]))

    def test_stream_diagnosis_does_not_ignore_invalid_observer_values(self):
        report = report_with_intervals([12_000] * 4)
        report["raw_metrics"]["invalid_value_count"][1] = 1
        report["frame_diagnostics"] = {"invalid_numeric_value_count": 1}
        with tempfile.TemporaryDirectory() as temp_dir:
            path, _ = write_stream_run(Path(temp_dir), "run", report)
            result = diagnose(path, path.with_suffix(".log"))
        self.assertFalse(result["valid"])
        self.assertTrue(any("invalid numeric readings" in issue for issue in result["measurement_issues"]))

    def test_overflowing_metadata_publishes_invalid_diagnosis(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = json.dumps(report_with_intervals([12000, 12000, 12000, 12000]))
            source = source.replace('"backend": "gl_compatibility"', '"backend": 1e309')
            (root / "run.json").write_text(source, encoding="utf-8")
            (root / "run.log").write_text("clean\n", encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                code = main(["--report", str(root / "run.json"), "--log", str(root / "run.log"),
                             "--out", str(root / "result.json")])
            self.assertEqual(code, 1)
            self.assertFalse(json.loads((root / "result.json").read_text())["valid"])

    def test_exact_budget_boundary_is_within_budget_and_nearest_rank_is_reused(self):
        report = report_with_intervals([16_667, 16_667, 16_667, 16_667])
        result = diagnose_report(report)

        observations = result["observations"]
        self.assertEqual(observations["over_budget_count"], 0)
        self.assertEqual(observations["over_budget_burst_count"], 0)
        self.assertEqual(observations["frame_ms_nearest_rank"]["p95"], 16.667)
        self.assertEqual(observations["budget_ms"], DEFAULT_BUDGET_MS)

    def test_known_hitch_has_wall_bounds_and_simulation_context_without_causal_claim(self):
        report = report_with_intervals([16_667, 16_667, 40_000, 16_667])
        result = diagnose_report(report)

        observations = result["observations"]
        self.assertEqual(observations["over_budget_count"], 1)
        self.assertEqual(observations["over_budget_share"], 0.25)
        hitch = observations["top_frames"][0]
        self.assertEqual(hitch["frame_index"], 2)
        self.assertAlmostEqual(hitch["start_ms"], 33.334)
        self.assertAlmostEqual(hitch["end_ms"], 73.334)
        self.assertEqual(hitch["context"]["sim_tick_delta"], 3)
        self.assertEqual(hitch["context"]["physics_step_usec"], 4167)
        self.assertEqual(hitch["context"]["draw_calls"], 42)
        self.assertEqual(hitch["context"]["observer_poll_usec"], 252)
        self.assertEqual(hitch["context"]["invalid_value_count"], 0)
        self.assertEqual(hitch["context"]["render_gpu_ms_reported"], 0.0)
        self.assertIsNone(hitch["context"]["render_gpu_ms"])
        self.assertEqual(hitch["context"]["render_gpu_ms_interpretation"], "unavailable_or_zero")
        self.assertEqual(result["claims"]["causal_attribution"], "not_established")
        self.assertEqual(observations["render_gpu_ms_status"]["zero_samples"], 4)

    def test_contiguous_bursts_are_counted_even_when_only_top_burst_is_returned(self):
        report = report_with_intervals([20_000, 21_000, 16_667, 24_000, 17_000, 16_667])
        result = diagnose_report(report, top=1)

        observations = result["observations"]
        self.assertEqual(observations["over_budget_count"], 4)
        self.assertEqual(observations["over_budget_burst_count"], 2)
        bursts = observations["over_budget_bursts"]
        self.assertEqual(bursts["returned"], 1)
        self.assertTrue(bursts["truncated"])
        self.assertEqual(bursts["items"][0]["start_frame_index"], 3)
        self.assertEqual(bursts["items"][0]["end_frame_index"], 4)
        self.assertAlmostEqual(bursts["items"][0]["total_excess_ms"], 7.666)

    def test_memory_deltas_are_sample_observations_not_leak_claims(self):
        result = diagnose_report(report_with_intervals([12_000, 12_500, 13_000, 14_000]))
        memory = result["observations"]["memory_sample_trends"]

        self.assertEqual(memory["memory_static_bytes"]["start"], 100.0)
        self.assertEqual(memory["memory_static_bytes"]["end"], 200.0)
        self.assertEqual(memory["memory_static_bytes"]["max_delta_from_start"], 100.0)
        self.assertEqual(memory["render_texture_memory_bytes"]["end_delta"], 12.0)
        self.assertEqual(memory["render_buffer_memory_bytes"]["end_delta"], 3.0)
        self.assertEqual(result["claims"]["memory_leak"], "not_claimed")

    def test_source_metadata_is_preserved_without_counting_observer_polls_as_frames(self):
        report = report_with_intervals([12_000, 12_500, 13_000, 14_000])
        report["frame_diagnostics"] = {
            "enabled": True,
            "observer_poll_count": 200,
            "warmup_poll_count": 120,
            "scope": "root_viewport",
        }
        result = diagnose_report(report)

        self.assertEqual(result["source_metadata"]["frame_diagnostics"], report["frame_diagnostics"])
        self.assertEqual(result["observations"]["frame_count"], 4)

    def test_observer_invalid_sample_values_invalidate_diagnosis(self):
        report = report_with_intervals([12_000, 12_500, 13_000, 14_000])
        report["raw_metrics"]["invalid_value_count"] = [0, 1, 0, 0]
        report["frame_diagnostics"] = {"invalid_numeric_value_count": 1}
        result = diagnose_dict(report)

        self.assertFalse(result["valid"])
        self.assertEqual(result["measurement_status"], "invalid")
        self.assertTrue(any("sampled frames with invalid values: 1" in issue for issue in result["measurement_issues"]))
        self.assertTrue(any("invalid numeric readings" in hint for hint in result["measurement_hints"]))

    def test_run_wide_invalid_count_includes_warmup_and_still_prevents_success(self):
        report = report_with_intervals([12_000, 12_500, 13_000, 14_000])
        report["frame_diagnostics"] = {"invalid_numeric_value_count": 2}
        result = diagnose_dict(report)

        self.assertFalse(result["valid"])
        self.assertTrue(any("may include warm-up polls" in issue for issue in result["measurement_issues"]))

    def test_unavailable_gpu_capability_rejects_positive_raw_values(self):
        report = report_with_intervals([12_000, 12_500, 13_000, 14_000])
        report["frame_diagnostics"] = {
            "render_timing_available": False,
            "viewport_scope": "provided viewport only",
        }
        report["raw_metrics"]["render_gpu_ms"] = [0.0, 1.4, 0.0, 0.8]
        result = diagnose_dict(report)

        self.assertFalse(result["valid"])
        gpu = result["observations"]["render_gpu_ms_status"]
        self.assertEqual(gpu["measured_positive_samples"], 0)
        self.assertEqual(gpu["contradictory_positive_samples"], 2)
        self.assertEqual(gpu["interpretation"], "invalid_positive_samples_with_timing_unavailable")
        self.assertEqual(gpu["scope"], "provided viewport only")
        by_index = {item["frame_index"]: item["context"] for item in result["observations"]["top_frames"]}
        self.assertIsNone(by_index[1]["render_gpu_ms"])
        self.assertEqual(by_index[1]["render_gpu_ms_reported"], 1.4)
        self.assertEqual(by_index[1]["render_gpu_ms_interpretation"], "contradictory_timing_unavailable")

    def test_older_gpu_report_without_capability_metadata_has_unknown_scope(self):
        report = report_with_intervals([12_000, 12_500, 13_000, 14_000])
        report["raw_metrics"]["render_gpu_ms"] = [0.0, 1.4, 0.0, 0.8]
        result = diagnose_dict(report)

        self.assertTrue(result["valid"])
        gpu = result["observations"]["render_gpu_ms_status"]
        self.assertEqual(gpu["scope"], "unknown")
        self.assertIsNone(gpu["timing_available"])
        self.assertEqual(gpu["measured_positive_samples"], 2)

    def test_positive_gpu_timers_are_counted_but_zeros_remain_explicit_sentinels(self):
        report = report_with_intervals([12_000, 12_500, 13_000, 14_000])
        report["raw_metrics"]["render_gpu_ms"] = [0.0, 1.4, 0.0, 0.8]
        result = diagnose_report(report)

        status = result["observations"]["render_gpu_ms_status"]
        self.assertEqual(status["measured_positive_samples"], 2)
        self.assertEqual(status["zero_samples"], 2)
        self.assertEqual(status["interpretation"], "positive_samples_with_zero_sentinels")
        top_by_index = {item["frame_index"]: item["context"] for item in result["observations"]["top_frames"]}
        self.assertEqual(top_by_index[0]["render_gpu_ms_reported"], 0.0)
        self.assertIsNone(top_by_index[0]["render_gpu_ms"])
        self.assertEqual(top_by_index[1]["render_gpu_ms"], 1.4)

    def test_optional_gpu_array_missing_is_reported_as_not_reported(self):
        report = report_with_intervals([12_000, 12_500, 13_000, 14_000])
        del report["raw_metrics"]["render_gpu_ms"]
        result = diagnose_report(report)

        self.assertFalse(result["observations"]["render_gpu_ms_status"]["reported"])
        self.assertEqual(result["observations"]["render_gpu_ms_status"]["interpretation"], "not_reported")
        self.assertEqual(result["observations"]["top_frames"][0]["context"]["render_gpu_ms_interpretation"], "not_reported")

    def test_warning_is_informational_and_error_invalidates_source(self):
        report = report_with_intervals([12_000, 12_500, 13_000, 14_000])
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report_path = root / "run.json"
            log_path = root / "run.log"
            report_path.write_text(json.dumps(report), encoding="utf-8")
            log_path.write_text("WARNING: benign context\n", encoding="utf-8")
            warning_result = diagnose(report_path, log_path)
            log_path.write_text("SHADER ERROR: broken shader\n", encoding="utf-8")
            error_result = diagnose(report_path, log_path)

        self.assertTrue(warning_result["valid"])
        self.assertEqual(warning_result["log_validation"]["counts"]["warning"], 1)
        self.assertIn("Informational", warning_result["log_validation"]["diagnostics"][0]["hint"])
        self.assertFalse(error_result["valid"])
        self.assertEqual(error_result["log_validation"]["counts"]["error"], 1)
        self.assertIn("Shader error", error_result["log_validation"]["diagnostics"][0]["hint"])

    def test_malformed_report_nonfinite_sample_and_raw_length_mismatch_do_not_pass(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report_path = root / "report.json"
            log_path = root / "run.log"
            log_path.write_text("Godot clean\n", encoding="utf-8")

            report_path.write_text("{" * 5000, encoding="utf-8")
            malformed = diagnose(report_path, log_path)
            self.assertFalse(malformed["valid"])
            self.assertTrue(any("malformed" in reason for reason in malformed["validity_reasons"]))

            report = report_with_intervals([12_000, 12_500, 13_000, 14_000])
            report["raw_metrics"]["sim_time_s"][2] = math.inf
            report_path.write_text(json.dumps(report, allow_nan=True), encoding="utf-8")
            nonfinite = diagnose(report_path, log_path)
            self.assertFalse(nonfinite["valid"])
            self.assertTrue(any("non-finite JSON" in reason or "finite" in reason for reason in nonfinite["validity_reasons"]))

            report = report_with_intervals([12_000, 12_500, 13_000, 14_000])
            report["raw_metrics"]["process_time_s"].pop()
            report_path.write_text(json.dumps(report), encoding="utf-8")
            mismatch = diagnose(report_path, log_path)
            self.assertFalse(mismatch["valid"])
            self.assertTrue(any("length must equal frames" in reason for reason in mismatch["validity_reasons"]))

    def test_incomplete_report_cannot_pass(self):
        report = report_with_intervals([12_000, 12_500, 13_000, 14_000])
        report["complete"] = False
        result = diagnose_dict(report)
        self.assertFalse(result["valid"])
        self.assertTrue(any("incomplete" in reason for reason in result["validity_reasons"]))
        self.assertIsNone(result["observations"])

    def test_report_and_log_share_one_bounded_input_budget(self):
        report = report_with_intervals([12_000, 12_500, 13_000, 14_000])
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report_path = root / "run.json"
            log_path = root / "run.log"
            report_path.write_text(json.dumps(report), encoding="utf-8")
            log_path.write_bytes(b"warning payload more than remainder\n")
            cap = report_path.stat().st_size + 4
            result = diagnose(report_path, log_path, max_input_bytes=cap)

        self.assertFalse(result["valid"])
        self.assertTrue(any("combined input exceeds" in error for error in result["log_validation"]["errors"]))
        self.assertLessEqual(result["source"]["combined_input_bytes"], cap + 1)

    def test_malformed_report_bytes_are_charged_before_log_reads(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report_path = root / "bad.json"
            log_path = root / "run.log"
            report_path.write_text("{malformed report}", encoding="utf-8")
            log_path.write_bytes(b"0123456789")
            cap = report_path.stat().st_size + 3
            result = diagnose(report_path, log_path, max_input_bytes=cap)

        self.assertFalse(result["valid"])
        self.assertEqual(result["source"]["combined_input_bytes"], cap + 1)
        self.assertTrue(any("combined input exceeds" in error for error in result["log_validation"]["errors"]))

    def test_non_object_json_bytes_are_charged_before_log_reads(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report_path = root / "array.json"
            log_path = root / "run.log"
            report_path.write_text("[]", encoding="utf-8")
            log_path.write_bytes(b"log")
            result = diagnose(report_path, log_path, max_input_bytes=2)

        self.assertFalse(result["valid"])
        self.assertEqual(result["source"]["combined_input_bytes"], 3)
        self.assertTrue(any("JSON object" in reason for reason in result["validity_reasons"]))
        self.assertTrue(any("combined input exceeds" in error for error in result["log_validation"]["errors"]))

    def test_output_creation_never_replaces_existing_file_or_symlink(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            payload = {"format": "example"}
            existing = root / "existing.json"
            existing.write_text("preserve me", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                write_new_json(existing, payload)
            self.assertEqual(existing.read_text(encoding="utf-8"), "preserve me")

            target = root / "target.json"
            target.write_text("target stays", encoding="utf-8")
            alias = root / "alias.json"
            try:
                alias.symlink_to(target)
            except (OSError, NotImplementedError):
                self.skipTest("symlink creation is unavailable in this environment")
            with self.assertRaises(FileExistsError):
                write_new_json(alias, payload)
            self.assertEqual(target.read_text(encoding="utf-8"), "target stays")

    def test_cli_reports_malformed_input_without_traceback_and_does_not_emit_success(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report_path = root / "bad.json"
            log_path = root / "run.log"
            output_path = root / "diagnosis.json"
            report_path.write_text("not json", encoding="utf-8")
            log_path.write_text("Godot clean\n", encoding="utf-8")
            stdout = io.StringIO()
            stderr = io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = main(["--report", str(report_path), "--log", str(log_path), "--out", str(output_path)])
            self.assertEqual(code, 1)
            self.assertTrue(output_path.exists())
            self.assertFalse(stdout.getvalue().startswith("frame diagnosis: valid"))
            self.assertNotIn("Traceback", stderr.getvalue())

    def test_cli_prints_actionable_percentiles_bursts_frames_and_warning_count(self):
        report = report_with_intervals([16_667, 16_667, 40_000, 16_667])
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report_path = root / "run.json"
            log_path = root / "run.log"
            output_path = root / "diagnosis.json"
            report_path.write_text(json.dumps(report), encoding="utf-8")
            log_path.write_text("WARNING: informational\n", encoding="utf-8")
            stdout = io.StringIO()
            stderr = io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = main(["--report", str(report_path), "--log", str(log_path), "--out", str(output_path)])
            self.assertEqual(code, 0)
            console = stdout.getvalue()
            self.assertIn("p95", console)
            self.assertIn("p99", console)
            self.assertIn("1 bursts", console)
            self.assertIn("1 warnings", console)
            self.assertIn("frame 3 33.334-73.334 ms: 40.000 ms", console)
            self.assertIn("GPU unavailable_or_zero", console)
            self.assertEqual(stderr.getvalue(), "")

    def test_cli_rejects_bad_limits_and_byte_parser_is_finite(self):
        self.assertEqual(parse_byte_limit("64MiB"), 64 * 1024 * 1024)
        with self.assertRaises(argparse.ArgumentTypeError):
            parse_byte_limit("0")
        with self.assertRaises(argparse.ArgumentTypeError):
            parse_byte_limit("2TiB")

    def test_cli_output_path_refuses_existing_file(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report_path = root / "run.json"
            log_path = root / "run.log"
            output_path = root / "existing.json"
            report_path.write_text(json.dumps(report_with_intervals([12_000, 12_500, 13_000, 14_000])), encoding="utf-8")
            log_path.write_text("Godot clean\n", encoding="utf-8")
            output_path.write_text("keep", encoding="utf-8")
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                code = main(["--report", str(report_path), "--log", str(log_path), "--out", str(output_path)])
            self.assertEqual(code, 2)
            self.assertEqual(output_path.read_text(encoding="utf-8"), "keep")
            self.assertNotIn("Traceback", stderr.getvalue())


def diagnose_report(report: dict, *, top: int = 10) -> dict:
    return diagnose_dict(report, top=top)


def diagnose_dict(report: dict, *, top: int = 10) -> dict:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        report_path = root / "report.json"
        log_path = root / "run.log"
        report_path.write_text(json.dumps(report, allow_nan=True), encoding="utf-8")
        log_path.write_text("Godot clean\n", encoding="utf-8")
        return diagnose(report_path, log_path, top=top)


if __name__ == "__main__":
    unittest.main()
