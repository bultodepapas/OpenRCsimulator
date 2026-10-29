"""Failure controls for the mandatory fixed-brake reference gate."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import tempfile
import unittest

import fixed_brake_legacy as gate


class ComparisonTests(unittest.TestCase):
    def setUp(self) -> None:
        fixture_path = gate.ROOT / "app/tests/fixtures/fixed_brake_legacy_outputs.json"
        self.fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        self.reference = {
            "format": "openrc-fixed-brake-legacy-capture v1",
            "os": "Linux",
            "engine": self.fixture["engine"],
            "physics_hz": self.fixture["physics_hz"],
            "session_sha256": gate.SESSION_OLD,
            "trace_sha256": gate.TRACE_OLD,
            "outputs": {},
        }
        for name in gate.IDS:
            row = dict(self.fixture["outputs"][name])
            row.update(self.fixture.get("outputs_by_os", {}).get("Linux", {}).get(name, {}))
            row.update(checkpoint_value={"test": 1}, metadata_value={"test": "x"}, csv_value="row\n")
            self.reference["outputs"][name] = row

    def test_all_original_golden_digests_are_required(self) -> None:
        gate.check_goldens(self.reference, self.fixture)
        for aircraft in gate.IDS:
            for field in gate.FIELDS:
                changed = copy.deepcopy(self.reference)
                changed["outputs"][aircraft][field] = "0" * 64
                with self.subTest(aircraft=aircraft, field=field), self.assertRaises(ValueError):
                    gate.check_goldens(changed, self.fixture)

    def test_every_candidate_digest_and_full_value_is_required(self) -> None:
        gate.check_comparison(self.reference, self.reference)
        for aircraft in gate.IDS:
            for field in gate.FIELDS:
                changed = copy.deepcopy(self.reference)
                changed["outputs"][aircraft][field] = "0" * 64
                with self.subTest(aircraft=aircraft, field=field), self.assertRaises(ValueError):
                    gate.check_comparison(self.reference, changed)
            for field in ("checkpoint_value", "metadata_value", "csv_value"):
                changed = copy.deepcopy(self.reference)
                changed["outputs"][aircraft][field] = "different"
                with self.subTest(aircraft=aircraft, field=field), self.assertRaises(ValueError):
                    gate.check_comparison(self.reference, changed)

    def test_bad_host_missing_aircraft_and_missing_values_fail(self) -> None:
        for mutation in ("host", "missing_aircraft", "missing_full_value", "bad_digest", "old_owner"):
            capture = copy.deepcopy(self.reference)
            row = capture["outputs"][sorted(gate.IDS)[0]]
            if mutation == "host": capture["os"] = "unknown"
            if mutation == "missing_aircraft": capture["outputs"].pop(sorted(gate.IDS)[0])
            if mutation == "missing_full_value": row.pop("csv_value")
            if mutation == "bad_digest": row["checkpoint"] = "g" * 64
            if mutation == "old_owner": capture["session_sha256"] = "0" * 64
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "capture.json"
                path.write_text(json.dumps(capture), encoding="utf-8")
                with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                    gate.load_capture(path, self.fixture, True)

    def test_unpinned_fuel_or_avanti_content_fails(self) -> None:
        fuel = (gate.ROOT / "app/data/fuels/openrc-fuel-registry.json").read_bytes()
        avanti = (gate.ROOT / "app/data/aircraft/sebart_avanti_s_a200.json").read_bytes()
        gate.check_input_bytes(fuel, avanti)
        for fuel_case, avanti_case in ((fuel + b" ", avanti), (fuel, avanti + b" ")):
            with self.assertRaises(ValueError):
                gate.check_input_bytes(fuel_case, avanti_case)

    def test_candidate_inventory_tracks_current_paths_and_detects_drift(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            for name in ("main.gd", "project.godot", "data/aircraft/moonrunner_x99.json",
                         "data/fuels/openrc-fuel-registry.json", "tests/fixtures/fixed_brake_legacy_outputs.json",
                         "tests/test_fixed_gear_brake_input.gd"):
                path = app / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("before", encoding="utf-8")
            before = gate.candidate_manifest(app)
            self.assertIn("data/aircraft/moonrunner_x99.json", before)
            self.assertNotIn("data/aircraft/skywalker_x8.json", before)
            (app / "data/aircraft/moonrunner_x99.json").write_text("after", encoding="utf-8")
            self.assertNotEqual(before, gate.candidate_manifest(app))


if __name__ == "__main__":
    unittest.main()
