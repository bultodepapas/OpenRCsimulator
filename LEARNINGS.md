# Learnings

**Status:** curated developer reference. Lessons from building and testing this repository; historical measurements belong to their linked reports.

Start here for mistakes worth avoiding. Commands live in [TOOLS](docs/TOOLS.md) and working rules in [AGENTS](AGENTS.md), current work in the [plans](docs/README.md#tracks-plans-and-step-ids), and detailed experiments in the [research index](docs/research/README.md).

| When working on… | Read next |
| --- | --- |
| Physics, state, aircraft data or performance | [Physics lessons](docs/learnings/physics.md) |
| Aircraft geometry, references, scenery or visual checks | [Models and rendering lessons](docs/learnings/models-and-rendering.md) |
| Godot execution, radio, menus, preferences or exports | [Runtime and delivery lessons](docs/learnings/runtime-and-delivery.md) |

## Prove what the airplane actually does

- **Passing regressions do not establish realistic flight.** The rudder's sign and golden replay were correct while a short pulse drove extreme sideslip and persistent rotation. A test computed from the same borrowed coefficients cannot validate those coefficients. Use independent data and flown magnitude/recovery checks; label known-defect characterizations as such. [Rudder audit](docs/research/ugly-stik-rudder-audit.md), [validation contract, VAL-3](docs/research/validation/VAL-3/README.md).

- **Exercise the real session, including trim and controls.** Unit tests passed while the app's synchronous trace path omitted elevator trim. A longitudinal-only trim also let propeller torque roll an apparently hands-off airplane into a spiral. Check the actual app's flight against the solver, including lateral trim, engine state and applied commands. [Trim solver tests](app/tests/test_trim.gd), [app trace check](app/tests/check_trimmed_flight.py), [session-path example, E0a2b](docs/research/aero-consistency/E0a2b/README.md).

- **Inspect trajectories before turning expectations into assertions.** Early spin models produced plausible-looking test outcomes with runaway rates; ground fixtures later exposed maneuvers flying below the field. Record angular rates, recovery and minimum altitude, and state the scripted pilot's technique. Full elevator can correctly stall a model; weakening authority to make a bad pilot pass hides that behavior. [Flight-model audit](docs/research/flight-model-robustness-audit.md), [E1](docs/research/landing-gear-contact-e1.md), [P-51 flight trials](docs/research/p51-flight-realism.md).

- **An oracle only applies under its stated assumptions.** Comparing different aircraft at equal speed instead of equal lift coefficient changed the apparent mode discrepancy. A fixed-attitude takeoff integral also diverged once the aircraft pitched, then agreed when fed the recorded attitude. State normalization, shared inputs and omitted physics before interpreting a gap. Full-roll video timing also measures a cycle average, not instantaneous body `p` or a decay pole; match the quantity before comparing ([VAL-8b](docs/research/validation/VAL-8b/README.md)). [VAL-3](docs/research/validation/VAL-3/README.md), [E3b3](docs/research/ground-contact/E3b3/README.md).

## Make evidence capable of rejecting a defect

- **A successful process or existing file does not prove a completed run.** The old trim checker accepted one-row traces and non-finite endpoints; capture scripts could accept a stale PNG after timeout. Require the requested duration, continuous tick/time pairs, finite samples, fresh artifacts and successful engine logs before judging quality. A readable ZIP can still contain a truncated executable after temporary-disk exhaustion; inspect archive members and budget output plus temporary storage ([PT1h](docs/research/release-readiness/PT1h/README.md)). [C7-R1](docs/research/trace-integrity/C7-R1/README.md), [VQ-01a](docs/research/visual-quality-implementation/VQ-01a/README.md).

- **A mutation needs a valid control and the intended failure.** Probes appeared to reject malformed input only because their baseline was already invalid. First show a finite, valid case succeeds, then inject a bounded defect and verify which assertion rejects it. An extreme literal may fail an earlier guard: construct finite normal inputs that overflow only the target expression, and remove that guard in a disposable copy to prove the assertion reaches it ([EL2a-P1](docs/research/propulsion/EL2a-P1/README.md#verification-record)). Run mutations on disposable copies so deliberate defects cannot enter another contributor's run or commit. [Native positive controls](docs/research/propwash/E0b6p/native/README.md), [VAL-4](docs/research/validation/VAL-4/README.md).

- **Separate preservation from correction.** Capture a baseline before a refactor and compare complete state, auxiliaries and loads. Byte equality proves the old behavior was preserved, including its defects. For a deliberate physics change, explain changed trajectories before re-recording goldens; switching the new term off can isolate its effect. [Exact-refactor evidence, H12](docs/research/simulation-state/H12/README.md), [D11d](docs/research/aero-consistency/D11d/README.md).

- **Visual metrics need a clean subject and a real renderer.** A changed-pixel airplane mask included its shadow and panel text, producing a false readability failure. Broad averages also hid narrow seams, while headless MultiMesh reads returned dummy transforms. Validate masks and spatial bins with injected visual defects, then use rendered readbacks for GPU-owned state. [L11a](docs/research/visual-quality-implementation/L11a/README.md), [visual evidence guide](docs/learnings/models-and-rendering.md#rendering-and-visual-evidence).

## Respect the boundaries between systems

- **Observation history and operational permission can need different lifetimes.** A raw throttle event remained useful to the latency marker after calibration, but could not justify arming under the new mapping. Keep connection-wide diagnostics while resetting profile-specific low-throttle evidence; check both the fresh event and current polled position. [Rearming repair, D6b-R2](docs/research/radio-input/D6b-R2/README.md).

- **Keep float64 physics separate from rendering types.** A small-acceleration test lost the entire velocity increment in Godot's float32 `Vector3`, while the float64 state preserved it. Convert at the rendering boundary; seeded quaternion composition checks also caught an error missed by individual known-answer cases. [Math tests](app/tests/test_math3d.gd).

- **The body array is not the whole simulation.** A wake lag advanced outside RK stages can lower integration order, and restoring only the rigid body leaves engine mode, sampled state or clock inconsistent. Define continuous, sampled and discrete state before extending the model, and test complete rollback and continuation. [H8a](docs/research/simulation-state/H8a/README.md), [H8](docs/research/simulation-state/H8/README.md), [E0b5](docs/research/propwash/E0b5/README.md).

- **Local event time and the absolute clock have different precision.** Rejecting a positive remainder because it cannot advance the rounded clock can fail a valid event-composed tick. Keep the local root bound distinct from timestamp rounding, and test near-endpoint events at nonzero clocks. [EL2a-P2](docs/research/propulsion/EL2a-P2/README.md), [numerical details](docs/learnings/physics.md#every-coupled-continuous-state-needs-the-same-integration-stages).

- **Use one air-relative flow and keep ground velocity intact.** A new wind path must also reach shaft inflow, wake transport, downwash, reset equilibrium and telemetry; changing only the main aero load leaves locally valid consumers inconsistent. Uniform-wind Galilean tests expose missed consumers without tuning aircraft coefficients. Trace state-time and k1 load-time samples separately, and fingerprint forcing in replay. [Wind delivery and proofs](docs/research/wind-implementation/README.md).

- **Integration errors often hide between two locally correct systems.** A model verifier existed without running in CI, generated reports could lag current runtime data, and visual coordinates could introduce a false force arm when copied into physics. Check the complete generation chain, shared datums and session wiring. Audit executable source and tracked tests when resuming a report: D1-R5 retained a patch and passing logs while the app still used the old loader and the referenced regression source was absent. [DATA-1](docs/research/aircraft-validation/DATA-1/README.md), [E0b2](docs/research/propwash/E0b2/README.md), [D1-R5 integration](docs/research/aircraft-validation/D1-R5/integration/README.md).

- **Source inspection proposes a behavior; the shipped path establishes it.** Real exports disproved the claim that JSON always needed an include filter. A scenery probe also reversed a paper recommendation for mesh merging. Read the pinned engine when needed, then reproduce the exact backend, import path and exported configuration before writing a rule. [SC-01](docs/research/scenery-implementation/SC-01/README.md), [runtime lessons](docs/learnings/runtime-and-delivery.md#clean-builds-and-desktop-evidence).

## Measure under conditions that support the claim

- **A component speedup is not a flight-budget result.** Native slipstream reduced local cost while whole ticks still exceeded budget. Measure complete evolving trajectories across aircraft/regimes, include adapter and decoding costs, and keep timing buckets exclusive. Distinguish batch-average percentiles from individual-tick latency. [Gate P](docs/research/simulation-state/Gate-P/README.md), [E0b6p attribution](docs/research/propwash/E0b6p/attribution/README.md).

- **Freeze the inputs to a comparison.** Concurrent aircraft regeneration changed flight fingerprints during a refactor; parallel suites raced on shared preferences; visual edits mixed two versions in one capture run. Use an isolated source/data snapshot and separate runtime settings for comparable evidence. [H13/H14](docs/research/simulation-state/H13/README.md), [VQ-01a](docs/research/visual-quality-implementation/VQ-01a/README.md).

- **Match acceptance to the observer.** Software-rendered captures establish pixels and repeatability, not target-GPU frame times or human attitude recognition. Export inspection establishes package structure, not native launch or signing trust. Keep pilot trials, hardware timing and native OS checks as distinct evidence. [L6c](docs/research/visual-quality-implementation/L6c/README.md), [DT-00-R2](docs/research/desktop-delivery-investigations/DT-00-R2/README.md).

## Keeping this useful

Add a lesson when an observed failure or surprising result changes how a future developer should work. State the cause, the practical consequence and an evidence link with the relevant step ID. Merge with an existing lesson when possible; keep specialized detail in the topic guides above.

Put step status and next actions in the owning plan, measurements and reproduction details in the evidence report, architectural choices in [DECISIONS](DECISIONS.md), and shipped changes in release notes. Routine passes, test counts, machine inventories and generic advice do not need a learning entry. If a later experiment corrects a lesson, update the recommendation and link the correction rather than leaving contradictory advice.

## 2026-10-15 · P51-24 — a constant inside a metrology script is not a measurement

The P-51's "measured" tail group carried a hard-coded rudder hinge, so its physics rudder was 43 % short of the NACA production area. It looked plausible because the measured outline around it was right. Steady-sideslip data exposed it: the model needed about four times the rudder per degree of sideslip that the P-51D flight tests recorded. Cross-check every control-surface split against published surface areas, chords and spans before tuning stability. Keep the visual and physical definitions explicit when they cannot change together. In this case the generator solved an aerodynamic hinge from the silhouette and the NACA area, which then reproduced the published chord and span independently, while the visual rework stays a separate reviewed step. [P51-24](docs/research/p51-realism/P51-24/README.md)

## 2026-10-15 · P51-22 — a consistent law can drop a measured effect; fix the source, not the denominator

R02 rewrote tail downwash as a wake velocity divided by the local tail speed. This is consistent in units, but inside the propeller jet it divided by the washed speed and almost removed the downwash. NACA Report 690 measured propeller operation increasing tail downwash on the tested aircraft. The P-51, the only catalog aircraft with tail wash, now rotated 3 m/s later and snap-rolled out of a test loop. The shared suites still passed, because their reference oracles encoded the new law. When you refactor a shared law, run every aircraft that declares the module and compare known qualitative effects from primary data. Bisect regressions in a clean worktree with that aircraft's tests. Do not patch the consumer instead of the missing source: replacing the washed denominator with the free-stream speed restored the tests but created a direction-dependent zero-speed force jump. The missing physics was the wing's immersion in the jet ([owner review](docs/research/physics-audit-2026-10-14/remediation/R11/washed-downwash-diagnostic/README.md)). [P51-22](docs/research/p51-realism/P51-22/README.md)

## 2026-10-14 · P51-19/20 — a matching trim gradient can hide a zero-lift moment error

The P-51's trim gradient and neutral point matched the full-size data, yet it needed 6.5° of up elevator to cruise. The full-size XP-51 needed about 1° at the same CL and CG. The handbook tail incidence and downwash left ΔCm0 ≈ +0.06 unaccounted for, which is easy to dismiss as RC "rigging". When the geometry is scaled from a documented full-size airplane, compare absolute elevator-for-trim at equal CL and CG against the flight-test trim curves before tuning handling. NACA flying-qualities reports publish them. Fit glide data, and keep cruise as an unfitted check: power effects differ between installations. Shared-module constants fitted to another planform are a similar trap. The Stik's ground-effect tail fit gives 0.27 of the free-air downwash at h/b 0.12, while a VLM of the P-51, whose tail sits 0.26 m above its low wing, gives 0.62. [P51-19](docs/research/p51-realism/P51-19/README.md) · [P51-20](docs/research/p51-realism/P51-20/README.md)

## 2026-10-13 · D6e-R1 — a borrowed `Cma` carries the donor's static margin, not the target's

Static margin is neutral point minus CG, and the neutral point comes from the target's own wing, tail and downwash. Applying the Ultra Stick's `Cma` about the Ugly Stik's plan CG gave 18.9 % margin where its planform gives about 4–8 %, so the model holds trim α too stiffly and turns every speed gain into a pull-up. Derive pitch stiffness from the target geometry at the target CG, or move the coefficient reference so the neutral point is geometric; then regenerate every value defined about that reference (fin-arm, rate and local-tail terms). Compare propeller tables at the same engine power, not the same rpm: the 12×6 table looked 1.4–1.8× weaker at 11149 rpm, but the repository's power balance spins it to about 12650 rpm and the climb is unchanged. [Root-cause review](docs/research/flight-dynamics/climb-trim/README.md#root-cause-review-2026-10-13-d6e-r1)

## 2026-10-14 · NITRO-05 — onboard fluids feel the specific force, not the attitude

The first fuel-feed tests expected a nose-up attitude to lean the engine and a nose-down one to richen it. Gravity accelerates the fuel and the airframe alike. The fuel feels only `−F_non-gravitational/m`: lift, thrust, drag and ground loads. A level airplane accelerating at full throttle therefore leans exactly like a steady up-line, and a dive richens only while drag slows it. Model any onboard fluid, accelerometer or pilot cue from that stage-local specific force. Test it from steady or explicitly accelerating states, never from attitude alone. [NITRO-05](docs/plans/RC_NITRO_ENGINE_REALISM_PLAN.md#milestones-and-proof-register) · `app/tests/test_glow_fuel_feed.gd`

## 2026-10-13 · CR-09f — a SceneTree test that hits a script error hangs instead of failing

When a `--script` SceneTree test raises a runtime script error (indexing `[0]` of an empty list, `.field` on `{}`), Godot prints the error and never reaches `quit()`; the runner only sees its timeout. Two CR-09f mutations looked like hangs for this reason. Fetch optional sections through helpers that return `{}` and read keys with `.get(key, default)`, so a missing part fails its checks and the summary line still prints. [CR-09e/f evidence](docs/research/crash-damage-investigations/CR-09e/README.md)

## 2026-10-13 · US-V10 — bend presentation meshes with relative per-axis blend shapes

The Compatibility renderer in 4.7.2 applies blend shapes. With `BLEND_SHAPE_MODE_RELATIVE` and three unit shapes per deforming part (X, Y, Z offsets weighted by a shape function), a physics offset in any direction becomes three blend weights: no per-frame vertex rebuild and no attitude assumptions. Two traps showed up. Boxes from `_bar` have vertices only at their ends, so a "bent" leg stays straight until it is segmented. And a test that computes its expected value with the function under test passed a linear-shape mutation, so check against an independent analytic value (5/16 of the tip at cantilever mid-span). [US-V10 evidence](docs/research/ugly-stik-finish-v6.md#us-v10--landing-gear-flex)

## 2026-10-13 · US-V09c — Geometry3D intersections miss millimetre triangles expressed in metres

`Geometry3D.segment_intersects_triangle` and `ray_intersects_triangle` treat a determinant below their 1e-5 epsilon as parallel. A mesh built in metres with millimetre-sized triangles therefore returns no hit at all, and an interference check passes while the throttle pushrod runs straight through the exhaust casting. Scale points and triangles to millimetres, as `visual_checks.gd` already does. Keep a positive-control segment that must hit, and mutate the installation once to prove the probe fails. [US-V09c evidence](docs/research/ugly-stik-finish-v6.md#us-v09c--throttle-linkage)

## 2026-10-13 · US-V09b — missing tangents and 8-bit slopes break subtle normal maps without errors

Without `SurfaceTool.generate_tangents()`, Godot 4.7 fills an arbitrary orthonormal tangent frame. The normal map then renders in the wrong direction, and both "has tangents" and orthogonality checks still pass. Compare each triangle's UV-derived dP/du with the stored tangent instead. RGB8 also quantises tilt in steps of about 0.45°, too coarse for sub-2° film sag. Store the slope ×8 and set `normal_scale = 1/8`; the normal-map depth is a mix, so this is accurate at small angles. [US-V09b evidence](docs/research/ugly-stik-finish-v6.md#us-v09b--film-over-structure)

## 2026-10-13 · CAM-08 — spring the camera's offset, not its world position

A critically damped spring that follows a moving point trails it by 2v/ω in steady motion: about 7 m at 20 m/s with a 0.25 s half-life, so a chase camera sprung in world space slides back to its lag cap whenever the airplane flies straight. Spring the offset from the target instead, in the target's frame or as a world-axis offset, and smooth only changes of heading, height or zoom. Test steady straight flight at several frame rates, not only a step response. Also, compare render results (`Vector3`, 32-bit) to about 1e-6. [CAM evidence](docs/research/camera-views/CAM-01-10/README.md)

## 2026-10-13 · CAM-04 — Help has no spare row at 720p; key caps set the column width

Help fit 598 of 600 px at 1280×720 before the camera keys. One extra row overflows, and a single wide key name ("Retroceso" in Spanish) widens the cap column so other rows wrap. Fold new keys into existing rows, prefer short key names, and run `test_ui_help.gd` in both languages before adding a shortcut. [CAM evidence](docs/research/camera-views/CAM-01-10/README.md)

## 2026-10-13 · AUD-07 — Godot audio: loops click, the hard limiter sticks; measure the mixer, not the asset

Godot 4.7.2 plays a forward-looping `AudioStreamWAV` by interpolating past `loop_end` into the stream's silent padding. A perfectly seamless PCM source therefore clicks at every wrap, at any pitch and with or without 3D positioning: the second difference at the seam is hundreds of times its median. Source seam metrics and earlier speaker reviews passed it. Append a copy of the loop's first frames after `loop_end` (`Soundscape.seamless_loop`), and check loops in the mixed output. `AudioEffectHardLimiter` never fully releases: after one overshoot the bus stays about 0.15 dB·s / `release` low for the rest of the session (−1.3 dB at 0.12 s), so a single loud moment ducks everything after it; the stateless `AudioEffectLimiter` recovers. A 3D player that starts at the listener's position plays at `max_db` whatever its `volume_db`, so position voices before `play()`. On the display-less Linux host, `--write-movie <x>.png --fixed-fps 60` under Xvfb writes the real Master mix to `<x>.wav`, frame-aligned with the simulation; `tools/audio/bench.sh` wraps it. [Audio realism plan, F14–F16](docs/plans/audio-realism.md), [probes](research/audio/review-2026-10-13/README.md)

## 2026-10-13 · CR-09d2 — heavy settling damping can hide collision tunnelling

The wreck's 1.5 s⁻¹ linear damping looked like a harmless settling aid. Lowering it to a physically plausible 0.3 s⁻¹ made the box colliders tunnel through the ground plane and kept pieces awake, failing 8 wreck checks. Before relaxing a damping or clamp, find out what it is compensating for, and fix that first (here: real collision shapes, CR-09d3). [CR-09d](docs/research/crash-damage-investigations/CR-09d/README.md#cr-09d2--surface-aware-wreck-contact-2026-10-13)

## 2026-10-13 · CR-09d1 — check presentation physics against the flight model's own invariants

The wreck's fixed section mass shares looked reasonable section by section, yet put the intact wreck's centre of mass 231.5 mm from the airplane's real CG: the wreck had tumbled about the wrong point since CR-09a without any check noticing. When presentation code builds its own physics (masses, centres, inertia), test it against an invariant the flight model already guarantees (here: the intact wreck's centre of mass equals the aircraft CG) instead of against plausible-looking numbers. [CR-09d](docs/research/crash-damage-investigations/CR-09d/README.md)

## 2026-10-13 · CR-01d — run a generator's --check at HEAD before regenerating

`tt07/derive_physics.py --check` already failed on the Linux host at HEAD, under Python 3.12 and 3.13. Regenerating there changed four floats in their last digit, a platform-only physics change hidden inside an unrelated edit. Check freshness before editing a generator. If HEAD is already stale, keep the committed values, insert only the intended change, prove the remaining difference is that drift, and have the reference machine confirm. [CR-01d](docs/research/crash-damage-investigations/CR-01d/README.md#timber-platform-drift)

PT1-rc9 traced this drift to Python 3.12's changed floating-point `sum()`. Explicit left-to-right accumulation preserves the existing generated values on both Windows and Linux. Reproducible generators must also specify path ordering: `Path` comparison differs across platforms, even when every source byte matches. Fix deterministic generation before replacing valid reference artifacts. [Cause and verification](docs/research/release-readiness/PT1-rc9/README.md#release-repairs).

D6e-S (2026-10-14) found the same trap in input bytes. Workshop descriptors hash the exact aircraft JSON bytes, and `.gitattributes` makes those JSONs CRLF. A working copy written before that rule still holds LF. A descriptor regenerated there binds LF hashes, passes `--check` locally, and fails in every fresh clone (`research/aircraft-editor/test_descriptor_checkout.py`). Before regenerating byte-bound outputs, normalize their inputs to the `eol` rule; git sees no change.

## 2026-10-13 · CR-08b — effective mass grades the first contact, not the whole impact

Effective mass at the struck point fixes whole-mass overrating: a level wingtip engages about 7 %. It also underrates oblique hits on long-nosed airframes. In a 45° Ventage Jet dive the nose engages 20 % of the mass and grades C2, yet the CG keeps most of its normal energy and slams the belly down next. Grade the first contact and also bound what the CG still carries into the surface; do not count sliding speed as impact energy. [CR-08b](docs/research/crash-damage-investigations/CR-08b/README.md)

## 2026-10-12 · VQ-05 — Compatibility lights by winding and ignores per-instance transparency

`GeometryInstance3D.transparency` reads as zero on the Compatibility renderer (documented for 4.7), so a fade needs an alpha-blended material of its own. A cull-disabled surface is lit with its normal flipped on back faces: the lit side follows the triangle winding, not the supplied normal, so a consistently wound double-sided disc reads as lit from both sides. Keep a presentation node beside a model when another system duplicates (crash wreck) or collects (projected silhouette) that model, show or hide the model's nodes instead of editing their resources, and prove the stopped state byte-identical. [Probe and evidence](docs/research/visual-quality-implementation/VQ-05/README.md).

## 2026-10-12 · TT-02/03/05 — imported meshes: measure arrays, never trust transformed boxes, wrap Euler-driven pivots

An imported object can contain multiple open or overlapping shells. Ray-parity containment assumes a closed boundary; using an AABB-filtered triangle subset opens it further and produced false control-interference reports on Timber r2. Test surface crossings with the millimetre scaling described in US-V09c, and qualify containment separately. Keep collision-probe semantics distinct from authoring extrema: a max-span cap marker and a navigation lens can differ by 155 mm fore/aft even when the wing skin is unchanged. [TT-19 diagnosis and contact convention](docs/research/timber-integration/TT-19/README.md).

Three surprises from the first glTF aircraft. A probe reported a vertex 7.9 mm ahead of the spinner because it transformed each mesh's axis-aligned bounding box; the tilted propeller's box corners stuck out and no vertex was there. Measure extents from transformed vertices, and read them with `surface_get_arrays()`: `Mesh.get_faces()` returned positions up to 28 µm off on this import with or without vertex compression. Godot's `rotation.x/z` setters replace a node's whole basis, so an imported pivot with a rest rotation cannot be driven by them; give it a mount that carries the rest basis and an identity child that takes the Euler angle, and prove the sense with a witness vertex. [TT-02](docs/research/timber-integration/TT-02/README.md), [TT-03](docs/research/timber-integration/TT-03/README.md), [TT-05](docs/research/timber-integration/TT-05/README.md).

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

## 2026-10-08 · D1-R4 — validate the solved domain and residual

Finite input coefficients can produce an out-of-domain stall root or a blend whose endpoints collapse in float64. Check physical reachability before dividing by a tiny slope, then validate finite ordered angles and the solved peak. A NaN residual needs an explicit finiteness check: comparison with a tolerance does not reject it. [Derivation and verification](docs/research/aircraft-validation/D1-R4/README.md).

## 2026-10-08 · L10b — test a near-pilot prop from the pilot eye

A plausible close-up does not establish that a nearby barrier preserves the runway view. Pair visible inspection views with exact on/off comparisons from the actual pilot eye toward both thresholds; verify that a pixel change fails the equality guard. Exclude the entire grass-clump envelope around a pad, not just roots inside its footprint. [Geometry, captures and limits](docs/research/visual-quality-implementation/L10b/README.md).

## 2026-10-08 · G1a1 — preserve source meaning during normalization

The UIUC 12×6 tunnel file needs both deduplication and sorting; stripping repeated final rows alone leaves a backward coordinate step. Preserve source-line identity and distinguish exact duplicate points from conflicting repeated measurements. Normalized knots do not establish continuous coverage, and a run label does not supply per-row RPM. [Source readback and parser proof](docs/research/propulsion/G1a1/README.md).

## 2026-10-08 · L10c/d — validate the view, not only the footprint

A barrier can clear the runway rectangle yet hide its near edge. Validate its height against the pilot-to-ground sightline, then protect projected runway pixels in on/off captures. Clip bounds and protected polygons at the camera near plane before projection. Keep contact footprints tied to the renderer’s post-layout helper; check stored vertex alpha as a range because the mesh quantizes it to 8-bit values. [Evidence and limits](docs/research/visual-quality-implementation/L10c/README.md).

## 2026-10-10 · FW-23/FW-24 — Compatibility's colour path breaks at night exposures

Values calibrated at exposure 0.6 hide two engine behaviours that a night exposure of 10⁴–10⁵ exposes. Every material's `ALBEDO`/`EMISSION`, unshaded included, passes through the engine's cubic `srgb_to_linear`, so a computed linear radiance must be encoded with that cubic's inverse or faint values lose ~13×; and the sky radiance cubemap already contains the exposure, which `scene.glsl` applies again to ambient, turning lit surfaces white. Probe a constant, known value at two exposures before trusting a brightness model, and read the pinned engine source for the conversion. [FW-24 findings](docs/research/field-world/FW-24/README.md).

## 2026-10-09 · M5-W04a — keep random forcing inside the transaction

A seeded RNG is insufficient for deterministic simulation: stage/render queries must never advance it. Store the exact RNG bits beside the filter interval in the existing sampled/discrete checkpoint and rollback both on a failed step. Reconstruct Gaussian samples from raw integer words when an engine's normal helpers use float32. A seed's PCG sequence initializer differs from the runtime recurrence increment; independent replay exposed this distinction. For replay, keep int64 state out of JSON numeric fields. [Kernel and integrated proof](docs/research/wind-implementation/M5-W04a/README.md).


## 2026-10-09 · M5-ATM-2/3 — density is shared, engine charge is distinct

Thread one field density through trim, aero, propeller load, wake and telemetry before exposing an atmosphere control. Moist aerodynamic density includes vapor; a naturally aspirated engine's oxygen-bearing charge follows dry partial pressure. Scale indicated torque explicitly and keep friction fixed, while leaving other propulsion laws separate. Preserve the literal reference branch instead of recomputing a nearly identical baseline, and reject a new environment's failed trim rather than flying its previous solution. [Equations and fleet proof](docs/research/atmosphere/M5-ATM-2/README.md).

## 2026-10-09 · G2a/G2b — relative rotor speed couples to body acceleration

With locked aircraft inertia, relative shaft acceleration and body acceleration along the shaft must be solved together. Add relative-spin reaction once over the existing external propeller torque, and use stage RPM for both loads and gyro momentum. Check angular momentum and motor work independently; algebra alone can hide an omitted body-acceleration term. Quantify table-knot crossings separately from smooth RK4 order, and use quaternion chord distance when errors are too small for `acos(dot)`. Continuous wake increments are signed; only the RPM suffix has a nonnegative domain. [Equations, conservation and refinement](docs/research/propulsion/G2a-RK4/README.md).

## 2026-10-09 · G2a-R1 — reuse work inside the RK stage

Coupled equations can need the same expensive loads to obtain forces and continuous derivatives. Return loads, derivatives and spinning momentum together from one pure stage evaluation, then validate the complete payload before consuming it. Keep that result inside the step; a persistent query cache would need every state, command, environment and model dependency in its key. Prove full checkpoint and trajectory bits against the frozen pre-optimization implementation, including sampled RNG and optional wake state. [Exact parity and measured cost](docs/research/propulsion/G2a-R1/README.md).

## 2026-10-10 · Rendering — scene snapshots must retire global progression

A scene-local lighting snapshot must retire any previous global sky progression before updates resume; changing only the Sun and Environment leaves a controller that can overwrite the new scene. Pass the same explicit snapshot to the sky, light and ground, while keeping empty arguments on the legacy route. Test the transition from a flowing world as well as each renderer separately. [Integration proof and limits](docs/research/branch-integration-2026-10-10.md).

## 2026-10-12 · CR-17a — spend a local contact budget at the impact

Splitting fences into visible bays increased the nearby proxy count; selecting the first 160 inventory IDs then omitted the car, trunk or lamp the wreck had just struck. Rank secondary-contact candidates by distance to the actual impact before applying the cap, and verify engine ray queries for the struck obstacle after the inventory grows. [Failure, correction and native checks](docs/research/crash-damage-investigations/CR-17a/README.md).

## 2026-10-12 · TT-11 — seed ground equilibrium from the support plane

A level Newton seed can converge to a two-main-wheel equilibrium for a taildragger even when the authored three-point gear supports the CG. A small residual does not establish the intended resting configuration. Seed height/roll/pitch from the actual contact plane, retain the established nosewheel branch, and require every selected contact to stick before accepting the start. [Timber diagnosis, static support and refinement](docs/research/timber-integration/TT-10/README.md).

## 2026-10-13 · HELI-04 — check crossflow joins as well as axial joins

Johnson's published inflow table contains printed endpoint/derivative errata, and its moving axial polynomials still jump when an entire crossflow branch switches off at C or M. Matching values and slopes inside one slice does not prove continuity across another parameter. Inspect the rendered equations, verify one-sided values with an independent implementation and retain source-law limitations as integration gates; do not silently fit a smoother. Ground-effect activation also needs downstream-wake geometry: signed body-axis thrust alone cannot distinguish upright descent from inverted lift. [Primary-source interpretation and checks](docs/research/helicopter/HELI-04/README.md).

## 2026-10-13 · HELI-05 — isolate rate terms before trusting an oracle

A first transcription put the rotor's body-rate terms inside the angle/lag bracket, turning rad/s into rad/s² while zero-rate fixtures still looked correct. At zero flap, cyclic and translational flow, the source requires `a1dot=-q` and `b1dot=-p` at every active rotor speed. This dimensional known answer caught the reference error before acceptance; a duplicated numerical oracle alone would not. Test terms with distinct units separately, then compare the complete response. [Source equations and independent checks](docs/research/helicopter/HELI-05/README.md).
