"""TQ-07-A9b–f: a remote job the supervisor lost is settled only with proof.

b: a stage's identity is durable before its gate is released, so a record
   without one proves nothing ran.
c: a slow process listing is a missing observation, not a teardown.
d: a supervisor still waiting for the lock is not declared lost.
e: a reserve is released just before the terminal journal.
f: a reboot settles every UNKNOWN job it proves ended.
"""
from __future__ import annotations

import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from unittest import mock

from tools.testqueue import processes, remote_agent as agent
from tools.testqueue.test_remote_agent import FAKE_RUNNER


class GateReleaseTests(unittest.TestCase):
    """The gate holds its command until released; unreleased, it never runs it."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-gate-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.marker = self.root / "ran.txt"

    def owned(self):
        code = f"from pathlib import Path; Path({str(self.marker)!r}).write_text('ran')"
        process = processes.OwnedProcess([sys.executable, "-c", code], self.root, os.environ.copy(),
                                         self.root / ("log-" + str(time.monotonic_ns()) + ".txt"))
        self.addCleanup(process.close)
        return process

    def test_unreleased_gate_never_runs_and_released_gate_does(self):
        held = self.owned()
        held.start(release=False)
        time.sleep(0.5)
        self.assertFalse(self.marker.exists())
        held.close_unreleased()  # the owner gives up before releasing; teardown is witnessed
        time.sleep(0.3)
        self.assertFalse(self.marker.exists())
        released = self.owned()
        released.start(release=False)
        released.release()
        deadline = time.monotonic() + 10
        while not self.marker.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertTrue(self.marker.exists())
        with self.assertRaises(RuntimeError):
            released.release()  # one release only


class LaunchOrderTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-launch-order-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        (self.root / "incoming").mkdir()
        (self.root / "jobs").mkdir()
        self.engine = self.root / "engine-fixture"
        self.engine.write_bytes(b"#!/bin/sh\nexit 0\n")
        self.engine.chmod(0o755)

    def archive(self):
        path = self.root / "incoming" / "source.tar"
        with tarfile.open(path, "w") as bundle:
            for name, text in (("app/project.godot", '[application]\nconfig/name="OpenRC Simulator"\n'),
                               ("app/tests/test_sample.gd", "extends SceneTree\n"),
                               ("tools/godot/run_checked.py", FAKE_RUNNER)):
                data = text.encode()
                info = tarfile.TarInfo(name)
                info.size = len(data)
                bundle.addfile(info, io.BytesIO(data))
        return path

    def accept(self, identifier="job1"):
        archive = self.archive()
        request = {"request_id": identifier, "preset": "checked",
                   "archive": {"path": str(archive), "sha256": agent.digest(archive)},
                   "engine_path": str(self.engine), "expected_engine_sha256": agent.digest(self.engine),
                   "options": {"script": "res://tests/test_sample.gd", "require": ["0 failed"], "timeout": 90}}
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent.subprocess, "Popen"):
            agent.launch(self.root, request)
        return request

    def journal(self, identifier="job1", **changes):
        path = agent.state_path(self.root, identifier)
        state = agent.read_json(path)
        state.update(changes)
        agent.write_json(path, state)

    def clone(self, identifier, **changes):
        # A host admits one job at a time; further records are written directly.
        state = agent.read_json(agent.state_path(self.root, "job1"))
        state.update(request_id=identifier, **changes)
        agent.write_json(agent.state_path(self.root, identifier), state)

    def supervise(self, identifier="job1"):
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "external_engine_present", return_value=False):
            return agent.supervise(self.root, identifier)

    # b ---------------------------------------------------------------
    def test_a_record_without_identity_written_in_the_new_order_proves_nonlaunch(self):
        self.accept()
        self.journal(state="RUNNING", stage="check", launch_order=agent.LAUNCH_ORDER)
        status = agent.status(self.root, "job1")
        self.assertEqual((status["state"], status["outcome"], status["cleanup"], status["launch"], status["reason_code"]),
                         ("FINISHED", "INFRA_FAILED", "CONFIRMED", "NOT_CREATED", "SUPERVISOR_LOST"))
        self.assertEqual(agent.scan(self.root), [])  # the host is not quarantined

    def test_after_the_import_ran_only_the_check_is_claimed_not_launched(self):
        self.accept()
        self.journal(state="RUNNING", stage="check", launch_order=agent.LAUNCH_ORDER,
                     reason_code="CHECK_TIMEOUT", **{"import": {"ok": True, "complete": True}})
        status = agent.status(self.root, "job1")
        self.assertEqual((status["state"], status["cleanup"], status["nonlaunch_stage"]), ("FINISHED", "CONFIRMED", "check"))
        self.assertNotIn("launch", status)  # the import did run (and was torn down)
        self.assertEqual(status["previous_reason_code"], "CHECK_TIMEOUT")

    def test_with_an_identity_or_from_an_older_agent_it_stays_quarantined(self):
        self.accept("job1")
        self.journal("job1", state="RUNNING", launch_order=agent.LAUNCH_ORDER, process={"pid": 99, "host": "h", "boot": "b"})
        self.clone("job2", state="RUNNING", launch_order=None, process=None)  # an older agent wrote it
        for identifier in ("job1", "job2"):
            with self.subTest(identifier=identifier):
                self.assertEqual(agent.status(self.root, identifier)["state"], "UNKNOWN")

    def test_identity_journal_retries_and_only_then_fails_closed_without_running(self):
        self.accept()
        real_write = agent.write_json
        failures = []

        def fail_identity(path, value):
            if value.get("state") == "RUNNING" and value.get("process"):
                failures.append(value.get("stage"))
                raise OSError(28, "No space left on device")
            return real_write(path, value)

        with mock.patch.object(agent, "write_json", side_effect=fail_identity), \
                mock.patch.object(agent, "TERMINAL_WRITE_DELAY", 0):
            self.supervise()
        status = agent.status(self.root, "job1")
        self.assertEqual(failures, ["import"] * agent.TERMINAL_WRITE_ATTEMPTS)
        self.assertEqual((status["state"], status["outcome"], status["cleanup"]), ("FINISHED", "INFRA_FAILED", "CONFIRMED"))
        self.assertEqual(status["import"]["reason"], "journal_unavailable_before_release")
        self.assertFalse((self.root / "jobs/job1/import-result.json").exists())  # the runner never ran

    # c ---------------------------------------------------------------
    def test_a_slow_process_listing_does_not_tear_down_healthy_work(self):
        self.accept()
        real_alive = processes.OwnedProcess.alive
        calls = {"n": 0}

        def flaky(process):
            calls["n"] += 1
            if calls["n"] <= 2:
                raise subprocess.TimeoutExpired("ps", 2)
            return real_alive(process)

        with mock.patch.object(processes.OwnedProcess, "alive", flaky):
            self.assertEqual(self.supervise(), 0)
        status = agent.status(self.root, "job1")
        self.assertEqual((status["outcome"], status["cleanup"]), ("PASSED", "CONFIRMED"), status)
        self.assertGreater(calls["n"], 2)

    # d ---------------------------------------------------------------
    def test_a_waiting_supervisor_is_not_declared_lost(self):
        self.accept()
        self.journal(accepted_at=time.time() - 3600, supervisor_pid=4242)
        with mock.patch.object(agent, "supervisor_alive", return_value=True):
            self.assertEqual(agent.status(self.root, "job1")["state"], "STARTING")
        # A dead supervisor whose preparation helper (an import-cache copy) still
        # runs is observed again later, not settled (review finding).
        with mock.patch.object(agent, "supervisor_alive", return_value=False), \
                mock.patch.object(agent, "_posix_group_absent", return_value=False):
            self.assertEqual(agent.status(self.root, "job1")["state"], "STARTING")
        with mock.patch.object(agent, "supervisor_alive", return_value=False), \
                mock.patch.object(agent, "_posix_group_absent", return_value=True):
            status = agent.status(self.root, "job1")
        self.assertEqual((status["state"], status["launch"]), ("FINISHED", "NOT_CREATED"))
        # A supervisor that wakes up late finds the job settled and runs nothing.
        self.assertEqual(self.supervise(), 1)
        self.assertFalse((self.root / "jobs/job1/import-result.json").exists())

    # e ---------------------------------------------------------------
    def test_the_reserve_is_released_before_the_terminal_journal(self):
        self.accept()
        seen = []
        real_publish = agent.publish_terminal

        def observe(path, value):
            seen.append(agent.reserve_path(self.root, "job1").exists())
            return real_publish(path, value)

        with mock.patch.object(agent, "publish_terminal", side_effect=observe):
            self.supervise()
        self.assertEqual(seen, [False])
        self.assertNotIn("reserves", {Path(name).parts[0] for name in agent.status(self.root, "job1")["artifacts"]})
        # A reserve a lost supervisor left behind is swept with the incoming archives.
        agent.make_terminal_reserve(self.root, "job1")
        swept = agent.collect_incoming(self.root, {"operator_confirm": True})
        self.assertEqual(swept["removed_reserves"], 1)
        self.assertFalse(agent.reserve_path(self.root, "job1").exists())

    # f ---------------------------------------------------------------
    def test_recover_boot_settles_only_jobs_a_reboot_proves_ended(self):
        self.accept("job1")
        self.journal("job1", state="FINISHED", cleanup="CONFIRMED")
        self.clone("old1", state="UNKNOWN", process={"pid": 7, "host": "h", "boot": "before"})
        self.clone("same1", state="UNKNOWN", process={"pid": 8, "host": "h", "boot": "now"})
        self.clone("none1", state="UNKNOWN", process=None)
        self.clone("drift1", state="UNKNOWN", process={"pid": 9, "host": "h", "boot": "before"})
        with mock.patch.object(processes, "confirm_stopped", side_effect=lambda identity: identity["boot"] == "before"), \
                mock.patch.object(agent, "_posix_group_absent", side_effect=lambda pid: pid != 9):
            result = agent.recover_boot(self.root, {})
        # drift1: the boot value changed (macOS kern.boottime can shift) but its
        # process group is still there, so it is not settled unattended.
        self.assertEqual(result["settled"], ["old1"])
        self.assertEqual(sorted(result["still_unknown"]), ["drift1", "none1", "same1"])
        self.assertEqual(agent.status(self.root, "old1")["reason_code"], "HOST_REBOOTED")
        with self.assertRaises(agent.Refused):
            agent.recover_boot(self.root, {"operator_confirm": True})


class PoolBootRecoveryTests(unittest.TestCase):
    def test_only_quarantined_hosts_with_the_feature_are_asked(self):
        from tools.testqueue.common import write_json
        from tools.testqueue.pool import Pool
        with tempfile.TemporaryDirectory() as temporary:
            config = Path(temporary) / "config.json"
            hosts = [{"id": name, "ssh": name, "python": "p", "root": "/r", "agent": "/a"} for name in ("a", "b", "c", "d")]
            write_json(config, {"state_root": str(Path(temporary) / "pool"), "hosts": [{"id": "w", "local": True}, *hosts]})
            pool = Pool(config)
            probes = {"a": {"admission": {"quarantined": True}, "features": ["recover-boot"]},
                      "b": {"admission": {"quarantined": True}, "features": []},
                      "c": {"admission": {"quarantined": False}, "features": ["recover-boot"]}}
            calls = []

            def remote(host, action, payload, timeout=45):
                calls.append((host["id"], action))
                if host["id"] == "d":
                    raise RuntimeError("ssh: connect timed out")
                return probes[host["id"]] if action == "probe" else {"settled": ["x"], "still_unknown": []}

            with mock.patch.object(pool, "remote", side_effect=remote):
                report = pool.recover_quarantined_hosts()
        self.assertEqual(report["a"], {"settled": ["x"], "still_unknown": []})
        self.assertIn("redeploy", report["b"]["skipped"])
        self.assertEqual(report["c"], {"skipped": "not quarantined"})
        self.assertIn("unreachable", report["d"]["skipped"])
        self.assertEqual([call for call in calls if call[1] == "recover-boot"], [("a", "recover-boot")])


if __name__ == "__main__":
    unittest.main()
