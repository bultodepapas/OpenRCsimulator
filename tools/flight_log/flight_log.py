#!/usr/bin/env python3
"""Record, export, summarize, and compare OpenRC flight logs using the stdlib."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Iterator, Sequence


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
GODOT_DEFAULT = ROOT / ".tools" / ("Godot_v4.8-beta1_win64_console.exe" if os.name == "nt" else "Godot_v4.8-beta1_linux.x86_64")
GODOT_SCRIPT = "res://tools/flight_log_cli.gd"

INT64_MIN = -(1 << 63)
INT64_MAX = (1 << 63) - 1

REQUIRED_COLUMNS = (
    "tick",
    "t_s",
    "loads_t_s",
    "north_m",
    "east_m",
    "down_m",
    "u_mps",
    "v_mps",
    "w_mps",
    "qw",
    "qx",
    "qy",
    "qz",
    "p_radps",
    "q_radps",
    "r_radps",
    "Fx_N",
    "Fy_N",
    "Fz_N",
    "Mx_Nm",
    "My_Nm",
    "Mz_Nm",
    "cmd_roll",
    "cmd_pitch",
    "cmd_yaw",
    "cmd_throttle",
    "engine_rpm",
    "srv_roll",
    "srv_pitch",
    "srv_yaw",
    "raw_roll",
    "raw_pitch",
    "raw_yaw",
    "raw_throttle",
    "stick_roll",
    "stick_pitch",
    "stick_yaw",
    "stick_throttle",
    "tas_mps",
    "alpha_rad",
    "beta_rad",
    "wind_north_mps",
    "wind_east_mps",
    "wind_down_mps",
)
OPTIONAL_COLUMNS = frozenset(("cmd_gear_down", "cmd_wheel_brake"))
INDEXED_COLUMN_FAMILIES = {"aux_": 4, "continuous_": 0, "mode_": 0}
INTEGER_COLUMN_PATTERNS = (re.compile(r"mode_[0-9]+\Z"),)
INTEGER_TEXT = re.compile(r"-?[0-9]+\Z")

POSITION_COLUMNS = ("north_m", "east_m", "down_m")
VELOCITY_COLUMNS = ("u_mps", "v_mps", "w_mps")
RATE_COLUMNS = ("p_radps", "q_radps", "r_radps")
QUATERNION_COLUMNS = ("qw", "qx", "qy", "qz")
DEBRIEF_STATE_COLUMNS = ("alpha_rad", "beta_rad", *RATE_COLUMNS)
DEBRIEF_COMMAND_COLUMNS = ("cmd_roll", "cmd_pitch", "cmd_yaw", "cmd_throttle",
    "cmd_flaps", "cmd_gear_down", "cmd_wheel_brake")
DEBRIEF_SERVO_COLUMNS = ("srv_roll", "srv_pitch", "srv_yaw", "srv_flaps")
DEBRIEF_LOAD_COLUMNS = ("Fx_N", "Fy_N", "Fz_N", "Mx_Nm", "My_Nm", "Mz_Nm")


class FlightLogError(Exception):
    """An input, output, or Godot flight-log operation failed."""


class _FilteredCsvLines:
    """Skip optional metadata comments and blank lines while keeping line numbers."""

    def __init__(self, stream: Any):
        self.stream = stream
        self.line_number = 0
        self.metadata: dict[str, str] = {}

    def __iter__(self) -> _FilteredCsvLines:
        return self

    def __next__(self) -> str:
        while True:
            line = self.stream.readline()
            if line == "":
                raise StopIteration
            self.line_number += 1
            stripped = line.strip()
            if not stripped:
                continue
            if line.lstrip().startswith("#"):
                content = line.lstrip()[1:].strip()
                key, separator, value = content.partition(":")
                if separator and key.strip():
                    self.metadata[key.strip().lower()] = value.strip()
                continue
            return line


def _is_int_column(name: str) -> bool:
    return name == "tick" or any(pattern.fullmatch(name) for pattern in INTEGER_COLUMN_PATTERNS)


def _bounded_decimal_index(digits: str, maximum: int) -> int | None:
    """Parse a decimal column index without converting an unbounded integer string."""
    value = 0
    for character in digits:
        digit = int(character)
        if value > maximum // 10 or (value == maximum // 10 and digit > maximum % 10):
            return None
        value = value * 10 + digit
    return value


def _validate_header(header: Sequence[str], path: Path) -> tuple[str, ...]:
    names = tuple(name.strip() for name in header)
    if not names or any(not name for name in names):
        raise FlightLogError(f"{path}: CSV header has an empty column name")
    if len(set(names)) != len(names):
        repeated = sorted({name for name in names if names.count(name) > 1})
        raise FlightLogError(f"{path}: duplicate CSV columns: {', '.join(repeated)}")
    missing = [name for name in REQUIRED_COLUMNS if name not in names]
    if missing:
        raise FlightLogError(f"{path}: missing required columns: {', '.join(missing)}")

    for prefix, first_index in INDEXED_COLUMN_FAMILIES.items():
        indexed_names = [name for name in names if name.startswith(prefix)]
        if not indexed_names:
            continue
        # A valid contiguous family cannot reach farther than its own column
        # count. This bound avoids int()'s untrusted, potentially huge suffix.
        maximum_index = first_index + len(indexed_names) - 1
        indices: list[int] = []
        for name in indexed_names:
            suffix = name[len(prefix) :]
            if not suffix.isdecimal():
                raise FlightLogError(f"{path}: invalid indexed column name {name!r}")
            index = _bounded_decimal_index(suffix, maximum_index)
            if index is None:
                raise FlightLogError(
                    f"{path}: {prefix} columns must be contiguous from {first_index}"
                )
            indices.append(index)
        expected_count = max(indices) - first_index + 1
        if min(indices) != first_index or len(indices) != expected_count:
            raise FlightLogError(
                f"{path}: {prefix} columns must be contiguous from {first_index}"
            )
    return names


class FlightCsvReader:
    """Validate a flight CSV one row at a time, with bounded memory use."""

    def __init__(self, path: Path | str):
        self.path = Path(path).expanduser().resolve()
        try:
            self.stream = self.path.open("r", encoding="utf-8-sig", newline="")
        except OSError as exc:
            raise FlightLogError(f"cannot read CSV {self.path}: {exc}") from exc
        self.lines = _FilteredCsvLines(self.stream)
        self.reader = csv.reader(self.lines, strict=True)
        self.metadata = self.lines.metadata
        self.row_count = 0
        self.first_tick: int | None = None
        self.last_tick: int | None = None
        self.first_time: float | None = None
        self.last_time: float | None = None
        self._finished = False
        try:
            try:
                header = next(self.reader)
            except StopIteration as exc:
                raise FlightLogError(f"{self.path}: CSV has no header") from exc
            except csv.Error as exc:
                raise FlightLogError(f"{self.path}: invalid CSV header: {exc}") from exc
            self.header = _validate_header(header, self.path)
            self.columns = {name: index for index, name in enumerate(self.header)}
            self._previous_tick: int | None = None
            self._previous_time: float | None = None
        except Exception:
            self.stream.close()
            raise

    def __enter__(self) -> FlightCsvReader:
        return self

    def __exit__(self, exc_type: Any, exc_value: Any, traceback: Any) -> None:
        self.close()

    def close(self) -> None:
        if not self.stream.closed:
            self.stream.close()

    def __iter__(self) -> FlightCsvReader:
        return self

    def __next__(self) -> dict[str, int | float]:
        if self._finished:
            raise StopIteration
        try:
            cells = next(self.reader)
        except StopIteration:
            self._finished = True
            if self.row_count == 0:
                raise FlightLogError(f"{self.path}: CSV contains no data rows")
            self._check_metadata_count()
            raise
        except csv.Error as exc:
            raise FlightLogError(
                f"{self.path}: invalid or truncated CSV near line {self.lines.line_number}: {exc}"
            ) from exc

        line_number = self.lines.line_number
        if len(cells) != len(self.header):
            if len(cells) < len(self.header):
                detail = f"row has {len(cells)} fields; expected {len(self.header)} (truncated row)"
            else:
                detail = f"row has {len(cells)} fields; expected {len(self.header)}"
            raise FlightLogError(f"{self.path}:{line_number}: {detail}")

        result: dict[str, int | float] = {}
        for name, raw in zip(self.header, cells):
            value = raw.strip()
            if not value:
                raise FlightLogError(f"{self.path}:{line_number}: empty value in {name}")
            if _is_int_column(name):
                if not INTEGER_TEXT.fullmatch(value):
                    raise FlightLogError(
                        f"{self.path}:{line_number}: {name} must be an int64 decimal"
                    )
                try:
                    parsed: int | float = int(value)
                except ValueError as exc:
                    raise FlightLogError(
                        f"{self.path}:{line_number}: {name} must be an int64 decimal"
                    ) from exc
                if parsed < INT64_MIN or parsed > INT64_MAX:
                    raise FlightLogError(f"{self.path}:{line_number}: {name} is outside int64")
            else:
                try:
                    parsed = float(value)
                except ValueError as exc:
                    raise FlightLogError(
                        f"{self.path}:{line_number}: invalid number in {name}: {value!r}"
                    ) from exc
                if not math.isfinite(parsed):
                    raise FlightLogError(
                        f"{self.path}:{line_number}: nonfinite number in {name}"
                    )
            result[name] = parsed

        tick = int(result["tick"])
        current_time = float(result["t_s"])
        if self._previous_tick is not None:
            if tick == self._previous_tick:
                raise FlightLogError(f"{self.path}:{line_number}: duplicate tick {tick}")
            if tick != self._previous_tick + 1:
                raise FlightLogError(
                    f"{self.path}:{line_number}: tick gap from {self._previous_tick} to {tick}"
                )
            if current_time <= float(self._previous_time):
                raise FlightLogError(
                    f"{self.path}:{line_number}: t_s must increase strictly with tick"
                )
        if all(float(result[name]) == 0.0 for name in QUATERNION_COLUMNS):
            raise FlightLogError(f"{self.path}:{line_number}: quaternion has zero magnitude")

        if self.row_count == 0:
            self.first_tick = tick
            self.first_time = current_time
        self.row_count += 1
        self.last_tick = tick
        self.last_time = current_time
        self._previous_tick = tick
        self._previous_time = current_time
        return result

    def _check_metadata_count(self) -> None:
        for key in ("rows", "samples", "sample_count", "row_count"):
            if key not in self.metadata:
                continue
            try:
                expected = int(self.metadata[key])
            except ValueError as exc:
                raise FlightLogError(
                    f"{self.path}: metadata {key!r} must be an integer"
                ) from exc
            if expected != self.row_count:
                raise FlightLogError(
                    f"{self.path}: truncated CSV: metadata expects {expected} rows, found {self.row_count}"
                )
            break


class _Rms:
    """Stable root-mean-square accumulator that does not retain observations."""

    def __init__(self) -> None:
        self.count = 0
        self.scale = 0.0
        self.sum_scaled_squares = 0.0

    def add(self, value: int | float) -> None:
        magnitude = abs(value)
        self.count += 1
        if magnitude == 0:
            return
        if self.scale < magnitude:
            ratio = self.scale / magnitude if self.scale else 0.0
            self.sum_scaled_squares = 1.0 + self.sum_scaled_squares * ratio * ratio
            self.scale = float(magnitude)
        else:
            ratio = magnitude / self.scale
            self.sum_scaled_squares += ratio * ratio

    def value(self) -> float:
        if not self.count or self.scale == 0.0:
            return 0.0
        ratio = min(1.0, math.sqrt(self.sum_scaled_squares / self.count))
        result = self.scale * ratio
        if not math.isfinite(result):
            raise FlightLogError("RMS calculation overflowed")
        return result


class _ColumnStats:
    def __init__(self) -> None:
        self.minimum: int | float | None = None
        self.maximum: int | float | None = None
        self.rms = _Rms()

    def add(self, value: int | float) -> None:
        if self.minimum is None or value < self.minimum:
            self.minimum = value
        if self.maximum is None or value > self.maximum:
            self.maximum = value
        self.rms.add(value)

    def json(self) -> dict[str, int | float]:
        assert self.minimum is not None and self.maximum is not None
        return {"min": self.minimum, "max": self.maximum, "rms": self.rms.value()}


def summarize_csv(path: Path | str) -> dict[str, Any]:
    source = Path(path).expanduser().resolve()
    with FlightCsvReader(source) as reader:
        stats = {name: _ColumnStats() for name in reader.header}
        for row in reader:
            for name, value in row.items():
                stats[name].add(value)
        assert reader.first_tick is not None and reader.last_tick is not None
        assert reader.first_time is not None and reader.last_time is not None
        duration = reader.last_time - reader.first_time
        if not math.isfinite(duration):
            raise FlightLogError(f"{source}: time span overflows finite seconds")
        down = stats["down_m"]
        rates = {name: stats[name] for name in RATE_COLUMNS}
        angular_rate_peak = max(
            max(abs(float(rates[name].minimum)), abs(float(rates[name].maximum)))
            for name in RATE_COLUMNS
        )
        altitude_rms = _Rms()
        # The RMS of altitude requires signed per-row values, so make a second
        # streaming pass rather than keeping the trajectory in memory.
        with FlightCsvReader(source) as altitude_reader:
            for row in altitude_reader:
                altitude_rms.add(-float(row["down_m"]))
        return {
            "status": "ok",
            "source": source.name,
            "rows": reader.row_count,
            "tick": {"first": reader.first_tick, "last": reader.last_tick},
            "time_s": {
                "first": reader.first_time,
                "last": reader.last_time,
                "duration": duration,
            },
            "altitude_m": {
                "min": -float(down.maximum),
                "max": -float(down.minimum),
                "rms": altitude_rms.value(),
            },
            "angular_rates_radps": {
                "max_abs": angular_rate_peak,
                "axes": {
                    name: {
                        "min": rates[name].minimum,
                        "max": rates[name].maximum,
                        "max_abs": max(
                            abs(float(rates[name].minimum)), abs(float(rates[name].maximum))
                        ),
                    }
                    for name in RATE_COLUMNS
                },
            },
            "columns": {name: value.json() for name, value in stats.items()},
        }


class _Range:
    """Minimum and maximum only; debriefs describe samples without scoring them."""

    def __init__(self) -> None:
        self.minimum: float | None = None
        self.maximum: float | None = None

    def add(self, value: int | float) -> None:
        value = float(value)
        if not math.isfinite(value):
            raise FlightLogError("debrief metric is nonfinite")
        self.minimum = value if self.minimum is None else min(self.minimum, value)
        self.maximum = value if self.maximum is None else max(self.maximum, value)

    def json(self) -> dict[str, float]:
        if self.minimum is None or self.maximum is None:
            return {}
        return {"min": self.minimum, "max": self.maximum}


class _DebriefWindow:
    """Bounded per-window accumulators for endpoint and interval-timed columns."""

    def __init__(self, start_tick: int, end_tick: int, kind: str,
            start_boundary: dict[str, Any], end_boundary: dict[str, Any]) -> None:
        self.start_tick = start_tick
        self.end_tick = end_tick
        self.kind = kind
        self.start_boundary = start_boundary
        self.end_boundary = end_boundary
        self.endpoint_samples = 0
        self.interval_samples = 0
        self.state_ranges = {name: _Range() for name in ("altitude_m", "tas_mps", *DEBRIEF_STATE_COLUMNS)}
        self.interval_ranges: dict[str, dict[str, _Range]] = {
            "commands": {}, "servos": {}, "loads": {}}
        self._state_first: dict[str, float] = {}
        self._state_last: dict[str, float] = {}
        self._first_interval_tick: int | None = None
        self._last_interval_tick: int | None = None
        self._first_load_time_s: float | None = None
        self._last_load_time_s: float | None = None

    def add_state(self, row: dict[str, int | float]) -> None:
        values = {"altitude_m": -float(row["down_m"]), "tas_mps": float(row["tas_mps"])}
        values.update({name: float(row[name]) for name in DEBRIEF_STATE_COLUMNS})
        for name, value in values.items():
            self.state_ranges[name].add(value)
        if self.endpoint_samples == 0:
            self._state_first = values
        self._state_last = values
        self.endpoint_samples += 1

    def add_interval(self, row: dict[str, int | float], columns: dict[str, tuple[str, ...]]) -> None:
        tick = int(row["tick"])
        self._first_interval_tick = tick if self._first_interval_tick is None else self._first_interval_tick
        self._last_interval_tick = tick
        for group, names in columns.items():
            for name in names:
                self.interval_ranges[group].setdefault(name, _Range()).add(row[name])
        self._first_load_time_s = float(row["loads_t_s"]) if self._first_load_time_s is None else self._first_load_time_s
        self._last_load_time_s = float(row["loads_t_s"])
        self.interval_samples += 1

    def json(self, dt_s: float) -> dict[str, Any]:
        if self.endpoint_samples == 0:
            raise FlightLogError("debrief window contains no endpoint samples")
        if self.endpoint_samples != self.end_tick - self.start_tick + 1:
            raise FlightLogError("debrief endpoint sample count does not match window ticks")
        if self.interval_samples != self.end_tick - self.start_tick:
            raise FlightLogError("debrief interval sample count does not match window ticks")
        state: dict[str, Any] = {name: stats.json() for name, stats in self.state_ranges.items()}
        for name in state:
            start = self._state_first[name]
            end = self._state_last[name]
            delta = end - start
            if not math.isfinite(delta):
                raise FlightLogError("debrief state delta is nonfinite")
            state[name].update({"start": start, "end": end, "delta": delta})
        intervals = {
            group: {name: stats.json() for name, stats in values.items()}
            for group, values in self.interval_ranges.items()
        }
        return {
            "kind": self.kind,
            "start_tick": self.start_tick,
            "end_tick": self.end_tick,
            "duration_s": (self.end_tick - self.start_tick) * dt_s,
            "start_boundary": self.start_boundary,
            "end_boundary": self.end_boundary,
            "endpoint_samples": self.endpoint_samples,
            "interval_samples": self.interval_samples,
            "state_endpoints": state,
            "interval_channels": intervals,
            "command_and_load_tick_range": (
                [self._first_interval_tick, self._last_interval_tick]
                if self._first_interval_tick is not None else None),
            "loads_t_s_range": (
                [self._first_load_time_s, self._last_load_time_s]
                if self._first_load_time_s is not None else None),
        }


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as exc:
        raise FlightLogError(f"cannot hash {path}: {exc}") from exc
    return digest.hexdigest()


def _validate_exact_replay_report(report: dict[str, Any], log_path: Path) -> tuple[int, int, float, list[dict[str, Any]]]:
    """Require the exact, complete replay contract before describing any segment."""
    if report.get("format") != "openrc-flight-log-report v1" or report.get("status") != "ok" or report.get("error") != "":
        raise FlightLogError("debrief requires a valid flight-log replay report")
    if report.get("mode") != "exact" or report.get("complete") is not True:
        raise FlightLogError("debrief requires a complete exact replay")
    if report.get("solver_changed") is not False:
        raise FlightLogError("debrief requires solver_changed=false")
    if report.get("source") != str(log_path):
        raise FlightLogError("replay report source path does not match the requested log")
    for key in ("source_sha256", "baseline_solver_sha256", "current_solver_sha256"):
        value = report.get(key)
        if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", value):
            raise FlightLogError(f"exact replay report must include a SHA-256 {key}")
    if report["baseline_solver_sha256"].lower() != report["current_solver_sha256"].lower():
        raise FlightLogError("exact replay solver identities differ")
    if report["source_sha256"].lower() != _sha256_file(log_path):
        raise FlightLogError("flight log changed during replay")
    for key in ("first_tick", "final_tick", "rows"):
        if type(report.get(key)) is not int:
            raise FlightLogError(f"exact replay report must include integer {key}")
    first_tick = int(report["first_tick"])
    final_tick = int(report["final_tick"])
    rows = int(report["rows"])
    if first_tick < 0 or final_tick < first_tick or rows != final_tick - first_tick + 1:
        raise FlightLogError("exact replay report has inconsistent tick bounds or row count")
    dt_value = report.get("dt_s")
    if type(dt_value) not in (int, float) or not math.isfinite(float(dt_value)) or float(dt_value) <= 0.0:
        raise FlightLogError("exact replay report must include a positive finite dt_s")
    if not isinstance(report.get("metadata"), dict):
        raise FlightLogError("exact replay report must include metadata")
    if type(report.get("events_omitted")) is not int or report["events_omitted"] != 0:
        raise FlightLogError("debrief refuses missing or truncated marker events")
    events = report.get("events")
    if not isinstance(events, list) or len(events) > 10000:
        raise FlightLogError("exact replay report has an invalid or oversized events list")
    return first_tick, final_tick, float(dt_value), events


def _marker_groups(events: list[dict[str, Any]], first_tick: int, final_tick: int) -> list[dict[str, Any]]:
    groups: list[dict[str, Any]] = []
    last_tick = first_tick
    for event in events:
        if not isinstance(event, dict):
            raise FlightLogError("exact replay report contains a malformed event")
        if event.get("kind") != "marker":
            continue
        tick = event.get("tick")
        label = event.get("detail")
        if type(tick) is not int or not isinstance(label, str):
            raise FlightLogError("exact replay report contains an invalid marker")
        if tick < first_tick or tick > final_tick:
            raise FlightLogError("marker tick falls outside the replayed CSV range")
        if groups and tick < last_tick:
            raise FlightLogError("marker ticks are out of order")
        if groups and tick == last_tick:
            groups[-1]["labels"].append(label)
        else:
            groups.append({"tick": tick, "labels": [label]})
        last_tick = tick
    return groups


def _debrief_windows(first_tick: int, final_tick: int, markers: list[dict[str, Any]]) -> list[_DebriefWindow]:
    start_edge = {"kind": "recording_start", "tick": first_tick}
    end_edge = {"kind": "recording_end", "tick": final_tick}
    if not markers:
        return [_DebriefWindow(first_tick, final_tick, "unmarked_flight", start_edge, end_edge)]
    boundaries = [start_edge, *({"kind": "marker", **marker} for marker in markers), end_edge]
    windows: list[_DebriefWindow] = []
    for start, end in zip(boundaries, boundaries[1:]):
        left = int(start["tick"])
        right = int(end["tick"])
        if right < left:
            raise FlightLogError("marker windows are out of order")
        if start["kind"] == "recording_start" and end["kind"] == "marker":
            kind = "unmarked_prefix"
        elif start["kind"] == "marker" and end["kind"] == "recording_end":
            kind = "marker_tail"
        elif start["kind"] == "marker" and end["kind"] == "marker":
            kind = "between_markers"
        else:
            kind = "unmarked_flight"
        windows.append(_DebriefWindow(left, right, kind, start, end))
    return windows


def _build_debrief(csv_path: Path | str, log_path: Path | str, report_path: Path | str,
        replay_report: dict[str, Any], summary: dict[str, Any]) -> dict[str, Any]:
    """Internal reducer; the CLI supplies only this command's verified exact-replay artifacts."""
    csv_file = Path(csv_path).resolve()
    log_file = Path(log_path).resolve()
    report_file = Path(report_path).resolve()
    first_tick, final_tick, dt_s, events = _validate_exact_replay_report(replay_report, log_file)
    if summary["rows"] != replay_report["rows"] or summary["tick"] != {"first": first_tick, "last": final_tick}:
        raise FlightLogError("replay report row/tick bounds do not match the replayed CSV")
    if not math.isclose(float(summary["time_s"]["first"]), first_tick * dt_s, rel_tol=1e-12, abs_tol=1e-9) \
            or not math.isclose(float(summary["time_s"]["last"]), final_tick * dt_s, rel_tol=1e-12, abs_tol=1e-9):
        raise FlightLogError("replay CSV timestamps do not match report dt_s/tick bounds")
    markers = _marker_groups(events, first_tick, final_tick)
    windows = _debrief_windows(first_tick, final_tick, markers)
    with FlightCsvReader(csv_file) as reader:
        available = set(reader.header)
        columns = {
            "commands": tuple(name for name in DEBRIEF_COMMAND_COLUMNS if name in available),
            "servos": tuple(name for name in DEBRIEF_SERVO_COLUMNS if name in available),
            "loads": tuple(name for name in DEBRIEF_LOAD_COLUMNS if name in available),
        }
        window_index = 0
        for row in reader:
            tick = int(row["tick"])
            if not math.isclose(float(row["t_s"]), tick * dt_s, rel_tol=1e-12, abs_tol=1e-9):
                raise FlightLogError(f"replay CSV time does not match report dt_s at tick {tick}")
            expected_load_time = max(0, tick - 1) * dt_s
            if not math.isclose(float(row["loads_t_s"]), expected_load_time, rel_tol=1e-12, abs_tol=1e-9):
                raise FlightLogError(f"replay CSV load time does not match report dt_s at tick {tick}")
            while window_index < len(windows) - 1 and tick > windows[window_index].end_tick:
                window_index += 1
            for index in range(max(0, window_index - 1), min(len(windows), window_index + 2)):
                window = windows[index]
                if window.start_tick <= tick <= window.end_tick:
                    window.add_state(row)
                if window.start_tick < tick <= window.end_tick:
                    window.add_interval(row, columns)
        if reader.row_count != replay_report["rows"]:
            raise FlightLogError("replayed CSV row count changed during debrief")
    return {
        "format": "openrc-flight-debrief v1",
        "status": "ok",
        "interpretation": "Descriptive replay data only; no pilot grade, physical validation, or causal diagnosis.",
        "window_semantics": {
            "state_endpoints": "inclusive [start_tick, end_tick]; marker endpoint rows are shared by adjacent windows",
            "commands_and_loads": "interval rows with start_tick < tick <= end_tick; command k drove k-1 to k; see loads_t_s for load time",
        },
        "input_artifacts": {
            "source_log": {"path": str(log_file), "sha256": replay_report["source_sha256"]},
            "replayed_csv": {"path": csv_file.name, "sha256": _sha256_file(csv_file)},
            "replay_report": {"path": report_file.name, "sha256": _sha256_file(report_file)},
        },
        "replay_report": replay_report,
        "flight": {
            "first_tick": first_tick, "final_tick": final_tick, "rows": summary["rows"], "dt_s": dt_s,
            "duration_s": summary["time_s"]["duration"], "marker_groups": markers,
            "windows": [window.json(dt_s) for window in windows],
        },
    }


