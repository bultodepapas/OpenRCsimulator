"""Local source reclamation keeps evidence, failures and claimed work, and never follows links."""
import contextlib
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest

from tools.testqueue import local_gc


class LocalGcTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-local-gc-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.db = sqlite3.connect(self.root / "queue.sqlite3")
        self.db.executescript("CREATE TABLE jobs (id TEXT, state TEXT);"
                              "CREATE TABLE attempts (id TEXT, job TEXT, generation INTEGER, state TEXT, data TEXT);"
                              "CREATE TABLE claims (resource TEXT, attempt TEXT, amount INTEGER);")
        self.addCleanup(self.db.close)

    def attempt(self, name, *, job_state="FINISHED", state="FINISHED", outcome="PASSED", claimed=False):
        self.db.execute("INSERT INTO jobs VALUES (?, ?)", ("T-" + name, job_state))
        data = {"outcome": outcome, "evidence": "COMPLETE", "cleanup": "CONFIRMED"}
        self.db.execute("INSERT INTO attempts VALUES (?, ?, 1, ?, ?)", (name, "T-" + name, state, json.dumps(data)))
        if claimed:
            self.db.execute("INSERT INTO claims VALUES ('headless', ?, 1)", (name,))
        self.db.commit()
        directory = self.root / "attempts" / name
        (directory / "source" / "app").mkdir(parents=True)
        (directory / "source" / "app" / "big.bin").write_bytes(b"x" * 1000)
        (directory / "checks").mkdir()
        (directory / "checks" / "report.json").write_text("{}")
        (directory / "verdict.json").write_text("{}")
        return directory

    def test_only_unclaimed_finished_passes_lose_their_source(self):
        kept = {name: self.attempt(name, **options) for name, options in {
            "failed": {"outcome": "TEST_FAILED"}, "running": {"state": "RUNNING", "job_state": "RUNNING"},
            "claimed": {"claimed": True}, "unknown": {"state": "UNKNOWN", "outcome": None}}.items()}
        passed = self.attempt("passed")
        self.assertEqual([name for name, _ in local_gc.candidates(self.root)], ["passed"])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(local_gc.main(["--root", str(self.root)]), 0)
        self.assertTrue((passed / "source").exists(), "dry run must not delete")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(local_gc.main(["--root", str(self.root), "--execute"]), 0)
        self.assertFalse((passed / "source").exists())
        self.assertTrue((passed / "checks" / "report.json").is_file())
        self.assertTrue((passed / "verdict.json").is_file())
        for directory in kept.values():
            self.assertTrue((directory / "source" / "app" / "big.bin").is_file())

    def test_links_inside_the_source_are_removed_without_touching_targets(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "precious.txt").write_text("keep")
        passed = self.attempt("passed")
        link = passed / "source" / "app" / ".godot"
        if os.name == "nt":
            created = subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(outside)],
                                     capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
            if created.returncode:
                self.skipTest("junction creation unavailable")
        else:
            link.symlink_to(outside, target_is_directory=True)
        removed = local_gc.safe_remove_tree(passed / "source")
        self.assertEqual(removed, 1000)
        self.assertFalse((passed / "source").exists())
        self.assertEqual((outside / "precious.txt").read_text(), "keep")


if __name__ == "__main__":
    unittest.main()
