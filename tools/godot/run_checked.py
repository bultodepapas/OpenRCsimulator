"""Run Godot with bounded diagnostics, retained logs and a machine-readable verdict.

Uses only Python's standard library; arguments after -- are passed without a shell.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time


ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
DIAGNOSTIC = re.compile(r"^\s*((?:(?:SCRIPT|SHADER)\s+)?ERROR|WARNING):\s*(.*)")
DEFAULT_OUT = Path(__file__).resolve().parents[2] / "tmp" / "godot-checks"


def inspect_log(path: Path, required: list[str], *, max_chars: int | None = None) -> dict:
    """Scan bounded line fragments; retain counts and at most 20 diagnostic samples."""
    counts = {"error": 0, "warning": 0}
    samples = []
    found = [False] * len(required)
    continuation = False
    line_number = 0
    overlap = ""
    overlap_size = max((len(s) for s in required), default=1)
    context_sample = None
    read_chars = 0
    with path.open("r", encoding="utf-8", errors="replace") as stream:
        while fragment := stream.readline(65536):
            read_chars += len(fragment)
            if max_chars is not None and read_chars > max_chars:
                raise ValueError("log grew beyond the bounded scan size")
            if not continuation:
                line_number += 1
            clean = ANSI.sub("", fragment).rstrip("\r\n")
            # Literal completion markers can cross read boundaries, including long lines.
            combined = overlap + clean
            for i, marker in enumerate(required):
                found[i] = found[i] or marker in combined
            overlap = combined[-overlap_size:]
            match = None if continuation else DIAGNOSTIC.match(clean)
            if match:
                context_sample = None
                severity = "warning" if match[1] == "WARNING" else "error"
                counts[severity] += 1
                if len(samples) < 20:
                    samples.append({"severity": severity, "kind": match[1],
                                    "line": line_number, "message": match[2][:1000], "context": []})
                    context_sample = samples[-1]
            elif (not continuation and context_sample is not None
                  and line_number <= context_sample["line"] + 3 and clean.strip()):
                context_sample["context"].append(clean[:1000])
            continuation = not fragment.endswith("\n")
            if not continuation:
                overlap = ""
    return {"counts": counts, "diagnostics": samples,
            "missing_required_text": [s for s, seen in zip(required, found) if not seen]}


def stop_process(process: subprocess.Popen) -> str:
    """Terminate this invocation's process tree, never other Godot instances."""
    cleanup_error = ""
    if os.name == "nt":
        # Windows console Godot launches a companion executable. Kill both while
        # the parent is alive; taskkill also handles ordinary test subprocesses.
        if process.poll() is None:
            try:
                result = subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                        timeout=10, check=False)
                if result.returncode and process.poll() is None:
                    cleanup_error = "taskkill failed; only the direct process could be terminated"
            except (OSError, subprocess.SubprocessError) as error:
                cleanup_error = f"process-tree cleanup failed: {error}"
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except OSError as error:
            cleanup_error = f"process-group cleanup failed: {error}"
    try:
        if process.poll() is None:
            process.kill()
        process.wait(timeout=10)
    except (OSError, subprocess.SubprocessError) as error:
        cleanup_error = f"process cleanup failed: {error}"
    return cleanup_error


