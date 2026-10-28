"""Offline tests for the isolated SDK 2.4 engine preparation contract."""
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest import mock
import zipfile


SPEC = importlib.util.spec_from_file_location("build_sdk24_under_test", Path(__file__).with_name("build_sdk24.py"))
assert SPEC is not None and SPEC.loader is not None
candidate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(candidate)


def put(root: Path, relative: str, content: bytes) -> Path:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    return path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class PrepareTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="build-sdk24-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repo"
        self.here = self.root / "tools/graphics/native"
        self.baseline = self.root / ".tools/advanced-rendering"
        self.cache = self.root / ".tools/candidate"
        self.intake = self.root / ".tools/sdk24-intake"
        self.source = self.intake / "intake-v2.4.0/source"
        self.engine = self.cache / "engine"
        self.nvidia = Path(self.temporary.name) / "nvidia"

        for name in ("fsr3.h", "fsr3.cpp", "fsr3_prepare.glsl", "sdk24.py", "build_sdk24.py", "build.py"):
            put(self.here, name, f"fixture {name}\n".encode())
        put(self.here, "engine.patch", b"--- a/core/patched.cpp\n+++ b/core/patched.cpp\n")
        put(self.root, "LICENSE", b"openrc license\n")
        put(self.engine, "LICENSE.txt", b"engine license\n")
        put(self.engine, "core/patched.cpp", b"patched engine source\n")
        (self.engine / "servers/rendering/renderer_rd/effects").mkdir(parents=True)
        (self.engine / "servers/rendering/renderer_rd/shaders/effects").mkdir(parents=True)
        self.sdk_files = {
            "Kits/FidelityFX/api/include/ffx_api.h": b"api header\n",
            "Kits/FidelityFX/api/include/ffx_api.hpp": b"api wrapper\n",
            "Kits/FidelityFX/api/include/vk/ffx_api_vk.h": b'#include "../ffx_api.h"\n',
            "Kits/FidelityFX/upscalers/include/ffx_upscale.h": b'#include "../../api/include/ffx_api.h"\n',
            "Kits/FidelityFX/upscalers/include/ffx_upscale.hpp": b"upscale wrapper\n",
            "Kits/FidelityFX/signedbin/amd_fidelityfx_loader_vk.dll": b"signed loader fixture\n",
            "Kits/FidelityFX/signedbin/amd_fidelityfx_upscaler_vk.dll": b"signed upscaler fixture\n",
            "docs/license.md": b"sdk license\n",
            "Kits/FidelityFX/docs/license.md": b"kit license\n",
            "3rdpartynotice.md": b"third party notice\n",
        }
        self.sdk_receipt = {
            "sdk_version": "2.4.0",
            "test_fixture": True,
            "pinned_files": {
                name: {"sha256": hashlib.sha256(content).hexdigest(),
                       "git_blob_sha1": hashlib.sha1(f"blob {len(content)}\0".encode() + content).hexdigest()}
                for name, content in self.sdk_files.items()
            },
        }
        for name, content in self.sdk_files.items():
            put(self.source, name, content)
        put(self.nvidia, "include/sl.h", b"streamline header\n")
        put(self.nvidia, "bin/x64/sl.interposer.dll", b"streamline dll\n")
        put(self.nvidia, "bin/x64/sl.interposer.license.txt", b"runtime license\n")
        put(self.nvidia, "license.txt", b"streamline license\n")
        put(self.nvidia, "3rd-party-licenses.md", b"streamline third parties\n")
        self.engine_archive = b"verified engine archive fixture"
        self.nvidia_archive = b"verified nvidia archive fixture"
        specs = (("godot.zip", "fixture://godot", hashlib.sha256(self.engine_archive).hexdigest(), "engine"),
                 ("unused.zip", "fixture://unused", "unused", "unused"),
                 ("nvidia.zip", "fixture://nvidia", hashlib.sha256(self.nvidia_archive).hexdigest(), "nvidia"))
        self.patches = [
            mock.patch.object(candidate, "ROOT", self.root),
            mock.patch.object(candidate, "HERE", self.here),
            mock.patch.object(candidate, "IMPORT_IDENTITIES", {name: digest(self.here / name)
                              for name in ("build.py", "sdk24.py", "build_sdk24.py")}),
            mock.patch.object(candidate.native_build, "ARCHIVES", specs),
            mock.patch.object(candidate.native_build, "ENGINE_PATCHES", ("engine.patch",)),
            mock.patch.object(candidate.sdk24, "prepare", return_value=(self.source, self.sdk_receipt)),
            mock.patch.object(candidate.native_build, "fetch", side_effect=[self.engine, self.nvidia]),
            mock.patch.object(candidate, "apply_frozen_engine_patches"),
        ]
        for patch in self.patches:
            patch.start()
            self.addCleanup(patch.stop)

    def test_rejects_cache_overlapping_baseline_or_intake_before_intake(self) -> None:
        for cache in (self.baseline, self.baseline / "nested", self.baseline.parent,
                      self.intake, self.intake / "intake-v2.4.0/source", self.intake.parent):
            with self.subTest(cache=cache):
                with self.assertRaises(ValueError):
                    candidate.prepare(cache, self.intake)
        candidate.sdk24.prepare.assert_not_called()
        candidate.native_build.fetch.assert_not_called()

    def test_preserves_header_layout_and_stages_dlls_notices_and_receipt(self) -> None:
        engine, receipt = candidate.prepare(self.cache, self.intake)
        self.assertEqual(engine, self.engine)
        headers = engine / "thirdparty/amd-fsr-sdk24"
        api = headers / "api/include/ffx_api.h"
        upscale = headers / "upscalers/include/ffx_upscale.h"
        vk = headers / "api/include/vk/ffx_api_vk.h"
        self.assertEqual((upscale.parent / "../../api/include/ffx_api.h").resolve(), api.resolve())
        self.assertEqual((vk.parent / "../ffx_api.h").resolve(), api.resolve())
        for rel, content in self.sdk_files.items():
            marker = "Kits/FidelityFX/"
            if rel.startswith(marker + "api/include/") or rel.startswith(marker + "upscalers/include/"):
                destination = headers / rel.removeprefix(marker)
                self.assertEqual(destination.read_bytes(), content)
                self.assertEqual(receipt["amd_headers"][destination.relative_to(headers).as_posix()], digest(destination))
        for name in ("amd_fidelityfx_loader_vk.dll", "amd_fidelityfx_upscaler_vk.dll"):
            staged = engine / "bin" / name
            self.assertEqual(staged.read_bytes(), self.sdk_files["Kits/FidelityFX/signedbin/" + name])
            self.assertEqual(receipt["runtime"][name], digest(staged))
        for name in ("AMD-FSR-SDK-2.4-LICENSE.md", "AMD-FidelityFX-kit-LICENSE.md",
                     "AMD-FSR-SDK-2.4-third-party.md"):
            staged = engine / "bin/licenses" / name
            self.assertEqual(receipt["licenses"][name], digest(staged))
        self.assertEqual(receipt["sdk_intake"], self.sdk_receipt)
        self.assertFalse(receipt["frame_generation_enabled"])

    def test_correct_baseline_archive_is_copied_without_changing_baseline(self) -> None:
        baseline = put(self.baseline, "godot.zip", self.engine_archive)
        put(self.baseline, "unrelated-work.txt", b"preserve me")
        before = {p.name: p.read_bytes() for p in self.baseline.iterdir()}
        candidate.prepare(self.cache, self.intake)
        self.assertEqual((self.cache / "godot.zip").read_bytes(), self.engine_archive)
        self.assertEqual({p.name: p.read_bytes() for p in self.baseline.iterdir()}, before)
        self.assertEqual(baseline.read_bytes(), self.engine_archive)

    def test_corrupted_staged_dll_cannot_receive_source_hash_receipt(self) -> None:
        real_copy = shutil.copy2

        def corrupt_after_copy(src, dst, *args, **kwargs):
            result = real_copy(src, dst, *args, **kwargs)
            if Path(src).name == "amd_fidelityfx_upscaler_vk.dll":
                Path(dst).write_bytes(b"different staged runtime")
            return result

        with mock.patch.object(candidate.shutil, "copy2", side_effect=corrupt_after_copy):
            with self.assertRaisesRegex(RuntimeError, "(?i)(runtime|sha|hash|mismatch)"):
                candidate.prepare(self.cache, self.intake)

    def test_missing_effect_dll_fails_preparation(self) -> None:
        # Model a disappearance between intake verification and the staging copy.
        (self.source / "Kits/FidelityFX/signedbin/amd_fidelityfx_upscaler_vk.dll").unlink()
        with self.assertRaises(FileNotFoundError):
            candidate.prepare(self.cache, self.intake)

    def test_corrupted_staged_header_cannot_receive_a_verified_receipt(self) -> None:
        real_copytree = shutil.copytree
        target = self.engine / "thirdparty/amd-fsr-sdk24/api/include"

        def corrupt_after_copy(src, dst, *args, **kwargs):
            result = real_copytree(src, dst, *args, **kwargs)
            if Path(dst) == target:
                (target / "ffx_api.h").write_bytes(b"different staged header")
            return result

        with mock.patch.object(candidate.shutil, "copytree", side_effect=corrupt_after_copy):
            with self.assertRaisesRegex(RuntimeError, "(?i)(header|sha|hash|mismatch)"):
                candidate.prepare(self.cache, self.intake)

    def test_corrupted_staged_notice_cannot_receive_a_verified_receipt(self) -> None:
        real_copy = shutil.copy2

        def corrupt_after_copy(src, dst, *args, **kwargs):
            result = real_copy(src, dst, *args, **kwargs)
            if Path(dst).name == "AMD-FSR-SDK-2.4-third-party.md":
                Path(dst).write_bytes(b"different staged notice")
            return result

        with mock.patch.object(candidate.shutil, "copy2", side_effect=corrupt_after_copy):
            with self.assertRaisesRegex(RuntimeError, "(?i)(license|notice|sha|hash|mismatch)"):
                candidate.prepare(self.cache, self.intake)

    def test_changed_intake_file_after_verification_is_not_staged_as_trusted(self) -> None:
        def mutate_after_verification(_intake):
            (self.source / "Kits/FidelityFX/signedbin/amd_fidelityfx_upscaler_vk.dll").write_bytes(b"different source")
            return self.source, self.sdk_receipt

        candidate.sdk24.prepare.side_effect = mutate_after_verification
        with self.assertRaisesRegex(RuntimeError, "(?i)(runtime|sha|hash|mismatch)"):
            candidate.prepare(self.cache, self.intake)

    def test_integration_edit_during_preparation_uses_snapshot_and_fails(self) -> None:
        original = (self.here / "fsr3.cpp").read_bytes()

        def mutate_after_freeze(_engine, _archive, snapshot):
            self.assertEqual((snapshot / "fsr3.cpp").read_bytes(), original)
            (self.here / "fsr3.cpp").write_bytes(b"concurrent integration edit")

        candidate.apply_frozen_engine_patches.side_effect = mutate_after_freeze
        with self.assertRaisesRegex(RuntimeError, "Integration source changed"):
            candidate.prepare(self.cache, self.intake)
        staged = self.engine / "servers/rendering/renderer_rd/effects/fsr3.cpp"
        self.assertEqual(staged.read_bytes(), original)
        self.assertFalse((self.engine / "bin/openrc-sdk24-prepare.json").exists())

    def test_imported_helper_changes_require_restart_before_staging(self) -> None:
        (self.here / "sdk24.py").write_bytes(b"changed after module import")
        with self.assertRaisesRegex(RuntimeError, "changed after import"):
            candidate.prepare(self.cache, self.intake)
        candidate.sdk24.prepare.assert_not_called()

    def test_unexpected_sdk_header_file_is_preserved_and_rejected(self) -> None:
        extra = put(self.engine, "thirdparty/amd-fsr-sdk24/unexpected.h", b"unknown local work")
        with self.assertRaisesRegex(RuntimeError, "unexpected files"):
            candidate.prepare(self.cache, self.intake)
        self.assertEqual(extra.read_bytes(), b"unknown local work")

    def test_patched_engine_and_integration_edits_invalidate_build_inputs(self) -> None:
        engine, receipt = candidate.prepare(self.cache, self.intake)
        self.assertIn("build.py", receipt["integration"])
        self.assertIn("core/patched.cpp", receipt["engine_source"])
        self.assertIn("servers/rendering/renderer_rd/effects/fsr3.cpp", receipt["engine_source"])
        candidate.verify_build_inputs(engine, receipt)
        patched = engine / "core/patched.cpp"
        original = patched.read_bytes()
        patched.write_bytes(b"different patched source")
        with self.assertRaisesRegex(RuntimeError, "Engine source hash mismatch"):
            candidate.verify_build_inputs(engine, receipt)
        patched.write_bytes(original)
        (self.here / "fsr3.h").write_bytes(b"different integration source")
        with self.assertRaisesRegex(RuntimeError, "Integration source changed"):
            candidate.verify_build_inputs(engine, receipt)

    def test_existing_receipt_is_preserved_before_staging(self) -> None:
        previous = put(self.engine, "bin/openrc-editor-build.json", b"previous receipt evidence\n")
        candidate.prepare(self.cache, self.intake)
        self.assertFalse(previous.exists())
        saved = list((self.root / "tmp/fsr-sdk24-build-receipts").glob("openrc-editor-build-*.json"))
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0].read_bytes(), b"previous receipt evidence\n")

    def test_receipt_publication_does_not_replace_existing_file(self) -> None:
        path = put(self.cache, "receipt.json", b"other process receipt\n")
        with self.assertRaises(FileExistsError):
            candidate.write_receipt(path, {"candidate": True})
        self.assertEqual(path.read_bytes(), b"other process receipt\n")

    @unittest.skipUnless(os.name == "nt", "The candidate builder targets Windows")
    def test_build_input_mutation_prevents_a_success_receipt(self) -> None:
        engine, receipt = candidate.prepare(self.cache, self.intake)
        fake_scons = types.ModuleType("SCons")
        fake_scons.__version__ = "4.10.1"

        def mutate_during_build(command, **kwargs):
            (engine / "core/patched.cpp").write_bytes(b"changed during compilation")
            return subprocess.CompletedProcess(command, 0)

        with (mock.patch.object(candidate, "prepare", return_value=(engine, receipt)),
              mock.patch.object(candidate.subprocess, "run", side_effect=mutate_during_build),
              mock.patch.object(sys, "argv", ["build_sdk24.py"]),
              mock.patch.dict(sys.modules, {"SCons": fake_scons})):
            with self.assertRaisesRegex(RuntimeError, "Engine source hash mismatch"):
                candidate.main()
        self.assertFalse((engine / "bin/openrc-editor-build.json").exists())


