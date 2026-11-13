#!/usr/bin/env python3
"""Small, process-free-of-Godot regression for historical app reconstruction."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location("publication_rebind_collector", HERE / "collect_publication_rebind.py")
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class ReconstructionTest(unittest.TestCase):
    def test_complete_historical_tree_and_checkout_line_endings(self):
        (ROOT / "tmp").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="publication-copy-test-", dir=ROOT / "tmp") as temp:
            repo = Path(temp) / "repo"
            repo.mkdir()

            def git(*args):
                return subprocess.check_output(["git", "-c", "core.autocrlf=false", *args], cwd=repo).decode().strip()

            git("init", "-q")
            git("config", "user.email", "fixture@example.invalid")
            git("config", "user.name", "Fixture")
            (repo / "app").mkdir()
            (repo / ".gitattributes").write_text("app/data.json text eol=crlf\n", encoding="utf-8")
            (repo / "app/data.json").write_bytes(b'{"old":true}\r\n')
            (repo / "app/removed.gd").write_text("old\n", encoding="utf-8")
            (repo / "app/changed.gd").write_text("baseline\n", encoding="utf-8")
            git("add", "--all")
            git("commit", "-qm", "baseline")
            baseline = git("rev-parse", "HEAD")
            (repo / "app/data.json").write_bytes(b'{"new":true}\r\n')
            (repo / "app/removed.gd").unlink()
            (repo / "app/changed.gd").write_text("candidate\n", encoding="utf-8")
            (repo / "app/added.gd").write_text("added\n", encoding="utf-8")
            git("add", "--all")
            git("commit", "-qm", "candidate")
            candidate = git("rev-parse", "HEAD")
            isolated = Path(temp) / "baseline"
            isolated.mkdir()
            shutil.copytree(repo / "app", isolated / "app")
            with mock.patch.object(collector, "ROOT", repo), mock.patch.object(collector, "BASELINE", baseline):
                historical, current = collector.tree(baseline), collector.tree(candidate)
                collector.reconstruct(isolated, current, historical, Path(temp) / "baseline.index")
                before = collector.inventory(isolated, baseline, historical)
                self.assertEqual((isolated / "app/data.json").read_bytes(), b'{"old":true}\r\n')
                self.assertEqual((isolated / "app/changed.gd").read_text(), "baseline\n")
                self.assertTrue((isolated / "app/removed.gd").is_file())
                self.assertFalse((isolated / "app/added.gd").exists())
                self.assertEqual(before, collector.inventory(isolated, baseline, historical))
                (isolated / "app/untracked.gd").write_text("unexpected\n")
                with self.assertRaisesRegex(ValueError, "file set differs"):
                    collector.inventory(isolated, baseline, historical)
                (isolated / "app/untracked.gd").unlink()
                attributes = isolated / ".gitattributes"
                original_attributes = attributes.read_bytes()
                attributes.write_text("* -text\n")
                with self.assertRaisesRegex(ValueError, "attributes differ"):
                    collector.inventory(isolated, baseline, historical)
                attributes.write_bytes(original_attributes)
                (isolated / "app/changed.gd").write_text("drift\n", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "differs from Git blob"):
                    collector.inventory(isolated, baseline, historical)


if __name__ == "__main__":
    unittest.main()
