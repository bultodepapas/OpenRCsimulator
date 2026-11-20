# Telemetry operator dashboard

A local, read-only HTML view of the live [telemetry receiver](../../services/telemetry/README.md): receiver health, ingest outcomes per UTC day, daily rollup coverage and the weekly operator insights (frame cadence, vehicle usage, errors, hardware and settings mix).

**Operator-only.** Insight cells share sessions and use a session-day floor, so the page must not be published, uploaded or committed. It is written to a local directory (`U:\OpenRC\telemetry-dashboard\` when `U:` exists, otherwise `%LOCALAPPDATA%\OpenRCsimulator\telemetry-dashboard\`) and makes no network requests.

## Use

```powershell
$env:OPENRC_TELEMETRY_SSH = "root@<proxmox-node>"          # host that runs the receiver container
$env:OPENRC_TELEMETRY_SSH_KEY = "$HOME\.ssh\<identity>"
python tools/telemetry/dashboard.py fetch                  # snapshot, render and open the page
python tools/telemetry/dashboard.py fetch --days 60 --weeks 8 --floor 20
python tools/telemetry/dashboard.py render --snapshot U:\OpenRC\telemetry-dashboard\snapshot.json
```

`fetch` pipes [`snapshot.py`](snapshot.py) over SSH into `pct exec <ct>` (default container `404`; `--ct ''` runs on the SSH host itself). Inside, it runs as user `telemetry` with the deployed venv and `/etc/openrc-telemetry/env` from `/opt/openrc-telemetry/current/services/telemetry` (override with `--remote-root` / `--remote-env`). Nothing is installed or changed on the receiver; the receiver host and deployment details live in the operations repository.

The snapshot uses only the service's public read paths (`status_report`, `ingest_counts`, `day_statuses`, `insights.collect`), so every insight cell has passed the same per-cell floor as `python -m openrc_telemetry insights` (default 20, minimum 10). No session or batch identifier, raw body or address leaves the receiver. `snapshot.json` is saved beside the page; it holds the same operator-only data.

## Page

| Section | Source |
| --- | --- |
| Health tiles | `status`: retention, newest stored batch, today's accepted/refused, raw batches held, allowed and suspended releases |
| Ingest outcomes | `ingest_counts` per day, grouped as accepted, duplicate, rejected (`rejected:*`) and other refusals; hover a day for every category |
| Rollup coverage | `daily_status` per release and day (`cells` status; hover for the GPU and vehicle tables) |
| Weekly insights | `insights.collect` per recent ISO week and release with cells; choose the week in the selector |

Interpretation follows the [insights notes](../../services/telemetry/README.md#weekly-insights-telem-1617): counts are session-day observations, FPS is a render-cadence estimate, and VSync or an FPS cap limits cadence by design.

## Test

```powershell
$env:OPENRC_DASHBOARD_DEMO = "U:\OpenRC\telemetry-dashboard-demo"   # optional: keep the synthetic demo page
python -m unittest tools/telemetry/test_dashboard.py                 # needs services/telemetry/requirements.txt
```

The test seeds a receiver database through the real ingest and rollup paths, then checks the snapshot (no identifiers, small cells combined) and the rendered page.
