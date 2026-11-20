# Telemetry follow-up: targeted investigations F18–F20

Research date: 2026-11-18. Starting repository commit `48ae3016a655acf7d062da3f32d72b9050c9e59a`; the lead's uncommitted `docs/research/telemetry/TELEM-00-R1/README.md` supplies the first-wave checkpoint. All external sources below were opened on the research date. These are proposals, not evidence of installed tools, an operational receiver, actual publication, or representative telemetry.

<a id="f18"></a>

## F18 — Can Schemathesis exercise the proposed receiver's HTTP contract?

**Question.** Would schema-generated positive and negative requests discover discrepancies between the planned OpenAPI 3.1 contract and a future receiver, and which acceptance properties remain outside that check?

**Exact English queries.** `site:schemathesis.readthedocs.io OpenAPI 3.1 quickstart property testing API negative testing tutorial`; `site:schemathesis.readthedocs.io checks positive_data_acceptance negative_data_rejection default responses`.

**Primary evidence.** [Schemathesis introduction](https://schemathesis.readthedocs.io/en/stable/) lists OpenAPI 3.1 support. Its [pytest tutorial](https://schemathesis.readthedocs.io/en/stable/tutorials/pytest/) generates requests per operation and validates responses; its booking example exposes an undocumented 500 caused by an unconstrained string. The [checks reference](https://schemathesis.readthedocs.io/en/latest/reference/checks/) distinguishes schema-valid from negative input; the [failure guide](https://schemathesis.readthedocs.io/en/stable/reference/failures/) notes that a cross-field rule may legitimately reject schema-valid input and that even a documented 503 triggers the default server-error check.

Local `research/telemetry/contracts/openapi.json` defines `POST /v1/batches`, a relative `batch.schema.json` reference and a deliberately non-routable server. A successful 202 claims durable whole-batch acceptance. `reference.py` separately checks histogram consistency, duplicate sequences and approved releases, which are not all expressible in the schema. Therefore a green schema run would not prove consent behavior, durable transaction/commit order, duplicate-key parsing, retention, safe logs or authorization.

**Plan and test.** Once a receiver exists, run the reviewed, exactly pinned tool against a disposable synthetic-only local service and database; override the placeholder base URL explicitly, preserve local reference resolution, deny external egress and use no real credentials or telemetry. Generate negative cases and inspect documented status, media type and safe error bodies. Independently generated semantically valid batches must receive 202 and commit as specified; separately allow a justified 422 for schema-valid but semantically invalid cases. For a deliberately injected database outage, assert 503 and no acknowledgment or commit; do not globally suppress unexpected 5xx failures. Add raw-byte duplicate-key, malformed UTF-8 and oversize cases separately. F09's Hypothesis client model addresses consent/retry sequences, not HTTP schema conformance. A local stub alone cannot qualify production persistence or networking.

<a id="f19"></a>

## F19 — What does durable execution actually guarantee for remote publication?

**Question.** If a publisher writes a GitHub issue and crashes before recording success, can a durable workflow or automatic activity retry guarantee that the issue is created only once?

**Exact English queries.** `site:docs.temporal.io activity idempotency retry side effects exactly once execution durable`; `site:docs.temporal.io "idempotency" "Activity" retry external system timeout`.

**Primary evidence.** [Temporal's Activity Definition](https://docs.temporal.io/activity-definition) describes a worker completing a side effect but crashing before reporting it; the activity may then run again. Observed completion does not mean the external effect executed only once. The guide’s idempotency-key approach requires enforcement by the remote service. [Temporal's Retry Policies](https://docs.temporal.io/encyclopedia/retry-policies) describe default activity retries with exponential backoff and unlimited attempts unless configured; workflow execution has different defaults. Activity arguments and results can enter event history, creating data-minimization concerns.

**Inference and limit.** A durable scheduler can recover intent and delays, but cannot make independent systems commit atomically. A local report key is not remote idempotency. Without remote enforcement, a timed-out create may have succeeded even if lookup returns nothing; an expired lease cannot recall an in-flight request. F10 examined comment actions and their find-then-create race.

**Plan and test.** Borrow the design principle without installing Temporal: record report key, intended digest, destination, attempt state and bounded retry deadline durably before sending; transition an ambiguous create to `unknown`, not back to `ready`. Permit automatic retry only where absence of a remote effect is established or the target enforces the intended idempotency semantics. Otherwise reconcile exact author, destination and marker; bind a unique verified match, but stop and alert for zero inconclusive matches, multiple matches or unresolved in-flight writers. Keep publication authorization and changed-digest review separate.

Inject process death after remote creation, delayed visibility, restart and an expired lease with a late writer. Assert no blind second create and preserve `unknown` until resolved. Simulate finite backoff and permanent permission failure. Real database durability, concurrency, credentials and provider semantics remain deployment gates.

<a id="f20"></a>

## F20 — Can a pooled FPS change identify a release regression?

**Question.** Can changing hardware mix or opt-in participation produce a greater-than-10% change in pooled cadence even if neither hardware group's cadence changes?

**Exact English queries.** `site:chromium.org telemetry UMA metrics population bias consent performance field trials analysis`; `site:docs.telemetry.mozilla.org operational monitoring experiments population representativeness release comparison`.

**Primary evidence.** Chromium's [web compatibility analysis guide](https://www.chromium.org/blink/platform-predictability/compat-tools/) describes a per-page usage numerator and page-visit denominator, and explicitly notes bias where UMA is disabled more often, such as enterprises. Mozilla's [operational monitoring guide](https://docs.telemetry.mozilla.org/cookbooks/operational_monitoring) distinguishes build-over-build monitoring from a bounded A/B experiment. Its [analysis gotchas](https://docs.telemetry.mozilla.org/concepts/analysis_gotchas) flags representativeness and delayed submissions. These large-scale systems differ from OpenRC's voluntary, short-lived session tokens and do not validate this project's sampling.

**Inference and synthetic counterexample.** Assume fast and slow strata remain at 100 and 50 frames per second. Release A has 500 eligible seconds in each stratum: `(50,000 + 25,000) / 1,000 = 75 FPS`. Release B has 300 fast and 700 slow seconds: `(30,000 + 35,000) / 1,000 = 65 FPS`, a 13.3% fall with no within-stratum change. Both reports describe participating, admitted session windows, not all users or unique people; repeat sessions and lost or declined uploads make the population and independence assumptions uncertain. Coarse GPU families also contain heterogeneous machines.

**Plan and test.** Predeclare comparable release/channel, dates, metric definition and eligible exposure. Report weighted `sum(frames)/sum(time)`, contributing session-day observations, included/suppressed days and approved coarse-context exposure mix; never infer a player denominator from downloads. Compare within preapproved sufficiently populated cells and treat missing/changed mix or instrumentation as an inconclusive limitation. Any extra breakdown must pass the disclosure gate. Add the synthetic mix-shift fixture above and a true within-stratum slowdown fixture; ensure the first is labeled an association requiring investigation, not a causal regression. Verify suspected changes with matched hardware, graphics settings, scene and repeatable replay/benchmark; no stable player identifier or unsupported confidence interval is needed or implied.