class _DifferenceStats:
    def __init__(self, component_names: Sequence[str]) -> None:
        self.component_names = tuple(component_names)
        self.components = {name: _Rms() for name in self.component_names}
        self.all = _Rms()
        self.max_abs = 0.0
        self.peaks = {name: 0.0 for name in self.component_names}
        self.max_component: str | None = None
        self.max_tick: int | None = None
        self.max_time: float | None = None

    def add(self, values: Sequence[float], tick: int, time_s: float) -> None:
        for name, value in zip(self.component_names, values):
            if not math.isfinite(value):
                raise FlightLogError(f"difference overflow in {name} at tick {tick}")
            self.components[name].add(value)
            self.all.add(value)
            magnitude = abs(value)
            self.peaks[name] = max(self.peaks[name], magnitude)
            if magnitude > self.max_abs:
                self.max_abs = magnitude
                self.max_component = name
                self.max_tick = tick
                self.max_time = time_s

    def json(self, unit: str) -> dict[str, Any]:
        result: dict[str, Any] = {
            "rmse": self.all.value(),
            "max_abs": self.max_abs,
            "components": {
                name: {
                    "rmse": accumulator.value(),
                    "max_abs": self._component_max(name),
                }
                for name, accumulator in self.components.items()
            },
        }
        result["unit"] = unit
        if self.max_component is not None:
            result["max_at"] = {
                "component": self.max_component,
                "tick": self.max_tick,
                "t_s": self.max_time,
            }
        return result

    def _component_max(self, name: str) -> float:
        return self.peaks[name]


