"""TQ-07-B3 (first slice): host reachability with hysteresis, backoff and a keeper heartbeat."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock

from tools.testqueue.agent_view import _host_view
from tools.testqueue.common import write_json
from tools.testqueue.pool import Pool


class FleetHealthTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-fleet-health-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        hosts = [{"id": name, "ssh": name, "python": "python3", "root": "/r", "agent": "/r/agent.py",
                  "engine": "/e", "engine_sha256": "f" * 64} for name in ("mac", "linux")]
        write_json(root / "config.json", {"state_root": str(root / "pool"), "hosts": hosts})
        self.pool = Pool(root / "config.json")
        self.up = {"mac": True, "linux": True}
        self.calls = []
        self.clock = [1_000_000.0]
        patches = (mock.patch.object(self.pool, "probe_host", side_effect=self.fake_probe),
                   mock.patch("tools.testqueue.pool.time.time", side_effect=lambda: self.clock[0]),
                   mock.patch("tools.testqueue.pool.time.sleep", side_effect=self.sleep))
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def sleep(self, seconds):
        self.clock[0] += seconds

    def fake_probe(self, host):
        self.calls.append(host["id"])
        if self.up[host["id"]]:
            return {"id": host["id"], "online": True, "busy": False, "platform": "linux"}
        return {"id": host["id"], "online": False, "reason": "ssh: connect to host port 22: Connection timed out"}

    def state(self, host):
        return self.pool.health()[host]["state"]

    def events(self):
        path = self.pool.root / "fleet-events.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def go_offline(self, host="mac"):
        self.up[host] = False
        self.pool.probe()
        self.clock[0] += Pool.HEALTH_CONFIRM_DELAY_SECONDS
        self.pool.probe()
        self.assertEqual(self.state(host), "OFFLINE")

    def test_two_failures_take_a_host_offline_and_placement_stops_waiting_on_it(self):
        self.up["mac"] = False
        self.pool.probe()
        self.assertEqual(self.state("mac"), "SUSPECT")
        self.clock[0] += Pool.HEALTH_CONFIRM_DELAY_SECONDS
        self.pool.probe()
        self.assertEqual(self.state("mac"), "OFFLINE")
        self.calls.clear()
        observations = {item["id"]: item for item in self.pool.probe()}
        self.assertEqual(self.calls, ["linux"])  # the offline host costs no connect timeout
        self.assertFalse(observations["mac"]["online"])
        self.assertTrue(observations["mac"]["reason"].startswith("offline since "))
        self.assertIn("Connection timed out", observations["mac"]["reason"])
        self.assertEqual([(event["host"], event["to"]) for event in self.events()],
                         [("linux", "ONLINE"), ("mac", "OFFLINE")])

    def test_the_heartbeat_backs_off_and_a_returning_host_rejoins_within_a_minute(self):
        self.up["mac"] = False
        self.pool.heartbeat()  # fails, then the confirming probe fails: OFFLINE in one pass
        self.assertEqual(self.state("mac"), "OFFLINE")
        checks = []
        for _ in range(12):  # twelve keeper passes, one every ten seconds
            self.clock[0] += 10
            self.calls.clear()
            self.pool.heartbeat()
            checks.append("mac" in self.calls)
        # 15 s, then 30 s, then 60 s between checks; never one per pass.
        self.assertLessEqual(sum(checks), 4)
        self.up["mac"] = True
        rejoined_after = None
        for step in range(1, 8):
            self.clock[0] += 10
            self.pool.heartbeat()
            if self.state("mac") == "ONLINE":
                rejoined_after = step * 10
                break
        self.assertIsNotNone(rejoined_after)
        self.assertLessEqual(rejoined_after, 60)
        self.assertEqual([event["to"] for event in self.events() if event["host"] == "mac"], ["OFFLINE", "ONLINE"])

    def test_a_flapping_host_never_goes_offline_and_logs_nothing(self):
        self.pool.probe()
        for index in range(10):
            self.up["mac"] = index % 2 == 0
            self.clock[0] += 5
            self.pool.probe()
            self.assertIn(self.state("mac"), {"ONLINE", "SUSPECT"})
        self.assertEqual([event["to"] for event in self.events() if event["host"] == "mac"], ["ONLINE"])

    def test_concurrent_placements_seeing_one_blip_count_one_failure(self):
        # B3 review: two submits probing in the same second are not "two in a row".
        self.up["mac"] = False
        for _ in range(3):
            self.pool.probe()
            self.clock[0] += 1
        self.assertEqual(self.state("mac"), "SUSPECT")
        self.up["mac"] = True
        self.pool.probe()
        self.assertEqual(self.state("mac"), "ONLINE")
        self.assertEqual([event["to"] for event in self.events() if event["host"] == "mac"], ["ONLINE"])

    def test_a_clock_stepping_back_never_holds_a_host_offline(self):
        self.go_offline()
        self.clock[0] -= 3600  # an NTP correction after a boot with a wrong clock
        self.up["mac"] = True
        self.calls.clear()
        self.pool.probe()
        self.assertIn("mac", self.calls)  # a next check an hour away is treated as due
        self.assertEqual(self.state("mac"), "ONLINE")  # and the "newer" stored time does not block the update

    def test_live_probes_ignore_backoff(self):
        self.go_offline()
        self.calls.clear()
        self.pool.probe(live=True)
        self.assertEqual(sorted(self.calls), ["linux", "mac"])

    def test_an_unreadable_health_file_is_never_replaced_by_a_partial_one(self):
        self.go_offline()
        before = (self.pool.root / "fleet-health.json").read_bytes()
        real = Pool.health

        def flaky(pool, *, strict=False):
            if strict:
                raise PermissionError(32, "sharing violation")
            return real(pool, strict=strict)

        with mock.patch.object(Pool, "health", flaky):
            self.pool._record_health([{"id": "linux", "online": True, "probed_at": self.clock[0]}])
        self.assertEqual((self.pool.root / "fleet-health.json").read_bytes(), before)

    def test_a_named_host_is_always_probed_and_placement_probes_inline_when_no_keeper_runs(self):
        self.go_offline()
        self.calls.clear()
        self.pool.probe("mac")  # an explicit request is never answered from the cache
        self.assertEqual(self.calls, ["mac"])
        self.calls.clear()
        self.clock[0] += 60 + Pool.HEALTH_INLINE_GRACE + 1  # due, and no heartbeat made the check
        self.pool.probe()
        self.assertIn("mac", self.calls)

    def test_an_older_observation_never_overwrites_a_newer_one(self):
        self.pool.probe()
        stale = {"id": "mac", "online": False, "reason": "late reply", "probed_at": self.clock[0] - 30}
        self.pool._record_health([stale])
        self.assertEqual(self.state("mac"), "ONLINE")

    def test_the_fleet_view_shows_when_an_offline_host_is_checked_next(self):
        self.go_offline()
        observation = next(item for item in self.pool.probe() if item["id"] == "mac")
        view = _host_view(observation, {})
        self.assertRegex(view["offline_reason"], r"^offline since \d\d:\d\d:\d\d, next check in \d+ s: ssh")


if __name__ == "__main__":
    unittest.main()
