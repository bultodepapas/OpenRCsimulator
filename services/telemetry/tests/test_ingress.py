import logging
import unittest

from starlette.testclient import TestClient

from openrc_telemetry.ingress import create_app
from openrc_telemetry.limits import RateLimiter
from openrc_telemetry.storage import StorageUnavailable

from .support import (FakeClock, TempDir, activity_event, batch, encode, fixture, hex32, make_config,
                      perf_event)

JSON = {"content-type": "application/json"}


class IngressCase(unittest.TestCase):
    def setUp(self):
        self._tmp = TempDir()
        self.dir = self._tmp.__enter__()
        self.clock = FakeClock(1_800_000_000)
        self.make()

    def make(self, **overrides):
        self.config = make_config(self.dir, **overrides)
        self.app = create_app(self.config, clock=self.clock)
        self.client = TestClient(self.app)

    def tearDown(self):
        self.client.close()
        self.app.state.raw.close()
        self.app.state.aggregates.close()
        self._tmp.__exit__()

    def post(self, body, headers=JSON, **kwargs):
        return self.client.post("/v1/batches", content=body, headers=headers, **kwargs)


class StatusTests(IngressCase):
    def test_health(self):
        response = self.client.get("/healthz")
        self.assertEqual((response.status_code, response.json()), (200, {"status": "ok"}))

    def test_unknown_routes_are_404(self):
        for path in ("/", "/v1/batches/", "/v1/batch", "/metrics", "/v1/reports/other"):
            self.assertEqual(self.client.get(path).status_code, 404, path)
        self.assertEqual(self.client.post("/healthz").status_code, 405)
        self.assertEqual(self.client.get("/v1/batches").status_code, 405)

    def test_canonical_fixture_accepted_and_replay_is_idempotent(self):
        body = encode(fixture())
        first = self.post(body)
        self.assertEqual((first.status_code, first.content), (202, b""))
        again = self.post(body)
        self.assertEqual(again.status_code, 202)
        self.assertEqual(self.app.state.raw.count(), 1)

    def test_415_media_type_and_encoding(self):
        body = encode(batch())
        self.assertEqual(self.post(body, {"content-type": "text/plain"}).status_code, 415)
        self.assertEqual(self.post(body, {}).status_code, 415)
        self.assertEqual(self.post(body, {"content-type": "application/json; charset=latin-1"}).status_code, 415)
        self.assertEqual(self.post(body, {**JSON, "content-encoding": "gzip"}).status_code, 415)
        self.assertEqual(self.post(body, {"content-type": "Application/JSON; charset=UTF-8"}).status_code, 202)

    def test_413_oversize_is_rejected_before_parsing(self):
        calls = []
        original = self.app.state.raw.ingest
        self.app.state.raw.ingest = lambda *a, **k: calls.append(1) or original(*a, **k)
        oversize = b"{" + b" " * 40000 + b"}"
        self.assertEqual(self.post(oversize).status_code, 413)
        # Streamed without a Content-Length header, and still bounded.
        response = self.client.post("/v1/batches", content=(b"x" * 1000 for _ in range(100)), headers=JSON)
        self.assertEqual(response.status_code, 413)
        self.assertEqual(calls, [])
        # Exactly the maximum is accepted for parsing (then rejected as invalid, not as too large).
        self.assertEqual(self.post(b" " * 32768).status_code, 400)
        self.assertEqual(self.post(b" " * 32769).status_code, 413)

    def test_413_does_not_invoke_the_validator(self):
        original = self.app.state.limiter
        from openrc_telemetry import contract
        calls = []
        saved = contract.Contracts.validate_body
        contract.Contracts.validate_body = lambda *a, **k: calls.append(1) or saved(*a, **k)
        try:
            self.assertEqual(self.post(b"[" * 33000).status_code, 413)
        finally:
            contract.Contracts.validate_body = saved
        self.assertEqual(calls, [])
        self.assertIs(original, self.app.state.limiter)

    def test_400_variants(self):
        deep = b"[" * 200 + b"]" * 200
        cases = {
            "duplicate key": b'{"a":1,"a":2}',
            "NaN": b'{"schema_version":NaN}',
            "Infinity": b'[Infinity]',
            "bad utf8": b'{"a":"\xff\xfe"}',
            "bad json": b"{not json",
            "empty": b"",
            "depth": deep,
            "deep recursion": b"[" * 30000,
            "bom": b"\xef\xbb\xbf{}",
        }
        for name, body in cases.items():
            self.assertEqual(self.post(body).status_code, 400, name)
        self.assertEqual(self.post(b"{}", {**JSON, "content-length": "abc"}).status_code, 400)

    def test_422_variants(self):
        base = batch(1, events=[perf_event(1), perf_event(2)])
        bad_schema = batch(2)
        bad_schema["context"]["os_family"] = "beos"
        extra_field = batch(3)
        extra_field["extra"] = 1
        bad_order = batch(4, events=[perf_event(2), perf_event(1)])
        dup_seq = batch(5, events=[perf_event(1), perf_event(1)])
        bad_hist = batch(6)
        bad_hist["events"][0]["interval_histogram"][1] = 1799
        bad_duration = batch(7)
        bad_duration["events"][0]["interval_sum_us"] = 59_000_000
        short_complete = batch(8, events=[{**perf_event(1), "interval_sum_us": 29_999_999,
                                           "interval_histogram": [0, 1800, 0, 0, 0, 0, 0, 0]}])
        unknown_release = batch(9, release="v9.9.9")
        overflow = encode(batch(10)).replace(b'"gpu_ms":null', b'"gpu_ms":1e999')
        for name, payload in {"schema": bad_schema, "extra": extra_field, "order": bad_order, "dup": dup_seq,
                              "hist": bad_hist, "duration": bad_duration, "incomplete": short_complete,
                              "release": unknown_release}.items():
            self.assertEqual(self.post(encode(payload)).status_code, 422, name)
        self.assertEqual(self.post(overflow).status_code, 422)
        self.assertEqual(self.post(encode(base)).status_code, 202)

    def test_error_bodies_are_tiny_fixed_json_and_never_echo_input(self):
        canary = "CANARY-secret-value"
        payload = batch(1)
        payload["context"]["os_family"] = canary
        response = self.post(encode(payload))
        self.assertEqual(response.status_code, 422)
        self.assertEqual(response.json(), {"code": "invalid_request"})
        self.assertLess(len(response.content), 4096)
        self.assertNotIn(canary.encode(), response.content)

    def test_409_same_batch_id_different_bytes(self):
        first = batch(1, batch_id=77)
        second = batch(2, batch_id=77)
        self.assertEqual(self.post(encode(first)).status_code, 202)
        self.assertEqual(self.post(encode(second)).status_code, 409)
        self.assertEqual(self.post(encode(first)).status_code, 202)
        self.assertEqual(self.app.state.raw.count(), 1)

    def test_409_overlapping_session_sequence(self):
        self.assertEqual(self.post(encode(batch(1, batch_id=1, events=[perf_event(1), perf_event(2)]))).status_code, 202)
        overlap = batch(1, batch_id=2, events=[perf_event(2), perf_event(3)])
        self.assertEqual(self.post(encode(overlap)).status_code, 409)
        # The conflicting batch rolled back completely: seq 3 is still free.
        self.assertEqual(self.post(encode(batch(1, batch_id=3, events=[perf_event(3)]))).status_code, 202)
        self.assertEqual(self.app.state.raw.count(), 2)

    def test_429_with_retry_after(self):
        self.client.close()
        self.make(client_burst=2.0, client_refill_per_s=0.1)
        statuses = [self.post(encode(batch(n))).status_code for n in (1, 2, 3)]
        self.assertEqual(statuses, [202, 202, 429])
        blocked = self.post(encode(batch(4)))
        self.assertEqual(blocked.json(), {"code": "rate_limited"})
        self.assertTrue(blocked.headers["retry-after"].isdigit())
        self.assertGreaterEqual(int(blocked.headers["retry-after"]), 1)

    def test_global_cap_429(self):
        self.client.close()
        self.make(global_burst=1.0, global_refill_per_s=0.01)
        self.assertEqual(self.post(encode(batch(1))).status_code, 202)
        self.assertEqual(self.post(encode(batch(2))).status_code, 429)

    def test_503_when_storage_unavailable(self):
        def broken(*args, **kwargs):
            raise StorageUnavailable("storage")
        self.app.state.raw.ingest = broken
        response = self.post(encode(batch(1)))
        self.assertEqual((response.status_code, response.json()), (503, {"code": "unavailable"}))

    def test_503_when_database_file_is_unusable(self):
        self.client.close()
        self.app.state.raw.close()
        blocked = self.dir / "blocked"
        blocked.write_text("a file where a directory is needed")
        self.make(data_dir=blocked / "sub")
        self.assertEqual(self.post(encode(batch(1))).status_code, 503)

    def test_503_when_storage_is_full(self):
        self.client.close()
        self.make(max_raw_bytes=1)
        self.assertEqual(self.post(encode(batch(1))).status_code, 503)

    def test_empty_release_allowlist_rejects_everything(self):
        self.client.close()
        self.make(releases=frozenset())
        self.assertEqual(self.post(encode(fixture())).status_code, 422)

    def test_410_for_a_suspended_release_is_never_stored(self):
        self.client.close()
        self.make(releases=frozenset({"v0.2.7"}), suspended_releases=frozenset({"v0.2.8"}))
        self.assertEqual(self.post(encode(batch(1, release="v0.2.8"))).status_code, 410)
        self.assertEqual(self.app.state.raw.count(), 0)
        self.assertEqual(self.post(encode(batch(2, release="v0.2.7"))).status_code, 202)
        self.assertEqual(self.post(b"{not json").status_code, 400)  # malformed input is still a 400

    def test_410_for_everything_when_suspended(self):
        self.client.close()
        self.make(suspend_all=True)
        response = self.post(encode(fixture()))
        self.assertEqual((response.status_code, response.json()), (410, {"code": "suspended"}))
        self.assertEqual(self.app.state.raw.count(), 0)

    def test_raw_and_aggregates_can_live_in_separate_directories(self):
        self.client.close()
        self.app.state.raw.close()
        self.make(raw_dir=self.dir / "raw-volume", aggregates_dir=self.dir / "aggregate-volume")
        self.assertEqual(self.post(encode(fixture())).status_code, 202)
        self.assertTrue((self.dir / "raw-volume" / "raw.sqlite").exists())
        self.assertFalse((self.dir / "aggregate-volume" / "raw.sqlite").exists())
        self.assertEqual(self.config.aggregates_path, self.dir / "aggregate-volume" / "aggregates.sqlite")

    def test_activity_summary_batch_accepted(self):
        payload = batch(1, events=[perf_event(1), activity_event(2)])
        self.assertEqual(self.post(encode(payload)).status_code, 202)

    def test_raw_database_contains_only_validated_bytes(self):
        body = encode(batch(1))
        self.post(body)
        with self.app.state.raw.connection() as conn:
            row = conn.execute("SELECT batch_id, body_sha256, session_id, receipt_unix, receipt_day, body FROM batches").fetchone()
        self.assertEqual(bytes(row[5]), body)
        self.assertEqual(row[4], "2027-01-15")


