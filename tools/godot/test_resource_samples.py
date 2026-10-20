"""Resource sampler validation, failure isolation, and optional direct-child check."""
from contextlib import nullcontext
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from types import SimpleNamespace
from unittest import mock

from resource_samples import ResourceSampler, clock_anchor, load_backend, validate_options


class AccessDenied(Exception):
    pass


class UnsupportedOperation(Exception):
    pass


class FakeProcess:
    def __init__(self):
        self.running = True
        self.create_times = [1234.5]
        self.memory_values = [SimpleNamespace(rss=4096, vms=8192)]
        self.cpu_values = [SimpleNamespace(user=1.0, system=0.5)]
        self.io_values = [SimpleNamespace(read_bytes=100, write_bytes=200,
                                          read_count=3, write_count=4)]
        self.thread_values = [2]
        self.num_thread_calls = 0
        self.oneshot_calls = 0
        self.terminate_calls = 0

    @staticmethod
    def _next(values):
        value = values.pop(0) if len(values) > 1 else values[0]
        if isinstance(value, BaseException):
            raise value
        return value

    def create_time(self):
        return self._next(self.create_times)

    def is_running(self):
        return self.running

    def oneshot(self):
        self.oneshot_calls += 1
        return nullcontext()

    def memory_info(self):
        return self._next(self.memory_values)

    def cpu_times(self):
        return self._next(self.cpu_values)

    def num_threads(self):
        self.num_thread_calls += 1
        return self._next(self.thread_values)

    def io_counters(self):
        return self._next(self.io_values)


class FakeBackend:
    __version__ = "7.2.2"

    def __init__(self, process=None):
        self.process = process or FakeProcess()
        self.volume_error = None
        self.virtual_error = None
        self.swap_error = None

    def Process(self, _pid):
        return self.process

    def virtual_memory(self):
        if self.virtual_error:
            raise self.virtual_error
        return SimpleNamespace(total=1024 * 1024, available=512 * 1024, percent=50.0)

    def swap_memory(self):
        if self.swap_error:
            raise self.swap_error
        return SimpleNamespace(used=1024, total=4096)

    def disk_usage(self, _path):
        if self.volume_error:
            raise self.volume_error
        return SimpleNamespace(free=1000, total=8000)


class FakeClock:
    def __init__(self, value=10.0):
        self.value = value

    def perf_counter(self):
        return self.value