def _unit_quaternion(row: dict[str, int | float]) -> tuple[float, float, float, float]:
    values = tuple(float(row[name]) for name in QUATERNION_COLUMNS)
    scale = max(abs(value) for value in values)
    if scale == 0.0:
        raise FlightLogError("quaternion has zero magnitude")
    scaled = tuple(value / scale for value in values)
    norm = math.sqrt(sum(value * value for value in scaled))
    return tuple(value / norm for value in scaled)  # type: ignore[return-value]


def _quaternion_angle(left: dict[str, int | float], right: dict[str, int | float]) -> float:
    left_values = tuple(float(left[name]) for name in QUATERNION_COLUMNS)
    right_values = tuple(float(right[name]) for name in QUATERNION_COLUMNS)
    if left_values == right_values or left_values == tuple(-value for value in right_values):
        return 0.0
    left_q = _unit_quaternion(left)
    right_q = _unit_quaternion(right)
    # The relative quaternion is equivalent to 2*acos(abs(dot(q0, q1))) but
    # atan2 of its vector/scalar parts retains precision near zero angle.
    w, x, y, z = left_q
    other_w, other_x, other_y, other_z = right_q
    relative_w = w * other_w + x * other_x + y * other_y + z * other_z
    relative_x = w * other_x - x * other_w - y * other_z + z * other_y
    relative_y = w * other_y + x * other_z - y * other_w - z * other_x
    relative_z = w * other_z - x * other_y + y * other_x - z * other_w
    vector_size = math.hypot(relative_x, relative_y, relative_z)
    return 2.0 * math.atan2(vector_size, abs(relative_w))


