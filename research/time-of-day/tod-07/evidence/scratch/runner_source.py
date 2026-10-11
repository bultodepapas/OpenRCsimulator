#!/usr/bin/env python3
"""Capture the TOD-07 fixed-time visual matrix from a real Godot project tree.

This runner lives outside app/ so it cannot alter the product. It requires an
explicit --run because a software-renderer capture matrix is an intentional,
multi-process operation. Image patches are located from capture metadata; they
are not a segmented aircraft silhouette or a photometric measurement.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from PIL import Image, ImageStat
except ImportError as exc:  # pragma: no cover - dependency guard
    raise SystemExit("TOD-07 captures require Pillow (python3 -m pip install Pillow)") from exc


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_AIRCRAFT = "jensen-das-ugly-stik-60"
AIRCRAFT = {
    DEFAULT_AIRCRAFT: {"name": "Jensen Das Ugly Stik 60", "span_m": 1.52},
    "gp-extra-300s-60": {"name": "Great Planes Extra 300S .60", "span_m": 1.63},
    "p51d-mustang-120": {"name": "P-51D Mustang 1/4", "span_m": 2.82},
    "sebart-avanti-s-a200-p100rx": {"name": "SebArt Avanti S", "span_m": 2.00},
}
DATE = "2026-03-20"
TIMES = ["00:00", "05:45", "06:00", "12:00", "18:00", "18:30"]
ENGINE_ERROR = re.compile(r"(?m)^\s*(?:ERROR|SCRIPT ERROR|SHADER ERROR):")


@dataclass(frozen=True)
class Case:
    case_id: str
    aircraft_id: str
    clock: str | None
    mode: str
    label: str


def matrix_cases() -> list[Case]:
    cases = [Case("legacy-default", DEFAULT_AIRCRAFT, None, "legacy", "pre-change pixel baseline")]
    for clock in TIMES:
        cases.append(Case(f"default-{clock.replace(':', '-')}", DEFAULT_AIRCRAFT, clock,
                          "astronomical", "default aircraft time sweep"))
    # The default aircraft's 00:00 and 12:00 captures above also satisfy its
    # night/noon pair. Add both endpoints for each other catalog aircraft.
    for aircraft_id in AIRCRAFT:
        if aircraft_id == DEFAULT_AIRCRAFT:
            continue
        for clock, label in [("12:00", "noon"), ("00:00", "night")]:
            cases.append(Case(f"{aircraft_id}-{label}", aircraft_id, clock,
                              "astronomical", f"{label} aircraft view"))
    return cases


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def decoded_pixel_diff(left: Path, right: Path) -> dict[str, Any]:
    with Image.open(left) as source, Image.open(right) as reference:
        a = source.convert("RGB")
        b = reference.convert("RGB")
        if a.size != b.size:
            return {"exact": False, "dimensions_match": False, "current_size": list(a.size),
                    "baseline_size": list(b.size), "changed_pixels": None,
                    "max_channel_delta": None, "mean_absolute_channel_delta": None}
        raw_a, raw_b = a.tobytes(), b.tobytes()
        changed_pixels = 0
        max_delta = 0
        total_delta = 0
        for offset in range(0, len(raw_a), 3):
            pixel_changed = False
            for channel in range(3):
                delta = abs(raw_a[offset + channel] - raw_b[offset + channel])
                total_delta += delta
                max_delta = max(max_delta, delta)
                pixel_changed = pixel_changed or delta != 0
            changed_pixels += int(pixel_changed)
        pixel_count = a.width * a.height
        return {
            "exact": changed_pixels == 0,
            "dimensions_match": True,
            "current_size": list(a.size),
            "baseline_size": list(b.size),
            "changed_pixels": changed_pixels,
            "max_channel_delta": max_delta,
            "mean_absolute_channel_delta": total_delta / (pixel_count * 3),
        }


def dot(a: list[float], b: list[float]) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def patch_metrics(image: Image.Image, center_x: float, center_y: float,
                  half_width: int, half_height: int) -> dict[str, Any]:
    width, height = image.size
    x0 = max(0, int(math.floor(center_x)) - half_width)
    y0 = max(0, int(math.floor(center_y)) - half_height)
    x1 = min(width, int(math.floor(center_x)) + half_width + 1)
    y1 = min(height, int(math.floor(center_y)) + half_height + 1)
    if x0 >= x1 or y0 >= y1:
        raise ValueError("projected capture ROI is outside the rendered image")
    stats = ImageStat.Stat(image.crop((x0, y0, x1, y1)))
    red, green, blue = stats.mean
    return {
        "box_xyxy": [x0, y0, x1, y1],
        "pixel_count": (x1 - x0) * (y1 - y0),
        "mean_rgb_code_0_255": [red, green, blue],
        "mean_rec709_code_luma_0_255": 0.2126 * red + 0.7152 * green + 0.0722 * blue,
    }


def metadata_rois(image_path: Path, metadata: dict[str, Any]) -> dict[str, Any]:
    evidence = metadata["visual_evidence"]
    camera = evidence["camera"]
    camera_transform = camera["transform"]
    aircraft_transform = evidence["pose"]
    camera_position = [float(v) for v in camera_transform["position"]]
    aircraft_position = [float(v) for v in aircraft_transform["position"]]
    relative = [aircraft_position[i] - camera_position[i] for i in range(3)]
    camera_basis = [[float(v) for v in column] for column in camera_transform["basis_columns"]]
    local = [dot(relative, column) for column in camera_basis]
    depth = -local[2]
    if depth <= 0.0:
        raise ValueError("aircraft metadata projects behind the camera")

    with Image.open(image_path) as source:
        image = source.convert("RGB")
    width, height = image.size
    viewport = [int(round(float(v))) for v in camera["viewport"]]
    if viewport != [width, height]:
        raise ValueError(f"metadata viewport {viewport} differs from PNG dimensions {[width, height]}")
    fov = math.radians(float(camera["fov_deg"]))
    focal_px = height / (2.0 * math.tan(fov / 2.0))
    center_x = width / 2.0 + local[0] * focal_px / depth
    center_y = height / 2.0 - local[1] * focal_px / depth
    span = float(AIRCRAFT[evidence["aircraft"]]["span_m"])
    projected_span_px = span * focal_px / depth
    # The patch is a small context box around the model origin, sized from its
    # catalog span and measured camera depth. It intentionally includes some
    # surrounding pixels; it is not represented as an exact mesh mask.
    half_width = max(12, int(math.ceil(projected_span_px * 1.5)))
    half_height = max(10, int(math.ceil(projected_span_px)))
    background_x = center_x + 3 * half_width + 5
    if background_x + half_width >= width:
        background_x = center_x - 3 * half_width - 5
    aircraft_patch = patch_metrics(image, center_x, center_y, half_width, half_height)
    background_patch = patch_metrics(image, background_x, center_y, half_width, half_height)
    plane_luma = aircraft_patch["mean_rec709_code_luma_0_255"]
    background_luma = background_patch["mean_rec709_code_luma_0_255"]
    return {
        "method": "model origin projected from capture metadata; square patch spans are estimated from catalog wing span, camera depth and FOV; background patch is adjacent at the same screen height",
        "projected_aircraft_origin_px": [center_x, center_y],
        "camera_depth_m": depth,
        "catalog_span_m": span,
        "projected_span_px": projected_span_px,
        "aircraft_context_patch": aircraft_patch,
        "background_patch": background_patch,
        "aircraft_minus_background_luma_code": plane_luma - background_luma,
        "absolute_luma_separation_code": abs(plane_luma - background_luma),
    }


def resolve_godot(explicit: str | None) -> Path:
    if explicit:
        path = Path(explicit).expanduser().resolve()
        if not path.is_file():
            raise FileNotFoundError(f"Godot binary does not exist: {path}")
        return path
    script = ROOT / "app" / "get-godot.sh"
    result = subprocess.run([str(script)], cwd=ROOT, text=True, capture_output=True, check=True)
    path = Path(result.stdout.strip().splitlines()[-1]).expanduser().resolve()
    if not path.is_file():
        raise FileNotFoundError(f"app/get-godot.sh returned a missing binary: {path}")
    return path


def case_arguments(case: Case, image_path: Path) -> list[str]:
    args = ["--scripted", "--capture", "--t=1.5", "--autozoom=0"]
    if case.aircraft_id != DEFAULT_AIRCRAFT:
        args.append(f"--aircraft={case.aircraft_id}")
    if case.clock is not None:
        args.extend([f"--time-of-day={case.clock}", f"--date={DATE}", f"--case=tod07-{case.case_id}"])
    args.append(f"--out={image_path}")
    return args


def prepare_xdg(root: Path) -> dict[str, str]:
    env = os.environ.copy()
    for name in ["config", "cache", "data", "state"]:
        folder = root / name
        folder.mkdir(parents=True, exist_ok=True)
        env[f"XDG_{name.upper()}_HOME"] = str(folder)
    env["LP_NUM_THREADS"] = "1"
    return env


def verify_metadata(case: Case, metadata: dict[str, Any]) -> None:
    evidence = metadata.get("visual_evidence", {})
    lighting = evidence.get("lighting", {})
    config = lighting.get("config", {})
    if evidence.get("aircraft") != case.aircraft_id:
        raise ValueError(f"capture selected {evidence.get('aircraft')!r}, expected {case.aircraft_id!r}")
    if config.get("mode") != case.mode:
        raise ValueError(f"capture lighting mode {config.get('mode')!r}, expected {case.mode!r}")
    if case.clock is not None:
        if config.get("date") != DATE:
            raise ValueError(f"capture date {config.get('date')!r}, expected {DATE!r}")
        seconds = int(config.get("local_seconds", -1))
        expected = sum(int(part) * factor for part, factor in zip(case.clock.split(":"), [3600, 60]))
        if seconds != expected:
            raise ValueError(f"capture local seconds {seconds}, expected {expected} for {case.clock}")
        if not config.get("location_name", "").endswith("(synthetic)"):
            raise ValueError("astronomical capture does not identify its synthetic reference location")


def sha_manifest(evidence_dir: Path, script_path: Path) -> Path:
    output = evidence_dir / "SHA256SUMS"
    files = sorted(p for p in evidence_dir.rglob("*") if p.is_file() and p != output)
    files.append(script_path)
    lines = [f"{file_sha256(path)}  {path}\n" for path in files]
    output.write_text("".join(lines), encoding="utf-8")
    return output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "app",
                        help="Godot project tree to capture (supports a scratch copy)")
    parser.add_argument("--godot", help="pinned Godot binary; defaults to app/get-godot.sh")
    parser.add_argument("--out-dir", type=Path, required=True, help="new or existing output folder")
    parser.add_argument("--baseline", type=Path, default=ROOT / "research/time-of-day/tod-01/evidence/legacy-production.png",
                        help="pre-change TOD-01 PNG used for decoded-pixel comparison")
    parser.add_argument("--xdg-root", type=Path, default=Path("/tmp/openrc-tod07-xdg"),
                        help="isolated user-data root for direct captures")
    parser.add_argument("--only", action="append", default=[], help="run only a case ID; repeatable")
    parser.add_argument("--run", action="store_true", help="required acknowledgement before launching captures")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.run:
        print("No captures started. Re-run with --run after the target project is ready.", file=sys.stderr)
        return 2
    project = args.project.expanduser().resolve()
    if not (project / "project.godot").is_file():
        raise FileNotFoundError(f"not a Godot project: {project}")
    baseline = args.baseline.expanduser().resolve()
    if not baseline.is_file():
        raise FileNotFoundError(f"baseline PNG does not exist: {baseline}")
    godot = resolve_godot(args.godot)
    if shutil.which("xvfb-run") is None:
        raise FileNotFoundError("xvfb-run is required for the isolated 1280x720 capture matrix")

    cases = matrix_cases()
    if args.only:
        known = {case.case_id for case in cases}
        unknown = set(args.only) - known
        if unknown:
            raise ValueError(f"unknown case IDs: {', '.join(sorted(unknown))}")
        selected = set(args.only)
        cases = [case for case in cases if case.case_id in selected]

    out_dir = args.out_dir.expanduser().resolve()
    images_dir = out_dir / "images"
    logs_dir = out_dir / "logs"
    images_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)
    xdg_root = args.xdg_root.expanduser().resolve()
    env = prepare_xdg(xdg_root)
    summary: dict[str, Any] = {
        "format": "openrc-tod-07-capture-matrix v1",
        "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "project_root": str(project),
        "project_kind": "scratch" if "/tmp/" in str(project) else "working-tree",
        "godot_binary": str(godot),
        "baseline_png": str(baseline),
        "baseline_sha256": file_sha256(baseline),
        "renderer_request": "opengl3 / Compatibility",
        "software_renderer_note": "llvmpipe measurements are reproducible software-renderer evidence, not target-GPU performance or physical validation",
        "date": DATE,
        "reference_location": "Reference field (synthetic), latitude 0°, longitude 0°, UTC offset 0",
        "planned_full_matrix_cases": [case.case_id for case in matrix_cases()],
        "ui_capture": "skipped: current Home has no TOD selection control or capture seam",
        "captures": [],
    }
    report_path = out_dir / "summary.json"
    baseline_diff: dict[str, Any] | None = None

    for index, case in enumerate(cases, 1):
        image_path = images_dir / f"{case.case_id}.png"
        metadata_path = image_path.with_suffix(".json")
        log_path = logs_dir / f"{case.case_id}.log"
        for stale in [image_path, metadata_path, log_path]:
            if stale.exists():
                stale.unlink()
        user_args = case_arguments(case, image_path)
        command = [
            "xvfb-run", "-a", "-s", "-screen 0 1280x720x24",
            str(godot), "--path", str(project), "--rendering-driver", "opengl3",
            "--audio-driver", "Dummy", "--", *user_args,
        ]
        started = time.monotonic()
        result = subprocess.run(command, cwd=project, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        elapsed = time.monotonic() - started
        log_path.write_text(result.stdout, encoding="utf-8")
        if result.returncode != 0:
            raise RuntimeError(f"capture {case.case_id} exited {result.returncode}; see {log_path}")
        if ENGINE_ERROR.search(result.stdout):
            raise RuntimeError(f"capture {case.case_id} logged an engine/script/shader error; see {log_path}")
        if not image_path.is_file() or not metadata_path.is_file():
            raise RuntimeError(f"capture {case.case_id} did not produce both PNG and JSON metadata; see {log_path}")

        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        verify_metadata(case, metadata)
        record: dict[str, Any] = {
            "case_id": case.case_id,
            "label": case.label,
            "aircraft_id": case.aircraft_id,
            "lighting_mode": case.mode,
            "local_time": case.clock,
            "date": DATE if case.clock else None,
            "capture_seconds": round(elapsed, 4),
            "png": str(image_path.relative_to(out_dir)),
            "png_sha256": file_sha256(image_path),
            "metadata": str(metadata_path.relative_to(out_dir)),
            "metadata_sha256": file_sha256(metadata_path),
            "renderer": metadata.get("renderer"),
            "adapter": metadata.get("adapter"),
            "api": metadata.get("api"),
            "godot": metadata.get("godot"),
            "draw_calls": metadata.get("draw_calls"),
            "primitives": metadata.get("primitives"),
            "visual_lighting": metadata["visual_evidence"]["lighting"],
            "roi": metadata_rois(image_path, metadata),
            "log": str(log_path.relative_to(out_dir)),
        }
        if case.case_id == "legacy-default":
            baseline_diff = decoded_pixel_diff(image_path, baseline)
            record["baseline_pixel_comparison"] = baseline_diff
        summary["captures"].append(record)
        summary["last_updated_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        report_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"[{index}/{len(cases)}] {case.case_id}: {record['png_sha256'][:12]}  {elapsed:.2f}s")

    summary["completed_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    summary["legacy_pixel_exact"] = bool(baseline_diff and baseline_diff.get("exact", False))
    summary["run_status"] = "complete"
    report_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    manifest = sha_manifest(out_dir, Path(__file__).resolve())
    print(f"matrix complete: {len(summary['captures'])} capture(s), legacy pixel exact={summary['legacy_pixel_exact']}")
    print(f"summary: {report_path}")
    print(f"checksums: {manifest}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"TOD-07 matrix failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
