"""Release input drift, metadata validation and exact transfer inventory regressions."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

if __package__:
    from . import manifest
else:
    import manifest

REPO = Path(__file__).resolve().parents[2]


def prepare_repository(root, version="v1.2.3-rc.2", native_digest="0" * 64):
    """Disposable capture inputs; no Godot or native qualification is implied."""
    for name in manifest.SOURCE_INPUTS:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        source = REPO / name
        if source.is_file():
            path.write_bytes(source.read_bytes().replace(b"\r\n", b"\n"))
        else:
            path.write_text('{"fixture": true}\n')
    (root / "app/project.godot").write_text('config/version="1.2.3"\n')
    (root / "app/export_presets.cfg").write_text('custom_template/release="res://.godot/export_templates/fixture.zip"\n')
    (root / "app/get-godot.sh").write_text("ENGINE_VERSION=fixture.engine\n")
    (root / ".gitignore").write_text("/export with spaces/\n/.cache/\n/app/.godot/\n/app/native/kernel/package.json\n")
    for kind in ("kernel", "ground_vehicle"):
        (root / f"app/native/{kind}/build-receipt.json").write_text(json.dumps(
            {"platforms": {"linux": {"binary_sha256": native_digest}}}))
    derived = root / "app/.godot/export_templates/fixture.zip"
    derived.parent.mkdir(parents=True)
    derived.write_bytes(b"corrected macOS template")
    derived.with_suffix(".zip.receipt.json").write_text('{"fixture": true}\n')
    templates = root / ".cache/template files"
    templates.mkdir(parents=True)
    for name in manifest.TEMPLATES:
        (templates / name).write_bytes(("template " + name).encode())
    editor = root / ".cache/editor"
    editor.write_text("#!/bin/sh\nprintf 'fixture.engine\\n'\n", newline="\n")
    editor.chmod(0o755)
    def git(*args):
        return subprocess.check_output(["git", *args], cwd=root, stderr=subprocess.PIPE, text=True).strip()
    git("init", "--quiet")
    git("config", "user.email", "fixture@example.invalid")
    git("config", "user.name", "Release fixture")
    git("config", "core.autocrlf", "false")
    git("add", ".")
    git("commit", "--quiet", "-m", "fixture")
    git("tag", version)
    env = {"OPENRC_BUILD_DESCRIBE": version, "OPENRC_BUILD_COMMIT": git("rev-parse", "HEAD"),
           "OPENRC_BUILD_DATE": git("show", "-s", "--format=%cI", "HEAD"), "OPENRC_BUILD_DIRTY": "0",
           "GITHUB_REF": "refs/tags/" + version, "GITHUB_RUN_ID": "123", "GITHUB_REPOSITORY": "owner/project"}
    return editor, templates, env


@unittest.skipUnless(sys.platform.startswith("linux") and shutil.which("readelf") and shutil.which("zip"),
                     "capture/export fixtures require Linux tools")
class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc manifest ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.editor, self.templates, self.env = prepare_repository(self.root)
        self.output = self.root / "export with spaces"
        self.output.mkdir()
        self.snapshot = self.output / manifest.SNAPSHOT
        self.captured = manifest.capture(self.root, self.editor, self.templates, self.env)
        manifest.write_new(self.snapshot, manifest.json_text(self.captured))
        self.names = manifest.artifact_names(self.env["OPENRC_BUILD_DESCRIBE"])
        for name in self.names:
            (self.output / name).write_bytes(("fixture final archive " + name).encode())
        self.report = {
            "format": "openrc-linux-abi-v1", "schema_version": 1,
            "archive": {"path": self.names[0], **manifest.file_info(self.output / self.names[0])},
            "expected_architecture": "x86_64", "elfs": [{"fixture": True}],
        }
        # ABI parsing/structure has its own real-ELF tests; these fixtures isolate
        # manifest binding and transfer integrity, rather than pretending to be ELF.
        self.abi_validator = mock.patch.object(manifest, "validate_abi", side_effect=self.check_binding)
        self.abi_validator.start()
        self.addCleanup(self.abi_validator.stop)
        self.payload_validator = mock.patch.object(manifest, "validate_linux_payload")
        self.payload_validator.start()
        self.addCleanup(self.payload_validator.stop)
        self.write_report()

    def check_binding(self, report, linux):
        manifest.require(report["archive"] == {"path": linux["filename"], "sha256": linux["sha256"], "bytes": linux["bytes"]},
                         "ABI report does not identify archive")

    def write_report(self):
        (self.output / manifest.ABI_REPORT).write_text(manifest.json_text(self.report))

    def finish(self):
        return manifest.finalize(self.output, self.root, self.snapshot)

    def transferred(self):
        self.finish()
        target = self.root / "downloaded"
        target.mkdir()
        for name in self.names + [manifest.MANIFEST, manifest.ABI_REPORT, manifest.CHECKSUMS]:
            shutil.copyfile(self.output / name, target / name)
        return target

    def test_roundtrip_transfer_binds_independent_source_tag_run_repository(self):
        target = self.transferred()
        data = manifest.verify(target, expected_commit=self.env["OPENRC_BUILD_COMMIT"],
                               expected_tag=self.env["OPENRC_BUILD_DESCRIBE"], expected_run_id="123",
                               expected_repository="owner/project")
        self.assertEqual(data["source"]["channel"], "preview")
        self.assertNotIn(str(self.root), (target / manifest.MANIFEST).read_text())
        lines = (target / manifest.CHECKSUMS).read_text().splitlines()
        self.assertEqual(len(lines), 5)
        self.assertFalse(any(line.endswith("  SHA256SUMS") for line in lines))
        with self.assertRaisesRegex(ValueError, "inventory"):
            manifest.verify(self.output)  # Private capture input is not a release asset.

    def test_rejects_wrong_independent_identity(self):
        target = self.transferred()
        for kwargs in ({"expected_commit": "0" * 40}, {"expected_tag": "v1.2.3"},
                       {"expected_run_id": "456"}, {"expected_repository": "other/project"}):
            with self.subTest(kwargs=kwargs), self.assertRaisesRegex(ValueError, "unexpected release"):
                manifest.verify(target, **kwargs)

    def test_rejects_changed_missing_extra_and_symlink_assets(self):
        target = self.transferred()
        asset = target / self.names[0]
        original = asset.read_bytes()
        asset.write_bytes(original + b"changed")
        with self.assertRaisesRegex(ValueError, "mismatch"):
            manifest.verify(target)
        asset.unlink()
        with self.assertRaisesRegex(ValueError, "not a regular"):
            manifest.verify(target)
        asset.symlink_to(self.output / self.names[0])
        with self.assertRaisesRegex(ValueError, "not a regular"):
            manifest.verify(target)
        asset.unlink()
        asset.write_bytes(original)
        for name in ("extra.zip", "notes"):
            extra = target / name
            extra.write_bytes(b"unreviewed")
            with self.assertRaisesRegex(ValueError, "inventory"):
                manifest.verify(target)
            extra.unlink()
        (target / "unexpected-directory").mkdir()
        with self.assertRaisesRegex(ValueError, "inventory"):
            manifest.verify(target)

    def test_rejects_duplicate_missing_and_self_checksum_entries(self):
        target = self.transferred()
        path = target / manifest.CHECKSUMS
        original = path.read_text()
        invalid = [original + original.splitlines()[0] + "\n", "\n".join(original.splitlines()[1:]) + "\n",
                   original + "0" * 64 + "  SHA256SUMS\n", original.replace("  ", " *", 1)]
        for text in invalid:
            path.write_text(text)
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, "checksum"):
                manifest.verify(target)

    def test_rejects_malformed_schema_types_names_and_qualification(self):
        data = self.finish()
        mutations = [lambda d: d.update(format="future"), lambda d: d["source"].update(dirty="false"),
                     lambda d: d["artifacts"][0].update(bytes=True),
                     lambda d: d["artifacts"][0].update(sha256="A" * 64),
                     lambda d: d["artifacts"][0].update(filename="../outside.zip"),
                     lambda d: d["artifacts"][0].update(architecture="arm64"),
                     lambda d: d["source"].update(channel="stable"),
                     lambda d: d["source"].update(application_version="9.9.9"),
                     lambda d: d["qualification"].update(status="qualified"),
                     lambda d: d["inputs"].pop("template/macos-derived.zip"),
                     lambda d: d.update(unrecognized=True)]
        for mutate in mutations:
            bad = copy.deepcopy(data)
            mutate(bad)
            with self.subTest(mutation=mutate), self.assertRaises(ValueError):
                manifest.validate_metadata(bad)

    def test_rejects_duplicate_json_keys(self):
        path = self.output / "duplicate.json"
        path.write_text('{"a": 1, "a": 2}')
        with self.assertRaisesRegex(ValueError, "duplicate JSON"):
            manifest.read_json(path)

    def test_source_and_template_mutations_after_capture_fail_before_handoff(self):
        template = self.templates / "linux_release.x86_64"
        original = template.read_bytes()
        template.write_bytes(b"changed template")
        with self.assertRaisesRegex(ValueError, "input changed"):
            self.finish()
        self.assertFalse((self.output / manifest.MANIFEST).exists())
        template.write_bytes(original)
        (self.root / "app/project.godot").write_text('config/version="1.2.4"\n')
        with self.assertRaisesRegex(ValueError, "cleanliness changed"):
            self.finish()

    def test_changed_abi_archive_binding_fails_before_manifest(self):
        self.report["archive"]["sha256"] = "0" * 64
        self.write_report()
        with self.assertRaisesRegex(ValueError, "ABI report"):
            self.finish()
        self.assertFalse((self.output / manifest.MANIFEST).exists())

    def test_finalize_does_not_replace_existing_metadata(self):
        self.finish()
        first = (self.output / manifest.MANIFEST).read_bytes()
        with self.assertRaises(FileExistsError):
            self.finish()
        self.assertEqual(first, (self.output / manifest.MANIFEST).read_bytes())

    def test_capture_hashes_actual_derived_template_and_blocks_wrong_editor(self):
        self.assertEqual(self.captured["inputs"]["template/macos-derived.zip"],
                         manifest.file_info(self.root / "app/.godot/export_templates/fixture.zip"))
        self.editor.write_text("#!/bin/sh\necho wrong.engine\n", newline="\n")
        with self.assertRaisesRegex(ValueError, "pinned engine"):
            manifest.capture(self.root, self.editor, self.templates, self.env)

    def test_empty_untracked_project_file_marks_development_source_dirty(self):
        (self.root / "app/empty.gd").touch()
        env = dict(self.env, GITHUB_REF="refs/heads/main", OPENRC_BUILD_DIRTY="1",
                   OPENRC_BUILD_DESCRIBE="v1.2.3-rc.2-dirty")
        result = manifest.capture(self.root, self.editor, self.templates, env)
        self.assertTrue(result["source"]["dirty"])
        self.assertEqual(result["source"]["channel"], "development")


if __name__ == "__main__":
    unittest.main()
