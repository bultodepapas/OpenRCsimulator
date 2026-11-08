"""Validate checked-Godot evidence and export one JUnit case per invocation.

Read a dedicated run collection, including incomplete directories. Never launch
Godot, follow report-supplied paths, infer assertion counts, or overwrite evidence.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

from run_checked import inspect_log

REASONS = {"passed", "process_exit", "engine_error", "warning", "missing_required_text",
           "timeout", "log_limit", "runner_error", "launch_error", "interrupted"}
CAPTURE_ERRORS = {"invalid_report", "timeout", "log_limit", "runner_error", "launch_error", "interrupted"}
MAX_REPORT_BYTES = 256 * 1024
# A passing script that prints this declared token did not qualify its contract (e.g. headless pixel suites).
DECLARED_SKIP = re.compile(r"^[ \t]*(\S[^\r\n]{0,200}? SKIPPED: [^\r\n]{0,300})\r?$", re.M)  # CRLF on Windows
XML_UNSAFE = re.compile(r"[^\x09\x0a\x0d\x20-\ud7ff\ue000-\ufffd\U00010000-\U0010ffff]")
HINTS = {
    "engine_error": "Inspect the first engine diagnostic and its source location.",
    "process_exit": "Inspect the child exit status and final engine output.",
    "warning": "Review warnings; this invocation enabled warnings-as-errors.",
    "missing_required_text": "The completion marker is missing; verify that the intended checks ran.",
    "timeout": "Inspect the last output for a hang before increasing the deadline.",
    "log_limit": "Inspect the retained prefix for repeated output before increasing the byte limit.",
    "runner_error": "Inspect the capture error and filesystem/process cleanup details.",
    "launch_error": "Check the executable path, dependencies and permissions.",
    "interrupted": "The invocation was interrupted; rerun into a fresh collection.",
    "invalid_report": "Evidence is missing, inconsistent or unsupported; retain it and rerun into a fresh collection.",
    "skipped": "Declared checks did not run; inspect the recorded skip reason.",
}

# These scripts deliberately exit successfully before their pixel assertions in a
# headless run. Keep their skip and completion evidence distinct from parse checks.
PIXEL_CONTRACTS = {
    "res://tests/test_lighting_segment_filter.gd": (
        b"Lighting segment pixels SKIPPED: native rendering required at 1920x1080.",
        rb"Lighting segment filter: (0|[1-9][0-9]*) checks, (0|[1-9][0-9]*) failed",
        12,
    ),
    "res://tests/test_lighting_skin_patterns.gd": (
        b"Lighting skin pixels SKIPPED: native renderer required at 1920x1080.",
        rb"Lighting skin patterns: (0|[1-9][0-9]*) checks, (0|[1-9][0-9]*) failed",
        13,
    ),
}
PIXEL_SKIP_PREFIXES = ("Lighting segment pixels SKIPPED:", "Lighting skin pixels SKIPPED:")


def pixel_skip(log: Path, command: list[str], size: int, sha256: str) -> str:
    """Validate one lighting execution's whole-line evidence, or exempt a parse."""
    # Arguments following the Godot user-argument delimiter are not engine flags.
    engine_args = command[:command.index("--")] if "--" in command else command
    if "--script" not in engine_args or engine_args.index("--script") + 1 >= len(engine_args):
        return ""
    script = engine_args[engine_args.index("--script") + 1]
    if script not in PIXEL_CONTRACTS or "--check-only" in engine_args:
        return ""
    expected, _, minimum = PIXEL_CONTRACTS[script]
    skips = {marker: name for name, (marker, _, _) in PIXEL_CONTRACTS.items()}
    completions = [(name, re.compile(pattern)) for name, (_, pattern, _) in PIXEL_CONTRACTS.items()]
    completion_prefixes = (b"Lighting segment filter:", b"Lighting skin patterns:")
    skip_prefixes = (b"Lighting segment pixels SKIPPED:", b"Lighting skin pixels SKIPPED:")
    outcome = ""
    reported_checks = 0
    successful_checks = 0
    continuation = False
    read_bytes = 0
    digest = hashlib.sha256()
    with log.open("rb") as stream:
        while fragment := stream.readline(65536):
            read_bytes += len(fragment)
            if read_bytes > size:
                raise ValueError("log changed during skip inspection")
            digest.update(fragment)
            # A marker is short and must occupy a complete line; do not treat a
            # continuation fragment of a long line as a standalone marker.
            if not continuation and (fragment.endswith(b"\n") or len(fragment) < 65536):
                line = fragment.removesuffix(b"\n").removesuffix(b"\r")
                if line.startswith(skip_prefixes) and line not in skips:
                    raise ValueError("malformed lighting skip marker")
                if line in skips:
                    if outcome or skips[line] != script:
                        raise ValueError("duplicate, contradictory or mismatched lighting marker")
                    outcome = "skipped"
                completion_found = False
                for name, pattern in completions:
                    match = pattern.fullmatch(line)
                    if match:
                        completion_found = True
                        if outcome or name != script:
                            raise ValueError("duplicate, contradictory or mismatched lighting marker")
                        reported_checks = int(match.group(1))
                        if reported_checks < minimum or match.group(2) != b"0":
                            raise ValueError("lighting completion has too few checks or failures")
                        outcome = "completed"
                if line.startswith(completion_prefixes) and not completion_found:
                    raise ValueError("malformed lighting completion marker")
                if line.startswith(b"FAIL "):
                    raise ValueError("lighting output contains a failed assertion")
                if line.startswith(b"ok   "):
                    if outcome:
                        raise ValueError("lighting assertion appears after terminal marker")
                    successful_checks += 1
            continuation = not fragment.endswith(b"\n")
    if read_bytes != size or digest.hexdigest() != sha256:
        raise ValueError("log changed during skip inspection")
    if outcome == "skipped":
        if successful_checks:
            raise ValueError("lighting skip contradicts assertion output")
        return expected.decode("ascii")
    if outcome != "completed" or successful_checks != reported_checks:
        raise ValueError("lighting execution lacks matching complete assertion evidence")
    return ""


