"""Integrity checks for the reviewed HX-700 mechanical-motion snapshot."""
import importlib.util
import hashlib
import ast
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("hx700_motion_compiler", HERE / "compile_hx700_motion.py")
COMPILER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPILER)
EXTRACTOR = HERE / "extract_hx700_motion.py"


def encode_snapshot(data):
    return (json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")


class MotionCompilerSnapshotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source_bytes = COMPILER.SOURCE.read_bytes()
        cls.source_data = json.loads(cls.source_bytes.decode("utf-8"))
        cls.generated = COMPILER.OUTPUT.read_text(encoding="utf-8")

    def test_reviewed_snapshot_compiles_to_checked_in_equations(self):
        self.assertEqual(COMPILER.MOTION_SOURCE_SHA256,
                         hashlib.sha256(self.source_bytes).hexdigest())
        self.assertEqual(COMPILER.compile_source(self.source_bytes), self.generated)
        self.assertIn('const MOTION_SOURCE_SHA256 := "%s"' % COMPILER.MOTION_SOURCE_SHA256,
                      self.generated)

    def test_driver_edit_is_rejected_even_if_blend_sha_claim_is_unchanged(self):
        changed = json.loads(self.source_bytes.decode("utf-8"))
        driver = next(d for d in changed["objects"]["Mezclador_01_Mandos"]["drivers"]
                      if d["path"] == '["COL"]')
        driver["expression"] = "0.0"
        self.assertEqual(changed["source_sha256"], COMPILER.SOURCE_SHA256)
        with self.assertRaisesRegex(ValueError, "snapshot differs"):
            COMPILER.compile_source(encode_snapshot(changed))

    def test_recipe_edit_is_rejected_even_if_blend_sha_claim_is_unchanged(self):
        changed = json.loads(self.source_bytes.decode("utf-8"))
        changed["recipes"][0]["location"][0] += 0.001
        self.assertEqual(changed["source_sha256"], COMPILER.SOURCE_SHA256)
        with self.assertRaisesRegex(ValueError, "snapshot differs"):
            COMPILER.compile_source(encode_snapshot(changed))

    def test_extractor_source_admission_survives_optimized_python(self):
        stub = """
import runpy, sys, types
script, output, source = sys.argv[1:]
bpy = types.ModuleType("bpy")
bpy.data = types.SimpleNamespace(filepath=source)
mathutils = types.ModuleType("mathutils")
mathutils.Matrix = lambda *_args, **_kwargs: None
sys.modules["bpy"] = bpy
sys.modules["mathutils"] = mathutils
sys.argv = [script, "--", "--out=" + output]
runpy.run_path(script, run_name="__main__")
"""
        with tempfile.TemporaryDirectory(prefix="hx700-motion-admission-",
                                         dir=COMPILER.ROOT / ".tools") as temporary:
            temporary_path = Path(temporary)
            source = temporary_path / "wrong-source.blend"
            source.write_bytes(b"not the reviewed HX-700 source")
            output = temporary_path / "generated"
            result = subprocess.run(
                [sys.executable, "-O", "-c", stub, str(EXTRACTOR), str(output), str(source)],
                cwd=COMPILER.ROOT, capture_output=True, text=True, encoding="utf-8")
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("source SHA-256 changed before extraction", result.stdout + result.stderr)
            self.assertFalse(output.exists(), "failed source admission created its output directory")

    def test_extractor_has_no_optimization_sensitive_assertions(self):
        tree = ast.parse(EXTRACTOR.read_text(encoding="utf-8"))
        self.assertFalse(any(isinstance(node, ast.Assert) for node in ast.walk(tree)))


if __name__ == "__main__":
    unittest.main()
