# OpenRC telemetry receiver

Production candidate for the receiver described in `docs/plans/telemetry/` (data contract, delivery, publication protocol). It has been tested only on localhost; nothing here deploys, schedules or publishes by itself.

Python 3.12, Starlette + uvicorn, jsonschema (Draft 2020-12), stdlib `sqlite3` and `urllib`. No ORM. The canonical generated contracts in `research/telemetry/contracts/` are the schema source; `research/telemetry/reference.py` is the semantic reference and is exercised by `tests/test_equivalence.py` (the service never imports research code).

## Layout

| Path | Purpose |
| --- | --- |
| `openrc_telemetry/contract.py` | Strict decode (duplicate keys, NaN/Infinity, depth, UTF-8), schema + semantic checks, report validation |
| `openrc_telemetry/ingress.py` | ASGI app: `POST /v1/batches`, `GET /healthz`, optional `GET /v1/reports/weekly` |
| `openrc_telemetry/limits.py` | Per-client and global token buckets keyed by a rotating HMAC |
| `openrc_telemetry/storage.py` | `raw.sqlite` (48 h) and `aggregates.sqlite` (ID-free, 180 days, publication intents) |
| `openrc_telemetry/rollup.py` | Daily GPU and stock-vehicle tables with the 20-token suppression rule |
| `openrc_telemetry/report.py` | Deterministic weekly Markdown and digest |
| `openrc_telemetry/publisher.py` | Reconcile-then-create GitHub issue publisher with a durable intent ledger |
| `openrc_telemetry/counters.py` | ID-free daily ingest counters per fixed status category (TELEM-20) |
| `openrc_telemetry/insights.py` | Unsuppressed ID-free daily cells for several context dimensions and the weekly operator insights report with per-cell disclosure (TELEM-16/17) |
| `openrc_telemetry/cli.py`, `__main__.py` | `serve`, `purge`, `rollup`, `report`, `publish`, `status`, `check-release` |
| `tests/` | `unittest` suite incl. equivalence with `reference.py` and a fake GitHub server |

## Run locally

```powershell
uv venv --python 3.12 U:\OpenRC\tmp\telem-svc-venv
uv pip install --python U:\OpenRC\tmp\telem-svc-venv\Scripts\python.exe -r requirements.txt
$env:OPENRC_TELEMETRY_RELEASES = "v0.2.7"
$env:OPENRC_TELEMETRY_DATA_DIR = "U:\OpenRC\tmp\telem-data"
U:\OpenRC\tmp\telem-svc-venv\Scripts\python.exe -m openrc_telemetry serve --host 127.0.0.1 --port 8787
curl -i -X POST -H "Content-Type: application/json" --data-binary "@..\..\research\telemetry\examples\batch.json" http://127.0.0.1:8787/v1/batches   # 202
```

Run the tests from `services/telemetry` (set `TEMP`/`TMP` to a scratch drive first):

```powershell
python -m unittest discover -s tests -t .
```

The default schema directory resolves `../../research/telemetry/contracts` relative to this directory, so repository runs need no configuration. With an empty release allowlist every batch is rejected with 422 (fail closed; `serve` warns).

## Configuration (environment)

