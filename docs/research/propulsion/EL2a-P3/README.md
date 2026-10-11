# EL2a-P3 — Nested motor stage allocation

2026-10-11 · Step prefix: **EL** · **Status: compact stage result integrated and exact behavior verified; full app/offline regression passes. A whole-session speedup is not established; Gate P and physical validation remain open.**

This bounded performance step follows [EL2a-E1](../EL2a-E1/README.md). The candidate changes the nested motor result used by the dynamic-battery RK stages. It retains all scalar arithmetic, input validation, derived-power finiteness checks, ordered failure diagnostics and full endpoint telemetry. No aircraft data, coefficients, event tolerances, checkpoint layout or golden flight changes are intended.

The internal motor kernel can return five consumed fields after all existing checks, instead of allocating its thirteen-field telemetry dictionary. The supply requests this form only for stage evaluation; its own result remains the existing six-field stage contract. On overflow, the motor keeps the original diagnostic path. The supply checks its six newly derived outputs and reports their first offending public field in the same order as the full result. Mutable definitions are still validated on every call; no model cache is introduced.

## Qualification contract

- Reuse the frozen EL2a-P1 source and rotor oracles and actual source defects on Windows and Linux.
- Add a frozen-motor oracle and permanent compact-source regression, including overflow in telemetry omitted from the compact result.
- Compare complete session checkpoints and every-boundary trajectory digests for twelve powered/coast cases and eight powered-exhaustion cases.
- Independently check the twelve EL2a-E1 takeoff, stall/recovery and landing traces, then require every numeric CSV sample, non-wall-clock header and maneuver/electrical metric to match the same-engine baseline.
- Run the complete app suite and offline measurement-tool regressions.
- Qualify whole-session speed only with isolated alternating timing. Ordinary batch averages and event ticks are different measurements. A passing equality test alone does not establish a speed improvement.

The native Windows pilot run passed all trajectory/event comparisons but had large, inconsistent control-case timing changes. A separate UI-track WSL app suite was running concurrently. Those [pilot timings](pilot-windows/scope.json) are excluded from performance acceptance. The final Windows/Linux state comparisons use matching app snapshots apart from the two selected kernels and their regression/UID. They ran for preservation proof under continuing test workloads; their wall-clock timings are also excluded from performance claims.

## Verification record

Godot `4.7.2.stable.official.ed1daf0bf`; native Windows x86_64 and Linux x86_64 under WSL. The baseline physics is the completed EL2a-E1 state in `b5febac`. Raw source and engine hashes are retained with each report.

| Proof | Result | Evidence |
| --- | --- | --- |
| Frozen rotor/source plus original compact-stage regression | 10,020 + 40,106 + 74 checks per platform; all three actual defects detected and restored | [Windows](oracles-windows/report.json), [Linux](oracles-linux/report.json) |
| New frozen motor oracle and permanent regression | 20,043 + 13 checks per platform; wrong compact torque and missing bus-power guard detected and restored | [Windows](motor-windows/report.json), [Linux](motor-linux/report.json) |
| Whole-session native bytes | Twelve powered/coast cases: exact seed/end checkpoints and all 121 replay boundaries; eight exact powered-exhaustion checkpoints per platform | [Windows](parity-windows/comparison.json), [Linux](parity-linux/comparison.json) |
| Actual takeoff, stall/recovery and landing | Twelve cases and 106,572 independently checked samples per platform; 240/480 Hz, unchanged acceptance bands and metrics | [Windows](envelope-windows/report.json), [Linux](envelope-linux/report.json) |
| Exact maneuver trace comparison | All numeric samples and non-wall-clock headers match; only creation timestamp and artifact location are excluded | [Windows](envelope-parity-windows.json), [Linux](envelope-parity-linux.json) |
| Complete application | 181 GDScript test programs, 72 Python cases, all script parsing, golden flights, model contracts, CLI/trim/replay, 30/60/144 FPS and ground-contact checks; exit 0 | [Full isolated Linux run](full-suite.log) |
| Offline tools | 258 cases, including eight new trace-comparison and eight verifier failure controls | [Log](offline-tools.log) |

The selected kernels and test were copied into the live app only after the complete suite passed. Their hashes match the frozen candidate; a native Windows run of the integrated thirteen-check regression also passes. Concurrent UI/audio/visual/glow work is outside this snapshot's qualification. [Final source/evidence manifest](verification.json).

## Cost and acceptance limit

Each finite dynamics-only motor result now contains **five fields instead of thirteen**, avoiding eight temporary telemetry entries per evaluation. All diagnostic power calculations and guards still execute. This is a verified construction reduction, not a measured whole-flight speed guarantee.

A separate Linux diagnostic alternated baseline/candidate/candidate/baseline twice, using 120 valid drive/coast/rest/exhausted points and 300,000 supply calls per child process. All fixture and accumulated-output fingerprints agree. Child user+system CPU medians were **5.4075685 s / 5.3225110 s** (1.57% lower); individual pair directions were inconsistent and other host suites remained active. CPU accounting excludes time descheduled from the process, but startup, compilation, cache and frequency effects remain. This result is **inconclusive for a repeatable speedup** and is not a 240 Hz tick measurement. [Raw CPU/wall results](supply-cpu/report.json).

The step delivers a smaller temporary result with demonstrated behavior preservation and stronger reusable qualification tools. No release-performance gate is closed. Repeat whole-session timing on an otherwise idle target before making a speed claim; retain the existing 500 µs target.

## Rejected alternative

Reusing the simulation's inertia inverse looked attractive because the coupled callback recomputes it. A correct accessor also has to observe same-tick public tensor changes, signed-zero changes and the previous call's independently mutable returned array. The protected prototype adds checking/copying costs greater than the small direct inverse. It remains outside production; its exploratory measurements are not Gate P evidence. [Preserved experiment](../../../../research/propulsion/el2a-p3/inertia-prototype/README.md).

## Reproduction and limits

[Tools and commands](../../../../research/propulsion/el2a-p3/README.md). All electrical fixtures remain synthetic. Physical pack/airframe identification, rendered-frame coverage and original-target performance qualification remain separate requirements. The 500 µs/tick target is unchanged.
