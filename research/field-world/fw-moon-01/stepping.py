# FW-MOON-01: how far the moon jumps per FLOW_STEP_SKY_S (30 s of sky time, app/render/world/world.gd) and how many
# pixels that is in the game's cameras. Uses the FW-MOON-00 Python port of app/render/world/ephemeris.gd.
# Usage: python3 -I research/field-world/fw-moon-01/stepping.py
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fw-moon-00"))
from ephemeris_port import sky  # noqa: E402

STEP_S = 30.0                      # world.gd FLOW_STEP_SKY_S
SIDEREAL_DEG_H = 15.041069         # Earth rotation relative to the stars
MOON_SIDEREAL_DEG_DAY = (11.8, 13.176, 15.4)  # min / mean / max eastward motion along its orbit (eccentricity)
H_PX = 1080.0                      # viewport height
SPEC_FOV = 50.0                    # spec.gd CAMERA.fov_deg (pilot base, close-up/inspect view)
AUTO = {"target_px": 30.0, "min_fov": 6.0}  # spec.gd AUTO_ZOOM
PILOT_FOV_MIN = 1.0                # camera_rig.gd PILOT_FOV_MIN (manual zoom 0.125 on top of auto-zoom)
STIK_SPAN = 1.524                  # data/aircraft/jensen_ugly_stik_60.json reference.wing_span
DISC_DEG = 0.52                    # sky.gdshader moon_radius × 2 (mean); the real disc is 0.49–0.56°


def px_per_deg(fov_deg, h=H_PX):
    return h / (2.0 * math.tan(math.radians(fov_deg) / 2.0)) * math.pi / 180.0  # at the image centre


def auto_fov(span, distance, h=H_PX):  # pilot_camera.gd auto_fov
    fov = math.degrees(2.0 * math.atan(span * h / (2.0 * distance * AUTO["target_px"])))
    return min(max(fov, AUTO["min_fov"]), SPEC_FOV)


def sep(az1, el1, az2, el2):
    a1, e1, a2, e2 = map(math.radians, (az1, el1, az2, el2))
    c = math.sin(e1) * math.sin(e2) + math.cos(e1) * math.cos(e2) * math.cos(a1 - a2)
    return math.degrees(math.acos(max(-1.0, min(1.0, c))))


def main():
    print("Diurnal motion of the moon along its daily circle (deg per 30 s step) = (15.041 - lunar RA rate) * cos(dec) / 120")
    for day_rate in MOON_SIDEREAL_DEG_DAY:
        ha_rate = SIDEREAL_DEG_H - day_rate / 24.0
        print("  lunar motion %.1f deg/day: hour-angle rate %.3f deg/h -> step %.4f deg at dec 0, %.4f deg at dec 28.6"
              % (day_rate, ha_rate, ha_rate * STEP_S / 3600.0, ha_rate * STEP_S / 3600.0 * math.cos(math.radians(28.6))))
    print("  (Earth rotation alone: %.4f deg; the plan's 0.125 deg ignores the lunar motion)" % (15.0 * STEP_S / 3600.0))

    print("\nGame ephemeris (Python port), separation between t and t + 30 s, Madrid reference place:")
    cases = [("Harvest Moon rise 2026-09-26 20:25 CEST", (2026, 9, 26, 20 + 25 / 60, 2.0)),
             ("Full moon 2026-10-25 21:00 CEST", (2026, 10, 25, 21.0, 2.0)),
             ("Near-perigee full moon 2026-12-23 19:40 CET", (2026, 12, 23, 19 + 40 / 60, 1.0)),
             ("Current preset 2026-06-29 solar midnight", (2026, 6, 30, 1.25, 2.0))]
    steps = []
    for name, (y, mo, d, h, utc) in cases:
        a = sky(y, mo, d, h, utc)
        b = sky(y, mo, d, h + STEP_S / 3600.0, utc)
        s = sep(a["maz"], a["mel"], b["maz"], b["mel"])
        steps.append(s)
        print("  %-45s az %6.1f el %5.1f -> step %.4f deg (%.2f arcmin)" % (name, a["maz"], a["mel"], s, s * 60))
    step = max(steps)

    print("\nPixels at %d px viewport height (image centre), step = %.3f deg, disc = %.2f deg:" % (H_PX, step, DISC_DEG))
    print("| Camera | Vertical FOV | px/deg | Jump per step (px) | Disc (px) | Per-frame motion at ×20, 60 fps (px) |")
    print("| --- | --- | --- | --- | --- | --- |")
    rows = [("Pilot base / close-up (spec.gd)", SPEC_FOV), ("Chase (chase_view.gd)", 55.0), ("Orbit (orbit_view.gd)", 45.0)]
    for dist in (100.0, 200.0, 300.0):
        rows.append(("Pilot auto-zoom, Stik 60 at %d m" % dist, auto_fov(STIK_SPAN, dist)))
    rows += [("Pilot auto-zoom floor (spec.gd min_fov_deg)", AUTO["min_fov"]), ("Pilot narrowest (camera_rig.gd PILOT_FOV_MIN)", PILOT_FOV_MIN)]
    per_frame_deg = step * 20.0 / STEP_S / 60.0
    for name, fov in rows:
        k = px_per_deg(fov)
        print("| %s | %.1f° | %.1f | %.1f | %.0f | %.3f |" % (name, fov, k, step * k, DISC_DEG * k, per_frame_deg * k))
    print("\nStep cadence: ×20 -> one jump every %.1f s of flight; ×1 -> one jump every %.0f s." % (STEP_S / 20.0, STEP_S))
    print("Auto-zoom note: px/rad = 30 * distance / span, independent of the viewport height (pilot_camera.gd auto_fov).")


if __name__ == "__main__":
    main()
