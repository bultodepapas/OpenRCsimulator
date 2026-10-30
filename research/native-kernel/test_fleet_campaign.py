#!/usr/bin/env python3
"""Failure-oriented tests for aggregation of native fleet evidence."""
from __future__ import annotations

import asyncio
import base64
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import tempfile
import unittest
import zlib
from unittest import mock

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("fleet_campaign", HERE / "fleet_campaign.py")
assert SPEC is not None and SPEC.loader is not None
campaign = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(campaign)


class MoonRunnerQualificationTests(unittest.TestCase):
    def test_pending_rows_fail_manifest_and_aggregate_for_every_claim(self):
        for battery, start, weather, default in (
                ("ideal", "airborne_half_power", "hot-high", False),
                ("pack", "hand_launch", "spatial-crosswind-v1", True)):
            for soft in (True, False):
                for expected in (None, "unqualified", "flight", "reference-refusal", "physical-terminal"):
                    with self.subTest(start=start, soft=soft, expected=expected):
                        row = {"aircraft": "moonrunner-x99", "vehicle": "fixed-wing", "battery": battery,
                               "case": start, "weather": weather, "default_battery": default, "soft_hull": soft}
                        if expected is not None:
                            row["expected"] = expected
                        manifest = {"format": "openrc-nk3-fleet-manifest v1",
                                    "aircraft": ["moonrunner-x99"], "rows": [row]}
                        with self.assertRaisesRegex(campaign.CampaignError, "MoonRunner requalification required"):
                            campaign.manifest_index(manifest)
                        for warmup, samples in ((1, 1), (600, 2400)):
                            with self.assertRaisesRegex(campaign.CampaignError, "MoonRunner requalification required"):
                                campaign.validate_reports(manifest, {}, {}, warmup, samples)

    def test_adjacent_rows_and_historical_identity_are_not_pending(self):
        row = {"aircraft": "moonrunner-x99", "vehicle": "fixed-wing", "battery": "pack",
               "case": "hand_launch", "weather": "spatial-crosswind-v1", "default_battery": True,
               "soft_hull": True}
        for field, value in (("aircraft", "skywalker-x8"), ("vehicle", "rotorcraft"),
                             ("battery", "ideal"), ("case", "trim"), ("weather", "calm")):
            with self.subTest(field=field):
                changed = dict(row, **{field: value})
                self.assertFalse(campaign.moonrunner_unqualified(changed))
        self.assertFalse(campaign.physical_terminal_boundary(row))
        self.assertTrue(campaign.physical_terminal_boundary(dict(row, aircraft="skywalker-x8")))

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