| Variable | Default | Meaning |
| --- | --- | --- |
| `OPENRC_TELEMETRY_DATA_DIR` | `./data` | Default directory for both databases |
| `OPENRC_TELEMETRY_RAW_DIR` / `_AGGREGATES_DIR` | the data directory | Separate locations; the container uses `/data/raw` and `/data/aggregates` (two volumes) |
| `OPENRC_TELEMETRY_SCHEMA_DIR` | `../../research/telemetry/contracts` | Folder with `batch.schema.json` and `report.schema.json` (container: `/app/contracts`) |
| `OPENRC_TELEMETRY_RELEASES` | empty | Comma list of accepted `build.release_id` values: exact tags or series prefixes `vX.*` / `vX.Y.*` (for example `v0.2.*,v0.3.*`), so a new tag in an accepted series is never dropped because it was not added in time. Anything else refuses to start |
| `OPENRC_TELEMETRY_SUSPEND_RELEASES` | empty | Releases (tags or prefixes) answered with `410`: clients stop collecting for the rest of their process; nothing is stored |
| `OPENRC_TELEMETRY_SUSPEND_ALL` | unset | `1` answers every batch with `410` (operator off switch) |
| `OPENRC_TELEMETRY_PURGE_INTERVAL_S` | `300` (30–1800) | `serve` purges raw rows this often, cutting interval + 60 s before 48 h so no row outlives 48 h and none is deleted before its day's 47 h rollup deadline |
| `OPENRC_TELEMETRY_TRUST_PROXY` | `0` | `1`: use the right-most `X-Forwarded-For` entry. Set only when every request passes the trusted proxy, which must append the peer address |
| `OPENRC_TELEMETRY_CLIENT_BURST` / `_CLIENT_REFILL_PER_S` | `20` / `0.1667` | Per-client bucket (about 10 requests/min sustained) |
| `OPENRC_TELEMETRY_GLOBAL_BURST` / `_GLOBAL_REFILL_PER_S` | `200` / `50` | Global ingress cap |
| `OPENRC_TELEMETRY_MAX_CLIENTS` | `100000` | Bound on tracked limiter keys; beyond it new clients get 429 |
| `OPENRC_TELEMETRY_MAX_RAW_BYTES` | `2147483648` | Raw database size above which ingestion returns 503 |
| `OPENRC_TELEMETRY_REPORT_TOKEN` | unset | Enables `GET /v1/reports/weekly` (Bearer token); unset means 404 |
| `OPENRC_TELEMETRY_GITHUB_API` | `https://api.github.com` | API base (https, or http on loopback for tests) |
| `OPENRC_TELEMETRY_BOT_AUTHOR` | unset | Login that authors the issues (for example `my-app[bot]`); required for `publish --execute` |
| `OPENRC_TELEMETRY_ISSUE_LABEL` | `telemetry` | Label set on created issues |
| `GITHUB_TOKEN` | unset | Needed only for `publish --execute`; never printed or logged |

## Endpoints

| Request | Result |
| --- | --- |
| `POST /v1/batches` | `202` accepted or identical replay (empty body, as in the OpenAPI); `400` malformed JSON, duplicate key, NaN/Infinity, bad UTF-8, depth; `409` same `batch_id` with other bytes, or overlapping session/seq; `410` suspended release or `SUSPEND_ALL` (never stored); `413` over 32768 bytes (checked while reading, before parsing); `415` not `application/json` (UTF-8 only) or any `Content-Encoding`; `422` schema, sequence order, histogram/duration, 30 s window floor, unapproved release, finite-overflow numbers; `429` + `Retry-After` (IPv6 clients are limited per /64); `503` storage unavailable or full |
| `GET /healthz` | `200 {"status":"ok"}` |
| `GET /v1/reports/weekly?week=2026-W47&release=v0.2.7` | `Authorization: Bearer <token>`; `200 {"title","body","digest"}`; `401`, `400`, `404` when disabled |
| anything else | `404` (`405` for a wrong method on a known path) |

Error bodies are `{"code": "<fixed category>"}` and never echo input. Request bodies, addresses, headers and jsonschema messages are never logged; only fixed categories (for example `category=schema`). uvicorn access logs are disabled.

## Storage and retention

- `raw.sqlite` holds batches (`batch_id` primary key, body digest, session, receipt time/day, body) and the `(session_id, seq)` dedup keys. WAL, `synchronous=FULL`, `secure_delete=ON`, incremental auto-vacuum. One transaction per batch; dedup and conflict come from the constraints, not from a cache.
- `aggregates.sqlite` holds ID-free daily tables, daily status rows and publication intents. The daily GPU table also keeps the summed 8-bucket frame-interval histogram (`hist0`…`hist7`) and excluded-gap total. The weekly report uses these for slow-frame shares and intervals over 100 ms per minute. The receiver refuses an aggregate store from before the histogram columns were added. Preserve its data and publication ledger, and verify compatibility on a disposable aggregate copy before switching a deployed service. Report v2 publishes under `weekly-v2/<week>/<release>`. Reconcile any earlier publication for the same week before attempting a new issue.
- **Raw data must never be backed up** (nor snapshotted, replicated or copied: `raw.sqlite`, `raw.sqlite-wal`, `raw.sqlite-shm`). The data contract promises at most 48 hours per record across every copy.
- `purge` deletes raw rows whose receipt is 48 h old or older (exactly 48 h counts as expired), then runs `incremental_vacuum` and `wal_checkpoint(TRUNCATE)`; it also removes aggregate rows older than 180 days. It is idempotent. Exit code 1 with a warning means a reader blocked the checkpoint; rerun it.
- Dedup protection ends with the record's expiry, as documented in the data contract.

## Operations

