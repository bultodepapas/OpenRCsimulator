"""Focused offline checks for current-source NVIDIA product packaging."""
from __future__ import annotations

import importlib.util
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("nvidia_product_tested", Path(__file__).with_name("product.py"))
assert SPEC and SPEC.loader
product = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(product)


def run_git(root: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class SnapshotTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="nvidia-product-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        run_git(self.root, "init", "--quiet")
        run_git(self.root, "config", "user.name", "Product test")
        run_git(self.root, "config", "user.email", "product-test@example.invalid")
        self.put("app/project.godot", b'[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        self.put("app/kept.gd", b"tracked\n")
        self.put("assets/aircraft/proof.json", b"proof\n")
        self.put("app/data/aircraft_models/test.json", json.dumps({"source_registry": {"path": "assets/aircraft/proof.json"},
            "geometry": {"source": {"path": "res://kept.gd"}}, "authoring_sources": [], "dependencies": []}).encode())
        self.put(".gitignore", b"/tmp/\napp/ignored.txt\n")
        run_git(self.root, "add", ".")
        run_git(self.root, "commit", "--quiet", "-m", "fixture")
        self.put("app/kept.gd", b"changed\n")
        self.put("app/new.gd", b"untracked\n")
        self.put("app/ignored.txt", b"ignored\n")
        patch = mock.patch.multiple(product, ROOT=self.root, SNAPSHOT=self.root / "tmp/nvidia-product")
        patch.start()
        self.addCleanup(patch.stop)
        native = mock.patch.object(product, "ground_vehicle_inputs", return_value=[])
        native.start()
        self.addCleanup(native.stop)

    def put(self, name: str, content: bytes) -> None:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    def test_snapshot_uses_current_app_and_proofs_and_records_renderer_override(self) -> None:
        receipt = product.prepare_snapshot()
        snapshot = self.root / "tmp/nvidia-product"
        self.assertEqual((snapshot / "app/kept.gd").read_bytes(), b"changed\n")
        self.assertEqual((snapshot / "app/new.gd").read_bytes(), b"untracked\n")
        self.assertFalse((snapshot / "app/ignored.txt").exists())
        self.assertEqual((snapshot / "assets/aircraft/proof.json").read_bytes(), b"proof\n")
        self.assertIn(b'rendering_method="forward_plus"', (snapshot / "app/project.godot").read_bytes())
        self.assertIn(b'rendering_method="gl_compatibility"', (self.root / "app/project.godot").read_bytes())
        self.assertTrue(receipt["build_identity"]["dirty"])
        self.assertEqual(receipt["project_override"]["source_sha256"], product.sha(self.root / "app/project.godot"))
        product.verify_tree(snapshot, product.SNAPSHOT_RECEIPT, product.SNAPSHOT_FORMAT, ignore_cache=True)

    def test_changed_snapshot_is_never_replaced(self) -> None:
        product.prepare_snapshot()
        snapshot = self.root / "tmp/nvidia-product"
        (snapshot / "app/kept.gd").write_bytes(b"unknown edit")
        with self.assertRaisesRegex(RuntimeError, "managed file changed"):
            product.prepare_snapshot()
        self.assertEqual((snapshot / "app/kept.gd").read_bytes(), b"unknown edit")

    def test_unreceipted_file_blocks_replacement_but_import_cache_is_allowed(self) -> None:
        product.prepare_snapshot()
        snapshot = self.root / "tmp/nvidia-product"
        cache = snapshot / "app/.godot/imported/example"
        cache.parent.mkdir(parents=True)
        cache.write_bytes(b"cache")
        product.verify_tree(snapshot, product.SNAPSHOT_RECEIPT, product.SNAPSHOT_FORMAT, ignore_cache=True)
        (snapshot / "app/extra.gd").write_bytes(b"unknown")
        with self.assertRaisesRegex(RuntimeError, "unknown or missing"):
            product.prepare_snapshot()
        self.assertEqual((snapshot / "app/extra.gd").read_bytes(), b"unknown")

    def test_tracked_deletion_is_not_resurrected(self) -> None:
        (self.root / "app/kept.gd").unlink()
        product.prepare_snapshot()
        self.assertFalse((self.root / "tmp/nvidia-product/app/kept.gd").exists())

    def test_source_changes_during_copy_are_detected(self) -> None:
        original = product.write_copy
        def change_source(name: str, destination: Path, files: dict[str, str]) -> None:
            original(name, destination, files)
            if name == "app/kept.gd":
                (self.root / name).write_bytes(b"late change")
        with mock.patch.object(product, "write_copy", side_effect=change_source):
            with self.assertRaisesRegex(RuntimeError, "source changed"):
                product.prepare_snapshot()
        self.assertFalse((self.root / "tmp/nvidia-product").exists())

    def test_imported_uid_is_recorded_and_later_mutation_is_rejected(self) -> None:
        product.prepare_snapshot()
        snapshot = self.root / "tmp/nvidia-product"
        uid = snapshot / "app/new.gd.uid"
        uid.write_text("uid://b5up2nm\n", encoding="utf-8")
        receipt = product.receipt_generated_imports(snapshot)
        self.assertEqual(receipt["generated_import_files"]["app/new.gd.uid"], product.sha(uid))
        product.verify_tree(snapshot, product.SNAPSHOT_RECEIPT, product.SNAPSHOT_FORMAT, ignore_cache=True)
        uid.write_text("uid://different\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "generated import file changed"):
            product.verify_tree(snapshot, product.SNAPSHOT_RECEIPT, product.SNAPSHOT_FORMAT, ignore_cache=True)

    def test_import_cannot_adopt_an_unrelated_file(self) -> None:
        product.prepare_snapshot()
        snapshot = self.root / "tmp/nvidia-product"
        unknown = snapshot / "app/other.gd.uid"
        unknown.write_text("uid://b5up2nm\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "unexpected file appeared"):
            product.receipt_generated_imports(snapshot)
        self.assertTrue(unknown.exists())

    def test_refresh_preserves_only_receipted_editor_cache(self) -> None:
        product.prepare_snapshot()
        snapshot = self.root / "tmp/nvidia-product"
        cache = snapshot / "app/.godot/imported/data"
        cache.parent.mkdir(parents=True)
        cache.write_bytes(b"expensive cache")
        receipt_path = snapshot / product.SNAPSHOT_RECEIPT
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        receipt["import"] = {"editor_sha256": "editor-hash"}
        receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
        (self.root / "app/kept.gd").write_bytes(b"new work")
        with mock.patch.object(product, "verify_engine", return_value=({"executable_sha256": "editor-hash"}, {}, [])):
            refreshed = product.prepare_snapshot()
            self.assertEqual(cache.read_bytes(), b"expensive cache")
            self.assertEqual((snapshot / "app/kept.gd").read_bytes(), b"new work")
            self.assertEqual(refreshed["cache_origin"]["editor_sha256"], "editor-hash")
            product.prepare_snapshot()
            self.assertEqual(cache.read_bytes(), b"expensive cache")

    def test_checked_import_must_match_project_editor_and_log(self) -> None:
        product.prepare_snapshot()
        snapshot = self.root / "tmp/nvidia-product"
        (snapshot / "app/new.gd.uid").write_text("uid://b5up2nm\n", encoding="utf-8")
        engine = self.root / "engine"
        engine.mkdir()
        executable = engine / "godot.windows.editor.x86_64.exe"
        executable.write_bytes(b"editor")
        report_dir = self.root / "checked"
        report_dir.mkdir()
        log = report_dir / "engine.log"
        log.write_text("Godot import finished\n", encoding="utf-8")
        report = {"format": "openrc-godot-check v1", "ok": True, "complete": True, "exit_code": 0,
                  "process_exit": 0, "counts": {"error": 0}, "cwd": str(self.root),
                  "started_utc": datetime.now(timezone.utc).isoformat(), "log": str(log), "log_sha256": product.sha(log),
                  "command": [str(executable), "--headless", "--path", str(snapshot / "app"), "--import"]}
        report_path = report_dir / "report.json"
        report_path.write_text(json.dumps(report), encoding="utf-8")
        with mock.patch.object(product, "ENGINE", engine), mock.patch.object(
                product, "verify_engine", return_value=({"executable_sha256": product.sha(executable)}, {}, [])):
            product.record_checked_import(report_path)
            receipt = product.verify_tree(snapshot, product.SNAPSHOT_RECEIPT, product.SNAPSHOT_FORMAT, ignore_cache=True)
            self.assertEqual(receipt["import"]["editor_sha256"], product.sha(executable))
            log.write_text("ERROR: substituted log\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "log does not match"):
                product.record_checked_import(report_path)


class PackageValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="nvidia-package-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.engine = self.root / "engine"
        self.engine.mkdir()
        self.here = self.root / "native"
        self.here.mkdir()
        (self.here / "patch").write_bytes(b"patch")
        (self.engine / "editor.exe").write_bytes(b"editor")
        (self.engine / "template.exe").write_bytes(b"template")
        (self.engine / "godot.windows.editor.x86_64.exe").write_bytes(b"editor")
        (self.engine / "godot.windows.template_release.x86_64.exe").write_bytes(b"template")
        (self.engine / "runtime.dll").write_bytes(b"runtime")
        (self.engine / "licenses").mkdir()
        (self.engine / "licenses/LICENSE.txt").write_bytes(b"license")
        patch = mock.patch.multiple(product, ENGINE=self.engine, HERE=self.here)
        patch.start()
        self.addCleanup(patch.stop)
        patch = mock.patch.multiple(product.native_build, COMMIT="abc", ARCHIVES=(("source.zip", "url", "source-hash", "dir"),))
        patch.start()
        self.addCleanup(patch.stop)
        patch = mock.patch.object(product.trial_package, "INTEGRATION", ("patch",))
        patch.start()
        self.addCleanup(patch.stop)
        shared = {"experimental": True, "godot_commit": "abc", "platform": "windows", "graphics_api": "vulkan",
                  "frame_generation_enabled": False, "sources": {"source.zip": "source-hash"},
                  "integration": {"patch": product.sha(self.here / "patch")}, "streamline_headers": {"a.h": "hash"},
                  "runtime": {"runtime.dll": product.sha(self.engine / "runtime.dll")}}
        for label, name in (("editor", "godot.windows.editor.x86_64.exe"), ("template_release", "godot.windows.template_release.x86_64.exe")):
            exe = self.engine / name
            self.receipt(label, dict(shared, executable=str(exe), executable_sha256=product.sha(exe)))

    def receipt(self, label: str, receipt: dict) -> None:
        (self.engine / f"openrc-{label}-build.json").write_text(json.dumps(receipt), encoding="utf-8")

    def test_matching_engine_receipts_and_license_pass(self) -> None:
        product.verify_engine()

    def test_modified_runtime_or_integration_is_rejected(self) -> None:
        (self.engine / "runtime.dll").write_bytes(b"modified")
        with self.assertRaisesRegex(RuntimeError, "runtime DLL"):
            product.verify_engine()
        (self.engine / "runtime.dll").write_bytes(b"runtime")
        (self.here / "patch").write_bytes(b"modified")
        with self.assertRaisesRegex(RuntimeError, "identities are stale"):
            product.verify_engine()

    def test_template_identity_mismatch_is_rejected(self) -> None:
        path = self.engine / "openrc-template_release-build.json"
        receipt = json.loads(path.read_text(encoding="utf-8"))
        receipt["streamline_headers"] = {"different.h": "hash"}
        self.receipt("template_release", receipt)
        with self.assertRaisesRegex(RuntimeError, "identities differ"):
            product.verify_engine()

    def test_launcher_keeps_real_user_profile_and_normal_home(self) -> None:
        launchers = product.launcher_files()
        normal = launchers["OpenRC Simulator.cmd"].decode()
        standard = launchers["Standard Graphics.cmd"].decode()
        self.assertNotIn("APPDATA", normal + standard)
        self.assertNotIn("OPENRC_", normal + standard)
        self.assertNotIn("quick-flight", normal + standard)
        self.assertIn("--rendering-method gl_compatibility", standard)
        self.assertNotIn("--rendering-method", normal)

    def test_product_executable_must_match_template_even_if_file_map_is_changed(self) -> None:
        output = self.root / "product"
        output.mkdir()
        shutil.copyfile(self.engine / "godot.windows.template_release.x86_64.exe", output / "OpenRC Simulator.exe")
        shutil.copyfile(self.engine / "runtime.dll", output / "runtime.dll")
        for name in ("openrc-editor-build.json", "openrc-template_release-build.json"):
            shutil.copyfile(self.engine / name, output / name)
        (output / "openrc_ground_vehicle.dll").write_bytes(b"ground")
        (output / "licenses").mkdir()
        (output / "licenses/LICENSE.txt").write_bytes(b"license")
        identity = {"commit": "fixture", "dirty": True}
        snapshot = {"format": product.SNAPSHOT_FORMAT, "build_identity": identity,
                    "files": {"app/native/ground_vehicle/openrc_ground_vehicle.dll": product.sha(output / "openrc_ground_vehicle.dll")}}
        (output / product.SNAPSHOT_RECEIPT).write_text(json.dumps(snapshot), encoding="utf-8")
        editor = json.loads((output / "openrc-editor-build.json").read_text(encoding="utf-8"))
        template = json.loads((output / "openrc-template_release-build.json").read_text(encoding="utf-8"))
        files = {path.relative_to(output).as_posix(): product.sha(path) for path in output.rglob("*") if path.is_file()}
        receipt = {"format": product.PACKAGE_FORMAT, "godot_commit": "abc", "build_identity": identity,
                   "snapshot_sha256": files[product.SNAPSHOT_RECEIPT], "editor_sha256": editor["executable_sha256"],
                   "template_sha256": template["executable_sha256"], "sources": editor["sources"],
                   "integration": editor["integration"], "runtime": editor["runtime"], "files": files}
        receipt_path = output / product.PACKAGE_RECEIPT
        receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
        with mock.patch.object(product, "OUTPUT", output):
            product.verify_product()
            executable = output / "OpenRC Simulator.exe"
            executable.write_bytes(b"substituted")
            receipt["files"][executable.name] = product.sha(executable)
            receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "release-template receipt"):
                product.verify_product()


if __name__ == "__main__":
    unittest.main()
