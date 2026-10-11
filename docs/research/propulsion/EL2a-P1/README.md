# EL2a-P1 — Electric flight cost without changing the flight

2026-10-11 · Step prefix: **EL** · **Status: complete; exact kernel, flight/event parity, paired performance and full regression checks pass. The 500 µs/tick gate remains open.**

This performance slice follows the [EL2a overrun](../EL2a/README.md#performance). It changes no motor, propeller, battery, rotor-stop or exhaustion law. EL2b remains the separately planned polarization model. The baseline is repository commit `e64d367eba4be867e6dbff3deffe0336e706126c`.

## Implementation contract

The battery stage path produces the six fields consumed by the coupled solver instead of constructing and merging the full telemetry result. Input dictionaries and OCV points are still validated on every call. All newly derived powers and SOC rate are checked even when the caller does not request their telemetry. Invalid arithmetic retains the original diagnostic path. The supply shares its already checked motor scalars with the internal motor kernel; the standalone public motor API keeps its validation.

The fixed-axis rotor/body solve now uses scalar intermediates in the exact order of the original vector helpers. It retains full inertia, tilted axes, gyro momentum, source reaction and all existing guards. Only its returned momentum and reaction require arrays.

The coupled session shares one `Air.compute` result among shaft inflow, aerodynamic/propeller loads and wash transport within each RK stage. Nothing survives that stage. Definitions, state layout, event localization, checkpoint identity, CSV versions and endpoint electrical telemetry are unchanged. No coefficient tuning, prevalidated model cache, native extension or precision change is introduced.

## Qualification

The [reproduction tools](../../../../research/propulsion/el2a-p1/README.md) preserve the original source kernels and compare native Variant bytes, including signed zero and dictionary key types. They also exercise actual defective production copies. The performance runner imports fresh app copies, alternates baseline/candidate run order, checks complete tick counts and engine logs, and compares native checkpoints plus every-boundary trajectory digests. Restore and serialization are outside the timing window.

Powered exhaustion is measured separately from ordinary warm batches. Its eight near-empty fixtures cover 4S/6S at 120/240/480/960 Hz and compare the complete seed and final native checkpoints. The existing independent battery-flight checker supplies charge/current/power/energy checks, 30-second maneuvers and refinement evidence.

## Measured result

Godot `4.7.2.stable.official.ed1daf0bf`, Linux x86_64 under WSL, AMD Ryzen 9 5900X (24 logical CPUs). Two rounds run **baseline, candidate, candidate, baseline**, with 20 batches per case/run: 40 samples of 120 evolving ticks per implementation. No verification suites or agent timing jobs run alongside these measurements. This is a different host from EL2a's historical Linux/i5-10500 target; compare only the paired runs below.

| Configuration | Mode | Baseline median µs/tick | Candidate median | Candidate batch p95 | Median reduction |
| --- | --- | ---: | ---: | ---: | ---: |
| 4S fixed bus | Powered | 528.90 | 461.73 | 522.09 | 12.7% |
| 4S fixed bus | Coast | 519.76 | 464.80 | 588.86 | 10.6% |
| 6S fixed bus | Powered | 523.03 | 455.36 | 526.52 | 12.9% |
| 6S fixed bus | Coast | 522.07 | 464.50 | 498.32 | 11.0% |
| 4S OCV battery | Powered | 697.65 | 557.63 | 622.27 | 20.1% |
| 4S OCV battery | Coast | 697.60 | 557.83 | 626.93 | 20.0% |
| 6S OCV battery | Powered | 696.98 | 561.52 | 665.32 | 19.4% |
| 6S OCV battery | Coast | 693.40 | 557.62 | 593.28 | 19.6% |

Stik/P-51 split-shaft control medians change between −0.3% and +1.0%; this does not establish a performance change in those paths. Every one of the twelve cases retains exact seed and endpoint checkpoint bytes across all batches/runs and the same 121-boundary replay digest. [Paired comparison, all raw batch timings and event hashes](comparison.json); [original benchmark reports/logs](timings/).

The eight powered-exhaustion samples take **12.117–14.392 ms**, versus **15.747–17.030 ms** in the matching baseline controls. All eight event ticks, seed blobs and final blobs remain identical. These are individual diagnostic samples over different packs/timesteps, not an event-latency distribution. Exhaustion is still a substantial tick spike; the root algorithm and its numerical tolerances are intentionally unchanged. [Baseline event records](baseline-events/control/results.json), [candidate records](candidate-events/control/results.json).

## Verification record

- Frozen rotor oracle: **10,020 checks**, including 10,000 seeded tilted-axis/full-inertia responses.
- Frozen supply/motor oracle: **40,106 native-byte comparisons** across 10,000 seeded points, both charge-boundary branches and malformed/nonfinite/overflow inputs.
- Compact-source app regression: **74 checks**, including mutation of input definitions between calls, source-off/rest/overrun and unreported-diagnostic overflow.
- All three production-code defects are caught by the intended numerical assertion; pristine source hashes are restored after each mutation. Both [native Windows](oracles-windows/report.json) and [Linux](oracles-linux/report.json) pass from fresh disposable app copies.
- The independent battery checker passes eight 30-second maneuvers, ten refinement endpoints and 48 corrupted-trace controls per snapshot: [baseline](flights-baseline/verified.json), [candidate](flights-candidate/verified.json). [Exact comparison](flight-parity.json) confirms all 7,201 samples per flight and checkpoint/refinement fingerprints; only the single CSV wall-clock creation line is excluded.
- All eight performance-harness tests pass; they are included in `research/test-tools.sh`, whose complete offline suite passes.
- Full `app/test.sh` passes in fresh baseline/candidate clones with separate runtime preferences: **177 / 178 GDScript test programs**, all script parsing, golden flights, model contracts, CLI/trace checks, four trimmed app flights, 30/60/144 FPS checks and E5a/E5b ground-contact checks. [Baseline log](baseline-app.log), [candidate log](candidate-app.log), [offline tools](offline-tools.log), [verification manifest](verification.json). The final working app's **808 source hashes** match the measured candidate.

The [raw source manifest](source-manifest.json) records every app file and the executable SHA. The [source audit](source-audit.json) verifies **1,615 raw hashes**: seven content changes (six implementation files and the added regression) and 743 checkout-only CRLF/LF differences. Normalization is used only to classify those text differences; raw hashes and state comparisons are not normalized.

The mutation exercise found that a subnormal decimal literal did not reach the intended SOC-rate guard on the pinned runtime. The final test uses finite normal inputs (capacity `1e-100 Ah`, auxiliary draw `1e280 A`, OCV `1e-200 V`, zero pack resistance/duty), whose SOC rate alone overflows while power stays finite. Both the valid control and the actual missing-guard defect are exercised; this is a numerical boundary fixture, not a plausible pack.

Software equality preserves the established model; it does not establish measured battery accuracy. Battery medians and several fixed-bus p95 batches still exceed 500 µs. Original-target remeasurement, stall/ground cost coverage, event-latency improvements, rendered-frame acceptance and physical battery/airframe validation remain open.

## Suggested commit message

```text
perf(physics): reduce electric stage cost with exact flight parity (EL2a-P1)

Share stage air and validated motor scalars, compact battery stage results,
and preserve scalar operation order in the rotor/body solve.

Proof: 50,126 frozen-kernel checks, 74 stage checks and three actual defects
detected on Windows/Linux; eight exact 30-second flights, ten refinement
endpoints, eight exhaustion checkpoints and paired AB/BA timings.
Full baseline/candidate app/test.sh and research/test-tools.sh pass.
Battery median tick cost falls 19–20%; the 500 us target remains open.
```
