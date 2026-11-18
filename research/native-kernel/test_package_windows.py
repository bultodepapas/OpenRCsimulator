"""NK-4 Windows release package (owner decision 2026-11-18, native kernel always): static packaging contracts.

The loader in app/sim/native_stage.gd compares the packaged descriptor byte for byte; package.py must write exactly
that text. Execution of the packaged DLL is qualified separately on the exported executable.
"""
import importlib.util
import re
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC = importlib.util.spec_from_file_location("nk4_package_under_test", HERE / "package.py")
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)


def gdscript_constant(path: Path, name: str) -> str:
    """Concatenate a `const NAME := ( "..." + "..." )` GDScript string literal."""
    text = path.read_text(encoding="utf-8")
    match = re.search(r"const %s := \((.*?)\n\)" % re.escape(name), text, re.S)
    if match is None:
        raise AssertionError(f"{name} not found in {path}")
    parts = re.findall(r'"((?:[^"\\]|\\.)*)"', match.group(1))
    return "".join(part.encode("utf-8").decode("unicode_escape") for part in parts)


class WindowsPackageContract(unittest.TestCase):
    def test_descriptor_matches_the_loader_contract(self):
        expected = gdscript_constant(ROOT / "app/sim/native_stage.gd", "EXPECTED_WINDOWS_PACKAGE_DESCRIPTOR")
        self.assertEqual(package.WINDOWS_PACKAGE_DESCRIPTOR, expected)
        self.assertNotIn("res://", package.WINDOWS_PACKAGE_DESCRIPTOR)

    def test_linux_descriptor_is_unchanged(self):
        self.assertEqual(package.DESCRIPTOR,
                         gdscript_constant(ROOT / "app/sim/native_stage.gd", "EXPECTED_PACKAGE_DESCRIPTOR"))

    def test_manifests_are_separate_files(self):
        self.assertNotEqual(package.WINDOWS_MANIFEST, package.MANIFEST)
        self.assertEqual(package.WINDOWS_MANIFEST.name, "package-windows.json")
        loader = (ROOT / "app/app_state/native_package.gd").read_text(encoding="utf-8")
        self.assertIn('WINDOWS_MANIFEST_PATH := "res://native/kernel/package-windows.json"', loader)
        plugin = (ROOT / "app/addons/native_kernel/export_plugin.gd").read_text(encoding="utf-8")
        self.assertIn('WINDOWS_MANIFEST := "res://native/kernel/package-windows.json"', plugin)

    def test_descriptor_is_written_with_lf_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "openrc_native_kernel.gdextension"
            path.write_text(package.WINDOWS_PACKAGE_DESCRIPTOR, encoding="utf-8", newline="\n")
            self.assertNotIn(b"\r", path.read_bytes())

    def test_finalize_refuses_without_a_prepared_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "missing.exe"
            with self.assertRaises((FileNotFoundError, OSError)):
                package.finalize_windows(missing, missing, Path(directory))

    def test_solver_identity_sources_match_flight_log(self):
        """The exported plugin compares FlightLog.solver_identity() with the manifest package.py writes."""
        flight_log = (ROOT / "app/sim/flight_log.gd").read_text(encoding="utf-8")
        block = flight_log[flight_log.index("static func _solver_identity_uncached()"):]
        block = block[:block.index("\nstatic func", 10)]
        self.assertIn('for directory in ["res://physics", "res://sim", "res://failures"]', block)
        extras = re.findall(r'"res://([^"]+\.gd)"', block.split("for source in", 1)[1].split("\n", 1)[0])
        self.assertEqual(tuple(extras), package.SOLVER_EXTRA_SOURCES)

    def test_cli_exposes_windows_commands(self):
        source = (HERE / "package.py").read_text(encoding="utf-8")
        self.assertIn('commands.add_parser("prepare-windows")', source)
        self.assertIn('commands.add_parser("finalize-windows")', source)


if __name__ == "__main__":
    unittest.main()
