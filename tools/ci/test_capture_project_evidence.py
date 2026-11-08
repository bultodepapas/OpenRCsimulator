"""Real filesystem controls for lossless capture artifact deduplication."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import capture_project_evidence as evidence


class CaptureProjectEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.captures = Path(self.temp.name) / "captures"
        self.reference = self.captures / evidence.REFERENCE
        self.target = self.captures / evidence.TARGET
        for root in (self.reference, self.target):
            (root / "render").mkdir(parents=True)
            (root / "project.godot").write_bytes(b"[application]\n")
            (root / "render/ground.gdshader").write_bytes(b"shader_type spatial;\n")
            (root / "binary.dat").write_bytes(bytes(range(256)))
        (self.captures / "capture.png").write_bytes(b"retained render")
        self.before = evidence.inventory(self.target)

    def prepare(self):
        return evidence.prepare(self.captures)

    def remove_uploaded_duplicate(self):
        # Simulate the workflow exclusion, never the preparer's behavior.
        shutil.rmtree(self.target)

    def cli(self, *args):
        return subprocess.run([sys.executable, evidence.__file__, *args],
                              text=True, capture_output=True)

    def test_round_trip_preserves_roster_bytes_and_independent_files(self):
        value = self.prepare()
        self.assertEqual(value["files"], self.before)
        self.assertEqual(value["duplicate_bytes"], sum(item["size"] for item in self.before.values()))
        self.assertEqual(evidence.inventory(self.target), self.before)
        self.remove_uploaded_duplicate()
        helper = self.captures / evidence.RESTORER
        result = subprocess.run([sys.executable, str(helper), "restore"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(evidence.inventory(self.target), self.before)
        original = (self.reference / "binary.dat").read_bytes()
        (self.target / "binary.dat").write_bytes(b"independent later mutation")
        self.assertEqual((self.reference / "binary.dat").read_bytes(), original)
        self.assertEqual((self.captures / "capture.png").read_bytes(), b"retained render")

    def test_same_size_different_bytes_keep_full_upload(self):
        (self.target / "binary.dat").write_bytes(bytes(reversed(range(256))))
        output = self.captures / "step-output"
        result = self.cli("prepare", "--captures", str(self.captures), "--github-output", str(output))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output.read_text(), "equivalent=false\n")
        self.assertFalse((self.captures / evidence.MANIFEST).exists())
        self.assertEqual((self.target / "binary.dat").read_bytes(), bytes(reversed(range(256))))

    def test_missing_extra_and_empty_projects_cannot_be_deduplicated(self):
        for kind in ("missing", "extra", "empty"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as work:
                captures = Path(work)
                first, second = captures / evidence.REFERENCE, captures / evidence.TARGET
                first.mkdir(parents=True)
                second.mkdir(parents=True)
                if kind != "empty":
                    (first / "expected").write_bytes(b"one")
                if kind == "extra":
                    (second / "expected").write_bytes(b"one")
                    (second / "extra").write_bytes(b"two")
                with self.assertRaises(ValueError):
                    evidence.prepare(captures)
                self.assertFalse((captures / evidence.MANIFEST).exists())

    @unittest.skipIf(os.name == "nt", "POSIX mode metadata")
    def test_mode_difference_keeps_full_upload(self):
        (self.target / "binary.dat").chmod(0o755)
        with self.assertRaisesRegex(ValueError, "differ"):
            self.prepare()

    def test_hidden_import_caches_are_outside_existing_upload_contract(self):
        for root, content in ((self.reference, b"first"), (self.target, b"second")):
            (root / ".godot/imported").mkdir(parents=True)
            (root / ".godot/imported/cache").write_bytes(content)
            (root / "render/.hidden").write_bytes(content)
        value = self.prepare()
        self.assertEqual(value["files"], self.before)
        self.remove_uploaded_duplicate()
        evidence.restore(self.captures)
        self.assertFalse((self.target / ".godot").exists())

    @unittest.skipIf(os.name == "nt", "symlink privileges vary on Windows")
    def test_visible_symlinks_and_dangling_links_keep_full_upload(self):
        for destination in ("binary.dat", "not-present", "render"):
            with self.subTest(destination=destination):
                link = self.target / "link"
                link.symlink_to(destination)
                with self.assertRaisesRegex(ValueError, "unsupported"):
                    self.prepare()
                link.unlink()

    @unittest.skipIf(os.name == "nt", "POSIX named pipe")
    def test_special_file_is_refused_without_opening_it(self):
        os.mkfifo(self.target / "pipe")
        with self.assertRaisesRegex(ValueError, "unsupported"):
            self.prepare()

    def test_changed_file_during_hashing_cannot_enable_exclusion(self):
        original = evidence.digest

        def change_after_read(path):
            result = original(path)
            if path.name == "binary.dat":
                path.write_bytes(b"changed")
            return result

        with patch.object(evidence, "digest", side_effect=change_after_read):
            with self.assertRaisesRegex(ValueError, "changed during"):
                self.prepare()
        self.assertFalse((self.captures / evidence.MANIFEST).exists())

    def test_walk_error_is_not_silently_an_empty_subdirectory(self):
        def unreadable(*args, **kwargs):
            kwargs["onerror"](PermissionError("fixture unreadable directory"))
            yield

        with patch.object(evidence.os, "walk", side_effect=unreadable):
            with self.assertRaises(PermissionError):
                self.prepare()

    @unittest.skipIf(os.name == "nt", "case-sensitive filesystem fixture")
    def test_case_collisions_keep_full_upload(self):
        for root in (self.reference, self.target):
            (root / "BINARY.dat").write_bytes(b"other")
        if (self.target / "binary.dat").read_bytes() == b"other":
            self.skipTest("filesystem is case insensitive")
        with self.assertRaisesRegex(ValueError, "case-insensitive"):
            self.prepare()

    def test_existing_metadata_and_destination_are_preserved(self):
        self.prepare()
        previous = (self.captures / evidence.MANIFEST).read_bytes()
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.prepare()
        with self.assertRaisesRegex(ValueError, "existing reconstruction"):
            evidence.restore(self.captures)
        self.assertEqual((self.captures / evidence.MANIFEST).read_bytes(), previous)
        self.assertEqual(evidence.inventory(self.target), self.before)

    def test_changed_retained_source_is_refused_before_destination_exists(self):
        self.prepare()
        self.remove_uploaded_duplicate()
        (self.reference / "binary.dat").write_bytes(bytes(reversed(range(256))))
        with self.assertRaisesRegex(ValueError, "no longer matches"):
            evidence.restore(self.captures)
        self.assertFalse(self.target.exists())

    def test_failed_copy_does_not_publish_partial_project_and_can_retry(self):
        self.prepare()
        self.remove_uploaded_duplicate()
        with patch.object(evidence.shutil, "copyfile", side_effect=OSError("fixture disk full")):
            with self.assertRaises(OSError):
                evidence.restore(self.captures)
        self.assertFalse(self.target.exists())
        self.assertFalse(list(self.target.parent.glob(".raw-app-restore-*")))
        evidence.restore(self.captures)
        self.assertEqual(evidence.inventory(self.target), self.before)

    @unittest.skipIf(os.name == "nt", "POSIX mode metadata")
    def test_zip_permission_normalization_does_not_prevent_restore(self):
        for root in (self.reference, self.target):
            (root / "binary.dat").chmod(0o755)
        self.prepare()
        self.remove_uploaded_duplicate()
        (self.reference / "binary.dat").chmod(0o644)
        evidence.restore(self.captures)
        self.assertEqual((self.target / "binary.dat").stat().st_mode & 0o777, 0o755)

    def test_tampered_helper_or_invalid_manifest_cannot_restore(self):
        value = self.prepare()
        self.remove_uploaded_duplicate()
        helper = self.captures / evidence.RESTORER
        original = helper.read_bytes()
        helper.write_bytes(original + b"\n# changed\n")
        with self.assertRaisesRegex(ValueError, "helper differs"):
            evidence.restore(self.captures)
        helper.write_bytes(original)
        binary = value["files"].pop("binary.dat")
        for invalid in ("../outside", "C:/outside", "/absolute", "render/./alias"):
            with self.subTest(path=invalid):
                value["files"][invalid] = binary
                (self.captures / evidence.MANIFEST).write_text(json.dumps(value))
                with self.assertRaisesRegex(ValueError, "invalid project-copy path"):
                    evidence.restore(self.captures)
                del value["files"][invalid]
        self.assertFalse(self.target.exists())


if __name__ == "__main__":
    unittest.main()
