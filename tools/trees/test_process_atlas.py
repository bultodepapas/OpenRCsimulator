#!/usr/bin/env python3
"""Focused contract tests for the L6a atlas postprocessor."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from process_atlas import PipelineError, process_bake, weighted_box_downsample_rgba, load_raw_frame


IDS = ("CommonTree_1", "CommonTree_3", "Pine_1")
VARIANTS = ("source_albedo", "adapted_albedo", "source_lit", "adapted_lit", "adapted_foliage_mask")
SLOTS = ((0, 0, 512, 512), (512, 0, 512, 512), (0, 512, 512, 512))
FOLIAGE_NAMES = ("Leaves_NormalTree", "Leaves_NormalTree", "Leaves_Pine")


def _write_rgba(path: Path, pixels: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(pixels, mode="RGBA").save(path, format="PNG", optimize=False)


def _make_bake(root: Path) -> Path:
    bake_dir = root / "bake"
    bake_dir.mkdir(parents=True)
    species = []
    for tree_id, rect, foliage_name in zip(IDS, SLOTS, FOLIAGE_NAMES, strict=True):
        species.append({
            "id": tree_id,
            "frame_size_m": 1.125001,
            "pivot_y_m": 0.5,
            "bark_material_name": "Bark_NormalTree",
            "foliage_material_name": foliage_name,
            "atlas_rect_px": list(rect),
        })
        for variant in VARIANTS:
            pixels = np.zeros((1024, 1024, 4), dtype=np.uint8)
            if variant == "adapted_foliage_mask":
                pixels[128:512, 128:896, :3] = 255
                pixels[128:896, 128:896, 3] = 255
                _write_rgba(bake_dir / f"{tree_id}-{variant}.png", pixels)
                continue
            rgb = (102, 130, 75) if variant.endswith("albedo") else (72, 91, 53)
            pixels[128:896, 128:896, :3] = rgb
            pixels[128:896, 128:896, 3] = 255
            _write_rgba(bake_dir / f"{tree_id}-{variant}.png", pixels)
    (bake_dir / "bake.json").write_text(json.dumps({"species": species}), encoding="utf-8")
    return bake_dir


class WeightedDownsampleTests(unittest.TestCase):
    def test_transparent_black_does_not_darken_opaque_edge_color(self) -> None:
        pixels = np.zeros((2, 2, 4), dtype=np.uint8)
        pixels[0, 0] = [200, 100, 50, 255]

        result = weighted_box_downsample_rgba(pixels)

        self.assertEqual(result.shape, (1, 1, 4))
        self.assertEqual(result[0, 0].tolist(), [200, 100, 50, 64])


class RawFrameValidationTests(unittest.TestCase):
    def test_wrong_size_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "small.png"
            _write_rgba(path, np.zeros((512, 1024, 4), dtype=np.uint8))
            with self.assertRaisesRegex(PipelineError, "must be 1024x1024"):
                load_raw_frame(path)

    def test_nonbinary_alpha_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pixels = np.zeros((1024, 1024, 4), dtype=np.uint8)
            pixels[100, 100] = [12, 34, 56, 128]
            path = Path(directory) / "nonbinary.png"
            _write_rgba(path, pixels)
            with self.assertRaisesRegex(PipelineError, "only 0 or 255"):
                load_raw_frame(path)

    def test_empty_raw_silhouette_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "empty.png"
            _write_rgba(path, np.zeros((1024, 1024, 4), dtype=np.uint8))
            with self.assertRaisesRegex(PipelineError, "empty silhouette"):
                load_raw_frame(path)


class AtlasPipelineTests(unittest.TestCase):
    def test_boolean_frame_size_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bake_dir = _make_bake(root)
            path = bake_dir / "bake.json"
            data = json.loads(path.read_text())
            data["species"][0]["frame_size_m"] = True
            path.write_text(json.dumps(data))
            with self.assertRaisesRegex(PipelineError, "finite positive number"):
                process_bake(bake_dir, root / "out")

    def test_broad_albedo_color_drift_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bake_dir = _make_bake(root)
            path = bake_dir / "CommonTree_1-adapted_albedo.png"
            pixels = np.asarray(Image.open(path)).copy()
            pixels[128:896, 128:896, 0] = 200
            _write_rgba(path, pixels)
            with self.assertRaisesRegex(PipelineError, "albedo color drift"):
                process_bake(bake_dir, root / "out")

    def test_low_silhouette_iou_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bake_dir = _make_bake(root)
            adapted_path = bake_dir / "CommonTree_1-adapted_albedo.png"
            pixels = np.asarray(Image.open(adapted_path).convert("RGBA")).copy()
            pixels[128:896, 128:240, 3] = 0
            _write_rgba(adapted_path, pixels)

            with self.assertRaisesRegex(PipelineError, "silhouette alpha IoU"):
                process_bake(bake_dir, root / "out")

    def test_material_mask_alpha_must_match_adapted_atlas_coverage_exactly(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bake_dir = _make_bake(root)
            mask_path = bake_dir / "CommonTree_1-adapted_foliage_mask.png"
            pixels = np.asarray(Image.open(mask_path).convert("RGBA")).copy()
            pixels[128, 128, 3] = 0
            _write_rgba(mask_path, pixels)

            with self.assertRaisesRegex(PipelineError, "material mask alpha must match adapted albedo exactly"):
                process_bake(bake_dir, root / "out")

    def test_non_material_values_are_rejected_in_raw_identity_mask(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bake_dir = _make_bake(root)
            mask_path = bake_dir / "CommonTree_1-adapted_foliage_mask.png"
            pixels = np.asarray(Image.open(mask_path).convert("RGBA")).copy()
            pixels[256, 256, :3] = 127
            _write_rgba(mask_path, pixels)

            with self.assertRaisesRegex(PipelineError, "must contain only bark 0 or foliage 255"):
                process_bake(bake_dir, root / "out")

    def test_source_material_name_changes_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bake_dir = _make_bake(root)
            path = bake_dir / "bake.json"
            data = json.loads(path.read_text())
            data["species"][0]["foliage_material_name"] = "Bark_NormalTree"
            path.write_text(json.dumps(data))

            with self.assertRaisesRegex(PipelineError, "foliage mask identity must be 'Leaves_NormalTree'"):
                process_bake(bake_dir, root / "out")

    def test_runtime_mask_alpha_matches_existing_atlas_after_edge_reconciliation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bake_dir = _make_bake(root)
            baseline = process_bake(bake_dir, root / "baseline")
            runtime_pixels = np.asarray(Image.open(baseline["atlas"]).convert("RGBA")).copy()
            alpha = runtime_pixels[:512, :512, 3]
            added_pixel = None
            for y in range(1, 511):
                for x in range(1, 511):
                    if alpha[y, x] == 0 and np.any(alpha[y - 1:y + 2, x - 1:x + 2] > 0):
                        added_pixel = (y, x)
                        break
                if added_pixel is not None:
                    break
            self.assertIsNotNone(added_pixel)
            y, x = added_pixel
            alpha[y, x] = 255
            runtime_path = root / "runtime-atlas.png"
            _write_rgba(runtime_path, runtime_pixels)

            aligned = process_bake(bake_dir, root / "aligned", runtime_path)
            with Image.open(aligned["foliage_mask"]) as mask_image:
                mask = np.asarray(mask_image.convert("RGBA"))
            self.assertTrue(np.array_equal(mask[:512, :512, 3], runtime_pixels[:512, :512, 3]))
            self.assertEqual(int(mask[y, x, 3]), 255)
            self.assertGreater(int(mask[y, x, 0]), 0)
            report = json.loads(aligned["analysis"].read_text())
            first = report["species"][0]
            self.assertTrue(first["runtime_mask_alpha_exactly_matches_runtime_atlas"])
            self.assertEqual(first["runtime_only_edge_labels_filled_from_nearest_source_material_id"], 1)
            self.assertGreaterEqual(first["runtime_mask_alpha_alignment_before_edge_reconciliation"]["coverage_iou_nonzero"], 0.995)
            catalog = json.loads(aligned["catalog"].read_text())
            self.assertEqual(catalog["foliage_mask"], "res://assets/landscape/trees/foliage_mask.png")

    def test_runtime_alpha_reference_with_misaligned_silhouette_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bake_dir = _make_bake(root)
            runtime_pixels = np.zeros((1024, 1024, 4), dtype=np.uint8)
            runtime_path = root / "misaligned-runtime.png"
            _write_rgba(runtime_path, runtime_pixels)

            with self.assertRaisesRegex(PipelineError, "runtime atlas alpha silhouette alignment is below"):
                process_bake(bake_dir, root / "out", runtime_path)

    def test_crop_with_less_than_sixteen_pixel_padding_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bake_dir = _make_bake(root)
            adapted_path = bake_dir / "CommonTree_1-adapted_albedo.png"
            pixels = np.asarray(Image.open(adapted_path).convert("RGBA")).copy()
            pixels[128:896, :128, :3] = (102, 130, 75)
            pixels[128:896, :128, 3] = 255
            _write_rgba(adapted_path, pixels)
            mask_path = bake_dir / "CommonTree_1-adapted_foliage_mask.png"
            mask_pixels = np.asarray(Image.open(mask_path).convert("RGBA")).copy()
            mask_pixels[128:896, :128, :3] = 255
            mask_pixels[128:896, :128, 3] = 255
            _write_rgba(mask_path, mask_pixels)
            # Keep source and adapted alpha close enough to test the tile-padding guard specifically.
            source_path = bake_dir / "CommonTree_1-source_albedo.png"
            source_pixels = np.asarray(Image.open(source_path).convert("RGBA")).copy()
            source_pixels[128:896, :128, :3] = (102, 130, 75)
            source_pixels[128:896, :128, 3] = 255
            _write_rgba(source_path, source_pixels)

            with self.assertRaisesRegex(PipelineError, "transparent padding must be at least 16px"):
                process_bake(bake_dir, root / "out")

    def test_two_runs_write_byte_identical_outputs_and_leave_fourth_tile_empty(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bake_dir = _make_bake(root)
            first = process_bake(bake_dir, root / "first")
            second = process_bake(bake_dir, root / "second")

            for name in ("atlas", "foliage_mask", "catalog", "analysis"):
                self.assertEqual(first[name].read_bytes(), second[name].read_bytes(), name)
            with Image.open(first["atlas"]) as atlas:
                self.assertEqual(atlas.size, (1024, 1024))
                atlas_pixels = np.asarray(atlas.convert("RGBA")).copy()
                self.assertFalse(np.any(atlas_pixels[512:, 512:, 3]))
            catalog = json.loads(first["catalog"].read_text(encoding="utf-8"))
            self.assertEqual(catalog["format"], "openrc-tree-assets v1")
            self.assertEqual([item["id"] for item in catalog["species"]], list(IDS))
            with Image.open(first["foliage_mask"]) as mask:
                pixels = np.asarray(mask.convert("RGBA"))
                self.assertEqual(pixels.shape, (1024, 1024, 4))
                self.assertFalse(np.any(pixels[512:, 512:, 3]))
                self.assertTrue(np.array_equal(pixels[:, :, 3], atlas_pixels[:, :, 3]))
                tile = pixels[:512, :512]
                self.assertGreater(int((tile[128:320, 128:512, 0] == 255).sum()), 0)
                self.assertGreater(int((tile[320:512, 128:512, 0] == 0).sum()), 0)


if __name__ == "__main__":
    unittest.main()
