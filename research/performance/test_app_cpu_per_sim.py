"""Portable CPU accounting contracts; no game or timing benchmark is launched."""
from contextlib import redirect_stdout
import io
import json
import math
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock
import uuid

import app_cpu_per_sim as bench


class AccessDenied(Exception):
    pass


class FakeProcess:
    def __init__(self, backend):
        self.backend = backend

    def create_time(self):
        return self.backend.created

    def is_running(self):
        return self.backend.running

    def cpu_times(self):
        value = self.backend.cpu
        if isinstance(value, Exception):
            raise value
        if self.backend.replace_on_cpu_read:
            self.backend.created += 1
        return value

    def memory_info(self):
        return SimpleNamespace(rss=1000, vms=2000)

    def io_counters(self):
        raise NotImplementedError("macOS process I/O counters unavailable")


class FakeBackend:
    __version__ = "7.2.2"

    def __init__(self):
        self.created = 125.0
        self.running = True
        self.replace_on_cpu_read = False
        self.cpu = SimpleNamespace(user=4.0, system=1.0)

    def Process(self, pid):
        if pid != 42:
            raise ProcessLookupError(pid)
        return FakeProcess(self)

    def virtual_memory(self):
        return SimpleNamespace(total=4000, available=2000, percent=50.0)

    def swap_memory(self):
        return SimpleNamespace(used=0, total=1000)


def write_stat(path, *, user, system, created):
    # Linux stat fields 3 through 22, including a ')' in the command name.
    fields = ["S"] + ["0"] * 19
    fields[11], fields[12], fields[19] = str(user), str(system), str(created)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("42 (plane ) name) " + " ".join(fields), encoding="utf-8")


def make_research_app(directory):
    app = Path(directory) / "app"
    (app / "render").mkdir(parents=True)
    (app.parent / "assets").mkdir()
    (app / "render/high_graphics_profile.gd").write_bytes(
        (Path(bench.REPO) / "app/render/high_graphics_profile.gd").read_bytes())
    name = "OpenRC-Research-" + uuid.uuid4().hex
    project = (f'config_version=5\n[application]\nconfig/name="{name}"\n'
               '[rendering]\nlights_and_shadows/multi_bounce_occlusion/enabled=false\n')
    (app / "project.godot").write_text(project, encoding="utf-8")
    return app, name


