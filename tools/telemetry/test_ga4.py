"""GA4 website collector against a fake Data/Admin API (no network, no Google account).

    python -m unittest tools/telemetry/test_ga4.py      (from the repository root; standard library only)
"""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import ga4  # noqa: E402

NOW = 1800000000.0  # 2027-01-15T08:00:00Z
PROPERTY = "123456789"


def ga_date(day):
    return day.replace("-", "")


class FakeGA:
    """Answers the requests ga4.collect makes; records every call."""

    def __init__(self, dimensions=("customEvent:download_platform",), fail=None, streams=None, zone="Etc/UTC"):
        self.calls, self.dimensions, self.fail, self.zone = [], set(dimensions), fail or set(), zone
        self.ranges = []
        self.streams = streams or {"properties/111": "G-OTHER", f"properties/{PROPERTY}": ga4.MEASUREMENT_ID}

    def __call__(self, method, url, token=None, body=None, form=None, headers=None):
        self.calls.append({"method": method, "url": url, "token": token, "body": body, "form": form,
                           "headers": headers or {}})
        if url.endswith("/token"):
            return {"access_token": "tok", "expires_in": 3599}
        if "accountSummaries" in url:
            if "pageToken" not in url:
                return {"accountSummaries": [{"propertySummaries": [{"property": "properties/111"}]}],
                        "nextPageToken": "p2"}
            return {"accountSummaries": [{"propertySummaries": [{"property": f"properties/{PROPERTY}"}]}]}
        if url.endswith("/dataStreams?pageSize=200"):
            name = url.split(ga4.ADMIN_API + "/", 1)[1].rsplit("/dataStreams", 1)[0]
            if self.streams[name] is None:
                raise ga4.GA4Error("HTTP 403: no access to this property")
            return {"dataStreams": [{"webStreamData": {"measurementId": self.streams[name]}}]}
        if url.endswith("/metadata"):
            if "metadata" in self.fail:
                raise ga4.GA4Error("HTTP 403: metadata denied")
            return {"dimensions": [{"apiName": n} for n in ["date", "country", *self.dimensions]]}
        if url.endswith(":runRealtimeReport"):
            return {"rows": [{"metricValues": [{"value": "3"}]}]}
        assert url.endswith(f"properties/{PROPERTY}:runReport"), url
        if "probe" in self.fail:
            raise ValueError("unexpected shape")
        if not body.get("dimensions"):  # the time-zone probe
            return {"rows": [{"metricValues": [{"value": "2"}]}], "metadata": {"timeZone": self.zone}}
        self.ranges.append(body["dateRanges"])
        dims = [d["name"] for d in body["dimensions"]]
        event = ((body.get("dimensionFilter") or {}).get("filter") or {}).get("stringFilter", {}).get("value")
        key = (tuple(dims), event)
        if key in self.fail or dims[0] in self.fail:
            raise ga4.GA4Error("HTTP 400: report refused")
        metrics = [m["name"] for m in body["metrics"]]
        if key == (("date",), None):
            rows = [(["20270114"], ["40", "30", "55", "120", "33"]), (["20270115"], ["12", "9", "14", "31", "8"])]
            totals = ["50", "39", "69", "151", "41"]
        elif key == (("date",), "download_request"):
            rows, totals = [(["20270110"], ["4"]), (["20270115"], ["2"])], ["6"]
        elif dims == ["country"]:
            rows = [(["Spain"], ["20", "25"][:len(metrics)]), (["<b>evil</b>"], ["1", "1"][:len(metrics)])]
            totals = None
        elif dims == ["pagePath"]:
            rows, totals = [(["/OpenRCsimulator/ja.html"], ["30", "11"])], None
        elif dims == ["customEvent:download_platform"]:
            rows, totals = [(["windows"], ["5"]), (["macos"], ["1"])], None
        else:
            rows, totals = [], None
        reply = {"rows": [{"dimensionValues": [{"value": v} for v in d], "metricValues": [{"value": v} for v in m]}
                          for d, m in rows], "metadata": {"timeZone": self.zone}}
        if totals:
            reply["totals"] = [{"dimensionValues": [{"value": "RESERVED_TOTAL"}],
                                "metricValues": [{"value": v} for v in totals]}]
        return reply


def model(**kwargs):
    return ga4.collect(PROPERTY, "tok", {}, days=7, now=NOW, http=FakeGA(**kwargs))


