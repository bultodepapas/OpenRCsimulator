# Learnings

**Status:** curated developer reference. Lessons from building and testing this repository; historical measurements belong to their linked reports.

Start here for mistakes worth avoiding. Commands and working rules live in [AGENTS](AGENTS.md), current work in the [plans](docs/README.md#tracks-plans-and-step-ids), and detailed experiments in the [research index](docs/research/README.md).

| When working on… | Read next |
| --- | --- |
| Physics, state, aircraft data or performance | [Physics lessons](docs/learnings/physics.md) |
| Aircraft geometry, references, scenery or visual checks | [Models and rendering lessons](docs/learnings/models-and-rendering.md) |
| Godot execution, radio, menus, preferences or exports | [Runtime and delivery lessons](docs/learnings/runtime-and-delivery.md) |

## Prove what the airplane actually does

- **Passing regressions do not establish realistic flight.** The rudder's sign and golden replay were correct while a short pulse drove extreme sideslip and persistent rotation. A test computed from the same borrowed coefficients cannot validate those coefficients. Use independent data and flown magnitude/recovery checks; label known-defect characterizations as such. [Rudder audit](docs/research/ugly-stik-rudder-audit.md), [validation contract, VAL-3](docs/research/validation/VAL-3/README.md).

- **Exercise the real session, including trim and controls.** Unit tests passed while the app's synchronous trace path omitted elevator trim. A longitudinal-only trim also let propeller torque roll an apparently hands-off airplane into a spiral. Check the actual app's flight against the solver, including lateral trim, engine state and applied commands. [Trim solver tests](app/tests/test_trim.gd), [app trace check](app/tests/check_trimmed_flight.py), [session-path example, E0a2b](docs/research/aero-consistency/E0a2b/README.md).

- **Inspect trajectories before turning expectations into assertions.** Early spin models produced plausible-looking test outcomes with runaway rates; ground fixtures later exposed maneuvers flying below the field. Record angular rates, recovery and minimum altitude, and state the scripted pilot's technique. Full elevator can correctly stall a model; weakening authority to make a bad pilot pass hides that behavior. [Flight-model audit](docs/research/flight-model-robustness-audit.md), [E1](docs/research/landing-gear-contact-e1.md), [P-51 flight trials](docs/research/p51-flight-realism.md).

- **An oracle only applies under its stated assumptions.** Comparing different aircraft at equal speed instead of equal lift coefficient changed the apparent mode discrepancy. A fixed-attitude takeoff integral also diverged once the aircraft pitched, then agreed when fed the recorded attitude. State normalization, shared inputs and omitted physics before interpreting a gap. [VAL-3](docs/research/validation/VAL-3/README.md), [E3b3](docs/research/ground-contact/E3b3/README.md).

## Make evidence capable of rejecting a defect

- **A successful process or existing file does not prove a completed run.** The old trim checker accepted one-row traces and non-finite endpoints; capture scripts could accept a stale PNG after timeout. Require the requested duration, continuous tick/time pairs, finite samples, fresh artifacts and successful engine logs before judging quality. [C7-R1](docs/research/trace-integrity/C7-R1/README.md), [VQ-01a](docs/research/visual-quality-implementation/VQ-01a/README.md).

- **A mutation needs a valid control and the intended failure.** Probes appeared to reject malformed input only because their baseline was already invalid. First show a finite, valid case succeeds, then inject a bounded defect and verify which assertion rejects it. Run mutations on disposable copies so deliberate defects cannot enter another contributor's run or commit. [Native positive controls](docs/research/propwash/E0b6p/native/README.md), [VAL-4](docs/research/validation/VAL-4/README.md).

- **Separate preservation from correction.** Capture a baseline before a refactor and compare complete state, auxiliaries and loads. Byte equality proves the old behavior was preserved, including its defects. For a deliberate physics change, explain changed trajectories before re-recording goldens; switching the new term off can isolate its effect. [Exact-refactor evidence, H12](docs/research/simulation-state/H12/README.md), [D11d](docs/research/aero-consistency/D11d/README.md).

- **Visual metrics need a clean subject and a real renderer.** A changed-pixel airplane mask included its shadow and panel text, producing a false readability failure. Broad averages also hid narrow seams, while headless MultiMesh reads returned dummy transforms. Validate masks and spatial bins with injected visual defects, then use rendered readbacks for GPU-owned state. [L11a](docs/research/visual-quality-implementation/L11a/README.md), [visual evidence guide](docs/learnings/models-and-rendering.md#rendering-and-visual-evidence).

## Respect the boundaries between systems

- **Keep float64 physics separate from rendering types.** A small-acceleration test lost the entire velocity increment in Godot's float32 `Vector3`, while the float64 state preserved it. Convert at the rendering boundary; seeded quaternion composition checks also caught an error missed by individual known-answer cases. [Math tests](app/tests/test_math3d.gd).

- **The body array is not the whole simulation.** A wake lag advanced outside RK stages can lower integration order, and restoring only the rigid body leaves engine mode, sampled state or clock inconsistent. Define continuous, sampled and discrete state before extending the model, and test complete rollback and continuation. [H8a](docs/research/simulation-state/H8a/README.md), [H8](docs/research/simulation-state/H8/README.md), [E0b5](docs/research/propwash/E0b5/README.md).

- **Integration errors often hide between two locally correct systems.** A model verifier existed without running in CI, generated reports could lag current runtime data, and visual coordinates could introduce a false force arm when copied into physics. Check the complete generation chain, shared datums and session wiring. [DATA-1](docs/research/aircraft-validation/DATA-1/README.md), [E0b2](docs/research/propwash/E0b2/README.md).

- **Source inspection proposes a behavior; the shipped path establishes it.** Real exports disproved the claim that JSON always needed an include filter. A scenery probe also reversed a paper recommendation for mesh merging. Read the pinned engine when needed, then reproduce the exact backend, import path and exported configuration before writing a rule. [SC-01](docs/research/scenery-implementation/SC-01/README.md), [runtime lessons](docs/learnings/runtime-and-delivery.md#clean-builds-and-desktop-evidence).

## Measure under conditions that support the claim

- **A component speedup is not a flight-budget result.** Native slipstream reduced local cost while whole ticks still exceeded budget. Measure complete evolving trajectories across aircraft/regimes, include adapter and decoding costs, and keep timing buckets exclusive. Distinguish batch-average percentiles from individual-tick latency. [Gate P](docs/research/simulation-state/Gate-P/README.md), [E0b6p attribution](docs/research/propwash/E0b6p/attribution/README.md).

- **Freeze the inputs to a comparison.** Concurrent aircraft regeneration changed flight fingerprints during a refactor; parallel suites raced on shared preferences; visual edits mixed two versions in one capture run. Use an isolated source/data snapshot and separate runtime settings for comparable evidence. [H13/H14](docs/research/simulation-state/H13/README.md), [VQ-01a](docs/research/visual-quality-implementation/VQ-01a/README.md).

- **Match acceptance to the observer.** Software-rendered captures establish pixels and repeatability, not target-GPU frame times or human attitude recognition. Export inspection establishes package structure, not native launch or signing trust. Keep pilot trials, hardware timing and native OS checks as distinct evidence. [L6c](docs/research/visual-quality-implementation/L6c/README.md), [DT-00-R2](docs/research/desktop-delivery-investigations/DT-00-R2/README.md).

## Keeping this useful

Add a lesson when an observed failure or surprising result changes how a future developer should work. State the cause, the practical consequence and an evidence link with the relevant step ID. Merge with an existing lesson when possible; keep specialized detail in the topic guides above.

Put step status and next actions in the owning plan, measurements and reproduction details in the evidence report, architectural choices in [DECISIONS](DECISIONS.md), and shipped changes in release notes. Routine passes, test counts, machine inventories and generic advice do not need a learning entry. If a later experiment corrects a lesson, update the recommendation and link the correction rather than leaving contradictory advice.

## 2026-10-07 · VAL-6a — reduce swing tests about a common axis

Subtract loaded and empty-rig compound inertia about the shared pivot before shifting the object to its CG; the two configuration CGs usually differ. Combine sensitivities of reused measurements before squaring uncertainty contributions. A stationary first derivative can hide second-order height uncertainty. Preserve the net pivot result: a rigid-mass axis shift does not resolve aerodynamic added-inertia transfer. [Equations, limits and verification](docs/research/validation/VAL-6a/README.md).

## 2026-10-07 · L9c — preserve field data while merging render surfaces

A render batch limit must not silently narrow the accepted field format. Validate containment, flat coverage and capacity before replacing any geometry; use a whole-field fallback for unsupported layouts. Derive overlapping surface colours from the same base grass to avoid multiplying brightness.

A half-pixel image difference includes expected camera motion. Surface-on/off pairs isolate the surface from the grass, but do not by themselves isolate aliasing. Keep motion measurements observational unless an appropriate control actually substantiates the claimed gate. [Implementation and evidence](docs/research/visual-quality-implementation/L9c/README.md).

## 2026-10-07 · E0b6p — duplicated work needs branch-specific evidence

Sharing thrust/torque halves the powered wake load path’s calls, but reverse cutoff already skips the duplicate and pays only the added argument/dispatch work. Preserve that control case when measuring an optimization. Count the continuous transport callback separately: stopped residual wash still evaluates its target four times per tick, so changing Dynamics alone does not remove that work. Exact trajectories establish numerical safety; mixed paired whole-tick savings are sufficient reason to leave a candidate outside production. [Experiment and decision](docs/research/propwash/E0b6p/stage-sharing/README.md).

## 2026-10-07 · VAL-5a — shared weighing errors do not average away

A calibration gain shared by every scale changes total mass but cancels from the CG ratio; a shared coordinate datum error contributes once, without shrinking with the number of supports. Propagate net readings through centered-arm sensitivities so moment/mass covariance is retained. Diagnose CG linearization from local load uncertainty: a large common gain alone cannot make CG uncertain. [Measurement model and verification](docs/research/validation/VAL-5a/README.md).

## 2026-10-07 · DATA-3 — fingerprint the bytes that were actually loaded

A rounded JSON serialization can hide a change to a parsed aerodynamic coefficient: the CL0 late-digit regression reproduces this collision. Hash the same byte buffer used for parsing, retain that identity across failed reloads, and never reread a mutable path when recording. Keep source-file identity separate from the derived-model checkpoint fingerprint; in-memory inputs have no original file bytes. Version the metadata and label legacy semantic-only checks explicitly. [Contract and verification](docs/research/aircraft-validation/DATA-3/README.md).

## 2026-10-07 · VAL-7a — keep measured and ideal propeller power distinct

Thrust and RPM cannot establish shaft power without torque or another independent shaft-power measurement. Static ideal-disc power is a model bound; figure of merit is distinct from propulsive efficiency. Calculate ratio uncertainty from original inputs: derived Ct and Cp share density and diameter errors. [Reduction equations and verification](docs/research/validation/VAL-7a/README.md).

## 2026-10-08 · E0b6p — snapshot isolation is not model freshness

A native snapshot can remain safely isolated yet become stale relative to its source dictionary. Rebuild explicitly after nested edits and invalidate old generations even when replacement preparation fails. Test refusal through the adapter: a stateless fallback can preserve nominal load equality while bypassing the lifecycle contract. [Ownership lesson](docs/learnings/physics.md#a-prepared-model-needs-an-explicit-ownership-boundary), [experiment](docs/research/propwash/E0b6p/prepared-model/README.md).

## 2026-10-08 · L9c-R1 — subtract expected image motion

To measure sampling error, isolate the changing cue with a zero-amplitude capture and subtract the motion of an independently supersampled reference. Check two reference resolutions: a low-resolution reference can alias more than the candidate. Define thin distant-surface masks in world units; a one-pixel erosion can erase the entire target. Preserve a nearby-detail control so removing the feature cannot pass as good filtering. [Method, limits and evidence](docs/research/visual-quality-implementation/L9c-R1/README.md).

## 2026-10-08 · DATA-2a — preserve the quantity a numerical search solves

Replacing a sampled lift maximum with a continuous optimizer can change a stall angle even when both searches are accurate. Bound and prune the original grid when exact behavior must survive: a curvature/chord bound avoids assuming a single peak, while an exhaustive oracle and deliberate bound mutations verify the implementation. Keep floating-point safeguards distinct from a formal interval proof. [Derivation, equivalence checks and timing limits](docs/research/aircraft-validation/DATA-2a/README.md).

## 2026-10-07 · E3c1a — stopping is not proof of runway landing

A soft touchdown followed by a stop can hide a runway overrun: rough ground supplied the stopping force in early approach trials. Check every wheel throughout rollout and require a stable idle hold inside the strip. Run the actual session crash detector at each committed boundary; calling only the integrator bypasses it and lets an initially penetrating aircraft advance. [Trajectories and rejection controls](docs/research/ground-contact/E3c1a/README.md).

## 2026-10-08 · G1b1 — verify the sampled command and the recorded query

Synchronous `sim.step()` does not sample changed session commands: an intended idle/full-power fixture kept flying at trim throttle until its inputs were explicitly updated. Assert recorded commands and RPM before accepting a maneuver's label. Trace v3 also pairs previous-state velocity with current RPM for its load columns; a same-row reconstruction evaluates a different operating point. Keep clamped reverse-flow J=0 separate from static-source support. [Regression and flight-query evidence](docs/research/propulsion/G1b1/README.md).

## 2026-10-08 · L10a — model calm and constrain actual geometry

A calm windsock still holds its throat and first three-eighths open on a basket; the remaining sleeve hangs. Preserve cloth arc length through the bend instead of shortening it by projecting a straight sleeve. Optional field cues should preserve legacy fields, and placement exclusions must match the terrain actually rendered: the 1.5 km flat radius belongs only to the 40 km hill mesh. Remove unrelated cues explicitly from synthetic geometry fixtures. [Contract and evidence](docs/research/visual-quality-implementation/L10a/README.md).
