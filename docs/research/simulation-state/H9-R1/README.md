# H9-R1 — Golden replay acceptance integrity

2026-10-08 · **Status: completed; 153 integrity checks, four guard mutations, full app suite and shared-tree replay checks passed.** Main-line ROADMAP H9-R1.

The golden reader could certify a nonfinite final body state or a replay that never advanced. It also accepted stamped auxiliary/discrete checkpoints with gaps relative to the body checkpoints. The fix stays in the test reader; flight dynamics, tolerance budgets and committed golden data are unchanged.

## Reproduced failures

[Before](repro-before.log) and [after](repro-after.log) use the same real-session probes:

- A `stepped` callback replaces the final north position with `NaN`. Previously the position-error reduction reported zero and replay passed. Godot's `maxf(NaN, finite)` can replace the invalid accumulated result with a later finite component. No subsequent simulation step exists to detect the final-state corruption.
- Removing an interior auxiliary checkpoint, then the corresponding mode checkpoint, still passed while the body checkpoint remained present.
- Setting `ticks` and all final checkpoint ticks to `INT64_MAX` passed validation. `ticks + 1` wrapped, the replay loop ran zero times, and acceptance returned true at tick zero.

## Acceptance rules

Validate live body state with the existing simulation validator before reading components or reducing their errors. Check the fault and actual tick first. A malformed body now returns a failure dictionary rather than indexing beyond its layout.

Require tick counts within `0 .. 2^53 - 1`, the contiguous exact-integer range of JSON float64 numbers, before integer conversion and loop-bound arithmetic. This is a representation bound, not a supported duration or execution-time budget; the existing test runner timeout remains responsible for stalled or excessively long tests.

Stamped auxiliary and mode tables must have the same checkpoint ticks as the body table. Auxiliary row width must stay constant throughout the record, and replay continues to require the active session's exact layout. All three tables may use an aligned sparse schedule: v1 never declared a mandatory recording cadence. Legacy body-only records remain supported. An initial-only zero-tick record remains a valid boundary comparison, not evidence of a flown maneuver.

This change does not authenticate fixtures or prove that every intended maneuver tick was recorded. Sampling still cannot detect every transient between checkpoints. E4 must separately verify that its circuit recording reaches the intended end and retains adequate sampling. Full coupled-state persistence and physical validation remain separate contracts; no new format or aerodynamic claim is introduced here.

## Verification

- [Focused test](../../../../app/tests/test_replay_integrity.gd): 153 checks cover stamped JSON and legacy replay, sparse schedules, missing/shifted checkpoints, changing auxiliary widths, clock overflow with matching endpoints, malformed numeric rows, every body component with NaN/±infinity, malformed body sizes, and recovery after rejected live faults. Structural rejection is checked before any reset or session mutation. Nonfinite tests inject corruption after the last committed step, independently of the simulation's next-step guards.
- [Guard-removal checks](mutations.json): all four mutations are detected, each with an unmodified positive control. Mutated scripts live only in a temporary directory. [Runner](check_mutations.py).
- Godot skill lint: zero errors and the same 12 existing warnings before and after.
- Full isolated app suite: 138 sections, including 110 GDScript tests; exit 0, no engine errors. Shared-tree replay checks: 153 integrity checks, 50 policy checks and four golden flights passed.
- Full app and integrated focused results are recorded in [verification](verification.json). Validation baseline and source hashes distinguish this change from concurrent uncommitted work.

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_replay_integrity.gd
python3 docs/research/simulation-state/H9-R1/check_mutations.py --project app --godot "$(app/get-godot.sh)"
app/test.sh
```

Original repository work; conclusions come from pinned Godot 4.7.2 executions and source inspection. No external material copied.

Commit message: `H9-R1: reject false golden replay passes; prove 153 integrity checks, four guard mutations and full headless suite`
