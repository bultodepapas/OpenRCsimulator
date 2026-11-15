# Physics and propulsion design investigation

**2026-11-15 · A120 research.** This is a proposed physical model and calibration strategy, not implemented behavior. [Source IDs](sources.md) identify evidence; [source audit](integration-audit.md) identifies what OpenRC already supports. The [plan](../../plans/aeris-120-3d-gas.md) owns delivery gates.

## 1. Scale, mass and geometry

The target is an original giant-scale **RC** aircraft. Full-scale Extra performance, another simulator's settings or a geometrically enlarged Extra .60 cannot establish its flight model. Reynolds number, propwash coverage, component mass distribution, surface travel and power loading differ.

Using the prior design inputs `b = 2.64 m`, `S = 1.2408 m²` gives the following **derived geometry checks**:

| Quantity | Relation | Result |
| --- | --- | --- |
| Aspect ratio | `b²/S` | 5.6170 |
| OpenRC coefficient reference chord | `S/b` | 0.4700 m |
| Illustrative mass loading at assumed 12.6 kg | `m/S` | 10.1547 kg/m² = 101.55 g/dm² |
| Illustrative weight loading | `mg/S`, `g = 9.80665 m/s²` | 99.584 N/m² |

The 12.6 kg assumption is a calculation example, not an AERIS mass measurement. It must not silently become authored dry mass. For the same example and assumed `CLmax = 1.2…1.5`, `rho = 1.225 kg/m³`, the steady unpowered estimate `Vs = sqrt(2mg/(rho S CLmax))` is approximately **10.41–11.64 m/s**. This is a sensitivity calculation, not a target stall speed; powered high-alpha flight does not follow that simple relation.

OpenRC defines `mean_chord` as `S/b`. Retain true MAC separately for geometry/stability studies: for a symmetric planform, `MAC = (2/S) integral_0^(b/2) c(y)² dy`, with the corresponding leading-edge station. Do not change coefficient reference length while retaining derivatives normalized with another length. Donor CG measured from its root leading edge is not transferable by copying millimetres or an unverified chord percentage.

Build mass from identified wing/fuselage/tail, engine/exhaust, prop/spinner, gear, receiver/ignition batteries, servos, hardware, empty tank and liquids. The visual model's material count or bounding box supplies no density distribution. Use the existing inventory and parallel-axis transformation, with a positive-definite full inertia tensor and physically consistent principal moments. Do not count installed engine/prop/fuel mass twice.

Fuel changes mass, CG and inertia together. Preserve the repository's reference inventory CG as fixed datum O, and evaluate loads about the live CG under the existing finite-fuel transaction. Applying a moving CG offset twice creates spurious moments. Tank shell remains after fuel depletion; unusable/reserve quantities have their documented meanings. See the [fuel standard](../../FUEL-SYSTEM.md).

## 2. Frames, local velocity and force accounting