def compare_csv(base_path: Path | str, candidate_path: Path | str) -> dict[str, Any]:
    base_source = Path(base_path).expanduser().resolve()
    candidate_source = Path(candidate_path).expanduser().resolve()
    groups = (
        ("position_m", POSITION_COLUMNS, "m"),
        ("velocity_mps", VELOCITY_COLUMNS, "m/s"),
        ("angular_rate_radps", RATE_COLUMNS, "rad/s"),
    )
    with FlightCsvReader(base_source) as base, FlightCsvReader(candidate_source) as candidate:
        base_commands = {name for name in base.header if name.startswith("cmd_")}
        candidate_commands = {name for name in candidate.header if name.startswith("cmd_")}
        if base_commands != candidate_commands:
            missing = sorted(base_commands - candidate_commands)
            extra = sorted(candidate_commands - base_commands)
            raise FlightLogError(
                "command columns differ between logs"
                + (f"; missing from candidate: {', '.join(missing)}" if missing else "")
                + (f"; extra in candidate: {', '.join(extra)}" if extra else "")
            )

        group_stats = {
            name: _DifferenceStats(columns) for name, columns, _unit in groups
        }
        quaternion_rms = _Rms()
        quaternion_max = 0.0
        quaternion_max_tick: int | None = None
        quaternion_max_time: float | None = None
        first_divergence: dict[str, Any] | None = None
        rows = 0

        base_iter = iter(base)
        candidate_iter = iter(candidate)
        sentinel = object()
        while True:
            try:
                base_row: Any = next(base_iter)
            except StopIteration:
                base_row = sentinel
            try:
                candidate_row: Any = next(candidate_iter)
            except StopIteration:
                candidate_row = sentinel
            if base_row is sentinel or candidate_row is sentinel:
                if base_row is not sentinel or candidate_row is not sentinel:
                    raise FlightLogError("flight logs have different row counts")
                break

            tick = int(base_row["tick"])
            time_s = float(base_row["t_s"])
            if tick != int(candidate_row["tick"]) or time_s != float(candidate_row["t_s"]):
                raise FlightLogError(
                    f"logs are not aligned at row {rows + 1}: "
                    f"base tick/time {tick}/{time_s}, candidate "
                    f"{candidate_row['tick']}/{candidate_row['t_s']}"
                )
            for command in sorted(base_commands):
                if base_row[command] != candidate_row[command]:
                    raise FlightLogError(
                        f"command input {command} differs at tick {tick}: "
                        f"{base_row[command]} versus {candidate_row[command]}"
                    )

            changed_groups: list[str] = []
            for name, columns, _unit in groups:
                differences = [float(candidate_row[column]) - float(base_row[column]) for column in columns]
                group_stats[name].add(differences, tick, time_s)
                if any(value != 0.0 for value in differences):
                    changed_groups.append(name)

            angle = _quaternion_angle(base_row, candidate_row)
            quaternion_rms.add(angle)
            if angle > quaternion_max:
                quaternion_max = angle
                quaternion_max_tick = tick
                quaternion_max_time = time_s
            if angle > 0.0:
                changed_groups.append("quaternion_angle_rad")
            if first_divergence is None and changed_groups:
                first_divergence = {
                    "tick": tick,
                    "t_s": time_s,
                    "metrics": changed_groups,
                }
            rows += 1

        assert base.first_time is not None and base.last_time is not None
        assert base.first_tick is not None and base.last_tick is not None
        duration = base.last_time - base.first_time
        if not math.isfinite(duration):
            raise FlightLogError(f"{base_source}: time span overflows finite seconds")
        return {
            "status": "ok",
            "base": base_source.name,
            "candidate": candidate_source.name,
            "rows": rows,
            "tick": {"first": base.first_tick, "last": base.last_tick},
            "time_s": {
                "first": base.first_time,
                "last": base.last_time,
                "duration": duration,
            },
            "first_divergence": first_divergence,
            "differences": {
                name: group_stats[name].json(unit)
                for name, _columns, unit in groups
            }
            | {
                "quaternion_angle_rad": {
                    "rmse": quaternion_rms.value(),
                    "max_abs": quaternion_max,
                    "unit": "rad",
                    **(
                        {
                            "max_at": {
                                "tick": quaternion_max_tick,
                                "t_s": quaternion_max_time,
                            }
                        }
                        if quaternion_max_tick is not None
                        else {}
                    ),
                }
            },
        }


