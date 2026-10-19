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


def worst_point(results):
    """Largest over-rotation of the right four-point roll's points, with that test's validity."""
    value, valid = case(results, "point_roll", "right", "over_rotation_point_1_deg")
    if value is None:
        return None, valid
    points = [case(results, "point_roll", "right", f"over_rotation_point_{i}_deg")[0] for i in range(1, 5)]
    return max(p for p in points if p is not None), valid


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
        # Card v4 (FT-04); a v3 profile shows – here.
        "Inverted at 0.8 Vmax: elevator stick / α (°)":
            f"{fmt(case(res, 'inverted_speeds', '0.8Vmax', 'elevator_stick'), 3)} / {fmt(case(res, 'inverted_speeds', '0.8Vmax', 'alpha_deg'))}",
        "Immelmann: height gained (m) / speed over the top (Vs)":
            f"{fmt(pick(res, 'immelmann', ['metrics', 'height_gain_m']), 0)} / {fmt(pick(res, 'immelmann', ['metrics', 'top_speed_vs']), 2)}",
        "Split-S from start speed, idle: height lost (m)": fmt(pick(res, "split_s", ["metrics", "height_lost_m"]), 0),
        "Outside loop: depth (m) / least load factor (g)":
            f"{fmt(pick(res, 'outside_loop', ['metrics', 'loop_depth_m']), 0)} / {fmt(pick(res, 'outside_loop', ['metrics', 'min_load_factor_g']), 2)}",
        "Slow roll (right): height change (m) / peak rudder stick":
            f"{fmt(case(res, 'slow_roll', 'right', 'height_change_m'))} / {fmt(case(res, 'slow_roll', 'right', 'peak_rudder_stick'), 2)}",
        "Four-point roll (right): worst over-rotation (°)": fmt(worst_point(res)),
        "Snap roll (right): entry / autorotation short of 360° (°) / stop error (°)":
            f"{fmt(case(res, 'snap_roll', 'right', 'entered'))} / {fmt(case(res, 'snap_roll', 'right', 'autorotation_short_of_finish_deg'), 0)}"
            f" / {fmt(case(res, 'snap_roll', 'right', 'stop_error_deg'), 0)}",
        "Stall turn (right, kick at 0.35 Vs): outcome / pivot radius (spans)":
            f"{fmt(case(res, 'stall_turn', 'right_0.35Vs', 'outcome'))} / {fmt(case(res, 'stall_turn', 'right_0.35Vs', 'pivot_radius_spans'), 2)}",
        "Engine cut in the climb, 1 s reaction: least speed (Vs) / stalled":
            f"{fmt(case(res, 'engine_cut_climb', 'delay_1s', 'min_speed_vs'), 2)} / {fmt(case(res, 'engine_cut_climb', 'delay_1s', 'stalled'))}",
        "Turn back, engine off: least height per 180° (m) at bank (°)":
            f"{fmt(pick(res, 'glide_turn', ['metrics', 'least_height_lost_180_m']))} at {fmt(pick(res, 'glide_turn', ['metrics', 'least_height_per_180_bank_deg']), 0)}",
        "Turning stall, 45° right: speed / Vs√n, roll-off":
            f"{fmt(case(res, 'stall_turning', '45_right', 'ratio_to_vs_root_n'), 3)}, {fmt(case(res, 'stall_turning', '45_right', 'roll_off'))}",
        "Skidded stall (right): roll-off in 1 s (°)": fmt(case(res, "stall_cross_controlled", "right", "roll_off_in_1_s_deg"), 0),
        "Stall held 5 s, controls neutral: outcome / height lost (m)":
            f"{fmt(case(res, 'stall_held', 'controls_neutral', 'outcome'))} / {fmt(case(res, 'stall_held', 'controls_neutral', 'height_lost_held_m'), 0)}",
        "Inverted stall: speed (upright Vs)": fmt(pick(res, "stall_inverted", ["metrics", "ratio_to_upright_vs"]), 2),
        "Inverted spin (right rudder): entry / time per turn (s)":
            f"{fmt(case(res, 'spin_inverted', 'right', 'entered'))} / {fmt(case(res, 'spin_inverted', 'right', 'steady_turn_time_s'), 2)}",
        "Dead-stick: glide ratio / touchdown past the aim (m)": "skipped" if skipped(res, "dead_stick_landing") else (
            f"{fmt(pick(res, 'dead_stick_landing', ['metrics', 'glide_ratio']))} / {fmt(pick(res, 'dead_stick_landing', ['metrics', 'touchdown_past_aim_m']))}"),
        "Go-around, throttle slammed: least wheel height (m) / most bank (°)": "skipped" if skipped(res, "go_around") else (
            f"{fmt(case(res, 'go_around', 'fast', 'min_wheel_height_m'), 2)} / {fmt(case(res, 'go_around', 'fast', 'max_bank_deg'))}"),
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
