#!/usr/bin/env python3
"""Steady spin state of each aircraft in a flight-test run, beside a measured RC spin.

Usage: python research/flight-test/spin_state.py <out dir> [aircraft ...]
Reads <out dir>/<aircraft>/spin_{right,left}.csv and profile.json from flight_test.gd (card v2 or later) and prints one
Markdown table. The state is averaged over the card's steady window, 4.0-6.25 s, where the spin card holds idle, full up
and full rudder. Ωb/2V uses the body rate magnitude; the reference airspeed is scaled to each aircraft's wing loading
with V ∝ sqrt(W/S), which holds for an equal resultant force coefficient.

Reference: NASA FASER (Ultra Stick 120) flight spin, Denham and Owens 2016, table 2: same entry, video-corrected
estimate with a saturated roll gyro. Another airframe, not a Stik acceptance band. Sources:
docs/research/flight-dynamics/rc-aero-data-sources.md.
"""
import csv
import json
import math
import sys
from pathlib import Path

WINDOW_S = (4.0, 6.25)
FASER = {"alpha_deg": 30.0, "beta_deg": 5.0, "speed_mps": 100 * 0.3048, "omega_dps": 250.0, "span_m": 6.29 * 0.3048,
         "wing_loading_kgm2": 19.72 * 0.45359237 / (8.28 * 0.09290304), "p_dps": ">200", "r_dps": "~160"}


def rows(path):
    with path.open() as fh:
        return list(csv.DictReader(line for line in fh if not line.startswith("#")))


def state(path, span):
    window = [r for r in rows(path) if WINDOW_S[0] <= float(r["t_s"]) <= WINDOW_S[1]]
    if not window:
        return None
    col = lambda key: [float(r[key]) for r in window]
    mean = lambda values: sum(values) / len(values)
    u, v, w, speed = col("u_mps"), col("v_mps"), col("w_mps"), col("speed_mps")
    p, q, r = col("p_radps"), col("q_radps"), col("r_radps")
    omega = [math.sqrt(a * a + b * b + c * c) for a, b, c in zip(p, q, r)]
    alt, t = col("alt_m"), col("t_s")
    return {
        "alpha_deg": mean([math.degrees(math.atan2(c, a)) for a, c in zip(u, w)]),
        "beta_deg": abs(mean([math.degrees(math.asin(max(-1.0, min(1.0, b / s)))) for b, s in zip(v, speed)])),
        "speed_mps": mean(speed),
        "omega_dps": math.degrees(mean(omega)),
        "reduced_rate": mean([o * span / (2.0 * s) for o, s in zip(omega, speed)]),
        "p_dps": abs(math.degrees(mean(p))),
        "r_dps": abs(math.degrees(mean(r))),
        "pitch_rate_pp_dps": math.degrees(max(q) - min(q)),
        "sink_mps": (alt[0] - alt[-1]) / (t[-1] - t[0]),
    }


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1])
    names = sys.argv[2:] or sorted(d.name for d in out.iterdir() if (d / "profile.json").exists())
    print("| Aircraft | Side | α (°) | \\|β\\| (°) | V (m/s) | \\|ω\\| (°/s) | Ωb/2V | \\|p\\| (°/s) | \\|r\\| (°/s) | q p-p (°/s) | Sink (m/s) |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for name in names:
        if not (out / name / "profile.json").exists():
            sys.exit(f"no profile.json for {name} in {out}")
        profile = json.loads((out / name / "profile.json").read_text())
        span = float(profile["span_m"])
        loading = float(profile["mass_kg"]) / float(profile["wing_area_m2"])
        for side in ("right", "left"):
            path = out / name / f"spin_{side}.csv"
            s = state(path, span) if path.exists() else None
            if s is None:
                print(f"| {name} | {side} | – | – | – | – | – | – | – | – | – |")
                continue
            print(f"| {name} | {side} | {s['alpha_deg']:.1f} | {s['beta_deg']:.1f} | {s['speed_mps']:.1f} | {s['omega_dps']:.0f} | "
                  f"{s['reduced_rate']:.3f} | {s['p_dps']:.0f} | {s['r_dps']:.0f} | {s['pitch_rate_pp_dps']:.0f} | {s['sink_mps']:.1f} |")
        scaled = FASER["speed_mps"] * math.sqrt(loading / FASER["wing_loading_kgm2"])
        reduced = math.radians(FASER["omega_dps"]) * FASER["span_m"] / (2.0 * FASER["speed_mps"])
        print(f"| FASER flight, V at {name} W/S | – | {FASER['alpha_deg']:.0f} | {FASER['beta_deg']:.0f} | {scaled:.1f} | "
              f"{FASER['omega_dps']:.0f} | {reduced:.3f} | {FASER['p_dps']} | {FASER['r_dps']} | oscillatory | – |")


if __name__ == "__main__":
    main()
