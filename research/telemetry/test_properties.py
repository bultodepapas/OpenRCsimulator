"""Bounded, synthetic property tests; no sockets, hardware or player data.

F09 research motivates sequences and hostile encodings, not a second copy of
the implementation's control flow. The observable contract is the oracle.
"""
from copy import deepcopy
import json
import unittest

from hypothesis import given, settings, strategies as st
from hypothesis.stateful import RuleBasedStateMachine, invariant, rule

from generate_examples import example
from reference import (
    ClientModel, ContractError, IngressModel, MAX_BODY,
    QUEUE_BATCHES, QUEUE_BYTES, encode, validate_body,
)

BOUNDED = settings(max_examples=80, deadline=None, derandomize=True, database=None)


def state(client):
    """Snapshot externally relevant consent/request/queue state."""
    return (client.state, client.epoch, client.session_id, client.active,
            tuple((x.body, x.epoch, x.created, x.due, x.retries) for x in client.queue))


class GeneratedPayloadTests(unittest.TestCase):
    @BOUNDED
    @given(location=st.sampled_from(["root", "context", "build", "event"]),
           suffix=st.text(alphabet="abcdef0123456789", min_size=1, max_size=20))
    def test_unknown_nested_fields_are_rejected_without_retention(self, location, suffix):
        payload = deepcopy(example())
        targets = {"root": payload, "context": payload["context"],
                   "build": payload["build"], "event": payload["events"][0]}
        canary = "SYNTHETIC_PRIVATE_CANARY_" + suffix
        targets[location]["unexpected_" + suffix] = canary
        body = encode(payload)
        with self.assertRaises(ContractError) as error:
            validate_body(body)
        self.assertNotIn(canary, str(error.exception))
        ingress = IngressModel()
        self.assertEqual(ingress.ingest(body, 0), 422)
        self.assertEqual((ingress.batches, ingress.events), ({}, {}))

    @BOUNDED
    @given(key=st.sampled_from(["session_id", "batch_id", "schema_version", "events"]),
           escaped=st.booleans())
    def test_duplicate_decoded_keys_are_rejected(self, key, escaped):
        body = encode(example())
        spelling = ('"\\u%04x%s"' % (ord(key[0]), key[1:])) if escaped else json.dumps(key)
        # Both spellings decode to the same existing key. No raw textual-key shortcut.
        duplicate = body[:-1] + b"," + spelling.encode("ascii") + b":null}"
        with self.assertRaisesRegex(ContractError, "^duplicate_key$"):
            validate_body(duplicate)

    @BOUNDED
    @given(body=st.binary(max_size=600))
    def test_guaranteed_invalid_utf8_fails_safely(self, body):
        # 0xff cannot begin a valid UTF-8 sequence, independent of payload size.
        with self.assertRaisesRegex(ContractError, "^invalid_json$"):
            validate_body(b"\xff" + body)

    @BOUNDED
    @given(sequence=st.integers(min_value=1, max_value=100_000))
    def test_valid_short_start_body_is_accepted(self, sequence):
        payload = deepcopy(example())
        payload["build"]["release_id"] = "v0.0.0"
        payload["context"] = {
            "os_family": "linux", "architecture": "arm64", "cpu_family": "other",
            "logical_threads_bucket": "le4", "ram_gib_bucket": "le4", "gpu_family": "other",
            "renderer": "mobile", "driver": "metal", "resolution_class": "other",
            "resolution_basis": "unknown", "vsync": "on", "fps_cap_bucket": "le30",
            "graphics_profile": "custom", "input_class": "rc",
        }
        payload["events"] = [{"name": "session_started", "seq": sequence}]
        body = encode(payload)
        self.assertLessEqual(len(body), 600)
        self.assertEqual(validate_body(body), payload)

    @BOUNDED
    @given(extra=st.integers(min_value=1, max_value=256), prefix=st.binary(max_size=8))
    def test_size_rejection_precedes_decoder(self, extra, prefix):
        body = prefix + b"\xff" * (MAX_BODY + extra - len(prefix))
        with self.assertRaisesRegex(ContractError, "^body_too_large$"):
            validate_body(body)

    @BOUNDED
    @given(sequence=st.integers(min_value=1, max_value=1_000_000),
           receipt=st.integers(min_value=0, max_value=100_000),
           delay=st.integers(min_value=0, max_value=172_799))
    def test_idempotency_does_not_extend_original_expiry(self, sequence, receipt, delay):
        payload = deepcopy(example())
        payload["events"][0]["seq"] = sequence
        body = encode(payload)
        ingress = IngressModel()
        self.assertEqual(ingress.ingest(body, receipt), 202)
        original = deepcopy((ingress.batches, ingress.events))
        self.assertEqual(ingress.ingest(body, receipt + delay), 202)
        self.assertEqual((ingress.batches, ingress.events), original)
        payload["context"]["input_class"] = "keyboard"
        self.assertEqual(ingress.ingest(encode(payload), receipt + delay), 409)
        self.assertEqual((ingress.batches, ingress.events), original)


