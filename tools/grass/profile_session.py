#!/usr/bin/env python3
"""Collect paired interactive native frame-time profiles for grass quality."""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
from typing import Any, Sequence


ROOT = Path(__file__).resolve().parents[2]
PERFORMANCE_DIR = ROOT / "research" / "performance"
if str(PERFORMANCE_DIR) not in sys.path:
    sys.path.insert(0, str(PERFORMANCE_DIR))

import native_summary  # noqa: E402


FORMAT = "openrc-grass-native-profile v1"
GRASS_SELECTOR = "OPENRC_GRASS_QUALITY"
DEFAULT_GODOT = ROOT / ".tools" / "Godot_v4.8-beta1_win64_console.exe"
EXPECTED_GODOT_PREFIX = "4.8-beta1 (official)"
EXPECTED_WINDOW = "1280x720"
EXPECTED_VIEWPORT = [1280, 720]
EXPECTED_BACKEND = "gl_compatibility"
EXPECTED_MSAA_3D = 2  # Viewport.MSAA_4X in Godot 4.7.2.
WARMUP_SECONDS = 10
SAMPLE_SECONDS = 60
MAX_FPS = 60
MINIMUM_PAIRS = 5
DEFAULT_TIMEOUT_SECONDS = 180
PROCESS_INVENTORY_TIMEOUT_SECONDS = 10

APP_RUNTIME_SUFFIXES = {
    ".cfg", ".godot", ".gd", ".gdshader", ".gdshaderinc", ".gdextension",
    ".gltf", ".glb", ".bin", ".obj", ".mtl", ".import", ".json", ".mp3", ".ogg",
    ".dll", ".so", ".dylib",
    ".po", ".png", ".res", ".svg", ".tscn", ".tres", ".scn", ".ttf",
    ".otf", ".wav", ".webp", ".jpg", ".jpeg",
}
APP_EXCLUDED_DIRS = {
    ".godot", ".tools", "__pycache__", ".pytest_cache", "cache", "caches",
    "captures", "docs", "doc", "test", "tests", "build", "dist",
}
IDENTITY_KEYS = (
    "godot", "os", "backend", "adapter", "api", "aircraft_id", "window",
    "vsync", "render_settings", "effective_grass_shared",
)

EXPECTED_GRASS_COUNTS = {
    "default": {"grass_common_short": 67, "grass_common_tall": 42, "grass_wispy_tall": 41},
    "enhanced": {"grass_common_short": 100, "grass_common_tall": 30, "grass_wispy_tall": 20},
}
EXPECTED_GRASS_SOURCE_TRIANGLES = {"default": 49_579, "enhanced": 37_720}
EXPECTED_GROUND_GRASS_PHOTO = {"default": False, "enhanced": True}
EXPECTED_GROUND_TEXTURE_BINDINGS = {
    "turf_detail": "res://assets/landscape/turf/detail.png",
    "rc_grass_albedo": "res://assets/landscape/rc-ground/grass-albedo.jpg",
    "rc_grass_normal": "res://assets/landscape/rc-ground/grass-normal.jpg",
    "rc_grass_roughness": "res://assets/landscape/rc-ground/grass-roughness.jpg",
}


class CampaignStop(RuntimeError):
    """A measurement cannot safely continue or compare with the other variant."""


