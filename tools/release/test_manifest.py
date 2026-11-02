"""Release input drift, metadata validation and exact transfer inventory regressions."""
import copy
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

if __package__:
    from . import manifest
    from .test_macos_reference_receipt import rewrite_zip, set_executable_mode, write_fixture_zip
else:
    import manifest
    from test_macos_reference_receipt import rewrite_zip, set_executable_mode, write_fixture_zip

REPO = Path(__file__).resolve().parents[2]


class WorktreeIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc worktree ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "app").mkdir()
        (self.root / "app/tracked.txt").write_bytes(b"original\n")
        (self.root / "tracked.bin").write_bytes(bytes(1024 * 1024 + 137))
        (self.root / "deleted.txt").write_bytes(b"delete me\n")
        for args in (("init", "--quiet"), ("config", "user.email", "fixture@example.invalid"),
                     ("config", "user.name", "Release fixture"), ("add", "."),
                     ("commit", "--quiet", "-m", "fixture")):
            subprocess.check_call(["git", "-C", str(self.root), *args])

    def original_identity(self):
        changes = manifest.git(self.root, "diff", "HEAD", "--binary", "--no-ext-diff", "--no-textconv")
        untracked = manifest.git(self.root, "ls-files", "--others", "--exclude-standard", "-z", "--", "app/")
        digest = hashlib.sha256(changes)
        for name in sorted(filter(None, untracked.split(b"\0"))):
            contents = (self.root / os.fsdecode(name)).read_bytes()
            digest.update(b"\0" + name + b"\0" + hashlib.sha256(contents).hexdigest().encode("ascii"))
        return bool(changes or untracked), digest.hexdigest(), changes

    def test_streamed_identity_matches_original_for_clean_untracked_and_large_binary_diffs(self):
        dirty, digest, _ = self.original_identity()
        self.assertFalse(dirty)
        self.assertEqual(manifest.worktree_identity(self.root), (dirty, digest))

        (self.root / "app/z bytes.bin").write_bytes(b"\x00binary\xff")
        (self.root / "app/a empty.txt").write_bytes(b"")
        (self.root / "outside untracked.txt").write_bytes(b"not in app")
        dirty, digest, _ = self.original_identity()
        self.assertTrue(dirty)
        self.assertEqual(manifest.worktree_identity(self.root), (dirty, digest))

        (self.root / "app/tracked.txt").write_bytes(b"staged change\n")
        subprocess.check_call(["git", "-C", str(self.root), "add", "app/tracked.txt"])
        (self.root / "deleted.txt").unlink()
        (self.root / "tracked.bin").write_bytes(random.Random(1234).randbytes(1024 * 1024 + 137))
        dirty, digest, changes = self.original_identity()
        self.assertGreater(len(changes), 1024 * 1024)
        self.assertIn(b"GIT binary patch", changes)

        reads = []
        real_popen = subprocess.Popen

        class ObservedStream:
            def __init__(self, stream):
                self.stream = stream

            def read(self, size=-1):
                chunk = self.stream.read(size)
                reads.append((size, len(chunk)))
                return chunk

            def __getattr__(self, name):
                return getattr(self.stream, name)

        def observe_popen(command, **kwargs):
            process = real_popen(command, **kwargs)
            if command[3:5] == ["diff", "HEAD"]:
                process.stdout = ObservedStream(process.stdout)
            return process

        with mock.patch.object(manifest.subprocess, "Popen", side_effect=observe_popen):
            self.assertEqual(manifest.worktree_identity(self.root), (dirty, digest))
        self.assertGreaterEqual(len(reads), 3)
        self.assertEqual(sum(length for _, length in reads), len(changes))
        self.assertTrue(all(0 < size <= 1024 * 1024 for size, _ in reads))

    def test_git_diff_failure_drains_and_bounds_stderr(self):
        real_popen = subprocess.Popen
        program = ("import sys\n"
                   "sys.stderr.buffer.write(b'E' * 1048576)\n"
                   "sys.stderr.flush()\n"
                   "sys.stdout.buffer.write(b'partial diff' * 100000)\n"
                   "sys.exit(23)\n")

        def failing_popen(command, **kwargs):
            return real_popen([sys.executable, "-c", program], **kwargs)

        with mock.patch.object(manifest.subprocess, "Popen", side_effect=failing_popen), \
             mock.patch.object(manifest, "git") as list_untracked:
            with self.assertRaises(subprocess.CalledProcessError) as failure:
                manifest.worktree_identity(self.root)
        self.assertEqual(failure.exception.returncode, 23)
        self.assertEqual(failure.exception.cmd[3:5], ["diff", "HEAD"])
        self.assertEqual(failure.exception.stderr, b"E" * 65536)
        list_untracked.assert_not_called()

    def test_stderr_read_failure_stops_child_and_propagates(self):
        real_popen = subprocess.Popen

        class BrokenStream:
            def __init__(self, stream):
                self.stream = stream

            def read(self, size=-1):
                raise OSError("stderr read failed")

            def __getattr__(self, name):
                return getattr(self.stream, name)

        def failing_popen(command, **kwargs):
            process = real_popen([sys.executable, "-c", "import time; time.sleep(30)"], **kwargs)
            process.stderr = BrokenStream(process.stderr)
            return process

        with mock.patch.object(manifest.subprocess, "Popen", side_effect=failing_popen):
            with self.assertRaisesRegex(OSError, "stderr read failed"):
                manifest.worktree_identity(self.root)