class CpuSamplerTests(unittest.TestCase):
    def test_linux_reports_process_and_main_thread_counters(self):
        with tempfile.TemporaryDirectory() as directory:
            process = Path(directory) / "42/stat"
            thread = Path(directory) / "42/task/42/stat"
            write_stat(process, user=100, system=50, created=999)
            write_stat(thread, user=80, system=20, created=999)
            sampler = bench.LinuxCpuSampler(42, proc_root=directory, ticks_per_second=100)
            start = sampler.sample()
            write_stat(process, user=225, system=75, created=999)
            write_stat(thread, user=150, system=30, created=999)
            process_delta, main_delta = bench.cpu_deltas(start, sampler.sample())
        self.assertAlmostEqual(process_delta, 1.5)
        self.assertAlmostEqual(main_delta, 0.8)
        self.assertEqual(sampler.cpu_backend, "linux_procfs")

    def test_linux_rejects_missing_malformed_and_replaced_processes(self):
        with tempfile.TemporaryDirectory() as directory:
            process = Path(directory) / "42/stat"
            thread = Path(directory) / "42/task/42/stat"
            write_stat(process, user=1, system=1, created=99)
            write_stat(thread, user=1, system=1, created=99)
            sampler = bench.LinuxCpuSampler(42, proc_root=directory, ticks_per_second=100)
            write_stat(thread, user=1, system=1, created=100)
            with self.assertRaisesRegex(bench.MeasurementError, "reused"):
                sampler.sample()
            thread.write_text("invalid", encoding="utf-8")
            with self.assertRaisesRegex(bench.MeasurementError, "cannot read"):
                sampler.sample()
            thread.unlink()
            with self.assertRaisesRegex(bench.MeasurementError, "cannot read"):
                sampler.sample()

    @unittest.skipUnless(os.path.exists("/proc/self/stat"), "Linux procfs unavailable")
    def test_linux_can_sample_this_process(self):
        sampler = bench.LinuxCpuSampler(os.getpid())
        process, main = bench.cpu_deltas(sampler.sample(), sampler.sample())
        self.assertGreaterEqual(process, 0)
        self.assertGreaterEqual(main, 0)

    def test_darwin_process_cpu_survives_unsupported_optional_io(self):
        backend = FakeBackend()
        sampler = bench.DarwinCpuSampler(42, backend=backend)
        first = sampler.sample()
        backend.cpu = SimpleNamespace(user=5.5, system=1.25)
        process, main = bench.cpu_deltas(first, sampler.sample())
        self.assertAlmostEqual(process, 1.75)
        self.assertIsNone(main)
        self.assertIn("unsupported", sampler.main_thread_cpu_scope)

    def test_darwin_rejects_replacement_exit_and_replacement_during_read(self):
        backend = FakeBackend()
        sampler = bench.DarwinCpuSampler(42, backend=backend)
        backend.created += 1  # Replacement after launch but before the first observation.
        with self.assertRaisesRegex(bench.MeasurementError, "pid_reused"):
            sampler.sample()

        backend = FakeBackend()
        sampler = bench.DarwinCpuSampler(42, backend=backend)
        sampler.sample()
        backend.created += 1
        with self.assertRaisesRegex(bench.MeasurementError, "reused"):
            sampler.sample()

        backend = FakeBackend()
        sampler = bench.DarwinCpuSampler(42, backend=backend)
        backend.running = False
        with self.assertRaisesRegex(bench.MeasurementError, "unavailable"):
            sampler.sample()

        backend = FakeBackend()
        sampler = bench.DarwinCpuSampler(42, backend=backend)
        backend.replace_on_cpu_read = True
        with self.assertRaisesRegex(bench.MeasurementError, "reused"):
            sampler.sample()

    def test_darwin_rejects_unavailable_or_invalid_cpu_fields(self):
        for cpu in (AccessDenied("denied"), NotImplementedError("unsupported"),
                    SimpleNamespace(user=1.0), SimpleNamespace(user=1.0, system=math.nan),
                    SimpleNamespace(user=-1.0, system=2.0)):
            with self.subTest(cpu=cpu):
                backend = FakeBackend()
                backend.cpu = cpu
                with self.assertRaisesRegex(bench.MeasurementError, "CPU counters unavailable"):
                    bench.DarwinCpuSampler(42, backend=backend).sample()

    def test_counter_resets_and_invalid_values_never_become_cpu_rates(self):
        start = bench.CpuReading(3.0, 2.0, 1.0, 1.0)
        for end in (bench.CpuReading(2.0, 4.0, 2.0, 1.0),
                    bench.CpuReading(4.0, 1.0, 2.0, 1.0),
                    bench.CpuReading(4.0, 3.0, 0.5, 2.0),
                    bench.CpuReading(4.0, 3.0, 2.0, None),
                    bench.CpuReading(math.inf, 3.0, 2.0, 1.0),
                    bench.CpuReading(math.nan, 3.0, 2.0, 1.0)):
            with self.subTest(end=end), self.assertRaises(bench.MeasurementError):
                bench.cpu_deltas(start, end)

    def test_darwin_dependency_failure_is_actionable_before_launch(self):
        with mock.patch.object(bench, "load_backend", side_effect=ValueError("requires psutil 7.2.2")):
            with self.assertRaisesRegex(ValueError, "requires psutil 7.2.2"):
                bench.cpu_sampler_factory("darwin")
        with self.assertRaisesRegex(bench.MeasurementError, "unsupported"):
            bench.cpu_sampler_factory("unknown-os")
        with mock.patch.object(bench, "load_backend", side_effect=AssertionError("unexpected psutil import")):
            self.assertIs(bench.cpu_sampler_factory("linux"), bench.LinuxCpuSampler)


