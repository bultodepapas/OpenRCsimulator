#!/usr/bin/env python3
"""Capture and check Phase 6 production sky/cloud-shadow A/B evidence."""

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
CAPTURE_SCRIPT = Path(__file__).with_name("capture_phase6.gd")
FORMAT = "openrc-phase6-capture v1"
SUMMARY_FORMAT = "openrc-phase6-review v1"
MODES = ("legacy", "enhanced")
SHADOW_CONTROL_MODE = "shadow-off"
TIMES = (0, 10, 120)
SHADOW_CONTROL_TIMES = (0, 120)
SKY_VIEWS = (
    ("sun-up10", 225.0, 10.0, 1.7, "sky-and-field"),
    ("sun-up45", 225.0, 45.0, 1.7, "sky-and-field"),
    ("antisun-up10", 45.0, 10.0, 1.7, "sky-and-field"),
    ("antisun-up45", 45.0, 45.0, 1.7, "sky-and-field"),
)
HIGH_VIEW = ("ground-down15", 225.0, -15.0, 140.0, "high-ground-and-shadow")
EXPECTED_SKY_KNOBS = ("cluster_strength", "cirrus_strength", "silver_strength")
EXPECTED_GROUND_KNOBS = ("cloud_shadow_strength", "cluster_strength", "cloud_deck_m", "cloud_coverage", "cloud_scale", "cloud_seed")
WIDTH = 1280
HEIGHT = 720
GRADING_METADATA = {"enabled": True, "brightness": 1.0, "contrast": 1.04, "saturation": 1.02}
NEUTRAL_GRADING_METADATA = {"enabled": False, "brightness": 1.0, "contrast": 1.04, "saturation": 1.02}
RUNTIME_SUFFIXES = {
    ".cfg", ".gd", ".gdshader", ".gdshaderinc", ".gdextension", ".godot", ".gltf", ".glb",
    ".import", ".json", ".mp3", ".ogg", ".po", ".png", ".res", ".svg", ".tres", ".tscn",
    ".ttf", ".otf", ".wav", ".webp", ".jpg", ".jpeg",
}
EXCLUDED_DIRS = {".git", ".godot", ".tools", "__pycache__", "build", "captures", "dist"}


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _map_sha256(entries: dict[str, str]) -> str:
    canonical = json.dumps(entries, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256_bytes(canonical)


def source_snapshot(project: Path) -> dict[str, Any]:
    app_files: dict[str, str] = {}
    for current, directories, filenames in os.walk(project):
        directories[:] = sorted(name for name in directories if name not in EXCLUDED_DIRS)
        current_path = Path(current)
        for filename in sorted(filenames):
            path = current_path / filename
            if path.suffix.lower() not in RUNTIME_SUFFIXES:
                continue
            relative = path.relative_to(project).as_posix()
            app_files[relative] = sha256_file(path)
    producer_files = {
        path.relative_to(ROOT).as_posix(): sha256_file(path)
        for path in (CAPTURE_SCRIPT.resolve(), Path(__file__).resolve())
    }
    return {
        "project": str(project),
        "app_files": app_files,
        "app_file_map_sha256": _map_sha256(app_files),
        "producer_files": producer_files,
        "producer_file_map_sha256": _map_sha256(producer_files),
    }


def source_guard_report(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    same_app = before["app_files"] == after["app_files"]
    same_producers = before["producer_files"] == after["producer_files"]
    if not same_app or not same_producers:
        changed_app = sorted(
            key for key in set(before["app_files"]) | set(after["app_files"])
            if before["app_files"].get(key) != after["app_files"].get(key)
        )
        changed_producers = sorted(
            key for key in set(before["producer_files"]) | set(after["producer_files"])
            if before["producer_files"].get(key) != after["producer_files"].get(key)
        )
        raise RuntimeError(
            f"runtime sources changed during capture: app={changed_app[:8]}, producers={changed_producers}"
        )
    return {
        "project": before["project"],
        "runtime_file_count": len(before["app_files"]),
        "runtime_files_sha256": before["app_files"],
        "runtime_file_map_sha256": before["app_file_map_sha256"],
        "producer_files_sha256": before["producer_files"],
        "producer_file_map_sha256": before["producer_file_map_sha256"],
        "after_runtime_file_map_sha256": after["app_file_map_sha256"],
        "after_producer_file_map_sha256": after["producer_file_map_sha256"],
        "unchanged_during_capture": True,
    }


def checked_run(command: list[str], log_path: Path, env: dict[str, str], timeout_s: int = 180) -> None:
    with log_path.open("w") as output:
        result = subprocess.run(
            ["timeout", "--kill-after=5", str(timeout_s), *command],
            stdout=output,
            stderr=subprocess.STDOUT,
            env=env,
            check=False,
        )
    text = re.sub(r"\x1b\[[0-9;]*m", "", log_path.read_text(errors="replace"))
    if result.returncode or re.search(r"^\s*(?:(?:SCRIPT|SHADER)\s+)?ERROR:", text, re.M):
        raise RuntimeError(f"engine capture failed ({result.returncode}): {log_path}")


def expected_case_ids(mode: str) -> set[str]:
    result: set[str] = set()
    if mode == SHADOW_CONTROL_MODE:
        return {f"{mode}-{HIGH_VIEW[0]}-t{time_s:03d}" for time_s in SHADOW_CONTROL_TIMES}
    views = [view[0] for view in SKY_VIEWS] + [HIGH_VIEW[0]]
    for time_s in TIMES:
        time_tag = f"t{time_s:03d}"
        result.update(f"{mode}-{view}-{time_tag}" for view in views)
    return result


def image_rgb(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        pixels = np.asarray(image.convert("RGB"), dtype=np.uint8)
    if pixels.shape != (HEIGHT, WIDTH, 3):
        raise RuntimeError(f"{path.name}: expected {WIDTH}×{HEIGHT} RGB, got {pixels.shape[1]}×{pixels.shape[0]}")
    return pixels


def image_metrics(path: Path) -> dict[str, Any]:
    pixels = image_rgb(path).astype(np.float32)
    luma = pixels[:, :, 0] * 0.2126 + pixels[:, :, 1] * 0.7152 + pixels[:, :, 2] * 0.0722
    return {
        "sha256": sha256_file(path),
        "width": WIDTH,
        "height": HEIGHT,
        "luma_p10": round(float(np.quantile(luma, 0.1)), 3),
        "luma_p50": round(float(np.quantile(luma, 0.5)), 3),
        "luma_p90": round(float(np.quantile(luma, 0.9)), 3),
    }


def compare_arrays(a: np.ndarray, b: np.ndarray) -> dict[str, Any]:
    delta = np.abs(a.astype(np.int16) - b.astype(np.int16))
    max_channel = delta.max(axis=2)
    changed = max_channel != 0
    return {
        "changed_pixels": int(np.count_nonzero(changed)),
        "changed_pixel_fraction": round(float(np.count_nonzero(changed)) / float(changed.size), 8),
        "mean_abs_rgb_delta": round(float(delta.mean()), 6),
        "p99_max_channel_delta": round(float(np.quantile(max_channel, 0.99)), 3),
    }


def expected_metadata(mode: str, view_id: str, time_s: int) -> tuple[float, float, float, str]:
    for view in SKY_VIEWS + (HIGH_VIEW,):
        if view[0] == view_id:
            return view[1], view[2], view[3], view[4]
    raise RuntimeError(f"unknown view id: {view_id}")


def load_run(
    folder: Path,
    mode: str,
    shadow_override: float | None,
    legacy_only: bool = False,
) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    manifest_path = folder / "capture-manifest.json"
    if not manifest_path.is_file():
        raise RuntimeError(f"missing manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("format") != FORMAT or manifest.get("mode") != mode:
        raise RuntimeError(f"{manifest_path}: unexpected format/mode")
    if manifest.get("legacy_only") is not legacy_only:
        raise RuntimeError(f"{manifest_path}: legacy-only metadata mismatch")
    expected_grading = GRADING_METADATA if mode == "graded" else NEUTRAL_GRADING_METADATA
    if manifest.get("grading") != expected_grading:
        raise RuntimeError(f"{manifest_path}: environment grading metadata mismatch")
    expected_times = SHADOW_CONTROL_TIMES if mode == SHADOW_CONTROL_MODE else TIMES
    if manifest.get("capture_times_s") != [float(time_s) for time_s in expected_times]:
        raise RuntimeError(f"{manifest_path}: requested time sequence metadata mismatch")
    if manifest.get("viewport") != {"width": WIDTH, "height": HEIGHT}:
        raise RuntimeError(f"{manifest_path}: viewport must be {WIDTH}×{HEIGHT}")
    if not isinstance(manifest.get("renderer"), str) or not manifest["renderer"]:
        raise RuntimeError(f"{manifest_path}: missing renderer metadata")

    cases = manifest.get("cases")
    if not isinstance(cases, list):
        raise RuntimeError(f"{manifest_path}: cases must be a list")
    ids = [str(case.get("id", "")) for case in cases]
    if len(ids) != len(set(ids)) or set(ids) != expected_case_ids(mode):
        raise RuntimeError(
            f"{manifest_path}: case inventory differs; missing={sorted(expected_case_ids(mode) - set(ids))}, "
            f"extra={sorted(set(ids) - expected_case_ids(mode))}"
        )

    production = manifest.get("production_knobs", {})
    effective = manifest.get("effective_knobs", {})
    if not legacy_only:
        sky_production = production.get("sky", {})
        ground_production = production.get("ground", {})
        sky_effective = effective.get("sky", {})
        ground_effective = effective.get("ground_cloud_shadow_strength_per_surface", [])
        if any(key not in sky_production or key not in sky_effective for key in EXPECTED_SKY_KNOBS):
            raise RuntimeError(f"{manifest_path}: missing sky production/effective knob values")
        if any(key not in ground_production for key in EXPECTED_GROUND_KNOBS):
            raise RuntimeError(f"{manifest_path}: missing ground production knob values")
        if len(ground_effective) < 1:
            raise RuntimeError(f"{manifest_path}: no effective ground material values")
        if abs(float(ground_production["cloud_deck_m"]) - 1500.0) > 1e-6:
            raise RuntimeError(f"{manifest_path}: cloud deck must be 1,500 m")

        for key in EXPECTED_SKY_KNOBS:
            value = float(sky_effective[key])
            expected = 0.0 if mode == "legacy" else float(sky_production[key])
            if abs(value - expected) > 1e-6:
                raise RuntimeError(f"{manifest_path}: {mode} {key}={value}; expected {expected}")
        expected_shadow = 0.0 if mode in ("legacy", SHADOW_CONTROL_MODE) else (
            float(shadow_override) if shadow_override is not None else float(ground_production["cloud_shadow_strength"])
        )
        if any(abs(float(value) - expected_shadow) > 1e-6 for value in ground_effective):
            raise RuntimeError(f"{manifest_path}: {mode} cloud-shadow strength does not match {expected_shadow}")
        if manifest.get("shadow_strength_override") != shadow_override:
            raise RuntimeError(f"{manifest_path}: shadow override metadata mismatch")
    elif production or effective or manifest.get("shadow_strength_override") is not None:
        raise RuntimeError(f"{manifest_path}: legacy-only baseline must not claim Phase 6 knobs")

    by_id: dict[str, dict[str, Any]] = {}
    expected_pngs: set[str] = set()
    for raw_case in cases:
        case = dict(raw_case)
        case_id = str(case["id"])
        view_id = str(case.get("view_id", ""))
        match = re.fullmatch(re.escape(mode) + r"-([a-z0-9-]+)-t(\d{3})", case_id)
        if not match or match.group(1) != view_id:
            raise RuntimeError(f"{case_id}: malformed case id or view metadata")
        time_s = int(match.group(2))
        if time_s not in expected_times or float(case.get("sim_time_s", -1.0)) != float(time_s):
            raise RuntimeError(f"{case_id}: simulation-time metadata mismatch")
        azimuth, elevation, height, scope = expected_metadata(mode, view_id, time_s)
        for key, expected in (("azimuth_deg", azimuth), ("elevation_deg", elevation), ("camera_height_m", height)):
            if abs(float(case.get(key, -10000.0)) - expected) > 1e-6:
                raise RuntimeError(f"{case_id}: {key} mismatch")
        if case.get("visual_scope") != scope or abs(float(case.get("camera_fov_deg", -1.0)) - 50.0) > 1e-6:
            raise RuntimeError(f"{case_id}: visual scope or FOV mismatch")
        image_name = str(case.get("image", ""))
        if image_name != f"capture-{case_id}.png" or Path(image_name).name != image_name:
            raise RuntimeError(f"{case_id}: invalid image name")
        expected_pngs.add(image_name)
        image_path = folder / image_name
        if not image_path.is_file():
            raise RuntimeError(f"{case_id}: missing image {image_path}")
        if type(case.get("draw_calls")) is not int or case["draw_calls"] <= 0:
            raise RuntimeError(f"{case_id}: missing draw-call telemetry")
        if type(case.get("primitives")) is not int or case["primitives"] <= 0:
            raise RuntimeError(f"{case_id}: missing primitive telemetry")
        if type(case.get("objects")) is not int or case["objects"] <= 0:
            raise RuntimeError(f"{case_id}: missing object telemetry")
        case["image_metrics"] = image_metrics(image_path)
        case["production_knobs"] = production
        case["effective_knobs"] = effective
        by_id[case_id] = case

    actual_pngs = {path.name for path in folder.glob("capture-*.png")}
    if actual_pngs != expected_pngs:
        raise RuntimeError(
            f"{folder}: PNG inventory differs; missing={sorted(expected_pngs - actual_pngs)}, "
            f"extra={sorted(actual_pngs - expected_pngs)}"
        )
    return manifest, by_id


def image_comparisons(folder_a: Path, case_a: dict[str, Any], folder_b: Path, case_b: dict[str, Any]) -> dict[str, Any]:
    first = image_rgb(folder_a / str(case_a["image"]))
    second = image_rgb(folder_b / str(case_b["image"]))
    result = compare_arrays(first, second)
    if case_a["view_id"] == HIGH_VIEW[0]:
        # The lower 70% contains the nearby ground where projected cloud shadows should be visible.
        result["ground_crop_lower_70pct"] = compare_arrays(first[int(HEIGHT * 0.30) :, :, :], second[int(HEIGHT * 0.30) :, :, :])
    return result


def compare_runs(folder_a: Path, cases_a: dict[str, dict[str, Any]], folder_b: Path, cases_b: dict[str, dict[str, Any]]) -> list[str]:
    names_a = sorted(path.name for path in folder_a.glob("capture-*.png"))
    names_b = sorted(path.name for path in folder_b.glob("capture-*.png"))
    if names_a != names_b:
        raise RuntimeError(f"repeat PNG inventory mismatch between {folder_a.name} and {folder_b.name}")
    mismatched_images = [name for name in names_a if (folder_a / name).read_bytes() != (folder_b / name).read_bytes()]
    if (folder_a / "capture-manifest.json").read_bytes() != (folder_b / "capture-manifest.json").read_bytes():
        raise RuntimeError(f"repeat manifests differ between {folder_a.name} and {folder_b.name}")
    if mismatched_images:
        raise RuntimeError(f"repeat images are not byte-identical: {mismatched_images[:5]}")
    if set(cases_a) != set(cases_b):
        raise RuntimeError("repeat case IDs differ")
    return []


def timeline_metrics(folder: Path, cases: dict[str, dict[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for view in [entry[0] for entry in SKY_VIEWS] + [HIGH_VIEW[0]]:
        zero_id = f"{cases[next(iter(cases))]['mode']}-{view}-t000"
        time10_id = f"{cases[next(iter(cases))]['mode']}-{view}-t010"
        time120_id = f"{cases[next(iter(cases))]['mode']}-{view}-t120"
        zero = cases[zero_id]
        metrics: dict[str, Any] = {}
        for label, later in (("t010_vs_t000", cases[time10_id]), ("t120_vs_t000", cases[time120_id])):
            delta = image_comparisons(folder, zero, folder, later)
            metrics[label] = delta
        result[view] = metrics
    return result


def expected_atmosphere_metadata(manifest: dict[str, Any]) -> None:
    if abs(float(manifest.get("sun_azimuth_deg", -1.0)) - 225.0) > 1e-6:
        raise RuntimeError("capture sun azimuth must remain the production 225°")
    if abs(float(manifest.get("sun_elevation_deg", -1.0)) - 45.0) > 1e-6:
        raise RuntimeError("capture sun elevation must remain the production 45°")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "app", help="Godot project directory")
    parser.add_argument("--godot", type=Path, help="pinned Godot 4.7 executable; defaults to app/get-godot.sh")
    parser.add_argument("--out", type=Path, default=Path("/tmp/phase6-atmosphere"), help="evidence output directory")
    parser.add_argument("--shadow-strength", type=float, help="diagnostic enhanced-mode shadow override in [0, 1]")
    parser.add_argument("--grading", action="store_true", help="capture an optional graded mode against normal enhanced output")
    parser.add_argument("--legacy-only", action="store_true", help="capture only pre-Phase-6 L4 views from --app")
    parser.add_argument("--baseline-app", type=Path, help="also capture and compare a frozen pre-Phase-6 Godot project")
    args = parser.parse_args()

    app = args.app.resolve()
    out = args.out.resolve()
    if not app.is_dir():
        parser.error(f"missing app directory: {app}")
    if not CAPTURE_SCRIPT.is_file():
        parser.error(f"missing capture script: {CAPTURE_SCRIPT}")
    if args.shadow_strength is not None and (not np.isfinite(args.shadow_strength) or not 0.0 <= args.shadow_strength <= 1.0):
        parser.error("--shadow-strength must be finite and in [0, 1]")
    if args.legacy_only and args.shadow_strength is not None:
        parser.error("--shadow-strength cannot be used with --legacy-only")
    if args.legacy_only and args.grading:
        parser.error("--grading cannot be used with --legacy-only")
    if args.grading and args.shadow_strength is not None:
        parser.error("--grading and --shadow-strength are separate experiments; run them independently")
    baseline_app = args.baseline_app.resolve() if args.baseline_app else None
    if baseline_app is not None and not baseline_app.is_dir():
        parser.error(f"missing baseline Godot project directory: {baseline_app}")
    if shutil.which("xvfb-run") is None:
        parser.error("xvfb-run is required for production Compatibility rendering")
    if args.godot:
        godot = args.godot.resolve()
    else:
        godot_text = subprocess.run([str(app / "get-godot.sh")], check=True, capture_output=True, text=True).stdout.strip()
        godot = Path(godot_text).resolve()
    if not godot.is_file():
        parser.error(f"missing Godot executable: {godot}")

    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        parser.error(f"output directory must be empty: {out}")
    out.mkdir(parents=True, exist_ok=True)
    summary_path = out / "capture-summary.json"
    full_modes = (*MODES, SHADOW_CONTROL_MODE, *(('graded',) if args.grading else ()))
    modes = ("legacy",) if args.legacy_only else full_modes
    run_dirs = [out / f"{mode}-repeat-{repeat}" for mode in modes for repeat in (1, 2)]
    if baseline_app is not None:
        run_dirs.extend(out / f"baseline-repeat-{repeat}" for repeat in (1, 2))
    for folder in run_dirs:
        folder.mkdir(parents=True)
    env = dict(os.environ, LP_NUM_THREADS="1", OPENRC_SCENERY="off", PYTHONDONTWRITEBYTECODE="1")
    source_projects = {"candidate": app}
    if baseline_app is not None:
        source_projects["baseline"] = baseline_app
    source_before = {name: source_snapshot(project) for name, project in source_projects.items()}

    checked_run([str(godot), "--headless", "--path", str(app), "--audio-driver", "Dummy", "--import"], out / "capture-import.log", env)
    render_base = [
        "xvfb-run", "-a", "-s", "-screen 0 1280x720x24", str(godot), "--path", str(app),
        "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--script", str(CAPTURE_SCRIPT), "--",
    ]
    run_results: dict[str, list[tuple[dict[str, Any], dict[str, dict[str, Any]]]]] = {mode: [] for mode in modes}
    for repeat in (1, 2):
        for mode in modes:
            folder = out / f"{mode}-repeat-{repeat}"
            command = [*render_base, f"--out={folder}", f"--mode={mode}"]
            if args.legacy_only:
                command.append("--legacy-only")
            if mode == "graded":
                command.append("--grading=on")
            if mode == SHADOW_CONTROL_MODE:
                command.append("--shadow-strength=0")
            elif args.shadow_strength is not None and mode == "enhanced":
                command.append(f"--shadow-strength={args.shadow_strength:.9g}")
            checked_run(command, out / f"{mode}-repeat-{repeat}.log", env)
            shadow_override = 0.0 if mode == SHADOW_CONTROL_MODE else args.shadow_strength if mode == "enhanced" else None
            loaded = load_run(folder, mode, shadow_override, args.legacy_only)
            expected_atmosphere_metadata(loaded[0])
            run_results[mode].append(loaded)

    repeatability: dict[str, Any] = {}
    for mode in modes:
        first_folder = out / f"{mode}-repeat-1"
        second_folder = out / f"{mode}-repeat-2"
        compare_runs(first_folder, run_results[mode][0][1], second_folder, run_results[mode][1][1])
        repeatability[mode] = {
            "images_compared": len(run_results[mode][0][1]),
            "image_mismatches": [],
            "manifests_identical": True,
            "byte_identical": True,
        }

    baseline_results: list[tuple[dict[str, Any], dict[str, dict[str, Any]]]] = []
    baseline_parity: dict[str, Any] | None = None
    if baseline_app is not None:
        checked_run(
            [str(godot), "--headless", "--path", str(baseline_app), "--audio-driver", "Dummy", "--import"],
            out / "baseline-import.log",
            env,
        )
        for repeat in (1, 2):
            folder = out / f"baseline-repeat-{repeat}"
            path_index = render_base.index("--path")
            command = [
                *render_base[:path_index], "--path", str(baseline_app),
                *render_base[path_index + 2 :], f"--out={folder}", "--mode=legacy", "--legacy-only",
            ]
            checked_run(command, out / f"baseline-repeat-{repeat}.log", env)
            loaded = load_run(folder, "legacy", None, legacy_only=True)
            expected_atmosphere_metadata(loaded[0])
            baseline_results.append(loaded)
        compare_runs(
            out / "baseline-repeat-1", baseline_results[0][1], out / "baseline-repeat-2", baseline_results[1][1]
        )
        candidate_legacy = run_results.get("legacy", [(None, {})])[0][1]
        baseline_cases = baseline_results[0][1]
        baseline_diff: dict[str, Any] = {}
        exact_pairs = True
        for case_id in sorted(baseline_cases):
            case = baseline_cases[case_id]
            candidate_case = candidate_legacy[case_id]
            metrics = image_comparisons(
                out / "baseline-repeat-1", case, out / "legacy-repeat-1", candidate_case
            )
            exact = (out / "baseline-repeat-1" / str(case["image"])).read_bytes() == (
                out / "legacy-repeat-1" / str(candidate_case["image"])
            ).read_bytes()
            metrics["byte_identical"] = exact
            baseline_diff[case_id] = metrics
            exact_pairs = exact_pairs and exact
            for key in ("view_id", "sim_time_s", "azimuth_deg", "elevation_deg", "camera_height_m", "camera_fov_deg", "visual_scope"):
                if case.get(key) != candidate_case.get(key):
                    raise RuntimeError(f"baseline parity case mismatch for {case_id}: {key}")
        baseline_parity = {
            "baseline_app": str(baseline_app),
            "images_compared": len(baseline_diff),
            "byte_identical": exact_pairs,
            "cases": baseline_diff,
        }
        if not exact_pairs:
            raise RuntimeError("zero-strength Phase 6 legacy captures differ from frozen pre-Phase-6 baseline")

    manifests = {mode: run_results[mode][0][0] for mode in modes}
    cases = {mode: run_results[mode][0][1] for mode in modes}
    ab: dict[str, Any] = {}
    grading_deltas: dict[str, Any] = {}
    timeline = {
        mode: timeline_metrics(out / f"{mode}-repeat-1", cases[mode])
        for mode in modes if mode != SHADOW_CONTROL_MODE
    }
    if not args.legacy_only:
        for view in [entry[0] for entry in SKY_VIEWS] + [HIGH_VIEW[0]]:
            for time_s in TIMES:
                time_tag = f"t{time_s:03d}"
                legacy_id = f"legacy-{view}-{time_tag}"
                enhanced_id = f"enhanced-{view}-{time_tag}"
                legacy_case = cases["legacy"][legacy_id]
                enhanced_case = cases["enhanced"][enhanced_id]
                for key in ("view_id", "sim_time_s", "azimuth_deg", "elevation_deg", "camera_height_m", "camera_fov_deg", "visual_scope"):
                    if legacy_case.get(key) != enhanced_case.get(key):
                        raise RuntimeError(f"A/B case mismatch for {view} t={time_s}: {key}")
                ab[f"{view}-t{time_tag}"] = image_comparisons(
                    out / "legacy-repeat-1", legacy_case, out / "enhanced-repeat-1", enhanced_case
                )
                if args.grading:
                    graded_case = cases["graded"][f"graded-{view}-{time_tag}"]
                    for key in ("view_id", "sim_time_s", "azimuth_deg", "elevation_deg", "camera_height_m", "camera_fov_deg", "visual_scope"):
                        if enhanced_case.get(key) != graded_case.get(key):
                            raise RuntimeError(f"grading A/B case mismatch for {view} t={time_s}: {key}")
                    grading_deltas[f"{view}-t{time_tag}"] = image_comparisons(
                        out / "enhanced-repeat-1", enhanced_case, out / "graded-repeat-1", graded_case
                    )

    enhanced_t120_movement = []
    enhanced_ab_changes = []
    if not args.legacy_only:
        enhanced_t120_movement = [
            timeline["enhanced"][view]["t120_vs_t000"]["changed_pixels"]
            for view in [entry[0] for entry in SKY_VIEWS] + [HIGH_VIEW[0]]
        ]
        if max(enhanced_t120_movement, default=0) <= 0:
            raise RuntimeError("enhanced mode shows no image movement between t=0 and t=120 s")
        enhanced_ground_t120_movement = timeline["enhanced"][HIGH_VIEW[0]]["t120_vs_t000"]["ground_crop_lower_70pct"]["changed_pixels"]
        if enhanced_ground_t120_movement <= 0:
            raise RuntimeError("enhanced high-ground view shows no ground-crop movement between t=0 and t=120 s")
        enhanced_ab_changes = [item["changed_pixels"] for item in ab.values()]
        if max(enhanced_ab_changes, default=0) <= 0:
            raise RuntimeError("legacy and enhanced captures are pixel-identical across the complete set")
    grading_changes = [item["changed_pixels"] for item in grading_deltas.values()]
    if args.grading and max(grading_changes, default=0) <= 0:
        raise RuntimeError("graded and normal enhanced captures are pixel-identical across the complete set")

    shadow_reference_deltas: dict[str, Any] = {}
    shadow_reference_ground_changes: dict[str, int] = {}
    if not args.legacy_only:
        enhanced_manifest = manifests["enhanced"]
        shadow_manifest = manifests[SHADOW_CONTROL_MODE]
        if enhanced_manifest["production_knobs"] != shadow_manifest["production_knobs"]:
            raise RuntimeError("enhanced and shadow-off modes have different production parameters")
        enhanced_sky = enhanced_manifest["effective_knobs"]["sky"]
        shadow_sky = shadow_manifest["effective_knobs"]["sky"]
        if enhanced_sky != shadow_sky:
            raise RuntimeError("enhanced and shadow-off modes have different sky strengths")
        for time_s in SHADOW_CONTROL_TIMES:
            time_tag = f"t{time_s:03d}"
            enhanced_case = cases["enhanced"][f"enhanced-{HIGH_VIEW[0]}-{time_tag}"]
            shadow_case = cases[SHADOW_CONTROL_MODE][f"{SHADOW_CONTROL_MODE}-{HIGH_VIEW[0]}-{time_tag}"]
            for key in ("view_id", "sim_time_s", "azimuth_deg", "elevation_deg", "camera_height_m", "camera_fov_deg", "visual_scope"):
                if enhanced_case.get(key) != shadow_case.get(key):
                    raise RuntimeError(f"shadow-off comparison camera mismatch at {time_tag}: {key}")
            metrics = image_comparisons(
                out / "enhanced-repeat-1", enhanced_case,
                out / f"{SHADOW_CONTROL_MODE}-repeat-1", shadow_case,
            )
            shadow_reference_deltas[time_tag] = metrics
            shadow_reference_ground_changes[time_tag] = int(metrics["ground_crop_lower_70pct"]["changed_pixels"])
        if any(count <= 0 for count in shadow_reference_ground_changes.values()):
            raise RuntimeError("enhanced cloud shadows do not change the isolated ground crop at t=0 and t=120")

    source_after = {name: source_snapshot(project) for name, project in source_projects.items()}
    source_provenance = {
        name: source_guard_report(source_before[name], source_after[name])
        for name in source_projects
    }

    summary = {
        "format": SUMMARY_FORMAT,
        "complete": True,
        "production_scene": {
            "field": "FieldLoader.DEFAULT_PATH through FieldBuilder.build",
            "environment": "Atmosphere.environment",
            "sun": "Atmosphere.create_sun; production 225° azimuth, 45° elevation",
            "clock": "ShaderClock.update + Atmosphere.update_clouds at every requested time",
            "scenery": "off",
        },
        "source_provenance": source_provenance,
        "capture_set": {
            "modes": list(modes),
            "times_s": list(TIMES),
            "sky_views": [
                {"id": view[0], "azimuth_deg": view[1], "elevation_deg": view[2], "height_m": view[3]}
                for view in SKY_VIEWS
            ],
            "high_ground_view": {
                "id": HIGH_VIEW[0], "azimuth_deg": HIGH_VIEW[1], "elevation_deg": HIGH_VIEW[2], "height_m": HIGH_VIEW[3]
            },
            "shadow_control_times_s": list(SHADOW_CONTROL_TIMES),
            "captures_per_mode_per_repeat": {mode: len(expected_case_ids(mode)) for mode in modes},
            "candidate_pngs_across_two_repeats": sum(len(expected_case_ids(mode)) * 2 for mode in modes),
            "baseline_pngs_across_two_repeats": len(expected_case_ids("legacy")) * 2 if baseline_app is not None else 0,
            "shadow_strength_override": args.shadow_strength,
        },
        "ab_contract": {
            "legacy": "new sky strengths and ground cloud-shadow strength forced to zero; existing base cloud deck remains active",
            "enhanced": "production sky and ground strengths from Spec/Atmosphere; optional diagnostic shadow-strength override",
            "shadow_off": "same enhanced sky and ground parameters with only cloud_shadow_strength forced to zero; high-ground t=0/120 control",
            "whole_field": True,
        },
        "repeatability": repeatability,
        "production_knobs": {mode: manifests[mode]["production_knobs"] for mode in modes},
        "effective_knobs": {mode: manifests[mode]["effective_knobs"] for mode in modes},
        "ab_deltas": ab,
        "cloud_shadow_isolation": {
            "high_ground_enhanced_vs_shadow_off": shadow_reference_deltas,
            "lower_70pct_changed_pixels": shadow_reference_ground_changes,
            "passed": None if args.legacy_only else all(count > 0 for count in shadow_reference_ground_changes.values()),
        },
        "grading_experiment": {
            "enabled": args.grading,
            "parameters": GRADING_METADATA if args.grading else NEUTRAL_GRADING_METADATA,
            "enhanced_vs_graded_deltas": grading_deltas,
            "changed_pixel_count_by_case": {key: value["changed_pixels"] for key, value in grading_deltas.items()},
            "passed": None if not args.grading else max(grading_changes, default=0) > 0,
        },
        "timeline_deltas": timeline,
        "pre_phase6_baseline_parity": baseline_parity,
        "drift_gate": {
            "t120_enhanced_changed_pixels_by_view": dict(zip(
                [entry[0] for entry in SKY_VIEWS] + [HIGH_VIEW[0]], enhanced_t120_movement, strict=True
            )) if not args.legacy_only else {},
            "enhanced_ground_crop_t120_changed_pixels": 0 if args.legacy_only else enhanced_ground_t120_movement,
            "passed": None if args.legacy_only else max(enhanced_t120_movement, default=0) > 0,
            "ground_passed": None if args.legacy_only else enhanced_ground_t120_movement > 0,
            "meaning": "enhanced views change between t=0 and t=120 s, including at least one pixel in the lower 70% of the high-ground field view",
        },
        "ab_gate": {
            "changed_pixels_by_case": {key: value["changed_pixels"] for key, value in ab.items()},
            "passed": None if args.legacy_only else max(enhanced_ab_changes, default=0) > 0,
            "meaning": "at least one same-camera, same-time whole-field capture differs between legacy and enhanced modes",
        },
        "image_hashes": {
            mode: {case_id: case["image_metrics"]["sha256"] for case_id, case in cases[mode].items()}
            for mode in modes
        },
    }
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    total_per_repeat = sum(len(expected_case_ids(mode)) for mode in modes)
    print(f"Phase 6 atmosphere: {total_per_repeat} captures in each of two repeats; byte-identical within each mode")
    print(f"Report: {summary_path}")
    return 0


if __name__ == "__main__":
	try:
		raise SystemExit(main())
	except (OSError, RuntimeError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
		print(f"FAIL: {error}", file=sys.stderr)
		raise SystemExit(1)
