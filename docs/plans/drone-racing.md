# 5-inch FPV racing drone: simulation integration plan

**Revised:** 2026-10-21; **status and remediation updated 2026-11-16.** **Status:** an EXPERIMENTAL software slice of M1–M3 is implemented: closed-loop free flight in the app and a local three-lap gate race, on estimated data. [§15](#15-implementation-status-2026-11-11) owns delivered step status and supersedes the historical "open" markers in §10; [§16](#16-audit-remediation-programme-2026-11-16) owns current repair priorities and acceptance. Implemented does not mean audit findings are closed. Physical, pilot, target-host and CI gates remain open. The [FPV handoff pack](../../FPV/00_START_HERE.md) (2026-11-11) holds the detailed contracts this implementation followed.

**Owner / IDs:** drone track, DR-00…41, under main-line acceptance; existing IDs are retained. **Evidence:** [2026-10-21 investigation](../research/drone-racing/DR-01/refresh-2026-10-21.md), [original source survey](../research/drone-racing/DR-01/README.md), [implemented foundation](../research/drone-racing/DR-04a/README.md). The original survey remains dated research, not the current implementation specification.

## 1. Outcome and delivery boundaries

Add one identified **5-inch-class, fixed-pitch electric quad-X racer**: select it on Home, start disarmed on a qualified pad, arm at low throttle, fly Acro through an onboard FPV camera, land/disarm and reset. Include optional Angle training, radio/gamepad input, adjustable rates/camera tilt, four visible rotors and flight logging. Add gate racing after free flight works.

| Milestone | Deliverable | Release gate |
| --- | --- | --- |
| M1 — headless flight | Strict data, sampled controller, dedicated session, arm/disarm from a test action tape and exact replay on the simple plant | Laboratory only; DR-02/03, 06/07, 09a, 10/11/13, 16/17; device bindings follow in DR-14 |
| M2 — experimental FPV free flight | Race configuration, shared pack/bus and motor response, pad/contact/crash lifecycle, downloaded visual, FPV, input/settings, minimal OSD/audio | DR-05, 08/09/12, 14/15, 18…22, 29…31, 35, 36a/37; software/usability gates in §11 |
| M3 — local gate racing | One track, swept gate checks, timer, invalid laps, deterministic results and pad respawn | DR-23…26, 32, 36b; M2 gates remain passing |
| M4 — fidelity qualification | Advanced rotor laws, held-out data comparison and measured selected-build response | DR-04, 38…40; promote only supported regimes |

M2 is **EXPERIMENTAL**, with explicit aerodynamic limits. Racing geometry does not establish accurate high-speed handling. M4 can run alongside product work, but M1–M3 grant no claim of validated propwash, VRS, exact Betaflight behavior or physical realism. Data from another quad does not validate this build.

Deferred: multiplayer, online rankings, GPS rescue/autopilots, turtle/reverse-thrust mode, whoops, 7-inch vehicles, track editor, structural damage, thermal fidelity and RF/video simulation. Horizon mode, ghosts, extra tracks, night effects and elaborate particles are not first-flight dependencies.

## 2. Repository baseline and ownership

Inspected at `22396c6e` on 2026-10-21. The checked native Godot runner reproduced **15 checks, 0 failed** for the existing multirotor test. This establishes those software checks only.

| Existing seam | Reuse / required change |
| --- | --- |
| [VehicleModel](../../app/sim/vehicle_model.gd), [Simulation](../../app/sim/simulation.gd) | Shared float64 kernel, 240 Hz outer ticks, joint RK4 stages, state transactions/checkpoints. No drone-specific kernel branch. |
| [Plant](../../app/physics/multirotor/plant.gd), [rotor](../../app/physics/multirotor/rotor.gd), [powertrain](../../app/physics/multirotor/powertrain.gd), [airframe](../../app/physics/multirotor/airframe.gd) | Four quadratic rotors, first-order speeds, drag, rotor momentum and raw duty inputs exist. No controller, disarm state or battery. Keep this law as a reference. |
| [Kernel test](../../app/tests/test_dr_multirotor_kernel.gd) | Hover, signs, inertial yaw, drag passivity, wind and replay checks exist; add independent conservation, configuration and failed-tick tests. |
| [Helicopter session](../../app/sim/helicopter_flight_session.gd), [activity](../../app/helicopter_main.gd) | Precedent for a specialized session installing a model. Reuse contracts/helpers; do not copy the whole activity or branch fixed-wing FlightSession. |
| [Electric motor](../../app/physics/electric_motor.gd), [supply](../../app/physics/electric_supply.gd), [battery plan](battery-realism.md) | Reuse supported equations through a four-load adapter with one bus and one pack state; coordinate EL/BAT. |
| [Shared inflow](../../app/physics/rotorcraft/inflow.gd) | HELI owns the law. DR needs a qualified small-prop consumer; helicopter source agreement is not racing-propwash validation. |
| [Input](../../app/input/rc_input.gd), [commands](../../app/input/commands.gd) | Reuse device ownership/calibration/holds. Add drone action semantics; airplane servo shaping is not a rate controller. |
| [Catalog](../../app/app_state/aircraft_catalog.gd), [shell](../../app/app_root.gd), [landscapes](../../app/landscapes/catalog.gd) | Explicit multirotor route, capability-based availability and selected field geometry. Do not classify the quad as a helicopter. |
| [Camera rig](../../app/render/camera/camera_rig.gd) / [CAM plan](camera-views.md) | Pilot/chase/orbit/close-up exist. FPV mount/view remains CAM-11…13 work. |
| [Flight logging](../FLIGHT-LOGGING.md) | `.orfl` currently serves fixed-wing sessions. A multirotor adapter/envelope is a DR-17 gate, not an existing capability. |

DR owns `app/physics/multirotor/`, proposed `app/physics/multirotor_data.gd`, `app/sim/multirotor_flight_session.gd`, `app/multirotor_main.gd`, multirotor schema/generated data, its model adapter/assets, `app/sim/race/`, track data/visuals, focused drone/race tests, `research/drone-racing/` and evidence. Retain existing `test_dr_*` names; use established `test_mr_*`/`test_race_*` patterns for their steps.

SF/main physics owns contracts/kernel review; EL/BAT owns energy; HELI owns inflow; AS owns shared authoring helpers; GP/CR owns contact/crash; UI/input owns catalog/profiles/actions; CAM/HUD/AUD owns presentation; LU/SC owns field collision. Check [ownership](../README.md#tracks-plans-and-step-ids) and `git status` before editing. Serialize shared-file integration and preserve airplane, helicopter and truck regression gates.

## 3. Reference build, assets and provenance

Keep three identities separate:

1. **Laboratory fixture:** `Plant.research_quad()` remains a software fixture, never a catalog aircraft. Its 152 mm motor diagonal implies adjacent spacing `152 / sqrt(2) = 107.48 mm`, below a 127 mm prop diameter. It mixes borrowed/estimated values and cannot become a physical 5-inch configuration unchanged.
2. **Research comparison:** reproduce one exact NeuroBEM/Agilicious configuration. Reconcile differing masses, motor fits and frames; do not combine parameter rows from different aircraft into a supposedly identified quad.
3. **Product build:** proposed ID `openrc-fpv5`, named **FPV 5-inch · Experimental** until the assembly is fixed. Use a downloaded racing frame, 5.0-inch props (127 mm; any 5.1-inch variant is explicitly 129.54 mm), matched motor/prop/voltage data and inventory-derived CG/inertia. A 6S/2207-class candidate is a planning direction, not an accepted configuration. Record all-up mass including battery; do not tune toward a guessed thrust-to-weight ratio.

**Reuse before authoring.** First candidate: [OpenRacer frame/canopy CAD](https://github.com/OpenRacer/OpenRacer), whose repository identifies a 5-inch configuration and GPL-3.0 license. Audit selected files and license obligations, pin a commit, retain source/attribution and make a reproducible CAD-to-GLB adapter. This is a frame asset, not a complete measured drone. A complete CC BY-SA visual and CC BY component alternatives are in the [asset shortlist](../research/drone-racing/DR-01/refresh-2026-10-21.md#asset-and-data-intake). Verify actual archives and constituent licenses before bundling. Do not create a procedural replacement for a suitable free download; missing parts remain an intake task.

[Five33 LightSwitch V2](https://flyfive33.com/pages/lightswitch-v2) is an official 5-inch racing-frame reference, not permission to redistribute its design. [T-Motor F60 PRO V](https://store.tmotor.com/product/f60prov-fpv-motor.html) supplies a 1750 KV/6S candidate with named-prop static bench data; those results do not establish torque, transient response or forward-flight behavior. Select compatible parts together in DR-02, rather than mixing convenient test rows.

Each asset/data manifest records URL, author, date, immutable version/SHA-256, license, modifications, units/axes and redistribution decision. Import checks hub positions, prop/prop and prop/frame clearance, camera mount and scale. Geometry does not establish material mass or inertia. Preserve existing aircraft node names; give the new adapter four stable rotor IDs rather than a fake one-prop alias that hides multiplicity.

## 4. Physics architecture

### 4.1 Fidelity ladder

| Level | Model | Evidence / limits |
| --- | --- | --- |
| Existing laboratory law | Quadratic thrust/torque, linear rotor drag, quadratic body drag, first-order motors | Known-answer reference; constant coefficients omit axial inflow and interactions. |
| Experimental product law | Sourced configuration, four-motor pack coupling, qualified motor response and sampled controller on the transparent load baseline | M2 software gates; estimates visible. No descent/propwash or racing-envelope validation claim. |
| Advanced law | Prop-specific blade loads, in-plane force/hub moment and qualified HELI inflow/ground effect | Separate law identity, domain, refinement and held-out benefit before activation. |
| Selected-build validation | Bench characterization and independent flight observations | Physical acceptance only for supported hardware, environment and maneuvers. |

Thrust alone cannot identify shaft torque, blade drag, radial geometry or unsteady wake. UIUC measured small-prop data does not cover every racing-RPM configuration. Faessler's identified drag is a whole-vehicle 6-inch prior, not measured per-rotor coefficients for this build. See [source corrections](../research/drone-racing/DR-01/refresh-2026-10-21.md#physics-and-controller-evidence).

### 4.2 Frames and rotor signs

Use NED world / FRD body and float64 scalars or `PackedFloat64Array`. Rendering converts at `render/frames.gd`. Store rotor speed in **rad/s**, as the current plant does; convert to RPM only for telemetry. Define `a = (0,0,-1)` as thrust axis, `s_i = +1` as CCW viewed from above, and hub `r_i` from the CG. Convert asset coordinates once at import.

Pin current quad-X numbering: 1 rear-right, 2 front-right, 3 rear-left, 4 front-left; spin is explicit data. More right-pair thrust rolls left; more front-pair thrust pitches nose-up; accelerating the CCW pair gives positive FRD yaw. Test individual motors and each admitted spin arrangement.

### 4.3 Aerodynamic loads

Every RK stage uses that stage's body, rotor speeds and environment:

```text
v_rel,i = v_body - R_world_to_body * wind_at_hub + omega_body × r_i
F_i     = T_i * a + H_i
tau_i   = r_i × F_i - s_i * Q_i * a + hub_moment_i
F_body,k = -0.5 * rho * CdA_k * v_rel,k * abs(v_rel,k)
```

Use the existing environment contract; uniform wind support does not imply resolved spatial gusts. Avoid double-counting body/rotor drag. Check passive drag work and Galilean/frame covariance.

HELI inflow is a later qualified consumer, not a first-flight blocker. Its isolated mean-inflow/VRS law cannot alone reproduce turbulent multicopter propwash oscillations. Qualify descent, oblique flow, stop, terrain orientation and clearance, including the documented C/M branch seams. Choose steady/dynamic inflow by model/data and timestep evidence; no guessed smoothing, noise shake or second ground-effect multiplier. Rotor/frame wake interaction remains a gap unless separately identified.

### 4.4 Four motors and one battery

All motors share **one stage-local bus voltage** and **one** pack's charge/energy state. Never solve four independent full packs. Keep motor, ESC and pack losses distinct and test power/energy closure.

DR-05 selects one coherent motor law: back-EMF/resistance/torque/inertia with load torque, or an empirical command/voltage-to-speed map and spin-up/down response with explicit energy-accounting limits. M2 may use public static-map fits and explicitly borrowed/estimated transient, torque and pack parameters, with uncertainty/sensitivity checks and energy closure. Missing selected-build measurements remain DR-40 gates, not hidden requirements for experimental flight. Do not stack an arbitrary first-order lag onto an already identified electromechanical response. The laboratory gains are not transferable: tune/qualify M2 control only after the product powertrain and pack are fixed.

Active braking, reverse rotation, bidirectional DShot telemetry and regeneration are different features. Do not assume braking returns current to the pack or DShot equals bridge duty. Start with supported motoring and a declared braking policy; enable signed pack current only with evidence, charging/overvoltage bounds and energy tests. This replaces the old mandatory `synchronous` ESC assumption.

Disarm means zero drive independently of armed idle; residual RPM decays under the chosen law. Current `Powertrain.duty()` always clamps to idle and is insufficient. Handle pack depletion and four rotor stops atomically, including simultaneous events. Post-step negative-speed clamping cannot repair invalid RK stages.

### 4.5 Mass, equilibrium and ground support

Derive mass, CG and positive-definite inertia from a sourced inventory, with an explicit motor-bell/prop inertia convention. Electric discharge changes energy, not modeled vehicle mass. Solve hover force/moment balance with individual arms/loads; the symmetric quadratic formula is only a known-answer case.

Start disarmed on a qualified flat pad with solved support equilibrium. Reuse isotropic contact kernels with GP/HELI where suitable. Test static support, friction, tip-over, touchdown, armed idle without unwanted lift-off and low-SOC takeoff. Sloped-pad starts are a later capability.

### 4.6 Rotor momentum and body coupling

For locked-rotor inertia `I_locked` and relative rotor momentum `h = sum(s_i J_i Ω_i a)`:

```text
I_locked * alpha = tau_external - omega_body × (I_locked * omega_body + h) - h_dot_relative
J_i * Ω_dot_i    = Q_motor_i - Q_aero_i - s_i * J_i * dot(alpha, a)
```

External torque includes prop aerodynamic reaction and thrust-arm moments. Motor torque is internal: do not add it again as an external torque. Solve relative shaft/body acceleration together; count `-h_dot_relative` exactly once across rotor evaluator and rigid-body kernel. Check steady yaw, zero-load angular-momentum conservation, motor work and nonzero body acceleration independently. The current inertial-yaw sign check is not a conservation proof.

### 4.7 Controller and timestep

Use simulator-owned Acro rate PID, explicit feed-forward/filter choices, anti-windup and bounded allocation with airmode. Angle is a bounded attitude-to-rate outer loop. Acro center sticks request zero angular rate, not level attitude. Airmode preserves low-throttle correction, subject to idle/output/voltage authority. [Betaflight mode semantics](https://betaflight.com/docs/wiki/guides/current/Modes).

Start at **240 Hz**. Import versioned Actual/Betaflight rate curves and explicitly supported throttle-curve fields. Reject unsupported curve types; report ignored PID/filter/motor-setting lines. Match full curves, not only endpoints. Do not silently import motor limits or claim Betaflight equivalence. Firmware code is GPL; independently implement documented behavior/math, or review applicable obligations before reuse. Any external firmware/SITL comparator is separately licensed and pinned.

A 240 Hz controller cannot represent filters above 120 Hz; a one-tick delay is not an equivalent filter. Use valid discrete filters, declare delay and test anti-windup/saturation recovery. Pin gains, sample rate, filter coefficients, scheduling and curve version into identity.

Separate (1) plant h/h2/h4 refinement with controller samples held at the same physical times, and (2) controller sample-rate/phase comparison against a higher-rate reference with a refined plant. Existing `substeps` refine the plant only. Repeated control on stale feedback is not a high-rate closed loop. If 240 Hz fails DR-21, stop promotion and qualify a generic sampled-event design with SF; do not change the global tick or run control in render callbacks.

## 5. Data contract

Create sibling `openrc-multirotor v1`, sharing v2 quantity/provenance rules, not airplane wing/tail/trim requirements. Blocks: identity/capabilities, inventory/balance, four hubs/axes/spins/props, rotor law/domain, motor/ESC, one battery, controller/rates, supports/hull, camera and starts. Physical quantities carry `{value, unit, kind, source}` with measured/borrowed/derived/estimated distinctions.

Reject unknown keys, nonfinite/wrong-unit values, missing/repeated motors, invalid axes/spins, nonpositive inertia, overlapping coplanar props, prop/frame intersections, inconsistent CG/inertia, unreachable hover, invalid idle/output bounds, controller timing or operation outside the declared model domain. Estimates can be explicitly accepted; missing data cannot become silent defaults.

Generate schema/data from source tables via `research/drone-racing/<build>/derive.py --check`; never hand-edit generated JSON. Pin exact source bytes, normalized law/config, geometry and control profile. `openrc-rates v1` is separate from powertrain configuration; track schema/rule identity is separate again.

## 6. Session integration and transactions

```text
Home / direct route -> validated drone + field + rates -> MultirotorFlightSession
  -> sampled pilot actions / controller -> VehicleModel -> existing Simulation
  -> accepted telemetry/events -> recorder, FPV, audio, OSD, optional race director
```

Add a dedicated session/activity. Any kernel extension must be generic, opt-in and preserve existing callback behavior exactly.

**Resolve control feedback before DR-07.** `pre_tick(aux, inputs, dt)` has no body-rate argument; `Plant.duties` lives outside kernel rollback. Preferred design: an opt-in body-aware sampled callback reads a detached accepted start-of-tick state and returns persistent controller memory/outputs into checkpointed arrays. Current `stage(body, continuous, t)` also receives no aux snapshot: DR-16a must define a generic opt-in stage signature/context carrying the candidate sampled snapshot, with legacy dispatch unchanged. Stages must receive that output without hidden mutable authority. Specify feedback, stage access and rollback together. A session-owned transaction is acceptable only if it proves the same atomicity. Never mutate PID state in RK evaluation.

| State class | Contents |
| --- | --- |
| Body | Existing 13 float64 values |
| Continuous | Four rotor speeds; accepted battery states; contact/inflow state only when selected laws require it |
| Sampled | Controller integrals/filters/previous samples, motor commands, declared input-delay/scheduler state |
| Discrete | Arm/mode/failsafe/crash, source and event lifecycle |
| Session envelope | Vehicle/rates/law/backend/environment/field identities, tick policy, pending actions and kernel checkpoint |
| Race envelope | Track/rule identity, previous crossing state, start clock, next gate/laps/penalties and staging RNG if present |

Validate the full restore envelope before replacement. Failed tick/reload/restore must preserve controller state, cached commands, environment RNG, recorder cursor and race state. Inject failure after sampling, in k2/k4, at events and restore. Holds freeze controller/pack/race clocks and delay history.

SF-04b: a `step_policy` owns the whole tick and cannot also request kernel contact substeps; the generic locator can evaluate beyond zero. DR-09/16 must choose one compatible policy for contact stiffness, four rotor stops and pack depletion, including coincident events. Reuse current protocols before extending them.

DR-17 adds a versioned multirotor session adapter to the bounded, read-only recording/replay workflow. Until then `.orfl` commands do not support this vehicle. Record the sampled **pilot command tape**, switch events, FC/filter state, requested/achieved motor commands, RPM, voltage/current/SOC and full identities. Exact replay restores the full state and reruns the FC. A controller candidate must also rerun its FC from pilot commands; replaying baseline motor duties would bypass the change. Preserve a complete baseline, verify exact replay, then compare one candidate on the same physical tick/input tape. Inspect `complete` and `solver_changed`; retain CSV/markers/reports with the owning evidence and use existing free plotting tools.

## 7. Input and lifecycle

Map calibrated roll/pitch/yaw/throttle once; bypass airplane throws and duplicate expo. Radio throttle is absolute 0…1. Centered gamepad/keyboard throttle uses an explicit policy visible in setup and frozen through holds. Reuse current input ownership, profiles, actions/AUX and calibration infrastructure.

Arming requires valid input, low throttle and a new explicit request. Test high arm switch at launch, bounce, mode transitions, focus/device loss, reconnect, pause/resume and reset. Airmode never overrides disarm. Normal device loss follows established hold/rearm semantics; simulated failsafe-drop is a deliberate exercise, not a hidden crash policy. Audit key/action conflicts. Radio defaults to Acro; offer visible Angle training for gamepad/keyboard without claiming keyboard Acro is impossible.

## 8. Racing after free flight

Start with one data-defined course on a qualified field: pads, ordered gates, poses/dimensions, solid proxies, start/finish and versioned rules. Reuse suitable licensed gate assets. Initial simulator rules: staged ground start, forward gate sequence, missed-gate retry, three laps, invalid current lap after respawn and pad reset. Do not claim FAI/MultiGP compliance without a pinned edition and complete rule tests.

Time comes from simulation, never rendering/wall time. Sweep the scoring aperture between accepted states; sort multiple crossings in one tick. Test wrong direction, tangent/coplanar starts, edge/frame contact, high speed and deterministic crash/crossing ties. Keep scoring geometry distinct from solid gate/prop collision. Linear interpolation is exact only for the straight segment; bound curved-path error against refined trajectories. Rotated/dive gates require compatible collision geometry, not heading-only proxies.

Race state advances only after accepted physics and has a matching checkpoint/event envelope; no snapshot may expose different physics/race ticks. Persist results atomically with vehicle/rates/track/rule identities and validity flags. Automation uses scratch storage. Ghosts remain observational and deferred.

## 9. FPV and presentation

FPV defaults only for the new drone activity. CAM owns the onboard mount/view: same interpolated pose as the mesh, full body roll, adjustable uptilt and no hidden auto-level. Proposed preferences: 40° tilt, adjustable 0…60°; horizontal FOV 120°; 16:9/4:3. These are product defaults, not measured camera calibration.

With `Camera3D.KEEP_HEIGHT`, `vfov = 2 atan(tan(hfov/2) / aspect)`. Verify projection at both aspects. Use one interpolation owner, reset history on respawn and measure any added camera lag. Check near props/ground/gates and far-field depth precision. [Godot 4.7 Camera3D](https://docs.godotengine.org/en/4.7/classes/class_camera3d.html).

Additional RC/video latency defaults off. A future measured-delay option must separate transport, controller/motor and glass-to-glass delay instead of summing overlapping figures. OSD/blur/audio/effects read accepted/interpolated telemetry only; discs follow achieved RPM/spin, not duties. Preserve existing stopped-prop visuals and reuse HELI/VQ patterns where compatible.

Minimal OSD: arm/mode, timer, profile, throttle, pack voltage/current/charge where modeled and experimental status; add lap/next gate in M3. Do not fabricate battery readings for the ideal-energy laboratory law. Reuse licensed audio/current AUD mixing before creating assets. Pilot/chase inspection remains available. Distortion, video noise, dust, grass wash and night lighting cannot delay M2.

## 10. Steps and dependency order

Each row is a reviewable change or splits into named suffixes without renumbering established IDs. **Open** means proposed. Proof belongs beside each step's evidence.

### Foundations and configuration

| ID | Work | Proof / status |
| --- | --- | --- |
| DR-00 | Registration and scope | Done historically; 5-inch plan refreshed here. |
| DR-01 | Sources and implementation audit | Original survey plus [dated refresh](../research/drone-racing/DR-01/refresh-2026-10-21.md). |
| DR-02 | Lock assemblies, assets, versions/licenses and measurement gaps | Source matrix, geometry/clearance audit; open. |
| DR-03 | Independent reference harness; reuse existing free tools/data | Units, known answers, conservation and sampled-control reference; open. |
| DR-04a…06a | Existing quadratic plant / first-order motors / drag | Delivered; 15 checks rerun. Laboratory only. |
| DR-04 | Advanced prop/HELI inflow consumer | Flow domain/seams, refinement and held-out benefit; M4, open. |
| DR-05 | Four-motor bus, pack, ESC and motor response | Public-source map residuals, estimated-parameter sensitivity, power/energy closure and depletion/stops/braking; selected-build measurements remain DR-40; open. |
| DR-06 | Coupled rotor/body momentum audit | Conservation, shaft work, steady/dynamic yaw; open beyond 06a. |
| DR-07 | Acro/Angle controller, mixer, anti-windup/lifecycle | Independent reference, signs, saturation; open after 16a. |
| DR-08 | Versioned rates importer | Full curve vectors, malformed/unsupported input and ignored-field report; open. |
| DR-09 | 09a simple-plant refinement/cost; 09b energy/contact/event policy | Fixed-sample h/h2/h4, coincident events, bounded work and timing; open. |
| DR-10 | Sibling schema, loader, immutable preparation | Malformed/unit/nonfinite/geometry/inertia rejection; open. |
| DR-11 | Exact research profile generator | Same-aircraft provenance and reproducible `--check`; open. |
| DR-12 | Race assembly generator | Five-inch clearance, matched motor/prop/voltage and explicit estimates; open. |
| DR-13 | Authoring/generator documentation | AS review; fixed-wing behavior preserved; open. |

### Session and first playable activity

| ID | Work | Proof / status |
| --- | --- | --- |
| DR-14 | Input/actions, arm/mode, throttle and holds | Device/focus/reconnect tests; existing input behavior unchanged; open. |
| DR-15 | Rates selection/identity | Correct sampled curves, no double shaping, persistence; open. |
| DR-16 | 16a transactional feedback/stage-access design; 16b session/activity | Generic contract/fault proof and fleet preservation; open. |
| DR-17 | Full checkpoint and recording/replay adapter | Complete exact replay, atomic rejection and controller-aware candidate workflow; open before tuning. |
| DR-18 | Pad/hover equilibrium and startup | Solved support, unreachable-hover refusal, idle/disarm/takeoff; open. |
| DR-19 | Leg/hull contact and swept rotor-envelope strikes | Terrain/post/edge/tunneling; stopped props retain appropriate physical hull; open. |
| DR-20 | Crash motor cut, held aftermath and pad reset | Explicit rearm, reset state and log closure; open. |
| DR-21 | Product controller qualification after DR-05/12 | Axis step/doublet, saturation/low-voltage recovery, sample-rate/phase checks; open. |
| DR-22 | Endurance/cost | Ten-minute runs, 30 pad cycles, no silent backlog/fault/energy gain; p50/p95; open. |
| DR-29 | Downloaded asset and deterministic adapter; optional PREVIEW | Licenses, source/GLB hashes, hubs/camera/scale; open. |
| DR-30 | Four-rotor presentation | Achieved RPM/spin, start/stop captures, airplane regressions; open. |
| DR-31 | CAM FPV view/mount and minimal OSD | Projection/roll/tilt/reset at 30/60/144 fps; replay unchanged; open. |
| DR-35 | HUD/help/localization and basic audio integration | en/es 720p/1080p, truthful telemetry, licensed sound; open. |
| DR-36 | 36a EXPERIMENTAL free flight; 36b race entry | Home/direct launch, vehicle switch, malformed data refusal, fresh-package smoke; open. |
| DR-37 | Crash labels/presentation and restart UX | Cause/rearm clarity. Race flow done in software (2026-11-12): contextual start hints, reason-specific refusals, one-key retry (G/R); elaborate wrecks deferred. |

### Racing and validation

| ID | Work | Proof / status |
| --- | --- | --- |
| DR-23 | Track format/loader and one course | Invalid geometry, terrain/obstacle conflicts and rule tests; open. |
| DR-24 | Scenery proxies and world identity | Hull/prop sweep and track-mismatch restore rejection; open. |
| DR-25 | Gate director/timing/checkpoint | Known times, curved-path refinement, multi-crossing/tie cases and exact lap replay; open. |
| DR-26 | Results/race route/finish summary | Atomic persistence, validity rules, isolated automation; open. |
| DR-27 | Local ghost | Observational identity proof; deferred. |
| DR-28 | Additional tracks / published rule formats | Pinned layouts/editions and clearance checks; deferred. |
| DR-32 | Licensed track visuals | FPV readability, proxy alignment and cost; M3 open. |
| DR-33 | Rich four-motor audio | Licensed intake, RPM/load response and listening comparison; deferred beyond basic M2 sound. |
| DR-34 | Wash/grass/particles | Zero-load/observational guards; deferred. |
| DR-38 | Held-out model/data comparison | Exact configuration, frames, splits, regime residuals; M4 open. |
| DR-39 | Experienced FPV pilot review | Rates/hardware recorded, baseline/candidate maneuver card; open. |
| DR-26a | Local race records and medals | Record book per course identity, geometry-derived medal targets, results card; software repairs and pilot review open. Historical alias: DR-40 (records). |
| DR-40 | Selected-build physical validation | Mass/CG/inertia, thrust/torque/RPM/current, steps, Blackbox and independent motion with uncertainty; open. |
| DR-41 | Capability expansion | Separate revision after evidence; deferred. |

**Critical path:** DR-02/03 + 16a → 10/11/13 + 06/07/09a → 16b/17 (M1) → 05/09b/12/14/15/18…22 + 29…31/35/37 → 36a (M2) → 23…26/32 → 36b (M3). Run asset/data intake alongside isolated reference work; serialize shared contracts/session/input. DR-04/38 is a separate fidelity branch. No reliable calendar estimate precedes source/asset intake and the transaction-seam design.

## 11. Acceptance and evidence

| Gate | Required proof |
| --- | --- |
| Physics software | Independent dimensional/sign/momentum/work checks, hover, passive drag, one-pack energy and valid state domains. Absolute plus relative tolerances/scales fixed before results. h/h2/h4 over hover, punch/chop, flip, descent and contacts; do not demand smooth fourth-order convergence across discontinuities. |
| Controller | Proposed engineering screen against pinned higher-rate reference: rise-time error ≤15%, settling-time error ≤20%, overshoot difference ≤5 percentage points of commanded step. Fix step size/window/settling band and non-settling failure policy before running. Include saturation and low voltage; no growing sustained oscillation. This is not hardware validation. |
| Transaction/replay | Same-build/platform complete exact baseline replay; restore mid-maneuver/pause/stop/depletion; malformed/mismatched rejection and injected rollback failures; identical physics at 30/60/144 fps. Check cross-platform identity rather than assuming it. |
| Existing vehicles | Relevant SF/input/catalog/checkpoint/contact/camera and fleet golden/trace checks; unchanged airplane/helicopter/truck trajectories. No golden rerecording for documentation/routing. Full `app/test.sh` and required CI before feature merge; [TOOLS](../TOOLS.md) owns commands. |
| Performance | Named target host/engine/source; complete tick p50/p95/worst including contact/events. Proposed DR gate: ≤500 µs p95 whole tick at 240 Hz; ≤16.67 ms p95 rendered frame at 1080p on that host. State any difference from main-line Gate P; another vehicle's timing is not proof. |
| Product/visual | Native captures and interaction: FPV tilt/roll/FOV, fast roll, near clipping/gates, four props, OSD, hold/rearm, Home vehicle/field switching and imported assets in fresh exports. Still images cannot prove handling or latency. |
| Race | Exact lap list/validity on replay; ≤0.1 ms synthetic straight-crossing error, separately bounded curved-path error; no missed/double crossing at tested maximum speed; deterministic reset/crash ties/results. |
| Model/data | Freeze fit/held-out split before tuning. Reconstruct loads with correct mass/inertia/filtering/frames; compare baseline/candidate on the same samples/metrics. Published RMSE is context, not a transferable threshold. Report missing descent/high-speed coverage. |
| Physical/pilot | DR-40 qualifies the selected assembly within uncertainty/envelope. Motor commands are not measured RPM/torque unless calibrated telemetry is present. Pilot feel/lap times supplement measurements. |

For tuning, follow [FLIGHT-LOGGING](../FLIGHT-LOGGING.md) after DR-17 qualifies the adapter: immutable baseline, exact replay, one candidate using the same pilot-command tape, identities, markers, CSV and reports. A changed-solver candidate or recovered prefix cannot establish exact equivalence. Candidate testing of a closed-loop controller must retain feedback, not replay baseline actuator output open loop.

## 12. Planning decisions and unresolved inputs

| Existing ID | Updated disposition |
| --- | --- |
| D1 | Owner requested the 5-inch integration plan; shared-kernel vehicle scope is established. Runtime work remains pending. |
| D2 | Research comparison separate; product uses a sourced race assembly, not the lab fixture. |
| D3 | Simulator-owned 240 Hz controller initially; qualify before promotion, no firmware-equivalence claim. |
| D4 | Simple local rules first; published race compliance deferred. |
| D5 | Sibling strict multirotor format/shared quantity helpers. |
| D6 | Four logical channels and explicit arm/mode; Acro plus Angle training. |
| D7 | FPV default for this activity; pilot/chase available; listener policy with AUD/CAM. |
| D8 | Evidence selects motor/ESC/braking law; no assumed regeneration. |
| D9 | Data tracks; no editor. |
| D10 | Licensed download first; reproducible import adapter. |
| D11 | Rate-curve import; no silent PID/filter/powertrain import. |
| D12 | Night effects deferred. |
| D13 | Qualified HELI inflow consumer later; not a simple-model first-flight dependency. |
| D14 | Added latency off by default; measured presentation option later. |

DR-02 needs the exact assembly, downloadable parts, motor/prop/pack coverage and license audit. DR-16a needs a reviewed generic transaction design. Selected-build physical validation needs hardware/measurements and stays open if unavailable. The owner's quad, firmware dump, radio and goggles would improve DR-12/39/40 but do not block this plan or its initial engineering work.

## 13. Principal risks

| Risk | Containment / stop condition |
| --- | --- |
| Hidden controller state breaks replay | Resolve feedback/rollback first; injected faults before integration. |
| Fixture mistaken for real hardware | Separate identities and reject prop overlap/mixed-source claims. |
| Rotor coupling/braking creates energy | Momentum/work and one-bus accounting before product use. |
| 240 Hz misses control/contact dynamics | Separate plant/control refinement; qualify generic policy/scheduler if needed. |
| Complex inflow lacks predictive benefit | Separate law and held-out benefit before activation. |
| Download mistaken for permission/completeness | Per-file provenance/license/geometry checks; no unlicensed bundled fallback. |
| Breadth delays requested FPV quad | Independently deliver M2; race/polish/physical promotion retain separate gates. |

## 14. First implementation task

The original DR-02 + DR-16a foundation sequence has delivered the software slice recorded in §15. The current first implementation task is **DR-14 controller authority**, beginning with A01's managed profile refusal and A02's binding ownership, followed by A03's pause contract. Use [§16](#16-audit-remediation-programme-2026-11-16) for current dependencies and desired-behavior tests; do not restart the already delivered renderer, kernel or activity work.

## 15. Implementation status (2026-11-11)

Software evidence, test names and limits: [M0–M3 slice](../research/drone-racing/M1-M3-2026-11-11/README.md). Decisions: [kernel protocol](../DECISIONS.md#closed-loop-control-samples-the-accepted-frame-through-an-opt-in-protocol), [quad law](../DECISIONS.md#the-first-quad-law-is-transparent-and-its-continuations-are-declared), [race state](../DECISIONS.md#race-state-commits-with-the-physics-tick).

Independent implementation audit: [2026-11-16 findings and reproducible evidence](../research/drone-racing/audit-2026-11-16/README.md), pinned to `cfb5acd5`: 18 initial findings plus A19 from the follow-up, for 19 prioritized findings across controller authority, lifecycle, physics boundaries, race validity, persistence and presentation. The 25 selected existing suites pass 1,120 checks; targeted diagnostic probes expose additional gaps. Audit evidence does not close native-controller, performance or physical-validation gates.

| IDs | State | Note |
| --- | --- | --- |
| DR-03, 16a | Done in software | Reference oracles reproduced; opt-in `framed-sampled-v1` kernel protocol with legacy parity evidence. |
| DR-06, 07, 08, 09a | Done in software | Coupled shaft/body solve, Acro/Angle controller with bounded allocation and feed-forward, Actual and Betaflight rate curves (4.5.2 pin), 240 Hz qualified against 960/1920 Hz. |
| DR-10, 11, 12, 13 | Done for one build | Strict `openrc-multirotor v1` loader and generator; one product candidate `openrc-fpv5-f50-2150-f5146-6s-x1`, every value manufacturer-reported, derived, borrowed or estimated. No research-aircraft reproduction (DR-11 exact profile) yet. |
| DR-05, 09b, 18, 19, 20 | Done with declared simplifications | Four motors on one bus (one-quadrant and damped variants), pad contact with substeps, endpoint-resolution crash, strike, obstacle and depletion events. Located sub-tick cut and rotor-stop events are open. |
| DR-14, 15 | Partly done | Pre-expo input adapter, arm and mode actions, throttle policies and limit. Real radio and gamepad acceptance, the recovery proposal flow and a rates/settings UI are open. |
| DR-16b, 17 | Done in software | Dedicated session; full-envelope checkpoint; `.orfl` recording with exact and candidate replay from the pilot tape, also for race sessions. |
| DR-21, 22 | Partly done | Step-response tune by software sweep; whole-step cost measured on one PC (above the 500 µs p95 budget); the pad cost cut from 3.7 to 1.27 ms resting or at armed idle, and the armed-idle yaw-loop flip removed (R1/R2, 2026-11-12). Endurance runs and target-host qualification are open. |
| DR-29, 30, 31, 35, 36a, 37 | Software complete; native visual review | Owner-supplied [ION R5](../../research/drone-racing/DR-29/ION_R5.md) is the default visual (2026-11-14): complete frame, achieved-RPM rotor assemblies and onboard lens mount; Home, FPV and chase reviewed natively at 1920×1080, with 115 focused checks passing. Existing OSD, Home/direct routes, crash and restart flow retained. No 4:3 mode; native pacing, latency and physical qualification remain open. The earlier OpenRacer intake remains a separate asset. |
| DR-31b | Done in software | Betaflight/INAV-style OSD (`osd_model.gd`, `osd_painter.gd`): heading tape, scrolling speed/height sidebars with vario, camera-referenced pitch ladder, pack gauge with charge, home arrow and distance (home = arm point), attitude, motor outputs, stick overlay, blinking pack warnings and post-flight statistics. Layouts Off/Race/Freestyle/Full (O or pause menu) and metric/imperial units, saved only on the interactive route. Readability reviewed in 1080p captures only; no pilot review. |
| DR-31c | Done in software | Firmware conventions from Betaflight 2026.6.2 and INAV 9.1.0 sources ([research](../../research/drone-racing/DR-31c/README.md)): one-slot priority warnings with 2 Hz blink and HD severity colours, ACRO/ANGL, timer/altitude/G alarms, G-force, ON timer, remaining time, live efficiency, motor RPM, up/down reference, craft name, next-gate marker and edge arrow, Betaflight-style statistics. A pause-menu OSD settings panel adds a Custom layout with one check per element, HD/analog (white, 12 Hz) style and four crosshairs. The edge arrow is unverified in a capture. |
| DR-23, 24, 25, 26, 32, 36b | Done in software | Upright-gate courses on the default field, atomic race state, chord-path gate scoring, results outbox and files, G starts or cancels. DR-32 (2026-11-12): league-style panel gates whose drawn panels are their collision boxes (0.18 m striped panels, 0.40 m top banner with the gate number, LED aperture edge, feet; built like league gates: a woven sleeve between a white PVC tube and an LED diffuser tube with single LEDs up close, corner connectors, eyelets, stitched seams, rimmed number plates, foot tubes with sandbags, fine detail faded by pixel footprint), next gate lime with chasing LEDs, a chevron, a light and a dotted path to it, the one after amber, gates flash white when scored, a start light bar on the checkered start/finish gate, red exit faces as a wrong-way cue, neon halos exposure-compensated for night, and a painted start pad ([course visual](../../app/vehicles/multirotor/race_course_visual.gd)). RC-TRACK (2026-11-12): both courses moved off the runway to a drone area north-east of the car circuit with their own pad; with the RC car circuit shown, the quad flies over its relief and dressing (replays exactly). Readability reviewed in 1080p day and night captures only; no pilot review. |
| DR-04, 38, 39, 40 | Open | Advanced rotor law, held-out comparison, pilot review, selected-build measurement. |
| DR-28 | Partly done | Second course, the Tower sprint (7 gates, 116.6 m gate to gate: low 5 x 1.3 m hurdle, a 4.6 m tower gate, high and low passes); T or the pause menu's Course button cycles the courses of the field on the pad. Published rule formats, dive/tilted gates, flags and a menu course picker are open. |
| DR-27, 33, 34, 41 | Deferred | Ghosts, rich audio, effects, capability expansion. |

The local records/medals implementation is now tracked as **DR-26a**, with its historical **DR-40 (records)** references retained in dated evidence and existing comments. **DR-40** in current planning means selected-build physical validation. This resolves ownership without rewriting historical work.

Next: the repair sequence below, required CI, a native 1080p session with a real radio/gamepad (DR-14 acceptance, frame pacing, latency), the kernel guard share of the tick, and DR-40 selected-build measurements. Earlier timing figures remain dated evidence rather than a measurement of this audit environment.

## 16. Audit remediation programme (2026-11-16)

**Status: battery/power implementation on `fix/fpv-battery-power-2026-11-16`; remaining packets planned.** The original audit branch remains a dated baseline. The [battery/power record](../research/drone-racing/power-2026-11-16/README.md) owns the A06/A08 repairs and battery/negative-drag subset of A09; full A09 parity remains open. The [baseline audit](../research/drone-racing/audit-2026-11-16/README.md) records 18 initial findings plus A19 from the follow-up (19 total); the [follow-up investigation](../research/drone-racing/audit-2026-11-16/follow-up.md) supplies stronger scene/session witnesses, negative search results, alternatives and pinned engine-source analysis. The [2026-11-17 lifecycle audit](../research/drone-racing/lifecycle-2026-11-17/README.md) adds seven reproduced defects, strengthens existing A05, and identifies two decision/disclosure gaps on this same branch. Its L02 is an A05 witness, not an eighth new finding. Those documents own dated evidence; this section is the authoritative remaining-work plan. Implementation must reference the owning DR step and applicable A/L finding, with proof in its commit.

For the original 2026-11-16 comparison, main head was `6dfe1b9179af408f6b765b91ca164e626570db9f`, with the relevant FPV/input/session/race source unchanged from `cfb5acd5`. The lifecycle audit instead uses production commit `7f6719137115a6da5a3b355cf6232a2f1de0661f`, including the subsequent battery work. Recheck drift before implementation. Preserve baseline recordings and configuration identities before intentional physics changes. Documentation and observation probes do not promote M2/M3 qualification.

### 16.1 Decisions and rejected shortcuts

| Area | Selected planning direction | Alternative and tradeoff |
| --- | --- | --- |
| Managed profile refusal | Fix the quad boundary first: unresolved selected device remains connected but unready; only an explicit service-resolved default is usable. Reuse the airship refusal pattern. | A typed shared resolution API offers better diagnostics but needs all consumers and transactional rollback reviewed; it is not required for the initial fix. No silent keyboard/default substitution. |
| Binding ownership | Resolve configured AUX, actually active actions and inherited LB/RB/Start shortcuts together; derive help from the effective result. Preserve separate flight/UI roles. | Migrating all quad shortcuts into shared semantic actions is a larger follow-up. Counting inactive fixed-wing LB throttle-cut as quad ownership would break the default arm control. |
| Pause | Implement an explicit ordinary-hold continuity contract for an unchanged verified source/mapping/arm intent, with atomic pause entry and a recheck before the first resumed tick. Any observed OFF or continuity loss enters disclosed recovery. | A disclosed pad restart is acceptable temporary containment but does not close ordinary powered resume. Waiting for fresh AUX while paused deadlocks; retaining stale ON indefinitely can hide an actual OFF. A new pilot-frame validity field requires a versioned protocol change. |
| Results | Stable publication ID and canonical payload outside pure physics; retry and graceful-exit/restore guards; authoritative attempt files and an idempotent recoverable book projection. | A durable queue follows only with an explicit verified acknowledgement boundary, startup recovery and rewind policy. It cannot persist an unavailable first write; graceful-exit safety must not be labeled process-crash durability. |
| Mutable saves | Reuse validated previous-copy or alternating-generation recovery, with readback, ownership and failure seams. Preserve unknown/future versions. | Native atomic replacement may be preferable once qualified per OS. Removing the application's unlink alone leaves the pinned Windows engine's own delete-before-move failure window. `flush` is not a power-loss guarantee. |
| Pack energy | Implemented experimental one-RC pack and explicitly named `damped_nonregenerative` policy; regenerate source data, preserve mean brake torque and account surplus as effective motor-path loss. Strict upper charge/energy restore domains and versioned layout. | Pure coasting fails the retained early-chop authority gate. Bounded regeneration needs identified acceptance/overvoltage/event rules; a charge clamp or clipped current does not conserve energy. |
| Hover admission | Solve loaded shared-pack equilibrium with duty, shaft-speed, voltage and residual checks; retain independent power bounds as negative oracles. | An OCV-only or maximum-power-only guard cannot prove actuator feasibility. A frozen-SOC operating point does not prove sustained or real-FC hover; charge still decreases under load. |
| Contact and scoring | Bounded full-terrain disc intersection; separately adopt a versioned conservative rule suppressing crossings in a tick with unresolved physical terminal time. | A plane formula is an exact fixture, not a curved-terrain certificate. A certified event locator can later reduce false-invalid finishes; endpoint timestamps cannot do so. |
| Quad menu lifecycle | A small explicit adapter to shared UI/input/departure ownership, with one Resume eligibility decision, named blocking holds and keyboard release masking. | A full scene/menu-framework rewrite is unnecessary for initial closure. Blanket shortcut suppression would erase intentional R/G quick retry; resetting virtual throttle on every pause would break powered continuity. |
| Restart/reconfiguration | Prepare the candidate and old-attempt transition before committing either. Refusal preserves the old accepted flight, scene counters, recording and pending output. | Closing the stream or publishing an abort first cannot be undone by restoring labels. A temporary honest refusal is safer than a partially applied reset, but does not replace the successful transition contract. |
| Incomplete streamed recordings | Retain a visible failure/path/prefix status across automatic stop and later recordings; acknowledge incomplete evidence explicitly. | Generic manual-trace Retry is not interchangeable with an already-closed streaming writer. Do not promise to recover bytes no longer retained. |

The battery/power choice above is implemented in the linked branch; other rows remain implementation choices, not claims that their patches exist. Record final architectural decisions in DECISIONS when the reviewed implementation settles their exact contracts. Do not silently alter historical local-practice scoring, document semantics or checkpoint compatibility.

### 16.2 Reviewable work packets and dependencies

| Order / owner | Findings and concrete work | Required closure evidence |
| --- | --- | --- |
| 1 — DR-14 | **A01, A02, A18, A19:** preserve managed refusal; enforce one effective binding owner, including switch-group members and Start; reconcile connection-generation evidence before flight; render current help/availability. | Real-scene unsupported/corrupt/ambiguous store cases fail closed; healthy explicit defaults still fly; default LB/RB work; cross-assigned AUX never acquires a second authority; selected/foreign and held/released controls behave correctly; duplicate arrival/removal never silently disarms an uninterrupted pad or leaves a stale verifier. True replacement/reconnect cannot retain old authority. Update fixtures that previously depended on empty managed profiles becoming defaults. |
| 2 — DR-14/16/17, UI-21/31 coordination | **A03, L01, L07; L03 eligibility core:** ordinary-hold epoch versus recovery; keyboard release boundary; explicit quad exit-hold adapter; one Resume decision before adding new input routes. Track device identity/connection evidence, mapping and valid arm intent; do not queue edges during a hold. | The real activity retains powered continuity only in its qualified unchanged-source case. Held keyboard W/arrows require release without zeroing frozen virtual throttle. Ground-depleted/crashed Resume stays refused, while depleted-air remains eligible for the unpowered aftermath. OFF, OFF→ON, focus loss, disconnect, generation/profile changes and invalid samples cannot reuse stale authority or synthesize OFF evidence. A failed statistics-save quit decision freezes ticks/tape and activity actions across dialog gaps; repeated quit preserves one decision. Stay respects both previously running and previously paused state under the recovery policy. |
| 3 — DR-16/14 | **A04, A05 (L02):** shared controller and selected UI-device initialization for Home and direct entry; honor live role changes and consume semantic Back/Pause. Depends on packet 1's refusal policy and packet 2's terminal eligibility core. | Same V2 mapping, inversion, limits and AUX on both routes; explicit keyboard and unconfigured radio remain meaningful. Selected UI pad/radio opens/navigates/accepts/backs out, including a UI device distinct from the flight device. OSD Back returns to its opener; outer-menu Back uses the common Resume guard and cannot add a ground-depletion bypass. Foreign devices have no authority. Radio center/OFF and native visible UI acceptance follow synthetic viewport checks. |
| 4 — DR-26/26a/17 | **A11, A12; G01 decision:** stable publication UUID, immutable payload, no-clobber ownership, explicit retry and all graceful-departure/restore guards. Specify active-attempt abandonment, replay and live-branch publication semantics before schema edits. Coordinate L05/L06. | Eight failed writes recover without another race; retries keep ID/payload and do not double-fold the book; two sessions/processes, repeated wall time and collision never overwrite another payload; ID-generation failure retains the terminal payload until it acquires one stable ID; Home/quit/reconfiguration/restore cannot silently lose the last pending copy. Compare committed Home/quit after a valid completed lap against G/reset; canceled departure retains the active attempt. Offer stay/retry/informed discard with a pending count. Deterministic verification replay does not publish. |
| 5 — DR-26a/26 | **A13, A16:** recoverable replacement, closed bounded book validation, legacy preservation/migration and idempotent projection reconciliation. Coordinate with packet 4's result schema. | Fault injection at stage/readback/publish/book/acknowledgement/rollback boundaries retains a valid accepted state; result-saved/book-failed and interrupted acknowledgement reconcile once. Empty/partial/future/malformed books never reach unsafe field access or get overwritten silently. Qualify native OS semantics separately. |
| 6 — DR-10/16/17 | **A09:** reusable normalized physical invariants for raw/prepared/candidate admission; recompute or validate consumed derived values. | Negative drag and invalid mass/inertia/rotor/pack/contact/command data reject transactionally; valid stock and lab fixtures remain supported. Raw-only provenance stays strict. Candidate refusal preserves frame, tape, recorder, environment and identity. |
| 7 — DR-18/05/21 | **A08:** loaded hover feasibility; **A06:** coherent pack/ESC candidate and charge-domain enforcement. Depends on packet 6's common admission boundary. | Independent impossibility and duty-limit fixtures, zero resistance, discriminant boundaries, chosen voltage branch, low/full SOC and actual bus residuals. Full/near-full chop, mixed motor flows, energy closure and refinement; full baseline exact replay then candidate FC/maneuver comparison. No physical ESC claim from software alone. |
| 8 — DR-19/24/09b | **A07:** full-disc endpoint geometry and valid conservative bounds for composed terrain; review unsafe early-outs and memo approximation. | Analytic plane oracle, tilted discs, interior crest, shipped RC ramps/shoulders, custom narrow ramps, memo boundaries, stopped props/hull, grazing/clear/penetrating states and bounded-budget refusal. Observed hit, proven clearance and unresolved state remain distinct. Endpoint repair does not claim swept impact time. |
| 9 — DR-25/23/24/20/26, DR-16/17 coordination | **A10, A14, A15, L05:** conservative same-tick scoring; capture original reset tick/reason; stage candidate reconfiguration and scene cleanup; hash resolved collision geometry and version rules/course identity. Can proceed alongside physics after publication/identity policy is fixed. | Composed RK4/session/wrapper test for earlier/tied/later or unresolved crash and depletion; unaffected clean race/replay; nonzero reset tick and failed-reset no-publication. Candidate refusal in IDLE/COUNTDOWN/RACING preserves frame, tick/tape, course/identity, counters, recorder and pending output. Successful replacement commits once, including observer reentrancy cases. Real admitted terrain change separates identities; preserve historical records. |
| 10 — DR-31/37, DR-16/20 coordination | **A17, L03, L04, L08:** visible OSD-save failure; one terminal Resume policy; current-attempt result presentation; terminal explanation survives early focus loss. Integrate A18 help with packet 1. | Failed save remains visible/retryable; successful reload agrees. Ground depletion stays held through button/P/Escape/Start/Back, while air depletion can continue an unpowered fall. Crash Resume stays refused. Reset/course change to IDLE removes the previous outcome only after commit. Early and late crash-focus paths retain the cause and recovery action. Targeted OSD/activity tests and native EN/ES 1080p readability. |
| 11 — DR-17, UI-31 coordination | **L06:** explicit incomplete-stream status and acknowledgement across flight, automatic stop, reset, Home, quit and the next F10 recording. Coordinate packet 4 without assuming the manual-trace retry protocol fits `.orfl`. | Inject in-flight chunk, final-buffer and footer failures; retain any verified prefix/path and distinguish incomplete from complete. An automatic failure remains visible, and a later REC notice cannot silently replace its only owner. Healthy finalization/reload remains valid. Retry is offered only for retained recoverable evidence; native storage qualification is separate. |

Packets 1–3 are the first control-authority integration sequence. The persistence and physics streams can then proceed independently, with serialized edits to shared session, identity and scene contracts. Do not combine every finding into one production patch. Scope the durable queue as a follow-on to packets 4–5 if process-loss recovery is required; closing the minimum graceful-recovery defect must explicitly state its narrower guarantee.

### 16.3 Contracts that must be settled before implementation

**Publication versus rewind.** A pending external result must have an owner outside arbitrary physics rewind. An interim implementation may refuse restores that would lose or ambiguously revive pending output. A stronger design separates the publication queue from the versioned simulation envelope. Do not union old dictionaries blindly, regenerate IDs on retry, or evict a deduplication ledger while still promising permanent exactly-once projection. Preserve a legacy aggregate baseline and bound any reconstruction scan/index; old files do not necessarily contain all medal/attempt-count facts needed for perfect migration. Specify concurrent writer, stale-lock and conflict recovery.

**Restart commit.** Stage target preparation and the old-attempt transition before closing a recorder or clearing accepted state. Candidate refusal is observationally non-destructive apart from an honest held error state. Reserve required result ownership/capacity before commit; capture original terminal metadata once. Define reentrant reset observers and commit-time failure. Do not promise rollback of a stream that has already been closed or of a result that has already become externally visible.

**Active-attempt departure.** G01 is a policy gap, separate from A11's already-pending results. The proposed direction is to abandon a race only when departure commits, using the last accepted tick and preserving valid completed laps without counting a completed attempt. Stay retains the attempt. Settle how a later guard refusal interacts with an already-published abandonment; physics mutation, file publication and book projection need explicit boundaries and idempotence. The audit compares terminal projections but did not execute a completed-lap Home case.

**Resume and nested ownership.** Use one eligibility result for menu buttons and semantic/physical shortcuts. Keyboard release masking must preserve accepted same-source virtual throttle. Radio positional and arm-switch continuity require their own evidence. Intentional R/G quick retry remains available through its guarded transition; a nested settings or exit surface owns input until it closes. A quad exit guard must freeze accepted ticks even if the native window manager does not emit focus loss.

**Keyboard-mask boundary cases.** Define how an already-deflected filtered keyboard stick is held or neutralized; masking only a raw target can leave its rate-limited output nonzero. If release is a per-key contract, opposed held keys such as W+S cannot count as released merely because their net axis is zero. Test releasing one of the opposed keys and then both. Keep the separate virtual-throttle accumulator continuous. These are design/acceptance risks, not additional reproduced findings in this audit.

**Terrain authority.** The current contact law linearizes samples in 0.1 mm cells. Its small microrelief error estimate is not a bound for every admitted custom RC ramp, whose widths can approach zero. Choose exact collision geometry, a certified bound for the approximation, or explicit refusal of unsupported terrain. Existing rotorcraft disc search and RC upper-bound helpers are reuse candidates, not drop-in proof that the composed quad surface is covered.

**Model and record identity.** Intentional pack/contact/scoring changes need explicit model/session/collision/rules versions and old-record handling. A flight log's solver hash alone does not reject a session checkpoint whose own identity still matches. Keep file-byte provenance, normalized candidate identity, exact replay and changed-solver/candidate comparison distinct. Never rewrite a baseline golden merely to hide a behavioral change.

**Evidence strength.** Current stronger A03 uses the real scene with a synthetic radio and research air start; A07 is a constructed endpoint on the shipped ramp; A10 is a real wrapped tick from an initialized final-lap checkpoint. Fifteen normal pad-start trials show regeneration but no over-capacity. Keep those limits in repair reports. Generation/ambiguity changes need both positive continuity controls and genuine replacement/reconnect recovery; equal numeric device IDs do not alone prove equal authority.

### 16.4 Verification and completion gates

For each packet, first turn its baseline observation into a desired-behavior regression that fails before the fix. Parse changed GDScript and run affected existing suites through the checked runner; retain complete outcomes and exact identities, excluding workspace metadata from publication. Use the repository test pool when configured. Broaden tests only for affected shared consumers or a required gate.

- **Controls/routes:** controller service/profile/AUX/setup, quad input/activity and affected fixed-wing/heli/airship consumers; explicit keyboard and default-pad positive controls; physical radio/gamepad follow-up.
- **Lifecycle sequences:** held W/arrows → Pause → Resume → release/repress, including pre-deflected filtered sticks and opposed held keys; OSD Back → pause opener → guarded Resume; crash/depletion → focus/Pause → restart; result → reset/course → IDLE; injected candidate refusal in IDLE/COUNTDOWN/RACING; running and paused quad → failed quit-save decision → Retry/Stay. Assert accepted frame/tape bytes, tick, motor state, course/identity, recorder cursor, visible surface and focus together; the audit's refusal control checks the narrower tick/tape-length/recording-flag subset.
- **Persistence/race:** race session/director/model/records and activity, isolated storage fault seams, concurrency, migration and checkpoint/replay cases; native Linux/macOS/Windows for platform promises.
- **Recording/departure:** chunk/final-buffer/footer errors across reset/Home/quit/F10; incomplete-prefix readability and visible failure ownership; active race with completed lap → departure commit/cancel/retry, including a later guard failure. Do not infer recoverable bytes or terminal-record policy from generic trace tests.
- **Physics:** data, electric bus, controlled plant, session/flight log and applicable rotor-disc/RC-track suites; independent analytic/energy oracles and a preserved complete baseline before any candidate comparison.
- **Product gates:** required repository CI, native **1920×1080 first**, actual selected controllers, frame pacing and input latency, DR-22 endurance and pad cycles. Higher resolution follows 1080p; 720p is fallback evidence.
- **Physical gate:** DR-40 selected-build mass/CG/inertia, thrust/torque/RPM/current, ESC/braking and pack response, independent held-out motion and uncertainty. Estimated coefficients and passing software checks do not close it.

Track each finding as **open → implemented with software evidence → applicable native/hardware acceptance complete**, linking the repair commit and retained evidence. Do not mark all 19 closed because diagnostic probes pass, or describe the baseline 1,120 checks as tests of an unimplemented repair.


### 16.5 Battery and power implementation checkpoint

**A06 and A08 addressed; A09 partially addressed (DR-05/10/16/17/18/21).** The [implementation record](../research/drone-racing/power-2026-11-16/README.md)
contains the one-RC equations and estimated provenance, coherent non-regenerative brake allocation, loaded-hover and
fixed-tick RC admission, strict charge/energy restore checks, baseline/candidate recordings and targeted verification.
The original full-charge air-start overcharge route is covered. Existing chop authority and sample-rate gates remain;
the full three-lap race and new nine-state mid-flight recordings replay exactly under the changed model.

A09 still needs complete raw/prepared geometry, inertia, contacts and command parity, including rotor ID/spin-count
invariants. A07 contact/event work, controls and persistence packets remain open. The battery `consumed_mah` initial-SOC
reference issue is also outside this change. Thermal/aging/cell-imbalance models, identified ESC charge acceptance and
physical pack characterization remain qualification work, not hidden claims of the new estimated model.

### 16.6 Menu and lifecycle audit checkpoint (2026-11-17)

**Audit complete; remedies planned.** The [lifecycle record](../research/drone-racing/lifecycle-2026-11-17/README.md)
contains seven additional reproduced defects (L01/L03–L08), stronger A05 witnesses (L02), and G01/G02 decision or
disclosure gaps. Three new defects require deliberately injected validation/storage failures; their frequency in
ordinary use is not established. No production source changed in this checkpoint.

The new probes cover the real scene, accepted race ticks and the real AppRoot/statistics decision. They preserve
successful continuity and terminal controls, and record that the exclusive dialog blocked the sampled C shortcut
even while the quad continued advancing. Synthetic events and a headless 1080p layout do not qualify physical
controllers, native focus/readability, frame pacing or latency. Exact results and limitations live in the linked
record and its portable verification file.

For this menu-focused stream, execute packet 1's authority prerequisites, then packets 2–3 (L01/L02/L07), the
transaction/publication/recording work in packets 9/4/11 (L05/L06/G01), and packet 10's terminal presentation
(L03 presentation/L04/L08); L03's shared eligibility core precedes the new Back route in packets 2–3. These are bounded implementation packets, not one broad refactor. G02's visible calm-wind disclosure
can be scoped separately; passing the existing activity/race/menu suites does not close these newly reproduced gaps.
