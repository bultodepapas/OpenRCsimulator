"""Offline export of an ``openrc-debug-frames v1`` snapshot.

This is a deliberately separate format from native ``openrc-frametimes``
reports. It preserves the supplied snapshot, and never invents simulation
clocks, presentation timestamps, CPU slices, or GPU execution intervals.
"""
from __future__ import annotations

import csv
import hashlib
import html
import io
import json
import math
import os
from pathlib import Path
import re
from typing import Any

FORMAT = "openrc-debug-frames v1"
ANALYSIS_FORMAT = "openrc-debug-frame-analysis v1"
DEFAULT_SUSTAINED_FRAMES = 30
MAX_FRAMES = 7200
MAX_EVENTS = 200
MAX_SAFE_INTEGER = (1 << 53) - 1
MAX_JSON_BYTES = 16 * 1024 * 1024
MAX_NODES = 250_000
MAX_TEXT_CHARS = 3_000_000
MAX_STRING_CHARS = 32_768
MAX_DEPTH = 32
FLAG_BITS = {
    "relative_stutter": 1,
    "absolute_stall": 2,
    "legacy_hitch": 4,
    "over_budget": 8,
    "diagnostic_query": 16,
}
EVENT_MASK = 1 | 2 | 4
COLUMNS = ("end_usec", "wall_usec", "process_frame", "physics_ticks", "gpu_ms",
           "baseline_ms", "flags", "observer_usec", "route")


class CaptureError(ValueError):
    """The input is not a complete, bounded debug-frame snapshot."""


def _snapshot(value: Any) -> tuple[dict[str, Any], str]:
    """Copy JSON data and bound arbitrary metadata before building artifacts."""
    if type(value) is not dict:
        raise CaptureError("frame report must be an object")
    pending = [(value, 0)]
    nodes = chars = 0
    while pending:
        item, depth = pending.pop()
        nodes += 1
        if nodes > MAX_NODES or depth > MAX_DEPTH:
            raise CaptureError("report exceeds the JSON node or depth limit")
        kind = type(item)
        if kind is dict:
            if nodes + len(pending) + 2 * len(item) > MAX_NODES:
                raise CaptureError("report exceeds the JSON node limit")
            for key, child in item.items():
                if type(key) is not str:
                    raise CaptureError("JSON object keys must be strings")
                pending.append((key, depth + 1))
                pending.append((child, depth + 1))
        elif kind is list:
            if nodes + len(pending) + len(item) > MAX_NODES:
                raise CaptureError("report exceeds the JSON node limit")
            pending.extend((child, depth + 1) for child in item)
        elif kind is str:
            if len(item) > MAX_STRING_CHARS:
                raise CaptureError("a report string exceeds the length limit")
            chars += len(item)
            if chars > MAX_TEXT_CHARS:
                raise CaptureError("report text exceeds the size limit")
            try:
                item.encode("utf-8")
            except UnicodeError as error:
                raise CaptureError("report text must contain valid Unicode") from error
        elif kind is int:
            if abs(item) > MAX_SAFE_INTEGER:
                raise CaptureError("report integer exceeds the exact JSON integer range")
        elif kind is float:
            if not math.isfinite(item):
                raise CaptureError("report contains a non-finite number")
        elif kind not in (bool, type(None)):
            raise CaptureError("report must contain only JSON values")
    try:
        encoded = json.dumps(value, ensure_ascii=True, allow_nan=False, separators=(",", ":"))
    except (ValueError, TypeError, OverflowError, RecursionError) as error:
        raise CaptureError(f"report cannot be serialized: {error}") from error
    if len(encoded) > MAX_JSON_BYTES:  # ensure_ascii makes characters equal bytes
        raise CaptureError("report exceeds the JSON byte limit")
    return json.loads(encoded), encoded


def _integer(value: Any, label: str, minimum: int = 0, maximum: int = MAX_SAFE_INTEGER) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        raise CaptureError(f"{label} must be an integer in [{minimum}, {maximum}]")
    return value


def _number(value: Any, label: str, minimum: float = 0.0, maximum: float = MAX_SAFE_INTEGER) -> float:
    if type(value) not in (int, float) or not math.isfinite(value) or not minimum <= value <= maximum:
        raise CaptureError(f"{label} must be a finite number in [{minimum}, {maximum}]")
    return float(value)


def _matches(actual: float, expected: float) -> bool:
    return math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9)


