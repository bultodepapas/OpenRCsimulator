"""Graphics requests cannot pass by losing the runtime's rendered flag."""
from __future__ import annotations

import json
import hashlib
from pathlib import Path
import tempfile
import unittest

from analysis import _dynamic_resolution_problem, report
from godtest import _case_success, _tour_success
from runner import write_json
from test_godtest import artifacts, replace_stream


class RenderingEvidenceTests(unittest.TestCase):
    def test_dynamic_resolution_uses_a_pixel_safe_floor_on_retina(self):
        output = [3456, 2234]
        scale = 1676.5 / 2234
        frame = {"frame_id": 4, "generation": 3, "recorded_usec": 3,
                 "input_size": [2593, 1676], "output_size": output}
        status = {"target_fps": 30, "configured_scale": scale, "state": "observing",
                  "completed_frame": frame}
        phase = {"id": "recover", "start_usec": 1, "end_usec": 100,
                 "dynamic_resolution": [{"phase_id": "recover", "observed_usec": 5, "status": status}],
                 "dynamic_resolution_end": dict(frame, frame_id=6, recorded_usec=99)}
        manifest = {"dynamic_resolution_fps": 30, "resolution": output, "render_scale": 85}
        self.assertEqual(_dynamic_resolution_problem(phase, manifest), "")
        frame["input_size"] = [2592, 1675]
        status["configured_scale"] = 0.75
        self.assertEqual(_dynamic_resolution_problem(phase, manifest),
                         "completed pixels do not match an allowed scale")

    def test_dynamic_resolution_requires_a_confirmed_frame_and_allows_holding_the_ceiling(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            artifacts(path)
            for name in ("manifest.requested.json", "manifest.resolved.json"):
                manifest = json.loads((path / name).read_text())
                manifest.update(dynamic_resolution_fps=60, render_scale=100, phases=["recover"])
                write_json(path / name, manifest)
            runtime = json.loads((path / "runtime.json").read_text())
            runtime["identity"]["effective_display"] = {"dynamic_resolution_fps": 60, "render_scale": 100}
            phase = runtime["phases"][0]
            phase.update(name="recover", id="0-0-recover", start_usec=1, end_usec=100)
            frame = {"frame_id": 4, "generation": 3, "recorded_usec": 3,
                     "input_size": [1920, 1080], "output_size": [1920, 1080]}
            phase["dynamic_resolution_end"] = dict(frame, frame_id=6, recorded_usec=99)
            for status, eligible in (
                ({"state": "observing", "completed_frame": frame}, True),
                ({"state": "observing"}, False),
                ({"state": "observing", "completed_frame": dict(frame, input_size=[1632, 918])}, False),
                ({"state": "fixed", "reason": "gpu_feedback_expired"}, False),
            ):
                with self.subTest(status=status):
                    phase["dynamic_resolution"] = [{"phase_id": phase["id"], "observed_usec": 5,
                                                     "status": {"target_fps": 60, "configured_scale": 1.0, **status}}]
                    write_json(path / "runtime.json", runtime)
                    result = report(path, write=False)
                    self.assertEqual(result["data"] == "valid", eligible, result["issues"])
                    if not eligible:
                        self.assertIn("dynamic resolution not verified", " ".join(result["issues"]))
            eligible_status = {"target_fps": 60, "configured_scale": 1.0, "state": "observing", "completed_frame": frame}
            phase["dynamic_resolution"] = [{"phase_id": phase["id"], "observed_usec": 5, "status": eligible_status}]
            for closing in (None, dict(frame, recorded_usec=0), dict(frame, generation=2)):
                phase["dynamic_resolution_end"] = closing
                write_json(path / "runtime.json", runtime)
                self.assertIn("dynamic resolution not verified", " ".join(report(path, write=False)["issues"]))
            phase["dynamic_resolution_end"] = dict(frame, frame_id=6, recorded_usec=99)
            waiting = {"phase_id": phase["id"], "observed_usec": 2,
                       "status": {"state": "awaiting_controller", "target_fps": 60}}
            phase["dynamic_resolution"].insert(0, waiting)
            write_json(path / "runtime.json", runtime)
            self.assertEqual(report(path, write=False)["data"], "valid")
            phase["dynamic_resolution"].append(dict(waiting, observed_usec=70))
            write_json(path / "runtime.json", runtime)
            self.assertIn("dynamic resolution not verified", " ".join(report(path, write=False)["issues"]))
            phase["dynamic_resolution"].pop()
            phase["dynamic_resolution"][1]["observed_usec"] = 110_000
            phase["end_usec"] = 160_000
            phase["dynamic_resolution_end"] = dict(frame, frame_id=6, recorded_usec=159_999)
            write_json(path / "runtime.json", runtime)
            self.assertIn("controller activation did not cover", " ".join(report(path, write=False)["issues"]))

    def test_explicit_render_scale_requires_matching_bilinear_receipts_at_both_boundaries(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            artifacts(path)
            for name in ("manifest.requested.json", "manifest.resolved.json"):
                manifest = json.loads((path / name).read_text())
                manifest.update(render_scale=67, phases=["recover"])
                write_json(path / name, manifest)
            runtime = json.loads((path / "runtime.json").read_text())
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
