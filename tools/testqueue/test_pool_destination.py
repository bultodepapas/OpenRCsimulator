"""TQ-07-A1: a receipt binds its own destination, not the whole configuration file.

Before this, any edit of ``config.json`` (adding a host, tuning another host)
made every in-flight receipt refuse observation and recovery, and the failed
observation demoted it to a state that reserves its host forever.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock

from tools.testqueue.common import write_json
from tools.testqueue.pool import Pool, RemoteRefusal, destination_of, identity_matches, request_digest
from tools.testqueue.pool_batch import run_batch


MAC = {"id": "mac", "ssh": "mac-alias", "python": "python3", "root": "/r", "agent": "/a", "engine": "/e"}
LINUX = {"id": "linux", "ssh": "linux-alias", "python": "python3", "root": "/l", "agent": "/a", "engine": "/e"}


class DestinationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-destination-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.config = self.root / "config.json"
        self.write_config([dict(MAC)])
        self.pool = Pool(self.config)
        (self.pool.root / "jobs").mkdir(parents=True, exist_ok=True)
        self.request = {"request_id": "job1", "preset": "checked", "engine_path": "/e",
                        "archive": {"path": "/r/incoming/a.tar", "sha256": "a" * 64},
                        "options": {"script": "res://tests/test_sample.gd"}}

    def write_config(self, hosts, **extra):
        write_json(self.config, {"state_root": str(self.root / "pool"), "hosts": hosts, **extra})

    def receipt(self, identifier="job1", *, state="SUBMITTED", **fields):
        value = {"request_id": identifier, "host": "mac", "state": state, "created": time.time(),
                 "request": {**self.request, "request_id": identifier}, **fields}
        write_json(self.pool.root / "jobs" / (identifier + ".json"), value)
        return value

    def path(self, identifier="job1"):
        return self.pool.root / "jobs" / (identifier + ".json")

    def running(self, identifier="job1"):
        return {"request_id": identifier, "state": "RUNNING", "cleanup": "UNCONFIRMED",
                "payload_sha256": request_digest({**self.request, "request_id": identifier})}

    def test_unrelated_edits_keep_observation_recovery_and_replay(self):
        self.receipt(destination=destination_of(MAC), config_sha256=self.pool.config_digest)
        self.write_config([dict(MAC, transfer_bytes_per_second=1), dict(LINUX)], engine_version="x")
        with mock.patch.object(self.pool, "remote", return_value=self.running()) as remote:
            self.assertEqual(self.pool.status("job1")["state"], "RUNNING")
            self.assertEqual(self.pool.recover("job1")["state"], "RUNNING")
        self.assertTrue(all(call.args[0]["id"] == "mac" for call in remote.call_args_list))
        self.assertEqual(self.pool.hosts[1]["id"], "linux")  # the running pool followed the edit
        # Replay of a never-confirmed request is still allowed on the same destination.
        self.receipt("job2", state="SUBMISSION_UNCONFIRMED", destination=destination_of(MAC))
        replies = [RemoteRefusal("request not found", "NOT_FOUND"), self.running("job2"), self.running("job2")]
        with mock.patch.object(self.pool, "remote", side_effect=replies) as remote:
            self.assertEqual(self.pool.recover("job2")["state"], "RUNNING")
        self.assertEqual([call.args[1] for call in remote.call_args_list], ["status", "run", "status"])

    def test_a_moved_destination_is_refused_and_the_receipt_is_untouched(self):
        self.receipt(destination=destination_of(MAC))
        before = self.path().read_bytes()
        for label, host in (("root", dict(MAC, root="/elsewhere")), ("ssh", dict(MAC, ssh="other-alias")),
                            ("local", {"id": "mac", "local": True})):
            with self.subTest(field=label):
                self.write_config([host])
                with mock.patch.object(self.pool, "remote") as remote, \
                        mock.patch("tools.testqueue.pool.rpc") as rpc:
                    for operation in (self.pool.status, self.pool.recover):
                        result = operation("job1")
                        self.assertEqual((result["state"], result["reason_code"]), ("UNKNOWN", "DESTINATION_CHANGED"))
                        self.assertIn(f"{label} differs", result["error"])
                remote.assert_not_called()
                rpc.assert_not_called()
                self.assertEqual(self.path().read_bytes(), before)
        self.assertFalse(self.pool._reserve([{"id": "mac", "busy": False}])[0]["busy"])

    def test_alias_change_needs_the_bound_store_identity_before_replay(self):
        identity = {"machine_id": "m" * 32, "store_id": "s" * 32}
        self.receipt(state="SUBMISSION_UNCONFIRMED", destination=destination_of(MAC, identity))
        self.write_config([dict(MAC, ssh="renamed-alias")])

        def transport(answer):
            def remote(host, action, payload, timeout=45):
                if action == "status":
                    raise RemoteRefusal("request not found", "NOT_FOUND")
                if action == "probe":
                    return {"identity": answer}
                if action == "run":
                    return self.running()
                raise AssertionError(action)
            return remote

        before = self.path().read_bytes()
        with mock.patch.object(self.pool, "remote", side_effect=transport({**identity, "store_id": "t" * 32})) as remote:
            result = self.pool.recover("job1")
            self.assertEqual(self.pool.status("job1")["reason_code"], "DESTINATION_CHANGED")
        self.assertEqual((result["state"], result["reason_code"]), ("UNKNOWN", "DESTINATION_CHANGED"))
        # Not even observed through the unproved alias, and the receipt is untouched.
        self.assertEqual({call.args[1] for call in remote.call_args_list}, {"probe"})
        self.assertEqual(self.path().read_bytes(), before)
        with mock.patch.object(self.pool, "remote", side_effect=transport(identity)) as remote:
            result = self.pool.recover("job1")
        self.assertIn("run", [call.args[1] for call in remote.call_args_list])

    def test_legacy_receipt_resolves_from_a_retained_configuration(self):
        old_digest = self.pool.config_digest  # retained under config-history by the pool
        self.receipt(config_sha256=old_digest)
        self.write_config([dict(MAC), dict(LINUX)])
        with mock.patch.object(self.pool, "remote", return_value=self.running()):
            self.assertEqual(self.pool.status("job1")["state"], "RUNNING")
        # A backup beside the file that no pool ever loaded also resolves, and a
        # destination that moved since that backup is still refused.
        backup = self.config.with_name("config.json.bak.fixture")
        data = json.dumps({"state_root": str(self.root / "pool"), "hosts": [MAC], "note": "backup"}).encode()
        backup.write_bytes(data)
        self.receipt("job3", config_sha256=hashlib.sha256(data).hexdigest())
        with mock.patch.object(self.pool, "remote", return_value=self.running("job3")):
            self.assertEqual(self.pool.status("job3")["state"], "RUNNING")
        self.write_config([dict(MAC, root="/elsewhere")])
        with mock.patch.object(self.pool, "remote") as remote:
            self.assertEqual(self.pool.status("job3")["reason_code"], "DESTINATION_CHANGED")
        remote.assert_not_called()

    def test_unresolvable_legacy_receipt_is_observed_but_never_replayed(self):
        self.receipt(state="SUBMISSION_UNCONFIRMED", config_sha256="f" * 64)
        replies = [RemoteRefusal("request not found", "NOT_FOUND")]
        with mock.patch.object(self.pool, "remote", side_effect=replies) as remote:
            result = self.pool.recover("job1")
        self.assertEqual(result["state"], "UNKNOWN")
        self.assertIn("automatic replay refused", result["error"])
        self.assertEqual([call.args[1] for call in remote.call_args_list], ["status"])

    def test_invalid_edit_keeps_the_previous_configuration(self):
        self.receipt(destination=destination_of(MAC))
        self.config.write_text("{ not json")
        with mock.patch.object(self.pool, "remote") as remote:
            result = self.pool.status("job1")
        self.assertEqual(result["reason_code"], "DESTINATION_CHANGED")
        self.assertIn("invalid", result["error"])
        remote.assert_not_called()
        self.assertEqual(self.pool.hosts, [MAC])

    def test_new_receipts_bind_the_probed_store_identity(self):
        identity = {"machine_id": None, "store_id": "s" * 32}
        self.assertEqual(destination_of(MAC, identity)["identity"], identity)
        self.assertNotIn("identity", destination_of(MAC, None))
        self.assertTrue(identity_matches(identity, {"machine_id": "m" * 32, "store_id": "s" * 32}))
        self.assertFalse(identity_matches(identity, {"machine_id": None, "store_id": "t" * 32}))
        self.assertFalse(identity_matches(None, identity))
        # A bound machine must be named again: a clone that copied store-id.json
        # but cannot report the machine is refused.
        bound = {"machine_id": "m" * 32, "store_id": "s" * 32}
        self.assertFalse(identity_matches(bound, {"machine_id": None, "store_id": "s" * 32}))
        self.assertTrue(identity_matches(bound, dict(bound)))

    def test_config_swap_is_atomic_for_concurrent_readers(self):
        # Review finding D4: lanes read hosts while another lane refreshes.
        snapshot = self.pool._snapshot
        self.write_config([dict(MAC), dict(LINUX)])
        self.assertTrue(self.pool.refresh_config())
        self.assertIsNot(self.pool._snapshot, snapshot)
        self.assertEqual(snapshot.hosts, [MAC])  # an earlier reader's view never changes under it
        write_json(self.config, {"state_root": str(self.root / "elsewhere"), "hosts": [MAC]})
        with self.assertRaisesRegex(ValueError, "state_root"):
            self.pool.refresh_config()
        self.assertEqual([host["id"] for host in self.pool.hosts], ["mac", "linux"])  # never published


class BatchConfigEditTests(unittest.TestCase):
    def test_batch_resumes_after_a_configuration_edit(self):
        with tempfile.TemporaryDirectory(prefix="openrc-batch-edit-") as temporary:
            root = Path(temporary)
            config = root / "config.json"
            write_json(config, {"state_root": str(root / "pool"), "hosts": [dict(MAC)]})
            snapshot = root / "snapshot"
            snapshot.mkdir()
            write_json(snapshot / "manifest.json", {"files": {}})
            manifest = root / "batch.json"
            write_json(manifest, {"snapshot": str(snapshot), "jobs": [{"script": "res://tests/test_a.gd"}]})
            state = root / "batch-state.json"
            pool = Pool(config)
            waiting = {"state": "WAITING", "decision": {"selected": None, "candidates": []}}
            with mock.patch.object(Pool, "submit", return_value=waiting):
                run_batch(pool, config, manifest, state, timeout=0.2, poll_interval=0)
                first = json.loads(state.read_text())["config_sha256"]
                write_json(config, {"state_root": str(root / "pool"), "hosts": [dict(MAC), dict(LINUX)]})
                result = run_batch(Pool(config), config, manifest, state, timeout=0.2, poll_interval=0)
            self.assertEqual(result["result"], "INCOMPLETE")
            saved = json.loads(state.read_text())
            self.assertNotEqual(saved["config_sha256"], first)
            self.assertEqual(saved["config_history"][0]["config_sha256"], first)


if __name__ == "__main__":
    unittest.main()
