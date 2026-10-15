#!/usr/bin/env python3
"""Run the frozen RCV powertrain test with its unchanged 60-second cap."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


ENGINE_ERROR = re.compile(r"^\s*(?:SCRIPT ERROR:|SHADER ERROR:|ERROR:|FATAL:|Parse Error:|Compile Error:|Failed to load script\b)")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--app-copy", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()

    candidate = args.candidate.resolve(strict=True)
    app_copy = args.app_copy.resolve(strict=True)
    godot = args.godot.resolve(strict=True)
    evidence = args.evidence.resolve(strict=True)
    if not app_copy.is_relative_to(Path("/tmp/openrc-r11-rcv-powertrain-native-diag-20261015-01")):
        raise SystemExit(f"Refusing to test outside the disposable diagnostic tree: {app_copy}")

    script = Path("tests/test_rcv_powertrain.gd")
    frozen_test = candidate / "app" / script
    diagnostic_test = app_copy / script
    if sha256(frozen_test) != sha256(diagnostic_test):
        raise SystemExit("The diagnostic app's powertrain test differs from the frozen candidate.")
    stage_receipt_path = evidence / "stage-receipt.json"
    stage_receipt = json.loads(stage_receipt_path.read_text(encoding="utf-8"))
    command = [
        "timeout", "60", str(godot), "--headless", "--path", str(app_copy),
        "--audio-driver", "Dummy", "--script", "res://tests/test_rcv_powertrain.gd",
    ]
    started = time.monotonic()
    outer_timed_out = False
    try:
        completed = subprocess.run(
            command,
            cwd=Path.cwd(),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=65,
            check=False,
        )
        output = completed.stdout
        exit_code = completed.returncode
    except subprocess.TimeoutExpired as exc:
        outer_timed_out = True
        partial = exc.stdout or ""
        output = partial.decode("utf-8", errors="replace") if isinstance(partial, bytes) else partial
        output += "\nOUTER_SAFETY_TIMEOUT after 65 seconds; inner GNU timeout was 60 seconds.\n"
        exit_code = 124

    elapsed = time.monotonic() - started
    log_path = evidence / "test_rcv_powertrain-native-60s.log"
    log_path.write_text(output, encoding="utf-8")
    engine_errors = [line for line in output.splitlines() if ENGINE_ERROR.search(line)]
    report = {
        "format": "openrc-rcv-powertrain-native-bounded-run-v1",
        "cwd": str(Path.cwd().resolve()),
        "candidate_root": str(candidate),
        "diagnostic_app_copy": str(app_copy),
        "godot_path": str(godot),
        "godot_sha256": sha256(godot),
        "frozen_test_sha256": sha256(frozen_test),
        "diagnostic_test_sha256": sha256(diagnostic_test),
        "stage_receipt_sha256": sha256(stage_receipt_path),
        "native_library_sha256": stage_receipt["native_library_sha256"],
        "command": command,
        "inner_timeout_seconds": 60,
        "outer_safety_timeout_seconds": 65,
        "outer_timed_out": outer_timed_out,
        "exit_code": exit_code,
        "elapsed_seconds": elapsed,
        "engine_errors": engine_errors,
        "stdout_sha256": hashlib.sha256(output.encode("utf-8")).hexdigest(),
        "stdout_path": str(log_path),
    }
    report_path = evidence / "test_rcv_powertrain-native-60s.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    if output:
        print(output, end="" if output.endswith("\n") else "\n")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
