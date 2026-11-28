"""Lifecycle, ownership and archive checks for the remote transport."""
from __future__ import annotations

import errno
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import time
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

    def test_idle_remote_probe_reports_external_occupancy_before_placement(self):
        with mock.patch.object(agent, "os", wraps=os) as remote_os, \
                mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "Lock"), \
                mock.patch.object(agent, "graphics_config", return_value=None), \
                mock.patch.object(agent, "external_engine_present", side_effect=[True, False, OSError("ps failed")]):
            remote_os.name = "posix"
            for code in ("EXTERNAL_SIMULATOR", None, "OCCUPANCY_UNKNOWN"):
                admission = agent.probe(self.root, {"engine_path": str(self.engine)})["admission"]
                self.assertEqual(admission["busy"], code is not None)
                self.assertEqual(admission.get("busy_code"), code)

    def test_external_after_preparation_proves_nonlaunch_on_original_request(self):
        request = self.request(self.sample_archive())
        request["options"]["timeout"] = 1
        accepted = self.accepted(request)
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "external_engine_present", return_value=True), \
                mock.patch.object(agent, "execute_stage") as execute:
            self.assertEqual(agent.supervise(self.root, "job1"), 0)
            execute.assert_not_called()
        result = agent.launch(self.root, request)
        self.assertEqual(result["payload_sha256"], accepted["payload_sha256"])
        self.assertEqual(result["state"], "FINISHED")
        self.assertEqual(result["evidence"], "INCOMPLETE")
        self.assertEqual(result["cleanup"], "CONFIRMED")
        self.assertEqual(result["stage"], "admission")
        self.assertEqual(result["reason_code"], "EXTERNAL_SIMULATOR")
        self.assertEqual((result["launch"], result["nonlaunch"]), ("NOT_CREATED", "CONFIRMED"))

    def test_remote_wait_stays_observable_and_resumes_original_attempt(self):
        request = self.request(self.sample_archive())
        accepted = self.accepted(request)
        def occupancy(engine):
            state = agent.status(self.root, "job1")
            if state.get("stage") != "admission":
                return True
            self.assertEqual(state["state"], "STARTING")
            self.assertEqual(state["reason_code"], "EXTERNAL_SIMULATOR")
            admission = agent.probe(self.root, {"engine_path": engine})["admission"]
            self.assertTrue(admission["busy"])
            self.assertEqual(admission["active_request_id"], "job1")
            self.assertEqual(agent.launch(self.root, request)["payload_sha256"], accepted["payload_sha256"])
            return False
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "external_engine_present", side_effect=occupancy):
            self.assertEqual(agent.supervise(self.root, "job1"), 0)
        result = agent.status(self.root, "job1")
        self.assertEqual(result["outcome"], "PASSED", result)
        self.assertEqual(result["payload_sha256"], accepted["payload_sha256"])
        self.assertGreaterEqual(result["admission_wait_finished_at"], result["admission_wait_started_at"])
        self.assertNotIn("reason_code", result)

    def test_remote_lost_waiting_supervisor_is_settled_as_never_launched(self):
        # Before TQ-07-A9 this stayed UNKNOWN and quarantined the host. A STARTING
        # record precedes every stage, and every stage records RUNNING before it
        # creates a process; the settlement happens under the host lock, which a
        # late supervisor re-checks before doing anything.
        request = self.request(self.sample_archive())
        self.accepted(request)
        path = agent.state_path(self.root, "job1")
        state = agent.read_json(path)
        state.update(stage="admission", reason_code="EXTERNAL_SIMULATOR", accepted_at=time.time() - 2 * agent.START_GRACE)
        agent.write_json(path, state)
        # Without a recorded supervisor PID (an older agent's record) the
        # supervisor's helpers cannot be checked: it stays uncertain.
        self.assertEqual(agent.status(self.root, "job1")["state"], "UNKNOWN")
        state.update(state="STARTING", supervisor_pid=4242)
        agent.write_json(path, state)
        with mock.patch.object(agent.subprocess, "Popen") as spawn, \
                mock.patch.object(agent, "supervisor_alive", return_value=False), \
                mock.patch.object(agent, "_posix_group_absent", return_value=True):
            result = agent.launch(self.root, request)
        spawn.assert_not_called()  # the same ID is never relaunched
        self.assertEqual((result["state"], result["cleanup"], result["launch"], result["nonlaunch"],
                          result["reason_code"], result["previous_reason_code"]),
                         ("FINISHED", "CONFIRMED", "NOT_CREATED", "CONFIRMED", "SUPERVISOR_LOST", "EXTERNAL_SIMULATOR"))
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "execute_stage") as execute:
            self.assertEqual(agent.supervise(self.root, "job1"), 1)  # a late supervisor runs nothing
        execute.assert_not_called()

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

    def test_import_has_its_own_budget_and_the_timeout_bounds_the_check(self):
        # TQ-07-A8: one deadline used to cover import and check, so a cold import
        # consumed the 90 s test budget and the test never started.
        archive = self.sample_archive()
        request = self.request(archive)
        request["expected_engine_sha256"] = agent.digest(self.engine)
        self.accepted(request)
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "external_engine_present", return_value=False), \
                mock.patch.object(agent, "execute_stage", wraps=agent.execute_stage) as execute:
            self.assertEqual(agent.supervise(self.root, "job1"), 0)
        deadlines = {call.args[3]: call.args[4] for call in execute.call_args_list}
        self.assertEqual(set(deadlines), {"import", "check"})
        # The check's 90 s starts after the import; the import had 900 s of its own.
        self.assertGreater(deadlines["import"] - deadlines["check"], agent.IMPORT_BUDGET_SECONDS - 90 - 60)
        self.assertEqual(agent.status(self.root, "job1")["outcome"], "PASSED")

    def test_import_timeout_is_typed_and_never_reaches_the_check(self):
        archive = self.sample_archive()
        request = self.request(archive)
        request["expected_engine_sha256"] = agent.digest(self.engine)
        self.accepted(request)
        stages = []

        def timed_out(root, directory, state, stage, deadline):
            stages.append(stage)
            return {"ok": False, "complete": False, "reason": "timeout"}

        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "external_engine_present", return_value=False), \
                mock.patch.object(agent, "execute_stage", side_effect=timed_out):
            agent.supervise(self.root, "job1")
        status = agent.status(self.root, "job1")
        self.assertEqual(stages, ["import"])
        self.assertEqual((status["outcome"], status["reason_code"], status["cleanup"]),
                         ("INFRA_FAILED", "IMPORT_TIMEOUT", "CONFIRMED"))

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
        # Since TQ-07-A8 the import stage has its own budget; shrink it so the
        # hanging runner is stopped at that deadline.
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "external_engine_present", return_value=False), \
                mock.patch.object(agent, "IMPORT_BUDGET_SECONDS", 1):
            agent.supervise(self.root, "job1")
        result = agent.status(self.root, "job1")
        self.assertEqual((result["state"], result["outcome"], result["cleanup"], result["evidence"]),
                         ("FINISHED", "INFRA_FAILED", "CONFIRMED", "INCOMPLETE"), result)
        self.assertEqual(result["import"]["reason"], "timeout")
        self.assertEqual(result["reason_code"], "IMPORT_TIMEOUT")

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

    def test_witnessed_nonlaunch_finishes_without_quarantine_but_unproved_start_does_not(self):
        from tools.testqueue import processes

        def refuse(witnessed):
            def start(process, **options):  # options: release=False since TQ-07-A9b
                process._nonlaunch_confirmed = witnessed
                raise processes.ProcessNotStartedError("injected runner log open failure")
            return start

        for identifier, witnessed, expected in [("job1", True, ("FINISHED", "INFRA_FAILED", "CONFIRMED")),
                                                ("job2", False, ("UNKNOWN", "INFRA_FAILED", "UNCONFIRMED"))]:
            with self.subTest(witnessed=witnessed):
                self.accepted(self.request(self.sample_archive(), identifier))
                with mock.patch.object(processes.OwnedProcess, "start", autospec=True, side_effect=refuse(witnessed)), \
                        mock.patch.object(agent, "authority_enrolled", return_value=False), \
                        mock.patch.object(agent, "external_engine_present", return_value=False):
                    agent.supervise(self.root, identifier)
                status = agent.read_json(self.root / "jobs" / identifier / "state.json")
                self.assertEqual((status["state"], status["outcome"], status["cleanup"]), expected, status)

    def test_unencodable_stage_result_is_published_without_a_pass(self):
        path = self.root / "terminal.json"
        state = {"state": "FINISHED", "outcome": "PASSED", "cleanup": "CONFIRMED", "evidence": "COMPLETE",
                 "checked": {"ok": True, "complete": True, "elapsed_seconds": float("nan")}}
        agent.publish_terminal(path, state)
        written = agent.read_json(path)
        self.assertEqual((written["state"], written["outcome"], written["cleanup"], written["evidence"]),
                         ("FINISHED", "INFRA_FAILED", "CONFIRMED", "INCOMPLETE"))
        self.assertEqual(written["checked"]["reason"], "not_serializable")

    def test_job_input_is_a_hard_link_not_a_second_copy(self):
        archive = self.sample_archive()
        self.accepted(self.request(archive))
        self.assertEqual(self._supervise(), 0)
        state = agent.read_json(self.root / "jobs/job1/state.json")
        self.assertEqual(state["outcome"], "PASSED")
        self.assertTrue(state.get("input_link"))
        self.assertEqual(state["storage_cleanup"]["state"], "SKIPPED")
        linked = (self.root / "jobs/job1/input.tar").stat()
        self.assertEqual((linked.st_ino, linked.st_dev), (archive.stat().st_ino, archive.stat().st_dev))

    def test_operator_gc_reclaims_only_a_collected_pass(self):
        self.accepted(self.request(self.sample_archive()))
        self.assertEqual(self._supervise(), 0)
        directory = self.root / "jobs/job1"
        state = agent.read_json(directory / "state.json")
        self.assertEqual(state["outcome"], "PASSED")
        bad = {"request_id": "job1", "payload_sha256": "0" * 64, "operator_confirm": True}
        with self.assertRaises(agent.Refused) as refused:
            agent.collect_garbage(self.root, bad)
        self.assertEqual(refused.exception.code, "CONFLICT")
        with self.assertRaises(agent.Refused):
            agent.collect_garbage(self.root, {**bad, "operator_confirm": False})
        result = agent.collect_garbage(self.root, {**bad, "payload_sha256": state["payload_sha256"]})
        self.assertIn("source", result["removed"])
        self.assertGreater(result["logical_bytes_removed"], 0)
        self.assertFalse((directory / "source").exists())
        kept = agent.read_json(directory / "state.json")
        self.assertEqual((kept["outcome"], kept["storage_gc"]["state"]), ("PASSED", "RECLAIMED"))
        self.assertTrue((directory / "check-result.json").is_file())
        # Unconfirmed cleanup or an UNKNOWN attempt is never a candidate, whatever its outcome.
        state.pop("storage_gc", None)
        for changes in ({"outcome": "TEST_FAILED", "cleanup": "UNCONFIRMED"},
                        {"state": "UNKNOWN", "outcome": "INFRA_FAILED", "cleanup": "CONFIRMED"},
                        {"outcome": "PASSED", "evidence": "INCOMPLETE"}):
            agent.write_json(directory / "state.json", {**state, **changes})
            with self.assertRaises(agent.Refused):
                agent.collect_garbage(self.root, {**bad, "payload_sha256": state["payload_sha256"]})

    def _failed_job(self, **changes):
        self.accepted(self.request(self.sample_archive()))
        self.assertEqual(self._supervise(), 0)
        directory = self.root / "jobs/job1"
        state = agent.read_json(directory / "state.json")
        # Same layout as a finished failed test: what matters is outcome and confirmed cleanup.
        state.update({"outcome": "TEST_FAILED", "evidence": "COMPLETE", "cleanup": "CONFIRMED", **changes})
        agent.write_json(directory / "state.json", state)
        # Pool remotes are POSIX; the logic is exercised on every OS.
        supported = mock.patch.object(agent, "_failure_reclaim_supported", return_value=True)
        supported.start()
        self.addCleanup(supported.stop)
        return directory, state, {"request_id": "job1", "payload_sha256": state["payload_sha256"],
                                  "operator_confirm": True}

    def test_operator_gc_of_a_failure_refuses_reconciled_attempts_and_windows_hosts(self):
        directory, state, request = self._failed_job(outcome="INFRA_FAILED", evidence="INCOMPLETE",
                                                     reconciliation={"proof": "reboot", "operator_confirmed": True})
        with self.assertRaises(agent.Refused) as refused:
            agent.collect_garbage(self.root, request)
        self.assertEqual(refused.exception.code, "CONFLICT")
        state.pop("reconciliation")
        agent.write_json(directory / "state.json", state)
        with mock.patch.object(agent, "_failure_reclaim_supported", return_value=False), \
                self.assertRaises(agent.Refused) as refused:
            agent.collect_garbage(self.root, request)
        self.assertEqual(refused.exception.code, "UNSUPPORTED")
        self.assertTrue((directory / "input.tar").is_file())
        self.assertTrue((directory / "source/app/tests/test_sample.gd").is_file())

    def test_operator_gc_of_a_failure_keeps_everything_the_run_wrote(self):
        directory, state, request = self._failed_job()
        source = directory / "source"
        (source / "assets/aircraft/model-bindings.json").write_text('{"changed": true}\n')  # modified input
        (source / "app/tests/capture.png").write_bytes(b"evidence")                     # written by the run
        imported = source / "app/.godot/imported"
        imported.mkdir(parents=True)
        (imported / "texture.ctex").write_bytes(b"x" * 64)
        cache = source / "tools/godot/__pycache__"
        cache.mkdir(exist_ok=True)
        (cache / "run_checked.cpython-312.pyc").write_bytes(b"pyc")
        result = agent.collect_garbage(self.root, request)
        self.assertFalse((directory / "input.tar").exists())
        self.assertFalse((source / "app/.godot").exists())
        self.assertFalse((source / "app/tests/test_sample.gd").exists())
        self.assertFalse((source / "tools/godot/run_checked.py").exists())
        self.assertFalse(cache.exists())
        self.assertEqual((source / "app/tests/capture.png").read_bytes(), b"evidence")
        self.assertEqual((source / "assets/aircraft/model-bindings.json").read_text(), '{"changed": true}\n')
        residue = result["retained_residue"]
        self.assertIn("app/tests/capture.png", residue["sample"])
        self.assertIn("assets/aircraft/model-bindings.json", residue["sample"])
        self.assertEqual(residue["files"], len(residue["sample"]))
        self.assertGreater(result["logical_bytes_removed"], 64)
        for name in ("check-result.json", "import-result.json", "source-inventory.json"):
            self.assertTrue((directory / name).is_file(), name)
        kept = agent.read_json(directory / "state.json")
        self.assertEqual((kept["outcome"], kept["storage_gc"]["state"]), ("TEST_FAILED", "RECLAIMED"))
        # Idempotent: a repeated sweep reports the earlier reclaim and touches nothing.
        self.assertEqual(agent.collect_garbage(self.root, request)["state"], "RECLAIMED")
        self.assertTrue((source / "app/tests/capture.png").is_file())

    def test_operator_gc_of_a_failure_trusts_only_its_own_inventory(self):
        directory, _, request = self._failed_job(outcome="INFRA_FAILED", evidence="INCOMPLETE",
                                                 source_inventory_sha256="0" * 64)
        result = agent.collect_garbage(self.root, request)
        # Archive copies go; with an unverified inventory every source file is residue.
        self.assertFalse((directory / "input.tar").exists())
        self.assertTrue((directory / "source/app/tests/test_sample.gd").is_file())
        self.assertGreaterEqual(result["retained_residue"]["files"], 4)

    def test_operator_gc_incoming_keeps_active_recent_and_pending_archives(self):
        incoming = self.root / "incoming"
        old, active, young = ("a" * 64 + ".tar", "b" * 64 + ".tar", "c" * 64 + ".tar")
        for name in (old, active, young, "d" * 64 + ".tar.job9.pending"):
            (incoming / name).write_bytes(b"x" * 10)
        past = time.time() - 7200
        for name in (old, active):
            os.utime(incoming / name, (past, past))
        running = {"state": "RUNNING", "request": {"archive": {"sha256": "b" * 64}}}
        with mock.patch.object(agent, "scan", return_value=[running]):
            result = agent.collect_incoming(self.root, {"operator_confirm": True})
        self.assertEqual(result, {"removed_files": 1, "removed_reserves": 0, "logical_bytes_removed": 10})
        self.assertEqual(sorted(path.name for path in incoming.iterdir()),
                         sorted([active, young, "d" * 64 + ".tar.job9.pending"]))
        with mock.patch.object(agent, "scan", return_value=[{"state": "UNKNOWN", "error": "unreadable journal"}]), \
                self.assertRaises(agent.Refused):
            agent.collect_incoming(self.root, {"operator_confirm": True})

    def test_operator_reconcile_requires_a_proved_absent_process_group(self):
        directory = self.root / "jobs/lost1"
        directory.mkdir(parents=True)
        unknown = {"state": "UNKNOWN", "request_id": "lost1", "cleanup": "UNCONFIRMED", "error": "supervisor disappeared",
                   "process": {"pid": 4242, "host": "h", "boot": "b"}}
        agent.write_json(directory / "state.json", unknown)
        request = {"request_id": "lost1", "operator_confirm": True}
        from tools.testqueue import processes
        with mock.patch.object(processes, "confirm_stopped", return_value=False), \
                mock.patch.object(agent, "_posix_group_absent", return_value=False), \
                self.assertRaises(agent.Refused):
            agent.reconcile_unknown(self.root, request)
        self.assertEqual(agent.read_json(directory / "state.json")["state"], "UNKNOWN")
        with self.assertRaises(agent.Refused):
            agent.reconcile_unknown(self.root, {**request, "operator_confirm": False})
        with mock.patch.object(processes, "confirm_stopped", return_value=False), \
                mock.patch.object(agent, "_posix_group_absent", return_value=True):
            result = agent.reconcile_unknown(self.root, request)
        self.assertEqual((result["state"], result["cleanup"], result["outcome"]), ("FINISHED", "CONFIRMED", "INFRA_FAILED"))
        self.assertIn("same boot", result["reconciliation"]["proof"])
        with self.assertRaises(agent.Refused):
            agent.reconcile_unknown(self.root, request)  # no longer UNKNOWN
        agent.write_json(directory / "state.json", {**unknown, "process": None})
        with self.assertRaises(agent.Refused):
            agent.reconcile_unknown(self.root, request)

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


