# FW-MOON-06: discontinuities in light_audit.gd's CSVs (one row per 30 s sky step).
# Usage: python3 -I research/field-world/fw-moon-06/analyze_audit.py OUT_DIR
# Reports, per scenario: every change of light source (direction jump, direct and ambient light, shadows), the largest
# step-to-step jumps of the light direction, of the displayed direct light on the ground (exposure x horizontal direct
# illuminance) relative to the displayed ambient, of the shadow strength, and the steps where engine shadows would
# switch on or off.
import csv
import glob
import math
import os
import sys


def ang(az1, el1, az2, el2):
    a1, e1, a2, e2 = map(math.radians, (az1, el1, az2, el2))
    c = math.sin(e1) * math.sin(e2) + math.cos(e1) * math.cos(e2) * math.cos(a1 - a2)
    return math.degrees(math.acos(max(-1.0, min(1.0, c))))


def main(out):
    for path in sorted(glob.glob(os.path.join(out, "*.csv"))):
        rows = list(csv.DictReader(open(path)))
        for r in rows:
            for k, v in r.items():
                if k not in ("light_source", "lobe_source"):
                    r[k] = float(v)
        name = os.path.basename(path)[:-4]
        print("\n## %s (%d steps)\n" % (name, len(rows) - 1))
        print("| t (min) | sun el | moon el | illum | change | light dir jump | direct/ambient before → after | shadow before → after | lobe |")
        print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
        worst = {"dir": (0, None), "direct": (0, None), "shadow": (0, None), "key": (0, None)}
        for a, b in zip(rows, rows[1:]):
            jump = ang(a["light_az"], a["light_el"], b["light_az"], b["light_el"])
            ra = a["direct_h_lum"] / max(a["ambient_lum"], 1e-30)
            rb = b["direct_h_lum"] / max(b["ambient_lum"], 1e-30)
            # Displayed brightness of a horizontal lit surface (direct + ambient) x exposure, step to step.
            ka = a["exposure"] * (a["direct_h_lum"] + a["ambient_lum"])
            kb = b["exposure"] * (b["direct_h_lum"] + b["ambient_lum"])
            dkey = abs(math.log(kb / ka)) if ka > 0 and kb > 0 else 0.0
            ddirect = abs(rb - ra)
            dshadow = abs(b["shadow"] - a["shadow"])
            for k, v in (("dir", jump), ("direct", ddirect), ("shadow", dshadow), ("key", dkey)):
                if v > worst[k][0]:
                    worst[k] = (v, b)
            if a["light_source"] != b["light_source"] or a["lobe_source"] != b["lobe_source"]:
                print("| %.1f | %.2f° | %.2f° | %.3f | light %s → %s | %.1f° | %.4f → %.4f | %.2f → %.2f | %s → %s |" % (
                    b["t_min"], b["sun_el"], b["moon_el"], b["illum"], a["light_source"], b["light_source"], jump, ra, rb,
                    a["shadow"], b["shadow"], a["lobe_source"], b["lobe_source"]))
        print()
        for k, label in (("dir", "light direction jump (deg)"), ("direct", "change of direct/ambient on the ground"),
                         ("shadow", "shadow strength change"), ("key", "|ln| change of displayed lit-ground brightness")):
            v, r = worst[k]
            if r is not None:
                print("- largest %s: %.4f at t = %.1f min (sun %.2f°, moon %.2f°, light %s)" % (
                    label, v, r["t_min"], r["sun_el"], r["moon_el"], r["light_source"]))
        on = [r for a, r in zip(rows, rows[1:]) if (a["shadow"] > 0) != (r["shadow"] > 0)]
        for r in on:
            print("- engine shadows would switch %s at t = %.1f min (sun %.2f°, moon %.2f°): flow steps do not apply it" % (
                "on" if r["shadow"] > 0 else "off", r["t_min"], r["sun_el"], r["moon_el"]))


if __name__ == "__main__":
    main(sys.argv[1])
