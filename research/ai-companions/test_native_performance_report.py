import copy
import unittest

from native_performance_report import assess


class WorkloadAcceptance(unittest.TestCase):
    def setUp(self):
        self.fixture = {"active_flight_endpoint": True, "initial": {"tick": 0},
                        "final": {"tick": 16800, "paused": False, "crashed": False, "prop_strike": False, "fault": ""}}
        self.frames = {"complete": True, "failure": "", "os": "Windows", "backend": "gl_compatibility",
                       "window": "1280x720", "actual_sample_s": 60.0, "input_enabled": True,
                       "simulation": {"end_tick": 16800, "physics_enabled": True, "paused": False,
                                      "fault": "", "physics_ticks_per_second": 240},
                       "frames": 3, "raw_metrics": {"sim_tick": [2400, 9600, 16800]},
                       "frame_end_monotonic_usec": [10000000, 40000000, 70000000],
                       "frame_ms": {"p95": 12.0, "p99": 20.0},
                       "flight_companions": {"status": {"active": 1, "error": "", "faulted": 0, "crashed": 0},
                                             "roster": [{"tick": 16800, "paused": False, "crashed": False, "fault": "", "failure": ""}]}}

    def test_active_clock_and_budget(self):
        self.assertTrue(assess(self.frames, self.fixture, 1)["render_budget_pass"])

    def test_smooth_frames_cannot_hide_inactive_or_slow_flight(self):
        for values in [[2400, 2400, 2400], [2400, 6000, 9600], [9600, 2400, 16800]]:
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
        self.frames["frame_ms"]["p95"] = 20.0
        result = assess(self.frames, self.fixture, 1)
        self.assertTrue(result["valid_active_workload"])
        self.assertFalse(result["render_budget_pass"])

    def test_short_sample_wrong_count_and_missing_samples_refuse(self):
        for key, value in [("actual_sample_s", 59.0), ("frames", 4), ("complete", False)]:
            frames = copy.deepcopy(self.frames)
            frames[key] = value
            self.assertFalse(assess(frames, self.fixture, 1)["valid_active_workload"])
        self.assertFalse(assess(self.frames, self.fixture, 2)["valid_active_workload"])


if __name__ == "__main__":
    unittest.main()