# Actual terminal Variant and its full-precision oracle JSON projection,
# decoded independently from the recorded collision on both hull settings.
TERMINAL_FULL_VIEW_JSON = (
    '{"commands":{"pitch":0.0,"roll":0.0,"throttle":1.0,"yaw":0.0},"contacts":{"active_hull_ids":[],"even'
    'ts":[{"contact_id":"tree:shade-tree:shade-trees:06:crown","event_id":"as13:impact:scenery:1640:new:3'
    '6:tree:shade-tree:shade-trees:06:crown","event_type":"impact","format":"openrc-aircraft-contact-even'
    'ts v1","lifecycle":"new","measure":{"dissipated_energy_j":0.0,"down_speed_mps":23.196051195422534,"e'
    'ffective_mass_kg":1.237544184741614,"impact_energy_j":332.93452641892867,"normal_speed_mps":23.19605'
    '1195422534,"restitution":0.0,"speed_mps":33.718832120605505},"normal_ned":[0.0,0.0,-1.0],"obstacle_k'
    'ind":"tree_foliage","obstacle_part":"crown","point_index":3,"point_ned":[-33.506406908787525,16.5172'
    '53178905257,-14.000002969226014],"policy":"scenery-response-v1:cr-17a-scenery-damage-v1","probe_id":'
    '"probe_nose_left_low","probe_source":"hull","response":"terminal","response_class":"soft_foliage_imp'
    'ulse","response_status":"terminal","source":"scenery","tick":1640,"time_fraction":0.5195759183769976'
    ',"velocity_ned":[-8.595895357007315,22.913171572881275,23.196051195422534]}],"format":"openrc-aircra'
    'ft-contact-state v1","prop_strike":{},"tick":1640},"crash":{"impact":{"_state_at_contact":[-33.51765'
    '521744055,16.23473532549036,-14.30887007169522,33.33829465400774,4.5978074842349494,2.53483512851945'
    '44,-0.6475687732405211,-0.16051344560067352,0.3758021464008154,-0.6431662805726884,0.204718954197765'
    '37,1.2172174283273376,-0.03417532498064766],"body_point":[0.4141190000001411,-0.0616,0.0072555339101'
    '6595],"component_name":"","compression_m":0.0,"contact_mass_properties":{},"damage_id":"prop:shade-t'
    'rees:06:crown","damage_profile":"foliage_mark","dissipated_energy_j":0.0,"down_speed_mps":23.1960511'
    '95422534,"effective_mass_kg":1.237544184741614,"has_compression":false,"has_kinematics":true,"impact'
    '_energy_j":332.93452641892867,"normal_ned":[0.0,0.0,-1.0],"normal_speed_mps":23.196051195422534,"obs'
    'tacle_id":"tree:shade-tree:shade-trees:06:crown","obstacle_kind":"tree_foliage","obstacle_part":"cro'
    'wn","point_index":3,"point_ned":[-33.506406908787525,16.517253178905257,-14.000002969226014],"respon'
    'se_class":"soft_foliage_impulse","response_status":"terminal","restitution":0.0,"soft_rule":"","spee'
    'd_mps":33.718832120605505,"terminal":true,"tick":1640,"time_fraction":0.5195759183769976,"travel_lim'
    'it_m":0.0,"trigger":"scenery","velocity_ned":[-8.595895357007315,22.913171572881275,23.1960511954225'
    '34]},"sink":23.531199679319815,"speed":33.74917944525917,"ticks_left":360,"why":"tree foliage impact'
    ' (tree:shade-tree:shade-trees:06:crown), normal speed 23.2 m/s"},"fault":"","last_scenery":{"_state_'
    'at_contact":[-33.51765521744055,16.23473532549036,-14.30887007169522,33.33829465400774,4.59780748423'
    '49494,2.5348351285194544,-0.6475687732405211,-0.16051344560067352,0.3758021464008154,-0.643166280572'
    '6884,0.20471895419776537,1.2172174283273376,-0.03417532498064766],"body_point":[0.4141190000001411,-'
    '0.0616,0.00725553391016595],"component_name":"","compression_m":0.0,"contact_mass_properties":{},"da'
    'mage_id":"prop:shade-trees:06:crown","damage_profile":"foliage_mark","dissipated_energy_j":0.0,"down'
    '_speed_mps":23.196051195422534,"effective_mass_kg":1.237544184741614,"has_compression":false,"has_ki'
    'nematics":true,"impact_energy_j":332.93452641892867,"normal_ned":[0.0,0.0,-1.0],"normal_speed_mps":2'
    '3.196051195422534,"obstacle_id":"tree:shade-tree:shade-trees:06:crown","obstacle_kind":"tree_foliage'
    '","obstacle_part":"crown","point_index":3,"point_ned":[-33.506406908787525,16.517253178905257,-14.00'
    '0002969226014],"response_class":"soft_foliage_impulse","response_status":"terminal","restitution":0.'
    '0,"soft_rule":"","speed_mps":33.718832120605505,"terminal":true,"tick":1640,"time_fraction":0.519575'
    '9183769976,"travel_limit_m":0.0,"trigger":"scenery","velocity_ned":[-8.595895357007315,22.9131715728'
    '81275,23.196051195422534]},"pause_reason":"CRASH at 33.7 m/s (sink 23.5 m/s, tree foliage impact (tr'
    'ee:shade-tree:shade-trees:06:crown), normal speed 23.2 m/s) - [R] restart","paused":true,"pending_cr'
    'ash":{},"pending_damage":{},"pending_scenery":{},"raw":{"pitch":0.0,"roll":0.0,"throttle":0.0,"yaw":'
    '0.0},"scenery_damage":{"prop:shade-trees:06:crown":{"energy_j":332.93452641892867,"normal_ned":[0.0,'
    '0.0,-1.0],"obstacle_id":"tree:shade-tree:shade-trees:06:crown","point_ned":[-33.506406908787525,16.5'
    '17253178905257,-14.000002969226014],"profile":"foliage_mark","state":"marked","tick":1640,"velocity_'
    'ned":[-8.595895357007315,22.913171572881275,23.196051195422534]}},"tick":1640}'
)

