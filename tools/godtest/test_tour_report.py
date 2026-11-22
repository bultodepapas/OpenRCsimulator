"""Offline, artifact-level tests for the three-aircraft suite reducer."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import catalog
from analysis import report
from godtest import _tour_success
from runner import write_json
from tour_report import report_tour
import tour_report


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def display(manifest: dict, stamp: int):
    if manifest["headless"]:
        return {"status": "unavailable_headless", "monotonic_usec": stamp}
    return {"status": "observed", "monotonic_usec": stamp, "max_fps": manifest["max_fps"],
            "window_mode": manifest["window_mode"], "window_mode_code": 0 if manifest["window_mode"] == "windowed" else 3,
            "vsync_mode": manifest["vsync_mode"], "vsync_mode_code": 0 if manifest["vsync_mode"] == "disabled" else 1,
            "window_size": manifest["resolution"], "viewport_size": manifest["resolution"]}


def fixture(root: Path, repeats=1, *, headless=False):
    suite = root / "tour"
    suite.mkdir()
    plan = catalog.performance_tour({"headless": headless}) * repeats
    source = suite / ("001-" + plan[0]["id"]) / "source"
    (source / "app/.godot/imported").mkdir(parents=True)
    project_bytes = b'[application]\nconfig/name="OpenRC Simulator"\n'
    (source / "app/project.godot").write_bytes(project_bytes)
    (source / "app/.godot/imported/fixture.bin").write_bytes(b"import")
    files = {"app/project.godot": hashlib.sha256(project_bytes).hexdigest()}
    imports = {"app/.godot/imported/fixture.bin": hashlib.sha256(b"import").hexdigest()}
    snapshot = {"format": "openrc-godtest-source-v1", "root": str(source), "files": files,
                "imports": imports, "source_digest": digest(files), "imported_digest": digest(imports)}
    outcomes = []
    for pos, manifest in enumerate(plan):
        path = suite / f"{pos+1:03d}-{manifest['id']}"
        path.mkdir(exist_ok=True)
        write_json(path / "manifest.requested.json", manifest)
        write_json(path / "manifest.resolved.json", {**manifest, "output_dir": str(path)})
        write_json(path / "snapshot.json", snapshot)
        phases, walls, indexes, clock = [], [], [], 1_000_000
        for index, (cycle, name) in enumerate(tour_report._expected_phases(manifest["cycles"])):
            # Three intervals deliberately keep percentile tails short, and a
            # different slow frame in each repeat makes median/range testable.
            values = [10_000, 16_000, 20_000 + 10_000 * (pos // 3)]
            start = clock
            clock += sum(values)
            walls.extend(values)
            indexes.extend([index] * len(values))
            phase = {"name": name, "id": f"{cycle}-{index}-{name}", "cycle": cycle, "index": index,
                     "requested": True, "status": "complete", "reason": "", "start_usec": start,
                     "end_usec": clock, "frames": len(values), "wall_seconds": sum(values) / 1_000_000,
                     "sim_seconds": sum(values) / 1_000_000, "rendered": not headless,
                     "runtime_display": display(manifest, clock)}
            if name == "runway_circuit":
                phase["pilot"] = {"runway_circuit": {"format": "openrc-godtest-runway-circuit-v1",
                    "complete": True, "failed": False, "center_north_m": 0, "center_east_m": 0,
                    "target_radius_m": 100, "runway_enclosing_radius_m": 50, "inner_radius_m": 60,
                    "outer_radius_m": 160, "clockwise_sweep_rad": 6.29, "lap_sim_seconds": 30,
                    "minimum_radius_m": 80, "maximum_radius_m": 120, "minimum_agl_m": 40,
                    "maximum_agl_m": 60, "quadrants_mask": 15, "agl_limits_m": [20, 140]}}
            if name.startswith("menu_"):
                phase.update(menu_screen=name.removeprefix("menu_"), pause_tick_invariant=True,
                             pause_state_invariant=True, resume_to_tick_ms=8)
            phases.append(phase)
        ends, clock = [], 1_000_000
        for wall in walls:
            clock += wall
            ends.append(clock)
        records = [{"type": "header", "format": "openrc-frame-stream v1"},
                   {"type": "chunk", "sequence": 0, "start_frame": 0, "frames": len(walls),
                    "wall_usec": walls, "end_usec": ends, "engine_delta_s": [x/1e6 for x in walls],
                    "metrics": {"phase_index": indexes,
                                "render_frames_drawn": list(range(1, len(walls) + 1)) if not headless else [0] * len(walls),
                                "render_interval_draws": [int(not headless)] * len(walls),
                                "render_window_drawable": [int(not headless)] * len(walls)}},
                   {"type": "trailer", "complete": True, "frames": len(walls), "chunks": 1}]
        raw = b"".join((json.dumps(row) + "\n").encode() for row in records)
        (path / "frames.jsonl").write_bytes(raw)
        write_json(path / "frametimes.json", {"format": "openrc-godtest-frames-v1", "completion_kind": "scenario_event",
            "complete": True, "frames": len(walls), "stream": {"file": "frames.jsonl", "complete": True,
            "frames": len(walls), "chunks": 1, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}})
        diag = {key: "fixture" for key in tour_report.HARDWARE}
        diag.update(max_fps=0, vsync_mode=0, reconstruction_at_start={"mode": "native"},
                    rendering_method="forward_plus", rendering_driver="vulkan")
        identity = {"engine": {"version": "fixture"}, "backend": {"backend": "native", "binary_sha256": "b"*64},
                    "instrumentation": "frames_diagnostics_pilot_v1", "actual_resolution": [1920, 1080],
                    "viewport_size": [1920, 1080], "selection": {"aircraft": manifest["aircraft"]},
                    "flight_aircraft": {key: manifest["aircraft"] for key in ("requested", "flight", "model")},
                    "diagnostics": diag, "frame_watch": {"run_id": path.name,
                        "identity": {"capture_id": path.name, "launch_instance": "launch", "epoch": 1}},
                    "field": {"sha256": "field"}, "pilot": {"profile": manifest["aircraft"]},
                    "camera": {"view": "pilot"}, "scenery_sha256": "same", "effective_weather": {},
                    "effective_lighting": {}, "effective_sky": {},
                    "runtime_display": display(manifest, 1_046_000), "final_display": display(manifest, clock),
                    "effective_display": {key: manifest[key] for key in ("scene_detail", "window_mode", "max_fps", "vsync_mode")}}
        write_json(path / "runtime.json", {"format": "openrc-godtest-runtime-v1", "complete": True,
            "execution": "completed", "data": "complete", "coverage": "complete", "flight": "completed",
            "identity": identity, "phases": phases,
            "metrics": {"rendered": not headless, "requested_resolution_match": True}})
        watchdir = path / "frame-watch"
        watchdir.mkdir()
        watch_id = identity["frame_watch"]["identity"]
        watch = {"format": "openrc-debug-frame-watch v1", "outcome": "owner_stopped", "error": None,
                 "final_poll": "complete", "identity": watch_id, "gaps": [], "incidents": [], "hangs": [],
                 "segments": [{**watch_id, "overall": {"frames": len(walls), "relative_stutter_frames": 3,
                                 "stall_frames": 1}, "rows_lost": 0, "coverage": "contiguous",
                               "reconciliation": {key: {"agrees": True} for key in
                                   ("relative_stutter_total", "stall_total", "hitch_total")}}]}
        write_json(watchdir / "watch.json", watch)
        (watchdir / "report.html").write_text("watch", encoding="utf-8")
        execution = {"state": "runtime_finished", "failure": "", "source_changed": False, "changed_frozen_files": [],
                     "host": {"platform": "Linux-fixture"},
                     "rendering_requested": {"rendering_method": "forward_plus", "rendering_driver": "vulkan"},
                     "engine_command_verified": True, "engine_files_changed": [],
                     "host_identity": {"format": "openrc-godtest-host-v1", "host_sha256": "1"*64, "boot_sha256": "2"*64},
                     "log": {"counts": {"error": 0}, "missing_required_text": []},
                     "shutdown": {"stopped": True, "forced": False, "launcher_exit_code": 0},
                     "engine_files": {"/godot": "a"*64}, "resource_sampling": False, "gpu_sampling": False,
                     "orchestrator_sources": {"frame_monitor.py": "d"*64},
                     "frame_watch": {"status": "complete", "identity": watch_id, "coverage_scope": "after arm",
                         "source_changed": False, "thread_alive": False,
                         "source_sha256": {"tools/godtest/frame_monitor.py": "d"*64,
                             "tools/debug/frame_watch.py": "e"*64, "tools/debug/frame_capture.py": "f"*64,
                             "tools/debug/debugctl.py": "a"*64},
                         "report_sha256": hashlib.sha256((watchdir / "watch.json").read_bytes()).hexdigest()}}
        write_json(path / "execution.json", execution)
        (path / "report.html").write_text("case report", encoding="utf-8")
        result = report(path, write=False)
        assert result["data"] == "valid", result["issues"]
        outcomes.append({key: result[key] for key in ("run_dir", "scenario", "aircraft", "execution", "data",
                                                       "coverage", "flight", "performance", "issues")})
    index = {"format": "openrc-godtest-suite-v1", "suite": "performance-tour-v1", "planned_cases": plan,
             "cases": outcomes, "complete": True}
    write_json(suite / "suite.json", index)
    return suite, index


def add_monitors(suite: Path, index: dict):
    """Add hashed offline CPU/GPU artifacts and refresh the recorded case receipts."""
    for entry in index["cases"]:
        path = Path(entry["run_dir"])
        cpu = {"format": "openrc-resource-samples v1", "pid": 42, "identity_status": "verified",
               "required_coverage": "complete", "measurement_status": "ok", "sample_count": 2,
               "interval_seconds": 1, "max_samples": 4000,
               "clock": {"source": "python_perf_counter", "origin_usec": 1_000_000,
                         "start": {"monotonic_usec": 1_000_000, "unix_usec": 1_700_000_000_000_000, "uncertainty_usec": 20_000},
                         "end": {"monotonic_usec": 3_100_000, "unix_usec": 1_700_000_002_100_000, "uncertainty_usec": 20_000}},
               "samples": [{"elapsed_seconds": .01, "poll_overhead_usec": 1000, "cpu_user_seconds": 1, "cpu_system_seconds": 1, "rss_bytes": 100},
                           {"elapsed_seconds": 2.01, "poll_overhead_usec": 1000, "cpu_user_seconds": 1.5, "cpu_system_seconds": 1.2, "rss_bytes": 150}],
               "summary": {"peaks": {"cpu_percent": 48, "num_threads": 4}}, "errors": []}
        required = ("rss_bytes", "cpu_user_seconds", "cpu_system_seconds", "virtual_memory_available_bytes")
        cpu.update(capped=False, stop_reason="caller_finished", required_field_counts={key: 2 for key in required})
        for row in cpu["samples"]:
            row.update(virtual_memory_available_bytes=1_000_000, field_status={key: "ok" for key in required})
        gpu_id = {"key": "nvidia:uuid:GPU-test", "status": "available", "uuid": "GPU-test", "name": "Fixture GPU"}
        gpu_samples = []
        for when, utilization in ((1_100_000, 30), (2_100_000, 40)):
            device = {"backend": "nvidia_smi", "identity": gpu_id, "raw": {"utilization.gpu": str(utilization)},
                      "metrics": {"gpu_utilization_pct": utilization},
                      "metric_status": {"gpu_utilization_pct": "available"},
                      "metric_source": {"gpu_utilization_pct": "utilization.gpu"}}
            backend = {"backend": "nvidia_smi", "start_monotonic_usec": when, "end_monotonic_usec": when + 1000,
                       "status": "available", "reason": None, "devices": [device]}
            gpu_samples.append({"start_monotonic_usec": when, "end_monotonic_usec": when + 1000, "backends": [backend]})
        gpu = {"format": "openrc-godtest-gpu-v1", "status": "available", "thread_alive": False,
               "source_sha256": "c"*64, "source_end_sha256": "c"*64, "source_changed": False,
               "worker_exit_reason": "owner_stopped", "timing_coverage": {"status": "complete"},
               "interval_seconds": 1, "max_samples": 4000, "scope": "whole_device_not_process",
               "clock_domain": "python_time_perf_counter", "start_monotonic_usec": 1_025_000,
               "stop_requested_monotonic_usec": 3_160_000, "stop_monotonic_usec": 3_170_000,
               "sample_count": 2, "sample_cap_reached": False,
               "summary_by_device": {gpu_id["key"]: {"identity": gpu_id, "backend": "nvidia_smi", "samples": 2,
                    "metrics": {"gpu_utilization_pct": {"min": 30, "max": 40, "mean": 35, "count": 2,
                                                         "status_counts": {"available": 2}}}}}, "samples": gpu_samples}
        write_json(path / "resources.json", cpu)
        write_json(path / "gpu.json", gpu)
        execution = read(path / "execution.json")
        execution["orchestrator_sources"]["hardware.py"] = "c"*64
        execution.update(launch={"pid": 42}, resource_sampling=True, gpu_sampling=True,
                         resource_observation={"clock_domain": "python_perf_counter", "interval_seconds": 1, "max_samples": 4000,
                                               "start_requested_usec": 1_000_000, "start_returned_usec": 1_015_000,
                                               "stop_requested_usec": 3_050_000,
                                               "finish_returned_usec": 3_150_000},
                         gpu_observation={"clock_domain": "python_perf_counter", "interval_seconds": 1, "max_samples": 4000,
                                          "start_requested_usec": 1_020_000, "start_returned_usec": 1_030_000,
                                          "stop_requested_usec": 3_160_000, "finish_returned_usec": 3_180_000},
                         resource_sampler_source_sha256="b"*64, resource_sampler_source_changed=False,
                         resources_sha256=hashlib.sha256((path / "resources.json").read_bytes()).hexdigest(),
                         gpu_sha256=hashlib.sha256((path / "gpu.json").read_bytes()).hexdigest())
        write_json(path / "execution.json", execution)
        reduced = report(path, write=False)
        entry.update({key: reduced[key] for key in ("execution", "data", "coverage", "flight", "performance", "issues")})
    write_json(suite / "suite.json", index)


class TourReportTests(unittest.TestCase):
    def test_real_evidence_reduction_and_html_without_promoting_completion(self):
        with tempfile.TemporaryDirectory() as temporary:
            suite, index = fixture(Path(temporary))
            value = report_tour(suite)
            self.assertEqual((value["data"], value["coverage"], value["performance"]), ("valid", "complete", "not_qualified"))
            self.assertFalse(value["hardware_qualified"])
            self.assertEqual(len(value["cases"]), 3)
            self.assertEqual(value["reducer_sha256"], hashlib.sha256(json.dumps(value["reducer_sources"], sort_keys=True).encode()).hexdigest())
            for name in ("tour_report.py", "analysis.py", "render_evidence.py", "resource_coverage.py", "gpu_coverage.py", "pace_windows.py"):
                self.assertEqual(value["reducer_sources"][name], hashlib.sha256(Path(tour_report.__file__).with_name(name).read_bytes()).hexdigest())
            self.assertEqual(len(value["cases"][0]["reducer_sha256"]), 64)
            row = value["cases"][0]["phases"][0]
            self.assertAlmostEqual(row["fps_mean"], 3_000_000 / 46_000)
            self.assertEqual((row["p95_ms"], row["p99_ms"], row["worst_ms"]), (20, 20, 20))
            self.assertEqual(row["low_01pct_status"], "short_sample")
            self.assertIsNone(row["stutter_frames"])
            self.assertEqual(value["cases"][0]["watch"]["stall_frames"], 1)
            self.assertTrue((suite / "report.json").is_file())
            page = (suite / "report.html").read_text()
            self.assertIn("Stutter report", page)
            self.assertIn("short_sample", page)
            self.assertIn("unavailable", page)
            self.assertIn("Startup/loading stay separate", page)
            self.assertEqual(index["planned_cases"][0]["aircraft"], catalog.STIK)

    def test_altered_stream_overrides_forged_suite_and_report_summaries(self):
        with tempfile.TemporaryDirectory() as temporary:
            suite, index = fixture(Path(temporary))
            case = Path(index["cases"][0]["run_dir"])
            (case / "report.json").write_text('{"data":"valid","coverage":"complete"}')
            stream = case / "frames.jsonl"
            stream.write_bytes(stream.read_bytes().replace(b"20000", b"21000", 1))
            result = report_tour(suite, write=False)
            self.assertEqual(result["data"], "ineligible")
            self.assertEqual(result["coverage"], "partial")
            self.assertTrue(any("stale" in issue or "hash" in issue for issue in result["issues"]))

    def test_interrupted_suite_reports_missing_cases(self):
        with tempfile.TemporaryDirectory() as temporary:
            suite, index = fixture(Path(temporary))
            index.update(cases=index["cases"][:1], complete=False)
            write_json(suite / "suite.json", index)
            result = report_tour(suite, write=False)
            self.assertEqual(result["coverage"], "partial")
            self.assertEqual(len(result["cases"]), 1)
            self.assertTrue(any("recorded 1 of 3" in issue for issue in result["issues"]))

    def test_forged_roster_or_omitted_mandatory_phase_cannot_make_a_tour(self):
        for damage in ("remove_phase", "missing_aircraft", "reorder", "instrumentation"):
            with self.subTest(damage=damage), tempfile.TemporaryDirectory() as temporary:
                suite, index = fixture(Path(temporary))
                if damage == "remove_phase":
                    for plan in index["planned_cases"]:
                        plan["phases"].remove("runway_circuit")
                elif damage == "missing_aircraft":
                    index["planned_cases"].pop()
                elif damage == "reorder":
                    index["planned_cases"][0], index["planned_cases"][1] = index["planned_cases"][1], index["planned_cases"][0]
                else:
                    for plan in index["planned_cases"]:
                        plan["watch_frames"] = False
                write_json(suite / "suite.json", index)
                result = report_tour(suite, write=False)
                self.assertNotEqual((result["data"], result["coverage"]), ("valid", "complete"))
                self.assertEqual(result["performance"], "not_qualified")

    def test_manifest_mismatch_and_actual_aircraft_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            suite, index = fixture(Path(temporary))
            case = Path(index["cases"][0]["run_dir"])
            requested = read(case / "manifest.requested.json")
            requested["sample_s"] = 11
            write_json(case / "manifest.requested.json", requested)
            result = report_tour(suite, write=False)
            self.assertTrue(any("manifests" in s for s in result["issues"]))
            requested["sample_s"] = 10
            write_json(case / "manifest.requested.json", requested)
            runtime = read(case / "runtime.json")
            runtime["identity"]["selection"]["aircraft"] = catalog.JET
            write_json(case / "runtime.json", runtime)
            result = report_tour(suite, write=False)
            self.assertTrue(any("actual aircraft" in s for s in result["issues"]))

    def test_loaded_aircraft_receipt_is_required_for_each_field(self):
        for field in ("requested", "flight", "model", "missing"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                suite, index = fixture(Path(temporary))
                path = Path(index["cases"][0]["run_dir"])
                runtime = read(path / "runtime.json")
                if field == "missing":
                    del runtime["identity"]["flight_aircraft"]
                else:
                    runtime["identity"]["flight_aircraft"][field] = catalog.JET
                write_json(path / "runtime.json", runtime)
                result = report_tour(suite, write=False)
                self.assertEqual(result["data"], "ineligible")
                self.assertTrue(any("loaded flight/model" in issue for issue in result["issues"]))

    def test_frozen_source_requires_an_explicit_clean_post_run_receipt(self):
        for damage in ("missing_flag", "missing_list", "changed_flag", "changed_list"):
            with self.subTest(damage=damage), tempfile.TemporaryDirectory() as temporary:
                suite, index = fixture(Path(temporary))
                path = Path(index["cases"][0]["run_dir"])
                execution = read(path / "execution.json")
                if damage == "missing_flag":
                    del execution["source_changed"]
                elif damage == "missing_list":
                    del execution["changed_frozen_files"]
                elif damage == "changed_flag":
                    execution["source_changed"] = True
                else:
                    execution["changed_frozen_files"] = ["app/project.godot"]
                write_json(path / "execution.json", execution)
                result = report_tour(suite, write=False)
                self.assertEqual(result["data"], "ineligible")
                self.assertTrue(any("frozen-source post-run" in issue for issue in result["issues"]))

    def test_reused_case_requires_same_slot_provenance(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            suite, index = fixture(root)
            resumed = root / "resumed"
            resumed.mkdir()
            copy_index = {**copy.deepcopy(index), "source_suite": str(suite)}
            for item in copy_index["cases"]:
                item["reused"] = True
            write_json(resumed / "suite.json", copy_index)
            result = report_tour(resumed)
            self.assertEqual((result["data"], result["coverage"]), ("valid", "complete"))
            self.assertIn("../tour/", (resumed / "report.html").read_text())
            copy_index["cases"][0]["run_dir"] = copy_index["cases"][1]["run_dir"]
            write_json(resumed / "suite.json", copy_index)
            result = report_tour(resumed, write=False)
            self.assertEqual(result["data"], "ineligible")
            self.assertTrue(any("source-suite case" in s for s in result["issues"]))
            copy_index.pop("source_suite")
            write_json(resumed / "suite.json", copy_index)
            with mock.patch.object(tour_report, "report", wraps=report) as child:
                result = report_tour(resumed, write=False)
                self.assertEqual(child.call_count, 0)
            self.assertTrue(any("explicit source_suite" in s for s in result["issues"]))

    def test_duplicate_and_escaping_run_paths_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            suite, index = fixture(Path(temporary))
            index["cases"][1]["run_dir"] = index["cases"][0]["run_dir"]
            write_json(suite / "suite.json", index)
            result = report_tour(suite, write=False)
            self.assertEqual(result["data"], "ineligible")
            self.assertEqual(result["coverage"], "partial")

    def test_frozen_source_change_is_detected_after_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            suite, _ = fixture(Path(temporary))
            (next(suite.glob("001-*/source/app/project.godot"))).write_bytes(b"different")
            result = report_tour(suite, write=False)
            self.assertEqual(result["data"], "ineligible")
            self.assertTrue(any("frozen source or imports" in s for s in result["issues"]))

    def test_missing_watch_or_native_backend_is_not_a_screen(self):
        for damage in ("watch", "native"):
            with self.subTest(damage=damage), tempfile.TemporaryDirectory() as temporary:
                suite, index = fixture(Path(temporary))
                case = Path(index["cases"][0]["run_dir"])
                if damage == "watch":
                    (case / "frame-watch/watch.json").unlink()
                else:
                    runtime = read(case / "runtime.json")
                    runtime["identity"]["backend"] = {"backend": "gdscript_reference"}
                    write_json(case / "runtime.json", runtime)
                result = report_tour(suite, write=False)
                self.assertEqual(result["data"], "ineligible")
                self.assertEqual(result["performance"], "not_qualified")

    def test_repeat_summary_uses_phase_medians_and_rejects_different_hardware(self):
        with tempfile.TemporaryDirectory() as temporary:
            suite, index = fixture(Path(temporary), repeats=2)
            result = report_tour(suite, write=False)
            self.assertEqual((result["data"], result["coverage"]), ("valid", "complete"))
            rows = [r for r in result["repeat_summaries"] if r["aircraft"] == catalog.STIK]
            self.assertEqual([r["phase"] for r in rows].count("home"), 2)
            startup = next(r for r in rows if r["phase"] == "startup")
            self.assertEqual(startup["runs"], 2)
            self.assertEqual(startup["metrics"]["p95_ms"], {"median": 25, "min": 20, "max": 30})
            self.assertEqual(startup["low_01pct_statuses"], ["short_sample", "short_sample"])
            case = Path(index["cases"][3]["run_dir"])
            runtime = read(case / "runtime.json")
            runtime["identity"]["diagnostics"]["adapter_name"] = "other GPU"
            write_json(case / "runtime.json", runtime)
            result = report_tour(suite, write=False)
            self.assertEqual(result["repeat_summaries"], [])
            self.assertEqual(result["performance"], "not_qualified")
            self.assertTrue(any("hardware" in s for s in result["issues"]))

    def test_different_backend_observer_or_host_blocks_a_cross_aircraft_screen(self):
        for changed in ("backend", "cpu_source", "host"):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as temporary:
                suite, index = fixture(Path(temporary))
                add_monitors(suite, index)
                path = Path(index["cases"][1]["run_dir"])
                if changed == "backend":
                    runtime = read(path / "runtime.json")
                    runtime["identity"]["backend"]["binary_sha256"] = "d"*64
                    write_json(path / "runtime.json", runtime)
                else:
                    execution = read(path / "execution.json")
                    if changed == "cpu_source": execution["resource_sampler_source_sha256"] = "d"*64
                    else: execution["host_identity"]["host_sha256"] = "d"*64
                    write_json(path / "execution.json", execution)
                result = report_tour(suite, write=False)
                self.assertEqual((result["data"], result["coverage"]), ("valid", "complete"))
                self.assertEqual(result["performance"], "not_qualified")
                self.assertFalse(_tour_success(result))
                self.assertTrue(any("differs across cases" in issue for issue in result["issues"]))

    def test_missing_engine_or_host_receipts_cannot_qualify_rendered_tour(self):
        for field in ("engine_command_verified", "engine_files_changed", "host_identity"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                suite, index = fixture(Path(temporary))
                path = Path(index["cases"][0]["run_dir"])
                execution = read(path / "execution.json")
                execution.pop(field)
                write_json(path / "execution.json", execution)
                result = report_tour(suite, write=False)
                self.assertEqual(result["data"], "ineligible")
                self.assertFalse(_tour_success(result))

    def test_complete_monitors_enable_screen_and_missing_gpu_does_not_erase_coverage(self):
        with tempfile.TemporaryDirectory() as temporary:
            suite, index = fixture(Path(temporary))
            add_monitors(suite, index)
            result = report_tour(suite, write=False)
            self.assertEqual((result["data"], result["coverage"], result["performance"]), ("valid", "complete", "screen_only"))
            self.assertAlmostEqual(result["cases"][0]["resources"]["cpu_percent_mean"], 35)
            self.assertEqual(result["cases"][0]["gpu"]["status"], "available")
            self.assertFalse(result["hardware_qualified"])
            (Path(index["cases"][0]["run_dir"]) / "gpu.json").unlink()
            result = report_tour(suite, write=False)
            self.assertEqual((result["data"], result["coverage"], result["performance"]), ("valid", "complete", "not_qualified"))
            self.assertTrue(any("monitoring is incomplete" in issue for issue in result["issues"]))

    def test_effective_display_mismatch_rejects_requested_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            suite, index = fixture(Path(temporary))
            path = Path(index["cases"][0]["run_dir"])
            runtime = read(path / "runtime.json")
            runtime["identity"]["effective_display"]["scene_detail"] = "low"
            write_json(path / "runtime.json", runtime)
            result = report_tour(suite, write=False)
            self.assertEqual(result["data"], "ineligible")
            self.assertTrue(any("effective scene_detail" in issue for issue in result["issues"]))

    def test_actual_display_checks_home_final_and_each_completed_phase(self):
        for location in ("home", "final", "phase", "contradictory_code"):
            with self.subTest(location=location), tempfile.TemporaryDirectory() as temporary:
                suite, index = fixture(Path(temporary))
                path = Path(index["cases"][0]["run_dir"])
                runtime = read(path / "runtime.json")
                if location in ("home", "contradictory_code"):
                    state = runtime["identity"]["runtime_display"]
                elif location == "final":
                    state = runtime["identity"]["final_display"]
                else:
                    state = runtime["phases"][2]["runtime_display"]
                # Preferences claim disabled VSync, but the platform ignored it.
                if location == "contradictory_code":
                    state["vsync_mode_code"] = 1
                else:
                    state.update(vsync_mode="enabled", vsync_mode_code=1)
                write_json(path / "runtime.json", runtime)
                result = report_tour(suite, write=False)
                self.assertEqual(result["data"], "ineligible")
                self.assertTrue(any("actual display state" in issue or "actual home display state" in issue
                                    or "actual final display state" in issue for issue in result["issues"]))

    def test_headless_display_is_explicitly_unavailable_and_never_screened(self):
        with tempfile.TemporaryDirectory() as temporary:
            suite, _ = fixture(Path(temporary), headless=True)
            result = report_tour(suite, write=False)
            self.assertEqual((result["data"], result["coverage"], result["performance"]),
                             ("valid", "complete", "not_qualified"))

    def test_macos_run_owned_profile_fields_do_not_change_the_requested_workload(self):
        with tempfile.TemporaryDirectory() as temporary:
            suite, index = fixture(Path(temporary))
            for number, entry in enumerate(index["cases"]):
                path = Path(entry["run_dir"])
                project = "OpenRC-GodTest-" + f"{number+1:032x}"
                user_dir = str(Path(temporary) / project)
                canonical = read(path / "snapshot.json")
                copied = path / "mac-source"
                (copied / "app/.godot/imported").mkdir(parents=True)
                original = (Path(canonical["root"]) / "app/project.godot").read_bytes()
                changed = original.replace(b'config/name="OpenRC Simulator"', f'config/name="{project}"'.encode(), 1)
                (copied / "app/project.godot").write_bytes(changed)
                (copied / "app/.godot/imported/fixture.bin").write_bytes(b"import")
                launch_files = {"app/project.godot": hashlib.sha256(changed).hexdigest()}
                isolation = {"format": "openrc-godtest-macos-profile-v1", "user_dir": user_dir, "project_name": project,
                             "canonical_source_digest": canonical["source_digest"],
                             "original_project_sha256": canonical["files"]["app/project.godot"],
                             "launch_project_sha256": launch_files["app/project.godot"],
                             "changed_settings": ["application/config/name"], "player_profile_touched": False}
                launch = {**canonical, "root": str(copied), "files": launch_files,
                          "source_digest": digest(launch_files), "profile_isolation": isolation}
                write_json(path / "launch-snapshot.json", launch)
                resolved = read(path / "manifest.resolved.json")
                resolved.update(isolated_user_dir=user_dir, isolated_project_name=project)
                write_json(path / "manifest.resolved.json", resolved)
                execution = read(path / "execution.json")
                execution["profile_isolation"] = isolation
                execution["changed_launch_files"] = []
                write_json(path / "execution.json", execution)
                runtime = read(path / "runtime.json")
                runtime["identity"]["user_dir"] = user_dir
                write_json(path / "runtime.json", runtime)
            result = report_tour(suite, write=False)
            self.assertEqual((result["data"], result["coverage"]), ("valid", "complete"))
            path = Path(index["cases"][0]["run_dir"])
            execution = read(path / "execution.json")
            del execution["changed_launch_files"]
            write_json(path / "execution.json", execution)
            result = report_tour(suite, write=False)
            self.assertEqual(result["data"], "ineligible")
            self.assertTrue(any("post-run verification" in issue for issue in result["issues"]))
            execution["changed_launch_files"] = []
            write_json(path / "execution.json", execution)
            (path / "mac-source/app/project.godot").write_bytes(b"modified")
            result = report_tour(suite, write=False)
            self.assertEqual(result["data"], "ineligible")
            self.assertTrue(any("macOS launch project differs" in issue for issue in result["issues"]))

    def test_write_false_does_not_publish(self):
        with tempfile.TemporaryDirectory() as temporary:
            suite, _ = fixture(Path(temporary))
            report_tour(suite, write=False)
            self.assertFalse((suite / "report.json").exists())
            self.assertFalse((suite / "report.html").exists())


if __name__ == "__main__":
    unittest.main()
