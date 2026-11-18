"""Adversarial contract and independently calculated examples; no network."""
from copy import deepcopy
import json
import math
from pathlib import Path
import unittest

from generate_examples import cohort, example, outputs
from reference import (
    BATCH_VALIDATOR, REPORT_VALIDATOR, ClientModel, ContractError, FrameWindow,
    IngressModel, MAX_BODY, QUEUE_BYTES, QUEUE_TTL, RAW_TTL,
    aggregate_daily_gpu, encode, hardware_family, render_report,
    validate_body, validate_report, vehicle_id,
)

ROOT = Path(__file__).resolve().parent


def daily_report(bodies, release_id):
    return aggregate_daily_gpu(
        [("2026-11-17", body) for body in bodies],
        "2026-11-17", release_id, as_of_utc="2026-11-18T01:00:00Z",
    )


class PayloadTests(unittest.TestCase):
    def setUp(self):
        self.payload = example()

    def test_canonical_fixture_accepted(self):
        self.assertEqual(validate_body(encode(self.payload)), self.payload)

    def test_generated_schemas_match_source(self):
        from generate_contracts import schemas
        for name, schema in schemas().items():
            self.assertEqual(json.loads((ROOT / "contracts" / name).read_text(encoding="utf-8")), schema)

    def test_examples_are_reproducible(self):
        for name, content in outputs().items():
            self.assertEqual((ROOT / "examples" / name).read_text(encoding="utf-8"), content)

    def test_every_object_is_closed(self):
        for path in [(), ("build",), ("context",), ("events", 0)]:
            candidate = deepcopy(self.payload)
            target = candidate
            for key in path:
                target = target[key]
            target["username"] = "DO-NOT-LEAK"
            with self.subTest(path=path), self.assertRaises(ContractError):
                validate_body(encode(candidate))

    def test_custom_aircraft_and_host_strings_rejected(self):
        for field, value in [("vehicle_id", "/home/EXAMPLE/private-plane"), ("vehicle_id", "@maintainer")]:
            candidate = deepcopy(self.payload)
            candidate["events"][0][field] = value
            with self.subTest(value=value), self.assertRaises(ContractError):
                validate_body(encode(candidate))
        self.payload["context"]["gpu_family"] = "Jane's GeForce"
        with self.assertRaises(ContractError):
            validate_body(encode(self.payload))

    def test_custom_content_projection(self):
        self.assertEqual(vehicle_id("f4u-corsair-250", custom=True), "custom")
        self.assertEqual(vehicle_id("secret-aircraft-name"), "unknown")

    def test_hardware_classification_never_echoes_source(self):
        self.assertEqual(hardware_family("NVIDIA GeForce RTX 4090 serial SECRET", "gpu"), "nvidia_rtx")
        self.assertEqual(hardware_family("/Users/private-machine", "cpu"), "other")
        self.assertEqual(hardware_family("", "gpu"), "unknown")

    def test_trailing_newline_identifiers_rejected(self):
        for path in [("session_id",), ("batch_id",), ("build", "release_id")]:
            candidate = deepcopy(self.payload)
            target = candidate
            for key in path[:-1]:
                target = target[key]
            target[path[-1]] += "\n"
            with self.subTest(path=path), self.assertRaises(ContractError):
                validate_body(encode(candidate))
        report = daily_report(cohort(20), "v0.2.7")
        report["period"] += "\n"
        with self.assertRaises(ContractError):
            render_report(report)

    def test_hardware_marketing_tokens_and_unrecognized_models(self):
        self.assertEqual(hardware_family("Intel(R) Xeon(R) CPU", "cpu"), "other")
        self.assertEqual(hardware_family("Intel(R) Core(TM) i7-13700", "cpu"), "intel_core")
        self.assertEqual(hardware_family("Intel(R) Arc(TM) Graphics", "gpu"), "intel_arc")

    def test_ambiguous_family_does_not_choose_first_match(self):
        cases = [
            ("Intel Core / AMD Ryzen", "cpu"),
            ("Apple Intel Core", "cpu"),
            ("Intel UHD Graphics / NVIDIA GeForce RTX 3060", "gpu"),
            ("NVIDIA GeForce GTX RTX", "gpu"),
            ("llvmpipe / AMD Radeon", "gpu"),
        ]
        for raw, kind in cases:
            with self.subTest(raw=raw, kind=kind):
                self.assertEqual(hardware_family(raw, kind), "other")

    def test_duplicate_json_key_rejected(self):
        with self.assertRaisesRegex(ContractError, "^duplicate_key$"):
            validate_body(b'{"session_id":"a","session_id":"b"}')

    def test_nonfinite_literals_rejected(self):
        for literal in [b"NaN", b"Infinity", b"-Infinity", b"1e999"]:
            body = encode(self.payload).replace(b'"gpu_ms":null', b'"gpu_ms":' + literal)
            with self.subTest(literal=literal), self.assertRaises(ContractError):
                validate_body(body)

    def test_invalid_utf8_and_deep_input_rejected(self):
        for body in [b"\xff", b"[" * 100 + b"0" + b"]" * 100]:
            with self.assertRaises(ContractError):
                validate_body(body)

    def test_body_limit_before_parse(self):
        with self.assertRaisesRegex(ContractError, "^body_too_large$"):
            validate_body(b" " * (MAX_BODY + 1))

    def test_invalid_value_not_echoed_in_error(self):
        self.payload["context"]["os_family"] = "PRIVATE-CANARY"
        with self.assertRaises(ContractError) as raised:
            validate_body(encode(self.payload))
        self.assertNotIn("PRIVATE-CANARY", str(raised.exception))

    def test_unknown_schema_notice_and_missing_fields(self):
        for key, value in [("schema_version", 2), ("notice_version", "future")]:
            candidate = deepcopy(self.payload)
            candidate[key] = value
            with self.assertRaises(ContractError):
                validate_body(encode(candidate))
        del self.payload["context"]
        with self.assertRaises(ContractError):
            validate_body(encode(self.payload))

    def test_duplicate_sequences_atomic_rejection(self):
        self.payload["events"].append(deepcopy(self.payload["events"][0]))
        with self.assertRaisesRegex(ContractError, "^duplicate_sequence$"):
            validate_body(encode(self.payload))

    def test_sequences_must_increase_within_batch(self):
        self.payload["events"] = [
            {"name": "session_started", "seq": 2},
            {"name": "error_count", "seq": 1, "category": "simulation_fault", "count": 1},
        ]
        with self.assertRaisesRegex(ContractError, "^sequence_order$"):
            validate_body(encode(self.payload))
        self.assertEqual(IngressModel().ingest(encode(self.payload), 0), 422)
        self.payload["events"][1]["seq"] = 3
        validate_body(encode(self.payload))

    def test_histogram_count_and_duration_consistency(self):
        for key, value in [("interval_count", 1801), ("interval_sum_us", 60_000_000)]:
            candidate = deepcopy(self.payload)
            candidate["events"][0][key] = value
            with self.assertRaises(ContractError):
                validate_body(encode(candidate))

    def test_booleans_not_integer_measurements(self):
        self.payload["events"][0]["interval_count"] = True
        with self.assertRaises(ContractError):
            validate_body(encode(self.payload))

    def test_gpu_zero_and_unverified_status(self):
        event = self.payload["events"][0]
        event.update(gpu_status="zero_ambiguous", gpu_ms=0)
        with self.assertRaises(ContractError):
            validate_body(encode(self.payload))
        event["gpu_ms"] = None
        validate_body(encode(self.payload))
        event.update(gpu_status="positive_freshness_unverified", gpu_ms=5.0)
        validate_body(encode(self.payload))

    def test_draw_unavailability_not_zero(self):
        self.payload["events"][0].update(draw_counter_status="unavailable", rendered_frames=0)
        with self.assertRaises(ContractError):
            validate_body(encode(self.payload))
        self.payload["events"][0]["rendered_frames"] = None
        validate_body(encode(self.payload))

    def test_unsupported_activity_counts_unknown(self):
        self.payload["events"] = [{
            "name": "activity_summary", "seq": 1, "vehicle_id": "rc-blimp-5m",
            "active_seconds": 60, "simulated_seconds": 60, "outcome": "returned_home",
            "complete_observation": True, "classification": "unsupported",
            "takeoffs": None, "landings": None, "aircraft_crashes": None,
        }]
        validate_body(encode(self.payload))
        self.payload["events"][0]["landings"] = 0
        with self.assertRaises(ContractError):
            validate_body(encode(self.payload))

    def test_fixed_wing_counts_require_known_stock_fixed_wing(self):
        # Independently inspected player-selectable fixed-wing catalog IDs at the baseline.
        fixed_wing = ["jensen-das-ugly-stik-60", "stik-electric-6s", "gp-extra-300s-60",
                      "p51d-mustang-120", "f4u-corsair-250", "sebart-avanti-s-a200-p100rx",
                      "turbo-lumber-evolution", "moonrunner-x99"]
        activity = {
            "name": "activity_summary", "seq": 1, "active_seconds": 60,
            "simulated_seconds": 60, "outcome": "returned_home", "complete_observation": True,
            "classification": "accepted_fixed_wing", "takeoffs": 1, "landings": 1, "aircraft_crashes": 0,
        }
        for vehicle in ["custom", "unknown", "xcell-60-research", "openrc-fpv5-x1",
                        "rc-blimp-5m", "mt8-bisonte", "monster-car-2"]:
            self.payload["events"] = [dict(activity, vehicle_id=vehicle)]
            with self.subTest(vehicle=vehicle), self.assertRaises(ContractError):
                validate_body(encode(self.payload))
            self.payload["events"][0].update(classification="unsupported", takeoffs=None,
                                             landings=None, aircraft_crashes=None)
            validate_body(encode(self.payload))
        for vehicle in fixed_wing:
            self.payload["events"] = [dict(activity, vehicle_id=vehicle)]
            with self.subTest(vehicle=vehicle):
                validate_body(encode(self.payload))

    def test_complete_window_requires_thirty_seconds_of_observed_time(self):
        event = self.payload["events"][0]
        event["interval_sum_us"] = 29_999_999
        with self.assertRaisesRegex(ContractError, "^incomplete_window$"):
            validate_body(encode(self.payload))
        event["window_complete"] = False
        validate_body(encode(self.payload))
        event.update(window_complete=True, interval_sum_us=30_000_000)
        validate_body(encode(self.payload))

    def test_start_and_bounded_error_event(self):
        self.payload["events"] = [
            {"name": "session_started", "seq": 1},
            {"name": "error_count", "seq": 2, "category": "simulation_fault", "count": 1},
        ]
        validate_body(encode(self.payload))
        self.payload["events"][1]["message"] = "private path"
        with self.assertRaises(ContractError):
            validate_body(encode(self.payload))


