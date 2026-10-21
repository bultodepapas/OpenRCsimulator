import copy
import unittest

from native_performance_report import assess


class WorkloadAcceptance(unittest.TestCase):
    def setUp(self):
        self._capture()

    def _capture(self, frame_usec=10000):
        count = 6000
        final_tick = 2400 + count * frame_usec * 240 // 1000000
        self.fixture = {"active_flight_endpoint": True, "initial": {"tick": 0},
                        "final": {"tick": final_tick, "paused": False, "crashed": False, "prop_strike": False, "fault": ""}}
        self.frames = {"complete": True, "failure": "", "os": "Windows", "backend": "gl_compatibility",
                       "window": "1280x720", "actual_sample_s": count * frame_usec / 1e6,
                       "actual_warmup_s": 10.0, "actual_sample_start_monotonic_usec": 10000000,
                       "actual_sample_end_monotonic_usec": 10000000 + count * frame_usec, "input_enabled": True,
                       "simulation": {"end_tick": final_tick, "physics_enabled": True, "paused": False,
                                      "fault": "", "physics_ticks_per_second": 240},
                       "frames": count, "raw_metrics": {"sim_tick": [2400 + i * frame_usec * 240 // 1000000 for i in range(1, count + 1)]},
                       "frame_end_monotonic_usec": [10000000 + i * frame_usec for i in range(1, count + 1)],
                       "frame_wall_usec": [frame_usec] * count,
                       "frame_ms": dict.fromkeys(["p50", "p95", "p99", "max"], frame_usec / 1000),
                       "flight_companions": {"status": {"active": 1, "error": "", "faulted": 0, "crashed": 0},
                                             "roster": [{"tick": final_tick, "paused": False, "crashed": False, "fault": "", "failure": ""}]}}

    def test_active_clock_and_budget(self):
        self.assertTrue(assess(self.frames, self.fixture, 1)["render_budget_pass"])

    def test_smooth_frames_cannot_hide_inactive_or_slow_flight(self):
        original = self.frames["raw_metrics"]["sim_tick"]
        for values in [[2400] * len(original), [2400 + (t - 2400) // 2 for t in original], list(reversed(original))]:
            frames = copy.deepcopy(self.frames)
            frames["raw_metrics"]["sim_tick"] = values
            self.assertFalse(assess(frames, self.fixture, 1)["valid_active_workload"])

    def test_paused_crashed_and_desynchronized_fleet_refuse(self):
        for key, value in [("paused", True), ("crashed", True), ("tick", 16799), ("failure", "lost packet")]:
            frames = copy.deepcopy(self.frames)
            frames["flight_companions"]["roster"][0][key] = value
            self.assertFalse(assess(frames, self.fixture, 1)["valid_active_workload"])

    def test_endpoint_damage_refuses(self):
        for key in ["paused", "crashed", "prop_strike"]:
            fixture = copy.deepcopy(self.fixture)
            fixture["final"][key] = True
            self.assertFalse(assess(self.frames, fixture, 1)["valid_active_workload"])

    def test_valid_slow_frames_are_budget_failure(self):
        self._capture(frame_usec=20000)
        result = assess(self.frames, self.fixture, 1)
        self.assertTrue(result["valid_active_workload"])
        self.assertFalse(result["render_budget_pass"])

    def test_short_sample_wrong_count_and_missing_samples_refuse(self):
        for key, value in [("actual_sample_s", 59.0), ("frames", 4), ("complete", False)]:
            frames = copy.deepcopy(self.frames)
            frames[key] = value
            self.assertFalse(assess(frames, self.fixture, 1)["valid_active_workload"])
        self.assertFalse(assess(self.frames, self.fixture, 2)["valid_active_workload"])

    def test_short_warmup_and_inconsistent_sample_endpoints_refuse(self):
        for key, value in [("actual_warmup_s", 9.0), ("actual_sample_end_monotonic_usec", 71000000),
                           ("actual_sample_start_monotonic_usec", 0)]:
            frames = copy.deepcopy(self.frames)
            frames[key] = value
            self.assertFalse(assess(frames, self.fixture, 1)["valid_active_workload"])

    def test_summary_cannot_hide_raw_slow_frames(self):
        self._capture(frame_usec=20000)
        self.frames["frame_ms"] = dict.fromkeys(["p50", "p95", "p99", "max"], 10.0)
        result = assess(self.frames, self.fixture, 1)
        self.assertFalse(result["render_budget_pass"])
        self.assertIn("reported frame percentiles disagree with raw frames", result["invalid_reasons"])

    def test_raw_duration_and_timestamp_mismatch_refuses(self):
        self.frames["frame_wall_usec"][100] += 1
        self.assertFalse(assess(self.frames, self.fixture, 1)["valid_active_workload"])

    def test_nonfinite_boolean_and_wrong_shapes_refuse_without_exception(self):
        for key, value in [("frames", True), ("simulation", []), ("actual_sample_s", float("nan")),
                           ("actual_warmup_s", float("inf")), ("frame_ms", None), ("frame_wall_usec", "bad")]:
            frames = copy.deepcopy(self.frames)
            frames[key] = value
            self.assertFalse(assess(frames, self.fixture, 1)["valid_active_workload"])
        for value in [None, True, float("nan"), float("inf"), -1, "x"]:
            frames = copy.deepcopy(self.frames)
            frames["raw_metrics"]["sim_tick"][3] = value
            self.assertFalse(assess(frames, self.fixture, 1)["valid_active_workload"])


if __name__ == "__main__":
    unittest.main()
