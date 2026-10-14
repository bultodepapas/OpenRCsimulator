# RC monster truck: physics laboratory and playable vehicle

**Date:** 2026-10-14. **Status:** Bisonte MT8 is integrated as an experimental ground activity with a garage, suspension/steering articulation, recording and laboratory controls. The production start is the shared aircraft runway; a dirt obstacle circuit now occupies that airfield in the RC activity ([track evidence](../research/rc-monster-truck/RCV-track/README.md)). Synthetic practice terrain remains a research/test fixture. Earlier focused runtime and native Windows RC-only package checks passed; the 500 µs, physical, hardware and full application release gates remain open. **Owner:** RC ground-vehicle track. **Prefix:** RCV-00…RCV-34, registered in the [ownership index](../README.md#tracks-plans-and-step-ids). **Evidence:** [source investigation](../research/rc-monster-truck/README.md), [RCV-04a](../research/rc-monster-truck/RCV-04a/README.md), [RCV-04b](../research/rc-monster-truck/RCV-04b/README.md), [RCV-14a](../research/rc-monster-truck/RCV-14a/README.md), [runtime verification](../research/rc-monster-truck/RCV-runtime/README.md). The [operating and research guide](../../research/rc-monster-truck/README.md) owns runnable commands.

This plan adds one large RC monster truck as another selectable vehicle in OpenRC Simulator. It has two equally important uses: expose physical behavior through repeatable experiments, and provide enjoyable driving, jumps and recovery. The same physical model serves both. A successful numerical experiment does not establish real-truck accuracy, and an attractive jump does not establish correct mechanics.

Repository documents are in English under [the documentation conventions](../README.md#conventions-for-documents). The future player interface must work in English and Spanish. The complete letter for the Blender developer is in [section 13](#13-letter-and-delivery-contract-for-the-blender-developer); it is a handoff draft, not a message sent to anyone.

## 1. Recommended scope

The [RCV-09-R2 handling revision](../research/rc-monster-truck/RCV-handling/README.md) extends the first drive revision with a corrected combined-friction solve, explicit axle brake allocation, power/launch tuning, disturbed-braking and skid comparisons, and track-sampler optimization. It retains the aircraft-runway start and the circuit on that airfield. Physical calibration, extreme steering/experiment envelopes and target-hardware performance qualification remain open.

Build a fictional **1/8-class, four-wheel-drive monster truck**, with the high-clearance stance, exposed suspension and large tires that motivate the user's Traxxas T-Maxx reference. The developer should first search for a suitable freely downloadable model and components with a usable redistribution license, then adapt them. Do not commission a complete new mesh before that audit. Do not imply this is an official Traxxas product or a calibrated replica.

The T-Maxx reference and the requested scale must remain separate: the manufacturer's T-Maxx 3.3 is a **1/10-scale nitro truck**. Its dimensions and mechanisms are reference evidence, not a specification for a 1/8 model. Do not enlarge its mesh by 1.25 and silently reuse its mass, suspension, inertia, gearing or handling. The visual developer proposes the final physical dimensions at RCV-02; the physics owner accepts a separate, sourced mass and mechanism inventory. [Manufacturer sources and limits](../research/rc-monster-truck/README.md#manufacturer-reference).

Implemented first powertrain: **estimated electric 4WD**, explicitly described as an experimental fictional configuration. It provides drive torque, braking and reverse. The owner authorized implementation of the plan and confirmed that the supplied model/scripts are original and authorized for inclusion and modification. Nitro sound or an exhaust plume must not stand in for electric mechanics. A T-Maxx-like nitro installation remains a later, separately identified configuration requiring clutch, gearing, idle/stall and brake evidence.

| Delivery | Player experience | Physical claim permitted |
| --- | --- | --- |
| P0: inspectable preview | Select the truck, rotate it, inspect the suspension and see its experimental status | Asset and coordinate contract only; Drive disabled |
| P1: first drive | Accelerate, brake, reverse and steer on a flat pad; move between rigid surfaces | Verified rigid chassis, rotating wheels, basic suspension and tire forces; parameters provisional |
| P2: off-road play | Cross bumps and grass, jump a ramp, land, roll onto the roof and recover manually | Qualified contact, suspension travel, wheel/body momentum and nonterminal rollover within a stated envelope |
| P3: physics laboratory | Run repeatable braking, suspension, CG, slope, material and jump experiments; compare A/B results | Numerical verification plus explicitly listed physical measurements; unmeasured regimes remain experimental |
| P4: polished release | Clear menus, comfortable camera, readable truck, useful lessons, convincing audio and packaged assets | Target-machine performance and user acceptance; physical validity still bounded by the evidence |

P1 is an early milestone, not completion of the user's request. P2, P3 and P4 are required for the intended combined laboratory/game. No multiplayer, deformable body destruction, tire FEM, granular soil, full CAD editor, new rendering engine or full-scale vehicle model is required for the first release. Water driving, mud excavation and moving debris are later capabilities; the first truck must state that they are unsupported.

## 2. Fit with the repository

### 2.1 Current implementation and useful boundaries

The audit began at `fe4891bdccb8acff7e00975234a0d94106ef63c9` with unrelated working-tree modifications. Several owners continued changing the tree during research. Code discovery used the existing MCP graph, then current source reads because some stored symbol ranges were stale. Recheck shared files before implementation; neither old plan summaries nor graph line numbers override live code.

| Existing seam | What is present | Integration consequence |
| --- | --- | --- |
| [project.godot](../../app/project.godot), [engine pin](../../app/get-godot.sh) | Godot 4.7.2, Compatibility renderer, 240 physics ticks/s, at most 12 catch-up steps/frame | Keep the engine and airplane tick behavior. No engine upgrade bundled with this track |
| [rigid_body.gd](../../app/physics/rigid_body.gd), [integrator.gd](../../app/physics/integrator.gd) | Scalar/packed-float64 rigid-body mechanics and RK4 | Reuse verified algebra and integrator machinery; a new vehicle load law is required |
| [simulation.gd](../../app/sim/simulation.gd) | Body state, sampled auxiliary state, discrete modes, continuous suffix state and transactional ticks | Candidate substrate for the truck; qualify its event, mass and joint-response assumptions before adopting |
| [flight_session.gd](../../app/sim/flight_session.gd) | Aircraft loading, forward-flight trim, controls, start/reset, holds, crash, checkpoint and identity policy | Add a separate ground-vehicle session; do not bypass airplane validation with invented wing data |
| [ground_wheels.gd](../../app/physics/ground_wheels.gd), [ground_terrain.gd](../../app/physics/ground_terrain.gd) | Per-wheel slip, grip limit, rolling loss, spin, spring/damper normal contact and terrain sampling; aircraft gear remains attached to one body | Reuse tested low-level laws where contracts match. Add vehicle suspension kinematics/dynamics, drivetrain and finite-wheel obstacle contact |
| [aircraft_catalog.gd](../../app/app_state/aircraft_catalog.gd) | Seven configurations across five airframes in the inspected tree; airplane-specific flyable entry loops | Introduce a product-level vehicle facade; leave aircraft enumeration and its tests aircraft-specific |
| [app_root.gd](../../app/app_root.gd), [home.gd](../../app/ui/home.gd), [home_scene.gd](../../app/ui/home_scene.gd) | Home chooses an aircraft and constructs `main.tscn`; preview, scene lifecycle and errors are aircraft-specific | Add explicit family dispatch and a truck preview builder; changing the button label alone is insufficient |
| [screen_stack.gd](../../app/ui/screen_stack.gd), [pause_menu.gd](../../app/ui/pause_menu.gd) | Named menu holds, input isolation and focus restoration | Reuse lifecycle through a small adapter with tested hold/release/restart semantics |
| [preferences.gd](../../app/app_state/preferences.gd), [controls_reference.gd](../../app/ui/controls_reference.gd) | Validated settings schema 4 and flight-specific action labels | Add a vehicle selection/mode section and vehicle-specific controls while preserving existing saved flights |
| [camera_rig.gd](../../app/render/camera/camera_rig.gd), [chase_view.gd](../../app/render/camera/chase_view.gd) | Pilot, chase, orbit and close-up; chase tuning uses wingspan and a ground-height callback | Reuse the rig, add a truck profile and obstacle-aware camera clearance. FPV is not an existing completed mode |
| [frames.gd](../../app/render/frames.gd) | NED/FRD to Godot Y-up boundary and CG-to-visual-root offset | Reuse the mapping; provide a truck datum instead of a wing leading-edge convention |
| [crash presentation](../CRASH-DAMAGE-PLAN.md) | Aircraft impact policy and a separate wreck presentation path | A rolled truck stays under authoritative truck physics. A visual wreck must not replace ordinary ground dynamics |
| [field/ground evidence](../research/ground-physics/GP-05/README.md), [landscape guide](../LANDSCAPE-PLAN.md#landscape-integration) | Shared surface regions and small analytic relief; visual grass/hills are not equivalent to drivable terrain | Author explicit physical obstacles and make close-range geometry agree with them |
| [collision_world.gd](../../app/scenery/collision_world.gd), `build`, `nearby` | Immutable scalar N/E/down obstacle inventory, stable IDs, bounded spatial bins and identity hash | Reuse the existing obstacle inventory/broadphase where compatible; it does not itself provide sustained truck contact response |

The [helicopter](helicopter.md), [drone](drone-racing.md) and [Aircraft Workshop](aircraft-editor.md) tracks touch the same session/catalog/menu seams. None is a prerequisite for driving the truck. Coordinate a shared family discriminator and shell adapter once; do not create three competing vehicle factories or wait for all those products. Workshop files and hooks appeared in the working tree during this audit: do not assume that track is absent just because its plan says proposed.

### 2.2 Ownership

Proposed owned paths, created only as their steps land:

| Path | Purpose |
| --- | --- |
| `app/physics/ground_vehicle/` | Truck data validation, load evaluation, suspension, tires, drivetrain, contacts and supported state layout |
| `app/sim/ground_vehicle/` | Session, starts, checkpoint envelope, truck trace and experiment protocol |
| `app/vehicles/ground/` | Truck scene/controller and visual builder; separate from airplane model builders |
| `app/ui/ground_vehicle/` | Drive mode, laboratory and truck-specific help/telemetry screens |
| `app/data/vehicles/ground/`, `app/data/schema/openrc-ground-vehicle-v1.*` | Generated accepted truck parameters and strict schema |
| `app/data/ground_vehicle/` | Course/experiment definitions; referenced shared material data retains the ground owner's contract |
| `assets/vehicles/<truck-id>/`, `app/assets/vehicles/<truck-id>/` | Authoring sources/provenance and runtime GLBs/textures respectively |
| `app/tests/test_rcv_*.gd`, `app/tests/bench_rcv.gd` | Truck-specific numerical, session, UI, asset and cost checks |
| `research/rc-monster-truck/`, `docs/research/rc-monster-truck/` | Generators/reducers/fixtures and dated source/measurement evidence |

Coordinate changes to `app_root.gd`, `app_state/`, `ui/`, `i18n/es.po` with UI; `simulation.gd`, the integrator and input hardware with the main physics owner; ground/material/field contracts with GP/LU/FW; cameras with CAM; overlays with HUD; electric kernels with EL; audio with AUD; collision/wreck policy with CR. `app/main.gd` remains the airplane integration path unless a separately reviewed shared extraction proves parity.

No rename of `airplane`, `propeller` or any aircraft hinge. No edits to generated aircraft JSON or geometry. No unrelated dirty-file cleanup. Stage only the implementing step's files. Inspect the whole repository for old-path references before any later move or rename.

## 3. Architecture decision and alternatives

Recommended authority: a **custom float64 truck simulation**, connected to Godot presentation at the same boundary as aircraft. Prefer reuse of the existing mathematical kernels and downloadable reference implementations over writing equivalent foundations again.

| Option | Benefit | Limitation for this task | Disposition |
| --- | --- | --- | --- |
| Godot `VehicleBody3D`/`VehicleWheel3D` | Fast downloadable/demo-based first drive | Official 4.7 documentation describes known limitations for realistic vehicle simulation; ray-based wheels and engine-body state do not meet this repo's laboratory contract | Use a disposable comparison if helpful, never call it validation of the custom truck |
| Godot rigid bodies and joints | Convenient collision and mechanism prototyping | Official-build vector/body state is not the project's scalar float64 state; adopting a second authoritative solver changes replay, checkpoints and force observability | Optional external reference experiment, not the proposed production path |
| Jolt vehicle implementation | MIT code, wheel-shape collision alternatives and differential/vehicle machinery | Its large-world double mode does not make velocities, rotations and all calculations double precision; direct adoption is a deliberate architecture change | Reuse ideas or licensed bounded algorithms after review; keep a comparison candidate if custom contact proves impractical |
| Project Chrono | Existing vehicle, suspension, tire and terrain implementations suitable for research | Native dependency, packaging and real-time cost need qualification; stock full-size tire values are not RC measurements | Optional offline reference, with exact version/build/data pinned before use |
| Existing OpenRC float64 core plus truck modules | Preserves scientific state, source identity, test culture and existing exports | Requires explicit coupled mechanics and contact qualification | Recommended, subject to RCV-04/10 performance and numerical gates |

Sources: [Godot 4.7 vehicle](https://docs.godotengine.org/en/4.7/classes/class_vehiclebody3d.html), [Godot precision](https://docs.godotengine.org/en/4.7/tutorials/physics/large_world_coordinates.html), [Jolt architecture](https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md), [Chrono tire models](https://api.projectchrono.org/wheeled_tire.html). These support the comparison; the production choice is this plan's recommendation, not a conclusion proved by those projects.

### 3.1 Additive session and catalog integration

Proposed composition:

```text
Home / shared screens
  -> VehicleCatalog facade: family, ID, status, capabilities, presentation
      -> existing AircraftCatalog -> existing main.tscn / FlightSession
      -> GroundVehicleCatalog     -> GroundVehicleScene / GroundVehicleSession

GroundVehicleSession
  -> validated model + environment + input profile + scenario identity
  -> fixed-tick transaction
      -> float64 body / wheel / suspension / drivetrain states
      -> terrain and obstacle queries -> joint loads and derivatives
      -> committed contact / mode / lesson events
  -> detached render snapshot / recorder / diagnostics
      -> model articulation, CameraRig, audio, truck HUD
```

`VehicleCatalog` must expose stable family/ID keys, status (`preview`, `experimental`, later qualified), data/model references, supported starts, input profile, camera profile and supported product modes. It contains no mass, friction or spring values. Keep `AircraftCatalog.flyable_ids()` unchanged; adding a truck must not make airplane trim, fleet model or golden-flight loops load it.

Add the truck scene beside `main.tscn`; avoid copying the entire airplane controller. Extract only services required by both scenes, one behavior-preserving change at a time. If field composition must be shared, first wrap the existing construction order and prove existing scene/lighting/collision parity. A truck can consume current field modules without making the whole app vehicle-generic.

The shell adapter's minimum contract must be proven against actual callers: startup result; scene/session lifetime; pause request; `hold(reason)`/`release(reason)`; explicit resume; reset; raw-input reader and held-key mask; recording save/discard result; detached presentation status; capability queries for conditions/help/overlays. `ScreenStack` already accepts a `Node` and depends only on hold/release; preserve it. Put the adaptation in the activity host and pause profile: current `PauseMenu` reads `is_flyable`, `pause_reason`, `crash` and `crash_auto_restart`, while `app_root` calls calibration and airplane overlay/workshop methods. Do not add fake aircraft properties or no-op trim/calibration APIs to the truck merely to satisfy those callers. Release of a hold does not imply resume. Invalid preparation cannot produce a half-initialized playable session. On a rejected interactive start, restore the previous Home preview, camera, focus and message.

The first truck may reuse `Simulation` only if its callback and transaction contracts can carry the selected mechanical model. Do not force a variable-mass-matrix suspension into the fixed-inertia rigid-body derivative by adding a few suffix states. RCV-04 qualifies a dedicated generalized-state integrator adapter if needed, while leaving the aircraft path intact.

### 3.2 Schema and model identity

Create `openrc-ground-vehicle v1` rather than weakening `openrc-aircraft v2`. Reuse quantity/provenance and inertia-validation helpers only where they are already vehicle-neutral or can be extracted with exact airplane parity. Validate JSON with the repository's schema tooling and the runtime loader; neither alone substitutes for the other.

Required modules:

| Module | Required content and rejection rules |
| --- | --- |
| Identity | Format/version, stable ID, revision, mechanism model IDs, source inventory and capability declarations; unknown fields/modules refused |
| Geometry | One datum, wheelbase, front/rear track measured between wheel centers, tire radius/width, hub coordinates, suspension hardpoints, chassis contact proxies; finite SI values |
| Mass | Sprung components, unsprung components and rotating inventory; mass, CG and positive-definite physically realizable inertia; no component counted twice |
| Suspension | Kinematic model, travel limits, ride height/preload, spring curves, compression/rebound damper curves, motion ratios, bump/droop stops; no impossible geometry or negative dissipative damping |
| Tires | Loaded/unloaded radius, spin inertia, vertical compliance, longitudinal/lateral grip/relaxation model, rolling loss, applicability ranges and matching surface profile IDs |
| Steering | Input convention, steering range and rate, left/right mapping, servo model and mechanical limits; rear steering absent unless declared |
| Drivetrain | Electric or nitro installation, ratios, efficiency/loss model, shaft inertias, front/rear and axle differential types, brake/ESC/reverse modes; mutually exclusive capabilities enforced |
| Contact | Wheel/chassis proxy sets, contact stiffness/damping or solver specification, friction rules, supported obstacle classes and operating envelope |
| Presentation bindings | Model manifest identity, articulation/mount names and camera/audio anchors; no render classes in physical state |
| Validation | Valid input/temperature/load/speed domains, estimated parameters and source limitations; no fabricated default for an essential missing value |

Each physical quantity carries `{value, unit, kind, source}`. A proposed extension for uncertainty/range belongs in this new schema or its source record; do not inject unsupported keys into aircraft v2. Reuse the current vocabulary `manual`, `measured`, `derived`, `borrowed`, `estimated`; manufacturer publications use `manual` with an identified OEM document in `source`. Do not add an unsupported `manufacturer` enum to a reused validator. Freeze allowed vocabulary at RCV-03.

A manifest fingerprints original input bytes, source/generator version, derived normalized model, materials, physical course, solver settings and imported visual asset. A model hash and an asset hash are separate: appearance changes must not silently change inertia. File loads hash the bytes actually parsed. Candidate reload is transactional and retains the accepted model on failure. Parameter edits create a new experiment/model identity and require reset to a valid start.

### 3.3 State, checkpoints and traces

Use scalar GDScript `float` and `PackedFloat64Array` in simulation/physics. World coordinates remain NED; body coordinates remain FRD. Convert to `Vector3`, `Basis`, `Quaternion` or `Transform3D` only for rendering. Stable ordering is FL, FR, RL, RR, defined from a driver looking forward, never from a screenshot.

| State tier | Truck examples | Rule |
| --- | --- | --- |
| Continuous | Body pose/velocity, signed wheel spin, suspension coordinates/rates when dynamic, motor/shaft speed, charge, tire relaxation states when used | Evaluate at every integration stage; explicit versioned layout and units |
| Tick-held auxiliary | Sampled controls, commanded actuator targets, deterministic controller/filter state | Sample once per outer tick; no render-rate dependence |
| Discrete | Arming, forward/brake/reverse mode, supported contact modes, experiment phase, manual recovery events | Deterministic transitions at defined boundaries; restore with continuous state |
| Solver history | Stiction anchors, contact IDs, event brackets and warm-start variables if introduced | Authoritative replay data, not hidden caches; include in rollback/checkpoints |
| Presentation only | Camera spring, wheel visual phase interpolation, particles and audio envelopes | Cannot write physical state; own visual checkpoint only when a capture needs it |

A ground-vehicle checkpoint records family/schema/model/course/material identities, simulation clock and tick, complete state layout, input/controller state, all holds, event state and contact history. Wrong family/version/hash, truncation, non-finite values and inconsistent mode/state combinations fail closed. Unknown future layouts must not be guessed. No int64 random seed/state round-trip through JSON floating-point numbers.

RCV-04 chooses the mechanical-state contract before RCV-09 freezes persistence. If P1 ships the reduced layout before P2's moving hubs, give the P1 layout an explicit experimental version; RCV-11 introduces a new checkpoint/trace model-layout version and refuses incompatible old state. It may migrate a validated parameter recipe and restart, but must not reinterpret missing hub rates as a physically equivalent continuation.

Use a distinct versioned truck trace envelope or channel extension; preserve existing airplane CSV meanings. Include applied controls, gear/mode, vehicle pose, per-wheel contact/surface/normal load/slip/spin/travel, steering angles, motor/brake torques, power, accumulated energy/work, contact events and experiment status. State whether each channel is pre-tick, post-tick or interval-integrated. Record peaks over internal steps as well as outer-tick samples so landing peaks are not silently missed. Record simulation time and wall-time slowdown separately.

Same build/platform replay must reproduce the complete accepted transaction; cross-platform comparison follows documented tolerances. Render/audio/telemetry on/off must not alter the physics. A screenshot and a CSV are not substitutes for a complete replay checkpoint.

## 4. Physical model

### 4.1 Chassis, CG and rollover

Compute mass properties from the identified inventory, not from the artistic mesh bounds. Permit controlled ballast/CG experiments while preserving total mass and inertia consistency. Moving ballast changes both CG and inertia through the parallel-axis theorem. An isolated synthetic CG variation may be offered only as an explicitly different test model, with its mass-property assumptions declared.

Use ordinary six-degree-of-freedom motion. The truck must lift wheels, pitch, roll, yaw and overturn without an angle clamp or a stabilizing torque. Distinguish:

- Quasi-static support: gravitational projection inside the active support polygon, including uneven or three-wheel support.
- Untripped dynamic rollover: load transfer while steering with tire forces.
- Tripped rollover: a tire/sidewall or chassis catches an obstacle or high-resistance surface.
- Recovery: an explicit game action that changes the experiment/run identity.

For a symmetric rigid fixture on a flat surface, `SSF = track/(2*CG_height)` is a useful first-order oracle; `tan(tilt_angle) = SSF` at geometric tipping. It is not a general dynamic threshold for a compliant truck, an off-center CG, unequal tracks or deformable terrain. Check sliding first when friction cannot support the tilt. NHTSA treats static and dynamic rollover measures as complementary; this plan uses its geometric principle, not full-size road-vehicle crash statistics. [Source](https://www.nhtsa.gov/sites/nhtsa.gov/files/rolloverresistance.pdf).

### 4.2 Suspension: useful prototype and laboratory model

P1 may use a rigid sprung assembly with **massless kinematic suspension**, axle positions following an identified travel curve, springs/dampers acting through motion ratios, and wheel spin inertia. Eliminate travel through an algebraic/quasi-static support solve rather than inventing an independent massless acceleration state; map loads to chassis generalized forces through the kinematic Jacobian/virtual work. This is a declared reduced model: it can exercise body heave/roll/pitch and travel but cannot claim unsprung wheel-hop accuracy. Do not show four unsprung masses in telemetry while omitting their dynamics.

P2/P3 must include a qualified reduced multibody suspension with unsprung motion for the requested bump/suspension experiments. A practical target is one travel coordinate per independent wheel plus its rate, with steering/camber/track variation provided by measured or identified kinematics. Derive the generalized equations with the moving masses and their reactions. Treat the sprung-body inertia, hub translational inertia, wheel rotational inertia and shaft momentum consistently; do not apply tire force to both the whole vehicle and an unsprung mass. Do not neglect changing inertia, transport terms or internal momentum and then compensate using damping.

Before integration, compare a constrained quarter-car and half-car against an independent implementation or analytic linear system. Then prove whole-vehicle momentum in free flight and energy accounting with internal suspension motion. If this cannot fit the existing body-plus-suffix integrator contract cleanly, use an isolated float64 truck state adapter. A full unconstrained double-wishbone solver is unnecessary unless the reduced kinematics fail their evidence gate.

For compression `x` with velocity `xdot`, specify a constitutive force from preload, spring curve, compression/rebound damper law and progressive stop forces. Clamp tensile **ground normal force**, not physical suspension travel by teleporting a wheel. Bump stops store/dissipate energy; reaching a limit is not automatically destruction. Droop stops also need a force/constraint law. Damper oil grade alone does not supply a damping coefficient. When the shock/wheel travel ratio is `r = dx_shock/dx_wheel`, the local linear wheel rate is `k_wheel = k_shock*r^2`; nonlinear geometry needs the corresponding generalized-force mapping. Sum the effect of multiple shocks per wheel, if the adopted mechanism has them.

Anti-roll bars, if present, transfer opposing suspension loads through an identified stiffness and must do no net work as an unexplained world-righting controller. Tune ride height by spring/preload/geometry and supported loads, never by lowering the simulated CG for visual stability.

### 4.3 Tires and low-speed behavior

Reuse the existing ground model's sign, grip-bound and dissipative-power tests. The truck requires forward and reverse wheel spin, drive torque, brake torque, coasting, steering and airborne wheel rotation. Keep tire vertical stiffness separate from suspension stiffness and surface deformation.

Define the contact frame from the actual surface normal and the steered wheel plane. At the patch, evaluate velocity from body translation, rotation and hub motion. Use longitudinal and lateral slip with a finite low-speed formulation; `slip = difference / abs(speed)` is invalid at standstill. A static-friction or bristle/relaxation branch must hold a parked vehicle without jitter, transition to sliding under sufficient torque and release on contact loss. Store its history deterministically. Braking at zero speed must not create energy or reverse wheel spin by numerical overshoot.

Constrain combined tangential forces by the declared friction circle/ellipse, for example `(Fx/(mu_x*Fn))^2 + (Fy/(mu_y*Fn))^2 <= 1` when `Fn > 0`. Handle zero grip and zero normal load separately. A force saturator must preserve the intended dissipation and relaxation-state behavior; a force bound alone does not prove passivity of a stateful tire.

Start with an identifiable brush/relaxation model plus measured load/slip curves and explicit limits. Do not adopt a large Pacejka coefficient set from a road car. Chrono documents distinctions between handling tires, geometric contact and deformable tires, and limitations of its Fiala implementation. Those are useful model-selection evidence, not coefficients for small foam-filled monster tires. [Source](https://api.projectchrono.org/wheeled_tire.html).

Rolling resistance, sliding friction and grass drag are distinct parameters. A wet-looking shader must not change grip; a selected physical wet-surface profile must. Tire spin visually follows signed integrated angular speed, including while airborne; it must not derive from vehicle speed when slipping.

### 4.4 Finite wheel geometry and collisions

A single suspension ray is insufficient as the final off-road representation: it can miss an edge before the axle crosses it and does not represent sidewall contact. Qualify a finite-radius/width contact envelope using a cylinder/rounded profile or an equivalent deterministic multi-sample tire envelope. Jolt's cylinder wheel tester is a useful existing implementation to inspect before writing a new geometric routine. [Source](https://jrouwe.github.io/JoltPhysicsDocs/5.6.0/_vehicle_collision_tester_8h_source.html).

RCV-10 must select and pin one geometry method after step, diagonal ridge, landing and sidewall benches. Multiple samples must approximate one tire contact result without multiplying supported load by sample count. Resolve normals and contact points consistently; prevent the selected support from jumping between unrelated obstacle faces. Refine footprint resolution independently of time-step refinement.

Use separate chassis contact proxies for underside/skid plates, bumpers, roof/body shell and relevant sides. Authoritative contact includes inverted resting/sliding and edge impacts. Deterministic broadphase ordering, bounded contact manifolds, swept motion and event localization must address tunneling. At 20 m/s, a 240 Hz outer tick travels about 83 mm: tick rate alone cannot protect an RC tire from missing a small curb.

Do not send a routine wheelie or rollover into the aircraft terminal-crash/wreck pipeline. Define states such as running, airborne, overturned, disabled and recovered as observations/policy over the same dynamics. During an overturn, wheels and drivetrain still evolve; disabling a motor must be an explicit rule. Structural damage thresholds require separate evidence and are not inferred from visual mesh pieces. Until calibrated, severe impacts can produce an explicitly provisional disabled state or stop outside the qualified envelope, with diagnostic cause.

### 4.5 Drivetrain, steering and jumps

Apply motor/engine torque through ratios, efficiency/losses and differential constraints to wheel torque; do not accelerate the chassis with a target-speed force. Reuse electric motor/battery laws only after checking their quadrant, reverse, braking and stop-event assumptions. Aircraft ESC behavior is not automatically a car ESC.

Select explicit front/rear axle differential and center-coupling models. An open axle differential constrains mean speed and equal torque in its ideal limit; it is not equal wheel speed. A locked coupling constrains relative speed and carries reaction torque. Limited-slip behavior needs a torque/relative-speed law and dissipation test. Include one-wheel-airborne and split-friction cases. The reference T-Maxx transmission must not be described as a modern center-differential electric drivetrain unless the selected model actually has one.

Brake, coast and reverse are different modes. The recommended trigger behavior is forward → brake → neutral acknowledgment → reverse, with a measured/declared low-speed engagement threshold; a separate reverse selector is also acceptable. Never convert a full-speed brake command into instant reverse drive. Model electrical regeneration only when the declared ESC/battery supports it; otherwise record dissipated brake energy. Retain motor/wheel dynamics off the ground.

Steering follows a rate/angle-limited servo and defined left/right geometry. Ackermann geometry is a useful low-speed geometric reference, not a demand that every real monster truck be ideal Ackermann. Do not add hidden speed-dependent steering reduction. A beginner steering-rate/power limit is an explicit control assist with its own trace identity.

In flight, wheel/shaft acceleration exchanges angular momentum with the chassis. The expected ability to raise or lower the nose with throttle/brake must arise from the coupled equations and the declared drivetrain, including clutch/freewheel effects. Compute `H_total = H_chassis + sum(H_wheel_hub_assemblies) + H_shafts` about one common inertial origin and over disjoint inventories. Include hub orbital `r × m*v` as well as wheel spin, transform all axes consistently, and exclude wheel inertia already included in the shaft inventory. Do not add both reaction torque and an equivalent momentum term twice. Steering a spinning wheel also changes its angular-momentum direction. Prove the no-external-torque case before teaching jump correction.

Wheel torque cannot directly create translational thrust in free flight. Gravity remains the shared physical value in ordinary play. Add a separate, source-labelled aerodynamic drag model only if needed for the tested speed/jump envelope. Alternate gravity is a marked laboratory intervention and cannot inherit real-world performance claims.

## 5. Terrain, materials and experimental course

The current small analytic ground relief and grass rendering are not a complete off-road course. Keep the existing default airplane field byte-identical when the truck/course extension is absent. Add a separate course descriptor and optional practice area or dedicated truck field, using existing field/light/sky modules. The first release needs one clear selection in Home; it does not need a world editor.

The physical query contract must return height/contact geometry, outward normal, material ID, object/feature ID and any surface velocity, entirely in scalar float64 form. Heightfields cover single-valued ground; curbs, vertical faces and ramps with overhangs require explicit solid proxies or a qualified static mesh query. Render geometry and collision proxies come from the same accepted source, with conservative simplification errors recorded.

| Station | Purpose | Controlled variables and output |
| --- | --- | --- |
| Level pad | Mass distribution, zero-input rest, steering circle | Corner normal loads, drift, steering/radius relation |
| Material strips | Asphalt/compacted dirt/mown grass/rough grass comparisons | Same geometry and entry speed; braking/coast distances, slip and energy |
| Isolated rounded bump | Suspension response | Height/width profile, approach speed, travel, rebound, normal-load loss |
| Alternating bumps | Roll articulation and tire contact continuity | Left/right phase, contact duty, body roll and wheel hop |
| Increasing step/curb | Finite tire radius and tripped rollover | Step size as fraction of tire radius, approach angle/speed, collision refinement |
| Smooth ramp and landing pad | Jump control, pitch and impact | Takeoff speed/pose, airborne time, landing attitude, normal impulse and travel |
| Static slope/banked lane | Grip limit and support/tipping | Angle, surface, ballast location, first unload/slip/tip event |
| Skidpad/slalom | Steering, lateral grip and dynamic rollover | Radius/control tape, speed, lateral acceleration, load transfer |
| Inverted rest fixture | Roof/side contact and recovery | Stability, residual energy, penetration and explicit reset event |

Define course dimensions from the selected truck's actual envelope. Start test bumps at several fractions of tire radius and suspension travel; do not assume a full-size racing circuit scaled visually gives meaningful RC dynamics. Derive ramp geometry and mesh from one descriptor so a beautiful ramp cannot disagree with its contact plane. Test seams from both directions and diagonally.

Physical surface records should separate grip curves, rolling resistance, vertical support/compliance, roughness geometry and optional vegetation drag. Soil compaction/moisture and tire construction matter; there is no universal grass coefficient. Provide provisional profiles with uncertainty and a calibration plan, not fabricated measured values. Start with rigid ground plus explicit relief. A later deformable-soil model needs its own soil parameters, contact area and validation; visual tire tracks remain visual until then.

If lake/water/bank work changes nearby ground, require a clear supported boundary and a deterministic out-of-course recovery policy. Do not let a height query claim solid ground beneath a visually open lake. No first-release flotation/submersion model is implied.

## 6. Numerical qualification and performance

Keep the public session clock at 240 Hz. Evaluate stage-dependent tire, suspension, terrain and motor loads from the stage state/time. Contact entry/loss, full travel, braking lock, reverse engagement and battery boundaries are events; RK4's smooth fourth-order expectation does not apply unchanged through them.

Use this decision sequence:

1. Establish analytic rigid-body, tire-sign and reduced suspension fixtures outside `app/`.
2. Measure the highest linearized sprung/unsprung/contact frequencies for each accepted configuration and the decay scales of relaxation states. Check stability margins, not only finite outputs.
3. Compare 240/480/960/1920 Hz offline references and refine contact geometry separately. Use a different integration method/high-accuracy reference where feasible; two copies of the same equations are not independent validation.
4. If necessary, add deterministic truck-only internal steps/event splits. An outer tick samples input once and commits atomically. Retry/rollback restores contact memory, charge and events. Internal-step count and limits belong to solver identity.
5. If qualified settings cannot meet the existing cost budget, profile the expensive kernel and evaluate a bounded native float64 implementation. No global lower tick rate or silent force clamp to make the truck cheap.

A supported model declares its speed, obstacle, spring, tire and mass ranges. A numerical guard that stops an out-of-domain run is visible, traceable and distinct from a crash. Never silently soften suspension, add damping, cap roll or alter gravity after a solver failure.

Target the main-line **500 microseconds per complete 240 Hz physics tick** on the owner's slowest accepted machine. This target is not already established for the current wheeled-aircraft path. RCV-04, RCV-06 and RCV-10 each include an early complete-tick/kernel cost stop/go before adding more model complexity; RCV-28 is final qualification, not the first performance check. Report individual-tick median/p95/p99/max and worst contact-event ticks, with warmup and run order. Include all internal steps and contact queries. Keep rendering, diagnostics and physics costs separate. Repeat timing alone, not while other agents benchmark the workstation. The 12 catch-up limit means low render frame rate can slow simulation; elapsed game time must not be presented as wall-clock time.

## 7. Menus, input and playable flow

### 7.1 Home and pause

Extend the existing Home selector to **Vehicle / Vehículo**, with a small family filter only if the growing list needs it. Preserve current aircraft choices, order, statuses and defaults. The truck card shows name, actual dimensions/scale class, powertrain, experimental label and a still 3D preview with wheels resting visibly on the ground. Use the existing visual style and screen widgets; this track does not replace the active menu redesign.

For airplanes, the primary action remains **Fly / Volar** and existing starts remain unchanged. For the truck it becomes **Drive / Conducir**, with:

- **Mode / Modo:** Free drive / Conducción libre; Jump practice / Práctica de saltos; Physics lab / Laboratorio de física.
- **Course / Circuito:** the qualified RC practice course initially; optional existing-field free drive only where physical support is explicit.
- **Start / Inicio:** accepted ground pad/checkpoint; no airborne flight start or aircraft trim choice.
- **Controls / Controles:** keyboard/gamepad/radio profile and neutral/arming status.
- **Setup / Ajustes del carro:** preset and evidence status. Advanced parameter editing belongs to the laboratory, not the primary menu.

Preview-only or invalid data disables Drive and supplies a reason. Successful starts alone persist a start choice. Preserve weather/lighting capabilities where supported; weather is not a proxy for surface moisture. Hide aircraft Workshop, elevator trim, smoke AUX, flaps/gear and airplane overlay choices for the truck until corresponding capabilities exist.

Pause offers Continue, Restart run, Return to Home, Controls, Camera, Audio, optional laboratory setup and Quit. Show **Recover vehicle / Recuperar vehículo** only as a deliberate action when supported. Restart reproduces the accepted initial setup; recovery moves to a known clear pose and starts a new run segment. Both save/close or explicitly discard an active trace through the existing failure-visible policy. Do not erase a failed experiment by quietly resetting it.

### 7.2 Preferences and launch routing

Add a validated product vehicle key `{family, id}` plus ground-specific mode/course/camera/input-profile fields. Retain the legacy aircraft preference for older routes. When new keys are absent, derive the existing aircraft selection exactly. Save a newer schema only when needed, preserving the current refusal to overwrite unknown future settings. An unavailable truck selection reports recovery and falls back to a valid selection without overwriting the user's source file unexpectedly.

Keep `--aircraft=<id>` and existing direct/capture commands unchanged. Proposed truck automation is `--vehicle=<truck-id> --mode=drive|lab --course=<id>` with explicit family resolution; these switches **do not exist yet**. Reject conflicting selectors, unsupported starts and unknown IDs. Direct automation remains English and ignores personal preferences. Add dedicated truck trace/capture commands only with their implementation and [TOOLS](../TOOLS.md) entry.

Test Home → truck → drive → pause → recover/restart → Home → airplane, and the opposite order. Check that field/world instances, camera/listener, lighting progression, audio voices, input readers and holds are released exactly once. Vehicle switching cannot inherit a throttle value, trim, camera dimension or stale collision world from the previous family.

### 7.3 Controls

Use a new vehicle command contract (`steering`, `drive`, `brake`, explicit direction/mode) instead of redefining the airplane four-channel meaning. An implementation can pack it internally, but the schema and trace channel names must be explicit. Reuse raw-device discovery/calibration primitives; store vehicle mappings separately from aircraft calibration.

| Device | Proposed mapping | Required behavior |
| --- | --- | --- |
| Keyboard | A/D or left/right steer; W/up drive; S/down brake, then reverse after neutral acknowledgment | Self-centering steering, release-to-zero drive, bounded command slew; do not reuse the airplane's hold-throttle keyboard rule |
| Gamepad | Left-stick X steering, right trigger drive, left trigger brake/reverse policy | Independent trigger calibration, disconnected-device handling, explicit neutral recognition |
| Two-channel pistol radio | Steering wheel + centered forward/brake trigger | Per-device neutral/endpoints, reverse policy, no assumed airplane throttle-at-minimum arming |
| Stick RC radio | Assigned steering and drive/brake channels | Explicit centered or unidirectional throttle profile, no automatic interpretation from axis count |

Arming requires observed valid neutral inputs for a configured dwell and an explicit start/arm rule. Startup/unmoved axes, menu return, focus loss and device loss cannot issue propulsion. Unplug releases propulsion and holds/pauses the session under a declared policy; no giant instantaneous brake force. Resume requires neutral acknowledgment. Physical key labels continue to use the existing keyboard-layout display helper.

Reuse Esc/P/R/C and current camera shortcuts only where their meaning agrees with the common controls reference. Bind recovery separately after a collision check against existing shortcuts; the exact new key is a RCV-20 decision, not an undocumented hidden control. No automatic self-righting in the laboratory. Optional assisted recovery in play is labelled and recorded.

## 8. Camera, audio, visuals and teaching

Default Free drive/Jump practice to a truck-tuned chase camera with a stable horizon and a clear landing-zone view. Offer the existing ground operator view for RC practice and orbit for inspection/lab. Fit distances to the accepted truck dimensions, not an invented wingspan. Retain a single authoritative camera/listener; camera motion consumes interpolated state and never affects physics.

The current chase camera clamps height against terrain but does not by that fact solve occlusion by ramps, walls or vegetation proxies. Add qualified camera sweep/clearance, reverse-motion behavior and upside-down handling. Reset camera history on restart/recovery. Inspect near clipping under the chassis and wheel jitter at 30/60/144 render FPS; model scale must remain real. A bumper/FPV camera is an optional later mount, not a requirement to ship the first truck.

Make the truck visually substantial through framing and detail: legible silhouette, visible suspension travel, tread and sidewall material, correct contact shadows, distinct front/rear and visible wheel spin without strobing. The Blender developer owns the visual proposal under section 13. Use downloaded licensed materials/models wherever suitable. Grass/dust/tire marks are driven by detached contact/slip telemetry and have no physical authority.

Reuse world ambience and audio lifecycle. Add separately sourced/licensed electric drivetrain, tire/surface and impact layers; pitch/load follow accepted telemetry. If a nitro variant is added later, choose its own engine/source model. No airplane propeller sound or arbitrary engine-rev loop presented as truck behavior. Audio on/off must preserve checkpoints; pause/recovery must not leave looping tire or motor voices.

Jump practice is a short sequence:

1. Drive a straight approach and stop in a marked zone.
2. Traverse one low bump and observe suspension travel.
3. Jump a small ramp at a repeatable approach speed.
4. Compare coast, throttle and brake during flight; explain the measured pitch effect and its powertrain limits.
5. Land inside a zone, remain on wheels and settle; then try another setup or replay the approach.

Beginner assistance limits command range/rate or provides an explicit visual cue; it does not secretly reduce gravity, grip or roll. Show speed, direction, control/arming state and the next objective in play. Laboratory overlays can show CG/support polygon, contact normals, wheel loads, slip, suspension travel, forces, energies and measured time histories. Define a clean landing using touchdown attitude/velocity, sustained supported travel and no disqualifying recovery, with thresholds frozen per lesson. Score from committed events and simulation time, never animation or render-frame count.

## 9. Physics laboratory and physical measurement

A run is identified by model/setup, course, materials, gravity/weather, controller, solver, command tape and seed. The laboratory offers known experiments, not a blank screen full of unbounded sliders. Start with presets, duplicate a preset into a user experiment, validate and reset before applying it. Never edit a shipped generated file in place.

| Experiment | Main intervention | Record | What a good result can establish |
| --- | --- | --- | --- |
| Balance | Move measured ballast; front/rear or lateral distribution | Four corner loads, CG, static support margin | Mass/CG implementation and measured static support |
| Suspension drop | Height, spring, damping, preload | Body/hub displacement, travel, wheel load, energy | Known oscillator behavior; measured rebound after identification |
| Bump sweep | Speed and bump size/phase | Contact loss, peak travel, hub/body acceleration | Resolution/domain limits and qualified suspension response |
| Coast/brake | Surface and wheel/brake configuration | Entry speed, distance/time, slip and energy | Rolling/braking behavior for identified conditions |
| Tilt | Slope, material and CG | First slip, unload and tip angles | Geometric oracle, then measured compliant response |
| Steering circle | Steering angle, speed, grip, differential | Radius, yaw rate, slip and side loads | Steering sign/geometry and lateral response |
| Split surface | Left/right grip and drive coupling | Wheel spin, torque, yaw, forward progress | Differential and combined-slip behavior |
| Jump | Ramp, entry speed and airborne command | Takeoff/landing states, airtime and total momentum | Ballistics and internal angular-momentum coupling |
| Rollover/roof slide | Entry state and surface | Contact sequence, energy, pose, recovery mark | Continuous nonterminal contact within tested limits |

A/B mode reruns the same initial state and command tape with one deliberate intervention. Some interventions necessarily change several derived quantities: moving a battery changes both CG and inertia. Show that dependency rather than claiming a one-variable comparison. Traces support export plus a compact plot; the graph reads committed data and does not sample the solver differently.

### Measurement campaign

Before calling the truck physically calibrated, obtain an identified real RC configuration with original files, dimensions, hardware inventory, battery/fuel condition and surface description. Retain source hashes, calibration and uncertainty. Split calibration and held-out trials before fitting.

- Mass/CG: individual component or total weighing and corner scales; raised-axle/tilt measurements for CG height with geometry and tire-deflection corrections. Borrow the repository's weighing uncertainty methods, not its airplane values.
- Inertia: measured pendulum/bifilar data where practical, with fixture/tare and common-axis treatment. A uniform box is an estimated starting point only.
- Suspension: force versus shock/wheel travel, linkage motion ratio, static sag and rebound over several speeds. Do not infer damping from an oil label alone.
- Tires/surface: loaded-radius and vertical-force curves, coast-down, drawbar/braking and constant-radius/slip tests on identified dry/wet grass or hard surfaces. Treat temperature/wear/foam and grass state as configuration.
- Powertrain: voltage/current, motor/shaft/wheel speed, drive/brake modes, gear ratios and loss evidence; distinguish manufacturer peak claims from continuous identified behavior.
- Dynamics: synchronized high-frame-rate side/front video over surveyed bumps/ramps, plus telemetry if available. Camera perspective, timing, scale and uncertain contact instants belong in the reduction.

Freeze comparison tolerances from measurement uncertainty and intended use **before** the held-out test. Where evidence is unavailable, retain experimental labels and report sensitivity ranges. Passing analytic checks or matching another simulator is software/model comparison, not validation of a real monster truck.

## 10. Acceptance matrix

The numbers below are **proposed engineering gates**, not measured results or manufacturer tolerances. Freeze or justify changes in RCV-01/04 before observing acceptance results. Use scale-relative and absolute tolerances together to avoid meaningless relative errors near zero.

| Gate | Test and proposed acceptance |
| --- | --- |
| G-DATA | Reject missing sources/units, unsupported module combinations, invalid inertia, negative masses, duplicate corner IDs, non-finite values, impossible travel and unknown schema fields; valid load/reload/restore is transactional |
| G-REST | Symmetric level fixture: summed normal loads within 0.1% of weight; net pitch moment within 0.1% of weight×wheelbase and roll moment within 0.1% of weight×track. After settling, drift <1 mm and speed <0.1 mm/s over 60 s; repeat on declared slopes with correct hold/slip behavior |
| G-SMOOTH | Free fall, wheel acceleration and linear quarter-car match analytic/high-accuracy reference; approximately fourth-order refinement only on explicitly smooth RK4 segments; a mismatched equation/sign fails even if outputs remain finite |
| G-CONTACT | Across qualified curb/diagonal/ramp/inverted cases, no tunneling; contact penetration target <1% tire radius in ordinary driving and <3% during declared impact events, with refined values reported; body proxy error bounded separately |
| G-REFINE | Offline/reference 240→480→960→1920 effective rates and independent contact resolution: converged event timing and integral quantities; proposed differences <2% for landing impulse, peak travel and stopping distance both between adjacent fine references and between the proposed production solver and the converged reference. Production keeps a 240 Hz outer clock; report any peak-force nonconvergence explicitly |
| G-ENERGY | No sustained positive energy drift in unpowered dissipative fixtures; signed work balance closes to <0.5% of relevant initial/input energy over the declared run, with an absolute floor chosen per fixture; independent wheel/body angular momentum <0.1% drift in no-external-torque benches |
| G-ROLLOVER | Rigid symmetric tilt oracle within 0.5° after refinement; low-friction slide occurs before impossible tipping; compliant result compared separately; roof/side rest remains finite and stable for 60 s |
| G-DRIVE | Verified torque/speed/power signs forward/reverse; brake passes through zero without energy injection; open/locked/split-grip cases satisfy their mechanical constraints; steering and airborne correction direction checked independently |
| G-REPLAY | Restore midway through braking, wheel lift, airborne motion, contact transition and overturned rest; compare complete state/history/identity; injected failure rolls back all; 30/60/144 render FPS and audio/overlays on/off preserve physical results |
| G-REGRESSION | Existing aircraft data validation, golden flights, traces, input, starts, ground handling and captures retain their declared baseline tolerance/identity; no golden re-recording for a vehicle-only change |
| G-UI | EN/ES at 1280×720 and supported scaling; keyboard navigation/focus, start rejection, future settings, no input leakage, device loss, save failure and repeated family round trips all exercised using real UI events |
| G-ASSET | Correct imported dimensions/datum, stable named pivots, witness-vertex articulation signs, no hidden unapplied mirror/scale, required licenses, matching model/manifest and loadable exports |
| G-COST | Whole-tick target ≤500 µs under the main-line measurement policy; record tails/worst events and full-scene frame pacing on target hardware; no accepted slowdown hidden by average FPS |
| G-PHYSICAL | Identified hardware and held-out measurements satisfy predeclared uncertainty-aware criteria; scope restrictions remain visible; no measured data means this gate stays open |
| G-PLAY | At least one novice and one experienced RC driver complete free drive and the basic jump lesson; record completion, recovery count, control confusion, readability and camera discomfort. Proposed target: each completes three controlled landings within 15 minutes after onboarding; sample is formative, not population evidence |
| G-PACKAGE | Fresh checkout imports and exports needed GLB/texture/JSON/shader/audio/license files; Windows/Linux/macOS launch paths exercised under the existing release policy; no authoring `.blend`, local reference dependency or unlicensed source leaked into the pack |

Required deliberate defect controls run only in disposable copies: inverted steering sign, omitted wheel reaction, double-applied normal force, force-circle bypass, corrupted checkpoint contact memory, unavailable asset, unrecorded recovery and skipped curb collision. A checker that still passes its corresponding defect is not acceptance evidence.

Existing commands stay in [TOOLS](../TOOLS.md): `app/test.sh`, `research/test-tools.sh`, focused headless scripts, captures and exports. They are Bash/Linux workflows; use the documented WSL/Linux setup rather than treating them as PowerShell scripts. Future `verify_rcv.py`/test filenames in this plan are proposed deliverables, not commands that can be run today. Documentation-only planning does not require running the complete simulation suite.

## 11. Execution order and reviewable steps

The following implementation map supersedes the original pending statuses in the execution table below. That table retains the full acceptance scope: implementing a subset does not close a step's physical, hardware or release gates. RCV-04a/b and RCV-14a remain dated evidence for their bounded fixtures.

| Steps | Implemented software | Remaining qualification or capability |
| --- | --- | --- |
| RCV-01…03 | Hash-pinned authorized MT8 delivery; generated, strict quantity/provenance vehicle data; estimated electric configuration; deterministic generator and rejection fixtures | Measured component inventory and physical operating envelope |
| RCV-04…07, 11…12 | 31-value float64 chassis, four moving hubs, four wheel spins and steering servo; configuration-dependent coupled mass matrix; RK4 at 240 Hz; support, friction, reverse, braking and steering tests | Full contact-event convergence, complete work accounting and measured suspension/tire response |
| RCV-08 | Symmetric four-wheel drive/braking torque, reverse and wheel/body reaction | Explicit differential/shaft topology, electrical/ESC/battery model and split-grip qualification |
| RCV-09, 19…20 | Transactional session, identity-bound checkpoints, exact float64 JSON payloads, command tape/replay, neutral arming, disconnect/focus holds, reset and marked manual recovery | Real pistol/stick radio profiles and hardware acceptance; wider failure-injection matrix |
| RCV-10, 13 | Shared-airfield dirt loop with banks, ramps/rollers and sphere/AABB wall contact for tire hubs and hull probes; synthetic material fixtures retained; [track evidence](../research/rc-monster-truck/RCV-track/README.md) | Finite terrain tire footprint, swept contact, independent impact refinement and 60 s roof/side-rest qualification |
| RCV-14…17 | Authorized imported GLB/generated rig, CG/datum render adapter, Home RC entry and direct CLI, separate garage/activity with EN/ES controls | General multi-family catalog and persistent vehicle selection are deferred; package qualification is tracked separately |
| RCV-18, 21…22 | Chase/pilot/orbit and circuit-overview cameras, free driving, tested tabletop hop and upright landing, manual recovery | Longer-jump success-toast qualification, full jump curriculum, camera/rollover scenarios and novice/experienced driver playtests |
| RCV-23…24 | Bounded gravity/grip/spring/damping/ballast edits with new identity; load/slip/contact overlays, travel plot, CSV recording and reproducible experiment tools | Measured experiment presets and complete automated A/B intervention workflow |
| RCV-25 | Shared procedural audio voice driven by wheel speed; sound/pause controls | Tire/impact surface audio and calibrated electric sound |
| RCV-26…27 | Experimental status shown in the garage and trace documentation | All physical measurement and held-out validation gates remain open |
| RCV-28…31 | Windows/Linux native evaluator parity; integrated Session/replay checks; four aircraft golden replays; native and reference Windows RC-only exports; native release mean/p95 below 4.167 ms | 500 µs target, worst-tick/render pacing, full application export (HX-700 proof blocker), Linux/macOS packages and clean-clone/CI assembly remain open |

The [runtime evidence](../research/rc-monster-truck/RCV-runtime/README.md) records actual test outcomes and limitations. The historical plan's ≤500 µs target is not relaxed merely because a slower implementation passes its numerical checks. No physical or user gate is closed from headless results alone.

| ID | Work and dependency | Proof / status |
| --- | --- | --- |
| RCV-00 | Register track; repository/source investigation; plan and Blender letter | This plan and its source record / delivered as documentation |
| RCV-01 | Freeze test envelope, baseline source hashes, candidate powertrain and numerical acceptance protocol | Baseline aircraft outputs and a decision/evidence matrix / pending |
| RCV-02 | Blender asset reuse audit, reference mechanism and proposed dimensions; no final mesh before fit/license review | MT8 draft dimensions and visual linkage received and checked in RCV-14a; reuse/license declaration and physical mechanism acceptance pending |
| RCV-03 | Strict ground-vehicle quantity/schema/loader and source pipeline | Positive/negative data fixtures, reproducible generator check / pending |
| RCV-04 | Mechanical-state/integrator spike and independent reduced suspension oracles | **Partial:** [RCV-04a quarter car](../research/rc-monster-truck/RCV-04a/README.md) and [RCV-04b coupled four-corner rig](../research/rc-monster-truck/RCV-04b/README.md) verify reduced motion, energy, refinement and diagnostic kernel cost. Fixed versus variable inertia selection, full-body momentum, complete-tick cost and production state/version selection remain pending |
| RCV-05 | Flat-ground reduced truck: support, mass properties, basic suspension and a minimal versioned flat-pad descriptor for P1 | RCV-04b provides static corner-load and reduced heave/roll/pitch proofs; production reduced truck, mass inventory, flat pad and valid vehicle spawn remain pending |
| RCV-06 | Tire spin, low-speed friction and contact-state transitions | Reverse, stick/slip, force/power signs, no ground force in air; early tire/complete-tick cost gate / pending |
| RCV-07 | Steering/servo and left/right kinematics | Turning geometry and sign witnesses; bounded hardware rate / pending |
| RCV-08 | Electric torque/ESC/braking/reverse and explicit differential model | Power balance, brake/neutral/reverse and split-grip tests / pending |
| RCV-09 | Ground session, accepted start/reset, identity/checkpoint/trace | Mid-regime restore, rejected candidates and failed-step rollback / pending |
| RCV-10 | Finite wheel/obstacle geometry and chassis contact | Curb/diagonal/sidewall/roof benches; independent geometry refinement and contact-event cost gate / pending |
| RCV-11 | Dynamic unsprung suspension and coupled moving-mass mechanics | Quarter/half-car reference, free-flight total momentum and drop tests / pending |
| RCV-12 | Wheel/shaft/body coupling and air control | No-external-torque known answers; drive/brake ballistic jump comparison / pending |
| RCV-13 | Validated physical course descriptor, material mapping and spawn poses | Surface/normal/seam tests and render/proxy agreement / pending |
| RCV-14 | Blender articulated asset delivery and import verifier | **Partial:** [RCV-14a](../research/rc-monster-truck/RCV-14a/README.md) verifies the supplied MT8 draft and local Godot articulation/inspection. Source rights, reuse audit, runtime anchors, LOD/material review and export qualification remain pending |
| RCV-15 | Shared vehicle catalog facade and scene/session adapter with UI/HELI/DR owners | Aircraft catalog loops unchanged; alternate-session lifecycle tests / pending |
| RCV-16 | Home family-aware preview, action, start/mode/course and preference migration; P1 uses RCV-05's flat pad, off-road course choices wait for RCV-13 | EN/ES captures, old/future preferences, start rejection and direct CLI isolation / pending |
| RCV-17 | Truck scene, model articulation and detached render state | RCV-14a provides a tested visual pose adapter; production scene, detached physical state/CG mapping and inversion integration remain pending |
| RCV-18 | Truck camera profile and obstacle/near-clip behavior | Reverse/jump/rollover clips at 30/60/144 FPS; camera-on/off parity / pending |
| RCV-19 | Vehicle device profiles and neutral arming/failsafe | Keyboard/gamepad/pistol/stick radio fixtures plus real hardware trial / pending |
| RCV-20 | Pause/restart/recovery/help and family transitions | Real-input round trips, no held-input launch, trace save/discard failures / pending |
| RCV-21 | Free-drive milestone | P1 user build after RCV-03…09 and 14…20; restricted pad until off-road gates pass / pending |
| RCV-22 | Repeatable jump, rollover and landing lessons; depends on RCV-10/11/12/13 and the playable scene | Committed event scoring, manual recovery invalidation and P2 playtest / pending |
| RCV-23 | Lab presets, bounded edits and A/B command-tape replay; depends on RCV-03/09/13/19 and the physical model each experiment exercises | One intervention changes the intended derived identity; identical-run repeatability / pending |
| RCV-24 | Lab plots/overlays/export and experiment protocol; depends on RCV-23 and finalized model/trace layouts | Channel timing/units and observer parity; repeatable P3 experiment / pending |
| RCV-25 | Tire/surface/motor/impact audio and optional effects | Licenses, telemetry coupling, pause lifecycle and audio/effects parity / pending |
| RCV-26 | Physical measurement acquisition and calibration | Identified hardware, raw hashes, uncertainty and pre-frozen held-out partition / pending |
| RCV-27 | Held-out physical validation and range labels | Independent measured residuals; accepted/unvalidated domains visible / pending |
| RCV-28 | Sequential whole-tick profiling and bounded optimization | Same numerical output, target cost/tails and native fallback decision if necessary / pending |
| RCV-29 | Airplane regression, UI, input and asset sweep | Frozen baselines, no re-recorded airplane goldens, clean resource dependencies / pending |
| RCV-30 | Native EN/ES usability, RC playtest and capture qualification | G-PLAY/G-UI/G-COST evidence on target display/hardware / pending |
| RCV-31 | Fresh-clone export/package and release content | Three-platform resource/launch proof under release policy; P4 candidate / pending |
| RCV-32 | Optional nitro variant after core acceptance | Identified clutch/gearbox/brake/idle/stall and updated model/audio validation / later |
| RCV-33 | Optional advanced soil/tire/damage capability | New measured domains and separate solver/cost gates / later |
| RCV-34 | Consolidate completed plan into operating/authoring guide | Preserve source/measurement evidence, remove superseded planning per conventions / after delivery |

Critical order: data → known mechanical answers → drivable pad → off-road contacts/suspension → controlled jump/rollover → laboratory → measured/playable release. Asset work can run alongside kernels after a shared datum/hardpoint contract. Catalog/menu work can proceed against a valid preview and a mock session, but Drive remains disabled until its numerical/session gates pass. Measurement acquisition can begin early; fitted values must wait for a frozen reduction method.

Parallel work, when requested, uses clear boundaries: physics kernels, source/measurement tooling, Blender assets and UI/presentation each have their own owner. Only one integrator edits shared shell/session files at a time. The external Blender developer supplies assets and manifests; the physics owner supplies numerical parameters and accepts binding compatibility.

## 12. Decision log to settle during implementation

The following are recommendations and open choices, not adopted runtime decisions. Record each accepted outcome in [DECISIONS](../../DECISIONS.md) with its RCV evidence link when implementation is authorized.

| Decision | Recommendation | Evidence/trigger to revisit |
| --- | --- | --- |
| D1 physical reference | Fictional 1/8-class monster with explicit T-Maxx inspiration | A reusable asset/identified real 1/8 platform better satisfies dimensions and measurement access |
| D2 powerplant | Electric first; distinct nitro later | User prioritizes a nitro replica or sufficient clutch/engine/gearbox data is available |
| D3 solver authority | Float64 truck modules with current core reuse | RCV-04/10/28 show correctness/cost or contact complexity requires a different approved architecture |
| D4 suspension | Reduced kinematics plus qualified unsprung dynamics by P2/P3 | Measured linkage behavior falls outside the reduced model |
| D5 contact geometry | Finite tire envelope and explicit chassis proxies | RCV-10 selects sample/envelope/sweep details based on accuracy/cost |
| D6 truck catalog | Product facade plus separate ground catalog/session | Coordinate equivalent shared interfaces already landed by HELI/DR/AE |
| D7 default camera | Chase in play; ground operator and orbit available | Target-user trials show another profile improves control/readability |
| D8 terrain | One deterministic practice course, rigid surfaces and explicit bumps | Measurements justify calibrated compliance or deformable soil |
| D9 recovery | Explicit reset/recovery with run invalidation | A later separately labelled game mode requests assistance |
| D10 source reuse | Download and adapt licensed assets/reference code before commissioning equivalents | No candidate fits the contract after documented review |

Largest risks: contact discontinuities and stiff tires at RC scale; incorrect moving-mass/wheel momentum; unknown material/tire coefficients; artistic pivots inconsistent with hardpoints; shared catalog/session churn; input profiles inherited from aircraft; render-only terrain mistaken for geometry; and a prototype being labelled physically validated. Each has an explicit step/gate above. No calendar promise is credible until RCV-04/10 establish solver complexity and RCV-02 establishes the asset fit.

## 13. Letter and delivery contract for the Blender developer

> **Subject: Reusable, articulated RC monster-truck asset for OpenRC Simulator**
>
> Hello,
>
> We need an attractive, substantial-looking RC monster truck in the 1/8 class for a Godot simulator. The visual direction is strongly inspired by the Traxxas T-Maxx: large tires, high ground clearance, exposed working suspension and a recognizable RC chassis. It must look convincing close up and remain readable while jumping or rolling. The manufacturer's T-Maxx reference is 1/10 scale; our requested vehicle is a fictional 1/8-class interpretation, not an official replica.
>
> Please begin by finding freely downloadable assets and components whose licenses permit the project's intended modification and redistribution. Present the candidates, source URLs, licenses, dimensions and missing work before creating new geometry. Adapt a suitable source whenever possible. Do not rebuild a good available asset just to make it original, and do not treat a free viewer or an unlicensed CAD download as permission to ship it.
>
> You own the visual proposal and modelling work. This plan intentionally does not design the body shell or prescribe a final mesh. First deliver a dimensioned concept and an articulation/hardpoint proposal aligned with the physics owner. We will agree on the datum, dimensions, mechanism and powertrain identity before final detailing. The likely first version is electric; nitro packaging should be a separate explicit variant if requested.
>
> We need separate steerable/spinning wheels, suspension pieces that can follow simulated travel, visible shock shafts, a body/chassis suitable for viewing from below, and simple separately identified contact proxies. Geometry is presentation; the physics team derives mass, CG, inertia and forces from a separate sourced inventory. Please do not tune handling by moving the model origin or hiding scale in parents.
>
> Deliver the editable Blender source, a reproducible glTF/GLB export, materials/textures, the binding/dimension/source manifest and the review evidence below. Our importer will verify dimensions and motion in the pinned Godot Compatibility renderer. A beautiful render alone is not final acceptance.
>
> Please raise unresolved dimensions, unclear licenses or mechanical conflicts in the first milestone. We prefer a reusable, correctly articulated and well-documented asset over cosmetic detail that makes iteration difficult.
>
> Thank you.

### 13.1 Required delivery package

| Deliverable | Contents |
| --- | --- |
| Reuse audit | At least the relevant candidate vehicles/components/materials found, exact URLs, author, asset version/download date, license evidence, redistribution/attribution conditions, fit and chosen/rejected rationale |
| Reference board | Manufacturer/reference links and permitted images, separate verified dimensions from estimates; do not bundle unlicensed manuals/images in the MIT runtime assets |
| Dimension sheet | Length/width/height, wheelbase, front/rear track, unloaded tire radius/width, ground clearance and rest pose; datum and units on every view; independent measurement of source asset bounds |
| Source | `.blend`, packed or resolvable textures, source license/attribution, exact Blender version, export settings/script and any required add-on version/license |
| Runtime | One identified GLB per accepted variant/LOD arrangement; PBR textures and license notices; no dependency on a developer's absolute paths |
| Binding manifest | Root/datum, FL/FR/RL/RR hardpoints and pivot axes, rest transforms, motion limits, named parts, contact proxy IDs, camera/audio anchors, material list and asset hashes |
| Inspection evidence | Front/rear/side/top/bottom orthographic views, three-quarter views, dimension overlays, wireframe, rest/full bump/full droop/full steering and combined travel/steering; Godot imported screenshots |
| Change record | What was downloaded/adapted/authored, dimension/articulation changes between deliveries, and commands/settings that reproduce the export |

Do not submit a procedural recreation of an available asset without explaining the reuse limitation. No asset pack is accepted solely because a search result says “free”; verify the chosen file's license and downloaded contents. Custom geometry is limited to missing or unsuitable parts after the reuse audit.

### 13.2 Coordinates and articulation contract

One metre in Blender/export equals one metre in Godot. The **imported** model uses local +X right, +Y up, −Z forward. The simulation uses body +X forward, +Y right, +Z down and `frames.gd` at the boundary. Choose a stable chassis datum agreed with physics, not an arbitrary changing CG; include the current CG location in the manifest as a diagnostic reference only. The renderer offsets the visual root to the simulated CG.

Freeze this proposed naming contract before detailed work; the stable names matter more than the exact hierarchy shown:

```text
vehicle_root
  chassis
  body_shell
  wheel_FL_mount
    wheel_FL_suspension
      wheel_FL_steer
        wheel_FL_spin
          wheel_FL_mesh
  wheel_FR_mount / wheel_FR_suspension / wheel_FR_steer / wheel_FR_spin / wheel_FR_mesh
  wheel_RL_mount / wheel_RL_suspension / wheel_RL_steer / wheel_RL_spin / wheel_RL_mesh
  wheel_RR_mount / wheel_RR_suspension / wheel_RR_steer / wheel_RR_spin / wheel_RR_mesh
  suspension_links_<corner>_<part>
  shock_<corner>_<index>_body / shock_<corner>_<index>_shaft
  camera_chase_target / camera_front_mount
  audio_motor / audio_contact_<corner>
  proxy_<component>_<index>   [source/debug collection; not a second physics system]
```

The sibling spelling above abbreviates identical per-corner subtrees. `mount` carries fixed imported/rest orientation; driven pivots start with identity rotations. Do not drive Euler angles onto a node whose imported basis already contains the rest transform. If linkage travel requires full transforms, the binding manifest says so and the renderer applies the accepted kinematic pose. Arms/links are presentation followers, not Blender rigid-body simulations baked into gameplay.

Rear steering pivots can exist as zero-angle bindings for symmetry but must not imply rear-steering capability. Name all shocks when a wheel has multiple shocks. Use separate left/right wheel assets or properly applied mirrored geometry; no negative-scale parent that reverses axes/normals. Wheels must roll forward correctly on all four corners and steer toward the commanded turn. Check signs with a marked witness vertex in Godot; do not rely on appearance from a single camera angle.

Hardpoints and motion curves must cover full steering through full bump/droop without impossible tire/body/link intersections. Any deliberately allowed cosmetic overlap is documented. The body shell must have a convincing underside; a roof-down rollover is a normal camera view. Fast tread motion may use an approved visual LOD, but the static and slow wheel must retain identifiable tread/orientation.

### 13.3 Materials, geometry and performance

Use glTF metallic/roughness materials supported by Godot Compatibility. Prefer opaque materials, baked detail and atlas reuse where helpful. Supply texture color-space/channel intent and readable names. Check UVs, normals, winding, tangents, transparency and mip behavior in the actual engine. Do not depend on Blender-only procedural shaders or modifiers surviving export.

Provisional **asset review budgets**, to be accepted or revised with target-GPU evidence: LOD0 about 60k–100k triangles for the complete truck; LOD1 about 20k–35k; LOD2 about 5k–10k; roughly 8–12 material surfaces in the near model; normally 2K texture sets, 4K only if inspection demonstrates a need. These are planning envelopes, not measured engine limits or reasons to destroy a reusable source. Count exported triangles/surfaces/textures, not Blender object count. LOD transitions cannot move wheel centers, change the silhouette abruptly or detach shocks.

Contact proxies are a small, named, dimensioned set of simple closed shapes supplied separately from the beauty mesh. Wheels need a physical radius/width envelope; the body needs underside, side, bumper and roof support. Do not generate collision from all tread triangles or every decorative bolt. The physics owner accepts proxy simplification and owns contact laws. The GLB must not introduce an authoritative Godot rigid body, hidden animation root motion or a second solver.

### 13.4 Developer milestones and acceptance

1. **B1 — reuse and dimensions:** source/license audit, reference selection, dimensioned proposal and unresolved questions. Accepted when the asset is legally usable under its actual license and geometrically suitable; this is not final vehicle design approval.
2. **B2 — articulated draft:** source-derived basic mesh, accepted datum/hardpoints and complete named moving parts; imported witness tests pass before surface detail.
3. **B3 — visual finish:** accepted materials, underside, shadows, LODs and full-motion clearance; review in daylight/evening and on the practice terrain.
4. **B4 — reproducible handoff:** all source/runtime files, manifest, licenses, settings, hashes and captures; clean-machine import and dimension/pivot checks pass.

Reject a delivery with unclear source rights, missing editable source, centimetre/metre mismatch, one joined wheel/body mesh, baked-only suspension, negative-scale articulation, missing roof/underbody proxies, changed stable pivot names, hidden texture paths or unaccounted mass claims. Accept visual quality through engine inspection and user review; accept mechanics only through the physics/data owner and numerical evidence.
