#!/usr/bin/env python3
"""FT-01: one Markdown comparison table from several profile.json files (flight_test.gd output).

Usage: python research/flight-test/summarize.py <out dir> [aircraft ...]
Prints the table; a metric whose test was not valid is shown in parentheses, a missing one as a dash.
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
        if isinstance(key, int):
            node = node[key] if isinstance(node, list) and len(node) > key else None
        else:
            node = node.get(key) if isinstance(node, dict) else None
        if node is None:
            return None, bool(r.get("valid"))
    return node, bool(r.get("valid"))


def row_where(results, test, **match):
    r = results.get(test, {})
    for row in r.get("table", []):
        if all(row.get(k) == v for k, v in match.items()):
            return row, bool(r.get("valid"))
    return None, bool(r.get("valid"))


def fmt(value, valid, digits=1):
    if value is None:
        return "–"
    text = f"{value:.{digits}f}" if isinstance(value, (int, float)) and not isinstance(value, bool) else str(value)
    return text if valid else f"({text})"


def main():
    out = Path(sys.argv[1])
    ids = sys.argv[2:] or sorted(p.name for p in out.iterdir() if (p / "profile.json").is_file())
    lines = {}
    names = []
    for aircraft in ids:
        d = json.loads((out / aircraft / "profile.json").read_text(encoding="utf-8"))
        res = d["results"]
        names.append(d.get("name", aircraft))
        start = d["start_speed_mps"]
        roll_row, roll_ok = row_where(res, "roll_rate", direction="right", speed_mps=round(start, 2))
        turn_row, turn_ok = row_where(res, "turn_60", direction="right")
        ke_row, ke_ok = row_where(res, "knife_edge_full_rudder", direction="right", throttle=1.0)
        spin_row, spin_ok = row_where(res, "spin", direction="right")
        cells = {
            "Mass (kg) / start speed (m/s)": f"{d['mass_kg']:.2f} / {start:.1f}",
            "Power-off stall (m/s), wing drop": (lambda v, ok, w: f"{fmt(v, ok, 2)} {w or ''}".strip())(*pick(res, "stall_power_off", ["metrics", "stall_speed_mps"]), pick(res, "stall_power_off", ["metrics", "wing_drop"])[0]),
            "Power-on stall, 50 % throttle (m/s)": fmt(*pick(res, "stall_power_on", ["metrics", "stall_speed_mps"]), 2),
            "Height lost in stall recovery (m)": fmt(*pick(res, "stall_power_off", ["metrics", "altitude_lost_m"])),
            "Max level speed (m/s)": fmt(*pick(res, "vmax", ["metrics", "max_level_speed_mps"])),
            "Time +10 m/s from start speed, full throttle (s)": fmt(*pick(res, "vmax", ["metrics", "time_plus_10_mps_s"]), 2),
            "Best full-throttle climb (m/s)": fmt(*pick(res, "climb", ["metrics", "best", "vertical_speed_mps"])),
            "Best idle glide ratio": fmt(*pick(res, "glide", ["metrics", "best", "glide_ratio"])),
            "Full-aileron roll at start speed (°/s)": fmt(roll_row.get("max_roll_rate_dps") if roll_row else None, roll_ok, 0),
            "60° level turn, full throttle (°/s)": fmt(turn_row.get("turn_rate_dps") if turn_row else None, turn_ok),
            "Loop height (m) / time (s)": f"{fmt(*pick(res, 'loop', ['metrics', 'loop_height_m']), 0)} / {fmt(*pick(res, 'loop', ['metrics', 'loop_time_s']), 1)}",
            "Knife-edge, full top rudder, full throttle: vertical speed (m/s), sideslip (°)":
                f"{fmt(ke_row.get('vertical_speed_mps') if ke_row else None, ke_ok)}, {fmt(ke_row.get('sideslip_deg') if ke_row else None, ke_ok)}",
            "Inverted pass: elevator stick / α (°)": f"{fmt(*pick(res, 'inverted', ['metrics', 'elevator_stick']), 3)} / {fmt(*pick(res, 'inverted', ['metrics', 'alpha_deg']))}",
            "Spin: time per turn (s) / recovery turns": f"{fmt(spin_row.get('steady_turn_time_s') if spin_row else None, spin_ok, 2)} / {fmt(spin_row.get('recovery_turns') if spin_row else None, spin_ok, 2)}",
            "Lift-off speed (m/s, Vs) / ground roll (m)": (lambda: "skipped" if res.get("takeoff", {}).get("skipped") else
                f"{fmt(*pick(res, 'takeoff', ['metrics', 'liftoff_speed_mps']))} ({fmt(*pick(res, 'takeoff', ['metrics', 'liftoff_speed_vs']), 2)}) / {fmt(*pick(res, 'takeoff', ['metrics', 'ground_roll_m']), 0)}")(),
            "Spool-up 10-90 % (s)": fmt(*pick(res, "throttle_response", ["metrics", "spool_up_10_90_s"]), 2),
            "Valid tests": f"{sum(1 for r in res.values() if r.get('valid'))} / {len(res)}",
        }
        for key, value in cells.items():
            lines.setdefault(key, []).append(value)
    print("| Metric | " + " | ".join(names) + " |")
    print("| --- |" + " --- |" * len(names))
    for key, values in lines.items():
        print(f"| {key} | " + " | ".join(values) + " |")


if __name__ == "__main__":
    main()
