"""DT-UPD-00 offline protocol sketch. No network, extraction, process or install actions.

This is a stable-channel research subset, not a production updater.
See README.md for deliberately unimplemented trust, persistence and OS boundaries.
"""
from __future__ import annotations

import base64
import binascii
from dataclasses import dataclass
import hashlib
import json
import re
from typing import Mapping

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

REPOSITORY = "bultodepapas/OpenRCsimulator"
ORIGIN = "https://github.com/" + REPOSITORY + "/releases/download/"
DOMAIN = b"OpenRC Simulator update v1\x00"
MAX_ENVELOPE = 64 * 1024
MAX_PAYLOAD = 40 * 1024
MAX_ASSET = 2**31 - 1  # GitHub documents each release asset as below 2 GiB.
MAX_EXPANDED = 8 * 1024**3  # Proposed local policy, not a measured package size.
MAX_MEMBERS = 100_000
MAX_TTL = 90 * 86400
CLOCK_SKEW = 300
PLATFORMS = frozenset(("windows-x86_64", "linux-x86_64", "macos-universal"))
HEX = re.compile(r"[0-9a-f]{64}")
TAG = re.compile(r"v(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})")
KEY_ID = re.compile(r"[a-z0-9][a-z0-9-]{0,63}")
RANGE = re.compile(r"bytes ([0-9]+)-([0-9]+)/([0-9]+)")


class ProtocolError(ValueError):
    """Reject untrusted or unsupported input without changing any state."""


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ProtocolError(message)


def _unique(pairs: list) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def _not_number(value: str):
    raise ProtocolError("floating or non-finite numbers are not supported")


def _json(data: bytes, maximum: int) -> dict:
    require(type(data) is bytes and 0 < len(data) <= maximum, "JSON size/type")
    try:
        result = json.loads(data.decode("utf-8"), object_pairs_hook=_unique,
                            parse_constant=_not_number, parse_float=_not_number)
    except (UnicodeError, ValueError, RecursionError) as error:
        raise ProtocolError("invalid bounded JSON") from error
    require(type(result) is dict, "JSON object required")
    return result


def _keys(value: object, expected: set[str], label: str) -> dict:
    require(type(value) is dict and set(value) == expected, label + " fields")
    return value


def _integer(value: object, low: int, high: int, label: str) -> int:
    require(type(value) is int and low <= value <= high, label + " integer/range")
    return value


def _hex(value: object, label: str) -> str:
    require(type(value) is str and HEX.fullmatch(value) is not None, label + " digest")
    return value


