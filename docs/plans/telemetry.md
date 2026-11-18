# Transparent product telemetry — implementation plan

Status: **client, receiver, rollup, report and publisher implemented and tested (TELEM-02…11); inactive in every build until the [activation steps](#merge-readiness-versus-activation) (TELEM-12…14)**. No receiving service is deployed and no build offers telemetry yet.
Dated 2026-11-18. Telemetry design baseline: [39fa2746](https://github.com/bultodepapas/OpenRCsimulator/commit/39fa2746ae4f4ba8698b87db279adcfe84ef5d17). TELEM-00/01 was merged into main the same day; current-main interface references were re-checked against main [35787fb5](https://github.com/bultodepapas/OpenRCsimulator/commit/35787fb583f3b654b28381c951783be7a85be0e0) ([main integration](../research/telemetry/TELEM-00-R1/verification.md#main-integration)). The merge is not a runtime-qualified build.
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
| 1 | TELEM-04 | Read-only frame observer, hardware classifier and effective graphics snapshot | TELEM-02; PT/VQ | **Implemented:** windows and classifier (graphics profile sent as unknown). Target-hardware overhead campaign pending |
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
3. **Configure releases.** Set the repository variables `OPENRC_TELEMETRY_ENDPOINT` (the HTTPS `/v1/batches` URL), `OPENRC_TELEMETRY_OPERATOR` and `OPENRC_TELEMETRY_CONTACT`. The next exact-tag export offers telemetry; untagged builds still do not. Unset variables turn it off again for later builds.
4. **Qualify a release candidate (TELEM-12/13).** On Windows, Linux and macOS: the notice at 1920×1080 first (Apple Silicon Retina at native panel resolution), Enable/decline/off, preview contents, receiver rows, frame-time overhead with telemetry on and off. A small volunteer preview precedes a stable release (TELEM-14).
5. **Weekly report (TELEM-11).** `rollup` each closed day, `report` the closed week, review it, then `publish --approved-digest <digest> --execute` to a private operations repository first.

Players can always turn telemetry off in Settings → Interface; `OPENRC_TELEMETRY_DISABLE=1` forces it off for a launch. Other languages become available only after a reviewed notice ([languages](telemetry/consent.md#languages)).

History: the design preparation merged as TELEM-00/01 after the [final finding dispositions](../research/telemetry/TELEM-00-R1/review.md#final-merge-preparation-review) and a [main-integration re-check](../research/telemetry/TELEM-00-R1/verification.md#main-integration).

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