class NativeAdaptationTests(unittest.TestCase):
    """Installed descriptors with no library for this host are dropped, as on a native checkout."""

    DESCRIPTOR = ('[configuration]\nentry_symbol = "init"\n\n[libraries]\n{}\n')

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.source = Path(tmp.name)

    def write(self, relative, libraries):
        path = self.source / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(self.DESCRIPTOR.format(libraries), encoding="utf-8")
        (path.parent / (path.name + ".uid")).write_text("uid://x")
        return path

    def adapt(self, system, machine):
        with mock.patch.object(agent.platform, "system", return_value=system), \
                mock.patch.object(agent.platform, "machine", return_value=machine):
            return agent.adapt_native_extensions(self.source)

    def test_mac_drops_windows_linux_descriptor_and_keeps_applicable_ones(self):
        ground = self.write("app/native/ground_vehicle/openrc_ground_vehicle.gdextension",
                            'windows = "res://a.dll"\nlinux = "res://a.so"')
        universal = self.write("app/native/other/mac.gdextension", 'macos = "res://m.framework"')
        intel = self.write("app/native/intel/x.gdextension", 'macos.x86_64 = "res://x.dylib"')
        arm = self.write("app/native/arm/y.gdextension", 'macos.debug.arm64 = "res://y.dylib"')
        tracked = self.write("app/addons/plugin/plugin.gdextension", 'windows = "res://p.dll"')
        result = self.adapt("Darwin", "arm64")
        self.assertEqual(result["platform"], "macos.arm64")
        self.assertEqual([item["path"] for item in result["removed_extensions"]],
                         ["app/native/ground_vehicle/openrc_ground_vehicle.gdextension",
                          "app/native/intel/x.gdextension"])
        self.assertFalse(ground.exists())
        self.assertFalse((ground.parent / (ground.name + ".uid")).exists())
        self.assertFalse(intel.exists())
        for kept in (universal, arm, tracked):
            self.assertTrue(kept.exists(), kept)

    def test_linux_keeps_its_descriptor_and_missing_native_dir_is_fine(self):
        self.write("app/native/ground_vehicle/openrc_ground_vehicle.gdextension",
                   'windows = "res://a.dll"\nlinux = "res://a.so"')
        self.assertEqual(self.adapt("Linux", "x86_64")["removed_extensions"], [])
        self.assertEqual(self.adapt("Linux", "aarch64")["platform"], "linux.arm64")
        empty = Path(tempfile.mkdtemp(dir=self.source))
        with mock.patch.object(agent.platform, "system", return_value="Darwin"):
            self.assertEqual(agent.adapt_native_extensions(empty)["removed_extensions"], [])


