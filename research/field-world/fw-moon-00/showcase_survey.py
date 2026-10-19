# FW-MOON-00: where the moon appears for the pilot of the default field, using the game's ephemeris (Python port).
# The pilot stands at the origin; the runway lies 15 m north, east-west. "Forward" = within 100 deg of north.
# Usage: python3 -I research/field-world/fw-moon-00/showcase_survey.py [year]
import datetime
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ephemeris_port import sky  # noqa: E402

LAT, LON = 40.0, -3.7  # Conditions.REFERENCE (decision D-5)
FORWARD_HALF_WIDTH_DEG = 100.0


def utc_offset(day):
    return 2.0 if 3 < day.month < 11 else 1.0  # coarse CEST/CET; labels only


def forward(azimuth):
    return min(abs(azimuth), abs(azimuth - 360.0)) <= FORWARD_HALF_WIDTH_DEG


def line(label, s):
    return (f"{label}: moon az {s['maz']:6.1f} el {s['mel']:5.1f} illum {s['illum']:.3f} dist {s['dist']:.2f} ER"
            f" | sun az {s['saz']:6.1f} el {s['sel']:6.1f}")


def main(year):
    print("Current presets:")
    print(line("  night (2026-06-30 01:15 CEST, solar midnight)", sky(2026, 6, 30, 1.25, 2.0, LAT, LON)))
    print(line("  evening flow (2026-06-21 22:30 CEST)", sky(2026, 6, 21, 22.5, 2.0, LAT, LON)))
    print("Eclipse dates (Espenak greatest eclipse, UT):")
    print(line("  2026-08-28 04:14 partial", sky(2026, 8, 28, 4.23, 0.0, LAT, LON)))
    print(line("  2028-12-31 16:53 total", sky(2028, 12, 31, 16.88, 0.0, LAT, LON)))
    print(line("  2028-12-31 17:30", sky(2028, 12, 31, 17.5, 0.0, LAT, LON)))
    print(f"Dusk moonrise in front of the pilot, {year} (sun -9..-3, moon el 3..20, illum > 0.9):")
    day = datetime.date(year, 1, 1)
    while day.year == year:
        off = utc_offset(day)
        for k in range(16 * 12, 24 * 12):
            h = k / 12
            s = sky(day.year, day.month, day.day, h, off, LAT, LON)
            if -9 <= s["sel"] <= -3 and 3 <= s["mel"] <= 20 and s["illum"] > 0.9 and forward(s["maz"]):
                print(line(f"  {day} {int(h):02d}:{int(round(h % 1 * 60)):02d} UTC+{off:.0f}", s))
                break
        day += datetime.timedelta(days=1)
    print(f"Full-moon night in front of the pilot, {year} (sun < -18, moon el 15..35, illum > 0.95):")
    day = datetime.date(year, 1, 1)
    while day.year == year:
        off = utc_offset(day)
        for k in range(18 * 6, 30 * 6):
            when = day + datetime.timedelta(days=k // (24 * 6))
            h = (k / 6) % 24
            s = sky(when.year, when.month, when.day, h, off, LAT, LON)
            if s["sel"] < -18 and 15 <= s["mel"] <= 35 and s["illum"] > 0.95 and forward(s["maz"]):
                print(line(f"  {when} {int(h):02d}:{int(round(h % 1 * 60)):02d} UTC+{off:.0f}", s))
                break
        day += datetime.timedelta(days=1)


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 2026)
