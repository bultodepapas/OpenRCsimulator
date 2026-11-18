"""The service validator must accept/reject exactly what research/telemetry/reference.py does."""
from copy import deepcopy
import json
import sys
import unittest

from starlette.testclient import TestClient

from openrc_telemetry.contract import ContractError, http_status, load_contracts
from openrc_telemetry.ingress import create_app
from openrc_telemetry.rollup import aggregate_daily_gpu

from .support import (CONTEXT, RELEASE, SCHEMA_DIR, TELEMETRY_RESEARCH, FakeClock, TempDir, activity_event,
                      batch, encode, fixture, make_config, perf_event)

sys.path.insert(0, str(TELEMETRY_RESEARCH))
import reference  # noqa: E402  (tests only; the service never imports research code)

contracts = load_contracts(SCHEMA_DIR)


def rich_batch():
    return batch(3, events=[
        {"name": "session_started", "seq": 1},
        perf_event(2),
        activity_event(3),
        {"name": "error_count", "seq": 4, "category": "simulation_fault", "count": 2},
        {**activity_event(5, vehicle="xcell-60-research"), "classification": "unsupported", "takeoffs": None,
         "landings": None, "aircraft_crashes": None},
    ])


def mutate(payload, *path, value=None, delete=False):
    clone = deepcopy(payload)
    target = clone
    for step in path[:-1]:
        target = target[step]
    if delete:
        del target[path[-1]]
    else:
        target[path[-1]] = value
    return clone


def dict_mutations():
    base, rich = fixture(), rich_batch()
    cases = {"fixture": base, "rich": rich, "rich_other_release": batch(4, release="v0.2.8")}
    for key in base:
        cases[f"drop_{key}"] = mutate(base, key, delete=True)
    cases["unknown_top"] = mutate(base, "extra", value=1)
    cases["unknown_build"] = mutate(base, "build", "extra", value=1)
    cases["unknown_context"] = mutate(base, "context", "extra", value="x")
    cases["unknown_event_field"] = mutate(base, "events", 0, "extra", value=1)
    for key in CONTEXT:
        cases[f"bad_context_{key}"] = mutate(base, "context", key, value="bogus")
        cases[f"drop_context_{key}"] = mutate(base, "context", key, delete=True)
    cases.update({
        "schema_version_2": mutate(base, "schema_version", value=2),
        "schema_version_str": mutate(base, "schema_version", value="1"),
        "notice_old": mutate(base, "notice_version", value="2026-01-01"),
        "session_upper": mutate(base, "session_id", value="A" * 32),
        "session_short": mutate(base, "session_id", value="a" * 31),
        "session_nonhex": mutate(base, "session_id", value="g" * 32),
        "session_newline": mutate(base, "session_id", value="a" * 31 + "\n"),
        "batch_long": mutate(base, "batch_id", value="b" * 33),
        "release_short": mutate(base, "build", "release_id", value="v1.2"),
        "release_newline": mutate(base, "build", "release_id", value="v0.2.7\n"),
        "release_dot_beta": mutate(base, "build", "release_id", value="v0.2.7-beta.1"),
        "release_rc": mutate(base, "build", "release_id", value="v0.2.7-rc2"),
        "release_unknown": mutate(base, "build", "release_id", value="v9.9.9"),
        "channel_bad": mutate(base, "build", "channel", value="beta"),
        "engine_bad": mutate(base, "build", "engine_minor", value="4.7"),
        "events_empty": mutate(base, "events", value=[]),
        "events_17": mutate(base, "events", value=[perf_event(n) for n in range(1, 18)]),
        "events_16": mutate(base, "events", value=[perf_event(n) for n in range(1, 17)]),
        "seq_zero": mutate(base, "events", 0, "seq", value=0),
        "seq_max": mutate(base, "events", 0, "seq", value=1_000_000),
        "seq_over": mutate(base, "events", 0, "seq", value=1_000_001),
        "seq_bool": mutate(base, "events", 0, "seq", value=True),
        "seq_float": mutate(base, "events", 0, "seq", value=1.5),
        "seq_str": mutate(base, "events", 0, "seq", value="1"),
        "seq_order": mutate(base, "events", value=[perf_event(2), perf_event(1)]),
        "seq_dup": mutate(base, "events", value=[perf_event(1), perf_event(1)]),
        "seq_gap_ok": mutate(base, "events", value=[perf_event(1), perf_event(9)]),
        "hist_sum": mutate(base, "events", 0, "interval_histogram", 1, value=1799),
        "hist_short": mutate(base, "events", 0, "interval_histogram", value=[1800]),
        "hist_negative": mutate(base, "events", 0, "interval_histogram", 0, value=-1),
        "duration_low": mutate(base, "events", 0, "interval_sum_us", value=10_000_000),
        "duration_high": mutate(base, "events", 0, "interval_sum_us", value=60_000_000),
        "incomplete_claim": mutate(base, "events", 0, "interval_sum_us", value=29_999_999),
        "partial_ok": mutate(mutate(base, "events", 0, "window_complete", value=False),
                             "events", 0, "interval_sum_us", value=20_000_000),
        "count_zero": mutate(base, "events", 0, "interval_count", value=0),
        "frames_null_observed": mutate(base, "events", 0, "rendered_frames", value=None),
        "frames_with_unavailable": mutate(base, "events", 0, "draw_counter_status", value="unavailable"),
        "gpu_ms_without_status": mutate(base, "events", 0, "gpu_ms", value=3.5),
        "gpu_positive_ok": mutate(mutate(base, "events", 0, "gpu_status", value="positive_freshness_unverified"),
                                  "events", 0, "gpu_ms", value=3.5),
        "gpu_positive_null": mutate(base, "events", 0, "gpu_status", value="positive_freshness_unverified"),
        "vehicle_bad": mutate(base, "events", 0, "vehicle_id", value="my-custom-plane"),
        "activity_seconds_over": mutate(rich, "events", 2, "active_seconds", value=1801),
        "activity_unsupported_counts": mutate(rich, "events", 4, "takeoffs", value=1),
        "activity_accepted_rotor": mutate(rich, "events", 2, "vehicle_id", value="xcell-60-research"),
        "activity_none_vehicle": mutate(rich, "events", 2, "vehicle_id", value="none"),
        "error_zero": mutate(rich, "events", 3, "count", value=0),
        "error_category_bad": mutate(rich, "events", 3, "category", value="disk_full_for_user"),
        "event_name_bad": mutate(base, "events", 0, "name", value="keypress"),
        "events_not_list": mutate(base, "events", value={}),
        "bool_as_int": mutate(base, "events", 0, "interval_count", value=True),
        "big_number": mutate(base, "events", 0, "interval_count", value=10**30),
        "nested_depth_inside_extra": mutate(base, "extra", value=[[[[[[[[[[[[[[[[[[1]]]]]]]]]]]]]]]]]]),
    })
    return cases


