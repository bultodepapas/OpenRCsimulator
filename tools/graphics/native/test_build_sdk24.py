"""Offline tests for the isolated SDK 2.4 engine preparation contract."""
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest import mock


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

        for name in ("fsr3.h", "fsr3.cpp", "fsr3_prepare.glsl", "sdk24.py", "build_sdk24.py"):
            put(self.here, name, f"fixture {name}\n".encode())
        put(self.root, "LICENSE", b"openrc license\n")
        put(self.engine, "LICENSE.txt", b"engine license\n")
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
            mock.patch.object(candidate.native_build, "ARCHIVES", specs),
            mock.patch.object(candidate.native_build, "ENGINE_PATCHES", ()),
            mock.patch.object(candidate.sdk24, "prepare", return_value=(self.source, self.sdk_receipt)),
            mock.patch.object(candidate.native_build, "fetch", side_effect=[self.engine, self.nvidia]),
            mock.patch.object(candidate.native_build, "apply_engine_patches"),
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


if __name__ == "__main__":
    unittest.main()