class ProcessInventoryError(RuntimeError):
    """The host process list could not be checked within the bounded preflight."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _canonical_hash(value: Any) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def engine_binary_snapshot(godot: Path) -> dict[str, str]:
    """The Windows console executable launches the sibling engine executable."""
    binaries = [godot.resolve()]
    if godot.name.lower().endswith("_console.exe"):
        binaries.append(godot.with_name(godot.name[:-len("_console.exe")] + ".exe").resolve())
    return {str(path): sha256_file(path) for path in binaries}


def app_runtime_snapshot(app: Path) -> dict[str, Any]:
    """Hash runtime sources, settings, and assets; skip cache, docs, and tests."""
    app = app.resolve()
    files: dict[str, str] = {}
    for current, directories, filenames in os.walk(app):
        directories[:] = sorted(
            name for name in directories if name.casefold() not in APP_EXCLUDED_DIRS
        )
        current_path = Path(current)
        for filename in sorted(filenames):
            path = current_path / filename
            if path.suffix.casefold() not in APP_RUNTIME_SUFFIXES:
                continue
            files[path.relative_to(app).as_posix()] = sha256_file(path)
    return {
        "app": str(app),
        "runtime_file_count": len(files),
        "files_sha256": files,
        "file_map_sha256": _canonical_hash(files),
    }


def source_snapshots_match(before: dict[str, Any], after: dict[str, Any]) -> bool:
    return before.get("files_sha256") == after.get("files_sha256")


def provenance_rejection_reasons(
    app_before: dict[str, Any], app_after: dict[str, Any], engine_hash_before: str, engine_hash_after: str,
) -> list[str]:
    reasons: list[str] = []
    if not source_snapshots_match(app_before, app_after):
        reasons.append("app runtime source/config changed during the campaign")
    if engine_hash_before != engine_hash_after:
        reasons.append("Godot executable changed during the campaign")
    return reasons


def ensure_new_output(out: Path, app: Path) -> Path:
    """Create an output directory only when it does not already exist."""
    output = out.resolve()
    application = app.resolve()
    if output.exists():
        raise ValueError(f"output must be a new path; refusing to reuse: {output}")
    if output == application or output in application.parents or application in output.parents:
        raise ValueError("output and app paths must be separate so evidence cannot enter the runtime snapshot")
    output.mkdir(parents=True, exist_ok=False)
    return output


def validate_pair_count(pairs: int) -> None:
    if type(pairs) is not int or pairs < MINIMUM_PAIRS:
        raise ValueError(f"pairs must be at least {MINIMUM_PAIRS}; got {pairs!r}")


def pair_order(pair_index: int) -> tuple[str, str]:
    if pair_index < 1:
        raise ValueError("pair index is one-based")
    return ("default", "enhanced") if pair_index % 2 else ("enhanced", "default")


def child_environment(variant: str, parent: dict[str, str] | None = None) -> dict[str, str]:
    if variant not in ("default", "enhanced"):
        raise ValueError(f"unknown grass profile {variant!r}")
    environment = dict(os.environ if parent is None else parent)
    environment.pop(GRASS_SELECTOR, None)
    if variant == "enhanced":
        environment[GRASS_SELECTOR] = "enhanced"
    return environment


def build_command(godot: Path, app: Path, report_path: Path) -> list[str]:
    """Construct a normal visible live-input launch, with no input/focus automation."""
    return [
        str(godot.resolve()),
        "--path", str(app.resolve()),
        "--rendering-method", EXPECTED_BACKEND,
        "--rendering-driver", "opengl3",
        "--resolution", EXPECTED_WINDOW,
        "--max-fps", str(MAX_FPS),
        "--",
        f"--frametimes={report_path.resolve().as_posix()}",
        f"--warmup={WARMUP_SECONDS}",
        f"--t={SAMPLE_SECONDS}",
        "--start=airborne",
        "--autozoom=0",
        "--view=pilot",
        "--scenery=on",
        "--scenery_quality=high",
    ]


def godot_process_inventory() -> dict[str, Any]:
    """List Godot process images once, with a bounded OS-native command."""
    system = platform.system()
    if system == "Windows":
        command = ["tasklist", "/FO", "CSV", "/NH"]
        scope = "tasklist CSV image names containing 'godot'"
        run_options: dict[str, Any] = {
            "capture_output": True,
            "text": True,
            "timeout": PROCESS_INVENTORY_TIMEOUT_SECONDS,
            "check": False,
            "creationflags": getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000),
        }
    elif system in {"Linux", "Darwin", "FreeBSD", "OpenBSD", "NetBSD"}:
        command = ["ps", "-A", "-o", "pid=,comm="]
        scope = "ps process command names containing 'godot'"
        run_options = {
            "capture_output": True,
            "text": True,
            "timeout": PROCESS_INVENTORY_TIMEOUT_SECONDS,
            "check": False,
        }
    else:
        raise ProcessInventoryError(f"process inventory unavailable for operating system {system!r}")

    try:
        result = subprocess.run(command, **run_options)
    except (OSError, UnicodeError, subprocess.SubprocessError) as error:
        raise ProcessInventoryError(f"cannot run bounded process inventory {command!r}: {error}") from error
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise ProcessInventoryError(
            f"process inventory command {command!r} exited {result.returncode}: {detail}"
        )

    godot_processes: list[dict[str, str]] = []
    if system == "Windows":
        try:
            rows = csv.reader(result.stdout.splitlines())
            for row in rows:
                if len(row) < 2:
                    continue
                image = row[0].strip()
                if "godot" in image.replace("\\", "/").rsplit("/", 1)[-1].casefold():
                    godot_processes.append({"image": image, "pid": row[1].strip()})
        except csv.Error as error:
            raise ProcessInventoryError(f"tasklist returned invalid CSV: {error}") from error
    else:
        for line in result.stdout.splitlines():
            fields = line.strip().split(None, 1)
            if len(fields) < 2:
                continue
            pid, image = fields[0], fields[1].strip()
            if "godot" in image.replace("\\", "/").rsplit("/", 1)[-1].casefold():
                godot_processes.append({"image": image, "pid": pid})

    return {
        "status": "available",
        "platform": system,
        "scope": scope,
        "command": command,
        "timeout_s": PROCESS_INVENTORY_TIMEOUT_SECONDS,
        "godot_processes": godot_processes,
    }


def validate_report_contract(report: dict[str, Any], variant: str) -> list[str]:
    """Check the effective render route after the shared reducer accepts the report."""
    errors: list[str] = []
    if report.get("route") != "live-input":
        errors.append("effective frametime route is not live-input")
    if report.get("godot") != EXPECTED_GODOT_PREFIX:
        errors.append(f"runtime is not Godot {EXPECTED_GODOT_PREFIX} official beta1 build")
    if report.get("backend") != EXPECTED_BACKEND:
        errors.append(f"backend is not {EXPECTED_BACKEND}")
    if report.get("window") != EXPECTED_WINDOW:
        errors.append(f"window is not {EXPECTED_WINDOW}")
    camera = report.get("camera")
    if not isinstance(camera, dict):
        camera = {}
        errors.append("camera metadata is missing")
    if camera.get("viewport") != EXPECTED_VIEWPORT:
        errors.append("effective viewport is not 1280x720")
    if camera.get("autozoom") is not False:
        errors.append("effective camera autozoom is not off")
    if camera.get("mode") != "pilot":
        errors.append("effective camera mode is not pilot")
    render_settings = report.get("render_settings")
    if not isinstance(render_settings, dict) or render_settings.get("msaa_3d") != EXPECTED_MSAA_3D:
        errors.append("effective 3D MSAA is not 4x")
    errors.extend(validate_effective_grass_state(report, variant))
    return errors


def validate_effective_grass_state(report: dict[str, Any], variant: str) -> list[str]:
    """Require the built scene to match this variant's grass profile and shared field settings."""
    errors: list[str] = []
    if variant not in EXPECTED_GRASS_COUNTS:
        return [f"unknown grass profile variant {variant!r}"]
    state = report.get("effective_grass")
    if not isinstance(state, dict):
        return ["effective grass scene metadata is missing"]
    if state.get("format") != "openrc-effective-grass-state v1":
        errors.append("effective grass scene metadata format is unsupported")
    if state.get("verified") is not True:
        details = state.get("errors")
        suffix = ": " + "; ".join(str(item) for item in details) if isinstance(details, list) and details else ""
        errors.append("effective grass scene bindings are unverified" + suffix)

    scenery = state.get("scenery")
    if not isinstance(scenery, dict) or scenery.get("enabled") is not True:
        errors.append("effective scenery is not enabled")
    if not isinstance(scenery, dict) or scenery.get("quality") != "high":
        errors.append("effective scenery quality is not high")

    ground = state.get("ground")
    if not isinstance(ground, dict):
        ground = {}
        errors.append("effective ground grass metadata is missing")
    if ground.get("shader_path") != "res://render/ground.gdshader":
        errors.append("effective ground shader is not the production ground shader")
    if not isinstance(ground.get("shader_sha256"), str) or len(ground["shader_sha256"]) != 64:
        errors.append("effective ground shader source hash is missing")
    if ground.get("grass_photo_enabled") is not EXPECTED_GROUND_GRASS_PHOTO[variant]:
        expected = "enabled" if EXPECTED_GROUND_GRASS_PHOTO[variant] else "disabled"
        errors.append(f"effective ground grass photo detail is not {expected} for {variant}")
    if ground.get("turf_detail_enabled") is not True or ground.get("turf_detail_strength") != 1.0:
        errors.append("effective ground turf detail is not enabled at full strength")
    if not isinstance(ground.get("material_count"), int) or ground["material_count"] <= 0:
        errors.append("effective ground material bindings are missing")
    texture_bindings = ground.get("texture_bindings")
    _require_ground_texture_binding(
        texture_bindings, "turf_detail", EXPECTED_GROUND_TEXTURE_BINDINGS["turf_detail"], errors
    )
    if EXPECTED_GROUND_GRASS_PHOTO[variant]:
        for uniform_name in ("rc_grass_albedo", "rc_grass_normal", "rc_grass_roughness"):
            _require_ground_texture_binding(
                texture_bindings,
                uniform_name,
                EXPECTED_GROUND_TEXTURE_BINDINGS[uniform_name],
                errors,
            )

    near_grass = state.get("near_grass")
    if not isinstance(near_grass, dict):
        near_grass = {}
        errors.append("effective NearGrass metadata is missing")
    if near_grass.get("present") is not True or near_grass.get("route") != "imported":
        errors.append("effective NearGrass route is not imported")
    if near_grass.get("quality") != "high":
        errors.append("effective NearGrass quality is not high")
    if near_grass.get("material_variant") != ("qualified-wind" if variant == "enhanced" else "source-static"):
        errors.append(f"effective NearGrass material variant is incorrect for {variant}")
    if near_grass.get("grass_wind") is not (variant == "enhanced"):
        errors.append(f"effective NearGrass wind shader state is incorrect for {variant}")
    expected_shader_paths = ["res://scenery/imported_grass.gdshader"] if variant == "enhanced" else []
    if near_grass.get("shader_paths") != expected_shader_paths:
        errors.append(f"effective NearGrass shader path is incorrect for {variant}")
    material_bindings = near_grass.get("material_bindings")
    expected_material_class = "ShaderMaterial" if variant == "enhanced" else "StandardMaterial3D"
    if not isinstance(material_bindings, list) or not material_bindings:
        errors.append("effective NearGrass material bindings are missing")
    else:
        for binding in material_bindings:
            if not isinstance(binding, dict) or binding.get("class") != expected_material_class:
                errors.append(f"effective NearGrass active material class is incorrect for {variant}")
                break
            expected_path = expected_shader_paths[0] if variant == "enhanced" else ""
            if binding.get("shader_path") != expected_path:
                errors.append(f"effective NearGrass active material shader is incorrect for {variant}")
                break
            if variant == "enhanced" and (not isinstance(binding.get("shader_sha256"), str) or len(binding["shader_sha256"]) != 64):
                errors.append("effective NearGrass shader source hash is missing")
                break
    if near_grass.get("species_counts") != EXPECTED_GRASS_COUNTS[variant]:
        errors.append(f"effective NearGrass species counts are incorrect for {variant}")
    if near_grass.get("batch_count") != 3 or near_grass.get("clump_count") != 150:
        errors.append("effective NearGrass batch or clump count is incorrect")
    if near_grass.get("source_triangles") != EXPECTED_GRASS_SOURCE_TRIANGLES[variant]:
        errors.append(f"effective NearGrass source triangle count is incorrect for {variant}")
    if not isinstance(near_grass.get("texture_paths"), list) or not near_grass["texture_paths"]:
        errors.append("effective NearGrass source textures are missing")
    return errors


