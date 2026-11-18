"""Shared test helpers: synthetic batches, temp configuration and a fake clock."""
from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path
import tempfile

from openrc_telemetry.config import Config

SERVICE_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = SERVICE_DIR.parents[1]
TELEMETRY_RESEARCH = REPO_ROOT / "research" / "telemetry"
SCHEMA_DIR = TELEMETRY_RESEARCH / "contracts"
FIXTURE = TELEMETRY_RESEARCH / "examples" / "batch.json"
RELEASE = "v0.2.7"

CONTEXT = {
    "os_family": "windows", "architecture": "x86_64", "cpu_family": "intel_core",
    "logical_threads_bucket": "9_16", "ram_gib_bucket": "9_16", "gpu_family": "nvidia_rtx",
    "renderer": "gl_compatibility", "driver": "opengl3", "resolution_class": "1080p",
    "resolution_basis": "viewport_coordinates", "vsync": "on", "fps_cap_bucket": "31_60",
    "graphics_profile": "custom", "input_class": "rc",
}


def hex32(number):
    return f"{number:032x}"


def perf_event(seq, *, vehicle="f4u-corsair-250", sum_us=30_000_000, frames=1800, complete=True,
               mode="flight", phase="steady", draws="observed"):
    histogram = [0, 1800, 0, 0, 0, 0, 0, 0]
    return {"name": "performance_window", "seq": seq, "mode": mode, "vehicle_id": vehicle, "phase": phase,
            "window_complete": complete, "interval_count": 1800, "interval_sum_us": sum_us,
            "rendered_frames": frames if draws == "observed" else None, "draw_counter_status": draws,
            "interval_histogram": histogram, "excluded_gap_count": 0, "gpu_status": "not_measured",
            "gpu_ms": None}


def activity_event(seq, *, vehicle="f4u-corsair-250", seconds=600):
    return {"name": "activity_summary", "seq": seq, "vehicle_id": vehicle, "active_seconds": seconds,
            "simulated_seconds": seconds, "outcome": "returned_home", "complete_observation": True,
            "classification": "accepted_fixed_wing", "takeoffs": 1, "landings": 1, "aircraft_crashes": 0}


def batch(session=1, batch_id=None, events=None, *, release=RELEASE, gpu="nvidia_rtx"):
    return {
        "schema_version": 1, "notice_version": "2026-11-18", "session_id": hex32(session),
        "batch_id": hex32(batch_id if batch_id is not None else 10_000 + session),
        "build": {"release_id": release, "channel": "stable", "engine_minor": "4.8"},
        "context": {**CONTEXT, "gpu_family": gpu},
        "events": deepcopy(events) if events is not None else [perf_event(1)],
    }


def encode(payload):
    return json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def fixture():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def make_config(directory, **overrides):
    values = {"data_dir": Path(directory), "schema_dir": SCHEMA_DIR, "releases": frozenset({RELEASE}),
              "client_burst": 1000.0, "client_refill_per_s": 1000.0,
              "global_burst": 100000.0, "global_refill_per_s": 100000.0}
    values.update(overrides)
    return Config(**values)


def unix(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00")).replace(tzinfo=timezone.utc).timestamp()


class FakeClock:
    def __init__(self, now):
        self.now = float(now)

    def __call__(self):
        return self.now


class TempDir:
    """Context manager placing temporary data under the configured TEMP (U: on this host)."""

    def __enter__(self):
        self._dir = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        return Path(self._dir.name)

    def __exit__(self, *exc):
        self._dir.cleanup()