class ProxyTests(IngressCase):
    def test_forwarded_for_ignored_unless_trusted(self):
        self.client.close()
        self.make(client_burst=1.0, client_refill_per_s=0.001)
        first = self.post(encode(batch(1)), {**JSON, "x-forwarded-for": "198.51.100.1"})
        second = self.post(encode(batch(2)), {**JSON, "x-forwarded-for": "198.51.100.2"})
        self.assertEqual((first.status_code, second.status_code), (202, 429))

    def test_rightmost_forwarded_for_used_when_trusted(self):
        self.client.close()
        self.make(client_burst=1.0, client_refill_per_s=0.001, trust_proxy=True)
        send = lambda n, xff: self.post(encode(batch(n)), {**JSON, "x-forwarded-for": xff}).status_code  # noqa: E731
        # The left part is client-controlled and must not matter; the proxy-added right part does.
        self.assertEqual(send(1, "10.0.0.1, 203.0.113.9"), 202)
        self.assertEqual(send(2, "10.0.0.2, 203.0.113.9"), 429)
        self.assertEqual(send(3, "10.0.0.2, 203.0.113.10"), 202)


class LoggingTests(IngressCase):
    def test_logs_contain_only_fixed_categories(self):
        canary = "CANARY-session-canary"
        payload = batch(1)
        payload["context"]["os_family"] = canary
        with self.assertLogs("openrc_telemetry", level=logging.DEBUG) as captured:
            self.post(encode(payload), {**JSON, "user-agent": "CANARY-agent"})
            self.post(b'{"a":"CANARY-body","a":1}')
            self.post(encode(batch(2)))
        text = "\n".join(captured.output)
        for secret in ("CANARY", "testclient", "127.0.0.1", hex32(1), hex32(2)):
            self.assertNotIn(secret, text)
        self.assertIn("category=schema", text)
        self.assertIn("category=duplicate_key", text)


