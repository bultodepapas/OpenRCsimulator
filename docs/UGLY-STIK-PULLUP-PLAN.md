# Ugly Stik high-speed pull-up: diagnosis and repair plan

2026-10-11 · Revision 3

**Status: experimental polar path, diagnostics and verification implemented; production polar selection and aircraft-specific validation pending.**

Main-line physics follow-up **D8b-R2** (substeps D8b-R2a…i), continuing [flight-model robustness](FLIGHT-MODEL-ROBUSTNESS-PLAN.md), D9 and Gate 2. Investigation owns `research/flight-robustness/d8b-r2/` and `docs/research/flight-robustness/D8b-R2/`. The implementation adds optional physics/data contracts, tests and a restricted research launch route. Default aircraft data, controls and golden trajectories remain unchanged.

[Reproduction and evidence](research/flight-robustness/D8b-R2/README.md) · [Measurements](research/flight-robustness/D8b-R2/results.json) · [Source fingerprints](research/flight-robustness/D8b-R2/manifest.json)

**Revision 2 adds [18 source-based investigations](research/flight-robustness/D8b-R2/research-index.md) and [four executed numerical investigations](research/flight-robustness/D8b-R2/research-experiments.md).** Their principal change is to make the complete post-stall slope, input history and uncertainty explicit acceptance targets; CLmax, finite values and passing existing regressions are insufficient.

**Revision 3 implements the experimental solution and its verification:** [implementation, results and launch instructions](research/flight-robustness/D8b-R2/implementation/README.md). Three synthetic polar fixtures exercise the complete pipeline; none is selected as a calibrated replacement. The evidence-availability stop condition below remains active.

## Finding

The reproduced departure is a **rapid amplification of small lateral disturbances by the wing's post-stall force law**. Full elevator drives the airplane into that region even while airspeed remains high. Estimated asymmetric mass properties, powered-flight lateral trim and propeller effects provide disturbances; the nonlinear strip model then converts them into a large roll and a departure from the intended loop plane.

This is a confirmed causal mechanism in the current simulator, **not a confirmed measurement of excessive response relative to a real Ugly Stik**. Accelerated stalls and wing drop are physically possible. The unsupported part is this model's particular onset, severity and recovery, derived from an estimated stall transition and an artificial reference mass configuration. No evidence found justifies calling the reproduced 375°/s keyboard departure realistic for the owner's aircraft.

There is no need for a radio fault, rendering defect or numerical blow-up to produce the symptom. The owner confirmed **keyboard input**; throttle and the exact speed/build of the original event remain unspecified. The controlled scenario below reproduces the symptom class, not the owner's exact flight.

## Reproduction in the actual flight session

Baseline: commit `fd945cd0b8a567e6e169a76ff5a472ba98fb9fef`, official Windows Godot `4.7.2.stable.official.ed1daf0bf`, current Jensen Ugly Stik JSON, calm air, 300 m initial altitude, level trim at each entry speed. Hold pitch-up from 0.25 to 2.25 s, then release; observe through 4 s. Raw roll/yaw stay zero; throttle remains at its level-trim setting. This deliberately avoids ground contact and a dive-entry energy transient.

The keyboard case injects the same raw targets returned by `Keyboard.read_raw()` into `FlightSession._physics_process()`: **Down arrow = nose up**, keyboard slew 4 command units/s, trim addition/clamping, then the real servos and RK4. It bypasses OS key-event delivery, not the keyboard command shaping. Other diagnostic cases inject pilot commands immediately before trim/servo processing.

Maxima below cover the entire 4 s; cross-track displacement is relative to the initial body's horizontal heading, not Euler yaw/roll near vertical flight.

