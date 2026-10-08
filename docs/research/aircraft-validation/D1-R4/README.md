# D1-R4 — Refuse invalid solved stall envelopes

2026-10-08 · **Status: implemented and verified.** Scope: `_envelope()` in the aircraft loader and its regression/proof tools.

## Defect and boundary

Finite source quantities do not guarantee a usable derived envelope. Reducing the Stik lift slope to `0.1 rad^-1` previously loaded successfully with a positive stall start near **9.93 radians**. At `1e-300`, the computed start is near `9.93e299` and adding the blend width cannot change it in float64: start and end collapse to the same value. Both cases must fail aircraft loading.

The model already requires fully separated flat-plate behavior at ±90°, including zero lift and `CD0+CD90` drag ([existing envelope test](../../../../app/tests/test_envelope.gd)). This gives a physical domain for validation without inventing a measured stall-angle limit.

For side `s = ±1` and angle magnitude `x`, signed linear lift is `s*CL0+CLa*x` and signed plate lift is `CD90*sin(2*x)/2`. A convex blend on `[0, pi/2]` cannot exceed `max(s*CL0+CLa*pi/2, CD90/2)`. Reject an unreachable requested peak before dividing by a potentially tiny slope. Require a finite positive search bracket, then finite ordered solved transitions finishing by 90°. Preserve the existing 8° linear-oracle exclusion. Finally require the sampled lift extreme to be finite and within `1e-9` absolute CL of its target.

The residual check explicitly tests finiteness: `abs(NaN) > tolerance` is false. Bisection, the historical 801-point peak grid, valid aircraft data and flight force laws are unchanged. The grid's last sample may extend beyond 90°; only the actual blend end is bounded. A positive control near 80° checks this distinction.

## Verification

[Reproduction tools](../../../../research/aircraft-data/d1-r4/README.md) use temporary copies for all negative controls. The [application regression](../../../../app/tests/test_envelope_integrity.gd) covers fleet invariants and an independent dense lift scan, tiny finite slopes, asymmetric lift offsets, invalid source numbers, an over-90° transition, constructed valid curves, refused initial loading and preservation of an existing flight after a refused reload.

[Recorded verification](proof/verification.json): **64 focused checks**, **48 exact complete fleet load pairs** (model, warnings and metadata), **16 solver-fault refusals** and **three failing negative controls**. Faults inject NaN, infinity, a wrong finite root and a NaN peak into copies. The original boundary, removed domain cap and removed NaN residual guard fail the corresponding assertions. Source hashes confirm no concurrent input edits during this run.

[Before reproduction](proof/before-probe.log) · [After refusal](proof/after-probe.log) · [Focused test](proof/focused.log) · [Load pairs](proof/load-pairs.log). Static lint has zero errors and the same 12 pre-existing warnings before and after ([before](lint-before.json), [after](lint-after.json)); none concerns the new test or loader checks.

The first full run exposed an existing fixture with two simultaneous violations: `CL_max=0.6` equaled `CD90/2`, but the assertion expected the later oracle-angle diagnostic. Set that fixture’s `CD90=0.8` so it reaches and verifies the intended oracle rejection. The production rule is unchanged. [Initial failure](initial-suite-failure.log) · [Corrected fixture: 15 checks](oracle-fixture.log).

Independent read-only mathematical/code review found no blocking issue. The isolated full `app/test.sh` passes [before: 137 sections](before-suite.log) and [after: 138 sections](after-suite.log), with zero engine errors. Golden flights pass without re-recording; all nine standard/transport/swirl state hashes match the baseline at 30/60/144 fps. [Suite verification](suite-verification.json) records results and log hashes; [input manifest](suite-inputs.json) identifies the frozen source snapshot. Only this task’s loader boundary and tests were overlaid for the comparison. The separate focused proof uses the then-current shared tree. After concurrent CR-01b changes reached `impact_snapshot.gd` and `flight_session.gd`, a final [64-check integration run](integration-focused.log) also passed on the shared tree ([hashes](integration-verification.json)).

Both full runs report intermittent ObjectDB exit warnings in existing scene/session tests (six before, eight after, with differing affected tests); the exact sections are retained in the suite report. The new integrity test has none. These warnings remain a separate lifecycle follow-up; this task does not claim a warning-free application.

## Limits

This closes a loader acceptance defect, not stall calibration. The sampled peak remains an approximation to a continuous maximum. The two extra peak evaluations happen during aircraft loading, with no per-tick work. Paired timing observations on this shared host are not a new DATA-2 performance acceptance. Empirical stall/aircraft validation remains open.

Suggested commit message:

```text
D1-R4: reject invalid solved stall envelopes before flight

Proof: 64 integrity checks, 15 envelope checks, 48 exact fleet load
pairs, 16 solver-fault refusals and three failing negative controls.
Full app/test.sh: 137 baseline / 138 final sections; unchanged goldens
and exact 30/60/144 fps hashes. Isolate the existing oracle fixture.
```