`serve` purges at startup and every `OPENRC_TELEMETRY_PURGE_INTERVAL_S`. A busy WAL checkpoint logs `purge category=checkpoint_busy` and schedules a retry after 15 seconds. Repeated warnings require an operator to check the blocking reader and the expiry deadline. `status.retention_ok` checks the ages of the current logical rows. Qualify readable copies independently. Run the other jobs from cron or a systemd timer next to the service. In Docker use `docker exec <container> python -m openrc_telemetry ...` so the commands share the container's SQLite WAL index.

| Job | Schedule (UTC) | Command |
| --- | --- | --- |
| Purge (second line of defence) | hourly; alert if the oldest raw row nears 48 h | `python -m openrc_telemetry purge` |
| Daily rollup | every day 01:30 | `python -m openrc_telemetry rollup --day yesterday` |
| Weekly report | Monday after 23:00 UTC (Sunday + 47 h, when no day of the week can change) | `python -m openrc_telemetry report --week 2026-W47 --release v0.2.7` |
| Weekly insights | same time | `python -m openrc_telemetry insights --week 2026-W47 --release v0.2.7` |

### Weekly insights (TELEM-16/17)

Each daily `rollup` also stores ID-free cells in `daily_cells` (aggregates database, 180 days) without suppression:

| Group | Tables (dimensions) | Values |
| --- | --- | --- |
| Flight frame cadence (complete steady windows with observed draws) | GPU family; frame-pacing limit (`vsync_or_fps_cap` when VSync or any FPS cap is on — the refresh rate is not reported, so the limit itself is unknown; `unlimited`; `unknown`); resolution class; OS + graphics driver; vehicle | windows, observed time, frames, 8-bucket interval histogram, excluded gaps |
| Menu and workshop cadence | screen (`home`, `workshop`, `other`) | same |
| Vehicle usage | vehicle, vehicle + physics evaluator | activity summaries, active and simulated time, takeoffs/landings/crashes for supported fixed-wing summaries. Schema v1 contributes an unknown evaluator |
| Software errors | error category | occurrences |
| Hardware and settings mix | OS + architecture, CPU family + threads, RAM, GPU family, renderer + driver, resolution class, frame-pacing limit, graphics settings, input | sessions |

Each named cell counts distinct temporary session tokens within each UTC receipt day. Windows and summaries are capped at 120 per token, day and cell. `python -m openrc_telemetry insights --week 2026-W48 --release v0.3.0 [--floor 20] [--format json]` pools the rolled-up days and applies the floor per cell (default 20, minimum 10, labelled "private floor" below 20). Categories can share sessions. Version 2 tests a combined row using the largest constituent count on each day, summed across days. Markdown labels a conservative count with `≥` and JSON sets `sessions_lower_bound`. The smallest eligible row joins the combination when needed. The table is withheld when the combined row cannot clear the floor. Stored cells are validated on read and daily counts stay inside the receiver.

**Insights are operator-only and must not be published.** Tables share the same sessions, so nested dimensions (for example a GPU family inside a renderer/driver cell) can still be differenced, and the weekly floor counts session-days: a new temporary session starts at each launch, each UTC day and every four hours, so one very active player can fill a cell. The older `report` (daily whole-table suppression, digest-bound `publish`) is unchanged and stays the conservative public form; never publish both for the same week and release.

### Is data arriving? (TELEM-20)

`serve` counts every `POST /v1/batches` outcome per UTC day under a fixed category (`accepted`, `duplicate`, `conflict`, `rejected:<validation category>` such as `rejected:unapproved_release`, `rate_limited`, `unsupported_media`, `too_large`, `bad_length`, `suspended_release`, `suspended_all`, `storage_unavailable`) and `forwarded_for_present` when the request carried `X-Forwarded-For` (its value is never read into the counters). Counts are held in memory and written to `ingest_counts` in `aggregates.sqlite` every minute and at shutdown; they expire with the other aggregates after 180 days and contain no identifier or address.

| Command | Use |
| --- | --- |
| `python -m openrc_telemetry status` | JSON: allowed and suspended releases, proxy trust, raw batch count, oldest raw age, seconds since the last stored batch, today's and yesterday's counters, yesterday's rollup statuses. Exit 1 when a raw row is past 48 h |
| `python -m openrc_telemetry check-release vX.Y.Z` | Before tagging a release: exit 0 only if the tag matches the client pattern, is allowlisted, is not suspended and the canonical example carrying it passes full ingest validation; exit 2 with the reason otherwise |

A rising `rejected:unapproved_release` means a published tag is missing from `OPENRC_TELEMETRY_RELEASES`; `rate_limited` behind a proxy usually means `OPENRC_TELEMETRY_TRUST_PROXY` does not match the proxy; `forwarded_for_present` with `TRUST_PROXY=0` shows the proxy does forward client addresses.

