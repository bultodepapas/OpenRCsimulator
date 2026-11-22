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
import math
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO = Path(__file__).resolve().parents[2]
MEASUREMENT_ID = "G-4Z11DSB2BV"
PRODUCTION_HOST = "bultodepapas.github.io"
SCOPE = "https://www.googleapis.com/auth/analytics.readonly"
DATA_API = "https://analyticsdata.googleapis.com/v1beta"
ADMIN_API = "https://analyticsadmin.googleapis.com/v1beta"
TOKEN_URI = "https://oauth2.googleapis.com/token"
TIMEOUT_S = 30
COLLECTION_BUDGET_S = 120
TOP = 15
# GA4's daily results can change for 24–48 h during processing. Keep today's data and
# the two preceding property-local days visible, but keep them out of comparisons.
PROVISIONAL_DAYS = 3

# Daily overview metrics: model key -> GA4 API name.
DAILY = (("users", "activeUsers"), ("new_users", "newUsers"), ("sessions", "sessions"),
         ("views", "screenPageViews"), ("engaged", "engagedSessions"))


class GA4Error(Exception):
    pass


# ---------------------------------------------------------------------------------------------- HTTP and auth


def http_json(method, url, token=None, body=None, form=None, headers=None, *, timeout=TIMEOUT_S):
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
        with urllib.request.urlopen(request, timeout=timeout) as response:
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
    except GA4Error as error:
        if "invalid_grant" in str(error) or "expired or revoked" in str(error).lower():
            raise GA4Error("the Google login expired or was revoked: rerun `python tools/telemetry/ga4.py login` "
                           "(a consent screen in Testing mode expires logins after 7 days; publish it)") from None
        raise
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


def exact(field, value):
    return {"filter": {"fieldName": field, "stringFilter": {"matchType": "EXACT", "value": value}}}


def event_filter(name):
    return exact("eventName", name)


def report_filter(event=None, segment=None):
    """TELEM-24b: every report counts only the published site (local previews reached GA before WEB-18)."""
    host = exact("hostName", PRODUCTION_HOST)
    expressions = [host]
    if event:
        expressions.append(event_filter(event))
    if segment:
        dimension, values = segment
        expressions.append({"filter": {"fieldName": dimension,
                                       "inListFilter": {"values": values, "caseSensitive": True}}})
    return {"andGroup": {"expressions": expressions}} if len(expressions) > 1 else host


def report_body(axis, dimensions, metrics, event=None, order=None, limit=None, totals=False, *, segment=None):
    """axis: the ISO days of the window, oldest first; explicit dates keep every report on the same days."""
    body = {"dateRanges": [{"startDate": axis[0], "endDate": axis[-1]}],
            "dimensions": [{"name": d} for d in dimensions], "metrics": [{"name": m} for m in metrics],
            "dimensionFilter": report_filter(event, segment)}
    if order:
        body["orderBys"] = [{"metric": {"metricName": order}, "desc": True}]
    if limit:
        body["limit"] = str(limit)
    if totals:
        body["metricAggregations"] = ["TOTAL"]
    return body


def number(text):
    if isinstance(text, str):
        try:
            return int(text)
        except ValueError:
            pass
    try:
        value = float(text)
    except (TypeError, ValueError):
        raise GA4Error("invalid numeric value in GA4 report") from None
    if not math.isfinite(value):
        raise GA4Error("non-finite numeric value in GA4 report")
    return int(value) if value.is_integer() else value


def parse_report(reply, metrics):
    rows = [{"dims": [d.get("value", "") for d in row.get("dimensionValues") or []],
             "values": {m: number(v.get("value")) for m, v in zip(metrics, row.get("metricValues") or [])}}
            for row in reply.get("rows") or []]
    totals = None
    for total in reply.get("totals") or []:
        totals = {m: number(v.get("value")) for m, v in zip(metrics, total.get("metricValues") or [])}
    return rows, totals


def quality_flags(reply):
    """GA4 metadata can limit what an absent row or a partial total tells us."""
    metadata = reply.get("metadata") or {}
    fields = (("subjectToThresholding", "thresholding"), ("samplingMetadatas", "sampled"),
              ("dataLossFromOtherRow", "other_row"), ("dataTruncationReasons", "truncated"),
              ("emptyReason", "empty"))
    return [flag for field, flag in fields if metadata.get(field)]


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
    ("download_methods", ["customEvent:download_method"], ["eventCount"], "download_request", "eventCount",
     ("customEvent:download_method",)),
    ("handoff_actions", ["customEvent:handoff_action"], ["eventCount"], "download_handoff", "eventCount",
     ("customEvent:handoff_action",)),
    ("vitals", ["customEvent:metric_name", "customEvent:metric_rating"], ["eventCount"], "web_vital", "eventCount",
     ("customEvent:metric_name", "customEvent:metric_rating")),
    ("download_releases", ["customEvent:release_version"], ["eventCount"], "download_request", "eventCount",
     ("customEvent:release_version",)),
)
# TELEM-24b conversion: (key, dimension) -> users, and users who sent download_request, per value.
FUNNELS = (("source", "sessionSource"), ("device", "deviceCategory"), ("os", "operatingSystem"))
# WEB-17 property setup the dashboard checks: custom definitions the site's events need.
EXPECTED_DIMENSIONS = ("download_platform", "release_version", "download_source", "download_method",
                       "handoff_action", "metric_name", "metric_rating")


