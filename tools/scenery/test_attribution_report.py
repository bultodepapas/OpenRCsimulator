"""LU-34-R1: the scene budget counts every instance of an instanced mesh with LODs."""
import unittest

import attribution_report as report_tool


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
    return {"format": fmt, "viewport": [1280, 720], "adapter": "test", "godot": "4.7.2", "groups": groups,
            "views": {name: view for name in report_tool.VIEW_CLASSES["pilot"]}}


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

    def test_per_instance_surfaces_are_not_counted_twice(self):
        # Four Quercus: 4 x 2,636 LOD-less leaves plus one 4,380 bark draw counted; 7,016 per tree.
        rows = [{"node": "quercus", "instances": 4, "counted": 14_924, "one_instance": 7_016}]
        self.assertEqual(report_tool.instanced_lod_correction(rows), 4 * 7_016 - 14_924)

    def test_budget_rejects_counter_only_attributions(self):
        budget = {"format": "openrc-scene-budget v1", "viewport": [1280, 720],
                  "classes": {"pilot": {"max_primitives": 10**7, "max_draws": 1000}}, "subsystems": {}}
        v1 = attribution("openrc-view-attribution v1")
        failures = report_tool.check_budget(report_tool.summarize(v1), v1, budget)
        self.assertTrue(any("v1 attribution" in failure for failure in failures))
        v2 = attribution()
        self.assertEqual(report_tool.check_budget(report_tool.summarize(v2), v2, budget), [])

    def test_full_detail_exception_covers_every_cell_of_a_mesh(self):
        budget = {"format": "openrc-scene-budget v1", "viewport": [1280, 720],
                  "classes": {"pilot": {"max_primitives": 10**7, "max_draws": 1000}}, "subsystems": {},
                  "full_detail_exceptions": {"trees": ["landscapelab_quercus_Part_00"]}}
        report = attribution()
        report["groups"]["trees"]["full_detail_meshes_over_5000"] = [
            "landscapelab_quercus_Part_00_Cell_-1_-2:15816", "landscapelab_quercus_Part_00:5272"]
        summary = report_tool.summarize(report)
        self.assertEqual(report_tool.check_budget(summary, report, budget), [])
        report["groups"]["trees"]["full_detail_meshes_over_5000"].append("landscapelab_pine_Part_00_Cell_0_0:9000")
        self.assertEqual(len(report_tool.check_budget(summary, report, budget)), 1)


if __name__ == "__main__":
    unittest.main()
