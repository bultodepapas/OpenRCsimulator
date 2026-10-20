"""Bounded, opt-in telemetry for one directly launched process.

This module has no psutil import at module load time. The regular Godot runner
can therefore remain standard-library-only when resource sampling is disabled.
"""
from __future__ import annotations

import importlib
import math
import os
from pathlib import Path
import sys
import time


PSUTIL_VERSION = "7.2.2"
MAX_ERRORS = 20
MAX_DISK_PATHS = 8
_MISSING = object()

_INTEGER_FIELDS = {
    "rss_bytes", "vms_bytes", "num_threads",
    "io_read_bytes", "io_write_bytes", "io_read_count", "io_write_count",
    "virtual_memory_total_bytes", "virtual_memory_available_bytes",
    "swap_used_bytes", "swap_total_bytes",
}
_COUNTER_FIELDS = {
    "cpu_user_seconds", "cpu_system_seconds",
    "io_read_bytes", "io_write_bytes", "io_read_count", "io_write_count",
}
_DELTA_FIELDS = tuple(sorted(_COUNTER_FIELDS))
_PROCESS_FIELDS = (
    "rss_bytes", "vms_bytes", "cpu_user_seconds", "cpu_system_seconds",
    "cpu_percent", "num_threads", "io_read_bytes", "io_write_bytes",
    "io_read_count", "io_write_count",
)


def validate_options(*, interval: float = 1.0, max_samples: int = 600,
                     disk_paths=()) -> tuple[str, ...]:
    """Validate monitor options without importing psutil or inspecting a PID.

    Returns normalized path strings for callers that want to reuse the result.
    """
    try:
        interval_value = float(interval) if type(interval) in (int, float) else math.nan
    except (OverflowError, TypeError, ValueError):
        interval_value = math.nan
    if (not math.isfinite(interval_value)
            or interval_value < 0.1 or interval_value > 60):
        raise ValueError("resource interval must be finite and between 0.1 and 60 seconds")
    if type(max_samples) is not int or not 1 <= max_samples <= 10000:
        raise ValueError("resource max_samples must be an integer between 1 and 10000")
    if isinstance(disk_paths, (str, bytes, os.PathLike)):
        raise ValueError("resource disk_paths must be a sequence of existing directories")
    try:
        paths = tuple(disk_paths)
    except TypeError as error:
        raise ValueError("resource disk_paths must be a sequence of existing directories") from error
    if len(paths) > MAX_DISK_PATHS:
        raise ValueError(f"at most {MAX_DISK_PATHS} resource disk paths may be sampled")

    normalized = []
    for raw_path in paths:
        try:
            path = Path(os.fspath(raw_path))
            valid = path.is_dir()
        except (OSError, TypeError, ValueError) as error:
            raise ValueError(f"resource disk path is invalid: {raw_path!r}") from error
        if not valid:
            raise ValueError(f"resource disk path must be an existing directory: {path}")
        normalized.append(os.fspath(path))
    return tuple(normalized)


def load_backend():
    """Lazily load the exact pinned psutil backend or raise an actionable error."""
    try:
        backend = importlib.import_module("psutil")
    except ImportError as error:
        raise ValueError(
            "resource sampling requires psutil 7.2.2; install tools/godot/requirements-resources.txt"
        ) from error
    version = getattr(backend, "__version__", None)
    if version != PSUTIL_VERSION:
        raise ValueError(
            f"resource sampling requires psutil {PSUTIL_VERSION}; found {version or 'unknown'}"
        )
    return backend


