# E0b6p — Remaining whole-tick cost

2026-10-07 · **Status: attribution verified; the 500 µs budget remains open.**

Follow-up: the [required-field lookup cleanup](../decoder/README.md) was verified on 2026-10-08. The measurements and proposed experiment below record the attribution before that change.

## Result and next experiment

Two disposable profilers separate the complete flight tick from native wake decoding and computation. Application physics, aircraft data and the original native evaluator are unchanged. The measured active native-flight medians remain **615–691 µs/tick** on the shared Linux i5-10500 host. This is diagnostic evidence, not quiet-target acceptance.

The next bounded experiment is to remove duplicate dictionary lookups from the native evaluator's three required-field readers (`read_number`, `read_vec3`, `read_pair`). They currently call both `has` and `get`; a missing field's NIL result is already rejected by the leaf decoder. Preserve optional-field behavior, malformed-input refusal and all numerical expressions. Test missing required keys from a valid positive control, compare complete loads and trajectories, then measure paired calls and whole ticks. Retain the change only if the gain survives timing variation.

Model decoding costs **13.3–14.4 µs/call**, about **53–58 µs for four RK load evaluations**. That is an approximate upper bound for eliminating *all* decoding on these fixed inputs, not the expected saving from removing a lookup. This cleanup cannot by itself establish budget compliance. Aerodynamics and the simulation remainder are also substantial; do not jump to model caching, a larger native port, fewer quadrature points or less frequent stage evaluation on this evidence.

## Complete-tick attribution

The [tick report](tick-attribution.json) compares an uninstrumented native-adapter flight with an instrumented copy. Each case restores the same checkpoint for one warm-up and five measured **24-tick** batches. Timer-enabled and timer-disabled batches alternate order. A separate 240-tick trajectory runs with instrumentation enabled.

The following are **instrumented component means in µs/tick**, with swirl factor 0.4. Buckets are exclusive and sum to the measured step mean. They include observer effects; do not compare their sum directly with a separately measured uninstrumented median.

| Regime | Air | Aero | Propulsion | Wake adapter | Ground | Pre-step | Simulation remainder | Sum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Forward | 19.9 | 152.9 | 42.5 | 233.9 | 7.9 | 35.1 | 154.8 | 647.0 |
| Stall | 23.3 | 224.5 | 45.5 | 268.1 | 9.8 | 43.0 | 180.9 | 795.1 |
| Static | 23.4 | 160.7 | 46.7 | 257.9 | 9.8 | 45.6 | 185.8 | 729.9 |
| Spin | 20.9 | 153.4 | 42.1 | 247.6 | 8.1 | 39.2 | 160.9 | 672.3 |
| Reverse fade | 19.6 | 134.0 | 36.3 | 216.9 | 8.2 | 35.4 | 144.5 | 595.0 |
| Reverse off | 18.3 | 127.6 | 34.8 | 20.4 | 6.3 | 31.6 | 131.4 | 370.4 |

Each tick records four Aero, Propulsion, Slipstream and Ground calls, six Air calls and one pre-step. Pre-step excludes its two nested Air calls. The simulation remainder includes RK arithmetic, rigid-body derivatives, validation, callbacks, state bookkeeping, instrumentation bookkeeping and untimed glue; it is **not a measurement of integration alone**. The airborne fixtures do not characterize loaded wheel contacts. Their continuous wash arrays are empty; transport behavior is covered by the earlier native verifier.

Paired enabled-minus-disabled median differences range from **−10.4 to 69.5 µs/tick** for these rows. The negative sample and large spreads demonstrate shared-host noise. Timer quantization and bookkeeping also affect small buckets. Raw batch timings are retained in the report; no observer-cost subtraction is used to claim budget acceptance.

## Native phases

The [native report](native-attribution.json) uses a separately instrumented binary built from the unchanged evaluator. Each of six fixed states has 500 warm-up calls and seven batches of 3,000 calls, through both the direct extension and the research adapter. These inputs differ from the evolving flight batches, so the two profiles are not an additive decomposition of one identical tick.

| Active-case phase | µs/call |
| --- | ---: |
| Model dictionary decoding | 13.3–14.4 |
| Distributed swirl | 17.4–24.7 |
| Axial profile-centroid loads | 0.90–1.14 |
| Input validation inside the kernel | 0.37–0.41 |
| Axial wake construction | 0.03–0.04 |
| Complete instrumented C++ method, raw | 34.1–42.0 |

Model decoding accounts for about 32–39% of the raw method total; swirl accounts for 51–59%. The measured clock pair costs 22 ns. Phase figures subtract only that endpoint estimate; raw method totals retain nested instrumentation costs. Independently computed medians need not sum exactly. Raw phase counters, residual estimates and all batch samples are preserved in [the instrumented profile](native-instrumented-profile.json) and [the baseline profile](native-baseline-profile.json).

A direct reverse-off call still decodes and validates (15.8 µs); the research adapter returns zero before entering native (baseline median 3.4 µs). The external-to-method remainder is roughly 1 µs and includes binding, marshalling and harness work. Separate-process baseline/instrumented differences do not isolate observer overhead.

## Proof and reproduction

- All **12 × 240 trajectory boundaries / 77,760 scalar values match exactly** with whole-tick instrumentation active. Expected call counts, case order, finite values and state shapes are checked. Native routing reports zero fallback/refusals. The report includes comparator fault injections for missing counters, wrong rosters, truncated series and non-finite boundaries.
- The instrumented native binary passes [315 checks / 297 oracle comparisons](native-instrumented-verification.json): 296 exact, maximum absolute difference `4.44e-16`, with the original `1e-10` absolute-plus-relative criterion. All six fixed direct and adapter outputs match the original native binary exactly. [Comparator fault injections](native-comparator-checks.json) reject missing vectors, non-finite output and incorrect call counts.
- [Validation](validation.json) records lint and engine parse checks. A parse preflight scans engine logs as well as exit codes: Godot can exit zero on a parse error. No production changes or golden regeneration required a new full application regression in this measurement-only step.
- Reproduce with the [whole-tick runner](../../../../../research/propwash/e0b6p/attribution/README.md) and [native phase runner](../../../../../research/propwash/e0b6p/native-cost/README.md). Source and library hashes are in both reports. The [raw trajectory manifest](raw-trajectory-manifest.json) identifies the reproducible full arrays; the checked-in tick report retains their exact comparison and all timing samples.

The production app remains GDScript. Gate P owner acceptance, release-platform proof and E0b7 independent calibration remain open; these synthetic fixtures do not validate powered Stik flight.

Commit message: `E0b6p: attribute native whole-tick cost; verify 12 exact trajectories and 297 load comparisons`
