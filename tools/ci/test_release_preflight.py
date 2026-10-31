"""Disposable Git fixtures for the cheap CI release preflight."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import release_preflight as preflight

REPO = Path(__file__).resolve().parents[2]
TAG = "v1.2.3-rc.2"


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc preflight ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in preflight.REQUIRED_FILES:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / name, target)
        (self.root / "app/project.godot").write_text('config/version="1.2.3"\n', encoding="utf-8")
        self.git("init", "--quiet")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "user.name", "Release fixture")
        self.git("config", "core.autocrlf", "false")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.PIPE).decode().strip()

    def commit(self, *, notes=b"Release notes\n", tag=TAG):
        if notes is not None:
            path = self.root / "docs/releases" / f"{tag}.md"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(notes)
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "fixture", "--allow-empty")
        if tag:
            self.git("tag", "-f", tag)
        return self.git("rev-parse", "HEAD")

    def test_release_and_untagged_candidate_events(self):
        sha = self.commit()
        result = preflight.preflight(self.root, "push", f"refs/tags/{TAG}", sha)
        self.assertEqual(result["tag"], TAG)
        for event, ref in (("push", "refs/heads/main"), ("workflow_dispatch", "refs/heads/feature"),
                           ("pull_request", "refs/pull/42/merge")):
            with self.subTest(event=event):
                self.assertIsNone(preflight.preflight(self.root, event, ref, sha)["tag"])

    def test_branch_candidate_does_not_need_release_notes_or_tag(self):
        sha = self.commit(notes=None, tag=None)
        self.assertIsNone(preflight.preflight(self.root, "workflow_dispatch", "refs/heads/feature", sha)["tag"])

    def test_rejects_wrong_sha_and_invalid_ref(self):
        sha = self.commit()
        with self.assertRaisesRegex(ValueError, "event SHA"):
            preflight.preflight(self.root, "push", "refs/heads/main", "0" * 40)
        with self.assertRaisesRegex(ValueError, "PR merge"):
            preflight.preflight(self.root, "pull_request", "refs/heads/main", sha)
        with self.assertRaisesRegex(ValueError, "full lowercase"):
            preflight.preflight(self.root, "push", "refs/heads/main", sha[:8])

    def test_rejects_dirty_tracked_input_and_untracked_app(self):
        sha = self.commit()
        script = self.root / "app/get-templates.sh"
        original = script.read_bytes()
        script.write_bytes(original + b"\n# changed\n")
        with self.assertRaisesRegex(ValueError, "tracked source changed"):
            preflight.preflight(self.root, "push", f"refs/tags/{TAG}", sha)
        script.write_bytes(original)
        (self.root / "app/untracked.gd").write_text("fixture")
        with self.assertRaisesRegex(ValueError, "untracked application"):
            preflight.preflight(self.root, "push", f"refs/tags/{TAG}", sha)

    def test_rejects_missing_empty_and_untracked_notes(self):
        sha = self.commit(notes=None)
        for content in (None, b"", b"untracked"):
            path = self.root / "docs/releases" / f"{TAG}.md"
            path.parent.mkdir(parents=True, exist_ok=True)
            if content is not None:
                path.write_bytes(content)
            with self.subTest(content=content), self.assertRaises(ValueError):
                preflight.preflight(self.root, "push", f"refs/tags/{TAG}", sha)

    def test_rejects_mismatched_version_bad_tag_and_moved_tag(self):
        (self.root / "app/project.godot").write_text('config/version="1.2.4"\n')
        sha = self.commit()
        with self.assertRaisesRegex(ValueError, "version mismatch"):
            preflight.preflight(self.root, "push", f"refs/tags/{TAG}", sha)
        with self.assertRaisesRegex(ValueError, "invalid release tag"):
            preflight.preflight(self.root, "push", "refs/tags/v1.2.3-rc_2", sha)
        (self.root / "app/project.godot").write_text('config/version="1.2.3"\n')
        new_sha = self.commit(notes=None, tag=None)
        with self.assertRaisesRegex(ValueError, "does not identify"):
            preflight.preflight(self.root, "push", f"refs/tags/{TAG}", new_sha)

    def test_release_tag_length_matches_manifest_boundary(self):
        prefix = "v1.2.3-"
        valid = prefix + "a" * (160 - len(prefix))
        invalid = valid + "a"
        notes = self.root / "docs/releases"
        notes.mkdir(parents=True)
        for tag in (valid, invalid):
            (notes / f"{tag}.md").write_text("Release notes\n", encoding="utf-8")
        sha = self.commit(notes=None, tag=None)
        for tag in (valid, invalid):
            self.git("tag", tag)
        self.assertEqual(preflight.preflight(self.root, "push", f"refs/tags/{valid}", sha)["tag"], valid)
        with self.assertRaisesRegex(ValueError, "invalid release tag"):
            preflight.preflight(self.root, "push", f"refs/tags/{invalid}", sha)

    def test_rejects_committed_inconsistent_pin(self):
        script = self.root / "app/get-templates.sh"
        script.write_text(script.read_text().replace("VERSION=4.8-beta1", "VERSION=9.9-stable", 1))
        sha = self.commit()
        with self.assertRaisesRegex(ValueError, "versions differ"):
            preflight.preflight(self.root, "push", f"refs/tags/{TAG}", sha)

    def test_requires_committed_uid_sidecars_before_import(self):
        names = ("shadow policy á.gd", "shadow.gdshader")
        for name in names:
            (self.root / "app" / name).write_text("# source\n", encoding="utf-8")
        sha = self.commit(notes=None, tag=None)
        with self.assertRaisesRegex(ValueError, "tracked Godot UID sidecars") as failure:
            preflight.preflight(self.root, "push", "refs/heads/main", sha)
        self.assertIn("shadow.gdshader.uid", str(failure.exception))
        for index, name in enumerate(names):
            (self.root / "app" / (name + ".uid")).write_text(f"uid://b{index + 1}2345\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "untracked application source"):
            preflight.preflight(self.root, "push", "refs/heads/main", sha)
        sha = self.commit(notes=None, tag=None)
        self.assertEqual(preflight.preflight(self.root, "push", "refs/heads/main", sha)["source"], sha)

    def test_rejects_empty_committed_uid_sidecar(self):
        (self.root / "app/new.gd").write_text("# source\n", encoding="utf-8")
        (self.root / "app/new.gd.uid").touch()
        sha = self.commit(notes=None, tag=None)
        with self.assertRaisesRegex(ValueError, "new.gd.uid"):
            preflight.preflight(self.root, "push", "refs/heads/main", sha)


if __name__ == "__main__":
    unittest.main()
