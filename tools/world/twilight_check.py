#!/usr/bin/env python3
"""FIELD-WORLD-PLAN FW-60: the sky table's twilight against the AMS Glossary of Meteorology.

Horizontal sky illuminance is approximated from the table as pi x hemisphere-average radiance, with the average
0.4 x zenith + 0.6 x (anti-sun haze + azimuth-averaged sunward lobe), plus direct sun. Ratios to sunset are
compared with the AMS clear-sky values (sunset 400-585 lux, civil -6 deg 2-3.5 lux, nautical -12 deg 0.008 lux).
Below -12 deg the scattered sunlight vanishes in the model; the game's night floor (sky_state.gd) carries the sky.
Measured 2026-10-10: -6 deg 2.1x the AMS ratio, -12 deg 3.9x. Exits non-zero beyond TOLERANCE.
  python3 tools/world/twilight_check.py
"""
import json
import math
import sys
from pathlib import Path

TABLE = Path(__file__).resolve().parents[2] / "app" / "data" / "sky" / "sky_table.json"
AMS_LUX = {0.0: (400.0, 585.0), -6.0: (2.0, 3.5), -12.0: (0.008, 0.008)}
TOLERANCE = 5.0  # factor; the -12 deg band sits at 3.9


def lum(v):
    return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]


def lobe_average(k, n=3600):
    return sum(max(math.cos(2.0 * math.pi * i / n), 0.0) ** k for i in range(n)) / n


def illuminance(row, elevation_deg):
    sky = 0.4 * lum(row["zenith"]) + 0.6 * (lum(row["haze"]) + lobe_average(row["lobe_k"]) * lum(row["lobe"]))
    return math.pi * sky + lum(row["sun"]) * max(math.sin(math.radians(elevation_deg)), 0.0)


def main():
    rows = {r["elevation_deg"]: r for r in json.loads(TABLE.read_text(encoding="utf-8"))["rows"]}
    sunset = illuminance(rows[0.0], 0.0)
    ams_sunset = math.sqrt(AMS_LUX[0.0][0] * AMS_LUX[0.0][1])
    worst = 1.0
    for el, (lo, hi) in AMS_LUX.items():
        model = illuminance(rows[el], el) / sunset
        ams = math.sqrt(lo * hi) / ams_sunset
        factor = max(model / ams, ams / model)
        worst = max(worst, factor)
        print(f"sun {el:6.1f} deg: model {model:.3e}, AMS {ams:.3e}, off by {factor:.2f}x")
    if worst > TOLERANCE:
        sys.exit(f"twilight off by {worst:.2f}x (> {TOLERANCE}x)")
    print(f"twilight within {TOLERANCE}x of the AMS bands")


if __name__ == "__main__":
    main()
