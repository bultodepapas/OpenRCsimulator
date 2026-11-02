"""Tests for bounded Perfetto JSON export of OpenRC captures."""
from __future__ import annotations

import contextlib
import copy
import hashlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from perfetto_export import (
    BudgetError,
    SourceError,
    build_trace,
    main,
    read_sources,
    _write_new_trace,
)
from research.performance.session_baseline import percentile_nearest_rank
from research.performance.test_native_summary import valid_report, write_stream_fixture, write_stream_run


UNIX_BASE = 1_700_000_000_000_000


def frame_report(*, capture_id: str | None = None, clock: dict | None = None,
                 complete: bool = True, raw_extra: dict | None = None,
                 gpu_values: list[float] | None = None) -> dict:
    wall = [20_000, 100_000]
    deltas = [value / 1_000_000.0 for value in wall]
    times_ms = [value / 1000.0 for value in wall]
    raw_metrics = {
        "sim_tick": [240.0, 243.0],
        "sim_time_s": [1.0, 1.0125],
        "fps_monitor": [50.0, 10.0],
    }
    if gpu_values is not None:
        raw_metrics["render_gpu_ms"] = gpu_values
    if raw_extra:
        raw_metrics.update(raw_extra)
    report = {
        "format": "openrc-frametimes v2",
        "version": 2,
        "complete": complete,
        "failure": "retention limit reached" if not complete else "",
        "route": "live-input",
        "case_id": "hitch-test",
        "aircraft_id": "test-aircraft",
        "preset": "test-preset",
        "backend": "gl_compatibility",
        "input_enabled": True,
        "frames": 2,
        "frame_deltas_s": deltas,
        "frame_wall_usec": wall,
        "frame_end_monotonic_usec": [1_020_000, 1_120_000],
        "frame_ms": {
            f"p{percentile}": percentile_nearest_rank(times_ms, percentile)
            for percentile in (50, 95, 99)
        } | {"max": max(times_ms)},
        "sample_s": 0.02,
        "warmup_s": 0.0,
        "actual_sample_s": sum(deltas),
        "actual_warmup_s": 0.0,
        "wall_seconds": sum(deltas),
        "seconds": sum(deltas),
        "raw_metrics": raw_metrics,
        "measured_simulation": {
            "scope": "first to last frame sample",
            "start_tick": 240,
            "end_tick": 243,
            "ticks": 3,
            "start_time_s": 1.0,
            "end_time_s": 1.0125,
        },
        "simulation": {
            "physics_ticks_per_second": 240,
            "physics_enabled": True,
            "paused": False,
            "fault": "",
        },
    }
    if capture_id is not None:
        report["capture_id"] = capture_id
    if clock is not None:
        report["clock"] = clock
    return report


def frame_clock(*, offset_drift_usec: int = 0) -> dict:
    return {
        "source": "godot_ticks_usec",
        "origin_usec": 0,
        "start": {
            "monotonic_usec": 900_000,
            "unix_usec": UNIX_BASE,
            "uncertainty_usec": 1_000,
        },
        "end": {
            "monotonic_usec": 1_200_000,
            "unix_usec": UNIX_BASE + 300_000 + offset_drift_usec,
            "uncertainty_usec": 2_000,
        },
    }


def resource_clock(*, offset_drift_usec: int = 0) -> dict:
    return {
        "source": "python_perf_counter",
        "origin_usec": 50_000,
        "start": {
            "monotonic_usec": 50_000,
            "unix_usec": UNIX_BASE + 100_000,
            "uncertainty_usec": 500,
        },
        "end": {
            "monotonic_usec": 150_000,
            "unix_usec": UNIX_BASE + 200_000 + offset_drift_usec,
            "uncertainty_usec": 1_000,
        },
    }


