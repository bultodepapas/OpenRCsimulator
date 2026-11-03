"""Supervise and validate the optional bounded macOS host-state companion.

The child is diagnostic only: failure or unsupported host never ends the game.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import stat
import subprocess
import threading
import uuid

MAX_BYTES = 4 * 1024 * 1024
MAX_LINE = 8192
MAX_SNAPSHOTS = 4096
MAX_EVENTS = 1024
SLEEP_TOLERANCE_USEC = 50000


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _load_line(line: bytes) -> dict:
    value = json.loads(line, object_pairs_hook=_unique_object,
                       parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite number")))
    if not isinstance(value, dict):
        raise ValueError("row is not an object")
    return value


def _integer(value, *, minimum=0):
    return type(value) is int and value >= minimum


def _anchor(value):
    return (isinstance(value, dict)
            and _integer(value.get("monotonic_usec"))
            and _integer(value.get("unix_usec"), minimum=1)
            and _integer(value.get("uncertainty_usec"), minimum=20000))


def _raw_uptime_anchor(value):
    return (isinstance(value, dict) and value.get("status") == "available"
            and value.get("domain") == "darwin_mach_absolute_time"
            and type(value.get("offset_lower_usec")) is int
            and type(value.get("offset_upper_usec")) is int
            and value["offset_lower_usec"] == value["offset_upper_usec"] == 0)


def _sleep_anchor(value):
    if not isinstance(value, dict):
        return False
    before, continuous, after = (value.get(k) for k in
                                  ("uptime_before_usec", "continuous_usec", "uptime_after_usec"))
    return (_integer(before) and _integer(continuous) and _integer(after)
            and before <= after and continuous >= before)


def _field(value, kind):
    if not isinstance(value, dict) or value.get("status") not in {"available", "unsupported", "unknown", "denied", "error"}:
        return False
    status, result = value["status"], value.get("value")
    if status != "available":
        return result is None and isinstance(value.get("reason"), str)
    if value.get("reason") is not None:
        return False
    if kind == "thermal":
        return (result in ("nominal", "fair", "serious", "critical")
                and type(value.get("enum")) is int
                and value["enum"] == ("nominal", "fair", "serious", "critical").index(result))
    if kind == "low_power":
        return type(result) is bool
    return result in ("ac", "battery", "ups")


def _state(value, *, power, upper):
    if not isinstance(value, dict):
        return False
    start, end = value.get("query_start_usec"), value.get("query_end_usec")
    return (_integer(start) and _integer(end) and start <= end <= upper
            and _field(value.get("thermal"), "thermal")
            and _field(value.get("low_power"), "low_power")
            and (not power or _field(value.get("power_source"), "power_source")))


def validate_stream(data: bytes, capture_id: str, game_pid: int) -> dict:
    """Validate bounded helper output; unknown pressure remains a valid value."""
    if len(data) > MAX_BYTES or not data.endswith(b"\n"):
        raise ValueError("stream exceeds byte bound or has an incomplete last row")
    lines = data.splitlines()
    if len(lines) > MAX_SNAPSHOTS + MAX_EVENTS + 4 or any(not line or len(line) > MAX_LINE for line in lines):
        raise ValueError("stream exceeds row or line bound")
    rows = [_load_line(line) for line in lines]
    if len(rows) < 5 or rows[0].get("type") != "header" or rows[-1].get("type") != "trailer":
        raise ValueError("header or trailer is missing")
    previous = -1
    for index, row in enumerate(rows):
        stamp = row.get("monotonic_usec")
        if row.get("capture_id") != capture_id or row.get("sequence") != index:
            raise ValueError("capture ID or row sequence mismatch")
        if not _integer(stamp) or stamp <= previous:
            raise ValueError("timestamps must increase")
        previous = stamp
    header, trailer = rows[0], rows[-1]
    version = header.get("format")
    if (version not in ("openrc-macos-host-v1", "openrc-macos-host-v2") or header.get("game_pid") != game_pid
            or header.get("test_mode") is not False
            or header.get("memory_pressure_initial") != "unknown"
            or header.get("clock_source") != ("clock_gettime(CLOCK_MONOTONIC)" if version == "openrc-macos-host-v1"
                                               else "clock_gettime(CLOCK_UPTIME_RAW)")
            or header.get("snapshot_limit") != MAX_SNAPSHOTS or header.get("event_limit") != MAX_EVENTS
            or header.get("byte_limit") != MAX_BYTES
            or not _anchor(header.get("clock_start")) or not _anchor(trailer.get("clock_end"))):
        raise ValueError("invalid header or clock anchors")
    start, end = header["clock_start"], trailer["clock_end"]
    if (start["monotonic_usec"] > rows[0]["monotonic_usec"]
            or end["monotonic_usec"] > trailer["monotonic_usec"]
            or end["monotonic_usec"] <= start["monotonic_usec"]
            or (version == "openrc-macos-host-v1" and end["unix_usec"] <= start["unix_usec"])):
        raise ValueError("invalid clock anchor ordering")
    drift = abs((end["unix_usec"] - end["monotonic_usec"])
                - (start["unix_usec"] - start["monotonic_usec"]))
    if version == "openrc-macos-host-v1" and drift > 50000 + start["uncertainty_usec"] + end["uncertainty_usec"]:
        raise ValueError("clock anchor drift exceeds allowance")
    sleep = None
    if version == "openrc-macos-host-v2":
        if not _raw_uptime_anchor(start.get("raw_uptime")) or not _raw_uptime_anchor(end.get("raw_uptime")):
            raise ValueError("invalid raw uptime clock anchor")
        sleep_start, sleep_end = header.get("sleep_start"), trailer.get("sleep_end")
        if (not _sleep_anchor(sleep_start) or not _sleep_anchor(sleep_end)
                or not start["monotonic_usec"] <= sleep_start["uptime_before_usec"]
                <= sleep_start["uptime_after_usec"] <= header["monotonic_usec"]
                or not end["monotonic_usec"] <= sleep_end["uptime_before_usec"]
                <= sleep_end["uptime_after_usec"] <= trailer["monotonic_usec"]):
            raise ValueError("invalid continuous/uptime sleep anchors")
        # Each continuous reading is bounded by its surrounding raw-uptime
        # reads. Widen by 2 us for truncating each clock to microseconds.
        lower = ((sleep_end["continuous_usec"] - sleep_end["uptime_after_usec"])
                 - (sleep_start["continuous_usec"] - sleep_start["uptime_before_usec"]) - 2)
        upper = ((sleep_end["continuous_usec"] - sleep_end["uptime_before_usec"])
                 - (sleep_start["continuous_usec"] - sleep_start["uptime_after_usec"]) + 2)
        sleep = {"start": sleep_start, "end": sleep_end, "delta_lower_usec": lower,
                 "delta_upper_usec": upper,
                 "bracket_uncertainty_usec": (sleep_start["uptime_after_usec"] - sleep_start["uptime_before_usec"]
                                              + sleep_end["uptime_after_usec"] - sleep_end["uptime_before_usec"] + 4),
                 "tolerance_usec": SLEEP_TOLERANCE_USEC,
                 "within_tolerance": lower >= -SLEEP_TOLERANCE_USEC and upper <= SLEEP_TOLERANCE_USEC}
    snapshots, events, initial, ready = [], [], [], []
    for row in rows[1:-1]:
        typ, stamp = row.get("type"), row["monotonic_usec"]
        if typ == "initial":
            if (not _state(row.get("before"), power=False, upper=stamp)
                    or not _state(row.get("after"), power=False, upper=stamp)
                    or row["before"]["query_end_usec"] > row["after"]["query_start_usec"]
                    or row.get("thermal_observer_registered") is not True
                    or row.get("low_power_observer_registered") is not True):
                raise ValueError("invalid initial registration snapshots")
            initial.append(row)
        elif typ == "snapshot":
            if not _state(row, power=True, upper=stamp):
                raise ValueError("invalid host snapshot")
            snapshots.append(row)
        elif typ == "event":
            source = row.get("source")
            if source == "memory_pressure":
                if not _integer(row.get("flags"), minimum=1) or row["flags"] & ~7:
                    raise ValueError("unknown memory pressure flags")
            elif source in ("thermal", "low_power"):
                if not _state(row, power=False, upper=stamp):
                    raise ValueError("invalid notification snapshot")
            else:
                raise ValueError("unknown event source")
            events.append(row)
        elif typ == "ready":
            if row.get("pressure_stream") != "registered":
                raise ValueError("invalid registration receipt")
            ready.append(row)
        else:
            raise ValueError("unknown row type")
    if (len(initial) != 1 or len(ready) != 1 or not snapshots
            or initial[0]["sequence"] >= ready[0]["sequence"]
            or len(snapshots) > MAX_SNAPSHOTS or len(events) > MAX_EVENTS):
        raise ValueError("missing, duplicate, or excessive observations")
    if (not _integer(trailer.get("snapshots")) or not _integer(trailer.get("events"))
            or trailer.get("snapshots") != len(snapshots) or trailer.get("events") != len(events)
            or not _integer(trailer.get("missed_ticks")) or not _integer(trailer.get("local_drops"))
            or type(trailer.get("complete")) is not bool or type(trailer.get("pressure_ready")) is not bool
            or trailer.get("os_coalesced_or_dropped", "missing") is not None):
        raise ValueError("trailer counts or loss fields are invalid")
    complete = (trailer.get("reason") == "stop" and trailer.get("pressure_ready") is True
                and trailer["missed_ticks"] == 0 and trailer["local_drops"] == 0)
    if trailer["complete"] != complete:
        raise ValueError("helper completion and loss fields disagree")
    required_fields = ("thermal", "low_power", "power_source")
    availability = {name: sum(row[name]["status"] == "available" for row in snapshots)
                    for name in required_fields}
    gaps = [b["monotonic_usec"] - a["monotonic_usec"] for a, b in zip(snapshots, snapshots[1:])]
    initial_known = all(initial[0][phase][name]["status"] == "available"
                        for phase in ("before", "after") for name in ("thermal", "low_power"))
    notifications_known = all(all(row[name]["status"] == "available" for name in ("thermal", "low_power"))
                              for row in events if row["source"] in ("thermal", "low_power"))
    complete_fields = all(count == len(snapshots) for count in availability.values())
    coverage = (complete and complete_fields and initial_known and notifications_known
                and all(gap <= 2000000 for gap in gaps)
                and (sleep is None or sleep["within_tolerance"]))
    issues = []
    if not complete:
        issues.append("helper_reported_incomplete:" + str(trailer.get("reason"))[:80])
    if not (complete_fields and initial_known and notifications_known):
        issues.append("required_host_field_unavailable")
    if any(gap > 2000000 for gap in gaps):
        issues.append("snapshot_gap_exceeded")
    if sleep is not None and not sleep["within_tolerance"]:
        issues.append("sleep_or_clock_discontinuity_exceeds_tolerance")
    result = {"coverage": "complete" if coverage else "partial",
            "issues": issues, "local_drops": trailer["local_drops"], "missed_ticks": trailer["missed_ticks"],
            "memory_pressure_initial": "unknown", "memory_pressure_callbacks": sum(e.get("source") == "memory_pressure" for e in events),
            "os_coalesced_or_dropped": None, "sample_count": len(snapshots), "event_count": len(events),
            "required_field_available_counts": availability, "first_snapshot_usec": snapshots[0]["monotonic_usec"],
            "last_snapshot_usec": snapshots[-1]["monotonic_usec"], "pressure_ready_usec": ready[0]["monotonic_usec"],
            "max_snapshot_gap_usec": max(gaps) if gaps else None,
            "initialization": {"start_usec": initial[0]["before"]["query_start_usec"],
                               "end_usec": initial[0]["after"]["query_end_usec"],
                               "thermal_changed": initial[0]["before"]["thermal"] != initial[0]["after"]["thermal"],
                               "low_power_changed": initial[0]["before"]["low_power"] != initial[0]["after"]["low_power"]},
            "clock_offset_drift_usec": drift,
            "clock": {"source": header["clock_source"], "start": start, "end": end},
            "clock_alignment_note": ("raw uptime domain; UTC drift is diagnostic only" if sleep is not None
                                     else "UTC anchors are estimated; check drift and actual frame interval separately")}
    if sleep is not None:
        result["sleep_check"] = sleep
    return result


def _stat_stamp(value: os.stat_result) -> tuple[int, ...]:
    return (value.st_dev, value.st_ino, value.st_mode, value.st_size,
            value.st_mtime_ns, value.st_ctime_ns)


def _file_identity(path: Path) -> tuple[str, tuple[int, ...]]:
    """Hash a bounded regular file and check the opened file and path for drift."""
    h = hashlib.sha256()
    total = 0
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0))
    with os.fdopen(fd, "rb") as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= 64 * 1024 * 1024:
            raise ValueError("identity input must be a bounded nonempty regular file")
        while block := stream.read(65536):
            total += len(block)
            if total > 64 * 1024 * 1024:
                raise ValueError("identity input exceeds size bound")
            h.update(block)
        after = os.fstat(stream.fileno())
        current = path.stat()
        if (total != before.st_size or _stat_stamp(before) != _stat_stamp(after)
                or _stat_stamp(after) != _stat_stamp(current)):
            raise ValueError("identity input changed during hashing")
    return h.hexdigest(), _stat_stamp(after)


class HostStateCapture:
    def __init__(self, helper: Path, capture_id: str, game_pid: int, duration: int, out: Path):
        uuid.UUID(capture_id)
        if not _integer(game_pid, minimum=1) or not _integer(duration, minimum=1) or duration > 3600:
            raise ValueError("invalid host capture PID or duration")
        if platform.system() != "Darwin":
            raise RuntimeError("host-state helper requires Darwin")
        self.path = Path(out)
        self.capture_id = capture_id
        self.game_pid = game_pid
        self.helper_path = Path(helper).absolute()
        self.source_path = Path(__file__).with_suffix(".m").absolute()
        self.helper_identity = _file_identity(self.helper_path)
        self.sha256 = self.helper_identity[0]
        # This is the local source at collection time, not proof of what was
        # compiled into the helper. Preserve the separate native build receipt.
        self.source_identity = _file_identity(self.source_path)
        self.source_sha256 = self.source_identity[0]
        self.identity_errors = []
        self.error = None
        self.process = None
        self.thread = None
        self.byte_count = 0
        self.digest = hashlib.sha256()
        destination = self.path.open("xb", buffering=0)
        try:
            self.process = subprocess.Popen([os.fspath(self.helper_path), capture_id, str(game_pid), str(duration)],
                                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=subprocess.DEVNULL)
        except Exception:
            destination.close()
            raise
        self._check_identities("after_launch")

        def drain():
            try:
                while block := self.process.stdout.read1(65536):
                    if self.byte_count + len(block) > MAX_BYTES:
                        self.error = "byte_limit"
                        break
                    if destination.write(block) != len(block):
                        self.error = "short_write"
                        break
                    self.digest.update(block)
                    self.byte_count += len(block)
            except Exception as error:
                self.error = f"read_or_write_failed:{type(error).__name__}"
            finally:
                self.process.stdout.close()
                destination.close()

        self.thread = threading.Thread(target=drain, daemon=True)
        try:
            self.thread.start()
        except Exception:
            self.process.stdin.close()
            self.process.kill()
            self.process.wait(timeout=3)
            self.process.stdout.close()
            destination.close()
            raise

    def _check_identities(self, phase: str) -> None:
        for name, path, expected in (("helper", self.helper_path, self.helper_identity),
                                     ("source", self.source_path, self.source_identity)):
            try:
                observed = _file_identity(path)
                if observed != expected:
                    self.identity_errors.append(f"{name}_identity_changed_{phase}")
            except (OSError, ValueError) as error:
                self.identity_errors.append(f"{name}_identity_unavailable_{phase}:{type(error).__name__}")

    def finish(self) -> dict:
        # The only process signalled is our still-unreaped Popen child, never a
        # subsequently looked-up PID. EOF requests a normal trailer first.
        try:
            self.process.stdin.close()
        except OSError:
            pass
        try:
            code = self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            code = self.process.wait(timeout=3)
            self.error = self.error or "stop_timeout"
        self.thread.join(timeout=3)
        if self.thread.is_alive():
            self.error = self.error or "reader_timeout"
        self._check_identities("after_stop")
        result = {"file": self.path.name, "bytes": self.byte_count, "sha256": self.digest.hexdigest(),
                  "helper_sha256": self.sha256, "local_source_sha256": self.source_sha256,
                  "identity_checks": "stable_at_prelaunch_postlaunch_and_stop" if not self.identity_errors else "changed_or_unavailable",
                  "identity_errors": list(self.identity_errors),
                  "identity_scope": "path and opened-file stat plus SHA-256 at checks; not executable attestation",
                  "helper_exit": code, "coverage": "partial", "error": self.error}
        if self.error:
            return result
        try:
            with self.path.open("rb") as stream:
                data = stream.read(MAX_BYTES + 1)
            result.update(validate_stream(data, self.capture_id, self.game_pid))
        except (OSError, ValueError, UnicodeError, RecursionError) as error:
            result["error"] = f"invalid_stream:{error}"[:500]
        if code != 0:
            result["coverage"] = "partial"
            result["error"] = result["error"] or "helper_nonzero_exit"
        if self.identity_errors:
            result["coverage"] = "partial"
            result["error"] = result["error"] or "helper_or_source_identity_changed"
        return result