class GA4Case(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.dict(os.environ, {}, clear=False)
        patcher.start()
        self.addCleanup(patcher.stop)
        for name in ("OPENRC_GA4_ACCESS_TOKEN", "OPENRC_GA4_CREDENTIALS", "GOOGLE_APPLICATION_CREDENTIALS",
                     "OPENRC_GA4_PROPERTY", "OPENRC_GA4_QUOTA_PROJECT"):
            os.environ.pop(name, None)
        self._tmp = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def test_collect_builds_the_model(self):
        m = model()
        json.dumps(m)
        self.assertEqual(m["days"], [f"2027-01-{d:02d}" for d in range(9, 16)])  # property today 2027-01-15
        self.assertEqual(m["totals"], {"users": 50, "new_users": 39, "sessions": 69, "views": 151, "engaged": 41})
        self.assertEqual(m["daily"][-1]["users"], 12)
        self.assertEqual(m["daily"][0]["users"], 0)  # days without a row are zero, not missing
        self.assertEqual(m["downloads_total"], 6)
        self.assertEqual(ga4.window(m, 7), 6)
        self.assertEqual(ga4.window(m, 3), 2)
        self.assertEqual(m["realtime_users"], 3)
        self.assertEqual(m["tables"]["download_platforms"][0], {"dims": ["windows"], "values": {"eventCount": 5}})
        self.assertEqual(m["missing"]["download_sources"], ["customEvent:download_source"])
        self.assertIn("vitals", m["missing"])
        self.assertEqual(m["errors"], {})
        self.assertEqual(m["time_zone"], "Etc/UTC")

    def test_report_body_window_and_filter(self):
        body = ga4.report_body(["2027-01-01", "2027-01-02"], ["date"], ["eventCount"], event="download_request",
                               order="eventCount", limit=15)
        self.assertEqual(body["dateRanges"], [{"startDate": "2027-01-01", "endDate": "2027-01-02"}])
        self.assertEqual(body["dimensionFilter"]["filter"]["stringFilter"]["value"], "download_request")
        self.assertEqual(body["limit"], "15")

    def test_every_report_uses_the_property_day_window(self):
        try:
            from zoneinfo import ZoneInfo
            ZoneInfo("America/Los_Angeles")
        except Exception:  # noqa: BLE001
            self.skipTest("no IANA time zone data (pip install tzdata)")
        fake = FakeGA(zone="America/Los_Angeles")
        m = ga4.collect(PROPERTY, "tok", {}, days=7, now=NOW - 3 * 3600, http=fake)  # 05:00 UTC = 21:00 PST, 14th
        self.assertEqual((m["days"][0], m["days"][-1]), ("2027-01-08", "2027-01-14"))
        self.assertFalse(m["zone_fallback"])
        self.assertTrue(fake.ranges)
        self.assertTrue(all(r == [{"startDate": "2027-01-08", "endDate": "2027-01-14"}] for r in fake.ranges))
        self.assertEqual(ga4.collect(PROPERTY, "tok", {}, days=7, now=NOW, http=FakeGA(zone="Asia/Tokyo"))
                         ["days"][-1], "2027-01-15")  # 17:00 JST

    def test_unloadable_zone_falls_back_to_utc_and_says_so(self):
        m = ga4.collect(PROPERTY, "tok", {}, days=7, now=NOW, http=FakeGA(zone="Not/AZone"))
        self.assertTrue(m["zone_fallback"])
        self.assertEqual(m["days"][-1], "2027-01-15")

    def test_failed_downloads_report_is_not_zero(self):
        m = model(fail={(("date",), "download_request")})
        self.assertIn("downloads", m["errors"])
        self.assertIsNone(m["downloads_total"])

    def test_unexpected_error_is_contained(self):
        os.environ["OPENRC_GA4_ACCESS_TOKEN"] = "ready"
        result = ga4.fetch(7, PROPERTY, now=NOW, http=FakeGA(fail={"probe"}))
        self.assertIn("unexpected ValueError", result["error"])

    def test_explicit_credentials_beat_an_environment_token(self):
        os.environ["OPENRC_GA4_ACCESS_TOKEN"] = "stale"
        path = self.dir / "adc.json"
        path.write_text(json.dumps({"type": "authorized_user", "client_id": "c", "client_secret": "s",
                                    "refresh_token": "r"}), encoding="utf-8")
        self.assertEqual(ga4.access_token(path, http=FakeGA()), ("tok", {}))
        self.assertEqual(ga4.access_token(None, http=FakeGA()), ("stale", {}))

    def test_discovery_skips_properties_it_cannot_inspect(self):
        os.environ["OPENRC_GA4_ACCESS_TOKEN"] = "ready"
        fake = FakeGA(streams={"properties/111": None, f"properties/{PROPERTY}": ga4.MEASUREMENT_ID})
        with mock.patch("sys.stderr"):
            self.assertEqual(ga4.fetch(7, None, now=NOW, http=fake)["property"], PROPERTY)

    def test_one_failed_report_keeps_the_rest(self):
        m = model(fail={"country", "metadata"})
        self.assertIn("countries", m["errors"])
        self.assertIn("metadata", m["errors"])
        self.assertIn("pages", m["tables"])
        # Without metadata every report is attempted; unregistered dimensions then fail individually.
        self.assertEqual(m["missing"], {})

    def test_daily_overview_failure_is_a_collection_error(self):
        os.environ["OPENRC_GA4_ACCESS_TOKEN"] = "ready"
        fake = FakeGA(fail={(("date",), None)})
        result = ga4.fetch(7, PROPERTY, now=NOW, http=fake)
        self.assertEqual(result["error"], "HTTP 400: report refused")
        self.assertEqual(fake.calls[0]["token"], "ready")

    def test_not_configured_returns_none(self):
        self.assertFalse(ga4.configured())
        self.assertIsNone(ga4.fetch(7, PROPERTY, now=NOW, http=FakeGA()))

    def test_property_is_discovered_from_the_measurement_id(self):
        os.environ["OPENRC_GA4_ACCESS_TOKEN"] = "ready"
        with mock.patch("sys.stderr"):
            result = ga4.fetch(7, None, now=NOW, http=FakeGA())
        self.assertEqual(result["property"], PROPERTY)
        missing = FakeGA(streams={"properties/111": "G-OTHER", f"properties/{PROPERTY}": "G-NOPE"})
        self.assertIn("no accessible GA4 property", ga4.fetch(7, None, now=NOW, http=missing)["error"])

    def test_property_must_be_numeric(self):
        os.environ["OPENRC_GA4_ACCESS_TOKEN"] = "ready"
        self.assertIn("numeric", ga4.fetch(7, "G-4Z11DSB2BV", now=NOW, http=FakeGA())["error"])
        self.assertEqual(ga4.fetch(7, f"properties/{PROPERTY}", now=NOW, http=FakeGA())["property"], PROPERTY)

    def test_authorized_user_refresh_and_quota_project(self):
        path = self.dir / "adc.json"
        path.write_text(json.dumps({"type": "authorized_user", "client_id": "cid", "client_secret": "sec",
                                    "refresh_token": "ref", "quota_project_id": "proj"}), encoding="utf-8")
        fake = FakeGA()
        token, headers = ga4.access_token(path, http=fake)
        self.assertEqual((token, headers), ("tok", {"x-goog-user-project": "proj"}))
        self.assertEqual(fake.calls[0]["form"]["grant_type"], "refresh_token")
        self.assertEqual(fake.calls[0]["url"], ga4.TOKEN_URI)

    def test_credentials_inside_the_repository_are_refused(self):
        with self.assertRaisesRegex(ga4.GA4Error, "outside the repository"):
            ga4.access_token(ga4.REPO / "ga4-key.json", http=FakeGA())

    def test_unknown_credential_type(self):
        path = self.dir / "x.json"
        path.write_text('{"type": "external_account"}', encoding="utf-8")
        with self.assertRaisesRegex(ga4.GA4Error, "unsupported credential type"):
            ga4.access_token(path, http=FakeGA())

    def test_service_account_assertion_is_a_valid_rs256_jwt(self):
        try:
            from cryptography.hazmat.primitives import hashes, serialization
            from cryptography.hazmat.primitives.asymmetric import padding, rsa
        except ImportError:
            self.skipTest("cryptography not installed")
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                serialization.NoEncryption()).decode()
        path = self.dir / "sa.json"
        path.write_text(json.dumps({"type": "service_account", "client_email": "sa@p.iam.gserviceaccount.com",
                                    "private_key": pem, "private_key_id": "kid1",
                                    "token_uri": "https://oauth2.googleapis.com/token"}), encoding="utf-8")
        fake = FakeGA()
        self.assertEqual(ga4.access_token(path, http=fake, now=NOW), ("tok", {}))
        assertion = fake.calls[0]["form"]["assertion"]
        head, claims, signature = assertion.split(".")
        pad = lambda s: base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))  # noqa: E731
        self.assertEqual(json.loads(pad(head)), {"alg": "RS256", "typ": "JWT", "kid": "kid1"})
        body = json.loads(pad(claims))
        self.assertEqual((body["scope"], body["iat"], body["exp"]), (ga4.SCOPE, int(NOW), int(NOW) + 3600))
        key.public_key().verify(pad(signature), f"{head}.{claims}".encode(), padding.PKCS1v15(), hashes.SHA256())


if __name__ == "__main__":
    unittest.main()
