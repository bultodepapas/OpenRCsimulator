from __future__ import annotations

import json
import hashlib
import tempfile
import unittest
from unittest.mock import patch
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


def write_stream_run(directory: Path, name: str, source: dict) -> tuple[Path, list[dict]]:
    """Build the on-disk stream format from a known-valid legacy fixture."""
    report = dict(source)
    report_path = directory / f"{name}.json"
    metrics = source["raw_metrics"]
    count = source["frames"]
    max_frames = count
    report.update(
        format="openrc-frametimes v3", version=3, capture_id="fixture", max_frames=max_frames,
        actual_sample_start_monotonic_usec=source["frame_end_monotonic_usec"][0] - source["frame_wall_usec"][0],
        actual_sample_end_monotonic_usec=source["frame_end_monotonic_usec"][-1],
        sample_endpoints={"first": {key: values[0] for key, values in metrics.items()},
                          "last": {key: values[-1] for key, values in metrics.items()}},
        frame_deltas_s=[], frame_wall_usec=[], frame_end_monotonic_usec=[],
        engine_frame_deltas_s=[], raw_metrics={},
    )
    records = [{"type": "header", "format": "openrc-frame-stream v1", "version": 1,
                "capture_id": "fixture", "chunk_frames": 512, "max_frames": max_frames,
                "max_bytes": 268_435_456, "warmup_s": report["warmup_s"], "sample_s": report["sample_s"]}]
    for start in range(0, count, 512):
        end = min(start + 512, count)
        records.append({"type": "chunk", "sequence": len(records) - 1, "start_frame": start,
                        "frames": end - start, "wall_usec": source["frame_wall_usec"][start:end],
                        "end_usec": source["frame_end_monotonic_usec"][start:end],
                        "engine_delta_s": source["frame_deltas_s"][start:end],
                        "metrics": {key: values[start:end] for key, values in metrics.items()}})
    records.append({"type": "trailer", "complete": True, "failure": "", "chunks": len(records) - 1,
                    "frames": count})
    report["stream"] = {"file": report_path.name + ".frames.jsonl", "chunks": len(records) - 2,
                        "frames": count, "complete": True, "chunk_frames": 512,
                        "max_bytes": 268_435_456, "rejected_frames": 0, "unstored_frames": 0,
                        "write_calls": len(records), "write_total_usec": 0, "write_max_usec": 0,
                        "write_timing_scope": "synthetic fixture"}
    report_path.with_suffix(".log").write_text("Godot clean\n", encoding="utf-8")
    write_stream_fixture(report_path, report, records)
    return report_path, records


def write_stream_fixture(report_path: Path, report: dict, records: list[dict]) -> None:
    payload = b"".join((json.dumps(record, separators=(",", ":"), allow_nan=False) + "\n").encode()
                       for record in records)
    report["stream"].update(bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest())
    report_path.with_name(report["stream"]["file"]).write_bytes(payload)
    report_path.write_text(json.dumps(report, allow_nan=False), encoding="utf-8")


def lake_reflection_settings(
    mode: str,
    *,
    requested: str = "",
    active: bool = False,
    capture_size: list[int] | None = None,
) -> dict:
    return {
        "requested": requested,
        "mode": mode,
        "planar_active_at_report": active,
        "capture_size_at_report": [0, 0] if capture_size is None else capture_size,
    }