def _require_ground_texture_binding(
    bindings: Any, uniform_name: str, expected_path: str, errors: list[str]
) -> None:
    """Require the expected texture in its actual shader slot, not just in a path set."""
    binding = bindings.get(uniform_name) if isinstance(bindings, dict) else None
    if (
        not isinstance(binding, dict)
        or binding.get("bound") is not True
        or binding.get("resource_path") != expected_path
    ):
        errors.append(f"effective ground {uniform_name} texture binding is not {expected_path}")


def run_rejection_reasons(
    run: dict[str, Any], summary: dict[str, Any], report_errors: Sequence[str] = (),
) -> list[str]:
    """Reject collection or active-flight failures, but retain eligible pacing misses."""
    reasons: list[str] = []
    if run.get("timed_out"):
        reasons.append("process timed out")
    if run.get("interrupted"):
        reasons.append("process was interrupted")
    if run.get("launch_error"):
        reasons.append(f"process could not start: {run['launch_error']}")
    if run.get("return_code") != 0:
        reasons.append(f"process exit code was {run.get('return_code')!r}, expected 0")
    if not summary.get("collection_valid"):
        collection_reasons = summary.get("collection_reasons")
        reasons.extend(
            collection_reasons
            if isinstance(collection_reasons, list) and collection_reasons
            else ["native report collection is invalid"]
        )
    if not summary.get("active_flight_qualifier"):
        active_reasons = summary.get("active_flight_reasons")
        reasons.extend(
            active_reasons
            if isinstance(active_reasons, list) and active_reasons
            else ["run is not active-flight eligible"]
        )
    duration = summary.get("duration_eligibility")
    if not isinstance(duration, dict) or not duration.get("eligible"):
        duration_reasons = duration.get("reasons") if isinstance(duration, dict) else None
        reasons.extend(
            duration_reasons
            if isinstance(duration_reasons, list) and duration_reasons
            else ["run does not meet native duration policy"]
        )
    reasons.extend(report_errors)
    return list(dict.fromkeys(str(reason) for reason in reasons))


