#!/usr/bin/env python3
"""Focused regression tests for the deterministic L6b/L7 tree placement recipe."""

from __future__ import annotations

import json
import math
from pathlib import Path
import unittest

from place import (
    CROWN_RADIUS_M,
    FAR_CLUSTER_COUNT,
    FAR_CLUSTER_RADIUS_M,
    FAR_COUNT,
    FAR_RADIUS_MAX_M,
    FAR_RADIUS_MIN_M,
    FAR_TREES_PER_CLUSTER,
    GAPS,
    NEAR_COUNT,
    NEAR_POSITIONS_SHA256,
    _angular_distance,
    _inside_flight_corridor,
    _positions_sha256,
    generate,
    generate_near,
)


ROOT = Path(__file__).resolve().parents[2]
FIELD_PATH = ROOT / "app/data/fields/default.json"


def _sector(north: float, east: float) -> int:
    return min(7, int((math.atan2(east, north) % math.tau) / (math.tau / 8.0)))


class FarForestPlacementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.field = json.loads(FIELD_PATH.read_text(encoding="utf-8"))
        cls.object_data, cls.manifest = generate(cls.field)
        cls.points = cls.object_data["positions"]["value"]
        cls.near = cls.points[:NEAR_COUNT]
        cls.far = cls.points[NEAR_COUNT:]

    def test_l6b_positions_keep_the_frozen_count_and_digest(self) -> None:
        near = generate_near(self.field)
        self.assertEqual(len(near), NEAR_COUNT)
        self.assertEqual(_positions_sha256(near), NEAR_POSITIONS_SHA256)
        self.assertEqual(self.near, near)

    def test_l7_is_twelve_bounded_clusters_and_uses_all_sectors(self) -> None:
        clusters = self.manifest["clusters"]
        self.assertEqual(len(clusters), FAR_CLUSTER_COUNT)
        self.assertTrue(all(cluster["count"] == FAR_TREES_PER_CLUSTER for cluster in clusters))
        self.assertTrue(all(cluster["radius_m"] == FAR_CLUSTER_RADIUS_M for cluster in clusters))
        self.assertEqual(len(self.far), FAR_COUNT)
        self.assertTrue(set(cluster["sector"] for cluster in clusters) >= set(range(8)))
        self.assertTrue(set(_sector(point[0], point[1]) for point in self.far) >= set(range(8)))

    def test_radii_grid_gap_and_flight_corridor_contracts(self) -> None:
        pilot_north = self.field["pilot"]["north"]["value"]
        strips = [surface for surface in self.field["surfaces"] if surface["type"] in ("runway", "mown")]
        self.assertTrue(all(270.0 <= math.hypot(point[0], point[1]) <= 570.0 for point in self.near))
        self.assertTrue(
            all(FAR_RADIUS_MIN_M <= math.hypot(point[0], point[1]) <= FAR_RADIUS_MAX_M for point in self.far)
        )
        for north, east, down in self.far:
            self.assertEqual(down, 0)
            self.assertEqual((north / 0.25) % 1, 0)
            self.assertEqual((east / 0.25) % 1, 0)
            radius = math.hypot(north, east)
            angle = math.degrees(math.atan2(east, north)) % 360.0
            margin = math.degrees(math.asin(CROWN_RADIUS_M / radius))
            self.assertTrue(all(_angular_distance(angle, center) > half + margin for center, half in GAPS))
            self.assertFalse(_inside_flight_corridor(north, pilot_north, strips, 0.0))

    def test_far_spacing_and_repeated_generation_are_stable(self) -> None:
        second, second_manifest = generate(self.field)
        self.assertEqual(self.object_data, second)
        self.assertEqual(self.manifest, second_manifest)
        for cluster_index in range(FAR_CLUSTER_COUNT):
            cluster = self.far[cluster_index * FAR_TREES_PER_CLUSTER:(cluster_index + 1) * FAR_TREES_PER_CLUSTER]
            for index, point in enumerate(cluster):
                for other in cluster[:index]:
                    self.assertGreaterEqual(math.hypot(point[0] - other[0], point[1] - other[1]), 4.5)

    def test_committed_default_matches_the_generator(self) -> None:
        self.assertEqual(self.field["objects"], [self.object_data])
        self.assertEqual(self.manifest["near_positions_sha256"], NEAR_POSITIONS_SHA256)
        self.assertEqual(self.manifest["far_count"], 1200)


if __name__ == "__main__":
    unittest.main()
