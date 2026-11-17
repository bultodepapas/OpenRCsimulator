"""Lifecycle, ownership and archive checks for the remote transport."""
from __future__ import annotations

import errno
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

from tools.testqueue import remote_agent as agent


FAKE_RUNNER = '''\
import hashlib
import json
from pathlib import Path

def run_checked(command, out_dir, *, timeout, required=None, **kwargs):
    folder = Path(out_dir) / "run"
    folder.mkdir(parents=True)
    log = folder / "engine.log"
    log.write_text("\\n".join(required or []) + "\\n", encoding="utf-8")
    report_path = folder / "report.json"
    report = {"format": "openrc-godot-check v1", "complete": True, "ok": True,
              "command": command, "required_text": required or [], "exit_code": 0,
              "process_exit": 0, "counts": {"error": 0, "warning": 0},
              "missing_required_text": [], "log": str(log), "report": str(report_path),
              "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest()}
    report_path.write_text(json.dumps(report), encoding="utf-8")
    return report
'''


class RemoteAgentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        (self.root / "incoming").mkdir()
        (self.root / "jobs").mkdir()
        # The engine is only digested and checked for execute permission here.
        # Never hash the interpreter: a Microsoft Store Python alias is unreadable.
        self.engine = self.root / "engine-fixture"
        self.engine.write_bytes(b"#!/bin/sh\nexit 0\n")
        self.engine.chmod(0o755)

    def archive(self, entries, filename="source.tar"):
        path = self.root / "incoming" / filename
        with tarfile.open(path, "w") as tar:
            for name, value in entries:
                info = tarfile.TarInfo(name)
                if value is None:
                    info.type = tarfile.SYMTYPE
                    info.linkname = "../../outside"
                    tar.addfile(info)
                else:
                    data = value.encode()
                    info.size = len(data)
                    tar.addfile(info, io.BytesIO(data))
        return path

    def request(self, archive, identifier="job1"):
        return {"request_id": identifier, "preset": "checked",
                "archive": {"path": str(archive), "sha256": agent.digest(archive)},
                "engine_path": str(self.engine),
                "options": {"script": "res://tests/test_sample.gd", "require": ["0 failed"], "timeout": 90}}

    def sample_archive(self):
        return self.archive([
            ("app/project.godot", '[application]\nconfig/name="OpenRC Simulator"\n'),
            ("app/tests/test_sample.gd", "extends SceneTree\n"),
            ("assets/aircraft/model-bindings.json", '{"aircraft": []}\n'),
            ("tools/godot/run_checked.py", FAKE_RUNNER),
        ])

    def accepted(self, request):
        # The test calls the supervisor directly; production launches it detached.
        with mock.patch.object(agent, "authority_enrolled", return_value=False), mock.patch.object(agent.subprocess, "Popen"):
            return agent.launch(self.root, request)

    def test_unsafe_archives_are_rejected_before_extraction(self):
        cases = [
            [("app/../../escape", "bad")],
            [("app/escape", None)],
            [("app/Foo.txt", "a"), ("app/foo.txt", "b")],
            [("app/.godot/imported/cache", "bad")],
            [("app/con.txt", "bad")],
            [("tools\\escape", "bad")],
        ]
        for index, entries in enumerate(cases):
            archive = self.archive(entries, f"bad{index}.tar")
            with self.subTest(entries=entries), self.assertRaises(agent.Refused):
                agent.extract_archive(archive, self.root / f"extract{index}")
        self.assertFalse((self.root / "escape").exists())

    def test_verified_archive_records_every_file(self):
        archive = self.sample_archive()
        files = agent.extract_archive(archive, self.root / "source")
        self.assertEqual(len(files), 4)
        self.assertIn("assets/aircraft/model-bindings.json", files)
        path = self.root / "source/app/project.godot"
        self.assertEqual(files["app/project.godot"]["sha256"], agent.digest(path))
        change = agent.isolate_project(self.root / "source", "job1")
        self.assertEqual(change["original_sha256"], files["app/project.godot"]["sha256"])
        self.assertNotEqual(change["isolated_sha256"], change["original_sha256"])
        self.assertIn(b"OpenRC pool job1", path.read_bytes())

    def test_custom_user_directory_is_rejected(self):
        source = self.root / "source/app"
        source.mkdir(parents=True)
        project = source / "project.godot"
        project.write_text('[application]\nconfig/name="OpenRC Simulator"\nconfig/use_custom_user_dir=true\n')
        with self.assertRaises(agent.Refused):
            agent.isolate_project(source.parent, "job1")
        project.write_text('[application]\nconfig/name="OpenRC Simulator"\nconfig/use_custom_user_dir=false\n')
        self.assertEqual(agent.isolate_project(source.parent, "job1")["project_name"], "OpenRC pool job1")

    def test_materialized_inventory_detects_changes_and_extra_files(self):
        archive = self.sample_archive()
        source = self.root / "source"
        files = agent.extract_archive(archive, source)
        agent.verify_source(source, files)
        path = source / "app/tests/test_sample.gd"
        original = path.read_bytes()
        path.write_bytes(original + b"changed")
        with self.assertRaises(agent.Refused):
            agent.verify_source(source, files)
        path.write_bytes(original)
        (source / "app/unexpected.txt").write_text("extra")
        with self.assertRaises(agent.Refused):
            agent.verify_source(source, files)

    def test_idempotent_retry_and_crash_quarantine(self):
        archive = self.sample_archive()
        request = self.request(archive)
        first = self.accepted(request)
        archive.unlink()
        # A lost response is recoverable even when uploaded inputs disappeared.
        repeated = agent.launch(self.root, request)
        self.assertEqual(first["payload_sha256"], repeated["payload_sha256"])
        altered = {**request, "options": {**request["options"], "timeout": 91}}
        with self.assertRaises(agent.Refused) as conflict:
            agent.launch(self.root, altered)
        self.assertEqual(conflict.exception.code, "CONFLICT")
        state_file = agent.state_path(self.root, "job1")
        state = agent.read_json(state_file)
        state["state"] = "RUNNING"
        agent.write_json(state_file, state)
        lock = agent.Lock(self.root / "pool.lock")
        try:
            self.assertEqual(agent.status(self.root, "job1")["state"], "RUNNING")
        finally:
            lock.close()
        self.assertEqual(agent.status(self.root, "job1")["state"], "UNKNOWN")
        other_archive = self.sample_archive()
        other = self.request(other_archive, "job2")
        with mock.patch.object(agent, "authority_enrolled", return_value=False), self.assertRaises(agent.Refused) as blocked:
            agent.launch(self.root, other)
        self.assertEqual(blocked.exception.code, "QUARANTINED")

    def test_supervisor_runs_import_and_check_in_owned_process(self):
        archive = self.sample_archive()
        request = self.request(archive)
        request["expected_engine_sha256"] = agent.digest(self.engine)
        self.accepted(request)
        with mock.patch.object(agent, "authority_enrolled", return_value=False), mock.patch.object(agent, "external_engine_present", return_value=False):
            self.assertEqual(agent.supervise(self.root, "job1"), 0)
        status = agent.status(self.root, "job1")
        self.assertEqual((status["state"], status["outcome"], status["cleanup"], status["evidence"]),
                         ("FINISHED", "PASSED", "CONFIRMED", "COMPLETE"), status)
        self.assertIn("check/run/engine.log", status["artifacts"])
        self.assertEqual(status["artifacts"]["check/run/engine.log"]["sha256"],
                         agent.digest(self.root / "jobs/job1/check/run/engine.log"))
        self.assertEqual(status["checked"]["required_text"], ["0 failed"])

    def test_changed_archive_fails_before_process_start(self):
        archive = self.sample_archive()
        request = self.request(archive)
        self.accepted(request)
        with archive.open("ab") as stream:
            stream.write(b"changed")
        with mock.patch.object(agent, "authority_enrolled", return_value=False), mock.patch.object(agent, "execute_stage") as execute:
            agent.supervise(self.root, "job1")
        execute.assert_not_called()
        result = agent.status(self.root, "job1")
        self.assertEqual(result["outcome"], "INFRA_FAILED")
        self.assertIn("SHA-256 differs", result["error"])

    def test_probe_selected_engine_digest_is_required_when_supplied(self):
        archive = self.sample_archive()
        request = self.request(archive)
        request["expected_engine_sha256"] = "0" * 64
        self.accepted(request)
        with mock.patch.object(agent, "authority_enrolled", return_value=False), mock.patch.object(agent, "external_engine_present", return_value=False), mock.patch.object(agent, "execute_stage") as execute:
            agent.supervise(self.root, "job1")
        execute.assert_not_called()
        result = agent.status(self.root, "job1")
        self.assertEqual(result["outcome"], "INFRA_FAILED")
        self.assertIn("engine SHA-256 differs", result["error"])

    def test_timeout_stops_owned_runner_without_passing(self):
        archive = self.archive([
            ("app/project.godot", '[application]\nconfig/name="OpenRC Simulator"\n'),
            ("app/tests/test_sample.gd", "extends SceneTree\n"),
            ("tools/godot/run_checked.py", "import time\ndef run_checked(*args, **kwargs):\n    time.sleep(30)\n"),
        ])
        request = self.request(archive)
        request["options"]["timeout"] = 1
        self.accepted(request)
        with mock.patch.object(agent, "authority_enrolled", return_value=False), mock.patch.object(agent, "external_engine_present", return_value=False):
            agent.supervise(self.root, "job1")
        result = agent.status(self.root, "job1")
        self.assertEqual((result["state"], result["outcome"], result["cleanup"], result["evidence"]),
                         ("FINISHED", "INFRA_FAILED", "CONFIRMED", "INCOMPLETE"), result)
        self.assertEqual(result["import"]["reason"], "timeout")

    def test_missing_real_marker_cannot_pass(self):
        archive = self.sample_archive()
        request = self.request(archive)
        self.accepted(request)
        with mock.patch.object(agent, "authority_enrolled", return_value=False), mock.patch.object(agent, "external_engine_present", return_value=False):
            agent.supervise(self.root, "job1")
        directory = self.root / "jobs/job1"
        result = agent.read_json(directory / "check-result.json")
        path = Path(result["log"])
        path.write_text("wrong output", encoding="utf-8")
        result["log_sha256"] = agent.digest(path)
        Path(result["report"]).write_text(json.dumps(result), encoding="utf-8")
        with self.assertRaises(agent.Refused):
            agent.verify_result(directory, "check", result, request)

    # TQ-04 continuity: the remote supervisor journal is observation, not ownership.

    def _supervise(self):
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "external_engine_present", return_value=False):
            return agent.supervise(self.root, "job1")

    def test_post_start_journal_failure_keeps_owned_child_running(self):
        self.accepted(self.request(self.sample_archive()))
        real_write = agent.write_json
        failures = []

        def fail_owned_observation(path, value):
            if value.get("state") == "RUNNING" and value.get("process") and len(failures) < 2:
                failures.append(value.get("stage"))
                raise OSError(errno.ENOSPC, "injected post-start journal failure")
            return real_write(path, value)

        with mock.patch.object(agent, "write_json", side_effect=fail_owned_observation):
            self.assertEqual(self._supervise(), 0)
        # Both failures hit owned observations (a slow import may retry once).
        self.assertEqual(len(failures), 2, failures)
        self.assertEqual(failures[0], "import")
        status = agent.status(self.root, "job1")
        self.assertEqual((status["state"], status["outcome"], status["cleanup"], status["evidence"]),
                         ("FINISHED", "PASSED", "CONFIRMED", "COMPLETE"), status)
        self.assertTrue((self.root / "jobs/job1/import-result.json").is_file())

    def test_terminal_write_is_retried_before_the_host_lock_is_released(self):
        self.accepted(self.request(self.sample_archive()))
        real_write = agent.write_json
        failures = []

        def fail_terminal_twice(path, value):
            if value.get("state") == "FINISHED" and len(failures) < 2:
                failures.append(1)
                raise OSError(errno.EIO, "injected terminal journal failure")
            return real_write(path, value)

        with mock.patch.object(agent, "write_json", side_effect=fail_terminal_twice), \
                mock.patch.object(agent, "TERMINAL_WRITE_DELAY", 0):
            self.assertEqual(self._supervise(), 0)
        self.assertEqual(len(failures), 2)
        status = agent.status(self.root, "job1")
        self.assertEqual((status["state"], status["outcome"]), ("FINISHED", "PASSED"), status)

    def test_exhausted_terminal_write_fails_closed_and_quarantines(self):
        self.accepted(self.request(self.sample_archive()))
        real_write = agent.write_json
        attempts = []

        def always_fail_terminal(path, value):
            if value.get("state") in {"FINISHED", "UNKNOWN"}:
                attempts.append(value["state"])
                raise OSError(errno.EIO, "injected persistent terminal failure")
            return real_write(path, value)

        with mock.patch.object(agent, "write_json", side_effect=always_fail_terminal), \
                mock.patch.object(agent, "TERMINAL_WRITE_DELAY", 0), self.assertRaises(OSError):
            self._supervise()
        self.assertEqual(attempts, ["FINISHED"] * agent.TERMINAL_WRITE_ATTEMPTS)
        # No durable terminal record: the stale RUNNING record is observed as
        # uncertainty and the host refuses new work instead of freeing capacity.
        self.assertEqual(agent.read_json(self.root / "jobs/job1/state.json")["state"], "RUNNING")
        self.assertEqual(agent.status(self.root, "job1")["state"], "UNKNOWN")
        second = self.archive([("app/project.godot", "[application]\n")], "second.tar")
        with self.assertRaises(agent.Refused) as refused:
            self.accepted(self.request(second, "job2"))
        self.assertEqual(refused.exception.code, "QUARANTINED")

    def test_unreadable_result_after_confirmed_teardown_is_not_unknown(self):
        self.accepted(self.request(self.sample_archive()))
        real_read = agent.read_json

        def unreadable_import(path):
            if str(path).endswith("import-result.json"):
                raise ValueError("injected unreadable stage result")
            return real_read(path)

        with mock.patch.object(agent, "read_json", side_effect=unreadable_import):
            self.assertEqual(self._supervise(), 0)
        status = agent.status(self.root, "job1")
        self.assertEqual((status["state"], status["outcome"], status["cleanup"], status["evidence"]),
                         ("FINISHED", "INFRA_FAILED", "CONFIRMED", "INCOMPLETE"), status)
        self.assertEqual(status["import"]["reason"], "result_unreadable")


if __name__ == "__main__":
    unittest.main()