def reflection_campaign(settings: list[dict | None]) -> tuple[dict, int]:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        for index, lake_settings in enumerate(settings, start=1):
            report = valid_report()
            if lake_settings is not None:
                report["render_settings"] = {"lake_reflections": lake_settings}
            write_run(root, f"run-{index}", report)
        return summarize_directory(
            root,
            root / "summary.json",
            {**SHORT_POLICY, "minimum_runs": len(settings)},
        )


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

    def test_optional_pacing_configuration_accepts_zero_sixty_and_all_vsync_modes(self):
        for max_fps in (0, 60):
            for vsync_mode in range(4):
                with self.subTest(max_fps=max_fps, vsync_mode=vsync_mode):
                    report = valid_report()
                    report.update(
                        max_fps=max_fps,
                        vsync_mode=vsync_mode,
                        vsync=vsync_mode != 0,
                    )

                    errors, _ = validate_native_report(report)
                    self.assertEqual(errors, [])

    def test_optional_pacing_configuration_rejects_invalid_values(self):
        invalid_values = (
            ("max_fps", True, "max_fps must be a non-negative integer"),
            ("max_fps", 60.0, "max_fps must be a non-negative integer"),
            ("max_fps", "60", "max_fps must be a non-negative integer"),
            ("max_fps", -1, "max_fps must be a non-negative integer"),
            ("vsync_mode", True, "vsync_mode must be an integer from 0 through 3"),
            ("vsync_mode", 1.0, "vsync_mode must be an integer from 0 through 3"),
            ("vsync_mode", "1", "vsync_mode must be an integer from 0 through 3"),
            ("vsync_mode", -1, "vsync_mode must be an integer from 0 through 3"),
            ("vsync_mode", 4, "vsync_mode must be an integer from 0 through 3"),
        )
        for key, value, expected_error in invalid_values:
            with self.subTest(key=key, value=value):
                report = valid_report()
                report[key] = value

                errors, _ = validate_native_report(report)
                self.assertIn(expected_error, errors)

    def test_vsync_boolean_must_match_vsync_mode(self):
        for mode, vsync in ((0, True), (1, False), (2, 0)):
            with self.subTest(mode=mode, vsync=vsync):
                report = valid_report()
                report.update(vsync_mode=mode, vsync=vsync)

                errors, _ = validate_native_report(report)
                self.assertIn("vsync must agree with vsync_mode", errors)

    def test_lake_reflection_report_metadata_accepts_supported_states(self):
        cases = (
            lake_reflection_settings("absent"),
            lake_reflection_settings("probe", requested="planar"),
            lake_reflection_settings("planar", requested="planar"),
            lake_reflection_settings(
                "planar", requested="planar", active=True, capture_size=[640, 360]
            ),
            lake_reflection_settings(
                "planar", requested="planar", capture_size=[640, 360]
            ),
        )
        for settings in cases:
            with self.subTest(settings=settings):
                report = valid_report()
                report["render_settings"] = {"lake_reflections": settings}
                errors, _ = validate_native_report(report)
                self.assertEqual(errors, [])

    def test_malformed_lake_reflection_report_metadata_is_rejected(self):
        malformed = (
            None,
            [],
            {},
            {"requested": None, "mode": "absent", "planar_active_at_report": False,
             "capture_size_at_report": [0, 0]},
            {"requested": " Planar ", "mode": "planar", "planar_active_at_report": False,
             "capture_size_at_report": [0, 0]},
            {"requested": "", "mode": "disabled", "planar_active_at_report": False,
             "capture_size_at_report": [0, 0]},
            {"requested": "", "mode": "probe", "planar_active_at_report": 1,
             "capture_size_at_report": [0, 0]},
            {"requested": "", "mode": "probe", "planar_active_at_report": False,
             "capture_size_at_report": [640, 0]},
            {"requested": "", "mode": "probe", "planar_active_at_report": False,
             "capture_size_at_report": [True, 360]},
            {"requested": "", "mode": "probe", "planar_active_at_report": False,
             "capture_size_at_report": [640]},
            {"requested": "planar", "mode": "probe", "planar_active_at_report": True,
             "capture_size_at_report": [640, 360]},
            {"requested": "planar", "mode": "planar", "planar_active_at_report": True,
             "capture_size_at_report": [0, 0]},
            {"requested": "", "mode": "absent", "planar_active_at_report": False,
             "capture_size_at_report": [640, 360]},
        )
        for settings in malformed:
            with self.subTest(settings=settings):
                report = valid_report()
                report["render_settings"] = {"lake_reflections": settings}
                errors, _ = validate_native_report(report)
                self.assertTrue(errors)

    def test_non_object_render_settings_parent_is_rejected(self):
        for render_settings in (None, [], "invalid", 1):
            with self.subTest(render_settings=render_settings):
                report = valid_report()
                report["render_settings"] = render_settings
                errors, _ = validate_native_report(report)
                self.assertIn("render_settings must be an object", errors)

    def test_missing_lake_reflection_metadata_remains_historical_unknown(self):
        cases = ((False, None), (True, {}))
        for has_render_settings, render_settings in cases:
            with self.subTest(has_render_settings=has_render_settings):
                with tempfile.TemporaryDirectory() as temp_dir:
                    root = Path(temp_dir)
                    report = valid_report()
                    if has_render_settings:
                        report["render_settings"] = render_settings
                    report_path = write_run(root, "run-1", report)
                    summary = summarize_run(report_path, SHORT_POLICY)

                self.assertTrue(summary["collection_valid"])
                self.assertIsNone(summary["lake_reflection_configuration"])

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


