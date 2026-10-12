"""LU-04: compare paired native rendered PNGs; dependency pinned in requirements.txt."""
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
        "aircraft_transit_reduces_glare": 0.0 <= results["aircraft"] < results["clear"] * 0.75,
        "off_axis_exact_zero": results["side"] == 0.0,
        "night_exact_zero": results["night"] == 0.0,
    }
    for name in ["cloud", "low_exposure", "aircraft_left", "aircraft_right"]:
        if (args.folder / f"glare_{name}.png").exists():
            results[name] = compare(args.folder, name, name + "_off")
    if "cloud" in results:
        checks["dense_cloud_reduces_glare"] = results["cloud"] < results["clear"] * 0.5
    if "low_exposure" in results:
        checks["lower_exposure_reduces_glare"] = results["low_exposure"] < results["clear"] * 0.8
    if "aircraft_left" in results and "aircraft_right" in results:
        checks["transit_recovers_on_both_sides"] = min(results["aircraft_left"], results["aircraft_right"]) > results["aircraft"] * 2.0
    if (args.folder / "glare_half.png").exists():
        results["half"] = compare(args.folder, "half", "off")
        checks["intensity_control_reduces_glare"] = 0.2 * results["clear"] < results["half"] < 0.8 * results["clear"]
    report = {"format": "openrc-glare-verification v1", "mean_rgb_difference_255": results,
              "checks": checks, "ok": all(checks.values()),
              "limits": "Matched controlled optical fixtures, not photometric calibration or pilot recognition."}
    (args.folder / "glare-checks.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if report["ok"] else 1)


if __name__ == "__main__":
    main()
