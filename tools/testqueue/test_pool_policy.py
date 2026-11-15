"""Host selection is advisory and never relaxes the host admission contract."""
from copy import deepcopy
import unittest

from tools.testqueue import pool_policy


MIB = 1024 * 1024
GIB = 1024 * MIB


def host(host_id, **overrides):
    result = {"id": host_id, "platform": "linux", "online": True, "busy": False,
              "capabilities": ["headless", "graphics", "performance"],
              "free_disk_bytes": 10 * GIB, "free_memory_bytes": 4 * GIB,
              "cores": 8, "load": 0, "cached_inputs": [], "durations": {}}
    result.update(overrides)
    return result


def candidate(plan, name):
    return next(item for item in plan["candidates"] if item["host"] == name)


class PoolPolicyTests(unittest.TestCase):
    def test_platform_offline_busy_and_capabilities_are_hard_rejections(self):
        hosts = [host("windows", platform="windows"),
                 host("busy", busy=True), host("offline", online=False),
                 host("no-graphics", capabilities=["headless"]), host("ready")]
        decision = pool_policy.plan({"platform": "linux", "workload": "graphics"}, hosts)
        self.assertEqual(decision["selected"], "ready")
        for name, reason in (("windows", "PLATFORM_MISMATCH"), ("busy", "BUSY"),
                             ("offline", "OFFLINE"), ("no-graphics", "CAPABILITY_MISSING")):
            result = candidate(decision, name)
            self.assertFalse(result["eligible"])
            self.assertTrue(any(item.startswith(reason) for item in result["reasons"]))
            self.assertIsNone(result["score"])

    def test_cache_avoids_transfer_and_one_disk_copy(self):
        job = {"source_bytes": GIB, "cache_id": "snapshot-a", "estimated_seconds": 30}
        remote = host("remote", transfer_bytes_per_second=10 * MIB, setup_seconds=5)
        cached = host("cached", cached_inputs=["snapshot-a"], transfer_bytes_per_second=10 * MIB, setup_seconds=5)
        decision = pool_policy.plan(job, [remote, cached])
        self.assertEqual(decision["selected"], "cached")
        remote_score = candidate(decision, "remote")["score"]
        cached_score = candidate(decision, "cached")["score"]
        self.assertEqual(remote_score["transfer_seconds"], 102.4)
        self.assertEqual(cached_score["transfer_seconds"], 0)
        self.assertEqual(remote_score["required_disk_bytes"] - cached_score["required_disk_bytes"], GIB)
        self.assertFalse(remote_score["cached"])
        self.assertTrue(cached_score["cached"])

    def test_locality_is_an_estimate_not_a_blanket_preference(self):
        job = {"source_bytes": 2 * GIB, "duration_key": "test-a", "estimated_seconds": 50}
        local = host("local", local=True, durations={"test-a": 50})
        remote = host("remote", durations={"test-a": 5})
        # The local copy saves transfer time and wins for this input size.
        self.assertEqual(pool_policy.plan(job, [local, remote])["selected"], "local")
        # With the same source already cached remotely, its measured test time wins.
        remote["cached_inputs"] = ["snapshot-a"]
        job["cache_id"] = "snapshot-a"
        decision = pool_policy.plan(job, [local, remote])
        self.assertEqual(decision["selected"], "remote")
        self.assertEqual(candidate(decision, "remote")["score"]["duration_source"], "history")

    def test_load_and_history_are_per_test_and_deterministic(self):
        job = {"duration_key": "test-a", "estimated_seconds": 40}
        hosts = [host("z", local=True, load=8, durations={"test-a": 20}),
                 host("a", local=True, durations={"other-test": 1}),
                 host("b", local=True, durations={"test-a": 50})]
        before = deepcopy((job, hosts))
        forward = pool_policy.plan(job, hosts)
        reverse = pool_policy.plan(job, list(reversed(hosts)))
        self.assertEqual(forward, reverse)
        self.assertEqual(forward["selected"], "a")  # 40-second tie, ID breaks it.
        self.assertEqual(candidate(forward, "z")["score"]["load_factor"], 2)
        self.assertEqual(candidate(forward, "a")["score"]["duration_source"], "estimate")
        self.assertEqual((job, hosts), before)  # Planning has no side effects.

    def test_performance_requires_exact_host_and_requested_graphics_gpu(self):
        with self.assertRaisesRegex(ValueError, "performance_host"):
            pool_policy.plan({"workload": "performance"}, [])
        job = {"workload": "performance", "performance_host": "mac-1", "requires_graphics": True,
               "required_gpu": "Apple M1"}
        other = host("mac-2", platform="darwin", gpu="Apple M1")
        intended = host("mac-1", platform="darwin", gpu="Apple M1", busy=True)
        decision = pool_policy.plan(job, [other, intended])
        self.assertIsNone(decision["selected"])
        self.assertIn("BUSY", candidate(decision, "mac-1")["reasons"])
        self.assertTrue(any(reason.startswith("PERFORMANCE_AFFINITY") for reason in candidate(decision, "mac-2")["reasons"]))
        intended["busy"] = False
        intended["capabilities"] = ["headless", "performance"]
        intended["gpu"] = "different"
        decision = pool_policy.plan(job, [other, intended])
        self.assertIsNone(decision["selected"])
        reasons = candidate(decision, "mac-1")["reasons"]
        self.assertIn("CAPABILITY_MISSING: graphics", reasons)
        self.assertIn("GPU_MISMATCH: requires Apple M1", reasons)
        intended["capabilities"].append("graphics")
        intended["gpu"] = "Apple M1"
        self.assertEqual(pool_policy.plan(job, [other, intended])["selected"], "mac-1")

    def test_headless_performance_requires_both_capabilities(self):
        job = {"workload": "performance", "performance_host": "host"}
        decision = pool_policy.plan(job, [host("host", capabilities=["performance"])])
        self.assertIsNone(decision["selected"])
        self.assertIn("CAPABILITY_MISSING: headless", candidate(decision, "host")["reasons"])

    def test_disk_and_memory_reserves_are_required_even_at_boundaries(self):
        job = {"source_bytes": 100, "cache_id": "id", "disk_bytes": 20, "memory_bytes": 50}
        disk = pool_policy.DISK_RESERVE_BYTES + 220
        memory = pool_policy.MEMORY_RESERVE_BYTES + 50
        exact = host("exact", local=True, free_disk_bytes=disk, free_memory_bytes=memory)
        insufficient_disk = host("disk", local=True, free_disk_bytes=disk - 1)
        insufficient_memory = host("memory", local=True, free_memory_bytes=memory - 1)
        unknown = host("unknown", local=True, free_memory_bytes=None, free_disk_bytes=None)
        decision = pool_policy.plan(job, [exact, insufficient_disk, insufficient_memory, unknown])
        self.assertEqual(decision["selected"], "exact")
        self.assertTrue(candidate(decision, "disk")["reasons"][0].startswith("INSUFFICIENT_DISK"))
        self.assertTrue(candidate(decision, "memory")["reasons"][0].startswith("INSUFFICIENT_MEMORY"))
        self.assertTrue(any(item.startswith("DISK_UNKNOWN") for item in candidate(decision, "unknown")["reasons"]))
        self.assertTrue(any(item.startswith("MEMORY_UNKNOWN") for item in candidate(decision, "unknown")["reasons"]))
        # A verified cached source saves the extra transfer copy, not the workspace copy.
        insufficient_disk["cached_inputs"] = ["id"]
        self.assertTrue(candidate(pool_policy.plan(job, [insufficient_disk]), "disk")["eligible"])

    def test_remote_input_and_workspace_copies_are_counted(self):
        job = {"source_bytes": GIB, "cache_id": "id"}
        decision = pool_policy.plan(job, [host("local", local=True), host("remote")])
        local = candidate(decision, "local")["score"]["required_disk_bytes"]
        remote = candidate(decision, "remote")["score"]["required_disk_bytes"]
        self.assertEqual(local, pool_policy.DISK_RESERVE_BYTES + 2 * GIB)
        self.assertEqual(remote, pool_policy.DISK_RESERVE_BYTES + 3 * GIB)
        cached = pool_policy.plan(job, [host("remote", cached_inputs=["id"])])
        self.assertEqual(candidate(cached, "remote")["score"]["required_disk_bytes"], local)

    def test_invalid_inputs_do_not_create_an_eligible_host(self):
        for job in ({"workload": "gpu"}, {"workload": []}, {"platform": []}, {"source_bytes": -1}, {"memory_bytes": True},
                    {"estimated_seconds": float("nan")}, {"requires_graphics": True},
                    {"required_gup": "typo"}):
            with self.subTest(job=job), self.assertRaises(ValueError):
                pool_policy.plan(job, [])
        with self.assertRaisesRegex(ValueError, "unique"):
            pool_policy.plan({}, [host("duplicate"), host("duplicate")])
        for invalid in ({"load": None}, {"cores": 0}, {"online": None}, {"busy": None}, {"platform": []},
                        {"capabilities": None}, {"transfer_bytes_per_second": 0},
                        {"durations": {"test": -1}}):
            with self.subTest(invalid=invalid):
                decision = pool_policy.plan({"duration_key": "test"}, [host("invalid", **invalid)])
                self.assertIsNone(decision["selected"])
                self.assertTrue(candidate(decision, "invalid")["reasons"])
        self.assertEqual(pool_policy.plan({}, []), {"selected": None, "candidates": []})


if __name__ == "__main__":
    unittest.main()
