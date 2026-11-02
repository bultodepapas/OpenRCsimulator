"""Portable fixtures for Mac release identity; no signature or native execution claim."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import macos_reference_receipt as receipt


class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / "OpenRC Simulator.app"
        self.exe = self.bundle / "Contents/MacOS/OpenRC Simulator"
        self.pack = self.bundle / "Contents/Resources/OpenRC Simulator.pck"
        self.sidecar = self.bundle / "Contents/Frameworks/libfixture.dylib"
        self.signature = self.bundle / "Contents/_CodeSignature/CodeResources"
        for path in (self.exe, self.pack, self.sidecar, self.signature):
            path.parent.mkdir(parents=True, exist_ok=True)
        self.exe.write_bytes(struct.pack("<II", 0xFEEDFACF, 0x0100000C) + bytes(56))
        self.pack.write_bytes(struct.pack("<4sIIIIIQQI", b"GDPC", 4, 4, 8, 0, 2, 0, 40, 1) + b"fixture data")
        self.sidecar.write_bytes(b"actual native sidecar")
        self.signature.write_bytes(b"signed resources")
        self.snapshot = self.root / "inputs.json"
        self.snapshot.write_bytes(b"release input receipt")
        self.probe = self.root / "research/performance/session_probe.gd"
        self.probe.parent.mkdir(parents=True)
        self.probe.write_bytes(b"fixed probe")
        self.source = {"commit": "a" * 40, "tree": "b" * 40, "worktree_sha256": "c" * 64}
        with patch.object(receipt, "_source_snapshot", return_value=self.source):
            self.receipt = receipt.create(self.bundle, self.snapshot, self.root)

    def test_complete_bundle_binds_executable_pack_sidecar_signature_and_source(self):
        identity = receipt.verify(self.exe, "arm64")
        self.assertEqual(identity["kind"], receipt.KIND)
        self.assertEqual(identity["pack_sha256"], hashlib.sha256(self.pack.read_bytes()).hexdigest())
        self.assertEqual(identity["source_receipt_sha256"], hashlib.sha256(self.snapshot.read_bytes()).hexdigest())
        self.assertEqual(identity["source_commit"], self.source["commit"])
        self.assertEqual(identity["probe_sha256"], hashlib.sha256(self.probe.read_bytes()).hexdigest())
        self.assertEqual(identity["sha256"], receipt.verify_for_launch(self.exe)["identities"]["arm64"])
        self.assertFalse(self.receipt.is_relative_to(self.bundle))

    def test_missing_or_changed_bundle_contents_and_receipt_are_refused(self):
        for path in (self.exe, self.pack, self.sidecar, self.signature):
            with self.subTest(path=path):
                original = path.read_bytes()
                path.write_bytes(original + b" drift")
                with self.assertRaises(ValueError):
                    receipt.verify(self.exe, "arm64")
                path.unlink()
                with self.assertRaises((ValueError, OSError)):
                    receipt.verify(self.exe, "arm64")
                path.write_bytes(original)
        self.receipt.unlink()
        with self.assertRaises(ValueError):
            receipt.verify(self.exe, "arm64")

    def test_added_files_wrong_bundle_architecture_and_malformed_receipt_are_refused(self):
        with self.assertRaises(ValueError):
            receipt.verify(self.exe, "x86_64")
        extra = self.bundle / "Contents/Resources/other.pck"
        extra.write_bytes(b"substitution")
        with self.assertRaises(ValueError):
            receipt.verify(self.exe, "arm64")
        extra.unlink()
        moved = self.root / "Other.app"
        self.bundle.rename(moved)
        self.receipt.rename(self.root / (moved.name + receipt.SUFFIX))
        with self.assertRaises(ValueError):
            receipt.verify(moved / self.exe.relative_to(self.bundle), "arm64")
        moved.rename(self.bundle)
        (self.root / (moved.name + receipt.SUFFIX)).rename(self.receipt)
        original = self.receipt.read_text()
        for altered in (original.replace("source_tree\t", "source_tree\tbroken", 1),
                        original + original.splitlines()[-1] + "\n", original.replace("Contents/Resources/OpenRC Simulator.pck", "../escape", 1)):
            self.receipt.write_text(altered)
            with self.assertRaises(ValueError):
                receipt.verify(self.exe, "arm64")
        self.receipt.write_text(original)

    def test_receipt_or_source_receipt_drift_changes_identity(self):
        before = receipt.verify(self.exe, "arm64")["sha256"]
        contents = self.receipt.read_text().replace("source_receipt_sha256\t" + hashlib.sha256(self.snapshot.read_bytes()).hexdigest(),
                                                    "source_receipt_sha256\t" + "d" * 64)
        self.receipt.write_text(contents)
        self.assertNotEqual(before, receipt.verify(self.exe, "arm64")["sha256"])
        # A receipt proves consistency, not the trustworthiness of its declared origin.

    def test_symlinks_and_overwrite_are_refused(self):
        with patch.object(receipt, "_source_snapshot", return_value=self.source):
            with self.assertRaises(FileExistsError):
                receipt.create(self.bundle, self.snapshot, self.root)
        link = self.bundle / "Contents/Resources/alias"
        try:
            link.symlink_to(self.pack.name)
        except OSError:
            self.skipTest("symlinks unavailable")
        with self.assertRaises(ValueError):
            receipt.verify(self.exe, "arm64")

    def test_source_or_bundle_change_during_receipt_creation_is_refused(self):
        self.receipt.unlink()
        with patch.object(receipt, "_source_snapshot", side_effect=[self.source, dict(self.source, commit="d" * 40)]):
            with self.assertRaises(ValueError):
                receipt.create(self.bundle, self.snapshot, self.root)
        self.assertFalse(self.receipt.exists())

    def test_wrong_name_truncated_encrypted_and_sparse_packs_are_refused(self):
        original = self.pack.read_bytes()
        relative_exe = self.exe.relative_to(self.bundle).as_posix()
        relative_pack = self.pack.relative_to(self.bundle).as_posix()
        with self.assertRaises(ValueError):
            receipt._check_pack(self.bundle, relative_exe, "Contents/Resources/other.pck")
        for pack in (b"GDPC", original[:20] + struct.pack("<I", 1) + original[24:],
                     original[:20] + struct.pack("<I", 4) + original[24:]):
            with self.subTest(pack=pack):
                self.pack.write_bytes(pack)
                with self.assertRaises(ValueError):
                    receipt._check_pack(self.bundle, relative_exe, relative_pack)
        self.pack.write_bytes(original)

    def test_mac_only_source_capture_needs_no_native_kernel_installation(self):
        app = self.root / "app"
        app.mkdir()
        (app / "project.godot").write_text("fixture project")
        editor, template = self.root / "editor", self.root / "macos-template.zip"
        editor.write_bytes(b"editor")
        template.write_bytes(b"template")
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(["git", "-C", str(self.root), "add", "app", "research"], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                        "commit", "-qm", "fixture"], check=True)
        captured = receipt.capture_source(self.root, editor, template)
        source_receipt = self.root / "mac-inputs.json"
        source_receipt.write_text(json.dumps(captured))
        self.assertEqual(receipt._source_snapshot(source_receipt, self.root), captured["source"])
        self.assertFalse((self.root / "app/native/kernel").exists())
        self.receipt.unlink()
        self.assertEqual(receipt.create(self.bundle, source_receipt, self.root), self.receipt)
        self.assertEqual(receipt.verify(self.exe, "arm64")["source_receipt_sha256"], receipt.digest(source_receipt))
        template.write_bytes(b"changed template")
        with self.assertRaises(ValueError):
            receipt._source_snapshot(source_receipt, self.root)
        template.write_bytes(b"template")
        self.probe.write_bytes(b"changed source")
        with self.assertRaises(ValueError):
            receipt._source_snapshot(source_receipt, self.root)


if __name__ == "__main__":
    unittest.main()
