#!/usr/bin/env python3
"""Reduce an explicitly defined turbine thrust step into response metrics.

The reducer is intentionally offline and dependency-free. It computes from the
timestamps, command edge, endpoint thrusts and sample uncertainties supplied by
the caller. It does not infer hardware provenance or claim that input data are
measurements.

Canonical JSON input (one or more trials)::

    {
      "schema": "openrc.av18.response-trace/v1",
      "source": "optional source or capture identifier",
      "dwell_required_s": 0.1,
      "trials": [{
        "id": "idle-to-full",
        "command_edge_time_s": 1.0,
        "command_before": 0.0,
        "command_after": 1.0,
        "f0_n": 2.0,
        "f1_n": 100.0,
        "rated_thrust_n": 100.0,
        "command_edge_uncertainty_s": 0.005,
        "f0_uncertainty_n": 0.2,
        "f1_uncertainty_n": 0.5,
        "rated_thrust_uncertainty_n": 0.5,
        "samples": [
          {"time_s": 0.0, "thrust_n": 2.0,
           "time_uncertainty_s": 0.001, "thrust_uncertainty_n": 0.2},
          {"time_s": 0.5, "thrust_n": 2.0},
          {"time_s": 1.5, "thrust_n": 2.0},
          {"time_s": 2.0, "thrust_n": 20.0}
        ]
      }]
    }

``dwell_required_s`` may also be set per trial. It is a data-quality window,
not an engine parameter. Each normalized F0-to-F1 crossing and each rated
thrust level inside the endpoint interval is linearly interpolated between its
adjacent samples. The reducer reports the first crossing in the response
direction, all subsequent crossings in that direction, time spent on the far
side before a recrossing or capture end, and the sample bracket for each time.
It rejects non-finite data, non-increasing time, a missing command-edge
bracket, insufficient samples, a missing requested crossing, and a capture
that ends before a requested dwell window can be observed.

CSV input is one trial per file. It has ``time_s`` and ``thrust_n`` columns;
optional ``time_uncertainty_s`` and ``thrust_uncertainty_n`` columns are
accepted. Trial metadata is supplied through the CLI, for example::

    uv run --no-project python research/avanti-s/av18/response_metrics.py capture.csv \
      --edge-time-s 1.0 --command-before 0 --command-after 1 \
      --f0-n 2 --f1-n 100 --rated-thrust-n 100 --dwell-required-s 0.1

JSON is the canonical batch input. Output defaults to JSON; ``--output-format
csv`` writes one row per applicable progress or rated-thrust crossing. Crossing
times use linear interpolation. ``sample_support_s`` and ``sample_gap_s`` expose
the time bracket and local sampling interval; they are not statistical
confidence intervals. If complete input standard uncertainties are supplied,
the reducer propagates them to a first-order crossing-time standard uncertainty
under an independent-input assumption. That uncertainty excludes interpolation
model error, aliasing, calibration bias and hardware-to-model differences.

The summary separates command-to-10% latency from the 10%-to-95% transition
duration. Normalized progress is defined from the caller's F0 and F1 endpoints.
Rated-thrust crossings use absolute fractions of the caller's rated thrust, so
they remain distinct from normalized progress thresholds. Up/down is determined
by F1 relative to F0.
"""

from __future__ import annotations

import argparse
import bisect
import csv
import json
import math
import statistics
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, TextIO


INPUT_SCHEMA = "openrc.av18.response-trace/v1"
OUTPUT_SCHEMA = "openrc.av18.response-metrics/v1"
PROGRESS_LEVELS = (10, 50, 90, 95)
RATED_LEVELS = (5, 50, 90, 95)
MIN_PRE_EDGE_SAMPLES = 2
MIN_POST_EDGE_SAMPLES = 4


class InputError(ValueError):
    """Raised when the supplied trace cannot support the requested metrics."""


@dataclass(frozen=True)
class Sample:
    time_s: float
    thrust_n: float
    time_uncertainty_s: float | None = None
    thrust_uncertainty_n: float | None = None


