#!/usr/bin/env python3
"""Offline policy and failure-path checks for the Mac research builder."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC = importlib.util.spec_from_file_location("nk3_macos_builder_test", HERE / "build_macos.py")
mac = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mac)
SCRATCH = ROOT / "tmp/macos-port/builder"


class ScratchCase(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="unit-", dir=SCRATCH)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()


class BuildPolicy(ScratchCase):
    def setUp(self):
        super().setUp()
        self.sdk = self.root / "SDK"
        (self.sdk / "usr/include/c++/v1").mkdir(parents=True)
        (self.sdk / "usr/include/c++/v1/vector").write_text("header")
        self.compiler = self.root / "bin/clang++"
        self.compiler.parent.mkdir()
        self.compiler.write_text("c++ driver")
        self.compiler.with_name("clang").write_text("c driver")
        self.source = self.root / "src"
        self.source.mkdir()
        (self.source / "nk_kernel.cpp").write_text("// source")
        self.env = {"PATH": str(self.compiler.parent)}

    def entry(self):
        return {"directory": str(self.root), "file": str(self.source / "nk_kernel.cpp"),
                "arguments": [str(self.compiler), *mac._common_flags(self.sdk), "-c", str(self.source / "nk_kernel.cpp")]}

    def validate(self, rows):
        path = self.root / "compile_commands.json"
        path.write_text(json.dumps(rows))
        with patch.object(mac.locked, "SOURCES", self.source):
            return mac.validate_compdb(path, self.compiler, self.sdk, self.env)

    def test_compile_database_requires_strict_flags_for_all_translation_units(self):
        binding = self.entry()
        binding["file"] = str(self.root / "generated.cpp")
        self.assertEqual(self.validate([self.entry(), binding])["entries"], 2)
        for flag in ("-ffast-math", "-Ofast", "-ffp-contract=fast", "-std=c++20", "-flto=thin",
                     "-fno-exceptions", "-fbuiltin-sin", "-DREAL_T_IS_DOUBLE", "-ffp-model=fast"):
            with self.subTest(flag=flag):
                bad = copy.deepcopy(binding)
                bad["arguments"].append(flag)
                with self.assertRaises(ValueError):
                    self.validate([self.entry(), bad])
        for flag in ("-fno-fast-math", "-ffp-contract=off", "-fno-builtin", "-fno-lto"):
            with self.subTest(missing=flag):
                bad = self.entry()
                bad["arguments"].remove(flag)
                with self.assertRaises(ValueError):
                    self.validate([bad])

    def test_exception_policy_uses_final_driver_option(self):
        row = self.entry()
        row["arguments"].insert(1, "-fno-exceptions")
        self.validate([row])
        row["arguments"].append("-fno-exceptions")
        with self.assertRaisesRegex(ValueError, "exception support"):
            self.validate([row])

    def test_compile_database_rejects_wrong_arch_sdk_floor_driver_and_source(self):
        for old, new in (("arm64", "x86_64"), (str(self.sdk), str(self.root)),
                         ("-mmacosx-version-min=11.0", "-mmacosx-version-min=12.0"),
                         (str(self.compiler), str(self.compiler.with_name("clang")))):
            with self.subTest(old=old):
                row = self.entry()
                row["arguments"][row["arguments"].index(old)] = new
                with self.assertRaises(ValueError):
                    self.validate([row])
        with self.assertRaises(ValueError):
            self.validate([])
        row = self.entry()
        row["file"] = str(self.root / "other.cpp")
        with self.assertRaises(ValueError):
            self.validate([row])
        with self.assertRaises(ValueError):
            self.validate([self.entry(), self.entry()])

    def test_actual_commands_must_match_candidate_or_mutant_variant(self):
        path = self.root / "variants.json"
        candidate = self.entry()
        mutant = copy.deepcopy(candidate)
        mutant["arguments"] += ["-DNK_MUTATION=1"]
        path.write_text(json.dumps([candidate]))
        mac.validate_variant_compdb(path, False)
        with self.assertRaises(ValueError):
            mac.validate_variant_compdb(path, True)
        path.write_text(json.dumps([mutant]))
        mac.validate_variant_compdb(path, True)
        with self.assertRaises(ValueError):
            mac.validate_variant_compdb(path, False)
        mutant["arguments"] += ["-D", "NK_DEBUG_ECM"]
        path.write_text(json.dumps([mutant]))
        with self.assertRaises(ValueError):
            mac.validate_variant_compdb(path, True)

    def test_sconstruct_applies_flags_before_bindings_and_after_import(self):
        lock = mac.locked.load_lock()
        lock["_sdk_path"] = str(self.sdk)
        flags = mac._common_flags(self.sdk)
        script = mac.make_sconstruct(self.root / "cpp", self.root, self.root / "profile.json", lock, flags,
                                     self.compiler, "openrc_native_kernel")
        self.assertEqual(script.count("env.Append(CCFLAGS="), 2)
        self.assertLess(script.index("env.Append(CCFLAGS="), script.index("env = SConscript("))
        self.assertGreater(script.rindex("env.Append(CCFLAGS="), script.index("env = SConscript("))
        self.assertIn("-Wl,-install_name,@rpath/libopenrc_native_kernel.dylib", script)
        self.assertIn('"openrc_native_kernel"', script)

    def test_link_command_is_verified_from_actual_log(self):
        import shlex
        library = self.root / "libopenrc_native_kernel.dylib"
        args = [str(self.compiler), "-o", str(library), "-fno-lto", "-arch", "arm64", "-isysroot", str(self.sdk),
                "-mmacosx-version-min=11.0", f"-Wl,-install_name,@rpath/{library.name}"]
        log = self.root / "build.log"
        log.write_text(shlex.join(args) + "\n")
        self.assertEqual(mac.validate_link_command(log, library, self.sdk, self.compiler, self.env), args)
        log.write_text(shlex.join(args[:-1]) + "\n")
        with self.assertRaises(ValueError):
            mac.validate_link_command(log, library, self.sdk, self.compiler, self.env)

    def test_environment_removes_ambient_build_and_loader_overrides(self):
        with patch.dict(os.environ, {"CXXFLAGS": "-ffast-math", "DYLD_INSERT_LIBRARIES": "bad", "CPATH": "bad",
                                     "DEVELOPER_DIR": "selected", "PATH": "base"}, clear=True):
            env = mac.clean_build_environment(self.compiler, self.sdk)
        self.assertNotIn("CXXFLAGS", env)
        self.assertNotIn("DYLD_INSERT_LIBRARIES", env)
        self.assertNotIn("CPATH", env)
        self.assertEqual(env["DEVELOPER_DIR"], "selected")
        self.assertEqual(env["CXX"], str(self.compiler))
        self.assertEqual(env["MACOSX_DEPLOYMENT_TARGET"], "11.0")

    def test_disk_reserve_has_a_non_overridable_floor(self):
        class Usage:
            free = 3 * 1024**3
        with patch.object(mac.shutil, "disk_usage", return_value=Usage()):
            self.assertEqual(mac.check_free_space(self.root, 2.0), Usage.free)
            for value in (0, 0.49, float("nan"), float("inf"), 4):
                with self.subTest(minimum=value), self.assertRaises(ValueError):
                    mac.check_free_space(self.root, value)

    def test_toolchain_requires_native_host_exact_versions_and_headers(self):
        def outputs(command, **_kwargs):
            values = {("sysctl", "-in", "sysctl.proc_translated"): "0",
                      ("xcrun", "--sdk", "macosx", "--show-sdk-path"): str(self.sdk),
                      ("xcrun", "--sdk", "macosx", "--show-sdk-version"): "27.0",
                      ("xcrun", "--sdk", "macosx", "--find", "clang++"): str(self.compiler),
                      ("xcrun", "--sdk", "macosx", "--find", "clang"): str(self.compiler.with_name("clang")),
                      (str(self.compiler), "--version"): mac.APPLE_CLANG + "\nTarget: arm64-apple-darwin",
                      (str(self.compiler), "-dumpmachine"): "arm64-apple-darwin26.0.0",
                      ("xcode-select", "-p"): "/selected", ("sw_vers", "-productVersion"): "27.0.1",
                      ("sw_vers", "-buildVersion"): "26A434"}
            return values[tuple(command)]
        with patch.object(mac.locked, "host_platform_name", return_value="macos"), \
             patch.object(mac.locked, "host_arch_name", return_value="arm64"), \
             patch.object(mac, "_output", side_effect=outputs):
            actual = mac.host_toolchain()
            self.assertEqual(actual["sdk_version"], "27.0")
            self.assertEqual(actual["os_build"], "26A434")
            self.assertEqual(actual["compiler"], str(self.compiler))
            (self.sdk / "usr/include/c++/v1/vector").unlink()
            with self.assertRaisesRegex(ValueError, "headers"):
                mac.host_toolchain()
        with patch.object(mac.locked, "host_platform_name", return_value="macos"), \
             patch.object(mac.locked, "host_arch_name", return_value="arm64"), \
             patch.object(mac, "_output", return_value="1"):
            with self.assertRaisesRegex(ValueError, "Rosetta"):
                mac.host_toolchain()
        with patch.object(mac.locked, "host_platform_name", return_value="linux"):
            with self.assertRaisesRegex(ValueError, "native macOS"):
                mac.host_toolchain()

    def test_godot_identity_requires_version_and_arm_slice(self):
        exe = self.root / "Godot"
        exe.write_text("engine")
        lock = mac.locked.load_lock()
        with patch.object(mac.os, "access", return_value=True), \
             patch.object(mac, "architectures", return_value=["arm64"]), \
             patch.object(mac, "_output", return_value=lock["godot"]["version"]):
            identity = mac.godot_identity(exe, lock)
            self.assertEqual(identity["sha256"], mac.nk.sha256_file(exe))
        with patch.object(mac.os, "access", return_value=True), patch.object(mac, "architectures", return_value=["x86_64"]):
            with self.assertRaisesRegex(ValueError, "ARM64"):
                mac.godot_identity(exe, lock)


class MachOPolicy(ScratchCase):
    def test_undefined_symbols_accepts_actual_apple_names_and_bsd_columns(self):
        for output, expected in [
                ("_sin\n_pow\ndyld_stub_binder\n", ["_pow", "_sin", "dyld_stub_binder"]),
                ("                 U _sin\nU _pow\n", ["_pow", "_sin"])]:
            with self.subTest(output=output), patch.object(mac, "_output", return_value=output):
                self.assertEqual(mac.undefined_symbols(self.root / "kernel.dylib"), expected)
        for output in ["", "not a symbol\n", "library.dylib:\n"]:
            with self.subTest(output=output), patch.object(mac, "_output", return_value=output):
                with self.assertRaises(ValueError):
                    mac.undefined_symbols(self.root / "kernel.dylib")

    COMMANDS = """Load command 7
          cmd LC_BUILD_VERSION
      cmdsize 32
     platform MACOS
        minos 11.0
          sdk 27.0
       ntools 1