def collect(property_id, token, headers=None, days=30, now=None, http=http_json):
    """Aggregate website reports for the last `days` days. The daily overview must succeed (it proves access);
    the other reports record their own error and leave the rest of the model usable."""
    now = time.time() if now is None else now
    if days < 1:
        raise GA4Error("GA4 reporting window must contain at least one day")
    headers = headers or {}
    base = f"{DATA_API}/properties/{property_id}"
    run = lambda body: http("POST", f"{base}:runReport", token, body=body, headers=headers)  # noqa: E731
    # A minimal report first: its metadata names the property's reporting time zone, which fixes the day window.
    probe = run({"dateRanges": [{"startDate": "today", "endDate": "today"}], "metrics": [{"name": "activeUsers"}]})
    time_zone = (probe.get("metadata") or {}).get("timeZone")
    today, zone_ok = property_today(time_zone, now)
    axis = [(today - timedelta(days=offset)).isoformat() for offset in range(days - 1, -1, -1)]
    provisional = set(axis[-PROVISIONAL_DAYS:])
    report_quality = {}

    def report(key, dimensions, metrics, **options):
        reply = run(report_body(axis, dimensions, metrics, **options))
        flags = quality_flags(reply)
        if flags:
            report_quality[key] = list(dict.fromkeys(report_quality.get(key, []) + flags))
        return parse_report(reply, metrics)

    def summary(key, metrics, **options):
        # A dimensionless report deduplicates users across the whole window. The
        # Data API's TOTAL aggregation is a sum, unsuitable for unique-user days.
        rows, _ = report(key, [], metrics, **options)
        if len(rows) > 1:
            raise GA4Error(f"{key} returned multiple whole-window rows")
        return rows[0]["values"] if rows else {}

    def absent_day(day, key):
        return None if day in provisional or report_quality.get(key) else 0

    names = [api for _, api in DAILY]
    rows, _ = report("daily", ["date"], names)
    by_day = {iso_day(r["dims"][0]): r["values"] for r in rows}
    model = {
        "property": str(property_id), "measurement_id": MEASUREMENT_ID, "time_zone": time_zone,
        "zone_fallback": not zone_ok,
        "collected_utc": datetime.fromtimestamp(now, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "days": axis, "provisional_days": [day for day in axis if day in provisional],
        "comparison_through": (today - timedelta(days=PROVISIONAL_DAYS)).isoformat() if zone_ok else None,
        "report_quality": report_quality,
        "daily": [{"day": day, **{key: by_day[day].get(api) if day in by_day else absent_day(day, "daily")
                                  for key, api in DAILY}} for day in axis],
        "totals": {key: None for key, _ in DAILY}, "conversion_users": None,
        "downloads_daily": [], "downloads_total": None, "downloads_users": None, "handoffs": None,
        "realtime_users": None, "host": PRODUCTION_HOST,
        "tables": {}, "funnels": {}, "missing": {}, "errors": {}, "setup": {},
    }
    try:
        totals = summary("totals", names + ["totalUsers"])
        default = 0 if not totals and not report_quality.get("totals") else None
        model["totals"] = {key: totals.get(api, default) for key, api in DAILY}
        if not report_quality.get("totals"):
            model["conversion_users"] = totals.get("totalUsers", default)
    except GA4Error as error:
        model["errors"]["totals"] = str(error)
    try:
        dl_rows, _ = report("downloads", ["date"], ["eventCount"], event="download_request")
        dl = {iso_day(r["dims"][0]): r["values"].get("eventCount") for r in dl_rows}
        model["downloads_daily"] = [{"day": day, "count": dl.get(day, absent_day(day, "downloads"))}
                                    for day in axis]
    except GA4Error as error:
        model["errors"]["downloads"] = str(error)
    try:
        dl_totals = summary("download_totals", ["eventCount", "totalUsers"], event="download_request")
        default = 0 if not dl_totals and not report_quality.get("download_totals") else None
        model["downloads_total"] = dl_totals.get("eventCount", default)
        requested, total = dl_totals.get("totalUsers", default), model["conversion_users"]
        if not report_quality.get("download_totals") and total is not None and requested is not None:
            if 0 <= requested <= total:
                model["downloads_users"] = requested
            else:
                report_quality["conversion"] = ["inconsistent_totals"]
    except GA4Error as error:
        model["errors"]["download_totals"] = str(error)
    try:
        handoff_rows, _ = report("handoffs", [], ["eventCount"], event="download_handoff")
        if handoff_rows or not report_quality.get("handoffs"):
            model["handoffs"] = sum(r["values"]["eventCount"] for r in handoff_rows)
    except GA4Error as error:
        model["errors"]["handoffs"] = str(error)
    for key, dimension in FUNNELS:
        report_key = f"funnel_{key}"
        try:
            users, _ = report(report_key, [dimension], ["totalUsers"], order="totalUsers", limit=25)
            names = [row["dims"][0] for row in users if row["dims"][0] not in ("", "(other)")]
            requesting, _ = report(report_key, [dimension], ["totalUsers"], event="download_request",
                                   segment=(dimension, names)) if names else ([], None)
            asked = {row["dims"][0]: row["values"]["totalUsers"] for row in requesting}
            rows = []
            trustworthy = not report_quality.get(report_key)
            for row in users:
                name, total = row["dims"][0], row["values"]["totalUsers"]
                requested = asked.get(name, 0) if trustworthy and name in names else None
                if requested is not None and not 0 <= requested <= total:
                    requested = None
                    report_quality[report_key] = ["inconsistent_totals"]
                rows.append({"name": name, "users": total, "requesting": requested})
            model["funnels"][key] = rows
        except GA4Error as error:
            model["errors"][report_key] = str(error)
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
            table, _ = report(key, dimensions, metrics, event=event, order=order, limit=50 if key == "vitals" else TOP)
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
    model["setup"] = property_setup(property_id, token, headers, available, http)
    return model


def property_setup(property_id, token, headers, available, http=http_json):
    """WEB-17 checklist from the Admin API (read-only); each item is None when it could not be read."""
    setup = {"retention": None, "key_events": None,
             "dimensions": None if available is None else
             {name: f"customEvent:{name}" in available for name in EXPECTED_DIMENSIONS}}
    try:
        setup["retention"] = http("GET", f"{ADMIN_API}/properties/{property_id}/dataRetentionSettings", token,
                                  headers=headers).get("eventDataRetention")
    except GA4Error:
        pass
    try:
        setup["key_events"] = sorted(e.get("eventName", "") for e in http(
            "GET", f"{ADMIN_API}/properties/{property_id}/keyEvents", token, headers=headers).get("keyEvents") or [])
    except GA4Error:
        pass
    return setup


def fetch(days=30, property_id=None, credentials=None, now=None, http=http_json):
    """Full collection for the dashboard: {"error": ...} on failure, None when nothing is configured."""
    if not configured(credentials):
        return None
    stamp = datetime.fromtimestamp(time.time() if now is None else now, tz=timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ")
    deadline = time.monotonic() + COLLECTION_BUDGET_S

    def request(*args, **kwargs):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise GA4Error("GA4 collection time budget exhausted")
        if http is http_json:
            kwargs["timeout"] = min(TIMEOUT_S, remaining)
        return http(*args, **kwargs)

    try:
        token, headers = access_token(credentials, http=request, now=now)
        property_id = property_id or os.environ.get("OPENRC_GA4_PROPERTY")
        if not property_id:
            property_id = discover_property(token, headers, http=request)
            print(f"GA4 property {property_id} has web stream {MEASUREMENT_ID}; set OPENRC_GA4_PROPERTY="
                  f"{property_id} to skip discovery", file=sys.stderr)
        property_id = str(property_id).removeprefix("properties/")
        if not property_id.isdigit():
            raise GA4Error(f"GA4 property must be the numeric property ID, not {property_id!r}")
        return collect(property_id, token, headers, days, now, request)
    except GA4Error as error:
        return {"error": str(error), "collected_utc": stamp, "property": property_id}
    except Exception as error:  # noqa: BLE001 - the website tab is optional: never lose the rest of the snapshot
        return {"error": f"unexpected {error.__class__.__name__} (rerun with OPENRC_GA4_DEBUG=1 for the traceback)"
                if not os.environ.get("OPENRC_GA4_DEBUG") else repr(error)[:300],
                "collected_utc": stamp, "property": property_id}


def window(model, count):
    """Sum the last `count` download days when every value is available."""
    if count < 1:
        raise ValueError("window must contain at least one day")
    values = [row["count"] for row in (model.get("downloads_daily") or [])[-count:]]
    return sum(values) if len(values) == count and None not in values else None


# ---------------------------------------------------------------------------------------------- CLI: login, check


def default_user_file():
    return Path.home() / ".config" / "openrc" / "ga4-user.json"


def login(client_file, out, redirect_uri, timeout_s=300, http=http_json):
    """One-time browser consent with an OAuth client ("installed" or "web" JSON from the Cloud console): loopback
    redirect with PKCE, then an authorized_user file for OPENRC_GA4_CREDENTIALS. A web client must list
    `redirect_uri` exactly under Authorized redirect URIs."""
    import hashlib
    from http.server import BaseHTTPRequestHandler, HTTPServer
    import secrets
    import webbrowser

    raw = json.loads(Path(client_file).read_text(encoding="utf-8"))
    client = raw.get("installed") or raw.get("web")
    if not client or not client.get("client_id") or not client.get("client_secret"):
        raise GA4Error("not an OAuth client file (expected an 'installed' or 'web' entry)")
    target = urllib.parse.urlsplit(redirect_uri)
    if target.scheme != "http" or target.hostname not in ("localhost", "127.0.0.1") or not target.port:
        raise GA4Error("redirect URI must be http://localhost:<port>/ (loopback)")
    verifier = b64url(secrets.token_bytes(48))
    state = secrets.token_urlsafe(24)
    query = {"client_id": client["client_id"], "redirect_uri": redirect_uri, "response_type": "code", "scope": SCOPE,
             "access_type": "offline", "prompt": "consent", "state": state, "code_challenge_method": "S256",
             "code_challenge": b64url(hashlib.sha256(verifier.encode("ascii")).digest())}
    url = (client.get("auth_uri") or "https://accounts.google.com/o/oauth2/auth") + "?" + urllib.parse.urlencode(query)
    result = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802 - http.server API
            params = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
            if params.get("state", [None])[0] != state:
                self.send_response(400)
                self.end_headers()
                return
            result.update({k: v[0] for k, v in params.items()})
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"<p>OpenRC dashboard: Google Analytics access recorded. You can close this tab.</p>")

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", target.port), Handler)
    server.timeout = 5
    print(f"Open this URL if the browser does not open:\n{url}", flush=True)
    webbrowser.open(url)
    deadline = time.time() + timeout_s
    with server:
        while not result and time.time() < deadline:
            server.handle_request()
    if not result:
        raise GA4Error("no answer from the browser before the timeout")
    if "code" not in result:
        raise GA4Error(f"consent refused: {result.get('error', 'unknown error')}")
    reply = http("POST", client.get("token_uri") or TOKEN_URI, form={
        "grant_type": "authorization_code", "code": result["code"], "redirect_uri": redirect_uri,
        "client_id": client["client_id"], "client_secret": client["client_secret"], "code_verifier": verifier})
    if not reply.get("refresh_token"):
        raise GA4Error("Google returned no refresh token; revoke the app's access and log in again")
    out = Path(out)
    if out.resolve().is_relative_to(REPO):
        raise GA4Error("write the GA4 login outside the repository (it is a secret)")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"type": "authorized_user", "client_id": client["client_id"],
                               "client_secret": client["client_secret"], "refresh_token": reply["refresh_token"],
                               "token_uri": client.get("token_uri") or TOKEN_URI}, indent=1), encoding="utf-8")
    return out


