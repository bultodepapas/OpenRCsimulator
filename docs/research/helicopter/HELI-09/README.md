# HELI-09: prepared helicopter aerodynamic evaluation

**Date:** 2026-10-13. **Status:** prepared stage API and parity evidence; full-flight cost and target-hardware timing remain open.

`AerodynamicStage.prepare(...)` validates the three immutable rotor/airframe models and stage constants once, then returns a read-only context. `fast_evaluate(context, ...)` consumes a new `[a1,b1,vi]` and caller-supplied flight inputs on every query. It retains finite, domain and output guards. It stores no state or previous-stage loads. Existing safe `evaluate(...)` and standalone component APIs remain available as reference paths.

The compact no-diagnostics path avoids repeated configuration-domain scans, intermediate stage dictionaries and three airframe piece results. It preserves the existing equations and the complete compact payload. Diagnostics use the same detailed paths as the reference. No rotor law, inflow pass count, wake equation or physical parameter was changed for timing.

## Evidence

[`test_heli_performance_context.gd`](../../../../app/tests/test_heli_performance_context.gd) passes 1,087 checks. It compares complete reference and prepared result dictionaries, byte-compares the six loads and three derivatives, and covers hover, forward flight, VRS descent, windmill, crosswind with rotation, repeated hover, 128 seeded inputs, readonly-context mutation, invalid vectors, commands and setup parameters. The earlier 49-check [`test_heli_aerodynamic_stage.gd`](../../../../app/tests/test_heli_aerodynamic_stage.gd) remains the legacy stand check.

The paired [`bench_heli_performance.gd`](../../../../app/tests/bench_heli_performance.gd) benchmark ran in one Godot 4.7.2 process on Windows with an AMD Ryzen 9 5900X. It warmed both paths, alternated call order across nine rounds, and timed 2,000 fixed hover evaluations per path per round. Median compact evaluation time fell from 131.089 µs to 88.7605 µs (1.477×, 32.3% lower). The range across round means was 114.684–141.778 µs safe and 79.781–97.896 µs prepared. Load checksums matched exactly, and all warmup full dictionaries matched. Raw samples and component probes are in [`paired-hover-2026-10-13.json`](../../../../research/helicopter/performance/paired-hover-2026-10-13.json).

The component profiles help locate cost but are separate calls and do not sum to the joint-stage time. In particular, the prepared main-stage microprofile uses its dictionary-returning wrapper; the joint fast path uses the prepared-parts helper.

This fixed hover microbenchmark remains above the proposed 37 µs/evaluation target. It does not establish whole-flight cost or the <500 µs/tick route; root integration must time a complete representative flight tick before drawing that conclusion. No flight-test or physical-validation claim is made. Further optimization must preserve input/output guards, old public APIs, complete payload parity, and the source equations.

Run the focused proofs from the repository root:

```powershell
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_heli_performance_context.gd
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_heli_aerodynamic_stage.gd
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/bench_heli_performance.gd
```
