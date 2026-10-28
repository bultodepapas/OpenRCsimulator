"""Offline SDK 2.4 candidate package and source-binding checks."""
from __future__ import annotations

import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location("product_sdk24_under_test", Path(__file__).with_name("product_sdk24.py"))
assert SPEC is not None and SPEC.loader is not None
candidate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(candidate)


def put(root: Path, relative: str, data: bytes) -> Path:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def pins(data: bytes) -> tuple[str, str]:
    return sha(data), hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()


class SDK24ProductTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="fsr24-product-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.here = self.root / "tools/graphics/native"
        self.engine = self.root / ".tools/advanced-rendering-fsr24" / f"godot-{candidate.native_build.COMMIT}"
        self.bin = self.engine / "bin"
        self.archives = self.root / "tmp/fsr-sdk24-build-receipts"
        self.snapshot_base = self.root / "tmp/fsr24-product"
        self.checks = self.root / "tmp/godot-checks/fsr24-product"
        self.output = self.root / "dist/windows-fsr24-candidate"
        self.integration_bytes = {name: f"source {name}\n".encode() for name in
                                  ("engine.patch", "fsr3.cpp", "sdk24.py", "build_sdk24.py", "build.py")}
        for name, content in self.integration_bytes.items():
            put(self.here, name, content)
        for name in ("product.py", "product_sdk24.py"):
            put(self.here, name, f"packager {name}\n".encode())
        self.integration = {name: sha(data) for name, data in self.integration_bytes.items()}
        self.packager_imports = {name: sha((self.here / name).read_bytes()) for name in ("product.py", "product_sdk24.py")}
        sdk_data = {
            "Kits/FidelityFX/api/include/ffx_api.h": b"api header",
            "Kits/FidelityFX/upscalers/include/ffx_upscale.h": b"upscale header",
            "Kits/FidelityFX/signedbin/amd_fidelityfx_loader_vk.dll": b"loader",
            "Kits/FidelityFX/signedbin/amd_fidelityfx_upscaler_vk.dll": b"upscaler",
            "docs/license.md": b"sdk license",
            "Kits/FidelityFX/docs/license.md": b"kit license",
            "3rdpartynotice.md": b"third party notice",
        }
        self.sdk_pins = {name: pins(data) for name, data in sdk_data.items()}
        self.sdk_data = sdk_data
        signature = {"status": "Valid", "type": "Authenticode", "subject": candidate.sdk24.SIGNER_SUBJECT,
                     "signer": candidate.sdk24.SIGNER, "timestamp_signer": candidate.sdk24.TIMESTAMP_SIGNER}
        sdk_files = {name: {"sha256": pin[0], "git_blob_sha1": pin[1]} for name, pin in self.sdk_pins.items()}
        signatures = {name: signature for name in candidate.AMD_DLLS.values()}
        self.sdk_receipt = candidate.sdk24._receipt(sdk_files, signatures, {"live": False, "checked_utc": None})
        self.engine_sources = {
            "src/patched.cpp": b"patched source",
            "src/fsr3.cpp": self.integration_bytes["fsr3.cpp"],
            "thirdparty/amd-fsr-sdk24/api/include/ffx_api.h": sdk_data["Kits/FidelityFX/api/include/ffx_api.h"],
            "thirdparty/amd-fsr-sdk24/upscalers/include/ffx_upscale.h": sdk_data["Kits/FidelityFX/upscalers/include/ffx_upscale.h"],
            "thirdparty/streamline/include/sl.h": b"streamline header",
        }
        for name, content in self.engine_sources.items():
            put(self.engine, name, content)
        for name, src in candidate.AMD_DLLS.items():
            put(self.bin, name, sdk_data[src])
        put(self.bin, "sl.dll", b"nvidia runtime")
        self.runtime = {name: sha((self.bin / name).read_bytes()) for name in (*candidate.AMD_DLLS, "sl.dll")}
        self.licenses = {}
        for name, src in candidate.AMD_NOTICES.items():
            self.licenses[name] = sha(sdk_data[src])
            put(self.bin, "licenses/" + name, sdk_data[src])
        self.licenses["other-license.txt"] = sha(b"other license")
        put(self.bin, "licenses/other-license.txt", b"other license")
        editor_exe = put(self.bin, "godot.windows.editor.x86_64.exe", b"editor")
        template_exe = put(self.bin, "godot.windows.template_release.x86_64.exe", b"template")
        archive_specs = (("godot.zip", "fixture", "a" * 64, self.engine.name),
                         ("unused.zip", "fixture", "b" * 64, "unused"),
                         ("streamline.zip", "fixture", "c" * 64, "streamline"))
        shared = {"experimental": True, "production_engine_unchanged": "4.8-beta1",
                  "godot_repository": "https://github.com/NVIDIA-RTX/godot", "godot_commit": candidate.native_build.COMMIT,
                  "version": "4.8.dev.custom_build", "fidelityfx_sdk": "2.4.0", "fsr_upscaler": "runtime_queried",
                  "bundled_upscalers": ["3.1.6", "4.1.2"], "streamline": "2.11.1", "platform": "windows",
                  "graphics_api": "vulkan", "frame_generation_enabled": False,
                  "sources": {archive_specs[0][0]: archive_specs[0][2], archive_specs[2][0]: archive_specs[2][2]},
                  "integration": self.integration, "sdk_intake": self.sdk_receipt,
                  "engine_source": {name: sha(data) for name, data in self.engine_sources.items()},
                  "amd_headers": {name.removeprefix("Kits/FidelityFX/"): self.sdk_pins[name][0]
                                  for name in sdk_data if "/include/" in name},
                  "streamline_headers": {"sl.h": sha(b"streamline header")},
                  "runtime": self.runtime, "licenses": self.licenses}
        def build_receipt(label: str, exe: Path) -> dict:
            command = ["python", "-m", "SCons", "platform=windows", f"target={label}", "arch=x86_64",
                       "use_streamline=yes", "d3d12=no", "angle=no", "accesskit=no", "winrt=no"]
            return dict(shared, executable=str(exe), executable_sha256=sha(exe.read_bytes()), build_command=command)
        self.editor = build_receipt("editor", editor_exe)
        self.template = build_receipt("template_release", template_exe)
        self.editor_path = put(self.archives, "openrc-editor-build-fixture.json", json.dumps(self.editor).encode())
        self.template_path = put(self.bin, "openrc-template_release-build.json", json.dumps(self.template).encode())
        self.patches = [
            mock.patch.multiple(candidate, ROOT=self.root, HERE=self.here, ARCHIVES=self.archives,
                                SNAPSHOT=self.snapshot_base, OUTPUT=self.output, CHECKS=self.checks,
                                PACKAGER_IMPORTS=self.packager_imports),
            mock.patch.object(candidate.product, "ROOT", self.root),
            mock.patch.object(candidate.native_build, "ARCHIVES", archive_specs),
            mock.patch.object(candidate.sdk24, "PINNED_FILES", self.sdk_pins),
            mock.patch.object(candidate.sdk24, "SIGNED_DLLS", tuple(candidate.AMD_DLLS.values())),
            mock.patch.object(candidate.sdk24, "verify_signature", return_value=signature),
            mock.patch.object(candidate.sdk_build, "HERE", self.here),
            mock.patch.object(candidate.sdk_build, "ADAPTER_FILES", {"fsr3.cpp": "src/fsr3.cpp"}),
            mock.patch.object(candidate.sdk_build, "freeze_integration", return_value=(self.integration_bytes, self.integration)),
            mock.patch.object(candidate.sdk_build, "patched_paths", return_value={"src/patched.cpp"}),
        ]
        for patch in self.patches:
            patch.start()
            self.addCleanup(patch.stop)

    def save_receipt(self, path: Path, data: dict) -> None:
        path.write_text(json.dumps(data), encoding="utf-8")

    def make_candidate_output(self) -> tuple[Path, dict]:
        snapshot = self.snapshot_base / "source-fixture"
        identity = {"commit": "fixture", "dirty": True}
        files = {}
        for name, content in self.integration_bytes.items():
            rel = "tools/graphics/native/" + name
            put(snapshot, rel, content)
            files[rel] = sha(content)
        for name in ("product.py", "product_sdk24.py"):
            rel = "tools/graphics/native/" + name
            content = (self.here / name).read_bytes()
            put(snapshot, rel, content)
            files[rel] = sha(content)
        put(snapshot, "app/project.godot", b"forward plus fixture")
        put(snapshot, "app/native/ground_vehicle/openrc_ground_vehicle.dll", b"ground dll")
        files["app/project.godot"] = sha(b"forward plus fixture")
        files["app/native/ground_vehicle/openrc_ground_vehicle.dll"] = sha(b"ground dll")

        def checked(label: str, export: bool) -> Path:
            directory = self.checks / label
            log = put(directory, "engine.log", b"[ DONE ] savepack\n" if export else b"import complete\n")
            command = [str(self.bin / "godot.windows.editor.x86_64.exe"), "--headless", "--path", str(snapshot / "app")]
            if export:
                command += ["--export-pack", "Windows", str(self.root / "dist/nvidia-product-export-fixture/OpenRC Simulator.pck")]
            else:
                command += ["--import"]
            report = {"format": "openrc-godot-check v1", "ok": True, "complete": True,
                      "exit_code": 0, "process_exit": 0, "counts": {"error": 0},
                      "started_utc": datetime.now(timezone.utc).isoformat(), "cwd": str(self.root),
                      "command": command, "log": str(log), "log_sha256": sha(log.read_bytes())}
            return put(directory, "report.json", json.dumps(report).encode())

        import_report = checked("import", False)
        export_report = checked("export", True)
        snapshot_receipt = {"format": candidate.SNAPSHOT_FORMAT, "build_identity": identity, "files": files,
                            "import": {"report": str(import_report.resolve()), "report_sha256": sha(import_report.read_bytes()),
                                       "editor_sha256": self.editor["executable_sha256"]}}
        snap_file = put(snapshot, candidate.product.SNAPSHOT_RECEIPT, json.dumps(snapshot_receipt).encode())
        put(self.output, "OpenRC Simulator.exe", b"template")
        put(self.output, "OpenRC Simulator.pck", b"exported pck")
        put(self.output, "openrc_ground_vehicle.dll", b"ground dll")
        put(self.output, "openrc-editor-build.json", json.dumps(self.editor).encode())
        put(self.output, "openrc-template_release-build.json", json.dumps(self.template).encode())
        put(self.output, candidate.product.SNAPSHOT_RECEIPT, snap_file.read_bytes())
        for name in self.runtime:
            put(self.output, name, (self.bin / name).read_bytes())
        for name in self.licenses:
            put(self.output, "licenses/" + name, (self.bin / "licenses" / name).read_bytes())
        for name, content in candidate.candidate_launchers().items():
            put(self.output, name, content)
        managed = {path.relative_to(self.output).as_posix(): sha(path.read_bytes())
                   for path in self.output.rglob("*") if path.is_file()}
        receipt = {"format": candidate.PACKAGE_FORMAT, "build_identity": identity,
                   "godot_commit": candidate.native_build.COMMIT, "sources": self.editor["sources"],
                   "integration": self.editor["integration"], "runtime": self.editor["runtime"],
                   "editor_sha256": self.editor["executable_sha256"], "template_sha256": self.template["executable_sha256"],
                   "snapshot_sha256": sha(snap_file.read_bytes()), "import_report": str(import_report),
                   "export_report": str(export_report), "files": managed,
                   "export_binding": {"snapshot_path": str(snapshot.resolve()), "pck_sha256": sha(b"exported pck"),
                                      "snapshot_sha256": sha(snap_file.read_bytes()),
                                      "import_report_sha256": sha(import_report.read_bytes()),
                                      "export_report_sha256": sha(export_report.read_bytes())}}
        put(self.output, candidate.product.PACKAGE_RECEIPT, json.dumps(receipt).encode())
        return snapshot, receipt

    def initialize_app_repository(self) -> None:
        if not shutil.which("git"):
            self.skipTest("Git is required for the current-source snapshot")
        put(self.root, ".gitignore", b"/.tools/\n/tmp/\n/dist/\n")
        put(self.root, "app/project.godot", b'[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        put(self.root, "app/aircraft.gd", b"aircraft source")
        put(self.root, "assets/aircraft/proof.json", b"proof")
        model = {"source_registry": {"path": "assets/aircraft/proof.json"},
                 "geometry": {"source": {"path": "res://aircraft.gd"}}, "authoring_sources": [], "dependencies": []}
        put(self.root, "app/data/aircraft_models/test.json", json.dumps(model).encode())
        for args in (("init", "--quiet"), ("config", "user.name", "FSR fixture"),
                     ("config", "user.email", "fsr-fixture@example.invalid"), ("add", "app", "assets", ".gitignore"),
                     ("commit", "--quiet", "-m", "fixture")):
            subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def test_archived_editor_and_template_pair_are_found_by_metadata_and_bytes(self) -> None:
        editor, template, licenses = candidate.verify_engine_pair(self.editor_path, self.template_path, self.engine)
        self.assertEqual(editor, self.editor)
        self.assertEqual(template, self.template)
        self.assertEqual({p.name for p in licenses}, set(self.licenses))
        self.assertEqual(candidate.select_pair(self.engine, None, None), (self.editor_path, self.template_path))

    def test_wrong_or_incomplete_pair_metadata_is_rejected(self) -> None:
        for key, value in (("fidelityfx_sdk", "1.1.4"), ("sdk_intake", {}), ("engine_source", {}),
                           ("amd_headers", {}), ("runtime", {}), ("licenses", {}), ("integration", {})):
            with self.subTest(field=key):
                changed = copy.deepcopy(self.template)
                changed[key] = value
                self.save_receipt(self.template_path, changed)
                with self.assertRaises(RuntimeError):
                    candidate.verify_engine_pair(self.editor_path, self.template_path, self.engine)
        self.save_receipt(self.template_path, self.template)
        changed = copy.deepcopy(self.template)
        changed["build_command"] = ["target=editor"]
        self.save_receipt(self.template_path, changed)
        with self.assertRaisesRegex(RuntimeError, "build command"):
            candidate.verify_engine_pair(self.editor_path, self.template_path, self.engine)

    def test_matching_but_forged_sdk_pins_and_boolean_flags_are_rejected(self) -> None:
        cases = []
        bad_intake = copy.deepcopy(self.editor["sdk_intake"])
        bad_intake["archive"]["sha256"] = "f" * 64
        cases.append(("sdk_intake", bad_intake))
        bad_runtime = dict(self.runtime)
        bad_runtime["amd_fidelityfx_upscaler_vk.dll"] = "e" * 64
        cases.append(("runtime", bad_runtime))
        cases.append(("frame_generation_enabled", 0))
        for key, value in cases:
            with self.subTest(field=key):
                editor, template = copy.deepcopy(self.editor), copy.deepcopy(self.template)
                editor[key] = template[key] = value
                self.save_receipt(self.editor_path, editor)
                self.save_receipt(self.template_path, template)
                with self.assertRaises(RuntimeError):
                    candidate.verify_engine_pair(self.editor_path, self.template_path, self.engine)
        self.save_receipt(self.editor_path, self.editor)
        self.save_receipt(self.template_path, self.template)

    def test_corrupt_editor_template_inputs_runtime_or_notice_are_rejected(self) -> None:
        paths = [self.bin / "godot.windows.editor.x86_64.exe", self.bin / "godot.windows.template_release.x86_64.exe",
                 self.engine / "src/patched.cpp", self.engine / "thirdparty/amd-fsr-sdk24/api/include/ffx_api.h",
                 self.bin / "amd_fidelityfx_upscaler_vk.dll", self.bin / "licenses/AMD-FSR-SDK-2.4-third-party.md"]
        for path in paths:
            with self.subTest(path=path.name):
                original = path.read_bytes()
                path.write_bytes(b"changed")
                with self.assertRaises(RuntimeError):
                    candidate.verify_engine_pair(self.editor_path, self.template_path, self.engine)
                path.write_bytes(original)
        (self.bin / "licenses/AMD-FSR-SDK-2.4-third-party.md").unlink()
        with self.assertRaises(RuntimeError):
            candidate.verify_engine_pair(self.editor_path, self.template_path, self.engine)

    def test_receipt_outside_workspace_and_ambiguous_archive_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="outside-fsr24-") as outside:
            path = Path(outside) / "editor.json"
            path.write_text(json.dumps(self.editor), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "outside the workspace"):
                candidate.select_pair(self.engine, path, self.template_path)
        put(self.archives, "openrc-editor-build-duplicate.json", json.dumps(self.editor).encode())
        with self.assertRaisesRegex(RuntimeError, "found 2"):
            candidate.select_pair(self.engine, None, None)

    def test_profile_is_isolated_and_restores_legacy_product_globals(self) -> None:
        original = {name: getattr(candidate.product, name) for name in
                    ("ENGINE", "SNAPSHOT", "OUTPUT", "CHECKS", "verify_engine", "engine_receipt_path")}
        snapshot = self.snapshot_base / "source-fixture"
        pending = self.root / "dist/fsr24-candidate-pending-fixture"
        with self.assertRaisesRegex(RuntimeError, "fixture failure"):
            with candidate.candidate_profile(self.engine, self.editor_path, self.template_path, pending, snapshot):
                self.assertEqual(candidate.product.ENGINE, self.bin)
                self.assertEqual(candidate.product.SNAPSHOT, snapshot)
                self.assertEqual(candidate.product.OUTPUT, pending)
                self.assertEqual(candidate.product.engine_receipt_path("editor"), self.editor_path)
                sources = candidate.product.additional_snapshot_files()
                self.assertIn("tools/graphics/native/sdk24.py", sources)
                self.assertIn("tools/graphics/native/build_sdk24.py", sources)
                launchers = candidate.product.launcher_files()
                self.assertIn(b"OpenRC-FSR24-Candidate", launchers["OpenRC Simulator.cmd"])
                self.assertIn(b"not qualified", launchers["EXPERIMENTAL.txt"])
                raise RuntimeError("fixture failure")
        self.assertEqual({name: getattr(candidate.product, name) for name in original}, original)

    def test_candidate_output_binds_pck_snapshot_reports_and_build_receipts(self) -> None:
        snapshot, receipt = self.make_candidate_output()
        with candidate.candidate_profile(self.engine, self.editor_path, self.template_path, self.output, snapshot):
            self.assertEqual(candidate.verify_candidate_output(self.output, self.engine, self.editor, self.template), receipt)

    def test_output_tampering_cannot_be_hidden_by_file_map(self) -> None:
        snapshot, original_receipt = self.make_candidate_output()
        receipt_path = self.output / candidate.product.PACKAGE_RECEIPT
        for name in ("OpenRC Simulator.pck", "amd_fidelityfx_upscaler_vk.dll", "licenses/AMD-FSR-SDK-2.4-third-party.md"):
            with self.subTest(file=name):
                target = self.output / name
                original = target.read_bytes()
                target.write_bytes(b"substituted")
                changed = copy.deepcopy(original_receipt)
                changed["files"][name] = sha(b"substituted")
                self.save_receipt(receipt_path, changed)
                with candidate.candidate_profile(self.engine, self.editor_path, self.template_path, self.output, snapshot):
                    with self.assertRaises(RuntimeError):
                        candidate.verify_candidate_output(self.output, self.engine, self.editor, self.template)
                target.write_bytes(original)
        self.save_receipt(receipt_path, original_receipt)

    def test_snapshot_source_tampering_is_rejected(self) -> None:
        snapshot, _ = self.make_candidate_output()
        (snapshot / "tools/graphics/native/sdk24.py").write_bytes(b"changed source")
        with candidate.candidate_profile(self.engine, self.editor_path, self.template_path, self.output, snapshot):
            with self.assertRaisesRegex(RuntimeError, "managed file changed"):
                candidate.verify_candidate_output(self.output, self.engine, self.editor, self.template)

    def test_export_report_must_point_to_candidate_staging(self) -> None:
        snapshot, receipt = self.make_candidate_output()
        report_path = Path(receipt["export_report"])
        report = json.loads(report_path.read_text(encoding="utf-8"))
        report["command"][-1] = str(self.root / "dist/windows-nvidia/OpenRC Simulator.pck")
        self.save_receipt(report_path, report)
        receipt["export_binding"]["export_report_sha256"] = sha(report_path.read_bytes())
        self.save_receipt(self.output / candidate.product.PACKAGE_RECEIPT, receipt)
        with candidate.candidate_profile(self.engine, self.editor_path, self.template_path, self.output, snapshot):
            with self.assertRaisesRegex(RuntimeError, "isolated candidate staging"):
                candidate.verify_candidate_output(self.output, self.engine, self.editor, self.template)

    def test_checked_import_rejects_a_substituted_editor_and_error_log(self) -> None:
        snapshot, receipt = self.make_candidate_output()
        report_path = Path(receipt["import_report"])
        report = json.loads(report_path.read_text(encoding="utf-8"))
        original = copy.deepcopy(report)
        report["command"][0] = str(self.root / "different-editor.exe")
        self.save_receipt(report_path, report)
        with self.assertRaisesRegex(RuntimeError, "different editor"):
            candidate._checked_report(str(report_path), export=False, engine=self.engine, snapshot=snapshot)
        report = original
        log = Path(report["log"])
        log.write_bytes(b"ERROR: substituted import failure\n")
        report["log_sha256"] = sha(log.read_bytes())
        self.save_receipt(report_path, report)
        with self.assertRaisesRegex(RuntimeError, "contains errors"):
            candidate._checked_report(str(report_path), export=False, engine=self.engine, snapshot=snapshot)

    def test_actual_snapshot_includes_the_verified_sdk24_source_proof(self) -> None:
        self.initialize_app_repository()
        snapshot = self.snapshot_base / "source-fixture"
        pending = self.root / "dist/fsr24-candidate-pending-fixture"
        with (mock.patch.object(candidate.product, "ground_vehicle_inputs", return_value=[]),
              candidate.candidate_profile(self.engine, self.editor_path, self.template_path, pending, snapshot)):
            receipt = candidate.product.prepare_snapshot()
            for name, digest in self.integration.items():
                self.assertEqual(receipt["files"][f"tools/graphics/native/{name}"], digest)
            for name, digest in self.packager_imports.items():
                self.assertEqual(receipt["files"][f"tools/graphics/native/{name}"], digest)
            candidate.product.verify_tree(snapshot, candidate.product.SNAPSHOT_RECEIPT, candidate.SNAPSHOT_FORMAT, ignore_cache=True)

    def test_failed_candidate_export_preserves_existing_package_and_snapshot(self) -> None:
        old_snapshot, _ = self.make_candidate_output()
        old_receipt = (self.output / candidate.product.PACKAGE_RECEIPT).read_bytes()
        with (mock.patch.object(candidate.product, "prepare_snapshot", return_value={}),
              mock.patch.object(candidate.product, "package_product", side_effect=RuntimeError("fake export failed"))):
            with self.assertRaisesRegex(RuntimeError, "fake export failed"):
                candidate.package_candidate(self.engine, self.editor_path, self.template_path)
        self.assertEqual((self.output / candidate.product.PACKAGE_RECEIPT).read_bytes(), old_receipt)
        self.assertTrue(old_snapshot.is_dir())


if __name__ == "__main__":
    unittest.main()