class MeasurementTests(unittest.TestCase):
    def test_independently_calculated_interval_distribution(self):
        window = FrameWindow()
        window.record(10_000, draws=1)
        window.record(50_000, draws=1)
        self.assertEqual(window.histogram, [0, 1, 0, 1, 0, 0, 0, 0])
        self.assertEqual(window.interval_sum_us, 60_000)
        self.assertAlmostEqual(window.rendered_frames * 1e6 / window.interval_sum_us, 33.333333, places=5)

    def test_suspend_gap_excluded_but_hitch_retained(self):
        window = FrameWindow()
        window.record(100_000)
        self.assertFalse(window.record(5_000_001))
        self.assertEqual(window.interval_count, 1)
        self.assertEqual(window.interval_sum_us, 100_000)
        self.assertEqual(window.excluded, 1)

    def test_default_draws_unknown_but_observed_zero_preserved(self):
        unknown = FrameWindow()
        unknown.record(16_000)
        self.assertIsNone(unknown.event()["rendered_frames"])
        zero = FrameWindow()
        zero.record(16_000, draws=0)
        event = zero.event()
        self.assertEqual(event["draw_counter_status"], "observed")
        self.assertEqual(event["rendered_frames"], 0)
        payload = example()
        payload["events"] = [event]
        validate_body(encode(payload))

    def test_invalid_clock_and_missing_draw_count(self):
        window = FrameWindow()
        with self.assertRaises(ContractError):
            window.record(-1)
        window.record(10_000, draws=None)
        self.assertIsNone(window.event()["rendered_frames"])

    def test_window_has_hard_duration_bound(self):
        window = FrameWindow()
        for _ in range(12):
            window.record(5_000_000)
        with self.assertRaises(ContractError):
            window.record(1)

    def test_empty_and_early_window_completion(self):
        window = FrameWindow()
        with self.assertRaisesRegex(ContractError, "^window_empty$"):
            window.event()
        window.record(2_500_000, draws=1)
        self.assertFalse(window.event()["window_complete"])
        with self.assertRaisesRegex(ContractError, "^incomplete_window$"):
            window.event(complete=True)
        for _ in range(11):
            window.record(2_500_000, draws=1)
        self.assertTrue(window.event()["window_complete"])
        self.assertFalse(window.event(complete=False)["window_complete"])
        payload = example()
        payload["events"] = [window.event()]
        validate_body(encode(payload))

    def test_draw_limit_is_atomic_and_encodable_at_boundary(self):
        window = FrameWindow()
        with self.assertRaisesRegex(ContractError, "^window_full$"):
            window.record(16_000, draws=60_001)
        self.assertEqual((window.interval_count, window.interval_sum_us), (0, 0))
        window.record(16_000, draws=60_000)
        before = window.event()
        with self.assertRaisesRegex(ContractError, "^window_full$"):
            window.record(16_000, draws=1)
        self.assertEqual(window.event(), before)
        payload = example()
        payload["events"] = [before]
        validate_body(encode(payload))

    def test_excluded_gap_limit_is_atomic_and_encodable_at_boundary(self):
        window = FrameWindow()
        window.record(16_000, draws=1)
        for _ in range(1000):
            self.assertFalse(window.record(5_000_001, draws=0))
        before = window.event()
        self.assertEqual(before["excluded_gap_count"], 1000)
        with self.assertRaisesRegex(ContractError, "^window_full$"):
            window.record(5_000_001, draws=0)
        self.assertEqual(window.event(), before)
        payload = example()
        payload["events"] = [before]
        validate_body(encode(payload))