@dataclass(frozen=True)
class Trial:
    trial_id: str
    command_edge_time_s: float
    command_before: float
    command_after: float
    f0_n: float
    f1_n: float
    rated_thrust_n: float
    samples: tuple[Sample, ...]
    dwell_required_s: float = 0.0
    command_edge_uncertainty_s: float | None = None
    f0_uncertainty_n: float | None = None
    f1_uncertainty_n: float | None = None
    rated_thrust_uncertainty_n: float | None = None


def _number(value: Any, name: str) -> float:
    if isinstance(value, bool):
        raise InputError(f"{name} must be a finite number")
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise InputError(f"{name} must be a finite number") from exc
    if not math.isfinite(result):
        raise InputError(f"{name} must be finite")
    return result


def _optional_uncertainty(record: dict[str, Any], key: str, label: str) -> float | None:
    if key not in record or record[key] is None or record[key] == "":
        return None
    value = _number(record[key], label)
    if value < 0:
        raise InputError(f"{label} must be non-negative")
    return value


def _sample_from_mapping(record: Any, index: int) -> Sample:
    if not isinstance(record, dict):
        raise InputError(f"samples[{index}] must be an object")
    if "time_s" not in record or "thrust_n" not in record:
        raise InputError(f"samples[{index}] requires time_s and thrust_n")
    return Sample(
        time_s=_number(record["time_s"], f"samples[{index}].time_s"),
        thrust_n=_number(record["thrust_n"], f"samples[{index}].thrust_n"),
        time_uncertainty_s=_optional_uncertainty(
            record, "time_uncertainty_s", f"samples[{index}].time_uncertainty_s"
        ),
        thrust_uncertainty_n=_optional_uncertainty(
            record, "thrust_uncertainty_n", f"samples[{index}].thrust_uncertainty_n"
        ),
    )


def _trial_from_mapping(record: Any, index: int, defaults: dict[str, Any]) -> Trial:
    if not isinstance(record, dict):
        raise InputError(f"trials[{index}] must be an object")
    required = (
        "command_edge_time_s",
        "command_before",
        "command_after",
        "f0_n",
        "f1_n",
        "samples",
    )
    missing = [key for key in required if key not in record]
    if missing:
        raise InputError(f"trials[{index}] missing required fields: {', '.join(missing)}")
    rated = record.get("rated_thrust_n", defaults.get("rated_thrust_n"))
    if rated is None:
        raise InputError(f"trials[{index}] requires rated_thrust_n or a document default")
    samples_value = record["samples"]
    if not isinstance(samples_value, list):
        raise InputError(f"trials[{index}].samples must be an array")
    samples = tuple(_sample_from_mapping(sample, i) for i, sample in enumerate(samples_value))
    dwell = record.get("dwell_required_s", defaults.get("dwell_required_s", 0.0))
    dwell_value = _number(dwell, f"trials[{index}].dwell_required_s")
    if dwell_value < 0:
        raise InputError(f"trials[{index}].dwell_required_s must be non-negative")
    trial_id = record.get("id", f"trial-{index + 1}")
    if not isinstance(trial_id, str) or not trial_id.strip():
        raise InputError(f"trials[{index}].id must be a non-empty string")
    return Trial(
        trial_id=trial_id,
        command_edge_time_s=_number(record["command_edge_time_s"], "command_edge_time_s"),
        command_before=_number(record["command_before"], "command_before"),
        command_after=_number(record["command_after"], "command_after"),
        f0_n=_number(record["f0_n"], "f0_n"),
        f1_n=_number(record["f1_n"], "f1_n"),
        rated_thrust_n=_number(rated, "rated_thrust_n"),
        samples=samples,
        dwell_required_s=dwell_value,
        command_edge_uncertainty_s=_optional_uncertainty(
            record, "command_edge_uncertainty_s", "command_edge_uncertainty_s"
        ),
        f0_uncertainty_n=_optional_uncertainty(record, "f0_uncertainty_n", "f0_uncertainty_n"),
        f1_uncertainty_n=_optional_uncertainty(record, "f1_uncertainty_n", "f1_uncertainty_n"),
        rated_thrust_uncertainty_n=_optional_uncertainty(
            record, "rated_thrust_uncertainty_n", "rated_thrust_uncertainty_n"
        ),
    )


def _reject_constant(value: str) -> None:
    raise InputError(f"JSON contains non-finite constant {value}")


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InputError(f"JSON contains duplicate key {key!r}")
        result[key] = value
    return result


