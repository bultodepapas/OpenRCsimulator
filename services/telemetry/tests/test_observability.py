"""TELEM-20: ID-free ingest counters, operator status and the release check."""
from __future__ import annotations

import json
import unittest

from starlette.testclient import TestClient

from openrc_telemetry.cli import check_release_tag, status_report
from openrc_telemetry.counters import MAX_KEYS, IngestCounters, flush
from openrc_telemetry.ingress import create_app
from openrc_telemetry.storage import RAW_TTL, AggStore, RawStore, StorageUnavailable

from tests.support import FIXTURE, RELEASE, FakeClock, TempDir, batch, encode, make_config, unix

NOW = unix("2026-11-19T12:00:00Z")
HEADERS = {"Content-Type": "application/json"}


class CountersTest(unittest.TestCase):
    def setUp(self):
        self.tmp = TempDir()
        self.dir = self.tmp.__enter__()
        self.clock = FakeClock(NOW)

    def tearDown(self):
        self.tmp.__exit__(None, None, None)

    def app(self, **overrides):
        config = make_config(self.dir, **overrides)
        app = create_app(config, clock=self.clock)
        return app, TestClient(app)

    def persisted(self, app):
        flush(app.state.counters, app.state.aggregates)
        return app.state.aggregates.ingest_counts("2026-11-19")

    def test_outcomes_are_counted_by_fixed_category(self):
        app, client = self.app()
        body = encode(batch(1))
        self.assertEqual(client.post("/v1/batches", content=body, headers=HEADERS).status_code, 202)
        self.assertEqual(client.post("/v1/batches", content=body, headers=HEADERS).status_code, 202)
        other = encode(batch(2, release="v9.9.9"))
        self.assertEqual(client.post("/v1/batches", content=other, headers=HEADERS).status_code, 422)
        self.assertEqual(client.post("/v1/batches", content=body, headers={"Content-Type": "text/plain"}).status_code,
                         415)
        self.assertEqual(client.post("/v1/batches", content=b"{", headers=HEADERS).status_code, 400)
        counts = self.persisted(app)
        self.assertEqual(counts["accepted"], 1)
        self.assertEqual(counts["duplicate"], 1)
        self.assertEqual(counts["rejected:unapproved_release"], 1)
        self.assertEqual(counts["unsupported_media"], 1)
        self.assertEqual(sum(v for k, v in counts.items() if k.startswith("rejected:")), 2)

    def test_rate_limit_and_suspension_are_counted(self):
        app, client = self.app(client_burst=1.0, client_refill_per_s=0.0)
        body = encode(batch(1))
        client.post("/v1/batches", content=body, headers=HEADERS)
        self.assertEqual(client.post("/v1/batches", content=body, headers=HEADERS).status_code, 429)
        self.assertEqual(self.persisted(app)["rate_limited"], 1)
        app, client = self.app(suspend_all=True)
        self.assertEqual(client.post("/v1/batches", content=body, headers=HEADERS).status_code, 410)
        self.assertEqual(self.persisted(app)["suspended_all"], 1)

    def test_forwarded_header_presence_is_counted_without_its_value(self):
        app, client = self.app()
        client.post("/v1/batches", content=encode(batch(1)), headers={**HEADERS, "X-Forwarded-For": "203.0.113.9"})
        counts = self.persisted(app)
        self.assertEqual(counts["forwarded_for_present"], 1)
        with app.state.aggregates.connection() as conn:
            dump = "\n".join(conn.iterdump())
        self.assertNotIn("203.0.113.9", dump)
        self.assertNotIn(batch(1)["session_id"], dump)

    def test_counts_add_up_across_flushes_and_days(self):
        app, client = self.app()
        client.post("/v1/batches", content=encode(batch(1)), headers=HEADERS)
        self.persisted(app)
        client.post("/v1/batches", content=encode(batch(2)), headers=HEADERS)
        self.assertEqual(self.persisted(app)["accepted"], 2)
        self.clock.now = NOW + 86400
        client.post("/v1/batches", content=encode(batch(3)), headers=HEADERS)
        flush(app.state.counters, app.state.aggregates)
        self.assertEqual(app.state.aggregates.ingest_counts("2026-11-20"), {"accepted": 1})

    def test_counts_are_persisted_at_shutdown(self):
        # Regression (PRIMIS 2026-11-20): counters were lost when systemd stopped the service before the first
        # periodic flush, because uvicorn re-raises SIGTERM and code after uvicorn.run() never ran.
        config = make_config(self.dir)
        app = create_app(config, clock=self.clock)
        with TestClient(app) as client:  # entering/leaving runs the application lifespan
            client.post("/v1/batches", content=encode(batch(1)), headers=HEADERS)
            self.assertEqual(app.state.aggregates.ingest_counts("2026-11-19"), {})
        self.assertEqual(app.state.aggregates.ingest_counts("2026-11-19"), {"accepted": 1})

    def test_failed_flush_keeps_the_counts(self):
        counters = IngestCounters()
        counters.add("accepted", NOW)

        class Broken:
            def add_ingest_counts(self, items):
                raise StorageUnavailable("storage")

        with self.assertRaises(StorageUnavailable):
            flush(counters, Broken())
        self.assertEqual(counters.drain(), [("2026-11-19", "accepted", 1)])

    def test_keys_are_bounded_and_unsafe_categories_collapse(self):
        counters = IngestCounters()
        counters.add("Not A Category!", NOW)
        for index in range(MAX_KEYS + 10):
            counters.add(f"c{index}", NOW)
        items = counters.drain()
        self.assertLessEqual(len(items), MAX_KEYS + 1)
        self.assertIn("other", {category for _, category, _ in items})

    def test_aggregate_purge_removes_old_counters(self):
        agg = AggStore(self.dir / "aggregates.sqlite")
        agg.add_ingest_counts([("2026-01-01", "accepted", 3), ("2026-11-19", "accepted", 1)])
        agg.purge(NOW)
        self.assertEqual(agg.ingest_counts("2026-01-01"), {})
        self.assertEqual(agg.ingest_counts("2026-11-19"), {"accepted": 1})


