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
