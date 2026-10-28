"""Portable fixtures for the macOS ARM64 branch of app/get-godot.sh.

The fixtures replace only the pinned archive hash in a disposable copy of the
getter and use a fake editor; they do not execute a Mac binary or contact Apple.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[2]
GETTER = ROOT / "app/get-godot.sh"
MAC_ARCHIVE_SHA512 = (
    "eaddf5418249373d6b7c78badc36beaaba1d2ef5972320cf68862d49f3e8c"
    "ce75d3f8219f4b711c88de4656ecca62c833f2d2f91b489456cdd7157d5a81cc08f"
)
VERSION = "4.8.beta1.official.4d10419ca"
NAME = "Godot_v4.8-beta1_macos.arm64"


def shell_tools() -> tuple[str | None, str | None, str | None, list[str]]:
    """Use Git Bash on Windows; regular Bash and a SHA-512 tool elsewhere."""
    if os.name == "nt":
        git = shutil.which("git")
        git_root = Path(git).resolve().parent.parent if git else None
        if not git_root:
            return None, None, None, []
        bash = git_root / "bin/bash.exe"
        unix_bin = git_root / "usr/bin"
        checksum = unix_bin / "sha512sum.exe"
        if bash.is_file() and checksum.is_file() and (unix_bin / "unzip.exe").is_file():
            return str(bash), str(checksum), "gnu", [str(unix_bin), str(git_root / "bin")]
        return None, None, None, []
    bash = shutil.which("bash")
    checksum = shutil.which("shasum")
    if checksum:
        return bash, checksum, "shasum", []
    return bash, shutil.which("sha512sum"), "gnu", []


BASH, CHECKSUM, CHECKSUM_KIND, SHELL_PATH = shell_tools()


def posix_arg(path: Path | str) -> str:
    return str(path).replace("\\", "/")


@unittest.skipUnless(BASH and CHECKSUM and (shutil.which("unzip") or SHELL_PATH),
                     "Bash, unzip and a SHA-512 tool are required")
class MacGetterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="openrc getter fixture ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "app"
        self.app.mkdir()
        self.bin = self.root / "fixture-bin"
        self.bin.mkdir()
        self.fixture_zip = self.root / "official-fixture.zip"
        self.network_log = self.root / "downloads.log"
        with zipfile.ZipFile(self.fixture_zip, "w", zipfile.ZIP_DEFLATED) as z:
            self.add_zip_file(z, "Godot.app/Contents/MacOS/Godot",
                              f'#!/usr/bin/env bash\nprintf "%s\\n" "${{TEST_ENGINE_VERSION:-{VERSION}}}"\n'.encode(), 0o755)
            self.add_zip_file(z, "Godot.app/Contents/Info.plist", b"fixture plist", 0o644)
            self.add_zip_file(z, "Godot.app/Contents/_CodeSignature/CodeResources", b"signature", 0o644)
            self.add_zip_file(z, "Godot.app/Contents/Resources/test.dat", b"resource", 0o644)
        source = GETTER.read_text(encoding="utf-8")
        self.assertEqual(source.count(MAC_ARCHIVE_SHA512), 1)
        fixture_hash = hashlib.sha512(self.fixture_zip.read_bytes()).hexdigest()
        (self.app / "get-godot.sh").write_text(source.replace(MAC_ARCHIVE_SHA512, fixture_hash), encoding="utf-8")
        self.shim("uname", 'if [ "$1" = -s ]; then echo "${TEST_SYSTEM:-Darwin}"; else echo "${TEST_ARCH:-arm64}"; fi')
        self.shim("git", 'printf "%s\\n" "$TEST_REPO_ROOT"')
        self.shim("file", 'printf "%s\\n" "${TEST_FILE_DESCRIPTION:-Mach-O 64-bit executable arm64}"')
        self.shim("shasum", '''if [ "$TEST_CHECKSUM_KIND" = gnu ]; then shift 2; fi
exec "$TEST_CHECKSUM" "$@"''')
        self.shim("curl", '''while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then output="$2"; break; fi
  shift
done
printf 'download\\n' >> "$TEST_NETWORK_LOG"
if [ "${TEST_CURL_FAIL:-0}" = 1 ]; then printf partial > "$output"; exit 28; fi
if [ "${TEST_CORRUPT:-0}" = 1 ]; then printf corrupt > "$output"; exit 0; fi
cp "$TEST_EDITOR_ZIP" "$output"''')
        self.env = os.environ.copy()
        self.env.update({
            "PATH": os.pathsep.join([str(self.bin), *SHELL_PATH, self.env.get("PATH", "")]),
            "TEST_REPO_ROOT": posix_arg(self.root), "TEST_EDITOR_ZIP": posix_arg(self.fixture_zip),
            "TEST_NETWORK_LOG": posix_arg(self.network_log), "TEST_CHECKSUM": posix_arg(CHECKSUM),
            "TEST_CHECKSUM_KIND": CHECKSUM_KIND, "TEST_FIXTURE_BIN": posix_arg(self.bin),
            "TEST_GETTER": posix_arg(self.app / "get-godot.sh"),
        })
        self.cache = self.root / ".tools" / NAME
        self.receipt = self.root / ".tools" / (NAME + ".sha512")
        self.archive = self.root / ".tools" / (NAME + ".zip")
        self.exe = self.cache / "Godot.app/Contents/MacOS/Godot"

    @staticmethod
    def add_zip_file(z: zipfile.ZipFile, name: str, data: bytes, mode: int) -> None:
        info = zipfile.ZipInfo(name)
        info.create_system = 3
        info.external_attr = (0o100000 | mode) << 16
        z.writestr(info, data)

    def shim(self, name: str, source: str) -> None:
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\n" + source + "\n", encoding="utf-8")
        path.chmod(0o755)

    def run_getter(self, **extra: str) -> subprocess.CompletedProcess[str]:
        env = self.env | extra
        command = 'PATH="$(cd "$TEST_FIXTURE_BIN" && pwd -P):$PATH"; export PATH; source "$TEST_GETTER"'
        return subprocess.run([BASH, "-c", command], cwd=self.root,
                              env=env, text=True, capture_output=True, timeout=30, check=False)

    def downloads(self) -> int:
        return len(self.network_log.read_text(encoding="utf-8").splitlines()) if self.network_log.exists() else 0

    def test_install_and_verified_cache_hit(self) -> None:
        first = self.run_getter()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertTrue(first.stdout.strip().endswith("/" + NAME + "/Godot.app/Contents/MacOS/Godot"))
        self.assertTrue(self.exe.is_file())
        self.assertTrue(self.receipt.is_file())
        self.assertTrue(self.archive.is_file())
        self.assertEqual(self.downloads(), 1)
        second = self.run_getter(TEST_CURL_FAIL="1")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(second.stdout.strip(), first.stdout.strip())
        self.assertEqual(self.downloads(), 1)

    def test_corrupt_archive_is_retained_and_never_installed(self) -> None:
        first = self.run_getter(TEST_CORRUPT="1")
        self.assertNotEqual(first.returncode, 0)
        self.assertIn("failed SHA-512", first.stderr)
        self.assertEqual(self.archive.read_bytes(), b"corrupt")
        self.assertFalse(self.cache.exists())
        self.assertFalse(self.receipt.exists())
        second = self.run_getter()
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual(self.archive.read_bytes(), b"corrupt")
        self.assertEqual(self.downloads(), 1)

    def test_interrupted_download_leaves_no_final_archive_and_can_retry(self) -> None:
        first = self.run_getter(TEST_CURL_FAIL="1")
        self.assertNotEqual(first.returncode, 0)
        self.assertFalse(self.archive.exists())
        self.assertFalse(self.cache.exists())
        second = self.run_getter()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.downloads(), 2)

    def test_changed_or_added_bundle_file_fails_closed(self) -> None:
        installed = self.run_getter()
        self.assertEqual(installed.returncode, 0, installed.stderr)
        resource = self.cache / "Godot.app/Contents/Resources/test.dat"
        resource.write_bytes(b"changed")
        failed = self.run_getter()
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("incomplete or changed", failed.stderr)
        self.assertEqual(resource.read_bytes(), b"changed")
        self.assertEqual(self.downloads(), 1)
        resource.write_bytes(b"resource")
        (resource.parent / "unexpected.dat").write_bytes(b"extra")
        self.assertNotEqual(self.run_getter().returncode, 0)
        self.assertEqual(self.downloads(), 1)

    def test_wrong_architecture_is_not_published(self) -> None:
        failed = self.run_getter(TEST_FILE_DESCRIPTION="Mach-O 64-bit executable x86_64")
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("not an ARM64 Mach-O", failed.stderr)
        self.assertFalse(self.cache.exists())
        self.assertFalse(self.receipt.exists())
        self.assertTrue(self.archive.exists())

    def test_wrong_engine_version_is_not_published(self) -> None:
        failed = self.run_getter(TEST_ENGINE_VERSION="unexpected-engine")
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("Unexpected Godot version: unexpected-engine", failed.stderr)
        self.assertFalse(self.cache.exists())
        self.assertFalse(self.receipt.exists())
        self.assertTrue(self.archive.exists())

    def test_existing_lock_is_preserved_and_fails_closed(self) -> None:
        lock = self.root / ".tools" / ("." + NAME + ".lock")
        lock.mkdir(parents=True)
        (lock / "owner").write_text("keep", encoding="utf-8")
        failed = self.run_getter()
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("cache is locked", failed.stderr)
        self.assertEqual((lock / "owner").read_text(encoding="utf-8"), "keep")
        self.assertEqual(self.downloads(), 0)

    def test_incomplete_cache_is_not_replaced(self) -> None:
        self.cache.mkdir(parents=True)
        (self.cache / "do-not-delete").write_text("keep", encoding="utf-8")
        failed = self.run_getter()
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("incomplete or changed", failed.stderr)
        self.assertEqual((self.cache / "do-not-delete").read_text(encoding="utf-8"), "keep")
        self.assertEqual(self.downloads(), 0)

    def test_archive_directory_is_not_overwritten(self) -> None:
        self.archive.mkdir(parents=True)
        (self.archive / "do-not-delete").write_text("keep", encoding="utf-8")
        failed = self.run_getter()
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("archive path is not a regular file", failed.stderr)
        self.assertEqual((self.archive / "do-not-delete").read_text(encoding="utf-8"), "keep")
        self.assertEqual(self.downloads(), 0)

    def test_intel_mac_is_rejected_without_downloading(self) -> None:
        failed = self.run_getter(TEST_ARCH="x86_64")
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("Unsupported Godot downloader host", failed.stderr)
        self.assertEqual(self.downloads(), 0)


if __name__ == "__main__":
    unittest.main()
