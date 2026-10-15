#!/usr/bin/env python3
"""P51-19: summarize baseline vs candidate P51-15 probe reports (trim, selected responses, ground events).

    python research/p51/p51-19/compare_probes.py <baseline-airborne.json> <candidate-airborne.json> \
        <baseline-ground.json> <candidate-ground.json>
"""
import json
import sys

KEYS = ["level_trim_20", "level_trim_25", "level_trim_35", "level_trim_45", "engine_stopped_glide",
        "inverted_hands_off_7s", "pitch_high_1", "pitch_high_-1", "pitch_loop_input_1", "pitch_loop_input_-1",
        "stall_throttle_0.0", "stall_throttle_0.3", "spin_-1", "spin_1", "throttle_split", "running_engine_idle_descent"]


def cases(path):
    return {c["id"]: c for c in json.load(open(path))["cases"]}


def metric(c, name, field):
    return c.get("flight", {}).get("metrics", {}).get(name, {}).get(field, float("nan"))


def main(b_air, c_air, b_gnd, c_gnd):
    B, C = cases(b_air), cases(c_air)
    print("| Case | Trim elevator TE-down deg (base -> cand) | cmd_pitch | alpha end deg | speed end m/s | alt delta m | max alpha deg | complete |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for k in KEYS:
        if k not in B or k not in C:
            continue
        b, c = B[k], C[k]
        te = lambda x: x.get("trim", {}).get("aero_surface_angles_deg", {}).get("elevator_te_down_positive", float("nan"))
        row = [k, f"{te(b):.2f} -> {te(c):.2f}",
               f"{metric(b, 'cmd_pitch', 'start'):.3f} -> {metric(c, 'cmd_pitch', 'start'):.3f}",
               f"{metric(b, 'alpha_deg', 'end'):.2f} -> {metric(c, 'alpha_deg', 'end'):.2f}",
               f"{metric(b, 'speed_mps', 'end'):.2f} -> {metric(c, 'speed_mps', 'end'):.2f}",
               f"{metric(b, 'alt_m', 'delta'):.2f} -> {metric(c, 'alt_m', 'delta'):.2f}",
               f"{metric(b, 'alpha_deg', 'max'):.2f} -> {metric(c, 'alpha_deg', 'max'):.2f}",
               f"{b.get('available') and not b.get('crash') and not b.get('simulation_fault')} / {c.get('available') and not c.get('crash') and not c.get('simulation_fault')}"]
        print("| " + " | ".join(row) + " |")
    bad = [k for k, c in C.items() if not c.get("available") or c.get("crash") or c.get("simulation_fault")]
    print(f"\ncandidate airborne cases {len(C)}, incomplete/crashed/faulted: {bad}")
    G0, G1 = json.load(open(b_gnd)), json.load(open(c_gnd))
    for name in ("numerics_ok", "cases_completed", "completed"):
        print(f"ground {name}: {G0.get(name)} -> {G1.get(name)}")
    fields = ("liftoff_s", "liftoff_along_runway_m", "liftoff_speed_mps", "touchdown_s", "touchdown_speed_mps", "touchdown_sink_mps",
              "post_touchdown_airborne", "ground_distance_m", "heading_change_deg", "max_heading_deviation_deg", "complete", "crashed")
    print("\n| Ground case | Quantity | Baseline | Candidate |\n| --- | --- | --- | --- |")
    for k, c1 in G1["cases"].items():
        c0 = G0["cases"][k]
        for f in fields:
            if c0.get(f) != c1.get(f) and f in c0:
                fmt = lambda x: f"{x:.3f}" if isinstance(x, float) else str(x)
                print(f"| {k} | {f} | {fmt(c0[f])} | {fmt(c1[f])} |")


if __name__ == "__main__":
    main(*sys.argv[1:5])
