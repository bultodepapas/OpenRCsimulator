from __future__ import annotations

import copy
import csv
import io
import json
import math
from pathlib import Path
import re
import tempfile
import unittest
from unittest import mock

if __package__:
    from . import frame_capture as capture
else:
    import frame_capture as capture

HERE = Path(__file__).resolve().parent


def make_report(walls=None, flags=None, first=41, detail_sequences=()):
    walls = list(walls if walls is not None else [16_000, 60_000, 100_000, 18_000])
    flags = list(flags if flags is not None else [0, 1 | 4 | 8, 1 | 2 | 8 | 16, 8])
    n = len(walls)
    total = first + n - 1
    start = 1_000_000
    ends = []
    for wall in walls:
        start += wall
        ends.append(start)
    s = {
        "end_usec": ends, "wall_usec": walls,
        "process_frame": list(range(first + 200, first + 200 + n)),
        "physics_ticks": [1] * n, "gpu_ms": [-1.0] * n,
        "baseline_ms": [10.0] * n, "flags": flags,
        "observer_usec": [25] * n, "route": ["home"] * n,
    }
    if n >= 2:
        s["gpu_ms"][1] = 2.25
    report = {
        "format": capture.FORMAT, "version": 1, "clock": "godot_ticks_usec",
        "timing_scope": "bridge_process_wall_intervals_not_presentation",
        "capture_id": "1234-5678-2", "epoch": 2,
        "frames": n, "first_sequence": first, "last_sequence": total,
        "frames_total": total, "retained_frames": min(total, capture.MAX_FRAMES),
        "frames_evicted": max(0, total - capture.MAX_FRAMES),
        "sample_start_usec": 1_000_000, "sample_end_usec": ends[-1],
        "duration_s": sum(walls) / 1_000_000,
        "target_fps": 60.0, "budget_ms": 1000 / 60, "budget_tolerance_ms": 1.0,
        "slow_threshold_ms": 1000 / 60 + 1,
        "hitch_ms": 50.0, "factor": 3.0, "stutter_factor": 1.5,
        "stutter_min_extra_ms": 4.0, "stall_ms": 80.0,
        "flag_bits": dict(capture.FLAG_BITS),
        "source": {"display_server": "headless", "rendering_method": "gl_compatibility"},
        "samples": s, "hitches": [], "stutters": [],
        "relative_stutter_frames": sum(bool(f & 1) for f in flags),
        "stall_frames": sum(bool(f & 2) for f in flags),
        "hitch_frames": sum(bool(f & 4) for f in flags),
        "over_budget_frames": sum(bool(f & 8) for f in flags),
        "diagnostic_query_frames": sum(bool(f & 16) for f in flags),
        "event_frames": sum(bool(f & 7) for f in flags),
    }
    for seq in detail_sequences:
        i = seq - first
        detail = {
            "sequence": seq, "epoch": 2, "frame": s["process_frame"][i],
            "start_usec": ends[i] - walls[i], "end_usec": ends[i], "ms": walls[i] / 1000,
            "flags": flags[i], "physics_ticks": s["physics_ticks"][i],
            "baseline_ms": s["baseline_ms"][i], "diagnostic_query": bool(flags[i] & 16),
            "causes": ["counter changed (correlation only)"], "deltas": {"nodes": 2},
            "log": ["context line"], "route_from": "home", "route": "flight",
        }
        report["stutters"].append(detail)
        if flags[i] & 4:
            report["hitches"].append(copy.deepcopy(detail))
    report["event_returned"] = len(report["stutters"])
    report["hitch_returned"] = len(report["hitches"])
    report["event_details_omitted_in_window"] = report["event_frames"] - len(report["stutters"])
    return report


