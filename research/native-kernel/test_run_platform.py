"""Native oracle routing must never read Linux evidence for a Mac process."""
from __future__ import annotations

import importlib.util
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("nk_oracle_platform_tests", HERE / "run.py")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class OraclePlatformTests(unittest.TestCase):
    def test_install_outputs_can_advance_only_in_canonical_app(self):
        with tempfile.TemporaryDirectory(prefix="nk-install-inventory-") as directory:
            root = Path(directory)
            canonical = root / "app"
            project = root / "prepared/app"
            original = (b'[application]\nconfig/name="OpenRC Simulator"\n'
                        b'lights_and_shadows/multi_bounce_occlusion/enabled=true\n')
            name = "OpenRC-Research-" + "b" * 32
            prepared = original.replace(b'config/name="OpenRC Simulator"', f'config/name="{name}"'.encode()).replace(b"enabled=true", b"enabled=false")
            for app in (canonical, project):
                (app / "native/kernel").mkdir(parents=True)
                (app / "native/kernel/other.gd").write_bytes(b"# frozen fixture")
                (app / "project.godot").write_bytes(original if app == canonical else prepared)
            with patch.object(runner, "ROOT", root):
                source_inventory = runner._project_inventory(canonical)
                receipt = {"format": "openrc-graphics-research-preparation v1", "complete": True,
                           "source": {"copied_app_manifest_sha256": runner._inventory_hash(source_inventory),
                                      "native_kernel_inventory": [row for row in source_inventory if row['path'].startswith('native/kernel/')]},
                           "destination": {"app": str(project), "project_name": name,
                                           "project_sha256": hashlib.sha256(prepared).hexdigest()}}
                record = project.parent / "research-preparation.json"
                record.write_text(json.dumps(receipt))
                before = runner.validate_project(project.resolve())
                for name in ('libopenrc_native_kernel.dylib', 'openrc_native_kernel_macos.gdextension',
                             'build-receipt-macos.json', 'package-macos.json', '.gdignore', 'LICENSE.godot-cpp.md'):
                    (canonical / 'native/kernel' / name).write_bytes(name.encode())
                self.assertEqual(runner.validate_project(project.resolve()), before)
                # This entire prepared inventory remains frozen, even for install outputs.
                changed = project / 'native/kernel/libopenrc_native_kernel.dylib'
                changed.write_bytes(b'changed target binary')
                with self.assertRaisesRegex(ValueError, 'content differs'):
                    runner.validate_project(project.resolve())
                changed.unlink()
                changed = canonical / 'native/kernel/other.gd'
                changed.write_bytes(b'# changed non-generated code')
                with self.assertRaisesRegex(ValueError, 'Canonical app changed'):
                    runner.validate_project(project.resolve())
                changed.write_bytes(b'# frozen fixture')
                del receipt['source']['native_kernel_inventory']
                record.write_text(json.dumps(receipt))
                with self.assertRaisesRegex(ValueError, 'Canonical app changed'):
                    runner.validate_project(project.resolve())

    def test_reconstructed_inventory_rejects_unsafe_or_repeated_entries(self):
        good = {'path': 'native/kernel/libopenrc_native_kernel.dylib', 'bytes': 1, 'sha256': 'a' * 64}
        for entries in ([good, good], [dict(good, path='native/kernel/../other.gd')],
                        [dict(good, bytes=True)], [dict(good, sha256='bad')]):
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                runner._prepared_source_inventory([], {'native_kernel_inventory': entries})

    def test_isolated_project_allows_only_recorded_name_and_render_setting(self):
        with tempfile.TemporaryDirectory(prefix="nk-oracle-project-") as directory:
            root = Path(directory)
            (root / "app").mkdir()
            canonical = (b'[application]\nconfig/name="OpenRC Simulator"\n'
                         b'[physics]\ncommon/physics_ticks_per_second=240\n'
                         b'[rendering]\nlights_and_shadows/multi_bounce_occlusion/enabled=true\n')
            (root / "app/project.godot").write_bytes(canonical)
            (root / "app/sim").mkdir()
            (root / "app/sim/collision_setup.gd").write_text("# original world fixture\n")
            project = root / "prepared/app"
            project.mkdir(parents=True)
            name = "OpenRC-Research-" + "a" * 32
            prepared = canonical.replace(b'config/name="OpenRC Simulator"',
                                          f'config/name="{name}"'.encode()).replace(b"enabled=true", b"enabled=false")
            (project / "project.godot").write_bytes(prepared)
            (project / "sim").mkdir()
            (project / "sim/collision_setup.gd").write_text("# original world fixture\n")
            with patch.object(runner, "ROOT", root):
                canonical_hash = runner._inventory_hash(runner._project_inventory(root / "app"))
            receipt = {"format": "openrc-graphics-research-preparation v1", "complete": True,
                       "source": {"copied_app_manifest_sha256": canonical_hash},
                       "destination": {"app": str(project), "project_name": name,
                                       "project_sha256": hashlib.sha256(prepared).hexdigest()}}
            (project.parent / "research-preparation.json").write_text(json.dumps(receipt))
            with patch.object(runner, "ROOT", root):
                runner.validate_project(project.resolve())
                self.assertEqual(runner.project_file(root / "app/sim/test.gd", project),
                                 project / "sim/test.gd")
                fixture = project / "sim/collision_setup.gd"
                fixture.write_text("# changed world fixture\n")
                with self.assertRaisesRegex(ValueError, "content differs"):
                    runner.validate_project(project.resolve())
                fixture.write_text("# original world fixture\n")
                for changed in [prepared.replace(b"=240", b"=120"), prepared + b"# changed\n"]:
                    (project / "project.godot").write_bytes(changed)
                    with self.assertRaisesRegex(ValueError, "settings differ"):
                        runner.validate_project(project.resolve())
                (project / "project.godot").write_bytes(prepared)
                (project / "override.cfg").write_text("[physics]\n")
                with self.assertRaisesRegex(ValueError, "settings differ"):
                    runner.validate_project(project.resolve())

    def test_mac_receipt_cannot_credit_a_different_engine_with_same_version(self):
        digest = "a" * 64
        receipt = {"platform": "macos", "architecture": "arm64", "engine_sha256": digest,
                   "engine": {"sha256": digest, "version": "4.8.beta2.official.cafc17a19"}}
        self.assertTrue(runner.macos_engine_matches(receipt, digest))
        self.assertFalse(runner.macos_engine_matches(receipt, "b" * 64))
        for field, value in [("architecture", "x86_64"), ("platform", "linux"),
                             ("engine_sha256", "b" * 64), ("engine", {})]:
            with self.subTest(field=field):
                changed = dict(receipt, **{field: value})
                self.assertFalse(runner.macos_engine_matches(changed, digest))

    def test_selects_process_architecture_without_rosetta_assumption(self):
        self.assertEqual(runner.host_platform_key("darwin", "arm64"), "macos.arm64")
        self.assertEqual(runner.host_platform_key("darwin", "aarch64"), "macos.arm64")
        self.assertEqual(runner.host_platform_key("win32", "AMD64"), "windows.x86_64")
        self.assertEqual(runner.host_platform_key("linux", "x86_64"), "linux.x86_64")
        for system, architecture in [("darwin", "x86_64"), ("linux", "arm64"),
                                     ("win32", "arm64"), ("freebsd", "x86_64")]:
            with self.subTest(system=system, architecture=architecture):
                with self.assertRaisesRegex(ValueError, "No qualified native oracle target"):
                    runner.host_platform_key(system, architecture)

    def test_mac_default_uses_bundle_executable(self):
        path = runner.default_godot("macos.arm64")
        self.assertEqual(path.name, "Godot")
        self.assertTrue(str(path).replace("\\", "/").endswith(
            "Godot_v4.8-beta2_macos.arm64/Godot.app/Contents/MacOS/Godot"))

    def test_descriptor_selects_only_mac_slice_and_fails_closed(self):
        with tempfile.TemporaryDirectory(prefix="nk-macos-descriptor-") as directory:
            descriptor = Path(directory) / "kernel.gdextension"
            descriptor.write_text('[libraries]\nlinux.x86_64="wrong.so"\nmacos.arm64="correct.dylib"\n')
            with patch.object(runner, "PLATFORM_KEY", "macos.arm64"):
                self.assertEqual(runner.selected_binary(descriptor),
                                 (descriptor.parent / "correct.dylib").resolve())
                descriptor.write_text('[libraries]\nlinux.x86_64="wrong.so"\n')
                with self.assertRaises(KeyError):
                    runner.selected_binary(descriptor)

    def test_res_binary_uses_the_executed_project_not_the_canonical_app(self):
        with tempfile.TemporaryDirectory(prefix="nk-project-library-") as directory:
            root = Path(directory)
            project = root / "prepared/app"
            canonical = root / "app"
            for app, contents in [(canonical, b"canonical"), (project, b"different prepared binary")]:
                (app / "native/kernel").mkdir(parents=True)
                (app / "native/kernel/kernel.dylib").write_bytes(contents)
            descriptor = project / "native/kernel/kernel.gdextension"
            descriptor.write_text('[libraries]\nmacos.arm64="res://native/kernel/kernel.dylib"\n')
            with patch.object(runner, "ROOT", root), patch.object(runner, "PLATFORM_KEY", "macos.arm64"):
                selected = runner.selected_binary(descriptor, project)
                self.assertEqual(selected, (project / "native/kernel/kernel.dylib").resolve())
                self.assertNotEqual(runner.sha256(selected),
                                    runner.sha256(canonical / "native/kernel/kernel.dylib"))


if __name__ == "__main__":
    unittest.main()
