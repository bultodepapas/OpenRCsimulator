#!/usr/bin/env python3
"""Tests for deterministic CPU forest composition diagnostics."""

from __future__ import annotations

import json
from pathlib import Path
import unittest

from habitat_diagnostics import (
    DEFAULT_CARD_CATALOG,
    DEFAULT_FIELD,
    DEFAULT_SCENERY,
    DEFAULT_VEGETATION_CATALOG,
    build_report,
    validate_report,
)


ROOT = Path(__file__).resolve().parents[2]


class HabitatDiagnosticsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.field_bytes = DEFAULT_FIELD.read_bytes()
        cls.inputs = (
            json.loads(cls.field_bytes),
            json.loads(DEFAULT_SCENERY.read_text(encoding="utf-8")),
            json.loads(DEFAULT_VEGETATION_CATALOG.read_text(encoding="utf-8")),
            json.loads(DEFAULT_CARD_CATALOG.read_text(encoding="utf-8")),
        )
        cls.report = build_report(*cls.inputs)

    def test_report_validates_both_equal_budget_placement_recipes(self) -> None:
        self.assertEqual(validate_report(self.report), [])
        comparison = self.report["recipe_comparison"]
        self.assertEqual(comparison["existing"]["counts"], comparison["habitat-v1"]["counts"])
        self.assertEqual(comparison["habitat-v1"]["counts"]["total"], 1680)
        self.assertTrue(self.report["committed_habitat_matches_generator"])
        self.assertEqual(DEFAULT_FIELD.read_bytes(), self.field_bytes)
        exclusions = self.report["authoritative_exclusions"]
        self.assertEqual(exclusions["lake_source_id"], "near_runway")
        self.assertEqual(exclusions["lake_source_format"], "openrc-lake v1")
        self.assertEqual(exclusions["lake_bank_polygon_used"], "bank_offsets_ne_m")
        self.assertTrue(exclusions["lake_geometry_separate_from_scenery_groups"])
        self.assertFalse(exclusions["separate_rc_course_geometry_found_in_default_scenery"])
        self.assertEqual(exclusions["scenery_track_ids_checked"], ["access-track", "worn-parking-door", "worn-door-pits"])

    def test_composition_reports_spacing_density_canopy_and_skyline_proxies(self) -> None:
        for recipe in self.report["recipe_comparison"].values():
            self.assertEqual(recipe["clearances"]["protected_gap_crown_hits"], 0)
            self.assertEqual(recipe["clearances"]["runway_mown_full_envelope_hits"], 0)
            self.assertEqual(recipe["clearances"]["rotorpad_full_envelope_hits"], 0)
            self.assertEqual(recipe["clearances"]["lake_bank_full_envelope_hits"], 0)
            self.assertEqual(recipe["clearances"]["rough_surface_full_envelope_failures"], 0)
            self.assertGreater(recipe["clearances"]["nearest_neighbor_distances_m"]["far"]["min_m"], 0.0)
            composition = recipe["composition"]
            self.assertEqual(len(composition["patches"]), 12)
            self.assertEqual(sum(patch["tree_count"] for patch in composition["patches"]), 1200)
            self.assertGreater(composition["eligible_patch_area_ha"], 0.0)
            self.assertGreater(composition["far_stems_per_ha_of_eligible_patch_area"], 0.0)
            self.assertGreaterEqual(composition["eligible_area_weighted_card_disk_occupancy_fraction"], 0.0)
            self.assertLessEqual(composition["eligible_area_weighted_card_disk_occupancy_fraction"], 1.0)
            self.assertIn("open_azimuth_intervals", recipe["skyline_proxy"]["combined"])
            self.assertGreaterEqual(recipe["skyline_proxy"]["combined"]["angular_coverage_percent"], 0.0)
            self.assertLessEqual(recipe["skyline_proxy"]["combined"]["angular_coverage_percent"], 100.0)
            self.assertTrue(all(value == 0 for value in recipe["clearances"]["scenery_track_full_envelope_hits"].values()))
        old = self.report["recipe_comparison"]["existing"]["composition"]
        habitat = self.report["recipe_comparison"]["habitat-v1"]["composition"]
        self.assertGreater(old["far_stems_per_ha_of_eligible_patch_area"], habitat["far_stems_per_ha_of_eligible_patch_area"])
        self.assertGreater(old["eligible_area_weighted_card_disk_occupancy_fraction"], habitat["eligible_area_weighted_card_disk_occupancy_fraction"])
        self.assertEqual(habitat["patch_tree_count_range"], [55, 173])
        self.assertNotEqual([patch["tree_count"] for patch in habitat["patches"]], [100] * 12)

    def test_wind_swept_card_envelope_fits_runtime_clearance(self) -> None:
        wind = self.report["recipe_comparison"]["habitat-v1"]["clearances"]["wind_envelope"]
        self.assertTrue(wind["runtime_clearance_covers_wind_envelope"])
        self.assertGreater(wind["clearance_margin_m"], 0.0)
        self.assertLessEqual(wind["max_horizontal_radius_with_wind_m"], 15.0)

    def test_catalog_and_current_instances_show_age_margin_and_lod_gaps(self) -> None:
        resources = self.report["resources"]
        self.assertEqual(resources["imported_mature_tree_form_count"], 8)
        self.assertEqual(resources["card_form_count"], 3)
        self.assertEqual(resources["imported_form_match_count"], 3)
        self.assertEqual(
            resources["imported_forms_without_a_same_named_card"],
            ["common_tree_2", "common_tree_4", "oak_tree", "pine_2", "pine_3"],
        )
        saplings = resources["sapling_group_zone_counts"]
        self.assertEqual(sum(group["count"] for group in saplings), 7)
        self.assertTrue(all(group["zone"] == "club" for group in saplings))
        self.assertEqual(resources["age_class_assessment"]["tree_role_forms_below_5m_source_height"], [])
        self.assertEqual(resources["understory_margin_assessment"]["configured_instances_in_countryside_or_forest_zones"], 0)
        self.assertIn("shrub", resources["understory_source_inventory_by_role"])
        self.assertIn("herb", resources["understory_source_inventory_by_role"])
        self.assertIn("L8a", self.report["representation_dispositions"])
        self.assertEqual(self.report["representation_dispositions"]["L8a"]["status"], "conditional; not qualified")
        oak_lods = resources["oak_supplier_lods_excluded_from_runtime"]
        self.assertEqual(oak_lods["levels"], [{"level": "LOD1", "triangles": 842}, {"level": "LOD2", "triangles": 14}])
        self.assertEqual(oak_lods["current_runtime_supplied_levels"], ["LOD0"])
        self.assertTrue(oak_lods["godot_importer_generated_lods_enabled"])
        self.assertEqual(self.report["representation_dispositions"]["L8a"]["runtime_supplier_alternate_lod_form_count"], 0)
        self.assertEqual(self.report["representation_dispositions"]["L8b"]["status"], "defer; dependent need not demonstrated")

    def test_density_increments_are_deferred_by_loader_and_evidence_gates(self) -> None:
        increments = self.report["density_increments"]
        self.assertEqual(increments["plus_25_percent"]["extra_tree_count"], 420)
        self.assertEqual(increments["plus_25_percent"]["hypothetical_total_tree_count"], 2100)
        self.assertEqual(increments["plus_25_percent"]["positions_over_current_loader_limit"], 420)
        self.assertEqual(increments["plus_50_percent"]["extra_tree_count"], 840)
        self.assertEqual(increments["plus_50_percent"]["hypothetical_total_tree_count"], 2520)
        self.assertEqual(increments["plus_50_percent"]["positions_over_current_loader_limit"], 840)
        self.assertFalse(increments["plus_25_percent"]["candidate_positions_generated"])
        self.assertFalse(increments["plus_50_percent"]["candidate_positions_generated"])


if __name__ == "__main__":
    unittest.main()
