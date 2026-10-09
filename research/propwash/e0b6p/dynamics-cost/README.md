# E0b6p — Aerodynamic and simulation cost probe

2026-10-08 · **Status: research-only Linux instrumentation.**

This extends the [prepared-path probe](../prepared-cost/README.md) with nested aero and simulation timers. It copies the app before editing, preserves physics expressions and checks original Godot float64 buffer bytes at every trajectory boundary. Production files are never instrumented.

From the repository root, with the existing prepared native library:

```sh
python3 research/propwash/e0b6p/prepared-model/build.py --jobs 2
python3 research/propwash/e0b6p/dynamics-cost/run.py \
  --godot "$(app/get-godot.sh)" --output /tmp/prepared-dynamics-cost
```

Choose a new output directory for every run. `--project /path/to/app` selects a source snapshot; `--build /path/to/build.json` selects the hashed candidate manifest. Run benchmarks sequentially. Inspect generated scripts under `OUTPUT/work/app`, raw reports in `baseline.json` and `instrumented.json`, and the validated summary in `dynamics-evidence.json`.

The fixtures, explicit preparation protocol, lifecycle/adapter checks and 24-tick timing batches are inherited unchanged. Six regimes at swirl 0 and 0.4 each have one warmup and five measured batches, then 240 evolving trajectory steps. Instrumented timing pairs alternate enabled/disabled order. State, sampled auxiliaries, continuous state and loads are compared as finite float64 numbers and as original buffers, concatenated in that order and hex-encoded outside timing. The byte proof is for this little-endian Linux host.

Aero timers measure blend selection, global loads and local loads. Global loads split out the lagged-downwash correction, including its instantaneous wing-lift solve. Local loads split into setup, geometric angles, coupled strip forces and both tails. Return-array construction and timer bookkeeping remain in explicitly named residuals. Top-level timers wrap call sites in `Aero.loads`; the downwash child timer is inside `_global_loads`; independent pre-step wing-lift calculations retain their original pre-step bucket.

Simulation timer definitions and expected calls are written into the evidence by `simulation_cost.py`. Nested children are subtracted only from their immediate measured parent. Every instrumented batch and trajectory must have the required counters, finite nonnegative durations, and nonnegative exclusive residuals before aggregation. The final exclusive means must sum to the measured step timer. Independent return-branch counts prevent a missing aero branch and all its child timers from disappearing into a residual. Twenty-four report controls reject counter/timer deletion, overlaps and original-byte corruption.

All source app files, research code, generated instrumentation and build inputs are hashed. The runner rejects inputs changed during measurement. The original native lifecycle and adapter checks also run, including two defective-adapter controls. Raw reports retain all arrays, bytes, timer counters and batches for independent reduction.

These are shared-host batch averages with observer overhead, not individual-tick latency percentiles or performance acceptance. The synthetic aircraft begins airborne, has no continuous axial-transport state, and does not measure loaded gear, render frames or physical flight realism. Preserve the guards and integration scheme when choosing a subsequent optimization.

Measured results and limits: [E0b6p evidence](../../../../docs/research/propwash/E0b6p/dynamics-cost/README.md).
