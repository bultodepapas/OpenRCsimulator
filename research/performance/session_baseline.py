#!/usr/bin/env python3
"""Run deterministic, paired full-session CPU probes and reduce their reports.

The defaults request 2,400 warmup ticks (10 simulated seconds) and 14,400
sample ticks (60 simulated seconds) at 240 Hz. These are simulation durations,
not real-time qualification. Run this tool alone on the machine being measured.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Iterable, Sequence


FORMAT = "openrc-session-cost v1"
BASELINE_FORMAT = "openrc-session-baseline v1"
REQUIRED_GODOT_VERSION = "4.7.2"
DEFAULT_AIRCRAFT = (
    "jensen-das-ugly-stik-60",
    "p51d-mustang-120",
    "turbo-lumber-evolution",
)
CASES = ("trim", "maneuver", "runway", "lake")
OBSERVERS = ("on", "off")
TIMING_ARRAYS = ("tick_usec", "input_usec", "simulation_usec")
CODE_SUFFIXES = {
    ".gd", ".py", ".gdshader", ".cs", ".cpp", ".c", ".h", ".hpp",
    ".ts", ".tsx", ".js", ".mjs", ".sh", ".bash", ".ps1", ".bat",
    ".json", ".toml", ".yaml", ".yml", ".godot", ".tscn", ".tres",
    ".gdextension",
}
ENGINE_ERROR_RE = re.compile(r"\b(?:SCRIPT\s+)?ERROR(?:\s*:|\b)", re.IGNORECASE)
VERSION_RE = re.compile(r"(?<![0-9])v?4\.7\.2(?=$|[.\-\s(])")
AIRCRAFT_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")


class ProbeReportError(ValueError):
    """A probe report does not satisfy the v1 contract."""


def _is_int(value: Any) -> bool:
    """JSON integers must not accept Python bool, which subclasses int."""
    return type(value) is int


def _json_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON number {value} is forbidden")


def _finite_values(value: Any, path: str = "report") -> list[str]:
    errors: list[str] = []
    if isinstance(value, float) and not math.isfinite(value):
        errors.append(f"{path} must be finite")
    elif isinstance(value, dict):
        for key, child in value.items():
            errors.extend(_finite_values(child, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            errors.extend(_finite_values(child, f"{path}[{index}]"))
    return errors


def _nonempty_string(report: dict[str, Any], key: str, errors: list[str]) -> str | None:
    value = report.get(key)
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{key} must be a non-empty string")
        return None
    return value


def _count_object(
    report: dict[str, Any],
    key: str,
    errors: list[str],
    *,
    positive_sample: bool = False,
) -> dict[str, int] | None:
    value = report.get(key)
    if not isinstance(value, dict):
        errors.append(f"{key} must be an object")
        return None
    counts: dict[str, int] = {}
    for field in ("warmup_ticks", "sample_ticks"):
        count = value.get(field)
        if not _is_int(count) or count < 0:
            errors.append(f"{key}.{field} must be a non-negative integer")
            continue
        if field == "sample_ticks" and positive_sample and count < 1:
            errors.append(f"{key}.sample_ticks must be positive")
            continue
        counts[field] = count
    if len(counts) != 2:
        return None
    return counts


def validate_probe_report(
    report: Any,
    *,
    expected: dict[str, Any] | None = None,
    allow_incomplete: bool = False,
) -> list[str]:
    """Return contract errors for a parsed ``openrc-session-cost v1`` report.

    Partial reports are structurally checked and retained by the runner, but
    are rejected for paired timing unless ``allow_incomplete`` is explicitly
    requested by a caller inspecting a failure ledger.
    """
    if not isinstance(report, dict):
        return ["probe report must be a JSON object"]

    errors = _finite_values(report)
    if report.get("format") != FORMAT:
        errors.append(f"format must be {FORMAT!r}")

    aircraft_id = _nonempty_string(report, "aircraft_id", errors)
    case_id = _nonempty_string(report, "case_id", errors)
    complete = report.get("complete")
    if type(complete) is not bool:
        errors.append("complete must be a boolean")
        complete = None
    failure = report.get("failure")
    if not isinstance(failure, str):
        errors.append("failure must be a string")
        failure = None
    elif complete is True and failure:
        errors.append("complete report must have an empty failure string")
    elif complete is False and not failure.strip():
        errors.append("incomplete report must explain its failure")

    observer = report.get("observer")
    if type(observer) is not bool:
        errors.append("observer must be a boolean")
        observer = None

    requested = _count_object(report, "requested", errors, positive_sample=True)
    completed = _count_object(report, "completed", errors)
    if requested is not None and completed is not None:
        for field in ("warmup_ticks", "sample_ticks"):
            if completed[field] > requested[field]:
                errors.append(f"completed.{field} exceeds requested.{field}")
        if complete is True and completed != requested:
            errors.append("complete report must complete all requested ticks")

    if requested is not None and completed is not None and observer is not None:
        arrays: dict[str, list[int]] = {}
        for key in TIMING_ARRAYS:
            values = report.get(key)
            if not isinstance(values, list):
                errors.append(f"{key} must be an array")
                continue
            parsed: list[int] = []
            for index, item in enumerate(values):
                if not _is_int(item) or item < 0:
                    errors.append(f"{key}[{index}] must be a non-negative integer")
                else:
                    parsed.append(item)
            arrays[key] = parsed

        if len(arrays) == len(TIMING_ARRAYS):
            lengths = {len(arrays[key]) for key in TIMING_ARRAYS}
            if len(lengths) != 1:
                errors.append("timing arrays must have equal lengths")
            else:
                array_length = next(iter(lengths))
                if observer is False:
                    if array_length != 0:
                        errors.append("observer-off timing arrays must be empty")
                elif complete is True:
                    if array_length != requested["sample_ticks"]:
                        errors.append("complete observer-on timing arrays must match requested sample ticks")
                else:
                    # The producer can retain timings for one failed attempted
                    # tick even though completed.sample_ticks excludes it.
                    minimum = completed["sample_ticks"]
                    if array_length not in (minimum, minimum + 1):
                        errors.append("incomplete observer-on timing arrays must match completed samples or one failed attempt")

                for index in range(min(len(arrays["tick_usec"]), len(arrays["input_usec"]), len(arrays["simulation_usec"]))):
                    if arrays["tick_usec"][index] != arrays["input_usec"][index] + arrays["simulation_usec"][index]:
                        errors.append(f"tick_usec[{index}] must equal input_usec + simulation_usec")
                        break

    for field, minimum in (("measured_wall_usec", 0), ("final_tick", 0), ("input_reads", 0)):
        value = report.get(field)
        if not _is_int(value) or value < minimum:
            errors.append(f"{field} must be a non-negative integer")

    tick_hz = report.get("tick_hz")
    if not _is_int(tick_hz) or tick_hz != 240:
        errors.append("tick_hz must equal the simulation rate of 240")

    setup = report.get("setup_usec")
    if not isinstance(setup, dict):
        errors.append("setup_usec must be an object")
    else:
        if not setup:
            errors.append("setup_usec must contain at least one phase")
        for key, value in setup.items():
            if not isinstance(key, str) or not key.strip():
                errors.append("setup_usec phase names must be non-empty strings")
            if not _is_int(value) or value < 0:
                errors.append(f"setup_usec.{key} must be a non-negative integer")

    machine = report.get("machine")
    if not isinstance(machine, dict):
        errors.append("machine must be an object")
    else:
        for key in ("os", "processor", "architecture", "godot"):
            value = machine.get(key)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"machine.{key} must be a non-empty string")
        cpu_count = machine.get("logical_cpu_count")
        if not _is_int(cpu_count) or cpu_count < 1:
            errors.append("machine.logical_cpu_count must be a positive integer")
        godot = machine.get("godot")
        if isinstance(godot, str) and not VERSION_RE.search(godot):
            errors.append("machine.godot must identify Godot 4.7.2")

    world = report.get("world")
    if not isinstance(world, dict):
        errors.append("world must be an object")
    else:
        for key in ("identity", "lake_identity"):
            value = world.get(key)
            if not isinstance(value, str):
                errors.append(f"world.{key} must be a string")
            elif complete is True and not value.strip():
                errors.append(f"complete report requires non-empty world.{key}")
        proxies = world.get("proxies")
        if not _is_int(proxies) or proxies < 0:
            errors.append("world.proxies must be a non-negative integer")
        field = world.get("field")
        if not isinstance(field, str) or field != "default":
            errors.append("world.field must be 'default'")

    scope = report.get("scope")
    if not isinstance(scope, str) or not scope.strip():
        errors.append("scope must be a non-empty string")

    if requested is not None and completed is not None:
        expected_final = requested["warmup_ticks"] + requested["sample_ticks"]
        final_tick = report.get("final_tick")
        if _is_int(final_tick):
            if complete is True and final_tick != expected_final:
                errors.append("complete report final_tick must equal warmup_ticks + sample_ticks")
            elif complete is False and final_tick > expected_final + 1:
                errors.append("incomplete report final_tick exceeds the one-tick failure allowance")
            elif complete is False and final_tick < completed["warmup_ticks"] + completed["sample_ticks"]:
                errors.append("incomplete report final_tick is below completed tick counts")
        reads = report.get("input_reads")
        if _is_int(reads):
            if complete is True and reads != expected_final:
                errors.append("complete report input_reads must equal warmup_ticks + sample_ticks")
            elif complete is False and reads > expected_final + 1:
                errors.append("incomplete report input_reads exceeds the one-tick failure allowance")

    if observer is True and all(isinstance(report.get(key), list) for key in TIMING_ARRAYS):
        wall = report.get("measured_wall_usec")
        tick_values = report["tick_usec"]
        if _is_int(wall) and all(_is_int(value) and value >= 0 for value in tick_values) and sum(tick_values) > wall:
            errors.append("sum(tick_usec) must not exceed measured_wall_usec")

    if complete is True:
        wall = report.get("measured_wall_usec")
        if _is_int(wall) and wall < 1:
            errors.append("complete report measured_wall_usec must be positive")
        fingerprint = report.get("fingerprint")
        if not isinstance(fingerprint, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", fingerprint):
            errors.append("complete report fingerprint must be a 64-digit SHA-256 hex string")
    else:
        fingerprint = report.get("fingerprint")
        if not isinstance(fingerprint, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", fingerprint):
            errors.append("fingerprint must be a 64-digit SHA-256 hex string")

    if expected:
        for key in ("aircraft_id", "case_id", "observer"):
            if key in expected and report.get(key) != expected[key]:
                errors.append(f"{key} does not match requested run")
        if "requested" in expected and requested is not None and requested != expected["requested"]:
            errors.append("requested tick counts do not match requested run")

    if complete is False and not allow_incomplete:
        errors.append(f"probe reported incomplete: {failure or 'unspecified failure'}")
    return errors


def parse_probe_file(path: Path) -> tuple[dict[str, Any] | None, str | None]:
    """Read one raw probe report without treating malformed JSON as success."""
    try:
        with path.open("r", encoding="utf-8") as stream:
            value = json.load(stream, parse_constant=_json_constant)
    except FileNotFoundError:
        return None, "probe did not create its report"
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        return None, f"probe report is unreadable or malformed: {error}"
    if not isinstance(value, dict):
        return None, "probe report must be a JSON object"
    return value, None


def percentile_nearest_rank(values: Iterable[int | float], percentile: float) -> int | float:
    """Return the nearest-rank percentile, where ``percentile`` is 0..100."""
    if isinstance(percentile, bool) or not isinstance(percentile, (int, float)) or not math.isfinite(percentile):
        raise ValueError("percentile must be a finite number")
    if percentile <= 0 or percentile > 100:
        raise ValueError("percentile must be in (0, 100]")
    samples = list(values)
    if not samples:
        raise ValueError("at least one sample is required")
    for value in samples:
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError("samples must be finite numbers, not booleans")
    samples.sort()
    rank = max(1, math.ceil((percentile / 100.0) * len(samples)))
    return samples[rank - 1]


def reduce_pair(on_report: dict[str, Any] | None, off_report: dict[str, Any] | None) -> dict[str, Any]:
    """Compare a pair; expose overhead only for complete identical trajectories."""
    reasons: list[str] = []
    if not isinstance(on_report, dict):
        reasons.append("observer-on report unavailable")
    if not isinstance(off_report, dict):
        reasons.append("observer-off report unavailable")
    for mode, report in (("on", on_report), ("off", off_report)):
        if isinstance(report, dict):
            reasons.extend(f"observer-{mode}: {error}" for error in validate_probe_report(report))

    on_rate: float | None = None
    off_rate: float | None = None
    fingerprints_equal: bool | None = None
    world_equal: bool | None = None
    machine_equal: bool | None = None

    if isinstance(on_report, dict) and isinstance(off_report, dict):
        on_sample = on_report.get("requested", {}).get("sample_ticks") if isinstance(on_report.get("requested"), dict) else None
        off_sample = off_report.get("requested", {}).get("sample_ticks") if isinstance(off_report.get("requested"), dict) else None
        on_wall = on_report.get("measured_wall_usec")
        off_wall = off_report.get("measured_wall_usec")
        if _is_int(on_sample) and on_sample > 0 and _is_int(on_wall) and on_wall >= 0:
            on_rate = on_wall / on_sample
        if _is_int(off_sample) and off_sample > 0 and _is_int(off_wall) and off_wall >= 0:
            off_rate = off_wall / off_sample

        if on_report.get("complete") is not True:
            reasons.append("observer-on report is incomplete")
        if off_report.get("complete") is not True:
            reasons.append("observer-off report is incomplete")
        if on_report.get("observer") is not True:
            reasons.append("observer-on report has the wrong observer mode")
        if off_report.get("observer") is not False:
            reasons.append("observer-off report has the wrong observer mode")

        fingerprints_equal = on_report.get("fingerprint") == off_report.get("fingerprint")
        world_equal = on_report.get("world") == off_report.get("world")
        machine_equal = on_report.get("machine") == off_report.get("machine")
        if not fingerprints_equal:
            reasons.append("observer modes produced different fingerprints")
        if not world_equal:
            reasons.append("observer modes used different world identities")
        if not machine_equal:
            reasons.append("observer modes reported different machines")

        for key in ("aircraft_id", "case_id", "requested", "completed", "final_tick"):
            if on_report.get(key) != off_report.get(key):
                reasons.append(f"observer modes differ in {key}")

    comparable = not reasons and on_rate is not None and off_rate is not None
    overhead = on_rate - off_rate if comparable else None
    return {
        "fingerprints_equal": fingerprints_equal,
        "world_equal": world_equal,
        "machine_equal": machine_equal,
        "observer_on_wall_usec_per_tick": on_rate,
        "observer_off_wall_usec_per_tick": off_rate,
        "observer_overhead_usec_per_tick": overhead,
        "comparable": comparable,
        "reasons": reasons,
    }


def alternating_observer_order(repeat_index: int) -> tuple[str, str]:
    """Alternate the first observer mode by one-based repeat number."""
    if not _is_int(repeat_index) or repeat_index < 1:
        raise ValueError("repeat_index must be a positive integer")
    return ("on", "off") if repeat_index % 2 == 1 else ("off", "on")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _git(root: Path, *args: str) -> bytes:
    result = subprocess.run(
        ["git", *args], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        details = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"git {' '.join(args)} failed: {details}")
    return result.stdout


def _nul_paths(data: bytes) -> list[str]:
    return [os.fsdecode(path) for path in data.split(b"\0") if path]


def capture_workspace_identity(root: Path) -> dict[str, Any]:
    """Record the commit, full status text, and hashes for dirty/untracked code."""
    commit = _git(root, "rev-parse", "HEAD").decode("ascii", errors="replace").strip()
    branch = _git(root, "branch", "--show-current").decode("utf-8", errors="replace").strip()
    status_text = _git(root, "status", "--porcelain=v1", "--untracked-files=all").decode("utf-8", errors="replace")
    changed_tracked = _nul_paths(_git(root, "diff", "--name-only", "-z", "HEAD"))
    untracked = _nul_paths(_git(root, "ls-files", "--others", "--exclude-standard", "-z"))

    def file_records(paths: Iterable[str], tracked: bool) -> list[dict[str, Any]]:
        records: list[dict[str, Any]] = []
        for relative in sorted(set(paths), key=str.casefold):
            path = root / relative
            if path.suffix.lower() not in CODE_SUFFIXES:
                continue
            exists = path.is_file()
            records.append({
                "path": relative.replace("\\", "/"),
                "tracked": tracked,
                "present": exists,
                "sha256": _sha256_file(path) if exists else None,
            })
        return records

    return {
        "commit": commit,
        "branch": branch,
        "status_porcelain": status_text.splitlines(),
        "dirty_tracked_code": file_records(changed_tracked, True),
        "untracked_code": file_records(untracked, False),
    }


def capture_system_identity() -> dict[str, Any]:
    """Record stable public platform facts; do not serialize environment vars."""
    return {
        "platform": platform.platform(),
        "system": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "logical_cpu_count": os.cpu_count(),
        "python": platform.python_version(),
    }


def resolve_executable(value: str) -> Path:
    path = Path(value).expanduser()
    if path.is_file():
        return path.resolve()
    found = shutil.which(value)
    if found:
        return Path(found).resolve()
    raise RuntimeError(f"Godot executable not found: {value}")


def inspect_godot(executable: Path, timeout: float) -> dict[str, Any]:
    result = subprocess.run(
        [str(executable), "--version"], cwd=executable.parent,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        encoding="utf-8", errors="replace", timeout=min(timeout, 30.0), check=False,
    )
    version_text = result.stdout.strip()
    engine_errors = [line for line in version_text.splitlines() if ENGINE_ERROR_RE.search(line)]
    if result.returncode != 0:
        raise RuntimeError(f"Godot --version exited {result.returncode}: {version_text}")
    if engine_errors:
        raise RuntimeError(f"Godot --version emitted an engine error: {' | '.join(engine_errors)}")
    if not VERSION_RE.search(version_text):
        raise RuntimeError(f"expected Godot {REQUIRED_GODOT_VERSION}; got {version_text!r}")
    binary = executable.with_name(executable.name.replace("_console.exe", ".exe"))
    runtime_binary = binary if executable.name.endswith("_console.exe") and binary.is_file() else executable
    return {
        "path": str(executable),
        "version": version_text,
        "required_version": REQUIRED_GODOT_VERSION,
        "sha256": _sha256_file(executable),
        "runtime_binary_path": str(runtime_binary),
        "runtime_binary_sha256": _sha256_file(runtime_binary),
    }


def _engine_error_lines(log_text: str) -> list[str]:
    clean = re.sub(r"\x1b\[[0-9;]*m", "", log_text)
    return [line.strip() for line in clean.splitlines() if ENGINE_ERROR_RE.search(line)]


def _terminate(process: subprocess.Popen[Any]) -> None:
    try:
        if os.name == "nt":
            process.kill()
        else:
            os.killpg(process.pid, signal.SIGKILL)
    except (OSError, ProcessLookupError):
        try:
            process.kill()
        except OSError:
            pass
    process.wait()


def _run_probe(
    *,
    godot: Path,
    app_dir: Path,
    probe: Path,
    output_json: Path,
    log_path: Path,
    aircraft_id: str,
    case_id: str,
    observer: bool,
    warmup_ticks: int,
    sample_ticks: int,
    timeout: float,
) -> dict[str, Any]:
    command = [
        str(godot), "--headless", "--path", str(app_dir), "--script", str(probe), "--",
        f"--output={output_json.resolve()}",
        f"--aircraft={aircraft_id}",
        f"--case={case_id}",
        f"--warmup-ticks={warmup_ticks}",
        f"--sample-ticks={sample_ticks}",
        f"--observer={'on' if observer else 'off'}",
    ]
    timed_out = False
    exit_code: int | None = None
    launch_error: str | None = None
    with log_path.open("w", encoding="utf-8", errors="replace") as log_stream:
        try:
            process = subprocess.Popen(
                command,
                cwd=app_dir.parent,
                stdout=log_stream,
                stderr=subprocess.STDOUT,
                start_new_session=(os.name != "nt"),
                creationflags=(subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0),
            )
            try:
                exit_code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                _terminate(process)
                exit_code = process.returncode
        except OSError as error:
            launch_error = f"could not launch Godot: {error}"

    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    engine_errors = _engine_error_lines(log_text)
    expected = {
        "aircraft_id": aircraft_id,
        "case_id": case_id,
        "observer": observer,
        "requested": {"warmup_ticks": warmup_ticks, "sample_ticks": sample_ticks},
    }
    report, report_error = parse_probe_file(output_json)
    validation_errors: list[str] = []
    if report is not None:
        validation_errors = validate_probe_report(report, expected=expected)
    failures: list[str] = []
    if launch_error:
        failures.append(launch_error)
    if timed_out:
        failures.append(f"Godot timed out after {timeout:g}s")
    if exit_code != 0:
        failures.append(f"Godot exited with status {exit_code}")
    if engine_errors:
        failures.append("engine error in log: " + " | ".join(engine_errors))
    if report_error:
        failures.append(report_error)
    failures.extend(validation_errors)
    if report is not None and report.get("complete") is True and exit_code != 0:
        failures.append("complete report is rejected because the process did not exit successfully")
    return {
        "observer": "on" if observer else "off",
        "command": command,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "engine_errors": engine_errors,
        "log": str(log_path),
        "report_file": str(output_json),
        "report": report,
        "validation_errors": validation_errors,
        "failures": failures,
        "accepted": not failures and report is not None,
    }


def _safe_report_view(run: dict[str, Any]) -> dict[str, Any]:
    report = run.get("report")
    if not isinstance(report, dict):
        return {"accepted": False, "failures": run["failures"]}
    sample_ticks = report.get("requested", {}).get("sample_ticks") if isinstance(report.get("requested"), dict) else None
    wall = report.get("measured_wall_usec")
    wall_per_tick = wall / sample_ticks if _is_int(wall) and _is_int(sample_ticks) and sample_ticks > 0 else None
    return {
        "accepted": run["accepted"],
        "observer": report.get("observer"),
        "complete": report.get("complete"),
        "failure": report.get("failure"),
        "fingerprint": report.get("fingerprint"),
        "final_tick": report.get("final_tick"),
        "measured_wall_usec": wall,
        "measured_wall_usec_per_sample_tick": wall_per_tick,
        "validation_errors": run["validation_errors"],
        "failures": run["failures"],
        "timing_usec_nearest_rank": {
            key: {f"p{p}": percentile_nearest_rank(report[key], p) for p in (50, 95, 99, 100)}
            for key in TIMING_ARRAYS
            if run["accepted"] and report.get(key)
        },
        "report_file": run["report_file"],
        "log": run["log"],
    }


def _write_json(path: Path, value: Any) -> None:
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")
    temporary.replace(path)


def _lock_path(root: Path) -> Path:
    key = hashlib.sha256(str(root.resolve()).encode("utf-8")).hexdigest()[:16]
    return Path(tempfile.gettempdir()) / f"openrc-session-baseline-{key}.lock"


def acquire_lock(root: Path) -> Path:
    path = _lock_path(root)
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY
    descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, "w", encoding="ascii") as stream:
        stream.write(f"pid={os.getpid()}\n")
    return path


def parse_id_list(values: Sequence[str] | None, defaults: Sequence[str], label: str) -> list[str]:
    raw = list(values) if values else list(defaults)
    parsed = [part.strip() for value in raw for part in value.split(",") if part.strip()]
    if not parsed:
        raise ValueError(f"at least one {label} is required")
    if len(set(parsed)) != len(parsed):
        raise ValueError(f"duplicate {label} values are not allowed")
    return parsed


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="pinned Godot 4.7.2 executable")
    parser.add_argument("--out", type=Path, required=True, help="new or empty output directory")
    parser.add_argument("--probe", type=Path, help="probe script; defaults beside this runner")
    parser.add_argument("--aircraft", action="append", help="catalog ID; repeat or pass comma-separated IDs")
    parser.add_argument("--case", action="append", help="trim, maneuver, runway, or lake; repeat or comma-separate")
    parser.add_argument("--warmup-ticks", type=int, default=2400)
    parser.add_argument("--sample-ticks", type=int, default=14400)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=1800.0, help="per-probe timeout in seconds")
    return parser


def _failure_report(config: dict[str, Any], reason: str) -> dict[str, Any]:
    return {
        "format": BASELINE_FORMAT,
        "complete": False,
        "status": "failed",
        "failure": reason,
        "configuration": config,
        "pairs": [],
        "summary": [],
        "failures": [reason],
    }


def run_campaign(args: argparse.Namespace) -> int:
    root = Path(__file__).resolve().parents[2]
    app_dir = root / "app"
    probe = (args.probe or Path(__file__).with_name("session_probe.gd")).resolve()
    output_dir = args.out.expanduser().resolve()
    if output_dir.exists():
        if not output_dir.is_dir() or any(output_dir.iterdir()):
            raise RuntimeError(f"output must be a fresh or empty directory: {output_dir}")
    else:
        output_dir.mkdir(parents=True)

    try:
        lock = acquire_lock(root)
    except FileExistsError as error:
        raise RuntimeError("another session baseline campaign holds this repository's lock") from error

    config: dict[str, Any] = {
        "aircraft": args.aircraft_ids,
        "cases": args.case_ids,
        "warmup_ticks": args.warmup_ticks,
        "sample_ticks": args.sample_ticks,
        "repeats": args.repeats,
        "timeout_seconds_per_probe": args.timeout,
        "tick_hz": 240,
        "meaning": "simulation ticks; default warmup is 10 simulated seconds and default sample is 60 simulated seconds, not real-time qualification",
    }
    failures: list[str] = []
    pairs: list[dict[str, Any]] = []
    summaries: list[dict[str, Any]] = []
    metadata: dict[str, Any] = {"system": capture_system_identity()}
    try:
        try:
            metadata["workspace"] = capture_workspace_identity(root)
            godot = resolve_executable(args.godot)
            metadata["engine"] = inspect_godot(godot, args.timeout)
            metadata["probe"] = {
                "path": str(probe),
                "sha256": _sha256_file(probe) if probe.is_file() else None,
            }
            if not probe.is_file():
                raise RuntimeError(f"probe script not found: {probe}")
            if not app_dir.is_dir():
                raise RuntimeError(f"app project directory not found: {app_dir}")
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            failures.append(str(error))
            report = _failure_report(config, str(error))
            report["metadata"] = metadata
            _write_json(output_dir / "session_baseline.json", report)
            print(f"session baseline failed: {error}", file=sys.stderr)
            return 1

        all_run_count = 0
        for aircraft_id in args.aircraft_ids:
            for case_id in args.case_ids:
                case_pairs: list[dict[str, Any]] = []
                for repeat_index in range(1, args.repeats + 1):
                    reports: dict[str, dict[str, Any] | None] = {"on": None, "off": None}
                    runs: dict[str, dict[str, Any]] = {}
                    order = alternating_observer_order(repeat_index)
                    run_dir = output_dir / "runs" / aircraft_id / case_id
                    run_dir.mkdir(parents=True, exist_ok=True)
                    for mode in order:
                        observer = mode == "on"
                        stem = f"repeat-{repeat_index:02d}-observer-{mode}"
                        json_path = run_dir / f"{stem}.json"
                        log_path = run_dir / f"{stem}.log"
                        run = _run_probe(
                            godot=godot,
                            app_dir=app_dir,
                            probe=probe,
                            output_json=json_path,
                            log_path=log_path,
                            aircraft_id=aircraft_id,
                            case_id=case_id,
                            observer=observer,
                            warmup_ticks=args.warmup_ticks,
                            sample_ticks=args.sample_ticks,
                            timeout=args.timeout,
                        )
                        reports[mode] = run["report"] if run["accepted"] else None
                        runs[mode] = _safe_report_view(run)
                        print(f"{aircraft_id}/{case_id}/{stem}: {'accepted' if run['accepted'] else 'failed'}", flush=True)
                        all_run_count += 1
                        for message in run["failures"]:
                            failures.append(f"{aircraft_id}/{case_id}/repeat-{repeat_index:02d}/{mode}: {message}")
                    reduced = reduce_pair(reports["on"], reports["off"])
                    pair_record = {
                        "aircraft_id": aircraft_id,
                        "case_id": case_id,
                        "repeat": repeat_index,
                        "observer_order": list(order),
                        "runs": runs,
                        **reduced,
                    }
                    if not reduced["comparable"]:
                        failures.append(
                            f"{aircraft_id}/{case_id}/repeat-{repeat_index:02d}: "
                            + "; ".join(reduced["reasons"] or ["pair is not comparable"])
                        )
                    pairs.append(pair_record)
                    case_pairs.append(pair_record)

                values = [
                    pair["observer_overhead_usec_per_tick"]
                    for pair in case_pairs
                    if pair["comparable"] and pair["observer_overhead_usec_per_tick"] is not None
                ]
                summaries.append({
                    "aircraft_id": aircraft_id,
                    "case_id": case_id,
                    "requested_pairs": args.repeats,
                    "comparable_pairs": len(values),
                    "overhead_usec_per_tick_nearest_rank": {
                        f"p{percentile}": percentile_nearest_rank(values, percentile) if values else None
                        for percentile in (50, 95, 99)
                    },
                })

        complete = not failures and all(len([p for p in pairs if p["aircraft_id"] == a and p["case_id"] == c and p["comparable"]]) == args.repeats
                                       for a in args.aircraft_ids for c in args.case_ids)
        report = {
            "format": BASELINE_FORMAT,
            "complete": complete,
            "status": "complete" if complete else "failed",
            "failure": "" if complete else "one or more runs failed or paired trajectories were not comparable",
            "configuration": config,
            "metadata": metadata,
            "pairs": pairs,
            "summary": summaries,
            "failures": failures,
        }
        _write_json(output_dir / "session_baseline.json", report)
        if complete:
            print(f"session baseline complete: {all_run_count} probes; report {output_dir / 'session_baseline.json'}")
            return 0
        print(f"session baseline failed: {len(failures)} issue(s); report {output_dir / 'session_baseline.json'}", file=sys.stderr)
        return 1
    finally:
        try:
            lock.unlink(missing_ok=True)
        except OSError:
            pass


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.warmup_ticks < 0 or args.warmup_ticks > 72000:
            raise ValueError("warmup ticks must be within 0..72000")
        if args.sample_ticks < 1 or args.sample_ticks > 72000:
            raise ValueError("sample ticks must be within 1..72000")
        if args.repeats < 1:
            raise ValueError("repeats must be positive")
        if isinstance(args.timeout, bool) or not math.isfinite(args.timeout) or args.timeout <= 0:
            raise ValueError("timeout must be a positive finite number")
        args.aircraft_ids = parse_id_list(args.aircraft, DEFAULT_AIRCRAFT, "aircraft ID")
        for aircraft_id in args.aircraft_ids:
            if not AIRCRAFT_ID_RE.fullmatch(aircraft_id):
                raise ValueError(f"invalid aircraft ID: {aircraft_id!r}")
        args.case_ids = parse_id_list(args.case, ("trim",), "case")
        invalid_cases = [case_id for case_id in args.case_ids if case_id not in CASES]
        if invalid_cases:
            raise ValueError(f"unknown case(s): {', '.join(invalid_cases)}")
        return run_campaign(args)
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"session baseline: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