| Keyboard entry speed | Peak body roll rate | Maximum lateral displacement | Maximum body angle of attack |
| --- | ---: | ---: | ---: |
| 15 m/s (54 km/h) | 268.0°/s | 7.72 m | 17.16° |
| 20 m/s (72 km/h) | 328.4°/s | 8.99 m | 16.00° |
| 25 m/s (90 km/h) | **375.5°/s** | **19.27 m** | 14.43° |
| 30 m/s (108 km/h) | 427.5°/s | 41.55 m | 13.81° |

At 25 m/s, the saved keyboard samples show:

| Time since start | Actual elevator, TE up | Angle of attack | Body roll rate | Local-model weight |
| --- | ---: | ---: | ---: | ---: |
| 0.45 s | 17.80° | 5.32° | +2.9°/s | 0 |
| 0.55 s | 20.00° | 9.71° | +3.8°/s | 0.423 |
| 0.65 s | 20.00° | 12.74° | +1.3°/s | 1 |
| 0.75 s | 20.00° | 14.11° | −34.9°/s | 1 |
| 0.85 s | 20.00° | 13.38° | **−373.7°/s** | 1 |

The airplane first pitches normally, then loses lateral stability near stall. The large roll is a body angular velocity and trajectory change, not an Euler-angle display artifact.

## Causal chain and code locations

### 1. Full keyboard input reaches an estimated 20° elevator throw

[`keyboard.gd`](../app/input/keyboard.gd) and [`commands.gd`](../app/input/commands.gd) keep pitch, roll and yaw separate. [`spec.gd`](../app/spec.gd) sets a 0.25 s neutral-to-full keyboard ramp. [`flight_session.gd`](../app/sim/flight_session.gd), `flown_commands`, `_inputs`, `_pre_step` and `_deflections`, add trims and apply the servo. The aircraft JSON labels the 20° elevator throw and 0.14 s servo full-throw time **estimated**.

The full-pull command is saturated at the endpoint after adding pitch trim. Neutral pilot roll/yaw still carry the solved lateral trims. Holding Down is therefore a sustained maximum surface demand, not a command to follow a geometrically circular loop. That input semantics is not itself a defect.

### 2. The stall law introduces strong positive roll feedback

[`aero.gd`](../app/physics/aero.gd), `_local_loads`, evaluates each strip using `v + omega × arm`. Its lift is blended from induced attached lift to a flat-plate curve. All six Stik strips use the same positive geometric stall-transition interval, approximately **12.13–18.13°**, with an estimated 6° width. There is no dynamic separation state or measured spanwise stall progression for this aircraft.

Once the lift curve falls steeply, a small roll raises one wing's local angle and lowers the other's. The down-going wing can lose lift, accelerating the existing roll. The relevant derivative becomes positive:

| Body angle of attack, 25 m/s, neutral surfaces, zero base rates | `dMx/dp`, N·m per rad/s | `dMx/dp / Jxx`, 1/s |
| --- | ---: | ---: |
| 11.0° | −4.081 | −35.36 |
| 12.0° | −4.193 | −36.33 |
| 13.0° | +2.226 | +19.29 |
| 14.0° | +7.793 | +67.52 |
| 15.5° | **+11.121** | **+96.36** |
| 18.0° | −0.547 | −4.74 |

The last column is a **frozen-state scalar roll-feedback estimate**, not an eigenvalue of the full coupled maneuver. Its largest value corresponds to an approximately 10 ms e-folding scale if other state variables were held fixed. Positive feedback near stall can be physical; its magnitude here has no Stik measurement behind it.

`local_flow_weight()` transitions the complete six-axis load vector to the local model. The severe departure above happens after its weight is already 1; it cannot be explained solely by a discontinuity at the blend boundary. The attached-to-local transition and retained cross-derivative discrepancies still require separate verification.

### 3. The reference inventory creates a repeatable lateral seed

The derived inertia is `[Jxx,Jyy,Jzz,Jxy,Jxz,Jyz] = [0.115407, 0.387086, 0.484108, -0.009540, 0.0072395, 0.000455257] kg·m²`. [`rigid_body.gd`](../app/physics/rigid_body.gd) correctly uses the full tensor: a pure pitching moment need not produce pure pitch acceleration.

