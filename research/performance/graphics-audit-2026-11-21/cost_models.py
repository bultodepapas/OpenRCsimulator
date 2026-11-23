#!/usr/bin/env python3
"""Reproduce analytical bounds. Outputs are arithmetic, never measured FPS."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import subprocess

BASE = "57abea025f62b20233ca281d58d2acbee4ab8b8e"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    sources = ["app/physics/ground_vehicle/nitro_dynamics.gd",
               "app/physics/ground_vehicle/vehicle_dynamics.gd"]
    sizes = {p: len(subprocess.check_output(["git", "-C", str(root), "show", f"{BASE}:{p}"]))
             for p in sources}
    hz, cap, tile_edge, channels, channel_bytes = 240, 12, 2048, 2, 2
    retained_frames = 500_000
    intervals = [1000 / 60] * 5999 + [300.0]
    result = {
        "format": "openrc-graphics-audit-arithmetic-v1", "source": BASE,
        "scope": "Analytical bounds and explicitly invented illustrations; no hardware measurements.",
        "clock": {"hz": hz, "tick_ms": 1000 / hz, "max_steps_per_frame": cap,
                  "max_simulated_ms_per_frame": cap * 1000 / hz,
                  "minimum_sustained_engine_fps_for_realtime": hz / cap,
                  "ordinary_ticks_per_frame": {str(f): hz / f for f in (30, 60, 120, 144)},
                  "sim_wall_upper_bound": {str(f): min(1.0, cap * f / hz) for f in (10, 15, 20, 30)}},
        "nitro_source_reads": {"bytes_by_path": sizes, "bytes_per_guard": sum(sizes.values()),
                               "logical_opens_per_second_at_240_successful_guards": len(sizes) * hz,
                               "logical_bytes_per_second": sum(sizes.values()) * hz,
                               "logical_mib_per_second": sum(sizes.values()) * hz / 2**20,
                               "physical_disk_throughput_measured": False},
        "cloud_tiles": {"maximum_ready_tiles_assumed": 4, "edge": tile_edge,
                        "bytes_per_base_texel": channels * channel_bytes,
                        "base_texels_bytes_per_tile": tile_edge**2 * channels * channel_bytes,
                        "four_tiles_mib": 4 * tile_edge**2 * channels * channel_bytes / 2**20,
                        "driver_or_transient_allocation_included": False},
        "diagnostic_stream": {"frames_per_chunk": 512,
                              "chunk_seconds_at_retained_process_fps": {str(f): 512 / f for f in (30, 60, 120, 144)},
                              "default_frame_cap": retained_frames,
                              "minutes_at_144": retained_frames / 144 / 60,
                              "frames_in_60_minutes_at_144": 3600 * 144,
                              "two_float64_series_mib_at_cap": 2 * 8 * retained_frames / 2**20},
        "pixels": {"scale_area_ratios": {str(s): s * s for s in (0.5, 0.67, 0.75, 1.0)},
                   "output_vs_1080p": {f"{w}x{h}": (w*h)/(1920*1080) for w,h in
                                       ((1920,1080),(2560,1440),(2560,1600),(3840,2160))}},
        "amdahl_illustrations": [{"affected_fraction": p, "component_speedup": 2.0,
                                   "serial_speedup": 1 / ((1-p) + p/2)} for p in (0.2, 0.4, 0.6)],
        "smoothed_step_illustration": {"previous_usec": 500, "one_sample_usec": 4000,
                                      "alpha": 0.05, "display_after_one_sample_usec": 0.95*500+0.05*4000,
                                      "residual_half_life_samples": math.log(0.5)/math.log(0.95)},
        "rare_hitch_illustration": {"definition": "nearest-rank quantile, invented 6000-frame series",
                                   "frames": len(intervals), "p95_ms": sorted(intervals)[math.ceil(.95*len(intervals))-1],
                                   "p99_ms": sorted(intervals)[math.ceil(.99*len(intervals))-1],
                                   "maximum_ms": max(intervals),
                                   "frames_over_33ms": sum(x > 33 for x in intervals)},
    }
    payload = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload)
    else:
        print(payload, end="")


if __name__ == "__main__":
    main()
