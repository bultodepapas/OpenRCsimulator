"""Passive, bounded device-wide GPU telemetry for an already running GOD TEST.

NVIDIA uses one finite nvidia-smi query per poll; macOS uses the AGX registry
entry's PerformanceStatistics; Linux additionally reads amdgpu DRM sysfs. These
are device-wide observations, include other applications, and cannot identify
the GPU rendering Godot. On Apple Silicon memory is shared system memory, not
a dedicated VRAM total. No privileged commands or state changes are made.
"""
from __future__ import annotations

import copy
import csv
import hashlib
import io
import math
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import threading
import time
from typing import Any

FORMAT = "openrc-godtest-gpu-v1"
COVERAGE = "after_sampler_start; start after bridge readiness; earlier startup is not observed"
SCOPE = "whole_device_not_process"
MAX_ERRORS = 20
COMMAND_TIMEOUT_S = 2.0
# A three-period window plus 250 ms scheduling slack; larger gaps are incomplete.
GAP_INTERVAL_MULTIPLIER = 3
GAP_SCHEDULING_SLACK_S = 0.25
MIN_UTILIZATION_SAMPLES = 2
NV_FIELDS = ("uuid", "pci.bus_id", "name", "utilization.gpu", "utilization.memory",
             "clocks.gr", "clocks.mem", "temperature.gpu", "power.draw", "memory.used", "memory.total")
METRICS = ("gpu_utilization_pct", "memory_utilization_pct", "graphics_clock_mhz", "memory_clock_mhz",
           "temperature_c", "power_w", "memory_used_bytes", "memory_total_bytes", "memory_allocated_bytes",
           "renderer_utilization_pct", "tiler_utilization_pct")
NV_MAP = {"gpu_utilization_pct": ("utilization.gpu", 1), "memory_utilization_pct": ("utilization.memory", 1),
          "graphics_clock_mhz": ("clocks.gr", 1), "memory_clock_mhz": ("clocks.mem", 1),
          "temperature_c": ("temperature.gpu", 1), "power_w": ("power.draw", 1),
          "memory_used_bytes": ("memory.used", 1048576), "memory_total_bytes": ("memory.total", 1048576)}
APPLE_MAP = {"gpu_utilization_pct": ("Device Utilization %", 1),
             "renderer_utilization_pct": ("Renderer Utilization %", 1),
             "tiler_utilization_pct": ("Tiler Utilization %", 1),
             "memory_used_bytes": ("In use system memory", 1),
             "memory_allocated_bytes": ("Alloc system memory", 1)}
AMD_MAP = {"gpu_utilization_pct": ("gpu_busy_percent", 1), "memory_utilization_pct": ("mem_busy_percent", 1),
           "memory_used_bytes": ("mem_info_vram_used", 1), "memory_total_bytes": ("mem_info_vram_total", 1)}
_MISSING = object()


def _now_us() -> int:
    return time.perf_counter_ns() // 1000


def _source_digest() -> str | None:
    try:
        return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    except OSError:
        return None


def _raw(value: Any) -> Any:
    """Keep source values JSON-safe even when a driver reports NaN or odd types."""
    if value is _MISSING or value is None:
        return None
    if type(value) in (int, bool):
        return value
    if type(value) is float:
        return value if math.isfinite(value) else str(value)
    if isinstance(value, str):
        return value[:512]
    if isinstance(value, bytes):
        return value[:256].hex()
    return str(value)[:512]


def _value(value: Any, metric: str, scale: float = 1) -> tuple[float | int | None, str]:
    if value is _MISSING or value is None or (isinstance(value, str) and value.strip().lower() in
                                               {"", "n/a", "not supported", "[not supported]", "-"}):
        return None, "unsupported"
    if isinstance(value, bool):
        return None, "invalid"
    try:
        number = float(value) * scale
    except (TypeError, ValueError, OverflowError):
        return None, "invalid"
    if not math.isfinite(number):
        return None, "invalid"
    # Bound values before summary arithmetic; temperature may legitimately be below zero.
    lower = -273.15 if metric == "temperature_c" else 0
    upper = 100 if metric.endswith("_pct") else (2**63 - 1 if metric.endswith("_bytes") else 1e9)
    if not lower <= number <= upper:
        return None, "invalid"
    return (int(number) if metric.endswith("_bytes") else number), "available"


