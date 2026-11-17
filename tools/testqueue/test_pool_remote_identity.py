"""Private transport fixtures for pool recovery and input identity."""

import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from tools.testqueue import remote_agent
from tools.testqueue.common import write_json
from tools.testqueue.pool import Pool, request_digest


class RemoteIdentityTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-remote-identity-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.host = {"id": "remote", "ssh": "unused-fixture-host", "python": "/usr/bin/python3",
                     "agent": "/private/remote_agent.py", "root": "/private/worker"}
        self.config = self.root / "config.json"
        write_json(self.config, {"state_root": str(self.root / "pool"), "hosts": [self.host]})
        self.pool = Pool(self.config)
        self.identifier = "originalrequest"
        self.request = {
            "request_id": self.identifier,
            "preset": "checked",
            "archive": {"path": "/private/worker/incoming/archive.tar", "sha256": "a" * 64},
            "engine_path": "/private/engine",
            "expected_engine_sha256": "b" * 64,
            "options": {"script": "res://tests/test_sample.gd", "headless": True,
                        "timeout": 90, "require": ["avión listo 🛩️"]},
        }
        self.receipt_path = self.pool.root / "jobs" / (self.identifier + ".json")
        self.receipt = {"request_id": self.identifier, "host": self.host["id"],
                        "state": "SUBMISSION_UNCONFIRMED", "request": self.request,
                        "config_sha256": self.pool.config_digest,
                        "source_digest": "original-source", "options": self.request["options"]}
        self.reset_receipt()

    def reset_receipt(self):
        write_json(self.receipt_path, self.receipt)

    def read_receipt(self):
        return json.loads(self.receipt_path.read_text(encoding="utf-8"))

    def remote_status(self, state="RUNNING", **changes):
        value = {"request_id": self.identifier, "payload_sha256": request_digest(self.request),
                 "state": state, "cleanup": "UNCONFIRMED"}
        value.update(changes)
        return value

    def completed(self, response, returncode=0):
        return subprocess.CompletedProcess([], returncode, stdout=json.dumps(response), stderr="")

    def assert_reserved(self):
        with patch.object(self.pool, "probe_host", return_value={"id": "remote", "online": True, "busy": False}):
            self.assertTrue(self.pool.probe()[0]["busy"])

    def test_canonical_digest_matches_remote_agent_with_unicode(self):
        self.assertIn("avión", self.request["options"]["require"][0])
        expected = hashlib.sha256(remote_agent.encode(self.request)).hexdigest()
        self.assertEqual(request_digest(self.request), expected)

    def test_status_first_recovers_accepted_job_without_replaying_inputs(self):
        # Neither the archive nor the engine exists in this fixture.
        with patch.object(self.pool, "remote", return_value=self.remote_status()) as remote:
            result = self.pool.recover(self.identifier)
        self.assertEqual(result["state"], "RUNNING")
        self.assertEqual(result["pool_host"], "remote")
        self.assertEqual([call.args[1] for call in remote.call_args_list], ["status", "status"])
        self.assertTrue(all(call.args[0] == self.host for call in remote.call_args_list))
        self.assertTrue(all(call.args[2] == {"request_id": self.identifier} for call in remote.call_args_list))
        self.assertEqual(self.read_receipt()["state"], "SUBMITTED")

    def test_wrong_or_missing_remote_identity_cannot_pass_or_collect(self):
        wrong_hash = self.remote_status("FINISHED", outcome="PASSED", payload_sha256="0" * 64)
        missing_hash = self.remote_status("FINISHED", outcome="PASSED")
        missing_hash.pop("payload_sha256")
        wrong_id = self.remote_status("FINISHED", outcome="PASSED", request_id="otherrequest")
        for label, response in (("wrong hash", wrong_hash), ("missing hash", missing_hash), ("wrong id", wrong_id)):
            with self.subTest(label=label):
                self.reset_receipt()
                with patch.object(self.pool, "remote", return_value=response) as remote, \
                     patch("tools.testqueue.pool.subprocess.run") as transfer:
                    result = self.pool.recover(self.identifier)
                    self.assertEqual(result["state"], "UNKNOWN")
                    self.assertEqual(result["cleanup"], "UNCONFIRMED")
                    self.assertEqual([call.args[1] for call in remote.call_args_list], ["status"])
                    with self.assertRaisesRegex(ValueError, "confirmed finished"):
                        self.pool.collect(self.identifier)
                    transfer.assert_not_called()
                self.assertEqual(self.read_receipt()["state"], "SUBMISSION_UNCONFIRMED")
                self.assert_reserved()
                self.assertFalse((self.pool.root / "results" / self.identifier).exists())

    def test_bound_not_found_replays_only_exact_request_to_original_host(self):
        refusal = {"ok": False, "protocol": remote_agent.PROTOCOL, "request_id": self.identifier,
                   "code": "NOT_FOUND", "error": "request not found"}
        found = {"ok": True, "result": self.remote_status()}
        responses = [self.completed(refusal, 1), self.completed(found), self.completed(found)]
        with patch("tools.testqueue.pool.subprocess.run", side_effect=responses) as ssh:
            result = self.pool.recover(self.identifier)
        self.assertEqual(result["state"], "RUNNING")
        calls = ssh.call_args_list
        actions = [shlex.split(call.args[0][-1])[2] for call in calls]
        self.assertEqual(actions, ["status", "run", "status"])
        self.assertTrue(all(call.args[0][-2] == self.host["ssh"] for call in calls))
        self.assertEqual(json.loads(calls[1].kwargs["input"]), self.request)
        self.assertEqual(json.loads(calls[0].kwargs["input"]), {"request_id": self.identifier})

    def test_unbound_or_disconnected_not_found_never_replays(self):
        responses = {
            "disconnect": subprocess.CompletedProcess([], 255, stdout="", stderr="connection lost"),
            "legacy": self.completed({"ok": False, "code": "NOT_FOUND", "error": "not found"}, 1),
            "wrong request": self.completed({"ok": False, "protocol": 1, "request_id": "other",
                                             "code": "NOT_FOUND", "error": "not found"}, 1),
            "wrong protocol": self.completed({"ok": False, "protocol": 2, "request_id": self.identifier,
                                              "code": "NOT_FOUND", "error": "not found"}, 1),
        }
        for label, response in responses.items():
            with self.subTest(label=label):
                self.reset_receipt()
                with patch("tools.testqueue.pool.subprocess.run", return_value=response) as ssh:
                    result = self.pool.recover(self.identifier)
                self.assertEqual(result["state"], "UNKNOWN")
                self.assertEqual(result["cleanup"], "UNCONFIRMED")
                self.assertEqual(ssh.call_count, 1)
                self.assertEqual(shlex.split(ssh.call_args.args[0][-1])[2], "status")
                self.assertEqual(self.read_receipt()["state"], "SUBMISSION_UNCONFIRMED")
                self.assert_reserved()

    def test_not_found_replay_must_return_same_payload_identity(self):
        refusal = {"ok": False, "protocol": 1, "request_id": self.identifier,
                   "code": "NOT_FOUND", "error": "not found"}
        conflict = {"ok": True, "result": self.remote_status("FINISHED", outcome="PASSED",
                                                                payload_sha256="f" * 64)}
        with patch("tools.testqueue.pool.subprocess.run", side_effect=[self.completed(refusal, 1),
                                                                        self.completed(conflict)]) as ssh:
            result = self.pool.recover(self.identifier)
        self.assertEqual(result["state"], "UNKNOWN")
        self.assertEqual(ssh.call_count, 2)
        self.assertEqual(self.read_receipt()["state"], "SUBMISSION_UNCONFIRMED")
        self.assert_reserved()

    def test_real_agent_reports_request_bound_not_found(self):
        request = {"request_id": self.identifier}
        result = subprocess.run([sys.executable, str(Path(remote_agent.__file__).resolve()),
                                 "status", "--root", str(self.root / "empty-agent")],
                                input=json.dumps(request), capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        response = json.loads(result.stdout)
        self.assertEqual(response["ok"], False)
        self.assertEqual(response["protocol"], remote_agent.PROTOCOL)
        self.assertEqual(response["request_id"], self.identifier)
        self.assertEqual(response["code"], "NOT_FOUND")


class LocalIdentityTests(unittest.TestCase):
    def test_missing_or_mismatched_snapshot_identity_cannot_pass(self):
        with tempfile.TemporaryDirectory(prefix="openrc-local-identity-") as temp:
            root = Path(temp)
            config = root / "config.json"
            write_json(config, {"state_root": str(root / "pool"),
                                "hosts": [{"id": "local", "local": True}]})
            pool = Pool(config)
            identifier = "localidentity"
            receipt_path = pool.root / "jobs" / (identifier + ".json")
            request = {"request_id": identifier, "request_secret": "s" * 64,
                       "expected_source_digest": "a" * 64, "expected_manifest_digest": "b" * 64}
            receipt = {"request_id": identifier, "host": "local", "request": request,
                       "source_digest": "a" * 64, "config_sha256": pool.config_digest,
                       "local_authority_root": str(root / "authority"), "state": "SUBMITTED"}
            observations = [
                {},
                {"source_digest": "c" * 64, "manifest_digest": "b" * 64},
                {"source_digest": "a" * 64, "manifest_digest": "d" * 64},
            ]
            for manifest in observations:
                with self.subTest(manifest=manifest):
                    write_json(receipt_path, receipt)

                    def rpc(operation, **kwargs):
                        if operation == "recover":
                            return {"job": "original-authority-job"}
                        if operation == "status":
                            return {"state": "FINISHED", "outcome": "PASSED", "cleanup": "CONFIRMED",
                                    "evidence": "COMPLETE", "payload": {"manifest": manifest}}
                        self.fail(f"unexpected RPC: {operation}")

                    with patch("tools.testqueue.pool.rpc", side_effect=rpc):
                        result = pool.status(identifier)
                        self.assertEqual(result["state"], "UNKNOWN")
                        with self.assertRaisesRegex(ValueError, "confirmed finished"):
                            pool.collect(identifier)
                    self.assertEqual(json.loads(receipt_path.read_text())["state"], "SUBMISSION_UNCONFIRMED")
                    with patch.object(pool, "probe_host", return_value={"id": "local", "online": True, "busy": False}):
                        self.assertTrue(pool.probe()[0]["busy"])
                    self.assertFalse((pool.root / "results" / identifier).exists())


if __name__ == "__main__":
    unittest.main()
