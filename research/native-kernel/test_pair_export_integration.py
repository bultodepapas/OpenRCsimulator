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
        self.executable = self.bundle / "Contents/MacOS/OpenRC"
        self.executable.parent.mkdir(parents=True)
        self.executable.write_bytes(self.f.binaries["template_release"].read_bytes() + b"\nFAKE_APP_SIGNATURE")
        def fake_codesign(args):
            path = Path(args[-1])
            data = path.read_bytes()
            if args[0] == "--remove-signature":
                path.write_bytes(data.removesuffix(b"\nFAKE_APP_SIGNATURE"))
            elif args[0] == "--force":
                path.write_bytes(data + b"\nFAKE_NORMAL_SIGNATURE")
            elif args[0] == "--verify":
                if not data.endswith(b"\nFAKE_NORMAL_SIGNATURE"):
                    raise ValueError("fake normalized signature is absent")
            else:
                raise AssertionError(args)
        signer = patch.object(self.binder, "_codesign", side_effect=fake_codesign)
        signer.start()
        self.addCleanup(signer.stop)
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

    def prepared_project(self):
        """Make a small real-validator fixture in the shape produced by prepare_research.py."""
        canonical = self.root / "app"
        (canonical / "project.godot").write_bytes(
            b'config/name="OpenRC Simulator"\n'
            b'lights_and_shadows/multi_bounce_occlusion/enabled=true\n')
        validator_path = self.root / "research/native-kernel/run.py"
        validator_path.parent.mkdir(parents=True)
        shutil.copyfile(HERE / "run.py", validator_path)
        validator = load("prepared_project_fixture_validator", validator_path)
        source = validator._project_inventory(canonical)
        project = self.root / "tmp/prepared/app"
        shutil.copytree(canonical, project)
        name = "OpenRC-Research-0123456789abcdef0123456789abcdef"
        original = (project / "project.godot").read_bytes()
        edited = original.replace(b'config/name="OpenRC Simulator"', f'config/name="{name}"'.encode(), 1)
        edited = edited.replace(b"lights_and_shadows/multi_bounce_occlusion/enabled=true",
                                b"lights_and_shadows/multi_bounce_occlusion/enabled=false", 1)
        (project / "project.godot").write_bytes(edited)
        receipt = project.parent / "research-preparation.json"
        receipt.write_text(json.dumps({
            "format": "openrc-graphics-research-preparation v1", "complete": True,
            "source": {"copied_app_manifest_sha256": validator._inventory_hash(source),
                       "native_kernel_inventory": [item for item in source
                                                   if item["path"].startswith("native/kernel/")]},
            "destination": {"app": str(project), "project_name": name,
                            "project_sha256": package.sha(project / "project.godot")},
        }), encoding="utf-8")
        probe = self.root / "research/performance/session_probe.gd"
        probe.parent.mkdir(parents=True)
        probe.write_text("the fixed probe", encoding="utf-8")
        prepared_probe = project.parent / "research/performance/session_probe.gd"
        prepared_probe.parent.mkdir(parents=True)
        shutil.copyfile(probe, prepared_probe)
        self.checked["command"][3] = str(project)
        self.write_report()
        self.assertTrue(validator.validate_project(project))
        return project, validator

    def checked_export(self):
        return package._checked_macos_export(self.report, self.bundle, self.f.expected,
                                             package.sha(self.checked_runner))

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
            project, _validator = self.prepared_project()
            self.stage()
            final = self.verify()
            self.assertEqual(final["engine_pair"], self.f.expected)
            self.assertEqual(final["executable_binding"]["template_sha256"], self.f.expected["template_sha256"])
            self.assertEqual(final["executable_binding"]["executable_sha256"], package.sha(self.executable))
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
            self.assertEqual(result["executable_binding"], final["executable_binding"])
            self.assertEqual(result["checked_export"]["prepared_project"]["project"], str(project))
            self.assertGreaterEqual(actual_bind.call_count, 9)
        bundled = self.bundle / "Contents/Frameworks/libopenrc_native_kernel.dylib"
        bundled.write_bytes(b"changed staged library")
        with self.assertRaisesRegex(ValueError, "files differ"):
            self.verify()

    def test_replaced_executable_refuses_even_if_pair_and_sidecars_are_unchanged(self):
        self.prepare()
        self.stage()
        initial = self.verify()
        content = bytearray(self.executable.read_bytes())
        content[32] ^= 1 # mutate payload without changing size or the simulated signing trailer
        self.executable.write_bytes(content)
        with self.assertRaisesRegex(ValueError, "differs from the selected release template"):
            self.verify()
        self.assertEqual(initial["engine_pair"], self.f.expected)

    def test_official_export_does_not_invoke_pair_or_executable_normalization(self):
        package.prepare_macos(self.tool_root, self.editor)
        package.stage_macos(self.bundle, self.tool_root, self.editor)
        with patch.object(package, "_pair_binder", side_effect=AssertionError("unexpected pair lookup")):
            result = package.verify_macos_export(self.bundle, self.tool_root, self.editor)
        self.assertNotIn("engine_pair", result)
        self.assertNotIn("executable_binding", result)

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

    def test_prepared_export_uses_real_validator_and_binds_project_and_sibling_probe(self):
        self.assertNotIn("prepared_project", self.checked_export())
        project, validator = self.prepared_project()
        binding = self.checked_export()["prepared_project"]
        self.assertEqual(binding["project"], str(project))
        self.assertEqual(binding["inventory"], validator.validate_project(project))
        self.assertEqual(binding["preparation_sha256"], package.sha(project.parent / "research-preparation.json"))
        self.assertEqual(binding["validator_sha256"], package.sha(self.root / "research/native-kernel/run.py"))
        self.assertEqual(binding["session_probe_sha256"], package.sha(self.root / "research/performance/session_probe.gd"))
        self.assertEqual(binding, self.checked_export()["prepared_project"])

    def test_prepared_export_refuses_changed_inventory_settings_and_probe(self):
        project, _validator = self.prepared_project()
        paths = [project / "physics/fixture.gd", project / "project.godot",
                 project.parent / "research/performance/session_probe.gd",
                 self.root / "app/sim/fixture.gd", project.parent / "research-preparation.json"]
        for path in paths:
            original = path.read_bytes()
            path.write_bytes(original + b" changed")
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.checked_export()
            path.write_bytes(original)
        extra = project / "extra.gd"
        extra.write_text("unexpected", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "project content differs"):
            self.checked_export()
        extra.unlink()
        missing = project / "failures/fixture.gd"
        data = missing.read_bytes()
        missing.unlink()
        with self.assertRaisesRegex(ValueError, "project content differs"):
            self.checked_export()
        missing.write_bytes(data)
        self.assertIn("prepared_project", self.checked_export())

    def test_native_artifact_drift_allowed_by_general_validator_is_refused_for_export(self):
        project, validator = self.prepared_project()
        self.library.write_bytes(b"a newer canonical installation")
        self.assertTrue(validator.validate_project(project))
        with self.assertRaisesRegex(ValueError, "native artifacts differ"):
            self.checked_export()

    def test_prepared_export_refuses_project_outside_tmp_and_missing_probe(self):
        project, _validator = self.prepared_project()
        outside = self.root / "elsewhere/app"
        shutil.copytree(project, outside)
        self.checked["command"][3] = str(outside)
        self.write_report()
        with self.assertRaisesRegex(ValueError, "below the repository tmp"):
            self.checked_export()
        self.checked["command"][3] = str(self.root / "tmp/prepared/../../elsewhere/app")
        self.write_report()
        with self.assertRaisesRegex(ValueError, "below the repository tmp"):
            self.checked_export()
        link = self.root / "tmp/prepared-link"
        try:
            link.symlink_to(project, target_is_directory=True)
        except (OSError, NotImplementedError):
            pass  # Some Windows accounts cannot create directory links.
        else:
            self.checked["command"][3] = str(link)
            self.write_report()
            with self.assertRaisesRegex(ValueError, "Redirected|Symbolic-link"):
                self.checked_export()
        self.checked["command"][3] = str(project)
        self.write_report()
        (project.parent / "research/performance/session_probe.gd").unlink()
        with self.assertRaisesRegex(ValueError, "Missing or inaccessible"):
            self.checked_export()

    def test_prepared_export_revalidates_after_log_inspection(self):
        project, _validator = self.prepared_project()
        receipt = project.parent / "research-preparation.json"
        receipt_bytes = receipt.read_bytes()
        runner_text = self.checked_runner.read_text(encoding="utf-8")
        # Change only harmless receipt whitespace inside the real log inspection;
        # a second real validation still succeeds, but the bound identity changes.
        with self.checked_runner.open("a", encoding="utf-8") as runner:
            runner.write("\n_original_inspect_log = inspect_log\n"
                         "def inspect_log(*args, **kwargs):\n"
                         "    result = _original_inspect_log(*args, **kwargs)\n"
                         f"    with open({str(receipt)!r}, 'ab') as changed: changed.write(b' ')\n"
                         "    return result\n")
        with self.assertRaisesRegex(ValueError, "project changed during checked export validation"):
            self.checked_export()
        receipt.write_bytes(receipt_bytes)
        changed = project / "physics/fixture.gd"
        self.checked_runner.write_text(
            runner_text + "\n_original_inspect_log = inspect_log\n"
            "def inspect_log(*args, **kwargs):\n"
            "    result = _original_inspect_log(*args, **kwargs)\n"
            f"    with open({str(changed)!r}, 'wb') as changed: changed.write(b'changed')\n"
            "    return result\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "project content differs"):
            self.checked_export()


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