class StatusAndReleaseCheckTest(unittest.TestCase):
    def setUp(self):
        self.tmp = TempDir()
        self.dir = self.tmp.__enter__()

    def tearDown(self):
        self.tmp.__exit__(None, None, None)

    def test_status_reports_raw_age_counters_and_retention(self):
        config = make_config(self.dir)
        raw, agg = RawStore(config.raw_path), AggStore(config.aggregates_path)
        empty = status_report(config, NOW, raw, agg)
        self.assertTrue(empty["retention_ok"])
        self.assertIsNone(empty["last_accepted_age_s"])
        body = encode(batch(1))
        raw.ingest(batch(1)["batch_id"], "d", batch(1)["session_id"], [1], body, NOW - 120)
        agg.add_ingest_counts([("2026-11-19", "accepted", 1)])
        agg.put_day("2026-11-18", RELEASE, "gpu", "suppressed", [], NOW)
        result = status_report(config, NOW, raw, agg)
        self.assertEqual(result["last_accepted_age_s"], 120)
        self.assertEqual(result["ingest_today"], {"accepted": 1})
        self.assertEqual(result["rollup_yesterday"], {f"{RELEASE}/gpu": "suppressed"})
        self.assertEqual(result["releases"], [RELEASE])
        json.dumps(result)  # serializable for the CLI
        late = status_report(config, NOW + RAW_TTL, raw, agg)
        self.assertFalse(late["retention_ok"])

    def test_check_release(self):
        config = make_config(self.dir)
        self.assertEqual(check_release_tag(config, RELEASE, FIXTURE), (True, "accepted"))
        self.assertFalse(check_release_tag(config, "v0.3.0", FIXTURE)[0])
        self.assertFalse(check_release_tag(config, "0.2.7", FIXTURE)[0])
        self.assertFalse(check_release_tag(make_config(self.dir, suspended_releases=frozenset({RELEASE})),
                                           RELEASE, FIXTURE)[0])
        self.assertFalse(check_release_tag(make_config(self.dir, releases=frozenset()), RELEASE, FIXTURE)[0])
        # Default location: beside the configured schema directory.
        self.assertEqual(check_release_tag(config, RELEASE), (True, "accepted"))


if __name__ == "__main__":
    unittest.main()
