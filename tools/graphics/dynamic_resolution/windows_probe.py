"""Run one visible experiment in a manually reserved Windows session."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.testqueue.common import rpc, write_json
from tools.testqueue.processes import OwnedProcess
from tools.testqueue.worker import desktop_ready, external_simulators
from tools.godot.run_checked import inspect_log


def _sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _available(owner: str | None = None) -> bool:
    host = rpc("hosts", timeout=15)
    reservation = host.get("reservation")
    if (host.get("condition") not in {"READY", "DRAINING"} or host.get("claims") != []
            or host.get("scheduler", {}).get("state") != "READY"
            or host.get("pending_quarantines") or host.get("pending_journals")
            or not desktop_ready()):
        return False
    if owner is None:
        return reservation is None and host.get("occupancy", {}).get("external_simulators") is False
    return isinstance(reservation, dict) and reservation.get("owner") == owner


def _experiment_data(log: Path, stress: bool) -> dict:
    expected = "openrc-flight-resolution-stress-v1" if stress else "openrc-completed-gpu-frame-v1"
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("{"):
            value = json.loads(line)
            if isinstance(value, dict) and value.get("format") == expected:
                return value
    return {}


def _engine_identity(engine: Path) -> dict[str, str]:
    files = [engine]
    for suffix in (".console.exe", "_console.exe"):
        if engine.name.lower().endswith(suffix):
            files.append(engine.with_name(engine.name[:-len(suffix)] + ".exe"))
            break
    return {path.name: _sha256(path) for path in files}


def run(args: argparse.Namespace) -> int:
    if os.name != "nt":
        raise ValueError("The manual probe requires Windows.")
    engine = args.engine.resolve(strict=True)
    app = args.app.resolve(strict=True)
    if not (app / "project.godot").is_file():
        raise ValueError("The selected project must contain project.godot.")
    output = args.out.resolve()
    output.mkdir()
    owner = "vq07d-gpu-" + output.name
    deadline = time.monotonic() + args.wait
    while not _available():
        if time.monotonic() >= deadline:
            raise RuntimeError("The Windows desktop did not become available.")
        time.sleep(2)
    if args.stress:
        script = "probe_flight_resolution_stress.gd"
        probe_args = [f"--probe-target={args.fps}", f"--probe-fixed={args.fixed}", f"--probe-load={args.load}",
                      f"--probe-heavy-seconds={args.heavy_seconds}", f"--probe-recovery-seconds={args.recovery_seconds}"]
    else:
        script = "probe_completed_gpu_frame.gd"
        probe_args = []
    engine_log = output / "engine.log"
    command = [str(engine), "--path", str(app), "--log-file", str(engine_log), "--rendering-method", "forward_plus",
               "--rendering-driver", "vulkan", "--resolution", args.resolution,
               "--audio-driver", "Dummy", "--script", f"res://tests/{script}"]
    if args.fullscreen:
        command.append("--fullscreen")
    command.extend(["--", "--experimental-dynamic-resolution", *probe_args])
    profile = output / "profile"
    profile.mkdir()
    environment = dict(os.environ)
    environment["APPDATA"] = str(profile)
    sources = ["project.godot", f"tests/{script}", "render/flight_dynamic_resolution.gd",
               "render/flight_resolution_policy.gd", "render/reconstruction.gd", "render/render_timing_lease.gd"]
    identity = {"command": command, "engine_files": _engine_identity(engine),
                "source_sha256": {source: _sha256(app / source) for source in sources},
                "patch_sha256": _sha256(Path(__file__).parent / "completed_viewport_gpu.patch"),
                "reservation_owner": owner}
    write_json(output / "experiment.json", identity)
    process = OwnedProcess(command, app, environment, output / "launcher.log")
    reservation = rpc("reserve", owner=owner)
    handle = reservation["handle"]
    receipt = output / "reservation.json"
    cleanup = False
    observations: list[str] = []
    exit_code = None
    try:
        write_json(receipt, {"handle": handle, "owner": owner})
        if not _available(owner) or external_simulators():
            cleanup = True
            raise RuntimeError("The reserved desktop lost exclusivity before launch.")
        process.start()
        deadline = time.monotonic() + (args.heavy_seconds + args.recovery_seconds + 31 if args.stress else 30)
        while process.alive():
            if time.monotonic() >= deadline:
                raise TimeoutError("The rendered case exceeded its time budget.")
            if not _available(owner):
                observations.append("desktop or queue contention during the case")
                break
            time.sleep(2)
        exit_code = process.poll()
        log = inspect_log(engine_log, ["target_fps" if args.stress else "Completed GPU frame probe: 0 failed"])
        if log["counts"]["error"]:
            observations.append("engine diagnostics contain errors")
        if log["missing_required_text"]:
            observations.append("experiment receipt is incomplete")
        result = _experiment_data(engine_log, args.stress)
        if result:
            write_json(output / "measurement.json", result)
        size = result.get("output") if args.stress else result.get("full", {}).get("output_size")
        if size != [int(part) for part in args.resolution.split("x")]:
            observations.append("measured output did not match the requested pixel dimensions")
        if args.stress and result and result.get("vsync") != 0:
            observations.append("VSync remained active")
        if args.stress and args.fullscreen and result and result.get("window_mode") not in (3, 4):
            observations.append("viewport did not enter fullscreen")
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        observations.append(str(error))
        raise
    finally:
        if not cleanup:
            process.close()
            cleanup = True
        if cleanup:
            rpc("release", handle=handle)
            receipt.unlink(missing_ok=True)
        write_json(output / "result.json", {"exit_code": exit_code, "cleanup_confirmed": cleanup,
                                           "observations": observations})
    return 0 if exit_code == 0 and not observations else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--app", type=Path, default=ROOT / "app")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--resolution", choices=("1920x1080", "2560x1440", "3840x2160", "1280x720"),
                        default="1920x1080")
    parser.add_argument("--fullscreen", action="store_true")
    parser.add_argument("--stress", action="store_true")
    parser.add_argument("--fixed", type=int, choices=(0, 75, 85, 100), default=0)
    parser.add_argument("--fps", type=int, choices=(30, 60, 90, 120), default=120)
    parser.add_argument("--load", type=int, choices=range(1, 769), metavar="1..768", default=64)
    parser.add_argument("--heavy-seconds", type=int, choices=range(18, 46), metavar="18..45", default=18)
    parser.add_argument("--recovery-seconds", type=int, choices=range(16, 31), metavar="16..30", default=16)
    parser.add_argument("--wait", type=int, choices=range(0, 301), metavar="0..300", default=30)
    try:
        return run(parser.parse_args())
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"Windows GPU probe: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