def load_json_document(stream: TextIO) -> tuple[list[Trial], Any]:
    try:
        document = json.load(
            stream, parse_constant=_reject_constant, object_pairs_hook=_unique_object
        )
    except InputError:
        raise
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise InputError(f"invalid JSON: {exc}") from exc
    if not isinstance(document, dict):
        raise InputError("JSON root must be an object")
    if document.get("schema") != INPUT_SCHEMA:
        raise InputError(f"schema must be {INPUT_SCHEMA!r}")
    records = document.get("trials")
    if not isinstance(records, list) or not records:
        raise InputError("trials must be a non-empty array")
    defaults = {
        "rated_thrust_n": document.get("rated_thrust_n"),
        "dwell_required_s": document.get("dwell_required_s", 0.0),
    }
    trials = [_trial_from_mapping(record, i, defaults) for i, record in enumerate(records)]
    return trials, document.get("source")


def csv_trial(
    stream: TextIO,
    *,
    trial_id: str,
    command_edge_time_s: float,
    command_before: float,
    command_after: float,
    f0_n: float,
    f1_n: float,
    rated_thrust_n: float,
    dwell_required_s: float = 0.0,
    command_edge_uncertainty_s: float | None = None,
    f0_uncertainty_n: float | None = None,
    f1_uncertainty_n: float | None = None,
    rated_thrust_uncertainty_n: float | None = None,
) -> Trial:
    reader = csv.DictReader(stream)
    required = {"time_s", "thrust_n"}
    if reader.fieldnames is None or not required.issubset(reader.fieldnames):
        raise InputError("CSV requires time_s and thrust_n columns")
    samples: list[Sample] = []
    for row_index, row in enumerate(reader, start=2):
        if None in row:
            raise InputError(f"CSV row {row_index} has more values than the header")
        samples.append(
            Sample(
                time_s=_number(row.get("time_s"), f"CSV row {row_index} time_s"),
                thrust_n=_number(row.get("thrust_n"), f"CSV row {row_index} thrust_n"),
                time_uncertainty_s=_optional_uncertainty(
                    row, "time_uncertainty_s", f"CSV row {row_index} time_uncertainty_s"
                ),
                thrust_uncertainty_n=_optional_uncertainty(
                    row, "thrust_uncertainty_n", f"CSV row {row_index} thrust_uncertainty_n"
                ),
            )
        )
    return Trial(
        trial_id=trial_id,
        command_edge_time_s=_number(command_edge_time_s, "command_edge_time_s"),
        command_before=_number(command_before, "command_before"),
        command_after=_number(command_after, "command_after"),
        f0_n=_number(f0_n, "f0_n"),
        f1_n=_number(f1_n, "f1_n"),
        rated_thrust_n=_number(rated_thrust_n, "rated_thrust_n"),
        samples=tuple(samples),
        dwell_required_s=_number(dwell_required_s, "dwell_required_s"),
        command_edge_uncertainty_s=command_edge_uncertainty_s,
        f0_uncertainty_n=f0_uncertainty_n,
        f1_uncertainty_n=f1_uncertainty_n,
        rated_thrust_uncertainty_n=rated_thrust_uncertainty_n,
    )