def report_identity(report: dict[str, Any]) -> dict[str, Any]:
    identity = {key: report.get(key) for key in IDENTITY_KEYS if key != "effective_grass_shared"}
    state = report.get("effective_grass")
    if not isinstance(state, dict):
        identity["effective_grass_shared"] = None
        return identity
    scenery = state.get("scenery") if isinstance(state.get("scenery"), dict) else {}
    ground = state.get("ground") if isinstance(state.get("ground"), dict) else {}
    near_grass = state.get("near_grass") if isinstance(state.get("near_grass"), dict) else {}
    identity["effective_grass_shared"] = {
        "scenery_enabled": scenery.get("enabled"),
        "scenery_quality": scenery.get("quality"),
        "ground_shader_path": ground.get("shader_path"),
        "near_grass_route": near_grass.get("route"),
        "near_grass_quality": near_grass.get("quality"),
        "near_grass_batch_count": near_grass.get("batch_count"),
        "near_grass_clump_count": near_grass.get("clump_count"),
    }
    return identity


def compare_identity(reference: dict[str, Any], candidate: dict[str, Any]) -> list[str]:
    return [key for key in IDENTITY_KEYS if reference.get(key) != candidate.get(key)]


def _run_metrics(summary: dict[str, Any]) -> dict[str, Any]:
    metrics = summary.get("metrics")
    if not isinstance(metrics, dict) or not isinstance(metrics.get("frame_ms"), dict):
        return {}
    return {
        "frame_ms": metrics["frame_ms"],
        "simulation_wall_ratio": metrics.get("simulation_wall_ratio"),
        "sample_simulation_span_s": metrics.get("sample_simulation_span_s"),
        "sample_simulation_ticks": metrics.get("sample_simulation_ticks"),
        "max_nonadvancing_interval_usec": metrics.get("max_nonadvancing_interval_usec"),
    }


