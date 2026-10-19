# Fuel-powered RC turbine realism and integration plan

**Date:** 2026-10-13. **Status:** AV-18/19/20 software implemented; ECU/fuel integration and physical acceptance pending. **Owner:** Ventage Jet / physics track. **Parent:** [Ventage Jet guide](../AVANTI-S-PLAN.md). **Steps:** existing AV-05b and AV-10, plus AV-18…30. This document owns detailed turbine work and its status; the parent retains aircraft-wide work. Consolidate completed guidance into the parent/contract and retain evidence before deleting this active plan.

**Owns:** `app/physics/turbine.gd`, bounded new turbine/fuel kernels, `app/tests/test_turbine*.gd`, Ventage Jet propulsion scenarios, `research/avanti-s/` turbine source/reducers and `docs/research/turbine-realism/`. Aircraft changes go through `research/avanti-s/av06/inputs.json` and `derive_physics.py`; generated `app/data/aircraft/sebart_avanti_s_a200.json` is never edited directly.

**Shared boundaries:** aircraft contract/schema/loader; `app/sim/flight_session.gd`, `simulation.gd`, trace/replay; rigid-body equations and mass properties; M5 atmosphere/wind; AV-09 gear/flaps; AUD-08/10 sound; HUD, input, menu and CR terminal-flight behavior. Inspect status and coordinate those seams before implementation. Other tracks retain ownership. The owner authorized implementation on 2026-10-13. Adopted choices go to DECISIONS; future choices remain proposals.

## 1. Objective and definition of realism

Make the selected RC turbojet behave like an engine with stored rotational/thermal energy, a fuel delivery system and a protective ECU. The aircraft must show the corresponding acceleration, energy management, endurance and changing balance. More delay is not automatically more realistic: response must depend on engine revision, operating point, command amplitude, controller setting and ambient conditions.

The first production target remains the **2017 non-BL JetCat P100-RX** in the existing Ventage Jet. Current P100-RX-BL, Xicoy and KingTech data are comparison evidence. A reusable engine-definition architecture is useful; shipping additional aircraft/engine variants is a separate task.

Acceptance has three distinct levels:

| Level | Meaning | Required evidence |
| --- | --- | --- |
| Software verified | Equations, units, events and lifecycle are correctly implemented | Analytic/independent oracles, actual-session tests, replay, numerical refinement and performance |
| Evidence constrained, experimental | Manufacturer endpoints are respected; unsupported maps remain declared estimates | Identified source revision, parameter register, uncertainty/sensitivity, supported operating domain |
| Physically validated for a stated installation/domain | Independent runs support engine response and aircraft consequences | Calibrated installed-engine measurements, held-out conditions and matched flight/pilot observations |

A nominal catalog match, plausible sound or passing golden replay does not confer physical validation. The latest evidence is the dated [AV-18 source review](../research/turbine-realism/AV-18/README.md), which includes exact sources, pages, download hashes and current-file fingerprints.

## 2. Baseline, demonstrated gaps and priorities

The current implementation already has a nonlinear throttle-to-RPM map, asymmetric rate schedules, a governor lag, static thrust/flow tables, ram corrections, separate inlet/nozzle arms and rotor gyro momentum. These are useful foundations; preserve them as a frozen comparison model before changing behavior.

| Priority | Starting limitation | Consequence | Required correction |
| --- | --- | --- | --- |
| P0 | RPM advances before body RK4 and is held during stages | Coupled thrust/gyro transients can inherit a lower-order split | One evolving continuous turbine state evaluated at each body stage |
| P0 | Disabling the engine gives zero RPM in the next pre-step | Abrupt loss of spin; no physical shutdown sequence | Separate fuel valve, combustion, rotor speed, cooling and run permission |
| P0 | Fuel-flow map is unused; wet inventory is constant | No endurance or empty-tank event; no weight/balance evolution | Consume actual delivered fuel; derive mass/CG/tensor together |
| P0 | Large-step schedules and interior maps are estimated | Apparent realism can be self-confirmed by the same equations | Reproducible response metrics, parameter sensitivity and independent identification |
| P1 | No EGT/core thermal state or supply/pump behavior | Hot starts, limits and supply loss have no causal mechanism | Bounded thermal/ECU model, then optional calibrated supply model |
| P1 | Density-only engine correction | Same density can conceal different engine pressure/temperature conditions | Separate ambient pressure, temperature and corrected engine quantities |
| P1 | Installed thrust/ram/crossflow remain unvalidated | Airspeed, climb and idle energy may be misattributed | Separate static, installation, flight-speed and aero evidence |
| P1 | Audio/crash/HUD lack a complete engine-state interface | Sound can imply thrust or a stopped rotor incorrectly | Read-only committed propulsion telemetry with explicit clocks |
| P2 | No pickup, hopper, slosh, surge or component wear | Advanced installation/failure behavior absent | Add only where identified data and complete state justify it |

The inspected inventory is 11.705089 kg with 1.28 kg of declared fuel. These are virtual-build values, not hardware measurements. Its 3.2 L tank is dealer-derived and its geometry estimated. The source review qualifies the older research's manual-version citations; AV-18a will repair those specific citations without rewriting historical findings as current evidence.

## 3. What the research supports

The following anchors are published specifications, not measured maps of the installed Ventage Jet. Flow refers to liquid fuel/oil mixture where the publication specifies it; missing idle flow is not zero.

| Identified engine | Idle / maximum RPM | Idle / maximum thrust | Published consumption | Timing interpretation |
| --- | ---: | ---: | --- | --- |
| P100-RX, 2017 catalog (R1) | 44,000 / 154,000 | 2 / 100 N | 80 / 390 ml/min at idle/max | No matched large-step duration |
| P100-RX-BL, current page (R4) | 44,000 / 154,000 | 2 / 100 N | 80 / 390 ml/min at idle/full load | Different controller/pump revision |
| Xicoy X52, current page (R5) | 60,000 / 225,000 | 1.8 / 52 N | 160 g/min at 52 N; idle unpublished | No quantitative response time |
| P250-PRO-S-V2, V1-4 (R7) | 35,000 / 117,000 | 12 / 250 N | 138 / 820 ml/min at idle/max | 5 s for 5→95% rated thrust; 5 s for reverse; separate startup |
| KingTech K-210G5, current page (R8) | Idle unpublished / 121,000 | Idle unpublished / 21 kgf interpreted as 205.94 N | 590 g/min; operating point unspecified | 10–15 s **start time**, endpoints/conditions unspecified |