def _write_json_fresh(path: Path | str, document: dict[str, Any]) -> Path:
    target = Path(path).expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        with target.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(document, stream, indent=2, sort_keys=True, allow_nan=False)
            stream.write("\n")
    except FileExistsError as exc:
        raise FlightLogError(f"output already exists: {target}") from exc
    except OSError as exc:
        raise FlightLogError(f"cannot write {target}: {exc}") from exc
    return target


def _fresh_record_path(value: str | None) -> Path:
    if value:
        target = Path(value).expanduser().resolve()
        if target.suffix.lower() != ".orfl":
            raise FlightLogError("record output must use the .orfl extension")
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            raise FlightLogError(f"output already exists: {target}")
        return target

    timestamp = time.strftime("flight-%Y%m%d-%H%M%S", time.localtime())
    base = Path.cwd() / f"{timestamp}.orfl"
    for suffix in range(10000):
        target = base if suffix == 0 else base.with_name(f"{base.stem}-{suffix:02d}{base.suffix}")
        if not target.exists():
            return target.resolve()
    raise FlightLogError("cannot choose a fresh default output name")


def _fresh_directory(value: str) -> Path:
    target = Path(value).expanduser().resolve()
    try:
        target.mkdir(parents=True, exist_ok=False)
    except FileExistsError as exc:
        raise FlightLogError(f"output directory already exists: {target}") from exc
    except OSError as exc:
        raise FlightLogError(f"cannot create output directory {target}: {exc}") from exc
    return target