class ResourceSampler:
    """Poll one process with bounded samples and diagnostic degradation.

    ``backend`` follows the small psutil module protocol used here (``Process``,
    ``virtual_memory``, ``swap_memory``, and ``disk_usage``). It is injectable
    for tests. Sampling never follows children or terminates the monitored PID.
    """

    def __init__(self, pid, *, interval: float = 1.0, max_samples: int = 600,
                 disk_paths=(), backend=None):
        paths = validate_options(interval=interval, max_samples=max_samples,
                                 disk_paths=disk_paths)
        if type(pid) is not int or pid <= 0:
            raise ValueError("resource sampler pid must be a positive integer")

        self.pid = pid
        self.interval = float(interval)
        self.max_samples = max_samples
        self.disk_paths = paths
        self.backend = load_backend() if backend is None else backend
        self._started_at = time.monotonic()
        self._next_due = None
        self._process = None
        self._create_time = None
        self._identity_status = "unavailable"
        self._finished = False
        self._stop_reason = None
        self._capped = False
        self._samples = []
        self._errors = []
        self._error_count = 0
        self._previous_counters = {}
        self._counter_resets = set()

        try:
            self._process = self.backend.Process(pid)
        except Exception as error:  # backend failures must remain diagnostic only
            self._record_error("process_open", "process", error)
            self._stop_reason = "process_unavailable"
            return
        try:
            creation_time = self._process.create_time()
        except Exception as error:
            self._record_error("identity_unavailable", "create_time", error)
            self._stop_reason = "identity_unavailable"
            return
        normalized = self._normalize(creation_time, "seconds")
        if normalized is None:
            self._record_error("identity_unavailable", "create_time",
                               "process creation time was missing or invalid")
            self._stop_reason = "identity_unavailable"
            return
        self._create_time = normalized
        self._identity_status = "verified"

    def _record_error(self, code: str, field: str, error) -> None:
        self._error_count += 1
        if len(self._errors) >= MAX_ERRORS:
            return
        if isinstance(error, BaseException):
            message = f"{type(error).__name__}: {error}"
        else:
            message = str(error)
        self._errors.append({"code": code[:80], "field": field[:120],
                             "message": message[:500]})

    @staticmethod
    def _normalize(value, kind: str, *, allow_minus_one: bool = False):
        if value is _MISSING or value is None or isinstance(value, bool):
            return None
        if not isinstance(value, (int, float)):
            return None
        try:
            numeric = float(value)
        except (OverflowError, TypeError, ValueError):
            return None
        if not math.isfinite(numeric):
            return None
        if allow_minus_one and numeric == -1:
            return None
        if numeric < 0:
            return None
        if kind == "integer":
            if not isinstance(value, int):
                return None
            return int(value)
        if kind == "percent":
            if numeric > 100:
                return None
            return numeric
        return numeric

    @staticmethod
    def _failure_status(error) -> str:
        name = type(error).__name__.lower()
        if name in {"accessdenied", "permissionerror"}:
            return "denied"
        if name in {"notimplementederror", "unsupportedoperation", "notsupportederror", "attributeerror"}:
            return "unsupported"
        if name in {"nosuchprocess", "zombieprocess", "processlookuperror"}:
            return "process_unavailable"
        return "error"

    def _metric(self, sample: dict, statuses: dict, field: str, getter,
                kind: str = "integer", *, counter: bool = False) -> None:
        try:
            raw = getter()
        except Exception as error:
            status = self._failure_status(error)
            sample[field] = None
            statuses[field] = status
            self._record_error(status, field, error)
            if status == "process_unavailable":
                sample["_process_exited"] = True
            return

        if raw is _MISSING:
            sample[field] = None
            statuses[field] = "unsupported"
            self._record_error("unsupported", field, "backend did not expose this counter")
            return
        if raw is None:
            sample[field] = None
            statuses[field] = "unknown"
            self._record_error("unknown", field, "backend returned no value")
            return
        if counter and isinstance(raw, (int, float)) and not isinstance(raw, bool) and raw == -1:
            sample[field] = None
            statuses[field] = "unknown"
            self._record_error("unknown", field, "backend marked this counter unavailable (-1)")
            return
        normalized = self._normalize(raw, kind, allow_minus_one=counter)
        if normalized is None:
            sample[field] = None
            statuses[field] = "invalid"
            self._record_error("invalid", field, "backend value was negative, non-finite, or had the wrong type")
            return
        sample[field] = normalized
        statuses[field] = "ok"

    def _object_fields(self, sample: dict, statuses: dict, source,
                       specs: tuple[tuple[str, str, str, bool], ...], *, label: str) -> None:
        try:
            obj = source()
        except Exception as error:
            status = self._failure_status(error)
            for field, _attribute, _kind, _counter in specs:
                sample[field] = None
                statuses[field] = status
            self._record_error(status, label, error)
            if status == "process_unavailable":
                sample["_process_exited"] = True
            return
        for field, attribute, kind, counter in specs:
            self._metric(sample, statuses, field,
                         lambda attr=attribute: getattr(obj, attr, _MISSING),
                         kind, counter=counter)

    def _read_process(self, sample: dict, statuses: dict) -> None:
        process = self._process

        def collect_fields():
            self._object_fields(sample, statuses, lambda: process.memory_info(),
                                (("rss_bytes", "rss", "integer", False),
                                 ("vms_bytes", "vms", "integer", False)), label="memory_info")
            self._object_fields(sample, statuses, lambda: process.cpu_times(),
                                (("cpu_user_seconds", "user", "seconds", True),
                                 ("cpu_system_seconds", "system", "seconds", True)), label="cpu_times")
            self._metric(sample, statuses, "num_threads", lambda: process.num_threads(), "integer")
            self._object_fields(sample, statuses, lambda: process.io_counters(),
                                (("io_read_bytes", "read_bytes", "integer", True),
                                 ("io_write_bytes", "write_bytes", "integer", True),
                                 ("io_read_count", "read_count", "integer", True),
                                 ("io_write_count", "write_count", "integer", True)), label="io_counters")

        try:
            oneshot = getattr(process, "oneshot", None)
        except Exception as error:
            self._record_error("oneshot", "process", error)
            collect_fields()
            return
        if not callable(oneshot):
            collect_fields()
            return
        entered = False
        try:
            context = oneshot()
            with context:
                entered = True
                collect_fields()
        except Exception as error:
            self._record_error("oneshot", "process", error)
            if not entered:
                collect_fields()

    def _verify_process_identity(self) -> bool:
        if self._process is None or self._create_time is None:
            return False
        try:
            # Start each poll with a fresh object. psutil caches create_time on
            # a Process instance, so reusing the constructor's object would
            # not independently read the PID's current identity.
            identity_process = self.backend.Process(self.pid)
            running = identity_process.is_running()
        except Exception as error:
            status = self._failure_status(error)
            self._record_error(status, "is_running", error)
            self._identity_status = "process_exited" if status == "process_unavailable" else "unavailable"
            self._stop_reason = "process_exited" if status == "process_unavailable" else "identity_unavailable"
            return False
        if running is not True:
            try:
                latest_process = self.backend.Process(self.pid)
                latest_create_time = self._normalize(latest_process.create_time(), "seconds")
            except Exception as error:
                status = self._failure_status(error)
                if status != "process_unavailable":
                    self._record_error("identity_unavailable", "create_time", error)
                    self._identity_status = "unavailable"
                    self._stop_reason = "identity_unavailable"
                    return False
                latest_create_time = _MISSING
            if latest_create_time is None:
                self._record_error("identity_unavailable", "create_time", "current process creation time was invalid")
                self._identity_status = "unavailable"
                self._stop_reason = "identity_unavailable"
                return False
            if latest_create_time is not _MISSING and latest_create_time != self._create_time:
                self._record_error("pid_reused", "create_time", "PID creation time changed; refusing to sample the new process")
                self._identity_status = "reused"
                self._stop_reason = "pid_reused"
                return False
            self._record_error("process_exited", "is_running", "direct process is no longer running")
            self._identity_status = "process_exited"
            self._stop_reason = "process_exited"
            return False
        try:
            current = self._normalize(identity_process.create_time(), "seconds")
        except Exception as error:
            status = self._failure_status(error)
            self._record_error(status, "create_time", error)
            self._identity_status = "process_exited" if status == "process_unavailable" else "unavailable"
            self._stop_reason = "process_exited" if status == "process_unavailable" else "identity_unavailable"
            return False
        if current is None:
            self._record_error("identity_unavailable", "create_time", "current process creation time was invalid")
            self._identity_status = "unavailable"
            self._stop_reason = "identity_unavailable"
            return False
        if current != self._create_time:
            self._record_error("pid_reused", "create_time", "PID creation time changed; refusing to sample the new process")
            self._identity_status = "reused"
            self._stop_reason = "pid_reused"
            return False
        self._process = identity_process
        return True

    def _read_system(self, sample: dict, statuses: dict) -> None:
        self._object_fields(sample, statuses, lambda: self.backend.virtual_memory(),
                            (("virtual_memory_total_bytes", "total", "integer", False),
                             ("virtual_memory_available_bytes", "available", "integer", False),
                             ("virtual_memory_percent", "percent", "percent", False)),
                            label="virtual_memory")
        self._object_fields(sample, statuses, lambda: self.backend.swap_memory(),
                            (("swap_used_bytes", "used", "integer", False),
                             ("swap_total_bytes", "total", "integer", False)),
                            label="swap_memory")
        for index, path in enumerate(self.disk_paths):
            volume = {"path": path}
            volume_status = {}
            self._object_fields(volume, volume_status,
                                lambda path=path: self.backend.disk_usage(path),
                                (("free_bytes", "free", "integer", False),
                                 ("total_bytes", "total", "integer", False)),
                                label=f"disk_usage[{index}]")
            sample["volumes"].append(volume)
            statuses.update({f"volume[{index}].{key}": value for key, value in volume_status.items()})

    def _update_counter_deltas(self, sample: dict, statuses: dict, elapsed: float) -> None:
        current_values = {}
        for field in _COUNTER_FIELDS:
            current = sample.get(field)
            if current is None:
                continue
            previous = self._previous_counters.get(field)
            if previous is not None and current < previous:
                self._counter_resets.add(field)
                self._record_error("counter_reset", field, "cumulative counter decreased during capture")
            current_values[field] = current

        previous_elapsed = self._samples[-1]["elapsed_seconds"] if self._samples else None
        previous_user = self._samples[-1].get("cpu_user_seconds") if self._samples else None
        previous_system = self._samples[-1].get("cpu_system_seconds") if self._samples else None
        user = sample.get("cpu_user_seconds")
        system = sample.get("cpu_system_seconds")
        sample["cpu_percent"] = None
        if not self._samples:
            statuses["cpu_percent"] = "insufficient_samples"
        elif {"cpu_user_seconds", "cpu_system_seconds"} & self._counter_resets:
            statuses["cpu_percent"] = "counter_reset"
        elif user is None or system is None or previous_user is None or previous_system is None:
            statuses["cpu_percent"] = "dependency_unavailable"
        elif elapsed <= previous_elapsed:
            statuses["cpu_percent"] = "insufficient_elapsed_time"
        if (previous_elapsed is not None and elapsed > previous_elapsed
                and user is not None and system is not None
                and previous_user is not None and previous_system is not None
                and not ({"cpu_user_seconds", "cpu_system_seconds"} & self._counter_resets)
                and user >= previous_user and system >= previous_system):
            cpu_percent = ((user - previous_user) + (system - previous_system)) / (elapsed - previous_elapsed) * 100.0
            if math.isfinite(cpu_percent) and cpu_percent >= 0:
                sample["cpu_percent"] = cpu_percent
                statuses["cpu_percent"] = "ok"
        if sample["cpu_percent"] is None:
            statuses.setdefault("cpu_percent", "unavailable")
        self._previous_counters.update(current_values)

    def poll(self) -> bool:
        """Append one due sample; return false when not due or capture has stopped."""
        if self._finished or self._stop_reason is not None or self._capped:
            return False
        schedule_at = time.monotonic()
        if self._next_due is not None and schedule_at < self._next_due:
            return False
        try:
            poll_started = time.perf_counter()
        except Exception as error:
            poll_started = None
            self._record_error("invalid_clock", "poll_overhead_usec", error)
        if not self._verify_process_identity():
            return False

        sample = {field: None for field in _PROCESS_FIELDS}
        sample.update({
            "virtual_memory_total_bytes": None,
            "virtual_memory_available_bytes": None,
            "virtual_memory_percent": None,
            "swap_used_bytes": None,
            "swap_total_bytes": None,
            "volumes": [],
        })
        statuses = {}
        try:
            self._read_process(sample, statuses)
        except Exception as error:
            self._record_error("process_sample", "process", error)
        try:
            self._read_system(sample, statuses)
        except Exception as error:
            self._record_error("system_sample", "system", error)

        sampled_at = time.monotonic()
        elapsed = sampled_at - self._started_at
        if not math.isfinite(elapsed) or elapsed < 0:
            self._record_error("invalid_clock", "elapsed_seconds", "monotonic elapsed time was invalid")
            elapsed = 0.0
        self._update_counter_deltas(sample, statuses, elapsed)
        sample["elapsed_seconds"] = elapsed
        try:
            overhead = (time.perf_counter() - poll_started) * 1_000_000 if poll_started is not None else math.nan
        except Exception as error:
            self._record_error("invalid_clock", "poll_overhead_usec", error)
            overhead = math.nan
        if not math.isfinite(overhead) or overhead < 0:
            self._record_error("invalid_clock", "poll_overhead_usec", "monotonic poll duration was invalid")
            overhead = 0
        sample["poll_overhead_usec"] = int(round(overhead))
        sample["field_status"] = statuses
        process_exited = bool(sample.pop("_process_exited", False))
        if process_exited:
            self._identity_status = "process_exited"
        self._samples.append(sample)
        self._next_due = sampled_at + self.interval

        if process_exited:
            self._stop_reason = "process_exited"
        if len(self._samples) >= self.max_samples:
            self._capped = True
            self._stop_reason = "sample_limit"
        return True

    def _summary(self) -> dict:
        peak_fields = (
            "rss_bytes", "vms_bytes", "cpu_percent", "num_threads",
            "virtual_memory_total_bytes", "virtual_memory_available_bytes",
            "virtual_memory_percent", "swap_used_bytes", "swap_total_bytes",
        )
        peaks = {}
        for field in peak_fields:
            values = [sample[field] for sample in self._samples if sample.get(field) is not None]
            peaks[field] = max(values) if values else None

        minimum_fields = ("virtual_memory_available_bytes",)
        minima = {}
        for field in minimum_fields:
            values = [sample[field] for sample in self._samples if sample.get(field) is not None]
            minima[field] = min(values) if values else None

        deltas = {}
        for field in _DELTA_FIELDS:
            values = [sample[field] for sample in self._samples if sample.get(field) is not None]
            if field in self._counter_resets or len(values) < 2:
                deltas[field] = None
            elif values[-1] < values[0]:
                deltas[field] = None
            else:
                delta = values[-1] - values[0]
                deltas[field] = int(delta) if field in _INTEGER_FIELDS else delta
        volume_peaks = {}
        volume_minima = {}
        for index, path in enumerate(self.disk_paths):
            volume_peaks[path] = {}
            volume_minima[path] = {}
            for metric in ("free_bytes", "total_bytes"):
                values = []
                for sample in self._samples:
                    if index < len(sample["volumes"]):
                        value = sample["volumes"][index].get(metric)
                        if value is not None:
                            values.append(value)
                volume_peaks[path][metric] = max(values) if values else None
                if metric == "free_bytes":
                    volume_minima[path][metric] = min(values) if values else None

        process_memory_window = {}
        for field in ("rss_bytes", "vms_bytes"):
            values = [sample[field] for sample in self._samples if sample.get(field) is not None]
            process_memory_window[field] = {
                "first_bytes": values[0] if values else None,
                "last_bytes": values[-1] if values else None,
                "delta_bytes": values[-1] - values[0] if len(values) >= 2 else None,
            }
        return {"peaks": peaks, "minima": minima, "counter_deltas": deltas,
                "counter_resets": sorted(self._counter_resets),
                "process_memory_window": process_memory_window,
                "volume_capacity_peaks": volume_peaks,
                "volume_free_capacity_minima": volume_minima}

    def finish(self) -> dict:
        """Stop future polling and return a bounded JSON-serializable report."""
        if not self._finished:
            self._finished = True
            if self._stop_reason is None:
                self._stop_reason = "caller_finished"
        if self._capped:
            coverage = "capped"
        elif not self._samples:
            coverage = "no_samples"
        elif (self._error_count > 0 or self._stop_reason in {
                "process_exited", "pid_reused", "identity_unavailable", "process_unavailable"}):
            coverage = "partial"
        else:
            coverage = "sampled"
        try:
            psutil_version = getattr(self.backend, "__version__", None)
        except Exception:
            psutil_version = None
        return {
            "format": "openrc-resource-samples v1",
            "pid": self.pid,
            "process_create_time": self._create_time,
            "platform": sys.platform,
            "identity_status": self._identity_status,
            "psutil_version": psutil_version,
            "scope": {
                "process": "direct launched PID only; descendants are not included",
                "memory": "RSS and virtual size for this process; Windows virtual size is private commit",
                "cpu": "process CPU time; derived percent is process CPU divided by elapsed wall time and may exceed 100%",
                "io": "process I/O counters where the operating system exposes them; not physical disk traffic",
                "system_memory": "system-wide virtual memory and swap snapshot",
                "volumes": "free and total capacity for explicitly listed paths; not free VRAM",
            },
            "interval_seconds": self.interval,
            "max_samples": self.max_samples,
            "disk_paths": list(self.disk_paths),
            "coverage": coverage,
            "measurement_status": "unavailable" if not self._samples else ("partial" if self._error_count else "ok"),
            "stop_reason": self._stop_reason,
            "capped": self._capped,
            "sample_count": len(self._samples),
            "error_count": self._error_count,
            "errors": list(self._errors),
            "errors_truncated": self._error_count > len(self._errors),
            "samples": list(self._samples),
            "summary": self._summary(),
        }