def prepare_repository(root, version="v1.2.3-rc.2", native_digest="0" * 64):
    """Disposable capture inputs; no Godot or native qualification is implied."""
    fixture_sources = manifest.SOURCE_INPUTS + ("tools/release/macos_reference_receipt.py",
                       "app/tests/check_macos_export.py", "research/performance/session_probe.gd")
    for name in fixture_sources:
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
    # Fix the commit timezone; Git versions render UTC as either Z or +00:00.
    with mock.patch.dict(os.environ, {"GIT_AUTHOR_DATE": "2026-10-29T13:00:00+00:00",
                                      "GIT_COMMITTER_DATE": "2026-10-29T13:00:00+00:00"}):
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
        for name in self.names[:2]:
            (self.output / name).write_bytes(("fixture final archive " + name).encode())
        mac_zip = self.output / "macos/OpenRC Simulator.zip"
        mac_zip.parent.mkdir()
        write_fixture_zip(mac_zip)
        manifest.macos_reference_receipt.package_zip(mac_zip, self.output / self.names[2], self.snapshot, self.root)
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

    def rebuild_transfer_metadata(self, target, *, release_format=None):
        metadata_path = target / manifest.MANIFEST
        metadata = json.loads(metadata_path.read_text())
        if release_format is not None:
            metadata["format"] = release_format
            if release_format == manifest.LEGACY_FORMAT:
                metadata.pop("macos_reference")
        metadata["artifacts"][2].update(manifest.file_info(target / self.names[2]))
        metadata_path.write_text(manifest.json_text(metadata))
        records = metadata["artifacts"] + metadata["reports"] + [{"filename": manifest.MANIFEST,
                    **manifest.file_info(metadata_path)}]
        (target / manifest.CHECKSUMS).write_text(
            "".join(f'{row["sha256"]}  {row["filename"]}\n' for row in records))

    def test_roundtrip_transfer_binds_independent_source_tag_run_repository(self):
        target = self.transferred()
        data = manifest.verify(target, expected_commit=self.env["OPENRC_BUILD_COMMIT"],
                               expected_tag=self.env["OPENRC_BUILD_DESCRIBE"], expected_run_id="123",
                               expected_repository="owner/project")
        self.assertEqual(data["format"], "openrc-release-manifest-v2")
        self.assertEqual(set(data["macos_reference"]), {"receipt_sha256", "source_receipt_sha256", "probe_sha256"})
        self.assertEqual(data["source"]["channel"], "preview")
        self.assertIn(data["source"]["commit_date"], ("2026-10-29T13:00:00Z", "2026-10-29T13:00:00+00:00"))
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

    def test_mac_package_refuses_changed_inputs_before_writing_final_zip(self):
        (self.templates / "macos.zip").write_bytes(b"changed after capture")
        output = self.root / ".cache/refused-macos.zip"
        with self.assertRaisesRegex(ValueError, "input changed"):
            manifest.macos_reference_receipt.package_zip(self.output / "macos/OpenRC Simulator.zip", output,
                                                         self.snapshot, self.root)
        self.assertFalse(output.exists())

    def test_mac_finalization_refuses_different_captured_input_receipt(self):
        snapshot_hash = manifest.file_info(self.snapshot)["sha256"].encode()
        rewrite_zip(self.output / self.names[2],
                    lambda name, data: data.replace(snapshot_hash, b"0" * 64)
                    if name.endswith(".openrc-reference-receipt") else data)
        with self.assertRaisesRegex(ValueError, "captured release inputs"):
            self.finish()
        self.assertFalse((self.output / manifest.MANIFEST).exists())

    def test_mac_finalization_refuses_a_single_architecture_package(self):
        source_zip = self.output / "macos/OpenRC Simulator.zip"
        arm_slice = struct.pack("<II", 0xFEEDFACF, 0x0100000C) + bytes(56)
        rewrite_zip(source_zip, lambda name, data: arm_slice if "/MacOS/" in name else data)
        final_zip = self.output / self.names[2]
        final_zip.unlink()
        manifest.macos_reference_receipt.package_zip(source_zip, final_zip, self.snapshot, self.root)
        with self.assertRaisesRegex(ValueError, "not universal"):
            self.finish()
        self.assertFalse((self.output / manifest.MANIFEST).exists())

    def test_finalization_rejects_rewritten_receipt_for_changed_bundle(self):
        final_zip = self.output / self.names[2]
        original_zip = final_zip.read_bytes()
        for suffix in (".pck", ".dylib", "CodeResources"):
            with zipfile.ZipFile(final_zip) as archive:
                member = next(name for name in archive.namelist() if name.endswith(suffix))
                original = archive.read(member)
            old_hash = hashlib.sha256(original).hexdigest().encode()
            changed = original + b"changed after packaging"
            new_hash = hashlib.sha256(changed).hexdigest().encode()
            rewrite_zip(final_zip, lambda name, data: changed if name == member else
                        data.replace(old_hash, new_hash) if name.endswith(".openrc-reference-receipt") else data)
            with self.subTest(member=member), self.assertRaisesRegex(ValueError, "differs from the checked staged ZIP"):
                self.finish()
            final_zip.write_bytes(original_zip)

    def test_transfer_rejects_missing_receipt_even_with_recomputed_public_hashes(self):
        target = self.transferred()
        mac_zip = target / self.names[2]
        rewrite_zip(mac_zip, lambda name, data: None if name.endswith(".openrc-reference-receipt") else data)
        self.rebuild_transfer_metadata(target)
        with self.assertRaisesRegex(ValueError, "missing external bundle receipt"):
            manifest.verify(target)

    def test_transfer_rejects_changed_executable_mode_after_recomputed_public_hashes(self):
        target = self.transferred()
        set_executable_mode(target / self.names[2], 0o644)
        self.rebuild_transfer_metadata(target)
        with self.assertRaisesRegex(ValueError, "user execute permission"):
            manifest.verify(target)

    def test_transfer_rejects_inconsistent_public_reference_hashes(self):
        target = self.transferred()
        metadata_path = target / manifest.MANIFEST
        original = metadata_path.read_bytes()
        for field in ("receipt_sha256", "source_receipt_sha256", "probe_sha256"):
            metadata = json.loads(original)
            metadata["macos_reference"][field] = "0" * 64
            metadata_path.write_text(manifest.json_text(metadata))
            self.rebuild_transfer_metadata(target)
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "manifest reference digests"):
                manifest.verify(target)

    def test_historical_v1_without_receipt_keeps_original_integrity_policy(self):
        target = self.transferred()
        rewrite_zip(target / self.names[2],
                    lambda name, data: None if name.endswith(".openrc-reference-receipt") else data)
        self.rebuild_transfer_metadata(target, release_format=manifest.LEGACY_FORMAT)
        self.assertEqual(manifest.verify(target)["format"], "openrc-release-manifest-v1")
        with self.assertRaisesRegex(ValueError, "mismatch"):
            with (target / self.names[2]).open("ab") as archive:
                archive.write(b"changed after recorded digest")
            manifest.verify(target)

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


