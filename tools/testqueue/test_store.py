"""Durable restart and cancellation invariants, with no simulator process."""
from pathlib import Path
import tempfile
import unittest

from tools.testqueue.common import Singleton
from tools.testqueue.store import Store


class DurableStoreTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="openrc-store-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.store = Store(self.root)
        self.addCleanup(lambda: self.store.db.close())

    def submit(self, identifier):
        return self.store.submit(identifier, {"owner": identifier}, "s" * 32)["job"]

    def test_restart_retains_unknown_claim_and_blocks_conflicting_dispatch(self):
        first, second = self.submit("first"), self.submit("second")
        attempt = self.store.allocate(first, {"rendered": 1}, {"rendered": 1}, {"process": {"host": "fixture", "boot": "fixture"}})
        self.store.update(first, attempt, "RUNNING", {"process": {"host": "fixture", "boot": "fixture"}})
        self.store.db.close()
        self.store = Store(self.root)
        self.assertEqual(self.store.get(first)["state"], "UNKNOWN")
        self.assertIsNone(self.store.allocate(second, {"rendered": 1}, {"rendered": 1}))
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM claims").fetchone()[0], 1)

    def test_delayed_start_after_cancel_is_rejected_across_restart(self):
        job = self.submit("cancel-before-start")
        self.store.cancel(job)
        self.store.db.close()
        self.store = Store(self.root)
        self.assertIsNone(self.store.allocate(job, {"rendered": 1}, {"rendered": 1}))
        self.assertEqual(self.store.get(job)["outcome"], "CANCELED")
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM attempts").fetchone()[0], 0)

    def test_operator_abandonment_releases_only_orphan_and_retains_incomplete_evidence(self):
        first, second = self.submit("orphan"), self.submit("next")
        attempt = self.store.allocate(first, {"exclusive": 1}, {"exclusive": 1})
        identity = {"process": {"host": "fixture", "boot": "fixture"}}
        self.store.update(first, attempt, "UNKNOWN", identity)
        for reason in (None, "", " ", "x" * 2001):
            with self.assertRaises(ValueError):
                self.store.abandon(first, reason)
        self.assertIsNone(self.store.allocate(second, {"headless": 1}, {"headless": 1}))
        self.store.abandon(first, "Owner requested release after loss of supervisor")
        status = self.store.get(first)
        self.assertEqual(status["state"], "FINISHED")
        self.assertEqual(status["outcome"], "INFRA_FAILED")
        self.assertEqual(status["cleanup"], "UNCONFIRMED")
        self.assertEqual(status["evidence"], "INCOMPLETE")
        self.assertEqual(status["process"], identity["process"])
        self.assertTrue(status["operator_abandoned"]["reason"])
        self.assertIsNotNone(self.store.allocate(second, {"headless": 1}, {"headless": 1}))
        with self.assertRaisesRegex(ValueError, "only UNKNOWN"):
            self.store.abandon(first, "repeat")

    def test_failed_release_rolls_back_and_singleton_cannot_be_duplicated(self):
        job = self.submit("cleanup")
        attempt = self.store.allocate(job, {"rendered": 1}, {"rendered": 1})
        with self.assertRaisesRegex(ValueError, "confirmed process-tree cleanup"):
            self.store.update(job, attempt, "FINISHED", {"cleanup": "UNCONFIRMED"})
        self.assertEqual(self.store.get(job)["state"], "DISPATCHING")
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM claims").fetchone()[0], 1)
        guard = Singleton(self.root / "singleton.lock")
        try:
            with self.assertRaises(OSError):
                Singleton(self.root / "singleton.lock")
        finally:
            guard.close()

    def test_recover_authenticates_without_creating_a_job(self):
        self.assertIsNone(self.store.recover("missing", "s" * 32))
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM jobs").fetchone()[0], 0)
        accepted = self.store.submit("original", {"owner": "fixture"}, "s" * 32)
        self.assertEqual(self.store.recover("original", "s" * 32), accepted)
        for method in (self.store.recover, self.store.cancel_submission):
            with self.assertRaisesRegex(ValueError, "another submitting client"):
                method("original", "x" * 32)
        self.assertFalse(self.store.get(accepted["job"])["canceled"])

    def test_cancel_before_late_submit_is_durable_and_never_dispatches(self):
        self.assertEqual(self.store.cancel_submission("late", "s" * 32), {"canceled": True})
        self.store.db.close()
        self.store = Store(self.root)
        with self.assertRaisesRegex(ValueError, "another submitting client"):
            self.store.submit("late", {}, "x" * 32)
        accepted = self.store.submit("late", {"owner": "fixture"}, "s" * 32)
        self.assertEqual(self.store.get(accepted["job"])["outcome"], "CANCELED")
        self.assertIsNone(self.store.allocate(accepted["job"], {"rendered": 1}, {"rendered": 1}))
        self.assertEqual(self.store.recover("late", "s" * 32), accepted)

    def test_cancel_unacknowledged_dispatch_retains_claim_until_cleanup(self):
        accepted = self.store.submit("dispatch", {}, "s" * 32)
        attempt = self.store.allocate(accepted["job"], {"exclusive": 1}, {"exclusive": 1})
        canceled = self.store.cancel_submission("dispatch", "s" * 32)
        self.assertEqual(canceled, {"canceled": True, **accepted})
        self.assertTrue(self.store.get(accepted["job"])["canceled"])
        self.assertEqual(self.store.db.execute("SELECT attempt FROM claims").fetchone()[0], attempt)

    def test_version_one_store_migrates_and_preserves_jobs(self):
        job = self.submit("legacy")
        self.store.db.execute("DROP TABLE canceled_submissions")
        self.store.db.execute("PRAGMA user_version=1")
        self.store.db.commit()
        self.store.db.close()
        self.store = Store(self.root)
        self.assertEqual(self.store.get(job)["state"], "QUEUED")
        self.assertEqual(self.store.db.execute("PRAGMA user_version").fetchone()[0], 2)
        self.store.cancel_submission("legacy", "s" * 32)
        self.assertEqual(self.store.get(job)["outcome"], "CANCELED")


if __name__ == "__main__":
    unittest.main()
