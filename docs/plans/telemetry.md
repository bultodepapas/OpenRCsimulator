# Transparent product telemetry — implementation plan

Status: **client, receiver, rollup, report and publisher implemented and tested (TELEM-02…11); inactive in every build until the [activation steps](#merge-readiness-versus-activation) (TELEM-12…14)**. No receiving service is deployed and no build offers telemetry yet. The [2026-11-19 audit](../research/telemetry/TELEM-AUDIT-2026-11-19/README.md) confirmed v0.2.9 ships the client without configuration, so no data has arrived, and found the reporting would stay empty at pilot volume; the [completion plan](#completion-plan-telem-1626) fixes usefulness before activation.
Dated 2026-11-18. Telemetry design baseline: [39fa2746](https://github.com/bultodepapas/OpenRCsimulator/commit/39fa2746ae4f4ba8698b87db279adcfe84ef5d17). TELEM-00/01 was merged into main the same day; current-main interface references were re-checked against main [35787fb5](https://github.com/bultodepapas/OpenRCsimulator/commit/35787fb583f3b654b28381c951783be7a85be0e0) ([main integration](../research/telemetry/TELEM-00-R1/verification.md#main-integration)). The merge is not a runtime-qualified build.
Track: **TELEM-00…26**. Owner: product telemetry lead; UI, PT/VQ, UI-FS, DT and infrastructure maintainers own their existing interfaces.

## Outcome

Learn which supported machines struggle, where frame cadence deteriorates, which stock aircraft people actually fly, and which release changes deserve attention. Return actionable engineering summaries through GitHub. Keep the simulator fully usable when telemetry is declined, unavailable, or disabled.

The enabled choice is recommended on first launch, but **collection and transmission begin only after an explicit enabling action**. Every later eligible launch shows the actual telemetry state and a Settings link. There is no permanent player, installation, device, or account identifier. Raw minimized session reports are treated as potentially identifiable; only reviewed aggregates reach GitHub. Do not advertise guaranteed anonymity.

The requested enabled-by-default experience is represented by a visibly recommended enabled choice, not automatic first-run collection. Only a deliberate, telemetry-specific Enable action grants it; a generic Continue, a preselection or input held as the notice appears cannot. A stored enabled preference can start collection automatically on subsequent eligible launches only while the notice and locale remain qualified. The consent rationale and exact copy live in [consent](telemetry/consent.md).

## Read in this order

| Need | Authoritative home |
| --- | --- |
| Decisions, phases and backlog | This plan |
| Reuse, architecture, interfaces, lifecycle and transport | [Architecture](telemetry/architecture.md) |
| First-run, startup and Settings copy, EN/ES | [Consent and privacy](telemetry/consent.md) |
| Events, hardware, measurement semantics and retention | [Data contract](telemetry/data-contract.md) |
| Receiving data, GitHub reports, abuse and operational ownership | [Delivery and operations](telemetry/delivery.md) |
| Acceptance tests and hardware qualification | [Verification](telemetry/verification.md) |
| 38 independent research questions, alternatives and source audit | [TELEM-00 evidence](../research/telemetry/TELEM-00/README.md) |
| Adaptive follow-up: ten, review, ten targeted, ten unconventional | [TELEM-00-R1 evidence](../research/telemetry/TELEM-00-R1/README.md) |
| Established test tools, fault experiments and measurement counterexamples | [Validation laboratory](telemetry/validation-lab.md) |
| Frozen disclosures, review receipts and uncertain GitHub writes | [Publication protocol](telemetry/publication-protocol.md) |
| Schemas, fixtures and executable offline reference | [Implementation starter](../../research/telemetry/README.md) |

## Decisions ready for implementation

1. Reuse Godot HTTPRequest and the existing monotonic measurement semantics, catalogs, accepted lifecycle receipts and UI shell. Build a small GDScript policy/serialization adapter. Do not copy raw diagnostic dictionaries or the local flight-history database.
2. Send bounded JSON over HTTPS to an operator-controlled collector. Use established schema validation and database software; do not develop authentication, a database engine, or an analytics SDK.
3. The pilot receiver is a small Python Starlette/uvicorn service with jsonschema and SQLite: one raw database that is never backed up and expires within 48 hours, one ID-free aggregate database ([delivery](telemetry/delivery.md#receiver-implementation)). PostgreSQL remains the documented path if one node cannot carry the admitted volume. Choose hosting only after its IP/logging, retention, region and cost controls are documented.
4. GitHub receives periodic summaries. A trusted workflow uses its own GITHUB_TOKEN for a same-repository report; a GitHub App is the alternative for an external/cross-repository publisher. Never embed a GitHub token in the game.
5. Base mode has coarse hardware categories, frame-cadence summaries, stock aircraft/activity usage and bounded error categories. Crash dumps, exact hardware diagnostics and user-provided text belong to a separate reviewed manual flow.
6. Source/editor, headless, technical/direct-argument and automation runs are off by default and cannot use production ingestion. A no-argument exported GUI launched from a terminal is indistinguishable from the same GUI launched by a shortcut.
7. No disk spool in v1. A small memory queue favors privacy and simple revocation over guaranteed event delivery. All reports are best-effort observations, never a census.
8. Use unpartitioned logged raw/dedup tables for the small pilot candidate, with global uniqueness and indexed expiry. A receipt-day partition key must not weaken cross-day deduplication. SQL deletion and backup age alone cannot qualify the 48-hour storage promise; raw-copy isolation and erasure feasibility remain explicit deployment gates.
9. Freeze a reviewed report snapshot. Persist publication intent before a remote write, preserve an unknown outcome and reconcile it; never blindly repeat an ambiguous create. Public review binds the exact destination, expected author, title/body content digest and relevant disclosure inventory. The offline model does not authenticate reviewers or provide durable coordination.

The [decision record](../DECISIONS.md#transparent-telemetry-as-a-separate-product-data-boundary) records the credible alternatives and revisit conditions.

## Phases and independently reviewable steps

Effort ranges are planning estimates for one experienced engineer with timely reviews, not delivery promises. Release gates depend on real hardware and deployment evidence.

| Phase / estimate | Step | Work | Dependency | Proof / present status |
| --- | --- | --- | --- | --- |
| 0 — evidence and contract, 2–3 days | TELEM-00 | Source audit and external investigations; privacy and GitHub alternatives | Baseline repository | **Delivered:** original 38 plus the adaptive follow-up; see its register and integration evidence |
| 0 | TELEM-01 | Versioned data/consent/API contracts, adversarial fixtures and offline reference | TELEM-00 | **Delivered as prototype:** see test evidence; no production integration |
| 1 — local consent and measurement, 4–6 days | TELEM-02 | Consent store, forced-off policy, generation fencing, no-network stub | TELEM-01; UI/DT | **Implemented:** policy, release/route gating, consent file, generation fence; admission and service tests |
| 1 | TELEM-03 | First-launch panel, startup state, Settings privacy controls, exact preview, translations | TELEM-02; UI/i18n | **Implemented:** notice, Home status, Settings → Interface, preview; all nine languages translated, EN/ES reviewed. Rendered, controller, large-scale and screen-reader review pending |
| 1 | TELEM-04 | Read-only frame observer, hardware classifier and effective graphics snapshot | TELEM-02; PT/VQ | **Implemented:** windows, classifier and graphics profile (current default or custom). Target-hardware overhead campaign pending |
| 1 | TELEM-05 | Accepted activity summaries and allowlisted aircraft/context projection | TELEM-04; UI-FS/vehicle owners | **Implemented:** summaries with accepted fixed-wing counts, reset, slice and custom; real AppRoot flight test |
| 2 — bounded delivery, 3–5 days | TELEM-06 | Memory queue, one-request sender, deadlines, retry budget and revocation races | TELEM-02/04/05 | **Implemented:** loopback HTTP tests (202, 429 Retry-After, redirect, silent peer, refused, cancel). TLS against the deployed endpoint pending |
| 2 | TELEM-07 | Sanitized export/preview, separate manual GitHub report route | TELEM-03/06 | Exact preview implemented; manual GitHub report route pending |
| 3 — receiving service, 4–7 days | TELEM-08 | Private ingestion, schema/semantic validation, idempotent transaction, overload limits | TELEM-01/06; operator choices | **Implemented:** [services/telemetry](../../services/telemetry/README.md); status, dedup, conflict and rate tests, reference equivalence, Godot end-to-end |
| 3 | TELEM-09 | Indexed expiry, raw/aggregate storage separation, restricted roles, safe error logs and service monitoring | TELEM-08 | **Implemented:** separate raw/aggregate files, purge with secure delete and WAL truncation, category-only logs. Host backup/log configuration evidence pending deployment |
| 4 — useful GitHub feedback, 3–5 days | TELEM-10 | Daily rollups and fixed weekly aggregate tables with disclosure gates | TELEM-09 | **Implemented:** daily GPU and vehicle tables with whole-table suppression below 20 sessions; weekly pooling. Real-volume review pending |
| 4 | TELEM-11 | Deterministic renderer, frozen review record and recoverable GitHub publisher | TELEM-10 | **Implemented:** digest-bound publisher with durable intent and reconcile (fake GitHub tests). Real repository and permission run pending |
| 5 — qualification and rollout, 4–7 days plus beta time | TELEM-12 | Cross-platform release-package consent, network and performance qualification | TELEM-02…11 | Windows/Linux/macOS, 1080p-first except Apple Silicon Retina native-panel evidence; pending |
| 5 | TELEM-13 | Small volunteer preview cohort and maintenance runbook rehearsal | TELEM-12 | Observed payloads, bounded costs, real off-switch, operator response; pending |
| 5 | TELEM-14 | Enable the approved release configuration and publish the notice | TELEM-13; completed deployment/privacy gates | Release owner accepts exact build, endpoint and notice; pending |
| 5 | TELEM-15 | First release comparison, metric review, deletion drill and quarterly pruning | TELEM-14 | Actionable regression report and unused-field removal; pending |

Do not gate gameplay on ingestion availability. Remaining work (TELEM-07 manual reports, TELEM-12…15) is operational qualification, not new architecture.

## Implementation (TELEM-02…11)

| Part | Where | Verification |
| --- | --- | --- |
| Client contract, policy, release gate, consent file, classifier, windows, queue, sender, service | [app/telemetry/](../../app/telemetry/) | `test_telemetry_contract`, `_admission`, `_queue`, `_service`, `_sender` (golden byte equality with the generated example, schema parity, loopback HTTP) |
| First-launch notice, Home status, Settings → Interface, preview, privacy notice, translations | [telemetry_screen.gd](../../app/ui/telemetry_screen.gd), [settings_screen.gd](../../app/ui/settings_screen.gd), `app/i18n/*.po` | `test_telemetry_app` through the real AppRoot, including a flight round trip; existing Settings, Home, language and update tests unchanged |
| Release configuration | [export_plugin.gd](../../app/addons/build_info/export_plugin.gd) packs `res://telemetry_release.json` from `OPENRC_TELEMETRY_ENDPOINT/_OPERATOR/_CONTACT`; [CI](../../.github/workflows/ci.yml) passes repository variables of those names | Runtime refuses development, debug-template, dirty, untagged and manual exports and partial configuration |
| Receiver, rollup, weekly report, GitHub publisher | [services/telemetry](../../services/telemetry/README.md) | Receiver suite, reference equivalence, Godot client end to end; [contracts CI](../../.github/workflows/telemetry-contracts.yml) |

Evidence and limits: [TELEM-02…11 verification](../research/telemetry/TELEM-02/README.md).

## Merge readiness versus activation

Merged code collects nothing: no build carries a release configuration, so every build reports telemetry as unavailable and creates no service node. Activation is an operator decision, in this order:

1. **Operator and notice (owner).** Name the operator, a contact and the processing region; confirm the notice text in [consent](telemetry/consent.md) still matches the deployment.
2. **Deploy the receiver (TELEM-12).** Follow [services/telemetry](../../services/telemetry/README.md): TLS proxy, `OPENRC_TELEMETRY_RELEASES` allowlist with the next tag, hourly `purge`, daily `rollup`, back up `aggregates.sqlite` only, and proxy/host logs without IP addresses or bodies (or deleted within 15 minutes). Check `/healthz` and send the canonical example once.
3. **Configure releases.** Set the repository variables `OPENRC_TELEMETRY_ENDPOINT` (the HTTPS `/v1/batches` URL), `OPENRC_TELEMETRY_OPERATOR` and `OPENRC_TELEMETRY_CONTACT`. The next exact-tag export offers telemetry; untagged builds still do not. Unset variables turn it off again for later builds. `export.sh` refuses a build whose variables are partial, whose endpoint the game would refuse (it needs `https://host/path`, not loopback) or whose tag the client cannot offer telemetry from (`vX.Y.Z`, optionally `-alpha`/`-beta`/`-rc` and a number), so a configured release never ships with telemetry silently off.
4. **Qualify a release candidate (TELEM-12/13).** On Windows, Linux and macOS: the notice at 1920×1080 first (Apple Silicon Retina at native panel resolution), Enable/decline/off, preview contents, receiver rows, frame-time overhead with telemetry on and off. A small volunteer preview precedes a stable release (TELEM-14).
5. **Weekly report (TELEM-11).** Expect suppressed tables at first: a day's GPU table is published only when every GPU family seen that day has at least 20 sessions (the vehicle table likewise per vehicle). `rollup` each closed day, `report` the closed week after Monday 23:00 UTC (when no day can change), review it (including the stock-vehicle table's disclosure), then `publish --approved-digest <digest> --execute` to a private operations repository first.

Players can always turn telemetry off in Settings → Interface; `OPENRC_TELEMETRY_DISABLE=1` forces it off for a launch. Other languages become available only after a reviewed notice ([languages](telemetry/consent.md#languages)).

**While active, every release and engine change has telemetry steps.** Before publishing a tag, add it to the receiver's `OPENRC_TELEMETRY_RELEASES`; otherwise its batches are refused (422) and dropped. To withdraw a release, add it to `OPENRC_TELEMETRY_SUSPEND_RELEASES` (410: those clients stop for the rest of their session). A Godot minor upgrade changes `engine_minor`. Until the schema (`generate_contracts.py`), the client constant and the receiver are updated together, the new builds stay unavailable (fail closed). A new stock vehicle reports as `unknown` until it is added to the schema; `test_telemetry_contract` fails as a reminder. `app/app_root.gd` is pinned by the AI-companion behavior manifest, so an edit there also needs the AFC-02 pin renewal.

History: the design preparation merged as TELEM-00/01 after the [final finding dispositions](../research/telemetry/TELEM-00-R1/review.md#final-merge-preparation-review) and a [main-integration re-check](../research/telemetry/TELEM-00-R1/verification.md#main-integration).

## Completion plan (TELEM-16…26)

From the [2026-11-19 audit](../research/telemetry/TELEM-AUDIT-2026-11-19/README.md) (finding IDs U/R). **Order matters:** phase 6 changes the schema and the notice, which reset consent grants and split the data series; doing it before anyone has granted costs nothing. Each step ends with its evidence; "before → after" is the improvement proof.

### Phase 6 — data that answers questions (before activation, about 5–7 days)

| Step | Work | Evidence of improvement / completion |
| --- | --- | --- |
| TELEM-16 | **Publishable reports (U1).** Rollup stores every daily cell with its session count in the operator-only aggregate database; suppression moves to the report: per cell, sub-floor families merge into one `other` row that is published only if it reaches the floor. Weekly cells pool daily cells. Private-operations floor configurable down to 10 and labelled; public floor stays 20. Record 503/suspended days as partial coverage (R6) | Fixture of 60 sessions/day in a realistic six-family mix: **before 0 rows published, after ≥3 family rows plus `other`**; one forged odd-family batch no longer suppresses the day; reference equivalence updated |
| TELEM-17 | **Aggregate what is already sent (U2).** Tables: hardware mix (OS × CPU family × RAM, threads), cadence by GPU family × cap class (VSync on or cap ≤60 versus uncapped) × resolution class, Home/menu cadence, error categories, input class. Drop or implement `gpu_ms` | Report v3 shows each table from the fixture; every context field has a consumer table or is removed from the schema (field inventory in the data contract) |
| TELEM-18 | **Client context v2 (U3, U4, U5).** Resolution as drawable-pixel band plus aspect (16:9, 16:10, other) and Retina scale; 3D render scale/upscaler bucket; flight backend (`native`/`reference`); graphics preset name; GPU tier split where names allow (RTX x050/x060/x070+, MX/GT/workstation). Schema v2 and `NOTICE_VERSION` bump in all three implementations | Rendered run on ANGEL's native panel reports `16:10`, 2× and the backing-pixel band (settles points versus pixels); a stale-native run reports `reference`; contract, admission and service suites pass on Windows and macOS |
| TELEM-19 | **Usage survives quitting in flight (R4).** Emit an activity slice every 5 minutes of flight without changing the "quit drops pending data" rule | **Done 2026-11-19:** slice 30 → 5 min; `test_telemetry_service` "quitting a 12-minute flight keeps two 5-minute slices" (before: 0 summaries); contract, app and receiver suites pass |
| TELEM-20 | **Receiver observability and safe defaults (R1–R3).** ID-free daily counters per status/reason, `status` and `check-release <tag>` CLI commands; public `/healthz` stays minimal because behind Funnel every request is local | **Done 2026-11-19:** counters (`rejected:unapproved_release`, `rate_limited`, `forwarded_for_present`, …) flushed every minute, `status` exits 1 on a retention breach, `check-release` refuses unlisted, suspended or malformed tags; `test_observability` 9 tests, receiver suite 118 OK including the Godot end to end. Proxy trust stays an explicit deployment check |

### Phase 7 — deploy the receiver (owner decisions plus about 1–2 days)

| Step | Work | Evidence |
| --- | --- | --- |
| TELEM-21a | **Owner decisions:** operator name, contact, processing location, private operations repository, private floor. Hosting decided 2026-11-19: the owner's always-on Proxmox node, no cost | Recorded in [DECISIONS.md](../DECISIONS.md) and the notice |
| TELEM-21b | **Deploy** in an unprivileged LXC on the owner's Proxmox node, published with Tailscale Funnel (public HTTPS, no open ports). Deployment, isolation and operation are owned by the owner's HomeLab repository (plan `2026-11-19-openrc-telemetry-primis`). **Done 2026-11-19:** container created, receiver suite 109 OK inside it (Debian Python 3.13.5), loopback service with systemd hardening, raw on a volume excluded from backups, egress firewall tested, daily rollup timer. **Gate before Funnel:** a node identity with no access to the rest of the tailnet (separate tailnet recommended, or a tag with a deny ACL) and key expiry disabled, because the URL is baked into releases | `/healthz` and the canonical example 202 from outside the tailnet; `X-Forwarded-For` behaviour tested from two external addresses and with a forged header, then `TRUST_PROXY` or per-client limits set; tailnet isolation tested |
| TELEM-21c | **"Is data arriving?"** Free uptime monitor on `/healthz`; a scheduled workflow in the operations repository opens an issue when the last batch is older than 48 hours or rejections exceed 5 % | Monitor alert received after a deliberate stop; stale-data issue opened by a forced test |

### Phase 8 — activate in a preview release (about 2 days plus one beta week)

| Step | Work | Evidence |
| --- | --- | --- |
| TELEM-22a | Set the three repository variables; add the tag to the allowlist and run `check-release` before tagging the next preview | Each package contains `telemetry_release.json` (the audit found 0 matches in v0.2.9's `.pck`) |
| TELEM-12 | Package qualification: Windows at 1920×1080, Linux, macOS on ANGEL's native panel; notice with keyboard, gamepad and radio; Enable, decline, Settings off; frame-time overhead on versus off on the same flight tape | One accepted batch per OS in the deployed receiver; overhead within run-to-run noise; screenshots kept outside Git |
| TELEM-13 | One-week volunteer cohort and runbook rehearsal (purge, rollup, suspend, withdraw a release) | Batches every day, 429 rate 0, rejections under 1 %, daily rollups `ready`, runbook steps timed |

### Phase 9 — GitHub reports and dashboard (about 3 days)

| Step | Work | Evidence |
| --- | --- | --- |
| TELEM-23 | **Weekly report through the operations repository.** A scheduled workflow there fetches the week's report and aggregate JSON (bearer token kept as a repository secret), commits `data/<week>.json` and opens a pull request; merging is the human review, then it files the issue. Keep the digest-bound publisher only if the workflow cannot meet the publication protocol | First real week produces a pull request and an issue with at least one published table |
| TELEM-24 | **Dashboard.** Static page in the operations repository built by Actions from `data/*.json` (Chart.js or Observable Plot): data health, sessions by OS and release, hardware mix, share of frames over 33.3/50 ms and hitches per minute by GPU family × cap class × resolution, aircraft usage and completion, error categories. Private until TELEM-26: GitHub Pages from a private repository is public unless on Enterprise Cloud, so view it as a workflow artifact or behind Cloudflare Access | Renders from the fixture and from the first real week; no cell below the floor in the built output (checked by the build) |

### Phase 10 — stable release and ongoing value

| Step | Work | Evidence |
| --- | --- | --- |
| TELEM-14 | Enable the approved configuration in a stable release | Release checklist completed |
| TELEM-15 | First release-to-release comparison, deletion drill, quarterly field pruning | A regression or improvement report a maintainer acted on; no raw row older than 48 h; unused fields removed |
| TELEM-25 | Manual GitHub report route (TELEM-07) for exact hardware and crashes, opt-in per report | Player-submitted issue from the preview with only allowlisted fields |
| TELEM-26 | Optional public summary in the OpenTTD style (weekly, per release, floor 20, non-representative warning) after four reviewed private weeks | Public page reviewed against the [publication protocol](telemetry/publication-protocol.md) |

**Telemetry is complete** when a stable release sends, four consecutive weekly reports contain published tables, the dashboard updates without manual steps, both alerts have fired in tests, the deletion drill has passed, and every collected field feeds a report table.

## Decisions that remain before deployment

| Decision | Recommended starting point | Why it remains open |
| --- | --- | --- |
| Operator, contact and processing region | Project-maintained notice with named contact | Not present in the task; never invent legal identity |
| Hosting and operational budget | **Decided 2026-11-19:** owner's Proxmox node with Tailscale Funnel, no cost; Fly.io and Cloudflare Workers compared in the [audit](../research/telemetry/TELEM-AUDIT-2026-11-19/README.md#external-inputs-checked-2026-11-19-prices-change) | Actual vendor logs, region, deletion and billing must be checked |
| Raw-copy retention feasibility | Isolate raw records from longer-lived aggregate backups; prove all readable copies meet their original deadlines | SQL TTL, pgBackRest retention, a separate database in the same cluster and restore filtering do not establish erasure |
| GitHub destination | Separate private operations repository initially | Current project repository is public; its audience is broader |
| Public report release | Manual review of each early report | Small cohorts and linked dimensions can reveal more than intended |
| Optional exact-hardware/crash support | Manual preview/export first; Sentry only after separate audit | Broader data and native crash paths need separate disclosure |
| Additional hardware generations / metric categories | Add only after a stated engineering question | Avoid arbitrary strings, cardinality growth and scope creep |

These decisions do not block the local adapter, UI, schemas or tests. They block production activation, not this planning branch.

## Success criteria and limits

- Every supported release can fly indefinitely with telemetry off or the receiver unavailable.
- We can investigate cadence by release, broad hardware and stock aircraft without tracking people across launches; the initial context cannot establish detailed graphics-setting comparability or causation.
- Each telemetry field has a documented purpose, finite representation and removal/review owner.
- The UI, wire data, logging stack and actual retention agree.
- Automatic telemetry never posts an event, token or player session directly to public GitHub. The optional manual route uses its separate reviewed allowlist and player submission.
- Observations cover consenting sessions only. We cannot infer total players, unique machines, retention, crashes not observed, or causal performance improvements from these samples alone.
