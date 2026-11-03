"""Portable fixtures for the macOS ARM64 branch of app/get-godot.sh.

The fixtures replace only the pinned archive hash in a disposable copy of the
getter and use a fake editor; they do not execute a Mac binary or contact Apple.
"""
from __future__ import annotations

import concurrent.futures
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[2]
GETTER = ROOT / "app/get-godot.sh"
MAC_ARCHIVE_SHA512 = (
    "91e14126ad880dc31983b11fe03817771acfb20286a7543f8cde0db1c8c6"
    "3c1845bcf38cb2252318165b65ddd166b362aadf874892555f4eb5e37dbc486b171e"
)
VERSION = "4.8.beta2.official.cafc17a19"
NAME = "Godot_v4.8-beta2_macos.arm64"
OTHER_PLATFORM_PINS = {
    "Linux": {
        "archive": "77470f53a9039cd22837935380230220167e098324e82ec448ee4b1f943f00afc424885f7d6631f385123d7a630a9399b3cc1b0e1dad1a4ac45c6356b3a0aa45",
        "binaries": {"Godot_v4.8-beta2_linux.x86_64": "428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9"},
    },
    "MINGW64_NT-10.0": {
        "archive": "23d6dc2561f95cf296ca88c18d843867dffe978ac23608e3e4eb3fd67c0745cf48a259d51c83650f47e9e42f23154e0f907a6a162ea6b0e47dddbb3d88aa4579",
        "binaries": {
            "Godot_v4.8-beta2_win64.exe": "e83c615fb181c6e1c83f204801e8c73a9340ea500d0da3d7e598f6c4213051de5df8073041c27790838b9e4eff4770c483d7dbb75545da7ad4382c53e23f6a55",
            "Godot_v4.8-beta2_win64_console.exe": "dd05e00ff13faac6b863aa1e4c51599cfaa973c9b8d2e31158d717b499a4ee0b08d46661c0c91215dcce77ce1edfb33595b8af476b2862a47465ec27545962ea",
        },
    },
}


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


