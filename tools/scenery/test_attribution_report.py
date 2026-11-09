"""LU-34: per-instance estimates and the historical budget's measurement identity."""
import copy
import json
from pathlib import Path
import unittest

import attribution_report as report_tool


IDENTITY = json.loads(Path(__file__).with_name("scene_budget.json").read_text(encoding="utf-8"))["measurement"]


def row(primitives, draws=10):
    return {"primitives": primitives, "draws": draws, "objects": draws}


def attribution(fmt="openrc-view-attribution v2"):
    # One pilot view: trees counted 9,312 for 79 beeches at full detail; grass needs no correction.
    view = {
        "complete": row(100_000), "complete_repeat": row(100_000), "without_sun_shadows": row(90_000, 8),
        "without": {"trees": row(90_688, 9), "grass": row(99_000, 9)},
        "instanced_lod": {"trees": [{"node": "fagus", "instances": 79, "counted": 9_312, "one_instance": 9_312}]},
    }
    if fmt.endswith("v1"):
        del view["instanced_lod"]
    groups = {name: {"source_triangles": 1, "full_detail_triangles": 0, "shadow_caster_triangles": 0,
                     "full_detail_meshes_over_5000": []} for name in ("trees", "grass")}
    return {"format": fmt, "viewport": [1280, 720], "adapter": "test", "godot": IDENTITY["godot"],
            "godot_hash": IDENTITY["godot_hash_prefix"] + "0000", "renderer": IDENTITY["renderer"],
            "scene_detail": "high", "mesh_lod_threshold": IDENTITY["mesh_lod_threshold"],
            "measurement_scope": IDENTITY["scope"], "measurement_settings": copy.deepcopy(IDENTITY["settings"]),
            "viewport_settings": copy.deepcopy(IDENTITY["viewport_settings"]), "groups": groups,
            "views": {name: copy.deepcopy(view) for name in report_tool.VIEW_CLASSES["pilot"]}}


def budget():
    return {"format": "openrc-scene-budget v1", "viewport": [1280, 720], "scene_detail": "high",
            "measurement": copy.deepcopy(IDENTITY),
            "classes": {"pilot": {"max_primitives": 10**7, "max_draws": 1000}}, "subsystems": {},
            "default_subsystem": {"pilot": {"primitives": 10**7, "draws": 1000}}}


def failures(report, limits=None):
    return report_tool.check_budget(report_tool.summarize(report), report, budget() if limits is None else limits)


