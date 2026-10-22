#!/usr/bin/env python3
"""Focused regression tests for the deterministic L6b/L7 tree placement recipe."""

from __future__ import annotations

from functools import lru_cache
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
    COUNTRYSIDE_FARM_BOXES_NE_M,
    FAR_GROVE_SEED,
    GAPS,
    GROVE_SEED,
    HABITAT_FAR_COUNT,
    HABITAT_FAR_SEED,
    HABITAT_PATCH_COUNT,
    NEAR_COUNT,
    NEAR_POSITIONS_SHA256,
    NEAR_RADIUS_MAX_M,
    NEAR_RADIUS_MIN_M,
    SCENERY_KEEPOUT_M,
    _angular_distance,
    _card_crown_radius,
    _in_skyline_anchor,
    _inside_protected_gap,
    _FarGroveSite,
    _scenery_keepout,
    _inside_flight_corridor,
    _positions_sha256,
    PRODUCTION_COUNTRYSIDE,
    PRODUCTION_SCENERY,
    PRODUCTION_WOODLAND_EDGES,
    generate,
    generate_habitat_far,
    generate_near,
    tree_identity,
)


ROOT = Path(__file__).resolve().parents[2]
FIELD_PATH = ROOT / "app/data/fields/default.json"
PLACE_SCRIPT = ROOT / "tools/trees/place.py"
HABITAT_TRIAL_ROOT = ROOT / "tmp/tree-quality-implementation"


