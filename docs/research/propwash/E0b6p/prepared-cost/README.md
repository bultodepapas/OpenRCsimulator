# E0b6p — Prepared-path attribution

2026-10-08 · **Status: prepared-path attribution verified on Linux. E0b6p and Gate P remain open; production remains GDScript.**

This is the next bounded experiment from the [prepared-model report](../prepared-model/README.md). It can run on Linux while the owner's PT2 trial remains pending. It measures the research candidate without changing force laws, aircraft inputs, preparation semantics or production code.

## Whole-tick result

The prepared candidate still has substantial cost outside its wake backend. Across the active instrumented swirling cases, aerodynamic loads take about 145–189 µs/tick, and the simulation remainder about 142–167 µs/tick in run 1. Native dispatch takes 110–126 µs/tick; the rest of the wake adapter takes about 60–68 µs/tick, including its repeated thrust/torque calculation. Reducing one small native validation phase cannot be assumed to close the whole-tick gap.

Two runs on the shared Linux i5-10500 host use Godot 4.7.2 and the same existing prepared binary. Each baseline has one warmup plus five 24-tick batches. The instrumented copy alternates timer-enabled/disabled order, again excluding warmup. Setup, model preparation, checkpoint restoration and comparisons are outside timing. These are **batch-average medians**, not individual-tick latency percentiles or quiet-target acceptance.

| Swirl 0.4 regime | Uninstrumented prepared median, run 1 / 2 (µs/tick) | Instrumented scaffold, timers disabled, run 1 / 2 (µs/tick) | Paired enabled-minus-disabled median, run 1 / 2 (µs/tick) |
| --- | ---: | ---: | ---: |
| Forward | 540.92 / 499.75 | 567.62 / 559.54 | -6.46 / 45.29 |
| Stall | 574.12 / 591.83 | 583.88 / 572.38 | 25.08 / 67.00 |
| Static thrust | 497.88 / 483.17 | 516.92 / 483.75 | 83.17 / 39.50 |
| Spin | 557.62 / 533.12 | 542.62 / 514.38 | 48.50 / 83.71 |
| Reverse fade | 504.12 / 510.25 | 506.04 / 490.62 | 27.67 / 39.00 |
| Reverse cutoff | 352.00 / 355.29 | 419.46 / 357.92 | -15.04 / 31.00 |

The spread, negative paired deltas and differences between separately measured baseline/scaffold runs prevent a stable overhead estimate. They do not establish an optimization. No observer-cost subtraction is used to claim the 500 µs budget. Stall and spin remain above it in both baseline runs; this experiment does not close Gate P.

The [run 1 report](tick-run1/tick-evidence.json) and [fresh-clone run 2 report](tick-run2/tick-evidence.json) retain every component, batch and paired sample. Their exclusive component means add to each run's measured `Simulation.step` timer. The adapter split subtracts only its two disjoint nested regions: native dispatch and thrust/torque. Native dispatch includes dynamic argument decoding, binding, kernel work and result creation. The simulation remainder includes RK arithmetic, guards, callbacks, untimed glue and instrumentation bookkeeping; it is not integration cost alone.

## Native phases

The separate [native report](native/native-evidence.json) uses six fixed states, 500 warmup calls and seven batches of 3,000 calls per regime, through both direct calls and the prepared adapter. The generated library retains validation order and numerical expressions; its [build manifest](native/build.json) records the locked g++ 13.3.0 toolchain and source/library hashes.

| Direct prepared call | Static validation (µs) | Dynamic validation (µs) | Axial profile loads (µs) | Distributed swirl (µs) | Complete prepared method, raw (µs) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Forward | 0.267 | 0.023 | 0.813 | 18.523 | 21.000 |
| Stall | 0.332 | 0.027 | 1.016 | 22.459 | 25.531 |
| Static thrust | 0.306 | 0.026 | 0.831 | 17.638 | 20.481 |
| Spin | 0.305 | 0.021 | 0.967 | 23.485 | 26.282 |
| Reverse fade | 0.327 | 0.031 | 0.892 | 18.548 | 21.472 |
| Reverse cutoff | 0.311 | 0.023 | 0 | 0 | 1.541 |

Inner phase medians subtract the measured 19 ns clock-pair cost for the actual number of timer pairs. The raw complete method includes instrumentation and all other phases. Preserve the [raw counters](native/native-instrumented-profile.json): clock correction does not remove counter bookkeeping or other observer effects, and independently computed medians are not additive. The report validates disjoint phase accounting per batch and derives residuals from each batch before aggregation.

Native dynamic input copies/decoding cost 0.50–0.63 µs/call raw in active regimes. External-to-method residuals are 1.15–1.60 µs/call after an empty-loop estimate; they include binding/marshalling, return conversion, Variant work, residual script overhead and quantization. They do not isolate pure binding cost. One preparation per fixture took 28–53 µs including instrumentation; these single samples are not a startup-cost benchmark.