IMPORTING_RUNNER = FAKE_RUNNER.replace(
    "    folder = Path(out_dir) / \"run\"\n",
    "    folder = Path(out_dir) / \"run\"\n"
    "    if \"--import\" in command:\n"
    "        imported = Path(command[3]) / \".godot/imported\"\n"
    "        warm = (imported / \"asset.ctex\").is_file()\n"
    "        imported.mkdir(parents=True, exist_ok=True)\n"
    "        (imported / \"asset.ctex\").write_text(\"texture\")\n"
    "        (imported / \"asset.md5\").write_text(\"source_md5=1\")\n"
    "        Path(out_dir).mkdir(parents=True, exist_ok=True)\n"
    "        (Path(out_dir) / \"warmth.txt\").write_text(\"WARM\" if warm else \"COLD\")\n")


class ImportCacheTests(unittest.TestCase):
    """TQ-05-F3.4: a host reuses its last good import instead of a cold full reimport."""

    # Reuse the fixtures only; inheriting would rerun every lifecycle test.
    setUp = RemoteAgentTests.setUp
    archive = RemoteAgentTests.archive
    request = RemoteAgentTests.request
    accepted = RemoteAgentTests.accepted

    def importing_archive(self, name):
        return self.archive([
            ("app/project.godot", '[application]\nconfig/name="OpenRC Simulator"\n'),
            ("app/tests/test_sample.gd", "extends SceneTree\n"),
            ("tools/godot/run_checked.py", IMPORTING_RUNNER),
        ], name)

    def run_job(self, identifier):
        request = self.request(self.importing_archive(identifier + ".tar"), identifier)
        self.accepted(request)
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "external_engine_present", return_value=False):
            self.assertEqual(agent.supervise(self.root, identifier), 0)
        return agent.status(self.root, identifier)

    def warmth(self, identifier):
        return (self.root / "jobs" / identifier / "import/warmth.txt").read_text()

    def test_second_job_starts_from_the_first_jobs_imports(self):
        first = self.run_job("job1")
        self.assertEqual(first["outcome"], "PASSED", first)
        self.assertEqual(self.warmth("job1"), "COLD")
        self.assertFalse(first["import_cache"]["seeded"])
        self.assertTrue(first["import_cache"]["published"])
        engine = agent.digest(self.engine)
        cache = self.root / agent.IMPORT_CACHE / engine
        self.assertEqual(agent.read_json(cache / "cache.json")["job"], "job1")
        second = self.run_job("job2")
        self.assertEqual(second["outcome"], "PASSED", second)
        self.assertEqual(self.warmth("job2"), "WARM")
        self.assertEqual((second["import_cache"]["seeded"], second["import_cache"]["from_job"]), (True, "job1"))
        self.assertEqual(agent.read_json(cache / "cache.json")["job"], "job2")
        self.assertEqual(sorted(path.name for path in cache.iterdir()), ["cache.json", "imported"])
        # The seed is a copy: the job's files are not the cache's inodes.
        job_file = self.root / "jobs/job2/source/app/.godot/imported/asset.ctex"
        self.assertNotEqual(os.stat(job_file).st_ino, os.stat(cache / "imported/asset.ctex").st_ino)

    def test_failed_import_never_publishes(self):
        runner = IMPORTING_RUNNER.replace('"complete": True, "ok": True', '"complete": True, "ok": "--import" not in command')
        request = self.request(self.archive([
            ("app/project.godot", '[application]\nconfig/name="OpenRC Simulator"\n'),
            ("app/tests/test_sample.gd", "extends SceneTree\n"),
            ("tools/godot/run_checked.py", runner)], "bad.tar"), "bad1")
        self.accepted(request)
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "external_engine_present", return_value=False):
            agent.supervise(self.root, "bad1")
        self.assertFalse((self.root / agent.IMPORT_CACHE).exists())

    def test_seed_failure_starts_cold_and_does_not_fail_the_job(self):
        self.run_job("job1")
        with mock.patch.object(agent, "_clone_tree", side_effect=OSError("clone broke")):
            second = self.run_job("job2")
        self.assertEqual(second["outcome"], "PASSED", second)
        self.assertEqual(self.warmth("job2"), "COLD")
        self.assertIn("clone broke", second["import_cache"]["error"])

    def test_publish_replaces_cache_and_clears_interrupted_leftovers(self):
        source = self.root / "src"
        (source / "app/.godot/imported").mkdir(parents=True)
        (source / "app/.godot/imported/new.ctex").write_text("new")
        base = self.root / agent.IMPORT_CACHE / "e"
        for name in ("imported", "staging-crashed", "old-crashed"):
            (base / name).mkdir(parents=True)
        (base / "imported/old.ctex").write_text("old")
        result = agent.publish_import_cache(self.root, source, "e", "jobx")
        self.assertTrue(result["published"])
        self.assertEqual(sorted(path.name for path in base.iterdir()), ["cache.json", "imported"])
        self.assertEqual(sorted(path.name for path in (base / "imported").iterdir()), ["new.ctex"])


if __name__ == "__main__":
    unittest.main()
