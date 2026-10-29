#!/usr/bin/env python3
"""Failure-oriented tests for aggregation of native fleet evidence."""
from __future__ import annotations

import asyncio
import copy
import hashlib
import importlib.util
import math
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("fleet_campaign", HERE / "fleet_campaign.py")
assert SPEC is not None and SPEC.loader is not None
campaign = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(campaign)

# Real FS64V midpoint encoded Variants; bytes avoid lossy decimal materialization.
FS64V_TRIAL_HEX = (
    "1c00000003000000210000000d0000002dfb4a651b002e40b2f619ab5f7f47c08db512ad9628cebf8864e81a45a9773f67b2"
    "57cbd95429bf0beed592e43268bfbabc1d39449fe63f9be668d172d1893f4589738ed0e08ebf7d320ac0bb9fe63fd5ebd948"
    "fe2a49bf1fddef3e77e694bf780dfe96e6372ebf210000001600000000000000000000007e1e48838021c83f2e19da8cf81f"
    "784000000000000000003a5cfdb1bb74983f0000000000000000000000000000000000000000000000000000000000000040"
    "000000000000000000000000000000000000000000000000666666666666f23f00000000000000000000000000000000d9f7"
    "0afdbfe1ecbf00000000000000000000000000000000000000000000f03fe75cab5af144463f4854f3cb2f714a3f19931f68"
    "57dd413f030001009999999999d90a40"
)
FS64V_CONTEXT_HEX = (
    "1c00000008000000210000000e0000000000000000000000d4519a951d5d9b3fa57d00ed5b9db33f8bd52d7239ab983f56f0"
    "ec88cd5b2e40f81b7414d08e47c0000000000000f03f1248bdca7ba32d404a66cdb6cf8e47c0000000000000f03fc1ce2860"
    "a4ff2d40f6aa28e1d96147c0000000000000f03f9e9ad56763b0f5bf2100000004000000d4519a951d5d9b3fa57d00ed5b9d"
    "b33f8bd52d7239ab983f00000000000000002100000005000000f88f96d123639bbf341b2c457e1a83bf341b2c457e1a833f"
    "72130dac128785bf0000000000000000030001005555555555d50a4003000000000000000300000000000000010000000000"
    "00000100000000000000"
)
FS64V_AIRCRAFT_SHA = "c42f72ac9f714e67801466fdd652f7bd214f59cc6577340ace348752f2f9a91a"
FS64V_CAUSE_BYTES_HEX = "210000000700000000000000000000000000000000000000acf7f5a16f0d90bf442c89836c0a903ffb702e7c620d903fd22f068cdc4b333f85580189a0cd453f"


def fixtures():
    a = {"aircraft": "fixed", "vehicle": "fixed-wing", "battery": "ideal", "case": "trim",
         "weather": "calm", "soft_hull": True, "default_battery": True}
    refusal = {"aircraft": "fixed", "vehicle": "fixed-wing", "battery": "ideal", "case": "runway",
               "weather": "crosswind", "soft_hull": False, "default_battery": True,
               "expected": "reference-refusal", "expected_refusal_reason": "exact reset refusal"}
    b = {"aircraft": "heli", "vehicle": "rotorcraft", "battery": "ideal", "case": "ground",
         "weather": "calm", "soft_hull": None, "default_battery": True, "expected": "flight"}
    manifest = {"format": "openrc-nk3-fleet-manifest v1", "aircraft": ["fixed", "heli"],
                "rows": [a, refusal, b]}
    binary, source, lock, engine, fleet = (x * 64 for x in "abcde")
    guard = {"binary_sha256": binary, "engine_sha256": engine, "fleet_sha256": fleet,
             "receipt": {"binary_sha256": binary, "source_sha256": source, "lock_sha256": lock},
             "reference_sources": {"app/a.gd": "1" * 64}}

    def run(requested, rotor):
        native = requested == "native"
        identity = {"backend": requested}
        if native:
            identity.update(abi_version=2, binary_sha256=binary, source_sha256=source, lock_sha256=lock)
        return {"complete": True, "requested": requested, "actual": requested, "identity": identity,
                "error": "", "reason": "", "warmup_completed": 2, "samples_completed": 3,
                "fingerprint_boundaries": 6, "end": {"tick": 5, "fault": "", "crashed": False,
                                                       "paused": False, "held": False},
                "fingerprint": "a" * 64, "aircraft_sha256": "b" * 64,
                "native_covered_every_tick": native, "context_calls": 5 if native else 0,
                "stage_calls": 20 if native else 0, "stage_in_use": "stage" if native else "reference",
                "replay_requested": 5 if rotor else 0, "replay_completed": 5 if rotor else 0,
                "replay_ok": rotor, "replay_native_covered": rotor and native}

    def flight(row):
        return {**row, "status": "pass", "reason": "", "fingerprint_equal": True,
                "reference": run("gdscript_reference", row["vehicle"] == "rotorcraft"),
                "native": run("native", row["vehicle"] == "rotorcraft")}

    def refused(row):
        source_row = {key: value for key, value in row.items() if key != "expected_refusal_reason"}
        reason = row["expected_refusal_reason"]
        return {**source_row, "status": "reference-refused", "reason": reason, "fingerprint_equal": False,
                "reference": {"complete": False, "requested": "gdscript_reference", "phase": "reset", "error": reason},
                "native": {"complete": False, "requested": "native", "phase": "reset", "error": reason}}

    def component(count):
        return {"count": count, "identical": count}

    def report(aircraft, rows, flights, refusals):
        components = {"literals": component(1), "fleet_pair": component(flights)}
        if refusals:
            components["fleet_reference_refusal"] = component(refusals)
        count = sum(x["count"] for x in components.values())
        command = ["godot", "--extension=res://native/kernel/openrc_native_kernel.gdextension",
                   f"--aircraft={aircraft}", "--warmup=2", "--samples=3"]
        harness = {name: "1" * 64 for name in ("research/native-kernel/oracle.gd",
            "research/native-kernel/trajectory.gd", "research/native-kernel/run.py", "research/native-kernel/build.py",
            "tools/godot/run_checked.py", "app/sim/native_stage.gd")}
        harness["research/native-kernel/fleet.gd"] = fleet
        return {"format": "openrc-nk3-fleet v2", "run_valid": True, "verdict": "pass", "failures": [],
                "self_test": {"passed": True}, "checked_run": {"ok": True, "complete": True,
                    "reason": "passed", "process_exit": 0, "counts": {"error": 0},
                    "missing_required_text": [], "required_text": ["NK3_ORACLE verdict=pass"], "command": command},
                "library": {"ok": True, "reason": ""}, "identity": {"backend": "native", "abi_version": 2},
                "build_receipt": copy.deepcopy(guard["receipt"]), "binary_sha256_before": binary, "binary_sha256_after": binary,
                "engine_sha256_before": engine, "engine_sha256_after": engine,
                "reference_sources_before": copy.deepcopy(guard["reference_sources"]),
                "reference_sources_after": copy.deepcopy(guard["reference_sources"]),
                "sources": {"res://physics/a.gd": "1" * 64}, "sources_after": {"res://physics/a.gd": "1" * 64},
                "harness_sources": harness, "engine": "engine", "seed": 1,
                "law_identity": {"law": "same"}, "fleet_scope": {"scope": "scoped",
                    "filters": {"aircraft": aircraft, "weather": "", "soft_hull": ""},
                    "declared_aircraft": ["fixed", "heli"], "declared_rows": 3, "selected_rows": len(rows),
                    "matrix_complete": False, "warmup_requested": 2, "samples_requested": 3, "failed": 0,
                    "flight_passed": flights, "reference_refused": refusals, "runtime_refused": 0},
                "fleet": rows, "components": components,
                "total": {"compared": count, "identical": count, "mismatched": 0}}

    return manifest, {"fixed": report("fixed", [flight(a), refused(refusal)], 1, 1),
                      "heli": report("heli", [flight(b)], 1, 0)}, guard