def _device(backend: str, identity: dict, raw: dict, mapping: dict,
            overrides: dict | None = None) -> dict:
    metrics, statuses, sources = {}, {}, {}
    for metric in METRICS:
        if metric not in mapping:
            metrics[metric], statuses[metric] = None, "unsupported"
            continue
        field, scale = mapping[metric]
        value = raw.get(field, _MISSING)
        metrics[metric], statuses[metric] = _value(value, metric, scale)
        sources[metric] = field
    for metric, (status, source) in (overrides or {}).items():
        metrics[metric], statuses[metric] = None, status
        sources[metric] = source
    return {"backend": backend, "identity": identity, "raw": {str(k): _raw(v) for k, v in raw.items()},
            "metrics": metrics, "metric_status": statuses, "metric_source": sources}


def _exception(error: Exception) -> tuple[str, str]:
    if isinstance(error, subprocess.TimeoutExpired) or isinstance(error, TimeoutError):
        code = "timeout"
    elif isinstance(error, FileNotFoundError):
        code = "tool_not_found"
    elif isinstance(error, PermissionError):
        code = "permission_denied"
    else:
        code = "error"
    return code, f"{type(error).__name__}: {error}"[:500]


def _clean_identity(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    value = value.strip()
    return None if value.lower() in ("", "n/a", "[not supported]", "-") else value[:512]


def _deduplicate(devices: list[dict]) -> bool:
    """Never merge duplicate or missing IDs into one device's history."""
    keys = [item["identity"].get("key") for item in devices]
    duplicate = {key for key in keys if key is not None and keys.count(key) > 1}
    for item in devices:
        identity = item["identity"]
        if identity.get("key") in duplicate:
            identity["key"] = None
            identity["status"] = "duplicate_id"
    return bool(duplicate) or any(not key for key in keys)


class GpuSampler:
    """Sample supported devices at approximately ``interval`` seconds.

    ``runner`` follows subprocess.run's keyword protocol; ``sysfs_root`` and
    ``pci_root`` can point at fixtures. No runner or filesystem reads happen until start().
    ``stop`` has a finite join deadline even if an injected reader blocks; the
    daemon worker cannot mutate the returned snapshot after the deadline.
    """

    def __init__(self, interval: float = 1.0, max_samples: int = 4000, *,
                 platform: str | None = None, runner=None, sysfs_root: str | Path = "/sys/class/drm",
                 pci_root: str | Path = "/sys/bus/pci/devices"):
        try:
            valid_interval = (type(interval) in (int, float) and math.isfinite(interval)
                              and 0.1 <= interval <= 60)
        except OverflowError:
            valid_interval = False
        if not valid_interval:
            raise ValueError("GPU interval must be finite and between 0.1 and 60 seconds")
        if type(max_samples) is not int or not 1 <= max_samples <= 10000:
            raise ValueError("GPU max_samples must be an integer between 1 and 10000")
        self.interval = float(interval)
        self.max_samples = max_samples
        self.platform = sys.platform if platform is None else platform
        self.runner = subprocess.run if runner is None else runner
        self.sysfs_root = Path(sysfs_root)
        self.pci_root = Path(pci_root)
        self._stop = threading.Event()
        self._lock = threading.Lock()
        self._samples: list[dict] = []
        self._errors: list[dict] = []
        self._error_count = 0
        self._capped = False
        self._started = False
        self._sealed = False
        self._result = None
        self._start_us = None
        self._worker_exit_reason = None
        self._thread = threading.Thread(target=self._run, name="godtest-gpu-sampler", daemon=True)
        self._source_hash = _source_digest()

    def _command(self, argv: list[str]) -> bytes:
        kwargs = {"capture_output": True, "timeout": COMMAND_TIMEOUT_S, "check": False}
        if sys.platform == "win32":
            kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW
        result = self.runner(argv, **kwargs)
        if result.returncode:
            stderr = result.stderr.decode("utf-8", "replace") if isinstance(result.stderr, bytes) else str(result.stderr or "")
            raise RuntimeError(f"exit {result.returncode}: {stderr[:300]}")
        return result.stdout.encode("utf-8") if isinstance(result.stdout, str) else result.stdout

    def _nvidia(self) -> tuple[list[dict], str, str | None]:
        output = self._command(["nvidia-smi", "--query-gpu=" + ",".join(NV_FIELDS),
                                "--format=csv,noheader,nounits"]).decode("utf-8", "replace")
        rows = list(csv.reader(io.StringIO(output), skipinitialspace=True))
        devices, malformed = [], 0
        for row in rows:
            if not row or not any(item.strip() for item in row):
                continue
            if len(row) != len(NV_FIELDS):
                malformed += 1
                continue
            raw = {key: value.strip() for key, value in zip(NV_FIELDS, row)}
            uuid, pci = _clean_identity(raw["uuid"]), _clean_identity(raw["pci.bus_id"])
            key = f"nvidia:uuid:{uuid}" if uuid else (f"nvidia:pci:{pci}" if pci else None)
            identity = {"key": key, "status": "available" if key else "unavailable",
                        "uuid": uuid, "pci_bus_id": pci, "name": _clean_identity(raw["name"])}
            devices.append(_device("nvidia_smi", identity, raw, NV_MAP))
        identity_problem = _deduplicate(devices)
        if not devices:
            return [], "unavailable", "malformed_output" if malformed else "no_devices"
        if malformed or identity_problem:
            return devices, "partial", "malformed_rows_or_missing_or_duplicate_identity"
        return devices, "available", None

    def _apple(self) -> tuple[list[dict], str, str | None]:
        data = plistlib.loads(self._command(["ioreg", "-a", "-r", "-d", "1", "-c", "AGXAccelerator"]))
        if not isinstance(data, list):
            raise ValueError("ioreg root is not an array")
        devices, malformed = [], 0
        for item in data:
            if not isinstance(item, dict):
                malformed += 1
                continue
            stats = item.get("PerformanceStatistics")
            if not isinstance(stats, dict):
                stats = {}
            registry_id = item.get("IORegistryEntryID")
            valid_id = type(registry_id) is int and 0 <= registry_id <= 2**64 - 1
            exact_id = str(registry_id) if valid_id else None
            identity = {"key": f"apple:ioreg:{exact_id}" if valid_id else None,
                        "status": "available" if valid_id else "unavailable", "registry_entry_id": exact_id,
                        "registry_id_scope": "until_reboot", "name": _clean_identity(item.get("IORegistryEntryName")),
                        "class": _clean_identity(item.get("IOObjectClass"))}
            raw = {source: stats[source] for source, _ in APPLE_MAP.values() if source in stats}
            devices.append(_device("apple_ioreg_agx", identity, raw, APPLE_MAP))
        identity_problem = _deduplicate(devices)
        if not devices:
            return [], "unavailable", "malformed_output" if malformed else "no_agx_devices"
        if malformed or identity_problem:
            return devices, "partial", "malformed_entries_or_missing_or_duplicate_identity"
        return devices, "available", None

    @staticmethod
    def _file(path: Path) -> tuple[str | None, str]:
        try:
            # sysfs attributes are tiny; avoid retaining arbitrary fixture contents.
            with path.open("r", encoding="utf-8", errors="replace") as stream:
                return stream.read(4096).strip(), "available"
        except FileNotFoundError:
            return None, "unsupported"
        except PermissionError:
            return None, "permission_denied"
        except OSError:
            return None, "error"

    def _amd(self) -> tuple[list[dict], str, str | None]:
        """Read only Linux DRM cards bound to amdgpu; unsupported files stay null."""
        try:
            cards = sorted(path for path in self.sysfs_root.iterdir() if re.fullmatch(r"card\d+", path.name))
        except FileNotFoundError:
            return [], "unavailable", "drm_sysfs_not_found"
        devices, seen, problems = [], set(), []
        for card in cards:
            device = card / "device"
            vendor, vendor_status = self._file(device / "vendor")
            if vendor_status not in ("available", "unsupported"):
                problems.append(f"{card.name}/vendor:{vendor_status}")
            if not vendor or vendor.lower() != "0x1002":
                continue
            try:
                if (device / "driver").resolve(strict=True).name != "amdgpu":
                    continue
                device_path = str(device.resolve(strict=True))
            except (OSError, RuntimeError) as error:
                problems.append(f"{card.name}/identity:{type(error).__name__}")
                continue
            if device_path in seen:
                continue
            seen.add(device_path)
            pci = Path(device_path).name if re.fullmatch(r"[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]", Path(device_path).name) else None
            device_id, id_status = self._file(device / "device")
            key = f"amdgpu:sysfs:{device_path}:device_id:{device_id or 'unavailable'}"
            identity = {"key": key, "status": "available", "sysfs_path": device_path,
                        "identity_scope": "sysfs_path_and_pci_device_model_not_serial",
                        "pci_bus_id": pci, "vendor_id": vendor, "device_id": device_id,
                        "device_id_status": id_status, "drm_card": card.name}
            raw, overrides = {}, {}
            for metric, (field, _) in AMD_MAP.items():
                value, status = self._file(device / field)
                if value is not None:
                    raw[field] = value
                elif status != "unsupported":
                    overrides[metric] = (status, field)
            # pp_dpm_* exposes a starred current level; reject ambiguous lists.
            mapping = dict(AMD_MAP)
            for metric, field in (("graphics_clock_mhz", "pp_dpm_sclk"), ("memory_clock_mhz", "pp_dpm_mclk")):
                text, status = self._file(device / field)
                if text is not None:
                    raw[field] = text
                    active = re.findall(r"(?im)^\s*\d+:\s*([\d.]+)\s*(mhz|ghz)\s*\*", text)
                    if len(active) == 1:
                        raw[field + ":active_mhz"] = str(float(active[0][0]) * (1000 if active[0][1].lower() == "ghz" else 1))
                    else:
                        overrides[metric] = ("invalid", field)
                elif status != "unsupported":
                    overrides[metric] = (status, field)
                mapping[metric] = (field + ":active_mhz", 1)
            try:
                hwmons = sorted((device / "hwmon").glob("hwmon*"))
            except OSError:
                hwmons = []
                problems.append(f"{card.name}/hwmon:error")
            matching = [path for path in hwmons if self._file(path / "name")[0] == "amdgpu"]
            # Do not arbitrarily select between multiple sensor sets.
            if len(matching) == 1:
                for metric, filenames, scale in (("temperature_c", ("temp1_input",), .001),
                                                  ("power_w", ("power1_average", "power1_input"), .000001)):
                    for field in filenames:
                        value, status = self._file(matching[0] / field)
                        if status == "unsupported":
                            continue
                        source = f"{matching[0].name}/{field}"
                        if value is not None:
                            raw[source] = value
                        else:
                            overrides[metric] = (status, source)
                        mapping[metric] = (source, scale)
                        break
            elif len(matching) > 1:
                problems.append(f"{card.name}/hwmon:ambiguous")
            devices.append(_device("amdgpu_sysfs", identity, raw, mapping, overrides))
        if not devices:
            return [], "unavailable", "; ".join(problems)[:500] if problems else "no_amdgpu_devices"
        return devices, "partial" if problems else "available", "; ".join(problems)[:500] if problems else None

    @staticmethod
    def _pci_bus(value: str | None) -> str | None:
        if not isinstance(value, str):
            return None
        match = re.fullmatch(r"([0-9a-fA-F]{4,8}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}\.[0-7])", value)
        if not match or int(match.group(1), 16) > 0xffff:
            return None
        return f"{int(match.group(1), 16):04x}:{match.group(2).lower()}:{match.group(3).lower()}"

    def _linux_inventory(self) -> dict:
        """Read visible PCI vendor IDs and DRM card identities, with no absence inference on failure.

        Every observed DRM card must resolve to a matching PCI device. This does
        not enumerate non-PCI GPUs or establish which GPU renders the app.
        """
        start = _now_us()
        inventory = {"scope": "visible_pci_vendor_ids_and_pci_backed_drm_cards",
                     "start_monotonic_usec": start, "end_monotonic_usec": None,
                     "status": "unknown", "reason": None, "pci_device_count": 0,
                     "pci_vendor_ids": [], "pci_inventory_sha256": None, "drm_cards": {}}
        try:
            paths = sorted(path for path in self.pci_root.iterdir() if self._pci_bus(path.name) == path.name.lower())
            cards = sorted(path for path in self.sysfs_root.iterdir() if re.fullmatch(r"card\d+", path.name))
            if not paths or not cards:
                inventory["reason"] = "empty_pci_or_drm_inventory"
                return inventory
            inventory["pci_device_count"] = len(paths)
            vendors = {}
            for path in paths:
                vendor, state = self._file(path / "vendor")
                if state != "available" or not vendor or not re.fullmatch(r"0x[0-9a-fA-F]{4}", vendor):
                    inventory["reason"] = f"pci_vendor_unavailable:{path.name}:{state}"
                    return inventory
                vendors[path.name.lower()] = vendor.lower()
            inventory["pci_vendor_ids"] = sorted(set(vendors.values()))
            inventory["pci_inventory_sha256"] = hashlib.sha256(
                "\n".join(f"{pci}={vendor}" for pci, vendor in sorted(vendors.items())).encode()
            ).hexdigest()
            inventory["_vendor_by_bus"] = vendors
            for card in cards:
                vendor, state = self._file(card / "device" / "vendor")
                try:
                    pci = self._pci_bus((card / "device").resolve(strict=True).name)
                except (OSError, RuntimeError):
                    pci = None
                if state != "available" or not vendor or not pci or vendors.get(pci) != vendor.lower():
                    inventory["reason"] = f"drm_identity_unavailable_or_inconsistent:{card.name}"
                    return inventory
                inventory["drm_cards"][card.name] = {"pci_bus_id": pci, "vendor_id": vendor.lower()}
            inventory["status"] = "visible_pci_and_drm_consistent"
            return inventory
        except (OSError, RuntimeError) as error:
            inventory["reason"] = f"inventory_unavailable:{type(error).__name__}"
            return inventory
        finally:
            inventory["end_monotonic_usec"] = _now_us()

    def _classify_linux_absence(self, backends: list[dict]) -> dict | None:
        by_name = {item["backend"]: item for item in backends}
        nvidia, amd = by_name["nvidia_smi"], by_name["amdgpu_sysfs"]
        absent_nv = (nvidia["status"] == "unavailable" and
                     (str(nvidia["reason"]).startswith("tool_not_found:") or nvidia["reason"] == "no_devices"))
        absent_amd = amd["status"] == "unavailable" and amd["reason"] == "no_amdgpu_devices"
        if not ((absent_nv and amd["status"] == "available") or
                (absent_amd and nvidia["status"] == "available")):
            return None
        inventory = self._linux_inventory()
        vendors = inventory.pop("_vendor_by_bus", {})
        if inventory["status"] != "visible_pci_and_drm_consistent":
            return inventory
        for candidate, other, absent_vendor, other_vendor, eligible in (
                (nvidia, amd, "0x10de", "0x1002", absent_nv),
                (amd, nvidia, "0x1002", "0x10de", absent_amd)):
            if not eligible or absent_vendor in vendors.values():
                continue
            # Confirm the supported backend's device identities appear in the
            # same inventory; otherwise missing devices cannot be ruled out.
            ids = [self._pci_bus(item["identity"].get("pci_bus_id")) for item in other["devices"]]
            if not ids or any(not pci or vendors.get(pci) != other_vendor for pci in ids):
                continue
            candidate["unavailable_reason"] = candidate["reason"]
            candidate["status"] = "not_applicable"
            candidate["reason"] = "vendor_absent_from_visible_pci_and_drm_inventory"
        return inventory

    def _poll_backend(self, name: str, read) -> dict:
        start = _now_us()
        try:
            devices, status, reason = read()
        except Exception as error:  # monitor failures must not interfere with runner cleanup
            devices, status = [], "unavailable"
            code, detail = _exception(error)
            reason = f"{code}: {detail}"
        return {"backend": name, "start_monotonic_usec": start, "end_monotonic_usec": _now_us(),
                "status": status, "reason": reason, "devices": devices}

    def _poll(self) -> dict:
        before = _now_us()
        if self.platform == "darwin":
            readers = (("apple_ioreg_agx", self._apple),)
        elif self.platform == "win32":
            readers = (("nvidia_smi", self._nvidia),)
        elif self.platform.startswith("linux"):
            readers = (("nvidia_smi", self._nvidia), ("amdgpu_sysfs", self._amd))
        else:
            readers = ()
        backends = [self._poll_backend(name, read) for name, read in readers]
        inventory = self._classify_linux_absence(backends) if self.platform.startswith("linux") else None
        if not readers:
            backends = [{"backend": "none", "start_monotonic_usec": before, "end_monotonic_usec": _now_us(),
                         "status": "unavailable", "reason": "unsupported_platform", "devices": []}]
        return {"start_monotonic_usec": before, "end_monotonic_usec": _now_us(), "backends": backends,
                "linux_inventory": inventory}

    def _run_loop(self) -> str:
        due = time.monotonic()
        while not self._stop.is_set():
            try:
                sample = self._poll()
            except Exception as error:  # monitor errors must not interfere with runner cleanup
                code, detail = _exception(error)
                stamp = _now_us()
                sample = {"start_monotonic_usec": stamp, "end_monotonic_usec": stamp,
                          "backends": [{"backend": "sampler", "start_monotonic_usec": stamp,
                                        "end_monotonic_usec": stamp, "status": "unavailable",
                                        "reason": f"{code}: {detail}", "devices": []}]}
            with self._lock:
                if self._sealed:
                    return "report_sealed"
                self._samples.append(sample)
                for backend in sample["backends"]:
                    if backend["status"] not in ("available", "not_applicable"):
                        self._error_count += 1
                        if len(self._errors) < MAX_ERRORS:
                            self._errors.append({"backend": backend["backend"], "reason": backend["reason"]})
                if len(self._samples) >= self.max_samples:
                    self._capped = True
                    return "sample_cap_reached"
            due = max(due + self.interval, time.monotonic() + 0.05)
            if self._stop.wait(max(0, due - time.monotonic())):
                break
        return "owner_stopped"

    def _run(self) -> None:
        reason = "error"
        try:
            reason = self._run_loop()
        except Exception as error:
            with self._lock:
                if not self._sealed:
                    self._error_count += 1
                    if len(self._errors) < MAX_ERRORS:
                        self._errors.append({"backend": "sampler", "reason": _exception(error)[1]})
        finally:
            with self._lock:
                if not self._sealed:
                    self._worker_exit_reason = reason

    def start(self) -> None:
        if self._started or self._result is not None:
            raise RuntimeError("GPU sampler can only be started once")
        self._started = True
        self._start_us = _now_us()
        self._thread.start()

    def _timing_coverage(self, samples: list[dict], stop_requested: int, device_brackets: dict) -> dict:
        """Check poll and per-device brackets against an explicit scheduling tolerance.

        Observations remain discrete; complete means the bounded sampling policy
        was met, not that the GPU was observed continuously.
        """
        limit = round((GAP_INTERVAL_MULTIPLIER * self.interval + GAP_SCHEDULING_SLACK_S) * 1_000_000)
        reasons = []
        poll_starts = []
        if len(samples) < MIN_UTILIZATION_SAMPLES:
            reasons.append("fewer_than_two_polls")
        for sample in samples:
            begin, end = sample["start_monotonic_usec"], sample["end_monotonic_usec"]
            if (type(begin) is not int or type(end) is not int or self._start_us is None or
                    begin < self._start_us or end < begin or begin > stop_requested or
                    (poll_starts and begin <= poll_starts[-1])):
                reasons.append("invalid_poll_bracket")
                break
            poll_starts.append(begin)
            for backend in sample["backends"]:
                bstart, bend = backend["start_monotonic_usec"], backend["end_monotonic_usec"]
                if (type(bstart) is not int or type(bend) is not int or
                        not begin <= bstart <= bend <= end or bstart > stop_requested):
                    reasons.append("invalid_backend_bracket")
                    break
        if not device_brackets:
            reasons.append("no_identified_utilization_devices")
        first_delays, last_gaps, between_gaps = [], [], []
        for brackets in device_brackets.values():
            if len(brackets) < MIN_UTILIZATION_SAMPLES:
                reasons.append("fewer_than_two_utilization_samples_per_device")
            if not brackets or self._start_us is None:
                continue
            first_delays.append(brackets[0][0] - self._start_us)
            last_gaps.append(max(0, stop_requested - brackets[-1][1]))
            between_gaps.extend(later[0] - earlier[0] for earlier, later in zip(brackets, brackets[1:]))
        first = max(first_delays) if first_delays else None
        last = max(last_gaps) if last_gaps else None
        between = max(between_gaps) if between_gaps else None
        poll_gap = max((later - earlier for earlier, later in zip(poll_starts, poll_starts[1:])), default=None)
        if first is not None and (first < 0 or first > limit):
            reasons.append("first_observation_delayed")
        if last is not None and last > limit:
            reasons.append("last_observation_too_early")
        if between is not None and (between <= 0 or between > limit):
            reasons.append("device_observation_gap")
        if poll_gap is not None and poll_gap > limit:
            reasons.append("poll_gap")
        reasons = sorted(set(reasons))
        return {"status": "incomplete" if reasons else "complete",
                "scope": "discrete per-device utilization observations, not continuous activity",
                "minimum_utilization_samples": MIN_UTILIZATION_SAMPLES,
                "gap_limit_usec": limit, "gap_policy": "three sampling intervals plus 250 ms scheduling slack",
                "first_sample_delay_usec": first, "last_sample_gap_usec": last,
                "max_inter_sample_start_gap_usec": between, "max_poll_start_gap_usec": poll_gap,
                "reasons": reasons}

    def stop(self, *, join_timeout: float = 3.0) -> dict:
        try:
            valid_timeout = (type(join_timeout) in (int, float) and math.isfinite(join_timeout)
                             and 0 <= join_timeout <= 5)
        except OverflowError:
            valid_timeout = False
        if not valid_timeout:
            raise ValueError("GPU sampler join timeout must be finite and between 0 and 5 seconds")
        if self._result is not None:
            return copy.deepcopy(self._result)
        stop_requested = _now_us()
        self._stop.set()
        if self._started:
            self._thread.join(join_timeout)
        alive = self._thread.is_alive()
        with self._lock:
            self._sealed = True
            samples = copy.deepcopy(self._samples)
            errors = copy.deepcopy(self._errors)
            error_count, capped = self._error_count, self._capped
            worker_exit_reason = self._worker_exit_reason
        if not self._started:
            worker_exit_reason = "not_started"
        elif alive:
            worker_exit_reason = "deadline_exceeded"
        elif worker_exit_reason is None:
            worker_exit_reason = "error"
        end_us = _now_us()
        summary, backend_summary, prior_device_sets, device_brackets = {}, {}, {}, {}
        observed_metrics = observed_util = 0
        status_reasons = set()
        if worker_exit_reason != "owner_stopped":
            status_reasons.add("worker_" + worker_exit_reason)
        if capped:
            status_reasons.add("sample_cap_reached")
        for sample in samples:
            for backend in sample["backends"]:
                name = backend["backend"]
                entry = backend_summary.setdefault(name, {"statuses": {}, "reasons": {}, "polls": 0,
                                                          "device_set_changes": 0})
                entry["polls"] += 1
                # An applicable backend becoming absent (or vice versa) is a
                # device-set change, even when another GPU still reports.
                if backend["status"] in ("available", "not_applicable"):
                    keys = frozenset(item["identity"]["key"] for item in backend["devices"])
                    if name in prior_device_sets and keys != prior_device_sets[name]:
                        entry["device_set_changes"] += 1
                        status_reasons.add("device_set_changed")
                    prior_device_sets[name] = keys
                for field, value in (("statuses", backend["status"]), ("reasons", backend["reason"])):
                    if value is not None:
                        entry[field][value] = entry[field].get(value, 0) + 1
                if backend["status"] not in ("available", "not_applicable"):
                    status_reasons.add("backend_unavailable_or_partial")
                for item in backend["devices"]:
                    values = item["metrics"]
                    observed_metrics += sum(value is not None for value in values.values())
                    observed_util += values["gpu_utilization_pct"] is not None
                    key = item["identity"]["key"]
                    if values["gpu_utilization_pct"] is None or not key:
                        status_reasons.add("utilization_or_device_identity_unavailable")
                    if not key:
                        continue
                    observations = device_brackets.setdefault(key, [])
                    if values["gpu_utilization_pct"] is not None:
                        observations.append((backend["start_monotonic_usec"], backend["end_monotonic_usec"]))
                    device = summary.setdefault(key, {"identity": item["identity"], "backend": name,
                                                      "samples": 0, "metrics": {}})
                    device["samples"] += 1
                    for metric, value in values.items():
                        stats = device["metrics"].setdefault(metric, {"count": 0, "min": None, "max": None, "mean": None,
                                                                     "status_counts": {}})
                        state = item["metric_status"][metric]
                        stats["status_counts"][state] = stats["status_counts"].get(state, 0) + 1
                        if value is not None:
                            count = stats["count"] + 1
                            stats["mean"] = value if count == 1 else stats["mean"] + (value - stats["mean"]) / count
                            stats["count"] = count
                            stats["min"] = value if stats["min"] is None else min(stats["min"], value)
                            stats["max"] = value if stats["max"] is None else max(stats["max"], value)
        timing = self._timing_coverage(samples, stop_requested, device_brackets)
        if timing["status"] != "complete":
            status_reasons.add("timing_coverage_incomplete")
        end_hash = _source_digest()
        source_changed = self._source_hash != end_hash if self._source_hash and end_hash else None
        if source_changed is not False:
            status_reasons.add("source_changed_or_unverifiable")
        status = "unavailable" if not observed_metrics else ("partial" if status_reasons or not observed_util else "available")
        result = {"format": FORMAT, "status": status, "status_reasons": sorted(status_reasons), "scope": SCOPE,
                  "coverage": COVERAGE,
                  "coverage_limitations": "Apple Silicon AGX on macOS, NVIDIA on Windows/Linux and amdgpu on Linux; "
                                          "other GPU types are not enumerated. Linux absence classification covers visible "
                                          "PCI vendor IDs and PCI-backed DRM cards only. No rendering-device or process "
                                          "attribution. AMD identity is a sysfs path and model ID, not a serial. "
                                          "Apple registry IDs last until reboot; Apple memory uses shared system memory.",
                  "platform": self.platform, "clock_domain": "python_time_perf_counter",
                  "interval_seconds": self.interval, "max_samples": self.max_samples,
                  "start_monotonic_usec": self._start_us, "stop_requested_monotonic_usec": stop_requested,
                  "stop_monotonic_usec": end_us, "worker_exit_reason": worker_exit_reason,
                  "timing_coverage": timing, "sample_count": len(samples), "sample_cap_reached": capped,
                  "thread_alive": alive, "backends": backend_summary, "samples": samples,
                  "summary_by_device": summary, "errors": errors, "error_count": error_count,
                  "source_sha256": self._source_hash, "source_end_sha256": end_hash, "source_changed": source_changed}
        self._result = result
        return copy.deepcopy(result)
