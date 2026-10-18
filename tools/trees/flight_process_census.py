"""Record a privacy-bounded 1 Hz process census around a flight quality series."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import time
from typing import Any

import psutil


REPO_ROOT = Path(__file__).resolve().parents[2]
RENDERER_NAMES = ("godot", "blender", "ffmpeg")
RUNNER_SCRIPT = "flight_quality.py"


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _normalized(value: str) -> str:
    return value.replace("\\", "/").casefold()


def _is_project_path(value: str) -> bool:
    normalized = _normalized(value)
    root = _normalized(str(REPO_ROOT.resolve()))
    if root in normalized:
        return True
    path = Path(value)
    if not path.is_absolute():
        candidates = (Path.cwd() / path, REPO_ROOT / path)
    else:
        candidates = (path,)
    for candidate in candidates:
        try:
            candidate.resolve(strict=False).relative_to(REPO_ROOT)
            if candidate.exists():
                return True
        except (OSError, ValueError):
            continue
    return False


def _renderer_kind(name: str) -> str | None:
    lowered = name.casefold()
    for kind in RENDERER_NAMES:
        if kind in lowered:
            return kind
    return None


def _is_runner(args: list[str]) -> bool:
    for arg in args:
        normalized = _normalized(arg)
        basename = normalized.rsplit("/", 1)[-1]
        if basename == RUNNER_SCRIPT and _is_project_path(arg):
            return True
    return False


def _prime_process_counters() -> None:
    current_user = psutil.Process().username().casefold()
    for process in psutil.process_iter(attrs=("name", "username")):
        try:
            name = str(process.info.get("name") or "unknown")
            username = str(process.info.get("username") or "").casefold()
            if _renderer_kind(name) is None and username != current_user:
                continue
            process.cpu_percent(interval=None)
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue


def _snapshot(load_threshold: float) -> tuple[list[dict[str, Any]], list[int]]:
    captured: list[dict[str, Any]] = []
    runner_pids: list[int] = []
    current_user = psutil.Process().username().casefold()
    for process in psutil.process_iter(attrs=("pid", "name", "username")):
        try:
            info = process.info
            pid = int(info["pid"])
            name = str(info.get("name") or "unknown")
            username = str(info.get("username") or "").casefold()
            kind = _renderer_kind(name)
            if kind is None and username != current_user:
                continue
            cpu_pct = float(process.cpu_percent(interval=None))
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess, TypeError, ValueError):
            continue

        is_python = name.casefold().startswith(("python", "py.exe"))
        if kind is None and not is_python and cpu_pct < load_threshold:
            continue

        try:
            args = [str(arg) for arg in process.cmdline()] if (kind is not None or is_python) else []
            if is_python and _is_runner(args):
                runner_pids.append(pid)
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            args = []

        if kind is not None:
            try:
                executable = str(process.exe() or "")
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                executable = ""
            kind = kind or _renderer_kind(Path(executable).name)
            is_project_process = _is_project_path(executable) or any(_is_project_path(arg) for arg in args)
            record: dict[str, Any] = {
                "pid": pid,
                "name": name,
                "cpu_pct_one_logical_cpu": round(cpu_pct, 2),
                "renderer": kind,
                "project_process": is_project_process,
            }
            # Command lines are retained only when the renderer belongs to this repo.
            if is_project_process:
                record["command_line"] = args
            captured.append(record)
        elif cpu_pct >= load_threshold:
            # Other processes are represented without executable paths or arguments.
            captured.append({
                "pid": pid,
                "name": name,
                "cpu_pct_one_logical_cpu": round(cpu_pct, 2),
                "renderer": None,
            })

    return captured, runner_pids


def run_census(
    output: Path,
    *,
    interval_s: float,
    load_threshold: float,
    max_wait_s: float,
    tail_s: float,
    duration_s: float | None,
) -> dict[str, Any]:
    output = output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    _prime_process_counters()
    psutil.cpu_percent(interval=None)

    started_utc = _utc_now()
    start = time.monotonic()
    deadline = start + (duration_s if duration_s is not None else max_wait_s)
    saw_runner = False
    last_runner_seen: float | None = None
    sample_count = 0
    stop_reason = "duration_elapsed" if duration_s is not None else "runner_not_seen_before_timeout"

    with output.open("x", encoding="utf-8", newline="\n") as target:
        header = {
            "record": "header",
            "format": "openrc-flight-process-census-v1",
            "started_utc": started_utc,
            "interval_s": interval_s,
            "load_threshold_cpu_pct": load_threshold,
            "repo_root": str(REPO_ROOT),
            "command_line_policy": "Full arguments are stored only for Godot/Blender/FFmpeg processes whose executable or an argument identifies this repository. All other processes store PID, name, and CPU only.",
            "other_process_scope": "All processes named Godot/Blender/FFmpeg are sampled; additional CPU-load samples are limited to the current user. total_cpu_pct covers the whole system.",
            "runner_detection": RUNNER_SCRIPT,
            "psutil_version": psutil.__version__,
        }
        target.write(json.dumps(header, sort_keys=True) + "\n")
        target.flush()

        next_sample = time.monotonic() + interval_s
        while True:
            remaining = next_sample - time.monotonic()
            if remaining > 0:
                time.sleep(remaining)
            now = time.monotonic()
            if duration_s is not None and now >= deadline:
                break
            if duration_s is None and now >= deadline:
                stop_reason = "runner_still_active_at_timeout" if saw_runner else "runner_not_seen_before_timeout"
                break

            processes, runner_pids = _snapshot(load_threshold)
            total_cpu_pct = float(psutil.cpu_percent(interval=None))
            if runner_pids:
                saw_runner = True
                last_runner_seen = now
            elif saw_runner and last_runner_seen is not None and now - last_runner_seen >= tail_s:
                stop_reason = "runner_exit_and_tail_elapsed"

            target.write(json.dumps({
                "record": "sample",
                "utc": _utc_now(),
                "monotonic_s": round(now - start, 3),
                "phase": "active" if runner_pids else ("tail" if saw_runner else "waiting"),
                "total_cpu_pct": round(total_cpu_pct, 2),
                "flight_quality_runner_pids": runner_pids,
                "processes": processes,
            }, sort_keys=True) + "\n")
            target.flush()
            sample_count += 1

            if stop_reason == "runner_exit_and_tail_elapsed":
                break
            next_sample = time.monotonic() + interval_s

    return {
        "output": str(output),
        "samples": sample_count,
        "runner_seen": saw_runner,
        "stop_reason": stop_reason,
        "elapsed_s": round(time.monotonic() - start, 3),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path, help="new JSONL output path; existing files are never overwritten")
    parser.add_argument("--interval", type=float, default=1.0, help="sample interval in seconds (default: 1.0)")
    parser.add_argument("--load-threshold", type=float, default=1.0, help="record other processes at or above this percent of one logical CPU")
    parser.add_argument("--max-wait", type=float, default=1800.0, help="seconds to wait for and observe the flight runner before timing out")
    parser.add_argument("--tail", type=float, default=3.0, help="seconds to keep sampling after the runner exits")
    parser.add_argument("--duration", type=float, help="sample for a fixed duration instead of waiting for flight_quality.py; intended for smoke checks")
    args = parser.parse_args()

    if args.interval <= 0 or args.load_threshold < 0 or args.max_wait <= 0 or args.tail < 0:
        parser.error("interval/max-wait must be positive; load-threshold/tail must be nonnegative")
    if args.duration is not None and args.duration <= 0:
        parser.error("duration must be positive")

    result = run_census(
        args.out,
        interval_s=args.interval,
        load_threshold=args.load_threshold,
        max_wait_s=args.max_wait,
        tail_s=args.tail,
        duration_s=args.duration,
    )
    print(json.dumps(result, sort_keys=True))
    return 0 if result["samples"] > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
