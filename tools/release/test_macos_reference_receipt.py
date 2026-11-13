"""Portable fixtures for Mac release identity; no signature or native execution claim."""
from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
import plistlib
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

    def _signing_fixture(self):
        library = self.bundle / receipt.NATIVE_LIBRARY
        descriptor = self.bundle / receipt.NATIVE_DESCRIPTOR
        notice = self.bundle / receipt.NATIVE_LICENSE
        library.write_bytes(struct.pack("<II", 0xFEEDFACF, 0x0100000C) + bytes(56))
        descriptor.write_bytes(receipt.NATIVE_DESCRIPTOR_TEXT.encode())
        notice.write_bytes(b"fixture dependency licence\n")
        self.receipt.unlink()
        with patch.object(receipt, "_source_snapshot", return_value=self.source):
            self.receipt = receipt.create(self.bundle, self.snapshot, self.root)
        files = receipt._files(self.bundle)
        reference = receipt.verify(self.exe, "arm64")
        native = self.bundle.with_name(self.bundle.name + receipt.NATIVE_SUFFIX)
        native.write_bytes(receipt._native_receipt_bytes(self.bundle.name, reference["receipt_sha256"], "f" * 64, files))
        return library

    def _mock_codesign(self, *, app_team="ABCDE12345", library_team="ABCDE12345", flags="0x10000",
                       entitlement=None, diagnostics=b"", adhoc=False, on_entitlements=None):
        def run(command, *, check, capture_output, timeout):
            self.assertEqual(command[0], "/usr/bin/codesign")
            self.assertTrue(check and capture_output)
            self.assertEqual(timeout, 120)
            self.assertEqual(command[command.index("--arch") + 1], "arm64")
            is_library = command[-1] == str(self.bundle / receipt.NATIVE_LIBRARY)
            if "--verify" in command:
                self.assertIn("--strict", command)
                requirement = command[command.index("-R") + 1]
                self.assertIn('certificate leaf[subject.OU] = "ABCDE12345"', requirement)
                self.assertIn("anchor apple generic", requirement)
                self.assertIn("1.2.840.113635.100.6.1.13", requirement)
                self.assertIn("1.2.840.113635.100.6.2.6", requirement)
                self.assertEqual('certificate leaf = H"' + "A" * 40 + '"' in requirement, is_library)
                if adhoc and is_library:
                    raise subprocess.CalledProcessError(1, command)
                return subprocess.CompletedProcess(command, 0, stdout=b"", stderr=b"")
            if "--entitlements" in command:
                self.assertIn("--xml", command)
                if on_entitlements:
                    on_entitlements()
                return subprocess.CompletedProcess(command, 0, stdout=entitlement or b"", stderr=diagnostics)
            team = library_team if is_library else app_team
            name = "Library" if is_library else "App"
            data = (f"Executable=/fixture/{name}\nCodeDirectory v=20500 size=100 flags={flags}(runtime)\n"
                    f"Authority=Developer ID Application: {name} ({team})\n"
                    f"Authority=Developer ID Certification Authority\nTeamIdentifier={team}\n").encode()
            return subprocess.CompletedProcess(command, 0, stdout=b"", stderr=data)
        return run

    def test_native_signing_accepts_matching_team_and_absent_or_false_exception(self):
        self._signing_fixture()
        for entitlements, expected in ((b"", "absent"), (plistlib.dumps({}), "absent"),
                                       (plistlib.dumps({"com.apple.security.cs.disable-library-validation": False}), "false")):
            with self.subTest(expected=expected, length=len(entitlements)), \
                    patch.object(receipt.sys, "platform", "darwin"), \
                    patch.object(receipt.subprocess, "run", side_effect=self._mock_codesign(entitlement=entitlements)) as run:
                result = receipt.verify_native_signing(self.exe, "ABCDE12345", "a" * 40)
                self.assertEqual(result["native_identity"]["kind"], receipt.NATIVE_KIND)
                self.assertFalse(result["disable_library_validation"])
                self.assertEqual(result["disable_library_validation_present"], expected == "false")
                self.assertEqual(result["dylib_certificate_sha1"], "A" * 40)
                self.assertTrue(result["app_hardened_runtime"])
                self.assertFalse(result["get_task_allow"])
                self.assertEqual(result["get_task_allow_keys_present"], [])
                self.assertFalse(result["secure_timestamp_checked"])
                self.assertFalse(result["notarization_checked"])
                self.assertFalse(result["quarantine_checked"])
                self.assertEqual(run.call_count, 5)

    def test_native_signing_refuses_wrong_team_adhoc_and_missing_runtime(self):
        self._signing_fixture()
        for kwargs in ({"library_team": "FGHIJ67890"}, {"app_team": "FGHIJ67890"},
                       {"adhoc": True}, {"flags": "0x0"}):
            with self.subTest(kwargs=kwargs), patch.object(receipt.sys, "platform", "darwin"), \
                    patch.object(receipt.subprocess, "run", side_effect=self._mock_codesign(**kwargs)):
                with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                    receipt.verify_native_signing(self.exe, "ABCDE12345", "A" * 40)

    def test_native_signing_refuses_malformed_or_ambiguous_signature_metadata(self):
        valid = (b"CodeDirectory v=20500 flags=0x10000(runtime)\n"
                 b"Authority=Developer ID Application: Example (ABCDE12345)\n"
                 b"Authority=Developer ID Certification Authority\nTeamIdentifier=ABCDE12345\n")
        receipt._signing_metadata(valid, "ABCDE12345", require_runtime=True)
        for bad in (valid + b"TeamIdentifier=ABCDE12345\n", valid.replace(b" Application:", b" Installer:"),
                    valid.replace(b"Authority=Developer ID Certification Authority\n", b""),
                    valid.replace(b"flags=0x10000", b"flags=invalid"), valid + b"warning: malformed\n",
                    valid + b"\xff"):
            with self.subTest(data=bad), self.assertRaises(ValueError):
                receipt._signing_metadata(bad, "ABCDE12345", require_runtime=True)

    def test_native_signing_refuses_enabled_malformed_or_ambiguous_entitlements(self):
        self._signing_fixture()
        key = "com.apple.security.cs.disable-library-validation"
        duplicate = (b'<?xml version="1.0"?><plist version="1.0"><dict><key>' + key.encode()
                     + b'</key><true/><key>' + key.encode() + b'</key><false/></dict></plist>')
        cases = ((plistlib.dumps({key: True}), b""), (plistlib.dumps({key: "false"}), b""),
                 (plistlib.dumps({key: 0}), b""), (plistlib.dumps({}, fmt=plistlib.FMT_BINARY), b""),
                 (duplicate, b""), (b"<plist>", b""), (b"x" * (1024 * 1024 + 1), b""),
                 (b"", b"warning: invalid entitlements blob\n"))
        for entitlement, diagnostics in cases:
            with self.subTest(data=entitlement[:70], diagnostics=diagnostics), \
                    patch.object(receipt.sys, "platform", "darwin"), \
                    patch.object(receipt.subprocess, "run", side_effect=self._mock_codesign(
                        entitlement=entitlement, diagnostics=diagnostics)):
                with self.assertRaises(ValueError):
                    receipt.verify_native_signing(self.exe, "ABCDE12345", "A" * 40)

    def test_native_signing_refuses_both_get_task_allow_spellings_when_enabled_or_not_boolean(self):
        self._signing_fixture()
        keys = ("get-task-allow", "com.apple.security.get-task-allow")
        for key in keys:
            for value in (True, "false", 0):
                with self.subTest(key=key, value=value), patch.object(receipt.sys, "platform", "darwin"), \
                        patch.object(receipt.subprocess, "run", side_effect=self._mock_codesign(
                            entitlement=plistlib.dumps({key: value}))):
                    with self.assertRaisesRegex(ValueError, "forbidden or malformed entitlement"):
                        receipt.verify_native_signing(self.exe, "ABCDE12345", "A" * 40)
        both_false = plistlib.dumps({key: False for key in keys})
        with patch.object(receipt.sys, "platform", "darwin"), \
                patch.object(receipt.subprocess, "run", side_effect=self._mock_codesign(entitlement=both_false)):
            result = receipt.verify_native_signing(self.exe, "ABCDE12345", "A" * 40)
            self.assertFalse(result["get_task_allow"])
            self.assertEqual(result["get_task_allow_keys_present"], list(keys))

    def test_app_entitlement_helper_enforces_its_own_output_bound(self):
        with self.assertRaisesRegex(ValueError, "oversized"):
            receipt._audit_app_entitlements(b"x" * (1024 * 1024 + 1), b"")
        with self.assertRaisesRegex(ValueError, "oversized"):
            receipt._audit_app_entitlements(b"", b"x" * (1024 * 1024 + 1))

    def test_native_signing_requires_macos_well_formed_pins_and_unchanged_bundle(self):
        library = self._signing_fixture()
        with patch.object(receipt.sys, "platform", "win32"), patch.object(receipt.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "requires macOS"):
                receipt.verify_native_signing(self.exe, "ABCDE12345", "A" * 40)
            run.assert_not_called()
        for team, certificate in (("bad", "A" * 40), ("ABCDE12345", "A" * 39),
                                  ('ABCDE12345" or true', "A" * 40)):
            with self.subTest(team=team, certificate=certificate), patch.object(receipt.sys, "platform", "darwin"), \
                    patch.object(receipt.subprocess, "run") as run:
                with self.assertRaises(ValueError):
                    receipt.verify_native_signing(self.exe, team, certificate)
                run.assert_not_called()
        original = library.read_bytes()
        library.write_bytes(b"changed before audit")
        with patch.object(receipt.sys, "platform", "darwin"), patch.object(receipt.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                receipt.verify_native_signing(self.exe, "ABCDE12345", "A" * 40)
            run.assert_not_called()
        library.write_bytes(original)
        with patch.object(receipt.sys, "platform", "darwin"), patch.object(receipt.subprocess, "run",
                side_effect=self._mock_codesign(on_entitlements=lambda: library.write_bytes(b"changed"))):
            with self.assertRaises(ValueError):
                receipt.verify_native_signing(self.exe, "ABCDE12345", "A" * 40)

    def test_native_signing_cli_is_explicit(self):
        args = ["receipt", "verify-native-signing", str(self.exe), "--team-id", "ABCDE12345",
                "--dylib-certificate-sha1", "A" * 40]
        with patch.object(receipt.sys, "argv", args), patch.object(receipt, "verify_native_signing",
                return_value={"result": "fixture"}) as audit, patch.object(receipt.sys, "stdout", new_callable=io.StringIO):
            receipt.main()
            audit.assert_called_once_with(self.exe, "ABCDE12345", "A" * 40)

    def test_native_receipt_binds_reference_manifest_library_and_descriptor(self):
        library = self.bundle / receipt.NATIVE_LIBRARY
        descriptor = self.bundle / receipt.NATIVE_DESCRIPTOR
        license_file = self.bundle / receipt.NATIVE_LICENSE
        library.write_bytes(struct.pack("<II", 0xFEEDFACF, 0x0100000C) + bytes(56))
        descriptor.write_bytes(receipt.NATIVE_DESCRIPTOR_TEXT.encode())
        license_file.write_bytes(b"fixture dependency licence\n")
        self.receipt.unlink()
        with patch.object(receipt, "_source_snapshot", return_value=self.source):
            self.receipt = receipt.create(self.bundle, self.snapshot, self.root)
        binary = hashlib.sha256(library.read_bytes()).hexdigest()
        probe = hashlib.sha256(self.probe.read_bytes()).hexdigest()
        row = {"platform": "macos", "architecture": "arm64", "backend": "native",
               "backend_version": "openrc-native-kernel-stage-v2", "abi_version": 2,
               "qualification_scope": receipt.NATIVE_SCOPE, "binary_sha256": binary,
               "source_sha256": "1" * 64, "lock_sha256": "2" * 64, "engine_sha256": "3" * 64,
               "engine_version": "fixture", "runtime_os_version": "27.0.1", "runtime_os_build": "26A434",
               "mirrored_sources": {"app/physics/aero.gd": "4" * 64}, "verification": {"oracle": "fixture"}}
        manifest = {"format": receipt.NATIVE_MANIFEST_FORMAT, "platform": "macos", "architecture": "arm64",
                    "engine_version": "fixture", "solver_sha256": "5" * 64,
                    "license_sha256": hashlib.sha256(license_file.read_bytes()).hexdigest(),
                    "native_receipt": {"format": "openrc-native-kernel-receipt", "backend": "native",
                        "backend_version": "openrc-native-kernel-stage-v2", "abi_version": 2,
                        "platforms": {"macos": row}},
                    "qualification_sources": {name: probe if name == "session_probe.gd" else "6" * 64
                                              for name in receipt.NATIVE_DIAGNOSTICS}}
        manifest_path = self.root / "manifest.json"
        manifest_path.write_text(json.dumps(manifest))
        native_receipt = receipt.create_native(self.bundle, manifest_path)
        identity = receipt.verify_native(self.exe, "arm64")
        self.assertEqual(identity["kind"], receipt.NATIVE_KIND)
        self.assertEqual(identity["library_sha256"], binary)
        self.assertEqual(identity["license_sha256"], manifest["license_sha256"])
        self.assertEqual(identity["manifest_sha256"], hashlib.sha256(manifest_path.read_bytes()).hexdigest())
        self.assertNotEqual(identity["sha256"], receipt.verify(self.exe, "arm64")["sha256"])
        with self.assertRaises(ValueError):
            receipt.verify_native(self.exe, "x86_64")
        with self.assertRaises(FileExistsError):
            receipt.create_native(self.bundle, manifest_path)
        original = native_receipt.read_bytes()
        self.assertEqual(len(original.splitlines()), 7)  # Reference/native receipt layout remains unchanged.
        native_receipt.write_bytes(original + b"duplicate\n")
        with self.assertRaises(ValueError):
            receipt.verify_native(self.exe, "arm64")
        native_receipt.write_bytes(original)
        for path in (library, descriptor, license_file, self.receipt):
            before = path.read_bytes()
            path.write_bytes(before + b"tampered")
            with self.assertRaises(ValueError):
                receipt.verify_native(self.exe, "arm64")
            path.unlink()
            with self.assertRaises((OSError, ValueError)):
                receipt.verify_native(self.exe, "arm64")
            path.write_bytes(before)
        expected_descriptor = descriptor.read_bytes()
        old_location = self.bundle / "Contents/Frameworks/openrc_native_kernel_macos.gdextension"
        for defect in ("old-library-path", "old-descriptor-location"):
            native_receipt.unlink()
            if defect == "old-library-path":
                descriptor.write_bytes(expected_descriptor.replace(b"../Frameworks/", b""))
            else:
                descriptor.rename(old_location)
            self.receipt.unlink()
            with patch.object(receipt, "_source_snapshot", return_value=self.source):
                self.receipt = receipt.create(self.bundle, self.snapshot, self.root)
            self.assertEqual(receipt.verify(self.exe, "arm64")["kind"], receipt.KIND)
            with self.assertRaises(ValueError):
                receipt.create_native(self.bundle, manifest_path)
            if defect == "old-library-path":
                descriptor.write_bytes(expected_descriptor)
            else:
                old_location.rename(descriptor)
            self.receipt.unlink()
            with patch.object(receipt, "_source_snapshot", return_value=self.source):
                self.receipt = receipt.create(self.bundle, self.snapshot, self.root)
            native_receipt = receipt.create_native(self.bundle, manifest_path)
            self.assertEqual(receipt.verify_native(self.exe, "arm64")["kind"], receipt.NATIVE_KIND)
        staged_zip = self.root / "native-staged.zip"
        with zipfile.ZipFile(staged_zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in self.bundle.rglob("*"):
                if path.is_file():
                    name = self.bundle.name + "/" + path.relative_to(self.bundle).as_posix()
                    info = zipfile.ZipInfo(name)
                    info.create_system = 3
                    info.external_attr = (stat.S_IFREG | (0o755 if "/MacOS/" in name else 0o644)) << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    archive.writestr(info, path.read_bytes())
        final_zip = self.root / "native-final.zip"
        with patch.object(receipt, "_source_snapshot", return_value=self.source):
            zipped = receipt.package_native_zip(staged_zip, final_zip, self.snapshot, self.root, manifest_path)
        self.assertEqual(zipped["kind"], receipt.NATIVE_KIND)
        self.assertEqual(zipped["manifest_sha256"], identity["manifest_sha256"])
        self.assertEqual(receipt.verify_native_zip(final_zip)["sha256"], zipped["sha256"])
        with self.assertRaises(ValueError):
            receipt.verify_zip(final_zip)  # The reference-only contract stays unchanged.
        rewrite_zip(final_zip, lambda name, data: data + b"tampered" if name.endswith(receipt.NATIVE_SUFFIX) else data)
        with self.assertRaises(ValueError):
            receipt.verify_native_zip(final_zip)
        rewrite_zip(staged_zip, lambda name, data: None if name.endswith("/" + receipt.NATIVE_LICENSE) else data)
        with patch.object(receipt, "_source_snapshot", return_value=self.source), self.assertRaises(ValueError):
            receipt.package_native_zip(staged_zip, self.root / "missing-license.zip", self.snapshot, self.root, manifest_path)
        altered_license = dict(manifest)
        altered_license["license_sha256"] = "0" * 64
        manifest_path.write_text(json.dumps(altered_license))
        native_receipt.unlink()
        with self.assertRaises(ValueError):
            receipt.create_native(self.bundle, manifest_path)
        manifest["native_receipt"]["platforms"]["macos"]["binary_sha256"] = "0" * 64
        manifest_path.write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            receipt.create_native(self.bundle, manifest_path)
        manifest["native_receipt"]["platforms"]["macos"]["binary_sha256"] = binary
        manifest_path.write_text(json.dumps(manifest))
        license_file.write_bytes(b"different dependency notice\n")
        self.receipt.unlink()
        with patch.object(receipt, "_source_snapshot", return_value=self.source):
            self.receipt = receipt.create(self.bundle, self.snapshot, self.root)
        self.assertEqual(receipt.verify(self.exe, "arm64")["kind"], receipt.KIND)
        with self.assertRaises(ValueError):
            receipt.create_native(self.bundle, manifest_path)
        license_file.unlink()
        self.receipt.unlink()
        with patch.object(receipt, "_source_snapshot", return_value=self.source):
            self.receipt = receipt.create(self.bundle, self.snapshot, self.root)
        self.assertEqual(receipt.verify(self.exe, "arm64")["kind"], receipt.KIND)
        with self.assertRaises(ValueError):
            receipt.create_native(self.bundle, manifest_path)

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
        self.receipt.write_bytes(contents.encode("utf-8"))
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
