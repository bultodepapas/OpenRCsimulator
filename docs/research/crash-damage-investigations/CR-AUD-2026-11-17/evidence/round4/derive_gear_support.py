#!/usr/bin/env python3
"""Derive a terrain projection from the retained gear run; no engine is launched.

This is a check of the recorded fixture, not finite-wheel collision geometry.
The point is inside the default runway, beyond its amplitude blending edges.
Print JSON to stdout; redirect to a fresh temporary file when reproducing.
"""
from __future__ import annotations

import ast
import hashlib
import json
import math
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[5]


def main() -> None:
    observed = HERE / "runs/probes/fixedwing-gear-scenery/observations.json"
    terrain_path = ROOT / "app/physics/ground_terrain.gd"
    terrain = terrain_path.read_text()
    match = re.search(r"const WAVES := (\[.*?\n\])", terrain, re.S)
    assert match is not None
    waves = ast.literal_eval(match.group(1))
    amplitude_match = re.search(r"const RELIEF_RUNWAY_M := ([0-9.]+)", terrain)
    assert amplitude_match is not None
    amplitude = float(amplitude_match.group(1))
    o = json.loads(observed.read_text())
    case = next(c for c in o["cases"] if c["name"] == "gear_box")
    row = next(r for r in case["history"] if r["tick"] == 24)
    n, e, d = row["wheel_point"]
    # Default-field runway bounds: default.json, runway rectangle. This assertion
    # admits the constant runway amplitude, not an approximation across a seam.
    assert 9.0 + 0.5 < n < 21.0 - 0.5 and -50.0 + 0.5 < e < 50.0 - 0.5
    height = slope_n = slope_e = 0.0
    for weight, wavelength, direction_n, direction_e, phase0 in waves:
        phase = math.tau * (direction_n * n + direction_e * e) / wavelength + phase0
        height += amplitude * weight * math.sin(phase)
        scale = amplitude * weight * math.tau / wavelength * math.cos(phase)
        slope_n += scale * direction_n
        slope_e += scale * direction_e
    norm = math.sqrt(1.0 + slope_n * slope_n + slope_e * slope_e)
    derived_compression = (d + height) / norm
    recorded_compression = row["compressions"][o["gear_contact_index"]]
    assert abs(derived_compression - recorded_compression) < 1.0e-12
    projection = [n, e, -height]
    box = o["gear_box"]
    dn, de = n - box["north"], e - box["east"]
    local = [-dn * box["sin_heading"] + de * box["cos_heading"],
             -height - box["down"],
             -dn * box["cos_heading"] - de * box["sin_heading"]]
    gap = max(abs(local[0]) - box["half_x"],
              abs(local[1]) - box["half_down"],
              abs(local[2]) - box["half_z"])
    assert gap < 0.0
    sources = [terrain_path, ROOT / "app/physics/ground_wheels.gd",
               ROOT / "app/sim/scenery_collision.gd", ROOT / "app/data/fields/default.json",
               ROOT / "app/physics/ground_surfaces.gd",
               ROOT / "app/data/ground/surface_friction.json"]
    result = {
        "classification": "derived_postprocessing_of_retained_run",
        "scope": "Vertical terrain projection of nominal undeformed nose support point; no finite wheel or new engine test",
        "tick": row["tick"], "nominal_point_ned_m": [n, e, d],
        "runway_amplitude_m": amplitude, "terrain_height_up_m": height,
        "terrain_up_slopes": [slope_n, slope_e],
        "recorded_compression_m": recorded_compression,
        "derived_compression_m": derived_compression,
        "compression_absolute_error_m": abs(derived_compression - recorded_compression),
        "vertical_projection_ned_m": projection, "projection_box_local_m": local,
        "projection_box_linf_gap_m": gap,
        "box_top_above_datum_m": box["half_down"] - box["down"],
        "box_top_above_local_terrain_m": box["half_down"] - box["down"] - height,
        "observations_sha256": hashlib.sha256(observed.read_bytes()).hexdigest(),
        "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sources},
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
