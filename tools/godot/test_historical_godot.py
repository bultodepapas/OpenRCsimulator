"""Failure controls for the fixed-brake historical editor cache."""
from __future__ import annotations

import concurrent.futures
import hashlib
import io
from pathlib import Path
import tempfile
from threading import Event
import unittest
from unittest import mock
import zipfile

import get_historical_godot as getter


def digest(data: bytes) -> str:
    return hashlib.sha512(data).hexdigest()


def archive_bytes(files: dict[str, bytes]) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        for name, contents in files.items():
            archive.writestr(name, contents)
    return output.getvalue()


class HistoricalEditorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.tools = Path(self.tmp.name) / ".tools"
        self.files = {"editor": b"editor bytes"}
        self.archive = archive_bytes(self.files)
        self.editor = getter.Editor("editor.zip", digest(self.archive), "editor",
                                    {name: digest(data) for name, data in self.files.items()})
        self.version = mock.patch.object(getter.subprocess, "check_output", return_value=getter.HISTORICAL_VERSION)
        self.version.start()
        self.addCleanup(self.version.stop)

    def install(self, archive: bytes | None = None) -> Path:
        with mock.patch.object(getter.urllib.request, "urlopen", return_value=io.BytesIO(archive or self.archive)):
            return getter.ensure_editor(self.tools, self.editor)

    def test_verified_install_then_offline_cache_and_refuse_changed_file(self) -> None:
        installed = self.install()
        self.assertEqual(installed.read_bytes(), self.files["editor"])
        with mock.patch.object(getter.urllib.request, "urlopen", side_effect=AssertionError("unexpected network")):
            self.assertEqual(getter.ensure_editor(self.tools, self.editor), installed)
            installed.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "incomplete or changed"):
                getter.ensure_editor(self.tools, self.editor)
        self.assertEqual(installed.read_bytes(), b"changed")

    def test_simultaneous_verified_warm_cache_hits_succeed(self) -> None:
        installed = self.install()
        original_verify = getter.verify_editor
        started, release = Event(), Event()

        def hold_first(directory: Path, editor: getter.Editor) -> Path:
            if not started.is_set():
                started.set()
                if not release.wait(10):
                    raise AssertionError("first verification was not released")
            return original_verify(directory, editor)

        with mock.patch.object(getter, "verify_editor", side_effect=hold_first):
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                first = pool.submit(getter.ensure_editor, self.tools, self.editor)
                try:
                    self.assertTrue(started.wait(10), "first verification did not start")
                    second = pool.submit(getter.ensure_editor, self.tools, self.editor).result(timeout=5)
                finally:
                    release.set()
                self.assertEqual(first.result(), installed)
                self.assertEqual(second, installed)

    def test_bad_archive_or_unexpected_members_install_nothing(self) -> None:
        with self.assertRaisesRegex(ValueError, "SHA-512"):
            self.install(b"bad archive")
        self.assertFalse((self.tools / "editor").exists())
        extra = archive_bytes({**self.files, "../escape": b"unexpected"})
        self.editor = getter.Editor("editor.zip", digest(extra), "editor", self.editor.binaries)
        with self.assertRaisesRegex(ValueError, "contents differ"):
            self.install(extra)
        self.assertFalse((self.tools / "editor").exists())
        self.assertFalse((self.tools.parent / "escape").exists())

    def test_incomplete_pair_is_preserved_and_refused_without_network(self) -> None:
        self.tools.mkdir()
        (self.tools / "editor").write_bytes(self.files["editor"])
        self.editor = getter.Editor("editor.zip", digest(self.archive), "editor",
                                    {"editor": digest(self.files["editor"]), "console": digest(b"console")})
        with mock.patch.object(getter.urllib.request, "urlopen", side_effect=AssertionError("unexpected network")):
            with self.assertRaisesRegex(ValueError, "incomplete or changed"):
                getter.ensure_editor(self.tools, self.editor)
        self.assertEqual((self.tools / "editor").read_bytes(), self.files["editor"])
        self.assertFalse((self.tools / "console").exists())

    def test_wrong_version_and_existing_lock_fail_closed(self) -> None:
        with mock.patch.object(getter.subprocess, "check_output", return_value="different"):
            with self.assertRaisesRegex(ValueError, "version differs"):
                self.install()
        self.assertFalse((self.tools / "editor").exists())
        (self.tools / ".fixed-brake-beta1.lock").mkdir()
        with self.assertRaisesRegex(ValueError, "cache is locked"):
            self.install()
        self.assertTrue((self.tools / ".fixed-brake-beta1.lock").is_dir())


if __name__ == "__main__":
    unittest.main()
