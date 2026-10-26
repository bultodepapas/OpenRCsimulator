# Reuse the current unconstrained rotor factor

2026-10-26. `RotorCoupling._evaluate_carrier` now uses the full mass factor
already produced by its own `_assemble` when no relative rotors are held.
Previously `_solve_holds` copied the unchanged full matrix and factored it again.
Nonempty hold sets retain their original reduced solve. No cross-call cache,
new trust boundary, force coefficient, integration law or receipt field changes.
Changing mass or axes still assembles a fresh matrix on every stage.

Eight production scripts pass **984 checks**, with complete checked-run receipts,
warnings as errors and zero engine diagnostics. They cover the new frozen-result
test, rotor systems, fixed shaft coupling, aircraft stage/drop, wheel coupling,
moving carriers, joint friction impulses and contact integration. The new test
pins 34 complete pre-change returns: free and held moving systems, failed holds
and malformed inputs. Inputs remain unmodified. Existing independent mechanical
work/momentum tests remain in the production cohort. The [independent review](independent-review/review.md)
adds seven checks for supported zero- and 64-rotor cases and body-only Euler
acceleration; these are separate from the 984 production assertions.

The [interleaved microbenchmark](development/benchmark.json) uses four rotors,
50 warmup evaluations and eight alternating pairs of 300 evaluations. Median
cost was 313.97 to 290.65 microseconds per evaluation, a 7.4% reduction on this
shared host. Individual pairs include regressions. This is a local method
measurement, not a whole-tick speedup or real-time qualification.

`source/` pins fourteen selected files, not the full dependency closure. Original
reports/logs and raw fixture bytes are retained. The first parity fixture used
the wrong hold key and failed eight expected-domain checks; its rejected source
and receipt remain distinct. The corrected parity run passes 82 checks. Other
draft and benchmark runs are development evidence, not extra production counts.
No golden flight or physical coefficient was re-recorded. The exact old/new
source identities and guarded promotion are in `development/`.

Reproduce the production regression with the repository checked runner and
`res://tests/test_rotor_stage_factor.gd`; the fixture is under
`app/tests/fixtures/rotor_stage_factor.bin` and its original SHA is asserted by
the test. `manifest.json` hashes retained payloads. `transport.json` checks a
disposable Git clone with `core.autocrlf=true`, including the installed binary;
the shared working tree is not staged or committed. Full landing rollout,
native audio, calibrated aircraft data and target-hardware performance remain
separate masterplan gates.
