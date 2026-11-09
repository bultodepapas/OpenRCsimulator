from __future__ import annotations

import json
import hashlib
import contextlib
import copy
import io
import os
import subprocess
import tempfile
import unittest
import uuid
from unittest.mock import patch
from pathlib import Path

try:
    from .native_summary import (
        BENCHMARK_FORCED_OPTIONS,
        BENCHMARK_PROVENANCE_SOURCES,
        BENCHMARK_REQUIRED_SOURCES,
        BENCHMARK_VIOLATIONS,
        DEFAULT_POLICY,
        active_flight_reasons,
        duration_gate,
        main,
        summarize_directory,
        summarize_run,
        validate_native_report,
    )
except ImportError:  # Also support direct execution from this directory.
    from native_summary import (
        BENCHMARK_FORCED_OPTIONS,
        BENCHMARK_PROVENANCE_SOURCES,
        BENCHMARK_REQUIRED_SOURCES,
        BENCHMARK_VIOLATIONS,
        DEFAULT_POLICY,
        active_flight_reasons,
        duration_gate,
        main,
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
        "display_server": "fixture-native",
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
            "render_frames_drawn": [float(100 + index) for index in range(frame_count)],
            "render_interval_draws": [1.0] * frame_count,
            "render_interval_counter_reset": [0.0] * frame_count,
            "render_window_drawable": [1.0] * frame_count,
            "render_counter_resets": [0.0] * frame_count,
            "render_no_draw_intervals": [0.0] * frame_count,
            "render_undrawable_samples": [0.0] * frame_count,
        },
        "render_progress": {
            "status": "observed", "sample_intervals": frame_count, "frames_drawn_at_start": 99,
            "frames_drawn_first": 100, "frames_drawn_last": 100 + frame_count - 1,
            "frames_drawn_delta": frame_count, "undrawable_samples": 0, "counter_resets": 0,
            "no_draw_intervals": 0,
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
    capture_id = source.get("capture_id", "fixture")
    report.update(
        format="openrc-frametimes v3", version=3, capture_id=capture_id, max_frames=max_frames,
        actual_sample_start_monotonic_usec=source["frame_end_monotonic_usec"][0] - source["frame_wall_usec"][0],
        actual_sample_end_monotonic_usec=source["frame_end_monotonic_usec"][-1],
        sample_endpoints={"first": {key: values[0] for key, values in metrics.items()},
                          "last": {key: values[-1] for key, values in metrics.items()}},
        frame_deltas_s=[], frame_wall_usec=[], frame_end_monotonic_usec=[],
        engine_frame_deltas_s=[], raw_metrics={},
    )
    records = [{"type": "header", "format": "openrc-frame-stream v1", "version": 1,
                "capture_id": capture_id, "chunk_frames": 512, "max_frames": max_frames,
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


def render_snapshot(scale: float = 1.0, msaa: int = 2) -> dict:
    snapshot = {
        "backend": "gl_compatibility", "driver": "opengl3", "scaling_3d_mode": 0,
        "scaling_3d_mode_constant": "SCALING_3D_MODE_BILINEAR", "provider_mode_id": 0,
        "scaling_3d_scale": scale, "msaa_3d": msaa,
        "reconstruction": {"requested": "native", "requested_provider": "native", "selected": "native",
                           "effective": "native", "provider": "native", "effective_provider": "native",
                           "execution_status": "policy_selected", "provider_available": True,
                           "fallback": False, "fallback_reason": "", "temporal": False,
                           "scaling_3d_mode": 0, "scale": scale, "msaa_3d": msaa},
    }
    set_snapshot_dimensions(snapshot, (1920, 1080))
    return snapshot


def set_snapshot_dimensions(snapshot: dict, window: tuple[int, int], *,
                            visible: tuple[int, int] | None = None, output: tuple[int, int] | None = None) -> None:
    visible = window if visible is None else visible
    output = window if output is None else output
    snapshot.update(dimension_observation_scope="per_frame_viewport_estimate_v1",
                    window_size_property=list(window), visible_rect_size=list(visible),
                    output_size=list(output), output_size_scope="viewport_render_target_estimate_v1",
                    nominal_3d_size=[max(1, int(value * snapshot["scaling_3d_scale"])) for value in output],
                    nominal_3d_size_scope="scaled_viewport_estimate_not_sdk_execution")


def frame_dimensions(snapshot: dict) -> dict:
    return {"logical_canvas_size": copy.deepcopy(snapshot["visible_rect_size"]),
            **{key: copy.deepcopy(snapshot[key]) for key in
               ("output_size", "output_size_scope", "nominal_3d_size", "nominal_3d_size_scope")}}


def set_render_observation(receipt: dict, report: dict, scale: float = 1.0, msaa: int = 2) -> None:
    snapshot = render_snapshot(scale, msaa)
    receipt["scenario"]["effective_render"] = {
        "start": copy.deepcopy(snapshot), "end": copy.deepcopy(snapshot), "stable": True,
        "samples": report["frames"] + 1, "observed_frame_count": report["frames"],
        "first_frame_bracketed": True, "contiguous": True, "seal_observed": True,
        "seal_reuses_last_frame": False,
    }
    report["rendering_driver"] = snapshot["driver"]
    report["render_settings"] = {key: copy.deepcopy(snapshot[key])
                                 for key in ("scaling_3d_mode", "scaling_3d_scale", "msaa_3d", "reconstruction")}
    report["render_settings"]["reconstruction"].update(frame_dimensions(snapshot))


def set_auto_native_observation(receipt: dict, report: dict, size: tuple[int, int] = (1920, 1080)) -> None:
    set_render_observation(receipt, report)
    receipt["scenario"]["render_override"] = {"reconstruction": "auto"}
    observation = receipt["scenario"]["effective_render"]
    for endpoint in ("start", "end"):
        snapshot = observation[endpoint]
        snapshot["reconstruction"].update(requested="auto", auto_selected="native", auto_output_size=list(size),
                                          auto_output_size_scope="viewport_render_target_estimate_v1")
        set_snapshot_dimensions(snapshot, size)
    report["render_settings"]["reconstruction"].update(requested="auto", auto_selected="native",
        auto_output_size=list(size), auto_output_size_scope="viewport_render_target_estimate_v1",
        **frame_dimensions(observation["start"]))


def save_benchmark_report(path: Path, receipt: dict, report: dict) -> None:
    path.write_text(json.dumps(report), encoding="utf-8")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    receipt.update(report_sha256=digest, frame_report_sha256=digest)


def cloud_snapshot(global_mode: str = "0", ground: str = "", sky: str = "") -> dict:
    environment = {"global": global_mode, "ground": ground, "sky": sky}
    requested = {mode: (environment[mode] or global_mode) == "1" for mode in ("ground", "sky")}
    return {"environment": environment, "requested": requested,
            "effective": {mode: "ready" if enabled else "disabled" for mode, enabled in requested.items()},
            "consumers": {mode: [{"seed": 42, "status": "ready" if enabled else "disabled", "enabled": enabled}]
                          for mode, enabled in requested.items()},
            "required_seeds": {mode: [42] for mode in requested},
            "seeds": [{"seed": 42, "status": "ready", "attempts": 1, "failure": ""}]
                     if any(requested.values()) else [], "generation": 12}


def set_cloud_observation(receipt: dict, snapshot: dict) -> None:
    generation = snapshot["generation"]
    receipt["scenario"]["cloud_cache"] = {"start": copy.deepcopy(snapshot), "end": copy.deepcopy(snapshot),
                                          "stable": True, "first_change": None,
                                          "initial_generations": {"previous_frame": generation,
                                                                  "before_snapshot": generation,
                                                                  "after_snapshot": generation},
                                          "final_generations": {"before_snapshot": generation,
                                                                "after_snapshot": generation}}


def write_benchmark_run(directory: Path, name: str = "run-1") -> tuple[Path, Path, dict]:
    """An independently constructed complete v3 capture and its health receipt."""
    report = valid_report(route="benchmark-input-circuit")
    capture_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, name))
    report["capture_id"] = capture_id
    sources = {key: hashlib.sha256(key.encode("ascii")).hexdigest() for key in BENCHMARK_REQUIRED_SOURCES}
    identity = "".join(f"{key}:{sources[key]}\n" for key in sorted(sources))
    report["case_id"] = "benchmark-input-circuit-" + hashlib.sha256(identity.encode("ascii")).hexdigest()
    report["code_provenance"] = {"source_sha256": {key: sources[key] for key in BENCHMARK_PROVENANCE_SOURCES}}
    report["clock"] = {"start": {"monotonic_usec": 900_000}, "end": {"monotonic_usec": 1_100_000}}
    report["simulation"].update(start_tick=240, end_tick=249)
    report["session_at_report"] = {
        "scope": "end of collection only", "crashed": False, "holds": [],
        "pause_reason": "", "window_focused": True,
    }
    report_path, _ = write_stream_run(directory, name, report)
    sealed = json.loads(report_path.read_text())
    report_hash = hashlib.sha256(report_path.read_bytes()).hexdigest()
    samples = [{"tick": tick, "time_s": tick / 240.0, "north_m": 2.0, "east_m": -1.0,
                "altitude_m": 25.0, "ground_clearance_m": 24.0, "radius_error_m": 0.5}
               for tick in (0, 240, 249)]
    receipt = {
        "format": "openrc-benchmark-health v1", "route": "benchmark-input-circuit",
        "capture_id": capture_id, "report": report_path.name, "frame_report": "/evidence/" + report_path.name,
        "report_sha256": report_hash, "frame_report_sha256": report_hash,
        "frame_stream_sha256": sealed["stream"]["sha256"], "frame_capture_id_matches": True,
        "complete": True, "timing_complete": True, "diagnostic_complete": False,
        "frame_collection_complete": True, "frame_exit_code": 0, "observer_off_control_complete": False,
        "timing_eligible": True, "failure": "", "source_unchanged": True,
        "dwell_after_frame_seal_s": 2.5,
        "source_sha256": sources, "source_scope": "application-visible-tree-v1",
        "scenario": {
            "aircraft_id": "jensen-das-ugly-stik-60", "field_id": "default", "seed": 20261021,
            "start_choice": "airborne", "trim_speed_m_s": 15.0, "trim_throttle": 0.28,
            "rate_profile": "full", "weather": {"format": "openrc-weather v1", "speed_mps": 0.0,
                                                     "gust_mps": 0.0, "gust_up_mps": 0.0},
            "stage_backend": {"requested": "gdscript_reference", "reason": "",
                              "identity": {"backend": "gdscript_reference"}},
            "physics_hz": 240, "control_update_ticks": 4,
            "initial_checkpoint_sha256": "a" * 64,
            "solver_identity": {"kind": "source-tree-v1", "sha256": "b" * 64},
            "input_enabled": True, "physics_enabled": True, "external_driver_enabled": False,
            "fixed_fps_diagnostic": False, "observation_mode": "on", "state_input_hashing": False,
            "arguments": ["--view=pilot", "--scene_detail=medium", "--frametimes=/evidence/" + report_path.name,
                          "--frametimes-stream", "--case=" + report["case_id"], "--t=0.0375", "--warmup=0.0"]
                         + [f"--{key}={value}" for key, value in BENCHMARK_FORCED_OPTIONS.items()],
        },
        "observation": {
            "start_monotonic_usec": 800_000, "end_monotonic_usec": 1_200_000,
            "start_tick": 0, "end_tick": 249, "accepted_ticks": 249,
            "input_reads": 249, "observer_calls": 249,
            "physics_enabled_throughout": True, "input_enabled_throughout": True,
            "external_driver_disabled_throughout": True, "automatic_callbacks_throughout": True,
        },
        "violations": {key: 0 for key in BENCHMARK_VIOLATIONS},
        "health": {"samples_1hz": samples, "accepted_ticks": 249, "input_reads": 249,
                   "observer_calls": 249, "last_read_tick": 248, "pilot_updates": 63, "pilot_failure": "",
                   "min_altitude_m": 25.0, "min_ground_clearance_m": 24.0, "max_abs_radius_error_m": 0.5},
        "checkpoints": [],
    }
    set_render_observation(receipt, sealed)
    set_cloud_observation(receipt, cloud_snapshot())
    bounds = {"requested": "", "effective": "off", "bound": "off",
              "scope": "sky density and analytic relief fallback", "qualified": False}
    receipt["scenario"]["cloud_density_bounds"] = {"start": copy.deepcopy(bounds), "end": copy.deepcopy(bounds),
                                                   "stable": True}
    save_benchmark_report(report_path, receipt, sealed)
    health_path = report_path.with_name("health-" + report_path.name)
    health_path.write_text(json.dumps(receipt, allow_nan=False), encoding="utf-8")
    check = {
        "format": "openrc-godot-check v1", "capture_id": capture_id, "complete": True,
        "ok": True, "reason": "passed", "exit_code": 0, "process_exit": 0,
        "log_sha256": hashlib.sha256(report_path.with_suffix(".log").read_bytes()).hexdigest(),
        "command": ["/Applications/Godot", "--path", "/frozen/app", "--rendering-method", "gl_compatibility",
                    "--rendering-driver", "opengl3", "--script",
                    "/frozen/research/performance/sustained_flight.gd", "--",
                    "--warmup=0", "--t=0.0375", "--view=pilot", "--scene_detail=medium",
                    "--frametimes=/evidence/" + report_path.name,
                    "--sustained-receipt=/evidence/" + health_path.name],
    }
    report_path.with_name("checked-" + report_path.name).write_text(json.dumps(check), encoding="utf-8")
    return report_path, health_path, receipt


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


class DurationCliTests(unittest.TestCase):
    @staticmethod
    def _campaign(root: Path) -> None:
        for index in range(1, 4):
            write_run(root, f"run-{index}", sustained_report())

    def test_requested_soak_gate_rejects_valid_short_runs_and_records_policy(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._campaign(root)
            output = root / "summary.json"
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                status = main(["--input", str(root), "--out", str(output),
                               "--minimum-warmup-s", "30", "--minimum-sample-s", "1800"])
            result = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(status, 1)
        self.assertEqual(result["policy"]["minimum_warmup_s"], 30.0)
        self.assertEqual(result["policy"]["minimum_sample_s"], 1800.0)
        self.assertEqual(result["policy"]["minimum_runs"], 3)
        self.assertEqual(result["collection_valid_count"], 3)
        self.assertEqual(result["duration_eligible_count"], 0)
        for run in result["runs"]:
            self.assertIn("requested warm-up is shorter than 30 s", run["duration_eligibility"]["reasons"])
            self.assertIn("requested sample is shorter than 1800 s", run["duration_eligibility"]["reasons"])

    def test_defaults_and_valid_zero_warmup_are_preserved_in_policy(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._campaign(root)
            default_output = root / "default.json"
            custom_output = root / "custom.json"
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                default_status = main(["--input", str(root), "--out", str(default_output)])
                custom_status = main(["--input", str(root), "--out", str(custom_output),
                                      "--minimum-warmup-s", "0", "--minimum-sample-s", "0.1"])
            default = json.loads(default_output.read_text(encoding="utf-8"))
            custom = json.loads(custom_output.read_text(encoding="utf-8"))
        self.assertEqual(default_status, 0)
        self.assertEqual(default["policy"], DEFAULT_POLICY)
        self.assertEqual(default["policy"]["minimum_warmup_s"], 10.0)
        self.assertEqual(default["policy"]["minimum_sample_s"], 60.0)
        self.assertEqual(custom_status, 0)
        self.assertEqual(custom["policy"]["minimum_warmup_s"], 0.0)
        self.assertEqual(custom["policy"]["minimum_sample_s"], 0.1)
        self.assertEqual(custom["policy"]["minimum_runs"], 3)

    def test_invalid_duration_flags_fail_before_writing_output(self):
        cases = (("--minimum-sample-s", "0"), ("--minimum-sample-s", "-1"),
                 ("--minimum-sample-s", "nan"), ("--minimum-sample-s", "inf"),
                 ("--minimum-warmup-s", "-1"), ("--minimum-warmup-s", "nan"),
                 ("--minimum-warmup-s", "inf"))
        for flag, value in cases:
            with self.subTest(flag=flag, value=value), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                output = root / "summary.json"
                with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit) as raised:
                        main(["--input", str(root), "--out", str(output), flag, value])
                self.assertEqual(raised.exception.code, 2)
                self.assertFalse(output.exists())


class NativeRunClassificationTests(unittest.TestCase):
    def test_non_drawing_native_report_keeps_complete_data_but_cannot_qualify(self):
        report = valid_report()
        report["raw_metrics"]["render_frames_drawn"] = [100.0] * report["frames"]
        report["raw_metrics"]["render_interval_draws"] = [0.0] * report["frames"]
        report["raw_metrics"]["render_no_draw_intervals"] = [float(index + 1) for index in range(report["frames"])]
        report["render_progress"].update(status="no_draw", frames_drawn_at_start=100,
                                         frames_drawn_last=100, frames_drawn_delta=0,
                                         no_draw_intervals=report["frames"])
        for streamed in (False, True):
            with self.subTest(streamed=streamed), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                path = write_stream_run(root, "run-1", report)[0] if streamed else write_run(root, "run-1", report)
                result = summarize_run(path, SHORT_POLICY)
            self.assertTrue(result["collection_valid"], result["collection_reasons"])
            self.assertTrue(result["active_flight_qualifier"])
            self.assertFalse(result["rendering_eligibility"]["eligible"])
            self.assertEqual(result["rendering_eligibility"]["status"], "no_draw")
            self.assertFalse(result["performance_pass"])

    def test_missing_legacy_and_headless_render_progress_remain_explicit(self):
        for status in ("legacy", "headless"):
            report = valid_report()
            if status == "legacy":
                report.pop("render_progress")
            else:
                report["render_progress"]["status"] = "headless"
                report["display_server"] = "headless"
            with self.subTest(status=status), tempfile.TemporaryDirectory() as temp_dir:
                result = summarize_run(write_run(Path(temp_dir), "run-1", report), SHORT_POLICY)
            self.assertTrue(result["collection_valid"])
            self.assertEqual(result["rendering_eligibility"]["status"], "unknown" if status == "legacy" else "headless")
            self.assertFalse(result["performance_pass"])

    def test_claimed_progress_requires_continuous_consistent_draw_samples(self):
        for fault in ("missing", "counter", "hidden", "reset", "gap", "first_gap", "first_reset"):
            report = valid_report()
            if fault == "missing":
                del report["raw_metrics"]["render_frames_drawn"]
            elif fault == "counter":
                report["render_progress"]["frames_drawn_delta"] = 999
            elif fault == "hidden":
                report["raw_metrics"]["render_window_drawable"][1] = 0
            elif fault == "reset":
                report["raw_metrics"]["render_counter_resets"][1] = 1
            elif fault == "gap":
                report["raw_metrics"]["render_frames_drawn"][1] = 100
            elif fault == "first_gap":
                report["raw_metrics"]["render_interval_draws"][0] = 0
            else:
                report["raw_metrics"]["render_interval_counter_reset"][0] = 1
            for streamed in (False, True):
                with self.subTest(fault=fault, streamed=streamed), tempfile.TemporaryDirectory() as temp_dir:
                    root = Path(temp_dir)
                    path = write_stream_run(root, "run-1", report)[0] if streamed else write_run(root, "run-1", report)
                    result = summarize_run(path, SHORT_POLICY)
                self.assertTrue(result["collection_valid"], result["collection_reasons"])
                self.assertEqual(result["rendering_eligibility"]["status"], "invalid")
                self.assertFalse(result["performance_pass"])

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


class MeasurementIdentityTests(unittest.TestCase):
    @staticmethod
    def modern_report():
        report = valid_report()
        report.update(
            godot="4.8.beta2.official.cafc17a19", rendering_driver="opengl3", adapter="RTX 3090",
            window="1920x1080", window_size_at_report=[1920, 1080], os="Windows", architecture="x86_64",
            camera={"viewport": [1920, 1080], "mode": "pilot", "autozoom": True, "fov_deg": 30.0},
            render_settings={"msaa_3d": 2, "scaling_3d_scale": 1.0, "scaling_3d_mode": 0,
                             "reconstruction": {"output_size": [1920, 1080], "output_size_scope": "viewport_render_target_estimate_v1"}},
            shadows={"effective": {"native": True, "projected": True}},
            effective_grass={"verified": True, "near_grass": {"present": True, "route": "imported", "clump_count": 150}},
            code_provenance={"source_sha256": {path: "a" * 64 for path in (
                "res://main.gd", "res://render/scene_detail.gd", "res://scenery/scenery.gd", "res://scenery/collision_setup.gd")}},
            scene_at_report={
                "scope": "end of collection only; not settings or visibility history",
                "landscape_id": "club_field", "collision_world_status": "installed",
                "collision_world_identity": "b" * 64, "scenery_present": True,
                "installed_scenery_quality": "high", "requested_scene_detail": "high",
                "mesh_lod_threshold_px": 1.0,
            },
        )
        return report

    def test_campaign_refuses_different_or_unknown_measurement_identities(self):
        mutations = {
            "aircraft": lambda r: r.update(aircraft_id="f4u-corsair-250"),
            "renderer": lambda r: r.update(backend="forward_plus"),
            "engine": lambda r: r.update(godot="another-engine"),
            "adapter": lambda r: r.update(adapter="Apple M1"),
            "resolution": lambda r: r.update(window="1280x720"),
            "output-resolution": lambda r: r["render_settings"]["reconstruction"].update(output_size=[1280, 720]),
            "world": lambda r: r["scene_at_report"].update(collision_world_identity="c" * 64),
            "quality": lambda r: r["scene_at_report"].update(installed_scenery_quality="balanced"),
            "lod": lambda r: r["scene_at_report"].update(mesh_lod_threshold_px=4.0),
            "missing-world": lambda r: r.pop("scene_at_report"),
            "source": lambda r: r["code_provenance"]["source_sha256"].update({"res://main.gd": "d" * 64}),
            "aa": lambda r: r["render_settings"].update(msaa_3d=0),
            "shadows": lambda r: r["shadows"]["effective"].update(native=False),
            "grass": lambda r: r["effective_grass"]["near_grass"].update(present=False),
            "grass-count": lambda r: r["effective_grass"]["near_grass"].update(clump_count=30),
            "missing-grass": lambda r: r.pop("effective_grass"),
            "camera": lambda r: r["camera"].update(mode="chase"),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                first, second = self.modern_report(), self.modern_report()
                mutate(second)
                write_run(root, "run-1", first)
                write_run(root, "run-2", second)
                summary, status = summarize_directory(root, root / "summary.json", SHORT_POLICY)
                self.assertTrue(summary["collection_valid"], summary["runs"])
                self.assertFalse(summary["measurement_identity_consistent"])
                self.assertFalse(summary["performance_pass"])
                self.assertEqual(status, 1)

    def test_dynamic_camera_endpoints_do_not_make_identical_workloads_different(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first, second = self.modern_report(), self.modern_report()
            second["camera"].update(fov_deg=28.0, transform={"position": [100, 2, 3]})
            write_run(root, "run-1", first)
            write_run(root, "run-2", second)
            summary, status = summarize_directory(root, root / "summary.json", SHORT_POLICY, require_1080p=True)
        self.assertEqual(status, 0)
        self.assertTrue(summary["primary_1080p_eligible"])
        self.assertTrue(summary["measurement_identity_consistent"])

    def test_1080p_gate_refuses_720p_software_and_missing_installed_world(self):
        for mutation in ("720p", "scaled-output", "wrong-scope", "software", "missing", "absent", "no-source", "bad-source", "legacy"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                report = self.modern_report()
                if mutation == "720p":
                    report.update(window="1280x720")
                    report["camera"]["viewport"] = [1280, 720]
                    report["window_size_at_report"] = [1280, 720]
                elif mutation == "scaled-output":
                    report["render_settings"]["reconstruction"]["output_size"] = [1280, 720]
                elif mutation == "wrong-scope":
                    report["render_settings"]["reconstruction"]["output_size_scope"] = "physical-pixels-guessed"
                elif mutation == "software":
                    report["adapter"] = "llvmpipe (LLVM)"
                elif mutation == "missing":
                    report.pop("scene_at_report")
                elif mutation == "absent":
                    report["scene_at_report"].update(collision_world_status="absent", collision_world_identity="")
                elif mutation == "no-source":
                    report.pop("code_provenance")
                elif mutation == "bad-source":
                    report["code_provenance"]["source_sha256"] = {"res://not-runtime.gd": "garbage"}
                else:
                    report = valid_report()
                write_run(root, "run-1", report)
                summary, status = summarize_directory(root, root / "summary.json", SHORT_POLICY, require_1080p=True)
                self.assertTrue(summary["collection_valid"])
                self.assertFalse(summary["primary_1080p_eligible"])
                self.assertFalse(summary["performance_pass"])
                self.assertEqual(status, 1)

    def test_1080p_output_with_different_logical_canvas_is_not_mistaken_for_720p(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = self.modern_report()
            report.update(window="1280x720")  # Legacy field is the logical canvas.
            report["camera"]["viewport"] = [1280, 720]
            write_run(root, "run-1", report)
            summary, status = summarize_directory(root, root / "summary.json", SHORT_POLICY, require_1080p=True)
        self.assertEqual(status, 0)
        self.assertTrue(summary["primary_1080p_eligible"])

    def test_installed_world_status_cannot_hide_missing_identity(self):
        report = self.modern_report()
        report["scene_at_report"]["collision_world_identity"] = ""
        errors, _ = validate_native_report(report)
        self.assertIn("scene_at_report collision identity must agree with its status", errors)


class BenchmarkHealthTests(unittest.TestCase):
    def test_complete_technical_circuit_is_admitted_without_product_claim(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            path, health_path, _ = write_benchmark_run(root)
            result = summarize_run(path, SHORT_POLICY)
            self.assertTrue(result["collection_valid"], result["collection_reasons"])
            self.assertTrue(result["benchmark_health"]["eligible"], result["benchmark_health"]["reasons"])
            self.assertTrue(result["active_flight_qualifier"])
            self.assertTrue(result["performance_pass"])
            self.assertEqual(result["workload_scope"], "technical-benchmark-circuit")
            self.assertFalse(result["normal_product_route_qualified"])
            self.assertEqual(result["benchmark_health"]["receipt_sha256"],
                             hashlib.sha256(health_path.read_bytes()).hexdigest())
            campaign, status = summarize_directory(root, root / "summary.json", SHORT_POLICY)
            self.assertEqual(campaign["run_count"], 1)  # health-run-1.json is not a run
            self.assertEqual(status, 0)

    def test_missing_malformed_duplicate_and_oversize_receipts_are_refused(self):
        for kind in ("missing", "malformed", "duplicate", "nonfinite", "oversize"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, _ = write_benchmark_run(Path(temp_dir))
                if kind == "missing":
                    health_path.unlink()
                elif kind == "malformed":
                    health_path.write_text("{", encoding="utf-8")
                elif kind == "duplicate":
                    health_path.write_text('{"format":"x","format":"y"}', encoding="utf-8")
                elif kind == "nonfinite":
                    health_path.write_text('{"value":NaN}', encoding="utf-8")
                else:
                    health_path.write_bytes(b"x" * 100)
                with patch(f"{summarize_run.__module__}.MAX_BENCHMARK_HEALTH_BYTES", 50 if kind == "oversize" else 4 * 1024 * 1024):
                    result = summarize_run(path, SHORT_POLICY)
                self.assertTrue(result["collection_valid"])
                self.assertFalse(result["benchmark_health"]["eligible"])
                self.assertFalse(result["active_flight_qualifier"])
                self.assertFalse(result["performance_pass"])

    def test_sealed_frame_and_stream_identities_are_required(self):
        mutations = {
            "capture ID": lambda r: r.update(capture_id="other"),
            "capture ID assertion": lambda r: r.update(frame_capture_id_matches=False),
            "frame name": lambda r: r.update(frame_report="run-2.json"),
            "report hash": lambda r: r.update(report_sha256="0" * 64),
            "frame report hash": lambda r: r.update(frame_report_sha256="0" * 64),
            "stream hash": lambda r: r.update(frame_stream_sha256="0" * 64),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                mutate(receipt)
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                result = summarize_run(path, SHORT_POLICY)
                self.assertFalse(result["benchmark_health"]["eligible"])
                self.assertFalse(result["performance_pass"])
        with tempfile.TemporaryDirectory() as temp_dir:
            path, _, _ = write_benchmark_run(Path(temp_dir))
            with path.open("ab") as stream:
                stream.write(b" ")  # Still valid JSON, but no longer the sealed report.
            result = summarize_run(path, SHORT_POLICY)
            self.assertTrue(result["collection_valid"])
            self.assertIn("health frame report SHA-256 does not match", result["benchmark_health"]["reasons"])
        with tempfile.TemporaryDirectory() as temp_dir:
            path, _, _ = write_benchmark_run(Path(temp_dir))
            sidecar = path.with_name(path.name + ".frames.jsonl")
            with sidecar.open("ab") as stream:
                stream.write(b"bad\n")
            result = summarize_run(path, SHORT_POLICY)
            self.assertFalse(result["collection_valid"])
            self.assertFalse(result["benchmark_health"]["eligible"])

    def test_completion_and_all_automatic_driver_guards_are_required(self):
        mutations = {
            "incomplete": lambda r: r.update(complete=False),
            "timing incomplete": lambda r: r.update(timing_complete=False),
            "frame collection incomplete": lambda r: r.update(frame_collection_complete=False),
            "frame exit failed": lambda r: r.update(frame_exit_code=1),
            "frame exit is boolean": lambda r: r.update(frame_exit_code=False),
            "observer-off receipt": lambda r: r.update(observer_off_control_complete=True),
            "diagnostic mode": lambda r: r.update(diagnostic_complete=True),
            "not timing eligible": lambda r: r.update(timing_eligible=False),
            "source changed": lambda r: r.update(source_unchanged=False),
            "failure": lambda r: r.update(failure="pilot refused"),
            "early exit after sealing": lambda r: r.update(dwell_after_frame_seal_s=2.49),
        }
        for flag in ("physics_enabled_throughout", "input_enabled_throughout",
                     "external_driver_disabled_throughout", "automatic_callbacks_throughout"):
            mutations[flag] = lambda r, flag=flag: r["observation"].update({flag: False})
        for name, mutate in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                mutate(receipt)
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                result = summarize_run(path, SHORT_POLICY)
                self.assertFalse(result["benchmark_health"]["eligible"])
                self.assertFalse(result["performance_pass"])

    def test_checked_launch_must_match_report_log_and_succeed(self):
        for difference in ("missing", "invalid", "capture", "log", "failed", "frame", "frame_directory",
                           "health", "health_directory", "script"):
            with self.subTest(difference=difference), tempfile.TemporaryDirectory() as temp_dir:
                path, _, _ = write_benchmark_run(Path(temp_dir))
                check_path = path.with_name("checked-" + path.name)
                check = json.loads(check_path.read_text())
                if difference == "missing":
                    check_path.unlink()
                elif difference == "invalid":
                    check_path.write_text("{}x", encoding="utf-8")
                else:
                    if difference == "capture":
                        check["capture_id"] = "different"
                    elif difference == "log":
                        check["log_sha256"] = "0" * 64
                    elif difference == "failed":
                        check["ok"] = False
                    elif difference == "frame":
                        check["command"][-2] = "--frametimes=/other/run-2.json"
                    elif difference == "frame_directory":
                        check["command"][-2] = "--frametimes=/other/run-1.json"
                    elif difference == "health":
                        check["command"][-1] = "--sustained-receipt=/other/health-run-2.json"
                    elif difference == "health_directory":
                        check["command"][-1] = "--sustained-receipt=/other/health-run-1.json"
                    elif difference == "script":
                        check["command"][check["command"].index("--script") + 1] = "/different.gd"
                    check_path.write_text(json.dumps(check), encoding="utf-8")
                result = summarize_run(path, SHORT_POLICY)
                self.assertTrue(result["benchmark_health"]["eligible"])
                self.assertFalse(result["benchmark_checked_runner"]["eligible"])
                self.assertFalse(result["active_flight_qualifier"])
                self.assertFalse(result["performance_pass"])

    def test_checked_launch_rejects_engine_time_control_but_not_user_text(self):
        for option in ("--fixed-fps", "--fixed-fps=60", "--write-movie", "--time-scale=2",
                       "--frame-delay", "--disable-render-loop", "--gpu-profile", "--gpu-profile=1"):
            with self.subTest(option=option), tempfile.TemporaryDirectory() as temp_dir:
                path, _, _ = write_benchmark_run(Path(temp_dir))
                check_path = path.with_name("checked-" + path.name)
                check = json.loads(check_path.read_text())
                check["command"].insert(check["command"].index("--"), option)
                check_path.write_text(json.dumps(check), encoding="utf-8")
                result = summarize_run(path, SHORT_POLICY)
                self.assertFalse(result["benchmark_checked_runner"]["eligible"])
                self.assertFalse(result["performance_pass"])
        with tempfile.TemporaryDirectory() as temp_dir:
            path, health_path, receipt = write_benchmark_run(Path(temp_dir))
            check_path = path.with_name("checked-" + path.name)
            check = json.loads(check_path.read_text())
            check["command"][2] = "/frozen/--fixed-fps/app"
            check["command"].extend(["--note=--fixed-fps", "--fixed-fps=60"])
            check_path.write_text(json.dumps(check), encoding="utf-8")
            receipt["scenario"]["arguments"].extend(["--note=--fixed-fps", "--fixed-fps=60"])
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            self.assertTrue(summarize_run(path, SHORT_POLICY)["benchmark_checked_runner"]["eligible"])

    def test_checked_renderer_must_be_explicit_and_match_actual(self):
        cases = (["--rendering-method", "mobile"], ["--rendering-driver", "metal"],
                 ["--rendering-method=gl_compatibility", "--rendering-driver=opengl3",
                  "--rendering-method=mobile"], ["--rendering-driver=opengl3"], [])
        for flags in cases:
            with self.subTest(flags=flags), tempfile.TemporaryDirectory() as temp_dir:
                path, _, _ = write_benchmark_run(Path(temp_dir))
                check_path = path.with_name("checked-" + path.name)
                check = json.loads(check_path.read_text())
                start = check["command"].index("--rendering-method")
                del check["command"][start:start + 4]
                check["command"][start:start] = flags
                check_path.write_text(json.dumps(check), encoding="utf-8")
                self.assertFalse(summarize_run(path, SHORT_POLICY)["performance_pass"])
        with tempfile.TemporaryDirectory() as temp_dir:
            path, _, _ = write_benchmark_run(Path(temp_dir))
            check_path = path.with_name("checked-" + path.name)
            check = json.loads(check_path.read_text())
            start = check["command"].index("--rendering-method")
            check["command"][start:start + 4] = ["--rendering-method=gl_compatibility", "--rendering-driver=opengl3"]
            check_path.write_text(json.dumps(check), encoding="utf-8")
            self.assertTrue(summarize_run(path, SHORT_POLICY)["performance_pass"])

    def test_effective_render_and_sample_continuity_are_required(self):
        mutations = {
            "missing": lambda s: s.pop("effective_render"),
            "unobserved transition": lambda s: s["effective_render"].update(stable=False),
            "missing frame observation": lambda s: s["effective_render"].update(samples=1),
            "unbracketed start": lambda s: s["effective_render"].update(first_frame_bracketed=False),
            "skipped frame": lambda s: s["effective_render"].update(contiguous=False),
            "wrong retained frame count": lambda s: s["effective_render"].update(observed_frame_count=3),
            "missing seal observation": lambda s: s["effective_render"].update(seal_observed=False),
            "missing seal provenance": lambda s: s["effective_render"].pop("seal_reuses_last_frame"),
            "changed scale": lambda s: s["effective_render"]["end"].update(scaling_3d_scale=0.5),
            "unexpected msaa": lambda s: [s["effective_render"][k].update(msaa_3d=0) for k in ("start", "end")],
            "boolean policy mode": lambda s: [s["effective_render"][k]["reconstruction"].update(
                                           scaling_3d_mode=False) for k in ("start", "end")],
            "fallback": lambda s: [s["effective_render"][k]["reconstruction"].update(fallback=True,
                                   fallback_reason="metalfx_unavailable") for k in ("start", "end")],
            "unknown execution": lambda s: [s["effective_render"][k]["reconstruction"].update(
                                            effective="unknown", effective_provider="unknown",
                                            execution_status="unverified_trial") for k in ("start", "end")],
            "wrong backend": lambda s: [s["effective_render"][k].update(backend="mobile") for k in ("start", "end")],
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                mutate(receipt["scenario"])
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                result = summarize_run(path, SHORT_POLICY)
                self.assertFalse(result["benchmark_health"]["eligible"])
                self.assertFalse(result["performance_pass"])

        with tempfile.TemporaryDirectory() as temp_dir:
            path, health_path, receipt = write_benchmark_run(Path(temp_dir))
            receipt["scenario"]["render_override"] = {"reconstruction": "metalfx_spatial_quality"}
            for endpoint in ("start", "end"):
                receipt["scenario"]["effective_render"][endpoint]["reconstruction"].update(
                    requested="metalfx_spatial_quality", requested_provider="metalfx_spatial",
                    selected="native", provider="native", effective="native", effective_provider="native",
                    fallback=True, fallback_reason="metalfx_unavailable")
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            checked_path = path.with_name("checked-" + path.name)
            checked = json.loads(checked_path.read_text())
            checked["command"].append("--sustained-reconstruction=metalfx_spatial_quality")
            checked_path.write_text(json.dumps(checked), encoding="utf-8")
            self.assertFalse(summarize_run(path, SHORT_POLICY)["performance_pass"])

        with tempfile.TemporaryDirectory() as temp_dir:
            path, health_path, receipt = write_benchmark_run(Path(temp_dir))
            report = json.loads(path.read_text())
            report["render_settings"]["scaling_3d_scale"] = 0.5
            save_benchmark_report(path, receipt, report)
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            self.assertFalse(summarize_run(path, SHORT_POLICY)["benchmark_health"]["eligible"])

        with tempfile.TemporaryDirectory() as temp_dir:
            path, health_path, receipt = write_benchmark_run(Path(temp_dir))
            report = json.loads(path.read_text())
            # The guard polls every 60 frames; a backend failure can be reported
            # before that guard has replaced the selected viewport policy.
            report["render_settings"]["reconstruction"]["backend"] = {"backend_failed": True}
            save_benchmark_report(path, receipt, report)
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            self.assertFalse(summarize_run(path, SHORT_POLICY)["benchmark_health"]["eligible"])

    def test_render_observations_cover_each_frame_and_start_bracket(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path, health_path, receipt = write_benchmark_run(Path(temp_dir))
            frame_count = json.loads(path.read_text())["frames"]
            observation = receipt["scenario"]["effective_render"]
            for count, valid in ((frame_count + 1, True), (2, False), (frame_count, False),
                                 (frame_count + 2, False), (True, False), (5.0, False)):
                with self.subTest(count=count):
                    observation["samples"] = count
                    health_path.write_text(json.dumps(receipt), encoding="utf-8")
                    self.assertEqual(summarize_run(path, SHORT_POLICY)["benchmark_health"]["eligible"], valid)
            observation.update(samples=frame_count + 1, seal_reuses_last_frame=True)
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            self.assertTrue(summarize_run(path, SHORT_POLICY)["benchmark_health"]["eligible"])
            observation["end"]["output_size"] = [1280, 720]
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            self.assertFalse(summarize_run(path, SHORT_POLICY)["benchmark_health"]["eligible"])

    def test_cloud_seed_record_order_does_not_change_campaign_identity(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            directory = Path(temp_dir)
            for index in (1, 2):
                path, health_path, receipt = write_benchmark_run(directory, f"run-{index}")
                snapshot = cloud_snapshot("1")
                for mode in ("ground", "sky"):
                    snapshot["required_seeds"][mode] = [42, 43]
                    snapshot["consumers"][mode].append({"seed": 43, "status": "ready", "enabled": True})
                snapshot["seeds"].append({"seed": 43, "status": "ready", "attempts": 1, "failure": ""})
                if index == 2:
                    snapshot["seeds"].reverse()
                set_cloud_observation(receipt, snapshot)
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                self.assertTrue(summarize_run(path, SHORT_POLICY)["performance_pass"])
            campaign, status = summarize_directory(directory, directory / "summary.json", SHORT_POLICY)
            self.assertEqual(status, 0)
            self.assertTrue(campaign["benchmark_identity_consistent"])
            for mode in ("ground", "sky"):
                snapshot["required_seeds"][mode] = [42, 44]
                snapshot["consumers"][mode][1]["seed"] = 44
            next(row for row in snapshot["seeds"] if row["seed"] == 43)["seed"] = 44
            set_cloud_observation(receipt, snapshot)
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            self.assertTrue(summarize_run(path, SHORT_POLICY)["performance_pass"])
            campaign, status = summarize_directory(directory, directory / "summary-different.json", SHORT_POLICY)
            self.assertEqual(status, 1)
            self.assertFalse(campaign["benchmark_identity_consistent"])

    def test_fixture_output_paths_do_not_enter_or_alias_the_application_tree(self):
        godot = os.environ.get("OPENRC_SUSTAINED_TEST_GODOT")
        if not godot:
            self.skipTest("set OPENRC_SUSTAINED_TEST_GODOT to run the headless fixture path checks")
        repo = Path(__file__).resolve().parents[2]
        app = repo / "app"
        tmp = repo / "tmp"
        tmp.mkdir(exist_ok=True)
        project = app / "project.godot"
        before = hashlib.sha256(project.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory(dir=tmp) as temp_dir:
            directory = Path(temp_dir)
            frame = (directory / "frame.json").as_posix()
            health = (directory / "health.json").as_posix()
            cases = [[frame, health, True],
                     [(app / "new-frame.json").as_posix(), health, False],
                     [frame, (app / "new-health.json").as_posix(), False],
                     ["res://new-frame.json", health, False],
                     [(directory / ".." / ".." / "app" / "new-frame.json").as_posix(), health, False],
                     [project.as_posix(), health, False],
                     [frame, frame + ".frames.jsonl", False]]
            link = directory / "app-link"
            try:
                link.symlink_to(app, target_is_directory=True)
            except OSError:
                pass  # On Windows symlink creation may need a privilege.
            else:
                cases.extend([[(link / "new-frame.json").as_posix(), health, False],
                              [frame, (link / "new-health.json").as_posix(), False]])
            script = directory / "options-probe.gd"
            script.write_text('''extends SceneTree
func _init() -> void:
    var args := OS.get_cmdline_user_args()
    var fixture: Variant = load(args[0]).new()
    var cases: Array = JSON.parse_string(args[1])
    var results := []
    for row: Array in cases:
        var result: Dictionary = fixture._options(PackedStringArray(["--frametimes=" + row[0], "--sustained-receipt=" + row[1]]))
        results.append(result.ok)
    print("SUSTAINED_OPTIONS_TEST:", JSON.stringify(results))
    fixture.free()
    quit()
''', encoding="utf-8")
            completed = subprocess.run([godot, "--headless", "--path", str(app), "--script", str(script), "--",
                                        (repo / "research/performance/sustained_flight.gd").as_posix(),
                                        json.dumps(cases)], capture_output=True, text=True, timeout=30)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            marker = "SUSTAINED_OPTIONS_TEST:"
            lines = [line[len(marker):] for line in completed.stdout.splitlines() if line.startswith(marker)]
            self.assertEqual(len(lines), 1, completed.stdout + completed.stderr)
            self.assertEqual(json.loads(lines[0]), [case[2] for case in cases])
        self.assertEqual(hashlib.sha256(project.read_bytes()).hexdigest(), before)

    def test_native_dimensions_are_observed_and_match_the_frame_report(self):
        def run(mutate=None) -> dict:
            with tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                report = json.loads(path.read_text())
                if mutate is not None:
                    mutate(receipt["scenario"], report)
                save_benchmark_report(path, receipt, report)
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                return summarize_run(path, SHORT_POLICY)

        self.assertTrue(run()["performance_pass"])
        for window, visible, output in (((2560, 1600), (1920, 1200), (2560, 1600)),
                                        ((2560, 1600), (1280, 720), (2560, 1440))):
            def scaled_canvas(s: dict, report: dict) -> None:
                for endpoint in ("start", "end"):
                    snapshot = s["effective_render"][endpoint]
                    set_snapshot_dimensions(snapshot, window, visible=visible, output=output)
                report["render_settings"]["reconstruction"].update(frame_dimensions(snapshot))
            with self.subTest(window=window, visible=visible, output=output):
                self.assertTrue(run(scaled_canvas)["performance_pass"])
        mutations = {
            "window resize": lambda s, r: s["effective_render"]["end"].update(window_size_property=[1280, 720]),
            "output resize": lambda s, r: s["effective_render"]["end"].update(output_size=[1280, 720]),
            "intermediate resize": lambda s, r: s["effective_render"].update(stable=False),
            "missing output sample": lambda s, r: [s["effective_render"][k].pop("output_size")
                                                    for k in ("start", "end")],
            "unscoped new dimensions": lambda s, r: [s["effective_render"][k].pop("dimension_observation_scope")
                                                      for k in ("start", "end")],
            "unknown observation scope": lambda s, r: [s["effective_render"][k].update(
                dimension_observation_scope="physical_display") for k in ("start", "end")],
            "frame output mismatch": lambda s, r: r["render_settings"]["reconstruction"].update(output_size=[1280, 720]),
            "frame logical mismatch": lambda s, r: r["render_settings"]["reconstruction"].update(logical_canvas_size=[1280, 720]),
            "frame nominal mismatch": lambda s, r: r["render_settings"]["reconstruction"].update(nominal_3d_size=[1280, 720]),
            "boolean output": lambda s, r: [s["effective_render"][k].update(output_size=[True, 1080])
                                            for k in ("start", "end")],
            "unbounded output": lambda s, r: [s["effective_render"][k].update(output_size=[10**400, 1080])
                                              for k in ("start", "end")],
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                self.assertFalse(run(mutate)["performance_pass"])

        def historical(s: dict, _report: dict) -> None:
            for endpoint in ("start", "end"):
                snapshot = s["effective_render"][endpoint]
                for key in ("dimension_observation_scope", "window_size_property", "visible_rect_size", "output_size",
                            "output_size_scope", "nominal_3d_size", "nominal_3d_size_scope"):
                    snapshot.pop(key)

        legacy = run(historical)
        self.assertFalse(legacy["performance_pass"])
        self.assertEqual(legacy["benchmark_health"]["dimension_observation_scope"], "legacy_unobserved")
        self.assertIn("per-frame observation", " ".join(legacy["benchmark_health"]["reasons"]))

    def test_cloud_modes_require_explicit_ready_and_stable_consumers(self):
        for snapshot in (cloud_snapshot(), cloud_snapshot("1"), cloud_snapshot("1", ground="0"),
                         cloud_snapshot("0", sky="1"), cloud_snapshot("", ground="1", sky="0")):
            with self.subTest(snapshot=snapshot), tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                set_cloud_observation(receipt, snapshot)
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                self.assertTrue(summarize_run(path, SHORT_POLICY)["performance_pass"])
        cases = {
            "unset modes": lambda c: c["environment"].update(global_=""),
            "unsupported setting": lambda c: c["environment"].update(global_="garbage"),
            "pending bake": lambda c: c["seeds"][0].update(status="pending"),
            "failed bake": lambda c: c["seeds"][0].update(status="failed", failure="readback"),
            "unexpected analytic fallback": lambda c: c["consumers"]["sky"][0].update(enabled=False),
            "inconsistent consumer": lambda c: c["consumers"]["ground"][0].update(status="inconsistent"),
            "wrong consumer seed": lambda c: c["consumers"]["sky"][0].update(seed=43),
            "unused enabled path": lambda c: c["consumers"].update(sky=[]),
        }
        for name, mutate in cases.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                snapshot = cloud_snapshot("1")
                mutate(snapshot)
                if "global_" in snapshot["environment"]:
                    snapshot["environment"]["global"] = snapshot["environment"].pop("global_")
                set_cloud_observation(receipt, snapshot)
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                self.assertFalse(summarize_run(path, SHORT_POLICY)["performance_pass"])
        with tempfile.TemporaryDirectory() as temp_dir:
            path, health_path, receipt = write_benchmark_run(Path(temp_dir))
            receipt["scenario"]["cloud_cache"]["stable"] = False
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            self.assertFalse(summarize_run(path, SHORT_POLICY)["performance_pass"])
        observation_mutations = {
            "missing start provenance": lambda c: c.pop("initial_generations"),
            "missing end provenance": lambda c: c.pop("final_generations"),
            "change before start snapshot": lambda c: c["initial_generations"].update(previous_frame=11),
            "change during start snapshot": lambda c: c["initial_generations"].update(before_snapshot=11),
            "change during final snapshot": lambda c: c["final_generations"].update(after_snapshot=13),
            "recorded sample transition": lambda c: c.update(first_change={"phase": "sample"}),
            "missing transition record": lambda c: c.pop("first_change"),
        }
        for name, mutate in observation_mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                mutate(receipt["scenario"]["cloud_cache"])
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                self.assertFalse(summarize_run(path, SHORT_POLICY)["performance_pass"])

    def test_reconstruction_mode_uses_the_provider_enum_from_the_engine(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path, health_path, receipt = write_benchmark_run(Path(temp_dir))
            report = json.loads(path.read_text())
            receipt["scenario"]["render_override"] = {"reconstruction": "fsr2_quality"}
            policy = {"requested": "fsr2_quality", "requested_provider": "fsr2", "selected": "fsr2_quality",
                      "effective": "fsr2_quality", "provider": "fsr2", "effective_provider": "fsr2",
                      "execution_status": "policy_selected", "provider_available": True, "fallback": False,
                      "fallback_reason": "", "temporal": True, "scaling_3d_mode": 7, "scale": 2 / 3, "msaa_3d": 0}
            for endpoint in ("start", "end"):
                snapshot = receipt["scenario"]["effective_render"][endpoint]
                snapshot.update(
                    scaling_3d_mode=7, scaling_3d_mode_constant="SCALING_3D_MODE_FSR2", provider_mode_id=7,
                    scaling_3d_scale=2 / 3, msaa_3d=0, reconstruction=copy.deepcopy(policy))
                set_snapshot_dimensions(snapshot, (1920, 1080))
            report["render_settings"].update(scaling_3d_mode=7, scaling_3d_scale=2 / 3, msaa_3d=0,
                                             reconstruction={**copy.deepcopy(policy), **frame_dimensions(snapshot)})
            save_benchmark_report(path, receipt, report)
            checked_path = path.with_name("checked-" + path.name)
            checked = json.loads(checked_path.read_text())
            checked["command"].append("--sustained-reconstruction=fsr2_quality")
            checked_path.write_text(json.dumps(checked), encoding="utf-8")
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            self.assertTrue(summarize_run(path, SHORT_POLICY)["performance_pass"])
            for endpoint in ("start", "end"):
                receipt["scenario"]["effective_render"][endpoint]["provider_mode_id"] = 8
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            self.assertFalse(summarize_run(path, SHORT_POLICY)["performance_pass"])
            for endpoint in ("start", "end"):
                receipt["scenario"]["effective_render"][endpoint].update(
                    scaling_3d_mode_constant="SCALING_3D_MODE_FSR", provider_mode_id=7)
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            self.assertFalse(summarize_run(path, SHORT_POLICY)["performance_pass"])

    def test_auto_reconstruction_requires_selected_mode_and_output_identity(self):
        def run(mutate=None) -> dict:
            with tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                report = json.loads(path.read_text())
                set_auto_native_observation(receipt, report)
                if mutate is not None:
                    mutate(receipt["scenario"], report)
                save_benchmark_report(path, receipt, report)
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                check_path = path.with_name("checked-" + path.name)
                check = json.loads(check_path.read_text())
                check["command"].append("--sustained-reconstruction=auto")
                check_path.write_text(json.dumps(check), encoding="utf-8")
                return summarize_run(path, SHORT_POLICY)

        result = run()
        self.assertTrue(result["performance_pass"])
        selected = result["benchmark_health"]["scenario"]["effective_render"]
        self.assertEqual(selected["reconstruction"]["requested"], "auto")
        self.assertEqual(selected["reconstruction"]["auto_selected"], "native")
        self.assertEqual(selected["reconstruction"]["auto_output_size"], [1920, 1080])
        self.assertEqual(selected["window_size_property"], [1920, 1080])

        def change_auto_selection(s: dict, r: dict, **values) -> None:
            for endpoint in ("start", "end"):
                s["effective_render"][endpoint]["reconstruction"].update(values)
            r["render_settings"]["reconstruction"].update(values)

        def remove_auto_scope(s: dict, r: dict) -> None:
            for endpoint in ("start", "end"):
                s["effective_render"][endpoint]["reconstruction"].pop("auto_output_size_scope")
            r["render_settings"]["reconstruction"].pop("auto_output_size_scope")

        mutations = {
            "selected mode missing": lambda s, r: s["effective_render"]["start"]["reconstruction"].pop("auto_selected"),
            "selection not allowed": lambda s, r: [s["effective_render"][k]["reconstruction"].update(
                auto_selected="fsr2_quality") for k in ("start", "end")],
            "window changed": lambda s, r: s["effective_render"]["end"].update(window_size_property=[1600, 900]),
            "selection used different pixels": lambda s, r: change_auto_selection(s, r, auto_output_size=[1600, 900]),
            "selection has no output scope": remove_auto_scope,
            "selection claims physical pixels": lambda s, r: change_auto_selection(
                s, r, auto_output_size_scope="physical_display"),
            "boolean size": lambda s, r: [s["effective_render"][k]["reconstruction"].update(
                auto_output_size=[True, 1080]) for k in ("start", "end")],
            "frame report viewport differs": lambda s, r: r["render_settings"]["reconstruction"].update(
                output_size=[1600, 900]),
            "frame report choice differs": lambda s, r: r["render_settings"]["reconstruction"].update(
                auto_selected="metalfx_spatial_quality"),
            "reported fallback": lambda s, r: [s["effective_render"][k]["reconstruction"].update(
                fallback=True, fallback_reason="unavailable") for k in ("start", "end")],
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                self.assertFalse(run(mutate)["performance_pass"])

        def scaled_canvas(s: dict, report: dict) -> None:
            for endpoint in ("start", "end"):
                snapshot = s["effective_render"][endpoint]
                snapshot.update(window_size_property=[2560, 1600], visible_rect_size=[1920, 1200])
                snapshot["reconstruction"]["auto_output_size"] = [2560, 1600]
                for key in ("dimension_observation_scope", "output_size", "output_size_scope",
                            "nominal_3d_size", "nominal_3d_size_scope"):
                    snapshot.pop(key)
            report["render_settings"]["reconstruction"].update(
                auto_output_size=[2560, 1600], output_size=[1920, 1200])
            for key in ("output_size_scope", "logical_canvas_size", "nominal_3d_size", "nominal_3d_size_scope"):
                report["render_settings"]["reconstruction"].pop(key)

        # Historical Auto observed the window and canvas, but not every output estimate.
        historical = run(scaled_canvas)
        self.assertFalse(historical["performance_pass"])
        self.assertEqual(historical["benchmark_health"]["dimension_observation_scope"], "legacy_auto_window_canvas_only")

        def corrected_canvas(s: dict, report: dict) -> None:
            for endpoint in ("start", "end"):
                snapshot = s["effective_render"][endpoint]
                set_snapshot_dimensions(snapshot, (2560, 1600), visible=(1920, 1200))
                snapshot["reconstruction"]["auto_output_size"] = [2560, 1600]
            report["render_settings"]["reconstruction"].update(auto_output_size=[2560, 1600],
                                                               **frame_dimensions(snapshot))

        self.assertTrue(run(corrected_canvas)["performance_pass"])

        def letterboxed_canvas(s: dict, report: dict) -> None:
            for endpoint in ("start", "end"):
                snapshot = s["effective_render"][endpoint]
                set_snapshot_dimensions(snapshot, (2560, 1600), visible=(1920, 1080), output=(1920, 1080))
                snapshot["reconstruction"]["auto_output_size"] = [1920, 1080]
            report["render_settings"]["reconstruction"].update(auto_output_size=[1920, 1080],
                                                               **frame_dimensions(snapshot))

        self.assertTrue(run(letterboxed_canvas)["performance_pass"])
        new_mutations = {
            "missing scope": lambda p: p.pop("output_size_scope"),
            "null scope": lambda p: p.update(output_size_scope=None),
            "unknown scope": lambda p: p.update(output_size_scope="physical_display"),
            "output is logical": lambda p: p.update(output_size=[1920, 1200]),
            "logical size mismatch": lambda p: p.update(logical_canvas_size=[2560, 1600]),
            "boolean output": lambda p: p.update(output_size=[True, 1600]),
            "nominal size mismatch": lambda p: p.update(nominal_3d_size=[1280, 800]),
            "nominal scope missing": lambda p: p.pop("nominal_3d_size_scope"),
            "nominal claims SDK execution": lambda p: p.update(nominal_3d_size_scope="sdk_observed"),
            "unbounded scale": lambda p: p.update(scale=1e308),
        }
        for name, mutate in new_mutations.items():
            def change(s: dict, report: dict) -> None:
                corrected_canvas(s, report)
                mutate(report["render_settings"]["reconstruction"])
            with self.subTest(name=name):
                self.assertFalse(run(change)["performance_pass"])

        def unbounded_size(s: dict, report: dict) -> None:
            corrected_canvas(s, report)
            huge = [10**400, 1600]
            for endpoint in ("start", "end"):
                snapshot = s["effective_render"][endpoint]
                snapshot["window_size_property"] = huge
                snapshot["reconstruction"]["auto_output_size"] = huge
            report["render_settings"]["reconstruction"].update(auto_output_size=huge, output_size=huge)

        self.assertFalse(run(unbounded_size)["performance_pass"])

        def unverified_metalfx(s: dict, report: dict) -> None:
            for endpoint in ("start", "end"):
                snap = s["effective_render"][endpoint]
                snap.update(backend="mobile", driver="metal", scaling_3d_mode=7,
                            scaling_3d_mode_constant="SCALING_3D_MODE_METALFX_SPATIAL", provider_mode_id=7,
                            scaling_3d_scale=2 / 3, window_size_property=[2560, 1600],
                            visible_rect_size=[2560, 1600])
                snap["reconstruction"].update(
                    requested_provider="metalfx_spatial", auto_selected="metalfx_spatial_quality",
                    auto_output_size=[2560, 1600], selected="metalfx_spatial_quality", effective="unknown",
                    provider="metalfx_spatial", effective_provider="unknown", execution_status="unverified_trial",
                    scaling_3d_mode=7, scale=2 / 3)
            report.update(backend="mobile", rendering_driver="metal")
            report["render_settings"].update(scaling_3d_mode=7, scaling_3d_scale=2 / 3,
                reconstruction={**s["effective_render"]["end"]["reconstruction"], "output_size": [2560, 1600]})

        result = run(unverified_metalfx)
        self.assertFalse(result["benchmark_health"]["eligible"])
        self.assertFalse(result["performance_pass"])

    def test_auto_output_size_is_part_of_campaign_identity(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            directory = Path(temp_dir)
            for index, size in enumerate(((1920, 1080), (2560, 1600)), 1):
                path, health_path, receipt = write_benchmark_run(directory, f"run-{index}")
                report = json.loads(path.read_text())
                set_auto_native_observation(receipt, report, size)
                save_benchmark_report(path, receipt, report)
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                check_path = path.with_name("checked-" + path.name)
                check = json.loads(check_path.read_text())
                check["command"].append("--sustained-reconstruction=auto")
                check_path.write_text(json.dumps(check), encoding="utf-8")
                self.assertTrue(summarize_run(path, SHORT_POLICY)["performance_pass"])
            summary, status = summarize_directory(directory, directory / "summary.json", SHORT_POLICY)
            self.assertEqual(status, 1)
            self.assertFalse(summary["benchmark_identity_consistent"])

    def test_native_output_size_is_part_of_campaign_identity(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            directory = Path(temp_dir)
            for index, size in enumerate(((1920, 1080), (2560, 1600)), 1):
                path, health_path, receipt = write_benchmark_run(directory, f"run-{index}")
                report = json.loads(path.read_text())
                for endpoint in ("start", "end"):
                    snapshot = receipt["scenario"]["effective_render"][endpoint]
                    set_snapshot_dimensions(snapshot, size)
                report["render_settings"]["reconstruction"].update(frame_dimensions(snapshot))
                save_benchmark_report(path, receipt, report)
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                self.assertTrue(summarize_run(path, SHORT_POLICY)["performance_pass"])
            summary, status = summarize_directory(directory, directory / "summary.json", SHORT_POLICY)
            self.assertEqual(status, 1)
            self.assertFalse(summary["benchmark_identity_consistent"])

    def test_cloud_density_selector_and_actual_shader_are_identity(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path, health_path, receipt = write_benchmark_run(Path(temp_dir))
            bounds = receipt["scenario"]["cloud_density_bounds"]
            for endpoint in ("start", "end"):
                bounds[endpoint].update(requested="three", effective="three", bound="three")
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            self.assertTrue(summarize_run(path, SHORT_POLICY)["performance_pass"])
            bounds["end"]["bound"] = "off"
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            self.assertFalse(summarize_run(path, SHORT_POLICY)["performance_pass"])

    def test_checked_launch_rejects_headless_engine_options(self):
        for flags in (["--headless"], ["--headless=1"], ["--display-driver", "headless"],
                      ["--display-driver=headless"], ["--rendering-driver", "dummy"], ["--rendering-driver=dummy"]):
            with self.subTest(flags=flags), tempfile.TemporaryDirectory() as temp_dir:
                path, _, _ = write_benchmark_run(Path(temp_dir))
                check_path = path.with_name("checked-" + path.name)
                check = json.loads(check_path.read_text())
                index = check["command"].index("--")
                check["command"][index:index] = flags
                check_path.write_text(json.dumps(check), encoding="utf-8")
                result = summarize_run(path, SHORT_POLICY)
                self.assertTrue(result["benchmark_health"]["eligible"])
                self.assertFalse(result["benchmark_checked_runner"]["eligible"])
                self.assertFalse(result["performance_pass"])

    def test_checked_workload_must_match_scenario_and_harness_modes(self):
        mutations = {
            "observer disabled": lambda c: c.append("--sustained-observation=off"),
            "diagnostic mode": lambda c: c.append("--sustained-diagnostic-ticks=2400"),
            "unrecorded hashing": lambda c: c.append("--sustained-hash"),
            "invalid hashing flag": lambda c: c.append("--sustained-hash=1"),
            "different camera": lambda c: c.__setitem__(c.index("--view=pilot"), "--view=chase"),
            "different scene detail": lambda c: c.__setitem__(c.index("--scene_detail=medium"), "--scene_detail=low"),
            "duplicate option": lambda c: c.append("--view=pilot"),
            "different duration": lambda c: c.__setitem__(c.index("--t=0.0375"), "--t=0.05"),
            "bare duration": lambda c: c.__setitem__(c.index("--t=0.0375"), "--t"),
            "different warmup": lambda c: c.__setitem__(c.index("--warmup=0"), "--warmup=30"),
            "conflicting forced option": lambda c: c.append("--aircraft=other"),
            "scripted": lambda c: c.append("--scripted"),
            "hidden geometry diagnostic": lambda c: c.append("--sustained-hide-shader=ground"),
            "forced shader parameter diagnostic": lambda c: c.append("--sustained-shader-param=ground.anti_tiling=0"),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp_dir:
                path, _, _ = write_benchmark_run(Path(temp_dir))
                check_path = path.with_name("checked-" + path.name)
                check = json.loads(check_path.read_text())
                mutate(check["command"])
                check_path.write_text(json.dumps(check), encoding="utf-8")
                result = summarize_run(path, SHORT_POLICY)
                self.assertTrue(result["benchmark_health"]["eligible"])
                self.assertFalse(result["benchmark_checked_runner"]["eligible"])
                self.assertFalse(result["performance_pass"])
        with tempfile.TemporaryDirectory() as temp_dir:
            path, _, _ = write_benchmark_run(Path(temp_dir))
            check_path = path.with_name("checked-" + path.name)
            check = json.loads(check_path.read_text())
            check["command"].extend(["--sustained-observation=on", "--aircraft=jensen-das-ugly-stik-60"])
            check_path.write_text(json.dumps(check), encoding="utf-8")
            self.assertTrue(summarize_run(path, SHORT_POLICY)["performance_pass"])

    def test_workload_reconciliation_distinguishes_unavailable_from_mismatch(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path, health_path, receipt = write_benchmark_run(Path(temp_dir))
            receipt["scenario"]["cloud_cache"]["stable"] = False
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            result = summarize_run(path, SHORT_POLICY)
            reasons = result["benchmark_checked_runner"]["reasons"]
            self.assertFalse(result["benchmark_health"]["eligible"])
            self.assertFalse(result["benchmark_checked_runner"]["eligible"])
            self.assertIn("checked invocation workload reconciliation unavailable because benchmark health scenario is ineligible", reasons)
            self.assertNotIn("checked invocation workload arguments do not match the benchmark scenario", reasons)
            self.assertFalse(result["performance_pass"])

        with tempfile.TemporaryDirectory() as temp_dir:
            path, _, _ = write_benchmark_run(Path(temp_dir))
            check_path = path.with_name("checked-" + path.name)
            check = json.loads(check_path.read_text())
            check["command"][check["command"].index("--view=pilot")] = "--view=chase"
            check_path.write_text(json.dumps(check), encoding="utf-8")
            result = summarize_run(path, SHORT_POLICY)
            self.assertTrue(result["benchmark_health"]["eligible"])
            self.assertIn("checked invocation workload arguments do not match the benchmark scenario",
                          result["benchmark_checked_runner"]["reasons"])
            self.assertFalse(result["performance_pass"])

    def test_render_override_sweep_must_match_checked_command(self):
        def run(command_extra: list[str], recorded) -> dict:
            with tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                receipt["scenario"]["render_override"] = recorded
                report = json.loads(path.read_text())
                if isinstance(recorded, dict):
                    scale = recorded.get("scaling_3d_scale", 1.0)
                    msaa = recorded.get("msaa_3d", 2)
                    if type(scale) in (int, float) and type(msaa) is int:
                        set_render_observation(receipt, report, scale=scale, msaa=msaa)
                        save_benchmark_report(path, receipt, report)
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                check_path = path.with_name("checked-" + path.name)
                check = json.loads(check_path.read_text())
                check["command"].extend(command_extra)
                check_path.write_text(json.dumps(check), encoding="utf-8")
                return summarize_run(path, SHORT_POLICY)

        both = ["--sustained-render-scale=0.75", "--sustained-msaa=1"]
        result = run(both, {"scaling_3d_scale": 0.75, "msaa_3d": 1})
        self.assertTrue(result["performance_pass"])
        self.assertEqual(result["benchmark_health"]["scenario"]["render_override"],
                         {"scaling_3d_scale": 0.75, "msaa_3d": 1})
        self.assertTrue(run(["--sustained-msaa=0"], {"msaa_3d": 0})["performance_pass"])
        self.assertTrue(run(["--sustained-reconstruction=native"],
                            {"reconstruction": "native"})["performance_pass"])
        self.assertTrue(run([], None)["performance_pass"])
        mismatches = {
            "unrecorded override": (both, None),
            "override without command": ([], {"scaling_3d_scale": 0.75, "msaa_3d": 1}),
            "different scale": (both, {"scaling_3d_scale": 0.5, "msaa_3d": 1}),
            "different msaa": (both, {"scaling_3d_scale": 0.75, "msaa_3d": 2}),
            "missing field": (both, {"scaling_3d_scale": 0.75}),
            "extra field": (["--sustained-msaa=1"], {"scaling_3d_scale": 1.0, "msaa_3d": 1}),
            "float msaa": (["--sustained-msaa=1"], {"msaa_3d": 1.0}),
            "malformed scale": (["--sustained-render-scale=fast"], {"scaling_3d_scale": 0.75}),
            "bare msaa flag": (["--sustained-msaa"], {"msaa_3d": 0}),
            "different reconstruction": (["--sustained-reconstruction=metalfx_spatial_85"],
                                         {"reconstruction": "metalfx_spatial_quality"}),
            "bare reconstruction flag": (["--sustained-reconstruction"], {"reconstruction": "native"}),
        }
        for name, (extra, recorded) in mismatches.items():
            with self.subTest(name=name):
                result = run(extra, recorded)
                self.assertFalse(result["benchmark_checked_runner"]["eligible"])
                self.assertFalse(result["performance_pass"])

    def test_each_violation_and_missing_counter_is_rejected(self):
        for key in sorted(BENCHMARK_VIOLATIONS):
            for value in (1, None, False):
                with self.subTest(counter=key, value=value), tempfile.TemporaryDirectory() as temp_dir:
                    path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                    if value is None:
                        del receipt["violations"][key]
                    else:
                        receipt["violations"][key] = value
                    health_path.write_text(json.dumps(receipt), encoding="utf-8")
                    result = summarize_run(path, SHORT_POLICY)
                    self.assertFalse(result["benchmark_health"]["eligible"])
                    self.assertFalse(result["active_flight_qualifier"])

    def test_source_map_is_required_and_bound_to_report_and_case(self):
        mutations = {
            "missing source scope": lambda r: r.pop("source_scope"),
            "incomplete source scope": lambda r: r.update(source_scope="named-inputs"),
            "missing adapter": lambda r: r["source_sha256"].pop("research/performance/sustained_flight.gd"),
            "missing cloud implementation": lambda r: r["source_sha256"].pop("res://render/cloud_shadow_map.gd"),
            "missing cloud include": lambda r: r["source_sha256"].pop("res://render/cloud_field.gdshaderinc"),
            "missing render project": lambda r: r["source_sha256"].pop("res://project.godot"),
            "missing pilot airdata": lambda r: r["source_sha256"].pop("res://ai/companions/observation_airdata.gd"),
            "missing input laws": lambda r: r["source_sha256"].pop("res://input/commands.gd"),
            "missing aircraft data": lambda r: r["source_sha256"].pop("res://data/aircraft/jensen_ugly_stik_60.json"),
            "missing field data": lambda r: r["source_sha256"].pop("res://data/fields/default.json"),
            "missing lake data": lambda r: r["source_sha256"].pop("res://data/fields/lake.json"),
            "missing contact helper": lambda r: r["source_sha256"].pop("res://statistics/fixed_wing_adapter.gd"),
            "missing terrain source": lambda r: r["source_sha256"].pop("res://physics/ground_terrain.gd"),
            "malformed hash": lambda r: r["source_sha256"].update({"res://main.gd": "x"}),
            "runtime disagreement": lambda r: r["source_sha256"].update({"res://main.gd": "0" * 64}),
            "unbound pilot change": lambda r: r["source_sha256"].update({"res://ai/companions/pilot.gd": "0" * 64}),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                mutate(receipt)
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                self.assertFalse(summarize_run(path, SHORT_POLICY)["benchmark_health"]["eligible"])

    def test_scenario_and_solver_identity_are_required(self):
        mutations = {
            "wrong aircraft": lambda r: r["scenario"].update(aircraft_id="other"),
            "wrong seed": lambda r: r["scenario"].update(seed=1),
            "external driver": lambda r: r["scenario"].update(external_driver_enabled=True),
            "physics disabled": lambda r: r["scenario"].update(physics_enabled=False),
            "input disabled": lambda r: r["scenario"].update(input_enabled=False),
            "fixed fps": lambda r: r["scenario"].update(fixed_fps_diagnostic=True),
            "observation disabled": lambda r: r["scenario"].update(observation_mode="off"),
            "missing weather": lambda r: r["scenario"].update(weather={}),
            "not calm": lambda r: r["scenario"]["weather"].update(speed_mps=3.0),
            "nonfinite weather": lambda r: r["scenario"].update(weather={"wind": float("inf")}),
            "huge integer throttle": lambda r: r["scenario"].update(trim_throttle=10**400),
            "backend substituted": lambda r: r["scenario"]["stage_backend"]["identity"].update(backend="native"),
            "missing solver identity": lambda r: r["scenario"].update(solver_identity={}),
            "missing checkpoint": lambda r: r["scenario"].pop("initial_checkpoint_sha256"),
            "wrong scene frame path": lambda r: r["scenario"]["arguments"].__setitem__(2, "--frametimes=/other/run-1.json"),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                mutate(receipt)
                health_path.write_text(json.dumps(receipt, allow_nan=True), encoding="utf-8")
                self.assertFalse(summarize_run(path, SHORT_POLICY)["benchmark_health"]["eligible"])

    def test_optional_checkpoint_hashes_must_cover_all_accepted_ticks(self):
        for difference in ("none", "gap", "bad_hash", "disabled"):
            with self.subTest(difference=difference), tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                receipt["scenario"]["state_input_hashing"] = difference != "disabled"
                receipt["checkpoints"] = [{"start_tick": 1, "end_tick": 249, "sha256": "d" * 64, "partial": True}]
                if difference == "gap":
                    receipt["checkpoints"][0]["end_tick"] = 248
                elif difference == "bad_hash":
                    receipt["checkpoints"][0]["sha256"] = "invalid"
                health_path.write_text(json.dumps(receipt), encoding="utf-8")
                if difference != "disabled":
                    checked_path = path.with_name("checked-" + path.name)
                    checked = json.loads(checked_path.read_text())
                    checked["command"].append("--sustained-hash")
                    checked_path.write_text(json.dumps(checked), encoding="utf-8")
                result = summarize_run(path, SHORT_POLICY)
                self.assertEqual(result["benchmark_health"]["eligible"], difference == "none")
                self.assertEqual(result["performance_pass"], difference == "none")

    def test_clock_tick_and_diagnostic_coverage_are_required(self):
        mutations = {
            "late observation despite bracketing sample": lambda r: r["observation"].update(start_monotonic_usec=950_000),
            "early observation end": lambda r: r["observation"].update(end_monotonic_usec=1_050_000),
            "tick reset": lambda r: r["observation"].update(start_tick=1),
            "unobserved end": lambda r: r["observation"].update(end_tick=248),
            "lost input": lambda r: r["observation"].update(input_reads=248),
            "missed tick": lambda r: r["observation"].update(observer_calls=248),
            "incomplete pilot": lambda r: r["health"].update(pilot_updates=62),
            "pilot refused": lambda r: r["health"].update(pilot_failure="refused"),
            "contact between diagnostic samples": lambda r: r["health"].update(min_ground_clearance_m=0.0),
            "claimed but missing checkpoints": lambda r: r["scenario"].update(state_input_hashing=True),
            "missing samples": lambda r: r["health"].pop("samples_1hz"),
            "sample gap": lambda r: r["health"].update(samples_1hz=[r["health"]["samples_1hz"][0], r["health"]["samples_1hz"][-1]]),
            "missing endpoint": lambda r: r["health"]["samples_1hz"].pop(),
            "contact sample": lambda r: r["health"]["samples_1hz"][1].update(ground_clearance_m=0.0),
            "bad sample time": lambda r: r["health"]["samples_1hz"][1].update(time_s=2.0),
            "nonfinite position": lambda r: r["health"]["samples_1hz"][1].update(north_m=float("nan")),
            "huge sample tick": lambda r: r["health"]["samples_1hz"][1].update(tick=10**400),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp_dir:
                path, health_path, receipt = write_benchmark_run(Path(temp_dir))
                mutate(receipt)
                health_path.write_text(json.dumps(receipt, allow_nan=True), encoding="utf-8")
                result = summarize_run(path, SHORT_POLICY)
                self.assertFalse(result["benchmark_health"]["eligible"])
                self.assertFalse(result["active_flight_qualifier"])

    def test_existing_live_input_does_not_require_a_benchmark_receipt(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = write_run(Path(temp_dir), "run-1", valid_report())
            result = summarize_run(path, SHORT_POLICY)
            self.assertTrue(result["active_flight_qualifier"])
            self.assertTrue(result["performance_pass"])
            self.assertIsNone(result["benchmark_health"])
            self.assertEqual(result["workload_scope"], "direct-live-input")

    def test_campaign_refuses_mixed_workloads_or_benchmark_identities(self):
        for difference in ("none", "live_input", "scenario", "arguments", "source", "render_override"):
            with self.subTest(difference=difference), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                write_benchmark_run(root, "run-1")
                if difference == "live_input":
                    second = write_run(root, "run-2", valid_report())
                else:
                    second, health_path, receipt = write_benchmark_run(root, "run-2")
                    if difference == "scenario":
                        receipt["scenario"]["trim_throttle"] = 0.3
                    elif difference == "render_override":
                        receipt["scenario"]["render_override"] = {"scaling_3d_scale": 0.5}
                        report = json.loads(second.read_text())
                        set_render_observation(receipt, report, scale=0.5)
                        save_benchmark_report(second, receipt, report)
                        checked_path = second.with_name("checked-" + second.name)
                        checked = json.loads(checked_path.read_text())
                        checked["command"].append("--sustained-render-scale=0.5")
                        checked_path.write_text(json.dumps(checked), encoding="utf-8")
                    elif difference == "arguments":
                        receipt["scenario"]["arguments"][1] = "--scene_detail=low"
                        checked_path = second.with_name("checked-" + second.name)
                        checked = json.loads(checked_path.read_text())
                        checked["command"][checked["command"].index("--scene_detail=medium")] = "--scene_detail=low"
                        checked_path.write_text(json.dumps(checked), encoding="utf-8")
                    elif difference == "source":
                        receipt["source_sha256"]["research/performance/sustained_input.gd"] = "c" * 64
                        sources = receipt["source_sha256"]
                        identity = "".join(f"{key}:{sources[key]}\n" for key in sorted(sources))
                        report = json.loads(second.read_text())
                        report["case_id"] = "benchmark-input-circuit-" + hashlib.sha256(identity.encode("ascii")).hexdigest()
                        case_index = next(i for i, arg in enumerate(receipt["scenario"]["arguments"]) if arg.startswith("--case="))
                        receipt["scenario"]["arguments"][case_index] = "--case=" + report["case_id"]
                        second.write_text(json.dumps(report), encoding="utf-8")
                        report_hash = hashlib.sha256(second.read_bytes()).hexdigest()
                        receipt.update(report_sha256=report_hash, frame_report_sha256=report_hash)
                    health_path.write_text(json.dumps(receipt), encoding="utf-8")
                self.assertTrue(summarize_run(second, SHORT_POLICY)["performance_pass"])
                campaign, status = summarize_directory(root, root / "summary.json", SHORT_POLICY)
                self.assertEqual(status, 0 if difference == "none" else 1)
                self.assertEqual(campaign["performance_pass"], difference == "none")
                if difference == "live_input":
                    self.assertFalse(campaign["workload_scope_consistent"])
                elif difference != "none":
                    self.assertFalse(campaign["benchmark_identity_consistent"])

    def test_campaign_refuses_reused_capture_id_even_if_each_run_is_valid(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            first, _, _ = write_benchmark_run(root, "run-1")
            second, health_path, receipt = write_benchmark_run(root, "run-2")
            capture_id = json.loads(first.read_text())["capture_id"]
            report = json.loads(second.read_text())
            report["capture_id"] = capture_id
            stream_path = second.with_name(second.name + ".frames.jsonl")
            records = [json.loads(line) for line in stream_path.read_text().splitlines()]
            records[0]["capture_id"] = capture_id
            write_stream_fixture(second, report, records)
            report_hash = hashlib.sha256(second.read_bytes()).hexdigest()
            receipt.update(capture_id=capture_id, report_sha256=report_hash, frame_report_sha256=report_hash,
                           frame_stream_sha256=report["stream"]["sha256"])
            health_path.write_text(json.dumps(receipt), encoding="utf-8")
            checked_path = second.with_name("checked-" + second.name)
            checked = json.loads(checked_path.read_text())
            checked["capture_id"] = capture_id
            checked_path.write_text(json.dumps(checked), encoding="utf-8")
            self.assertTrue(summarize_run(first, SHORT_POLICY)["performance_pass"])
            self.assertTrue(summarize_run(second, SHORT_POLICY)["performance_pass"])
            summary, status = summarize_directory(root, root / "summary.json", SHORT_POLICY)
            self.assertEqual(status, 1)
            self.assertFalse(summary["benchmark_capture_ids_distinct"])
            self.assertIn("benchmark capture IDs are missing or repeated", summary["campaign_reasons"])


if __name__ == "__main__":
    unittest.main()
