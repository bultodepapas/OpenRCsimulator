"""Requested rendering is bound to the workload and raw frame observations."""
import copy
import math
import unittest

from tools.godtest.render_evidence import RenderAccumulator, validate_rendering


def accumulator_rows(rows):
    accumulator = RenderAccumulator()
    for row in rows:
        accumulator.add(*row)
    return accumulator.finish()


def request_fixture():
    requested = {"headless": False, "phases": ["startup", "selection", "shutdown"], "cycles": 1,
                 "rendering_method": "auto", "rendering_driver": "auto", "aircraft": "fixture"}
    resolved = {**requested, "output_dir": "/fixture/run"}
    phases = [{"name": "startup", "id": "0-0-startup", "index": 0, "cycle": 0,
               "requested": True, "status": "complete", "rendered": True},
              {"name": "selection", "id": "0-1-selection", "index": 1, "cycle": 0,
               "requested": True, "status": "complete", "rendered": True}]
    raw = accumulator_rows([(0, 100, 10, 10, 1, 1), (0, 110, 10, 11, 1, 1),
                            (1, 120, 10, 12, 1, 1), (1, 130, 10, 13, 1, 1)])
    execution = {"host": {"platform": "Windows-10-10.0.0"},
                 "rendering_requested": {"rendering_method": "forward_plus", "rendering_driver": "vulkan"}}
    runtime = {"metrics": {"rendered": True}, "identity": {"diagnostics": dict(execution["rendering_requested"])}}
    return requested, resolved, runtime, phases, raw, execution


