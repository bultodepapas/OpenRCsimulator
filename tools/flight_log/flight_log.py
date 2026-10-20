#!/usr/bin/env python3
"""Record, export, summarize, and compare OpenRC flight logs using the stdlib."""

from __future__ import annotations

import argparse
import csv
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
GODOT_DEFAULT = ROOT / ".tools" / "Godot_v4.7.2-stable_win64_console.exe"
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


def _check_exported_csv(csv_path: Path, report: dict[str, Any]) -> None:
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


def _godot_export(args: argparse.Namespace, replay: bool) -> int:
    recover = bool(not replay and getattr(args, "recover", False))
    log_path = _existing_log(args.log, allow_truncated=recover)
    godot = _resolve_godot(args.godot)
    timeout = _check_timeout(args.timeout)
    candidate: Path | None = None
    if replay and args.candidate:
        candidate = Path(args.candidate).expanduser().resolve()
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
    _check_exported_csv(csv_path, report)
    print(f"Wrote {csv_path}")
    print(f"Wrote {report_path}")
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
