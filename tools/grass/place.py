#!/usr/bin/env python3
"""Generate deterministic, field-independent L11a grass clump offsets."""

from __future__ import annotations

import argparse
import hashlib
import json
from math import isqrt
from pathlib import Path
import sys


SEED = 610707
COUNT = 6000
RADIUS_MM = 30_000
CENTER_CAP_MM = 3_000
DIRECTION_LIMIT = 32_767
MASK64 = (1 << 64) - 1
MAX_CANDIDATES = COUNT * 10_000

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "app/data/fields/grass.json"

COUNT_SOURCE = (
    "Estimated L11a prototype count, grounded in the 6,000-clump Compatibility spike "
    "in docs/research/landscape-investigations/05-grass-rendering.md; not measured field coverage."
)
RADIUS_SOURCE = (
    "Derived from the L11a near-field limit of 30 m in docs/research/landscape-investigations/05-grass-rendering.md; "
    "a visual radius, not surveyed geography."
)
SEED_SOURCE = "Fixed L11a generation seed for reproducibility; it has no physical meaning."
PROFILE_SOURCE = (
    "Derived from L11a's requested density proportional to 1/r in "
    "docs/research/landscape-investigations/05-grass-rendering.md. A 3 m estimated core caps "
    "the center density; outside it, expected count per radial metre is constant."
)


class SplitMix64:
    """Small platform-independent PRNG with integer-only bounded sampling."""

    def __init__(self, seed: int) -> None:
        self.state = seed & MASK64

    def next_u64(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        value = self.state
        value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & MASK64
        return value ^ (value >> 31)

    def randbelow(self, upper: int) -> int:
        """Return an unbiased integer in [0, upper), rejecting modulo tails."""
        if upper <= 0:
            raise ValueError("upper bound must be positive")
        limit = (1 << 64) - ((1 << 64) % upper)
        while True:
            value = self.next_u64()
            if value < limit:
                return value % upper


def _sample_radius_mm(rng: SplitMix64) -> int:
    """Sample capped 1/r density using integer rejection sampling.

    A uniform radius proposal is retained with probability r / core inside the
    core and always retained outside. Thus the radial probability is proportional
    to r inside the core (constant area density) and constant outside it.
    """
    while True:
        radius = rng.randbelow(RADIUS_MM + 1)
        if radius >= CENTER_CAP_MM or rng.randbelow(CENTER_CAP_MM) < radius:
            return radius


def _sample_direction(rng: SplitMix64) -> tuple[int, int, int]:
    """Return a discrete uniform-angle direction as x, y, integer length.

    Rejection sampling accepts integer points inside a disk. Normalizing by the
    integer square root removes the source point's radial weighting.
    """
    limit_squared = DIRECTION_LIMIT * DIRECTION_LIMIT
    while True:
        north = rng.randbelow(2 * DIRECTION_LIMIT + 1) - DIRECTION_LIMIT
        east = rng.randbelow(2 * DIRECTION_LIMIT + 1) - DIRECTION_LIMIT
        length_squared = north * north + east * east
        if 0 < length_squared <= limit_squared:
            return north, east, isqrt(length_squared)


def _round_div(numerator: int, denominator: int) -> int:
    """Round an integer quotient to nearest, symmetrically about zero."""
    if numerator < 0:
        return -((-numerator + denominator // 2) // denominator)
    return (numerator + denominator // 2) // denominator


def _rows_sha256(rows: list[list[int]]) -> str:
    canonical = "".join(f"{north},{east},{yaw},{size}\n" for north, east, yaw, size in rows)
    return hashlib.sha256(canonical.encode("ascii")).hexdigest()


def generate() -> dict[str, object]:
    """Build 6,000 unique pilot-relative N/E millimetre offsets."""
    rng = SplitMix64(SEED)
    rows: list[list[int]] = []
    centers: set[tuple[int, int]] = set()
    radius_squared_limit = RADIUS_MM * RADIUS_MM

    for _ in range(MAX_CANDIDATES):
        radius = _sample_radius_mm(rng)
        direction_north, direction_east, direction_length = _sample_direction(rng)
        north = _round_div(direction_north * radius, direction_length)
        east = _round_div(direction_east * radius, direction_length)
        if north * north + east * east > radius_squared_limit:
            continue
        center = (north, east)
        if center in centers:
            continue
        centers.add(center)
        rows.append([north, east, rng.randbelow(65_536), rng.randbelow(256)])
        if len(rows) == COUNT:
            break

    if len(rows) != COUNT:
        raise RuntimeError(f"candidate budget ended after {len(rows)} of {COUNT} unique centers")

    return {
        "format": "openrc-grass v1",
        "seed": SEED,
        "radius_mm": RADIUS_MM,
        "metadata": {
            "seed": {"value": SEED, "unit": "integer", "kind": "derived", "source": SEED_SOURCE},
            "radius_mm": {"value": RADIUS_MM, "unit": "mm", "kind": "derived", "source": RADIUS_SOURCE},
            "count": {"value": COUNT, "unit": "clumps", "kind": "estimated", "source": COUNT_SOURCE},
            "radial_density": {
                "kind": "derived",
                "source": PROFILE_SOURCE,
                "center_cap_mm": {
                    "value": CENTER_CAP_MM,
                    "unit": "mm",
                    "kind": "estimated",
                    "source": "L11a implementation choice to bound the center density; not specified by the visual study.",
                },
            },
            "row_encoding": {
                "kind": "derived",
                "source": "tools/grass/place.py; yaw is an unsigned turn fraction and size maps linearly to 0.75–1.25 in the renderer.",
                "columns": ["north_mm", "east_mm", "yaw_u16", "size_u8"],
            },
        },
        "rows_sha256": _rows_sha256(rows),
        "rows": rows,
    }


def _encoded(data: dict[str, object]) -> bytes:
    return (json.dumps(data, separators=(",", ":"), ensure_ascii=True) + "\n").encode("ascii")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="generated JSON path")
    parser.add_argument("--check", action="store_true", help="compare exact canonical output without writing")
    args = parser.parse_args(argv)

    data = generate()
    expected = _encoded(data)
    if args.check:
        try:
            actual = args.output.read_bytes()
        except OSError as exc:
            print(f"cannot read {args.output}: {exc}", file=sys.stderr)
            return 1
        if actual != expected:
            print(f"{args.output} differs from the deterministic L11a recipe", file=sys.stderr)
            return 1
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(expected)

    print(json.dumps({"rows": COUNT, "seed": SEED, "rows_sha256": data["rows_sha256"]}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