The [aircraft contract](../../AIRCRAFT_CONTRACT.md#coordinates-signs-and-units) governs implementation:

- Authored positions: wing-leading-edge datum, aft/right/up, metres.
- Physical body: forward/right/down (FRD); world: north/east/down (NED).
- Stored body kinematics for finite-resource configurations refer to fixed O; moments are transferred to live CG.
- Orientation: scalar-first body-to-NED quaternion; render coordinates are converted at the boundary.
- Shaft sense: currently clockwise viewed from behind. A manufacturer's “counter-clockwise” description requires its viewing-direction definition before comparison.

For a component at O-relative body position `r_i`, the air-relative velocity is conceptually

`V_rel,i = R_BW (v_O,world - v_air,world(x_i,t)) + omega_body × r_i`.

Here `v_air` is actual local air velocity, including any modeled induced velocity. A wake moving aft increases forward relative flow behind a tractor propeller. If a shared API instead returns a **relative-flow increment**, its sign is already converted; never apply both conventions. Define this explicitly for wing, tail, propeller and wake consumers.

Compute local dynamic pressure from the relevant section-plane velocity, use `atan2` for signed section angles and preserve the full vector direction. A conventional sideslip angle in ±90° cannot alone distinguish reverse flow; the vertical surface needs its own plane angle or equivalent vector treatment. At exactly zero local flow the aerodynamic load is zero. Epsilons may regularize a denominator, but must not create a minimum physical airspeed or free control power.

Sum component forces and their actual arms:

`F_body = sum(F_i) + F_prop + F_contact`

`M_CG = sum((r_i - r_CG) × F_i + M_section,i) + M_prop + M_contact`.

Gravity and variable-mass terms stay in their existing owners. Avoid retaining a whole-aircraft damping derivative and adding the same damping again through local `omega × r`; the existing small-angle oracle/local-load blend must have a single ledger. This requirement also applies to sideforce, downwash and the tail wake increment.

## 3. Aerodynamics across the operating envelope

Selig's RC work supports component/strip methods for large deflections and broad flow angles; it is explicitly quasi-steady and provides no AERIS coefficient set [S13]. The design recommendations below adapt that class of method to OpenRC's existing laws.

### Attached flight

Retain left/right wing sections, horizontal/vertical tail and declared fuselage terms. Match geometry, neutral incidence, lift slopes, drag and pitching moment to one coherent convention. Identify low-angle trim and control response at several speeds before tuning high-alpha behavior. Use local angular motion to generate roll/pitch/yaw damping, retaining only justified residual terms.

Use airfoil/polar tools within their domain. Low-angle potential-flow or XFOIL-style predictions can supply hypotheses for attached flow; they do not establish separated three-dimensional motion, an exact `CLmax`, large-deflection hinge loads or a complete 360° database. Match Reynolds regimes and record surface roughness/transition assumptions.

### Stall, high alpha and reverse section flow

Use continuous positive/negative-angle forces, moments and control effects. Verify forward/separated blend boundaries, zero speed, ±180° continuity and reversed control geometry. Separate the control-induced camber change from any fitted change in stall boundary; a single angle shift can generate artificial reversal in a steep stall ramp. Conversely, forcing positive aileron authority everywhere is not a valid universal physical law.

Large elevator/rudder travel needs bounded lift/normal-force, drag and moment behavior; extrapolating a linear derivative to 55° can grossly overstate authority. Differential left/right local flow must allow asymmetric stall and autorotation without a “spin detected” branch. A geometric perturbation or documented asymmetry may seed a case; random roll impulses are not calibration.

OpenRC already supports local strips, optional wing polars, body sideforce and a separated-wing force-offset couple. Use them within their declared limits. The current six-strip resolution is a starting point: compare force/moment convergence with finer resolution before changing shared discretization. Refine propwash overlap without pretending every half-wing section sees one uniform jet.

### Knife-edge and coupling

Evaluate vertical-tail force and fuselage crossflow at appropriate positions. On a banked aircraft their world components can support weight, while their arms and thrust/CG offsets create roll/pitch/yaw coupling. Calibrate both knife-edge directions with mixes disabled. Perfect symmetry is not a whole-aircraft requirement: propeller rotation, vertical-tail location and installation offsets can produce differences. Do not add a world-up “knife-edge lift” term or suppress coupling through hidden trim.

### Unsteady aerodynamics

Static polars cannot identify separation delay, hysteresis, wake history or wing-rock frequency. Unsteady roll research supports using dynamic data, but transport-model coefficients are not transferable [S16]. First fit mass, actuator motion, propulsion and quasi-steady loads. Introduce separation/wake state only when a repeatable held-out discrepancy remains.

A first-order state such as `df/dt = (f_eq(alpha, delta, Re) - f)/tau` is a **candidate approximation**, not a calibrated dynamic-stall model. Its state, limits, initial conditions, regime dependence and observability need specification. Avoid singular `tau ~ c/V` behavior at zero velocity. Add no canned oscillation for harrier, fixed snap duration or scripted tumble. L3 claims require their own dynamic evidence.

## 4. Gasoline engine operation

The DA-120 reference is a two-stroke gasoline installation with a diaphragm carburetor and electronic ignition [S04, S05]. The selected healthy reference should support ordinary upright/inverted aerobatics. Carburetor orientation capability does not guarantee fuel pickup under every acceleration or tank condition [S12].

### Minimum mechanical model

Reuse the existing coupled shaft, with consistent units. For a **fixed-carrier bench** only, the load relation is:

`I_rotor * dOmega/dt = Q_engine(Omega, carburetor_command, air_charge, engine_state) - Q_prop(Omega, inflow) - Q_loss`.

In flight, OpenRC stores `Omega` relative to the aircraft. For a shaft axis fixed in the body the coupled relation is `I_rotor * (Omega_dot + e_shaft · omega_body_dot) = Q_engine - Q_prop - Q_loss`. Retain `RotorCoupling` and `FlightSession._coupled_response()` to solve body and relative shaft acceleration together. Independently integrating the bench equation during a torque roll would omit axial body acceleration and give the wrong RPM/reaction exchange.

Throttle changes torque request; RPM changes through rotor inertia and load. The propeller then changes thrust, torque and wake. A throttle-to-thrust multiplier or instantaneous RPM curve misses unloading, braking and the delay a pilot manages in hover. The published peak horsepower does not specify torque at idle or every RPM; do not infer constant power down to zero speed.

Fit idle torque/friction, steady load points and acceleration/deceleration separately. Identify prop, exhaust, mixture setup, density and temperature with each observation. Do not assert an arbitrary universal throttle time constant. Carburetor/throttle-servo motion is a separate proposed input state; it must not be confused with RPM inertia or added twice as generic lag.

### Lifecycle boundary

Current legacy gasoline starts already running; the detailed glow start/cut/mixture API is a different installation. A gasoline lifecycle extension should specify ignition-off, stopped, starting, running and stopped-by-fuel/ignition states, accepted transitions and restart policy. An explicit convenience ground start can coexist with mechanics. Raising throttle on a stopped gas engine must not start it as an electric motor.

Ignition kill, idle throttle and fuel-out are different events. Mid-air restart, choke/flooding, thermal behavior and fuel unporting are later scope unless supported by data and a complete shared lifecycle. The baseline must not add random coughs, automatic inverted flameout or arbitrary engine failures to sound realistic.

### Fuel and atmosphere

Use `gasoline_bsfc_v1` and the existing gasoline blend registry initially. Calibrate fuel flow separately from thrust. A nominal one-litre tank is proposed; no endurance is claimed. Current gasoline feed is not a pressure/slosh/pickup solver, so attitude-related fuel starvation remains an explicit limitation.

At fixed RPM and coefficients, prop thrust/torque scale with density, but **fixed throttle is not fixed RPM**. Recompute engine charge, shaft equilibrium and prop load together. Qualify more than one density condition without assuming the user's flying site from their time zone. Display/lighting choices cannot alter atmosphere physics.

## 5. Propeller data and load checks

The proposed initial surrogate is **Mejzlik 28×10 2B GAS EVO LF**, PN 228108, rev. 3.0. Its source specifies 182 g ±10%, estimated axial inertia `0.00767 kg·m²` and a 6,400 RPM tip-speed limit reduced by forward speed. Its performance table is simulated at 5,000 RPM [S06]. Confirm the actual prop version before implementation; other 28×10 props are not the same dataset.

For `n = RPM/60`, diameter `D`, and axial aircraft-relative flow `Vax`:

`J = Vax/(n D)`

`T = rho n² D⁴ Ct(J)`

`P_prop = rho n³ D⁵ Cp(J)`

`Q_prop = rho n² D⁵ Cp(J)/(2 pi)`.

The torque expression avoids a separate division by zero RPM, but evaluating `J` still needs a qualified low-speed/stopped-rotor regime. Ct/Cp may depend on Reynolds number, nonaxial inflow and other variables absent from a one-speed table. A simulation must not blindly extrapolate into reverse flow or clamp every negative coefficient to zero. Negative thrust can represent braking; negative power can represent energy transfer to a windmilling rotor. The usual propulsive efficiency ratio is not a useful “efficiency percentage” in every sign regime.

At assumed `rho = 1.225`, `D = 0.7112 m`, `n = 5000/60`, and the source's static `Ct = 0.0816`, `Cp = 0.0264`, the equations give approximately **177.6 N**, **3.405 kW**, **6.50 N·m**. With the illustrative 12.6 kg aircraft this is **T/W ≈ 1.437**. This is an algebra check of an isolated simulated prop point, not a full-throttle DA-120 prediction or proof of hover margin. The installed equilibrium RPM must satisfy the engine/prop torque balance.

The engine's listed upper RPM and the prop's operating limit are separate. Select/calibrate the installation inside its declared envelope; do not impose an undocumented perfect governor merely to hide a mismatched prop. Mark unqualified operating regions. The current legacy gasoline code's negative-advance clamp needs a versioned signed-flow investigation before tailslide realism is claimed.

## 6. Torque, gyroscopic effects and wake

Maintain one accounting convention for body and rotor angular momentum. Shaft reaction, prop aerodynamic drag torque and rotor acceleration are related; summing a motor-reaction formulation and a separate spin-up correction double-counts the effect. The existing coupled solver is the implementation starting point.

For a diagnostic using locked-assembly inertia `I`, rotor relative angular momentum `H = I_rotor Omega e_shaft`, and constant mass, a total-system statement is

`I omega_dot + omega × (I omega + H) + H_dot_body = M_external`.

External moment includes aerodynamic propeller torque; engine torque is internal to this total-system balance. An airframe/rotor split can instead use the appropriate bearing/motor reaction. Document which inventory inertia and relative rotor acceleration each formulation uses, and never combine the two. For changing fuel mass use the established finite-mass formulation, not this simplified diagnostic as a replacement.

Distinguish four effects in telemetry and tests: axial thrust applied at the hub; reaction roll torque; gyroscopic coupling when the shaft axis rotates; and aerodynamic nonaxial/P-factor loads. Swirl is the air's rotation and affects immersed surfaces; it is not another copy of engine reaction torque. Geometry, sign and source identity must remain consistent across all of them [S14].

For a positive-thrust static actuator-disk check, `vi = sqrt(T/(2 rho A))`, `A = pi D²/4`, gives disk induced velocity and an ideal far-wake increment near `2vi`. It is a normal-working-state sanity check, not a universal field through descent, strong crossflow, windmilling or reverse flow. A120-04 must specify spatial coverage, contraction/decay, swirl and permitted transport combinations.

The tail and only the intersected wing/aileron area retain powered authority at zero freestream speed. Wake velocity belongs in the same local section law used for unwashed loads; choose either full replacement or a mathematically consistent washed-minus-unwashed increment. Do not apply both. Apply prop thrust once; do not add its momentum-disk thrust again when computing surface wash.

A throttle chop should propagate through shaft speed, wake history and actual surface loads. A rolling harrier or rapid pitch/yaw maneuver changes hub inflow and wake exposure, so instantaneous global “control boost” cannot reproduce the same coupling. The current axial transport option is valuable but restricted; the source audit defines what must be extended.

## 7. Numerical implementation constraints

Keep the production 240 Hz float64 RK4 contract. Evaluate every coupled physical quantity at the correct stage with the stage mass/CG, attitude, rates and inflow. Surface sampling and discrete engine events retain their declared timing. Continuous wake/engine/separation additions require model-owned derivatives and versioned state; force evaluation must remain pure.

Test zero flow/RPM, fuel boundaries, large throws, high angular rates, reversed sections, table boundaries and pause/reset/restore. Define native/reference support explicitly: fail closed or use the existing qualified fallback when a capability is unsupported. A code path accepting a field is not source-bound native qualification. See the [test protocol](controls-and-validation.md#numerical-and-integration-gates).

Do not use clamps, extra damping, timestep changes or altered goldens to conceal an unexplained energy increase or a divergent regime. Diagnose units, signs, duplicate moments, state timing and model applicability first. Numerical convergence and smooth force curves remain separate from physical validation.