The numbered source links below resolve to the exact official publications and their qualification in AV-18. Do not rank engines by these unmatched figures or transfer their schedules.

| Evidence | Supported use | Boundary |
| --- | --- | --- |
| [R1: P100-RX 2017](../research/turbine-realism/AV-18/README.md#r1--jetcat-p100-rx-selected-historical-configuration) | Selected static endpoints and catalog conditions | No intermediate, in-flight or transient map |
| [R2/R3: dated JetCat manuals](../research/turbine-realism/AV-18/README.md#r2--jetcat-rxrxi-ecu-behavior) | Controller modes, control permissions and stop/cooling transitions | Exact response preset and firmware still need identification |
| [R4: P100-RX-BL](../research/turbine-realism/AV-18/README.md#r4--jetcat-p100-rx-bl-current-comparison) | Demonstrates current revision/controller differences | Similar endpoints do not make it the historical installation |
| [R5/R6: Xicoy](../research/turbine-realism/AV-18/README.md#r5--xicoy-x52-current-small-engine-comparison) | Small-engine scale and distinct fuel/curve/restart capabilities | Family manual predates X52; do not transfer family options blindly |
| [R7/R8: P250/KingTech](../research/turbine-realism/AV-18/README.md#r7--jetcat-p250-pro-s-v2-response-definition-comparison) | Distinguishes startup from defined thrust transitions | Other-engine times are not P100 calibration |
| [R9–R11: original experiments](../research/turbine-realism/AV-18/README.md#r9--p100-rx-multi-sine-ground-identification) | Operating-point/amplitude-dependent identification and instrumentation | Test engine/command conventions differ from the aircraft configuration |
| [R12/R13: physics/fuel suppliers](../research/turbine-realism/AV-18/README.md#r12--general-engine-equations-and-controller-limitations) | Control-volume relations and density/energy bookkeeping | No unpublished engine maps or actual blend density |

Do not adopt a generic “three-second turbine,” assume every down-step is faster, or make engine acceleration depend directly on aircraft speed. Preserve ordinary idle, low idle, normal stop, emergency cut, flameout and OFF as distinct cases.

## 4. Required behavior by physical mechanism

### 4.1 Radio demand, ECU curve and response

Trace `raw input → calibrated/armed command → optional transmitter shaping → ECU curve → RPM target → actual RPM → thrust`. Record each quantity independently. RC arming authorizes commands; it is not turbine ignition. Engine STOP needs an explicit command/event separate from throttle zero. Existing radio throttle calibration and pause behavior remain authoritative.

Identify the ECU's throttle mapping from steady samples. A thrust-linear control law, if chosen, should invert the accepted steady thrust map between **idle thrust and full thrust**. A zero-origin cube root does not necessarily provide that exact mapping. Retain the current cube-root schedule as an estimated legacy mode until the actual selected ECU curve is established. Avoid applying radio expo twice; report trim/PWM conventions in physical experiments rather than assuming every paper uses 0%=idle.

Measure response from multiple initial RPMs and command sizes, including idle→25/50/100%, 25→75%, 50→100%, and reverse transitions. Include a short command reversal while spooling, low-amplitude sinusoidal commands at several biases and finite ramps. Separate command transport latency, ECU decision delay, rotor acceleration and thrust change. A delay alone cannot reproduce a rate-limited trajectory.

The response schedule may have distinct low/high RPM regions, acceleration/deceleration settings and ambient correction. Do not turn qualitative Fast/Normal/Slow names into fabricated seconds. Identify actual schedules, their joins and saturation. A second-order model becomes justified only if held-out residuals show a first-order schedule is insufficient.

### 4.2 Rotor and thermal dynamics

Use continuous RPM in every RK stage. Start with the existing empirical closed-loop law:

```text
dN/dt = clamp((N_target - N) / tau_local,
              -R_decel(N, ambient, ecu_mode),
              +R_accel(N, ambient, ecu_mode))
```

`tau_local` describes a local identified equivalent. A thrust bandwidth cannot be promoted directly into a universal RPM-governor pole. Schedule knots need continuity and explicit numerical-refinement checks; an event or nonsmooth join cannot be judged by an assumed global RK4 order.

For a later physical spool model, use an audited power/torque balance rather than an arbitrary inertia multiplier:

```text
J_rotor * domega/dt = Q_turbine - Q_compressor - Q_loss + Q_starter
omega = N * 2*pi/60
```

Those torques/maps are unavailable for the selected installation. Keep this model outside production until its maps, identifiability and held-out advantage are demonstrated. More component equations can increase uncertainty and runtime cost without improving predictions.

Add a thermal state sufficient to reproduce hot/cold history and cooling. Distinguish hot gas, core/case heat and measured EGT: exhaust temperature is not turbine-inlet temperature, and a thermocouple has its own lag. An initial reduced model may use:

```text
dT_core/dt = (T_core_equilibrium(mode, N, fuel, ambient) - T_core) / tau_core
dT_egt_sensor/dt = (T_egt_physical - T_egt_sensor) / tau_sensor
```

Fit heating and cooling separately. Cooling depends on starter airflow, ambient temperature and wind; RPM need not decay monotonically while a cooling starter is active. Thresholds/hysteresis/timeouts belong to an identified ECU profile. A catalog EGT range is not itself a shutdown threshold. No heat-limit thrust penalty without a defined physical/controller cause.

### 4.3 Gross thrust, inlet momentum, pressure thrust and installation

Keep the force budget observable. In an axial control-volume model:

```text
F_net = mdot_exhaust * V_exit - mdot_air * V_inlet
        + (p_exit - p_ambient) * A_exit
mdot_exhaust = mdot_air + mdot_fuel
```

The usual small-fuel/adapted-nozzle approximation must be declared. At full catalog flow the fuel/air ratio is about 2.3%; assess the approximation against the intended error budget. Do not omit pressure thrust while claiming a general nozzle solution; alternatively keep a calibrated adapted-nozzle surrogate within its domain. Do not assume a convergent nozzle is choked throughout its RPM range.

For body-vector loads, apply gross exit force along the nozzle axis and captured-air momentum using local **air-relative velocity at each intake**, including body rotation about the selected datum. Retain intake/nozzle arms separately. A downstream thrust tube's entrained flow and forces belong to an installation control volume; avoid counting the same momentum through both engine and tube laws. Report where a scalar installation factor remains an approximation.

Define airspeed in the engine axis separately from TAS, IAS and groundspeed. Evaluate static through forward flight, high angle of attack/sideslip, near-zero axial flow and reverse flow. The existing reverse-flow cutoff is a declared surrogate, not validated reverse-flight inlet physics. Crossflow capture, separation and inlet distortion need bounded domains and measured justification; do not turn full crossflow velocity into a guaranteed engine-normal-force law outside that domain.

Installation loss is not an aerodynamic drag tuning knob. Preserve bare-engine static data, inlet pressure recovery, tube loss/entrainment and external airframe drag as separate parameter families. Compare bare and installed thrust on the same run/conditions before changing the current estimated 0.92 factor. No generic propeller wake/P-factor/reaction-torque module is allowed on this branch.

### 4.4 Fuel flow, chemistry and endurance

Advance total liquid fuel/oil mixture mass using **actual delivered flow**, not throttle demand:

```text
dm_tank/dt = -mdot_delivered - mdot_leak + mdot_transfer
m_consumed(t) = integral(mdot_delivered dt)
```

The first implementation has no leak and no transfer. OFF/cooling with a closed valve consumes no fuel; startup, stabilization and controlled auto-off can consume fuel. Flameout may temporarily occur with fuel delivery still present: report consumed liquid separately from combusted energy. Fuel cut does not erase rotor/core energy in the same tick. Residual delivery or trapped fuel needs an explicit line state before it is modeled.

Use kg/s internally. Convert ml/min with the documented density and temperature of the mixture. Oil fraction by volume versus mass and “5% added to fuel” versus “5% of final mixture” must be resolved before calculating density or heating value. Keep fuel-specific viscosity/start effects and ECU fuel selection in engine data; no universal diesel penalty or X52 diesel support inferred from another model's manual.

Fit a steady fuel map using gravimetric runs at multiple powers. Two endpoints cannot establish linear fuel-versus-thrust behavior. Initially retain the existing intermediate estimate and publish sensitivity. Transient enrichment is a separate optional term, bounded nonnegative and identified from flow data. Endurance integrates a recorded mission and includes startup, reserves and unusable fuel. Remaining time is conditional on a declared future power profile, not a guaranteed countdown.

For the declared 3.2 L and catalog full-load 0.39 L/min, **8.21 minutes** is a mathematical full-tank constant-power upper estimate before startup/reserve/unusable deductions; half-tank gives **4.10 minutes**. Neither is a demonstrated flight time. Reserve quantity is authored scenario policy, not a manufacturer limit.

### 4.5 Changing mass, CG, inertia and datum

Define dry hardware once and bind each tank to an explicit inventory component ID. Replace the loaded liquid component with a derived fill-dependent quantity; do not leave it in the static inventory and add dynamic fuel a second time. Never infer tanks from free-text component names.

For all hardware and liquid distributions, derive together:

```text
m = sum(m_i)
c = sum(m_i * c_i) / m
I_CG = sum(I_i_at_own_center
           + m_i * ((dot(d_i,d_i) * identity) - outer(d_i,d_i)))
d_i = c_i - c
```

The six tensor entries preserve the repository sign convention and must describe one distribution. A fill-dependent tank centroid/envelope is preferable to a full box with only its mass scaled. The initial verified approximation may hold the liquid at a fixed centroid, explicitly marked estimated; it does not simulate slosh or a free surface.

**This is a solver change, not a `sim.mass` assignment.** The current rigid-body state is referenced to the inventory CG. A changing CG affects velocity interpretation, aerodynamic/contact/nozzle arms, rendering placement, hull transforms, trim and inertia derivatives. Simply editing mass/CG each tick can create discontinuous geometry or artificial angular acceleration.

AV-10b must derive an open-system momentum balance and choose the state reference before integration. Recommended investigation: a fixed dry-body reference datum for the optional variable-mass route, with stage-local spatial mass properties and a carefully defined transform to current-CG telemetry. Compare it against a correctly derived moving-CG formulation on independent fixtures. Keep the existing constant-mass route intact. Admit the variable-mass route only after agreement and acceptable cost; document the chosen equations in DECISIONS when adopted.

Account for momentum carried by departing liquid/gas once. Net engine thrust already represents a control-volume momentum/pressure result; adding a second rocket term double counts it. Conversely, blindly adding `-I_dot * omega` while omitting angular-momentum outflow can produce spurious spin-up. Frozen-within-tick mass properties are an approximation that requires a measured convergence/error bound, not an assertion of stage-coupled accuracy.

Require a positive physical tensor for every accepted fill and a continuous visual structural datum. A hypothetical 1.28 kg fuel reduction increases force-per-mass by about **12.3%** between this declared half-tank build and its virtual dry build at unchanged force; that illustrates why fuel matters, but does not predict actual acceleration, climb or CG travel. Do not rebalance hardware between fill states. Preserve existing AV-14 fuel-sensitivity corrections.

### 4.6 Pickup, hopper, negative g and slosh

Defer slosh until basic depletion is validated. Empty main tank is not necessarily empty feed: a hopper/UAT may sustain flow, while trapped/unusable fuel may not be reachable. A supported feed-system extension needs separate tank capacities, pump pickup, usable volumes, transfer connectivity and bubble-buffer state.

Pickup access depends on **effective acceleration in the body frame**, including vehicle acceleration, not merely pitch/roll or gravity. Correctly designed RC systems can support inverted flight. No automatic flameout at 90° bank, negative-g timer or arbitrary probability. Begin with deterministic bench-injected supply interruptions of stated duration; later test clunk/baffle/UAT behavior against installation measurements.

If slosh becomes material, use a small identified mechanical model with fuel-dependent mode frequency/damping and proper forces/moments/internal mass motion. Validate energy/passivity and update the full mass distribution. Do not render fuel movement and add an unrelated random force. Reserve CFD/particle liquid methods for offline investigation unless a lower-cost model demonstrably fails.

### 4.7 Ambient conditions, rotor gyro and limits

Pass static pressure and temperature from the existing M5 environment through trim, stage evaluation and telemetry. Use engine-inlet **total** conditions when forming corrected coordinates:

```text
theta = T_total_inlet / T_reference
delta = p_total_inlet / p_reference
N_corrected = N / sqrt(theta)
mdot_corrected = mdot * sqrt(theta) / delta
```

These coordinates organize maps; they do not alone predict thrust or authorize a particular temperature exponent. Do not apply the piston engine's dry-charge factor to a turbine. Distinguish atmospheric effects from ECU compensation and thermal/RPM limits. Include equal-density/different-pressure-temperature cases, uniform-wind Galilean checks and hot/high combinations. If M5's atmosphere is field-constant, an aircraft-height lapse profile requires that track's explicit extension.

Rotor momentum is `H = sense * J_rotor * N * 2*pi/60 * axis`. Use stage RPM and preserve the existing gyro convention. Rotation direction and rotor inertia remain estimated for this engine. A transient mounting torque needs rotor plus gas angular-momentum flux, stator/casing reaction and the inertia convention; the closed mechanical propeller correction cannot simply be copied. AV-26 may conclude that evidence only supports the existing gyro term. Report both possible rotation senses in sensitivity until hardware direction is established.

Engine RPM/temperature limits, airframe tested speed, structural limit and model-domain boundary are different quantities. The manual's aircraft speed guidance does not authorize a drag cap or simulated breakup. No afterburner, turbine-powered propeller, thrust vectoring or twin-engine behavior is implied by this turbojet plan.

## 5. ECU lifecycle and abnormal cases

Use an engine-profile state machine; names below are simulator semantics, not a claim that every vendor uses the same firmware states. OFF can retain thermal history; “cold” is derived. Starter rotation, combustion and usable thrust are independently observable.

| Mode | Main behavior | Exit/guard |
| --- | --- | --- |
| OFF | Valve closed; thermal state may still be warm | Valid START, correct supply/fuel, permitted temperature and arm state |
| PRECHECK / PREHEAT | ECU owns start; igniter/starter sequencing is profile-specific | Sensor/voltage checks, heat/ignition criterion or timeout |
| IGNITING | Metered start fuel and observed light-off | Consistent RPM/EGT response; abort on failed light-off |
| START_ACCEL | ECU fuel schedule accelerates to self-sustaining operation | RPM/EGT limits, start timeouts; no pilot full-power override |
| STABILIZE | Hold/settle and wait for valid pilot idle handover | Profile-specific stable interval and handover command |
| RUN_IDLE / RUN | Govern demand inside accepted limits | STOP, supply fault, controller fault or flameout |
| LOW_IDLE | Optional profile; reduced idle with recovery cost | Supported request and recovery schedule; excluded if unsupported |
| AUTO_OFF | Optional controlled stabilization before fuel closure | Documented profile sequence, interrupted only by allowed commands |
| FUEL_CUT / FLAMEOUT | Fuel shutoff or lost combustion; rotor/core continue | Closed fuel flow, thermal/RPM rundown, restart rules |
| COOLING | Starter may rotate; valve remains closed | Profile temperature/RPM/switch criterion; supply loss changes cooling |
| FAULT_LOCKOUT | Latched reason and restart permission | Explicit permitted reset/precheck; throttle alone cannot clear it |
| RELIGHT | Optional, profile-specific restart attempt | Qualified signals, supply, RPM/EGT window, timeout and cancel |

Use a source-backed normal stop sequence and separate immediate fuel cut. Emergency cut can close fuel immediately while RPM/thermal/thrust outputs continue according to physics. Do not continue the RUN static hot-thrust map through cold rundown; distinguish residual hot-gas thrust, cold starter flow and possible windmilling drag. A starter-spun cold rotor does not imply RUN thrust. RPM can reach a low windmilling equilibrium in flight rather than zero; keep unmeasured windmilling behavior estimated and opt-in.

First support deterministic faults: empty usable fuel, commanded fuel cut, injected lost combustion, failed ignition and a specified supply interruption. Low supply voltage, overtemperature, overspeed, sensor disagreement and signal loss follow only a supported ECU profile. Separate radio signal failure from application focus loss: focus/pause freezes simulation rather than inventing receiver failsafe.

Healthy flights have no invented random flameouts. Optional training faults record cause, onset, duration, seed if relevant and restart policy in the checkpoint. In-flight relight stays unsupported for the historical P100 profile until evidenced. A Xicoy restart mode cannot silently enable it for JetCat. Wear, bearing seizure, FOD, coking, lubrication damage and maintenance hours remain research scenarios until causal parameters are supported; no persistent damage subsystem is introduced here.

## 6. Minimal model and optional extensions

Use a data-driven, bounded empirical model first. Recommended progression:

1. Stage-coupled RPM, legacy steady maps and actual fuel telemetry, retaining prescribed mass. Establish a known numerical delta before retuning.
2. Source-backed ECU modes plus identified/estimated thermal history and a separate cutoff/rundown map. Initial empirical estimates remain experimental.
3. Explicit tank depletion and empty event; then the independently verified variable-mass route. Telemetry-only depletion can be an isolated test harness, but production cannot claim physical fuel burn with frozen mass.
4. Installed/ambient corrections supported by measurements or bounded experimental surrogates.
5. Pump, battery, hopper, relight and slosh only as separately validated optional modules.

Do not simultaneously evolve thrust as an independent state and derive another thrust from RPM unless the second state represents a specifically identified residual dynamic. A second-order thrust model can serve as an offline benchmark; it must not disagree with RPM/audio/fuel/state semantics in production. Identify the smallest state set that explains held-out data.

A pump extension may use delivered-flow/pressure lag and saturation, with supply head/voltage/viscosity dependencies measured for the actual pump. A supply-battery extension can reuse EL infrastructure only after validating separate battery ownership, different loads, start/cooling currents and voltage thresholds. Propeller motor/ESC physics is not a turbine fuel pump. Receiver power-off may still leave an independently supplied ECU cooling, according to the selected profile.

## 7. Aircraft-data and state contracts

Extend [AIRCRAFT_CONTRACT](../AIRCRAFT_CONTRACT.md) before enabling any new configuration. Current `prescribed_fuel` means fixed wet mass; silently consuming it would break that capability. Propose a conditional `finite_fuel` capability plus explicit turbine-control/model-law selections; exact names require contract-owner review. Optional modules must be rejected until all consumers and lifecycle state exist. Keep v2 quantity objects exactly `{value, unit, kind, source}`; unit/kind/source rules remain unchanged.

| Authored definition | Required content / validation |
| --- | --- |
| Engine identity | Manufacturer, exact model/revision, ECU/firmware/response settings, reference conditions and supported domain |
| Steady maps | RPM/thrust/air/fuel tables, idle/max endpoints, monotone ordered abscissae, finite values, interpolation/extrapolation policy |
| Dynamics | Valid positive local lag; bounded acceleration/deceleration schedules and join policy; separate fuel-cut/start/cooling laws |
| Thermal / ECU | State transitions, limits, hysteresis/timeouts and sensor meaning; profile-supported relight/low idle only |
| Installation | Axis, datum-relative intake/nozzle locations, inlet/tube assumptions and loss-map provenance |
| Fuel | Mixture identity, density reference, oil convention, capacity/usable reserve, explicit inventory binding, initial fill and liquid distribution |
| Optional supply | Actual pump, separate battery, line/hopper geometry and calibrated domain; no inert inactive fields |

Keep mutable values in state, never in the normalized aircraft definition. Engine/fuel state has a fixed layout selected at accepted configuration/reset, not resized during flight.

| State class | Minimal contents |
| --- | --- |
| Continuous float64 | RPM; thermal state when active; tank masses; optional delivered-flow/pressure, supply charge and slosh states |
| Sampled | Input/ECU samples at explicit simulation ticks; retained sensor observations where required |
| Discrete/int64 | ECU mode, command/fault latches, event order, qualified restart state and exact timer ticks where applicable |
| Derived read-only | Demand, flow/thrust budget, CG/tensor, rotor momentum, fuel remaining/used, limits and estimated supported-domain status |

A physical dwell timer can use a continuous phase age; fixed-rate ECU timers can use tick counts. Define the time convention once. Mode history, last qualified sample and pending events must serialize. Identical-looking aircraft with different fuel/ECU/profile configuration need different model/checkpoint identities.

## 8. Integration with the existing simulator

| Seam | Concrete change and constraint |
| --- | --- |
| `app/physics/turbine.gd` | Keep pure table/force queries; add a pure stage evaluator returning derivatives, loads, rotor momentum and diagnostics. Isolate new ECU/fuel kernels when useful; no render types |
| Source generator / aircraft loader | Extend authored inputs and conditional schema; derive new fields; check exact units, profile consistency and full wet/dry range before acceptance |
| `FlightSession` continuous setup | Route the turbine through existing continuous callbacks; append engine/fuel state after existing owned layouts, with explicit indices/capacity. `AUX_RPM` becomes an endpoint mirror, never a second evolving state |
| `VehicleModel.stage` | One pure evaluation per stage, shared by load and derivative consumers. Validate the complete payload; no persistent cache keyed incompletely |
| Event integration | Extend/reuse `step_policy` patterns with bounded earliest-event localization; turbine modes must change transactionally between substeps. Evaluate the remainder with the new mode and fuel limit |
| Mass properties / rigid body | Add the chosen verified variable-mass route only for the explicit capability. Update all stage forces/contact arms and accepted endpoint/render transforms consistently |
| Trim/start | RUN trim solves actual steady propulsion at initial fill/ambient conditions. Airborne starts initialize running/settled state; a requested cold start is an explicit engine scenario. No fallback to old trim after a new model/environment fails |
| Checkpoint/reload/reset | Version layouts/identity; restore all continuous, sampled/discrete state, timers, fuel, weather/RNG and source identity. A rejected step/reload preserves the full previous accepted transaction |
| Trace / telemetry | Version metadata and sampling semantics. Record state-time engine outputs separately from k1-time loads; no mixed-row RPM/thrust reconstruction |
| Other aircraft | Inactive branch must preserve accepted configurations and complete trajectories. Do not change glow/electric input, fuel semantics or coupled-shaft equations as a side effect |

Fuel exhaustion, thermal guard crossing, start timeout and sample-driven ECU decisions need an explicit event-order policy. Use physical time first; define deterministic priority for simultaneous safety cut, timeout and pilot demand. Locate the earliest crossing, consume only available fuel, switch mode once, then integrate the remaining subinterval. Never advance with negative accepted mass and clamp afterward. Cap event iterations and fail safely on a nonprogressing event; distinguish small local remainder from absolute float64 clock precision.

No RNG, UI signal, audio action, fuel mutation or mode transition inside RK stage queries. Commit externally visible signals once after the complete tick succeeds. Deliberate defect tests run on disposable copies. A new schema field without a validated runtime consumer is rejected.

## 9. Aircraft acceleration, speed and pilot consequences

Acceleration must emerge from the force budget. For a straight-flight diagnostic with aligned thrust and path angle gamma:

```text
dV_ground_along_path/dt ≈ (T_net - D) / m - g*sin(gamma)
P_excess ≈ (T_net - D) * V_air
```

The speed equation assumes the stated alignment and wind conditions. Wind gradients make groundspeed derivative and airspeed derivative different; do not apply the simplified equation indiscriminately. Climb-rate estimates from excess power require quasi-steady conditions and the actual thrust direction. Log force/mass before explaining a speed change.

At constant configuration, level maximum speed is a stable intersection of thrust and drag with feasible lift/trim. It is not exhaust velocity, a hardcoded limit, or a consequence of engine RPM alone. The catalog's jet kinetic power is not shaft output or useful aircraft power; static useful translational power is zero despite nonzero fuel flow. Distinguish Newtons from manufacturer kgf, RPM from rad/s, and km/h from m/s.

Required flight comparisons at matched commands/configuration:

| Scenario | Inspect |
| --- | --- |
| Hands-off idle/full-power transition at several speeds | RPM/thrust lag, along-path acceleration, pitch from line arms, trim and airspeed/groundspeed |
| Go-around from sustained idle and from modest power | Height lost, minimum airspeed, time to positive excess power and pilot-command clipping; no automatic boost |
| Approach energy reduction / throttle blip | Residual idle thrust, airframe drag, descent rate, overshoot and command reversal while spooling |
| Fixed-build full/half/reserve fuel | Mass/CG/tensor, stall/trim change, climb and maneuver acceleration; hardware positions unchanged |
| Constant-power and representative mission | Fuel used/usable remaining, endurance, empty event and post-cut glide |
| High/low speed and sideslip | Installed force budget/domain warnings; no drag compensation for unvalidated inlet physics |
| Hot/high and wind | Shared environment, corrected operating point, controller limits, exact deterministic input history |
| Engine-off / attempted relight | Residual energy/rundown, altitude loss, permission/timeout; no guaranteed rescue |

Ventage Jet currently has gear locked up and no qualified runway start. Taxi, takeoff, rejected takeoff, braking, landing rollout and flap-dependent go-around depend on **AV-09** and ground/start qualification. Define them now as later acceptance cases; do not test an airborne locked-up jet on invisible landing gear. Landing-realism claims remain open until those systems exist.

## 10. Audio, visuals, HUD and terminal flight

Coordinate with the [audio realism plan](audio-realism.md), especially AUD-08/10. Publish one read-only engine endpoint snapshot: RPM/demand, mode, combusting flag, delivered fuel, actual gross/net thrust, estimated exit flow/velocity, EGT/thermal state, starter state and supported-domain/limit flags. If an acoustic quantity is unmodeled, label its perceptual proxy; do not derive thrust from a sound envelope.

Pitch/whine follows rotor speed; exhaust roar follows combustion/flow; starter and cold rundown differ from RUN. Do not extend fuel delivery to keep a sound alive. Visual heat shimmer, flame/smoke and an exhaust anchor are presentation consumers. They cannot add force or change simulation timing. Thermal appearance requires the corresponding state, and visible flame is not evidence of useful thrust.

HUD defaults should expose RPM, usable fuel and clear ECU/fault state, with optional EGT/flow diagnostics. Distinguish idle from stopped and requested power from delivered power. A forecast endurance label must disclose its assumed consumption/profile. Keep internal fit coefficients and solver modes out of ordinary player flows.

Pause/menu/focus freezes physical time and all turbine/fuel/cooling state. Reset recreates the selected start state; it is not an unrecorded refueling command. Crash currently terminates/holds the flight, so an audible physical rundown needs an explicit ownership decision: recommended **terminal engine afterrun** using the same turbine kernel, a deterministic separately identified local clock and fuel cut, while terminal body state remains fixed. It must be serialized/replayable and paused with the product. If that subsystem is deferred, audio may fade the held snapshot but must not report a fabricated physical RPM trajectory. Do not pretend a frozen flight body underwent a coupled post-crash motion.

## 11. Measurement and identification campaign

Physical engine operation is performed by the owner/qualified operator using manufacturer procedures; this plan defines observations and reductions, not substitute operating instructions. No external messages or measurement requests were sent during this task.

| Campaign | Minimum observations | Identification purpose |
| --- | --- | --- |
| Configuration/metrology | Engine/ECU revisions, preset values, fuel/oil convention, dry inventory/tank/pickup/tube, calibrated ambient conditions | Prevent cross-variant and installation ambiguity |
| Steady bench | Randomized 0/10/25/50/75/90/100% commands; actual RPM, force, fuel consumption and EGT; at least three repeat runs | Separate demand map, thrust map and fuel map; establish repeatability |
| Dynamic bench | Step/reversal/ramp matrix; several biases/amplitudes; cold/warm starts and normal/emergency cuts | Identify latency, acceleration/deceleration, thermal/rundown and ECU modes |
| Installation comparison | Bare versus fitted inlet/tube with matched settings/conditions | Separate installed loss from engine and airframe drag |
| Feed/supply | Controlled instrumented interruptions and recorded supply voltage/flow | Identify buffering/supply failure before enabling advanced faults |
| Aircraft balance | Same hardware at full/half/reserve/empty fill; scales/CG and optional inertia measurements | Validate tank mass properties without rebalancing |
| Flight | Time-synchronized radio/ECU/airspeed/altitude data, mass/fill/weather and known maneuvers | Validate installed response, acceleration, glide and go-around |

Target thrust logging ≥200 Hz; capture command edges with an independent timestamp. Record the ECU's real update rate rather than duplicating values and calling interpolation new evidence. Acquire RPM/demand/EGT at the fastest documented real rate; report stale-sample intervals and quantization. Use weighing/time integration for fuel when an instantaneous meter is unavailable, and report its dynamic resolution. A pump-voltage proxy is not a measured fuel-flow rate.

Calibrate force zero/gain before and after; bound stand dynamics, tare, fuel scale error, ambient drift and timing skew. Measurement uncertainty must be below the planned discrimination threshold. Use actual mixture density only for volume conversions. Store raw time series unchanged, complete run metadata, calibration, synchronization, sensor locations and discarded-run reasons. Avoid filtering away the transient being fitted; document phase/group delay.

Fit steady maps first, then dynamics at fixed installation/ambient conditions, then thermal/cutoff behavior, then ambient/installation corrections. Separate whole runs/days/conditions for training and validation; random row splitting across an autocorrelated run is insufficient. Digitized public plots may bound behavior with pixel/time uncertainty, but cannot serve as a high-accuracy primary calibration set. Unsupported raw data remain an explicit evidence gap.

Publish parameter intervals/correlations and sensitivity, not just a best fit. Investigate identifiability: RPM-only logs cannot uniquely determine thrust, fuel, pump and compressor efficiencies. Rank the first measurements by expected impact on go-around height, mission fuel and trim/CG change. Proposed priority: step response and static/fuel maps, installation loss, tank mass properties, thermal/cutoff, ambient map, then rotor direction/inertia and advanced feed behavior.

## 12. Metrics, test matrix and acceptance gates

For a transition from measured steady `F0` to `F1`, define progress `z=(F-F0)/(F1-F0)`. For both up/down steps, command latency and t10/t50/t90/t95 are measured from the documented command edge; transition duration t90−t10 is separate. Record absolute 5%/95% rated-thrust crossings only when comparing a publication that uses those definitions. Require sustained crossing/settling over a declared dwell to reject noise. Distinguish normalized progress from percent rated thrust and report demand/RPM/thrust timings separately.

Required engine grid: stopped/cold/warm/idle and 25/50/75/100% RUN; all major up/down pairs; command reversals at 0.25/1/2 s; fuel full/half/reserve/unusable; 0/20/40/60/70/85 m/s axial flow; both signs of sideslip and body rotation; ambient 0/15/35 °C and illustrative field elevations 0/1500/2500 m. These are investigation points, not manufacturer-certified envelopes. Unsupported combinations stay experimental or are refused by an explicit domain rule.

| Gate | Required proof / proposed engineering threshold |
| --- | --- |
| Units/data | Exact scalar conversions and source endpoints; ordered finite tables; malformed module/units/shape/identity rejected; no numeric strings/null/booleans accepted as physical quantities |
| Analytic governor | Constant-target unrestricted lag matches analytic solution at float64-scaled tolerance; rate schedule and reversals preserve finite domain without hidden demand overshoot |
| Numerical convergence | 120/240/480/960 Hz comparison to an independent refined reference; at 240→480, representative smooth thrust/RPM/fuel outputs change ≤1% and selected flight measures ≤2%. Report absolute errors near zero; no blanket RK4-order claim across events |
| Events | Analytic empty-tank/timeout crossings within 0.1 ms of reference, or a stricter justified local bound; zero negative committed fuel, one event, correct remainder and simultaneous-event order. Separately report absolute timestamp rounding |
| Mass/geometry | Independent mass/first-moment/tensor fixtures, positive principal moments, symmetric full tensor; no visual/contact datum jump at fill transitions; no double-counted fuel |
| Conservation | Open-system known-answer cases below; no spurious acceleration from co-moving mass loss; gyro/mount terms not double counted |
| Lifecycle | Every mode's positive path, abort/fault path and rejected transition; pause/reset/reload/trace/checkpoint continuation through starts, cuts, empty events and cooling |
| Steady physical fit | Provisional target: thrust error ≤max(0.15 N, 5% of measured thrust), plus combined expanded uncertainty; measurement uncertainty ≤half the target band. Catalog-only matching is a separate nominal check |
| Dynamic physical fit | Held-out thrust RMSE ≤3% of tested thrust span, peak error ≤7.5% of span; t10/t90/t95 error ≤max(0.15 s, 10% of measured elapsed time). Report bias/operating point, not only aggregate RMSE |
| Fuel physical fit | Integrated liquid consumption ≤5% error per held-out mission/steady bin, with density/scale/timing uncertainty stated; reserve/empty-event errors evaluated separately |
| Thermal physical fit | Provisional EGT RMSE ≤25 K on held-out runs; guard/cooling/start mode timing must also agree. No tuning a sensor lag to conceal wrong physical heat history |
| Flight physical fit | Matched-build acceleration/climb/trim/endurance within predeclared observation uncertainty; pilot delayed-power/recovery ratings and input evidence. Thresholds set from obtainable matched observations before tuning |
| Performance | Actual whole-tick p50/p95 by aircraft/regime and event cost on an idle accepted target host; existing 500 µs/tick gate remains. Investigate repeatable >5% baseline regression; do not run timing beside other agents' workloads |
| Compatibility/delivery | Inactive aircraft complete state/trajectory parity, generator/schema/fleet checks, full suite and fresh-clone/export checks when runtime integration lands |

These physical thresholds are proposed acceptance targets, not manufacturer accuracy claims or achieved results. If observation quality cannot discriminate them, improve the measurement or narrow the claim; do not mark the gate passed. Model uncertainty outside the calibration domain remains explicit even after an in-domain fit.

Independent known-answer fixtures must include:

1. Exponential governor and a constant-rate saturated transition, including reversal before settling.
2. Constant net force `F` with depletion rate `k`, no drag/gravity: `m=m0-k*t`, `v-v0=(F/k)*ln(m0/m)`. The thrust already includes relative exhaust momentum. This rejects a duplicate rocket term.
3. Zero force and co-moving mass departure: no artificial translational acceleration. A freely spinning annular mass draining with its local rotational velocity must not gain spin from an unbalanced `I_dot` term.
4. Independent two-mass/box CG/tensor calculations, fuel removal symmetry and off-axis tank cases; fixed-datum versus moving-CG equivalence.
5. Known intake/nozzle force arms, wind translation invariance and stage-consistent signed rotor gyro; zero-combustion starter case rejects hot RUN thrust.
6. Closed-form constant fuel exhaustion before/at/after a tick boundary, multiple event ordering and no repeated consumption after cut.
7. Rejected k2/k4 derivative or endpoint projection restores body, engine, fuel, mass properties, mode/timers and weather state exactly.

Mutation controls in disposable copies: instantaneous RPM cut, stage RPM replaced by endpoint RPM, duplicated fuel inventory, ml/min treated as kg/s, direct-throttle consumption, stale mode/timer restore, doubled ram drag, hot-thrust map on starter/cold state, missing event remainder, density correction applied twice and unsupported relight accepted. Demonstrate that each intended assertion catches its specific defect with a valid unmutated control.

## 13. Incremental implementation sequence

Each integration slice is independently reviewable. [AV-18…20 evidence](../research/turbine-realism/AV-20/README.md) distinguishes delivered software from pending calibration and later ECU/fuel work. No combined turbine/fuel/aero/UI retune.

| ID | Work | Proof / status |
| --- | --- | --- |
| AV-18 | Source/runtime audit, baseline and metrics | Delivered: dated sources, native paired snapshots and [response reducer](../../research/avanti-s/av18/response_metrics.py), 11 analytic tests; no measured engine calibration |
| AV-18a | Repair affected historical manual URLs/pages and record variant/thermal differences | Delivered: AV-05 cites the correct March 2015 ECU manual and February 2023 P250 publication; historical fit scope retained |
| AV-19 | Explicit turbine integration and state/identity contract | Delivered: optional `spool_integrator` category, strict loader/schema and stiffness preflight; supported one-RPM layout, versioned snapshots/trace and generated aircraft selection |
| AV-20 | Continuous turbine RPM with existing maps/settings, prescribed mass | Delivered: stage thrust/gyro/governor, endpoint mirror, analytic impulse/refinement, rollback/replay, trace guards and inactive-fleet exactness; evidence and full-suite limits linked above |
| AV-21 | Steady/response identification and bounded empirical maps | Run-separated validation, schedule/curve joins, parameter sensitivity; estimated fallback labeled **pending** |
| AV-22 | Thermal/history and state-specific cold/hot flow/rundown kernels outside `app/` | EGT/sensor distinction, no cold hot-thrust leakage, thermal/history and numerical tests **pending** |
| AV-05b | Integrate ECU start/idle/normal stop/fuel cut/flameout/cooling | Source-backed permissions/events, residual energy, fault/lifecycle/trace proof; low idle/relight only when supported **pending** |
| AV-23 | Optional calibrated pump and separate supply-battery behavior | Delivered-flow/voltage/saturation/start/cooling data, energy/rollback checks; deferred if data insufficient **pending** |
| AV-10a | Tank inventory binding, usable volume and depletion kernel | No duplicated fuel; constant-flow and mission integrals; empty-event localization in isolated harness **pending** |
| AV-10b | Derive and independently verify variable-mass equations/state datum | [Independent reference](../../research/avanti-s/av10/README.md) and 5 analytic/transform fixtures delivered; tank distribution/flux assumptions and production architecture **pending** |
| AV-10c | Integrate finite fuel and changing mass/CG/inertia | Actual-session empty event, trim/start/reset/replay; continuous structural geometry, full/half/reserve fixed-build comparison **pending** |
| AV-24 | Installed force budget, ambient corrected coordinates and domain policy | [VAL-AUD-R03](../research/physics-audit-2026-10-14/remediation/R03/F02-capture-vector.md) repairs the zero-axial capture-force jump; [local intake kinematics](../research/physics-audit-2026-10-14/remediation/R03/F07-local-intake.md) now use the force application point in standalone and RK stages. Corrected engine maps, installed-force identification and physical acceptance remain **pending**. |
| AV-25 | Optional hopper/pickup and supply interruptions; slosh experiment if justified | Buffer/transfer mass conservation and measured effective-acceleration behavior; slosh remains opt-in until validated **pending** |
| AV-26 | Rotor gyro/rotation sense and transient mount-balance investigation | Stage gyro oracle, both-sense sensitivity; add mounting load only with complete momentum/evidence balance **pending** |
| AV-27 | Telemetry, versioned replay and audio/HUD/crash handoff | Pure committed snapshot, compatible traces, pause and terminal-afterrun clock decision; AUD/HUD/CR owner proofs **pending** |
| AV-28 | Flight-energy/handling scenarios; later ground cases with AV-09 | Same-source/command paired traces, go-around/idle/glide/fuel/ambient metrics; ground scenarios blocked by absent gear, airborne work independent **pending** |
| AV-29 | Matched installation physical validation and pilot acceptance | Held-out engine runs and flight cards; unsupported domains and remaining uncertainty published **pending** |
| AV-30 | Fleet/full-suite, cost and clean export integration | Generator `--check`, isolated LF full suite, no unrelated regressions, target cost, fresh-clone/export trace smoke; default promotion decision **pending** |

Dependencies:

```text
AV-18 -> AV-19 -> AV-20 -> AV-21
AV-19/21 -> AV-22 -> AV-05b
AV-19/21 -> AV-10a -> AV-10b -> AV-10c
AV-05b/10c -> AV-24 -> AV-27 -> AV-28 -> AV-29 -> AV-30
AV-23/25/26 are evidence-gated extensions; they cannot block a verified minimal slice.
AV-09 + ground/start qualification -> ground portions of AV-28 only.
```

If implementation uses Luna Max agents, assign isolated boundaries: manufacturer/source reduction, disposable analytic kernels/oracles, and authored aircraft data. The lead alone owns shared session/schema/rigid-body integration. Avoid concurrent production-data regeneration or shared-preference tests. Source work can parallelize; mutating integration and timing are sequential.

## 14. Verification commands and evidence layout

Use [TOOLS](../TOOLS.md) for the pinned Godot and full platform workflow. On this Windows checkout, full Bash checks belong in a fresh LF WSL/Linux checkout; do not claim PowerShell ran `app/test.sh` successfully. Inspect generator freshness at baseline before regeneration and preserve platform float drift as described in LEARNINGS.

Existing focused commands, from the repository root in the documented Linux environment:

```bash
python3 research/avanti-s/av06/derive_physics.py --check
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_turbine.gd
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_avanti_handling.gd
app/test.sh
```

New kernel/session/event/fuel tests and reducers must be added to the appropriate existing runner once implemented. Do not list a proposed script as a currently working command. Broader CI generator/schema/tool/capture checks and native package tests follow the owning integration slice; this documentation change needs link/structure/source QA, not runtime golden regeneration.

Evidence uses `docs/research/turbine-realism/<step>/` and reusable scripts/raw-data reducers use `research/avanti-s/` under explicit step directories. Each result includes baseline/candidate source and aircraft hashes, accepted model law/presets, command/ambient/fuel history, true sample times, calibration/uncertainty, reference method, fresh complete outputs, acceptance result and limitations. Large copyrighted publications are linked/fingerprinted rather than bundled automatically. Raw physical records require clear provenance and permission for repository distribution.

Keep tests, comparison traces and evidence together in each small commit. Do not re-record goldens for accidental changes or to hide unexplained behavior. Unrelated baseline failures must be reproduced on the frozen baseline and reported separately, never suppressed. Proposed decisions become DECISIONS entries only when chosen; reusable findings go to LEARNINGS only if they meet its criteria.

## 15. Completion criteria and exclusions

The minimal realism milestone is complete when the selected P100 profile has stage-coupled response, causal shutdown/cooling, explicit fuel use and depletion with consistent mass properties, truthful presentation and complete lifecycle verification. It may still be labeled experimental while physical gates remain open. Physical acceptance requires the matched measurements and declared envelope in AV-29; no feature checklist substitutes for them.

Ground-flight qualification, general fuel CFD, complete proprietary ECU emulation, compressor/turbine design reconstruction, universal stochastic reliability, structural turbine destruction, afterburners, thrust vectoring and new engine/aircraft catalog entries are separate scopes. Keep their useful research questions, but prioritize the measurable response, fuel, force and aircraft-energy behavior that the current simulator can integrate and validate incrementally.
