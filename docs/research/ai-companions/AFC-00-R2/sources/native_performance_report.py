"""Reject inactive/slow-clock native captures before evaluating frame budgets."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path


def assess(frames: dict, fixture: dict, count: int, minimum_seconds: float = 60.0) -> dict:
    errors: list[str] = []

    def require(value: bool, reason: str) -> None:
        if not value:
            errors.append(reason)

    require(frames.get("complete") is True and not frames.get("failure"), "incomplete frame capture")
    require(frames.get("os") == "Windows" and frames.get("backend") == "gl_compatibility", "wrong native backend/OS")
    require(frames.get("window") == "1280x720", "wrong window size")
    require(float(frames.get("actual_sample_s", 0)) >= minimum_seconds, "sample duration too short")
    require(fixture.get("active_flight_endpoint") is True, "inactive fixture endpoint")
    first, final = fixture.get("initial", {}), fixture.get("final", {})
    require(first.get("tick") == 0 and final.get("tick", 0) > 0, "fixture launch/tick mismatch")
    require(not final.get("paused", True) and not final.get("crashed", True)
            and not final.get("prop_strike", True) and final.get("fault") == "", "stopped or damaged player")
    sim = frames.get("simulation", {})
    require(sim.get("end_tick") == final.get("tick") and sim.get("physics_enabled") is True
            and not sim.get("paused", True) and sim.get("fault") == "", "frame/fixture player mismatch")
    require(frames.get("input_enabled") is True and sim.get("physics_ticks_per_second") == 240, "wrong input/physics policy")
    ticks = frames.get("raw_metrics", {}).get("sim_tick", [])
    wall = frames.get("frame_end_monotonic_usec", [])
    require(len(ticks) > 1 and len(ticks) == len(wall) == frames.get("frames"), "missing common frame/tick samples")
    ratio = 0.0
    if len(ticks) > 1 and len(ticks) == len(wall):
        require(all(math.isfinite(t) and t == int(t) and t >= 0 for t in ticks), "invalid tick sample")
        require(all(b >= a for a, b in zip(ticks, ticks[1:])), "simulation tick reset")
        require(all(b > a for a, b in zip(wall, wall[1:])), "nonmonotonic wall samples")
        span = (wall[-1] - wall[0]) / 1e6
        ratio = (ticks[-1] - ticks[0]) / 240.0 / span if span > 0 else 0.0
        require(0.98 <= ratio <= 1.02, "simulation did not maintain wall time within 2 percent")
    fleet = frames.get("flight_companions", {})
    roster = fleet.get("roster", [])
    require(len(roster) == count, "wrong companion roster size")
    if count:
        status = fleet.get("status", {})
        require(status.get("active") == count and not status.get("error")
                and status.get("faulted") == 0 and status.get("crashed") == 0, "fleet is not fully active")
    for aircraft in roster:
        require(aircraft.get("tick") == final.get("tick") and not aircraft.get("paused", True)
                and not aircraft.get("crashed", True) and aircraft.get("fault") == ""
                and aircraft.get("failure") == "", "companion stopped or lost clock synchronization")
    timing = frames.get("frame_ms", {})
    p95, p99 = float(timing.get("p95", math.inf)), float(timing.get("p99", math.inf))
    budget_pass = math.isfinite(p95) and math.isfinite(p99) and p95 <= 16.67 and p99 <= 25.0
    return {"valid_active_workload": not errors, "invalid_reasons": errors,
            "count": count, "simulation_wall_ratio": ratio, "frame_ms": timing,
            "render_budget_pass": not errors and budget_pass,
            "scope": "This capture only; isolation, source identity, CPU budget, all-visible/regime matrix and release gates require separate evidence."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--count", type=int, choices=range(4), required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error("Output must be new")
    result = assess(json.loads(args.frames.read_text()), json.loads(args.fixture.read_text()), args.count)
    result["sources"] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [args.frames, args.fixture, Path(__file__)]}
    args.out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["valid_active_workload"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
