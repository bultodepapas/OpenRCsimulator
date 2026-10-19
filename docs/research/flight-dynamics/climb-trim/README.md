# D6e-R1 — reported climb and pilot elevator trim

2026-10-13. **Status: the owner's Ugly Stik loops are captured and reproduced. The controlled campaign below completes 16 diagnostic flights and 126 independent runtime-load comparisons; no tested intervention qualifies as the repair. Real-aircraft fidelity remains unvalidated. Manual trim is implemented and verified. The earlier hands-off Timber climb at 25% throttle remains unreproduced and unresolved.** Main physics/input track; this report does not close a flight-validation gate. The [root-cause review](#root-cause-review-2026-10-13-d6e-r1) separates the correct fixed-elevator mechanism from the borrowed static margin that inflated it; the Stik data now use a geometric neutral point.

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

## Controlled intervention campaign (2026-10-13, D6e-R1)

The owner requested experiments after the literature review. The experimental plan separates numerical/coefficient contracts, elevator force/moment consistency, longitudinal versus lateral departure, and installed propulsion. Each comparison keeps controls explicit; a changed trim or mass is a reported confound. A candidate must complete the requested interval without a fault/contact, preserve the neutral equilibrium, and have a defensible physical cause. Merely delaying inversion or suppressing a physical degree of freedom is not a successful repair. The probes live outside `app/`; no production coefficient or golden reference is changed by this campaign.

### Elevator force/moment interventions

Nine runs compare three models under the owner's first 15 seconds, 30 seconds of calm flight starting at 500 m with the same absolute throttle history followed by full power, and a 30-second hold at each model's own solved equilibrium. All starts are retrimmed normally at 15 m/s. Retrimming changes initial alpha/elevator/RPM; the intervention preserves the **absolute throttle commands**, not just the raw keyboard increments. Elevator remains fixed throughout every run.

| Global elevator derivative candidate | CLde (/rad) | Cmde (/rad) | Initial elevator up | First inversion, captured weather | First inversion, calm 30 s |
| --- | ---: | ---: | ---: | ---: | ---: |
| Current baseline | 0.098300 | -0.848800 | 5.257° | 9.542 s | 9.521 s |
| CLde from the 0.72 m tail arm, preserve Cmde | 0.359325 | -0.848800 | 5.567° | 9.521 s | 9.500 s |
| Both derivatives from the existing local force model | 0.422829 | -1.003028 | 4.712° | 9.521 s | 9.496 s |

The first candidate uses `CLde=-Cmde*c/(tail_x-ARP_x)`, a lift-only small-angle relation. The second takes central finite differences of the existing local model at alpha=0, V=15 m/s, zero rates and elevator ±1e-5 rad, then transports the moment derivative from CG to ARP including the drag-arm term. These are uncalibrated consistency counterfactuals. Whole-aircraft control derivatives can contain wing/tail interactions and intrinsic moments, so an implausible effective arm is a warning to investigate provenance, not proof of an impossible rigid-body force law.

All nine runs complete without crash/fault. Each model's neutral equilibrium holds altitude for 30 s with no reported height drift; the baseline reproduces the recorded checkpoints to 1.42e-14. Source hashes are unchanged during the run, and the elevator change is exactly zero. Both derivative interventions retain the departure and are **rejected as solutions to the captured behavior**. Other static derivatives, local incidence/geometry, rates and propulsion are unchanged. The retained JSON samples commands/flight state every 0.5 s; the executable probe derives and reuses the full 240 Hz throttle history from the retained input fixture. Inversion here remains a body-down reversal, not a 360° pitch-loop detector. [Full measurements, provenance and limitations](model-consistency-interventions.json).

### Independent coefficient and runtime-load oracle

A separate scalar implementation checks seven catalog aircraft at alpha ±3°, elevator -5/0/+5°, and nondimensional pitch rate -0.01/0/+0.01, with `q=qhat*2*V/c`. Its 126 comparisons against the actual `Aero._global_loads` path include FRD force resolution and moment transport from ARP to CG. Maximum absolute discrepancies are 1.78e-15 N in Fx, 1.42e-14 N in Fz and 3.56e-15 N·m in My; all are below 1e-9. Signed elevator drag and finite-difference alpha/elevator/rate responses are recorded. Probe and aerodynamic-source hashes remain unchanged. This rejects the tested sign, rate normalization and reference-transport implementation hypotheses at these attached-flow points; it is not a full-envelope validation.

The global/local elevator mismatch is shared by the three Stik installations, which reuse the same aero data. Extra, P-51, Avanti and Timber have nearly identical global/local elevator lift derivatives and much closer moment derivatives. Thus the observed inconsistency is specific to the Stik data lineage, not a demonstrated fleet-wide bug. [Oracle, comparison cases and exact derivative values](coefficient-contract-experiments.json).

