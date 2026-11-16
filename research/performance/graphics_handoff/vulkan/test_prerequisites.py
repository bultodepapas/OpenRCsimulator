"""Source-bound controls for the two pinned Vulkan research patches.

Set OPENRC_GODOT_SOURCE_DIR to a pristine tree containing the three named
complete files at Godot cafc17a192acf67903910a68aeb3c076c0907a4b. Full-file
SHA-256 is checked before copying. Each patch is checked and applied in order
only to a disposable copy. The executable controls compile actual extracted
patched functions and an extracted data structure against native-call, memory,
container and resource stand-ins. The RD RID owner and Vulkan structures are
stand-ins; the wrapper creation cases use no geometry. The tracked VMA path
uses only its actual patched block inside a stand-in enclosing function. This
is not a Godot translation-unit build,
a Vulkan driver/device test, validation-layer execution, or GPU qualification.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
SOURCE_ENV = "OPENRC_GODOT_SOURCE_DIR"
PATHS = {
    "drivers/vulkan/rendering_device_driver_vulkan.cpp": "482b78643b2cfc28873f61800b98b631c7a84a8c30f7177fd57982a0b2b17350",
    "drivers/vulkan/rendering_device_driver_vulkan.h": "eb15e7855afe5dbb2d15ae6abd797e5bf1decd40fe60172b2ace89ada7850c5b",
    "servers/rendering/rendering_device.cpp": "60e9c20f0d28cf822aec5adf4b9b9560910b877eb40b528fed3138a08d36ebd2",
}
PATCHES = (HERE / "0001-as-address-and-creation.patch", HERE / "0002-tlas-instance-reservation.patch")

# Reuse the existing balanced C++ function/block extractor, including its
# handling of braces in comments and literals.
_spec = importlib.util.spec_from_file_location("metalfx_patch_checks", ROOT / "tools/graphics/metalfx/test_engine_patch.py")
assert _spec and _spec.loader
_helpers = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_helpers)
cxx_function, cxx_block = _helpers.cxx_function, _helpers.cxx_block


def verified_copy(source: Path, destination: Path) -> None:
    for name, expected in PATHS.items():
        path = source / name
        try:
            data = path.read_bytes()
        except OSError as exc:
            raise RuntimeError(f"Cannot read required pristine source {path}: {exc}") from exc
        digest = hashlib.sha256(data).hexdigest()
        if digest != expected:
            raise RuntimeError(f"Pristine source SHA-256 mismatch for {name}: {digest} != {expected}")
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)


class VulkanPrerequisiteControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        source_env = os.environ.get(SOURCE_ENV)
        if not source_env:
            raise RuntimeError(f"Set {SOURCE_ENV} to the pristine pinned source tree")
        compiler = shutil.which("g++") or shutil.which("clang++")
        if not compiler:
            raise RuntimeError("A C++17 compiler is required")
        cls.compiler = compiler
        cls.temp = tempfile.TemporaryDirectory(prefix="openrc-vulkan-controls-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.base = Path(cls.temp.name)
        verified_copy(Path(source_env), cls.base)
        cls.original_driver = (cls.base / "drivers/vulkan/rendering_device_driver_vulkan.cpp").read_text(encoding="utf-8")
        cls.original_rd = (cls.base / "servers/rendering/rendering_device.cpp").read_text(encoding="utf-8")
        # Do not let a caller's Git environment or user/system config redirect
        # application to another work tree or alter Git's whitespace rules.
        git_env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        git_env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                       GIT_CEILING_DIRECTORIES=str(cls.base))
        for patch in PATCHES:
            for check in (True, False):
                command = ["git", "apply", "--whitespace=error"]
                if check:
                    command.append("--check")
                command.append(str(patch))
                result = subprocess.run(command, cwd=cls.base, env=git_env,
                                        capture_output=True, text=True, timeout=30)
                if result.returncode:
                    raise RuntimeError(f"{' '.join(command)} failed:\n{result.stdout}{result.stderr}")
        driver = (cls.base / "drivers/vulkan/rendering_device_driver_vulkan.cpp").read_text(encoding="utf-8")
        header = (cls.base / "drivers/vulkan/rendering_device_driver_vulkan.h").read_text(encoding="utf-8")
        rd = (cls.base / "servers/rendering/rendering_device.cpp").read_text(encoding="utf-8")
        template = (HERE / "controls.cpp.in").read_text(encoding="utf-8")
        info = "struct AccelerationStructureInfo " + cxx_block(header, header.index("struct AccelerationStructureInfo")) + ";"
        parts = {
            "@ACCEL_INFO@": info,
            "@TRANSFORM@": cxx_function(driver, "static _FORCE_INLINE_ void _store_transform_transposed_3x4("),
            "@BLAS_CREATE@": cxx_function(driver, "RDD::AccelerationStructureID RenderingDeviceDriverVulkan::blas_create("),
            "@TLAS_CREATE@": cxx_function(driver, "RDD::AccelerationStructureID RenderingDeviceDriverVulkan::tlas_create("),
            "@INSTANCE_WRITE@": cxx_function(driver, "void RenderingDeviceDriverVulkan::acceleration_structure_instance_write("),
            "@CREATE@": cxx_function(driver, "bool RenderingDeviceDriverVulkan::_acceleration_structure_create("),
            "@FREE@": cxx_function(driver, "void RenderingDeviceDriverVulkan::acceleration_structure_free("),
            "@TLAS_BUILD@": cxx_function(rd, "Error RenderingDevice::tlas_build("),
            "@TRACKED_ALLOC@": cls.tracked_block(driver),
            "@RD_BLAS_CREATE@": cxx_function(rd, "RID RenderingDevice::blas_create("),
            "@RD_TLAS_CREATE@": cxx_function(rd, "RID RenderingDevice::tlas_create("),
        }
        cls.patched_source = cls.compose(template, parts)
        cls.driver_binary = cls.compile(cls.patched_source, "driver", "DRIVER_CONTROL")
        cls.tlas_binary = cls.compile(cls.patched_source, "tlas", "TLAS_CONTROL")
        cls.tracked_binary = cls.compile(cls.patched_source, "tracked", "TRACKED_CONTROL")
        cls.template, cls.parts = template, parts

    @staticmethod
    def tracked_block(source: str) -> str:
        function = cxx_function(source, "RDD::BufferID RenderingDeviceDriverVulkan::buffer_create(")
        branch_start = function.index("} else {\n\t\tVkResult err = vkCreateBuffer(")
        return cxx_block(function, branch_start)

    @staticmethod
    def compose(template: str, parts: dict[str, str]) -> str:
        for marker, value in parts.items():
            assert template.count(marker) == 1, marker
            template = template.replace(marker, value)
        return template

    @classmethod
    def compile(cls, source: str, name: str, flag: str) -> Path:
        cpp, binary = cls.base / f"{name}.cpp", cls.base / name
        cpp.write_text(source, encoding="utf-8")
        result = subprocess.run([cls.compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", f"-D{flag}", str(cpp), "-o", str(binary)], capture_output=True, text=True, timeout=90)
        if result.returncode:
            raise AssertionError(f"{name} compilation failed:\n{result.stdout}{result.stderr}")
        return binary

    def run_case(self, binary: Path, case: str, expected: bool = True) -> None:
        result = subprocess.run([str(binary), case], cwd=self.base, capture_output=True, text=True, timeout=10)
        if expected:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS "+case, result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, f"Original/regressed source unexpectedly passed {case}")
            self.assertIn("Assertion", result.stderr)

    def test_pristine_identity_rejects_changed_source(self) -> None:
        source = self.base / "identity-control"
        verified_copy(Path(os.environ[SOURCE_ENV]), source)
        changed = source / "servers/rendering/rendering_device.cpp"
        changed.write_bytes(changed.read_bytes() + b"\n")
        with self.assertRaisesRegex(RuntimeError, "Pristine source SHA-256 mismatch"):
            verified_copy(source, self.base / "identity-refused")

    def test_address_uses_as_query_not_buffer_address(self) -> None:
        self.run_case(self.driver_binary, "address")

    def test_creation_failure_and_lifetime(self) -> None:
        for case in ("allocation", "missing_query", "create_failure", "zero_address", "oversized_scratch", "free_order", "rid_rejection"):
            with self.subTest(case=case):
                self.run_case(self.driver_binary, case)

    def test_tlas_reservation_and_rejections(self) -> None:
        for case in ("reservations", "dependencies", "wrong_type", "overflow", "create_failure", "map_failure", "retirement"):
            with self.subTest(case=case):
                self.run_case(self.tlas_binary, case)

    def test_tracked_buffer_allocation_cleanup(self) -> None:
        for case in ("allocation_failure", "bind_failure", "create_failure", "success"):
            with self.subTest(case=case):
                self.run_case(self.tracked_binary, case)

    def test_unmodified_source_negative_controls(self) -> None:
        # Execute actual original function bodies against the same stand-ins; an
        # assertion must fail at runtime, not merely at extraction or compilation.
        parts = dict(self.parts)
        parts["@INSTANCE_WRITE@"] = cxx_function(self.original_driver, "void RenderingDeviceDriverVulkan::acceleration_structure_instance_write(")
        binary = self.compile(self.compose(self.template, parts), "original_address", "DRIVER_CONTROL")
        self.run_case(binary, "address", expected=False)
        parts = dict(self.parts)
        parts["@TLAS_BUILD@"] = cxx_function(self.original_rd, "Error RenderingDevice::tlas_build(")
        binary = self.compile(self.compose(self.template, parts), "original_tlas", "TLAS_CONTROL")
        self.run_case(binary, "reservations", expected=False)
        self.run_case(binary, "dependencies", expected=False)
        parts = dict(self.parts)
        parts["@TRACKED_ALLOC@"] = self.tracked_block(self.original_driver)
        binary = self.compile(self.compose(self.template, parts), "original_tracked", "TRACKED_CONTROL")
        self.run_case(binary, "allocation_failure", expected=False)
        self.run_case(binary, "bind_failure", expected=False)


if __name__ == "__main__":
    unittest.main()
