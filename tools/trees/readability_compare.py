"""Run/reduce the native tree readability matrix; reuse the established L6c metrics."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "app/tests"))
from compare_captures import difference_mask, load, measure_pair

AIRCRAFT = ("jensen-das-ugly-stik-60", "p51d-mustang-120")
BACKGROUNDS = ("sky", "trees")
DISTANCES_M = (20, 50, 100)
SHORT_POSES = ("level", "inverted")
LONG_POSES = ("level", "inverted", "knife_left", "knife_right", "climb", "dive")


def source_hashes(app: Path, *, exclude: Path | None = None) -> dict:
    app = app.resolve()
    excluded = exclude.resolve() if exclude is not None else None
    result = {}
    for path in sorted(app.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(app)
        if relative.suffix.lower() == ".uid" or any(part in {".godot", "__pycache__", "captures"} for part in relative.parts):
            continue
        resolved = path.resolve()
        if excluded is not None and (resolved == excluded or excluded in resolved.parents):
            continue
        result[relative.as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def preimport_app(godot: Path, app: Path, output: Path) -> None:
    command = [str(godot.resolve()), "--headless", "--path", str(app.resolve()), "--editor", "--import"]
    log_path = output / "preimport.log"
    with log_path.open("w") as log:
        process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, text=True, timeout=600)
    text = log_path.read_text()
    if process.returncode or re.search(r"^(SCRIPT |SHADER )?ERROR:", text, re.M):
        raise RuntimeError(f"Headless import failed for frozen app; see {log_path}")


def _checked_load(folder: Path, filename: str, expected_sha256: str, label: str) -> np.ndarray:
    if not isinstance(filename, str) or not isinstance(expected_sha256, str):
        raise ValueError(f"Missing {label} image path or SHA-256")
    relative = Path(filename)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"Invalid {label} image path: {filename}")
    root = folder.resolve()
    path = (root / relative).resolve()
    if path != root and root not in path.parents:
        raise ValueError(f"Image escapes capture folder: {filename}")
    if not expected_sha256 or hashlib.sha256(path.read_bytes()).hexdigest() != expected_sha256:
        raise ValueError(f"Changed or unhashed {label} image: {path}")
    return load(path)


def _validate_matrix(captures: list) -> None:
    expected = set()
    for aircraft in AIRCRAFT:
        for distance in DISTANCES_M:
            poses = SHORT_POSES if distance < 100 else LONG_POSES
            for background in BACKGROUNDS:
                for autozoom in (False, True):
                    for pose in poses:
                        expected.add((aircraft, distance, background, autozoom, pose))
    observed = set()
    for row in captures:
        if not isinstance(row, dict):
            raise ValueError("Invalid readability capture row")
        aircraft = row.get("aircraft")
        distance = row.get("requested_distance_m")
        background = row.get("requested_background")
        autozoom = row.get("autozoom")
        pose = row.get("pose")
        if not isinstance(aircraft, str) or type(distance) is not int or not isinstance(background, str) \
                or not isinstance(autozoom, bool) or not isinstance(pose, str):
            raise ValueError("Missing readability matrix coordinates")
        key = (aircraft, distance, background, autozoom, pose)
        if key not in expected:
            raise ValueError(f"Unexpected readability matrix case: {key}")
        if key in observed:
            raise ValueError(f"Duplicate readability matrix case: {key}")
        observed.add(key)
    missing = expected - observed
    if missing:
        raise ValueError(f"Readability matrix is missing {len(missing)} cases")


def reduce_capture(folder: Path) -> dict:
    manifest = json.loads((folder / "manifest.json").read_text())
    captures = manifest.get("captures")
    if manifest.get("format") != "openrc-tree-readability v1" or manifest.get("complete") is not True \
            or not isinstance(captures, list) or len(captures) != 80:
        raise ValueError("Incomplete readability matrix")
    _validate_matrix(captures)
    viewport = manifest.get("viewport")
    if not isinstance(viewport, list) or len(viewport) != 2 \
            or any(type(value) is not int or value <= 0 for value in viewport):
        raise ValueError("Invalid capture viewport")
    height = viewport[1]
    results = []
    for row in captures:
        camera = row.get("camera_transform")
        fov = row.get("fov_deg")
        distance = row.get("distance_m")
        projected_span = row.get("projected_span_px")
        if not isinstance(camera, list) or len(camera) != 12 \
                or any(not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value) for value in camera) \
                or not isinstance(fov, (int, float)) or isinstance(fov, bool) or not math.isfinite(fov) or not 0.0 < fov < 180.0 \
                or not isinstance(distance, (int, float)) or isinstance(distance, bool) or not math.isfinite(distance) or distance <= 0.0 \
                or not isinstance(projected_span, (int, float)) or isinstance(projected_span, bool) \
                or not math.isfinite(projected_span) or projected_span <= 0.0:
            raise ValueError("Invalid camera or projection metadata")
        actual = _checked_load(folder, row["png"], row.get("sha256", ""), "aircraft")
        background = _checked_load(folder, row["background_png"], row.get("background_sha256", ""), "background")
        without_trees = _checked_load(folder, row["without_trees_png"], row.get("without_trees_sha256", ""), "without-trees")
        if list(actual.shape[:2][::-1]) != viewport or actual.shape != background.shape or actual.shape != without_trees.shape:
            raise ValueError("Image dimensions disagree with capture")
        mask = difference_mask(actual, background)
        y, x = np.nonzero(mask)
        metrics = {"pixels": 0}
        if len(y):
            # Preserve the complete six-pixel metric ring while avoiding full-screen Lab conversions.
            top, bottom = max(0, int(y.min()) - 8), min(height, int(y.max()) + 9)
            left, right = max(0, int(x.min()) - 8), min(actual.shape[1], int(x.max()) + 9)
            crop = np.s_[top:bottom, left:right]
            tree_mask = difference_mask(background[crop], without_trees[crop])
            pitch = math.asin(max(-1.0, min(1.0, -camera[7])))
            horizon = height / 2 + (height / 2) / math.tan(math.radians(fov) / 2) * math.tan(pitch)
            metrics = measure_pair(actual[crop], background[crop], tree_mask, horizon - top)
            metrics["bbox_px"]["centre"][0] += left
            metrics["bbox_px"]["centre"][1] += top
        requested = row["requested_background"]
        share = metrics.get("background", {}).get(requested, 0.0)
        results.append({**row, "metrics": metrics,
                        "background_matches_request": share >= (0.6 if requested == "trees" else 0.9)})
    return {"format": "openrc-tree-readability-metrics v1", "captures": results,
            "viewport": viewport, "lighting": manifest["lighting"],
            "build_options": manifest.get("build_options", {}),
            "renderer": manifest.get("renderer"), "adapter": manifest.get("adapter"),
            "api": manifest.get("api"), "godot": manifest.get("godot"),
            "zero_pixel_cases": [r["png"] for r in results if r["metrics"]["pixels"] == 0],
            "background_mismatch_cases": [r["png"] for r in results if not r["background_matches_request"]],
            "scope": "Existing L6c pixel/contrast metrics. Missing pixels or mismatched backgrounds remain explicit failures of those cases. No human recognition score is inferred."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--reduce", type=Path)
    parser.add_argument("--lights", nargs="+", default=["noon", "low_sun", "sunset", "night"], choices=["noon", "low_sun", "sunset", "night"])
    parser.add_argument("--resolutions", nargs="+", type=int, default=[720, 1080], choices=[720, 1080])
    args = parser.parse_args()
    if args.out.exists():
        parser.error("Output must be new")
    if args.reduce:
        args.out.write_text(json.dumps(reduce_capture(args.reduce), indent=2) + "\n")
        return 0
    if not args.godot or not args.godot.is_file() or not args.app or not (args.app / "project.godot").is_file():
        parser.error("Require --godot and a frozen --app")
    args.out.mkdir(parents=True)
    app = args.app.resolve()
    args.out = args.out.resolve()
    preimport_app(args.godot, app, args.out)
    identity = source_hashes(app, exclude=args.out)
    (args.out / "source-identity.json").write_text(json.dumps({"app": identity,
        "engine_sha256": hashlib.sha256(args.godot.read_bytes()).hexdigest(),
        "fixture_sha256": hashlib.sha256(Path(__file__).with_name("readability_capture.gd").read_bytes()).hexdigest(),
        "reducer_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}, indent=2) + "\n")
    summary = []
    for resolution in args.resolutions:
        for light in args.lights:
            name = f"{light}-{resolution}"
            folder = args.out.resolve() / name
            command = [str(args.godot.resolve()), "--path", str(args.app.resolve()), "--audio-driver", "Dummy",
                       "--script", str(Path(__file__).with_name("readability_capture.gd")), "--",
                       f"--out={folder}", f"--light={light}"]
            if resolution == 1080:
                command.append("--1080")
            with (args.out / f"{name}.log").open("w") as log:
                process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=300)
            text = (args.out / f"{name}.log").read_text()
            if process.returncode or re.search(r"^(SCRIPT |SHADER )?ERROR:", text, re.M) or "TREE_READABILITY_OK" not in text:
                raise RuntimeError(f"Native capture failed: {name}")
            metrics = reduce_capture(folder)
            (args.out / f"{name}-metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
            summary.append({"case": name, "command": command, "captures": len(metrics["captures"]),
                            "zero_pixel_cases": metrics["zero_pixel_cases"],
                            "background_mismatch_cases": metrics["background_mismatch_cases"]})
            print(f"{name}: {len(metrics['captures'])} captures; {len(metrics['zero_pixel_cases'])} invisible, {len(metrics['background_mismatch_cases'])} background mismatches", flush=True)
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    if source_hashes(app, exclude=args.out) != identity:
        raise RuntimeError("Source changed during capture; reject this comparison")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
