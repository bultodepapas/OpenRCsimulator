"""Robust advisory duration history: window, median, legacy reads and peer estimates."""
import math
import unittest

from tools.testqueue import pool_history
from tools.testqueue.pool_policy import plan


def host(identifier, **values):
    value = {"id": identifier, "online": True, "busy": False, "platform": "linux",
             "capabilities": ["headless"], "free_disk_bytes": 2**40, "free_memory_bytes": 2**40,
             "cores": 8, "load": 0, "cached_inputs": ["src"], "durations": {}}
    value.update(values)
    return value


class PoolHistoryTests(unittest.TestCase):
    def test_window_keeps_newest_samples_and_median_resists_one_cold_run(self):
        history = {}
        for seconds in [10, 11, 9, 10, 300]:
            pool_history.record(history, "linux", "res://tests/a.gd", seconds)
        self.assertEqual(pool_history.estimate(history["linux"]["res://tests/a.gd"]), 10)
        for seconds in range(20):
            pool_history.record(history, "linux", "res://tests/a.gd", 5)
        self.assertEqual(history["linux"]["res://tests/a.gd"]["samples"], [5.0] * pool_history.WINDOW)

    def test_legacy_scalar_and_invalid_entries(self):
        history = {"linux": {"a": 4.0, "b": "bad", "c": {"samples": [math.inf, -1, "x", 6]},
                             pool_history.SETUP_KEY: 3}}
        pool_history.record(history, "linux", "a", 8)
        self.assertEqual(history["linux"]["a"]["samples"], [4.0, 8.0])
        durations, sources, setup = pool_history.host_view(history, "linux", 5)
        self.assertEqual(durations, {"a": 6.0, "c": 6.0})
        self.assertEqual(set(sources.values()), {"history"})
        self.assertEqual(setup, 3)
        self.assertEqual(pool_history.host_view({}, "linux", 5), ({}, {}, 5))
        self.assertEqual(pool_history.host_view([], "linux", 0), ({}, {}, 0))
        for bad in [math.nan, -1, "1"]:
            with self.assertRaises(ValueError):
                pool_history.record({}, "linux", "a", bad)
        pool_history.record(history, "linux", "zero", 0)
        self.assertEqual(history["linux"]["zero"], {"samples": [pool_history.MINIMUM_SECONDS], "ids": [None]})

    def test_retried_collection_of_one_job_adds_one_sample(self):
        history = {}
        self.assertTrue(pool_history.record(history, "linux", "a", 10, "job1"))
        self.assertFalse(pool_history.record(history, "linux", "a", 10, "job1"))
        self.assertTrue(pool_history.record(history, "linux", "a", 12, "job2"))
        self.assertEqual(history["linux"]["a"], {"samples": [10.0, 12.0], "ids": ["job1", "job2"]})
        legacy = {"linux": {"a": 4}}
        pool_history.record(legacy, "linux", "a", 6, "job3")
        self.assertEqual(legacy["linux"]["a"], {"samples": [4.0, 6.0], "ids": [None, "job3"]})

    def test_tiny_or_overflowing_values_cannot_disqualify_or_crash(self):
        history = {"fast": {"x": 0.0001, "base": 1.0, "huge": 10**400},
                   "slow": {"base": 0.0001, pool_history.SETUP_KEY: 10**400}}
        self.assertEqual(pool_history.estimate(history["fast"]["x"]), pool_history.MINIMUM_SECONDS)
        durations, sources, setup = pool_history.host_view(history, "slow", 5)
        self.assertGreaterEqual(durations["x"], pool_history.MINIMUM_SECONDS)
        self.assertNotIn("huge", durations)
        self.assertEqual(setup, 5)
        candidate = plan({"duration_key": "x", "cache_id": "src"},
                         [host("slow", durations=durations, duration_sources=sources)])["candidates"][0]
        self.assertTrue(candidate["eligible"], candidate["reasons"])

    def test_unmeasured_host_assumes_at_least_the_peer_setup(self):
        history = {"warm": {"t": 10, pool_history.SETUP_KEY: 40}}
        self.assertEqual(pool_history.host_view(history, "cold", 5)[2], 40)
        self.assertEqual(pool_history.host_view(history, "cold", 60)[2], 60)
        self.assertEqual(pool_history.host_view(history, "warm", 5)[2], 40)

    def test_unmeasured_host_borrows_a_speed_scaled_peer_estimate(self):
        history = {"fast": {"shared": 10, "only-fast": 40}, "slow": {"shared": 20}}
        durations, sources, _ = pool_history.host_view(history, "slow", 5)
        self.assertEqual(durations["only-fast"], 80)
        self.assertEqual(sources, {"shared": "history", "only-fast": "peer"})
        durations, sources, _ = pool_history.host_view(history, "new", 5)
        self.assertEqual(durations, {"shared": 15.0, "only-fast": 40})
        self.assertEqual(set(sources.values()), {"peer"})
        self.assertEqual(pool_history.expected_seconds(history, "shared"), 10)
        self.assertIsNone(pool_history.expected_seconds(history, "missing"))

    def test_peer_estimate_competes_instead_of_the_full_timeout(self):
        history = {"measured": {"t": 30}}
        job = {"duration_key": "t", "estimated_seconds": 3600, "cache_id": "src"}
        hosts = []
        for identifier, load in [("measured", 6), ("unmeasured", 0)]:
            durations, sources, setup = pool_history.host_view(history, identifier, 0)
            hosts.append(host(identifier, load=load, durations=durations, duration_sources=sources,
                              setup_seconds=setup))
        decision = plan(job, hosts)
        self.assertEqual(decision["selected"], "unmeasured")
        scores = {item["host"]: item["score"] for item in decision["candidates"]}
        self.assertEqual(scores["unmeasured"]["duration_source"], "peer")
        self.assertEqual(scores["measured"]["duration_source"], "history")
        hosts[1]["duration_sources"] = {"t": "invented"}
        self.assertEqual({item["host"]: item["score"]["duration_source"]
                          for item in plan(job, hosts)["candidates"]}["unmeasured"], "history")


if __name__ == "__main__":
    unittest.main()