def _validate_trial(trial: Trial) -> tuple[list[float], list[float], list[float]]:
    if not trial.trial_id.strip():
        raise InputError("trial id must be a non-empty string")
    for name, value in (
        ("command_edge_time_s", trial.command_edge_time_s),
        ("command_before", trial.command_before),
        ("command_after", trial.command_after),
        ("f0_n", trial.f0_n),
        ("f1_n", trial.f1_n),
        ("rated_thrust_n", trial.rated_thrust_n),
        ("dwell_required_s", trial.dwell_required_s),
    ):
        if not math.isfinite(value):
            raise InputError(f"{trial.trial_id}: {name} must be finite")
    for name, value in (
        ("command_edge_uncertainty_s", trial.command_edge_uncertainty_s),
        ("f0_uncertainty_n", trial.f0_uncertainty_n),
        ("f1_uncertainty_n", trial.f1_uncertainty_n),
        ("rated_thrust_uncertainty_n", trial.rated_thrust_uncertainty_n),
    ):
        if value is not None and (not math.isfinite(value) or value < 0):
            raise InputError(f"{trial.trial_id}: {name} must be finite and non-negative")
    if trial.command_before == trial.command_after:
        raise InputError(f"{trial.trial_id}: command edge has no command change")
    if trial.f0_n == trial.f1_n:
        raise InputError(f"{trial.trial_id}: f0_n and f1_n must differ")
    if trial.rated_thrust_n <= 0:
        raise InputError(f"{trial.trial_id}: rated_thrust_n must be positive")
    if trial.dwell_required_s < 0:
        raise InputError(f"{trial.trial_id}: dwell_required_s must be non-negative")
    if trial.command_edge_uncertainty_s is not None and trial.command_edge_uncertainty_s < 0:
        raise InputError(f"{trial.trial_id}: command edge uncertainty must be non-negative")
    if not trial.samples:
        raise InputError(f"{trial.trial_id}: no samples")

    times: list[float] = []
    thrusts: list[float] = []
    gaps: list[float] = []
    for i, sample in enumerate(trial.samples):
        for name, value in (("time_s", sample.time_s), ("thrust_n", sample.thrust_n)):
            if not math.isfinite(value):
                raise InputError(f"{trial.trial_id}: sample {i} {name} must be finite")
        for name, value in (
            ("time_uncertainty_s", sample.time_uncertainty_s),
            ("thrust_uncertainty_n", sample.thrust_uncertainty_n),
        ):
            if value is not None and (not math.isfinite(value) or value < 0):
                raise InputError(f"{trial.trial_id}: sample {i} {name} must be finite and non-negative")
        if times and sample.time_s <= times[-1]:
            raise InputError(f"{trial.trial_id}: sample time must be strictly increasing at index {i}")
        if times:
            gaps.append(sample.time_s - times[-1])
        times.append(sample.time_s)
        thrusts.append(sample.thrust_n)

    edge = trial.command_edge_time_s
    if not math.isfinite(edge) or not times[0] < edge < times[-1]:
        raise InputError(f"{trial.trial_id}: command edge must be inside the sample time span")
    pre_count = sum(time < edge for time in times)
    post_count = sum(time > edge for time in times)
    if pre_count < MIN_PRE_EDGE_SAMPLES or post_count < MIN_POST_EDGE_SAMPLES:
        raise InputError(
            f"{trial.trial_id}: insufficient samples around command edge; need at least "
            f"{MIN_PRE_EDGE_SAMPLES} before and {MIN_POST_EDGE_SAMPLES} after, got "
            f"{pre_count} before and {post_count} after"
        )
    return times, thrusts, gaps


def _interpolate_time(t0: float, y0: float, t1: float, y1: float, level: float) -> tuple[float, float]:
    dy = y1 - y0
    if dy == 0:
        raise InputError("cannot interpolate a crossing across equal thrust samples")
    fraction = (level - y0) / dy
    return t0 + fraction * (t1 - t0), fraction


def _forward_crossings(
    times: list[float], values: list[float], level: float, direction: int
) -> list[dict[str, Any]]:
    hits: list[dict[str, Any]] = []
    for i in range(1, len(times)):
        y0, y1 = values[i - 1], values[i]
        crossed = (y0 < level <= y1) if direction > 0 else (y0 > level >= y1)
        if crossed:
            at, fraction = _interpolate_time(times[i - 1], y0, times[i], y1, level)
            hits.append({"time_s": at, "right_index": i, "fraction": fraction})
    return hits


def _reverse_crossing_time(
    times: list[float], values: list[float], level: float, direction: int, right_index: int
) -> float | None:
    for i in range(right_index + 1, len(times)):
        y0, y1 = values[i - 1], values[i]
        reversed_past_level = (y0 >= level > y1) if direction > 0 else (y0 <= level < y1)
        if reversed_past_level:
            at, _ = _interpolate_time(times[i - 1], y0, times[i], y1, level)
            return at
    return None


