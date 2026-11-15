# Flight-test evidence: coverage, interruptions and comparison contracts

This follow-up examines whether a report supports the conclusion a developer might draw from it. The executed checkout is `00610ce3df391560dc195444d797bb81f2f83270`, including the first audit's bounded runner repairs. No production runner, card, runtime or aircraft data is changed in this follow-up. The failures below are additional open findings; they do not undo the earlier verified input-validation fixes.

The source locations below refer to that exact checkout. [Verification](verification.md) records the observed newer main and limits the freshness claim to the paths actually compared. [Probe sources](../../../../research/ugly-stik-audit-2026-11-15/follow-up-01/README.md) and [retained evidence](evidence/) allow the findings to be inspected without trusting a prose summary.

## Results and priority

| ID | Priority and evidence | Finding | Scope of the proposed repair |
| --- | --- | --- | --- |
| EVID-01 | High evidence integrity; checked production-card reproduction with an injected early floor | A stopped flight can supply its last observed row for later named times and still be marked completed/valid. | Explicit termination and time coverage, per-metric availability, accurate card labels. |
| EVID-02 | Medium diagnostic integrity; actual Python timeout passed through the real wrapper | Captured timeout stdout bytes are discarded; captured stderr is ignored. The timeout still fails. | Preserve both streams and interruption provenance before interpreting the profile. |
| EVID-03 | Medium/high campaign diagnosability; malformed/truncated-profile injection | Profile parsing or missing `results` can raise before `run.log` and the aggregate `run.json` are written. | Isolate one aircraft's failure, retain diagnostics and partial output, produce an explicit incomplete result. |
| EVID-04 | High if used as a regression gate; actual comparator on synthetic fixtures | Empty/disjoint comparisons can exit zero; duplicate case keys hide changed rows; candidate-only aircraft are outside the enumerated scope. | Validate comparison input, state the roster and coverage, distinguish no change from insufficient evidence. |

These are primarily defects or gaps in research evidence, not evidence that the game's integrator produced the wrong force. Fixing them before coefficient tuning reduces the chance of accepting a change for the wrong reason.

## EVID-01: early termination is not full-duration observation

### Source path

`research/flight-test/flight_test.gd:223–315` stops a non-runway maneuver below `start.get("floor", 60.0)`. It records the floor time, appends a note, and returns a non-crashed flight. `_row_at`, at `:427–428`, clamps a requested sample index to the last available row. `research/flight-test/card_power.gd:146–219` runs the power-step case for 31 seconds, applies the throttle step after the first second, and requests measurements 5, 10, 20 and 30 seconds after that step. It derives `completed` from the absence of a crash rather than from elapsed coverage, and sets card validity when all five rows are completed.

Each individual choice has a plausible local purpose: a floor prevents an irrelevant long descent, a bounded lookup avoids an indexing error, and an early termination can still be a valid physical observation. Together, they allow unobserved future times to receive measured-looking numbers. A floor-stop note is present, so this is not a claim that the stop is wholly hidden.

### Checked counterexample

The research-only [subclass probe](../../../../research/ugly-stik-audit-2026-11-15/follow-up-01/evidence_contract_probe.gd) injects a floor of **399 m** into the production power-step start at 400 m. It calls the unchanged production flight and metric code. This deliberately exercises an early-stop boundary; it does not establish that the normal 60 m floor is reached in ordinary stock runs.

| Case | Requested end, s from start | Last recorded sample, s from start | Time available after the 1 s step | Reported `completed` | Values reported at 5/10/20/30 s after step |
| --- | ---: | ---: | ---: | --- | --- |
| Idle | 31.0 | 3.120833 | 2.120833 s | `true` | Every speed is 13.26 m/s; every height change is −1.0 m. |
| 25% | 31.0 | 5.220833 | 4.220833 s | `true` | Every speed is 14.87 m/s; every height change is −1.0 m. |
| 50%, 75%, 100% | 31.0 | 31.0 | 30.0 s | `true` | Full requested time coverage in this probe. |

The five-case result is still `valid=true`. Both early stops are visible in the notes and `reached_floor_s`. Source and captured values demonstrate that all four later sample labels in each early-stopped row use the endpoint; none of those four target times was reached.

Evidence: [structured result](evidence/card-floor.json), [actual card profile](evidence/floor-card/profile.json), [CSV traces](evidence/floor-card/), [checked receipt](evidence/checks/card-floor/report.json) and [full log](evidence/checks/card-floor/engine.log). The receipt is complete, exits 0 and counts zero errors **and one warning**. Godot warned that `JSON.stringify` converted a NaN in power-step metrics to null at `flight_test.gd:216`; `warnings_as_errors` was false. This warning is retained and not described as a clean zero-diagnostic gate.

