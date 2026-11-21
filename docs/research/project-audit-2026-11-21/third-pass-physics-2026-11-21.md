# A36 R3 — independent source audit of power, mass, numerics and computational cost

**Review date:** 2026-11-21. **Pinned source base:** \`9bb1f2c3dac2cead68445161f94513d965d12248\`, the existing [audit branch](https://github.com/bultodepapas/OpenRCsimulator/tree/audit/physics-math-aero-2026-11-21). This is a third **investigation-only** batch, not a production physics patch. Its evidence and pending gates do not modify the immutable original A36 PDF/ZIP or the R2 review.

**Methods:** inspected the actual source paths for the blimp's control-to-power-to-SOC calculation, Nitro ground vehicle fuel-to-body coupling, multirotor electric bus, full rigid-body Euler dynamics, mass inventory, rotorcraft rotor/inflow, wind spatial/thermal field, ground effect and vehicle contact integration. Compared the math with conservation and dimensional equations from M. Drela/MIT, NASA, FAA and MIT rigid-body dynamics. Ran [independent standard-library Python 3 calculations](probes/third_pass_power_and_mass.py), reflecting exact source equations and checked values from shipped airship/truck JSON. **No Godot stage/accepted-session/native/rendered flight tests were run in this batch.** Findings distinguish a source-invariant contradiction, an uncalibrated physical-fidelity omission, and unbenchmarked performance candidates.

## Findings/status

| ID | Finding | Evidence level | Recommended priority |
| --- | --- | --- | --- |
| **R3-F01** | Airship battery current is independent of instantaneous motor target at fixed rotor speed: dropping all pilot controls to zero can leave positive pack current during modeled rotor coast | **Source-confirmed coupling contradiction + independent numerical witness using shipped data**; accepted flight still to run | **P1** physics and power/telemetry |
| **R3-G01** | Nitro truck has a changing fuel-mass state but a constant body mass, CG and inertia, not a variable-mass mechanics model | **Source-confirmed model gap** with shipped-data scale and closed equations; exact tank datum unknown | **P2** fidelity |
| **R3-O01** | Nitro path duplicates the prepared model and control dictionaries **each simulation tick**, and repeats the copies for telemetry | **Source-confirmed allocation pattern, unmeasured CPU/RSS impact** | **P2** optimize only after profiling |
| **R3-P01** | Rotorcraft inflow, thermal/wind and CG inertia areas examined; selected equations are mathematically consistent within their stated domain | **Negative control / no promoted bug** | Preserve behavior; continue physical calibration |

## R3-F01 — Blimp at zero throttle: electrical demand persists while rotors coast

### Source path

1. [Mixer](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/airship/airship_dynamics.gd#L28-L68) sets side and stern-axial motor targets proportional to pilot throttle, and the lateral target proportional to yaw. At all-zero sticks, **all four speed targets are zero**.
2. [Stage battery](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/airship/airship_dynamics.gd#L196-L217) sums electrical demand based on **current** motor speed alone: \(P_{\rm request}=\sum_i P_{{\rm shaft},i}|n_i|^3/\eta_i\). It does not sample the targets or a motor electrical enable/ESC duty. It then solves the pack Thevenin equation for \(V,I\).
3. [Motor derivatives and SOC](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/airship/airship_dynamics.gd#L218-L242) are separately \(\dot n_i=(n_{{\rm target},i}V_{\rm scaled}-n_i)/\tau_i\) and \(\dot{\rm SOC}=-I/(3600C_{\rm Ah})\). With every target zero, the rotor's declared **unpowered exponential coast** has \(\dot n_i=-n_i/\tau_i\), yet the battery demand remains positive for any \(n_i\ne0\).
4. [Detailed telemetry](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/airship/airship_dynamics.gd#L323-L332) calls the speed-based demand \`battery.power_w\`. The model does not independently close the electrical supply against rotor shaft work and stored rotor kinetic energy.

This is distinct from **A36-F4**, the previously repaired after-depletion supply boundary, and distinct from **R2-I01**, the custom-resistance maximum-power construction. Here the stock battery itself draws modeled power **during a zero-command coast**. It is not proof of infinite/free energy or of an actual flyaway. It is a causal electrical/mechanical coupling inconsistency at an otherwise ordinary transient, independent of the previous zero-SOC bug.

### Numbers using shipped values

The [shipped 5 m blimp](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/data/airships/rc-blimp-5m.json) has four nominal shaft power values \(27,27,13,8.7\) W, efficiencies \(0.75,0.75,0.75,0.72\), a 3S battery with \(V_{oc}=12.6\) V at full SOC and \(R=0.045\,\Omega\), and a 2.2 Ah capacity.

For a common normalized rotor speed \(n\), at full SOC, the source computes

\[
P_{\rm request}(n) =
 \left(\frac{27}{0.75}+\frac{27}{0.75}
       +\frac{13}{0.75}+\frac{8.7}{0.72}\right)|n|^3
=101.416667\,|n|^3~{\rm W}.
\]

The high-voltage branch of the battery equation is \(V=[V_{oc}+\sqrt{V_{oc}^2-4RP}]/2\) and \(I=P/V\). The zero-throttle **initial stage** (no wall-clock integration) therefore predicts:

| All rotors at normalized speed \(n\) | New pilot throttle | Rotor shaft-speed derivative, port (s⁻¹) | Battery current | Requested electrical power |
| ---: | ---: | ---: | ---: | ---: |
| 0.00 | 0 | 0 | 0.000000 A | 0 W |
| 0.25 | 0 | −1.785714 | **0.125821 A** | 1.584635 W |
| 0.50 | 0 | −3.571429 | **1.009759 A** | 12.677083 W |
| 0.75 | 0 | −5.357143 | **3.437858 A** | 42.785156 W |
| 1.00 | 0 | −7.142857 | **8.294661 A** | 101.416667 W |

The entire pack current is **the same at fixed n whether the newly requested throttle is zero or one**, since the electrical solve does not read motor target. The motor-speed derivative *does* respond to throttle. The listed port derivatives use the shipped 0.14 s lag. All full-charge listed bus voltages exceed the end of the declared low-voltage cutoff band, so the cutoff scale is one in the coast case. Current still flows as SOC decreases, even though a physically disconnected ideal coasting motor should not draw traction power from the pack. A real ESC may apply braking or provide an auxiliary load; such behavior must be declared and modeled with signed current and a corresponding motor torque, not inferred from positive rotor speed.

**Reference:** Mark Drela's [first-order DC motor model](https://web.mit.edu/drela/Public/web/qprop/motor1_theory.pdf) defines motor current from applied terminal voltage and back EMF and shaft power as \(Q_m\Omega\), not from RPM alone. NASA/FAA rotorcraft resources distinguish external power supply from rotor's stored/mechanically transferred energy; see [FAA helicopter handbook](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/helicopter_flying_handbook/hfh_ch11.pdf). These equations constrain the BL model but do not calibrate its actual motors.

### Correction strategy and required acceptance

Do not simply force battery current to zero when throttle is zero if the actual intended ESC law is different. Define a **source/shaft topology**:

- \(\tau_{\rm aero}(n, V_{\rm axial})\) from a propeller load map, \(\tau_{\rm motor}(d,V_{\rm bus},\omega)\) from motor/back-EMF/resistance/ESC branch, and \(J_r\dot\omega=\tau_{\rm motor}-\tau_{\rm aero}-\tau_{\rm friction}\).
- \(\dot{\rm SOC}=-I_{\rm pack}/(3600C)\), with auxiliaries separated from motor power, reverse and regeneration explicitly admitted or refused, and battery OCV/polarization/internal-loss terms accounted.
- Preserve reference-law identity, finite charge events, the earlier F4 cutoff fix and replay. Do not infer rotor inertia or ESC losses from a single static thrust datum.

**Tests:** construct equal-RPM stage samples with throttle 0 vs 1 using real stock BL data; assert the expected current/torque direction under the newly declared motor law. Execute an accepted 240 Hz full-throttle-to-zero transition, measure \(\int V I\,dt\), rotor \(\Delta(\tfrac12J_r\omega^2)\), aerodynamic shaft work and losses. Check cutoff, rollback, checkpoint and recorded event/replay across timestep refinement. Until those tests, this finding is source-level+independent arithmetic, **not a demonstrated accepted-flight log**.

## R3-G01 — The Nitro truck burns fuel without changing its inertial body

[Ground Nitro step](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/ground_vehicle/nitro_dynamics.gd#L87-L141) advances fuel \(m_{f,k+1}=\max(0,m_{f,k}-\dot m_f\Delta t)\) in the extra state but advances the 31-value body through \`VehicleDynamics.step(_body_state(state), body_model, ...)\`. [_body_model_with_drive_torque](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/ground_vehicle/nitro_dynamics.gd#L224-L231) duplicates the same nominal model and changes drive torque and fade only—not mass, CG, inertia or fuel moment. This is a **deliberately reduced model topology**, not a numerical integration arithmetic sign error. However a displayed decreasing fuel mass and unchanged body inertia are physically inconsistent if represented as the same real vehicle.

The [shipped MONSTER CAR 2](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/data/vehicles/ground/monster_car_2.json) states \(m_{\rm sprung}=4.952\) kg, \(m_{\rm unsprung}=0.5186\) kg per corner and \(m_{f,0}=0.100\) kg. Thus

\[
m_{\rm nominal}=4.952+4(0.5186)=7.0264~{\rm kg};\qquad
\Delta W = (0.100~{\rm kg}) (9.80665~{\rm m/s^2}) = 0.980665~{\rm N}.
\]

Full-to-empty fuel is 1.4232% of nominal mass, not negligible for calibration-sensitive acceleration/support tests. Whether the 4.952 kg authored sprung mass included full fuel is **not established**; *either* the reference full fuel was included and the empty-mass state is overestimated, *or* it was not and the full-mass state is underestimated. The distance from the fuel tank to CG is not established, so no numerical CG-shift estimate is claimed. The [FAA Weight & Balance Handbook](https://www.faa.gov/sites/faa.gov/files/2023-09/Weight_Balance_Handbook.pdf) documents fuel as variable aircraft weight and the importance of its arm.

**Fix / test:** establish tank full/empty reference and position, fuel mass distribution, and dry inventory with a single datum; calculate \(m(t)\), \(\mathbf r_{\rm CG}(t)\), and positive-definite \(\mathbf J_{\rm CG}(t)\) from the shared [mass inventory](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/mass_inventory.gd). Qualify total mass, weight, center of mass, parallel-axis identity, elastic support equilibrium, gravity potential and full 240 Hz replay at full/half/empty fuel. Version recorded dynamics. This is a **fidelity gap with source-confirmed behavior**, not proof that the existing reduced truck is unplayable.

## R3-O01 — Repeated model copies in the Nitro hot path

[Every Nitro step](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/ground_vehicle/nitro_dynamics.gd#L104-L141) builds a fresh \`body_model = model.duplicate()\` through \`_body_model_with_drive_torque\` and also duplicates the control dictionary via \`_body_controls(...).duplicate(true)\`. [Telemetry](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/ground_vehicle/nitro_dynamics.gd#L144-L169) invokes the same adaptation again. At **240 Hz**, this entails at least **240 model copies and 240 deep control copies per simulated second**, plus telemetry-dependent additional copies. The number of bytes and runtime cost are **not measured**; \`model.duplicate()\` is a shallow dictionary copy, while the controls are deeply copied.

A refactor could pass one immutable model plus per-tick signed drive torque separately to the reference/native body evaluator, avoiding per-tick whole-model duplication. This crosses public adapters and backend identities, so run an isolated hot-path benchmark and compare exactly identical per-tick body states, telemetry, native dispatch, checkpoints and input tapes before modifying production code. No FPS/RSS gain has been claimed.

## Negative controls: what I examined without falsely promoting it to a defect

- [Rigid-body Euler dynamics](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/rigid_body.gd#L70-L137): translation and angular derivatives follow the body-frame \(\dot{\mathbf v}=\mathbf F/m+\mathbf g-\boldsymbol\omega\times\mathbf v\) and \(\dot{\boldsymbol\omega}=\mathbf J^{-1}(\mathbf M-\boldsymbol\omega\times(\mathbf J\boldsymbol\omega+\mathbf h))\) forms. This agrees algebraically with [MIT's rigid-body dynamics](https://ocw.mit.edu/courses/8-09-classical-mechanics-iii-fall-2014/6fe39e8d5ce4ce746ca256dfea665eda_MIT8_09F14_Chapter_2.pdf) under a fixed rigid inertia. No general Euler-sign bug was established.
- [Generalized-coordinate Schur factorization](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/generalized_coordinates.gd#L103-L177) and [mass-inventory parallel-axis terms](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/mass_inventory.gd#L15-L41) are consistent with the stated block and tensor contracts. No new current bug asserted from a code skim.
- [Rotorcraft inflow](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/rotorcraft/inflow.gd) already distinguishes normal/windmill branches and declares VRS instability. The [helicopter session](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/sim/helicopter_flight_session.gd#L585-L595) **rejects** vertical-atmosphere mode rather than silently applying a fixed-density rotor law. This guards against repeating the prior FPV air-density finding for helicopters.
- [Wind thermal streamfunction](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/wind_thermal_field.gd#L250-L306) computes its radial and vertical velocities from a shared axisymmetric streamfunction: in cylindrical coordinates \(v_r=-\partial_z\Psi/r\), \(v_z=\partial_r\Psi/r\), giving \(r^{-1}\partial_r(r v_r)+\partial_z v_z=0\) away from the axis. The near-axis limit is explicitly handled. This is divergence-free **kinematically**, not a solved buoyancy or terrain thermal PDE. No new sign error established.
- [Fixed-wing ground effect](https://github.com/bultodepapas/OpenRCsimulator/blob/9bb1f2c3dac2cead68445161f94513d965d12248/app/physics/ground_effect.gd) uses an explicitly empirical correction with stated aircraft-dependent coefficients and a bounded fade. The [FAA's physical summary](https://www.faa.gov/sites/faa.gov/files/2022-03/pilot_handbook.pdf) supports near-ground changes in induced drag and downwash; it does not validate these particular fitted coefficients. No new numerical bug count from model insufficiency alone.

## Qualification matrix and action sequence

1. **BL power:** executable stage confirmation of R3-F01, then a real 240 Hz throttle release with energy-account closure, fixed motor/pack identities, an explicit command-vs-speed distinction, and checkpoint/replay and remaining-charge tests.
2. **RCV mass:** full/empty fuel-state tests with independent mass/CG/inertia target and physical source uncertainty; no visual-only solution.
3. **RCV performance:** measure allocation rates and median/p95/p99 tick times on representative Nitro pad/track sessions and current target hardware before attempting a changed adapter boundary; use exact-source native/reference parity.
4. **World/flight realism:** independently measure rotor/wing, surface/ground and atmospheric parameters. Prefer a calibrated simple law to an uncalibrated complex one, and maintain explicit domain restrictions/old-law replay refusal.

**Audit discipline:** This third pass adds two code/physics findings and one optimization opportunity. It neither retests nor claims to repair the prior A36/R2 implementation. **Complete production CI, Godot stage and actual pilot/physical acceptance remain open.**