def _crossing_uncertainty(
    trial: Trial,
    left: Sample,
    right: Sample,
    level: float,
    fraction: float,
    level_uncertainty: float | None,
) -> float | None:
    required = (
        left.time_uncertainty_s,
        right.time_uncertainty_s,
        left.thrust_uncertainty_n,
        right.thrust_uncertainty_n,
        level_uncertainty,
    )
    if any(value is None for value in required):
        return None
    dt = right.time_s - left.time_s
    dy = right.thrust_n - left.thrust_n
    if dy == 0:
        return None
    # First-order propagation for linear interpolation. Inputs are treated as
    # statistically independent; interpolation-shape error is not included.
    d_t0 = 1.0 - fraction
    d_t1 = fraction
    d_level = dt / dy
    d_y0 = dt * (level - right.thrust_n) / (dy * dy)
    d_y1 = -dt * (level - left.thrust_n) / (dy * dy)
    variance = (
        (d_t0 * left.time_uncertainty_s) ** 2
        + (d_t1 * right.time_uncertainty_s) ** 2
        + (d_level * level_uncertainty) ** 2
        + (d_y0 * left.thrust_uncertainty_n) ** 2
        + (d_y1 * right.thrust_uncertainty_n) ** 2
    )
    return math.sqrt(variance)


def _crossing_result(
    trial: Trial,
    times: list[float],
    thrusts: list[float],
    level: float,
    level_uncertainty: float | None,
    direction: int,
    family: str,
    fraction: float | None,
) -> dict[str, Any]:
    hits = _forward_crossings(times, thrusts, level, direction)
    edge = trial.command_edge_time_s
    pre_edge_hits = [hit for hit in hits if hit["time_s"] < edge]
    if pre_edge_hits:
        raise InputError(
            f"{trial.trial_id}: {family} {level:.6g} N crossing precedes the command edge; "
            "check synchronization and F0/F1"
        )
    hits = [hit for hit in hits if hit["time_s"] >= edge]
    if not hits:
        raise InputError(f"{trial.trial_id}: response does not cross {family} level {level:.6g} N")

    events: list[dict[str, Any]] = []
    for hit in hits:
        right_index = hit["right_index"]
        if right_index >= len(times) - 1:
            raise InputError(
                f"{trial.trial_id}: {family} crossing at {level:.6g} N has no post-crossing sample"
            )
        reverse_time = _reverse_crossing_time(times, thrusts, level, direction, right_index)
        end_of_dwell = reverse_time if reverse_time is not None else times[-1]
        dwell = max(0.0, end_of_dwell - hit["time_s"])
        if reverse_time is None and dwell + 1e-12 < trial.dwell_required_s:
            raise InputError(
                f"{trial.trial_id}: capture ends before the {trial.dwell_required_s:g} s dwell "
                f"window for {family} level {level:.6g} N"
            )
        left = trial.samples[right_index - 1]
        right = trial.samples[right_index]
        crossing_u = _crossing_uncertainty(
            trial, left, right, level, hit["fraction"], level_uncertainty
        )
        elapsed_u = (
            math.hypot(crossing_u, trial.command_edge_uncertainty_s)
            if crossing_u is not None and trial.command_edge_uncertainty_s is not None
            else None
        )
        events.append(
            {
                "crossing_time_s": hit["time_s"],
                "after_command_s": hit["time_s"] - edge,
                "crossing_dwell_s": dwell,
                "dwell_required_s": trial.dwell_required_s,
                "dwell_qualified": dwell + 1e-12 >= trial.dwell_required_s,
                "dwell_censored_at_capture_end": reverse_time is None,
                "sample_indices": [right_index - 1, right_index],
                "sample_support_s": [left.time_s, right.time_s],
                "sample_gap_s": right.time_s - left.time_s,
                "crossing_time_standard_uncertainty_s": crossing_u,
                "after_command_standard_uncertainty_s": elapsed_u,
            }
        )

    first = events[0]
    reverse_count = 0
    for i in range(1, len(times)):
        y0, y1 = thrusts[i - 1], thrusts[i]
        opposite = (y0 >= level > y1) if direction > 0 else (y0 <= level < y1)
        if opposite and times[i] >= edge:
            reverse_count += 1
    result: dict[str, Any] = {
        "applicable": True,
        "level_n": level,
        "level_standard_uncertainty_n": level_uncertainty,
        "crossing_time_s": first["crossing_time_s"],
        "after_command_s": first["after_command_s"],
        "crossing_dwell_s": first["crossing_dwell_s"],
        "dwell_required_s": first["dwell_required_s"],
        "dwell_qualified": first["dwell_qualified"],
        "dwell_censored_at_capture_end": first["dwell_censored_at_capture_end"],
        "directional_crossing_count": len(events),
        "reverse_crossing_count": reverse_count,
        "sample_indices": first["sample_indices"],
        "sample_support_s": first["sample_support_s"],
        "sample_support_width_s": first["sample_gap_s"],
        "interpolation": "linear_between_adjacent_samples",
        "crossing_time_standard_uncertainty_s": first["crossing_time_standard_uncertainty_s"],
        "after_command_standard_uncertainty_s": first["after_command_standard_uncertainty_s"],
        "crossings": events,
    }
    if fraction is not None:
        result["progress_fraction"] = fraction
    return result