The previously published ordinary dynamic profiles for basic Stik, ideal Electric, pack Electric, 61FX and Extra have no recorded power-step floor stop. The injected reproduction establishes the contract error, not retrospective corruption of those normal profiles.

### Implementation plan

Have the shared flight result report the requested duration, actual observed interval, last recorded time and an explicit termination reason such as duration, safety floor, crash or initialization failure. Define whether these times refer to pre-step state, post-step state or stored samples: in this trace the loop's recorded floor time precedes the final row by one integration step. Consumers should use recorded time coverage rather than assume exact equality between these distinct timestamps.

Add a lookup with an explicit unavailable outcome for a target beyond coverage. Preserve the last valid row for actual endpoint metrics, but return null plus an availability reason for a named future-time metric. Interpolation within a covered interval can be a deliberate separate contract; endpoint repetition beyond the interval must not pretend to be interpolation.

Keep execution completion, maneuver validity and measurement availability separate. A floor stop may be the meaningful result of the maneuver; it should not be described as a fully observed 30-second response. A card revision that changes field meaning must document compatibility and update `summarize.py`, comparison rules and Markdown presentation together. Preserve old reports as evidence rather than rewriting their values in place.

Acceptance should exercise an early stop before every requested measurement, one between two target times, a stop exactly at a sample boundary within the declared time tolerance, a complete run, a crash and a failed initialization. Assert both the raw trace interval and serialized profile/summary. A complete baseline must retain its existing observed values. The test must catch an apparently valid row with unobserved future numbers, not merely assert that a new status field exists.

## EVID-02: timeout diagnostic bytes disappear

`research/flight-test/run.py:149–163` normally combines child stdout and stderr. Its `TimeoutExpired` handler retains stdout only if it is already a string and never appends stderr. Python's documented timeout contract permits captured bytes even when the original invocation requested text output; the Python 3.12 documentation explicitly describes that behavior for both streams ([official reference](https://docs.python.org/3.12/library/subprocess.html#subprocess.TimeoutExpired), accessed 2026-11-15).

The [Python evidence probe](../../../../research/ugly-stik-audit-2026-11-15/follow-up-01/tool_evidence_probe.py) starts a real Python child that flushes a stdout marker and an `ERROR:` marker to stderr, then waits beyond a 0.25-second timeout. It passes the actual exception through the unchanged runner. On Python 3.12.14 both captured attributes are bytes and contain their markers. The wrapper's retained `run.log` is just a newline, and the per-aircraft record says `script_errors=0`. The wrapper still exits **1** with `exit="timeout"`, missing tests and mismatched identity. This is lost diagnostic evidence in a failed run, not a timeout reported successful. The `ERROR:` marker is a deliberately injected Python diagnostic, not an observed Godot engine error.

The repair is small in scope: normalize bytes/string/None using a declared encoding and replacement policy, preserve both streams with their provenance, and mark capture completeness. Keep the timeout failure independent of whether its truncated output happens to contain an error marker. Persist the capture before parsing any profile. If the project consolidates this wrapper with its checked execution infrastructure, preserve the runner's standalone use and aircraft-level results; do not assume process success alone proves card coverage.

Acceptance should include byte and string captures, empty streams, a partial UTF-8 sequence at interruption, a diagnostic only on stderr, and a timeout after a partial profile. Verify retained bytes or explicitly documented decoding, nonzero outcome, timeout metadata and completion state. No claim about a real engine deadlock follows from this injected child.

## EVID-03: a broken profile can destroy the useful failure receipt

The wrapper reads and parses `profile.json`, indexes `report["results"]`, and counts its entries at `run.py:164–170`; it writes `run.log` only later. An uncaught worker exception escapes `pool.map` before the aggregate record is assembled at `:195–207`. The source therefore has no per-aircraft isolation for these profile-format failures.

The probe substitutes child responses and writes temporary artifacts, then calls the actual wrapper:

| Child/profile condition | Observed wrapper outcome | Per-aircraft log | Aggregate manifest | Summary |
| --- | --- | --- | --- | --- |
| Complete schema and expected result; positive control | Exit 0 | Present | Present | Present |
| Child exit 2, stdout/stderr diagnostics, truncated JSON `{"results":` | Uncaught `JSONDecodeError` | Absent | Absent | Absent |
| Child exit 0, accepted identity but no `results` | Uncaught `KeyError` | Absent | Absent | Absent |

These are synthetic corrupt or incomplete outputs. They demonstrate wrapper behavior if a child leaves those files; they do not establish that a normal engine run has produced them. The malformed file can remain on disk, but losing the captured stdout/stderr and campaign receipt removes information needed to distinguish numerical failure, schema error and process interruption. The multi-aircraft consequence is source-derived here; the retained injection uses one aircraft at a time.

