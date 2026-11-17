#!/usr/bin/env python3
"""Size candidate MP control shapes, not a finalized schema or network codec.

Standard library only; no network, engine, dependency install or file write.
Run from any directory and redirect stdout to inspect/regenerate the JSON.
Fixtures measure JSON escaping plus the four-byte application prefix, without
Godot/ENet/UDP/IP/DTLS overhead. All names and hashes below are synthetic.
"""

from __future__ import annotations

import base64
import json


PREFIX = b"OR\x01\x02"
LIMIT = 1024
U32 = 0xFFFFFFFF
ROOM = "ffffffffffffffff"
CONNECTION = "c" * 32  # Public per-connection freshness context, not an invite secret.
ATTEMPT = "d" * 32     # Client auth-attempt challenge, also not authentication.
# This tests the encoded length of a 128-byte record, not pose validity.
POSE_B64 = base64.b64encode(bytes(range(128))).decode("ascii")


def serialize(value: dict, *, ascii_only: bool = False) -> bytes:
    return PREFIX + json.dumps(
        value, ensure_ascii=ascii_only, allow_nan=False, separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def container_depth(value) -> int:
    """Count only dict/list containers, with the root object at depth one."""
    if isinstance(value, dict):
        return 1 + max((container_depth(v) for v in value.values()), default=0)
    if isinstance(value, list):
        return 1 + max((container_depth(v) for v in value), default=0)
    return 0


def room_message(count: int, name: str) -> dict:
    # One approved aircraft; no arbitrary resource paths or downloaded catalog.
    return {
        "type": "ROOM", "control_id": U32, "room": ROOM, "connection": CONNECTION,
        "config_rev": U32,
        "build": "b" * 40, "field_sha256": "f" * 64,
        "aircraft_sha256": "a" * 64, "environment_sha256": "e" * 64,
        "roster": [{"entity": U32 - i, "name": name} for i in range(count)],
    }


def baseline() -> dict:
    return {
        "type": "BASELINE", "control_id": U32, "room": ROOM, "connection": CONNECTION,
        "config_rev": U32, "entity": U32, "epoch": U32,
        "status": "DEGRADED", "status_rev": U32, "pose_b64": POSE_B64,
    }


def record(name: str, value: dict, *, ascii_only: bool = False,
           json_override: str | None = None) -> dict:
    framed = (PREFIX + json_override.encode("utf-8") if json_override is not None
              else serialize(value, ascii_only=ascii_only))
    result = {
        "id": name, "ensure_ascii": ascii_only,
        "json_utf8": framed[len(PREFIX):].decode("utf-8"),
        "json_bytes": len(framed) - len(PREFIX), "framed_bytes": len(framed),
        "remaining_bytes": LIMIT - len(framed),
        "fits_size_limit_only": len(framed) <= LIMIT,
        "container_depth": container_depth(value),
    }
    if json_override is not None:
        result["serialization_override"] = "every ASCII name character uses a six-byte Unicode escape"
    return result


def document() -> dict:
    if len(POSE_B64) != 172:
        raise RuntimeError("128 bytes must encode to 172 padded Base64 characters")
    names = {"ascii": "A" * 32, "quotes": '"' * 32,
             "accented": "é" * 16, "emoji": "✈️" * 5 + "AB"}
    if any(len(name.encode("utf-8")) != 32 for name in names.values()):
        raise RuntimeError("All name fixtures must use exactly 32 decoded UTF-8 bytes")
    cases = [record(f"room_4_{key}", room_message(4, name))
             for key, name in names.items()]
    ascii_room = room_message(4, names["ascii"])
    escaped_name = '"' + r"\u0041" * 32 + '"'
    alternate = serialize(ascii_room)[len(PREFIX):].decode("utf-8").replace(
        json.dumps(names["ascii"]), escaped_name)
    cases.append(record("room_4_ascii_all_name_chars_escaped", ascii_room,
                        json_override=alternate))
    cases += [record("room_4_accented_ascii_escape", room_message(4, names["accented"]),
                     ascii_only=True),
              record("room_8_quotes", room_message(8, names["quotes"])),
              record("room_8_ascii", room_message(8, names["ascii"])),
              record("baseline_single", baseline()),
              record("paused_status_single", dict(baseline(), type="STATUS", status="PAUSED")),
              record("heartbeat_decimal_strings", {
                  "type": "HEARTBEAT", "room": ROOM, "connection": CONNECTION,
                  "entity": U32, "epoch": U32,
                  "status": "PAUSED", "status_rev": U32, "sequence": U32,
                  "sample_sequence": U32, "sample_time_us": str(-(2**52 - 1)),
                  "sim_tick": str(2**63 - 1),
              }),
              record("session_heartbeat_before_baseline", {
                  "type": "SESSION_HEARTBEAT", "room": ROOM,
                  "connection": CONNECTION, "sequence": U32,
              }),
              record("auth_hello_candidate", {
                  "type": "HELLO", "attempt": ATTEMPT, "build": "b" * 40,
                  "compatibility_sha256": "a" * 64, "name": names["quotes"],
                  "capability": "f" * 32,
              }),
              record("auth_accept_candidate", {
                  "type": "ACCEPT", "attempt": ATTEMPT, "connection": CONNECTION,
                  "room": ROOM, "entity": U32, "config_rev": U32,
                  "compatibility_sha256": "a" * 64,
              }),
              record("auth_ack_candidate", {
                  "type": "AUTH_ACK", "attempt": ATTEMPT, "connection": CONNECTION,
                  "room": ROOM,
              })]
    bundled = room_message(4, names["quotes"])
    bundled["baselines"] = [dict(baseline(), entity=U32 - i) for i in range(4)]
    cases.append(record("room_4_with_4_baselines_antipattern", bundled))
    # Arbitrary unknown fields are not permitted: these two shapes only expose
    # exact byte boundaries and must NOT be accepted as real control messages.
    empty_bytes = len(serialize({"padding": ""}))
    cases += [record(f"size_only_{size}", {"padding": "X" * (size - empty_bytes)})
              for size in (LIMIT, LIMIT + 1)]
    by_id = {case["id"]: case for case in cases}
    return {
        "format": "openrc-mp-control-size-research-v1",
        "status": "candidate size fixtures; no final control schema, parser or transport",
        "prefix_hex": PREFIX.hex(), "total_application_limit_bytes": LIMIT,
        "pose_raw_bytes": 128, "pose_base64_chars": len(POSE_B64),
        "scope": [
            "fits_size_limit_only does not imply schema, identity, ordering or admission validity",
            "Base64 bytes are deliberately not a valid pose; this is only a length fixture",
            "message keys and digest coverage require the MP-01a schema/compatibility review",
            "fresh connection/attempt nonces distinguish old generations; they do not authenticate cleartext peers",
            "8-player and bundled-baseline shapes are comparisons, not proposed v1 messages",
            "final Godot serialization may differ; measure its bytes independently",
            "ensure_ascii is not a worst-case bound; legal escaped ASCII can be larger still",
            "no real names, capabilities, account or network data are present",
        ],
        "cases": cases,
        "separate_message_example": {
            "room_4_quotes_bytes": by_id["room_4_quotes"]["framed_bytes"],
            "one_baseline_bytes": by_id["baseline_single"]["framed_bytes"],
            "room_plus_four_baselines_total_bytes": (
                by_id["room_4_quotes"]["framed_bytes"]
                + 4 * by_id["baseline_single"]["framed_bytes"]),
            "order": "apply/ACK ROOM first; then bounded individual BASELINE controls",
            "control_ids_for_sized_sequence": list(range(U32 - 4, U32 + 1)),
            "note": "sum is not one packet; substitute these distinct 10-digit IDs for the per-shape U32 placeholder; sequence exhaustion requires a fresh generation; no READY, ACK, auth, transport or retransmit cost included",
        },
    }


if __name__ == "__main__":
    print(json.dumps(document(), ensure_ascii=False, indent=2, allow_nan=False))
