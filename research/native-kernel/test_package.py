#!/usr/bin/env python3
"""NK-3 package admission tests with temporary source, evidence and outputs.

No native binary is executed and the production installation is never modified.
"""
from __future__ import annotations

import contextlib
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


package = load_module("nk3_package_tests", HERE / "package.py")
verification_tests = load_module("nk3_package_evidence", HERE / "test_verification.py")
macos_evidence_tests = load_module("nk3_package_macos_evidence", HERE / "test_build_macos.py")
builder = package.builder


class PackageAdmissionTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="nk3-package-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.install = self.root / "app/native/kernel"
        self.install.mkdir(parents=True)
        self.tool = self.root / "research/native-kernel"
        self.tool.mkdir(parents=True)
        self.native_sources = self.tool / "src"
        self.native_sources.mkdir()
        self.native_source = self.native_sources / "nk_stage.hpp"
        self.native_source.write_text("verified native source\n")
        self.lock = self.tool / "toolchain-lock.json"
        self.lock.write_text(json.dumps({"godot": {"version": "4.8.beta2.official.cafc17a19"}}))
        self.editor = self.root / ".tools/Godot_v4.8-beta2_linux.x86_64"
        self.editor.parent.mkdir()
        self.editor.write_bytes(b"pinned editor\n")
        self.library = self.install / "libopenrc_native_kernel.so"
        self.library.write_bytes(b"verified native library\n")
        (self.install / "LICENSE.godot-cpp.md").write_text("test license\n")
        self.mirrored_names = ["app/physics/a.gd", "app/sim/native_stage.gd"]
        for name in self.mirrored_names + ["app/failures/a.gd"]:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("source " + name + "\n")
        self.qualification = {}
        for name in package.QUALIFICATION:
            path = self.tool / "diagnostics" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("diagnostic " + name + "\n")
            self.qualification[name] = path
        for name in ("oracle.gd", "stage_oracle.gd", "stage_adapter.gd", "trajectory.gd", "run.py", "build.py"):
            (self.tool / name).write_text("harness " + name + "\n")
        checked_runner = self.root / "tools/godot/run_checked.py"
        checked_runner.parent.mkdir(parents=True)
        checked_runner.write_text("checked runner\n")
        self.evidence_dir = self.root / "tmp/native-kernel"
        self.evidence_dir.mkdir(parents=True)
        self.manifest = self.install / "package.json"
        replacements = [
            (package, "ROOT", self.root), (package, "HERE", self.tool),
            (package, "MANIFEST", self.manifest), (package, "QUALIFICATION", self.qualification),
            (builder, "ROOT", self.root), (builder, "APP_DESTINATION", self.install),
            (builder, "TOOL_ROOT", self.evidence_dir), (builder, "REFERENCE_SOURCES", self.mirrored_names),
            # Package admission delegates evidence policy to build.py. Exercise that boundary
            # with two independent kinds; the complete family roster has its own policy tests.
            (builder, "VERIFICATIONS", {"stage_oracle": "stage-*.json", "trajectory": "trajectory-*.json"}),
            (builder.locked, "SOURCES", self.native_sources), (builder.locked, "LOCK_PATH", self.lock),
        ]
        for owner, name, value in replacements:
            mocked = patch.object(owner, name, value)
            mocked.start()
            self.addCleanup(mocked.stop)
        self.binary_sha = package.sha(self.library)
        self.sources = builder.mirrored_sources()
        version, editor_sha = builder.pinned_engine_identity()
        self.evidence = {}
        for kind in builder.VERIFICATIONS:
            data = verification_tests.evidence(kind)
            data["engine"] = version
            data["engine_sha256_before"] = data["engine_sha256_after"] = editor_sha
            data["build_receipt"]["binary_sha256"] = self.binary_sha
            data["build_receipt"]["source_sha256"] = builder.source_digest()
            data["build_receipt"]["lock_sha256"] = builder.sha256_file(builder.locked.LOCK_PATH)
            data["build_receipt"]["builder_sha256"] = builder.sha256_file(Path(builder.__file__))
            data["build_receipt"]["reference_sources_sha256"] = copy.deepcopy(self.sources)
            data["binary_sha256_before"] = data["binary_sha256_after"] = self.binary_sha
            data["reference_sources_before"] = copy.deepcopy(self.sources)
            data["reference_sources_after"] = copy.deepcopy(self.sources)
            data["sources"] = {name.replace("app/", "res://", 1): digest for name, digest in self.sources.items()}
            data["sources_after"] = copy.deepcopy(data["sources"])
            harness = [self.tool / name for name in ("oracle.gd", "stage_oracle.gd", "stage_adapter.gd", "run.py", "build.py", "trajectory.gd")]
            harness += [self.root / "app/sim/native_stage.gd", checked_runner]
            data["harness_sources"] = {str(path.relative_to(self.root)): package.sha(path) for path in harness}
            evidence_path = self.evidence_dir / ("stage-verified.json" if kind == "stage_oracle" else "trajectory-verified.json")
            evidence_path.write_text(json.dumps(data))
            self.evidence[kind] = evidence_path
        proof = {kind: builder.find_verification(kind, pattern, self.binary_sha, self.sources)
                 for kind, pattern in builder.VERIFICATIONS.items()}
        self.receipt = {
            "format": builder.RECEIPT_FORMAT, "backend": "native", "backend_version": builder.BACKEND_VERSION,
            "abi_version": builder.ABI_VERSION, "platforms": {"linux": {
                "backend_version": builder.BACKEND_VERSION, "abi_version": builder.ABI_VERSION,
                "platform": "linux", "architecture": "x86_64", "backend": "native",
                "binary_sha256": self.binary_sha, "source_sha256": builder.source_digest(),
                "lock_sha256": package.sha(self.lock), "mirrored_sources": self.sources,
                "engine_version": version, "engine_sha256": editor_sha, "verification": proof,
            }},
        }
        self.receipt_path = self.install / "build-receipt.json"
        self.receipt_path.write_text(json.dumps(self.receipt))
        self.original_install = self.install_bytes()
        self.template = self.root / "template"
        self.template.write_bytes(b"release template\n")

    def install_bytes(self) -> dict[str, bytes]:
        return {path.name: path.read_bytes() for path in self.install.iterdir() if path.is_file() and path.name != "package.json"}

    def executable(self, name: str = "candidate") -> Path:
        path = self.root / name / "openrc-simulator.x86_64"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"release executable including embedded PCK\n")
        return path

    def test_prepare_and_finalize_bind_exact_inputs_and_keep_install_unchanged(self):
        initial = package.prepare()
        manifest = json.loads(self.manifest.read_text())
        self.assertEqual(manifest["native_receipt"], self.receipt)
        self.assertEqual(manifest["qualification_sources"], {name: package.sha(path) for name, path in self.qualification.items()})
        self.assertEqual(initial["manifest_sha256"], package.sha(self.manifest))
        executable = self.executable()
        result = package.finalize(executable, self.template)
        destination = executable.parent / "native/kernel"
        self.assertEqual(result["executable_sha256"], hashlib.sha256(executable.read_bytes()).hexdigest())
        self.assertEqual(result["manifest_sha256"], hashlib.sha256(self.manifest.read_bytes()).hexdigest())
        self.assertEqual(result["template_sha256"], hashlib.sha256(self.template.read_bytes()).hexdigest())
        self.assertEqual(result["native_binary_sha256"], self.binary_sha)
        self.assertEqual(json.loads((destination / "package-receipt.json").read_text()), result)
        self.assertEqual((destination / self.library.name).read_bytes(), self.library.read_bytes())
        self.assertEqual((destination / "LICENSE.godot-cpp.md").read_bytes(), (self.install / "LICENSE.godot-cpp.md").read_bytes())
        self.assertEqual((destination / "openrc_native_kernel.gdextension").read_text(), package.DESCRIPTOR)
        self.assertEqual(self.install_bytes(), self.original_install)

    def test_helicopter_diagnostics_are_bound_and_cannot_change_during_export(self):
        names = ("test_native_helicopter_session.gd", "test_heli_restore_radio.gd")
        self.assertTrue(set(names).issubset(package.QUALIFICATION))
        package.prepare()
        manifest = json.loads(self.manifest.read_text())
        for name in names:
            with self.subTest(diagnostic=name):
                path = self.qualification[name]
                self.assertEqual(manifest["qualification_sources"][name], package.sha(path))
                original = path.read_bytes()
                path.write_bytes(original + b"changed during export\n")
                executable = self.executable("changed-" + name)
                try:
                    with self.assertRaisesRegex(ValueError, "diagnostic sources changed"):
                        package.finalize(executable, self.template)
                    self.assertFalse((executable.parent / "native/kernel").exists())
                finally:
                    path.write_bytes(original)

    def test_prepare_refuses_stale_inputs_and_missing_evidence(self):
        mutations = {
            "library": lambda: self.library.write_bytes(b"changed library"),
            "native source": lambda: self.native_source.write_text("changed source"),
            "lock": lambda: self.lock.write_text('{"godot":{"version":"changed"}}'),
            "mirrored source": lambda: (self.root / self.mirrored_names[0]).write_text("changed source"),
            "editor": lambda: self.editor.write_bytes(b"changed editor"),
            "stage evidence": lambda: self.evidence["stage_oracle"].unlink(),
            "trajectory evidence": lambda: self.evidence["trajectory"].unlink(),
        }
        for name, change in mutations.items():
            with self.subTest(name=name):
                # Restore the bytes for each mutation; no production file is touched.
                paths = [self.library, self.native_source, self.lock, self.root / self.mirrored_names[0],
                         self.editor, *self.evidence.values()]
                saved = {path: path.read_bytes() for path in paths}
                change()
                try:
                    with self.assertRaises((ValueError, SystemExit)):
                        package.prepare()
                    self.assertFalse(self.manifest.exists())
                finally:
                    for path, content in saved.items():
                        path.write_bytes(content)
        self.assertEqual(self.install_bytes(), self.original_install)

    def test_prepare_rejects_changed_oracle_result_and_receipt_identity(self):
        path = self.evidence["stage_oracle"]
        original = path.read_bytes()
        data = json.loads(original)
        data["run_valid"] = False
        path.write_text(json.dumps(data))
        with self.assertRaises(SystemExit):
            package.prepare()
        self.assertFalse(self.manifest.exists())
        path.write_bytes(original)
        stale_receipt = copy.deepcopy(self.receipt)
        stale_receipt["platforms"]["linux"]["verification"]["stage_oracle"]["results_sha256"] = "0" * 64
        self.receipt_path.write_text(json.dumps(stale_receipt))
        with self.assertRaises(ValueError):
            package.prepare()
        self.assertFalse(self.manifest.exists())

    def test_prepare_rejects_malformed_or_incompatible_receipt_envelopes_and_rows(self):
        for value in (None, [], "invalid", 1):
            with self.subTest(scope="receipt", value=value):
                self.receipt_path.write_text(json.dumps(value))
                with self.assertRaises(ValueError):
                    package.verified_install()
        cases = [
            ("format", "other"), ("backend", "gdscript_reference"), ("backend_version", "other"),
            ("abi_version", True), ("abi_version", 2.0), ("abi_version", "2"), ("abi_version", 1),
            ("platforms", None), ("platforms", []), ("platforms", {}),
        ]
        for field, value in cases:
            with self.subTest(scope="envelope", field=field, value=value):
                receipt = copy.deepcopy(self.receipt)
                receipt[field] = value
                self.receipt_path.write_text(json.dumps(receipt))
                with self.assertRaises(ValueError):
                    package.verified_install()
        for value in (None, [], {}):
            with self.subTest(scope="linux", value=value):
                receipt = copy.deepcopy(self.receipt)
                receipt["platforms"]["linux"] = value
                self.receipt_path.write_text(json.dumps(receipt))
                with self.assertRaises(ValueError):
                    package.verified_install()
        for field, value in (("backend", "gdscript_reference"), ("backend_version", "other"),
                             ("abi_version", True), ("abi_version", 2.0), ("abi_version", "2"),
                             ("abi_version", 1), ("platform", "windows"), ("architecture", "arm64"),
                             ("verification", None), ("verification", [])):
            with self.subTest(scope="row", field=field, value=value):
                receipt = copy.deepcopy(self.receipt)
                receipt["platforms"]["linux"][field] = value
                self.receipt_path.write_text(json.dumps(receipt))
                with self.assertRaises(ValueError):
                    package.verified_install()
        self.assertFalse(self.manifest.exists())

    def test_finalize_rejects_stale_sources_or_diagnostics_before_creating_output(self):
        for name in ("solver", "diagnostic", "manifest", "native-source", "library", "lock", "editor", "evidence"):
            with self.subTest(name=name):
                package.prepare()
                executable = self.executable("stale-" + name)
                if name == "solver":
                    target = self.root / "app/failures/a.gd"
                    saved = target.read_bytes()
                    target.write_text("changed unmirrored solver\n")
                elif name == "diagnostic":
                    target = self.qualification["session_probe.gd"]
                    saved = target.read_bytes()
                    target.write_text("changed probe\n")
                elif name == "manifest":
                    target = self.manifest
                    saved = target.read_bytes()
                    target.write_text("{}")
                else:
                    target = {"native-source": self.native_source, "library": self.library,
                              "lock": self.lock, "editor": self.editor, "evidence": self.evidence["trajectory"]}[name]
                    saved = target.read_bytes()
                    if name == "lock":
                        target.write_bytes(saved + b" ")
                    elif name == "evidence":
                        stale = json.loads(saved)
                        stale["run_valid"] = False
                        target.write_text(json.dumps(stale))
                    else:
                        target.write_bytes(saved + b"changed")
                try:
                    with self.assertRaises((ValueError, SystemExit)):
                        package.finalize(executable, self.template)
                    self.assertFalse((executable.parent / "native/kernel").exists())
                finally:
                    target.write_bytes(saved)
        self.assertEqual(self.install_bytes(), self.original_install)

    def test_existing_or_redirected_destinations_are_refused_and_preserved(self):
        package.prepare()
        for scenario in ("existing", "kernel symlink", "native symlink"):
            with self.subTest(scenario=scenario):
                executable = self.executable(scenario.replace(" ", "-"))
                outside = self.root / (scenario.replace(" ", "-") + "-outside")
                outside.mkdir()
                marker = outside / "keep.txt"
                marker.write_text("do not alter\n")
                native = executable.parent / "native"
                if scenario == "native symlink":
                    native.symlink_to(outside, target_is_directory=True)
                else:
                    native.mkdir()
                    destination = native / "kernel"
                    if scenario == "kernel symlink":
                        destination.symlink_to(outside, target_is_directory=True)
                    else:
                        destination.mkdir()
                        (destination / "keep.txt").write_text("existing\n")
                with self.assertRaises(ValueError):
                    package.finalize(executable, self.template)
                self.assertEqual(marker.read_text(), "do not alter\n")
                self.assertEqual({path.name for path in outside.iterdir()}, {"keep.txt"})
                if scenario == "existing":
                    self.assertEqual((destination / "keep.txt").read_text(), "existing\n")
        self.assertEqual(self.install_bytes(), self.original_install)

    def test_copy_corruption_cannot_create_a_package_receipt(self):
        package.prepare()
        executable = self.executable("bad-copy")

        def corrupt_copy(source, destination):
            Path(destination).write_bytes(b"not the verified library")
            return str(destination)

        with patch.object(package.shutil, "copy2", side_effect=corrupt_copy):
            with self.assertRaises(ValueError):
                package.finalize(executable, self.template)
        self.assertFalse((executable.parent / "native/kernel/package-receipt.json").exists())
        self.assertEqual(self.install_bytes(), self.original_install)

    def test_cli_prepare_finalize_protocol(self):
        executable = self.executable("cli")
        with patch.object(sys, "argv", ["package.py", "prepare"]), contextlib.redirect_stdout(io.StringIO()) as stdout:
            package.main()
        prepared = json.loads(stdout.getvalue())
        with patch.object(sys, "argv", ["package.py", "finalize", "--executable", str(executable),
                                        "--template", str(self.template)]), contextlib.redirect_stdout(io.StringIO()) as stdout:
            package.main()
        finalized = json.loads(stdout.getvalue())
        self.assertEqual(prepared["manifest_sha256"], finalized["manifest_sha256"])
        self.assertEqual(finalized["executable_sha256"], package.sha(executable))
        self.assertEqual(self.install_bytes(), self.original_install)

    def test_solver_identity_uses_sorted_paths_and_exact_source_bytes(self):
        nested = self.root / "app/physics/a/inside.gd"
        nested.parent.mkdir()
        nested.write_text("nested source with a colliding basename\n")
        expected = hashlib.sha256()
        for name in ("app/failures/a.gd", "app/physics/a.gd", "app/physics/a/inside.gd", "app/sim/native_stage.gd"):
            expected.update(name.replace("app/", "res://", 1).encode())
            expected.update((self.root / name).read_bytes())
        self.assertEqual(package.solver_identity(), expected.hexdigest())

class MacPackagePortableTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="nk3-mac-package-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.install = self.root / "app/native/kernel"
        self.install.mkdir(parents=True)
        (self.install / "LICENSE.godot-cpp.md").write_bytes(b"dependency licence")
        for directory in ("physics", "sim", "failures"):
            path = self.root / "app" / directory / "fixture.gd"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture")
        self.editor = self.root / "editor"
        self.editor.write_bytes(b"editor fixture")
        self.qualification = {}
        for name in package.MAC_QUALIFICATION:
            path = self.root / "diagnostics" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name)
            self.qualification[name] = path
        for owner, name, value in ((package, "ROOT", self.root), (builder, "APP_DESTINATION", self.install)):
            mocked = patch.object(owner, name, value)
            mocked.start()
            self.addCleanup(mocked.stop)

    def test_mac_staging_binds_prepared_signed_bytes_and_refuses_stale_inputs(self):
        library = self.install / "libopenrc_native_kernel.dylib"
        library.write_bytes(b"fixture signed dylib bytes")
        manifest_path = self.install / "package-macos.json"
        mac_receipt = {"platforms": {"macos": {"engine_version": "fixture",
                                               "binary_sha256": package.sha(library)}}}
        diagnostics = {name: self.qualification[name] for name in
                       ("session_probe.gd", "test_native_stage.gd", "test_native_session.gd", "test_native_replay.gd")}
        tool_root = self.root / "tmp/candidate"
        godot = self.editor
        bundle = self.root / "OpenRC.app"
        (bundle / "Contents/Resources").mkdir(parents=True)
        with patch.object(package, "MAC_MANIFEST", manifest_path), \
                patch.object(package, "MAC_QUALIFICATION", diagnostics), \
                patch.object(package, "verified_mac_install", return_value=mac_receipt):
            prepared = package.prepare_macos(tool_root, godot)
            self.assertEqual(prepared["manifest_sha256"], package.sha(manifest_path))
            manifest = json.loads(manifest_path.read_text())
            installed_license = self.install / "LICENSE.godot-cpp.md"
            self.assertEqual(manifest["license_sha256"], package.sha(installed_license))
            with self.assertRaises(FileExistsError):
                package.prepare_macos(tool_root, godot)
            staged = package.stage_macos(bundle, tool_root, godot)
            self.assertEqual(staged["library_sha256"], package.sha(library))
            self.assertEqual((bundle / "Contents/Frameworks" / library.name).read_bytes(), library.read_bytes())
            descriptor = bundle / "Contents/Resources/openrc_native_kernel_macos.gdextension"
            self.assertEqual(descriptor.read_bytes(),
                             package.MAC_DESCRIPTOR.encode())
            self.assertEqual((descriptor.parent / "../Frameworks/libopenrc_native_kernel.dylib").resolve(),
                             (bundle / "Contents/Frameworks" / library.name).resolve())
            receipt_tool = load_module("nk3_mac_release_receipt", HERE.parents[1] / "tools/release/macos_reference_receipt.py")
            self.assertEqual(package.MAC_DESCRIPTOR, receipt_tool.NATIVE_DESCRIPTOR_TEXT)
            self.assertEqual(descriptor.relative_to(bundle).as_posix(), receipt_tool.NATIVE_DESCRIPTOR)
            self.assertEqual((bundle / "Contents/Resources/LICENSE.godot-cpp.md").read_bytes(),
                             installed_license.read_bytes())
            self.assertEqual(staged["license_sha256"], manifest["license_sha256"])
            with self.assertRaises(ValueError):
                package.stage_macos(bundle, tool_root, godot)
            missing_license_bundle = self.root / "MissingLicence.app"
            (missing_license_bundle / "Contents/Resources").mkdir(parents=True)
            license_bytes = installed_license.read_bytes()
            installed_license.unlink()
            with self.assertRaises(OSError):
                package.stage_macos(missing_license_bundle, tool_root, godot)
            self.assertFalse((missing_license_bundle / "Contents/Frameworks").exists())
            installed_license.write_bytes(license_bytes + b" changed")
            with self.assertRaises(ValueError):
                package.stage_macos(missing_license_bundle, tool_root, godot)
            self.assertFalse((missing_license_bundle / "Contents/Frameworks").exists())
            installed_license.write_bytes(license_bytes)
            changed_bundle = self.root / "Changed.app"
            (changed_bundle / "Contents/Resources").mkdir(parents=True)
            diagnostics["test_native_replay.gd"].write_bytes(b"changed test")
            with self.assertRaises(ValueError):
                package.stage_macos(changed_bundle, tool_root, godot)
            self.assertFalse((changed_bundle / "Contents/Frameworks").exists())

    def test_mac_verified_install_rejects_changed_receipt_or_library(self):
        library = self.install / "libopenrc_native_kernel.dylib"
        library.write_bytes(b"signed fixture")
        ignore = self.install / ".gdignore"
        ignore.touch()
        binary = package.sha(library)
        descriptor = self.install / "openrc_native_kernel_macos.gdextension"
        descriptor.write_bytes(b"source descriptor\n")
        identity = {"source_sha256": "1" * 64, "lock_sha256": "2" * 64,
                    "reference_sources_sha256": {"app/physics/fixture.gd": "3" * 64}}
        toolchain = {"os_version": "27.0.1", "os_build": "26A434"}
        engine = {"version": "engine", "sha256": "4" * 64}
        candidate = {"binary_sha256": binary, "extension_api_sha256": "5" * 64}
        mutant = {"binary_sha256": "6" * 64, "extension_api_sha256": "5" * 64}
        evidence = {}
        roster = {"base_oracle": "results-[0-9]*.json", "negative_control": "stage_mutant-[0-9]*.json"}

        def check_oracle(data, report, key, built, _cache, _runner):
            expected = mutant if key == "negative_control" else candidate
            if built != expected or data.get("binary_sha256") != expected["binary_sha256"] or data.get("valid") is not True:
                raise ValueError("oracle identity refused")

        fake = SimpleNamespace(
            locked=SimpleNamespace(load_lock=lambda: {}), host_toolchain=lambda: toolchain,
            godot_identity=lambda _godot, _lock: engine, _identity=lambda: identity,
            validate_build=lambda _root, is_mutant, *_args: mutant if is_mutant else candidate,
            validate_signing_pair=lambda _candidate, _mutant: None,
            _runner=lambda: None, verification_roster=lambda: roster, _check_oracle_identity=check_oracle,
            SOURCE_SCOPE="macos-arm64-fixed-wing-experimental-v1", _engine_display=lambda version: version,
            SOURCE_DESCRIPTOR="source descriptor\n")
        row = {"platform": "macos", "architecture": "arm64", "backend": "native",
               "backend_version": builder.BACKEND_VERSION, "abi_version": builder.ABI_VERSION,
               "qualification_scope": fake.SOURCE_SCOPE, "binary_sha256": binary,
               "source_sha256": identity["source_sha256"], "lock_sha256": identity["lock_sha256"],
               "mirrored_sources": identity["reference_sources_sha256"], "runtime_os_version": toolchain["os_version"],
               "runtime_os_build": toolchain["os_build"], "engine_version": engine["version"],
               "engine_sha256": engine["sha256"], "verification": evidence}
        envelope = {"format": builder.RECEIPT_FORMAT, "backend": "native", "backend_version": builder.BACKEND_VERSION,
                    "abi_version": builder.ABI_VERSION, "platforms": {"macos": row}}
        path = self.install / "build-receipt-macos.json"
        tool_root = self.root / "tmp/native"
        tool_root.mkdir(parents=True)
        for key, name, build, verdict in (("base_oracle", "results-2026111201.json", candidate, "pass"),
                                           ("negative_control", "stage_mutant-2026111201.json", mutant, "fail")):
            report = tool_root / name
            report.write_text(json.dumps({"binary_sha256": build["binary_sha256"], "valid": True, "total": {"compared": 15}}))
            evidence[key] = {"results": name, "results_sha256": package.sha(report), "verdict": verdict, "compared": 15}
        path.write_text(json.dumps(envelope))
        verified_license = tool_root / "work/candidate/dependencies/godot-cpp/LICENSE.md"
        verified_license.parent.mkdir(parents=True)
        verified_license.write_bytes((self.install / "LICENSE.godot-cpp.md").read_bytes())
        with patch.object(package, "_mac_builder", return_value=fake):
            self.assertEqual(package.verified_mac_install(tool_root, self.editor), envelope)
            with patch.object(fake, "validate_signing_pair", side_effect=ValueError("signing pair mismatch")) as signing:
                with self.assertRaisesRegex(ValueError, "signing pair mismatch"):
                    package.verified_mac_install(tool_root, self.editor)
                signing.assert_called_once_with(candidate, mutant)
            installed_license = self.install / "LICENSE.godot-cpp.md"
            original_license = installed_license.read_bytes()
            installed_license.write_bytes(original_license + b" tampered")
            with self.assertRaises(ValueError):
                package.verified_mac_install(tool_root, self.editor)
            installed_license.unlink()
            with self.assertRaises(ValueError):
                package.verified_mac_install(tool_root, self.editor)
            installed_license.write_bytes(original_license)
            (tool_root / "results-9999999999.json").write_bytes(
                (tool_root / evidence["base_oracle"]["results"]).read_bytes())
            self.assertEqual(package.verified_mac_install(tool_root, self.editor), envelope)
            ignore.unlink()
            with self.assertRaises(ValueError):
                package.verified_mac_install(tool_root, self.editor)
            ignore.mkdir()
            with self.assertRaises(ValueError):
                package.verified_mac_install(tool_root, self.editor)
            ignore.rmdir()
            ignore.touch()
            original_is_symlink = Path.is_symlink
            with patch.object(Path, "is_symlink", autospec=True,
                              side_effect=lambda item: item == ignore or original_is_symlink(item)):
                with self.assertRaises(ValueError):
                    package.verified_mac_install(tool_root, self.editor)
            for key in ("base_oracle", "negative_control"):
                cited_report = tool_root / evidence[key]["results"]
                saved_report = cited_report.read_bytes()
                cited_report.unlink()
                with self.assertRaises(ValueError):
                    package.verified_mac_install(tool_root, self.editor)
                cited_report.write_bytes(saved_report + b" ")
                with self.assertRaises(ValueError):
                    package.verified_mac_install(tool_root, self.editor)
                cited_report.write_bytes(saved_report)
                with patch.object(Path, "is_symlink", autospec=True,
                                  side_effect=lambda item: item == cited_report or original_is_symlink(item)):
                    with self.assertRaises(ValueError):
                        package.verified_mac_install(tool_root, self.editor)
            original_report = tool_root / evidence["base_oracle"]["results"]
            report_bytes = original_report.read_bytes()
            for key, field, value in (("base_oracle", "results", "../results-2026111201.json"),
                                      ("base_oracle", "results", "not-the-oracle.json"),
                                      ("base_oracle", "compared", 16),
                                      ("base_oracle", "compared", True),
                                      ("base_oracle", "results_sha256", "A" * 64),
                                      ("negative_control", "results", "results-2026111201.json"),
                                      ("negative_control", "verdict", "pass")):
                altered = copy.deepcopy(envelope)
                altered["platforms"]["macos"]["verification"][key][field] = value
                path.write_text(json.dumps(altered))
                with self.assertRaises(ValueError):
                    package.verified_mac_install(tool_root, self.editor)
            for mutation in ("missing", "extra", "record-extra"):
                altered = copy.deepcopy(envelope)
                citations = altered["platforms"]["macos"]["verification"]
                if mutation == "missing": citations.pop("negative_control")
                elif mutation == "extra": citations["unrecognized"] = {}
                else: citations["base_oracle"]["unexpected"] = "x"
                path.write_text(json.dumps(altered))
                with self.assertRaises(ValueError):
                    package.verified_mac_install(tool_root, self.editor)
            path.write_text(json.dumps(envelope))
            invalid = json.loads(report_bytes)
            invalid["valid"] = False
            original_report.write_text(json.dumps(invalid))
            altered = copy.deepcopy(envelope)
            altered["platforms"]["macos"]["verification"]["base_oracle"]["results_sha256"] = package.sha(original_report)
            path.write_text(json.dumps(altered))
            with self.assertRaisesRegex(ValueError, "oracle identity refused"):
                package.verified_mac_install(tool_root, self.editor)
            original_report.write_bytes(report_bytes)
            for field, value in (("runtime_os_build", "changed"), ("verification", {}), ("binary_sha256", "0" * 64)):
                altered = copy.deepcopy(envelope)
                altered["platforms"]["macos"][field] = value
                path.write_text(json.dumps(altered))
                with self.assertRaises(ValueError):
                    package.verified_mac_install(tool_root, self.editor)
            path.write_text(json.dumps(envelope))
            library.write_bytes(b"changed library")
            with self.assertRaises(ValueError):
                package.verified_mac_install(tool_root, self.editor)


