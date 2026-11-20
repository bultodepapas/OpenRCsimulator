# Improvement plan for the second collision investigation

**Date:** 18 November 2026, America/Bogota. **Baseline:** `a7de9b35676d891bc2034cc344b910d9e1ef9c61`, reached through the first audit commit `1effa267c519526156e9aefbef63d344102bc989` without application changes.

This plan adds focused work to the [original improvement plan](improvement-plan.md). The [new findings](deep-dive-2026-11-18.md) supply the evidence and source locations. These are proposed implementation slices; this audit commit does not claim that any product defect has been fixed.

## Scheduling and ownership

Retain the original plan's urgent world-composition, dropped-contact, and source-off prop-strike work. Within this continuation, first make session boundaries coherent, then decide mixed-contact incident arbitration, then add a bounded quad obstacle aftermath and correct delayed helicopter release. The two publication records have a common design concern but belong to different family adapters; keep their changes reviewable and independently testable.

| Slice | Record | Suggested owner | Main deliverable | Exit evidence |
|---|---|---|---|---|
| R2-A | CR-AUD-17 | Simulation/session maintainer | A complete-or-refused public quad checkpoint boundary and cross-field restore validation | Real drop callback checkpoint, healthy/depleted/crashed controls, atomic refusal |
| R2-B | CR-AUD-19 | Fixed-wing session and flight-log maintainer | A completed crash publication boundary with an available final reason and damage/contact state | Real accepted collision, callback observation, written `.orfl` round trip |
| R2-C | CR-AUD-18 | Collision/ground-physics maintainer | Explicit, versioned arbitration policy for mixed terminal candidates | Matched accepted-stage counterexample plus ties, reversed order, dynamic-mass/lake cases |
| R2-D | CR-AUD-20 | Multirotor contact and activity maintainer | Obstacle-specific terminal response or an explicit colliding aftermath handoff | No full solid crossing, one terminal event, cut retained, secondary-contact continuation |
| R2-E | CR-AUD-16 | Helicopter wreck/presentation maintainer | Consistent current-pose rotor release kinematics | Covariance controls before caps, capped released velocity, delayed scene integration |

P2 is a scheduling recommendation, not a promise of equal effort. R2-C needs a product/physics policy decision before code can be judged against an exact expected outcome. R2-D needs an explicit presentation contract but does not require material-strength calibration before it can stop an intact quad from passing through a fixed wall. No effort estimate is presented as measured engineering time.

## R2-A: Publish and restore one coherent quad boundary

Define whether session checkpoints may be read while the enclosing `tick_once()` is completing. Two viable contracts are a fully assembled session envelope or an explicit temporary refusal with a documented completion signal. Preserve the kernel's independent contract allowing read-only access to its already committed state.

Restore should validate relations between terminal mode, crash record, cut latch, accepted tick, and any retained session metadata before mutation. `MOTOR_DEPLETED` must remain distinguishable from `MOTOR_CRASHED`; do not invent a crash for every exhausted pack. Use a prepared envelope or equivalent staging so a rejected restore leaves the current state unchanged.

The retained probe accepts either a refused early checkpoint or a coherent early envelope. Its two baseline failures must disappear without editing the expected behavior to accept contradictory state. Healthy restore must still resume, ordinary crash restore must still refuse resume, and the motor cut must remain latched. Add a graded obstacle crash and a depleted-but-not-crashed case, since the first fixture uses a strict ground crash.

Before merging, run the affected existing session, kernel publication, and multirotor log checks, including `test_mr_session.gd`, `test_simulation.gd`, and the relevant `test_mr_flight_log.gd` coverage. Select further tests from the actual change; a full-suite count cannot substitute for the callback/restore counterexample.

## R2-B: Commit crash context before observer notification

Treat crash reason, terminal contact, supported simultaneous facts, and scenery damage as an owner-level boundary. Publish a complete snapshot once it is ready. If the low-level pause signal must occur sooner for scheduling reasons, do not advertise it as a completed session incident; let the logger and incident consumers subscribe to a later coherent payload with the same accepted tick.

Two partial fixes need explicit caution. Assigning the reason earlier repairs the empty log detail but leaves incomplete contact/damage observations. Deferring only the logger's callback can hide that symptom while changing tick association or allowing a restart before the data is consumed. Neither closes the entire finding without lifecycle evidence.

Keep an ordinary pause control, then test ground, scenery, and lake terminal paths with the real writer/reader. Include auto-restart and a listener that immediately stops recording. Verify one complete crash context, the correct accepted tick, a nonempty matching reason, and no partial damage publication after rejected candidate ticks. Existing `test_flight_log.gd`, `test_aircraft_contact_events.gd`, and `test_scenery_damage_session.gd` provide relevant surrounding gates.

## R2-C: State what the first incident means