def paired_comparison(pairs: Sequence[dict[str, Any]]) -> dict[str, Any]:
    deltas: dict[str, list[float]] = {"p95": [], "p99": []}
    pair_rows: list[dict[str, Any]] = []
    for pair in pairs:
        runs = pair.get("runs", {})
        default = runs.get("default", {}).get("metrics", {}).get("frame_ms", {})
        enhanced = runs.get("enhanced", {}).get("metrics", {}).get("frame_ms", {})
        row: dict[str, Any] = {"pair": pair.get("pair")}
        for percentile in ("p95", "p99"):
            difference = float(enhanced[percentile]) - float(default[percentile])
            deltas[percentile].append(difference)
            row[f"enhanced_minus_default_{percentile}_ms"] = difference
        pair_rows.append(row)
    median_deltas = {
        percentile: statistics.median(values) if values else None
        for percentile, values in deltas.items()
    }
    return {
        "complete_pair_count": len(pairs),
        "minimum_pairs_required": MINIMUM_PAIRS,
        "minimum_pairs_met": len(pairs) >= MINIMUM_PAIRS,
        "delta_sign": "enhanced minus default; negative means lower measured frame time with enhanced",
        "per_pair": pair_rows,
        "median_paired_delta_ms": median_deltas,
        "decision_scope": "comparative evidence only; no grass-only global-budget pass is inferred",
    }