TERMINAL_TYPED_VIEW_ZLIB_B64 = (
    'eNrtWFtoXEUYPumm95tal1JS6InGmki25tImsLbusQpeQKTtgw8Sh+nZ2ew058bM7MZ9KBYRBbVPCiposIggiLbVovVpY1EEMUJ8'
    'kiK2aH0QRCx5qW0Q/7ntnm6TtqQqCikMmzPz3//v//+ZdjiOsxZWFlY7LEH9sSXwW16m9+DHSXCFk6LjtDl6yf2lsEq4EgjD55j9'
    'NZYeMYJ5HMmzZ2Ddv/e+fQ+5WLiDg9uG3fBu7nZzGo25A4PbdsjPXlcwQtxSHFA8SlwaJtgXbrfczPMyLpJcy5883zeU91k8HvX0'
    'ulHMQhy4PCGkKEUOSJE9bs59Yu+IywgXmImm3T7DvAy/Hebb7it2+M2AlxObj23++Yzn2bhIY+X+0n2nPpp9fljtrzLx4iggJZCv'
    '4tam5WVgjZdrinePpPu7vXOa+dHitD9bjL2rYcX7wXE/IIgW1V6XseNaKiXtSlhFHIK1klvL3CRzy+JkTiZDs67JB6QlGhC9L3Fh'
    '3EchZmPtBncNG8doZPWsMXYiw3AFbaLSqWh1Pi/XDwlP4ggg6AeYc71/q8xhXBJWJoKgVQKuZK9P84AKUeGKZ4W0g7CQRjiwMZVg'
    'oqIiaBypHDtG7wbpN+WcJliQIiIRYaM1dOAymrUKLyH4xSBfUoLG2k+zW98feetsQdLcBEvnG6l8ozDhkqb6gUf7BoY9SXMzLFIq'
    'EZBRldHkHI2NGlmvbznceenrmYL1S2MjbU+bUy//MT3zjfBafbT1bXWoWBCEBfLjSCiIOZ3Gj9JnHz63+5Q3GQ/sfnPjzj5v6uHp'
    '4a6J3snZo7t2Pfqe52HU/c6dxVu84+en3n78wXbvwt4zd/x48lx95K6P0YkXP69nTt7OutZ+V3jVn+DTr5yr//bIy+vu2f5VYctr'
    'waWTtZnC1MF7J8Knj9SlLRtljrUF2lsJQsIEJVxh3sZ3ucINHR0lrPHNfem6rsPW/mZzmsQ0EgjwR55SNZxJYcmPQ8AFgfMIh6TZ'
    '69pN/e+PizWkBOjYSN4LX9KLvx46XfjW+WHJyheO1tGO+uGLnxwsWJllzCXcSYjBGt7sq7butD2R6kVW5p+nV5+fnvQmo62PnTjw'
    'bJ+3rnLEd5zeSVsvVRLEPhU1yWZ5Xnpy58Cm/s7Jas+nb3zxy5CXxtCqJs6UIssz97/f69a2BigN3va8e/bYku89r1H7UIooRdSK'
    '3fXGfxlXqCUuq6CtpUZSZyhM2WV1CIbBXRTQkApJkD5faeucVWTruWw2rWjiiKd7/zLVmyAWQtO7stckJGJ+DlMG06IkcoYvp0rC'
    'rfbPNy+lf1gXZrkSBNA8uXNbygapi1QBTxCbzeB5h8l9R2oGt9rTeRV7tCwwKIVJtYdELSFNeXZG2JrXNLQovx+QNvP+wbwmypua'
    'yfcPbe/LR2Q8PziUv965MVeNLVM5qTCfOHPW5apUfcths5BZFVDohzW/kXOJCTC9oT+Btu/X9FlvU3/O9v1ctR8E5vqHcc4e6TEG'
    'BzZmlna+2TBfH1mj5+Z+GC4qCjZOEiBWlj7X+djQ+I5imEjycoGCePw/3x9kXkO49VUYUXhenq7JG+wb//ZcvJ55frX7wP/tbnOt'
    'u0nWYhxGL8hhdIw0Zm/W2GYKB+nCcRq97Xrujh3GpqzBjb08znV3bNzXZS9O9Ux5JrE6X29Wfc8kMp3v7ALqKruAGskuoBazN3iX'
    'tzoBLQKZBC2+ExbfCYvvhMV3wuI7Ye53gpQN1+0ijUZR+v+K7Pn61LnFTesstOfpWWjPpR0Mj6u99tS9n8VBkEnRyZ6VUOGXU75Z'
    '/hrwZ1reNqLMYiECkrnizROGOCryf1bfocJfAgG/rw=='
)


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
                    "flight_passed": flights, "reference_refused": refusals, "runtime_refused": 0, "physical_terminal": 0},
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


