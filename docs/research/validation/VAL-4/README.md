# VAL-4 — Symmetry, similarity and flight energy

**Status:** ✅ implemented and verified, 2026-10-08. Scope: external regression tooling; no changes to M2, aircraft data or the running simulator. These are software properties, not independent flight validation.

[Commands and contract](../../../../research/validation/metamorphic/README.md) · [GDScript checks](../../../../research/validation/metamorphic/checks.gd) · [Isolated mutation runner](../../../../research/validation/metamorphic/run.py) · [Recorded proof](verification.json)

## What is exercised

The fixture wires the real `FlightSession` callbacks into `Simulation`, then advances actual RK4 ticks off-tree. It includes servo slew, the sampled tail-downwash lag, gravity, aerodynamic blending and the full inertia tensor. Contact is explicitly disabled; zero rpm and zero wind isolate the properties being tested. No numerical helper replaces the flight equations.

- **Mirror:** four initial states (attached, stalled, reverse flow and zero translation with rotation), full-aileron reversals, 240 ticks each and their reflected flights. A symmetrized inertia removes Jxy/Jyz but keeps Jxz. Every body and auxiliary value must reflect within 1e-12 absolute. One-sided surface probes also check the attached and local aerodynamic paths.
- **Froude:** those four trajectories at four length factors (0.25, 2.25, 4, 9), with consistent mass, inertia, geometry, servo time, downwash length and timestep. After undoing the scale, component error divided by `max(1, abs(baseline))` must stay below 1e-9. This is a mixed absolute/relative bound, not pure relative error near zero.
- **Energy:** 32 reproducible random initial attitudes/flows/rates, original asymmetric inertia, neutral controls, 240 ticks each. Total translational/rotational kinetic energy plus `-m*g*down` potential energy must not rise by more than 1e-9 J in any step.

The report counts actual attached, blended and local samples, moving servos and transient downwash. Those counts are aggregate coverage, not a claim that each scenario exercises every branch. The baseline contains 56 complete flights and 7,680 energy increments. Seed: 64007.

Observed maxima: mirror error 7.11e-15; scaled-state error 5.30e-15; positive energy increment 0 J. All baseline checks pass. Static app lint reports zero errors and the same 12 existing warnings before/after; a debug parse of the new script reports no errors or warnings in that script (14 warnings are in existing dependencies).

## Proof that the tests detect defects

The runner copies the app into a temporary directory and first requires its unmodified report to equal the original report. It then applies each source mutation separately, restores the copy after each run, and requires the named property to fail with engine execution, flight integrity and branch coverage still valid:

| Mutation | Required failure |
| --- | --- |
| Reverse only `Cnda_left` in the global yaw expression | Mirror symmetry |
| Add a fixed 3 cm outward displacement to each local wing station | Froude scaling |
| Turn wing drag into anti-drag at one tenth magnitude | Energy non-increase |

A full-strength drag sign reversal caused numerical runaway in several trajectories. That was not accepted as targeted proof; the smaller positive-work mutation keeps the fixture valid. Similarly, ordinary differential ailerons can hide equal-sign yaw derivatives through cancellation. The one-sided attached-flow probe is required to expose the specified Cnda mutation.

The Python harness has seven regression tests for positive controls, zero-exit engine errors, incomplete output, inconsistent success, wrong mutation failures, timeouts and preserving an existing report after a failed file replacement. The command rejects source changes during verification and publishes evidence only after all runs pass.

## Limits and reuse

Froude similarity holds here for unchanged dimensionless coefficients, density and gravity; Reynolds-number effects and real-airframe similarity are not established. Power, wash transport, fuel, contact/crash behavior, other aircraft and device timing remain separate work. Monotonic energy is a tested property of these passive fixtures at the stated timestep, not a theorem for every possible state or control history.

The runner is deliberately separate from `app/test.sh`, which another track is editing. Re-run it after physics changes; it fails if source anchors or the expected roster change rather than silently skipping proof. The source hashes and full baseline/mutation outcomes in `verification.json` identify precisely what was checked.
