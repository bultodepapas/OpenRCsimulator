#!/usr/bin/env python3
"""Validate the Godot L6a raw captures and assemble the straight-alpha atlas."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image


ATLAS_SIZE = 1024
TILE_SIZE = 512
RAW_SIZE = 1024
ALPHA_IOU_MINIMUM = 0.995
MIN_TRANSPARENT_PADDING = 16
VARIANTS = ("source_albedo", "adapted_albedo", "source_lit", "adapted_lit")
EXPECTED_SLOTS = {
    "CommonTree_1": (0, 0, TILE_SIZE, TILE_SIZE),
    "CommonTree_3": (TILE_SIZE, 0, TILE_SIZE, TILE_SIZE),
    "Pine_1": (0, TILE_SIZE, TILE_SIZE, TILE_SIZE),
}



class PipelineError(ValueError):
    """Input bake or atlas output violates the L6a asset contract."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise PipelineError(message)


def load_raw_frame(path: Path) -> np.ndarray:
    """Load one capture and enforce the exact 1024² RGBA8 binary-alpha contract."""
    try:
        with Image.open(path) as image:
            _require(image.format == "PNG", f"{path.name}: raw capture must be a PNG.")
            _require(image.mode == "RGBA", f"{path.name}: raw capture must be RGBA, got {image.mode}.")
            _require(image.size == (RAW_SIZE, RAW_SIZE),
                     f"{path.name}: raw capture must be {RAW_SIZE}x{RAW_SIZE}, got {image.width}x{image.height}.")
            image.load()
            pixels = np.asarray(image, dtype=np.uint8).copy()
    except PipelineError:
        raise
    except (OSError, ValueError) as error:
        raise PipelineError(f"Cannot read raw capture {path}: {error}") from error

    alpha = pixels[:, :, 3]
    _require(bool(np.logical_or(alpha == 0, alpha == 255).all()),
             f"{path.name}: raw alpha must contain only 0 or 255 (MSAA must be disabled).")
    _require(bool((alpha == 255).any()), f"{path.name}: raw capture has an empty silhouette.")
    return pixels


def alpha_iou(left_alpha: np.ndarray, right_alpha: np.ndarray) -> float:
    """Intersection-over-union for binary-alpha silhouettes."""
    _require(left_alpha.shape == right_alpha.shape, "Silhouette alpha arrays have different sizes.")
    left = left_alpha == 255
    right = right_alpha == 255
    union_count = int(np.logical_or(left, right).sum())
    _require(union_count > 0, "Cannot compare an empty silhouette.")
    return float(np.logical_and(left, right).sum() / union_count)