class FrameCaptureTests(unittest.TestCase):
    def test_bundle_preserves_source_and_ring_order(self):
        report = make_report(first=7198, detail_sequences=[7199, 7200])
        before = copy.deepcopy(report)
        with tempfile.TemporaryDirectory(prefix="openrc-frame-capture-") as temp:
            out = Path(temp) / "capture"
            paths = capture.write_capture(report, out)
            self.assertEqual(set(paths), {"json", "csv", "perfetto", "html"})
            self.assertEqual(report, before)
            self.assertEqual(json.loads(Path(paths["json"]).read_text()), before)
            rows = list(csv.DictReader(io.StringIO(Path(paths["csv"]).read_text())))
            self.assertEqual([int(r["sequence"]) for r in rows], [7198, 7199, 7200, 7201])
            self.assertEqual([int(r["end_usec"]) for r in rows], before["samples"]["end_usec"])
            self.assertEqual([int(r["flags"]) for r in rows], before["samples"]["flags"])
            self.assertEqual([json.loads(r["route_json"]) for r in rows], ["home"] * 4)
            self.assertEqual(int(rows[0]["relative_start_usec"]), 0)
            self.assertEqual(int(rows[1]["relative_start_usec"]), 16_000)
            self.assertTrue(all(Path(p).parent == out for p in paths.values()))

    def test_trace_uses_microseconds_and_preserves_sparse_detail(self):
        report = make_report(detail_sequences=[42, 43])
        # A query limiting returned stutter details can omit an older hitch,
        # while the separate hitch list still retains that older record.
        report["stutters"] = report["stutters"][1:]
        report["event_returned"] = 2
        report["event_details_omitted_in_window"] = 0
        trace = capture.build_trace(report)
        slices = [e for e in trace if e["ph"] == "X"]
        self.assertEqual([e["ts"] for e in slices], [0, 16_000, 76_000, 176_000])
        self.assertEqual([e["dur"] for e in slices], [16_000, 60_000, 100_000, 18_000])
        self.assertEqual([e["args"]["flags"] for e in slices], report["samples"]["flags"])
        self.assertEqual(slices[1]["args"]["gpu_last_read_ms"], 2.25)
        self.assertNotIn("gpu_last_read_ms", slices[0]["args"])
        self.assertTrue(all(e["name"] == "frame wall interval" for e in slices))
        counters = [e for e in trace if e["ph"] == "C" and e["name"] == "frame.flags [bitmask]"]
        self.assertEqual([e["args"]["value"] for e in counters], report["samples"]["flags"])
        events = [e for e in trace if e["ph"] == "I" and e["cat"] == "stutter"]
        self.assertEqual([e["args"]["sequence"] for e in events], [42, 43])
        self.assertTrue(all(e["args"]["detail_retained"] for e in events))
        dishonest = copy.deepcopy(report)
        dishonest["event_details_omitted_in_window"] = 1
        with self.assertRaises(capture.CaptureError):
            capture.build_trace(dishonest)
        query = [e for e in trace if e["ph"] == "I" and e["cat"] == "diagnostics"]
        self.assertEqual(len(query), 1)
        self.assertEqual(query[0]["args"]["sequence"], 43)
        metadata = next(e["args"] for e in trace if e["name"] == "capture_metadata")
        self.assertIn("no cross-process correlation", metadata["clock"])
        self.assertIn("not proof of a GPU bottleneck", metadata["gpu"])
        self.assertNotIn("sim_tick", json.dumps(trace))
        self.assertFalse(any("present" in e["name"].lower() or "gpu" in e["name"].lower()
                             for e in slices))

    def test_fully_suppressed_event_details_still_emit_flag_markers(self):
        report = make_report()
        trace = capture.build_trace(report)
        markers = [e for e in trace if e["ph"] == "I" and e["cat"] == "stutter"]
        self.assertEqual(len(markers), 2)
        self.assertTrue(all(not m["args"]["detail_retained"] for m in markers))
        self.assertTrue(all("detail" not in m["args"] for m in markers))
        with tempfile.TemporaryDirectory(prefix="openrc-frame-capture-") as temp:
            paths = capture.write_capture(report, Path(temp) / "capture")
            rendered = Path(paths["html"]).read_text()
            self.assertIn("2 flagged frame(s) have no detail", rendered)
            self.assertIn("headless", rendered)
            self.assertIn("Headless runs cannot establish rendering", rendered)
            self.assertIn("below 100 frames; short tail", rendered)
            self.assertIn("below 1,000 frames; short tail", rendered)
            self.assertIn("using 1 frame(s)", rendered)

    def test_large_stall_log_plot_and_short_sample(self):
        report = make_report(walls=[16_000, 3_000_000_000, 32_000], flags=[0, 1 | 2 | 8, 8])
        with tempfile.TemporaryDirectory(prefix="openrc-frame-capture-") as temp:
            paths = capture.write_capture(report, Path(temp) / "capture")
            rendered = Path(paths["html"]).read_text()
            self.assertIn('type="checkbox" checked', rendered)
            self.assertIn("Logarithmic vertical scale", rendered)
            self.assertIn("Math.log10(1+v)", rendered)
            self.assertIn("Horizontal spacing is by frame sequence", rendered)
            match = re.search(r'<script type="application/json" id="capture-data">(.*?)</script>', rendered, re.S)
            self.assertIsNotNone(match)
            data = json.loads(match.group(1))
            self.assertEqual(data["wall"], [16.0, 3_000_000.0, 32.0])
            self.assertEqual(data["relative_end_s"], [.016, 3000.016, 3000.048])

    def test_escapes_untrusted_text_and_csv_route(self):
        report = make_report(detail_sequences=[42])
        attack = '</script><img src=x onerror=alert(1)>&\u2028\u2029@@WORST@@'
        report["capture_id"] = attack
        report["samples"]["route"][1] = '=HYPERLINK("https://bad.example")' + attack
        for collection in ("stutters", "hitches"):
            report[collection][0]["log"] = [attack]
        with tempfile.TemporaryDirectory(prefix="openrc-frame-capture-") as temp:
            paths = capture.write_capture(report, Path(temp) / "capture")
            rendered = Path(paths["html"]).read_text()
            self.assertNotIn('<img src=x onerror=', rendered)
            self.assertIn('&lt;/script&gt;&lt;img src=x onerror=alert(1)&gt;&amp;&#8232;&#8233;@@WORST@@', rendered)
            self.assertEqual(rendered.count('<script'), 2)
            self.assertNotIn('innerHTML', rendered)
            self.assertNotIn('<script src=', rendered)
            rows = list(csv.DictReader(io.StringIO(Path(paths["csv"]).read_text())))
            self.assertTrue(rows[1]["route_json"].startswith('"'))
            self.assertEqual(json.loads(rows[1]["route_json"]), report["samples"]["route"][1])

    def test_existing_output_is_never_changed(self):
        report = make_report()
        with tempfile.TemporaryDirectory(prefix="openrc-frame-capture-") as temp:
            out = Path(temp) / "capture"
            out.mkdir()
            marker = out / "frames.json"
            marker.write_text("original")
            with self.assertRaises(FileExistsError):
                capture.write_capture(report, out)
            self.assertEqual(marker.read_text(), "original")
            self.assertEqual(list(out.iterdir()), [marker])

    def test_io_failure_removes_only_created_output(self):
        report = make_report()
        original_open = Path.open

        def failing_open(path, *args, **kwargs):
            if path.name == "frames.perfetto.json":
                raise OSError("injected write failure")
            return original_open(path, *args, **kwargs)

        with tempfile.TemporaryDirectory(prefix="openrc-frame-capture-") as temp:
            out = Path(temp) / "capture"
            with mock.patch.object(Path, "open", failing_open):
                with self.assertRaisesRegex(OSError, "injected write failure"):
                    capture.write_capture(report, out)
            self.assertFalse(out.exists())

    def test_invalid_data_rejected_without_creating_directory(self):
        good = make_report(detail_sequences=[42, 43])
        mutations = {
            "unsupported format": lambda r: r.update(format="openrc-frametimes v2"),
            "zero frames": lambda r: r.update(frames=0),
            "oversized frames": lambda r: r.update(frames=7201),
            "boolean count": lambda r: r.update(frames=True),
            "wrong last": lambda r: r.update(last_sequence=500),
            "wrong total": lambda r: r.update(frames_total=8000),
            "missing column": lambda r: r["samples"].pop("route"),
            "short column": lambda r: r["samples"]["flags"].pop(),
            "boolean timestamp": lambda r: r["samples"]["end_usec"].__setitem__(0, True),
            "nonpositive start": lambda r: r["samples"]["wall_usec"].__setitem__(0, r["samples"]["end_usec"][0]),
            "gap": lambda r: r["samples"]["end_usec"].__setitem__(1, r["samples"]["end_usec"][1] + 1),
            "overlap": lambda r: r["samples"]["wall_usec"].__setitem__(1, r["samples"]["wall_usec"][1] + 1),
            "process frame reversal": lambda r: r["samples"]["process_frame"].__setitem__(1, 0),
            "nan": lambda r: r["samples"]["gpu_ms"].__setitem__(0, math.nan),
            "inf metadata": lambda r: r.update(duration_s=math.inf),
            "boolean number": lambda r: r["samples"]["physics_ticks"].__setitem__(0, False),
            "invalid gpu sentinel": lambda r: r["samples"]["gpu_ms"].__setitem__(0, 0),
            "bad flag": lambda r: r["samples"]["flags"].__setitem__(0, 32),
            "bad flag mapping": lambda r: r["flag_bits"].update(diagnostic_query=8),
            "bad duration": lambda r: r.update(duration_s=900.0),
            "bad threshold": lambda r: r.update(slow_threshold_ms=100),
            "out of window detail": lambda r: r["stutters"][0].update(sequence=40),
            "detail mismatches row": lambda r: r["stutters"][0].update(end_usec=1),
            "detail flags mismatch": lambda r: r["stutters"][0].update(flags=0),
            "detail ms mismatch": lambda r: r["stutters"][0].update(ms=1),
            "duplicate detail": lambda r: r["stutters"].append(copy.deepcopy(r["stutters"][-1])),
            "conflicting arrays": lambda r: r["hitches"][0].update(log=["different"]),
            "count mismatch": lambda r: r.update(event_frames=100),
            "huge metadata": lambda r: r.update(note="x" * (capture.MAX_STRING_CHARS + 1)),
            "invalid unicode": lambda r: r.update(note="\ud800"),
            "non-JSON": lambda r: r.update(note={1, 2}),
        }
        with tempfile.TemporaryDirectory(prefix="openrc-frame-capture-") as temp:
            for index, (name, mutate) in enumerate(mutations.items()):
                with self.subTest(name=name):
                    report = copy.deepcopy(good)
                    mutate(report)
                    out = Path(temp) / str(index)
                    with self.assertRaises(capture.CaptureError):
                        capture.write_capture(report, out)
                    self.assertFalse(out.exists())

    def test_cyclic_and_deep_metadata_are_bounded(self):
        for name in ("cyclic", "deep"):
            with self.subTest(name=name):
                report = make_report()
                nested = {}
                report["metadata"] = nested
                if name == "cyclic":
                    nested["self"] = nested
                else:
                    for _ in range(capture.MAX_DEPTH + 2):
                        nested["child"] = {}
                        nested = nested["child"]
                with self.assertRaises(capture.CaptureError):
                    capture.build_trace(report)

    def test_one_frame_and_exact_capacity(self):
        one = make_report(walls=[16_000], flags=[0], first=1)
        trace = capture.build_trace(one)
        self.assertEqual(len([e for e in trace if e["ph"] == "X"]), 1)
        maximum = make_report(walls=[16_000] * 7200, flags=[0] * 7200, first=2)
        trace = capture.build_trace(maximum)
        self.assertEqual(len([e for e in trace if e["ph"] == "X"]), 7200)
        self.assertEqual(trace[-1]["ts"], 7200 * 16_000)

    def test_trace_metadata_does_not_mutate_global_flag_mapping(self):
        trace = capture.build_trace(make_report())
        metadata = next(e for e in trace if e["name"] == "capture_metadata")
        metadata["args"]["flag_bits"]["relative_stutter"] = 99
        self.assertEqual(capture.FLAG_BITS["relative_stutter"], 1)


if __name__ == "__main__":
    unittest.main()
