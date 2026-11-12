"""Focused admission and evidence contracts, without a Godot process.

Fixtures use the system temporary directory; set TEMP/TMP before running when
the host's normal temporary volume is constrained.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock

from tools.testqueue import adapter, common, integration, presets, snapshots, testctl
from tools.testqueue.worker import Worker


class ContractFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-contracts-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.source = self.base / "checkout"
        self.source.mkdir()
        self._git("init", "-q")
        self._git("config", "user.name", "Queue Fixture")
        self._git("config", "user.email", "queue@example.invalid")
        self._write(self.source / "app/project.godot", "[application]\n")
        self._write(self.source / "tools/testqueue/adapter.py", "# fixture adapter\n")
        self._git("add", ".")
        self._git("commit", "-qm", "fixture")
        self.worker = Worker(self.base / "state", self.source, Path(sys.executable), fixture=True)
        self.addCleanup(self.worker.singleton.close)
        self.addCleanup(self.worker.store.db.close)

    def _git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.source), *args], stderr=subprocess.PIPE)

    def _write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def _call(self, operation, **kwargs):
        return self.worker.dispatch({"operation": operation, "auth": self.worker.auth, **kwargs})

    def _queue(self, payload=None):
        return self.worker.store.submit("request-id", payload or {"options": {"headless": True}}, "a" * 32)

    def _running_session(self):
        submitted = self._queue()
        job = submitted["job"]
        attempt = self.worker.store.allocate(job, {"headless": 1}, {"headless": 1})
        self.worker.store.update(job, attempt, "RUNNING", {"attempt": attempt, "session": {"port": 47870}})
        directory = self.worker.root / "attempts" / attempt
        self._write(directory / "ready.json", json.dumps({"port": 47870, "token": "bridge-secret"}))
        self.worker.contexts[attempt] = (job, "nested-secret")
        return submitted, attempt

    def test_duplicate_request_requires_original_submission_secret(self):
        first = self._queue({"preset": "debug-session", "owner": "agent-a"})
        visible = self.worker.store.get(first["job"])
        same = self.worker.store.submit(visible["request_id"], visible["payload"], "a" * 32)
        self.assertEqual(same, first)
        self.assertNotIn("capability", visible)
        self.assertNotIn("request_secret", visible)
        with self.assertRaises(ValueError):
            self.worker.store.submit(visible["request_id"], visible["payload"], "b" * 32)
        with self.assertRaises(ValueError):
            self.worker.store.submit(visible["request_id"], {"preset": "checked"}, "a" * 32)

    def test_queued_cancel_has_explicit_terminal_outcome_and_evidence(self):
        submitted = self._queue()
        self._call("cancel", handle=submitted["handle"])
        result = self._call("result", job=submitted["job"])
        self.assertEqual(result["state"], "FINISHED")
        self.assertEqual(result.get("outcome"), "CANCELED")
        self.assertIn(result.get("evidence"), {"COMPLETE", "INCOMPLETE"})
        self.assertEqual(result["attempts"], [])

    def test_owner_and_inherited_capabilities_cannot_be_forged(self):
        submitted, attempt = self._running_session()
        self.assertEqual(self._call("validate", context=attempt + ":nested-secret", scope="headless")["job"], submitted["job"])
        with self.assertRaises(ValueError):
            self._call("validate", context=attempt + ":wrong", scope="headless")
        with self.assertRaises(ValueError):
            self._call("validate", context=attempt + ":nested-secret", scope="rendered")
        with mock.patch.dict(os.environ, {"OPENRC_TESTQUEUE_CONTEXT": attempt + ":wrong"}):
            with mock.patch.object(common, "rpc", side_effect=lambda operation, **kw: self._call(operation, **kw)):
                with self.assertRaises(ValueError):
                    common.inherited("headless")
        with mock.patch("tools.testqueue.worker.socket.create_connection") as connect:
            with self.assertRaises(ValueError):
                self._call("bridge", handle=submitted["job"] + ":wrong", command="key", args={}, port=47870)
            connect.assert_not_called()

    def test_app_argument_named_headless_requires_rendered_claim(self):
        from tools.debug import debugctl
        from tools.godot import run_checked

        options = presets.validate("debug-session", {"argv": ["--", "--headless"]})
        self.assertFalse(options["headless"], "app arguments do not select Godot's headless display")
        with mock.patch.object(debugctl.admission, "enabled", return_value=True), mock.patch.object(debugctl.admission, "inherited", return_value=False) as grant, mock.patch.object(integration, "open_debug", return_value=0):
            debugctl.launch(["--", "--headless"])
        grant.assert_called_once_with("rendered")
        with mock.patch.object(common, "enabled", return_value=True), mock.patch.object(common, "inherited", side_effect=ValueError("stop before process creation")) as grant:
            with self.assertRaises(ValueError):
                run_checked.run_checked(["godot", "--path", "app", "--", "--headless"], self.base)
        grant.assert_called_once_with("rendered")

    def test_landscape_app_help_argument_cannot_bypass_admission(self):
        entry = Path(__file__).resolve().parent / "entry.py"
        argv = [str(entry), "landscape", "--", "--", "--help"]
        with mock.patch.object(sys, "argv", argv), mock.patch.object(common, "enabled", return_value=True), mock.patch.object(common, "inherited", return_value=False), mock.patch.object(integration, "run", return_value=0) as queued:
            with self.assertRaises(SystemExit) as result:
                runpy.run_path(str(entry), run_name="__main__")
        self.assertNotEqual(result.exception.code, 100, "a game argument must not bypass host admission")
        queued.assert_called_once()

    def test_bridge_passes_requested_timeout_to_owned_session(self):
        submitted, _ = self._running_session()
        with mock.patch.dict(os.environ, {"OPENRC_TESTQUEUE_HANDLE": submitted["handle"]}):
            with mock.patch.object(integration, "rpc", return_value={"ok": True}) as call:
                integration.request("sample", {"seconds": 40}, 90, 47870)
        forwarded = call.call_args.kwargs
        self.assertEqual(forwarded["bridge_timeout"], 90)
        connection = mock.MagicMock()
        connection.__enter__.return_value = connection
        reader = connection.makefile.return_value
        reader.__enter__.return_value = reader
        reader.readline.return_value = b'{"ok":true,"result":{}}\n'
        with mock.patch("tools.testqueue.worker.socket.create_connection", return_value=connection) as connect:
            self._call("bridge", **{key: value for key, value in forwarded.items() if key != "timeout"})
        connect.assert_called_once_with(("127.0.0.1", 47870), timeout=90)
        connection.settimeout.assert_called_once_with(90)

    def test_changed_manifest_identity_is_rejected_before_start(self):
        snapshot = self.base / "snapshot"
        receipt = snapshots.capture(self.source, snapshot, scope=("app", "tools"))
        submitted = self.worker.store.submit("snapshot-request", {
            "preset": "debug-session", "options": {"headless": False, "timeout": 60},
            "snapshot": str(snapshot), "source": str(self.source), "environment": {},
            "manifest": {"source_digest": receipt["source_digest"], "manifest_digest": receipt["manifest_digest"]},
        }, "c" * 32)
        attempt = self.worker.store.allocate(submitted["job"], {"rendered": 1}, {"rendered": 1})
        receipt["commit"] = "0" * 40
        receipt.pop("manifest_digest")
        encoded = json.dumps(receipt, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()
        receipt["manifest_digest"] = hashlib.sha256(encoded).hexdigest()
        (snapshot / "manifest.json").write_text(json.dumps(receipt), encoding="utf-8")
        self.assertTrue(snapshots.verify(snapshot)["ok"], "changed receipt remains internally consistent")
        with mock.patch("tools.testqueue.processes.OwnedProcess") as owned:
            self.worker.execute(submitted["job"], attempt)
        owned.assert_not_called()
        status = self.worker.store.get(submitted["job"])
        self.assertEqual(status.get("outcome"), "INFRA_FAILED")
        self.assertIn("snapshot", status.get("error", ""))

    def test_missing_or_invalid_capture_evidence_cannot_pass(self):
        for mode in ("missing", "invalid"):
            with self.subTest(mode=mode):
                directory = self.base / ("run-" + mode)
                directory.mkdir()
                self._write(directory / "request.json", json.dumps({
                    "preset": "capture", "options": {"headless": False, "argv": [], "timeout": 20}}))
                root = self.base / ("project-" + mode)
                root.mkdir()
                if mode == "invalid":
                    self._write(directory / "shell-receipt.json", json.dumps({"preset": "capture", "complete": True, "exit_code": 0}))
                    self._write(root / "app/captures/run-manifest.json", json.dumps({"format": "openrc-capture-set v1", "complete": False}))
                with mock.patch.object(adapter, "ROOT", root), mock.patch.object(adapter, "inherited", return_value=True), mock.patch.object(adapter, "prepare_history"), mock.patch.object(adapter.subprocess, "call", return_value=0):
                    adapter.main(directory)
                verdict = json.loads((directory / "verdict.json").read_text(encoding="utf-8"))
                self.assertFalse(verdict.get("ok") is True and verdict.get("complete") is True, verdict)

    def test_incomplete_runner_failure_is_infrastructure_failure(self):
        snapshot = self.base / "evidence-snapshot"
        receipt = snapshots.capture(self.source, snapshot, scope=("app", "tools"))
        submitted = self.worker.store.submit("evidence-request", {
            "preset": "debug-session", "options": {"headless": False, "timeout": 60},
            "snapshot": str(snapshot), "source": str(self.source), "environment": {},
            "manifest": {"source_digest": receipt["source_digest"], "manifest_digest": receipt["manifest_digest"]},
        }, "d" * 32)
        attempt = self.worker.store.allocate(submitted["job"], {"rendered": 1}, {"rendered": 1})

        class FailedRunner:
            def __init__(self, command, cwd, env, log):
                self.directory = log.parent
                self.identity = {"pid": 1}

            def start(self):
                (self.directory / "verdict.json").write_text(json.dumps({"ok": False, "complete": False}))

            def alive(self):
                return False

            def poll(self):
                return 1

            def close(self):
                pass

        with mock.patch("tools.testqueue.processes.OwnedProcess", FailedRunner):
            self.worker.execute(submitted["job"], attempt)
        status = self.worker.store.get(submitted["job"])
        self.assertEqual(status.get("cleanup"), "CONFIRMED")
        self.assertEqual(status.get("outcome"), "INFRA_FAILED", status)
        self.assertEqual(status.get("evidence"), "INCOMPLETE")

    def test_godtest_suite_with_missing_case_artifacts_cannot_pass(self):
        directory = self.base / "godtest-run"
        directory.mkdir()
        self._write(directory / "godtest/suite.json", json.dumps({
            "format": "openrc-godtest-suite-v1", "complete": True,
            "cases": [{"run_dir": str(directory / "godtest/missing-case"),
                       "data": "valid", "coverage": "complete"}],
        }))
        analysis = types.ModuleType("analysis")
        analysis.report = mock.Mock(side_effect=FileNotFoundError("case evidence missing"))
        with mock.patch.object(sys, "path", list(sys.path)), mock.patch.dict(sys.modules, {"analysis": analysis}):
            try:
                complete, ok, _ = adapter.validate_evidence("godtest", directory, self.source)
            except (OSError, ValueError):
                complete, ok = False, False
        self.assertFalse(complete and ok, "a saved summary cannot substitute for missing case artifacts")

    def test_fresh_submission_creates_snapshot_parent_without_prepared_imports(self):
        def rpc(operation, **kwargs):
            if operation == "hosts":
                return {"condition": "READY"}
            self.assertEqual(operation, "submit")
            manifest = json.loads((Path(kwargs["snapshot"]) / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["import_files"], [])
            return {"job": "fixture-job", "handle": "fixture-handle"}

        with mock.patch.object(integration, "state_root", return_value=self.worker.root), mock.patch.object(integration, "rpc", side_effect=rpc):
            result = integration.submit("debug-session", {"argv": ["--import"]}, self.source)
        self.assertEqual(result["job"], "fixture-job")
        self.assertEqual(len(list((self.worker.root / "submissions").glob("*.json"))), 1)

    def test_cli_persists_retry_identity_before_lost_reply(self):
        sent = {}

        def lost_reply(operation, **kwargs):
            if operation == "hosts":
                return {"condition": "READY"}
            self.assertEqual(operation, "submit")
            sent.update(kwargs)
            raise RuntimeError("reply lost after commit")

        with mock.patch.object(testctl, "state_root", return_value=self.worker.root), mock.patch.object(testctl, "rpc", side_effect=lost_reply):
            with self.assertRaises(RuntimeError):
                testctl.main(["submit", "--preset", "debug-session", "--source", str(self.source),
                              "--snapshot", str(self.base / "snapshot"), "--owner", "agent-a"])
        receipts = list((self.worker.root / "submissions").glob("*.json"))
        self.assertEqual(len(receipts), 1, "lost reply needs a recoverable submission receipt")
        receipt = json.loads(receipts[0].read_text(encoding="utf-8"))
        self.assertTrue(receipt.get("request_id"))
        self.assertGreaterEqual(len(receipt.get("request_secret", "")), 32)
        self.assertEqual(receipt["request_id"], sent["request_id"])
        self.assertEqual(receipt["request_secret"], sent["request_secret"])

    def test_cli_retry_does_not_replace_original_receipt_or_escape_root(self):
        def refuse(operation, **kwargs):
            raise RuntimeError("submit reply lost")

        common_args = ["submit", "--preset", "debug-session", "--source", str(self.source),
                       "--snapshot", str(self.base / "snapshot"), "--owner", "agent-a"]
        with mock.patch.object(testctl, "state_root", return_value=self.worker.root), mock.patch.object(testctl, "rpc", side_effect=refuse):
            with self.assertRaises(RuntimeError):
                testctl.main([*common_args, "--request-id", "stable", "--request-secret", "a" * 32])
            path = self.worker.root / "submissions/stable.json"
            original = path.read_bytes()
            with self.assertRaises((ValueError, RuntimeError)):
                testctl.main([*common_args, "--request-id", "stable", "--request-secret", "b" * 32])
            self.assertEqual(path.read_bytes(), original, "a rejected retry must preserve its recovery receipt")
            with self.assertRaises(ValueError):
                testctl.main([*common_args, "--request-id", "../escaped", "--request-secret", "c" * 32])
            self.assertFalse((self.worker.root / "escaped.json").exists())


if __name__ == "__main__":
    unittest.main()
