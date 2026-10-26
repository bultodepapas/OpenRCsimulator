#!/usr/bin/env python3
"""Evidence acceptance must reject incomplete flights and inventory nested dependencies."""
from copy import deepcopy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import conformance


def complete_report():
    row = {"ok": True, "complete": True, "id": "specimen", "battery_mode": "ideal",
           "data_path": "res://data/aircraft/specimen.json", "soft_hull": False,
           "completed_ticks": 240, "replay_ticks": 120, "replay_exact": True,
           "model_sha256": "a" * 64, "initial_sha256": "b" * 64,
           "trajectory_sha256": "c" * 64,
           "samples": [{"tick": tick, "sha256": "d" * 64} for tick in [60, 120, 180, 240]]}
    return {"format": "openrc-as-fleet-probe v2", "ok": True, "complete": True,
            "ticks_per_case": 240, "replay_start_tick": 120, "expected_cases": 1, "cases": [row]}


class ConformanceEvidenceTests(unittest.TestCase):
    def test_complete_report_is_accepted(self):
        self.assertTrue(conformance.fleet_complete(complete_report()))

    def test_prefix_and_malformed_reports_are_rejected(self):
        report = complete_report()
        for key, value in [("complete", False), ("ok", False), ("expected_cases", 2),
                           ("format", "openrc-as-fleet-probe v1"), ("cases", [])]:
            with self.subTest(key=key):
                candidate = deepcopy(report)
                candidate[key] = value
                self.assertFalse(conformance.fleet_complete(candidate))
        for key, value in [("complete", False), ("ok", False), ("completed_ticks", 239),
                           ("replay_ticks", 119), ("replay_exact", False), ("data_path", ""),
                           ("battery_mode", "unknown"), ("trajectory_sha256", "bad"),
                           ("samples", [{"tick": 60, "sha256": "d" * 64}])]:
            with self.subTest(row_key=key):
                candidate = deepcopy(report)
                candidate["cases"][0][key] = value
                self.assertFalse(conformance.fleet_complete(candidate))
        report["cases"].append(deepcopy(report["cases"][0]))
        report["expected_cases"] = 2
        self.assertFalse(conformance.fleet_complete(report))

    def test_fingerprint_tracks_nested_data_and_model_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = ["app/physics/battery/pack_ecm.gd", "app/sim/ground_vehicle/session.gd",
                     "app/app_state/aircraft_catalog.gd", "app/failures/runtime.gd",
                     "app/data/aircraft/battery/specimen.json", "app/data/battery/packs/specimen.json",
                     "app/data/wheels/specimen.json", "app/project.godot",
                     "research/aircraft-standardization/fleet_probe.gd",
                     "research/aircraft-standardization/contact_probe.gd",
                     "research/aircraft-standardization/conformance.py"]
            for name in paths:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("baseline")
            with patch.object(conformance, "ROOT", root), patch.object(conformance, "APP", root / "app"):
                baseline = conformance.fingerprint()
                self.assertEqual(set(baseline), set(paths))
                for name in paths:
                    with self.subTest(path=name):
                        path = root / name
                        path.write_text("changed")
                        changed = conformance.fingerprint()
                        self.assertEqual([key for key in baseline if baseline[key] != changed[key]], [name])
                        path.write_text("baseline")


if __name__ == "__main__":
    unittest.main()