def _validate(report: dict[str, Any]) -> None:
    if report.get("format") != FORMAT or type(report.get("version")) is not int or report["version"] != 1:
        raise CaptureError(f"format/version must identify {FORMAT!r}")
    if report.get("clock") != "godot_ticks_usec":
        raise CaptureError("clock must be godot_ticks_usec")
    if report.get("timing_scope") != "bridge_process_wall_intervals_not_presentation":
        raise CaptureError("timing_scope must identify bridge wall callback intervals")
    if type(report.get("capture_id")) is not str or not report["capture_id"]:
        raise CaptureError("capture_id must be a nonempty string")
    epoch = _integer(report.get("epoch"), "epoch", 1)
    n = _integer(report.get("frames"), "frames", 1, MAX_FRAMES)
    first = _integer(report.get("first_sequence"), "first_sequence", 1)
    last = _integer(report.get("last_sequence"), "last_sequence", 1)
    if last != first + n - 1:
        raise CaptureError("first_sequence, last_sequence, and frames must describe consecutive rows")
    total = _integer(report.get("frames_total"), "frames_total", 1)
    retained = _integer(report.get("retained_frames"), "retained_frames", 1, MAX_FRAMES)
    evicted = _integer(report.get("frames_evicted"), "frames_evicted")
    if (last != total or retained != min(total, MAX_FRAMES) or n > retained
            or evicted != max(0, total - MAX_FRAMES)):
        raise CaptureError("frame retention metadata must describe the newest retained ring window")
    if report.get("flag_bits") != FLAG_BITS or any(type(v) is not int for v in report["flag_bits"].values()):
        raise CaptureError("flag_bits does not match the v1 mapping")
    if type(report.get("source")) is not dict:
        raise CaptureError("source must be an object")
    if "display_server" in report["source"] and type(report["source"]["display_server"]) is not str:
        raise CaptureError("source.display_server must be a string")
    target = _number(report.get("target_fps"), "target_fps", 1, 1000)
    budget = _number(report.get("budget_ms"), "budget_ms", 0.000001)
    tolerance = _number(report.get("budget_tolerance_ms"), "budget_tolerance_ms", 0, 1_000_000)
    threshold = _number(report.get("slow_threshold_ms"), "slow_threshold_ms", 0.000001)
    if not _matches(budget, 1000.0 / target) or not _matches(threshold, budget + tolerance):
        raise CaptureError("budget and slow threshold do not match the reported policy")
    # All policy numbers emitted by this version must be present and numeric.
    for key in ("hitch_ms", "factor", "stutter_factor", "stutter_min_extra_ms", "stall_ms"):
        _number(report.get(key), key)

    samples = report.get("samples")
    if type(samples) is not dict:
        raise CaptureError("complete samples are required; request samples=true")
    for key in COLUMNS:
        column = samples.get(key)
        if type(column) is not list or len(column) != n:
            raise CaptureError(f"samples.{key} must contain exactly {n} values")
    previous_end = previous_frame = None
    for i in range(n):
        end = _integer(samples["end_usec"][i], f"samples.end_usec[{i}]", 1)
        wall = _integer(samples["wall_usec"][i], f"samples.wall_usec[{i}]", 1)
        frame = _integer(samples["process_frame"][i], f"samples.process_frame[{i}]")
        _integer(samples["physics_ticks"][i], f"samples.physics_ticks[{i}]")
        _integer(samples["observer_usec"][i], f"samples.observer_usec[{i}]")
        flags = _integer(samples["flags"][i], f"samples.flags[{i}]", 0, 31)
        _number(samples["baseline_ms"][i], f"samples.baseline_ms[{i}]")
        gpu = _number(samples["gpu_ms"][i], f"samples.gpu_ms[{i}]", -1)
        if gpu != -1 and gpu <= 0:
            raise CaptureError(f"samples.gpu_ms[{i}] must be -1 or a positive last-read value")
        if type(samples["route"][i]) is not str:
            raise CaptureError(f"samples.route[{i}] must be a string")
        start = end - wall
        if start <= 0 or (previous_end is not None and start != previous_end):
            raise CaptureError(f"samples[{i}] must form a positive, contiguous wall interval")
        if previous_frame is not None and frame < previous_frame:
            raise CaptureError("process_frame must not decrease within one epoch")
        previous_end, previous_frame = end, frame
    start = samples["end_usec"][0] - samples["wall_usec"][0]
    end = samples["end_usec"][-1]
    if _integer(report.get("sample_start_usec"), "sample_start_usec", 1) != start:
        raise CaptureError("sample_start_usec does not match the first wall interval")
    if _integer(report.get("sample_end_usec"), "sample_end_usec", 1) != end:
        raise CaptureError("sample_end_usec does not match the last wall interval")
    duration = _number(report.get("duration_s"), "duration_s", 0.000001)
    if not math.isclose(duration, (end - start) / 1_000_000, rel_tol=1e-8, abs_tol=1e-6):
        raise CaptureError("duration_s does not match the sample intervals")

    details: dict[int, dict[str, Any]] = {}
    for collection in ("stutters", "hitches"):
        entries = report.get(collection)
        if type(entries) is not list or len(entries) > MAX_EVENTS:
            raise CaptureError(f"{collection} must be an array of at most {MAX_EVENTS} records")
        prior_sequence = 0
        for j, item in enumerate(entries):
            label = f"{collection}[{j}]"
            if type(item) is not dict:
                raise CaptureError(f"{label} must be an object")
            sequence = _integer(item.get("sequence"), f"{label}.sequence", first, last)
            if sequence <= prior_sequence:
                raise CaptureError(f"{collection} must be in sequence order with no duplicates")
            prior_sequence = sequence
            i = sequence - first
            sample_flags = samples["flags"][i]
            if not sample_flags & EVENT_MASK or (collection == "hitches" and not sample_flags & 4):
                raise CaptureError(f"{label} does not point to a matching flagged frame")
            expected = {"epoch": epoch, "frame": samples["process_frame"][i],
                        "start_usec": samples["end_usec"][i] - samples["wall_usec"][i],
                        "end_usec": samples["end_usec"][i], "flags": sample_flags,
                        "physics_ticks": samples["physics_ticks"][i]}
            for key, expected_value in expected.items():
                if _integer(item.get(key), f"{label}.{key}") != expected_value:
                    raise CaptureError(f"{label}.{key} does not match its sample")
            if not _matches(_number(item.get("ms"), f"{label}.ms"), samples["wall_usec"][i] / 1000):
                raise CaptureError(f"{label}.ms does not match its sample")
            if not _matches(_number(item.get("baseline_ms"), f"{label}.baseline_ms"), samples["baseline_ms"][i]):
                raise CaptureError(f"{label}.baseline_ms does not match its sample")
            if "diagnostic_query" in item and (type(item["diagnostic_query"]) is not bool
                                                or item["diagnostic_query"] != bool(sample_flags & 16)):
                raise CaptureError(f"{label}.diagnostic_query disagrees with its flags")
            if sequence in details and details[sequence] != item:
                raise CaptureError(f"duplicate detail for sequence {sequence} conflicts across arrays")
            details[sequence] = item

    flags = samples["flags"]
    counts = {
        "relative_stutter_frames": sum(bool(f & 1) for f in flags),
        "stall_frames": sum(bool(f & 2) for f in flags),
        "hitch_frames": sum(bool(f & 4) for f in flags),
        "over_budget_frames": sum(bool(f & 8) for f in flags),
        "diagnostic_query_frames": sum(bool(f & 16) for f in flags),
        "event_frames": sum(bool(f & EVENT_MASK) for f in flags),
        "event_returned": len(details),
        "hitch_returned": len(report["hitches"]),
        "event_details_omitted_in_window": sum(bool(f & EVENT_MASK) for f in flags) - len(details),
    }
    for key, expected in counts.items():
        if key in report and _integer(report[key], key) != expected:
            raise CaptureError(f"{key} disagrees with the selected samples")


