#!/usr/bin/env python3
"""Focused deterministic checks for the default-field woodland-edge recipe."""

from __future__ import annotations

import hashlib
import unittest

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
        self.assertEqual(document["format"], "openrc-woodland-edges v1")
        self.assertEqual(document["field_id"], "default")
        self.assertEqual(document["pilot_origin_ne_m"], [0.0, 0.0])
        patches = document["patches"]
        self.assertEqual(len(patches), 4)
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
        for patch in patches:
            self.assertEqual(len(patch["paths_ne_m"]), 12)
            for path in patch["paths_ne_m"]:
                self.assertEqual(len(path), 2)
                length = woodland.math.dist(path[0], path[1])
                self.assertTrue(1.5 <= length <= 2.0, length)
                self.assertEqual(int(length // float(hedge["card_spacing_m"])), 1)
                yaw = woodland.math.atan2(path[1][1] - path[0][1], path[1][0] - path[0][0]) % woodland.math.tau
                segment_yaw_bins.add(int(yaw / (woodland.math.pi / 6.0)))
            self.assertEqual(len(patch["grass_ne_m"]), 3)
            self.assertEqual(patch["shrub_width_m"], 0.90)
            self.assertEqual(patch["grass_height_m"], 0.25)
            grass = patch["grass_ne_m"]
            area_twice = abs(
                (grass[1][0] - grass[0][0]) * (grass[2][1] - grass[0][1])
                - (grass[1][1] - grass[0][1]) * (grass[2][0] - grass[0][0])
            )
            self.assertGreater(area_twice, 4.0, "asymmetric grass margin should not be collinear")
        self.assertGreaterEqual(len(segment_yaw_bins), 8, "independent segments should have varied orientations")

        source = document["source_geometry"]
        self.assertEqual(source["shrub_card_instance_count"], 48)
        self.assertEqual(source["grass_instance_count"], 12)
        self.assertEqual(source["shrub_card_triangles_per_instance"], 2)
        self.assertEqual(source["grass_source_triangles_per_instance"], 155)
        self.assertEqual(document["source_triangle_budget"], 48 * 2 + 12 * 155)
        self.assertEqual(document["source_triangle_budget"], 1956)
        self.assertEqual(source["computed_source_triangle_budget"], document["source_triangle_budget"])
        self.assertEqual(source["shrub_source_geometry_sha256"],
                         "08768c680e3abeafd25858c9d3f369bcb7eed014661d3b6825a397f2a6a3deea")
        self.assertEqual(len(source["grass_source_asset_sha256"]), 64)
        self.assertEqual(source["shrub_max_height_m"], 1.232)
        self.assertGreater(source["shrub_full_quad_side_m_at_max_height"], 1.6)
        self.assertGreater(source["shrub_full_quad_horizontal_radius_m_at_max_height"], 1.1)
        self.assertEqual(source["shrub_full_quad_horizontal_radius_m_at_max_height"],
                         source["shrub_full_quad_sphere_radius_m_at_max_height"])
        self.assertGreater(source["grass_mesh_max_horizontal_radius_m_at_grass_height"], 0.0)

    def test_full_layout_envelopes_and_existing_masks_are_clear(self) -> None:
        document = woodland.build_document()
        validation = document["validation"]
        self.assertTrue(validation["passed"])
        self.assertEqual(validation["layout_cards_reproduced_from_imported_hedge_contract"], 48)
        self.assertEqual(validation["independent_shrub_segment_count"], 48)
        self.assertEqual(validation["segment_seed_count"], 48)
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
                         48 + 12 + validation["path_sweep_samples_at_0_25m"])
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
        self.assertGreater(validation["grass_to_shrub_bound_clearance_m"], 0.0)

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
        self.assertIn("app/render/landscape_upgrade/scenery_grass_mask.gd", hashes)
        self.assertTrue(all(len(value) == 64 for value in hashes.values()))
        self.assertFalse(any(key in document for key in ("groups", "collision_proxies")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