class ConsentStateMachine(RuleBasedStateMachine):
    def __init__(self):
        super().__init__()
        self.client = ClientModel()
        self.allowed = False
        self.now = 0
        self.serial = 0
        self.probes = 0
        self.attempts = []
        self.previewed = {}

    def payload(self):
        self.probes += 1
        self.serial += 1
        payload = deepcopy(example())
        payload["batch_id"] = f"{self.serial:032x}"
        payload["events"][0]["seq"] = self.serial
        return payload

    @rule(current_notice=st.booleans())
    def grant(self, current_notice):
        self.allowed = current_notice
        result = self.client.enable() if current_notice else self.client.enable("old")
        assert result == current_notice

    @rule()
    def revoke(self):
        self.client.disable()
        self.allowed = False

    @rule()
    def collect(self):
        before = self.probes
        collected = self.client.collect(self.payload, self.now)
        assert self.probes - before == int(self.allowed)
        assert collected == self.allowed
        if collected:
            body = self.client.queue[-1].body
            self.previewed[validate_body(body)["batch_id"]] = body

    @rule()
    def revoke_inside_probe(self):
        def probe():
            result = self.payload()
            self.client.disable()
            self.allowed = False
            return result
        assert not self.client.collect(probe, self.now)

    @rule(seconds=st.sampled_from([0, 1, 5, 59, 60, 599, 600, 3600]))
    def advance(self, seconds):
        self.now += seconds
        self.client.expire(self.now)

    @rule()
    def begin(self):
        previous = self.client.active
        result = self.client.begin_send(self.now)
        if not self.allowed or previous is not None:
            assert result is None
        if result:
            token, body = result
            assert body == self.previewed[validate_body(body)["batch_id"]]
            assert self.now - self.client.active[1].created < 600
            self.attempts.append(token)

    @rule(status=st.sampled_from([0, 202, 400, 401, 403, 408, 409, 410, 413, 415, 422, 429, 500, 503]),
           retry_after=st.sampled_from([0, 1, 120, 599, 600, 900]))
    def complete_current(self, status, retry_after):
        if self.client.active is None:
            return
        token = self.client.active[0]
        assert self.client.complete(token, status, self.now, retry_after=retry_after)
        if status in (401, 403, 410):
            self.allowed = False

    @rule(index=st.integers(min_value=0, max_value=100))
    def replay_old_completion(self, index):
        if not self.attempts:
            return
        token = self.attempts[index % len(self.attempts)]
        if self.client.active is not None and self.client.active[0] == token:
            return
        before = state(self.client)
        assert not self.client.complete(token, 202, self.now)
        assert state(self.client) == before

    @invariant()
    def consent_and_memory_contract(self):
        assert self.client.enabled == self.allowed
        assert len(self.client.queue) <= QUEUE_BATCHES
        assert sum(len(item.body) for item in self.client.queue) <= QUEUE_BYTES
        if not self.allowed:
            assert not self.client.queue
            assert self.client.active is None
            assert self.client.session_id is None
        if self.client.active is not None:
            assert any(item is self.client.active[1] for item in self.client.queue)


TestConsentStateMachine = ConsentStateMachine.TestCase
TestConsentStateMachine.settings = settings(
    max_examples=120, stateful_step_count=50, deadline=None,
    derandomize=True, database=None,
)


if __name__ == "__main__":
    unittest.main()
