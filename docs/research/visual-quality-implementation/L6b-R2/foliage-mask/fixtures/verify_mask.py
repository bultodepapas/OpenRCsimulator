#!/usr/bin/env python3
"""Verify the retained L6b-R2 source-material mask against the runtime assets."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PureWindowsPath
from typing import Any

import numpy as np
from PIL import Image


REPOSITORY = Path(__file__).resolve().parents[6]
EVIDENCE = Path(__file__).resolve().parents[1]
TILES = {
    "CommonTree_1": (0, 0, 512, 512),
    "CommonTree_3": (512, 0, 512, 512),
    "Pine_1": (0, 512, 512, 512),
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read_rgba(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        if image.format != "PNG" or image.size != (1024, 1024):
            raise ValueError(f"{path} must be a 1024x1024 PNG")
        return np.asarray(image.convert("RGBA"), dtype=np.uint8).copy()


def _resolve_reference(value: str) -> Path:
    path = Path(value)
    return (path if path.is_absolute() else REPOSITORY / path).resolve()


def verify(build_root: Path | None = None) -> dict[str, Any]:
    manifest_path = EVIDENCE / "manifest.json"
    analysis_path = EVIDENCE / "atlas-analysis.json"
    evidence_mask_path = EVIDENCE / "foliage_mask.png"
    evidence_catalog_path = EVIDENCE / "catalog.json"
    runtime_atlas_path = REPOSITORY / "app/assets/landscape/trees/atlas.png"
    runtime_mask_path = REPOSITORY / "app/assets/landscape/trees/foliage_mask.png"
    runtime_catalog_path = REPOSITORY / "app/assets/landscape/trees/catalog.json"
    runtime_import_path = REPOSITORY / "app/assets/landscape/trees/foliage_mask.png.import"
    evidence_import_path = EVIDENCE / "foliage_mask.png.import"
    provenance_path = REPOSITORY / "assets/landscape/PROVENANCE.json"

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    analysis = json.loads(analysis_path.read_text(encoding="utf-8"))
    catalog = json.loads(evidence_catalog_path.read_text(encoding="utf-8"))
    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    manifest_sha = _sha256(manifest_path)
    if provenance.get("bake_manifest_sha256") != manifest_sha:
        raise ValueError("PROVENANCE.json bake_manifest_sha256 does not match the retained full build manifest")

    for relative, expected in provenance["runtime_sha256"].items():
        runtime_path = REPOSITORY / relative
        actual = _sha256(runtime_path)
        if actual != expected:
            raise ValueError(f"Runtime provenance hash mismatch for {relative}: {actual}")
    if evidence_import_path.read_bytes() != runtime_import_path.read_bytes():
        raise ValueError("Retained texture import settings are not byte-identical to runtime settings")
    if "mipmaps/generate=true" not in runtime_import_path.read_text(encoding="utf-8"):
        raise ValueError("Runtime material mask does not generate the atlas-aligned mip chain")
    if evidence_catalog_path.read_bytes() != runtime_catalog_path.read_bytes():
        raise ValueError("Retained catalog is not byte-identical to the runtime catalog")

    evidence_mask = _read_rgba(evidence_mask_path)
    runtime_mask = _read_rgba(runtime_mask_path)
    runtime_atlas = _read_rgba(runtime_atlas_path)
    if not np.array_equal(evidence_mask, runtime_mask):
        raise ValueError("Retained mask is not byte-identical to the runtime mask")
    if not np.array_equal(evidence_mask[:, :, 3], runtime_atlas[:, :, 3]):
        raise ValueError("Mask alpha does not match the runtime atlas alpha byte-for-byte")
    if np.any(evidence_mask[512:, 512:, 3]):
        raise ValueError("Reserved fourth atlas tile is not transparent")

    input_key = "app\\assets\\landscape\\trees\\atlas.png"
    runtime_atlas_sha = _sha256(runtime_atlas_path)
    if manifest["inputs_sha256"].get(input_key) != runtime_atlas_sha:
        raise ValueError("Full build manifest does not pin the current runtime atlas as its alpha reference")
    if _resolve_reference(analysis["runtime_alpha_reference"]) != _resolve_reference(manifest["runtime_alpha_reference"]):
        raise ValueError("Analysis and full build manifest disagree on the runtime alpha reference")

    output_hashes = manifest["outputs_sha256"]
    retained_outputs = {
        "atlas\\atlas-analysis.json": analysis_path,
        "atlas\\catalog.json": evidence_catalog_path,
        "atlas\\foliage_mask.png": evidence_mask_path,
    }
    for relative, path in retained_outputs.items():
        if _sha256(path) != output_hashes.get(relative):
            raise ValueError(f"Retained output does not match the build manifest: {relative}")

    species_results: list[dict[str, Any]] = []
    for item in analysis["species"]:
        tree_id = item["id"]
        if tree_id not in TILES:
            raise ValueError(f"Unknown species in retained analysis: {tree_id}")
        if item.get("runtime_mask_alpha_exactly_matches_runtime_atlas") is not True:
            raise ValueError(f"{tree_id}: runtime alpha reconciliation was not recorded")
        alignment = item["runtime_mask_alpha_alignment_before_edge_reconciliation"]
        nonzero_iou = float(alignment["coverage_iou_nonzero"])
        cutoff_iou = float(alignment["coverage_iou_at_cutoff_0_5"])
        if min(nonzero_iou, cutoff_iou) < 0.995:
            raise ValueError(f"{tree_id}: pre-reconciliation silhouette IoU is below 0.995")
        x, y, width, height = TILES[tree_id]
        tile = evidence_mask[y:y + height, x:x + width]
        visible = tile[:, :, 3] >= 128
        bark_pixels = int(np.logical_and(visible, tile[:, :, 0] < 128).sum())
        foliage_pixels = int(np.logical_and(visible, tile[:, :, 0] >= 128).sum())
        if not bark_pixels or not foliage_pixels:
            raise ValueError(f"{tree_id}: mask does not contain both visible material classes")
        species_catalog = next((entry for entry in catalog["species"] if entry.get("id") == tree_id), None)
        if species_catalog is None:
            raise ValueError(f"{tree_id}: catalog entry is missing")
        if (species_catalog.get("bark_material_name") != item["bark_material_name"]
                or species_catalog.get("foliage_material_name") != item["foliage_material_name"]):
            raise ValueError(f"{tree_id}: source material names differ between catalog and analysis")
        species_results.append({
            "id": tree_id,
            "bark_material_name": item["bark_material_name"],
            "foliage_material_name": item["foliage_material_name"],
            "coverage_iou_nonzero_before_edge_reconciliation": nonzero_iou,
            "coverage_iou_cutoff_0_5_before_edge_reconciliation": cutoff_iou,
            "alpha_differing_pixels_before_edge_reconciliation": int(alignment["alpha_differing_pixels"]),
            "runtime_only_edge_labels_filled": int(item["runtime_only_edge_labels_filled_from_nearest_source_material_id"]),
            "visible_bark_pixels_at_alpha_128": bark_pixels,
            "visible_foliage_pixels_at_alpha_128": foliage_pixels,
        })

    checked_build_outputs = 0
    if build_root is not None:
        for relative, expected in output_hashes.items():
            path = build_root.joinpath(*PureWindowsPath(relative).parts)
            if not path.is_file() or _sha256(path) != expected:
                raise ValueError(f"Full build output hash mismatch: {relative}")
            checked_build_outputs += 1

    return {
        "format": "openrc-tree-foliage-mask-audit v1",
        "runtime_alpha_reference": "app/assets/landscape/trees/atlas.png",
        "runtime_atlas_sha256": runtime_atlas_sha,
        "mask_sha256": _sha256(evidence_mask_path),
        "catalog_sha256": _sha256(evidence_catalog_path),
        "analysis_sha256": _sha256(analysis_path),
        "bake_manifest_sha256": manifest_sha,
        "mask_alpha_matches_runtime_atlas_exactly": True,
        "silhouette_iou_minimum": 0.995,
        "full_build_outputs_checked": checked_build_outputs,
        "runtime_import_mipmaps_enabled": True,
        "species": species_results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-root", type=Path, help="Optional full build directory; verifies every manifest output hash")
    parser.add_argument("--write", type=Path, help="Write the audit report to this JSON file")
    args = parser.parse_args()
    try:
        report = verify(args.build_root.resolve() if args.build_root else None)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))
    rendered = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.write:
        args.write.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
