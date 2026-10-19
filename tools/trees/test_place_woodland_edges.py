#!/usr/bin/env python3
"""Focused deterministic checks for the default-field woodland-edge recipe."""

from __future__ import annotations

import hashlib
from collections import Counter
import unittest
from unittest import mock

import place_woodland_edges as woodland


class WoodlandEdgePlacementTests(unittest.TestCase):
    def test_generated_document_is_deterministic_and_current(self) -> None:
        output = woodland.DEFAULT_OUTPUT
        self.assertTrue(output.is_file(), "generate app/data/woodland_edges.json first")
        expected = output.read_text(encoding="utf-8")
        self.assertEqual(woodland._encode(woodland.build_document()), expected)
        self.assertEqual(woodland._encode(woodland.build_document()), expected)

    def test_contract_and_source_derived_triangle_budget(self) -> None:
        document = woodland.build_document()
        self.assertEqual(document["format"], "openrc-woodland-edges v3")
        self.assertEqual(document["field_id"], "default")
        self.assertEqual(document["pilot_origin_ne_m"], [0.0, 0.0])
        patches = document["patches"]
        self.assertEqual(len(patches), 4)
        self.assertEqual([patch["id"] for patch in patches], [patch["id"] for patch in woodland.PATCHES])
        self.assertEqual([patch["path_seeds"] for patch in patches], [
            [710000 + patch_index * 100 + path_index for path_index in range(12)]
            for patch_index in range(4)
        ])
        self.assertEqual([patch["shrub_height_m"] for patch in patches], [0.8, 1.0, 1.1, 0.9])
        hedge = woodland._parse_hedge_contract(
            woodland.HEDGE_SOURCE_PATH.read_text(encoding="utf-8"),
            woodland.PALETTE_SOURCE_PATH.read_text(encoding="utf-8"),
        )
        segment_yaw_bins: set[int] = set()
        expected_species = dict(woodland.SHRUB_SPECIES_COUNTS)
        for patch_index, patch in enumerate(patches):
            self.assertEqual(len(patch["paths_ne_m"]), 12)
            self.assertEqual(len(patch["shrub_species"]), 12)
            self.assertEqual(len(patch["shrub_heights_m"]), 12)
            self.assertEqual(Counter(patch["shrub_species"]), Counter(expected_species))
            self.assertGreaterEqual(min(patch["shrub_heights_m"]), patch["shrub_height_m"] * 0.55 - 1e-6)
            self.assertEqual(max(patch["shrub_heights_m"]), patch["shrub_height_m"])
            self.assertGreaterEqual(len(set(patch["shrub_heights_m"])), 8)
            for path in patch["paths_ne_m"]:
                self.assertEqual(len(path), 2)
                length = woodland.math.dist(path[0], path[1])
                self.assertTrue(1.5 <= length <= 2.0, length)
                self.assertEqual(int(length // float(hedge["card_spacing_m"])), 1)
                yaw = woodland.math.atan2(path[1][1] - path[0][1], path[1][0] - path[0][0]) % woodland.math.tau
                segment_yaw_bins.add(int(yaw / (woodland.math.pi / 6.0)))
            self.assertEqual(len(patch["grass_ne_m"]), 3)
            self.assertEqual(len(patch["grass_heights_m"]), 3)
            self.assertEqual(len(patch["grass_cards"]), 43)
            self.assertEqual([card["id"] for card in patch["grass_cards"][:3]], [
                f"{patch['id']}:grass:{index}" for index in range(3)
            ])
            self.assertEqual([(card["north_m"], card["east_m"]) for card in patch["grass_cards"][:3]],
                             [tuple(point) for point in patch["grass_ne_m"]])
            groundcover = patch["grass_cards"][3:]
            self.assertEqual(len(groundcover), 40)
            self.assertEqual([card["id"] for card in groundcover], [
                f"{patch['id']}:groundcover:{index}" for index in range(40)
            ])
            self.assertEqual(len({card["seed"] for card in patch["grass_cards"]}), 43)
            self.assertTrue(all(0.0 <= card["yaw_rad"] < woodland.math.tau for card in patch["grass_cards"]))
            self.assertGreater(len({round(card["yaw_rad"], 3) for card in patch["grass_cards"]}), 35)
            self.assertEqual(patch["shrub_width_m"], 0.90)
            self.assertEqual(patch["grass_height_m"], 0.25)
            self.assertGreaterEqual(min(patch["grass_heights_m"]), 0.25 * 0.45 - 1e-6)
            self.assertEqual(max(patch["grass_heights_m"]), 0.25)
            self.assertEqual(patch["floor_center_ne_m"], woodland.PATCHES[patch_index]["center_ne_m"])
            self.assertEqual(patch["floor_half_size_m"], 2.0)
            grass = patch["grass_ne_m"]
            area_twice = abs(
                (grass[1][0] - grass[0][0]) * (grass[2][1] - grass[0][1])
                - (grass[1][1] - grass[0][1]) * (grass[2][0] - grass[0][0])
            )
            self.assertGreater(area_twice, 4.0, "asymmetric grass margin should not be collinear")
        self.assertGreaterEqual(len(segment_yaw_bins), 8, "independent segments should have varied orientations")

        source = document["source_geometry"]
        self.assertEqual(source["shrub_card_instance_count"], 48)
        self.assertEqual(source["grass_card_instance_count"], 172)
        self.assertEqual(source["shrub_card_triangles_per_instance"], 2)
        self.assertEqual(source["grass_card_triangles_per_instance"], 2)
        self.assertEqual(source["grass_source_triangles"], 155)
        self.assertEqual(source["shrub_source_asset_role"], "maximum_card_envelope_reference_only")
        self.assertEqual(source["shrub_species_source_ids"], list(expected_species))
        self.assertEqual(source["shrub_species_instances_per_patch"], expected_species)
        self.assertEqual(source["shrub_species_instance_counts"], {
            source_id: count * 4 for source_id, count in expected_species.items()
        })
        self.assertEqual(list(source["shrub_species_source_metadata"]), list(expected_species))
        for source_id, manifest_path in woodland.SHRUB_SPECIES_MANIFEST_PATHS.items():
            manifest = woodland._read_json(manifest_path)
            metadata = source["shrub_species_source_metadata"][source_id]
            self.assertEqual(metadata["impostor_asset_id"], manifest["asset_id"])
            self.assertEqual(metadata["source_geometry_sha256"], manifest["source_geometry_sha256"])
            self.assertEqual(metadata["atlas_sha256"], manifest["atlas_sha256"])
            self.assertAlmostEqual(
                metadata["source_height_to_frame_ratio"],
                manifest["source_height_m"] / max(manifest["frame_world_size_m"]),
                places=8,
            )
        self.assertEqual(source["floor_patch_count"], 4)
        self.assertEqual(source["floor_half_size_m"], 2.0)
        self.assertEqual(source["floor_grid_cells_per_side"], 2)
        self.assertEqual(source["floor_triangles_per_patch"], 8)
        self.assertEqual(source["floor_triangle_count"], 32)
        self.assertEqual(document["source_triangle_budget"], 48 * 2 + 172 * 2 + 32)
        self.assertEqual(document["source_triangle_budget"], 472)
        self.assertEqual(source["computed_source_triangle_budget"], document["source_triangle_budget"])
        self.assertEqual(source["shrub_source_geometry_sha256"],
                         "08768c680e3abeafd25858c9d3f369bcb7eed014661d3b6825a397f2a6a3deea")
        self.assertEqual(len(source["grass_source_geometry_sha256"]), 64)
        grass_manifest = woodland._read_json(woodland.GRASS_SHORT_MANIFEST_PATH)
        self.assertEqual(source["grass_card_asset_id"], grass_manifest["asset_id"])
        self.assertEqual(source["grass_card_atlas_sha256"], grass_manifest["atlas_sha256"])
        self.assertEqual(source["grass_card_frame_world_size_m"], grass_manifest["frame_world_size_m"])
        self.assertEqual(hashlib.sha256(woodland.GRASS_SHORT_ATLAS_PATH.read_bytes()).hexdigest(),
                         grass_manifest["atlas_sha256"])
        all_grass_cards = [card for patch in patches for card in patch["grass_cards"]]
        balanced_cards = [card for card in all_grass_cards
                          if woodland._hash01(card["seed"], 4242, 0) < 0.5]
        self.assertGreaterEqual(len(balanced_cards), 72)
        self.assertLessEqual(len(balanced_cards), 100)
        self.assertEqual(source["shrub_max_height_m"], 1.232)
        self.assertGreater(source["shrub_full_quad_side_m_at_max_height"], 1.6)
        self.assertGreater(source["shrub_full_quad_horizontal_radius_m_at_max_height"], 1.1)
        self.assertEqual(source["shrub_full_quad_horizontal_radius_m_at_max_height"],
                         source["shrub_full_quad_sphere_radius_m_at_max_height"])
        self.assertGreater(source["grass_full_quad_horizontal_radius_m_at_max_height"], 0.0)
        self.assertLess(source["grass_full_quad_horizontal_radius_m_at_max_height"], 0.3)

    def test_full_layout_envelopes_and_existing_masks_are_clear(self) -> None:
        document = woodland.build_document()
        validation = document["validation"]
        self.assertTrue(validation["passed"])
        self.assertEqual(validation["layout_cards_reproduced_from_imported_hedge_contract"], 48)
        self.assertEqual(validation["independent_shrub_segment_count"], 48)
        self.assertEqual(validation["segment_seed_count"], 48)
        self.assertEqual(validation["shrub_species_instance_counts"], {
            source_id: count * 4 for source_id, count in woodland.SHRUB_SPECIES_COUNTS.items()
        })
        self.assertEqual(validation["grass_card_count"], 172)
        self.assertEqual(validation["groundcover_card_count"], 160)
        self.assertLessEqual(validation["groundcover_center_radius_max_m"], 5.2)
        self.assertGreaterEqual(validation["grass_card_nearest_neighbor_distance_min_m"],
                                woodland.GROUNDCOVER_MIN_SPACING_M)
        self.assertLess(validation["grass_card_nearest_neighbor_distance_max_m"], 5.0)
        self.assertLess(validation["groundcover_to_shrub_nearest_center_m"], 1.0)
        inner_heights: list[float] = []
        outer_heights: list[float] = []
        for patch in document["patches"]:
            for card in patch["grass_cards"]:
                if ":groundcover:" not in card["id"]:
                    continue
                radius = woodland.math.dist(
                    (card["north_m"], card["east_m"]), patch["floor_center_ne_m"])
                (inner_heights if radius < 3.5 else outer_heights).append(card["height_m"])
        self.assertLess(sum(outer_heights) / len(outer_heights),
                        sum(inner_heights) / len(inner_heights))
        self.assertEqual(validation["cards_per_short_segment_min"], 1)
        self.assertEqual(validation["cards_per_short_segment_max"], 1)
        self.assertGreaterEqual(validation["segment_length_min_m"], 1.5)
        self.assertLessEqual(validation["segment_length_max_m"], 2.0)
        self.assertGreaterEqual(validation["segment_yaw_30_degree_bin_count"], 8)
        self.assertLess(validation["card_nearest_neighbor_distance_max_m"], 2.0)
        self.assertLess(validation["card_nearest_neighbor_distance_min_m"],
                        validation["card_nearest_neighbor_distance_max_m"])
        self.assertGreater(validation["path_sweep_samples_at_0_25m"], 350)
        self.assertEqual(validation["plant_geometry_centers_checked"],
                         48 + 172 + 4 + validation["path_sweep_samples_at_0_25m"])
        self.assertEqual(validation["floor_rectangles_checked"], 4)
        self.assertEqual(validation["all_current_treeline_positions_checked"], 1680)
        self.assertEqual(validation["all_scenery_placement_envelopes_checked"], 136)
        self.assertEqual(validation["scenery_track_segments_checked"], 29)
        self.assertEqual(validation["scenery_hedge_fence_segments_checked"], 10)
        self.assertEqual(validation["scenery_patch_polygons_checked"], 1)

        margins = validation["minimum_margins_m_or_degrees"]
        for key in (
            "edge_ring_inner_m", "edge_ring_outer_m", "protected_gap_clearance_deg",
            "tree_clearance_m", "rough_surface_margin_m", "runway_corridor_margin_m",
            "rotorpad_corridor_margin_m", "lake_bank_clearance_m", "track_clearance_m",
            "props_clearance_m", "hedge_fence_clearance_m", "scenery_patch_clearance_m",
        ):
            self.assertGreater(margins[key], 0.0, key)
        tree = document["source_geometry"]["tree_envelope"]
        self.assertLessEqual(tree["tree_max_horizontal_radius_with_wind_m"],
                             tree["tree_runtime_clearance_radius_m"])
        self.assertLessEqual(tree["tree_clearance_used_m"], 15.0)
        limits = document["source_geometry"]["patch_radial_envelope_limits_m"]
        used = validation["patch_radial_envelope_used_m"]
        self.assertEqual(set(used), set(limits))
        self.assertEqual(limits, woodland.PATCH_RADIAL_ENVELOPE_LIMITS_M)
        for patch_id, limit in limits.items():
            self.assertLessEqual(used[patch_id], limit)

    def test_source_hashes_cover_reproducible_inputs_without_mutation(self) -> None:
        watched = (woodland.FIELD_PATH, woodland.SCENERY_PATH, woodland.LAKE_PATH)
        before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in watched}
        document = woodland.build_document()
        after = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in watched}
        self.assertEqual(before, after)
        hashes = document["source_sha256_normalized_text"]
        self.assertIn("app/data/fields/default.json", hashes)
        self.assertIn("app/data/scenery/default.json", hashes)
        self.assertIn("app/data/fields/lake.json", hashes)
        self.assertIn("app/scenery/imported_hedge.gd", hashes)
        self.assertIn("app/scenery/imported_vegetation.gd", hashes)
        self.assertIn("app/scenery/vegetation_placement.gd", hashes)
        self.assertIn("app/assets/landscape/vegetation/impostors/grass_common_short_4view.json", hashes)
        self.assertIn("app/render/landscape_upgrade/scenery_grass_mask.gd", hashes)
        self.assertIn("app/assets/landscape/vegetation/impostors/grass_common_tall_4view.json", hashes)
        self.assertIn("app/assets/landscape/vegetation/impostors/fern_1_4view.json", hashes)
        self.assertTrue(all(len(value) == 64 for value in hashes.values()))
        self.assertFalse(any(key in document for key in ("groups", "collision_proxies")))

    def test_maple_clearance_uses_the_mature_placement_height(self) -> None:
        prefab_source = woodland.PREFABS_SOURCE_PATH.read_text(encoding="utf-8")
        model_source = woodland.MODELS_SOURCE_PATH.read_text(encoding="utf-8")
        placement_source = woodland.VEGETATION_PLACEMENT_PATH.read_text(encoding="utf-8")
        maple = {
            "id": "maple_tree",
            "source_bounds_m": {
                "height": 7.0,
                "min": [-2.0, 0.0, -3.0],
                "max": [2.0, 7.0, 3.0],
            },
        }
        broadleaf = {
            "id": "common_tree_3",
            "source_bounds_m": {
                "height": 10.0,
                "min": [-2.0, 0.0, -2.0],
                "max": [2.0, 10.0, 2.0],
            },
        }
        small_assets = {
            asset_id: {
                "id": asset_id,
                "source_bounds_m": {
                    "height": 1.0,
                    "min": [-0.5, 0.0, -0.5],
                    "max": [0.5, 1.0, 0.5],
                },
            }
            for asset_id in ("common_tree_1", "bush_common_flowers", "flower_3_group")
        }
        catalog = {"assets": [maple, broadleaf, *small_assets.values()]}
        aliases = (
            '"shade_tree": ["maple_tree", "common_tree_3"]\n'
            '"sapling": ["common_tree_1"]\n'
            '"bush": ["bush_common_flowers"]\n'
            '"flower_clump": ["flower_3_group"]\n'
        )

        radii, _max_radius = woodland._max_prop_radii(
            prefab_source, model_source, catalog, aliases, placement_source
        )

        maple_radius_at_14m = woodland.math.hypot(4.0, 6.0)
        broadleaf_radius_at_10_3m = woodland.math.hypot(2.06, 2.06)
        self.assertAlmostEqual(radii["shade_tree"], maple_radius_at_14m)
        self.assertGreater(radii["shade_tree"], broadleaf_radius_at_10_3m)
        self.assertAlmostEqual(
            float(woodland._source_number("const MATURE_MAPLE_HEIGHT_M := 14.0\n", "MATURE_MAPLE_HEIGHT_M")),
            14.0,
        )
        stale_catalog = {"assets": [item for item in catalog["assets"] if item["id"] != "maple_tree"]}
        with self.assertRaisesRegex(ValueError, "Maple placement alias"):
            woodland._max_prop_radii(prefab_source, model_source, stale_catalog, aliases, placement_source)

    def test_short_grass_impostor_manifest_is_bound_to_catalog_source(self) -> None:
        original_read_json = woodland._read_json
        changed_manifest = dict(original_read_json(woodland.GRASS_SHORT_MANIFEST_PATH))
        changed_manifest["source_geometry_sha256"] = "0" * 64

        def read_with_changed_grass_manifest(path):
            if path == woodland.GRASS_SHORT_MANIFEST_PATH:
                return changed_manifest
            return original_read_json(path)

        with mock.patch.object(woodland, "_read_json", side_effect=read_with_changed_grass_manifest):
            with self.assertRaisesRegex(ValueError, "short-grass impostor manifest"):
                woodland.build_document()


if __name__ == "__main__":
    unittest.main(verbosity=2)