@lru_cache(maxsize=None)
def _generated(recipe: str) -> tuple[dict, dict]:
    """One generation per recipe for the read-only tests; determinism tests regenerate."""
    return generate(json.loads(FIELD_PATH.read_bytes()), recipe)


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
        for index, cluster in enumerate(clusters):
            self.assertEqual(cluster["start_index"], index * FAR_TREES_PER_CLUSTER)
            self.assertEqual(cluster["end_index"], (index + 1) * FAR_TREES_PER_CLUSTER)
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
        second, second_manifest = generate(self.field, "existing")
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
        cls.object_data, cls.manifest = generate(cls.field, "habitat-v1")
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
                self.assertTrue(0.0 <= patch["outline_phase_rad"] < math.tau)
                self.assertTrue(0.0 <= patch["notch_angle_rad"] < math.tau)
                self.assertGreater(patch["notch_width_rad"], 0.0)
                self.assertGreater(patch["outline_notch_depth"], 0.0)

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
        second_object, second_manifest = generate(self.field, "habitat-v1")
        self.assertEqual(self.object_data, second_object)
        self.assertEqual(self.manifest, second_manifest)
        self.assertEqual(_positions_sha256(self.far), "c24d479e2a5063f895a106a7a6e687736b8bfc2b8c5c62cf6c60554a6d58594e")

    def test_groves_cli_is_default_and_other_recipes_remain_explicit(self) -> None:
        production_hash = hashlib.sha256(FIELD_PATH.read_bytes()).hexdigest()
        default_check = subprocess.run(
            [sys.executable, str(PLACE_SCRIPT), "--check"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(default_check.returncode, 0, default_check.stderr)
        self.assertEqual(json.loads(default_check.stdout)["recipe"], "groves-v2")

        # The committed field is groves-v1, so the habitat-v1 reference no longer matches it.
        explicit_habitat_check = subprocess.run(
            [sys.executable, str(PLACE_SCRIPT), "--recipe", "habitat-v1", "--check"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(explicit_habitat_check.returncode, 0)

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


class GroveRecipeTests(unittest.TestCase):
    """L7-R3 near groves, committed through the groves-v2 default."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.field_bytes = FIELD_PATH.read_bytes()
        cls.field = json.loads(cls.field_bytes)
        cls.object_data, cls.manifest = _generated("groves-v2")
        cls.points = cls.object_data["positions"]["value"]
        cls.near = cls.points[:NEAR_COUNT]
        cls.far = cls.points[NEAR_COUNT:]
        cls.v1_object, cls.v1_manifest = _generated("groves-v1")

    def test_committed_field_is_groves_v2_with_the_v1_near_ring_and_same_counts(self) -> None:
        self.assertEqual(self.field["objects"], [self.object_data])
        self.assertEqual(self.manifest["recipe"], "groves-v2")
        self.assertEqual((GROVE_SEED, FAR_GROVE_SEED), (620101, 620102))
        self.assertEqual((len(self.near), len(self.far), len(self.points)), (NEAR_COUNT, HABITAT_FAR_COUNT, 1680))
        self.assertEqual(self.near, self.v1_object["positions"]["value"][:NEAR_COUNT])
        self.assertEqual(self.manifest["near_groups"], self.v1_manifest["near_groups"])
        self.assertIn("L7-R3 groves-v2", self.object_data["positions"]["source"])
        self.assertIn("L7-R4", self.object_data["positions"]["source"])
        self.assertIn(self.manifest["positions_sha256"], self.object_data["positions"]["source"])
        # .gitattributes keeps the field CRLF; the generator writes those bytes on every OS.
        self.assertNotIn(b"\n", self.field_bytes.replace(b"\r\n", b""))

    def test_groups_are_woods_hedgerows_solitary_trees_and_frozen_anchors(self) -> None:
        groups = self.manifest["near_groups"]
        kinds = [group["kind"] for group in groups]
        self.assertEqual(kinds.count("wood"), 9)
        self.assertEqual(kinds.count("hedgerow"), 4)
        self.assertEqual(sum(group["count"] for group in groups), NEAR_COUNT)
        self.assertEqual(sum(g["count"] for g in groups if g["kind"] == "solitary"), 24)
        self.assertEqual(sum(g["count"] for g in groups if g["kind"] == "hedgerow"), 56)
        woods = [group for group in groups if group["kind"] == "wood"]
        self.assertTrue(all(group["dominant_share"] >= 0.75 for group in woods), woods)
        self.assertEqual(len({group["dominant_species"] for group in woods}), 3)
        frozen = generate_near(self.field)
        anchored = sorted(p for p in frozen if _in_skyline_anchor(p[0], p[1]))
        self.assertEqual(sorted(p for p in self.near if _in_skyline_anchor(p[0], p[1])), anchored)
        self.assertEqual(groups[0], {"kind": "skyline-anchor", "count": len(anchored)})

    def test_new_near_trees_keep_ring_gaps_corridor_anchors_and_scenery_clearance(self) -> None:
        pilot_north = self.field["pilot"]["north"]["value"]
        strips = [s for s in self.field["surfaces"] if s["type"] in ("runway", "mown")]
        frozen = {tuple(p) for p in generate_near(self.field)}
        keepout = _scenery_keepout(ROOT / "app/data/scenery/default.json")
        for north, east, down in self.near:
            with self.subTest(north=north, east=east):
                self.assertEqual(down, 0)
                self.assertEqual(north * 4, round(north * 4))
                self.assertEqual(east * 4, round(east * 4))
                self.assertTrue(NEAR_RADIUS_MIN_M <= math.hypot(north, east) <= NEAR_RADIUS_MAX_M)
                self.assertFalse(_inside_flight_corridor(north, pilot_north, strips, 0.0))
                if (north, east, down) in frozen and _in_skyline_anchor(north, east):
                    continue
                self.assertFalse(_inside_protected_gap(north, east))
                self.assertFalse(_in_skyline_anchor(north, east, CROWN_RADIUS_M))
                self.assertTrue(all(math.hypot(north - n, east - e) >= SCENERY_KEEPOUT_M for n, e in keepout))

    def test_crowns_do_not_stack_and_species_follow_the_renderer_hash(self) -> None:
        crowns = [(n, e, _card_crown_radius(n, e)) for n, e, _ in self.near]
        for index, (north, east, radius) in enumerate(crowns):
            for other_north, other_east, other_radius in crowns[index + 1:]:
                self.assertGreaterEqual(
                    math.hypot(north - other_north, east - other_east) + 1e-9,
                    0.55 * (radius + other_radius) if (north, east) != (other_north, other_east) else 0.0,
                )
        species = [tree_identity(n, e)[0] for n, e, _ in self.near]
        self.assertTrue(all(species.count(value) > 50 for value in range(3)))

    def test_grove_generation_is_deterministic(self) -> None:
        second_object, second_manifest = generate(self.field)
        self.assertEqual(self.object_data, second_object)
        self.assertEqual(self.manifest, second_manifest)
        # The manifest includes far_groups, so this also covers the L7-R4 far woods.


class FarGroveTests(unittest.TestCase):
    """L7-R4 far woods: compacted habitat-v1 patches clear of every fixed countryside feature."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.field = json.loads(FIELD_PATH.read_bytes())
        cls.object_data, cls.manifest = _generated("groves-v2")
        cls.far = cls.object_data["positions"]["value"][NEAR_COUNT:]
        habitat_far, _ = generate_habitat_far(cls.field)
        cls.anchored = sorted(p for p in habitat_far if _in_skyline_anchor(p[0], p[1]))

    def test_far_groups_are_twelve_single_species_woods_and_frozen_anchors(self) -> None:
        groups = self.manifest["far_groups"]
        self.assertEqual(groups[0], {"kind": "skyline-anchor", "count": len(self.anchored)})
        woods = [group for group in groups if group["kind"] == "wood"]
        self.assertEqual(len(woods), 12)
        self.assertEqual(sum(group["count"] for group in groups), HABITAT_FAR_COUNT)
        self.assertTrue(all(group["dominant_share"] >= 0.75 for group in woods), woods)
        self.assertEqual(sorted(p for p in self.far if _in_skyline_anchor(p[0], p[1])), self.anchored)

    def test_new_far_trees_clear_roads_farm_boxes_and_keepouts(self) -> None:
        site = _FarGroveSite(self.field, PRODUCTION_SCENERY, PRODUCTION_COUNTRYSIDE, PRODUCTION_WOODLAND_EDGES)
        roads = json.loads(PRODUCTION_COUNTRYSIDE.read_text(encoding="utf-8"))["roads"]
        anchored = {tuple(p) for p in self.anchored}
        for north, east, down in self.far:
            if (north, east, down) in anchored:
                continue
            with self.subTest(north=north, east=east):
                self.assertTrue(site.allowed(north, east))
                self.assertTrue(FAR_RADIUS_MIN_M < math.hypot(north, east) <= FAR_RADIUS_MAX_M)
                for n0, e0, n1, e1 in COUNTRYSIDE_FARM_BOXES_NE_M:
                    self.assertFalse(n0 - 10 < north < n1 + 10 and e0 - 10 < east < e1 + 10)
                for road in roads:
                    line = road["centerline_ne_m"]
                    clearance = min(_segment_distance((north, east), a, b) for a, b in zip(line, line[1:]))
                    self.assertGreater(clearance - road["width_m"] / 2.0, 3.0, road["id"])


def _segment_distance(point, start, end) -> float:
    dn, de = end[0] - start[0], end[1] - start[1]
    length2 = dn * dn + de * de
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, ((point[0] - start[0]) * dn + (point[1] - start[1]) * de) / length2))
    return math.hypot(point[0] - start[0] - t * dn, point[1] - start[1] - t * de)


if __name__ == "__main__":
    unittest.main()
