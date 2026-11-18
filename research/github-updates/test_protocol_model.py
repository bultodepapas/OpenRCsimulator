"""DT-UPD-00 adversarial protocol checks. Synthetic fixtures, no network/install."""
import base64
import copy
import json
from pathlib import Path
import unittest

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

import protocol_model as model

NOW = 1794873600


def encode(data):
    return json.dumps(data, sort_keys=True, separators=(",", ":")).encode("utf-8")


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.payload = json.loads(Path(__file__).with_name("channel-payload.example.json").read_text())
        self.payload["issued_at"] = NOW - 30
        self.payload["expires_at"] = NOW + 86400
        self.private = Ed25519PrivateKey.generate()  # Memory-only fixture key, never a shipping key.
        self.trust = {"fixture": self.private.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)}

    def envelope(self, payload=None, raw=None, domain=model.DOMAIN):
        raw = encode(self.payload if payload is None else payload) if raw is None else raw
        return encode({"format": "openrc-update-envelope-v1", "key_id": "fixture",
                       "payload": base64.b64encode(raw).decode("ascii"),
                       "signature": base64.b64encode(
                           self.private.sign(domain + b"fixture\x00" + raw)).decode("ascii")})

    def verify(self, wire=None, **options):
        arguments = dict(trusted_keys=self.trust, now=NOW, installed_tag="v0.0.0",
                         platform="windows-x86_64")
        arguments.update(options)
        return model.verify_envelope(self.envelope() if wire is None else wire, **arguments)

    def reject(self, payload):
        with self.assertRaises(model.ProtocolError):
            self.verify(self.envelope(payload))

    def test_rfc8032_independent_empty_message_vector(self):
        # RFC 8032 section 7.1 TEST 1: public verification data, no copied secret.
        public = bytes.fromhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        signature = bytes.fromhex(
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555"
            "fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
        key = Ed25519PublicKey.from_public_bytes(public)
        key.verify(signature, b"")
        with self.assertRaises(InvalidSignature):
            key.verify(signature, b"changed")

    def test_signed_offer_for_each_explicit_platform(self):
        for platform in sorted(model.PLATFORMS):
            with self.subTest(platform=platform):
                verified = self.verify(platform=platform)
                self.assertTrue(verified.newer_than_installed)
                self.assertTrue(verified.archive["name"].endswith(platform + ".zip"))
                self.assertEqual(verified.sequence, 1)

    def test_payload_tampering_without_resigning_is_rejected(self):
        envelope = json.loads(self.envelope())
        changed = copy.deepcopy(self.payload)
        changed["sequence"] += 1
        envelope["payload"] = base64.b64encode(encode(changed)).decode("ascii")
        with self.assertRaisesRegex(model.ProtocolError, "invalid signature"):
            self.verify(encode(envelope))

    def test_wrong_domain_rejected_before_payload_parsing(self):
        with self.assertRaisesRegex(model.ProtocolError, "invalid signature"):
            self.verify(self.envelope(raw=b"not JSON", domain=b"Another product\x00"))

    def test_unknown_or_wrong_public_key_rejected(self):
        with self.assertRaises(model.ProtocolError):
            self.verify(trusted_keys={})
        other = Ed25519PrivateKey.generate().public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        with self.assertRaisesRegex(model.ProtocolError, "invalid signature"):
            self.verify(trusted_keys={"fixture": other})

    def test_same_public_key_alias_cannot_replace_signed_key_id(self):
        envelope = json.loads(self.envelope())
        envelope["key_id"] = "second-alias"
        aliases = dict(self.trust, **{"second-alias": self.trust["fixture"]})
        with self.assertRaisesRegex(model.ProtocolError, "invalid signature"):
            self.verify(encode(envelope), trusted_keys=aliases)

    def test_signature_length_and_base64_are_closed(self):
        for bad in ("AAAA", "*" * 88, base64.b64encode(b"x" * 65).decode(), " "):
            with self.subTest(value=bad):
                envelope = json.loads(self.envelope())
                envelope["signature"] = bad
                with self.assertRaises(model.ProtocolError):
                    self.verify(encode(envelope))

    def test_duplicate_envelope_keys_rejected(self):
        wire = self.envelope()[:-1] + b',"format":"openrc-update-envelope-v1"}'
        with self.assertRaises(model.ProtocolError):
            self.verify(wire)

    def test_signed_duplicate_payload_keys_rejected(self):
        raw = encode(self.payload)[:-1] + b',"sequence":1}'
        with self.assertRaises(model.ProtocolError):
            self.verify(self.envelope(raw=raw))

    def test_closed_fields_and_formats(self):
        for key, value in (("unexpected", "ignored?"), ("format", "production-v9"),
                           ("repository", "someone/else"), ("channel", "preview"),
                           ("source_commit", "not-a-commit")):
            with self.subTest(field=key):
                payload = copy.deepcopy(self.payload)
                payload[key] = value
                self.reject(payload)

    def test_expiry_future_clock_and_lifetime(self):
        for issued, expires in ((NOW - 10, NOW), (NOW + 301, NOW + 900),
                                (NOW - 1, NOW + model.MAX_TTL), (NOW, NOW - 1)):
            with self.subTest(issued=issued, expires=expires):
                payload = copy.deepcopy(self.payload)
                payload["issued_at"], payload["expires_at"] = issued, expires
                self.reject(payload)

    def test_bool_float_negative_and_huge_integer_rejected(self):
        for field in ("sequence", "issued_at", "expires_at", "minimum_updater"):
            for invalid in (True, 1.5, -1, 2**100):
                with self.subTest(field=field, invalid=invalid):
                    payload = copy.deepcopy(self.payload)
                    payload[field] = invalid
                    self.reject(payload)

    def test_newer_updater_requirement_rejected(self):
        payload = copy.deepcopy(self.payload)
        payload["minimum_updater"] = 2
        self.reject(payload)

    def test_canonical_stable_tags_only(self):
        for tag in ("v00.0.1", "v0.0.01", "v0.0.1-rc.1", "v0.0.1+build", "V0.0.1", "v0.0.1/../../"):
            with self.subTest(tag=tag):
                payload = copy.deepcopy(self.payload)
                payload["tag"] = tag
                self.reject(payload)

    def test_exact_url_repo_tag_filename_and_no_query(self):
        for bad in ("http://github.com/" + model.REPOSITORY,
                    "https://github.com.evil.invalid/" + model.REPOSITORY,
                    self.payload["targets"]["windows-x86_64"]["url"] + "?download=1",
                    self.payload["targets"]["windows-x86_64"]["url"].replace("/v0.0.1/", "/latest/"),
                    self.payload["targets"]["windows-x86_64"]["url"] + "/../other.zip"):
            with self.subTest(url=bad):
                payload = copy.deepcopy(self.payload)
                payload["targets"]["windows-x86_64"]["url"] = bad
                self.reject(payload)

    def test_asset_sizes_hashes_and_member_bounds(self):
        for field, invalid in (("bytes", 2**31), ("bytes", 0), ("bytes", True),
                               ("bytes", 1.5), ("sha256", "A" * 64),
                               ("sha256", "0" * 63), ("expanded_bytes", model.MAX_EXPANDED + 1),
                               ("file_count", model.MAX_MEMBERS + 1), ("file_count", False)):
            with self.subTest(field=field, invalid=invalid):
                payload = copy.deepcopy(self.payload)
                payload["targets"]["windows-x86_64"][field] = invalid
                self.reject(payload)

    def test_manifest_and_other_platform_are_also_validated(self):
        payload = copy.deepcopy(self.payload)
        payload["release_manifest"]["bytes"] = 1024 * 1024 + 1
        self.reject(payload)
        payload = copy.deepcopy(self.payload)
        payload["targets"]["macos-universal"]["sha256"] = "invalid"
        self.reject(payload)

    def test_unknown_or_missing_platform_rejected(self):
        payload = copy.deepcopy(self.payload)
        payload["targets"]["linux-arm64"] = payload["targets"]["linux-x86_64"]
        self.reject(payload)
        payload = copy.deepcopy(self.payload)
        del payload["targets"]["windows-x86_64"]
        self.reject(payload)
        with self.assertRaises(model.ProtocolError):
            self.verify(platform="linux-arm64")

    def test_lower_sequence_is_rejected(self):
        with self.assertRaisesRegex(model.ProtocolError, "metadata rollback"):
            self.verify(last_sequence=2, last_payload_sha256="a" * 64)

    def test_same_sequence_identical_payload_is_allowed(self):
        prior = self.verify()
        again = self.verify(last_sequence=prior.sequence, last_payload_sha256=prior.payload_sha256)
        self.assertEqual(prior.payload_sha256, again.payload_sha256)

    def test_same_sequence_different_payload_is_rejected(self):
        prior = self.verify()
        changed = copy.deepcopy(self.payload)
        changed["expires_at"] += 1
        with self.assertRaisesRegex(model.ProtocolError, "equivocation"):
            self.verify(self.envelope(changed), last_sequence=prior.sequence,
                        last_payload_sha256=prior.payload_sha256)

    def test_current_or_older_game_is_not_an_update(self):
        self.assertFalse(self.verify(installed_tag="v0.0.1").newer_than_installed)
        self.assertFalse(self.verify(installed_tag="v0.0.2").newer_than_installed)
        self.payload["sequence"] = 3
        self.assertFalse(self.verify(installed_tag="v0.0.2", last_sequence=2,
                                     last_payload_sha256="a" * 64).newer_than_installed)

    def test_size_utf8_nan_deep_and_array_json_rejected(self):
        with self.assertRaises(model.ProtocolError):
            self.verify(b"x" * (model.MAX_ENVELOPE + 1))
        for raw in (b"\xff", b"[]", b'{"sequence":NaN}',
                    b'{"nested":' + b"[" * 1500 + b"0" + b"]" * 1500 + b"}"):
            with self.subTest(raw_size=len(raw)):
                with self.assertRaises(model.ProtocolError):
                    self.verify(self.envelope(raw=raw))
        with self.assertRaises(model.ProtocolError):
            self.verify(self.envelope(raw=b" " * (model.MAX_PAYLOAD + 1)))


class RangeTests(unittest.TestCase):
    def test_ignored_range_restarts_and_never_appends(self):
        self.assertEqual(model.range_action(200, offset=4, total=10,
                                            content_length=10, received_bytes=10), "restart")
        self.assertEqual(model.range_action(200, offset=0, total=10), "start")

    def test_exact_206_and_short_valid_segment(self):
        self.assertEqual(model.range_action(206, offset=4, total=10,
                         content_range="bytes 4-9/10", content_length=6, received_bytes=6), "append")
        self.assertEqual(model.range_action(206, offset=4, total=10,
                         content_range="bytes 4-6/10", content_length=3, received_bytes=3), "append")

    def test_wrong_206_range_and_body_length_rejected(self):
        for value in (None, "bytes 0-9/10", "bytes 4-9/11", "bytes 4-10/10",
                      "bytes 4-9/*", "bytes 5-4/10", "items 4-9/10", "bytes " + "9" * 150):
            with self.subTest(value=value):
                with self.assertRaises(model.ProtocolError):
                    model.range_action(206, offset=4, total=10, content_range=value)
        for lengths in (dict(content_length=5), dict(received_bytes=5), dict(received_bytes=7)):
            with self.subTest(lengths=lengths):
                with self.assertRaises(model.ProtocolError):
                    model.range_action(206, offset=4, total=10,
                                       content_range="bytes 4-9/10", **lengths)

    def test_bad_full_body_and_range_on_200_rejected(self):
        for options in (dict(content_length=9), dict(received_bytes=9),
                        dict(content_range="bytes 0-9/10")):
            with self.subTest(options=options):
                with self.assertRaises(model.ProtocolError):
                    model.range_action(200, offset=4, total=10, **options)

    def test_416_requires_local_verification_or_restart(self):
        self.assertEqual(model.range_action(416, offset=10, total=10), "verify-existing")
        self.assertEqual(model.range_action(416, offset=4, total=10), "restart")

    def test_retryable_errors_do_not_append(self):
        for code in (408, 429, 500, 502, 503, 504):
            with self.subTest(code=code):
                self.assertEqual(model.range_action(code, offset=4, total=10), "retry-with-backoff")
        for code in (302, 403, 404):
            with self.subTest(code=code):
                with self.assertRaises(model.ProtocolError):
                    model.range_action(code, offset=4, total=10)

    def test_invalid_offsets_and_boolean_lengths_rejected(self):
        for offset, total in ((-1, 10), (11, 10), (0, 0), (True, 10), (0, 2**31)):
            with self.subTest(offset=offset, total=total):
                with self.assertRaises(model.ProtocolError):
                    model.range_action(200, offset=offset, total=total)
        with self.assertRaises(model.ProtocolError):
            model.range_action(206, offset=4, total=10,
                               content_range="bytes 4-9/10", content_length=True)


if __name__ == "__main__":
    unittest.main()
