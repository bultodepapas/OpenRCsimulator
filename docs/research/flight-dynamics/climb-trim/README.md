# D6e-R1 — reported climb and pilot elevator trim

2026-10-13. **Status: the owner's Ugly Stik loops are captured, reproduced and internally explained; real-aircraft fidelity remains unvalidated. Manual trim is implemented and verified. The earlier hands-off Timber climb at 25% throttle remains unreproduced and unresolved.** Main physics/input track; this report does not close a flight-validation gate.

The owner reports a common tendency to climb, especially Timber at low power with keyboard controls and no elevator input; the Stik feels incorrectly trimmed. The initial power-step hypothesis alone does **not** explain that report. The owner confirmed running this repository on Windows. A later actual Stik flight establishes its airborne launch and control history below; it does not establish the history of the original Timber report.

## Evidence

Production `FlightSession`, real servos/propulsion/downwash and RK4 at 240 Hz, normal input rates. Five catalog aircraft, four conditions each, ten simulated seconds. Neutral keyboard samples are applied before each tick. [Reproducible probes](../../../../research/flight-dynamics/climb-trim/README.md), [numerical summaries](results.json).

All five maintain starting altitude within 2e-9 m in calm air at solved power. Their solved powers are different: Stik 28.44%, Extra 35.72%, P-51 14.05%, jet 8.60%, Timber 40.94%. A common throttle percentage is not a common equilibrium.

| Condition, 10 seconds | Stik altitude change | Timber altitude change |
| --- | ---: | ---: |
| Calm, starting power | 0.000 m | −0.000 m |
| Calm, 25% throttle | −4.574 m | −11.439 m |
| Gentle weather, 25% throttle | −4.678 m | −11.914 m |
| Calm, 50% throttle | +9.330 m | +10.273 m |

The complete `main.tscn` scene, field, soft contacts, gentle weather, **real keyboard polling and engine physics callbacks** reproduce the 25% descent values exactly. Recorded commands remain neutral plus the solved trim, with `cmd_throttle=0.25`. This rules out a startup climb in those tested current-source conditions; it does not invalidate the owner's observation of another flight.

A further **native Windows Home-to-Fly run**, with rendering on the RTX 3090 and the player's gentle-weather preferences copied to an isolated diagnostic file, also failed to reproduce the climb. In about ten simulated seconds, Timber at 25% lost 11.795 m and Stik lost 4.623 m; Timber at its solved starting power lost 0.400 m in gusts. Timber at 25% on the runway stayed on the ground. Raw pitch/roll/yaw inputs remained zero. The native HUD capture showed negative vertical speed. The recorder attaches a few ticks after Home launches, so these deltas do not start at tick zero. [Native summaries and trace hashes](native-windows.json); reproduce using `native_probe.gd`. The shared checkout changed concurrently; this is measured working-tree evidence, not a clean release qualification. This run also emitted ObjectDB/resource cleanup warnings at exit.

`Trim._evaluate` and the runtime share `Dynamics`; pilot trailing-edge-up angles are converted once to the aerodynamic convention. No common elevator sign or gravity defect was found. A nose-up attitude is distinct from a rising flight path: the level starts have approximately 4.3° pitch/angle of attack. No camera-perception explanation has been established for the report.

## Owner follow-up

The owner subsequently reported substantial improvement ("MEJOR BASTANTE") while using the observed native session. [Actual-flight segment summary](user-flight-summary.json) records the first fourteen completed segment slots, including hashes. This is user feedback, not a controlled before/after comparison or proof of the original cause. Elevator trim stayed at 0.145223519557 throughout these segments, so the improvement cannot be attributed to operating the new manual trim keys in this captured flight.

The flight includes control/power changes, resets and crashes. A hands-off interval at 37.08% power rose from 7.97 m to a 22.45 m peak, then descended to 15.92 m; its initial airspeed was 20.07 m/s after earlier inputs, compared with the 13.1 m/s starting trim. A subsequent hands-off segment ended at 14.81 m. Such recovery and oscillation are consistent with exchanging speed and height after a disturbance; this is an interpretation, not measured validation of the model's damping or an explanation established for the original neutral-start report. Two flight segments (002 and 007) were rejected by the trace validator with `ERR_INVALID_DATA`; their raw-input files remain, but missing flight data must not be inferred.

