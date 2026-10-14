"""Run the native synthetic visibility fixture with an external-process timeout.

The app must be a separately imported frozen snapshot. This tool never imports it.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

try:
    from .visibility_pack import validate_capture
except ImportError:
    from visibility_pack import validate_capture


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--background", choices=("sky", "horizon", "trees", "ground"), default="trees")
    parser.add_argument("--pose", choices=("level", "inverted", "knife_left", "knife_right", "climb", "dive"), default="level")
    parser.add_argument("--autozoom", choices=("on", "off"), default="on")
    parser.add_argument("--aircraft", default="jensen-das-ugly-stik-60")
    parser.add_argument("--frames", type=int, default=90)
    parser.add_argument("--timeout", type=float, default=180)
    args = parser.parse_args()
    if args.out.exists() or not args.godot.is_file() or not (args.app / "project.godot").is_file():
        parser.error("Require an existing engine/project and a new output directory")
    if args.frames < 2 or args.frames > 600 or not 0 < args.timeout <= 1800:
        parser.error("Frames must be 2..600 and timeout in (0, 1800]")
    if len(args.source_commit) != 40 or any(c not in "0123456789abcdefABCDEF" for c in args.source_commit):
        parser.error("source-commit must be the 40-character archived commit")
    args.out.mkdir(parents=True)
    script = Path(__file__).with_name("visibility_capture.gd").resolve()
    capture = args.out.resolve() / "capture"
    command = [
        str(args.godot.resolve()), "--path", str(args.app.resolve()),
        "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility",
        "--script", str(script), "--",
        f"--output={capture}", f"--source-commit={args.source_commit}",
        f"--background={args.background}", f"--pose={args.pose}",
        f"--autozoom={args.autozoom}", f"--aircraft={args.aircraft}", f"--frames={args.frames}",
    ]
    # Use the actual Windows engine executable, not a detached console launcher.
    start = time.monotonic()
    with (args.out / "process.log").open("w", encoding="utf-8") as log:
        try:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout, check=False)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = -1
    text = (args.out / "process.log").read_text(encoding="utf-8")
    errors = [line for line in text.splitlines() if "ERROR:" in line or "WARNING:" in line]
    capture_errors, _details = validate_capture(capture, args.frames)
    passed = code == 0 and not errors and not capture_errors and "VISIBILITY_CAPTURE_OK" in text
    report = {
        "command": command, "returncode": code, "completed_without_engine_warnings": passed,
        "diagnostics": errors, "elapsed_s_not_performance_evidence": time.monotonic() - start,
        "capture_validation_errors": capture_errors,
        "engine_sha256": hashlib.sha256(args.godot.read_bytes()).hexdigest(),
        "script_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
    }
    (args.out / "process.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"completed": passed, "output": str(args.out), "returncode": code}))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
