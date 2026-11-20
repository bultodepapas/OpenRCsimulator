# Transparent product telemetry — implementation plan

Status: **receiver deployed and public; configured so the next tagged release offers telemetry ([activation and release checklist](#activation-and-release-checklist))**. Published builds up to v0.2.9 carry no configuration and send nothing. The [2026-11-19 audit](../research/telemetry/TELEM-AUDIT-2026-11-19/README.md) confirmed v0.2.9 ships the client without configuration, so no data has arrived, and found the reporting would stay empty at pilot volume; the [completion plan](#completion-plan-telem-1626) fixes usefulness before activation.
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

## Activation and release checklist

**State 2026-11-20: active from v0.3.0.** The owner released [v0.3.0](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.3.0) as a stable tag with telemetry configured, before the TELEM-12/13 preview cohort; the release notes state the remaining notice and overhead checks. `check-release v0.3.0` printed `ok` before tagging, and the downloaded Windows package's embedded pack contains `telemetry_release.json` with the endpoint, operator and contact below. The receiver runs on the owner's Proxmox node (HomeLab plan `2026-11-19-openrc-telemetry-primis`, CT 404) and is public at `https://openrc-telemetry.tail229a51.ts.net/v1/batches` through Tailscale Funnel from a dedicated tailnet with no grants. It accepts the series `v0.2.*` and `v0.3.*`. The repository variables `OPENRC_TELEMETRY_ENDPOINT`, `OPENRC_TELEMETRY_OPERATOR` ("OpenRC Simulator maintainers (relayed by Tailscale Funnel)") and `OPENRC_TELEMETRY_CONTACT` (the repository's Issues page) are set, so the next exact-tag CI export offers telemetry. Untagged, dirty, debug and source builds still never do. Unsetting the variables turns it off for later builds.

Qualification already done: the real Godot client (service, queue, HTTPRequest sender, TLS) delivered batches to the public endpoint from Windows, macOS (M1) and Linux, each accepted and classified; Funnel was tested from two public addresses (forwarded address overwritten, per-client limit); Tailscale log upload is disabled on the receiver node and its local journal holds no client address. An exported Windows release with a packed configuration showed the notice in the [release review](../research/telemetry/TELEM-02/README.md#exported-release-build). Still to watch on the first tagged build: the notice rendered on a Mac native panel and with a controller or radio, and frame-time overhead with telemetry on and off.

For every tag:

1. The tag must be `vX.Y.Z`, optionally `-alpha`/`-beta`/`-rc` and a number; `export.sh` refuses a configured build otherwise.
2. On the receiver host, `python -m openrc_telemetry check-release <tag>` must print `ok`. Accepted series prefixes cover new patch tags; a new minor series (for example `v0.4.*`) must be added to `OPENRC_TELEMETRY_RELEASES` first.
3. After the CI export, the package's `.pck` contains `telemetry_release.json` (the audit found it absent in v0.2.9).
4. Within a day of publication, `status` shows `accepted` counters and the [health workflow](../../.github/workflows/telemetry-health.yml) is green.
5. Weekly, after Monday 23:00 UTC: `insights --week <week> --release <tag>` (per-cell floor) and, for the conservative public form, `report`. Review before anything leaves the operations repository.

Players can always turn telemetry off in Settings → Interface; `OPENRC_TELEMETRY_DISABLE=1` forces it off for a launch. Other languages become available only after a reviewed notice ([languages](telemetry/consent.md#languages)).

**While active, every release and engine change has telemetry steps.** A tag outside the accepted series is refused (422) and its batches are dropped; `rejected:unapproved_release` in `status` shows it. To withdraw a release, add it to `OPENRC_TELEMETRY_SUSPEND_RELEASES` (410: those clients stop for the rest of their session). A Godot minor upgrade changes `engine_minor`. Until the schema (`generate_contracts.py`), the client constant and the receiver are updated together, the new builds stay unavailable (fail closed). A new stock vehicle reports as `unknown` until it is added to the schema; `test_telemetry_contract` fails as a reminder. `app/app_root.gd` is pinned by the AI-companion behavior manifest, so an edit there also needs the AFC-02 pin renewal.

History: the design preparation merged as TELEM-00/01 after the [final finding dispositions](../research/telemetry/TELEM-00-R1/review.md#final-merge-preparation-review) and a [main-integration re-check](../research/telemetry/TELEM-00-R1/verification.md#main-integration).

## Completion plan (TELEM-16…26)

From the [2026-11-19 audit](../research/telemetry/TELEM-AUDIT-2026-11-19/README.md) (finding IDs U/R). **Order matters:** phase 6 changes the schema and the notice, which reset consent grants and split the data series; doing it before anyone has granted costs nothing. Each step ends with its evidence; "before → after" is the improvement proof.

### Phase 6 — data that answers questions (before activation, about 5–7 days)

| Step | Work | Evidence of improvement / completion |
| --- | --- | --- |
| TELEM-16 | **Publishable reports (U1).** Rollup stores every daily cell with its session count in the operator-only aggregate database; suppression moves to the report: per cell, sub-floor cells merge into one combined row that is published only if it reaches the floor. Weekly cells pool daily cells. Private-operations floor configurable down to 10 and labelled; public floor stays 20 | **Done 2026-11-19** (`insights.py`, `insights` command): fixture of 60 sessions/day in a six-family mix — **before 0 rows published, after the 30-session family plus a combined row of 30**; a week shows four families and folds the lone 7-session cell with the smallest shown one, so every table adds up to its population (no withheld remainder for cross-table differencing); one forged odd batch no longer hides the day. Operator-only (Good Enemy review: nested-dimension differencing, session-day floor). The v2 report and reference equivalence are unchanged. `test_insights` 13 tests, receiver suite 132 OK |
| TELEM-17 | **Aggregate what is already sent (U2).** Tables: hardware mix, cadence by GPU family, pacing class, resolution class, OS/driver and vehicle, Home/menu cadence, vehicle usage, error categories, input class | **Done 2026-11-19:** 5 flight-cadence, 1 menu-cadence, usage, error and 9 mix tables (data contract, receiver README). `gpu_ms` stays in the schema as `not_measured` until a GPU timer is qualified |
| TELEM-18 | **Client context (U4).** Resolution as pixel-count bands so 16:10, MacBook panels, ultrawide and windowed sizes are classified, without a schema or notice change | **Done 2026-11-19 (minimal):** `test_telemetry_contract` checks 17 sizes. Deferred to a later schema v2 with a notice review: aspect and Retina scale, render scale, flight backend, preset name, GPU tiers (they need `app_root.gd`, pinned by the companion manifest). **Flight backend delivered in schema v2 / notice 2026-11-20** ([DECISIONS](../DECISIONS.md#telemetry-schema-v2-reports-the-physics-backend)); the others remain deferred |
| TELEM-19 | **Usage survives quitting in flight (R4).** Emit an activity slice every 5 minutes of flight without changing the "quit drops pending data" rule | **Done 2026-11-19:** slice 30 → 5 min; `test_telemetry_service` "quitting a 12-minute flight keeps two 5-minute slices" (before: 0 summaries); contract, app and receiver suites pass |
| TELEM-20 | **Receiver observability and safe defaults (R1–R3).** ID-free daily counters per status/reason, `status` and `check-release <tag>` CLI commands; public `/healthz` stays minimal because behind Funnel every request is local | **Done 2026-11-19:** counters (`rejected:unapproved_release`, `rate_limited`, `forwarded_for_present`, …) flushed every minute, `status` exits 1 on a retention breach, `check-release` refuses unlisted, suspended or malformed tags; `test_observability` 9 tests, receiver suite 118 OK including the Godot end to end. Proxy trust stays an explicit deployment check |

### Phase 7 — deploy the receiver (owner decisions plus about 1–2 days)

| Step | Work | Evidence |
| --- | --- | --- |
| TELEM-21a | **Owner decisions:** operator name, contact, processing location, private operations repository, private floor. Hosting decided 2026-11-19: the owner's always-on Proxmox node, no cost | Recorded in [DECISIONS.md](../DECISIONS.md) and the notice |
| TELEM-21b | **Deploy** in an unprivileged LXC on the owner's Proxmox node, published with Tailscale Funnel (public HTTPS, no open ports). Deployment, isolation and operation are owned by the owner's HomeLab repository (plan `2026-11-19-openrc-telemetry-primis`). **Done 2026-11-19/20:** receiver suite 119 OK inside the container (Debian Python 3.13.5), loopback service with systemd hardening, raw on a volume excluded from backups, egress firewall, daily rollup timer; a **dedicated tailnet with no grants** holds only this tagged, non-expiring node; public endpoint **`https://openrc-telemetry.tail229a51.ts.net/v1/batches`** (permanent once a release carries it) | From two public addresses: `/healthz` 200; canonical example 202, replay 202, unapproved release 422; Funnel sends one `X-Forwarded-For` and overwrites forged values, so `TRUST_PROXY=1` and the per-client 429 hit only the bursting client. The live test found counters lost on `systemctl stop` (uvicorn re-raises SIGTERM); fixed with a lifespan flush and a regression test |
| TELEM-21c | **"Is data arriving?"** A light daily public check, plus `status` on the host for counters and data age | **Done 2026-11-19:** [telemetry-health.yml](../../.github/workflows/telemetry-health.yml) checks `/healthz` daily once the endpoint variable is set (a failed scheduled run is the email alert); `status` shows last-batch age, rejection counters and the retention check |

### Phase 8 — activate in a preview release (about 2 days plus one beta week)

| Step | Work | Evidence |
| --- | --- | --- |
| TELEM-22a | Set the three repository variables; add the tag to the allowlist and run `check-release` before tagging the next preview | **Done 2026-11-20 with v0.3.0:** `check-release` ok; the downloaded Windows package contains `telemetry_release.json` (v0.2.9 had none) |
| TELEM-12 | Package qualification: Windows at 1920×1080, Linux, macOS on ANGEL's native panel; notice with keyboard, gamepad and radio; Enable, decline, Settings off; frame-time overhead on versus off on the same flight tape | One accepted batch per OS in the deployed receiver; overhead within run-to-run noise; screenshots kept outside Git |
| TELEM-13 | One-week volunteer cohort and runbook rehearsal (purge, rollup, suspend, withdraw a release) | Batches every day, 429 rate 0, rejections under 1 %, daily rollups `ready`, runbook steps timed |

### Phase 9 — GitHub reports and dashboard (about 3 days)

| Step | Work | Evidence |
| --- | --- | --- |
| TELEM-23 | **Weekly report through the operations repository.** A scheduled workflow there fetches the week's report and aggregate JSON (bearer token kept as a repository secret), commits `data/<week>.json` and opens a pull request; merging is the human review, then it files the issue. Keep the digest-bound publisher only if the workflow cannot meet the publication protocol | First real week produces a pull request and an issue with at least one published table |
| TELEM-24 | **Dashboard.** Static page in the operations repository built by Actions from `data/*.json` (Chart.js or Observable Plot): data health, sessions by OS and release, hardware mix, share of frames over 33.3/50 ms and hitches per minute by GPU family × cap class × resolution, aircraft usage and completion, error categories. Private until TELEM-26: GitHub Pages from a private repository is public unless on Enterprise Cloud, so view it as a workflow artifact or behind Cloudflare Access | Renders from the fixture and from the first real week; no cell below the floor in the built output (checked by the build). **TELEM-24a done 2026-11-20:** local operator view over SSH, [tools/telemetry](../../tools/telemetry/README.md), floor-checked through `insights.collect`. **TELEM-24c proposed:** always-on private host for that view. A `dashboard.py build` command reads a receiver snapshot file pushed by the Proxmox host and writes the page and `health.json` atomically. It runs on timers in its own container on the owner's personal tailnet and is served by Tailscale Serve to the owner only. Plan in the HomeLab repository (`docs/plans/2026-11-20-openrc-stats-primis.md`) |

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