class ProviderSelectorTests(unittest.TestCase):
    def test_actual_version_matcher_uses_exact_bundled_version_tokens(self) -> None:
        compiler = shutil.which("g++") or shutil.which("clang++")
        if not compiler:
            self.skipTest("A C++ compiler is required for the provider selector test")
        source = Path(__file__).with_name("fsr3.cpp").read_text(encoding="utf-8")
        signature = "static bool matches_bundled_version("
        self.assertEqual(source.count(signature), 1)
        start = source.index(signature)
        end = source.index("\n}\n", start) + len("\n}")
        matcher = source[start:end]
        program = r"""
#include <cassert>
#include <cctype>
#include <cstring>
#include <string>
""" + matcher + r"""
int main() {
    assert(matches_bundled_version("3.1.6", "3.1.6"));
    assert(matches_bundled_version("FSR 3.1.6 (bundled)", "3.1.6"));
    assert(matches_bundled_version("FSR 4.1.2", "4.1.2"));
    assert(!matches_bundled_version("13.1.6", "3.1.6"));
    assert(!matches_bundled_version("3.1.60", "3.1.6"));
    assert(!matches_bundled_version("3.1.6.1", "3.1.6"));
    assert(!matches_bundled_version("3.1.6a", "3.1.6"));
    assert(!matches_bundled_version("FSR 3.1.6-rc1", "3.1.6"));
    assert(!matches_bundled_version("3.1.6+custom", "3.1.6"));
    assert(!matches_bundled_version("FSR 3.1.6 *", "3.1.6"));
    assert(!matches_bundled_version("FSR 4.1.2 *", "4.1.2"));
    assert(!matches_bundled_version("4.1.2", "3.1.6"));
}
"""
        output = Path(__file__).resolve().parents[3] / "tmp/fsr-sdk24-intake"
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="selector-", dir=output) as temporary:
            cpp = Path(temporary) / "selector.cpp"
            executable = Path(temporary) / ("selector.exe" if os.name == "nt" else "selector")
            cpp.write_text(program, encoding="utf-8")
            result = subprocess.run([compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                                     str(cpp), "-o", str(executable)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            result = subprocess.run([str(executable)], capture_output=True)
            # Windows may briefly hold a just-exited executable for scanning.
            for attempt in range(20):
                try:
                    executable.unlink(missing_ok=True)
                    break
                except PermissionError:
                    if attempt == 19:
                        raise
                    time.sleep(0.1)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))


