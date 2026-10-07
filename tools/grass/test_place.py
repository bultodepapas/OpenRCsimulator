#!/usr/bin/env python3
"""Focused regression tests for the integer-only L11a placement recipe."""

from __future__ import annotations

import json
from math import isqrt
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from place import CENTER_CAP_MM, COUNT, RADIUS_MM, SEED, _rows_sha256, generate


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "app/data/fields/grass.json"
SCRIPT = Path(__file__).with_name("place.py")


class GrassPlacementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.data = generate()
        cls.rows = cls.data["rows"]

    def test_rows_are_in_bounds_unique_and_use_the_renderer_encoding(self) -> None:
        self.assertEqual(len(self.rows), COUNT)
        centers: set[tuple[int, int]] = set()
        for row in self.rows:
            self.assertEqual(len(row), 4)
            north, east, yaw, size = row
            self.assertTrue(all(type(value) is int for value in row))
            self.assertLessEqual(north * north + east * east, RADIUS_MM * RADIUS_MM)
            self.assertNotIn((north, east), centers, "a center was emitted twice")
            centers.add((north, east))
            self.assertGreaterEqual(yaw, 0)
            self.assertLessEqual(yaw, 65_535)
            self.assertGreaterEqual(size, 0)
            self.assertLessEqual(size, 255)
        self.assertEqual(len(centers), COUNT)

    def test_radial_counts_follow_ring_width_outside_the_bounded_core(self) -> None:
        # For density proportional to 1/r, annular counts scale with radial
        # width. The equal-width outer rings should therefore be close in count.
        ring_edges = (CENTER_CAP_MM, 8_000, 13_000, 18_000, 23_000, 28_000, RADIUS_MM)
        counts = [0] * (len(ring_edges) - 1)
        inner_cap = 0
        for north, east, _, _ in self.rows:
            radius = isqrt(north * north + east * east)
            if radius < CENTER_CAP_MM:
                inner_cap += 1
                continue
            for index, (low, high) in enumerate(zip(ring_edges, ring_edges[1:])):
                if low <= radius < high or (index == len(counts) - 1 and radius == high):
                    counts[index] += 1
                    break
        self.assertGreater(inner_cap, 0)
        # A bounded area density puts about one quarter of the cap's samples
        # inside half its radius, instead of accumulating at the pilot.
        self.assertGreaterEqual(inner_cap, 250)
        self.assertLessEqual(inner_cap, 410)
        half_cap = sum(
            isqrt(north * north + east * east) < CENTER_CAP_MM // 2
            for north, east, _, _ in self.rows
        )
        self.assertGreaterEqual(half_cap, 40)
        self.assertLessEqual(half_cap, 120)
        # Each 5 m interval outside the cap expects ~1,053; the final 2 m ring
        # expects ~421. Tolerances cover deterministic finite-sample variation.
        for actual in counts[:-1]:
            self.assertGreaterEqual(actual, 900)
            self.assertLessEqual(actual, 1_200)
        self.assertGreaterEqual(counts[-1], 350)
        self.assertLessEqual(counts[-1], 500)

    def test_reproducibility_digest_and_metadata_contract(self) -> None:
        second = generate()
        self.assertEqual(self.data, second)
        self.assertEqual(self.data["format"], "openrc-grass v1")
        self.assertEqual(self.data["seed"], SEED)
        self.assertEqual(self.data["radius_mm"], RADIUS_MM)
        self.assertEqual(self.data["metadata"]["count"]["kind"], "estimated")
        self.assertEqual(self.data["metadata"]["radial_density"]["center_cap_mm"]["value"], CENTER_CAP_MM)
        self.assertEqual(self.data["rows_sha256"], _rows_sha256(self.rows))
        self.assertEqual(len(self.data["rows_sha256"]), 64)

    def test_committed_json_is_exact_generator_output(self) -> None:
        self.assertEqual(OUTPUT.read_bytes(), (json.dumps(self.data, separators=(",", ":"), ensure_ascii=True) + "\n").encode("ascii"))
        result = subprocess.run([sys.executable, str(SCRIPT), "--check"], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_check_detects_mutation_in_a_temporary_copy(self) -> None:
        with tempfile.TemporaryDirectory(prefix="openrc-grass-mutation-") as temp_dir:
            mutated = Path(temp_dir) / "grass.json"
            raw = OUTPUT.read_bytes()
            changed = bytearray(raw)
            changed[changed.index(b"610707") + 1] ^= 1
            mutated.write_bytes(changed)
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--check", "--output", str(mutated)],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("differs from", result.stderr)


if __name__ == "__main__":
    unittest.main()
