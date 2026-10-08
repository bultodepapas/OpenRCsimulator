#!/usr/bin/env python3
"""Render L9c ground surfaces and compare stripe filtering with a scratch mutation.

The half-pixel score compares (surface-on − surface-off) residuals, so grass
aliasing cancels. Both oblique views are observational: the captures document
the measured effect without treating it as proof of shimmer closure.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
APP_DEFAULT = ROOT / "app"
CAPTURE_SCRIPT = Path(__file__).with_name("capture_surfaces.gd")
FORMAT = "openrc-l9c-surfaces-capture v1"
WIDTH, HEIGHT = 1280, 720
SCREEN = "-screen 0 1280x720x24"
VIEWS = {
    "runway_zoom_100": 10.0,
    "runway_zoom_300": 10.0,
    "runway_oblique_100": 10.0,
    "runway_oblique_300": 10.0,
    "runway_threshold": 40.0,
    "aerial_overview": 50.0,
}
VERTICAL_SHIFT_VIEWS = {"runway_oblique_100", "runway_oblique_300"}
EDGE_CONTRAST_FLOOR = 0.05


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON constant {value}")


def finite_tree(value: Any, path: str = "manifest") -> None:
    if value is None:
        raise RuntimeError(f"{path} contains null instead of a finite capture value")
    if isinstance(value, float) and not math.isfinite(value):
        raise RuntimeError(f"{path} contains a non-finite number")
    if isinstance(value, dict):
        for key, child in value.items():
            finite_tree(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            finite_tree(child, f"{path}[{index}]")


def load_manifest(folder: Path) -> dict[str, Any]:
    manifest_path = folder / "capture.json"
    if not manifest_path.is_file():
        raise RuntimeError(f"missing capture manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(), parse_constant=reject_constant)
    finite_tree(manifest)
    if manifest.get("format") != FORMAT:
        raise RuntimeError(f"{folder.name}: wrong capture format")
    if manifest.get("renderer_method") != "gl_compatibility":
        raise RuntimeError(f"{folder.name}: expected Compatibility renderer, got {manifest.get('renderer_method')!r}")
    if manifest.get("renderer_driver") != "opengl3":
        raise RuntimeError(f"{folder.name}: expected OpenGL Compatibility driver, got {manifest.get('renderer_driver')!r}")
    if manifest.get("viewport") != [WIDTH, HEIGHT] or manifest.get("surfaces_consolidated") is not True:
        raise RuntimeError(f"{folder.name}: wrong viewport or lifted surface geometry remains")
    if manifest.get("shader_time_s") != 0.0:
        raise RuntimeError(f"{folder.name}: shader time was not fixed at zero")
    return manifest


def checked_run(command: list[str], log_path: Path, env: dict[str, str], timeout_s: int) -> None:
    with log_path.open("w") as output:
        result = subprocess.run(
            ["timeout", "--kill-after=5", str(timeout_s), *command],
            stdout=output,
            stderr=subprocess.STDOUT,
            env=env,
            check=False,
        )
    log = re.sub(r"\x1b\[[0-9;]*m", "", log_path.read_text(errors="replace"))
    if result.returncode or re.search(r"^\s*(?:(?:SCRIPT|SHADER)\s+)?ERROR:", log, re.M):
        raise RuntimeError(f"Godot command failed ({result.returncode}); see {log_path}")


def import_mutation_project(godot: Path, project: Path, log_path: Path,
                            env: dict[str, str], timeout_s: int) -> list[str]:
    command = [str(godot), "--headless", "--path", str(project), "--audio-driver", "Dummy", "--import"]
    checked_run(command, log_path, env, timeout_s)
    return command


def image_pixels(folder: Path, capture: dict[str, Any]) -> np.ndarray:
    name = str(capture.get("image", ""))
    path = folder / name
    if not path.is_file():
        raise RuntimeError(f"missing PNG: {path}")
    if sha256(path) != capture.get("sha256"):
        raise RuntimeError(f"PNG hash mismatch: {path}")
    with Image.open(path) as image:
        pixels = np.asarray(image.convert("RGB"), dtype=np.uint8)
    if pixels.shape != (HEIGHT, WIDTH, 3):
        raise RuntimeError(f"{path.name}: expected {WIDTH}x{HEIGHT}, got {pixels.shape[1]}x{pixels.shape[0]}")
    return pixels


def index_captures(manifest: dict[str, Any], folder: Path,
                   expected_views: set[str] | None = None) -> dict[tuple[str, float, str], tuple[dict[str, Any], np.ndarray]]:
    indexed: dict[tuple[str, float, str], tuple[dict[str, Any], np.ndarray]] = {}
    views = manifest.get("views")
    if not isinstance(views, list):
        raise RuntimeError(f"{folder.name}: missing view array")
    for view in views:
        view_id = str(view.get("id", ""))
        if view_id not in VIEWS or float(view.get("fov_deg", -1)) != VIEWS[view_id]:
            raise RuntimeError(f"{folder.name}: unexpected view or FOV: {view_id}")
        captures = view.get("captures")
        if not isinstance(captures, list) or len(captures) != 4:
            raise RuntimeError(f"{folder.name}/{view_id}: expected four paired captures")
        for capture in captures:
            state = str(capture.get("state", ""))
            shift = float(capture.get("shift_pixels", -1))
            if state not in ("on", "off") or shift not in (0.0, 0.5):
                raise RuntimeError(f"{folder.name}/{view_id}: invalid state or shift")
            expected_axis = "vertical" if view_id in VERTICAL_SHIFT_VIEWS else "horizontal"
            if capture.get("shift_axis") != expected_axis:
                raise RuntimeError(f"{folder.name}/{view_id}: expected a {expected_axis} camera-plane shift")
            polygon = capture.get("projected_runway")
            if not isinstance(polygon, list) or len(polygon) != 4 or any(len(point) != 2 for point in polygon):
                raise RuntimeError(f"{folder.name}/{view_id}: missing projected runway quad")
            counters = [capture.get(key) for key in ("draw_calls", "primitives", "objects")]
            if any(not isinstance(counter, int) or counter < 0 for counter in counters):
                raise RuntimeError(f"{folder.name}/{view_id}: missing render counters")
            key = (view_id, shift, state)
            if key in indexed:
                raise RuntimeError(f"{folder.name}: duplicate capture {key}")
            indexed[key] = (capture, image_pixels(folder, capture))
    required = expected_views if expected_views is not None else set(VIEWS)
    expected = {(view, shift, state) for view in required for shift in (0.0, 0.5) for state in ("off", "on")}
    if set(indexed) != expected:
        raise RuntimeError(f"{folder.name}: incomplete view set")
    return indexed


def check_surface_metadata(manifest: dict[str, Any], priority: bool) -> None:
    expected_kinds = [1, 2] if priority else [2]
    if manifest.get("surface_count") != len(expected_kinds) or manifest.get("surface_kinds") != expected_kinds:
        raise RuntimeError("surface arrays do not contain mown-before-runway priority order")
    expected_input_order = ["rough", "runway", "mown"] if priority else ["rough", "runway"]
    if manifest.get("surface_input_order") != expected_input_order:
        raise RuntimeError("priority fixture input order was not reversed as intended")
    rects = manifest.get("surface_rects")
    bounds = manifest.get("surface_bounds")
    if not isinstance(rects, list) or len(rects) != len(expected_kinds) or not isinstance(bounds, list) or len(bounds) != 4:
        raise RuntimeError("surface arrays or bounds are missing")
    if any(len(rect) != 4 or rect[2] <= 0 or rect[3] <= 0 for rect in rects):
        raise RuntimeError("invalid surface rectangle")
    if bounds[0] >= bounds[2] or bounds[1] >= bounds[3]:
        raise RuntimeError("invalid surface bounds")
    for x, z, hx, hz in rects:
        if x - hx < bounds[0] - 0.001 or z - hz < bounds[1] - 0.001 \
                or x + hx > bounds[2] + 0.001 or z + hz > bounds[3] + 0.001:
            raise RuntimeError("surface rectangle lies outside surface_bounds")


def compare_repeats(first: Path, second: Path, first_manifest: dict[str, Any], second_manifest: dict[str, Any]) -> int:
    if first_manifest != second_manifest:
        raise RuntimeError(f"repeat manifests differ: {first.name} vs {second.name}")
    ids = {str(view["id"]) for view in first_manifest.get("views", [])}
    a = index_captures(first_manifest, first, ids)
    b = index_captures(second_manifest, second, ids)
    if a.keys() != b.keys():
        raise RuntimeError("repeat capture sets differ")
    for key in a:
        meta_a, _ = a[key]
        meta_b, _ = b[key]
        if meta_a.get("sha256") != meta_b.get("sha256"):
            raise RuntimeError(f"repeat PNG hash differs: {key}")
        for counter in ("draw_calls", "primitives", "objects"):
            if meta_a.get(counter) != meta_b.get(counter):
                raise RuntimeError(f"repeat {counter} differs: {key}")
    return len(a)


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[:, :, 0] * 0.2126 + rgb[:, :, 1] * 0.7152 + rgb[:, :, 2] * 0.0722


def polygon_mask(capture: dict[str, Any]) -> np.ndarray:
    mask = Image.new("L", (WIDTH, HEIGHT), 0)
    points = [(round(float(x)), round(float(y))) for x, y in capture["projected_runway"]]
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return np.asarray(mask, dtype=np.uint8) > 0


def filter_mask(mask: np.ndarray, size: int, operation: Any) -> np.ndarray:
    image = Image.fromarray(mask.astype(np.uint8) * 255)
    return np.asarray(image.filter(operation(size)), dtype=np.uint8) > 0


def pair_metrics(folder: Path, captures: dict[tuple[str, float, str], tuple[dict[str, Any], np.ndarray]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    view_ids = sorted({key[0] for key in captures})
    for view_id in view_ids:
        per_shift: dict[float, tuple[dict[str, Any], np.ndarray, np.ndarray, np.ndarray]] = {}
        for shift in (0.0, 0.5):
            off_meta, off = captures[(view_id, shift, "off")]
            on_meta, on = captures[(view_id, shift, "on")]
            if [on_meta.get(k) for k in ("draw_calls", "primitives", "objects")] != \
                    [off_meta.get(k) for k in ("draw_calls", "primitives", "objects")]:
                raise RuntimeError(f"surface ablation changed render counters: {view_id}, shift {shift}")
            polygon = polygon_mask(on_meta)
            if np.count_nonzero(polygon) < 16:
                raise RuntimeError(f"projected runway is missing from {view_id}")
            difference = np.max(np.abs(on.astype(np.int16) - off.astype(np.int16)), axis=2)
            changed = difference > 1
            changed_in_polygon = int(np.count_nonzero(changed & polygon))
            if changed_in_polygon == 0:
                raise RuntimeError(f"surface-on/off ablation changed no runway pixels in {view_id}")
            per_shift[shift] = (on_meta, on, off, changed)
        meta0, on0, off0, changed0 = per_shift[0.0]
        meta1, on1, off1, changed1 = per_shift[0.5]
        region = (filter_mask(polygon_mask(meta0) | polygon_mask(meta1), 17, ImageFilter.MaxFilter)
                  & (changed0 | changed1))
        if np.count_nonzero(region) < 16:
            raise RuntimeError(f"surface residual mask is too small in {view_id}")
        residual0 = on0.astype(np.float32) - off0.astype(np.float32)
        residual1 = on1.astype(np.float32) - off1.astype(np.float32)
        signal = float(np.sqrt(np.mean(((residual0[region] ** 2) + (residual1[region] ** 2)) * 0.5)))
        delta = float(np.sqrt(np.mean((residual0[region] - residual1[region]) ** 2)))
        shimmer = delta / max(signal, 2.0)
        if not math.isfinite(shimmer):
            raise RuntimeError(f"non-finite half-pixel surface shimmer score in {view_id}")
        result[view_id] = {
            "surface_changed_pixels": {"shift0": int(np.count_nonzero(changed0)), "shift05": int(np.count_nonzero(changed1))},
            "surface_residual_rms_rgb": round(signal, 4),
            "half_pixel_residual_rms_delta_rgb": round(delta, 4),
            "half_pixel_shimmer_ratio": round(shimmer, 5),
            "comparison": "surface residual only; observational and includes expected half-pixel camera motion",
        }

    edge_id = "runway_zoom_100"
    if edge_id not in view_ids:
        return result
    on_meta: dict[str, Any]
    on: np.ndarray
    off: np.ndarray
    changed: np.ndarray
    on_meta = captures[(edge_id, 0.0, "on")][0]
    on = captures[(edge_id, 0.0, "on")][1]
    off = captures[(edge_id, 0.0, "off")][1]
    changed = np.max(np.abs(on.astype(np.int16) - off.astype(np.int16)), axis=2) > 1
    polygon = polygon_mask(on_meta)
    expanded = filter_mask(polygon, 11, ImageFilter.MaxFilter)
    eroded = filter_mask(polygon, 11, ImageFilter.MinFilter)
    inner_edge = polygon & ~eroded & changed
    if np.count_nonzero(inner_edge) < 8:
        inner_edge = polygon & changed
    outside = expanded & ~polygon
    if np.count_nonzero(inner_edge) < 8 or np.count_nonzero(outside) < 8:
        raise RuntimeError("100 m projected runway edge does not have enough inside/outside pixels")
    on_luma = luma(on)
    off_luma = luma(off)
    inside_level = float(np.median(on_luma[inner_edge]))
    outside_level = float(np.median(off_luma[outside]))
    contrast = (inside_level - outside_level) / max(outside_level, 1.0)
    if not math.isfinite(contrast) or contrast < EDGE_CONTRAST_FLOOR:
        raise RuntimeError(f"100 m runway edge contrast failed: {contrast:.3f} < {EDGE_CONTRAST_FLOOR}")
    result["runway_edge_100m"] = {
        "inside_median_luma": round(inside_level, 3),
        "adjacent_rough_median_luma": round(outside_level, 3),
        "weber_contrast": round(contrast, 5),
        "minimum_weber_contrast": EDGE_CONTRAST_FLOOR,
        "inside_edge_pixels": int(np.count_nonzero(inner_edge)),
        "outside_edge_pixels": int(np.count_nonzero(outside)),
    }
    return result


def make_priority_field(default_path: Path, output_path: Path) -> None:
    raw = json.loads(default_path.read_text())
    surfaces = copy.deepcopy(raw["surfaces"])
    runway = copy.deepcopy(next(surface for surface in surfaces if surface["type"] == "runway"))
    mown = copy.deepcopy(runway)
    mown["id"] = "mown"
    mown["type"] = "mown"
    for key, value in (("length_east_west", 160), ("width_north_south", 50)):
        mown[key] = {"value": value, "unit": "m", "kind": "estimated",
                     "source": "L9c priority capture fixture around the existing runway; visual test only."}
    raw["id"] = "l9c_priority_capture"
    # Input order puts runway below the later mown rectangle; the renderer must retain runway priority.
    raw["surfaces"] = [next(surface for surface in surfaces if surface["type"] == "rough"), runway, mown]
    # The broad pad crosses the field validator's reserved tree corridor; trees are irrelevant to this GPU fixture.
    raw["objects"] = []
    raw.pop("flight_cues", None)  # Broad synthetic mown pad is independent of flight-cue placement.
    output_path.write_text(json.dumps(raw, indent=2) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=APP_DEFAULT, help="candidate Godot project directory")
    parser.add_argument("--godot", type=Path, help="Godot 4.7 executable; defaults to app/get-godot.sh")
    parser.add_argument("--out", type=Path, default=Path("/tmp/l9c-surfaces"), help="new or empty evidence directory")
    parser.add_argument("--timeout", type=int, default=240, help="timeout per renderer process in seconds")
    args = parser.parse_args()
    app, out = args.app.resolve(), args.out.resolve()
    if not app.is_dir() or not CAPTURE_SCRIPT.is_file():
        parser.error("app project or capture script is missing")
    if args.timeout <= 0 or shutil.which("xvfb-run") is None or shutil.which("timeout") is None:
        parser.error("positive --timeout, xvfb-run, and timeout are required")
    if args.godot:
        godot = args.godot.resolve()
    else:
        godot_text = subprocess.run([str(app / "get-godot.sh")], check=True, capture_output=True, text=True).stdout.strip()
        godot = Path(godot_text).resolve()
    if not godot.is_file():
        parser.error(f"missing Godot executable: {godot}")
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        parser.error(f"output must be new or empty; stale evidence is refused: {out}")
    out.mkdir(parents=True, exist_ok=True)
    folders = {name: out / name for name in ("default-repeat-1", "default-repeat-2", "priority-repeat-1", "priority-repeat-2")}
    for folder in folders.values():
        folder.mkdir()
    priority_path = out / "priority-field.json"
    make_priority_field(app / "data/fields/default.json", priority_path)
    env = dict(os.environ, LP_NUM_THREADS="1", OPENRC_SCENERY="off", OPENRC_SCENERY_AUDIO="off",
               OPENRC_SCENERY_BIRDS="off", PYTHONDONTWRITEBYTECODE="1")
    base = ["xvfb-run", "-a", "-s", SCREEN, str(godot), "--path", str(app), "--rendering-driver", "opengl3",
            "--audio-driver", "Dummy", "--script", str(CAPTURE_SCRIPT.resolve()), "--"]
    manifests: dict[str, dict[str, Any]] = {}
    repeat_counts: dict[str, int] = {}
    commands: dict[str, list[str]] = {}
    for label in ("default", "priority"):
        for repeat in (1, 2):
            name = f"{label}-repeat-{repeat}"
            command = [*base, f"--out={folders[name]}"]
            if label == "priority":
                command += [f"--field={priority_path}", "--fixture=priority"]
            commands[name] = command
            checked_run(command, out / f"{name}.log", env, args.timeout)
            manifests[name] = load_manifest(folders[name])
            check_surface_metadata(manifests[name], priority=(label == "priority"))
        repeat_counts[label] = compare_repeats(folders[f"{label}-repeat-1"], folders[f"{label}-repeat-2"],
                                                manifests[f"{label}-repeat-1"], manifests[f"{label}-repeat-2"])
    default_folder = folders["default-repeat-1"]
    default_captures = index_captures(manifests["default-repeat-1"], default_folder)
    metrics = pair_metrics(default_folder, default_captures)
    custom_folder = folders["priority-repeat-1"]
    custom_captures = index_captures(manifests["priority-repeat-1"], custom_folder, {"runway_zoom_100"})
    default_on = default_captures[("runway_zoom_100", 0.0, "on")][1]
    custom_on = custom_captures[("runway_zoom_100", 0.0, "on")][1]
    default_meta = default_captures[("runway_zoom_100", 0.0, "on")][0]
    # The 12 m runway width is about nine pixels in this end-on 10° view.
    # A seven-pixel erosion leaves a three-pixel interior band and discards edge AA.
    runway_core = filter_mask(polygon_mask(default_meta), 7, ImageFilter.MinFilter)
    default_changed = np.max(np.abs(default_on.astype(np.int16) - default_captures[("runway_zoom_100", 0.0, "off")][1].astype(np.int16)), axis=2) > 1
    runway_core &= default_changed
    if np.count_nonzero(runway_core) < 16:
        raise RuntimeError("custom priority comparison has no runway core")
    priority_delta = np.abs(default_on.astype(np.int16) - custom_on.astype(np.int16))[runway_core]
    priority_mean = float(priority_delta.mean())
    priority_p95 = float(np.quantile(priority_delta, 0.95))
    if priority_mean > 2.0 or priority_p95 > 5.0:
        raise RuntimeError(f"runway lost priority under overlapping mown surface: mean={priority_mean:.2f}, p95={priority_p95:.2f}")
    custom_meta = custom_captures[("runway_zoom_100", 0.0, "on")][0]
    if "mown" not in custom_meta.get("projected_surfaces", {}):
        raise RuntimeError("priority fixture is missing its projected mown rectangle")
    mown_mask = polygon_mask({"projected_runway": custom_meta["projected_surfaces"]["mown"]})
    runway_mask = polygon_mask(custom_meta)
    mown_ring = mown_mask & ~filter_mask(runway_mask, 11, ImageFilter.MaxFilter)
    custom_off = custom_captures[("runway_zoom_100", 0.0, "off")][1]
    mown_effect = np.max(np.abs(custom_on.astype(np.int16) - custom_off.astype(np.int16)), axis=2)
    mown_pixels = mown_ring & (mown_effect > 1)
    if np.count_nonzero(mown_pixels) < 32 or float(mown_effect[mown_pixels].mean()) < 2.0:
        raise RuntimeError("overlapping custom mown surface produced no measurable GPU contribution")
    metrics["reversed_input_priority_fixture"] = {
        "surface_count": 2,
        "shader_kind_order": manifests["priority-repeat-1"]["surface_kinds"],
        "runway_core_mean_abs_rgb_delta_from_default": round(priority_mean, 4),
        "runway_core_p95_abs_rgb_delta_from_default": round(priority_p95, 4),
        "mean_limit_levels": 2.0,
        "p95_limit_levels": 5.0,
        "mown_ring_changed_pixels": int(np.count_nonzero(mown_pixels)),
        "mown_ring_mean_rgb_delta_from_rough": round(float(mown_effect[mown_pixels].mean()), 3),
    }
    mutant_app = out / "disabled-surface-app"
    make_mutation_app(app, mutant_app, "disabled")
    commands["disabled_surface_mutation_import"] = import_mutation_project(
        godot, mutant_app, out / "disabled-surface-import.log", env, args.timeout)
    mutation_run = out / "disabled-surface-run"
    mutation_run.mkdir()
    mutant_base = [*base[:4], str(godot), "--path", str(mutant_app), *base[7:]]
    disabled_command = [*mutant_base, f"--out={mutation_run}", "--fixture=disabled"]
    commands["disabled_surface_mutation"] = disabled_command
    checked_run(disabled_command,
                out / "disabled-surface-mutation.log", env, args.timeout)
    mutant_manifest = load_manifest(mutation_run)
    mutant_captures = index_captures(mutant_manifest, mutation_run, {"runway_zoom_100"})
    try:
        pair_metrics(mutation_run, mutant_captures)
    except RuntimeError as exc:
        if "surface-on/off ablation changed no runway pixels" not in str(exc):
            raise
        mutation_caught = True
    else:
        raise RuntimeError("disabled-surfaces shader mutation escaped the no-effect gate")
    unfiltered_app = out / "unfiltered-stripe-app"
    make_mutation_app(app, unfiltered_app, "unfiltered")
    commands["unfiltered_stripe_mutation_import"] = import_mutation_project(
        godot, unfiltered_app, out / "unfiltered-stripe-import.log", env, args.timeout)
    unfiltered_run = out / "unfiltered-stripe-run"
    unfiltered_run.mkdir()
    unfiltered_base = [*base[:4], str(godot), "--path", str(unfiltered_app), *base[7:]]
    unfiltered_command = [*unfiltered_base, f"--out={unfiltered_run}", "--fixture=stripe"]
    commands["unfiltered_stripe_mutation"] = unfiltered_command
    checked_run(unfiltered_command,
                out / "unfiltered-stripe-mutation.log", env, args.timeout)
    unfiltered_manifest = load_manifest(unfiltered_run)
    oblique_views = {"runway_oblique_100", "runway_oblique_300"}
    unfiltered_captures = index_captures(unfiltered_manifest, unfiltered_run, oblique_views)
    unfiltered_metrics = pair_metrics(unfiltered_run, unfiltered_captures)
    stripe_comparison: dict[str, Any] = {}
    for distance in ("100", "300"):
        view_id = f"runway_oblique_{distance}"
        filtered_score = metrics[view_id]["half_pixel_shimmer_ratio"]
        unfiltered_score = unfiltered_metrics[view_id]["half_pixel_shimmer_ratio"]
        stripe_comparison[f"oblique_{distance}m"] = {
            "filtered_ratio": round(filtered_score, 5),
            "unfiltered_ratio": round(unfiltered_score, 5),
            "ratio_reduction": round(1.0 - filtered_score / max(unfiltered_score, 1e-9), 5),
            "interpretation": "observational; no acceptance threshold is claimed",
        }
    metrics["runway_stripe_filter_mutation"] = {
        "per_view": stripe_comparison,
        "raw_square_wave_mutation_captured": True,
        "acceptance_status": "open_observational",
    }
    summary = {
        "format": "openrc-l9c-surfaces-review v1",
        "complete": True,
        "project": str(app),
        "godot_version": subprocess.run([str(godot), "--version"], check=True, capture_output=True, text=True).stdout.strip(),
        "renderer": manifests["default-repeat-1"]["renderer_adapter"],
        "renderer_method": manifests["default-repeat-1"]["renderer_method"],
        "renderer_driver": manifests["default-repeat-1"]["renderer_driver"],
        "sources_sha256": {
            relative: sha256(app / relative) for relative in (
                "render/field.gd", "render/ground.gd", "render/ground.gdshader",
                "render/atmosphere.gd", "data/fields/default.json",
            )
        } | {
            "tools/ground/capture_surfaces.gd": sha256(CAPTURE_SCRIPT),
            "tools/ground/check_surfaces.py": sha256(Path(__file__).resolve()),
        },
        "commands": commands,
        "capture_environment": {"LP_NUM_THREADS": "1", "OPENRC_SCENERY": "off",
                                "OPENRC_SCENERY_AUDIO": "off", "OPENRC_SCENERY_BIRDS": "off"},
        "repeat_processes": 2,
        "repeat_capture_counts": repeat_counts,
        "byte_identical_repeats": True,
        "disabled_surfaces_mutation_rejected": mutation_caught,
        "no_filter_stripe_mutation_captured": True,
        "no_filter_stripe_mutation_rejected": False,
        "stripe_filter_acceptance": "open_observational",
        "metrics": metrics,
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True, allow_nan=False) + "\n")
    print(f"L9c surface review passed: edge contrast {metrics['runway_edge_100m']['weber_contrast']:.1%}; "
          f"max half-pixel shimmer {max(metrics[k]['half_pixel_shimmer_ratio'] for k in VIEWS):.3f}; "
          f"outputs: {out}")
    return 0


def make_mutation_app(source: Path, target: Path, mutation: str) -> None:
    shutil.copytree(source, target, ignore=shutil.ignore_patterns(
        ".godot", ".tools", "captures", "build", "dist", "__pycache__"
    ))
    shader_path = target / "render" / "ground.gdshader"
    shader = shader_path.read_text()
    if mutation == "disabled":
        needle = "} else if (surface_count > 0) {"
        if shader.count(needle) != 1:
            raise RuntimeError("cannot apply disabled-surface mutation to the current ground shader")
        shader = shader.replace(needle, "} else if (false) {", 1)
    elif mutation == "unfiltered":
        pattern = re.compile(r"float square_filtered\(float u, float du\)\s*\{.*?\n\}", re.S)
        if len(pattern.findall(shader)) != 1:
            raise RuntimeError("cannot apply no-filter mutation to the current ground shader")
        shader = pattern.sub("float square_filtered(float u, float du) {\n\treturn fract(u) < 0.5 ? 1.0 : -1.0;\n}", shader, count=1)
    else:
        raise RuntimeError(f"unknown shader mutation: {mutation}")
    shader_path.write_text(shader)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        print(f"L9c surface review failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
