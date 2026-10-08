# E3b2-R1 — runway-start numerical integrity

**Status:** completed, 2026-10-07. Scope: `GroundStart` and its dedicated integrity test; no session, force-law or aircraft-data changes.

## Defect and repair

The original Newton solver accepted `[NaN, 0]` as a zero residual: the maximum reduction replaced an earlier NaN with a later zero. Testing NaN only in the last position missed this. Empty residuals, a short zero residual and a nonfinite initial iterate could also report convergence. The linear solver returned infinity when finite input arithmetic overflowed. [Original reproduction](repro-before.log), [corrected reproduction](repro-after.log).

The solver now requires a finite, nonempty initial iterate and exactly one finite residual per unknown at every evaluation. It checks the matrix/RHS shape and finite values, elimination and back-substitution arithmetic, the updated iterate, and the final state/anchors. Invalid operating scalars or deflections are refused before physics evaluation. RPM/density may be zero; negative RPM/density and nonpositive gravity are refused. A loaded model and a validated ground-surface table remain preconditions; valid catch-all surface bounds still use infinity.

The Newton method, difference step, iteration budget, pivot threshold and convergence tolerance are unchanged. Public failure keys remain compatible: empty state/rest-state/anchor arrays, `iterations=0`, `residual=INF`, and a reason. The session's existing failure path restores its normal airborne start.

## Verification

- **254 focused checks pass**, including every placement of NaN/infinity, wrong residual dimensions, invalid perturbations/updates, finite-input overflow, known pivoted roots, the 40-iteration failure cap, caller-input preservation, successful array shape/finiteness, and session fallback/recovery. [Final test log](focused-final.log), [shared-tree rerun](integrated.log).
- **96 complete result hashes match the original implementation**: 24 successful Stik configurations (four headings, three densities, stopped/idle RPM) and 72 unchanged refusals for the other three fleet aircraft without stiction support. Hashes include states, anchors, residuals, iteration counts and messages. [Results](starts.json), [capture script](capture_starts.gd).
- **Four isolated mutations are rejected with the intended assertions and no engine errors**: hidden NaN, unchecked initial iterate, unchecked division overflow, and accepted negative operating inputs. [Mutation results](mutations.json), [runner](check_mutations.py).
- Project lint has zero errors and the same 12 warnings before/after. [Before](lint-before.json), [after](lint-after.json). Full isolated `app/test.sh` passes **143 sections**, including goldens, four trimmed starts and matching 30/60/144 FPS flight/wake/swirl fingerprints. [Full log](app-test.log), [source identities and verification scope](verification.json). The full suite used the initial 245-check test; the final 254-check revision passed separately and in the shared tree with identical production code.

## Reproduce and limits

From the repository root:

```sh
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_ground_start_integrity.gd
"$(app/get-godot.sh)" --headless --path app --script "$PWD/docs/research/ground-contact/E3b2-R1/reproduce.gd"
python3 docs/research/ground-contact/E3b2-R1/check_mutations.py
app/test.sh
```

Run `capture_starts.gd` against identified baseline/candidate project paths using the same pinned engine. The hashes are same-platform software-preservation evidence, not independent aircraft validation. This repair does not guarantee Newton convergence for arbitrary configurations or improve conditioning. Gear stiffness, friction and real resting attitude still need field measurements. The guard work runs during start solving, not during flight ticks; no flight-performance claim is made.

Sources: [E3b2 equilibrium contract](../E3b2/README.md), [solver](../../../../app/physics/ground_start.gd), [session](../../../../app/sim/flight_session.gd), [regression test](../../../../app/tests/test_ground_start_integrity.gd), and experiments on pinned Godot 4.7.2. Repository code and fixtures use the repository's MIT license; no external data or dependency was added.

Ready-to-paste commit message:

```text
E3b2-R1: reject invalid runway-start convergence and numerical overflow

Proof: 254 focused checks, 96 exact baseline result comparisons, four
mutations rejected, zero lint errors, and full isolated app/test.sh pass.
```