Two off-center inventory items explain `Jxy`:

| Item | Mass | Lateral position | Contribution to `Jxy` |
| --- | ---: | ---: | ---: |
| Side-mounted muffler | 150 g | +60 mm | −0.0029781 kg·m² |
| **Virtual reference-build balancing mass** | **284.1 g** | **−31.68 mm** | **−0.0065619 kg·m²** |

About **69% of this cross inertia comes from virtual ballast**, not a measured installation. Centering CG does not remove products of inertia: the balancing masses can cancel first moments while reinforcing cross moments. This is an evidence/configuration problem, not proof of an algebra error. Do not simply zero valid cross inertias in production. Removing cross inertia in powered flight does not remove the departure; the virtual ballast is a seed/configuration concern, not a sufficient explanation or a standalone repair.

With stopped propulsion and symmetric diagnostic inertia (`Jxy = Jyz = 0`, `Jxz` retained), roll remains microscopic through the first stall entry but eventually grows from floating-point/asymmetry residuals. Explicit mirrored initial roll seeds of ±0.0001 rad/s produce mirrored large departures. Removing the deterministic seed delays the instability; it does not repair its gain.

### 4. Propeller effects influence the direction but are not required

[`dynamics.gd`](../app/physics/dynamics.gd), `rotor_momentum`, and `RigidBody.derivative` include gyroscopic coupling. [`propulsion.gd`](../app/physics/propulsion.gd) supplies propeller torque. In the immediate-command 25 m/s diagnostic, peak roll is **7.549 rad/s** normally, **7.292 rad/s** with only gyro momentum disabled, and **7.361 rad/s** in separately trimmed dead-stick glide. Removing cross inertia in powered flight still produces **7.546 rad/s**.

The no-gyro comparison retains identical initial state, trim, RPM and thrust/torque laws. The glide comparison is not identical-state: it has its own glide trim and zero RPM. Together they show the large departure does not require the gyro or powered propulsion. Current Stik data has no enabled slipstream block; adding propwash is not an evidenced repair for this symptom.

## Why existing tests pass

All **43 targeted checks pass**: spin (8), damping regimes (20), gyro (6), handling (9). This is a coverage/validation gap:

- `test_spin.gd` requires positive roll feedback at 13.5°, but does not bound its magnitude against independent evidence. Its symmetric-stall case starts at 12 m/s; it does not cover the high-speed keyboard pull.
- `test_damping_regimes.gd` checks 0–11° attached/blended behavior, below the strongest amplification measured here.
- The existing `pull_throttle` maneuver uses 50% pitch at 15 m/s. Its handling check establishes climb, not loop-plane tracking or stall-entry roll severity.
- A golden trajectory protects existing behavior, including an unvalidated response.

Keyboard refinement at 25 m/s gives peak roll **375.49 / 375.50 / 375.51°/s** at 240/480/960 Hz; cross-track peaks are **19.271 / 19.250 / 19.240 m**. The departure survives refinement. These results argue against tick rate as the root cause; they do not establish fourth-order convergence of the sampled-control session. Keep production at 240 Hz unless another requirement justifies changing it.

## Repair, improvement and reinforcement

One small change per substep. Preserve baseline evidence before changing physics; a candidate is not accepted merely because it makes a clean loop possible.