def resource_report(*, capture_id: str | None = None, clock: dict | None = None,
                    coverage: str = "sampled", elapsed: tuple[float, ...] = (0.0, 0.1),
                    volume_path: str | None = None) -> dict:
    samples = []
    for index, elapsed_seconds in enumerate(elapsed):
        sample = {
            "elapsed_seconds": elapsed_seconds,
            "rss_bytes": 1_000_000 + index * 500_000,
            "vms_bytes": 2_000_000,
            "cpu_user_seconds": index * 0.05,
            "cpu_system_seconds": index * 0.01,
            "cpu_percent": None if index == 0 else 60.0,
            "num_threads": None,
            "io_read_bytes": 0,
            "io_write_bytes": index * 1024,
            "io_read_count": 0,
            "io_write_count": index,
            "virtual_memory_total_bytes": 16_000_000_000,
            "virtual_memory_available_bytes": 8_000_000_000 - index * 1000,
            "virtual_memory_percent": 50.0,
            "swap_used_bytes": 0,
            "swap_total_bytes": 2_000_000_000,
            "volumes": [],
            "field_status": {
                "rss_bytes": "ok",
                "vms_bytes": "ok",
                "cpu_user_seconds": "ok",
                "cpu_system_seconds": "ok",
                "cpu_percent": "insufficient_samples" if index == 0 else "ok",
                "num_threads": "disabled",
                "io_read_bytes": "ok",
                "io_write_bytes": "ok",
                "io_read_count": "ok",
                "io_write_count": "ok",
                "virtual_memory_total_bytes": "ok",
                "virtual_memory_available_bytes": "ok",
                "virtual_memory_percent": "ok",
                "swap_used_bytes": "ok",
                "swap_total_bytes": "ok",
            },
        }
        if volume_path is not None:
            sample["volumes"] = [{
                "path": volume_path,
                "free_bytes": 5_000_000 - index * 1000,
                "total_bytes": 10_000_000,
            }]
            sample["field_status"].update({
                "volume[0].free_bytes": "ok",
                "volume[0].total_bytes": "ok",
            })
        samples.append(sample)
    report = {
        "format": "openrc-resource-samples v1",
        "platform": "test",
        "coverage": coverage,
        "measurement_status": "ok" if coverage == "sampled" else "partial",
        "sample_count": len(samples),
        "error_count": 0,
        "capped": coverage == "capped",
        "stop_reason": "caller_finished",
        "errors": [],
        "errors_truncated": False,
        "samples": samples,
    }
    if capture_id is not None:
        report["capture_id"] = capture_id
    if clock is not None:
        report["clock"] = clock
    return report


