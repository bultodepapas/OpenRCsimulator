# DATA-2b — Stop repeated induced-flow inversions

2026-10-08 · **Status: complete; focused proof and full regression passed.** Scope: two-line termination guard in `AircraftData._induced_map`, plus offline proof tools. DATA-2's broader load-time acceptance remains open.

## Measured cause and change

Whole-load profiling found approximately half the remaining cost in the already optimized stall envelope, with another 3.2–3.3 ms in induced-flow setup. That setup inverted its six-by-six matrix 81 times: 80 bisection iterations plus the final map. The last 24 iterations recomputed an identical rounded midpoint.

The solver now stops before matrix inversion when `a0 == lo or a0 == hi`. All four fleet aircraft require 57 inversions, including the final map. No force law, coefficient, search bracket, arithmetic expression, schema, cache or tick-loop code changed. This startup optimization does not change aerodynamic calibration.

## Why the result is exact

The initial bracket `[0.1, 50.0]` is finite, positive and ordered. Each update replaces one endpoint with its rounded midpoint. Once that midpoint equals an endpoint, the original predicate can only leave the bracket unchanged or collapse it to that same value. Every remaining midpoint is identical. The code after the loop recomputes the final midpoint and matrix, so ending before the redundant evaluation preserves the derived slope, map, strip offsets and downwash fields exactly. Signed zero is unreachable in this bracket. This argument does not depend on predicate monotonicity or on the target being bracketed.

The existing 80-step upper bound remains. No tolerance-based early exit or root-acceptance change was added; synthetic out-of-range targets retain the original boundary result. Root reachability and real-aircraft calibration are distinct questions.

## Verification and timing

[Verification manifest](verification.json) records two alternating whole-load timing runs, 24 pairs per aircraft per run: **192 exact complete result comparisons**, including models, warnings, errors and exact input identity. Another **128 induced-map cases** vary target, twist, incidence and downwash, including both bracket extremes; **24 invalid inputs** retain exact refusal results. A deliberate `hi-lo < 0.01` stopping rule fails the exact comparator ([negative control](premature-stop.log)). The comparison uses serialized Variant bytes, preserving floating-point bits and field order.

Whole-loader milliseconds, warm OS file cache, shared host, no application cache:

| Aircraft | Run 1: before → after median | Run 2: before → after median | After min–max, both runs |
| --- | ---: | ---: | ---: |
| jensen_ugly_stik_60 | 12.189 → 11.727 | 12.572 → 11.439 | 10.809–14.384 |
| gp_extra_300s_60 | 13.024 → 11.584 | 12.629 → 11.726 | 11.058–16.267 |
| p51d_mustang_120 | 14.153 → 13.039 | 13.829 → 12.963 | 11.911–17.682 |
| sebart_avanti_s_a200 | 13.086 → 11.802 | 13.181 → 12.162 | 11.300–16.868 |

[Paired run 1](pairs-1.log) · [Paired run 2](pairs-2.log) · [Before profile](profile-before.log) · [After profile](profile-after.log) · [Exact cases](cases.log).

Every paired median improves. These observations are loader calls, not total app startup or cold-disk timing. The raw tails and concurrent scheduling preclude a universal 15 ms guarantee; the parent DATA-2 acceptance stays open. Instrumented component timings are diagnostic; the paired whole-load runs use uninstrumented code. An independent read-only review checked the termination proof before integration. The shared and isolated app snapshots match across 617 files ([integration record](integration.json)); static lint has zero errors and the same 12 pre-existing warnings. All 16 recorded fleet RPM/trim/240-tick hashes match [the prior G2-R1 snapshot](../../propulsion/G2-R1/after.log) exactly ([current fleet probe](fleet.log)).

The isolated full `app/test.sh` passes: **153 sections, 125 GDScript test programs**, zero engine errors, unchanged airborne goldens, four real app trimmed traces and identical 30/60/144 fps state/wake hashes. [Full log](suite.log). Existing ObjectDB shutdown warnings remain separate lifecycle debt. The checkout includes the shared runway/UI and G2-R1 work; all 617 app files match the integrated tree. A first checkout attempt exhausted temporary disk space; after removing only this agent's old temporary checkouts, the sparse checkout includes `app`, `assets`, `research`, `tools` and the required `docs/research/propwash/E0b2`/`E0b3b` geometry reports. No check was disabled.

## Reproduce

From the repository root:

```sh
python3 research/aircraft-data/data2b/verify.py --output /tmp/data2b-new-evidence
app/test.sh
```

The verifier requires an empty output directory and uses only Python's standard library and the pinned Godot. It reconstructs the old loader by removing exactly the new guard, instruments disposable copies, runs parity/negative controls and refuses changed inputs or incomplete outputs. No mutation touches the shared app. Private GDScript drivers receive loader paths from the verifier and refuse absent paths.

[Tool source](../../../../research/aircraft-data/data2b/verify.py) · [Previous optimization](../DATA-2a/README.md) · [Loader](../../../../app/physics/aircraft_data.gd). Source and generated fixtures are repository-owned under its MIT license; no third-party data or dependency was added.

Ready-to-paste commit message:

```text
DATA-2b: stop redundant induced-map inversions at float64 convergence

Proof: 192 exact load pairs, 128 map cases, 24 unchanged refusals,
premature-stop mutation rejected, full app/test.sh and unchanged fleet hashes.
Fleet inversions fall from 81 to 57; preserve all derived data and physics.
```
