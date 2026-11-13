#!/usr/bin/env python3
"""Run deterministic, paired full-session CPU probes and reduce their reports.

The defaults request 2,400 warmup ticks (10 simulated seconds) and 14,400
sample ticks (60 simulated seconds) at 240 Hz. These are simulation durations,
not real-time qualification. Run this tool alone on the machine being measured.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
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
IDENTICAL_FORMAT = "openrc-session-identical-campaign v1"
REQUIRED_GODOT_VERSION = "4.8-beta2"
REQUIRED_GODOT_BUILD = "4.8.beta2.official.cafc17a19"
REQUIRED_GODOT_REPORT = "4.8-beta2 (official)"
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
VERSION_RE = re.compile(r"(?<![0-9])v?4\.8[.-]beta2(?=$|[.\-\s(])")
BETA1_REPORT_RE = re.compile(r"(?<![0-9])v?4\.8[.-]beta1(?=$|[.\-\s(])")
LEGACY_VERSION_RE = re.compile(r"(?<![0-9])v?4\.7\.2(?=$|[.\-\s(])")
AIRCRAFT_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
_MAC_SPEC = importlib.util.spec_from_file_location(
    "openrc_macos_reference_receipt", Path(__file__).resolve().parents[2] / "tools/release/macos_reference_receipt.py")
assert _MAC_SPEC is not None and _MAC_SPEC.loader is not None
MAC_RECEIPT = importlib.util.module_from_spec(_MAC_SPEC)
_MAC_SPEC.loader.exec_module(MAC_RECEIPT)


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
    if "experimental_native_macos" in report and type(report["experimental_native_macos"]) is not bool:
        errors.append("experimental_native_macos must be a boolean")

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
        version_res = (LEGACY_VERSION_RE,) if report_format == LEGACY_FORMAT else (VERSION_RE, BETA1_REPORT_RE)
        if isinstance(godot, str) and not any(version_re.search(godot) for version_re in version_res):
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
        if "battery" in report:
            battery = report.get("battery")
            if not isinstance(battery, dict) or set(battery) != {"mode", "data_path", "data_sha256", "dynamic", "pack"}:
                errors.append("battery must identify the selected mode, data and actual session flags")
            else:
                mode, path, digest = battery.get("mode"), battery.get("data_path"), battery.get("data_sha256")
                if mode not in ("ideal", "pack") or not isinstance(path, str) or not re.fullmatch(
                        r"res://data/aircraft/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.json", path):
                    errors.append("battery mode or aircraft data path is invalid")
                if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
                    errors.append("battery aircraft data SHA-256 is invalid")
                elif complete is True and digest != report.get("aircraft_sha256"):
                    errors.append("battery aircraft data does not match the loaded aircraft identity")
                if type(battery.get("dynamic")) is not bool or type(battery.get("pack")) is not bool:
                    errors.append("battery dynamic and pack flags must be booleans")
                elif complete is True and (battery["pack"] != (mode == "pack")
                                            or (battery["pack"] and not battery["dynamic"])):
                    errors.append("battery mode does not match the actual session")
        kind = report.get("solver_identity_kind")
        if kind is not None and kind not in ("source-tree-v1", "packaged-executable-v1", "macos-reference-bundle-v1",
                                              MAC_RECEIPT.NATIVE_KIND):
            errors.append("solver_identity_kind is unsupported")
        if report.get("template_release") is True and kind not in ("packaged-executable-v1", "macos-reference-bundle-v1",
                                                                    MAC_RECEIPT.NATIVE_KIND):
            errors.append("release report requires a supported package identity")
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
        if kind == MAC_RECEIPT.NATIVE_KIND:
            actual = backend.get("actual") if isinstance(backend, dict) else None
            if (report.get("template_release") is not True or report.get("experimental_native_macos") is not True
                    or not isinstance(machine, dict) or machine.get("os") != "macOS"
                    or machine.get("architecture") != "arm64" or not isinstance(backend, dict)
                    or backend.get("requested") != "native" or not isinstance(actual, dict)
                    or actual.get("backend") != "native" or actual.get("abi_version") != 2
                    or actual.get("backend_version") != "openrc-native-kernel-stage-v2"):
                errors.append("Mac native package identity requires the opted-in ARM64 ABI 2 native release")
        if (kind == MAC_RECEIPT.KIND and isinstance(backend, dict) and backend.get("requested") == "native"):
            errors.append("Mac reference bundle identity cannot identify the native backend")

    if expected:
        for key in ("aircraft_id", "case_id", "observer"):
            if key in expected and report.get(key) != expected[key]:
                errors.append(f"{key} does not match requested run")
        if "requested" in expected and requested is not None and requested != expected["requested"]:
            errors.append("requested tick counts do not match requested run")
        if "physics_backend" in expected and (report_format != FORMAT or not isinstance(report.get("backend"), dict)
                                               or report["backend"].get("requested") != expected["physics_backend"]):
            errors.append("backend does not match requested run")
        if "battery" in expected:
            battery = report.get("battery")
            if ((expected["battery"] is None and "battery" in report)
                    or (expected["battery"] is not None and
                        (not isinstance(battery, dict) or battery.get("mode") != expected["battery"]))):
                errors.append("battery mode does not match requested run")
        if "godot" in expected and (not isinstance(machine, dict) or machine.get("godot") != expected["godot"]):
            errors.append("machine.godot does not match requested run")

    if complete is False and not allow_incomplete:
        errors.append(f"probe reported incomplete: {failure or 'unspecified failure'}")
    return errors


def _parse_probe_bytes(raw: bytes) -> tuple[dict[str, Any] | None, str | None]:
    try:
        value = json.loads(raw.decode("utf-8"), parse_constant=_json_constant)
    except (UnicodeError, json.JSONDecodeError, ValueError) as error:
        return None, f"probe report is unreadable or malformed: {error}"
    if not isinstance(value, dict):
        return None, "probe report must be a JSON object"
    return value, None


def read_probe_capture(path: Path) -> tuple[dict[str, Any] | None, str | None, str | None]:
    """Parse and hash the same captured bytes; callers can then check the live file."""
    try:
        raw = path.read_bytes()
    except FileNotFoundError:
        return None, "probe did not create its report", None
    except OSError as error:
        return None, f"probe report is unreadable or malformed: {error}", None
    digest = hashlib.sha256(raw).hexdigest()
    report, error = _parse_probe_bytes(raw)
    return report, error, digest


def parse_probe_file(path: Path) -> tuple[dict[str, Any] | None, str | None]:
    """Read one raw probe report without treating malformed JSON as success."""
    report, error, _digest = read_probe_capture(path)
    return report, error


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

        for key in ("format", "aircraft_id", "case_id", "requested", "completed", "final_tick", "backend", "battery",
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


def mac_release_identity_error(reference: Any, native: Any) -> str:
    """Validate the relationship returned by the reference and native bundle verifiers."""
    if not isinstance(reference, dict) or not isinstance(native, dict):
        return "Mac release bundle identities are missing"
    if (reference.get("kind") != MAC_RECEIPT.KIND or reference.get("architecture") != "arm64"
            or native.get("kind") != MAC_RECEIPT.NATIVE_KIND or native.get("architecture") != "arm64"):
        return "Mac release bundle kind or architecture differs"
    ref_fields = ("sha256", "receipt_sha256", "executable_sha256", "pack_sha256", "probe_sha256",
                  "source_worktree_sha256")
    native_fields = ("sha256", "receipt_sha256", "reference_receipt_sha256", "manifest_sha256",
                     "descriptor_sha256", "library_sha256")
    if any(not isinstance(identity.get(field), str) or not re.fullmatch(r"[0-9a-f]{64}", identity[field])
           for identity, fields in ((reference, ref_fields), (native, native_fields)) for field in fields):
        return "Mac release bundle identity digest is malformed"
    if any(not isinstance(reference.get(field), str) or not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", reference[field])
           for field in ("source_commit", "source_tree")):
        return "Mac release source commit or tree identity is malformed"
    if (native["reference_receipt_sha256"] != reference["receipt_sha256"]
            or any(identity["sha256"] != hashlib.sha256((identity["receipt_sha256"] + "\narm64").encode()).hexdigest()
                   for identity in (reference, native))):
        return "Mac release receipts are not linked to their architecture identities"
    return ""


def reduce_backend_pair(reference: dict[str, Any] | None, native: dict[str, Any] | None, *,
                        mac_reference_identity: dict[str, Any] | None = None,
                        mac_native_identity: dict[str, Any] | None = None) -> dict[str, Any]:
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
        for key in ("fingerprint", "fingerprint_boundaries", "template_release", "probe_sha256", "aircraft_sha256",
                    "aircraft_id", "case_id", "requested", "completed", "final_tick", "input_reads",
                    "world", "machine", "tick_hz", "battery"):
            if reference.get(key) != native.get(key):
                reasons.append(f"backends differ in {key}")
        mac_release = mac_reference_identity is not None or mac_native_identity is not None
        if mac_release:
            error = mac_release_identity_error(mac_reference_identity, mac_native_identity)
            if error:
                reasons.append(error)
            else:
                assert mac_reference_identity is not None and mac_native_identity is not None
                actual = native.get("backend", {}).get("actual", {}) if isinstance(native.get("backend"), dict) else {}
                if (reference.get("solver_identity_kind") != MAC_RECEIPT.KIND
                        or reference.get("solver_sha256") != mac_reference_identity["sha256"]
                        or native.get("solver_identity_kind") != MAC_RECEIPT.NATIVE_KIND
                        or native.get("solver_sha256") != mac_native_identity["sha256"]
                        or reference.get("probe_sha256") != mac_reference_identity["probe_sha256"]
                        or not isinstance(actual, dict) or actual.get("binary_sha256") != mac_native_identity["library_sha256"]
                        or reference.get("experimental_native_macos") is not True
                        or native.get("experimental_native_macos") is not True):
                    reasons.append("backends do not match their linked Mac release identities")
        else:
            for key in ("solver_sha256", "solver_identity_kind"):
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


def reduce_identical_pair(a: dict[str, Any] | None, b: dict[str, Any] | None, backend: str) -> dict[str, Any]:
    """Compare two observer-on runs of the same backend without an optimization claim."""
    reasons: list[str] = []
    if backend not in ("gdscript_reference", "native"):
        reasons.append("unsupported requested backend")
    for role, report in (("a", a), ("b", b)):
        if not isinstance(report, dict):
            reasons.append(f"role {role} report unavailable")
            continue
        reasons.extend(f"role {role}: {error}" for error in validate_probe_report(
            report, expected={"observer": True, "physics_backend": backend}))
        if report.get("format") != FORMAT:
            reasons.append(f"role {role}: identical comparisons require v2 fingerprints")
        if not isinstance(report.get("solver_identity_kind"), str) or not report["solver_identity_kind"]:
            reasons.append(f"role {role}: solver identity kind is missing")
    if isinstance(a, dict) and isinstance(b, dict):
        for key in ("fingerprint", "fingerprint_boundaries", "template_release", "probe_sha256", "aircraft_sha256",
                    "aircraft_id", "case_id", "requested", "completed", "final_tick", "input_reads", "world",
                    "machine", "tick_hz", "solver_sha256", "solver_identity_kind", "battery"):
            if a.get(key) != b.get(key):
                reasons.append(f"identical roles differ in {key}")
        if a.get("experimental_native_macos", False) != b.get("experimental_native_macos", False):
            reasons.append("identical roles differ in experimental_native_macos")
        a_backend, b_backend = a.get("backend"), b.get("backend")
        if (not isinstance(a_backend, dict) or not isinstance(b_backend, dict)
                or a_backend.get("actual") != b_backend.get("actual")):
            reasons.append("identical roles use different backend identities")
    result: dict[str, Any] = {"comparable": False, "reasons": reasons,
                              "a_callback_mean_usec_per_tick": None, "b_callback_mean_usec_per_tick": None,
                              "a_over_b_callback_mean_ratio": None, "absolute_callback_mean_difference_usec_per_tick": None,
                              "absolute_ratio_deviation_percent": None}
    if not reasons:
        assert a is not None and b is not None
        ticks = a["requested"]["sample_ticks"]
        a_mean, b_mean = sum(a["tick_usec"]) / ticks, sum(b["tick_usec"]) / ticks
        if b_mean <= 0:
            reasons.append("role b inclusive callback mean is zero; ratio is undefined")
        else:
            result.update(comparable=True, a_callback_mean_usec_per_tick=a_mean, b_callback_mean_usec_per_tick=b_mean,
                          a_over_b_callback_mean_ratio=a_mean / b_mean,
                          absolute_callback_mean_difference_usec_per_tick=abs(a_mean - b_mean),
                          absolute_ratio_deviation_percent=abs(a_mean / b_mean - 1.0) * 100.0)
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


def verify_macos_release_identities(executable: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    """Recheck both linked release receipts and the executable bytes on this probe."""
    reference = MAC_RECEIPT.verify(executable, "arm64")
    native = MAC_RECEIPT.verify_native(executable, "arm64")
    error = mac_release_identity_error(reference, native)
    if error:
        raise ValueError(error)
    if _sha256_file(executable) != reference["executable_sha256"]:
        raise ValueError("Mac release executable differs from the reference receipt")
    return reference, native


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


def load_project_validator(root: Path):
    """Use the native oracle's canonical prepared-project inventory contract."""
    path = root / "research/native-kernel/run.py"
    spec = importlib.util.spec_from_file_location("openrc_session_project_validator", path)
    if spec is None or spec.loader is None:
        raise ValueError(f"Cannot load prepared-project verifier: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def mac_source_install_identity(app: Path, engine_sha256: str, source_sha256: str) -> dict[str, Any]:
    """Bind a source-editor Mac measurement to its checked receipt and selected dylib."""
    native = app / "native/kernel"
    if (app / "native").is_symlink() or native.is_symlink() or native.resolve() != app.resolve() / "native/kernel":
        raise ValueError("Mac native source directory is symlinked or outside the selected project")
    library = native / "libopenrc_native_kernel.dylib"
    descriptor = native / "openrc_native_kernel_macos.gdextension"
    receipt_file = native / "build-receipt-macos.json"
    for path in (library, descriptor, receipt_file):
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Missing regular Mac source native artifact: {path}")
    receipt = json.loads(receipt_file.read_text(encoding="utf-8"), parse_constant=_json_constant)
    row = receipt.get("platforms", {}).get("macos") if isinstance(receipt, dict) and isinstance(receipt.get("platforms"), dict) else None
    if (not isinstance(row, dict) or receipt.get("format") != "openrc-native-kernel-receipt"
            or receipt.get("backend") != "native" or row.get("backend") != "native"
            or row.get("platform") != "macos" or row.get("architecture") != "arm64"
            or row.get("qualification_scope") != "macos-arm64-fixed-wing-experimental-v1"
            or row.get("engine_sha256") != engine_sha256 or row.get("source_sha256") != source_sha256
            or not isinstance(row.get("engine"), dict) or row["engine"].get("sha256") != engine_sha256
            or not isinstance(row.get("lock_sha256"), str) or not re.fullmatch(r"[0-9a-f]{64}", row["lock_sha256"])
            or not isinstance(row.get("backend_version"), str) or not row["backend_version"]
            or not _is_int(row.get("abi_version")) or row["abi_version"] < 1
            or receipt.get("backend_version") != row["backend_version"]
            or receipt.get("abi_version") != row["abi_version"]
            or not isinstance(row.get("runtime_os_version"), str) or not row["runtime_os_version"]
            or not isinstance(row.get("runtime_os_build"), str) or not row["runtime_os_build"]):
        raise ValueError("Mac source native receipt does not match the engine, sources or experimental scope")
    binary_sha256 = _sha256_file(library)
    if row.get("binary_sha256") != binary_sha256:
        raise ValueError("Mac source native dylib differs from its receipt")
    return {"library": str(library), "binary_sha256": binary_sha256,
            "descriptor_sha256": _sha256_file(descriptor), "receipt_sha256": _sha256_file(receipt_file),
            "source_sha256": source_sha256, "engine_sha256": engine_sha256,
            "lock_sha256": row["lock_sha256"], "backend_version": row["backend_version"],
            "abi_version": row["abi_version"]}


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


def capture_mac_release_source(root: Path) -> dict[str, Any]:
    """Use the release input's real Git/worktree declaration for this checkout."""
    release_tools = str(Path(MAC_RECEIPT.__file__).resolve().parent)
    sys.path.insert(0, release_tools)
    try:
        manifest = MAC_RECEIPT._manifest()
    finally:
        sys.path.remove(release_tools)
    commit = manifest.git(root, "rev-parse", "HEAD").decode("ascii").strip()
    tree = manifest.git(root, "rev-parse", "HEAD^{tree}").decode("ascii").strip()
    dirty, worktree = manifest.worktree_identity(root)
    if (manifest.git(root, "rev-parse", "HEAD").decode("ascii").strip() != commit
            or manifest.git(root, "rev-parse", "HEAD^{tree}").decode("ascii").strip() != tree):
        raise ValueError("Git commit or tree changed while checking the Mac release source")
    return {"commit": commit, "tree": tree, "worktree_sha256": worktree, "dirty": dirty}


def mac_release_source_matches(reference: dict[str, Any], source: Any) -> bool:
    return (isinstance(source, dict) and type(source.get("dirty")) is bool
            and source.get("commit") == reference.get("source_commit")
            and source.get("tree") == reference.get("source_tree")
            and source.get("worktree_sha256") == reference.get("source_worktree_sha256"))


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
    if version_text != REQUIRED_GODOT_BUILD:
        raise RuntimeError(f"expected Godot {REQUIRED_GODOT_BUILD}; got {version_text!r}")
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
    mac_identity: dict[str, Any] | None = None,
    mac_native_identity: dict[str, Any] | None = None,
    experimental_native_macos: bool = False,
    mac_source_identity: dict[str, Any] | None = None,
    battery: str | None = None,
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
    if battery is not None:
        command.append(f"--battery={battery}")
    if experimental_native_macos:
        command.append("--experimental-native-macos=true")
    def refused(reason: str) -> dict[str, Any]:
        return {"observer": "on" if observer else "off", "command": command, "exit_code": None,
                "timed_out": False, "engine_errors": [], "log": str(log_path), "report_file": str(output_json),
                "report": None, "validation_errors": [], "failures": [reason], "accepted": False}
    if battery not in (None, "ideal", "pack"):
        return refused("battery mode must be ideal or pack")
    if mac_native_identity is not None and (not release_executable or not experimental_native_macos
                                            or mac_identity is None or mac_source_identity is not None):
        return refused("Mac native release requires explicit opt-in and both linked bundle identities")
    if experimental_native_macos and release_executable and mac_native_identity is None:
        return refused("Experimental Mac release requires verified native and reference bundles")
    if experimental_native_macos and not release_executable and physics_backend == "native" and mac_source_identity is None:
        return refused("Mac native source measurement requires a verified source installation")
    if mac_source_identity is not None:
        try:
            if (not experimental_native_macos or _sha256_file(godot) != executable_sha256
                    or mac_source_install_identity(app_dir, executable_sha256, native_source_sha256) != mac_source_identity):
                raise ValueError("Mac native source installation or engine changed before the probe")
        except (OSError, ValueError, TypeError) as error:
            return refused(str(error))
    timed_out = False
    exit_code: int | None = None
    launch_error: str | None = None
    executable_before = _sha256_file(godot) if release_executable else ""
    if mac_identity is not None:
        try:
            if mac_native_identity is not None:
                if verify_macos_release_identities(godot) != (mac_identity, mac_native_identity):
                    raise ValueError("Mac release bundle identities changed before the probe")
            elif physics_backend != "gdscript_reference" or MAC_RECEIPT.verify_for_launch(godot) != mac_identity:
                raise ValueError("Mac release requires the unchanged reference bundle")
        except (OSError, ValueError, KeyError, TypeError) as error:
            return refused(str(error))
    native_library = godot.parent / "native/kernel/libopenrc_native_kernel.so"
    library_before = (_sha256_file(native_library) if release_executable and mac_native_identity is None and physics_backend == "native"
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

    log_bytes = log_path.read_bytes()
    log_sha256 = hashlib.sha256(log_bytes).hexdigest()
    log_text = log_bytes.decode("utf-8", errors="replace")
    engine_errors = _engine_error_lines(log_text)
    expected = {
        "aircraft_id": aircraft_id,
        "case_id": case_id,
        "observer": observer,
        "physics_backend": physics_backend,
        "battery": battery,
        "godot": REQUIRED_GODOT_REPORT,
        "requested": {"warmup_ticks": warmup_ticks, "sample_ticks": sample_ticks},
    }
    report, report_error, report_sha256 = read_probe_capture(output_json)
    validation_errors: list[str] = []
    if report is not None:
        validation_errors = validate_probe_report(report, expected=expected)
        if report.get("experimental_native_macos", False) is not experimental_native_macos:
            validation_errors.append("session did not report the requested experimental Mac opt-in")
        if battery is not None and not release_executable and report.get("complete") is True:
            selected = report.get("battery")
            try:
                data_path = selected.get("data_path") if isinstance(selected, dict) else None
                if not isinstance(data_path, str) or not data_path.startswith("res://data/aircraft/"):
                    raise ValueError("selected aircraft data path is invalid")
                file = app_dir / data_path.removeprefix("res://")
                if (file.is_symlink() or not file.is_file() or not file.resolve().is_relative_to(app_dir.resolve())
                        or _sha256_file(file) != selected.get("data_sha256")):
                    raise ValueError("selected aircraft data differs from the measured project")
            except (OSError, ValueError) as error:
                validation_errors.append(str(error))
        if mac_source_identity is not None:
            machine = report.get("machine")
            if (not isinstance(machine, dict) or machine.get("os") != "macOS" or machine.get("architecture") != "arm64"
                    or report.get("solver_identity_kind") != "source-tree-v1" or report.get("template_release") is not False):
                validation_errors.append("session did not run the experimental source project on native Mac ARM64")
        if release_executable:
            if report.get("template_release") is not True:
                validation_errors.append("session did not run in a release template")
            if mac_identity is not None:
                machine = report.get("machine")
                architecture = machine.get("architecture") if isinstance(machine, dict) else None
                expected_identity = (mac_native_identity if physics_backend == "native" else mac_identity) \
                    if mac_native_identity is not None else None
                expected_kind = (MAC_RECEIPT.NATIVE_KIND if physics_backend == "native" else MAC_RECEIPT.KIND) \
                    if mac_native_identity is not None else MAC_RECEIPT.KIND
                expected_hash = expected_identity.get("sha256") if expected_identity is not None else \
                    mac_identity.get("identities", {}).get(architecture)
                if report.get("solver_identity_kind") != expected_kind \
                        or not isinstance(machine, dict) or machine.get("os") != "macOS" \
                        or (mac_native_identity is not None and architecture != "arm64") \
                        or report.get("solver_sha256") != expected_hash:
                    validation_errors.append("session did not identify the verified Mac bundle and architecture")
                if mac_identity["probe_sha256"] != probe_sha256:
                    validation_errors.append("Mac receipt probe differs from the recorded source")
            elif report.get("solver_identity_kind") != "packaged-executable-v1" \
                    or report.get("solver_sha256") != executable_sha256:
                validation_errors.append("session did not identify the verified release executable")
            if report.get("probe_sha256") != probe_sha256:
                validation_errors.append("packaged probe differs from the recorded source")
        if physics_backend == "native" and report.get("complete") is True:
            backend = report.get("backend")
            actual = backend.get("actual", {}) if isinstance(backend, dict) else {}
            if not isinstance(actual, dict) or actual.get("source_sha256") != native_source_sha256:
                validation_errors.append("installed native source identity differs from the current C++ sources")
            if mac_source_identity is not None and (not isinstance(actual, dict) or any(
                    actual.get(field) != mac_source_identity[field]
                    for field in ("binary_sha256", "source_sha256", "lock_sha256", "backend_version", "abi_version"))):
                validation_errors.append("native backend identity differs from the measured Mac source dylib")
            if mac_native_identity is not None and (not isinstance(actual, dict)
                    or actual.get("binary_sha256") != mac_native_identity.get("library_sha256")
                    or actual.get("abi_version") != 2 or actual.get("backend_version") != "openrc-native-kernel-stage-v2"):
                validation_errors.append("native identity differs from the verified Mac release dylib or ABI 2")
            if release_executable and mac_native_identity is None and (not library_before or not isinstance(actual, dict)
                                                                         or actual.get("binary_sha256") != library_before):
                validation_errors.append("native identity differs from the release sibling library")
    failures: list[str] = []
    try:
        if (_sha256_file(log_path) != log_sha256 or (report_sha256 is not None
                and _sha256_file(output_json) != report_sha256)):
            failures.append("probe report or log changed during validation")
    except OSError as error:
        failures.append(f"probe report or log unavailable during validation: {error}")
    if launch_error:
        failures.append(launch_error)
    if release_executable and (executable_before != executable_sha256 or _sha256_file(godot) != executable_sha256):
        failures.append("release executable changed before or during the probe")
    if mac_identity is not None:
        try:
            verified = (verify_macos_release_identities(godot) == (mac_identity, mac_native_identity)
                        if mac_native_identity is not None else MAC_RECEIPT.verify_for_launch(godot) == mac_identity)
            if not verified:
                failures.append("Mac release bundle changed during the probe")
        except (OSError, ValueError, KeyError, TypeError) as error:
            failures.append(f"Mac release bundle changed during the probe: {error}")
    if mac_source_identity is not None:
        try:
            if (_sha256_file(godot) != executable_sha256
                    or mac_source_install_identity(app_dir, executable_sha256, native_source_sha256) != mac_source_identity):
                failures.append("Mac native source installation or engine changed during the probe")
        except (OSError, ValueError, TypeError) as error:
            failures.append(f"Mac native source installation or engine changed during the probe: {error}")
    if release_executable and mac_native_identity is None and physics_backend == "native" and (not library_before or not native_library.is_file()
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
        "log_sha256": log_sha256,
        "report_file": str(output_json),
        "report_sha256": report_sha256,
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
    view = {
        "accepted": run["accepted"],
        "command": run.get("command"),
        "exit_code": run.get("exit_code"),
        "timed_out": run.get("timed_out"),
        "engine_errors": run.get("engine_errors"),
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
    if "battery" in report:
        view["battery"] = report["battery"]
    return view


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
    parser.add_argument("--godot", help="pinned Godot 4.8-beta2 executable")
    parser.add_argument("--release-executable", action="store_true",
                        help="use --godot as the actual exported Linux or verified Mac release executable")
    parser.add_argument("--out", type=Path, required=True, help="new or empty output directory")
    parser.add_argument("--probe", type=Path, help="probe script; defaults beside this runner")
    parser.add_argument("--project", type=Path, help="canonical app or a verified isolated research project")
    parser.add_argument("--experimental-native-macos", action="store_true",
                        help="explicit opt-in to the experimental Mac ARM64 native source or release backend")
    parser.add_argument("--aircraft", action="append", help="catalog ID; repeat or pass comma-separated IDs")
    parser.add_argument("--case", action="append", help="trim, maneuver, runway, or lake; repeat or comma-separate")
    parser.add_argument("--battery", choices=("ideal", "pack"),
                        help="explicit catalog data mode; without this option the historical ideal profile is used")
    parser.add_argument("--warmup-ticks", type=int, default=2400)
    parser.add_argument("--sample-ticks", type=int, default=14400)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=1800.0, help="per-probe timeout in seconds")
    parser.add_argument("--physics-backend", choices=("gdscript_reference", "native"), default="gdscript_reference",
                        help="backend for observer pairs or both identical-control roles")
    comparisons = parser.add_mutually_exclusive_group()
    comparisons.add_argument("--compare-backends", action="store_true",
                        help="alternate observer-on reference/native pairs instead of observer pairs")
    comparisons.add_argument("--compare-identical", action="store_true",
                        help="alternate observer-on A/A roles with the selected backend; report variation only")
    comparisons.add_argument("--compare-campaigns", nargs=2, type=Path, metavar=("BEFORE", "AFTER"),
                        help="compare completed backend campaigns; distinct Mac native release bundles are refused")
    return parser


def _failure_report(config: dict[str, Any], reason: str, *, report_format: str = BASELINE_FORMAT) -> dict[str, Any]:
    return {
        "format": report_format,
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
    identical = getattr(args, "compare_identical", False)
    report_format = IDENTICAL_FORMAT if identical else BASELINE_FORMAT
    report_name = "session_identical.json" if identical else "session_baseline.json"
    app_dir = (args.project.expanduser().resolve() if args.project is not None else (root / "app").resolve())
    probe = (args.probe or Path(__file__).with_name("session_probe.gd")).resolve()
    output_dir = args.out.expanduser().resolve()
    if output_dir == app_dir or output_dir.is_relative_to(app_dir) or app_dir.is_relative_to(output_dir):
        raise RuntimeError("campaign output and executed project must not overlap")
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
        "pair_type": "identical" if identical else "backends" if args.compare_backends else "observer",
        "physics_backend": args.physics_backend,
        "release_executable": args.release_executable,
        "experimental_native_macos": args.experimental_native_macos,
        "timeout_seconds_per_probe": args.timeout,
        "tick_hz": 240,
        "meaning": "simulation ticks; default warmup is 10 simulated seconds and default sample is 60 simulated seconds, not real-time qualification",
    }
    if args.battery is not None:
        config["battery"] = args.battery
    failures: list[str] = []
    pairs: list[dict[str, Any]] = []
    summaries: list[dict[str, Any]] = []
    metadata: dict[str, Any] = {"system": capture_system_identity()}
    native_identities: set[str] = set()
    solver_identities: dict[str, set[str]] = {"gdscript_reference": set(), "native": set()}
    project_validator = None
    project_proof: dict[str, Any] | None = None
    try:
        try:
            metadata["workspace"] = capture_workspace_identity(root)
            godot = resolve_executable(args.godot)
            if args.release_executable and MAC_RECEIPT.looks_like_bundle_executable(godot):
                wants_native = args.physics_backend == "native" or args.compare_backends
                if wants_native and not args.experimental_native_macos:
                    raise RuntimeError("Mac release benchmarks support the reference backend only")
                try:
                    if args.experimental_native_macos:
                        if (not wants_native or metadata["system"].get("system") != "Darwin"
                                or metadata["system"].get("machine", "").lower() not in ("arm64", "aarch64")):
                            raise ValueError("Mac native release requires a native ARM64 host and native measurement")
                        reference, native = verify_macos_release_identities(godot)
                        metadata["mac_reference_bundle"], metadata["mac_native_bundle"] = reference, native
                        source = capture_mac_release_source(root)
                        if not mac_release_source_matches(reference, source):
                            raise ValueError("current Git/worktree source differs from the Mac release declaration")
                        metadata["mac_release_source"] = {"before": source,
                            "scope": "Checked release source declaration; no source-to-binary reproducibility claim."}
                    else:
                        metadata["mac_reference_bundle"] = MAC_RECEIPT.verify_for_launch(godot)
                except (OSError, ValueError) as error:
                    raise RuntimeError(f"Mac release bundle identity refused: {error}") from error
            elif args.release_executable and args.experimental_native_macos:
                raise RuntimeError("Experimental Mac native release requires a verified Mac app bundle")
            metadata["engine"] = inspect_godot(godot, args.timeout)
            metadata["native_source_sha256"] = native_source_digest(root)
            if not app_dir.is_dir() or not (app_dir / "project.godot").is_file():
                raise RuntimeError(f"app project directory not found: {app_dir}")
            if args.project is not None:
                validator_path = root / "research/native-kernel/run.py"
                validator_sha256 = _sha256_file(validator_path)
                project_validator = load_project_validator(root)
                project_proof = project_validator.validate_project(app_dir)
                if not isinstance(project_proof, dict) or (app_dir != (root / "app").resolve() and not project_proof):
                    raise ValueError("Prepared project has no verified inventory proof")
                if _sha256_file(validator_path) != validator_sha256:
                    raise ValueError("Prepared-project verifier changed during validation")
                metadata["project"] = {"path": str(app_dir), "inventory_before": project_proof,
                                       "validator_sha256": validator_sha256}
            metadata["app_source_sha256"] = app_source_digest(app_dir)
            if args.experimental_native_macos and not args.release_executable \
                    and (args.compare_backends or args.physics_backend == "native"):
                metadata["mac_source_install"] = mac_source_install_identity(
                    app_dir, metadata["engine"]["sha256"], metadata["native_source_sha256"])
            metadata["probe"] = {
                "path": str(probe),
                "sha256": _sha256_file(probe) if probe.is_file() else None,
            }
            if not probe.is_file():
                raise RuntimeError(f"probe script not found: {probe}")
            if "mac_native_bundle" in metadata and (metadata["mac_reference_bundle"]["probe_sha256"] != metadata["probe"]["sha256"]
                    or metadata["mac_reference_bundle"]["executable_sha256"] != metadata["engine"]["sha256"]):
                raise RuntimeError("Mac release receipt differs from the probe or executable")
        except (OSError, ValueError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
            failures.append(str(error))
            report = _failure_report(config, str(error), report_format=report_format)
            report["metadata"] = metadata
            _write_json(output_dir / report_name, report)
            print(f"session baseline failed: {error}", file=sys.stderr)
            return 1

        all_run_count = 0
        for aircraft_id in args.aircraft_ids:
            for case_id in args.case_ids:
                case_pairs: list[dict[str, Any]] = []
                for repeat_index in range(1, args.repeats + 1):
                    modes = ("a", "b") if identical else ("reference", "native") if args.compare_backends else ("on", "off")
                    reports: dict[str, dict[str, Any] | None] = {mode: None for mode in modes}
                    runs: dict[str, dict[str, Any]] = {}
                    order = modes if repeat_index % 2 == 1 else tuple(reversed(modes))
                    run_dir = output_dir / "runs" / aircraft_id / case_id
                    run_dir.mkdir(parents=True, exist_ok=True)
                    for mode in order:
                        observer = True if identical or args.compare_backends else mode == "on"
                        physics_backend = ("gdscript_reference" if mode == "reference" else "native") \
                            if args.compare_backends else args.physics_backend
                        role_label = "identical" if identical else "backend" if args.compare_backends else "observer"
                        stem = f"repeat-{repeat_index:02d}-{role_label}-{mode}"
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
                            mac_identity=metadata.get("mac_reference_bundle"),
                            mac_native_identity=metadata.get("mac_native_bundle"),
                            experimental_native_macos=args.experimental_native_macos,
                            mac_source_identity=metadata.get("mac_source_install"),
                            battery=args.battery,
                        )
                        if ("mac_native_bundle" in metadata or identical) and run["accepted"]:
                            try:
                                if (not json_path.is_file() or not log_path.is_file()
                                        or _sha256_file(json_path) != run.get("report_sha256")
                                        or _sha256_file(log_path) != run.get("log_sha256")):
                                    raise ValueError("probe report or log changed after validation")
                            except (OSError, ValueError) as error:
                                run["accepted"] = False
                                run["failures"].append(str(error))
                        reports[mode] = run["report"] if run["accepted"] else None
                        if run["accepted"] and isinstance(run["report"], dict):
                            accepted_report = run["report"]
                            solver_identities[physics_backend].add(accepted_report["solver_sha256"])
                            if physics_backend == "native":
                                native_identities.add(json.dumps(accepted_report["backend"]["actual"], sort_keys=True))
                        runs[mode] = _safe_report_view(run)
                        runs[mode]["report_relative_path"] = json_path.relative_to(output_dir).as_posix()
                        runs[mode]["report_sha256"] = (run.get("report_sha256") if "mac_native_bundle" in metadata or identical
                                                       else _sha256_file(json_path) if json_path.is_file() else None)
                        runs[mode]["log_relative_path"] = log_path.relative_to(output_dir).as_posix()
                        runs[mode]["log_sha256"] = (run.get("log_sha256") if "mac_native_bundle" in metadata or identical
                                                    else _sha256_file(log_path) if log_path.is_file() else None)
                        print(f"{aircraft_id}/{case_id}/{stem}: {'accepted' if run['accepted'] else 'failed'}", flush=True)
                        all_run_count += 1
                        for message in run["failures"]:
                            failures.append(f"{aircraft_id}/{case_id}/repeat-{repeat_index:02d}/{mode}: {message}")
                    reduced = (reduce_identical_pair(reports["a"], reports["b"], args.physics_backend) if identical else
                               reduce_backend_pair(reports["reference"], reports["native"],
                                mac_reference_identity=metadata.get("mac_reference_bundle") if "mac_native_bundle" in metadata else None,
                                mac_native_identity=metadata.get("mac_native_bundle")) if args.compare_backends
                               else reduce_pair(reports["on"], reports["off"]))
                    pair_record = {
                        "aircraft_id": aircraft_id,
                        "case_id": case_id,
                        "repeat": repeat_index,
                        "role_order" if identical else "backend_order" if args.compare_backends else "observer_order": list(order),
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

                metric = ("a_over_b_callback_mean_ratio" if identical else "reference_over_native" if args.compare_backends
                          else "observer_overhead_usec_per_tick")
                values = [pair[metric] for pair in case_pairs if pair["comparable"] and pair[metric] is not None]
                summaries.append({
                    "aircraft_id": aircraft_id,
                    "case_id": case_id,
                    "requested_pairs": args.repeats,
                    "comparable_pairs": len(values),
                    ("a_over_b_callback_mean_ratio_nearest_rank" if identical else "reference_over_native_nearest_rank"
                     if args.compare_backends else "overhead_usec_per_tick_nearest_rank"): {
                        f"p{percentile}": percentile_nearest_rank(values, percentile) if values else None
                        for percentile in (50, 95, 99)
                    },
                })

        final_checks = (
            ("native C++ source", lambda: native_source_digest(root), metadata["native_source_sha256"]),
            ("application code or text data", lambda: app_source_digest(app_dir), metadata["app_source_sha256"]),
            ("probe", lambda: _sha256_file(probe), metadata["probe"]["sha256"]),
            ("Godot executable", lambda: _sha256_file(godot), metadata["engine"]["sha256"]),
        )
        for label, observe, original in final_checks:
            try:
                if observe() != original:
                    failures.append(f"{label} changed during the campaign")
            except (OSError, RuntimeError, ValueError) as error:
                failures.append(f"{label} unavailable after the campaign: {error}")
        if project_validator is not None:
            try:
                final_proof = project_validator.validate_project(app_dir)
                metadata["project"]["inventory_after"] = final_proof
                if (final_proof != project_proof
                        or _sha256_file(root / "research/native-kernel/run.py") != metadata["project"]["validator_sha256"]):
                    failures.append("prepared project or its inventory verifier changed during the campaign")
            except (OSError, ValueError, TypeError) as error:
                failures.append(f"prepared project validation failed after the campaign: {error}")
        if "mac_source_install" in metadata:
            try:
                if mac_source_install_identity(app_dir, metadata["engine"]["sha256"],
                                               metadata["native_source_sha256"]) != metadata["mac_source_install"]:
                    failures.append("Mac native source installation changed during the campaign")
            except (OSError, ValueError, TypeError) as error:
                failures.append(f"Mac native source installation changed during the campaign: {error}")
        if "mac_reference_bundle" in metadata:
            try:
                if "mac_native_bundle" in metadata:
                    valid_bundle = verify_macos_release_identities(godot) == (metadata["mac_reference_bundle"], metadata["mac_native_bundle"])
                else:
                    valid_bundle = MAC_RECEIPT.verify_for_launch(godot) == metadata["mac_reference_bundle"]
                if not valid_bundle:
                    failures.append("Mac release bundle changed during the campaign")
            except (OSError, ValueError, KeyError, TypeError) as error:
                failures.append(f"Mac release bundle changed during the campaign: {error}")
        if "mac_native_bundle" in metadata:
            try:
                source_after = capture_mac_release_source(root)
                metadata["mac_release_source"]["after"] = source_after
                if (source_after != metadata["mac_release_source"]["before"]
                        or not mac_release_source_matches(metadata["mac_reference_bundle"], source_after)):
                    failures.append("current Git/worktree source changed or differs from the Mac release declaration")
            except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
                failures.append(f"Mac release source declaration unavailable after the campaign: {error}")
        if "mac_native_bundle" in metadata or identical:
            for pair in pairs:
                for run in pair["runs"].values():
                    if not run["accepted"]:
                        continue
                    try:
                        raw_path = output_dir / run["report_relative_path"]
                        log_path = output_dir / run["log_relative_path"]
                        if (_sha256_file(raw_path) != run["report_sha256"]
                                or _sha256_file(log_path) != run["log_sha256"]):
                            label = "identical" if identical else "Mac release"
                            failures.append(f"{label} probe report or log changed during the campaign")
                    except (OSError, ValueError, KeyError) as error:
                        label = "identical" if identical else "Mac release"
                        failures.append(f"{label} probe evidence unavailable after the campaign: {error}")
        if any(len(identities) > 1 for identities in solver_identities.values()):
            failures.append("solver source identity changed between runs")
        if len(native_identities) > 1:
            failures.append("installed native backend identity changed between runs")
        complete = not failures and all(len([p for p in pairs if p["aircraft_id"] == a and p["case_id"] == c and p["comparable"]]) == args.repeats
                                       for a in args.aircraft_ids for c in args.case_ids)
        report = {
            "format": report_format,
            "complete": complete,
            "status": "complete" if complete else "failed",
            "failure": "" if complete else "one or more runs failed or paired trajectories were not comparable",
            "configuration": config,
            "metadata": metadata,
            "pairs": pairs,
            "summary": summaries,
            "failures": failures,
        }
        if identical:
            report["scope"] = ("Same-backend observer-on paired measurements; the inclusive callback mean ratio and "
                               "absolute difference describe observed variation, not a speedup or acceptance threshold. "
                               "Timing noise is not subtracted.")
        _write_json(output_dir / report_name, report)
        if complete:
            print(f"session baseline complete: {all_run_count} probes; report {output_dir / report_name}")
            return 0
        print(f"session baseline failed: {len(failures)} issue(s); report {output_dir / report_name}", file=sys.stderr)
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
    battery = config.get("battery")
    if "battery" in config and battery not in ("ideal", "pack"):
        raise ValueError(f"{path}: invalid battery mode")
    experimental = config.get("experimental_native_macos", False)
    if type(experimental) is not bool:
        raise ValueError(f"{path}: malformed experimental Mac opt-in")
    release = config.get("release_executable", False)
    if type(release) is not bool:
        raise ValueError(f"{path}: malformed release mode")
    project = metadata.get("project")
    if project is not None and (not isinstance(project, dict) or not isinstance(project.get("path"), str)
                                or not isinstance(project.get("inventory_before"), dict)
                                or project.get("inventory_after") != project.get("inventory_before")
                                or not isinstance(project.get("validator_sha256"), str)):
        raise ValueError(f"{path}: prepared project evidence is incomplete")
    mac_source = metadata.get("mac_source_install")
    mac_reference, mac_native = metadata.get("mac_reference_bundle"), metadata.get("mac_native_bundle")
    mac_release = experimental and release
    if mac_release:
        error = mac_release_identity_error(mac_reference, mac_native)
        engine, probe = metadata.get("engine"), metadata.get("probe")
        source = metadata.get("mac_release_source")
        if (error or mac_source is not None or project is not None or not isinstance(engine, dict)
                or not isinstance(engine.get("path"), str) or not isinstance(probe, dict)
                or engine.get("sha256") != mac_reference.get("executable_sha256")
                or probe.get("sha256") != mac_reference.get("probe_sha256")
                or not isinstance(source, dict) or source.get("before") != source.get("after")
                or not mac_release_source_matches(mac_reference, source.get("before"))):
            raise ValueError(f"{path}: invalid Mac release receipt or source/editor evidence: {error}")
        if verify_macos_release_identities(Path(engine["path"])) != (mac_reference, mac_native):
            raise ValueError(f"{path}: Mac release bundle differs from retained evidence")
    elif mac_native is not None:
        raise ValueError(f"{path}: native Mac release identity requires release mode and explicit opt-in")
    elif release and mac_reference is not None:
        raise ValueError(f"{path}: reference-only Mac release cannot claim a backend comparison")
    if experimental and not release and not isinstance(mac_source, dict):
        raise ValueError(f"{path}: experimental Mac source identity is missing")
    if (not isinstance(aircraft, list) or not aircraft or not isinstance(cases, list) or not cases
            or not _is_int(repeats) or repeats < 1 or any(not isinstance(item, str) for item in aircraft + cases)):
        raise ValueError(f"{path}: invalid campaign configuration")
    expected_keys = {(air, case, repeat) for air in aircraft for case in cases for repeat in range(1, repeats + 1)}
    runs: dict[tuple[str, str, int], dict[str, Any]] = {}
    native_ids: set[str] = set()
    solver_ids: set[str] = set()
    captured_files: list[tuple[Path, str]] = []
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
            if not raw_path.is_relative_to(path.parent.resolve()) or not raw_path.is_file():
                raise ValueError(f"{path}: missing or changed {mode} raw report")
            if mac_release:
                command = item.get("command")
                requested_backend = "gdscript_reference" if mode == "reference" else "native"
                expected_command = [metadata["engine"]["path"], "--headless", "--audio-driver", "Dummy", "--",
                    "--quick-flight", "--native-qualification=session", f"--output={raw_path}", f"--aircraft={key[0]}",
                    f"--case={key[1]}", f"--warmup-ticks={config.get('warmup_ticks')}",
                    f"--sample-ticks={config.get('sample_ticks')}", "--observer=on",
                    f"--physics-backend={requested_backend}"]
                if battery is not None:
                    expected_command.append(f"--battery={battery}")
                expected_command.append("--experimental-native-macos=true")
                log_relative = item.get("log_relative_path")
                if (command != expected_command or type(item.get("exit_code")) is not int or item["exit_code"] != 0
                        or item.get("timed_out") is not False or item.get("engine_errors") != []
                        or item.get("validation_errors") != [] or item.get("failures") != []
                        or not isinstance(log_relative, str)):
                    raise ValueError(f"{path}: invalid Mac release probe command or process outcome")
                log_path = (path.parent / log_relative).resolve()
                if not log_path.is_relative_to(path.parent.resolve()) or not log_path.is_file():
                    raise ValueError(f"{path}: missing or changed Mac release probe log")
                log_bytes = log_path.read_bytes()
                log_digest = hashlib.sha256(log_bytes).hexdigest()
                if log_digest != item.get("log_sha256"):
                    raise ValueError(f"{path}: missing or changed Mac release probe log")
                captured_files.append((log_path, log_digest))
                log_text = log_bytes.decode("utf-8", errors="replace")
                if "NATIVE_QUALIFICATION mode=session verdict=pass" not in log_text or _engine_error_lines(log_text):
                    raise ValueError(f"{path}: Mac release probe log lacks a clean completion marker")
            report, error, report_digest = read_probe_capture(raw_path)
            if report_digest != item.get("report_sha256"):
                raise ValueError(f"{path}: missing or changed {mode} raw report")
            if error or report is None:
                raise ValueError(f"{raw_path}: {error}")
            if mac_release:
                captured_files.append((raw_path, report_digest))
            raw[mode] = report
        reduced = reduce_backend_pair(raw["reference"], raw["native"],
                                      mac_reference_identity=mac_reference if mac_release else None,
                                      mac_native_identity=mac_native if mac_release else None)
        if not reduced["comparable"]:
            raise ValueError(f"{path}: raw pair is not comparable: {reduced['reasons']}")
        for report in raw.values():
            if (report["aircraft_id"], report["case_id"]) != key[:2] or report["requested"] != {
                "warmup_ticks": config.get("warmup_ticks"), "sample_ticks": config.get("sample_ticks")
            }:
                raise ValueError(f"{path}: raw report differs from campaign configuration")
            if report.get("experimental_native_macos", False) is not experimental:
                raise ValueError(f"{path}: raw report differs from the Mac opt-in")
            report_battery = report.get("battery")
            if ((battery is None and "battery" in report) or (battery is not None
                    and (not isinstance(report_battery, dict) or report_battery.get("mode") != battery))):
                raise ValueError(f"{path}: raw report differs from the requested battery mode")
            if mac_release and report.get("machine", {}).get("godot") != REQUIRED_GODOT_REPORT:
                raise ValueError(f"{path}: raw report does not identify the pinned release engine")
        identity = raw["native"]["backend"]["actual"]
        if identity["source_sha256"] != metadata.get("native_source_sha256"):
            raise ValueError(f"{path}: native binary does not match campaign source")
        if experimental and not release and (any(identity.get(field) != mac_source.get(field) for field in
                                 ("binary_sha256", "source_sha256", "lock_sha256", "backend_version", "abi_version"))
                             or any(report.get("machine", {}).get("os") != "macOS"
                                    or report.get("machine", {}).get("architecture") != "arm64"
                                    for report in raw.values())):
            raise ValueError(f"{path}: raw pair does not match the measured Mac native source identity")
        native_ids.add(json.dumps(identity, sort_keys=True))
        solver_ids.add(raw["reference"]["solver_sha256"])
        runs[key] = {"raw": raw, "reduced": reduced}
    if set(runs) != expected_keys or len(native_ids) != 1 or len(solver_ids) != 1:
        raise ValueError(f"{path}: missing pairs or inconsistent native/solver identity")
    if mac_release and any(_sha256_file(file) != digest for file, digest in captured_files):
        raise ValueError(f"{path}: Mac release probe evidence changed while rereading")
    if mac_release and verify_macos_release_identities(Path(metadata["engine"]["path"])) != (mac_reference, mac_native):
        raise ValueError(f"{path}: Mac release bundle changed while rereading evidence")
    return campaign, runs


def compare_campaigns(before_path: Path, after_path: Path, output_dir: Path) -> int:
    """Compare matching inputs; distinct Mac release bundles have no independent reference identity."""
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
        old_meta, new_meta = before["metadata"], after["metadata"]
        old_mac, new_mac = old_meta.get("mac_native_bundle"), new_meta.get("mac_native_bundle")
        if old_mac is not None or new_mac is not None:
            old_reference, new_reference = old_meta.get("mac_reference_bundle"), new_meta.get("mac_reference_bundle")
            if (not isinstance(old_mac, dict) or not isinstance(new_mac, dict)
                    or not isinstance(old_reference, dict) or not isinstance(new_reference, dict)
                    or old_mac.get("sha256") != new_mac.get("sha256")
                    or old_reference.get("sha256") != new_reference.get("sha256")):
                raise ValueError("Mac native release campaigns cannot compare different bundles; "
                                 "the reference identity includes native bundle artifacts")
        for key in ("aircraft", "cases", "warmup_ticks", "sample_ticks", "repeats", "tick_hz", "pair_type"):
            if before["configuration"].get(key) != after["configuration"].get(key):
                failures.append(f"campaign configuration differs in {key}")
        if before["configuration"].get("experimental_native_macos", False) != after["configuration"].get("experimental_native_macos", False):
            failures.append("campaign configuration differs in experimental_native_macos")
        if before["configuration"].get("battery") != after["configuration"].get("battery"):
            failures.append("campaign configuration differs in battery")
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
                          "world", "machine", "requested", "completed", "final_tick", "input_reads", "battery"):
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
              "scope": "Separate build campaigns, not interleaved across builds; host variation can bias the comparison. "
                       "Distinct Mac native release bundles cannot be compared because the reference identity includes native artifacts. "
                       "Raw callback stopwatch excludes fingerprint and guard work, which can perturb subsequent ticks."}
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
            if args.project is not None or args.experimental_native_macos or args.battery is not None:
                raise ValueError("--project, --experimental-native-macos and --battery apply to a new campaign")
            return compare_campaigns(*args.compare_campaigns, args.out)
        if not args.godot:
            raise ValueError("--godot is required for a campaign")
        if args.release_executable and args.probe:
            raise ValueError("--release-executable uses the fixed embedded probe; --probe is not permitted")
        if args.release_executable and args.project is not None:
            raise ValueError("--project requires a source-editor campaign")
        if args.release_executable and args.experimental_native_macos and (
                not MAC_RECEIPT.looks_like_bundle_executable(Path(args.godot).expanduser().resolve())
                or not (args.compare_backends or args.physics_backend == "native")):
            raise ValueError("experimental native release requires a Mac app bundle and native measurement")
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