def terminal_fixture(soft=True):
    """Use the real typed terminal view; other typed payloads are bounded stand-ins."""
    row = {"aircraft": "skywalker-x8", "vehicle": "fixed-wing", "battery": "pack", "case": "hand_launch",
           "weather": "spatial-crosswind-v1", "soft_hull": soft, "default_battery": True,
           "expected": "physical-terminal", "expected_terminal_tick": 1640}
    _, reports, guard = fixtures()
    guard["binary_sha256"] = campaign.TERMINAL_NATIVE_IDENTITY["binary_sha256"]
    guard["receipt"]["source_sha256"] = campaign.TERMINAL_NATIVE_IDENTITY["source_sha256"]
    guard["receipt"]["lock_sha256"] = campaign.TERMINAL_NATIVE_IDENTITY["lock_sha256"]
    view = json.loads(TERMINAL_FULL_VIEW_JSON)
    payload_names = tuple(campaign.TERMINAL_IDENTITIES) + tuple(campaign.TERMINAL_CONFIGS[soft])
    payloads = {name: ("typed-" + name).encode() for name in payload_names}
    payloads["terminal_view"] = zlib.decompress(base64.b64decode(TERMINAL_TYPED_VIEW_ZLIB_B64, validate=True))
    identities = {name: hashlib.sha256(payloads[name]).hexdigest() for name in campaign.TERMINAL_IDENTITIES}
    configs = {name: hashlib.sha256(payloads[name]).hexdigest() for name in campaign.TERMINAL_CONFIGS[soft]}
    proof = {"code": campaign.TERMINAL_CODE, "aircraft_sha256": campaign.TERMINAL_AIRCRAFT,
             "world_identity": campaign.TERMINAL_WORLD, "accepted_ticks": 1640, "requested_ticks": 3000,
             "warmup_completed": 600, "samples_completed": 1040, "prefix_boundaries": 1641,
             "terminal_tick": 1640, "stopped_attempts": 2, "reference_input_reads": 1640,
             "native_input_reads": 1640, "native_context_calls": 1640, "native_stage_calls": 6560,
             "reference_prefix_sha256": campaign.TERMINAL_PREFIX, "native_prefix_sha256": campaign.TERMINAL_PREFIX,
             "reference_view_prefix_sha256": campaign.TERMINAL_VIEW_PREFIX,
             "native_view_prefix_sha256": campaign.TERMINAL_VIEW_PREFIX,
             "reference_identity": {"backend": "gdscript_reference"},
             "native_identity": copy.deepcopy(campaign.TERMINAL_NATIVE_IDENTITY), "terminal_view": view}
    for name in ("prefix_equal_every_tick", "view_equal_every_tick", "native_owner_every_tick",
                 "reference_owner_every_tick", "model_contract_retained", "native_covered_every_tick",
                 "physical_configuration_retained", "live_configuration_retained", "no_holds",
                 "one_input_each_every_tick", "terminal_accepted", "previous_state_retained", "stopped_unchanged"):
        proof[name] = True
    for name, raw in payloads.items():
        proof[name + "_bytes_hex"] = raw.hex()
        proof[name + "_sha256"] = hashlib.sha256(raw).hexdigest()
    proof["stopped_frame_bytes_hex"] = proof["terminal_frame_bytes_hex"]
    proof["stopped_view_bytes_hex"] = proof["terminal_view_bytes_hex"]
    result = {**row, "status": "physical-terminal", "reason": campaign.TERMINAL_CODE,
              "fingerprint_equal": False, "reference": {"complete": False, "requested": "gdscript_reference"},
              "native": {"complete": False, "requested": "native"}, "physical_terminal": proof}
    report = copy.deepcopy(reports["fixed"])
    report["binary_sha256_before"] = report["binary_sha256_after"] = guard["binary_sha256"]
    report["build_receipt"] = copy.deepcopy(guard["receipt"])
    report["checked_run"]["command"] = ["godot", "--extension=res://native/kernel/openrc_native_kernel.gdextension",
                                        "--aircraft=skywalker-x8", "--warmup=600", "--samples=2400"]
    report["fleet_scope"].update(filters={"aircraft": "skywalker-x8", "weather": "", "soft_hull": ""},
                                 declared_aircraft=["skywalker-x8"], declared_rows=1, selected_rows=1,
                                 warmup_requested=600, samples_requested=2400, flight_passed=0,
                                 reference_refused=0, runtime_refused=0, physical_terminal=1)
    report["fleet"] = [result]
    report["components"] = {"literals": {"count": 1, "identical": 1},
                            "fleet_physical_terminal": {"count": 1, "identical": 1}}
    report["total"] = {"compared": 2, "identical": 2, "mismatched": 0}
    manifest = {"format": "openrc-nk3-fleet-manifest v1", "aircraft": ["skywalker-x8"], "rows": [row]}
    return manifest, {"skywalker-x8": report}, guard, identities, configs


