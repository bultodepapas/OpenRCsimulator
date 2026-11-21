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

    def __init__(self, dimensions=("customEvent:download_platform",), fail=None, streams=None, zone="Etc/UTC",
                 quality=None, conversion_totals=("6", "4"), source_requests="9"):
        self.calls, self.dimensions, self.fail, self.zone = [], set(dimensions), fail or set(), zone
        self.ranges, self.filters = [], []
        self.streams = streams or {"properties/111": "G-OTHER", f"properties/{PROPERTY}": ga4.MEASUREMENT_ID}
        self.quality, self.conversion_totals, self.source_requests = quality or {}, conversion_totals, source_requests

    def __call__(self, method, url, token=None, body=None, form=None, headers=None):
        self.calls.append({"method": method, "url": url, "token": token, "body": body, "form": form,
                           "headers": headers or {}})
        if url.endswith("/token"):
            return {"access_token": "tok", "expires_in": 3599, **({"refresh_token": "rt"} if form and
                                                                   form.get("grant_type") == "authorization_code"
                                                                   else {})}
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
        if url.endswith("/dataRetentionSettings"):
            return {"eventDataRetention": "TWO_MONTHS"}
        if url.endswith("/keyEvents"):
            return {"keyEvents": [{"eventName": "purchase"}]}
        assert url.endswith(f"properties/{PROPERTY}:runReport"), url
        if "probe" in self.fail:
            raise ValueError("unexpected shape")
        if "dimensionFilter" not in body:  # the time-zone probe
            return {"rows": [{"metricValues": [{"value": "2"}]}], "metadata": {"timeZone": self.zone}}
        self.ranges.append(body["dateRanges"])
        self.filters.append(body["dimensionFilter"])
        dims = [d["name"] for d in body["dimensions"]]
        found = body["dimensionFilter"].get("andGroup", {}).get("expressions") or [body["dimensionFilter"]]
        values = {f["filter"]["fieldName"]: f["filter"]["stringFilter"]["value"]
                  for f in found if "stringFilter" in f["filter"]}
        event = values.get("eventName")
        key = (tuple(dims), event)
        if key in self.fail or (dims and dims[0] in self.fail):
            raise ga4.GA4Error("HTTP 400: report refused")
        metrics = [m["name"] for m in body["metrics"]]
        if key == ((), None):
            rows, totals = [([], ["50", "39", "69", "151", "41", "52"])], None
        elif key == (("date",), None):
            rows = [(["20270114"], ["40", "30", "55", "120", "33"]), (["20270115"], ["12", "9", "14", "31", "8"])]
            totals = None
        elif key == (("date",), "download_request"):
            rows, totals = [(["20270110"], ["4"]), (["20270115"], ["2"])], None
        elif key == ((), "download_request"):
            rows, totals = [([], self.conversion_totals)], None
        elif key == ((), "download_handoff"):
            rows, totals = [([], ["7"])], None
        elif key == (("sessionSource",), None):
            rows, totals = [(["github"], ["10"]), (["reddit.com"], ["20"])], None
        elif key == (("sessionSource",), "download_request"):
            rows, totals = [(["github"], [self.source_requests])], None
        elif dims == ["country"]:
            rows = [(["Spain"], ["20", "25"][:len(metrics)]), (["<b>evil</b>"], ["1", "1"][:len(metrics)])]
            totals = None
        elif dims == ["pagePath"]:
            rows, totals = [(["/OpenRCsimulator/ja.html"], ["30", "11"])], None
        elif dims == ["customEvent:download_platform"]:
            rows, totals = [(["windows"], ["5"]), (["macos"], ["1"])], None
        elif dims == ["customEvent:download_method"]:
            rows, totals = [(["automatic"], ["4"]), (["manual"], ["2"])], None
        elif dims == ["customEvent:handoff_action"]:
            rows, totals = [(["shown"], ["5"]), (["shared"], ["1"]), (["copied"], ["1"])], None
        else:
            rows, totals = [], None
        reply = {"rows": [{"dimensionValues": [{"value": v} for v in d], "metricValues": [{"value": v} for v in m]}
                          for d, m in rows], "metadata": {"timeZone": self.zone, **self.quality.get(key, {})}}
        if totals:
            reply["totals"] = [{"dimensionValues": [{"value": "RESERVED_TOTAL"}],
                                "metricValues": [{"value": v} for v in totals]}]
        return reply


def model(**kwargs):
    return ga4.collect(PROPERTY, "tok", {}, days=7, now=NOW, http=FakeGA(**kwargs))


