# Learnings

**Status:** curated developer reference. Lessons from building and testing this repository; historical measurements belong to their linked reports.

Start here for mistakes worth avoiding. Commands live in [TOOLS](TOOLS.md) and working rules in [AGENTS](../AGENTS.md), current work in the [plans](README.md#tracks-plans-and-step-ids), and detailed experiments in the [research index](research/README.md).

| When working on… | Read next |
| --- | --- |
| Physics, state, aircraft data or performance | [Physics lessons](learnings/physics.md) |
| Aircraft geometry, references, scenery or visual checks | [Models and rendering lessons](learnings/models-and-rendering.md) |
| Godot execution, radio, menus, preferences or exports | [Runtime and delivery lessons](learnings/runtime-and-delivery.md) |

## Prove what the airplane actually does

- **Passing regressions do not establish realistic flight.** The rudder's sign and golden replay were correct while a short pulse drove extreme sideslip and persistent rotation. A test computed from the same borrowed coefficients cannot validate those coefficients. Use independent data and flown magnitude/recovery checks; label known-defect characterizations as such. [Rudder audit](research/ugly-stik-rudder-audit.md), [validation contract, VAL-3](research/validation/VAL-3/README.md).

- **Exercise the real session, including trim and controls.** Unit tests passed while the app's synchronous trace path omitted elevator trim. A longitudinal-only trim also let propeller torque roll an apparently hands-off airplane into a spiral. Check the actual app's flight against the solver, including lateral trim, engine state and applied commands. [Trim solver tests](../app/tests/test_trim.gd), [app trace check](../app/tests/check_trimmed_flight.py), [session-path example, E0a2b](research/aero-consistency/E0a2b/README.md).

- **Inspect trajectories before turning expectations into assertions.** Early spin models produced plausible-looking test outcomes with runaway rates; ground fixtures later exposed maneuvers flying below the field. Record angular rates, recovery and minimum altitude, and state the scripted pilot's technique. Full elevator can correctly stall a model; weakening authority to make a bad pilot pass hides that behavior. [Flight-model audit](research/flight-model-robustness-audit.md), [E1](research/landing-gear-contact-e1.md), [P-51 flight trials](research/p51-flight-realism.md).

- **An oracle only applies under its stated assumptions.** Comparing different aircraft at equal speed instead of equal lift coefficient changed the apparent mode discrepancy. A fixed-attitude takeoff integral also diverged once the aircraft pitched, then agreed when fed the recorded attitude. State normalization, shared inputs and omitted physics before interpreting a gap. Full-roll video timing also measures a cycle average, not instantaneous body `p` or a decay pole; match the quantity before comparing ([VAL-8b](research/validation/VAL-8b/README.md)). [VAL-3](research/validation/VAL-3/README.md), [E3b3](research/ground-contact/E3b3/README.md).

## Make evidence capable of rejecting a defect

- **A successful process or existing file does not prove a completed run.** The old trim checker accepted one-row traces and non-finite endpoints; capture scripts could accept a stale PNG after timeout. Require the requested duration, continuous tick/time pairs, finite samples, fresh artifacts and successful engine logs before judging quality. A readable ZIP can still contain a truncated executable after temporary-disk exhaustion; inspect archive members and budget output plus temporary storage ([PT1h](research/release-readiness/PT1h/README.md)). [C7-R1](research/trace-integrity/C7-R1/README.md), [VQ-01a](research/visual-quality-implementation/VQ-01a/README.md).

- **A mutation needs a valid control and the intended failure.** Probes appeared to reject malformed input only because their baseline was already invalid. First show a finite, valid case succeeds, then inject a bounded defect and verify which assertion rejects it. An extreme literal may fail an earlier guard: construct finite normal inputs that overflow only the target expression, and remove that guard in a disposable copy to prove the assertion reaches it ([EL2a-P1](research/propulsion/EL2a-P1/README.md#verification-record)). Run mutations on disposable copies so deliberate defects cannot enter another contributor's run or commit. [Native positive controls](research/propwash/E0b6p/native/README.md), [VAL-4](research/validation/VAL-4/README.md).

- **Separate preservation from correction.** Capture a baseline before a refactor and compare complete state, auxiliaries and loads. Byte equality proves the old behavior was preserved, including its defects. For a deliberate physics change, explain changed trajectories before re-recording goldens; switching the new term off can isolate its effect. [Exact-refactor evidence, H12](research/simulation-state/H12/README.md), [D11d](research/aero-consistency/D11d/README.md).

- **Visual metrics need a clean subject and a real renderer.** A changed-pixel airplane mask included its shadow and panel text, producing a false readability failure. Broad averages also hid narrow seams, while headless MultiMesh reads returned dummy transforms. Validate masks and spatial bins with injected visual defects, then use rendered readbacks for GPU-owned state. [L11a](research/visual-quality-implementation/L11a/README.md), [visual evidence guide](learnings/models-and-rendering.md#rendering-and-visual-evidence).

## Respect the boundaries between systems

- **Observation history and operational permission can need different lifetimes.** A raw throttle event remained useful to the latency marker after calibration, but could not justify arming under the new mapping. Keep connection-wide diagnostics while resetting profile-specific low-throttle evidence; check both the fresh event and current polled position. [Rearming repair, D6b-R2](research/radio-input/D6b-R2/README.md).

- **Keep float64 physics separate from rendering types.** A small-acceleration test lost the entire velocity increment in Godot's float32 `Vector3`, while the float64 state preserved it. Convert at the rendering boundary; seeded quaternion composition checks also caught an error missed by individual known-answer cases. [Math tests](../app/tests/test_math3d.gd).

- **The body array is not the whole simulation.** A wake lag advanced outside RK stages can lower integration order, and restoring only the rigid body leaves engine mode, sampled state or clock inconsistent. Define continuous, sampled and discrete state before extending the model, and test complete rollback and continuation. [H8a](research/simulation-state/H8a/README.md), [H8](research/simulation-state/H8/README.md), [E0b5](research/propwash/E0b5/README.md).

- **Local event time and the absolute clock have different precision.** Rejecting a positive remainder because it cannot advance the rounded clock can fail a valid event-composed tick. Keep the local root bound distinct from timestamp rounding, and test near-endpoint events at nonzero clocks. [EL2a-P2](research/propulsion/EL2a-P2/README.md), [numerical details](learnings/physics.md#every-coupled-continuous-state-needs-the-same-integration-stages).

- **Use one air-relative flow and keep ground velocity intact.** A new wind path must also reach shaft inflow, wake transport, downwash, reset equilibrium and telemetry; changing only the main aero load leaves locally valid consumers inconsistent. Uniform-wind Galilean tests expose missed consumers without tuning aircraft coefficients. Trace state-time and k1 load-time samples separately, and fingerprint forcing in replay. [Wind delivery and proofs](research/wind-implementation/README.md).

- **Integration errors often hide between two locally correct systems.** A model verifier existed without running in CI, generated reports could lag current runtime data, and visual coordinates could introduce a false force arm when copied into physics. Check the complete generation chain, shared datums and session wiring. Audit executable source and tracked tests when resuming a report: D1-R5 retained a patch and passing logs while the app still used the old loader and the referenced regression source was absent. [DATA-1](research/aircraft-validation/DATA-1/README.md), [E0b2](research/propwash/E0b2/README.md), [D1-R5 integration](research/aircraft-validation/D1-R5/integration/README.md).

- **Source inspection proposes a behavior; the shipped path establishes it.** Real exports disproved the claim that JSON always needed an include filter. A scenery probe also reversed a paper recommendation for mesh merging. Read the pinned engine when needed, then reproduce the exact backend, import path and exported configuration before writing a rule. [SC-01](research/scenery-implementation/SC-01/README.md), [runtime lessons](learnings/runtime-and-delivery.md#clean-builds-and-desktop-evidence).

## Measure under conditions that support the claim

- **A component speedup is not a flight-budget result.** Native slipstream reduced local cost while whole ticks still exceeded budget. Measure complete evolving trajectories across aircraft/regimes, include adapter and decoding costs, and keep timing buckets exclusive. Distinguish batch-average percentiles from individual-tick latency. [Gate P](research/simulation-state/Gate-P/README.md), [E0b6p attribution](research/propwash/E0b6p/attribution/README.md).

- **Freeze the inputs to a comparison.** Concurrent aircraft regeneration changed flight fingerprints during a refactor; parallel suites raced on shared preferences; visual edits mixed two versions in one capture run. Use an isolated source/data snapshot and separate runtime settings for comparable evidence. [H13/H14](research/simulation-state/H13/README.md), [VQ-01a](research/visual-quality-implementation/VQ-01a/README.md).

- **Match acceptance to the observer.** Software-rendered captures establish pixels and repeatability, not target-GPU frame times or human attitude recognition. Export inspection establishes package structure, not native launch or signing trust. Keep pilot trials, hardware timing and native OS checks as distinct evidence. [L6c](research/visual-quality-implementation/L6c/README.md), [DT-00-R2](research/desktop-delivery-investigations/DT-00-R2/README.md).

## Keeping this useful

Add a lesson when an observed failure or surprising result changes how a future developer should work. State the cause, the practical consequence and an evidence link with the relevant step ID. Merge with an existing lesson when possible; keep specialized detail in the topic guides above.

Put step status and next actions in the owning plan, measurements and reproduction details in the evidence report, architectural choices in [DECISIONS](DECISIONS.md), and shipped changes in release notes. Routine passes, test counts, machine inventories and generic advice do not need a learning entry. If a later experiment corrects a lesson, update the recommendation and link the correction rather than leaving contradictory advice.

## 2026-10-20 · EX-14c — a frozen fixture that subclasses a runtime script pins its signatures

Adding an optional parameter to `Slipstream.loads` broke `test_segmented_slipstream_parity.gd` with "Could not resolve external class member", because its frozen reference fixture `extends` the script and overrides `loads`, and GDScript requires an override to match the parent signature. Keep a public function's signature when a fixture subclasses it, and add a new function (`stage_loads`) for the new argument. Search `tests/fixtures/` for `extends "res://…"` before changing a runtime signature. [Evidence](research/extra-300-realism/EX-14/README.md)

## 2026-10-19 · D10-R5 — differentiate every static derivative in both load regimes, not only in the production blend

The Stik's oracle carried the dihedral effect in `Clb`, but the local strips have no spanwise flow, so its roll due to sideslip dropped 85 % between α 8° and 12°. No flight test flagged it, because the blend weight changes with α and the jump looked like stall behaviour. The fuselage yaw (P51-25) and the section pitching moment (D11j) were the same kind of gap.

- When a term enters one regime, give the other regime its counterpart, with a loader rule that ties the two together. The fuselage side force was the next instance: without it in the local law the Extra 300S could not knife-edge (−35 m/s with full rudder), although its oracle `CYb` was sufficient (D10-R3, [EX-14](research/extra-300-realism/EX-14/README.md)).
- Before tuning a maneuver, differentiate the oracle, the local law and the blend at fixed states across α. [`roll_regimes.gd`](../research/flight-dynamics/stik-lateral-directional/roll_regimes.gd) does this for Clβ and Cnβ. [Evidence](research/flight-dynamics/stik-roll-sideslip-2026-10-19/README.md)

## 2026-10-19 · GP-06 — check contacts against the built model, and never require a fallback in shipped data

The Stik's physics wheels sat 5 mm below its drawn wheels: the source read a model-origin height as thrust-line-relative, and the unit test re-derived the contact with the same misreading, so both agreed. The glow Stiks had no wheel profile for days, because a fleet test required at least one shipped aircraft on the legacy route and they satisfied it; their wheels were drawn sunk, without spin or steering.

- Compare physics geometry with the built visual model through its manifest datum (`test_gear_visual_contacts.gd`), not with another derivation from the same table.
- Cover fallback and legacy routes with isolated fixtures; require shipped data to take the full route. Enabling a full route on new data can expose latent gaps (here, glow traces without a wheel tail). [GP-06](research/ground-physics/GP-06/README.md)

## 2026-10-19 · FT-04 — on a shared tree, fly the baseline and the candidate against one frozen snapshot

While the card v4 tests were written, other tracks committed three times. A v3 baseline flown an hour earlier already differed from the current tree in three Stik takeoff and landing values, from ground-contact data, not from the card. Comparing against it would have charged FT-04 with changes it did not make.

- Copy `app/` once, then fly both versions against that copy (`run.py --app`), each from its own frozen copy of the runner. Record the commit, the dirty paths and the file hashes.
- Append new tests after the old ones, so the old cases stay comparable and "nothing else moved" can be proved at zero tolerance.

[FT-04](research/flight-test/FT-04/README.md)

## 2026-10-19 · D8b-R2d — a quasi-steady strip law trades post-stall lift against autorotation; compare damping like for like

Strip tables solved to the measured Ultra Stick 120 static lift and stall-onset roll damping (with or without spanwise progression) stopped the Stik spinning, although that airframe spins with the same inputs. In strip theory autorotation needs a negative local lift slope, and holding the measured post-stall lift removes it.

- Judge a post-stall law on static lift, damping and a held-out spin together. Matching one curve can break the maneuver.
- Forced-oscillation "Clp" is Clp + Clβ̇ sin α (NASA convention), so compare it with a model's dMx/dp only where sin α is small.
- Rate- and history-dependent separation is the missing physics.

Evidence: [D8b-R2d analog](research/flight-robustness/D8b-R2/analog/README.md), [D10-R4](research/flight-dynamics/spin-post-stall-2026-10-19/README.md).

## 2026-10-18 · D10-R2 — re-trim before judging a coefficient, and never judge an oscillation by one sample

Writing a new Cnβ into a session after its trim was solved left Cnβ·β_trim unbalanced: the airplane rolled to 32° in 40 s with no input and looked spirally unstable, while the re-trimmed airplane was stable. The flight-log candidate mode has the same property (it keeps the baseline trim), and `compare` refuses tapes whose trimmed commands differ, so for a change that moves the trim record the same stick tape on each data set and compare the exports. Separately, a recovery check that read r at one instant passed or failed with the Dutch roll's phase (the mirrored doublet passed with the same physics); judge oscillatory recovery by modes or by an envelope over at least one period. [Evidence](research/flight-dynamics/stik-lateral-directional-2026-10-18/README.md#6-decisions-and-adoption-d10-r2-2026-10-18)

## 2026-10-18 · AUD-12 — a "recovering" limiter can be a clipper, and Movie Maker runs on the Dummy driver

Godot 4.7.2's `AudioEffectLimiter` recovers instantly because it is a stateless per-sample clipper: its knee sits at −`soft_clip` dBFS whatever the ceiling, and a −1.9 dBFS tone comes out at the −1 dBFS ceiling with −26 dB distortion. Choosing it to avoid `AudioEffectHardLimiter`'s stuck release (AUD-07d) traded a level offset for distortion near full scale; a transfer sweep, not a recovery test, shows that. `--write-movie` reports `AudioServer.get_driver_name() == "Dummy"` while still mixing, so code that silences itself on Dummy to protect headless tests also silences every Movie Maker capture; gate on `Engine.get_write_movie_path().is_empty()` as well. [Probes](../research/audio/master-limiter-2026-10-18/README.md)

## 2026-10-17 · AUD-11b — Godot audio filters do not mean their property names; measure the mixer

In Godot 4.7.2 an `AudioEffectHighShelfFilter` applies its `gain` squared (gain 0.5 → −12 dB), and `AudioStreamPlayer3D` routes its distance filter through the same shelf, so `attenuation_filter_db = −12` measured −24 dB at 200 m and −18 dB already at 30 m. `FILTER_6DB` is one 12 dB/octave biquad; the default `FILTER_12DB` cascades two. The default resonance 0.5 is not Butterworth (use 0.7071). Enabling a bus effect mid-stream clicks (15–27×), and so does stepping a cutoff; a moving cutoff above about 15 kHz adds small artifacts. Keep filters enabled, glide their cutoffs, and verify a filter's response with noise through the real mixer before using its numbers. [Probes](../research/audio/air-absorption-2026-10-17/README.md)

## 2026-10-16 · FT-01 — a scripted pilot must fly like a pilot before its numbers describe the airplane

Building a generic flight-test card, most first failures were the pilot's, not the airplanes'. Coordinating to zero sideslip made the P-51's left and right turns differ by 17 % because the slipstream adds a side force at β = 0; centring the ball, as a pilot does, made them equal. A fixed sideslip gain diverged at high speed; integrators bounded inside a scheduled gain stopped short of the stick a hold needed; an attitude-holding inverted pilot stalled a cambered wing. Schedule gains with dynamic pressure, keep integrators in stick units, bound α near limits, judge saturation on the pilot's own commands (recorded command columns include trims) and report every test as valid only when its pilot met the card. Then a remaining failure is a finding: the card exposed that no propeller aircraft can knife-edge because the local model has no fuselage side force beyond the sideslip blend. [FT-01](research/flight-test/FT-01/README.md)

## 2026-10-15 · SF-05 — substep with the full loads and the proof becomes bitwise

Holding slow loads while substepping a stiff contact needs a splitting argument and a tolerance. Integrating full RK4 pieces of dt/n with the tick's inputs is exactly what a finer tick does, so the scheme is checked by byte equality against the 480 Hz run and refinement is measured against 960 Hz with no fitted budget. The cost is paid only while a stiff gear is within reach of the ground. [SF-05 evidence](research/simulation-foundation/SF-05/README.md).

## 2026-10-15 · SF-06 — per-axis passivity at the CG is a pure-translation property

Checking that each gear force opposes the CG velocity axis by axis failed for the P-51 and the Ventage Jet while the laws were right: under body rates a wheel moves at v + ω × r, so a force that opposes the wheel's own velocity can do positive work along a CG axis. Friction's "never adds energy" holds at the contact point; at the CG, test it in pure translation, or sum the power over the contact velocities. [SF-06 evidence](research/simulation-foundation/SF-06/README.md).

## 2026-10-15 · SF-04 — a stop's known answer needs the locator's continuation, not a kinked derivative

A synthetic "x falls at a constant rate and rests at zero" model located its stop at 0.6 of the tick instead of the analytic 0.5, because a derivative that switches to zero for x ≤ 0 kinks the RK4 trial map that the bracket solves. The locator treats negative trial values as a continuation, so a known-answer model must keep its derivative smooth across zero and rest only at exactly zero; then the secant lands within 1e-12 of the analytic crossing. [SF-04 evidence](research/simulation-foundation/SF-04/README.md).

## 2026-10-15 · SF-03 — a kernel transaction does not cover observers that run after its commit

Moving the truck onto the shared kernel left telemetry, damage, events and recording in the session, after `sim.step()` has committed. Before, a rejected observation left the state untouched; after, the kernel had already advanced. Keep the old transaction by taking a kernel checkpoint before the step and restoring it when an observer rejects the tick, until the observers join the kernel's own event protocol. [SF-03 evidence](research/simulation-foundation/SF-03/README.md).

## 2026-10-15 · SF-02 — a vehicle's coupled-state layout belongs to the start, not the vehicle

Declaring the helicopter's continuous block as six rotor states refused every ground start: a pad start appends four elastic skid-friction pairs, so the same vehicle integrates 14 coupled values. A layout declaration must be made where the start is resolved and held fixed for the run; the kernel then enforces it at reset and restore. [SF-01/02 evidence](research/simulation-foundation/SF-01/README.md).
## 2026-10-15 · P51-V14 — when parts start to touch, extend the clearance pairs before trusting a pass

Nesting the P-51's new lower rudder inside a concave cut in the fuselage passed the existing clearance check 28/28, because rudder against fuselage had never been a checked pair. Once added, it found 0.1 mm where the design gave 2.5 mm: straight facets between the fixed part's vertices cut inside the moving nose where an elliptic section's radius changes steeply near its ends. List every pair a geometry change makes adjacent before reading the result; hold a clearance cut at the end radius beyond the moving part; and locate the closest points with a vertex-to-triangle probe rather than trusting the designed gap. [P51-V14](research/p51-realism/P51-V14/README.md)

## 2026-10-15 · P51-11 — a new aircraft feature fails in the checks you did not write

Enabling P-51 flaps passed every P-51 and flap test, yet broke three things outside them: `Maneuvers.fly` silently recorded zero rows for any flap or gear session (the trace drops rows whose input count disagrees with its metadata), the migrator's `--check-known` rejected the new capability, and the module registry did not know the new gear value. Before reporting a capability change, run every generator `--check` and Python test in `app/test.sh` that reads aircraft data, and fly one scripted maneuver through the session; a test that only reads the data file cannot see consumers that are keyed by capability. Any edit to a procedural builder also changes its model-manifest hash, so `Builder.build` returns `{}` until `build_models.py` regenerates it; guard the build result in tests ([P51-V13](research/p51-realism/P51-V13/README.md)). [P51-11a](research/p51-realism/P51-11a/README.md), [P51-11b](research/p51-realism/P51-11b/README.md).

## 2026-10-15 · P51-26 — distrust a perfect match, and point-sample nothing singular

A first propeller-sidewash candidate hit the P-51D's measured 0.55 °/° almost exactly; re-deriving Ribner's relation in the model's own terms showed it counted the axial-wash deflection twice and diverged at static thrust. The correct form gives 0.72. Before accepting a result that lands on the target, rewrite the source equation in the code's variables and check the limits. In the same step, a free-vortex swirl sampled at one centroid per tail piece made a stability derivative wrong by up to 2× in either direction as speed changed. Integrate any profile with a core or edge kink across its kinks (split there, then low-order Gauss) and compare with a dense reference before trusting its derivatives. [Evidence](research/p51-realism/P51-26/README.md).

## 2026-10-15 · P51-25 — calibrate whole-aircraft ratios about the CG, and test the maneuver, not an integral

A steady-sideslip calibration solved with the stored coefficients missed its target by 19 %. They are about the aerodynamic reference point; the runtime adds r × F at the CG, and a 64 mm / 97 mm offset turns CYβ and CYδr into significant Cnβ, Clβ and Cldr. Solve any whole-airplane balance (trim, sideslip, turn) about the CG with the runtime's own transfer, then confirm on the runtime. In the same step, a loop check that integrated pitch rate passed a rolling departure that never went past 46° of pitch. A maneuver check should assert the maneuver's geometry (here: passing the vertical with small sideslip) and be shown to pass a genuine example. [Evidence](research/p51-realism/P51-25/README.md).

## 2026-10-15 · P51-24 — a constant inside a metrology script is not a measurement

The P-51's "measured" tail group carried a hard-coded rudder hinge, so its physics rudder was 43 % short of the NACA production area. It looked plausible because the measured outline around it was right. Steady-sideslip data exposed it: the model needed about four times the rudder per degree of sideslip that the P-51D flight tests recorded. Cross-check every control-surface split against published surface areas, chords and spans before tuning stability. Keep the visual and physical definitions explicit when they cannot change together. In this case the generator solved an aerodynamic hinge from the silhouette and the NACA area, which then reproduced the published chord and span independently, while the visual rework stays a separate reviewed step. [P51-24](research/p51-realism/P51-24/README.md)

## 2026-10-15 · P51-22 — check that a scripted pilot flew the maneuver before blaming the law (corrected 2026-10-16)

R02 rewrote tail downwash as a wake velocity divided by the local tail speed. Inside the propeller jet it divides by the washed speed, and the P-51's lift-off and loop gates failed after it. Two things were learned. First, do not patch the consumer: replacing the washed denominator with the free-stream speed restored the gates but created a direction-dependent zero-speed force jump. Second, and found later: the gates were measuring the test pilots. The proportional rotation loop settled 4.7° short of its 8° target against the stronger full-power nose-down moment, using a quarter of the stick. The open-loop loop step asked for more than CLmax once a trim correction stopped clipping it. Before attributing a maneuver failure to physics, log whether the pilot reached its commanded attitude or α, and whether a control saturated. A proportional pilot measures its own steady-state error. The suspected missing source, the wing in the jet, was then built self-consistently: it adds blown lift but almost no circulation, so it would not have restored the downwash. [P51-22 resolution](research/p51-realism/P51-22/README.md#resolution--2026-10-16)

## 2026-10-14 · P51-19/20 — a matching trim gradient can hide a zero-lift moment error

The P-51's trim gradient and neutral point matched the full-size data, yet it needed 6.5° of up elevator to cruise. The full-size XP-51 needed about 1° at the same CL and CG. The handbook tail incidence and downwash left ΔCm0 ≈ +0.06 unaccounted for, which is easy to dismiss as RC "rigging". When the geometry is scaled from a documented full-size airplane, compare absolute elevator-for-trim at equal CL and CG against the flight-test trim curves before tuning handling. NACA flying-qualities reports publish them. Fit glide data, and keep cruise as an unfitted check: power effects differ between installations. Shared-module constants fitted to another planform are a similar trap. The Stik's ground-effect tail fit gives 0.27 of the free-air downwash at h/b 0.12, while a VLM of the P-51, whose tail sits 0.26 m above its low wing, gives 0.62. [P51-19](research/p51-realism/P51-19/README.md) · [P51-20](research/p51-realism/P51-20/README.md)

## 2026-10-19 · NITRO-06 — a throttle sets an air flow, not a charge fraction

Mapping the stick to a fixed fraction of the cylinder charge makes a closed throttle deliver power in proportion to the engine speed, so an idling engine that is unloaded by the airstream makes ten times its ground-idle power and the airplane cannot descend. A carburettor throttle is an orifice: at a small opening it chokes, the mass flow is fixed by the opening and the charge per cycle falls as 1/rpm (Heywood §7.6.2). Model throttles as flow restrictions in series with the engine's breathing, anchor the idle to the static idle speed and the wide-open end to the breathing tables, and test every part-throttle law with the engine unloaded (a glide or a dive), not only on the ground. Measure the complaint first: a hands-off throttle step from the trimmed start, with the energy balance beside it, separates a propulsion law error from the fixed-trim physics that every airplane shows. [NITRO-06](research/glow-engines/NITRO-06/README.md) · [D6e-R3](research/flight-dynamics/power-climb-2026-10-19/README.md)

## 2026-10-13 · D6e-R1 — a borrowed `Cma` carries the donor's static margin, not the target's

Static margin is neutral point minus CG, and the neutral point comes from the target's own wing, tail and downwash. Applying the Ultra Stick's `Cma` about the Ugly Stik's plan CG gave 18.9 % margin where its planform gives about 4–8 %, so the model holds trim α too stiffly and turns every speed gain into a pull-up. Derive pitch stiffness from the target geometry at the target CG, or move the coefficient reference so the neutral point is geometric; then regenerate every value defined about that reference (fin-arm, rate and local-tail terms). Compare propeller tables at the same engine power, not the same rpm: the 12×6 table looked 1.4–1.8× weaker at 11149 rpm, but the repository's power balance spins it to about 12650 rpm and the climb is unchanged. [Root-cause review](research/flight-dynamics/climb-trim/README.md#root-cause-review-2026-10-13-d6e-r1)

## 2026-10-14 · NITRO-05 — onboard fluids feel the specific force, not the attitude

The first fuel-feed tests expected a nose-up attitude to lean the engine and a nose-down one to richen it. Gravity accelerates the fuel and the airframe alike. The fuel feels only `−F_non-gravitational/m`: lift, thrust, drag and ground loads. A level airplane accelerating at full throttle therefore leans exactly like a steady up-line, and a dive richens only while drag slows it. Model any onboard fluid, accelerometer or pilot cue from that stage-local specific force. Test it from steady or explicitly accelerating states, never from attitude alone. [NITRO-05](plans/RC_NITRO_ENGINE_REALISM_PLAN.md#milestones-and-proof-register) · `app/tests/test_glow_fuel_feed.gd`

## 2026-10-13 · CR-09f — a SceneTree test that hits a script error hangs instead of failing

When a `--script` SceneTree test raises a runtime script error (indexing `[0]` of an empty list, `.field` on `{}`), Godot prints the error and never reaches `quit()`; the runner only sees its timeout. Two CR-09f mutations looked like hangs for this reason. Fetch optional sections through helpers that return `{}` and read keys with `.get(key, default)`, so a missing part fails its checks and the summary line still prints. [CR-09e/f evidence](research/crash-damage-investigations/CR-09e/README.md)

## 2026-10-13 · US-V10 — bend presentation meshes with relative per-axis blend shapes

The Compatibility renderer in 4.7.2 applies blend shapes. With `BLEND_SHAPE_MODE_RELATIVE` and three unit shapes per deforming part (X, Y, Z offsets weighted by a shape function), a physics offset in any direction becomes three blend weights: no per-frame vertex rebuild and no attitude assumptions. Two traps showed up. Boxes from `_bar` have vertices only at their ends, so a "bent" leg stays straight until it is segmented. And a test that computes its expected value with the function under test passed a linear-shape mutation, so check against an independent analytic value (5/16 of the tip at cantilever mid-span). [US-V10 evidence](research/ugly-stik-finish-v6.md#us-v10--landing-gear-flex)

## 2026-10-13 · US-V09c — Geometry3D intersections miss millimetre triangles expressed in metres

`Geometry3D.segment_intersects_triangle` and `ray_intersects_triangle` treat a determinant below their 1e-5 epsilon as parallel. A mesh built in metres with millimetre-sized triangles therefore returns no hit at all, and an interference check passes while the throttle pushrod runs straight through the exhaust casting. Scale points and triangles to millimetres, as `visual_checks.gd` already does. Keep a positive-control segment that must hit, and mutate the installation once to prove the probe fails. [US-V09c evidence](research/ugly-stik-finish-v6.md#us-v09c--throttle-linkage)

## 2026-10-13 · US-V09b — missing tangents and 8-bit slopes break subtle normal maps without errors

Without `SurfaceTool.generate_tangents()`, Godot 4.7 fills an arbitrary orthonormal tangent frame. The normal map then renders in the wrong direction, and both "has tangents" and orthogonality checks still pass. Compare each triangle's UV-derived dP/du with the stored tangent instead. RGB8 also quantises tilt in steps of about 0.45°, too coarse for sub-2° film sag. Store the slope ×8 and set `normal_scale = 1/8`; the normal-map depth is a mix, so this is accurate at small angles. [US-V09b evidence](research/ugly-stik-finish-v6.md#us-v09b--film-over-structure)

## 2026-10-13 · CAM-08 — spring the camera's offset, not its world position

A critically damped spring that follows a moving point trails it by 2v/ω in steady motion: about 7 m at 20 m/s with a 0.25 s half-life, so a chase camera sprung in world space slides back to its lag cap whenever the airplane flies straight. Spring the offset from the target instead, in the target's frame or as a world-axis offset, and smooth only changes of heading, height or zoom. Test steady straight flight at several frame rates, not only a step response. Also, compare render results (`Vector3`, 32-bit) to about 1e-6. [CAM evidence](research/camera-views/CAM-01-10/README.md)

## 2026-10-13 · CAM-04 — Help has no spare row at 720p; key caps set the column width

Help fit 598 of 600 px at 1280×720 before the camera keys. One extra row overflows, and a single wide key name ("Retroceso" in Spanish) widens the cap column so other rows wrap. Fold new keys into existing rows, prefer short key names, and run `test_ui_help.gd` in both languages before adding a shortcut. [CAM evidence](research/camera-views/CAM-01-10/README.md)

## 2026-10-13 · AUD-07 — Godot audio: loops click, the hard limiter sticks; measure the mixer, not the asset

Godot 4.7.2 plays a forward-looping `AudioStreamWAV` by interpolating past `loop_end` into the stream's silent padding. A perfectly seamless PCM source therefore clicks at every wrap, at any pitch and with or without 3D positioning: the second difference at the seam is hundreds of times its median. Source seam metrics and earlier speaker reviews passed it. Append a copy of the loop's first frames after `loop_end` (`Soundscape.seamless_loop`), and check loops in the mixed output. `AudioEffectHardLimiter` never fully releases: after one overshoot the bus stays about 0.15 dB·s / `release` low for the rest of the session (−1.3 dB at 0.12 s), so a single loud moment ducks everything after it; the stateless `AudioEffectLimiter` recovers. A 3D player that starts at the listener's position plays at `max_db` whatever its `volume_db`, so position voices before `play()`. On the display-less Linux host, `--write-movie <x>.png --fixed-fps 60` under Xvfb writes the real Master mix to `<x>.wav`, frame-aligned with the simulation; `tools/audio/bench.sh` wraps it. [Audio realism plan, F14–F16](plans/audio-realism.md), [probes](../research/audio/review-2026-10-13/README.md)

## 2026-10-13 · CR-09d2 — heavy settling damping can hide collision tunnelling

The wreck's 1.5 s⁻¹ linear damping looked like a harmless settling aid. Lowering it to a physically plausible 0.3 s⁻¹ made the box colliders tunnel through the ground plane and kept pieces awake, failing 8 wreck checks. Before relaxing a damping or clamp, find out what it is compensating for, and fix that first (here: real collision shapes, CR-09d3). [CR-09d](research/crash-damage-investigations/CR-09d/README.md#cr-09d2--surface-aware-wreck-contact-2026-10-13)

## 2026-10-13 · CR-09d1 — check presentation physics against the flight model's own invariants

The wreck's fixed section mass shares looked reasonable section by section, yet put the intact wreck's centre of mass 231.5 mm from the airplane's real CG: the wreck had tumbled about the wrong point since CR-09a without any check noticing. When presentation code builds its own physics (masses, centres, inertia), test it against an invariant the flight model already guarantees (here: the intact wreck's centre of mass equals the aircraft CG) instead of against plausible-looking numbers. [CR-09d](research/crash-damage-investigations/CR-09d/README.md)

## 2026-10-13 · CR-01d — run a generator's --check at HEAD before regenerating

`tt07/derive_physics.py --check` already failed on the Linux host at HEAD, under Python 3.12 and 3.13. Regenerating there changed four floats in their last digit, a platform-only physics change hidden inside an unrelated edit. Check freshness before editing a generator. If HEAD is already stale, keep the committed values, insert only the intended change, prove the remaining difference is that drift, and have the reference machine confirm. [CR-01d](research/crash-damage-investigations/CR-01d/README.md#timber-platform-drift)

PT1-rc9 traced this drift to Python 3.12's changed floating-point `sum()`. Explicit left-to-right accumulation preserves the existing generated values on both Windows and Linux. Reproducible generators must also specify path ordering: `Path` comparison differs across platforms, even when every source byte matches. Fix deterministic generation before replacing valid reference artifacts. [Cause and verification](research/release-readiness/PT1-rc9/README.md#release-repairs).

D6e-S (2026-10-14) found the same trap in input bytes. Workshop descriptors hash the exact aircraft JSON bytes, and `.gitattributes` makes those JSONs CRLF. A working copy written before that rule still holds LF. A descriptor regenerated there binds LF hashes, passes `--check` locally, and fails in every fresh clone (`research/aircraft-editor/test_descriptor_checkout.py`). Before regenerating byte-bound outputs, normalize their inputs to the `eol` rule; git sees no change.

## 2026-10-13 · CR-08b — effective mass grades the first contact, not the whole impact

Effective mass at the struck point fixes whole-mass overrating: a level wingtip engages about 7 %. It also underrates oblique hits on long-nosed airframes. In a 45° Ventage Jet dive the nose engages 20 % of the mass and grades C2, yet the CG keeps most of its normal energy and slams the belly down next. Grade the first contact and also bound what the CG still carries into the surface; do not count sliding speed as impact energy. [CR-08b](research/crash-damage-investigations/CR-08b/README.md)

## 2026-10-12 · VQ-05 — Compatibility lights by winding and ignores per-instance transparency

`GeometryInstance3D.transparency` reads as zero on the Compatibility renderer (documented for 4.7), so a fade needs an alpha-blended material of its own. A cull-disabled surface is lit with its normal flipped on back faces: the lit side follows the triangle winding, not the supplied normal, so a consistently wound double-sided disc reads as lit from both sides. Keep a presentation node beside a model when another system duplicates (crash wreck) or collects (projected silhouette) that model, show or hide the model's nodes instead of editing their resources, and prove the stopped state byte-identical. [Probe and evidence](research/visual-quality-implementation/VQ-05/README.md).

## 2026-10-12 · TT-02/03/05 — imported meshes: measure arrays, never trust transformed boxes, wrap Euler-driven pivots

An imported object can contain multiple open or overlapping shells. Ray-parity containment assumes a closed boundary; using an AABB-filtered triangle subset opens it further and produced false control-interference reports on Timber r2. Test surface crossings with the millimetre scaling described in US-V09c, and qualify containment separately. Keep collision-probe semantics distinct from authoring extrema: a max-span cap marker and a navigation lens can differ by 155 mm fore/aft even when the wing skin is unchanged. [TT-19 diagnosis and contact convention](research/timber-integration/TT-19/README.md).

Three surprises from the first glTF aircraft. A probe reported a vertex 7.9 mm ahead of the spinner because it transformed each mesh's axis-aligned bounding box; the tilted propeller's box corners stuck out and no vertex was there. Measure extents from transformed vertices, and read them with `surface_get_arrays()`: `Mesh.get_faces()` returned positions up to 28 µm off on this import with or without vertex compression. Godot's `rotation.x/z` setters replace a node's whole basis, so an imported pivot with a rest rotation cannot be driven by them; give it a mount that carries the rest basis and an identity child that takes the Euler angle, and prove the sense with a witness vertex. [TT-02](research/timber-integration/TT-02/README.md), [TT-03](research/timber-integration/TT-03/README.md), [TT-05](research/timber-integration/TT-05/README.md).

## 2026-10-07 · VAL-6a — reduce swing tests about a common axis

Subtract loaded and empty-rig compound inertia about the shared pivot before shifting the object to its CG; the two configuration CGs usually differ. Combine sensitivities of reused measurements before squaring uncertainty contributions. A stationary first derivative can hide second-order height uncertainty. Preserve the net pivot result: a rigid-mass axis shift does not resolve aerodynamic added-inertia transfer. [Equations, limits and verification](research/validation/VAL-6a/README.md).

## 2026-10-07 · L9c — preserve field data while merging render surfaces

A render batch limit must not silently narrow the accepted field format. Validate containment, flat coverage and capacity before replacing any geometry; use a whole-field fallback for unsupported layouts. Derive overlapping surface colours from the same base grass to avoid multiplying brightness.

A half-pixel image difference includes expected camera motion. Surface-on/off pairs isolate the surface from the grass, but do not by themselves isolate aliasing. Keep motion measurements observational unless an appropriate control actually substantiates the claimed gate. [Implementation and evidence](research/visual-quality-implementation/L9c/README.md).

## 2026-10-07 · E0b6p — duplicated work needs branch-specific evidence

Sharing thrust/torque halves the powered wake load path’s calls, but reverse cutoff already skips the duplicate and pays only the added argument/dispatch work. Preserve that control case when measuring an optimization. Count the continuous transport callback separately: stopped residual wash still evaluates its target four times per tick, so changing Dynamics alone does not remove that work. Exact trajectories establish numerical safety; mixed paired whole-tick savings are sufficient reason to leave a candidate outside production. [Experiment and decision](research/propwash/E0b6p/stage-sharing/README.md).

## 2026-10-07 · VAL-5a — shared weighing errors do not average away

A calibration gain shared by every scale changes total mass but cancels from the CG ratio; a shared coordinate datum error contributes once, without shrinking with the number of supports. Propagate net readings through centered-arm sensitivities so moment/mass covariance is retained. Diagnose CG linearization from local load uncertainty: a large common gain alone cannot make CG uncertain. [Measurement model and verification](research/validation/VAL-5a/README.md).

## 2026-10-07 · DATA-3 — fingerprint the bytes that were actually loaded

A rounded JSON serialization can hide a change to a parsed aerodynamic coefficient: the CL0 late-digit regression reproduces this collision. Hash the same byte buffer used for parsing, retain that identity across failed reloads, and never reread a mutable path when recording. Keep source-file identity separate from the derived-model checkpoint fingerprint; in-memory inputs have no original file bytes. Version the metadata and label legacy semantic-only checks explicitly. [Contract and verification](research/aircraft-validation/DATA-3/README.md).

## 2026-10-07 · VAL-7a — keep measured and ideal propeller power distinct

Thrust and RPM cannot establish shaft power without torque or another independent shaft-power measurement. Static ideal-disc power is a model bound; figure of merit is distinct from propulsive efficiency. Calculate ratio uncertainty from original inputs: derived Ct and Cp share density and diameter errors. [Reduction equations and verification](research/validation/VAL-7a/README.md).

## 2026-10-08 · E0b6p — snapshot isolation is not model freshness

A native snapshot can remain safely isolated yet become stale relative to its source dictionary. Rebuild explicitly after nested edits and invalidate old generations even when replacement preparation fails. Test refusal through the adapter: a stateless fallback can preserve nominal load equality while bypassing the lifecycle contract. [Ownership lesson](learnings/physics.md#a-prepared-model-needs-an-explicit-ownership-boundary), [experiment](research/propwash/E0b6p/prepared-model/README.md).

## 2026-10-08 · L9c-R1 — subtract expected image motion

To measure sampling error, isolate the changing cue with a zero-amplitude capture and subtract the motion of an independently supersampled reference. Check two reference resolutions: a low-resolution reference can alias more than the candidate. Define thin distant-surface masks in world units; a one-pixel erosion can erase the entire target. Preserve a nearby-detail control so removing the feature cannot pass as good filtering. [Method, limits and evidence](research/visual-quality-implementation/L9c-R1/README.md).

## 2026-10-08 · DATA-2a — preserve the quantity a numerical search solves

Replacing a sampled lift maximum with a continuous optimizer can change a stall angle even when both searches are accurate. Bound and prune the original grid when exact behavior must survive: a curvature/chord bound avoids assuming a single peak, while an exhaustive oracle and deliberate bound mutations verify the implementation. Keep floating-point safeguards distinct from a formal interval proof. [Derivation, equivalence checks and timing limits](research/aircraft-validation/DATA-2a/README.md).

## 2026-10-07 · E3c1a — stopping is not proof of runway landing

A soft touchdown followed by a stop can hide a runway overrun: rough ground supplied the stopping force in early approach trials. Check every wheel throughout rollout and require a stable idle hold inside the strip. Run the actual session crash detector at each committed boundary; calling only the integrator bypasses it and lets an initially penetrating aircraft advance. [Trajectories and rejection controls](research/ground-contact/E3c1a/README.md).

## 2026-10-08 · G1b1 — verify the sampled command and the recorded query

Synchronous `sim.step()` does not sample changed session commands: an intended idle/full-power fixture kept flying at trim throttle until its inputs were explicitly updated. Assert recorded commands and RPM before accepting a maneuver's label. Trace v3 also pairs previous-state velocity with current RPM for its load columns; a same-row reconstruction evaluates a different operating point. Keep clamped reverse-flow J=0 separate from static-source support. [Regression and flight-query evidence](research/propulsion/G1b1/README.md).

## 2026-10-08 · L10a — model calm and constrain actual geometry

A calm windsock still holds its throat and first three-eighths open on a basket; the remaining sleeve hangs. Preserve cloth arc length through the bend instead of shortening it by projecting a straight sleeve. Optional field cues should preserve legacy fields, and placement exclusions must match the terrain actually rendered: the 1.5 km flat radius belongs only to the 40 km hill mesh. Remove unrelated cues explicitly from synthetic geometry fixtures. [Contract and evidence](research/visual-quality-implementation/L10a/README.md).

## 2026-10-08 · D1-R4 — validate the solved domain and residual

Finite input coefficients can produce an out-of-domain stall root or a blend whose endpoints collapse in float64. Check physical reachability before dividing by a tiny slope, then validate finite ordered angles and the solved peak. A NaN residual needs an explicit finiteness check: comparison with a tolerance does not reject it. [Derivation and verification](research/aircraft-validation/D1-R4/README.md).

## 2026-10-08 · L10b — test a near-pilot prop from the pilot eye

A plausible close-up does not establish that a nearby barrier preserves the runway view. Pair visible inspection views with exact on/off comparisons from the actual pilot eye toward both thresholds; verify that a pixel change fails the equality guard. Exclude the entire grass-clump envelope around a pad, not just roots inside its footprint. [Geometry, captures and limits](research/visual-quality-implementation/L10b/README.md).

## 2026-10-08 · G1a1 — preserve source meaning during normalization

The UIUC 12×6 tunnel file needs both deduplication and sorting; stripping repeated final rows alone leaves a backward coordinate step. Preserve source-line identity and distinguish exact duplicate points from conflicting repeated measurements. Normalized knots do not establish continuous coverage, and a run label does not supply per-row RPM. [Source readback and parser proof](research/propulsion/G1a1/README.md).

## 2026-10-08 · L10c/d — validate the view, not only the footprint

A barrier can clear the runway rectangle yet hide its near edge. Validate its height against the pilot-to-ground sightline, then protect projected runway pixels in on/off captures. Clip bounds and protected polygons at the camera near plane before projection. Keep contact footprints tied to the renderer’s post-layout helper; check stored vertex alpha as a range because the mesh quantizes it to 8-bit values. [Evidence and limits](research/visual-quality-implementation/L10c/README.md).

## 2026-10-10 · FW-23/FW-24 — Compatibility's colour path breaks at night exposures

Values calibrated at exposure 0.6 hide two engine behaviours that a night exposure of 10⁴–10⁵ exposes. Every material's `ALBEDO`/`EMISSION`, unshaded included, passes through the engine's cubic `srgb_to_linear`, so a computed linear radiance must be encoded with that cubic's inverse or faint values lose ~13×; and the sky radiance cubemap already contains the exposure, which `scene.glsl` applies again to ambient, turning lit surfaces white. Probe a constant, known value at two exposures before trusting a brightness model, and read the pinned engine source for the conversion. [FW-24 findings](research/field-world/FW-24/README.md).

## 2026-10-09 · M5-W04a — keep random forcing inside the transaction

A seeded RNG is insufficient for deterministic simulation: stage/render queries must never advance it. Store the exact RNG bits beside the filter interval in the existing sampled/discrete checkpoint and rollback both on a failed step. Reconstruct Gaussian samples from raw integer words when an engine's normal helpers use float32. A seed's PCG sequence initializer differs from the runtime recurrence increment; independent replay exposed this distinction. For replay, keep int64 state out of JSON numeric fields. [Kernel and integrated proof](research/wind-implementation/M5-W04a/README.md).


## 2026-10-09 · M5-ATM-2/3 — density is shared, engine charge is distinct

Thread one field density through trim, aero, propeller load, wake and telemetry before exposing an atmosphere control. Moist aerodynamic density includes vapor; a naturally aspirated engine's oxygen-bearing charge follows dry partial pressure. Scale indicated torque explicitly and keep friction fixed, while leaving other propulsion laws separate. Preserve the literal reference branch instead of recomputing a nearly identical baseline, and reject a new environment's failed trim rather than flying its previous solution. [Equations and fleet proof](research/atmosphere/M5-ATM-2/README.md).

## 2026-10-09 · G2a/G2b — relative rotor speed couples to body acceleration

With locked aircraft inertia, relative shaft acceleration and body acceleration along the shaft must be solved together. Add relative-spin reaction once over the existing external propeller torque, and use stage RPM for both loads and gyro momentum. Check angular momentum and motor work independently; algebra alone can hide an omitted body-acceleration term. Quantify table-knot crossings separately from smooth RK4 order, and use quaternion chord distance when errors are too small for `acos(dot)`. Continuous wake increments are signed; only the RPM suffix has a nonnegative domain. [Equations, conservation and refinement](research/propulsion/G2a-RK4/README.md).

## 2026-10-09 · G2a-R1 — reuse work inside the RK stage

Coupled equations can need the same expensive loads to obtain forces and continuous derivatives. Return loads, derivatives and spinning momentum together from one pure stage evaluation, then validate the complete payload before consuming it. Keep that result inside the step; a persistent query cache would need every state, command, environment and model dependency in its key. Prove full checkpoint and trajectory bits against the frozen pre-optimization implementation, including sampled RNG and optional wake state. [Exact parity and measured cost](research/propulsion/G2a-R1/README.md).

## 2026-10-10 · Rendering — scene snapshots must retire global progression

A scene-local lighting snapshot must retire any previous global sky progression before updates resume; changing only the Sun and Environment leaves a controller that can overwrite the new scene. Pass the same explicit snapshot to the sky, light and ground, while keeping empty arguments on the legacy route. Test the transition from a flowing world as well as each renderer separately. [Integration proof and limits](research/branch-integration-2026-10-10.md).

## 2026-10-12 · CR-17a — spend a local contact budget at the impact

Splitting fences into visible bays increased the nearby proxy count; selecting the first 160 inventory IDs then omitted the car, trunk or lamp the wreck had just struck. Rank secondary-contact candidates by distance to the actual impact before applying the cap, and verify engine ray queries for the struck obstacle after the inventory grows. [Failure, correction and native checks](research/crash-damage-investigations/CR-17a/README.md).

## 2026-10-12 · TT-11 — seed ground equilibrium from the support plane

A level Newton seed can converge to a two-main-wheel equilibrium for a taildragger even when the authored three-point gear supports the CG. A small residual does not establish the intended resting configuration. Seed height/roll/pitch from the actual contact plane, retain the established nosewheel branch, and require every selected contact to stick before accepting the start. [Timber diagnosis, static support and refinement](research/timber-integration/TT-10/README.md).

## 2026-10-13 · HELI-04 — check crossflow joins as well as axial joins

Johnson's published inflow table contains printed endpoint/derivative errata, and its moving axial polynomials still jump when an entire crossflow branch switches off at C or M. Matching values and slopes inside one slice does not prove continuity across another parameter. Inspect the rendered equations, verify one-sided values with an independent implementation and retain source-law limitations as integration gates; do not silently fit a smoother. Ground-effect activation also needs downstream-wake geometry: signed body-axis thrust alone cannot distinguish upright descent from inverted lift. [Primary-source interpretation and checks](research/helicopter/HELI-04/README.md).

## 2026-10-13 · HELI-05 — isolate rate terms before trusting an oracle

A first transcription put the rotor's body-rate terms inside the angle/lag bracket, turning rad/s into rad/s² while zero-rate fixtures still looked correct. At zero flap, cyclic and translational flow, the source requires `a1dot=-q` and `b1dot=-p` at every active rotor speed. This dimensional known answer caught the reference error before acceptance; a duplicated numerical oracle alone would not. Test terms with distinct units separately, then compare the complete response. [Source equations and independent checks](research/helicopter/HELI-05/README.md).