def _detail_map(report: dict[str, Any]) -> dict[int, dict[str, Any]]:
    return {event["sequence"]: event for name in ("hitches", "stutters") for event in report[name]}


def _flag_names(flags: int) -> list[str]:
    return [name for name, bit in FLAG_BITS.items() if flags & bit]


def read_capture(path: Path) -> dict[str, Any]:
    """Read one bounded raw snapshot, refusing ambiguous JSON before validation."""
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise CaptureError("duplicate JSON object key")
            result[key] = value
        return result

    def reject_constant(value):
        raise CaptureError(f"non-finite JSON value: {value}")

    if not Path(path).is_file():
        raise CaptureError("capture input must be a regular JSON file")
    with Path(path).open("rb") as source:
        raw = source.read(MAX_JSON_BYTES + 1)
    if len(raw) > MAX_JSON_BYTES:
        raise CaptureError("capture input exceeds the JSON byte limit")
    try:
        report = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object,
                            parse_constant=reject_constant)
    except (UnicodeError, ValueError, RecursionError) as error:
        raise CaptureError(f"invalid capture JSON: {error}") from error
    copied, _ = _snapshot(report)
    _validate(copied)
    return copied


def _analyze_slowdowns(report: dict[str, Any], sustained_frames: int) -> dict[str, Any]:
    """Reduce validated rows only; an edge episode has an unobserved boundary."""
    s, n = report["samples"], report["frames"]
    first, budget = report["first_sequence"], report["budget_ms"]
    disagreements = [bool(f & 8) != (w / 1000 > report["slow_threshold_ms"])
                     for w, f in zip(s["wall_usec"], s["flags"])]
    episodes = []
    start = None
    for i in range(n + 1):
        if i < n and s["flags"][i] & FLAG_BITS["over_budget"]:
            if start is None:
                start = i
            continue
        if start is None:
            continue
        walls, flags = s["wall_usec"][start:i], s["flags"][start:i]
        count, elapsed = i - start, sum(walls)
        episodes.append({
            "id": len(episodes) + 1, "first_sequence": first + start,
            "last_sequence": first + i - 1, "frames": count,
            "start_usec": s["end_usec"][start] - walls[0], "end_usec": s["end_usec"][i - 1],
            "duration_ms": elapsed / 1000, "fps_mean": count * 1_000_000 / elapsed,
            "worst_ms": max(walls) / 1000,
            "budget_excess_ms": None if any(disagreements[start:i]) else elapsed / 1000 - count * budget,
            "left_censored": start == 0, "right_censored": i == n,
            "observed_sustained": count >= sustained_frames,
            "full_episode_sustained": True if count >= sustained_frames else (None if start == 0 or i == n else False),
            "route_first": s["route"][start], "route_last": s["route"][i - 1],
            "route_changes": sum(s["route"][j] != s["route"][j - 1] for j in range(start + 1, i)),
            "diagnostic_query_frames": sum(bool(f & 16) for f in flags),
            "relative_stutter_frames": sum(bool(f & 1) for f in flags),
            "stall_frames": sum(bool(f & 2) for f in flags),
        })
        start = None
    elapsed = sum(s["wall_usec"])
    slow_us = sum(w for w, f in zip(s["wall_usec"], s["flags"]) if f & 8)
    over = sum(e["frames"] for e in episodes)
    by_frames = max(episodes, key=lambda e: (e["frames"], e["duration_ms"], -e["id"]), default=None)
    by_time = max(episodes, key=lambda e: (e["duration_ms"], e["frames"], -e["id"]), default=None)
    return {
        "format": ANALYSIS_FORMAT, "version": 1,
        "capture_id": report["capture_id"], "epoch": report["epoch"],
        "timing_scope": report["timing_scope"],
        "quality": {"threshold_cross_check_disagreements": sum(disagreements),
                    "screening_status": "uncertain_policy_disagreement" if any(disagreements) else "recorded_flags_consistent",
                    "cross_check": "exact wall_usec / 1000 > reported threshold; diagnostic only; original flags preserved"},
        "policy": {"target_fps": report["target_fps"], "budget_ms": budget,
                   "budget_tolerance_ms": report["budget_tolerance_ms"],
                   "slow_threshold_ms": report["slow_threshold_ms"],
                   "sustained_min_frames": sustained_frames,
                   "episode_method": "maximal consecutive original over_budget flags; all rows retained",
                   "sustained_method": "observed frame count, not a fixed-duration or perceptual threshold"},
        "coverage": {"scope": "selected_window_only", "first_sequence": first,
                     "last_sequence": report["last_sequence"],
                     "sample_start_usec": report["sample_start_usec"], "sample_end_usec": report["sample_end_usec"],
                     "ring_frames_evicted": report["frames_evicted"],
                     "retained_frames_not_selected": report["retained_frames"] - n,
                     "boundary_method": "window-edge episodes have unobserved boundaries, including sequence 1"},
        "summary": {"frames": n, "duration_ms": elapsed / 1000, "fps_mean": n * 1_000_000 / elapsed,
                    "over_budget_frames": over, "over_budget_percent": 100 * over / n,
                    "slow_time_ms": slow_us / 1000, "slow_time_percent": 100 * slow_us / elapsed,
                    "budget_excess_ms": None if any(disagreements) else slow_us / 1000 - over * budget,
                    "episode_count": len(episodes),
                    "sustained_episode_count": sum(e["observed_sustained"] for e in episodes),
                    "longest_by_frames_id": by_frames["id"] if by_frames else None,
                    "longest_by_duration_id": by_time["id"] if by_time else None},
        "episodes": episodes,
    }