class BenchmarkOutputTests(unittest.TestCase):
    def run_benchmark(self, sampler, *, sim_end=4.0, times=(10.0, 12.0), paused=False, crashed=False,
                      on_sleep=None, snapshot_ages=(20, 30), aircrafts=(bench.AIRCRAFT_ID, bench.AIRCRAFT_ID),
                      boundary_clock=None, scenario="airborne", platform="linux", app_dir=""):
        calls = []
        states = iter([
            {"flight": {"time_s": 2.0, "height_m": 20.0, "tick": 480, "aircraft": aircrafts[0]}, "frame": 100,
             "snapshot_age_ms": snapshot_ages[0]},
            {"flight": {"time_s": sim_end, "height_m": 25.0, "tick": 960,
                        "paused": paused, "crashed": crashed, "aircraft": aircrafts[1]}, "frame": 160,
             "snapshot_age_ms": snapshot_ages[1]},
        ])
        w0, w1 = times
        if boundary_clock is None:
            boundary_clock = (w0 - 0.2, w0 - 0.1, w0 - 0.05, w0,
                              w1 - 0.05, w1, w1 + 0.02, w1 + 0.1)

        def ctl(port, *args, timeout=300):
            calls.append((port, args))
            if args[0] == "launch":
                return json.dumps({"port": 2468, "pid": 42})
            if args[0] == "state":
                return json.dumps(next(states))
            if args[0] == "perf":
                return json.dumps({"sim_step_usec": 12.3, "fps": 60})
            return ""

        output = io.StringIO()
        with mock.patch.object(bench, "ctl", side_effect=ctl), \
                mock.patch.object(bench, "cpu_sampler_factory", return_value=lambda pid: sampler), \
                mock.patch.object(bench.sys, "platform", platform), \
                mock.patch.object(bench.time, "sleep", side_effect=on_sleep), \
                mock.patch.object(bench.time, "monotonic", side_effect=boundary_clock), \
                mock.patch.dict(os.environ, {"OPENRC_PRESENTATION_CADENCE": "2", "OPENRC_APP_DIR": app_dir}, clear=True), \
                redirect_stdout(output):
            try:
                bench.main(["candidate", scenario, "0", "2", "60", "0.5"])
            finally:
                self.assertIn((2468, ("stop",)), calls)
        return json.loads(output.getvalue()), calls

    @staticmethod
    def fake_sampler(readings, *, darwin=False):
        return SimpleNamespace(
            sample=mock.Mock(side_effect=readings),
            cpu_backend="psutil_7.2.2" if darwin else "linux_procfs",
            main_thread_cpu_scope="unsupported on darwin" if darwin else "main thread of the direct launched process")

    def test_linux_output_keeps_existing_metrics_and_workload_settings(self):
        sampler = self.fake_sampler([bench.CpuReading(1, 1, 0.5, 0.5), bench.CpuReading(2, 1.5, 1, 0.75)])
        result, calls = self.run_benchmark(sampler)
        self.assertEqual(result["main_ms_per_sim_s"], 375.0)
        self.assertEqual(result["cpu_ms_per_sim_s"], 750.0)
        self.assertEqual(result["frames_per_sim_s"], 30.0)
        self.assertEqual(result["realtime"], 1.0)
        self.assertEqual((result["wall_seconds"], result["simulated_seconds"]), (2.0, 2.0))
        self.assertEqual((result["max_fps"], result["time_scale"], result["presentation_cadence"]), (60, 0.5, "2"))
        self.assertEqual(result["aircraft"], bench.AIRCRAFT_ID)
        self.assertIn((2468, ("eval", "expr=Engine.set_max_fps(60)")), calls)
        self.assertIn((2468, ("eval", "expr=Engine.set_time_scale(0.5)")), calls)
        self.assertIn((2468, ("fly", "start=airborne", f"aircraft={bench.AIRCRAFT_ID}")), calls)
        self.assertIn((2468, ("sticks", "throttle=0.62", "pitch=0.02", "for_s=32.0")), calls)

    def test_boundary_ages_and_wall_bounds_expose_stale_snapshot_uncertainty(self):
        sampler = self.fake_sampler([bench.CpuReading(1, 1, None, None), bench.CpuReading(2, 2, None, None)],
                                    darwin=True)
        with mock.patch.object(bench.time, "get_clock_info", return_value=SimpleNamespace(resolution=1 / 24_000_000)):
            result, _ = self.run_benchmark(sampler)
        timing = result["boundary_timing"]
        self.assertEqual(timing["snapshot_age_ms"], [20.0, 30.0])
        self.assertEqual(timing["snapshot_age_status"], ["ok", "ok"])
        self.assertAlmostEqual(timing["state_call_duration_seconds"][0], 0.1)
        self.assertAlmostEqual(timing["cpu_call_duration_seconds"][0], 0.05)
        start = timing["start_cpu_minus_state_wall_seconds_bounds"]
        end = timing["end_state_minus_cpu_wall_seconds_bounds"]
        allowance = 2 * timing["clock_resolution_seconds"]
        self.assertAlmostEqual(start[0], 0.05 - allowance)
        self.assertAlmostEqual(start[1], 0.221 + allowance)
        self.assertAlmostEqual(end[0], -0.011 - allowance)
        self.assertAlmostEqual(end[1], 0.15 + allowance)
        self.assertLess(end[0], 0)  # A cached final state can precede the CPU sample.
        self.assertIn("does not bound simulation-time error", timing["bounds_scope"])

    def test_missing_and_invalid_snapshot_ages_produce_unknown_bounds(self):
        for ages, statuses in (((None, None), ["missing", "missing"]),
                               ((-1, math.nan), ["invalid", "invalid"]),
                               ((True, "12"), ["invalid", "invalid"])):
            with self.subTest(ages=ages):
                sampler = self.fake_sampler([bench.CpuReading(1, 1, None, None),
                                             bench.CpuReading(2, 2, None, None)], darwin=True)
                result, _ = self.run_benchmark(sampler, snapshot_ages=ages)
                timing = result["boundary_timing"]
                self.assertEqual(timing["snapshot_age_ms"], [None, None])
                self.assertEqual(timing["snapshot_age_status"], statuses)
                self.assertIsNone(timing["start_cpu_minus_state_wall_seconds_bounds"])
                self.assertIsNone(timing["end_state_minus_cpu_wall_seconds_bounds"])

    def test_nonfinite_nonpositive_or_reversed_boundary_timestamps_reject_run(self):
        clocks = ((9.8, 9.9, 9.95, 10.0, 11.95, 12.0, 12.02, math.nan),
                  (0.0, 9.9, 9.95, 10.0, 11.95, 12.0, 12.02, 12.1),
                  (9.8, 9.7, 9.95, 10.0, 11.95, 12.0, 12.02, 12.1))
        for clock in clocks:
            with self.subTest(clock=clock):
                sampler = self.fake_sampler([bench.CpuReading(1, 1, None, None),
                                             bench.CpuReading(2, 2, None, None)], darwin=True)
                with self.assertRaisesRegex(SystemExit, "invalid monotonic boundary timestamps"):
                    self.run_benchmark(sampler, boundary_clock=clock)

    def test_wrong_missing_or_changed_aircraft_rejects_run(self):
        for aircrafts in (("other-aircraft", bench.AIRCRAFT_ID),
                         (bench.AIRCRAFT_ID, "other-aircraft"),
                         (None, bench.AIRCRAFT_ID)):
            with self.subTest(aircrafts=aircrafts):
                sampler = self.fake_sampler([bench.CpuReading(1, 1, None, None),
                                             bench.CpuReading(2, 2, None, None)], darwin=True)
                with self.assertRaisesRegex(SystemExit, "unexpected aircraft"):
                    self.run_benchmark(sampler, aircrafts=aircrafts)

    def test_runway_also_requests_the_stik(self):
        sampler = self.fake_sampler([bench.CpuReading(1, 1, None, None), bench.CpuReading(2, 2, None, None)],
                                    darwin=True)
        result, calls = self.run_benchmark(sampler, scenario="runway")
        self.assertEqual(result["aircraft"], bench.AIRCRAFT_ID)
        self.assertIn((2468, ("fly", "start=runway", f"aircraft={bench.AIRCRAFT_ID}")), calls)
        self.assertIn((2468, ("sticks", "throttle=0.0", "for_s=32.0")), calls)

    def test_darwin_launch_uses_and_records_verified_research_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            app, project_name = make_research_app(directory)
            sampler = self.fake_sampler([bench.CpuReading(1, 1, None, None),
                                         bench.CpuReading(2, 2, None, None)], darwin=True)
            result, calls = self.run_benchmark(sampler, platform="darwin", app_dir=str(app))
        self.assertIn((0, ("launch", "--headless", "--app", str(app.resolve()))), calls)
        identity = result["research_project"]
        self.assertEqual(identity["project_name"], project_name)
        self.assertTrue(identity["validated_before_launch"])
        self.assertEqual(len(identity["project_sha256"]), 64)

    def test_darwin_output_uses_null_and_explicit_scope_for_main_thread(self):
        backend = FakeBackend()
        sampler = bench.DarwinCpuSampler(42, backend=backend)

        def sleep(seconds):
            if seconds == 2.0:
                backend.cpu = SimpleNamespace(user=5.0, system=1.5)

        result, _ = self.run_benchmark(sampler, on_sleep=sleep)
        self.assertEqual(result["cpu_ms_per_sim_s"], 750.0)
        self.assertIsNone(result["main_ms_per_sim_s"])
        self.assertIn("unsupported", result["main_thread_cpu_scope"])
        self.assertIn("descendants excluded", result["cpu_scope"])

    def test_no_result_for_invalid_sim_or_wall_intervals_and_crash(self):
        cases = [(2.0, (10.0, 12.0), False, False), (math.nan, (10.0, 12.0), False, False),
                 (math.inf, (10.0, 12.0), False, False), (4.0, (10.0, 10.0), False, False),
                 (4.0, (10.0, 9.0), False, False), (4.0, (10.0, math.inf), False, False),
                 (4.0, (10.0, math.nan), False, False), (4.0, (10.0, 12.0), True, False),
                 (4.0, (10.0, 12.0), False, True)]
        for sim_end, times, paused, crashed in cases:
            with self.subTest(sim_end=sim_end, times=times, paused=paused, crashed=crashed):
                sampler = self.fake_sampler([bench.CpuReading(1, 1, None, None), bench.CpuReading(2, 2, None, None)],
                                            darwin=True)
                with self.assertRaisesRegex(SystemExit, "invalid sample"):
                    self.run_benchmark(sampler, sim_end=sim_end, times=times, paused=paused, crashed=crashed)

    def test_invalid_request_fails_before_launch(self):
        for warm, sample in (("nan", "1"), ("-1", "1"), ("0", "nan"), ("0", "inf"), ("0", "0")):
            with self.subTest(warm=warm, sample=sample), mock.patch.object(bench, "ctl") as ctl:
                with self.assertRaises(SystemExit):
                    bench.main(["case", "runway", warm, sample])
                ctl.assert_not_called()


