#!/usr/bin/env python3
"""Check LU-11 material and twilight paired-capture evidence with Pillow."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageStat


SCHEMA_VERSION = 1
ENGINE_VERSION = "4.8-beta1 (official)"
ENGINE_HASH = "4d10419cacd6d3009976e8f9fd3abd970fd58018"
RENDERER = "gl_compatibility"
TWILIGHT_ROI = (910, 490, 1010, 590)  # left, top, right, bottom; right/bottom exclusive
REC709 = (0.2126, 0.7152, 0.0722)


def _load_report(root: Path, folder: str) -> dict[str, Any]:
    return json.loads((root / folder / "report.json").read_text(encoding="utf-8"))


def _load_image(root: Path, folder: str, filename: str) -> Image.Image:
    path = root / folder / filename
    with Image.open(path) as source:
        return source.convert("RGB").copy()


def _check(
    checks: list[dict[str, Any]],
    name: str,
    passed: bool,
    actual: Any,
    requirement: str,
) -> bool:
    checks.append(
        {
            "name": name,
            "passed": bool(passed),
            "actual": actual,
            "requirement": requirement,
        }
    )
    return bool(passed)


def _hist_percentile(histogram: list[int], percentile: float, total: int) -> int:
    target = max(1, math.ceil(total * percentile / 100.0))
    cumulative = 0
    for value, count in enumerate(histogram):
        cumulative += count
        if cumulative >= target:
            return value
    return 255


def _image_delta(reference: Image.Image, candidate: Image.Image) -> dict[str, Any]:
    if reference.size != candidate.size:
        raise ValueError(f"paired image sizes differ: {reference.size} vs {candidate.size}")

    difference = ImageChops.difference(reference, candidate)
    channel_means = ImageStat.Stat(difference).mean
    maximum = ImageChops.lighter(
        ImageChops.lighter(difference.getchannel("R"), difference.getchannel("G")),
        difference.getchannel("B"),
    )
    histogram = maximum.histogram()
    pixel_count = reference.width * reference.height

    def fraction_at_least(delta: int) -> float:
        return sum(histogram[delta:]) / pixel_count

    return {
        "width": reference.width,
        "height": reference.height,
        "mean_abs_rgb": sum(channel_means) / 3.0,
        "changed_fraction_max_channel_ge_1": fraction_at_least(1),
        "changed_fraction_max_channel_ge_8": fraction_at_least(8),
        "changed_fraction_max_channel_ge_2": fraction_at_least(2),
        "max_channel_delta_p95": _hist_percentile(histogram, 95.0, pixel_count),
        "max_channel_delta_max": max(i for i, count in enumerate(histogram) if count),
        "byte_identical": max(channel_means) == 0.0,
    }


def _report_summary(report: dict[str, Any]) -> dict[str, Any]:
    engine = report.get("engine") or {}
    return {
        "engine": engine.get("string"),
        "engine_hash": engine.get("hash"),
        "renderer": report.get("renderer"),
        "width": report.get("width"),
        "height": report.get("height"),
        "adapter": report.get("adapter"),
    }


def _case(report: dict[str, Any], name: str) -> dict[str, Any]:
    try:
        return report["cases"][name]
    except (KeyError, TypeError) as exc:
        raise ValueError(f"capture report lacks case {name!r}") from exc


def _check_capture_identity(
    checks: list[dict[str, Any]], label: str, report: dict[str, Any]
) -> None:
    summary = _report_summary(report)
    engine = summary["engine"] or ""
    _check(
        checks,
        f"{label}: pinned Godot engine",
        engine == ENGINE_VERSION and summary["engine_hash"] == ENGINE_HASH,
        engine,
        f"engine is {ENGINE_VERSION} at {ENGINE_HASH}",
    )
    _check(
        checks,
        f"{label}: Compatibility renderer",
        summary["renderer"] == RENDERER,
        summary["renderer"],
        RENDERER,
    )
    _check(
        checks,
        f"{label}: 1920x1080 capture",
        summary["width"] == 1920 and summary["height"] == 1080,
        [summary["width"], summary["height"]],
        [1920, 1080],
    )


def _check_reports_matched(
    checks: list[dict[str, Any]],
    label: str,
    before_report: dict[str, Any],
    after_report: dict[str, Any],
    case_names: tuple[str, ...],
    exposure_tolerance: float = 0.001,
) -> None:
    before_meta = _report_summary(before_report)
    after_meta = _report_summary(after_report)
    _check(
        checks,
        f"{label}: engine and renderer matched",
        before_meta["engine"] == after_meta["engine"]
        and before_meta["engine_hash"] == after_meta["engine_hash"]
        and before_meta["renderer"] == after_meta["renderer"],
        {"before": before_meta, "after": after_meta},
        "same engine string/hash and renderer",
    )
    _check(
        checks,
        f"{label}: report resolution matched",
        before_meta["width"] == after_meta["width"]
        and before_meta["height"] == after_meta["height"],
        {
            "before": [before_meta["width"], before_meta["height"]],
            "after": [after_meta["width"], after_meta["height"]],
        },
        "same report resolution",
    )

    for case_name in case_names:
        before_case = _case(before_report, case_name)
        after_case = _case(after_report, case_name)
        before_exposure = float(before_case["exposure"])
        after_exposure = float(after_case["exposure"])
        exposure_delta = abs(before_exposure - after_exposure)
        _check(
            checks,
            f"{label}: {case_name} exposure matched",
            exposure_delta <= exposure_tolerance,
            {
                "before": before_exposure,
                "after": after_exposure,
                "absolute_delta": exposure_delta,
            },
            f"absolute delta <= {exposure_tolerance:g}",
        )
        before_draws = float(before_case["draws"])
        after_draws = float(after_case["draws"])
        _check(
            checks,
            f"{label}: {case_name} draw count unchanged",
            before_draws == after_draws,
            {"before": before_draws, "after": after_draws},
            "exactly equal reported draw counts",
        )


def _check_day_materials(root: Path, checks: list[dict[str, Any]]) -> dict[str, Any]:
    after_report = _load_report(root, "after-day")
    flat_report = _load_report(root, "flat-day")
    _check_capture_identity(checks, "after-day", after_report)
    _check_capture_identity(checks, "flat-day", flat_report)
    case_names = ("gravel_close", "car_park", "gravel_far")
    _check_reports_matched(checks, "day material pair", flat_report, after_report, case_names)

    result: dict[str, Any] = {"reference": "flat-day", "candidate": "after-day", "cases": {}}
    for case_name in case_names:
        reference = _load_image(root, "flat-day", f"{case_name}.png")
        candidate = _load_image(root, "after-day", f"{case_name}.png")
        delta = _image_delta(reference, candidate)
        reference_case = _case(flat_report, case_name)
        candidate_case = _case(after_report, case_name)
        expected_size = (_report_summary(after_report)["width"], _report_summary(after_report)["height"])
        _check(
            checks,
            f"day material pair: {case_name} image/report size matched",
            (delta["width"], delta["height"]) == expected_size,
            {"image": [delta["width"], delta["height"]], "report": list(expected_size)},
            "image dimensions equal capture report dimensions",
        )

        case_checks: dict[str, Any] = {"image_delta": delta, "draws": {"flat_day": reference_case["draws"], "after_day": candidate_case["draws"]}}
        if case_name == "gravel_close":
            visible = (
                delta["mean_abs_rgb"] >= 1.0
                and delta["changed_fraction_max_channel_ge_8"] >= 0.10
            )
            criterion = "mean absolute RGB delta >= 1.0 and >=10% pixels have max-channel delta >=8"
        elif case_name == "car_park":
            visible = (
                delta["mean_abs_rgb"] >= 0.5
                and delta["changed_fraction_max_channel_ge_8"] >= 0.03
            )
            criterion = "mean absolute RGB delta >= 0.5 and >=3% pixels have max-channel delta >=8"
        else:
            visible = (
                delta["mean_abs_rgb"] <= 0.02
                and delta["changed_fraction_max_channel_ge_2"] <= 0.001
            )
            criterion = "mean absolute RGB delta <= 0.02 and <=0.1% pixels have max-channel delta >=2"
        passed = _check(
            checks,
            f"day material pair: {case_name} visual detail/attenuation",
            visible,
            delta,
            criterion,
        )
        case_checks["passed"] = passed
        result["cases"][case_name] = case_checks
    return result


def _contrast_against_background(
    foreground: Image.Image, background: Image.Image
) -> dict[str, Any]:
    if foreground.size != background.size:
        raise ValueError(
            f"aircraft/background image sizes differ: {foreground.size} vs {background.size}"
        )
    left, top, right, bottom = TWILIGHT_ROI
    if right > foreground.width or bottom > foreground.height:
        raise ValueError(f"fixed twilight ROI {TWILIGHT_ROI} falls outside {foreground.size}")

    foreground_roi = foreground.crop(TWILIGHT_ROI)
    background_roi = background.crop(TWILIGHT_ROI)
    fg_pixels = foreground_roi.load()
    bg_pixels = background_roi.load()
    contrast_values: list[float] = []
    for y in range(bottom - top):
        for x in range(right - left):
            fg = fg_pixels[x, y]
            bg = bg_pixels[x, y]
            rgb_max_delta = max(abs(fg[channel] - bg[channel]) for channel in range(3))
            if rgb_max_delta >= 8:
                encoded_luma_delta = (
                    REC709[0] * (fg[0] - bg[0])
                    + REC709[1] * (fg[1] - bg[1])
                    + REC709[2] * (fg[2] - bg[2])
                )
                contrast_values.append(abs(encoded_luma_delta))

    pixel_count = (right - left) * (bottom - top)
    mask_count = len(contrast_values)
    return {
        "roi_xyxy": list(TWILIGHT_ROI),
        "roi_pixel_count": pixel_count,
        "aircraft_mask_pixels": mask_count,
        "aircraft_mask_fraction": mask_count / pixel_count,
        "mean_abs_encoded_rec709_luma_contrast": (
            sum(contrast_values) / mask_count if mask_count else 0.0
        ),
    }


def _check_twilight(root: Path, checks: list[dict[str, Any]]) -> dict[str, Any]:
    before_report = _load_report(root, "before-aircraft")
    after_report = _load_report(root, "after-sunset")
    _check_capture_identity(checks, "before-aircraft", before_report)
    _check_capture_identity(checks, "after-sunset", after_report)

    before_foreground = _load_image(root, "before-aircraft", "twilight_aircraft.png")
    before_background = _load_image(root, "before-aircraft", "twilight_background.png")
    after_foreground = _load_image(root, "after-sunset", "twilight_aircraft.png")
    after_background = _load_image(root, "after-sunset", "twilight_background.png")
    before_contrast = _contrast_against_background(before_foreground, before_background)
    after_contrast = _contrast_against_background(after_foreground, after_background)
    for folder, foreground, background, report in (
        ("before-aircraft", before_foreground, before_background, before_report),
        ("after-sunset", after_foreground, after_background, after_report),
    ):
        expected_size = (_report_summary(report)["width"], _report_summary(report)["height"])
        _check(
            checks,
            f"{folder}: image/report size matched",
            foreground.size == expected_size and background.size == expected_size,
            {
                "aircraft": list(foreground.size),
                "background": list(background.size),
                "report": list(expected_size),
            },
            "both images match capture report dimensions",
        )

    _check_reports_matched(
        checks,
        "twilight aircraft/background exposure",
        before_report,
        after_report,
        ("twilight_aircraft", "twilight_background"),
    )
    for folder, report in (("before-aircraft", before_report), ("after-sunset", after_report)):
        aircraft_case = _case(report, "twilight_aircraft")
        background_case = _case(report, "twilight_background")
        exposure_delta = abs(float(aircraft_case["exposure"]) - float(background_case["exposure"]))
        _check(
            checks,
            f"{folder}: aircraft and background exposure matched",
            exposure_delta <= 0.001,
            {
                "aircraft": aircraft_case["exposure"],
                "background": background_case["exposure"],
                "absolute_delta": exposure_delta,
            },
            "absolute delta <= 0.001",
        )
    for folder, contrast in (("before-aircraft", before_contrast), ("after-sunset", after_contrast)):
        _check(
            checks,
            f"{folder}: aircraft mask isolates silhouette",
            40 <= contrast["aircraft_mask_pixels"] <= 200,
            contrast["aircraft_mask_pixels"],
            "40..200 ROI pixels pass max-channel RGB delta >=8 (not a sky-wide mask)",
        )

    before_value = before_contrast["mean_abs_encoded_rec709_luma_contrast"]
    after_value = after_contrast["mean_abs_encoded_rec709_luma_contrast"]
    ratio = after_value / before_value if before_value > 0.0 else 0.0
    _check(
        checks,
        "twilight: after sunset retains aircraft contrast",
        before_value > 0.0 and ratio >= 0.95,
        {"before": before_value, "after": after_value, "after_over_before": ratio},
        "mean absolute encoded Rec.709 luma contrast after / before >= 0.95",
    )

    return {
        "before_aircraft": before_contrast,
        "after_sunset": after_contrast,
        "contrast_ratio_after_over_before": ratio,
        "exposures": {
            "before_aircraft": {
                "twilight_aircraft": _case(before_report, "twilight_aircraft")["exposure"],
                "twilight_background": _case(before_report, "twilight_background")["exposure"],
            },
            "after_sunset": {
                "twilight_aircraft": _case(after_report, "twilight_aircraft")["exposure"],
                "twilight_background": _case(after_report, "twilight_background")["exposure"],
            },
        },
        "draws": {
            folder: {
                "twilight_aircraft": _case(report, "twilight_aircraft")["draws"],
                "twilight_background": _case(report, "twilight_background")["draws"],
            }
            for folder, report in (("before-aircraft", before_report), ("after-sunset", after_report))
        },
    }


def verify(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    result: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "evidence_root": str(root),
        "result": "fail",
        "checks": checks,
    }
    try:
        result["day_materials"] = _check_day_materials(root, checks)
        result["twilight"] = _check_twilight(root, checks)
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        result["input_error"] = f"{type(exc).__name__}: {exc}"
        checks.append(
            {
                "name": "evidence inputs readable and complete",
                "passed": False,
                "actual": result["input_error"],
                "requirement": "all required images and report fields exist",
            }
        )
    result["result"] = "pass" if all(check["passed"] for check in checks) else "fail"
    result["check_count"] = len(checks)
    result["failed_check_count"] = sum(not check["passed"] for check in checks)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(".tools/landscape-lu11"),
        help="capture evidence root containing after-day, flat-day, before-aircraft, and after-sunset",
    )
    args = parser.parse_args()
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    result = verify(root)
    report_path = root / "materials-checks.json"
    report_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        f"materials check: {result['result']} "
        f"({result['check_count']} checks, {result['failed_check_count']} failed); {report_path}"
    )
    if result["result"] != "pass":
        for check in result["checks"]:
            if not check["passed"]:
                print(f"FAIL: {check['name']}: {check['actual']} ({check['requirement']})", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
