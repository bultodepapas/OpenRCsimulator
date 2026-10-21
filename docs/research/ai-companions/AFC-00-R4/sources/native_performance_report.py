"""Reject inactive/slow-clock native captures before evaluating frame budgets."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path


def assess(frames: dict, fixture: dict, count: int, minimum_seconds: float = 60.0) -> dict:
    errors: list[str] = []

    def invalid(reason: str) -> dict:
        return {"valid_active_workload": False, "invalid_reasons": [reason],
                "count": count, "simulation_wall_ratio": 0.0, "frame_ms": {},
                "render_budget_pass": False}

    def finite_number(value: object) -> bool:
        return type(value) in (int, float) and math.isfinite(value)

    # A malformed capture must fail as evidence, including NaN/Infinity and
    # booleans masquerading as numbers. Never trust only its summary percentiles.
    if not isinstance(frames, dict) or not isinstance(fixture, dict):
        return invalid("capture and fixture must be objects")
    if type(count) is not int or not 0 <= count <= 3:
        return invalid("invalid requested count")
    for obj, names in [(frames, ["simulation", "raw_metrics", "frame_ms", "flight_companions"]),
                       (fixture, ["initial", "final"])]:
        if any(not isinstance(obj.get(name), dict) for name in names):
            return invalid("missing or malformed capture objects")
    for name in ["actual_sample_s", "actual_warmup_s", "actual_sample_start_monotonic_usec",
                 "actual_sample_end_monotonic_usec"]:
        if not finite_number(frames.get(name)):
            return invalid("missing or nonfinite " + name)
    sample_count = frames.get("frames")
    ticks = frames["raw_metrics"].get("sim_tick")
    wall = frames.get("frame_end_monotonic_usec")
    durations = frames.get("frame_wall_usec")
    if (type(sample_count) is not int or sample_count < 2
            or any(not isinstance(a, list) or len(a) != sample_count for a in [ticks, wall, durations])):
        return invalid("missing common frame/tick/duration samples")
    if (any(not finite_number(t) or t != int(t) or t < 0 for t in ticks)
            or any(not finite_number(t) or t != int(t) or t <= 0 for t in wall + durations)):
        return invalid("invalid tick, wall or frame-duration sample")
    roster = frames["flight_companions"].get("roster")
    if not isinstance(roster, list) or any(not isinstance(a, dict) for a in roster):
        return invalid("malformed companion roster")
    if count and not isinstance(frames["flight_companions"].get("status"), dict):
        return invalid("malformed companion status")
    if not all(finite_number(fixture[key].get("tick")) for key in ["initial", "final"]):
        return invalid("missing or invalid endpoint tick")
    timing = frames["frame_ms"]
    if any(not finite_number(timing.get(key)) or timing[key] <= 0 for key in ["p50", "p95", "p99", "max"]):
        return invalid("missing or invalid frame percentiles")

    def require(value: bool, reason: str) -> None:
        if not value:
            errors.append(reason)

    require(frames.get("complete") is True and not frames.get("failure"), "incomplete frame capture")
    require(frames.get("os") == "Windows" and frames.get("backend") == "gl_compatibility", "wrong native backend/OS")
    require(frames.get("window") == "1280x720", "wrong window size")
    require(float(frames.get("actual_sample_s", 0)) >= minimum_seconds, "sample duration too short")
    require(frames["actual_warmup_s"] >= 10.0, "warmup duration too short")
    start, end = frames["actual_sample_start_monotonic_usec"], frames["actual_sample_end_monotonic_usec"]
    require(start >= 0 and end > start and wall[-1] == end
            and wall[0] - durations[0] == start, "sample endpoints do not match frame durations")
    require(abs(sum(durations) / 1e6 - frames["actual_sample_s"]) <= 1e-6
            and abs((end - start) / 1e6 - frames["actual_sample_s"]) <= 1e-6,
            "reported sample duration disagrees with raw frames")
    require(all(b - a == d for a, b, d in zip(wall, wall[1:], durations[1:])),
            "frame durations disagree with monotonic timestamps")
    ordered = sorted(durations)
    measured = {name: ordered[max(0, math.ceil(q * sample_count) - 1)] / 1000.0
                for name, q in [("p50", .5), ("p95", .95), ("p99", .99), ("max", 1.0)]}
    require(all(abs(timing[k] - measured[k]) <= 1e-9 for k in measured),
            "reported frame percentiles disagree with raw frames")
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
    p95, p99 = measured["p95"], measured["p99"]
    budget_pass = math.isfinite(p95) and math.isfinite(p99) and p95 <= 16.67 and p99 <= 25.0
    return {"valid_active_workload": not errors, "invalid_reasons": errors,
            "count": count, "simulation_wall_ratio": ratio, "frame_ms": measured,
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
