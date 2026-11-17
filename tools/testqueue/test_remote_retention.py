"""Private-file fixtures for conservative remote input archive retention."""
from __future__ import annotations

import errno
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

from tools.testqueue import remote_agent as agent


@unittest.skipUnless(agent._retention_supported(), "descriptor-relative POSIX retention required")
class RemoteRetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / "incoming").mkdir()
        self.job = self.root / "jobs" / "job1"
        self.job.mkdir(parents=True)
        self.backup = self.root / "incoming" / "source.tar"
        self.target = self.job / "input.tar"
        self.content = b"exact verified archive bytes\n"
        self.backup.write_bytes(self.content)
        self.target.write_bytes(self.content)
        self.request = {"request_id": "job1", "preset": "checked",
                        "archive": {"path": str(self.backup), "sha256": hashlib.sha256(self.content).hexdigest()},
                        "engine_path": sys.executable,
                        "options": {"script": "res://tests/test_sample.gd", "timeout": 90}}
        self.state = {"protocol": 1, "request_id": "job1", "state": "FINISHED", "outcome": "PASSED",
                      "cleanup": "CONFIRMED", "evidence": "COMPLETE", "request": self.request,
                      "payload_sha256": hashlib.sha256(agent.encode(self.request)).hexdigest(),
                      "storage_cleanup": {"state": "PENDING", "phase": "PREPARING", "logical_bytes_removed": None}}
        agent.write_json(self.job / "state.json", self.state)
        for name in ("source/app/evidence.txt", "profile/user.log", "temp/data", "check/engine.log",
                     "source-inventory.json", "supervisor.log"):
            path = self.job / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("preserve " + name, encoding="utf-8")

    def saved(self):
        return agent.read_json(self.job / "state.json")

    def reclaim(self, **kwargs):
        return agent.reclaim_success_input(self.root, "job1", **kwargs)

    def reclaim_cli(self, payload):
        return subprocess.run([sys.executable, str(Path(agent.__file__).resolve()), "reclaim-input", "--root", str(self.root)],
                              input=json.dumps(payload), capture_output=True, text=True, timeout=10)

    def test_reclaim_cli_rejects_missing_malformed_and_wrong_identity(self):
        digest = self.state["payload_sha256"]
        cases = ({}, {"request_id": "job1"}, {"payload_sha256": digest},
                 {"request_id": "../job1", "payload_sha256": digest},
                 {"request_id": "job1", "payload_sha256": "bad"},
                 {"request_id": "job1", "payload_sha256": "A" * 64},
                 {"request_id": "job1", "payload_sha256": "0" * 64},
                 {"request_id": "job1", "payload_sha256": digest, "extra": True})
        for payload in cases:
            with self.subTest(payload=payload):
                result = self.reclaim_cli(payload)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertFalse(json.loads(result.stdout)["ok"])
                self.assertEqual(self.target.read_bytes(), self.content)
                self.assertFalse((self.job / "retained-input.tar").exists())
                self.assertEqual(self.saved(), self.state)

    def test_reclaim_cli_binds_durable_success_and_is_idempotent(self):
        payload = {"request_id": "job1", "payload_sha256": self.state["payload_sha256"]}
        first = self.reclaim_cli(payload)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(json.loads(first.stdout)["result"]["state"], "RECLAIMED")
        self.assertEqual((self.job / "retained-input.tar").read_bytes(), self.content)
        self.assertFalse(self.target.exists())
        repeated = self.reclaim_cli(payload)
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertEqual(json.loads(repeated.stdout)["result"]["state"], "RECLAIMED")
        wrong = self.reclaim_cli({**payload, "payload_sha256": "0" * 64})
        self.assertEqual(wrong.returncode, 1)
        self.assertEqual(json.loads(wrong.stdout)["code"], "CONFLICT")
        self.assertEqual((self.job / "retained-input.tar").read_bytes(), self.content)

    def test_reclaim_cli_refuses_changed_journal_and_busy_authority(self):
        payload = {"request_id": "job1", "payload_sha256": self.state["payload_sha256"]}
        altered = self.saved()
        altered["request"]["options"]["timeout"] = 91
        agent.write_json(self.job / "state.json", altered)
        result = self.reclaim_cli(payload)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(json.loads(result.stdout)["ok"])
        self.assertEqual(self.target.read_bytes(), self.content)
        self.assertFalse((self.job / "retained-input.tar").exists())
        agent.write_json(self.job / "state.json", self.state)
        lock = agent.Lock(self.root / "pool.lock")
        try:
            result = self.reclaim_cli(payload)
        finally:
            lock.close()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["code"], "BUSY")
        self.assertEqual(self.target.read_bytes(), self.content)
        self.assertFalse((self.job / "retained-input.tar").exists())

    def test_reclaim_cli_does_not_mutate_non_successful_attempt(self):
        state = {**self.state, "outcome": "TEST_FAILED"}
        agent.write_json(self.job / "state.json", state)
        result = self.reclaim_cli({"request_id": "job1", "payload_sha256": self.state["payload_sha256"]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["result"]["state"], "SKIPPED")
        self.assertEqual(self.target.read_bytes(), self.content)
        self.assertFalse((self.job / "retained-input.tar").exists())
        self.assertEqual(self.saved(), state)

    def test_success_pins_archive_and_preserves_results_and_identity(self):
        inventory = agent.artifact_inventory(self.job)
        outcome = self.reclaim()
        self.assertEqual(outcome["state"], "RECLAIMED")
        self.assertEqual(outcome["logical_bytes_removed"], len(self.content))
        self.assertIn("physical space is not guaranteed", outcome["size_semantics"])
        self.assertFalse(self.target.exists())
        pinned = self.job / outcome["retained_anchor"]
        self.assertEqual(pinned.read_bytes(), self.content)
        self.assertTrue(os.path.samefile(pinned, self.backup))
        self.assertNotIn("retained-input.tar", agent.artifact_inventory(self.job))
        self.assertEqual(agent.artifact_inventory(self.job), inventory)
        self.assertEqual((self.job / "source/app/evidence.txt").read_text(), "preserve source/app/evidence.txt")
        self.assertEqual((self.job / "profile/user.log").read_text(), "preserve profile/user.log")
        self.assertEqual((self.job / "temp/data").read_text(), "preserve temp/data")
        status = agent.status(self.root, "job1")
        self.assertEqual((status["state"], status["outcome"], status["cleanup"], status["evidence"]),
                         ("FINISHED", "PASSED", "CONFIRMED", "COMPLETE"))
        self.assertEqual(self.reclaim(), outcome)
        replacement = self.backup.with_suffix(".new")
        replacement.write_bytes(b"different future input")
        replacement.replace(self.backup)
        self.assertEqual(pinned.read_bytes(), self.content)
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
             mock.patch.object(agent.subprocess, "Popen") as launch:
            repeated = agent.launch(self.root, self.request)
        launch.assert_not_called()
        self.assertEqual(repeated["payload_sha256"], self.state["payload_sha256"])
        self.assertEqual(repeated["storage_cleanup"]["state"], "RECLAIMED")

    def test_only_confirmed_complete_success_is_eligible(self):
        cases = [("RUNNING", "PASSED", "COMPLETE", "CONFIRMED"),
                 ("UNKNOWN", "PASSED", "COMPLETE", "UNCONFIRMED"),
                 ("FINISHED", "INFRA_FAILED", "INCOMPLETE", "CONFIRMED"),
                 ("FINISHED", "CANCELED", "INCOMPLETE", "CONFIRMED"),
                 ("FINISHED", "TEST_FAILED", "COMPLETE", "CONFIRMED"),
                 ("FINISHED", "PASSED", "INCOMPLETE", "CONFIRMED"),
                 ("FINISHED", "PASSED", "COMPLETE", "UNCONFIRMED")]
        for state, outcome, evidence, cleanup in cases:
            with self.subTest(state=state, outcome=outcome, evidence=evidence, cleanup=cleanup):
                value = {**self.state, "state": state, "outcome": outcome, "evidence": evidence, "cleanup": cleanup}
                agent.write_json(self.job / "state.json", value)
                self.assertEqual(self.reclaim()["state"], "SKIPPED")
                self.assertEqual(self.target.read_bytes(), self.content)
                self.assertFalse((self.job / "retained-input.tar").exists())
                self.assertEqual(self.saved(), value)

    def test_missing_corrupt_or_oversized_inputs_are_retained(self):
        cases = ("missing_backup", "corrupt_backup", "corrupt_target", "oversized", "missing_target")
        for case in cases:
            with self.subTest(case=case):
                self.backup.write_bytes(self.content)
                self.target.write_bytes(self.content)
                anchor = self.job / "retained-input.tar"
                if anchor.exists():
                    anchor.unlink()
                agent.write_json(self.job / "state.json", self.state)
                if case == "missing_backup":
                    self.backup.unlink()
                elif case == "corrupt_backup":
                    self.backup.write_bytes(b"corrupt")
                elif case == "corrupt_target":
                    self.target.write_bytes(b"corrupt")
                elif case == "missing_target":
                    self.target.unlink()
                result = self.reclaim(max_bytes=1 if case == "oversized" else 1024)
                self.assertEqual(result["state"], "SKIPPED")
                self.assertEqual(self.saved()["storage_cleanup"]["state"], "SKIPPED")
                if case != "missing_target":
                    self.assertTrue(self.target.is_file())
                self.assertEqual(self.saved()["outcome"], "PASSED")

    def test_target_with_another_hard_link_is_retained(self):
        other = self.job / "other-link"
        os.link(self.target, other)
        self.assertEqual(self.reclaim()["state"], "SKIPPED")
        self.assertEqual(other.read_bytes(), self.content)
        self.assertEqual(self.target.read_bytes(), self.content)

    def test_bounded_hash_deadline_leaves_target(self):
        with mock.patch.object(agent.time, "monotonic", side_effect=[0, 1, 3]):
            result = self.reclaim(max_seconds=2)
        self.assertEqual(result["state"], "SKIPPED")
        self.assertIn("deadline", result["reason"])
        self.assertEqual(self.target.read_bytes(), self.content)

    def test_rejected_backup_is_not_pinned_and_corrected_backup_can_retry(self):
        for mode in ("corrupt", "oversized"):
            with self.subTest(mode=mode):
                self.backup.write_bytes(b"bad backup" if mode == "corrupt" else self.content)
                result = self.reclaim(max_bytes=1 if mode == "oversized" else 1024)
                self.assertEqual(result["state"], "SKIPPED")
                self.assertEqual(self.target.read_bytes(), self.content)
                self.assertFalse((self.job / "retained-input.tar").exists())
                replacement = self.backup.with_suffix(".replacement")
                replacement.write_bytes(self.content)
                replacement.replace(self.backup)
                self.assertEqual(self.reclaim()["state"], "RECLAIMED")
                self.target.write_bytes(self.content)
                (self.job / "retained-input.tar").unlink()
                agent.write_json(self.job / "state.json", self.state)

    def test_change_before_archive_fsync_removes_uncommitted_anchor(self):
        real_fsync = agent.os.fsync
        changed = []
        backup_identity = (self.backup.stat().st_dev, self.backup.stat().st_ino)
        def mutate(fd):
            info = os.fstat(fd)
            if (info.st_dev, info.st_ino) == backup_identity and not changed:
                changed.append(True)
                self.backup.write_bytes(b"changed after hashing")
            return real_fsync(fd)
        with mock.patch.object(agent.os, "fsync", side_effect=mutate):
            result = self.reclaim()
        self.assertEqual(result["state"], "SKIPPED")
        self.assertEqual(self.target.read_bytes(), self.content)
        self.assertFalse((self.job / "retained-input.tar").exists())
        replacement = self.backup.with_suffix(".replacement")
        replacement.write_bytes(self.content)
        replacement.replace(self.backup)
        self.assertEqual(self.reclaim()["state"], "RECLAIMED")

    def test_anchor_open_failure_removes_only_new_uncommitted_link(self):
        real_open = agent._retention_open_file
        failed = []
        def fail_anchor(name, directory):
            if name == "retained-input.tar" and not failed:
                failed.append(True)
                raise OSError(errno.EMFILE, "injected anchor open failure")
            return real_open(name, directory)
        with mock.patch.object(agent, "_retention_open_file", side_effect=fail_anchor):
            result = self.reclaim()
        self.assertEqual(result["state"], "SKIPPED")
        self.assertEqual(self.target.read_bytes(), self.content)
        self.assertFalse((self.job / "retained-input.tar").exists())
        replacement = self.backup.with_suffix(".replacement")
        replacement.write_bytes(self.content)
        replacement.replace(self.backup)
        self.assertEqual(self.reclaim()["state"], "RECLAIMED")

    def test_crash_after_pinning_and_incoming_replacement_can_retry(self):
        real_write = agent._retention_write_state
        def crash_before_intent(directory, value):
            if value.get("storage_cleanup", {}).get("phase") == "UNLINK":
                raise SystemExit("simulated crash before intent publication")
            real_write(directory, value)
        with mock.patch.object(agent, "_retention_write_state", side_effect=crash_before_intent), \
             self.assertRaises(SystemExit):
            self.reclaim()
        anchor = self.job / "retained-input.tar"
        self.assertEqual(anchor.read_bytes(), self.content)
        self.assertEqual(self.target.read_bytes(), self.content)
        self.assertEqual(self.saved()["storage_cleanup"]["phase"], "PREPARING")
        replacement = self.backup.with_suffix(".replacement")
        replacement.write_bytes(self.content)
        replacement.replace(self.backup)
        self.assertFalse(os.path.samefile(anchor, self.backup))
        self.assertEqual(self.reclaim()["state"], "RECLAIMED")
        self.assertEqual(anchor.read_bytes(), self.content)

    def test_symlinks_and_special_inputs_cannot_escape(self):
        external = self.root / "external"
        external.write_bytes(self.content)
        self.target.unlink()
        self.target.symlink_to(external)
        self.assertEqual(self.reclaim()["state"], "SKIPPED")
        self.assertEqual(external.read_bytes(), self.content)
        self.target.unlink()
        self.target.write_bytes(self.content)
        self.backup.unlink()
        self.backup.symlink_to(external)
        self.assertEqual(self.reclaim()["state"], "SKIPPED")
        self.assertEqual(external.read_bytes(), self.content)
        self.assertEqual(self.target.read_bytes(), self.content)
        self.backup.unlink()
        self.backup.write_bytes(self.content)
        self.target.unlink()
        os.mkfifo(self.target)
        self.assertEqual(self.reclaim()["state"], "SKIPPED")
        self.assertTrue(self.target.exists())
        self.assertEqual(external.read_bytes(), self.content)

    def test_backup_path_swap_after_intent_refuses_unlink(self):
        real_write = agent._retention_write_state
        swapped = []
        def swap(directory, value):
            real_write(directory, value)
            if not swapped and value.get("storage_cleanup", {}).get("phase") == "UNLINK":
                swapped.append(True)
                replacement = self.backup.with_suffix(".replacement")
                replacement.write_bytes(b"different backup")
                replacement.replace(self.backup)
        with mock.patch.object(agent, "_retention_write_state", side_effect=swap):
            result = self.reclaim()
        self.assertEqual(result["state"], "PENDING")
        self.assertEqual(self.target.read_bytes(), self.content)
        self.assertEqual((self.job / "retained-input.tar").read_bytes(), self.content)
        self.assertEqual(self.backup.read_bytes(), b"different backup")
        self.assertIn("changed", self.saved()["storage_cleanup"]["last_error"])

    def test_target_swap_after_intent_refuses_unlink(self):
        real_write = agent._retention_write_state
        swapped = []
        def swap(directory, value):
            real_write(directory, value)
            if not swapped and value.get("storage_cleanup", {}).get("phase") == "UNLINK":
                swapped.append(True)
                self.target.rename(self.job / "original-input.tar")
                self.target.write_bytes(b"new unrelated file")
        with mock.patch.object(agent, "_retention_write_state", side_effect=swap):
            result = self.reclaim()
        self.assertEqual(result["state"], "PENDING")
        self.assertEqual(self.target.read_bytes(), b"new unrelated file")
        self.assertEqual((self.job / "original-input.tar").read_bytes(), self.content)

    def test_job_directory_swap_after_intent_refuses_unlink(self):
        real_write = agent._retention_write_state
        moved = []
        original = self.job.parent / "original-job"
        def swap(directory, value):
            real_write(directory, value)
            if not moved and value.get("storage_cleanup", {}).get("phase") == "UNLINK":
                moved.append(True)
                self.job.rename(original)
                self.job.mkdir()
                (self.job / "input.tar").write_bytes(b"unrelated job")
        with mock.patch.object(agent, "_retention_write_state", side_effect=swap):
            result = self.reclaim()
        self.assertEqual(result["state"], "PENDING")
        self.assertEqual((original / "input.tar").read_bytes(), self.content)
        self.assertEqual(self.target.read_bytes(), b"unrelated job")

    def test_intent_write_failure_never_unlinks(self):
        with mock.patch.object(agent, "_retention_write_state", side_effect=OSError("journal unavailable")):
            result = self.reclaim()
        self.assertEqual(result["state"], "SKIPPED")
        self.assertEqual(self.target.read_bytes(), self.content)
        self.assertEqual(self.saved()["storage_cleanup"]["phase"], "PREPARING")

    def test_journal_temporaries_are_removed_before_rename_failure(self):
        fd = os.open(self.job, os.O_RDONLY | os.O_DIRECTORY)
        try:
            for operation in ("write", "rename"):
                with self.subTest(operation=operation), \
                     mock.patch.object(agent.os, operation, side_effect=OSError("injected journal failure")), \
                     self.assertRaises(OSError):
                    agent._retention_write_state(fd, {**self.state, "test_marker": operation})
                self.assertEqual(list(self.job.glob(".retention-state-*.pending")), [])
                self.assertNotIn("test_marker", self.saved())
        finally:
            os.close(fd)

    def test_journal_directory_fsync_failure_never_unlinks_published_state(self):
        fd = os.open(self.job, os.O_RDONLY | os.O_DIRECTORY)
        real_fsync = agent.os.fsync
        def fail_directory(value):
            if value == fd:
                raise OSError("injected directory fsync failure")
            return real_fsync(value)
        try:
            with mock.patch.object(agent.os, "fsync", side_effect=fail_directory), self.assertRaises(OSError):
                agent._retention_write_state(fd, {**self.state, "test_marker": "published"})
            self.assertEqual(list(self.job.glob(".retention-state-*.pending")), [])
            self.assertEqual(self.saved()["test_marker"], "published")
        finally:
            os.close(fd)

    def test_unlink_failure_preserves_pending_intent_and_can_retry(self):
        unlink = agent.os.unlink
        def fail(path, *args, **kwargs):
            if path == "input.tar":
                raise OSError(errno.EACCES, "injected unlink failure")
            return unlink(path, *args, **kwargs)
        with mock.patch.object(agent, "_retention_supported", return_value=True), \
             mock.patch.object(agent.os, "unlink", side_effect=fail):
            result = self.reclaim()
        self.assertEqual(result["state"], "PENDING")
        self.assertEqual(self.target.read_bytes(), self.content)
        self.assertEqual(self.saved()["storage_cleanup"]["phase"], "UNLINK")
        self.assertEqual(self.reclaim()["state"], "RECLAIMED")

    def test_result_write_failure_never_claims_retention_or_changes_verdict(self):
        real_write = agent._retention_write_state
        calls = []
        def fail_result(directory, value):
            calls.append(value.get("storage_cleanup", {}).get("state"))
            if value.get("storage_cleanup", {}).get("state") == "RECLAIMED":
                raise OSError("injected final journal failure")
            real_write(directory, value)
        with mock.patch.object(agent, "_retention_write_state", side_effect=fail_result):
            result = self.reclaim()
        self.assertEqual(result["state"], "PENDING")
        self.assertFalse(self.target.exists())
        self.assertEqual(self.saved()["storage_cleanup"]["phase"], "UNLINK")
        self.assertEqual(self.saved()["outcome"], "PASSED")
        recovered = self.reclaim()
        self.assertEqual(recovered["state"], "ABSENT_AFTER_INTENT")
        self.assertIsNone(recovered["logical_bytes_removed"])
        self.assertEqual((self.job / recovered["retained_anchor"]).read_bytes(), self.content)

    def test_final_result_rename_followed_by_failed_fsync_stays_unresolved(self):
        real_fsync = agent.os.fsync
        failed = []
        job_identity = (self.job.stat().st_dev, self.job.stat().st_ino)
        def fail_result_directory(fd):
            info = os.fstat(fd)
            if ((info.st_dev, info.st_ino) == job_identity and not failed
                    and self.saved()["storage_cleanup"].get("state") == "RECLAIMED"):
                failed.append(True)
                raise OSError("injected result-directory fsync failure")
            return real_fsync(fd)
        with mock.patch.object(agent.os, "fsync", side_effect=fail_result_directory):
            result = self.reclaim()
        self.assertTrue(failed)
        self.assertEqual(result["state"], "PENDING")
        self.assertFalse(self.target.exists())
        self.assertEqual(self.saved()["storage_cleanup"]["state"], "PENDING")
        self.assertEqual(self.saved()["outcome"], "PASSED")
        recovered = self.reclaim()
        self.assertEqual(recovered["state"], "ABSENT_AFTER_INTENT")
        self.assertIsNone(recovered["logical_bytes_removed"])

    def test_crash_after_unlink_remains_honestly_unresolved(self):
        real_write = agent._retention_write_state
        def crash(directory, value):
            if value.get("storage_cleanup", {}).get("state") == "RECLAIMED":
                raise SystemExit("simulated crash")
            real_write(directory, value)
        with mock.patch.object(agent, "_retention_write_state", side_effect=crash), \
             self.assertRaises(SystemExit):
            self.reclaim()
        self.assertFalse(self.target.exists())
        self.assertEqual(self.saved()["storage_cleanup"]["phase"], "UNLINK")
        recovered = self.reclaim()
        self.assertEqual(recovered["state"], "ABSENT_AFTER_INTENT")
        self.assertIsNone(recovered["logical_bytes_removed"])

    def test_unsupported_platform_and_busy_lock_retain(self):
        with mock.patch.object(agent, "_retention_supported", return_value=False):
            self.assertIn("unavailable", self.reclaim()["reason"])
        lock = agent.Lock(self.root / "pool.lock")
        try:
            with self.assertRaises(agent.Refused) as error:
                self.reclaim()
            self.assertEqual(error.exception.code, "BUSY")
        finally:
            lock.close()
        self.assertEqual(self.target.read_bytes(), self.content)

    def test_invalid_request_identity_cannot_delete_input(self):
        state = self.saved()
        state["payload_sha256"] = "0" * 64
        agent.write_json(self.job / "state.json", state)
        with self.assertRaises(agent.Refused):
            self.reclaim()
        self.assertEqual(self.target.read_bytes(), self.content)

    def test_supervisor_publishes_success_and_intent_before_unlink(self):
        # The stage is a fake: no simulator or child process runs in this fixture.
        archive = self.root / "incoming" / "candidate.tar"
        entries = {"app/project.godot": b'[application]\nconfig/name="OpenRC Simulator"\n',
                   "app/tests/test_sample.gd": b"extends SceneTree\n",
                   "tools/godot/run_checked.py": b"# fixture\n"}
        with tarfile.open(archive, "w") as bundle:
            for name, data in entries.items():
                item = tarfile.TarInfo(name)
                item.size = len(data)
                bundle.addfile(item, io.BytesIO(data))
        request = {**self.request, "archive": {"path": str(archive), "sha256": agent.digest(archive)}}
        state = {"protocol": 1, "request_id": "job1", "state": "STARTING", "request": request,
                 "payload_sha256": hashlib.sha256(agent.encode(request)).hexdigest(),
                 "accepted_at": 0, "cleanup": "UNCONFIRMED", "evidence": "INCOMPLETE", "output": str(self.job)}
        agent.write_json(self.job / "state.json", state)
        self.target.unlink()
        (self.job / "source").rename(self.job / "preserved-source")
        original_unlink, original_link = agent.os.unlink, agent.os.link
        observed = []
        def check_before_unlink(name, *args, **kwargs):
            if name == "input.tar":
                observed.append(self.saved())
            return original_unlink(name, *args, **kwargs)
        def no_job_input_link(source, target, *args, **kwargs):
            # Exercise the copy fallback (a filesystem without hard links).
            if "dst_dir_fd" not in kwargs:
                raise OSError("hard links unavailable in this fixture")
            return original_link(source, target, *args, **kwargs)
        with mock.patch.object(agent, "_retention_supported", return_value=True), \
             mock.patch.object(agent, "authority_enrolled", return_value=False), \
             mock.patch.object(agent, "external_engine_present", return_value=False), \
             mock.patch.object(agent, "execute_stage", return_value={"ok": True, "complete": True}), \
             mock.patch.object(agent, "verify_result"), \
             mock.patch.object(agent.os, "link", side_effect=no_job_input_link), \
             mock.patch.object(agent.os, "unlink", side_effect=check_before_unlink):
            self.assertEqual(agent.supervise(self.root, "job1"), 0)
        self.assertEqual(len(observed), 1)
        at_unlink = observed[0]
        self.assertEqual((at_unlink["state"], at_unlink["outcome"], at_unlink["cleanup"], at_unlink["evidence"]),
                         ("FINISHED", "PASSED", "CONFIRMED", "COMPLETE"))
        self.assertEqual((at_unlink["storage_cleanup"]["state"], at_unlink["storage_cleanup"]["phase"]),
                         ("PENDING", "UNLINK"))
        self.assertEqual(self.saved()["storage_cleanup"]["state"], "RECLAIMED")
        self.assertEqual((self.job / "retained-input.tar").read_bytes(), archive.read_bytes())


if __name__ == "__main__":
    unittest.main()
