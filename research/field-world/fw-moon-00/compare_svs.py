# FW-MOON-00: compares the game's moon (ephemeris_port.py) with NASA SVS 5587 "Moon Phase and Libration, 2026"
# (mooninfo_2026.json, hourly, geocentric). Usage:
#   python3 -I research/field-world/fw-moon-00/compare_svs.py references/moon/svs/mooninfo_2026.json
# Reports illuminated-fraction, distance and precession-corrected ecliptic position residuals (every 7th hour).
import datetime
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ephemeris_port as eph  # noqa: E402

EARTH_RADIUS_KM = 6378.14
OBLIQUITY_J2000 = math.radians(23.4392911)


def stats(values):
    a = sorted(abs(v) for v in values)
    return f"mean {sum(values) / len(values):+.3f}  p95|x| {a[int(0.95 * len(a))]:.3f}  max|x| {a[-1]:.3f}"


def main(path):
    rows = json.load(open(path))
    d_illum, d_dist, d_pos = [], [], []
    for row in rows[::7]:
        t = datetime.datetime.strptime(row["time"], "%d %b %Y %H:%M UT")
        jd = eph.jd(t.year, t.month, t.day, t.hour + t.minute / 60)
        _, _, sun_lon = eph.sun(jd)
        _, _, moon_lon, moon_lat, moon_r = eph.moon(jd)
        elong = math.acos(math.cos(math.radians(sun_lon - moon_lon)) * math.cos(math.radians(moon_lat)))
        d_illum.append((1 + math.cos(math.pi - elong)) / 2 * 100 - row["phase"])
        d_dist.append(moon_r * EARTH_RADIUS_KM - row["distance"])
        # SVS J2000 RA/Dec -> ecliptic J2000 -> of date (IAU 1976 general precession in longitude).
        a = math.radians(row["j2000"]["ra"] * 15)
        d = math.radians(row["j2000"]["dec"])
        e = OBLIQUITY_J2000
        lam = math.atan2(math.sin(a) * math.cos(e) + math.tan(d) * math.sin(e), math.cos(a))
        beta = math.asin(math.sin(d) * math.cos(e) - math.cos(d) * math.sin(e) * math.sin(a))
        lam += math.radians(5029.0966 * (jd - 2451545) / 36525 / 3600)
        c = math.sin(math.radians(moon_lat)) * math.sin(beta) \
            + math.cos(math.radians(moon_lat)) * math.cos(beta) * math.cos(math.radians(moon_lon) - lam)
        d_pos.append(math.degrees(math.acos(min(1.0, c))) * 60)
    print(f"samples {len(d_illum)}")
    print(f"illuminated percentage points (game - SVS): {stats(d_illum)}")
    print(f"distance km (game - SVS):                   {stats(d_dist)}")
    s = sorted(d_pos)
    print(f"position residual arcmin: median {s[len(s) // 2]:.2f}  p95 {s[int(0.95 * len(s))]:.2f}  max {s[-1]:.2f}")


if __name__ == "__main__":
    main(sys.argv[1])
