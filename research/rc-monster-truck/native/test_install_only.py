"""Exercise install-only through its CLI using disposable staged artifacts."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[3]
NATIVE = Path("research/rc-monster-truck/native")


class InstallOnly(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="openrc-install-only-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for path in (NATIVE / "build.py", NATIVE / "toolchain-lock.json",
                     Path("research/native-slipstream/build.py"),
                     Path("research/native-slipstream/sources.json")):
            destination = self.root / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / path, destination)
        shutil.copytree(REPO / NATIVE / "src", self.root / NATIVE / "src")
        builder_path = self.root / NATIVE / "build.py"
        spec = importlib.util.spec_from_file_location("install_only_fixture_builder", builder_path)
        self.builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.builder)
        self.lock = self.builder.locked.load_lock()
        self.cache = self.builder.locked.TOOL_ROOT
        self.cache.mkdir(parents=True)
        self.inputs = []
        for platform in ("linux", "windows"):
            binary = self.cache / self.builder.expected_library_name(platform)
            binary.write_bytes((platform + " qualified binary").encode())
            self.builder.refresh_receipt(platform, binary, self.lock[platform], self.lock)
            self.inputs.extend((binary, self.cache / f"build-receipt.{platform}.json"))
        license_path = self.cache / "LICENSE.godot-cpp.md"
        shutil.copyfile(REPO / "research/rc-monster-truck/handling_probe/baseline_sources/app/native/ground_vehicle/LICENSE.godot-cpp.md", license_path)
        self.inputs.append(license_path)

    def invoke(self, *args):
        env = os.environ.copy()
        # The CLI must succeed without git, compilers, SCons or an engine on PATH.
        env["PATH"] = ""
        return subprocess.run([sys.executable, "-B", str(self.root / NATIVE / "build.py"), *args],
                              cwd=self.root, env=env, text=True, capture_output=True, timeout=30)

    def test_installs_exact_qualified_inputs_without_building(self):
        before = {path: path.read_bytes() for path in self.inputs}
        result = self.invoke("--install-only")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, {path: path.read_bytes() for path in self.inputs})
        destination = self.root / "app/native/ground_vehicle"
        for platform in ("linux", "windows"):
            name = self.builder.expected_library_name(platform)
            self.assertEqual((destination / name).read_bytes(), before[self.cache / name])
        self.assertEqual((destination / "LICENSE.godot-cpp.md").read_bytes(), before[self.inputs[-1]])
        receipt = json.loads((destination / "build-receipt.json").read_text())
        for platform in ("linux", "windows"):
            self.assertEqual(receipt["platforms"][platform], json.loads(
                before[self.cache / f"build-receipt.{platform}.json"]))
        self.assertTrue((destination / "openrc_ground_vehicle.gdextension").is_file())

    def test_missing_or_corrupt_inputs_fail_before_staging(self):
        for case in ("missing_binary", "binary_hash", "missing_receipt", "source_hash", "missing_license", "license_hash"):
            with self.subTest(case=case):
                before = {path: path.read_bytes() for path in self.inputs}
                if case == "missing_binary":
                    self.inputs[0].unlink()
                elif case == "binary_hash":
                    self.inputs[0].write_bytes(b"altered")
                elif case == "missing_receipt":
                    self.inputs[3].unlink()
                elif case == "source_hash":
                    receipt = json.loads(self.inputs[3].read_text())
                    receipt["source_sha256"] = "0" * 64
                    self.inputs[3].write_text(json.dumps(receipt))
                elif case == "missing_license":
                    self.inputs[-1].unlink()
                else:
                    self.inputs[-1].write_bytes(b"altered license")
                result = self.invoke("--install-only")
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse((self.root / "app/native/ground_vehicle").exists())
                for path, contents in before.items():
                    path.write_bytes(contents)

    def test_build_options_cannot_be_combined_with_install_only(self):
        for options in (("--install-app",), ("--jobs", "2"), ("--output", "other"),
                        ("--godot", "other"), ("--skip-smoke",), ("--skip-parity",)):
            with self.subTest(options=options):
                result = self.invoke("--install-only", *options)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse((self.root / "app/native/ground_vehicle").exists())


if __name__ == "__main__":
    unittest.main()
