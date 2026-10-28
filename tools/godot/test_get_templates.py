"""Disposable shell fixtures for the pinned Godot template getter."""
from __future__ import annotations

import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

from tools.godot.test_get_godot import BASH, CHECKSUM, CHECKSUM_KIND, SHELL_PATH, posix_arg
from tools.godot import macos_universal_template as correction


ROOT = Path(__file__).resolve().parents[2]
GETTER = ROOT / "app/get-templates.sh"
ARCHIVE_HASH = (
    "fa53ad6883ae6c78ee9d2f8d14ca4d34852fa21c462d1f4b0f599138d7de40"
    "897cc058f15083a1fa80c7d4b7590b2222dea6f056be7b49e3a584eb64fc30b0b7"
)
ARCHIVE_NAME = "Godot_v4.8-beta1_export_templates.tpz"


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
            for name in ("linux_release.x86_64", "windows_release_x86_64.exe", "macos.zip"):
                z.writestr("templates/" + name, "template " + name)
            z.writestr("templates/version.txt", "4.8.beta1\n")
        source = GETTER.read_text(encoding="utf-8")
        self.assertEqual(source.count(ARCHIVE_HASH), 1)
        self.assertEqual(source.count('DATA_ROOT="$HOME/Library/Application Support/Godot"'), 1)
        self.assertEqual(source.count('DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/godot"'), 1)
        source = source.replace(ARCHIVE_HASH, hashlib.sha512(self.archive.read_bytes()).hexdigest())
        source = source.replace('DATA_ROOT="$HOME/Library/Application Support/Godot"', 'DATA_ROOT="$TEST_DATA_ROOT"')
        source = source.replace('DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/godot"', 'DATA_ROOT="$TEST_DATA_ROOT"')
        (self.app / "get-templates.sh").write_text(source, encoding="utf-8")
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
        self.shim("fixture-python", '''if [ "$1" = -c ]; then [ "${TEST_OLD_PYTHON:-0}" != 1 ]; exit; fi
[ "$2" = --source ] && [ -s "$3" ] && [ "$4" = --project ] || exit 4
printf '%s\\n' "$3" >> "$TEST_HELPER_LOG"''')
        self.env = os.environ.copy()
        self.env.update({
            "PATH": os.pathsep.join([str(self.bin), *SHELL_PATH, self.env.get("PATH", "")]),
            "TEST_REPO_ROOT": posix_arg(self.root), "TEST_DATA_ROOT": posix_arg(self.data),
            "TEST_TEMPLATE_ARCHIVE": posix_arg(self.archive), "TEST_FIXTURE_BIN": posix_arg(self.bin),
            "TEST_GETTER": posix_arg(self.app / "get-templates.sh"), "TEST_CHECKSUM": posix_arg(CHECKSUM),
            "TEST_CHECKSUM_KIND": CHECKSUM_KIND, "OPENRC_GODOT_PYTHON": posix_arg(self.bin / "fixture-python"),
            "TEST_CHECKSUM_LOG": posix_arg(self.root / "checksum.log"),
            "TEST_NETWORK_LOG": posix_arg(self.root / "network.log"),
            "TEST_HELPER_LOG": posix_arg(self.root / "helper.log"),
        })
        self.dest = self.data / "export_templates/4.8.beta1"

    def shim(self, name: str, source: str) -> None:
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\n" + source + "\n", encoding="utf-8")
        path.chmod(0o755)

    def run_getter(self, **extra: str) -> subprocess.CompletedProcess[str]:
        command = 'PATH="$(cd "$TEST_FIXTURE_BIN" && pwd -P):$PATH"; export PATH; source "$TEST_GETTER"'
        return subprocess.run([BASH, "-c", command, posix_arg(self.app / "get-templates.sh")], cwd=self.root, env=self.env | extra,
                              text=True, capture_output=True, timeout=30, check=False)

    def log(self, name: str) -> list[str]:
        path = self.root / name
        return path.read_text(encoding="utf-8").splitlines() if path.exists() else []

    def test_darwin_download_uses_shasum_and_prepares_mac_workaround(self) -> None:
        first = self.run_getter()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertTrue(first.stdout.strip().endswith("/export_templates/4.8.beta1"))
        self.assertEqual(self.log("checksum.log"), ["shasum"])
        self.assertEqual(self.log("network.log"), ["download"])
        self.assertEqual(len(self.log("helper.log")), 1)
        self.assertTrue(self.log("helper.log")[0].endswith("/macos.zip"))
        self.assertTrue((self.dest / "linux_release.x86_64").is_file())
        self.assertTrue((self.dest / "windows_release_x86_64.exe").is_file())
        self.assertFalse((self.root / ".tools" / ARCHIVE_NAME).exists())
        second = self.run_getter(TEST_CURL_FAIL="1")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.log("network.log"), ["download"])
        self.assertEqual(len(self.log("helper.log")), 2)

    def test_corrupt_archive_is_not_extracted(self) -> None:
        result = self.run_getter(TEST_CORRUPT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / ".tools" / ARCHIVE_NAME).read_bytes(), b"corrupt")
        self.assertFalse((self.dest / "macos.zip").exists())
        self.assertEqual(self.log("helper.log"), [])

    def test_old_python_fails_with_actionable_message(self) -> None:
        result = self.run_getter(TEST_OLD_PYTHON="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires Python 3.11+", result.stderr)
        self.assertIn("OPENRC_GODOT_PYTHON", result.stderr)
        self.assertEqual(self.log("helper.log"), [])

    def test_linux_still_uses_sha512sum(self) -> None:
        result = self.run_getter(TEST_SYSTEM="Linux")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log("checksum.log"), ["sha512sum"])
        self.assertEqual(len(self.log("helper.log")), 1)

    def test_real_workaround_is_invoked_and_cached(self) -> None:
        original = io.BytesIO()
        payloads = {name: ("payload " + name).encode() for name in correction.SWAPS}
        with zipfile.ZipFile(original, "w") as mac:
            for name, payload in payloads.items():
                mac.writestr(name, payload)
            mac.writestr("macos_template.app/Contents/Info.plist", b"plist")
        mac_bytes = original.getvalue()
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("templates/linux_release.x86_64", b"linux")
            archive.writestr("templates/windows_release_x86_64.exe", b"windows")
            archive.writestr("templates/macos.zip", mac_bytes)
            archive.writestr("templates/version.txt", "4.8.beta1\n")
        getter = GETTER.read_text(encoding="utf-8").replace(ARCHIVE_HASH, hashlib.sha512(self.archive.read_bytes()).hexdigest())
        getter = getter.replace('DATA_ROOT="$HOME/Library/Application Support/Godot"', 'DATA_ROOT="$TEST_DATA_ROOT"')
        (self.app / "get-templates.sh").write_text(getter, encoding="utf-8")
        helper_dir = self.root / "tools/godot"
        helper_dir.mkdir(parents=True)
        helper_source = (ROOT / "tools/godot/macos_universal_template.py").read_text(encoding="utf-8")
        self.assertEqual(helper_source.count(correction.MACOS_ZIP_SHA512), 1)
        helper_source = helper_source.replace(correction.MACOS_ZIP_SHA512, hashlib.sha512(mac_bytes).hexdigest())
        (helper_dir / "macos_universal_template.py").write_text(helper_source, encoding="utf-8")
        (self.app / "export_presets.cfg").write_text(
            '[preset.0]\nplatform="macOS"\n[preset.0.options]\nbinary_format/architecture="universal"\n'
            'custom_template/debug="res://.godot/export_templates/macos-universal-4.8-beta1.zip"\n'
            'custom_template/release="res://.godot/export_templates/macos-universal-4.8-beta1.zip"\n',
            encoding="utf-8")
        self.shim("fixture-python", 'exec "$TEST_REAL_PYTHON" "$@"')
        first = self.run_getter(TEST_REAL_PYTHON=posix_arg(sys.executable))
        self.assertEqual(first.returncode, 0, first.stderr)
        corrected = self.app / ".godot/export_templates/macos-universal-4.8-beta1.zip"
        self.assertEqual((self.dest / "macos.zip").read_bytes(), mac_bytes)
        with zipfile.ZipFile(corrected) as archive:
            for output_name, original_name in correction.SWAPS.items():
                self.assertEqual(archive.read(output_name), payloads[original_name])
        before = corrected.read_bytes()
        second = self.run_getter(TEST_REAL_PYTHON=posix_arg(sys.executable), TEST_CURL_FAIL="1")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(corrected.read_bytes(), before)
        self.assertEqual(self.log("network.log"), ["download"])


if __name__ == "__main__":
    unittest.main()
