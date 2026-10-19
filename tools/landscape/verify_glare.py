"""LU-04 / SUN-05: compare paired native rendered PNGs; dependency pinned in requirements.txt.

v2 (SUN plan, 2026-10-19) follows the sun optics in docs/plans/sun.md: the eye's veil scales with the sun's
illuminance over the sky behind the model, so a model covering only part of the disc does not remove it, and the
exposure only changes how the same veil is displayed. Occlusion, night, clouds, the intensity control and the
off-axis cut keep LU-04's bounds; the afterimage and lens cases are new. v1 results stay in LU-06's evidence.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageStat


def compare(folder, first, second):
    a = Image.open(folder / f"glare_{first}.png").convert("RGB")
    b = Image.open(folder / f"glare_{second}.png").convert("RGB")
    if a.size != b.size:
        raise ValueError("mismatched image dimensions")
    difference = ImageChops.difference(a, b)
    return sum(ImageStat.Stat(difference).mean) / 3.0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    results = {name: compare(args.folder, name, other) for name, other in [
        ("clear", "off"), ("blocked", "blocked_off"), ("partial", "partial_off"),
        ("aircraft", "aircraft_off"), ("side", "side_off"), ("night", "night_off")
    ]}
    checks = {
        "visible_clear_glare": results["clear"] > 0.3,
        "full_occlusion_exact_zero": results["blocked"] == 0.0,
        "partial_occlusion_reduces_glare": 0.0 < results["partial"] < results["clear"] * 0.75,
        # A model in front of the sun covers part of the disc: what remains still veils the view (SUN-02).
        "aircraft_transit_keeps_a_veil": results["clear"] * 0.2 < results["aircraft"] < results["clear"],
        "off_axis_exact_zero": results["side"] == 0.0,
        "night_exact_zero": results["night"] == 0.0,
    }
    for name in ["cloud", "low_exposure", "aircraft_left", "aircraft_right", "afterimage", "lens"]:
        if (args.folder / f"glare_{name}.png").exists() and (args.folder / f"glare_{name}_off.png").exists():
            results[name] = compare(args.folder, name, name + "_off")
    if "cloud" in results:
        checks["dense_cloud_hides_glare"] = results["cloud"] < results["clear"] * 0.05
    if "low_exposure" in results:
        # The veil ratio does not depend on the exposure; a darker display shows it darker, never brighter.
        checks["lower_exposure_still_veils"] = 0.0 < results["low_exposure"] <= results["clear"]
    if "aircraft_left" in results and "aircraft_right" in results:
        checks["transit_recovers_on_both_sides"] = min(results["aircraft_left"], results["aircraft_right"]) > results["aircraft"]
    if (args.folder / "glare_half.png").exists():
        results["half"] = compare(args.folder, "half", "off")
        checks["intensity_control_reduces_glare"] = 0.2 * results["clear"] < results["half"] < 0.8 * results["clear"]
    if "afterimage" in results:
        checks["afterimage_drawn_after_looking_away"] = results["afterimage"] > 0.2
    if "lens" in results:
        checks["lens_optics_drawn"] = results["lens"] > 0.3
    report = {"format": "openrc-glare-verification v2", "mean_rgb_difference_255": results,
              "checks": checks, "ok": all(checks.values()),
              "limits": "Matched controlled optical fixtures, not photometric calibration or pilot recognition."}
    (args.folder / "glare-checks.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if report["ok"] else 1)


if __name__ == "__main__":
    main()