| ID | Priority and work | Proof / acceptance | Status (2026-10-11) |
| --- | --- | --- | --- |
| D8b-R2a | P0: reproduce and identify the chain through the real session and keyboard shaping | 28 complete 4 s trials, static roll derivative sweep, hashes, fault checks and 43 existing checks; separate direct-command and keyboard results | **Done: engineering diagnosis** |
| D8b-R2i | P0: strengthen diagnosis and proposed solution through research | [18 investigations](research/flight-robustness/D8b-R2/research-index.md), exact-source links and applicability limits; [four numerical investigations](research/flight-robustness/D8b-R2/research-experiments.md) distinguish constitutive sensitivity, mesh sensitivity, differentiation and the stall-weight contribution | **Done: research and synthetic experiments** |
| D8b-R2b | P0: add a regression scenario and causal telemetry | Per-tick commands, committed state, component loads and wing strips; exact input/source identities; 15 m/s trim → full-power acceleration → pull without retrimming | **Implemented:** [17-case runner and 70 complete flights](research/flight-robustness/D8b-R2/implementation/matrix/README.md). Owner event/physical-key capture and dive-entry comparison remain open |
| D8b-R2c | P1: reconcile the reference aircraft's mass and controls | Independent full-tensor algebra, reflection, inverse and pitch-coupling tests; keyboard mapping and throw provenance; measured build needed before changing inventory | **Contracts implemented:** [41 checks](research/flight-robustness/D8b-R2/implementation/mass-controls.md). Physical inventory/servo measurements remain open; VAL-5/6 |
| D8b-R2d | P1: replace unsupported stall severity with a justified wing model | Optional positive/negative C1 polar tables, provenance validation, attached/reverse-flow joins, actual-load CL and roll-feedback sweeps | **Experimental implementation complete.** Three synthetic families evaluated. Matched data, defensible uncertainty bands and production selection remain open |
| D8b-R2e | P1: improve nonlinear coupling only where the evidence demands it | Explicit finite-wing/geometric-angle basis; C1, nonnegative drag and local power tests; 240/480/960 Hz comparisons; evolving-tick timing | **Verification implemented.** Fixed-input mesh convergence, performance acceptance and physical transient identification remain open. No unsupported nonlinear circulation or dynamic separation state added |
| D8b-R2f | P1: close the complete-maneuver coverage gap | Three speeds, two command ramps, positive/negative pulls, three powers, mirrored seeds, release; load reflection, exact replay/reload, synthetic spin/recovery; sensitive negative controls | **Automated coverage implemented:** 111 polar + 8 session checks and mutation evidence. Pilot loops, measured handling bands and reduced-throw/hold sweeps remain open |
| D8b-R2g | P1: integrate the smallest justified correction | Restricted experimental CLI route, persistent HUD/trace identity, fail-closed loading; directed tests and full `app/test.sh`; unchanged default data/goldens | **Integrated as opt-in research:** [verification evidence](research/flight-robustness/D8b-R2/implementation/README.md). Production coefficient replacement awaits d/f/h |
| D8b-R2h | Gate 2: validate keyboard usability and RC handling independently | Owner compares identified before/after builds: progressive loop, abrupt full pull, stall/recovery, both directions and several powers. Record inputs and blind ratings when practical. Validate on held-out maneuvers/configurations, not only those used for tuning | Open; depends on g |

### Acceptance contracts to define before tuning

1. **Attached-flow pull:** bounded uncommanded p/r and loop-plane departure, with bounds justified by the aircraft's measured/estimated propulsion and inertia. A clean loop is a maneuver with a specified input history and entry energy, not a guarantee for full elevator indefinitely.
2. **Accelerated-stall entry:** onset corresponds to local wing separation/load evidence; growth rate and left/right asymmetry are checked, not just the presence of a stall. At 25 m/s, a 9.51 m/s reference 1-g stall speed implies an approximate `n = (25/9.51)^2 = 6.91` lift limit. This is a model-based scale estimate, not a measured structural limit or exact dynamic onset criterion.
3. **Recovery:** measure residual p/r, alpha, altitude loss and time after releasing elevator and after a defined recovery input. Preserve genuine stalls, spins and gyro/torque effects.
4. **Symmetry and perturbations:** test load-level reflection at exact symmetric states and paired finite perturbations. Do not require a numerically perfect symmetric trajectory to stay identical forever through an unstable regime. Preserve source seeds and report sensitivity.
5. **Numerics and robustness:** finite complete runs, 240/480/960 Hz refinement, clean data reload, unchanged frame-rate independence, and no forced rate/attitude clamp hiding unstable physics.