### Longitudinal motion with lateral constraints

Four 30-second calm-air runs at 500 m compare full flight with a research-only planar constraint at every RK stage and accepted endpoint. Production loads and continuous derivatives are evaluated normally; the constrained equations impose zero lateral velocity, roll/yaw and their rates, and `qdot=My/Jyy`. This includes lateral reaction moments: simply discarding lateral rates after an unconstrained rigid-body step would not be the same model. Removing initial lateral velocity and heading is explicit. Neither artificial reaction loads nor the projected integrator are installed in production.

The input events cover the first 15 s, followed by an explicit absolute throttle command of 1.0. The 480 Hz run holds each recorded raw-input event for the corresponding two substeps; the keyboard/propulsion dynamics are refined with the integration, so this is convergence of the sampled system, not a fixed-command RK-order measurement.

| Case | First body inversion | First unwrapped pitch revolution | First unwrapped flight-path revolution |
| --- | ---: | ---: | ---: |
| Full 6-DOF, 240 Hz | 9.521 s | Not defined by this detector | Not defined by this detector |
| Constrained longitudinal, 240 Hz | 9.667 s | 15.0458 s | 15.0125 s |
| Constrained longitudinal, 480 Hz | 9.667 s | 15.0479 s | 15.0125 s |
| Constrained longitudinal, hold solved launch power | None | None | None |

The two powered planar cases reach approximately 3.09 pitch revolutions by 30 s. The neutral control stays below 7.7e-7 revolutions; all cases complete without faults, the elevator stays fixed at 5.25673° up, and the projected constraint residual is zero. Every sampled RK stage remains in the global attached branch. Refining the timestep changes the pitch-revolution crossing by 0.0021 s. The session source hash is unchanged during the run.

Thus lateral departure and the separated-flow model are **not necessary** for this simulated powered rotation. The free airplane's original inversion is still coupled roll/pitch; the ideal planar constraint does not prove it flies a clean vertical loop or that the real aircraft would loop. [Stage audits, validation and trajectories](longitudinal-interventions.json).

### Propulsion substitutions with fixed body state and surfaces

Three calm-air runs start from the same standard-Stik state at 15 m/s and 500 m, retain the same actual elevator and absolute throttle commands, and exchange only the runtime propulsion branch. The first 15 s use the capture; the following 30 s hold its final **50.2083% throttle**, unlike the full-power continuation above. Dry airframe mass/inertia are retained; donor engine/propeller mass changes are excluded. Fuel consumption changes effective mass/CG/inertia in the glow cases, and those changes are measured rather than assumed absent.

| Propulsion experiment | First inversion in 45 s | Outcome |
| --- | ---: | --- |
| Legacy 61FX / APC 12×6 | 9.521 s | Completes; inversion remains |
| 55AX / APC 12×7 transplant | 35.579 s | Completes; delaying inversion is not a solution |
| FS64V / Master Airscrew 14×6 transplant | None | Completes, but the hybrid's native startup trim is rejected |

The FS64V hybrid's trim attempt reports `nonfinite iterated trim residual`. Its exploratory run deliberately seeds the baseline initial condition after preparation checks; it is **not a successfully trimmed or qualified installation**. It gains about 29.45 m over 45 s, stays between 14.64 and 27.93 m/s, consumes fuel and retains positive sampled thrust (about 8.84 N at 45 s). Its engine-running flag is true initially and at every one-second sample, with an empty stop reason. Its non-inversion therefore is not merely an early crash or a powerless glide. All three runs complete with no fault/contact, zero elevator drift and zero absolute throttle-command error; the body initial states match exactly and dependency hashes stay unchanged during the run. The 55AX and FS64V maximum sampled fuel-mass changes are about 17.8 g and 7.84 g. This experiment changes the engine, propeller, torque/RPM law and transient response together; it does not isolate one faulty parameter or validate the standard 61FX installation. [Exact inputs, engine state, mass effects and limitations](powertrain-interventions.json).

**Selection:** none of the tested changes qualifies for promotion as the repair. The FS64V response is the most promising behavioral counterexample, but changing to a different engine/propeller and bypassing a failed startup equilibrium cannot establish the correct behavior of the reported airplane. The strongest remaining calibration target is the standard Stik's coupled installed propulsion, trim and speed response. The coefficient edits do not remedy the capture; the planar test rejects lateral motion as a necessary trigger; the independent runtime oracle finds no tested shared sign/normalization/reference bug. The separate Timber low-power report remains unresolved. These research results preserve a reproducible way to evaluate a future physically sourced correction without installing a throttle limiter, extra damping or automatic trim.

