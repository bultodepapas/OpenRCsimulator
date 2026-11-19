from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock
from types import SimpleNamespace

import catalog
from analysis import compare, report, validate_stream
from godtest import parser, plan
from runner import environment, write_json
import runner


def artifacts(directory: Path, *, rendered=True, complete=True):
    directory.mkdir(parents=True)
    manifest = catalog.scenario("startup", {"headless": not rendered})
    manifest["output_dir"] = str(directory)
    write_json(directory / "manifest.resolved.json", manifest)
    rows = [dict(type="header", format="openrc-frame-stream v1"),
            dict(type="chunk", sequence=0, start_frame=0, frames=2, wall_usec=[16000, 17000], end_usec=[1016000, 1033000], engine_delta_s=[.016, .017], metrics={"phase_index": [0, 0]}),
            dict(type="trailer", complete=complete, frames=2, chunks=1)]
    raw = b"".join((json.dumps(item) + "\n").encode() for item in rows)
    (directory / "frametimes.json.frames.jsonl").write_bytes(raw)
    frames = dict(format="openrc-godtest-frames-v1", completion_kind="scenario_event", complete=complete, frames=2,
                  stream=dict(file="frametimes.json.frames.jsonl", frames=2, chunks=1, complete=complete, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest()))
    write_json(directory / "frametimes.json", frames)
    diagnostic = {key: "matched" for key in ("cpu_model", "adapter_name", "adapter_vendor", "adapter_api_version", "os_name", "os_version", "rendering_method", "rendering_driver", "vsync_mode", "max_fps", "reconstruction_at_start")}
    phase = dict(name="startup", id="0-0-startup", index=0, cycle=0, requested=True, status="complete", reason="", start_usec=1000000, end_usec=1033000, start_tick=-1, end_tick=-1, wall_seconds=.033, sim_seconds=0, frames=2, rendered=rendered, frame_ms=dict(p50=16, p95=17, p99=17, max=17))
    runtime = dict(format="openrc-godtest-runtime-v1", complete=complete, execution="completed", data="complete" if complete else "partial", coverage="complete", flight="not_run", phases=[phase], metrics=dict(rendered=rendered, requested_resolution_match=True), identity=dict(actual_resolution=[1920, 1080], viewport_size=[1920, 1080], selection={}, backend={}, scenery_sha256="same", field={}, diagnostics=diagnostic))
    write_json(directory / "runtime.json", runtime)
    write_json(directory / "execution.json", dict(state="runtime_finished", failure="", source_changed=False, log=dict(counts=dict(error=0, warning=0), missing_required_text=[]), shutdown=dict(stopped=True, forced=False, launcher_exit_code=0), engine_files={"godot": "same"}))
    return frames