def _base64(value: object, limit: int, label: str) -> bytes:
    require(type(value) is str and len(value) <= 4 * ((limit + 2) // 3), label + " encoding size")
    try:
        decoded = base64.b64decode(value.encode("ascii"), validate=True)
    except (UnicodeError, ValueError, binascii.Error) as error:
        raise ProtocolError(label + " base64") from error
    require(len(decoded) <= limit and base64.b64encode(decoded).decode("ascii") == value,
            label + " canonical base64")
    return decoded


def _version(tag: object) -> tuple[int, int, int]:
    require(type(tag) is str, "stable tag type")
    match = TAG.fullmatch(tag)
    require(match is not None, "only canonical stable tags supported by this draft")
    return tuple(int(part) for part in match.groups())


def _asset(asset: object, tag: str, name: str, expanded: bool) -> dict:
    fields = {"name", "url", "bytes", "sha256"}
    if expanded:
        fields |= {"expanded_bytes", "file_count"}
    asset = _keys(asset, fields, "asset")
    require(asset["name"] == name and asset["url"] == ORIGIN + tag + "/" + name,
            "asset must be exact repository/tag/name URL")
    _integer(asset["bytes"], 1, MAX_ASSET, "asset bytes")
    _hex(asset["sha256"], "asset")
    if expanded:
        _integer(asset["expanded_bytes"], 1, MAX_EXPANDED, "expanded bytes")
        _integer(asset["file_count"], 1, MAX_MEMBERS, "file count")
    else:
        require(asset["bytes"] <= 1024 * 1024, "release manifest size")
    return asset


@dataclass(frozen=True)
class VerifiedOffer:
    """Validated metadata only; neither installation permission nor persisted state."""
    tag: str
    sequence: int
    payload_sha256: str
    platform: str
    newer_than_installed: bool
    archive: dict
    release_manifest: dict


def verify_envelope(
    wire: bytes,
    *,
    trusted_keys: Mapping[str, bytes],
    now: int,
    installed_tag: str,
    platform: str,
    last_sequence: int = 0,
    last_payload_sha256: str = "",
    client_protocol: int = 1,
) -> VerifiedOffer:
    """Verify a signed stable offer. Caller owns trusted key provenance and durable state.

    No input object is modified. A returned object is not a persisted high-water mark.
    Production must add clock-anomaly policy, preview/withdrawal, trust rotation,
    release provenance, extracted inventory, concurrency and native lifecycle.
    """
    _integer(now, 1, 2**63 - 1, "current time")
    _integer(last_sequence, 0, 2**63 - 1, "last sequence")
    _integer(client_protocol, 1, 2**31 - 1, "client protocol")
    require(platform in PLATFORMS, "unsupported platform")
    installed = _version(installed_tag)
    if last_sequence:
        _hex(last_payload_sha256, "previous payload")
    else:
        require(last_payload_sha256 == "", "unexpected previous payload")
    envelope = _keys(_json(wire, MAX_ENVELOPE),
                     {"format", "key_id", "payload", "signature"}, "envelope")
    require(envelope["format"] == "openrc-update-envelope-v1", "envelope format")
    key_id = envelope["key_id"]
    require(type(key_id) is str and KEY_ID.fullmatch(key_id) is not None, "key ID")
    require(key_id in trusted_keys, "unknown signing key")
    public_bytes = trusted_keys[key_id]
    require(type(public_bytes) is bytes and len(public_bytes) == 32, "trusted key bytes")
    payload_bytes = _base64(envelope["payload"], MAX_PAYLOAD, "payload")
    signature = _base64(envelope["signature"], 64, "signature")
    require(len(signature) == 64, "signature length")
    try:
        message = DOMAIN + key_id.encode("ascii") + b"\x00" + payload_bytes
        Ed25519PublicKey.from_public_bytes(public_bytes).verify(signature, message)
    except (InvalidSignature, ValueError) as error:
        raise ProtocolError("invalid signature") from error

    # Only interpret payload fields AFTER signature verification.
    payload = _keys(_json(payload_bytes, MAX_PAYLOAD),
                    {"format", "repository", "channel", "sequence", "issued_at",
                     "expires_at", "minimum_updater", "tag", "source_commit",
                     "release_manifest", "targets"}, "payload")
    require(payload["format"] == "openrc-update-payload-draft-v1", "payload format")
    require(payload["repository"] == REPOSITORY and payload["channel"] == "stable",
            "repository/channel")
    sequence = _integer(payload["sequence"], 1, 2**63 - 1, "sequence")
    issued = _integer(payload["issued_at"], 1, 2**63 - 1, "issued time")
    expires = _integer(payload["expires_at"], 1, 2**63 - 1, "expiry time")
    require(issued <= now + CLOCK_SKEW and now < expires, "future or expired metadata")
    require(0 < expires - issued <= MAX_TTL, "metadata lifetime")
    minimum = _integer(payload["minimum_updater"], 1, 2**31 - 1, "minimum updater")
    require(minimum <= client_protocol, "updater upgrade required")
    target_version = _version(payload["tag"])
    require(type(payload["source_commit"]) is str
            and re.fullmatch(r"[0-9a-f]{40}", payload["source_commit"]) is not None,
            "source commit")
    release_manifest = _asset(payload["release_manifest"], payload["tag"],
                              "release-manifest.json", False)
    targets = payload["targets"]
    require(type(targets) is dict and targets and set(targets) <= PLATFORMS, "target inventory")
    require(platform in targets, "platform not offered")
    for target_platform, target in targets.items():
        _asset(target, payload["tag"],
               "openrc-simulator-" + payload["tag"] + "-" + target_platform + ".zip", True)

    digest = hashlib.sha256(payload_bytes).hexdigest()
    require(sequence >= last_sequence, "metadata rollback")
    if sequence == last_sequence:
        require(digest == last_payload_sha256, "same-sequence equivocation")
    return VerifiedOffer(payload["tag"], sequence, digest, platform,
                         target_version > installed, dict(targets[platform]),
                         dict(release_manifest))


def range_action(
    status: int, *, offset: int, total: int,
    content_range: str | None = None, content_length: int | None = None,
    received_bytes: int | None = None,
) -> str:
    """Pure response decision, not a downloader. Final signed hash remains mandatory.

    Tests supply a completed response body length when available. Real transport
    must validate headers BEFORE writing, cap actual streamed bytes and enforce
    deadlines before calling completion checks.
    """
    _integer(offset, 0, MAX_ASSET, "offset")
    _integer(total, 1, MAX_ASSET, "total")
    require(offset <= total, "partial exceeds target")
    if content_length is not None:
        _integer(content_length, 0, total, "content length")
    if received_bytes is not None:
        _integer(received_bytes, 0, total, "received bytes")
    if status == 200:
        require(content_range is None, "unexpected Content-Range on 200")
        require(content_length in (None, total), "full response length")
        require(received_bytes in (None, total), "incomplete full body")
        return "restart" if offset else "start"
    if status == 206:
        require(type(content_range) is str and len(content_range) <= 100, "missing/large range")
        match = RANGE.fullmatch(content_range)
        require(match is not None, "invalid range")
        start, end, reported_total = (int(part) for part in match.groups())
        require(start == offset and start <= end < total and reported_total == total,
                "range does not match requested target")
        count = end - start + 1
        require(content_length in (None, count) and received_bytes in (None, count),
                "partial body length")
        return "append" if offset else "start"
    if status == 416:
        return "verify-existing" if offset == total else "restart"
    if status in (408, 429, 500, 502, 503, 504):
        return "retry-with-backoff"
    raise ProtocolError("unsupported/error response; no bytes may be appended")
