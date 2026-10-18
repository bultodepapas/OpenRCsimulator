from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(r"C:/DEVELOPMENT/OpenRCsimulator/tmp/tree-mips")
SWEEP = ROOT / "bark-sweep"
REFERENCE = ROOT / "supersampled-reference"
OUTPUT = ROOT / "bark-sweep" / "reference-comparison.json"
THRESHOLD = 12
CASES = (("common_tree_3", 1280, 720, 4), ("common_tree_3", 1920, 1080, 2),
         ("bush_common_flowers", 1280, 720, 4), ("bush_common_flowers", 1920, 1080, 2))
FIXTURE = ROOT / "draft" / "mip_supersample_capture.gd"


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_rgb(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        return np.asarray(image.convert("RGB"), dtype=np.uint8)


def background(rgb: np.ndarray) -> np.ndarray:
    color = rgb[0, 0].astype(np.int16)
    for corner in (rgb[0, -1], rgb[-1, 0], rgb[-1, -1]):
        if int(np.max(np.abs(corner.astype(np.int16) - color))) > 2:
            raise ValueError("nonuniform capture background")
    return color


def mask_for(rgb: np.ndarray, bg: np.ndarray) -> np.ndarray:
    return np.max(np.abs(rgb.astype(np.int16) - bg), axis=2) > THRESHOLD


def outline_metrics(mask: np.ndarray) -> dict[str, float | int | list[int]]:
    rows = np.flatnonzero(mask.any(axis=1))
    left = np.full(mask.shape[0], -1, dtype=np.int32)
    right = np.full(mask.shape[0], -1, dtype=np.int32)
    for y in rows:
        xs = np.flatnonzero(mask[y])
        left[y] = xs[0]
        right[y] = xs[-1]
    envelope = int(sum(int(right[y] - left[y] + 1) for y in rows))
    occupied = int(mask.sum())
    return {
        "row_count": int(rows.size),
        "occupied_pixels": occupied,
        "row_envelope_pixels": envelope,
        "interior_empty_pixels": envelope - occupied,
        "interior_fill_fraction": occupied / max(envelope, 1),
        "interior_empty_fraction": (envelope - occupied) / max(envelope, 1),
        "left_edges": left.tolist(),
        "right_edges": right.tolist(),
    }


def edge_error(mask: np.ndarray, reference_mask: np.ndarray) -> dict[str, float | int]:
    actual = outline_metrics(mask)
    expected = outline_metrics(reference_mask)
    actual_left = np.asarray(actual["left_edges"])
    actual_right = np.asarray(actual["right_edges"])
    ref_left = np.asarray(expected["left_edges"])
    ref_right = np.asarray(expected["right_edges"])
    actual_rows = actual_left >= 0
    reference_rows = ref_left >= 0
    common = actual_rows & reference_rows
    edge_errors = np.concatenate((np.abs(actual_left[common] - ref_left[common]),
                                  np.abs(actual_right[common] - ref_right[common]))).astype(np.float64)
    return {
        "shared_outline_rows": int(common.sum()),
        "row_presence_mismatches": int(np.count_nonzero(actual_rows != reference_rows)),
        "mean_outline_edge_error_px": float(edge_errors.mean()) if edge_errors.size else 0.0,
        "p95_outline_edge_error_px": float(np.percentile(edge_errors, 95)) if edge_errors.size else 0.0,
        "max_outline_edge_error_px": float(edge_errors.max()) if edge_errors.size else 0.0,
        "envelope_area_pixels": int(actual["row_envelope_pixels"]),
        "envelope_area_delta_pixels": int(actual["row_envelope_pixels"]) - int(expected["row_envelope_pixels"]),
        "interior_fill_fraction": float(actual["interior_fill_fraction"]),
        "interior_fill_delta_vs_reference": float(actual["interior_fill_fraction"]) - float(expected["interior_fill_fraction"]),
    }


def compare_case(asset: str, width: int, height: int, scale: int) -> dict:
    hi_path = REFERENCE / f"{asset}__d128__{width * scale}x{height * scale}__p00.png"
    hi_rgb = load_rgb(hi_path)
    hi_bg = background(hi_rgb)
    hi_mask = mask_for(hi_rgb, hi_bg)
    if hi_rgb.shape[1] != width * scale or hi_rgb.shape[0] != height * scale:
        raise ValueError(f"unexpected supersample dimensions: {hi_path}")

    ref_rgb = np.asarray(Image.fromarray(hi_rgb).resize((width, height), Image.Resampling.BOX), dtype=np.uint8)
    ref_bg = background(ref_rgb)
    ref_mask = mask_for(ref_rgb, ref_bg)
    soft = hi_mask.reshape(height, scale, width, scale).mean(axis=(1, 3), dtype=np.float32)
    if not np.allclose(ref_bg, hi_bg, atol=2):
        raise ValueError("background changed while downsampling")

    results = {}
    masks = {}
    rgbs = {}
    for treatment in ("baseline", "candidate"):
        path = SWEEP / treatment / f"{asset}__d128__{width}x{height}__p00.png"
        rgb = load_rgb(path)
        bg = background(rgb)
        if not np.allclose(bg, ref_bg, atol=2):
            raise ValueError(f"background mismatch for {path}: {bg.tolist()} vs {ref_bg.tolist()}")
        mask = mask_for(rgb, bg)
        masks[treatment] = mask
        rgbs[treatment] = rgb

    union = (masks["baseline"] | masks["candidate"] | ref_mask | (soft > 0.0))
    soft_area = float(soft.sum())
    for treatment in ("baseline", "candidate"):
        rgb = rgbs[treatment]
        mask = masks[treatment]
        raw_delta = np.abs(rgb.astype(np.int16) - ref_rgb.astype(np.int16))
        union_error = raw_delta[union]
        soft_error = np.abs(mask.astype(np.float32) - soft)
        actual_outline = outline_metrics(mask)
        results[treatment] = {
            "binary_coverage_pixels": int(mask.sum()),
            "binary_coverage_fraction": float(mask.mean()),
            "coverage_bias_vs_supersampled_area_percent": (float(mask.sum()) - soft_area) * 100.0 / max(soft_area, 1.0),
            "soft_coverage_mae": float(soft_error.mean()),
            "soft_coverage_mae_over_union": float(soft_error[union].mean()) if union.any() else 0.0,
            "rgb_mae_over_union_channel_levels": float(union_error.mean()) if union_error.size else 0.0,
            "rgb_rmse_over_union_channel_levels": float(np.sqrt(np.mean(np.square(union_error, dtype=np.float64)))) if union_error.size else 0.0,
            "rgb_p95_absolute_error_channel_levels": float(np.percentile(union_error, 95)) if union_error.size else 0.0,
            "mask_iou_vs_box_rgb_reference": int(np.logical_and(mask, ref_mask).sum()) / max(int(np.logical_or(mask, ref_mask).sum()), 1),
            "outline_vs_box_rgb_reference": edge_error(mask, ref_mask),
            "interior_fill_fraction": actual_outline["interior_fill_fraction"],
            "interior_empty_fraction": actual_outline["interior_empty_fraction"],
        }
    results["reference"] = {
        "source_frame": hi_path.name,
        "supersample_scale": scale,
        "rgb_box_downsampled_to": [width, height],
        "supersampled_binary_area_in_native_pixels": soft_area,
        "box_rgb_binary_coverage_pixels": int(ref_mask.sum()),
        "soft_coverage_pixel_count": int(np.count_nonzero((soft > 0.0) & (soft < 1.0))),
        "mask_threshold_channel_levels": THRESHOLD,
        "source_treatment": "No-mipmap baseline rendered directly at supersampled resolution; binary source mask then averaged for soft coverage comparison.",
    }
    results["candidate_minus_baseline"] = {
        "binary_coverage_pixels": results["candidate"]["binary_coverage_pixels"] - results["baseline"]["binary_coverage_pixels"],
        "soft_coverage_mae": results["candidate"]["soft_coverage_mae"] - results["baseline"]["soft_coverage_mae"],
        "rgb_mae_over_union_channel_levels": results["candidate"]["rgb_mae_over_union_channel_levels"] - results["baseline"]["rgb_mae_over_union_channel_levels"],
        "mean_outline_edge_error_px": results["candidate"]["outline_vs_box_rgb_reference"]["mean_outline_edge_error_px"] - results["baseline"]["outline_vs_box_rgb_reference"]["mean_outline_edge_error_px"],
        "interior_fill_fraction": results["candidate"]["interior_fill_fraction"] - results["baseline"]["interior_fill_fraction"],
    }
    return {"asset_id": asset, "width": width, "height": height, "distance_m": 128, "phase_index": 0, **results}


def main() -> None:
    sweep_base = json.loads((SWEEP / "baseline" / "report.json").read_text(encoding="utf-8"))
    sweep_candidate = json.loads((SWEEP / "candidate" / "report.json").read_text(encoding="utf-8"))
    ref = json.loads((REFERENCE / "report.json").read_text(encoding="utf-8"))
    if sweep_base["identity"] != sweep_candidate["identity"] or sweep_base["assets"] != sweep_candidate["assets"]:
        raise ValueError("baseline/candidate source identities differ")
    if ref["identity"] != sweep_base["identity"]:
        raise ValueError("supersampled reference is not from the frozen baseline")
    if ref["fixture"]["asset_ids"] != ["common_tree_3", "bush_common_flowers"]:
        raise ValueError("reference source-ID scope changed")
    report = {
        "format": "openrc-tree-mipmap-supersample-check v1",
        "complete": True,
        "capture_identity": ref["identity"],
        "fixture_snapshot": {
            "path": str(FIXTURE),
            "sha256": sha256_file(FIXTURE),
            "godot_version": ref["godot"],
            "renderer": ref["renderer"],
            "adapter": ref["adapter"],
            "api": ref["api"],
            "native_reference_count": len(ref["captures"]),
            "native_reference_png_sha256": {item["filename"]: item["sha256"] for item in ref["captures"]},
        },
        "scope": "Two highest-risk distant cutout sources at identical phase/distance/FOV. Four no-mipmap baseline renders were taken at 4x720p and 2x1080p, then BOX-downsampled to native dimensions.",
        "reference_limitations": "A finite 4x/2x raster reference is an approximation, not analytic ground truth. RGB BOX downsampling and a thresholded background mask do not recover a shader alpha channel; soft coverage is derived from the high-resolution binary mask.",
        "outline_metric": "Per scanline, take the leftmost/rightmost foreground pixel and sum those row spans. Interior fill is foreground pixels divided by that envelope area; it is a row-span proxy, not a connected-component or topological hole count. Branch gaps also count as interior empty area.",
        "analysis_script": {"path": str(Path(__file__)), "sha256": sha256_file(Path(__file__))},
        "cases": [compare_case(*case) for case in CASES],
    }
    OUTPUT.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(OUTPUT)


if __name__ == "__main__":
    main()
