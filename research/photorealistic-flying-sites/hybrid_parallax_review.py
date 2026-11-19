#!/usr/bin/env python3
"""Reproduce the hybrid scenery planning calculation; no renderer or asset access.

Run from the repository root:
  python3 research/photorealistic-flying-sites/hybrid_parallax_review.py

An initially centered feature is at forward depth D. The camera translates T
perpendicular to its unchanged optical axis. A direction-only panorama keeps
the feature centered; actual geometry moves by focal_pixels * T / D. This is
an ideal pinhole calculation with square pixels, not a general view-motion,
occlusion, calibration, stereo or Godot qualification.
"""

import json
import math

from optics_review import focal_pixels, rounded


def report():
    output_height_px = 1080
    translation_m = 0.25
    illustrative_limit_px = 2.0
    rows = []
    for fov in (120, 60, 30, 15, 6, 1):
        focal = focal_pixels(output_height_px, fov)
        minimum_depth = focal * translation_m / illustrative_limit_px
        # Algebraic consistency identity, not an independent projection oracle.
        angle = math.atan2(translation_m, minimum_depth)
        projected = focal * math.tan(angle)
        assert abs(projected - illustrative_limit_px) < 1e-12
        rows.append({
            "vertical_fov_deg": fov,
            "focal_pixels": rounded(focal),
            "minimum_forward_depth_for_2px_m": rounded(minimum_depth),
            "missing_parallax_at_1000m_px": rounded(focal * translation_m / 1000),
            "transverse_5cm_representation_error_at_100m_px": rounded(focal * 0.05 / 100),
        })

    # Sanity properties of the model, not implementation acceptance tests.
    assert all(a["minimum_forward_depth_for_2px_m"] < b["minimum_forward_depth_for_2px_m"]
               for a, b in zip(rows, rows[1:]))
    assert focal_pixels(2160, 60) == 2 * focal_pixels(1080, 60)

    return {
        "kind": "analytical planning receipt; no Godot execution",
        "date": "2026-11-19",
        "assumptions": {
            "output_height_px": output_height_px,
            "camera_transverse_translation_m": translation_m,
            "illustrative_screen_error_limit_px": illustrative_limit_px,
            "limit_status": "planning example, not a new release threshold",
            "projection": "ideal pinhole; centered feature; unchanged orientation; square pixels",
            "depth": "forward optical-axis depth, not general radial survey range",
            "background": "direction-only panorama with no translation response",
            "equations": ["f = H / (2 tan(v / 2))", "pixel_shift = f * T / D",
                          "D_min = f * T / pixel_limit"],
        },
        "rows": rows,
        "interpretation": [
            "The fixed-pilot proposal has zero eye translation; these are moving-view examples.",
            "Adding real foreground geometry does not remove missing parallax in the remaining panorama.",
            "A screen-error distance does not establish hidden surface content, depth ordering or physical coverage.",
            "For native Mac and other outputs, recompute using actual projection/output and inspect the final upscale.",
            "The 5cm example is an imposed transverse silhouette error, not a measured LOD error.",
            "General camera translation/rotation, off-axis points and disocclusion require full projection and scene evidence.",
        ],
    }


if __name__ == "__main__":
    print(json.dumps(report(), indent=2))
