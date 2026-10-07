#!/usr/bin/env python3
"""Render and verify the shared cloud-density shader contract on the GPU."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
CAPTURE_SCRIPT = Path(__file__).with_name("probe_clouds.gd")
FORMAT = "openrc-cloud-density-probe v1"
SUMMARY_FORMAT = "openrc-cloud-density-probe-review v1"
PANEL_SIZE = 256
PANEL_IDS = (
    "base",
    "plus-64-x",
    "plus-64-y",
    "negative",
    "negative-plus-64-x",
    "negative-plus-64-y",
    "projection-ground",
    "projection-sky",
    "projection-wrong-sign",
    "drift-before-wrap",
    "drift-after-wrap",
    "zero-coverage",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def checked_run(command: list[str], log_path: Path, env: dict[str, str], timeout_s: int = 180) -> None:
    with log_path.open("w") as output:
        try:
            result = subprocess.run(
                ["timeout", "--kill-after=5", str(timeout_s), *command],
                stdout=output,
                stderr=subprocess.STDOUT,
                env=env,
                check=False,
                timeout=timeout_s + 10,
            )
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"engine probe did not stop after {timeout_s + 10}s; inspect {log_path}") from error
    text = re.sub(r"\x1b\[[0-9;]*m", "", log_path.read_text(errors="replace"))
    if result.returncode or re.search(r"^\s*(?:(?:SCRIPT|SHADER)\s+)?ERROR:", text, re.M):
        raise RuntimeError(f"engine probe failed ({result.returncode}); inspect {log_path}")


def read_run(folder: Path, include: Path) -> tuple[dict[str, Any], np.ndarray]:
    metadata_path = folder / "probe.json"
    image_path = folder / "cloud-probe.png"
    if not metadata_path.is_file() or not image_path.is_file():
        raise RuntimeError(f"incomplete probe output in {folder}")
    metadata = json.loads(metadata_path.read_text())
    width = len(PANEL_IDS) * PANEL_SIZE
    if metadata.get("format") != FORMAT or metadata.get("complete") is not True:
        raise RuntimeError(f"{metadata_path}: unexpected or incomplete probe metadata")
    if not str(metadata.get("godot", "")).startswith("4.7.2") or not metadata.get("renderer"):
        raise RuntimeError(f"{metadata_path}: missing pinned Godot 4.7.2 / renderer metadata")
    if metadata.get("panels") != list(PANEL_IDS):
        raise RuntimeError(f"{metadata_path}: panel inventory mismatch")
    if (metadata.get("width"), metadata.get("height"), metadata.get("panel_size")) != (width, PANEL_SIZE, PANEL_SIZE):
        raise RuntimeError(f"{metadata_path}: atlas dimensions mismatch")
    if metadata.get("density") != {
        "seed": 1253,
        "coverage": 0.55,
        "cluster_strength": 0.65,
        "cloud_scale": 6.0,
        "deck_m": 1500.0,
    }:
        raise RuntimeError(f"{metadata_path}: density or projection configuration mismatch")
    if metadata.get("sun_render_xz") != [-0.5, 0.5] or abs(float(metadata.get("sun_render_y", 0.0)) - 2**-0.5) > 1e-7:
        raise RuntimeError(f"{metadata_path}: the registered 225°/45° sun vector changed")
    if sha256_file(image_path) != metadata.get("png_sha256"):
        raise RuntimeError(f"{image_path}: PNG checksum mismatch")
    if sha256_file(include) != metadata.get("cloud_include_sha256"):
        raise RuntimeError(f"{metadata_path}: hash does not match the candidate shared include")
    with Image.open(image_path) as image:
        pixels = np.asarray(image.convert("RGB"), dtype=np.uint8)
    if pixels.shape != (PANEL_SIZE, width, 3):
        raise RuntimeError(f"{image_path}: expected {width}×{PANEL_SIZE} RGB, got {pixels.shape[1]}×{pixels.shape[0]}")
    return metadata, pixels


def panel(pixels: np.ndarray, index: int) -> np.ndarray:
    left = index * PANEL_SIZE
    return pixels[:, left : left + PANEL_SIZE, :]


def comparison(a: np.ndarray, b: np.ndarray) -> dict[str, Any]:
    delta = np.abs(a.astype(np.int16) - b.astype(np.int16))
    max_pixel = delta if delta.ndim == 2 else delta.max(axis=2)
    return {
        "max_byte_delta": int(delta.max()),
        "mean_abs_byte_delta": round(float(delta.mean()), 6),
        "p99_sample_delta": round(float(np.quantile(max_pixel, 0.99)), 3),
        "changed_sample_fraction": round(float(np.count_nonzero(max_pixel)) / float(max_pixel.size), 8),
    }


def verify_atlas(pixels: np.ndarray) -> dict[str, Any]:
    # Green is a GPU-computed assertion bit, checked before the 8-bit density channel.
    sentinels = np.stack([panel(pixels, index)[:, :, 1] for index in range(len(PANEL_IDS))])
    bad_bounds = int(np.count_nonzero(sentinels != 255))
    if bad_bounds:
        raise RuntimeError(f"GPU density range/non-finite sentinel failed in {bad_bounds} pixels")

    density = [panel(pixels, index)[:, :, 0] for index in range(len(PANEL_IDS))]
    base_range = density[0]
    if int(base_range.max()) - int(base_range.min()) < 32 or len(np.unique(base_range)) < 16:
        raise RuntimeError("cloud_density has insufficient nontrivial variation in the rendered base panel")
    if float(base_range.std()) < 12.0:
        raise RuntimeError("cloud_density variation is too narrow in the rendered base panel")
    if int(density[11].max()) > 1:
        raise RuntimeError("zero coverage did not produce a clear density field")

    periodic_pairs = {
        "positive_x_64_cells": (0, 1),
        "positive_y_64_cells": (0, 2),
        "negative_x_64_cells": (3, 4),
        "negative_y_64_cells": (3, 5),
    }
    periodic: dict[str, Any] = {}
    for label, (first, second) in periodic_pairs.items():
        stats = comparison(density[first], density[second])
        if stats["max_byte_delta"] > 2:
            raise RuntimeError(f"64-cell periodicity failed for {label}: {stats}")
        periodic[label] = stats

    projection = comparison(density[6], density[7])
    if projection["max_byte_delta"] > 2:
        raise RuntimeError(f"pilot-origin sky/ground cloud projection disagrees: {projection}")

    wrong_sign = comparison(density[7], density[8])
    if wrong_sign["changed_sample_fraction"] < 0.10 or wrong_sign["mean_abs_byte_delta"] < 2.0:
        raise RuntimeError(f"wrong-sign projection mutation was not detected strongly enough: {wrong_sign}")

    drift = comparison(density[9], density[10])
    if drift["max_byte_delta"] > 8 or drift["p99_sample_delta"] > 4.0:
        raise RuntimeError(f"density changed discontinuously across the 64-cell drift wrap: {drift}")

    return {
        "base_density_byte_range": [int(base_range.min()), int(base_range.max())],
        "base_unique_byte_values": int(len(np.unique(base_range))),
        "base_byte_stddev": round(float(base_range.std()), 3),
        "bounds_sentinel_failures": bad_bounds,
        "zero_coverage_max_byte": int(density[11].max()),
        "periodicity": periodic,
        "projection_ground_vs_sky": projection,
        "wrong_sign_mutation_control": wrong_sign,
        "drift_wrap_continuity": drift,
    }


def prepare_output(out: Path, parser: argparse.ArgumentParser) -> None:
    """Remove only this checker's prior artifacts, and drop stale success first."""
    owned = ("summary.json", "import.log", "repeat-1.log", "repeat-2.log", "repeat-1", "repeat-2")
    if out.exists() and not out.is_dir():
        parser.error(f"output path is not a directory: {out}")
    out.mkdir(parents=True, exist_ok=True)

    summary = out / "summary.json"
    if summary.is_symlink() or summary.is_file():
        summary.unlink()
    elif summary.exists():
        parser.error(f"owned summary path must be a regular file: {summary}")

    unexpected = sorted(entry.name for entry in out.iterdir() if entry.name not in owned)
    if unexpected:
        parser.error(f"output contains unowned entries; preserving them: {unexpected}")

    for name in owned[1:]:
        path = out / name
        if not path.exists() and not path.is_symlink():
            continue
        if path.is_symlink():
            parser.error(f"refusing to remove symlink at owned output path: {path}")
        if path.is_dir():
            shutil.rmtree(path)
        elif path.is_file():
            path.unlink()
        else:
            parser.error(f"unsupported filesystem entry at owned output path: {path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="Godot app directory to test")
    parser.add_argument("--godot", type=Path, required=True, help="pinned Godot executable")
    parser.add_argument("--out", type=Path, required=True, help="evidence directory; owned prior outputs are refreshed")
    args = parser.parse_args()

    app, godot, out = args.app.resolve(), args.godot.resolve(), args.out.resolve()
    prepare_output(out, parser)
    include = app / "render" / "cloud_field.gdshaderinc"
    if not app.is_dir():
        parser.error(f"missing app directory: {app}")
    if not godot.is_file():
        parser.error(f"missing Godot executable: {godot}")
    if not include.is_file():
        parser.error(f"candidate app is missing the shared shader include: {include}")
    if not CAPTURE_SCRIPT.is_file():
        parser.error(f"missing capture script: {CAPTURE_SCRIPT}")
    if shutil.which("xvfb-run") is None:
        parser.error("xvfb-run is required for GPU rendering")
    run_dirs = [out / f"repeat-{repeat}" for repeat in (1, 2)]
    for folder in run_dirs:
        folder.mkdir()

    env = dict(os.environ, LP_NUM_THREADS="1", OPENRC_SCENERY="off", PYTHONDONTWRITEBYTECODE="1")
    render_base = [
        "xvfb-run",
        "-a",
        "-s",
        "-screen 0 1280x720x24",
        str(godot),
        "--path",
        str(app),
        "--rendering-driver",
        "opengl3",
        "--audio-driver",
        "Dummy",
        "--script",
        str(CAPTURE_SCRIPT),
        "--",
    ]
    reports: list[dict[str, Any]] = []
    metrics: list[dict[str, Any]] = []
    for repeat, folder in enumerate(run_dirs, start=1):
        checked_run([*render_base, f"--out={folder}"], out / f"repeat-{repeat}.log", env)
        metadata, pixels = read_run(folder, include)
        reports.append(metadata)
        metrics.append(verify_atlas(pixels))

    if reports[0] != reports[1]:
        raise RuntimeError("repeat probe metadata differs")
    if (run_dirs[0] / "probe.json").read_bytes() != (run_dirs[1] / "probe.json").read_bytes():
        raise RuntimeError("repeat probe metadata is not byte-identical")
    pngs_identical = (run_dirs[0] / "cloud-probe.png").read_bytes() == (run_dirs[1] / "cloud-probe.png").read_bytes()
    if not pngs_identical:
        raise RuntimeError("repeat GPU atlas PNGs are not byte-identical")
    if metrics[0] != metrics[1]:
        raise RuntimeError("repeat probe measurements differ")

    summary = {
        "format": SUMMARY_FORMAT,
        "complete": True,
        "godot": reports[0]["godot"],
        "renderer": reports[0]["renderer"],
        "api": reports[0]["api"],
        "cloud_include_sha256": reports[0]["cloud_include_sha256"],
        "capture": {
            "repeat_count": 2,
            "pngs_byte_identical": pngs_identical,
            "png_sha256": reports[0]["png_sha256"],
            "atlas_dimensions": [len(PANEL_IDS) * PANEL_SIZE, PANEL_SIZE],
            "quantization_tolerance_levels": 2,
        },
        "measurements": metrics[0],
    }
    summary_path = out / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(
        "Cloud density GPU probe passed: 4 periodic comparisons, sky/ground projection, "
        "wrong-sign mutation, drift wrap, bounds and variation; 2 byte-identical atlas PNGs."
    )
    print(f"Evidence: {out}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"CLOUD PROBE FAILED: {error}", file=sys.stderr)
        raise SystemExit(1) from error
