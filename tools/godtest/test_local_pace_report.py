"""Exercise raw stream → child report → suite projection for local pace."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import catalog
from analysis import report
from runner import read_json, write_json
from test_godtest import artifacts
from tour_report import _html, _phase_rows


def flight_artifacts(path: Path, ticks: list[int], *, split=512, channels=True):
    frames = artifacts(path)
    manifest = catalog.scenario("startup", {"phases": ["recover", "shutdown"], "start": "airborne"})
    write_json(path / "manifest.requested.json", manifest)
    write_json(path / "manifest.resolved.json", dict(manifest, output_dir=str(path)))
    count = len(ticks)
    ends = [1_000_000 + index * 10_000 for index in range(count)]
    records = [{"type": "header", "format": "openrc-frame-stream v1"}]
    for start in range(0, count, split):
        stop = min(count, start + split)
        size = stop - start
        metrics = {"phase_index": [0] * size, "render_frames_drawn": list(range(start + 1, stop + 1)),
                   "render_interval_draws": [1] * size, "render_window_drawable": [1] * size}
        if channels:
            metrics.update(sim_tick=ticks[start:stop], sim_time_s=[tick * (1 / 240) for tick in ticks[start:stop]],
                           paused=[0] * size, crashed=[0] * size)
        records.append({"type": "chunk", "sequence": len(records) - 1, "start_frame": start, "frames": size,
                        "wall_usec": [10_000] * size, "end_usec": ends[start:stop],
                        "engine_delta_s": [.01] * size, "metrics": metrics})
    chunks = len(records) - 1
    records.append({"type": "trailer", "frames": count, "chunks": chunks, "complete": True})
    raw = b"".join((json.dumps(row) + "\n").encode() for row in records)
    (path / frames["stream"]["file"]).write_bytes(raw)
    frames["frames"] = count
    frames["stream"].update(frames=count, chunks=chunks, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
    write_json(path / "frametimes.json", frames)
    runtime = read_json(path / "runtime.json")
    runtime["phases"][0].update(name="recover", id="0-0-recover", start_usec=990_000, end_usec=ends[-1],
                               start_tick=ticks[0], end_tick=ticks[-1],
                               wall_seconds=count * .01, sim_seconds=(ticks[-1] - ticks[0]) / 240,
                               frames=count)
    write_json(path / "runtime.json", runtime)


class LocalPaceReportTests(unittest.TestCase):
    def test_equal_total_does_not_hide_slowdown_and_catchup_in_reports(self):
        ticks = [round(index * 1.2) if index <= 500 else 600 + round((index - 500) * 3.6)
                 for index in range(1001)]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            flight_artifacts(path, ticks)
            result = report(path)
            self.assertEqual(result["data"], "valid", result["issues"])
            target = result["targets"][0]
            self.assertTrue(target["simulation_pace_target_met"])
            self.assertTrue(target["p95_within_18ms"])
            self.assertFalse(target["local_simulation_pace_target_met"])
            self.assertAlmostEqual(target["worst_local_simulation_wall_ratio"], .5)
            self.assertAlmostEqual(target["fastest_local_simulation_wall_ratio"], 1.5)
            self.assertAlmostEqual(target["maximum_observed_simulation_lag_seconds"], 2.5)
            rows = _phase_rows(result["phases"], result["targets"])
            self.assertEqual(rows[0]["screen_target_status"], "missed")
            self.assertAlmostEqual(rows[0]["worst_local_simulation_wall_ratio"], .5)
            suite = {"data": "valid", "coverage": "complete", "performance": "not_qualified", "issues": [],
                     "repeat_summaries": [], "cases": [{"number": 1, "aircraft": result["aircraft"],
                                                         "phases": rows}]}
            for html in ((path / "report.html").read_text(), _html(suite, path)):
                self.assertIn("Simulation pace and screen targets", html)
                self.assertIn("missed", html)
                self.assertIn("0.50", html)
                self.assertIn("2.50", html)

    def test_partial_tail_cannot_hide_a_stall_behind_healthy_full_windows(self):
        ticks = [round(index * 2.4) if index <= 1000 else 2400 if index <= 1040
                 else 2400 + round((index - 1040) * 4.8) for index in range(1081)]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            flight_artifacts(path, ticks)
            result = report(path)
            target = result["targets"][0]
            self.assertEqual(result["data"], "valid", result["issues"])
            self.assertTrue(target["simulation_pace_target_met"])
            self.assertAlmostEqual(target["worst_local_simulation_wall_ratio"], 1)
            self.assertAlmostEqual(target["maximum_observed_simulation_lag_seconds"], .4)
            self.assertIsNone(target["local_simulation_pace_target_met"])
            self.assertEqual(target["local_simulation_pace_target_reason"], "partial_tail_unscored")
            self.assertEqual(target["screen_target_status"], "inconclusive")

    def test_missing_legacy_channels_preserve_frames_without_a_local_pace_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            flight_artifacts(path, [round(index * 2.4) for index in range(1001)], channels=False)
            result = report(path)
            self.assertEqual(result["data"], "valid", result["issues"])
            target = result["targets"][0]
            self.assertEqual(target["local_simulation_pace_status"], "unavailable_missing_channels")
            self.assertIsNone(target["local_simulation_pace_target_met"])
            self.assertEqual(target["screen_target_status"], "inconclusive")

    def test_steady_complete_windows_and_chunk_boundaries_have_identical_results(self):
        ticks = [round(index * 2.4) for index in range(1001)]
        with tempfile.TemporaryDirectory() as temporary:
            results = []
            for split in (37, 512):
                path = Path(temporary) / str(split)
                flight_artifacts(path, ticks, split=split)
                result = report(path, write=False)
                self.assertEqual(result["data"], "valid", result["issues"])
                self.assertTrue(result["targets"][0]["local_simulation_pace_target_met"])
                self.assertEqual(result["targets"][0]["screen_target_status"], "met_observed_screen")
                results.append(result)
            self.assertEqual(results[0]["targets"], results[1]["targets"])
            self.assertEqual(results[0]["phases"][0]["simulation_pace"], results[1]["phases"][0]["simulation_pace"])

    def test_projection_does_not_overwrite_distinct_indices_with_duplicate_labels(self):
        phases = [{"index": index, "id": "duplicate", "name": "recover", "cycle": 0,
                   "requested": True, "status": "complete"} for index in (4, 5)]
        targets = [{"phase_index": 4, "phase_id": "duplicate", "screen_target_status": "missed", "simulation_wall_ratio": .5},
                   {"phase_index": 5, "phase_id": "duplicate", "screen_target_status": "met_observed_screen", "simulation_wall_ratio": 1}]
        rows = _phase_rows(phases, targets)
        self.assertEqual([row["simulation_wall_ratio"] for row in rows], [.5, 1])
        self.assertEqual([row["screen_target_status"] for row in rows], ["missed", "met_observed_screen"])


if __name__ == "__main__":
    unittest.main()
