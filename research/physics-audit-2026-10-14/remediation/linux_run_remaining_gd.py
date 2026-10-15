#!/usr/bin/env python3
"""Run only the GDScript tests after a known app/test.sh failure.

This is diagnostic remainder evidence, never a replacement for the canonical
app/test.sh gate. Per-test timeouts and engine-error detection mirror that gate.
Combined stdout/stderr is retained even when a test fails or times out.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time


LONG_180 = {
    "test_ui_pause.gd",
    "test_ui_screen_stack.gd",
    "test_landing_variations.gd",
    "test_input_report_cli.gd",
    "test_latency_patch_cli.gd",
    "test_failure_session.gd",
    "test_failure_shutdown.gd",
    "test_failure_routes.gd",
}
LONG_300 = {
    "test_heli_session.gd",
    "test_heli_ground_session.gd",
    "test_rcv_vehicle_dynamics.gd",
    "test_rcv_session.gd",
    "test_rcv_airfield_course.gd",
    "test_rcv_airfield_track.gd",
    "test_rcv_obstacle_contacts.gd",
    "test_rcv_activity.gd",
    "test_rcv_presentation.gd",
    "test_rcv_menu.gd",
}
LONG_600 = {
    "test_aircraft_catalog.gd",
    "test_ui_aircraft.gd",
    "test_ui_runway.gd",
    "test_workshop_integration.gd",
    "test_workshop_ui.gd",
    "test_ui_natural_random.gd",
}


def timeout_for(name: str) -> int:
    if name in {"test_landing_maneuver.gd", "test_crash_integration.gd", "test_crash_wreck.gd"}:
        return 180
    if name in LONG_180:
        return 180
    if name in LONG_300:
        return 300
    if name in LONG_600:
        return 600
    return 60


def inside(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--after", required=True, help="last already-run test filename")
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    args = parser.parse_args()

    candidate = args.candidate.resolve(strict=True)
    app = candidate / "app"
    tests_dir = app / "tests"
    godot = args.godot.resolve(strict=True)
    log_path = args.log.resolve()
    summary_path = args.summary.resolve()
    if not tests_dir.is_dir() or not (app / "project.godot").is_file():
        parser.error(f"candidate does not contain an app project: {candidate}")
    if inside(log_path, candidate) or inside(summary_path, candidate):
        parser.error("diagnostic outputs must stay outside the frozen candidate")
    if log_path == summary_path:
        parser.error("log and summary paths must be different")
    if shutil.which("timeout") is None:
        parser.error("GNU timeout is required to match app/test.sh per-test bounds")

    tests = sorted(tests_dir.glob("test_*.gd"), key=lambda p: p.name)
    names = [p.name for p in tests]
    try:
        start = names.index(args.after) + 1
    except ValueError:
        parser.error(f"--after test not found: {args.after}")
    remaining = tests[start:]
    if not remaining:
        parser.error("there are no GDScript tests after the requested marker")

    log_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    started_utc = dt.datetime.now(dt.timezone.utc).isoformat()
    results: list[dict[str, object]] = []
    error_pattern = re.compile(r"^(SCRIPT )?ERROR:", re.MULTILINE)

    with log_path.open("w", encoding="utf-8", newline="") as log:
        log.write("CLASSIFICATION: diagnostic remainder only; not canonical app/test.sh pass evidence\n")
        log.write(f"started_utc: {started_utc}\ncandidate: {candidate}\ngodot: {godot}\n")
        log.write(f"already_run_through: {args.after}\nremaining_test_count: {len(remaining)}\n\n")
        log.flush()

        for index, test_path in enumerate(remaining, start=1):
            name = test_path.name
            limit = timeout_for(name)
            command = [
                "timeout", str(limit), str(godot), "--headless", "--path", str(app),
                "--audio-driver", "Dummy", "--script", f"res://tests/{name}",
            ]
            print(f"[{index}/{len(remaining)}] START {name} timeout={limit}s", flush=True)
            began = time.monotonic()
            with tempfile.TemporaryFile(mode="w+b") as output:
                try:
                    proc = subprocess.run(
                        command,
                        cwd=app,
                        stdout=output,
                        stderr=subprocess.STDOUT,
                        check=False,
                        env=os.environ.copy(),
                    )
                    code = proc.returncode
                    timed_out = code == 124
                    output.flush()
                    output.seek(0)
                    raw = output.read()
                except OSError as exc:
                    code = 127
                    timed_out = False
                    raw = f"runner OSError: {exc}\n".encode("utf-8", errors="replace")
            elapsed = time.monotonic() - began
            decoded = raw.decode("utf-8", errors="replace")
            engine_error = bool(error_pattern.search(decoded))
            passed = code == 0 and not engine_error
            log.write(f"===== {name} =====\n")
            log.write(f"command: {json.dumps(command)}\n")
            log.write(f"timeout_s: {limit}\nexit_code: {code}\ntimed_out: {str(timed_out).lower()}\n")
            log.write(f"engine_error_detected: {str(engine_error).lower()}\nelapsed_s: {elapsed:.3f}\n")
            log.write("----- combined stdout+stderr -----\n")
            log.write(decoded)
            if decoded and not decoded.endswith("\n"):
                log.write("\n")
            log.write("===== end test =====\n\n")
            log.flush()
            result = {
                "test": name,
                "command": command,
                "timeout_s": limit,
                "exit_code": code,
                "timed_out": timed_out,
                "engine_error_detected": engine_error,
                "passed": passed,
                "elapsed_s": round(elapsed, 3),
            }
            results.append(result)
            state = "PASS" if passed else "FAIL"
            print(f"[{index}/{len(remaining)}] {state} {name} exit={code} engine_error={engine_error} elapsed={elapsed:.1f}s", flush=True)

    ended_utc = dt.datetime.now(dt.timezone.utc).isoformat()
    failed = [row for row in results if not row["passed"]]
    summary = {
        "classification": "diagnostic_remainder_not_canonical_gate",
        "started_utc": started_utc,
        "ended_utc": ended_utc,
        "candidate": str(candidate),
        "godot": str(godot),
        "already_run_through": args.after,
        "count": len(results),
        "passed": len(results) - len(failed),
        "failed": len(failed),
        "results": results,
        "log": str(log_path),
    }
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"DIAGNOSTIC REMAINDER: {summary['passed']}/{summary['count']} passed; {summary['failed']} failed; not canonical", flush=True)
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