def replace_stream(directory, frames, walls, phases, split=512):
    """Build real framed inputs with matching receipts for reducer boundary tests."""
    ends, end = [], 1_000_000
    for wall in walls:
        end += wall
        ends.append(end)
    rows = [dict(type="header", format="openrc-frame-stream v1")]
    for start in range(0, len(walls), split):
        stop = min(start + split, len(walls))
        metrics = {} if phases is None else {"phase_index": phases[start:stop]}
        rows.append(dict(type="chunk", sequence=len(rows)-1, start_frame=start, frames=stop-start,
                         wall_usec=walls[start:stop], end_usec=ends[start:stop],
                         engine_delta_s=[w/1_000_000 for w in walls[start:stop]], metrics=metrics))
    chunks = len(rows)-1
    rows.append(dict(type="trailer", complete=True, frames=len(walls), chunks=chunks))
    raw = b"".join((json.dumps(row) + "\n").encode() for row in rows)
    (directory / frames["stream"]["file"]).write_bytes(raw)
    frames["frames"] = len(walls)
    frames["stream"].update(frames=len(walls), chunks=chunks, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
    write_json(directory / "frametimes.json", frames)


class ManifestTests(unittest.TestCase):
    def test_enrolled_resume_is_refused_before_reading_or_retrying_cases(self):
        import godtest
        from tools.testqueue import common
        with mock.patch.object(common, "enabled", return_value=True), \
                mock.patch.object(common, "inherited", return_value=False), \
                mock.patch.object(godtest, "resume_suite") as resume:
            self.assertEqual(godtest.main(["resume", "missing-suite", "--out", "unused"]), 2)
            resume.assert_not_called()

    def test_rejects_nonfinite_bool_and_unknown_fields(self):
        for overrides in ({"timeout_s": float("nan")}, {"cycles": True}, {"surprise": 1}, {"seed": -1}, {"resolution": [720, 1280]}, {"phases": ["pretend"]}, {"id": "../outside"}, {"landscape": "green_paradise", "phases": ["flag"]}):
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                catalog.scenario("smoke", overrides)

    def test_unsupported_aircraft_maneuvers_and_isolated_landing_refused(self):
        with self.assertRaisesRegex(ValueError, "profile"):
            catalog.scenario("ugly-standard", {"aircraft": catalog.JET})
        with self.assertRaisesRegex(ValueError, "isolated"):
            catalog.scenario("ugly-standard", {"entry": "isolated"})

    def test_full_route_contains_both_landmarks_and_pause(self):
        value = catalog.scenario("ugly-standard")
        for required in ("farmhouse", "flag", "pause", "roll", "large_loop", "landing", "stop", "environment"):
            self.assertIn(required, value["phases"])
        self.assertEqual(value["resolution"], [1920, 1080])

    def test_partial_continuous_includes_dependencies(self):
        args = parser().parse_args(["run", "ugly-standard", "--phase", "pause", "--dry-run"])
        value = plan(args)[0]
        self.assertIn("farmhouse", value["phases"])
        self.assertIn("flag", value["phases"])
        self.assertNotIn("roll", value["phases"])

    def test_suites_expand_and_reject_unsupported_combination(self):
        self.assertEqual(len(plan(parser().parse_args(["all", "--dry-run"]))), len(catalog.ALL_V1))
        self.assertEqual(len(plan(parser().parse_args(["fleet", "--dry-run"]))), len(catalog.AIRCRAFT))
        with self.assertRaises(ValueError):
            plan(parser().parse_args(["all", "--start", "runway"]))

    def test_environment_restored_after_exception(self):
        name = "OPENRC_GODTEST_UNIT_TEST"
        previous = os.environ.get(name)
        with self.assertRaises(RuntimeError):
            with environment({name: "temporary"}):
                self.assertEqual(os.environ[name], "temporary")
                raise RuntimeError("expected")
        self.assertEqual(os.environ.get(name), previous)


class ArtifactTests(unittest.TestCase):
    def test_phase_pacing_uses_assigned_intervals_and_breaks_runs_at_phase_changes(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / "run"
            frames = artifacts(directory)
            replace_stream(directory, frames, [20_000, 20_000, 10_000, 20_000], [0, 0, 1, 0], split=2)
            value = validate_stream(directory, frames)
            phase = value["phase_pacing"]["0"]
            self.assertEqual((phase["frames"], phase["sample_wall_ms"], phase["fps_mean"]), (3, 60, 50))
            slow = value["phase_hitches"]["0"]["16.667"]
            self.assertEqual((slow["frames"], slow["runs"], slow["max_consecutive"]), (3, 2, 2))
            self.assertEqual((slow["max_run_ms"], slow["slow_time_ms"], slow["slow_time_percent"]), (40, 60, 100))
            self.assertEqual(value["phase_hitches"]["1"]["16.667"]["frames"], 0)

    def test_phase_slow_share_is_time_weighted_and_equality_is_within_budget(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / "run"
            frames = artifacts(directory)
            replace_stream(directory, frames, [20_000, 10_000, 20_000], [0, 0, 0])
            value = validate_stream(directory, frames)
            slow = value["phase_hitches"]["0"]["16.667"]
            self.assertEqual(slow["slow_time_percent"], 80)
            self.assertAlmostEqual(slow["over_budget_percent"], 200/3)
            self.assertEqual(value["phase_pacing"]["0"]["fps_mean"], 60)
            replace_stream(directory, frames, [16_667, 16_668], [0, 0])
            self.assertEqual(validate_stream(directory, frames)["phase_hitches"]["0"]["16.667"]["frames"], 1)

    def test_missing_phase_channel_never_becomes_zero_ms_or_a_pass(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / "run"
            frames = artifacts(directory)
            replace_stream(directory, frames, [16_000, 17_000], None)
            with self.assertRaisesRegex(ValueError, "phase_index"):
                validate_stream(directory, frames)
            runtime = json.loads((directory / "runtime.json").read_text())
            runtime["phases"][0].update(name="takeoff", frame_statistics="offline_from_verified_stream")
            write_json(directory / "runtime.json", runtime)
            value = report(directory)
            self.assertEqual(value["data"], "ineligible")
            self.assertIsNone(value["phases"][0]["frame_ms"]["p95"])
            self.assertIsNone(value["targets"][0]["p95_within_18ms"])
            self.assertEqual(value["targets"][0]["pacing_target"], "unavailable")
            self.assertIn("unavailable", (directory / "report.html").read_text())
            self.assertFalse(compare(directory, directory, "startup")["eligible"])

    def test_completed_phase_without_samples_is_ineligible(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / "run"
            artifacts(directory)
            runtime = json.loads((directory / "runtime.json").read_text())
            runtime["phases"][0].update(index=1, frames=0, frame_statistics="offline_from_verified_stream")
            write_json(directory / "runtime.json", runtime)
            value = report(directory)
            self.assertEqual(value["data"], "ineligible")
            self.assertEqual(value["phases"][0]["pacing"], {})
            self.assertTrue(any("no verified frame samples" in issue for issue in value["issues"]))

    def test_report_uses_verified_reduction_instead_of_supplied_zero_statistics(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / "run"
            frames = artifacts(directory)
            replace_stream(directory, frames, [40_000, 50_000], [0, 0])
            runtime = json.loads((directory / "runtime.json").read_text())
            runtime["phases"][0]["frame_ms"] = dict(p50=0, p95=0, p99=0, max=0)
            write_json(directory / "runtime.json", runtime)
            value = report(directory)
            self.assertEqual(value["phases"][0]["frame_ms"]["p95"], 50)

    def test_runway_excursion_is_visible_without_erasing_performance(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / "run"
            artifacts(directory)
            runtime = json.loads((directory / "runtime.json").read_text())
            stop = dict(runtime["phases"][0], name="stop", id="0-1-stop", requested=False,
                        pilot=dict(touchdown={"roll_deg": 2}, minimum_wheel_runway_margin_m=-4.5))
            runtime["phases"].append(stop)
            write_json(directory / "runtime.json", runtime)
            value = report(directory)
            self.assertEqual(value["data"], "valid")
            self.assertTrue(value["flight_observations"][0]["wheel_outside_runway_observed"])
            self.assertIn("outside the runway", (directory / "report.html").read_text())

    def test_valid_stream_and_report(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / "run"
            frames = artifacts(directory)
            self.assertTrue(validate_stream(directory, frames)["valid"])
            value = report(directory)
            self.assertEqual(value["data"], "valid")
            self.assertFalse(value["hardware_qualified"])
            self.assertTrue((directory / "report.html").is_file())

    def test_corruption_and_truncated_prefix_are_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / "run"
            frames = artifacts(directory)
            path = directory / frames["stream"]["file"]
            raw = path.read_bytes()
            path.write_bytes(raw.replace(b"17000", b"18000"))
            with self.assertRaises(ValueError): validate_stream(directory, frames)
            path.write_bytes(b"\n".join(raw.splitlines()[:-1]) + b"\n")
            with self.assertRaisesRegex(ValueError, "prefix"): validate_stream(directory, frames)

    def test_valid_hash_cannot_hide_clock_discontinuity(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / "run"
            frames = artifacts(directory)
            path = directory / frames["stream"]["file"]
            raw = path.read_bytes().replace(b"1033000", b"1034000")
            path.write_bytes(raw)
            frames["stream"].update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
            with self.assertRaisesRegex(ValueError, "noncontiguous"): validate_stream(directory, frames)

    def test_partial_data_and_forced_shutdown_are_not_passes(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / "run"
            artifacts(directory, complete=False)
            self.assertEqual(report(directory)["data"], "ineligible")
            other = Path(root) / "other"
            artifacts(other)
            execution = json.loads((other / "execution.json").read_text())
            execution["shutdown"]["forced"] = True
            write_json(other / "execution.json", execution)
            self.assertEqual(report(other)["data"], "ineligible")

    def test_comparison_admits_only_matched_complete_transitions(self):
        with tempfile.TemporaryDirectory() as root:
            left, right = Path(root) / "left", Path(root) / "right"
            artifacts(left)
            artifacts(right)
            self.assertTrue(compare(left, right, "startup")["eligible"])
            self.assertFalse(compare(left, right)["eligible"])
            runtime = json.loads((right / "runtime.json").read_text())
            runtime["identity"]["actual_resolution"] = [1280, 720]
            write_json(right / "runtime.json", runtime)
            self.assertFalse(compare(left, right, "startup")["eligible"])


class SupervisionTests(unittest.TestCase):
    def test_reuse_receipt_rejects_escaping_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt = dict(format="openrc-godtest-source-v1", root=str(root), files={"app/project.godot": "0"*64, "../outside": "0"*64}, imports={})
            with self.assertRaisesRegex(ValueError, "invalid snapshot"):
                runner.check_frozen(receipt)

    def test_frozen_inputs_survive_live_edits_and_detect_snapshot_edits(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            files = {"app/project.godot": b"project", "research/performance/sustained_input.gd": b"input", "app/.godot/imported/fixture.ctex": b"import"}
            for relative, raw in files.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
            output = root / "output"
            output.mkdir()
            identity = {"files": {"app/project.godot": hashlib.sha256(b"project").hexdigest()}}
            with mock.patch.object(runner, "ROOT", root):
                frozen = runner.freeze_inputs(output, identity)
                (root / "app/project.godot").write_bytes(b"independent developer edit")
                self.assertEqual(runner.check_frozen(frozen), [])
                (Path(frozen["root"]) / "app/project.godot").write_bytes(b"bad frozen edit")
                self.assertEqual(runner.check_frozen(frozen), ["app/project.godot"])

    def test_early_process_exit_stops_only_the_owned_session(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            engine = root / "engine.bin"
            engine.write_bytes(b"engine")
            stopped = []
            def launch(arguments):
                self.assertNotIn("--", arguments)
                self.assertIn("--profile", arguments)
                print(json.dumps(dict(ok=True, port=49001, pid=10001)))
                return 0
            def stop(arguments):
                stopped.append((os.environ.get("OPENRC_DEBUG_BRIDGE"), arguments))
                print(json.dumps(dict(stopped=True, forced=False, launcher_exit_code=0)))
                return 0
            bridge = SimpleNamespace(launch=launch, stop=stop, godot=lambda: str(engine), alive=lambda pid: False, session_for=lambda port: dict(command=[str(engine)]))
            identity = dict(files={}, digest="same", commit="fixture")
            frozen = dict(root=str(root / "source"), files={}, imports={})
            with mock.patch.object(runner, "ROOT", root), mock.patch.object(runner, "source_identity", return_value=identity), mock.patch.object(runner, "freeze_inputs", return_value=frozen), mock.patch.object(runner, "check_frozen", return_value=[]), mock.patch.object(runner, "_bridge", return_value=bridge):
                path, result = runner.run(catalog.scenario("smoke", {"headless": True}), root / "run")
            self.assertIn("exited before", result["failure"])
            self.assertEqual(stopped, [("49001", [])])
            self.assertTrue((path / "execution.json").is_file())

    def test_headless_cannot_establish_rendered_comparison(self):
        with tempfile.TemporaryDirectory() as root:
            left, right = Path(root) / "left", Path(root) / "right"
            artifacts(left, rendered=False)
            artifacts(right, rendered=False)
            self.assertFalse(compare(left, right, "startup")["eligible"])

    def test_busy_progress_read_does_not_cancel_a_completed_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            engine = root / "engine.bin"
            engine.write_bytes(b"engine")
            output = root / "run"
            def launch(arguments):
                print(json.dumps(dict(ok=True, port=49002, pid=10002)))
                return 0
            def stop(arguments):
                print(json.dumps(dict(stopped=True, forced=False, launcher_exit_code=0)))
                return 0
            def progress_busy(path, *args, **kwargs):
                raise PermissionError("Windows replacement is temporarily busy")
            def complete_after_retry(seconds):
                write_json(output / "runtime.json", {"complete": True})
            bridge = SimpleNamespace(launch=launch, stop=stop, godot=lambda: str(engine), alive=lambda pid: True, session_for=lambda port: dict(command=[str(engine)]))
            identity = dict(files={}, digest="same", commit="fixture")
            frozen = dict(root=str(root / "source"), files={}, imports={})
            with mock.patch.object(runner, "ROOT", root), mock.patch.object(runner, "source_identity", return_value=identity), mock.patch.object(runner, "freeze_inputs", return_value=frozen), mock.patch.object(runner, "check_frozen", return_value=[]), mock.patch.object(runner, "_bridge", return_value=bridge), mock.patch.object(runner, "read_json", side_effect=progress_busy), mock.patch.object(runner.time, "sleep", side_effect=complete_after_retry):
                path, result = runner.run(catalog.scenario("smoke", {"headless": True}), output)
            self.assertEqual(result["failure"], "")
            self.assertEqual(result["state"], "runtime_finished")
            self.assertEqual(result["progress_read_retries"], 1)


if __name__ == "__main__":
    unittest.main()