class ConsentAndDeliveryTests(unittest.TestCase):
    def test_pending_and_declined_do_not_call_probe(self):
        client = ClientModel()
        def forbidden():
            self.fail("pre-consent probe")
        self.assertFalse(client.collect(forbidden, 0))
        self.assertIsNone(client.begin_send(0))
        client.disable()
        self.assertFalse(client.collect(forbidden, 1))

    def test_forced_off_and_old_notice_cannot_enable(self):
        self.assertFalse(ClientModel(eligible=False).enable())
        client = ClientModel()
        self.assertFalse(client.enable("old"))
        self.assertIsNone(client.session_id)

    def test_new_enable_rotates_identity(self):
        client = ClientModel()
        client.enable()
        original = client.session_id
        client.disable()
        client.enable()
        self.assertNotEqual(client.session_id, original)

    def test_disable_during_collection_prevents_queue(self):
        client = ClientModel()
        client.enable()
        def changing_policy():
            client.disable()
            return example()
        self.assertFalse(client.collect(changing_policy, 0))
        self.assertEqual(len(client.queue), 0)

    def test_disable_cancels_and_late_callback_cannot_resurrect(self):
        client = ClientModel()
        client.enable()
        client.collect(example, 0)
        token, _ = client.begin_send(0)
        client.disable()
        self.assertFalse(client.complete(token, 503, 1))
        self.assertFalse(client.queue)
        client.enable()
        self.assertFalse(client.complete(token, 202, 2))

    def test_preview_and_retry_bytes_identical(self):
        client = ClientModel()
        client.enable()
        client.collect(example, 0)
        preview = client.queue[0].body
        token, body = client.begin_send(0)
        self.assertEqual(preview, body)
        client.complete(token, 503, 1)
        _, retry_body = client.begin_send(10)
        self.assertEqual(retry_body, body)

    def test_old_attempt_cannot_ack_new_attempt(self):
        client = ClientModel()
        client.enable()
        client.collect(example, 0)
        old, _ = client.begin_send(0)
        client.complete(old, 503, 1)
        new, _ = client.begin_send(10)
        self.assertNotEqual(old, new)
        self.assertFalse(client.complete(old, 202, 11))
        self.assertTrue(client.active)

    def test_expired_memory_queue_not_replayed(self):
        client = ClientModel()
        client.enable()
        client.collect(example, 0)
        self.assertIsNone(client.begin_send(QUEUE_TTL))
        self.assertFalse(client.queue)

    def test_memory_queue_bounded_and_oldest_evicted(self):
        client = ClientModel()
        client.enable()
        for _ in range(40):
            client.collect(example, 0)
        self.assertLessEqual(len(client.queue), 32)
        self.assertLessEqual(sum(len(item.body) for item in client.queue), QUEUE_BYTES)

    def test_one_request_and_normal_cadence(self):
        client = ClientModel()
        client.enable()
        client.collect(example, 0)
        token, _ = client.begin_send(0)
        self.assertIsNone(client.begin_send(1))
        client.complete(token, 202, 1)
        client.collect(example, 2)
        self.assertIsNone(client.begin_send(2))
        self.assertIsNotNone(client.begin_send(60))

    def test_retry_after_not_ignored_or_sent_past_expiry(self):
        client = ClientModel()
        client.enable()
        client.collect(example, 0)
        token, _ = client.begin_send(0)
        client.complete(token, 429, 1, retry_after=120)
        self.assertIsNone(client.begin_send(120))
        self.assertIsNotNone(client.begin_send(121))
        token = client.active[0]
        client.complete(token, 429, 122, retry_after=900)
        self.assertFalse(client.queue)

    def test_permanent_status_drops_without_retry(self):
        for code in [202, 301, 400, 409, 413, 415, 422]:
            client = ClientModel()
            client.enable()
            client.collect(example, 0)
            token, _ = client.begin_send(0)
            client.complete(token, code, 1)
            with self.subTest(code=code):
                self.assertFalse(client.queue)

    def test_service_suspension_stops_collection(self):
        for code in [401, 403, 410]:
            client = ClientModel()
            client.enable()
            client.collect(example, 0)
            token, _ = client.begin_send(0)
            client.complete(token, code, 1)
            self.assertEqual(client.state, "suspended")
            self.assertFalse(client.enabled)

    def test_service_suspension_cannot_be_toggled_away_in_same_process(self):
        for code in [401, 403, 410]:
            client = ClientModel()
            self.assertTrue(client.enable())
            client.collect(example, 0)
            token, _ = client.begin_send(0)
            client.complete(token, code, 1)
            with self.subTest(code=code):
                self.assertTrue(client.service_suspended)
                self.assertFalse(client.enable())
                client.disable()
                self.assertFalse(client.enable())
                self.assertFalse(client.collect(lambda: self.fail("suspended probe"), 2))
                self.assertIsNone(client.begin_send(2))
                self.assertTrue(ClientModel().enable())

    def test_invalid_disable_state_does_not_open_probe_gate(self):
        client = ClientModel()
        client.disable("enabled")
        self.assertFalse(client.enabled)
        self.assertFalse(client.collect(lambda: self.fail("ungranted probe"), 0))

    def test_direct_suspension_is_sticky_across_off_and_enable(self):
        client = ClientModel()
        client.enable()
        client.disable("suspended")
        client.disable()
        self.assertFalse(client.enable())
        self.assertFalse(client.collect(lambda: self.fail("suspended probe"), 0))

    def test_unknown_or_truthy_non_boolean_admission_stays_closed(self):
        for eligible in [None, 1, "true", "false", [], {}, {"eligible": True}]:
            with self.subTest(eligible=eligible):
                client = ClientModel(eligible=eligible)
                self.assertFalse(client.enable())
                self.assertFalse(client.enabled)
                self.assertFalse(client.collect(lambda: self.fail("inadmissible probe"), 0))

    def test_attempt_budget_includes_retry(self):
        client = ClientModel()
        client.enable()
        client.collect(example, 0)
        token, _ = client.begin_send(0)
        client.complete(token, 503, 1)
        client.hour_attempts = 90
        self.assertIsNone(client.begin_send(10))

    def test_byte_budget_includes_retry(self):
        client = ClientModel()
        client.enable()
        client.collect(example, 0)
        token, _ = client.begin_send(0)
        client.complete(token, 503, 1)
        client.hour_bytes = 256 * 1024
        self.assertIsNone(client.begin_send(10))

    def test_maximum_retry_count(self):
        client = ClientModel()
        client.enable()
        client.collect(example, 0)
        for attempt in range(6):
            now = attempt * 61
            result = client.begin_send(now)
            self.assertIsNotNone(result)
            client.complete(result[0], 503, now + 1, jitter=0)
        self.assertFalse(client.queue)


