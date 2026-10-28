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
        self.lock.write_text(json.dumps({"godot": {"version": "4.8.beta1.official.4d10419ca"}}))
        self.editor = self.root / ".tools/Godot_v4.8-beta1_linux.x86_64"
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
        for name in ("oracle.gd", "stage_oracle.gd", "stage_adapter.gd", "trajectory.gd", "run.py"):
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
            data["binary_sha256_before"] = data["binary_sha256_after"] = self.binary_sha
            data["sources"] = {name.replace("app/", "res://", 1): digest for name, digest in self.sources.items()}
            data["sources_after"] = copy.deepcopy(data["sources"])
            harness = [self.tool / name for name in ("oracle.gd", "stage_oracle.gd", "stage_adapter.gd", "run.py", "trajectory.gd")]
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
            ("abi_version", True), ("abi_version", 1.0), ("abi_version", "1"), ("abi_version", 2),
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
                             ("abi_version", True), ("abi_version", 1.0), ("abi_version", "1"),
                             ("abi_version", 2), ("platform", "windows"), ("architecture", "arm64"),
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


if __name__ == "__main__":
    unittest.main()
