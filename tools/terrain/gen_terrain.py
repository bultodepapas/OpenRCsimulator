#!/usr/bin/env python3
"""Generate the deterministic visual horizon profile used by the L7 hill ring.

This is a small visual-only L13a slice. It does not generate physical terrain.
All sampling, interpolation, masks, and quantization use integer arithmetic.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "app/data/fields/horizon.json"

M32 = 0xFFFFFFFF
Q = 1 << 16
AZIMUTH_SAMPLES = 1440
RADIAL_START_MM = 1_500_000
RADIAL_STEP_MM = 187_500
RADIAL_ROWS = 25
RADIAL_INNER_FULL_MM = 3_000_000
RADIAL_OUTER_FADE_START_MM = 5_000_000
RADIAL_END_MM = 6_000_000
OUTER_FLAT_RADIUS_MM = 20_000_000
HEIGHT_SCALE = 256
SEED = 20261007

# The three wavelengths stay broad enough to read as distant rolling hills.
# Amplitudes sum to 39 m, so the 72 m bias bounds all relief to 33..111 m
# before radial masks. The maximum is below the 120 m profile limit.
OCTAVES = (
    (180, 1_500_000, 24 * HEIGHT_SCALE),
    (90, 750_000, 11 * HEIGHT_SCALE),
    (45, 375_000, 4 * HEIGHT_SCALE),
)
RELIEF_BIAS_Q = 72 * HEIGHT_SCALE

CORRIDOR_CENTERS = (360, 1080)  # 90° east and 270° west, north-clockwise.
CORRIDOR_CORE_HALF_WIDTH = 80  # 20° at four samples per degree.
CORRIDOR_FEATHER = 60  # a further 15° with integer smoothstep.


def lowbias32(value: int) -> int:
    """lowbias32 by skeeto/hash-prospector; hash constants are Unlicense."""
    value &= M32
    value ^= value >> 16
    value = (value * 0x7FEB352D) & M32
    value ^= value >> 15
    value = (value * 0x846CA68B) & M32
    value ^= value >> 16
    return value


def lattice(azimuth_cell: int, radial_cell: int, seed: int, period: int) -> int:
    """Return a signed integer sample in [-32768, 32767], periodic in azimuth."""
    x = azimuth_cell % period
    value = lowbias32(
        (x * 0x9E3779B1 ^ radial_cell * 0x85EBCA77 ^ seed) & M32
    )
    return (value >> 16) - 32768


def smoothstep_q(value_q: int) -> int:
    """Integer smoothstep for a value in [0, Q], returned in [0, Q]."""
    value_q = max(0, min(Q, value_q))
    return (value_q * value_q * (3 * Q - 2 * value_q)) // (Q * Q)


def interpolate_q(a: int, b: int, fraction_q: int) -> int:
    """Linear interpolation between integer samples using a Q-scaled fraction."""
    return (a * (Q - fraction_q) + b * fraction_q) // Q


def value_noise_q(
    azimuth_index: int,
    radius_mm: int,
    angular_cell_samples: int,
    radial_cell_mm: int,
    seed: int,
) -> int:
    """Periodic 2D integer value noise in the cylindrical angle/radius domain."""
    angular_period = AZIMUTH_SAMPLES // angular_cell_samples
    ax, angle_remainder = divmod(azimuth_index, angular_cell_samples)
    rx, radius_remainder = divmod(radius_mm, radial_cell_mm)
    angle_t = smoothstep_q(angle_remainder * Q // angular_cell_samples)
    radius_t = smoothstep_q(radius_remainder * Q // radial_cell_mm)

    a = lattice(ax, rx, seed, angular_period)
    b = lattice(ax + 1, rx, seed, angular_period)
    c = lattice(ax, rx + 1, seed, angular_period)
    d = lattice(ax + 1, rx + 1, seed, angular_period)
    top = interpolate_q(a, b, angle_t)
    bottom = interpolate_q(c, d, angle_t)
    return interpolate_q(top, bottom, radius_t)


def radial_mask_q(radius_mm: int) -> int:
    """Fade in from 1.5 to 3 km, then out from 5 to 6 km."""
    inner_t = (radius_mm - RADIAL_START_MM) * Q // (RADIAL_INNER_FULL_MM - RADIAL_START_MM)
    outer_t = (RADIAL_END_MM - radius_mm) * Q // (RADIAL_END_MM - RADIAL_OUTER_FADE_START_MM)
    return min(smoothstep_q(inner_t), smoothstep_q(outer_t))


def corridor_mask_q(azimuth_index: int) -> int:
    """Keep broad, smooth lowland corridors toward the east and west."""
    distance = min(
        min((azimuth_index - center) % AZIMUTH_SAMPLES,
            (center - azimuth_index) % AZIMUTH_SAMPLES)
        for center in CORRIDOR_CENTERS
    )
    if distance <= CORRIDOR_CORE_HALF_WIDTH:
        return 0
    if distance >= CORRIDOR_CORE_HALF_WIDTH + CORRIDOR_FEATHER:
        return Q
    feather_t = (distance - CORRIDOR_CORE_HALF_WIDTH) * Q // CORRIDOR_FEATHER
    return smoothstep_q(feather_t)


def rounded_signed_product(value: int, factor_q: int) -> int:
    """Multiply by a Q-scaled mask with symmetric nearest-integer rounding."""
    product = value * factor_q
    if product < 0:
        return -((-product + Q // 2) // Q)
    return (product + Q // 2) // Q


def height_q(azimuth_index: int, radius_mm: int) -> int:
    """Height in 1/256 m; all calculations are integers."""
    if radius_mm == RADIAL_START_MM or radius_mm == 6_000_000:
        return 0

    relief_q = RELIEF_BIAS_Q
    for octave_index, (angle_width, radial_width, amplitude_q) in enumerate(OCTAVES):
        sample = value_noise_q(
            azimuth_index,
            radius_mm,
            angle_width,
            radial_width,
            SEED + octave_index * 0x9E37,
        )
        scaled_noise = amplitude_q * sample
        if scaled_noise < 0:
            relief_q -= (-scaled_noise + 16384) // 32768
        else:
            relief_q += (scaled_noise + 16384) // 32768

    relief_q = max(0, min(120 * HEIGHT_SCALE, relief_q))
    relief_q = rounded_signed_product(relief_q, radial_mask_q(radius_mm))
    return max(0, rounded_signed_product(relief_q, corridor_mask_q(azimuth_index)))


def radius_rows_mm() -> list[int]:
    return [RADIAL_START_MM + row * RADIAL_STEP_MM for row in range(RADIAL_ROWS)]


def canonical_height_bytes(rows: list[list[int]]) -> bytes:
    flattened = [value for row in rows for value in row]
    if any(value < -32768 or value > 32767 for value in flattened):
        raise ValueError("height profile exceeds the signed int16 range")
    return struct.pack("<" + "h" * len(flattened), *flattened)


def build_profile() -> dict[str, object]:
    radii = radius_rows_mm()
    if any(height_q(0, radius) != height_q(AZIMUTH_SAMPLES, radius) for radius in radii):
        raise ValueError("azimuth noise is not periodic at the seam")
    rows = [
        [height_q(azimuth, radius) for azimuth in range(AZIMUTH_SAMPLES)]
        for radius in radii
    ]
    height_bytes = canonical_height_bytes(rows)
    heights = [value for row in rows for value in row]
    if any(rows[0]) or any(rows[-1]):
        raise ValueError("profile lost its zero-height radial borders")
    for center in CORRIDOR_CENTERS:
        for offset in range(-CORRIDOR_CORE_HALF_WIDTH, CORRIDOR_CORE_HALF_WIDTH + 1):
            angle = (center + offset) % AZIMUTH_SAMPLES
            if any(row[angle] for row in rows):
                raise ValueError("profile lost an exact-zero scenery corridor core")
    if max(heights) > 120 * HEIGHT_SCALE:
        raise ValueError("profile exceeds the 120 m height bound")
    active_heights = [
        value
        for radius, row in zip(radii, rows)
        if RADIAL_INNER_FULL_MM <= radius <= RADIAL_OUTER_FADE_START_MM
        for angle, value in enumerate(row)
        if min(
            min((angle - center) % AZIMUTH_SAMPLES,
                (center - angle) % AZIMUTH_SAMPLES)
            for center in CORRIDOR_CENTERS
        ) >= CORRIDOR_CORE_HALF_WIDTH + CORRIDOR_FEATHER
    ]
    if not active_heights or min(active_heights) < 30 * HEIGHT_SCALE:
        raise ValueError("full-height 3–5 km hill elevations fell below 30 m")

    return {
        "format": "openrc-horizon-profile v1",
        "azimuth_samples": AZIMUTH_SAMPLES,
        "azimuth_origin": "north",
        "azimuth_direction": "clockwise",
        "azimuth_periodic": True,
        "radial_rows": RADIAL_ROWS,
        "radii_mm": radii,
        "height_scale": HEIGHT_SCALE,
        "dtype": "int16_le",
        "layout": "radial_major",
        "outer_flat_radius_mm": OUTER_FLAT_RADIUS_MM,
        "min_q": min(heights),
        "max_q": max(heights),
        "sha256": hashlib.sha256(height_bytes).hexdigest(),
        "heights_q": rows,
        "generator": {
            "script": "tools/terrain/gen_terrain.py",
            "algorithm": "periodic lowbias32 value noise with integer smoothstep",
            "seed": SEED,
            "params": {
                "height_unit": "1/256 m",
                "radial_start_mm": RADIAL_START_MM,
                "radial_step_mm": RADIAL_STEP_MM,
                "radial_end_mm": RADIAL_END_MM,
                "outer_flat_radius_mm": OUTER_FLAT_RADIUS_MM,
                "relief_bias_q": RELIEF_BIAS_Q,
                "octaves": [
                    {
                        "azimuth_cell_samples": angle_width,
                        "radial_cell_mm": radial_width,
                        "amplitude_q": amplitude_q,
                    }
                    for angle_width, radial_width, amplitude_q in OCTAVES
                ],
                "radial_fade_in_mm": [RADIAL_START_MM, RADIAL_INNER_FULL_MM],
                "radial_fade_out_mm": [RADIAL_OUTER_FADE_START_MM, RADIAL_END_MM],
                "corridors": {
                    "axis": "azimuth_deg_from_north_clockwise",
                    "centers_deg": [90, 270],
                    "flat_half_width_deg": 20,
                    "feather_deg": 15,
                    "evidence_kind": "design estimate from optional scenery landmarks",
                },
            },
        },
        "source": {
            "kind": "procedural",
            "license": "MIT generator; lowbias32 constants from Unlicense source",
            "evidence_kind": "design estimate; visual-only L7 profile",
        },
    }


def serialized_profile() -> bytes:
    return (json.dumps(build_profile(), sort_keys=True, separators=(",", ":")) + "\n").encode()


def write_profile(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(serialized_profile())


def check_profile(path: Path) -> bool:
    expected = serialized_profile()
    try:
        actual = path.read_bytes()
    except OSError as error:
        print(f"missing or unreadable generated profile: {path}: {error}", file=sys.stderr)
        return False
    if actual != expected:
        print(f"stale or modified generated profile: {path}", file=sys.stderr)
        return False
    print(f"profile is deterministic and current: {path}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="profile JSON path")
    parser.add_argument("--check", action="store_true", help="compare output with regenerated bytes")
    args = parser.parse_args()
    output_path = args.output if args.output.is_absolute() else ROOT / args.output

    if args.check:
        return 0 if check_profile(output_path) else 1
    write_profile(output_path)
    profile = build_profile()
    print(
        f"wrote {output_path}: {profile['radial_rows']} x {profile['azimuth_samples']} samples, "
        f"height_q {profile['min_q']}..{profile['max_q']}, sha256 {profile['sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