def runway_start_fixture(aircraft="sebart-avanti-s-a200-p100rx", soft_hull=True, battery="ideal", trim=False):
    """Small typed-byte stand-ins; actual source hashes are exercised by the Godot test."""
    cases = campaign.TRIM_START_CASES if trim else campaign.RUNWAY_START_CASES
    spec = copy.deepcopy(cases[aircraft])
    battery_spec = spec["batteries"][battery]
    payloads = {"frame": b"typed-frame", "config": b"typed-configuration", "outcome": b"typed-outcome",
                "live_config": b"typed-live-configuration"}
    for field, payload in payloads.items():
        if field in ("config", "live_config"):
            battery_spec[field + "_sha256"][soft_hull] = hashlib.sha256(payload).hexdigest()
        else:
            battery_spec[field + "_sha256"] = hashlib.sha256(payload).hexdigest()
    reason = campaign.TRIM_START_REASON if trim else campaign.RUNWAY_START_REASON
    expected = {"aircraft": aircraft, "vehicle": "fixed-wing", "battery": battery,
                "case": "airborne_half_power" if trim else "runway",
                "weather": spec["weather"], "soft_hull": soft_hull, "default_battery": battery_spec["default_battery"],
                "expected": "reference-refusal", "expected_refusal_reason": reason}

    def proof(requested):
        status = {"requested": requested, "identity": {"backend": "gdscript_reference"},
                  "reason": "" if requested == "gdscript_reference" else "pending configuration requires reset"}
        result = {"requested": requested, "before_status": copy.deepcopy(status), "after_status": status,
                  "before_helper_absent": True, "after_helper_absent": True, "model_retained": True,
                  "callbacks_retained": True, "reference_callbacks_before": True, "reference_callbacks_after": True,
                  "kernel_guard_retained": True, "owner_guard_retained": True,
                  "selection_valid_before": True, "selection_valid_after": True,
                  "input_configuration_retained": True, "live_configuration_retained": True, "outcome_empty": True,
                  "aircraft_sha256": battery_spec["aircraft_sha256"], "outcome_dictionary_empty": trim,
                  "outcome_status": "" if trim else "numerical_unresolved", "outcome_ok": None if trim else False,
                  "outcome_message": "" if trim else reason.removeprefix("reset failed: "),
                  "before_frame_bytes_hex": payloads["frame"].hex(),
                  "before_live_config_bytes_hex": payloads["live_config"].hex()}
        for field, payload in payloads.items():
            result[field + "_bytes_hex"] = payload.hex()
            result[field + "_sha256"] = hashlib.sha256(payload).hexdigest()
        return result

    row = {key: value for key, value in expected.items() if key != "expected_refusal_reason"}
    row.update(status="reference-refused", reason=reason, fingerprint_equal=False,
               reference={"complete": False, "requested": "gdscript_reference", "phase": "reset",
                          "error": reason},
               native={"complete": False, "requested": "native", "phase": "reset",
                       "error": reason},
               startup_proof={"reference": proof("gdscript_reference"), "native": proof("native")})
    return expected, row, spec


def startup_campaign_fixture(expected, row):
    _, reports, guard = fixtures()
    report = reports["fixed"]
    aircraft = expected["aircraft"]
    report["checked_run"]["command"] = [arg.replace("--aircraft=fixed", "--aircraft=" + aircraft)
                                        for arg in report["checked_run"]["command"]]
    report["fleet_scope"].update(filters={"aircraft": aircraft, "weather": "", "soft_hull": ""},
                                 declared_aircraft=[aircraft], declared_rows=1, selected_rows=1,
                                 flight_passed=0, reference_refused=1, runtime_refused=0)
    report["fleet"] = [row]
    report["components"] = {"literals": {"count": 1, "identical": 1},
                            "fleet_reference_refusal": {"count": 1, "identical": 1}}
    report["total"] = {"compared": 2, "identical": 2, "mismatched": 0}
    return {"format": "openrc-nk3-fleet-manifest v1", "aircraft": [aircraft], "rows": [expected]}, {aircraft: report}, guard


