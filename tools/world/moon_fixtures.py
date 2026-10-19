#!/usr/bin/env python3
"""FW-MOON-02 (docs/plans/moon.md): reference data the moon tests compare against.

Writes app/tests/fixtures/moon_reference_v1.json ("openrc-moon-reference v1") from:
  * NASA SVS 5587 "Moon Phase and Libration, 2026" (mooninfo_2026.json, geocentric, hourly): every 73rd hour, 120 rows.
    The file is read locally (download it from SVS_URL into references/moon/svs/); its SHA-256 is checked.
  * JPL Horizons API (DE441), queried now: topocentric refracted azimuth/elevation, illuminated fraction, angular
    diameter, sub-observer point, north-pole position angle, range and phase angle at Madrid, Buenos Aires and Tromso,
    plus rise/transit/set (TVH: refracted upper limb on the apparent horizon) at Madrid and Buenos Aires.
  * Espenak's lunar eclipse catalogue (umbral magnitude and time of greatest eclipse, TD) and phase catalogue, typed in
    from the cited pages.
Stdlib only. The epochs were chosen so the moon stands 12-55 deg (or 2-4 deg, for refraction) above each site.
  python3 tools/world/moon_fixtures.py [--svs references/moon/svs/mooninfo_2026.json]
Re-running changes Horizons digits only if JPL updates its Earth-orientation data; the retrieval date is recorded.
"""
import argparse
import datetime
import hashlib
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "app" / "tests" / "fixtures" / "moon_reference_v1.json"
SVS_URL = "https://svs.gsfc.nasa.gov/vis/a000000/a005500/a005587/mooninfo_2026.json"
SVS_SHA256 = "098ec6434ba4fecb84e66485385816d465b7969f142864bcfc9ffc68311b4a86"
SVS_STEP_HOURS = 73
HORIZONS = "https://ssd.jpl.nasa.gov/api/horizons.api"

SITES = {
    "madrid": {"latitude_deg": 40.4168, "longitude_deg": -3.7038, "epochs_jd_ut": [
        2461045.6875, 2461150.8542, 2461246.2396, 2461322.7604, 2461420.0, 2461527.6771, 2461647.7188, 2461809.5208,
        2461937.5521, 2462096.0208, 2461310.77083, 2461486.73264]},
    "buenos_aires": {"latitude_deg": -34.6037, "longitude_deg": -58.3816, "epochs_jd_ut": [
        2461045.5833, 2461151.1562, 2461245.5938, 2461322.9062, 2461419.5, 2461527.8229, 2461647.9479, 2461809.5,
        2461937.7188, 2462095.5, 2461310.89236, 2461486.90278]},
    "tromso": {"latitude_deg": 69.6492, "longitude_deg": 18.9553, "epochs_jd_ut": [
        2461045.5, 2461150.6979, 2461322.7812, 2461419.9583, 2461527.6875, 2461647.625, 2461809.5, 2461937.5417,
        2461310.72222, 2461486.63889]},
}
RTS = {"madrid": ("2026-03-02", "2026-03-05"), "buenos_aires": ("2026-08-27", "2026-08-30")}

ECLIPSES_URL = "https://eclipse.gsfc.nasa.gov/LEdecade/LEdecade2021.html"
# [date, greatest eclipse TD (h, m, s), type, umbral magnitude (None: penumbral only)]
ECLIPSES = [
    ["2026-03-03", [11, 34, 52], "total", 1.151],
    ["2026-08-28", [4, 14, 4], "partial", 0.930],
    ["2027-02-20", [23, 14, 6], "penumbral", None],
    ["2028-01-12", [4, 14, 13], "partial", 0.066],
    ["2028-07-06", [18, 20, 57], "partial", 0.389],
    ["2028-12-31", [16, 53, 15], "total", 1.246],
]
DELTA_T_S = 69.0  # TD - UT, 2026-2028 (estimate; Espenak's tables use ~70 s)
PHASES_URL = "https://www.astropixels.com/ephemeris/phasescat/phases2001.html"
PHASES_UT = {
    "full": ["2026-01-03T10:03", "2026-02-01T22:09", "2026-03-03T11:38", "2026-05-31T08:45", "2026-08-28T04:18",
             "2026-11-24T14:53", "2026-12-24T01:28"],
    "new": ["2026-01-18T19:52", "2026-02-17T12:01", "2026-08-12T17:37", "2026-10-10T15:50"],
}


def horizons(params):
    query = {"format": "json", "COMMAND": "'301'", "OBJ_DATA": "'NO'", "MAKE_EPHEM": "'YES'",
             "EPHEM_TYPE": "'OBSERVER'", "CENTER": "'coord@399'", "COORD_TYPE": "'GEODETIC'", "TIME_TYPE": "'UT'",
             "ANG_FORMAT": "'DEG'", "CSV_FORMAT": "'YES'", "EXTRA_PREC": "'YES'", "APPARENT": "'REFRACTED'",
             "RANGE_UNITS": "'KM'"}
    query.update(params)
    url = HORIZONS + "?" + urllib.parse.urlencode(query)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                result = json.load(r)["result"]
            break
        except OSError:
            if attempt == 2:
                raise
            time.sleep(5)
    if "$$SOE" not in result:
        raise RuntimeError("Horizons returned no ephemeris:\n" + result[:2000])
    body = result.split("$$SOE")[1].split("$$EOE")[0]
    rows = [[c.strip() for c in line.split(",")] for line in body.strip().splitlines()]
    return url, rows


