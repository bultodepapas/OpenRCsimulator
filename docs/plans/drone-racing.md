# 5-inch FPV racing drone: simulation integration plan

**Revised:** 2026-10-21. **Status:** plan; no playable drone is implemented. DR-00/01 and the DR-04a…06a laboratory foundation exist. The remaining gates below are open. This revision answers the owner's request for a 5-inch racing-style FPV drone and replaces the older integration proposal in this file. It changes no runtime behavior.

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
| DR-37 | Crash labels/presentation and restart UX | Cause/rearm clarity; M2 open, elaborate wrecks deferred. |

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

Start **DR-02 + DR-16a**: freeze the sourced build/asset manifest; specify sampled-feedback, stage access and rollback, then demonstrate the current gap in an isolated failing test. Next implement the smallest headless Acro/session/replay slice. Do not begin with a new renderer, procedural drone, global timestep change or fixed-wing FlightSession rewrite.