The four probes execute with pinned native Windows Godot 4.7.2. Their scope is this diagnostic campaign in a concurrently edited checkout, not a clean release or physical flight qualification. The campaign changes only research scripts, their evidence and these two documentation homes. It does not modify production physics/data or re-record golden flights; the full application/WSL suite was not rerun for these research-only additions.

## Root-cause review (2026-10-13, D6e-R1)

**Mechanism.** With the launch elevator fixed, the pitch-moment balance holds α at 4.261° at every throttle, so lift equals weight only near the trimmed 15 m/s. Throttle changes the climb angle, not the level speed: 0 % gives −9.0°, 28.3 % level, 50 % +15.4°, 75 % +43.0°, and from about 85 % there is no straight steady flight. An independent 3-DOF reimplementation reproduces [fixed-trim-power-equilibrium.json](fixed-trim-power-equilibrium.json) to within 0.1°. This is ordinary rigid-airplane behavior ([AOPA: trimmed at 100 kt, more power climbs at 100 kt](https://www.aopa.org/news-and-media/all-news/2010/october/flight-training-magazine/technique)), not a solver defect. For a drag-free constant-CL path, a bottom speed above √3 times trim speed (26.0 m/s here) loops; the capture passes 31–39 m/s.

**One input error inflates it; a suspected second one does not.**

1. **Propeller table: not a cause.** The UIUC APC 11×6 coefficients stand in for the named 12×6. At the same 11149 rpm, [APC's 12×6 data](apc12x6-comparison.json) give 0.71× the thrust at J = 0.40 and 0.54× at J = 0.571, but also 23 % less shaft power. The repository's own rule derives `max_rpm_static` from the engine/propeller static power balance; with the 12×6 Cp it gives about 12650 rpm. With that consistent rpm the 50 % climb is 15.4°, as now, and steady flight ends at 75 % instead of 85 %. The earlier fixed-rpm comparison in this section mistook a power reduction for a propeller error.
2. **Borrowed static margin.** Placing the borrowed `Cma` at the plan CG ([DECISIONS 2026-10-05](../../../DECISIONS.md)) gives 18.9 % margin at the CG in the runtime loads, including the 7 cm ARP height. The Stik's own wing and stabilizer put the neutral point at 43–47 % chord in a vortex lattice before fuselage and propeller corrections, so 4–8 % at the 39.4 % plan CG. The donor margin implies a neutral point at 55 % chord, which this tail (volume 0.486) cannot produce. Trim at 15 m/s then needs 5.26° up elevator instead of about 1.4°.

| Simulator counterfactual, normal 15 m/s start | Level throttle | Calm step to 75 %: first inversion / max q | Calm step to 100 % | Owner inputs replayed |
| --- | ---: | ---: | ---: | ---: |
| Data before the correction | 28.4 % | 7.25 s / 0.81 rad/s | 5.70 s / 1.03 rad/s | 9.54 s / 1.18 rad/s |
| APC 12×6 table at 11149 rpm (less power) | 35.0 % | none / 0.65 | 6.38 s / 0.94 | 10.39 s / 0.91 |
| Geometric 6 % margin | 28.2 % | none / 0.40 | 7.93 s / 0.52 | 11.67 s / 0.53 |
| Both | 34.8 % | none / 0.34 | 19.75 s / 0.46 | 12.85 s / 0.43 |

With the geometric margin the replayed owner inputs end at ground contact (43.9 s, and 44.6 s with both changes): 48 % throttle is then barely above level power while the aircraft is banked. The run used a disposable checkout of `c64e0d9f` with the unrelated indentation error at `app/physics/aircraft_contact_contract.gd:81` fixed only in that copy. The margin variant moves only `aero_reference_point`, so global and local regimes move together; directional derivatives follow the loader's fin-arm rule. Full throttle still inverts eventually because static-slice thrust exceeds weight below about 14 m/s even with the APC table; that is expected for a fixed up-elevator. [Variant data](root-cause-variants.json), [tools](../../../../research/flight-dynamics/climb-trim/README.md#root-cause-review-tools).

**Roll couples into the loops.** Propeller reaction torque rises from 0.13 N·m at 28 % to 0.80 N·m at 100 % against the aileron trim solved at 28 %, and this aircraft has no slipstream-swirl model. In the current-data 100 % step the bank reaches −53° at 5 s and −127° at 7 s, so most "inversions" are rolled pull-ups, not clean loops. This needs its own torque/slipstream review.

**Also found.** The 0.284 kg virtual balancing mass sits at the tail; without it the inventory CG is at 13.5 % chord. It supplies 39 % of `Jyy` and a lateral product of inertia. With the borrowed `Cm0`, a centered elevator trims at CL −0.069, so no upright level flight exists at any speed. The plan shows F1 square to the keel and the wing about +0.5° to it; zero modeled downthrust matches the plan.

**Rejected.** The geometric margin alone does not remove full-power loops in the longitudinal model, so it is not the climb's sole cause. The propeller table is not a cause once rpm follows the power balance. Wind, gyroscopic coupling, integration, energy, sign conventions and the separated-flow model were already excluded above.

**Implemented correction.** `derive_pitch_reference.py` estimates the Stik's neutral point with the fleet generators' method: Helmbold slopes, tail dynamic-pressure ratio 0.9 and Raymer's fuselage term. It lands at 43.5 % c, within a 42.5–44.5 % band; the vortex lattice gives 44.4 %. The source now places the ARP at x = 0.0844 m, so the borrowed derivatives' neutral point lands there. Values defined about the ARP were regenerated: `Cnb`/`Cndr` by the loader's fin-arm rule, and `Cmq −7.944`, `CLq 1.977`, `Cnr −0.1354` by D11g, now ARP-referred. The local tail incidence of 0.02205 rad comes from `derive_tail_incidence.gd`, so neither regime steps at the start trim. D11g and the incidence solve were iterated to a common fixed point. The glow variants and Workshop descriptors were regenerated and the four golden flights re-recorded. The synthetic electric fixtures are not catalog aircraft and keep the earlier reference.

| Production data, normal 15 m/s start | Before | After |
| --- | ---: | ---: |
| Static margin at the CG (runtime loads) | 18.9 % | 6.9 % |
| Trim elevator / level throttle | 5.26° up / 28.4 % | 1.63° up / 28.2 % |
| Short period ωn, ζ; phugoid ωn, ζ | 8.30 rad/s, 0.65; 0.734 rad/s, 0.20 | 6.58 rad/s, 0.83; 0.564 rad/s, 0.28 |
| Calm step to 50 %: max pitch / max q | 23.5° / 0.46 rad/s | 18.5° / 0.26 rad/s |
| Calm step to 75 % | inverts at 7.25 s, max pitch 59° | no inversion, max pitch 31° |
| Calm step to 100 % | inverts at 5.70 s, max q 1.03 rad/s | inverts at 7.71 s, max q 0.55 rad/s |
| Owner inputs replayed | inverts at 9.54 s, max pitch 89°, max q 1.18 | inverts at 11.48 s, max pitch 43°, max q 0.53 |

[Correction data](root-cause-correction.json). Full throttle can still invert: below about 14 m/s thrust exceeds weight with any fixed up-elevator, and the torque roll above remains open. Regime consistency passes for the Stik family. Checks that assumed the ARP at the CG, or pinned the old behavior, were updated and explained in place:

- `test_aero`: the hand-computed transfer now uses the full ARP arm.
- `test_damping_regimes`, `test_yaw_damping`: the data's rate and fin derivatives are moved to the CG before comparison. The oracle then matches the local model to 0.01 %.
- `test_tail_downwash`: the moment band is a coefficient, 0.003, not a ratio to a total that now nearly cancels.
- `test_ground_effect`: the 0.02 N drag increment may also agree within 1 % of free-air drag.
- `test_half_power_start`: proves the density re-solve by the trim α, because the speed barely moves near minimum-drag CL.
- `test_takeoff_roll`: the hands-off roll is longer with less trim elevator. A new check holds lift-off within 2 % of the integral driven by the actual pitch (0.6 %); the fixed-attitude band is 12 %.
- `test_modes`: bands were re-recorded. The 15 and 25 m/s short period is now just overdamped (ζ 1.04/1.11), so the sanity ceiling is 1.25.

The D8b-R2 synthetic polar candidates were regenerated. They were also stale from the identity migration.

On the native Windows working tree, 139 flight-related GDScript tests ran. All pass except unrelated or pre-existing failures:

- `test_pilot_trim`, glow live-neutral: fails on `HEAD` too.
- `test_turbulence_flight`: fails on `HEAD` too.
- `xcell-60-research` loading: another track's in-progress data.
- Failure-route UI layout, runway lighting and wash-transport layout: other tracks' uncommitted changes.
- `test_ui_aircraft`: timed out on the loaded host.

The aircraft-contract, descriptor, migration, glow and candidate freshness checks pass. The trace and pull-up CLI Python tests time out launching the full app on this Windows host, including for invalid arguments; they were not qualified here. The full WSL `app/test.sh` was not run. No automatic trim, power limit or artificial nose-down moment was added.

**Open.** Measure the built CG, neutral point and inertia, then replace the virtual tail mass with a balanced inventory. Review torque roll with a slipstream-swirl model. A full Stik coefficient generator would replace the remaining borrowed derivatives.

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
