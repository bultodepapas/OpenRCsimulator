"""TQ-07-A2: a remote request is either fenced and never launched, or launched and reported.

Agent-side fixtures drive the real ``fence`` and ``launch`` functions on a
private store; pool-side fixtures drive settlement through ``status`` and
``reconcile`` with a scripted transport. No real host is needed.
"""
from __future__ import annotations

import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from unittest import mock

from tools.testqueue import remote_agent as agent
from tools.testqueue.common import write_json
from tools.testqueue.pool import Pool, RemoteRefusal


class AgentFenceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-fence-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        (self.root / "incoming").mkdir()
        (self.root / "jobs").mkdir()
        self.engine = self.root / "engine-fixture"
        self.engine.write_bytes(b"#!/bin/sh\nexit 0\n")
        self.engine.chmod(0o755)
        archive = self.root / "incoming" / "source.tar"
        with tarfile.open(archive, "w") as bundle:
            data = b"extends SceneTree\n"
            info = tarfile.TarInfo("app/tests/test_sample.gd")
            info.size = len(data)
            bundle.addfile(info, io.BytesIO(data))
        self.archive = archive

    def request(self, identifier):
        return {"request_id": identifier, "preset": "checked",
                "archive": {"path": str(self.archive), "sha256": agent.digest(self.archive)},
                "engine_path": str(self.engine),
                "options": {"script": "res://tests/test_sample.gd", "require": ["0 failed"], "timeout": 90}}

    def launch(self, identifier):
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent.subprocess, "Popen") as spawn:
            return agent.launch(self.root, self.request(identifier)), spawn

    def test_fence_first_means_the_request_never_launches(self):
        result = agent.fence(self.root, {"request_id": "late1"})
        self.assertEqual(result["state"], "FENCED")
        self.assertEqual(result["identity"], agent.host_identity(self.root))
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent.subprocess, "Popen") as spawn, \
                self.assertRaises(agent.Refused) as refused:
            agent.launch(self.root, self.request("late1"))
        self.assertEqual(refused.exception.code, "FENCED")
        spawn.assert_not_called()
        self.assertFalse(agent.job_path(self.root, "late1").exists())
        self.assertEqual(agent.fence(self.root, {"request_id": "late1"})["state"], "FENCED")  # idempotent

    def test_launched_request_is_known_and_never_fenced(self):
        accepted, spawn = self.launch("ran1")
        spawn.assert_called_once()
        result = agent.fence(self.root, {"request_id": "ran1"})
        self.assertEqual(result["state"], "KNOWN")
        self.assertEqual(result["status"]["payload_sha256"], accepted["payload_sha256"])
        self.assertFalse(agent.fence_path(self.root, "ran1").exists())

    def test_tombstone_written_after_mkdir_makes_the_launch_refuse(self):
        # Interleaving: the launch creates its directory, then fence writes its
        # tombstone before the launch checks for one. The launch must back out.
        original = Path.mkdir

        def mkdir_then_fence(path, *args, **kwargs):
            original(path, *args, **kwargs)
            if path == agent.job_path(self.root, "race1"):
                tombstone = agent.fence_path(self.root, "race1")
                tombstone.parent.mkdir(exist_ok=True)
                tombstone.write_text("{}")

        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent.subprocess, "Popen") as spawn, \
                mock.patch.object(Path, "mkdir", mkdir_then_fence), \
                self.assertRaises(agent.Refused) as refused:
            agent.launch(self.root, self.request("race1"))
        self.assertEqual(refused.exception.code, "FENCED")
        spawn.assert_not_called()
        self.assertFalse(agent.job_path(self.root, "race1").exists())

    def test_directory_seen_while_a_launch_may_be_in_flight_settles_nothing(self):
        # Interleaving: a launch created its directory and holds the host lock.
        directory = agent.job_path(self.root, "race2")
        directory.mkdir()
        lock = agent.Lock(self.root / "pool.lock")
        try:
            with self.assertRaises(agent.Refused) as refused:
                agent.fence(self.root, {"request_id": "race2"})
        finally:
            lock.close()
        self.assertEqual(refused.exception.code, "BUSY")  # the coordinator settles nothing on BUSY
        self.assertTrue(directory.exists())
        # The tombstone stays: if that launch had not yet checked, it must back out.
        self.assertTrue(agent.fence_path(self.root, "race2").exists())
        self.assertEqual(agent.fence(self.root, {"request_id": "race2"})["state"], "FENCED")  # launch died
        self.assertFalse(directory.exists())

    def test_a_second_fencer_never_withdraws_the_first_ones_promise(self):
        # Review finding F1. Fencer B creates the tombstone and pauses; fencer A
        # finds it, sees no job directory and answers FENCED; a launch then
        # creates the directory and holds the host lock; B resumes, sees the
        # directory and a busy lock. If B withdrew the tombstone it created, the
        # launch's own check would pass and A's FENCED would be false.
        original_sync = agent._sync_directory
        held = {}

        def pause_after_tombstone(path):
            original_sync(path)
            if held:
                return
            held["paused"] = True  # fencer A's own sync passes straight through
            held["answer"] = agent.fence(self.root, {"request_id": "two1"})  # fencer A
            agent.job_path(self.root, "two1").mkdir()  # the launch got past mkdir...
            held["lock"] = agent.Lock(self.root / "pool.lock")  # ...and still holds the lock

        try:
            with mock.patch.object(agent, "_sync_directory", side_effect=pause_after_tombstone), \
                    self.assertRaises(agent.Refused) as busy:
                agent.fence(self.root, {"request_id": "two1"})  # fencer B
        finally:
            if "lock" in held:
                held["lock"].close()
        self.assertEqual(held["answer"]["state"], "FENCED")
        self.assertEqual(busy.exception.code, "BUSY")
        # The launch now checks for a tombstone after its mkdir: it must find one.
        self.assertTrue(agent.fence_path(self.root, "two1").exists())

    def test_unjournaled_directory_of_a_dead_launch_is_cleared(self):
        # TQ-07-A9a: a launch that died between mkdir and its journal.
        directory = agent.job_path(self.root, "dead1")
        directory.mkdir()
        (directory / "state.json.pending").write_text("{")
        self.assertEqual(agent.fence(self.root, {"request_id": "dead1"})["state"], "FENCED")
        self.assertFalse(directory.exists())
        directory = agent.job_path(self.root, "dead2")
        directory.mkdir()
        accepted, spawn = self.launch("dead2")  # the same ID launches instead of failing forever
        self.assertEqual(accepted["state"], "STARTING")
        spawn.assert_called_once()

    def test_unexpected_contents_are_kept_for_inspection(self):
        directory = agent.job_path(self.root, "odd1")
        directory.mkdir()
        (directory / "supervisor.log").write_text("evidence")
        with self.assertRaises(agent.Refused) as refused:
            agent.fence(self.root, {"request_id": "odd1"})
        self.assertEqual(refused.exception.code, "CONFLICT")
        self.assertTrue((directory / "supervisor.log").exists())
        # Not settled, and still never launchable: an operator inspects it.
        self.assertTrue(agent.fence_path(self.root, "odd1").exists())

    def test_store_identity_is_stable_and_changes_with_a_new_store(self):
        first = agent.host_identity(self.root)
        self.assertEqual(agent.host_identity(self.root), first)
        self.assertRegex(first["store_id"], r"^[0-9a-f]{32}$")
        other = self.root / "other-store"
        other.mkdir()
        self.assertNotEqual(agent.host_identity(other)["store_id"], first["store_id"])

    def test_cli_wires_fence_and_reports_identity_and_features(self):
        command = [sys.executable, str(Path(agent.__file__).resolve()), "fence", "--root", str(self.root)]
        result = subprocess.run(command, input=json.dumps({"request_id": "cli1"}),
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        response = json.loads(result.stdout)
        self.assertEqual((response["ok"], response["result"]["state"]), (True, "FENCED"))
        probe = subprocess.run([sys.executable, str(Path(agent.__file__).resolve()), "probe", "--root", str(self.root)],
                               input=json.dumps({"engine_path": None}), capture_output=True, text=True, timeout=30)
        value = json.loads(probe.stdout)["result"]
        self.assertIn("fence", value["features"])
        self.assertEqual(value["identity"]["store_id"], response["result"]["identity"]["store_id"])


class PoolFenceTests(unittest.TestCase):
    IDENTITY = {"machine_id": "m" * 32, "store_id": "s" * 32}

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-pool-fence-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.config = root / "config.json"
        self.host = {"id": "mac", "ssh": "mac", "python": "python3", "root": "/r", "agent": "/a", "engine": "/e"}
        write_json(self.config, {"state_root": str(root / "pool"), "hosts": [self.host]})
        self.pool = Pool(self.config)
        (self.pool.root / "jobs").mkdir(parents=True, exist_ok=True)

    def unconfirmed(self, identifier, *, age=3600, identity=IDENTITY, **extra):
        destination = {"host": "mac", "local": False, "root": "/r", "ssh": "mac"}
        if identity is not None:
            destination["identity"] = identity
        value = {"request_id": identifier, "host": "mac", "state": "SUBMISSION_UNCONFIRMED",
                 "created": time.time() - age, "submitted_at": time.time() - age,
                 "request": {"request_id": identifier}, "destination": destination,
                 "error": "ssh: connection reset", **extra}
        write_json(self.pool.root / "jobs" / (identifier + ".json"), value)

    def stored(self, identifier):
        return json.loads((self.pool.root / "jobs" / (identifier + ".json")).read_text())

    def reserved(self):
        return self.pool._reserve([{"id": "mac", "busy": False}])[0]["busy"]

    def transport(self, fence_reply=None, fence_error=None):
        calls = []

        def remote(host, action, payload, timeout=45):
            calls.append(action)
            if action == "status":
                raise RemoteRefusal("request not found", "NOT_FOUND")
            if action == "fence":
                if fence_error is not None:
                    raise fence_error
                return fence_reply
            raise AssertionError("unexpected remote action " + action)
        return remote, calls

    def fenced_reply(self, identifier, identity=IDENTITY):
        return {"request_id": identifier, "state": "FENCED", "identity": identity}

    def test_overdue_unconfirmed_submission_is_fenced_and_releases_the_host(self):
        self.unconfirmed("late1")
        self.assertTrue(self.reserved())
        remote, calls = self.transport(self.fenced_reply("late1"))
        with mock.patch.object(self.pool, "remote", side_effect=remote):
            result = self.pool.status("late1")
        self.assertEqual(calls, ["status", "fence"])
        self.assertEqual((result["state"], result["outcome"], result["reason_code"]),
                         ("FINISHED", "NOT_DISPATCHED", "REMOTE_FENCED"))
        self.assertEqual(self.stored("late1")["state"], "CANCELED_BEFORE_DISPATCH")
        self.assertFalse(self.reserved())
        with mock.patch.object(self.pool, "remote", side_effect=AssertionError("no further call")):
            self.assertEqual(self.pool.status("late1")["outcome"], "NOT_DISPATCHED")
            # Recovery of a settled receipt never replays it (review finding R1).
            self.assertEqual(self.pool.recover("late1")["outcome"], "NOT_DISPATCHED")
        self.assertEqual(self.stored("late1")["state"], "CANCELED_BEFORE_DISPATCH")

    def test_nothing_is_settled_without_every_proof(self):
        cases = {
            "recent": dict(age=30),
            "accepted earlier": dict(accepted={"state": "STARTING"}),
            "unknown store": dict(identity=None),
        }
        for label, extra in cases.items():
            with self.subTest(label=label):
                identifier = "case" + str(abs(hash(label)) % 10**8)
                self.unconfirmed(identifier, **extra)
                remote, calls = self.transport(self.fenced_reply(identifier))
                with mock.patch.object(self.pool, "remote", side_effect=remote):
                    result = self.pool.status(identifier)
                self.assertEqual(calls, ["status"])
                self.assertEqual(result["state"], "UNKNOWN")
                self.assertEqual(self.stored(identifier)["state"], "SUBMISSION_UNCONFIRMED")
        replies = {
            "other store": (self.fenced_reply("x", {"machine_id": "m" * 32, "store_id": "t" * 32}), None),
            "other machine": (self.fenced_reply("x", {"machine_id": "n" * 32, "store_id": "s" * 32}), None),
            "known": ({"request_id": "x", "state": "KNOWN", "identity": self.IDENTITY}, None),
            "old agent": (None, RuntimeError("remote agent returned no valid response")),
            "transport": (None, OSError("ssh: connect timed out")),
        }
        for label, (reply, error) in replies.items():
            with self.subTest(label=label):
                identifier = "reply" + str(abs(hash(label)) % 10**8)
                self.unconfirmed(identifier)
                if reply is not None:
                    reply = {**reply, "request_id": identifier}
                remote, calls = self.transport(reply, error)
                with mock.patch.object(self.pool, "remote", side_effect=remote):
                    result = self.pool.status(identifier)
                self.assertEqual(calls, ["status", "fence"])
                self.assertEqual(result["state"], "UNKNOWN")
                self.assertEqual(self.stored(identifier)["state"], "SUBMISSION_UNCONFIRMED")
        self.assertTrue(self.reserved())

    def test_watchdog_sweep_settles_orphans_and_skips_what_it_cannot_prove(self):
        self.unconfirmed("orph1")
        self.unconfirmed("young1", age=30)
        write_json(self.pool.root / "jobs" / "prep1.json",
                   {"request_id": "prep1", "host": "mac", "state": "PREPARING",
                    "destination": {"host": "mac", "local": False, "root": "/r", "ssh": "mac"}})

        def remote(host, action, payload, timeout=45):
            if action == "status":
                raise RemoteRefusal("request not found", "NOT_FOUND")
            if action == "fence":
                return self.fenced_reply(payload["request_id"])
            raise AssertionError(action)

        with mock.patch.object(self.pool, "remote", side_effect=remote):
            report = self.pool.settle_reserving_receipts(budget_seconds=30)
        settled = {item["job"]: item["reason_code"] for item in report["settled"]}
        self.assertEqual(settled, {"orph1": "REMOTE_FENCED", "prep1": "TRANSFER_DEFERRED"})
        self.assertEqual(self.stored("young1")["state"], "SUBMISSION_UNCONFIRMED")  # inside its grace period
        self.assertTrue(self.reserved())  # young1 still holds the host, truthfully

    def test_reconcile_settles_with_the_tombstone_and_needs_no_operator(self):
        self.unconfirmed("rec1", age=30)  # reconcile is an explicit request; no grace period
        remote, calls = self.transport(self.fenced_reply("rec1"))
        with mock.patch.object(self.pool, "remote", side_effect=remote):
            result = self.pool.reconcile("rec1")
        self.assertEqual(calls, ["status", "fence"])
        self.assertEqual(result["reason_code"], "REMOTE_FENCED")
        self.assertFalse(self.stored("rec1")["reconciliation"]["automatic"])
        self.assertFalse(self.reserved())

    def test_operator_release_still_leaves_a_tombstone_when_possible(self):
        self.unconfirmed("op1", accepted={"state": "STARTING"})  # accepted once: only an operator may release
        remote, calls = self.transport(self.fenced_reply("op1"))
        with mock.patch.object(self.pool, "remote", side_effect=remote):
            with self.assertRaisesRegex(ValueError, "operator-confirm"):
                self.pool.reconcile("op1")
            result = self.pool.reconcile("op1", operator_confirm=True)
        self.assertEqual(result["outcome"], "NOT_DISPATCHED")
        stored = self.stored("op1")
        self.assertEqual(stored["state"], "OPERATOR_RECONCILED_ABSENT")
        self.assertEqual(stored["reconciliation"]["fence"]["state"], "FENCED")


if __name__ == "__main__":
    unittest.main()