"""

    def test_build_version_and_math_imports_fail_closed(self):
        self.assertEqual(mac.build_version(self.COMMANDS)["sdk"], "27.0")
        for change in (self.COMMANDS.replace("11.0", "12.0"), self.COMMANDS.replace("27.0", "26.0"),
                       self.COMMANDS.replace("MACOS", "IOS"), self.COMMANDS + self.COMMANDS, ""):
            with self.subTest(change=change), self.assertRaises(ValueError):
                mac.build_version(change)
        self.assertEqual(mac.math_imports(["_sin", "_cos", "_pow", "___sincos_stret", "_malloc"]),
                         ["___sincos_stret", "_cos", "_pow", "_sin"])

    def test_inspection_requires_matching_uuids_system_dependencies_and_separate_math(self):
        library = self.root / "libopenrc_native_kernel.dylib"
        library.write_bytes(b"library")
        dsym = self.root / "symbols"
        dsym.write_bytes(b"symbols")
        install = f"{library}:\n@rpath/{library.name}"
        def output(command, **_kwargs):
            return self.COMMANDS if "-l" in command else install
        with patch.object(mac, "architectures", return_value=["arm64"]), patch.object(mac, "_output", side_effect=output), \
             patch.object(mac, "dependencies", return_value=[f"@rpath/{library.name}", "/usr/lib/libSystem.B.dylib"]), \
             patch.object(mac, "undefined_symbols", return_value=["_sin", "_cos", "_pow"]), \
             patch.object(mac, "uuid_map", return_value={"arm64": "ABC"}):
            self.assertEqual(mac.inspect_library(library, dsym, self.root)["uuid"], {"arm64": "ABC"})
            with patch.object(mac, "dependencies", return_value=[f"@rpath/{library.name}", "/tmp/other.dylib"]):
                with self.assertRaisesRegex(ValueError, "non-system"):
                    mac.inspect_library(library, dsym, self.root)
            with patch.object(mac, "undefined_symbols", return_value=["_sin", "_cos", "_pow", "___sincos_stret"]):
                with self.assertRaisesRegex(ValueError, "sincos"):
                    mac.inspect_library(library, dsym, self.root)
            with patch.object(mac, "uuid_map", side_effect=[{"arm64": "ABC"}, {"arm64": "DEF"}]):
                with self.assertRaisesRegex(ValueError, "UUID"):
                    mac.inspect_library(library, dsym, self.root)

    def test_fixed_wing_roster_reuses_the_shared_verifier(self):
        self.assertEqual(mac.verification_roster(), {"base_oracle": "results-[0-9]*.json", **{
            key: value for key, value in mac.nk.VERIFICATIONS.items()
            if key not in {"helicopter", "helicopter_stage"}}})
        with patch.object(mac.nk, "verification_error", return_value="invalid") as verify:
            self.assertEqual(mac.verification_error("stage_oracle", {}), "invalid")
            verify.assert_called_once_with("stage_oracle", {})
        self.assertEqual(mac.verification_error("invented", {}), "unknown verification kind")
        self.assertEqual(mac.verification_error("helicopter", {}), "unknown verification kind")


class SigningPolicy(ScratchCase):
    def setUp(self):
        super().setUp()
        self.fingerprint = "A1" * 20
        self.team = "AB12CDE345"
        self.authority = f"Developer ID Application: Example Corp ({self.team})"
        self.selection = {**mac.signing_selection(self.fingerprint, self.team), "authority": self.authority}
        self.details = (f"Executable=/some/library\nAuthority={self.authority}\n"
                        "Authority=Developer ID Certification Authority\nAuthority=Apple Root CA\n"
                        f"Timestamp=Nov 13, 2026 at 10:00:00\nTeamIdentifier={self.team}")
        self.library = self.root / "library.dylib"

    def record(self, details=None, selection=None):
        def run(command, **_kwargs):
            return SimpleNamespace(stderr=(self.details if details is None else details), stdout="")
        with patch.object(mac.subprocess, "run", side_effect=run):
            return mac.inspect_signing(self.library, selection or self.selection)

    def test_exact_fingerprint_and_team_are_both_required(self):
        self.assertEqual(mac.signing_selection(None, None), {"kind": "ad-hoc"})
        self.assertEqual(mac.signing_selection(self.fingerprint.lower(), self.team)["identity_sha1"], self.fingerprint)
        for fingerprint, team in ((None, self.team), (self.fingerprint, None),
                                  ("Developer ID Application: Example Corp", self.team),
                                  (self.fingerprint + "0", self.team),
                                  ("z" * 40, self.team), (self.fingerprint + " ", self.team),
                                  (self.fingerprint, self.team.lower()), (self.fingerprint, "A" * 9),
                                  (self.fingerprint, 'ABC"EFGHIJ')):
            with self.subTest(fingerprint=fingerprint, team=team), self.assertRaises(ValueError):
                mac.signing_selection(fingerprint, team)

    def test_cli_rejects_incomplete_selection_before_build_or_install(self):
        for options in (["--signing-identity", self.fingerprint], ["--team-id", self.team],
                        ["--signing-identity", "Developer ID Application: Example", "--team-id", self.team]):
            for install in ([], ["--install-app"]):
                with self.subTest(options=options, install=install), \
                     patch.object(mac.sys, "argv", ["builder", "--godot", "Godot", *options, *install]), \
                     patch.object(mac.sys, "stderr", new_callable=io.StringIO), \
                     patch.object(mac, "build") as build, patch.object(mac, "install_app") as install_app:
                    self.assertEqual(mac.main(), 1)
                    build.assert_not_called()
                    install_app.assert_not_called()
        argv = ["builder", "--godot", "Godot", "--install-app", "--signing-identity", self.fingerprint.lower(),
                "--team-id", self.team]
        with patch.object(mac.sys, "argv", argv), patch.object(mac, "install_app", return_value=0) as install_app:
            self.assertEqual(mac.main(), 0)
            self.assertEqual(install_app.call_args.kwargs["expected_signing"],
                             mac.signing_selection(self.fingerprint, self.team))

    def test_keychain_lookup_requires_one_matching_developer_application_identity(self):
        selection = mac.signing_selection(self.fingerprint, self.team)
        valid = f'  1) {self.fingerprint} "{self.authority}"\n'
        with patch.object(mac.subprocess, "run", return_value=SimpleNamespace(stdout=valid)) as run:
            self.assertEqual(mac.resolve_signing_identity(selection), self.selection)
            self.assertEqual(run.call_args.args[0], ["security", "find-identity", "-p", "codesigning", "-v"])
        with patch.object(mac.subprocess, "run") as run:
            self.assertEqual(mac.resolve_signing_identity({"kind": "ad-hoc"}), {"kind": "ad-hoc"})
            run.assert_not_called()
        for output in ("", valid + valid, valid.replace(self.fingerprint, "B" * 40),
                       valid.replace(self.team, "ZX98ABCDE7"),
                       valid.replace("Developer ID Application", "Apple Development"),
                       valid.replace("Developer ID Application", "Developer ID Installer")):
            with self.subTest(output=output), patch.object(mac.subprocess, "run", return_value=SimpleNamespace(stdout=output)):
                with self.assertRaises(ValueError):
                    mac.resolve_signing_identity(selection)
        with patch.object(mac.subprocess, "run", side_effect=mac.subprocess.CalledProcessError(1, "security")):
            with self.assertRaises(mac.subprocess.CalledProcessError):
                mac.resolve_signing_identity(selection)

    def test_strict_verification_binds_apple_chain_team_fingerprint_and_timestamp(self):
        with patch.object(mac.subprocess, "run", return_value=SimpleNamespace(stderr=self.details)) as run:
            receipt = mac.inspect_signing(self.library, self.selection)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands[0], ["codesign", "--verify", "--strict", str(self.library)])
        self.assertEqual(commands[1][:4], ["codesign", "--verify", "--strict", "-R"])
        requirement = commands[1][4]
        for clause in ("anchor apple generic", "field.1.2.840.113635.100.6.2.6",
                       "field.1.2.840.113635.100.6.1.13", f'certificate leaf[subject.OU] = "{self.team}"',
                       f'certificate leaf = H"{self.fingerprint}"'):
            self.assertIn(clause, requirement)
        self.assertEqual(receipt["requirement"], requirement)
        self.assertEqual(receipt["timestamp"], "Nov 13, 2026 at 10:00:00")
        self.assertEqual(receipt["authorities"][0], self.authority)
        self.assertFalse(receipt["notarized"])
        self.assertEqual(run.call_args_list[-1].args[0], ["codesign", "-dv", "--verbose=4", str(self.library)])
        for failed_call in (1, 2):
            calls = []
            def fail(command, **_kwargs):
                calls.append(command)
                if len(calls) == failed_call:
                    raise mac.subprocess.CalledProcessError(1, command)
                return SimpleNamespace(stderr=self.details)
            with self.subTest(failed_call=failed_call), patch.object(mac.subprocess, "run", side_effect=fail):
                with self.assertRaises(mac.subprocess.CalledProcessError):
                    mac.inspect_signing(self.library, self.selection)

    def test_signature_metadata_rejects_wrong_team_type_and_missing_timestamp(self):
        for details in (self.details.replace(self.team, "ZX98ABCDE7"),
                        self.details.replace("Developer ID Application", "Developer ID Installer"),
                        self.details.replace("Timestamp=Nov 13, 2026 at 10:00:00\n", ""),
                        self.details.replace("Timestamp=Nov 13, 2026 at 10:00:00", "Timestamp=none"),
                        self.details + "\nTimestamp=duplicate", self.details + "\nSignature=adhoc",
                        self.details + f"\nTeamIdentifier={self.team}"):
            with self.subTest(details=details), self.assertRaises(ValueError):
                self.record(details)

    def test_pair_enforces_selection_and_immutable_receipt_metadata(self):
        adhoc = {"kind": "ad-hoc", "verified": True, "details": "Signature=adhoc", "notarized": False}
        self.assertIsNone(mac.validate_signing_pair({"signing": adhoc}, {"signing": copy.deepcopy(adhoc)}))
        candidate = self.record()
        mutant = self.record(self.details.replace("10:00:00", "10:00:01"))
        self.assertIsNone(mac.validate_signing_pair({"signing": candidate}, {"signing": mutant}))
        different = {**self.selection, "identity_sha1": "B2" * 20}
        other = self.record(selection=different)
        for invalid in (adhoc, other, {**mutant, "team_id": "ZX98ABCDE7"},
                        {**mutant, "authority": "Developer ID Installer: Example Corp (AB12CDE345)"},
                        {**mutant, "timestamp": "modified"}, {**mutant, "requirement": "modified"},
                        {**mutant, "details": mutant["details"].replace(self.team, "ZX98ABCDE7")},
                        {**mutant, "verified": False}, {**mutant, "notarized": True}, {}):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                mac.validate_signing_pair({"signing": candidate}, {"signing": invalid})
        with self.assertRaises(ValueError):
            mac.validate_signing_pair({}, {"signing": adhoc})

    def test_retained_receipt_is_compared_with_actual_signature_again(self):
        receipt = self.record()
        changed_details = self.details.replace("10:00:00", "10:00:01")
        with patch.object(mac, "architectures", return_value=["arm64"]), \
             patch.object(mac.subprocess, "run", return_value=SimpleNamespace(stderr=changed_details)):
            with self.assertRaisesRegex(ValueError, "recorded Developer ID signature metadata"):
                mac._verified_macho(self.library, self.root, {"mach_o": {"architectures": ["arm64"]}, "signing": receipt})

    def test_default_adhoc_receipt_keeps_legacy_shape(self):
        with patch.object(mac.subprocess, "run", return_value=SimpleNamespace(stderr="Signature=adhoc")) as run:
            receipt = mac.inspect_signing(self.library, {"kind": "ad-hoc"})
        self.assertEqual(receipt, {"kind": "ad-hoc", "verified": True, "details": "Signature=adhoc", "notarized": False})
        self.assertEqual(len(run.call_args_list), 2)
        self.assertEqual(run.call_args_list[0].args[0], ["codesign", "--verify", "--strict", str(self.library)])


class Publishing(ScratchCase):
    def test_developer_id_build_signs_before_hashing_and_rejects_mixed_pair(self):
        tool_root = self.root / "outputs"
        compiler = self.root / "bin/clang++"
        compiler.parent.mkdir()
        compiler.write_text("clang++")
        sdk = self.root / "SDK"
        engine = self.root / "Godot"
        engine.write_bytes(b"engine")
        engine_identity = {"path": str(engine), "version": "version", "sha256": mac.nk.sha256_file(engine),
                           "architectures": ["arm64"]}
        toolchain = {"compiler": str(compiler), "c_compiler": str(compiler.with_name("clang")),
                     "compiler_version": mac.APPLE_CLANG, "sdk_path": str(sdk)}
        lock = mac.locked.load_lock()
        identity = {"source_sha256": "source", "reference_sources_sha256": {}, "lock_sha256": "lock",
                    "builder_sha256": "builder", "linux_builder_sha256": "linux", "shared_builder_sha256": "shared"}
        fingerprint, team = "A1" * 20, "AB12CDE345"
        authority = f"Developer ID Application: Example Corp ({team})"
        details = (f"Authority={authority}\nAuthority=Developer ID Certification Authority\n"
                   f"Authority=Apple Root CA\nTimestamp=Nov 13, 2026 at 10:00:00\nTeamIdentifier={team}")
        commands = []

        def ensure_cpp(_lock):
            cpp = mac.locked.TOOL_ROOT / "godot-cpp"
            (cpp / "gdextension").mkdir(parents=True)
            (cpp / "gdextension/extension_api-4-7.json").write_text("api")
            return cpp

        def run(command, **_kwargs):
            commands.append(command)
            if command[0] == "security":
                return SimpleNamespace(returncode=0, stdout=f'1) {fingerprint} "{authority}"\n', stderr="")
            if "platform=macos" in command:
                work = Path(command[command.index("-C") + 1])
                variant = "_mutant" if work.name == "mutant" else ""
                dest = work / "lib" / f"lib{mac.nk.NAME}{variant}.dylib"
                dest.parent.mkdir()
                dest.write_bytes(work.name.encode())
            elif command[:2] == ["xcrun", "dsymutil"]:
                dylib = Path(command[2])
                dwarf = Path(command[-1]) / "Contents/Resources/DWARF" / dylib.name
                dwarf.parent.mkdir(parents=True)
                dwarf.write_bytes(b"debug")
            elif command[:2] == ["codesign", "--force"]:
                path = Path(command[-1])
                path.write_bytes(path.read_bytes() + b"-developer-signed")
            return SimpleNamespace(returncode=0, stdout="", stderr=details)

        def inspection(library, _dwarf, _work):
            self.assertTrue(library.read_bytes().endswith(b"-developer-signed"))
            return {"architectures": ["arm64"]}

        args = argparse.Namespace(jobs=1, godot=engine, tool_root=tool_root, mutant=False, min_free_gib=2.0,
                                  signing_identity=fingerprint.lower(), team_id=team)
        with patch.object(mac, "host_toolchain", return_value=toolchain), patch.object(mac, "godot_identity", return_value=engine_identity), \
             patch.object(mac, "_identity", return_value=identity), patch.object(mac, "preflight", return_value={}), \
             patch.object(mac.locked, "load_lock", return_value=lock), patch.object(mac.locked, "ensure_scons", return_value=["scons"]) as scons, \
             patch.object(mac.locked, "ensure_godot_cpp", side_effect=ensure_cpp), \
             patch.object(mac.locked, "run", return_value="head"), patch.object(mac, "validate_compdb", return_value={}), \
             patch.object(mac, "validate_variant_compdb"), patch.object(mac, "validate_link_command", return_value=[]), \
             patch.object(mac, "inspect_library", side_effect=inspection), patch.object(mac.subprocess, "run", side_effect=run):
            self.assertEqual(mac.build(args), 0)
            candidate = json.loads((tool_root / "build-receipt.json").read_text())
            library = tool_root / "lib/libopenrc_native_kernel.dylib"
            self.assertEqual(candidate["binary_sha256"], mac.nk.sha256_file(library))
            self.assertEqual(candidate["signing"]["identity_sha1"], fingerprint)
            self.assertEqual(candidate["signing"]["team_id"], team)
            self.assertFalse(candidate["signing"]["notarized"])
            args.mutant = True
            args.signing_identity = None
            args.team_id = None
            before = scons.call_count
            with self.assertRaisesRegex(ValueError, "same signing selection"):
                mac.build(args)
            self.assertEqual(scons.call_count, before)
            args.signing_identity, args.team_id = fingerprint, team
            self.assertEqual(mac.build(args), 0)
            mutant = json.loads((tool_root / "build-receipt_mutant.json").read_text())
            self.assertNotEqual(candidate["binary_sha256"], mutant["binary_sha256"])
            self.assertIsNone(mac.validate_signing_pair(candidate, mutant))
        signing = [command for command in commands if command[:2] == ["codesign", "--force"]]
        self.assertEqual(len(signing), 2)
        for command in signing:
            self.assertEqual(command[:6], ["codesign", "--force", "--sign", fingerprint, "--timestamp", command[-1]])
            self.assertNotIn("--entitlements", command)

    def test_signed_bytes_are_hashed_and_candidate_and_mutant_are_isolated(self):
        tool_root = self.root / "outputs"
        sdk = self.root / "SDK"
        compiler = self.root / "bin/clang++"
        compiler.parent.mkdir()
        compiler.write_text("clang++")
        engine = self.root / "Godot"
        engine.write_bytes(b"engine")
        engine_identity = {"path": str(engine), "version": "version", "sha256": mac.nk.sha256_file(engine),
                           "architectures": ["arm64"]}
        toolchain = {"compiler": str(compiler), "c_compiler": str(compiler.with_name("clang")),
                     "compiler_version": mac.APPLE_CLANG, "sdk_path": str(sdk)}
        lock = mac.locked.load_lock()
        identity = {"source_sha256": "source", "reference_sources_sha256": {}, "lock_sha256": "lock",
                    "builder_sha256": "builder", "linux_builder_sha256": "linux", "shared_builder_sha256": "shared"}
        made = []

        def ensure_cpp(_lock):
            cpp = mac.locked.TOOL_ROOT / "godot-cpp"
            (cpp / "gdextension").mkdir(parents=True)
            (cpp / "gdextension/extension_api-4-7.json").write_text("api")
            made.append(cpp)
            return cpp

        def run(command, **kwargs):
            if "platform=macos" in command:
                work = Path(command[command.index("-C") + 1])
                variant = "_mutant" if work.name == "mutant" else ""
                dest = work / "lib" / f"lib{mac.nk.NAME}{variant}.dylib"
                dest.parent.mkdir()
                dest.write_bytes(b"unsigned")
            elif command[:2] == ["xcrun", "dsymutil"]:
                dylib = Path(command[2])
                dwarf = Path(command[-1]) / "Contents/Resources/DWARF" / dylib.name
                dwarf.parent.mkdir(parents=True)
                dwarf.write_bytes(b"debug")
            elif command[:2] == ["codesign", "--force"]:
                path = Path(command[-1])
                path.write_bytes(path.read_bytes() + b"-signed")
            class Result:
                returncode = 0
                stderr = "Signature=adhoc"
            return Result()

        def inspection(library, _dwarf, _work):
            self.assertTrue(library.read_bytes().endswith(b"-signed"))
            return {"architectures": ["arm64"]}

        args = argparse.Namespace(jobs=1, godot=engine, tool_root=tool_root, mutant=False, min_free_gib=2.0)
        with patch.object(mac, "host_toolchain", return_value=toolchain), patch.object(mac, "godot_identity", return_value=engine_identity), \
             patch.object(mac, "_identity", return_value=identity), patch.object(mac, "preflight", return_value={}), \
             patch.object(mac.locked, "load_lock", return_value=lock), patch.object(mac.locked, "ensure_scons", return_value=["scons"]), \
             patch.object(mac.locked, "ensure_godot_cpp", side_effect=ensure_cpp), \
             patch.object(mac.locked, "run", return_value="head"), patch.object(mac, "validate_compdb", return_value={}), \
             patch.object(mac, "validate_variant_compdb"), \
             patch.object(mac, "validate_link_command", return_value=[]), patch.object(mac, "inspect_library", side_effect=inspection), \
             patch.object(mac.subprocess, "run", side_effect=run):
            self.assertEqual(mac.build(args), 0)
            receipt = json.loads((tool_root / "build-receipt.json").read_text())
            library = tool_root / "lib/libopenrc_native_kernel.dylib"
            self.assertEqual(receipt["binary_sha256"], mac.nk.sha256_file(library))
            self.assertTrue(receipt["signing"]["verified"])
            self.assertFalse(receipt["signing"]["notarized"])
            self.assertFalse(receipt["installable"])
            self.assertEqual(receipt["disk_headroom"]["minimum_gib"], 2.0)
            self.assertTrue(all(receipt["disk_headroom"][key] > 0 for key in
                                ("before_bytes", "before_build_bytes", "after_bytes")))
            self.assertIn('macos.arm64 = "lib/libopenrc_native_kernel.dylib"',
                          (tool_root / "openrc_native_kernel.gdextension").read_text())
            with self.assertRaisesRegex(ValueError, "overwrite"):
                mac.build(args)
            args.mutant = True
            self.assertEqual(mac.build(args), 0)
            self.assertEqual(len(made), 2)
            self.assertNotEqual(made[0], made[1])
            mutant = json.loads((tool_root / "build-receipt_mutant.json").read_text())
            self.assertTrue(mutant["mutant"])
            self.assertIn("-DNK_MUTATION=1", mutant["cxxflags_appended"])


class ExperimentalEvidence(ScratchCase):
    def setUp(self):
        super().setUp()
        self.repo = self.root / "repo"
        self.here = self.repo / "research/native-kernel"
        self.app = self.repo / "app"
        for relative in ("research/native-kernel/oracle.gd", "research/native-kernel/stage_oracle.gd",
                         "research/native-kernel/stage_adapter.gd", "research/native-kernel/run.py",
                         "research/native-kernel/build.py", "research/native-kernel/build_macos.py",
                         "tools/godot/run_checked.py", "app/sim/native_stage.gd", "app/sim/proof.gd"):
            file = self.repo / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(relative.encode())
        self.engine = {"path": str(self.root / "Godot"), "version": "4.8.beta2.official.cafc17a19",
                       "sha256": "e" * 64, "architectures": ["arm64"]}
        self.descriptor = self.root / "candidate.gdextension"
        self.source = mac.nk.sha256_file(self.app / "sim/proof.gd")
        self.built = {"engine": self.engine, "binary_sha256": "a" * 64, "descriptor": str(self.descriptor),
                      "library": str(self.root / "lib/libopenrc_native_kernel.dylib"),
                      "reference_sources_sha256": {"app/sim/proof.gd": self.source}}
        self.result = self.root / "results-20261112.json"
        self.harness = {name: mac.nk.sha256_file(self.repo / name) for name in (
            "research/native-kernel/oracle.gd", "research/native-kernel/stage_oracle.gd",
            "research/native-kernel/stage_adapter.gd", "research/native-kernel/run.py",
            "research/native-kernel/build.py", "research/native-kernel/build_macos.py",
            "tools/godot/run_checked.py", "app/sim/native_stage.gd")}
        self.before = patch.object(mac, "ROOT", self.repo)
        self.before.start()
        self.addCleanup(self.before.stop)
        self.here_patch = patch.object(mac, "HERE", self.here)
        self.here_patch.start()
        self.addCleanup(self.here_patch.stop)

    def evidence(self):
        counts = {"math_shim": 14 * (27 * 27 + 20000), "literals": 130, "aero_loads": 100,
                  "macos_float64_scalar_transport": 13, "macos_float64_packed_transport": 13,
                  **{name: 1 for name in ("macos_float64_input_isolation", "macos_float64_result_isolation",
                                         "macos_float64_caller_isolation", "macos_float64_repeated_transport",
                                         "macos_float64_retained_transport", "macos_fpcr_math_witness")}}
        total = sum(counts.values())
        return {"format": "openrc-nk3-oracle v1", "run_valid": True, "verdict": "pass", "failures": [],
                "engine": "4.8-beta2 (official)", "build_receipt": copy.deepcopy(self.built),
                "binary_sha256_before": self.built["binary_sha256"], "binary_sha256_after": self.built["binary_sha256"],
                "engine_sha256_before": self.engine["sha256"], "engine_sha256_after": self.engine["sha256"],
                "engine_executable_sha256_before": self.engine["sha256"],
                "engine_executable_sha256_after": self.engine["sha256"],
                "identity": {"backend": "native", "backend_version": mac.nk.BACKEND_VERSION,
                             "abi_version": mac.nk.ABI_VERSION},
                "reference_sources_before": copy.deepcopy(self.built["reference_sources_sha256"]),
                "reference_sources_after": copy.deepcopy(self.built["reference_sources_sha256"]),
                "sources": {"res://sim/proof.gd": self.source}, "sources_after": {"res://sim/proof.gd": self.source},
                "harness_sources": copy.deepcopy(self.harness), "project": str(self.app),
                "project_inventory_before": {}, "project_inventory_after": {},
                "checked_run": {"complete": True, "ok": True, "required_text": ["NK3_ORACLE verdict=pass"],
                                "missing_required_text": [], "counts": {"error": 0}, "process_exit": 0,
                                "reason": "passed", "cwd": str(self.repo),
                                "command": [self.engine["path"], "--headless", "--path", str(self.app),
                                            "--audio-driver", "Dummy", "--script", str(self.here / "oracle.gd"),
                                            "--", f"--extension={self.descriptor}", f"--output={self.result}",
                                            "--states=12000", "--variant-states=1500"]},
                "states": 12000, "variant_states": 1500, "self_test": {"passed": True, "detected": [True] * 4},
                "law_identity": {"aero_reference": "law1", "aero_native": "law1",
                                 "rolling_reference": "law2", "rolling_native": "law2"},
                "macos_boundary": {
                    "format": "openrc-nk3-macos-boundary-probe v1", "control_mask": "0x07c8bf07",
                    "fpsr": "not_observed", "signaling_nan": "not_tested",
                    "float32_detector_input": "3ff0000000000001", "float32_detector_result": "3ff0000000000000",
                    **{name: True for name in ("control_unchanged", "control_detector", "float32_narrowing_detected",
                                              "retained_after_input_change", "independent_results", "caller_unchanged_by_result",
                                              "repeated_call", "retained_after_repeat", "stage_prepared", "tick_context_accepted",
                                              "stage_shaped", "refusal_observed")},
                    "fpcr": {f"{edge}_{operation}": {"raw": "0x0000000000000000", "control": "0x00000000"}
                             for edge in ("before", "after")
                             for operation in ("transport", "math", "prepare", "context", "stage", "refusal", "checks")}},
                "coverage": {
                    "macos_float64_transport": {"scalar_cases": 13, "packed_cases": 13, "retention_checks": 5,
                                                "quiet_nan_encodings": 3, "signaling_nan_tested": False,
                                                "beyond_float32_cases": 2},
                    "macos_fpcr": {"observations": 14, "changed": 0, "fpsr_tested": False}},
                "components": {name: {"count": count, "identical": count} for name, count in counts.items()},
                "total": {"compared": total, "identical": total, "mismatched": 0}}

    class Runner:
        @staticmethod
        def validate_project(_project):
            return {}

    def seal(self, report, result=None, marker="NK3_ORACLE verdict=pass"):
        result = self.result if result is None else result
        checks = Path(report["build_receipt"]["library"]).parent.parent / "checks" / result.stem
        checks.mkdir(parents=True, exist_ok=True)
        log = checks / "engine.log"
        log.write_text(marker + "\n")
        checked = report["checked_run"]
        checked.update(log=str(log), log_sha256=mac.nk.sha256_file(log), report=str(checks / "report.json"))
        (checks / "report.json").write_text(json.dumps(checked))

    def check(self, report):
        self.seal(report)
        mac._check_oracle_identity(report, self.result, "base_oracle", self.built, {}, self.Runner())

    def test_complete_base_evidence_and_detector_requirements(self):
        good = self.evidence()
        self.check(good)
        for mutation in (
            lambda x: x.update(verdict="fail"),
            lambda x: x.update(run_valid=False),
            lambda x: x["self_test"].update(passed=False),
            lambda x: x["law_identity"].update(aero_native="wrong"),
            lambda x: x["components"]["math_shim"].update(identical=0),
            lambda x: x["components"]["math_shim"].update(count=1, identical=1),
            lambda x: x["components"]["literals"].update(count=1, identical=1),
            lambda x: x.update(states=11999),
            lambda x: x.update(variant_states=1499),
            lambda x: x["total"].update(mismatched=1),
            lambda x: x["identity"].update(backend="gdscript_reference"),
        ):
            bad = copy.deepcopy(good)
            mutation(bad)
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                self.check(bad)

    def test_mac_boundary_observations_and_detectors_are_required(self):
        good = self.evidence()
        mutations = [
            lambda x: x.pop("macos_boundary"),
            lambda x: x["macos_boundary"]["fpcr"].pop("after_checks"),
            lambda x: x["macos_boundary"]["fpcr"]["after_stage"].update(raw="0x0000000000400000"),
            lambda x: x["macos_boundary"]["fpcr"]["after_stage"].update(raw="0x0000000000400000", control="0x00400000"),
            lambda x: x["coverage"]["macos_float64_transport"].update(scalar_cases=12),
            lambda x: x["coverage"]["macos_fpcr"].update(changed=False),
            lambda x: x["components"].pop("macos_float64_input_isolation"),
            lambda x: x["macos_boundary"].update(float32_detector_result="3ff0000000000001"),
        ]
        for field, value in good["macos_boundary"].items():
            if type(value) is bool:
                mutations.append(lambda x, key=field: x["macos_boundary"].update({key: False}))
        for mutation in mutations:
            bad = copy.deepcopy(good)
            mutation(bad)
            self.assertTrue(mac.verification_error("base_oracle", bad))

    def test_stale_artifact_source_harness_or_checked_process_is_refused(self):
        good = self.evidence()
        for mutation in (
            lambda x: x.update(engine_sha256_after="f" * 64),
            lambda x: x.update(engine_executable_sha256_after="f" * 64),
            lambda x: x.update(binary_sha256_before="b" * 64),
            lambda x: x["build_receipt"].update(architecture="x86_64"),
            lambda x: x["reference_sources_after"].clear(),
            lambda x: x["sources_after"].clear(),
            lambda x: x["harness_sources"].pop("research/native-kernel/build_macos.py"),
            lambda x: x["harness_sources"].update({"../../outside": "a" * 64}),
            lambda x: x["checked_run"].update(complete=False),
            lambda x: x["checked_run"].update(required_text=[]),
            lambda x: x["checked_run"].update(missing_required_text=["missing"]),
            lambda x: x["checked_run"]["command"].append("--extension=other"),
            lambda x: x["checked_run"]["command"].__setitem__(0, str(self.root / "other-godot")),
            lambda x: x["checked_run"]["command"].append("--output=other"),
        ):
            bad = copy.deepcopy(good)
            mutation(bad)
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                self.check(bad)

    def test_copied_project_requires_current_inventory_proof(self):
        copied = self.root / "research/app"
        copied.mkdir(parents=True)
        report = self.evidence()
        report["project"] = str(copied)
        report["checked_run"]["command"][3] = str(copied)
        with self.assertRaisesRegex(ValueError, "inventory proof"):
            self.check(report)
        proof = {"canonical_manifest_sha256": "a" * 64, "executed_project_content_sha256": "b" * 64,
                 "checked_files": 42, "excluded_generated_suffixes": [".import", ".uid"]}
        report["project_inventory_before"] = copy.deepcopy(proof)
        report["project_inventory_after"] = copy.deepcopy(proof)
        class CopiedRunner:
            @staticmethod
            def validate_project(project):
                self.assertEqual(project, copied)
                return proof
        self.seal(report)
        mac._check_oracle_identity(report, self.result, "base_oracle", self.built, {}, CopiedRunner())
        report["project_inventory_after"]["checked_files"] = 0
        with self.assertRaisesRegex(ValueError, "inventory proof"):
            mac._check_oracle_identity(report, self.result, "base_oracle", self.built, {}, CopiedRunner())

    def test_checked_report_and_log_must_still_match(self):
        report = self.evidence()
        self.seal(report)
        mac._check_oracle_identity(report, self.result, "base_oracle", self.built, {}, self.Runner())
        log = Path(report["checked_run"]["log"])
        log.write_text("missing marker")
        with self.assertRaisesRegex(ValueError, "marker"):
            mac._check_oracle_identity(report, self.result, "base_oracle", self.built, {}, self.Runner())
        self.seal(report)
        Path(report["checked_run"]["report"]).write_text("{}")
        with self.assertRaisesRegex(ValueError, "report"):
            mac._check_oracle_identity(report, self.result, "base_oracle", self.built, {}, self.Runner())

    def test_newer_bad_report_cannot_hide_older_valid_evidence(self):
        report = self.evidence()
        self.seal(report)
        self.result.write_text(json.dumps(report))
        bad = copy.deepcopy(report)
        bad["verdict"] = "fail"
        newer = self.root / "results-20261113.json"
        bad["checked_run"]["command"] = [f"--output={newer}" if arg.startswith("--output=") else arg
                                            for arg in bad["checked_run"]["command"]]
        self.seal(bad, newer)
        newer.write_text(json.dumps(bad))
        row = mac.find_verification(self.root, "base_oracle", "results-[0-9]*.json", self.built, {}, self.Runner())
        self.assertEqual(row["results"], self.result.name)
        self.assertEqual(row["results_sha256"], mac.nk.sha256_file(self.result))
        self.result.unlink()
        with self.assertRaisesRegex(ValueError, "base oracle did not pass"):
            mac.find_verification(self.root, "base_oracle", "results-[0-9]*.json", self.built, {}, self.Runner())

    def test_install_is_source_only_and_rejects_missing_or_failed_evidence_before_writes(self):
        tool_root = self.repo / "tmp/build"
        (tool_root / "lib").mkdir(parents=True)
        candidate_path = tool_root / "lib/libopenrc_native_kernel.dylib"
        candidate_path.write_bytes(b"signed-candidate")
        mutant_path = tool_root / "lib/libopenrc_native_kernel_mutant.dylib"
        mutant_path.write_bytes(b"signed-mutant")
        license_path = tool_root / "work/candidate/dependencies/godot-cpp/LICENSE.md"
        license_path.parent.mkdir(parents=True)
        license_path.write_text("license")
        identity = {"source_sha256": "1" * 64, "lock_sha256": "2" * 64, "builder_sha256": "3" * 64,
                    "linux_builder_sha256": "4" * 64, "shared_builder_sha256": "5" * 64,
                    "reference_sources_sha256": copy.deepcopy(self.built["reference_sources_sha256"])}
        self.built.update(library=str(candidate_path), binary_sha256=mac.nk.sha256_file(candidate_path),
                          godot_cpp_commit="c", extension_api_sha256="d" * 64, binding_precision="single",
                          cxxflags_appended=[], repository_head="head",
                          signing={"kind": "ad-hoc", "verified": True, "details": "Signature=adhoc", "notarized": False})
        mutant = copy.deepcopy(self.built)
        mutant.update(library=str(mutant_path), binary_sha256=mac.nk.sha256_file(mutant_path),
                      descriptor=str(self.root / "mutant.gdextension"))
        self.result = tool_root / "results-20261112.json"
        base = self.evidence()
        self.seal(base)
        self.result.write_text(json.dumps(base))
        # Use the shared verifier's real stage/negative-control fixture.
        spec = importlib.util.spec_from_file_location("existing_nk_evidence_fixture", HERE / "test_verification.py")
        existing = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(existing)
        control = existing.evidence("stage_oracle")
        control.update({key: copy.deepcopy(base[key]) for key in (
            "identity", "reference_sources_before", "reference_sources_after", "sources", "sources_after",
            "harness_sources", "project", "project_inventory_before", "project_inventory_after",
            "engine", "engine_sha256_before", "engine_sha256_after", "engine_executable_sha256_before",
            "engine_executable_sha256_after")})
        control["build_receipt"] = copy.deepcopy(mutant)
        control["binary_sha256_before"] = control["binary_sha256_after"] = mutant["binary_sha256"]
        control["verdict"] = "fail"
        control["states"] = 12000
        control["variant_states"] = 1500
        control["components"]["stage_bytes"]["identical"] -= 1
        control["total"]["identical"] -= 1
        control["total"]["mismatched"] = 1
        control_path = tool_root / "stage_mutant-20261112.json"
        control["checked_run"] = copy.deepcopy(base["checked_run"])
        control["checked_run"].update(ok=False, required_text=["NK3_ORACLE verdict=fail"], process_exit=1,
                                      reason="process_exit")
        control["checked_run"]["command"][7] = str(self.here / "stage_oracle.gd")
        control["checked_run"]["command"] = [
            f'--extension={mutant["descriptor"]}' if arg.startswith("--extension=") else
            f"--output={control_path}" if arg.startswith("--output=") else arg
            for arg in control["checked_run"]["command"]]
        self.seal(control, control_path, "NK3_ORACLE verdict=fail")
        control_path.write_text(json.dumps(control))
        toolchain = {"os_version": "27.0.1", "os_build": "26A434"}
        roster = {"base_oracle": "results-[0-9]*.json", "negative_control": "stage_mutant-[0-9]*.json"}
        def selected_build(_root, is_mutant, *_args):
            return mutant if is_mutant else self.built
        with patch.object(mac, "host_toolchain", return_value=toolchain), \
             patch.object(mac, "godot_identity", return_value=self.engine), \
             patch.object(mac, "_identity", return_value=identity), \
             patch.object(mac, "validate_build", side_effect=selected_build), \
             patch.object(mac, "_runner", return_value=self.Runner()), \
             patch.object(mac, "verification_roster", return_value=roster):
            base["components"]["math_shim"]["identical"] -= 1
            self.result.write_text(json.dumps(base))
            with self.assertRaisesRegex(ValueError, "base_oracle evidence"):
                mac.install_app(tool_root, Path(self.engine["path"]))
            self.assertFalse((self.app / "native/kernel").exists())
            base["components"]["math_shim"]["identical"] += 1
            self.result.write_text(json.dumps(base))
            control_path.unlink()
            with self.assertRaisesRegex(ValueError, "negative_control evidence"):
                mac.install_app(tool_root, Path(self.engine["path"]))
            self.assertFalse((self.app / "native/kernel").exists())
            control_path.write_text(json.dumps(control))
            self.assertEqual(mac.install_app(tool_root, Path(self.engine["path"])), 0)
        dest = self.app / "native/kernel"
        receipt = json.loads((dest / "build-receipt-macos.json").read_text())
        row = receipt["platforms"]["macos"]
        self.assertEqual(row["qualification_scope"], "macos-arm64-fixed-wing-experimental-v1")
        self.assertEqual(row["runtime_os_version"], "27.0.1")
        self.assertEqual(row["runtime_os_build"], "26A434")
        self.assertEqual(row["engine_sha256"], self.engine["sha256"])
        self.assertEqual(set(row["verification"]), set(roster))
        self.assertEqual((dest / "openrc_native_kernel_macos.gdextension").read_text(), mac.SOURCE_DESCRIPTOR)
        self.assertEqual((dest / "libopenrc_native_kernel.dylib").read_bytes(), b"signed-candidate")
        self.assertTrue((dest / ".gdignore").is_file())


class RetainedBuildValidation(ScratchCase):
    def setUp(self):
        super().setUp()
        import hashlib
        import shlex
        self.out = self.root / "output"
        self.work = self.out / "work/candidate"
        self.sdk = self.root / "SDK"
        self.compiler = self.root / "bin/clang++"
        self.compiler.parent.mkdir(parents=True)
        self.compiler.write_text("compiler")
        self.source = self.root / "src"
        self.source.mkdir()
        (self.source / "nk_kernel.cpp").write_text("source")
        self.cpp = self.work / "dependencies/godot-cpp"
        (self.cpp / "gdextension").mkdir(parents=True)
        self.api = self.cpp / "gdextension/extension_api-4-7.json"
        self.api.write_text("api")
        self.lock = copy.deepcopy(mac.locked.load_lock())
        wheel = self.work / "dependencies/downloads" / self.lock["scons"]["wheel_filename"]
        wheel.parent.mkdir(parents=True)
        wheel.write_bytes(b"pinned-wheel")
        self.lock["scons"]["wheel_sha256"] = mac.nk.sha256_file(wheel)
        profile = json.dumps(self.lock["godot_cpp"]["build_profile"]["content"], sort_keys=True, separators=(",", ":")) + "\n"
        self.profile = self.work / "build_profile.json"
        self.profile.write_bytes(profile.encode())
        self.assertEqual(hashlib.sha256(profile.encode()).hexdigest(), self.lock["godot_cpp"]["build_profile"]["sha256"])
        self.library = self.out / "lib/libopenrc_native_kernel.dylib"
        self.library.parent.mkdir(parents=True)
        self.library.write_bytes(b"signed")
        self.descriptor = self.out / "openrc_native_kernel.gdextension"
        self.descriptor.write_text("descriptor")
        self.toolchain = {"compiler": str(self.compiler), "sdk_path": str(self.sdk), "os_version": "27.0.1",
                          "os_build": "26A434"}
        self.engine = {"path": str(self.root / "Godot"), "sha256": "e" * 64,
                       "version": "4.8.beta2.official.cafc17a19", "architectures": ["arm64"]}
        self.identity = {"source_sha256": "a" * 64, "reference_sources_sha256": {"app/proof": "b" * 64},
                         "lock_sha256": "c" * 64, "builder_sha256": "d" * 64,
                         "linux_builder_sha256": "f" * 64, "shared_builder_sha256": "1" * 64}
        args = [str(self.compiler), *mac._common_flags(self.sdk), "-c", str(self.source / "nk_kernel.cpp")]
        db = self.work / "compile_commands.json"
        db.write_text(json.dumps([{"directory": str(self.work), "file": str(self.source / "nk_kernel.cpp"),
                                   "arguments": args}]))
        self.link = [str(self.compiler), "-o", str(self.work / "lib" / self.library.name), "-fno-lto", "-arch", "arm64",
                     "-isysroot", str(self.sdk), "-mmacosx-version-min=11.0",
                     f"-Wl,-install_name,@rpath/{self.library.name}"]
        log = self.work / "build.log"
        log.write_text(shlex.join(self.link) + "\n")
        self.receipt = {**self.identity, "format": mac.FORMAT, "installable": False, "mutant": False,
                        "platform": "macos", "architecture": "arm64", "target": "template_release",
                        "backend_version": mac.nk.BACKEND_VERSION, "abi_version": mac.nk.ABI_VERSION,
                        "toolchain": self.toolchain, "engine": self.engine, "engine_version": self.engine["version"],
                        "engine_sha256": self.engine["sha256"], "godot_cpp_commit": self.lock["godot_cpp"]["commit"],
                        "scons_version": self.lock["scons"]["version"],
                        "scons_wheel_sha256": self.lock["scons"]["wheel_sha256"],
                        "extension_api": self.lock["godot"]["extension_api"], "binding_precision": "single",
                        "build_profile_sha256": self.lock["godot_cpp"]["build_profile"]["sha256"],
                        "cxxflags_appended": mac._common_flags(self.sdk), "library": str(self.library),
                        "binary_sha256": mac.nk.sha256_file(self.library), "descriptor": str(self.descriptor),
                        "descriptor_sha256": mac.nk.sha256_file(self.descriptor), "extension_api_path": str(self.api),
                        "extension_api_sha256": mac.nk.sha256_file(self.api),
                        "compile_database": {"entries": 1, "native_translation_units": 1, "sha256": mac.nk.sha256_file(db)},
                        "link_command": self.link, "build_log_sha256": mac.nk.sha256_file(log)}
        self.path = self.out / "build-receipt.json"
        self.write()

    def write(self):
        self.path.write_text(json.dumps(self.receipt))

    def check(self):
        def git(command, **_kwargs):
            return self.lock["godot_cpp"]["commit"] if "rev-parse" in command else ""
        with patch.object(mac.locked, "SOURCES", self.source), patch.object(mac.locked, "run", side_effect=git), \
             patch.object(mac, "_verified_macho"):
            return mac.validate_build(self.out, False, self.identity, self.toolchain, self.engine, self.lock)

    def test_receipt_and_actual_artifacts_are_checked_together(self):
        self.assertEqual(self.check(), self.receipt)
        for field, value in (("mutant", True), ("binding_precision", "double"), ("architecture", "x86_64"),
                             ("engine_sha256", "0" * 64), ("source_sha256", "0" * 64),
                             ("cxxflags_appended", ["-ffast-math"])):
            original = self.receipt[field]
            self.receipt[field] = value
            self.write()
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.check()
            self.receipt[field] = original
        self.write()
        for file in (self.library, self.api, self.profile, self.work / "build.log"):
            before = file.read_bytes()
            file.write_bytes(before + b"changed")
            with self.subTest(file=file), self.assertRaises(ValueError):
                self.check()
            file.write_bytes(before)
        self.assertEqual(self.check(), self.receipt)


class MacManualLoading(ScratchCase):
    def test_only_mac_cache_entries_are_removed_and_other_bytes_are_preserved(self):
        app = self.root / "app"
        registry = app / ".godot/extension_list.cfg"
        registry.parent.mkdir(parents=True)
        other = b"res://native/kernel/openrc_native_kernel.gdextension\r\nres://another.gdextension\n"
        entry = b"res://native/kernel/openrc_native_kernel_macos.gdextension"
        registry.write_bytes(other + entry + b"\r\n" + entry)
        dest = app / "native/kernel"
        mac.prepare_macos_manual_loading(app, dest)
        self.assertEqual(registry.read_bytes(), other)
        self.assertTrue((dest / ".gdignore").is_file())
        mac.prepare_macos_manual_loading(app, dest)
        self.assertEqual(registry.read_bytes(), other)

    def test_failed_cache_replacement_keeps_previous_bytes(self):
        app = self.root / "app"
        registry = app / ".godot/extension_list.cfg"
        registry.parent.mkdir(parents=True)
        contents = b"res://native/kernel/openrc_native_kernel_macos.gdextension\nres://other.gdextension\n"
        registry.write_bytes(contents)
        with patch.object(mac.os, "replace", side_effect=OSError("failed")):
            with self.assertRaises(OSError):
                mac.prepare_macos_manual_loading(app, app / "native/kernel")
        self.assertEqual(registry.read_bytes(), contents)
        self.assertEqual(list(registry.parent.glob(".nk3-mac-extension-list-*")), [])


if __name__ == "__main__":
    unittest.main()