class RawRenderEvidenceTests(unittest.TestCase):
    def test_complete_phases_reconcile_absolute_counts_and_deltas(self):
        rows = [(0, 100, 10, 10, 1, 1), (0, 110, 10, 11, 1, 1),
                (1.0, 120, 10, 13.0, 2.0, 1.0), (1, 130, 10, 14, 1, 1)]
        result = accumulator_rows(rows)
        self.assertEqual(set(result), {"0", "1"})
        for receipt in result.values():
            self.assertEqual(receipt["status"], "complete")
            self.assertEqual(receipt["positive_in_phase_intervals"], 1)
            self.assertEqual(receipt["segments"], 1)
            self.assertEqual(receipt["undrawable_intervals"], 0)

    def test_labeled_window_mode_transition_is_counted_not_invalidating(self):
        # macOS fullscreen Space animation: undrawable while frames still draw.
        rows = [(0, 100, 10, 10, 1, 1, 0), (0, 110, 10, 11, 1, 0, 1), (0, 120, 10, 12, 1, 0, 1),
                (0, 130, 10, 13, 1, 1, 0)]
        receipt = accumulator_rows(rows)["0"]
        self.assertEqual(receipt["status"], "complete")
        self.assertEqual((receipt["window_mode_transition_intervals"], receipt["undrawable_intervals"]), (2, 0))

    def test_unlabeled_or_contradictory_transition_evidence_stays_invalid(self):
        unlabeled = accumulator_rows([(0, 100, 10, 10, 1, 1, 0), (0, 110, 10, 11, 1, 0, 0)])["0"]
        self.assertEqual(unlabeled["status"], "incomplete")
        self.assertIn("window_undrawable", unlabeled["reasons"])
        # Older streams without the label keep the strict meaning.
        legacy = accumulator_rows([(0, 100, 10, 10, 1, 1), (0, 110, 10, 11, 1, 0)])["0"]
        self.assertIn("window_undrawable", legacy["reasons"])
        drawable = accumulator_rows([(0, 100, 10, 10, 1, 1, 0), (0, 110, 10, 11, 1, 1, 1)])["0"]
        self.assertIn("window_transition_without_undrawable_window", drawable["reasons"])
        invalid = accumulator_rows([(0, 100, 10, 10, 1, 1, 0), (0, 110, 10, 11, 1, 0, 2)])["0"]
        self.assertIn("invalid_render_window_transition", invalid["reasons"])
        # A labeled interval without draw progress is a stall, not an animation.
        stalled = accumulator_rows([(0, 100, 10, 10, 1, 1, 0), (0, 110, 10, 10, 0, 0, 1),
                                    (0, 120, 10, 11, 1, 1, 0)])["0"]
        self.assertEqual((stalled["undrawable_intervals"], stalled["window_mode_transition_intervals"]), (1, 0))
        self.assertIn("window_undrawable", stalled["reasons"])

    def test_transition_draw_cannot_prove_new_phase(self):
        result = accumulator_rows([(0, 100, 10, 10, 1, 1), (0, 110, 10, 11, 1, 1),
                                   (1, 120, 10, 15, 4, 1), (1, 130, 10, 15, 0, 1)])
        self.assertEqual(result["0"]["status"], "complete")
        self.assertEqual(result["1"]["status"], "incomplete")
        self.assertEqual(result["1"]["positive_in_phase_intervals"], 0)
        self.assertIn("segment_without_in_phase_draw", result["1"]["reasons"])

    def test_reentered_phase_cannot_hide_an_undrawn_segment(self):
        rows = [(0, 100, 10, 10, 1, 1), (0, 110, 10, 11, 1, 1),
                (1, 120, 10, 12, 1, 1), (1, 130, 10, 13, 1, 1),
                (0, 140, 10, 14, 1, 1), (0, 150, 10, 14, 0, 1)]
        result = accumulator_rows(rows)
        self.assertEqual(result["0"]["status"], "incomplete")
        self.assertEqual((result["0"]["segments"], result["0"]["segments_without_draw"]), (2, 1))
        self.assertEqual(result["1"]["status"], "complete")

    def test_missing_channels_are_unavailable_and_undrawable_is_incomplete(self):
        for index in (3, 4, 5):
            rows = [[0, 100, 10, 10, 1, 1], [0, 110, 10, 11, 1, 1]]
            rows[0][index] = None
            with self.subTest(channel=index):
                self.assertEqual(accumulator_rows(rows)["0"]["status"], "unavailable")
        result = accumulator_rows([(0, 100, 10, 10, 1, 0), (0, 110, 10, 11, 1, 1)])
        self.assertEqual(result["0"]["status"], "incomplete")
        self.assertIn("window_undrawable", result["0"]["reasons"])

    def test_invalid_numeric_channels_and_counter_contradictions_fail_closed(self):
        for index, invalid in ((3, -1), (3, True), (3, math.inf), (4, 1.5),
                               (4, math.nan), (5, 2), (5, False), (5, "1")):
            rows = [[0, 100, 10, 10, 1, 1], [0, 110, 10, 11, 1, 1]]
            rows[1][index] = invalid
            with self.subTest(channel=index, value=str(invalid)):
                self.assertEqual(accumulator_rows(rows)["0"]["status"], "incomplete")
        mismatch = accumulator_rows([(0, 100, 10, 10, 1, 1), (0, 110, 10, 11, 1, 1),
                                     (1, 120, 10, 15, 1, 1), (1, 130, 10, 16, 1, 1)])
        for phase in ("0", "1"):
            self.assertEqual(mismatch[phase]["status"], "incomplete")
            self.assertIn("draw_counter_delta_mismatch", mismatch[phase]["reasons"])

    def test_structural_clock_errors_and_state_lifecycle(self):
        accumulator = RenderAccumulator()
        for row in ((-1, 100, 10, 1, 1, 1), (True, 100, 10, 1, 1, 1),
                    (0, 100, 0, 1, 1, 1), (0, 9, 10, 1, 1, 1),
                    (10001, 100, 10, 1, 1, 1)):
            with self.subTest(row=row), self.assertRaises(ValueError):
                accumulator.add(*row)
        accumulator.add(0, 100, 10, 10, 1, 1)
        accumulator.add(0, 111, 10, 11, 1, 1)
        first = accumulator.finish()
        self.assertIn("noncontiguous_frame_clock", first["0"]["reasons"])
        self.assertEqual(first, accumulator.finish())
        with self.assertRaises(ValueError):
            accumulator.add(0, 121, 10, 12, 1, 1)


