# H8-R1 — Checkpoint restoration integrity

2026-10-08 · **Status: completed; 149 integrity checks, four guard mutations, exact fleet continuations and segmented full regression verified.** Main-line ROADMAP H8-R1.

Checkpoint acceptance now validates the derived inertia inverse and clock's ability to advance, and checkpoint production uses the same acceptance rules. Restoring a compatible fresh simulation establishes its fixed timestep. Normal stepping, force laws, aircraft data and checkpoint v1 fields are unchanged.

## Reproduced failures

[Before](repro-before.log) and [after](repro-after.log) use the same [probe](reproduce.gd):

| Case | Before | After |
| --- | --- | --- |
| Restore tick 1 into a compatible `Simulation.new()` that has not been reset | Returns true, but next step faults because `_fixed_dt` remains zero | Restores the validated timestep and advances to tick 2 |
| Emit a checkpoint with quaternion scalar changed to 2 | Emits a checkpoint that its own reader rejects | Returns an empty dictionary without repairing or mutating the owner |
| Restore `INT64_MAX`, then step | Returns true; tick wraps negative and reported time reverses | Rejects before any mutation |
| Finite positive-definite inertia with an overflowing inverse | Preflight/restore succeed and install infinity in the inverse cache and invalid configuration in rollback history | Preflight, restore and producer reject it |

The inverse fixture has diagonal inertia `(1e-310, 1, 1)` kg·m². Its determinant is positive and finite, but the first inverse entry is approximately `1e310`, beyond float64. The test computes the tiny entry as `1e-300 * 1e-10`; this Godot build's decimal literal parser rounds `1e-310` to zero. A second finite, ill-conditioned tensor independently exercises the same rejection. These are numerical fixtures, not plausible aircraft parameters.

## Boundary contract

- Producer and consumer share validation; nonempty output must pass the same owner's preflight. Production still refuses faulted owners and changes to the committed continuous-state layout.
- A native integer tick must support `tick + 1` without wrap. At its saved timestep, `t`, `t + h/2`, `t + h` must be distinct and ordered, and the next tick's computed time must advance. Finite time alone cannot establish this. This is a numerical representability check, not a duration cap or an accuracy guarantee for very long runs.
- Positive-definite finite inertia is necessary but not sufficient: the actual inverse used by the integrator must also remain finite. Validation runs before changing dynamic state, cached values, fault/pause state or rollback history.
- A successful restore copies the saved timestep, keeps the existing owner configuration/callbacks, pauses, and emits no completed-step sample. A compatible fresh kernel can continue without a prior reset.

This step changes checkpoint boundaries only. It validates the next step at the restored boundary; it does not add an ongoing live-step clock-exhaustion policy, guard arbitrary direct writes to the live tick counter, authenticate snapshots, serialize callbacks, or establish semantic consistency between recorded finite loads and a changed callback. The owning session still verifies model/ground identity and mode semantics. Checkpoint compatibility remains native, same-build physics replay rather than portable interactive save files.

## Proof

[The integrity suite](../../../../app/tests/test_checkpoint_integrity.gd) passes 149 checks:

- Fresh-owner exact continuation at 120/240/480 Hz, both body-only and coupled nonautonomous dynamics; native serialization, paused restore and no spurious tick.
- Rejected clock/time values, missing fields and nonfinite body/previous/continuous/auxiliary/input/load entries.
- Producer rejection of invalid clock, stop condition and quaternion; both overflowing-inverse fixtures.
- Byte-for-byte preservation of dynamic fields, configuration, derived caches, fault/pause state and rollback history after failed preflight/restore; no pause/fault signals; valid recovery afterward.

The existing H8 suite passes 90 checks. [Fleet proof](fleet-proof.json) retains eight byte-identical complete checkpoints across four aircraft and exact mid-flight continuation before/after. [Four guard-removal mutations](mutations.json) fail the integrity suite; the unmodified control passes. Mutations use temporary scripts outside `app/` ([runner](check_mutations.py)). Lint has zero errors and the same 12 existing warnings.

Regression coverage includes all 115 GDScript test programs plus the full application/contract/trace/frame-rate tail. Seven focused suites also pass after integration into the shared tree. Full regression and final shared-tree checks are recorded in [verification](verification.json), with baseline and source hashes. The first `app/test.sh` run reached the landing test's 60-second timeout without an assertion failure. Remaining checks were resumed from that test with a 180-second process timeout using [this runner](resume_suite.py); assertions and test bodies were unchanged. Both logs are retained, and verification checks that their combined test inventory covers every `test_*.gd` file. These establish numerical/software integrity, not empirical aircraft validation.

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_checkpoint_integrity.gd
python3 docs/research/simulation-state/H8-R1/check_mutations.py --project app --godot "$(app/get-godot.sh)"
$(app/get-godot.sh) --headless --path app --script "$PWD/docs/research/simulation-state/H8-R1/reproduce.gd"
app/test.sh
```

Original repository work, verified with pinned Godot 4.7.2 and source inspection. No external material copied.

Commit message: `H8-R1: validate checkpoint clocks and derived state; prove 149 checks, exact fleet continuations and segmented headless regression`
