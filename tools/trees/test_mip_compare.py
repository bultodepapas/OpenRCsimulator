"""Negative controls for the analysis-only native maple coverage comparison."""

from copy import deepcopy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image, ImageDraw

import mip_compare as probe


def manifest(label: str) -> dict:
    mips = label != "baseline"
    config = ('[params]\ncompress/mode=2\nmipmaps/generate=' + str(mips).lower()
              + '\nmipmaps/preserve_alpha_test_coverage=' + str(label == "candidate").lower()
              + '\nmipmaps/alpha_test_threshold=0.5\nprocess/fix_alpha_border=true\n')
    texture = {
        "basename": "maple_leaves_basecolor.png", "source_png_sha256": "a" * 64,
        "import_path": probe.MAPLE_ALPHA + ".import", "import_sha256": label,
        "texture_class": "CompressedTexture2D", "image_size": [2048, 2048], "image_format": 18,
        "used_by": ["maple_tree"], "import_config_text": config,
        "decoded_image_has_mipmaps": mips, "decoded_image_mipmap_count": 11 if mips else 0,
        "decoded_image_data_sha256": label, "decoded_image_data_bytes": 1024 if mips else 768,
        "decoded_image_base_level_sha256": "e" * 64,
    }
    return {
        "format": "openrc-tree-mipmap-sweep v1", "complete": True, "mip_scope": "coverage",
        "godot": "4.8.beta1.official", "renderer": "gl_compatibility", "adapter": "test GPU", "api": "test GL",
        "identity": {"res://project.godot": "b" * 64},
        "assets": {"maple_tree": {"scene_sha256": "c" * 64, "surfaces": [
            {"albedo_texture": probe.MAPLE_ALPHA, "alpha_scissor_threshold": 0.5}]}},
        "textures": {probe.MAPLE_ALPHA: texture, "res://bark.png": {"source_png_sha256": "d" * 64}},
        "fixture": {"asset_ids": ["maple_tree"], "distances_m": [32.0, 64.0, 128.0, 256.0],
                    "view_sizes": [[1920, 1080]], "phase_count": 8,
                    "phase_offsets_pixels": [phase / 8 for phase in range(8)],
                    "msaa": "4x", "wind_enabled": False, "wind_vector_mps": [0.0, 0.0, 0.0],
                    "wind_clock_seconds": 0.0, "shadow_enabled": False},
        "captures": [],
    }


class CoverageValidationTests(unittest.TestCase):
    def setUp(self):
        self.captures = {label: manifest(label) for label in ("baseline", "ordinary", "candidate")}

    def test_policies_and_import_inventory(self):
        audit = probe.validate_coverage_triplet(self.captures)
        self.assertEqual(audit["baseline"]["decoded_image_mipmap_count"], 0)
        self.assertEqual(audit["candidate"]["decoded_image_mipmap_count"], 11)

    def test_rejects_independent_identity_and_policy_mutations(self):
        cases = [
            ("fixture", lambda data: data["fixture"].update(msaa="disabled")),
            ("assets", lambda data: data["assets"]["maple_tree"].update(triangles=1)),
            ("adapter", lambda data: data.update(adapter="different GPU")),
            ("source identity", lambda data: data["textures"][probe.MAPLE_ALPHA].update(source_png_sha256="e" * 64)),
            ("unrelated texture", lambda data: data["textures"]["res://bark.png"].update(decoded_image_data_bytes=999)),
            ("outside the three", lambda data: data["textures"][probe.MAPLE_ALPHA].update(
                import_config_text=data["textures"][probe.MAPLE_ALPHA]["import_config_text"].replace("compress/mode=2", "compress/mode=0"))),
            ("policy", lambda data: data["textures"][probe.MAPLE_ALPHA].update(
                import_config_text=data["textures"][probe.MAPLE_ALPHA]["import_config_text"].replace("threshold=0.5", "threshold=0.2"))),
            ("decoded mip", lambda data: data["textures"][probe.MAPLE_ALPHA].update(decoded_image_has_mipmaps=False)),
        ]
        for expected, mutate in cases:
            with self.subTest(expected=expected):
                captures = deepcopy(self.captures)
                mutate(captures["candidate"])
                with self.assertRaisesRegex(ValueError, expected):
                    probe.validate_coverage_triplet(captures)

    def test_rejects_camera_metadata_drift(self):
        row = {"asset_id": "maple_tree", "distance_m": 16, "width": 1920, "height": 1080,
               "phase_index": 0, "world_offset_x_m": 0.0}
        for data in self.captures.values():
            data["captures"] = [deepcopy(row)]
        self.captures["candidate"]["captures"][0]["world_offset_x_m"] = 0.2
        with self.assertRaisesRegex(ValueError, "camera/subpixel"):
            probe.validate_coverage_triplet(self.captures)

    def test_missing_optional_false_preservation_defaults_are_valid(self):
        for label in ("baseline", "ordinary"):
            texture = self.captures[label]["textures"][probe.MAPLE_ALPHA]
            texture["import_config_text"] = texture["import_config_text"].replace(
                "mipmaps/preserve_alpha_test_coverage=false\n", "").replace("mipmaps/alpha_test_threshold=0.5\n", "")
        probe.validate_coverage_triplet(self.captures)


class CaptureFilesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.directories = {}
        for label, rectangle in (("baseline", (900, 400, 1020, 680)),
                                 ("ordinary", (920, 440, 1000, 640)),
                                 ("candidate", (902, 402, 1018, 678))):
            directory = cls.root / label
            directory.mkdir()
            cls.directories[label] = directory
            image = Image.new("RGB", (1920, 1080), (0, 0, 200))
            ImageDraw.Draw(image).rectangle(rectangle, fill=(40, 160, 30))
            image.save(directory / "tree.png")
            digest = probe.sha256_file(directory / "tree.png")
            data = manifest(label)
            data["captures"] = [{"asset_id": "maple_tree", "distance_m": distance, "width": 1920, "height": 1080,
                                 "phase_index": phase, "subpixel_offset_x_px": phase / 8,
                                 "filename": "tree.png", "sha256": digest}
                                for distance in (32.0, 64.0, 128.0, 256.0) for phase in range(8)]
            (directory / "report.json").write_text(json.dumps(data), encoding="utf-8")

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_analysis_cli_needs_no_engine_and_records_dissolving_control(self):
        out = self.root / "analysis"
        command = [sys.executable, str(Path(probe.__file__)), "--out", str(out)]
        for label, directory in self.directories.items():
            command.extend([f"--coverage-{label}", str(directory)])
        completed = subprocess.run(command, capture_output=True, text=True, timeout=60)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        data = json.loads((out / "comparison.json").read_text())
        ordinary = data["comparisons_against_unmipped"]["ordinary"][0]
        candidate = data["comparisons_against_unmipped"]["candidate"][0]
        self.assertLess(ordinary["difference"]["mean_coverage_delta_pixels"], 0)
        self.assertGreater(candidate["difference"]["mean_mask_iou"], ordinary["difference"]["mean_mask_iou"])
        self.assertNotIn("accepted", data)
        with self.assertRaisesRegex(ValueError, "new or empty"):
            probe.compare_coverage(self.directories, out)

    def test_rejects_wrong_hash_missing_phase_wrong_dimensions_and_non1080_fixture(self):
        original = json.loads((self.directories["baseline"] / "report.json").read_text())
        directory = self.root / "mutations"
        directory.mkdir(exist_ok=True)
        (directory / "tree.png").write_bytes((self.directories["baseline"] / "tree.png").read_bytes())
        mutations = [
            ("hash mismatch", lambda data: data["captures"][0].update(sha256="0" * 64)),
            ("frames", lambda data: data["captures"].pop()),
            ("dimensions", lambda data: data["captures"][0].update(width=1280)),
            ("fixture", lambda data: data["fixture"].update(view_sizes=[[1280, 720]])),
            ("frame keys", lambda data: data["captures"][0].update(phase_index=9)),
        ]
        for expected, mutate in mutations:
            with self.subTest(expected=expected):
                data = deepcopy(original)
                mutate(data)
                path = directory / "report.json"
                path.write_text(json.dumps(data), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, expected):
                    probe.parse_capture(path, coverage=True)


if __name__ == "__main__":
    unittest.main()
