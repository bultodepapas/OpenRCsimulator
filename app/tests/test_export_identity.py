"""Exercise release identity and native receipt gates using disposable fixtures."""
import hashlib
import importlib.util
import itertools
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


class ExportIdentity(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-export-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "app"
        self.app.mkdir()
        source = Path(__file__).parents[1] / "export.sh"
        (self.app / "export.sh").write_text(source.read_text(encoding="utf-8"),
                                             encoding="utf-8", newline="\n")
        (self.app / "project.godot").write_text('config/version="1.2.3"\n', encoding="utf-8")
        scripts = {
            "get-godot.sh": '#!/usr/bin/env bash\nprintf "%s/fake-engine.sh\\n" "$(cd "$(dirname "$0")" && pwd)"\n',
            "get-templates.sh": "#!/usr/bin/env bash\nexit 0\n",
            "fake-engine.sh": '''#!/usr/bin/env bash
python3 - <<'PY'
import json, os
from pathlib import Path
keys = ("DESCRIBE", "COMMIT", "DIRTY", "DATE")
Path(os.environ["PROBE_IDENTITY"]).write_text(json.dumps({key: os.environ["OPENRC_BUILD_" + key] for key in keys}))
PY
if [[ "${PROBE_IMPORT_ERROR:-}" == 1 ]]; then
  echo 'SCRIPT ERROR: simulated import failure'
  exit 0
fi
exit 23
''',
        }
        for name, content in scripts.items():
            path = self.app / name
            path.write_text(content, encoding="utf-8", newline="\n")
            path.chmod(0o755)
        self.git("init", "--quiet")
        self.git("config", "user.email", "export-test@example.invalid")
        self.git("config", "user.name", "Export test")
        self.git("config", "core.autocrlf", "false")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "fixture")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def export(self, *args, **overrides):
        env = os.environ.copy()
        env.pop("GITHUB_REF", None)
        env.update(PROBE_IDENTITY=str(self.root / "identity.json"))
        env.update(overrides)
        return subprocess.run([os.environ.get("OPENRC_TEST_BASH", "bash"), "app/export.sh", *args],
                              cwd=self.root, env=env, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=30)

    def test_triggering_tag_wins_over_another_annotated_tag(self):
        self.git("tag", "-a", "v1.2.3-rc1", "-m", "annotated candidate")
        self.git("tag", "v1.2.3")
        self.assertEqual(self.git("describe", "--tags", "--always"), "v1.2.3-rc1")
        result = self.export(GITHUB_REF="refs/tags/v1.2.3")
        self.assertEqual(result.returncode, 1, result.stdout)  # fake import exits 23
        identity = json.loads((self.root / "identity.json").read_text())
        self.assertEqual(identity["DESCRIBE"], "v1.2.3")
        self.assertEqual(identity["COMMIT"], self.git("rev-parse", "HEAD"))
        self.assertEqual(identity["DIRTY"], "0")

    def test_prerelease_trigger_is_preserved(self):
        self.git("tag", "v1.2.3-rc.2")
        result = self.export(GITHUB_REF="refs/tags/v1.2.3-rc.2")
        self.assertEqual(result.returncode, 1, result.stdout)
        identity = json.loads((self.root / "identity.json").read_text())
        self.assertEqual(identity["DESCRIBE"], "v1.2.3-rc.2")

    def test_branch_exports_retain_git_describe_identity(self):
        self.git("tag", "v1.2.3-rc1")
        (self.app / "project.godot").write_text('config/version="1.2.3"\n# development\n', encoding="utf-8")
        result = self.export(GITHUB_REF="refs/heads/main")
        self.assertEqual(result.returncode, 1, result.stdout)
        identity = json.loads((self.root / "identity.json").read_text())
        self.assertEqual(identity["DESCRIBE"], self.git("describe", "--tags", "--always", "--dirty"))
        self.assertEqual(identity["DIRTY"], "1")

    def test_crlf_project_version_reaches_engine_setup(self):
        (self.app / "project.godot").write_bytes(b'config/version="1.2.3"\r\n')
        result = self.export()
        self.assertEqual(result.returncode, 1, result.stdout)  # fake import exits 23
        self.assertIn("numeric 1.2.3", result.stdout)
        self.assertTrue((self.root / "identity.json").is_file(), result.stdout)

    def test_tagged_release_rejects_untracked_project_resource(self):
        self.git("tag", "v1.2.3")
        (self.app / "scratch scene.gd").write_text("extends Node\n", encoding="utf-8")
        result = self.export(GITHUB_REF="refs/tags/v1.2.3")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("requires a clean working tree", result.stdout)
        self.assertFalse((self.root / "identity.json").exists())

    def test_branch_export_marks_untracked_project_resource_dirty(self):
        self.git("tag", "v1.2.3")
        (self.app / "scratch.gd").write_text("extends Node\n", encoding="utf-8")
        result = self.export(GITHUB_REF="refs/heads/main")
        self.assertEqual(result.returncode, 1, result.stdout)
        identity = json.loads((self.root / "identity.json").read_text())
        self.assertEqual(identity["DESCRIBE"], "v1.2.3-dirty")
        self.assertEqual(identity["DIRTY"], "1")

    def test_ignored_generated_files_and_nonproject_notes_do_not_dirty_identity(self):
        (self.root / ".gitignore").write_text("/app/.godot/\n/app/native/ground_vehicle/\n", encoding="utf-8")
        self.git("add", ".gitignore")
        self.git("commit", "--quiet", "-m", "generated artifact exclusions")
        self.git("tag", "v1.2.3")
        for relative in (".godot/cache", "native/ground_vehicle/build-receipt.json"):
            path = self.app / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture", encoding="utf-8")
        (self.root / "local-notes.md").write_text("outside the project", encoding="utf-8")
        result = self.export(GITHUB_REF="refs/tags/v1.2.3")
        self.assertEqual(result.returncode, 1, result.stdout)  # fake import exits 23
        identity = json.loads((self.root / "identity.json").read_text())
        self.assertEqual(identity["DESCRIBE"], "v1.2.3")
        self.assertEqual(identity["DIRTY"], "0")

    def test_release_rejects_wrong_commit_dirty_tree_and_numeric_mismatch(self):
        self.git("tag", "v1.2.3")
        self.git("tag", "v9.8.7")
        result = self.export(GITHUB_REF="refs/tags/v9.8.7")
        self.assertIn("does not match project.godot", result.stdout)
        (self.app / "project.godot").write_text('config/version="1.2.3"\n# dirty\n', encoding="utf-8")
        result = self.export(GITHUB_REF="refs/tags/v1.2.3")
        self.assertIn("requires a clean working tree", result.stdout)
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "advance HEAD")
        result = self.export(GITHUB_REF="refs/tags/v1.2.3")
        self.assertIn("does not identify HEAD", result.stdout)
        self.assertFalse((self.root / "identity.json").exists())

    def test_malformed_release_tags_and_arguments_fail_before_engine_setup(self):
        for tag in ("vlatest", "v1.2.3garbage", "v1.2.3-", "v1.2.3-rc_2"):
            with self.subTest(tag=tag):
                self.git("tag", tag)
                result = self.export(GITHUB_REF="refs/tags/" + tag)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn("release tag must be", result.stdout)
        result = self.export("1.2.3")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("takes no version argument", result.stdout)
        self.assertFalse((self.root / "identity.json").exists())

    def test_zero_exit_import_error_stops_before_export(self):
        self.git("tag", "v1.2.3")
        result = self.export(PROBE_IMPORT_ERROR="1")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("engine error while importing", result.stdout)
        self.assertNotIn("== export Linux", result.stdout)