def weighted_box_downsample_rgba(pixels: np.ndarray) -> np.ndarray:
    """Downsample 2x with box alpha and alpha-weighted straight-alpha RGB."""
    _require(pixels.ndim == 3 and pixels.shape[2] == 4, "Downsample expects an RGBA image array.")
    height, width, _ = pixels.shape
    _require(height > 0 and width > 0 and height % 2 == 0 and width % 2 == 0,
             f"Downsample expects positive even dimensions, got {width}x{height}.")
    _require(pixels.dtype == np.uint8, "Downsample expects 8-bit RGBA pixels.")

    blocks = pixels.reshape(height // 2, 2, width // 2, 2, 4).astype(np.uint32)
    block_alpha = blocks[:, :, :, :, 3]
    alpha_sum = block_alpha.sum(axis=(1, 3), dtype=np.uint32)
    weighted_rgb_sum = (blocks[:, :, :, :, :3] * block_alpha[:, :, :, :, None]).sum(
        axis=(1, 3), dtype=np.uint32
    )

    rgb = np.zeros(weighted_rgb_sum.shape, dtype=np.float64)
    np.divide(weighted_rgb_sum, alpha_sum[:, :, None], out=rgb, where=alpha_sum[:, :, None] != 0)
    rgb_u8 = np.floor(rgb + 0.5).clip(0, 255).astype(np.uint8)
    alpha_u8 = ((alpha_sum + 2) // 4).clip(0, 255).astype(np.uint8)
    return np.concatenate((rgb_u8, alpha_u8[:, :, None]), axis=2)


def _load_bake(bake_dir: Path) -> list[dict[str, Any]]:
    bake_path = bake_dir / "bake.json"
    try:
        bake = json.loads(bake_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PipelineError(f"Cannot read bake metadata {bake_path}: {error}") from error

    species = bake.get("species") if isinstance(bake, dict) else None
    _require(isinstance(species, list), "bake.json must contain a species array.")
    _require(len(species) == len(EXPECTED_SLOTS) and all(isinstance(item, dict) for item in species),
             f"bake.json must contain exactly {len(EXPECTED_SLOTS)} species objects.")
    _require([item.get("id") for item in species] == list(EXPECTED_SLOTS),
             f"bake.json species order must be {list(EXPECTED_SLOTS)}.")

    for item in species:
        tree_id = item["id"]
        frame_size = item.get("frame_size_m")
        _require(type(frame_size) in (int, float) and math.isfinite(frame_size) and frame_size > 0,
                 f"{tree_id}: frame_size_m must be a finite positive number.")
        _require(item.get("pivot_y_m") == 0.5, f"{tree_id}: pivot_y_m must be 0.5 m.")
        rect = item.get("atlas_rect_px")
        _require(isinstance(rect, list) and len(rect) == 4 and all(type(value) is int for value in rect),
                 f"{tree_id}: atlas_rect_px must contain four integers.")
        _require(tuple(rect) == EXPECTED_SLOTS[tree_id],
                 f"{tree_id}: atlas_rect_px must be {list(EXPECTED_SLOTS[tree_id])}.")
    return species


def _transparent_padding(tile: np.ndarray) -> tuple[dict[str, int], list[int]]:
    opaque_y, opaque_x = np.nonzero(tile[:, :, 3] > 0)
    _require(opaque_x.size > 0, "Atlas tile has an empty silhouette.")
    bbox = [int(opaque_x.min()), int(opaque_y.min()), int(opaque_x.max()), int(opaque_y.max())]
    padding = {
        "left": bbox[0],
        "top": bbox[1],
        "right": TILE_SIZE - 1 - bbox[2],
        "bottom": TILE_SIZE - 1 - bbox[3],
    }
    too_small = [side for side, amount in padding.items() if amount < MIN_TRANSPARENT_PADDING]
    _require(not too_small,
             f"Atlas tile is cropped: transparent padding must be at least {MIN_TRANSPARENT_PADDING}px on every side; "
             f"found {padding}.")
    return padding, bbox


def _opaque_rgb_difference(source: np.ndarray, adapted: np.ndarray) -> dict[str, Any]:
    common_opaque = (source[:, :, 3] == 255) & (adapted[:, :, 3] == 255)
    count = int(common_opaque.sum())
    _require(count > 0, "Albedo captures have no common opaque pixels for RGB comparison.")
    difference = np.abs(source[:, :, :3].astype(np.int16) - adapted[:, :, :3].astype(np.int16))
    selected = difference[common_opaque]
    return {
        "compared_opaque_pixels": count,
        "mean_absolute_rgb_difference_0_255": float(selected.mean()),
        "mean_absolute_difference_by_channel_0_255": [float(value) for value in selected.mean(axis=0)],
        "maximum_absolute_rgb_difference_0_255": int(selected.max()),
        "fraction_pixels_above_two_rgb_levels": float((selected.max(axis=1) > 2).mean()),

    }


def _save_png(path: Path, pixels: np.ndarray) -> None:
    Image.fromarray(pixels, mode="RGBA").save(path, format="PNG", optimize=False, compress_level=9)


def process_bake(bake_dir: Path, out_dir: Path) -> dict[str, Path]:
    """Validate captures and write atlas.png, catalog.json, and atlas-analysis.json."""
    bake_dir = Path(bake_dir)
    out_dir = Path(out_dir)
    _require(bake_dir.is_dir(), f"Bake directory does not exist: {bake_dir}")
    species = _load_bake(bake_dir)

    atlas = np.zeros((ATLAS_SIZE, ATLAS_SIZE, 4), dtype=np.uint8)
    analysis_species: list[dict[str, Any]] = []
    for item in species:
        tree_id = item["id"]
        frames = {
            variant: load_raw_frame(bake_dir / f"{tree_id}-{variant}.png")
            for variant in VARIANTS
        }

        alpha_checks: dict[str, dict[str, Any]] = {}
        for label, source_variant, adapted_variant in (
            ("albedo", "source_albedo", "adapted_albedo"),
            ("lit", "source_lit", "adapted_lit"),
        ):
            iou = alpha_iou(frames[source_variant][:, :, 3], frames[adapted_variant][:, :, 3])
            _require(iou >= ALPHA_IOU_MINIMUM,
                     f"{tree_id}: {label} silhouette alpha IoU {iou:.8f} is below {ALPHA_IOU_MINIMUM:.3f}.")
            alpha_checks[label] = {
                "source_variant": source_variant,
                "adapted_variant": adapted_variant,
                "iou": iou,
                "minimum_iou": ALPHA_IOU_MINIMUM,
            }

        rgb_difference = _opaque_rgb_difference(frames["source_albedo"], frames["adapted_albedo"])
        # Float32 geometry normalization can change one occluded leaf at a raster edge.
        # Reject broad color drift while reporting (not hiding) those rare large outliers.
        _require(rgb_difference["mean_absolute_rgb_difference_0_255"] <= 0.05
                 and rgb_difference["fraction_pixels_above_two_rgb_levels"] <= 0.001,
                 f"{tree_id}: normalized albedo color drift exceeds MAE 0.05 or 0.1% pixels >2 levels.")
        tile = weighted_box_downsample_rgba(frames["adapted_albedo"])
        padding, bbox = _transparent_padding(tile)
        x, y, width, height = item["atlas_rect_px"]
        atlas[y:y + height, x:x + width] = tile
        analysis_species.append({
            "id": tree_id,
            "silhouette_alpha_iou": alpha_checks,
            "opaque_rgb_difference_source_albedo_vs_adapted_albedo": rgb_difference,
            "atlas_tile_alpha_bbox_px_inclusive": bbox,
            "transparent_padding_px": padding,
            "adapted_albedo_raw_alpha_values": [0, 255],
        })

    empty_slot = atlas[TILE_SIZE:, TILE_SIZE:, :]
    _require(not np.any(empty_slot[:, :, 3]), "Reserved fourth atlas tile must remain transparent.")
    catalog = {
        "format": "openrc-tree-assets v1",
        "atlas": "res://assets/landscape/trees/atlas.png",
        "atlas_size_px": ATLAS_SIZE,
        "tile_size_px": TILE_SIZE,
        "alpha_cutoff": 0.5,
        "species": species,
    }
    analysis = {
        "schema": "openrc-tree-atlas-analysis v1",
        "raw_capture_size_px": RAW_SIZE,
        "atlas_size_px": ATLAS_SIZE,
        "tile_size_px": TILE_SIZE,
        "atlas_variant": "adapted_albedo",
        "silhouette_iou_minimum": ALPHA_IOU_MINIMUM,
        "downsampling": {
            "method": "2x2 BOX; RGB is alpha-weighted in straight-alpha space, alpha is the arithmetic mean.",
            "transparent_rgb": "zero when every input sample in a 2x2 block is transparent",
        },
        "reserved_fourth_slot": "transparent",
        "species": analysis_species,
    }

    out_dir.mkdir(parents=True, exist_ok=True)
    atlas_path = out_dir / "atlas.png"
    catalog_path = out_dir / "catalog.json"
    analysis_path = out_dir / "atlas-analysis.json"
    _save_png(atlas_path, atlas)
    catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    analysis_path.write_text(json.dumps(analysis, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return {"atlas": atlas_path, "catalog": catalog_path, "analysis": analysis_path}


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bake", required=True, type=Path, help="Godot raw bake directory containing bake.json and 12 PNGs")
    parser.add_argument("--out", required=True, type=Path, help="Output directory for atlas.png and catalog/analysis JSON")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    try:
        outputs = process_bake(args.bake, args.out)
    except PipelineError as error:
        print(f"process_atlas: {error}", file=sys.stderr)
        return 1
    print(json.dumps({name: str(path) for name, path in outputs.items()}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
