#!/usr/bin/env python3
"""FT-02: one Markdown comparison table from several profile.json files (flight_test.gd output).

Usage: python research/flight-test/summarize.py <out dir> [aircraft ...]
Prints the table. A value from a test whose pilot did not meet the card is in parentheses; – means not measured.
"""
import json
import sys
from pathlib import Path


def pick(results, test, path):
    r = results.get(test)
    if r is None:
        return None, False
    node = r
    for key in path:
        node = node.get(key) if isinstance(node, dict) else None
        if node is None:
            return None, bool(r.get("valid"))
    return node, bool(r.get("valid"))


def case(results, test, name, field):
    r = results.get(test, {})
    for row in r.get("table", []):
        if row.get("case") == name:
            return row.get(field), bool(r.get("valid"))
    return None, bool(r.get("valid"))


def fmt(pair, digits=1):
    value, valid = pair
    if value is None:
        return "–"
    text = f"{value:.{digits}f}" if isinstance(value, (int, float)) and not isinstance(value, bool) else str(value)
    return text if valid else f"({text})"


def skipped(results, test):
    return results.get(test, {}).get("skipped", False)


def column(d):
    res = d["results"]
    land = "skipped" if skipped(res, "landing") else (
        f"{fmt(pick(res, 'landing', ['metrics', 'touchdown_speed_mps']))} / {fmt(pick(res, 'landing', ['metrics', 'touchdown_sink_mps']), 2)}"
        f" / {fmt(pick(res, 'landing', ['metrics', 'rollout_m']), 0)}")
    takeoff = "skipped" if skipped(res, "takeoff") else (
        f"{fmt(pick(res, 'takeoff', ['metrics', 'liftoff_speed_mps']))} ({fmt(pick(res, 'takeoff', ['metrics', 'liftoff_speed_vs']), 2)})"
        f" / {fmt(pick(res, 'takeoff', ['metrics', 'ground_roll_m']), 0)}")
    spiral = case(res, "modes", "start", "spiral_time_to_double_s")
    spiral_text = f"doubles {fmt(spiral)} s" if spiral[0] is not None else f"halves {fmt(case(res, 'modes', 'start', 'spiral_time_to_half_s'))} s"
    return {
        "Mass (kg) / start speed (m/s)": f"{d['mass_kg']:.2f} / {d['start_speed_mps']:.1f}",
        "Power-off stall (m/s), wing drop": f"{fmt(pick(res, 'stall_power_off', ['metrics', 'stall_speed_mps']), 2)} {pick(res, 'stall_power_off', ['metrics', 'wing_drop'])[0] or ''}".strip(),
        "Power-on stall, 50 % throttle (m/s)": fmt(pick(res, "stall_power_on", ["metrics", "stall_speed_mps"]), 2),
        "Max level speed (m/s)": fmt(pick(res, "vmax", ["metrics", "max_level_speed_mps"])),
        "Time +10 m/s, full throttle (s)": fmt(pick(res, "vmax", ["metrics", "time_plus_10_mps_s"]), 2),
        "Cruise throttle at start speed": fmt(pick(res, "trim_sweep", ["metrics", "cruise_throttle_at_start_speed"]), 3),
        "Best full-throttle climb (m/s)": fmt(pick(res, "climb", ["metrics", "best", "vertical_speed_mps"])),
        "Best idle glide ratio": fmt(pick(res, "glide", ["metrics", "best", "glide_ratio"])),
        "Full-aileron roll at start speed (°/s)": fmt(case(res, "roll_rate", "start_right", "max_roll_rate_dps"), 0),
        "60° level turn, full throttle (°/s)": fmt(case(res, "turn_60", "right", "turn_rate_dps")),
        "Loop height (m) / time (s)": f"{fmt(pick(res, 'loop', ['metrics', 'loop_height_m']), 0)} / {fmt(pick(res, 'loop', ['metrics', 'loop_time_s']))}",
        "Knife-edge, full top rudder, full throttle: vertical speed (m/s) / sideslip (°)":
            f"{fmt(case(res, 'knife_edge_full_rudder', 'right_100pct', 'vertical_speed_mps'))} / {fmt(case(res, 'knife_edge_full_rudder', 'right_100pct', 'sideslip_deg'))}",
        "Inverted pass: elevator stick / α (°)": f"{fmt(pick(res, 'inverted', ['metrics', 'elevator_stick']), 3)} / {fmt(pick(res, 'inverted', ['metrics', 'alpha_deg']))}",
        "Spin (right): entry / time per turn (s) / recovery turns":
            f"{case(res, 'spin', 'right', 'entered')[0] or '–'} / {fmt(case(res, 'spin', 'right', 'steady_turn_time_s'), 2)} / {fmt(case(res, 'spin', 'right', 'recovery_turns'), 2)}",
        "Modes at start speed: phugoid period (s), ζ / dutch roll ζ / spiral":
            f"{fmt(case(res, 'modes', 'start', 'phugoid_period_s'))}, {fmt(case(res, 'modes', 'start', 'phugoid_zeta'), 2)} / {fmt(case(res, 'modes', 'start', 'dutch_roll_zeta'), 2)} / {spiral_text}",
        "Hands off 30 s after small pulses: heading change (°) / height change (m)":
            f"{fmt(pick(res, 'hands_off', ['metrics', 'heading_change_30_s_deg']), 0)} / {fmt(pick(res, 'hands_off', ['metrics', 'height_change_30_s_m']))}",
        "Lift-off speed (m/s, Vs) / ground roll (m)": takeoff,
        "Landing: touchdown speed (m/s) / sink (m/s) / rollout (m)": land,
        "Spool-up 10-90 % (s)": fmt(pick(res, "throttle_response", ["metrics", "spool_up_10_90_s"]), 2),
        "Valid tests": f"{sum(1 for r in res.values() if r.get('valid'))} / {len(res)} ({sum(1 for r in res.values() if r.get('skipped'))} skipped)",
    }


def main_with(out, ids):
    names = []
    lines = {}
    for aircraft in ids:
        d = json.loads((Path(out) / aircraft / "profile.json").read_text(encoding="utf-8"))
        names.append(d.get("name", aircraft))
        for key, value in column(d).items():
            lines.setdefault(key, []).append(value)
    print("| Metric | " + " | ".join(names) + " |")
    print("| --- |" + " --- |" * len(names))
    for key, values in lines.items():
        print(f"| {key} | " + " | ".join(values) + " |")


def main():
    out = Path(sys.argv[1])
    ids = sys.argv[2:] or sorted(p.name for p in out.iterdir() if (p / "profile.json").is_file())
    main_with(out, ids)


if __name__ == "__main__":
    main()
