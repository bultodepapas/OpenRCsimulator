"""Shared native-flight qualification helpers for the L6c tree continuation."""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
from typing import Any, Sequence


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ENGINE = REPO_ROOT / ".tools" / "Godot_v4.8-beta1_win64.exe"
PROBE = REPO_ROOT / "tools" / "trees" / "flight_quality_probe.gd"
ERROR_RE = re.compile(r"\b(?:ERROR|SCRIPT ERROR|PARSE ERROR)\b", re.IGNORECASE)
ENVIRONMENT_SELECTORS = {"OPENRC_TREE_WIND", "OPENRC_TREE_CELL_SIZE_M", "OPENRC_GRASS_QUALITY"}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def project_source_fingerprint(project: Path) -> dict[str, Any]:
    """Hash a frozen app's source tree, excluding Godot's generated cache and VCS metadata."""
    project = project.resolve()
    files: dict[str, dict[str, Any]] = {}
    for path in sorted(project.rglob("*")):
        if not path.is_file() or ".godot" in path.parts or ".git" in path.parts:
            continue
        relative = path.relative_to(project).as_posix()
        files[relative] = {"sha256": sha256_file(path), "size_bytes": path.stat().st_size}
    canonical = json.dumps(files, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {"sha256": sha256_bytes(canonical), "files": len(files), "file_manifest": files}


def resolve_repo_path(value: str | Path) -> Path:
    path = Path(value).expanduser()
    return (path if path.is_absolute() else REPO_ROOT / path).resolve()


def validate_engine_and_project(engine: Path, project: Path) -> None:
    if not engine.is_file():
        raise FileNotFoundError(f"Godot executable does not exist: {engine}")
    if not (project / "project.godot").is_file() or not (project / "main.tscn").is_file():
        raise FileNotFoundError(f"Not a runnable app project with project.godot and main.tscn: {project}")
    if not PROBE.is_file():
        raise FileNotFoundError(f"External quality probe is missing: {PROBE}")


def parse_environment(items: Sequence[str] | None) -> dict[str, str]:
    """Parse documented tree/grass selectors, rejecting accidental unknown options."""
    parsed: dict[str, str] = {}
    for item in items or []:
        name, separator, value = item.partition("=")
        if not separator or name not in ENVIRONMENT_SELECTORS:
            raise ValueError(f"unsupported environment selector {item!r}; choose {', '.join(sorted(ENVIRONMENT_SELECTORS))}")
        if name in parsed:
            raise ValueError(f"environment selector specified more than once: {name}")
        parsed[name] = value
    return parsed


def make_fresh_directory(path: Path) -> Path:
    """Create an evidence directory without overwriting a prior run."""
    if path.exists():
        if not path.is_dir() or any(path.iterdir()):
            raise FileExistsError(f"Output directory must be new or empty: {path}")
    path.mkdir(parents=True, exist_ok=True)
    return path


def contains_engine_error(*texts: str) -> bool:
    return any(ERROR_RE.search(text) for text in texts if text)


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as source:
        value = json.load(source)
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object in {path}")
    return value


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as target:
        json.dump(value, target, indent=2, ensure_ascii=False, sort_keys=True)
        target.write("\n")


def godot_command(
    engine: Path,
    project: Path,
    *,
    width: int,
    height: int,
    log_path: Path,
    user_args: Sequence[str],
    movie_path: Path | None = None,
    fps: int = 60,
    fixed_fps: bool = False,
) -> list[str]:
    command = [
        str(engine),
        "--path",
        str(project),
        "--script",
        str(PROBE),
        "--resolution",
        f"{width}x{height}",
        "--position",
        "0,0",
        "--disable-vsync",
        "--max-fps",
        str(fps),
        "--log-file",
        str(log_path.with_suffix(log_path.suffix + ".engine.log")),
    ]
    if fixed_fps:
        command.extend(["--fixed-fps", str(fps)])
    if movie_path is not None:
        command.extend(["--write-movie", str(movie_path)])
    command.append("--")
    command.extend(user_args)
    return command


def run_godot(
    command: Sequence[str],
    *,
    log_path: Path,
    timeout_s: float,
    environment: dict[str, str] | None = None,
) -> dict[str, Any]:
    import time

    log_path.parent.mkdir(parents=True, exist_ok=True)
    start_utc = utc_now()
    start_monotonic_ns = time.monotonic_ns()
    try:
        result = subprocess.run(
            list(command),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout_s,
            check=False,
            env={**os.environ, **(environment or {})},
        )
        output = result.stdout
        exit_code = result.returncode
        timed_out = False
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or "")
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        exit_code = None
        timed_out = True
    end_monotonic_ns = time.monotonic_ns()
    end_utc = utc_now()
    with log_path.open("w", encoding="utf-8", newline="\n") as target:
        target.write(output)
    engine_log = log_path.with_suffix(log_path.suffix + ".engine.log")
    engine_log_text = engine_log.read_text(encoding="utf-8", errors="replace") if engine_log.is_file() else ""
    return {
        "command": list(command),
        "exit_code": exit_code,
        "timed_out": timed_out,
        "started_utc": start_utc,
        "finished_utc": end_utc,
        "elapsed_monotonic_s": (end_monotonic_ns - start_monotonic_ns) / 1_000_000_000.0,
        "stdout_log": str(log_path),
        "godot_log": str(engine_log) if engine_log.is_file() else None,
        "environment": environment or {},
        "contains_error": contains_engine_error(output, engine_log_text),
        "output": output,
    }


