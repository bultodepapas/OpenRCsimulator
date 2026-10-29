"""Exercise release identity and native receipt gates using disposable fixtures."""
import hashlib
import importlib.util
import itertools
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock
import zipfile


@unittest.skipUnless(sys.platform.startswith("linux"), "export requires a Linux host; use WSL on Windows")
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
import json, os, time
from pathlib import Path
keys = ("DESCRIBE", "COMMIT", "DIRTY", "DATE")
Path(os.environ["PROBE_IDENTITY"]).write_text(json.dumps({key: os.environ["OPENRC_BUILD_" + key] for key in keys}))
if os.environ.get("PROBE_READY"):
    Path(os.environ["PROBE_READY"]).touch()
    deadline = time.monotonic() + 20
    while not Path(os.environ["PROBE_RELEASE"]).exists():
        if time.monotonic() > deadline:
            raise SystemExit("fixture release signal timed out")
        time.sleep(0.01)
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

    def export_env(self, **overrides):
        env = os.environ.copy()
        env.pop("GITHUB_REF", None)
        env.pop("GITHUB_OUTPUT", None)
        env.update(PROBE_IDENTITY=str(self.root / "identity.json"))
        env.update(overrides)
        return env

    def export(self, *args, **overrides):
        return subprocess.run([os.environ.get("OPENRC_TEST_BASH", "bash"), "app/export.sh", *args],
                              cwd=self.root, env=self.export_env(**overrides), text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=30)

    def output_path(self, result):
        match = re.search(r"^== export output: (.+)$", result.stdout, re.MULTILINE)
        self.assertIsNotNone(match, result.stdout)
        return Path(match.group(1))

    def test_default_runs_preserve_previous_outputs_even_on_failure(self):
        dist = self.root / "dist"
        dist.mkdir()
        sentinel = dist / "previous-release.zip"
        sentinel.write_bytes(b"keep the prior verified release")
        runs = [self.export(), self.export()]
        outputs = [self.output_path(result) for result in runs]
        self.assertNotEqual(outputs[0], outputs[1])
        for result, output in zip(runs, outputs):
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertEqual(output.parent, dist)
            self.assertTrue((output / "linux").is_dir())
            self.assertIn("partial output retained", result.stdout)
        self.assertEqual(sentinel.read_bytes(), b"keep the prior verified release")

    def test_explicit_output_rejects_existing_paths_and_symlinks(self):
        existing = self.root / "existing"
        existing.mkdir()
        sentinel = existing / "previous.zip"
        sentinel.write_bytes(b"keep")
        existing_file = self.root / "existing-file"
        existing_file.write_bytes(b"keep file")
        dangling = self.root / "dangling"
        dangling.symlink_to(self.root / "absent-target", target_is_directory=True)
        for path in (existing, existing_file, dangling):
            with self.subTest(path=path.name):
                result = self.export("--output-dir", str(path))
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("output already exists", result.stdout)
                self.assertFalse((self.root / "identity.json").exists())
        self.assertEqual(sentinel.read_bytes(), b"keep")
        self.assertEqual(existing_file.read_bytes(), b"keep file")
        self.assertTrue(dangling.is_symlink())
        self.assertFalse((self.root / "absent-target").exists())

    def test_explicit_spaced_output_is_retained_without_success_handoff(self):
        output = self.root / "new parent" / "export with spaces"
        handoff = self.root / "github-output"
        handoff.write_text("other_step=value\n", encoding="utf-8")
        result = self.export("--output-dir", str(output), GITHUB_OUTPUT=str(handoff))
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.output_path(result), output)
        self.assertTrue((output / "windows").is_dir())
        self.assertEqual(handoff.read_text(), "other_step=value\n")

    def test_output_cannot_become_a_project_resource_or_git_metadata(self):
        alias = self.root / "project-alias"
        alias.symlink_to(self.app, target_is_directory=True)
        for output in (self.app / "export", alias / "export", self.root / ".git" / "export"):
            with self.subTest(path=str(output)):
                result = self.export("--output-dir", str(output))
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("outside app/ and Git metadata", result.stdout)
                self.assertFalse(output.exists())
                self.assertFalse((self.root / "identity.json").exists())

    def test_same_checkout_export_is_locked_before_engine_work(self):
        ready, release = self.root / "ready", self.root / "release"
        first = subprocess.Popen(
            [os.environ.get("OPENRC_TEST_BASH", "bash"), "app/export.sh"], cwd=self.root,
            env=self.export_env(PROBE_READY=str(ready), PROBE_RELEASE=str(release)),
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        try:
            deadline = time.monotonic() + 10
            while not ready.exists() and first.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists(), "first export did not enter the import fixture")
            second = self.export()
            self.assertNotEqual(second.returncode, 0, second.stdout)
            self.assertIn("another export is using this checkout", second.stdout)
            self.assertNotIn("== export output:", second.stdout)
        finally:
            release.touch()
            stdout, _ = first.communicate(timeout=25)
        self.assertNotEqual(first.returncode, 0, stdout)
        # The advisory lock releases after failure; a subsequent export reaches import.
        third = self.export()
        self.assertIn("== import", third.stdout)
        self.assertNotIn("another export", third.stdout)

    def test_symlinked_checkout_cannot_export_into_its_project(self):
        alias = self.root / "checkout-alias"
        alias.symlink_to(self.root, target_is_directory=True)
        output = self.app / "new-output"
        result = subprocess.run(
            [os.environ.get("OPENRC_TEST_BASH", "bash"), str(alias / "app/export.sh"),
             "--output-dir", str(output)], cwd=self.root, env=self.export_env(), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
        )
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("outside app/ and Git metadata", result.stdout)
        self.assertFalse(output.exists())
        self.assertFalse((self.root / "identity.json").exists())

    def test_worktree_cannot_export_into_shared_git_metadata(self):
        worktree = self.root / "worktree"
        self.git("worktree", "add", "--quiet", "--detach", str(worktree))
        output = self.root / ".git/refs/heads/new-output"
        result = subprocess.run(
            [os.environ.get("OPENRC_TEST_BASH", "bash"), str(worktree / "app/export.sh"),
             "--output-dir", str(output)], cwd=worktree, env=self.export_env(), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
        )
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("outside app/ and Git metadata", result.stdout)
        self.assertFalse(output.exists())

    def test_lock_path_preserves_existing_bytes_and_rejects_symlinks(self):
        lock = self.root / ".git/openrc-export.lock"
        lock.write_bytes(b"existing lock contents")
        result = self.export()
        self.assertIn("== import", result.stdout)
        self.assertEqual(lock.read_bytes(), b"existing lock contents")
        lock.unlink()
        sentinel = self.root / "sentinel"
        sentinel.write_bytes(b"do not truncate")
        lock.symlink_to(sentinel)
        result = self.export()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("export lock must be a regular file", result.stdout)
        self.assertEqual(sentinel.read_bytes(), b"do not truncate")

    def test_help_does_not_prepare_an_export(self):
        result = self.export("--help")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("--output-dir NEW_DIRECTORY", result.stdout)
        self.assertFalse((self.root / "dist").exists())
        self.assertFalse((self.root / "identity.json").exists())

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


