I researched rotorcraft papers, experimental datasets, open-source implementations, numerical tools, and the official documentation of other RC simulators.

**My strongest recommendation is to develop three independently testable systems around OpenRC’s existing kernel: rotor aerodynamics, achieved actuator motion, and drivetrain energy.** Those would give you a much stronger foundation for realistic HX-700 behavior—and make subsequent optimization decisions easier to justify.

The complete research package is here:

[**OpenRC_Helicopter_Research_2026-11-06.zip**](https://chatgpt.com/library?file_id=libfile_38cafd8457fc81918306b37e365c6fad&account_id=personal)

It contains the full report, **27 selected primary references, nine proposed experiments, the supporting calculations, and a map of the relevant OpenRC files**.

I cross-checked this work against the consolidated audits and the existing helicopter research. Gavrilets, Johnson’s inflow/VRS work, Walker–Tischler, ArduPilot, and Rotorflight already appear in your research; I treat those as foundations. The additions below are new data sources, more precise experimental methods, implementation references, and concrete ways to use them. Repository context was checked through commit `d0b672b`. No production code was changed.

## 1. The best physics investment: a rotor thrust-and-power benchmark

### A particularly useful NASA dataset

Harris’s **Model Rotor Hover Performance at Low Reynolds Number** contains tabulated experimental results for small rotors. Appendix A is especially valuable because it provides numerical data suitable for an automated comparison, rather than requiring estimates from plotted curves. [ntrs.nasa.gov](https://ntrs.nasa.gov/api/citations/20205001147/downloads/Harris%20CR-20205001147_Final_7_1_2020.pdf?utm_source=chatgpt.com)

My proposed use is to reproduce one of those experimental rotors as a separate research fixture:

1. Match its geometry and operating conditions.
2. Evaluate thrust, shaft torque, and power.
3. Fit a limited subset of conditions.
4. Reserve other conditions for validation.
5. Compare the existing mean-rotor model with any proposed alternative.

This would be an **independent component benchmark**. It would not establish that the HX-700 parameters are correct.

The useful nondimensional quantities are:

\[
C_T=\frac{T}{\rho A(\Omega R)^2},
\qquad
C_Q=\frac{Q}{\rho A(\Omega R)^2R},
\qquad
C_P=\frac{P}{\rho A(\Omega R)^3},
\]

where \(A=\pi R^2\). With consistent conventions and \(P=Q\Omega\),

\[
C_P=C_Q.
\]

That equality is also a useful implementation check. At zero rotor speed, these normalized coefficients are undefined; the evaluator must work with dimensional forces and torques there.

**Why compare power as well as thrust?** A model can produce the correct hover lift while consuming the wrong shaft power. In flight, that discrepancy appears as incorrect RPM droop, collective response, yaw reaction, climb performance, and energy available during power-off maneuvers.

I would therefore make these four plots standard outputs of the rotor research harness:

- Thrust versus collective at several RPM values.
- Shaft torque versus collective.
- Power coefficient versus thrust coefficient.
- Model residuals, including measurement uncertainty.

### A measurement trap worth addressing early

A separate NASA analysis found that **download on the test stand** was the largest influence on the measured results in its comparison. The fixture itself can contaminate what appears to be rotor performance. [NASA Technical Reports Server (NTRS)](https://ntrs.nasa.gov/citations/19900011009?utm_source=chatgpt.com)

For future HX measurements, record fixture tare, RPM, collective, thrust, shaft torque, air conditions, and repeatability. Electrical input power should have its own channel: it includes losses in the motor, ESC, and transmission, so it cannot automatically substitute for aerodynamic rotor power.

### Your main and tail rotors operate in different aerodynamic regimes

Using the declared values in the [HX-700 laboratory configuration](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/data/aircraft/hx700_electric_3d_experimental.json), and an explicitly assumed kinematic viscosity of \(1.5\times10^{-5}\,\mathrm{m^2/s}\), I calculated:

| Quantity | Derived value |
|---|---:|
| Main-rotor tip speed | 153.94 m/s |
| Main-rotor tip Reynolds number | Approximately 575,000 |
| Main-rotor Reynolds number at 75% radius, neglecting inflow and forward velocity | Approximately 431,000 |
| Tail-rotor tip Reynolds number | Approximately 189,000 |

These are **scale estimates from unvalidated configuration declarations**, not aircraft measurements.

The implication is useful: the main and tail rotors should not automatically share the same assumptions about section drag, separation, and Reynolds-number sensitivity.

UIUC provides measured low-speed airfoil data that can help here. Distinguish airfoil coordinate files from aerodynamic polars: one describes the shape; the other describes its measured performance. [m-selig.web.engr.illinois.edu](https://m-selig.web.engr.illinois.edu/pd.html?utm_source=chatgpt.com)

XFOIL is useful for exploratory section calculations, but its own documented scope includes limited separation. I would use it to investigate attached-flow behavior within a declared envelope, then seek additional evidence for deep stall, reverse flow, and unsteady rotor behavior. [web.mit.edu](https://web.mit.edu/drela/Public/web/xfoil/?utm_source=chatgpt.com)

## 2. Choose additional aerodynamic complexity by the error it explains

OpenRC already has a mean-rotor formulation, inflow dynamics, descent/VRS treatment, and ground effect. The next question should be:

**Which measured response cannot the present model reproduce, and which additional state or equation explains it?**

Examples include:

- The transient after a collective step.
- Pitch response to a lateral cyclic input.
- Tail authority as collective and forward speed change.
- Rotor power near the ground.
- Differences between upright and inverted head response.

This keeps model complexity connected to evidence.

### Build a blade-element model offline first

A useful research candidate would evaluate local air-relative velocity at radial and azimuthal stations, apply the actual blade pitch and section polars, then integrate both forces and shaft torque.

For a conventional section basis with positive tangential flow:

\[
\phi=\operatorname{atan2}(U_P,U_T),
\qquad
\alpha=\theta-\phi,
\]

\[
dL=\tfrac12\rho(U_T^2+U_P^2)c\,C_L\,dr,
\qquad
dD=\tfrac12\rho(U_T^2+U_P^2)c\,C_D\,dr,
\]

\[
dT=dL\cos\phi-dD\sin\phi,
\qquad
dQ=r(dL\sin\phi+dD\cos\phi).
\]

These are individual blade-element contributions. Their use requires explicit axis, rotation, and inflow conventions, along with suitable polar coverage.

The advantage of the research implementation is diagnostic: you can inspect which blade regions contribute thrust, consume power, or enter an unsupported flow regime. Then compare its integrated result against the existing production law.

The important qualification is that **blade elements alone do not supply a valid wake model**. More radial stations cannot compensate for inappropriate polars or an incorrect inflow closure.

### Changing rotor speed introduces a mathematical obligation

This is particularly relevant to startup, shutdown, RPM droop, and autorotation.

Suppose a future wake formulation stores nondimensional inflow:

\[
\lambda=\frac{v_i}{\Omega R}.
\]

For fixed radius and physical time,

\[
\boxed{
\dot{\lambda}
=
\frac{\dot v_i}{\Omega R}
-
\lambda\frac{\dot\Omega}{\Omega}
}
\qquad \Omega>0.
\]

The second term follows directly from the product rule.

A constant-RPM wake equation cannot be transferred into a variable-RPM implementation without examining this scaling. Near zero RPM, a dimensional inflow state is often more convenient.

This is a design consideration for future model development. OpenRC’s existing dimensional inflow state should not be presented as a newly discovered defect.

### Signed thrust is only one part of inverted-flight fidelity

NASA’s small hingeless-rotor experiment reported different lead-lag damping between positive- and negative-thrust conditions. That supports testing head dynamics separately in both directions; it does not provide HX-700 coefficients. [NASA Technical Reports Server (NTRS)](https://ntrs.nasa.gov/citations/19880010873?utm_source=chatgpt.com)

A separate TU Delft study compared aerodynamic models in positive- and negative-thrust propeller operation and found important limitations in simplified methods in part of the negative-thrust regime. Its axial, cambered propeller differs from an inverted RC helicopter, so its value is methodological. [TU Delft Research Portal](https://research.tudelft.nl/en/publications/benchmarking-of-aerodynamic-models-for-isolated-propellers-operat/?utm_source=chatgpt.com)

For OpenRC, I would keep these as distinct qualification questions:

| Question | Required evidence |
|---|---|
| Does collective reversal produce correctly signed force? | Equation, frame, and sign checks |
| Does the inverted helicopter have the correct response? | Head, actuator, and flight-response measurements |
| Can airflow drive the rotor during descent? | Correct signed aerodynamic torque and power |
| Does the aircraft autorotate realistically? | Drivetrain, wake, tail, entry, equilibrium, and recovery evidence |

Passing the first test cannot establish the other three.

## 3. Achieved servo motion should connect controls to mechanics

The most useful new actuator reference I found is a University of Minnesota thesis describing an instrumented hobby-servo test bench and identified actuator dynamics. Its contribution here is the distinction between **the commanded signal and the measured mechanical output**. [conservancy.umn.edu](https://conservancy.umn.edu/bitstream/handle/11299/183295/Lakshminarayan_umn_0130M_17648.pdf?isAllowed=y\&sequence=1\&utm_source=chatgpt.com)

For the HX-700 FBL candidate, I would structure the model as:

**Pilot command → FBL controller → mixing and limits → achieved servo states → linkage geometry → blade pitch → aerodynamic loads.**

The historical X-Cell surrogate should retain its distinct effective-flybar formulation.

### A small, testable actuator model

An illustrative starting point is:

\[
\dot\delta=
\operatorname{clip}
\left(
\frac{\delta_c-\delta}{\tau},
-r_{\max},
+r_{\max}
\right),
\]

with mechanical travel limits and separately declared command delay and sampling.

Here:

- \(\delta_c\) is the limited commanded position.
- \(\delta\) is the achieved position.
- \(\tau\) controls the lag.
- \(r_{\max}\) limits speed.

This is a proposed model to fit, not a universal servo law.

For a held target in the unsaturated region, its exact update is:

\[
\delta(t+h)=
\delta_c+
\bigl(\delta(t)-\delta_c\bigr)e^{-h/\tau}.
\]

When rate limiting is active, the solution begins with constant-speed motion and then enters exponential decay. The report derives that complete piecewise solution, giving you an independent verification oracle.

The implementation boundary matters. Within an integration stage, evaluate the derivative and loads from the stage state:

```text
servo_dot  = actuator_rhs(stage_servo_state, held_servo_command)
blade_pitch = linkage_map(stage_servo_state, stage_rotor_azimuth)
loads       = rotor_loads(stage_state, blade_pitch, stage_airflow)
```

The solver advances the state. A force evaluation should not independently advance the servo or update a sampled controller again.

For identification, measure output angle, input command, supply voltage, load, direction, and timestamps. A published “seconds per 60 degrees” specification does not identify delay, small-signal phase, backlash, or loaded behavior.

ArduPilot’s swash documentation is useful for setup and calibration ideas. Its optional horn linearization depends on geometry; it should not be imported as a universal linkage correction. [Copter documentation](https://ardupilot.org/copter/docs/traditional-helicopter-swashplate-setup.html?utm_source=chatgpt.com)

### A concrete optimization inspiration: precalculate kinematics

AccuRC documents a tail-control option that replaces its full tail-mechanism calculation with precalculated servo-to-pitch values. This is a useful engineering example of reducing mechanical computation. It is not a measured OpenRC speedup. [accurcsimulator.com](https://accurcsimulator.com/faqs/?utm_source=chatgpt.com)

Your articulated HX inspector provides a promising basis for the same kind of experiment:

1. Solve the authoritative geometry offline.
2. Generate a mapping from **achieved servo positions** to blade-pitch quantities.
3. Compare that map with the full solver at withheld positions.
4. Include travel extremes, combined inputs, and invalid/binding regions.
5. Measure the actual runtime cost.

Keep actuator dynamics in the simulation. A static kinematic map does not account for elasticity, backlash, or load-dependent servo behavior.

This could become a valuable optimization because it targets repeated geometry work while retaining the physical state that affects handling.

## 4. Treat the governor and the freewheel as separate systems

Rotorflight’s documented governor distinguishes spoolup, active regulation, hold recovery, autorotation-related windows, bailout, and RPM-loss fallback. Those distinctions are useful for a controller state machine and its tests. They do not establish the physical state of a clutch. [Rotorflight Documentation](https://doc.rotorflight.org/stable/contributing/tech/governor/?utm_source=chatgpt.com)

### An independent drivetrain experiment

For a simple idealized bench model, use a fixed positive reduction ratio \(g\), positive inertias, and define:

\[
v=\frac{\omega_m}{g},
\qquad
J_e=g^2J_m,
\qquad
Q_e=gQ_m.
\]

These express motor speed, inertia, and torque in rotor-side coordinates for the declared lossless reduction.

Let \(\Omega\) be rotor speed, \(J_r\) the inertia continuously connected to the rotor side, and \(Q_a\) the **signed opposing torque**—positive when resisting rotation and negative when airflow drives it.

An ideal one-way clutch can be expressed as:

\[
s=\Omega-v\ge0,
\qquad
\lambda\ge0,
\qquad
s\lambda=0,
\]

\[
J_e\dot v=Q_e-\lambda,
\qquad
J_r\dot\Omega=\lambda-Q_a.
\]

These are proposed scalar bench equations, not a replacement for the aircraft’s full angular-momentum coupling.

Their behavior is clear:

- If the rotor overruns the motor, \(s>0\), so transmitted torque is zero.
- At equal speeds, solve the locked acceleration.
- If maintaining engagement would require negative transmitted torque, the one-way clutch opens.

Consequently, **zero throttle is not itself the clutch-opening condition**. Motor inertia, losses, rotor loads, and relative speed matter.

Track the mechanical energy:

\[
E=\tfrac12J_ev^2+\tfrac12J_r\Omega^2.
\]

Every energy change should be explained by input work, aerodynamic work, mechanical losses, or an explicitly modeled engagement event.

Project Chrono provides a shaft-clutch component with asymmetric torque limits, making it useful as an isolated comparison tool. Its solver, timestep, torque capacity, and tolerances still need qualification for the chosen experiment. [api.projectchrono.org](https://api.projectchrono.org/10.0.0/classchrono_1_1_ch_shafts_clutch.html?utm_source=chatgpt.com)

The first useful cases are powered spin-up, equal-speed engagement, overrun, hold, recovery, and stopping. Only after that should the model be used to assess autorotation, which additionally requires the correct aerodynamic energy extraction and tail-drive behavior.

## 5. Numerical fidelity depends on what the model resolves

The HX configuration’s nominal RPM and gearing lead to an important calculation:

| Quantity | Main rotor | Tail rotor |
|---|---:|---:|
| Revolutions per second | 35.000 | 172.308 |
| Two-blade passage frequency | 70.000 Hz | 344.615 Hz |
| Whole 240 Hz steps per revolution | 6.857 | 1.393 |
| Whole 240 Hz steps per blade passage | 3.429 | 0.696 |

These values are derived from the [declared HX parameters](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/data/aircraft/hx700_electric_3d_experimental.json).

**This does not prove the current averaged rotor model is inaccurate.** An averaged model has different requirements from a model that follows individual blades. Whole-step sampling, RK stage evaluations, controller bandwidth, and aerodynamic state bandwidth must be considered separately.

It does establish a design constraint: introducing blade-resolved tail loads into the existing loop requires a deliberate integration and sampling strategy.

I would compare candidates using:

- Several integration rates, such as 240/480/960 Hz.
- Fixed controller/input sampling clocks when testing solver convergence.
- Separate experiments for controller sampling.
- A converged independent reference for smooth cases.
- Force, torque, trajectory, event-time, and energy residuals.

Changing the integration rate and controller sampling together can make it unclear which change caused the difference.

### Accurate integration does not guarantee correct contact detection

CVODE’s documentation explicitly explains that sign-change rootfinding can miss a grazing root. [Documentation for SUNDIALS documentation](https://sundials.readthedocs.io/en/v7.8.0/cvode/Mathematics_link.html?utm_source=chatgpt.com)

For example:

\[
g(t)=(t-t_*)^2
\]

reaches zero without changing sign.

That matters for a rotor grazing terrain: a sophisticated ODE solver does not automatically provide conservative collision detection.

The authors’ **Tight-Inclusion** implementation provides conservative continuous collision tests for its specified point/triangle and edge/edge primitives. Adapting the approach to OpenRC’s curved rotor motion and analytic terrain would also require bounds on the geometry approximation, motion between endpoints, and floating-point error. [GitHub](https://github.com/Continuous-Collision-Detection/Tight-Inclusion?utm_source=chatgpt.com)

The useful principle is:

> A “clear” result should be justified by a bound. Dense sampling is useful for finding counterexamples, but it does not prove that every collision has been excluded.

This supplies a research direction for the previously audited contact problem without presenting it again as a new finding.

## 6. Parameter identification deserves as much attention as the equations

Walker and Tischler’s Blade 360-CFX paper is already in your research. Its experimental method remains highly relevant: excitation sweeps for identification, separate doublets for validation, and explicit treatment of coupled rotor/fuselage dynamics. [sjsu.edu](https://www.sjsu.edu/researchfoundation/docs/VFS_2021_Walker.pdf?utm_source=chatgpt.com)

For OpenRC, I would identify parameters in this order:

1. Mass, center of gravity, and inertia.
2. Servo response.
3. Linkage geometry.
4. Rotor thrust and power.
5. Head/flapping response.
6. Closed-loop flight behavior.

Otherwise, an optimizer can compensate for an incorrect servo delay by changing rotor lag—or hide an airframe error in FBL gains.

### A fitting objective that respects units and uncertainty

Define scaled residuals:

\[
r_{j,k}(\vartheta)=
\frac{
y^{sim}_{j,k}(\vartheta)-y^{meas}_{j,k}
}{s_j},
\]

then solve a bounded problem such as:

\[
\min_{\ell\le\vartheta\le u}
\sum_{j,k}\rho\!\left(r_{j,k}^2\right).
\]

The scale \(s_j\) should reflect measurement noise or a justified error tolerance. Otherwise, numerically large channels can dominate the fit simply because of their units.

SciPy’s `least_squares` supports bounds, Jacobians, and robust losses. Those are useful building blocks, but a small residual does not establish that the parameters are uniquely identified. [SciPy v1.18.0 Manual](https://docs.scipy.org/doc/scipy-1.18.0/reference/generated/scipy.optimize.least_squares.html?utm_source=chatgpt.com)

Inspect the sensitivity matrix after scaling both residuals and parameter coordinates. Small singular values indicate combinations that are weakly distinguishable at the experiment’s noise level. Hold those parameters to independent measurements, improve the excitation, or report their uncertainty.

Reserve entire flights or operating conditions for validation. Randomly splitting neighboring samples can produce an overly optimistic assessment because those samples share nearly the same dynamics and disturbances.

### A particularly important detail in your existing recorder

OpenRC’s [rotorcraft recorder](https://github.com/bultodepapas/OpenRCsimulator/blob/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/sim/rotorcraft_recorder.gd) exposes separate `t_s` and `loads_t_s` columns. After tick zero, the loads timestamp is one step earlier.

An unaccounted one-tick shift at 240 Hz introduces a phase difference of:

\[
|\Delta\phi|=360^\circ\frac{f}{240}.
\]

At 20 Hz:

\[
|\Delta\phi|=30^\circ.
\]

That is large enough to distort an identified dynamic response. The recorder exposes the timing distinction; the analysis must use it correctly. This is an analysis requirement, not a recorder defect.

Use the demonstrated helicopter trace and checkpoint paths. Helicopter integration with the separate `.orfl` mechanism was not established during this research.

For real logs, Rotorflight Blackbox Explorer provides helicopter-specific log analysis, while ArduPilot documents controlled system-identification excitation and logging. Preserve actual timestamps, firmware configuration, injected reference signals, and sensor filtering. Servo command channels remain distinct from measured shaft position. [rotorflight/rotorflight-blackbox · GitHub](https://github.com/rotorflight/rotorflight-blackbox?utm_source=chatgpt.com)

Also account for sensor location. A body-mounted accelerometer away from the center of gravity contains rotational acceleration terms:

\[
\dot{\boldsymbol\omega}\times\mathbf r
+
\boldsymbol\omega\times
(\boldsymbol\omega\times\mathbf r).
\]

A location or frame mismatch should not be fitted accidentally into rotor parameters.

## 7. The most useful simulator and tool inspirations

### HoverHere: a close implementation reference

**HoverHere** is particularly relevant because it is an RC helicopter simulator with coupled rotor, drivetrain, and controller ODEs. Its documentation describes a separate high-frequency calculation thread. [zulugithub/HoverHere · GitHub](https://github.com/zulugithub/HoverHere?utm_source=chatgpt.com)

I inspected its main helicopter ODE source at commit `494cf80`.

I would study:

- Component state ownership.
- Initialization of the drivetrain and controllers.
- Force/velocity diagnostic visualization.
- The separation between physics and presentation.

It shares some literature with OpenRC, so agreement between the two would not constitute independent physical validation. Its GPLv3 code and separately licensed assets also need to retain their applicable terms if reused.

### FLOWUnsteady: an optional offline wake laboratory

FLOWUnsteady combines several aerodynamic methods with a reformulated vortex-particle approach. Its documentation identifies specific rotor and propeller validation cases. [GitHub](https://github.com/byuflowlab/FLOWUnsteady?utm_source=chatgpt.com)

My proposed use would be:

1. Reproduce a documented reference case.
2. Investigate a specific question, such as main-rotor wake exposure at the tail.
3. Quantify numerical convergence.
4. Fit a compact runtime correction only within a supported envelope.

A simulation-derived table would still need physical validation for the intended aircraft.

Its acoustic workflow also provides ideas for relating blade motion and loading to sound. One practical dependency is that PSU-WOPWOP is a separate closed-source binary, not bundled with FLOWUnsteady. [FLOWUnsteady](https://flow.byu.edu/FLOWUnsteady/examples/rotorhover-acoustics/?utm_source=chatgpt.com)

For OpenRC, a more immediate sound experiment would use accepted RPM, rotor loading, and observer geometry to control separate main- and tail-rotor layers. Blade-passage harmonics provide a useful frequency reference; recordings are needed to assess perceptual accuracy.

### Commercial simulators: useful training and interface ideas

These are documented product features, rather than independently established realism rankings.

| Simulator | Useful documented idea | Proposed OpenRC application |
|---|---|---|
| **HELI-X** | Select which controls the trainee operates while the helper manages others. | An explicit instructor controller, selectable axes, visible assistance, and real actuator limits. |
| **neXt** | Flight recordings, stick displays, hover orientations, and rotor-energy feedback. | Repeatable checkpoint practice, recorded/current stick comparison, and energy feedback once the drivetrain is qualified. |
| **AccuRC** | Component-level configuration and precalculated tail kinematics. | Requested-versus-achieved control inspection and geometry-derived runtime maps. |

HELI-X’s hover-training manual describes the helper acting through control inputs; neXt’s official description documents the recording, stick, and energy features. [help10.heli-x.info](https://help10.heli-x.info/UsersManualV10.pdf?utm_source=chatgpt.com)

My preferred initial training metrics would be position and heading RMS error, time inside a hover region, minimum rotor RPM, saturation time, and energy lost during a maneuver. Compare attempts under the same starting state and weather.

Checkpoint restoration should include controller, actuator, drivetrain, gust, and sensor histories. That is what makes repeated practice experimentally comparable.

### The toolset I would start with

| Tool or resource | Role |
|---|---|
| **Python / NumPy / SciPy** | Parameter fitting, residual analysis, spectra, convergence studies, and plotting |
| **UIUC measured polars** | Section-data reference where geometry and conditions match |
| **XFOIL** | Scoped exploratory airfoil analysis |
| **Rotorflight Blackbox / ArduPilot tools** | Compatible real-flight logs and identification workflows |
| **Project Chrono** | Isolated drivetrain and constraint comparisons |
| **OpenRC’s existing trace, checkpoint, and native/reference tools** | Reproducible implementation verification |
| **FLOWUnsteady** | Later, targeted wake investigations |
| **Tight-Inclusion** | Conservative collision-method reference |

Each additional dependency should answer a specific experimental question.

## 8. A practical sequence for OpenRC

I would organize the next work into the following independently reviewable packages. These are proposals; the experiments have not been run in this research pass.

| Order | Work package | Main code areas | Required result |
|---|---|---|---|
| **1** | Rotor thrust-and-power benchmark | `research/helicopter/`; `main_rotor.gd`, `tail_rotor.gd` | Source-matched data, compatible units, held-out conditions, uncertainty, and residual plots |
| **2** | Achieved actuator and linkage bench | `electronics.gd`, `swash.gd`, `hx700_mechanism.gd` | Measured output response, analytic simple-model checks, combined travel limits, and mapping errors |
| **3** | Two-speed drive/freewheel experiment | `drive.gd`, `rotor_coupling.gd` | Overrun/engagement behavior, energy and momentum accounting, stop-event convergence |
| **4** | Identification and telemetry work | `rotorcraft_recorder.gd`, `helicopter_flight_session.gd` | Correct timing and frames, replayable inputs, separate fitting/validation data, parameter uncertainty |
| **5** | Aerodynamic candidate comparison | Rotor evaluators and `flight_dynamics.gd` | A measured response improved on held-out conditions, with a declared signed/low-speed envelope |
| **6** | Contact, performance, and training qualification | `impact_detector.gd`, native stage, presentation paths | Conservative swept coverage, accepted-state parity, measured 1080p performance, repeatable practice |

The full paths and detailed acceptance cases are included in the report and experiment cards. The core physics files are in the [rotorcraft physics directory](https://github.com/bultodepapas/OpenRCsimulator/tree/d0b672b09663226ff8b8ac4f43eae8643c77a8c4/app/physics/rotorcraft).

For performance qualification, measure stage evaluation, a complete physics tick, and the paced rendered frame separately. Include both ground and airborne workloads. The prior audit’s optimization timings were inconclusive, so these research recommendations carry **no assumed speedup**.

The first milestone I recommend is a reproducible rotor benchmark, an achieved-servo bench, and a drivetrain energy stand. Their outputs would give you concrete evidence for deciding which aerodynamic changes improve the HX-700—and which calculations can be simplified while preserving its response.