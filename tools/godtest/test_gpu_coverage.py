from __future__ import annotations

import copy
import subprocess
import threading
import time
import unittest

from gpu_coverage import validate_gpu_timing
from tools.godtest.hardware import GpuSampler


def make_sample(start, end, devices=("gpu-a",), backend_start=None, backend_end=None):
    lower = start if backend_start is None else backend_start
    upper = end if backend_end is None else backend_end
    return {"start_monotonic_usec": start, "end_monotonic_usec": end,
            "backends": [{"backend": "fixture", "status": "available",
                          "start_monotonic_usec": lower, "end_monotonic_usec": upper,
                          "devices": [{"identity": {"key": device},
                                       "metrics": {"gpu_utilization_pct": 50},
                                       "metric_status": {"gpu_utilization_pct": "available"}}
                                      for device in devices]}]}


def fixture():
    samples = [make_sample(0, 1_000), make_sample(1_000_000, 1_001_000),
               make_sample(2_000_000, 2_001_000)]
    gpu = {"format": "openrc-godtest-gpu-v1", "clock_domain": "python_time_perf_counter",
           "interval_seconds": 1, "max_samples": 4000, "start_monotonic_usec": 0,
           "stop_requested_monotonic_usec": 3_001_000, "stop_monotonic_usec": 3_002_000,
           "sample_count": len(samples), "samples": samples, "timing_coverage": {"status": "complete"}}
    execution = {"gpu_observation": {"clock_domain": "python_perf_counter", "interval_seconds": 1,
                                     "max_samples": 4000, "start_requested_usec": 0,
                                     "stop_requested_usec": 3_000_000, "finish_returned_usec": 3_003_000}}
    return gpu, execution


