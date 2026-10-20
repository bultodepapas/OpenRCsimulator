from __future__ import annotations

import csv
import json
import tempfile
import unittest
from pathlib import Path

from analyze_reachable_plans import analyze, read_event_groups, synchronized_piecewise_minimum


def event(kind: str, value: dict) -> str:
    return kind + " " + json.dumps(value, separators=(",", ":"))


class ReachablePlanAnalysisTests(unittest.TestCase):
    def test_groups_hold_retarget_release_and_next_flight(self) -> None:
        initial = {"tick": 0, "selected_bank_deg": 10.0,
                   "predicted_threat_distance_traces": []}
        retarget = {"tick": 240, "selected_bank_deg": -5.0,
                    "predicted_threat_distance_traces": []}
        lines = [
            event("AFC_REACHABLE_MANEUVER", {"action": "hold", "tick": 0}),
            event("AFC_REACHABLE_INITIAL", initial),
            event("AFC_REACHABLE_MANEUVER", {"action": "retarget", "tick": 240}),
            event("AFC_REACHABLE_PLAN", retarget),
            event("AFC_REACHABLE_MANEUVER", {"action": "release", "tick": 480}),
            event("AFC_REACHABLE_MANEUVER", {"action": "hold", "tick": 0}),
            event("AFC_REACHABLE_INITIAL", initial),
        ]
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "engine.log"
            log.write_text("\n".join(lines), encoding="utf-8")
            groups = read_event_groups(log)
        self.assertEqual(len(groups), 2)
        self.assertEqual([plan["kind"] for plan in groups[0]["plans"]], ["initial", "retarget"])
        self.assertEqual([entry["action"] for entry in groups[0]["maneuvers"]],
                         ["hold", "retarget", "release"])
        self.assertEqual(len(groups[1]["plans"]), 1)

    def test_clipped_piecewise_minimum_uses_exact_relative_segment(self) -> None:
        a = [
            {"time_s": 0.0, "north_m": 0.0, "east_m": 0.0, "altitude_m": 0.0},
            {"time_s": 1.0, "north_m": 10.0, "east_m": 0.0, "altitude_m": 0.0},
        ]
        b = [
            {"time_s": 0.0, "north_m": 5.0, "east_m": 0.0, "altitude_m": 0.0},
            {"time_s": 1.0, "north_m": 5.0, "east_m": 0.0, "altitude_m": 0.0},
        ]
        result = synchronized_piecewise_minimum(a, b, 0.25, 0.75)
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result["distance_m"], 0.0)
        self.assertAlmostEqual(result["time_s"], 0.5)

    def test_end_to_end_residual_stops_at_release(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            report = root / "report.json"
            trajectory = root / "trajectory.csv"
            log = root / "engine.log"
            candidate = root / "candidate.gd"
            parent = root / "parent.gd"
            output = root / "analysis.json"
            report.write_text(json.dumps({"cases": [{
                "case_id": "case-one",
                "separation_gate_passed": True,
                "min_separation_to_player_m": 4.0,
            }]}), encoding="utf-8")
            with trajectory.open("w", newline="", encoding="utf-8") as source:
                writer = csv.writer(source)
                writer.writerow(["case", "time_s", "role", "north_m", "east_m", "altitude_m"])
                for index in range(11):
                    time_s = index / 10.0
                    writer.writerow(["case-one", time_s, "ai", time_s, 0.0, 0.0])
                    writer.writerow(["case-one", time_s, "player", 5.0, 0.0, 0.0])
            initial = {
                "tick": 0,
                "selected_bank_deg": 10.0,
                "held_bank_deg": 10.0,
                "prediction_wind_ned_m_s": [0.0, 0.0, 0.0],
                "prediction_air_speed_m_s": 15.0,
                "predicted_threat_distance_traces": [{
                    "id": "player", "distance_m": [5.0, 4.75, 4.5],
                }],
            }
            log.write_text("\n".join([
                event("AFC_REACHABLE_MANEUVER", {"action": "hold", "tick": 0}),
                event("AFC_REACHABLE_INITIAL", initial),
                event("AFC_REACHABLE_MANEUVER", {"action": "release", "tick": 120}),
            ]), encoding="utf-8")
            candidate.write_text("candidate", encoding="utf-8")
            parent.write_text("parent", encoding="utf-8")
            result = analyze(report, trajectory, log, candidate, parent)
        threat = result["cases"][0]["plans"][0]["threats"][0]
        self.assertEqual(threat["matched_prediction_sample_count"], 3)
        self.assertAlmostEqual(threat["overlap_end_s"], 0.5)
        self.assertAlmostEqual(threat["actual_piecewise_linear_minimum_m"], 4.5)
        self.assertAlmostEqual(threat["sampled_forecast_minimum_minus_actual_minimum_m"], 0.0)
        self.assertEqual(result["overall_sample_residuals_m"]["count"], 3)


if __name__ == "__main__":
    unittest.main()