class IngressAndPublicationTests(unittest.TestCase):
    def test_ingress_distinguishes_malformed_large_and_invalid_content(self):
        ingress = IngressModel()
        bodies = [b"{", b"\xff", b'{"x":1,"x":2}', b"[" * 20 + b"0" + b"]" * 20,
                  encode(example()).replace(b'"gpu_ms":null', b'"gpu_ms":NaN')]
        for body in bodies:
            with self.subTest(body=body[:20]):
                self.assertEqual(ingress.ingest(body, 0), 400)
        self.assertEqual(ingress.ingest(b" " * (MAX_BODY + 1), 0), 413)
        payload = example()
        payload["context"]["os_family"] = "invalid"
        self.assertEqual(ingress.ingest(encode(payload), 0), 422)
        self.assertEqual(ingress.ingest(encode(example()).replace(b'"gpu_ms":null', b'"gpu_ms":1e999'), 0), 422)
        self.assertEqual((ingress.batches, ingress.events), ({}, {}))

    def test_openapi_represents_opaque_intermediary_failures(self):
        from generate_contracts import schemas
        responses = schemas()["openapi.json"]["paths"]["/v1/batches"]["post"]["responses"]
        self.assertIn("408", responses)
        self.assertIn("5XX", responses)
        self.assertIn("503", responses)
        self.assertNotIn("content", responses["408"])
        self.assertNotIn("content", responses["5XX"])

    def test_duplicate_is_accepted_once_and_conflict_rejected(self):
        ingress = IngressModel()
        body = encode(example())
        self.assertEqual(ingress.ingest(body, 0), 202)
        self.assertEqual(ingress.ingest(body, 1), 202)
        self.assertEqual(len(ingress.batches), 1)
        payload = example()
        payload["events"][0]["vehicle_id"] = "moonrunner-x99"
        self.assertEqual(ingress.ingest(encode(payload), 2), 409)

    def test_different_batch_reusing_event_refused_atomically(self):
        ingress = IngressModel()
        ingress.ingest(encode(example()), 0)
        payload = example()
        payload["batch_id"] = "c" * 32
        self.assertEqual(ingress.ingest(encode(payload), 1), 409)
        self.assertEqual(len(ingress.batches), 1)

    def test_invalid_batch_does_not_commit(self):
        ingress = IngressModel()
        payload = example()
        payload["events"].append({"name": "anything", "seq": 2})
        self.assertEqual(ingress.ingest(encode(payload), 0), 422)
        self.assertFalse(ingress.batches)

    def test_backpressure_does_not_ack_dropped_data(self):
        ingress = IngressModel(max_batches=0)
        self.assertEqual(ingress.ingest(encode(example()), 0), 503)

    def test_dedup_expiry_explicitly_limits_replay_protection(self):
        ingress = IngressModel()
        body = encode(example())
        self.assertEqual(ingress.ingest(body, 0), 202)
        self.assertEqual(ingress.ingest(body, RAW_TTL), 202)
        self.assertEqual(ingress.batches[example()["batch_id"]][0], RAW_TTL)

    def test_mixed_or_open_days_cannot_qualify_daily_cohort(self):
        records = [("2026-11-17", body) for body in cohort(20)]
        records[0] = ("2026-11-16", records[0][1])
        with self.assertRaisesRegex(ContractError, "^mixed_receipt_day$"):
            aggregate_daily_gpu(records, "2026-11-17", "v0.2.7", as_of_utc="2026-11-18T01:00:00Z")
        with self.assertRaisesRegex(ContractError, "^day_not_eligible$"):
            aggregate_daily_gpu([], "2026-11-18", "v0.2.7", as_of_utc="2026-11-18T01:00:00Z")

    def test_daily_close_and_recovery_deadline(self):
        records = [("2026-11-17", body) for body in cohort(20)]
        for instant in ["2026-11-18T00:59:59Z", "2026-11-18T23:00:00Z", "2026-11-18T01:00:00+05:00"]:
            with self.subTest(instant=instant), self.assertRaises(ContractError):
                aggregate_daily_gpu(records, "2026-11-17", "v0.2.7", as_of_utc=instant)
        report = aggregate_daily_gpu(records, "2026-11-17", "v0.2.7", as_of_utc="2026-11-18T01:00:00Z")
        self.assertEqual(report["day"], "2026-11-17")
        self.assertIn("UTC day: 2026-11-17", render_report(report))

    def test_syntactically_valid_unapproved_build_rejected(self):
        payload = example()
        payload["build"]["release_id"] = "v999.0.0"
        validate_body(encode(payload))
        self.assertEqual(IngressModel().ingest(encode(payload), 0), 422)

    def test_session_contribution_cap(self):
        bodies = cohort(19)
        for seq in range(1, 131):
            payload = example()
            payload["session_id"] = f"{20:032x}"
            payload["batch_id"] = f"{seq + 2000000:032x}"
            payload["events"][0]["seq"] = seq
            bodies.append(encode(payload))
        report = daily_report(bodies, "v0.2.7")
        self.assertEqual(report["rows"][0]["session_observations"], 20)
        self.assertEqual(report["rows"][0]["rendered_frames"], (19 + 120) * 1800)

    def test_threshold_19_suppressed_20_ready(self):
        for count, status in [(19, "suppressed"), (20, "ready")]:
            report = daily_report(cohort(count), "v0.2.7")
            self.assertEqual(report["status"], status)
            self.assertEqual(bool(report["rows"]), count == 20)

    def test_repeated_windows_do_not_inflate_session_threshold(self):
        bodies = []
        for i in range(40):
            payload = example()
            payload["batch_id"] = f"{i:032x}"
            payload["events"][0]["seq"] = i + 1
            bodies.append(encode(payload))
        self.assertEqual(daily_report(bodies, "v0.2.7")["status"], "suppressed")

    def test_small_cell_suppresses_entire_table_without_total(self):
        report = daily_report(cohort(20) + cohort(1, "apple_silicon", 100), "v0.2.7")
        self.assertEqual(report["status"], "suppressed")
        self.assertEqual(report["rows"], [])
        self.assertNotIn("| 20 |", render_report(report))

    def test_duplicate_delivery_does_not_double_count(self):
        bodies = cohort(20)
        report = daily_report(bodies + bodies, "v0.2.7")
        self.assertEqual(report["rows"][0]["rendered_frames"], 20 * 1800)

    def test_weighted_rate_is_ratio_of_totals_not_mean_fps(self):
        bodies = []
        for i in range(20):
            payload = example()
            payload["session_id"] = f"{i:032x}"
            payload["batch_id"] = f"{i + 1000:032x}"
            event = payload["events"][0]
            if i < 10:
                event.update(interval_count=3000, interval_sum_us=30_000_000, rendered_frames=3000,
                             interval_histogram=[0, 3000, 0, 0, 0, 0, 0, 0])
            else:
                event.update(interval_count=1200, interval_sum_us=60_000_000, rendered_frames=1200,
                             interval_histogram=[0, 0, 0, 1200, 0, 0, 0, 0])
            bodies.append(encode(payload))
        report = daily_report(bodies, "v0.2.7")
        self.assertIn("46.67", render_report(report))
        self.assertNotIn("60.00", render_report(report))

    def test_partial_warmup_and_unavailable_excluded(self):
        for update in [{"window_complete": False}, {"phase": "warmup"},
                       {"rendered_frames": None, "draw_counter_status": "unavailable"}]:
            bodies = []
            for body in cohort(20):
                payload = json.loads(body)
                payload["events"][0].update(update)
                bodies.append(encode(payload))
            report = daily_report(bodies, "v0.2.7")
            self.assertEqual(report["status"], "no_data")

    def test_mixed_builds_rejected(self):
        bodies = cohort(20)
        payload = json.loads(bodies[0])
        payload["build"]["release_id"] = "v0.2.6"
        bodies[0] = encode(payload)
        with self.assertRaisesRegex(ContractError, "^mixed_release$"):
            daily_report(bodies, "v0.2.7")

    def test_report_forbids_identity_and_injection(self):
        report = daily_report(cohort(20), "v0.2.7")
        report["session_id"] = "a" * 32
        with self.assertRaises(ContractError):
            render_report(report)
        del report["session_id"]
        report["rows"][0]["gpu_family"] = "@all $(danger)"
        with self.assertRaises(ContractError):
            render_report(report)

    def test_report_calendar_and_duplicate_cells(self):
        report = daily_report(cohort(20), "v0.2.7")
        report["period"] = "2026-W99"
        with self.assertRaises(ContractError):
            render_report(report)
        report["period"] = "2026-W47"
        report["rows"].append(deepcopy(report["rows"][0]))
        with self.assertRaises(ContractError):
            render_report(report)

    def test_report_exposure_and_frames_obey_session_bounds(self):
        report = daily_report(cohort(20), "v0.2.7")
        row = report["rows"][0]
        sessions = row["session_observations"]
        minimum = sessions * 30_000_000
        maximum = sessions * 120 * 60_000_000
        max_frames = sessions * 120 * 60_000
        for exposure in [minimum - 1, maximum + 1]:
            row["interval_sum_us"] = exposure
            with self.subTest(exposure=exposure), self.assertRaisesRegex(ContractError, "^report_exposure$"):
                validate_report(report)
        for exposure in [minimum, maximum]:
            row.update(interval_sum_us=exposure, rendered_frames=max_frames)
            with self.subTest(exposure=exposure):
                validate_report(report)
        row["rendered_frames"] = max_frames + 1
        with self.assertRaisesRegex(ContractError, "^report_frames$"):
            validate_report(report)

    def test_report_scalar_capacity_rejects_whole_report_without_truncation(self):
        report = daily_report(cohort(20), "v0.2.7")
        stress = {"gpu_family": "amd_radeon", "session_observations": 300_000_000,
                  "interval_sum_us": 2**53 - 1, "rendered_frames": 0}
        report["rows"].append(stress)
        # The stress row is feasible under the per-session duration bounds.
        validate_report(report)
        stress["interval_sum_us"] += 1
        original = deepcopy(report)
        with self.assertRaisesRegex(ContractError, "^report_schema$"):
            render_report(report)
        self.assertEqual(report, original)

        stress.update(session_observations=140_000, interval_sum_us=140_000 * 30_000_000,
                      rendered_frames=10**12)
        validate_report(report)
        stress["rendered_frames"] += 1
        original = deepcopy(report)
        with self.assertRaisesRegex(ContractError, "^report_schema$"):
            render_report(report)
        self.assertEqual(report, original)

    def test_empty_rollup_still_validates_request_and_calendar_safely(self):
        when = "2026-11-18T01:00:00Z"
        for day in [None, 1, "2026-99-99", "9999-12-31"]:
            with self.subTest(day=day), self.assertRaises(ContractError):
                aggregate_daily_gpu([], day, "v0.2.7", as_of_utc=when)
        for when_bad in [None, 10, "invalid"]:
            with self.subTest(as_of=when_bad), self.assertRaises(ContractError):
                aggregate_daily_gpu([], "2026-11-17", "v0.2.7", as_of_utc=when_bad)
        for release in [None, "", "v1.2.3\n", "PRIVATE/CANARY"]:
            with self.subTest(release=release), self.assertRaises(ContractError):
                aggregate_daily_gpu([], "2026-11-17", release, as_of_utc=when)
        self.assertEqual(aggregate_daily_gpu([], "2026-11-17", "v0.2.7", as_of_utc=when)["status"], "no_data")

    def test_empty_data_is_not_zero_fps(self):
        report = daily_report([], "v0.2.7")
        self.assertEqual(report["status"], "no_data")
        self.assertNotIn("0.00", render_report(report))

    def test_report_discloses_censored_long_stalls_and_missing_gap_counts(self):
        body = render_report(daily_report(cohort(20), "v0.2.7"))
        self.assertIn("at least 30 s observed time and observed draw counts", body)
        self.assertIn("including real foreground stalls", body)
        self.assertIn("does not measure freeze incidence", body)
        self.assertIn("gap counts are not in this table", body)
        self.assertIn("pools channels and other contexts", body)


if __name__ == "__main__":
    unittest.main(verbosity=2)
