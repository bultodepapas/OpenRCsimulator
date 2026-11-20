"""Website statistics for the operator dashboard, read from the Google Analytics 4 Data API (read-only).

The public site sends page views, `download_request` and sampled `web_vital` events to GA4 measurement ID
G-4Z11DSB2BV (site/README.md). This module reads aggregate reports for that property with the
`analytics.readonly` scope and returns a JSON-serialisable model for `dashboard.py`. It writes nothing to Google.

Credentials (first found wins):
  --ga4-credentials                  explicit credential file (below)
  OPENRC_GA4_ACCESS_TOKEN            a ready OAuth access token (expires after about an hour)
  OPENRC_GA4_CREDENTIALS / GOOGLE_APPLICATION_CREDENTIALS:
      a service-account key ("service_account"; signing needs the `cryptography` package) or an
      application-default user login ("authorized_user"; standard library only).
The property is --ga4-property / OPENRC_GA4_PROPERTY (numeric ID); without it the Admin API is searched for the
web stream with the site's measurement ID. Everything else is standard library.
"""
from __future__ import annotations

import base64
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO = Path(__file__).resolve().parents[2]
MEASUREMENT_ID = "G-4Z11DSB2BV"
SCOPE = "https://www.googleapis.com/auth/analytics.readonly"
DATA_API = "https://analyticsdata.googleapis.com/v1beta"
ADMIN_API = "https://analyticsadmin.googleapis.com/v1beta"
TOKEN_URI = "https://oauth2.googleapis.com/token"
TIMEOUT_S = 30
TOP = 15

# Daily overview metrics: model key -> GA4 API name.
DAILY = (("users", "activeUsers"), ("new_users", "newUsers"), ("sessions", "sessions"),
         ("views", "screenPageViews"), ("engaged", "engagedSessions"))


class GA4Error(Exception):
    pass


# ---------------------------------------------------------------------------------------------- HTTP and auth


def http_json(method, url, token=None, body=None, form=None, headers=None):
    """One HTTPS request; returns parsed JSON or raises GA4Error with Google's error message."""
    data, head = None, {"Accept": "application/json", **(headers or {})}
    if token:
        head["Authorization"] = f"Bearer {token}"
    if body is not None:
        data, head["Content-Type"] = json.dumps(body).encode("utf-8"), "application/json"
    elif form is not None:
        data = urllib.parse.urlencode(form).encode("ascii")
        head["Content-Type"] = "application/x-www-form-urlencoded"
    request = urllib.request.Request(url, data=data, headers=head, method=method)
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise GA4Error(f"HTTP {error.code}: {error_message(error)}") from None
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise GA4Error(f"network error: {getattr(error, 'reason', error)}") from None
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise GA4Error("response is not JSON") from None


def error_message(error):
    try:
        payload = json.loads(error.read().decode("utf-8"))
    except (OSError, ValueError, UnicodeDecodeError):
        return error.reason or "error"
    inner = payload.get("error")
    if isinstance(inner, dict):
        return str(inner.get("message") or inner.get("status") or "error")[:300]
    return str(payload.get("error_description") or inner or "error")[:300]