def analyze_capture(report: dict[str, Any], *, sustained_frames: int = DEFAULT_SUSTAINED_FRAMES) -> dict[str, Any]:
    """Produce separate offline analysis; never alter the runtime snapshot or flags."""
    _integer(sustained_frames, "sustained_frames", 1, MAX_FRAMES)
    copied, encoded = _snapshot(report)
    _validate(copied)
    analysis = _analyze_slowdowns(copied, sustained_frames)
    analysis["frames_json_sha256"] = hashlib.sha256((encoded + "\n").encode("utf-8")).hexdigest()
    return analysis


def _build_trace(report: dict[str, Any], analysis: dict[str, Any]) -> list[dict[str, Any]]:
    s = report["samples"]
    n = report["frames"]
    first = report["first_sequence"]
    origin = s["end_usec"][0] - s["wall_usec"][0]
    detail_by_sequence = _detail_map(report)
    events: list[dict[str, Any]] = [
        {"pid": 1, "tid": 1, "ph": "M", "name": "process_name",
         "args": {"name": "OpenRC debug frame capture"}},
        {"pid": 1, "tid": 1, "ph": "M", "name": "thread_name",
         "args": {"name": "Bridge wall callback intervals"}},
        {"pid": 1, "tid": 2, "ph": "M", "name": "thread_name",
         "args": {"name": "Frame sampled counters"}},
        {"pid": 1, "tid": 3, "ph": "M", "name": "thread_name",
         "args": {"name": "Detection and diagnostic markers"}},
        {"pid": 1, "tid": 4, "ph": "M", "name": "thread_name",
         "args": {"name": "Observed over-budget episodes (not CPU work)"}},
        {"pid": 1, "tid": 1, "ph": "M", "name": "capture_metadata", "args": {
            "format": FORMAT, "capture_id": report["capture_id"], "epoch": report["epoch"],
            "first_sequence": first, "last_sequence": report["last_sequence"],
            "clock": "local microseconds from first wall interval start; no cross-process correlation",
            "wall_intervals": "bridge callbacks, not presentation, CPU busy time, or GPU completion",
            "gpu": "optional last-read context, freshness unverified; not proof of a GPU bottleneck",
            "event_details": "bounded and possibly missing; flags are per-frame; correlations are not causes",
            "source": report["source"], "flag_bits": dict(FLAG_BITS),
            "analysis_policy": dict(analysis["policy"]), "analysis_quality": dict(analysis["quality"]),
        }},
    ]
    for i in range(n):
        seq, end, wall, flags = first + i, s["end_usec"][i], s["wall_usec"][i], s["flags"][i]
        relative_end = end - origin
        args: dict[str, Any] = {"sequence": seq, "process_frame": s["process_frame"][i],
                                "flags": flags, "flag_names": _flag_names(flags), "route": s["route"][i]}
        if s["gpu_ms"][i] > 0:
            args["gpu_last_read_ms"] = s["gpu_ms"][i]
            args["gpu_freshness"] = "unverified"
        events.append({"pid": 1, "tid": 1, "ts": relative_end - wall, "dur": wall,
                       "ph": "X", "cat": "frame", "name": "frame wall interval", "args": args})
        for name, value in (("frame.wall [ms]", wall / 1000),
                            ("frame.baseline [ms]", s["baseline_ms"][i]),
                            ("frame.physics_ticks [count]", s["physics_ticks"][i]),
                            ("frame.observer [us]", s["observer_usec"][i]),
                            ("frame.flags [bitmask]", flags)):
            events.append({"pid": 1, "tid": 2, "ts": relative_end, "ph": "C",
                           "cat": "frame_metric", "name": name, "args": {"value": value}})
        if flags & EVENT_MASK:
            marker_args: dict[str, Any] = {"sequence": seq, "flags": flags,
                                           "flag_names": _flag_names(flags),
                                           "detail_retained": seq in detail_by_sequence}
            if seq in detail_by_sequence:
                marker_args["detail"] = detail_by_sequence[seq]
            events.append({"pid": 1, "tid": 3, "ts": relative_end, "ph": "I", "s": "t",
                           "cat": "stutter", "name": "flagged stutter frame", "args": marker_args})
        if flags & 16:
            events.append({"pid": 1, "tid": 3, "ts": relative_end, "ph": "I", "s": "t",
                           "cat": "diagnostics", "name": "diagnostic query coincidence",
                           "args": {"sequence": seq, "flags": flags}})
    for episode in analysis["episodes"]:
        events.append({"pid": 1, "tid": 4, "ph": "X", "cat": "budget_episode",
                       "name": ("recorded slow flags (policy uncertain)" if analysis["quality"]["threshold_cross_check_disagreements"]
                                else "sustained slow callbacks" if episode["observed_sustained"] else "over-budget callbacks"),
                       "ts": episode["start_usec"] - origin,
                       "dur": episode["end_usec"] - episode["start_usec"],
                       "args": {**episode, "sustained_min_frames": analysis["policy"]["sustained_min_frames"],
                                "slow_threshold_ms": analysis["policy"]["slow_threshold_ms"],
                                "screening_status": analysis["quality"]["screening_status"]}})
    return events


def build_trace(report: dict[str, Any]) -> list[dict[str, Any]]:
    """Build bounded Perfetto/Chrome trace events on one local clock, in microseconds."""
    copied, _ = _snapshot(report)
    _validate(copied)
    return _build_trace(copied, _analyze_slowdowns(copied, DEFAULT_SUSTAINED_FRAMES))


