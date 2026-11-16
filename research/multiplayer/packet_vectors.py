#!/usr/bin/env python3
"""Emit synthetic vectors for the unimplemented MP-01 pose contract; stdlib only.

This is research input for an independent Godot codec, not a decoder or a runtime
qualification. No network, engine, filesystem write, or external package is used.
Run from the repository root and redirect stdout to a new file to inspect changes.
The authoritative field meanings live in docs/plans/multiplayer-protocol.md.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct


FORMAT = "<2sBBHHIIIIIIqQ3d4f3f3f4hfHH"
POSE = struct.Struct(FORMAT)


def encode(fields: dict) -> bytes:
    """Pack known synthetic inputs, without claiming to validate untrusted data."""
    return POSE.pack(
        b"OR", 1, 1, 0, 48,
        fields["room_low_u32"], fields["room_high_u32"], fields["entity_id"],
        fields["epoch"], fields["sequence"], fields["config_revision"],
        int(fields["sample_time_us"]), int(fields["sim_tick"]),
        *fields["position_datum_ned_m"], *fields["body_to_ned_wxyz"],
        *fields["velocity_datum_ned_mps"], *fields["angular_body_frd_radps"],
        *fields["surfaces_centidegrees"], fields["rpm"], fields["throttle_u16"], 0,
    )


def record(name: str, packet: bytes, expectation: str, reason: str,
           fields: dict | None = None) -> dict:
    result = {
        "id": name,
        "bytes": len(packet),
        "hex": packet.hex(),
        "sha256": hashlib.sha256(packet).hexdigest(),
        "outer_guard_expectation": expectation,
        "reason": reason,
    }
    if fields is not None:
        result["input_fields"] = fields
    return result


def patched(packet: bytes, offset: int, fmt: str, *values) -> bytes:
    result = bytearray(packet)
    struct.pack_into("<" + fmt, result, offset, *values)
    return bytes(result)


def document() -> dict:
    if POSE.size != 128:
        raise RuntimeError("The candidate pose must remain exactly 128 bytes")
    base = {
        "room_low_u32": 0x01234567,
        "room_high_u32": 0x89ABCDEF,
        "entity_id": 7,
        "epoch": 3,
        "sequence": 42,
        "config_revision": 2,
        "sample_time_us": "1000000",
        "sim_tick": "240",
        "position_datum_ned_m": [12.5, -3.25, -10.0],
        "body_to_ned_wxyz": [1.0, 0.0, 0.0, 0.0],
        "velocity_datum_ned_mps": [25.0, 0.0, 0.0],
        "angular_body_frd_radps": [0.0, 0.0, 0.0],
        "surfaces_centidegrees": [125, -125, 250, -375],
        "rpm": 6000.0,
        "throttle_u16": 32768,
    }
    packet = encode(base)
    cases = [record("identity", packet, "pass",
                    "Synthetic identity attitude; admission and aircraft limits remain external", base)]
    yaw = dict(base, sequence=43, sample_time_us="1050000", sim_tick="252",
               body_to_ned_wxyz=[math.sqrt(0.5), 0.0, 0.0, math.sqrt(0.5)],
               velocity_datum_ned_mps=[0.0, 25.0, 0.0],
               angular_body_frd_radps=[0.0, 0.0, 1.5])
    cases.append(record("yaw_90", encode(yaw), "pass",
                        "Positive body-to-NED yaw maps forward velocity north to east", yaw))
    paused = dict(base, sequence=0, sample_time_us="-250000", sim_tick="0",
                  velocity_datum_ned_mps=[0.0, 0.0, 0.0], rpm=0.0, throttle_u16=0)
    cases.append(record("paused_before_host_start", encode(paused), "pass",
                        "Negative sample time is representable; only a validated paused baseline/status may use this old sample", paused))
    cases.append(record("short", packet[:-1], "reject", "Length is 127, not 128"))
    cases.append(record("long", packet + b"\x00", "reject", "Length is 129, not 128"))
    mutations = [
        ("magic", 0, "2s", b"NO", "Wrong magic"),
        ("major", 2, "B", 2, "Unsupported protocol major"),
        ("kind", 3, "B", 255, "Unknown kind in the pose decoder"),
        ("header_flags", 4, "H", 1, "Reserved header flags"),
        ("header_length", 6, "H", 47, "Header length differs from 48"),
        ("entity_zero", 16, "I", 0, "Entity IDs must be nonzero"),
        ("clock_magnitude", 32, "q", 1 << 52, "Clock magnitude must be below 2^52"),
        ("tick_high_bit", 40, "Q", 1 << 63, "Simulation tick high bit must be zero"),
        ("position_nan", 48, "Q", 0x7FF8000000000000, "Nonfinite float64 position"),
        ("position_limit", 48, "d", 100001.0, "Position exceeds the broad 100 km guard"),
        ("attitude_nan", 72, "I", 0x7FC00000, "Nonfinite float32 quaternion"),
        ("attitude_zero", 72, "f", 0.0, "Quaternion norm is below 0.99"),
        ("attitude_norm", 72, "f", 2.0, "Quaternion norm is outside 0.99 to 1.01"),
        ("velocity_inf", 88, "I", 0x7F800000, "Nonfinite float32 velocity"),
        ("velocity_limit", 88, "f", 1001.0, "Velocity component exceeds 1000 m/s"),
        ("angular_inf", 100, "I", 0xFF800000, "Nonfinite float32 angular rate"),
        ("angular_limit", 100, "f", 101.0, "Angular-rate component exceeds 100 rad/s"),
        ("rpm_nan", 120, "I", 0x7FC00000, "Nonfinite float32 RPM"),
        ("rpm_negative", 120, "f", -1.0, "RPM is negative"),
        ("rpm_limit", 120, "f", 250001.0, "RPM exceeds the broad 250000 guard"),
        ("presentation_flags", 126, "H", 1, "Reserved presentation flags"),
    ]
    for name, offset, fmt, value, reason in mutations:
        cases.append(record(name, patched(packet, offset, fmt, value), "reject", reason))

    # Expectations come from the contract, not from a decoder under test.
    sequence_cases = [
        {"previous": 42, "incoming": 43, "expectation": "newer"},
        {"previous": 42, "incoming": 42, "expectation": "duplicate"},
        {"previous": 42, "incoming": 41, "expectation": "old"},
        {"previous": 0xFFFFFFFE, "incoming": 1, "expectation": "newer"},
        {"previous": 1, "incoming": 0x80000001, "expectation": "ambiguous_reject"},
        {"previous": 42, "incoming": 10042, "expectation": "newer"},
        {"previous": 42, "incoming": 10043, "expectation": "fresh_baseline_required"},
    ]
    return {
        "format": "openrc-mp-pose-research-vectors-v1",
        "status": "synthetic proposed-contract fixtures; no Godot codec or network tested",
        "contract": "docs/plans/multiplayer-protocol.md",
        "byte_order": "little-endian",
        "struct_format": FORMAT,
        "application_bytes": POSE.size,
        "header_bytes": 48,
        "body_bytes": 80,
        "scope": [
            "pass means only the documented outer field guards, not session acceptance",
            "room/connection ownership, roster, revision, epoch, freshness and model-specific throws still require validation",
            "input quaternion values precede float32 rounding; use rounded values/tolerances when checking decoded fields",
            "positions and linear velocities refer to fixed body datum O, not a changing live CG",
            "surface values are trailing-edge centidegrees, not normalized controls or hinge rotations",
            "signed sample time and nonnegative tick use decimal strings in JSON metadata",
            "no control-message schema, transport/auth, pause/reset state machine or impairment is exercised",
        ],
        "packets": cases,
        "sequence_cases_same_room_entity_epoch": sequence_cases,
        "context_cases": [
            {"packet": "identity", "context": "connection owns entity 8, packet claims 7",
             "expectation": "reject_sender_binding"},
            {"packet": "identity", "context": "accepted configuration revision is 3, packet has 2",
             "expectation": "reject_revision"},
            {"packet": "identity", "context": "accepted epoch is 2; epoch 3 baseline has not arrived",
             "expectation": "drop_until_baseline"},
            {"packet": "identity", "context": "accepted epoch is 4; packet epoch is 3",
             "expectation": "reject_old_epoch"},
            {"packet": "paused_before_host_start", "context": "ACTIVE ingress at host time 1000000 us",
             "expectation": "reject_sample_older_than_one_second"},
            {"packet": "paused_before_host_start", "context": "validated current PAUSED baseline or final STATUS at host time 1000000 us",
             "expectation": "age_lower_bound_exempt; all other admission checks remain"},
        ],
        "quantization_cases": [
            {"field": "throttle", "input": 0.0, "encoded": 0},
            {"field": "throttle", "input": 0.5, "encoded": 32768},
            {"field": "throttle", "input": 1.0, "encoded": 65535},
            {"field": "surface_degrees", "input": 0.125, "encoded_centidegrees": 13},
            {"field": "surface_degrees", "input": -0.125, "encoded_centidegrees": -13},
        ],
    }


if __name__ == "__main__":
    print(json.dumps(document(), indent=2, allow_nan=False))