class ReportEndpointTests(IngressCase):
    def test_disabled_without_token(self):
        response = self.client.get("/v1/reports/weekly?week=2027-W02&release=v0.2.7",
                                   headers={"authorization": "Bearer anything"})
        self.assertEqual(response.status_code, 404)

    def test_requires_bearer_token_and_valid_query(self):
        self.client.close()
        self.make(report_token="s3cret-token")
        url = "/v1/reports/weekly?week=2027-W02&release=v0.2.7"
        self.assertEqual(self.client.get(url).status_code, 401)
        self.assertEqual(self.client.get(url, headers={"authorization": "Bearer nope"}).status_code, 401)
        self.assertEqual(self.client.get(url, headers={"authorization": "Basic s3cret-token"}).status_code, 401)
        good = {"authorization": "Bearer s3cret-token"}
        self.assertEqual(self.client.get("/v1/reports/weekly?week=bad&release=v0.2.7", headers=good).status_code, 400)
        self.assertEqual(self.client.get("/v1/reports/weekly?week=2027-W02&release=x", headers=good).status_code, 400)
        response = self.client.get(url, headers=good)
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(set(body), {"title", "body", "digest"})
        self.assertEqual(len(body["digest"]), 64)
        self.assertEqual(self.client.get(url, headers=good).json(), body)

    def test_limiter_is_used_for_failed_attempts(self):
        self.client.close()
        self.make(report_token="s3cret-token", client_burst=2.0, client_refill_per_s=0.001)
        url = "/v1/reports/weekly?week=2027-W02&release=v0.2.7"
        codes = [self.client.get(url, headers={"authorization": "Bearer bad"}).status_code for _ in range(3)]
        self.assertEqual(codes, [401, 401, 429])


