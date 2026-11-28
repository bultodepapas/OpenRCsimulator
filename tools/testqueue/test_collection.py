"""Fault and evidence tests for immutable pool collection, without fleet access."""
from __future__ import annotations

from contextlib import ExitStack
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

from tools.testqueue import collection
from tools.testqueue import pool as pool_module
from tools.testqueue.common import write_json
from tools.testqueue.pool import Pool


def digest_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def checked_fixture(output, script="res://tests/test_sample.gd", *, local=True,
                    outcome="PASSED", required=(), kind="check", complete=True):
    """Materialize the actual report/log contract, without launching an engine."""
    output = Path(output).resolve()
    required = list(required)
    engine = "/fixture/Godot"
    folder = ("checks" if local else "check") if kind == "check" else ("imports" if local else "import")
    directory = output / folder / "fixture-run"
    directory.mkdir(parents=True, exist_ok=True)
    log = directory / "engine.log"
    report_path = directory / "report.json"
    log.write_text("fixture output\n" + "\n".join(required) + "\n", encoding="utf-8")
    passed = outcome == "PASSED" and kind == "check"
    source = str(output / "source" / "app") if local else (output / "source" / "app").as_posix()
    if kind == "import":
        command = [engine, "--headless", "--path", source, "--audio-driver", "Dummy", "--import"]
        required_text = []
    elif local:
        command = [engine, "--path", source, "--audio-driver", "Dummy", "--headless", "--script", script]
        required_text = required
    else:
        command = [engine, "--headless", "--path", source, "--audio-driver", "Dummy", "--script", script]
        required_text = required
    report = {"format": "openrc-godot-check v1", "ok": passed, "complete": complete,
              "log": str(log) if local else log.as_posix(),
              "report": str(report_path) if local else report_path.as_posix(),
              "log_sha256": digest_file(log), "command": command, "required_text": required_text,
              "exit_code": 0 if passed else 1, "process_exit": 0 if passed else 1,
              "missing_required_text": [], "counts": {"error": 0 if passed else 1, "warning": 0},
              "elapsed_seconds": 1.25}
    report_path.write_text(json.dumps(report), encoding="utf-8")
    inventory = {}
    for path in (log, report_path):
        name = path.relative_to(output).as_posix()
        inventory[name] = digest_file(path) if local else {"size": path.stat().st_size, "sha256": digest_file(path)}
    status = {"state": "FINISHED", "outcome": outcome, "cleanup": "CONFIRMED",
              "evidence": "COMPLETE" if kind == "check" and complete else "INCOMPLETE",
              "output": str(output) if local else output.as_posix(), "artifacts": inventory}
    if local:
        status["engine"] = {"path": engine}
        status["runner_verdict"] = {"checked" if kind == "check" else "import_verdict": report}
    else:
        status["checked" if kind == "check" else "import"] = report
    return status


def write_pool_receipt(pool, identifier, *, host="local", script="res://tests/test_sample.gd", required=()):
    request = {"request_id": identifier, "engine_path": "/fixture/Godot"}
    receipt = {"request_id": identifier, "host": host, "state": "SUBMITTED", "request": request,
               "config_sha256": pool.config_digest,
               "source_digest": "fixture-source", "options": {"script": script, "require": list(required)}}
    write_json(pool.root / "jobs" / (identifier + ".json"), receipt)
    return receipt


def tree_bytes(directory):
    return {path.relative_to(directory).as_posix(): path.read_bytes()
            for path in Path(directory).rglob("*") if path.is_file()}


class CollectionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-collection-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.identifier = "fixtureid"
        self.config = self.root / "config.json"
        write_json(self.config, {"state_root": str(self.root / "pool"),
                                 "hosts": [{"id": "local", "local": True}]})
        self.pool = Pool(self.config)
        write_pool_receipt(self.pool, self.identifier, required=["COMPLETE"])
        self.status = checked_fixture(self.root / "attempt", required=["COMPLETE"])
        self.status.update(pool_host="local", job=self.identifier,
                           payload={"manifest": {"source_digest": "fixture-source"}})

    def collect(self, status=None, pool=None, out_dir=None):
        pool = pool or self.pool
        with patch.object(pool, "_status_locked", return_value=status or self.status):
            return pool.collect(self.identifier, out_dir=out_dir)

    def test_success_reuses_verified_generation_after_original_output_is_removed(self):
        first = self.collect()
        generation = Path(first["report"]).parent
        before = tree_bytes(generation)
        self.assertEqual(Path(first["log"]).read_text(), "fixture output\nCOMPLETE\n")
        shutil.rmtree(self.root / "attempt")
        with patch.object(collection, "_copy_local", side_effect=AssertionError("source was read again")):
            repeated = self.collect()
        self.assertEqual(repeated, first)
        self.assertEqual(tree_bytes(generation), before)

    def test_offline_verification_reads_only_saved_generation_and_receipt(self):
        result = self.collect()
        shutil.rmtree(self.root / "attempt")
        with patch("tools.testqueue.pool.rpc", side_effect=AssertionError("unexpected authority RPC")) as rpc, \
                patch.object(self.pool, "remote", side_effect=AssertionError("unexpected remote call")) as remote:
            self.assertEqual(self.pool.verify_collection(self.identifier, result), result)
        rpc.assert_not_called()
        remote.assert_not_called()

    def test_verification_refuses_changed_batch_result_and_configuration(self):
        result = self.collect()
        # False and 0 compare equal in Python, but are different JSON evidence.
        with self.assertRaisesRegex(ValueError, "batch collection differs"):
            self.pool.verify_collection(self.identifier, {**result, "exit_code": False})
        config = json.loads(self.config.read_text())
        config["changed"] = True
        write_json(self.config, config)
        with patch("tools.testqueue.pool.rpc") as rpc, \
                self.assertRaisesRegex(ValueError, "configuration changed"):
            self.pool.verify_collection(self.identifier, result)
        rpc.assert_not_called()

    def test_verification_refuses_a_rebound_request_without_contacting_authority(self):
        result = self.collect()
        receipt_path = self.pool.root / "jobs" / (self.identifier + ".json")
        receipt = json.loads(receipt_path.read_text())
        receipt["request"]["changed"] = True
        write_json(receipt_path, receipt)
        with patch("tools.testqueue.pool.rpc") as rpc, \
                self.assertRaisesRegex(ValueError, "bound receipt and status"):
            self.pool.verify_collection(self.identifier, result)
        rpc.assert_not_called()

    def test_new_failed_collection_preserves_prior_verified_generation(self):
        first = self.collect()
        generation = Path(first["report"]).parent
        before = tree_bytes(generation)
        newer = {**self.status, "observation_revision": 2}
        source_log = Path(self.status["runner_verdict"]["checked"]["log"])
        original = source_log.read_bytes()
        source_log.write_bytes(b"X" * len(original))
        with self.assertRaisesRegex(ValueError, "digest mismatch"):
            self.collect(newer)
        self.assertEqual(tree_bytes(generation), before)
        failed = list((self.pool.root / "results" / self.identifier).glob(".collection-*.pending"))
        self.assertEqual(len(failed), 1)
        self.assertEqual(json.loads((failed[0] / "pool-status.json").read_text()), newer)
        source_log.write_bytes(original)
        second = self.collect(newer)
        self.assertNotEqual(Path(second["report"]).parent, generation)
        self.assertEqual(tree_bytes(generation), before)

    def test_stale_log_cannot_substitute_for_missing_inventory_member(self):
        parent = self.pool.root / "results" / self.identifier
        stale = parent / "checks" / "fixture-run" / "engine.log"
        stale.parent.mkdir(parents=True)
        stale.write_bytes(Path(self.status["runner_verdict"]["checked"]["log"]).read_bytes())
        for omitted in ("engine.log", "report.json"):
            inventory = {name: value for name, value in self.status["artifacts"].items()
                         if not name.endswith(omitted)}
            with self.subTest(omitted=omitted), self.assertRaisesRegex(ValueError, "missing.*inventory"):
                self.collect({**self.status, "artifacts": inventory, "omitted": omitted})
        self.assertEqual(stale.read_text(), "fixture output\nCOMPLETE\n")
        self.assertFalse(list(parent.glob("collection-*/report.json")))

    def test_inventoried_report_must_equal_observed_verdict(self):
        report_path = Path(self.status["runner_verdict"]["checked"]["report"])
        tampered = dict(self.status["runner_verdict"]["checked"], reason="different observation")
        report_path.write_text(json.dumps(tampered), encoding="utf-8")
        name = report_path.relative_to(Path(self.status["output"])).as_posix()
        altered = {**self.status, "artifacts": {**self.status["artifacts"], name: digest_file(report_path)}}
        with self.assertRaisesRegex(ValueError, "report differs"):
            self.collect(altered)

    def test_report_json_comparison_distinguishes_boolean_integer_and_float(self):
        for index, (observed, file_value) in enumerate(((True, 1), (1, 1.0))):
            with self.subTest(observed=observed, file_value=file_value):
                status = checked_fixture(self.root / ("json-" + str(index)), required=["COMPLETE"])
                status.update(pool_host="local", job=self.identifier)
                report = status["runner_verdict"]["checked"]
                report["extra_evidence"] = observed
                report_path = Path(report["report"])
                report_path.write_text(json.dumps({**report, "extra_evidence": file_value}), encoding="utf-8")
                name = report_path.relative_to(Path(status["output"])).as_posix()
                status["artifacts"][name] = digest_file(report_path)
                with self.assertRaisesRegex(ValueError, "report differs"):
                    self.collect(status, out_dir=self.root / ("json-results-" + str(index)))

    def test_private_local_control_artifacts_are_never_copied(self):
        output = Path(self.status["output"])
        sentinel = b"PRIVATE-CONTROL-SECRET-DO-NOT-COLLECT"
        inventory = dict(self.status["artifacts"])
        for name in ("request.json", "ready.json", "shell-receipt.json"):
            (output / name).write_bytes(sentinel)
            inventory[name] = digest_file(output / name)
        status = {**self.status, "artifacts": inventory}
        result = self.collect(status)
        generation = Path(result["report"]).parent
        for name, content in tree_bytes(generation).items():
            self.assertNotIn(sentinel, content, name)
        self.assertFalse(any(path.name in {"request.json", "ready.json", "shell-receipt.json"}
                             for path in generation.rglob("*")))
        shutil.rmtree(output)
        self.assertEqual(self.collect(status), result)

    def test_incomplete_import_is_collected_as_diagnostic_not_success(self):
        status = checked_fixture(self.root / "failed-import", outcome="INFRA_FAILED", kind="import", complete=False)
        status.update(pool_host="local", job=self.identifier)
        result = self.collect(status)
        self.assertEqual(result["pool_outcome"], "INFRA_FAILED")
        self.assertIs(result["diagnostic_only"], True)
        self.assertEqual(result["diagnostic_stage"], "import")
        self.assertEqual(Path(result["diagnostic_log"]).read_text(), "fixture output\n\n")
        self.assertEqual(json.loads(Path(result["pool_status"]).read_text()), status)

    def test_legacy_failure_without_checked_report_is_diagnostic_only(self):
        status = {"state": "FINISHED", "outcome": "TEST_FAILED", "cleanup": "CONFIRMED",
                  "evidence": "COMPLETE", "runner_verdict": {}, "pool_host": "local", "job": self.identifier}
        result = self.collect(status)
        self.assertEqual(result["pool_outcome"], "TEST_FAILED")
        self.assertIs(result["diagnostic_only"], True)
        self.assertEqual(result["diagnostic_stage"], "execution")
        self.assertEqual(json.loads(Path(result["pool_status"]).read_text()), status)
        self.assertNotIn("ok", result)

    def test_admission_nonlaunch_keeps_legacy_and_current_diagnostics_verifiable(self):
        status = {"state": "FINISHED", "outcome": "INFRA_FAILED", "cleanup": "CONFIRMED", "evidence": "INCOMPLETE",
                  "stage": "admission", "reason_code": "EXTERNAL_SIMULATOR", "launch": "NOT_CREATED",
                  "nonlaunch": "CONFIRMED", "pool_host": "local", "job": self.identifier, "payload": self.status["payload"]}
        # An older coordinator computed the original binding and fallback label.
        with patch.object(collection, "_admission_nonlaunch", return_value=False):
            original = self.collect(status)
        self.assertEqual(original["diagnostic_stage"], "execution")
        current = self.collect(status)
        self.assertEqual(current["diagnostic_stage"], "admission")
        self.assertIs(current["diagnostic_only"], True)
        self.assertNotEqual(current["pool_status"], original["pool_status"])
        for result in (original, current):
            self.assertEqual(self.pool.verify_collection(self.identifier, result), result)
        uncertain = self.collect({**status, "nonlaunch": "UNCONFIRMED"})
        self.assertEqual(uncertain["diagnostic_stage"], "execution")

    def test_remote_partial_stage_returns_diagnostic_and_cannot_establish_pass(self):
        self.pool.hosts.append({"id": "remote", "ssh": "fixture-no-network", "python": "python3"})
        write_pool_receipt(self.pool, self.identifier, host="remote")
        for stage in ("checked", "import"):
            for reason in ("timeout", "runner_exit"):
                partial = {"ok": False, "complete": False, "reason": reason}
                if reason == "runner_exit":
                    partial["exit_code"] = 1
                status = {"state": "FINISHED", "outcome": "INFRA_FAILED", "cleanup": "CONFIRMED",
                          "evidence": "INCOMPLETE", "output": "/remote/job", "artifacts": {},
                          "pool_host": "remote", "job": self.identifier, stage: partial}
                with self.subTest(stage=stage, reason=reason), \
                        patch("tools.testqueue.pool.subprocess.run") as transport:
                    result = self.collect(status, out_dir=self.root / (stage + reason))
                    transport.assert_not_called()
                    self.assertEqual(result["pool_outcome"], "INFRA_FAILED")
                    self.assertIs(result["diagnostic_only"], True)
                    self.assertEqual(result["diagnostic_stage"], "check" if stage == "checked" else "import")
                    self.assertNotIn("diagnostic_report", result)
                    self.assertEqual(json.loads(Path(result["pool_status"]).read_text())[stage], partial)
                    impossible_pass = {**status, "outcome": "PASSED", "evidence": "COMPLETE"}
                    with self.assertRaises(ValueError):
                        self.collect(impossible_pass, out_dir=self.root / ("pass-" + stage + reason))

    def test_passing_report_cannot_hide_actual_log_errors_or_missing_markers(self):
        for index, contents in enumerate(("ERROR: unexpected failure\nCOMPLETE\n", "no completion marker\n")):
            with self.subTest(contents=contents):
                status = checked_fixture(self.root / ("bad-log-" + str(index)), required=["COMPLETE"])
                report = status["runner_verdict"]["checked"]
                log = Path(report["log"])
                log.write_text(contents, encoding="utf-8")
                report["log_sha256"] = digest_file(log)
                report_path = Path(report["report"])
                report_path.write_text(json.dumps(report), encoding="utf-8")
                for path in (log, report_path):
                    status["artifacts"][path.relative_to(Path(status["output"])).as_posix()] = digest_file(path)
                status.update(pool_host="local", job=self.identifier)
                with self.assertRaisesRegex(ValueError, "diagnostics|markers"):
                    self.collect(status)

    def test_rewritten_report_must_still_match_request_and_success_contract(self):
        receipt_path = self.pool.root / "jobs" / (self.identifier + ".json")
        receipt = json.loads(receipt_path.read_text())
        settings = {"label": "fixture", "warnings_as_errors": True, "max_log_bytes": 4096}
        receipt["options"]["settings"] = settings
        write_json(receipt_path, receipt)

        def replace_command(report, index, value):
            report["command"][index] = value

        cases = {
            "engine": lambda report: replace_command(report, 0, "/different/Godot"),
            "source": lambda report: replace_command(report, 2, "/different/source/app"),
            "script": lambda report: replace_command(report, -1, "res://tests/different.gd"),
            "markers": lambda report: report.update(required_text=["OTHER"]),
            "settings": lambda report: report.update(max_log_bytes=8192),
            "incomplete": lambda report: report.update(complete=False),
            "exit": lambda report: report.update(process_exit=1),
        }
        for name, mutate in cases.items():
            with self.subTest(field=name):
                status = checked_fixture(self.root / ("rewritten-" + name), required=["COMPLETE"])
                status.update(pool_host="local", job=self.identifier)
                report = status["runner_verdict"]["checked"]
                report.update(settings)
                mutate(report)
                report_path = Path(report["report"])
                report_path.write_text(json.dumps(report), encoding="utf-8")
                report_name = report_path.relative_to(Path(status["output"])).as_posix()
                status["artifacts"][report_name] = digest_file(report_path)
                out_dir = self.root / ("rejected-" + name)
                with self.assertRaises(ValueError):
                    self.collect(status, out_dir=out_dir)
                self.assertFalse(list((out_dir / self.identifier).glob("collection-*/report.json")))

    def test_path_aliases_and_escape_are_refused_without_touching_external_file(self):
        victim = self.root / "victim"
        victim.write_text("preserve", encoding="utf-8")
        digest = "a" * 64
        cases = [
            {"checks/../../victim": digest},
            {"checks/CON.txt": digest},
            {"checks/trailing.": digest},
            {"checks/Foo": digest, "checks/foo": digest},
            {"checks/Folder/a": digest, "checks/folder/b": digest},
            {"checks/caf\u00e9/a": digest, "checks/cafe\u0301/b": digest},
            {"checks/folder": digest, "checks/folder/file": digest},
        ]
        for index, inventory in enumerate(cases):
            with self.subTest(inventory=inventory), self.assertRaises(ValueError):
                self.collect({**self.status, "artifacts": inventory, "observation_revision": index},
                             out_dir=self.root / ("out" + str(index)))
            self.assertEqual(victim.read_text(), "preserve")

    def test_output_and_artifact_symlinks_are_refused(self):
        outside = self.root / "outside"
        outside.mkdir()
        alias = self.root / "alias"
        try:
            alias.symlink_to(outside, target_is_directory=True)
        except (OSError, NotImplementedError) as error:
            self.skipTest(f"symlink creation unavailable: {error}")
        with self.assertRaisesRegex(ValueError, "link|linked|reparse"):
            self.collect(out_dir=alias)
        log = Path(self.status["runner_verdict"]["checked"]["log"])
        target = outside / "engine.log"
        target.write_bytes(log.read_bytes())
        log.unlink()
        log.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "link|linked|reparse"):
            self.collect()
        self.assertEqual(target.read_text(), "fixture output\nCOMPLETE\n")

    def test_corrupt_published_generation_is_refused_without_overwrite(self):
        result = self.collect()
        generation = Path(result["report"]).parent
        Path(result["log"]).write_text("changed after verification", encoding="utf-8")
        damaged = tree_bytes(generation)
        with self.assertRaisesRegex(ValueError, "changed|differs"):
            self.collect()
        self.assertEqual(tree_bytes(generation), damaged)

    def test_normalized_log_must_match_bound_log_even_if_manifest_is_rewritten(self):
        result = self.collect()
        generation = Path(result["report"]).parent
        log = Path(result["log"])
        log.write_text("forged normalized log", encoding="utf-8")
        manifest_path = generation / "collection-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["files"]["engine.log"] = {"size": log.stat().st_size, "sha256": digest_file(log)}
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        before = tree_bytes(generation)
        with self.assertRaisesRegex(ValueError, "normalized log"):
            self.collect()
        self.assertEqual(tree_bytes(generation), before)

    def test_diagnostic_result_must_match_observation_even_if_manifest_is_rewritten(self):
        status = checked_fixture(self.root / "diagnostic", outcome="INFRA_FAILED", kind="import", complete=False)
        status.update(pool_host="local", job=self.identifier)
        result = self.collect(status)
        result_path = Path(result["pool_report"])
        generation = result_path.parent
        altered = {**result, "diagnostic_stage": "check"}
        result_path.write_text(json.dumps(altered), encoding="utf-8")
        manifest_path = generation / "collection-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["files"][result_path.name] = {"size": result_path.stat().st_size, "sha256": digest_file(result_path)}
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        before = tree_bytes(generation)
        with self.assertRaisesRegex(ValueError, "normalized result"):
            self.collect(status)
        self.assertEqual(tree_bytes(generation), before)

    def test_rename_failure_retains_staging_and_preserves_previous_generation(self):
        first = self.collect()
        previous = Path(first["report"]).parent
        before = tree_bytes(previous)
        newer = {**self.status, "observation_revision": 1}
        with patch.object(Path, "rename", autospec=True, side_effect=OSError("injected rename failure")), \
                self.assertRaisesRegex(ValueError, "injected rename failure"):
            self.collect(newer)
        self.assertEqual(tree_bytes(previous), before)
        parent = previous.parent
        self.assertEqual(len(list(parent.glob("collection-*"))), 1)
        retained, = parent.glob(".collection-*.pending")
        self.assertTrue((retained / "collection-manifest.json").is_file())
        self.assertEqual(json.loads((retained / "pool-status.json").read_text()), newer)

    @unittest.skipUnless(os.name == "posix", "directory fsync is qualified only on POSIX")
    def test_post_rename_sync_failure_is_not_success_and_generation_can_be_reused(self):
        first = self.collect()
        previous = Path(first["report"]).parent
        before = tree_bytes(previous)
        newer = {**self.status, "observation_revision": 2}
        original_sync = collection._sync_directory
        injected = []

        def fail_after_rename(path):
            path = Path(path)
            if path == previous.parent and len(list(path.glob("collection-*"))) == 2 and not injected:
                injected.append(path)
                raise OSError("injected post-rename fsync failure")
            return original_sync(path)

        with patch.object(collection, "_sync_directory", side_effect=fail_after_rename), \
                self.assertRaisesRegex(ValueError, "post-rename fsync failure"):
            self.collect(newer)
        self.assertEqual(len(injected), 1)
        self.assertEqual(tree_bytes(previous), before)
        generations = list(previous.parent.glob("collection-*"))
        self.assertEqual(len(generations), 2)
        visible = next(path for path in generations if path != previous)
        visible_before = tree_bytes(visible)
        recovered = self.collect(newer)
        self.assertEqual(Path(recovered["report"]).parent, visible)
        self.assertEqual(tree_bytes(visible), visible_before)
        self.assertEqual(tree_bytes(previous), before)

    def test_history_write_failure_is_advisory_and_verified_collection_is_reusable(self):
        original = pool_module.write_json

        def fail_history(path, value):
            if Path(path).name == "history.json":
                raise OSError("injected history storage failure")
            return original(path, value)

        with patch.object(pool_module, "write_json", side_effect=fail_history):
            result = self.collect()
        self.assertEqual(result["pool_outcome"], "PASSED")
        self.assertIs(result["diagnostic_only"], False)
        self.assertIn("injected history storage failure", result["history_warning"])
        self.assertEqual(Path(result["log"]).read_text(), "fixture output\nCOMPLETE\n")
        self.assertEqual(self.collect(), result)

    def test_failed_staging_is_bounded_and_retains_prior_evidence(self):
        invalid = {**self.status, "runner_verdict": {}}
        for _ in range(collection.MAX_FAILED_STAGES):
            with self.assertRaisesRegex(ValueError, "no checked report"):
                self.collect(invalid)
        parent = self.pool.root / "results" / self.identifier
        stages = list(parent.glob(".collection-*.pending"))
        self.assertEqual(len(stages), collection.MAX_FAILED_STAGES)
        before = {stage.name: tree_bytes(stage) for stage in stages}
        with self.assertRaisesRegex(ValueError, "staging budget"):
            self.collect(invalid)
        self.assertEqual({stage.name: tree_bytes(stage) for stage in stages}, before)
        self.assertEqual(len(list(parent.glob(".collection-*.pending"))), collection.MAX_FAILED_STAGES)

    def _concurrent_collections(self, other_pool, *, shared_output):
        entered = threading.Event()
        release = threading.Event()
        second_started = threading.Event()
        second_copy = threading.Event()
        calls_lock = threading.Lock()
        copy_count = 0
        original_copy = collection._copy_local
        outputs = []
        errors = []

        def slow_copy(*args, **kwargs):
            nonlocal copy_count
            with calls_lock:
                copy_count += 1
                first = copy_count == 1
            if first:
                entered.set()
                if not release.wait(5):
                    raise AssertionError("first copy did not receive release")
            elif threading.current_thread().name == "second-collector":
                second_copy.set()
            return original_copy(*args, **kwargs)

        def run(pool, *, second=False):
            try:
                if second:
                    second_started.set()
                outputs.append(pool.collect(self.identifier, out_dir=shared_output))
            except Exception as error:
                errors.append(error)

        first = threading.Thread(target=run, args=(self.pool,), name="first-collector")
        second = threading.Thread(target=run, args=(other_pool,), kwargs={"second": True},
                                  name="second-collector")
        with ExitStack() as stack:
            stack.enter_context(patch.object(self.pool, "_status_locked", return_value=self.status))
            if other_pool is not self.pool:
                stack.enter_context(patch.object(other_pool, "_status_locked", return_value=self.status))
            stack.enter_context(patch.object(collection, "_copy_local", side_effect=slow_copy))
            first.start()
            try:
                self.assertTrue(entered.wait(5), "first collection did not reach copy")
                second.start()
                self.assertTrue(second_started.wait(5), "second collection did not start")
                self.assertFalse(second_copy.wait(0.3), "collectors wrote the same destination concurrently")
            finally:
                release.set()
                first.join(10)
                if second.ident is not None:
                    second.join(10)
        self.assertFalse(first.is_alive())
        self.assertFalse(second.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual(len(outputs), 2)
        for result in outputs:
            self.assertEqual(Path(result["log"]).read_text(), "fixture output\nCOMPLETE\n")
        return outputs

    def test_same_pool_concurrent_collection_reuses_one_generation(self):
        outputs = self._concurrent_collections(self.pool, shared_output=self.root / "shared-results")
        self.assertEqual(outputs[0], outputs[1])

    def test_distinct_pools_share_destination_lock_and_preserve_both_generations(self):
        config = self.root / "other-config.json"
        write_json(config, {"state_root": str(self.root / "other-pool"),
                            "hosts": [{"id": "local", "local": True}]})
        other = Pool(config)
        write_pool_receipt(other, self.identifier, required=["COMPLETE"])
        outputs = self._concurrent_collections(other, shared_output=self.root / "shared-results")
        self.assertNotEqual(outputs[0]["report"], outputs[1]["report"])
        self.assertTrue(all(Path(result["report"]).is_file() for result in outputs))

    @unittest.skipUnless(os.name == "posix", "remote POSIX reader fixture")
    def test_remote_reader_is_bounded_and_rejects_changed_or_linked_source(self):
        remote_host = {"id": "remote", "ssh": "fixture-no-network", "python": sys.executable}
        self.pool.hosts.append(remote_host)
        receipt = write_pool_receipt(self.pool, self.identifier, host="remote", required=["COMPLETE"])
        status = checked_fixture(self.root / "remote-job", local=False, required=["COMPLETE"])
        status.update(pool_host="remote", job=self.identifier, request_id=self.identifier,
                      payload_sha256=pool_module.request_digest(receipt["request"]))
        real_run = subprocess.run
        calls = []

        def local_transport(command, **kwargs):
            calls.append(command)
            self.assertEqual(command[0], "ssh")
            self.assertNotIn("scp", command)
            arguments = shlex.split(command[-1])
            self.assertEqual(arguments[1], "-c")
            return real_run(arguments, stdout=kwargs["stdout"], stderr=kwargs["stderr"],
                            check=kwargs["check"], timeout=kwargs["timeout"])

        with patch("tools.testqueue.pool.subprocess.run", side_effect=local_transport):
            result = self.collect(status)
        self.assertGreaterEqual(len(calls), 2)
        self.assertEqual(Path(result["log"]).read_text(), "fixture output\nCOMPLETE\n")
        with patch.object(self.pool, "remote", side_effect=AssertionError("host offline")) as remote, \
                patch("tools.testqueue.pool.subprocess.run", side_effect=AssertionError("unexpected transport")) as transport:
            self.assertEqual(self.pool.verify_collection(self.identifier, result), result)
        remote.assert_not_called()
        transport.assert_not_called()
        published = Path(result["report"]).parent
        before = tree_bytes(published)
        source = Path(status["checked"]["log"])
        original = source.read_bytes()
        source.write_bytes(original + b"unexpected growth")
        newer = {**status, "observation_revision": 1}
        with patch("tools.testqueue.pool.subprocess.run", side_effect=local_transport), \
                self.assertRaises(ValueError):
            self.collect(newer)
        self.assertEqual(tree_bytes(published), before)
        source.unlink()
        target = self.root / "remote-symlink-target"
        target.write_bytes(original)
        source.symlink_to(target)
        with patch("tools.testqueue.pool.subprocess.run", side_effect=local_transport), \
                self.assertRaises(ValueError):
            self.collect({**status, "observation_revision": 2})
        self.assertEqual(target.read_bytes(), original)
        self.assertEqual(tree_bytes(published), before)


if __name__ == "__main__":
    unittest.main()