def encode_runtime_array(items):
    data = bytearray(struct.pack("<II", 28, len(items)))
    for kind, value in items:
        if kind == "packed":
            data.extend(struct.pack("<II", 33, len(value)))
            for number in value:
                data.extend(struct.pack("<d", number))
        elif kind == "float":
            data.extend(struct.pack("<Id", 3 | (1 << 16), value))
        elif kind == "bool":
            data.extend(struct.pack("<II", 1, int(value)))
        else:
            raise AssertionError(kind)
    return bytes(data)


def runtime_payloads(tick=873, stage_fraction=1.0):
    body, continuous = [0.0] * 13, [0.0] * 22
    body[6], continuous[8], continuous[18] = 1.0, 2.0, 1.0
    tick_time = float(tick) * (1.0 / 240.0)
    trial = [("packed", body), ("packed", continuous), ("float", tick_time + (1.0 / 240.0) * stage_fraction)]
    context = [("packed", [0.0] * 14), ("packed", [0.0] * 4), ("packed", [0.0] * 5),
               ("float", tick_time), ("float", 0.0), ("float", 0.0), ("bool", False), ("bool", False)]
    return trial, context


def replace_runtime_payload(proof, name, data):
    digest = hashlib.sha256(data).hexdigest()
    proof[name + "_bytes_hex"] = proof["native_" + name + "_bytes_hex"] = data.hex()
    proof[name + "_sha256"] = proof["native_" + name + "_sha256"] = digest


def runtime_fixture(aircraft="stik-glow-61fx-2t", tick=873, stage_fraction=1.0,
                    rejected_stage_calls=4, soft_hull=True):
    _, reports, guard = fixtures()
    row = {"aircraft": aircraft, "vehicle": "fixed-wing", "battery": "ideal", "case": "runway",
           "weather": "gusty", "soft_hull": soft_hull, "default_battery": True,
           "expected": "runtime-domain-refusal", "expected_runtime_tick": tick}
    manifest = {"format": "openrc-nk3-fleet-manifest v1", "aircraft": [aircraft], "rows": [row]}
    end = {"tick": tick, "fault": campaign.RUNTIME_FAULT, "crashed": False, "paused": True, "held": False,
           "pause_reason": "simulation fault: " + campaign.RUNTIME_FAULT}
    cause = {"code": campaign.RUNTIME_CODE, "origin": "feed_endpoint", "feed_factor": 0.0, "rpm": 0.0,
             "demand_nm": -0.02, "friction_nm": 0.01, "prop_load_torque_nm": 0.02,
             "axial_acceleration_rad_s2": 0.0, "rotor_inertia_kg_m2": 0.01}
    native_cause = {**cause, "feed_factor": 0.0}
    trial_items, context_items = runtime_payloads(tick, stage_fraction)
    trial, context = encode_runtime_array(trial_items), encode_runtime_array(context_items)
    proof = {"code": campaign.RUNTIME_CODE, "origin": "feed_endpoint", "accepted_ticks": tick,
             "attempted_tick": tick + 1, "requested_ticks": 3000, "warmup_completed": 600,
             "samples_completed": tick - 600, "prefix_boundaries": tick + 1, "reference_prefix_sha256": "d" * 64,
             "native_prefix_sha256": "d" * 64, "prefix_equal_every_tick": True, "terminal_equal": True,
             "reference_rollback": True, "native_rollback": True, "reference_end": end, "native_end": copy.deepcopy(end),
             "reference_identity": {"backend": "gdscript_reference"}, "reference_owner_retained": True,
             "reference_aircraft_sha256": "c" * 64, "native_aircraft_sha256": "c" * 64,
             "native_identity": {"backend": "native", "abi_version": 2, "binary_sha256": guard["binary_sha256"],
                                 "source_sha256": guard["receipt"]["source_sha256"],
                                 "lock_sha256": guard["receipt"]["lock_sha256"]},
             "native_owner_retained": True, "native_covered_every_tick": True,
             "reference_input_reads": tick + 1, "native_input_reads": tick + 1,
             "native_stage_calls": 4 * tick + rejected_stage_calls, "native_context_calls": tick + 1,
             "rejected_stage_calls": rejected_stage_calls, "rejected_context_calls": 1,
             "native_diagnostic_stage_call": 4 * tick + rejected_stage_calls, "native_diagnostic_context_call": tick + 1,
             "trial_equal": True, "context_equal": True, "reference_result_empty": True,
             "trial_bytes_hex": trial.hex(), "trial_sha256": hashlib.sha256(trial).hexdigest(),
             "native_trial_bytes_hex": trial.hex(), "native_trial_sha256": hashlib.sha256(trial).hexdigest(),
             "context_bytes_hex": context.hex(), "context_sha256": hashlib.sha256(context).hexdigest(),
             "native_context_bytes_hex": context.hex(), "native_context_sha256": hashlib.sha256(context).hexdigest(),
             "reference_cause": cause, "native_cause": native_cause}
    if aircraft == "stik-glow-fs64v-4t":
        proof["reference_aircraft_sha256"] = proof["native_aircraft_sha256"] = FS64V_AIRCRAFT_SHA
        replace_runtime_payload(proof, "trial", bytes.fromhex(FS64V_TRIAL_HEX))
        replace_runtime_payload(proof, "context", bytes.fromhex(FS64V_CONTEXT_HEX))
        fields = ("feed_factor", "rpm", "demand_nm", "friction_nm", "prop_load_torque_nm",
                  "axial_acceleration_rad_s2", "rotor_inertia_kg_m2")
        values = struct.unpack("<7d", bytes.fromhex(FS64V_CAUSE_BYTES_HEX)[8:])
        for field, value in zip(fields, values):
            proof["reference_cause"][field] = proof["native_cause"][field] = value
    result = {**row, "status": "runtime-domain-refused", "reason": campaign.RUNTIME_CODE,
              "fingerprint_equal": False, "reference": {"complete": False, "requested": "gdscript_reference"},
              "native": {"complete": False, "requested": "native"}, "runtime_domain": proof}
    report = copy.deepcopy(reports["fixed"])
    report["checked_run"]["command"] = ["godot", "--extension=res://native/kernel/openrc_native_kernel.gdextension",
                                        f"--aircraft={aircraft}", "--warmup=600", "--samples=2400"]
    report["fleet_scope"].update(filters={"aircraft": aircraft, "weather": "", "soft_hull": ""},
        declared_aircraft=[aircraft], declared_rows=1, selected_rows=1, warmup_requested=600,
        samples_requested=2400, flight_passed=0, reference_refused=0, runtime_refused=1)
    report["fleet"] = [result]
    report["components"] = {"literals": {"count": 1, "identical": 1},
                            "fleet_runtime_domain_refusal": {"count": 1, "identical": 1}}
    report["total"] = {"compared": 2, "identical": 2, "mismatched": 0}
    return manifest, {aircraft: report}, guard


