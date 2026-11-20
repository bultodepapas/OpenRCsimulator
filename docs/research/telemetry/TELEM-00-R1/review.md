# Independent review and lead resolution — TELEM-00-R1

Date: 2026-11-18. Baseline: `48ae3016a655acf7d062da3f32d72b9050c9e59a`.
The independent reviewer inspected the working candidate after integration. Requested helper route: gpt-6.1-terra with max effort; effective provider model and effort were not independently verified.

## Scope and conclusion

The bounded review covered the sequential publication model, its example and generated tests, related privacy/retention and implementation acceptance language, and affected reducer/generator interfaces. The reviewer independently reproduced failing synthetic sequences, then rechecked the lead's fixes. After the final corrections, **no remaining concrete blocker was found within that offline scope**. This was not an independent review of all 30 investigations, the complete integrated diff, or production readiness.

The review used synthetic inputs and read-only source access. It did not run Godot, use production data, write to GitHub, or mutate the integration tree. The lead separately owns source integration, the two disposable mutation checks, document links and branch publication.

## Findings and resolutions

| Finding | Lead resolution and regression |
| --- | --- |
| Repository casing aliases could create independent intents | Canonicalize owner/repository casing before identity and approval checks; exercise equivalent aliases |
| An absent or false-like issue kind could be treated as verified | Require the explicit issue-kind field and literal `False` for `is_pull_request`; reject unknown kinds |
| Multiple remote matches could lose their conflict state | Persist `review_required`; a narrower later discovery or callback cannot clear it |
| Already-published intents skipped meaningful remote audits | Reconcile complete candidates and flag missing, edited or duplicate artifacts |
| A different verified late success could be ignored after binding an issue | A valid-token confirmation for issue 43 after reconciliation to issue 42 sets sticky review; invalid callbacks still cannot rewrite state |
| Public approvals could outlive the known disclosure inventory they reviewed | Bind approvals to the current inventory digest; reserve pending/unknown intents immediately and invalidate stale approvals |
| Syntax alone did not constrain release identity | Require an explicit release allowlist and independently requested report key |
| A generated-test oracle assumed every body of at most 600 bytes was invalid | Use guaranteed invalid UTF-8 for malformed-byte generation and add a valid short session-start payload as a positive case |
| The laboratory text named a coordinated-omission counterexample that was absent | Add a fixture distinguishing one observed 100 ms interval from ten modeled intervals totaling 550 ms |

The new tests also run the actual daily reducer against a population-mix counterexample: unchanged 100/50 FPS strata produce a pooled change from 75 to 65 FPS when exposure shifts. This checks interpretation without claiming a release regression.

## Independent verification

The reviewer ran `python -m unittest discover -s research/telemetry -p 'test_*.py' -v` in the prepared Python environment: **97 tests passed on the final code candidate**, including generated cases and both generator reproducibility tests. Both standalone `--check` commands had also matched immediately before the final narrow publication-model/test correction; their inputs did not change. The lead then reran all 97 tests and both standalone generator checks on the final code candidate, with matching results.

The [verification record](verification.md) owns executed checks and their limits. Passing offline tests establish neither production concurrency nor delivery guarantees.

## Remaining implementation gates

The model has trusted inputs, sequential execution and in-memory state. A real implementation still needs authenticated reviewers; complete disclosure inventories; durable coordination across writers; handling of already in-flight remote requests; verified GitHub repository identity and visibility; recovery from stale backups or failover; report provenance and freeze-before-expiry evidence; qualified provider retention and error logging; and native client UI, network and hardware measurements.

Thresholding, session tokens and frozen outputs do not prove person-level anonymity or safety against combining releases. The [publication protocol](../../../plans/telemetry/publication-protocol.md), [validation laboratory](../../../plans/telemetry/validation-lab.md) and [delivery plan](../../../plans/telemetry/delivery.md) retain these requirements before activation.

## Final merge-preparation review