class GA4Case(unittest.TestCase):
    def test_fetch_enforces_a_global_collection_budget(self):
        http = mock.Mock()
        with mock.patch.object(ga4, "configured", return_value=True), mock.patch.object(
                ga4, "access_token", return_value=("fixture-token", {})), mock.patch.object(
                ga4.time, "monotonic", side_effect=[0, ga4.COLLECTION_BUDGET_S + 1]):
            result = ga4.fetch(property_id=PROPERTY, now=NOW, http=http)
        self.assertIn("time budget exhausted", result["error"])
        http.assert_not_called()

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
        self.assertEqual(m["daily"][0]["users"], 0)
        self.assertIsNone(m["daily"][-3]["users"])  # an unpublished provisional day
        self.assertEqual(m["downloads_total"], 6)
        self.assertIsNone(ga4.window(m, 7))  # some dates are provisional and unavailable
        self.assertEqual(ga4.window(m, 1), 2)
        self.assertEqual(m["provisional_days"], ["2027-01-13", "2027-01-14", "2027-01-15"])
        self.assertEqual(m["comparison_through"], "2027-01-12")
        self.assertEqual(m["realtime_users"], 3)
        self.assertEqual(m["tables"]["download_platforms"][0], {"dims": ["windows"], "values": {"eventCount": 5}})
        self.assertEqual(m["missing"]["download_sources"], ["customEvent:download_source"])
        self.assertIn("vitals", m["missing"])
        self.assertEqual(m["errors"], {})
        self.assertEqual(m["time_zone"], "Etc/UTC")

    def test_production_host_filter_funnels_and_setup(self):
        fake = FakeGA()
        m = ga4.collect(PROPERTY, "tok", {}, days=7, now=NOW, http=fake)
        self.assertTrue(fake.filters)
        for expression in fake.filters:  # every report is restricted to the published site
            found = expression.get("andGroup", {}).get("expressions") or [expression]
            self.assertIn({"filter": {"fieldName": "hostName", "stringFilter": {
                "matchType": "EXACT", "value": "bultodepapas.github.io"}}}, found)
        self.assertEqual((m["downloads_users"], m["handoffs"]), (4, 7))
        self.assertEqual(m["conversion_users"], 52)
        self.assertEqual(m["funnels"]["source"], [{"name": "github", "users": 10, "requesting": 9},
                                                  {"name": "reddit.com", "users": 20, "requesting": 0}])
        self.assertEqual(m["setup"]["retention"], "TWO_MONTHS")
        self.assertEqual(m["setup"]["key_events"], ["purchase"])
        self.assertEqual(m["setup"]["dimensions"]["download_platform"], True)
        self.assertEqual(m["setup"]["dimensions"]["release_version"], False)
        self.assertEqual(m["missing"]["download_releases"], ["customEvent:release_version"])
        self.assertEqual(m["missing"]["download_methods"], ["customEvent:download_method"])
        self.assertEqual(m["missing"]["handoff_actions"], ["customEvent:handoff_action"])
        reports = [call["body"] for call in fake.calls if call["url"].endswith(":runReport")]
        sources = [report for report in reports if report.get("dimensions") == [{"name": "sessionSource"}]]
        self.assertEqual([report["metrics"] for report in sources], [[{"name": "totalUsers"}]] * 2)
        self.assertEqual(sources[1]["dimensionFilter"]["andGroup"]["expressions"][-1],
                         {"filter": {"fieldName": "sessionSource",
                                     "inListFilter": {"values": ["github", "reddit.com"], "caseSensitive": True}}})
        totals = [report for report in reports
                  if report.get("dimensions") == [] and {"name": "totalUsers"} in report["metrics"]]
        self.assertEqual(len(totals), 2)
        self.assertTrue(all("metricAggregations" not in report for report in totals))

    def test_report_quality_preserves_unknown_days_and_conversions(self):
        m = model(quality={
            (("date",), None): {"subjectToThresholding": True},
            (("date",), "download_request"): {"samplingMetadatas": [{"samplesReadCount": "100"}]},
            ((), "download_request"): {"dataLossFromOtherRow": True},
            (("sessionSource",), "download_request"): {"dataTruncationReasons": [{"reason": "example"}]},
        })
        self.assertEqual(m["report_quality"],
                         {"daily": ["thresholding"], "downloads": ["sampled"],
                          "download_totals": ["other_row"], "funnel_source": ["truncated"]})
        self.assertIsNone(m["daily"][0]["users"])
        self.assertIsNone(m["downloads_daily"][0]["count"])
        self.assertEqual(m["downloads_daily"][1]["count"], 4)
        self.assertEqual(m["downloads_total"], 6)   # reported, but coverage is limited
        self.assertIsNone(m["downloads_users"])     # do not derive a percentage from this total
        self.assertTrue(all(row["requesting"] is None for row in m["funnels"]["source"]))

    def test_conversion_inconsistent_totals_are_unavailable(self):
        m = model(conversion_totals=("60", "55"), source_requests="11")
        self.assertIsNone(m["downloads_users"])
        self.assertIsNone(m["funnels"]["source"][0]["requesting"])
        self.assertIn("inconsistent_totals", m["report_quality"]["conversion"])
        self.assertIn("inconsistent_totals", m["report_quality"]["funnel_source"])

    def test_invalid_metric_never_becomes_zero_or_nonstandard_json(self):
        self.assertEqual(ga4.number("9007199254740993"), 9007199254740993)
        for value in ("NaN", "unknown", None):
            with self.subTest(value=value), self.assertRaises(ga4.GA4Error):
                ga4.number(value)
        model_with_failure = model(conversion_totals=("NaN", "4"))
        self.assertIn("download_totals", model_with_failure["errors"])
        self.assertIsNone(model_with_failure["downloads_total"])
        self.assertEqual(model_with_failure["downloads_daily"][1]["count"], 4)

    def test_registered_dimensions_split_requests_and_handoffs(self):
        m = model(dimensions=["customEvent:download_method", "customEvent:handoff_action"])
        for key, expected in (("download_methods", [("automatic", 4), ("manual", 2)]),
                              ("handoff_actions", [("shown", 5), ("shared", 1), ("copied", 1)])):
            self.assertEqual([(row["dims"][0], row["values"]["eventCount"]) for row in m["tables"][key]], expected)

    def test_expired_login_says_how_to_fix_it(self):
        path = self.dir / "user.json"
        path.write_text(json.dumps({"type": "authorized_user", "client_id": "c", "client_secret": "s",
                                    "refresh_token": "r"}), encoding="utf-8")

        def refused(*_args, **_kwargs):
            raise ga4.GA4Error("HTTP 400: Token has been expired or revoked.")
        with self.assertRaisesRegex(ga4.GA4Error, "ga4.py login"):
            ga4.access_token(path, http=refused)

    def test_report_body_window_and_filter(self):
        body = ga4.report_body(["2027-01-01", "2027-01-02"], ["date"], ["eventCount"], event="download_request",
                               order="eventCount", limit=15)
        self.assertEqual(body["dateRanges"], [{"startDate": "2027-01-01", "endDate": "2027-01-02"}])
        self.assertEqual(body["dimensionFilter"]["andGroup"]["expressions"][1]["filter"]["stringFilter"]["value"],
                         "download_request")
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
        self.assertEqual(m["comparison_through"], "2027-01-11")
        self.assertFalse(m["zone_fallback"])
        self.assertTrue(fake.ranges)
        self.assertTrue(all(r == [{"startDate": "2027-01-08", "endDate": "2027-01-14"}] for r in fake.ranges))
        self.assertEqual(ga4.collect(PROPERTY, "tok", {}, days=7, now=NOW, http=FakeGA(zone="Asia/Tokyo"))
                         ["days"][-1], "2027-01-15")  # 17:00 JST

    def test_unloadable_zone_falls_back_to_utc_and_says_so(self):
        m = ga4.collect(PROPERTY, "tok", {}, days=7, now=NOW, http=FakeGA(zone="Not/AZone"))
        self.assertTrue(m["zone_fallback"])
        self.assertEqual(m["days"][-1], "2027-01-15")
        self.assertIsNone(m["comparison_through"])

    def test_failed_downloads_report_is_not_zero(self):
        m = model(fail={(("date",), "download_request")})
        self.assertIn("downloads", m["errors"])
        self.assertEqual(m["downloads_daily"], [])
        self.assertEqual(m["downloads_total"], 6)
        m = model(fail={((), "download_request")})
        self.assertIn("download_totals", m["errors"])
        self.assertIsNone(m["downloads_total"])
        self.assertEqual(m["downloads_daily"][1]["count"], 4)

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

    def test_login_refuses_bad_client_files_and_redirects(self):
        bad = self.dir / "bad.json"
        bad.write_text('{"type": "service_account"}', encoding="utf-8")
        with self.assertRaisesRegex(ga4.GA4Error, "not an OAuth client file"):
            ga4.login(bad, self.dir / "out.json", "http://localhost:8085/")
        good = self.dir / "client.json"
        good.write_text('{"web": {"client_id": "c", "client_secret": "s"}}', encoding="utf-8")
        for uri in ("https://example.com/", "http://localhost/"):
            with self.assertRaisesRegex(ga4.GA4Error, "loopback"):
                ga4.login(good, self.dir / "out.json", uri)

    def test_login_writes_an_authorized_user_file(self):
        import threading
        import urllib.request as request
        client = self.dir / "client.json"
        client.write_text('{"installed": {"client_id": "cid", "client_secret": "sec"}}', encoding="utf-8")
        fake, out, opened = FakeGA(), self.dir / "user.json", []

        def browser(url):  # the "user" consents: follow the redirect with the code and the same state
            query = dict(ga4.urllib.parse.parse_qsl(ga4.urllib.parse.urlsplit(url).query))
            opened.append(query)
            back = f"{query['redirect_uri']}?state={query['state']}&code=abc"
            threading.Timer(0.2, lambda: request.urlopen(back, timeout=5).read()).start()
            return True

        with mock.patch("webbrowser.open", browser), mock.patch("sys.stdout"):
            ga4.login(client, out, "http://localhost:18765/", timeout_s=20, http=fake)
        self.assertEqual(opened[0]["scope"], ga4.SCOPE)
        self.assertEqual(opened[0]["code_challenge_method"], "S256")
        exchange = fake.calls[-1]["form"]
        self.assertEqual((exchange["grant_type"], exchange["code"]), ("authorization_code", "abc"))
        self.assertTrue(exchange["code_verifier"])
        self.assertEqual(json.loads(out.read_text(encoding="utf-8"))["type"], "authorized_user")

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
