# VAL-AUD-2026-10-14 — Jet and Ugly Stik physics audit

**Date:** 2026-10-14. **Scope:** current production `app/`, using the Ventage Jet (SebArt Avanti S A200 / JetCat P100-RX) and baseline Jensen Das Ugly Stik 60. **Disposition:** audit and reproducible evidence only; no production fixes, parameter tuning, or golden-flight replacement.

**Planning follow-up, 2026-10-14:** the [remediation plan](#remediation-plan) below defines proposed repairs, integration boundaries, dependencies, and acceptance gates for all eleven findings. It does not change the audit results or mark any repair implemented. The original artifact manifest remains the pre-plan snapshot; [remediation-plan-manifest.json](remediation-plan-manifest.json) records the document amendments.

The audit reproduced **two force-law discontinuities, one broken regression comparison, and a Jet runway-initialization failure under mild crosswind**. It also verified material omissions in the two selected aircraft configurations. The rigid-body equations, gravity, inertia realizability, and tested integration paths passed the numerical checks. Those passes do not establish aircraft realism: important parameters remain estimates, and no independent flight-identification campaign supports either complete aircraft model.

The strongest counterexample is shared by both aircraft: approaching the same lateral air velocity along two different Cartesian directions produces different finite aerodynamic forces. At 20 m/s lateral speed, the difference is **164.49 N for the Stik and 256.97 N for the Jet** with the current authored coefficients. The magnitude depends on those coefficients; the demonstrated lack of a unique force limit does not require accepting them as physically validated.

## Scope, identities, and method

| Item | Jensen Ugly Stik 60 | Ventage Jet |
|---|---:|---:|
| Catalog ID | `jensen-das-ugly-stik-60` | `sebart-avanti-s-a200-p100rx` |
| Loaded mass | 2.885058291 kg | 11.705089 kg |
| Wing area / span | 0.464515 m² / 1.524 m | 0.702275 m² / 2.000 m |
| Reference chord | 0.304800 m | 0.351137 m |
| Loaded CG, aft of reference leading edge | 0.120900 m | 0.240000 m |
| Declared fuel | 0.120 kg | 1.280 kg |
| Flight-probe trim speed | 15 m/s | 29 m/s |
| Active engine integration | Prescribed RPM, sampled lag | Continuous turbine RPM, RK4 |
| Tail propwash configured | No | No propeller; this is appropriate |
| Input SHA-256 prefix | `5fe8ece91b7ebe92` | `74043c9bc1de35de` |

The audit used native Windows Godot `4.7.2.stable.official.ed1daf0bf`, float64 simulation state, and 240 Hz flight sessions. Forces and moments below use body axes **forward, right, down** and the order `[Fx,Fy,Fz,Mx,My,Mz]`; moments are about the CG. Structural positions use the aircraft data's aft/right/up convention. Comparing the two aircraft does not imply they should have equal rates, stall speeds, or control forces.

The base Git commit was `c642a997b758d58b9eefefe6f6f3ab6b9ab44742`, with substantial pre-existing staged, unstaged, and untracked work. **HEAD alone does not reproduce the audited application.** [Initial identity](identity-before.json), [final identity](identity-after.json), and [source drift](source-drift.json) record 148 source hashes. The observed changes in that set were the unrelated ground-vehicle files `app/physics/ground_vehicle/airfield_track.gd` and `app/physics/ground_vehicle/vehicle_dynamics.gd`; the selected aircraft and fixed-wing solver sources were unchanged. The flight recorder's development build label is not a substitute for these working-tree identities. This bundle retains inputs in the flight logs, scripts, hashes, and results; it is not a complete source checkout.

Three delegated reviews covered aerodynamics, data/propulsion, and numerics/ground contact. The lead independently reproduced the key force defects, isolated the regression failure in a disposable test copy, and checked inertia eigenvalues with NumPy. An incorrect wind-axis transform in an early delegated diagnostic was identified and rejected. Its superseded output is explicitly labeled in the [aerodynamic review](aero/README.md); its lift numbers are not evidence for this report.

## Finding register

Priority describes the order for closing a realism claim, not a claim that every issue affects ordinary cruise. **P1:** resolve before claiming the affected behavior is verified or realistic. **P2:** material limit in an identified operating domain. **P3:** smaller or deliberately narrow approximation. “Omission” means an implemented scope restriction, not a newly discovered coding accident.

| ID | Priority / classification | Affected aircraft | Finding and proven domain |
|---|---|---|---|
| F01 | P1 — force-law defect | Both | Aerodynamic force has no unique Cartesian limit at pure spanwise flow. |
| F02 | P2 — force-law defect | Jet | Entire inlet momentum vector switches off at zero axial speed, creating finite side-force and moment jumps. |
| F03 | P1 — verification defect | Shared test / Jet polar | Current H12 comparison fails 1,556 cases because its legacy oracle and current model have different optional polar behavior. |
| F04 | P1 — aircraft-model omission | Baseline Stik | Running propeller cannot increase elevator/rudder authority; particularly material at low speed. |
| F05 | P2 — explicit energy/mass omission | Both; larger on Jet | Fuel flow does not deplete fuel or change weight, CG, or inertia. |
| F06 | P2 — propulsion approximation | Baseline Stik | Prescribed RPM has no flight-load equilibrium; stopped propeller adds no explicit disc drag or windmilling. |
| F07 | P3 — local-flow approximation | Jet | Offset inlet force uses CG air velocity and omits the local `ω × r` contribution. |
| F08 | P1 — physical-validation gap | Both | Estimated mass distribution, virtual balance, aerodynamics, and ground coefficients are not independently identified for these builds. |
| F09 | P3 — atmospheric scope limit | Both | Density is uniform through each flight; altitude excursions do not change it. |
| F10 | P2 — configuration omission | Jet | Flap aerodynamics are explicitly not simulated, limiting landing-configuration realism. |
| F11 | P1 — initialization defect | Jet | The production runway reset fails with 1.5 m/s exactly perpendicular crosswind; a 0.001° direction change makes it succeed. |

## F01 — Aerodynamic force is discontinuous at pure spanwise flow

**Evidence:** [lead probe](../../../research/physics-audit-2026-10-14/aero_edges.gd), [raw loads](aero-edges.json), [derived differences](lead-summary.json), and [independent aerodynamic corroboration](aero/README.md).

Set density to 1.225 kg/m³, controls and angular rates to zero, disable propulsion, and evaluate the production `Aero.loads` function at:

```text
v_A = [ε, 20, 0] m/s
v_B = [0, 20, ε] m/s
ε = 10^-2, 10^-4, 10^-6, 10^-9 m/s
```

Both velocity sequences approach exactly `[0,20,0]`. No trigonometric reconstruction of velocity is involved. At `ε=10^-9`, their separation is only `1.4142×10^-9 m/s`, but:

| Production result | Stik, path A | Stik, path B | Jet, path A | Jet, path B |
|---|---:|---:|---:|---:|
| Total side force Fy, N | −19.759651 | −184.252891 | −56.606590 | −313.578379 |
| Wing-only side force Fy, N | −5.099872 | −141.506598 | −6.070880 | −214.603229 |
| Total yaw moment Mz, N·m | 10.656334 | 25.899778 | 29.126805 | 57.365185 |
| Total roll moment Mx, N·m | −1.421744 | −9.688347 | −11.941519 | −13.765987 |

The side-force difference converges to 164.493240 N and 256.971790 N, respectively. Dividing by each loaded mass gives acceleration differences of **5.814 g** and **2.239 g**. These are instantaneous force-derived differences, not measured flight load factors. The exact zero-projection state follows path A's result. The discrepancy persists through the epsilon sweep; it does not shrink with the velocity perturbation.

**Cause:** [wing angle construction](../../../app/physics/aero.gd#L327) uses `atan2(f2,f0)` to select the section coefficients. [Wing drag](../../../app/physics/aero.gd#L379) then uses the full speed, including spanwise `f1`:

```text
angle = atan2(f2, f0)
speed = sqrt(f0² + f1² + f2²)
F_drag = −0.5 ρ speed S_strip CD(angle) [f0,f1,f2]
```

As `(f0,f2)` tends to zero, its angle can approach either 0° or 90°, while `speed` stays 20 m/s. The angle-dependent drag therefore remains finite and depends on the path to a coordinate singularity. The [tail drag calculation](../../../app/physics/aero.gd#L443) has the same combination. The lift path uses section-plane speed and tends to zero, so this is not merely an undefined coefficient whose dimensional force vanishes. The global/local blend selects the local law in these cases.

**Consequence:** large artificial sensitivity in extreme sideslip, tumbling, and some post-stall attitudes. This audit does not show that the discontinuity is reached by the ordinary six-second control pulses, or that it caused a particular user-observed crash. It does prove that the current aerodynamic force model lacks a unique limit at this boundary.

**Closure evidence required:** define a consistent three-dimensional/spanwise drag treatment, retain physically justified spanwise resistance, and demonstrate that force **and moment** differences tend to zero for several Cartesian approaches, signs, and wing/tail geometries. Merely forcing `atan2(0,0)` to a chosen value will not repair the neighborhood. Recheck passivity and preserve a recorded ordinary-flight baseline before comparing the candidate on the same input tape.

## F02 — Turbine crossflow force jumps when axial velocity changes sign

**Evidence:** [lead probe](../../../research/physics-audit-2026-10-14/propulsion_edges.gd), [raw turbine loads](propulsion-edges.json), and [source](../../../app/physics/turbine.gd#L147).

At 154,000 RPM, density 1.225 kg/m³, and 20 m/s lateral air velocity:

| Input | Fx, N | Fy, N | Mx, N·m | My, N·m | Mz, N·m |
|---|---:|---:|---:|---:|---:|
| `[0,20,0]` m/s | 92.000000 | 0 | 0 | 0.934076 | 0 |
| `[0.000001,20,0]` m/s | 92.000000 | −4.600000 | 0.152504 | 0.934076 | −1.518000 |

The finite transverse jump persists at smaller axial perturbations; the `10^-3` and `10^-6` cases agree to the shown precision. A 20 m/s vertical crossflow instead produces a 4.6 N vertical-force jump and approximately 1.518 N·m pitch-moment jump. At idle, the lateral jump is still 1.3142 N.

**Cause:** line 152 applies `−mass_flow × v_air` only if `dot(v_air,axis) > 0`; otherwise it sets the **whole vector** to zero. The running engine's authored mass flow remains nonzero at zero axial speed. Switching off its transverse momentum contribution at this boundary creates an artificial discontinuity. Inlet momentum is part of the propulsion balance, but a general thrust equation does not identify the real Avanti intake capture law. See [NASA's thrust equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/).

**Consequence:** a force/moment step near 90° angle of attack or sideslip while the turbine is running. This is not evidence that ordinary forward-flight thrust is wrong by 4.6 N.

**Closure evidence required:** a continuous, stated inlet-capture model through zero and reverse axial flow, with separate limits for unvalidated crossflow. Test dimensional forces and moments on both sides of zero at idle and full RPM; do not validate only an axial thrust curve.

## F03 — The current H12 regression comparison is broken

**Evidence:** [current run](checks/h12-current.log), [disposable isolated run](checks/h12-polar-neutralized-disposable-test.log), [commands, exit codes, and source hashes](checks/h12-isolation.json), [reproducer](../../../research/physics-audit-2026-10-14/reproduce_h12.py).

Running the unmodified `app/tests/test_aero_flow.gd` returns exit code **1**:

```text
H4 local flow: 20000 byte-exact comparisons, 0 failed
H12 local loads: 20001 byte-exact comparisons (14553 stalled, 4000 zero-flow), 1556 failed
```

The [test's model normalization](../../../app/tests/test_aero_flow.gd#L73) removes several newer optional mechanisms before comparing the current scalar implementation with the frozen [vector reference](../../../app/tests/aero_flow_reference.gd). It does not remove `wing_polar`, which the current Jet enables and the reference does not evaluate.

The lead made a disposable copy outside `app/`, added only `wing_polar` to the existing exclusion list for **both** compared model copies, and reran it. H12 then reported **20,001 comparisons, zero failures**, exit code 0; H4 was unchanged. The original test remained byte-identical. This isolates an incompatible test contract; it does **not** prove the Jet polar is physically wrong or authorize deleting its independent tests.

**Consequence:** the current native regression check is red, and broad claims that all physics checks pass are unsupported. [`app/test.sh`](../../../app/test.sh#L160) includes this test. The entire repository suite was not run in this audit, so no whole-suite outcome is claimed.

**Closure evidence required:** explicitly separate legacy implementation parity from enabled-polar behavior; maintain independent enabled-polar expectations, rerun the failing check, and then run the repository's required integration checks. Do not re-record a golden flight to hide this mismatch.

## F04 — The baseline Stik has no propwash contribution to tail authority

**Evidence:** [production-session probe](../../../research/physics-audit-2026-10-14/session_probe.gd), `static_control_authority` in [session results](session/session-results.json), and [RPM comparison](lead-summary.json).

The selected Stik lacks a `propulsion.slipstream` module. [Dynamics](../../../app/physics/dynamics.gd#L96) adds the existing optional wash model only when that module is present.

At zero airspeed, 11,149 RPM generates **41.251877 N** thrust and **−0.834106 N·m** airframe reaction roll torque, yet changing the elevator or rudder from 0° to +10° produces **zero incremental force and moment**. At 5 m/s, a +10° elevator produces `ΔMy=−0.315709 N·m` and a +10° rudder produces `ΔMz=−0.126350 N·m`, identically with RPM zero or full. The same lack of RPM-dependent authority holds at 15 and 29 m/s, within floating-point subtraction noise. These are physical surface deflections, not the pilot-input sign convention.

For a tractor propeller aircraft, wake reaching the tail can provide control authority beyond that implied by free-stream speed. The [FAA flight-controls chapter, p. 6-8](https://www.faa.gov/sites/faa.gov/files/08_phak_ch6.pdf) explicitly describes increased rudder effectiveness from propeller slipstream. The exact immersed area and gain for this Stik require geometry and measurement; this audit does not invent them.

**Consequence:** the baseline configuration cannot represent that power-dependent mechanism during takeoff, slow flight, go-around, or powered stall recovery. Enabling a generic model without aircraft-specific evidence would not by itself validate those maneuvers. Other Stik/glow variants have different modules and are outside this finding; the codebase as a whole is not missing every propwash implementation. The Jet should not inherit a tractor-propeller wake.

**Closure evidence required:** configure the existing wake capability through the aircraft's source pipeline using defensible geometry, then compare engine-off/on control increments over speed, deflection, and RPM. Retain the original baseline and compare a single candidate with identical inputs.

## F05 — Fuel flow does not change the aircraft's available fuel or mass properties

Both selected records declare `energy: prescribed_fuel`: [Stik](../../../app/data/aircraft/jensen_ugly_stik_60.json#L1524) and [Jet](../../../app/data/aircraft/sebart_avanti_s_a200.json#L2448). Current [turbine telemetry](../../../app/sim/flight_session.gd#L2258) reports fuel flow and that policy. It does not integrate depletion into these aircraft's mass, CG, and inertia.

The Jet begins with 1.28 kg fuel, **10.94% of loaded mass**. Its maximum fuel-flow map is 0.0052 kg/s. The ratio `1.28/0.0052 = 246.15 s`, or 4.10 minutes, is the **nominal budget calculated from the authored fuel and full-flow endpoint**. It is not a measured endurance and not the result of a 246-second flight test. The current policy has no fuel exhaustion at that budget.

At the same assumed fuel centroid, recomputing the inventory first moment changes the Jet CG from 0.2400 m aft of the leading edge at the initial half-tank state to 0.2633 m empty: **23.3 mm**, or 6.6% of reference chord. The analogous Stik shift is **9.6 mm**, or 3.2% of chord. These are sensitivities of the authored inventory, not measured CG travel: the tank locations are estimates. Calculations and inputs are retained in the [data review](data-propulsion/README.md) and [raw inventory diagnostic](../../../research/physics-audit-2026-10-14/data-propulsion/godot-audit.log).

**Consequence:** neither selected aircraft can reproduce fuel exhaustion, progressive weight reduction, or the associated balance/inertia change. This is a declared model omission, not a gravity error. It is especially material for the Jet's sustained maneuvers and landing after fuel use.

**Closure evidence required:** a bounded fuel state with explicit exhaustion behavior and consistent variable mass/CG/inertia treatment, supported by actual tank position and usable-fuel data. Verify fuel accounting analytically and compare full/partial/empty configurations; use the existing aircraft authoring pipeline.

## F06 — The baseline Stik uses prescribed RPM and loses explicit propeller drag when stopped

The selected Stik uses [target RPM and first-order lag](../../../app/physics/propulsion.gd#L53), rather than an engine/propeller shaft balance. The active [session branch](../../../app/sim/flight_session.gd#L2696) calls that lag when no shaft model is configured. Consequently airspeed and propeller torque cannot alter its demanded steady RPM. The data already describes this approximation.

At the prescribed maximum 11,149 RPM, modeled propeller demand is 973.836 W static, 982.644 W at 5 m/s, and 1,000.261 W at 15 m/s. These values show a changing aerodynamic load while the prescribed RPM remains fixed. They are not, by themselves, a proof of energy conservation failure: the model does not solve an engine torque budget. See the [propulsion diagnostic](../../../research/physics-audit-2026-10-14/data-propulsion/godot-audit.log).

Separately, [the stopped-propeller branch](../../../app/physics/propulsion.gd#L553) returns six zero loads below 1 RPM for this non-glow-law configuration. The lead's [edge probe](propulsion-edges.json) confirms zero propeller loads at **30 m/s and 0 RPM**, whereas the 2,800 RPM idle propeller has approximately **−2.30255 N** axial force. The aircraft still has airframe drag; this finding concerns the explicit incremental propeller load. A fixed airframe drag coefficient cannot identify separate stopped and windmilling disc behavior over the envelope.

**Consequence:** limited realism for unloading, throttle response under changing flight load, engine-out glide, and windmilling. The more detailed glow/shaft implementations elsewhere in the repository do not automatically apply to this baseline catalog entry.

**Closure evidence required:** select and identify an appropriate existing shaft/propeller model, or explicitly bound the baseline's valid domain. Measure RPM versus airspeed/throttle and glide drag in the relevant propeller states; preserve distinctions between APC Sport and Thin Electric propellers and between measured and similarity-scaled coefficient tables.

## F07 — Jet intake loads do not use the intake's local rotational velocity

[Dynamics](../../../app/physics/dynamics.gd#L85) supplies CG-relative air velocity to the turbine, although [Turbine.loads](../../../app/physics/turbine.gd#L154) applies inlet momentum at an offset intake point. The point-velocity relation is `v_intake = v_CG + ω × r_intake`. Only the glow path receives a hub-local velocity adjustment in the shared caller.

For the current intake body arm `[0.33,0,0.033153] m`, CG air velocity `[29,0,0] m/s`, and pitch rate `q=+2 rad/s`, the local velocity is `[29.066306,0,−0.66] m/s`. At `q=−2`, it is `[28.933694,0,+0.66]`. Nevertheless, the production **propulsion component** is identical for both rates and for zero rate: `[86.414376,0,0,0,0.723310,0]` in N/N·m. This does not mean total aerodynamic loads are rate-independent.

Holding the current mass-flow scalar fixed to isolate the missing kinematic contribution yields `ΔF=[−0.015315,0,+0.152438] N` and `ΔMy=−0.050812 N·m` at `q=+2`; the signs reverse at `q=−2`. See [raw local-velocity calculations](propulsion-edges.json).

**Interpretation:** a small local-flow approximation within the authored capture-momentum model, affecting its rate-dependent force/moment contribution. This calculation is not a validated replacement turbine model, does not settle real twin-intake flow, and does not establish that every open-system engine force is missing.

**Closure evidence required:** derive inlet/outlet kinematics and the open-system momentum balance consistently before adding a rate term. A physical intake-flow model may justify further terms; the current scalar map alone cannot establish them.

## F08 — Passing equations does not identify either physical aircraft

The [data review](data-propulsion/README.md) and [numerics/ground review](numerics-ground/README.md) separate provenance from mathematical consistency. Important limits are already visible in the accepted data:

| Quantity or mechanism | Evidence and unresolved issue |
|---|---|
| Mass distribution | Both are virtual balanced reference builds. Stik includes 0.284058 kg virtual balance mass, 9.85% of total; Jet includes 0.345089 kg, 2.95%. These are not weighed installations. |
| Inertia | Inventory boxes and parallel-axis calculations produce realizable tensors, but their component positions and dimensions are not measured inertia identification. |
| Stik aerodynamics | Several derivative/drag assumptions originate from donor-aircraft data. Similar planform dimensions do not validate the donor's dynamic stability or control derivatives for this build. |
| Jet aerodynamics | Area/tail geometry and several stability/drag quantities are estimates. Its current post-stall polar is an experimental NACA 0015 hybrid-data proxy scaled to an assumed finite-wing CLmax, not an identified Avanti airfoil/flight polar. [Authored provenance](../../../app/data/aircraft/sebart_avanti_s_a200.json#L1984). |
| Propulsion | Jet installation factor, ram corrections, rotor inertia, and spin sense remain estimates/unverified. Stik propeller coefficients use similarity-scaled donor measurements; RPM/torque matching is incomplete. |
| Ground | Tire, suspension, braking/steering, and surface parameters have software consistency checks but no independent measured rollout/drop/taxi campaign for these two builds. |

Matching the Jet's modeled dry mass (10.425 kg) to the manual's coarse approximately 10.5 kg value cannot establish its CG, inertia, or flying qualities. Likewise, the Stik loader's `Jyy` warning against a scaled UltraStick reference is a reason to measure, not proof of an erroneous tensor. No negative or unrealizable inertia was found.

Lift, drag, and moments depend on coefficients appropriate to geometry and operating condition; validating their units does not identify those coefficients. The [NASA lift-equation discussion](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/lift-equation/) distinguishes the governing relation from determining the aerodynamic coefficient.

**Consequence:** a smooth, deterministic simulation can still have incorrect stall/recovery, damping, trim, turn response, and touchdown behavior. The current evidence does not support “100% realism” for either aircraft. This is an evidence gap, not proof that every estimated value is false.

**Closure evidence required:** an as-built mass/CG/inertia record and independent measurements of trim, speed, RPM/thrust, control response, stall/recovery, and ground behavior. State uncertainty and valid operating ranges. Fit to one dataset and validate on different maneuvers; do not use a test generated from the same coefficient assumptions as independent physical proof.

## F09 — Air density does not follow aircraft altitude during flight

[Atmosphere](../../../app/physics/atmosphere.gd#L41) explicitly computes one uniform field-level atmosphere. [FlightSession.air_density](../../../app/sim/flight_session.gd#L250) returns that value without consulting aircraft position. The lead's 50, 500, and 1,000 m start-altitude samples retain `ρ=1.225 kg/m³` and the same trimmed loads for both aircraft.

An independent hydrostatic dry-standard-atmosphere calculation using the source constants gives:

| Height above a sea-level field | Calculated standard-day density | Uniform-model aerodynamic force excess at equal speed/coefficients |
|---|---:|---:|
| 50 m | 1.219131 kg/m³ | 0.48% |
| 500 m | 1.167273 kg/m³ | 4.95% |
| 1,000 m | 1.111660 kg/m³ | 10.20% |

The calculation and assumptions are in [summarize.py](../../../research/physics-audit-2026-10-14/summarize.py) and [results](lead-summary.json). These are conditional standard-day sensitivities, not measured weather or turbine-performance errors. Field elevation, pressure, temperature, and humidity support exists; the omission is **vertical variation during the flight**, not the absence of atmospheric configuration. The error is modest near the field and becomes more material in large altitude excursions.

**Closure evidence required:** either state a justified altitude range for uniform density or evaluate the atmospheric column at aircraft altitude consistently across airframe and propulsion. Constant local gravity was not demonstrated to be a material error in the RC domain.

## F10 — Jet flap aerodynamics are outside the current configuration

The [Jet capability record](../../../app/data/aircraft/sebart_avanti_s_a200.json#L2450) declares `flaps: not_simulated`. The audited aero control dictionary contains the two ailerons, elevator, and rudder; it does not contain a flap lift/drag/moment input. A flap mesh or hinge is not evidence of flap aerodynamics.

**Consequence:** the current aircraft cannot reproduce a deployed-flap landing configuration, including its changed lift, drag, trim, and approach behavior. This does not invalidate a deliberately flaps-up scenario. The general aerodynamic role of flaps is described in the [FAA flight-controls chapter](https://www.faa.gov/sites/faa.gov/files/08_phak_ch6.pdf); the Avanti's actual increments need aircraft-specific data.

**Closure evidence required:** explicit authored flap capability, geometry/limits, and justified aerodynamic increments, verified from input through physical forces and trim. Keep flaps-up evidence distinguishable from deployed-flap evidence.

## F11 — Jet runway initialization fails under mild perpendicular crosswind

**Evidence:** the existing [ground-session test log](../../../research/physics-audit-2026-10-14/numerics-ground/logs/test_retractable_gear_ground.log), independent [lead direction-sweep script](../../../research/physics-audit-2026-10-14/runway_crosswind.gd), [14-case result](runway-crosswind.json), [lead log](runway-crosswind.log), and the delegated [magnitude sweep](../../../research/physics-audit-2026-10-14/numerics-ground/logs/runway_crosswind_probe.log).

The unmodified `test_retractable_gear_ground.gd` finished with **25 checks, one failure**. The failing [assertion](../../../app/tests/test_retractable_gear_ground.gd#L256) requests a default-field eastbound runway start with a steady 1.5 m/s wind from north. This is a 5.4 km/h perpendicular crosswind. The production `reset_on_runway` returns false; the solver reports:

```text
runway start: idling pose did not converge (residual 9.239795830815291)
```

The lead reproduced it with new production sessions and the actual default field. Aircraft loading, weather setup, field setup, and the runway threshold all succeeded. Only the runway reset was rejected:

| Wind speed | Wind from | Baseline Stik runway reset | Jet runway reset |
|---|---:|---|---|
| 0 m/s | 0° | Accepted | Accepted |
| 1.5 m/s | 0° | Accepted | **Rejected** |
| 1.5 m/s | 0.001° | Accepted | Accepted |
| 1.5 m/s | 359.999° | Accepted | Accepted |
| 1.5 m/s | 1° or 359° | Accepted | Accepted |
| 1.5 m/s | 90° | Accepted | Accepted |

The delegated magnitude sweep also accepted exact perpendicular wind at 0.5 and 1.0 m/s, then reproduced rejection at 1.5 m/s. These finite samples do not establish a monotonic wind limit.

**Failure location:** [GroundStart.solve, stage 2](../../../app/physics/ground_start.gd#L100), which seeks an idling static pose with fixed wheel anchors using Newton iteration. Its reported residual combines acceleration components; **9.2398 is not a measured force or a single acceleration in a common unit**. The test failure's printed `{ok:true, north:15, east:-47, heading:π/2}` describes a successfully found runway threshold, not a successful aircraft equilibrium. This is not a stale assertion like F03.

**Consequence:** the requested runway initialization fails in an ordinary mild-wind configuration and is highly sensitive to wind direction. The compatibility reset helper restores its normal start on failure; this audit does not claim the whole application crashes. F01/F02 are plausible contributors around perpendicular flow, but their causal role in this Newton failure was **not isolated**. The numerical initialization failure is confirmed; its underlying cause remains open.

**Closure evidence required:** identify the failing residual/Jacobian behavior, distinguish a missing physical static equilibrium from an iteration failure, and verify both wind directions and small angular perturbations. After a successful start, retain the currently skipped two-second stationarity check. Do not merely perturb the input direction or relax the residual tolerance until the single test passes.

## Checks that passed and suspicions not substantiated

| Area | Observed result | What it establishes |
|---|---|---|
| Live control path | 28 independent six-second sessions; all reached 1,440 ticks, finite, with no fault or crash. | Both aircraft's production session path runs for the prescribed cases. |
| Control signs | All 24 non-neutral initial roll/pitch/yaw response checks passed under normal/full keyboard rates. | No reversed pilot-axis sign in those cases. |
| Neutral trim | Both aircraft held their independently solved trim in calm-air neutral runs. | Internal six-axis equilibrium, not real-aircraft trim validation. |
| Exact replay | Both recorded normal-rate right-rudder flights replayed all 1,441 rows, `complete=true`, `solver_changed=false`, no error. | Byte-exact reproducibility on the recorded solver. |
| Focused session/data suites | All 10 suites in [verification.json](checks/verification.json) passed. | Trim, regimes, Jet handling/gamepad, data validation, rates, turbine integration, actuators, and checkpoint checks pass. The unmodified H12 subcheck in `test_aero_flow.gd` remains failing (F03). |
| Numerics/contact suites | 15 focused suites passed 407 checks; aircraft-data and retractable-gear checks also passed. | The bounded invariants, integration, contact, friction, and collision checks in the [numerical review](numerics-ground/README.md). Counts are not a claim of unique whole-suite coverage. |
| Jet ground session | `test_retractable_gear_ground.gd`: 24 passed, one failed. | Brakes, nominal landing, taxi, and other checked routes pass; crosswind initialization fails (F11), and its dependent stationarity check is skipped. |
| Aero passivity sampling | 1,683 zero-control/rate-grid cases per aircraft had finite loads and nonpositive `F·v + M·ω` in the delegated diagnostic. | No energy-source counterexample in that grid. Dissipation does not imply continuity: F01 still fails. |

The flight experiment resets each aircraft to trimmed level flight at 300 m, uses its own starting speed, holds trim throttle, applies a full raw keyboard-axis pulse from 0.5 to 1.0 s, then releases it until 6 s. It exercises the current input sampler and simulation, including their different rate/expo policies. No hardware radio or human flying-quality judgment is implied. The [complete samples](session/session-results.json) include surface angles, inputs, states, and extrema.

For illustration, normal-rate positive-roll pulse peak roll rates were about 68.64°/s for the Stik and 167.22°/s for the Jet. Different aircraft, speeds, and control policies can legitimately produce different rates; this audit does not label that difference a defect.

Independent principal moments were `[0.1149297783,0.3874197810,0.4842504253] kg·m²` for the Stik and `[0.6863632601,2.4641959071,3.0586153786] kg·m²` for the Jet. Both satisfy positivity and the principal-moment triangle inequalities. Tilted free fall matched `½gt²` and `gt` after 1.25 s to approximately `10^-14 m` and `5×10^-14 m/s`. Torque-free rotation with fixed rotor momentum conserved inertial angular momentum within `2.95×10^-11 N·m·s` over five seconds. The [invariant script and logs](../../../research/physics-audit-2026-10-14/numerics-ground/README.md) retain the setup.

The turbine's missing transient mounting reaction remains an **open-system modeling question**. Adding a closed-solid-rotor `−dH/dt` term without accounting for inlet/exhaust angular-momentum flux is not justified by the present evidence. Current Jet wheel brakes and retractable-gear interlocks do exist; an old ground-physics limitation list must not be read as current proof that they are absent.

## Reproduce and retain evidence

Run from the repository root with the audited working-tree inputs and installed Godot binary. These commands regenerate audit outputs; copy the existing evidence directory first if preserving this dated run. The probes call production functions without modifying production files.

```powershell
$auditRoot = (Get-Location).Path
$auditEngine = Join-Path $auditRoot '.tools/Godot_v4.7.2-stable_win64_console.exe'
$auditScripts = Join-Path $auditRoot 'research/physics-audit-2026-10-14'
$auditEvidence = Join-Path $auditRoot 'docs/research/physics-audit-2026-10-14'

& $auditEngine --headless --path app --audio-driver Dummy --script "$auditScripts/aero_edges.gd" -- "--out=$auditEvidence/aero-edges.json"
& $auditEngine --headless --path app --audio-driver Dummy --script "$auditScripts/propulsion_edges.gd" -- "--out=$auditEvidence/propulsion-edges.json"
& $auditEngine --headless --path app --audio-driver Dummy --script "$auditScripts/runway_crosswind.gd" -- "--out=$auditEvidence/runway-crosswind.json"
& $auditEngine --headless --path app --audio-driver Dummy --script "$auditScripts/session_probe.gd" -- "--out=$auditEvidence/session"
python tools/flight_log/flight_log.py replay "$auditEvidence/session/stik-normal-yaw.orfl" --out "$auditEvidence/session/stik-exact"
python tools/flight_log/flight_log.py replay "$auditEvidence/session/jet-normal-yaw.orfl" --out "$auditEvidence/session/jet-exact"
python research/physics-audit-2026-10-14/reproduce_h12.py
python research/physics-audit-2026-10-14/run_checks.py
python research/physics-audit-2026-10-14/summarize.py
```

The H12 reproducer intentionally captures the original failing check and an isolated passing test copy; its wrapper completion does not mean the production test passed. Source and evidence hashes are indexed in [artifact-manifest.json](artifact-manifest.json).

| Evidence | Location |
|---|---|
| Lead numerical summaries | [lead-summary.json](lead-summary.json) |
| Aero force defect | [aero-edges.json](aero-edges.json), [run log](aero-edges.log) |
| Turbine joins / inlet velocity / stopped propeller | [propulsion-edges.json](propulsion-edges.json), [run log](propulsion-edges.log) |
| Crosswind runway initialization | [14-case direction sweep](runway-crosswind.json), [run log](runway-crosswind.log) |
| All 28 live-session cases | [session-results.json](session/session-results.json), [run log](session/run.log) |
| Stik baseline and exact replay | [.orfl](session/stik-normal-yaw.orfl), [report](session/stik-exact/replay.json), [CSV](session/stik-exact/flight.csv) |
| Jet baseline and exact replay | [.orfl](session/jet-normal-yaw.orfl), [report](session/jet-exact/replay.json), [CSV](session/jet-exact/flight.csv) |
| Aerodynamic review | [aero/README.md](aero/README.md) |
| Data and propulsion review | [data-propulsion/README.md](data-propulsion/README.md) |
| Numerics and ground review | [numerics-ground/README.md](numerics-ground/README.md) |
| Initial / final working-tree status | [before](git-status-before.txt), [after](git-status-after.txt) |

The next justified work is to repair F01/F02, isolate and repair F11, and correct the F03 comparison under independent numerical checks, then establish the missing aircraft-specific evidence and capabilities. Any physics candidate must retain its original `.orfl`, verify exact baseline replay, and use the same tick/input tape for comparison under the [flight-logging workflow](../../FLIGHT-LOGGING.md). Candidate agreement, recovered prefixes, and software test counts do not establish physical equivalence. No code or physics changes are part of this audit.

## Remediation plan

**Date:** 2026-10-14. **Status:** proposed; implementation and acceptance are pending. **Coordinator:** physics/simulation, using the existing `VAL-` namespace. **Scope:** F01–F11, the two audited aircraft, and the shared contracts needed to keep other and future vehicle families consistent. This is a closure plan attached to the audit, not a new vehicle framework or a replacement for the [ownership registry](../../README.md#tracks-plans-and-step-ids).

The required outcome is a simulator whose declared physical model is continuous where the mechanism is continuous, obeys its stated momentum/energy balances, uses consistent state and geometry, and fails explicitly outside its supported domain. Aircraft-specific realism additionally requires independent measurements. A software repair may close a demonstrated defect while its new force law or coefficients remain experimental.

The sections below specify implementation choices, alternatives that require evidence, and release gates. They do **not** claim that all possible defects have been found, that the future vehicle families have been audited to the same depth, or that passing a test establishes “100% realism.”

### Ownership, boundaries, and delivery register

Use the [aircraft contract](../../../AIRCRAFT_CONTRACT.md), [standardization plan](../../plans/aircraft-standardization.md), [turbine plan](../../plans/turbine-realism.md), [propulsion guide](../../PROPULSION-CORE-PLAN.md), [Glow guide](../../GLOW-ENGINES.md), [atmosphere guide](../../ATMOSPHERE-PLAN.md), [helicopter plan](../../plans/helicopter.md), and [ground-vehicle plan](../../plans/rc-monster-truck.md) as the authoritative homes for their implementation status. The IDs below track audit closure and cross-track dependencies only. Add repair substeps under the owning track when implementation begins.

| ID | Work and owning boundary | Proof/status |
|---|---|---|
| VAL-AUD-R00 | Freeze the reproduction baseline, create focused failing contracts, inventory consumers and source generators. Physics/FL with each affected owner. | Pending. Exact baseline replay, preserved source/config identities, minimal red cases for F01/F02/F03/F11, explicit capability matrix. |
| VAL-AUD-R01 | Correct H12's legacy comparison contract, keeping enabled-polar validation separate. Physics, F03. | Pending. Original failure reproduced; H4/H12 legacy comparisons pass before any force-law change; polar suites still active. |
| VAL-AUD-R02 | Repair local surface-force and wake-driver continuity. Physics with AS; F01. | Pending. Cartesian limit, component-load, wake, moment, energy, blend, and fleet gates below. |
| VAL-AUD-R03 | Repair inlet-force continuity, then local inlet kinematics in separate slices. AV-24/physics; F02/F07. | Pending. Continuous vector law, scalar/vector consistency, local-point oracle, stage/session coverage, declared off-axis scope. |
| VAL-AUD-R04 | Isolate and repair runway equilibrium failure and transactional installation. Physics/GP with AV; F11. | Pending. Feasibility diagnosis, bounded solver, original crosswind case, stationarity and failed-start lifecycle proofs. |
| VAL-AUD-R05 | Qualify mass/reference-datum and accepted-state interfaces for finite resources. AV-10b/AS/physics, coordinating NITRO, HELI, RCV, FL and CR. | Pending. Independent open-system fixtures, complete consumer list, stage/endpoint rules, versioned layout and rollback contracts. |
| VAL-AUD-R06 | Add a source-backed Stik wash candidate, then qualify a shaft/fuel/wash composition for the same installation. G2/NITRO/physics with Stik data owner; F04/F06 and Stik F05. | Pending. Low-speed authority, shaft-work/windmilling, fuel and combined-state tests; installation measurements remain a separate gate. |
| VAL-AUD-R07 | Integrate finite Jet fuel and causal engine lifecycle. Existing AV-10a/b/c, AV-22, AV-05b and AV-27; Jet F05. | Pending. Depletion, changing mass/CG/tensor, engine rundown, contacts, UI/audio, replay and actual-session gates. |
| VAL-AUD-R08 | Implement shared flap capability through AS-15/TT-14, then authored Jet AV-09 installation. F10. | Pending. Actual actuator state, flap-on aerodynamic data, trim/landing loads, neutral parity, saved variants and recording compatibility. |
| VAL-AUD-R09 | Add an explicit vertical atmosphere mode under M5-ATM-4. F09. | Pending. Independent column checks, absolute-altitude datum, one coherent stage environment, old uniform-mode parity. |
| VAL-AUD-R10 | Identify aircraft and installation parameters, quantify uncertainty, validate on withheld data. DATA/VAL, AV-21/29, NITRO and ground owners; F08 and physical gates for other findings. | Pending. As-built measurements, source/uncertainty register, sensitivity, identifiable fits and independent validation by domain. |
| VAL-AUD-R11 | Qualify fleet combinations, lifecycle, performance and clean exports; decide promotion separately for each capability. Physics/AS/FL with HELI/RCV/UI/AUD/HUD/CR/DT. | Pending. Shared-contract regressions, family-specific recordings, bounded cost, fresh-checkout/export proof and published remaining limits. |

Start R10's source collection alongside R00. Implement R01 before changing aero. R02 and R03 may proceed independently in their kernels; combine them only for R04's cause-isolation experiment. R04 instrumentation can begin immediately, but its final acceptance uses the corrected force laws.

R05 precedes variable-mass production integration in R06/R07. The stateless baseline-Stik wash experiment can precede R05, after R02. Dynamic wash, coupled shaft, fuel and wheel-state composition cannot skip R05's layout/lifecycle review. R08 follows AS-15's existing Timber-first sequence; Jet-specific flap code must not bypass it. R09 can be developed independently, then must be exercised with the propulsion and fuel candidates. Each delivery runs its own relevant regressions; R11 adds the combined release gate.

Each implementation PR should contain one mechanism, its focused evidence and its necessary interface changes. Keep pure refactors, changed equations and aircraft parameter identification distinguishable. Coordinate shared session/schema files through their owners; parallel contributors should work on separate kernels, research fixtures or owned generators. Do not combine turbine, aero, fuel, controller shaping and UI tuning into one candidate.

### Existing architecture to reuse

| Current seam | Reuse | Boundary that must remain explicit |
|---|---|---|
| [Simulation](../../../app/sim/simulation.gd) | Float64 body state, 240 Hz default, coupled RK stages, validation, rollback and accepted-step observation. | A model repair does not justify replacing the integrator or switching simulation state to Godot rendering vectors. |
| [Propulsion runtime adapter](../../../app/sim/aircraft_propulsion_runtime.gd) | Family dispatch, continuous evaluators and committed observations. | It currently composes one installation. Multiple engines/resource networks need an explicit contract extension. |
| [Glow flight](../../../app/physics/glow/flight.gd) and [fuel mass](../../../app/physics/glow/fuel_mass.gd) | Existing finite-fuel state, tank tensor arithmetic, fixed reference geometry, event handling and telemetry patterns. | Its co-moving-efflux/no-jet-thrust derivation is conditional, not a universal variable-mass law. |
| [Slipstream](../../../app/physics/slipstream.gd) and [wash transport](../../../app/physics/wash_transport.gd) | Tail-piece geometry, washed-minus-free loads and optional transported axial wake. | These are approximate laws; Glow currently rejects this combination. Stateful wake composition needs code as well as data. |
| [Control surfaces](../../../app/physics/control_surfaces.gd) and [actuators](../../../app/physics/control_actuators.gd) | Existing pilot-to-surface sign conventions and achieved deflections. | Current logical controls are not a general per-surface flap/mixer/servo network. |
| [Helicopter session](../../../app/sim/helicopter_flight_session.gd) and [rotor step adapter](../../../app/physics/rotorcraft/simulation_step_adapter.gd) | Shared Simulation with dedicated rotor/controller/inflow states, rotor-stop handling and versioned checkpoints (v4 at the final planning review). | Preserve rotor physics, phase, power lifecycle and its own recorder. Fixed-wing fuel/wake equations are not helicopter equations. |
| [Ground-vehicle session](../../../app/sim/ground_vehicle/session.gd) and [dynamics](../../../app/physics/ground_vehicle/vehicle_dynamics.gd) | Separate fixed-tick transaction, 31-state vehicle, road/contact model, checkpoint/recording and pinned evaluator backend. | Preserve sprung/unsprung masses and generalized dynamics. The optional native evaluator is not another time integrator. |
| [Module registry](../../../app/data/schema/aircraft-modules-v1.json), aircraft loaders and [model generator](../../../research/aircraft-standardization/build_models.py) | Explicit capabilities, physical identities, conformance and generated visual bindings. | Model bindings are not a replacement for aircraft physics generators. Unsupported module combinations must reject before flight. |

Shared code should express a demonstrated common calculation or boundary. Extract it after comparing at least two real consumers; do not require every vehicle to use an aircraft force model, identical control channels, or one serialized state array.

### R00/R01 — Baseline and trustworthy verification

1. Preserve the original audit manifest, source identities, raw results, both baseline `.orfl` files and their exact-replay reports. Before implementation, capture the actual working tree, generated inputs, engine version and affected native-backend identity. Resolve concurrent changes by reviewing them, not overwriting them.
2. Promote the F01/F02/F11 reproductions to small deterministic regression cases. Keep the first failing version and numerical output in the owning evidence directory. Add expected invariants derived independently of the production expressions; reproducing the implementation in a test is not an independent oracle.
3. Repair [test_aero_flow.gd](../../../app/tests/test_aero_flow.gd)'s explicit legacy-model projection: remove `envelope.wing_polar` from both compared legacy inputs, alongside the already enumerated unsupported options. Assert the known projection rather than silently deleting every unfamiliar field.
4. Require H4's 20,000 and H12's 20,001 legacy comparisons to pass on the unchanged force law. Keep [test_wing_polar.gd](../../../app/tests/test_wing_polar.gd) and [test_wing_polar_session.gd](../../../app/tests/test_wing_polar_session.gd) exercising the enabled Jet polar. Do not remove the polar from the production aircraft or rewrite the frozen oracle to match a failing implementation.
5. When R02 intentionally changes the local law, preserve a clearly identified legacy regression lane and add independent tests for the new law. Byte equality to an obsolete local-force equation is no longer a valid acceptance requirement for that changed domain. The untouched attached/global branch and genuinely unchanged configurations still require their original parity.
6. Review stale operating claims in the owning documentation as part of the affected delivery. For example, AV-28's current “absent gear” blocker conflicts with the working AV-09 gear/brake path; dynamic-wheel compatibility descriptions also need checking against runtime. Keep historical findings dated and correct current guidance in its own home.

### R02 — Continuous aerodynamic loads and wake coupling

**Target:** eliminate F01 throughout the shared local-flow path without replacing missing physics with an angle clamp.

Use a declared orthonormal section frame and the air-relative velocity at its application point. Here “span direction” means the orthogonal complement of the chosen chord/normal plane, not an assumed geometric tangent to a swept leading edge. The first repair retains current strip geometry as an explicit straight-strip approximation; accurate swept/dihedral local flow requires sourced per-station positions and orientations, not merely rotating the basis. The structural-to-body-FRD conversion must occur once. Separate the existing two-dimensional section law from explicitly modeled spanwise/body resistance. For chord velocity `u`, normal velocity `w`, section area `A`, chord unit vector `t`, normal unit vector `n`, and declared positive section-moment axis `s_m`:

```text
Vp = sqrt(u² + w²)
F_section = 0.5 rho A Vp [CL (w t - u n) - CD (u t + w n)]
M_section = 0.5 rho Vp² A c_ref Cm_ac s_m
M_about_O = r_O_to_surface × F_section + M_section
```

Here `Cm_ac` is the bounded pure-couple coefficient about the declared aerodynamic center and `c_ref` its reference chord; the force arm uses that same application point. With bounded coefficients and this pressure scaling, both dimensional force and section couple have a unique zero limit as `Vp → 0`. Do not treat `atan2(0,0)` as a physically identified incidence. Give the degenerate branch an explicit zero section-load result and a diagnostic flag. This proposal is a model decomposition: it does not establish that the real wing has zero spanwise resistance.

The implementation must cover the following connected consumers:

- Wing strips, horizontal tail and vertical tail, including the correct plane for each surface; local application-point velocity includes angular rate.
- The scalar tail calculations in slipstream, so washed and free tails use the same corrected law and arms. A helper must have real shared consumers and preserve accepted summation behavior where the equations are unchanged.
- Ground effect, optional wing polar, section pitching couples, flap increments when added, and the global/local blend. Sweep the blend boundaries and reverse-flow angle wrap as well as the demonstrated spanwise boundary.
- Strip diagnostics and offline curves: report the force actually applied, its pressure/area convention and model domain. Avoid a diagnostic `q` convention that disagrees with the force.
- Induced-flow coupling and both instantaneous and lagged downwash. The current unweighted average of `CL` is path-dependent even when dimensional wing lift vanishes; changing drag alone is incomplete.

Define the wake quantity from the same force-producing strip evaluation. Prefer a dimensional induced-velocity or qualified circulation representation for the wider local-flow domain. For example, `Gamma_equiv = 0.5 Vp c CL` vanishes with section speed; it is an equivalent-force proxy until its interpretation as bound circulation is justified in the applicable attached/separated/reverse-flow domain. A sourced influence operator may then map qualified circulation to induced velocity.

Fix the induced coupling **before** forming downstream wake quantities: the current angle-based map lets a stagnant strip's undefined angle alter another, loaded strip's coefficient. Replacing only the final mean `CL` cannot remove that influence. Use a continuous loading-based coupling, or an explicitly qualified continuous removal of a degenerate source, and verify mixed stagnant/loaded strips. Preserve the current map only in the domain where the new derivation establishes its equivalence.

If an initial compatibility adapter retains a normalized lift/downwash state, specify its reference pressure, supported forward-flow domain and continuous zero-reference behavior. Dividing by a vanishing pressure, retaining raw mean `CL`, or hiding the singularity with a tiny arbitrary denominator is unacceptable. Verify the instantaneous target, lagged state, tail forces and reset/trim initializer together. A new wake state meaning requires a new law/layout identity even if its array length is unchanged.

Author spanwise drag only from an explicit component geometry/area convention and applicable coefficients. Do not reuse the normal-flow `CD90` with planform area as an edge-on drag coefficient, or infer it directly from `CY_beta`. Inventory existing fuselage and global side-force terms first to avoid counting the same resistance twice. A projection-only candidate can be software verified, but must retain an explicit unvalidated side-flow domain until this data gap is resolved.

**Closure evidence:** reproduce both audited 20 m/s cases; approach each boundary from both signs and multiple Cartesian paths, including mixed body rates, one locally stagnant strip, vertical-tail spanwise flow, and a tail in active propwash. Sweep shrinking `epsilon/V` from `10^-2` to `10^-9`; forces, moments, wake targets and active wake states must converge to the exact-boundary solution without a finite plateau. As an initial numerical gate at the smallest perturbation, require normalized force/moment differences below `10^-7`, using fixed nonzero case scales `q_ref S` and `q_ref S L`; report absolute errors too. This is an engineering continuity tolerance, not a physical error bar.

For isolated section tests, require `F_drag · v_plane = -0.5 rho A CD Vp³`, `F_lift · v_plane = 0`, and the application-point power identity in the verification matrix below. Add a disposable mutation that restores the old full-speed drag and confirm the boundary regression fails. Compare attached flight, stall onset, spin-entry probes and trim separately; no retuning of aircraft coefficients in this repair slice.

### R03 — Continuous turbine capture and correct inlet kinematics

**F02 first:** a nonnegative captured mass flow and its inlet momentum must belong to one declared continuous law. Remove the `u > 0` switch on the whole vector; changing only the scalar axial correction does not repair transverse loads.

The preferred first candidate is a versioned continuation of the existing forward-flight model:

```text
v_in = local air-relative velocity at the represented intake
u_in = dot(v_in, engine_axis)
F_inlet = -mdot_capture(N, environment, u_in) * v_in
F_total = F_gross_exit + F_inlet
M_O = r_exit × F_gross_exit + r_intake × F_inlet + supported pure couples
```

Initially retain the existing nonnegative mass-flow map and its positive-axial ram-rise law; evaluate a continuous full-vector continuation through `u_in = 0`. No incidence-dependent capture factor is introduced without sourced data. This preserves the present positive-axial result at fixed input flow while removing the demonstrated jump. For this versioned candidate, scalar axial thrust becomes `gross_thrust - mdot_capture * u_in`, with signed `u_in`; the old clipped reverse-axial result intentionally changes. Its crossflow/reverse-flow validity remains an estimated installation model. It must not be presented as identified inlet physics.

Compare that candidate with an explicitly one-dimensional fallback, `F_inlet = -mdot max(u_in,0) axis`, which is also continuous but removes all crossflow capture force and changes the positive-axial off-axis domain. Retain the vector candidate unless source evidence or the declared supported domain justifies that reduction. Record the chosen law, its supported incidence range and the tradeoff in the owning AV decision/evidence. A smooth gate selected only to conceal the discontinuity is not evidence for a capture law.

Make scalar `thrust()`, vector loads, trim diagnostics and displayed force use the same model/projection convention, including reverse inputs. Do not allow the scalar API to keep clipping negative axial flow while the vector law applies signed momentum. Keep static thrust, ram rise, installed loss and external airframe drag separately attributable. Published static engine endpoints do not identify the two Avanti intake mouths' crossflow capture.

**F07 in a separate slice:** derive and implement the velocity at the modeled intake point:

```text
v_in = v_O + omega × r_intake - R_inertial_to_body * wind(x_intake, t)
```

Here `v_O` is the body-resolved inertial velocity of a datum fixed in the structure, and the intake is fixed relative to it. The present constant-mass CG route meets that assumption. A changing-CG state needs R05's derived kinematic transformation, including relative geometry motion where required; do not substitute a moving coordinate origin blindly. Convert the authored offset once and use that same reference for the arm. Under uniform wind and fixed CG this reduces to the familiar local correction to CG-relative air velocity. A future spatial wind query must use the point position consistently.

Pass stage-local body rate and reference geometry through the common dynamics dispatch and continuous turbine evaluator, including trim and runway-start paths. Retain distinct inlet and exit arms; their positions do not become identical because both contribute to net thrust. The current centroid approximation does not resolve unequal flow between intake mouths.

Before expanding the engine model, derive a control-volume momentum budget with inlet, exhaust, fuel, pressure thrust and stored rotor/gas angular momentum. The [NASA thrust relation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/) supports this bookkeeping, not an Avanti-specific off-axis force map. Preserve the installed net-force surrogate once; do not add exhaust momentum a second time. AV-26 owns any transient mounting-reaction extension: adding a closed-rotor `-dH/dt` alone remains unjustified.

**Closure evidence:** sweep axial speed through zero with lateral and vertical flow at stopped, idle, intermediate and maximum RPM; test both signs and independent axis rotations. Check vector/scalar agreement in their declared common domain and unchanged static/forward-axial values. For F07, compare the audit's `q = ±2 rad/s` cases with independent point-velocity and `r × F` calculations, then exercise real RK stages and session traces. Zero-offset/zero-rate cases must reduce to their prior kinematics. Track F02 continuity, F07 kinematics and off-axis physical validation as separate acceptance results.

### R04 — Feasible, bounded, transactional runway starts

**Do not assume F01 or F02 is the sole cause of F11.** Instrument the current [ground solver](../../../app/physics/ground_start.gd) before changing its acceptance rule. Its residual norm is the maximum absolute component, `L-infinity`, across mixed linear/angular acceleration units. The original numerics note's “Euclidean” wording is corrected in this planning amendment; no raw result changes.

Retain a bounded diagnostic record: six residual components with units, initial/final pose, iterations, total force evaluations including numerical Jacobians, variable scales, Jacobian/pivot indicators, accepted step lengths, contact active sets, each wheel's compression/normal force, and anchor demand versus its friction limit. Hold wind/random state fixed throughout a residual solve.

Run a controlled 2×2 experiment: original/corrected aero versus original/corrected turbine capture, with unchanged aircraft inputs and solver. Separately compare the original and revised solver on the same residual function. Use these runs to distinguish a force-law boundary, a bad Jacobian/step, and a contact configuration for which no feasible static equilibrium has been demonstrated.

For a numerical repair:

1. Scale translations by a declared characteristic length `L`, rotations by radians, linear residuals by `g`, and angular residuals by `g/L`. Retain dimensional per-component errors in diagnostics. Use local rotation increments for a revised pose parameterization; do not introduce an Euler singularity as a solver workaround.
2. Choose variable-specific finite-difference steps from a scale/sensitivity study; compare at multiple step sizes. Identify stencils crossing contact/friction active sets rather than treating a discontinuity as a smooth derivative.
3. Add bounded backtracking or a trust-region step, rank/conditioning rejection, physically feasible compression/pose bounds and deterministic fallback ordering. Preserve the requested runway spot and nominal heading: for the audit fixtures, predeclare at most 10 mm horizontal displacement and 0.1° heading change, additionally bounded by each anchor's admissible elastic strain/friction region. These are placement budgets, not measured tire properties. The present Stik start intentionally permits millimeters of elastic displacement; fixing all six pose values would change that mechanism. Log achieved-minus-requested pose and reject solutions outside the admitted launch bounds. Other installations need justified bounds before qualification. A continuation seed from smaller wind may help, but the final candidate must satisfy the exact requested wind and the same tolerances; it cannot change input direction to avoid the force boundary.
4. Set an initial engineering budget of 64 iterations per stage, eight backtracking trials per iteration and 4,096 total residual evaluations across the entire start attempt, including seeds and Jacobians. Validate cost and revise the documented budget if necessary before promotion; never use an unbounded retry loop.
5. Predeclare a dimensionless residual target of `10^-9` for the new scaled solver and tie it to dimensional force/acceleration and two-second stationarity error budgets. Retain or strengthen existing stationarity assertions. A small cost change, small step or optimizer “success” is insufficient without residual and contact-feasibility acceptance.

Use the existing pinned research environment for an independent offline comparison, such as bounded [SciPy 1.11.4 least_squares](https://docs.scipy.org/doc/scipy-1.11.4/reference/generated/scipy.optimize.least_squares.html) with explicit scales and evaluation caps. Its local minimum is not proof that an equilibrium exists or does not exist. Keep the production helper small and deterministic; this task does not require shipping SciPy or inventing a general optimization library.

Classify contact infeasibility only with an independently verifiable bound or certificate: for example, required tangential force/moment outside a conservative achievable contact-wrench set for the stated pose/support/normal-load envelope, with a margin above numerical error. A certificate for one pose does not exclude every allowed pose. Without such a bound, exhausted iterations, bad conditioning, active-set cycling or an unsatisfied placement budget remain unresolved numerical/initialization outcomes, not a physical crosswind limit.

Separate solve/validate from installation. Prepare candidate body/aux/engine/control/anchor states and a structured outcome before mutating the session. Distinguish converged, invalid input, contact infeasibility actually established, and numerical/unresolved failure. On rejection, publish no runway-success event, partial pose, trace row or changed crash state. Ordinary transactional launch retains the previous valid session. The legacy `reset_on_runway` helper currently promises an airborne fallback; either preserve that as an explicit, separately committed fallback with its own reason, or migrate its callers/tests deliberately. A printed error plus an ambiguous boolean is insufficient user feedback.

**Closure evidence:** both audited aircraft at calm, 0.5, 1.0, 1.5 and 2.0 m/s; exact perpendicular flow from both sides; direction offsets `±0.001°`, `±1°`, and aligned wind; the actual default runway coordinates and explicit achieved-pose assertions. The original 1.5 m/s Jet case must reach a verified feasible start, or retain an explicit unresolved failure until its cause is established. Do not redefine that failure as a physical crosswind limit. Higher winds need not be forced into a static state if friction/support cannot supply it. Accepted starts must pass stationarity, checkpoint/restore and repeated-run determinism. Rejected starts and explicit fallbacks require separate lifecycle tests.

### R05 — Mass properties, state, and cross-system contracts

Define these semantic contracts before adding resource states. They are proposed interface requirements, not API names already implemented:

| Contract | Required content and invariant |
|---|---|
| Prepared model | Immutable source/config identity, law versions, geometry, units, reference datum, module dependencies and stable physical IDs. Preparation may cache constant coefficients; it cannot cache evolving fuel, RPM, air or contact state as constants. |
| Stage context | Body pose/velocity/rates, continuous states, stage time, held effective command, mode and coherent environment sample. All coupled forces/derivatives use the same RK stage. Repeated evaluation cannot advance RNG, consume fuel or emit events. |
| Load result | Force, application point, pure couple and stated reference; internal exchange versus external load distinguished. Accumulate each contribution exactly once into the family derivative. Diagnostic component breakdown may be optional to avoid per-stage allocation overhead. |
| Mass result | Current mass, first mass moment/CG, full inertia tensor, datum convention and any required flux terms. Rigid-aircraft and generalized vehicle adapters need different equations even when they share tensor arithmetic. |
| Candidate step | Proposed body/internal state, modes, contact observations and ordered events for the entire tick. Validate before commit; rejected work restores the preceding complete state. |
| Accepted observation | One committed tick/time, matching state/loads/mass timestamps, achieved controls, resource levels, mode, identity and structured failure status. Observers cannot re-evaluate forces, advance random state or alter physics. |

For fixed-wing finite fuel, prefer a reference point fixed in the structure. An explicitly identified initial wet-CG datum, as in the existing Glow route, can serve this role; it must not silently become the changing CG. Transform independently derived dry-datum and instantaneous-CG reference equations into that declared convention and compare them.

Derive mass, first moment and inertia from one inventory at each stage. If remaining tank items have masses `m_i`, structural positions `r_i`, and intrinsic tensors `I_i`:

```text
m = m_dry + sum(m_i)
h_O = h_dry,O + sum(m_i r_i)
c_O = h_O / m
I_O = I_dry,O + sum(I_i + m_i (|r_i|² Identity - r_i r_i^T))
I_CG = I_O - m (|c_O|² Identity - c_O c_O^T)
```

This is geometry bookkeeping, not the complete open-system equation of motion. Reuse the [AV-10b independent reference](../../../research/avanti-s/av10/README.md) and compare its fixed-datum and moving-CG forms. Reconcile the assumed spatial distribution of disappearing fuel with mass, first-moment and angular-momentum flux. A uniform tank shrink, a point pickup and liquid moving through lines are not interchangeable assumptions. Declare any neglected line/engine inventory and slosh error budget.

Account for net engine thrust once. Never subtract captured outside air from onboard fuel mass or add an extra rocket/exhaust term to a force that already contains it. Likewise, do not add `-I_dot omega` or `-mdot v` in isolation. The cancellation or retention of such terms follows from the chosen control volume and flux model. Under gravity, apply `m g` at the current CG: its moment about a displaced fixed datum is `c_O × (m g)`, whereas its moment about the instantaneous CG is zero. Do not retain that datum moment after recentering at the CG. Keep the existing constant-gravity scope unless a separate accuracy budget justifies changing it.

Audit **every** mass/reference consumer, not only the flight derivative:

- Aero, engine/intake/nozzle arms, rotor momentum and thrust-line torque use one reference convention. Geometry must not jump when the computed CG moves.
- Trim, runway support, wheel/hull/scenery/water contacts, impact impulse and damage energy must receive the appropriate dynamic properties. Current `FlightSession` prepares hull data and supplies `sim.mass/sim.inertia` to impact paths; adding fuel only inside a stage derivative would leave those consumers on their wet reference values.
- Mid-tick contact events need mass/internal state at the event's declared time. If the current collision crossing is an interpolation estimate, document a consistent bounded mass estimate too; do not label it an exact integrated event state.
- HUD load factor, energy, fuel, weight, CG and recorder channels use time-matched properties. Existing initial-build mass metadata may remain as reference metadata, clearly distinct from live mass.
- Reset, aircraft swap, field/weather change, trim start, runway start, failed preparation, pause, crash/afterrun and checkpoint restoration cover all internal states. No implicit refill on pause/resume or restore.

Use explicit state-layout builders and named offsets per admitted composition. Do not append wash states by guessing the generic rotor index in the 17-state Glow layout; do not overwrite wheel states when adding fuel/flaps. Freeze the layout/law identity in prepared models, traces and checkpoints. Unknown mandatory capabilities and unsupported combinations fail preflight.

A family adapter owns event handling. Fuel empty, rotor stop, battery cutoff and contact transitions may coexist; specify deterministic priority for simultaneous roots, left/right mode semantics, bounded event/substep counts and consumption of the remainder of the original tick. Never pick one existing `continuous_step` callback and silently discard another event mechanism. Preserve HELI's rotor-stop guarantees when extending its future resource path. Stage trials may use explicitly derived continuation values for root localization; accepted fuel/charge/RPM states must remain inside their physical domain.

**Closure evidence:** fixed mass reduces to the existing equations; independent full/half/empty tensor calculations and positive principal moments/triangle inequalities; off-center tank/force tests; no-force co-moving efflux fixture; constant net thrust with `m(t)=m0-k t` checked against `Delta v=(F/k) ln(m0/(m0-k t))`; fixed-datum/current-CG equivalence; gravity and rotor/body momentum budgets; contact/impact response at different fuel loads. Include rejection at each RK/event stage and demonstrate full rollback with no observer-visible partial tick.

### R06 — Stik shaft, propeller, fuel, and tail authority

The baseline Stik and generated Glow variants are different identified models. A `61FX` surrogate scaled from another engine is not a measurement of the audited installation; swapping to a different `55AX` or four-stroke profile does not validate it. Preserve the baseline identity and recording, and create separately identified candidates through the owning source pipeline.

**Slice A: tail wash with the existing baseline propulsion.** Author hub position, shaft direction, tail-piece geometry, immersion and wake assumptions with quantity provenance. The present non-Glow path can use the existing optional slipstream module; explicit zero thrust angles may still be required to define its axis. Obtain one stage-local thrust/torque result and use it for both propeller loads and wash. Washed-minus-free loads must use the R02 surface law, the same actual surface angles and downwash, and the same application points.

Test increments in elevator and rudder moment at 0, 5, 15 and 29 m/s for stopped, idle and high actual RPM. The desired change is causal dependence on local flow, not a hand-authored throttle-to-control gain. Preserve the existing free-flow tail response when the wash is inactive. Include engine cut and restart, forward/reverse flow and transport decay. A remaining wake after engine cut should evolve under its declared law rather than disappear because a boolean changed.

The existing wash is an actuator-disc/occupancy surrogate. Its swirl heuristics are not a closed angular-momentum balance; its forward-flow transport is not a complete transient wake. Review the stopped-prop/reverse-flow fading boundary before composing it with a new engine law. Record empirical gains and transport speed floors as estimates. If rotation/swirl is included, budget propeller torque, wake angular momentum and tail energy consistently rather than claiming all propeller work reaches the tail.

**Slice B: load-responsive shaft and stopped/windmilling propeller.** Evaluate the existing G2 shaft route and the matching finite-Glow route against the required installation behavior. Select one versioned engine law; do not sum two torque/governor models. Prepare matched engine torque versus RPM/throttle, installed propeller thrust/torque maps, rotating inertia, friction, idle/cut behavior and domain limits. Peak catalog power alone cannot identify a complete curve.

Use a coupled shaft/body derivative where rotor reaction is part of the model. Check shaft work, rotating kinetic energy, propeller work and losses together. The generic non-Glow propeller's current below-1-RPM zero-load branch is insufficient to close F06: provide an identified stationary-prop drag law and a bounded route through stopped rotation/windmilling, or retain an explicit unresolved stopped-prop scope. Torque/power coefficient extrapolation near zero RPM must not divide by RPM to generate arbitrary load. Preserve sign conventions through spin reversal only if that domain is actually supported.

Existing finite-Glow propeller kernels provide useful stopped/windmilling and energy-bound precedents; verify their applicability to the selected propeller before reuse. Do not apply a driven-propeller efficiency inequality outside its applicable operating quadrant. A propeller may exchange energy with the incoming stream during windmilling; the total shaft/air/body budget must still balance.

**Slice C: combine shaft/fuel/wash rather than enabling incompatible flags.** [Glow installation preparation](../../../app/physics/glow/installation.gd) currently rejects slipstream, its runtime callback bypasses generic wash composition, and its airframe call supplies no transported wash state. Implement a supported adapter before changing that capability. It must use one stage-local RPM, environment, propeller result, effective mass and achieved-control state; integrate selected wash variables alongside Glow and wheel states; and include every derivative in the same body step.

Reuse finite-Glow fuel semantics only after R05's consumer/impact review and evidence for the Stik tank. Engine cutoff and exhaustion must have their own mode/shaft/wake response. Maintain source identities, generator checks, trim/start behavior and unsupported-combination rejection. The baseline may remain an explicitly simplified model while the improved installation remains experimental; changing a catalog default requires R11 and physical qualification, not the mere existence of more equations.

**Closure evidence:** engine-off/on control authority and wake-delay data; measured steady RPM versus airspeed/throttle and transient response; static thrust/torque and engine-off propeller behavior; energy/momentum fixtures; full/partial/empty fuel; combined wash/shaft/fuel/wheel refinement; reset/checkpoint/replay and failure-mode integration. Keep software closure and installation validation separate for F04, F05 and F06.

### R07 — Jet finite fuel and engine lifecycle

Use the existing [turbine realism plan](../../plans/turbine-realism.md) for detailed ECU, thermal, supply and fuel steps. This audit adds integration gates rather than a competing turbine roadmap.

1. **AV-10a:** bind one onboard fuel resource to the actual inventory ID. Define usable versus unusable fuel, mixture density/units, tank distribution and initial fill. Consume delivered fuel from the selected engine mode, not throttle alone; catalog running flow must not be used as a universal cold/stopped law. The authored 1.28 kg divided by maximum-flow endpoint is only a nominal budget.
2. **AV-10b/c:** integrate remaining fuel with the continuous turbine/body state and R05 mass properties. Check the AV-10b reference assumptions against the real engine-level net-force surrogate. Retain structural positions and inlet/nozzle arms consistently as CG changes.
3. **AV-22/AV-05b:** define fuel-valve, combustion, rotating and cooling states with a causal stop/exhaustion path. Throttle zero remains idle where the ECU defines it; it is not engine OFF. Exhausting the modeled usable fuel removes that supply and exits steady RUN. Any residual combustion, hot-gas thrust or spool-down must follow explicitly accounted inventory/energy and a separately supported transient law; continuing the steady RUN thrust map is invalid. Rotor RPM/angular momentum must not be zeroed by the event. Fit cold/hot rundown and cooling to applicable evidence; do not fabricate a detailed thermodynamic map from two catalog points.
4. Localize empty-fuel events, apply the mode transition once, and integrate the rest of the tick. Use the turbine plan's event/refinement budget; an initial acceptance target is at most 0.1 ms empty-time error against an independent reference, with nonnegative accepted fuel and convergent trajectory errors. Account for simultaneous cut/crash/fuel events through the stated priority policy.
5. **AV-27:** expose committed actual RPM, engine state, thrust decomposition, fuel flow, remaining/consumed fuel, live mass and validity flags. Audio follows actual operating state; HUD fuel uses kg or a sourced mixture-volume conversion. Do not reuse the Glow premix conversion for kerosene.
6. Follow existing input/arming, controller-loss, pause, emergency and crash semantics. Decide whether any afterrun clock advances while flight is stopped and record that decision; presentation clocks must not secretly consume simulation fuel. Startup, shutdown and hot restart are engine events, not radio arming synonyms.

Keep pump/supply battery, pickup/hopper, slosh and a fully resolved thermal engine outside the minimal delivery unless their prerequisites and evidence exist. Stable inventory/installation IDs should permit future multiple tanks or engines without silently claiming that those topologies already work. Battery charge consumption does not reduce battery mass.

**Closure evidence:** constant-flow and variable-flow integrals, nominal/partial/empty starts, exact depletion tick, mid-step exhaustion, shutdown/restart where supported, no steady RUN-map leakage into cold/OFF modes, separately verified residual-thrust decay, full-tick consumption after an event, mass/CG/inertia trajectory, full/half/reserve trim and ground support, collisions at different fill levels, controller/terminal lifecycle, and versioned recordings. Physical acceptance still requires matched P100-RX revision, installed flow/thrust/rundown data and the aircraft's actual tank.

### R08 — Shared flaps, actuators, controls, and aerodynamic configuration

Follow **AS-15 → TT-14 → Jet AV-09** as the current standardization plan specifies. Extend the contract before enabling a physical flap module. Use a versioned optional extension only if closed v2 semantics remain intact; otherwise use the explicit successor schema and v2 adapter. The existing Jet visual `set_flaps` hook and `not_simulated` capability are not a functioning aerodynamic module.

Define stable surface/actuator IDs, hinge/span/chord geometry, signs, travel limits, detents, rate limits and control allocation. Keep pilot demand, mixer output, servo target and achieved angle distinct. Use achieved angles for both force calculations and rendering, preserving the model's stable node/hinge names. Add asymmetric surfaces or failures only through declared topology; a symmetric two-flap aircraft is not evidence that a general mixer already works.

Author flap-dependent lift, drag, section pitching moment, stall behavior and downwash from applicable data over angle and actual deflection. Reuse shared section interpolation only within its declared Reynolds/geometry domain. The current Jet clean NACA 0015 proxy is not an identified flap-on Avanti polar. Do not implement flaps as elevator offset, a uniform aircraft-wide lift multiplier or visual-only rotation. Update both the attached/global representation and local sections so their blend retains flap loads continuously. Audit reference areas, section coverage and coefficient moment reference: the contract's `mean_chord = S/b` is not automatically the mean aerodynamic chord.

Integrate control mapping with existing keyboard/gamepad/radio profiles and help UI; inspect current bindings before choosing actions. Logging already uses F10/F11 and Glow uses F6–F9, so do not assume those keys are free. Add channel/layout identity, actual servo state, trim initialization, checkpoint restoration, failure permissions and Workshop eligibility together. Avoid silently assigning a new command value in an old tape.

**Closure evidence:** zero-deflection module parity in the unchanged clean law; independent single-surface force/moment and deflection/hinge-axis sign cases; symmetric and mixed-control fixtures; measured or qualified flap-on tables; actuator stops/rates and noninstantaneous deployment; downwash/blend continuity; re-trimmed steady approaches versus identical-command deployment transients; go-around, landing and gear/flap combinations; visual/physics angle agreement; saved-variant, input, replay and reset compatibility. These sign tests do not validate hinge torque. Load-dependent servo motion, blowback or torque limits require sourced hinge-moment and actuator laws; do not infer them from section pitching moment or invent flap-speed thresholds.

### R09 — Atmosphere at the vehicle's actual altitude

Add an explicit M5-ATM-4 atmosphere mode while preserving the existing literal-reference and uniform-field modes. A vertical profile must declare its anchoring pressure/temperature/humidity data, height coordinate, interpolation, valid altitude interval and out-of-domain policy. A standard-atmosphere column is a controlled reference case, not an observed sounding.

Use absolute geometric elevation from the field/world datum and vehicle position, then the atmospheric model's required geometric/geopotential conversion. If NED down is zero at the field datum, geometric altitude is `field_elevation - down`; do not substitute terrain clearance/AGL or displayed density altitude. Confirm that relation for each session/field adapter.

Sample a pure, versioned environment query at the appropriate stage time/position. Aero, propeller, wash, engine, trim, start solver and HUD must agree on density and its timestamp. Use total moist-air density for aerodynamic mass flow, dry-air charge where the naturally aspirated engine law calls for it, and separate pressure/temperature inputs for a future corrected turbine map. Do not multiply electric motor torque by air density, or apply density corrections twice through a pre-scaled map and a consumer.

For the first column implementation, explicitly state whether all components use a common stage datum sample or local point samples; quantify the approximation. Spatial wind must likewise distinguish deterministic field queries from stochastic state advanced once per accepted tick. Repeated RK/residual calls must not draw new random samples.

Integrate weather identity, checkpoint/preference migration, reset/retrim and operating-domain messages. Helicopter adoption goes through its environment/rotor adapter and existing weather-capability restrictions. Ground vehicles currently receive road data rather than a flight atmosphere; only add air/thermal consumers when an actual vehicle model needs them. A shared environment identity is useful without fabricating aerodynamic forces.

**Closure evidence:** independent reference-column values at 0/50/500/1,000 m and supported limits; pressure/density continuity and positivity; field-offset equivalence; above-field versus elevated-field consistency; climb/descent using stage density; current uniform/reference exact parity; wet-density/dry-charge separation; trim/start infeasibility reporting; deterministic weather replay. Varying density alone does not validate Reynolds-dependent polars or engine altitude performance.

### R10 — Parameter identification and physical validation

Maintain one parameter/evidence register for each installation, linked to the existing authoring register and generators. For each load-bearing parameter, record units, source revision/hash, provenance kind, applicable configuration/conditions, uncertainty if known, consumer, and validation status. “Estimated,” “derived,” “borrowed” and “measured” describe different evidence; none alone establishes whole-aircraft validation.

| Evidence campaign | Required observations | What it can resolve |
|---|---|---|
| As-built geometry and mass | Actual airframe/engine/propeller revision, spans/areas/hinges/arms, itemized wet/dry mass, CG at multiple fill levels; independently checked inertia measurement or defensible mass-distribution reconstruction. | F08; R05 geometry/tensors. Account for virtual balance explicitly rather than treating it as a measured component. |
| Stik propulsion and wash | Matched propeller, engine RPM/throttle, thrust/torque, ambient conditions, cut/windmilling behavior, tail force/moment versus actual deflection at several RPM/airspeeds. | F04/F06; separate engine, propeller and tail-wake errors. |
| Jet engine and installation | Identified historical P100-RX/ECU revision, bare/installed thrust and fuel, multi-amplitude RPM transients, idle/cut/rundown, applicable inlet incidence data. | F02/F05/F07 and AV-21/24/29. Current BL specifications are comparison data, not a substitute installation. |
| Aero and controls | Trim, glide/drag, stall onset/recovery within a defined test envelope, aileron/elevator/rudder pulses, rate damping, flap-up/down conditions and speed/air-density uncertainty. | Lift/drag/moment/control derivatives and flap model, with separate pilot-input/servo delays. |
| Ground behavior | Static wheel loads/CG, tire radius, compression/rebound, rolling resistance, brake torque, surface-specific friction and taxi/landing observations. | Ground/start/contact calibration; the solver passing does not measure the coefficients. |
| Independent validation | New runs, conditions and maneuvers withheld from fitting, with instrumentation errors and reproducible analysis. | Stated-domain predictive error; not merely reconstruction of the calibration run. |

Use available primary manufacturer/manual/research data before creating new surrogate data. Keep incompatible revisions and conditions separate. Use existing free scientific tools for reduction, parameter fitting, uncertainty propagation and plots; reuse downloaded assets and published datasets where licensing and applicability permit. Do not build a custom plotting application for this work.

Run dimensional/range checks and global/local sensitivity before fitting. Check identifiability: for example, a climb trace alone cannot distinguish engine thrust loss, excess drag and wrong mass. Reserve data by run/condition before fitting, use independently observable parameter groups, and report correlations/confidence or unresolved bounds. Do not choose an uncertainty percentage without evidence. Freeze physical acceptance tolerances from measurement uncertainty and training-use requirements before inspecting held-out results.

Validate progressively: component → installed subsystem → complete aircraft → declared maneuver/ground envelope. Repeat geometry/source-generator checks after data changes. Preserve the measured/unmeasured distinction in the catalog and Workshop; an improved fit cannot silently promote a borrowed airfoil, guessed inertia or virtual ballast to measured status.

### R11 — Integration, recordings, and release acceptance

#### Preserve family-specific dynamics

| Family | Shared obligations | Family-owned implementation and required future extensions |
|---|---|---|
| Conventional fixed-wing, including Stik and Jet | Frames/units, declared datum, stage consistency, physical identities, accepted observations and reproducible inputs. | Existing FlightSession/Simulation adapters; selected aero/propulsion/wake/actuator/contact modules. Admit each new combination explicitly. |
| Helicopters and future rotorcraft | The same frame/mass bookkeeping utilities where valid, environment identity, accepted-tick semantics and evidence protocol. | Main/tail rotor aerodynamics, inflow/flapping, controller, phase, rotor/body exchange, skids and rotor-stop events remain HELI-owned. A future fuel adapter must update that coupled system and its recording; the fixed-wing tail-wash law is not rotor inflow. |
| Wheeled vehicles | Units, source identity, inventory arithmetic where applicable, transactional results and reproducible scenarios. | Retain suspension coordinates, sprung/unsprung mass, generalized inertia, tire/slip/friction, wheel/drivetrain energy, road contact and native/reference evaluator parity. Future combustion fuel enters this system's mass matrix; battery state of charge leaves battery mass fixed. |
| New topology: multi-engine, mixed controls, hybrid or multirotor | Stable installation/resource/actuator IDs and an explicit capability/dependency graph. | Add only the missing physical mechanism and a family adapter with complete lifecycle, conservation, schema and recorder support. Present single-installation code and fixed-wing channels do not already support these topologies. |

A common result vocabulary can expose accepted tick, state identity, effective input/environment, telemetry/events and failure reason. It must not replace the distinct body/internal layouts, ground-vehicle integrator ownership or checkpoint formats. Helicopters currently share WindField but restrict weather modes; the vehicle session currently has no air/wind input. Preserve truthful capability discovery in menus and Workshop.

For a future model, require: declared family and supported domain; valid sourced mass/geometry/energy/control/contact data; complete existing module combination or a reviewed new module; one independent mechanism fixture; family recording/restore support; visual/physical identity binding; and a stated software/physical validation level. Adding a new conventional airframe should remain principally a data/generator task. A helicopter, tracked vehicle or hybrid with different mechanisms must not be made to “fit” by tuning airplane coefficients.

#### State, replay, and observer migration

Follow the existing [flight-logging workflow](../../FLIGHT-LOGGING.md) and preserve the audit's original tapes. The following table describes fixed-wing `.orfl` experiments and report flags; other families need their own supported path:

| Experiment | Correct comparison | Invalid interpretation |
|---|---|---|
| Same source/config/layout | Exact replay, complete rows and `solver_changed=false`; investigate any mismatch. | A recovered prefix or incomplete run is not exact replay. |
| Compatible law/layout candidate | Same initial state and post-conditioning command tape, explicitly changed source/config identity. Solver changes should report `solver_changed=true`; aircraft-data-only changes keep the solver identity unchanged. | A deterministic candidate is not byte-equivalent physics or physical validation. |
| New state meaning/layout or initialization | Versioned scenario inputs with independently prepared valid initial state, or an explicitly derived and tested migration. Preserve the old reader/source path for historical replay/export. | Zero-filling new fuel/flap/wake states cannot reconstruct unrecorded history. The current `--candidate` CLI does not bypass layout/law compatibility checks. |

New trim comparisons answer a different question from identical-initial-state transients. Retain both where relevant, with each model's trim and initial fuel documented. Input shaping changes need raw device/sample replay or a dedicated input test: existing `.orfl` command tapes are already conditioned and cannot re-test a changed expo or calibration path.

Advance schema/law/layout versions when semantics change even if array length does not. Restore must preflight model, environment, backend, capability and layout before mutation. Define explicit migrations only when the missing values are physically recoverable. Old fixed-mass checkpoints cannot supply the fuel consumed by a model that never integrated fuel. Keep compatibility failure messages actionable.

Fixed-wing `.orfl`, rotorcraft's dedicated recorder/checkpoint, and the ground vehicle's recording/checkpoint remain separate contracts. Ground vehicles have a native replay path with their own identity checks; use that API and its actual result fields. The helicopter currently has recording/export and checkpoint/restore, but no equivalent flight-input playback API. Its initial regression gate is a deterministic authored command scenario plus checkpoint-continuation comparison. Full helicopter input-tape replay requires an explicit HELI/FL adapter, sufficient recorded commands/events, identity checks and a verified playback harness before it can be claimed or required for future model promotion. It does not block independent F01–F03 repairs.

An offline common-channel/unit comparison adapter may help analysis, but it is not an input playback implementation. Ground-vehicle native backend identity stays pinned in prepare/replay; changing backend mid-recording is not permitted.

Record load timing explicitly: a cached RK `k1` force is a start-of-tick quantity, while accepted state/fuel may be at the endpoint. Compute reported acceleration/load factor with mass at the matching time, or publish clearly distinct timestamps. Recorder/HUD/audio/render hooks must remain read-only and bounded. Demonstrate observer-on/off physics equality, including RNG and event sequences.

#### Verification matrix and proposed numerical gates

The tolerances below are software gates and initial engineering budgets. State absolute and relative scales in each fixture, justify any revision independently of the result being fitted, and keep physical measurement error budgets separate.

| Mechanism or boundary | Required independent evidence |
|---|---|
| Units, frames and geometry | Dimensional checks; structural↔FRD↔inertial transforms; known `r × F` moments; rotate the complete geometry/flow and verify force/moment covariance. A common uniform velocity added to vehicle and wind leaves air-relative forces unchanged. |
| Applied-load power | Verify `F·v_O + (r×F + C)·omega = F·(v_O + omega×r) + C·omega` for an isolated force/couple. Test passive drag signs separately. Do not impose a blanket negative-power rule on powered wash, active rotor systems or arbitrary control-couple models. |
| Mass, gravity and inertia | Preserve the audited ballistic and torque-free invariants; independent tensors and principal-moment realizability; R05 open-system fixtures and consistent potential/kinetic/flux bookkeeping. Remaining-aircraft energy alone need not be conserved when fuel leaves. |
| Force boundaries | R02 Cartesian continuity; R03 zero-axial and point-flow tests; RPM stop, wake fade, polar/blend, actuator stop and supported reverse-flow boundaries. Test exact boundaries and shrinking perturbations, not only a coarse grid. |
| Shaft/engine/rotors | Analytic torque/impulse and kinetic-energy cases, body/rotor angular momentum, resource/power budgets, zero-source rundown and declared stopped/windmilling domains. Keep turbine open-gas and mechanical propeller balances distinct. |
| Controls and trim | Known roll/pitch/yaw signs, measured actual angles, actuator limits/rates, trim residuals and feasibility; command-versus-achieved state through resets, failure overlays and recording. Re-run the original 28-session control scenario when a changed path affects it. |
| Ground/contact | F11 direction/magnitude matrix; static loads/friction feasibility, two-second stationarity, contact dissipation, brake/gear interactions, takeoff/landing and variable-mass impact cases. Do not use an initializer tolerance to recalibrate tires. |
| Time integration | Compare 120/240/480/960 Hz where supported with identical physical input timing. On smooth analytic fixtures, verify the expected fourth-order trend before roundoff. Event/clamp/contact cases need event-time and trajectory convergence, not a blanket fourth-order claim. |
| Hybrid events and rollback | Empty fuel/rotor stop/battery cutoff at the start, interior and end of a tick; simultaneous events, bounded remainder integration and no repeated zero-time event. Inject invalid candidate states on disposable fixtures and verify complete rollback/no accepted row. |
| Model composition | Supported catalog combinations and independent minimal fixtures; reject unsupported mandatory modules. Check legacy/inactive parity, enabled-polar behavior, shaft+wash+fuel+wheel state layout and Jet fuel+gear+flap+atmosphere composition when delivered. |
| Lifecycle and presentation | Aircraft/field/weather swaps, pause/resume, reset, failed preparation/start, controller disconnect/reconnect, crash/water and engine cut. HUD, controls help, visual hinges, propeller/rotor phase and audio match committed physical state. |
| Determinism and history | Exact replay under exact identities where a playback path exists; checkpoint-continuation and deterministic command scenarios otherwise; declared candidate differences; version rejection/migration; stable event ordering; no recorder side effects; native/reference evaluator agreement for affected ground-vehicle changes. |

Run focused suites before the full project check. The initial affected set includes `test_aero_flow`, `test_wing_polar`, `test_wing_polar_session`, `test_runway_start`, `test_retractable_gear_ground`, ground contact/friction/stiction, control/actuator, turbine, shaft/Glow/electric, checkpoint and trace suites. For shared-boundary edits include `test_heli_session`, `test_heli_ground_session`, `test_rcv_vehicle_dynamics` and `test_rcv_session` plus each family's lifecycle/recorder suites. Then run the canonical `app/test.sh` procedure from [TOOLS](../../TOOLS.md), including parsing all production GDScript. Tests of unsupported feature combinations should reject deliberately; do not weaken loaders to make a broad test matrix load.

Re-record a golden only for an intentional explained physical change after independent checks. Retain the previous result, predicted change and measured difference; a new golden cannot be the only proof. Keep deliberate mutations and draft scripts outside `app/` or on disposable copies.

#### Performance, generation, and release

Measure each changed kernel and complete family session on an identified target machine, without concurrent benchmark jobs. Record warm and cold preparation separately, stage-evaluation counts, time distribution including p50/p95/p99/max, allocation behavior, event/substep caps and recording cost. Apply the project's existing 500 microsecond simulation-cost target where that gate is defined; meeting the 4.167 ms period at 240 Hz does not establish that stricter target. Helicopter and ground-vehicle acceptance retain their own declared budgets and native-backend qualification.

The initialization solver has a separate startup cost/evaluation budget and must add no work to steady ticks. Cache validated immutable geometry and prepared coefficient data, not evolving mass or environment. If a native evaluator changes, retain a source/build receipt and independent reference parity before export; do not introduce another integrator or a second authoritative physics implementation.

Regenerate Avanti physics from [av06 inputs](../../../research/avanti-s/av06/inputs.json) and [derive_physics.py](../../../research/avanti-s/av06/derive_physics.py); regenerate Glow installations through [build_installations.py](../../../research/glow-engines/build_installations.py) and their registered profile sources. Follow the owning guide for every other aircraft. Where baseline data is directly authored, use its contract and provenance review; do not invent a generator or hand-edit a generated output. Schema/module changes must update their sources, runtime validators, Python validators, parameter consumers and conformance evidence together.

Verify generator `--check` modes and clean-checkout/export behavior using the canonical tools. Preserve exact dependency pins. Packaging must include admitted model/schema resources and matching native binaries; read-only old-recording export and a short actual-session recording/restore smoke belong in delivery proof, plus replay where the family provides playback.

Promote each capability only when its software, source, lifecycle and cost gates pass. Expose its actual evidence level: simplified, experimental/evidence-constrained, or physically validated for a named installation and envelope. Shared improvements must not automatically promote the experimental helicopter, laboratory helicopter profiles, synthetic electric conversions or truck to a stronger validation claim.

### Finding-by-finding closure and remaining decisions

| Finding | Software/model repair needed | Evidence required before a physical-realism claim |
|---|---|---|
| F01 | R02: dimensional force and all wake/induced-flow consumers have a unique Cartesian limit. | Applicable side-flow/section/wake model and coefficients; continuity alone is insufficient. |
| F02 | R03: continuous capture force and consistent scalar/vector projections. | Installed inlet capture/force behavior over the claimed incidence domain. |
| F03 | R01: honest legacy comparison plus independent enabled-polar coverage. | This closes a verification defect only; it cannot validate the Jet polar. |
| F04 | R06: propeller flow reaches actual tail controls through a supported composition. | Installed tail-authority/wake measurements and uncertainty. |
| F05 | R05/R06/R07: finite resource, correct mass properties, events, contacts and lifecycle. | Usable fuel, distribution/CG/tensor, delivered flow and endurance under matched conditions. |
| F06 | R06: identified load-responsive shaft and declared stopped/windmilling behavior. | Matching engine/propeller torque, RPM, drag and transient data. |
| F07 | R03: local intake-point kinematics in all stage/initialization consumers. | Justification of centroid versus resolved inlet representation and installed off-axis model. |
| F08 | R10: source/uncertainty register, reproducible fitting and held-out protocol. | Independent as-built component and complete-aircraft validation; no software-only substitute. |
| F09 | R09: coherent altitude-dependent environment with explicit old-mode compatibility. | Relevant atmosphere/engine/aero conditions for the claimed operating envelope. |
| F10 | R08: shared flap/actuator/input/aero/visual/recording path. | Actual flap geometry, coefficients, servo behavior and landing-configuration data. |
| F11 | R04: demonstrated cause, feasible residual/contact solution and transactional launch. | Separate ground/friction/wind-envelope calibration; a numerical start pass is not a crosswind rating. |

Before implementing each affected slice, record the bounded design decision in its owning work item: F01's side-flow/wake closure, F02's capture-domain policy, finite-fuel datum/flux assumptions, engine stop/cooling model, flap schema revision, vertical-atmosphere anchoring, and compatibility migration. These decisions cannot be settled by copying another aircraft's coefficients. Missing measurements block physical promotion of that domain, while independently justified numerical repairs can proceed.

### Planning evidence and document integrity

This follow-up performed source/contract review and cross-checked three delegated proposals against the current code. No production changes, aircraft retuning, new physical measurements or runtime regression runs are part of the planning amendment. All gates above are pending work, not new passing results.

The original [artifact manifest](artifact-manifest.json), source identities, logs, CSV and flight recordings remain unchanged. Its README hashes identify the original audit snapshot; the main README now also contains this plan, and the numerics note corrects “Euclidean norm” to the actual maximum-component norm. The [planning amendment manifest](remediation-plan-manifest.json) records before/after document hashes, linked-source snapshot hashes and document-link verification. It neither replaces the historical manifest nor supplies a complete executable source checkout.

Concurrent work changed ground-vehicle data/dynamics and the helicopter session after audit close. The planning review checked their affected family boundaries, including the new helicopter checkpoint revision; these changes are identified separately in the amendment manifest. They do not retroactively change the audit's fixed-wing results or constitute a new whole-family runtime audit.
