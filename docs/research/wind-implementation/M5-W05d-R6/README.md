# M5-W05d-R6 — bounded gust agenda search

2026-10-26. Owner: M5-W. [Wind guide](../../../WIND-PLAN.md), [preceding workload admission](../M5-W05d-R5/README.md), [original hotspot profile](../M5-W05d-R2/README.md#profiling-and-timing).

## Change and numerical contract

`WindSpatialField._gust_wind` previously visited every authored event at every aircraft sampling point. The existing profile identified this routine as the next largest field cost after turbulence. The resolved agenda already guarantees finite, nondecreasing start times and at most 32 entries.

Only `app/physics/wind_spatial_field.gd` changes runtime code. Construction now prepares the maximum event duration, `D`. At each query, a pure binary search finds the first event for which `epoch_time - start < D`. Every skipped event has `elapsed >= D >= its duration`, so the previous evaluator would skip it too. Evaluation retains the original duration test and pulse arithmetic, visiting candidates in their original order. It stops at the first negative elapsed time because all subsequent starts are also in the future. Empty agendas, times before the first event and completely expired agendas return zero without calculating the wall weight.

The comparison deliberately uses subtraction, not `epoch_time >= start + duration`. Floating-point rounding makes those tests differ at some endpoints. Tied starts retain their ordering; the binary predicate is monotone for the validated finite operands. The maximum is cleared and recomputed on preparation, including empty reconstruction. Returned arrays remain detached. There is no mutable time cursor, result cache, query RNG, changed field identity, changed weather schema, new force or aircraft-specific condition.

The search performs at most six comparisons for a 32-event agenda, followed by a scan of the conservative candidate window and at most one future event. Long durations can keep expired short events in that window, so worst-case scanning still includes 32 entries. This simple bound avoids another index or stateful invalidation scheme. In the R5 24-event active workload's two-second window, the event loop visits the first active pulse and the first future event instead of all 24, in addition to five binary comparisons. These are logical work counts, not measured speedup percentages.

No modes, sampling points, physics ticks, aerodynamic terms, gust amplitudes, arithmetic grouping or summation order are removed. Public APIs and scenario hashes remain unchanged. Source-bound ORFL identity correctly changes.

## Correctness evidence

The isolated candidate passes **33,945 checks plus four golden flights**:

| Test | Checks / failures |
| --- | ---: |
| `test_spatial_gust_index` | 31,369 / 0 |
| `test_spatial_wind_field` | 154 / 0 |
| `test_spatial_wind_prepared` | 1,543 / 0 |
| `test_spatial_stage_lean` | 668 / 0 |
| `test_spatial_wind_benchmark` | 110 / 0 |
| `test_spatial_weather_session` | 101 / 0 |
| `test_golden` | 4 tapes / 0 |

The new test compares exact gust bytes against the former serial loop across empty, maximum-length sparse, tied/overlapping variable-duration, long-epoch rounding and complete preset agendas. It checks the safe lower bound independently, queries times in both directions while interleaving fields, mutates caller/public copies and returned arrays, and verifies shorter/empty rebuilds replace the prepared bound. Existing full-field fixtures retain all 760 pre-optimization samples. Golden flights pass their existing tolerance checks; they are not described as byte-identical recordings.

The first new-test run passed the serial parity matrix but failed its explicit rounded-end assertion because a separately written decimal literal did not equal the endpoint computed from the compiled start/duration. The corrected fixture calculates the endpoint from those operands and separately verifies `elapsed < duration`. All receipts remain under `checks/`; no production arithmetic or tolerance was changed to resolve that test mistake.

The [nine R5 workload comparisons](workload-parity.json) retain identical complete aircraft-report values: configurations, field receipts, starting states, repeated final states, active gust/thermal coverage and all query counts. The candidate accepts **23,760 ticks** across the prescribed warmups, batches and coverage replays. Baseline reports remain at [R5](../M5-W05d-R5/workloads/); candidate reports are under `workloads/`. These are repeated short trajectories, not long-duration flight validation.

The preserved `extra-active-baseline.orfl` records 480 ticks with the complete 24-event gust agenda, mature thermal, seeded turbulence and a fixed input tape with an aileron reversal at the gust peak. [Replay parity](replay/parity.json) confirms **all cells in all 481 exported CSV rows remain identical**. Baseline exact replay completes with `solver_changed=false`; candidate replay completes with `solver_changed=true`. Both are complete, and the existing comparator passes. Candidate replay remains a candidate experiment, not exact-source replay or physical validation.

After integration, the gust-index, prepared-field and benchmark-contract tests pass **33,022 checks** in the shared tree. [Before](integrated-before.json)/[after](integrated-after.json) solver observations match during those checks. [Comparison](integration-comparison.json) records unrelated sources that differ from the preserved R5 snapshot. Concurrent aircraft tuning, session/ground work and the pre-existing documentation merge conflict were preserved. The controlled comparison uses the frozen R5 solver; no complete shared-tree suite is claimed.

## Timing attempt and remaining gate

A sequential ABBA experiment used the existing full-session benchmark, Extra 300S, five batches per case, a spatial no-gust control and the active gust/thermal case. Both engine processes inherited affinity mask 1048576, verified in [the process receipt](timing-affinity.json). There were no other Godot processes at the first run boundaries or before the candidate window.

A separate fullscreen lighting capture appeared during the first candidate window. The guard recorded it in [the sequence receipt](pinned-sequence.json) and stopped before the remaining BA runs. Both completed raw reports and logs are retained under `rejected-timing/`. **This incomplete, contaminated pair is excluded from speedup interpretation.** No percentage gain, per-tick latency result, 500 microsecond physics admission, 240 Hz real-time operation or 1080p qualification is claimed. CPU frequency, thermals, the SMT sibling and non-engine host work were not controlled either.

Repeat the paired measurement on a reserved quiet host before making a performance claim. Further optimization should follow the measured field/stage costs; this change does not justify reducing modes or point sampling. Meteorological spectra, terrain flow, heating, pilot handling and shared companion gates remain open.

## Separate existing validator issue

Review identified an inherited endpoint mismatch in `WindSpatialConfig._validate_events`: overlap admission uses `start + duration`, whereas evaluation uses elapsed subtraction. The retained `check_existing_endpoint_gap.gd` reproduces this on the unchanged baseline. With compiled start `63869.15030607467`, duration `32.88826421165945` and their rounded sum `63902.03857028633`, subtraction is `32.88826421165868`, still below the duration. An authored five-event fixture passes admission while the runtime support test counts five entries at that rounded endpoint; the newly starting pulse is zero there.

This is a numerical consistency issue in the structural overlap limit, not evidence of a large force discontinuity. R6 does not rely on the four-overlap bound for correctness and retains the old samples/admission. Aligning validation with runtime requires a separate compatibility-tested correction rather than silently changing accepted weather during an optimization.

## Reproduction and identities

Pinned engine: `4.8.beta1.official.4d10419ca`, Windows. R5's [source reconstruction](../M5-W05d-R5/README.md#reproduction-and-source-identity) supplies the baseline, including its pre-existing working-tree bytes. [Comparison manifest](comparison-manifest.json) verifies that exactly one of the 158 physics/simulation/failure sources differs.

| Solver | SHA-256 |
| --- | --- |
| Baseline | `5a501c161343d39a3a7694b94030153d5f541677a0885455b0e5b754710b0612` |
| Candidate | `4a4d6d72d991069f2c8bf31460e173f80ff4325fb28aed97b4989cf9aa7488a4` |

For baseline, use R5's restoration helper on a disposable checkout of its recorded base commit. For candidate, run this directory's `restore_sources.py --repo <repository> --destination <checkout>`; it first restores R5, applies the two retained source overlays and verifies the candidate solver. Import the reconstructed app before running tests. Source-only reconstruction was verified; this is not complete-app clone qualification.

The retained orchestration scripts record the original layout under `tmp/wind-gust-r6/`: `baseline/app`, `candidate/app`, sibling `tools/` copies, and the pinned root `.tools` engine. Adapt those paths or recreate that layout. `verify_workloads.py` uses the R5 original source manifest and base-revision annotation; actual source hashes in reports identify the candidate. Checked-runner reports retain exact commands, while `verify_change.py` uses the existing ORFL CLI for complete replay and comparison. Use fresh output paths. [Payload hashes](payload-manifest.json) and [evidence-only checkout checks](checkout-verification.json) preserve the recorded bytes independently of Git newline conversion.