def _existing_log(value: str, *, allow_truncated: bool = False) -> Path:
    path = Path(value).expanduser().resolve()
    truncated_prefix = allow_truncated and path.name.lower().endswith(".orfl.truncate")
    if path.suffix.lower() != ".orfl" and not truncated_prefix:
        raise FlightLogError(f"flight log must use the .orfl extension: {path}")
    if not path.is_file():
        raise FlightLogError(f"flight log does not exist: {path}")
    return path


def _resolve_godot(explicit: str | None) -> str:
    if explicit is not None:
        candidate_value = explicit
    elif os.environ.get("GODOT"):
        candidate_value = os.environ["GODOT"]
    else:
        candidate_value = str(GODOT_DEFAULT)

    candidate_value = os.path.expandvars(candidate_value.strip().strip('"'))
    candidate_path = Path(candidate_value).expanduser()
    if candidate_path.is_file():
        return str(candidate_path.resolve())
    located = shutil.which(candidate_value)
    if located:
        return located
    source = "--godot" if explicit is not None else "GODOT or .tools default"
    raise FlightLogError(f"Godot executable from {source} was not found: {candidate_value}")


def _check_timeout(timeout: float | None) -> float | None:
    if timeout is None:
        return None
    if not math.isfinite(timeout) or timeout <= 0.0:
        raise FlightLogError("timeout must be a finite number greater than zero")
    return timeout


