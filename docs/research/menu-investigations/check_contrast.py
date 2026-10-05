"""Reproduce contrast-check.json; stdlib only, proposed opaque sRGB colors.

Run from any directory: python3 path/to/check_contrast.py
Writes beside this script. No Godot resources or user settings are changed.
"""

import json
from pathlib import Path


PALETTE = {
    "panel": "#17252A",
    "text": "#F5F2E9",
    "secondary": "#BBC8C6",
    "accent": "#B6322E",
    "focus": "#F5C65D",
}


def luminance(color):
    rgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
    return sum(c * w for c, w in zip(linear, (0.2126, 0.7152, 0.0722)))


def main():
    pairs = [
        ("text", "panel", 4.5),
        ("secondary", "panel", 4.5),
        ("text", "accent", 4.5),
        ("focus", "panel", 3.0),
        ("accent", "panel", 3.0),
        ("focus", "accent", 3.0),
    ]
    rows = []
    for foreground, background, target in pairs:
        low, high = sorted([luminance(PALETTE[foreground]), luminance(PALETTE[background])])
        ratio = (high + 0.05) / (low + 0.05)
        rows.append({
            "foreground": foreground, "background": background,
            "contrast_ratio": ratio, "adopted_target": target,
            "passes_unrounded": ratio >= target,
        })
    result = {
        "date": "2026-10-05",
        "evidence_kind": "calculated",
        "method": "WCAG 2.x relative sRGB luminance; opaque flat colors; no rounding before comparison",
        "source": "https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html",
        "palette": PALETTE,
        "pairs": rows,
        "limitations": [
            "Proposed palette, not rendered UI.",
            "Does not measure font shape, anti-aliasing, color vision, image backgrounds, focus geometry or usability.",
            "Thresholds adopted as design goals; no accessibility compliance claim.",
        ],
    }
    Path(__file__).with_name("contrast-check.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    for row in rows:
        print(f"{row['foreground']}/{row['background']}: {row['contrast_ratio']:.3f}:1; target met={row['passes_unrounded']}")


if __name__ == "__main__":
    main()