A soft ground force, a terminal predicate, an interpolated crossing witness, and an exact accepted-path event time are different quantities. The implementation must not compare them as interchangeable scalars without recording their evidence quality. Choose one documented policy:

1. **Earliest supported accepted-path incident.** Collect compatible terminal candidates, preserve surface/probe identity, compare available time bounds, and explicitly represent unresolved ordering.
2. **Declared tick-boundary precedence.** Keep a deterministic approximation, but expose its precedence and avoid describing its selected witness as a physically established earliest contact.

The audit favors preserving causal ordering where the accepted path supports it. Either implementation requires a deliberate answer to the reproduced case, rather than allowing whichever helper runs first to silently own the incident.

Keep the current production-force stage capture as a regression control. Add reversal of wall/ground ordering, a same-time tie, harmless ground scrape followed by a terminal wall, multiple hull points, sampled dynamic mass, lake-bank ownership, and refused ticks. Do not convert all soft ground touches into legacy terminal contacts. Ordinary survivable belly contact is an essential negative control.

Record whether the fixed policy changes incident source, contact pose, or only presentation wording. If accepted physics changes, run appropriate reference/native parity and affected flight traces, following repository gates. The current 960 Hz diagnostic is not a proposed product tick-rate change.

## R2-D: Continue collisions after terminal adjudication

Keep the one-shot gameplay transition and latched motor cut, while providing a separate rule for the body's continuing contact with solids. Viable designs include an accepted obstacle-normal response followed by ongoing bounded contact, or a declared handoff to a colliding aftermath body. Whichever design is chosen must own geometry identity, pose, linear/angular motion, terrain contact, and cleanup.

Do not call the terrain-only settlement helper for an airborne wall. Do not merely set the speed to zero at an arbitrary embedded pose. Retain a contact witness and normal, separate or bound penetration, and specify how tangential velocity and angular motion are handled. Restitution/friction values should remain declared gameplay parameters until validated.

The baseline 3 m/s bounce and clear controls must remain intact. The 9 m/s case should retain one crash notification and the cut latch while satisfying the new solid-containment contract. Test a second nearby obstacle after the first terminal strike, then ground contact, oblique incidence, roofs, thin bars, and reset/replay. Verify that the actual activity still poses the intended body and that reset removes any replacement aftermath resources. Use `test_mr_graded_crashes.gd` and the affected multirotor session/activity checks around the new regression.

A headless state test can establish bounded geometry and motion. A rendered scene test must establish that the player sees the corrected aftermath; no GPU timing or scene validation is implied by the current evidence.

## R2-E: Transform every rotor operand consistently

Store the main/tail hub and axis in a stable local frame and transform them with the same current assembly pose used for the blade center. Document whether blade phase and shaft speed are frozen at impact. This fix should not quietly introduce a second rotor integrator in the visual wreck.

Keep the independent geometric oracle: translation invariance and rotational covariance of spin-relative velocity before caps. Separately check the shaft/group cap and final point-speed cap. Cover main and tail rotors, multiple delayed groups, unchanged pose, zero spin, inherited core motion, and reset/reuse. Preserve the passing existing `test_heli_crash_visual.gd` checks and add a rendered core-motion scenario after the algebraic counterexample passes.

Do not use this fix to claim corrected mass conservation or continuous damaged-flight physics. The original audit's mass/COM and scheduled-part ownership findings remain separate work.

## Evidence and CI discipline

Promote focused regressions into the owning test locations when implementing the corresponding fix. The retained research probes deliberately fail on the audited baseline and should not be inserted unchanged as a permanently red required CI job. Keep their raw failure records, create corrected evidence against a new source commit, and connect each change to its finding ID.

For each correction, retain the source/engine identity, checked diagnostics, actual assertions, controls, and declared scope. Failing expected behavior and failing to parse are separate categories. A passing simulation process alone is not a successful probe unless its completion marker and required checks are present. The supplied continuation launcher preserves nonzero exits rather than treating known failures as passes.

Use performance measurements only after a concrete algorithm change introduces a concrete cost question. Candidate collection may increase per-tick work; repeated aftermath contacts may increase queries; publication staging may allocate. Measure those paths against the original budget on supported hardware, with warm and first-impact cases. Do not infer runtime costs from this headless audit's wall-clock execution durations.

## Remaining research queue

The unpromoted leads remain separate: slow soft-box entry/inside overlap policy; rotating-point excursions between accepted endpoints; stock-geometry high-angular-rate and high-speed sweeps; actual terminal-aftermath scene behavior; and observer contracts for other vehicle families. Begin each with a valid accepted trajectory or a precise public API contract, then add independent controls. Do not add a defect count based solely on an analytic construction or an already documented approximation.

The original full-fleet scenario matrix, physical-strength qualification, fuel/battery ignition separation, terrain/friction validation, and target-hardware gates still apply. Completing these five slices does not complete progressive fracture or certify 300 km/h crash behavior.