class StreamReportTests(unittest.TestCase):
    def test_thirty_minute_equivalent_streams_at_60_and_120_hz(self):
        for hz in (60, 120):
            with self.subTest(hz=hz), tempfile.TemporaryDirectory() as temp_dir:
                count = hz * 1800
                ticks = [(index + 1) * (240 // hz) for index in range(count)]
                source = valid_report(ticks=ticks, warmup_s=10.0, actual_warmup_s=10.0, sample_s=1800.0)
                ends = [2_000_000 + ((index + 1) * 1_000_000 // hz) for index in range(count)]
                wall = [ends[0] - 2_000_000] + [right - left for left, right in zip(ends, ends[1:])]
                ordered = sorted(wall)
                rank = lambda percent: ordered[(count * percent + 99) // 100 - 1] / 1000.0
                source.update(frame_wall_usec=wall, frame_end_monotonic_usec=ends,
                              frame_deltas_s=[value / 1_000_000.0 for value in wall],
                              frame_ms={"p50": rank(50), "p95": rank(95), "p99": rank(99),
                                        "max": ordered[-1] / 1000.0},
                              actual_sample_s=1800.0, wall_seconds=1800.0, seconds=1800.0)
                path, _records = write_stream_run(Path(temp_dir), "run-1", source)
                result = summarize_run(path, DEFAULT_POLICY)
                self.assertTrue(result["collection_valid"], result["collection_reasons"])
                self.assertTrue(result["performance_pass"])
                self.assertEqual(result["stream"]["frames"], count)
                self.assertEqual(result["metrics"]["frame_ms"], source["frame_ms"])

    def test_stream_matches_legacy_analysis_across_chunk_boundaries(self):
        source = sustained_report()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            legacy = summarize_run(write_run(root, "run-legacy", source), DEFAULT_POLICY)
            path, records = write_stream_run(root, "run-stream", source)
            stream = summarize_run(path, DEFAULT_POLICY)
        self.assertGreater(len(records), 3)
        self.assertTrue(stream["collection_valid"], stream["collection_reasons"])
        self.assertTrue(stream["performance_pass"])
        self.assertEqual(stream["metrics"], legacy["metrics"])
        self.assertEqual(stream["stream"]["frames"], source["frames"])
        self.assertEqual(stream["report_format"], "openrc-frametimes v3")

    def test_stream_rejects_bad_sequence_schema_and_continuity(self):
        for fault in ("sequence", "schema", "clock", "endpoint"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as temp_dir:
                path, records = write_stream_run(Path(temp_dir), "run-1", sustained_report())
                report = json.loads(path.read_text(encoding="utf-8"))
                if fault == "sequence":
                    records[2]["sequence"] += 1
                elif fault == "schema":
                    del records[2]["metrics"]["fps_monitor"]
                elif fault == "clock":
                    records[2]["end_usec"][0] += 1
                else:
                    report["sample_endpoints"]["first"]["sim_tick"] += 1
                write_stream_fixture(path, report, records)
                result = summarize_run(path, DEFAULT_POLICY)
                self.assertFalse(result["collection_valid"])
                self.assertFalse(result["performance_pass"])
                self.assertTrue(any("stream" in reason for reason in result["collection_reasons"]))

    def test_stream_requires_complete_intact_trailer_and_hash(self):
        for fault in ("missing-trailer", "truncated-line", "bad-hash", "marked-incomplete", "missing-file"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as temp_dir:
                path, records = write_stream_run(Path(temp_dir), "run-1", valid_report())
                report = json.loads(path.read_text(encoding="utf-8"))
                sidecar = path.with_name(report["stream"]["file"])
                if fault == "missing-trailer":
                    write_stream_fixture(path, report, records[:-1])
                elif fault == "truncated-line":
                    payload = sidecar.read_bytes()[:-1]
                    sidecar.write_bytes(payload)
                    report["stream"].update(bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest())
                    path.write_text(json.dumps(report), encoding="utf-8")
                elif fault == "bad-hash":
                    report["stream"]["sha256"] = "0" * 64
                    path.write_text(json.dumps(report), encoding="utf-8")
                elif fault == "marked-incomplete":
                    report["complete"] = False
                    report["stream"]["complete"] = False
                    path.write_text(json.dumps(report), encoding="utf-8")
                else:
                    sidecar.unlink()
                result = summarize_run(path, SHORT_POLICY)
                self.assertFalse(result["collection_valid"])
                self.assertFalse(result["performance_pass"])
                self.assertTrue(any("stream" in reason for reason in result["collection_reasons"]))

    def test_stream_rejects_path_escape_and_overstated_limits(self):
        for fault in ("path", "max-frames", "max-bytes"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as temp_dir:
                path, _records = write_stream_run(Path(temp_dir), "run-1", valid_report())
                report = json.loads(path.read_text(encoding="utf-8"))
                if fault == "path":
                    report["stream"]["file"] = "../other.jsonl"
                elif fault == "max-frames":
                    report["max_frames"] = 1_000_001
                else:
                    report["stream"]["bytes"] = 268_435_457
                path.write_text(json.dumps(report), encoding="utf-8")
                result = summarize_run(path, SHORT_POLICY)
                self.assertFalse(result["collection_valid"])
                self.assertFalse(result["performance_pass"])

    def test_stream_rejects_duplicate_json_keys_and_false_counters(self):
        for fault in ("duplicate-key", "rejected", "unstored", "write-timing"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as temp_dir:
                path, _records = write_stream_run(Path(temp_dir), "run-1", valid_report())
                report = json.loads(path.read_text(encoding="utf-8"))
                sidecar = path.with_name(report["stream"]["file"])
                if fault == "duplicate-key":
                    payload = sidecar.read_bytes().replace(b'"sequence":0', b'"sequence":0,"sequence":0', 1)
                    sidecar.write_bytes(payload)
                    report["stream"].update(bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest())
                elif fault == "rejected":
                    report["stream"]["rejected_frames"] = 1
                elif fault == "unstored":
                    report["stream"]["unstored_frames"] = 1
                else:
                    report["stream"]["write_calls"] = 0
                path.write_text(json.dumps(report), encoding="utf-8")
                result = summarize_run(path, SHORT_POLICY)
                self.assertFalse(result["collection_valid"])
                self.assertFalse(result["performance_pass"])

    def test_native_summary_bounds_report_and_log_reads(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            path = write_run(root, "run-1", valid_report(), "longer than five bytes")
            with patch(f"{summarize_run.__module__}.MAX_REPORT_BYTES", 5):
                report_result = summarize_run(path, SHORT_POLICY)
            with patch(f"{summarize_run.__module__}.MAX_LOG_BYTES", 5):
                log_result = summarize_run(path, SHORT_POLICY)
        self.assertFalse(report_result["collection_valid"])
        self.assertFalse(log_result["collection_valid"])
        self.assertTrue(any("byte limit" in reason for reason in report_result["collection_reasons"]))
        self.assertTrue(any("byte limit" in reason for reason in log_result["collection_reasons"]))


class NativeRunClassificationTests(unittest.TestCase):
    def test_endpoint_context_is_retained_without_inventing_history(self):
        for paused in (False, True):
            report = valid_report(paused=paused)
            endpoint = {
                "scope": "end of collection only; not pause history",
                "pause_reason": "" if paused else "a previous diagnostic message",
                "holds": ["focus"] if paused else [],
                "crashed": False,
                "window_focused": False,
            }
            report["session_at_report"] = endpoint
            with self.subTest(paused=paused), tempfile.TemporaryDirectory() as temp_dir:
                summary = summarize_run(write_run(Path(temp_dir), "run-1", report), SHORT_POLICY)
            self.assertTrue(summary["collection_valid"])
            self.assertEqual(summary["session_at_report"], endpoint)
            self.assertEqual(summary["active_flight_qualifier"], not paused)
            self.assertEqual(summary["performance_pass"], not paused)

    def test_historical_report_has_unknown_endpoint_context(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            summary = summarize_run(write_run(Path(temp_dir), "run-1", valid_report()), SHORT_POLICY)
        self.assertIsNone(summary["session_at_report"])
        self.assertTrue(summary["performance_pass"])

    def test_malformed_endpoint_context_invalidates_collection(self):
        valid = {"scope": "end of collection", "pause_reason": "", "holds": [],
                 "crashed": False, "window_focused": True}
        cases = [None, [], {}, {**valid, "scope": ""}, {**valid, "pause_reason": False},
                 {**valid, "holds": "focus"}, {**valid, "holds": [1]},
                 {**valid, "crashed": 0}, {**valid, "window_focused": 1}]
        for endpoint in cases:
            report = valid_report()
            report["session_at_report"] = endpoint
            with self.subTest(endpoint=endpoint), tempfile.TemporaryDirectory() as temp_dir:
                summary = summarize_run(write_run(Path(temp_dir), "run-1", report), SHORT_POLICY)
            self.assertFalse(summary["collection_valid"])
            self.assertFalse(summary["performance_pass"])
            self.assertTrue(any("session_at_report" in error for error in summary["collection_reasons"]))

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

    def test_legacy_report_without_pacing_metadata_remains_valid_and_unknown(self):
        report = valid_report()
        report["vsync"] = True
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = write_run(Path(temp_dir), "run-1", report)
            summary = summarize_run(report_path, SHORT_POLICY)

        self.assertTrue(summary["collection_valid"])
        self.assertTrue(summary["performance_pass"])
        self.assertEqual(summary["pacing_configuration"], {"max_fps": None, "vsync_mode": None})

    def test_campaign_requires_three_individually_passing_runs(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report = sustained_report()
            report.update(max_fps=60, vsync_mode=1, vsync=True)
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
        self.assertTrue(three_run_summary["pacing_configuration_consistent"])
        self.assertTrue(three_run_summary["pacing_configuration_complete"])
        self.assertEqual(three_run_status, 0)

    def test_legacy_campaign_with_all_pacing_metadata_missing_stays_numeric_valid(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report = sustained_report()
            report["vsync"] = True
            for index in range(1, 4):
                write_run(root, f"run-{index}", report)

            summary, status = summarize_directory(root, root / "summary.json")

        self.assertEqual(summary["performance_pass_count"], 3)
        self.assertTrue(summary["performance_pass"])
        self.assertTrue(summary["pacing_configuration_consistent"])
        self.assertFalse(summary["pacing_configuration_complete"])
        self.assertEqual(status, 0)

    def test_campaign_rejects_consistent_but_partial_pacing_metadata(self):
        scenarios = ("partial-cap", "partial-mode")
        for scenario in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                for index in range(1, 4):
                    report = sustained_report()
                    report["vsync"] = True
                    if scenario == "partial-cap":
                        report["max_fps"] = 60
                    else:
                        report["vsync_mode"] = 1
                    report_path = write_run(root, f"run-{index}", report)
                    self.assertTrue(summarize_run(report_path, DEFAULT_POLICY)["performance_pass"])

                summary, status = summarize_directory(root, root / "summary.json")

            self.assertEqual(summary["performance_pass_count"], 3)
            self.assertTrue(summary["pacing_configuration_consistent"])
            self.assertFalse(summary["pacing_configuration_complete"])
            self.assertFalse(summary["performance_pass"])
            self.assertEqual(status, 1)

    def test_campaign_refuses_individually_passing_runs_with_mixed_pacing_configuration(self):
        scenarios = (
            ("mixed-cap", [(60, 1), (60, 1), (0, 1)]),
            ("mixed-mode", [(60, 1), (60, 1), (60, 2)]),
            ("mixed-missing", [(60, 1), (60, 1), None]),
        )
        for scenario, configurations in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                for index, configuration in enumerate(configurations, start=1):
                    report = sustained_report()
                    if configuration is None:
                        report["vsync"] = True
                    else:
                        max_fps, vsync_mode = configuration
                        report.update(
                            max_fps=max_fps,
                            vsync_mode=vsync_mode,
                            vsync=vsync_mode != 0,
                        )
                    report_path = write_run(root, f"run-{index}", report)
                    self.assertTrue(summarize_run(report_path, DEFAULT_POLICY)["performance_pass"])

                summary, status = summarize_directory(root, root / "summary.json")

            self.assertEqual(summary["performance_pass_count"], 3)
            self.assertFalse(summary["performance_pass"])
            self.assertFalse(summary["pacing_configuration_consistent"])
            self.assertIn(
                "runs have different or mixed known/unknown FPS caps or VSync modes",
                summary["campaign_reasons"],
            )
            self.assertEqual(status, 1)

    def test_campaign_accepts_homogeneous_installed_lake_reflection_mode(self):
        settings = [
            lake_reflection_settings("probe", requested=requested)
            for requested in ("", "planar", "")
        ]
        summary, status = reflection_campaign(settings)

        self.assertEqual(summary["performance_pass_count"], 3)
        self.assertTrue(summary["performance_pass"])
        self.assertTrue(summary["lake_reflection_configuration_consistent"])
        self.assertTrue(summary["lake_reflection_configuration_complete"])
        self.assertEqual(
            [run["lake_reflection_configuration"] for run in summary["runs"]],
            [{"mode": "probe"}] * 3,
        )
        self.assertEqual(status, 0)

    def test_campaign_rejects_individually_passing_runs_with_mixed_lake_reflection_modes(self):
        settings = [
            lake_reflection_settings("probe"),
            lake_reflection_settings("planar", requested="planar"),
            lake_reflection_settings("planar", requested="planar"),
        ]
        summary, status = reflection_campaign(settings)

        self.assertEqual(summary["performance_pass_count"], 3)
        self.assertFalse(summary["performance_pass"])
        self.assertFalse(summary["lake_reflection_configuration_consistent"])
        self.assertTrue(summary["lake_reflection_configuration_complete"])
        self.assertIn(
            "runs have different or mixed known/unknown installed lake reflection modes",
            summary["campaign_reasons"],
        )
        self.assertEqual(status, 1)

    def test_campaign_rejects_mixed_known_and_historical_unknown_lake_reflection_modes(self):
        settings = [lake_reflection_settings("probe"), None, lake_reflection_settings("probe")]
        summary, status = reflection_campaign(settings)

        self.assertEqual(summary["performance_pass_count"], 3)
        self.assertFalse(summary["performance_pass"])
        self.assertFalse(summary["lake_reflection_configuration_consistent"])
        self.assertFalse(summary["lake_reflection_configuration_complete"])
        self.assertIn(
            "runs have different or mixed known/unknown installed lake reflection modes",
            summary["campaign_reasons"],
        )
        self.assertEqual(status, 1)

    def test_all_historical_unknown_lake_reflection_metadata_remains_numerically_valid(self):
        summary, status = reflection_campaign([None, None, None])

        self.assertEqual(summary["performance_pass_count"], 3)
        self.assertTrue(summary["performance_pass"])
        self.assertTrue(summary["lake_reflection_configuration_consistent"])
        self.assertFalse(summary["lake_reflection_configuration_complete"])
        self.assertEqual(
            [run["lake_reflection_configuration"] for run in summary["runs"]],
            [None] * 3,
        )
        self.assertEqual(status, 0)

    def test_same_planar_mode_allows_active_and_inactive_report_snapshots(self):
        settings = [
            lake_reflection_settings(
                "planar", requested="planar", active=True, capture_size=[640, 360]
            ),
            lake_reflection_settings(
                "planar", requested="planar", active=False, capture_size=[640, 360]
            ),
            lake_reflection_settings("planar", requested="planar"),
        ]
        summary, status = reflection_campaign(settings)

        self.assertEqual(summary["performance_pass_count"], 3)
        self.assertTrue(summary["performance_pass"])
        self.assertTrue(summary["lake_reflection_configuration_consistent"])
        self.assertTrue(summary["lake_reflection_configuration_complete"])
        self.assertEqual(
            [run["lake_reflection_configuration"] for run in summary["runs"]],
            [{"mode": "planar"}] * 3,
        )
        self.assertEqual(status, 0)

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