Date: 2026-11-18. Starting telemetry revision: `a16a2dbc2e0fdf3d22cdf7c2dd23bbfca24dd2e8`; original feature base: `39fa2746ae4f4ba8698b87db279adcfe84ef5d17`. This review covers the full preparation introduced by both telemetry commits, not only the latest publication module. The earlier 97-test receipt above remains historical. The lead inspected the integrated fixes and owns the final combined verification.

Three independent supporting assignments examined core contracts/reducers and generated tests; publication/receipt/failure semantics; and architecture, privacy, current-main integration and senior-team handoff. Each used source-read-only review, with separately owned scratch candidates where explicitly assigned. The lead checked material findings, accepted or narrowed the proposals, applied the final changes and reran the integrated checks. Requested helpers were gpt-6.1-terra/max; provider execution settings were not independently verified. No votes or model labels establish correctness.

### Concrete findings and disposition

| Finding | Final correction / acceptance |
| --- | --- |
| A service 401/403/410 could be cleared by enable or off/enable; direct suspension had the same edge | A separate sticky latch now belongs to the suspension transition. Fresh process only in the model; direct transition and response paths have regressions. Literal Boolean admission also rejects truthy unknown configuration before any probe. |
| Non-fixed-wing/custom activity could carry fixed-wing counts; ambiguous hardware strings selected the first family | Generated schema binds accepted fixed-wing counts to independently inspected stock aircraft IDs. Ambiguous recognized hardware families become other. |
| Counter overflow produced an event that its own schema rejected | FrameWindow rejects draw/gap/count/time overflow before mutation and refuses an empty event. Native handling of individually unrepresentable observations is explicitly bounded drop/reset/partial, not endless rollover or clamping. |
| Completeness had no duration floor; impossible report totals and calendar overflow escaped the intended boundary | Claimed complete windows need 30 seconds; partial boundaries remain explicit. Report exposure/frame totals must be plausible per contributing session and stay under independent scalar caps; integers fit the exact common JSON range. Invalid/maximal calendars and empty-data request identities fail with safe categories. |
| Event order and HTTP failure categories disagreed with the contract | Batch sequences must increase. Malformed input maps to 400, oversized bytes to 413 and schema/semantic rejection to 422. OpenAPI describes opaque intermediary 408/5XX responses separately from fixed direct-service errors. |
| A report title was outside the reviewed artifact; an approval could substitute the proposed bot; mutable policy values were accepted | Intent and remote candidates now include the deterministic title. Public approval binds canonical bot author plus the title/body content digest and current inventory. Policy author must be a bounded string; attempt tokens require actual integers. |
| Exact-match filtering hid an altered same-key issue beside a valid original | Related artifacts are checked before exact matching. Changed titles/bodies, duplicate matches and contradictory known-issue evidence create a sticky review state, even from incomplete discovery or a valid-token late callback. |
| “Four hours/one day” token lifetime contradicted the ten-minute queue; copy blurred local versus server retention | Separate the active collection epoch, remaining sealed-byte TTL and 48-hour receiver retention. The EN/ES notice explains local regeneration and receiver retention. Rotation/cancellation remains native implementation work. |
| Default-enabled copy, locale coverage and manual exports were underspecified | Explicit telemetry-specific acceptance remains required; generic/held input cannot grant. All nine offered locales require reviewed notice/layout or effective off. Manual export has a separate typed allowlist excluding wire tokens, sequences and raw events; its projector remains pending. |
| Technical-route forced-off conflicted with native overhead testing; newer main added independent hardware calibration | Define a non-shipped, locally targeted, explicitly admitted qualification build with source/behavior equivalence and real controlled QA observations. Ordinary shipped-route off safety is separate. Existing local graphics probes/calibration are independent and never serialized wholesale. Apply the current Apple Silicon Retina target exception. |
| Long-stall censoring, pooled channels/settings and missing coverage could be mistaken for release-regression evidence | Keep the bounded v1 measurement and pooled release-wide prototype, but label these limits in the actual generated report and canonical contract. Channel/context comparisons, coverage/histograms and new publication identities remain TELEM-10 work; the current row cannot reconstruct them. |
| Fixed process windows were called rolling-hour caps; local tests had no CI protection | Document request-anchored 3,600-second budgets and boundary bursts. Add an isolated offline CI workflow with the repository's verified immutable checkout pin, read-only permissions, no persisted checkout credentials or telemetry secrets, fresh pinned test dependencies and all three checks. |

