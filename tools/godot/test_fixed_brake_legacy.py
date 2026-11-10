"""Failure controls for the mandatory fixed-brake reference gate."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
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

    def test_one_bit_digest_change_including_three_tick_state_fails(self) -> None:
        for field in gate.FIELDS:
            changed = copy.deepcopy(self.reference)
            row = changed["outputs"]["gp-extra-300s-60"]
            digest = row[field]
            row[field] = format(int(digest[0], 16) ^ 1, "x") + digest[1:]
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "candidate differs"):
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

    def test_matched_capture_requires_both_overlay_owner_identities(self) -> None:
        current = copy.deepcopy(self.reference)
        current["engine"] = gate.CURRENT_CAPTURE_ENGINE
        current["trace_sha256"] = gate.TRACE_LAW_OVERLAY
        current["session_sha256"] = gate.SESSION_IDENTITY_OVERLAY
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "capture.json"
            path.write_text(json.dumps(current), encoding="utf-8")
            gate.load_capture(path, self.fixture, True, gate.CURRENT_CAPTURE_ENGINE,
                              gate.TRACE_LAW_OVERLAY, gate.SESSION_IDENTITY_OVERLAY)
            with self.assertRaises(ValueError):
                gate.load_capture(path, self.fixture, True, gate.CURRENT_CAPTURE_ENGINE)
            current["trace_sha256"] = gate.TRACE_OLD
            path.write_text(json.dumps(current), encoding="utf-8")
            with self.assertRaises(ValueError):
                gate.load_capture(path, self.fixture, True, gate.CURRENT_CAPTURE_ENGINE,
                                  gate.TRACE_LAW_OVERLAY, gate.SESSION_IDENTITY_OVERLAY)
            current["trace_sha256"] = gate.TRACE_LAW_OVERLAY
            current["session_sha256"] = gate.SESSION_OLD
            path.write_text(json.dumps(current), encoding="utf-8")
            with self.assertRaises(ValueError):
                gate.load_capture(path, self.fixture, True, gate.CURRENT_CAPTURE_ENGINE,
                                  gate.TRACE_LAW_OVERLAY, gate.SESSION_IDENTITY_OVERLAY)

    def test_one_bit_change_to_any_candidate_input_fails(self) -> None:
        fuel = (gate.ROOT / "app/data/fuels/openrc-fuel-registry.json").read_bytes()
        avanti = (gate.ROOT / "app/data/aircraft/sebart_avanti_s_a200.json").read_bytes()
        extra = (gate.ROOT / "app" / gate.EXTRA_PATH).read_bytes()
        stik = (gate.ROOT / "app" / gate.STIK_PATH).read_bytes()
        inputs = [fuel, avanti, extra, stik]
        gate.check_input_bytes(*inputs)
        for index in range(len(inputs)):
            changed = inputs.copy()
            changed[index] = bytes([changed[index][0] ^ 1]) + changed[index][1:]
            with self.subTest(index=index), self.assertRaises(ValueError):
                gate.check_input_bytes(*changed)

    def test_extra_data_must_be_exactly_the_reviewed_additions_to_the_prior_pin(self) -> None:
        project = gate.ROOT / "app"
        fuel = (project / "data/fuels/openrc-fuel-registry.json").read_bytes()
        avanti = (project / "data/aircraft/sebart_avanti_s_a200.json").read_bytes()
        extra = (project / gate.EXTRA_PATH).read_bytes()
        stik = (project / gate.STIK_PATH).read_bytes()
        gate.check_input_bytes(fuel, avanti, extra, stik)
        for block in gate.EXTRA_ADDITIONS:
            for altered in (extra.replace(block, b"", 1), extra + block,
                            extra.replace(block, block.replace(b'"value":', b'"VALUE":', 1), 1)):
                # Even an incorrectly refreshed current hash cannot admit a
                # missing, duplicated or modified EX-14 addition.
                with self.subTest(block=block[:40], length=len(altered)), \
                     mock.patch.object(gate, "EXTRA_CURRENT", gate.sha(altered)), self.assertRaises(ValueError):
                    gate.check_input_bytes(fuel, avanti, altered, stik)
        altered = extra.replace(b'"format":', b'"FORMAT":', 1)
        self.assertNotEqual(extra, altered)
        with mock.patch.object(gate, "EXTRA_CURRENT", gate.sha(altered)), \
             self.assertRaisesRegex(ValueError, "evolution differs"):
            gate.check_input_bytes(fuel, avanti, altered, stik)

    def test_candidate_physics_markers_must_each_occur_once(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            for path, markers in gate.CANDIDATE_IDENTITY_MARKERS.items():
                target = project / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"\n".join(markers))
            gate.check_candidate_physics_identity(project)
            for path, markers in gate.CANDIDATE_IDENTITY_MARKERS.items():
                target = project / path
                original = target.read_bytes()
                for marker in markers:
                    for changed in (original.replace(marker, b"missing", 1), original + b"\n" + marker):
                        target.write_bytes(changed)
                        with self.subTest(path=path, marker=marker, changed=changed), self.assertRaises(ValueError):
                            gate.check_candidate_physics_identity(project)
                    target.write_bytes(original)
            for path in (gate.AERO_PATH, gate.PROPULSION_PATH):
                target = project / path
                original = target.read_bytes()
                declaration = gate.CANDIDATE_IDENTITY_MARKERS[path][0]
                name = b"LOADS_LAW" if path == gate.AERO_PATH else b"COEFFICIENT_LAW"
                for changed in (original.replace(declaration, b"# " + declaration, 1),
                                original + b'\nconst ' + name + b' := "wrong"'):
                    target.write_bytes(changed)
                    with self.subTest(path=path, changed=changed), self.assertRaises(ValueError):
                        gate.check_candidate_physics_identity(project)
                target.write_bytes(original)

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
        self.contract = b"# reference contract\n"
        files = {**self.originals, gate.CONTRACT_PATH: self.contract, "data/fuels/openrc-fuel-registry.json": self.fuel,
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
            "CONTRACT_OLD_LF": gate.sha(self.contract),
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
        changed = dict(overlay)
        changed[gate.TRACE_PATH] += b"changed"
        (self.project / gate.TRACE_PATH).write_bytes(changed[gate.TRACE_PATH])
        with self.assertRaisesRegex(ValueError, "overlay identity"):
            gate.check_reference_inputs(self.project, self.fuel, self.avanti, changed)


class ReferenceIdentityOverlayTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.project = Path(temporary.name)
        self.originals = {
            path: b"# pinned reference\n" + before + b"\n# retained code\n"
            for path, (before, _) in gate.REFERENCE_IDENTITY_EDITS.items()
        }
        self.originals.update({gate.EXTRA_PATH: b"old extra", gate.STIK_PATH: b"old stik",
                               "sim/other.gd": b"another pinned source"})
        self.fuel, self.avanti = b"fuel", b"avanti"
        self.data_overlay = {gate.EXTRA_PATH: b"current extra", gate.STIK_PATH: b"current stik"}
        self.contract = b"# pinned contract\n" + gate.CONTRACT_BEFORE + b"\n"
        self.contract_patched = self.contract.replace(gate.CONTRACT_BEFORE, gate.CONTRACT_AFTER, 1)
        files = {**self.originals, gate.CONTRACT_PATH: self.contract, "data/fuels/openrc-fuel-registry.json": self.fuel,
                 "data/aircraft/sebart_avanti_s_a200.json": self.avanti, "project.godot": b"project\n"}
        for path, contents in files.items():
            target = self.project / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(contents)
        self.hashes = {
            path: (gate.sha(self.originals[path]), gate.sha(self.originals[path].replace(before, after)))
            for path, (before, after) in gate.REFERENCE_IDENTITY_EDITS.items()
        }
        self.pins = {path: gate.sha(data) for path, data in self.originals.items()}
        patches = {
            "pin_paths": mock.Mock(return_value=self.pins),
            "REFERENCE_PROJECT": gate.sha(files["project.godot"]),
            "CONTRACT_OLD_LF": gate.sha(self.contract),
            "CONTRACT_OVERLAY_LF": gate.sha(self.contract_patched),
            "REFERENCE_IDENTITY_HASHES": self.hashes,
            "SESSION_IDENTITY_OVERLAY": self.hashes[gate.SESSION_PATH][1],
            "EXTRA_CURRENT": gate.sha(self.data_overlay[gate.EXTRA_PATH]),
            "STIK_CURRENT": gate.sha(self.data_overlay[gate.STIK_PATH]),
        }
        for name, value in patches.items():
            patcher = mock.patch.object(gate, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_exact_identity_edits_retain_all_other_bytes(self) -> None:
        overlay = gate.reference_identity_overlay(self.project)
        for path, (before, after) in gate.REFERENCE_IDENTITY_EDITS.items():
            self.assertEqual(overlay[path], self.originals[path].replace(before, after, 1))

    def test_contract_overlay_requires_exact_old_and_new_bytes(self) -> None:
        path = self.project / gate.CONTRACT_PATH
        overlay = gate.reference_contract_overlay(self.project)
        self.assertEqual(overlay, self.contract_patched)
        path.write_bytes(overlay)
        gate.check_reference_inputs(self.project, self.fuel, self.avanti, contract_overlay=overlay)
        for changed in (self.contract + b"changed", overlay + b"changed"):
            path.write_bytes(changed)
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                gate.check_reference_inputs(self.project, self.fuel, self.avanti,
                                            contract_overlay=overlay if changed.startswith(overlay) else None)
        path.write_bytes(self.contract)
        with mock.patch.object(gate, "CONTRACT_OVERLAY_LF", "0" * 64), \
             self.assertRaisesRegex(ValueError, "contract overlay differs"):
            gate.reference_contract_overlay(self.project)
        # Checkout line endings do not change the admitted source identity.
        path.write_bytes(self.contract.replace(b"\n", b"\r\n"))
        self.assertEqual(gate.reference_contract_overlay(self.project).replace(b"\r\n", b"\n"), overlay)

    def test_contract_anchor_cannot_be_missing_or_duplicated(self) -> None:
        path = self.project / gate.CONTRACT_PATH
        for changed in (self.contract.replace(gate.CONTRACT_BEFORE, b"missing", 1),
                        self.contract + gate.CONTRACT_BEFORE):
            path.write_bytes(changed)
            with mock.patch.object(gate, "CONTRACT_OLD_LF", gate.sha(changed)), \
                 self.assertRaisesRegex(ValueError, "missing or duplicated"):
                gate.reference_contract_overlay(self.project)

    def test_each_missing_or_duplicate_identity_anchor_fails(self) -> None:
        for path, (before, _) in gate.REFERENCE_IDENTITY_EDITS.items():
            target = self.project / path
            original = self.originals[path]
            for changed in (original.replace(before, b"missing", 1), original + before):
                target.write_bytes(changed)
                self.pins[path] = gate.sha(changed)
                self.hashes[path] = (gate.sha(changed), self.hashes[path][1])
                with self.subTest(path=path, changed=changed), self.assertRaisesRegex(ValueError, "missing or duplicated"):
                    gate.reference_identity_overlay(self.project)
            target.write_bytes(original)
            self.pins[path] = gate.sha(original)
            self.hashes[path] = (gate.sha(original), self.hashes[path][1])

    def test_changed_reference_and_wrong_derived_pin_fail(self) -> None:
        for path in gate.REFERENCE_IDENTITY_EDITS:
            target = self.project / path
            original = target.read_bytes()
            target.write_bytes(original + b"changed")
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "identity input changed"):
                gate.reference_identity_overlay(self.project)
            target.write_bytes(original)
        path = gate.AERO_PATH
        old_hashes = self.hashes[path]
        self.hashes[path] = (old_hashes[0], "0" * 64)
        with self.assertRaisesRegex(ValueError, "identity overlay differs"):
            gate.reference_identity_overlay(self.project)

    def test_overlays_and_remaining_reference_are_checked_after_capture(self) -> None:
        identity = gate.reference_identity_overlay(self.project)
        for path, contents in {**identity, **self.data_overlay}.items():
            (self.project / path).write_bytes(contents)
        gate.check_reference_inputs(self.project, self.fuel, self.avanti, None, identity, self.data_overlay)
        for path in self.originals:
            target = self.project / path
            saved = target.read_bytes()
            target.write_bytes(saved + b"changed")
            with self.subTest(path=path), self.assertRaises(ValueError):
                gate.check_reference_inputs(self.project, self.fuel, self.avanti, None, identity, self.data_overlay)
            target.write_bytes(saved)
        for overlay, name in ((identity, "identity"), (self.data_overlay, "aircraft")):
            path = next(iter(overlay))
            changed = dict(overlay)
            changed[path] += b"changed"
            (self.project / path).write_bytes(changed[path])
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "overlay identity"):
                gate.check_reference_inputs(self.project, self.fuel, self.avanti, None,
                                            changed if name == "identity" else identity,
                                            changed if name == "aircraft" else self.data_overlay)
            (self.project / path).write_bytes(overlay[path])


class RealHistoricalReferenceTests(unittest.TestCase):
    def test_pinned_historical_sources_derive_every_supported_overlay(self) -> None:
        paths = set(gate.REFERENCE_LAW_DECLARATIONS) | set(gate.REFERENCE_IDENTITY_EDITS) | {gate.CONTRACT_PATH}
        sources = {}
        history = subprocess.run(["git", "-C", str(gate.ROOT), "cat-file", "-e", "fa9f387f6^{commit}"],
                                 capture_output=True, check=False)
        if history.returncode:
            self.skipTest("historical reference commit is not present in this checkout")
        for path in paths:
            result = subprocess.run(["git", "-C", str(gate.ROOT), "show", "fa9f387f6:app/" + path],
                                    capture_output=True, check=False)
            self.assertEqual(result.returncode, 0, path)
            sources[path] = result.stdout.replace(b"\r\n", b"\n")
        pins = gate.pin_paths()
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            for path, data in sources.items():
                # Reproduce the historical checkout's pinned line endings.
                if path in pins and gate.sha(data) != pins[path]:
                    data = data.replace(b"\n", b"\r\n")
                    self.assertEqual(gate.sha(data), pins[path], path)
                target = project / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            law = gate.reference_law_overlay(project)
            identity = gate.reference_identity_overlay(project)
            contract = gate.reference_contract_overlay(project)
            self.assertEqual(gate.sha(law[gate.TRACE_PATH]), gate.TRACE_LAW_OVERLAY)
            self.assertEqual(gate.sha(law[gate.GLOW_FLIGHT_PATH].replace(b"\r\n", b"\n")),
                             gate.GLOW_FLIGHT_LAW_OVERLAY_LF)
            self.assertEqual(gate.sha(identity[gate.AIRCRAFT_DATA_PATH].replace(b"\r\n", b"\n")),
                             gate.REFERENCE_IDENTITY_HASHES[gate.AIRCRAFT_DATA_PATH][1])
            self.assertEqual(gate.sha(contract.replace(b"\r\n", b"\n")), gate.CONTRACT_OVERLAY_LF)


if __name__ == "__main__":
    unittest.main()
