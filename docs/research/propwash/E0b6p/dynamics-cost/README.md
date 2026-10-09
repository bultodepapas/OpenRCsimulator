# E0b6p — Aerodynamic and simulation cost

2026-10-08 · **Status: nested attribution verified on Linux; next optimization selected. E0b6p and Gate P remain open.**

This completes the bounded investigation selected by [prepared-path attribution](../prepared-cost/README.md). Two sequential runs split the prepared candidate's aerodynamic loads and simulation remainder while preserving every recorded flight boundary. Production code, aircraft data and goldens are unchanged.

## Findings and next experiment

The simulation remainder is not principally RK arithmetic or checkpoint copying. In the active swirling fixtures, the instrumented means span 6.6–9.8 µs/tick for RK arithmetic, 16.7–23.7 for rigid-body derivatives, 1.5–3.6 for checkpoint copies, and 31.3–45.1 for all measured validation regions combined. The load-callback remainder is larger, 63.0–92.0 µs/tick, but includes argument construction, flight/dynamics glue, load summation and timer bookkeeping. It does **not** measure pure Callable dispatch.

Aerodynamic work depends on the branch. In attached forward flight, blend selection costs 51.0–63.9 µs/tick and the global downwash correction, including its instantaneous wing-lift solve, 49.8–59.0. In active cases using local surfaces, the coupled strip-force region costs 55.2–73.1 µs/tick and both tails 30.2–42.2. These are instrumented means across the two runs, not predicted savings. The stalled fixture also spends some stages in the global/local blend; per-tick component cost depends on branch counts.

**Selected next change:** test hoisting loop-invariant dictionary reads and induced-map row offsets within `Aero.wing_lift_coefficient` and the local wing-strip loop. Keep each floating-point expression and summation order, the existing number of strips, and all guards. This is a bounded GDScript experiment without cross-stage caching or a new model lifecycle. Require exact loads, fleet trajectories, existing aero/downwash tests and paired uninstrumented whole-tick measurements before retaining it. This report establishes where to test; it does not claim that lookup work explains the entire measured region or predict a speedup.

## Timing evidence

Godot 4.7.2, Linux i5-10500 shared host, source `77312ec82810d60a8c971323bcf09945b1608ed9`. The prepared binary is unchanged from the previous experiment. Six regimes at swirl 0 and 0.4 use one warmup plus five measured 24-tick batches. Setup, preparation, checkpoint restoration and trajectory-byte capture are outside timing. Timer-enabled and disabled batches alternate order.

| Swirl 0.4 regime | Uninstrumented prepared median, run 1 / 2 (µs/tick) | Instrumented scaffold with timers disabled, run 1 / 2 | Paired enabled-minus-disabled median, run 1 / 2 |
| --- | ---: | ---: | ---: |
| Forward | 516.25 / 481.88 | 724.71 / 546.50 | 137.92 / 85.25 |
| Stall | 621.92 / 592.21 | 687.83 / 591.50 | 83.42 / 128.42 |
| Static thrust | 526.08 / 465.38 | 601.12 / 521.71 | 79.04 / 104.92 |
| Spin | 531.96 / 504.58 | 580.25 / 533.96 | 108.42 / 119.21 |
| Reverse fade | 540.42 / 483.12 | 482.25 / 507.96 | 83.92 / 114.50 |
| Reverse cutoff | 356.92 / 328.62 | 404.17 / 380.08 | 112.38 / 77.21 |

These are medians of **batch averages**, not individual-tick percentiles. The extra instrumentation has substantial overhead even when disabled, and host variability remains visible. No observer-cost subtraction is used to claim the 500 µs budget. Active baseline medians span 465–622 µs/tick; stall and spin exceed 500 in both runs. The difference from earlier runs is not an optimization result: the uninstrumented numerical implementation is unchanged.

[Run 1](run1/dynamics-evidence.json) and [fresh-clone run 2](run2/dynamics-evidence.json) retain every component and batch. Their exclusive means sum to the measured `Simulation.step` duration. Raw [baseline 1](run1/baseline.json.gz), [instrumented 1](run1/instrumented.json.gz), [baseline 2](run2/baseline.json.gz) and [instrumented 2](run2/instrumented.json.gz) retain all counters and trajectory arrays. Report hashes of raw JSON refer to decompressed bytes.

## Timer boundaries and correctness

- Aero: blend selection, global downwash correction, other global work, local setup, geometric strip angles, coupled strip forces, both tails, and explicit residuals. Independent counters at the global-only, local-only and mixed return branches cross-check the timed call counts. Pre-step wing-lift work remains in the pre-step bucket.
- Simulation: preflight checks; auxiliary, load, rotor, derivative and state validation; rotor callback; rigid-body derivative; RK stage arithmetic and final normalization; tick commit; checkpoint copies; signal dispatch; and named callback/glue residuals. The three stage callbacks include their `axpy` argument evaluation, which is subtracted from that parent before reporting RK arithmetic separately. Load-callback residuals subtract all four load evaluations' nested force timers once.
- Each run compares **12 × 240 boundaries and 95,040 finite float64 values**, including state, sampled auxiliaries, continuous state and loads. Original Godot packed-array bytes match between baseline and instrumented runs and also match the decoded numeric arrays, including signed zero. The runner explicitly requires little-endian Linux for this byte representation.
- **68 native lifecycle and 35 prepared-adapter checks** pass before measurement. Both deliberately defective adapters are rejected. Timed work and trajectory checks make zero stateless setup calls.
- **24 malformed reports** are rejected: the inherited twelve controls plus missing nested phases, removal of entire aero branches and their child timers, timer overlaps, missing/changed original bytes, a missing simulation phase, fractional durations and unknown timers. Required counters, integer durations and nonnegative exclusive residuals are checked on every instrumented batch and trajectory before averaging.
- Both runs use the same **617 app inputs and 37 research-code inputs**, verified before/after measurement. Run 2 stages the app from a fresh clone; the new research runner and hashed prepared binary are explicitly supplied from the working tree. Generated instrumentation and build inputs are hashed. [Validation](validation.json) retains checks and artifact hashes; source and instrumented lint each report zero errors and the same 12 existing warnings.

During probe development, unique-anchor checks rejected an ambiguous reset/step signal pair before instrumented execution. Review caught an RK arithmetic double count and a missing-branch validation gap; the retained runs include both fixes and the new rejection controls. Earlier development outputs are excluded from the retained evidence. No production-file change requires a new full app regression in this measurement-only step.

## Scope and reproduction

[Runner and commands](../../../../../research/propwash/e0b6p/dynamics-cost/README.md). Preserve the raw reports; the checked-in reducers can replay them. Instrumentation is generated only in disposable app copies, with exact source anchors and provenance guards. Its extra locals, callback arguments and timer calls change execution cost, so residuals include observer bookkeeping.

The fixtures begin airborne and have no continuous axial-transport states. They do not measure loaded wheel contact, player rendering, model reload or native Windows/macOS execution. Reverse-cutoff timing batches bypass the native kernel, while the longer trajectory may re-enter active flow. No independent aerodynamic calibration or pilot acceptance follows from this software proof. Production remains GDScript and Stik propwash remains off.

Ready-to-paste commit message: `E0b6p: split aero and simulation cost; proof: two exact 95,040-value buffer runs, 103 contract checks and 24 corrupted reports rejected per run`