def _build_csv(report: dict[str, Any]) -> str:
    s = report["samples"]
    origin = s["end_usec"][0] - s["wall_usec"][0]
    stream = io.StringIO(newline="")
    writer = csv.writer(stream, lineterminator="\n")
    writer.writerow(("sequence", "start_usec", "end_usec", "relative_start_usec", "relative_end_usec",
                     "wall_usec", "wall_ms", "process_frame", "physics_ticks", "gpu_ms",
                     "baseline_ms", "flags", "flag_names", "observer_usec", "route_json"))
    for i in range(report["frames"]):
        end, wall, flags = s["end_usec"][i], s["wall_usec"][i], s["flags"][i]
        # JSON quoting makes this text field start with a literal quote even if
        # its value begins with a spreadsheet formula character. Decode as JSON.
        route_json = json.dumps(s["route"][i], ensure_ascii=True)
        writer.writerow((report["first_sequence"] + i, end - wall, end, end - wall - origin,
                         end - origin, wall, wall / 1000, s["process_frame"][i],
                         s["physics_ticks"][i], s["gpu_ms"][i], s["baseline_ms"][i],
                         flags, "|".join(_flag_names(flags)), s["observer_usec"][i], route_json))
    return stream.getvalue()


def _escape(value: Any) -> str:
    return html.escape(str(value), quote=True).replace("\u2028", "&#8232;").replace("\u2029", "&#8233;")


def _fps_text(value: float) -> str:
    return "<0.1" if value < 0.1 else f"{value:.1f}"


def _detail_text(item: dict[str, Any] | None, flagged: bool) -> str:
    if item is None:
        return "Event detail not returned" if flagged else "No event flagged"
    pieces = []
    for key, title in (("causes", "Correlated observations"), ("deltas", "Counter changes"),
                       ("log", "Recent log"), ("route_from", "Route from"), ("route", "Route to")):
        value = item.get(key)
        if value not in (None, "", [], {}):
            if type(value) is str:
                text = value
            else:
                text = json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
            pieces.append(f"{title}: {text[:900]}")
    return " | ".join(pieces) if pieces else "No additional context returned"


