"""Intake negative controls; these do not compile an engine or qualify MetalFX."""
from pathlib import Path
import json
import tempfile
import unittest
from unittest import mock
import zipfile

import engine


class IntakeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="metalfx-intake-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archive = self.root / "source.zip"
        self.write_archive({"engine/source.cpp": "old\n", "LICENSE.txt": "MIT\n"})
        pin = mock.patch.object(engine, "SOURCE_SHA256", engine.sha256(self.archive))
        pin.start()
        self.addCleanup(pin.stop)
        self.output = self.root / "candidate"

    def write_archive(self, files):
        with zipfile.ZipFile(self.archive, "w") as package:
            for name, data in files.items():
                package.writestr(engine.SOURCE_PREFIX + "/" + name, data)

    def patch(self, name="change.patch", before="old", after="new"):
        patch = self.root / name
        patch.write_text(f"diff --git a/engine/source.cpp b/engine/source.cpp\n"
                         f"--- a/engine/source.cpp\n+++ b/engine/source.cpp\n"
                         f"@@ -1 +1 @@\n-{before}\n+{after}\n", encoding="utf-8", newline="\n")
        return patch

    def test_archive_hash_checked_before_output_created(self):
        self.archive.write_bytes(self.archive.read_bytes() + b"drift")
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            engine.prepare(self.archive, self.output, [])
        self.assertFalse(self.output.exists())

    def test_path_traversal_rejected_even_with_matching_archive_hash(self):
        self.write_archive({"../escape": "bad"})
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            engine.archive_catalog(self.archive, expected=engine.sha256(self.archive))
        self.assertFalse((self.root / "escape").exists())

    def test_case_collision_rejected(self):
        self.write_archive({"file": "one", "FILE": "two"})
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            engine.archive_catalog(self.archive, expected=engine.sha256(self.archive))

    def test_symbolic_link_archive_member_rejected(self):
        with zipfile.ZipFile(self.archive, "w") as package:
            info = zipfile.ZipInfo(engine.SOURCE_PREFIX + "/link")
            info.create_system = 3
            info.external_attr = (0o120777 << 16)
            package.writestr(info, "outside")
        with self.assertRaisesRegex(ValueError, "symbolic-link"):
            engine.archive_catalog(self.archive, expected=engine.sha256(self.archive))

    def test_patch_order_and_full_catalog_verified(self):
        patches = [self.patch(), self.patch("second.patch", "new", "final")]
        receipt = engine.prepare(self.archive, self.output, patches)
        self.assertEqual(receipt["native_build"], "not_run")
        self.assertEqual(receipt["hardware_qualification"], "not_run")
        self.assertEqual((self.output / "source/engine/source.cpp").read_text(), "final\n")
        self.assertEqual(engine.verify_intake(self.archive, self.output, patches), receipt)
        with self.assertRaises(Exception):
            engine.verify_intake(self.archive, self.output, patches[::-1])

    def test_unknown_edit_and_extra_input_rejected(self):
        engine.prepare(self.archive, self.output, [])
        source = self.output / "source"
        (source / "injected.cpp").write_text("unknown")
        with self.assertRaisesRegex(ValueError, "Unexpected engine input"):
            engine.verify_intake(self.archive, self.output, [])
        (source / "injected.cpp").unlink()
        (source / "LICENSE.txt").write_text("changed")
        with self.assertRaisesRegex(ValueError, "source drift"):
            engine.verify_intake(self.archive, self.output, [])

    def test_changed_patch_rejected_without_modifying_prepared_tree(self):
        patch = self.patch()
        engine.prepare(self.archive, self.output, [patch])
        self.patch(after="other")
        with self.assertRaisesRegex(ValueError, "receipt"):
            engine.verify_intake(self.archive, self.output, [patch])
        self.assertEqual((self.output / "source/engine/source.cpp").read_text(), "new\n")

    def test_existing_output_preserved(self):
        self.output.mkdir()
        marker = self.output / "keep"
        marker.write_text("preserve")
        with self.assertRaisesRegex(ValueError, "fresh"):
            engine.prepare(self.archive, self.output, [])
        self.assertEqual(marker.read_text(), "preserve")

    def test_patch_path_escape_rejected(self):
        patch = self.root / "escape.patch"
        patch.write_text("--- a/../escape\n+++ b/../escape\n@@ -1 +1 @@\n-x\n+y\n")
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            engine.prepare(self.archive, self.output, [patch])
        self.assertFalse(self.output.exists())

    def test_non_native_build_rejected_without_receipt(self):
        with mock.patch.object(engine.sys, "platform", "win32"):
            with self.assertRaisesRegex(ValueError, "ARM64 macOS"):
                engine.build(self.archive, self.output, [], "editor", 4)
        self.assertFalse(self.output.exists())

    def pair_fixture(self):
        """Synthetic receipts exercise the verifier, never a claimed native pair."""
        template = self.root / "template"
        for directory, target in ((self.output, "editor"), (template, "template_release")):
            intake = engine.prepare(self.archive, directory, [])
            binary = directory / f"build-source-{target}/bin/godot.macos.{target}.arm64"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b"fixture-not-a-Mach-O")
            log = directory / f"build-{target}.log"
            log.write_text("fixture only")
            build = {"schema": engine.SCHEMA, "status": "built", "target": target, "intake": intake,
                     "command": ["python", "-m", "SCons", f"target={target}", "metal=yes"],
                     "sdk_path": "/sdk", "sdk_version": "27.0", "clang": "fixture clang",
                     "host_os": "27.0.1", "process_arch": "arm64", "scons": engine.SCONS_VERSION,
                     "zstandard": engine.ZSTANDARD_VERSION, "python": "fixture Python",
                     "deployment_target": "13.0", "controlled_environment": {}, "path": "/usr/bin",
                     "log_sha256": engine.sha256(log), "artifacts": [{"name": binary.name,
                     "sha256": engine.sha256(binary), "bytes": binary.stat().st_size, "architectures": ["arm64"]}]}
            (directory / f"build-{target}.json").write_text(json.dumps(build))
        return template

    def test_pair_rejects_toolchain_mismatch(self):
        template = self.pair_fixture()
        self.assertEqual(engine.verify_pair(self.archive, self.output, template, [])["status"], "pair_verified")
        path = template / "build-template_release.json"
        data = json.loads(path.read_text())
        data["sdk_version"] = "other"
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "toolchain differs"):
            engine.verify_pair(self.archive, self.output, template, [])

    def test_pair_rejects_artifact_replacement(self):
        template = self.pair_fixture()
        (template / "build-source-template_release/bin/godot.macos.template_release.arm64").write_bytes(b"replaced")
        with self.assertRaisesRegex(ValueError, "artifact identity"):
            engine.verify_pair(self.archive, self.output, template, [])

    def test_pair_rejects_flag_mismatch(self):
        template = self.pair_fixture()
        path = template / "build-template_release.json"
        data = json.loads(path.read_text())
        data["command"].append("metal=no")
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "flags differ"):
            engine.verify_pair(self.archive, self.output, template, [])


if __name__ == "__main__":
    unittest.main()