Do not ship a blanket elevator reduction, artificial auto-rudder, permanent gyro removal, arbitrary extra roll damping or a wider stall blend merely because the symptom disappears. Reduced throws can be an explicit keyboard accessibility option later; they must remain separate from aircraft-physics validation. Similarly, an estimated candidate may be useful experimentally but must not be labeled a calibrated fix.

## Revision 2: strengthened solution

### What the new experiments change

- **The unstable contribution is localized.** At 15.5°, differentiating the local wing gives +11.1307 N·m/(rad/s). Freezing only stall weights for a diagnostic perturbation leaves −2.7481; the changing weights contribute +13.8788. An independent Python force reduction agrees with Godot to 5.33e-10 or better at the tested angles. The term `(CL_plate − CL_attached) dw/dp` is the primary target for investigation, not an instruction to remove stall feedback.
- **The nominal lift peak is not the principal discrepancy.** Actual static total CL peaks at 1.10511 versus the 1.1 label in the baseline. Widths 4–12° preserve the helper peak but change maximum positive roll feedback from 17.1308 to 4.9769. A correct peak cannot validate the curve's falling branch.
- **More strips alone are insufficient.** Regenerating the attached calibration at 3/6/12/24 strips per side changes maximum feedback from 11.1210 to 9.4714, approximately −14.8%, still strongly positive. Once independent section data exists, also refine with that constitutive input fixed; the current sweep re-solves its section slope and is not a strict fixed-model mesh-convergence study.
- **The derivative estimate is robust locally.** Perturbations from ±1e-2 to ±1e-6 rad/s retain essentially the same result. A full maneuver requires finite-time coupled growth measurements rather than treating `dMx/dp / Jxx` as its exact eigenvalue.

All values are synthetic, static, positive-alpha evidence at 25 m/s. [Methods, controls and limitations](research/flight-robustness/D8b-R2/research-experiments.md).

### Concrete implementation sequence

1. **Make the failing maneuver observable (R2b).** Add a reusable research runner that records every tick from raw keyboard targets through servo outputs and per-component loads. Include trim identity, engine state, last-load timestamp and exact source hash. Sample state/attitude with quaternions and body rates; derive loop-plane error without Euler singularities. Compare injected keys, the actual app with real key delivery, and replayed downstream commands. Test acceleration from the default 15 m/s trim as well as separately retrimmed entries; retrimming at 25 m/s does not reproduce simply accelerating with the original trims.
2. **Build bounded aircraft inputs (R2c).** Use the Jensen plan/scan, a specific physical build and the owner's measured control travel. Keep other manufacturers' Stik manuals as donor evidence only. Audit the drawn CG marker, virtual ballast and measured uncertainty jointly with mass/inertia. A symmetric synthetic fixture is useful for verification but must not silently become the claimed real aircraft.
3. **Compare the smallest constitutive candidates (R2d).** Keep the current law as the recorded baseline. First evaluate a supported section/finite-wing polar with an explicit post-peak shape, positive/negative stall and smooth continuation to the existing reverse-flow domain. Constrain lift, drag, moment, onset and slope together at the relevant Reynolds range. Preserve force/moment consistency. Do not fit solely to a clean loop or solely to the 1.1 peak. Where independent data is absent, carry bounded candidate families and label them estimated; allow no stronger realism claim.
4. **Escalate model complexity only after discrimination (R2e).** Test whether improved quasi-steady polar and spanwise separation explain both gentle and abrupt pulls. Only if held-out transient evidence requires it, add a separation-state model with documented rate/Reynolds validity and identified time constants. Integrate new continuous states in the coupled solver; include them in reset, checkpoint, replay and stage timing. An unsteady wind-turbine model is a research reference, not a drop-in aircraft calibration.
5. **Promote through separate gates (R2f–h).** First mathematical correctness and complete traces; then convergence and performance; then measured/estimated handling bands; finally the owner's keyboard and radio acceptance. Keep the physics change independent of any keyboard comfort option. Update golden files only after documenting intended physical differences.