The **direct** reverse-cutoff control still enters the prepared method and validates inputs before returning zero. The **adapter** control bypasses native entirely: zero kernel calls in each 3,000-call batch, with about 4.95 µs/call external adapter cost. Keep both controls. Baseline stateless and instrumented prepared measurements run in separate processes; they establish exact outputs, not a causal timing speedup. No native phase is subtracted from the different evolving whole-tick workload.

## Correctness and evidence integrity

- Both runs compare **12 cases × 240 boundaries**, covering state, sampled auxiliaries, continuous state and loads: **95,040 float64 values match bit for bit after full-precision JSON decoding**. Every scalar is checked for finiteness, including when both reports contain equal values. This compares reconstructed float64 bytes, not hashes of the original Godot buffers.
- The existing **68 native lifecycle and 35 adapter checks** pass before timing. Two actual broken adapters are rejected: accepting a smooth/legacy route change and bypassing prepared dispatch. Timed work and trajectory checks report zero stateless setup calls.
- **Twelve malformed-report controls** are rejected: missing dispatch calls, stateless fallback, truncated trajectories, changed loads, matching nonfinite states, overlapping timers, wrong roster, fractional counters, missing timing batches, duplicate observer pairs, changed workload metadata and missing elapsed timers.
- Each run hashes all **617 app inputs**, the candidate binary/build sources and the relevant harness files, then checks them again. Run 2 uses a fresh `git clone --local --no-hardlinks --dissociate` at `4cd669c`; the research runner and explicit native build are supplied from this working tree. No ignored app resources are copied into that source clone.
- Raw arrays and counters are preserved in [run 1 baseline](tick-run1/baseline.json.gz), [run 1 instrumented](tick-run1/instrumented.json.gz), [run 2 baseline](tick-run2/baseline.json.gz) and [run 2 instrumented](tick-run2/instrumented.json.gz). Hashes in each report refer to the decompressed JSON bytes. Generated instrumentation remains in the local runner output for inspection and can be reproduced from the hashed sources.
- The instrumented native binary passes **68 lifecycle, 35 adapter, 165 field-contract and 297 oracle/native comparisons**, plus both actual adapter mutations. All six direct and adapter output vectors equal the stateless baseline bytes. **Nine native report corruptions** are rejected, including fractional timers and phase sums exceeding their parent total. Native provenance remains stable across 617 app inputs, 44 harness files and 14 build inputs; full maps are retained.
- [Validation summary](validation.json): engine parse checks and measured runs pass; source and instrumented app lint report zero errors and the same 12 existing warnings. No production file changes require a new full app regression. During probe development, the counter roster caught an omitted per-fixture preparation reset; a subsequent indentation mistake was rejected before timing. The successful native evidence excludes those failed runs.

## Decision and next bounded work

Keep the prepared candidate outside production. Repeated static validation is only about 0.3 µs per direct call here; removing it would not plausibly close the observed whole-tick shortfall. Preserve the guards and explicit model lifecycle. Distributed swirl dominates the native method, while aerodynamics and the simulation remainder remain substantial outside it.

Follow-up: [nested aero/simulation attribution](../dynamics-cost/README.md) now completes this measurement and selects a bounded wing-loop experiment. The original next-step scope was to split `Aero.loads` into local wing/tail work and split the simulation remainder into validation/checkpoint bookkeeping, RK/rigid-body work and callback/dispatch cost on these same evolving fixtures. Select one behavior-preserving change from that evidence. Do not infer an integration bottleneck from the residual, reduce quadrature accuracy, or expand the native interface without proof. Production adoption still needs target headroom, explicit model revision ownership and native-platform qualification.

## Limits and reproduction

[Commands and timer contract](../../../../../research/propwash/e0b6p/prepared-cost/README.md). Run the two profilers separately to avoid competing CPU workloads. Keep original raw counters and positive controls; timer output alone is not proof that the prepared path was exercised.

Whole-tick fixtures start airborne, with no continuous axial-transport states. They do not measure loaded wheel contact, production model reload or the player's complete graphical frame. The reverse-cutoff timing batches bypass native dispatch; the longer trajectory can re-enter active flow, so its counts must not be assumed zero. Native direct microbenchmarks are a different workload and cannot be subtracted from these whole ticks.

Systematic startup-cost measurement, Windows/macOS native execution, model revision ownership and independent E0b7 calibration remain outside this step. Production Stik wash stays off. The software proof preserves existing model behavior; it does not validate aerodynamic realism or close the pilot gates.

Ready-to-paste commit message: `E0b6p: attribute prepared wake cost; proof: two exact 95,040-value runs, native contract checks and 21 report corruptions rejected`