## Ugly Stik capture and adversarial audit

The owner's second recording is the standard `jensen-das-ugly-stik-60`, not the experimental glow variants. Eleven contiguous segments cover ticks 1–11782 (49.092 seconds). **Raw pitch is zero throughout.** The commanded and actual servo pitch remain 0.262836485: the launch solver's fixed **5.257° trailing-edge-up elevator**, not a physically centered elevator. Power falls from 28.44% to zero, rises to 100% at 6.708 s, and changes again later. The first inverted attitude occurs at 9.542 s. These are recorded facts, not assumptions about how the owner flew. [Capture summary](ugly-observed.json), [control and motion plot](ugly-observed.png).

The compact input fixture reproduces all recorded state checkpoints with maximum absolute component error **1.42e-14**. It is a diagnostic fixture, not a golden flight requiring future models to retain this behavior. Three independent adversarial reviews examined load/sign conventions and static stability, numerical energy/integration, and real airframe/engine/propeller evidence. [Replay and counterfactual results](ugly-loop-replay.json).

| Hypothesis or intervention | Result | Scope |
| --- | --- | --- |
| Hidden elevator input | Raw pitch remains zero; actual elevator stays at launch trim | Rules out pilot pitch input in this capture |
| Wind creates the loops | Calm replay still spends 9.78 s inverted | Wind is not necessary |
| Rotor gyroscopic coupling creates the loops | Removing rotor inertia still produces inversion | Gyroscopic coupling is not necessary |
| Launch elevator carried into a faster flight | Changing only elevator trim at 5 s from 5.257° to 2.340° removes inversion before ground contact at 45.28 s | Strong sensitivity, not validated handling or a safe full-flight solution |
| Borrowed propeller curve creates the first loop | Both APC 12x6 curve counterfactuals still invert at 9.51–10.45 s | First inversion precedes curve extrapolation; neither is a calibrated installed powertrain |
| Numerical energy/sign defect | Energy closure and timestep checks below show no such defect in loop onset | Does not establish physical parameter accuracy |

At 8 s, the replay has airspeed 24.73 m/s, angle of attack 2.773°, and lift 57.16 N against weight 28.29 N: about **2.02 times weight**. This lift curves the flight path upward; a positive pitch acceleration is not required throughout a loop. The body pitch rate is already +0.493 rad/s while total pitch moment is −0.0557 N·m. Independent force projection predicts ground-flight-path angular rate 0.4839 rad/s versus 0.4827 rad/s from recorded motion. The initial loop uses the attached global aerodynamic model (`blend=0`), so the local stall model is not its trigger. Component reconstruction must include the sampled downwash lag and align tick-k states with the next tick's recorded k1 loads.

### Energy and numerical checks

The independent audit compares body translational, rotational and gravitational energy change with trapezoidal load work, including the sampled downwash state. Over the first 15 s, the actual replay's accumulated closure residual is **−0.00259 J**, summed absolute per-step residual 0.01148 J, and maximum step residual 5.66e-5 J. The independent review found no positive aerodynamic-power endpoint among those 3600 steps; aerodynamic work totals approximately −3233 J. This is evidence against artificial aerodynamic energy injection in this interval, not a global passivity proof.

In calm air, doubling the rate from 240 to 480 Hz reduces cumulative closure residual from −0.000454 J to −0.000102 J. At whole-second checkpoints, maximum differences are 0.0792 m per position component, 0.0212 m/s in airspeed and 0.000541 rad/s in pitch rate. No frame, quaternion, inertia, moment-transfer or integration defect was found that explains the first loop. Modes (42 checks) and rigid-body (15 checks) tests pass. [Energy results](ugly-energy-audit.json); `energy_probe.gd` reproduces the independent work calculation. These checks verify software consistency, not real-aircraft flight behavior.

### Real-aircraft and model limitations

