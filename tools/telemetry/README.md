# Telemetry operator dashboard

A local, read-only HTML view of the live [telemetry receiver](../../services/telemetry/README.md) and of the GitHub release download counters: alerts, receiver health, release downloads, ingest outcomes per UTC day, daily rollup coverage and the weekly operator insights (frame cadence, vehicle usage, errors, hardware and settings mix).

**Operator-only.** Insight cells share sessions and use a session-day floor, so the page must not be published, uploaded or committed. It is written to a local directory (`U:\OpenRC\telemetry-dashboard\` when `U:` exists, otherwise `%LOCALAPPDATA%\OpenRCsimulator\telemetry-dashboard\`); `--out` inside the repository is refused. The page makes no network requests.

## Use

```powershell
$env:OPENRC_TELEMETRY_SSH = "root@<proxmox-node>"          # host that runs the receiver container
$env:OPENRC_TELEMETRY_SSH_KEY = "$HOME\.ssh\<identity>"
python tools/telemetry/dashboard.py fetch                  # snapshot, render and open the page
python tools/telemetry/dashboard.py fetch --days 60 --weeks 8 --floor 20
python tools/telemetry/dashboard.py render --snapshot U:\OpenRC\telemetry-dashboard\dashboard.snapshot.json
```

`fetch` pipes [`snapshot.py`](snapshot.py) over SSH into `pct exec <ct>` (default container `404`; `--ct ''` runs on the SSH host itself). Inside, it runs as user `telemetry` with the deployed venv from `/opt/openrc-telemetry/current/services/telemetry`, exporting only the `OPENRC_TELEMETRY_*` lines of `/etc/openrc-telemetry/env` (tokens stay out; override paths with `--remote-root` / `--remote-env`). Nothing is installed or changed on the receiver, and the snapshot refuses to run (exit 3) unless both databases already exist. Receiver host and deployment details live in the operations repository.

The snapshot uses only the service's public read paths (`status_report`, `ingest_counts`, `day_statuses`, `insights.collect`), so every insight cell has passed the same per-cell floor as `python -m openrc_telemetry insights` (default 20, minimum 10). No session or batch identifier, raw body or address leaves the receiver. `<page>.snapshot.json` is saved beside the page and holds the same operator-only data.

## Page

| Section | Source and meaning |
| --- | --- |
| Alerts | Critical: suspend-all, raw row past 48 h, `storage_unavailable`, a day with traffic never rolled up. Warning: rollup overdue (with the command and hours left), raw age near 48 h, suspended releases, `rejected:unapproved_release`, `rate_limited`, no batch in 24 h |
| Release downloads | GitHub package counters from the [GitHub history archive](../analytics/README.md) (`%LOCALAPPDATA%\OpenRCsimulator\analytics`, or `--downloads-dir` / `OPENRC_ANALYTICS_DIR`), opened read-only: total and platform share, latest release, the last 7 days, increases per collection day, and every release split by Windows / macOS / Linux. `fetch` first runs that tool's `collect` (read-only GitHub API through the existing `gh` login; skip with `--no-download-collect`); a failed collection keeps the archived counters and raises an alert, as do counters older than 36 h |
| Health tiles | Worst alert; newest accepted batch (exact from raw rows, else the UTC day from the counters, which outlive the 48 h raw purge); accepted today and yesterday; last 7 days against the 7 before; refusals; raw age; releases |
| Ingest outcomes | `ingest_counts` per day, grouped as accepted, duplicate, rejected (`rejected:*`) and other refusals; hover, tap or tab to a day, or open the table |
| Rollup coverage | `daily_status` per release and day. Days without a row are pending (before 03:00 UTC next day), overdue (still inside the 47 h window), missed (traffic but never rolled up) or no traffic |
| Weekly insights | `insights.collect` per recent ISO week and release with cells, newest release first; choose the week in the selector. Bars are sorted by value, the grey combined row last |

Alerts and "today" are as of the snapshot; the page shows the snapshot's age and a banner once it is over an hour old. Interpretation follows the [insights notes](../../services/telemetry/README.md#weekly-insights-telem-1617): counts are session-day observations, FPS is a render-cadence estimate, and VSync or an FPS cap limits cadence by design.

## Test

```powershell
$env:OPENRC_DASHBOARD_DEMO = "U:\OpenRC\telemetry-dashboard-demo"   # optional: keep the synthetic demo page
python -m unittest tools/telemetry/test_dashboard.py                 # needs services/telemetry/requirements.txt
```

The test seeds a receiver database through the real ingest and rollup paths, then checks the snapshot (no identifiers, small cells combined, missing databases refused), the derived coverage states and alerts, and the rendered page. The telemetry contracts workflow runs it.
