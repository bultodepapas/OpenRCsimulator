#!/usr/bin/env python3
"""Capture actual RC ground activity closeups and bounded render timings."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "app"
SCRIPT = ROOT / "research" / "rc-monster-truck" / "ground-closeup" / "capture.gd"
GODOT_DEFAULT = ROOT / ".tools" / "Godot_v4.7.2-stable_win64.exe"
VERIFICATION = ROOT / "docs" / "research" / "rc-ground-implementation-2026-10-15" / "verification"

SOURCE_FILES = (
    "app/project.godot",
    "app/vehicles/ground/ground_scene.gd",
    "app/vehicles/ground/airfield_track_view.gd",
    "app/vehicles/ground/ground_camera.gd",
    "app/vehicles/ground/mt8_model.gd",
    "app/vehicles/ground/monster_car_2_model.gd",
    "app/vehicles/ground/vehicle_catalog.gd",
    "app/render/ground.gd",
    "app/render/ground.gdshader",
    "app/render/rc_ground_detail.gdshaderinc",
    "app/render/rc_ground_material.gd",
    "app/render/grass_surface.gdshaderinc",
    "app/render/turf_detail.gdshaderinc",
    "app/render/cloud_field.gdshaderinc",
    "app/scenery/gravel.gdshader",
    "app/data/fields/default.json",
    "app/data/fields/lake.json",
    "app/data/ground_vehicle/airfield_track.json",
    "app/data/ground/surface_friction.json",
    "app/data/vehicles/ground/mt8_bisonte.json",
    "app/data/vehicles/ground/monster_car_2.json",
    "research/rc-monster-truck/ground-closeup/capture.gd",
    "research/rc-monster-truck/ground-closeup/run.py",
)

VEHICLES = ("mt8-bisonte", "monster-car-2")
SPAWNS = ("start", "track_start", "track_rollers", "shore")
CAMERAS = ("chase", "low-orbit")
LIGHTINGS = ("day", "night")
RESOLUTIONS = ("1280x720", "1920x1080", "2048x1080", "2560x1440", "3840x2160")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def hash_sources(paths: tuple[str, ...] | list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for relative in paths:
        path = ROOT / relative
        result[relative] = sha256_file(path) if path.is_file() else "missing"
    return result


def parse_resolution(value: str) -> tuple[int, int]:
    try:
        width, height = (int(part) for part in value.lower().split("x", 1))
    except (ValueError, TypeError) as exc:
        raise argparse.ArgumentTypeError("resolution must be WIDTHxHEIGHT") from exc
    if width < 640 or height < 360 or width > 3840 or height > 2160:
        raise argparse.ArgumentTypeError("resolution must fit within 640x360..3840x2160")
    return width, height


def safe_case_id(vehicle: str, spawn: str, camera: str, lighting: str) -> str:
    value = f"{vehicle}__{spawn}__{camera}__{lighting}"
    return re.sub(r"[^A-Za-z0-9_-]+", "-", value)


def percentile(values: list[float], quantile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    location = (len(ordered) - 1) * quantile
    lower = int(location)
    upper = min(lower + 1, len(ordered) - 1)
    fraction = location - lower
    return ordered[lower] * (1.0 - fraction) + ordered[upper] * fraction


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"cannot read JSON evidence {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"JSON evidence is not an object: {path}")
    return value


def load_receipts(output_dir: Path) -> list[dict[str, Any]]:
    receipts = []
    for path in sorted(output_dir.glob("*.json")):
        if path.name in {"manifest.json", "summary.json", "godot-summary.json", "capture-plan.json",
                         "parity.json", "texture-source-hashes.json"}:
            continue
        value = read_json(path)
        if value.get("format") == "openrc-ground-closeup-capture-v1":
            receipts.append(value)
    return receipts


def receipt_summary(receipts: list[dict[str, Any]]) -> dict[str, Any]:
    cases = []
    for receipt in receipts:
        timings = [float(value) for value in receipt.get("frame_ms", [])]
        draws = [float(value) for value in receipt.get("draw_calls", [])]
        cases.append({
            "case_id": receipt.get("case_id"),
            "complete": bool(receipt.get("complete", False)),
            "image": receipt.get("image"),
            "image_sha256": receipt.get("image_sha256"),
            "vehicle_id": receipt.get("vehicle_id"),
            "spawn_id": receipt.get("physical", {}).get("spawn_id"),
            "camera_mode": receipt.get("camera_mode"),
            "lighting": receipt.get("lighting"),
            "state_sha256": receipt.get("physical", {}).get("state_sha256_after_capture"),
            "tick": receipt.get("physical", {}).get("tick"),
            "preconditioning": receipt.get("preconditioning"),
            "frame_ms": {
                "count": len(timings),
                "p50": percentile(timings, 0.50),
                "p95": percentile(timings, 0.95),
                "p99": percentile(timings, 0.99),
            },
            "draw_calls": {
                "count": len(draws),
                "p50": percentile(draws, 0.50),
                "p95": percentile(draws, 0.95),
                "p99": percentile(draws, 0.99),
            },
            "mesh_signature_sha256": receipt.get("mesh_diagnostics", {}).get("mesh_signature_sha256"),
            "mesh_geometry_signature_sha256": receipt.get("mesh_diagnostics", {}).get("mesh_geometry_signature_sha256"),
            "unique_texture_count": receipt.get("mesh_diagnostics", {}).get("unique_texture_count"),
        })
    complete = all(case["complete"] for case in cases) and bool(cases)
    return {
        "format": "openrc-ground-closeup-summary-v1",
        "complete": complete,
        "case_count": len(cases),
        "cases": cases,
    }


def texture_source_hashes(receipts: list[dict[str, Any]]) -> dict[str, str]:
    paths: set[str] = set()
    for receipt in receipts:
        for texture in receipt.get("mesh_diagnostics", {}).get("textures", []):
            resource_path = str(texture.get("resource_path", ""))
            if resource_path.startswith("res://"):
                relative = resource_path.removeprefix("res://")
                local = APP / Path(relative)
                if local.is_file():
                    paths.add(local.relative_to(ROOT).as_posix())
    return hash_sources(sorted(paths))


def compare_physical_states(baseline_dir: Path, candidate_receipts: list[dict[str, Any]]) -> dict[str, Any]:
    baseline_manifest = read_json(baseline_dir / "manifest.json")
    if baseline_manifest.get("variant") != "baseline":
        raise RuntimeError("--compare-dir must point to a baseline capture directory")
    baseline_receipts = {
        str(receipt.get("case_id")): receipt for receipt in load_receipts(baseline_dir)
    }
    comparisons = []
    for candidate in candidate_receipts:
        case_id = str(candidate.get("case_id"))
        baseline = baseline_receipts.get(case_id)
        if baseline is None:
            comparisons.append({"case_id": case_id, "matched": False, "state_exact": False})
            continue
        before = baseline.get("physical", {})
        after = candidate.get("physical", {})
        same_state = before.get("state_f64") == after.get("state_f64")
        same_state_hash = before.get("state_sha256_after_capture") == after.get("state_sha256_after_capture")
        same_model = before.get("model") == after.get("model")
        same_identities = before.get("identities") == after.get("identities")
        same_solver = before.get("solver_identity") == after.get("solver_identity")
        same_mesh_geometry = (
            baseline.get("mesh_diagnostics", {}).get("mesh_geometry_signature_sha256")
            == candidate.get("mesh_diagnostics", {}).get("mesh_geometry_signature_sha256")
        )
        comparisons.append({
            "case_id": case_id,
            "matched": True,
            "state_exact": same_state and same_state_hash,
            "model_exact": same_model,
            "identities_exact": same_identities,
            "solver_identity_exact": same_solver,
            "mesh_geometry_exact": same_mesh_geometry,
            "baseline_state_sha256": before.get("state_sha256_after_capture"),
            "candidate_state_sha256": after.get("state_sha256_after_capture"),
            "baseline_tick": before.get("tick"),
            "candidate_tick": after.get("tick"),
        })
    return {
        "format": "openrc-ground-closeup-physical-parity-v1",
        "baseline_dir": str(baseline_dir),
        "candidate_case_count": len(candidate_receipts),
        "matched_case_count": sum(bool(row.get("matched")) for row in comparisons),
        "state_exact_all": bool(comparisons) and all(bool(row.get("state_exact")) for row in comparisons),
        "model_exact_all": bool(comparisons) and all(bool(row.get("model_exact")) for row in comparisons),
        "identities_exact_all": bool(comparisons) and all(bool(row.get("identities_exact")) for row in comparisons),
        "solver_identity_exact_all": bool(comparisons) and all(bool(row.get("solver_identity_exact")) for row in comparisons),
        "mesh_geometry_exact_all": bool(comparisons) and all(bool(row.get("mesh_geometry_exact")) for row in comparisons),
        "cases": comparisons,
    }


def encode_pan_clips(output_dir: Path, receipts: list[dict[str, Any]]) -> dict[str, Any]:
    ffmpeg = shutil.which("ffmpeg")
    clips: dict[str, Any] = {"ffmpeg": ffmpeg, "encoded": [], "unencoded_sequences": []}
    if not ffmpeg:
        clips["note"] = "ffmpeg not found; bounded PNG pan sequences are retained."
        return clips
    for receipt in receipts:
        frames = receipt.get("pan_frames", [])
        if not frames:
            continue
        case_id = str(receipt.get("case_id", "case"))
        target = output_dir / f"{case_id}__pan.mp4"
        command = [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-framerate", "24",
            "-i", str(output_dir / f"{case_id}__pan_%03d.png"),
            "-frames:v", str(len(frames)),
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            str(target),
        ]
        completed = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                                   errors="replace", check=False)
        if completed.returncode == 0 and target.is_file():
            clips["encoded"].append({
                "case_id": case_id,
                "path": target.name,
                "sha256": sha256_file(target),
                "frame_count": len(frames),
            })
        else:
            clips["unencoded_sequences"].append({
                "case_id": case_id,
                "frame_count": len(frames),
                "error": completed.stderr.strip() or f"ffmpeg exited {completed.returncode}",
            })
    return clips


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Capture the actual Bisonte / Monster Car 2 ground scene without overwriting evidence."
    )
    parser.add_argument("--variant", required=True, choices=("baseline", "candidate"))
    parser.add_argument("--output-dir", type=Path,
                        help="fresh output directory below docs/research/rc-ground-implementation-2026-10-15/verification/")
    parser.add_argument("--godot", type=Path, default=GODOT_DEFAULT)
    parser.add_argument("--vehicle", action="append", choices=(*VEHICLES, "all"),
                        help="repeat to select both vehicle types; defaults to both")
    parser.add_argument("--spawn", action="append", choices=SPAWNS,
                        help="repeat to select supported aliases; defaults to start, track_start, track_rollers, shore")
    parser.add_argument("--camera", action="append", choices=CAMERAS,
                        help="repeat to select chase and/or low-orbit; defaults to both")
    parser.add_argument("--lighting", action="append", choices=LIGHTINGS,
                        help="repeat for day and/or night; defaults to day")
    parser.add_argument("--resolution", type=parse_resolution, default=(1280, 720),
                        metavar="WIDTHxHEIGHT", help="1280x720, 2K, or 4K output")
    parser.add_argument("--frames", type=int, default=120, help="measured rendered frames (1..600)")
    parser.add_argument("--warmup-frames", type=int, default=60, help="unmeasured rendered warmup frames (1..300)")
    parser.add_argument("--ticks", type=int, default=0,
                        help="optional deterministic Session preconditioning with neutral arm then throttle .25 (0..240)")
    parser.add_argument("--pan-frames", type=int, default=0,
                        help="optional low-orbit yaw sweep PNG sequence (0 or 12..120 frames)")
    parser.add_argument("--capture-only", action="store_true",
                        help="render images after warmup without collecting frame timings")
    parser.add_argument("--timeout", type=int, default=600, help="Godot timeout in seconds (30..1200)")
    parser.add_argument("--compare-dir", type=Path,
                        help="baseline evidence directory to compare exact candidate physical state")
    parser.add_argument("--parse-only", action="store_true",
                        help="ask Godot to parse/preload the harness in headless mode, without opening a scene")
    args = parser.parse_args(argv)
    if args.frames < 1 or args.frames > 600:
        parser.error("--frames must be in the bounded range 1..600")
    if args.warmup_frames < 1 or args.warmup_frames > 300:
        parser.error("--warmup-frames must be in the bounded range 1..300")
    if args.ticks < 0 or args.ticks > 240:
        parser.error("--ticks must be in the bounded range 0..240")
    if args.pan_frames != 0 and not 12 <= args.pan_frames <= 120:
        parser.error("--pan-frames must be zero or in the bounded range 12..120")
    if args.timeout < 30 or args.timeout > 1200:
        parser.error("--timeout must be in the bounded range 30..1200 seconds")
    if args.compare_dir and args.variant != "candidate":
        parser.error("--compare-dir is only valid for --variant=candidate")
    if args.capture_only:
        args.frames = 0
    return args


def create_output_dir(requested: Path | None, variant: str) -> Path:
    VERIFICATION.mkdir(parents=True, exist_ok=True)
    if requested is None:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        requested = VERIFICATION / f"ground-closeup-{variant}-{stamp}"
    elif not requested.is_absolute():
        requested = ROOT / requested
    resolved = requested.resolve()
    try:
        resolved.relative_to(VERIFICATION.resolve())
    except ValueError as exc:
        raise RuntimeError("output directory must stay under the configured verification evidence directory") from exc
    if resolved.exists():
        raise RuntimeError(f"output directory must be fresh and absent: {resolved}")
    resolved.mkdir(parents=True, exist_ok=False)
    return resolved


def build_cases(vehicles: list[str], spawns: list[str], cameras: list[str],
                lightings: list[str]) -> list[dict[str, str]]:
    cases = []
    for vehicle in vehicles:
        for spawn in spawns:
            for camera in cameras:
                for lighting in lightings:
                    cases.append({
                        "id": safe_case_id(vehicle, spawn, camera, lighting),
                        "vehicle_id": vehicle,
                        "spawn": spawn,
                        "camera": camera,
                        "lighting": lighting,
                    })
    if len(cases) > 64:
        raise RuntimeError("case matrix exceeds the bounded 64-case limit")
    return cases


def godot_command(godot: Path, plan_path: Path | None, parse_only: bool) -> list[str]:
    command = [str(godot), "--path", str(APP)]
    if parse_only:
        command.extend(["--headless", "--script", str(SCRIPT), "--", "--validate-only"])
        return command
    command.extend([
        "--position=-16000,-16000",
        "--audio-driver=Dummy",
        "--script", str(SCRIPT),
        "--", f"--plan={plan_path}",
    ])
    return command


def run_godot(command: list[str], timeout: int, output_dir: Path | None = None) -> tuple[int, str]:
    creationflags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    try:
        completed = subprocess.run(
            command,
            cwd=APP,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
            creationflags=creationflags,
        )
        text_output = completed.stdout + ("\n" if completed.stdout and completed.stderr else "") + completed.stderr
        return completed.returncode, text_output
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout.decode("utf-8", errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode("utf-8", errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        text_output = stdout + ("\n" if stdout and stderr else "") + stderr + "\nTIMEOUT\n"
        if output_dir is not None:
            (output_dir / "godot.log").write_text(text_output, encoding="utf-8")
        return 124, text_output
    except OSError as exc:
        return 127, f"could not run Godot: {exc}\n"


def run(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    godot = args.godot if args.godot.is_absolute() else ROOT / args.godot
    if not godot.is_file():
        print(f"Godot executable not found: {godot}", file=sys.stderr)
        return 2
    if args.parse_only:
        command = godot_command(godot, None, True)
        code, output = run_godot(command, args.timeout)
        sys.stdout.write(output)
        print(f"Harness parse {'passed' if code == 0 else 'failed'} (exit {code}).")
        return code

    vehicles = args.vehicle or list(VEHICLES)
    if "all" in vehicles:
        if len(vehicles) > 1:
            print("--vehicle=all cannot be combined with another --vehicle", file=sys.stderr)
            return 2
        vehicles = list(VEHICLES)
    spawns = args.spawn or list(SPAWNS)
    cameras = args.camera or list(CAMERAS)
    lightings = args.lighting or ["day"]
    try:
        cases = build_cases(vehicles, spawns, cameras, lightings)
        if len(cases) * (args.frames + args.warmup_frames) > 48_000:
            raise RuntimeError("requested rendered frame count exceeds the bounded 48,000-frame limit")
        output_dir = create_output_dir(args.output_dir, args.variant)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if args.compare_dir:
        compare_dir = args.compare_dir if args.compare_dir.is_absolute() else ROOT / args.compare_dir
        compare_dir = compare_dir.resolve()
        try:
            compare_dir.relative_to(VERIFICATION.resolve())
        except ValueError:
            print("--compare-dir must point within the verification evidence directory", file=sys.stderr)
            return 2
        if not compare_dir.is_dir():
            print(f"baseline directory not found: {compare_dir}", file=sys.stderr)
            return 2
    else:
        compare_dir = None

    source_before = hash_sources(SOURCE_FILES)
    plan = {
        "format": "openrc-ground-closeup-plan-v1",
        "variant": args.variant,
        "output_dir": str(output_dir),
        "resolution": list(args.resolution),
        "frames": args.frames,
        "warmup_frames": args.warmup_frames,
        "ticks": args.ticks,
        "pan_frames": args.pan_frames,
        "cases": cases,
    }
    (output_dir / "capture-plan.json").write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
    manifest = {
        "format": "openrc-ground-closeup-manifest-v1",
        "variant": args.variant,
        "output_dir": str(output_dir),
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "native offscreen Godot renderer; production ground activity; no simulation during render timing; optional deterministic Session preconditioning is recorded separately",
        "physical_validation": False,
        "resolution": list(args.resolution),
        "frames": args.frames,
        "capture_only": args.capture_only,
        "warmup_frames": args.warmup_frames,
        "ticks": args.ticks,
        "pan_frames": args.pan_frames,
        "case_count": len(cases),
        "cases": cases,
        "source_sha256_before": source_before,
        "godot_executable": str(godot),
        "compare_dir": str(compare_dir) if compare_dir else None,
        "renderer_requirement": "normal native renderer at offscreen window position; never --headless",
        "bounds": {
            "max_cases": 64,
            "max_rendered_frames_total": 48000,
            "max_timing_frames_per_case": 600,
            "max_warmup_frames_per_case": 300,
            "max_preconditioning_ticks": 240,
            "max_pan_frames_per_case": 120,
            "timeout_seconds": args.timeout,
        },
    }
    (output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    command = godot_command(godot, output_dir / "capture-plan.json", False)
    print(f"Capturing {len(cases)} {args.variant} case(s) into {output_dir}")
    print("Godot uses the native renderer with its window positioned at -16000,-16000.")
    code, output = run_godot(command, args.timeout, output_dir)
    (output_dir / "godot.log").write_text(output, encoding="utf-8")
    sys.stdout.write(output)

    receipts = load_receipts(output_dir)
    summary = receipt_summary(receipts)
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    texture_hashes = texture_source_hashes(receipts)
    (output_dir / "texture-source-hashes.json").write_text(
        json.dumps(texture_hashes, indent=2) + "\n", encoding="utf-8")
    clips = encode_pan_clips(output_dir, receipts)
    (output_dir / "pan-clips.json").write_text(json.dumps(clips, indent=2) + "\n", encoding="utf-8")

    source_after = hash_sources(SOURCE_FILES)
    manifest["source_sha256_after"] = source_after
    manifest["sources_stable_during_run"] = source_before == source_after
    manifest["actual_render_success"] = code == 0 and summary["complete"]
    manifest["texture_source_sha256"] = texture_hashes
    (output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    parity = None
    if compare_dir is not None:
        try:
            parity = compare_physical_states(compare_dir, receipts)
        except RuntimeError as exc:
            print(str(exc), file=sys.stderr)
            return 2
        (output_dir / "parity.json").write_text(json.dumps(parity, indent=2) + "\n", encoding="utf-8")
        print(f"Physical state exact across baseline/candidate: {parity['state_exact_all']}")

    if code != 0:
        print(f"Godot capture exited with {code}; see {output_dir / 'godot.log'}", file=sys.stderr)
    if not summary["complete"]:
        print("One or more captures are incomplete; see summary.json and per-case receipts.", file=sys.stderr)
    if source_before != source_after:
        print("Capture source changed while Godot was running; this run is not comparable.", file=sys.stderr)
    if parity is not None and not parity["state_exact_all"]:
        print("Candidate physical states differ from baseline; see parity.json.", file=sys.stderr)
    return 0 if code == 0 and summary["complete"] and source_before == source_after \
        and (parity is None or (parity["state_exact_all"] and parity["mesh_geometry_exact_all"])) else 1


if __name__ == "__main__":
    raise SystemExit(run())
