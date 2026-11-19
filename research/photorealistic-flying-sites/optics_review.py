#!/usr/bin/env python3
"""Reproduce SC-PHOTO's 2026-11-19 analytical review; no Godot or asset access.

Run from the repository root:
  python3 research/photorealistic-flying-sites/optics_review.py

Stdout is deterministic for a fixed Python/math runtime. Across platforms use
declared numeric tolerances, not byte identity of libm's final floating bits.
These are ideal pinhole/spherical calculations and coordinate fixtures, not
measured renderer, calibration or memory results.
"""

import json
import math


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def unit(v):
    length = math.sqrt(dot(v, v))
    if length == 0:
        raise ValueError("The eye itself has no photographic direction")
    return tuple(x / length for x in v)


def mul(matrix, vector):
    return tuple(dot(row, vector) for row in matrix)


def transpose(matrix):
    return tuple(zip(*matrix))


def ned_to_render(v):
    n, e, d = v
    return e, -d, -n


def render_to_ned(v):
    x, y, z = v
    return -z, x, -y


def direction_to_uv(direction):
    n, e, d = unit(direction)
    u = (0.5 + math.atan2(e, n) / (2 * math.pi)) % 1.0
    v = 0.5 + math.asin(max(-1.0, min(1.0, d))) / math.pi
    return u, v


def uv_to_direction(uv):
    u, v = uv
    longitude = (u - 0.5) * 2 * math.pi
    latitude = (0.5 - v) * math.pi
    return (math.cos(latitude) * math.cos(longitude),
            math.cos(latitude) * math.sin(longitude), -math.sin(latitude))


def rotation(axis, angle_deg):
    x, y, z = unit(axis)
    c = math.cos(math.radians(angle_deg))
    s = math.sin(math.radians(angle_deg))
    k = 1 - c
    return ((c + x*x*k, x*y*k - z*s, x*z*k + y*s),
            (y*x*k + z*s, c + y*y*k, y*z*k - x*s),
            (z*x*k - y*s, z*y*k + x*s, c + z*z*k))


def focal_pixels(height, vertical_fov_deg):
    return height / (2 * math.tan(math.radians(vertical_fov_deg) / 2))


def rounded(value):
    return round(value, 9)


def report():
    cardinal = {"north": (1, 0, 0), "east": (0, 1, 0),
                "south": (-1, 0, 0), "west": (0, -1, 0),
                "up": (0, 0, -1), "down": (0, 0, 1)}
    expected = {"north": (.5, .5), "east": (.75, .5),
                "south": (0, .5), "west": (.25, .5),
                "up": (.5, 0), "down": (.5, 1)}
    for name, direction in cardinal.items():
        assert direction_to_uv(direction) == expected[name], name
        assert render_to_ned(ned_to_render(direction)) == direction, name

    # One nontrivial proper rotation exercises the declared matrix direction.
    orientation = rotation((1, 2, 3), 37)
    station = (12.0, -7.0, -1.65)
    directions = list(cardinal.values()) + [(-1, 1e-6, 0), (-1, -1e-6, 0),
                                          (2, 3, -4), (1, -7, 2)]
    max_error = 0.0
    for direction in directions:
        expected_direction = unit(direction)
        delta_ned = mul(transpose(orientation), expected_direction)
        point_ned = tuple(a + 30 * b for a, b in zip(station, delta_ned))
        relative_ned = tuple(a - b for a, b in zip(point_ned, station))
        recovered = uv_to_direction(direction_to_uv(mul(orientation, relative_ned)))
        error = math.sqrt(sum((a - b)**2 for a, b in zip(recovered, expected_direction)))
        max_error = max(max_error, error)
        assert error < 2e-12, (direction, error)
        assert render_to_ned(ned_to_render(point_ned)) == point_ned

    wide_fx = 1920 / (2 * math.tan(math.radians(90) / 2))
    angle4 = math.atan(4 / wide_fx)
    angle8 = math.atan(8 / wide_fx)
    zoom_rows = []
    for fov in (120, 75, 45, 30, 15, 6, 1):
        focal = focal_pixels(1080, fov)
        zoom_rows.append({
            "vertical_fov_deg": fov,
            "horizontal_fov_deg_16_by_9": rounded(math.degrees(2 * math.atan((16/9) * math.tan(math.radians(fov)/2)))),
            "old_4px_wide_error_at_optical_axis_px": rounded(focal * math.tan(angle4)),
            "old_8px_wide_error_at_optical_axis_px": rounded(focal * math.tan(angle8)),
            "16k_panorama_vertical_source_texels_in_view": rounded(8192 * fov / 180),
            "16k_panorama_center_output_px_per_latitude_texel": rounded(focal * math.pi / 8192),
        })
    narrow_focal = focal_pixels(1080, 1)
    four_pixel_angle = math.atan(4 / narrow_focal)
    memory = []
    for width in (4096, 8192, 16384):
        pixels = width * (width // 2)
        memory.append({"width": width, "height": width // 2,
                       "rgba8_mipped_mib_estimate": rounded(pixels * 4 * 4 / 3 / 2**20),
                       "8bpp_mipped_mib_estimate": rounded(pixels * 4 / 3 / 2**20)})
    return {
        "kind": "analytical-only; not runtime qualification",
        "inputs": {"output_px": [1920, 1080], "old_horizontal_fov_deg": 90,
                   "panorama_px": [16384, 8192], "station_ned_m": station,
                   "ned_to_photo_rotation_rows": orientation},
        "coordinate_fixture": {"cardinal_uv": expected,
                               "rotated_direction_cases": len(directions),
                               "max_direction_roundtrip_error": max_error},
        "old_wide_error_deg": {"4px": rounded(math.degrees(angle4)), "8px": rounded(math.degrees(angle8))},
        "zoom_projection": zoom_rows,
        "four_output_pixels_at_1deg": {
            "angular_error_deg": rounded(math.degrees(four_pixel_angle)),
            "16k_panorama_latitude_texels": rounded(math.degrees(four_pixel_angle) * 8192 / 180)},
        "transverse_5cm_offset_at_1deg": [
            {"range_m": distance, "optical_axis_error_px": rounded(narrow_focal * .05 / distance)}
            for distance in (10, 100, 1000)],
        "memory_estimates": memory,
        "three_8k_8bpp_mipped_panorama_copies_mib_estimate": 128,
        "limitations": ["Ideal pinhole and full 2:1 equirectangular assumptions",
                        "Vertical texel spans assume a level/equatorial optical axis",
                        "Center displacement is not a whole-frame residual bound",
                        "Five-centimetre transverse displacement is not a ground-height error model",
                        "Mips use the 4/3 approximation; no CPU, upload, lighting or driver overhead",
                        "Three panorama copies illustrate overlap, not an observed or admitted loader"]}


if __name__ == "__main__":
    print(json.dumps(report(), indent=2, allow_nan=False) + "\n", end="")