class GpuCoverageTests(unittest.TestCase):
    def test_good_raw_brackets_are_complete_without_trusting_gpu_summary(self):
        gpu, execution = fixture()
        gpu["timing_coverage"]["status"] = "not_used_by_this_validator"
        value = validate_gpu_timing(gpu, execution)
        self.assertEqual(value["status"], "complete", value)
        self.assertEqual(value["first_poll_gap_usec"], 1_000)
        self.assertEqual(value["max_inter_poll_gap_usec"], 1_001_000)
        self.assertEqual(value["last_poll_gap_usec"], 1_000_000)
        self.assertEqual(value["devices"]["gpu-a"]["completed_observations"], 3)
        self.assertEqual(value["worst_device_inter_gap_usec"], 1_001_000)
        self.assertEqual(value["reasons"], [])

    def test_missing_owner_or_old_clock_is_unavailable(self):
        gpu, execution = fixture()
        self.assertEqual(validate_gpu_timing(gpu, {})["status"], "unavailable")
        del execution["gpu_observation"]["finish_returned_usec"]
        self.assertEqual(validate_gpu_timing(gpu, execution)["status"], "unavailable")
        gpu, execution = fixture()
        del gpu["clock_domain"]
        self.assertEqual(validate_gpu_timing(gpu, execution)["status"], "unavailable")

    def test_forged_sampling_cadence_and_limit_cannot_enlarge_gap_policy(self):
        for side, key, value in (("gpu", "interval_seconds", 60),
                                 ("gpu", "interval_seconds", True),
                                 ("gpu", "max_samples", 10000),
                                 ("owner", "interval_seconds", 60),
                                 ("owner", "max_samples", 10000)):
            gpu, execution = fixture()
            (gpu if side == "gpu" else execution["gpu_observation"])[key] = value
            with self.subTest(side=side, key=key, value=value):
                result = validate_gpu_timing(gpu, execution)
                self.assertEqual(result["status"], "incomplete")
                self.assertIn("sampling_configuration_mismatch", result["reasons"][0])

    def test_owner_and_sampler_brackets_must_be_independently_ordered(self):
        for side, key, value in (("gpu", "start_monotonic_usec", -1),
                                 ("gpu", "start_monotonic_usec", 3_000_001),
                                 ("gpu", "stop_requested_monotonic_usec", 2_999_999),
                                 ("gpu", "stop_monotonic_usec", 3_004_000),
                                 ("owner", "clock_domain", "wall_clock"),
                                 ("gpu", "clock_domain", "unknown"),
                                 ("owner", "start_returned_usec", 3_000_001),
                                 ("owner", "finish_returned_usec", 2_999_999)):
            gpu, execution = fixture()
            (gpu if side == "gpu" else execution["gpu_observation"])[key] = value
            with self.subTest(side=side, key=key):
                self.assertEqual(validate_gpu_timing(gpu, execution)["status"], "incomplete")
        gpu, execution = fixture()
        gpu["stop_requested_monotonic_usec"] = 3_050_001
        gpu["stop_monotonic_usec"] = 3_050_002
        execution["gpu_observation"]["finish_returned_usec"] = 3_050_003
        self.assertIn("owner_stop_signal_delayed", validate_gpu_timing(gpu, execution)["reasons"])

    def test_poll_and_per_device_gaps_use_full_backend_query_brackets(self):
        gpu, execution = fixture()
        gpu["samples"] = [make_sample(0, 1000),
                          make_sample(3_000_000, 6_300_001, backend_start=6_300_000)]
        gpu["sample_count"] = 2
        gpu["stop_requested_monotonic_usec"] = 6_400_000
        gpu["stop_monotonic_usec"] = 6_400_001
        execution["gpu_observation"].update(stop_requested_usec=6_399_999, finish_returned_usec=6_400_002)
        result = validate_gpu_timing(gpu, execution)
        self.assertEqual(result["status"], "incomplete")
        self.assertIn("inter_poll_gap_exceeded", result["reasons"])
        self.assertIn("device_inter_gap_exceeded", result["reasons"])
        self.assertEqual(result["worst_device_inter_gap_usec"], 6_300_001)
        self.assertEqual(result["max_backend_duration_usec"], 1000)

    def test_device_missing_from_intermediate_poll_creates_per_device_gap(self):
        gpu, execution = fixture()
        gpu["samples"] = [make_sample(0, 1000, ("gpu-a", "gpu-b")),
                          make_sample(2_000_000, 2_001_000, ("gpu-a",)),
                          make_sample(4_000_000, 4_001_000, ("gpu-a", "gpu-b"))]
        gpu["stop_requested_monotonic_usec"] = 4_101_000
        gpu["stop_monotonic_usec"] = 4_102_000
        execution["gpu_observation"].update(stop_requested_usec=4_100_000, finish_returned_usec=4_103_000)
        result = validate_gpu_timing(gpu, execution)
        self.assertEqual(result["status"], "incomplete")
        self.assertNotIn("inter_poll_gap_exceeded", result["reasons"])
        self.assertIn("device_inter_gap_exceeded", result["reasons"])
        self.assertEqual(result["devices"]["gpu-b"]["max_inter_gap_usec"], 4_001_000)

    def test_start_and_tail_gaps_are_measured_from_owner_bounds(self):
        gpu, execution = fixture()
        gpu["samples"] = [make_sample(3_260_000, 3_261_000), make_sample(4_260_000, 4_261_000)]
        gpu["sample_count"] = 2
        gpu["stop_requested_monotonic_usec"] = 4_301_000
        gpu["stop_monotonic_usec"] = 4_302_000
        execution["gpu_observation"].update(stop_requested_usec=4_300_000, finish_returned_usec=4_303_000)
        result = validate_gpu_timing(gpu, execution)
        self.assertEqual(result["status"], "incomplete")
        self.assertIn("first_poll_gap_exceeded", result["reasons"])
        self.assertIn("device_first_gap_exceeded", result["reasons"])
        gpu, execution = fixture()
        gpu["samples"] = gpu["samples"][:2]
        gpu["sample_count"] = 2
        gpu["stop_requested_monotonic_usec"] = 5_001_000
        gpu["stop_monotonic_usec"] = 5_002_000
        execution["gpu_observation"].update(stop_requested_usec=5_000_000, finish_returned_usec=5_003_000)
        result = validate_gpu_timing(gpu, execution)
        self.assertEqual(result["status"], "incomplete")
        self.assertIn("last_poll_gap_exceeded", result["reasons"])
        self.assertIn("device_last_gap_exceeded", result["reasons"])

    def test_query_started_after_stop_cannot_forge_coverage(self):
        gpu, execution = fixture()
        gpu["samples"] = [make_sample(0, 1000), make_sample(1_000_000, 6_000_001,
                                                             backend_start=6_000_000)]
        gpu["sample_count"] = 2
        gpu["stop_requested_monotonic_usec"] = 2_001_000
        gpu["stop_monotonic_usec"] = 6_000_002
        execution["gpu_observation"].update(stop_requested_usec=2_000_000, finish_returned_usec=6_000_003)
        result = validate_gpu_timing(gpu, execution)
        self.assertEqual(result["status"], "incomplete")
        self.assertIn("backend_started_after_owner_stop", result["reasons"])

    def test_inflight_query_can_finish_after_owner_stop_but_is_not_credited(self):
        gpu, execution = fixture()
        gpu["samples"] = [make_sample(0, 1000), make_sample(1_000_000, 1_001_000),
                          make_sample(2_400_000, 2_700_000)]
        gpu["stop_requested_monotonic_usec"] = 2_501_000
        gpu["stop_monotonic_usec"] = 2_701_000
        execution["gpu_observation"].update(stop_requested_usec=2_500_000, finish_returned_usec=2_702_000)
        result = validate_gpu_timing(gpu, execution)
        self.assertEqual(result["status"], "complete", result)
        self.assertEqual(result["straddled_polls"], 1)
        self.assertEqual(result["straddled_device_observations"], 1)
        self.assertEqual(result["completed_polls"], 2)
        self.assertEqual(result["devices"]["gpu-a"]["completed_observations"], 2)
        self.assertEqual(result["last_poll_gap_usec"], 1_500_000)
        only_one = copy.deepcopy(gpu)
        only_one["samples"] = [gpu["samples"][0], gpu["samples"][2]]
        only_one["sample_count"] = 2
        result = validate_gpu_timing(only_one, execution)
        self.assertEqual(result["status"], "incomplete")
        self.assertIn("fewer_than_two_completed_device_observations", result["reasons"])

    def test_small_stop_race_is_ignored_for_coverage_but_large_is_incomplete(self):
        gpu, execution = fixture()
        gpu["samples"] = [make_sample(0, 1000), make_sample(1_000_000, 1_001_000),
                          make_sample(2_510_000, 2_520_000)]
        gpu["stop_requested_monotonic_usec"] = 2_530_000
        gpu["stop_monotonic_usec"] = 2_531_000
        execution["gpu_observation"].update(stop_requested_usec=2_500_000, finish_returned_usec=2_532_000)
        result = validate_gpu_timing(gpu, execution)
        self.assertEqual(result["status"], "complete", result)
        self.assertEqual(result["post_stop_polls"], 1)
        self.assertEqual(result["post_stop_device_observations"], 1)
        gpu["samples"][-1] = make_sample(2_551_000, 2_552_000)
        gpu["stop_monotonic_usec"] = 2_553_000
        execution["gpu_observation"]["finish_returned_usec"] = 2_554_000
        result = validate_gpu_timing(gpu, execution)
        self.assertEqual(result["status"], "incomplete")
        self.assertIn("poll_started_after_owner_stop", result["reasons"])

    def test_malformed_poll_and_backend_brackets_are_incomplete(self):
        for mutation in ("overlap", "duplicate_clock", "outside", "after_finish", "bad_device", "duplicate_device"):
            gpu, execution = fixture()
            if mutation == "overlap":
                gpu["samples"][1]["start_monotonic_usec"] = 0
            elif mutation == "duplicate_clock":
                gpu["samples"][0] = make_sample(0, 0)
                gpu["samples"][1] = make_sample(0, 0)
            elif mutation == "outside":
                gpu["samples"][1]["backends"][0]["start_monotonic_usec"] = 999_999
            elif mutation == "after_finish":
                gpu["samples"][-1]["end_monotonic_usec"] = 3_004_000
            elif mutation == "bad_device":
                gpu["samples"][1]["backends"][0]["devices"][0]["identity"] = {}
            else:
                gpu["samples"][1]["backends"][0]["devices"] *= 2
            with self.subTest(mutation=mutation):
                self.assertEqual(validate_gpu_timing(gpu, execution)["status"], "incomplete")

    def test_real_gpu_sampler_lifecycle_with_mocked_backend(self):
        csv = b'GPU-test, 0000:01:00.0, Mock GPU, 30, 10, 1500, 3000, 50, 70, 1000, 8000\n'
        def runner(argv, **kwargs):
            return subprocess.CompletedProcess(argv, 0, stdout=csv, stderr=b"")
        now_us = lambda: time.perf_counter_ns() // 1000
        owner = {"clock_domain": "python_perf_counter", "interval_seconds": 1, "max_samples": 4000,
                 "start_requested_usec": now_us()}
        sampler = GpuSampler(interval=1, max_samples=4000, platform="win32", runner=runner)
        # Exercise the actual worker/stop implementation with a fake query. The
        # shorter wait merely speeds this offline fixture; policy remains 1 s.
        original_wait = sampler._stop.wait
        sampler._stop.wait = lambda timeout: original_wait(min(timeout, .01))
        sampler.start()
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            with sampler._lock:
                if len(sampler._samples) >= 2:
                    break
            threading.Event().wait(.002)
        owner["stop_requested_usec"] = now_us()
        gpu = sampler.stop()
        owner["finish_returned_usec"] = now_us()
        self.assertEqual(gpu["status"], "available", gpu)
        result = validate_gpu_timing(gpu, {"gpu_observation": owner})
        self.assertEqual(result["status"], "complete", result)
        self.assertGreaterEqual(result["devices"]["nvidia:uuid:GPU-test"]["completed_observations"], 2)


if __name__ == "__main__":
    unittest.main()