class PerfettoExportTests(unittest.TestCase):
    def test_combined_frames_and_resources_align_wall_hitch_as_x_slice(self):
        frames = frame_report(capture_id="capture-1", clock=frame_clock(), gpu_values=[0.0, 2.0])
        frames["frame_diagnostics"] = {"render_timing_available": True, "viewport_scope": "root"}
        resources = resource_report(capture_id="capture-1", clock=resource_clock(), volume_path="C:/")

        events, partial = build_trace(frames=frames, resources=resources)
        self.assertFalse(partial)
        slices = [event for event in events if event.get("ph") == "X"]
        self.assertEqual([(event["ts"], event["dur"]) for event in slices], [(0, 20_000), (20_000, 100_000)])
        rss = [event for event in events if event.get("name") == "resource.process.rss_bytes [bytes]"]
        self.assertEqual([event["ts"] for event in rss], [0, 100_000])
        gpu = [event for event in events if "render_gpu_ms" in event.get("name", "")]
        self.assertEqual([(event["ts"], event["args"]["value"]) for event in gpu], [(120_000, 2.0)])
        metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
        self.assertEqual(metadata["clock"]["mode"], "aligned_utc")
        self.assertTrue(metadata["complete"])
        self.assertFalse(metadata["partial"])
        self.assertIn("[bytes]", next(event["name"] for event in events if event.get("name", "").endswith("free_bytes [bytes]")))

    def test_single_old_format_uses_relative_timeline_and_zero_gpu_is_omitted(self):
        events, partial = build_trace(frames=frame_report(gpu_values=[0.0, 0.0]))
        self.assertFalse(partial)
        slices = [event for event in events if event.get("ph") == "X"]
        self.assertEqual([event["ts"] for event in slices], [0, 20_000])
        self.assertFalse(any(event.get("ph") == "C" and "render_gpu_ms" in event.get("name", "") for event in events))
        metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
        self.assertEqual(metadata["sources"]["frames"]["gpu_timer"]["interpretation"], "unavailable_or_zero")
        self.assertEqual(metadata["clock"]["mode"], "relative_frame_timeline")

    def test_empty_frame_capture_id_is_allowed_only_for_single_source_trace(self):
        events, partial = build_trace(frames=frame_report(capture_id=""))
        self.assertFalse(partial)
        metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
        self.assertIsNone(metadata["capture_id"])
        with self.assertRaisesRegex(SourceError, "same non-empty capture_id"):
            build_trace(
                frames=frame_report(capture_id="", clock=frame_clock()),
                resources=resource_report(capture_id="other", clock=resource_clock()),
            )

    def test_invalid_observer_samples_are_omitted_and_mark_partial(self):
        report = frame_report(raw_extra={"render_cpu_ms": [2.5, 0.0], "invalid_value_count": [0, 1]})
        events, partial = build_trace(frames=report)
        self.assertTrue(partial)
        cpu = [event for event in events if event.get("name") == "frame.render_cpu_ms [ms]"]
        self.assertEqual([(event["ts"], event["args"]["value"]) for event in cpu], [(20_000, 2.5)])
        metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
        frame_metadata = metadata["sources"]["frames"]
        self.assertFalse(metadata["complete"])
        self.assertTrue(metadata["partial"])
        self.assertEqual(frame_metadata["invalid_observer_frame_count"], 1)
        self.assertEqual(frame_metadata["observer_counter_samples_omitted"], 1)

    def test_unknown_frame_metrics_are_reported_but_not_exported(self):
        events, _partial = build_trace(frames=frame_report(raw_extra={"future_metric": [5, 6]}))
        self.assertFalse(any("future_metric" in event.get("name", "") for event in events))
        metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
        self.assertEqual(metadata["sources"]["frames"]["unknown_metric_names"], ["future_metric"])

    def test_short_capped_prefix_preserves_duration_without_weakening_integrity(self):
        report = frame_report(complete=False)
        report["sample_s"] = 10.0
        events, partial = build_trace(frames=report)
        self.assertTrue(partial)
        self.assertEqual(sum(e["dur"] for e in events if e["ph"] == "X"), 120000)
        report["complete"] = True
        report["failure"] = ""
        with self.assertRaisesRegex(SourceError, "shorter than sample_s"):
            build_trace(frames=report)
        report["complete"] = False
        report["failure"] = "retention limit"
        report["frame_wall_usec"][1] += 1
        with self.assertRaises(SourceError):
            build_trace(frames=report)

    def test_mismatched_ids_and_missing_combined_clock_are_rejected(self):
        with self.assertRaisesRegex(SourceError, "same non-empty capture_id"):
            build_trace(
                frames=frame_report(capture_id="one", clock=frame_clock()),
                resources=resource_report(capture_id="two", clock=resource_clock()),
            )
        with self.assertRaisesRegex(SourceError, "require valid clock anchors"):
            build_trace(frames=frame_report(capture_id="same"), resources=resource_report(capture_id="same"))

    def test_clock_offset_drift_over_allowance_is_rejected(self):
        with self.assertRaisesRegex(SourceError, "anchor drift exceeds allowance"):
            build_trace(
                frames=frame_report(capture_id="same", clock=frame_clock()),
                resources=resource_report(capture_id="same", clock=resource_clock(offset_drift_usec=200_000)),
            )

    def test_combined_source_samples_must_fit_their_monotonic_anchor_bounds(self):
        shifted_resource_clock = resource_clock()
        shifted_resource_clock["origin_usec"] = 1_000_000
        with self.assertRaisesRegex(SourceError, "fall outside their monotonic clock anchors"):
            build_trace(
                frames=frame_report(capture_id="same", clock=frame_clock()),
                resources=resource_report(capture_id="same", clock=shifted_resource_clock),
            )

    def test_partial_frame_prefix_and_capped_resource_prefix_are_exported_as_partial(self):
        events, partial = build_trace(
            frames=frame_report(capture_id="same", clock=frame_clock(), complete=False),
            resources=resource_report(capture_id="same", clock=resource_clock(), coverage="capped"),
        )
        self.assertTrue(partial)
        self.assertEqual(len([event for event in events if event.get("ph") == "X"]), 2)
        metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
        self.assertEqual(metadata["sources"]["frames"]["complete"], False)
        self.assertEqual(metadata["sources"]["resources"]["coverage"], "capped")

    def test_resource_unknown_values_stay_absent_and_missing_or_invalid_values_reject(self):
        report = resource_report()
        for sample in report["samples"]:
            sample["vms_bytes"] = None
            sample["field_status"]["vms_bytes"] = "unsupported"
        events, _partial = build_trace(resources=report)
        self.assertFalse(any(event.get("name") == "resource.process.vms_bytes [bytes]" for event in events))
        bad_missing = resource_report()
        del bad_missing["samples"][0]["field_status"]["rss_bytes"]
        with self.assertRaisesRegex(SourceError, "missing rss_bytes or its field_status"):
            build_trace(resources=bad_missing)
        bad_nonfinite = resource_report()
        bad_nonfinite["samples"][0]["rss_bytes"] = float("inf")
        with self.assertRaisesRegex(SourceError, "finite and non-negative"):
            build_trace(resources=bad_nonfinite)
        bad_status_value = resource_report()
        bad_status_value["samples"][0]["vms_bytes"] = 1
        bad_status_value["samples"][0]["field_status"]["vms_bytes"] = "unsupported"
        with self.assertRaisesRegex(SourceError, "must be null when status"):
            build_trace(resources=bad_status_value)
        partial_status = resource_report()
        for sample in partial_status["samples"]:
            sample["vms_bytes"] = None
            sample["field_status"]["vms_bytes"] = "unsupported"
        events, partial = build_trace(resources=partial_status)
        self.assertTrue(partial)
        metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
        self.assertIn("vms_bytes", metadata["sources"]["resources"]["partial_fields"])

    def test_required_coverage_is_preserved_without_relabeling_legacy_partial(self):
        report = resource_report()
        report["required_coverage"] = "complete"
        for sample in report["samples"]:
            sample["io_read_bytes"] = None
            sample["field_status"]["io_read_bytes"] = "unsupported"
        events, partial = build_trace(resources=report)
        self.assertTrue(partial)
        metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
        self.assertEqual(metadata["sources"]["resources"]["required_coverage"], "complete")
        self.assertFalse(metadata["sources"]["resources"]["required_coverage_validated"])
        report["required_coverage"] = "invented"
        with self.assertRaisesRegex(SourceError, "required_coverage is unsupported"):
            build_trace(resources=report)

    def test_required_channel_claims_are_checked_against_samples_and_stop(self):
        report = resource_report()
        fields = ("rss_bytes", "cpu_user_seconds", "cpu_system_seconds", "virtual_memory_available_bytes")
        report["required_coverage"] = "complete"
        report["required_field_counts"] = {field: 2 for field in fields}
        report["summary"] = {"counter_resets": []}
        events, partial = build_trace(resources=report)
        self.assertFalse(partial)
        metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
        self.assertTrue(metadata["sources"]["resources"]["required_coverage_validated"])
        inconsistent = copy.deepcopy(report)
        inconsistent["required_field_counts"]["rss_bytes"] = 1
        with self.assertRaisesRegex(SourceError, "do not match sample statuses"):
            build_trace(resources=inconsistent)
        missing = copy.deepcopy(report)
        missing["samples"][1]["rss_bytes"] = None
        missing["samples"][1]["field_status"]["rss_bytes"] = "denied"
        missing["required_field_counts"]["rss_bytes"] = 1
        with self.assertRaisesRegex(SourceError, "expected partial"):
            build_trace(resources=missing)
        stopped = copy.deepcopy(report)
        stopped["stop_reason"] = "process_exited"
        with self.assertRaisesRegex(SourceError, "expected partial"):
            build_trace(resources=stopped)
        stopped["stop_reason"] = "sample_limit"
        with self.assertRaisesRegex(SourceError, "cap and stop reason disagree"):
            build_trace(resources=stopped)
        reset = copy.deepcopy(report)
        reset["summary"]["counter_resets"] = ["cpu_user_seconds"]
        with self.assertRaisesRegex(SourceError, "expected partial"):
            build_trace(resources=reset)

    def test_v3_stream_rejects_bad_sequences_nonfinite_values_and_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = valid_report(ticks=[240 + 3 * index for index in range(600)])
            frames, records = write_stream_run(root, "frames", source)
            report = json.loads(frames.read_text(encoding="utf-8"))
            for label, mutate in (
                    ("duplicate", lambda rows: rows[2].update(sequence=0)),
                    ("reorder", lambda rows: rows.__setitem__(slice(1, 3), [rows[2], rows[1]])),
                    ("missing", lambda rows: rows.pop(1)),
                    ("nonfinite", lambda rows: rows[1]["metrics"]["fps_monitor"].__setitem__(0, float("nan"))),
                    ("incomplete", lambda rows: rows[-1].update(complete=False)),
            ):
                with self.subTest(case=label):
                    variant = copy.deepcopy(records)
                    mutate(variant)
                    if label == "nonfinite":
                        payload = b"".join((json.dumps(record, separators=(",", ":"), allow_nan=True) + "\n").encode()
                                           for record in variant)
                        report["stream"].update(bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest())
                        frames.with_name(report["stream"]["file"]).write_bytes(payload)
                        frames.write_text(json.dumps(report), encoding="utf-8")
                    else:
                        write_stream_fixture(frames, report, variant)
                    with self.assertRaises(SourceError):
                        read_sources(frames_path=frames)
            write_stream_fixture(frames, report, records)
            report["version"] = 4
            frames.write_text(json.dumps(report), encoding="utf-8")
            with self.assertRaisesRegex(SourceError, "version must be integer 3"):
                read_sources(frames_path=frames)
            report["version"] = 3
            report["stream"]["complete"] = False
            frames.write_text(json.dumps(report), encoding="utf-8")
            with self.assertRaisesRegex(SourceError, "marked incomplete"):
                read_sources(frames_path=frames)

    def test_selected_frames_keep_original_indices_and_single_source_clock(self):
        report = frame_report(clock=frame_clock(), raw_extra={"draw_calls": [10, 11]})
        events, partial = build_trace(frames=report, start_frame=1, end_frame=2,
                                      selected_frame_metrics=["draw_calls"])
        self.assertFalse(partial)
        metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
        self.assertEqual(metadata["clock"]["frame_clock"]["start"]["uncertainty_usec"], 1000)
        self.assertFalse(metadata["complete"])
        self.assertTrue(metadata["source_data_complete"])
        self.assertEqual(metadata["sources"]["frames"]["selection"]["start_monotonic_usec"], 1_020_000)
        frames = [event for event in events if event.get("ph") == "X"]
        self.assertEqual([(event["args"]["frame_index"], event["ts"], event["dur"]) for event in frames],
                         [(1, 20_000, 100_000)])
        with self.assertRaisesRegex(BudgetError, "start < end"):
            build_trace(frames=report, start_frame=2, end_frame=2)
        with self.assertRaisesRegex(BudgetError, "distinct known metrics"):
            build_trace(frames=report, selected_frame_metrics=["draw_calls", "draw_calls"])
        with self.assertRaisesRegex(BudgetError, "requires a frame source"):
            build_trace(resources=resource_report(), start_frame=0)

    def test_v3_cli_selection_and_late_output_collision(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            frames, _records = write_stream_run(root, "frames", frame_report(clock=frame_clock()))
            output = root / "timeline.json"
            sidecar = frames.with_name(frames.name + ".frames.jsonl")
            with self.assertRaisesRegex(BudgetError, "combined source input"):
                read_sources(frames_path=frames,
                             max_input_bytes=frames.stat().st_size + sidecar.stat().st_size - 1)
            arguments = ["--frames", str(frames), "--out", str(output),
                         "--start-frame", "1", "--end-frame", "2", "--frame-metric", "sim_tick"]
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                status = main(arguments)
            self.assertEqual(status, 0)
            events = json.loads(output.read_text(encoding="utf-8"))
            metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
            self.assertEqual(metadata["sources"]["frames"]["format"], "openrc-frametimes v3")
            self.assertFalse(metadata["full_session_timeline"])
            self.assertEqual(metadata["sources"]["frames"]["selection"]["end_frame_exclusive"], 2)
            output.write_text("preserve existing trace", encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                status = main(arguments)
            self.assertEqual(status, 2)
            self.assertEqual(output.read_text(encoding="utf-8"), "preserve existing trace")
            no_output = root / "over-cap.json"
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                status = main(["--frames", str(frames), "--out", str(no_output), "--max-events", "2"])
            self.assertEqual(status, 2)
            self.assertFalse(no_output.exists())

    def test_v3_selection_preserves_resource_scope_and_clock_uncertainty(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            frames, _records = write_stream_run(root, "combined", frame_report(clock=frame_clock()))
            resources = root / "resources.json"
            resources.write_text(json.dumps(resource_report(capture_id="fixture", clock=resource_clock())),
                                 encoding="utf-8")
            loaded_frames, loaded_resources = read_sources(frames_path=frames, resources_path=resources)
            events, partial = build_trace(frames=loaded_frames, resources=loaded_resources,
                                          start_frame=1, end_frame=2, selected_frame_metrics=["sim_tick"])
            self.assertFalse(partial)
            metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
            self.assertEqual(metadata["clock"]["mode"], "aligned_utc")
            self.assertEqual(metadata["clock"]["frame_clock"]["start"]["uncertainty_usec"], 1000)
            self.assertFalse(metadata["clock"]["resource_timestamps_bracket_full_frame_window"])
            self.assertFalse(metadata["clock"]["resource_timestamps_bracket_selected_frame_window"])
            self.assertEqual(metadata["sources"]["frames"]["selection"]["resource_scope"],
                             "all retained resource samples")
            rss = [event for event in events if event.get("name") == "resource.process.rss_bytes [bytes]"]
            self.assertEqual([event["ts"] for event in rss], [0, 100_000])

    @unittest.skipIf(os.name == "nt", "Windows does not permit replacing an open output file")
    def test_failed_output_does_not_remove_an_unrelated_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "timeline.json"

            def swap_and_fail(*_args, **_kwargs):
                output.rename(root / "displaced-partial.json")
                output.write_text("replacement", encoding="utf-8")
                raise OSError("injected write failure")

            with mock.patch("perfetto_export.json.dump", side_effect=swap_and_fail):
                with self.assertRaises(BudgetError):
                    _write_new_trace(output, [])
            self.assertEqual(output.read_text(encoding="utf-8"), "replacement")

    def test_resource_elapsed_time_must_be_finite_and_strictly_increasing(self):
        with self.assertRaisesRegex(SourceError, "strictly increasing"):
            build_trace(resources=resource_report(elapsed=(0.0, 0.0)))
        with self.assertRaisesRegex(SourceError, "finite and non-negative"):
            build_trace(resources=resource_report(elapsed=(0.0, float("nan"))))

    def test_resource_error_codes_are_preserved_in_partial_metadata(self):
        report = resource_report(coverage="partial")
        report["measurement_status"] = "partial"
        report["error_count"] = 1
        report["errors"] = [{"code": "counter_reset", "field": "io_write_bytes", "message": "counter decreased"}]
        events, partial = build_trace(resources=report)
        self.assertTrue(partial)
        metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
        self.assertFalse(metadata["complete"])
        self.assertTrue(metadata["partial"])
        self.assertIn("resource counter_reset io_write_bytes: counter decreased", metadata["source_issues"])

    def test_known_negative_frame_metric_is_rejected(self):
        with self.assertRaisesRegex(SourceError, "raw_metrics.draw_calls\\[1\\] must be non-negative"):
            build_trace(frames=frame_report(raw_extra={"draw_calls": [10, -1]}))

    def test_sample_and_event_caps_are_checked_before_output(self):
        frames = frame_report()
        frames["frames"] = 120_001
        with self.assertRaisesRegex(SourceError, "frames must be an integer"):
            build_trace(frames=frames)
        resources = resource_report()
        resources["samples"] = [resources["samples"][0]] * 10_001
        resources["sample_count"] = 10_001
        with self.assertRaisesRegex(SourceError, "at most 10000"):
            build_trace(resources=resources)
        with self.assertRaises(BudgetError):
            build_trace(frames=frame_report(), max_events=2)

    def test_input_limit_is_aggregate_and_malformed_nonfinite_json_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            frames_path = root / "frames.json"
            resources_path = root / "resources.json"
            frames_path.write_text(json.dumps(frame_report()), encoding="utf-8")
            resources_path.write_text(json.dumps(resource_report()), encoding="utf-8")
            total = frames_path.stat().st_size + resources_path.stat().st_size
            with self.assertRaises(BudgetError):
                read_sources(frames_path=frames_path, resources_path=resources_path, max_input_bytes=total - 1)
            frames_path.write_text('{"bad": NaN}', encoding="utf-8")
            with self.assertRaisesRegex(SourceError, "non-finite JSON value"):
                read_sources(frames_path=frames_path)
            with self.assertRaisesRegex(SourceError, "regular file"):
                read_sources(frames_path=root)

    def test_partial_cli_writes_prefix_and_returns_one_without_overwriting(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "frames.json"
            output = root / "trace.json"
            source.write_text(json.dumps(frame_report(complete=False)), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                status = main(["--frames", str(source), "--out", str(output)])
            self.assertEqual(status, 1)
            self.assertTrue(output.is_file())
            self.assertEqual(len([item for item in json.loads(output.read_text(encoding="utf-8")) if item.get("ph") == "X"]), 2)
            output.write_text("keep", encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                status = main(["--frames", str(source), "--out", str(output)])
            self.assertEqual(status, 2)
            self.assertEqual(output.read_text(encoding="utf-8"), "keep")

    def test_invalid_source_and_output_failure_leave_no_trace(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "bad.json"
            output = root / "trace.json"
            source.write_text(json.dumps({"format": "old-format"}), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                status = main(["--frames", str(source), "--out", str(output)])
            self.assertEqual(status, 1)
            self.assertFalse(output.exists())
            valid = root / "valid.json"
            valid.write_text(json.dumps(frame_report()), encoding="utf-8")
            missing_parent = root / "missing" / "trace.json"
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                status = main(["--frames", str(valid), "--out", str(missing_parent)])
            self.assertEqual(status, 2)
            self.assertFalse(missing_parent.exists())


if __name__ == "__main__":
    unittest.main()
