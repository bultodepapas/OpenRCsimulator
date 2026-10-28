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


FORMAT = "openrc-session-cost v2"
LEGACY_FORMAT = "openrc-session-cost v1"
BASELINE_FORMAT = "openrc-session-baseline v1"
REQUIRED_GODOT_VERSION = "4.8-beta1"
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
VERSION_RE = re.compile(r"(?<![0-9])v?4\.8[.-]beta1(?=$|[.\-\s(])")
LEGACY_VERSION_RE = re.compile(r"(?<![0-9])v?4\.7\.2(?=$|[.\-\s(])")
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
    """Return contract errors for a parsed session cost report.

    Partial reports are structurally checked and retained by the runner, but
    are rejected for paired timing unless ``allow_incomplete`` is explicitly
    requested by a caller inspecting a failure ledger.
    """
    if not isinstance(report, dict):
        return ["probe report must be a JSON object"]

    errors = _finite_values(report)
    report_format = report.get("format")
    if report_format not in (FORMAT, LEGACY_FORMAT):
        errors.append(f"format must be {FORMAT!r} or {LEGACY_FORMAT!r}")

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
        version_re = LEGACY_VERSION_RE if report_format == LEGACY_FORMAT else VERSION_RE
        if isinstance(godot, str) and not version_re.search(godot):
            errors.append("machine.godot must identify the pinned version for this report")

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

    if report_format == FORMAT:
        for field in ("solver_sha256", "aircraft_sha256"):
            value = report.get(field)
            if complete is True and (not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value)):
                errors.append(f"complete report requires {field} as a SHA-256 hex string")
        boundaries = report.get("fingerprint_boundaries")
        if not _is_int(boundaries) or boundaries < 0:
            errors.append("fingerprint_boundaries must be a non-negative integer")
        elif completed is not None and complete is True and boundaries != 1 + sum(completed.values()):
            errors.append("complete fingerprint must include the initial boundary and every completed tick")
        backend = report.get("backend")
        if not isinstance(backend, dict):
            errors.append("backend must be an object")
        else:
            requested_backend = backend.get("requested")
            actual = backend.get("actual")
            stats = backend.get("native_stats")
            if requested_backend not in ("gdscript_reference", "native"):
                errors.append("backend.requested must identify a supported backend")
            if not isinstance(actual, dict) or not isinstance(stats, dict):
                errors.append("backend.actual and backend.native_stats must be objects")
            elif complete is True:
                if actual.get("backend") != requested_backend:
                    errors.append("complete report actual backend must equal the requested backend")
                if requested_backend == "native":
                    for field in ("binary_sha256", "source_sha256", "lock_sha256"):
                        if not isinstance(actual.get(field), str) or not re.fullmatch(r"[0-9a-f]{64}", actual[field]):
                            errors.append(f"native backend requires a valid {field}")
                    if not isinstance(actual.get("backend_version"), str) or not actual["backend_version"]:
                        errors.append("native backend requires backend_version")
                    if not _is_int(actual.get("abi_version")) or actual["abi_version"] < 1:
                        errors.append("native backend requires a positive abi_version")
                    ticks = sum(completed.values()) if completed is not None else 0
                    for field, minimum in (("context_calls", ticks), ("stage_calls", 4 * ticks)):
                        if not _is_int(stats.get(field)) or stats[field] < minimum:
                            errors.append(f"native {field} must cover every completed tick")
                    if stats.get("timing") is not False:
                        errors.append("native internal stage timing must be disabled")
                elif actual != {"backend": "gdscript_reference"} or stats:
                    errors.append("reference backend identity/stats are invalid")

    if expected:
        for key in ("aircraft_id", "case_id", "observer"):
            if key in expected and report.get(key) != expected[key]:
                errors.append(f"{key} does not match requested run")
        if "requested" in expected and requested is not None and requested != expected["requested"]:
            errors.append("requested tick counts do not match requested run")
        if "physics_backend" in expected and (report_format != FORMAT or not isinstance(report.get("backend"), dict)
                                               or report["backend"].get("requested") != expected["physics_backend"]):
            errors.append("backend does not match requested run")

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

        for key in ("format", "aircraft_id", "case_id", "requested", "completed", "final_tick", "backend",
                    "fingerprint_boundaries", "solver_sha256", "solver_identity_kind", "template_release",
                    "probe_sha256", "aircraft_sha256"):
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