def _write_campaign(path: Path, campaign: dict[str, Any]) -> None:
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(campaign, stream, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")
    temporary.replace(path)


def _terminate_process(process: subprocess.Popen[bytes]) -> int | None:
    if process.poll() is not None:
        return process.returncode
    try:
        process.terminate()
    except OSError:
        pass
    try:
        return process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            process.kill()
        except OSError:
            pass
        return process.wait()


def _launch_and_summarize(
    *, variant: str, pair_index: int, order_index: int, godot: Path, app: Path,
    report_path: Path, log_path: Path, environment: dict[str, str], timeout_s: int,
) -> dict[str, Any]:
    command = build_command(godot, app, report_path)
    started = utc_now()
    return_code: int | None = None
    timed_out = False
    interrupted = False
    launch_error = ""
    process: subprocess.Popen[bytes] | None = None
    try:
        with log_path.open("wb") as log:
            try:
                process = subprocess.Popen(command, cwd=str(app), env=environment, stdout=log, stderr=subprocess.STDOUT)
                try:
                    return_code = process.wait(timeout=timeout_s)
                except subprocess.TimeoutExpired:
                    timed_out = True
                    return_code = _terminate_process(process)
                except KeyboardInterrupt:
                    interrupted = True
                    return_code = _terminate_process(process)
            except OSError as error:
                launch_error = str(error)
                log.write((f"profile_session launch error: {error}\n").encode("utf-8", errors="replace"))
    except OSError as error:
        launch_error = str(error)

    # This reducer reads the same-stem log and report, and is called even after
    # an abort/timeout so partial evidence is classified and retained.
    summary = native_summary.summarize_run(report_path, native_summary.DEFAULT_POLICY)
    raw_report: dict[str, Any] = {}
    report_errors: list[str] = []
    if report_path.is_file():
        try:
            loaded = json.loads(report_path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                raw_report = loaded
                report_errors.extend(validate_report_contract(raw_report, variant))
            else:
                report_errors.append("frame-time report root is not an object")
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            report_errors.append(f"frame-time report cannot be read: {error}")
    else:
        report_errors.append("frame-time report is missing")

    pacing_gate = summary.get("pacing_gate")
    run: dict[str, Any] = {
        "id": f"pair-{pair_index:02d}-{variant}",
        "pair": pair_index,
        "order_in_pair": order_index,
        "variant": variant,
        "started_utc": started,
        "finished_utc": utc_now(),
        "command": command,
        "working_directory": str(app.resolve()),
        "grass_selector": "unset" if variant == "default" else "enhanced",
        "report": report_path.relative_to(report_path.parents[2]).as_posix(),
        "log": log_path.relative_to(log_path.parents[2]).as_posix(),
        "return_code": return_code,
        "timed_out": timed_out,
        "interrupted": interrupted,
        "launch_error": launch_error,
        "native_summary": summary,
        "metrics": _run_metrics(summary),
        "individual_pacing_pass": pacing_gate.get("pass") if isinstance(pacing_gate, dict) else None,
        "report_contract_errors": report_errors,
    }
    run["rejection_reasons"] = run_rejection_reasons(run, summary, report_errors)
    run["eligible_for_pair"] = not run["rejection_reasons"]
    run["report_identity"] = report_identity(raw_report) if raw_report else {}
    return run


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=DEFAULT_GODOT, help="pinned Godot 4.8-beta1 binary")
    parser.add_argument("--app", type=Path, default=ROOT / "app", help="Godot app checkout to profile")
    parser.add_argument("--out", type=Path, required=True, help="new output directory; existing paths are refused")
    parser.add_argument("--pairs", type=int, default=MINIMUM_PAIRS, help="complete AB/BA pairs (minimum 5; default 5)")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_SECONDS, help="per-process timeout in seconds")
    return parser


