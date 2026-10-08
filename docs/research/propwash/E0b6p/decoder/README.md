# E0b6p — Single-lookup required-field readers

2026-10-08 · **Status: cleanup retained in the research native evaluator; whole-tick budget remains open.**

## Change and decision

The [native evaluator](../../../../../research/propwash/e0b6p/native/src/smooth_wake_extension.cpp) now uses one dictionary lookup in `read_number`, `read_vec3` and `read_pair`. Missing keys produce NIL, which the existing typed leaf readers reject. Removing the preceding `has()` preserves malformed-input refusal. Optional-number readers retain their distinction between an absent key (zero) and an explicit null (refused).

This is a three-line implementation change. Numerical expressions, quadrature, model data, current-stage inputs and production GDScript are untouched. Both paired runs show lower median differences for the five active fixed-input cases, so the bounded cleanup is retained. The measured size varies substantially; it does **not** establish a precise whole-flight speed-up or close the 500 µs/tick gate.

## Measurements

Both libraries coexist in one Godot process under distinct native class names. Each pair alternates which backend runs first. Timings include the research adapter. The rebuilt baseline library matches the earlier evaluator's SHA-256 exactly (`b0a90d20…`); [validation](validation.json) proves the retained source matches the measured candidate except for registration names.

| Fixed input | Run 1 paired median saving, µs/call | Run 2 paired median saving, µs/call | Faster pairs, run 1 / run 2 (of 24 each) |
| --- | ---: | ---: | ---: |
| Forward | 4.43 | 1.59 | 18 / 13 |
| Stall | 4.58 | 1.93 | 20 / 13 |
| Static | 5.92 | 4.05 | 20 / 15 |
| Spin | 6.06 | 5.95 | 19 / 19 |
| Reverse fade | 4.83 | 2.46 | 21 / 15 |
| Reverse off | 0.01 | −0.08 | 12 / 9 |

Positive values mean the candidate was faster. Reverse cutoff bypasses native and acts as an unchanged control. These are medians of paired differences, not differences of independent medians. For example, the second stalled case has separate medians of 51.2 and 57.0 µs, despite its positive paired median; scheduling noise prevents a precise effect-size claim. All individual samples are retained in the [first profile](run1/profile.json) and [repeat profile](run2/profile.json).

Whole-flight measurements retain the established 24-tick workload. Active candidate medians span **593–744 µs/tick** across both runs. Paired active-flight median savings span about **0.2–52 µs/tick**, with overlapping distributions and occasional worse independent medians. Do not convert the direct-call saving into a claimed total-flight improvement. The complete timing summaries are in [run 1](run1/evidence.json) and [run 2](run2/evidence.json).

## Correctness proof

- **297 complete-load outputs match byte-for-byte between native versions**, covering 256 seeded samples across 16 validated geometry variants, both tail laws, held/default downwash, reverse fade, stopped-source residual wash and axial transport. Both retain the existing oracle result: 296 exact comparisons and maximum absolute difference `4.44e-16`, within the unchanged `1e-10` absolute-plus-relative criterion. [Baseline](run2/baseline-verification.json), [candidate](run2/candidate-verification.json).
- **165 field-contract cases pass for each version**: a finite nonzero positive control, 34 required fields with missing/null/wrong-type/non-finite probes, packed-array shape errors, finite integer acceptance, conditional `free_slope` and six optional-number defaults. [Baseline](run2/baseline-fields.json), [candidate](run2/candidate-fields.json).
- **All 12 × 240 flight boundaries / 77,760 scalar values are byte-exact**. Body and auxiliary shapes/finiteness are enforced; continuous arrays are empty in this swirl fixture. Each backend records 34,867 native kernel calls and zero fallback/refusals in the repeated profile. Backend classes and distinct instances are asserted.
- **41 independent dense-integration accuracy checks pass** through the candidate adapter, with unchanged tolerances. [Log](run2/accuracy.log). The retained build under its normal registration name also passes the [original 297-case verifier](retained/verification.json).
- Engine parse checks and log scanning pass. The before/after lint reports have zero errors and the same 12 existing warnings, with no decoder harness diagnostics. No application files or goldens changed; the production application suite was not rerun for this research-only decoder change.

Reproduce with the [isolated builder and runner](../../../../../research/propwash/e0b6p/decoder/README.md). Both reports preserve source, fixture and library hashes; the final [retained build manifest](retained/evidence.json) identifies the normal-name library.

## Next bounded step

Investigate sharing `Propulsion.thrust_torque` **within one Dynamics load evaluation**: `Propulsion.loads` and the wake adapter currently evaluate it for the same stage velocity, rpm and density. Compare a disposable implementation before changing production interfaces. Preserve stopped/reverse behavior, turbine dispatch, transported wash and exact production-fleet/experimental trajectories. No result may be reused across RK stages or ticks. This duplicated work is another small opportunity, not a promise of closing the remaining budget.

Gate P owner acceptance, release-platform proof and independent E0b7 calibration remain open. The Stik remains unconfigured for this experimental smooth wake.

Commit message: `E0b6p: remove redundant required-field lookups; verify 297 exact native loads, 165 field cases and 12 exact flights`
