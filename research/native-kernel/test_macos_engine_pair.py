#!/usr/bin/env python3
"""Portable synthetic controls; no compiled engine or hardware qualification."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock
import warnings
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = next(parent for parent in HERE.parents if (parent / "tools/graphics/metalfx/engine.py").is_file())
TEST_ROOT = HERE.parents[1] if HERE.parents[1] != ROOT else ROOT / "tmp"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pair = load("pair_draft", HERE / "macos_engine_pair.py")
engine = load("pair_actual_intake", ROOT / "tools/graphics/metalfx/engine.py")
identity_path = HERE / "macos_engine_identity.py"
if not identity_path.is_file():
    identity_path = Path(os.environ["OPENRC_PAIR_TEST_IDENTITY"])
policy = load("pair_actual_editor_identity", identity_path)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def macho(cpu=0x0100000C):
    return struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, 8, 0, 0) + b"fixture executable payload"


class PairBindingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="pair-test-", dir=TEST_ROOT)
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).absolute()
        self.archive = self.root / "source.zip"
        self.skeleton = {name: ("original " + name).encode() for name in pair.SKELETON}
        with zipfile.ZipFile(self.archive, "w") as package:
            package.writestr(engine.SOURCE_PREFIX + "/engine/source.cpp", "old\n")
            for name, content in self.skeleton.items():
                package.writestr(engine.SOURCE_PREFIX + "/misc/dist/" + name, content)
        self.start(mock.patch.object(engine, "SOURCE_SHA256", digest(self.archive)))
        self.patches = []
        for index, (old, new) in enumerate((("old", "new"), ("new", "final")), 1):
            path = self.root / f"000{index}.patch"
            path.write_text(f"diff --git a/engine/source.cpp b/engine/source.cpp\n"
                            f"--- a/engine/source.cpp\n+++ b/engine/source.cpp\n"
                            f"@@ -1 +1 @@\n-{old}\n+{new}\n", encoding="utf-8", newline="\n")
            self.patches.append(path)
        self.editor, self.template = self.root / "editor", self.root / "template"
        self.binaries = {}
        for directory, target in ((self.editor, "editor"), (self.template, "template_release")):
            intake = engine.prepare(self.archive, directory, self.patches)
            build = directory / f"build-source-{target}"
            shutil.copytree(directory / "source", build, ignore=shutil.ignore_patterns(".git"))
            binary = build / f"bin/godot.macos.{target}.arm64"
            binary.parent.mkdir()
            binary.write_bytes(macho() if target == "template_release" else b"synthetic editor")
            binary.chmod(0o755)
            self.binaries[target] = binary
            log = directory / f"build-{target}.log"
            log.write_text("synthetic build log", encoding="utf-8")
            sdk = "/SDK"
            command = ["/python", "-m", "SCons", "-j4", "platform=macos", "arch=arm64",
                       f"target={target}", "metal=yes", "vulkan=no", "opengl3=yes", "d3d12=no",
                       "debug_symbols=no", "optimize=speed", "lto=none", "accesskit=no", "generate_bundle=no",
                       f"MACOS_SDK_PATH={sdk}", f"cxxflags=-isystem {sdk}/usr/include/c++/v1"]
            record = {"schema": engine.SCHEMA, "status": "built", "target": target, "intake": intake,
                      "returncode": 0, "command": command, "sdk_path": sdk, "sdk_version": "27.2",
                      "clang": policy.TOOLCHAIN_PROFILES[policy.NEW_TOOLCHAIN_PROFILE]["compiler_version"] + "\nfixture",
                      "host_os": "27.0", "process_arch": "arm64", "scons": engine.SCONS_VERSION,
                      "zstandard": engine.ZSTANDARD_VERSION, "python": "fixture Python", "deployment_target": "13.0",
                      "controlled_environment": {**dict.fromkeys(policy.CONTROLLED),
                                                 "GODOT_VERSION_STATUS": "beta2", "BUILD_NAME": "openrc_metalfx"},
                      "path": "/usr/bin:/bin:/usr/sbin:/sbin", "hardware_qualification": "not_run",
                      "log_sha256": digest(log), "artifacts": [{"name": binary.name, "sha256": digest(binary),
                      "bytes": binary.stat().st_size, "architectures": ["arm64"]}]}
            (directory / f"build-{target}.json").write_text(json.dumps(record), encoding="utf-8")
        self.receipt = self.root / "pair.json"
        self.export = self.root / "custom-macos.zip"
        self.reference = self.root / "official-godot"
        self.reference.write_bytes(b"synthetic official editor")
        self.reference.chmod(0o755)
        self.api = self.root / "godot-cpp/gdextension/extension_api-4-7.json"
        self.api.parent.mkdir(parents=True)
        self.api.write_text("{}", encoding="utf-8")
        self.lock = {"godot": {"version": policy.OFFICIAL_VERSION, "extension_api": "4.7"},
                     "godot_cpp": {"commit": policy.GODOT_CPP_COMMIT}}
        self.selection = {"sha256": digest(self.binaries["editor"]), "cli_version": policy.RESEARCH_CLI,
                          "runtime_version": policy.RESEARCH_RUNTIME, "receipt": str(self.editor / "build-editor.json"),
                          "archive": str(self.archive), "extension_api": str(self.api),
                          "reference_godot": str(self.reference), "patches": [str(p) for p in self.patches],
                          "toolchain_profile": policy.NEW_TOOLCHAIN_PROFILE}
        self.dump = {"header": {"version_major": 4, "version_minor": 8, "version_patch": 0,
                                "version_status": "beta2", "version_build": "official", "precision": "single"}}
        self.dump.update({key: [{"name": "fixture"}] for key in (
            "global_constants", "global_enums", "utility_functions", "builtin_classes", "classes",
            "singletons", "native_structures")})
        api_proof = {"checkout": str(self.api.parent.parent), "commit": policy.GODOT_CPP_COMMIT,
                     "blob": "b" * 40, "sha256": digest(self.api)}
        self.start(mock.patch.object(policy, "HELPER", Path(engine.__file__)))
        self.start(mock.patch.object(policy, "OFFICIAL_ARM64_SHA256", digest(self.reference)))
        self.start(mock.patch.object(policy, "_helper", return_value=engine))
        self.start(mock.patch.object(policy, "extension_api_identity", return_value=api_proof))
        original_tempdir = tempfile.TemporaryDirectory
        def owned_tempdir(*args, **kwargs):
            kwargs.setdefault("dir", self.root)
            return original_tempdir(*args, **kwargs)
        self.start(mock.patch.object(policy.tempfile, "TemporaryDirectory", side_effect=owned_tempdir))
        self.mac = SimpleNamespace(engine_policy=policy, locked=SimpleNamespace(load_lock=lambda: self.lock),
                                   godot_identity=self.identify)
        self.start(mock.patch.object(pair, "_engine", return_value=engine))
        self.start(mock.patch.object(pair, "_mac_builder", return_value=self.mac))
        self.write_export()
        self.refresh_pair_and_pins()

    def start(self, patcher):
        patcher.start()
        self.addCleanup(patcher.stop)

    def output(self, command, *, cwd=None, expected_diagnostic=None):
        if "--version" in command:
            return policy.OFFICIAL_VERSION if command[0] == str(self.reference) else policy.RESEARCH_CLI
        if "--dump-extension-api" in command:
            (Path(cwd) / "extension_api.json").write_text(json.dumps(self.dump), encoding="utf-8")
            return "Dumping API"
        if "--validate-extension-api" in command:
            return expected_diagnostic or ""
        raise AssertionError(command)

    def identify(self, godot, lock, selection):
        return policy.identify(godot, lock, selection, architectures=lambda _: ["arm64"], output=self.output)

    def write_export(self, *, changes=None, extra=None, duplicate=None, release=None, symlink=None):
        contents = {**self.skeleton, pair.RELEASE_MEMBER: release if release is not None
                    else self.binaries["template_release"].read_bytes()}
        for name, value in (changes or {}).items():
            if value is None:
                del contents[name]
            else:
                contents[name] = value
        if extra:
            contents.update(extra)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.export, "w", compression=zipfile.ZIP_DEFLATED) as package:
                for name, content in contents.items():
                    info = zipfile.ZipInfo(name)
                    info.create_system = 3
                    mode = stat.S_IFLNK | 0o777 if name == symlink else \
                        stat.S_IFREG | (0o755 if name == pair.RELEASE_MEMBER else 0o644)
                    info.external_attr = mode << 16
                    package.writestr(info, content, compress_type=zipfile.ZIP_DEFLATED)
                if duplicate:
                    info = zipfile.ZipInfo(duplicate)
                    info.create_system = 3
                    info.external_attr = (stat.S_IFREG | 0o644) << 16
                    package.writestr(info, b"duplicate")

    def refresh_pair_and_pins(self):
        fresh = engine.verify_pair(self.archive, self.editor, self.template, self.patches)
        self.receipt.write_text(json.dumps(fresh, indent=2) + "\n", encoding="utf-8")
        intake = json.loads((self.editor / "intake.json").read_text(encoding="utf-8"))
        self.expected = {"format": pair.FORMAT, "editor_sha256": fresh["artifacts"][0]["sha256"],
                         "template_sha256": fresh["artifacts"][1]["sha256"],
                         "editor_receipt_sha256": fresh["build_receipts"][0],
                         "template_receipt_sha256": fresh["build_receipts"][1],
                         "pair_receipt_sha256": digest(self.receipt), "export_template_sha256": digest(self.export),
                         "source_archive_sha256": digest(self.archive),
                         "source_catalog_sha256": intake["source_catalog_sha256"],
                         "patch_sha256": [digest(path) for path in self.patches]}

    def bind(self, **overrides):
        values = {"archive": self.archive, "editor_intake": self.editor, "template_intake": self.template,
                  "patches": self.patches, "pair_receipt": self.receipt, "export_template": self.export,
                  "godot": self.binaries["editor"], "selection": self.selection, "expected": self.expected}
        values.update(overrides)
        return pair.bind(**values)

    def test_valid_binding_uses_real_pair_and_editor_verifiers(self):
        with mock.patch.object(engine, "verify_pair", wraps=engine.verify_pair) as verified, \
                mock.patch.object(policy, "identify", wraps=policy.identify) as identified:
            result = self.bind()
        self.assertEqual(result, self.expected)
        self.assertEqual(verified.call_count, 2)
        self.assertEqual(identified.call_count, 2)
        self.assertEqual(result["template_sha256"], digest(self.binaries["template_release"]))

    def test_saved_receipt_and_all_external_pins_are_mandatory(self):
        changed = json.loads(self.receipt.read_text())
        changed["artifacts"][1]["sha256"] = "a" * 64
        self.receipt.write_text(json.dumps(changed), encoding="utf-8")
        pins = {**self.expected, "pair_receipt_sha256": digest(self.receipt)}
        with self.assertRaisesRegex(ValueError, "Saved pair differs"):
            self.bind(expected=pins)
        self.refresh_pair_and_pins()
        for key in sorted(pair.SHA_FIELDS):
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "independently selected"):
                self.bind(expected={**self.expected, key: "f" * 64})
        with self.assertRaisesRegex(ValueError, "independently selected"):
            self.bind(expected={**self.expected, "patch_sha256": self.expected["patch_sha256"][::-1]})
        self.receipt.write_text('{"status":"built","status":"pair_verified"}', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Duplicate receipt key"):
            self.bind()

    def test_wrong_selected_editor_pair_order_and_patch_order_refuse(self):
        selection = {**self.selection, "sha256": "f" * 64}
        with self.assertRaises(ValueError):
            self.bind(selection=selection)
        with self.assertRaises(ValueError):
            self.bind(editor_intake=self.template, template_intake=self.editor)
        reversed_selection = {**self.selection, "patches": self.selection["patches"][::-1]}
        with self.assertRaises((ValueError, RuntimeError)):
            self.bind(patches=self.patches[::-1], selection=reversed_selection)

    def test_explicit_engine_profile_must_match_both_receipts(self):
        without = dict(self.selection)
        del without["toolchain_profile"]
        with self.assertRaisesRegex(ValueError, "explicit, supported"):
            self.bind(selection=without)
        wrong = {**self.selection, "toolchain_profile": policy.DEFAULT_TOOLCHAIN_PROFILE}
        with self.assertRaisesRegex(ValueError, "compiler/SDK profile"):
            self.bind(selection=wrong)
        target = self.template / "build-template_release.json"
        receipt = json.loads(target.read_text())
        receipt["sdk_version"] = "27.0"
        target.write_text(json.dumps(receipt), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "compiler/SDK profile"):
            self.bind(expected={**self.expected, "template_receipt_sha256": digest(target)})

    def test_extra_target_hidden_from_pair_normalization_is_rejected(self):
        target = self.template / "build-template_release.json"
        receipt = json.loads(target.read_text())
        receipt["command"].append("target=editor")
        target.write_text(json.dumps(receipt), encoding="utf-8")
        # The original helper strips all target= arguments when comparing flags.
        self.refresh_pair_and_pins()
        with self.assertRaisesRegex(ValueError, "Template command differs"):
            self.bind()

    def test_duplicate_template_intake_key_is_rejected(self):
        target = self.template / "intake.json"
        contents = target.read_text(encoding="utf-8")
        target.write_text(contents.replace('"schema":', '"schema": "forged", "schema":', 1), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Duplicate receipt key"):
            self.bind()

    def test_provenance_mismatch_cannot_be_replaced_by_matching_pair(self):
        actual = self.mac.godot_identity
        for field in ("build_receipt_sha256", "source_archive_sha256", "source_catalog_sha256", "ordered_patches"):
            def altered(*args, field=field):
                identity = actual(*args)
                identity["research_engine"][field] = [] if field == "ordered_patches" else "a" * 64
                return identity
            with self.subTest(field=field), mock.patch.object(self.mac, "godot_identity", side_effect=altered):
                with self.assertRaisesRegex(ValueError, "provenance differs|source catalog differs"):
                    self.bind()

    def test_zip_roster_skeleton_and_payload_refuse_even_when_zip_pin_is_updated(self):
        cases = [dict(extra={"../escape": b"evil"}),
                 dict(extra={"macos_template.app/Contents/MacOS/godot_macos_debug.arm64": macho()}),
                 dict(duplicate=pair.RELEASE_MEMBER),
                 dict(changes={"macos_template.app/Contents/PkgInfo": b"wrong source skeleton"}),
                 dict(release=macho()[:-1] + b"X")]
        for case in cases:
            self.write_export(**case)
            pins = {**self.expected, "export_template_sha256": digest(self.export)}
            with self.subTest(case=case), self.assertRaises(ValueError):
                self.bind(expected=pins)

    def test_symlink_member_and_non_arm64_release_refuse(self):
        self.write_export(symlink="macos_template.app/Contents/PkgInfo")
        with self.assertRaisesRegex(ValueError, "Unsafe or oversized ZIP member"):
            self.bind(expected={**self.expected, "export_template_sha256": digest(self.export)})
        # Forge mutually consistent receipt/ZIP bytes: architecture must still be independently inspected.
        binary = self.binaries["template_release"]
        binary.write_bytes(macho(cpu=0x01000007))
        target = self.template / "build-template_release.json"
        receipt = json.loads(target.read_text())
        receipt["artifacts"][0]["sha256"] = digest(binary)
        receipt["artifacts"][0]["bytes"] = binary.stat().st_size
        target.write_text(json.dumps(receipt), encoding="utf-8")
        self.write_export()
        self.refresh_pair_and_pins()
        with self.assertRaisesRegex(ValueError, "ARM64 Mach-O"):
            self.bind()

    def test_forged_central_directory_count_is_rejected_before_zipfile_parsing(self):
        raw = bytearray(self.export.read_bytes())
        struct.pack_into("<H", raw, len(raw) - 12, 60000)
        self.export.write_bytes(raw)
        with self.assertRaisesRegex(ValueError, "bounded five-entry central directory"):
            self.bind(expected={**self.expected, "export_template_sha256": digest(self.export)})

    def test_mutated_source_build_log_and_inputs_during_identification_refuse(self):
        source = self.template / "build-source-template_release/engine/source.cpp"
        original = source.read_bytes()
        source.write_bytes(b"tampered build source")
        with self.assertRaisesRegex(ValueError, "source drift"):
            self.bind()
        source.write_bytes(original)
        log = self.template / "build-template_release.log"
        original = log.read_bytes()
        log.write_bytes(b"tampered log")
        with self.assertRaisesRegex(ValueError, "log identity changed"):
            self.bind()
        log.write_bytes(original)
        actual = self.mac.godot_identity
        def mutate(*args):
            result = actual(*args)
            self.receipt.write_bytes(self.receipt.read_bytes() + b" ")
            return result
        with mock.patch.object(self.mac, "godot_identity", side_effect=mutate):
            with self.assertRaisesRegex(ValueError, "inputs changed"):
                self.bind()

    def test_export_zip_mutated_after_member_inspection_is_rejected(self):
        actual = self.mac.godot_identity
        calls = []
        def mutate_after_inspection(*args):
            result = actual(*args)
            calls.append(True)
            if len(calls) == 2:
                self.export.write_bytes(self.export.read_bytes() + b"\0")
            return result
        with mock.patch.object(self.mac, "godot_identity", side_effect=mutate_after_inspection):
            with self.assertRaisesRegex(ValueError, "inputs changed"):
                self.bind()
        self.assertEqual(len(calls), 2)

    def test_redirected_input_is_rejected(self):
        link = self.root / "redirect.zip"
        try:
            link.symlink_to(self.export)
        except OSError as error:
            self.skipTest(f"symlink creation unavailable: {error}")
        with self.assertRaisesRegex(ValueError, "Redirected|Symbolic-link"):
            self.bind(export_template=link)


if __name__ == "__main__":
    unittest.main()
