# Drone racing plan: FPV racing quadcopters and a race mode

**Date:** 2026-10-13. **Status:** in review; the shared foundation is active. The standalone HELI-04 inflow code is not session-ready while its source-law gate is open. DR-00 registration and scope are complete; multirotor/racing implementation remains proposed. Reference-aircraft, controller and racing product recommendations in D1–D14 (§12) remain provisional. DR-01 (research record) is done.
**Prefix:** DR-00…DR-41, registered in the [track registry](../README.md#tracks-plans-and-step-ids). `DR-` was free on 2026-10-13 (checked against `docs/`, `app/`, `research/`).
**Owner:** drone-racing track (proposed), under the main line's acceptance.
**Owns (proposed):**
- `app/physics/multirotor/` and `app/physics/multirotor_data.gd`
- `app/data/aircraft/<quad-id>.json` (generated) and `app/data/schema/openrc-multirotor-v1.*`
- `app/data/tracks/` and `app/data/schema/openrc-track-v1.*`
- `app/sim/race/`
- `app/aircraft/<quad>_*.gd` and `assets/aircraft/<quad-id>/`
- `app/render/track/`
- `app/tests/test_mr_*.gd`, `app/tests/test_race_*.gd`, `app/tests/bench_multirotor.gd`
- `research/drone-racing/` and `docs/research/drone-racing/`

**Coordinated, not owned:**

| Owner | Files |
| --- | --- |
| Main line | `app/sim/simulation.gd`, `app/sim/flight_session.gd`, `app/sim/trace.gd`, `app/main.gd`, `app/tests/replay_policy.gd`, golden flights, `app/input/` |
| Ground track | `app/physics/ground_contact.gd`, `app/physics/ground_start.gd` |
| Electric propulsion (EL) | `app/physics/electric_motor.gd`, `electric_supply.gd`, `electric_battery_step.gd`, `electric_stop.gd` (reused; an ESC kind is added with the EL owner) |
| Helicopter track (HELI-04 shared-kernel owner) | Owns the first shared inflow kernel at `app/physics/rotorcraft/inflow.gd`; multirotor consumes it only after its source-law, interface and reference-test gates pass. Skid/leg contact and rotor-disc clearance remain separately coordinated seams. |
| Catalog / menu track | `app/app_state/aircraft_catalog.gd`, `app/ui/`, `app/app_state/preferences.gd`, `app/i18n/es.po` |
| Camera-views track | `app/render/pilot_camera.gd` today; `app/render/camera/` after CAM-02; FPV mount capability (CAM-13) |
| Flight-overlays track | `app/render/overlays/` (an OSD overlay is added there) |
| Scenery / landscape | `app/scenery/collision_world.gd`, `collision_setup.gd` (track proxies), `app/data/fields/default.json` (start pad), `app/render/near_grass.*` |
| Visual-quality track | `app/render/propeller_blur.gd` (N-rotor extension) |
| Audio track | `app/audio/` |
| Crash track | `app/render/crash/`, CR-01d hull labels |
| Aircraft standardization | [AIRCRAFT_CONTRACT](../../AIRCRAFT_CONTRACT.md) |

**Evidence:** [DR-01 research record](../research/drone-racing/DR-01/README.md) holds the sources, parameter tables, derived numbers and the seam map with line references.

**Goal.** Fly one 5-inch FPV racing quadcopter whose physics comes from published, identified data, through a flight controller that behaves like the one real pilots fly, and race it through gates on the existing field with real timing rules. Hover, punch-outs, prop-wash on descents, ground effect, battery sag, motor saturation and the loss of authority at full throttle must emerge from the equations. The rates and expo a pilot flies must import unchanged. Present it so that:

- the FPV view has the camera tilt, field of view and OSD a pilot expects
- four props read as translucent discs that never strobe
- the sound follows four motors, with Doppler at 40 m/s
- a lap time means the same thing it means at a MultiGP race

The airplanes must not change: every existing golden flight, trace and capture stays byte-identical.

## 1. Why this is a scope decision

[DECISIONS](../../DECISIONS.md) opens with "Build an RC airplane simulator". The [data-pipeline investigation](../research/roadmap-investigations/09-aircraft-data-pipeline.md) placed helicopters and multirotors out of scope and reserved a `vehicle` key. The [helicopter plan](helicopter.md) proposes the second vehicle class and lists multirotors as a non-goal.

A racing quad is a third vehicle class **and** the project's first game mode:

- different controls: four sticks drive a flight controller, not surfaces; arm and mode switches
- a different power chain: four motors on one pack, with regenerative braking and a 2–15 ms motor lag
- onboard electronics that **define** the handling (rate loop, mixer, air mode, angle mode)
- a different start (disarmed on a pad), contact (legs, props), and crash (prop strike, gate hit)
- a race layer: tracks, gate detection, timing, results and ghosts
- a different default view (FPV) for a project whose principle is flying from the ground

The owner must accept it explicitly (D1) and record a DECISIONS row. Until then this plan is research.

What makes it tractable now:

- The float64 RK4 core carries arbitrary continuous states, tick-held auxiliary state, discrete modes and gyroscopic rotor momentum ([helicopter plan](helicopter.md) F1–F3).
- The electric propulsion kernels (three-constant motor, OCV/resistance pack with SOC, stop and exhaustion events) exist and are replayable ([electric plan](../ELECTRIC-PROPULSION-PLAN.md)).
- The scenery collision world already sweeps the hull against boxes and capsules with response classes ([LU-05](../research/landscape-upgrade/LU-05/collision-report.md)), which is what gates need.
- The camera plan already designs the onboard/FPV view, mounts and lens warp (CAM-11…13) and its rig (CAM-02) is in the tree; the overlays plan has the layer an OSD goes in.
- A quad has no flapping, swashplate, governor or tail rotor, so it can later exercise the shared rotorcraft kernel with a simpler airframe. The helicopter track lands that kernel first (D13); this plan remains a proposed third vehicle class.

## 2. What exists today (2026-10-13)

Line references are recorded in [DR-01 §13](../research/drone-racing/DR-01/README.md#13-code-seams-on-2026-10-13); verify them before editing. The tree moved while this plan was written (CAM-02 camera rig, SM-03/04 smoke auxiliary input, CR-01d hull labels and the Timber runway qualification landed); the references below were re-checked against the working tree on 2026-10-13 after those changes.

| # | Finding | Where | Consequence |
| --- | --- | --- | --- |
| F1 | **The rigid body and integrator are vehicle-neutral.** 13 body states; `RB.derivative` takes a summed rotor momentum `h`; RK4 is generic over array length. | [rigid_body.gd:13-20](../../app/physics/rigid_body.gd#L13), [integrator.gd:30](../../app/physics/integrator.gd#L30) | No core rewrite. |
| F2 | **Three tiers of extra state** exist: `aux` sampled once per tick and held through the stages, `modes` discrete, `continuous` integrated in RK4 with a joint `{loads, derivative, rotor_momentum}` callback. | [simulation.gd:151-275](../../app/sim/simulation.gd#L151) | Motor speeds and pack charge go in `continuous`; the flight controller, ESC commands and filters in `aux`; arming, flight mode and race state in `modes`. |
| F3 | **The coupled shaft rpm is a complete template for a new continuous state** (layout, derivative, aux mirror, reset, checkpoint, restore whitelist, trace metadata, replay class). | [flight_session.gd](../../app/sim/flight_session.gd) `_settled_continuous`, `_coupled_response`, `checkpoint`, `restore_checkpoint`, `trace_meta`; [replay_policy.gd](../../app/tests/replay_policy.gd) | Follow the same nine touch points, four times over (DR-17). |
| F4 | **Inputs are four channels end to end** (`inputs` hard-sized to 4; trace `cmd_*`; golden rows; calibration). Radios expose 10 axes; `RcInput` reads one optional auxiliary binding (axis or button) for the smoke pump (SM-03/04, `smoke_aux.gd`) and no flight switches. | [simulation.gd:24](../../app/sim/simulation.gd#L24), [rc_input.gd:15-33](../../app/input/rc_input.gd#L15), [rc_input.gd:139-162](../../app/input/rc_input.gd#L139) | Keep four sticks as the flight controller's setpoints; arm and mode switches become `modes` fed by a named-switch mapping that generalizes the smoke binding (shared with HELI-14). |
| F5 | **Force assembly is single-rotor.** `Dynamics._components_from_air` sums `Aero.loads` (wing and tails required) plus one `Propulsion.loads` at one offset and axis; `rotor_momentum` is one vector. `RotorCoupling.response` solves one axis and one inertia. | [dynamics.gd:18-97](../../app/physics/dynamics.gd#L18), [propulsion.gd:519-538](../../app/physics/propulsion.gd#L519), [rotor_coupling.gd:13](../../app/physics/rotor_coupling.gd#L13) | One multirotor evaluate callback beside the airplane paths; N parallel rotors in the coupling. |
| F6 | **The electric motor is one-quadrant.** `I = max(0, (d·V − E)/Rm)`, no regeneration or braking; the ESC is `ideal_motoring` with identity mapping; the pack closed form solves **one** motor. | [electric_motor.gd:27-50](../../app/physics/electric_motor.gd#L27), [electric_supply.gd:88-93](../../app/physics/electric_supply.gd#L88) | Add a `synchronous` ESC kind (bidirectional current) and a shared-bus solve for N motors (DR-05, D8). |
| F7 | **The explicit-step envelope is `dt·kt²/(Rm·J·carrier) ≤ 0.25`.** A 2306 2450 KV motor with a 5-inch tri-blade sits at 0.10–0.26 depending on `Rm` and `J` (7 × 10⁻⁶–1 × 10⁻⁵ kg·m², estimated) ([DR-01 derived checks](../research/drone-racing/DR-01/README.md#derived-checks)). | [flight_session.gd:16,79-99](../../app/sim/flight_session.gd#L79) | Measure the real `J` and `Rm`; qualify the ratio per configuration with refinement evidence before relaxing it (DR-09). |
| F8 | **The propeller law clamps reverse flow.** `coefficient()` returns the static value for `J ≤ 0`; there is no descent-through-wake, vortex-ring or in-plane force for electric props; `thrust_angles` are limited to ±10°, so a rotor axis along −z is impossible. | [propulsion.gd:30-46](../../app/physics/propulsion.gd#L30), [aircraft_data.gd:835,905](../../app/physics/aircraft_data.gd#L835) | DR-04 adds prop-specific blade and hub loads, using HELI-04's shared signed inflow and ground-effect kernel; the airplane propeller stays as the static-point oracle. |
| F9 | **The loader is airplane-only.** v2 requires a wing of 0.3–4 m, 32 stable-airplane derivatives, tails, `start.level_speed` 5–60 m/s and control throws. | [aircraft_data.gd:181-241](../../app/physics/aircraft_data.gd#L181), [aircraft_data.gd:1276](../../app/physics/aircraft_data.gd#L1276), [aircraft_contract.gd:139](../../app/physics/aircraft_contract.gd#L139) | A separate multirotor derive path reusing the quantity, inventory, inertia and identity kernels (D5). |
| F10 | **Trim is forward flight only**; hover is explicitly refused; session preparation refuses flight if trim fails; runway starts are limited to a qualified list (Stik and Timber since TT-11). | [trim.gd:60-63](../../app/physics/trim.gd#L60), [test_trim_integrity.gd:53](../../app/tests/test_trim_integrity.gd#L53), [flight_session.gd:236-241](../../app/sim/flight_session.gd#L236), [flight_session.gd:584-611](../../app/sim/flight_session.gd#L584) | A hover equilibrium (analytic) and a pad start on legs (DR-18). |
| F11 | **Contacts use a rolling-tyre law with anchors**; without a gear module every hull touch is terminal. | [ground_contact.gd:73,179](../../app/physics/ground_contact.gd#L73), [flight_session.gd:958](../../app/sim/flight_session.gd#L958) | Four leg contacts with the isotropic friction mode the helicopter also needs (DR-19). |
| F12 | **Crash is terminal on any hull point**; hull points carry CR-01d labels (`crash_hull_components`) in the working tree, with the wing-span region guess as the fallback; auto-restart after 1.5 s; no disarm concept. | [flight_session.gd:907-1026](../../app/sim/flight_session.gd#L907), [director.gd:150-166](../../app/render/crash/director.gd#L150), [aircraft_data.gd:1559](../../app/physics/aircraft_data.gd#L1559) | Prop-disc clearance, labelled hull points, fast pad or last-gate respawn (DR-19/20/37). |
| F13 | **Scenery collision exists; gate detection does not.** Proxies are heading-only boxes and vertical capsules with four response classes (`soft_foliage_impulse` 22 m/s, `frangible_impulse` 12, `light_airframe_impulse` 14, `hard_terminal`). | [collision_world.gd:475-520](../../app/scenery/collision_world.gd#L475), [scenery_collision.gd:19-21](../../app/sim/scenery_collision.gd#L19) | Gates as capsules/boxes with a race class; a separate CG plane-crossing detector in `post_step` (DR-24/25). |
| F14 | **Render, blur, audio and HUD read one rpm from `aux[0]`.** `main.gd` spins one `propeller`; VQ-05 attaches one disc; the soundscape has one motor voice; O5 shows one rpm. | [main.gd:529-531](../../app/main.gd#L529), [main.gd:1091-1094](../../app/main.gd#L1091), [propeller_blur.gd:58,458](../../app/render/propeller_blur.gd#L58), [soundscape.gd:49-60](../../app/audio/soundscape.gd#L49), [overlay_manager.gd:206](../../app/render/overlays/overlay_manager.gd#L206) | A published per-rotor telemetry accessor; four discs; four motor voices summed; OSD (DR-30/31/33). |
| F15 | **Camera: a rig exists, no onboard view yet.** The CAM-02 rig with pilot, chase, orbit and close-up views is in the working tree (`app/render/camera/`, uncommitted on this date); the onboard/FPV view (CAM-11), lens warp (CAM-12) and mounts (CAM-13) are designed, not implemented. | [camera-views.md §5.3](camera-views.md#53-onboard--fpv-v3), [camera_rig.gd:16](../../app/render/camera/camera_rig.gd#L16), [main.gd:1056-1057](../../app/main.gd#L1056) | The quad declares a mount; FPV is a new `fpv` view in the rig, built with the camera owner (DR-31). |
| F16 | **Performance.** Tick ≤ 500 µs (Gate P open). Stik 200–445 µs; electric Stik with battery 558–562 µs on the EL2a-P1 host; local strips 2.3–3.6 µs per element evaluation. | [H15](../research/simulation-state/H15/README.md), [EL2a-P1](../research/propulsion/EL2a-P1/README.md) | The quad has no wing strips: a closed-form four-rotor model should cost less than the Stik. Budget in §4.12; bench before integration (DR-09). |
| F17 | **The catalog supports a PREVIEW entry** with `data=""` that refuses Fly (Timber). | [aircraft_catalog.gd:20-64](../../app/app_state/aircraft_catalog.gd#L20) | Ship the visual quad as PREVIEW before its physics (DR-29). |
| F18 | **Particles and grass.** Only crash `CPUParticles3D`; no `GPUParticles3D`; near grass reacts to the global wind within 30 m of the pilot. | [effects.gd](../../app/render/crash/effects.gd), [near_grass.gd](../../app/render/near_grass.gd) | Prop wash reuses the helicopter's wash field (HELI-27) with one combined source; particles only after SM-00 (DR-34). |

## 3. Reference aircraft and data policy

**Recommendation (D2): the identified ETH/UZH research quadrotor of the Agilicious and NeuroBEM work as the first, validated configuration; a MultiGP-style 5-inch 4S racing build as the second, estimated configuration.** Rationale and the parameter table are in [DR-01 §1](../research/drone-racing/DR-01/README.md#1-identified-multirotor-models-and-data).

- The Agilicious platform is the only 5-inch class quad with a published, numerically complete and **flight-validated** parameter set: an Armattan Chameleon frame with Hobbywing XRotor 2306 2400 KV motors, 5.1-inch tri-blade props, a 4S 1800 mAh pack and 4 × 9.5 N continuous static thrust (manufacturer/measured); 752–870 g depending on the payload; inertia diag(0.0025, 0.0021, 0.0043) kg·m²; a motor time constant of 33–39 ms identified on a load cell; a measured 40 ms command-to-force latency under Betaflight; and the NeuroBEM dataset of 96 aggressive flights at 400 Hz with the four motor speeds, battery voltage and ground-truth forces and torques. The same platform family beat human champions in the Swift work (870 g, 35 N, Betaflight + BLHeli_32), so it is a racing airframe in all but the frame branding.
- Every retail racing build has retail geometry and static bench data only (thrust, current and rpm per throttle step at a fixed voltage; no torque). Its inertia, drag, motor lag and the forward-flight rotor behaviour would all be estimates.

Consequences to state honestly:

| Item | Fact | Policy |
| --- | --- | --- |
| Configuration | A research quad with onboard computer and camera: thrust-to-weight ≈ 4–4.5 against ≈ 9 for a race build | Fly the identified configuration first, named as such (D3). The race build re-estimates mass, inertia and drag and is labelled `estimated`, with its motor/prop static points `borrowed` from a named bench dataset. |
| Rotor law | The papers identify `T = c_t·ω²` and `Q = c_q·ω²` plus linear rotor drag | Those constants calibrate the blade-element + momentum law at the static point (§4.3); the law's forward-flight behaviour is **validated held-out** against the dataset's forces and torques (DR-38), never fitted to them. |
| Flight controller | The research FC is not Betaflight | The handling comes from the simulator's Betaflight-equivalent discrete controller (§4.7) with imported rates; its gains are simulator-owned equivalents, not a pilot's PID profile (D3). |
| Missing | Visual geometry of the actual airframe; ESC behaviour; propeller chord/pitch distribution | Procedural visual from published frame dimensions (DR-29); ESC kind and idle from documented defaults (`estimated`); prop geometry measured from a photographed sample or borrowed from a database, each labelled (DR-02). |

Identified values of the reference quad used by tests ([DR-01 §1](../research/drone-racing/DR-01/README.md#1-identified-multirotor-models-and-data)): mass 0.752 kg and inertia diag(0.0025, 0.0021, 0.0043) kg·m² (NeuroBEM configuration), motor lag 33–39 ms, static c_t ≈ 1.1 × 10⁻⁶ N·s²/rad² per rotor (derived from a bench point; c_q at this scale is unmeasured), rotor-drag coefficients d_x = 0.54 s⁻¹ and d_y = 0.39 s⁻¹ identified on a comparable 610 g quad, and the NeuroBEM force/torque error table that DR-38 is judged against.

Derived values for a typical 650 g, 5.1-inch tri-blade, 4S **race build** are listed in [DR-01 Derived checks](../research/drone-racing/DR-01/README.md#derived-checks) (all inputs estimated unless the record says otherwise):

- hover thrust 1.59 N per rotor, disc loading ≈ 121 N/m², hover induced velocity v_h ≈ 7.0 m/s
- hover ≈ 9,900 rpm at a static C_T of 0.17, full throttle ≈ 30,000 rpm, thrust-to-weight ≈ 9
- blade-passing 0.5–1.5 kHz, commutation 1.2–3.5 kHz (14-pole motor), tip Mach 0.2–0.6
- hover current ≈ 3.5 A per motor; full throttle ≈ 24 A per motor, ≈ 95 A on the pack, ≈ 1.1 V sag at 12 mΩ
- motor electromechanical time constant 16–28 ms; inflow time constant ≈ 2 ms
- 0.7–2.1 rotor revolutions per 240 Hz tick; 2.7–8.3 revolutions per 60 fps frame
- Johnson-model predicted VRS window ≈ 3–10 m/s at low forward speed for the estimated race build; this is an extrapolation to 5-inch props, not validated small-prop data
- frame drag ≈ 2.2 g at 44 m/s for a 0.012 m² drag area

## 4. Physics architecture

### 4.1 Fidelity choice

The model is the standard quadrotor rigid-body model of the control literature, grown toward the blade-element detail that racing speeds need ([DR-01 §1–2](../research/drone-racing/DR-01/README.md)):

- (a) **per-rotor blade-element thrust and torque** using the shared `rotorcraft/inflow.gd` momentum branches, Johnson VRS/windmill model, signed inflow derivative and ground-effect response (HELI-04); prop-specific blade loads stay in DR-04
- (b) **per-rotor in-plane H-force and hub moment** from the advancing/retreating blade asymmetry, which is what makes a quad pitch up and slow down when the sticks are released at speed
- (c) **four coupled motor-speed states** on one pack, with regenerative braking and an idle floor
- (d) **a discrete flight controller** at the tick rate, with the pilot's rates imported one to one

Accepted and rejected:

- **Design contract:** HELI-04 is the intended source of truth for rotorcraft inflow after its source-law gate passes. The standalone implementation matches the independent reference but still needs the verified Johnson Table 3 crossflow cutoffs C/M handled under dynamic-flow refinement before session use. Motor dt/τ = 0.15–0.26 (§2 F7). The estimated hover inflow time constant is ≈ 2 ms, so its treatment at a 4.17 ms tick needs an accuracy check: DR-03/04/09 compare the shared derivative with an algebraic steady solution under timestep refinement before choosing whether λ is integrated or treated quasi-statically. A time constant below one tick alone does not justify dropping the state; DR must not add a separate guessed smoother. Body–controller coupled modes are far below Nyquist (120 Hz).
- **Rejected: per-blade azimuth marching.** The rotor turns 250–750° per tick. Nothing in the body response needs blade azimuth.
- **Rejected for now: full BEMT tables from measured prop geometry.** They are the right upgrade when a measured chord/pitch distribution and Re ≈ 10⁵ polars exist; the closed form is calibrated at the static point from measured bench data instead (DR-02/DR-04), and the table generator is a deferred step behind a capability.
- **Deferred, behind capabilities:** rotor-to-rotor wake interaction; aerodynamic interaction with the frame (NeuroBEM shows it is the main residual at > 15 m/s); prop flex and stall at high rpm; motor thermal derating (EL4); turtle mode (bidirectional rotation).

### 4.2 Frames, signs and units

Body FRD at the inventory CG and NED world, per [AIRCRAFT_CONTRACT](../../AIRCRAFT_CONTRACT.md#coordinates-signs-and-units). Structural positions are in the datum frame `[x_aft, y_right, z_up]`; the multirotor datum is the frame's geometric centre on the bottom-plate plane.

Rotor quantities:

| Symbol | Meaning |
| --- | --- |
| ω_i ≥ 0 | Rotor i speed, rad/s (stored as rpm in state, as the shaft is today) |
| `spin` ±1 per rotor | Explicit data field: +1 counter-clockwise viewed from above |
| a = [0, 0, −1] | Positive-thrust axis in FRD: every rotor pushes along body −z (up). Per-rotor tilt is a later capability. |
| r_i | Rotor hub position from the CG, FRD |
| V_a, V_p | Air velocity at the hub resolved along the rotor axis and in the rotor plane; V_a maps to HELI-04's climb input along the positive-thrust axis, and crossflow is passed as a nonnegative magnitude |
| μ = V_p/(ωR), μ_a = V_a/(ωR), λ_i | Advance ratio, normalized axial flow and induced inflow under the shared HELI-04 sign convention |
| θ_75, θ_tw | Equivalent blade pitch at 0.75R and linear twist of the fixed-pitch prop (from the helical pitch, DR-02) |
| d_i ∈ [0, 1] | ESC duty command for rotor i |

Rotor numbering follows the Betaflight quad-X convention (1 rear right, 2 front right, 3 rear left, 4 front left), with the spin sense of each motor a data field; the kernel tests pin the signs:

- raising rotors 1 and 2 (right) rolls left (negative p)
- raising rotors 2 and 4 (front) pitches up (positive q): `M_y = -r_x F_z > 0` for a forward hub and upward thrust in FRD
- speeding the counter-clockwise pair yaws the body clockwise (positive r)
- the reaction torque of each rotor on the body has the sign of −`spin`

All angles are radians internally; data files use the contract's exact units. The shared inflow boundary defines the sign convention for both vehicles; tests cover positive and negative axial flow rather than assuming thrust is even in flow direction. Thrust can be signed in windmill-brake flow; reversing motor rotation remains out of scope.

### 4.3 Rotor loads

The air velocity at hub i is the CG air velocity plus ω × r_i, resolved into axial V_a and in-plane V_p. Convert the axial sign once to the HELI-04 contract before evaluating the rotor law.

**Thrust** (fixed-pitch blade-element form from DR-01, evaluated with the shared inflow sign convention):

    C_T = f_BE(θ_75, θ_tw, μ, μ_a, λ_i; a_l, σ)
    C_T ← C_Tmax·tanh(C_T/C_Tmax)          (smooth signed saturation)
    T   = C_T·ρ·πR²·(ωR)²

- `f_BE` is the fixed-pitch, uniform-inflow expression recorded in DR-01, re-derived in DR-02/03 with HELI-04's axial-flow sign convention. Do not carry the earlier `−(μ_c + λ)/2` form forward unless that mapping is derived and shown equivalent. Negative aerodynamic thrust in windmill-brake flow is representable; reverse motor rotation is not.
- a_l is the blade lift-curve slope and σ = N·c/(πR) the solidity. Neither is measured for racing props at Re ≈ 10⁵: a_l, the drag law and a tip-loss factor B are **fitted to the measured static bench points** (thrust and torque against rpm) so that the static point is `derived` from measurement and labelled with its residual. The identified `c_t` of the reference quad is the primary static constraint; the bench dataset of the race build is the second.
- The existing airplane `thrust_torque` (static Ct·ρn²D⁴) is the unit-test oracle at zero axial and in-plane flow.

**Shared inflow (HELI-04):** `app/physics/rotorcraft/inflow.gd` is intended to own the signed momentum branches, Johnson's normalized VRS model, windmill-brake branch, Hayden ground-effect correction and inflow derivative. Its standalone source law is not session-ready until HELI-04 qualifies the verified Johnson Table 3 crossflow cutoffs C/M under dynamic-flow refinement and full-evaluation cost. After that, DR-04 consumes `target(T_i, ρ, R, V_a, |V_p|, z/R, loss, instability)` with signed physical thrust in newtons; it uses the returned induced velocity, hover velocity and ground factor, then calls `derivative(λ_i, λ_target, Ω_i, λ_effective, λ_floor)` if inflow is integrated as state. DR does not duplicate the momentum/VRS/ground-effect equations, fit a separate VRS curve or add a guessed smoother. Johnson's NASA/TP-2005-213477 model is a mean-inflow extension for isolated rotorcraft rotors ([NASA NTRS primary source](https://ntrs.nasa.gov/citations/20060024029)); its transfer to 5-inch racing props is an estimate until held-out or physical data cover that regime.

**Torque:**

    C_Q = f_Q(C_T, λ_i, μ_a, μ; σ, C_d),   Q = C_Q·ρ·πR²·(ωR)²·R

- `f_Q` is the DR-01 prop profile and induced-torque expression, derived with the shared axial sign convention in DR-02/03. C_d(α̂) = C_d0 + d1·α̂ + d2·α̂² with α̂ the mean section angle at 0.75R; the quadratic drag is what makes current rise faster than thrust at full throttle, which the bench data constrains.
- The reaction torque on the body is −`spin`·Q about a.

**In-plane H-force and hub moment** (rigid fixed-pitch blades do not flap; the advancing/retreating asymmetry appears as forces and moments at the hub):

- H-force along −V̂_p from the profile and induced terms, with λ_i and μ_a in the shared sign convention; the prop-specific expression is derived from Leishman ch. 5 and Padfield in DR-03.
- Hub moment ∝ ρπR²(ωR)²R·(a_l σ/2)·μ·(θ_75 − …), giving the nose-up moment with speed.
- The linear rotor-drag model of the control literature (F_h = −k_h·ω·V_p) is the small-μ check; the identified k_h of the reference quad is a held-out comparison, not a fit.

**Ground effect:** HELI-04 applies its Hayden correction to induced velocity for each rotor using that hub's terrain clearance and disk orientation; do not add a second thrust multiplier. Cheeseman–Bennett remains an independent check where its stated range applies (z/R > 0.6); values below that and any multirotor correction remain `estimated`. Do not add a guessed rotor-count factor to the shared law. The 2026 small-rotor measurements and the limits of the multirotor evidence are recorded in [DR-01 §6](../research/drone-racing/DR-01/README.md#6-secondary-aerodynamics).

### 4.4 Powertrain: four motors, one pack

Per rotor i, reusing the EL kernels where their law is unchanged:

    E_i   = ω_i / K_v,si                       back-EMF
    I_i   = (d_i·V − E_i) / R_m                ESC kind `synchronous` (bidirectional: braking current flows back to the pack)
    I_i   = max(0, (d_i·V − E_i) / R_m)        ESC kind `ideal_motoring` (today's one-quadrant law, kept for comparison)
    J_i·ω̇_i = k_t·(I_i − I_0) − Q_i(ω_i, flow) − `spin`·J_i·(α_body·a)
    V     = OCV(SOC) − R_pack·(Σ d_i·I_i + I_aux)

- With every motor in the linear branch the bus voltage has the closed form V·(1 + R_pack·Σ d_i²/R_m) = OCV − R_pack·I_aux + R_pack·Σ d_i·E_i/R_m; the clamped kind iterates the active set (≤ 4 passes). This generalizes `electric_supply.gd`'s single-motor closed form and is the shared-bus solve the EL owner reviews (DR-05).
- **Why `synchronous` matters (D8):** modern racing ESCs drive the bridge with complementary PWM, so a lowered command brakes the motor against the pack. With the one-quadrant law a motor can only slow down through prop drag, which at 10,000 rpm takes several times longer than a real throttle chop; air mode and every yaw command rely on fast deceleration. The pack current goes negative transiently; charge accounting already handles signed current.
- Idle floor and limits: the mixer never commands below `esc.idle_duty` while armed (Betaflight's idle, ≈ 5.5 %, `estimated` default) and never above `esc.output_limit`. The mapping from command to duty is linear, declared as `command_mapping: "linear"`; a measured ESC map is a later field.
- Motor time constant is not a field: it emerges from J_i, R_m, k_t and the torque law (16–28 ms at hover for the typical build with J = 7 × 10⁻⁶ kg·m², [DR-01 derived checks](../research/drone-racing/DR-01/README.md#derived-checks)). The reference quad's identified constant is 33–39 ms, measured on a load cell behind a real ESC; DR-09 measures J (prop plus bell) and DR-38 compares the emergent lag with the identified one. If the gap stays above the tolerance, the ESC's documented ramp limits are the first suspect (EL3), not a tuning constant.
- Command to speed: Betaflight sends an 11-bit DShot value that the ESC applies as voltage duty; thrust is not linear in duty, which is why the firmware offers `thrust_linear` and why the Swift work fitted steady-state speed as a polynomial of pack voltage and command. The physical model needs no such fit: ω follows from duty through the motor law and thrust ∝ ω². A fitted `command_mapping` is a later field for ESCs that document a nonlinear throttle.
- Battery: the EL2a OCV/resistance pack with SOC, delivered energy and pack heat, unchanged. Racing packs need the pack resistance (2–6 mΩ per cell for fresh packs, community figures, `estimated`) and an OCV–SOC curve; the one published, validated small-pack model (Bauersfeld & Scaramuzza 2022: OCV polynomial, 4.5 mΩ/cell, one RC pair with τ = 3.3 s, validated on a 4S 1.8 Ah pack at 100–800 W) supplies `borrowed` coefficients, and its RC pair is the EL2b polarization state the electric plan already reserves, admitted only if the residual justifies it. Exhaustion ends the flight as EL2a's event does; a low-voltage warning is presentation.
- Stiffness: the explicit-step ratio of §2 F7 is recomputed by the loader from the actual J, R_m and K_v; DR-09 qualifies the acceptable ratio for this configuration with h/h2 refinement at a full-throttle punch, instead of copying the airplane's 0.25.

### 4.5 Airframe

- **Drag:** quadratic three-axis drag areas S_x, S_y, S_z (Heffley form, F_k = −½ρ·S_k·v_k·|v_k|, no α/β singularity), `estimated` from frame, battery and camera frontal areas. At 44 m/s a 0.012 m² area is ≈ 2.2 g of drag: the frame, not the rotors, caps top speed.
- **Rotor-induced body loads** are in §4.3. A canopy lift or pitching couple at high speed is an optional later field.
- **Mass and inertia** from the inventory (frame, arms, motors, ESC, FC, camera, VTX, battery, props), as every aircraft here. The battery is the largest item and sits above the CG: the data states its position so that a 6S pack swap moves the CG honestly.

### 4.6 Gyroscopic and inertial coupling

All rotor axes are parallel to a, so `RotorCoupling.response` generalizes from one unit to N signed parallel rotors:

- rotor momentum h = J_r·Σ `spin`_i·ω_i · a; for matched pairs it nearly cancels, and reappears under differential rpm (4.4 mN·m·s at ±3,000 rpm with J_r = 7 × 10⁻⁶ kg·m², 77 mN·m of precession at 1,000°/s roll: small but not zero)
- the body receives Σ `spin`_i·(Q_motor,i − Q_aero,i) about a: the **inertial yaw** that gives a quad most of its yaw authority at hover (the Swift model carries the same motor-acceleration yaw term; with J_r ≈ 10⁻⁵ kg·m² and a 2,500 rad/s step in 35 ms it is ≈ 0.7 N·m per rotor, the size of the control torques)
- each rotor's relative acceleration subtracts the body's angular acceleration about a, solved simultaneously as G2a does (angular momentum and motor work closure tests)

The airplane call path keeps its existing arithmetic, with a byte-identity test.

### 4.7 Flight controller (what makes a quad feel like a quad)

The controller runs **once per tick in `aux`, as a zero-order hold**, like a real 240 Hz sampled controller. Real controllers run at 4–8 kHz; the difference is a loop delay of one tick (4.2 ms) instead of ≈ 0.5 ms, and the inability to represent filters above the 120 Hz Nyquist frequency. The consequence, and the rule that follows from it:

- **Rates and expo import one to one.** They map stick to rate setpoint and do not depend on the loop rate.
- **PID gains are simulator-owned equivalents.** A pilot's Betaflight PID profile is not imported (D3, D11). DR-21 tunes the equivalent gains so that the closed-loop step response matches an 8 kHz reference controller on the same plant (DR-03) within a declared tolerance; that comparison is the fidelity gate, and its result is recorded with the data. The reference starts from the firmware's documented defaults at a pinned commit (roll P/I/D/FF 45/80/30/120, pitch 47/84/34/125, yaw 45/80/0/120; gyro low-pass 250–500 Hz, D-term low-pass 75–150 Hz; feed-forward smoothing; level P 50 and 60° angle limit) because that is the loop most pilots fly.
- **The reference loop has two forms.** The offline Python model at 8 kHz (DR-03) is the primary, MIT-clean reference. Betaflight's own SITL target (a separate GPL process talking UDP to a flight-dynamics model) is an optional research check of that model: it runs the real firmware against our plant equations exported to it, never linked into the application and never shipped.
- **No code is copied from Betaflight** (GPL-3). The rate formulas, mixer algorithm and mode semantics are implemented from the published documentation and source reading, and tested against their documented examples (R9).

Pipeline per tick:

    sticks (4) ─► link delay (N ticks, data) ─► rates (Actual / Betaflight) ─► mode (acro | angle | horizon)
      ─► rate PID + FF with gyro and D-term low-pass ─► quad-X mixer with air mode, idle floor, output limit
      ─► four duties d_i ─► ESC/motor (§4.4)

- **Rates.** `rates.type` selects the law. Actual rates (the firmware default since 4.3; defaults 70 deg/s centre, 670 deg/s max, expo 0): `rate = x·C + max(0, M − C)·|x|·(x⁵·e + x·(1 − e))` with centre sensitivity C, max rate M (deg/s) and expo e. Betaflight rates: `rate = 200·rc_rate·(x·|x|³·e + x·(1 − e)) / clamp(1 − |x|·super_rate, 0.01, 1)`, with rc_rate above 2 expanded as documented. Raceflight, KISS and Quick are importable later from the same source reading. Output is clamped at ±1,998 deg/s as the firmware does. All curves are pinned by tests against the documented examples ([DR-01 §4](../research/drone-racing/DR-01/README.md#4-flight-controller-behaviour)). Throttle is linear (an optional throttle expo/mid field later). Racers fly ≈ 550–650 deg/s near-linear, freestyle 850–1,200 deg/s; the achievable rate is capped by motor authority, not by the curve.
- **Modes** (`modes.flight_mode`): acro (rate) is the racing default; angle (self-level: setpoint = P_level·(x·max_angle − angle), max angle a data field, 55° typical) is the real FC feature a keyboard pilot needs (D6); horizon blends the two. Turtle (flip-over) needs bidirectional motors and is deferred.
- **Rate loop per axis:** P·e + I·∫e (clamped, with I-term relax optional) + D·(−ġ_f) + FF·ṡ, where g_f is the gyro through a first-order low-pass with declared cutoff and ṡ the setpoint derivative. Filter cutoffs above 60 Hz are replaced by a one-tick equivalent and declared as such in the data (`estimated`, fidelity note). Throttle-PID attenuation and anti-gravity are optional fields, off by default. Gyro noise is **off**: a noisy gyro would need the seeded-RNG transaction pattern of M5-W04a and buys nothing until a filter can be represented.
- **Mixer (quad X):** m_i = t + Σ_axis k_i,axis·u_axis; air mode keeps the PID active at zero throttle and, when the span max(m) − min(m) exceeds 1, scales the PID share and shifts the throttle so that the span fits; then clamp to [idle, output_limit]. This is the documented "legacy" mixer behaviour (the firmware's default `mixer_type`); the "dynamic" variant is a later option. The plan reproduces the documented examples, including the loss of control authority at full throttle that pilots feel in a punch-out. Idle is the firmware's 5.5 % default; the dynamic-idle rpm floor is a later option.
- **Arming and failsafe** (`modes.armed`, `modes.failsafe`): arming needs the arm switch (or key) with throttle at or below the arm threshold the radio path already enforces (5 %); disarm on switch, on crash when `crash_disarm` is set, or on failsafe after a declared delay. The failsafe procedure is "drop" (motors stop); a declared "land" procedure is a later field. The radio-unplug failsafe of the session (idle, neutral, pause) maps to this.
- **Link delay** (D14): an optional `link.delay_ticks` ring buffer on the sticks models the RC link and its smoothing: ExpressLRS packet intervals are 1–2 ms at 500–1,000 Hz, the firmware's RC smoothing adds a few ms, and no independent end-to-end measurement was found, so the default is 1 tick labelled `estimated`. The measured chain that matters for feel is elsewhere: 40 ms from command to force through Betaflight and the motor on the reference quad, 14–30 ms of video latency and 23–55 ms of goggle display lag by model, against a 220 ms human visuomotor delay ([DR-01 §4](../research/drone-racing/DR-01/README.md#4-flight-controller-behaviour)). The motor part emerges from the powertrain; the video part is a presentation setting (§9.3, D14).

### 4.8 State inventory

| Tier | Entries | Notes |
| --- | --- | --- |
| Body (existing) | 13 | Unchanged |
| `continuous` (RK stages) | ω_1…ω_4 (4); remaining charge, delivered energy, pack heat (3, EL2a); λ_1…λ_4 only if DR-03/09 show the shared inflow derivative is resolved at 240 Hz | Joint evaluate returns `{loads, derivative, rotor_momentum}`; the selected steady/dynamic inflow treatment is recorded in trace metadata |
| `aux` (tick-held) | d_1…d_4; per axis: I-term, gyro low-pass state, D low-pass state, previous setpoint (12); link ring buffer (4 × N); telemetry mirrors: rpm_1…4, bus voltage, pack current, mixer saturation flag | Sampled once per tick, like a real controller output |
| `modes` (discrete) | `armed`, `flight_mode`, `failsafe`, `crash_disarm`; race: `race_state`, `next_gate`, `lap`, `gate_count` | Tick-transactional; race entries owned by the race director (§8) |

### 4.9 Control chain (what the pilot moves → what the rotor does)

    sticks (4) ─► [throttle no-spring, 0…1] ─► FC §4.7 ─► d_i ─► ESC (synchronous) ─► motor ODE ─► ω_i ─► C_T(ω_i, flow) ─► T_i, Q_i, H_i

- There are no servos and no surfaces; the `srv_*` aux entries of airplanes do not exist for the quad.
- The same four duties drive physics, the rendered discs and the sound: no renderer-only retuning.

### 4.10 Ground, pad and prop strike

- **Legs.** Four contact points at the arm tips or standoffs, with vertical spring-damper (E1/E1b onset law, stiffness bounded by ω·dt < 0.1 — ≈ 370 N/m for 0.65 kg, 4 mm static sag) and the **isotropic regularized Coulomb** friction mode the helicopter plan specifies for skids (HELI-19): a friction circle without heading, stiction anchors, no rolling resistance. Four contacts with zero steering pass the contract's topology check. This is a contract `gear` capability `legs` owned with the ground track and shared with `skids`.
- **Pad start.** A static solve on the legs generalizing `ground_start.gd` (DR-18): disarmed, ω = 0, on the track's start pad or the field pad. Arming spins the motors to idle; the FC holds them there until the throttle rises.
- **Hover start** (tests, captures and a menu option): airborne at 1.5 m above the pad, ω_i from the static hover solve, FC integrators zero.
- **Prop strike.** The terminal hull keeps the body points (camera, battery, arm tips, antenna). A **rotor-disc clearance ring** adds 8 points per rotor on its disc, checked each tick against terrain and scenery proxies while the rotor spins above a threshold; a crossing ends the flight with cause `prop_strike`. With the rotors stopped the discs are not checked, so a disarmed quad can sit on grass. Shared with HELI-21.
- **Gate contact.** Gate posts and bars are scenery proxies (§8.7) with the sweep that exists; a hit below the class threshold is a bounded impulse (a bump), above it a terminal crash. Props hitting a post are prop strikes.

### 4.11 Equilibrium and linearization

- **Hover** has a closed form: ω_h from C_T(ω) = m·g/(4ρπR²(ωR)²) by one-dimensional Newton, level attitude, d_i from the motor law. No six-axis trim solve is needed; `_prepare_aircraft` branches to it (DR-18).
- **Forward flight** trim (pitch angle and throttle against drag at a given speed) is a two-unknown Newton on the same loads, used for the speed/pitch bucket in DR-38 and for forward starts in tests.
- **Linearization** reuses `linearize.gd` for the open-loop hover modes (the unstable pendulum-like pair, heave, yaw) against DR-03; the closed loop is judged on time responses (DR-21), because the controller is discrete.

### 4.12 Cost budget

| Item | Budget (H15 host, median) |
| --- | --- |
| Multirotor rotor and airframe loads, 4 evaluations per tick | ≤ 100 µs |
| Powertrain (4 motors, shared bus) and battery derivatives, 4 evaluations | ≤ 60 µs |
| Flight controller, once per tick | ≤ 10 µs |
| Race director and gate sweep, once per tick | ≤ 15 µs |
| Whole tick, armed hover on the pad with leg contacts | ≤ 350 µs |
| Whole tick, any regime including gate proxies nearby | ≤ 500 µs (Gate P rule) |

- Four rotors with the shared inflow call are estimated at 100–150 scalar operations each per evaluation; no strip loops.
- The kernel is benchmarked **before** integration (DR-09) and the whole tick after it (DR-22).
- Scalarize from the start, following H3/H12: no per-call arrays, trigonometry through `math3d` (H6 guard), and no duplicate per-rotor inflow solver.

### 4.13 Non-goals

Out of scope for this plan:

- per-blade marching, blade flex, prop stall maps
- rotor–rotor and rotor–frame wake interaction (declared residual, measured in DR-38)
- turtle mode and reverse rotation; bidirectional DShot telemetry
- motor and ESC thermal limits (EL4)
- GPS, barometer, position hold, return-to-home or any autopilot
- real radio-link or video-link modelling (a delay is a parameter, not a link model)
- multiplayer; online leaderboards (ghosts are local)
- an in-app track editor (tracks are data, D9)
- whoop-class ducted props (different rotor data) and 7-inch long-range builds
- structural or flyable damage

An angle (self-level) mode is **not** an autopilot: real flight controllers have it, and it is in scope because the modelled hardware has it (D6).

## 5. Data contract

**Recommendation (D5): a sibling format `openrc-multirotor v1`** with `vehicle: "multirotor"`, not a branch of `openrc-aircraft v2` and not a conditional block inside the proposed `openrc-rotorcraft v1`.

- The v2 loader requires a wing, stable-airplane derivatives, tails and a forward shaft (§2 F9); a branch would touch the frozen AS migration and the 152-path register.
- A helicopter file describes a main rotor, tail rotor, swashplate and governor; a quad file describes N identical rotors and a flight controller. Two closed shapes are simpler to validate than one shape with mutually exclusive blocks.
- The sibling format shares the v2 *rules*: every quantity `{value, unit, kind, source}`, explicit capabilities, inventory-derived mass/CG/inertia, strict unknown-key errors, file-byte and semantic hashes, a generated schema. It shares the *kernels*: quantity parsing, inventory and inertia, identity, the EL battery block, and HELI-04's inflow contract. Other extractions happen only if needed, with airplane byte-identity proof.

Sketch of the multirotor blocks; the exact paths are fixed in DR-10:

    format: "openrc-multirotor v1", vehicle: "multirotor", convention_id: "openrc-le-frd-v1"
    capabilities: { controls: "flight_controller", layout: "quad_x", gear: "legs", energy: "ocv_resistance",
                    damage: "terminal_hull_prop_disc", esc: "synchronous", electronics: "rate_angle_horizon" }
    reference:    { wheelbase, rotor_count: 4, prop_diameter, mass_class }
    rotors:       [ { id: 1…4, position [x_aft, y_right, z_up], spin: ±1 } ]      (positions datum-relative; CG subtracted at derivation)
    rotor_model:  { radius, blades, chord_075, theta_075, theta_twist, lift_slope, tip_loss, profile_drag{cd0,d1,d2},
                    ct_max, inflow{loss, instability, lambda_effective, lambda_floor as applicable; HELI-04 units and provenance},
                    ground_effect{shared HELI-04 height convention}, inertia,
                    static_calibration{rpm[], thrust_n[], torque_nm[], residual} }
    motor:        { kv_rpm_per_volt, resistance_ohm, resistance_scope, no_load_current_a, no_load_context, pole_pairs }
    esc:          { kind: "synchronous" | "ideal_motoring", idle_duty, output_limit, command_mapping: "linear" }
    battery:      EL2a block (kind, capacity_ah, resistance_ohm, auxiliary_current_a, initial_soc, ocv_points)
    airframe:     { drag_areas [x, y, z] }
    flight_controller:
                  { rates{ type: "actual" | "betaflight", roll{center, max, expo}, pitch{…}, yaw{…} },
                    pid{ roll{p, i, d, ff}, pitch{…}, yaw{…}, i_limit, i_relax? },
                    filters{ gyro_lpf_hz, dterm_lpf_hz },        (declared with the one-tick-equivalent note)
                    mixer{ airmode: true, idle_duty_source: "esc" },
                    angle{ level_p, max_angle_deg, horizon_transition },
                    arming{ throttle_threshold, crash_disarm, failsafe{ procedure: "drop", delay_s } },
                    link{ delay_ticks },
                    fidelity{ reference_loop_hz: 8000, step_response_tolerance, record: "<DR-21 evidence path>" } }
    legs:         { contacts[4]{ name, position, stiffness, damping, travel }, friction{ mu, regularization } }
    crash_hull:   labelled points (CR-01d): camera, battery, arm_1…4, antenna
    camera_mount: { position, uptilt_deg, fov{ horizontal, vertical, diagonal }, aspect: "4:3" | "16:9", lens: "rectilinear" | "barrel" }
    inventory, balance, plausibility, start: { pad | hover }

- The generator is `research/drone-racing/<quad>/derive.py`. It emits the JSON from a source table that cites each paper table or bench row, with a `--check` mode, as the P-51 and Extra generators do. The JSON is never hand-edited.
- Rates files: `openrc-rates v1` (`user://rates/<name>.json`), produced by the Betaflight `diff rates` importer (DR-08) and selectable per flight. The aircraft file carries the default rates with provenance; a loaded rates file overrides them and is recorded in the trace metadata.

## 6. Session integration

- **One seam in `FlightSession`.** When `model.vehicle == "multirotor"`, `_configure_continuous_callbacks` selects `_multirotor_evaluate`, `_pre_step` runs the flight controller instead of the servo limiter, and `_prepare_aircraft` uses the hover/pad equilibrium instead of `trimmed_level_across_view`. The callback returns the joint `{loads, derivative, rotor_momentum}` from `physics/multirotor/loads.gd` plus `Ground.evaluate` on the legs. Every airplane path stays as it is.
- **Proof of non-interference** at every integration step: all existing goldens, `check_trimmed_flight` traces and 30/60/144 fps determinism checks are byte-identical; `test.sh` is green.
- **New state classes:**
  - a checkpoint format bump with a multirotor law string and the race block
  - restore whitelist entries for every new aux and mode entry
  - a trace column group `MR_COLUMNS`: `rpm_1…4, duty_1…4, bus_v, pack_a, soc, setpoint_p/q/r, mode, armed, mixer_sat, thrust_n, vz_over_vh, z_over_r`, plus `lambda_1…4` when inflow is integrated as state; `metadata_schema` records the HELI-04 kernel identity and chosen steady/dynamic treatment. `RACE_COLUMNS`: `race_state, next_gate, lap, lap_time_s`
  - a new `metadata_schema` version and an `input_semantics` field (`airplane_aetr`, `heli_aetc`, `multirotor_fc`), plus the rates profile identity
  - `replay_policy` classes for every new entry (the controller integrators are tick-exact state, not tolerance-replayed quantities)
- **Multirotor goldens:** `hover_hold`, `punch_out`, `roll_flip`, `yaw_spin`, `descent_propwash`, `pad_arm_takeoff`. They are recorded only after the model-to-data comparison passes (DR-38) and re-recorded only for an explained physics change. `golden_flights.gd` refuses to record or replay while the shaft is coupled (`session.shaft_is_coupled()`); DR-17 extends the format to coupled continuous tails (electric airplanes benefit too) rather than adding a second format.

## 7. Input and controls

- **Four sticks, same width (D6).** `[roll, pitch, yaw, throttle]` are the flight controller's inputs; the trace `cmd_*` columns keep their names. Throttle is 0…1 with **no spring and no centre**: racing gimbals are non-centering, so the radio calibration gains a "throttle: no centre" flag that disables the centre step and keeps the existing low-throttle arming evidence (5 %).
- **Switches** are discrete `modes` entries fed by an optional switch mapping in calibration (shared with HELI-14 and the smoke track's SM-03 AUX work): any of the 10 raw axes as a two- or three-position switch with declared thresholds, or a joypad button. EdgeTX's USB joystick mode exposes channels 9–32 as 24 buttons, so an arm switch on CH9 is a button, not an axis ([DR-01 §9](../research/drone-racing/DR-01/README.md#9-input)). `RcInput.poll` already takes an optional button reader for the smoke pump's auxiliary binding (SM-03/04); the mapping step generalizes that single binding into named switches with the same failsafe rules.
  - `arm`: switch or key; arming is refused unless throttle ≤ threshold, as the radio arming rule already does; disarm anywhere.
  - `mode`: acro / angle / horizon, three-position switch or a key.
  - keyboard proposal: **Space** arm/disarm, **M** cycle flight mode (a key-clash check against HUD **H**, camera **C/Z/V**, trace **T**, reset **R** is part of DR-14; final keys in that step).
- **Keyboard flying.** A keyboard cannot fly a racing quad in acro. The keyboard profile defaults to **angle mode** (a real flight-controller mode) with throttle as a rate-integrated axis, like the gamepad profile does today; gamepad and radio default to acro with angle selectable. No invented stabilizer beyond what the modelled firmware has (D6).
- **Rates import (D11).** `research/drone-racing/tools/import_rates.py` and a GDScript parser read a Betaflight `diff rates` / `dump rates` text block (`set rates_type = ACTUAL`, `set roll_rc_rate = 7`, `set roll_srate = 67`, `set roll_expo = 54`, …) into `openrc-rates v1` with the source text hashed. Only rates, expo, throttle limit/expo, `dshot_idle_value`, `motor_output_limit` and the angle-mode limits are imported; PID, filter and feed-forward lines are ignored with a listed warning (§4.7). The importer is tested against the documented example values (7/67 → 70/670 deg/s).
- **Shaping.** The D6e stick shaping (`controls.rates`) does not apply: the flight controller's rates are the shaping. A gamepad keeps its deadzone; its expo is disabled when the vehicle is a multirotor so that imported rates are not shaped twice.
- **Failsafe.** The radio-unplug failsafe (idle, neutral, pause) becomes `failsafe = drop` after the declared delay: motors stop, the quad falls, the crash director grades the impact. Pause/holds keep the controller frozen as the servos are today.

## 8. Race mode

The race layer is simulation-side, deterministic and replayable: a trace replayed through the director reproduces every lap time to the millisecond.

### 8.1 Track format `openrc-track v1`

    format: "openrc-track v1", id, name, field: "default", source
    start:    { pads[ { north, east, heading } ], procedure: "fai_tone" | "staged_tones", random_hold_s: [0, 5] }
    elements: [ { id, type, north, east, down (base), heading, pitch?, size: { width, height } , led: bool } ]
    sequence: [ { element, direction: "forward" | "either" } ]          (last entry is start/finish for lap races)
    rules:    { laps: 3, missed_gate: "invalid_lap", min_lap_s: 5, timer_s: 120, scoring: "best_3_consecutive" | "fastest_lap" | "total" }

Every position is in metres, `{value, unit, kind, source}` where a value is physical. Gate poses are recorded from the gate centre with the heading of the intended crossing; the MultiGP setup guides measure from the left leg as entered, so the loader accepts an optional `left_leg` reference and converts. The field's start pad for the quad is declared in `openrc-field` (coordinated with the field owners), 10–15 m north of the pilot on the mown strip, like the helicopter pad (D10 there).

### 8.2 Element library and dimensions

From the MultiGP obstacle and class pages and the FAI F9U code ([DR-01 §5](../research/drone-racing/DR-01/README.md#5-racing-formats-rules-and-track-elements)):

| Element | Size | Source |
| --- | --- | --- |
| `gate_5x5` | 5 ft × 5 ft opening (1.52 m), PVC frame, vinyl mesh panels | MultiGP Open class gate |
| `gate_7x6` | 7 ft wide × 6 ft tall (2.13 × 1.83 m) | MultiGP Pro Spec / championship set |
| `flag` | pole ≥ 8 ft (2.44 m) with a 1 ft wide, ≥ 5 ft tall side panel | MultiGP track guide; gate+flag panel |
| `hurdle` | 5 ft tall × 10 ft wide bar to cross over | MultiGP obstacles |
| `tower` | a 5×5 gate elevated 5 ft (6 ft in the championship set) | MultiGP obstacles |
| `double_gate` | two 5×5 gates stacked | MultiGP obstacles |
| `ladder` | three stacked gates, elevated | MultiGP obstacles |
| `dive_gate` | horizontal 5×5 gate elevated 15 ft with a slight entry angle | MultiGP championship set |
| `launch_gate` | horizontal gate, panels facing the ground, at the start | MultiGP championship set |
| `split_s` | gate with flags 1.5 ft behind and beside; must be flown up-and-over | MultiGP championship set |
| `whoop_gate` | 19 in and 30 in openings | MultiGP UTT #7 / Whoop class; later |

FAI requires ≥ 1.5 m free diameter for crossed obstacles and ≥ 2.5 m for avoided ones, which every 5×5 gate satisfies. Only the first five rows are needed for the first tracks; the rest are data entries once the mesh generator exists.

### 8.3 Gate-pass detection and timing

- **Detector.** Each tick, in `post_step` beside the scenery sweep, the CG segment from the previous committed position to the new one is tested against the gate's inner rectangle (oriented plane, half-extents from `size`, a declared thickness of 0 since a segment crossing is exact). The crossing direction must match `direction` unless `either`. The crossing fraction f along the segment gives the time `t_prev + f·dt`, so lap times carry millisecond resolution at a 4.2 ms tick (12.5 cm per tick at 30 m/s; linear interpolation error ≪ 1 ms). Results are rounded to 1 ms for display, like the transponder timers.
- **Sequence.** The director keeps `next_gate`. A pass through `next_gate` advances; a pass through any other gate is ignored (FAI: a missed obstacle may be re-attempted; the lap is not validated otherwise). A pass through start/finish with `next_gate == 0` ends the lap; `min_lap_s` discards impossible laps (RotorHazard's minimum lap time). The first start/finish crossing after the tone starts lap 1 ("hole shot" first-crossing mode); the option "first lap ends at the first crossing" is a rules field.
- **Start procedure.** `fai_tone`: "Arm your quads", about 3 s, one tone, no countdown. `staged_tones`: per-second prestage tones with a random 0–5 s hold (RotorHazard staging). Motion of the CG by more than a declared radius before the tone is a false start: the race restarts (penalty variants are a later rules field).
- **Race states** (`modes.race_state`): idle → staged (armed on the pad) → running (after the tone) → finished (laps complete, or the fixed timer with a grace lap) → results. A crash in `running` keeps the state; the respawn choice (pad or last gate) is the pilot's (DR-20), and a lap with a respawn is marked.
- **Determinism.** The director reads committed state only; its state is in the checkpoint; a replayed trace reproduces the same lap list (test in DR-25).

### 8.4 Results and ghosts

- Results per race: lap list with times and validity, holeshot time, best lap, best three consecutive laps (the GQ score), total time, gates missed, crashes and respawns, rates profile identity, aircraft identity. Persisted to `user://races/<track-id>/<aircraft-id>.json` (additive, versioned); automation routes never read or write it, like preferences.
- Comparison anchors from real events, not acceptance targets: GQ laps of 10–13 s and best-3 of 28–36 s on the 10-gate/5-flag course; UTT single laps; 80–100+ mph straights ([DR-01 §5](../research/drone-racing/DR-01/README.md#5-racing-formats-rules-and-track-elements)).
- **Ghost** (DR-27): the pose stream of a lap (60 Hz, position and quaternion, render-side float32 is enough) stored with the result; replayed as a translucent copy of the model. Presentation only; never affects the session or the trace.

### 8.5 Authored tracks on the default field

The default field has a 100 m × 12 m mown strip centred 15 m north of the pilot and rough grass elsewhere; the treeline starts ≈ 500 m west ([default.json](../../app/data/fields/default.json)). Three data tracks, all `estimated` layouts:

| Track | Layout | Purpose |
| --- | --- | --- |
| `strip-sprint` | 6 gates (5×5) in a 120 × 30 m oval around the strip, two flags at the ends, start pad at the west end, counter-clockwise, 3 laps | First flyable track; UTT-like |
| `gq-style` | 10 gates and 5 flags on the 45 × 30 m base grid of the 2020 GQ setup guide, placed east of the strip, best three consecutive laps in 120 s | The MultiGP qualifier format |
| `pad-free` | start pad, a tower, a dive gate and a hurdle, no sequence | Freestyle and practice |

The exact GQ gate coordinates are image-only in the published PDF (DR-02 digitizes them with provenance); until then `gq-style` uses the stake grid and spacing figures that are printed.

### 8.6 Spectating and the pilot view

The pilot stands at the station and can fly line-of-sight in the pilot view; the auto-zoom uses the wheelbase as the span so the quad stays readable. The race HUD (lap, next gate, gap to best) appears in both views through the overlays track.

### 8.7 Collision classes for track elements

Gate posts and bars are vertical capsules and heading-only boxes in the collision world (`openrc-collision-world v1` already supports both), with a new response class `race_frangible` (restitution 0.2, terminal above a declared 8 m/s normal speed, `estimated`) and flags as `soft_foliage_impulse`. A hit below the threshold is a bump the pilot recovers from; above it the crash director takes over with cause `gate_strike`. Prop contact with a post is a prop strike (§4.10). The world identity hash includes the track so a checkpoint cannot restore into a different layout.

## 9. Presentation, VFX and audio

### 9.1 Visual model

- **Source (D10).** A procedural generator from published frame dimensions (the Stik pattern), because a racing quad is plates, arms, cylinders and props: 220 mm wheelbase X frame, 5–6 mm arms, 30.5 mm stack, 2306 motors (Ø 27.9 mm), 5.1-inch tri-blade props, 19 mm camera in a tilted cage, antenna, strapped battery, LED strip. Dimensions come from the data file's inventory and `rotors`, so the visual cannot drift from the physics.
- **Node contract** (registered with the model owners): root `airplane`; `propeller_1…4` with local +Z on the rotor axis; `propeller` aliases rotor 1 for consumers that expect one; `camera_mount`; wreck groups `arm_1…4`, `battery`, `camera`. No `*_hinge` nodes.
- **Spin.** `main.gd` spins each `propeller_i` with its own sign from a read-only per-rotor telemetry accessor, not `aux[0]`.
- **Verify script** `verify_<quad>.gd` checks node names, rotor positions against the data, clearances and the camera mount, like `verify_timber.gd`.

### 9.2 Prop discs that never strobe

- At 18–35 kRPM a tri-blade passes 900–1,750 blades per second and turns 5–10 revolutions per 60 fps frame: a racing prop is a disc at every flying rpm. The VQ-05 law already gives the disc opacity from the measured blade profile: for 14 mm chords the time-averaged coverage is ≈ 15 % at 0.7R and ≈ 50 % near the root, so the disc reads denser than an airplane's, with a coloured ring where the blades are tinted, as it does in reality.
- VQ-05 is extended to N propellers with per-rotor rpm and spin (DR-30). The 12/48 Hz cross-fade thresholds only matter at spool-up and spool-down; the stopped state must stay byte-identical.
- Compatibility rules from the VQ-05 probe apply: alpha-blended material copies, no per-instance transparency, cull disabled, no shadows from the disc, `sorting_offset` against particles.
- In the FPV view the two front discs intrude into the frame, as they do on a real camera with a wide lens; keeping them is the default (CAM D8).

### 9.3 FPV view and OSD

Built as a new `fpv` view in the camera track's rig (CAM-02, in the working tree with pilot, chase, orbit and close-up), using the onboard view, mounts and lens warp that CAM-11…13 own; DR-31 contributes the view and the OSD, and the camera owner reviews.

- **Mount** from the aircraft data: position at the front of the top plate, **uptilt 30°** default (racing 40–60°, freestyle 30–45°; a setting), FOV declared horizontal/vertical/diagonal because camera labels disagree (RunCam Phoenix 2: 155° on 4:3 with a 2.1 mm lens; DJI O4: 117.6°), aspect 4:3 with letterbox or 16:9.
- **Projection.** Rectilinear with a horizontal FOV setting of 65–137°, default ≈ 120° (Velocidrone exposes exactly this range; Liftoff pilots fly 138°+), converted to Godot's vertical FOV (120° horizontal at 16:9 is 88.5° vertical; `Camera3D` accepts up to 179.9°). Fisheye or Pannini warp is the optional CAM-12 full-screen pass; a six-face cubemap is rejected for cost.
- **Latency.** Manufacturer and independent figures put analog at ≈ 19 ms frame latency, HDZero at 14–20 ms, Walksnail at 22–30 ms and DJI O3 at 28–42 ms glass-to-glass, plus 23–55 ms of goggle display lag by model. The research finding is blunt: without a video delay the sim will feel faster than any real system whatever the aerodynamics. The FPV view therefore offers a **frame-delay buffer** (the FPV `SubViewport` texture shown N frames late, N from a declared latency and the measured frame time) with those cited presets; D14 decides its default. It is presentation only, off in captures and automation, and never presented as a link model.
- **OSD overlay** (overlays track, new overlay O8 "OSD"): a Betaflight-style character grid (PAL 30 × 16, HD 53 × 20 variant) with battery voltage and cell average (the bus voltage with sag, so a punch-out dips it), mAh used (delivered charge), current, flight timer, flight mode, ARMED, crosshair, throttle, race fields (lap, next gate, last/best lap, gap), and the Warnings line (LOW BATTERY, FAILSAFE, CRASH, DISARMED, EXPERIMENTAL). Everything reads the session's telemetry; nothing writes. Three OSD profiles (race, freestyle, minimal) as presets.
- **Analog look** (optional, off by default): a cheap screen-space noise/tearing shader keyed to range from the pilot, height and line-of-sight occlusion, the "Distance" model Velocidrone exposes. Never presented as a radio-link model.
- **Audio listener in FPV:** the pilot stands at the station and hears the quad through the air; goggles have no onboard microphone feed. The listener stays at the pilot station in both views (CAM D3 for this vehicle).

### 9.4 Track visuals

`app/render/track/` builds gates, flags, hurdles and pads from the track data: PVC tube frames as MultiMesh cylinders, mesh panels as double-sided alpha-tested quads, flag cloth on the existing windsock/motion shader, a start pad mat. Gates optionally carry LED edge strips (`led: true`) as emissive materials with the glow pass for the evening and night fields (D12); no per-gate lights (Compatibility's per-mesh light limit). Budget ≤ +20 draw calls and ≤ 0.5 ms GPU at 1080p on the owner's host; captures from the FPV, pilot and chase views.

### 9.5 Particles and prop wash

- The quad's four small rotors produce a wall jet whose peak sits at ≈ 1.75R ≈ 11 cm from each hub: grass bends only when hovering below ≈ 0.5 m, within ≈ 1 m. DR-34 reuses the helicopter's pure wash field (HELI-27) with one combined source at the frame centre and the summed thrust; zero thrust gives zero wash. Dust needs a dirt surface that the field does not have: do not invent dust on grass.
- Particles only after the shared Compatibility probe (SM-00/HELI-28): no trails, sub-emitters or `emit_particle()`; CPU depth sorting two frames old; `use_fixed_seed`; prewarm. Candidates: grass clippings on a hard landing, prop-break debris (three blades tangential at ω·r), LED-off at disarm.
- Motion blur and speed lines are not available in Compatibility and are not planned.

### 9.6 Audio

Coordinated with the audio track; `MAX_VOICES` and the voice indices change.

| Layer | Frequency (25,000 rpm tri-blade, 14-pole motor; derived) | Modulation |
| --- | --- | --- |
| Shaft and blade-passing per motor | shaft 417 Hz; blade-passing 1,250 Hz, first four harmonics sustained, higher decaying | rpm_i, load (C_T/σ), per-motor detune: four distinct lines that split in forward flight as the rear motors run faster |
| Electrical whine | commutation 7 × shaft ≈ 2.9 kHz | rpm_i, duty |
| Broadband prop noise | 600–6,000 Hz hump, ≈ 10 dB above the floor, rolling off above 6 kHz | thrust, rpm; +6–8 dB for four rotors |
| Doppler and distance | ±13 % at 44 m/s; ≈ 70–80 dBA at 1.5 m, ≈ 63 dBA at 15 m | existing manual Doppler and distance law |

Spectral anchors come from the NASA Langley and Virginia Tech small-quadcopter measurements ([DR-01 §8](../research/drone-racing/DR-01/README.md#8-vfx-and-audio)). Assets come from the seeded generator (`tools/audio/generate.py`) or rpm-pitched loops; a GDScript `AudioStreamGenerator`, if used, runs at ≤ 22,050 Hz. Crash: motor cut, prop break, slide. The owner's listening review is the acceptance.

### 9.7 HUD and warnings (line-of-sight view)

- O1 flight data reinterpreted for a quad: ground speed, height, vertical speed, throttle, distance, timer; O5: mean rpm and the four rpm in the developer overlay, bus voltage, pack current, SOC.
- O3 warnings: BATTERY LOW (bus voltage under load below a per-cell threshold, or SOC below 15 %), DISARMED, FAILSAFE, PROP STRIKE on crash, EXPERIMENTAL. Thresholds are display aids awaiting pilot review, as the existing overlays state.
- Race HUD in O1 or a race overlay: lap, next gate, last and best lap, gap to best.

### 9.8 Crash

Coordinated with the crash track and its CR-01d semantic hull labels.

- **Hull labels:** `arm_1…4`, `propeller_1…4` (disc ring), `camera`, `battery`, `antenna`.
- **Causes:** prop strike, gate strike, ground impact after disarm (failsafe or crash disarm), VRS descent into the ground, battery exhaustion, tree or building.
- **Wreck groups:** arms with motors, props (tangential debris), battery, camera cage. The component estimate must use the wheelbase, never a wing span.
- **Respawn:** after the 1.5 s hold, reset to the pad (default) or, in a race, to the last gate passed at a declared offset, disarmed, with the lap marked (DR-20). Betaflight's flip-over-after-crash needs bidirectional motors and is deferred.

## 10. Steps

Each step is one small working change with its proof. A step that touches a coordinated file states the owner's acceptance.

### Phase 0: decision and reference

| ID | Work | Proof / status |
| --- | --- | --- |
| DR-00 | Track registration and scope row; ROADMAP pointer. Record remaining owner choices for reference aircraft, controller and racing product defaults. | Registration, scope and pointer / done; product recommendations D1–D14 remain provisional / open |
| DR-01 | Research record: sources, parameters, derived values, seam map | [DR-01](../research/drone-racing/DR-01/README.md) / done |
| DR-02 | Read the remaining primary sources in full: the reference quad's parameter tables and dataset format, the NeuroBEM evaluation protocol, the Betaflight mixer/air-mode and failsafe documentation, the FAI F9U 2026 edition and the MultiGP rulebook (ground start, heats, rejoin), the 2020 GQ gate coordinates; measure or borrow the prop chord/pitch distribution | Updated parameter table with page references; every [U] in §4, §8 and §9 resolved or kept explicit |
| DR-03 | **Offline reference model** `research/drone-racing/reference/` (Python, stdlib + pinned NumPy): §4 rotor, powertrain, airframe and controller equations; hover and forward equilibria; linearization; the controller at 8 kHz and at 240 Hz on the same plant; scripted time responses; optional check of the 8 kHz controller against Betaflight SITL over UDP (separate GPL process, research only) | Reproduces the identified hover point and the NeuroBEM replay script; emits oracle CSVs for GDScript known-answer tests; publishes the 8 kHz-vs-240 Hz step-response comparison that DR-21 must meet |

### Phase 1: pure physics kernels (no session changes)

| ID | Work | Proof / status |
| --- | --- | --- |
| DR-04 | `multirotor/rotor.gd`: prop-specific blade-element thrust/torque, H-force and hub moment; consume HELI-04's signed inflow, Johnson VRS/windmill branches, ground effect and derivative without editing `rotorcraft/inflow.gd`; start only after HELI-04 qualifies the verified Table 3 crossflow cutoffs C/M under dynamic-flow refinement and full-evaluation cost | `test_mr_rotor`: static point equals the airplane `thrust_torque` oracle and identified c_t within fit residual; shared-kernel known answers and branch continuity over the declared range; positive/negative axial-flow and coordinate-sign covariance cases; H-force reduces to the linear law at small μ within 5 %; Cheeseman–Bennett cross-check for z/R > 0.6; timestep-refinement comparison of dynamic and steady inflow. No drone-specific smoothing or fitted VRS curve |
| DR-05 | `multirotor/powertrain.gd`: N motors on one pack, `synchronous` and `ideal_motoring` ESC kinds, shared-bus closed form with active-set passes, rotor ODEs, idle floor and output limit; EL battery kernels reused (EL owner review) | Bus solve equals a brute-force root to 1e-12; energy closure ∫(P_elec − P_loss − P_shaft)dt = ΔE within 1e-6 relative over 10 s; braking current sign and pack charge accounting; single-motor case byte-identical to `electric_supply.gd` |
| DR-06 | `multirotor/airframe.gd` (three-axis quadratic drag) and N-rotor parallel `RotorCoupling` (signed momentum, inertial yaw, simultaneous relative-spin solve) | Momentum and work closure (extends `test_rotor_coupling`); airplane path byte-identical |
| DR-07 | `multirotor/fc.gd`: rates (actual, betaflight), modes (acro, angle, horizon), rate PID + FF with low-pass states, quad-X mixer with air mode, idle and output limit, arming/disarm/failsafe logic, link ring buffer; pure functions over an aux slice | Rate curves pinned to the documented examples (7/67/54 → 70/670 deg/s with expo); mixer reproduces the documented saturation examples; hover step responses vs the DR-03 240 Hz model to 1e-9; no code copied from GPL firmware (review) |
| DR-08 | Betaflight `diff rates` importer (`research/drone-racing/tools/import_rates.py` and the GDScript parser) → `openrc-rates v1` with warnings for ignored lines | Round trip on a real dump; ignored PID lines listed; rejected malformed input |
| DR-09 | `bench_multirotor.gd`: per-call kernel cost; explicit-step ratio from actual J, R_m, K_v; h/h2/h4 refinement at a full-throttle punch, throttle chop and axial-flow transition | ≤ 25 µs per full evaluation (100 µs per tick) on the H15 host, or stop and redesign before integration; qualified motor and inflow timestep treatment recorded with the data |

### Phase 2: data

| ID | Work | Proof / status |
| --- | --- | --- |
| DR-10 | `openrc-multirotor v1` spec, generated schema and `multirotor_data.gd` (validation, derivation, identity); shared kernels extracted only if needed | Invalid-data suite (missing, extra, wrong unit, null, out of range, rotor count/positions inconsistent, CG/inertia inconsistent, idle above limit); airplane loader untouched or byte-identical |
| DR-11 | Reference quad source table and generator `research/drone-racing/<quad>/derive.py --check` → `app/data/aircraft/<quad-id>.json`; static calibration of a_l and the drag law against the identified c_t/c_q | Every row cites its table with its kind; fit residual printed; `--check` in `test.sh` |
| DR-12 | Race build configuration: 5-inch 4S/6S build from a named bench dataset (static points `borrowed`, inertia and drag `estimated`) as a second file | Same generator with a second source table; comparison of the two static curves in the report |
| DR-13 | Contract text: multirotor section in AIRCRAFT_CONTRACT (with the AS owner); `openrc-track v1` and `openrc-rates v1` documented in the contract or a track guide | Reviewed diff |

### Phase 3: controls

| ID | Work | Proof / status |
| --- | --- | --- |
| DR-14 | Input semantics: four sticks as controller inputs, no-centre throttle calibration, `modes` for arm and flight mode, keyboard/gamepad keys, optional switch/button mapping in calibration (shared with HELI-14 / SM-03), failsafe → drop | Input tests; existing airplane input traces byte-identical; key-clash check; fake-radio button and axis-switch tests |
| DR-15 | Rates file selection: `--rates-file=`, `user://rates/`, trace metadata identity; gamepad expo disabled for multirotors | Trace metadata test; a loaded profile changes the setpoint curve and nothing else |

### Phase 4: session integration

| ID | Work | Proof / status |
| --- | --- | --- |
| DR-16 | `multirotor/loads.gd` joint evaluate; the single `FlightSession` seam selecting it and the controller `_pre_step` | All airplane goldens, traces and fps-determinism byte-identical |
| DR-17 | State layout (continuous/aux/modes), reset, checkpoint format, restore whitelist, `MR_COLUMNS`, metadata schema, replay classes; golden recorder extended to coupled continuous tails | Checkpoint round trip; replay within declared tolerances; 30/60/144 fps determinism for the quad; an electric airplane golden records and replays |
| DR-18 | Hover equilibrium and pad start (static solve on four legs generalizing `ground_start.gd`); `_prepare_aircraft` branch; hover start route for tests | Hover residual < 1e-9; pad rest on 0–10° slopes; arming spins to idle without lift-off |
| DR-19 | Leg contact mode (isotropic regularized Coulomb + anchors, with the ground track; shared with HELI-19) and rotor-disc clearance rings against terrain and proxies (shared with HELI-21) | Slide threshold = μ; tip-over fixture on a slope; prop strike on a tilted touchdown, on a post and on a tree proxy; stopped rotors ignore the ring |
| DR-20 | Crash and respawn: disarm on crash, pad respawn, last-gate respawn, lap marking | Fixtures per cause; respawn pose on terrain; trace continuity |
| DR-21 | **Controller fidelity gate:** closed-loop roll, pitch and yaw step and doublet responses of the 240 Hz implementation against the DR-03 8 kHz reference on the same plant; equivalent gains recorded in the data with the comparison | Rise time and overshoot within ±15 %, settling within ±20 %, or re-tune and re-run; result filed under `docs/research/drone-racing/DR-21/` |
| DR-22 | Integrated cost (Gate P rule) and long-run stability: 10 minutes of scripted laps, punch-outs, descents and pad cycles | p50/p95 per regime; no nonfinite state; no sticky fault; pack exhaustion ends cleanly |

### Phase 5: race mode

| ID | Work | Proof / status |
| --- | --- | --- |
| DR-23 | `openrc-track v1` loader/validator, element library dimensions, `app/data/tracks/strip-sprint.json` | Invalid-track suite (unknown element, sequence referencing a missing gate, overlapping pads, gate below terrain); `--check` of authored tracks in `test.sh` |
| DR-24 | Track proxies in the collision world (`race_frangible`, flags soft) and the world identity including the track hash (scenery owner review) | Collision tests: bump below threshold, terminal above, prop strike on a post; checkpoint refuses a different track |
| DR-25 | `sim/race/director.gd`: CG plane-crossing detector with sub-tick time, sequence rules, start procedures, states, min lap, `RACE_COLUMNS`, checkpoint block | Crossing time error < 0.1 ms on synthetic segments at 10–50 m/s; direction and missed-gate rules; a replayed trace reproduces the lap list exactly; director cost ≤ 15 µs/tick |
| DR-26 | Results store, direct route `--race=<track-id> --laps=`, finish summary (pause menu text first; menu track owns the panel) | Round trip; automation never touches `user://races/`; en/es strings |
| DR-27 | Ghost recording and replay (presentation) | Trace identity with the ghost on; capture of a ghost lap |
| DR-28 | `gq-style` and `pad-free` tracks; GQ coordinates from DR-02 | Captures from the pilot station and a 60 m fly-by; element clearance checks against the FAI minimum diameters |

### Phase 6: presentation

Steps DR-29, DR-30 and DR-32 can start in parallel with Phase 1 because their file boundaries are disjoint.

| ID | Work | Proof / status |
| --- | --- | --- |
| DR-29 | Visual generator, node contract, verify script, **catalog PREVIEW** | `verify_<quad>.gd`; catalog test updated (counts, span rule replaced by wheelbase for multirotors); Home preview on the pad |
| DR-30 | Propeller blur for N rotors with per-rotor rpm and spin (visual-quality owner review) | Stopped state byte-identical for every airplane; four-disc rpm sweep captures front/quarter/top; disc density matches the coverage law |
| DR-31 | FPV view as an `fpv` mode of the CAM-02 rig (camera owner): camera mount from data, uptilt, FOV conversion, 4:3 option, near/far per CAM §4.3, frame-delay buffer; OSD overlay O8 (overlays owner) | Captures at 100/120/137° horizontal FOV; OSD fixtures per field and warning; trace identity with FPV on; cost on the owner's host |
| DR-32 | Track visuals (gates, flags, hurdles, pads, LED emissives for evening/night) | Captures day/evening/night; draw-call and GPU budget on the owner's host |
| DR-33 | Audio layers for four motors (audio owner) | Spectrum checks of shaft, blade-passing and commutation lines per rpm; Doppler sweep; owner listening review |
| DR-34 | Prop-wash grass response via the shared wash field; particles only after the Compatibility probe | Zero thrust → zero wash; captures at 0.2/0.5/1 m hover; cost |
| DR-35 | Line-of-sight HUD fields and warnings; race HUD; es strings | Overlay fixtures; 720p/1080p captures en/es |
| DR-36 | **Catalog EXPERIMENTAL**: Fly enabled with the "experimental" warning; Home race entry (menu track: track, laps, rates profile, view) | Every route trims and flies; export smoke loads the quad and a track |
| DR-37 | Crash semantics with CR-01d labels and causes; wreck groups; respawn text | Fixtures per cause; crash card shows cause |

### Phase 7: acceptance and growth

| ID | Work | Proof / status |
| --- | --- | --- |
| DR-38 | **Model-to-data comparison (held-out):** feed the dataset's recorded motor speeds and body velocities into the rotor/airframe model and compare predicted forces and torques with the dataset's ground truth; speed/pitch bucket vs the identified rotor-drag model; motor lag vs the identified time constant; report whether held-out records cover negative axial flow or VRS | Report in `docs/research/drone-racing/DR-38/`; tolerances §11; if VRS is absent from the held-out data, label the small-prop VRS prediction unvalidated and reserve physical validation for DR-40 |
| DR-39 | Owner race session (Gate DR-P, §11) | Ratings, lap results and traces in `docs/research/drone-racing/DR-39/` |
| DR-40 | Physical data, if the owner or a contributor has a quad: Betaflight blackbox logs (gyro, setpoint, motor outputs, voltage, current), weight/CG via VAL-5, bench thrust via VAL-7, lap times on a real 5×5 course | Measurements with uncertainty; held-out comparison; the race build re-estimated from measured hardware |
| DR-41 | Later: turtle mode (bidirectional rotation), Freedom-Spec rpm cap and 6S/7-inch Pro-Spec class, whoop gates and ducted rotor data, BEMT tables from measured prop geometry, rotor–frame interaction, in-app track editor, shared ghosts | Separate plan revision |

**Parallel lanes** (one agent per lane, each with disjoint files):

| Lane | Steps | Files |
| --- | --- | --- |
| A | DR-03 | `research/drone-racing/reference/` |
| B | DR-04…09 (after HELI-04's interface and reference tests settle) | `app/physics/multirotor/`, `app/tests/test_mr_*.gd`, `bench_multirotor.gd`; consumes but does not own `app/physics/rotorcraft/inflow.gd` |
| C | DR-10…13 | `app/physics/multirotor_data.gd`, `app/data/schema/openrc-multirotor-v1.*`, `research/drone-racing/<quad>/` |
| D | DR-23, DR-25…27 | `app/sim/race/`, `app/data/tracks/`, `app/tests/test_race_*.gd` |
| E | DR-29, DR-32 | `assets/aircraft/<quad-id>/`, `app/aircraft/<quad>_*`, `app/render/track/` |
| F | DR-31, DR-33 | coordinated with CAM, HUD and AUD owners |

Integration steps (DR-14…22, DR-24, DR-30) are serialized with the main line and their owners.

**Order:** HELI-04 owns the first shared inflow implementation, which remains under source-law and reference-vector review. DR-00 registration/scope and DR-01 are complete; after DR-02/03 research and the HELI-04 gate, DR-04…09 may consume the stable contract (with DR-29/32 presentation work in parallel). Reference-aircraft, controller and racing product choices remain provisional. Then DR-10…13 → 14/15 → 16 → 17 → 18 → 19 → 20 → 21 → 22 → 23 → 24 → 25 → 26 → 30 → 31 → 35 → 36 → 27 → 28 → 33 → 34 → 37 → 38 → 39 → 40.

## 11. Acceptance

| Level | Criterion |
| --- | --- |
| Software verification | Kernel known answers (§10). The GDScript model equals the independent DR-03 model within 1e-6 relative over 5 s of scripted inputs. Airplanes byte-identical. 30/60/144 fps determinism. `test.sh` green. |
| Controller fidelity (DR-21) | Closed-loop step and doublet responses within ±15 % rise and overshoot and ±20 % settling of the 8 kHz reference on the same plant; the equivalent gains and the comparison are filed with the data. |
| Model-to-data (held-out, DR-38) | Replaying the NeuroBEM motor speeds and body states through the rotor and airframe model, the force and torque RMSE over the unseen flights must beat the published quadratic-model baseline (1.49 N, 0.087 N·m) and approach the published blade-element result (0.98 N, 0.074 N·m); hover thrust within ±10 %; the residual is reported against speed (rotor–frame interaction dominates above ≈ 15 m/s and is reported, not hidden). Emergent motor lag within ±30 % of the identified 33–39 ms. |
| Emergent behaviour (scripted fixtures) | Each must appear with its declared cause: hover throttle ≈ 30 % of max rpm at thrust-to-weight ≈ 9; ground-effect lift-off below the hover throttle within 1R of the pad; predicted loss of mean rotor thrust and increased sink in the Johnson VRS region at low forward speed, with recovery trend as forward speed rises; no claim of stochastic roughness without an unsteady model or data; loss of authority at full throttle (mixer saturation flag) and its return with air mode at zero throttle; nose-up and deceleration on stick release at speed (H-force and hub moment); yaw authority from inertial reaction; bus sag of ≈ 1 V on a punch-out at 100 A; faster deceleration with `synchronous` than `ideal_motoring` on a throttle chop; pack exhaustion ending the flight. |
| Race logic | Lap times reproduce to the millisecond under replay; a missed gate invalidates the lap; false starts restart; results persist; GQ-style laps land in the 10–20 s band for the authored course (a sanity range, not a target). |
| Performance | ≤ 100 µs rotor/airframe, ≤ 60 µs powertrain, ≤ 15 µs race per tick and ≤ 500 µs whole tick (H15 host, median). FPV view and OSD ≤ 1.0 ms p95 added frame time at 1080p on the owner's host; track visuals ≤ 0.5 ms. 60 fps p95 maintained. |
| Gate DR-P (pilot) | The owner, and ideally an experienced FPV racer, flies with a radio and imported rates: 60 s hover in a 2 m box in angle and acro; a punch-out and a dive; three clean laps of `strip-sprint`; a GQ-style session. Per-axis ratings −2…+2 against a real 5-inch quad, FPV readability of gates at 30 m, OSD legibility, disc/sound realism notes, and lap times against the pilot's real or Velocidrone/Liftoff times on a comparable course. |
| Physical validation | Only DR-40 measurements count. Software checks, dataset comparisons and other simulators do not establish physical realism for any built quad. |

## 12. Decisions for the owner

| ID | Question | Recommendation |
| --- | --- | --- |
| D1 | Admit multirotors as a third vehicle class and racing as the first game mode? | **Yes**, as an isolated track whose integration keeps airplanes byte-identical; record the scope extension in DECISIONS |
| D2 | Reference aircraft | **The identified ETH/UZH research quad (Agilicious/NeuroBEM data)** first, because it is the only 5-inch class platform with validated forces; a **named 5-inch race build** from bench data second (DR-12), labelled estimated |
| D3 | Controller fidelity | **Betaflight-equivalent discrete controller at 240 Hz**; rates imported one to one; PID gains simulator-owned equivalents qualified by DR-21. Alternative: a fixed "sim feel" with no import (rejected: pilots judge a sim by their own rates) |
| D4 | Race rules default | **MultiGP-style**: ground start on pads, tone start, gate sequence with missed-gate re-attempt, 3 laps; GQ scoring (best three consecutive laps in 120 s) for the qualifier track; FAI "arm your quads" tone as the alternative procedure |
| D5 | Data format | **Sibling `openrc-multirotor v1`** sharing the v2 rules and kernels; `vehicle: "multirotor"` |
| D6 | Input and beginner aid | **Four sticks; arm and mode as switches/keys; keyboard defaults to angle mode** (real firmware feature), radio and gamepad to acro. No invented stabilizer |
| D7 | Default view for the quad | **FPV in race routes, pilot view in free flight**, C cycles between them; listener at the pilot station in both (goggles carry no onboard audio) |
| D8 | ESC law | **Add the `synchronous` (bidirectional current) ESC kind** with the EL owner; keep `ideal_motoring` selectable for comparison |
| D9 | Track authoring | **Data tracks only** (three authored JSON tracks); an in-app editor is DR-41 |
| D10 | Visual asset source | **Procedural generator** from the data file's dimensions; a GLB with manifest if the owner supplies one |
| D11 | Betaflight import scope | **Rates, expo, throttle limits, idle, motor limit, angle limits**; PID/filter/feed-forward lines ignored with a warning |
| D12 | LEDs and night racing | **Yes**: emissive gate strips and arm LEDs in evening/night, after the field-world owner reviews the glow pass |
| D13 | Order against the helicopter track | **Helicopter first for shared rotorcraft kernels:** HELI-04 owns the initial inflow implementation and reference vectors; DR-04 consumes that stable contract. Contact, input and disc-clearance seams keep their own named owners and acceptance steps. |
| D14 | Latency modelling | **RC-link delay as a declared data field (default 1 tick, estimated)**; **video frame-delay buffer available with cited presets (analog ≈ 19 ms, HDZero ≈ 15 ms, DJI ≈ 30 ms), on in FPV race routes at the analog value**, off in captures; never presented as a link model. Alternative: off everywhere until DR-39 |

## 13. Risks

| # | Risk | Mitigation |
| --- | --- | --- |
| R1 | The 240 Hz controller cannot reproduce the feel of an 8 kHz loop | DR-03 reference at both rates; DR-21 fidelity gate with declared tolerances; rates imported exactly; the record states what is equivalent and what is not |
| R2 | No forward-flight data for 5-inch racing props; blade-element constants are fitted at the static point | Held-out NeuroBEM-style comparison (DR-38) with the residual reported against speed; BEMT tables from measured geometry as the declared upgrade (DR-41) |
| R3 | Explicit-step ratio of small motors at 240 Hz | DR-09 measures J and R_m, refines h/h2/h4 and qualifies the ratio per configuration; no blanket relaxation of the airplane's 0.25 |
| R4 | GDScript cost | Closed-form kernels, scalarized; DR-09 stops integration if over budget; a native kernel is a separate decision under Gate P |
| R5 | Handling dominated by estimated controller gains | DR-21 ties them to a reference loop; separate airframe validation (DR-38) from controller tuning; pilot rating with the pilot's own rates |
| R6 | GPL-3 contamination from Betaflight, INAV, ArduPilot or Liftoff/Velocidrone reverse-engineering | Implement from documentation and published mathematics; cite; never copy code; review in DR-07 |
| R7 | Churn in main-line files (`flight_session.gd`, `simulation.gd`, `main.gd`) | One callback seam, one controller seam, one camera seam; byte-identity proofs; serialized integration steps |
| R8 | Gate collisions read as wrong (a real quad tumbles, breaks a prop or bounces off mesh) | Frangible class with declared thresholds; prop strike through the disc ring; thresholds labelled estimated and reviewed in DR-39 |
| R9 | FPV wide FOV cost and depth precision on the owner's GPU; the VM proves pixels only | CAM §4.3 near/far per mode; measured on the owner's host in DR-31; rectilinear default, warp optional |
| R10 | Keyboard pilots cannot fly acro and judge the quad broken | Angle mode default for the keyboard; recommended gamepad/radio; honest labelling |
| R11 | Compatibility particle limits; captures lose particle history | Shared probe first (SM-00/HELI-28); pure-function wash laws; xvfb captures with prewarm |
| R12 | The identified research quad is heavier and slower than a race build | Name the configuration; race build as the second file with labelled estimates; pilots choose |
| R13 | Scope creep (turtle mode, whoops, long range, multiplayer, editor) | Non-goals in §4.13; each needs its own revision |
| R14 | Two rotorcraft tracks need the same shared kernels | HELI-04 owns the first inflow implementation; DR consumes it without editing the shared file and adds consumer conformance tests. Other shared seams get an explicit owner and acceptance when their steps start. |
| R15 | Firmware defaults and rate maths change between releases; commercial sims are not ground truth | Pin the firmware commit and version in the data's `source`; test the curves against the pinned documentation; never cite another sim as validation |
| R16 | Perceived responsiveness is latency-dominated; a sim without video delay feels "too fast" and the aerodynamics get blamed | D14 frame-delay buffer with cited presets; DR-39 rates feel with and without it |

## 14. Open questions

1. Does the owner fly or own an FPV quad (frame, motors, props, pack, firmware, radio and goggles)? That decides DR-40, the race build (DR-12) and whether the owner's own `diff rates` is the first imported profile.
2. Should the first flyable build ship the identified research quad or wait for the race build so that the first impression is a race-weight 5-inch?
3. Should racing be allowed on the airplane field's mown strip by default, or does the owner prefer a dedicated gate area east of the strip (the GQ grid needs 45 × 30 m)?
4. Does the held-out NeuroBEM data cover negative axial flow or VRS? If not, DR-38 must leave the small-prop VRS prediction unvalidated until physical data are collected under DR-40.