The pooled-channel finding was deliberately resolved by narrowing the prototype's claim, not inventing a channel-specific report. Ten stable plus ten preview observations may form a pooled cell of twenty; neither channel individually meets that threshold. Production channel-specific reporting requires a new validated identity and disclosure review. The long-stall limit was similarly retained and made explicit; a passing offline suite does not make v1 freeze-complete.

### Independent re-review and lead result

The publication reviewer independently replayed the initial author, title/content, related-artifact, mutable-policy, implausible-total and maximum-date counterexamples, recomputed the artifact digest and ran the integrated 121-test candidate. The contract reviewer rechecked the final additional admission/direct-suspension regressions and the generated consent state machine; the document reviewer rechecked the final wording, workflow structure and generated-output commands. Their bounded re-reviews found no remaining concrete blocker in the reviewed preparation scope. The lead's final combined checks, source scope and limitations are recorded in [verification](verification.md#final-candidate-verification).

Newer main `d407acd9da55dc49d6e1e0442a81f3b6d7657591` was source-reviewed for architecture compatibility; the lead also inspected the later increment to `d60cf725c8f40379ef10768678ae1e873764839f`. Those changes are not silently included in this branch. The final merge-tree check uses the latter main revision and is evidence about that exact pair, not a promise that future main changes cannot conflict. Maintain the repository's required CI and senior review before merging.

### Handoff decision

The result is prepared for senior review and merge as documentation, executable contracts and test infrastructure. It does not activate product telemetry. The [master plan](../../../plans/telemetry.md#activation-and-release-checklist) owns the first implementation PRs and pending activation decisions. Native Godot consent/persistence/rotation/sockets, real database transactions and erasure, authenticated/durable publication, all enabled locales and target-hardware performance remain qualification gates. No first-run production guarantee is inferred from this offline review.

## Main integration review

Date: 2026-11-18. Candidate: branch head `bd7187cd9acf390af689455e5d0c17b111107490` merged onto main; current-main claims were checked at `35787fb583f3b654b28381c951783be7a85be0e0`. One independent source-read-only reviewer (requested Sonnet, high effort; effective settings not independently verified) statically compared docs against the executable reference, the CI workflow against repository conventions, and architecture claims against current main. It reported no merge blocker and confirmed the listed transport, window, budget, retention, disclosure and HTTP-mapping limits against the code. The lead verified each finding below against source before accepting it.

| Finding | Disposition |
| --- | --- |
| Two test reads used the platform default encoding; the example report contains non-ASCII characters | Fixed: explicit UTF-8. Local runs passed only because this host uses Python UTF-8 mode |
| Retry delay was documented as 5…300 s; the reference uses a jittered fraction of min(300, 5·2^n) with a 1 s floor | Fixed in the architecture transport table |
| NaN/Infinity literals (400) and overflowing numbers such as 1e999 (422) were not distinguished in the delivery text | Fixed; matches existing regression tests |
| Statuses outside the documented sets, and the HTTP-date Retry-After form, had no stated behavior | Documented the model's drop/delta-seconds behavior; final handling is TELEM-06/12 work |
| Architecture omitted current main's single automatic-graphics policy owner and scene-detail module | Added auto_graphics_policy.gd and scene_detail.gd; telemetry reads decided state and never re-derives it |
| Consent copy said "graphics settings", broader than the closed wire context | EN/ES copy now names renderer/API, resolution range, VSync/frame cap and customized-or-default |
| The contract workflow ran on every pull request, unlike other scoped workflows | Added the same path filter as pushes; the job is not a required check |
| Snapshot files appeared to use CRLF | Rejected: all 48 branch blobs are LF; the CRs came from the review export under core.autocrlf |

Integration checks are recorded in [verification](verification.md#main-integration).
