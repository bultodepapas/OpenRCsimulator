"""SUN-02/03: a model's displayed contrast near the sun, from four matched native captures per case.

app/tests/capture_landscape_upgrade.gd renders glare_offset_<deg> (pilot view centred on the aircraft 60 m away, <deg>
from the sun) and glare_crossing[_late] (the aircraft flown across the sun with the view following it, measured
0.67 s or 5 s after), each with suffixes _off (glare intensity 0), _hidden (aircraft removed) and _hidden_off. The
aircraft's pixels are where it differs from the hidden control without glare. Weber contrast (aircraft - background)
/ background over those pixels is measured in display luma (sRGB code values: the space the overlay blends in) and in
linear luminance, with and without glare; "retained" is their ratio. For the steady veil the model predicts
1 / (1 + r) from the strength and aureole coefficient the capture reports (render/sun/sun_optics.gd, mirrored here);
after a crossing the bleached patch should hide the aircraft and then let it return.

Run with the pinned visual environment from the repository root:
    "$(app/tests/visual-env.sh)" tools/landscape/glare_contrast.py <capture-folder>
Writes <capture-folder>/glare-contrast.json and exits 1 if a check fails.
"""
import argparse
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image

# render/sun/sun_optics.gd
AGE = 40.0
PIGMENT = 0.5
CUT_DEG = 45.0
AUREOLE_CORE_DEG = 0.27


def spread(theta_deg):
    t = min(max(theta_deg, 0.1), 100.0)
    age = 1.0 + (AGE / 62.5) ** 4
    return 10.0 / t ** 3 + (5.0 / t ** 2 + 0.1 * PIGMENT / t) * age + 0.0025 * PIGMENT


def aureole(theta_deg, coeff):
    if theta_deg >= 45.0 or coeff <= 0.0:
        return 0.0
    far = 10.0 ** (6.15 - theta_deg / 40.0)
    near = 6.2e7 / (theta_deg ** 2 + AUREOLE_CORE_DEG ** 2)
    return ((max(near, far) if theta_deg < 30.0 else far) - 10.0 ** (6.15 - 45.0 / 40.0)) * coeff


def predicted(theta_deg, e_over_b, coeff):
    """1 / (1 + r) for the steady veil; the capture's glare_strength is the sun's E/B (sr) with clouds and strength."""
    excess = 0.0 if theta_deg >= CUT_DEG else spread(theta_deg) - spread(CUT_DEG)
    return 1.0 / (1.0 + e_over_b * excess / (1.0 + e_over_b * aureole(theta_deg, coeff)))


def load(folder, name):
    return np.asarray(Image.open(folder / f"{name}.png").convert("RGB"), dtype=np.float64) / 255.0


def luma(rgb):
    return rgb @ np.array([0.2126, 0.7152, 0.0722])


def linear(rgb):
    return np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)


def contrast(plane, background, mask):
    p = plane[mask].mean()
    b = background[mask].mean()
    return (p - b) / b


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    report_path = args.folder / "report.json"
    cases = json.loads(report_path.read_text(encoding="utf-8")).get("cases", {}) if report_path.exists() else {}
    angles = sorted({float(m.group(1)) for p in args.folder.glob("glare_offset_*.png")
                     if (m := re.fullmatch(r"glare_offset_([0-9.]+)\.png", p.name))})
    rows = []
    crossings = {}
    for tag in [f"glare_offset_{a:g}" for a in angles] + ["glare_crossing", "glare_crossing_late"]:
        names = [tag, tag + "_off", tag + "_hidden", tag + "_hidden_off"]
        if not all((args.folder / f"{n}.png").exists() for n in names):
            continue
        on, off, hidden, hidden_off = (load(args.folder, n) for n in names)
        mask = np.abs(off - hidden_off).sum(axis=2) > 24.0 / 255.0
        if mask.sum() < 20:
            continue
        case = cases.get(tag, {})
        strength = float(case.get("glare_strength", 1.0))
        coeff = float(case.get("glare_aureole_coeff", 0.0))
        c_off = contrast(luma(off), luma(hidden_off), mask)
        c_on = contrast(luma(on), luma(hidden), mask)
        l_off = contrast(luma(linear(off)), luma(linear(hidden_off)), mask)
        l_on = contrast(luma(linear(on)), luma(linear(hidden)), mask)
        row = {"case": tag, "aircraft_pixels": int(mask.sum()), "glare_strength": strength, "aureole_coeff": coeff,
               "afterimage_dose": float(case.get("glare_afterimage", 0.0)),
               "contrast_without_display": c_off, "contrast_with_display": c_on,
               "retained_display": c_on / c_off, "retained_linear": l_on / l_off,
               "background_display": float(luma(hidden)[mask].mean())}
        if tag.startswith("glare_offset_"):
            row["angle_deg"] = float(tag.removeprefix("glare_offset_"))
            row["predicted_retained"] = predicted(row["angle_deg"], strength, coeff)
            rows.append(row)
        else:
            crossings[tag] = row
    retained = [r["retained_display"] for r in rows]
    checks = {
        "at_least_six_angles": len(rows) >= 6,
        "retained_grows_with_angle": all(b >= a - 0.02 for a, b in zip(retained, retained[1:])),
        "veil_follows_the_model": all(abs(r["retained_display"] - r["predicted_retained"]) < 0.1 for r in rows),
    }
    if "glare_crossing" in crossings:
        checks["crossing_hides_the_aircraft"] = crossings["glare_crossing"]["retained_display"] < 0.25
    if "glare_crossing" in crossings and "glare_crossing_late" in crossings:
        checks["aircraft_returns_as_the_eye_recovers"] = (crossings["glare_crossing_late"]["retained_display"]
                                                          > crossings["glare_crossing"]["retained_display"] + 0.15)
    checks = {name: bool(ok) for name, ok in checks.items()}
    out = {"format": "openrc-glare-contrast v1", "rows": rows, "crossings": crossings, "checks": checks,
           "ok": all(checks.values()),
           "limits": ("Display contrast of one model, attitude and distance against clear calibrated-day sky; "
                      "not photometric calibration or a pilot detection threshold.")}
    (args.folder / "glare-contrast.json").write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(f"{'deg':>5} {'px':>5} {'C off':>7} {'C on':>7} {'kept':>6} {'lin':>6} {'model':>6}")
    for r in rows:
        print(f"{r['angle_deg']:5g} {r['aircraft_pixels']:5d} {r['contrast_without_display']:7.3f} "
              f"{r['contrast_with_display']:7.3f} {r['retained_display']:6.3f} {r['retained_linear']:6.3f} "
              f"{r['predicted_retained']:6.3f}")
    for tag, r in crossings.items():
        print(f"{tag}: kept {r['retained_display']:.3f} (linear {r['retained_linear']:.3f}), dose {r['afterimage_dose']:.3f}")
    print(json.dumps(checks, indent=2))
    raise SystemExit(0 if out["ok"] else 1)


if __name__ == "__main__":
    main()