def jd_of(utc):
    """Julian Day of a datetime (UT), via the Unix epoch (JD 2440587.5)."""
    return 2440587.5 + (utc - datetime.datetime(1970, 1, 1)).total_seconds() / 86400.0


def observer_rows(site):
    s = SITES[site]
    epochs = sorted(s["epochs_jd_ut"])  # Horizons returns a TLIST in time order
    url, rows = horizons({
        "SITE_COORD": "'%.4f,%.4f,0'" % (s["longitude_deg"], s["latitude_deg"]),
        "TLIST": " ".join("'%s'" % jd for jd in epochs), "TLIST_TYPE": "'JD'",
        "QUANTITIES": "'4,10,13,14,17,20,24'"})
    if len(rows) != len(epochs):
        raise RuntimeError("%s: %d rows for %d epochs" % (site, len(rows), len(epochs)))
    out = []
    for jd, c in zip(epochs, rows):
        row_jd = jd_of(datetime.datetime.strptime(c[0], "%Y-%b-%d %H:%M:%S.%f"))
        if abs(row_jd - jd) * 86400.0 > 1.0:
            raise RuntimeError("%s: row time %s does not match JD %s" % (site, c[0], jd))
        # date, solar flag, lunar flag, az, el, illum%, ang-diam ", sub-lon, sub-lat, NP.ang, NP.dist, delta km, deldot, S-T-O
        out.append({"jd_ut": jd, "azimuth_deg": float(c[3]), "elevation_deg": float(c[4]),
                    "illuminated": float(c[5]) / 100.0, "diameter_arcsec": float(c[6]),
                    "sub_observer_lon_deg": float(c[7]), "sub_observer_lat_deg": float(c[8]),
                    "north_pole_angle_deg": float(c[9]), "distance_km": float(c[11]), "phase_angle_deg": float(c[13])})
    return url, out


def rts_rows(site):
    s = SITES[site]
    start, stop = RTS[site]
    url, rows = horizons({
        "SITE_COORD": "'%.4f,%.4f,0'" % (s["longitude_deg"], s["latitude_deg"]),
        "START_TIME": "'%s'" % start, "STOP_TIME": "'%s'" % stop, "STEP_SIZE": "'1 m'",
        "R_T_S_ONLY": "'TVH'", "QUANTITIES": "'4'"})
    out = []
    for c in rows:
        when = datetime.datetime.strptime(c[0], "%Y-%b-%d %H:%M")
        kind = {"r": "rise", "t": "transit", "s": "set"}.get(c[2][-1:] if c[2] else "", "")
        if kind:
            out.append({"utc": when.strftime("%Y-%m-%dT%H:%M"), "event": kind, "azimuth_deg": float(c[3]),
                        "elevation_deg": float(c[4])})
    return url, out


def svs_rows(path):
    data = Path(path).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != SVS_SHA256:
        sys.exit("unexpected %s sha256 %s (want %s); download it from %s" % (path, digest, SVS_SHA256, SVS_URL))
    rows = json.loads(data)
    out = []
    for r in rows[::SVS_STEP_HOURS]:
        t = datetime.datetime.strptime(r["time"], "%d %b %Y %H:%M UT")
        out.append({"utc": t.strftime("%Y-%m-%dT%H:%M"), "illuminated": r["phase"] / 100.0,
                    "diameter_arcsec": r["diameter"], "distance_km": r["distance"],
                    "sub_earth_lon_deg": r["subearth"]["lon"], "sub_earth_lat_deg": r["subearth"]["lat"],
                    "sub_solar_lon_deg": r["subsolar"]["lon"], "sub_solar_lat_deg": r["subsolar"]["lat"],
                    "axis_angle_j2000_deg": r["posangle"]})
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--svs", default=str(ROOT / "references" / "moon" / "svs" / "mooninfo_2026.json"))
    args = parser.parse_args()
    fixture = {
        "format": "openrc-moon-reference v1",
        "generator": "tools/world/moon_fixtures.py",
        "retrieved": datetime.date.today().isoformat(),
        "svs": {"source": SVS_URL, "sha256": SVS_SHA256, "credit": "NASA's Scientific Visualization Studio (SVS 5587)",
                "frame": "geocentric; sub-Earth/sub-solar east longitude; axis angle from J2000 celestial north",
                "step_hours": SVS_STEP_HOURS, "rows": svs_rows(args.svs)},
        "horizons": {"credit": "JPL Horizons On-Line Ephemeris System (DE441)", "sites": {}},
        "eclipses": {"source": ECLIPSES_URL, "delta_t_s": DELTA_T_S, "time_scale": "TD", "rows": ECLIPSES},
        "phases": {"source": PHASES_URL, "time_scale": "UT", "rows": PHASES_UT},
    }
    for site in SITES:
        url, rows = observer_rows(site)
        entry = dict(SITES[site])
        entry.pop("epochs_jd_ut")
        entry.update({"query": url, "observer": rows})
        if site in RTS:
            rts_url, events = rts_rows(site)
            entry.update({"rts_query": rts_url, "rts": events})
        fixture["horizons"]["sites"][site] = entry
    OUT.write_text(json.dumps(fixture, indent=1) + "\n")
    print("wrote %s: %d SVS rows, %s" % (OUT.relative_to(ROOT), len(fixture["svs"]["rows"]),
          ", ".join("%s %d+%d" % (k, len(v["observer"]), len(v.get("rts", [])))
                    for k, v in fixture["horizons"]["sites"].items())))


if __name__ == "__main__":
    main()
