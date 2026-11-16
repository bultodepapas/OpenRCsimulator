import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

MODULE = Path(__file__).with_name("package_flight_summary.py")
SPEC = importlib.util.spec_from_file_location("package_flight_summary_draft", MODULE)
summary = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(summary)
sys.path.insert(0, str(Path.cwd() / "tools" / "godot"))
from research.performance.test_native_summary import valid_report, write_stream_run
from test_perfetto_export import resource_report


def evidence():
    package = {"ok": True, "kind": "reference-kind", "sha256": "a" * 64,
               "receipt_sha256": "b" * 64, "executable_sha256": "c" * 64, "pack_sha256": "d" * 64}
    pins = {"format": summary.PINS_FORMAT, "reference_receipt_sha256": "b" * 64,
            "executable_sha256": "c" * 64, "pack_sha256": "d" * 64}
    frame_path = "/tmp/run/flight.json"
    args = ["--frametimes=" + frame_path, "--frametimes-stream", "--package-flight-receipt=/tmp/run/health-flight.json",
            "--physics-backend=gdscript_reference", "--rates=full", "--warmup=30", "--t=120"]
    render = {"backend": "forward_plus", "driver": "metal", "requested": "native", "selected": "native",
              "provider": "native", "fallback": False, "scaling_3d_mode": 0, "scaling_3d_scale": 1.0,
              "msaa_3d": 0, "screen_space_aa": 0, "use_hdr_2d": False, "logical_size": [1920, 1080],
              "window_size": [1920, 1080], "max_fps": 60, "vsync_mode": 1, "camera_view": "pilot",
              "shadow_mode": "sun", "auto_zoom": True}
    frame = {"route": summary.ROUTE, "pid": 42, "capture_id": "sample-id", "aircraft_id": "ugly-stik", "backend": "forward_plus",
             "rendering_driver": "metal", "window_size_at_report": [1920, 1080], "max_fps": 60, "vsync_mode": 1,
             "camera": {"viewport": [1920, 1080], "mode": "pilot", "autozoom": True},
             "render_settings": {"scaling_3d_mode": 0, "scaling_3d_scale": 1.0, "msaa_3d": 0,
                                 "screen_space_aa": 0, "use_hdr_2d": False,
                                 "reconstruction": {"requested": "native", "selected": "native", "provider": "native", "fallback": False}},
             "actual_sample_start_monotonic_usec": 200,
             "actual_sample_end_monotonic_usec": 900, "measured_simulation": {"start_tick": 20, "end_tick": 460}}
    activation = {"radio_connected": False, "controller_service_selected": False, "soundscape_installed": True,
                  "engine_audio_installed": False, "engine_audio_playing": None, "engine_audio_paused": None,
                  "lake_audio_installed": False, "lake_audio_playing": None, "lens_installed": True,
                  "lens_options": {}, "companion_config": {"enabled": False, "count": 1}, "companion_manager_installed": False,
                  "companion_status": None, "weather": {"preset": "calm"}}
    health = {"format": summary.FORMAT, "route": summary.ROUTE, "complete": True, "failure": "",
              "frame_exit_code": 0, "promotion_eligible": False, "capture_id": "sample-id", "pid": 42,
              "frame_report": frame_path, "frame_report_sha256": "e" * 64, "frame_stream_sha256": "f" * 64,
              "package_before": copy.deepcopy(package), "package_after": copy.deepcopy(package),
              "replay_before": {"kind": "reference-kind", "sha256": "a" * 64},
              "replay_after": {"kind": "reference-kind", "sha256": "a" * 64},
              "backend_identity": {"backend": "gdscript_reference"}, "native_checked_ticks": 0,
              "render_scope": render,
              "drawable": {"status": "not_observed", "scope": "native drawable unavailable", "reason": "not_requested"},
              "real_gpu_completion": {"status": "not_observed", "scope": "not observed"},
              "activation_scope": "sampled once per second",
              "initial_checkpoint_sha256": "1" * 64,
              "scenario": {"arguments": args, "weather": {"preset": "calm"}, "aircraft_id": "ugly-stik",
                           "field_id": "default", "seed": 20261021, "rate_profile": "full", "start_choice": "airborne",
                           "frame_generation_requested": False, "display_link_requested": False, "metalfx_trial_requested": False,
                           "drawable_observation_requested": False,
                           "configuration": "3" * 64, "collision_world_identity": "4" * 64,
                           "lake_identity": "5" * 64, "trim": {"ok": True, "V": 15.0, "throttle": 0.5}},
              "observation": {"start_tick": 0, "end_tick": 480, "observer_calls": 480, "input_reads": 480,
                              "last_read_tick": 479, "pilot_updates": 120, "pilot_failure": "",
                              "observer_usec": 123, "input_usec": 234, "pilot_usec": 100,
                              "start_usec": 100, "end_usec": 1000, "dwell_usec": 2_500_000},
              "violations": {name: 0 for name in summary.VIOLATIONS},
              "checkpoints": [{"start_tick": 1, "end_tick": 480, "sha256": "2" * 64, "partial": True}],
              "activation_samples": [{"tick": tick, "monotonic_usec": 100 + tick, "value": copy.deepcopy(activation),
                                       "companion_accepted_ticks": None, "frame_generation_status": None} for tick in (0, 240, 480)],
              "activation_transitions": [{"tick": 0, "monotonic_usec": 101, "value": copy.deepcopy(activation)}]}
    command = ["/tmp/OpenRC.app/Contents/MacOS/OpenRC", "--rendering-method", "forward_plus",
               "--rendering-driver", "metal", "--", *args]
    return health, frame, pins, command