def read_run(directory: Path, max_log_bytes: int) -> dict:
    item = {"name": directory.name, "directory": directory.name, "reason": "invalid_report",
            "ok": False, "skipped": False, "skip_reason": "", "time": 0.0,
            "detail": "", "diagnostics": []}
    try:
        report_path, log = directory / "report.json", directory / "engine.log"
        if (directory.is_symlink() or report_path.is_symlink() or log.is_symlink()
                or directory.resolve() != directory.parent.resolve() / directory.name):
            raise ValueError("linked evidence is not supported")
        if not report_path.is_file() or not log.is_file():
            raise ValueError("missing report.json or engine.log (interrupted capture or incomplete artifact)")
        with report_path.open("rb") as stream:
            raw = stream.read(MAX_REPORT_BYTES + 1)
        if len(raw) > MAX_REPORT_BYTES:
            raise ValueError("report exceeds the 256 KiB metadata limit")
        report = json.loads(raw)
        if not isinstance(report, dict) or report.get("format") != "openrc-godot-check v1":
            raise ValueError("unsupported report format")
        if report.get("reason") not in REASONS:
            raise ValueError("unknown verdict reason")
        if type(report.get("ok")) is not bool or type(report.get("complete")) is not bool:
            raise ValueError("invalid verdict flags")
        code = report.get("exit_code")
        if type(code) is not int or not 0 <= code <= 255:
            raise ValueError("invalid wrapper exit code")
        if report["ok"] != (code == 0) or report["ok"] != (report["reason"] == "passed"):
            raise ValueError("contradictory verdict and exit code")
        elapsed = report.get("elapsed_seconds")
        if type(elapsed) not in (int, float) or not math.isfinite(elapsed) or elapsed < 0:
            raise ValueError("invalid elapsed duration")
        required = report.get("required_text")
        if (not isinstance(required, list) or len(required) > 128
                or any(not isinstance(s, str) or not s or len(s) > 4096 or "\n" in s or "\r" in s for s in required)):
            raise ValueError("invalid completion markers")
        counts = report.get("counts")
        if (not isinstance(counts, dict) or any(type(counts.get(k)) is not int or counts[k] < 0
                                               for k in ("error", "warning"))):
            raise ValueError("invalid diagnostic counts")
        if type(report.get("warnings_as_errors")) is not bool:
            raise ValueError("missing warning policy")
        size = report.get("log_bytes")
        if type(size) is not int or not 0 <= size <= max_log_bytes:
            raise ValueError("log size is invalid or exceeds --max-log-bytes")
        expected_hash = report.get("log_sha256")
        if not isinstance(expected_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_hash):
            raise ValueError("missing/invalid log hash; regenerate older reports with the current runner")
        digest = hashlib.sha256()
        read_bytes = 0
        skip, tail = None, b""
        with log.open("rb") as stream:
            while block := stream.read(65536):
                read_bytes += len(block)
                if read_bytes > max_log_bytes or read_bytes > size:
                    raise ValueError("log exceeds its declared size or reader limit")
                digest.update(block)
                if skip is None and b" SKIPPED: " in tail + block:
                    skip = True
                tail = block[-9:]
        if read_bytes != size or digest.hexdigest() != expected_hash:
            raise ValueError("log size/hash mismatch; evidence changed or is incomplete")
        if skip:
            # Rare path: re-read only logs containing the token to extract the declared line.
            skip = next((match.group(1) for match in DECLARED_SKIP.finditer(
                log.read_bytes().decode("utf-8", "replace"))
                if not match.group(1).startswith(PIXEL_SKIP_PREFIXES)), None)
        scanned = inspect_log(log, required, max_chars=read_bytes)
        if counts != scanned["counts"] or report.get("missing_required_text") != scanned["missing_required_text"]:
            raise ValueError("log diagnostics/completion disagree with report")
        if report["ok"] and (not report["complete"] or type(report.get("process_exit")) is not int
                             or report["process_exit"] != 0 or counts["error"]
                             or (report["warnings_as_errors"] and counts["warning"])
                             or scanned["missing_required_text"]):
            raise ValueError("success contradicts process, completeness or diagnostic policy")
        if report["reason"] not in CAPTURE_ERRORS:
            if not report["complete"] or type(report.get("process_exit")) is not int:
                raise ValueError("completed verdict lacks a completed process")
            expected_reason = (
                "process_exit" if report["process_exit"] != 0 else
                "engine_error" if counts["error"] else
                "warning" if report["warnings_as_errors"] and counts["warning"] else
                "missing_required_text" if scanned["missing_required_text"] else "passed")
            if report["reason"] != expected_reason:
                raise ValueError("verdict reason contradicts process/log policy")
        command = report.get("command")
        if not isinstance(command, list) or not command or any(not isinstance(s, str) for s in command):
            raise ValueError("invalid command identity")
        label = str(report.get("label", "godot"))[:256]
        if "--script" in command and command.index("--script") + 1 < len(command):
            label = command[command.index("--script") + 1][:512]
        elif "--import" in command:
            label = "resource import"
        detail = f"process_exit={report.get('process_exit')}; complete={report['complete']}; "
        detail += f"errors={counts['error']}; warnings={counts['warning']}\n{str(report.get('detail', ''))[:2000]}"
        if scanned["missing_required_text"]:
            detail += f"\nMissing completion text: {scanned['missing_required_text']}"
        # Named pixel contracts require their own evidence and cannot be skipped
        # by a matching line printed from an unrelated script or parse command.
        skip = (pixel_skip(log, command, size, expected_hash) or skip) if report["ok"] else ""
        if skip:
            detail += f"\n{skip}"
        item.update(name=label, reason="skipped" if skip else report["reason"], ok=report["ok"],
                    skipped=bool(skip), skip_reason=skip, time=elapsed,
                    detail=detail, diagnostics=scanned["diagnostics"][:3])
    except (OSError, ValueError, TypeError, OverflowError, RecursionError) as error:
        item["detail"] = str(error)[:2000]
    return item