The [operator dashboard](../../tools/telemetry/README.md) renders `status`, the daily counters, rollup coverage and recent weekly insights from the live receiver as one local HTML page.

Rollup works only for a closed day: from day end + 1 h until day start + 47 h. Outside that window it refuses with an explanation. A missed deadline yields a missing day and raw retention remains capped at 48 h. Each run replaces the whole day in one SQLite transaction with a completion marker, including days with no accepted batches. The dashboard snapshot distinguishes legacy rollups with all expected tables from those with missing tables. Tables are suppressed as a whole when any cell has fewer than 20 distinct session tokens. Each token counts at most 120 windows or activity summaries.

Weekly publication flow:

1. `report --week W --release R` prints the Markdown to stdout and the title and SHA-256 digest to stderr (`--format json` gives `{title, body, digest}`; the endpoint returns the same data).
2. A person reviews the exact text and records the digest as approved.
3. `publish --week W --release R --repo owner/name --approved-digest <sha256>` is a dry run: it prints the plan and writes nothing.
4. Add `--execute` (with `GITHUB_TOKEN` and `OPENRC_TELEMETRY_BOT_AUTHOR`) to post. The report is recomputed and refused if its digest differs. The intent is committed first, existing issues are listed (all pages) and reconciled, and an issue is created only when none exists and no earlier create attempt is unresolved. Exit codes: 0 done or dry run, 2 refused, 3 review required, 4 unknown or pending, 5 GitHub refused.

An unknown outcome (timeout, dropped connection, 5xx) stays unknown. The next run reconciles and never creates again while the earlier attempt is unresolved. To abandon an unresolved intent after checking GitHub by hand, delete its row from `publications` in `aggregates.sqlite`. `review_required` is sticky and has no automatic exit. A weekly digest changes whenever a daily table changes, so a changed digest after an intent exists also needs review.

### TLS reverse proxy (Caddy example, unverified here)

```caddyfile
{
    servers { timeouts { read_body 10s read_header 5s } }
}
telemetry.example.org {
    log { output discard }
    request_body { max_size 32KB }
    @public path /v1/batches /healthz
    handle @public { reverse_proxy 127.0.0.1:8787 }
    handle { respond 404 }
}
```

Publish the container port on `127.0.0.1` only, set `OPENRC_TELEMETRY_TRUST_PROXY=1`, and disable or redact every proxy, WAF and journal log that could contain addresses or bodies. The service itself logs only fixed categories at warning level; bound the container log retention anyway. Expose `/v1/reports/weekly` only if a workflow needs it, and keep the token long, secret and rotated.

### Docker

```bash
docker build -f services/telemetry/Dockerfile -t openrc-telemetry .   # from the repository root
docker run -d --name telemetry -p 127.0.0.1:8787:8787 \
  -v telemetry-raw:/data/raw -v telemetry-aggregates:/data/aggregates \
  -e OPENRC_TELEMETRY_RELEASES=v0.2.9 -e OPENRC_TELEMETRY_TRUST_PROXY=1 openrc-telemetry
```

Back up only the `telemetry-aggregates` volume (`sqlite3 aggregates.sqlite ".backup out.sqlite"`, expiring with the 180-day rule). Exclude `telemetry-raw` from every backup, snapshot and replica; a tmpfs mount is acceptable because losing raw rows only loses not-yet-rolled-up days.

## Known limits

- One process and one SQLite connection per database; scale-out needs another store.
- Rate limiting is in memory per process.
- Publisher approval is a digest supplied by the operator, not an authenticated review. Issues from other authors with the same title are ignored by design, as in the publication protocol.
- Weekly output is the private-operations form only; a public release needs the inventory review in `docs/plans/telemetry/publication-protocol.md`.
- The stock-vehicle table is new relative to the reference reducer: approving a digest is also the explicit disclosure review of that table. It is suppressed whenever any vehicle (including `custom`/`unknown`) has 1–19 session tokens, so at pilot volume it will usually be suppressed.
- Days on which ingestion answered 503 (storage full) or a release was suspended are still rolled up as `ready`; there is no coverage flag in the report yet. Check that day's `storage_unavailable` and `suspended_*` counters (`ingest_counts`) before approving a report.
- A rollup aborts the whole day if any stored body no longer validates (for example after a stricter schema); rerunning after a fix is idempotent.
- Vehicle rows are re-validated at publication (floor, bounds, stock id) in addition to the rollup.