class InstancedLodCorrectionTest(unittest.TestCase):
    def test_every_instance_is_counted(self):
        summary = report_tool.summarize(attribution())
        trees = summary["cost"]["trees"]["pilot_north"]
        self.assertEqual(trees["counter_primitives"], 9_312)
        self.assertEqual(trees["primitives"], 79 * 9_312)
        self.assertEqual(summary["cost"]["grass"]["pilot_north"]["primitives"], 1_000)
        total = summary["view_totals"]["pilot_north"]
        self.assertEqual(total["counter_primitives"], 100_000)
        self.assertEqual(total["primitives"], 100_000 + 78 * 9_312)

    def test_sun_delta_remains_raw_while_totals_are_corrected(self):
        summary = report_tool.summarize(attribution())
        shadow = summary["classes"]["pilot"]["sun_shadow_pass"]
        self.assertEqual(shadow["counter_primitives_max"], 10_000)
        self.assertEqual(shadow["primitives_max"], 10_000)  # compatibility alias
        self.assertEqual(shadow["primitives_kind"], "raw_engine_counter")
        self.assertIsNone(shadow["corrected_primitives_max"])
        self.assertEqual(shadow["draws_max"], 2)
        self.assertIn("raw sun-shadow counter delta", report_tool.markdown(summary))
        self.assertIn("no corrected shadow estimate", report_tool.markdown(summary))

    def test_per_instance_surfaces_are_not_counted_twice(self):
        # Four Quercus: 4 x 2,636 LOD-less leaves plus one 4,380 bark draw counted; 7,016 per tree.
        rows = [{"node": "quercus", "instances": 4, "counted": 14_924, "one_instance": 7_016}]
        self.assertEqual(report_tool.instanced_lod_correction(rows), 4 * 7_016 - 14_924)

    def test_budget_rejects_counter_only_attributions(self):
        self.assertTrue(any("v1 attribution" in failure for failure in failures(attribution("openrc-view-attribution v1"))))
        self.assertEqual(failures(attribution()), [])

    def test_budget_applies_to_its_scene_detail_only(self):
        report = attribution()
        report["scene_detail"] = "extreme"
        self.assertTrue(any("scene detail extreme" in failure for failure in failures(report)))
        del report["scene_detail"]
        self.assertTrue(any("scene detail None" in failure for failure in failures(report)))

    def test_identity_and_scope_mismatches_cannot_qualify(self):
        for key, wrong in (("godot", "4.8-beta2 (official)"), ("godot_hash", "000000000"),
                           ("renderer", "forward_plus"), ("measurement_scope", "complete-flight-v1"),
                           ("mesh_lod_threshold", 2.0), ("viewport", [1920, 1080]),
                           ("viewport", [1280.9, 720])):
            with self.subTest(key=key, wrong=wrong):
                report = attribution()
                report[key] = wrong
                self.assertTrue(failures(report), key)

    def test_different_world_and_viewport_settings_cannot_qualify(self):
        for field, key, wrong in (("measurement_settings", "scenery_enabled", False),
                                  ("measurement_settings", "scenery_quality", "low"),
                                  ("measurement_settings", "sun_shadows_enabled", False),
                                  ("measurement_settings", "lake_enabled", False),
                                  ("measurement_settings", "runway_meadow", False),
                                  ("measurement_settings", "shader_clock_s", 2.0),
                                  ("viewport_settings", "scaling_3d_scale", 0.5),
                                  ("viewport_settings", "msaa_3d", 0)):
            with self.subTest(field=field, key=key):
                report = attribution()
                report[field][key] = wrong
                self.assertTrue(any(key in failure for failure in failures(report)))

    def test_legacy_v2_is_readable_but_cannot_establish_identity(self):
        report = attribution()
        for key in ("measurement_scope", "measurement_settings", "viewport_settings", "godot_hash", "scene_detail"):
            del report[key]
        summary = report_tool.summarize(report)
        self.assertTrue(summary["instanced_lod_corrected"])
        self.assertIn("unknown (legacy attribution)", report_tool.markdown(summary))
        self.assertTrue(any("scope" in failure for failure in failures(report)))
        limits = budget()
        del limits["measurement"]
        self.assertTrue(any("budget lacks required measurement identity" in failure for failure in failures(attribution(), limits)))

    def test_missing_or_unstable_measurements_cannot_qualify(self):
        report = attribution()
        del report["views"]["pilot_north"]["instanced_lod"]
        report["views"]["pilot_east"]["complete_repeat"]["primitives"] += 1
        limits = budget()
        limits["max_texture_mib"] = 495
        limits["shadow_casters"] = {"allowed": [], "max_triangles": 1}
        del report["groups"]["grass"]["shadow_caster_triangles"]
        found = failures(report, limits)
        for phrase in ("missing instanced LOD", "unstable", "missing texture memory", "missing shadow-caster"):
            self.assertTrue(any(phrase in failure for failure in found), (phrase, found))

    def test_all_views_in_each_budgeted_class_are_required(self):
        report = attribution()
        del report["views"]["pilot_west"]
        self.assertTrue(any("missing views" in failure and "pilot_west" in failure for failure in failures(report)))

    def test_full_detail_exception_covers_every_cell_of_a_mesh(self):
        limits = budget()
        limits["full_detail_exceptions"] = {"trees": ["landscapelab_quercus_Part_00"]}
        report = attribution()
        report["groups"]["trees"]["full_detail_meshes_over_5000"] = [
            "landscapelab_quercus_Part_00_Cell_-1_-2:15816", "landscapelab_quercus_Part_00:5272"]
        self.assertEqual(failures(report, limits), [])
        report["groups"]["trees"]["full_detail_meshes_over_5000"].append("landscapelab_pine_Part_00_Cell_0_0:9000")
        self.assertEqual(len(failures(report, limits)), 1)


if __name__ == "__main__":
    unittest.main()
