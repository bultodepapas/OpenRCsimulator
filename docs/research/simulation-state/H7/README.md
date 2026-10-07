# H7 — One-ULP sensitivity and branch signatures

2026-10-07 · **Status: complete; sensitivity, branch mutations and full Phase H regression pass.** Main-line ROADMAP H7.

## Method

`app/tests/check_math_sensitivity.py` copies the app into temporary directories and instruments only those copies. It advances `sin_` and `atan2_` to the exact next binary64 value, then replays all four air goldens. Per-tick branch tapes cover selected aero blend/local-flow, gear contact, and propulsion regime decisions. The same report compares the normal wrapper build with a copy whose call sites use direct built-ins.

A separate adjacent-float fixture places the stall blend threshold at the perturbed `atan2_` value. A controlled mutation changes the actual aero golden replay branch from `blend == 0.0` to `blend < 0.0`. The runner must detect branch-signature divergence even when all recorded state errors remain below tolerance/1000. No branch instrumentation is added to production scripts.

## Results

[`verification.json`](verification.json) and [`targeted.log`](targeted.log) are the repeatable evidence. On Godot 4.7.2, the largest one-ULP golden component error was `0.00111023 × (tolerance / 1000)`; all four golden branch signatures matched the baseline. The adjacent-float stall weight crossed from `0.99002646` to `1.0`. The controlled branch mutation was detected in all four actual golden replays, with maximum state error `0.000333067 × (tolerance / 1000)`. State, auxiliary, and mode fingerprints match the direct-built-in copies byte-for-byte on this machine.

The tapes intentionally cover selected decision points, not every conditional in the simulator. This demonstrates the branch-divergence policy for instrumented decisions; it is not complete program-wide branch coverage or cross-platform determinism evidence.

Reproduce with:

```sh
OPENRC_TEST_GODOT="$(app/get-godot.sh)" python3 app/tests/check_math_sensitivity.py
app/test.sh
```

Sources: [sensitivity runner](../../../../app/tests/check_math_sensitivity.py), [golden replay](../../../../app/tests/golden_flights.gd), [math wrappers](../../../../app/physics/math3d.gd), [numerics investigation](../../roadmap-investigations/01-numerics-architecture-performance.md). No external material used.

Final integration evidence: [suite, scene/resource checks and source fingerprints](../H8/integration-verification.json).

Commit message: `H7: gate one-ulp replay sensitivity; detect golden branch mutation below the state tolerance`
