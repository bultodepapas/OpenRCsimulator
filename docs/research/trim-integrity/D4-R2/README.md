# D4-R2 — reject nonfinite trim convergence

2026-10-07 · **Status: complete; implemented and verified. Valid fleet trims and flight checkpoints are unchanged.**

## Defect and boundary

With a valid Stik model, `Trim.solve("level", 15.0, model, NAN, throws)` returned `ok=true`, `residual=nan`, `message="trimmed"`. A valid-gravity control converged at approximately `1.1e-13`. The linear solver independently returned `[nan]` for `A=[[1]]`, `b=[NAN]`. The original source reproduces both failures with a valid positive control in the [isolated mutation runner](check_mutations.py).

The direct reproduction identifies the cause: both `NaN > convergence_tolerance` comparisons are false. Invalid arithmetic therefore bypassed the iteration and failure branches. Nonfinite values also bypassed pivot comparisons. A separate broad hypothesis search was unnecessary for this deterministic guard failure.

Session preparation already checked state, controls and loads downstream; this is not evidence that the default flight launched with NaN. It repairs the public trim result contract and prevents modal analysis from treating a numerical failure as a valid equilibrium. The solver still expects a structurally valid loader model; it does not duplicate the aircraft schema validator.

## Change

- Refuse unsupported modes, nonpositive/nonfinite speed, negative/nonfinite gravity, and absent/nonpositive/nonfinite/nonnumeric control throws.
- Check initial and iterated residual norms, finite-difference samples, Newton iterates and successful output values. Numerical failures retain the documented result keys with unavailable values marked NaN; failure reporting does not reevaluate a poisoned candidate or divide by invalid throws. Scenario adapters read angles even on failure, so the key contract remains intact.
- Validate the linear system's square shape, packed float64 row types and finite coefficients/RHS; reject overflow during elimination and back substitution. Return an empty solution on refusal without mutating inputs.

The valid-path arithmetic order, pivot threshold, Newton iteration limit, convergence tolerances and retry guesses are unchanged. No aerodynamic forces, aircraft parameters, session code or golden expectations are changed. Guards execute during trim preparation, not per physics tick. This step makes no new conditioning guarantee for the existing Gaussian solver.

## Proof

- **700 focused checks:** valid trim/pivot controls; NaN/Inf inputs and model residuals; finite speed causing overflow; invalid throws/mode; failure-key compatibility; scenario/modal refusal; exact repeatability and direct model immutability; malformed/singular matrices; elimination and back-substitution overflow; detached inputs.
- **Original defect and three isolated mutations:** the original solver fails the two specific refusal assertions while its valid trim succeeds. Deliberately accepting an overflowed solution, extra rows or extra columns is detected by the intended assertion. Malformed matrix fixtures have a nonsingular leading block, so singularity cannot conceal missing shape validation. [Results](mutations.json).
- **Exact preservation:** all 24 successful trims (four aircraft, level/glide, 0.85/1/1.15 times their start speed) and four complete 240-tick flight checkpoints match the original source byte for byte. [Fixture](fleet.gd), [fingerprints](fleet-proof.json).
- **Independent review:** Luna Max found no remaining nonfinite-success path under the loader-model precondition. Its test review prompted a direct model-byte immutability assertion. These test-only refinements were run separately while the complete suite used its frozen candidate; production code remained unchanged.
- **Full app suite passes:** 137 sections and 109 GDScript test programs on isolated baseline `0a496184ab0c583d6c67dd211ad076d9ca01ae62` plus the candidate, with separate XDG directories and pinned Godot 4.7.2. Four real-app trimmed traces complete; ordinary, wash and swirl flights retain identical 30/60/144 FPS hashes. [Full log](app-test.log), [source identity and verification inventory](verification.json). The final strengthened focused test passes 700 checks in the shared tree; lint reports zero errors (existing warnings remain).

Reproduce:

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_trim_integrity.gd
python3 docs/research/trim-integrity/D4-R2/check_mutations.py
$(app/get-godot.sh) --headless --path app \
  --script "$PWD/docs/research/trim-integrity/D4-R2/fleet.gd" -- /tmp/trim-fleet.bin
app/test.sh
```

The mutation runner checks out only the original `trim.gd` bytes at the recorded commit, into a disposable app copy. It never changes the shared tree. For exact preservation, run `fleet.gd` against the recorded baseline and current app with separate output files, then compare bytes; native Variant encoding is a same-build check, not a portable interchange format.

Sources: repository [trim implementation](../../../../app/physics/trim.gd), [focused tests](../../../../app/tests/test_trim_integrity.gd), [scenario adapter](../../../../app/sim/scenarios.gd), [modal analysis](../../../../app/physics/flight_modes.gd), [D4-R1 preparation safeguards](../../../../app/sim/flight_session.gd). Original code/evidence, repository MIT license; no external assets or aircraft measurements.

Ready-to-paste commit message:

```text
D4-R2: reject nonfinite trim results and invalid linear systems

Proof: 700 focused checks; original false-success reproduction and three
isolated mutations; 24 exact fleet trims and four exact flight checkpoints;
full app/test.sh on the identified isolated candidate (see evidence).
```
