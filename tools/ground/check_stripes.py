#!/usr/bin/env python3
"""L9c-R1: compare stripe-only camera motion with a supersampled reference."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess

import numpy as np
from PIL import Image

from check_surfaces import (APP_DEFAULT, CAPTURE_SCRIPT, FORMAT, checked_run,
                            finite_tree, import_mutation_project, make_mutation_app,
                            reject_constant, sha256)

SIZE = (640, 64)
VIEWS = {"runway_oblique_100", "runway_oblique_300", "runway_threshold"}
SHIFTS = (0.0, 0.5)
# Engineering separation margin against measured 8x/16x reference disagreement;
# this is not a human visibility threshold or a bound on all sampling error.
REFERENCE_MARGIN = 2.0


def linear_rgb(pixels: np.ndarray) -> np.ndarray:
    values = pixels.astype(np.float32) / 255.0
    return np.where(values <= 0.04045, values / 12.92, ((values + 0.055) / 1.055) ** 2.4)


def rms(values: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(values.astype(np.float64)))))


def load(folder: Path, scale: int) -> tuple[dict, dict]:
    manifest = json.loads((folder / "capture.json").read_text(), parse_constant=reject_constant)
    finite_tree(manifest)
    expected = {"format": FORMAT, "renderer_method": "gl_compatibility", "renderer_driver": "opengl3",
                "viewport": [SIZE[0] * scale, SIZE[1] * scale], "reference_scale": scale,
                "base_viewport": [1280, 720], "measurement_viewport": list(SIZE), "ablation": "stripe_amp", "shader_time_s": 0.0,
                "surfaces_consolidated": True}
    for key, value in expected.items():
        if manifest.get(key) != value:
            raise RuntimeError(f"{folder.name}: incorrect {key}: {manifest.get(key)!r}")
    if not 0 < manifest.get("stripe_amplitude", 0) <= 1:
        raise RuntimeError("missing positive stripe amplitude")
    captures = {}
    for view in manifest["views"]:
        view_id = view["id"]
        if view_id not in VIEWS:
            raise RuntimeError(f"unexpected view: {view_id}")
        for capture in view["captures"]:
            key = (view_id, capture["shift_pixels"], capture["state"])
            if key in captures:
                raise RuntimeError(f"duplicate capture: {key}")
            path = folder / capture["image"]
            if path.parent != folder or sha256(path) != capture["sha256"]:
                raise RuntimeError(f"invalid image path or hash: {path}")
            with Image.open(path) as image:
                if image.size != (SIZE[0] * scale, SIZE[1] * scale):
                    raise RuntimeError(f"wrong image dimensions: {path}")
                pixels = linear_rgb(np.asarray(image.convert("RGB")))
            pixels = pixels.reshape(SIZE[1], scale, SIZE[0], scale, 3).mean(axis=(1, 3))
            captures[key] = (pixels, capture)
    if set(captures) != {(view, shift, state) for view in VIEWS for shift in SHIFTS for state in ("on", "off")}:
        raise RuntimeError("incomplete stripe capture set")
    residuals = {}
    for view in VIEWS:
        for shift in SHIFTS:
            on, metadata = captures[view, shift, "on"]
            off, off_metadata = captures[view, shift, "off"]
            for key in ("eye_render", "target_render", "projected_runway", "projected_runway_core", "draw_calls", "primitives", "objects"):
                if metadata[key] != off_metadata[key]:
                    raise RuntimeError(f"stripe ablation changed {key}")
            residuals[view, shift] = (on - off, metadata)
    return manifest, residuals


def mask_for(records: dict, view: str) -> np.ndarray:
    mask = np.ones((SIZE[1], SIZE[0]), dtype=bool)
    y, x = np.mgrid[:SIZE[1], :SIZE[0]] + 0.5
    for shift in SHIFTS:
        polygon = np.asarray(records[view, shift][1]["projected_runway_core"])
        if polygon.shape != (4, 2):
            raise RuntimeError("missing one-metre-inset runway projection")
        sides = []
        for start, end in zip(polygon, np.roll(polygon, -1, axis=0)):
            sides.append((end[0] - start[0]) * (y - start[1]) - (end[1] - start[1]) * (x - start[0]))
        # Pixel centres inside the physical inset quad; no rounded raster-mask expansion.
        mask &= np.all(np.asarray(sides) >= 0, axis=0) | np.all(np.asarray(sides) <= 0, axis=0)
    if np.count_nonzero(mask) < 16:
        raise RuntimeError(f"{view}: fewer than 16 interior pixels in the fixed mask")
    return mask


def errors(candidate: list[np.ndarray], reference: list[np.ndarray], mask: np.ndarray) -> dict:
    error = [candidate[i] - reference[i] for i in range(2)]
    return {"spatial_rms_linear_rgb": rms(np.stack(error)[:, mask]),
            "temporal_rms_linear_rgb": rms((error[1] - error[0])[mask])}


def assess(filtered: dict, raw: dict, reference8: dict, reference16: dict) -> dict:
    report = {}
    for view in sorted(VIEWS):
        mask = mask_for(filtered, view)
        arrays = lambda records: [records[view, shift][0] for shift in SHIFTS]
        ref = arrays(reference16)
        measured = {name: errors(arrays(records), ref, mask) for name, records in
                    (("filtered", filtered), ("raw", raw), ("reference_disagreement", reference8))}
        measured["no_stripes"] = errors([np.zeros_like(item) for item in ref], ref, mask)
        measured["mask_pixels"] = int(np.count_nonzero(mask))
        for metric in (() if view == "runway_threshold" else ("spatial_rms_linear_rgb", "temporal_rms_linear_rgb")):
            f, r, uncertainty = [measured[name][metric] for name in ("filtered", "raw", "reference_disagreement")]
            if not f + REFERENCE_MARGIN * uncertainty < r:
                raise RuntimeError(f"{view}/{metric}: filter improvement does not exceed reference disagreement "
                                   f"(filtered={f:.6g}, raw={r:.6g}, reference={uncertainty:.6g})")
        # Preserve visible nearby stripes: erasing all detail must not pass as a good filter.
        if view == "runway_threshold":
            metric = "spatial_rms_linear_rgb"
            if not measured["filtered"][metric] + REFERENCE_MARGIN * measured["reference_disagreement"][metric] < measured["no_stripes"][metric]:
                raise RuntimeError("nearby stripes were erased instead of filtered")
        report[view] = measured
    return report


def verify_projection(native: dict, other: dict, scale: int) -> None:
    for key, (_, metadata) in native.items():
        candidate = other[key][1]
        for name in ("eye_render", "target_render", "metres_per_pixel", "shift_axis", "crop_origin"):
            if metadata[name] != candidate[name]:
                raise RuntimeError(f"camera mismatch across references: {key}/{name}")
        for name in ("projected_runway", "projected_runway_core"):
            if not np.allclose(np.asarray(metadata[name]), np.asarray(candidate[name]) / scale, rtol=0, atol=0.002):
                raise RuntimeError(f"scaled projection mismatch: {key}/{name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=APP_DEFAULT)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True, help="new or empty directory")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    app, godot, out = args.app.resolve(), args.godot.resolve(), args.out.resolve()
    if not (app / "project.godot").is_file() or not godot.is_file() or args.timeout <= 0:
        parser.error("valid app, Godot binary and positive timeout required")
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        parser.error("refusing stale evidence: --out must be new or empty")
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, LP_NUM_THREADS="1", OPENRC_SCENERY="off", OPENRC_SCENERY_AUDIO="off",
               OPENRC_SCENERY_BIRDS="off", PYTHONDONTWRITEBYTECODE="1")
    commands = {}
    raw_app = out / "raw-app"
    make_mutation_app(app, raw_app, "unfiltered")
    commands["import"] = import_mutation_project(godot, raw_app, out / "import.log", env, args.timeout)
    manifests, records = {}, {}
    for name, project, scale in (("filtered", app, 1), ("repeat", app, 1), ("raw", raw_app, 1),
                                  ("reference8", raw_app, 8), ("reference16", raw_app, 16)):
        print(f"L9c-R1: rendering {name} ({scale}x)", flush=True)
        size = (SIZE[0] * scale, SIZE[1] * scale)
        command = ["xvfb-run", "-a", "-s", f"-screen 0 {size[0]}x{size[1]}x24", str(godot),
                   "--path", str(project), "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
                   "--resolution", f"{size[0]}x{size[1]}", "--script", str(CAPTURE_SCRIPT), "--",
                   f"--out={out / name}", "--fixture=stripe-reference", f"--scale={scale}"]
        commands[name] = command
        checked_run(command, out / f"{name}.log", env, args.timeout)
        manifests[name], records[name] = load(out / name, scale)
        if name != "filtered":
            verify_projection(records["filtered"], records[name], scale)
            if manifests[name]["stripe_amplitude"] != manifests["filtered"]["stripe_amplitude"]:
                raise RuntimeError("stripe amplitude differs between runs")
    if manifests["filtered"] != manifests["repeat"]:
        raise RuntimeError("independent repeat images or render metadata differ")
    metrics = assess(records["filtered"], records["raw"], records["reference8"], records["reference16"])
    # The same acceptance function must reject both raw aliasing and removed detail.
    controls = {"raw": records["raw"], "no_stripes": {
        key: (np.zeros_like(pixels), metadata) for key, (pixels, metadata) in records["filtered"].items()}}
    rejected = {}
    for name, control in controls.items():
        try:
            assess(control, records["raw"], records["reference8"], records["reference16"])
        except RuntimeError as exc:
            rejected[name] = str(exc)
        else:
            raise RuntimeError(f"negative control escaped acceptance: {name}")
    sources = [app / "render/ground.gdshader", CAPTURE_SCRIPT, Path(__file__).resolve()]
    summary = {"format": "openrc-l9c-stripe-reference v1", "complete": True,
               "scope": "stripe-only error against a 16x reference, separated from measured 8x/16x disagreement; not proven convergence or perceptual shimmer closure",
               "metrics": metrics, "reference_margin": REFERENCE_MARGIN,
               "byte_identical_repeat": True, "negative_controls_rejected": rejected,
               "godot_version": subprocess.run([str(godot), "--version"], check=True, capture_output=True, text=True).stdout.strip(),
               "renderer": manifests["filtered"]["renderer_adapter"], "commands": commands,
               "capture_environment": {key: env[key] for key in ("LP_NUM_THREADS", "OPENRC_SCENERY", "OPENRC_SCENERY_AUDIO", "OPENRC_SCENERY_BIRDS")},
               "sources_sha256": {str(path): sha256(path) for path in sources}}
    (out / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True, allow_nan=False) + "\n")
    print(f"L9c-R1 stripe reference passed: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
