# Receiving telemetry and delivering it through GitHub

Status: architecture and operational specification; no endpoint, account, app, workflow schedule or issue was created.
Sources: [15 GitHub investigations](../../research/telemetry/TELEM-00/github-delivery.md), [backend reuse](../../research/telemetry/TELEM-00/README.md#additional-implementation-references).

## Recommended route

Game → bounded HTTPS receiver → private short-lived records → daily rollup/disclosure gate → aggregate-only report endpoint → trusted GitHub report job.

Automatic data submission does not require a player's GitHub account. The project's engineers receive digestible reports in GitHub. A separate optional manual Issue Form path associates the report with the player's GitHub identity and is explicitly described as such.

The game never creates an issue or invokes repository_dispatch. GitHub's write APIs require credentials; a shared token in a released binary is extractable. repository_dispatch is authenticated, limited to a small payload and default-branch workflow semantics. It is not anonymous ingestion. Actions schedules are best-effort, and artifact retention does not erase issues or Git history. Detailed platform evidence and reusable actions are in G01–G15.

## Receiver implementation

Prefer a small Python/FastAPI service using the same JSON Schema 2020-12 contract and PostgreSQL transactions. FastAPI is a routing/validation framework, not a privacy control by itself. Enforce raw body and depth limits before model parsing; return fixed error categories. Use prepared statements/typed columns and separately restricted database roles. Avoid a generic “anything goes” event table.

Proposed logical records:

| Store | Fields and boundaries |
| --- | --- |
| accepted_batch | batch ID, body digest, receipt day/time for expiry, expiration; no request headers/IP |
| accepted_event | bounded schema fields, session/sequence for 48-hour dedup, receipt expiry |
| daily_rollup | day, approved release/dimension/category, coverage, summed counts/durations/histograms; no session IDs |
| publication | trusted report key, destination repo, issue number, digest and publication outcome |
| service metrics | status counts, queue depth, latency histograms, expiry lag, volume; no player labels/payloads |

Use one transaction for all event inserts plus dedup receipt. Acknowledge 202 only after commit. A DB timeout before commit returns retryable failure; an uncertain commit is resolved by the same retry identity. Unique constraints protect concurrent submissions. A full queue/database returns 429/503 before acknowledgment. Do not silently drop an acknowledged batch and still call it delivered.

Schema is independent of the client. Treat all inputs as hostile, including valid-but-fabricated values. Never log body bytes or jsonschema exception reprs: error messages can contain rejected personal data. Reject diagnostic attachment content types, arbitrary destinations and compressed bombs. The [OpenAPI proposal](../../../research/telemetry/contracts/openapi.json) has no live server.

## Anonymous ingress and abuse limits

There is no hidden secret in a public game. A static app key, version or Origin identifies a project, not a trusted client. Signed game binaries do not make a public request truthful. Do not introduce hardware attestation or stable identity just to count users.

Start with a global request/body budget, maximum concurrency and storage cap; bound parsing time and dimensions. Use an edge memory-only IP-derived limiter with a 15-minute lifetime if needed, acknowledging shared NATs and privacy impact. Do not retain a permanent IP hash or geolocation. Per-session limits are useful but bypassable through new tokens. Reject/suspend collection on sustained overload without blocking gameplay.

Test forged session storms, same-ID conflicts, a single IP behind NAT, malformed batches, oversized JSON, database outage, stale build IDs and late retries. Flag suspicious aggregate patterns for exclusion; telemetry must never drive billing, punitive decisions or automatic physics changes.

## GitHub publication

Initial recommendation: a separately chosen **private operations repository**. The current project repository is public, so automatic publication there needs a stronger disclosure review. Even a private report contains aggregates only.

Use a trusted default-branch workflow in the report repository:

1. A schedule/manual invocation asks for a **closed, precomputed report**, never raw events.
2. OIDC obtains short-lived read access to the aggregate-only endpoint when supported. Restrict audience, repository, workflow, trusted ref and environment. Otherwise use a narrowly scoped server credential with a documented rotation process.
3. Validate the aggregate schema, release allowlist, exact period, row/size caps and publication status. No ad hoc dimension query or raw storage permission is available to the job.
4. Render deterministic Markdown with a fixed renderer. Do not interpolate player/API text into shell or JavaScript source.
5. Upsert one report issue per period/release. A trusted store owns the issue number, content digest and report key; verify repository, marker and expected bot author when reconciling.
6. On an ambiguous create timeout, find/reconcile the original report before another create. Serialize by report key. Ignore an unchanged digest. Use bounded retry for rate limiting and transient errors.
7. Record the issue URL/digest and status privately. A failed update preserves the previous report; monitoring marks it stale.

For a same-repository job, GITHUB_TOKEN needs issues:write and contents:read only if checking out the renderer. id-token:write is needed only for OIDC. No administration, workflows, packages or repository contents write is required to update an issue. For an external service/cross-repository route, install a GitHub App only on the selected report repository, with Issues write and the mandatory read-only metadata permission. Keep its private key server-side; mint short-lived installation tokens.

Reuse the official actions/create-github-app-token only when that route is needed, and actions/github-script or Octokit for API calls. Pin every action to a reviewed immutable upstream commit and every package in a lockfile before activation. No exact action SHA is invented in this plan. Never run fork/PR code with publisher secrets or trust a player-provided report title.

403 must distinguish exhausted rate limits from missing permissions; 429 honors Retry-After; 401/410/422 are operational/configuration failures, not tight retry loops. Schedule delays/dropped runs need a catch-up job and stale-report alert. No reporting failure changes client consent.

## Report content and statistical use

The prepared [synthetic report](../../../research/telemetry/examples/github-report.md) shows a minimal GPU table. The full production report should include:

- Release/channel, covered closed days, missing/suppressed coverage, known sampling limitations.
- Performance by one reviewed dimension at a time, weighted rates and mergeable histogram bounds.
- Stock aircraft/activity usage counts and active time, with approved classifier/completeness labels.
- Known software error categories and service health, with clearly stated denominators.
- Candidate regressions with the compared releases, comparable settings, exposure and uncertainty.

Do not say “20 users” when the count is 20 temporary sessions. Do not average p99s or FPS values. Do not post raw session examples, arbitrary exceptions, report IDs, exact hardware strings or rare cross-products. Freeze a period's published table to limit differencing; handle later corrections as a reviewed replacement with a disclosure check. Do not expose public filter APIs for arbitrary slice queries.

Regression alerts are hypotheses. A useful starting investigation rule is a ≥10% worsening of a comparable frame-interval metric with adequate eligible exposure in each release; set sample/coverage requirements before launch and confirm on a controlled benchmark. No baseline or significance level is invented by this design. The offline model tests only a fixed GPU table; aircraft tables and statistical comparison are explicitly pending.

## Capacity and budget model

Illustrative workload, not measured traffic or a provider quote: 30 minutes per consenting session, one 2 KiB batch/minute, 30 batches/session. HTTP/TLS, database indexes, backups and retries add overhead.

| Consenting sessions/day | Requests/day | Payload/day | Average requests/s |
| --- | ---: | ---: | ---: |
| 1,000 | 30,000 | 58.6 MiB | 0.35 |
| 10,000 | 300,000 | 586 MiB | 3.47 |
| 100,000 | 3,000,000 | 5.72 GiB | 34.72 |

Benchmark a 10× traffic burst and explicit 32 KiB maximum bodies, not only the 2 KiB example. The hard client limit is 256 KiB/hour and 90 attempts/hour, including retries; modified clients can bypass it, so enforce receiver caps independently. Hosting selection must include a monthly spending ceiling and usage alerts before activation. No paid service is provisioned here.

## Operating procedures

| Incident | Immediate response | Recovery/evidence |
| --- | --- | --- |
| Unexpected field or private canary in logs | Disable ingestion/logging path; block new collection through receiver status or release config | Isolate affected retention surfaces; fix allowlist/logging; record incident and requalify |
| Retention lag or backup violates notice | Pause ingestion before accumulating more data | Purge/reconfigure; verify expiration and restore; revise notice only through review |
| Database or network outage | Return bounded failure; client expires queue | Restore private service; mark coverage gap; no client replay beyond queue lifetime |
| GitHub permission/rate/outage | Leave last valid report; mark publisher stale | Fix server permission or wait; reconcile identity before retry |
| Spam or spend spike | Edge/global cap and receiver suspension | Review filters/cost; do not add undisclosed identifiers |
| Bad telemetry release | Ship local force-off / 410 ingestion response | Keep gameplay running; fix contract and require notice review if scope changes |
| Metric no longer useful | Stop collecting it and remove from next schema/notice inventory | Purge expired data and document why it was removed |

Owner assignments before production: named service maintainer, privacy/contact owner, report reviewer and release approver. Service SLO targets for the pilot: request p95 <500 ms at admitted load, error rate reported by category, expiry lag alert before the 48-hour hard limit, and daily report freshness checked after the close window. These are proposed acceptance targets, not achieved results.

TLS, private credentials, storage encryption, least-privilege roles, log redaction and retention apply to every provider, proxy, WAF, APM, queue, replica and backup. PostgreSQL row-level security alone is insufficient: privileged/owner roles can bypass it; use explicit grants and separate publication views/roles. Do not rely on dashboards to hide rows that the publisher can still query.

## Manual GitHub path

Prepare a sanitized file locally, show it to the player, then optionally open an Issue Form. The player handles attachment/submission. GitHub identity and public-attachment visibility are stated before upload. Never auto-send a report, populate a URL with telemetry JSON, or attach the existing raw flight/diagnostics archive. The [template](../../../research/telemetry/templates/manual-report.md) is documentation-only and contains no submit action.