def validate_frame_report(report: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if report.get("format") != "openrc-tree-flight-quality-v1":
        errors.append("frame report format is missing or unsupported")
    if report.get("complete") is not True:
        errors.append(f"frame report is incomplete: {report.get('failure', '')}")
    if report.get("route") != "live-input-tick-tape":
        errors.append("route was not recorded as live input through FlightSession.read_raw")
    for key in ("input_tape_sha256", "scenario_sha256"):
        if not re.fullmatch(r"[0-9a-f]{64}", str(report.get(key, ""))):
            errors.append(f"{key} is missing or is not a SHA-256 digest")
    if not isinstance(report.get("scenario_identity"), dict):
        errors.append("scenario identity is missing")
    settings = report.get("settings", {})
    if settings.get("input_enabled") is not True or settings.get("physics_enabled") is not True:
        errors.append("live input or simulation physics was disabled")
    simulation = report.get("simulation", {})
    if simulation.get("paused") is not False or simulation.get("crash") is not False or simulation.get("fault"):
        errors.append("flight paused, crashed or faulted during the sample")
    if int(simulation.get("read_raw_calls", 0)) <= 0:
        errors.append("FlightSession.read_raw received no input samples")
    if int(simulation.get("physics_ticks_per_second", 0)) < 1:
        errors.append("physics tick rate is missing or invalid")
    if int(report.get("route_spec", {}).get("tick_rate", 0)) != int(simulation.get("physics_ticks_per_second", 0)):
        errors.append("input route tick rate does not match the live physics tick rate")
    raw = report.get("raw_metrics", {})
    required = {
        "input_read_calls",
        "sim_tick",
        "sim_time_s",
        "process_time_s",
        "physics_process_time_s",
        "draw_calls",
        "primitives",
        "visible_draw_calls",
        "shadow_draw_calls",
        "visible_primitives",
        "shadow_primitives",
        "video_memory_bytes",
        "texture_memory_bytes",
        "buffer_memory_bytes",
        "cpu_static_memory_bytes",
        "render_cpu_ms",
        "render_gpu_ms",
    }
    if not required.issubset(raw):
        errors.append("frame report is missing required raw metrics: " + ", ".join(sorted(required - set(raw))))
    frames = report.get("frames")
    if not isinstance(frames, int) or frames < 1:
        errors.append("frame report contains no samples")
        frames = 0
    clock_fields = ("frame_deltas_s", "frame_wall_usec", "frame_end_monotonic_usec")
    for field in clock_fields:
        values = report.get(field)
        if not isinstance(values, list) or len(values) != frames:
            errors.append(f"{field} clock samples do not match the reported frame count")
            continue
        try:
            numeric = [float(value) for value in values]
        except (TypeError, ValueError):
            errors.append(f"{field} contains a non-numeric clock sample")
            continue
        if not all(math.isfinite(value) for value in numeric):
            errors.append(f"{field} contains a non-finite clock sample")
        elif field == "frame_deltas_s" and any(value <= 0.0 for value in numeric):
            errors.append("frame delta clock contains a non-positive interval")
        elif field == "frame_wall_usec" and any(value <= 0.0 for value in numeric):
            errors.append("monotonic wall clock contains a non-positive frame interval")
        elif field == "frame_end_monotonic_usec" and any(a >= b for a, b in zip(numeric, numeric[1:])):
            errors.append("monotonic frame-end clock does not strictly advance")
    metric_values: dict[str, list[float]] = {}
    for key in required:
        values = raw.get(key)
        if not isinstance(values, list) or len(values) != frames:
            errors.append(f"raw metric {key} does not contain one sample per rendered frame")
            continue
        try:
            numeric = [float(value) for value in values]
        except (TypeError, ValueError):
            errors.append(f"raw metric {key} contains a non-numeric sample")
            continue
        if not all(math.isfinite(value) for value in numeric):
            errors.append(f"raw metric {key} contains a non-finite sample")
            continue
        metric_values[key] = numeric
    for key in ("process_time_s", "physics_process_time_s", "draw_calls", "primitives", "visible_draw_calls", "visible_primitives"):
        if not any(value > 0.0 for value in metric_values.get(key, [])):
            errors.append(f"native performance monitor {key} has no positive samples")
    ticks = metric_values.get("sim_tick", [])
    sim_times = metric_values.get("sim_time_s", [])
    inputs = metric_values.get("input_read_calls", [])
    if ticks and any(a >= b for a, b in zip(ticks, ticks[1:])):
        errors.append("simulation tick clock did not strictly advance during the rendered sample")
    if sim_times and any(a >= b for a, b in zip(sim_times, sim_times[1:])):
        errors.append("simulation time clock did not strictly advance during the rendered sample")
    if inputs and any(a > b for a, b in zip(inputs, inputs[1:])):
        errors.append("FlightSession.read_raw sample counter moved backwards")
    measured_ticks = int(simulation.get("ticks", 0))
    if ticks and inputs and inputs[-1] - inputs[0] < measured_ticks:
        errors.append("measured raw input calls did not cover the simulation ticks in the sample")
    sample_s = _finite_number(report.get("sample_s"))
    actual_sample_s = _finite_number(report.get("actual_sample_s"))
    warmup_s = _finite_number(report.get("warmup_s"))
    actual_warmup_s = _finite_number(report.get("actual_warmup_s"))
    if sample_s is None or sample_s <= 0.0 or actual_sample_s is None or actual_sample_s <= 0.0:
        errors.append("requested or actual measurement clock is missing or non-positive")
    elif abs(actual_sample_s - sample_s) > 0.5:
        errors.append("actual measurement duration differs from its request by more than 0.5 s")
    if warmup_s is None or warmup_s < 0.0 or actual_warmup_s is None or actual_warmup_s < 0.0:
        errors.append("requested or actual warm-up clock is missing or invalid")
    elif abs(actual_warmup_s - warmup_s) > 0.5:
        errors.append("actual warm-up duration differs from its request by more than 0.5 s")
    measured_wall_s = _finite_number(simulation.get("measured_wall_s"))
    elapsed_sim_s = _finite_number(simulation.get("elapsed_time_s"))
    wall_ratio = _finite_number(simulation.get("wall_ratio"))
    start_usec = _finite_number(report.get("actual_sample_start_monotonic_usec"))
    end_usec = _finite_number(report.get("actual_sample_end_monotonic_usec"))
    if measured_wall_s is None or measured_wall_s <= 0.0 or elapsed_sim_s is None or elapsed_sim_s <= 0.0:
        errors.append("active simulation or monotonic wall clock did not advance")
    frame_end_usec = report.get("frame_end_monotonic_usec", [])
    if isinstance(frame_end_usec, list) and len(frame_end_usec) == frames and frames > 1:
        try:
            frame_end_values = [int(value) for value in frame_end_usec]
        except (TypeError, ValueError):
            errors.append("monotonic frame-end timestamps are not integers")
        else:
            endpoint_wall_s = float(frame_end_values[-1] - frame_end_values[0]) / 1_000_000.0
            if measured_wall_s is not None and abs(measured_wall_s - endpoint_wall_s) > 0.000002:
                errors.append("measured wall duration does not match monotonic frame-end timestamps")
    if wall_ratio is None or wall_ratio <= 0.0:
        errors.append("simulation-to-wall-clock ratio is missing or non-positive")
    elif measured_wall_s and elapsed_sim_s and abs(wall_ratio - elapsed_sim_s / measured_wall_s) > 0.01:
        errors.append("simulation-to-wall-clock ratio does not match the measured clocks")
    if start_usec is None or end_usec is None or start_usec <= 0.0 or end_usec <= start_usec:
        errors.append("monotonic measurement start/end clocks are missing or do not advance")
    frame_ms = report.get("frame_ms", {})
    percentiles = [_finite_number(frame_ms.get(key)) for key in ("p50", "p95", "p99", "max")]
    if any(value is None or value <= 0.0 for value in percentiles):
        errors.append("frame-time percentiles are missing or non-positive")
    elif percentiles != sorted(percentiles):
        errors.append("frame-time percentile ordering is invalid")
    build = report.get("build", {})
    if not build.get("adapter") or not build.get("api"):
        errors.append("GPU adapter/API identity is missing")
    if not build.get("frame_samples_sha256"):
        errors.append("FrameSamples source hash is missing")
    render_timing = build.get("viewport_render_timing", {})
    for key, raw_key in (("cpu", "render_cpu_ms"), ("gpu", "render_gpu_ms")):
        timing = render_timing.get(key, {})
        has_positive = any(sample > 0.0 for sample in metric_values.get(raw_key, []))
        if timing.get("available") is not has_positive:
            errors.append(f"{key.upper()} viewport timer availability does not match its raw samples")
    render_settings = settings.get("render_settings", {})
    if render_settings.get("msaa_4x") is not True:
        errors.append("root viewport did not use 4x MSAA")
    window = settings.get("window", {})
    if int(window.get("width", 0)) <= 0 or int(window.get("height", 0)) <= 0:
        errors.append("actual root viewport dimensions are missing")
    memory_available = build.get("render_memory", {}).get("available", {})
    for key, raw_key in (
        ("cpu_static", "cpu_static_memory_bytes"),
        ("video", "video_memory_bytes"),
        ("textures", "texture_memory_bytes"),
        ("buffers", "buffer_memory_bytes"),
    ):
        has_positive = any(sample > 0.0 for sample in metric_values.get(raw_key, []))
        if memory_available.get(key) is not has_positive:
            errors.append(f"{key} memory availability does not match its raw samples")
    return errors


def _finite_number(value: Any) -> float | None:
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return None
    return numeric if math.isfinite(numeric) else None


def discover_ffmpeg(explicit: str | None = None) -> Path | None:
    if explicit:
        candidate = resolve_repo_path(explicit)
        return candidate if candidate.is_file() else None
    found = shutil.which("ffmpeg")
    if found:
        return Path(found).resolve()
    bundled = REPO_ROOT / ".tools" / "tree-review-ffmpeg" / "imageio_ffmpeg" / "binaries" / "ffmpeg-win-x86_64-v7.1.exe"
    return bundled if bundled.is_file() else None