**Motor installation.** The model puts the thrust line through the CG, with a 0.414 m forward offset, zero vertical/lateral offset and no thrust angle. Consequently thrust has zero direct pitch moment by construction. Propeller reaction torque is primarily a roll-axis effect; it cannot simply be relabeled as pitch torque. The [Jensen plan record](https://outerzone.co.uk/plan_details.asp?ID=1253) and [O.S. engine manual](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/manual/50sx_40-91fx.pdf) do not establish the installed thrust-line height relative to the actual CG or a measured downthrust angle for this modeled build. Inventing those values would be another tuning patch.

**Propeller and engine.** The standard model names an APC 12x6 but uses borrowed UIUC 11x6 coefficients. [APC now supplies 12x6 performance data](https://www.apcprop.com/files/PER3_12x6.dat), computed from propeller geometry, **not wind-tunnel measurements** ([manufacturer's method](https://www.apcprop.com/technical-information/performance-data/)). At the same 11149 RPM and 25 m/s, the existing curve predicts about 24.33 N versus 16.85 N with APC's curve. Keeping RPM fixed is not a complete engine/propeller replacement: a constant-torque estimate using repository power instead predicts roughly 12648 RPM at static balance. Both bounded map experiments retain the first loop. Their single-RPM slices, legacy RPM-lag law and late extrapolation prevent treating them as physically calibrated replacements. [Curve provenance and comparison](apc12x6-comparison.json).

**Pitch stability.** `Cm0=-0.0278`, `Cma=-0.723/rad` and `Cmde=-0.8488/rad` are borrowed from the Ultra Stick 25e model. Putting the aerodynamic reference point at the Jensen plan CG defines where that surrogate whole-aircraft moment acts; it does not validate the target's static margin. The pinned donor has AERORP x=0.2175 m and configured CG x=0.222 m with chord 0.25 m ([metrics](https://raw.githubusercontent.com/UASLab/OpenFlightSim/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/MetricsOpenFlight.xml), [mass](https://raw.githubusercontent.com/UASLab/OpenFlightSim/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/MassOpenFlight.xml), [aerodynamics](https://raw.githubusercontent.com/UASLab/OpenFlightSim/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/AeroOpenFlight.xml)). With structural X positive aft, transferring that slope to the donor's configured CG adds approximately +0.082/rad, giving about −0.641/rad. This is a model-derived reference correction, not a measured static margin. The donor files do not establish a wing-leading-edge datum, and its generator marks mass-property sourcing unresolved; no donor CG chord fraction may be inferred from those absolute coordinates. [Frame convention](https://jsbsim-team.github.io/jsbsim-reference-manual/user/concepts/frames-of-reference/), [donor generator](https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Utilities/UltraStick25e.py).

A rough target geometry estimate with a quarter-chord wing aerodynamic center yields wing `Cma` about +0.67 and estimated tail contribution −0.85, hence net roughly −0.18/rad rather than −0.723. This is a warning about coefficient transfer, **not a replacement coefficient**: varying the assumed wing center from 20% to 30% chord alone changes the net estimate from about +0.05 to −0.41/rad, before tail/downwash/fuselage uncertainty. The local wing strips also sit on the reference line at the CG; that known simplification is documented in `test_regime_consistency.gd`. Its agreement with the global model is not independent geometric validation. Adding a quarter-chord wing moment without recalibrating the effective tail would break the existing model's consistency and would not address the attached-model first loop.

### Decision after the audit

The captured loop has an internally consistent mechanism: **fixed launch elevator trim, increasing power/speed, and the model's resulting lift and pitch response**. The data do not justify saying that the real Jensen should perform this maneuver, or that manual trim fixes the aircraft model. Keep runtime physics and generated aircraft data unchanged during this audit. Do not suppress the symptom with automatic nose-down correction, arbitrary downthrust, a higher launch speed, or an unsupported `Cma` change.

The robust next correction must calibrate the aircraft as a coupled system: establish the target build's CG and thrust line, use the matching propeller map with an evidenced engine torque/RPM model, then constrain trim/elevator and pitch response at multiple airspeeds using flight measurements or an independently validated aerodynamic model. Change the source generator and verify both attached and separated-regime consistency, trim, dynamic response and replay behavior. Current evidence is sufficient to reproduce and investigate the defect report; it is insufficient to select physically validated numerical replacements. The original Timber low-power report remains a separate unresolved observation.

## Follow-up: explicit half-throttle airborne operating point

After the adversarial audit, the owner requested an actionable next step. Home now offers **Start: in the air at 50% throttle** for the standard Stik as a separate choice. It does not replace the existing airborne/runway defaults or prescribe a manufacturer cruise setting. `cruise_trim.gd` searches a bounded increasing-speed branch using the existing six-axis trim solver; it refuses failed, nonfinite, excessive-angle or unbracketed solutions. No runtime aerodynamic/propulsion parameters or generated aircraft data change. No trim changes automatically during flight.

At reference atmosphere, the selected operating point is **20.56138 m/s, throttle 0.500000006, elevator 2.69422° up**, with six-axis residual about 1.34e-14. The old launch remains 15 m/s and 5.25673° up. The new setting holds altitude within 1 mm for ten seconds in calm air, responds naturally to power increases, and descends at quarter throttle. Reset, reload and an atmosphere change retain the selected power condition; unavailable equilibria refuse launch. Trace metadata records the selected profile separately from the actual airborne launch. This is a physically consistent initialization choice, **not a correction of the aircraft's uncertain coefficients**.

The required counterexample remains: replaying the owner's keyboard sequence with the new initial condition still produces inversion. [Complete comparison](half-power-start.json):

| Start/input case | Duration | First inverted attitude | Result |
| --- | ---: | ---: | --- |
| Original start, recorded keyboard sequence | 49.092 s | 9.542 s | Exact baseline reproduction |
| Half-throttle start, recorded keyboard sequence | 45.458 s | 13.567 s | Inversion remains; ends at ground contact |
| Half-throttle start, hold starting power | 49.092 s | None | No crash; gentle-weather altitude peaks at 32.390 m from 30 m |
| Half-throttle start, hold quarter power | 7.825 s | None | Descends to ground contact |
| Half-throttle start, hold full power | 49.092 s | 6.958 s | Inversion remains |

The replay comparison changes initial speed, all solved trims and starting throttle. The recorded case repeats **raw keyboard events**, not an identical absolute throttle history. These results do not justify calling the new option a loop fix. It gives the owner a defined operating point and a controlled comparison while physical qualification remains open.

Verification: 22 power-trim helper checks; 14 selected-start checks covering equilibrium, fixed trim, restart, reload, atmosphere, late profile selection and unsupported-aircraft refusal; 36 existing start-choice checks; 92 checkpoint checks; unchanged observer checkpoint parity. The final real Home/Fly test passes all 87 checks, including the new selection, persistence, launch, restart and unsupported-aircraft checks. A stale process first encountered a concurrently changed scenery catalog; a fresh run resolved that error. The test now navigates to End by its focus identity rather than a fixed number of rows, and verifies that a field without runway support still allows both airborne choices. Existing UI teardown ObjectDB warnings remain. The fleet pilot-trim run passed the original aircraft but failed its exact ten-second equilibrium assertion for both newly added finite-fuel glow variants; that run is not a passing full-fleet qualification. Full WSL suite was not run. [Focused verification record](half-power-verification.json).

## Shared-code audit and tail-selector correction (2026-10-13)

The owner rejected the start-profile change as a diagnosis and requested a deeper shared-code investigation. Three adversarial reviews covered aerodynamic loads/regime selection, rigid-body/integration/propulsion state, and Godot/input/lifecycle. This pass keeps aircraft parameters and generated data unchanged.

**Confirmed defect:** `Aero.loads` supplied lagged wing CL and ground-effect factors to the force laws, but omitted them from `local_flow_weight`. The selector consequently assessed a different horizontal-tail flow from the one producing the force. Its documented attached-flow limit is 8°, with transition completed at 12° for the Stik fixture. Two bounded prescribed-flow counterexamples isolate the missing inputs:

| Case | Tail angle used by old selector | Tail angle used by force law | Required local-model weight |
| --- | ---: | ---: | ---: |
| 15 m/s, alpha ramp 7.8° to 0° over 11 ticks, elevator 12.605° up, settled initial downwash | −6.839° | −9.086° | 0.18097 instead of 0 |
| Ground height/span 0.05, alpha 7.8°, neutral elevator | 5.432° | 8.600° | Nonzero instead of 0 |

These are selector-contract failures, not evidence of a naturally flown maneuver or tail stall at 12°. The correction passes the same downwash state and ground factors into the selector and uses the same horizontal-tail angle law. Calls omitting both retain the existing static trim policy. No extra pitching moment, automatic elevator, CG adjustment or new aircraft coefficient is introduced. The focused downwash and ground-effect tests cover the counterexamples and force-path wiring.

Other independent checks:

- Seven flyable aircraft, 400 seeded synthetic states each: quaternion-sign, common heading/wind rotation, common aircraft/wind velocity offset and stage-air reuse. Explicit downwash and ground queries are included. Maximum scaled discrepancy is 1.18e-13; sign and stage-air comparisons are exact. [Results](shared-code-invariants.json).
- 1,000 rigid-body coordinate-basis changes, transforming inertia and rotor momentum too: maximum derivative residual 2.28e-13; angular power-identity residual 9.95e-14.
- Five propulsion configurations, 0.5 s throttle transients at 120/240/480/960 Hz: all complete without faults and RPM mirrors match exactly. Body endpoint discrepancies decrease with refinement. The battery 4S RPM error is slightly nonmonotonic at tiny absolute errors; no blanket RK4-order claim is made for the coupled sampled system.
- Actual SceneTree callbacks at 15/30/60/144 FPS produce the same serialized state after 240 ticks and the same 0.1 throttle increase over 48 keyboard callbacks. At 15 FPS wall time stretches as expected from the 12-step catch-up cap. Focus-loss and radio-recovery tests pass; injecting a new key after directly invoking only the Simulation focus notification was rejected as an invalid reproduction of the real application path.
- Rigid-body (15), integrator (9), RK-stage-time (22), continuous-state (42), coupled-shaft (43), turbine-continuous (46), electric event-localization (2,946), glow-session (132), input-latency (533), UI-pause (33) and radio E2E (40) checks pass. After the selector correction, checkpoint checks (92) and all four existing golden flights also pass. Golden references were not re-recorded.

Focused correction checks pass: downwash lag 20/20, ground effect 50/50, tail downwash 8/8, aero 23/23, and 35,001 aero-flow/parity comparisons. An independent mechanical-power probe finds no positive-power cases in 28,000 local force-only samples (intrinsic wing pitching moment disabled to isolate force work), nor in 28,000 isolated global rate increments. This is a check of the dissipative terms, not a claim that every possible aerodynamic moment must dissipate energy.

**The recorded first loop is unchanged by this fix.** The complete 49.092 s replay still first inverts at 9.541667 s, spends 9.2875 s inverted, reaches 87.2346 m and maximum absolute pitch rate 1.180776 rad/s. Its recorded checkpoints match to 1.42e-14. The selector remains in attached flow around the first inversion. Thus the corrected defect is not the demonstrated cause of that loop, and the low-power Timber observation remains unresolved. [Post-fix audit and replay measurements](shared-code-audit.json). The half-power start must not be described as a remedy for either report.

The coordinate/force review used the [JSBSim frame definitions](https://jsbsim-team.github.io/jsbsim-reference-manual/user/concepts/frames-of-reference/) and [force/moment implementation](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGAerodynamics.html). The tail-flow review used [NASA-CR-2774](https://ntrs.nasa.gov/citations/19770013083), which discusses predicting the flow reaching the horizontal tail; it supplies no new Stik coefficients. Godot's [callback priorities](https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-property-process-physics-priority), [fixed-tick/catch-up contract](https://docs.godotengine.org/en/stable/classes/class_engine.html#class-engine-property-max-physics-steps-per-frame) and [packed-array reference semantics](https://docs.godotengine.org/en/stable/classes/class_packedfloat64array.html) informed the engine-boundary checks. Flight remains the custom float64 solver, not Godot's rigid-body solver.

These are native Windows software checks in a concurrently edited checkout. Full WSL qualification and physical validation were not performed. Some scene teardown checks emit existing ObjectDB leak warnings; they are not treated as a cause of pitch motion.

## Physical causality follow-up (2026-10-13)

Three further reviews challenged the longitudinal equilibrium, coefficient transfer, and startup branch. The startup roots of all seven current aircraft are attached (`blend=0`), at alpha 1.50–5.38°, below the 8° attached-flow limit. The standard Stik starts at 1.58 times its model-estimated stall speed. Its root is not a hidden post-stall solution, and no duplicate trim/sign conversion was found. These checks do not validate the chosen physical airspeeds or elevator angles.

**Steady-flight existence is distinct from stability.** With launch surfaces fixed, zero body rates/sideslip and settled downwash, projected longitudinal equilibrium requires both `My=0` and `sqrt(Fx²+Fz²)=mg`, where the forces exclude gravity. Pitch attitude comes from the force direction and flight-path angle is attitude minus alpha. The retained probe enumerates pitch-moment sign roots in −8° to +8° and scans speeds 1–60 m/s. One attached root occurs at alpha 4.260299°; checks at 5, 9, 15, 24.728 and 40 m/s confirm zero local blend and pitch-moment residual below 1.7e-15 N·m.

| Fixed launch elevator; power | Upper-speed projected equilibrium | Climb angle |
| --- | ---: | ---: |
| Launch, 28.44% | 15.000 m/s | Approximately 0° |
| 50% | 14.581 m/s | 15.31° |
| 75% | 12.381 m/s | 42.94° |
| 85% and 100% | None in the analyzed branch/range | — |

At full power, the minimum resultant-force magnitude still exceeds the 28.293 N weight by **8.825 N**, at 9.071 m/s. The last force-root threshold is approximately 83.05% throttle, at an already very steep 69.60° climb. This is a property of this model and fixed surface setting, not a proposed throttle limit. It shows why assuming the model must settle into a straight climb at full power is unjustified. It does not prove that a loop is inevitable; banked, unsteady and separated-flow motions are outside this equilibrium calculation. Lateral/roll/yaw balance is not solved. [Equilibrium measurements](fixed-trim-power-equilibrium.json).

**The transient supplies the causal evidence.** Replaying the first 15 s while bounding only the absolute throttle command at 100%, 85%, 75% and 50% gives first inverted attitudes at 9.542, 10.079, 10.708 s and none, respectively; all four complete the interval without contact/fault. The 75% result matters: existence of a steady climb does not ensure that this transient reaches it. This experiment supports the power/trim interaction, but a 15-second non-inversion is not a handling qualification or a reason to install a limiter. The unchanged baseline matches the capture to 1.42e-14. [Power interventions and pitch-moment terms](pitch-causality.json).

At 8 s the accepted endpoint's attached pitch-moment terms are, in N·m: zero-angle −1.474, alpha −1.856, elevator +4.130, pitch-rate damping −1.205, force-arm +0.364, downwash −0.0166, and direct propulsion 0. Their total is −0.0578 N·m while body pitch rate remains +0.493 rad/s. Full component closure is within 2.45e-15 N·m. This endpoint differs slightly from the earlier next-tick k1 load sample; both are temporally identified. The previously measured lift/trajectory curvature explains continued upward rotation even while pitch acceleration is negative. Inversion is coupled roll/pitch, not a pure 360° pitch-loop detector: at 9 s the recorded Euler bank is −51.5° and pitch +60.0°; at 10 s they are −117.1° and +51.3°.

**A data-transfer inconsistency survives review, but not as the first-loop explanation.** The target's assertion that moving the borrowed moments to its CG preserves donor static margin omits the donor's 1.8%-chord AERORP-to-CG separation. An approximate three-coefficient transfer gives `Cm0=−0.0258776`, `Cma=−0.64056`, `Cmde=−0.8470306`. Recomputing startup trim with those values reduces elevator-up from 5.257° to 4.715°, but first inversion moves only from 9.542 to 9.654 s and remains. This is a bounded sensitivity study, not a complete transport or a calibrated production replacement: nonlinear force projection, other derivatives and local-tail incidence are not rederived. [Counterfactual measurements](donor-reference-sensitivity.json).

Separately, using the whole-aircraft coefficient reference as the local wing force location conflates two different concepts. Here it puts wing lift through the CG. The estimated local horizontal tail also predicts `CLde≈0.423/rad` versus the global donor's `0.0983/rad`, while `Cmde` differs much less. These are model-construction consistency issues requiring explicit reference geometry and joint force/moment qualification. The recorded first inversion remains in the global model, so neither local mismatch is its trigger.

The diagnosis established for the capture is a powered, fixed-trim transient with excess lift and coupled attitude motion. There is no evidence here that Godot or the integrator invents the climb, and no demonstrated shared defect explaining all reported low-power climbs. Realistic severity remains unqualified because the target's aerodynamic and installed powertrain data are surrogates. Source reference transport and cross-regime force/moment consistency should be corrected in their generators as explicit model work, then checked against independent trim and response evidence. No production coefficient, automatic trim or power limiter was introduced in this follow-up. The [NASA throttles-only flight-control study](https://ntrs.nasa.gov/citations/19950026600) supports the general coupling of thrust, speed and pitch dynamics; it supplies no coefficients or handling validation for this RC airplane.

## Options and chosen improvement

- Reducing lift, changing CG/incidence or adding a universal nose-down moment has no supporting reproduction and would disturb the verified equilibrium. Rejected.
- Automatic altitude hold or continuously adapting trim would change manual RC flight into an assisted mode. Rejected for this repair.
- A pilot-controlled fixed elevator trim addresses a confirmed usability gap: the old session solved trim at launch but offered no keyboard adjustment for another operating point. Implemented independently of the unresolved report.

Page Up trims nose down; Page Down trims nose up, 0.1° per fresh key press. The command offset is independent of rates/expo and bounded by the aircraft's physical throw. Existing servos apply it on the next sampled ticks. The operation changes no state, force, throttle or aerodynamic coefficient. Invalid, paused, held, crashed, calibration and recorded-input sessions refuse it. Reset restores solved trims and initial servo positions. Existing trace commands/servo columns and recorded-input checkpoints already capture its physical effect; no new replay format is introduced.

At a controlled 40 m/s jet initial condition, preserving its old 29 m/s elevator trim gains 46.519 m in five seconds; applying the solved faster-cruise correction through the new trim API holds height within 1 mm. This counterfactual verifies the new trim path, not a fix for the Timber report or real-aircraft fidelity.

Power, elevator and trim interact with speed and flight path; the chosen separation follows the [FAA Airplane Flying Handbook, chapter 4](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/05_afh_ch4.pdf). Actual RC coefficient and handling qualification remains separate.

## Verification and remaining diagnosis

Native Windows, pinned Godot 4.7.2: `test_pilot_trim.gd` (68 checks), trim (14), trim integrity (700), regime consistency (50), rates (21), session guards (32), runway start (19), controls-reference, Help EN/ES and real key-event tests pass. Help still fits the 600 px content region at 720p in both languages. Checkpoint (92), replay-integrity (153), density-trim (35) and electric-session (86) checks also pass. The full Bash/WSL suite and physical pilot validation were not run. Existing UI teardown ObjectDB warnings remain.

No aircraft data or golden-flight references were changed. Other tracks modified/committed the shared checkout during this work; test evidence is scoped to the listed runs, not to a clean-tree release.

To resolve the original symptom, capture the actual climb with aircraft, launch choice and controls unchanged. The read-only `watch.gd` diagnostic opens normal Home and automatically saves independent flight and raw-input segments; the normal **T** recorder is also available. Its test verifies exact physics checkpoint equality against an unobserved session, including reset. Compare raw inputs, `cmd_pitch`, `srv_pitch`, throttle, RPM, airspeed, vertical velocity, weather and initial-state identity. A current-source low-power descent is insufficient evidence to declare the reported climb fixed.
