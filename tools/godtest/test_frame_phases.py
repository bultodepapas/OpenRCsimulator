"""Offline phase-split reports for GOD TEST frame streams; no Godot process is launched."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from tools.godtest import frame_phases

DURATIONS = frame_phases.DURATIONS


def _row(wall: int, phases: dict[str, int], ticks: int, valid: int = 1, drawn: int = 1, phase_index: int = 3) -> dict:
    row = {f"phase_{key}_usec": phases.get(key, 0) for key in DURATIONS}
    row.update({"phase_valid": valid, "phase_drawn": drawn, "phase_ticks": ticks,
                "phase_tick_scripts_usec": phases.get("physics", 0) // 2, "phase_tick_max_usec": 700,
                "monitor_process_s": 0.002, "monitor_physics_process_s": 0.001, "phase_index": phase_index})
    row["_wall"] = wall
    return row


def _write_case(directory: Path, rows: list[dict]) -> None:
    keys = [key for key in rows[0] if key != "_wall"]
    end = 1_000_000
    walls, ends = [], []
    for row in rows:
        end += row["_wall"]
        walls.append(row["_wall"])
        ends.append(end)
    chunk = {"type": "chunk", "sequence": 0, "start_frame": 0, "frames": len(rows), "wall_usec": walls,
             "end_usec": ends, "engine_delta_s": [0.004] * len(rows),
             "metrics": {key: [row[key] for row in rows] for key in keys}}
    lines = [{"type": "header", "format": "openrc-frame-stream v1"}, chunk, {"type": "trailer", "complete": True}]
    (directory / frame_phases.STREAM_NAME).write_text("".join(json.dumps(line) + "\n" for line in lines), encoding="utf-8")
    (directory / "runtime.json").write_text(json.dumps({"phases": [{"index": 3, "name": "runway_circuit"}]}), encoding="utf-8")


def _typical() -> dict:
    return {"tail_process": 100, "tail_engine": 200, "render": 2000, "between": 500, "physics": 1000,
            "after_physics": 100, "pre_process": 100, "process": 2000}


class FramePhaseReportTest(unittest.TestCase):
    def test_slow_frame_excess_lands_in_its_phase(self):
        typical = _typical()
        render_spike = dict(typical, render=12000)
        catch_up = dict(typical, physics=5000)
        rows = [_row(6000, typical, 1) for _ in range(9)]
        rows.append(_row(16000, render_spike, 1))
        rows.append(_row(10000, catch_up, 5))
        rows.append(_row(30000, typical, 0, valid=0))  # incomplete boundaries are excluded
        for row in rows[:-1]:
            self.assertEqual(sum(row[f"phase_{key}_usec"] for key in DURATIONS), row["_wall"])
        with tempfile.TemporaryDirectory() as folder:
            _write_case(Path(folder), rows)
            [result] = frame_phases.analyse(Path(folder), "runway_circuit", (9.0, 15.0))
        self.assertEqual((result["frames"], result["valid"]), (12, 11))
        self.assertEqual(result["typical"]["phases_ms"]["render"], 2.0)
        above_nine, above_fifteen = result["slow"]
        self.assertEqual(above_nine["frames"], 2)
        self.assertEqual(above_fifteen["frames"], 1)
        self.assertEqual(above_fifteen["largest_excess"], "render")
        # Mean over valid frames: (10 x 2.0 + 12.0) / 11 ms; the slow frame's excess is 12.0 minus that.
        self.assertAlmostEqual(above_fifteen["excess_mean_ms"]["render"], 12.0 - 32.0 / 11, places=3)
        self.assertAlmostEqual(sum(above_fifteen["excess_mean_ms"].values()),
                               16.0 - (9 * 6.0 + 16.0 + 10.0) / 11, places=2)
        self.assertEqual(above_nine["ticks"]["max"], 5)

    def test_rejects_a_split_that_does_not_sum_to_its_interval(self):
        rows = [_row(9999, _typical(), 1)]
        with tempfile.TemporaryDirectory() as folder:
            _write_case(Path(folder), rows)
            with self.assertRaisesRegex(ValueError, "sum to"):
                frame_phases.analyse(Path(folder))

    def test_streams_without_phase_metrics_are_reported_not_guessed(self):
        rows = [{"_wall": 5000, "phase_index": 3, "sim_tick": 1}]
        with tempfile.TemporaryDirectory() as folder:
            _write_case(Path(folder), rows)
            [result] = frame_phases.analyse(Path(folder))
        self.assertEqual(result["phase_metrics"], "absent")
        self.assertIn("no phase metrics", frame_phases.render_text([result]))

    def test_missing_stream_is_an_error(self):
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(frame_phases.main([folder]), 2)


if __name__ == "__main__":
    unittest.main()
