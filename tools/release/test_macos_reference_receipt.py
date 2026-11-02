"""Portable fixtures for Mac release identity; no signature or native execution claim."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import stat
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

if __package__:
    from . import macos_reference_receipt as receipt
else:
    import macos_reference_receipt as receipt


def fixture_macho():
    """Small universal headers with synthetic ad-hoc flags, not a real signature."""
    slices = []
    for cpu in (0x01000007, 0x0100000C):
        header = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, 16, 0, 0)
        command = struct.pack("<4I", 0x1D, 16, 48, 36)
        blob = struct.pack(">5I", 0xFADE0CC0, 36, 1, 0, 20) + struct.pack(">4I", 0xFADE0C02, 16, 0, 2)
        slices.append(header + command + blob)
    offset = 8 + 2 * 20
    table = b""
    for cpu, data in zip((0x01000007, 0x0100000C), slices):
        table += struct.pack(">5I", cpu, 0, offset, len(data), 0)
        offset += len(data)
    return struct.pack(">2I", 0xCAFEBABE, 2) + table + b"".join(slices)


def write_fixture_zip(path):
    bundle = "OpenRC Simulator.app"
    files = {f"{bundle}/Contents/MacOS/OpenRC Simulator": fixture_macho(),
             f"{bundle}/Contents/Resources/OpenRC Simulator.pck":
                 struct.pack("<4sIIIIIQQI", b"GDPC", 4, 4, 8, 0, 2, 0, 40, 1) + b"fixture pack",
             f"{bundle}/Contents/Frameworks/libfixture.dylib": b"fixture native sidecar",
             f"{bundle}/Contents/_CodeSignature/CodeResources": b"fixture signature resources",
             f"{bundle}/Contents/Info.plist": b"fixture plist"}
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in files.items():
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            mode = 0o755 if "/MacOS/" in name else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    return files


def rewrite_zip(path, transform):
    """Mutate a disposable archive without introducing duplicate member names."""
    with zipfile.ZipFile(path) as archive:
        members = [(info, archive.read(info)) for info in archive.infolist()]
    with zipfile.ZipFile(path, "w") as archive:
        for info, data in members:
            replacement = transform(info.filename, data)
            if replacement is not None:
                archive.writestr(info, replacement)


def set_executable_mode(path, mode):
    with zipfile.ZipFile(path) as archive:
        members = [(info, archive.read(info)) for info in archive.infolist()]
    with zipfile.ZipFile(path, "w") as archive:
        for info, data in members:
            if "/MacOS/" in info.filename:
                info.external_attr = (stat.S_IFREG | mode) << 16
            archive.writestr(info, data)


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

    def test_final_zip_contains_sibling_receipt_and_extracts_to_verified_identity(self):
        source_zip, final_zip = self.root / "godot.zip", self.root / "release.zip"
        original = write_fixture_zip(source_zip)
        source_bytes = source_zip.read_bytes()
        with patch.object(receipt, "_source_snapshot", return_value=self.source):
            identity = receipt.package_zip(source_zip, final_zip, self.snapshot, self.root)
        self.assertEqual(source_zip.read_bytes(), source_bytes)
        self.assertEqual(identity["architectures"], ["arm64", "x86_64"])
        with zipfile.ZipFile(final_zip) as archive:
            name = "OpenRC Simulator.app" + receipt.SUFFIX
            self.assertEqual(set(archive.namelist()), set(original) | {name})
            for member, contents in original.items():
                self.assertEqual(archive.read(member), contents)
            self.assertFalse(name.startswith("OpenRC Simulator.app/"))
            extracted = self.root / "extracted"
            archive.extractall(extracted)
            with zipfile.ZipFile(source_zip) as source:
                for info in source.infolist():
                    final_info = archive.getinfo(info.filename)
                    self.assertEqual((info.external_attr, info.CRC, info.compress_size),
                                     (final_info.external_attr, final_info.CRC, final_info.compress_size))
        executable = extracted / "OpenRC Simulator.app/Contents/MacOS/OpenRC Simulator"
        self.assertEqual(receipt.verify(executable, "arm64")["sha256"], identity["sha256"])

    def test_final_zip_rejects_missing_tampered_receipt_or_bundle_files(self):
        source_zip = self.root / "godot.zip"
        write_fixture_zip(source_zip)
        for target in ("receipt", "pack", "executable", "sidecar", "signature", "missing_receipt", "missing_pack"):
            final_zip = self.root / (target + ".zip")
            with patch.object(receipt, "_source_snapshot", return_value=self.source):
                receipt.package_zip(source_zip, final_zip, self.snapshot, self.root)
            def mutate(name, data):
                selected = ((target.endswith("receipt") and name.endswith(receipt.SUFFIX))
                            or (target == "pack" and name.endswith(".pck"))
                            or (target == "missing_pack" and name.endswith(".pck"))
                            or (target == "executable" and "/MacOS/" in name)
                            or (target == "sidecar" and name.endswith(".dylib"))
                            or (target == "signature" and name.endswith("CodeResources")))
                return (None if target.startswith("missing_") else data + b"tampered") if selected else data
            rewrite_zip(final_zip, mutate)
            with self.subTest(target=target), self.assertRaises(ValueError):
                receipt.verify_zip(final_zip, source=self.source)

    def test_final_zip_rejects_wrong_source_snapshot_and_preexisting_output(self):
        source_zip, final_zip = self.root / "godot.zip", self.root / "release.zip"
        write_fixture_zip(source_zip)
        with patch.object(receipt, "_source_snapshot", return_value=self.source):
            receipt.package_zip(source_zip, final_zip, self.snapshot, self.root)
            with self.assertRaises(FileExistsError):
                receipt.package_zip(source_zip, final_zip, self.snapshot, self.root)
        with self.assertRaisesRegex(ValueError, "source commit"):
            receipt.verify_zip(final_zip, source=dict(self.source, commit="d" * 40))
        with self.assertRaisesRegex(ValueError, "captured release inputs"):
            receipt.verify_zip(final_zip, snapshot_hash="d" * 64)

    def test_zip_rejects_unsafe_members_before_packaging(self):
        for kind in ("traversal", "duplicate", "symlink", "outside", "receipt_inside",
                     "case_collision", "ancestor_collision", "unicode_collision"):
            source_zip, output = self.root / (kind + ".zip"), self.root / (kind + "-out.zip")
            write_fixture_zip(source_zip)
            paths = {"traversal": "../escape", "duplicate": "OpenRC Simulator.app/Contents/Info.plist",
                     "symlink": "OpenRC Simulator.app/Contents/link", "outside": "other.txt",
                     "receipt_inside": "OpenRC Simulator.app/" + "OpenRC Simulator.app" + receipt.SUFFIX,
                     "case_collision": "OpenRC Simulator.app/Contents/INFO.PLIST",
                     "ancestor_collision": "OpenRC Simulator.app/CONTENTS/extra",
                     "unicode_collision": "OpenRC Simulator.app/Contents/Resources/re\u0301sume\u0301.txt"}
            info = zipfile.ZipInfo(paths[kind])
            info.create_system = 3
            info.external_attr = ((stat.S_IFLNK | 0o777) if kind == "symlink" else (stat.S_IFREG | 0o644)) << 16
            with warnings.catch_warnings(), zipfile.ZipFile(source_zip, "a") as archive:
                warnings.simplefilter("ignore", UserWarning)
                if kind == "unicode_collision":
                    archive.writestr("OpenRC Simulator.app/Contents/Resources/r\u00e9sum\u00e9.txt", b"other")
                archive.writestr(info, b"unsafe fixture")
            with self.subTest(kind=kind), patch.object(receipt, "_source_snapshot", return_value=self.source):
                with self.assertRaises(ValueError):
                    receipt.package_zip(source_zip, output, self.snapshot, self.root)
                self.assertFalse(output.exists())

    def test_final_zip_rejects_nonexecutable_app_even_when_contents_match(self):
        source_zip, final_zip = self.root / "godot.zip", self.root / "release.zip"
        write_fixture_zip(source_zip)
        with patch.object(receipt, "_source_snapshot", return_value=self.source):
            receipt.package_zip(source_zip, final_zip, self.snapshot, self.root)
        set_executable_mode(final_zip, 0o644)
        with self.assertRaisesRegex(ValueError, "user execute permission"):
            receipt.verify_zip(final_zip)

    def test_source_drift_during_zip_packaging_refuses_handoff(self):
        source_zip, final_zip = self.root / "godot.zip", self.root / "release.zip"
        write_fixture_zip(source_zip)
        with patch.object(receipt, "_source_snapshot", side_effect=[self.source, dict(self.source, commit="d" * 40)]):
            with self.assertRaisesRegex(ValueError, "inputs changed"):
                receipt.package_zip(source_zip, final_zip, self.snapshot, self.root)


if __name__ == "__main__":
    unittest.main()
