#!/usr/bin/env python3
"""Portable integration controls; no Godot export or native binary is executed."""
from __future__ import annotations

import argparse
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

HERE = Path(__file__).resolve().parent


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


package = load("pair_export_package", HERE / "package.py")
fixtures = load("pair_export_fixtures", HERE / "test_macos_engine_pair.py")


class PairExportIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.PairBindingTests(methodName="runTest")
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)
        self.root = self.f.root
        self.install = self.root / "app/native/kernel"
        self.install.mkdir(parents=True)
        self.library = self.install / "libopenrc_native_kernel.dylib"
        self.library.write_bytes(b"synthetic signed native library")
        (self.install / "LICENSE.godot-cpp.md").write_bytes(b"fixture licence")
        for area in ("physics", "sim", "failures"):
            path = self.root / "app" / area / "fixture.gd"
            path.parent.mkdir(parents=True)
            path.write_text("fixture", encoding="utf-8")
        export_plugin = self.root / "app/addons/native_kernel/export_plugin.gd"
        export_plugin.parent.mkdir(parents=True)
        export_plugin.write_text("synthetic export plugin", encoding="utf-8")
        self.diagnostics = {}
        for name in package.MAC_QUALIFICATION:
            path = self.root / "diagnostics" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name, encoding="utf-8")
            self.diagnostics[name] = path
        self.manifest = self.install / "package-macos.json"
        self.pins = self.root / "binding-pins.json"
        self.pins.write_text(json.dumps(self.f.expected), encoding="utf-8")
        self.pair_selection = {"template_intake": self.f.template, "pair_receipt": self.f.receipt,
                               "export_template": self.f.export, "pins": self.pins}
        self.editor_identity = self.f.identify(self.f.binaries["editor"], self.f.lock, self.f.selection)
        self.receipt = {"platforms": {"macos": {"engine_version": fixtures.policy.RESEARCH_RUNTIME,
                                                "engine_sha256": self.f.expected["editor_sha256"],
                                                "binary_sha256": package.sha(self.library),
                                                "engine": self.editor_identity}}}
        # Load the real reviewed binder; stub only native platform observations,
        # exactly as in its portable fixture. No bind() result is fabricated.
        self.binder = package._pair_binder()
        for owner, name, value in ((self.binder, "_engine", fixtures.engine),
                                   (self.binder, "_mac_builder", self.f.mac),
                                   (package, "_pair_binder", self.binder),
                                   (package, "ROOT", self.root),
                                   (package, "MAC_MANIFEST", self.manifest),
                                   (package, "MAC_QUALIFICATION", self.diagnostics),
                                   (package.builder, "APP_DESTINATION", self.install)):
            replacement = (lambda value=value: value) if name in ("_engine", "_mac_builder", "_pair_binder") else value
            mocked = patch.object(owner, name, replacement)
            mocked.start()
            self.addCleanup(mocked.stop)
        verified = patch.object(package, "verified_mac_install", return_value=self.receipt)
        verified.start()
        self.addCleanup(verified.stop)
        self.tool_root = self.root / "tmp/tool"
        self.editor = self.f.binaries["editor"]
        self.bundle = self.root / "OpenRC.app"
        (self.bundle / "Contents/Resources").mkdir(parents=True)
        self.checked_runner = self.root / "tools/godot/run_checked.py"
        self.checked_runner.parent.mkdir(parents=True)
        shutil.copyfile(HERE.parents[1] / "tools/godot/run_checked.py", self.checked_runner)
        self.report = self.root / "checks/export/report.json"
        self.report.parent.mkdir(parents=True)
        self.log = self.report.parent / "engine.log"
        self.markers = [f"OPENRC_MAC_PAIR_EXPORT_{phase} {self.f.expected['editor_sha256']} "
                        f"{self.f.expected['export_template_sha256']}" for phase in ("BEGIN", "END")]
        self.log.write_text("\n".join(self.markers) + "\n", encoding="utf-8")
        self.checked = {"format": "openrc-godot-check v1", "ok": True, "complete": True, "process_exit": 0,
                        "exit_code": 0, "reason": "passed", "required_text": self.markers,
                        "missing_required_text": [], "counts": {"error": 0, "warning": 0},
                        "log": str(self.log), "log_sha256": package.sha(self.log),
                        "log_bytes": self.log.stat().st_size, "report": str(self.report),
                        "command": [str(self.editor), "--headless", "--path", str(self.root / "app"),
                                    "--export-release", "macOS", str(self.bundle)]}
        self.write_report()

    def write_report(self):
        self.report.write_text(json.dumps(self.checked), encoding="utf-8")

    def prepare(self, pair_selection=None):
        return package.prepare_macos(self.tool_root, self.editor, self.f.selection,
                                     pair_selection=pair_selection or self.pair_selection)

    def stage(self, pair_selection=None):
        return package.stage_macos(self.bundle, self.tool_root, self.editor, self.f.selection,
                                   pair_selection=pair_selection or self.pair_selection)

    def verify(self):
        return package.verify_macos_export(self.bundle, self.tool_root, self.editor, self.f.selection,
                                           pair_selection=self.pair_selection)

    def test_real_binding_is_embedded_staged_and_checked_again_at_final_boundary(self):
        with patch.object(self.binder, "bind", wraps=self.binder.bind) as actual_bind:
            self.prepare()
            saved = json.loads(self.manifest.read_text(encoding="utf-8"))
            self.assertEqual(saved["engine_pair"], self.f.expected)
            self.stage()
            final = self.verify()
            self.assertEqual(final["engine_pair"], self.f.expected)
            def create_receipt(bundle, _manifest):
                path = bundle.with_name(bundle.name + ".openrc-native-receipt")
                path.write_bytes(b"synthetic receipt")
                return path
            release = SimpleNamespace(NATIVE_SUFFIX=".openrc-native-receipt", create_native=create_receipt)
            with patch.object(package, "_mac_release_tool", return_value=release):
                result = package.finalize_research_macos(self.bundle, self.tool_root, self.editor, self.f.selection,
                                                        pair_selection=self.pair_selection,
                                                        checked_export_report=self.report)
            self.assertEqual(result["engine_pair"], self.f.expected)
            self.assertGreaterEqual(actual_bind.call_count, 9)
        bundled = self.bundle / "Contents/Frameworks/libopenrc_native_kernel.dylib"
        bundled.write_bytes(b"changed staged library")
        with self.assertRaisesRegex(ValueError, "files differ"):
            self.verify()

    def test_different_individually_valid_template_and_binding_cannot_replace_prepared_pair(self):
        self.prepare()
        alternative = self.root / "valid-other-export.zip"
        with zipfile.ZipFile(self.f.export) as original, zipfile.ZipFile(alternative, "w") as changed:
            for info in reversed(original.infolist()):
                changed.writestr(info, original.read(info))
        self.assertNotEqual(package.sha(alternative), package.sha(self.f.export))
        other_pins = {**self.f.expected, "export_template_sha256": package.sha(alternative)}
        other_path = self.root / "other-pins.json"
        other_path.write_text(json.dumps(other_pins), encoding="utf-8")
        other = {**self.pair_selection, "export_template": alternative, "pins": other_path}
        self.assertEqual(package._research_pair(self.editor, self.f.selection, other), other_pins)
        with self.assertRaisesRegex(ValueError, "changed since preparation"):
            self.stage(other)
        self.assertFalse((self.bundle / "Contents/Frameworks").exists())

    def test_template_mutation_during_staging_is_refused(self):
        self.prepare()
        real_sha = package.sha
        library_in_bundle = self.bundle / "Contents/Frameworks/libopenrc_native_kernel.dylib"
        changed = []
        def mutate_after_copy(path):
            value = real_sha(path)
            if path == library_in_bundle and not changed:
                self.f.export.write_bytes(self.f.export.read_bytes() + b" ")
                changed.append(True)
            return value
        with patch.object(package, "sha", side_effect=mutate_after_copy):
            with self.assertRaises(ValueError):
                self.stage()
        self.assertEqual(changed, [True])

    def test_manifest_byte_change_during_staging_is_refused(self):
        self.prepare()
        real_sha = package.sha
        library_in_bundle = self.bundle / "Contents/Frameworks/libopenrc_native_kernel.dylib"
        changed = []
        def mutate_after_copy(path):
            value = real_sha(path)
            if path == library_in_bundle and not changed:
                self.manifest.write_bytes(self.manifest.read_bytes() + b" ")
                changed.append(True)
            return value
        with patch.object(package, "sha", side_effect=mutate_after_copy):
            with self.assertRaisesRegex(ValueError, "changed during staging"):
                self.stage()
        self.assertEqual(changed, [True])

    def test_duplicate_manifest_keys_are_rejected_before_staging(self):
        self.prepare()
        raw = self.manifest.read_text(encoding="utf-8")
        self.manifest.write_text(raw.replace('"format":', '"format": "forged", "format":', 1), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Duplicate receipt key"):
            self.stage()
        self.assertFalse((self.bundle / "Contents/Frameworks").exists())

    def test_changed_export_plugin_or_checked_runner_refuses_staging(self):
        self.prepare()
        plugin = self.root / "app/addons/native_kernel/export_plugin.gd"
        for path in (plugin, self.checked_runner):
            original = path.read_bytes()
            path.write_bytes(original + b" changed")
            with self.subTest(path=path.name), self.assertRaisesRegex(ValueError, "changed since preparation"):
                self.stage()
            path.write_bytes(original)
        self.assertFalse((self.bundle / "Contents/Frameworks").exists())

    def test_independent_pins_are_stable_across_binding(self):
        actual = self.binder.bind
        def mutate_pins(*args, **kwargs):
            result = actual(*args, **kwargs)
            self.pins.write_bytes(self.pins.read_bytes() + b" ")
            return result
        with patch.object(self.binder, "bind", side_effect=mutate_pins):
            with self.assertRaisesRegex(ValueError, "pins changed"):
                package._research_pair(self.editor, self.f.selection, self.pair_selection)

    def test_installed_editor_provenance_must_match_fresh_pair(self):
        altered = copy.deepcopy(self.receipt)
        altered["platforms"]["macos"]["engine"]["research_engine"]["source_catalog_sha256"] = "f" * 64
        with patch.object(package, "verified_mac_install", return_value=altered):
            with self.assertRaisesRegex(ValueError, "installed research editor provenance"):
                self.prepare()
        self.assertFalse(self.manifest.exists())

    def test_checked_export_requires_matching_editor_bundle_and_clean_ordered_callbacks(self):
        runner_sha = package.sha(self.checked_runner)
        self.assertEqual(package._checked_macos_export(self.report, self.bundle, self.f.expected, runner_sha)["editor_sha256"],
                         self.f.expected["editor_sha256"])
        original = copy.deepcopy(self.checked)
        wrong_editor = self.root / "other-editor"
        wrong_editor.write_bytes(b"different editor")
        variants = [lambda report: report.update(complete=False),
                    lambda report: report["command"].__setitem__(0, str(wrong_editor)),
                    lambda report: report["command"].__setitem__(-1, str(self.root / "Other.app")),
                    lambda report: report.update(required_text=self.markers[:1])]
        for mutate in variants:
            self.checked = copy.deepcopy(original)
            mutate(self.checked)
            self.write_report()
            with self.subTest(mutation=mutate), self.assertRaises(ValueError):
                package._checked_macos_export(self.report, self.bundle, self.f.expected, runner_sha)
        self.checked = copy.deepcopy(original)
        self.log.write_text("\n".join("\x1b[0m" + marker for marker in self.markers) + "\n", encoding="utf-8")
        self.checked["log_sha256"] = package.sha(self.log)
        self.checked["log_bytes"] = self.log.stat().st_size
        self.write_report()
        package._checked_macos_export(self.report, self.bundle, self.f.expected, runner_sha)
        self.log.write_text("\n".join(self.markers[::-1]) + "\n", encoding="utf-8")
        self.checked["log_sha256"] = package.sha(self.log)
        self.checked["log_bytes"] = self.log.stat().st_size
        self.write_report()
        with self.assertRaisesRegex(ValueError, "ordered pair callbacks"):
            package._checked_macos_export(self.report, self.bundle, self.f.expected, runner_sha)


class PairCommandTests(unittest.TestCase):
    def setUp(self):
        self.policy = load("pair_command_policy", HERE / "macos_engine_identity.py")
        self.fake_mac = SimpleNamespace(engine_policy=self.policy,
                                        add_toolchain_arguments=self.policy.add_toolchain_arguments)

    def test_missing_mixed_and_repeated_pair_arguments_refuse_before_prepare(self):
        policy = self.policy
        research = ["--research-engine-sha256", "a" * 64, "--research-engine-cli-version", policy.RESEARCH_CLI,
                    "--research-engine-runtime-version", policy.RESEARCH_RUNTIME,
                    "--research-engine-build-receipt", "editor/build-editor.json", "--research-engine-archive", "source.zip",
                    "--research-engine-extension-api", "extension_api-4-7.json", "--research-engine-reference-godot", "official",
                    "--research-engine-patch", "one.patch", "--research-engine-toolchain-profile", policy.NEW_TOOLCHAIN_PROFILE]
        pair_args = ["--pair-template-intake", "template", "--pair-receipt", "pair.json",
                     "--pair-export-template", "export.zip", "--pair-binding-pins", "pins.json"]
        base = ["package.py", "prepare-macos", "--tool-root", "tool", "--godot", "editor"]
        for extra in (research, research + pair_args[:-2], pair_args):
            with self.subTest(extra=extra), patch.object(package, "_mac_builder", return_value=self.fake_mac), \
                    patch.object(package, "prepare_macos") as prepare, patch.object(sys, "argv", base + extra), \
                    self.assertRaisesRegex(ValueError, "supplied together"):
                package.main()
            prepare.assert_not_called()
        with patch.object(package, "_mac_builder", return_value=self.fake_mac), \
                patch.object(sys, "argv", base + research + pair_args + pair_args[-2:]), \
                contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            package.main()

    def test_binding_cannot_be_smuggled_into_official_route(self):
        with self.assertRaisesRegex(ValueError, "supplied together"):
            package._mac_manifest(Path("tool"), Path("editor"), None,
                                  pair_selection={"template_intake": "one"})
        with self.assertRaisesRegex(ValueError, "supplied together"):
            package._mac_manifest(Path("tool"), Path("editor"), {"sha256": "a" * 64})

    def test_failed_final_revalidation_removes_only_its_created_receipt(self):
        with tempfile.TemporaryDirectory(prefix="pair-final-test-") as directory:
            bundle = Path(directory) / "OpenRC.app"
            bundle.mkdir()
            destination = bundle.with_name(bundle.name + ".openrc-native-receipt")
            def create_receipt(_bundle, _manifest):
                destination.write_bytes(b"new receipt")
                return destination
            release = SimpleNamespace(NATIVE_SUFFIX=".openrc-native-receipt", create_native=create_receipt)
            with patch.object(package, "_mac_release_tool", return_value=release), \
                    patch.object(package, "_checked_macos_export", return_value={"report_sha256": "b" * 64}), \
                    patch.object(package, "verify_macos_export", side_effect=[{"manifest_sha256": "a" * 64,
                                                                               "engine_pair": {}, "export_runner_sha256": "c" * 64},
                                                                              ValueError("changed")]):
                with self.assertRaisesRegex(ValueError, "changed"):
                    package.finalize_research_macos(bundle, Path("tool"), Path("editor"), {}, pair_selection={},
                                                    checked_export_report=Path("report.json"))
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
