# Transparent product telemetry — implementation plan

Status: **design and offline contract prototype; no product-telemetry collection, service, or publisher deployed**.
Dated 2026-11-18. Telemetry design baseline: [39fa2746](https://github.com/bultodepapas/OpenRCsimulator/commit/39fa2746ae4f4ba8698b87db279adcfe84ef5d17); the offline telemetry branch is based on that snapshot. Compatibility was also source-reviewed against newer main [d407acd](https://github.com/bultodepapas/OpenRCsimulator/commit/d407acd9da55dc49d6e1e0442a81f3b6d7657591); that is not a claim of a merged or runtime-qualified build.
Track: **TELEM-00…15**. Owner: product telemetry lead; UI, PT/VQ, UI-FS, DT and infrastructure maintainers own their existing interfaces.

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
3. Prefer a small Python/FastAPI ingress plus jsonschema and PostgreSQL for the pilot. Choose hosting only after its IP/logging, retention, region and cost controls are documented. The offline prototype uses jsonschema, not a custom schema validator. No server dependency is installed or selected as a production pin by this branch.
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
| 1 — local consent and measurement, 4–6 days | TELEM-02 | Consent store, forced-off policy, generation fencing, no-network stub | TELEM-01; UI/DT | Unit/packet tests prove zero telemetry before grant and after decline; pending |
| 1 | TELEM-03 | First-launch panel, startup state, Settings privacy page, exact preview, translations | TELEM-02; UI/i18n | Reviewed notices and keyboard/controller/scale review in each enabled locale; 1080p-first except native Retina target; pending |
| 1 | TELEM-04 | Read-only frame observer, hardware classifier and effective graphics snapshot | TELEM-02; PT/VQ | Known-trace calculations, availability matrix and overhead campaign; pending |
| 1 | TELEM-05 | Accepted activity summaries and allowlisted aircraft/context projection | TELEM-04; UI-FS/vehicle owners | Rejected launch, restart, pause, custom aircraft and unsupported classifier tests; pending |
| 2 — bounded delivery, 3–5 days | TELEM-06 | Memory queue, one-request sender, deadlines, retry budget and revocation races | TELEM-02/04/05 | Silent peer, TLS, redirects, 429, offline and shutdown harness; pending |
| 2 | TELEM-07 | Sanitized export/preview, separate manual GitHub report route | TELEM-03/06 | No automatic browser upload, no payload in URL; GitHub identity warning; pending |
| 3 — receiving service, 4–7 days | TELEM-08 | Private ingestion, schema/semantic validation, idempotent transaction, overload limits | TELEM-01/06; operator choices | Fault injection + duplicate/conflict/race tests against selected database; pending |
| 3 | TELEM-09 | Indexed expiry, raw/aggregate storage separation, restricted roles, safe error logs and service monitoring | TELEM-08 | Physical-copy/backup feasibility, boundary races and log-canary evidence; pending |
| 4 — useful GitHub feedback, 3–5 days | TELEM-10 | Daily rollups and fixed weekly aggregate tables with disclosure gates | TELEM-09 | Correct weighting, suppressed cells, missing periods and late batches; pending |
| 4 | TELEM-11 | Deterministic renderer, frozen review record and recoverable GitHub publisher | TELEM-10 | Offline intent/disclosure model prepared; durable state, real permission/rate/timeout/concurrency tests pending |
| 5 — qualification and rollout, 4–7 days plus beta time | TELEM-12 | Cross-platform release-package consent, network and performance qualification | TELEM-02…11 | Windows/Linux/macOS, 1080p-first except Apple Silicon Retina native-panel evidence; pending |
| 5 | TELEM-13 | Small volunteer preview cohort and maintenance runbook rehearsal | TELEM-12 | Observed payloads, bounded costs, real off-switch, operator response; pending |
| 5 | TELEM-14 | Enable the approved release configuration and publish the notice | TELEM-13; completed deployment/privacy gates | Release owner accepts exact build, endpoint and notice; pending |
| 5 | TELEM-15 | First release comparison, metric review, deletion drill and quarterly pruning | TELEM-14 | Actionable regression report and unused-field removal; pending |

Expected implementation effort after this design: roughly **18–30 engineering days**, plus review and beta observation. This estimate assumes a hosting/storage arrangement that can actually meet the declared retention contract; a new erasure mechanism or provider redesign requires re-estimation. Consent/UI and backend preparation can proceed in parallel after TELEM-01. Do not gate gameplay on ingestion availability.

## First three implementation PRs

### PR 1 — local consent foundation

Add proposed app/telemetry/consent_store.gd, policy.gd and a no-op service; wire only the interactive exported route in app/app_root.gd. Add the first-launch choice and startup/Settings effective-state controls, using reviewed notices for enabled locales. Add a separate versioned user://telemetry_consent.cfg instead of overloading display/flight preferences. Test corrupt, future, unwritable and revoked states. Keep the compiled endpoint empty and collection off until policy admits it. Do not activate third-party autoloads.

Done means startup/Settings report the effective state correctly, a denial survives a successful restart/save, and a failed save is visible without resuming current-session collection. No live transport exists in this PR. Qualify the current notice in all offered locales or force effective telemetry off in locales without reviewed notices; an unreviewed language change cannot silently reactivate a saved grant.

### PR 2 — local data path and preview

Implement the catalog projection, hardware buckets, fixed histogram and post-consent activity projection. Port the portable fixtures and reference invariants to focused GDScript tests. Add a local readable preview generated from the exact pending wire object. Keep memory bounds and reset-on-context-change semantics. No backfill.

Done means known input traces produce the specified measurements, custom strings cannot cross the allowlist, and local preview works with the transport stub. Existing simulation/checkpoint tests remain unchanged.

### PR 3 — controlled transport and receiving spike

Use an isolated local test collector and exported release builds. Implement cancellation/epoch fences, status-specific retry and the strict server schema. Prove silent-peer shutdown and queue behavior before any operator endpoint is configured. Use synthetic fixtures for transport failure tests; the separately admitted native qualification route can capture controlled tester timings and coarse hardware categories.

Done means both sides enforce the contract under malformed traffic and outages; no test depends on real player data. A non-shipped, explicitly admitted qualification build may run the same adapter against a compiled local-only test origin for controlled native measurements; ordinary shipped-route off-state checks remain separate. Promotion requires the remaining operations/consent/hardware gates.

## Merge readiness versus activation

The design and offline starter are reviewable as preparation when their generated artifacts and focused tests pass on the candidate and the source diff is reviewed. The [isolated CI job](../../.github/workflows/telemetry-contracts.yml) runs both generator checks and the offline suite for pull requests, relevant pushes and manual dispatch. It uses a fresh pinned-dependency environment, read-only repository permission and no publisher credential. Its hosted result and the repository's existing required CI must be checked on the proposed merge; this job does not replace the existing gates. A merge does not make collection or a receiver available and does not satisfy the pending implementation, privacy, provider, hardware, publication or volunteer-preview gates in TELEM-02…15.

The first implementation sequence remains the three PRs above: local consent foundation, local data path and preview, then isolated transport and receiver. Their stated acceptance, including locale and qualification-build boundaries, is required before each next integration; later phases keep their own owners and evidence.

Senior-team handoff: review the [final finding dispositions](../research/telemetry/TELEM-00-R1/review.md#final-merge-preparation-review) and [verification evidence](../research/telemetry/TELEM-00-R1/verification.md#final-candidate-verification), confirm the current merge base and required CI, then merge this preparation as TELEM-00/01. Assign named owners to the first three implementation PRs and the deployment decisions below. No production endpoint, telemetry secret or public-report destination is needed to merge the preparation. Enabling a live release remains TELEM-14, after its explicit gates.

## Decisions that remain before deployment

| Decision | Recommended starting point | Why it remains open |
| --- | --- | --- |
| Operator, contact and processing region | Project-maintained notice with named contact | Not present in the task; never invent legal identity |
| Hosting and operational budget | One small managed service/database; reviewed cost ceiling | Actual vendor logs, region, deletion and billing must be checked |
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
