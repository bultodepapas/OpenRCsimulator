"""Offline tests for SDK archive, cache, signature and receipt admission."""
from __future__ import annotations

import hashlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock
import zipfile


SPEC = importlib.util.spec_from_file_location("sdk24_under_test", Path(__file__).with_name("sdk24.py"))
assert SPEC is not None and SPEC.loader is not None
sdk = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sdk)


def archive_bytes(files: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for path, content in files.items():
            archive.writestr("fixture/" + path, content)
    return buffer.getvalue()


def file_pins(data: bytes) -> tuple[str, str]:
    return (hashlib.sha256(data).hexdigest(),
            hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest())


def tree_pin(files: dict[str, bytes]) -> str:
    digest = hashlib.sha256()
    for path, data in sorted(files.items()):
        digest.update((path + "\0" + hashlib.sha256(data).hexdigest() + "\n").encode())
    return digest.hexdigest()


class IntakeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="sdk24-test-")
        self.addCleanup(self.temporary.cleanup)
        self.cache = Path(self.temporary.name) / "cache"
        self.cache.mkdir()
        self.files = {
            "api/include/ffx_api.h": b"api header\n",
            "upscalers/include/ffx_upscale.h": b"upscaler header\n",
            "signed/loader.dll": b"signed loader fixture\n",
            "signed/upscaler.dll": b"signed upscaler fixture\n",
            "docs/license.md": b"license fixture\n",
            "3rdpartynotice.md": b"notice fixture\n",
            "samples/sample.cpp": b"sample source\n",
        }
        self.archive = archive_bytes(self.files)
        pinned_names = set(self.files) - {"samples/sample.cpp"}
        replacements = {
            "ZIP_ROOT": "fixture/", "ARCHIVE_NAME": "fixture.zip", "STAGE_NAME": "stage",
            "ARCHIVE_SHA256": hashlib.sha256(self.archive).hexdigest(),
            "TREE_SHA256": tree_pin(self.files), "TREE_FILE_COUNT": len(self.files),
            "TREE_SIZE": sum(map(len, self.files.values())),
            "PINNED_FILES": {name: file_pins(self.files[name]) for name in pinned_names},
            "SIGNED_DLLS": ("signed/loader.dll", "signed/upscaler.dll"),
        }
        self.pin_patch = mock.patch.multiple(sdk, **replacements)
        self.pin_patch.start()
        self.addCleanup(self.pin_patch.stop)
        self.signature_patch = mock.patch.object(sdk, "verify_signature", return_value={"fixture_signature": "valid"})
        self.signature = self.signature_patch.start()
        self.addCleanup(self.signature_patch.stop)

    def cache_archive(self) -> Path:
        path = self.cache / sdk.ARCHIVE_NAME
        path.write_bytes(self.archive)
        return path

    def test_prepare_and_offline_repeat_preserve_complete_layout_and_receipt(self) -> None:
        self.cache_archive()
        with mock.patch.object(sdk, "verify_tag") as verify_tag:
            source, receipt = sdk.prepare(self.cache, offline=True)
            second_source, second_receipt = sdk.prepare(self.cache, offline=True)
        verify_tag.assert_not_called()
        self.assertEqual(source, second_source)
        self.assertEqual(receipt, second_receipt)
        self.assertFalse(receipt["tag_check"]["live"])
        self.assertIsNone(receipt["tag_check"]["checked_utc"])
        self.assertEqual({p.relative_to(source).as_posix(): p.read_bytes() for p in source.rglob("*") if p.is_file()},
                         self.files)
        self.assertEqual(self.signature.call_count, 4)

    def test_cached_archive_mismatch_fails_without_replacement(self) -> None:
        archive = self.cache_archive()
        archive.write_bytes(b"modified cache")
        with self.assertRaisesRegex(RuntimeError, "archive SHA-256 mismatch"):
            sdk.prepare(self.cache, offline=True)
        self.assertEqual(archive.read_bytes(), b"modified cache")
        self.assertFalse((self.cache / sdk.STAGE_NAME).exists())

    def test_download_validates_before_publishing_and_cleans_failed_download(self) -> None:
        with mock.patch.object(sdk.urllib.request, "urlopen", return_value=io.BytesIO(b"wrong bytes")):
            with self.assertRaisesRegex(RuntimeError, "archive SHA-256 mismatch"):
                sdk.fetch(self.cache)
        self.assertEqual(list(self.cache.iterdir()), [])
        with mock.patch.object(sdk.urllib.request, "urlopen", return_value=io.BytesIO(self.archive)):
            result = sdk.fetch(self.cache)
        self.assertEqual(result.read_bytes(), self.archive)
        self.assertEqual(list(self.cache.iterdir()), [result])

    def test_offline_missing_archive_fails_without_network(self) -> None:
        with mock.patch.object(sdk.urllib.request, "urlopen") as download:
            with self.assertRaisesRegex(RuntimeError, "Offline SDK archive is missing"):
                sdk.prepare(self.cache, offline=True)
        download.assert_not_called()

    def test_live_tag_failure_stops_before_using_cached_archive(self) -> None:
        self.cache_archive()
        with mock.patch.object(sdk, "verify_tag", side_effect=RuntimeError("tag moved")):
            with self.assertRaisesRegex(RuntimeError, "tag moved"):
                sdk.prepare(self.cache)
        self.assertFalse((self.cache / sdk.STAGE_NAME).exists())

    def test_moved_tag_is_rejected(self) -> None:
        response = mock.Mock(stdout=f"{'0' * 40}\trefs/tags/{sdk.TAG}\n")
        with mock.patch.object(sdk.subprocess, "run", return_value=response):
            with self.assertRaisesRegex(RuntimeError, "does not resolve"):
                sdk.verify_tag()

    def test_unpinned_file_mutation_is_detected_by_full_tree_hash(self) -> None:
        self.cache_archive()
        source, _ = sdk.prepare(self.cache, offline=True)
        edited = source / "samples/sample.cpp"
        edited.write_bytes(b"sample sourcf\n")  # Same length and not a singled-out file pin.
        with self.assertRaisesRegex(RuntimeError, "staged tree hash"):
            sdk.prepare(self.cache, offline=True)
        self.assertEqual(edited.read_bytes(), b"sample sourcf\n")

    def test_added_build_output_and_missing_receipt_are_rejected(self) -> None:
        self.cache_archive()
        source, _ = sdk.prepare(self.cache, offline=True)
        added = source / "samples/build-output"
        added.write_bytes(b"unknown work")
        with self.assertRaisesRegex(RuntimeError, "file count or size mismatch"):
            sdk.prepare(self.cache, offline=True)
        self.assertEqual(added.read_bytes(), b"unknown work")
        added.unlink()
        (source.parent / "receipt.json").unlink()
        with self.assertRaisesRegex(RuntimeError, "Invalid or missing SDK intake receipt"):
            sdk.prepare(self.cache, offline=True)

    def test_receipt_tampering_and_failed_signature_never_publish_stage(self) -> None:
        self.cache_archive()
        self.signature.side_effect = RuntimeError("bad signature")
        with self.assertRaisesRegex(RuntimeError, "bad signature"):
            sdk.prepare(self.cache, offline=True)
        self.assertFalse((self.cache / sdk.STAGE_NAME).exists())
        self.assertEqual({p.name for p in self.cache.iterdir()}, {sdk.ARCHIVE_NAME})
        self.signature.side_effect = None
        source, _ = sdk.prepare(self.cache, offline=True)
        receipt_path = source.parent / "receipt.json"
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        receipt["archive"]["sha256"] = "fabricated"
        receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "Invalid or missing SDK intake receipt"):
            sdk.prepare(self.cache, offline=True)
        self.assertEqual(json.loads(receipt_path.read_text(encoding="utf-8"))["archive"]["sha256"], "fabricated")

    def test_unsafe_and_duplicate_archive_members_are_rejected(self) -> None:
        cases = ["../outside", "sub/../../outside", "C:/outside", "/outside"]
        for unsafe in cases:
            with self.subTest(unsafe=unsafe):
                raw = archive_bytes({unsafe: b"bad"})
                with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                    with self.assertRaisesRegex(RuntimeError, "Unsafe archive member"):
                        sdk._archive_files(archive)
        # Windows normalizes backslashes while reading; traversal must still fail.
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as package:
            entry = zipfile.ZipInfo("fixture/placeholder")
            entry.filename = "fixture/sub\\..\\..\\outside"
            package.writestr(entry, b"bad")
        with zipfile.ZipFile(io.BytesIO(buffer.getvalue())) as archive:
            with self.assertRaisesRegex(RuntimeError, "Unsafe archive member"):
                sdk._archive_files(archive)
        raw = archive_bytes({"a.txt": b"one", "A.TXT": b"two"})
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            with self.assertRaisesRegex(RuntimeError, "Duplicate archive member"):
                sdk._archive_files(archive)
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as package:
            entry = zipfile.ZipInfo("fixture/link")
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            package.writestr(entry, b"../../outside")
        with zipfile.ZipFile(io.BytesIO(buffer.getvalue())) as archive:
            with self.assertRaisesRegex(RuntimeError, "Special archive member"):
                sdk._archive_files(archive)


class SignatureTests(unittest.TestCase):
    def test_windows_signature_requires_trust_and_expected_certificates(self) -> None:
        valid = {"status": "Valid", "type": "Authenticode", "subject": sdk.SIGNER_SUBJECT,
                 "signer": sdk.SIGNER, "timestamp_signer": sdk.TIMESTAMP_SIGNER}
        path = Path("loader.dll")
        response = mock.Mock(stdout=json.dumps(valid))
        # The subprocess is mocked, so this also runs on non-Windows CI.
        with mock.patch.object(sdk.os, "name", "nt"), mock.patch.object(sdk.subprocess, "run", return_value=response):
            self.assertEqual(sdk.verify_signature(path), valid)
            response.stdout = json.dumps(dict(valid, status="NotTrusted"))
            with self.assertRaisesRegex(RuntimeError, "Invalid or unexpected Authenticode"):
                sdk.verify_signature(path)
            response.stdout = json.dumps(dict(valid, signer="wrong"))
            with self.assertRaisesRegex(RuntimeError, "Invalid or unexpected Authenticode"):
                sdk.verify_signature(path)


if __name__ == "__main__":
    unittest.main()