class OtherPlatformFixture:
    def __init__(self, test: unittest.TestCase, system: str) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="openrc editor fixture ")
        test.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "app"
        self.app.mkdir()
        self.bin = self.root / "fixture-bin"
        self.bin.mkdir()
        self.network_log = self.root / "downloads.log"
        self.version_log = self.root / "versions.log"
        self.fixture_zip = self.root / "editor-fixture.zip"
        pins = OTHER_PLATFORM_PINS[system]
        self.names = list(pins["binaries"])
        self.file = self.names[0]
        self.exe = self.root / ".tools" / self.names[-1]
        self.receipt = self.root / ".tools" / (self.file + ".sha512")
        self.archive = self.root / ".tools" / (self.file + ".zip")
        payloads = {name: (f'#!/usr/bin/env bash\n# {name}\n'
                           'printf "version\\n" >> "$TEST_VERSION_LOG"\n'
                           'if [ -n "${TEST_CREATE_RECEIPT:-}" ]; then printf sentinel > "$TEST_CREATE_RECEIPT"; fi\n'
                           f'printf "%s\\n" "${{TEST_ENGINE_VERSION:-{VERSION}}}"\n').encode()
                    for name in self.names}
        with zipfile.ZipFile(self.fixture_zip, "w", zipfile.ZIP_DEFLATED) as archive:
            for name, payload in payloads.items():
                MacGetterTests.add_zip_file(archive, name, payload, 0o755)
        source = GETTER.read_text(encoding="utf-8")
        test.assertEqual(source.count(pins["archive"]), 1)
        source = source.replace(pins["archive"], hashlib.sha512(self.fixture_zip.read_bytes()).hexdigest())
        for name, pin in pins["binaries"].items():
            test.assertEqual(source.count(pin), 1)
            source = source.replace(pin, hashlib.sha512(payloads[name]).hexdigest())
        self.getter = self.app / "get-godot.sh"
        self.getter.write_text(source, encoding="utf-8")
        self.shim("uname", 'if [ "$1" = -s ]; then printf "%s\\n" "$TEST_SYSTEM"; else echo x86_64; fi')
        self.shim("git", 'printf "%s\\n" "$TEST_REPO_ROOT"')
        self.shim("sha512sum", '''if [ "$TEST_CHECKSUM_KIND" = shasum ]; then exec "$TEST_CHECKSUM" -a 512 "$@"; fi
exec "$TEST_CHECKSUM" "$@"''')
        self.shim("curl", '''while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then output="$2"; break; fi
  shift
done
printf 'download\\n' >> "$TEST_NETWORK_LOG"
if [ "${TEST_CURL_FAIL:-0}" = 1 ]; then exit 28; fi
cp "$TEST_EDITOR_ZIP" "$output"''')
        self.env = os.environ.copy()
        self.env.update({
            "PATH": os.pathsep.join([str(self.bin), *SHELL_PATH, self.env.get("PATH", "")]),
            "TEST_SYSTEM": system, "TEST_REPO_ROOT": posix_arg(self.root),
            "TEST_EDITOR_ZIP": posix_arg(self.fixture_zip), "TEST_NETWORK_LOG": posix_arg(self.network_log),
            "TEST_VERSION_LOG": posix_arg(self.version_log), "TEST_FIXTURE_BIN": posix_arg(self.bin),
            "TEST_GETTER": posix_arg(self.getter), "TEST_CHECKSUM": posix_arg(CHECKSUM),
            "TEST_CHECKSUM_KIND": CHECKSUM_KIND,
        })

    def shim(self, name: str, source: str) -> None:
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\n" + source + "\n", encoding="utf-8")
        path.chmod(0o755)

    def run(self, **extra: str) -> subprocess.CompletedProcess[str]:
        command = 'PATH="$(cd "$TEST_FIXTURE_BIN" && pwd -P):$PATH"; export PATH; source "$TEST_GETTER"'
        return subprocess.run([BASH, "-c", command], cwd=self.root, env=self.env | extra,
                              text=True, capture_output=True, timeout=30, check=False)

    def log(self, path: Path) -> list[str]:
        return path.read_text(encoding="utf-8").splitlines() if path.exists() else []


@unittest.skipUnless(BASH and CHECKSUM and (shutil.which("unzip") or SHELL_PATH),
                     "Bash, unzip and a SHA-512 tool are required")
