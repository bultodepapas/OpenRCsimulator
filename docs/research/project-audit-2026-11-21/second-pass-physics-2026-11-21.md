# A36 — second-pass mathematical and physical audit (2026-11-21)

**Target:** [OpenRC Simulator audit branch](https://github.com/bultodepapas/OpenRCsimulator/tree/audit/physics-math-aero-2026-11-21), built on the existing A36 fix series, source base 31db53ca28d3ee8bf39cc1a3108f42a405896127. This is a **read-only physics investigation**, not a new physics implementation or a claim of complete CI/native validation. Its findings extend, rather than replace, the original A36 report and the consolidated external-audit ledger.

**Approaches checked:** (1) independent nondimensional aerodynamics and altitude effects against the multirotor plant and its data admission; (2) quaternion/SO(3) controller topology and actual branch behavior; (3) airship buoyancy, electrical bus and source-derived energy bounds; (4) fixed-wing section and spanwise-flow ownership; (5) documented rotor inflow/descent, near-ground and turbine/fuel fidelity. I distinguish *source-confirmed contradiction*, *independent arithmetic witness*, *acknowledged approximation*, and *unverified investigation candidate*. No Godot application or flight test was executed for these new R2 findings. All newly computed numbers are reproducible with the Python 3 standard-library-only [independent probe](probes/physical_crosschecks.py).

## Priority and evidence ledger

| ID | Type | What is established | Priority / needed verification |
| --- | --- | --- | --- |
| **R2-F01** | Source-confirmed physics inconsistency; independent ISA calculation | FPV rotor thrust, aerodynamic torque and in-plane rotor drag are invariant to atmospheric density at fixed rotor state, even though the airframe drag samples changing density | **P1 realism**. Run paired accepted 240 Hz flight states at two admitted heights; validate reference and any native backend, controller response, performance and replay before correcting |
| **R2-F02** | Source-confirmed control discontinuity; independent quaternion witness | FPV Angle heading changes by 90° for a 0.002° pitch perturbation near a hard horizontal-nose threshold | **P1 numerical/control** near the transition, not a demonstrated crash. Add exact mode-level and accepted-session crossing traces before repairing |
| **R2-I01** | Constructed admitted-parameter bus-power inconsistency; stage **not** executed | In a hypothetical custom high-resistance blimp state, the calculated electrical request exceeds the battery's own maximum deliverable power and the telemetry calls the former battery power | **P2 investigation**; reproduce in a real stage with an admitted model and state, then check reachability/energy before calling it a flown defect |
| **R2-L01** | Already-declared airship model limitation, now quantified | Blimp uses a fixed launch-density model at all heights; ISA density change across 1000 m changes the ideal buoyant force by ~2.78 N for the shipped envelope volume | **P2 physical expansion**, not a fresh implementation defect; couple atmosphere, helium, geometry and added mass consistently |
| **R2-L02** | Already-declared multirotor approximation | Static rotor law has no descent inflow, vortex-ring dynamics, wakes or rotor/ground interaction | **High-value realism research**, not a new defect count; preserve calibrated static baseline and use measured hover/climb/descent data |
| **R2-L03** | Already-declared fixed-wing section limitation | Horizontal wing sections omit drag from pure spanwise crossflow, leaving that load to optional body terms | **Research/measurement gap**, not proof of zero whole-aircraft lateral force; quantify affected aircraft and physical spans |
| **R2-L04** | Already-declared turbine approximation | Turbine can report fuel flow while fixed mass/CG remains prescribed | **Future physical program**, not a fresh defect; coordinate existing AV/fuel owners |

## R2-F01 — FPV rotor density disconnect

**Code ownership and source anchors:**

- [Electric and laboratory closed-loop plant, stage density and rotor equations](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/multirotor/controlled_plant.gd#L366-L474). The evaluator obtains the stage's actual atmospheric density and passes it to Airframe.loads, but rotor thrust is \(k_T\omega^2 h\), torque is \(k_Q\omega^2\max(h,h_{\min})\), and rotor in-plane drag is \( -k_H\omega v_{\rm hub}\) with no density.
- [Standalone/legacy plant](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/multirotor/plant.gd#L99-L125) likewise samples density for airframe drag but passes no density to [Rotor.loads](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/multirotor/rotor.gd#L13-L42).
- [Session](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/sim/multirotor/session.gd#L178-L185) admits an air start through **500 m** and [installs the actual environment on its plant](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/sim/multirotor/session.gd#L273-L291).

The dimensional static coefficient relation at fixed advance ratio and approximately constant Reynolds/Mach effects is

\[
T = \rho n^2 D^4 C_T,\qquad Q = \rho n^2 D^5 C_Q.
\]

For a bench coefficient \(k_{T0}=T_0/\omega_0^2\) at \(\rho_0\), a first-order density-corrected law is \(T(\omega,\rho)=k_{T0}\omega^2(\rho/\rho_0)\). Holding the speed and geometry fixed, the present code instead gives \(T(\omega,\rho)=k_{T0}\omega^2\) at all heights. This discrepancy is separate from the acknowledged absence of inflow, vortex-ring and Reynolds corrections; it occurs even in nominal static hover.

**Independent ISA troposphere arithmetic (not an app flight):**

| Height relative to ISA sea level | Density ratio \(\rho/\rho_0\) | Static thrust implied by a 33 N sea-level rotor assembly at fixed RPM | Thrust predicted by implemented FPV law | Hover-speed correction if \(C_T\) fixed |
| ---: | ---: | ---: | ---: | ---: |
| 0 m | 1.000000 | 33.000 N | 33.000 N | 1.000× |
| **500 m (admitted start height)** | **0.952872** | **31.445 N** | **33.000 N** | **1.02443×** |
| 1000 m (analytic sensitivity, not an admitted air-start height) | 0.907463 | 29.946 N | 33.000 N | 1.04975× |
| 3000 m (analytic sensitivity, not an admitted air-start height) | 0.742140 | 24.491 N | 33.000 N | 1.16080× |

The 33 N reference is the [identified research-quad static datum](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/multirotor/plant.gd#L32-L40); it is not a measured high-altitude flight result. At 500 m the frozen coefficient overpredicts the density-scaled fixed-RPM thrust by about **4.95%** relative to the physical first-order comparison (and misses ~4.71% of sea-level thrust). At 3000 m the overprediction is ~34.75% relative to the density-scaled comparison. Actual motor load, voltage and Reynolds/Mach changes will modify the equilibrium; those are precisely the subsequent qualification questions.

**Repair hypothesis:** put the reference density explicitly into admitted rotor law identity (or convert the static coefficients into \(C_T(J,Re,M)\) / \(C_Q\) tables); scale aerodynamic thrust, drag torque and in-plane load with the *same evaluated stage density*. Do **not** multiply rotor inertia or electromagnetic torque by density. Recompute source-derived hover/electric admission at the intended atmosphere, not only the original OCV/sea-level datum. Keep GDScript/native law identity, checkpoints and recorded old-flight refusal explicit. Verify fixed-\(\omega\) pure component invariants, loaded bus voltage and accepted 240 Hz tick behavior for at least two densities and one wind case. The historical coefficient oracle should be preserved as the reference-density baseline rather than silently changed.

## R2-F02 — FPV Angle mode yaw-reference seam

The [Angle controller](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/multirotor/flight_controller.gd#L447-L476) forms a desired quaternion with the **current inferred heading**, zero/commanded roll and pitch. That inferred heading switches branches when the norm of the nose's horizontal projection crosses **0.2**:

\[
\psi =
\begin{cases}
\operatorname{atan2}(n_E,n_N), & \sqrt{n_N^2+n_E^2}>0.2,\\
\operatorname{atan2}(-t_E,-t_N), & \text{otherwise and nose-up},\\
\operatorname{atan2}(t_E,t_N), & \text{otherwise and nose-down}.
\end{cases}
\]

That fallback is *finite everywhere* but not continuous on the switching surface. The exact crossing at zero yaw and roll 90° is \(\theta=\cos^{-1}(0.2)\approx78.463040967^\circ\).

Using an independent quaternion product/rotation computation that is **not** copied from the production optimized rotation helper, zero Angle roll/pitch sticks, fixed yaw 0°, roll 90°, and a pitch perturbation of only **0.002°**, the resulting outputs are:

| Current pitch | Nose horizontal norm | Branch | Chosen heading | Pre-gain quaternion-log [roll,pitch] error (rad) |
| --- | ---: | --- | ---: | --- |
| 78.462° | 0.200017801 | nose | 0° | [-1.297735988, -1.059577349] |
| 78.464° | 0.199983600 | reversed top | **−90°** | [-0.158084788, -1.565009052] |

Thus the desired-heading reference jumps **90°**, and the two-axis pre-gain attitude-error vector jumps by **1.246702 rad**. The actual rate target is gain-scaled and clipped by the existing angle-rate limit; this witness does **not** assert that the final commanded rate jumps by 1.2467 rad/s, nor that the vehicle crashed. It establishes that an arbitrarily small attitude perturbation can change the controller's target discontinuously. This is a **separate FPV finding**, not the earlier known helicopter Euler-heading issue.

**Repair hypothesis:** define a continuous target-heading policy with explicit accepted-sample continuity/state ownership, or adopt a geometric reduced-attitude/heading construction on SO(3) with a declared singular policy and a checkpointed heading reference. A pure local Euler-yaw replacement or a hand-tuned epsilon moves the seam but does not solve it. Qualify upright, nose-up, nose-down, inverted, changing yaw, physical stick reversals and reconnects, with 240/480/960 Hz sweeps around both sides of the threshold and reference/backend/checkpoint parity. Do not claim the global yaw direction is well-defined for a nose exactly vertical.

## R2-I01 — blimp bus power ceiling versus reported power (constructed candidate)

[Airship stage electrical calculation](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/airship/airship_dynamics.gd#L196-L217) calculates electrical demand from rotor speed, solves the Thevenin quadratic, and when the discriminant is non-positive returns \(V=V_{oc}/2\) and current \(I=V_{oc}/(2R)\), i.e. \(P_{\mathrm{terminal}}=V_{oc}^2/(4R)\), while [detailed telemetry reports battery.power_w as electrical demand](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/airship/airship_dynamics.gd#L323-L332).

The shipped [5 m blimp](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/data/airships/rc-blimp-5m.json) requests **101.416667 W** at four unit-normalized rotor speeds using its own nominal shaft-power/efficiency numbers. Its default pack resistance 0.045 ohm leaves considerable headroom, so **this is not demonstrated on the shipped battery**. But the [reader admits 0 to 2 ohms](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/airship/airship_data.gd#L163-L170). A constructed custom resistance \(R=0.5\,\Omega\) and 3S full OCV \(V_{oc}=12.6\,V\) give

\[
P_{\max}=\frac{12.6^2}{4(0.5)}=79.38\,W < 101.416667\,W.
\]

The solved source yields 79.38 W at that limit yet the nominal demand output can still say 101.42 W. Moreover the low-voltage cutoff reduces new actuator demand; the motor-speed state can retain energy for a while. **Do not interpret the 22.04 W difference as proven spontaneously generated energy without a rotor kinetic-energy budget.** A full accepted-session trajectory or a directly admitted stage fixture at this custom parameter point is required before promoting it from a constructed consistency candidate to a production bug. A clear immediate telemetry improvement would expose requested electrical power, pack terminal power, available ceiling and rotor stored-energy rate separately.

## Physical fidelity gaps — counted separately from new bugs

### R2-L01: blimp constant launch density

[Airship dynamics](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/airship/airship_dynamics.gd#L73-L98) reads model.rho as a constant on each stage and applies \(B=\rho Vg\), regardless of body altitude. This is an explicit constant-property experimental approximation, not a newly undisclosed defect. For the shipped **2.502001 m³ envelope** and a simple constant-volume ISA estimate, moving 0→1000 m lowers air density 1.225→1.11164 kg/m³ and **reduces ideal buoyancy by 2.7814 N** (equivalent to about 0.284 kg). At 3000 m the static-volume difference is about 7.7505 N (0.790 kg equivalent). These are *counterfactual fixed-volume estimates*, not predicted actual blimp flights: gas volume, envelope pressure, temperature, helium leakage, inertia and air-relative motion must be coupled for real physical qualification.

**Expansion order:** first verify the game altitude/ground-pressure convention; then use stage-local atmospheric density (and consistent drag/added mass), with a separately stated gas-mass, gas-temperature and envelope-volume model and a validated limited domain. Check neutral-buoyancy crossing, climb, no-power descend, energy work and checkpoint reproducibility. Preserve the current stock model as the reference-law baseline.

### R2-L02: FPV rotor inflow, descent and rotor/ground interaction

The [rotor law itself explicitly excludes these regimes](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/multirotor/rotor.gd#L1-L5). It is intentionally a **static-calibrated** research model. Vortex-ring descent near hovering induced velocity produces non-steady rotor loads; published quadcopter descent flow studies report thrust fluctuations. Multirotor near-ground loads depend on rotor spacing, ground slope, fountain flow, overlapping wakes and partial ground effect, so a blanket single-rotor helicopter multiplier would be inadequately justified.

**Research ladder:** (i) acquire fixed-RPM thrust/torque versus axial inflow and density with uncertainty; (ii) fit \(C_T(J,Re)\) and \(C_Q(J,Re)\) or a bounded blade-element/momentum approximation against held-out data; (iii) identify dynamic inflow and separately label unsupported vortex-ring states; (iv) add individually validated near-ground rotor-to-rotor and rotor-to-terrain effects; (v) qualify flight control re-tuning because actuator maps and settling behavior change. Use real quad and prop measurements—not just replay matching. Added physics should be selected by its measured error and CPU budget, not breadth of equations.

### R2-L03: fixed-wing spanwise wing-flow drag

The [local wing force law](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/aero.gd#L249-L273) resolves only the chord-normal section plane; [the loop skips a section](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/aero.gd#L571-L580) at zero chord-normal speed. Thus a purely spanwise air-relative flow with zero chord-normal velocity contributes no wing-section force, although real finite-thickness geometry experiences spanwise viscous/bluff-body drag. The code documents the unresolved spanwise/body-drag regime, and optional [fuselage crossflow](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/aero.gd#L681-L690) means **this is not proof of zero total aircraft lateral drag**.

Before adding another drag term, audit all existing body and vertical-tail drag ownership to prevent double counting. Measure/estimate a physically justified spanwise projected area for each wing, test \(\mathbf F_{\rm passive}\cdot\mathbf v_{\rm local}\le0\), and calibrate at sideslip and post-stall angles with independent data. Retain the small-angle attached flight oracle and deliberate versioning.

### R2-L04: turbine fuel burn and mass balance

The [turbine law](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/turbine.gd#L1-L15) explicitly keeps vehicle mass fixed while [fuel flow can be reported](https://github.com/bultodepapas/OpenRCsimulator/blob/31db53ca28d3ee8bf39cc1a3108f42a405896127/app/physics/turbine.gd#L188-L191). This is a **known approximation** with an existing AV/FUEL roadmap, not a new bug count. Integrate mass/CG/inertia and efflux momentum only after establishing the exact fuel and installation topology and flight log compatibility. A naive subtraction from aircraft mass or an unanchored additional thrust term risks violating linear/angular momentum closure.

## External physical sources inspected

These are research constraints, not substitute performance measurements of OpenRC:

1. [NASA Glenn: Propeller Thrust](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/propeller-thrust/) — swept area, density and mass/momentum flux in actuator-disk thrust.
2. [Lee–Leok–McClamroch geometric quadrotor control work](https://fdcl.engineering.gwu.edu/geometric-quadrotor-aerial-transportation) and [original SE(3) research abstract](https://arxiv.org/abs/1003.2005) — attitude control geometry, yaw/attitude coupling and singularity-aware control.
3. [Mori et al., 2025, quadcopter vortex-ring experiments/simulations](https://www.sciencedirect.com/science/article/pii/S1877750325000055) — descending rotor recirculation and fluctuating loads.
4. [Experimental inclined-ground quadrotor interactions, 2025](https://www.jstage.jst.go.jp/article/jrobomech/37/4/37_807/_article/-char/en) — asymmetric rotor torque and moments near sloped terrain.
5. [Open-access volumetric free-flying quadcopter wake measurements, 2024](https://link.springer.com/article/10.1007/s00348-024-03880-3) — overlapping rotor wakes and rotor/ground coupling.
6. [2026 Phys. Fluids quadrotor ground-effect experiment and simulation](https://doi.org/10.1063/5.0337114) — non-monotonic spacing-dependent rotor/ground effect. Do not turn its particular geometry into an OpenRC coefficient without matching dimensions and Reynolds number.

## Verification levels and actionable next work

**Completed this pass:** direct code tracing against pinned branch, dimensional derivations, independent pure Python quaternion/ISA/buoyancy/bus algebra, examination of previous consolidated A36 and current implementation notes, and external primary scientific sources. The probe can be executed locally with \`python3 docs/research/project-audit-2026-11-21/probes/physical_crosschecks.py\`. It does not call any project code or Godot. No source fix or new native/complete-flight evidence is claimed.

**Suggested order for a separate implementation PR or further commits, maintaining this draft branch as appropriate:**

1. **R2-F01**: prepare two accepted FPV frames at different legal heights with identical rotor RPM/body state, assert \(T\) and \(Q\) scaling using the reference-density coefficient, then implement only after confirming source/native identity and motor equilibrium admission.
2. **R2-F02**: run accepted Angle-mode tick samples immediately on both sides of the threshold with deliberately unsaturated gains, verify that the torque command changes in a way not explained by physical attitude changes; design a checkpointed continuous-heading strategy.
3. **R2-I01**: validate the extreme resistance and high-spin initial-state admission; compute requested/terminal/stored-rotor powers and determine if any accepted source-driven flight can exhibit inconsistent telemetry.
4. **R2-L01–L04**: target real measurements and versioned feature branches; introduce no unqualified global laws merely to make the model appear more detailed.
5. **Performance**: profile complete 1080p/Retina target sessions separately from float64 component probes. Favor native/C++ evaluators when qualified; preserve the 240 Hz fixed clock, exact transaction/replay boundaries and baseline player handling.

**Constraints:** no changes to main, no merge request, no claim of physical validation, no fake “FPS gained,” no repeat count for known rotor/heli/wing limitations already in existing research. A later implementation must retain old/reference laws, explicit saved-flight compatibility and measured acceptance.