def run_checked(command: list[str], out_dir: Path = DEFAULT_OUT, *, timeout: float = 60,
                max_log_bytes: int = 8 * 1024 * 1024, warnings_as_errors: bool = False,
                required: list[str] | None = None, label: str = "godot") -> dict:
    required = required or []
    if (not command or type(timeout) not in (int, float) or not math.isfinite(timeout)
            or timeout <= 0 or type(max_log_bytes) is not int or max_log_bytes <= 0):
        raise ValueError("command, finite positive timeout and positive integer log limit required")
    if any(not s or len(s) > 4096 or "\n" in s or "\r" in s for s in required):
        raise ValueError("required text must be a nonempty single-line literal of at most 4096 characters")
    out_dir = Path(out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    prefix = re.sub(r"[^a-zA-Z0-9_.-]", "_", label)[:60].strip(".") or "godot"
    directory = Path(tempfile.mkdtemp(prefix=prefix + "-", dir=out_dir))
    log = directory / "engine.log"
    report_path = directory / "report.json"
    started = time.monotonic()
    report = {"format": "openrc-godot-check v1", "command": command, "cwd": os.getcwd(),
              "started_utc": datetime.now(timezone.utc).isoformat(), "label": label,
              "log": str(log), "report": str(report_path), "timeout_seconds": timeout,
              "max_log_bytes": max_log_bytes, "warnings_as_errors": warnings_as_errors,
              "required_text": required, "process_exit": None, "complete": False}
    reason = ""
    detail = ""
    overflow = threading.Event()
    read_errors = []
    process = None
    reader = None

    def collect(source, destination):
        remaining = max_log_bytes
        total = 0
        try:
            while block := source.read1(65536):
                destination.write(block[:remaining])
                remaining -= min(len(block), remaining)
                total += len(block)
                if total > max_log_bytes:
                    overflow.set()
                    break
            destination.flush()
        except Exception as error:
            # Exceptions in a worker thread never propagate to the supervisor.
            # Any collector failure must explicitly invalidate the capture.
            read_errors.append(f"{type(error).__name__}: {error}")
        finally:
            try:
                source.close()
            except (OSError, ValueError) as error:
                read_errors.append(f"output pipe close failed: {error}")

    try:
        with log.open("wb") as destination:
            try:
                process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                           stdin=subprocess.DEVNULL, start_new_session=os.name != "nt")
            except OSError as error:
                reason, detail = "launch_error", str(error)
            if process is not None:
                reader = threading.Thread(target=collect, args=(process.stdout, destination), daemon=True)
                reader.start()
                while process.poll() is None or reader.is_alive():
                    if overflow.is_set():
                        reason = "log_limit"
                        break
                    if read_errors:
                        reason, detail = "runner_error", read_errors[0]
                        break
                    if time.monotonic() - started >= timeout:
                        reason = "timeout"
                        break
                    time.sleep(0.02)
                if reason:
                    detail = stop_process(process) or detail
                reader.join(timeout=2)
                if reader.is_alive():
                    reason, detail = "runner_error", "output pipe remained open after process termination"
                report["process_exit"] = process.poll()
                # The last read may finish between the poll and loop condition.
                if overflow.is_set():
                    reason = "log_limit"
                if read_errors:
                    reason, detail = "runner_error", read_errors[0]
                report["complete"] = not reason
    except KeyboardInterrupt:
        reason = "interrupted"
        if process is not None:
            detail = stop_process(process)
        if reader is not None:
            reader.join(timeout=2)
    except OSError as error:
        reason, detail = "runner_error", str(error)
        if process is not None:
            detail = stop_process(process) or detail

    if process is not None:
        report["process_exit"] = process.poll()
    report.update(inspect_log(log, required))
    if not reason:
        if report["process_exit"] != 0:
            reason = "process_exit"
        elif report["counts"]["error"]:
            reason = "engine_error"
        elif warnings_as_errors and report["counts"]["warning"]:
            reason = "warning"
        elif report["missing_required_text"]:
            reason = "missing_required_text"
        else:
            reason = "passed"
    codes = {"passed": 0, "timeout": 124, "log_limit": 125, "runner_error": 125,
             "launch_error": 127, "interrupted": 130}
    code = codes.get(reason, 1)
    if reason == "process_exit" and 0 < report["process_exit"] < 124:
        code = report["process_exit"]
    report.update(reason=reason, detail=detail, exit_code=code, ok=code == 0,
                  elapsed_seconds=round(time.monotonic() - started, 6), log_bytes=log.stat().st_size)
    digest = hashlib.sha256()
    with log.open("rb") as stream:
        while block := stream.read(65536):
            digest.update(block)
    report["log_sha256"] = digest.hexdigest()
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    return report


def main() -> int:
    # Windows terminals may not represent every character; the raw log remains
    # byte-exact even when the terminal needs replacement characters.
    sys.stdout.reconfigure(errors="replace")
    sys.stderr.reconfigure(errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--label", default="godot", help="label for the unique run directory and report")
    parser.add_argument("--timeout", type=float, default=60, help="wall-clock deadline in seconds (default: 60)")
    parser.add_argument("--max-log-bytes", type=int, default=8 * 1024 * 1024,
                        help="stop after this many output bytes (default: 8388608)")
    parser.add_argument("--warnings-as-errors", action="store_true", help="also fail on engine WARNING records")
    parser.add_argument("--require-text", action="append", default=[],
                        help="require this literal completion text; repeat for multiple markers")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    try:
        result = run_checked(command, args.out_dir, timeout=args.timeout,
                             max_log_bytes=args.max_log_bytes, warnings_as_errors=args.warnings_as_errors,
                             required=args.require_text, label=args.label)
    except (OSError, ValueError) as error:
        print(f"Godot check configuration/output error: {error}", file=sys.stderr)
        return 2
    # Replay output after completion, preserving stdout consumers and avoiding a
    # slow terminal in the capture loop. Memory and retained output remain bounded.
    with Path(result["log"]).open("r", encoding="utf-8", errors="replace") as stream:
        while block := stream.read(65536):
            sys.stdout.write(block)
    if not result["ok"]:
        print(f"Godot check failed: {result['reason']} (process exit {result['process_exit']}); "
              f"report: {result['report']}", file=sys.stderr)
        if result["detail"]:
            print(result["detail"], file=sys.stderr)
        for item in result["diagnostics"][:3]:
            print(f"  log:{item['line']} {item['kind']}: {item['message']}", file=sys.stderr)
            for context in item["context"]:
                print(context, file=sys.stderr)
        if result["missing_required_text"]:
            print(f"Missing completion text: {result['missing_required_text']}", file=sys.stderr)
    return result["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
