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
        self.reference = self.root / "official-godot"
        self.reference.write_bytes(b"fixture official editor")
        official_pin = patch.object(policy, "OFFICIAL_ARM64_SHA256", policy._sha(self.reference))
        official_pin.start()
        self.addCleanup(official_pin.stop)
        self.archive = self.root / "source.zip"
        self.archive.write_bytes(b"fixture source")
        self.api = self.root / "godot-cpp/gdextension/extension_api-4-7.json"
        self.api.parent.mkdir(parents=True)
        self.api.write_text("{}", encoding="utf-8")
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
                          "archive": str(self.archive), "extension_api": str(self.api),
                          "reference_godot": str(self.reference),
                          "patches": [str(self.patch1), str(self.patch2)]}
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
                                      verify_source=lambda *_a, **_k: None, patch_paths=lambda _p: {"render/file.cpp"})
        self.lock = {"godot": {"version": policy.OFFICIAL_VERSION, "extension_api": "4.7"},
                     "godot_cpp": {"commit": policy.GODOT_CPP_COMMIT}}
        self.api_proof = {"checkout": str(self.api.parent.parent), "commit": policy.GODOT_CPP_COMMIT,
                          "blob": "b" * 40, "sha256": policy._sha(self.api)}
        self.dump = {"header": {"version_major": 4, "version_minor": 8, "version_patch": 0,
                                "version_status": "beta2", "version_build": "official", "precision": "single"}}
        self.dump.update({name: [{"name": "fixture"}] for name in (
            "global_constants", "global_enums", "utility_functions", "builtin_classes",
            "classes", "singletons", "native_structures")})

    def verify_intake(self, archive, root, patches):
        if (archive, root, patches) != (self.archive, self.root, [self.patch1, self.patch2]):
            raise ValueError("archive or ordered patches differ")
        return self.intake

    def write_record(self):
        self.receipt.write_text(json.dumps(self.record), encoding="utf-8")

    def output(self, command, *, cwd=None, expected_diagnostic=None):
        if "--version" in command:
            return policy.OFFICIAL_VERSION if command[0] == str(self.reference) else policy.RESEARCH_CLI
        if "--dump-extension-api" in command:
            self.assertIsNotNone(cwd)
            (Path(cwd) / "extension_api.json").write_text(json.dumps(self.dump), encoding="utf-8")
            return "Dumping Extension API"
        self.assertIn("--validate-extension-api", command)
        if expected_diagnostic is not None:
            self.assertEqual(expected_diagnostic, policy.CONTROL_DIAGNOSTIC)
            self.assertEqual(Path(command[-1]).name, "incompatible_extension_api.json")
            return expected_diagnostic
        return ""

    def identify(self, selection=None, arch=None, version=None, output=None):
        def commands(command, *, cwd=None, expected_diagnostic=None):
            if version is not None and command == [str(self.binary), "--version"]:
                return version
            return self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic)
        with patch.object(policy, "_helper", return_value=self.helper), patch.object(policy.os, "access", return_value=True), \
             patch.object(policy, "extension_api_identity", return_value=self.api_proof):
            return policy.identify(self.binary, self.lock, self.selection if selection is None else selection,
                                   architectures=lambda _p: arch if arch is not None else ["arm64"],
                                   output=output or commands)

    def test_explicit_pin_and_retained_build_are_checked(self):
        result = self.identify()
        self.assertEqual(result["sha256"], self.selection["sha256"])
        self.assertEqual(result["research_engine"]["scope"], policy.SCOPE)
        self.assertEqual(result["research_engine"]["runtime_version"], policy.RESEARCH_RUNTIME)
        self.assertEqual(result["research_engine"]["build_receipt_sha256"], policy._sha(self.receipt))
        self.assertEqual(result["research_engine"]["binding_api_4_7"], self.api_proof)
        compatibility = result["research_engine"]["compatibility_api_4_8"]
        self.assertEqual(compatibility["reference"]["sha256"], policy.OFFICIAL_ARM64_SHA256)
        self.assertEqual(compatibility["validation"], "passed without diagnostics")
        self.assertEqual(compatibility["validator_control"]["official"], "detected")
        self.assertEqual(compatibility["validator_control"]["research"], "detected")
        self.assertIn("not an attestation", policy.__doc__)

    def test_pins_are_all_or_nothing_and_exact(self):
        self.assertIsNone(policy.selection_from_args(argparse.Namespace()))
        with self.assertRaises(ValueError):
            policy.selection_from_args(argparse.Namespace(research_engine_sha256="a" * 64))
        parser = argparse.ArgumentParser()
        policy.add_arguments(parser)
        without_reference = ["--research-engine-sha256", self.selection["sha256"],
                             "--research-engine-cli-version", policy.RESEARCH_CLI,
                             "--research-engine-runtime-version", policy.RESEARCH_RUNTIME,
                             "--research-engine-build-receipt", str(self.receipt),
                             "--research-engine-archive", str(self.archive),
                             "--research-engine-extension-api", str(self.api),
                             "--research-engine-patch", str(self.patch1)]
        with self.assertRaisesRegex(ValueError, "official reference"):
            policy.selection_from_args(parser.parse_args(without_reference))
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
        def mutate(command, *, cwd=None, expected_diagnostic=None):
            self.log.write_text("changed during version check", encoding="utf-8")
            return self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic)
        with patch.object(policy, "_helper", return_value=self.helper), patch.object(policy.os, "access", return_value=True), \
             patch.object(policy, "extension_api_identity", return_value=self.api_proof):
            with self.assertRaisesRegex(ValueError, "changed during validation"):
                policy.identify(self.binary, self.lock, self.selection, architectures=lambda _p: ["arm64"], output=mutate)

    def test_timed_out_executable_is_a_bounded_refusal(self):
        def timeout(_args):
            raise subprocess.TimeoutExpired("engine --version", 30)
        with patch.object(policy, "_helper", return_value=self.helper), patch.object(policy.os, "access", return_value=True), \
             patch.object(policy, "extension_api_identity", return_value=self.api_proof):
            with self.assertRaisesRegex(ValueError, "inspection failed"):
                policy.identify(self.binary, self.lock, self.selection, architectures=lambda _p: ["arm64"], output=timeout)

    def test_api_checkout_binds_commit_blob_and_clean_state(self):
        blob = "c" * 40
        def command(_checkout, *args):
            return {("rev-parse", "--show-toplevel"): str(self.api.parent.parent),
                    ("rev-parse", "--verify", "HEAD"): policy.GODOT_CPP_COMMIT,
                    ("status", "--porcelain", "--untracked-files=no"): "",
                    ("rev-parse", f"{policy.GODOT_CPP_COMMIT}:gdextension/extension_api-4-7.json"): blob,
                    ("hash-object", "--no-filters", str(self.api)): blob}[args]
        with patch.object(policy, "_git_text", side_effect=command):
            self.assertEqual(policy.extension_api_identity(self.api, self.lock)["blob"], blob)
        def dirty(_checkout, *args):
            return " M gdextension/extension_api-4-7.json" if args[0] == "status" else command(_checkout, *args)
        with patch.object(policy, "_git_text", side_effect=dirty), self.assertRaisesRegex(ValueError, "checkout"):
            policy.extension_api_identity(self.api, self.lock)
        def wrong_blob(_checkout, *args):
            return "d" * 40 if args[0] == "hash-object" else command(_checkout, *args)
        with patch.object(policy, "_git_text", side_effect=wrong_blob), self.assertRaisesRegex(ValueError, "blob"):
            policy.extension_api_identity(self.api, self.lock)

    def test_c_interface_delta_and_failed_api_validation_refuse(self):
        self.helper.patch_paths = lambda _patches: {"core/extension/gdextension_interface.json"}
        with self.assertRaisesRegex(ValueError, "core/extension"):
            self.identify()
        self.helper.patch_paths = lambda _patches: {"servers/rendering/renderer.cpp"}
        calls = []
        def checked(command, *, cwd=None, expected_diagnostic=None):
            calls.append(command)
            if "--validate-extension-api" in command and expected_diagnostic is None:
                raise subprocess.CalledProcessError(1, command)
            return self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic)
        with patch.object(policy, "_helper", return_value=self.helper), patch.object(policy.os, "access", return_value=True), \
             patch.object(policy, "extension_api_identity", return_value=self.api_proof):
            with self.assertRaisesRegex(ValueError, "4.8 extension API compatibility check failed"):
                policy.identify(self.binary, self.lock, self.selection, architectures=lambda _p: ["arm64"], output=checked)
        self.assertEqual(calls[-1][:3], [str(self.binary), "--headless", "--validate-extension-api"])
        self.assertEqual(Path(calls[-1][3]).name, "extension_api.json")

    def test_reference_pin_version_and_architecture_are_independent(self):
        self.reference.write_bytes(b"wrong official editor")
        with self.assertRaisesRegex(ValueError, "independent macOS SHA-256"):
            self.identify()
        self.reference.write_bytes(b"fixture official editor")
        def wrong_version(command, *, cwd=None, expected_diagnostic=None):
            return ("4.8.beta2.official.other" if command == [str(self.reference), "--version"]
                    else self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic))
        with self.assertRaisesRegex(ValueError, "Official reference Godot architecture or version"):
            self.identify(output=wrong_version)
        with patch.object(policy, "_helper", return_value=self.helper), patch.object(policy.os, "access", return_value=True), \
             patch.object(policy, "extension_api_identity", return_value=self.api_proof):
            with self.assertRaisesRegex(ValueError, "Official reference Godot architecture or version"):
                policy.identify(self.binary, self.lock, self.selection,
                                architectures=lambda path: ["x86_64"] if path == self.reference else ["arm64"],
                                output=self.output)

    def test_fresh_official_dump_and_zero_exit_incompatibilities(self):
        generated = []
        def checked(command, *, cwd=None, expected_diagnostic=None):
            if "--dump-extension-api" in command:
                generated.append(Path(cwd))
                self.assertFalse((Path(cwd) / "extension_api.json").exists())
            if "--validate-extension-api" in command and expected_diagnostic is None:
                self.assertEqual(command[0], str(self.binary))
                self.assertEqual(Path(command[-1]).parent, generated[-1])
                return "Validate extension JSON: API was removed: classes/Example"
            return self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic)
        for _ in range(2):
            with self.assertRaisesRegex(ValueError, "incompatibility or engine error"):
                self.identify(output=checked)
        self.assertNotEqual(generated[0], generated[1])
        self.assertTrue(all(not path.exists() for path in generated))

    def test_both_validators_must_detect_the_specific_control_before_clean_validation(self):
        calls = []
        def checked(command, *, cwd=None, expected_diagnostic=None):
            if "--validate-extension-api" in command:
                calls.append((command[0], Path(command[-1]).name, expected_diagnostic))
            return self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic)
        result = self.identify(output=checked)
        self.assertEqual(calls, [
            (str(self.reference), "incompatible_extension_api.json", policy.CONTROL_DIAGNOSTIC),
            (str(self.binary), "incompatible_extension_api.json", policy.CONTROL_DIAGNOSTIC),
            (str(self.binary), "extension_api.json", None)])
        self.assertEqual(result, self.identify(output=checked))
        for validator in (self.reference, self.binary):
            def noop(command, *, cwd=None, expected_diagnostic=None):
                if expected_diagnostic and command[0] == str(validator):
                    return ""
                return self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic)
            with self.subTest(validator=validator), self.assertRaisesRegex(ValueError, "did not detect"):
                self.identify(output=noop)
        def extra_error(command, *, cwd=None, expected_diagnostic=None):
            result = self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic)
            return result + "\nERROR: unrelated problem" if expected_diagnostic else result
        with self.assertRaisesRegex(ValueError, "unrelated diagnostic"):
            self.identify(output=extra_error)

    def test_control_refuses_collisions_and_changes_to_either_api(self):
        self.dump["classes"].append({"name": policy.CONTROL_CLASS})
        with self.assertRaisesRegex(ValueError, "not uniquely absent"):
            self.identify()
        self.dump["classes"].pop()
        for altered in ("extension_api.json", "incompatible_extension_api.json"):
            def mutate(command, *, cwd=None, expected_diagnostic=None):
                result = self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic)
                if expected_diagnostic:
                    path = Path(command[-1]).with_name(altered)
                    path.write_text(path.read_text(encoding="utf-8") + " ", encoding="utf-8")
                return result
            with self.subTest(altered=altered), self.assertRaisesRegex(ValueError, "reference or control changed"):
                self.identify(output=mutate)

    def test_missing_invalid_oversized_and_changed_dumps_are_refused(self):
        def no_dump(command, *, cwd=None, expected_diagnostic=None):
            return ("Dumping Extension API" if "--dump-extension-api" in command
                    else self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic))
        with self.assertRaisesRegex(ValueError, "missing, redirected or oversized"):
            self.identify(output=no_dump)
        self.dump["header"]["version_minor"] = 7
        with self.assertRaisesRegex(ValueError, "Invalid official 4.8"):
            self.identify()
        self.dump["header"]["version_minor"] = 8
        self.dump["classes"] = []
        with self.assertRaisesRegex(ValueError, "Invalid official 4.8"):
            self.identify()
        self.dump["classes"] = [{"name": "fixture"}]
        with patch.object(policy, "MAX_API_BYTES", 8), self.assertRaisesRegex(ValueError, "oversized"):
            self.identify()
        def mutate_dump(command, *, cwd=None, expected_diagnostic=None):
            if "--validate-extension-api" in command and expected_diagnostic is None:
                path = Path(command[-1])
                path.write_text(path.read_text(encoding="utf-8") + " ", encoding="utf-8")
                return ""
            return self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic)
        with self.assertRaisesRegex(ValueError, "reference or control changed during validation"):
            self.identify(output=mutate_dump)

    def test_reference_replacement_during_validation_is_refused(self):
        def replace_reference(command, *, cwd=None, expected_diagnostic=None):
            if "--validate-extension-api" in command and expected_diagnostic is None:
                self.reference.write_bytes(b"changed official editor")
                return ""
            return self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic)
        with self.assertRaisesRegex(ValueError, "provenance changed during validation"):
            self.identify(output=replace_reference)

    def test_dyld_overrides_are_rejected_and_children_are_cleaned(self):
        with patch.dict(policy.os.environ, {"DYLD_INSERT_LIBRARIES": "/tmp/inject", "ASAN_OPTIONS": "bad"}):
            with self.assertRaisesRegex(ValueError, "without DYLD"):
                policy.reject_dyld_environment()
            clean = policy.clean_child_environment()
            self.assertNotIn("DYLD_INSERT_LIBRARIES", clean)
            self.assertNotIn("ASAN_OPTIONS", clean)
            with policy.clean_process_environment():
                self.assertNotIn("DYLD_INSERT_LIBRARIES", policy.os.environ)
            self.assertEqual(policy.os.environ["DYLD_INSERT_LIBRARIES"], "/tmp/inject")

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
                     "archive": str(archive), "extension_api": str(self.api),
                     "reference_godot": str(self.reference), "patches": [str(patch_path)]}
        record = copy.deepcopy(self.record)
        record.update(schema=helper.SCHEMA, intake=intake, log_sha256=policy._sha(log),
                      artifacts=[{"name": binary.name, "sha256": selection["sha256"],
                                  "bytes": binary.stat().st_size, "architectures": ["arm64"]}])
        receipt.write_text(json.dumps(record), encoding="utf-8")
        with patch.object(policy, "_helper", return_value=helper), patch.object(policy.os, "access", return_value=True), \
             patch.object(policy, "extension_api_identity", return_value=self.api_proof):
            args = (binary, self.lock, selection)
            kwargs = {"architectures": lambda _p: ["arm64"], "output": self.output}
            self.assertEqual(policy.identify(*args, **kwargs)["research_engine"]["source_commit"], policy.SOURCE_COMMIT)
            def incompatible(command, *, cwd=None, expected_diagnostic=None):
                if "--validate-extension-api" in command and expected_diagnostic is None:
                    return "Validate extension JSON: API was removed: classes/Example"
                return self.output(command, cwd=cwd, expected_diagnostic=expected_diagnostic)
            with self.assertRaisesRegex(ValueError, "incompatibility or engine error"):
                policy.identify(*args, architectures=kwargs["architectures"], output=incompatible)
            (build_source / "engine/source.cpp").write_text("changed\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "source drift"):
                policy.identify(*args, **kwargs)


if __name__ == "__main__":
    unittest.main()
