# R20 — A comparison needs an explicit denominator

**Decision:** integrate coverage and ambiguity checks in `research/flight-test/compare.py`. **Priority:** P1. **Baseline:** `08f0c08348395c0d6d9f7e224f66460828f59a7f`. Preserve the tool's purpose: describe changes in model measurements; it does not validate a real aircraft.

**Implementation update:** this branch implements the contract with structured tuple identities, so nested metric paths and punctuation-bearing names remain distinct across profiles. Declared aircraft IDs and present run receipts are checked for consistency and successful execution; old missing fields remain explicitly unverified. Executed acceptance is in [verification](../verification.md); independent counterexamples and their disposition are in [implementation review](../implementation-review.md).

## Observed failure modes

The baseline enumerates aircraft only from the baseline directory. Empty directories produce zero changes and success. `--shared-tests` intersects test names without requiring a nonempty intersection. A repeated table `case` overwrites the earlier flattened fields. Candidate-only aircraft are invisible. Numeric tolerances are accepted without checking finiteness or sign. These are different failures: absent coverage, ambiguous identity, an implicit roster policy and invalid comparison parameters.

The earlier [tool probe](../../follow-up-01/evidence/tool-evidence.json) demonstrates empty directories, disjoint shared tests, duplicate cases hiding a changed first row, candidate-only aircraft and an ordinary numeric-change control. The independent reviewer also inspected 18 retained original profiles, covering 820 table rows, without finding missing or repeated case IDs. That is a useful compatibility sample, not a complete promise about all historical/custom profiles.

## Research

The pytest project distinguishes a collection with no tests from a successful collection ([LEAD-S04](https://docs.pytest.org/en/stable/reference/exit-codes.html)). This is a design precedent for a separate ineligible-comparison result; its numeric exit codes are not imposed on our CLI.

JSON Schema explains that item uniqueness alone admits an empty array and that minimum size is a separate constraint ([LEAD-S05](https://json-schema.org/understanding-json-schema/reference/array)). Moreover, whole-object uniqueness does not enforce uniqueness of a selected `case` property. Two rows with one identity and different values are distinct objects but still ambiguous measurements. The repository needs explicit key-level validation, irrespective of whether a schema library is used. Python's documented last-name-wins decoder behavior adds a separate ambiguity before flattening ([LEAD-S02](https://docs.python.org/3.12/library/json.html#repeated-names-within-an-object)).

## Contract and alternatives

Use the union of aircraft rosters by default, reporting additions and removals. An explicit `--aircraft-scope baseline` retains intentional baseline-only work and names candidate-only exclusions. Keep `--shared-tests` as an explicit test subset, naming omitted tests. Refuse zero shared aircraft or zero shared test coverage with exit 2, independently of `--fail-on-change`. Exit 1 continues to mean differences were found when that flag is requested; exit 0 means an eligible comparison completed under the selected policy. Invalid input and card incompatibility also require a nonzero outcome.

Report shared aircraft, shared tests, shared value keys, and shared non-null value pairs. A validity-only comparison is useful and must remain possible: two tests can both report an unavailable maneuver. State clearly when there are no measured values. `null` is unavailable, never zero. A measurement appearing or disappearing is a difference; valid/invalid/skipped transitions remain explicit. Neither all-invalid results nor a stable boolean alone qualify flight behavior.

Reject repeated JSON names, duplicate case IDs, missing case IDs and malformed result containers. Preserve `(test, kind, path...)` identities independently of display labels, so flattening cannot merge distinct fields. Compare raw test names instead of deriving ownership from a punctuation-based split. Accept the producer's finite values and its explicit nulls; refuse NaN/Infinity or overflowed JSON numbers. Require finite nonnegative `--rel` and `--abs`, because an invalid tolerance can hide a real change. These checks can use the standard library, avoiding an additional schema package for a small existing format.

Strict schemas for every maneuver would be stronger but couple this generic comparator to every card version. Automatically treating all newly added aircraft as intentional would preserve the old blind spot. The selected design validates generic structure, makes scope explicit, and leaves scientific per-test expectations with the versioned card and investigator.

## Acceptance and limits

Exercise empty/disjoint directories, disjoint tests, candidate additions/removals, explicit baseline scope, missing profiles, duplicate JSON names, duplicate case IDs, flattened-name collisions, malformed containers, invalid tolerances, numeric changes, null availability changes, valid/skipped transitions and an eligible unchanged control. Scan retained profiles for structural compatibility. Keep `--allow-card-change` and shared-test workflows useful while reporting their exclusions.

A report still cannot prove that the underlying pilot completed a requested time horizon; the retained early-floor counterexample requires a future card semantic/version change. Provenance fields and coverage must not be presented as evidence of physical validity. This repair makes the comparison's denominator visible and prevents known empty or ambiguous inputs from receiving a clean regression result.
