#!/usr/bin/env python3
"""Focused regression tests for the deterministic L6b/L7 tree placement recipe."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from place import (
    CROWN_RADIUS_M,
    FAR_MIN_SPACING_M,
    FAR_CLUSTER_COUNT,
    FAR_CLUSTER_RADIUS_M,
    FAR_COUNT,
    FAR_RADIUS_MAX_M,
    FAR_RADIUS_MIN_M,
    FAR_TREES_PER_CLUSTER,
    GAPS,
    HABITAT_FAR_COUNT,
    HABITAT_FAR_SEED,
    HABITAT_PATCH_COUNT,
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
PLACE_SCRIPT = ROOT / "tools/trees/place.py"
HABITAT_TRIAL_ROOT = ROOT / "tmp/tree-quality-implementation"


def _sector(north: float, east: float) -> int:
    return min(7, int((math.atan2(east, north) % math.tau) / (math.tau / 8.0)))


class HistoricalPlacementRecipeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.field = json.loads(FIELD_PATH.read_text(encoding="utf-8"))
        cls.object_data, cls.manifest = generate(cls.field, "existing")
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

    def test_existing_recipe_remains_a_reproducible_historical_control(self) -> None:
        self.assertEqual(self.manifest["recipe"], "existing")
        self.assertEqual(self.manifest["near_positions_sha256"], NEAR_POSITIONS_SHA256)
        self.assertEqual(self.manifest["far_count"], FAR_COUNT)
        self.assertEqual(
            self.manifest["far_positions_sha256"],
            "7c8ee96a60c22241ea1f58f0fdadcba6c010e540c6d9f0fe82b7bbe10d9b442c",
        )
        self.assertEqual(
            self.manifest["positions_sha256"],
            "772d1207da670718c575c20e5b6246d8d2e6e7cdf70e006e006642c9e95ff2f3",
        )


class HabitatRecipeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.field_bytes = FIELD_PATH.read_bytes()
        cls.field = json.loads(cls.field_bytes)
        cls.object_data, cls.manifest = generate(cls.field)
        cls.points = cls.object_data["positions"]["value"]
        cls.near = cls.points[:NEAR_COUNT]
        cls.far = cls.points[NEAR_COUNT:]

    def test_habitat_keeps_frozen_near_prefix_and_total_count(self) -> None:
        frozen_near = generate_near(self.field)
        self.assertEqual(self.near, frozen_near)
        self.assertEqual(_positions_sha256(self.near), NEAR_POSITIONS_SHA256)
        self.assertEqual(len(self.near), NEAR_COUNT)
        self.assertEqual(len(self.far), HABITAT_FAR_COUNT)
        self.assertEqual(len(self.points), 1680)
        self.assertEqual(self.manifest["near_count"], NEAR_COUNT)
        self.assertEqual(self.manifest["far_count"], HABITAT_FAR_COUNT)
        self.assertEqual(self.manifest["recipe"], "habitat-v1")
        self.assertEqual(HABITAT_FAR_SEED, 610617)
        self.assertEqual(self.field["objects"], [self.object_data])
        self.assertEqual(self.manifest["near_positions_sha256"], NEAR_POSITIONS_SHA256)
        self.assertEqual(
            self.manifest["far_positions_sha256"],
            "c24d479e2a5063f895a106a7a6e687736b8bfc2b8c5c62cf6c60554a6d58594e",
        )

    def test_habitat_patches_have_varied_counts_shapes_and_bounds(self) -> None:
        patches = self.manifest["patches"]
        self.assertEqual(len(patches), HABITAT_PATCH_COUNT)
        self.assertEqual(HABITAT_PATCH_COUNT, 12)
        self.assertEqual(len({patch["count"] for patch in patches}), HABITAT_PATCH_COUNT)
        self.assertEqual(sum(patch["count"] for patch in patches), HABITAT_FAR_COUNT)
        self.assertEqual(self.manifest["patch_counts"], [patch["count"] for patch in patches])
        self.assertTrue({patch["sector"] for patch in patches} >= set(range(8)))
        self.assertTrue(
            {_sector(patch["north_m"], patch["east_m"]) for patch in patches} >= set(range(8))
        )
        self.assertEqual(
            len({(patch["semi_major_m"], patch["semi_minor_m"]) for patch in patches}),
            HABITAT_PATCH_COUNT,
        )
        self.assertTrue(all(patch["semi_major_m"] > patch["semi_minor_m"] for patch in patches))
        self.assertEqual(len({patch["orientation_deg"] for patch in patches}), HABITAT_PATCH_COUNT)
        self.assertIn("far_bounds_m", self.manifest)
        self.assertEqual(self.object_data["positions"]["kind"], "derived")
        self.assertIn("not surveyed", self.object_data["positions"]["source"])
        self.assertIn("ecological simulation", self.object_data["positions"]["source"])
        self.assertIn(self.manifest["far_positions_sha256"], self.object_data["positions"]["source"])
        self.assertIn("collision proxies are derived by the runtime", self.object_data["positions"]["source"])
        self.assertIn("no terrain or aerodynamics change", self.object_data["positions"]["source"])

        for patch in patches:
            with self.subTest(patch=patch["sector"], count=patch["count"]):
                self.assertEqual(patch["end_index"] - patch["start_index"], patch["count"])
                points = self.far[patch["start_index"]:patch["end_index"]]
                self.assertEqual(len(points), patch["count"])
                self.assertEqual(patch["bounds_m"]["north_min_m"], min(p[0] for p in points))
                self.assertEqual(patch["bounds_m"]["north_max_m"], max(p[0] for p in points))
                self.assertEqual(patch["bounds_m"]["east_min_m"], min(p[1] for p in points))
                self.assertEqual(patch["bounds_m"]["east_max_m"], max(p[1] for p in points))

    def test_habitat_keeps_ring_gaps_corridor_grid_and_spacing(self) -> None:
        pilot_north = self.field["pilot"]["north"]["value"]
        strips = [surface for surface in self.field["surfaces"] if surface["type"] in ("runway", "mown")]
        spacing_grid: dict[tuple[int, int], list[tuple[float, float]]] = {}
        for north, east, down in self.far:
            self.assertEqual(down, 0)
            self.assertTrue(FAR_RADIUS_MIN_M <= math.hypot(north, east) <= FAR_RADIUS_MAX_M)
            self.assertAlmostEqual(north / 0.25, round(north / 0.25))
            self.assertAlmostEqual(east / 0.25, round(east / 0.25))
            radius = math.hypot(north, east)
            angle = math.degrees(math.atan2(east, north)) % 360.0
            margin = math.degrees(math.asin(CROWN_RADIUS_M / radius))
            self.assertTrue(all(_angular_distance(angle, center) > half + margin for center, half in GAPS))
            self.assertFalse(_inside_flight_corridor(north, pilot_north, strips, 0.0))
            cell = (math.floor(north / FAR_MIN_SPACING_M), math.floor(east / FAR_MIN_SPACING_M))
            for offset_north in (-1, 0, 1):
                for offset_east in (-1, 0, 1):
                    for other_north, other_east in spacing_grid.get(
                        (cell[0] + offset_north, cell[1] + offset_east),
                        (),
                    ):
                        self.assertGreaterEqual(
                            math.hypot(north - other_north, east - other_east),
                            FAR_MIN_SPACING_M,
                        )
            spacing_grid.setdefault(cell, []).append((north, east))

    def test_habitat_generation_is_deterministic(self) -> None:
        second_object, second_manifest = generate(self.field)
        self.assertEqual(self.object_data, second_object)
        self.assertEqual(self.manifest, second_manifest)
        self.assertEqual(_positions_sha256(self.far), "c24d479e2a5063f895a106a7a6e687736b8bfc2b8c5c62cf6c60554a6d58594e")

    def test_habitat_cli_is_default_and_existing_remains_explicit_control(self) -> None:
        production_hash = hashlib.sha256(FIELD_PATH.read_bytes()).hexdigest()
        default_check = subprocess.run(
            [sys.executable, str(PLACE_SCRIPT), "--check"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(default_check.returncode, 0, default_check.stderr)
        self.assertEqual(json.loads(default_check.stdout)["recipe"], "habitat-v1")

        explicit_habitat_check = subprocess.run(
            [sys.executable, str(PLACE_SCRIPT), "--recipe", "habitat-v1", "--check"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(explicit_habitat_check.returncode, 0, explicit_habitat_check.stderr)

        HABITAT_TRIAL_ROOT.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="place-habitat-test-", dir=HABITAT_TRIAL_ROOT) as temp:
            historical_path = Path(temp) / "historical-field.json"
            historical_path.write_bytes(self.field_bytes)
            historical_object, historical_manifest = generate(self.field, "existing")
            historical_command = [
                sys.executable,
                str(PLACE_SCRIPT),
                "--field",
                str(historical_path),
                "--recipe",
                "existing",
            ]
            generated = subprocess.run(historical_command, cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(generated.returncode, 0, generated.stderr)
            stage_bytes = historical_path.read_bytes()
            staged_field = json.loads(stage_bytes)
            self.assertEqual(staged_field["objects"], [historical_object])
            output = json.loads(generated.stdout)
            self.assertEqual(output["recipe"], "existing")
            self.assertEqual(output["positions_sha256"], historical_manifest["positions_sha256"])

            checked = subprocess.run([*historical_command, "--check"], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(checked.returncode, 0, checked.stderr)
            self.assertEqual(historical_path.read_bytes(), stage_bytes)

        self.assertEqual(hashlib.sha256(FIELD_PATH.read_bytes()).hexdigest(), production_hash)


if __name__ == "__main__":
    unittest.main()