def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser(description="GA4 website statistics for the operator dashboard")
    sub = parser.add_subparsers(dest="command", required=True)
    g = sub.add_parser("login", help="one-time browser consent with an OAuth client file")
    g.add_argument("--client-secret", required=True, help="OAuth client JSON downloaded from the Cloud console")
    g.add_argument("--out", default=str(default_user_file()), help="authorized_user file to write")
    g.add_argument("--redirect-uri", default="http://localhost:8085/")
    c = sub.add_parser("check", help="read the reports once and print a summary")
    c.add_argument("--property", default=None)
    c.add_argument("--credentials", default=None)
    c.add_argument("--days", type=int, default=30)
    args = parser.parse_args(argv)
    try:
        if args.command == "login":
            out = login(args.client_secret, args.out, args.redirect_uri)
            print(f"wrote {out}\nset OPENRC_GA4_CREDENTIALS={out}")
            return 0
    except (GA4Error, OSError, ValueError) as error:
        print(f"login failed: {error}", file=sys.stderr)
        return 1
    model = fetch(args.days, args.property, args.credentials)
    if model is None:
        print("no GA4 credentials configured", file=sys.stderr)
        return 2
    if model.get("error"):
        print(f"GA4 failed: {model['error']}", file=sys.stderr)
        return 1
    totals = model["totals"]
    print(f"property {model['property']} ({model['time_zone']}), {model['days'][0]}..{model['days'][-1]}: "
          f"{totals['users']} users, {totals['sessions']} sessions, {totals['views']} views, "
          f"{model['downloads_total']} download requests, {model['realtime_users']} active now")
    for key, value in sorted(model["missing"].items()):
        print(f"not registered: {key} needs {', '.join(value)}")
    for key, value in sorted(model["errors"].items()):
        print(f"report {key} failed: {value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
