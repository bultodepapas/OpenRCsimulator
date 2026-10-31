"""Exercise local preflight scope and failure handling without running the full suite."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LocalPreflight(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-local-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("tools/ci", "app/tests", "prototypes/stage0/three", "bin"):
            (self.root / name).mkdir(parents=True)
        (self.root / ".nvmrc").write_text("24\n")
        shutil.copyfile(ROOT / "tools/ci/check-local.sh", self.root / "tools/ci/check-local.sh")
        self.log = self.root / "calls"
        fake = '''#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >> "$CALL_LOG"
case "${0##*/} $*" in *"${FAIL_MATCH:-__not_a_command__}"*) exit 9;; esac
exit 0
'''
        for name in ("python3", "bash", "git", "timeout", "zip", "unzip", "readelf", "g++", "xvfb-run", "npm"):
            path = self.root / "bin" / name
            path.write_text(fake, encoding="utf-8", newline="\n")
            path.chmod(0o755)
        node = self.root / "bin/node"
        node.write_text('#!/bin/bash\nif [[ "$1" == --version ]]; then printf "v24.0.0\\n"; exit; fi\n' + fake.removeprefix('#!/bin/bash\n'))
        node.chmod(0o755)
        getter = self.root / "app/get-godot.sh"
        getter.write_text('#!/bin/bash\nprintf "/fake/godot\\n"\n', encoding="utf-8")
        getter.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(PATH=str(self.root / "bin") + os.pathsep + self.env["PATH"], CALL_LOG=str(self.log))

    def run_mode(self, mode, **overrides):
        env = self.env.copy()
        env.update(overrides)
        return subprocess.run(["/bin/bash", "tools/ci/check-local.sh", mode], cwd=self.root, env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20)

    def test_quick_is_partial_and_every_fixture_failure_is_fatal(self):
        fixtures = ["app/tests/test_ci_partitions.py", "app/tests/test_export_identity.py",
                    "-m unittest discover -s tools/ci -p test_*.py"]
        result = self.run_mode("quick")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Quick is partial", result.stdout)
        self.assertIn("Windows ground-native CI", result.stdout)
        self.assertEqual(self.log.read_text().splitlines(), ["python3 " + name for name in fixtures])
        for name in fixtures:
            with self.subTest(fixture=name):
                result = self.run_mode("quick", FAIL_MATCH=name)
                self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_full_invokes_app_schema_visual_and_prototype_and_lists_gaps(self):
        result = self.run_mode("full")
        self.assertEqual(result.returncode, 0, result.stdout)
        calls = self.log.read_text()
        for command in ("research/aircraft-data/schema/check.py", "research/aircraft-data/schema/test_contract.py",
                        "research/helicopter/hx700/test_schema.py", "research/aircraft-standardization/test_schema_v2.py",
                        "research/test-tools.sh", "test_resource*.py", "research/native-kernel/test_trajectory.gd",
                        "research/native-kernel/test_fleet.gd", "app/test.sh", "app/capture.sh",
                        "site/build_locales.py --check", "site/test_locales.py", "node --test site/test_downloads.cjs",
                        "tools/analytics/test_github_history.py", "npm ci", "npm run typecheck", "npm test",
                        "npm run capture", "npm run e2e"):
            self.assertIn(command, calls)
        self.assertIn("full NK-3 native CI qualification", result.stdout)
        self.assertIn("Windows ground-native CI", result.stdout)
        self.assertIn("Package/export checks are also not run", result.stdout)
        for command in ("research/test-tools.sh", "app/test.sh", "app/capture.sh", "npm run e2e"):
            with self.subTest(command=command):
                result = self.run_mode("full", FAIL_MATCH=command)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertNotIn("checks completed", result.stdout)

    def test_release_refuses_missing_native_receipts_before_quick(self):
        result = self.run_mode("release")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("ground_vehicle/build-receipt.json", result.stdout)
        self.assertFalse(self.log.exists())
        ground = self.root / "app/native/ground_vehicle"
        ground.mkdir(parents=True)
        (ground / "build-receipt.json").write_text("{}")
        result = self.run_mode("release")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("kernel/build-receipt.json", result.stdout)
        self.assertFalse(self.log.exists())

    @unittest.skipUnless(Path("/usr/bin/python3").exists(), "Linux Python required")
    def test_release_refuses_absent_platform_rows_and_invalid_nk3_receipt(self):
        # Minimal builder stubs let the real shell's receipt orchestration run in a disposable tree.
        python = self.root / "bin/python3"
        python.write_text('#!/bin/bash\nexec /usr/bin/python3 "$@"\n')
        python.chmod(0o755)
        base = self.root / "research/rc-monster-truck/native"
        base.mkdir(parents=True)
        (base / "build.py").write_text('''from pathlib import Path
HERE = Path(__file__).resolve().parent
def source_digest(): return "source"
def validate_platform_receipt(platform, row, lock, digest):
    if not isinstance(row, dict) or row.get("platform") != platform: raise SystemExit("missing " + platform)
def sha256_file(path): return path.read_text()
def expected_library_name(platform): return platform + ".bin"
''')
        (base / "toolchain-lock.json").write_text("{}")
        kernel = self.root / "research/native-kernel"
        kernel.mkdir(parents=True)
        (kernel / "package.py").write_text('def verified_install(): raise ValueError("invalid NK-3 receipt")\n')
        ground = self.root / "app/native/ground_vehicle"
        ground.mkdir(parents=True)
        nk3 = self.root / "app/native/kernel"
        nk3.mkdir(parents=True)
        (nk3 / "build-receipt.json").write_text("{}")
        receipt = {"format": "openrc-ground-vehicle-native-receipt", "platforms": {}}
        (ground / "build-receipt.json").write_text(json.dumps(receipt))
        self.assertIn("missing linux", self.run_mode("release").stdout)
        receipt["platforms"]["linux"] = {"platform": "linux", "binary_sha256": "valid"}
        (ground / "linux.bin").write_text("valid")
        (ground / "build-receipt.json").write_text(json.dumps(receipt))
        self.assertIn("missing windows", self.run_mode("release").stdout)
        receipt["platforms"]["windows"] = {"platform": "windows", "binary_sha256": "valid"}
        (ground / "windows.bin").write_text("valid")
        (ground / "build-receipt.json").write_text(json.dumps(receipt))
        result = self.run_mode("release")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("invalid NK-3 receipt", result.stdout)
        self.assertNotIn("quick checks", result.stdout)


if __name__ == "__main__":
    unittest.main()