class ResearchIsolationTests(unittest.TestCase):
    def assert_refused_before_launch(self, path, reason):
        with mock.patch.dict(os.environ, {"OPENRC_APP_DIR": str(path)}, clear=True), \
                mock.patch.object(bench.sys, "platform", "darwin"), \
                mock.patch.object(bench, "ctl") as ctl, \
                mock.patch.object(bench, "cpu_sampler_factory") as factory:
            with self.assertRaisesRegex(SystemExit, reason):
                bench.main(["case", "airborne", "0", "1"])
            ctl.assert_not_called()
            factory.assert_not_called()

    def test_missing_or_live_app_is_refused_before_launch(self):
        self.assert_refused_before_launch("", "requires OPENRC_APP_DIR")
        self.assert_refused_before_launch(Path(bench.REPO) / "app", "separate app copy")

    def test_copied_regular_name_custom_user_dir_and_feature_overrides_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            app, name = make_research_app(directory)
            project_path = app / "project.godot"
            original = project_path.read_text(encoding="utf-8")
            variants = (
                (original.replace(name, "OpenRC Simulator"), "project name"),
                (original.replace("[rendering]", "config/use_custom_user_dir=true\n[rendering]"), "user directory"),
                (original.replace("[rendering]", "config/use_custom_user_dir.macos=true\n[rendering]"), "feature override"),
                (original.replace("[rendering]", 'config/name.macos="OpenRC Simulator"\n[rendering]'), "feature override"),
                (original.replace("[rendering]", 'config/project_settings_override="user://override.cfg"\n[rendering]'),
                 "settings override"),
            )
            for value, reason in variants:
                with self.subTest(reason=reason):
                    project_path.write_text(value, encoding="utf-8")
                    self.assert_refused_before_launch(app, reason)
            project_path.write_text(original, encoding="utf-8")
            (app / "override.cfg").write_text("[application]\nconfig/name=\"OpenRC Simulator\"\n", encoding="utf-8")
            self.assert_refused_before_launch(app, "override.cfg")

    def test_linux_retains_existing_app_path_behavior(self):
        self.assertEqual(bench.validated_app_dir("", "linux"), ("", None))
        self.assertEqual(bench.validated_app_dir("my-app", "linux"), ("my-app", None))


if __name__ == "__main__":
    unittest.main()
