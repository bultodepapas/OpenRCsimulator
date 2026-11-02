"""Disposable shell fixtures for the pinned Godot template getter."""
from __future__ import annotations

import configparser
import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile

from tools.godot.test_get_godot import BASH, CHECKSUM, CHECKSUM_KIND, SHELL_PATH, posix_arg


ROOT = Path(__file__).resolve().parents[2]
GETTER = ROOT / "app/get-templates.sh"
ARCHIVE_HASH = (
    "260de4173d9bb366110dab4f35e42e39f2eace62f29e082d6630bc5c6ea790e"
    "f92f51a9145ffbca2c0ffe97a60da46019c6780d7f88569932cd3237284085c0e"
)
ARCHIVE_NAME = "Godot_v4.8-beta2_export_templates.tpz"
MEMBER_HASHES = {
    "linux_release.x86_64": "c0702f8d2e43f9a8168db71d404b35bc7c3b1d8a69a516b4bee8946b70faf16afd3b046dd8d9c5255da0b7fe71385cff473050dcdc874f4ac72b55868b91bc9a",
    "windows_release_x86_64.exe": "345862e92c5f1d94596ba64e9ad46dcea323280fb2ed760abdc7e0586f71921d07d049d3e5953b493e09c401cf6c7acf97718ec4cc377f028910ba5bd738fe46",
    "macos.zip": "a307324eec2db7db8eef26be10c7c4b91c923c8f91fe9144aee4c5812cd17f4e65e7b03e33021d29f8ff9384fc51a8a9b2d3ea81c461b966dc795edad42a09c7",
    "version.txt": "19e82db58a24133a12f2f9514c6112bfcb9e8a3a4c2247986a24cd47548dc355eb28d10bd496b7f492df8fc711c7a9eae2f18779bc932ef6bf3215f4eec6edf7",
}


@unittest.skipUnless(BASH and CHECKSUM and (shutil.which("unzip") or SHELL_PATH),
                     "Bash, unzip and a SHA-512 tool are required")
class TemplateGetterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="openrc template fixture ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "app"
        self.app.mkdir()
        self.bin = self.root / "fixture-bin"
        self.bin.mkdir()
        self.data = self.root / "isolated Godot data"
        self.archive = self.root / "template-fixture.tpz"
        with zipfile.ZipFile(self.archive, "w") as z:
            linux = zipfile.ZipInfo("templates/linux_release.x86_64")
            linux.create_system = 3
            linux.external_attr = 0o100750 << 16
            z.writestr(linux, "template linux_release.x86_64")
            for name in ("windows_release_x86_64.exe", "macos.zip"):
                z.writestr("templates/" + name, "template " + name)
            z.writestr("templates/version.txt", "4.8.beta2\n")
        self.write_getter()
        self.shim("git", 'printf "%s\\n" "$TEST_REPO_ROOT"')
        self.shim("uname", 'printf "%s\\n" "${TEST_SYSTEM:-Darwin}"')
        self.shim("shasum", '''printf 'shasum\\n' >> "$TEST_CHECKSUM_LOG"
if [ "$TEST_CHECKSUM_KIND" = gnu ]; then shift 2; fi
exec "$TEST_CHECKSUM" "$@"''')
        self.shim("sha512sum", '''printf 'sha512sum\\n' >> "$TEST_CHECKSUM_LOG"
if [ "$TEST_CHECKSUM_KIND" = shasum ]; then exec "$TEST_CHECKSUM" -a 512 "$@"; fi
exec "$TEST_CHECKSUM" "$@"''')
        self.shim("curl", '''while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then output="$2"; break; fi
  shift
done
printf 'download\\n' >> "$TEST_NETWORK_LOG"
if [ "${TEST_CURL_FAIL:-0}" = 1 ]; then exit 28; fi
if [ "${TEST_CORRUPT:-0}" = 1 ]; then printf corrupt > "$output"; exit 0; fi
cp "$TEST_TEMPLATE_ARCHIVE" "$output"''')
        self.shim("fixture-python", '''if [ "$1" = -c ]; then
  [ "${TEST_OLD_PYTHON:-0}" != 1 ] || exit 1
  exec "$TEST_REAL_PYTHON" "$@"
fi
[ "$2" = --source ] && [ -s "$3" ] && [ "$4" = --project ] || exit 4
printf '%s\\n' "$3" >> "$TEST_HELPER_LOG"''')
        self.env = os.environ.copy()
        self.env.update({
            "PATH": os.pathsep.join([str(self.bin), *SHELL_PATH, self.env.get("PATH", "")]),
            "TEST_REPO_ROOT": posix_arg(self.root), "TEST_DATA_ROOT": posix_arg(self.data),
            "TEST_TEMPLATE_ARCHIVE": posix_arg(self.archive), "TEST_FIXTURE_BIN": posix_arg(self.bin),
            "TEST_GETTER": posix_arg(self.app / "get-templates.sh"), "TEST_CHECKSUM": posix_arg(CHECKSUM),
            "TEST_CHECKSUM_KIND": CHECKSUM_KIND, "OPENRC_GODOT_PYTHON": posix_arg(self.bin / "fixture-python"),
            "TEST_REAL_PYTHON": posix_arg(sys.executable),
            "TEST_CHECKSUM_LOG": posix_arg(self.root / "checksum.log"),
            "TEST_NETWORK_LOG": posix_arg(self.root / "network.log"),
            "TEST_HELPER_LOG": posix_arg(self.root / "helper.log"),
        })
        self.dest = self.data / "export_templates/4.8.beta2"

    def write_getter(self) -> None:
        source = GETTER.read_text(encoding="utf-8")
        self.assertEqual(source.count(ARCHIVE_HASH), 1)
        source = source.replace(ARCHIVE_HASH, hashlib.sha512(self.archive.read_bytes()).hexdigest())
        with zipfile.ZipFile(self.archive) as archive:
            for name, official_hash in MEMBER_HASHES.items():
                self.assertEqual(source.count(official_hash), 1)
                source = source.replace(official_hash, hashlib.sha512(archive.read("templates/" + name)).hexdigest())
        for definition in ('DATA_ROOT="$HOME/Library/Application Support/Godot"',
                           'DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/godot"'):
            self.assertEqual(source.count(definition), 1)
            source = source.replace(definition, 'DATA_ROOT="$TEST_DATA_ROOT"')
        (self.app / "get-templates.sh").write_text(source, encoding="utf-8")

    def shim(self, name: str, source: str) -> None:
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\n" + source + "\n", encoding="utf-8")
        path.chmod(0o755)

    def run_getter(self, **extra: str) -> subprocess.CompletedProcess[str]:
        command = 'umask 022; PATH="$(cd "$TEST_FIXTURE_BIN" && pwd -P):$PATH"; export PATH; source "$TEST_GETTER"'
        return subprocess.run([BASH, "-c", command, posix_arg(self.app / "get-templates.sh")], cwd=self.root, env=self.env | extra,
                              text=True, capture_output=True, timeout=30, check=False)

    def log(self, name: str) -> list[str]:
        path = self.root / name
        return path.read_text(encoding="utf-8").splitlines() if path.exists() else []

    def test_darwin_download_uses_shasum_and_verified_cache(self) -> None:
        first = self.run_getter()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertTrue(first.stdout.strip().endswith("/export_templates/4.8.beta2"))
        self.assertEqual(self.log("checksum.log"), ["shasum", "shasum", "shasum"])
        self.assertEqual(self.log("network.log"), ["download"])
        self.assertEqual(self.log("helper.log"), [])
        self.assertTrue((self.dest / "linux_release.x86_64").is_file())
        self.assertTrue((self.dest / "windows_release_x86_64.exe").is_file())
        self.assertFalse((self.root / ".tools" / ARCHIVE_NAME).exists())
        second = self.run_getter(TEST_CURL_FAIL="1")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.log("network.log"), ["download"])
        self.assertEqual(self.log("checksum.log"), ["shasum", "shasum", "shasum", "shasum"])
        self.assertEqual(self.log("helper.log"), [])

    def test_corrupt_archive_is_not_extracted(self) -> None:
        result = self.run_getter(TEST_CORRUPT="1")
        self.assertNotEqual(result.returncode, 0)
        downloads = list((self.root / ".tools").glob(".templates-download.*/" + ARCHIVE_NAME))
        self.assertEqual(len(downloads), 1)
        self.assertEqual(downloads[0].read_bytes(), b"corrupt")
        self.assertFalse((self.dest / "macos.zip").exists())
        self.assertEqual(self.log("helper.log"), [])

    def test_existing_corrupt_archive_is_retained(self) -> None:
        tools = self.root / ".tools"
        tools.mkdir()
        existing = tools / ARCHIVE_NAME
        existing.write_bytes(b"existing corrupt archive")
        result = self.run_getter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("failed SHA-512", result.stderr)
        self.assertEqual(existing.read_bytes(), b"existing corrupt archive")
        self.assertFalse(self.dest.exists())
        self.assertEqual(self.log("network.log"), [])
        self.assertEqual(self.log("helper.log"), [])

    def test_old_python_fails_with_actionable_message(self) -> None:
        result = self.run_getter(TEST_OLD_PYTHON="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires Python 3.11+", result.stderr)
        self.assertIn("OPENRC_GODOT_PYTHON", result.stderr)
        self.assertEqual(self.log("helper.log"), [])
        self.assertEqual(self.log("network.log"), [])
        self.assertFalse(self.dest.exists())

    def test_linux_still_uses_sha512sum(self) -> None:
        result = self.run_getter(TEST_SYSTEM="Linux")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log("checksum.log"), ["sha512sum", "sha512sum", "sha512sum"])
        self.assertEqual(self.log("helper.log"), [])
        if sys.platform.startswith("linux"):
            self.assertEqual(stat.S_IMODE((self.dest / "linux_release.x86_64").stat().st_mode), 0o750)

    def test_changed_or_truncated_cache_is_refused_without_overwrite(self) -> None:
        first = self.run_getter()
        self.assertEqual(first.returncode, 0, first.stderr)
        originals = {name: (self.dest / name).read_bytes() for name in MEMBER_HASHES}
        # An attacker-controlled adjacent receipt must not authorize changed files.
        (self.dest / "linux_release.x86_64.sha512").write_text("forged receipt\n", encoding="utf-8")
        for name, original in originals.items():
            for altered in (b"!" + original[1:], original[:max(1, len(original) // 2)]):
                with self.subTest(name=name, altered=altered):
                    (self.dest / name).write_bytes(altered)
                    result = self.run_getter(TEST_CURL_FAIL="1")
                    self.assertNotEqual(result.returncode, 0, result.stderr)
                    self.assertIn("changed or incomplete", result.stderr)
                    self.assertEqual((self.dest / name).read_bytes(), altered)
                    for other, expected in originals.items():
                        if other != name:
                            self.assertEqual((self.dest / other).read_bytes(), expected)
                    (self.dest / name).write_bytes(original)
        self.assertEqual(self.log("network.log"), ["download"])
        self.assertEqual(self.log("helper.log"), [])

    def test_partial_cache_and_locked_cache_are_not_replaced(self) -> None:
        first = self.run_getter()
        self.assertEqual(first.returncode, 0, first.stderr)
        windows = self.dest / "windows_release_x86_64.exe"
        windows.unlink()
        before = (self.dest / "linux_release.x86_64").read_bytes()
        result = self.run_getter(TEST_CURL_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("changed or incomplete", result.stderr)
        self.assertFalse(windows.exists())
        self.assertEqual((self.dest / "linux_release.x86_64").read_bytes(), before)
        lock = self.dest.parent / ".openrc-4.8.beta2.lock"
        lock.mkdir()
        result = self.run_getter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("locked", result.stderr)
        self.assertEqual(self.log("network.log"), ["download"])
        self.assertEqual(self.log("helper.log"), [])

    def test_verified_archive_with_wrong_member_is_not_published(self) -> None:
        original_hash = hashlib.sha512(self.archive.read_bytes()).hexdigest()
        with zipfile.ZipFile(self.archive) as archive:
            payloads = {name: archive.read(name) for name in archive.namelist()}
        # A separately pinned archive with different contents still cannot
        # authorize a member that differs from the independent member pin.
        payloads["templates/linux_release.x86_64"] = b"unexpected"
        with zipfile.ZipFile(self.archive, "w") as archive:
            for name, payload in payloads.items():
                archive.writestr(name, payload)
        new_hash = hashlib.sha512(self.archive.read_bytes()).hexdigest()
        getter = (self.app / "get-templates.sh").read_text(encoding="utf-8")
        (self.app / "get-templates.sh").write_text(getter.replace(original_hash, new_hash), encoding="utf-8")
        result = self.run_getter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("extraction failed verification", result.stderr)
        self.assertFalse(self.dest.exists())
        self.assertEqual(len(list(self.dest.parent.glob(".openrc-4.8.beta2.*"))), 1)
        self.assertEqual(self.log("helper.log"), [])

    def test_destination_appearing_during_staging_is_preserved(self) -> None:
        self.shim("shasum", '''printf 'shasum\\n' >> "$TEST_CHECKSUM_LOG"
if [ "$TEST_CHECKSUM_KIND" = gnu ]; then shift 2; fi
"$TEST_CHECKSUM" "$@" || exit
if [ "$(wc -l < "$TEST_CHECKSUM_LOG")" -eq 2 ]; then
  mkdir "$TEST_DATA_ROOT/export_templates/4.8.beta2"
  printf 'existing' > "$TEST_DATA_ROOT/export_templates/4.8.beta2/sentinel"
fi''')
        result = self.run_getter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("destination appeared", result.stderr)
        self.assertEqual((self.dest / "sentinel").read_bytes(), b"existing")
        self.assertEqual(self.log("helper.log"), [])

    def test_publication_collision_does_not_overwrite_existing_file(self) -> None:
        self.shim("fixture-python", '''if [ "$1" = -c ]; then
  case "$2" in *shutil.copyfileobj*) printf 'existing' > "$4/linux_release.x86_64" ;; esac
  exec "$TEST_REAL_PYTHON" "$@"
fi
exit 4''')
        result = self.run_getter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("installation incomplete", result.stderr)
        self.assertEqual((self.dest / "linux_release.x86_64").read_bytes(), b"existing")
        self.assertFalse((self.dest / "windows_release_x86_64.exe").exists())
        self.assertEqual(self.log("helper.log"), [])

    def test_official_macos_template_is_installed_unchanged(self) -> None:
        with zipfile.ZipFile(self.archive) as archive:
            official = archive.read("templates/macos.zip")
        first = self.run_getter()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual((self.dest / "macos.zip").read_bytes(), official)
        self.assertFalse((self.app / ".godot").exists())
        second = self.run_getter(TEST_CURL_FAIL="1")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual((self.dest / "macos.zip").read_bytes(), official)
        self.assertEqual(self.log("helper.log"), [])
        self.assertEqual(self.log("network.log"), ["download"])


class CurrentPresetTests(unittest.TestCase):
    def test_universal_macos_preset_uses_the_official_default_template(self) -> None:
        presets = configparser.ConfigParser(interpolation=None)
        presets.read(ROOT / "app/export_presets.cfg", encoding="utf-8")
        matches = [section for section in presets.sections()
                   if presets[section].get("platform") == '"macOS"']
        self.assertEqual(len(matches), 1)
        options = presets[matches[0] + ".options"]
        self.assertEqual(options.get("binary_format/architecture"), '"universal"')
        for mode in ("debug", "release"):
            self.assertIn(options.get("custom_template/" + mode), (None, '""'))


if __name__ == "__main__":
    unittest.main()
