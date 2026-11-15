"""Recovery observes the original attempt; validation errors are not teardown."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.testqueue.test_pool import verified_fixture

from tools.testqueue.common import write_json
from tools.testqueue.pool import Pool


class PoolRecoveryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-pool-recovery-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.config = self.root / "config.json"
        write_json(self.config, {"state_root": str(self.root / "pool"),
                                 "hosts": [{"id": "windows", "local": True}]})
        self.pool = Pool(self.config)
        self.snapshot = self.root / "snapshot"
        self.snapshot.mkdir()
        write_json(self.snapshot / "manifest.json", {"source_root": str(self.root),
                   "source_digest": "fixture", "files": {}})
        self.identifier = "recoverycase"
        self.path = self.pool.root / "jobs" / (self.identifier + ".json")
        self.script = "res://tests/test_fixture.gd"

    def uncertain(self, error=None):
        with patch("tools.testqueue.pool.verify", side_effect=verified_fixture), \
                patch.object(self.pool, "probe", return_value=[]), \
                patch("tools.testqueue.pool.plan", return_value={"selected": "windows"}), \
                patch("tools.testqueue.pool.rpc", side_effect=error or RuntimeError("lost reply")):
            return self.pool.submit(self.snapshot, self.script, request_id=self.identifier)

    def receipt(self):
        return json.loads(self.path.read_text())

    def observed(self, state, **extra):
        return {"state": state, "payload": {"manifest": {"source_digest": "fixture"}}, **extra}

    def legacy(self):
        self.uncertain()
        value = self.receipt()
        value.pop("config_sha256")
        value.pop("local_authority_root")
        value.update(state="NOT_DISPATCHED", last_status={"state": "FINISHED",
                     "outcome": "INFRA_FAILED", "cleanup": "CONFIRMED", "error": "missing input"})
        write_json(self.path, value)
        return value

    def test_initial_validation_response_does_not_prove_nonacceptance(self):
        result = self.uncertain(ValueError("worker response could follow earlier acceptance"))
        self.assertEqual(result["state"], "SUBMISSION_UNCONFIRMED")
        self.assertNotIn("last_status", self.receipt())

    def test_recover_accepted_identity_without_revalidating_missing_inputs(self):
        self.uncertain()
        (self.snapshot / "manifest.json").unlink()
        with patch("tools.testqueue.pool.rpc", side_effect=[{"job": "owned"},
                {"job": "owned"}, self.observed("RUNNING", cleanup="UNCONFIRMED")]) as rpc:
            result = self.pool.recover(self.identifier)
        self.assertEqual([call.args[0] for call in rpc.call_args_list], ["recover", "recover", "status"])
        self.assertEqual(result["state"], "RUNNING")
        self.assertEqual(self.receipt()["accepted"]["job"], "owned")

    def test_absence_then_replay_refusal_stays_uncertain(self):
        self.uncertain()
        request = self.receipt()["request"]
        with patch("tools.testqueue.pool.rpc", side_effect=[None, ValueError("snapshot unavailable")]) as rpc:
            result = self.pool.recover(self.identifier)
        self.assertEqual([call.args[0] for call in rpc.call_args_list], ["recover", "submit"])
        self.assertEqual(rpc.call_args.kwargs["request_id"], request["request_id"])
        self.assertEqual(rpc.call_args.kwargs["request_secret"], request["request_secret"])
        self.assertEqual(result["state"], "UNKNOWN")
        self.assertEqual(result["cleanup"], "UNCONFIRMED")
        self.assertEqual(self.receipt()["state"], "SUBMISSION_UNCONFIRMED")

    def test_late_original_acceptance_is_found_after_replay_failure(self):
        self.uncertain()
        with patch("tools.testqueue.pool.rpc", side_effect=[None, ValueError("input changed"),
                {"job": "original"}, self.observed("RUNNING")]) as rpc:
            self.pool.recover(self.identifier)
            result = self.pool.status(self.identifier)
        self.assertEqual([call.args[0] for call in rpc.call_args_list],
                         ["recover", "submit", "recover", "status"])
        self.assertEqual(result["state"], "RUNNING")
        self.assertEqual(result["pool_host"], "windows")

    def test_legacy_terminal_status_requeries_and_preserves_original(self):
        original = self.legacy()
        with patch("tools.testqueue.pool.rpc", side_effect=[{"job": "original"}, self.observed("RUNNING")]) as rpc:
            result = self.pool.status(self.identifier)
        self.assertEqual([call.args[0] for call in rpc.call_args_list], ["recover", "status"])
        self.assertEqual(result["state"], "RUNNING")
        self.assertEqual(result["pool_recovery_version"], 1)
        self.assertEqual(self.receipt()["invalidated_nonexecution"]["status"], original["last_status"])
        self.assertTrue(self.pool.needs_reobservation(self.identifier, original["last_status"]))
        self.assertFalse(self.pool.needs_reobservation(self.identifier, result))

    def test_legacy_receipt_reuse_cannot_repeat_false_terminal_state(self):
        self.legacy()
        with patch("tools.testqueue.pool.rpc") as rpc:
            result = self.pool.submit(self.snapshot, self.script, request_id=self.identifier)
        rpc.assert_not_called()
        self.assertEqual(result["state"], "SUBMISSION_UNCONFIRMED")
        self.assertIn("invalidated_nonexecution", self.receipt())

    def test_legacy_unknown_retains_host_reservation(self):
        self.legacy()
        with patch.object(self.pool, "probe_host", return_value={"id": "windows", "online": True, "busy": False}):
            self.assertTrue(self.pool.probe()[0]["busy"])
        with patch("tools.testqueue.pool.rpc", side_effect=RuntimeError("authority unavailable")):
            result = self.pool.status(self.identifier)
        self.assertEqual(result["state"], "UNKNOWN")
        self.assertEqual(self.receipt()["state"], "SUBMISSION_UNCONFIRMED")

    def test_legacy_unbound_absence_does_not_authorize_replay(self):
        self.legacy()
        with patch("tools.testqueue.pool.rpc", return_value=None) as rpc:
            result = self.pool.recover(self.identifier)
        self.assertEqual([call.args[0] for call in rpc.call_args_list], ["recover"])
        self.assertEqual(result["state"], "UNKNOWN")
        self.assertIn("destination binding", result["error"])

    def test_changed_config_cannot_redirect_recovery(self):
        self.uncertain()
        config = json.loads(self.config.read_text())
        config["hosts"][0] = {"id": "windows", "ssh": "different-authority"}
        write_json(self.config, config)
        rebound = Pool(self.config)
        with patch("tools.testqueue.pool.rpc") as rpc, patch.object(rebound, "remote") as remote:
            result = rebound.recover(self.identifier)
        rpc.assert_not_called()
        remote.assert_not_called()
        self.assertEqual(result["state"], "UNKNOWN")
        self.assertIn("configuration changed", result["error"])

    def test_local_authority_root_is_bound_before_dispatch(self):
        # Windows may canonicalize the temporary user's long/8.3 path spelling.
        original_root = (self.root / "original-authority").resolve()
        with patch("tools.testqueue.pool.state_root", return_value=original_root):
            self.uncertain()
        with patch("tools.testqueue.pool.state_root", return_value=self.root / "different-authority"), \
                patch("tools.testqueue.pool.rpc", side_effect=[{"job": "owned"}, {"state": "RUNNING"}]) as rpc:
            self.pool.status(self.identifier)
        self.assertTrue(all(call.kwargs["root"] == original_root for call in rpc.call_args_list))

    def test_recollection_keeps_old_terminal_artifacts(self):
        self.legacy()
        destination = self.pool.root / "results" / self.identifier
        destination.mkdir(parents=True)
        original = destination / "pool-status.json"
        original.write_text("retained original false status")
        with patch("tools.testqueue.pool.rpc", side_effect=[{"job": "original"},
                self.observed("FINISHED", outcome="INFRA_FAILED", cleanup="CONFIRMED")]):
            report = self.pool.collect(self.identifier)
        self.assertEqual(original.read_text(), "retained original false status")
        self.assertEqual(Path(report["pool_status"]).parent, destination / "recovery-1")


if __name__ == "__main__":
    unittest.main()