class OtherGetterTests(unittest.TestCase):
    def test_cold_and_warm_verify_each_binary_and_version(self) -> None:
        for system in OTHER_PLATFORM_PINS:
            with self.subTest(system=system):
                fixture = OtherPlatformFixture(self, system)
                first = fixture.run()
                self.assertEqual(first.returncode, 0, first.stderr)
                self.assertTrue(fixture.receipt.is_file())
                self.assertFalse(fixture.archive.exists())
                second = fixture.run(TEST_CURL_FAIL="1")
                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertEqual(fixture.log(fixture.network_log), ["download"])
                self.assertEqual(fixture.log(fixture.version_log), ["version", "version", "version"])

    def test_simultaneous_verified_warm_cache_hits_succeed(self) -> None:
        for system in OTHER_PLATFORM_PINS:
            with self.subTest(system=system):
                fixture = OtherPlatformFixture(self, system)
                installed = fixture.run()
                self.assertEqual(installed.returncode, 0, installed.stderr)
                fixture.shim("sha512sum", '''if [ "${TEST_HOLD_CHECKSUM:-0}" = 1 ]; then
  touch "$TEST_REPO_ROOT/checksum-started"
  while [ ! -e "$TEST_REPO_ROOT/checksum-release" ]; do sleep 0.02; done
fi
if [ "$TEST_CHECKSUM_KIND" = shasum ]; then exec "$TEST_CHECKSUM" -a 512 "$@"; fi
exec "$TEST_CHECKSUM" "$@"''')
                with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                    first = pool.submit(fixture.run, TEST_HOLD_CHECKSUM="1", TEST_CURL_FAIL="1")
                    try:
                        deadline = time.monotonic() + 15
                        while not (fixture.root / "checksum-started").exists() and time.monotonic() < deadline:
                            time.sleep(0.02)
                        self.assertTrue((fixture.root / "checksum-started").exists(), "first checksum did not start")
                        second = fixture.run(TEST_CURL_FAIL="1")
                    finally:
                        (fixture.root / "checksum-release").touch()
                    self.assertEqual(first.result().returncode, 0)
                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertEqual(fixture.log(fixture.network_log), ["download"])

    def test_invalid_receipt_type_cannot_use_warm_cache(self) -> None:
        for system in OTHER_PLATFORM_PINS:
            with self.subTest(system=system):
                fixture = OtherPlatformFixture(self, system)
                installed = fixture.run()
                self.assertEqual(installed.returncode, 0, installed.stderr)
                fixture.receipt.unlink()
                fixture.receipt.mkdir()
                result = fixture.run(TEST_CURL_FAIL="1")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cache is incomplete", result.stderr)
                self.assertTrue(fixture.receipt.is_dir())
                fixture.receipt.rmdir()
                try:
                    fixture.receipt.symlink_to(fixture.exe)
                except (NotImplementedError, OSError):
                    continue  # Windows may not permit unprivileged symlink creation.
                result = fixture.run(TEST_CURL_FAIL="1")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cache is incomplete", result.stderr)
                self.assertTrue(fixture.receipt.is_symlink())

    def test_forged_receipt_cannot_authorize_modified_binary(self) -> None:
        for system in OTHER_PLATFORM_PINS:
            with self.subTest(system=system):
                fixture = OtherPlatformFixture(self, system)
                first = fixture.run()
                self.assertEqual(first.returncode, 0, first.stderr)
                for name in fixture.names:
                    target = fixture.root / ".tools" / name
                    original = target.read_bytes()
                    changed = original + b"# unexpected change\n"
                    target.write_bytes(changed)
                    fixture.receipt.write_text("".join(
                        f"{hashlib.sha512((fixture.root / '.tools' / item).read_bytes()).hexdigest()}  {item}\n"
                        for item in fixture.names), encoding="utf-8")
                    result = fixture.run()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("cache is incomplete, changed or has the wrong version", result.stderr)
                    self.assertEqual(target.read_bytes(), changed)
                    target.write_bytes(original)
                self.assertEqual(fixture.log(fixture.network_log), ["download"])
                self.assertEqual(fixture.log(fixture.version_log), ["version", "version"])

    def test_wrong_version_or_missing_binary_is_retained_and_rejected(self) -> None:
        for system in OTHER_PLATFORM_PINS:
            with self.subTest(system=system):
                fixture = OtherPlatformFixture(self, system)
                first = fixture.run()
                self.assertEqual(first.returncode, 0, first.stderr)
                wrong = fixture.run(TEST_ENGINE_VERSION="unexpected-engine")
                self.assertNotEqual(wrong.returncode, 0)
                self.assertIn("wrong version", wrong.stderr)
                self.assertTrue(fixture.exe.is_file())
                (fixture.root / ".tools" / fixture.names[0]).unlink()
                missing = fixture.run()
                self.assertNotEqual(missing.returncode, 0)
                self.assertIn("cache is incomplete", missing.stderr)
                self.assertEqual(fixture.log(fixture.network_log), ["download"])

    def test_valid_binary_with_missing_legacy_receipt_is_accepted(self) -> None:
        for system in OTHER_PLATFORM_PINS:
            with self.subTest(system=system):
                fixture = OtherPlatformFixture(self, system)
                first = fixture.run()
                self.assertEqual(first.returncode, 0, first.stderr)
                fixture.receipt.unlink()
                second = fixture.run(TEST_CURL_FAIL="1")
                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertEqual(fixture.log(fixture.network_log), ["download"])
                self.assertEqual(fixture.log(fixture.version_log), ["version", "version", "version"])

    def test_cold_wrong_version_does_not_create_a_receipt(self) -> None:
        for system in OTHER_PLATFORM_PINS:
            with self.subTest(system=system):
                fixture = OtherPlatformFixture(self, system)
                first = fixture.run(TEST_ENGINE_VERSION="unexpected-engine")
                self.assertNotEqual(first.returncode, 0)
                self.assertIn("failed official SHA-512 or version verification", first.stderr)
                self.assertFalse(fixture.receipt.exists())
                retained = list((fixture.root / ".tools").glob("." + fixture.file + ".*/" + fixture.file + ".zip"))
                self.assertEqual(len(retained), 1)
                shutil.copyfile(retained[0], fixture.archive)
                second = fixture.run(TEST_CURL_FAIL="1")
                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertEqual(fixture.log(fixture.network_log), ["download"])
                self.assertTrue(fixture.archive.is_file())  # A pre-existing archive is never deleted.

    def test_verified_archive_still_requires_the_pinned_executable_members(self) -> None:
        for system in OTHER_PLATFORM_PINS:
            with self.subTest(system=system):
                fixture = OtherPlatformFixture(self, system)
                old_hash = hashlib.sha512(fixture.fixture_zip.read_bytes()).hexdigest()
                with zipfile.ZipFile(fixture.fixture_zip) as archive:
                    payloads = {name: archive.read(name) for name in fixture.names}
                payloads[fixture.names[0]] += b"# unexpected change\n"
                with zipfile.ZipFile(fixture.fixture_zip, "w", zipfile.ZIP_DEFLATED) as archive:
                    for name, payload in payloads.items():
                        MacGetterTests.add_zip_file(archive, name, payload, 0o755)
                new_hash = hashlib.sha512(fixture.fixture_zip.read_bytes()).hexdigest()
                source = fixture.getter.read_text(encoding="utf-8")
                self.assertEqual(source.count(old_hash), 1)
                fixture.getter.write_text(source.replace(old_hash, new_hash), encoding="utf-8")
                result = fixture.run()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("failed official SHA-512 or version verification", result.stderr)
                self.assertFalse(fixture.receipt.exists())
                staged = list((fixture.root / ".tools").glob("." + fixture.file + ".*/" + fixture.names[0]))
                self.assertEqual(len(staged), 1)
                self.assertEqual(staged[0].read_bytes(), payloads[fixture.names[0]])
                self.assertFalse((fixture.root / ".tools" / fixture.names[0]).exists())

    def test_destination_appearing_during_download_is_not_overwritten(self) -> None:
        for system in OTHER_PLATFORM_PINS:
            with self.subTest(system=system):
                fixture = OtherPlatformFixture(self, system)
                fixture.shim("curl", '''while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then output="$2"; break; fi
  shift
done
printf sentinel > "$TEST_REPO_ROOT/.tools/$TEST_COLLISION_BINARY"
cp "$TEST_EDITOR_ZIP" "$output"''')
                result = fixture.run(TEST_COLLISION_BINARY=fixture.names[0])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("destination appeared during installation", result.stderr)
                self.assertEqual((fixture.root / ".tools" / fixture.names[0]).read_bytes(), b"sentinel")
                self.assertFalse(fixture.receipt.exists())

    def test_receipt_appearing_during_installation_is_not_overwritten(self) -> None:
        for system in OTHER_PLATFORM_PINS:
            with self.subTest(system=system):
                fixture = OtherPlatformFixture(self, system)
                result = fixture.run(TEST_CREATE_RECEIPT=posix_arg(fixture.receipt))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("receipt appeared during installation", result.stderr)
                self.assertEqual(fixture.receipt.read_bytes(), b"sentinel")

    def test_existing_lock_is_preserved(self) -> None:
        for system in OTHER_PLATFORM_PINS:
            with self.subTest(system=system):
                fixture = OtherPlatformFixture(self, system)
                lock = fixture.root / ".tools" / ("." + fixture.file + ".lock")
                lock.mkdir(parents=True)
                (lock / "owner").write_text("keep", encoding="utf-8")
                result = fixture.run()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cache is locked", result.stderr)
                self.assertEqual((lock / "owner").read_text(encoding="utf-8"), "keep")
                self.assertEqual(fixture.log(fixture.network_log), [])


if __name__ == "__main__":
    unittest.main()