Write captured diagnostics before interpreting the result, and wrap decoding/schema interpretation at the aircraft-job boundary. Return an explicit `profile_invalid`/incomplete result with the actual child status, parse detail and preserved raw path/hash. Continue collecting independent aircraft outcomes, then emit a failed campaign manifest even when some jobs produced no valid profile. Do not synthesize a successful empty result or erase the malformed file. Reporting should also survive a summary-generation error without losing the already collected campaign evidence.

The first positive fixture used during probe development omitted required summary metadata; that fixture was corrected before the retained run. Its resulting `mass_kg` error is not treated as a game defect. The published positive control provides those fields and reaches a successful summary.

Acceptance should combine one good aircraft and one malformed aircraft in a campaign, cover truncated JSON, a wrong top-level type, missing or malformed `results`, and an unsuccessful child that nonetheless leaves an apparently valid profile. Assert every aircraft's receipt, original exit status and raw diagnostics; only genuinely complete eligible results enter the successful summary. A failed campaign must not be represented as a successful partial comparison unless the user explicitly selected and can see that narrower scope.

## EVID-04: zero differences can mean zero useful comparison

The comparator's `flatten` function writes table fields into keys based on `test[case].field` (`research/flight-test/compare.py:21–41`). It has no duplicate-case rejection. `main` enumerates aircraft only from baseline directories at `:71–77`. With `--shared-tests`, it filters to the intersection without requiring that intersection to be nonempty (`:86–94`). The final exit status depends on the count of changes, not the amount or validity of compared evidence (`:126–131`).

The actual comparator was invoked with `--fail-on-change` on temporary fixtures:

| Fixture | Observed result | Interpretation |
| --- | --- | --- |
| Empty baseline and candidate directories | Exit 0, “0 change(s)” | No aircraft was compared. |
| Same aircraft, disjoint test sets, explicit `--shared-tests` | Exit 0; explicitly says zero shared tests and values | The report discloses the empty intersection, but the exit status cannot by itself establish a regression pass. |
| Two rows share case `start`; first rate changes 5→500, last rate remains 10 | Exit 0, “0 change(s)” | The later duplicate overwrites the earlier row in both flattened profiles. These are intentionally malformed identities; no duplicate in a normal produced stock profile is claimed. |
| Same unchanged baseline aircraft plus a new candidate-only aircraft | Exit 0, “0 change(s)” | The new aircraft is not inspected. This can be intentional for a baseline-only policy, but cannot certify equal fleet coverage. |
| One unique case changes 5→500; positive detection control | Exit 1, one reported change | Ordinary numerical change detection works for the control fixture. |

Evidence: [all wrapper and comparator outputs](evidence/tool-evidence.json). The probe source contains the exact synthetic inputs; it does not modify existing reports. No claim is made that differences in aircraft input hash should always be forbidden: intentional before/after data comparisons are a legitimate use of this tool.

A stricter gate should validate unique aircraft/test/case identities and schema before flattening. It should record the eligible roster, compared tests/values, exclusions and scope. Empty evidence should yield an explicit insufficient-coverage outcome unless a deliberately named exploratory option permits it; even then, the report must not imply equivalence. Baseline-only and union-roster comparisons can both be useful, but the chosen policy and candidate-only identities should be visible. Missing, invalid, skipped and unavailable measurements need separate semantics from measured zero.

Acceptance should retain the unique-case positive control and exercise duplicates, absent case IDs, empty runs, no shared tests, partial overlap, a candidate-only aircraft, a missing candidate aircraft and intentional source/card changes. Verify the exit result and rendered report together. A synthetic malformed profile should be refused or visibly uncomparable rather than quietly reduced to the last value.

## Additional source-proven provenance opportunity

`run.py` accepts a disposable `--app` copy, but the reported Git commit and dirty paths are taken from the wrapper's repository after execution, not a frozen content manifest of that external copy. The actual input JSON has stronger binding: the accepted input hash is compared with the file after the run. That is useful, but it does not identify every changed physics module in an external candidate directory. This review did not execute a candidate-source mutation or race; it is a source-proven provenance gap, not a demonstrated source-swap incident.

Before relying on such runs for approval, freeze the candidate source identity and selected engine identity at launch, record the actual app path and relevant content/tree digest, and check for mutation before completion. Include generated/imported dependency identity where it affects the result. Keep the accepted JSON hash distinction: a transformed/serialized data hash is not the same thing as the exact bytes accepted by the loader. Reuse an existing project provenance contract where possible rather than introduce another incompatible one.

## Suggested delivery order

First preserve failure captures and isolate profile-format errors; these changes make subsequent failures easier to diagnose. Next add explicit comparison coverage and schema validation. Then revise card time coverage and mode/period presentation as deliberate report-semantic changes. Use the retained baseline and positive controls to check that valid measured results remain unchanged. None of these tasks requires tuning the Stik's physics, changing stock identities or claiming improved frame rate.