class FleetCampaignTests(unittest.TestCase):
    def test_observed_startup_proofs_count_only_as_refusals(self):
        for aircraft, trim in (("sebart-avanti-s-a200-p100rx", False), ("skywalker-x8", True)):
            with self.subTest(aircraft=aircraft):
                expected, row, spec = runway_start_fixture(aircraft, trim=trim)
                manifest, reports, guard = startup_campaign_fixture(expected, row)
                cases = campaign.TRIM_START_CASES if trim else campaign.RUNWAY_START_CASES
                with mock.patch.dict(cases, {aircraft: spec}):
                    self.assertEqual(campaign.validate_reports(manifest, reports, guard, 2, 3),
                                     {"declared": 1, "flight_passed": 0, "reference_refused": 1, "runtime_refused": 0})

    def test_runway_start_refusals_are_bounded_and_not_flights(self):
        for aircraft in campaign.RUNWAY_START_CASES:
            for battery in campaign.RUNWAY_START_CASES[aircraft]["batteries"]:
                for soft in (True, False):
                    with self.subTest(aircraft=aircraft, battery=battery, soft=soft):
                        expected, row, spec = runway_start_fixture(aircraft, soft, battery)
                        with mock.patch.dict(campaign.RUNWAY_START_CASES, {aircraft: spec}):
                            campaign.validate_refusal(row, expected)
                            self.assertFalse(row["reference"]["complete"])
                            self.assertFalse(row["native"]["complete"])
                            self.assertFalse(row["fingerprint_equal"])

    def test_x8_trim_refusal_is_distinct_from_runway_failures(self):
        for soft in (True, False):
            expected, row, spec = runway_start_fixture("skywalker-x8", soft, trim=True)
            with mock.patch.dict(campaign.TRIM_START_CASES, {"skywalker-x8": spec}):
                campaign.validate_refusal(row, expected)
                for field, value in (("outcome_dictionary_empty", False), ("outcome_status", "numerical_unresolved"),
                                     ("outcome_ok", False), ("outcome_message", "another cause"),
                                     ("after_helper_absent", False), ("callbacks_retained", False),
                                     ("config_sha256", "0" * 64), ("outcome_bytes_hex", "00"),
                                     ("kernel_guard_retained", False), ("owner_guard_retained", False),
                                     ("live_configuration_retained", False)):
                    altered = copy.deepcopy(row)
                    altered["startup_proof"]["native"][field] = value
                    with self.assertRaises(campaign.CampaignError):
                        campaign.validate_refusal(altered, expected)
                altered = copy.deepcopy(row)
                altered["reason"] = altered["native"]["error"] = campaign.RUNWAY_START_REASON
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_refusal(altered, expected)

    def test_manifest_accepts_only_the_observed_start_rows(self):
        for cases, trim in ((campaign.RUNWAY_START_CASES, False), (campaign.TRIM_START_CASES, True)):
            for aircraft, spec in cases.items():
                for battery in spec["batteries"]:
                    for soft in (True, False):
                        with self.subTest(aircraft=aircraft, battery=battery, soft=soft):
                            expected, _, _ = runway_start_fixture(aircraft, soft, battery, trim)
                            manifest = {"format": "openrc-nk3-fleet-manifest v1", "aircraft": [aircraft], "rows": [expected]}
                            campaign.manifest_index(manifest)
                            for field, value in (("weather", "spatial-crosswind-v1"),
                                                 ("case", "trim"), ("expected_refusal_reason", "another cause"),
                                                 ("expected", "flight")):
                                altered = copy.deepcopy(manifest)
                                altered["rows"][0][field] = value
                                with self.assertRaises(campaign.CampaignError):
                                    campaign.manifest_index(altered)

    def test_matching_rehashed_forged_payloads_still_fail_the_pinned_observation(self):
        for field in ("frame", "config", "outcome", "live_config"):
            with self.subTest(field=field):
                expected, row, spec = runway_start_fixture()
                for proof in row["startup_proof"].values():
                    altered = b"different typed " + field.encode()
                    proof[field + "_bytes_hex"] = altered.hex()
                    proof[field + "_sha256"] = hashlib.sha256(altered).hexdigest()
                    if field == "frame":
                        proof["before_frame_bytes_hex"] = altered.hex()
                    if field == "live_config":
                        proof["before_live_config_bytes_hex"] = altered.hex()
                with mock.patch.dict(campaign.RUNWAY_START_CASES, {expected["aircraft"]: spec}):
                    with self.assertRaises(campaign.CampaignError):
                        campaign.validate_refusal(row, expected)

    def test_runway_start_rejects_owner_outcome_and_typed_identity_mutations(self):
        mutations = [
            lambda r: r.pop("startup_proof"),
            lambda r: r["startup_proof"]["native"].update(after_helper_absent=False),
            lambda r: r["startup_proof"]["native"].update(before_helper_absent=False),
            lambda r: r["startup_proof"]["native"].update(model_retained=False),
            lambda r: r["startup_proof"]["native"].update(callbacks_retained=False),
            lambda r: r["startup_proof"]["native"].update(reference_callbacks_before=False),
            lambda r: r["startup_proof"]["native"].update(reference_callbacks_after=False),
            lambda r: r["startup_proof"]["native"].update(kernel_guard_retained=False),
            lambda r: r["startup_proof"]["native"].update(owner_guard_retained=False),
            lambda r: r["startup_proof"]["native"].update(selection_valid_before=False),
            lambda r: r["startup_proof"]["native"].update(selection_valid_after=False),
            lambda r: r["startup_proof"]["native"].update(input_configuration_retained=False),
            lambda r: r["startup_proof"]["native"].update(live_configuration_retained=False),
            lambda r: r["startup_proof"]["native"].update(live_config_bytes_hex="00"),
            lambda r: r["startup_proof"]["native"].update(before_frame_bytes_hex="00"),
            lambda r: r["startup_proof"]["native"].update(outcome_status="invalid_input"),
            lambda r: r["startup_proof"]["native"].update(outcome_dictionary_empty=True),
            lambda r: r["startup_proof"]["native"].update(outcome_ok=True),
            lambda r: r["startup_proof"]["native"].update(outcome_empty=False),
            lambda r: r["startup_proof"]["native"].update(outcome_message="another cause"),
            lambda r: r["startup_proof"]["native"].update(aircraft_sha256="0" * 64),
            lambda r: r["startup_proof"]["native"]["after_status"].update(identity={"backend": "native"}),
            lambda r: r["startup_proof"]["native"].update(config_bytes_hex="00"),
            lambda r: r["startup_proof"]["native"].update(outcome_sha256="0" * 64),
            lambda r: r["startup_proof"]["native"].update(frame_bytes_hex="zz"),
            lambda r: r["startup_proof"]["native"].update(callbacks_retained=1),
            lambda r: r["native"].update(complete=True),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                expected, row, spec = runway_start_fixture()
                mutate(row)
                with mock.patch.dict(campaign.RUNWAY_START_CASES, {expected["aircraft"]: spec}):
                    with self.assertRaises(campaign.CampaignError):
                        campaign.validate_refusal(row, expected)

    def test_runway_start_rejects_other_rows_even_with_the_same_reason(self):
        for field, value in (("aircraft", "f4u-corsair-250"), ("weather", "spatial-crosswind-v1"),
                             ("battery", "pack"), ("case", "trim"), ("soft_hull", None)):
            with self.subTest(field=field):
                expected, row, spec = runway_start_fixture()
                expected[field] = row[field] = value
                with mock.patch.dict(campaign.RUNWAY_START_CASES, {"sebart-avanti-s-a200-p100rx": spec}):
                    with self.assertRaises(campaign.CampaignError):
                        campaign.validate_refusal(row, expected)

    def test_complete_union(self):
        manifest, reports, guard = fixtures()
        self.assertEqual(campaign.validate_reports(manifest, reports, guard, 2, 3),
                         {"declared": 3, "flight_passed": 2, "reference_refused": 1, "runtime_refused": 0})

    def test_bounded_runtime_refusal_is_separate_from_flights(self):
        manifest, reports, guard = runtime_fixture()
        self.assertEqual(campaign.validate_reports(manifest, reports, guard, 600, 2400),
                         {"declared": 1, "flight_passed": 0, "reference_refused": 0, "runtime_refused": 1})

    def test_fs64v_midpoint_refusal_is_separate_from_flights(self):
        for soft_hull in (True, False):
            with self.subTest(soft_hull=soft_hull):
                manifest, reports, guard = runtime_fixture("stik-glow-fs64v-4t", 805, 0.5, 2, soft_hull)
                self.assertEqual(campaign.validate_reports(manifest, reports, guard, 600, 2400),
                                 {"declared": 1, "flight_passed": 0, "reference_refused": 0, "runtime_refused": 1})

    def test_fs64v_rejects_wrong_phase_ordinals_and_forged_evidence(self):
        def fixture():
            return runtime_fixture("stik-glow-fs64v-4t", 805, 0.5, 2)

        def phase(row): row["runtime_domain"].update(warmup_completed=599, samples_completed=206)
        def ordinal(row):
            row["runtime_domain"].update(rejected_stage_calls=4, native_stage_calls=3224,
                                         native_diagnostic_stage_call=3224)
        def context_ordinal(row): row["runtime_domain"].update(rejected_context_calls=2)
        def diagnostic_ordinal(row): row["runtime_domain"].update(native_diagnostic_stage_call=3221)
        def diagnostic_stage_type(row): row["runtime_domain"].update(native_diagnostic_stage_call=3222.0)
        def diagnostic_context_type(row): row["runtime_domain"].update(native_diagnostic_context_call=806.0)
        def short_coverage(row): row["runtime_domain"].update(native_stage_calls=3221, native_diagnostic_stage_call=3221)
        def rollback(row): row["runtime_domain"].update(reference_rollback=False)
        def owner(row): row["runtime_domain"].update(native_owner_retained=False)
        def altered_aircraft(row):
            row["runtime_domain"].update(reference_aircraft_sha256="d" * 64, native_aircraft_sha256="d" * 64)
        def altered_endpoint(row):
            cause = row["runtime_domain"]
            cause["reference_cause"]["feed_factor"] = cause["native_cause"]["feed_factor"] = 2.0
        def mismatched_context(row): row["runtime_domain"].update(native_context_bytes_hex="00")
        for mutate in (phase, ordinal, context_ordinal, diagnostic_ordinal, diagnostic_stage_type,
                       diagnostic_context_type, short_coverage, rollback, owner,
                       altered_aircraft, altered_endpoint, mismatched_context):
            with self.subTest(case=mutate.__name__):
                manifest, reports, guard = fixture()
                mutate(next(iter(reports.values()))["fleet"][0])
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 600, 2400)

        for problem in ("stale", "forged-finite"):
            with self.subTest(context=problem):
                manifest, reports, guard = fixture()
                proof = next(iter(reports.values()))["fleet"][0]["runtime_domain"]
                decoded = campaign.decode_runtime_payload(FS64V_CONTEXT_HEX,
                                                          (14, 4, 5, "float", "float", "float", "bool", "bool"))
                if problem == "stale":
                    decoded[3] -= 1.0 / 240.0
                else:
                    decoded[0][0] = 0.01
                kinds = ("packed", "packed", "packed", "float", "float", "float", "bool", "bool")
                forged = encode_runtime_array(list(zip(kinds, decoded)))
                if problem == "forged-finite":
                    # Shape, time, and source flags alone cannot detect this alteration.
                    campaign.validate_runtime_payload(FS64V_TRIAL_HEX, forged.hex(), 805, 0.5)
                replace_runtime_payload(proof, "context", forged)
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 600, 2400)

    def test_fs64v_rejects_coherently_forged_cause(self):
        manifest, reports, guard = runtime_fixture("stik-glow-fs64v-4t", 805, 0.5, 2)
        proof = next(iter(reports.values()))["fleet"][0]["runtime_domain"]
        for cause in (proof["reference_cause"], proof["native_cause"]):
            cause.update(demand_nm=-0.02, friction_nm=0.01, prop_load_torque_nm=0.02,
                         axial_acceleration_rad_s2=0.0, rotor_inertia_kg_m2=0.01)
        with self.assertRaises(campaign.CampaignError):
            campaign.validate_reports(manifest, reports, guard, 600, 2400)

    def test_model_specific_trial_phase_and_ordinal_are_not_interchangeable(self):
        for aircraft, tick, stage_fraction, calls, wrong_fraction, wrong_calls in (
                ("stik-glow-fs64v-4t", 805, 0.5, 2, 1.0, 4),
                ("stik-glow-61fx-2t", 873, 1.0, 4, 0.5, 2),
                ("stik-glow-55ax-2t", 801, 1.0, 4, 0.5, 2)):
            with self.subTest(aircraft=aircraft):
                trial, context = runtime_payloads(tick, wrong_fraction)
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_runtime_payload(encode_runtime_array(trial).hex(),
                                                     encode_runtime_array(context).hex(), tick, stage_fraction)
                manifest, reports, guard = runtime_fixture(aircraft, tick, stage_fraction, calls)
                proof = next(iter(reports.values()))["fleet"][0]["runtime_domain"]
                proof.update(rejected_stage_calls=wrong_calls, native_stage_calls=4 * tick + wrong_calls,
                             native_diagnostic_stage_call=4 * tick + wrong_calls)
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 600, 2400)

    def test_runtime_refusal_rejects_missing_or_altered_proof(self):
        mutations = [
            lambda r: r.update(status="pass"), lambda r: r["native"].update(complete=True),
            lambda r: r["runtime_domain"].update(accepted_ticks=872),
            lambda r: r["runtime_domain"].update(samples_completed=274),
            lambda r: r["runtime_domain"].update(prefix_equal_every_tick=False),
            lambda r: r["runtime_domain"].update(native_owner_retained=False),
            lambda r: r["runtime_domain"].update(reference_owner_retained=False),
            lambda r: r["runtime_domain"].update(native_aircraft_sha256="d" * 64),
            lambda r: r["runtime_domain"]["reference_identity"].update(backend="native"),
            lambda r: r["runtime_domain"].update(native_covered_every_tick=False),
            lambda r: r["runtime_domain"].update(rejected_stage_calls=0),
            lambda r: r["runtime_domain"].update(rejected_context_calls=0),
            lambda r: r["runtime_domain"].update(native_diagnostic_stage_call=0),
            lambda r: r["runtime_domain"].update(trial_equal=False),
            lambda r: r["runtime_domain"].update(context_equal=False),
            lambda r: r["runtime_domain"].update(trial_bytes_hex="00"),
            lambda r: r["runtime_domain"]["native_end"].update(fault="unrelated"),
            lambda r: r["runtime_domain"]["native_identity"].update(backend="gdscript_reference"),
            lambda r: r["runtime_domain"]["native_cause"].update(code="unrelated"),
            lambda r: r["runtime_domain"]["native_cause"].update(feed_factor=1.0),
            lambda r: r["runtime_domain"]["native_cause"].update(demand_nm=float("nan")),
            lambda r: r["runtime_domain"]["native_cause"].update(friction_nm=0.5),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(case=index):
                manifest, reports, guard = runtime_fixture()
                mutate(next(iter(reports.values()))["fleet"][0])
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 600, 2400)

    def test_identical_invalid_reverse_boundaries_fail(self):
        for field, value in (("demand_nm", -0.01), ("demand_nm", -0.009), ("demand_nm", float("nan")),
                             ("rotor_inertia_kg_m2", 0.0), ("rotor_inertia_kg_m2", -1.0),
                             ("prop_load_torque_nm", 0.03)):
            with self.subTest(field=field, value=value):
                manifest, reports, guard = runtime_fixture()
                proof = next(iter(reports.values()))["fleet"][0]["runtime_domain"]
                proof["reference_cause"][field] = value
                proof["native_cause"][field] = value
                if field == "demand_nm" and math.isfinite(value):
                    proof["reference_cause"]["prop_load_torque_nm"] = -value
                    proof["native_cause"]["prop_load_torque_nm"] = -value
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 600, 2400)

    def test_identical_rehashed_malformed_payloads_fail(self):
        def short_body(trial, context): trial[0][1].pop()
        def short_continuous(trial, context): trial[1][1].pop()
        def nonfinite_body(trial, context): trial[0][1][0] = float("nan")
        def degenerate_attitude(trial, context): trial[0][1][6] = 0.0
        def wrong_mode(trial, context): trial[1][1][18] = 0.0
        def wrong_stage_time(trial, context): trial[2] = ("float", 0.0)
        def short_context(trial, context): context[0][1].pop()
        def nonfinite_input(trial, context): context[1][1][0] = float("inf")
        def wrong_tick_time(trial, context): context[3] = ("float", 0.0)
        def wrong_flags(trial, context): context[6] = ("bool", True)
        for mutate in (short_body, short_continuous, nonfinite_body, degenerate_attitude, wrong_mode,
                       wrong_stage_time, short_context, nonfinite_input, wrong_tick_time, wrong_flags):
            with self.subTest(case=mutate.__name__):
                manifest, reports, guard = runtime_fixture()
                proof = next(iter(reports.values()))["fleet"][0]["runtime_domain"]
                trial, context = runtime_payloads()
                mutate(trial, context)
                replace_runtime_payload(proof, "trial", encode_runtime_array(trial))
                replace_runtime_payload(proof, "context", encode_runtime_array(context))
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 600, 2400)

    def test_manifest_rejects_duplicates_and_missing_refusal_proof(self):
        manifest, _, _ = fixtures()
        manifest["rows"].append(copy.deepcopy(manifest["rows"][0]))
        with self.assertRaises(campaign.CampaignError):
            campaign.manifest_index(manifest)
        manifest, _, _ = fixtures()
        del manifest["rows"][1]["expected_refusal_reason"]
        with self.assertRaises(campaign.CampaignError):
            campaign.manifest_index(manifest)

    def test_missing_duplicate_and_filtered_shards_fail(self):
        def missing(m, r, g): del r["heli"]
        def duplicate(m, r, g): r["fixed"]["fleet"][1] = copy.deepcopy(r["fixed"]["fleet"][0])
        def extra(m, r, g): r["extra"] = r["heli"]
        def filter_weather(m, r, g): r["fixed"]["fleet_scope"]["filters"]["weather"] = "calm"
        def truncated(m, r, g): r["heli"]["fleet"] = []
        def wrong_aircraft(m, r, g): r["heli"]["fleet"][0]["aircraft"] = "fixed"
        for mutate in (missing, duplicate, extra, filter_weather, truncated, wrong_aircraft):
            with self.subTest(case=mutate.__name__):
                manifest, reports, guard = fixtures()
                mutate(manifest, reports, guard)
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 2, 3)

    def test_incomplete_fallback_and_changed_fingerprints_fail(self):
        mutations = [
            ("complete", False), ("actual", "gdscript_reference"), ("warmup_completed", 1),
            ("samples_completed", 2), ("fingerprint_boundaries", 5), ("context_calls", 4),
            ("stage_calls", 19), ("native_covered_every_tick", False), ("fingerprint", "e" * 64),
            ("aircraft_sha256", "e" * 64), ("stage_in_use", "_wheel_evaluate"),
        ]
        for key, value in mutations:
            with self.subTest(key=key):
                manifest, reports, guard = fixtures()
                reports["fixed"]["fleet"][0]["native"][key] = value
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 2, 3)
        manifest, reports, guard = fixtures()
        reports["fixed"]["fleet"][0]["native"]["identity"]["binary_sha256"] = "0" * 64
        with self.assertRaises(campaign.CampaignError):
            campaign.validate_reports(manifest, reports, guard, 2, 3)

    def test_heli_replay_requires_native_coverage(self):
        for field, value in (("replay_requested", 0), ("replay_completed", 4),
                             ("replay_ok", False), ("replay_native_covered", False)):
            with self.subTest(field=field):
                manifest, reports, guard = fixtures()
                reports["heli"]["fleet"][0]["native"][field] = value
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 2, 3)

    def test_refusal_requires_both_exact_reset_outcomes(self):
        mutations = [lambda r: r.update(status="pass"),
                     lambda r: r.update(fingerprint_equal=True),
                     lambda r: r["native"].update(phase="weather"),
                     lambda r: r["reference"].update(error="another failure"),
                     lambda r: r["native"].update(complete=True),
                     lambda r: r["native"].update(requested="gdscript_reference")]
        for mutate in mutations:
            manifest, reports, guard = fixtures()
            mutate(reports["fixed"]["fleet"][1])
            with self.assertRaises(campaign.CampaignError):
                campaign.validate_reports(manifest, reports, guard, 2, 3)

    def test_source_checks_and_checked_run_are_required(self):
        mutations = [
            lambda r: r.update(run_valid=False),
            lambda r: r["checked_run"].update(complete=False),
            lambda r: r["checked_run"]["counts"].update(error=1),
            lambda r: r["checked_run"]["command"].append("--weather=calm"),
            lambda r: r.update(binary_sha256_after="0" * 64),
            lambda r: r.update(engine_sha256_after="0" * 64),
            lambda r: r["reference_sources_after"].update({"app/changed.gd": "0" * 64}),
            lambda r: r["harness_sources"].update({"research/native-kernel/fleet.gd": "0" * 64}),
            lambda r: r["components"]["fleet_pair"].update(identical=0),
            lambda r: r["fleet_scope"].update(failed=False),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(case=index):
                manifest, reports, guard = fixtures()
                mutate(reports["fixed"])
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 2, 3)

    def test_live_source_mismatch_fails(self):
        _, reports, _ = fixtures()
        with self.assertRaises(campaign.CampaignError):
            campaign.validate_live_sources(reports["fixed"])

    def test_manifest_script_uses_actual_declaration(self):
        with tempfile.TemporaryDirectory() as temporary:
            script = Path(temporary) / "manifest.gd"
            campaign.write_manifest_script(script, Path(temporary) / "manifest.json")
            source = script.read_text(encoding="utf-8")
            self.assertIn("_fleet_declared_rows()", source)
            self.assertIn("_fleet_expected_refusal(row", source)
            self.assertNotIn("FLEET_PATH", source)
            self.assertNotIn("OUTPUT_PATH", source)

    def test_failed_shard_cancels_other_running_work(self):
        async def scenario():
            active = asyncio.Event()
            cancelled = asyncio.Event()

            async def fake_shard(aircraft, _out, _semaphore, _warmup, _samples, _timeout):
                if aircraft == "bad":
                    await active.wait()
                    raise campaign.CampaignError("intentional shard failure")
                active.set()
                try:
                    await asyncio.Event().wait()
                except asyncio.CancelledError:
                    cancelled.set()
                    raise

            with mock.patch.object(campaign, "run_shard", side_effect=fake_shard):
                with self.assertRaises(campaign.CampaignError):
                    await campaign.run_shards(["bad", "running"], Path("."), 2, 2, 3, 10)
            self.assertTrue(cancelled.is_set())

        asyncio.run(scenario())

    def test_keep_going_finishes_independent_shards_but_fails_campaign(self):
        async def scenario():
            completed = []

            async def fake_shard(aircraft, _out, _semaphore, _warmup, _samples, _timeout):
                await asyncio.sleep(0.01 if aircraft.startswith("bad") else 0.03)
                completed.append(aircraft)
                if aircraft.startswith("bad"):
                    raise campaign.CampaignError("deliberate shard failure")
                return aircraft, Path(aircraft)

            with mock.patch.object(campaign, "run_shard", side_effect=fake_shard):
                with self.assertRaises(campaign.CampaignError) as raised:
                    await campaign.run_shards(["bad-1", "good", "bad-2"], Path("."), 2, 2, 3, 10,
                                              keep_going=True)
            self.assertCountEqual(completed, ["bad-1", "good", "bad-2"])
            self.assertIn("bad-1", str(raised.exception))
            self.assertIn("bad-2", str(raised.exception))

        asyncio.run(scenario())

    def test_keep_going_returns_complete_successes(self):
        async def scenario():
            async def fake_shard(aircraft, _out, _semaphore, _warmup, _samples, _timeout):
                await asyncio.sleep(0.01)
                return aircraft, Path(aircraft)

            with mock.patch.object(campaign, "run_shard", side_effect=fake_shard):
                result = await campaign.run_shards(["first", "second"], Path("."), 2, 2, 3, 10,
                                                   keep_going=True)
            self.assertEqual(result, {"first": Path("first"), "second": Path("second")})

        asyncio.run(scenario())

    def test_keep_going_does_not_allow_source_drift(self):
        async def scenario():
            active = asyncio.Event()
            cancelled = asyncio.Event()
            guard = {"binary_sha256": "a" * 64}

            async def fake_shard(_aircraft, _out, _semaphore, _warmup, _samples, _timeout):
                active.set()
                try:
                    await asyncio.Event().wait()
                except asyncio.CancelledError:
                    cancelled.set()
                    raise

            with mock.patch.object(campaign, "run_shard", side_effect=fake_shard), \
                    mock.patch.object(campaign, "snapshot", return_value={"binary_sha256": "b" * 64}):
                with self.assertRaisesRegex(campaign.CampaignError, "snapshot changed"):
                    await campaign.run_shards(["running"], Path("."), 1, 2, 3, 10,
                                              guard=guard, monitor_interval=0.01, keep_going=True)
            self.assertTrue(active.is_set() and cancelled.is_set())

        asyncio.run(scenario())

    def test_reuse_waits_for_final_checked_run_and_rejects_failure(self):
        async def scenario():
            with tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "report.json"
                path.write_text('{"verdict":"pass"}', encoding="utf-8")

                async def finish():
                    await asyncio.sleep(0.01)
                    path.write_text('{"verdict":"pass","run_valid":true}', encoding="utf-8")

                writer = asyncio.create_task(finish())
                name, used = await campaign.wait_reused_report("heli", path, 4)
                await writer
                self.assertEqual((name, used), ("heli", path))
                path.write_text('{"verdict":"fail","run_valid":false}', encoding="utf-8")
                with self.assertRaises(campaign.CampaignError):
                    await campaign.wait_reused_report("heli", path, 1)

        asyncio.run(scenario())

    def test_live_drift_cancels_workers_with_clear_reason(self):
        async def scenario():
            active = asyncio.Event()
            cancelled = asyncio.Event()
            guard = {"binary_sha256": "a" * 64}

            async def fake_shard(_aircraft, _out, _semaphore, _warmup, _samples, _timeout):
                active.set()
                try:
                    await asyncio.Event().wait()
                except asyncio.CancelledError:
                    cancelled.set()
                    raise

            with mock.patch.object(campaign, "run_shard", side_effect=fake_shard), \
                    mock.patch.object(campaign, "snapshot", return_value={"binary_sha256": "b" * 64}):
                with self.assertRaisesRegex(campaign.CampaignError, "snapshot changed: binary_sha256"):
                    await campaign.run_shards(["running"], Path("."), 1, 2, 3, 10,
                                              guard=guard, monitor_interval=0.01)
            self.assertTrue(active.is_set())
            self.assertTrue(cancelled.is_set())

        asyncio.run(scenario())

    def test_live_drift_names_changed_mirrored_source(self):
        with tempfile.TemporaryDirectory(dir=campaign.ROOT / "tmp") as temporary:
            source = Path(temporary) / "source.gd"
            source.write_text("before", encoding="utf-8")
            name = str(source.relative_to(campaign.ROOT))
            guard = {"reference_sources": {name: campaign.sha256(source)}}
            source.write_text("after", encoding="utf-8")
            with mock.patch.object(campaign, "snapshot", side_effect=campaign.CampaignError("receipt stale")):
                reason = campaign.drift_reason(guard)
            self.assertIn("receipt stale", reason)
            self.assertIn(name, reason)

    def test_unchanged_snapshot_allows_completed_shards(self):
        async def scenario():
            guard = {"binary_sha256": "a" * 64}

            async def fake_shard(aircraft, _out, _semaphore, _warmup, _samples, _timeout):
                await asyncio.sleep(0.04)
                return aircraft, Path(aircraft)

            with mock.patch.object(campaign, "run_shard", side_effect=fake_shard), \
                    mock.patch.object(campaign, "snapshot", return_value=guard) as check:
                result = await campaign.run_shards(["fixed"], Path("."), 1, 2, 3, 10,
                                                   guard=guard, monitor_interval=0.01)
            self.assertEqual(result, {"fixed": Path("fixed")})
            self.assertGreater(check.call_count, 0)

        asyncio.run(scenario())


if __name__ == "__main__":
    unittest.main()