def raw_mutations():
    good = encode(fixture())
    return {
        "duplicate_key": good.replace(b'"schema_version":1', b'"schema_version":1,"schema_version":1'),
        "nan": good.replace(b'"gpu_ms":null', b'"gpu_ms":NaN'),
        "infinity": good.replace(b'"gpu_ms":null', b'"gpu_ms":Infinity'),
        "minus_infinity": good.replace(b'"gpu_ms":null', b'"gpu_ms":-Infinity'),
        "overflow_1e999": good.replace(b'"gpu_ms":null', b'"gpu_ms":1e999'),
        "bad_utf8": good.replace(b'"stable"', b'"\xff\xfe"'),
        "bom": b"\xef\xbb\xbf" + good,
        "truncated": good[:-5],
        "trailing_garbage": good + b"x",
        "trailing_ws_ok": good + b"  \n",
        "empty": b"",
        "null": b"null", "array": b"[]", "true": b"true", "string": b'"x"',
        "depth_17_ok_shape": b"[" * 5 + b"]" * 5,
        "depth_deep": b"[" * 40 + b"]" * 40,
        "recursion": b"[" * 30000,
        "pad_32768_ok": good + b" " * (32768 - len(good)),
        "pad_32769": good + b" " * (32769 - len(good)),
        "unicode_escape_key": good.replace(b'"seq"', b'"s\\u0065q"'),
        "lone_surrogate": good.replace(b'"stable"', b'"\\ud800"'),
        "control_char": good.replace(b'"stable"', b'"sta\x01ble"'),
        "single_quotes": good.replace(b'"', b"'"),
    }


class EquivalenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = TempDir()
        cls.dir = cls._tmp.__enter__()
        cls.config = make_config(cls.dir)
        cls.app = create_app(cls.config, clock=FakeClock(1_800_000_000))
        cls.client = TestClient(cls.app)

    @classmethod
    def tearDownClass(cls):
        cls.client.close()
        cls.app.state.raw.close()
        cls.app.state.aggregates.close()
        cls._tmp.__exit__()

    def reference_outcome(self, body):
        try:
            return "ok", reference.validate_body(body)
        except reference.ContractError as error:
            return "error", str(error)

    def service_outcome(self, body):
        try:
            return "ok", contracts.validate_body(body)
        except ContractError as error:
            return "error", str(error)

    def post_status(self, body):
        with self.app.state.raw.transaction() as conn:
            conn.execute("DELETE FROM batches")
        return self.client.post("/v1/batches", content=body, headers={"content-type": "application/json"}).status_code

    def check(self, name, body):
        expected = self.reference_outcome(body)
        actual = self.service_outcome(body)
        self.assertEqual(actual, expected, name)
        model_status = reference.IngressModel(approved_releases={RELEASE}).ingest(body, 1_800_000_000)
        self.assertEqual(self.post_status(body), model_status, name)
        if expected[0] == "error" and expected[1] != "unapproved_release":
            self.assertEqual(http_status(ContractError(expected[1])), model_status, name)
        return expected[0], model_status

    def test_canonical_fixture(self):
        self.assertEqual(self.check("fixture", FIXTURE_BYTES()), ("ok", 202))

    def test_dict_mutations_match_reference(self):
        cases = dict_mutations()
        self.assertGreaterEqual(len(cases), 30)
        outcomes = {name: self.check(name, encode(payload)) for name, payload in cases.items()}
        statuses = {status for _, status in outcomes.values()}
        self.assertEqual(statuses, {202, 400, 422})   # 400 only from the depth bound
        self.assertEqual(outcomes["fixture"], ("ok", 202))
        for accepted in ("rich", "seq_gap_ok", "partial_ok", "gpu_positive_ok", "events_16", "seq_max"):
            self.assertEqual(outcomes[accepted], ("ok", 202), accepted)
        self.assertEqual(outcomes["nested_depth_inside_extra"], ("error", 400))
        for release in ("release_dot_beta", "release_rc"):   # schema-valid tags, not allow-listed
            self.assertEqual(outcomes[release], ("ok", 422))
        self.assertEqual(outcomes["release_unknown"], ("ok", 422))   # schema-valid but not allow-listed
        self.assertEqual(outcomes["rich_other_release"], ("ok", 422))
        for rejected in ("drop_events", "unknown_top", "seq_order", "seq_dup", "hist_sum", "duration_low",
                         "incomplete_claim", "activity_unsupported_counts"):
            self.assertEqual(outcomes[rejected][0], "error", rejected)

    def test_raw_byte_mutations_match_reference_with_all_status_categories(self):
        cases = raw_mutations()
        outcomes = {name: self.check(name, body) for name, body in cases.items()}
        statuses = {status for _, status in outcomes.values()}
        self.assertEqual(statuses, {202, 400, 413, 422})
        self.assertEqual(outcomes["pad_32768_ok"], ("ok", 202))
        self.assertEqual(outcomes["pad_32769"][1], 413)
        self.assertEqual(outcomes["nan"][1], 400)
        self.assertEqual(outcomes["overflow_1e999"][1], 422)
        self.assertEqual(outcomes["duplicate_key"][1], 400)
        self.assertEqual(outcomes["depth_deep"][1], 400)
        self.assertEqual(outcomes["depth_17_ok_shape"][1], 422)

    def test_non_bytes_rejected_identically(self):
        self.assertEqual(self.service_outcome("{}"), self.reference_outcome("{}"))

    def test_conflict_and_duplicate_statuses_match_the_ingress_model(self):
        model = reference.IngressModel(approved_releases={RELEASE})
        raw = self.app.state.raw
        with raw.transaction() as conn:
            conn.execute("DELETE FROM batches")
        first, second = batch(1, batch_id=1, events=[perf_event(1), perf_event(2)]), batch(2, batch_id=1)
        overlap = batch(1, batch_id=2, events=[perf_event(2)])
        fresh = batch(1, batch_id=3, events=[perf_event(3)])
        for payload in (first, first, second, overlap, fresh):
            body = encode(payload)
            expected = model.ingest(body, 1_800_000_000)
            actual = self.client.post("/v1/batches", content=body,
                                      headers={"content-type": "application/json"}).status_code
            self.assertEqual(actual, expected)

    def test_daily_gpu_reducer_matches_reference(self):
        day, as_of = "2027-01-14", "2027-01-15T03:00:00Z"
        datasets = {
            "19_tokens": [batch(n, batch_id=n) for n in range(1, 20)],
            "20_tokens": [batch(n, batch_id=n) for n in range(1, 21)],
            "mixed_cells": [batch(n, batch_id=n) for n in range(1, 21)] +
                           [batch(n, batch_id=n, gpu="amd_radeon") for n in range(100, 119)],
            "two_cells_ready": [batch(n, batch_id=n) for n in range(1, 21)] +
                               [batch(n, batch_id=n, gpu="amd_radeon") for n in range(100, 120)],
            "no_data": [batch(n, batch_id=n, events=[perf_event(1, mode="home")]) for n in range(1, 30)],
            "cap_120": [batch(n, batch_id=n) for n in range(1, 20)] + [
                batch(500, batch_id=900 + chunk, events=[perf_event(chunk * 16 + i + 1) for i in range(16)])
                for chunk in range(9)],
            "retransmit_same_events": [batch(n, batch_id=n) for n in range(1, 21)] + [batch(1, batch_id=99)],
        }
        for name, payloads in datasets.items():
            records = [(day, encode(p)) for p in payloads]
            self.assertEqual(aggregate_daily_gpu(contracts, records, day, RELEASE, as_of_utc=as_of),
                             reference.aggregate_daily_gpu(records, day, RELEASE, as_of_utc=as_of), name)
        conflicting = [(day, encode(batch(1, batch_id=1))),
                       (day, encode(batch(1, batch_id=2, events=[perf_event(1, frames=1700)])))]
        for fn, args in ((aggregate_daily_gpu, (contracts,)), (reference.aggregate_daily_gpu, ())):
            with self.assertRaises((ContractError, reference.ContractError)):
                fn(*args, conflicting, day, RELEASE, as_of_utc=as_of)
        for bad_as_of in ("2027-01-14T23:59:59Z", "2027-01-16T00:00:00Z", "2027-01-15T03:00:00+02:00", "nonsense"):
            for fn, args in ((aggregate_daily_gpu, (contracts,)), (reference.aggregate_daily_gpu, ())):
                with self.assertRaises((ContractError, reference.ContractError), msg=bad_as_of):
                    fn(*args, [], day, RELEASE, as_of_utc=bad_as_of)

    def test_report_validator_matches_reference(self):
        row = {"gpu_family": "nvidia_rtx", "session_observations": 20, "interval_sum_us": 600_000_000,
               "rendered_frames": 36000}
        good = {"report_version": 1, "aggregation_scope": "closed_day", "day": "2027-01-14", "period": "2027-W02",
                "release_id": RELEASE, "status": "ready", "basis": "eligible_daily_session_observations",
                "rows": [row]}
        cases = [good, {**good, "period": "2027-W03"}, {**good, "status": "suppressed"},
                 {**good, "rows": [{**row, "session_observations": 19}]},
                 {**good, "rows": [{**row, "interval_sum_us": 1}]},
                 {**good, "rows": [{**row, "rendered_frames": 10**12}]},
                 {**good, "rows": [row, row]}, {**good, "day": "2027-02-30"}, {**good, "extra": 1},
                 {**good, "status": "no_data", "rows": []}, {**good, "rows": []}]
        for case in cases:
            expected = actual = "ok"
            try:
                reference.validate_report(case)
            except reference.ContractError as error:
                expected = str(error)
            try:
                contracts.validate_report(case)
            except ContractError as error:
                actual = str(error)
            self.assertEqual(actual, expected, json.dumps(case)[:120])


def FIXTURE_BYTES():
    return encode(fixture())


if __name__ == "__main__":
    unittest.main()