@unittest.skipUnless(sys.platform.startswith("linux"), "package shell checks require a Linux host")
class ExportPackaging(unittest.TestCase):
    """Run the real final packaging/handoff commands on disposable payloads."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc package fixture ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dist = self.root / "export with spaces"
        for platform in ("linux", "windows", "macos"):
            (self.dist / platform).mkdir(parents=True)
        self.linux = self.dist / "linux/openrc-simulator.x86_64"
        shutil.copyfile("/bin/true", self.linux)  # Real ELF; it is inventoried, never executed here.
        self.linux.chmod(0o755)
        sidecar = self.dist / "linux/native/kernel/libopenrc_native_kernel.so"
        sidecar.parent.mkdir(parents=True)
        sidecar.write_bytes(self.linux.read_bytes())
        (self.dist / "linux/libopenrc_ground_vehicle.so").write_bytes(self.linux.read_bytes())
        (self.dist / "windows/OpenRC Simulator.exe").write_bytes(b"fixture exe")
        with zipfile.ZipFile(self.dist / "macos/OpenRC Simulator.zip", "w") as archive:
            archive.writestr("OpenRC Simulator.app/Contents/Info.plist", "fixture")
        self.handoff = self.root / "github output"
        self.version = "v1.2.3-rc.2"
        repo = Path(__file__).resolve().parents[2]
        sys.path.insert(0, str(repo / "tools/release"))
        self.addCleanup(sys.path.remove, str(repo / "tools/release"))
        from test_manifest import prepare_repository
        import manifest
        editor, templates, env = prepare_repository(self.root, self.version,
            hashlib.sha256(self.linux.read_bytes()).hexdigest())
        self.captured = manifest.capture(self.root, editor, templates, env)
        manifest.write_new(self.dist / manifest.SNAPSHOT, manifest.json_text(self.captured))
        embedded_manifest = self.root / "app/native/kernel/package.json"
        embedded_manifest.write_text('{"fixture": true}\n')
        receipt = {
            "format": "openrc-native-kernel-package-artifact v1",
            "executable_sha256": manifest.file_info(self.linux)["sha256"],
            "native_binary_sha256": manifest.file_info(sidecar)["sha256"],
            "editor_sha256": self.captured["inputs"]["editor"]["sha256"],
            "template_sha256": self.captured["inputs"]["template/linux_release.x86_64"]["sha256"],
            "manifest_sha256": manifest.file_info(embedded_manifest)["sha256"],
        }
        (self.dist / "linux/native/kernel/package-receipt.json").write_text(manifest.json_text(receipt))
        self.names = [f"openrc-simulator-{self.version}-{suffix}.zip" for suffix in
                      ("linux-x86_64", "windows-x86_64", "macos-universal")]
        source = (Path(__file__).parents[1] / "export.sh").read_text(encoding="utf-8")
        self.commands = source.split('echo "== packages"\n', 1)[1]

    def package(self):
        env = os.environ.copy()
        env.update(ROOT=str(self.root), DIST=str(self.dist), VERSION=self.version, GITHUB_OUTPUT=str(self.handoff))
        return subprocess.run([os.environ.get("OPENRC_TEST_BASH", "bash"), "-euc", self.commands],
                              cwd=self.root, env=env, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=30)

    def test_success_handoff_identifies_exact_checked_package_set(self):
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.handoff.read_text(), f"package_dir={self.dist}\nversion={self.version}\n")
        sums = (self.dist / "SHA256SUMS").read_text().splitlines()
        self.assertEqual(len(sums), 5)
        for name, line in zip(self.names + ["linux-abi.json", "release-manifest.json"], sums):
            self.assertEqual(line, f"{hashlib.sha256((self.dist / name).read_bytes()).hexdigest()}  {name}")
        with zipfile.ZipFile(self.dist / self.names[0]) as archive:
            self.assertEqual(archive.read("openrc-simulator.x86_64"), self.linux.read_bytes())
            self.assertEqual(archive.read("native/kernel/libopenrc_native_kernel.so"), self.linux.read_bytes())
            self.assertEqual((archive.getinfo("openrc-simulator.x86_64").external_attr >> 16) & 0o777, 0o755)
        # Exercise the actual transfer gate with only the six public deliverables.
        transferred = self.root / "downloaded"
        transferred.mkdir()
        for name in self.names + ["linux-abi.json", "release-manifest.json", "SHA256SUMS"]:
            shutil.copyfile(self.dist / name, transferred / name)
        checked = subprocess.run([sys.executable, str(self.root / "tools/release/manifest.py"), "verify",
                                  "--directory", str(transferred), "--expected-tag", self.version,
                                  "--expected-commit", self.captured["source"]["commit"],
                                  "--expected-run-id", "123", "--expected-repository", "owner/project"],
                                 text=True, capture_output=True, timeout=30)
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)

    def test_failed_packaging_never_emits_a_success_handle(self):
        (self.dist / "macos/OpenRC Simulator.zip").unlink()
        result = self.package()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.handoff.exists())
        self.assertFalse((self.dist / "SHA256SUMS").exists())
        self.assertTrue(self.linux.exists())

    def test_changed_qualified_executable_rejects_final_manifest_and_handoff(self):
        # ELF stays valid, but its bytes no longer match the prior package qualification receipt.
        with self.linux.open("ab") as output:
            output.write(b"changed after qualification")
        result = self.package()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("qualified native package receipt", result.stdout)
        self.assertFalse(self.handoff.exists())
        self.assertFalse((self.dist / "release-manifest.json").exists())

    def test_invalid_elf_rejects_final_manifest_and_handoff(self):
        self.linux.write_bytes(b"\x7fELFbroken")
        result = self.package()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.handoff.exists())
        self.assertFalse((self.dist / "release-manifest.json").exists())

    def test_ci_uploads_only_the_run_and_version_returned_by_export(self):
        workflow = (Path(__file__).parents[2] / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn("      - id: packages\n        run: app/export.sh", workflow)
        artifact = workflow.split("          name: release-builds\n", 1)[1].split("\n  release:", 1)[0]
        for suffix in ("linux-x86_64", "windows-x86_64", "macos-universal"):
            self.assertIn("${{ steps.packages.outputs.package_dir }}/openrc-simulator-"
                          "${{ steps.packages.outputs.version }}-" + suffix + ".zip", artifact)
        self.assertIn("${{ steps.packages.outputs.package_dir }}/SHA256SUMS", artifact)
        for name in ("release-manifest.json", "linux-abi.json"):
            self.assertIn("${{ steps.packages.outputs.package_dir }}/" + name, artifact)
        self.assertIn("if-no-files-found: error", artifact)
        self.assertNotIn("*.zip", artifact)
        self.assertIn("(cd dist && sha256sum --check --strict SHA256SUMS)", workflow)
        self.assertIn("--expected-commit \"$GITHUB_SHA\" --expected-tag \"$GITHUB_REF_NAME\"", workflow)
        self.assertIn('--verify-tag --title', workflow)
        self.assertIn('git fetch --no-tags origin "refs/tags/$GITHUB_REF_NAME"', workflow)
        self.assertNotIn("dist/openrc-simulator-*.zip", workflow)


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