class TimestampValidationTests(unittest.TestCase):
    def test_utc_and_offsets_are_accepted_and_malformed_values_rejected(self):
        # An invalid later field proves the validator reached it after the timestamp.
        source = {"version": "v1.2.3", "commit": "a" * 40, "tree": "b" * 40,
                  "commit_date": "", "application_version": None, "dirty": False,
                  "tag": "v1.2.3", "channel": "stable", "worktree_sha256": "c" * 64}
        data = {"format": manifest.LEGACY_FORMAT, "source": source, "build": None, "engine_version": None,
                "inputs": None, "artifacts": None, "reports": None, "qualification": None}
        for timestamp in ("2026-10-29T13:00:00Z", "2026-10-29T08:00:00-05:00",
                          "2026-10-29T14:00:00+01:00"):
            source["commit_date"] = timestamp
            with self.subTest(timestamp=timestamp), self.assertRaisesRegex(ValueError, "invalid application version"):
                manifest.validate_metadata(data)
        for timestamp in ("2026-10-29T13:00:00", "2026-10-29T13:00:00z",
                          "2026-10-29T13:00:00+0000", "2026-10-29T13:00:00Zextra", None):
            source["commit_date"] = timestamp
            with self.subTest(timestamp=timestamp), self.assertRaisesRegex(ValueError, "invalid source timestamp"):
                manifest.validate_metadata(data)


if __name__ == "__main__":
    unittest.main()
