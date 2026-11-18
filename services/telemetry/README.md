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
| `openrc_telemetry/cli.py`, `__main__.py` | `serve`, `purge`, `rollup`, `report`, `publish` |
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
| `OPENRC_TELEMETRY_RELEASES` | empty | Comma list of accepted `build.release_id` values |
| `OPENRC_TELEMETRY_SUSPEND_RELEASES` | empty | Releases answered with `410`: clients stop collecting for the rest of their process; nothing is stored |
| `OPENRC_TELEMETRY_SUSPEND_ALL` | unset | `1` answers every batch with `410` (operator off switch) |
| `OPENRC_TELEMETRY_PURGE_INTERVAL_S` | `300` | `serve` purges raw rows this often, cutting interval + 60 s before 48 h so no row outlives 48 h |
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
- `aggregates.sqlite` holds ID-free daily tables, daily status rows and publication intents. It never contains a session or batch ID.
- **Raw data must never be backed up** (nor snapshotted, replicated or copied: `raw.sqlite`, `raw.sqlite-wal`, `raw.sqlite-shm`). The data contract promises at most 48 hours per record across every copy.
- `purge` deletes raw rows whose receipt is 48 h old or older (exactly 48 h counts as expired), then runs `incremental_vacuum` and `wal_checkpoint(TRUNCATE)`; it also removes aggregate rows older than 180 days. It is idempotent. Exit code 1 with a warning means a reader blocked the checkpoint; rerun it.
- Dedup protection ends with the record's expiry, as documented in the data contract.

## Operations

`serve` purges by itself at start and every `OPENRC_TELEMETRY_PURGE_INTERVAL_S`. Run the other jobs from cron or a systemd timer next to the service. In Docker use `docker exec <container> python -m openrc_telemetry ...` so the commands share the container's SQLite WAL index.

| Job | Schedule (UTC) | Command |
| --- | --- | --- |
| Purge (second line of defence) | hourly; alert if the oldest raw row nears 48 h | `python -m openrc_telemetry purge` |
| Daily rollup | every day 01:30 | `python -m openrc_telemetry rollup --day yesterday` |
| Weekly report | Monday, after the Sunday rollup | `python -m openrc_telemetry report --week 2026-W47 --release v0.2.7` |

Rollup works only for a closed day: from day end + 1 h until day start + 47 h. Outside that window it refuses with an explanation; a missed deadline yields a missing day, never extended raw retention. It is an idempotent upsert keyed by (day, release, table). Tables are suppressed as a whole when any cell has fewer than 20 distinct session tokens; each token counts at most 120 windows (or activity summaries).

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
