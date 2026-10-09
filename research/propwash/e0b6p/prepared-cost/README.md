# E0b6p — Prepared-path cost attribution

2026-10-08 · **Status: research tooling; production remains GDScript.**

Measure the retained prepared-model candidate before changing its interfaces. The two experiments below use disposable app copies and preserve the production sources, aircraft data and prepared candidate. [Results, proof and limits](../../../../docs/research/propwash/E0b6p/prepared-cost/README.md).

## Whole ticks

Build the existing candidate if needed, then run from the repository root:

```sh
python3 research/propwash/e0b6p/prepared-model/build.py --jobs 2
python3 research/propwash/e0b6p/prepared-cost/tick_run.py \
  --godot "$(app/get-godot.sh)" --output /tmp/prepared-tick-cost
```

The output directory must not exist. `--project /path/to/app` selects an app snapshot; `--build /path/to/build.json` selects its hashed prepared-library manifest. Generated instrumentation remains in `OUTPUT/work/app` for inspection. The source app, build inputs and harness are hashed and checked for changes during measurement.

The runner reuses the original twelve-case attribution fixtures: forward, stall, static thrust, spin, reverse fade and reverse cutoff, each with swirl 0 or 0.4. Each model is explicitly prepared after setup; no stateless call is allowed during the timed work or trajectory. It checks the existing 68 native lifecycle and 35 adapter cases, including two deliberately broken adapters.

One warmup and five measured 24-tick batches retain the uninstrumented baseline. Instrumented batches alternate enabled/disabled order to report observer overhead. Each case then compares 240 state, auxiliary, continuous and load boundaries bit for bit, with finite/shape checks. Twelve malformed-report controls must be rejected. Preparation, setup and trajectory comparisons are outside timing.

Exclusive whole-tick buckets are air data, aerodynamics, propulsion, airborne ground checks, pre-step without its nested air calls, native dispatch, adapter thrust/torque, adapter remainder and simulation remainder. The adapter's native-dispatch timer includes GDExtension binding, dynamic inputs, kernel work and result creation. Adapter remainder is the outer wake timer less its two disjoint nested timers. Simulation remainder includes untimed glue, validation, RK arithmetic, callbacks and timer bookkeeping; it is not integration cost alone.

`tick-evidence.json` retains per-batch component and observer timings, exact trajectory comparisons, lifecycle results, hashes and negative controls. `baseline.json` and `instrumented.json` retain all boundary arrays and raw counters.

The fixtures are uncalibrated smooth-wake experiments. They start airborne and have empty continuous wake state; they do not time loaded gear contact or axial transport. Reverse cutoff can re-enter active flow in the longer trajectory, so counts are checked against the calls actually made. Independent native microbenchmarks use different workloads and must not be subtracted from these whole-tick measurements.

No production native integration, performance acceptance or physical flight validation follows from this experiment alone.

## Native phases

Build the stateless baseline and prepared candidate first if their libraries are absent. The new builder creates a separate instrumented candidate under `.tools/native-prepared-attribution`; it never replaces either existing binary.

```sh
python3 research/propwash/e0b6p/native/build.py --jobs 2
python3 research/propwash/e0b6p/prepared-model/build.py --jobs 2
python3 research/propwash/e0b6p/prepared-cost/native_build.py --jobs 2
python3 research/propwash/e0b6p/prepared-cost/native_run.py \
  --godot "$(app/get-godot.sh)" --output /tmp/prepared-native-cost
```

Use a fresh output directory and run separately from the whole-tick profiler. `--project` selects a source app; `--keep-work` retains the staged projects. The locked Linux compiler and godot-cpp build machinery come from the existing native experiment. No new dependency version is introduced.

Six fixed regimes each use 500 warmups and seven batches of 3,000 direct calls and adapter calls. The runner verifies native lifecycle, adapter, field and oracle contracts, exact output bytes, the adapter's reverse-cutoff bypass, phase counts and exclusive accounting. Nine deliberate report corruptions must fail. App, harness and build hashes must remain stable throughout the run.

`native-evidence.json` contains the phase summary, checks and provenance. `native-baseline-profile.json` and `native-instrumented-profile.json` retain all raw timings, counters and loads. Static/dynamic validation scopes preserve the original short-circuit order. Inner phases are disjoint; prepared-method and kernel totals are inclusive. Per-batch residuals retain bookkeeping. The calibrated clock-pair subtraction is an estimate, not removal of all instrumentation overhead. A direct reverse-cutoff call still validates; the adapter bypasses native dispatch.

The stateless baseline and instrumented candidate run in separate processes. Their timing difference is descriptive, not a causal speedup. The external-to-method residual includes marshalling, return conversion and remaining script overhead; do not call it pure binding cost or subtract it from the independent whole-tick workload.