class FrozenPatchStackTests(unittest.TestCase):
    def test_frozen_helper_applies_real_patch_stack_to_pinned_archive(self) -> None:
        if not shutil.which("git"):
            self.skipTest("Git is required for the native patch stack")
        root = Path(__file__).resolve().parents[3]
        archive = root / ".tools/advanced-rendering" / candidate.native_build.ARCHIVES[0][0]
        if not archive.is_file():
            self.skipTest("Pinned engine archive is not in the local native cache")
        self.assertEqual(candidate.native_build.sha256(archive), candidate.native_build.ARCHIVES[0][2])
        frozen, _ = candidate.freeze_integration()
        paths = candidate.patched_paths(frozen)
        self.assertTrue(paths)
        output = root / "tmp/fsr-sdk24-intake"
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="frozen-patches-", dir=output) as temporary:
            directory = Path(temporary)
            engine = directory / "engine"
            snapshot = directory / "integration"
            engine.mkdir()
            snapshot.mkdir()
            for name, data in frozen.items():
                (snapshot / name).write_bytes(data)
            with zipfile.ZipFile(archive) as package:
                for name in paths:
                    content = package.read(f"godot-{candidate.native_build.COMMIT}/{name}")
                    put(engine, name, content)
            candidate.apply_frozen_engine_patches(engine, archive, snapshot)
            first = {name: digest(engine / name) for name in paths}
            candidate.apply_frozen_engine_patches(engine, archive, snapshot)
            self.assertEqual({name: digest(engine / name) for name in paths}, first)


if __name__ == "__main__":
    unittest.main()
