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
VARIANTS = ("source_albedo", "adapted_albedo", "source_lit", "adapted_lit")
SLOTS = ((0, 0, 512, 512), (512, 0, 512, 512), (0, 512, 512, 512))


def _write_rgba(path: Path, pixels: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(pixels, mode="RGBA").save(path, format="PNG", optimize=False)


def _make_bake(root: Path) -> Path:
    bake_dir = root / "bake"
    bake_dir.mkdir(parents=True)
    species = []
    for tree_id, rect in zip(IDS, SLOTS, strict=True):
        species.append({
            "id": tree_id,
            "frame_size_m": 1.125001,
            "pivot_y_m": 0.5,
            "atlas_rect_px": list(rect),
        })
        for variant in VARIANTS:
            pixels = np.zeros((1024, 1024, 4), dtype=np.uint8)
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

    def test_crop_with_less_than_sixteen_pixel_padding_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bake_dir = _make_bake(root)
            adapted_path = bake_dir / "CommonTree_1-adapted_albedo.png"
            pixels = np.asarray(Image.open(adapted_path).convert("RGBA")).copy()
            pixels[128:896, :128, :3] = (102, 130, 75)
            pixels[128:896, :128, 3] = 255
            _write_rgba(adapted_path, pixels)
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

            for name in ("atlas", "catalog", "analysis"):
                self.assertEqual(first[name].read_bytes(), second[name].read_bytes(), name)
            with Image.open(first["atlas"]) as atlas:
                self.assertEqual(atlas.size, (1024, 1024))
                pixels = np.asarray(atlas.convert("RGBA"))
                self.assertFalse(np.any(pixels[512:, 512:, 3]))
            catalog = json.loads(first["catalog"].read_text(encoding="utf-8"))
            self.assertEqual(catalog["format"], "openrc-tree-assets v1")
            self.assertEqual([item["id"] for item in catalog["species"]], list(IDS))


if __name__ == "__main__":
    unittest.main()