def reduce_backend_pair(reference: dict[str, Any] | None, native: dict[str, Any] | None) -> dict[str, Any]:
    """Compare production backends only after a complete, identical trajectory."""
    reasons: list[str] = []
    for label, report in (("reference", reference), ("native", native)):
        if not isinstance(report, dict):
            reasons.append(f"{label} report unavailable")
        else:
            reasons.extend(f"{label}: {error}" for error in validate_probe_report(report))
            if report.get("format") != FORMAT:
                reasons.append(f"{label}: backend comparisons require v2 fingerprints")
            if report.get("observer") is not True:
                reasons.append(f"{label}: callback timings require observer on")
            expected = "gdscript_reference" if label == "reference" else "native"
            if not isinstance(report.get("backend"), dict) or report["backend"].get("requested") != expected:
                reasons.append(f"{label}: requested backend is not {expected}")
    if isinstance(reference, dict) and isinstance(native, dict):
        for key in ("fingerprint", "fingerprint_boundaries", "solver_sha256", "solver_identity_kind",
                    "template_release", "probe_sha256", "aircraft_sha256",
                    "aircraft_id", "case_id", "requested", "completed", "final_tick", "input_reads",
                    "world", "machine", "tick_hz"):
            if reference.get(key) != native.get(key):
                reasons.append(f"backends differ in {key}")
    comparable = not reasons
    result: dict[str, Any] = {"comparable": comparable, "reasons": reasons,
                              "reference_usec_per_tick": None, "native_usec_per_tick": None,
                              "reference_over_native": None}
    if comparable:
        assert reference is not None and native is not None
        ticks = reference["requested"]["sample_ticks"]
        for label, report in (("reference", reference), ("native", native)):
            result[f"{label}_usec_per_tick"] = sum(report["tick_usec"]) / ticks
            result[f"{label}_simulation_usec_per_tick"] = sum(report["simulation_usec"]) / ticks
        if result["native_usec_per_tick"] > 0:
            result["reference_over_native"] = result["reference_usec_per_tick"] / result["native_usec_per_tick"]
    return result


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