class HealthControls(unittest.TestCase):
    def setUp(self):
        self.health, self.frame, self.pins, self.command = evidence()

    def errors(self):
        return summary._health_errors(self.health, self.frame, "e" * 64, "f" * 64, self.pins)

    def test_complete_reference_fixture(self):
        self.assertEqual([], self.errors())
        self.assertEqual([], summary._command_errors(self.command, self.frame, self.health))

    def test_package_and_stream_identity_mutations_are_rejected(self):
        for field in ("frame_report_sha256", "frame_stream_sha256", "initial_checkpoint_sha256"):
            with self.subTest(field=field):
                self.health[field] = "0" * 63
                self.assertTrue(self.errors())
                self.health, self.frame, self.pins, self.command = evidence()
        self.health["package_after"]["pack_sha256"] = "0" * 64
        self.assertTrue(self.errors())
        self.health, self.frame, self.pins, self.command = evidence()
        self.pins["executable_sha256"] = "0" * 64
        self.assertTrue(self.errors())

    def test_pilot_is_the_exact_frozen_existing_adapter(self):
        bundled = MODULE.parents[2] / "app" / "tools" / "package_flight_input.gd"
        source = MODULE.parents[2] / "research" / "performance" / "sustained_input.gd"
        source_bytes = source.read_bytes()
        self.assertEqual(source_bytes, bundled.read_bytes())
        # Check the repository's LF bytes even on Windows CRLF checkouts.
        self.assertEqual(hashlib.sha256(source_bytes.replace(b"\r\n", b"\n")).hexdigest(),
                         "15cde7b99cc7cb1f45d8bcf2e4f9b079e752688216684aa87ab1045d9039b3a5")

    def test_step_checks_clock_before_overwriting_it(self):
        observer = MODULE.parents[2] / "app" / "tools" / "package_flight_observer.gd"
        code = observer.read_text(encoding="utf-8").split("func _on_stepped(", 1)[1].split("\nfunc ", 1)[0]
        self.assertLess(code.index("_tick_gap_invalid(last_tick_usec, began)"), code.index("last_tick_usec = began"))

    def test_unavailable_output_or_gpu_proof_cannot_be_claimed(self):
        for field in ("drawable", "real_gpu_completion"):
            with self.subTest(field=field):
                self.health[field]["status"] = "observed"
                self.assertTrue(self.errors())
                self.health, self.frame, self.pins, self.command = evidence()

    def test_ordinary_drawable_boundaries_require_unchanged_scope_extent_and_coverage(self):
        before = {"status": "observed", "owner": "ordinary", "evidence": "acquired_framebuffer_texture_not_scanout",
                  "scope": 3, "attempts": 10, "observed": 10, "missed": 0, "changes": 0,
                  "width": 1920, "height": 1080, "pixel_format": 80, "query_before_usec": 150, "query_after_usec": 160}
        after = dict(before, attempts=60, observed=60, query_before_usec=910, query_after_usec=920)
        self.health["scenario"]["drawable_observation_requested"] = True
        self.health["drawable"] = {"status": "observed", "scope": "acquired only", "before": before, "after": after}
        self.assertEqual([], self.errors())
        self.assertTrue(summary._drawable_observation(self.health, self.frame)["actual_1080p"])
        for key, value in (("scope", 4), ("changes", 1), ("missed", 1), ("width", 1280),
                           ("pixel_format", 81), ("query_before_usec", 899), ("owner", "display_link"),
                           ("observed", 10), ("attempts", -1), ("query_after_usec", 909)):
            with self.subTest(key=key):
                original = after[key]
                after[key] = value
                self.assertTrue(self.errors())
                after[key] = original
        self.health["scenario"]["display_link_requested"] = True
        self.assertTrue(self.errors())
        self.health["scenario"]["display_link_requested"] = False
        self.health["scenario"]["drawable_observation_requested"] = False
        self.assertTrue(self.errors())

    def test_non_1080_acquired_drawable_stays_valid_but_not_primary(self):
        before = {"status": "observed", "owner": "ordinary", "evidence": "acquired_framebuffer_texture_not_scanout",
                  "scope": 3, "attempts": 10, "observed": 10, "missed": 0, "changes": 0,
                  "width": 1280, "height": 720, "pixel_format": 80, "query_before_usec": 150, "query_after_usec": 160}
        after = dict(before, attempts=60, observed=60, query_before_usec=910, query_after_usec=920)
        self.health["scenario"]["drawable_observation_requested"] = True
        self.health["drawable"] = {"status": "observed", "scope": "acquired only", "before": before, "after": after}
        self.assertEqual([], self.errors())
        self.assertFalse(summary._drawable_observation(self.health, self.frame)["actual_1080p"])

    def test_tick_loss_pause_bad_counter_and_coverage_fail(self):
        for mutation in (lambda h: h["observation"].update(input_reads=479),
                         lambda h: h["observation"].update(end_tick=True),
                         lambda h: h["observation"].update(pilot_updates=119),
                         lambda h: h["violations"].update(pause=1),
                         lambda h: h["violations"].pop("hold"),
                         lambda h: h.update(native_checked_ticks=False),
                         lambda h: h["render_scope"].update(fallback=True),
                         lambda h: h["render_scope"].update(window_size=[1280, 720]),
                         lambda h: h["observation"].update(end_usec=899)):
            with self.subTest(mutation=mutation):
                h, frame, pins, _ = evidence()
                mutation(h)
                self.assertTrue(summary._health_errors(h, frame, "e" * 64, "f" * 64, pins))

    def test_flight_local_render_scope_is_typed_and_joined_to_camera(self):
        for field, value in (("shadow_mode", None), ("shadow_mode", "unexpected"),
                             ("auto_zoom", None), ("auto_zoom", 1), ("auto_zoom", False)):
            with self.subTest(field=field, value=value):
                h, frame, pins, _ = evidence()
                h["render_scope"][field] = value
                self.assertTrue(summary._health_errors(h, frame, "e" * 64, "f" * 64, pins))
        for value in (None, 1, False):
            h, frame, pins, _ = evidence()
            frame["camera"]["autozoom"] = value
            self.assertTrue(summary._health_errors(h, frame, "e" * 64, "f" * 64, pins))

    def test_transient_scope_or_external_input_failure_survives_restored_endpoint(self):
        for violation in ("render_scope", "input_ownership"):
            h, frame, pins, _ = evidence()
            h["violations"][violation] = 1
            # The final values match the initial ones; a latched violation still refuses the run.
            self.assertTrue(summary._health_errors(h, frame, "e" * 64, "f" * 64, pins))

    def test_incomplete_checkpoint_and_activation_evidence_fails(self):
        for mutation in (lambda h: h["checkpoints"][0].update(start_tick=2),
                         lambda h: h["checkpoints"][0].update(partial=False),
                         lambda h: h["activation_samples"].pop(),
                         lambda h: h["activation_samples"][1]["value"].update(radio_connected=True),
                         lambda h: h["activation_samples"][1]["value"]["weather"].update(preset="wind"),
                         lambda h: h["activation_samples"][1].pop("frame_generation_status"),
                         lambda h: h["activation_samples"][1].update(monotonic_usec=1001),
                         lambda h: h["activation_samples"][1]["value"]["companion_config"].update(enabled=True),
                         lambda h: h["activation_transitions"].clear()):
            with self.subTest(mutation=mutation):
                h, frame, pins, _ = evidence()
                mutation(h)
                self.assertTrue(summary._health_errors(h, frame, "e" * 64, "f" * 64, pins))

    def test_companion_stall_is_not_counted_as_active(self):
        for row in self.health["activation_samples"]:
            row["value"]["companion_manager_installed"] = True
            row["value"]["companion_config"]["enabled"] = True
            row["value"]["companion_status"] = {"active": 1, "airborne": 1, "requested": 1,
                                                "faulted": 0, "crashed": 0, "removed": False}
            row["companion_accepted_ticks"] = 0
        self.health["activation_transitions"][0]["value"] = copy.deepcopy(self.health["activation_samples"][0]["value"])
        self.assertTrue(any("companion ticks" in item for item in self.errors()))

    def test_native_receipt_requires_exact_backend_and_tick_coverage(self):
        native_package = {"ok": True, "kind": "native-kind", "sha256": "7" * 64,
                          "receipt_sha256": "8" * 64, "reference_identity": self.health["package_before"]}
        native_backend = {"backend": "native", "abi_version": 2}
        self.health["package_before"] = copy.deepcopy(native_package)
        self.health["package_after"] = copy.deepcopy(native_package)
        self.health["replay_before"] = {"kind": "native-kind", "sha256": "7" * 64, "stage_backend": native_backend}
        self.health["replay_after"] = copy.deepcopy(self.health["replay_before"])
        self.health["backend_identity"] = native_backend
        self.health["native_checked_ticks"] = 480
        self.pins["native_receipt_sha256"] = "8" * 64
        self.assertEqual([], self.errors())
        self.health["native_checked_ticks"] = 479
        self.assertTrue(self.errors())
        self.health["native_checked_ticks"] = 480
        self.health["replay_before"]["stage_backend"]["abi_version"] = 3
        self.assertTrue(self.errors())

    def test_scripted_headless_wrong_receipt_and_duplicate_arguments_fail(self):
        for option in ("--script=foreign.gd", "--fixed-fps=60", "--headless", "--gpu-profile"):
            with self.subTest(option=option):
                command = self.command[:1] + [option] + self.command[1:]
                self.assertTrue(summary._command_errors(command, self.frame, self.health))
        command = self.command[:1] + ["--display-driver", "headless"] + self.command[1:]
        self.assertTrue(summary._command_errors(command, self.frame, self.health))
        for suffix in (["--scripted"], ["--rates=full"], ["--package-flight-receipt=/tmp/other.json"]):
            with self.subTest(suffix=suffix):
                command = self.command + suffix
                h = copy.deepcopy(self.health)
                h["scenario"]["arguments"] = command[command.index("--") + 1:]
                self.assertTrue(summary._command_errors(command, self.frame, h))