def collect_runs(root: Path, *, max_runs: int = 10000, max_log_bytes: int = 64 * 1024 * 1024,
                 max_total_log_bytes: int = 512 * 1024 * 1024) -> list[dict]:
    if (type(max_runs) is not int or not 1 <= max_runs <= 10000
            or any(type(n) is not int or n <= 0 for n in (max_log_bytes, max_total_log_bytes))):
        raise ValueError("max-runs must be 1..10000 and log byte limits positive integers")
    root = Path(root)
    if not root.is_dir():
        raise ValueError(f"report collection does not exist: {root}")
    directories = []
    for index, path in enumerate(root.iterdir()):
        if index >= 20000:
            raise ValueError("too many collection entries; use a dedicated collection")
        if path.is_dir() or path.is_symlink():
            directories.append(path)
            if len(directories) > max_runs:
                raise ValueError("too many run directories; use a dedicated collection or raise --max-runs")
    if not directories:
        raise ValueError("no run directories; an empty collection is not a passing test run")
    items = []
    remaining = max_total_log_bytes
    for path in sorted(directories):
        log = path / "engine.log"
        # Never inspect linked run directories when accounting for the read budget.
        if (not path.is_symlink() and path.resolve() == path.parent.resolve() / path.name
                and not log.is_symlink() and log.is_file()):
            remaining -= log.stat().st_size
            if remaining < 0:
                raise ValueError("collection exceeds --max-total-log-bytes; narrow the collection or raise the limit")
        items.append(read_run(path, max_log_bytes))
    return items