def _run_godot(command: Sequence[str], timeout: float | None, log_path: Path | None = None) -> None:
    timeout = _check_timeout(timeout)
    try:
        if log_path is None:
            result = subprocess.run(command, cwd=ROOT, timeout=timeout, check=False)
        else:
            with log_path.open("x", encoding="utf-8", errors="replace") as output:
                result = subprocess.run(
                    command,
                    cwd=ROOT,
                    stdout=output,
                    stderr=subprocess.STDOUT,
                    timeout=timeout,
                    check=False,
                    text=True,
                )
    except subprocess.TimeoutExpired as exc:
        raise FlightLogError(
            f"Godot timed out after {timeout:g} seconds" if timeout is not None else "Godot timed out"
        ) from exc
    except OSError as exc:
        raise FlightLogError(f"could not start Godot: {exc}") from exc
    if result.returncode != 0:
        details = ""
        if log_path is not None:
            try:
                lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
                if lines:
                    details = "\n" + "\n".join(lines[-30:])
            except OSError:
                pass
        raise FlightLogError(f"Godot exited with code {result.returncode}{details}")
    if log_path is not None:
        with log_path.open(encoding="utf-8", errors="replace") as output:
            for line in output:
                if re.match(r"^(?:(?:SCRIPT|SHADER) )?ERROR:", line):
                    raise FlightLogError(f"Godot reported an engine error despite exit 0: {line.strip()}")


def _check_godot_report(
    report_path: Path, *, recover: bool = False, candidate_replay: bool = False
) -> dict[str, Any]:
    if not report_path.is_file():
        raise FlightLogError(f"Godot did not write its report: {report_path}")
    try:
        document = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise FlightLogError(f"cannot read Godot report {report_path}: {exc}") from exc
    if not isinstance(document, dict):
        raise FlightLogError(f"Godot report must be a JSON object: {report_path}")
    status = document.get("status")
    error = document.get("error")
    if status != "ok" or not isinstance(error, str) or error:
        reason = f"; {error}" if error else ""
        raise FlightLogError(f"Godot reported status {status!r}{reason}")
    complete = document.get("complete")
    if type(complete) is not bool:
        raise FlightLogError("Godot report must include a boolean complete field")
    if not complete:
        recovery_reason = document.get("recovery_reason")
        if not recover:
            raise FlightLogError("Godot reported an incomplete log; pass --recover to export its verified prefix")
        if not isinstance(recovery_reason, str) or not recovery_reason.strip():
            raise FlightLogError("recovered export report must include a recovery_reason")
    if candidate_replay:
        for key in ("baseline_solver_sha256", "current_solver_sha256"):
            value = document.get(key)
            if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", value):
                raise FlightLogError(f"candidate replay report must include a SHA-256 {key}")
        if type(document.get("solver_changed")) is not bool:
            raise FlightLogError("candidate replay report must include boolean solver_changed")
        method = document.get("comparison_method")
        if not isinstance(method, str) or not method.strip():
            raise FlightLogError("candidate replay report must include comparison_method")
    return document


def _check_exported_csv(csv_path: Path, report: dict[str, Any]) -> dict[str, Any]:
    if not csv_path.is_file() or csv_path.stat().st_size == 0:
        raise FlightLogError(f"Godot did not write a nonempty CSV: {csv_path}")
    summary = summarize_csv(csv_path)
    for key in ("rows", "samples", "sample_count", "row_count", "csv_rows"):
        if key not in report:
            continue
        if type(report[key]) is not int:
            raise FlightLogError(f"Godot report field {key!r} must be an integer")
        expected = report[key]
        if expected != summary["rows"]:
            raise FlightLogError(
                f"exported CSV is truncated: Godot reported {expected} rows, found {summary['rows']}"
            )
        break
    return summary