class JoinedReceiptControls(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.health, _, self.pins, _ = evidence()
        ticks = [7200 + 3 * index for index in range(9600)]
        report = valid_report(interval_usec=12500, ticks=ticks, sample_s=120.0,
                              warmup_s=30.0, actual_warmup_s=30.0, route=summary.ROUTE)
        report["frame_end_monotonic_usec"] = [time + 30_000_000 for time in report["frame_end_monotonic_usec"]]
        clock_epoch = 1_700_000_000_000_000
        report.update(capture_id="sample-id", pid=42, os="macOS", architecture="arm64", backend="forward_plus",
                      rendering_driver="metal", window_size_at_report=[1920, 1080], max_fps=60, vsync_mode=1, vsync=True,
                      camera={"viewport": [1920, 1080], "mode": "pilot", "autozoom": True},
                      render_settings={"scaling_3d_mode": 0, "scaling_3d_scale": 1.0, "msaa_3d": 0,
                                       "screen_space_aa": 0, "use_hdr_2d": False,
                                       "reconstruction": {"requested": "native", "selected": "native", "provider": "native", "fallback": False}},
                      session_at_report={"scope": "endpoint", "pause_reason": "", "holds": [], "crashed": False, "window_focused": True},
                      clock={"source": "godot_ticks_usec", "origin_usec": 0,
                             "start": {"monotonic_usec": 900_000, "unix_usec": clock_epoch + 900_000, "uncertainty_usec": 20_000},
                             "end": {"monotonic_usec": 153_000_000, "unix_usec": clock_epoch + 153_000_000, "uncertainty_usec": 20_000}})
        self.path, _ = write_stream_run(self.directory, "flight", report)
        frame = json.loads(self.path.read_text())
        frame_bytes = self.path.read_bytes()
        self.health["scenario"].update(aircraft_id=frame["aircraft_id"])
        self.health["frame_report_sha256"] = hashlib.sha256(frame_bytes).hexdigest()
        self.health["frame_stream_sha256"] = frame["stream"]["sha256"]
        self.health["observation"].update(end_tick=36000, observer_calls=36000, input_reads=36000, last_read_tick=35999,
                                           pilot_updates=9000, start_usec=100, end_usec=152_000_000)
        self.health["checkpoints"] = [{"start_tick": start, "end_tick": start + 5999, "sha256": "2" * 64, "partial": False}
                                      for start in range(1, 36001, 6000)]
        initial = self.health["activation_samples"][0]["value"]
        self.health["activation_samples"] = [{"tick": tick, "monotonic_usec": 100 + tick * 1_000_000 // 240,
                                               "value": copy.deepcopy(initial), "companion_accepted_ticks": None,
                                               "frame_generation_status": None}
                                              for tick in range(0, 36001, 240)]
        self.health_path = self.directory / "health-flight.json"
        self.health_path.write_text(json.dumps(self.health), encoding="utf-8")
        log = b"PACKAGE_FLIGHT verdict=collected capture_id=sample-id\n"
        self.path.with_suffix(".log").write_bytes(log)
        command = ["/evidence/OpenRC.app/Contents/MacOS/OpenRC", "--rendering-method", "forward_plus",
                   "--rendering-driver", "metal", "--", *self.health["scenario"]["arguments"]]
        # The retained paths describe the original Mac run; the reader rebases only the checked hierarchy.
        self.health["frame_report"] = "/evidence/flight.json"
        self.health["scenario"]["arguments"][0] = "--frametimes=/evidence/flight.json"
        self.health["scenario"]["arguments"][2] = "--package-flight-receipt=/evidence/health-flight.json"
        command = command[:command.index("--") + 1] + self.health["scenario"]["arguments"]
        self.health_path.write_text(json.dumps(self.health), encoding="utf-8")
        self.capture = self.directory / "checks" / "godot-fixture"
        self.capture.mkdir(parents=True)
        (self.capture / "engine.log").write_bytes(log)
        self.checked = {"format": "openrc-godot-check v1", "capture_id": "sample-id", "command": command,
                        "cwd": "/frozen", "started_utc": "2023-11-14T22:13:20+00:00", "elapsed_seconds": 155.0,
                        "process_exit": 0, "reason": "passed", "ok": True, "complete": True,
                        "report": "/evidence/checks/godot-fixture/report.json",
                        "log": "/evidence/checks/godot-fixture/engine.log", "log_sha256": hashlib.sha256(log).hexdigest()}
        clock = {"source": "python_perf_counter", "origin_usec": 0,
                 "start": {"monotonic_usec": 0, "unix_usec": clock_epoch, "uncertainty_usec": 20_000},
                 "end": {"monotonic_usec": 155_000_000, "unix_usec": clock_epoch + 155_000_000, "uncertainty_usec": 20_000}}
        self.sampled = resource_report(capture_id="sample-id", clock=clock, elapsed=tuple(range(155)))
        self.sampled.update(pid=42, process_create_time=1_700_000_000.0, identity_status="verified",
                            interval_seconds=1.0, max_samples=200, required_coverage="complete",
                            summary={"counter_resets": []},
                            tool_source_sha256={"run_checked.py": "a" * 64, "resource_samples.py": "b" * 64})
        for sample in self.sampled["samples"]: sample["poll_overhead_usec"] = 1000
        self.sampled["required_field_counts"] = {field: 155 for field in (
            "rss_bytes", "cpu_user_seconds", "cpu_system_seconds", "virtual_memory_available_bytes")}
        self.sampled["invocation"] = {key: self.checked[key] for key in (
            "capture_id", "command", "cwd", "started_utc", "process_exit", "reason", "log_sha256", "elapsed_seconds")}
        self.save()

    def save(self):
        blob = (json.dumps(self.sampled) + "\n").encode()
        (self.capture / "resources.json").write_bytes(blob)
        self.checked["resources"] = {"file": "resources.json", "published": True, "bytes": len(blob),
                                     "sha256": hashlib.sha256(blob).hexdigest(),
                                     **{key: self.sampled[key] for key in ("coverage", "required_coverage", "sample_count", "measurement_status", "summary")}}
        checked = (json.dumps(self.checked) + "\n").encode()
        (self.directory / "checked-flight.json").write_bytes(checked)
        (self.capture / "report.json").write_bytes(checked)

    def test_complete_join_never_promotes(self):
        result = summary.reduce_run(self.path, self.pins, minimum_seconds=120)
        self.assertTrue(result["collection_valid"])
        self.assertFalse(result["promotion_eligible"])
        self.assertIn("actual 1080p acquired drawable", result["unresolved"])

    def test_resource_tamper_and_runner_replacement_fail(self):
        self.assertTrue(summary.reduce_run(self.path, self.pins, minimum_seconds=120)["collection_valid"])
        resource_path = self.capture / "resources.json"
        resource_path.write_bytes(resource_path.read_bytes() + b" ")
        with self.assertRaisesRegex(ValueError, "resource attachment hash"):
            summary.reduce_run(self.path, self.pins, minimum_seconds=120)
        self.save()
        (self.capture / "report.json").write_bytes(b"{}")
        with self.assertRaisesRegex(ValueError, "copied checked receipt"):
            summary.reduce_run(self.path, self.pins, minimum_seconds=120)

    def test_stream_bytes_must_match_report(self):
        stream = self.path.with_name(self.path.name + ".frames.jsonl")
        stream.write_bytes(stream.read_bytes() + b" ")
        with self.assertRaisesRegex(ValueError, "stream byte count"):
            summary.reduce_run(self.path, self.pins, minimum_seconds=120)

    def test_short_data_does_not_satisfy_soak(self):
        with self.assertRaisesRegex(ValueError, "duration"):
            summary.reduce_run(self.path, self.pins, minimum_seconds=1800)


if __name__ == "__main__":
    unittest.main()