class RequestedRenderEvidenceTests(unittest.TestCase):
    def test_matching_rendered_workload_is_accepted(self):
        result = validate_rendering(*request_fixture())
        self.assertEqual(result["status"], "complete", result)
        self.assertFalse(result["requested_headless"])
        self.assertEqual(result["requested_phases"], 2)

    def test_requested_manifest_cannot_be_reinterpreted_as_headless(self):
        fixture = list(request_fixture())
        fixture[1]["headless"] = True
        fixture[2]["metrics"]["rendered"] = False
        for phase in fixture[3]:
            phase["rendered"] = False
        result = validate_rendering(*fixture)
        self.assertEqual(result["status"], "incomplete")
        self.assertFalse(result["requested_headless"])
        self.assertIn("original requested and resolved workloads differ", result["issues"])
        for invalid in (None, {}, {"headless": 0}, {"headless": "false"}):
            changed = list(request_fixture()); changed[0] = invalid
            with self.subTest(original=invalid):
                self.assertEqual(validate_rendering(*changed)["status"], "incomplete")

    def test_all_phase_requested_flags_must_be_booleans_matching_the_workload(self):
        for invalid in (1, "yes", None, False):
            fixture = list(request_fixture()); fixture[3][1]["requested"] = invalid
            with self.subTest(requested=invalid):
                self.assertEqual(validate_rendering(*fixture)["status"], "incomplete")
        fixture = list(request_fixture()); fixture[3][1]["index"] = 0
        self.assertEqual(validate_rendering(*fixture)["status"], "incomplete")

    def test_positive_runtime_flags_cannot_hide_missing_or_undrawable_raw_frames(self):
        for fault in ("missing", "undrawable", "no_draw"):
            fixture = list(request_fixture())
            rows = [[0, 100, 10, 10, 1, 1], [0, 110, 10, 11, 1, 1],
                    [1, 120, 10, 12, 1, 1], [1, 130, 10, 13, 1, 1]]
            if fault == "missing":
                rows[2][5] = None
            elif fault == "undrawable":
                rows[2][5] = 0
            else:
                rows[3][3], rows[3][4] = 12, 0
            fixture[4] = accumulator_rows(rows)
            with self.subTest(fault=fault):
                result = validate_rendering(*fixture)
                self.assertEqual(result["status"], "incomplete")
                self.assertIn("raw draw evidence", " ".join(result["issues"]))

    def test_runtime_phase_or_global_receipt_must_be_positive(self):
        for fault in ("global", "phase", "unfinished"):
            fixture = list(request_fixture())
            if fault == "global": fixture[2]["metrics"]["rendered"] = False
            elif fault == "phase": fixture[3][1]["rendered"] = False
            else: fixture[3][1]["status"] = "failed"
            with self.subTest(fault=fault):
                self.assertEqual(validate_rendering(*fixture)["status"], "incomplete")

    def test_explicit_renderer_needs_matching_launcher_and_actual_receipts(self):
        fixture = list(request_fixture())
        for manifest in fixture[:2]:
            manifest.update(rendering_method="gl_compatibility", rendering_driver="opengl3")
        fixture[5]["rendering_requested"] = {"rendering_method": "gl_compatibility", "rendering_driver": "opengl3"}
        fixture[2]["identity"]["diagnostics"] = dict(fixture[5]["rendering_requested"])
        self.assertEqual(validate_rendering(*fixture)["status"], "complete")
        for fault in ("missing_launcher", "wrong_launcher", "wrong_actual"):
            altered = copy.deepcopy(fixture)
            if fault == "missing_launcher": altered[5].pop("rendering_requested")
            elif fault == "wrong_launcher": altered[5]["rendering_requested"]["rendering_driver"] = "vulkan"
            else: altered[2]["identity"]["diagnostics"]["rendering_driver"] = "vulkan"
            with self.subTest(fault=fault):
                self.assertEqual(validate_rendering(*altered)["status"], "incomplete")

    def test_auto_uses_recorded_host_not_report_host(self):
        fixture = list(request_fixture())
        fixture[5]["host"]["platform"] = "macOS-15.0-arm64"
        fixture[5]["rendering_requested"] = {"rendering_method": "mobile", "rendering_driver": "metal"}
        fixture[2]["identity"]["diagnostics"] = dict(fixture[5]["rendering_requested"])
        self.assertEqual(validate_rendering(*fixture)["status"], "complete")
        fixture[5]["host"]["platform"] = "unknown"
        result = validate_rendering(*fixture)
        self.assertEqual(result["status"], "incomplete")
        self.assertIn("recorded host platform", " ".join(result["issues"]))

    def test_headless_requires_verified_requested_mode_but_not_draw_evidence(self):
        fixture = list(request_fixture())
        fixture[0]["headless"] = fixture[1]["headless"] = True
        fixture[2], fixture[4], fixture[5] = {}, {}, {}
        result = validate_rendering(*fixture)
        self.assertTrue(result["requested_headless"])
        self.assertEqual(result["status"], "not_requested")
        fixture[1]["headless"] = False
        self.assertEqual(validate_rendering(*fixture)["status"], "incomplete")

    def test_all_expected_cycles_and_duplicate_requested_phases_are_present(self):
        fixture = list(request_fixture())
        for manifest in fixture[:2]:
            manifest["cycles"] = 2
        result = validate_rendering(*fixture)
        self.assertEqual(result["status"], "incomplete")
        self.assertIn("requested phase records are missing: selection", result["issues"])

    def test_phase_labels_cannot_alias_another_index_or_cycle(self):
        for fault in ("duplicate_id", "wrong_cycle", "missing_cycle", "numeric_mode"):
            fixture = list(request_fixture())
            if fault == "duplicate_id": fixture[3][1]["id"] = fixture[3][0]["id"]
            elif fault == "wrong_cycle": fixture[3][1]["cycle"] = 1
            elif fault == "missing_cycle": fixture[3][1].pop("cycle")
            else: fixture[1]["headless"] = 0
            with self.subTest(fault=fault):
                self.assertEqual(validate_rendering(*fixture)["status"], "incomplete")


if __name__ == "__main__":
    unittest.main()
