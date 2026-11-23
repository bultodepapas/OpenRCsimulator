"""Graphics requests cannot pass by losing the runtime's rendered flag."""
from __future__ import annotations

import json
import hashlib
from pathlib import Path
import tempfile
import unittest

import catalog
from analysis import _dynamic_resolution_problem, report
from godtest import _case_success, _tour_success
from runner import write_json
from test_godtest import artifacts, replace_stream


class RenderingEvidenceTests(unittest.TestCase):
    def test_dynamic_resolution_close_requires_fresh_completed_work_for_the_final_scale(self):
        manifest = catalog.scenario("smoke", dict(dynamic_resolution_fps=60, render_scale=100))
        cached = dict(frame_id=4, generation=3, input_size=[1920, 1080], output_size=[1920, 1080],
                      recorded_usec=990_000)
        status = dict(state="observing", target_fps=60, configured_scale=1.0, completed_frame=cached)
        phase = dict(id="recover", start_usec=1_000_000, end_usec=1_500_000, dynamic_resolution=[
            dict(phase_id="recover", observed_usec=1_010_000, status=status),
        ], dynamic_resolution_close_status=status)
        fresh = dict(cached, frame_id=5, recorded_usec=1_480_000, gpu_usec=7_000.0)
        for close, reason in (
            (None, "missing phase-close completed frame"),
            (dict(cached, gpu_usec=7_000.0), "outside the measured phase"),
            (dict(fresh, recorded_usec=1_399_999), "stale at phase close"),
            (dict(fresh, recorded_usec=1_400_000), ""),
            (dict(fresh, recorded_usec=1_500_001), "outside the measured phase"),
            (dict(fresh, generation=4), "does not match the final confirmed scale"),
            (dict(fresh, input_size=[1632, 918]), "does not match the final confirmed scale"),
            (dict(fresh, output_size=[2560, 1440]), "does not match the final confirmed scale"),
            (dict(fresh, frame_id=3), "older than the final confirmation"),
            (dict(fresh, frame_id=4), "timestamp disagrees with the final confirmation"),
            (dict(fresh, gpu_usec=float("inf")), "invalid completed GPU duration"),
            (fresh, ""),
        ):
            with self.subTest(close=close):
                phase["dynamic_resolution_close_frame"] = close
                result = _dynamic_resolution_problem(phase, manifest)
                if reason:
                    self.assertIn(reason, result)
                else:
                    self.assertEqual(result, "")

        # With one in-phase frame, the phase close may re-observe that same exact frame.
        cached["recorded_usec"] = 1_410_000
        phase["dynamic_resolution"][0]["observed_usec"] = 1_415_000
        phase["dynamic_resolution_close_frame"] = dict(cached, gpu_usec=7_000.0)
        self.assertEqual(_dynamic_resolution_problem(phase, manifest), "")

    def test_dynamic_resolution_respects_the_pixel_floor_and_needs_two_rungs(self):
        output = [3456, 2234]
        for ceiling, extent, scale, issue in (
            (100, [2592, 1675], 0.75, "completed pixels do not match an allowed scale"),
            (100, [2937, 1898], 0.85, ""),
            (100, output, 1.0, ""),
            (85, [2937, 1898], 0.85, "no legal adaptive scale range"),
        ):
            with self.subTest(ceiling=ceiling, extent=extent):
                manifest = catalog.scenario("smoke", dict(resolution=output, window_mode="borderless",
                                                           dynamic_resolution_fps=60, render_scale=ceiling))
                frame = dict(frame_id=4, generation=3, input_size=extent, output_size=output, recorded_usec=100)
                status = dict(state="observing", target_fps=60, configured_scale=scale, completed_frame=frame)
                phase = dict(id="recover", start_usec=100, end_usec=200, dynamic_resolution=[
                    dict(phase_id="recover", observed_usec=120, status=status),
                ], dynamic_resolution_close_status=status,
                    dynamic_resolution_close_frame=dict(frame, frame_id=5, recorded_usec=180, gpu_usec=7_000.0))
                self.assertEqual(_dynamic_resolution_problem(phase, manifest), issue)

    def test_dynamic_resolution_requires_a_confirmed_frame_and_allows_holding_the_ceiling(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            artifacts(path)
            for name in ("manifest.requested.json", "manifest.resolved.json"):
                manifest = json.loads((path / name).read_text())
                manifest.update(dynamic_resolution_fps=60, render_scale=100, phases=["recover"])
                write_json(path / name, manifest)
            runtime = json.loads((path / "runtime.json").read_text())
            runtime["identity"]["window_focused_before_selection"] = True
            runtime["identity"]["effective_display"] = {"dynamic_resolution_fps": 60}
            phase = runtime["phases"][0]
            phase.update(name="recover", id="0-0-recover", start_usec=1, end_usec=100)
            frame = {"frame_id": 4, "generation": 3, "input_size": [1920, 1080], "output_size": [1920, 1080],
                     "recorded_usec": 2}
            phase["dynamic_resolution_close_frame"] = dict(frame, frame_id=6, recorded_usec=90, gpu_usec=7_000.0)
            for status, eligible in (
                ({"state": "observing", "completed_frame": frame}, True),
                ({"state": "observing"}, False),
                ({"state": "observing", "completed_frame": dict(frame, input_size=[1632, 918])}, False),
                ({"state": "fixed", "reason": "gpu_feedback_expired"}, False),
            ):
                with self.subTest(status=status):
                    phase["dynamic_resolution"] = [{"phase_id": phase["id"], "observed_usec": 5,
                                                     "status": {"target_fps": 60, "configured_scale": 1.0, **status}}]
                    phase["dynamic_resolution_close_status"] = phase["dynamic_resolution"][-1]["status"]
                    write_json(path / "runtime.json", runtime)
                    result = report(path, write=False)
                    self.assertEqual(result["data"] == "valid", eligible, result["issues"])
                    if not eligible:
                        self.assertIn("dynamic resolution not verified", " ".join(result["issues"]))

            confirmed = {"target_fps": 60, "state": "observing", "configured_scale": 1.0, "completed_frame": frame}
            pending = {"target_fps": 60, "state": "apply_pending", "configured_scale": 0.85}
            next_frame = dict(frame, frame_id=5, generation=4, input_size=[1632, 918], recorded_usec=3)
            applied = dict(confirmed, configured_scale=0.85, completed_frame=next_frame)
            warming = dict(pending, state="observing")
            for states, issue in (
                ([confirmed, {}], "controller status disappeared"),
                ([confirmed, {}, confirmed], "controller status disappeared"),
                ([confirmed, pending], "no completed frame"),
                ([confirmed, pending, warming], "no completed frame"),
                ([confirmed, dict(confirmed, completed_frame=None), confirmed], "identity did not advance"),
                ([confirmed, dict(pending, configured_scale=None), applied], "outside the allowed ladder"),
                ([confirmed, dict(pending, configured_scale=10**400)], "outside the allowed ladder"),
                ([confirmed, pending, dict(pending, configured_scale=0.75)], "changed without a completed frame"),
                ([confirmed, pending, confirmed], "pending scale"),
                ([confirmed, pending, dict(applied, completed_frame=dict(next_frame, generation=3))],
                 "identity did not advance"),
                ([confirmed, pending, dict(applied, completed_frame=dict(next_frame, frame_id=4))],
                 "identity did not advance"),
                ([confirmed, dict(pending, configured_scale=1.0), confirmed], "identity did not advance"),
                ([confirmed, dict(confirmed)], ""),
                ([pending, applied], ""),
                ([confirmed, pending, dict(pending), applied], ""),
                ([confirmed, pending, warming, applied], ""),
            ):
                with self.subTest(states=states):
                    phase["dynamic_resolution"] = [
                        {"phase_id": phase["id"], "observed_usec": at, "status": state}
                        for at, state in enumerate(states, start=5)
                    ]
                    phase["dynamic_resolution_close_status"] = states[-1]
                    phase["dynamic_resolution_close_frame"] = dict(states[-1].get("completed_frame") or {},
                                                                  frame_id=6, recorded_usec=90, gpu_usec=7_000.0)
                    write_json(path / "runtime.json", runtime)
                    result = report(path, write=False)
                    self.assertEqual(result["data"] == "valid", not issue, result["issues"])
                    if issue:
                        self.assertIn(issue, " ".join(result["issues"]))

            phase["dynamic_resolution"] = [{"phase_id": phase["id"], "observed_usec": 5, "status": confirmed}]
            for close_status in (None, pending):
                with self.subTest(close_status=close_status):
                    if close_status is None:
                        phase.pop("dynamic_resolution_close_status")
                    else:
                        phase["dynamic_resolution_close_status"] = close_status
                    write_json(path / "runtime.json", runtime)
                    result = report(path, write=False)
                    self.assertNotEqual(result["data"], "valid")
                    self.assertIn("phase-close controller observation", " ".join(result["issues"]))

    def test_explicit_render_scale_requires_matching_bilinear_receipts_at_both_boundaries(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            artifacts(path)
            for name in ("manifest.requested.json", "manifest.resolved.json"):
                manifest = json.loads((path / name).read_text())
                manifest.update(render_scale=67, phases=["recover"])
                write_json(path / name, manifest)
            runtime = json.loads((path / "runtime.json").read_text())
            runtime["identity"]["window_focused_before_selection"] = True
            phase = runtime["phases"][0]
            phase.update(name="recover", id="0-0-recover")
            phase["start_flight_3d_scaling"] = {"bilinear": True, "scale": 0.6700000166893005}
            for receipt, eligible in (
                (phase["start_flight_3d_scaling"], True),
                (None, False),
                ({"bilinear": True, "scale": 1.0}, False),
                ({"bilinear": False, "scale": 0.67}, False),
            ):
                with self.subTest(receipt=receipt):
                    phase["end_flight_3d_scaling"] = receipt
                    write_json(path / "runtime.json", runtime)
                    result = report(path, write=False)
                    self.assertEqual(result["data"] == "valid", eligible, result["issues"])
                    if not eligible:
                        self.assertIn("requested bilinear render scale not verified", " ".join(result["issues"]))

    def test_missing_false_or_non_boolean_runtime_receipt_fails_closed(self):
        for observed in (None, False, 1, "true"):
            with self.subTest(observed=observed), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "run"
                artifacts(path)
                runtime = json.loads((path / "runtime.json").read_text())
                if observed is None:
                    runtime["metrics"].pop("rendered")
                else:
                    runtime["metrics"]["rendered"] = observed
                write_json(path / "runtime.json", runtime)
                result = report(path, write=False)
                self.assertEqual((result["data"], result["coverage"], result["performance"]),
                                 ("ineligible", "partial", "not_qualified"))
                self.assertFalse(result["requested_headless"])
                self.assertFalse(_case_success(result))
                self.assertIn("positive runtime render receipt", " ".join(result["issues"]))

    def test_global_receipt_cannot_hide_undrawn_requested_phase(self):
        for observed in (None, False, 1):
            with self.subTest(observed=observed), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "run"
                artifacts(path)
                runtime = json.loads((path / "runtime.json").read_text())
                runtime["phases"][0]["rendered"] = observed
                write_json(path / "runtime.json", runtime)
                result = report(path, write=False)
                self.assertEqual(result["rendering"]["status"], "incomplete")
                self.assertFalse(result["rendered"])
                self.assertFalse(_case_success(result))
                self.assertIn("complete runtime draw progress", " ".join(result["issues"]))

    def test_non_boolean_phase_request_cannot_skip_its_render_receipt(self):
        for requested in (1, "true"):
            with self.subTest(requested=requested), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "run"
                frames = artifacts(path)
                replace_stream(path, frames, [16000, 17000, 16000, 17000], [0, 0, 1, 1])
                manifest = json.loads((path / "manifest.resolved.json").read_text())
                manifest["phases"] = ["startup", "loading"]
                write_json(path / "manifest.resolved.json", manifest)
                runtime = json.loads((path / "runtime.json").read_text())
                runtime["phases"].append(dict(runtime["phases"][0], name="loading", id="0-1-loading",
                                              index=1, requested=requested, rendered=False))
                write_json(path / "runtime.json", runtime)
                result = report(path, write=False)
                self.assertEqual((result["data"], result["coverage"]), ("ineligible", "partial"))
                self.assertFalse(_case_success(result))
                self.assertIn("explicit booleans", " ".join(result["issues"]))

    def test_lost_render_flag_does_not_skip_resolution_renderer_or_backend_checks(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            artifacts(path)
            manifest = json.loads((path / "manifest.resolved.json").read_text())
            manifest["require_native"] = True
            write_json(path / "manifest.resolved.json", manifest)
            runtime = json.loads((path / "runtime.json").read_text())
            runtime["metrics"].update(rendered=False, requested_resolution_match=False)
            runtime["identity"]["diagnostics"]["adapter_name"] = "llvmpipe (LLVM)"
            runtime["identity"]["backend"] = {"backend": "reference"}
            write_json(path / "runtime.json", runtime)
            result = report(path, write=False)
            for reason in ("window dimensions", "software renderer", "native physics"):
                self.assertIn(reason, " ".join(result["issues"]))

    def test_explicit_headless_functional_run_remains_available_without_performance_claim(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            artifacts(path, rendered=False)
            result = report(path, write=False)
            self.assertTrue(_case_success(result))
            self.assertTrue(result["requested_headless"])
            self.assertEqual(result["rendering"]["status"], "not_requested")
            self.assertEqual(result["performance"], "not_qualified")
            self.assertTrue(_tour_success({"data": "valid", "coverage": "complete", "cases": [result]}))

    def test_positive_requested_render_evidence_is_accepted(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            artifacts(path)
            result = report(path, write=False)
            self.assertTrue(_case_success(result))
            self.assertEqual(result["rendering"]["status"], "complete")
            self.assertTrue(result["rendered"])

    def test_original_graphics_request_cannot_be_rewritten_as_headless(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            artifacts(path)
            resolved = json.loads((path / "manifest.resolved.json").read_text())
            resolved["headless"] = True
            write_json(path / "manifest.resolved.json", resolved)
            runtime = json.loads((path / "runtime.json").read_text())
            runtime["metrics"]["rendered"] = False
            runtime["phases"][0]["rendered"] = False
            write_json(path / "runtime.json", runtime)
            result = report(path, write=False)
            self.assertFalse(result["requested_headless"])
            self.assertEqual((result["data"], result["coverage"]), ("ineligible", "partial"))
            self.assertFalse(_case_success(result))
            self.assertIn("original requested and resolved workloads differ", result["issues"])

    def test_positive_runtime_booleans_cannot_replace_raw_draw_evidence(self):
        for fault in ("undrawable", "no_draws", "missing"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "run"
                frames = artifacts(path)
                stream_path = path / frames["stream"]["file"]
                rows = [json.loads(line) for line in stream_path.read_text().splitlines()]
                metrics = rows[1]["metrics"]
                if fault == "undrawable": metrics["render_window_drawable"] = [0, 0]
                elif fault == "no_draws":
                    metrics["render_frames_drawn"] = [0, 0]
                    metrics["render_interval_draws"] = [0, 0]
                else:
                    for key in tuple(metrics):
                        if key.startswith("render_"): metrics.pop(key)
                raw = b"".join((json.dumps(row) + "\n").encode() for row in rows)
                stream_path.write_bytes(raw)
                frames["stream"].update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
                write_json(path / "frametimes.json", frames)
                result = report(path, write=False)
                self.assertEqual(result["rendering"]["status"], "incomplete")
                self.assertFalse(_case_success(result))
                self.assertIn("raw draw evidence", " ".join(result["issues"]))

    def test_absent_or_invalid_requested_mode_never_becomes_a_headless_success(self):
        for requested in (None, 0, "false"):
            with self.subTest(requested=requested), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "run"
                artifacts(path)
                manifest = json.loads((path / "manifest.resolved.json").read_text())
                if requested is None:
                    manifest.pop("headless")
                else:
                    manifest["headless"] = requested
                write_json(path / "manifest.resolved.json", manifest)
                result = report(path, write=False)
                self.assertFalse(_case_success(result))
                self.assertEqual(result["coverage"], "partial")

    def test_cli_rejects_ambiguous_summaries_and_missing_render_evidence(self):
        legacy = {"data": "valid", "coverage": "complete", "rendered": False}
        for case in (legacy, dict(legacy, requested_headless=False),
                     dict(legacy, requested_headless=False, rendered=True)):
            with self.subTest(case=case):
                self.assertFalse(_case_success(case))
                self.assertFalse(_tour_success({"data": "valid", "coverage": "complete",
                                               "performance": "screen_only", "cases": [case]}))


if __name__ == "__main__":
    unittest.main()