def _level_uncertainty_for_progress(trial: Trial, fraction: float) -> float | None:
    if trial.f0_uncertainty_n is None or trial.f1_uncertainty_n is None:
        return None
    return math.hypot((1.0 - fraction) * trial.f0_uncertainty_n, fraction * trial.f1_uncertainty_n)


def _edge_support(times: list[float], edge: float) -> dict[str, Any]:
    index = bisect.bisect_left(times, edge)
    if index < len(times) and times[index] == edge:
        return {"sample_indices": [index], "sample_support_s": [edge], "sample_support_width_s": 0.0}
    return {
        "sample_indices": [index - 1, index],
        "sample_support_s": [times[index - 1], times[index]],
        "sample_support_width_s": times[index] - times[index - 1],
    }


def analyze_trial(trial: Trial) -> dict[str, Any]:
    times, thrusts, gaps = _validate_trial(trial)
    direction = 1 if trial.f1_n > trial.f0_n else -1
    direction_name = "up" if direction > 0 else "down"
    progress: dict[str, Any] = {}
    for percent in PROGRESS_LEVELS:
        fraction = percent / 100.0
        level = trial.f0_n + fraction * (trial.f1_n - trial.f0_n)
        progress[str(percent)] = _crossing_result(
            trial,
            times,
            thrusts,
            level,
            _level_uncertainty_for_progress(trial, fraction),
            direction,
            "normalized progress",
            fraction,
        )

    low, high = sorted((trial.f0_n, trial.f1_n))
    rated: dict[str, Any] = {}
    for percent in RATED_LEVELS:
        level = trial.rated_thrust_n * percent / 100.0
        if not low < level < high:
            rated[str(percent)] = {
                "applicable": False,
                "level_n": level,
                "reason": "rated level is outside the open F0-to-F1 interval",
            }
            continue
        level_u = (
            percent / 100.0 * trial.rated_thrust_uncertainty_n
            if trial.rated_thrust_uncertainty_n is not None
            else None
        )
        rated[str(percent)] = _crossing_result(
            trial,
            times,
            thrusts,
            level,
            level_u,
            direction,
            "rated thrust",
            None,
        )

    progress_10 = progress["10"]["after_command_s"]
    progress_95 = progress["95"]["after_command_s"]
    summary: dict[str, Any] = {
        "response_latency_to_10_progress_s": progress_10,
        "command_to_95_progress_s": progress_95,
        "transition_duration_10_to_95_progress_s": progress_95 - progress_10,
        "final_sample_residual_from_f1_n": thrusts[-1] - trial.f1_n,
    }
    rated_5, rated_95 = rated["5"], rated["95"]
    summary["command_to_5_percent_rated_s"] = (
        rated_5["after_command_s"] if rated_5["applicable"] else None
    )
    summary["command_to_95_percent_rated_s"] = (
        rated_95["after_command_s"] if rated_95["applicable"] else None
    )
    summary["transition_duration_5_to_95_percent_rated_s"] = (
        abs(rated_95["after_command_s"] - rated_5["after_command_s"])
        if rated_5["applicable"] and rated_95["applicable"]
        else None
    )
    summary["rated_5_to_95_order"] = (
        ("5_to_95" if direction > 0 else "95_to_5")
        if rated_5["applicable"] and rated_95["applicable"]
        else None
    )

    return {
        "id": trial.trial_id,
        "direction": direction_name,
        "command": {
            "edge_time_s": trial.command_edge_time_s,
            "edge_uncertainty_s": trial.command_edge_uncertainty_s,
            "before": trial.command_before,
            "after": trial.command_after,
            "delta": trial.command_after - trial.command_before,
            "edge_sample_support": _edge_support(times, trial.command_edge_time_s),
        },
        "endpoints": {
            "f0_n": trial.f0_n,
            "f0_uncertainty_n": trial.f0_uncertainty_n,
            "f1_n": trial.f1_n,
            "f1_uncertainty_n": trial.f1_uncertainty_n,
            "rated_thrust_n": trial.rated_thrust_n,
            "rated_thrust_uncertainty_n": trial.rated_thrust_uncertainty_n,
        },
        "sampling": {
            "sample_count": len(times),
            "time_start_s": times[0],
            "time_end_s": times[-1],
            "samples_before_edge": sum(time < trial.command_edge_time_s for time in times),
            "samples_after_edge": sum(time > trial.command_edge_time_s for time in times),
            "interval_min_s": min(gaps),
            "interval_median_s": statistics.median(gaps),
            "interval_max_s": max(gaps),
        },
        "summary": summary,
        "progress_crossings": progress,
        "rated_thrust_crossings": rated,
    }