def native_source_digest(root: Path) -> str:
    """Match the native builder's digest, so receipt identity binds the measured sources."""
    source = root / "research/native-kernel/src"
    files = sorted([*source.glob("*.cpp"), *source.glob("*.hpp")])
    if not files:
        raise RuntimeError("native kernel source files are missing")
    digest = hashlib.sha256()
    for path in files:
        digest.update(path.name.encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def app_source_digest(app: Path) -> str:
    """Hash application code and text data, excluding generated cache and installed native binaries."""
    digest = hashlib.sha256()
    paths = sorted(path for path in app.rglob("*") if path.is_file() and path.suffix.lower() in CODE_SUFFIXES
                   and not any(part in (".godot", "native", "captures") for part in path.relative_to(app).parts))
    if not paths:
        raise RuntimeError("application source files are missing")
    for path in paths:
        digest.update(path.relative_to(app).as_posix().encode() + b"\0" + path.read_bytes() + b"\0")
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
    physics_backend: str,
    native_source_sha256: str,
    release_executable: bool = False,
    executable_sha256: str = "",
    probe_sha256: str = "",
) -> dict[str, Any]:
    command = ([str(godot), "--headless", "--audio-driver", "Dummy", "--", "--quick-flight",
                "--native-qualification=session"] if release_executable else
               [str(godot), "--headless", "--path", str(app_dir), "--script", str(probe), "--"])
    command += [
        f"--output={output_json.resolve()}",
        f"--aircraft={aircraft_id}",
        f"--case={case_id}",
        f"--warmup-ticks={warmup_ticks}",
        f"--sample-ticks={sample_ticks}",
        f"--observer={'on' if observer else 'off'}",
        f"--physics-backend={physics_backend}",
    ]
    timed_out = False
    exit_code: int | None = None
    launch_error: str | None = None
    executable_before = _sha256_file(godot) if release_executable else ""
    native_library = godot.parent / "native/kernel/libopenrc_native_kernel.so"
    library_before = (_sha256_file(native_library) if release_executable and physics_backend == "native"
                      and native_library.is_file() else "")
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
        "physics_backend": physics_backend,
        "requested": {"warmup_ticks": warmup_ticks, "sample_ticks": sample_ticks},
    }
    report, report_error = parse_probe_file(output_json)
    validation_errors: list[str] = []
    if report is not None:
        validation_errors = validate_probe_report(report, expected=expected)
        if release_executable:
            if report.get("template_release") is not True:
                validation_errors.append("session did not run in a release template")
            if report.get("solver_identity_kind") != "packaged-executable-v1" \
                    or report.get("solver_sha256") != executable_sha256:
                validation_errors.append("session did not identify the verified release executable")
            if report.get("probe_sha256") != probe_sha256:
                validation_errors.append("packaged probe differs from the recorded source")
        if physics_backend == "native" and report.get("complete") is True:
            backend = report.get("backend")
            actual = backend.get("actual", {}) if isinstance(backend, dict) else {}
            if not isinstance(actual, dict) or actual.get("source_sha256") != native_source_sha256:
                validation_errors.append("installed native source identity differs from the current C++ sources")
            if release_executable and (not library_before or not isinstance(actual, dict)
                                       or actual.get("binary_sha256") != library_before):
                validation_errors.append("native identity differs from the release sibling library")
    failures: list[str] = []
    if launch_error:
        failures.append(launch_error)
    if release_executable and (executable_before != executable_sha256 or _sha256_file(godot) != executable_sha256):
        failures.append("release executable changed before or during the probe")
    if release_executable and physics_backend == "native" and (not library_before or not native_library.is_file()
                                                                  or _sha256_file(native_library) != library_before):
        failures.append("release native library is missing or changed during the probe")
    if timed_out:
        failures.append(f"Godot timed out after {timeout:g}s")
    if exit_code != 0:
        failures.append(f"Godot exited with status {exit_code}")
    if engine_errors:
        failures.append("engine error in log: " + " | ".join(engine_errors))
    if release_executable and "NATIVE_QUALIFICATION mode=session verdict=pass" not in log_text:
        failures.append("release qualification host did not report a passing session")
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
        "fingerprint_boundaries": report.get("fingerprint_boundaries"),
        "backend": report.get("backend"),
        "solver_sha256": report.get("solver_sha256"),
        "aircraft_sha256": report.get("aircraft_sha256"),
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
    parser.add_argument("--godot", help="pinned Godot 4.8-beta1 executable")
    parser.add_argument("--release-executable", action="store_true",
                        help="use --godot as the actual exported Linux release executable")
    parser.add_argument("--out", type=Path, required=True, help="new or empty output directory")
    parser.add_argument("--probe", type=Path, help="probe script; defaults beside this runner")
    parser.add_argument("--aircraft", action="append", help="catalog ID; repeat or pass comma-separated IDs")
    parser.add_argument("--case", action="append", help="trim, maneuver, runway, or lake; repeat or comma-separate")
    parser.add_argument("--warmup-ticks", type=int, default=2400)
    parser.add_argument("--sample-ticks", type=int, default=14400)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=1800.0, help="per-probe timeout in seconds")
    parser.add_argument("--physics-backend", choices=("gdscript_reference", "native"), default="gdscript_reference",
                        help="backend for the default observer-on/off pairs")
    parser.add_argument("--compare-backends", action="store_true",
                        help="alternate observer-on reference/native pairs instead of observer pairs")
    parser.add_argument("--compare-campaigns", nargs=2, type=Path, metavar=("BEFORE", "AFTER"),
                        help="compare two completed backend campaign JSON files")
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
        "pair_type": "backends" if args.compare_backends else "observer",
        "physics_backend": args.physics_backend,
        "release_executable": args.release_executable,
        "timeout_seconds_per_probe": args.timeout,
        "tick_hz": 240,
        "meaning": "simulation ticks; default warmup is 10 simulated seconds and default sample is 60 simulated seconds, not real-time qualification",
    }
    failures: list[str] = []
    pairs: list[dict[str, Any]] = []
    summaries: list[dict[str, Any]] = []
    metadata: dict[str, Any] = {"system": capture_system_identity()}
    native_identities: set[str] = set()
    solver_identities: set[str] = set()
    try:
        try:
            metadata["workspace"] = capture_workspace_identity(root)
            godot = resolve_executable(args.godot)
            metadata["engine"] = inspect_godot(godot, args.timeout)
            metadata["native_source_sha256"] = native_source_digest(root)
            metadata["app_source_sha256"] = app_source_digest(app_dir)
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
                    modes = ("reference", "native") if args.compare_backends else ("on", "off")
                    reports: dict[str, dict[str, Any] | None] = {mode: None for mode in modes}
                    runs: dict[str, dict[str, Any]] = {}
                    order = modes if repeat_index % 2 == 1 else tuple(reversed(modes))
                    run_dir = output_dir / "runs" / aircraft_id / case_id
                    run_dir.mkdir(parents=True, exist_ok=True)
                    for mode in order:
                        observer = True if args.compare_backends else mode == "on"
                        physics_backend = ("gdscript_reference" if mode == "reference" else "native") \
                            if args.compare_backends else args.physics_backend
                        stem = f"repeat-{repeat_index:02d}-{'backend' if args.compare_backends else 'observer'}-{mode}"
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
                            physics_backend=physics_backend,
                            native_source_sha256=metadata["native_source_sha256"],
                            release_executable=args.release_executable,
                            executable_sha256=metadata["engine"]["sha256"],
                            probe_sha256=metadata["probe"]["sha256"],
                        )
                        reports[mode] = run["report"] if run["accepted"] else None
                        if run["accepted"] and isinstance(run["report"], dict):
                            accepted_report = run["report"]
                            solver_identities.add(accepted_report["solver_sha256"])
                            if physics_backend == "native":
                                native_identities.add(json.dumps(accepted_report["backend"]["actual"], sort_keys=True))
                        runs[mode] = _safe_report_view(run)
                        runs[mode]["report_relative_path"] = json_path.relative_to(output_dir).as_posix()
                        runs[mode]["report_sha256"] = _sha256_file(json_path) if json_path.is_file() else None
                        print(f"{aircraft_id}/{case_id}/{stem}: {'accepted' if run['accepted'] else 'failed'}", flush=True)
                        all_run_count += 1
                        for message in run["failures"]:
                            failures.append(f"{aircraft_id}/{case_id}/repeat-{repeat_index:02d}/{mode}: {message}")
                    reduced = (reduce_backend_pair(reports["reference"], reports["native"]) if args.compare_backends
                               else reduce_pair(reports["on"], reports["off"]))
                    pair_record = {
                        "aircraft_id": aircraft_id,
                        "case_id": case_id,
                        "repeat": repeat_index,
                        "backend_order" if args.compare_backends else "observer_order": list(order),
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

                metric = "reference_over_native" if args.compare_backends else "observer_overhead_usec_per_tick"
                values = [pair[metric] for pair in case_pairs if pair["comparable"] and pair[metric] is not None]
                summaries.append({
                    "aircraft_id": aircraft_id,
                    "case_id": case_id,
                    "requested_pairs": args.repeats,
                    "comparable_pairs": len(values),
                    ("reference_over_native_nearest_rank" if args.compare_backends else "overhead_usec_per_tick_nearest_rank"): {
                        f"p{percentile}": percentile_nearest_rank(values, percentile) if values else None
                        for percentile in (50, 95, 99)
                    },
                })

        if native_source_digest(root) != metadata["native_source_sha256"]:
            failures.append("native C++ source changed during the campaign")
        if app_source_digest(app_dir) != metadata["app_source_sha256"]:
            failures.append("application code or text data changed during the campaign")
        if _sha256_file(probe) != metadata["probe"]["sha256"]:
            failures.append("probe changed during the campaign")
        if _sha256_file(godot) != metadata["engine"]["sha256"]:
            failures.append("Godot executable changed during the campaign")
        if len(solver_identities) > 1:
            failures.append("solver source identity changed between runs")
        if len(native_identities) > 1:
            failures.append("installed native backend identity changed between runs")
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


def _campaign_runs(path: Path) -> tuple[dict[str, Any], dict[tuple[str, str, int], dict[str, Any]]]:
    """Re-read and verify retained raw reports; do not trust the campaign's summary alone."""
    with path.open(encoding="utf-8") as stream:
        campaign = json.load(stream, parse_constant=_json_constant)
    if not isinstance(campaign, dict) or campaign.get("format") != BASELINE_FORMAT or campaign.get("complete") is not True:
        raise ValueError(f"{path}: campaign is not complete")
    config, metadata, pairs = campaign.get("configuration"), campaign.get("metadata"), campaign.get("pairs")
    if not isinstance(config, dict) or config.get("pair_type") != "backends" or not isinstance(metadata, dict) or not isinstance(pairs, list):
        raise ValueError(f"{path}: backend campaign metadata or pairs are missing")
    aircraft, cases, repeats = config.get("aircraft"), config.get("cases"), config.get("repeats")
    if (not isinstance(aircraft, list) or not aircraft or not isinstance(cases, list) or not cases
            or not _is_int(repeats) or repeats < 1 or any(not isinstance(item, str) for item in aircraft + cases)):
        raise ValueError(f"{path}: invalid campaign configuration")
    expected_keys = {(air, case, repeat) for air in aircraft for case in cases for repeat in range(1, repeats + 1)}
    runs: dict[tuple[str, str, int], dict[str, Any]] = {}
    native_ids: set[str] = set()
    solver_ids: set[str] = set()
    for pair in pairs:
        if not isinstance(pair, dict) or pair.get("comparable") is not True or not isinstance(pair.get("runs"), dict):
            raise ValueError(f"{path}: invalid or incomparable pair")
        key = (pair.get("aircraft_id"), pair.get("case_id"), pair.get("repeat"))
        if key not in expected_keys or key in runs:
            raise ValueError(f"{path}: unexpected or duplicate pair {key}")
        raw: dict[str, Any] = {}
        for mode in ("reference", "native"):
            item = pair["runs"].get(mode)
            if not isinstance(item, dict) or item.get("accepted") is not True or not isinstance(item.get("report_relative_path"), str):
                raise ValueError(f"{path}: missing accepted {mode} report")
            raw_path = (path.parent / item["report_relative_path"]).resolve()
            if not raw_path.is_relative_to(path.parent.resolve()) or not raw_path.is_file() or _sha256_file(raw_path) != item.get("report_sha256"):
                raise ValueError(f"{path}: missing or changed {mode} raw report")
            report, error = parse_probe_file(raw_path)
            if error or report is None:
                raise ValueError(f"{raw_path}: {error}")
            raw[mode] = report
        reduced = reduce_backend_pair(raw["reference"], raw["native"])
        if not reduced["comparable"]:
            raise ValueError(f"{path}: raw pair is not comparable: {reduced['reasons']}")
        for report in raw.values():
            if (report["aircraft_id"], report["case_id"]) != key[:2] or report["requested"] != {
                "warmup_ticks": config.get("warmup_ticks"), "sample_ticks": config.get("sample_ticks")
            }:
                raise ValueError(f"{path}: raw report differs from campaign configuration")
        identity = raw["native"]["backend"]["actual"]
        if identity["source_sha256"] != metadata.get("native_source_sha256"):
            raise ValueError(f"{path}: native binary does not match campaign source")
        native_ids.add(json.dumps(identity, sort_keys=True))
        solver_ids.add(raw["reference"]["solver_sha256"])
        runs[key] = {"raw": raw, "reduced": reduced}
    if set(runs) != expected_keys or len(native_ids) != 1 or len(solver_ids) != 1:
        raise ValueError(f"{path}: missing pairs or inconsistent native/solver identity")
    return campaign, runs


def compare_campaigns(before_path: Path, after_path: Path, output_dir: Path) -> int:
    """Compare separate native builds only when their reference trajectories and inputs match."""
    output_dir = output_dir.expanduser().resolve()
    if output_dir.exists() and (not output_dir.is_dir() or any(output_dir.iterdir())):
        raise ValueError(f"output must be a fresh or empty directory: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []
    rows: list[dict[str, Any]] = []
    try:
        before_path, after_path = before_path.expanduser().resolve(), after_path.expanduser().resolve()
        before, old_runs = _campaign_runs(before_path)
        after, new_runs = _campaign_runs(after_path)
        for key in ("aircraft", "cases", "warmup_ticks", "sample_ticks", "repeats", "tick_hz", "pair_type"):
            if before["configuration"].get(key) != after["configuration"].get(key):
                failures.append(f"campaign configuration differs in {key}")
        old_meta, new_meta = before["metadata"], after["metadata"]
        for key in ("app_source_sha256", "system"):
            if not old_meta.get(key) or old_meta.get(key) != new_meta.get(key):
                failures.append(f"campaign metadata differs in {key}")
        for group, key in (("engine", "sha256"), ("engine", "runtime_binary_sha256"), ("probe", "sha256")):
            old_group, new_group = old_meta.get(group), new_meta.get(group)
            if (not isinstance(old_group, dict) or not isinstance(new_group, dict)
                    or not old_group.get(key) or old_group.get(key) != new_group.get(key)):
                failures.append(f"campaign metadata differs in {group}.{key}")
        if set(old_runs) != set(new_runs):
            failures.append("campaign pair sets differ")
        for key in sorted(set(old_runs) & set(new_runs)):
            old, new = old_runs[key], new_runs[key]
            for field in ("fingerprint", "fingerprint_boundaries", "solver_sha256", "solver_identity_kind",
                          "template_release", "probe_sha256", "aircraft_sha256",
                          "world", "machine", "requested", "completed", "final_tick", "input_reads"):
                if old["raw"]["reference"].get(field) != new["raw"]["reference"].get(field):
                    failures.append(f"{key}: reference reports differ in {field}")
            old_id = old["raw"]["native"]["backend"]["actual"]
            new_id = new["raw"]["native"]["backend"]["actual"]
            for field in ("backend_version", "abi_version", "lock_sha256"):
                if old_id.get(field) != new_id.get(field):
                    failures.append(f"{key}: native build identity differs in {field}")
            old_rate, new_rate = old["reduced"]["native_usec_per_tick"], new["reduced"]["native_usec_per_tick"]
            rows.append({"aircraft_id": key[0], "case_id": key[1], "repeat": key[2],
                         "before_native_usec_per_tick": old_rate, "after_native_usec_per_tick": new_rate,
                         "before_over_after": old_rate / new_rate if new_rate > 0 else None,
                         "before_native_identity": old_id, "after_native_identity": new_id})
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        failures.append(str(error))
    summary = []
    if not failures:
        for aircraft_id, case_id in sorted({(row["aircraft_id"], row["case_id"]) for row in rows}):
            selected = [row for row in rows if row["aircraft_id"] == aircraft_id and row["case_id"] == case_id]
            old_median = percentile_nearest_rank([row["before_native_usec_per_tick"] for row in selected], 50)
            new_median = percentile_nearest_rank([row["after_native_usec_per_tick"] for row in selected], 50)
            summary.append({"aircraft_id": aircraft_id, "case_id": case_id, "repeats": len(selected),
                            "before_native_median_usec_per_tick": old_median,
                            "after_native_median_usec_per_tick": new_median,
                            "before_over_after_medians": old_median / new_median if new_median > 0 else None})
    result = {"format": "openrc-session-campaign-comparison v1", "complete": not failures,
              "before": str(before_path), "after": str(after_path), "pairs": rows if not failures else [],
              "summary": summary, "failures": failures,
              "scope": "Separate build campaigns, not interleaved across builds; host variation can bias the comparison. Raw callback stopwatch excludes fingerprint and guard work, which can perturb subsequent ticks."}
    _write_json(output_dir / "session_comparison.json", result)
    print(f"session campaign comparison: {'complete' if not failures else 'failed'}; report {output_dir / 'session_comparison.json'}")
    return 0 if not failures else 1


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.compare_campaigns:
            if args.release_executable:
                raise ValueError("--release-executable applies to a new campaign, not a campaign comparison")
            return compare_campaigns(*args.compare_campaigns, args.out)
        if not args.godot:
            raise ValueError("--godot is required for a campaign")
        if args.release_executable and args.probe:
            raise ValueError("--release-executable uses the fixed embedded probe; --probe is not permitted")
        if args.warmup_ticks < 0 or args.warmup_ticks > 72000:
            raise ValueError("warmup ticks must be within 0..72000")
        if args.sample_ticks < 1 or args.sample_ticks > 72000:
            raise ValueError("sample ticks must be within 1..72000")
        if args.repeats < 1:
            raise ValueError("repeats must be positive")
        if args.compare_backends and args.physics_backend != "gdscript_reference":
            raise ValueError("--compare-backends cannot be combined with --physics-backend=native")
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
