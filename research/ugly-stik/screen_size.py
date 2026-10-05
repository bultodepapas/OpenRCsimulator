"""Investigation 10: analytical projection, not a renderer or a pilot study.

Run from any directory: python3 research/ugly-stik/screen_size.py
Outputs only this investigation's JSON/CSV evidence. Standard library only.
"""

import csv
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/research/ugly-stik-investigations/evidence"


def projected_segment(length, depth, angle_degrees, height=720, fov=50):
    """Pixel distance between endpoints; angle 0 lies in the image plane."""
    focal_pixels = height / (2 * math.tan(math.radians(fov) / 2))
    half_x = length * math.cos(math.radians(angle_degrees)) / 2
    half_z = length * math.sin(math.radians(angle_degrees)) / 2
    assert depth > abs(half_z)
    return focal_pixels * half_x * (1 / (depth - half_z) + 1 / (depth + half_z))


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    size = math.sqrt(dot(a, a))
    return tuple(x / size for x in a)


def scripted_wingtips():
    # Frozen values from Stage 0 SPEC. Independent of moving app code.
    time, speed, radius, gravity, span = 3.0, 15.0, 40.0, 9.80665, 1.524
    phase = time * speed / radius
    center = (60 + radius * math.cos(phase), radius * math.sin(phase), -20)
    eye = (0, 0, -1.7)
    yaw = phase + math.pi / 2
    roll = math.atan(speed**2 / (gravity * radius))
    right_body = (-math.sin(yaw) * math.cos(roll), math.cos(yaw) * math.cos(roll), math.sin(roll))
    offset = tuple(x - y for x, y in zip(center, eye))
    forward = unit(offset)
    camera_right = unit(cross(forward, (0, 0, -1)))
    camera_up = cross(camera_right, forward)
    focal_pixels = 720 / (2 * math.tan(math.radians(50) / 2))
    projected = []
    for sign in (-1, 1):
        relative = tuple(offset[i] + sign * span / 2 * right_body[i] for i in range(3))
        depth = dot(relative, forward)
        projected.append([focal_pixels * dot(relative, camera_right) / depth, focal_pixels * dot(relative, camera_up) / depth])
    distance = math.sqrt(dot(offset, offset))
    return {
        "time_s": time,
        "distance_to_center_m": distance,
        "wingtip_distance_px": math.dist(*projected),
        "broadside_span_at_same_distance_px": projected_segment(span, distance, 0),
        "scope": "wingtip line through model origin; no chord, fuselage, rasterization or antialiasing",
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for depth in (20, 50, 100):
        for height in (720, 1080):
            for angle in (0, 60, 80):
                rows.append({
                    "depth_m": depth,
                    "height_px": height,
                    "fov_vertical_deg": 50,
                    "span_angle_to_image_plane_deg": angle,
                    "span_px": projected_segment(1.524, depth, angle, height),
                    "patch_200mm_px": projected_segment(0.2, depth, angle, height),
                    "seam_2mm_px": projected_segment(0.002, depth, angle, height),
                })
    # Analytic invariants, not a claim of engine or human validation.
    assert math.isclose(projected_segment(1.524, 20, 0), 2 * projected_segment(1.524, 40, 0))
    assert math.isclose(projected_segment(1.524, 20, 0, 1080), 1.5 * projected_segment(1.524, 20, 0, 720))
    assert projected_segment(1.524, 20, 80) < projected_segment(1.524, 20, 60) < projected_segment(1.524, 20, 0)
    payload = {
        "evidence_kind": "analytical_experiment",
        "inputs": {"span_m": 1.524, "span_source": "Jensen printed 60 in; exact SI conversion", "patch_m": 0.2, "seam_m": 0.002, "feature_source": "chosen diagnostic sizes, not measured details"},
        "assumptions": ["pinhole projection", "square pixels", "zoom 1", "depth along camera axis", "centered segment", "no postprocessing"],
        "checks": "inverse distance at zero angle; linear resolution scaling; foreshortening: PASS",
        "rows": rows,
        "scripted_capture": scripted_wingtips(),
    }
    (OUT / "screen-size.json").write_text(json.dumps(payload, indent=2) + "\n")
    with (OUT / "screen-size.csv").open("w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps(payload["scripted_capture"], indent=2))


if __name__ == "__main__":
    main()