def credentials_path(explicit=None):
    """Opt-in only: gcloud's default login file is never picked up implicitly (it rarely has the GA scope)."""
    for candidate in (explicit, os.environ.get("OPENRC_GA4_CREDENTIALS"),
                      os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")):
        if candidate:
            return Path(candidate).expanduser()
    return None


def configured(explicit_credentials=None):
    """True when some credential source exists (the tab otherwise shows the setup steps)."""
    return bool(os.environ.get("OPENRC_GA4_ACCESS_TOKEN") or credentials_path(explicit_credentials))


def b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def service_account_assertion(info, now):
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding
    except ImportError:
        raise GA4Error("a service-account key needs the 'cryptography' package (pip install cryptography), "
                       "or use an authorized_user login / OPENRC_GA4_ACCESS_TOKEN") from None
    header = {"alg": "RS256", "typ": "JWT"}
    if info.get("private_key_id"):
        header["kid"] = info["private_key_id"]
    claims = {"iss": info["client_email"], "scope": SCOPE, "aud": info.get("token_uri") or TOKEN_URI,
              "iat": int(now), "exp": int(now) + 3600}
    signing_input = (b64url(json.dumps(header, separators=(",", ":")).encode()) + "."
                     + b64url(json.dumps(claims, separators=(",", ":")).encode()))
    try:
        key = serialization.load_pem_private_key(info["private_key"].encode("utf-8"), password=None)
        signature = key.sign(signing_input.encode("ascii"), padding.PKCS1v15(), hashes.SHA256())
    except (ValueError, TypeError) as error:
        raise GA4Error(f"service-account private key unusable: {error}") from None
    return signing_input + "." + b64url(signature)


def access_token(path=None, http=http_json, now=None):
    """(token, extra request headers). Reads only the credential file; never writes or caches tokens."""
    ready = os.environ.get("OPENRC_GA4_ACCESS_TOKEN")
    if ready and not path:  # an explicit --ga4-credentials wins over a token left in the environment
        return ready.strip(), {}
    path = credentials_path(path)
    if path is None:
        raise GA4Error("no GA4 credentials configured")
    if Path(path).resolve().is_relative_to(REPO):
        raise GA4Error("keep the GA4 credential file outside the repository (it is a secret)")
    try:
        info = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise GA4Error(f"credential file unreadable ({path.name}): {error.__class__.__name__}") from None
    kind = info.get("type")
    try:
        if kind == "service_account":
            reply = http("POST", info.get("token_uri") or TOKEN_URI, form={
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": service_account_assertion(info, time.time() if now is None else now)})
            headers = {}
        elif kind == "authorized_user":
            reply = http("POST", info.get("token_uri") or TOKEN_URI, form={
                "grant_type": "refresh_token", "client_id": info["client_id"],
                "client_secret": info["client_secret"], "refresh_token": info["refresh_token"]})
            # User logins bill API quota to a project; gcloud records it as quota_project_id.
            project = info.get("quota_project_id") or os.environ.get("OPENRC_GA4_QUOTA_PROJECT")
            headers = {"x-goog-user-project": project} if project else {}
        else:
            raise GA4Error(f"unsupported credential type {kind!r} (service_account or authorized_user)")
    except KeyError as error:
        raise GA4Error(f"credential file lacks {error.args[0]!r}") from None
    token = reply.get("access_token")
    if not token:
        raise GA4Error("token endpoint returned no access_token")
    return token, headers


# ---------------------------------------------------------------------------------------------- reports


def discover_property(token, headers, measurement_id=MEASUREMENT_ID, http=http_json):
    """Numeric property ID whose web stream has `measurement_id` (needs the Admin API enabled)."""
    url = f"{ADMIN_API}/accountSummaries?pageSize=200"
    properties = []
    while url:
        page = http("GET", url, token, headers=headers)
        for account in page.get("accountSummaries") or []:
            properties += [p["property"] for p in account.get("propertySummaries") or []]
        next_token = page.get("nextPageToken")
        url = f"{ADMIN_API}/accountSummaries?pageSize=200&pageToken={urllib.parse.quote(next_token)}" \
            if next_token else None
    for name in properties:
        try:
            streams = http("GET", f"{ADMIN_API}/{name}/dataStreams?pageSize=200", token, headers=headers)
        except GA4Error:
            continue  # an unrelated property the credential cannot inspect
        for stream in streams.get("dataStreams") or []:
            if (stream.get("webStreamData") or {}).get("measurementId") == measurement_id:
                return name.split("/", 1)[1]
    raise GA4Error(f"no accessible GA4 property has web stream {measurement_id} "
                   f"({len(properties)} properties visible); set OPENRC_GA4_PROPERTY")


def event_filter(name):
    return {"filter": {"fieldName": "eventName", "stringFilter": {"matchType": "EXACT", "value": name}}}


def report_body(axis, dimensions, metrics, event=None, order=None, limit=None, totals=False):
    """axis: the ISO days of the window, oldest first; explicit dates keep every report on the same days."""
    body = {"dateRanges": [{"startDate": axis[0], "endDate": axis[-1]}],
            "dimensions": [{"name": d} for d in dimensions], "metrics": [{"name": m} for m in metrics]}
    if event:
        body["dimensionFilter"] = event_filter(event)
    if order:
        body["orderBys"] = [{"metric": {"metricName": order}, "desc": True}]
    if limit:
        body["limit"] = str(limit)
    if totals:
        body["metricAggregations"] = ["TOTAL"]
    return body


def number(text):
    try:
        value = float(text)
    except (TypeError, ValueError):
        return 0
    return int(value) if value.is_integer() else value


def parse_report(reply, metrics):
    rows = [{"dims": [d.get("value", "") for d in row.get("dimensionValues") or []],
             "values": {m: number(v.get("value")) for m, v in zip(metrics, row.get("metricValues") or [])}}
            for row in reply.get("rows") or []]
    totals = None
    for total in reply.get("totals") or []:
        totals = {m: number(v.get("value")) for m, v in zip(metrics, total.get("metricValues") or [])}
    return rows, totals


def iso_day(ga_date):
    return f"{ga_date[:4]}-{ga_date[4:6]}-{ga_date[6:8]}" if len(ga_date) == 8 and ga_date.isdigit() else None


def property_today(time_zone, now):
    """(today in the property's reporting time zone, True) or (UTC today, False) when the zone cannot be loaded
    (Windows Python without the tzdata package, or an unknown zone)."""
    moment = datetime.fromtimestamp(now, tz=timezone.utc)
    if time_zone:
        try:
            from zoneinfo import ZoneInfo
            return moment.astimezone(ZoneInfo(time_zone)).date(), True
        except Exception:  # noqa: BLE001 - missing tzdata or an unknown zone: fall back to UTC
            pass
    return moment.date(), False


# (key, dimensions, metrics, event filter, order metric, custom dimensions it needs)
TABLES = (
    ("countries", ["country"], ["activeUsers", "sessions"], None, "activeUsers", ()),
    ("sources", ["sessionSourceMedium"], ["sessions", "activeUsers"], None, "sessions", ()),
    ("pages", ["pagePath"], ["screenPageViews", "activeUsers"], None, "screenPageViews", ()),
    ("devices", ["deviceCategory"], ["activeUsers"], None, "activeUsers", ()),
    ("download_countries", ["country"], ["eventCount"], "download_request", "eventCount", ()),
    ("download_platforms", ["customEvent:download_platform"], ["eventCount"], "download_request", "eventCount",
     ("customEvent:download_platform",)),
    ("download_sources", ["customEvent:download_source"], ["eventCount"], "download_request", "eventCount",
     ("customEvent:download_source",)),
    ("vitals", ["customEvent:metric_name", "customEvent:metric_rating"], ["eventCount"], "web_vital", "eventCount",
     ("customEvent:metric_name", "customEvent:metric_rating")),
)


def collect(property_id, token, headers=None, days=30, now=None, http=http_json):
    """Aggregate website reports for the last `days` days. The daily overview must succeed (it proves access);
    the other reports record their own error and leave the rest of the model usable."""
    now = time.time() if now is None else now
    headers = headers or {}
    base = f"{DATA_API}/properties/{property_id}"
    run = lambda body: http("POST", f"{base}:runReport", token, body=body, headers=headers)  # noqa: E731
    names = [api for _, api in DAILY]
    # A minimal report first: its metadata names the property's reporting time zone, which fixes the day window.
    probe = run({"dateRanges": [{"startDate": "today", "endDate": "today"}], "metrics": [{"name": "activeUsers"}]})
    time_zone = (probe.get("metadata") or {}).get("timeZone")
    today, zone_ok = property_today(time_zone, now)
    axis = [(today - timedelta(days=offset)).isoformat() for offset in range(days - 1, -1, -1)]
    rows, totals = parse_report(run(report_body(axis, ["date"], names, totals=True)), names)
    by_day = {iso_day(r["dims"][0]): r["values"] for r in rows}
    model = {
        "property": str(property_id), "measurement_id": MEASUREMENT_ID, "time_zone": time_zone,
        "zone_fallback": not zone_ok,
        "collected_utc": datetime.fromtimestamp(now, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "days": axis,
        "daily": [{"day": d, **{key: (by_day.get(d) or {}).get(api, 0) for key, api in DAILY}} for d in axis],
        "totals": {key: (totals or {}).get(api, 0) for key, api in DAILY},
        "downloads_daily": [], "downloads_total": 0, "realtime_users": None,
        "tables": {}, "missing": {}, "errors": {},
    }
    try:
        dl_rows, dl_totals = parse_report(run(report_body(axis, ["date"], ["eventCount"], event="download_request",
                                                          totals=True)), ["eventCount"])
        dl = {iso_day(r["dims"][0]): r["values"]["eventCount"] for r in dl_rows}
        model["downloads_daily"] = [{"day": d, "count": dl.get(d, 0)} for d in axis]
        model["downloads_total"] = (dl_totals or {}).get("eventCount", sum(dl.values()))
    except GA4Error as error:
        model["errors"]["downloads"] = str(error)
        model["downloads_total"] = None
    try:
        available = {d.get("apiName") for d in http("GET", f"{base}/metadata", token, headers=headers)
                     .get("dimensions") or []}
    except GA4Error as error:
        available, model["errors"]["metadata"] = None, str(error)
    for key, dimensions, metrics, event, order, custom in TABLES:
        absent = [c for c in custom if available is not None and c not in available]
        if absent:
            model["missing"][key] = absent
            continue
        try:
            table, _ = parse_report(run(report_body(axis, dimensions, metrics, event, order,
                                                    50 if key == "vitals" else TOP)), metrics)
            model["tables"][key] = table
        except GA4Error as error:
            model["errors"][key] = str(error)
    try:
        realtime = http("POST", f"{base}:runRealtimeReport", token, body={"metrics": [{"name": "activeUsers"}]},
                        headers=headers)
        model["realtime_users"] = sum(number((r.get("metricValues") or [{}])[0].get("value"))
                                      for r in realtime.get("rows") or [])
    except GA4Error as error:
        model["errors"]["realtime"] = str(error)
    return model


def fetch(days=30, property_id=None, credentials=None, now=None, http=http_json):
    """Full collection for the dashboard: {"error": ...} on failure, None when nothing is configured."""
    if not configured(credentials):
        return None
    stamp = datetime.fromtimestamp(time.time() if now is None else now, tz=timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ")
    try:
        token, headers = access_token(credentials, http=http, now=now)
        property_id = property_id or os.environ.get("OPENRC_GA4_PROPERTY")
        if not property_id:
            property_id = discover_property(token, headers, http=http)
            print(f"GA4 property {property_id} has web stream {MEASUREMENT_ID}; set OPENRC_GA4_PROPERTY="
                  f"{property_id} to skip discovery", file=sys.stderr)
        property_id = str(property_id).removeprefix("properties/")
        if not property_id.isdigit():
            raise GA4Error(f"GA4 property must be the numeric property ID, not {property_id!r}")
        return collect(property_id, token, headers, days, now, http)
    except GA4Error as error:
        return {"error": str(error), "collected_utc": stamp, "property": property_id}
    except Exception as error:  # noqa: BLE001 - the website tab is optional: never lose the rest of the snapshot
        return {"error": f"unexpected {error.__class__.__name__} (rerun with OPENRC_GA4_DEBUG=1 for the traceback)"
                if not os.environ.get("OPENRC_GA4_DEBUG") else repr(error)[:300],
                "collected_utc": stamp, "property": property_id}


def window(model, count):
    """Sum of the newest `count` days of a daily key list, e.g. download requests in 7 days."""
    return sum(r["count"] for r in (model.get("downloads_daily") or [])[-count:])