### Additional acceptance and stop conditions

| Concern | Required evidence before promotion |
| --- | --- |
| Input and Godot scheduling | Same per-tick command history gives consistent trajectories across render rates; physical keyboard/ghosting/pause behavior is checked separately from injected raw targets. Interpolation never feeds simulation state |
| Constitutive sensitivity | Plot the full polar and `dMx/dp` through both stall transitions at the tested control deflections; compare shape/rate uncertainty, not only nominal peaks. A materially different derivative must be explained |
| Spatial and temporal accuracy | Separate time refinement, strip refinement with fixed physical inputs, and any recalibration. Compare at equal physical times and retain sampled-control discontinuities in reference solutions |
| Inertia | Full-tensor and reflection tests, measured or defensibly bounded inventory, correct axes and about-CG convention. Zeroing cross terms is never an unreported stabilization device |
| Passivity and propulsion | Under explicit passive/fixed-surface assumptions, account for both force and moment power. Isolate gyro, shaft torque and wake contributions; a passive wing can still autorotate by converting translational energy |
| Maneuver validity | Track alpha, local separation, load factor, roll-growth delay, peak rate, plane error, recovery time and altitude loss. Keep physical flights held out from tuning; owner ratings supplement rather than replace trace evidence |
| Evidence availability | If matched post-stall data or useful uncertainty bounds remain unavailable, keep candidates experimental. Do not close Gate 2 or invent a numeric realism tolerance |

**First repair candidate to evaluate:** a documented, bounded revision of the falling branch/spanwise separation behavior, after input and mass provenance are made explicit. **Not selected yet:** a particular width, damping coefficient, dynamic-stall law, higher tick rate or mesh size. The research narrows the mechanism and the next experiment; it does not supply missing real-aircraft coefficients.

## Research basis and limits

Sources reviewed 2026-10-11. No third-party figures or datasets are copied into this report; summaries are linked to their primary sources.

- [FAA Airplane Flying Handbook, chapter 5](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/06_afh_ch5.pdf): accelerated stall depends on angle of attack/load, not low airspeed alone. Establishes physical possibility, not the Stik's departure magnitude.
- [NASA TP-1589, 1979](https://ntrs.nasa.gov/api/citations/19800004771/downloads/19800004771.pdf): near-stall unstable roll damping and autorotation; wind-tunnel, RC-model and full-scale comparisons show strong sensitivity to spanwise separation. This is a different aircraft, not a source for copying numerical derivatives into the Stik.
- [NASA Glenn: inclination effects on drag](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/inclination-effects-on-drag/): separated flow is unsteady and stall prediction needs experiments matching the important similarity parameters. Supports uncertainty and Reynolds-aware evidence rather than accepting a generic flat-plate blend as validation.
- [NASA: determining products of inertia for small-scale UAVs](https://ntrs.nasa.gov/api/citations/20170000461/downloads/20170000461.pdf): symmetry assumptions and measurement sensitivity. Supports checking the full tensor; does not justify discarding a real asymmetric muffler or assigning this Stik another aircraft's inertia.
- [JSBSim FGPropeller](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGPropeller.html): independent implementation reference for rotor inertia, torque and gyro. The local no-gyro ablation, rather than analogy, establishes that gyro is not necessary here.

Remaining uncertainty: no recorded user flight, no observed physical keyboard-event delivery, no measured Stik high-load maneuver, no structural-flex model validation and no stall-polar identification. The investigation establishes where the simulator generates the departure and why current checks allow it; it does not yet establish a final replacement coefficient set.
