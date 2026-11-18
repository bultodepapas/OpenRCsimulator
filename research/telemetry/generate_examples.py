"""Generate synthetic fixtures only. No data is read from a machine or player."""
import argparse
from copy import deepcopy
import json
from pathlib import Path

from reference import aggregate_daily_gpu, encode, render_report, validate_body

ROOT = Path(__file__).resolve().parent


def example():
    return {
        "schema_version": 1, "notice_version": "2026-11-18",
        "session_id": "a" * 32, "batch_id": "b" * 32,
        "build": {"release_id": "v0.2.7", "channel": "stable", "engine_minor": "4.8"},
        "context": {
            "os_family": "windows", "architecture": "x86_64",
            "cpu_family": "intel_core", "logical_threads_bucket": "9_16",
            "ram_gib_bucket": "9_16", "gpu_family": "nvidia_rtx",
            "renderer": "gl_compatibility", "driver": "opengl3",
            "resolution_class": "1080p", "resolution_basis": "viewport_coordinates",
            "vsync": "on", "fps_cap_bucket": "31_60",
            "graphics_profile": "custom", "input_class": "rc",
        },
        "events": [{
            "name": "performance_window", "seq": 1, "mode": "flight",
            "vehicle_id": "f4u-corsair-250", "phase": "steady",
            "window_complete": True, "interval_count": 1800,
            "interval_sum_us": 30_000_000, "rendered_frames": 1800,
            "draw_counter_status": "observed",
            "interval_histogram": [0, 1800, 0, 0, 0, 0, 0, 0],
            "excluded_gap_count": 0, "gpu_status": "not_measured", "gpu_ms": None,
        }],
    }


def cohort(count, family="nvidia_rtx", start=1):
    result = []
    for index in range(start, start + count):
        payload = deepcopy(example())
        payload["session_id"] = f"{index:032x}"
        payload["batch_id"] = f"{index + 1_000_000:032x}"
        payload["context"]["gpu_family"] = family
        result.append(encode(payload))
    return result


def outputs():
    payload = example()
    validate_body(encode(payload))
    report = aggregate_daily_gpu([("2026-11-17", body) for body in cohort(20)], "2026-11-17", "v0.2.7", as_of_utc="2026-11-18T01:00:00Z")
    return {
        "batch.json": json.dumps(payload, indent=2) + "\n",
        "aggregate.json": json.dumps(report, indent=2) + "\n",
        "github-report.md": "> SYNTHETIC EXAMPLE — one eligible daily subset, not measured players or performance.\n\n" + render_report(report),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    mismatch = []
    for name, content in outputs().items():
        path = ROOT / "examples" / name
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                mismatch.append(name)
        else:
            path.write_text(content, encoding="utf-8")
    if mismatch:
        raise SystemExit("Example mismatch: " + ", ".join(mismatch))
    print("Examples match source" if args.check else "Wrote 3 synthetic examples")


if __name__ == "__main__":
    main()
