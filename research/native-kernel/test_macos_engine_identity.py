#!/usr/bin/env python3
"""Portable checks for explicit local research-engine admission."""
from __future__ import annotations

import argparse
import copy
from contextlib import redirect_stderr
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("mac_engine_identity_test", HERE / "macos_engine_identity.py")
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)


class ResearchIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).absolute()
        self.binary = self.root / "build-source-editor/bin/godot.macos.editor.arm64"
        self.binary.parent.mkdir(parents=True)
        self.binary.write_bytes(b"fixture editor")
        self.archive = self.root / "source.zip"
        self.archive.write_bytes(b"fixture source")
        self.patch1, self.patch2 = self.root / "0001.patch", self.root / "0002.patch"
        self.patch1.write_text("first", encoding="utf-8")
        self.patch2.write_text("second", encoding="utf-8")
        self.log = self.root / "build-editor.log"
        self.log.write_text("fixture build", encoding="utf-8")
        self.receipt = self.root / "build-editor.json"
        self.intake = {"source_catalog_sha256": "b" * 64, "source_files": 1, "source_url": "fixture-url",
                       "native_build": "not_run", "hardware_qualification": "not_run"}
        (self.root / "intake.json").write_text(json.dumps(self.intake), encoding="utf-8")
        self.selection = {"sha256": policy._sha(self.binary), "cli_version": policy.RESEARCH_CLI,
                          "runtime_version": policy.RESEARCH_RUNTIME, "receipt": str(self.receipt),
                          "archive": str(self.archive), "patches": [str(self.patch1), str(self.patch2)]}
        sdk = "/SDK"
        self.record = {"schema": "fixture", "status": "built", "returncode": 0, "target": "editor",
                       "intake": self.intake, "process_arch": "arm64", "log_sha256": policy._sha(self.log),
                       "hardware_qualification": "not_run", "sdk_path": sdk, "sdk_version": "27.0",
                       "clang": policy.APPLE_CLANG + "\nTarget: arm64-apple-darwin",
                       "scons": "4.10.1", "zstandard": "0.25.0", "path": "/usr/bin:/bin:/usr/sbin:/sbin",
                       "controlled_environment": {**dict.fromkeys(policy.CONTROLLED),
                                                  "GODOT_VERSION_STATUS": "beta2", "BUILD_NAME": "openrc_metalfx"},
                       "command": ["/python", "-m", "SCons", "-j4", "platform=macos", "arch=arm64",
                                   "target=editor", "metal=yes", "vulkan=no", "opengl3=yes", "d3d12=no",
                                   "debug_symbols=no", "optimize=speed", "lto=none", "accesskit=no",
                                   "generate_bundle=no", f"MACOS_SDK_PATH={sdk}",
                                   f"cxxflags=-isystem {sdk}/usr/include/c++/v1"],
                       "artifacts": [{"name": self.binary.name, "sha256": self.selection["sha256"],
                                      "bytes": self.binary.stat().st_size, "architectures": ["arm64"]}]}
        self.write_record()
        self.helper = SimpleNamespace(COMMIT=policy.SOURCE_COMMIT, SOURCE_URL="fixture-url", SOURCE_SHA256=policy._sha(self.archive),
                                      SCHEMA="fixture", SCONS_VERSION="4.10.1", ZSTANDARD_VERSION="0.25.0",
                                      verify_intake=self.verify_intake, expected_catalog=lambda *_a: {"file": "hash"},
                                      verify_source=lambda *_a, **_k: None)
        self.lock = {"godot": {"version": policy.OFFICIAL_VERSION, "extension_api": "4.7"}}

    def verify_intake(self, archive, root, patches):
        if (archive, root, patches) != (self.archive, self.root, [self.patch1, self.patch2]):
            raise ValueError("archive or ordered patches differ")
        return self.intake

    def write_record(self):
        self.receipt.write_text(json.dumps(self.record), encoding="utf-8")

    def identify(self, selection=None, arch=None, version=None):
        with patch.object(policy, "_helper", return_value=self.helper), patch.object(policy.os, "access", return_value=True):
            return policy.identify(self.binary, self.lock, self.selection if selection is None else selection,
                                   architectures=lambda _p: arch if arch is not None else ["arm64"],
                                   output=lambda _args: version if version is not None else policy.RESEARCH_CLI)

    def test_explicit_pin_and_retained_build_are_checked(self):
        result = self.identify()
        self.assertEqual(result["sha256"], self.selection["sha256"])
        self.assertEqual(result["research_engine"]["scope"], policy.SCOPE)
        self.assertEqual(result["research_engine"]["runtime_version"], policy.RESEARCH_RUNTIME)
        self.assertEqual(result["research_engine"]["build_receipt_sha256"], policy._sha(self.receipt))
        self.assertIn("not an attestation", policy.__doc__)

    def test_pins_are_all_or_nothing_and_exact(self):
        self.assertIsNone(policy.selection_from_args(argparse.Namespace()))
        with self.assertRaises(ValueError):
            policy.selection_from_args(argparse.Namespace(research_engine_sha256="a" * 64))
        for field, value in (("sha256", "f" * 64), ("cli_version", "4.8.beta2.official.cafc17a19"),
                             ("runtime_version", "4.8-beta2 (official)")):
            altered = copy.deepcopy(self.selection)
            altered[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.identify(altered)
        with self.assertRaises(ValueError):
            self.identify(arch=["x86_64"])
        with self.assertRaises(ValueError):
            self.identify(version="4.8.beta2.wrong")
        self.lock["godot"]["extension_api"] = "4.8"
        with self.assertRaisesRegex(ValueError, "ABI"):
            self.identify()

    def test_repeated_scalar_pin_is_rejected_instead_of_replaced(self):
        parser = argparse.ArgumentParser()
        policy.add_arguments(parser)
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parser.parse_args(["--research-engine-sha256", "a" * 64, "--research-engine-sha256", "b" * 64])

    def test_changed_artifacts_commands_or_order_refuse(self):
        mutations = [lambda r: r.update(status="running"), lambda r: r.update(returncode=1),
                     lambda r: r.update(returncode=False),
                     lambda r: r["artifacts"][0].update(sha256="c" * 64),
                     lambda r: r["command"].append("custom_modules=evil"),
                     lambda r: r["controlled_environment"].update(CC="other"),
                     lambda r: r.update(log_sha256="d" * 64)]
        original = copy.deepcopy(self.record)
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                self.record = copy.deepcopy(original)
                mutate(self.record)
                self.write_record()
                with self.assertRaises(ValueError):
                    self.identify()
        self.record = original
        self.write_record()
        changed = {**self.selection, "patches": self.selection["patches"][::-1]}
        with self.assertRaisesRegex(ValueError, "ordered patches"):
            self.identify(changed)
        self.binary.write_bytes(b"replaced")
        with self.assertRaises(ValueError):
            self.identify()

    def test_receipt_duplicate_keys_and_source_drift_refused(self):
        self.receipt.write_text('{"status":"built","status":"failed"}', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            self.identify()
        self.write_record()
        self.helper.verify_source = lambda *_a, **_k: (_ for _ in ()).throw(ValueError("source drift"))
        with self.assertRaisesRegex(ValueError, "source drift"):
            self.identify()

    def test_input_changes_during_executable_version_check_are_refused(self):
        def mutate(_args):
            self.log.write_text("changed during version check", encoding="utf-8")
            return policy.RESEARCH_CLI
        with patch.object(policy, "_helper", return_value=self.helper), patch.object(policy.os, "access", return_value=True):
            with self.assertRaisesRegex(ValueError, "changed during validation"):
                policy.identify(self.binary, self.lock, self.selection, architectures=lambda _p: ["arm64"], output=mutate)

    def test_timed_out_executable_is_a_bounded_refusal(self):
        def timeout(_args):
            raise subprocess.TimeoutExpired("engine --version", 30)
        with patch.object(policy, "_helper", return_value=self.helper), patch.object(policy.os, "access", return_value=True):
            with self.assertRaisesRegex(ValueError, "inspection failed"):
                policy.identify(self.binary, self.lock, self.selection, architectures=lambda _p: ["arm64"], output=timeout)

    def test_real_intake_rebuilds_ordered_catalog_and_rejects_build_source_drift(self):
        helper = policy._helper()
        archive = self.root / "actual-source.zip"
        with zipfile.ZipFile(archive, "w") as package:
            package.writestr(helper.SOURCE_PREFIX + "/engine/source.cpp", "old\n")
        helper.SOURCE_SHA256 = policy._sha(archive)
        patch_path = self.root / "actual.patch"
        patch_path.write_bytes(b"diff --git a/engine/source.cpp b/engine/source.cpp\n"
                               b"--- a/engine/source.cpp\n+++ b/engine/source.cpp\n"
                               b"@@ -1 +1 @@\n-old\n+new\n")
        intake_root = self.root / "real-editor"
        intake = helper.prepare(archive, intake_root, [patch_path])
        build_source = intake_root / "build-source-editor"
        shutil.copytree(intake_root / "source", build_source, ignore=shutil.ignore_patterns(".git"))
        binary = build_source / "bin/godot.macos.editor.arm64"
        binary.parent.mkdir()
        binary.write_bytes(b"selected editor")
        log = intake_root / "build-editor.log"
        log.write_text("captured build output", encoding="utf-8")
        receipt = intake_root / "build-editor.json"
        selection = {"sha256": policy._sha(binary), "cli_version": policy.RESEARCH_CLI,
                     "runtime_version": policy.RESEARCH_RUNTIME, "receipt": str(receipt),
                     "archive": str(archive), "patches": [str(patch_path)]}
        record = copy.deepcopy(self.record)
        record.update(schema=helper.SCHEMA, intake=intake, log_sha256=policy._sha(log),
                      artifacts=[{"name": binary.name, "sha256": selection["sha256"],
                                  "bytes": binary.stat().st_size, "architectures": ["arm64"]}])
        receipt.write_text(json.dumps(record), encoding="utf-8")
        with patch.object(policy, "_helper", return_value=helper), patch.object(policy.os, "access", return_value=True):
            args = (binary, self.lock, selection)
            kwargs = {"architectures": lambda _p: ["arm64"], "output": lambda _c: policy.RESEARCH_CLI}
            self.assertEqual(policy.identify(*args, **kwargs)["research_engine"]["source_commit"], policy.SOURCE_COMMIT)
            (build_source / "engine/source.cpp").write_text("changed\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "source drift"):
                policy.identify(*args, **kwargs)


if __name__ == "__main__":
    unittest.main()
