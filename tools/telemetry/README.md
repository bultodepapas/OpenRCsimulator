# OpenRC statistics dashboard

One local, read-only HTML page for every project statistic: players from the live [telemetry receiver](../../services/telemetry/README.md), release downloads, GitHub visits, clones, stars, referrers and releases from the [GitHub history archive](../analytics/README.md), and receiver health. Tabs: Overview, Players, Downloads, GitHub, Website, Receiver.

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

The receiver snapshot uses only the service's public read paths (`status_report`, `ingest_counts`, `day_statuses`, `insights.collect`), so every player cell has passed the same per-cell floor as `python -m openrc_telemetry insights` (default 20, minimum 10). No session or batch identifier, raw body or address leaves the receiver. `<page>.snapshot.json` is saved beside the page with the receiver and GitHub data; it is operator-only too.

## Tabs

| Tab | Content and source |
| --- | --- |
| Overview | Alerts; players (newest insight week), package downloads, latest release, repository views and clones over 14 days, stars, forks, watchers and issues; 30-day charts of downloads, visits, stars and accepted telemetry batches, with final releases marked |
| Players | Weekly insights per ISO week and release: frame cadence by GPU, pacing, resolution, OS/driver and vehicle; menu cadence; vehicle usage; errors; hardware and settings mix. Bars sorted by value, the grey combined row last |
| Downloads | Package counters: total and platform share, latest release, last 7 days, increases per collection day, every release by Windows / macOS / Linux |
| GitHub | Stars, forks, watchers, open issues; page views and unique visitors, clones and unique cloners per day (archived beyond GitHub's 14 days); stars over time; releases with dates and downloads; top referrers and popular pages (GitHub's 14-day window) |
| Website | GA4 is not connected yet (see below) |
| Receiver | Health tiles; ingest outcomes per day with refusal detail; rollup coverage per release and day (pending, overdue, missed, no traffic) |

**Alerts.** Critical: suspend-all, raw row past 48 h, `storage_unavailable`, a day with telemetry traffic never rolled up. Warning: rollup overdue (with the command and hours left), raw age near 48 h, suspended releases, `rejected:unapproved_release`, `rate_limited`, no batch in 24 h, a failed GitHub collection, counters older than 36 h.

**Reading the numbers.** Player counts are session-day observations from consenting sessions, not people; FPS is a render-cadence estimate and VSync or an FPS cap limits it by design ([insights notes](../../services/telemetry/README.md#weekly-insights-telem-1617)). Downloads are cumulative GitHub counters including repeats and automation; per-day values are increases between collections. Clones are mostly automated (CI, mirrors). Stars over time count current stargazers by the day they starred; withdrawn stars disappear from GitHub's list. Alerts and "today" are as of the snapshot; the page shows its age and a banner once it is over an hour old.

**Website (GA4).** The public site reports to GA4 destination `G-4Z11DSB2BV` ([site analytics](../../site/README.md#website-analytics-web-12)). Charting it here needs the numeric GA4 property ID and a read-only Data API credential (`analytics.readonly`); none is configured.

## Test

```powershell
$env:OPENRC_DASHBOARD_DEMO = "U:\OpenRC\telemetry-dashboard-demo"   # optional: keep the synthetic demo page
python -m unittest tools/telemetry/test_dashboard.py                 # needs services/telemetry/requirements.txt
```

The test seeds a receiver database through the real ingest and rollup paths and a GitHub archive through the history tool's own storage functions, then checks the snapshot (no identifiers, small cells combined, missing databases refused), coverage states, alerts, every tab and escaping. The telemetry contracts workflow runs it.
