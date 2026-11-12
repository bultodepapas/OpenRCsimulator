"""Small, isolated worktrees exercise the frozen input contract."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

from tools.testqueue import snapshots


class SnapshotTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-snapshot-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Snapshot Fixture")
        self.git("config", "user.email", "snapshot@example.invalid")
        self.write(".gitignore", b".godot/\napp/native/\n*.ignored\n")
        self.write("app/original.gd", b"original\n")
        self.write("app/delete.gd", b"delete me\n")
        self.write("app/staged-delete.gd", b"delete from index\n")
        self.write("tools/debug/debugctl.py", b"adapter v1\n")
        self.write("outside/not-in-scope.txt", b"no\n")
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")

    def git(self, *args: str) -> bytes:
        return subprocess.check_output(["git", "-C", str(self.repo), *args], stderr=subprocess.PIPE)

    def write(self, name: str, data: bytes) -> Path:
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def capture(self, name: str = "snapshot", **kwargs) -> dict:
        return snapshots.capture(self.repo, self.base / name, scope=("app", "tools"), **kwargs)

    def test_dirty_untracked_deleted_and_binary_inputs_are_frozen(self) -> None:
        self.write("app/original.gd", b"staged\n")
        self.git("add", "app/original.gd")
        self.write("app/original.gd", b"working tree\x00\xff\n")
        (self.repo / "app/delete.gd").unlink()
        self.git("rm", "-q", "app/staged-delete.gd")
        self.write("app/new.bin", b"\x00\xff\x01")
        self.write("app/ignored.ignored", b"ignored")
        self.write("app/native/kernel/native.dll", b"runtime\x00")
        self.write("app/native/kernel/~native.dll~RANDOM.TMP", b"transient")
        receipt = self.capture()
        root = self.base / "snapshot/source"
        self.assertEqual((root / "app/original.gd").read_bytes(), b"working tree\x00\xff\n")
        self.assertEqual((root / "app/new.bin").read_bytes(), b"\x00\xff\x01")
        self.assertEqual((root / "app/native/kernel/native.dll").read_bytes(), b"runtime\x00")
        self.assertFalse((root / "app/ignored.ignored").exists())
        self.assertFalse((root / "app/native/kernel/~native.dll~RANDOM.TMP").exists())
        self.assertFalse((root / "outside/not-in-scope.txt").exists())
        self.assertEqual(receipt["deleted"], ["app/delete.gd", "app/staged-delete.gd"])
        self.assertTrue(receipt["dirty"])
        self.assertFalse(receipt["history_included"])
        self.assertEqual(receipt["commit"], self.git("rev-parse", "HEAD").decode().strip())
        self.assertIn("tools/debug/debugctl.py", receipt["adapter_digests"])
        self.assertTrue(snapshots.verify(self.base / "snapshot")["ok"])
        self.assertEqual(json.loads((self.base / "snapshot/manifest.json").read_text()), receipt)

    def test_later_source_changes_cannot_change_the_snapshot(self) -> None:
        receipt = self.capture()
        frozen = self.base / "snapshot/source/app/original.gd"
        self.write("app/original.gd", b"later edit")
        self.assertEqual(frozen.read_bytes(), b"original\n")
        self.assertEqual(snapshots.verify(self.base / "snapshot")["source_digest"], receipt["source_digest"])
        self.assertTrue(snapshots.verify(self.base / "snapshot")["ok"])

    def test_verify_detects_changed_added_deleted_and_hardlinked_files(self) -> None:
        self.capture()
        root = self.base / "snapshot/source"
        (root / "app/original.gd").write_bytes(b"tampered!")
        (root / "app/delete.gd").unlink()
        (root / "app/extra").write_bytes(b"extra")
        (root / "app/staged-delete.gd").unlink()
        os.link(self.repo / "app/staged-delete.gd", root / "app/staged-delete.gd")
        report = snapshots.verify(self.base / "snapshot")
        self.assertFalse(report["ok"])
        self.assertTrue(any("hash mismatch" in error for error in report["errors"]))
        self.assertTrue(any("missing file" in error for error in report["errors"]))
        self.assertTrue(any("unexpected file" in error for error in report["errors"]))
        self.assertTrue(any("hard-linked file" in error for error in report["errors"]))

    def test_edit_to_earlier_file_during_copy_rejects_entire_capture(self) -> None:
        self.write("app/z-last.gd", b"last")
        original = snapshots._read_hash
        changed = False

        def edit_after_later_copy(path, expected, destination=None):
            nonlocal changed
            result = original(path, expected, destination)
            if destination is not None and path.name == "z-last.gd" and not changed:
                changed = True
                self.write("app/original.gd", b"changed after it was copied")
            return result

        with mock.patch.object(snapshots, "_read_hash", side_effect=edit_after_later_copy):
            with self.assertRaisesRegex(ValueError, "source changed"):
                self.capture()
        self.assertTrue(changed)
        self.assertFalse(snapshots.verify(self.base / "snapshot")["ok"])

    def test_new_untracked_file_during_copy_is_rejected(self) -> None:
        original = snapshots._read_hash
        changed = False

        def add_during_copy(path, expected, destination=None):
            nonlocal changed
            result = original(path, expected, destination)
            if destination is not None and not changed:
                changed = True
                self.write("app/added-later.gd", b"new")
            return result

        with mock.patch.object(snapshots, "_read_hash", side_effect=add_during_copy):
            with self.assertRaisesRegex(ValueError, "source changed"):
                self.capture()

    def test_imports_are_opt_in_and_change_during_copy_fails(self) -> None:
        self.write("app/.godot/imported/asset.bin", b"import")
        for name in snapshots._CACHE_FILES:
            self.write(f"app/.godot/{name}", name.encode())
        regular = self.capture("without-cache")
        self.assertEqual(regular["import_files"], [])
        receipt = self.capture("with-cache", include_imports=True)
        self.assertEqual(len(receipt["import_files"]), 4)
        self.assertEqual((self.base / "with-cache/source/app/.godot/imported/asset.bin").read_bytes(), b"import")
        original = snapshots._read_hash
        changed = False

        def edit_import(path, expected, destination=None):
            nonlocal changed
            result = original(path, expected, destination)
            if destination is not None and path.name == "asset.bin" and not changed:
                changed = True
                self.write("app/.godot/imported/added.bin", b"added during snapshot")
            return result

        with mock.patch.object(snapshots, "_read_hash", side_effect=edit_import):
            with self.assertRaisesRegex(ValueError, "source changed"):
                self.capture("changing-cache", include_imports=True)

    def test_authoring_references_and_research_inputs_are_included(self) -> None:
        self.write("app/data/aircraft_models/fixture.json", json.dumps({"nested": [
            {"path": "assets/source/model.bin"}, "assets/source/missing.bin"]}).encode())
        self.write("assets/source/model.bin", b"authoring input")
        self.write("research/performance/sustained_input.gd", b"input helper")
        receipt = snapshots.capture(self.repo, self.base / "snapshot")
        root = self.base / "snapshot/source"
        self.assertEqual((root / "assets/source/model.bin").read_bytes(), b"authoring input")
        self.assertEqual((root / "research/performance/sustained_input.gd").read_bytes(), b"input helper")
        self.assertEqual(receipt["authoring_files"], ["assets/source/model.bin"])
        self.assertEqual(receipt["missing_authoring_files"], ["assets/source/missing.bin"])
        self.assertTrue(snapshots.verify(self.base / "snapshot")["ok"])

    def test_narrow_native_scope_includes_ignored_binary(self) -> None:
        self.write("app/native/kernel/engine.dll", b"native")
        receipt = snapshots.capture(self.repo, self.base / "snapshot", scope=("app/native/kernel",))
        self.assertEqual(receipt["native_files"], ["app/native/kernel/engine.dll"])
        self.assertEqual((self.base / "snapshot/source/app/native/kernel/engine.dll").read_bytes(), b"native")

    def test_manifest_tampering_is_reported(self) -> None:
        self.capture()
        path = self.base / "snapshot/manifest.json"
        manifest = json.loads(path.read_text())
        manifest["commit"] = "0" * 40
        path.write_text(json.dumps(manifest), encoding="utf-8")
        report = snapshots.verify(self.base / "snapshot")
        self.assertFalse(report["ok"])
        self.assertIn("manifest digest does not match", report["errors"])

    def test_rejects_links_and_destinations_inside_checkout(self) -> None:
        with self.assertRaisesRegex(ValueError, "outside"):
            snapshots.capture(self.repo, self.repo / "snapshot", scope=("app",))
        external = self.base / "external"
        external.write_text("outside", encoding="utf-8")
        try:
            os.symlink(external, self.repo / "app/link")
        except (OSError, NotImplementedError) as exc:
            self.skipTest(f"symlink creation not available: {exc}")
        with self.assertRaisesRegex(ValueError, "linked|reparse"):
            self.capture()

    def test_rejects_missing_cache_invalid_scope_and_low_disk(self) -> None:
        with self.assertRaisesRegex(ValueError, "cache"):
            self.capture("no-cache", include_imports=True)
        with self.assertRaisesRegex(ValueError, "invalid relative path"):
            snapshots.capture(self.repo, self.base / "invalid", scope=("../outside",))
        with mock.patch.object(snapshots.shutil, "disk_usage", return_value=mock.Mock(free=0)):
            with self.assertRaisesRegex(ValueError, "reserve"):
                self.capture("no-space")
        self.assertFalse((self.base / "no-space").exists())

    def test_verify_refuses_manifest_path_escape(self) -> None:
        self.capture()
        path = self.base / "snapshot/manifest.json"
        manifest = json.loads(path.read_text())
        manifest["files"]["../escape"] = next(iter(manifest["files"].values()))
        path.write_text(json.dumps(manifest), encoding="utf-8")
        report = snapshots.verify(self.base / "snapshot")
        self.assertFalse(report["ok"])
        self.assertTrue(any("invalid relative path" in error for error in report["errors"]))


if __name__ == "__main__":
    unittest.main()