class LimiterTests(unittest.TestCase):
    def test_keys_rotate_and_are_not_the_address(self):
        now = [0.0]
        keys = iter([b"k1" * 16, b"k2" * 16, b"k3" * 16])
        limiter = RateLimiter(1, 0.0001, 1000, 1000, monotonic=lambda: now[0], key_source=lambda: next(keys))
        self.assertEqual(limiter.check("203.0.113.1"), 0)
        self.assertGreater(limiter.check("203.0.113.1"), 0)
        for key in limiter._clients:
            self.assertNotIn(b"203.0.113.1", key)
        now[0] = 15 * 60  # rotation drops every bucket, so the address is forgotten
        self.assertEqual(limiter.tracked_clients(), 1)
        self.assertEqual(limiter.check("203.0.113.1"), 0)
        self.assertEqual(limiter.tracked_clients(), 1)

    def test_ipv6_clients_share_a_bucket_per_64(self):
        limiter = RateLimiter(1, 0.0001, 1000, 1000, monotonic=lambda: 0.0)
        self.assertEqual(limiter.check("2001:db8:1:2::1"), 0)
        self.assertGreater(limiter.check("2001:db8:1:2:ffff::9"), 0)  # same /64: limited
        self.assertEqual(limiter.check("2001:db8:1:3::1"), 0)  # another /64
        self.assertEqual(limiter.check("::ffff:203.0.113.9"), 0)  # IPv4-mapped counts as the IPv4 address
        self.assertGreater(limiter.check("203.0.113.9"), 0)

    def test_refill_and_global_cap(self):
        now = [0.0]
        limiter = RateLimiter(2, 1.0, 3, 0.0001, monotonic=lambda: now[0])
        self.assertEqual([limiter.check("a"), limiter.check("a"), limiter.check("a") > 0], [0, 0, True])
        now[0] = 5
        self.assertEqual(limiter.check("a"), 0)       # refilled client token, global bucket 3rd
        self.assertGreater(limiter.check("b"), 0)     # global bucket exhausted

    def test_client_table_is_bounded(self):
        limiter = RateLimiter(5, 1, 1000, 1000, max_clients=2, monotonic=lambda: 0.0)
        limiter.check("a")
        limiter.check("b")
        self.assertGreater(limiter.check("c"), 0)
        self.assertEqual(limiter.tracked_clients(), 2)


if __name__ == "__main__":
    unittest.main()