class ResourceSamplerTests(unittest.TestCase):
    def test_clock_anchor_brackets_wall_read_and_preserves_finish(self):
        with mock.patch("resource_samples.time.perf_counter", side_effect=[10.0, 10.1]), \
                mock.patch("resource_samples.time.time_ns", return_value=1000000000000):
            anchor = clock_anchor()
        self.assertEqual(anchor["monotonic_usec"], 10050000)
        self.assertEqual(anchor["unix_usec"], 1000000000)
        self.assertGreaterEqual(anchor["uncertainty_usec"], 50000)
        sampler = ResourceSampler(44, backend=FakeBackend())
        first = sampler.finish()["clock"]
        with mock.patch("resource_samples.clock_anchor", side_effect=AssertionError("recaptured")):
            second = sampler.finish()["clock"]
        self.assertEqual(first, second)
        self.assertLessEqual(first["origin_usec"], first["start"]["monotonic_usec"])
        self.assertLessEqual(first["start"]["monotonic_usec"], first["end"]["monotonic_usec"])
        self.assertGreaterEqual(first["start"]["uncertainty_usec"], 20000)

    def test_validation_is_independent_of_psutil(self):
        with mock.patch("resource_samples.importlib.import_module", side_effect=AssertionError("imported")):
            self.assertEqual(validate_options(), ())

    def test_rejects_invalid_options_and_disk_paths(self):
        for value in (True, False, math.nan, math.inf, -math.inf, 0.099, 60.01, "1"):
            with self.subTest(interval=value), self.assertRaises(ValueError):
                validate_options(interval=value)
        for value in (True, 1.0, 0, -1, 10001):
            with self.subTest(max_samples=value), self.assertRaises(ValueError):
                validate_options(max_samples=value)
        for value in (None, 0, 1, "false"):
            with self.subTest(include_threads=value), self.assertRaises(ValueError):
                validate_options(include_threads=value)
        self.assertEqual(validate_options(include_threads=True), ())
        with self.assertRaises(ValueError):
            validate_options(disk_paths="single-path-is-not-a-sequence")
        with self.assertRaises(ValueError):
            validate_options(disk_paths=[Path(tempfile.gettempdir())] * 9)
        with tempfile.TemporaryDirectory() as temp:
            file_path = Path(temp) / "not-a-directory"
            file_path.write_text("x", encoding="utf-8")
            with self.assertRaises(ValueError):
                validate_options(disk_paths=[file_path])
        with self.assertRaises(ValueError):
            validate_options(disk_paths=[Path(tempfile.gettempdir()) / "missing-resource-dir"])

    def test_load_backend_requires_exact_pin(self):
        with mock.patch("resource_samples.importlib.import_module",
                        return_value=SimpleNamespace(__version__="7.0.0")):
            with self.assertRaisesRegex(ValueError, "requires psutil 7.2.2"):
                load_backend()
        with mock.patch("resource_samples.importlib.import_module", side_effect=ImportError("missing")):
            with self.assertRaisesRegex(ValueError, "requirements-resources.txt"):
                load_backend()

    def test_poll_is_due_monotonic_and_sample_schema_is_finite(self):
        backend = FakeBackend()
        backend.process.memory_values.append(SimpleNamespace(rss=6144, vms=10240))
        backend.process.cpu_values.append(SimpleNamespace(user=1.5, system=0.75))
        backend.process.io_values.append(SimpleNamespace(read_bytes=150, write_bytes=250,
                                                           read_count=4, write_count=5))
        clock = FakeClock()
        with tempfile.TemporaryDirectory() as temp:
            with mock.patch("resource_samples.time.perf_counter", side_effect=clock.perf_counter):
                sampler = ResourceSampler(44, interval=1.0, max_samples=3,
                                          disk_paths=[temp], backend=backend)
                self.assertTrue(sampler.poll())
                self.assertFalse(sampler.poll())
                clock.value = 11.0
                self.assertTrue(sampler.poll())
                report = sampler.finish()
        self.assertEqual(report["coverage"], "sampled")
        self.assertEqual(report["sample_count"], 2)
        sample = report["samples"][1]
        self.assertAlmostEqual(sample["cpu_percent"], 75.0)
        self.assertEqual(sample["poll_overhead_usec"], 0)
        self.assertEqual(sample["field_status"]["rss_bytes"], "ok")
        self.assertEqual(report["summary"]["process_memory_window"]["rss_bytes"],
                         {"first_bytes": 4096, "last_bytes": 6144, "delta_bytes": 2048})
        self.assertEqual(report["summary"]["minima"]["virtual_memory_available_bytes"], 512 * 1024)
        self.assertEqual(report["summary"]["volume_free_capacity_minima"][temp]["free_bytes"], 1000)
        json.dumps(report, allow_nan=False)
        self.assertEqual(backend.process.oneshot_calls, 2)

    def test_thread_count_is_opt_in_and_samples_when_enabled(self):
        disabled_process = FakeProcess()
        disabled = ResourceSampler(54, backend=FakeBackend(disabled_process))
        self.assertTrue(disabled.poll())
        disabled_report = disabled.finish()
        self.assertEqual(disabled_process.num_thread_calls, 0)
        self.assertIsNone(disabled_report["samples"][0]["num_threads"])
        self.assertEqual(disabled_report["samples"][0]["field_status"]["num_threads"], "disabled")
        self.assertFalse(disabled_report["include_threads"])

        enabled_process = FakeProcess()
        enabled = ResourceSampler(55, include_threads=True, backend=FakeBackend(enabled_process))
        self.assertTrue(enabled.poll())
        enabled_report = enabled.finish()
        self.assertEqual(enabled_process.num_thread_calls, 1)
        self.assertEqual(enabled_report["samples"][0]["num_threads"], 2)
        self.assertEqual(enabled_report["samples"][0]["field_status"]["num_threads"], "ok")
        self.assertTrue(enabled_report["include_threads"])

    def test_pid_reuse_and_exit_are_not_sampled(self):
        reused = FakeProcess()
        reused.create_times = [1234.5, 1235.5]
        sampler = ResourceSampler(45, backend=FakeBackend(reused))
        self.assertFalse(sampler.poll())
        report = sampler.finish()
        self.assertEqual(report["coverage"], "no_samples")
        self.assertEqual(report["stop_reason"], "pid_reused")
        self.assertTrue(any(error["code"] == "pid_reused" for error in report["errors"]))

        exited = FakeProcess()
        exited.running = False
        exited_sampler = ResourceSampler(46, backend=FakeBackend(exited))
        self.assertFalse(exited_sampler.poll())
        report = exited_sampler.finish()
        self.assertEqual(report["stop_reason"], "process_exited")
        self.assertEqual(report["coverage"], "no_samples")

        reused_after_exit = FakeProcess()
        reused_after_exit.running = False
        reused_after_exit.create_times = [1234.5, 1235.5]
        reused_after_exit_sampler = ResourceSampler(53, backend=FakeBackend(reused_after_exit))
        self.assertFalse(reused_after_exit_sampler.poll())
        self.assertEqual(reused_after_exit_sampler.finish()["stop_reason"], "pid_reused")

    def test_access_denied_unsupported_missing_and_nonfinite_are_explicit_nulls(self):
        process = FakeProcess()
        process.memory_values = [SimpleNamespace(rss=math.nan, vms=8.0)]
        process.cpu_values = [SimpleNamespace(user=1.0)]  # system time is absent
        process.io_values = [AccessDenied("io is restricted")]
        backend = FakeBackend(process)
        backend.virtual_error = UnsupportedOperation("virtual memory unsupported")
        with tempfile.TemporaryDirectory() as temp:
            backend.volume_error = AccessDenied("volume denied")
            sampler = ResourceSampler(47, disk_paths=[temp], backend=backend)
            self.assertTrue(sampler.poll())
            sample = sampler.finish()["samples"][0]
        self.assertIsNone(sample["rss_bytes"])
        self.assertEqual(sample["field_status"]["rss_bytes"], "invalid")
        self.assertIsNone(sample["vms_bytes"])
        self.assertEqual(sample["field_status"]["vms_bytes"], "invalid")
        self.assertIsNone(sample["cpu_system_seconds"])
        self.assertEqual(sample["field_status"]["cpu_system_seconds"], "unsupported")
        self.assertIsNone(sample["io_read_bytes"])
        self.assertEqual(sample["field_status"]["io_read_bytes"], "denied")
        self.assertEqual(sample["field_status"]["virtual_memory_total_bytes"], "unsupported")
        self.assertEqual(sample["field_status"]["volume[0].free_bytes"], "denied")
        self.assertTrue(any(error["code"] == "denied" for error in sampler.finish()["errors"]))

    def test_linux_unknown_minus_one_and_missing_counters_remain_null(self):
        process = FakeProcess()
        process.io_values = [SimpleNamespace(read_bytes=-1, write_bytes=-5)]
        process.thread_values = ["unknown"]
        sample = self._one_sample(FakeBackend(process), include_threads=True)["samples"][0]
        self.assertIsNone(sample["io_read_bytes"])
        self.assertEqual(sample["field_status"]["io_read_bytes"], "unknown")
        self.assertIsNone(sample["io_write_bytes"])
        self.assertEqual(sample["field_status"]["io_write_bytes"], "invalid")
        self.assertIsNone(sample["num_threads"])
        self.assertEqual(sample["field_status"]["num_threads"], "invalid")
        self.assertIsNone(sample["io_read_count"])
        self.assertEqual(sample["field_status"]["io_read_count"], "unsupported")

    def test_max_samples_caps_capture_without_stopping_child(self):
        process = FakeProcess()
        sampler = ResourceSampler(48, max_samples=1, backend=FakeBackend(process))
        self.assertTrue(sampler.poll())
        self.assertFalse(sampler.poll())
        report = sampler.finish()
        self.assertEqual(report["coverage"], "capped")
        self.assertTrue(report["capped"])
        self.assertEqual(report["stop_reason"], "sample_limit")
        self.assertTrue(process.running)
        self.assertEqual(process.terminate_calls, 0)

    def test_counter_resets_never_produce_negative_deltas(self):
        process = FakeProcess()
        process.cpu_values = [SimpleNamespace(user=5.0, system=2.0),
                              SimpleNamespace(user=4.0, system=1.0)]
        process.io_values = [SimpleNamespace(read_bytes=100, write_bytes=200,
                                             read_count=3, write_count=4),
                             SimpleNamespace(read_bytes=90, write_bytes=180,
                                             read_count=2, write_count=3)]
        backend = FakeBackend(process)
        clock = FakeClock()
        with mock.patch("resource_samples.time.perf_counter", side_effect=clock.perf_counter):
            sampler = ResourceSampler(49, interval=1.0, max_samples=2, backend=backend)
            sampler.poll()
            clock.value = 11.0
            sampler.poll()
            report = sampler.finish()
        self.assertIsNone(report["summary"]["counter_deltas"]["cpu_user_seconds"])
        self.assertIsNone(report["summary"]["counter_deltas"]["io_read_bytes"])
        self.assertIn("cpu_user_seconds", report["summary"]["counter_resets"])
        self.assertIn("io_read_bytes", report["summary"]["counter_resets"])
        self.assertTrue(any(error["code"] == "counter_reset" for error in report["errors"]))

    def test_backend_failures_degrade_to_diagnostics(self):
        class BrokenBackend(FakeBackend):
            def virtual_memory(self):
                raise RuntimeError("backend bug")

            def disk_usage(self, _path):
                raise RuntimeError("volume bug")

        process = FakeProcess()
        process.memory_values = [RuntimeError("memory lookup failed")]
        with tempfile.TemporaryDirectory() as temp:
            sampler = ResourceSampler(50, disk_paths=[temp], backend=BrokenBackend(process))
            self.assertTrue(sampler.poll())
            report = sampler.finish()
        self.assertEqual(report["sample_count"], 1)
        self.assertIsNone(report["samples"][0]["rss_bytes"])
        self.assertIsNone(report["samples"][0]["virtual_memory_total_bytes"])
        self.assertGreater(report["error_count"], 0)
        json.dumps(report, allow_nan=False)

    def test_error_details_are_bounded(self):
        process = FakeProcess()
        process.memory_values = [AccessDenied("no memory access")]
        process.cpu_values = [AccessDenied("no CPU access")]
        process.io_values = [AccessDenied("no I/O access")]
        backend = FakeBackend(process)
        backend.virtual_error = AccessDenied("no system access")
        backend.swap_error = AccessDenied("no swap access")
        with tempfile.TemporaryDirectory() as temp:
            backend.volume_error = AccessDenied("no volume access")
            clock = FakeClock()
            with mock.patch("resource_samples.time.perf_counter", side_effect=clock.perf_counter):
                sampler = ResourceSampler(51, interval=0.1, max_samples=10,
                                          disk_paths=[temp], backend=backend)
                for index in range(10):
                    clock.value = 10.0 + index / 10
                    sampler.poll()
                report = sampler.finish()
        self.assertEqual(len(report["errors"]), 20)
        self.assertGreater(report["error_count"], 20)
        self.assertTrue(report["errors_truncated"])

    @staticmethod
    def _one_sample(backend, *, include_threads=False):
        sampler = ResourceSampler(52, include_threads=include_threads, backend=backend)
        sampler.poll()
        return sampler.finish()

    def test_optional_real_direct_child_allocation_and_io(self):
        try:
            backend = load_backend()
        except ValueError as error:
            self.skipTest(str(error))
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            target = root / "sample.bin"
            ready = root / "ready"
            go = root / "go"
            done = root / "done"
            code = "\n".join((
                "import os, pathlib, time",
                f"root = pathlib.Path({str(root)!r})",
                "ready = root / 'ready'; go = root / 'go'; done = root / 'done'",
                f"target = pathlib.Path({str(target)!r})",
                "ready.write_text('ready', encoding='utf-8')",
                "deadline = time.monotonic() + 8",
                "while not go.exists() and time.monotonic() < deadline: time.sleep(0.01)",
                "if not go.exists(): raise SystemExit(7)",
                "data = bytearray(32 * 1024 * 1024)",
                "for page in range(len(data) // 4096):",
                "    start = page * 4096; data[start:start + 4] = page.to_bytes(4, 'little')",
                "with target.open('wb') as stream:",
                "    stream.write(b'x' * (1024 * 1024))",
                "    stream.flush(); os.fsync(stream.fileno())",
                "done.write_text('done', encoding='utf-8')",
                "deadline = time.monotonic() + 1.2",
                "while time.monotonic() < deadline:",
                "    for offset in range(0, len(data), 4096): data[offset] ^= 1",
            ))
            # The Windows venv's sys.executable is an app-execution alias that
            # launches python.exe as a child. Monitor the base executable so
            # this test measures the PID we actually launch, as production does.
            child_executable = (getattr(sys, "_base_executable", sys.executable)
                                if sys.platform == "win32" else sys.executable)
            child = subprocess.Popen([child_executable, "-c", code],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            sampler = None
            sample_count = 0

            def poll_once():
                nonlocal sample_count
                if sampler.poll():
                    sample_count += 1

            try:
                sampler = ResourceSampler(child.pid, interval=0.1, max_samples=40,
                                          disk_paths=[temp], backend=backend)
                deadline = time.monotonic() + 8
                while (not ready.is_file() or sample_count == 0) and child.poll() is None:
                    poll_once()
                    if time.monotonic() >= deadline:
                        self.fail("child did not reach the baseline handshake before its deadline")
                    time.sleep(0.03)
                self.assertTrue(ready.is_file(), "child exited before announcing readiness")
                self.assertGreater(sample_count, 0, "no baseline sample was captured before allocation")
                # Baseline must follow interpreter startup. Otherwise the test
                # could attribute Python's own startup allocations to our payload.
                ready_sample_count = sample_count
                deadline = time.perf_counter() + 2
                while sample_count == ready_sample_count and child.poll() is None:
                    poll_once()
                    if time.perf_counter() >= deadline:
                        self.fail("no initialized-process baseline sample before allocation")
                    time.sleep(0.01)
                baseline_index = sample_count - 1
                go.write_text("go", encoding="utf-8")

                deadline = time.monotonic() + 8
                while not done.is_file() and child.poll() is None:
                    poll_once()
                    if time.monotonic() >= deadline:
                        self.fail("child did not finish its allocation and I/O before the deadline")
                    time.sleep(0.03)
                self.assertTrue(done.is_file(), "child exited before completing allocation and I/O")

                samples_at_done = sample_count
                deadline = time.monotonic() + 1
                while sample_count <= samples_at_done and child.poll() is None:
                    poll_once()
                    if time.monotonic() >= deadline:
                        break
                    time.sleep(0.03)
                report = sampler.finish()
                child.wait(timeout=4)
                self.assertEqual(child.returncode, 0)
                self.assertGreater(report["sample_count"], 0)
                baseline = report["samples"][baseline_index]
                self.assertEqual(baseline["field_status"]["rss_bytes"], "ok")
                self.assertIsNotNone(baseline["rss_bytes"])
                post_samples = report["samples"][baseline_index + 1:]
                post_rss = [sample["rss_bytes"] for sample in post_samples
                            if sample["field_status"].get("rss_bytes") == "ok"]
                self.assertTrue(post_rss, "no valid RSS sample followed the allocation handshake")
                self.assertGreaterEqual(max(post_rss) - baseline["rss_bytes"], 12 * 1024 * 1024,
                                        f"touched 32 MiB allocation should raise RSS by at least 12 MiB "
                                        f"(baseline={baseline['rss_bytes']}, peak={max(post_rss)})")
                self.assertEqual(target.stat().st_size, 1024 * 1024)
                baseline_io = baseline["io_write_bytes"]
                io_statuses = [baseline["field_status"].get("io_write_bytes")]
                io_statuses.extend(sample["field_status"].get("io_write_bytes") for sample in post_samples)
                post_io = [sample["io_write_bytes"] for sample in post_samples
                           if sample["field_status"].get("io_write_bytes") == "ok"]
                if "ok" in io_statuses:
                    self.assertEqual(baseline["field_status"].get("io_write_bytes"), "ok")
                    self.assertTrue(post_io, "supported write counter has no valid post-I/O sample")
                    self.assertGreaterEqual(max(post_io) - baseline_io, 1024 * 1024,
                                            "supported process write counter should include the flushed 1 MiB write")
                else:
                    unavailable = {"denied", "unsupported", "unknown"}
                    self.assertTrue(io_statuses)
                    self.assertTrue(all(status in unavailable for status in io_statuses))
                    self.assertIsNone(baseline["io_write_bytes"])
                    self.assertTrue(all(sample["field_status"].get("io_write_bytes") in unavailable
                                        and sample["io_write_bytes"] is None for sample in post_samples),
                                    "unavailable I/O metrics must be explicitly null with an unavailable status")
                self.assertEqual(report["scope"]["process"],
                                 "direct launched PID only; descendants are not included")
                json.dumps(report, allow_nan=False)
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