class MacCitedEvidenceTests(unittest.TestCase):
    def test_cited_reports_reuse_full_oracle_verification_and_ignore_newer_runs(self):
        fixture = macos_evidence_tests.ExperimentalEvidence(methodName="runTest")
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        mac = macos_evidence_tests.mac
        base = fixture.evidence()
        fixture.seal(base)
        fixture.result.write_text(json.dumps(base))

        mutant = copy.deepcopy(fixture.built)
        mutant["binary_sha256"] = "b" * 64
        mutant["descriptor"] = str(fixture.root / "mutant.gdextension")
        mutant["library"] = str(fixture.root / "lib/libopenrc_native_kernel_mutant.dylib")
        negative_path = fixture.root / "stage_mutant-20261112.json"
        negative = copy.deepcopy(base)
        negative.update({"format": "openrc-nk3-stage-oracle v1", "verdict": "fail", "build_receipt": mutant,
                         "binary_sha256_before": mutant["binary_sha256"], "binary_sha256_after": mutant["binary_sha256"]})
        stage = verification_tests.evidence("stage_oracle")
        negative["components"] = stage["components"]
        negative["coverage"] = stage["coverage"]
        negative["components"]["stage_bytes"]["identical"] -= 1
        compared = sum(item["count"] for item in negative["components"].values())
        negative["total"] = {"compared": compared, "identical": compared - 1, "mismatched": 1}
        checked = negative["checked_run"]
        checked.update(ok=False, reason="process_exit", process_exit=1, required_text=["NK3_ORACLE verdict=fail"])
        command = checked["command"]
        command[command.index("--script") + 1] = str(fixture.here / "stage_oracle.gd")
        checked["command"] = [f"--extension={mutant['descriptor']}" if arg.startswith("--extension=")
                              else f"--output={negative_path}" if arg.startswith("--output=") else arg for arg in command]
        fixture.seal(negative, negative_path, marker="NK3_ORACLE verdict=fail")
        negative_path.write_text(json.dumps(negative))
        roster = {"base_oracle": "results-[0-9]*.json", "negative_control": "stage_mutant-[0-9]*.json"}
        cited = {"base_oracle": {"results": fixture.result.name, "results_sha256": package.sha(fixture.result),
                                  "verdict": "pass", "compared": base["total"]["compared"]},
                 "negative_control": {"results": negative_path.name, "results_sha256": package.sha(negative_path),
                                      "verdict": "fail", "compared": compared}}
        with patch.object(mac, "verification_roster", return_value=roster), \
                patch.object(mac, "_runner", return_value=fixture.Runner()):
            package._validate_mac_cited_evidence(fixture.root, cited, fixture.built, mutant, mac)
            newer = fixture.root / "results-9999999999.json"
            later = copy.deepcopy(base)
            later["checked_run"]["command"] = [f"--output={newer}" if arg.startswith("--output=") else arg
                                                 for arg in later["checked_run"]["command"]]
            fixture.seal(later, newer)
            newer.write_text(json.dumps(later))
            mac._check_oracle_identity(later, newer, "base_oracle", fixture.built, {}, fixture.Runner())
            package._validate_mac_cited_evidence(fixture.root, cited, fixture.built, mutant, mac)

            original_log = Path(base["checked_run"]["log"])
            saved_log = original_log.read_bytes()
            original_log.write_bytes(b"corrupted checked log")
            with self.assertRaises(ValueError):
                package._validate_mac_cited_evidence(fixture.root, cited, fixture.built, mutant, mac)
            original_log.write_bytes(saved_log)

            saved_report = fixture.result.read_bytes()
            original_check = mac._check_oracle_identity

            def mutate_after_check(data, result, key, built, cache, runner):
                original_check(data, result, key, built, cache, runner)
                if result == fixture.result:
                    result.write_bytes(saved_report + b" ")

            with patch.object(mac, "_check_oracle_identity", side_effect=mutate_after_check):
                with self.assertRaisesRegex(ValueError, "count or bytes changed"):
                    package._validate_mac_cited_evidence(fixture.root, cited, fixture.built, mutant, mac)
            fixture.result.write_bytes(saved_report)

            changed = copy.deepcopy(base)
            changed["engine_sha256_after"] = "0" * 64
            fixture.result.write_text(json.dumps(changed))
            changed_citation = copy.deepcopy(cited)
            changed_citation["base_oracle"]["results_sha256"] = package.sha(fixture.result)
            with self.assertRaises(ValueError):
                package._validate_mac_cited_evidence(fixture.root, changed_citation, fixture.built, mutant, mac)


if __name__ == "__main__":
    unittest.main()