class NativeReceiptIdentity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.repo = Path(__file__).resolve().parents[2]
        cls.builder_path = cls.repo / "research/rc-monster-truck/native/build.py"
        spec = importlib.util.spec_from_file_location("native_receipt_test_builder", cls.builder_path)
        if spec is None or spec.loader is None:
            raise RuntimeError("Could not load native receipt builder")
        cls.builder = importlib.util.module_from_spec(spec)
        with mock.patch.object(sys, "dont_write_bytecode", True):
            spec.loader.exec_module(cls.builder)
        cls.lock = cls.builder.locked.load_lock()
        cls.source_hash = cls.builder.source_digest()
        export_source = (cls.repo / "app/export.sh").read_text(encoding="utf-8")
        cls.export_validator = export_source.split("<<'PYRECEIPT'\n", 1)[1].split("\nPYRECEIPT", 1)[0]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-native-receipt-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / "native-cache"
        self.cache.mkdir()
        self.dependency = self.root / "dependency"
        self.dependency.mkdir()
        (self.dependency / "LICENSE.md").write_text("fixture", encoding="utf-8")
        self.binaries = {}
        for platform in ("linux", "windows"):
            binary = self.cache / self.builder.expected_library_name(platform)
            binary.write_bytes((platform + " fixture binary").encode())
            self.binaries[platform] = binary

    def record(self, platform, lock_crlf=False, builder_crlf=False):
        # Independently construct the existing on-disk receipt format.
        lock = self.lock
        section = lock[platform]
        compiler = ({"compiler_version": section["compiler_version"]} if platform == "linux" else {
            key: section[key] for key in ("visual_studio_version", "compiler_toolset", "sdk_version")
        })

        def text_hash(path, crlf):
            data = path.read_bytes().replace(b"\r\n", b"\n")
            if crlf:
                data = data.replace(b"\n", b"\r\n")
            return hashlib.sha256(data).hexdigest()

        toolchain = {
            "lock_sha256": text_hash(self.builder.HERE / "toolchain-lock.json", lock_crlf),
            "platform": platform,
            "architecture": "x86_64",
            "compiler": compiler,
            "floating_point_flags": section["floating_point_flags"],
            "exception_flags": section["exception_flags"],
            "scons_builder_sha256": text_hash(self.builder.SHARED_BUILDER, builder_crlf),
            "godot_cpp_commit": lock["godot_cpp"]["commit"],
        }
        digest = hashlib.sha256(
            (json.dumps(toolchain, sort_keys=True, separators=(",", ":")) + "\n").encode()
        ).hexdigest()
        return {
            "platform": platform,
            "architecture": "x86_64",
            "backend": "native",
            "backend_version": lock["backend_version"],
            "abi_version": lock["native_abi_version"],
            "solver_version": lock["solver_version"],
            "source_sha256": self.source_hash,
            "toolchain_sha256": digest,
            "binary_sha256": hashlib.sha256(self.binaries[platform].read_bytes()).hexdigest(),
            "toolchain": compiler,
            "floating_point_flags": list(section["floating_point_flags"]),
            "exception_flags": list(section["exception_flags"]),
        }

    def write_records(self, records):
        for platform, record in records.items():
            (self.cache / f"build-receipt.{platform}.json").write_text(json.dumps(record), encoding="utf-8")
        receipt = {
            "format": "openrc-ground-vehicle-native-receipt",
            "backend": "native",
            "backend_version": self.lock["backend_version"],
            "abi_version": self.lock["native_abi_version"],
            "solver_version": self.lock["solver_version"],
            "platforms": records,
        }
        path = self.root / "build-receipt.json"
        path.write_text(json.dumps(receipt), encoding="utf-8")
        return path

    def stage(self):
        with mock.patch.object(self.builder, "ROOT", self.root), \
                mock.patch.object(self.builder.locked, "TOOL_ROOT", self.cache), \
                mock.patch.object(self.builder.locked, "ensure_godot_cpp", return_value=self.dependency):
            self.builder.stage_app_native(self.lock)

    def validate_export(self, receipt):
        return subprocess.run(
            [sys.executable, "-B", "-c", self.export_validator, str(receipt), str(self.binaries["linux"]),
             str(self.binaries["windows"]), str(self.builder_path)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
        )

    def test_install_and_export_accept_linux_windows_newline_variants(self):
        variants = list(itertools.product((False, True), repeat=2))
        for index, linux_style in enumerate(variants):
            windows_style = variants[-index - 1]
            with self.subTest(linux=linux_style, windows=windows_style):
                records = {"linux": self.record("linux", *linux_style),
                           "windows": self.record("windows", *windows_style)}
                receipt = self.write_records(records)
                self.stage()
                result = self.validate_export(receipt)
                self.assertEqual(result.returncode, 0, result.stdout)

    def test_install_and_export_reject_wrong_receipt_fields(self):
        invalid = {
            "platform": "other", "architecture": "arm64", "backend": "reference",
            "backend_version": "wrong", "abi_version": True, "solver_version": "wrong",
            "source_sha256": "0" * 64, "toolchain_sha256": "0" * 64,
            "toolchain": {"compiler_version": "wrong"}, "floating_point_flags": ["wrong"],
            "exception_flags": ["wrong"], "binary_sha256": "0" * 64,
        }
        for platform, (key, value) in itertools.product(("linux", "windows"), invalid.items()):
            with self.subTest(platform=platform, field=key):
                records = {name: self.record(name) for name in ("linux", "windows")}
                records[platform][key] = value
                receipt = self.write_records(records)
                with self.assertRaises(SystemExit):
                    self.stage()
                result = self.validate_export(receipt)
                self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_generated_receipts_keep_raw_checkout_digest(self):
        for platform in ("linux", "windows"):
            with self.subTest(platform=platform), mock.patch.object(self.builder.locked, "TOOL_ROOT", self.cache):
                record = self.builder.refresh_receipt(platform, self.binaries[platform], self.lock[platform], self.lock)
                expected = self.builder.toolchain_digest(
                    platform, self.lock[platform], self.lock,
                    self.builder.sha256_file(self.builder.HERE / "toolchain-lock.json"),
                    self.builder.sha256_file(self.builder.SHARED_BUILDER),
                )
                self.assertEqual(record["toolchain_sha256"], expected)
                self.builder.validate_platform_receipt(platform, record, self.lock, self.source_hash)


if __name__ == "__main__":
    unittest.main()
