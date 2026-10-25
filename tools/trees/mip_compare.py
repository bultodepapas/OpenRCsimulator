#!/usr/bin/env python3
"""Run a fixed imported-tree mipmap sweep and compare silhouette coverage."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
CAPTURE_SCRIPT = Path(__file__).with_name("mip_capture.gd")
FORMAT = "openrc-tree-mipmap-comparison v1"
ASSET_IDS = (
    "common_tree_1", "common_tree_2", "common_tree_3", "common_tree_4",
    "pine_1", "pine_2", "pine_3", "bush_common_flowers",
)
DISTANCES_M = (16, 48, 128)
VIEW_SIZES = ((1280, 720), (1920, 1080))
PHASE_COUNT = 8
MASK_DELTA_THRESHOLD = 12
EXPECTED_MIP_TEXTURES = {
    "Bark_NormalTree.png": "2",
    "Bark_NormalTree_Normal.png": "1",
    "Leaves_NormalTree_C.png": "2",
    "Leaf_Pine_C.png": "2",
}
BARK_TEXTURES = {"Bark_NormalTree.png", "Bark_NormalTree_Normal.png"}
MAPLE_ALPHA = "res://assets/landscape/vegetation/models/maple_tree/textures/maple_leaves_basecolor.png"
COVERAGE_OPTIONS = {"mipmaps/generate", "mipmaps/preserve_alpha_test_coverage", "mipmaps/alpha_test_threshold"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def project_app(value: Path) -> Path:
    value = value.resolve()
    if (value / "project.godot").is_file():
        return value
    if (value / "app" / "project.godot").is_file():
        return value / "app"
    raise ValueError(f"project.godot not found under {value}")


def parse_capture(path: Path, *, coverage: bool = False) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"invalid capture manifest {path}: {error}") from error
    if data.get("format") != "openrc-tree-mipmap-sweep v1" or data.get("complete") is not True:
        raise ValueError(f"capture is incomplete or has an unknown format: {path}")
    if data.get("renderer") != "gl_compatibility":
        raise ValueError(f"native Compatibility backend required in {path}")
    expected_keys = None
    if coverage:
        fixture = data.get("fixture", {})
        sizes = fixture.get("view_sizes", [])
        distances = fixture.get("distances_m", [])
        if (fixture.get("asset_ids") != ["maple_tree"]
                or len(distances) < 3 or len(distances) != len(set(distances))
                or any(type(value) not in (int, float) or value <= 0 or not float(value).is_integer() for value in distances)
                or fixture.get("phase_count") != PHASE_COUNT
                or fixture.get("phase_offsets_pixels") != [phase / PHASE_COUNT for phase in range(PHASE_COUNT)]
                or [1920, 1080] not in sizes
                or len(sizes) != len({tuple(size) for size in sizes})
                or any(len(size) != 2 or any(type(value) is not int or value <= 0 for value in size) for size in sizes)
                or fixture.get("msaa") != "4x" or fixture.get("wind_enabled") is not False
                or fixture.get("wind_vector_mps") != [0.0, 0.0, 0.0]
                or fixture.get("wind_clock_seconds") != 0.0 or fixture.get("shadow_enabled") is not False):
            raise ValueError("coverage fixture requires maple_tree, at least three positive integer distances, native 1080p, eight phases, 4x MSAA and frozen wind/shadows")
        expected_keys = {("maple_tree", distance, width, height, phase)
                         for distance in distances for width, height in sizes for phase in range(PHASE_COUNT)}
    expected_count = len(expected_keys) if expected_keys is not None else len(ASSET_IDS) * len(DISTANCES_M) * len(VIEW_SIZES) * PHASE_COUNT
    captures = data.get("captures", [])
    if len(captures) != expected_count:
        raise ValueError(f"{path} has {len(captures)} frames; expected {expected_count}")
    seen: set[tuple[str, int, int, int, int]] = set()
    for record in captures:
        key = capture_key(record)
        if key in seen:
            raise ValueError(f"duplicate capture key in {path}: {key}")
        seen.add(key)
        image_path = (path.parent / str(record.get("filename", ""))).resolve()
        if coverage and not image_path.is_relative_to(path.parent.resolve()):
            raise ValueError(f"raw frame escapes capture directory: {image_path}")
        if not image_path.is_file():
            raise ValueError(f"missing raw frame {image_path}")
        if sha256_file(image_path) != record.get("sha256"):
            raise ValueError(f"raw frame hash mismatch: {image_path}")
        if coverage:
            with Image.open(image_path) as image:
                if image.size != (record["width"], record["height"]):
                    raise ValueError(f"raw frame dimensions disagree with manifest: {image_path}")
    if expected_keys is not None and seen != expected_keys:
        raise ValueError("coverage capture frame keys do not match the complete declared fixture")
    return data


def coverage_config(text: str) -> tuple[dict[str, str], str]:
    """Separate only the three permitted importer changes from all other text."""
    options: dict[str, str] = {}
    unchanged: list[str] = []
    for line in text.splitlines():
        key, separator, value = line.partition("=")
        if separator and key in COVERAGE_OPTIONS:
            if key in options:
                raise ValueError(f"duplicate importer option: {key}")
            options[key] = value.strip()
        elif line.strip():
            unchanged.append(line)
    return options, "\n".join(unchanged)


def validate_coverage_triplet(captures: dict[str, dict[str, Any]]) -> dict[str, Any]:
    baseline = captures["baseline"]
    if not baseline.get("identity") or set(baseline.get("assets", {})) != {"maple_tree"}:
        raise ValueError("coverage capture is missing runtime or maple source identities")
    if MAPLE_ALPHA not in baseline.get("textures", {}):
        raise ValueError("maple leaf alpha texture was not inventoried")
    surfaces = baseline["assets"]["maple_tree"].get("surfaces", [])
    leaves = [surface for surface in surfaces if surface.get("albedo_texture") == MAPLE_ALPHA]
    if not leaves or any(surface.get("alpha_scissor_threshold") != 0.5 for surface in leaves):
        raise ValueError("maple leaf material must retain its authored 0.5 alpha cutoff")
    for field in ("identity", "assets", "fixture", "godot", "renderer", "adapter", "api", "mip_scope"):
        if field not in baseline or any(data.get(field) != baseline[field] for data in captures.values()):
            raise ValueError(f"coverage captures differ or lack {field}")
    if not str(baseline["godot"]).startswith("4.8"):
        raise ValueError("coverage capture requires the adopted Godot 4.8 engine")
    audit: dict[str, Any] = {}
    base_textures = baseline["textures"]
    for label, data in captures.items():
        if set(data.get("textures", {})) != set(base_textures):
            raise ValueError("coverage source texture inventory changed")
        for path, texture in data["textures"].items():
            original = base_textures[path]
            if path != MAPLE_ALPHA:
                if texture != original:
                    raise ValueError(f"unrelated texture/import/decoded data changed: {path}")
                continue
            for field in ("basename", "source_png_sha256", "import_path", "texture_class", "image_size", "image_format", "used_by", "decoded_image_base_level_sha256"):
                if field not in original or texture.get(field) != original[field]:
                    raise ValueError(f"maple leaf source identity changed or missing: {field}")
            allowed_payload_changes = {"import_config_text", "import_sha256", "decoded_image_has_mipmaps",
                                       "decoded_image_mipmap_count", "decoded_image_data_bytes", "decoded_image_data_sha256"}
            if ({key: value for key, value in texture.items() if key not in allowed_payload_changes}
                    != {key: value for key, value in original.items() if key not in allowed_payload_changes}):
                raise ValueError("maple leaf metadata changed outside the importer payload")
            if not re.fullmatch(r"[0-9a-f]{64}", str(texture["source_png_sha256"])):
                raise ValueError("maple leaf source hash is missing or invalid")
            options, remainder = coverage_config(texture.get("import_config_text", ""))
            _, base_remainder = coverage_config(original.get("import_config_text", ""))
            if not remainder or remainder != base_remainder:
                raise ValueError("maple leaf import changed outside the three coverage options")
            expected_mips = label != "baseline"
            expected_preserve = label == "candidate"
            if (options.get("mipmaps/generate") != str(expected_mips).lower()
                    or options.get("mipmaps/preserve_alpha_test_coverage", "false") != str(expected_preserve).lower()
                    or float(options.get("mipmaps/alpha_test_threshold", "0.5")) != 0.5):
                raise ValueError(f"incorrect maple leaf mip/coverage/threshold policy: {label}")
            count = texture.get("decoded_image_mipmap_count", -1)
            expected_count = max(texture["image_size"]).bit_length() - 1 if expected_mips else 0
            if (texture.get("decoded_image_has_mipmaps") is not expected_mips
                    or not isinstance(count, int) or count != expected_count):
                raise ValueError(f"decoded mip chain disagrees with coverage policy: {label}")
            audit[label] = texture
    if audit["ordinary"]["decoded_image_mipmap_count"] != audit["candidate"]["decoded_image_mipmap_count"]:
        raise ValueError("ordinary and coverage mip chain lengths differ")
    base_records = {capture_key(row): row for row in baseline["captures"]}
    for label, data in captures.items():
        rows = {capture_key(row): row for row in data["captures"]}
        if set(rows) != set(base_records):
            raise ValueError("coverage frame keys differ")
        for key, record in rows.items():
            if ({name: value for name, value in record.items() if name not in {"filename", "sha256"}}
                    != {name: value for name, value in base_records[key].items() if name not in {"filename", "sha256"}}):
                raise ValueError(f"camera/subpixel metadata changed: {label}, {key}")
    return audit


def compare_coverage(directories: dict[str, Path], out_dir: Path) -> Path:
    captures = {label: parse_capture(directory / "report.json", coverage=True)
                for label, directory in directories.items()}
    audit = validate_coverage_triplet(captures)
    if out_dir.exists() and any(out_dir.iterdir()):
        raise ValueError(f"output must be new or empty: {out_dir}")
    for directory in directories.values():
        if out_dir.resolve().is_relative_to(directory.resolve()):
            raise ValueError("analysis output must be outside raw capture directories")
    comparisons = {}
    for label in ("ordinary", "candidate"):
        groups = []
        for distance in captures["baseline"]["fixture"]["distances_m"]:
            for width, height in captures["baseline"]["fixture"]["view_sizes"]:
                rows = {name: [row for row in data["captures"]
                               if capture_key(row)[1:4] == (distance, width, height)]
                        for name, data in captures.items()}
                group = analyze_group(rows["baseline"], rows[label], directories["baseline"], directories[label])
                if group["baseline"]["phase_coverage_min_pixels"] == 0 or group["candidate"]["phase_coverage_min_pixels"] == 0:
                    raise ValueError("coverage frame contains no detectable tree silhouette")
                groups.append(group)
        comparisons[label] = groups
    result = {
        "format": "openrc-maple-alpha-coverage-comparison v1", "complete": True,
        "scope": "Native fixed-camera maple near/mid/far subpixel sampling comparison; no frame-time or flight evidence.",
        "limitations": "Coverage and mask transitions describe raster sampling. They do not establish visual acceptance, temporal shimmer reduction, FPS, or pilot readability; review native stills and normal-speed motion separately.",
        "mask": {
            "method": "RGB max-channel distance from top-left background sample",
            "background_corner_tolerance_channel_levels": 2,
            "silhouette_delta_threshold_channel_levels": MASK_DELTA_THRESHOLD,
        },
        "inputs": {label: {"directory": str(directory.resolve()), "report_sha256": sha256_file(directory / "report.json")}
                   for label, directory in directories.items()},
        "fixture": captures["baseline"]["fixture"], "source_identities": captures["baseline"]["identity"],
        "assets": captures["baseline"]["assets"], "texture_import_audit": audit,
        "renderer": {key: captures["baseline"][key] for key in ("godot", "renderer", "adapter", "api")},
        "comparisons_against_unmipped": comparisons,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "comparison.json"
    path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def capture_key(record: dict[str, Any]) -> tuple[str, int, int, int, int]:
    return (
        str(record.get("asset_id", "")),
        int(record.get("distance_m", -1)),
        int(record.get("width", -1)),
        int(record.get("height", -1)),
        int(record.get("phase_index", -1)),
    )


def validate_capture_pair(
    baseline: dict[str, Any], candidate: dict[str, Any], mip_scope: str
) -> dict[str, Any]:
    if mip_scope not in {"all", "bark"}:
        raise ValueError(f"unsupported mip scope: {mip_scope}")
    if baseline.get("mip_scope") != mip_scope or candidate.get("mip_scope") != mip_scope:
        raise ValueError(f"capture manifests do not both report requested mip scope {mip_scope!r}")
    if baseline.get("identity") != candidate.get("identity"):
        raise ValueError("runtime project, renderer script, wind shader, or catalog identity changed between captures")
    if baseline.get("fixture") != candidate.get("fixture"):
        raise ValueError("capture fixture settings differ")
    if baseline.get("assets") != candidate.get("assets"):
        raise ValueError("source asset geometry/material identities differ between captures")
    if set(baseline.get("textures", {})) != set(candidate.get("textures", {})):
        raise ValueError("source texture resource paths differ between captures")

    changed_configs: list[str] = []
    texture_pair: dict[str, dict[str, Any]] = {}
    for resource_path, base in baseline["textures"].items():
        cand = candidate["textures"][resource_path]
        basename = str(base.get("basename", ""))
        if basename != cand.get("basename"):
            raise ValueError(f"texture basename changed for {resource_path}")
        if base.get("source_png_sha256") != cand.get("source_png_sha256"):
            raise ValueError(f"original PNG bytes changed for {basename}")
        if base.get("import_config_text") != cand.get("import_config_text"):
            changed_configs.append(basename)
        texture_pair[basename] = {"baseline": base, "candidate": cand}

    if set(changed_configs) != set(EXPECTED_MIP_TEXTURES):
        raise ValueError(
            "expected exactly the four source-tree mip imports to change; got "
            + ", ".join(sorted(changed_configs))
        )

    active_mip_textures: list[str] = []
    candidate_mipmap_counts: dict[str, int] = {}
    for basename, normal_mode in EXPECTED_MIP_TEXTURES.items():
        pair = texture_pair.get(basename)
        if pair is None:
            raise ValueError(f"required mip texture missing: {basename}")
        base = pair["baseline"]
        cand = pair["candidate"]
        base_config = str(base.get("import_config_text", ""))
        cand_config = str(cand.get("import_config_text", ""))
        if not re.search(r"(?m)^mipmaps/generate=false\s*$", base_config):
            raise ValueError(f"baseline must have mipmaps disabled for {basename}")
        candidate_should_mip = mip_scope == "all" or basename in BARK_TEXTURES
        candidate_mip_setting = "true" if candidate_should_mip else "false"
        if not re.search(rf"(?m)^mipmaps/generate={candidate_mip_setting}\s*$", cand_config):
            raise ValueError(
                f"candidate must set mipmaps/generate={candidate_mip_setting} for {basename} in {mip_scope} scope"
            )
        if not re.search(rf"(?m)^compress/normal_map={normal_mode}\s*$", cand_config):
            raise ValueError(f"candidate normal-map import mode {normal_mode} missing for {basename}")
        if not re.search(r"(?m)^detect_3d/compress_to=0\s*$", cand_config):
            raise ValueError(f"candidate must keep lossless 3D import for {basename}")
        if not re.search(r"(?m)^compress/mode=0\s*$", cand_config):
            raise ValueError(f"candidate must use lossless import for {basename}")
        if base.get("decoded_image_has_mipmaps") or int(base.get("decoded_image_mipmap_count", -1)) != 0:
            raise ValueError(f"baseline decoded image unexpectedly has mips: {basename}")
        candidate_mipmap_count = int(cand.get("decoded_image_mipmap_count", 0))
        candidate_has_mips = bool(cand.get("decoded_image_has_mipmaps"))
        candidate_mipmap_counts[basename] = candidate_mipmap_count
        if candidate_should_mip:
            if not candidate_has_mips or candidate_mipmap_count <= 0:
                raise ValueError(f"candidate decoded image has no mip chain: {basename}")
            active_mip_textures.append(basename)
        elif candidate_has_mips or candidate_mipmap_count != 0:
            raise ValueError(f"bark-only candidate unexpectedly has leaf mip chain: {basename}")

    flower = texture_pair.get("Flowers.png")
    if flower is None:
        raise ValueError("shared flowering shrub texture was not inventoried")
    if flower["baseline"].get("import_config_text") != flower["candidate"].get("import_config_text"):
        raise ValueError("Flowers.png import changed outside the four mip candidate textures")
    if flower["baseline"].get("decoded_image_data_sha256") != flower["candidate"].get("decoded_image_data_sha256"):
        raise ValueError("unmodified Flowers.png decoded image changed")

    return {
        "changed_import_configs": sorted(changed_configs),
        "mip_scope": mip_scope,
        "active_mipmap_textures": sorted(active_mip_textures),
        "source_png_hashes_match": True,
        "candidate_mipmap_counts": candidate_mipmap_counts,
        "texture_inventory": texture_pair,
    }


def read_mask(path: Path) -> tuple[np.ndarray, list[int]]:
    with Image.open(path) as image:
        rgb = np.asarray(image.convert("RGB"), dtype=np.int16)
    if rgb.ndim != 3 or rgb.shape[2] != 3:
        raise ValueError(f"not an RGB image: {path}")
    background = rgb[0, 0].copy()
    corners = (rgb[0, -1], rgb[-1, 0], rgb[-1, -1])
    if any(int(np.max(np.abs(corner - background))) > 2 for corner in corners):
        raise ValueError(f"background is not uniform in all corners: {path}")
    mask = np.max(np.abs(rgb - background), axis=2) > MASK_DELTA_THRESHOLD
    return mask, [int(channel) for channel in background]


def coverage_summary(masks: list[np.ndarray]) -> dict[str, float | int]:
    areas = np.asarray([int(mask.sum()) for mask in masks], dtype=np.float64)
    pixel_count = int(masks[0].size)
    transitions: list[float] = []
    for left, right in zip(masks, masks[1:]):
        union_count = int(np.logical_or(left, right).sum())
        change_count = int(np.logical_xor(left, right).sum())
        transitions.append(change_count / max(union_count, 1))
    mean_area = float(areas.mean())
    return {
        "frames": len(masks),
        "pixel_count": pixel_count,
        "mean_area_pixels": mean_area,
        "mean_coverage_fraction": mean_area / pixel_count,
        "mean_coverage_percent": mean_area * 100.0 / pixel_count,
        "phase_coverage_std_pixels": float(areas.std(ddof=0)),
        "phase_coverage_std_percent_points": float(areas.std(ddof=0) * 100.0 / pixel_count),
        "phase_coverage_min_pixels": int(areas.min()),
        "phase_coverage_max_pixels": int(areas.max()),
        "adjacent_phase_mask_transition_mean": float(np.mean(transitions)) if transitions else 0.0,
        "adjacent_phase_mask_transition_max": float(np.max(transitions)) if transitions else 0.0,
    }


def analyze_group(
    base_records: list[dict[str, Any]],
    candidate_records: list[dict[str, Any]],
    baseline_dir: Path,
    candidate_dir: Path,
) -> dict[str, Any]:
    base_by_key = {capture_key(record): record for record in base_records}
    cand_by_key = {capture_key(record): record for record in candidate_records}
    if set(base_by_key) != set(cand_by_key):
        raise ValueError("baseline and candidate have different frame keys")

    ordered_keys = sorted(base_by_key, key=lambda key: key[4])
    base_masks: list[np.ndarray] = []
    cand_masks: list[np.ndarray] = []
    phase_rows: list[dict[str, Any]] = []
    for key in ordered_keys:
        base_record = base_by_key[key]
        cand_record = cand_by_key[key]
        base_mask, base_bg = read_mask(baseline_dir / str(base_record["filename"]))
        cand_mask, cand_bg = read_mask(candidate_dir / str(cand_record["filename"]))
        if base_mask.shape != cand_mask.shape:
            raise ValueError(f"frame dimensions differ for {key}")
        if base_bg != cand_bg:
            raise ValueError(f"background color differs for {key}: {base_bg} vs {cand_bg}")
        base_masks.append(base_mask)
        cand_masks.append(cand_mask)
        union_count = int(np.logical_or(base_mask, cand_mask).sum())
        intersection_count = int(np.logical_and(base_mask, cand_mask).sum())
        phase_rows.append({
            "phase_index": key[4],
            "baseline_area_pixels": int(base_mask.sum()),
            "candidate_area_pixels": int(cand_mask.sum()),
            "coverage_delta_pixels": int(cand_mask.sum()) - int(base_mask.sum()),
            "coverage_delta_percent_points": (int(cand_mask.sum()) - int(base_mask.sum())) * 100.0 / base_mask.size,
            "mask_iou": intersection_count / max(union_count, 1),
        })

    baseline_stats = coverage_summary(base_masks)
    candidate_stats = coverage_summary(cand_masks)
    baseline_iou = [row["mask_iou"] for row in phase_rows]
    return {
        "asset_id": ordered_keys[0][0],
        "distance_m": ordered_keys[0][1],
        "width": ordered_keys[0][2],
        "height": ordered_keys[0][3],
        "baseline": baseline_stats,
        "candidate": candidate_stats,
        "difference": {
            "mean_coverage_delta_pixels": candidate_stats["mean_area_pixels"] - baseline_stats["mean_area_pixels"],
            "mean_coverage_delta_percent_points": candidate_stats["mean_coverage_percent"] - baseline_stats["mean_coverage_percent"],
            "phase_coverage_std_delta_percent_points": candidate_stats["phase_coverage_std_percent_points"] - baseline_stats["phase_coverage_std_percent_points"],
            "adjacent_phase_transition_delta": candidate_stats["adjacent_phase_mask_transition_mean"] - baseline_stats["adjacent_phase_mask_transition_mean"],
            "mean_mask_iou": float(np.mean(baseline_iou)),
        },
        "phases": phase_rows,
    }


def run_capture(
    godot: Path,
    app: Path,
    output: Path,
    log_path: Path,
    timeout_s: int,
    mip_scope: str,
) -> None:
    command = [
        str(godot.resolve()),
        "--path", str(app.resolve()),
        "--rendering-driver", "opengl3",
        "--audio-driver", "Dummy",
        "--script", str(CAPTURE_SCRIPT.resolve()),
        "--", f"--out={output.resolve()}", f"--mip-scope={mip_scope}",
    ]
    with log_path.open("w", encoding="utf-8", newline="\n") as log:
        log.write("COMMAND: " + json.dumps(command) + "\n")
        log.flush()
        try:
            result = subprocess.run(
                command,
                cwd=ROOT,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=timeout_s,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"Godot capture timed out after {timeout_s}s; see {log_path}") from error
    if result.returncode != 0:
        raise RuntimeError(f"Godot capture exited {result.returncode}; see {log_path}")
    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    bad_lines = [line for line in log_text.splitlines() if re.search(r"\b(ERROR|SCRIPT ERROR):", line)]
    if bad_lines:
        raise RuntimeError(f"Godot emitted errors; see {log_path}: " + " | ".join(bad_lines[:4]))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, help="native pinned Godot executable")
    parser.add_argument("--baseline", type=Path, help="frozen no-mipmap app or parent directory")
    parser.add_argument("--candidate", type=Path, help="frozen explicit-mipmap app or parent directory")
    parser.add_argument("--coverage-baseline", type=Path, help="existing unmipped maple capture directory")
    parser.add_argument("--coverage-ordinary", type=Path, help="existing ordinary-mip maple capture directory")
    parser.add_argument("--coverage-candidate", type=Path, help="existing coverage-preserved maple capture directory")
    parser.add_argument("--out", type=Path, required=True, help="new paired-capture directory")
    parser.add_argument(
        "--mip-scope", choices=("all", "bark"), default="all",
        help="require mip chains on all four tree maps, or only bark albedo/normal maps",
    )
    parser.add_argument("--timeout-s", type=int, default=900, help="per-project native capture timeout")
    args = parser.parse_args()
    coverage_paths = (args.coverage_baseline, args.coverage_ordinary, args.coverage_candidate)
    if any(path is not None for path in coverage_paths):
        if not all(path is not None for path in coverage_paths):
            parser.error("coverage analysis requires --coverage-baseline, --coverage-ordinary and --coverage-candidate")
        if any(path is not None for path in (args.godot, args.baseline, args.candidate)):
            parser.error("coverage analysis cannot be combined with native capture arguments")
    elif not all(path is not None for path in (args.godot, args.baseline, args.candidate)):
        parser.error("native capture requires --godot, --baseline and --candidate")
    return args


def main() -> int:
    args = parse_args()
    try:
        if args.coverage_baseline is not None:
            path = compare_coverage({"baseline": args.coverage_baseline, "ordinary": args.coverage_ordinary,
                                     "candidate": args.coverage_candidate}, args.out)
            print(f"COVERAGE COMPARISON COMPLETE: {path}", flush=True)
            return 0
        godot = args.godot.resolve(strict=True)
        if not godot.is_file():
            raise ValueError(f"Godot executable is not a file: {godot}")
        if not CAPTURE_SCRIPT.is_file():
            raise ValueError(f"capture fixture missing: {CAPTURE_SCRIPT}")
        baseline_app = project_app(args.baseline)
        candidate_app = project_app(args.candidate)
        out_dir = args.out.resolve()
        if out_dir.exists() and any(out_dir.iterdir()):
            raise ValueError(f"output must be new or empty: {out_dir}")
        out_dir.mkdir(parents=True, exist_ok=True)
        baseline_dir = out_dir / "baseline"
        candidate_dir = out_dir / "candidate"
        baseline_log = out_dir / "baseline.log"
        candidate_log = out_dir / "candidate.log"
        if args.timeout_s <= 0:
            raise ValueError("--timeout-s must be positive")

        print(f"Capturing baseline Compatibility frames: {baseline_app}", flush=True)
        run_capture(godot, baseline_app, baseline_dir, baseline_log, args.timeout_s, args.mip_scope)
        print(f"Capturing mip candidate Compatibility frames: {candidate_app}", flush=True)
        run_capture(godot, candidate_app, candidate_dir, candidate_log, args.timeout_s, args.mip_scope)

        baseline = parse_capture(baseline_dir / "report.json")
        candidate = parse_capture(candidate_dir / "report.json")
        texture_info = validate_capture_pair(baseline, candidate, args.mip_scope)
        base_by_key = {capture_key(record): record for record in baseline["captures"]}
        candidate_by_key = {capture_key(record): record for record in candidate["captures"]}
        if set(base_by_key) != set(candidate_by_key):
            raise ValueError("baseline and candidate frame keys differ")

        groups: list[dict[str, Any]] = []
        for asset_id in ASSET_IDS:
            for distance in DISTANCES_M:
                for width, height in VIEW_SIZES:
                    keys = [
                        (asset_id, distance, width, height, phase)
                        for phase in range(PHASE_COUNT)
                    ]
                    groups.append(analyze_group(
                        [base_by_key[key] for key in keys],
                        [candidate_by_key[key] for key in keys],
                        baseline_dir,
                        candidate_dir,
                    ))

        result = {
            "format": FORMAT,
            "complete": True,
            "mip_scope": args.mip_scope,
            "scope": "Fixed imported source geometry/materials, native Compatibility, 4x MSAA, fixed lighting, wind disabled, matched camera and subpixel offsets.",
            "mask": {
                "method": "RGB max-channel distance from top-left background sample",
                "background_corner_tolerance_channel_levels": 2,
                "silhouette_delta_threshold_channel_levels": MASK_DELTA_THRESHOLD,
                "limitations": "This is an alpha-silhouette/coverage diagnostic. Camera shifts move real edges; adjacent mask transitions are only a subpixel sampling-instability proxy and do not directly measure shimmer, flight readability, or visual quality.",
            },
            "paired_inputs": {
                "godot_executable": str(godot),
                "godot_executable_sha256": sha256_file(godot),
                "baseline_app": str(baseline_app),
                "candidate_app": str(candidate_app),
                "baseline_adapter": baseline.get("adapter"),
                "candidate_adapter": candidate.get("adapter"),
                "baseline_api": baseline.get("api"),
                "candidate_api": candidate.get("api"),
                "baseline_log": baseline_log.name,
                "candidate_log": candidate_log.name,
            },
            "source_identities": baseline["identity"],
            "assets": baseline["assets"],
            "texture_import_audit": {
                "mip_scope": texture_info["mip_scope"],
                "active_mipmap_textures": texture_info["active_mipmap_textures"],
                "changed_import_configs": texture_info["changed_import_configs"],
                "source_png_hashes_match": texture_info["source_png_hashes_match"],
                "candidate_mipmap_counts": texture_info["candidate_mipmap_counts"],
                "textures": texture_info["texture_inventory"],
            },
            "groups": groups,
            "raw_frame_count_per_project": len(baseline["captures"]),
        }
        report_path = out_dir / "comparison.json"
        report_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"MIP COMPARISON COMPLETE: {report_path}", flush=True)
        return 0
    except (OSError, ValueError, RuntimeError, KeyError, TypeError) as error:
        print(f"mip_compare: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
