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


if __name__ == "__main__":
    unittest.main()
