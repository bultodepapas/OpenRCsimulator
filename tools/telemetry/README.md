# OpenRC statistics dashboard

One local, read-only HTML page for every project statistic: players from the live [telemetry receiver](../../services/telemetry/README.md), release downloads, GitHub visits, clones, stars, referrers and releases from the [GitHub history archive](../analytics/README.md), website visitors and download requests from Google Analytics 4, and receiver health. Tabs: Overview, Players, Downloads, GitHub, Website, Receiver.

**Operator-only.** Player cells share sessions and use a session-day floor, and GitHub traffic is owner-only data, so the page must not be published, uploaded or committed. It is written to a local directory (`U:\OpenRC\telemetry-dashboard\` when `U:` exists, otherwise `%LOCALAPPDATA%\OpenRCsimulator\telemetry-dashboard\`); `--out` inside the repository is refused. The page makes no network requests.

## Use

```powershell
$env:OPENRC_TELEMETRY_SSH = "root@<proxmox-node>"          # host that runs the receiver container
$env:OPENRC_TELEMETRY_SSH_KEY = "$HOME\.ssh\<identity>"
python tools/telemetry/dashboard.py fetch                  # receiver snapshot + GitHub collection, render, open
python tools/telemetry/dashboard.py fetch --days 60 --weeks 8 --floor 20
python tools/telemetry/dashboard.py render --snapshot U:\OpenRC\telemetry-dashboard\dashboard.snapshot.json
```

`fetch` pipes [`snapshot.py`](snapshot.py) over SSH into `pct exec <ct>` (default container `404`; `--ct ''` runs on the SSH host itself). Inside, it runs as user `telemetry` with the deployed venv from `/opt/openrc-telemetry/current/services/telemetry`, exporting only the `OPENRC_TELEMETRY_*` lines of `/etc/openrc-telemetry/env` (tokens stay out; override paths with `--remote-root` / `--remote-env`). Nothing is installed or changed on the receiver, and the snapshot refuses to run (exit 3) unless both databases already exist. Receiver host and deployment details live in the operations repository.

Then `fetch` runs the GitHub history tool's `collect` on its archive (`%LOCALAPPDATA%\OpenRCsimulator\analytics`, or `--downloads-dir` / `OPENRC_ANALYTICS_DIR`; read-only GitHub API through the existing `gh` login; skip with `--no-download-collect`) and reads the archive read-only. The daily task keeps that archive growing without the dashboard.

Last, `fetch` reads the website's GA4 reports for the same `--days` window through [`ga4.py`](ga4.py) when a Google credential is configured (skip with `--no-ga4`); see [Website (GA4)](#website-ga4).

The receiver snapshot uses only the service's public read paths (`status_report`, `ingest_counts`, `day_statuses`, `insights.collect`), so every player cell has passed the same per-cell floor as `python -m openrc_telemetry insights` (default 20, minimum 10). No session or batch identifier, raw body or address leaves the receiver. `<page>.snapshot.json` is saved beside the page with the receiver and GitHub data; it is operator-only too.

## Tabs

| Tab | Content and source |
| --- | --- |
| Overview | Receiver alerts and freshness per source. Last seven full days in UTC for GitHub and the receiver and in the GA4 property zone for Website. Each sum shows coverage and compares periods with complete observations. Recent releases, platform downloads, referrals, countries and daily charts |
| Players | Weekly insights per ISO week and release: frame cadence by GPU, pacing, resolution, OS/driver and vehicle; menu cadence; vehicle usage; errors; hardware and settings mix. Bars sorted by value, the grey combined row last |
| Downloads | Package counters: total and platform share, latest release, last 7 days, increases per collection day, every release by Windows / macOS / Linux |
| GitHub | Stars, forks, watchers, open issues; page views and unique visitors, clones and unique cloners per day (archived beyond GitHub's 14 days); stars over time; releases with dates and downloads; top referrers and popular pages (GitHub's 14-day window) |
| Website | GA4, published host only: active users, sessions, page views, download requests, download conversion, phone hand-offs and realtime users. Charts of visitors and download requests per day, with releases marked. Countries, download requests by country, traffic sources, top pages and devices. Download requests by platform, source and release, and Web Vitals ratings. Conversion per source, device and OS. A property-setup checklist (retention, key event, custom dimensions) |
| Receiver | Health tiles; ingest outcomes per day with refusal detail; rollup coverage per release and day (pending, overdue, missed, no traffic) |

**Alerts.** Critical: suspend-all, raw row past 48 h, `storage_unavailable`, a day with telemetry traffic never rolled up. Warning: rollup overdue (with the command and hours left), raw age near 48 h, suspended releases, `rejected:unapproved_release`, `rate_limited`, no batch in 24 h, a failed GitHub collection, counters older than 36 h.

**Reading the numbers.** Player counts are consenting session-day observations, shown with their release. FPS is a render-cadence estimate limited by VSync or the FPS cap ([insights notes](../../services/telemetry/README.md#weekly-insights-telem-1617)). Cumulative GitHub downloads include repeats and automation. Daily increases use the UTC date of the later collection. Gaps and changed asset sets can make those increases partial. Clones are mostly automated. Historical stars use the date of starring for accounts that still star the repository. Public collection refreshes the current total and leaves the authenticated series dated separately. The dashboard shows snapshot age and warns after an hour.

## Website (GA4)

The public site reports to GA4 destination `G-4Z11DSB2BV` ([site analytics](../../site/README.md#website-analytics-web-12)). `ga4.py` reads aggregate reports from the [GA4 Data API](https://developers.google.com/analytics/devguides/reporting/data/v1) with the `analytics.readonly` scope; it writes nothing to Google. One-time setup with a service account:

1. In a Google Cloud project, enable the **Google Analytics Data API** (and the **Google Analytics Admin API** if the property ID should be found automatically).
2. Create a service account, add a JSON key, and store it **outside the repository** (for example `%APPDATA%\OpenRCsimulator\ga4-key.json`). A key inside the repository is refused.
3. In Google Analytics → Admin → Property access management, add the service account's e-mail with the **Viewer** role.
4. Set the environment and run `fetch` as usual:

```powershell
$env:OPENRC_GA4_CREDENTIALS = "$env:APPDATA\OpenRCsimulator\ga4-key.json"
$env:OPENRC_GA4_PROPERTY = "<numeric property ID>"   # Admin → Property details; optional with the Admin API
python tools/telemetry/dashboard.py fetch
```

**With your own Google login instead (current owner setup).** Create an OAuth client in the same Cloud project (type *Desktop app*, or *Web application* with `http://localhost:8085/` under Authorized redirect URIs), download its JSON outside the repository, enable both APIs, then consent once in the browser:

```powershell
python tools/telemetry/ga4.py login --client-secret "$HOME\.config\openrc\ga4-client.json"   # writes ~/.config/openrc/ga4-user.json
$env:OPENRC_GA4_CREDENTIALS = "$HOME\.config\openrc\ga4-user.json"
python tools/telemetry/ga4.py check                      # one-line summary; prints the property ID if discovered
python tools/telemetry/dashboard.py render --snapshot <saved snapshot> --ga4   # refresh only the Website data
```

`login` uses a loopback redirect with PKCE and asks only for `analytics.readonly`. A consent screen in *Testing* mode lists the account as a test user; Google may then expire the refresh token after seven days, so publish the consent screen (no verification is needed for personal use) or rerun `login`. Install `tzdata` where Python lacks IANA time zones (Windows), or the tab falls back to UTC days.

Signing a service-account key needs the `cryptography` package. Alternatives without it: an application-default user login file (`authorized_user`, as written by `login` or Google's [Data API quickstart](https://developers.google.com/analytics/devguides/reporting/data/v1/quickstart-client-libraries); a `quota_project_id` in it is sent as `x-goog-user-project`) named by `OPENRC_GA4_CREDENTIALS` or `GOOGLE_APPLICATION_CREDENTIALS`, or a ready token in `OPENRC_GA4_ACCESS_TOKEN`. gcloud's default login file is never used implicitly. `--ga4-credentials` wins over a token in the environment, and `--ga4-property` over `OPENRC_GA4_PROPERTY`. Without the property ID, `fetch` searches the visible properties for the web stream with the site's measurement ID and prints the ID to set.

Every report is filtered to `hostName = bultodepapas.github.io`, so local previews (before WEB-18) are excluded; realtime users are not filtered. The *Property setup* panel reads data retention and key events through the Admin API, and registered dimensions through the Data API metadata. It checks them against [WEB-17](../../docs/plans/website-analytics.md). An expired or revoked login reports how to run `ga4.py login` again.

Days follow the property's reporting time zone, not UTC: a first minimal report reads the zone, and every report then uses the same explicit dates. If Python cannot load the zone (Windows without the `tzdata` package), the tab says it fell back to UTC days. Platform, source, release and Web Vitals breakdowns need event-scoped custom dimensions `download_platform`, `download_source`, `release_version`, `metric_name` and `metric_rating` registered in Admin → Custom definitions; GA4 reports them only from registration onwards, and the tab says which are missing. A failed collection keeps the rest of the page and raises a warning alert; one failed report leaves the others.

## Test

```powershell
$env:OPENRC_DASHBOARD_DEMO = "U:\OpenRC\telemetry-dashboard-demo"   # optional: keep the synthetic demo page
python -m unittest tools/telemetry/test_dashboard.py                 # needs services/telemetry/requirements.txt
python -m unittest tools/telemetry/test_ga4.py                       # standard library; signing test uses cryptography
```

`test_ga4.py` runs the collector against a fake Data/Admin API: report bodies, property discovery, missing custom dimensions, per-report failures, token exchange for both credential types and a verified RS256 assertion. Python 3.12 is required (`dashboard.py` uses its f-string syntax).

The test seeds a receiver database through the real ingest and rollup paths and a GitHub archive through the history tool's own storage functions, then checks the snapshot (no identifiers, small cells combined, missing databases refused), coverage states, alerts, every tab and escaping. The telemetry contracts workflow runs it.
