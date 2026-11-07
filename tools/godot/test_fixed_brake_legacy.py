"""Failure controls for the mandatory fixed-brake reference gate."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

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

    def test_candidate_numeric_drift_is_not_normalized(self) -> None:
        reference = copy.deepcopy(self.reference)
        aircraft = "gp-extra-300s-60"
        reference["outputs"][aircraft]["checkpoint_value"] = {"state": [0.0, 1.0]}
        candidate = copy.deepcopy(reference)
        candidate["outputs"][aircraft]["checkpoint_value"]["state"][1] += 0.000001
        with self.assertRaisesRegex(ValueError, "candidate full value differs"):
            gate.check_comparison(reference, candidate)

    def test_full_values_preserve_types_and_signed_zero_even_with_a_stale_digest(self) -> None:
        aircraft = "gp-extra-300s-60"
        for old, new in ((True, 1), (1, 1.0), (0.0, -0.0)):
            reference, candidate = copy.deepcopy(self.reference), copy.deepcopy(self.reference)
            reference["outputs"][aircraft]["checkpoint_value"]["test"] = old
            candidate["outputs"][aircraft]["checkpoint_value"]["test"] = new
            with self.subTest(old=old, new=new), self.assertRaisesRegex(ValueError, "candidate full value differs"):
                gate.check_comparison(reference, candidate)

    def test_bad_host_missing_aircraft_and_missing_values_fail(self) -> None:
        for mutation in ("host", "engine", "physics_hz", "missing_aircraft", "missing_full_value", "bad_digest", "old_owner"):
            capture = copy.deepcopy(self.reference)
            row = capture["outputs"][sorted(gate.IDS)[0]]
            if mutation == "host": capture["os"] = "unknown"
            if mutation == "engine": capture["engine"] = gate.CURRENT_CAPTURE_ENGINE
            if mutation == "physics_hz": capture["physics_hz"] += 1
            if mutation == "missing_aircraft": capture["outputs"].pop(sorted(gate.IDS)[0])
            if mutation == "missing_full_value": row.pop("csv_value")
            if mutation == "bad_digest": row["checkpoint"] = "g" * 64
            if mutation == "old_owner": capture["session_sha256"] = "0" * 64
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "capture.json"
                path.write_text(json.dumps(capture), encoding="utf-8")
                with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                    gate.load_capture(path, self.fixture, True, self.fixture["engine"])

    def test_current_capture_uses_actual_current_engine_not_frozen_identity(self) -> None:
        current = copy.deepcopy(self.reference)
        current["engine"] = gate.CURRENT_CAPTURE_ENGINE
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "capture.json"
            path.write_text(json.dumps(current), encoding="utf-8")
            gate.load_capture(path, self.fixture, True, gate.CURRENT_CAPTURE_ENGINE)
            with self.assertRaises(ValueError):
                gate.load_capture(path, self.fixture, True, self.fixture["engine"])
        with self.assertRaises(ValueError):
            gate.check_comparison(self.reference, current)

    def test_matched_capture_requires_the_overlay_trace_identity(self) -> None:
        current = copy.deepcopy(self.reference)
        current["engine"] = gate.CURRENT_CAPTURE_ENGINE
        current["trace_sha256"] = gate.TRACE_LAW_OVERLAY
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "capture.json"
            path.write_text(json.dumps(current), encoding="utf-8")
            gate.load_capture(path, self.fixture, True, gate.CURRENT_CAPTURE_ENGINE, gate.TRACE_LAW_OVERLAY)
            with self.assertRaises(ValueError):
                gate.load_capture(path, self.fixture, True, gate.CURRENT_CAPTURE_ENGINE)
            current["trace_sha256"] = gate.TRACE_OLD
            path.write_text(json.dumps(current), encoding="utf-8")
            with self.assertRaises(ValueError):
                gate.load_capture(path, self.fixture, True, gate.CURRENT_CAPTURE_ENGINE, gate.TRACE_LAW_OVERLAY)

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


class ReferenceLawOverlayTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.project = Path(temporary.name)
        self.originals = {
            path: b"# pinned reference\n" + declarations[0] + b"\n# retained code\n"
            for path, declarations in gate.REFERENCE_LAW_DECLARATIONS.items()
        }
        self.originals["sim/other.gd"] = b"# another pinned source\n"
        self.fuel, self.avanti = b"fuel", b"avanti"
        files = {**self.originals, "data/fuels/openrc-fuel-registry.json": self.fuel,
                 "data/aircraft/sebart_avanti_s_a200.json": self.avanti, "project.godot": b"project\n"}
        for path, contents in files.items():
            target = self.project / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(contents)
        flight = self.originals[gate.GLOW_FLIGHT_PATH]
        trace = self.originals[gate.TRACE_PATH]
        patched_flight = flight.replace(*gate.REFERENCE_LAW_DECLARATIONS[gate.GLOW_FLIGHT_PATH])
        patched_trace = trace.replace(*gate.REFERENCE_LAW_DECLARATIONS[gate.TRACE_PATH])
        patches = {
            "pin_paths": mock.Mock(return_value={path: gate.sha(data) for path, data in self.originals.items()}),
            "REFERENCE_PROJECT": gate.sha(files["project.godot"]),
            "GLOW_FLIGHT_OLD_LF": gate.sha(flight),
            "GLOW_FLIGHT_LAW_OVERLAY_LF": gate.sha(patched_flight),
            "TRACE_OLD": gate.sha(trace),
            "TRACE_LAW_OVERLAY": gate.sha(patched_trace),
        }
        for name, value in patches.items():
            patcher = mock.patch.object(gate, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_candidate_requires_one_exact_current_declaration(self) -> None:
        old, current = gate.REFERENCE_LAW_DECLARATIONS[gate.GLOW_FLIGHT_PATH]
        gate.check_candidate_glow_law(b"extends Node\n" + current + b"\n")
        for data in (old, b"# missing declaration", current + b"\n" + current,
                     current + b"\nconst LAW: String = \"wrong\""):
            with self.subTest(data=data), self.assertRaises(ValueError):
                gate.check_candidate_glow_law(data)

    def test_substitution_requires_exactly_one_original_declaration(self) -> None:
        before, after = gate.REFERENCE_LAW_DECLARATIONS[gate.GLOW_FLIGHT_PATH]
        self.assertEqual(gate.replace_once(b"prefix\n" + before + b"\nsuffix", before, after, "test"),
                         b"prefix\n" + after + b"\nsuffix")
        for data in (b"missing", before + b"\n" + before):
            with self.subTest(data=data), self.assertRaisesRegex(ValueError, "missing or duplicated"):
                gate.replace_once(data, before, after, "test")

    def test_changed_reference_and_wrong_derived_trace_pin_fail(self) -> None:
        for path, original in self.originals.items():
            if path not in gate.REFERENCE_LAW_DECLARATIONS:
                continue
            target = self.project / path
            target.write_bytes(original + b"changed")
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "reference input changed"):
                gate.reference_law_overlay(self.project)
            target.write_bytes(original)
        with mock.patch.object(gate, "TRACE_LAW_OVERLAY", "0" * 64), self.assertRaisesRegex(ValueError, "trace overlay identity"):
            gate.reference_law_overlay(self.project)

    def test_reference_checks_every_overlaid_and_unmodified_source(self) -> None:
        gate.check_reference_inputs(self.project, self.fuel, self.avanti)
        overlay = gate.reference_law_overlay(self.project)
        for path, data in overlay.items():
            (self.project / path).write_bytes(data)
        gate.check_reference_inputs(self.project, self.fuel, self.avanti, overlay)
        for path in self.originals:
            target = self.project / path
            saved = target.read_bytes()
            target.write_bytes(saved + b"changed")
            with self.subTest(path=path), self.assertRaises(ValueError):
                gate.check_reference_inputs(self.project, self.fuel, self.avanti, overlay)
            target.write_bytes(saved)
        with self.assertRaisesRegex(ValueError, "overlay set"):
            gate.check_reference_inputs(self.project, self.fuel, self.avanti, {gate.TRACE_PATH: overlay[gate.TRACE_PATH]})


if __name__ == "__main__":
    unittest.main()