def run_campaign(args: argparse.Namespace) -> dict[str, Any]:
    validate_pair_count(args.pairs)
    if args.timeout <= 0:
        raise ValueError("timeout must be a positive number of seconds")
    app = args.app.resolve()
    godot = args.godot.resolve()
    if not (app / "project.godot").is_file():
        raise ValueError(f"app path has no project.godot: {app}")
    if not godot.is_file():
        raise ValueError(f"Godot binary not found: {godot}")
    output = ensure_new_output(args.out, app)

    engine_hash_before = sha256_file(godot)
    engine_binaries_before = engine_binary_snapshot(godot)
    app_before = app_runtime_snapshot(app)
    campaign_path = output / "campaign.json"
    campaign: dict[str, Any] = {
        "format": FORMAT,
        "status": "in_progress",
        "complete": False,
        "started_utc": utc_now(),
        "finished_utc": None,
        "app": str(app),
        "godot": {
            "path": str(godot),
            "expected_version_prefix": EXPECTED_GODOT_PREFIX,
            "sha256_before": engine_hash_before,
            "sha256_after": None,
            "binary_files_sha256_before": engine_binaries_before,
            "binary_files_sha256_after": None,
        },
        "app_runtime_snapshot": {"before": app_before, "after": None, "unchanged": None},
        "host": {"platform": platform.platform(), "machine": platform.machine()},
        "parameters": {
            "route": "live-input",
            "warmup_s": WARMUP_SECONDS,
            "sample_s": SAMPLE_SECONDS,
            "resolution": EXPECTED_WINDOW,
            "max_fps_argument": MAX_FPS,
            "backend": EXPECTED_BACKEND,
            "msaa_3d": "4x",
            "start": "airborne",
            "autozoom": False,
            "camera": "pilot",
            "scenery": "on",
            "scenery_quality": "high",
            "pairs_requested": args.pairs,
            "pair_order": "default/enhanced on odd pairs; enhanced/default on even pairs",
            "timeout_s_per_process": args.timeout,
            "reducer_policy": dict(native_summary.DEFAULT_POLICY),
        },
        "verification_limits": {
            "live_input_route": "checked against the frametime report route field",
            "camera_autozoom_and_mode": "checked against effective camera metadata",
            "scenery_enabled_and_quality": "observed from the built field's Scenery node stats at report serialization; the runner requires enabled/high and a verified effective snapshot",
            "grass_selector": "observed from active ground and NearGrass render bindings at report serialization; the runner checks per-variant grass settings plus shared route, material, and instance invariants",
        },
        "environment_delta": {
            GRASS_SELECTOR: {"default": "unset", "enhanced": "enhanced"},
            "other_variables": "inherited unchanged from the invoking process",
        },
        "runs": [],
        "process_preflights": [],
        "pairs": [],
        "comparison": None,
        "stop_reason": None,
        "acceptance": "not claimed; owner input-tape, hardware and overall-budget gates are independent",
    }
    _write_campaign(campaign_path, campaign)

    reference_identity: dict[str, Any] | None = None
    stop_reason = ""
    try:
        for pair_index in range(1, args.pairs + 1):
            order = pair_order(pair_index)
            pair_record: dict[str, Any] = {"pair": pair_index, "order": list(order), "status": "in_progress", "runs": {}}
            campaign["pairs"].append(pair_record)
            _write_campaign(campaign_path, campaign)
            for order_index, variant in enumerate(order, start=1):
                report_dir = output / "runs" / variant
                report_dir.mkdir(parents=True, exist_ok=True)
                stem = f"run-{pair_index:02d}-{variant}"
                report_path = report_dir / f"{stem}.json"
                log_path = report_path.with_suffix(".log")
                attempt = {"pair": pair_index, "variant": variant, "report": str(report_path), "log": str(log_path)}
                campaign["current_attempt"] = attempt
                try:
                    preflight = godot_process_inventory()
                except ProcessInventoryError as error:
                    preflight = {
                        "status": "unavailable",
                        "platform": platform.system(),
                        "scope": "unavailable",
                        "command": None,
                        "timeout_s": PROCESS_INVENTORY_TIMEOUT_SECONDS,
                        "godot_processes": [],
                        "error": str(error),
                    }
                preflight_record = {
                    "pair": pair_index,
                    "variant": variant,
                    "checked_utc": utc_now(),
                    **preflight,
                }
                campaign["process_preflights"].append(preflight_record)
                attempt["process_preflight"] = preflight_record
                _write_campaign(campaign_path, campaign)

                process_list = preflight.get("godot_processes", [])
                if preflight.get("status") != "available":
                    reason = (
                        f"Godot process preflight unavailable before {attempt['variant']} in pair {pair_index}: "
                        f"{preflight.get('error', 'inventory status unavailable')}; no launch was attempted "
                        "and the current pair is not qualified"
                    )
                elif process_list:
                    process_labels = ", ".join(
                        f"PID {item.get('pid', '?')} ({item.get('image', 'Godot')})"
                        for item in process_list
                    )
                    reason = (
                        f"Godot process preflight found another process before {attempt['variant']} "
                        f"in pair {pair_index}: {process_labels}; no launch was attempted and the current pair "
                        "is not qualified"
                    )
                else:
                    reason = ""
                if reason:
                    pair_record["status"] = "stopped_preflight"
                    pair_record["qualified"] = False
                    pair_record["stop_reason"] = reason
                    campaign["status"] = "stopped"
                    campaign["stop_reason"] = reason
                    campaign["comparison"] = paired_comparison(
                        [pair for pair in campaign["pairs"] if pair.get("status") == "complete"]
                    )
                    campaign.pop("current_attempt", None)
                    _write_campaign(campaign_path, campaign)
                    stop_reason = reason
                    raise CampaignStop(stop_reason)

                print(
                    f"Pair {pair_index}/{args.pairs}, {variant}: start the live flight in the visible Godot window; "
                    "do not use scripted input or change focus/pause behavior.",
                    flush=True,
                )
                run = _launch_and_summarize(
                    variant=variant, pair_index=pair_index, order_index=order_index,
                    godot=godot, app=app, report_path=report_path, log_path=log_path,
                    environment=child_environment(variant), timeout_s=args.timeout,
                )
                campaign["runs"].append(run)
                pair_record["runs"][variant] = run["id"]
                campaign.pop("current_attempt", None)
                if reference_identity is None and run["report_identity"]:
                    reference_identity = run["report_identity"]
                elif run["report_identity"] and reference_identity is not None:
                    changed_identity = compare_identity(reference_identity, run["report_identity"])
                    if changed_identity:
                        run["rejection_reasons"].append("run identity differs across the campaign: " + ", ".join(changed_identity))
                        run["eligible_for_pair"] = False
                if run["rejection_reasons"]:
                    pair_record["status"] = "stopped_ineligible"
                    pair_record["stop_reason"] = run["rejection_reasons"]
                    stop_reason = f"{run['id']} rejected: " + "; ".join(run["rejection_reasons"])
                    campaign["status"] = "stopped"
                    campaign["stop_reason"] = stop_reason
                    campaign["comparison"] = paired_comparison(
                        [pair for pair in campaign["pairs"] if pair.get("status") == "complete"]
                    )
                    _write_campaign(campaign_path, campaign)
                    raise CampaignStop(stop_reason)
                # Preserve eligible pacing failures as evidence; only collection,
                # duration, active-flight, or identity failures stop acquisition.
                if run["interrupted"]:
                    stop_reason = "campaign interrupted by the operator"
                    pair_record["status"] = "stopped_interrupted"
                    pair_record["qualified"] = False
                    pair_record["stop_reason"] = stop_reason
                    campaign["status"] = "stopped"
                    campaign["complete"] = False
                    campaign["stop_reason"] = stop_reason
                    raise CampaignStop(stop_reason)

            default_id = pair_record["runs"]["default"]
            enhanced_id = pair_record["runs"]["enhanced"]
            runs_by_id = {run["id"]: run for run in campaign["runs"]}
            default_metrics = runs_by_id[default_id]["metrics"]["frame_ms"]
            enhanced_metrics = runs_by_id[enhanced_id]["metrics"]["frame_ms"]
            pair_record["status"] = "complete"
            pair_record["runs"] = {
                "default": runs_by_id[default_id],
                "enhanced": runs_by_id[enhanced_id],
            }
            pair_record["paired_delta_ms"] = {
                percentile: float(enhanced_metrics[percentile]) - float(default_metrics[percentile])
                for percentile in ("p95", "p99")
            }
            campaign["comparison"] = paired_comparison(
                [pair for pair in campaign["pairs"] if pair.get("status") == "complete"]
            )
            _write_campaign(campaign_path, campaign)
        campaign["status"] = "complete"
        campaign["complete"] = True
        campaign["comparison"] = paired_comparison(campaign["pairs"])
    except CampaignStop:
        pass
    except KeyboardInterrupt:
        stop_reason = "campaign interrupted by the operator"
        failed_attempt = campaign.pop("current_attempt", None)
        if isinstance(failed_attempt, dict):
            campaign["failed_attempt"] = failed_attempt
        for pair_record in reversed(campaign["pairs"]):
            if pair_record.get("status") == "in_progress":
                pair_record["status"] = "stopped_interrupted"
                pair_record["qualified"] = False
                pair_record["stop_reason"] = stop_reason
                break
        campaign["status"] = "stopped"
        campaign["complete"] = False
        campaign["stop_reason"] = stop_reason
    except Exception as error:
        stop_reason = f"campaign failed while collecting evidence ({type(error).__name__}): {error}"
        failed_attempt = campaign.pop("current_attempt", None)
        if isinstance(failed_attempt, dict):
            campaign["failed_attempt"] = failed_attempt
        for pair_record in reversed(campaign["pairs"]):
            if pair_record.get("status") == "in_progress":
                pair_record["status"] = "stopped_error"
                pair_record["qualified"] = False
                pair_record["stop_reason"] = stop_reason
                break
        campaign["status"] = "stopped"
        campaign["complete"] = False
        campaign["stop_reason"] = stop_reason
    finally:
        campaign["finished_utc"] = utc_now()
        if stop_reason:
            campaign["status"] = "stopped"
            campaign["stop_reason"] = stop_reason
        try:
            app_after = app_runtime_snapshot(app)
            engine_hash_after = sha256_file(godot)
            engine_binaries_after = engine_binary_snapshot(godot)
            campaign["app_runtime_snapshot"]["after"] = app_after
            campaign["app_runtime_snapshot"]["unchanged"] = source_snapshots_match(app_before, app_after)
            campaign["godot"]["sha256_after"] = engine_hash_after
            campaign["godot"]["binary_files_sha256_after"] = engine_binaries_after
            provenance_reasons = provenance_rejection_reasons(
                app_before, app_after, engine_hash_before, engine_hash_after
            )
            if engine_binaries_before != engine_binaries_after:
                provenance_reasons.append("Godot launcher or runtime binary changed during the campaign")
            if provenance_reasons:
                campaign["status"] = "stopped"
                campaign["complete"] = False
                stop_reason = "; ".join(filter(None, [stop_reason, *provenance_reasons]))
        except OSError as error:
            provenance_error = f"final provenance snapshot failed: {error}"
            stop_reason = "; ".join(filter(None, [stop_reason, provenance_error]))
            campaign["status"] = "stopped"
            campaign["complete"] = False
        if stop_reason:
            campaign["stop_reason"] = stop_reason
        _write_campaign(campaign_path, campaign)

    print(f"Campaign {campaign['status']}: {campaign_path}", flush=True)
    if campaign["status"] != "complete":
        raise CampaignStop(str(campaign.get("stop_reason") or "campaign did not complete"))
    return campaign


def main(argv: Sequence[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    try:
        run_campaign(args)
    except (CampaignStop, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"grass profile session: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