def json_bytes(value):
    import json
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode()


class FleetCampaignTests(unittest.TestCase):
    def test_terminal_view_uses_the_full_precision_typed_projection(self):
        for soft in (True, False):
            _, reports, _, identities, _ = terminal_fixture(soft)
            proof = reports["skywalker-x8"]["fleet"][0]["physical_terminal"]
            with self.subTest(soft=soft):
                self.assertEqual(identities["terminal_view"], campaign.TERMINAL_IDENTITIES["terminal_view"])
                self.assertEqual(hashlib.sha256(json_bytes(proof["terminal_view"])).hexdigest(),
                                 campaign.TERMINAL_VIEW_JSON)

    def test_terminal_view_rejects_the_recorded_reduced_precision_projection(self):
        def reduced(value):
            if isinstance(value, float):
                return float(format(value, ".15g"))
            if isinstance(value, list):
                return [reduced(item) for item in value]
            if isinstance(value, dict):
                return {key: reduced(item) for key, item in value.items()}
            return value

        for soft in (True, False):
            manifest, reports, guard, identities, configs = terminal_fixture(soft)
            proof = reports["skywalker-x8"]["fleet"][0]["physical_terminal"]
            proof["terminal_view"] = reduced(proof["terminal_view"])
            # This is the exact old diagnostic projection, not a tolerance case.
            self.assertEqual(hashlib.sha256(json_bytes(proof["terminal_view"])).hexdigest(),
                             "7b8e59666676db2baeb0e0b873fe14751e90c891305d9eff0365d790c330426d")
            with self.subTest(soft=soft), mock.patch.object(campaign, "TERMINAL_IDENTITIES", identities), \
                    mock.patch.dict(campaign.TERMINAL_CONFIGS, {soft: configs}), \
                    self.assertRaisesRegex(campaign.CampaignError, "JSON metadata differs"):
                campaign.validate_reports(manifest, reports, guard, 600, 2400)

    def test_terminal_view_rejects_single_ulp_and_coherently_rehashed_typed_mutation(self):
        for soft in (True, False):
            for mutate_typed in (False, True):
                manifest, reports, guard, identities, configs = terminal_fixture(soft)
                proof = reports["skywalker-x8"]["fleet"][0]["physical_terminal"]
                impact = proof["terminal_view"]["crash"]["impact"]
                before = impact["time_fraction"]
                after = math.nextafter(before, math.inf)
                impact["time_fraction"] = after
                if mutate_typed:
                    raw = bytes.fromhex(proof["terminal_view_bytes_hex"])
                    old, new = struct.pack("<d", before), struct.pack("<d", after)
                    self.assertEqual(raw.count(old), 3)
                    forged = raw.replace(old, new, 1)  # First occurrence is crash.impact.time_fraction.
                    proof["terminal_view_bytes_hex"] = forged.hex()
                    proof["terminal_view_sha256"] = hashlib.sha256(forged).hexdigest()
                    proof["stopped_view_bytes_hex"] = forged.hex()
                reason = "terminal_view differs" if mutate_typed else "JSON metadata differs"
                with self.subTest(soft=soft, mutate_typed=mutate_typed), \
                        mock.patch.object(campaign, "TERMINAL_IDENTITIES", identities), \
                        mock.patch.dict(campaign.TERMINAL_CONFIGS, {soft: configs}), \
                        self.assertRaisesRegex(campaign.CampaignError, reason):
                    campaign.validate_reports(manifest, reports, guard, 600, 2400)

    def test_observed_physical_terminal_is_counted_separately(self):
        for soft in (True, False):
            manifest, reports, guard, identities, configs = terminal_fixture(soft)
            with self.subTest(soft=soft), mock.patch.object(campaign, "TERMINAL_IDENTITIES", identities), \
                    mock.patch.dict(campaign.TERMINAL_CONFIGS, {soft: configs}):
                self.assertEqual(campaign.validate_reports(manifest, reports, guard, 600, 2400),
                                 {"declared": 1, "flight_passed": 0, "reference_refused": 0,
                                  "runtime_refused": 0, "physical_terminal": 1})

    def test_physical_terminal_rejects_other_rows_and_forged_evidence(self):
        for field, value in (("aircraft", "other"), ("battery", "ideal"), ("case", "trim"),
                             ("weather", "crosswind"), ("vehicle", "rotorcraft"),
                             ("soft_hull", 1), ("default_battery", 1), ("expected_terminal_tick", 1639)):
            with self.subTest(row_field=field):
                manifest, reports, guard, identities, configs = terminal_fixture()
                manifest["rows"][0][field] = value
                with self.assertRaises(campaign.CampaignError):
                    campaign.manifest_index(manifest)
        mutations = [
            lambda r: r.update(status="pass"),
            lambda r: r.update(expected_terminal_tick=1640.0),
            lambda r: r["native"].update(complete=True),
            lambda r: r["physical_terminal"].update(terminal_tick=1639),
            lambda r: r["physical_terminal"].update(terminal_accepted=False),
            lambda r: r["physical_terminal"].update(previous_state_retained=False),
            lambda r: r["physical_terminal"].update(stopped_unchanged=False),
            lambda r: r["physical_terminal"].update(stopped_attempts=1),
            lambda r: r["physical_terminal"].update(stopped_frame_bytes_hex="00"),
            lambda r: r["physical_terminal"].update(native_covered_every_tick=False),
            lambda r: r["physical_terminal"].update(native_owner_every_tick=False),
            lambda r: r["physical_terminal"].update(model_contract_retained=False),
            lambda r: r["physical_terminal"].update(physical_configuration_retained=False),
            lambda r: r["physical_terminal"].update(live_configuration_retained=False),
            lambda r: r["physical_terminal"].update(no_holds=False),
            lambda r: r["physical_terminal"].update(native_context_calls=1639),
            lambda r: r["physical_terminal"].update(native_stage_calls=6559),
            lambda r: r["physical_terminal"]["native_identity"].update(binary_sha256="0" * 64),
            lambda r: r["physical_terminal"]["native_identity"].update(backend_version="other"),
            lambda r: r["physical_terminal"].update(reference_prefix_sha256="0" * 64,
                                                   native_prefix_sha256="0" * 64),
            lambda r: r["physical_terminal"]["terminal_view"]["crash"]["impact"].update(obstacle_id="other"),
            lambda r: r["physical_terminal"]["terminal_view"]["raw"].update(throttle=1.0),
            lambda r: r["physical_terminal"]["terminal_view"]["commands"].update(throttle=0.0),
        ]
        for name in ("terminal_frame", "terminal_view", "contact_event", "impact",
                     "physical_configuration", "reference_live_configuration", "native_live_configuration"):
            def forged(r, name=name):
                p = r["physical_terminal"]
                p[name + "_bytes_hex"] = "00"
                p[name + "_sha256"] = hashlib.sha256(b"\0").hexdigest()
                if name == "terminal_frame": p["stopped_frame_bytes_hex"] = "00"
                if name == "terminal_view": p["stopped_view_bytes_hex"] = "00"
            mutations.append(forged)
        def paired_forged_configs(r):
            p = r["physical_terminal"]
            for side in ("reference", "native"):
                p[side + "_live_configuration_bytes_hex"] = "00"
                p[side + "_live_configuration_sha256"] = hashlib.sha256(b"\0").hexdigest()
        mutations.append(paired_forged_configs)
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                manifest, reports, guard, identities, configs = terminal_fixture()
                mutate(reports["skywalker-x8"]["fleet"][0])
                with mock.patch.object(campaign, "TERMINAL_IDENTITIES", identities), \
                        mock.patch.dict(campaign.TERMINAL_CONFIGS, {True: configs}), \
                        self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 600, 2400)

    def test_short_terminal_horizon_is_still_a_healthy_flight(self):
        manifest, terminal_reports, _, _, _ = terminal_fixture()
        _, reports, guard = fixtures()
        report = reports["fixed"]
        flight = report["fleet"][0]
        flight.update(manifest["rows"][0])
        report["fleet"] = [flight]
        report["checked_run"]["command"] = [arg.replace("--aircraft=fixed", "--aircraft=skywalker-x8")
                                            for arg in report["checked_run"]["command"]]
        report["fleet_scope"].update(filters={"aircraft": "skywalker-x8", "weather": "", "soft_hull": ""},
                                     declared_aircraft=["skywalker-x8"], declared_rows=1, selected_rows=1,
                                     flight_passed=1, reference_refused=0, runtime_refused=0, physical_terminal=0)
        report["components"] = {"literals": {"count": 1, "identical": 1},
                                "fleet_pair": {"count": 1, "identical": 1}}
        report["total"] = {"compared": 2, "identical": 2, "mismatched": 0}
        self.assertEqual(campaign.validate_reports(manifest, {"skywalker-x8": report}, guard, 2, 3)["flight_passed"], 1)
        report["fleet"][0] = terminal_reports["skywalker-x8"]["fleet"][0]
        with self.assertRaises(campaign.CampaignError):
            campaign.validate_reports(manifest, {"skywalker-x8": report}, guard, 2, 3)

    def test_terminal_at_exact_requested_horizon_is_not_a_healthy_flight(self):
        manifest, reports, guard, identities, configs = terminal_fixture()
        report = reports["skywalker-x8"]
        report["checked_run"]["command"][-1] = "--samples=1040"
        report["fleet_scope"]["samples_requested"] = 1040
        report["fleet"][0]["physical_terminal"]["requested_ticks"] = 1640
        with mock.patch.object(campaign, "TERMINAL_IDENTITIES", identities), \
                mock.patch.dict(campaign.TERMINAL_CONFIGS, {True: configs}):
            totals = campaign.validate_reports(manifest, reports, guard, 600, 1040)
        self.assertEqual(totals["physical_terminal"], 1)
        self.assertEqual(totals["flight_passed"], 0)

    def test_observed_startup_proofs_count_only_as_refusals(self):
        for aircraft, trim in (("sebart-avanti-s-a200-p100rx", False), ("skywalker-x8", True)):
            with self.subTest(aircraft=aircraft):
                expected, row, spec = runway_start_fixture(aircraft, trim=trim)
                manifest, reports, guard = startup_campaign_fixture(expected, row)
                cases = campaign.TRIM_START_CASES if trim else campaign.RUNWAY_START_CASES
                with mock.patch.dict(cases, {aircraft: spec}):
                    self.assertEqual(campaign.validate_reports(manifest, reports, guard, 2, 3),
                                     {"declared": 1, "flight_passed": 0, "reference_refused": 1, "runtime_refused": 0, "physical_terminal": 0})

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
                         {"declared": 3, "flight_passed": 2, "reference_refused": 1, "runtime_refused": 0, "physical_terminal": 0})

    def test_bounded_runtime_refusal_is_separate_from_flights(self):
        manifest, reports, guard = runtime_fixture()
        self.assertEqual(campaign.validate_reports(manifest, reports, guard, 600, 2400),
                         {"declared": 1, "flight_passed": 0, "reference_refused": 0, "runtime_refused": 1, "physical_terminal": 0})

    def test_fs64v_midpoint_refusal_is_separate_from_flights(self):
        for soft_hull in (True, False):
            with self.subTest(soft_hull=soft_hull):
                manifest, reports, guard = runtime_fixture("stik-glow-fs64v-4t", 805, 0.5, 2, soft_hull)
                self.assertEqual(campaign.validate_reports(manifest, reports, guard, 600, 2400),
                                 {"declared": 1, "flight_passed": 0, "reference_refused": 0, "runtime_refused": 1, "physical_terminal": 0})

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
