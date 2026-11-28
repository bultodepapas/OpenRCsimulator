"""TQ-07-D1–D3: a reviewed registry routes known-portable checks to any free listed OS."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tools.testqueue import pool_mcp, routing
from tools.testqueue.pool_batch import _host_lanes
from tools.testqueue.pool_policy import plan, platform_set


def host(name, system, **extra):
    return {"id": name, "platform": system, "online": True, "busy": False, "capabilities": ["headless"],
            "free_disk_bytes": 10**11, "free_memory_bytes": 10**10, "load": 0.0, "cores": 8, **extra}


class RegistryTests(unittest.TestCase):
    def test_committed_registry_is_valid_and_names_existing_scripts(self):
        self.assertEqual(routing.check(), [])
        entries = routing.load()
        self.assertIn("res://tests/test_math3d.gd", entries)
        for entry in entries.values():
            self.assertGreaterEqual(len(entry["os"]), 2, entry["script"])  # seeded from multi-OS passes only

    def test_bad_entries_are_refused_and_a_broken_registry_routes_nothing(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "routing.json"
            for entry in ({"script": "res://tests/x.gd", "os": ["windows", "windows"], "evidence": "e"},
                          {"script": "res://tests/x.gd", "os": ["beos"], "evidence": "e"},
                          {"script": "res://tests/x.gd", "os": ["linux"]},
                          {"script": "res://tests/x.gd", "os": ["linux"], "evidence": "e", "extra": 1}):
                with self.subTest(entry=entry):
                    path.write_text(json.dumps({"format": routing.FORMAT, "entries": [entry]}))
                    with self.assertRaises(ValueError):
                        routing.load(path)
                    self.assertIsNone(routing.lookup("res://tests/x.gd", path))

    def test_platform_of_an_entry(self):
        self.assertEqual(routing.platform_of({"os": ["darwin", "linux", "windows"]}), "any")
        self.assertEqual(routing.platform_of({"os": ["linux", "darwin"]}), ["darwin", "linux"])
        self.assertEqual(routing.platform_of({"os": ["linux"]}), "linux")


class PlacementTests(unittest.TestCase):
    def test_a_platform_list_admits_exactly_its_operating_systems(self):
        hosts = [host("windows", "windows"), host("linux", "linux"), host("angela", "darwin")]
        self.assertEqual(platform_set(["linux", "darwin"]), frozenset({"linux", "darwin"}))
        decision = plan({"platform": ["linux", "darwin"]}, hosts)
        eligible = {item["host"] for item in decision["candidates"] if item["eligible"]}
        self.assertEqual(eligible, {"linux", "angela"})
        refusal = next(item for item in decision["candidates"] if item["host"] == "windows")["reasons"]
        self.assertEqual(refusal, ["PLATFORM_MISMATCH: requires darwin/linux"])
        for bad in ([], ["linux", "linux"], ["solaris"], "solaris", 3):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                platform_set(bad)

    def test_the_busy_preferred_os_spills_to_a_free_listed_one(self):
        # 28 November: Windows was busy and Linux idle, but checks defaulted to Windows.
        hosts = [host("windows", "windows", busy=True, busy_reason="RUNNING_QUEUE_WORK"), host("linux", "linux")]
        self.assertEqual(plan({"platform": ["windows", "linux"]}, hosts)["selected"], "linux")
        self.assertIsNone(plan({"platform": "windows"}, hosts)["selected"])

    def test_overlapping_os_sets_share_one_batch_lane(self):
        rows = [{"input": {"host": None, "platform": ["linux", "darwin"]}},
                {"input": {"host": None, "platform": "windows"}}]
        self.assertEqual(len(_host_lanes(rows)), 1)


class McpDefaultTests(unittest.TestCase):
    def jobs(self, job, system="Windows"):
        with mock.patch.object(pool_mcp.platform, "system", return_value=system):
            return pool_mcp._jobs([job])[0]

    def test_registry_fills_what_the_agent_omitted(self):
        entry = routing.lookup("res://tests/test_math3d.gd")
        item = self.jobs({"script": "res://tests/test_math3d.gd"})
        self.assertEqual(item["platform"], routing.platform_of(entry))
        self.assertEqual(item["require"], entry["require"])
        self.assertEqual(item["timeout"], entry["timeout"])

    def test_explicit_fields_win_and_unknown_scripts_keep_the_caller_os(self):
        explicit = self.jobs({"script": "res://tests/test_math3d.gd", "platform": "windows",
                              "require": ["custom"], "timeout": 30})
        self.assertEqual((explicit["platform"], explicit["require"], explicit["timeout"]), ("windows", ["custom"], 30))
        self.assertEqual(self.jobs({"script": "res://tests/test_not_registered.gd"}, "Linux")["platform"], "linux")
        listed = self.jobs({"script": "res://tests/test_not_registered.gd", "platform": ["linux", "darwin"]})
        self.assertEqual(listed["platform"], ["darwin", "linux"])
        gpu = self.jobs({"script": "res://tests/test_math3d.gd", "rendering_driver": "vulkan"})
        self.assertEqual(gpu["platform"], "linux")  # the GPU lane ignores the headless registry


if __name__ == "__main__":
    unittest.main()