def analyze_trials(trials: Iterable[Trial], source: Any = None) -> dict[str, Any]:
    analyzed = [analyze_trial(trial) for trial in trials]
    if not analyzed:
        raise InputError("no trials to analyze")
    ids = [trial["id"] for trial in analyzed]
    if len(ids) != len(set(ids)):
        raise InputError("trial ids must be unique")
    return {
        "schema": OUTPUT_SCHEMA,
        "source": source,
        "method": {
            "interpolation": "linear_between_adjacent_samples",
            "progress_definition": "F0 + fraction * (F1 - F0)",
            "progress_levels_pct": list(PROGRESS_LEVELS),
            "rated_thrust_levels_pct": list(RATED_LEVELS),
            "direction": "sign of F1 - F0",
            "uncertainty_scope": (
                "First-order propagation of supplied standard uncertainties under an independent-input "
                "assumption. Sampling support is reported separately; interpolation-shape error, aliasing, "
                "calibration bias and hardware-to-model differences are excluded."
            ),
        },
        "trials": analyzed,
    }


def _csv_rows(report: dict[str, Any]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for report_trial in report["trials"]:
        for family, crossings in (
            ("progress", report_trial["progress_crossings"]),
            ("rated_thrust", report_trial["rated_thrust_crossings"]),
        ):
            for percent, metric in crossings.items():
                if not metric.get("applicable", False):
                    continue
                rows.append(
                    {
                        "trial_id": report_trial["id"],
                        "direction": report_trial["direction"],
                        "metric_family": family,
                        "threshold_pct": percent,
                        "level_n": metric["level_n"],
                        "crossing_time_s": metric["crossing_time_s"],
                        "after_command_s": metric["after_command_s"],
                        "crossing_dwell_s": metric["crossing_dwell_s"],
                        "dwell_required_s": metric["dwell_required_s"],
                        "dwell_qualified": metric["dwell_qualified"],
                        "dwell_censored_at_capture_end": metric["dwell_censored_at_capture_end"],
                        "directional_crossing_count": metric["directional_crossing_count"],
                        "reverse_crossing_count": metric["reverse_crossing_count"],
                        "sample_index_left": metric["sample_indices"][0],
                        "sample_index_right": metric["sample_indices"][1],
                        "sample_support_start_s": metric["sample_support_s"][0],
                        "sample_support_end_s": metric["sample_support_s"][1],
                        "sample_support_width_s": metric["sample_support_width_s"],
                        "crossing_time_standard_uncertainty_s": metric[
                            "crossing_time_standard_uncertainty_s"
                        ],
                        "after_command_standard_uncertainty_s": metric[
                            "after_command_standard_uncertainty_s"
                        ],
                        "response_latency_to_10_progress_s": report_trial["summary"][
                            "response_latency_to_10_progress_s"
                        ],
                        "transition_duration_10_to_95_progress_s": report_trial["summary"][
                            "transition_duration_10_to_95_progress_s"
                        ],
                    }
                )
    return rows


def write_json(report: dict[str, Any], stream: TextIO) -> None:
    json.dump(report, stream, indent=2, sort_keys=True, allow_nan=False)
    stream.write("\n")


def write_csv(report: dict[str, Any], stream: TextIO) -> None:
    rows = _csv_rows(report)
    if not rows:
        raise InputError("no applicable crossings to write")
    writer = csv.DictWriter(stream, fieldnames=list(rows[0].keys()), lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Compute AV-18 turbine thrust-step response metrics from JSON or CSV samples.",
        epilog=(
            "JSON carries trial metadata and samples. CSV is one trial per file and requires "
            "--edge-time-s, --command-before/after, --f0-n, --f1-n and --rated-thrust-n. "
            "Use --help for the module's input schema and uncertainty conventions."
        ),
    )
    parser.add_argument("input", type=Path, help="input trace file")
    parser.add_argument("--input-format", choices=("auto", "json", "csv"), default="auto")
    parser.add_argument("--output", type=Path, default=Path("-"), help="output file; default is stdout")
    parser.add_argument("--output-format", choices=("json", "csv"), default="json")
    parser.add_argument("--trial-id", default="csv-trial")
    parser.add_argument("--edge-time-s", type=float)
    parser.add_argument("--command-before", type=float)
    parser.add_argument("--command-after", type=float)
    parser.add_argument("--f0-n", type=float)
    parser.add_argument("--f1-n", type=float)
    parser.add_argument("--rated-thrust-n", type=float)
    parser.add_argument("--dwell-required-s", type=float, default=0.0)
    parser.add_argument("--edge-uncertainty-s", type=float)
    parser.add_argument("--f0-uncertainty-n", type=float)
    parser.add_argument("--f1-uncertainty-n", type=float)
    parser.add_argument("--rated-thrust-uncertainty-n", type=float)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    fmt = args.input_format
    if fmt == "auto":
        fmt = args.input.suffix.lower().lstrip(".")
    try:
        with args.input.open("r", encoding="utf-8-sig", newline="") as stream:
            if fmt == "json":
                csv_metadata = (
                    args.edge_time_s,
                    args.command_before,
                    args.command_after,
                    args.f0_n,
                    args.f1_n,
                    args.rated_thrust_n,
                    args.dwell_required_s,
                    args.edge_uncertainty_s,
                    args.f0_uncertainty_n,
                    args.f1_uncertainty_n,
                    args.rated_thrust_uncertainty_n,
                )
                if any(value is not None for value in csv_metadata[0:6]) or any(
                    value != 0.0 and value is not None for value in csv_metadata[6:]
                ):
                    raise InputError("CSV trial metadata flags cannot be used with JSON input")
                trials, source = load_json_document(stream)
            elif fmt == "csv":
                required_flags = {
                    "--edge-time-s": args.edge_time_s,
                    "--command-before": args.command_before,
                    "--command-after": args.command_after,
                    "--f0-n": args.f0_n,
                    "--f1-n": args.f1_n,
                    "--rated-thrust-n": args.rated_thrust_n,
                }
                missing = [name for name, value in required_flags.items() if value is None]
                if missing:
                    raise InputError("CSV input requires " + ", ".join(missing))
                trials = [
                    csv_trial(
                        stream,
                        trial_id=args.trial_id,
                        command_edge_time_s=args.edge_time_s,
                        command_before=args.command_before,
                        command_after=args.command_after,
                        f0_n=args.f0_n,
                        f1_n=args.f1_n,
                        rated_thrust_n=args.rated_thrust_n,
                        dwell_required_s=args.dwell_required_s,
                        command_edge_uncertainty_s=args.edge_uncertainty_s,
                        f0_uncertainty_n=args.f0_uncertainty_n,
                        f1_uncertainty_n=args.f1_uncertainty_n,
                        rated_thrust_uncertainty_n=args.rated_thrust_uncertainty_n,
                    )
                ]
                source = str(args.input)
            else:
                raise InputError("input format must be selected as json or csv")
        report = analyze_trials(trials, source=source)
        output = sys.stdout if str(args.output) == "-" else args.output.open("w", encoding="utf-8", newline="")
        try:
            if args.output_format == "json":
                write_json(report, output)
            else:
                write_csv(report, output)
        finally:
            if output is not sys.stdout:
                output.close()
    except (OSError, InputError, csv.Error) as exc:
        print(f"response_metrics: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