def hint_text(item: dict) -> str:
    if item["skipped"] and item["skip_reason"].startswith(PIXEL_SKIP_PREFIXES):
        return "Pixel assertions did not run; a display-backed run is required."
    return HINTS.get(item["reason"], "Checked invocation completed.")


def detail_text(item: dict) -> str:
    lines = [hint_text(item), item["detail"],
             f"Evidence: {item['directory']}/report.json and engine.log"]
    for sample in item["diagnostics"][:3]:
        lines.append(f"log:{sample['line']} {sample['kind']}: {sample['message']}")
        lines.extend(sample["context"])
    return "\n".join(lines)


def write_junit(path: Path, items: list[dict]) -> None:
    if not items:
        raise ValueError("cannot publish an empty invocation collection")
    failures = sum(not item["ok"] and item["reason"] not in CAPTURE_ERRORS for item in items)
    errors = sum(item["reason"] in CAPTURE_ERRORS for item in items)
    skipped = sum(item["skipped"] for item in items)
    duration = sum(item['time'] for item in items)
    if not math.isfinite(duration):
        raise ValueError("aggregate elapsed duration is not finite")
    suite = ET.Element("testsuite", name="OpenRC checked Godot invocations", tests=str(len(items)),
                       failures=str(failures), errors=str(errors), skipped=str(skipped),
                       time=f"{duration:.6f}")
    for item in items:
        case = ET.SubElement(suite, "testcase", classname="OpenRC.GodotCommand",
                             name=XML_UNSAFE.sub("\ufffd", f"{item['name']} [{item['directory']}]"),
                             time=f"{item['time']:.6f}")
        if not item["ok"]:
            tag = "error" if item["reason"] in CAPTURE_ERRORS else "failure"
            node = ET.SubElement(case, tag, type=item["reason"], message=HINTS[item["reason"]])
            node.text = XML_UNSAFE.sub("\ufffd", detail_text(item))
        elif item["skipped"]:
            node = ET.SubElement(case, "skipped", message=XML_UNSAFE.sub(
                "\ufffd", f"{hint_text(item)} {item['skip_reason']}"))
            node.text = XML_UNSAFE.sub("\ufffd", detail_text(item))
        else:
            ET.SubElement(case, "system-out").text = XML_UNSAFE.sub("\ufffd", detail_text(item))
    # Exclusive creation preserves earlier evidence and never follows an existing symlink.
    with Path(path).open("xb") as stream:
        ET.ElementTree(suite).write(stream, encoding="utf-8", xml_declaration=True)


def main() -> int:
    sys.stdout.reconfigure(errors="replace")
    sys.stderr.reconfigure(errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("collection", type=Path, help="dedicated directory of checked-run subdirectories")
    parser.add_argument("--junit", type=Path, help="new JUnit XML file; parent directory must exist")
    parser.add_argument("--max-runs", type=int, default=10000)
    parser.add_argument("--max-log-bytes", type=int, default=64 * 1024 * 1024)
    parser.add_argument("--max-total-log-bytes", type=int, default=512 * 1024 * 1024)
    args = parser.parse_args()
    try:
        items = collect_runs(args.collection, max_runs=args.max_runs, max_log_bytes=args.max_log_bytes,
                             max_total_log_bytes=args.max_total_log_bytes)
        if args.junit:
            write_junit(args.junit, items)
    except (OSError, ValueError) as error:
        print(f"Diagnostic summary refused: {error}", file=sys.stderr)
        return 2
    failed = [item for item in items if not item["ok"]]
    skipped = [item for item in items if item["skipped"]]
    print(f"{len(items)} invocations: {len(items) - len(failed) - len(skipped)} passed, "
          f"{len(skipped)} skipped, {len(failed)} failed or invalid.")
    for item in skipped[:20]:
        print(f"\n{item['name']} [skipped]\n{detail_text(item)}")
    if len(skipped) > 20:
        print(f"{len(skipped) - 20} additional skips; see the JUnit file and per-run reports.")
    for item in failed[:20]:
        print(f"\n{item['name']} [{item['reason']}]\n{detail_text(item)}")
    if len(failed) > 20:
        print(f"{len(failed) - 20} additional failures; see the JUnit file and per-run reports.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