def _build_html(report: dict[str, Any], analysis: dict[str, Any]) -> str:
    s = report["samples"]
    n = report["frames"]
    origin = s["end_usec"][0] - s["wall_usec"][0]
    durations = [x / 1000 for x in s["wall_usec"]]
    sorted_ms = sorted(durations)
    duration = (s["end_usec"][-1] - origin) / 1_000_000
    flags = s["flags"]
    details = _detail_map(report)
    event_count = sum(bool(flag & EVENT_MASK) for flag in flags)
    missing = event_count - len(details)
    budget = report["budget_ms"]
    threshold = report["slow_threshold_ms"]
    tail1 = max(1, n // 100)
    tail01 = max(1, n // 1000)
    low1 = 1000 * tail1 / sum(sorted_ms[-tail1:])
    low01 = 1000 * tail01 / sum(sorted_ms[-tail01:])
    source = report["source"]
    display = source.get("display_server", "not reported")
    headless = " Headless runs cannot establish rendering or presentation performance." if display.lower() == "headless" else ""
    cards = [("Average FPS", _fps_text(n / duration)), ("1% low FPS", _fps_text(low1)),
             ("0.1% low FPS", _fps_text(low01)), ("Frames", str(n)), ("Duration", f"{duration:.3f} s"),
             ("Worst interval", f"{max(durations):.2f} ms"),
             ("Flagged events", str(event_count)), ("Over budget", str(sum(bool(f & 8) for f in flags))),
             ("Query-marked", str(sum(bool(f & 16) for f in flags)))]
    card_html = "".join(f'<div class="card"><span>{_escape(label)}</span><strong>{_escape(value)}</strong></div>'
                        for label, value in cards)
    episode_rows = []
    for item in sorted(analysis["episodes"], key=lambda e: (-e["duration_ms"], e["id"]))[:20]:
        boundary = ", ".join(side for side in ("start unobserved" if item["left_censored"] else "",
                                             "end unobserved" if item["right_censored"] else "") if side) or "both observed"
        values = (f"{item['first_sequence']}–{item['last_sequence']}", item["frames"],
                  f"{(item['start_usec'] - origin) / 1_000_000:.3f}–{(item['end_usec'] - origin) / 1_000_000:.3f}",
                  f"{item['duration_ms']:.3f}", _fps_text(item["fps_mean"]),
                  "observed" if item["observed_sustained"] else ("not established" if item["left_censored"] or item["right_censored"] else "no"), boundary,
                  f"{item['route_first']} → {item['route_last']} ({item['route_changes']} changes)",
                  item["diagnostic_query_frames"])
        episode_rows.append("<tr>" + "".join(f"<td>{_escape(value)}</td>" for value in values) + "</tr>")
    if not episode_rows:
        episode_rows.append('<tr><td colspan="9">No over-budget episode observed in this selected window.</td></tr>')
    worst_rows = []
    for i in sorted(range(n), key=lambda index: (-s["wall_usec"][index], index))[:12]:
        sequence = report["first_sequence"] + i
        values = (sequence, f"{(s['end_usec'][i] - origin) / 1_000_000:.3f}",
                  f"{durations[i]:.3f}", ", ".join(_flag_names(flags[i])) or "none", s["route"][i],
                  s["physics_ticks"][i], _detail_text(details.get(sequence), bool(flags[i] & EVENT_MASK)))
        worst_rows.append("<tr>" + "".join(f"<td>{_escape(value)}</td>" for value in values) + "</tr>")
    detail_rows = []
    for sequence in sorted(details, reverse=True)[:20]:
        i = sequence - report["first_sequence"]
        values = (sequence, f"{(s['end_usec'][i] - origin) / 1_000_000:.3f}",
                  ", ".join(_flag_names(flags[i])), _detail_text(details[sequence], True))
        detail_rows.append("<tr>" + "".join(f"<td>{_escape(value)}</td>" for value in values) + "</tr>")
    if not detail_rows:
        detail_rows.append('<tr><td colspan="4">No event details were returned.</td></tr>')
    data = {"wall": durations, "flags": flags,
            "relative_end_s": [(end - origin) / 1_000_000 for end in s["end_usec"]],
            "first": report["first_sequence"], "budget": budget, "threshold": threshold}
    # JSON is parsed from textContent, never evaluated as JavaScript. Escape
    # HTML-significant characters and U+2028/U+2029 even if fields are extended.
    json_data = (json.dumps(data, ensure_ascii=True, allow_nan=False, separators=(",", ":"))
                 .replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
                 .replace("\u2028", "\\u2028").replace("\u2029", "\\u2029"))
    tail1_note = "below 100 frames; short tail" if n < 100 else "available"
    tail01_note = "below 1,000 frames; short tail" if n < 1000 else "available"
    replacements = {
        "@@CAPTURE@@": _escape(report["capture_id"]), "@@EPOCH@@": str(report["epoch"]),
        "@@FIRST@@": str(report["first_sequence"]), "@@LAST@@": str(report["last_sequence"]),
        "@@DISPLAY@@": _escape(display), "@@HEADLESS@@": _escape(headless), "@@CARDS@@": card_html,
        "@@BUDGET@@": f"{budget:.3f}", "@@THRESHOLD@@": f"{threshold:.3f}",
        "@@P95@@": f"{sorted_ms[math.ceil(.95 * n) - 1]:.3f}",
        "@@P50@@": f"{sorted_ms[math.ceil(.5 * n) - 1]:.3f}",
        "@@P99@@": f"{sorted_ms[math.ceil(.99 * n) - 1]:.3f}",
        "@@P999@@": f"{sorted_ms[math.ceil(.999 * n) - 1]:.3f}",
        "@@LOW1@@": _escape(_fps_text(low1)), "@@TAIL1@@": str(tail1), "@@TAIL1NOTE@@": tail1_note,
        "@@LOW01@@": _escape(_fps_text(low01)), "@@TAIL01@@": str(tail01), "@@TAIL01NOTE@@": tail01_note,
        "@@MISSING@@": str(missing), "@@DETAILCOUNT@@": str(len(details)),
        "@@WORST@@": "".join(worst_rows), "@@DETAILROWS@@": "".join(detail_rows), "@@DATA@@": json_data,
        "@@EPISODEROWS@@": "".join(episode_rows),
        "@@EPISODES@@": str(analysis["summary"]["episode_count"]),
        "@@SUSTAINED@@": str(analysis["summary"]["sustained_episode_count"]),
        "@@MINFRAMES@@": str(analysis["policy"]["sustained_min_frames"]),
        "@@SLOWTIME@@": f"{analysis['summary']['slow_time_percent']:.2f}",
        "@@EXCESS@@": (f"{analysis['summary']['budget_excess_ms']:.3f} ms"
                       if analysis['summary']['budget_excess_ms'] is not None else "unavailable (policy disagreement)"),
        "@@DISAGREEMENTS@@": str(analysis["quality"]["threshold_cross_check_disagreements"]),
        "@@EVICTED@@": str(report["frames_evicted"]),
        "@@UNSELECTED@@": str(report["retained_frames"] - n),
    }
    # A single pass avoids interpreting placeholder-looking text in a route,
    # capture ID, or log as a second template substitution.
    return re.sub(r"@@[A-Z0-9]+@@", lambda match: replacements[match.group()], _HTML)


_HTML = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OpenRC debug frames</title><style>
:root{color-scheme:dark;font-family:system-ui,sans-serif;background:#0d1420;color:#e9eef8}
body{max-width:1450px;margin:auto;padding:24px;line-height:1.45} h1{margin-bottom:.1em} h2{margin-top:1.6em}
p,.muted{color:#b8c5d8} code{color:#cee1ff;overflow-wrap:anywhere}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px}
.card{background:#182436;border:1px solid #30425b;border-radius:8px;padding:14px}.card span{display:block;color:#b8c5d8;font-size:.9em}
.card strong{font-size:1.35em}.panel{background:#131e2e;border:1px solid #30425b;border-radius:8px;padding:16px}
canvas{display:block;width:100%;height:360px;background:#0c1725;border-radius:6px}.legend{display:flex;flex-wrap:wrap;gap:8px 18px;font-size:.9em}
.swatch{display:inline-block;width:11px;height:11px;margin-right:5px}.table{overflow-x:auto}table{width:100%;border-collapse:collapse;font-size:.9em}
th,td{text-align:left;vertical-align:top;border-bottom:1px solid #30425b;padding:9px 8px}td{overflow-wrap:anywhere}th{white-space:nowrap;color:#bdd1ea}
label{display:inline-block;padding:8px 0} .note{border-left:3px solid #ffc86b;padding-left:12px}
</style></head><body><h1>Frame timing snapshot</h1>
<p>Capture <code>@@CAPTURE@@</code> · epoch @@EPOCH@@ · sequences @@FIRST@@–@@LAST@@ · display server @@DISPLAY@@.</p>
<p class="note">Local monotonic callback intervals only. They are not presented frames, CPU busy time, GPU completion, or proof of a cause. Positive GPU values are last-read context with unverified freshness, not proof of a GPU bottleneck.@@HEADLESS@@</p>
<div class="grid">@@CARDS@@</div>
<h2>Frame timeline</h2><div class="panel"><p>Horizontal spacing is by frame sequence, with selected relative end times shown in seconds. Each screen column shows the maximum interval in its frame bin; colored rows combine any flags in that bin. No frames are excluded.</p>
<label><input id="logscale" type="checkbox" checked> Logarithmic vertical scale (preserves visibility of smaller intervals)</label>
<canvas id="timeline" width="1200" height="430" role="img" aria-label="Frame wall intervals in milliseconds, budget and flag bands by frame sequence">Frame timeline unavailable. See the tables and frames.csv.</canvas>
<div class="legend"><span><i class="swatch" style="background:#e8a23b"></i>Relative stutter</span><span><i class="swatch" style="background:#fb6572"></i>Absolute stall</span><span><i class="swatch" style="background:#a48bfa"></i>Legacy hitch</span><span><i class="swatch" style="background:#f3d66b"></i>Over budget</span><span><i class="swatch" style="background:#57c6e5"></i>Diagnostic query</span></div>
<p>The dashed white line is the target budget (@@BUDGET@@ ms); the dashed yellow line is the flag threshold (@@THRESHOLD@@ ms, including tolerance). Query marks indicate coincidence only. Relative times are local to this capture and cannot establish cross-process correlation.</p></div>
<h2>Distribution</h2><p>Frame-time percentiles (nearest rank): p50 @@P50@@ ms · p95 @@P95@@ ms · p99 @@P99@@ ms · p99.9 @@P999@@ ms.</p>
<p>The slowest 1% average corresponds to @@LOW1@@ FPS using @@TAIL1@@ frame(s) (@@TAIL1NOTE@@). The slowest 0.1% average corresponds to @@LOW01@@ FPS using @@TAIL01@@ frame(s) (@@TAIL01NOTE@@). Tail counts use max(1, floor(N × fraction)); short tails are descriptive.</p>
<h2>Sustained slowdown and over-budget episodes</h2>
<p>@@EPISODES@@ observed episode(s), including @@SUSTAINED@@ with at least @@MINFRAMES@@ consecutive slow callbacks. This is a frame-count screen, not a fixed duration or a perceptual threshold. Flagged slow callbacks occupy @@SLOWTIME@@% of selected wall time; their excess above the ideal budget totals @@EXCESS@@.</p>
<p>Threshold cross-check disagreements: @@DISAGREEMENTS@@. Original flags are preserved; any disagreement makes policy screening uncertain and the total budget excess unavailable.</p>
<p>Showing up to 20 episodes by observed duration; all are in <code>analysis.json</code>. FPS is callbacks divided by their elapsed time. Boundary labels mean the onset or recovery is unobserved and may lie outside the window; censored lengths are lower bounds. Query-marked rows and route changes remain inside episodes. Routes describe interval-start observations, not exact transition times or causes.</p>
<div class="table"><table><thead><tr><th>Sequences</th><th>Frames</th><th>Relative interval (s)</th><th>Duration (ms)</th><th>Mean callback FPS</th><th>Sustained</th><th>Boundaries</th><th>Route context</th><th>Query frames</th></tr></thead><tbody>@@EPISODEROWS@@</tbody></table></div>
<p>Coverage is this selected window only: @@EVICTED@@ earlier frames were evicted from the ring; @@UNSELECTED@@ retained frames were not selected. No absence claim applies outside this window. This analysis does not identify a CPU or GPU cause.</p>
<h2>Worst observed intervals</h2><p>Exact flags remain available for every frame. Event details are bounded and can be suppressed, evicted, or omitted from a query: @@MISSING@@ flagged frame(s) have no detail in either returned detail list.</p>
<div class="table"><table><thead><tr><th>Sequence</th><th>Relative end (s)</th><th>Wall (ms)</th><th>Flags</th><th>Route</th><th>Physics ticks</th><th>Retained context</th></tr></thead><tbody>@@WORST@@</tbody></table></div>
<h2>Recent returned event details</h2><p>Showing up to 20 of @@DETAILCOUNT@@ distinct returned event details. Any logged observations are correlations and may lag; they do not establish causality.</p>
<div class="table"><table><thead><tr><th>Sequence</th><th>Relative end (s)</th><th>Flags</th><th>Context</th></tr></thead><tbody>@@DETAILROWS@@</tbody></table></div>
<p>CSV timestamps use microseconds; <code>route_json</code> is a JSON-encoded string. GPU value -1 means unavailable; a positive value has unverified freshness. Full data and details are in frames.json.</p>
<script type="application/json" id="capture-data">@@DATA@@</script>
<script>
'use strict';
const data = JSON.parse(document.getElementById('capture-data').textContent);
const canvas = document.getElementById('timeline');
const logbox = document.getElementById('logscale');

// Bound label widths even for unusually long stalls or relative times.
function msLabel(value) {
  if (value >= 10000 || (value > 0 && value < .01)) return value.toExponential(1) + ' ms';
  return value.toFixed(value < 10 ? 2 : (value < 1000 ? 1 : 0)) + ' ms';
}
function secondsLabel(value) {
  return (value >= 10000 ? value.toExponential(1) : value.toFixed(3)) + ' s';
}

function draw() {
  const rect = canvas.getBoundingClientRect();
  const w = rect.width, h = rect.height, n = data.wall.length;
  if (w <= 0 || h <= 0 || n === 0) return;
  const dpr = window.devicePixelRatio || 1;
  const pixelsWide = Math.max(1, Math.round(w * dpr));
  const pixelsHigh = Math.max(1, Math.round(h * dpr));
  if (canvas.width !== pixelsWide) canvas.width = pixelsWide;
  if (canvas.height !== pixelsHigh) canvas.height = pixelsHigh;
  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = '#0c1725'; ctx.fillRect(0, 0, w, h);

  let max = Math.max(data.budget, data.threshold, .001);
  for (const value of data.wall) max = Math.max(max, value);
  const logMax = Math.log10(1 + max);
  const tickValues = Array.from({length: 5}, (_, j) => {
    const fraction = j / 4;
    return logbox.checked ? Math.pow(10, fraction * logMax) - 1 : fraction * max;
  });
  ctx.font = '13px system-ui';
  const tickWidth = Math.max(...tickValues.map(value => ctx.measureText(msLabel(value)).width));
  function tickHalfWidth(i) {
    return Math.max(ctx.measureText('#' + (data.first + i)).width,
                    ctx.measureText(secondsLabel(data.relative_end_s[i])).width) / 2;
  }
  // Make room for the longest tick and the first/last labels, including on phones.
  const left = Math.ceil(Math.max(55, tickWidth + 26, tickHalfWidth(0) + 5));
  const right = Math.ceil(tickHalfWidth(n - 1) + 6);
  const top = 18, plotH = Math.max(1, h - top - 150);
  const firstColumn = Math.ceil(left * dpr);
  const lastColumn = Math.max(firstColumn + 1, Math.floor((w - right) * dpr));
  const plotLeft = firstColumn / dpr;
  const pixelColumns = lastColumn - firstColumn;
  const plotW = pixelColumns / dpr;
  const bins = Array.from({length: Math.min(n, pixelColumns)}, () => ({max: 0, flags: 0}));
  for (let i = 0; i < n; i++) {
    const bin = bins[Math.min(bins.length - 1, Math.floor(i * bins.length / n))];
    bin.max = Math.max(bin.max, data.wall[i]);
    bin.flags |= data.flags[i];
  }
  // Integer physical-pixel boundaries ensure a narrow spike stays visible.
  function binBounds(i) {
    const start = Math.floor(i * pixelColumns / bins.length);
    const end = Math.floor((i + 1) * pixelColumns / bins.length);
    return [plotLeft + start / dpr, (end - start) / dpr];
  }
  const valY = v => top + plotH * (1 - (logbox.checked ? Math.log10(1+v) / logMax : v / max));
  ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
  for (let j = 0; j <= 4; j++) {
    const y = top + plotH * (1 - j / 4);
    ctx.strokeStyle = '#263b51'; ctx.beginPath(); ctx.moveTo(plotLeft, y); ctx.lineTo(plotLeft + plotW, y); ctx.stroke();
    ctx.fillStyle = '#bbcadb'; ctx.fillText(msLabel(tickValues[j]), plotLeft - 8, y);
  }
  ctx.fillStyle = '#65a9d7';
  for (let i = 0; i < bins.length; i++) {
    const [x, width] = binBounds(i), y = valY(bins[i].max);
    ctx.fillRect(x, y, width, top + plotH - y);
  }
  for (const entry of [[data.budget, '#ffffff'], [data.threshold, '#f3d66b']]) {
    ctx.strokeStyle = entry[1]; ctx.setLineDash([7, 5]); ctx.beginPath();
    ctx.moveTo(plotLeft, valY(entry[0])); ctx.lineTo(plotLeft + plotW, valY(entry[0])); ctx.stroke(); ctx.setLineDash([]);
  }
  const colors = ['#e8a23b', '#fb6572', '#a48bfa', '#f3d66b', '#57c6e5'];
  const flagTop = top + plotH + 8, flagStep = 11;
  for (let bit = 0; bit < 5; bit++) {
    ctx.fillStyle = colors[bit];
    for (let i = 0; i < bins.length; i++) {
      if (bins[i].flags & (1 << bit)) {
        const [x, width] = binBounds(i);
        ctx.fillRect(x, flagTop + bit * flagStep, width, 8);
      }
    }
  }
  ctx.fillStyle = '#bbcadb'; ctx.textAlign = 'center';
  const tickX = i => plotLeft + (i + .5) * plotW / n;
  const indexes = n === 1 ? [0] : [0, n - 1];
  const mid = Math.floor((n - 1) / 2);
  // At mobile widths omit the middle label if the labels would collide.
  if (mid > 0 && mid < n - 1 &&
      tickX(mid) - tickHalfWidth(mid) >= tickX(0) + tickHalfWidth(0) + 8 &&
      tickX(mid) + tickHalfWidth(mid) <= tickX(n - 1) - tickHalfWidth(n - 1) - 8) {
    indexes.splice(1, 0, mid);
  }
  for (const i of indexes) {
    ctx.fillText('#' + (data.first + i), tickX(i), flagTop + 5 * flagStep + 13);
    ctx.fillText(secondsLabel(data.relative_end_s[i]), tickX(i), flagTop + 5 * flagStep + 30);
  }
  ctx.fillText('Sequence / relative end (s)', w / 2, h - 12);
  ctx.save(); ctx.translate(10, top + plotH / 2); ctx.rotate(-Math.PI / 2);
  ctx.fillText('Wall interval (ms)', 0, 0); ctx.restore();
}
logbox.addEventListener('change', draw);
window.addEventListener('resize', draw);
draw();
</script></body></html>'''


def write_capture(report: dict[str, Any], out: Path, *, sustained_frames: int = DEFAULT_SUSTAINED_FRAMES) -> dict[str, str]:
    """Write a new standalone capture directory, returning JSON-serializable paths.

    Validation and artifact construction happen before directory creation. An
    existing path is never overwritten. On an I/O failure, remove only files
    that this call created and still have the same filesystem identity.
    """
    _integer(sustained_frames, "sustained_frames", 1, MAX_FRAMES)
    copied, encoded = _snapshot(report)
    _validate(copied)
    analysis = _analyze_slowdowns(copied, sustained_frames)
    analysis["frames_json_sha256"] = hashlib.sha256((encoded + "\n").encode("utf-8")).hexdigest()
    payloads = {
        "json": ("frames.json", encoded + "\n"),
        "analysis": ("analysis.json", json.dumps(analysis, ensure_ascii=True, allow_nan=False,
                                                 separators=(",", ":")) + "\n"),
        "csv": ("frames.csv", _build_csv(copied)),
        "perfetto": ("frames.perfetto.json", json.dumps(_build_trace(copied, analysis), ensure_ascii=True,
                                                        allow_nan=False, separators=(",", ":")) + "\n"),
        "html": ("report.html", _build_html(copied, analysis)),
    }
    destination = Path(out)
    destination.mkdir(mode=0o700, parents=True, exist_ok=False)
    created: list[tuple[Path, tuple[int, int]]] = []
    try:
        for filename, content in payloads.values():
            path = destination / filename
            with path.open("x", encoding="utf-8", newline="") as stream:
                info = os.fstat(stream.fileno())
                created.append((path, (info.st_dev, info.st_ino)))
                stream.write(content)
    except (OSError, ValueError, UnicodeError):
        for path, identity in reversed(created):
            try:
                info = path.lstat()
                if (info.st_dev, info.st_ino) == identity:
                    path.unlink()
            except OSError:
                pass
        try:
            destination.rmdir()
        except OSError:
            pass
        raise
    return {name: str(destination / filename) for name, (filename, _) in payloads.items()}
