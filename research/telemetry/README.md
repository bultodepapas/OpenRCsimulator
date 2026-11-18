# Telemetry implementation starter

**Offline reference only.** These files make the proposed telemetry contracts reviewable and testable before a Godot/client/backend implementation. Nothing here opens a socket, reads hardware/player data, deploys a service, schedules a workflow or writes a GitHub issue.

[Phased plan](../../docs/plans/telemetry.md) · [data contract](../../docs/plans/telemetry/data-contract.md) · [actual evidence](../../docs/research/telemetry/TELEM-00/verification.md).
[Adaptive follow-up and new checks](../../docs/research/telemetry/TELEM-00-R1/README.md) · [publication protocol](../../docs/plans/telemetry/publication-protocol.md) · [planned validation laboratory](../../docs/plans/telemetry/validation-lab.md).
[Final merge review](../../docs/research/telemetry/TELEM-00-R1/review.md#final-merge-preparation-review) · [offline CI](../../.github/workflows/telemetry-contracts.yml).

## Contents

| File | Purpose |
| --- | --- |
| [generate_contracts.py](generate_contracts.py) | Authoritative source for closed JSON Schemas and the OpenAPI proposal |
| [contracts/batch.schema.json](contracts/batch.schema.json) | Versioned hardware/performance/stock-activity/error wire shape |
| [contracts/report.schema.json](contracts/report.schema.json) | One closed UTC day's fixed GPU aggregate, explicitly not a complete weekly report |
| [contracts/openapi.json](contracts/openapi.json) | HTTPS batch API/status proposal; example.invalid is not a live endpoint |
| [reference.py](reference.py) | Strict decoding, semantic checks, frame reducer, in-memory consent/queue/request model, fake ingress and conservative daily disclosure gate |
| [test_reference.py](test_reference.py) | Adversarial privacy, race, transport-policy, metric and disclosure tests |
| [test_properties.py](test_properties.py) | Test-only Hypothesis hostile encodings, valid short bodies, idempotency expiry and generated consent/request sequences |
| [publication.py](publication.py) | Sequential frozen-intent model, public inventory reservations and uncertain remote outcomes; no GitHub client or durable database |
| [test_publication.py](test_publication.py) | Publication identity, stale approvals, conflict persistence, remote audit and metric-interpretation counterexamples |
| [generate_examples.py](generate_examples.py) | Reproducible synthetic fixture/report source |
| [examples/batch.json](examples/batch.json) | One synthetic 30-second, 60-FPS cadence report; no real measurement |
| [examples/aggregate.json](examples/aggregate.json) | Twenty synthetic temporary-session observations in one day |
| [examples/github-report.md](examples/github-report.md) | Deterministically rendered example; no GitHub publication |
| [templates/manual-report.md](templates/manual-report.md) | Optional player-reviewed manual diagnostic/report template |
| [requirements.txt](requirements.txt) | Exact versions used for this Python 3.12 offline prototype |

## Run

Use an isolated environment as documented in the [verification plan](../../docs/plans/telemetry/verification.md#offline-prototype-reproduction). With the dependencies installed:

~~~bash
python3 research/telemetry/generate_contracts.py --check
python3 research/telemetry/generate_examples.py --check
python3 -m unittest discover -s research/telemetry -p 'test_*.py' -v
~~~

Edit the generators, then regenerate; do not hand-edit the JSON/Markdown examples or generated schemas. The exact package pins reproduce the observed test environment; production service and transitive licensing/security review remain separate. The package-download step contacts a package registry; the checks themselves do not use the network.

## Contract coverage

The model demonstrates strict UTF-8 JSON, duplicate-key/depth/nonfinite rejection, closed enums and nested properties, increasing batch sequences, fixed-wing classifier eligibility, finite metric bounds, histogram/exposure plausibility and safe failure categories. It models no pre-grant probe, literal-Boolean eligibility, sticky service suspension, generation and per-attempt fences, pending queue expiry/purge, retry classes, Retry-After and fixed-window attempt/byte budgets.

The fake ingress models whole-batch acceptance, same-body dedup, conflicting identity, sequence overlap, approved release IDs, storage backpressure and a finite replay-protection horizon. It is not durable or concurrent database code.

Hypothesis generates bounded synthetic payloads and consent/request action sequences. Settings cap each data property at 80 examples and the state machine at 120 examples of up to 50 steps; these are configured bounds, not a claim that every possible sequence or that exact many cases ran. The package and sortedcontainers are exact test-only pins. No example database is persisted by these tests.

The publication model normalizes repository/bot casing, checks an explicit release allowlist/requested report identity, freezes the exact title and body and preserves unknown outcomes. A public approval binds the proposed bot, content digest and current inventory of known public intents; a new reservation invalidates older approvals. Missing/edited/duplicated artifacts, including altered same-key reports found alongside an exact original, create a sticky review-required state. The model has no automatic conflict resolution, real reviewer authentication, immutable repository-ID/visibility lookup, durable/multi-process coordinator, complete remote inventory or provider request. Its small state machine must not be shipped as a ready publisher.

The reducer takes trusted server receipt-day/body tuples plus a trusted UTC as-of instant. It rejects mixed days/releases and runs only from day close +1 hour until day start +47 hours. Complete windows need at least 30 seconds of observed time. It counts temporary session tokens, caps each at 120 eligible windows, suppresses the whole fixed GPU table if a cell has fewer than 20, and removes identifiers before rendering. Its output includes the specific UTC day and containing ISO week. This is a release-wide pooled GPU summary: channels and other contexts are not distinguished; intervals over five seconds, even real foreground stalls, are excluded. The output lacks gap counts/histograms and does not qualify release or channel comparisons. Impossible totals and scalar-capacity overflow reject the whole report.

Weekly pooling, aircraft popularity tables, arbitrary-dimension suppression, provider deletion, real authentication/roles, actual GitHub writes and schedules are **not implemented**. Do not claim these offline models verify those features. The deployment plan owns those next steps.

## Limits that matter when porting

ClientModel is an executable state model, not a reusable production GDScript SDK. It has no consent-file durability, real hardware classification completeness, monotonic timer binding, day/four-hour automatic session rotation, actual socket cancellation/deadlines, genuine thread races or shutdown driver. Callers still own frame focus/drawability/scene boundaries and validated event sequencing. No UI has been rendered.

An anonymous sender can forge values and create new IDs. The reference's public-cohort rule is not formal anonymization, distinct-human counting or Sybil resistance. The native package, operational and privacy gates remain open in the plan.