def _godot_export(args: argparse.Namespace, replay: bool, *, debrief: bool = False) -> int:
    recover = bool(not replay and getattr(args, "recover", False))
    log_path = _existing_log(args.log, allow_truncated=recover)
    source_sha256_before = _sha256_file(log_path) if debrief else ""
    godot = _resolve_godot(args.godot)
    timeout = _check_timeout(args.timeout)
    candidate: Path | None = None
    candidate_value = getattr(args, "candidate", None)
    if replay and candidate_value:
        candidate = Path(candidate_value).expanduser().resolve()
        if not candidate.is_file():
            raise FlightLogError(f"candidate aircraft JSON does not exist: {candidate}")
    output_dir = _fresh_directory(args.out)
    csv_path = output_dir / "flight.csv"
    report_path = output_dir / ("replay.json" if replay else "export.json")
    command = [
        godot,
        "--headless",
        "--path",
        str(APP),
        "--audio-driver",
        "Dummy",
        "--script",
        GODOT_SCRIPT,
        "--",
        f"--log={log_path}",
        f"--csv={csv_path}",
        f"--report={report_path}",
    ]
    if replay:
        command.append("--replay")
        if candidate is not None:
            command.append(f"--candidate={candidate}")
    elif getattr(args, "recover", False):
        command.append("--recover")

    _run_godot(command, timeout, output_dir / "godot.log")
    report = _check_godot_report(
        report_path,
        recover=recover,
        candidate_replay=bool(replay and candidate is not None),
    )
    # Validate the output now so a successful exit never advertises a malformed
    # or incomplete CSV as an export/replay result.
    csv_summary = _check_exported_csv(csv_path, report)
    print(f"Wrote {csv_path}")
    print(f"Wrote {report_path}")
    if debrief:
        if _sha256_file(log_path) != source_sha256_before:
            raise FlightLogError("source flight log changed during exact replay; debrief refused")
        document = _build_debrief(csv_path, log_path, report_path, report, csv_summary)
        debrief_path = _write_json_fresh(output_dir / "debrief.json", document)
        print(f"Wrote {debrief_path}")
    return 0


def _record(args: argparse.Namespace) -> int:
    godot = _resolve_godot(args.godot)
    timeout = _check_timeout(args.timeout)
    output = _fresh_record_path(args.out)
    command = [
        godot,
        "--path",
        str(APP),
        "--",
        "--quick-flight",
        f"--flight-log={output}",
    ]
    if args.aircraft:
        command.append(f"--aircraft={args.aircraft}")
    print(f"Recording to {output}; F10 stops, F11 marks a maneuver.", flush=True)
    _run_godot(command, timeout, output.with_suffix(".godot.log"))
    if not output.is_file() or output.stat().st_size == 0:
        raise FlightLogError(f"Godot did not write a nonempty flight log: {output}")
    print(f"Wrote {output}")
    return 0


def _make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Record and inspect OpenRC simulator flight logs. Python analysis uses only the standard library."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    record = subparsers.add_parser("record", help="launch a quick flight and save a new .orfl log")
    record.add_argument("--godot", help="Godot executable (or set GODOT)")
    record.add_argument("--out", help="new .orfl output path; defaults to a timestamped name")
    record.add_argument("--aircraft", help="aircraft catalog ID")
    record.add_argument(
        "--timeout",
        type=float,
        help="maximum run time in seconds; by default an interactive recording has no time limit",
    )
    record.set_defaults(handler=_record)

    export = subparsers.add_parser("export", help="export a .orfl log to CSV in a new directory")
    export.add_argument("log", help="source .orfl flight log")
    export.add_argument("--out", required=True, help="new output directory")
    export.add_argument("--godot", help="Godot executable (or set GODOT)")
    export.add_argument("--timeout", type=float, default=300.0, help="maximum run time in seconds (default: 300)")
    export.add_argument(
        "--recover",
        action="store_true",
        help="export the complete verified prefix of an interrupted or damaged-tail log",
    )
    export.set_defaults(handler=lambda args: _godot_export(args, replay=False))

    replay = subparsers.add_parser("replay", help="replay a .orfl log and export its CSV in a new directory")
    replay.add_argument("log", help="source .orfl flight log")
    replay.add_argument("--out", required=True, help="new output directory")
    replay.add_argument("--godot", help="Godot executable (or set GODOT)")
    replay.add_argument("--candidate", help="candidate aircraft JSON")
    replay.add_argument("--timeout", type=float, default=300.0, help="maximum run time in seconds (default: 300)")
    replay.set_defaults(handler=lambda args: _godot_export(args, replay=True))

    debrief = subparsers.add_parser(
        "debrief", help="exactly replay a complete flight and summarize its marked windows")
    debrief.add_argument("log", help="source .orfl flight log")
    debrief.add_argument("--out", required=True, help="new output directory")
    debrief.add_argument("--godot", help="Godot executable (or set GODOT)")
    debrief.add_argument("--timeout", type=float, default=300.0, help="maximum run time in seconds (default: 300)")
    debrief.set_defaults(handler=lambda args: _godot_export(args, replay=True, debrief=True))

    summarize = subparsers.add_parser("summarize", help="summarize a CSV flight log")
    summarize.add_argument("csv", help="flight log CSV")
    summarize.add_argument("--out", help="write JSON to a new file instead of stdout")
    summarize.set_defaults(handler=_summarize_command)

    compare = subparsers.add_parser("compare", help="compare two aligned flight log CSV files")
    compare.add_argument("base_csv", help="baseline CSV")
    compare.add_argument("candidate_csv", help="candidate CSV")
    compare.add_argument("--out", help="write JSON to a new file instead of stdout")
    compare.set_defaults(handler=_compare_command)
    return parser


def _summarize_command(args: argparse.Namespace) -> int:
    document = summarize_csv(args.csv)
    if args.out:
        print(f"Wrote {_write_json_fresh(args.out, document)}")
    else:
        print(json.dumps(document, indent=2, sort_keys=True, allow_nan=False))
    return 0


def _compare_command(args: argparse.Namespace) -> int:
    document = compare_csv(args.base_csv, args.candidate_csv)
    if args.out:
        print(f"Wrote {_write_json_fresh(args.out, document)}")
    else:
        print(json.dumps(document, indent=2, sort_keys=True, allow_nan=False))
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = _make_parser()
    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except FlightLogError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
