# Advanced ground, takeoff, landing and damage physics masterplan

**Status: implementation in progress; bounded physics, lifecycle and audio slices integrated. Stock advanced-contact activation remains gated.** Audit date: **2026-10-25**. Owner: existing **GP ground-physics track**, with SF, AS, aircraft, CR, AUD, AE, UI-FS, input, landscape and performance owners retaining their interfaces. This plan extends GP-00…07; it does not replace their delivered evidence. Execution steps are GP-08…23 (§12). The execution ledger distinguishes delivered slices from the full acceptance gates. Later dated slices supersede earlier scope limits; their original evidence remains unchanged.

| Implemented slice | Evidence and remaining gate |
| --- | --- |
| GP-08a frozen air/ground reference and candidate preservation | [Baseline](research/ground-physics/GP-08/evidence/README.md), [candidate replay](research/ground-physics/GP-08/evidence/candidate/README.md): four Stik/P-51 cases, 1,484 byte-equal sample rows, complete explicit candidate replays. Full scenario/fleet inventory and target-host budgets remain open. |
| GP-09a fixed-axis coupled wheel/body foundation | [Implementation and 84 checks](research/ground-physics/GP-09/README.md). Actual legacy code reproduces the +1.5 W counterexample; the coupled reference conserves momentum and energy, including internal airborne braking, at 120/240/480 Hz. The stock wheel law is unchanged. Moving steering/retract axes, locked-inertia inventory and joint dynamic-shaft integration must pass before fleet migration. |
| GP-10a/b typed support query and bank-normal correction | [Contract and evidence](research/ground-physics/GP-10/README.md). Adds detached geometry/material observations and an explicit relief-profile adapter; corrects the hull's positive-down lake-slope normal. No-lake force laws retain their prior arithmetic. Round-wheel closest points, whole-hull relief migration and live explicit-profile rollout remain open. |
| GP-14a/b survivable accidents and shared events | [Implementation and integration](research/ground-physics/GP-14/README.md), [453-check shared-event cohort](research/ground-physics/GP-14/evidence/shared-events/README.md). The existing classifier records nonterminal gear-up accidents, touchdown/bounce and landing outcomes, publishing immutable batches while preserving M7. Snapshot v3 preserves hop history and historical coverage. Physical component-damage/gear-failure emitters, full observation envelope and general accident archive remain open. |
| GP-14c optional intended hull support (2026-10-26) | [Contract/status](research/ground-physics/GP-14/README.md#optional-authored-hull-support-gp-14c), [2037-check cohort](research/ground-physics/GP-14/evidence/intended-hull-support/README.md): strict optional v2 role authoring and model-pinned accepted flat-solid observations feed the existing classifier. Mixed/wrong-pose IDs disqualify without event detail; no new forces/state or inferred no-gear intent. Stock X8 authoring, lake scope, physical calibration and performance remain open. The original 11 changed-input baseline mismatches are retained honestly. |
| GP-14d accepted runway reset publication (2026-10-26) | [Contract/status](research/ground-physics/GP-14/README.md#accepted-runway-reset-publication-gp-14d), [3882-check cohort](research/ground-physics/GP-14/evidence/reset-publication/README.md): physical commit precedes synchronous reset notifications, which precede tick0 publication. Detached old closing context preserves recorder/footer/fleet identity; precommit reentry rejects silently, committed observer faults pause and retain one new generation. Legacy empty-hook bytes are frozen. Airborne/reload/restore reset migration, full-suite and physical/performance qualification remain open. |
| GP-14e common start/reload transactions (2026-10-26) | [Current contract](research/ground-physics/GP-14/README.md#common-start-and-reload-transactions-gp-14e), [4066-check cohort](research/ground-physics/GP-14/evidence/start-transactions/README.md): one owner begins before trim/model staging for runway, airborne, hand launch, fallback and reload. Explicit commit receipts preserve failed candidates/open recordings and prevent post-commit observer-fault rollback or false reload credit; original kernel/model/failure/RNG context restores without old reset/evaluation. Initial failure parking remains separate. Restore/configuration publication and full physical/performance qualification remain open. |
| GP-14f accepted restore publication (2026-10-26) | [Current contract](research/ground-physics/GP-14/README.md#accepted-restore-publication-gp-14f), [4398-check cohort](research/ground-physics/GP-14/evidence/restore-publication/README.md): existing restore parser and common owner commit before closing old observers, then automatically pause without a stepped sample. Refusal preserves old state/resources/recording; committed observer faults keep the accepted paused frame. Existing checkpoint-restore bookkeeping and noncredit replay branch remain; empty-hook legacy bytes/order are frozen. Configuration setters, full-suite and physical/performance qualification remain open. |
| GP-14g refused field replacement (2026-10-26) | [Contract](research/ground-physics/GP-14/README.md#refused-field-replacement-gp-14g), [3409-check cohort](research/ground-physics/GP-14/evidence/field-refusal/README.md): failed replacement preserves installed physical/observation tables, hull binding, checkpoint and open recorder without notifications; observational error is separate from active invalidity. First invalid setup remains fail-closed; empty field descriptions are recognized. Accepted no-reset field behavior is unchanged; live changed-field recording identity and weather/shaft publication remain outside this slice. |
| GP-14h accepted pending-weather selection (2026-10-26) | [Contract](research/ground-physics/GP-14/README.md#accepted-pending-weather-selection-gp-14h), [3915 production checks plus 19 independent checks](research/ground-physics/GP-14/evidence/weather-publication/README.md): guarded configuration publication closes the old recording with its exact checkpoint, retains pending selection on observer faults and emits no tick or statistics credit. The subsequent explicit reset remains the physical start. Frozen weather traces are unchanged; shaft publication and full physical/performance gates remain open. |
| GP-14i accepted pending-shaft selection (2026-10-26) | [Contract](research/ground-physics/GP-14/README.md#accepted-pending-shaft-selection-gp-14i), [4017-check cohort](research/ground-physics/GP-14/evidence/shaft-publication/README.md): validated pending mode and existing callbacks precede guarded notification; exact old recorder footer, protected state, rejection silence and one later physical-reset credit are preserved. Frozen split/coupled traces are unchanged. Stock advanced contact, live changed-field recording identity and full physical/performance gates remain open. |
| GP-09b/c and GP-10c coupled rotation/geometry foundations | [Common rotor system](research/ground-physics/GP-09/README.md#gp-09b-c-prescribed-carriers-and-a-common-rotor-system) and [round-wheel envelope](research/ground-physics/GP-10/README.md#gp-10c-round-wheel-geometry): full prescribed-carrier work, simultaneous shaft/wheel solves, finite holds, mass-metric projection and certified local terrain support. Fixed hubs and zero-width rings are explicit limits; stock session migration remains open. |
| GP-11a and GP-20a compliant support authoring | [Implementation record](research/ground-physics/GP-11/README.md): exact spring/stop potential, asymmetric unilateral damping, bounded scalar integration admission, strict optional aircraft resources and explicit estimated rotor partition. Synthetic rebound/static-sag/refinement tests pass. Live combined traction, complete aircraft admission, Workshop editing and measured coefficients remain open. |
| GP-16a/b and GP-17a/b persistent damage and attached response | [Contracts and tests](research/ground-physics/GP-16/README.md), [657-check response cohort](research/ground-physics/GP-16/evidence/attached-response/README.md): fixed-layout transactions now bind actual normal-force/potential evaluation to persistent authored weaker compliance. Synthetic symmetric light/heavy/hard kernel drops, rebound and exact continuation pass; a separate direct boundary check proves asymmetric support failure and roll moment, without qualifying its dynamic continuation. This is fixed-hub constitutive failure; stock moving-leg collapse, session activation and peak-load localization remain open. |
| GP-16c accepted component-failure events (2026-10-26) | [Contract](research/ground-physics/GP-14/README.md#accepted-component-failure-events-gp-16c), [948 checks with source scope](research/ground-physics/GP-14/evidence/component-failure-events/README.md): strict optional accepted facts feed the existing detector/service; one nonterminal CRASH/M7 plus per-component damage/failure pairs, with replay dedup and bounded evidence. 332 affected checks use final source; 616 regressions retain their preceding source revision. Actual heavy/hard kernel batches and first asymmetric commit pass; rolled continuation explicitly refuses. Stock activation, full overload timing, calibrated strength, moving collapse and comprehensive archives remain open. |
| GP-12a/20b traction and prescribed steering composition | [Assembled stage and steering](research/ground-physics/GP-11/README.md#prescribed-steering-and-assembled-stage): one common shaft/wheel stage, bounded full-mobility friction impulse solve, explicit steering resource bindings and continuous linkage states. Passive fixture integration and aircraft source-event policies must pass before live opt-in; these helpers do not replace stock handling by themselves. |
| GP-12b/c fixed-voltage composition, numerical resolution and accuracy | [Implementation and limits](research/ground-physics/GP-12/README.md), earlier [1,134-check acceleration cohort](research/ground-physics/GP-12/evidence/traction-acceleration/README.md) plus 34 independent checks, and [1,433-check resolution/accuracy cohort](research/ground-physics/GP-12/evidence/rest-resolution/README.md). Electric startup/cutoff and exact capture pass; a distinct operand-verified numerical contract addresses captured near-rest QP refusals. Loaded three-wheel refinement and two-sided integration qualification continue. These foundations do not enable stock contact or complete the fleet gate. |
| GP-12 numerical correctness foundation (2026-10-26) | [1,550-check production cohort](research/ground-physics/GP-12/evidence/numerical-foundation/README.md): bounded proposals, final-impulse proofs, post-slip/work cancellation bounds and published-state passivity checks preserve strict defaults. The full 10-second rest tape completes without solver refusal; its original 15/1 receipt retains an incomplete normal-only torque assertion, corrected by independent full-reaction postprocessing. Drop localization, runtime performance and stock activation remain open. |
| GP-12 finite-source evaluation (2026-10-26) | [742-check cohort](research/ground-physics/GP-12/evidence/finite-source-evaluation/README.md): existing OCV/PackEcm rates and sampled ESC reuse the single aircraft stage/shaft-wheel torque ownership. Complete fixed-bus output parity passes. Finite-source boundary integration is still explicitly refused by Step; no stock launch is enabled. |
| GP-12 local normal envelope (2026-10-26) | [553 production checks](research/ground-physics/GP-12/evidence/local-envelope/README.md): additive interval bounds preserve all existing force/default outputs. Combined local compression/load/projection envelopes reduce the tested resting checkpoints from 16 to 4 pieces with unchanged raw accuracy gates. Whole-interval coverage remains conditional; runtime integration and production performance are unqualified. |
| GP-12 qualified unloaded normal loss (2026-10-26) | [381 production checks](research/ground-physics/GP-12/evidence/unloaded-potential/README.md): an explicitly bound unforced fixed-plane owner can use per-piece support-potential loss when all actual RK normal samples remain zero. Default state/force/output bytes and raw physical tolerances are preserved; mixed-method accounting, rollback and exact continuation pass. Original full drops remain 24/2: gentle advances from tick 98 to 143 before QP nonconvergence; hard remains at tick 78 on cap-area accuracy. Full loaded drops, stock activation and performance remain open. |
| GP-12 fixed mass-proof prefix reuse (2026-10-26) | [858 production checks and measured cohort](research/ground-physics/GP-12/evidence/mass-prefix-reuse/README.md): one trusted local proof reuses exact fixed-matrix SPD/inverse work; mismatches recompute, while all current assembly/objective/work gates and complete outputs remain unchanged. Ten warmed pairs reduce resting medians by 13.7%/20.1%, with substantial spread and roughly 0.7 s per resting tick. This is no real-time qualification or QP convergence/stock-activation result. |
| GP-12 current-stage factor reuse (2026-10-26) | [984 production checks](research/ground-physics/GP-12/evidence/stage-factor-reuse/README.md) plus seven independent edge checks: an unconstrained wheel/shaft stage reuses its already computed factor; held solves and complete physical outputs remain unchanged. The isolated four-rotor method median fell by 7.4%; no whole-tick or real-time qualification follows. |
| GP-12 bounded unresolved-direction fallback (2026-10-26) | [1,607 production assertions, 64 independent assertions and complete gentle drop](research/ground-physics/GP-12/evidence/unresolved-descent/README.md): exact scalar cap verification plus opt-in full-objective weak-direction descent preserves original capacities/KKT/work and completes unchanged gentle180. Selected fallback version belongs in owner solver/start/checkpoint identity before first use; conditional usage receipts are insufficient. Default/early/zero-optimal bytes remain pinned. Hard78 cap-area accuracy, stock activation and performance remain open. |
| GP-19a accepted mechanism audio (2026-10-26) | [Current contract](servo-retract-audio-implementation.md), [317-check cohort](research/ground-physics/GP-19/evidence/accepted-mechanics/README.md): servo/flap/retract transitions now survive between render frames through the existing classifier and bounded players. Real-session checkpoint parity, rejected-tick silence and pause/reset/reattach cleanup pass. Ground/slip/damage audio, native listening and whole-flight performance remain open. |
| GP-19b material-driven fixed-wing rolling (2026-10-26) | [91-check cohort](research/ground-physics/GP-19/evidence/material-routing/README.md): existing contact snapshots use shared solid-support material identities; turf and long grass select grass audio, with explicit unknown-material fallback. Full-session checkpoint preservation and existing audio checks pass. Accepted wheel/slip/work capture, helicopter material migration, damage layers and native/performance gates remain open. |
| GP-19c accepted contact audio (2026-10-26) | [202 production checks plus 11 independent review checks](research/ground-physics/GP-19/evidence/accepted-contacts/README.md): bounded accepted-endpoint capture preserves brief contacts between renders, using the same legacy presentation classifier and recordings. Actual Stik drop checkpoint parity, rewind/pause/reset, source-clock expiry and voice bounds pass. Advanced solver receipt input, new scrape/damage layers, native listening and production performance remain open. |
| GP-19d accepted hull-friction scraping (2026-10-26) | [550 production checks and independent review](research/ground-physics/GP-19/evidence/accepted-hull-scrape/README.md): optional same-law loaded tangent-force/velocity diagnostics feed accepted-endpoint grains in the existing crash pool; default force bytes, live-fuel mass/CG and full checkpoints remain unchanged. Capture is player-free; render applies deferred cancellation, and short brushes survive between frames. Flat solid only, instantaneous power without integrated-work/heat claims, 0.25 accepted-simulation-second cue age. Existing generic asset provenance retained. Lake scope, native/listening, combined budgets and whole-flight performance remain open. |
| GP-19 native continuous-flight audio (2026-10-26) | [One source-pinned WASAPI capture](research/ground-physics/GP-19/evidence/native-continuous-timber/README.md): current Turbo Lumber takeoff/touchdown/terrain rollout completes without reset, fault or crash; PCM clocks, discards, clipping and selected source stability pass. Estimated Master true peak -22.5047 dBTP. Full-fleet, isolated hull-scrape audibility, listening and target-hardware qualification remain open; the experimental contact solver is not enabled. |
| GP-19 scrape unloading envelope (2026-10-26) | [72 focused production checks](research/ground-physics/GP-19/evidence/scrape-unloading/README.md): accepted scrape amplitude now tends continuously to silence as friction power tends to zero, with unchanged maximum gain and pool. Baseline fails the two new limiting-response checks. The prior native capture predates this presentation-only change; acoustic calibration and listening remain open. |

The source audit and model comparisons below describe their dated baseline unless explicitly amended. Progressive suspension and persistent failure now have tested executable components; **calibrated rebound and live stock-aircraft broken-gear dynamics remain open**. Existing compliant bounce remains in service until the combined contact/propulsion/state adapter passes its gates. No golden flight was re-recorded.

Baseline commit: `4336ba6897e46adef2fe88aa24f55e639d5ad140`. Source symbols, rather than graph line numbers, are the audit references: the existing knowledge graph was substantially stale, so discoveries were checked against current files. Concurrent work in this shared tree is explicitly outside this mission. The dated [source and audit ledger](research/ground-physics/GP-08/sources.md) records execution, source identity, research limitations and any checks actually performed. Numerical targets below are **proposed acceptance criteria**, not achieved measurements or universal physical limits.

Canonical boundaries: [stack](STACK.md#boundaries-and-data-flow), [aircraft contract](AIRCRAFT_CONTRACT.md), [ground evidence](research/ground-physics/README.md), [crash guide](CRASH-DAMAGE-PLAN.md), [audio guide](AUDIO-PLAN.md), [Workshop plan](plans/aircraft-editor.md), [statistics plan](flight-statistics-plan.md), [flight logging](FLIGHT-LOGGING.md), [tool index](tools/README.md). This document owns the integrated future sequence; those guides continue to own current behavior and their existing qualification gates.

## 1. Executive summary

OpenRC already has a substantial ground model. Aircraft are integrated by a custom float64, six-degree-of-freedom kernel at 240 Hz, with RK4-coupled wheel rim speeds, spring/damper support, separate rolling and sliding terms, friction limiting, static anchors, terrain micro-relief, rudder-linked steering, ground effect, retractable-gear drag, soft airframe contact and propeller strikes. Replacing this with `VehicleBody3D` or a second `RigidBody3D` solver would discard valuable behavior and create conflicting force owners.

The largest gaps are **physical parameter evidence, coherent wheel/body energy accounting, geometry, state semantics and integration**:

1. Gear springs were partly selected to satisfy an older numerical envelope. The GP-06 audit measured simulator sag of roughly 17.5–34.5 mm, not real aircraft sag. Inflating allowable compression to pass a borrowed full-scale reserve-drop convention did not measure RC structural strength.
2. A wheel is still represented by its body-fixed level-attitude bottom point. Pitch, bank, camber and retraction change the real rim contact location. Hull and propeller ground queries also differ from wheel terrain queries outside lake geometry.
3. The wheel spin reaction, locked-body inertia and relative rim speed require a single energy derivation. §4 gives an independently checked instantaneous energy-balance counterexample under an explicit locked-inertia convention. GP-09a now reproduces it against the actual legacy functions and provides a conservative fixed-axis reference; it is not a measured stock-aircraft flight defect or a completed fleet migration.
4. Friction, rolling loss, braking and roughness are partly entangled. The surface table has no explicit material identity; roughness is selected through rolling-factor values. Brakes only act in loaded contact and the session exposes brake demand through retractable-gear capability.
5. Retracts have continuous extension and drag, but wheel support is admitted only at full extension. Partial deployment does not have a complete mechanical collision/support model, door forces, asymmetric state or failure contract.
6. Soft belly slides already continue in ordinary interactive flight. Gear overtravel and selected severe hull contacts still terminate it. There is no general persistent aircraft component-damage model; wreck breakup and repair estimates are not damaged-flight mechanics.
7. Contact observations, audio and the statistics detector are valuable foundations. GP-14a amends the detector's terminal-only crash assumption for survivable gear-up contact. A complete shared takeoff/landing/accident vocabulary and independent damage model are still required.

**Recommended architecture:** retain the shared kernel and aircraft aerodynamic model. Extend the existing ground laws through versioned aircraft modules, explicit surface/material queries and a coupled wheel/body formulation. Keep compliant normal support; select substeps from physical stiffness and numerical accuracy, never soften hardware merely to fit a tick. Stage all physical changes transactionally. Publish accepted contact, damage and flight-episode observations to audio, reports and statistics. A statistical accident is independent of damage severity and independent of whether physics continues.

**Required visible outcome:** as aerodynamic lift and pitching moments change, per-wheel reactions change through the equations of motion. Rolling loss decreases with load; the last contact unloads naturally. Touchdown restores support through finite compliance, wheel spin-up and dissipative tire forces. No force is enabled by a takeoff score, airspeed threshold, animation state or sound cue. Gentle gear-up contact emits an accident/crash classification and may continue sliding, steering or flying when the physical model remains valid.

**Priority order:** P0 conservation, contact/query correctness, deterministic lifecycle and accidental termination; P1 measured suspension, wheel geometry/traction, gear mechanisms and aerodynamic coupling; P2 persistent damage, complete feedback and authoring; P3 measured refinements, deformable terrain and polish. Rendering qualification is **1920×1080 first**, higher resolutions second, 720p fallback last. Existing 720p defaults are not qualification evidence.

## 2. Repository audit

### 2.1 Runtime, scene and solver identity

| Item | Verified implementation | Architectural consequence |
| --- | --- | --- |
| Engine | [get-godot.sh](../app/get-godot.sh) pins **4.8-beta1**, exact identity `4.8.beta1.official.4d10419ca`, official archive SHA-512 per platform. [project.godot](../app/project.godot) declares 4.8. | Use this binary/source tag for acceptance. Do not quietly substitute stable or latest documentation behavior. |
| Native 3D backend | No `physics/3d/physics_engine` override is set. In this pinned engine the setting's default is **GodotPhysics3D**. The fact that newly created projects select Jolt does not change an existing project's unset setting. | Native backend is not the flight solver. Log the resolved setting in future acceptance receipts, especially exported builds. |
| Application route | [startup.tscn](../app/ui/startup.tscn) → [app_root.tscn](../app/app_root.tscn)/[app_root.gd](../app/app_root.gd) → [main.tscn](../app/main.tscn)/[main.gd](../app/main.gd). `main.tscn` has a `Node3D` root, not a flight `RigidBody3D`. | Session owns aircraft physics; Main assembles presentation, input actions and reports. |
| Kernel | [simulation.gd](../app/sim/simulation.gd), `step`, checkpoint/restore and accepted `stepped` publication; [vehicle_model.gd](../app/sim/vehicle_model.gd) defines stage, continuous state, event and substep callbacks. | One model per simulation. No `if aircraft` branch in the kernel. |
| Timing | 240 Hz, `dt=1/240 s`; maximum 12 catch-up ticks per rendered frame; custom render interpolation, jitter fix 0. Kernel supports bounded contact substeps. | Physics time, not render time or wall time, drives contact, damage and episode timers. Slow rendering can slow simulation. |
| Coordinates/state | 13 rigid-body float64 values plus continuous blocks. FRD body, NED world, quaternion `[w,x,y,z]` maps body to NED. Rendering conversion at [frames.gd](../app/render/frames.gd). | No `Vector3`, `Basis`, `Quaternion` or `Transform3D` simulation state. Native vector queries, if used, are boundary adapters only. |
| Moving mass | [mass_inventory.gd](../app/physics/mass_inventory.gd), [fixed_datum_body.gd](../app/physics/fixed_datum_body.gd), session `mass_properties()`. O is the fixed reference datum; live CG/inertia depend on fuel. | Contact point velocities use O-relative arms; dynamic moments/mobility use live CG. Do not subtract CG twice. |
| Landscapes | [catalog.gd](../app/landscapes/catalog.gd), [field_loader.gd](../app/data/field_loader.gd), selected field data and scenery inventory. [environment.gd](../app/sim/environment.gd) supplies physical wind, atmosphere, terrain, lake and optional road queries. | Extend this environment contract rather than add a parallel runway detector. |

### 2.2 Subsystem classification and exact seams

**Existing** means implemented; **reusable** means suitable foundation; **incomplete** means a real implementation lacks a requested capability; **incorrect** identifies a demonstrated contract/model inconsistency within stated assumptions; **missing** means absent in the audited baseline. None of these labels establishes physical calibration. Later concurrent UI-FS edits are not treated as accepted baseline functionality.

| Subsystem / classification | Source and functions | Evidence, limitation and required integration |
| --- | --- | --- |
| Flight force model — existing/reusable | [aero.gd](../app/physics/aero.gd), `loads`, strip/envelope paths; [propulsion.gd](../app/physics/propulsion.gd); session `_loads`, joint stage evaluators | Aerodynamics, propulsion and contact already sum physical loads. Preserve free-flight laws; add ground contributions at their current boundaries, not in Main. |
| Body integration — existing/reusable | [rigid_body.gd](../app/physics/rigid_body.gd), `derivative`; [integrator.gd](../app/physics/integrator.gd), RK4; `VehicleModel.stage` | Kernel handles accepted state/rollback. A contact projection must update body and wheel state together; existing body-only post-tick callbacks cannot do that. |
| Gear support — existing/incomplete | [ground_contact.gd](../app/physics/ground_contact.gd), `loads`, `evaluate`, `compressions`, `collapsed`, `substeps`; [ground_wheels.gd](../app/physics/ground_wheels.gd), `frame`, `evaluate` | Spring/damper load and terrain normal already exist. Physical stiffness evidence, round contact, explicit stroke/bottom stop and surviving collapse are missing. GP-06 remains the parameter warning. |
| Wheel rotation/traction — existing/incomplete; energy consistency issue | `GroundWheels.evaluate`, `coefficients`, `anchor_step`; [wheel_profiles.gd](../app/physics/wheel_profiles.gd), `apply_to_model`, `_validate_physics_limits` | Rim speed, longitudinal slip and combined tangential bound exist. Current force slope is capped by numerical relaxation, not a measured tire law. Coupled-body energy and general static rolling need §4/GP-09 proof. |
| Resting/static friction — existing/incomplete | `GroundContact.anchor_step`, `anchor_energy`; `GroundWheels.anchor_step` | Anchors use low-speed thresholds and separate rolling/lateral limits. Do not call this a fully calibrated tire static-friction law. Preserve spring energy and deterministic anchor lifecycle during replacement. |
| Terrain/material lookup — existing/reusable but incomplete | [ground_surfaces.gd](../app/physics/ground_surfaces.gd), `validate`, `build`, `build_airframe`; [ground_terrain.gd](../app/physics/ground_terrain.gd), `sample_validated`, `amplitude_for_rolling_factor`; [surface_friction.json](../app/data/ground/surface_friction.json) | Per-wheel rectangle precedence is already used. `runway` means maintained turf in the default field. Only runway/rotorpad/mown/rough types are accepted; asphalt/concrete names in crash presentation are not full field support. Roughness is inferred from rolling factor, including reserved rotorpad 0.5. |
| Hull support — existing/reusable/incomplete | [hull_contact.gd](../app/physics/hull_contact.gd), `prepare`, `loads`, `contacts`, `terminal`, `prop_disc_depth` | Soft hull forces allow slides. Outside lake coverage the ordinary hull/prop plane is not the wheels' full micro-relief query. Numerical penetration is not measured soil sinkage. More probes alone must not multiply stiffness or friction. |
| Obstacles/water — existing/reusable/incomplete | [scenery_collision.gd](../app/sim/scenery_collision.gd), session scenery/lake post-tick paths; [lake_collision.gd](../app/sim/lake_collision.gd), [impact_snapshot.gd](../app/physics/impact_snapshot.gd) | Swept/typed impacts and bounded responses exist. Reuse their crossing evidence, immutable inventory and accepted damage masks. Sparse aircraft proxies and moving gear/attachments remain coverage gaps. |
| Ground starts — existing/reusable | [ground_start.gd](../app/physics/ground_start.gd), `solve`, `_contact_feasibility`; session runway/reset setup | Start qualification solves supported geometry and checks stability. Extend to new roles/curved wheels; never spawn an invalid aircraft by clamping its altitude. |
| Steering — existing/incomplete | `GroundWheels.frame`; session control deflections; [control_surfaces.gd](../app/physics/control_surfaces.gd) | Signed steering follows actual rudder servo output. No general independent tiller, caster trail, tire aligning moment or shimmy dynamics. Authority must depend on N and tire traction, not a direct yaw-rate override. |
| Input sampling/mixing — existing/reusable/incomplete | [rc_input.gd](../app/input/rc_input.gd), `poll`; [commands.gd](../app/input/commands.gd), `shape_sticks`, `gamepad_yaw_response`; [controller_service.gd](../app/input/controller_service.gd), profile/store/actions; session `_inputs`, `_pre_step`, `_deflections` | Devices/calibration, expo/rates, trims, failsafe and actual servo positions already exist. Flap-elevator mix follows slowed flap travel before failures/servos; surfaces remain frozen across RK stages. Current recorded gear/brake channels depend on retractability. Extend versioned input/layout/capabilities for independent steering/differential brakes without bypassing hardware, focus release, failure ordering or replay. |
| Failure injection — existing/reusable/incomplete | [catalog.gd](../app/failures/catalog.gd), session failure adapter and `_pre_step` | Existing jam/bias/slow controls, throttle/radio-loss and finite-powertrain cutoffs are reusable deterministic commands. They do not constitute gear lock, mount fracture or physical servo topology; add those through declared mechanism/damage states. |
| Brakes — existing/incomplete | `GroundWheels.evaluate`; session `set_wheel_brake`, `gear_is_retractable`, `_inputs`; Main `_clear_wheel_brake`, `_input`, `_unhandled_input` | `B` supplies full brake and releases on key-up/focus loss. Session acceptance is gated by retractability; brake torque evaluation is inside loaded-contact logic and early airborne exit. No independent left/right channel or stopped-wheel constraint. |
| Retracts — existing/incomplete | [retractable_gear.gd](../app/physics/retractable_gear.gd), `advance`, `pose`, `drag_loads`; session `current_landing_gear`, `set_gear_down`, `gear_state` | Extension timing, interpolation, CdA force/moment and weight-on-wheels command inhibit exist. Inhibit is a simulator operator rule, not declared pneumatic hardware. Full mechanical support during intermediate states, per-leg locks/failures and door loads are missing. |
| Ground effect — existing/incomplete | [ground_effect.gd](../app/physics/ground_effect.gd), `factors`; `Aero` global/local wing and free-tail paths | Already modifies lift slope, induced drag/downwash continuously. Shared fit is approximate; add local clearance/planform evidence without multiplying the whole-aircraft lift a second time. |
| Propwash/shaft — existing/reusable/incomplete | [slipstream.gd](../app/physics/slipstream.gd), `stage_loads`; propeller, glow, electric and turbine evaluators | Tail wash is a washed-minus-free increment. Preserve installed capability and force bookkeeping; no universal throttle steering boost. Ground-effect interaction and wing wash remain model limits. |
| Prop strikes — existing/incomplete | session `_check_prop_strike`; `HullContact.prop_disc_depth`; `AircraftContactEvents.strike_event` | Turning prop contact can stop the engine and continue flight. Current 300 RPM trigger and disc proxy are explicit estimates; no complete stopped-blade orientation, shaft/mount failure or rotor impact-energy transfer. |
| Contact observations — existing/reusable | [aircraft_contact_contract.gd](../app/physics/aircraft_contact_contract.gd), `describe`; [aircraft_contact_events.gd](../app/sim/aircraft_contact_events.gd), `hull_events`, `impact_event`, `strike_event`, `validate_events`; session `_on_sim_stepped`, `contact_events` | Stable IDs, new/persistent/ended lifecycle and strict measurements exist. Support role is only `wheel_support`; ordinary wheel support is not a touchdown event. Schema is closed: adding fields requires versioned readers. |
| Terminal response — existing/incomplete | session `_crash`, `reset`, `reload`; `HullContact.terminal`, `GroundContact.collapsed` | Severe hull impact/depth and gear overtravel pause the flight. Separate accident classification from this control path. Preserve invalid-state fault containment. |
| Structural damage — missing as general flyable model | [crash guide](CRASH-DAMAGE-PLAN.md), existing `app/render/crash/`; proposed `app/damage/` owned by CR | Mesh breakup, debris and severity are presentation. They cannot silently change aircraft inertia, lift or control effectiveness. Structural calibration and continued damaged-flight topology need an explicit transaction. |
| Accident economics — existing/reusable/incomplete | [incident.gd](../app/economy/incident.gd), `observe`; [settlement.gd](../app/economy/settlement.gd); impact/thermal budgets and checkpoint/archive paths | Deduplication, bounded evidence and last-accident persistence exist. An inspection state or price does not prove damage. Keep economic assessment separate from physical failure and statistics. |
| Landing/takeoff evaluation — incomplete | [test_takeoff_roll.gd](../app/tests/test_takeoff_roll.gd), [p51_envelope_base.gd](../app/tests/p51_envelope_base.gd), `takeoff`; [landing_maneuver.gd](../app/sim/landing_maneuver.gd) | Maneuvers are test drivers, not a player event ledger. Do not copy their pilot commands or thresholds into physics. |
| Statistics — proposed baseline; concurrent implementation must be reconciled | [flight-statistics-plan.md](flight-statistics-plan.md), UI-FS-00…08 | Defines accepted-tick episodes, session/lifetime and per-aircraft totals. Current proposal calls M7 terminal crashes. This mission requires a survivable gear-up event to count as a crash; GP-14 must coordinate a rules-version change, not create a second statistics store. |
| Audio — existing/reusable/incomplete | [ground_audio.gd](../app/audio/ground_audio.gd), ground events/profile helpers, soundscape/powertrain code; crash audio | Rolling and touchdown layers already read accepted support and surface. Extend observations and layering for slip, brakes, strokes, mechanisms and materials; do not create another per-frame touchdown detector. §9 gives exact ownership. |
| Aircraft contract — existing/reusable/incomplete | [aircraft_contract.gd](../app/physics/aircraft_contract.gd), `validate`; [aircraft_data.gd](../app/physics/aircraft_data.gd), `load_file`, `validate_and_derive`, `_landing_gear`; [aircraft_modules.gd](../app/physics/aircraft_modules.gd), `classify` | Closed v2 quantities/capabilities, stable identity and separate rotating-wheel registry exist. Missing explicit wheel axle/axis, support roles, component topology and model-selectable advanced contact law. |
| Workshop — existing/reusable/incomplete | [parameters.gd](../app/workshop/parameters.gd), `validate`, `definitions`; [compiler.gd](../app/workshop/compiler.gd), `compile`, `_inherit_wheel_model`; descriptor/dependencies/trial/store | Current closed recipe transforms scale/mass/controls and inherits wheel profiles by name. It does not author arbitrary gear layouts or damage. Extend the compiler and source pins, not raw mutation of live aircraft dictionaries. |
| Logging/debugging — existing/reusable | [flight_log.gd](../app/sim/flight_log.gd), [trace.gd](../app/sim/trace.gd), debug bridge and tool index | Read-only bounded logs, exact replay, fault checks, contact tests and state inspection exist. Add versioned diagnostics and use existing viewers/plotting tools. No new test platform is justified. |
| Experimental truck solver — reusable mathematics, not drop-in aircraft law | [vehicle_dynamics.gd](../app/physics/ground_vehicle/vehicle_dynamics.gd), generalized wheel coupling/constraint solver | Useful coupling and constrained-friction precedent. Do not import truck suspension/drivetrain assumptions, native backend or qualified status into aircraft by inheritance. Extract only independently tested float64 primitives. |

### 2.3 Fleet and authoring sources

The initial audit recorded nine fixed-wing configurations. The 2026-10-26 native-capture catalog query now returns **ten fixed-wing configurations plus X-Cell**, including the installed Skywalker X8. Enumerate `AircraftCatalog.airplane_flyable_entries()` in acceptance; never hardcode a historical count. The [capture evidence](research/ground-physics/GP-19/evidence/native-continuous-timber/README.md) records the current IDs; adding a catalog aircraft does not qualify its advanced ground contract.

| Family / installed arrangement | Current source pipeline and migration focus |
| --- | --- |
| Ugly Stik baseline and 61FX/55AX/FS-64V variants; tricycle fixed gear | Base [jensen_ugly_stik_60.json](../app/data/aircraft/jensen_ugly_stik_60.json); glow variants via [build_installations.py](../research/glow-engines/build_installations.py); hull via [derive_stik_hull.py](../research/ground-physics/gp07/derive_stik_hull.py). Preserve GP-06b datum and GP-07 probes. Resolve the generator's 0.8 stiffness/damping scaling only with physical gear evidence. |
| Extra 300S; taildragger fixed gear | [derive_physics.py](../research/extra-300/ex05/derive_physics.py). Includes the current finite MAX-61FX installation. Test wheel pants, tailwheel angle, tail-raising, tip scrape and fuel-dependent CG. |
| P-51D; retractable taildragger | [derive_physics.py](../research/p51/p51-05/derive_physics.py). Retain installed brakes/CdA/force point; qualify circular wheel contact, main-gear loading and asymmetric mechanisms. |
| F4U Corsair; retractable taildragger | [derive_physics.py](../research/f4u-corsair/F4U-07/derive_physics.py), [ground_effect_vlm.py](../research/f4u-corsair/F4U-07/ground_effect_vlm.py), [fit_propeller.py](../research/f4u-corsair/F4U-07/fit_propeller.py) and [source manifest](../assets/aircraft/f4u-corsair-250/source.json). Preserve wing-fold/canopy/tailhook identities. Current manual-versus-simulator nose-over discrepancy is an open validation case, not permission for a pitch hack. |
| Ventage Jet / Avanti; retractable tricycle | [derive_physics.py](../research/avanti-s/av06/derive_physics.py). Current gear/brakes exist despite historical GP-05 gear-up-only prose. No propeller-strike module; intake and undercarriage contacts must stay distinct. |
| Turbo Lumber; fixed taildragger, electric and finite-pack selection | [derive_physics.py](../research/timber/tt07/derive_physics.py). Large wheels, soft-field geometry, nose-over margin and pack mass. Current model is flaps-up; flaps, ground effect and propwash are not simulated merely because the reference aircraft has relevant hardware/behavior. |
| Skywalker X8; installed wheel-less flying wing | [Guide](X8-PLAN.md), [generator](../research/skywalker-x8/X8-06/derive_physics.py), ideal and finite-pack aircraft data. Current [rest-geometry audit](research/ground-physics/GP-14/evidence/x8-rest-geometry/README.md) includes engine/elevon contact in a stable rigid facet; this is not compliant-landing qualification. Resolve actual support roles and clearance before authoring intended-belly landing credit. |
| Future wheel-less/flying-wing/glider arrangements | No new commercial model is required for solver qualification. Use analytical fixtures plus a suitable freely licensed model when an authored visual is needed. Permit explicit belly/skid support and absent propulsion; this requires a reviewed aircraft-module extension, not a fake set of three wheels. |

Generated physics, descriptors, model manifests and economics pins must be regenerated through their source pipelines. Preserve `airplane`, `propeller`, `*_hinge`, authored contact IDs and attachment IDs. A physics rollout must include all catalog routes and applicable Workshop/finite-resource variants.

### 2.4 Continuation review: current statistics and mechanical audio

The initial-baseline classifications above remain dated. A continuation review on 2026-10-25 inspected later source at HEAD `cb2924b3676b72ee49497c92fe742b0b1dcd2d9c`; these concurrent additions must be integrated rather than recreated. Source inspection does not establish their runtime qualification.

| Current addition | Verified ownership and behavior | Required plan adjustment |
| --- | --- | --- |
| [Flight statistics](FLIGHT-STATISTICS.md); `app/statistics/service.gd::begin_activity/_observe`, `detector.gd::configure/observe/_handle_terminal` | Service creates one pure accepted-tick detector through `fixed_wing_adapter.gd`; detector owns episode timers, flight transitions, incident/crash latches and snapshot state. Terminal handling still closes the flight. | GP-14 evolves this **one classifier**, with nonterminal accident semantics; it must not introduce a second session detector with its own takeoff/landing timers. Keep service, eligibility, aggregation and persistence ownership. |
| [AUD-16 mechanical audio](servo-retract-audio-implementation.md); `app/audio/flight_audio.gd::mechanical_snapshot/_process`, `mechanical_motion.gd::observe/transition_for`, `mechanical_audio.gd`, `mechanical_profile.gd` | Actual accepted servo/flap/retract endpoint deltas drive existing bounded players and closed presentation profiles. Frame sampling can miss start/stop/reversal between renders. | GP-19 migrates edge capture to accepted-tick batches and preserves playback/profile ownership. `mechanical_audio.retract_type` selects a sound, not physical pneumatic/electric hardware, downlocks or failures. |

The [source ledger](research/ground-physics/GP-08/sources.md) records the continuation review and exact sampled source identities. Current-source guides supplement the earlier plans; no feature is retroactively claimed at the original baseline.

## 3. RC flight and ground-dynamics research

### 3.1 Evidence hierarchy and conclusions

The [dated source ledger](research/ground-physics/GP-08/sources.md) retains primary URLs, access scope and what each source supports. Use sources for their actual domain:

| Evidence class | Useful conclusion | Limit on transfer to this simulator |
| --- | --- | --- |
| Rigid-body mechanics and constrained dynamics | Forces/impulses must obey virtual work, angular momentum and dissipation; effective mass depends on inertia and arm. | A correct equation does not establish aircraft-specific k, c, tire grip or strength. |
| JSBSim ground-reaction implementation/documentation | Existing free, auditable precedent for per-contact loads, static/dynamic/rolling friction and bogey/structure distinctions. | Do not transplant its full-scale coefficients or replace the OpenRC kernel. Review license before sharing code. |
| Project Chrono tire/terrain documentation | Distinguishes slip laws, contact assumptions and deformable soil models. Useful independent reference software. | Tire models requiring measured automotive curves or finite contact patches are not automatically suitable for small foam/rubber RC wheels. |
| FAA Airplane Flying Handbook | Supports qualitative tricycle/tailwheel handling, bounce mechanisms, crosswind control and configuration-dependent elevator effects. | Full-scale procedures, speeds and certification criteria are not RC measurements or simulator scoring thresholds. |
| Manufacturer RC manuals and actual fleet evidence | Installed gear type, wheel sizes, brake presence, retract sequence and cautions; geometry and component identity. | A manual's caution is not a calibrated force curve. Do not infer universal nose-over behavior from one design. |
| Phillips/Hunsaker ground-effect research | Ground effect depends on height/span, planform, aspect ratio and lift condition; induced drag/downwash are central. | A single fitted multiplier cannot claim whole-fleet RC validation, particularly with stall, bank, propwash and uneven ground. |
| GP-02/04/05/06/07 and retained flight research | Existing analytical checks, exact replay, numerical convergence, geometry and measured simulator outcomes. | Software-generated coast distances/drop heights do not validate actual grass, tires or aircraft strength. |

### 3.2 What must be measured

Use existing free tools: Python/NumPy/SciPy and plotting software already in the research workflows, manufacturer geometry/manuals, video tracking/reduction tools listed in [TOOLS](TOOLS.md), and CC0/compatible audio libraries. Do not author replacements for available tools or freely downloadable suitable assets. Asset selection still needs exact source, license and redistribution provenance.

The minimum independent RC dataset is deliberately small and discriminating:

1. **Static support:** weighed aircraft, per-wheel scale readings, fixed datum/CG, fuel state, wheel pressure/material and unloaded/loaded axle positions. Fit k from load–deflection, including uncertainty and nonlinearity. Repeat nose/tail/main support redistribution with known ballast.
2. **Drop response:** instrumented/video-tracked low-energy drops of a gear rig or representative aircraft under suitable supervision; capture pre-impact speed, stroke, rebound and attitude. Fit compression/rebound damping jointly with tire compliance. A 240 fps camera gives 4.17 ms frames; peak loads need suitable higher-rate instrumentation, not a differentiated noisy video claim.
3. **Coast/pull tests:** known mass, wheel radius, surface moisture/grass length, slope and wind. Separate low-speed breakaway torque from steady rolling force, and rolling resistance from sliding traction. Compare at several loads and speeds; do not fit drag to one powered takeoff distance.
4. **Traction:** controlled lateral pull and braked-wheel pull with measured N; record breakaway/sliding and combined-force behavior. A chassis that tips before sliding only bounds tire grip; it does not measure μ directly.
5. **Ground transitions:** synchronized control/RPM/video and reference airspeed where available. Record takeoff wheel unloading, nose/tail motion, spin-up and bounce, not just time-to-liftoff. Separate true airspeed from GPS/ground speed and local wind.
6. **Material/joints:** component-specific load/deflection or manufacturer limits for gear, doors, foam/wood/composite sections, attachments and prop/shaft. Use fixtures or published tests where available. Unknown strength remains unknown; do not destructively test an aircraft merely to fill a table.

Each receipt needs exact configuration, source identity, environmental conditions, measurement method, sample rate, uncertainty and excluded observations. Parameter fitting and validation use different runs. Publish confidence intervals or bounded ranges where possible. Reserve full-scale certification drop rules as labelled scenario conventions; they do not certify an RC model.

### 3.3 RC scale and pilot-control interpretation

For geometrically similar vehicles, mass, inertia, wheel size, Reynolds number and terrain-to-wheel ratios do not scale independently. Tire deformation, bearing drag and grass stem/soil resistance can dominate small wheels. Use `Re=ρVc/μ_air` for aerodynamic applicability and `roughness_amplitude/R`, `stroke/R`, wheel loading and `I_w/(mR²)` for contact comparisons. Workshop virtual similarity is a declared simulator transform, not a prediction that a commercial aircraft scaled to 10% has the same tire or aerodynamic behavior.

Tricycle nose loading and taildragger tail loading follow **forces and pitch moments**, including elevator effectiveness, tail wash, thrust-line moment, CG, braking and wind. A down-elevator command can increase nosewheel load in an applicable tricycle configuration, but not at zero effective tail dynamic pressure and not universally with crosswind/gusts. Up-elevator can increase tailwheel load in an applicable taildragger, while tail-raising and wheel landing require different control histories. Do not create universal control coaching from those tendencies. Crosswind techniques and safe limits remain aircraft/manual/pilot-specific. The simulation should expose the forces and reproduce controlled test cases; it should not force the expected attitude.

## 4. Mathematical physics model

### 4.1 Reference frames and one force ledger

Let `R_BN` map FRD body vectors to NED, `O` be the fixed body datum, `c` the live CG offset from O in body coordinates, `r_i` a contact arm from O, `ω` body angular velocity, and `v_O` the datum velocity. For static contact geometry:

```text
p_i,N = p_O,N + R_BN r_i
v_i,N = R_BN [v_O,B + ω × r_i]
r_i,CM = r_i - c
F_i,B = R_BNᵀ F_i,N
M_i,O = r_i × F_i,B
M_total,CM = M_total,O - c × F_total,B
```

Perform the total-load moment transfer **once**, in the owning finite-mass adapter, then supply `moment_cm` to `FixedDatumBody.derivative`; that function explicitly expects a CG-relative moment and handles the datum-acceleration correction. Do not transfer an already CG-relative wrench again. A moving axle/door adds its relative kinematic velocity; an independently spinning wheel adds `σ_i a_i × ρ_i`, where `ρ_i` is the contact offset from axle and `a_i` the positive spin axis. Contact velocity subtracts terrain velocity if a future moving-platform capability is enabled. Current fields are stationary.

For constant mass at its CG:

```text
m (dv_CM,B/dt + ω × v_CM,B) = F_aero + F_prop + ΣF_contact + m g_B
I_CM dω/dt + ω × (I_CM ω) = M_external,CM       # rigid locked-body case
```

Wheel rotors replace the second equation with the coupled formulation below. Finite-resource routes retain the existing co-moving efflux law; blindly adding `-I_dot ω` or a fuel-ejection thrust would be a separate, unjustified model change.

| Quantity | Sole authoritative owner | Explicit exclusion |
| --- | --- | --- |
| Gravity, kinematics, tick commit/fault | Shared kernel / selected qualified body derivative | Ground law does not add a second weight force. |
| Wing/tail/body aero and propulsive wrench | Existing Dynamics/Aero/propulsion/wash assembly | No ground observer, retract animator or tire law scales aircraft speed. |
| Wheel normal, tangential and rolling reactions | Selected version of GroundContact/GroundWheels | Native Godot aircraft collision impulses disabled/absent. |
| Wheel/body internal brake/steer reaction | Coupled generalized wheel dynamics | No additional hand-added spin correction after the coupled solve. |
| Belly/wingtip/skid reaction | HullContact or explicit intended skid support | Each authored feature belongs to one support owner; duplicate hull/wheel points are rejected. |
| Obstacle/water impulse | Existing accepted collision arbitration, extended with the same geometry IDs | A swept hit and compliant surface contact cannot both supply the same normal impulse. |
| Damage dissipation/topology | Damage transaction, with an explicit energy and momentum receipt | Presentation severity, debris and economics never alter physical state. |
| Scores, sounds, VFX | Accepted read-only observers | No forces, damage inference from loudness, or integration clocks. |

### 4.2 Normal support, weight distribution and continuous release

For terrain height `h(N,E)` measured upward, the surface is `D=-h` and outward normal is

```text
n = (-∂h/∂N, -∂h/∂E, -1) / sqrt(1 + h_N² + h_E²).
```

Define signed separation `g_i` positive outside the surface and compression `x_i=max(0,-g_i)`. Define compression rate positive while closing, `x_dot=-g_dot`. A first qualified effective normal spring/damper is

```text
F_el(x) = k x                       # linear starting model; k in N/m
U_el(x) = integral_0^x F_el(z) dz    # ½ k x² in the linear case
N_i = max(0, F_el(x_i) + c(x_i,x_dot_i) x_dot_i), if x_i>0; else 0
F_normal,i = N_i n_i.
```

Compression and rebound damping may differ, with nonnegative coefficients. Preserve a documented contact-onset ramp if necessary for a continuous force at `x→0`; its width is a numerical/model parameter and must pass refinement. A damper cannot pull the wheel into the ground. The force/gap Jacobian and elastic energy must use the same geometry. Current local-tangent compression and `-n·v` differ on curved terrain at finite penetration; GP-10 must either use a closest-point gap with its derivative or qualify the current approximation only inside a measured micro-relief/penetration envelope. Generic hills cannot inherit that qualification.

For this clipped unilateral law the actual normal dissipation is `P_diss,n=(N-F_el) x_dot≥0`, not always `c x_dot²`. They agree while the unclipped force is nonnegative; when rebound clips N to zero, use `-F_el x_dot`. An onset ramp that changes elastic force must also change its integrated potential. This distinction is required in bounce/damage energy receipts so clipping is neither hidden energy creation nor overcounted damper work.

For nearly level motion, projecting Newton's law upward gives

```text
ΣN_i = mg - F_aero,up - F_prop,up + m a_CM,up.
```

Thus `N≈W-L` is only a **quasi-static aggregate check** when vertical thrust, acceleration, slope and other forces are negligible. Never allocate it equally to wheels. Individual forces must also satisfy pitch/roll moment balance. For two equivalent fore/aft supports on flat ground, measured static reactions satisfy `N_front+N_rear=mg` and `x_front N_front+x_rear N_rear=0` about CG; the same equations include tail/thrust/braking moments when present. This gives a useful independent scale-load oracle.

During takeoff, the aero and propulsion laws stay active at every stage. Increasing lift generally reduces aggregate support, but elevator tail downforce, rotation and vertical acceleration can temporarily increase a particular wheel load. As compression/reaction vanishes, its rolling and traction forces vanish. Keep wheel spin, shaft/wash states and aero continuous through release. **No airspeed threshold, friction toggle, minimum liftoff force or velocity jump is permitted.** State-machine hysteresis in §8 affects records only.

Touchdown reverses support acquisition, with contact-point velocity including pitch/roll/yaw. A hard one-wheel or nosewheel touchdown may be severe despite modest CG sink rate. Predict first touch using swept geometry and stage/substep refinement; do not wait for a deep endpoint penetration to manufacture a large impulse.

### 4.3 Suspension travel, bounce and bottoming

**Realistic bounce is a required outcome, not a defect to suppress.** Keep these mechanisms separate:

| Mechanism | Energy source and observable signature | Correct response |
| --- | --- | --- |
| Elastic gear/tire rebound | Stored `U_el` returns during extension; damper work reduces it. | Simulate compression/rebound and changing load. Do not zero vertical velocity at touchdown. |
| Taildragger aerodynamic bounce/balloon | Main-wheel reaction ahead of CG raises pitch/AOA; aerodynamic redirection can convert remaining forward kinetic energy into climb even with power off. Ideal lift in still air does no total work; propulsion can supply additional work when powered. | Continue aero at all stages. Compare aero-disabled, power-off and powered cases; log total `F·v` and vertical power separately. |
| Roughness-induced hop | Wheels traverse a known height profile; body/gear exchange gravitational/elastic energy. | Use actual surface wavelength/height and load transfer. No random vertical kicks. |
| Bottom stop | Stroke is exhausted and a much stiffer local compliance engages. | Add a measured/declared progressive stop and its energy; check overload. Do not simply enlarge travel until a test passes. |
| Yield/break/collapse | Plastic strain, joint fracture or bent geometry dissipates energy and changes future support. | Commit per-leg damage, reduce travel/stiffness/geometry as authored, and allow belly support and continued dynamics. |

Initial normal support is a lumped **effective leg+tire compliance**, justified for the available data. It must not claim an independent unsprung suspension mode. Author an optional two-stage leg/tire or unsprung module only when measurements demand it. Springs in series satisfy `1/k_eff=1/k_leg+1/k_tire`; applying both complete reactions in parallel is wrong. For an oblique massless strut with compression axis `a_s`, geometry and virtual work give `N(n·a_s)=F_strut`, with positive compression defined consistently. Reject a near-zero projection for that model; do not divide through a near-horizontal strut without lateral/bending support physics.

Separate `stroke_m` (mechanical travel), `tire_deflection_m`, `stop_deflection_m` and numerical overlap. A progressive stop can use `F_stop=k_stop max(0,x-stroke)^p`, `p≥1`, plus nonnegative dissipative damping, with `U_stop=k_stop excess^(p+1)/(p+1)`. Values need component evidence or an explicitly bounded estimate. Failure criteria (§8) evaluate load/moment, absorbed energy and geometry; crossing `stroke_m` alone is not proof of fracture.

For an isolated linear underdamped mode, `ω_n=sqrt(k/m_eff)` and `ζ=c/(2 sqrt(k m_eff))`. The textbook rebound ratio `exp(-πζ/sqrt(1-ζ²))` applies only to that ideal mode and boundary convention; unilateral clipping, damping onset, multiple legs, aerodynamic work and plastic loss change it. Use it as an analytic fixture, never as the aircraft's universal bounce coefficient.

**Heavy aircraft tests:** increasing mass with the same gear changes sag, modal frequency, load distribution and impact energy; `E_n≈½m_eff v_n²` grows with effective mass and quadratically with impact speed. A larger aircraft with appropriately stronger gear need not fail earlier than a small one. Full/reserve fuel, ballast changes, high CG, asymmetric touchdown, forward speed, pitch rate and load on each leg must be explicit. Do not break every aircraft above a global mass or sink-rate threshold.

### 4.4 Wheel rotation, inertia and generalized energy

Retain a relative rim-speed state `u_i=R_i σ_i`, m/s, where `σ_i` is wheel spin relative to its carrier. On flat terrain with heading `t`, outward `n`, rightward tangent `s=t×n`, positive forward spin axis is `a=-s`. The no-camber longitudinal slip velocity is

```text
v_slip,long = v_locked_contact·t - u_i.
```

For arbitrary geometry use the full contact Jacobian, including `σ(a×ρ)`, rather than assume the radius projects identically at all camber angles.

If `I_locked` includes the wheels locked to the aircraft **once**, the rotational/relative-spin kinetic energy is

```text
T = ½ m |v_CM|² + ½ ωᵀ I_locked ω
    + Σ [(J_i/R_i) u_i (a_i·ω) + ½(J_i/R_i²)u_i²].
```

The angular/wheel generalized mass blocks are

```text
M_ωω = I_locked
M_ωui = (J_i/R_i) a_i
M_uiui = J_i/R_i²
M_uiuj = 0, i≠j                         # fixed hubs, separate axial rotors
```

Validate the assembled matrix and residual `I_locked-ΣJ_i a_i a_iᵀ` as positive definite. If authored inventory only provides a box/point approximation, record the rotor inertia partition explicitly and reject an impossible split. Translational wheel mass is already in inventory; do not add it again as a separate sprung mass.

At each RK stage solve

```text
M(q) z_dot = Q_external + Q_internal - b(q,z)
Q_contact = J_contactᵀ F_contact
Q_ui,contact = a_i·(ρ_i×F_contact)/R_i
Q_ui,brake = -τ_brake/R_i
```

`b` includes body-frame transport, gyroscopic terms and changing-axis kinematics. Reuse [generalized_coordinates.gd](../app/physics/generalized_coordinates.gd), `factor_body_local`/`solve_body_local`, and the qualified finite-datum mass adapter. The new aircraft stage may return `body_derivative`; SF must explicitly qualify this use alongside finite-resource derivatives. Do not also add today's independent `spin=J/R*u_dot` correction. Internal braking conserves total angular momentum when isolated and dissipates `τ_brake σ`; it works airborne and at zero ground grip.

`factor_body_local` is a structured solve: local coordinates couple to the body but its local-local block must be diagonal. Current code does not validate or use off-diagonal local entries. Validate symmetry and this structure before selecting it. Independent fixed-axis rotors satisfy the assumption; dynamically coupled caster/steering/spin/suspension coordinates may not. For those, reuse the existing `cholesky_factor`/`solve_cholesky` through a separately qualified full-SPD consumer with finite/symmetry checks. An unsupported local coupling rejects the configuration; it is never silently discarded as an approximation.

For the first **fixed-hub, fixed-axis, constant-inventory** reference, the rotational equations are explicit:

```text
h_B = I_locked ω + Σ (J_i/R_i) u_i a_i
I_locked α + Σ (J_i/R_i) a_i u_dot_i = M_external,CM - ω×h_B
(J_i/R_i) a_i·α + (J_i/R_i²)u_dot_i = (τ_external,axle_i - τ_brake_i)/R_i
```

External contact moments enter the first row at their actual contact arms and the wheel row through axle torque; this is the same force represented by virtual work, not two forces. Internal brake torque enters only the relative-coordinate generalized force; its opposite carrier reaction emerges from the coupled angular equation. Preserve separately installed engine/propeller angular momentum and its qualified exchange without counting it among wheel rotors again.

Moving hubs/axles require more than substituting a time-varying `a_i` into that fixed-geometry formula. Assemble component kinetic energy from `v_j=J_vj z+v_prescribed,j` and `ω_j=J_ωj z+ω_prescribed,j`, then derive the mass, affine momentum and transport/bias terms consistently. Each component contributes `m_j J_vjᵀJ_vj + J_ωjᵀ I_j J_ωj`; prescribed-rate cross terms and derivatives produce the required bias/work channels. Use the complete inventory once, replacing its corresponding locked partition. Qualify analytic derivatives against independent finite-difference energy/momentum fixtures offline. Finite-fuel routes retain their existing co-moving efflux balance; the closed-system formula is not permission to introduce a spurious `I_dot` fuel torque. GP-13 may use a declared negligible-mechanism-inertia approximation only if bounded and independently tested, never silently omit moving-axis work.

**Energy-balance counterexample, algebraic source audit only:** declare one fixed axisymmetric rotor with `a=-y`, `I_locked,yy=1 kg·m²`, `J=0.1 kg·m²`, `R=0.2 m`, body pitch rate `q=1 rad/s`, relative rim speed `u=3 m/s`, no brake/rolling loss and zero tire slip. Impose a pure carrier pitch moment `M_y=-1 N·m`. At this instant `GroundWheels.evaluate` gives `u_dot=0`, hence no spin correction, and the current uncoupled body equation gives `α_y=-1 rad/s²`. The declared residual body inertia is `I_locked,yy-J=0.9>0`.

```text
T_rot = ½ I_locked,yy q² - (J/R)u q + ½(J/R²)u²
∂T/∂q = 1 - 0.5*3 = -0.5
∂T/∂u = -0.5 + 2.5*3 = 7
current T_dot = (-0.5)*(-1) + 7*0 = +0.5 W
external power = M_y*q = -1 W
unexplained balance residual = +1.5 W
coupled α_y = -1/0.9; u_dot = 0.2*α_y; coupled T_dot = -1 W.
```

The contact instant can be realized with `r=(0,0,z)`, upward normal, zero side/normal velocity and `v_CM,x=3-qz`, so the normal contributes no pitch torque or power. Gravity/normal can balance; this is not asserted to be a sustained no-slip trajectory. An airborne fixed-axis rotational fixture gives the same missing coupling. The calculation assumes axial rotor inertia is included exactly once in `I_locked`; stock inventory partition must be audited before applying it to any actual aircraft. Independent scalar arithmetic first reproduced these values. **Implementation amendment:** [GP-09a](research/ground-physics/GP-09/README.md) now reproduces the residual against `GroundWheels.evaluate` and `RigidBody.derivative`, with a separate coupled reference and arbitrary-axis energy/momentum tests. No measured aircraft defect or physical calibration is claimed. An additive energy oracle without cross terms cannot qualify the remaining moving-axis/shaft integration.

### 4.5 Traction, static friction, rolling loss and brakes

Let wheel-plane slip components be `w=(v_slip,long,v_slip,lat)`. Longitudinal slip ratio and slip angle are useful telemetry above a declared low-speed range:

```text
κ = (Rσ - v_long) / max(|v_long|, |Rσ|, v_reg)
α = atan2(v_lat, max(|v_long|, v_reg))
```

Retain sign conventions in reverse explicitly; the force law uses physical slip velocity at/near zero rather than dividing by speed. The first coupled reference keeps the existing finite-slope law under a new identified formulation, so geometry/inertia corrections can be tested separately from tuning.

For isotropic friction, `sqrt(F_t²+F_l²)≤μN`. If measured anisotropy justifies it, use `(F_t/(μ_xN))²+(F_l/(μ_yN))²≤1`. Static and kinetic friction are distinct: a static reaction cancels a feasible external tendency; sliding traction dissipates slip power. Tire braking and cornering share one limit. An independent full lateral limit plus full brake limit overestimates grip by up to `sqrt(2)` in the isotropic case.

The selected P1 refinement is a **pure-stage, finite-relaxation constrained-force solve**, reusing the truck's tested mobility-metric mathematics. With all contact tangent/brake rows assembled:

```text
W = J M⁻¹ Jᵀ
c_free = J M⁻¹(Q_free-b) + J_dot z + prescribed_geometry_bias
target = -w/τ_relax
solve bounded reactions so W λ + c_free approaches target
subject to each tire's coupled traction cone and each brake's torque bound.
```

A concrete stage formulation minimizes `½λᵀWλ + λᵀ(c_free+w/τ_relax)` over those convex bounds, additionally enforcing each sliding contact's `λ_i·w_i≤0` and each internal brake's nonpositive relative power. At exactly zero slip, the dissipation half-space imposes no restriction on a static reaction. For isotropic tires the local bound is a disk of radius μN; measured anisotropy gives an ellipse. Use nondimensional row scaling and a declared minimal numerical regularization only for redundant/singular rows, reporting its magnitude/residual. Do not Euclidean-clamp an unconstrained anisotropic mobility solve and assume it is the metric projection. If bounded iterations cannot satisfy feasibility/passivity/residual tolerances, reject the candidate or choose the already qualified reference law at session creation; do not switch force laws mid-impact.

Use a small deterministic active-set/metric-projected iteration in stable contact-ID order. Freeze its sweep cap/tolerances in the law identity; verify feasibility and stationarity/complementarity residuals, not just small update size. Sliding reactions must satisfy `F_t w_long+F_l w_lat≤0`; internal brake power must be nonpositive. A static constraint at zero slip may carry nonzero force with zero work. Any regularized transition that stores/releases elastic tire/anchor energy must expose that energy in the ledger. Do not accept a force solve that satisfies acceleration targets while injecting unexplained contact energy. At load loss the feasible tire reaction becomes exactly zero; brake rows remain active independently of N.

**Rolling resistance:** `F_rr≈C_rr N` is an equivalent steady rolling-force approximation, not available traction. In the initial coupled reference retain the old explicitly identified force approximation for isolated comparison. The selected refined law uses a dissipative wheel-ground resisting couple with magnitude `M_rr≈C_rr N R`, opposing the wheel's absolute rolling angular motion, with near-zero static torque bounds and separately authored bearing drag. Its generalized body and wheel work must equal that of the same external couple; do not add `C_rrN` force as well. In steady no-slip rolling it gives the equivalent force above. Soil/vegetation drag is a separate external resistance with an identified application point and power ledger; do not disguise it as brake friction.

Brake capability is independent of retractability: `none`, shared proportional axle braking, or independent channels. `τ_brake,max` is N·m, not a vehicle deceleration. At zero spin, a bounded static brake reaction can hold the wheel; with excess applied torque the wheel turns, and with insufficient ground traction the locked wheel skids. Braking limits and tire grip remain separate. Never clamp aircraft velocity to a brake target.

### 4.6 Stability, impulses and conservation gates

Rigid-body point normal effective mass is

```text
m_eff,n⁻¹ = 1/m + (r_CM×n)ᵀ I_CM⁻¹ (r_CM×n).
```

The generalized form is `W_nn=J_n M⁻¹J_nᵀ`; its off-diagonal entries couple multiple contacts. Spring, damper, friction, anchor and brake modes must be bounded together. `sqrt(Σk/m)` and `dt/τ` alone are insufficient. Build an offline linearization/eigenvalue or conservative matrix-bound oracle over admitted mass/CG/attitude/load ranges. RK4's approximate negative-real stability limit 2.785 and imaginary-axis limit 2.828 are boundaries, **not accuracy targets**. Start with `ω_max dt_sub≤0.25` and decay-rate `λ_max dt_sub≤0.5` as conservative proposed engineering guards, then validate complex modes and nonlinear refinement. These are acceptance-policy choices, not gear properties.

Choose substeps before a swept contact can enter, using wheel/hull reach, point translational+rotational speed, mechanism speed and terrain bounds. Kernel maximum is 16; current GP qualification is narrower (up to 8). Exceeding a qualified bound returns a numerical/configuration diagnostic and preserves the last accepted state. It must not silently soften k/c, skip contacts or be recorded as a physical crash.

The chosen P0/P1 design keeps compliant normal force and RK4. Ideal impact impulses are an **alternative only if measured stiffness/cost or contact error fails GP-22**. For that alternative use `j_n=-(1+e)v_n/W_nn` only for an isolated approaching contact; simultaneous contacts require a coupled unilateral solve. Clamp neither body nor wheel independently. Do not apply restitution impulse on top of an already energy-rebounding penalty impact. Current `post_tick_joint` can only return body state; a combined-state impulse implementation requires an explicitly qualified generic policy and composition with shaft/fuel/battery boundaries. It is not a hidden local fix.

## 5. Ground contact and terrain

### 5.1 Explicit shared surface query

Extend `GroundSurfaces` and `SimulationEnvironment` with one immutable versioned query contract, used by wheels, hull, prop, gear doors, obstacle support, ground effect, audio and VFX:

```text
sample_support(position_NED, footprint, stage_time, environment_identity) ->
  valid, support_geometry_id, material_id, region_id,
  signed_gap_m, closest_point_NED, outward_normal_NED, surface_velocity_NED,
  profile_index, geometry_derivatives_or_validity_bound, coverage_status
```

Use float64 packed arrays for hot numeric channels and stable integer IDs into immutable registries; strings/dictionaries belong to setup and detached observations. Explicit `no_surface`, invalid query and unsupported geometry are different outcomes. The field's current ordered rectangles remain a reusable region map; retain their overlap precedence and outside region. Regions identify usage (`runway`, `rotorpad`) separately from material (`maintained_turf`, `asphalt`, etc.). A runway can be grass. A bare empty-table flat fixture keeps its named dry-pavement semantics.

Version the existing six-float surface representation through an adapter rather than silently append a seventh value: helicopters, truck courses, checkpoints, render shaders and tests also consume it. For v1, map each legacy region to explicit material/roughness fields preserving old coefficients and exact empty-fixture behavior. For v2, roughness never comes from `rolling_factor`; remove the rotorpad 0.5 selector by explicit `height_profile=flat`. Keep old readers for old identities.

### 5.2 Material behavior and profile fields

| Surface | Expected behavior to model | Parameters/evidence required; limits |
| --- | --- | --- |
| Smooth asphalt/concrete | Small load-bearing roughness and rolling loss, predictable dry grip, higher body abrasion than grass in many material pairs | Separate tire μ_s/μ_k, Crr, material-pair hull friction, spectral/height profile, wear/impact transfer and sound. Asphalt and concrete remain distinct IDs even if a provisional profile shares values. |
| Maintained runway turf | Current default field; more small-wheel rolling loss and grass noise than pavement | Grass length/moisture, soil firmness, wheel radius/load dependence and measured drag. No assumption that green color establishes traction. |
| Mown/long grass | More vegetation drag, possible wheel trapping and reduced directional control; roughness may unload a wheel | Keep tire grip independent of vegetation drag. Do not force Crr to rise whenever roughness rises. Long stems and soft soil are distinct mechanisms. |
| Firm dirt | Dust and texture/compaction dependent grip/drag | Dry/wet state only if authored and tested. Do not derive physical mud from weather VFX alone. |
| Gravel | Granular displacement, local variation and audible texture; potential reduced lateral traction | A first rigid-terrain profile is an effective model. Loose-particle displacement/sinkage needs a later terrain law. |
| Rough/damaged hard surface | Potholes, edges and bumps increase impacts despite low average rolling drag | Geometry must contain the defect with resolution/sweep coverage adequate for R and speed. No random force spikes. |
| Optional soft soil/sand/mud | Sinkage and ploughing can consume substantial work, reduce clearance and cause nose-over | Opt-in pressure–sinkage/shear law with wheel width/contact area, calibrated soil parameters, independent terrain deformation state and energy accounting. Numerical penalty overlap is not soil sinkage. |

`GroundSurfaceProfile` fields: immutable ID/version, physical material class, tire interaction class, `mu_static`, `mu_kinetic`, optional directional ratios, rolling-law selector/coefficients, bearing-independent vegetation term, roughness geometry/spectrum/seed, contact stiffness only when soil compliance is actually modeled, hull material-pair law, audio/VFX tags and provenance. Physical quantities carry units and evidence. No universal coefficient table is asserted here: seed profiles preserve existing values with `borrowed/estimated` status; new materials remain experimental until measured or credibly bounded.

Height is spatially deterministic: the same point yields the same sample at every RK evaluation, regardless of FPS or contact iteration count. Roughness bandwidth must be resolved by contact footprint and sampling; high-frequency grass blades are an audio/render cue unless they represent load-bearing geometry. Store sample phase/seed in environment identity. A wheel-sized footprint filters sub-resolution geometry physically; increasing render quality must not change the physical field.

### 5.3 Round wheels and hull agreement

For a thin circular wheel with unit axle `a`, hub `p_h` and surface normal `n`, compute `b=n-a(a·n)` and `ρ=-R b/|b|`; `p_contact=p_h+ρ`. Re-sample slope at the candidate with a bounded deterministic closest-contact iteration. At near-degenerate `|b|`, select a declared finite-width/sidewall support shape or transfer to a named nonrolling feature; do not invent a forward tangent. A finite-width cylinder/rounded tire is the later geometry option for high camber and curb contact.

Author hubs, axes, tire width and radius; derive contact points. Migrate level-bottom legacy data by a reviewed inverse transform, not a guessed display-node axis. Use the same geometry for loads, travel, render compression, prop clearance, swept obstacle queries and damage. Keep mesh and physical support comparison at several pitch/bank/retract fractions, not only the build pose. Preserve GP-06's P-51 rest-angle discrepancy as a regression.

Hull, prop disc and wheel queries must agree on the physical ground surface. Reuse GP-07 hull-generation/coverage tools across the fleet. Adding probes must preserve a bounded distributed support stiffness/damping and energy budget; otherwise mesh-detail changes would change bounce and damage. Treat a scraping wingtip as a contact patch feature with consistent area/material mapping, not N independent copies of the entire wing strength.

## 6. Landing gear configurations

### 6.1 Reusable mechanical configurations

| Arrangement | Required authored mechanisms | Dynamic behavior and qualification |
| --- | --- | --- |
| Fixed tricycle | Two main supports aft of CG, steering nose support, signed steering axis/range, actual brake hardware | Static nose share; elevator/thrust/brake load transfer; nosewheel unloading during rotation; loaded steering versus unloaded caster; lateral tip and nose-over boundaries. Shimmy is optional, never a cosmetic yaw oscillation. |
| Fixed/retractable taildragger | Mains ahead of CG, tailwheel or skid, linkage/caster/lock behavior, prop clearance | Tail raise removes rear steering load naturally. Ground-loop divergence comes from geometry, lateral tire reaction and inertia; three-point and wheel landing use distinct pitch histories. Brake and drag can pitch nose-down. |
| Retractable tricycle | Per-leg deployment path and locks, doors where installed, brakes/tiller declared separately | Nose/mains during rotation and landing, partial/unequal extension, door/belly contact and realistic drag increments. |
| Wheel-less belly landing | Intended belly/skid support feature IDs and materials, allowed attitude range, no wheel state | Normal belly landing can be successful for this configuration. It is not a gear-up accident when gear was never installed. Unintended wingtip/prop damage remains distinct. |
| Hand-launched glider/flying wing | Explicit absent gear/propulsion capability as appropriate, launch state/force policy, elevon or other control topology | No fake wheel masses or automatic launch speed. Ground support, trim, launch eligibility and landing classifier must accept the actual geometry. |
| Nonstandard gear/skids | Explicit count/roles/axes, intended support sets and qualified contact law | Do not retain the current minimum-three-wheel assumption for all support types. A tandem or two-skid model needs its own equilibrium/coverage proof. Floats remain a separate water-contact capability. |

### 6.2 Steering and shimmy

Stage steering reads the accepted actual actuator output, not raw keyboard/radio demand. Preserve current signed tailwheel conventions from `ControlSurfaces` and gear data. Provide optional input mapping to `steering`, `brake_left`, `brake_right` and `brake_common`; no brake hardware means a recognized inactive channel with no force. Retain throttle arming/failsafe/focus-release behavior.

For a linked wheel, compute target angle from the declared linkage ratio and servo limits/rate. Force authority emerges from `N`, tire law and contact orientation. A speed-dependent steering limiter is allowed only as a declared transmitter/control assist or measured servo/load behavior, with its identity recorded; it is not an unexplained physics yaw gain. Differential brakes act through wheel torques and lateral lever arms.

Free-caster/tailwheel lock/shimmy is an optional P3 mechanical module: `I_δ δ_ddot = M_trail + M_align + M_link - c_δ δ_dot - M_friction`, with trail, caster, inertia, damping, stops and linkage compliance. Tire slip and contact-patch state generate aligning moment. A high-speed oscillation requires that model and timestep qualification; otherwise report shimmy as unsupported. No sinusoidal steering perturbation is called shimmy.

### 6.3 Retract state and moving contact

Replace the one common fraction only when installing the versioned per-leg module. Each leg has command, actual extension `q∈[0,1]`, rate, up/down lock, optional jam/bent/failed mode and its cause evidence. Doors have their own declared schedule/interlock or kinematic relationship. Preserve the old module as a compatibility reader/law.

Moving path geometry must return position, orientation and their derivatives at stage time. A visual hinge is a binding target, never the physical authority. Distinguish deployed/unlocked/locked support capacity: a partially extended leg can strike, fold or bear a bounded load according to its geometry/lock strength. It cannot become noncolliding simply because `q<1`. End-stop/lock transitions generate one event and an energy receipt; no position/velocity teleport is allowed to cross the ground.

Weight-on-wheels command inhibit is an explicit simulator assistance policy. Record both pilot request and actual actuator state so a blocked request is not blamed for a later failure. If an installation has real squat-switch logic, declare it separately. Failure-practice injection must use accepted sampled/discrete state and deterministic seeds through the existing failures track.

## 7. Aerodynamic coupling

### 7.1 Takeoff and landing force budget

For each stage retain wing lift/drag, tail lift, side force, propulsion force/torque, ground reaction and their moments. Use air-relative velocity for aero and terrain-relative point velocity for wheels. The aircraft's acceleration is the resultant; no direct drag or acceleration multiplier is permissible. At constant density a local aerodynamic drag contribution is

```text
D = ½ ρ V_air² S C_D;
F_drag = -½ ρ (C_D A) |v_local,air| v_local,air.
```

Use force application points and `r×F` to obtain pitch/yaw effects. A gust changes both aero side force and wheel-load distribution; it must not simply change tire friction. Propeller torque, P-factor/swirl and gyroscopic effects remain with existing qualified propulsion models. The wheel solver consumes their resultant load.

Takeoff telemetry must explain any nonmonotonic wheel unloading: tail force or rotation may increase total N briefly even while wing lift increases. The isolated increasing-lift fixture should unload monotonically when all other vertical forces/moments are held appropriately; a real controlled takeoff need not do so at every sample.

### 7.2 Ground effect and tail flow

Reuse `GroundEffect.factors` and Aero's existing strip/free-tail machinery. Current GE is present on Stik/glow Stiks, Extra, P-51 and F4U; absent on Avanti and Turbo Lumber. F4U already has planform-specific image-method VLM work. Preserve absence on unsupported configurations rather than silently grant lift to every aircraft.

The current height query under the datum/CG is reused for strips. Extend to local strip/wing-plane clearance only through the shared terrain sampler, with a declared slowly varying ground-plane approximation. Bank and unequal wing height affect moments. At large height the new module must become exactly inactive or reproduce its accepted asymptote; low/negative clearance is handled by bounded aerodynamic domain plus physical contact, not infinite GE lift.

Current `Slipstream.stage_loads` adds washed-tail minus free-tail load; GE is not threaded consistently through that increment's tail baseline. The correction is a shared stage-local tail-flow context, used in **both** free and washed evaluations, then one subtraction. Do not append an extra tail GE moment to the existing totals. Preserve wake-transport state, stage time and frozen inputs; avoid algebraic feedback where a force uses its own already-corrected result twice.

Add no-wash aircraft to the existing wash module only with installation/tail-immersion evidence. At zero free-stream speed, absent wash must give no invented elevator force. Propeller windmilling/coast, engine cutoff and damage must alter wash through accepted shaft/thrust state.

### 7.3 Fixed gear, retracts, doors and trim

`RetractableGear.drag_loads` already applies local-airflow CdA drag and a moment at an authored point. Current fully exposed CdA estimates are P-51 `0.022 m²`, F4U `0.0176 m²`, Avanti `0.020 m²`; these are source data, not universal values. Current extension scaling is linear and isotropic. Preserve those endpoints during the first mechanism migration before changing aerodynamic calibration.

Refined law: per-component projected-area/coefficient table versus extension, door angle and airflow direction; interpolate continuously with bounded derivatives and no negative drag work. Sum only **incremental exposure beyond the defined clean baseline**. Audit whether the main aircraft `CD0` already includes fixed gear or exposed retracted wheels; record a drag-accounting manifest. Do not add a second full fixed-gear drag force to a polar already fitted with that gear installed.

An aerodynamic component may have its own force point and pitching-moment coefficient if evidence supports one. Transfer moment once to live CG. Asymmetric gear/doors create asymmetric forces and yaw/roll naturally. Retraction does not grant a speed bonus; lower drag changes subsequent acceleration and equilibrium. Extending gear can change approach energy, required thrust and trim, with direction depending on installation.

The existing airborne trim solve is essentially the clean reference, not a gear-down/flapped landing trim qualification. Extend the existing trim query to accept frozen gear/flap/door/damage configuration; do not mutate the flight or solve a separate approximate equilibrium. Qualify clean/down/partial/asymmetric configurations and full/reserve fuel against the same Dynamics evaluator. Changed gear aero is a separately versioned candidate; preserve unrelated free-flight goldens.

## 8. Damage and crash architecture

### 8.1 Three independent decisions

Every accepted incident has three separate outputs:

1. **Classification:** touchdown, intended skid contact, unintended scrape, gear-up accident, component damage, crash, etc. This feeds the logbook and reports.
2. **Physical state:** measured/estimated deformation, fractured joint, locked wheel, unavailable control, lost propeller, disabled engine, changed mass/aero/contact topology, or `assessment_unknown`.
3. **Continuation:** intact/partly damaged model can continue; a model incapable of flight may still slide/roll; a numerical fault safely preserves its last accepted state; a supported destruction transition can transfer to physical wreck bodies. These are not interchangeable.

`FlightSession._crash()` currently pauses and sets crash state used by guards. **Do not call it merely to count an accident.** Preserve `_crash` as the legacy terminal adapter until explicit physical outcome/continuation contracts replace its callers. A valid gentle gear-up contact must emit `GEAR_UP_CONTACT` and one `CRASH` classification with `terminal=false`, keep integrating, and make the landing unsuccessful in statistics. It may produce little physical damage. A severe gear-up impact can produce a terminal structural outcome, but gear position alone cannot determine it.

### 8.2 Component structure and failure model

Extend CR's proposed `app/damage/` boundary; reuse existing physical IDs, inventory, contact events, `ImpactSnapshot`, economics impact/thermal budgets and failure-state patterns. Do not build a second crash director or price ledger.

| Component | Inputs / response | Required distinction |
| --- | --- | --- |
| Gear leg, mount, wheel/axle | Axial/bending/shear load, compression, stop contact, cumulative plastic/impact work; elastic → yielded/bent → collapsed/detached | Travel exhaustion is not automatic fracture; bent gear changes contact position/capacity. Each leg can fail separately. |
| Fuselage belly / skid | Normal load, pressure proxy/area, sliding work, local material, structural support graph | Intended skid/belly support differs from gear-up accident; thin decorative skin is not the entire fuselage's strength. |
| Wingtip, wing, stabilizer, control surface/flap | Contact direction/arm, section/joint loads, deformation and aero/control binding | Cosmetic scrape can leave lift/control intact; hinge loss or structural fracture alters the explicitly bound surface. |
| Gear doors | Hinge/edge contact, local load and travel; jam/detach | Door breakage must not remove whole gear support or invent a lost wheel. |
| Propeller / motor / engine mount | Rotor phase/swept envelope, local impact, shaft rotational energy, fracture/jam/load transfer | Current stop-and-continue is a reusable limited response. Broken blade, bent shaft and failed mount require distinct evidence and dynamics. |
| Antennas, pods, decorative bombs and external accessories | Authored attachment transform, mass/inertia, geometry, mount strength and optional drag | Small detachments should not destroy the whole aircraft. No attachment means no invented contact/damage. Decorative devices have no explosive behavior. |
| Wheel-less foam wing/glider | Intended support footprint, abrasion and structural limits | A clean intentional belly landing can succeed; unknown structure does not imply indestructibility or total failure. |

Physical damage state is a bounded component/joint state table, not a single global hit-point number. Suggested modes are `intact`, `yielded`, `jammed`, `fractured_attached`, `detached`, `unknown_assessment`, with mode-specific continuous variables only where necessary. A declarative mapping identifies affected contact geometry, actuator DOF, aero strip/section, propulsion installation and inventory item. IDs for hull probes, visual sections and inventory masses remain distinct; explicit bindings connect them.

### 8.3 Collision energy, overload and abrasion

For a single approaching point, the normal kinetic scale is `E_n=½m_eff,n v_n²`; for a rotating propeller include `E_rot=½J_prop Ω²` only through the shaft/contact exchange. Neither the aircraft's entire `½mV²` nor all shaft energy is automatically deposited into each contacted component.

For a compliant contact, integrate actual channel work. Fix the system boundary first: for a closed, constant-mass fixture use `E_mech=T_coupled_body_and_rotors+U_elastic_and_stops+U_anchor+U_gravity`. Define `W_boundary` as the declared aerodynamic, propulsive, actuator and moving-ground work at that boundary, excluding gravity already represented by potential and excluding the passive contact/internal-loss channels being measured. A force's work appears once. With gravity omitted from potential instead, its work must explicitly enter the boundary ledger; do not mix these conventions.

```text
W_damper = integral (N-F_el) x_dot dt   # equals c*x_dot² only in unclipped branch
W_slide  = integral max(0, -F_tangent·v_slip) dt
W_brake  = integral max(0, τ_brake σ_relative) dt
ΔU_elastic = U_after - U_before
E_dissipated = E_mech,before + W_boundary - E_mech,after
```

For finite fuel, transferred/detached bodies or other open boundaries, include signed energy flux `+E_in-E_out` using the same reference and mechanical-state convention before comparing this balance. Propeller/shaft energy already inside `T` must not be charged again as an independent reservoir. Report both gravitational potential and optional gravity-work diagnostics if useful, but only one enters a given balance. Summed channel dissipation must reconcile with this residual within its numerical/observation uncertainty; never allocate the same plastic/fracture work to several components.

Track gravity/aero/propulsion/actuator work so powered or aerodynamically redirected bounces are not called energy creation. Some energy leaves in ground deformation, heat and sound; only a documented fraction/work channel enters structural damage. Multiple simultaneous contacts share one event/work budget. Repeated scrape frames must add their incremental work, not re-charge the original impact kinetic energy every tick. Reuse CR's allocation arithmetic while retaining its provenance: current `ImpactBudget` is an isolated estimate with `accepted_work_observed=false` and a caller-supplied budget, not measured solver work. Current `ComponentResolver` reports inspection required, qualification unverified and production billing disabled. The new accepted-work producer must be independently qualified; allocations cannot exceed its available budget within numerical tolerance.

Each component profile supplies load axes, area/section proxy, elastic/plastic law and strength evidence. A first bounded combined overload criterion can be an authored interaction surface, for example

```text
η_load = (N/N_limit)^pN + (|V|/V_limit)^pV + (|M|/M_limit)^pM,
```

with the interaction/exponents justified for that component. `η_load>1` identifies exceeding the declared envelope, not universally instant fracture. A qualified brittle joint can break at its peak limit; a ductile wire leg follows a plastic work/rotation rule. Define `E_yield`, `E_fracture`, residual stiffness, permanent geometry change and rate dependence only with evidence or labelled experimental bounds. Abrasion can integrate sliding work per effective area, with a separate material-pair wear coefficient. Do not derive structural strength from `CRASH_DEPTH_M`, C0–C3 presentation classes or repair price.

**Threshold policy:** no universal joule, sink-rate or mass cutoff is proposed. Profiles must contain explicit units/provenance and a numerical test fixture for each onset/ultimate threshold. Missing strength yields `inspection_required/unknown` and the conservative previously qualified physical law; do not silently infer breakage. Structural experiments stay opt-in until their component evidence and conservation gates pass. The gear-up accident classification does not wait for calibrated structural thresholds.

### 8.4 Collapse, detachment and continued motion

At a committed leg failure, replace its healthy support law/geometry with the declared bent/collapsed leg and remaining wheel/strut features. Lost load transfers through the next coupled solve; belly, door or wingtip contacts may acquire support. Do not zero aircraft velocity, snap it onto its belly or delete all gear at once. Damping/plastic work must account for released spring energy; a broken spring cannot vanish its stored energy without a recorded dissipation/release allocation.

For component detachment:

1. Resolve exact inventory partition and attachment geometry before accepting the aircraft profile. Decorative mesh sections without mass/physics bindings cannot become authoritative debris.
2. At event time, in one common inertial frame use `v_i,N=v_O,N+R_BN(ω_B×c_i,B)` for a rigidly attached component center. Include declared relative mechanism motion and convert retained datum/CG velocities consistently. Internal wheel/prop spin belongs exactly once to its partition. Release impulses conserve common-frame total linear/angular momentum and satisfy `ΔT_release≤U_released+W_actuator-W_fracture-W_other_loss`. Fracture/plastic/damping work is a sink; previously dissipated energy cannot fund a release kick. No unbudgeted random impulse is allowed.
3. Recompute retained mass, CG and full inertia from inventory, preserving common-frame total linear/angular momentum and explicitly accounting fracture work. Fuel/battery/propeller resources belong to exactly one retained or detached body.
4. Remove/reconfigure only the mapped lift/control/propulsion/contact terms. Prefer preallocated bounded component/body blocks with active masks; do not resize the active Simulation layout implicitly. A changed layout requires a separately qualified generic atomic model transaction that preserves physical flight/observer continuity. Validate inertia, resource ownership, dimensions and geometry before commit; exhaustion of physical slots rejects the candidate with an explicit unsupported-outcome fault, never silently drops finite mass because a presentation pool is full.
5. Publish detached-body physical state and IDs to presentation. Native decorative debris may follow a detached authoritative receipt, but cannot push on the still-authoritative aircraft through a second collision solver. Debris that must interact physically requires the same qualified coupling owner.

A destroyed airframe may cease to be a qualified single rigid aircraft. Transfer once to an explicitly qualified wreck-body representation or stop with an honest unsupported-physical-outcome state. Never label a numerical singularity as a pilot crash. User restart/repair is explicit; failed reset preserves prior state, successful clean reinitialization clears damage and creates a new generation while keeping historical incident records.

Tick-boundary failure initially has at most one accepted-tick onset uncertainty, recorded in its evidence. This approximation must pass load/energy/refinement gates; brittle or strongly coupled failure that cannot do so needs a located, combined transaction before healthy support continues beyond the known break. Current scalar event-location callbacks do not already provide that capability.

### 8.5 Shared accepted event model

Retain low-level `openrc-aircraft-contact-events v1` compatibility. Introduce a strict v2 physical observation envelope and evolve the **existing pure UI-FS detector as the single flight/incident classifier**; use adapters for legacy observers. `FlightSession` publishes accepted physical facts and lifecycle receipts, not a competing takeoff/landing state machine. The existing service/adapter installs one detector per observed activity; other consumers subscribe to that instance's ordered output. An ineligible technical/Workshop route requiring semantic events uses the same pure detector through a nonpersistent observer, without enabling player totals. Unknown landing-credit geometry may disable success while still recording physical accident evidence. The kernel never owns scoring rules.

The detector alone owns episode timers, touchdown/bounce/rearm, success and semantic accident grouping. Physical component modes, accepted contact-work groups and contact IDs remain with physics; a contact-work grouping is not another landing classifier. UI-FS retains eligibility, aggregation, persistence and its M7 latch contract. Database record UUIDs may wrap immutable deterministic event IDs but cannot replace them in replay/deduplication. Proposed required envelope:

```text
format, rules_version, law_identity,
activity_id, generation_id, flight_id?, contact_episode_id?, accident_id?, event_id,
type, accepted_tick, substep_fraction?, sequence,
aircraft_id, configuration_hash, field_hash,
contact_ids[], component_ids[], material_id?, evidence_coverage,
measurements{units implicit in closed field names}, severity_status,
terminal, continuation, cause{classification, evidence_ids[], uncertainty}
```

IDs are deterministic from generation, accepted tick/order and stable entities, not wall time or display names. Bounded buffers retain overflow/coverage status. Events from rejected stages/ticks never escape; observers receive a detached committed batch after physical state and damage commit. A contact snapshot includes support load/geometry even when there is no new event. Crossing time is optional evidence; absent crossing is recorded with ≤one accepted sample interval uncertainty, not fabricated precision.

| Event | Definition and deduplication |
| --- | --- |
| `TAKEOFF` | Confirmed departure from actual supported state, retaining first loss-of-support time. An airborne spawn is `air_start`, never takeoff. No force depends on this confirmation. |
| `TOUCHDOWN` | First actual land support/contact after flight, with intended/unintended contact kind and pre-contact velocity. Spawn/reset priming emits none. Multiple simultaneous wheels share an episode with per-contact details. |
| `BOUNCE` | Separation/recontact sequence within the unresolved landing episode before confirmed rearm; store hop height, unsupported duration, wheel/hull set and energy channels. One record per resolved hop, not every unloaded tick. |
| `LANDING_SUCCESS` | Classifier resolves a clean controlled full stop or confirmed touch-and-go under versioned aircraft-aware rules; emitted once. Unknown coverage cannot earn success. |
| `TOUCH_AND_GO` | A qualified clean support window followed by confirmed re-ascent before full stop; same flight, one landing success with subtype. No arbitrary rollout deadline. |
| `GEAR_UP_CONTACT` | Belly/door/retracted-gear ground contact outside the authored normal support configuration of an aircraft that requires deployed locked gear. Always opens/joins an accident, even with negligible damage or a deliberate pilot-commanded gear-up landing. Authored wheel-less belly/skid support is exempt; pilot intention is not the exemption. |
| `CRASH` | One accident classification per `accident_id`, including survivable gear-up contact. `terminal=false` does not close flight or stop physics. Later severity/terminal escalation updates the same incident. |
| `COMPONENT_DAMAGE` | Accepted transition or incremental damage revision for a stable component ID; repeated ongoing scrape work updates its revision without replaying initial breakage. |
| `GEAR_FAILURE` | Accepted lock/jam/yield/collapse/fracture state change; can occur before or during ground contact. Preserve actual command/state and failure evidence. |
| `GROUND_STOP` | A kinematic supported-rest observation under explicit thresholds. It can describe a damaged/inverted aircraft and is not by itself `LANDING_SUCCESS`. |

Open an accident at the first qualifying event in a contact episode. Persistent scraping, changing material, additional damaged parts, bounce recontacts and subsequent terminal escalation share its ID. Close its active contact grouping after supported rest or confirmed airborne rearm; a new independent accident after rearm may have a new ID within the same generation. Keep historical IDs for deduplication. Semantic `CRASH` events and incident archives are per accident; **UI-FS M7 remains one crash/accident per activity generation**, latched by its first accepted qualifying event whether survivable or terminal. Later distinct incidents remain inspectable but do not increment M7 again. A separate per-accident total or terminal-crash metric requires its own versioned definition; never change the existing denominator silently.

### 8.6 Landing criteria and statistics compatibility

Reuse the UI-FS detector/reducer/store, including any concurrent implementation, rather than building a GP statistics service. Preserve its provisional classifier policies unless a separately reviewed version changes them: 0.5 s clean intended support, 2 s supported full stop, speed ≤0.5 m/s and angular speed ≤0.10 rad/s, 2 s airborne rearm, 1 s liftoff confirmation above geometry-relative clearance `max(0.25 m,0.1 span)`. These are **classification choices**, not force thresholds or physical validation. Review the existing ±15° roll / ±20° resting-pitch / ≤1 rad/s controlled envelope per configuration. Load/geometry observations replace reliance on a bare compression threshold as the new law evolves.

Normal wheel contact can begin on one main wheel; touchdown does not require all three. Stop-support sets must be explicit and use stable roles, including skids/belly when intentional. Brief bounces reset the stable-support timer but keep the episode; aerodynamic ballooning is not a second successful landing. Once a clean support window qualifies, departure retains that evidence until rearm. An unintended contact/gear-up accident disqualifies that episode even if the aircraft stops gently.

GP-14 must amend UI-FS M7, detector precedence, totals and conservation equations: the first nonterminal accident sets the generation crash latch and increments M7 once, but leaves airborne time and active-flight state running. If it later stops damaged, close as `damaged_stop`; if later terminal, close as `crashed` without another M7 increment. Later distinct accident events within that generation also leave the latch unchanged. A previous successful touch-and-go remains successful after a later unrelated accident. Store rules version; never silently retally historical terminal-only records as if nonterminal accidents were observed.

Continue the existing eligibility distinction: player flight totals versus sandbox Workshop trials, automation, debug-controlled runs, replay and AI companions. Pause, Home, failed reload, restore and scene switching must not create touchdown or reset events. Use committed lifecycle receipts; raw `resetting` is not proof of success. Statistics writing remains outside tick callbacks. Local lifetime/per-aircraft/session scope remains UI-FS-owned.

### 8.7 Gear-up cause without false certainty

Store actual leg fractions/locks, requested command history, inhibit state, actuator fault/jam receipts, timing and telemetry coverage. Possible classifications are `pilot_command_observed`, `mechanical_failure_confirmed`, `incomplete_extension_observed`, `mixed_evidence` and `unknown`. Incomplete extension is an observed state, not necessarily the root cause. A pilot-down command with jam receipt supports failure; a final up command alone does not establish intent, responsibility or what happened before the recording began. Never infer a mechanical fault solely from missing wheels or a pilot error solely from a belly mark.

## 9. Audio architecture

### 9.1 Preserve and correct the existing path

Actual foundations are [ground_audio.gd](../app/audio/ground_audio.gd) and [ground_audio_model.gd](../app/audio/ground_audio_model.gd), with flight/helicopter audio and crash audio. `GroundAudioModel.snapshot_contacts()` currently reevaluates ground forces from accepted state and uses a frame-polled contact observer. This is read-only, but can miss brief contacts between rendered frames and duplicates work. Its `surface_name()` maps `runway/rotorpad` to `hard` and rough/outside to `gravel`; that disagrees with the default turf field and crash audio's turf mapping.

GP-19 first replaces those material aliases and frame-only touchdown detection with the accepted contact batch from GP-10/14. Keep existing rolling assets, bounded player pools, smoothing and pause behavior; do not recreate the audio engine. Audio assets/profile IDs remain separate from physical identity, while event and material IDs connect them.

The later AUD-16 path already owns servo/retract playback: `FlightAudio.mechanical_snapshot/_process` feeds `MechanicalMotion.observe/transition_for`, `MechanicalAudio` and `MechanicalProfile` (current [mechanical-audio guide](servo-retract-audio-implementation.md)). Migrate its transition capture to accepted-tick batches as part of the same observer change so a complete movement/reversal between rendered frames survives. Preserve existing players, profile/import semantics and Workshop presentation controls. A selected pneumatic sound does not identify real mechanism type, lock strength or installed door hardware. Physical mechanism evidence comes from the aircraft module, never from an audio profile.

### 9.2 Signal-to-layer contract

| Layer | Physical driver | Playback rule / realistic scope |
| --- | --- | --- |
| Smooth rolling | Loaded wheel, axle/rim speed, Crr/deformation work, hard-surface tag | Quiet continuous loop; fade to zero with N or motion. Airborne spinning wheels do not make pavement sound. |
| Turf/dirt/gravel rolling | Actual material and roughness excitation; load and speed | Crossfade material loops by contact load/coverage. Rough grass is not automatically gravel. Long grass can add a soft brush layer. |
| Touchdown/spin-up | Accepted first contact, normal impact energy/impulse, spin mismatch and slip work | One bounded one-shot per wheel/contact onset, coalesced for nearly simultaneous contacts. A rubber hard-surface chirp is optional; foam wheels on turf need not squeal. |
| Suspension/bottom stop | Compression rate, stop transition, transmitted impulse, intact/damaged mechanism | One impact/lock click per transition; rattle loop only with declared looseness/excitation. No pitch oscillation manufactured to make sound. |
| Tire skid / braking | Tangential slip power, N, material and brake hardware | Fade in/out continuously; braking with no slip need not squeal. Internal airborne brake may make a mechanism sound, not ground skid. |
| Nose/tailwheel vibration | Measured/simulated strut/caster response and surface excitation | Bounded filtered rumble/rattle. Do not imply shimmy when no caster dynamics exist. |
| Belly/wingtip scraping | Incremental sliding work, contact material pair, support footprint and speed | Separate foam/wood/plastic/metal banks where licensed assets exist; avoid metal scrape for foam by default. |
| Breakage/impact | Committed component transition and allocated impact/structural work | One-shot keyed by component transition ID; severity sets mix intensity, never physical damage. |
| Gear motors/doors/locks | Actual actuator rate, motor mode/load, door state and lock edge | Start loop when moving, follow direction/load, stop/fade at stop or jam, one lock event. Pilot command alone does not play completion. |
| Prop strike/damaged mechanisms | Accepted prop/shaft event, rotor state and persistent damage mode | Coordinate engine bank shutdown/coast and strike clip through one event; prevent crash and ground paths playing duplicate strikes. |

Continuous inputs include `normal_load_N`, `slip_long_mps`, `slip_lat_mps`, rim/axle speed, `compression_m`, `compression_rate_mps`, dissipative power W, material IDs and component state. Transients include peak/impulse/integrated-work measures accumulated over accepted physics substeps. Do not infer impact solely from positive compression at the rendered endpoint.

### 9.3 Mix, spatialization and bounded work

Use `AudioStreamPlayer3D` through existing aircraft-relative emitters and camera/listener conventions. Convert NED to render once at the presentation boundary. Preserve near-field attenuation guards, camera-cut/Doppler reset, pause/hold, reset, aircraft switch and teardown. All sounds are read-only consumers of detached accepted packets; workers never touch session state.

Recommended initial mix rules, explicitly authored and subject to listening:

- Load/speed/work mappings use bounded monotonic curves with per-profile reference values. Gain may scale with `sqrt(max(P_loss,0)/P_ref)` before compression/clamping; this is a sound-design mapping, not acoustic calibration.
- Rolling loop pitch follows wheel rate/speed within the recorded usable band; crossfade adjacent bands before excessive transposition. Mechanism pitch follows actual actuator rate/load. Never use aircraft airspeed alone for ground sound.
- Material transitions use short equal-power crossfades (initial target 80–150 ms), continuous envelopes (20–50 ms attack, 100–250 ms release) and event scheduling from accepted tick time. These are provisional mix values, not contact delays.
- Use a proposed **32-player ceiling for nonterminal ground/mechanism audio combined**, reallocating the existing ground and AUD-16 players rather than stacking pools: initially 16 continuous material/slip/scrape slots, 8 transient slots, 4 mechanism slots and 4 crossfade reserves. This is a future combined budget, not a claim that today's separate pools already total 32. Retain the existing separate 8-player crash pool and audit total scene voices, including engine/environment. One playback per slot; prioritize near/energetic/unique events and aggregate quiet simultaneous wheel impacts. Never suppress physical evidence when dropping a sound.
- Consume a bounded accepted queue once per render/audio update; coalesce continuous samples by component while preserving discrete IDs and peak/work summaries. Initial proposed limits to test: 256 queued discrete cues, at most 64 drained per update, overflow/drop counters and a 250 ms authored lateness budget for obsolete texture cues. If propagation delay is enabled, lateness begins at due time. Critical lost cues fail QA; audio overflow never stalls or mutates physics. Disk I/O and decoding occur before flight or asynchronously, never in the solver.
- Missing optional clip/profile: fall back to a compatible material family or silence, report once in diagnostics, and continue physics/events. Missing physics configuration still blocks flight. Do not generate synthetic recordings merely because a suitable free licensed recording exists.

Silence is correct at supported rest unless an actual moving/damaged mechanism warrants sound. Pause resumes loops without replaying a touchdown; reset primes observer state; returning from an unseen airborne/ground interval does not invent old events. Audio quality can reduce voices/distance without changing simulation timestep, contact laws or accident counts. Headless Dummy-driver tests prove logic/bounds, not audibility, spatial quality, clipping or real-time mixer performance.

## 10. Godot system architecture

### 10.1 Selected data flow and file ownership

```mermaid
flowchart TD
  A[Aircraft v2 + profile and field registries] --> B[Validated derived model and identities]
  B --> C[FlightSession / VehicleModel adapter]
  I[Accepted input and failure commands] --> C
  C --> K[Shared Simulation tick transaction]
  E[Pure scalar environment queries] --> G[Existing ground / hull / mechanism laws]
  K --> S[Pure joint RK stage]
  S --> F[Existing aero and propulsion]
  S --> G
  G --> M[Coupled body and wheel operator]
  F --> M
  M --> K
  K --> D[Accepted physical damage and contact batch]
  D --> O[Flight and accident classification]
  O --> T[Statistics / economics / recorder]
  D --> P[Render / audio / debug overlays]
```

The diagram's damage box denotes a **transactional commit boundary**, not an observer allowed to mutate already published physics. Future damage transitions are staged and validated before accepted state/event publication. Rendering can interpolate detached snapshots; it cannot interpolate the authoritative event sequence into new impacts.

| Existing boundary | Planned extension | Owner / implementation restriction |
| --- | --- | --- |
| `ground_wheels.gd`, `ground_contact.gd` | Relative wheel convention, shared contact geometry, coupled wrench/Jacobians, passive traction and brakes | GP; split small pure helpers only when reuse warrants them. Keep legacy law reader explicit. |
| `generalized_coordinates.gd` | Reuse factor/solve and qualify any common constrained-force primitive | SF with RCV parity tests; no copied matrix library. |
| `flight_session.gd` | Assemble stage mass/geometry, resolve new continuous/discrete layout, accepted snapshots/events, explicit damage transitions | Aircraft adapter; no per-aircraft ID branches for physical laws. |
| `vehicle_model.gd`, `simulation.gd` | Document/test coupled `body_derivative`; generic transaction support only if damage composition requires it | SF; preserve fixed-wing/rotorcraft/truck/multirotor contracts. No gameplay enums in kernel. |
| `ground_surfaces.gd`, `ground_terrain.gd`, `environment.gd` | Versioned typed support/material query and legacy adapters | GP with LU/FW/HELI/RCV. Query results must be deterministic and immutable. |
| `retractable_gear.gd`, aircraft mechanisms/render binding | Per-leg/door state and stage geometry; admitted support/locks and incremental drag | GP/AS/aircraft owners, presentation consumes accepted pose. |
| `hull_contact.gd`, `sim/scenery_collision.gd`, `scenery/collision_world.gd`, lake paths | Shared geometry, finite support/swept attachment coverage and one contact arbitration owner | GP/CR/LU; retain stable IDs and scenery damage masks. |
| `aircraft_contact_contract.gd`, `aircraft_contact_events.gd` | Versioned observations, support roles, source provenance and episode inputs | AS/GP; strict legacy adapters; no unknown measurements represented by zero. |
| Proposed `app/damage/` | Component/joint evaluation and staged response, physically bound topology | CR; economics/visual bindings remain adapters. Do not move files before searching all references. |
| UI-FS `app/statistics/detector.gd`, adapter/service | Existing pure detector produces the sole shared episodes and semantic accident events; service aggregates/persists eligible observations | UI-FS; no duplicate session classifier. Reconcile current implementation/tests and provide nonpersistent observation when needed. |
| `audio/ground_audio*.gd`, flight/crash audio | Accepted packet consumer, materials, layers and shared budget | AUD; no solver calls for sound-only reconstruction. |
| `workshop/parameters`, compiler, descriptor/dependencies/trial/store | Capability-gated ground/damage recipes, frozen identity and migration | AE/AS; no arbitrary scripts embedded in aircraft packages. |

### 10.2 Godot alternatives and API limits

The exact engine references are pinned in the source ledger. Context7 was used for discovery, then beta1 official source/XML checked for decisive claims.

| Alternative | Supported APIs and limits | Decision |
| --- | --- | --- |
| Native dynamic flight body | `RigidBody3D._integrate_forces`, `PhysicsDirectBodyState3D.apply_force/apply_torque`, contact reporting, `continuous_cd` | Rejected for this roadmap: conflicts with float64 deterministic kernel/state/replay. `custom_integrator=true` disables default force integration but **does not disable collision response**. |
| `VehicleBody3D` / raycast wheels | Native car-style vehicle support; engine documentation itself warns about realistic advanced vehicle physics | Rejected as aircraft solver; does not preserve current coupling or required flight contracts. |
| Scalar analytic field + existing obstacle proxies | Current float64 terrain, stable IDs, swept scenery queries, stage-local sampling | Selected. Extend geometry coverage and material identity; reuse existing broad phase. |
| `PhysicsDirectSpaceState3D.intersect_ray/intersect_shape/cast_motion` | Version-supported boundary queries via shape/ray parameters; collision masks and excludes; cast translation, initial-overlap caveats and float32 fraction result | Optional later geometry adapter only when scalar inventory cannot represent required scenery. Separate overlap test and rotational sweep; pin query/backend identity. |
| `RayCast3D`/`ShapeCast3D` nodes | Cached physics-frame result; force-update APIs exist; shape casts cost more and mutate scene query objects | Debug/authoring comparison only by default. A cached render/physics-frame ray cannot stand in for four stage-local wheel queries. |

Direct physics-space access is subject to engine main-thread/physics-frame locking rules; detached replay workers cannot assume access. Native `Vector3` precision and backend contact ordering do not promise byte-identical cross-platform replay. Collision layer/mask policies must keep authoritative aircraft out of native response; optional query proxies can occupy a dedicated query layer. Exclude own visual/debris proxies and identify materials by authored metadata, not node names or shader color. `continuous_cd` on a visual/native body does not prevent tunneling in separately integrated scalar aircraft state.

### 10.3 Mathematical pseudocode: selected stage solver

```text
stage(body, continuous, stage_time, frozen_tick_context):
    validate layout/domain; unpack relative wheel rims and existing shaft/wash/fuel states
    mass = existing stage mass properties; geometry = mechanism_pose(stage_time, state)
    aero_prop = existing Dynamics using actual controls, wind, density and geometry context
    contacts = shared per-feature support queries(body, geometry, environment)
    assemble M and kinematic bias from declared inventory + wheel rotor partition
    require finite SPD M; factor using GeneralizedCoordinates
    for each stable-ID contact:
        compute gap, compression rate, actual-point Jacobian
        compute unilateral normal compliance and potential/damper ledger
        add normal generalized force once
        prepare tangent rows, tire limits, rolling/terrain losses
    prepare internal brake rows for every installed brake, including airborne wheels
    solve continuous reference forces or selected constrained-force law
    check grip, passivity, residual and iteration bounds
    solve coupled body/wheel accelerations with existing finite-datum mass semantics
    return body derivative, all continuous derivatives, loads and bounded stage diagnostics
    # no events, RNG advancement, sound, files, damage mutation or session writes here
```

```text
accepted_tick_transaction:
    sample pilot/failure commands once; advance sampled actuators/anchors under their contract
    choose bounded substeps from geometry reach + coupled rate bound + existing engine bounds
    integrate all continuous states together; arbitrate swept impacts once
    accumulate contact impulse/work/peak evidence locally across substeps
    evaluate candidate component transitions from accepted-path evidence
    validate candidate mass/topology/state and work/momentum receipt
    if any physical/numerical transaction guard fails: roll back, publish fault only
    else commit body/continuous/aux/modes/contact/damage state together
    publish ordered accepted contact and damage batch, then episode observations
```

Some current session contact transitions run at tick boundaries. GP-08 must map exact callback ordering before extending it. A new accumulator cannot mutate global state from speculative RK stages or count four RK evaluations as four physical impacts. Derive integral estimates with the accepted integration weights/substeps, or use a separately qualified accepted-interval quadrature; preserve uncertainty for a located crossing.

### 10.4 Steering, damage and transition pseudocode

```text
steering_stage:
    demand = mapped channel after device calibration/failsafe
    actual_angle = declared actuator/linkage state within mechanical stops
    axle_axis, heading = mechanism geometry(actual_angle)
    wheel_contact_velocity = actual-point Jacobian * generalized_velocity
    tire_force = solve slip + normal-load-limited traction
    # actual yaw/pitch/roll response is the resulting moment, never a target yaw rate
```

```text
damage_candidate(accepted_contact_work, old_damage):
    group simultaneous contacts by physical feature/joint and event interval
    get one available incident-energy ledger; partition without duplicated work
    for each affected component:
        evaluate authored load/energy/abrasion envelope with evidence status
        propose mode/deformation only if supported by selected profile
    if gear-equipped contact outside authored normal support: classify gear-up accident
    # applies even to a deliberate pilot-commanded belly landing; damage is independent
    resolve lost support/actuation/aero/mass from declarative bindings
    validate conservation and topology; return candidate + immutable receipts
```

```text
observe_accepted_flight_batch(batch, classifier_state):
    reject duplicate generation/tick/sequence; mark gaps unknown
    update physical support from all wheel/skid/hull sources
    open/reuse landing episode on first real touchdown
    join bounce/recontact to same episode until rearm criteria are satisfied
    attach gear-up/component/terminal evidence to one accident ID
    emit CRASH once per accident; later escalation updates it
    if continued flight is physically allowed: keep accumulating accepted state/time
    resolve LANDING_SUCCESS only after clean controlled support + stop or re-ascent rules
    process committed reset/switch receipt after closing unresolved outcomes explicitly
```

### 10.5 Debug and telemetry contract

Extend the debug bridge/state/overlay hooks, not ad-hoc UI automation. A read-only ground overlay should show each actual contact/axle, outward normal, scaled force vectors, material/region IDs, longitudinal/lateral slip, rim speed, stroke/stop margin, brake torque and component state. Add a compact energy/work residual and solver iteration/substep indicator. Use IDs and numeric labels as well as color; hide/distance-limit dense detail. Presentation disabled must leave identical state/events.

Production keeps bounded scalar counters/last accepted snapshots; expensive contact arrays, histories, eigenvalue diagnostics and vector drawing are opt-in. Capture channel names/units, datum reference, source/solver/profile/layout hashes, sample phase, completeness and known gaps. Extend trace metadata/readers and `.orfl` solver identity together; existing CSV layouts cannot silently acquire ambiguous columns. Match P0 baseline and candidate by accepted tick/input tape, not render-frame timestamps.

## 11. Aircraft / Workshop contract

### 11.1 Extend established abstractions, not six competing resources

The requested conceptual profiles map to existing JSON/module boundaries. Use `RefCounted` validated data and packed arrays for simulation; optional Godot `Resource` wrappers may support editor UX but are not a second authority. Keep `openrc-aircraft v2` as the envelope while adding explicit versioned modules/registries and closed schemas. Unknown modules/versions fail with diagnostics; no silent downgrade.

| Concept | Selected home / schema evolution | Required contents |
| --- | --- | --- |
| `AircraftGroundProfile` | New registered ground module resolved by `AircraftModules` and `AircraftData`; derived model owns normalized view | Law/version, intended support roles/sets, accepted geometry envelope, refs to gear/wheel/damage material bindings and provenance. No runtime compression or event history. |
| `LandingGearConfiguration` | Extend existing `landing_gear` through a versioned module | Fixed/retract/skid/none topology, stable leg/contact/attachment IDs, hubs/axes/linkage/paths/locks, stroke/compliance and actuator limits; no hidden aircraft-ID dispatch. |
| `WheelContactProfile` | Proposed `openrc-wheel-profiles v2`; retain explicit v1 reader/law and name adapter, bind new records by stable contact ID | Radius/width, rotational inertia partition, tire law/slip parameters, bearing/rolling behavior, brake hardware/torque, steering/caster capability. |
| `GroundSurfaceProfile` | Proposed `openrc-surfaces v2`; retain v1 table adapters | Explicit material/region, traction, rolling/roughness/soil laws and audio/VFX refs. Environment owns placement; aircraft owns tires. |
| `AircraftDamageProfile` | CR-owned versioned structural module bound to physical identity/inventory | Components/joints, material and section laws, threshold provenance, energy channels, topology/actuator/aero mappings, continuation envelope. |
| `GroundAudioProfile` | AUD-owned data/presentation profile | Material-compatible licensed assets, gain/pitch/crossfade rules and voice priorities; no physical strength or solver coefficient overrides. |

### 11.2 Concrete parameter contract

All numeric authored physical quantities use `{value, unit, kind, source}` with current evidence kinds `manual`, `measured`, `borrowed`, `estimated`, `derived`. Optional uncertainty/range metadata requires explicit schema support. Normalized runtime arrays have documented index layouts and SI units.

| Parameter group | Units / convention | Validation and safe absence |
| --- | --- | --- |
| Hub/attachment/feature position | m in authored LE `[aft,right,up]`; derived O-relative FRD | One conversion; stable model-manifest binding. Every axle/door path in bounds; no nonfinite/duplicate IDs. |
| Axle, strut, steering axes | unit direction, right-handed FRD after conversion | Unit tolerance then deterministic normalization; orthogonality/degenerate wheel-plane checks; sign fixture for left/right/reverse. |
| Wheel geometry | radius and width m; optional rounded profile | Positive radius; width required for sidewall/finite-volume model; absent width retains explicitly limited thin-wheel model. |
| Wheel inertia | kg·m²; relative spin convention and inventory owner ID | Positive rotor inertia; residual locked-body inertia SPD; no duplicate translational/rotational inventory. Missing profile may use legacy only under its explicit historical law. |
| Suspension | N/m, N·s/m, m stroke, optional nonlinear curve/stop | Monotone elastic potential, nonnegative dissipation, finite travel, no hidden k changes with dt; load-sharing/eigenvalue checks. Unknown k/c labelled estimate, not measured. |
| Tire traction | dimensionless μ and slip ratios; force slope N/(m/s) or identified transient model | μ_s≥0, μ_k≥0; declared relation where appropriate; combined constraint; finite zero/reverse-speed behavior. No default aircraft-level brake. |
| Rolling/bearings | dimensionless Crr or resisting moment N·m; law selector | Nonnegative dissipative work over both travel directions. Separate surface/size interaction to avoid scaling wheel radius twice. |
| Brake | none/shared/differential, N·m limit, response/rate and command mapping | Absent means zero torque; shared does not imply retractable. Unsupported input cannot silently control another channel. |
| Steering/caster | rad/rad linkage, rad angle, rad/s rate; optional kg·m², N·m/rad, N·m·s/rad, m trail | Fixed/linked/free/locked distinct. Absent shimmy state means no claimed shimmy. |
| Retracts/doors | dimensionless q, seconds/rates, path geometry, lock capacity N/N·m | Intermediate geometry remains collidable; independent leg IDs; rate/position continuous and bounded; actuator work policy explicit. |
| Aero exposure | CdA m² or dimensionless coefficients with S reference; force point m | Nonnegative drag work, clean-baseline accounting, endpoints/partial tables, force/moment application reference. |
| Damage | N, N·m, Pa, J, J/m² and deformation units by selected model | No magic global threshold; explicit component and mode mapping, evidence coverage, valid post-failure geometry/mass. Unknown strength is not zero. |
| Limits/quality | contact/feature count, geometry envelope, iteration/substep caps | Reject or mark configuration unavailable if it exceeds qualified caps; never silently delete physical contacts for performance. |

Launch validation checks required supports, equilibrium feasibility, prop/door/belly clearance, full tensor, brake/steer roles, path geometry, mechanisms, material coverage, numerical rate envelope and resource identity. Existing minimum-three-support logic must remain for legacy wheeled law but change for explicitly selected skid/no-gear laws. A glider also requires a propulsion-absent/control-topology extension; accepting no wheels alone is not full glider support.

### 11.3 Compatibility and migration

1. Freeze stock source bytes, current registry and solver identities plus baseline tapes before migration. Old logs/checkpoints retain exact readers/laws or are explicitly unavailable; do not reinterpret rim-state bytes under a new convention.
2. Register the new module/law in `app/data/schema/aircraft-modules-v1.json`, `aircraft-contract-v2.json` and generated JSON schema, through existing schema generators. Coordinate AS before adding physical fields.
3. Build a legacy adapter that derives an explicit ground profile from existing gear+wheel registry without changing numerical behavior. Legacy names remain pins; stable IDs are new primary keys. Do not rename current wheel names during this step.
4. Migrate one tricycle reference, one taildragger, one retractable tricycle and one retractable taildragger through their source generators; retain legacy comparison fixtures. Then enumerate the entire current catalog and source-dependent synthetic/Workshop variants.
5. Changing geometry/law/thresholds produces new configuration/solver hashes, model/descriptor/dependency pins and replay version decisions. A physically changed candidate is not exact replay. Re-record golden flights only after an intentional explained change passes independent checks.
6. Only the selected qualified module may write physical contact loads. Legacy and new paths cannot both be active. Missing optional sound remains harmless; missing required geometry/profile or unsupported law blocks launch with a useful error.

### 11.4 Workshop and hot reload

Add creator controls in existing Workshop parameter definitions/compiler: gear type/support role, wheel hub/radius/inertia, spring/damper/stroke, steering/linkage, brake availability/torque, retract path/door/lock, intended hull/skid supports and component strength evidence. Basic controls expose validated presets and units; advanced panels show provenance/range and qualification warnings. Do not surface matrix-layout/debug details as ordinary creator choices.

Use one detached candidate compile, recalculate mass/CG/inertia/contact arms, run existing start qualification and show physical compatibility before a trial. Import GLB/FBX metadata through the established manifest/binding pipeline; never infer gear strength or tire radius solely from node names. Explicit author tools can measure geometry, but physics values remain reviewed quantities. Preserve stable `airplane`, `propeller` and hinge identities.

Extend `parameters.gd`, `compiler.gd`, descriptor/dependency pins, bundle/versioned store and trial freeze as one contract change. Current `_inherit_wheel_model` applies similarity scaling to radius/inertia/brake torque; new independent hardware edits must not also apply that transform twice. Virtual scaling remains labelled experimental. Saved builds use a new immutable revision; do not mutate stock generated data or previous saved revisions.

**Hot reload:** physical parameter/layout/topology changes require a transactional reinitialization or new trial, with new generation and explicit statistics outcome. Invalid reload keeps accepted aircraft, damage, input state and logs unchanged. Do not hot-swap k, tire inertia or damage profile mid-contact and erase stored energy. Compatible presentation/audio changes can rebind at a safe presentation boundary without touching physical hashes. Checkpoint restore requires matching law/layout/profile/source identities and complete damage/episode cursors; partial history remains unknown, not clean.

## 12. Phased implementation roadmap

### 12.1 Execution rules and dependency order

All steps below are **planned, not implemented by this document**. GP owns contact mechanics; SF owns kernel contracts; AS owns authoring schemas; CR owns physical damage; AUD owns audio; UI-FS owns statistics; AE owns Workshop. The step IDs extend the existing GP track. Cross-track work is coordinated at those existing interfaces, not a new parallel implementation track.

Each step must produce a small independently reviewable change, exact source/configuration identities, a test inventory with outcomes and limitations, and a dated receipt under the owning evidence directory. Read current source again before implementation: the audit occurred in a concurrently changing tree. A row's paths are existing integration points unless explicitly marked proposed. Every new law is versioned. Every generated aircraft change goes through its source pipeline.

Priority ranks consider correctness (C), realism (R), stability (S), player impact (P), and architectural cost (A). H/M/L are qualitative, not calculated benefit scores. High cost never excuses failing a conservation or transaction gate. Dependencies specify minimum prerequisite gates; physical calibration can proceed independently while software foundations are built.

```mermaid
flowchart LR
  G08[GP-08 Baseline and contracts] --> G09[GP-09 Coupled wheels]
  G08 --> G10[GP-10 Common ground geometry]
  G08 --> G14[GP-14 Accident and flight events]
  G09 --> G11[GP-11 Suspension and bounce]
  G10 --> G11
  G09 --> G12[GP-12 Traction brakes steering]
  G10 --> G12
  G10 --> G13[GP-13 Gear mechanisms]
  G11 --> G15[GP-15 Aero coupling qualification]
  G13 --> G15
  G10 --> G16[GP-16 Structural evidence and work]
  G11 --> G16
  G14 --> G16
  G13 --> G17[GP-17 Gear and prop failure]
  G16 --> G17
  G17 --> G18[GP-18 Detachment]
  G10 --> G19[GP-19 Ground audio]
  G14 --> G19
  G12 --> G20[GP-20 Creator contracts]
  G13 --> G20
  G16 --> G20
  G12 --> G21[GP-21 Optional advanced laws]
  G15 --> G22[GP-22 Qualification]
  G18 --> G22
  G19 --> G22
  G20 --> G22
  G22 --> G23[GP-23 Rollout and consolidation]
```

GP-14's survivable accident path must not wait for a complete structural solver. It can classify accepted gentle hull contact using existing soft-contact physics and report structural severity as unknown. GP-19 can follow the accepted event contract before advanced damage assets exist. GP-21 is optional and cannot block a qualified core release; if enabled, its own evidence joins GP-22.

### 12.2 P0 — core correctness and lifecycle

Execution status: GP-08a, GP-09a, GP-10a/b and GP-14a in the opening ledger are implemented subsets. The table describes each **full step**, not work claimed complete by those subsets. Complete GP-10's wheel geometry and whole-consumer migration and GP-09's moving-axis/inventory/shaft work before migrating GP-11 suspension and GP-12 traction. Do not enable the fixed-axis reference as a drop-in replacement for moving production gear.

| Step / priority | Existing foundation and gap | Change and exact integration | Physical justification / implementation | Dependency, risk and acceptance gate |
| --- | --- | --- | --- | --- |
| **GP-08: freeze evidence and contracts**; C H/R H/S H/P M/A L | GP-00…07, flight recorder, current contact tests and source generators exist; no frozen cross-system baseline for this mission. | Record current catalog, source bytes, `VehicleModel` layouts/callback ordering, `FlightSession` contact publication, wheel/gear/hull laws and UI-FS state. Extend existing test fixtures/trace metadata only as needed. | Separates solver errors, geometry errors, data fitting and player classification. Preserve baseline `.orfl`, exact replay and current software observations before changing a law. Include current heavy-aircraft/drop outcomes without calling them real validation. | First step. Risk: concurrent changes invalidate receipts. Gate: isolated snapshot, full scenario inventory, baseline replay complete and exact where supported, all existing failures/pending checks explicitly listed; no golden re-recording. |
| **GP-09: coupled wheel/body dynamics**; C H/R H/S H/P H/A H | Rim state, spin-up and shared generalized-coordinate factors exist; arbitrary-body-rate energy proof, inertia partition and airborne brake integration are incomplete. | `ground_wheels.gd`, `generalized_coordinates.gd`, `flight_session.gd`, `vehicle_model.gd`, wheel profiles, wheel/session/finite-mass tests and replay identity. Qualify coupled `body_derivative` without adding a vehicle branch to Simulation. | Implement §4's relative-spin mass/Jacobian convention first with the existing continuous traction law. Remove the redundant independent reaction path in the new law. Evaluate installed internal brakes without ground or retractability gating. Do not simultaneously retune tires. | After GP-08. Risk: sign, locked inertia, axle transport and fuel coupling. Gate: independent matrix/virtual-work oracle, body-wheel momentum/energy tests including nonzero body rates, airborne internal brake, reverse spin, rejected-step rollback, no double torque and explicit old-log compatibility. |
| **GP-10: one geometry/material query**; C H/R H/S H/P H/A M | Analytic terrain, per-wheel regions, hull probes and scenery IDs exist; height/material/relief differ across consumers. | `ground_terrain.gd`, `ground_surfaces.gd`, `environment.gd`, `hull_contact.gd`, `ground_contact.gd`, `ground_wheels.gd`, field loader, `scenery/collision_world.gd`, authoring contracts. Introduce versioned typed samples and a legacy adapter. | Use consistent gap, normal, gap rate and material IDs; separate roughness from rolling coefficient. Define shared round-wheel geometry helpers, retaining the legacy point law until GP-12 migration. Match collision geometry and support work; no hidden runway-location friction switch. | After GP-08; can parallel GP-09 on separate files with interface agreement. Risk: broader terrain semantics and changing contact datums. Gate: flat/slope/curved-surface derivatives and virtual work, per-wheel edge samples, hull/prop agreement, deterministic query parity for legacy path, no new material inferred from usage name. |
| **GP-14: accepted events and survivable accidents**; C H/R H/S H/P H/A M | Strict contact events, soft hull continuation, economy dedup and UI-FS work exist; terminal crash semantics cannot represent a gentle gear-up accident correctly. | Version `aircraft_contact_events.gd`/contract, session accepted publication, UI-FS adapter/detector/rules/schema/reducer/store, existing incident adapter; coordinate current UI-FS source before edits. | Implement §8's orthogonal accident, damage and continuation fields; wheel observations and episode state machine; generation-latched M7 plus distinct accident archive. A valid gentle belly slide records `GEAR_UP_CONTACT` and nonterminal `CRASH` while accepted ticks continue. No new force or mandatory structural-failure inference. | After GP-08; initial existing-material adapter permitted, GP-10 completes typed samples. Risk: duplicate counts, flight closure and reset races. Gate: all ten event types, bounce/touch-and-go boundary tests, 100 persistent scrape ticks yield one incident, terminal escalation yields no second M7, failed reset/reload changes nothing, intended skid contact is not gear-up. |

**P0 exit:** legacy airborne behavior is unchanged outside a justified, isolated wheel-coupling correction; one authoritative force path exists; no ordinary survivable gear-up contact is forced through `_crash` solely to update statistics; physical state, accepted observations and persistence agree. Existing severe-response heuristics remain explicitly provisional until P2 replaces their physical meaning. Numerical faults remain contained and distinct from aircraft accidents.

### 12.3 P1 — realistic support and flight transitions

| Step / priority | Existing foundation and gap | Change and exact integration | Physical justification / implementation | Dependency, risk and acceptance gate |
| --- | --- | --- | --- | --- |
| **GP-11: suspension, bounce and numerical envelope**; C H/R H/S H/P H/A M | Linear support/damping, substeps and GP-06 drop scenarios exist; coefficients/overtravel are not structural calibration. | `ground_contact.gd`, wheel normal law, `ground_start.gd`, profile validation and source generators; contact/substep/drop/landing tests and traces. | Fit static sag then dynamic compression/rebound independently; add explicit progressive stop potential and separate travel/yield/fracture. Compute coupled stiffness/damping rate bounds. Same hardware under larger mass must change sag/response through equations. Preserve natural rebound energy; no post-touchdown velocity clamp or artificial bounce. | After GP-09/10. Risk: excessive stiffness, damper sign, onset discontinuity, hidden energy from anchors. Gate: static load split, independent drop oscillator, phase/refinement sweep, rebound-energy ledger, no attractive support, heavy/CG sweeps and documented uncertainty. Unknown strength remains unknown. |
| **GP-12: wheel shape, traction, brakes and steering**; C H/R H/S H/P H/A H | Current point contacts, slip circle, anchors and rudder steering provide a baseline; actual rolling geometry, stable general static rolling and differential brakes are incomplete. | `ground_wheels.gd`, `wheel_profiles.gd`, shared GP-10 geometry, input/channel definitions, session brake commands, wheel render bindings and ground-start qualification. | Migrate declared hubs/axles/radii to round contact; implement §4 constrained tangent-force solve after coupled continuous reference passes. Distinct rolling moment/bearings/traction; proper stopped-wheel/airborne brake; per-wheel commands and real steering linkage. Keep old rolling-force law as an explicit baseline, never sum both laws. | After GP-09/10; use GP-11 normal model when migrated. Risk: low-speed creep, wrong friction projection, poorly conditioned contact sets and camber degeneracy. Gate: cone/passivity/KKT checks, coast/hold/reverse/combined braking, brake hardware absent means zero, steering requires load, tricycle load transfer and taildragger destabilizing moment tests. |
| **GP-13: retractable mechanisms and partial contact**; C H/R H/S H/P H/A H | Common extension timer, contact path, visual interpolation and gear CdA already exist. Intermediate support is currently removed. | `retractable_gear.gd`, session layout/current gear, contact contract, aircraft bindings/generators and retract traces/checkpoints. | Per-leg actuator/lock/path and optional doors; moving-axis kinematics and actuator work; continuous contact geometry at intermediate positions. Distinguish operator inhibit from installed hardware. A partial leg supports only according to its mechanism/lock/load capacity, not a global q threshold. | After GP-10 and GP-09 for moving wheel axes. Risk: actuator-created energy and shape tunneling. Gate: reversal/endpoints/asymmetry/jam, complete geometry sweeps, unchanged initial endpoint CdA, passive fixed mechanism and accounted moving-mechanism work, deterministic rollback/restore. |
| **GP-15: aerodynamic takeoff/landing coupling**; C H/R H/S M/P H/A M | Existing GE, wash, flap and gear drag modules have aircraft-specific coverage; trim and intermediate aero require evidence. | `aero.gd`, `ground_effect.gd`, `slipstream.gd`, `retractable_gear.gd`, trim/maneuver tooling and aircraft source generators. | Validate unchanged free-flight model first; expose actual gear/flap state to trim, incremental door/partial-gear drag and measured moments, local wing clearance as justified. Add GE/wash to an aircraft only via its capabilities/evidence. Lift unloads wheels through dynamics, never a takeoff detector. | After GP-11/13; calibration data may be collected earlier. Risk: duplicate clean drag, global GE lift multiplier and empirical model extrapolation. Gate: power/drag/trim signs, q-dependent exposure, gear-asymmetry yaw, airspeed versus ground-speed crosswind cases, continuous individual loads through rotation, bounce and go-around; unchanged disabled-module results. |

**P1 exit:** reference tricycle and taildragger aircraft taxi, accelerate, unload, lift off, touch down, bounce and settle through force balance. A hard drop can reach the stop without being classified as a proven fracture; P2 supplies structural consequences. An aircraft with doubled mass and unchanged gear is not required to have the same response as a correctly resized gear assembly. Numerical convergence and held-out physical validation remain separate gates.

### 12.4 P2 — meaningful damage, complete feedback and authoring

| Step / priority | Existing foundation and gap | Change and exact integration | Physical justification / implementation | Dependency, risk and acceptance gate |
| --- | --- | --- | --- | --- |
| **GP-16: structural contracts and accepted work**; C H/R H/S H/P H/A H | Contact snapshots, mass inventory, economic evidence and visual crash effects exist; no general physical component/joint model. | Proposed CR `app/damage/`, contact measurements/contract, session transaction, mass inventory binding, v2 component schema and source generators. | Implement component/mount IDs, local load/energy/deformation channels, material/strength evidence and solver-work provenance. Define work-sharing across probes/patches; unknown threshold never becomes a made-up fracture. Reuse economics arithmetic only with its actual provenance. | After GP-10/11/14. Risk: spending full aircraft kinetic energy at every probe, damage from rejected stages, circular economics-to-physics inference. Gate: multipoint partition bounded by accepted work, local-frame direction, probe-count invariance, threshold intervals and immutable accepted transitions. |
| **GP-17: gear collapse, scraping and prop damage**; C H/R H/S H/P H/A H | Current terminal overtravel, soft scraping and engine-stop prop strike are useful observation paths but incomplete physical failures. | Ground/retract/hull laws, proposed damage components, session propulsion/failure adapters, aircraft geometry/aero masks and component bindings. | Progressive yielding/bending/broken-lock/leg response for supported profiles; continued belly/wingtip/door contact; prop rotational/mount energy and declared stopped/coasting blade coverage. Replace the physical meaning of global terminal heuristics only where the new profile is qualified. | After GP-13/16; wheel/fixed-gear subset can precede full retract damage. Risk: unstable broken geometry, unsupported thrust after strike and false certainty. Gate: gentle gear-up survives with one crash, overload collapses weak gear in an independently bounded fixture, stronger gear survives the same case, heavy mass effect follows loads, subsequent scrape moves plausibly, serious failure has explicit continuation limit. |
| **GP-18: detachable physical components**; C H/R H/S H/P M/A H | Stable visual parts and inventory mathematics exist; deleting a mesh does not partition the physical vehicle. | CR topology transaction; SF generic combined-state/topology boundary if required; inventory, aircraft aero/control/propulsion masks, scalar collision inventory and render adapters. | Start with a wheel/door/accessory, then supported control/wing parts. Partition mass, full inertia, angular/linear momentum and stored/relative-spin energy once; assign fuel/shaft state ownership. Qualify wreck continuation or explicit unsupported outcome. | After GP-17 and approved generic SF contract. Risk: invalid SPD retained inertia, double resource ownership, energy gain, many bodies. Gate: conservation/energy budget, deterministic simultaneous failure order, no repeated detach, continued contact and bounded debris budget. Unsupported critical topology must not masquerade as a validated damaged aircraft. |
| **GP-19: physics-aware ground audio**; C M/R M/S M/P H/A M | Ground rolling/touchdown assets, pooling, crash/powertrain audio, AUD-16 servo/retract playback and tools exist. Frame polling and usage-name material aliases miss important events. | `audio/ground_audio.gd`, `ground_audio_model.gd`, `flight_audio.gd`, `mechanical_motion.gd`, `mechanical_audio.gd`, `mechanical_profile.gd`, existing ground/crash pools and free-asset importer/manifest; AUD accepted packet adapter. | Consume accepted material/contact/slip/work/gear observations. Migrate existing mechanical transition capture to accepted ticks; retain playback/profile ownership. Add rolling crossfades, spin-up/skid, suspension/bottom-stop and damage layers with dedup/fallbacks. Audio retract type cannot select physical hardware. | After GP-10/14; GP-16/17 unlock truthful damage layers. Risk: aliasing, repeated one-shots, pool leaks, fake squeal and licensing gaps. Gate: deterministic event selection including between-frame reversal/stalls, silence at rest, pause/reset/hot reload, no missing-asset crash, bounded combined pools and native-output/soak tests (§13). |
| **GP-20: universal aircraft and Workshop migration**; C H/R H/S H/P H/A H | v2 module contracts, compiler, source pins, trials and profile transfer already exist. Advanced roles/layouts are not creator-editable. | AS schema/registry/generators; `workshop/parameters.gd`, compiler/descriptor/dependencies/bundle/trial/store and existing Workshop UI; contact/render bindings. | Capability-gated wheel/gear/brake/damage presets and numeric units; explicit skid/no-gear and propulsion-absent routes; independent geometry/hardware edits. Recompute all dependent mass/arms and numerics on a detached candidate. Preserve saved immutable revisions and historical readers. | After GP-12/13/16 contract freeze; UI prototypes may precede runtime enablement. Risk: invalid imported geometry, hidden similarity scaling twice, source drift and wrong profile key. Gate: current fleet plus variants compile through one pipeline, malformed/unsupported candidates reject atomically, export/fresh-clone resources present, failed hot reload preserves accepted state. |

**P2 exit:** supported damage outcomes change physics and remain controllable when plausible; gentle gear-up contact counts statistically while continuing; contact/accident/audio/economics share accepted evidence without duplicate events. A missing sound is harmless. Missing mandatory physical data prevents selection of that law rather than inventing strength.

### 12.5 P3 — advanced realism and release qualification

| Step / priority | Existing foundation and gap | Change and exact integration | Physical justification / implementation | Dependency, risk and acceptance gate |
| --- | --- | --- | --- | --- |
| **GP-21: optional measured refinements**; C M/R H/S M/P M/A H | Basic linkage, analytic relief and tire laws are available after P1; true caster shimmy, wheel sinkage and deformable soil are not. | GP wheel/terrain modules, explicit caster/soil continuous state and schema, existing environment query and audio packet. | Add only evidence-supported trail/alignment dynamics, unsprung modes, finite patch/roughness filtering, grass ploughing or soil deformation. Never call numerical penetration soil sinkage or animate random shimmy as force. | After GP-12 and relevant data. Risk: parameter identifiability, stiffness, terrain memory and cost. Gate: independent measurements, passive energy and refinement, bounded state, saved terrain/reset semantics, proven incremental realism within budget. Each optional module can remain deferred. |
| **GP-22: whole-fleet numerical/physical/performance qualification**; C H/R H/S H/P H/A M | Existing test runner, .orfl replay, flight scenarios, benchmarks and debug bridge exist. Historical performance does not qualify new engine/laws. | Extend existing test/flight/audio tools and evidence manifests, not a new platform; all applicable aircraft/contact/damage routes. | Execute §13 in an isolated frozen snapshot, separate law/data changes, include held-out physical cases and 1080p rendered pacing. Profile before optimizing; preserve deterministic ordering and derived-rate guarantees. | After required P0–P2 gates; include GP-21 only if enabled. Risk: shared host noise, missing cases, false batch percentiles and tuned-to-test fixtures. Gate: every declared scenario executed, uncertainty/results recorded, current engine/hardware receipts, all enabled modules within approved budget. No claims of physical validation for unmeasured configurations. |
| **GP-23: guarded rollout and canonical documentation**; C H/R M/S H/P H/A L | Existing aircraft guides, STACK/contract/decisions and GP evidence homes define ownership. | Capability/law selection, release manifests, canonical GP/aircraft/AS/CR/AUD/UI-FS guides, `DECISIONS.md`, useful `LEARNINGS.md` entries only. | Roll out one qualified tricycle and taildragger then retract/no-gear routes; keep legacy law explicitly selectable for historical replay during the supported migration window. Retire duplicate paths only after dependent data/logs migrate. | After GP-22. Risk: hidden mixed laws, stale instructions and premature legacy removal. Gate: fresh clone/export and upgrade/restore acceptance, documented supported/experimental modes, no duplicate force ownership, plans consolidated when completed as repository policy requires. |

No date estimate substitutes for a gate. If empirical hardware data remain unavailable, ship only an honestly labelled estimated configuration after software/stability acceptance; do not call it physically validated. If the coupled solver exceeds budget, first reduce allocations/query duplication and factor once per stage; never repair performance by disabling forces when a speed threshold is crossed.

## 13. Verification plan

### 13.1 Evidence classes and reproducibility

Every result must be labelled **analytic software verification**, **numerical convergence**, **empirical calibration**, **held-out physical validation**, **workflow acceptance**, or **target-host performance**. A test that reproduces the current implementation is useful regression evidence but cannot independently prove that implementation's physics. A plausible animation, audio recording or manufacturer caution cannot validate a spring constant or fracture threshold.

Freeze a snapshot for each campaign. The receipt records commit plus dirty-file identities, exact engine binary/version, platform/CPU/GPU/driver, tick/substep law and limits, aircraft/source/profile/material/configuration hashes, initial state including all continuous/aux/modes, environment/weather seed, deterministic input tape, physics-time range, observer settings, tool invocation, scenario inventory, raw logs and completion status. Use `.orfl` and the [flight logging workflow](FLIGHT-LOGGING.md): exact baseline first, then one explicit candidate with the same physical-time inputs. Preserve `solver_changed` and `complete`. Recovered prefixes and candidate runs cannot establish exact equivalence.

Use the [tool index](tools/README.md), existing [physics tools](tools/physics.md), [checked Godot runner](../tools/godot/README.md), flight-test drivers and [debug bridge](../tools/debug/README.md). A command returning zero is insufficient if the engine logged an error or no requested scenario ran. Assert expected scenario names/counts because some current selectors can silently omit unknown names. Avoid ad-hoc alternate physics implementations except independent small analytical oracles. Long suites run on an isolated snapshot; importing concurrently into the shared tree invalidates evidence.

### 13.2 Quantitative numerical gates

These are proposed engineering acceptance tolerances to freeze with fixture scales before implementation. They are not measured achievements. Each residual divides by an explicitly declared same-unit scale with a nonzero floor.

| Check | Acceptance criterion / scope |
| --- | --- |
| Units, signs and virtual work | Synthetic well-conditioned fixtures: normalized force/moment/acceleration/work residual ≤`1e-10`; exact zero for disabled force modules, absent hardware and tire traction at N=0. Test both steering/spin/travel directions. |
| Coupled matrix | Independent dense assembly versus shared block factor/solve: normalized residual ≤`1e-10`. Reject nonfinite, nonsymmetric or non-SPD declared tensors. Reject nonzero local-local off-diagonal entries for the structured factor; qualify the existing full-SPD path for coupled local DOFs. Ill-conditioned fixtures must produce diagnostics/refusal, not fake decimal accuracy. |
| Instantaneous dissipation | With only dissipative elements active, total mechanical power including rotor/body cross terms, declared springs/anchors and actuator work ≤`1e-10` of the fixture power scale. Friction within combined bound; passive tire/rolling/brake signs in forward, reverse and zero-speed limits. |
| Conservation over time | Smooth closed-system coast/internal-brake fixtures: normalized energy/momentum residual ≤`1e-6` over 10 simulated seconds at accepted refinement. Report maximum drift as well as endpoint residual. Internal brakes dissipate relative rotation while conserving total angular momentum. |
| Static support | Analytic level fixture: force residual ≤`1e-6 mg`, moment residual ≤`1e-6 mg*wheelbase`, nonnegative individual reactions. Preserve the existing Stik fixture's ≤`1e-3 N/Nm`, speed/rate <`1e-4` after 6 s and positive per-tick energy <`1e-6 J` gates unless an intentional law change justifies a revised independent oracle. |
| Refinement | Compare 240/480/960 Hz with unchanged physical coefficients, matched-time tape and touch phases 0, ¼, ½, ¾ tick. Adjacent peak stroke/load, rebound and stopping-distance discrepancies ≤2%; finer pair ≤1%. Use declared near-zero floors, initially 0.1 mm stroke, 1 mm position, 0.01 m/s speed. Event/failure class agrees outside declared threshold uncertainty. Smooth modes approach RK4 order; nonsmooth contacts need not converge at a 16× ratio. |
| Existing whole-flight regression | Preserve `test_landing_maneuver`'s 240/480 bands: touchdown position 0.25 m, sink 0.05 m/s, stop position/time 0.5 m/0.5 s, compression 5 mm. Preserve applicable Stik takeoff reference bands: early 1-D 0.5%, full roll 3%, attitude-matched 0.2%. State assumptions when a new law makes an old oracle inapplicable; never widen automatically. |
| Transaction/replay | Byte-identical accepted state, clocks and IDs for same-source/platform exact replay where promised. Every rejected candidate restores body, wheels, actuators, damage, anchors, RNG, journals and counters. No sound/event/persistence write for rejected physics. Cross-platform tolerance checks are separate from byte-exact claims. |
| Physical realism | Fit and held-out runs separate; predeclare measurement uncertainty/model-discrepancy allowance, report residuals and coverage. At least one held-out load/drop/speed/surface per calibrated mechanism. No universal percentage or full-scale certification scenario substitutes for RC measurements. |

If a regularization/stop/caster mode cannot meet refinement within the bounded solver, reject that configuration or improve the qualified integrator. Do not silently soften hardware based on frame rate. Log iteration/substep saturation as an explicit failure, not a performance success.

### 13.3 Scenario matrix and existing tests

Existing tests named below are assets to inspect/extend; this mission does not claim they were run or passed. New coverage targets a concrete failure mechanism and reuses shared fixtures.

| Scenario family | Controlled variation and required observations | Existing seams / decisive regression |
| --- | --- | --- |
| Contact geometry and materials | Level/slope/curvature; forward/reverse/camber; one wheel crossing turf/asphalt/grass/gravel boundary; hull, prop and wheel same location | `test_ground_physics`, `test_ground_friction`, `test_ground_surfaces`, `test_ground_terrain`, `test_gear_visual_contacts`. Verify gap derivative, normals, stable material/feature IDs, no mesh-density force multiplication. |
| Coupled wheel dynamics | Body rate with zero relative spin; free spin; airborne braking; arbitrary axle; moving steering/retract axle; live fuel/CG; §4.4 pure-carrier-moment fixture | `test_wheel_session`, `test_sf_generalized_coordinates`, dynamic-mass contact/session tests. Execute current and candidate source against independent energy gradients; identify the declared 1.5 W residual and remove it under the qualified law. No duplicate inertia/spin torque. |
| Taxi/coast/hold | 2/5/10 m/s both directions; slopes, brake off/on, low-speed breakaway, zero grip, no brake hardware, differential braking | `test_ground_stiction`, `test_controller_ground`, ground-start integrity/environment tests; GP-04 scenario method. Track force/load/slip/work/drift/stopping distance; uncalibrated historical coast distances are regression data only. |
| Tricycle handling | Stik/Avanti; CG shifts; full/reserve fuel; elevator signs with/without actual wash; nosewheel unloading, braking pitch, crosswind/steering | Existing takeoff/Avanti/ground tests. Check fore/aft load and moment balance, steering loss at low N and natural rotation. Do not assert down-elevator is universally helpful. |
| Taildragger handling | Extra/P51/F4U/Timber; tail up/down, signed yaw/crosswind perturbations, brake asymmetry, wheel versus three-point landing | `test_p51_ground`, `test_timber_ground`, existing ground-contact research verifiers. Measure ground-loop moment/trajectory, prop clearance and nose-over margin. Neither universal stability nor universal ground-loop threshold is required. |
| Continuous lift transfer | Constant matched inputs and increasing actual lift; clean/flaps/gear as supported; rejected takeoff, go-around, touchdown/rebound/re-ascent | `test_takeoff_roll`, `test_landing_maneuver`, `test_landing_variations`, `test_ground_effect`, existing flap/wash tests. Continuous N, rolling work and motion; no force discontinuity when classifier changes state. |
| Gentle/normal/hard/bounced landing | Sweep measured/local sink, pitch/roll rate, spin, mass/CG and surface independently; drop fixtures plus realistic approach | `test_ground_contact`, `test_sf_contact_substeps`, soft-contact/landing suites. Record §13.4 rebound metrics, stop work, asymmetry and failure provenance. |
| Retractable gear | Fully up/down, intermediate fractions, door phase, reversal, one leg jammed, unlocked/collapsed, asymmetric drag, brake in air | `test_retractable_gear`, retract ground/input/trace tests, `test_p51_retracts`. No q=1 support discontinuity in new law; actual lock capability and geometry determine response. |
| Belly/skid/no-gear | Gentle gear-up, powered/power-off slide, subsequent reflight, intended skid/flying-wing belly, glider with no propulsion | Hull/contact/session tests plus new capability fixtures. Gear-equipped deliberate gear-up counts crash; intended authored wheel-less landing does not. Continued accepted physics and one generation M7 increment. |
| Prop/wingtip/accessories | Spinning/coasting/stopped prop phase if supported; wingtip/flap/stabilizer scrape; door/antenna/pod/ornamental attachment | `test_airframe_contacts`, `test_soft_contacts`, contact event/session tests and generated probe coverage. Local direction/energy/geometry determines component response; no universal whole-plane destruction. |
| Collapse/detachment | One leg then belly, asymmetric mount break, simultaneous failures, detached recontact, full debris slots | New CR transaction fixtures built on existing inventory/contact adapters. Momentum/work/energy receipt, no silently lost mass, stable ID ownership, masks/topology committed once. |
| Contact arbitration | Terrain plus scenery, lake boundary, several probes against one obstacle, high translation/angular rate | `test_lake_ground_contact`, scenery/contact policy suites; swept geometry coverage and ordered TOI evidence. No duplicate normal response; positional correction includes potential-energy accounting. |
| Events/statistics | Spawn, short bounce, long balloon, touch-and-go, full stop, survivable then terminal accident, second distinct incident same generation, unknown recording prefix | UI-FS detector/lifecycle/reset/store tests plus aircraft contact event tests. Per-incident records distinct, M7 generation latch stable, clean landing disqualification local, no terminal-only dependency. |
| Reload/switch/reset | Mid-spin/partial retract/contact/damage, failure at every RK/endpoint boundary, wrong law/material/checkpoint, focus loss/pause | `test_aircraft_contact_session`, `test_dynamic_mass_contact_session`, `test_sf_vehicle_model`, flight log/restart guards. Accepted lifecycle only; failed operation changes no state/counter; restored scene emits no phantom impact. |
| Workshop/import/export | All catalog routes, permitted scale/mass extremes, explicit axles/support roles, missing resources, unknown laws, malformed units, old recipes | Existing Workshop compiler/parameters/bundle/trial/starts/store tests and AS conformance. Same detached candidate through preview/save/import/launch; source-generated data match; fresh export contains selected profiles/assets. |
| Cross-vehicle regressions | Existing airplane, rotorcraft, truck and multirotor kernel cases with unchanged models | Existing SF/model and vehicle-specific suites. Shared math changes must preserve each route's separate qualification; fixed-wing success does not certify another vehicle. |

`test_ground_stage_queries` and its frozen reference are a parity oracle for the old law, including only five named fleet cases at audit. Preserve them for semantics-preserving refactors; add missing Extra/F4U coverage explicitly and use new independent oracles for a changed physical law. Do not overwrite the reference merely to make a new model green.

### 13.4 Dedicated bounce and heavy-aircraft failure campaign

For every controlled touchdown record first touch, maximum compression, release, apex and recontact times; local normal velocity immediately before impact/release; hop clearance, unsupported duration, per-leg peak normal/side force and mount moment; stroke/stop deflection/permanent set; and all kinetic, gravitational, elastic, actuator, aero, propulsion, tire, brake, damping, plastic and fracture work channels. Retain peaks across substeps even when rendering misses them.

1. **Isolated rebound:** disable aero/propulsive forces in a synthetic fixture, drop onto unchanged compliant hardware, compare with the independently solved mode within its stated assumptions. Vary damping and drop phase. More damping must not add mechanical energy; no fabricated velocity kick. Confirm no permanent damage below the declared elastic envelope.
2. **Aerodynamic bounce:** compare aero-off, power-off aero-on and powered aero-on with matched initial conditions. Gear-induced pitch can redirect forward kinetic energy into altitude without propulsion. Log total `F·v` separately from its vertical channel; ideal lift in still air is not a source of total energy. Compare touchdown spin-up pitch effects and flap/GE configuration.
3. **Fixed gear with added mass:** hold hardware k/c/travel/strength and a declared CG/inertia prescription fixed; compare light/heavy cases at the same local approach velocity. In the simple linear mode, sag scales with mass, natural frequency with `1/sqrt(m)` and damping ratio with `1/sqrt(m)` for fixed c. Full coupled peak loads need not be monotonic under uncontrolled attitude changes. Compare every leg's envelope and energy, not just whole-aircraft sink.
4. **Heavier aircraft with upgraded gear:** recompute hardware from evidence. In an ideal similarity fixture, scaling k and c with mass preserves simple-mode sag/frequency/damping ratio; actual travel, tire, mounting strength and inertia still require independent evidence. Do not require a larger properly equipped aircraft to break earlier.
5. **Asymmetric hard landing:** same CG sink with pitch/roll rates, one-wheel contact and lateral slip. Identify first overloaded leg/mount using its local velocity and combined load/energy. The other leg remains healthy unless its own load history exceeds its criterion. Include full/reserve fuel, ballast and high-CG cases.
6. **Bottoming through collapse:** produce below-stop elastic compression, stop engagement, yielding/permanent set, and ultimate failure in separate evidence-backed synthetic cases. Transition into belly/door/wingtip support while conserving/accounting stored energy and momentum. No freeze, reset, instantaneous safe pose or disappear-and-reappear leg. Keep one contact episode across the resulting bounce/scrape.
7. **Failure timing and uncertainty:** sweep just below/above onset/ultimate intervals at all refinement rates; inject rollback exactly at candidate failure. Threshold uncertainty remains visible. Uncalibrated real gear yields unknown/inspection evidence; an arbitrary vertical-speed cutoff cannot establish breakage.

Physical validation needs safe measurements from actual hardware or suitably documented independent experiments. Use static loading and nondestructive dynamic evidence first. This document neither requires destructive tests on a flying model nor invents missing ultimate-strength data. A validated stiffness/bounce law does not by itself validate fracture.

### 13.5 Audio, visual and human acceptance

Extend existing `tools/audio/check_pack.gd`, `check_parity.gd`, `contact_mix_probe.gd`, fleet-sequence and bench/native profile tools after confirming their current names/options. Fixed-wing audio parity does not automatically include rotorcraft. Validate packet selection at render rates 30/60/144 Hz, a deliberate 600 ms presentation stall and pause/step/resume; all physical events remain in the journal even when stale audio is dropped. Run at least 100 load/reset/switch cycles, a 125 s representative output capture and a 10 min stress soak. Require bounded players/queues, no ongoing growth, no repeated break/touch samples and no stale gear sounds after reload.

Native-output acceptance uses the actual target audio driver, initially Windows WASAPI, then each release platform. Proposed mix gate: true peak ≤−1 dBTP, no digital clipping or audible underrun/starvation; preserve dynamic range rather than normalizing every scrape. Log device/driver/buffer and analysis method. Sample license/manifest, missing-asset fallback and pack/export checks are mandatory. Listen to real reference material where available; car/skateboard proxies must remain identified as approximations.

Manual scenarios at **1080p** include calm and crosswind taxi, rotation, tricycle derotation, tail-raising/three-point/wheel landings, visible suspension rebound, grass edge transition, progressive collapse and gear-up rollout. Compare drawn wheel/contact compression, prop/door clearance and shadow/terrain cues with overlays. Repeat with expert RC pilots where available and record aircraft/configuration and disagreements; pilot preference cannot override conservation or compensate for wrong geometry. Higher-resolution readability/performance follows 1080p qualification; 720p is fallback evidence only.

### 13.6 Performance and practical quality settings

The 240 Hz tick interval is 4.167 ms, not permission to spend all of it on contact. Retain the existing **500 µs whole-physics-tick target** and historical **75 µs contact / 150 µs incremental-ground goals** as goals to reconcile, not three additive allowances. GP-05 recorded older shared-host Windows Ryzen 5900X/4.7.2 whole-session medians roughly 526–1284 µs and p95 675–1614 µs, with contact medians roughly 59–94 µs. Those historical results miss some goals and do not qualify 4.8-beta1 or this design. Preserve the exact historical context in linked GP evidence.

Proposed new limits require target-host agreement at GP-08: whole-tick median ≤500 µs, p95 ≤750 µs, p99 ≤1000 µs for the declared stock fleet/reference scenarios, with contact work reported separately; budget additional bodies explicitly before enabling detachment. Measure per-tick tails, not p95 of batch averages. A contact feature is not accepted merely because average FPS remains high. Production observers default to bounded summaries; full force traces/debug geometry are opt-in and separately budgeted.

At 1920×1080 on declared target hardware/settings, proposed whole-frame gate is p95 ≤18 ms, p99 ≤25 ms, simulation-time/wall-time ratio 0.99–1.01 in sustained representative play. Investigate repeated >50 ms frames and every unexplained >100 ms hitch. Run three alternating baseline/candidate pairs with 10 s warm-up and at least 60 s measurement, no competing workloads; retain raw distributions and confidence/variability. These frame limits are proposals, not current product guarantees. Audio observer CPU target is p95 ≤0.25 ms, p99 ≤0.5 ms and is included in the frame total.

Quality settings may reduce audio voices, visual debris lifetime, VFX density, debug detail and distant decorative sound. They may choose a separately qualified optional terrain/unsprung law **before a session**, with identity recorded. They must not drop authoritative contacts, change physical coefficients with FPS, halve solver iterations without its residual gate, or remove damage mass because the render pool is full. Production limits specify maximum wheels, hull features, active patches, mechanism/debris bodies, iterations and substeps; reject unsupported authored configurations explicitly. Set concrete count caps from measured stock maxima plus declared supported extension fixtures at GP-08/22, rather than claiming an unmeasured universal capacity.

## 14. Risk register and architectural decisions

### 14.1 Selected decisions and resolved disagreements

The main agent owns these recommendations. Six specialist reviews informed them; execution details are in the dated source ledger. These are proposed decisions for implementation review, not claims that `DECISIONS.md` or runtime contracts have already changed.

| Decision / alternatives considered | Selected approach and reason | Revisit trigger / verification |
| --- | --- | --- |
| Custom kernel versus native Godot body/vehicle | Extend existing float64 `VehicleModel` and force laws. Native collision response would duplicate authority and break current replay/state contracts. | Only a separately authorized kernel migration could reverse this. Verify no native response applies to authoritative aircraft. |
| Continuous compliance versus immediate global impulse solver | Coupled continuous RK4 stage first; constrained tangent forces next. Preserves existing callbacks and lets suspension cause bounce. Impulses remain a qualified alternative if stiffness/error/cost fails. | GP-22 failure with measured hardware, not convenience. No restitution impulse stacked onto rebounding compliance. |
| Existing spin-up patch versus coupled inertia | Select the derived relative-spin generalized model, qualify it with independent energy/momentum oracles. The instantaneous source-audit fixture shows a +1.5 W balance residual under explicit locked-inertia assumptions, not a measured production flight result. | GP-09 must reproduce it against actual code and inventory conventions; it cannot merely relabel the old additive oracle. |
| Point versus circular/finite wheel geometry | Keep explicit historical point law; migrate to authored hub/axle round contact and later finite-width coverage when needed. | Thin-wheel degeneracy or measured patch behavior requires a new geometry law, not arbitrary bank-angle scaling. |
| Native impulse/visual crash severity versus component work | Existing impulses and evidence are inputs; accepted work, structural limits and mass bindings determine physical damage. Economic inspection and visual breakup remain separate. | New measured component data; never repair price or sample loudness. |
| One crash per generation versus every independent accident | **Resolve in favor of compatibility:** semantic `CRASH` events/archive are per accident; UI-FS M7 remains latched once per generation, now including nonterminal accidents. A later distinct-accident total needs its own versioned metric. | UI wording/product requirements may request a separate metric. Do not silently change M7's denominator or backfill unobserved incidents. |
| Suppress bounce versus add fixed restitution | Neither. Elastic/damping/aero dynamics produce rebound; plastic failure modifies support when evidenced. A numerical exploding bounce is a defect; a bounded physical bounce is required. | Independent energy/refinement/physical traces distinguish them. |
| Heavy aircraft must break versus aircraft-specific hardware | Fixed hardware load sensitivity and upgraded-hardware cases are separate. Per-leg geometry, load, moment and energy determine failure. | New strength data; mass alone never acts as a global fracture switch. |
| One gear fraction versus per-leg mechanics | Per-leg path/lock/fault state, with a common command adapter for old aircraft. Door and partial-state drag are incremental within existing aero. | Component evidence may justify simpler mechanisms for fixed/linked gear, but collision support cannot be gated solely at q=1. |
| General `Resource` components versus current v2 dictionaries/registries | Keep current generated v2 quantities and runtime normalized arrays authoritative; editor resources may be views/adapters only. | AS contract evolution, not independent per-aircraft scripts. |
| Audio pool redesign versus reuse | Reuse bounded existing ground/crash/flight/mechanical playback and import pipeline; introduce accepted packet/material semantics first. Reallocate the combined nonterminal pools to the proposed budget and explicitly cap active layers. | Measured native-output/performance evidence can change voice budgets, never physical events. |
| Unknown structure versus invented safe threshold | Unknown/inspection plus explicitly limited qualified physical law. Gentle gear-up accident classification is still mandatory. | Only sourced estimates with labelled uncertainty or measurements enable corresponding failure behavior. |

### 14.2 Risk register

| Priority / risk | Consequence | Mitigation and owning gate |
| --- | --- | --- |
| P0: wrong wheel/body mass or moment convention | Energy creation, wrong spin-up pitch, fuel-dependent yaw | Independent virtual work, cross-term energy, CG moment transfer and SPD checks; GP-09. |
| P0: double normal/friction/drag ownership | Unrealistic takeoff release, excessive damping/braking or gear drag | Per-load ledger, mutually exclusive laws, clean/gear baseline checks; GP-09/10/15. |
| P0: stage-side effects or incomplete rollback | Phantom damage/crashes/sounds; corrupt replay | Pure evaluations, local work accumulators and one accepted transaction; GP-08/14/16. |
| P0: statistics still tied to terminal pause | Gentle belly landing fails requirement or closes active flight | Versioned orthogonal observations, generation latch and incident archive tests; GP-14. |
| P1: contact stiffness exceeds bounded integrator | Exploding bounce, missed hard impact, FPS dependence | Coupled mode/rate guards, swept reach, refinement and explicit refusal; GP-11/22. |
| P1: terrain normal/gap mismatch or probe multiplication | Spurious energy, inconsistent hull support, geometry-dependent strength | Shared derivative/geometry/material query, distributed patch normalization; GP-10/16. |
| P1: moving retract/steering geometry injects untracked work | Sudden bounce or spin during actuation | Moving-axis bias and actuator work; collision sweep at intermediate poses; GP-13. |
| P1: insufficient measured RC tire/gear data | Plausible but unvalidated landing distance, bounce and failures | Separate software/empirical gates, provenance and uncertainty, independent held-out cases; GP-11/16/22. |
| P1: stale exact-reference tests mask new errors | Green suite with wrong physics | Retain old-law oracle and independent new-law invariants; declared law identity; GP-08/09. |
| P2: damage topology breaks mass/resource ownership | Momentum discontinuity, invalid retained inertia, duplicated fuel or spin | Prevalidated bounded inventory partitions, transactional masks/model transition, energy receipt; GP-18. |
| P2: material/audio naming conflates turf and pavement | Implausible sound/traction and creator confusion | Material ID separate from field usage, source metadata and missing-asset fallbacks; GP-10/19. |
| P2: concurrent UI-FS/AUD/AE changes drift during implementation | Duplicate services, schema conflicts, stale integration claims | Re-read current code/ownership before each step; freeze review snapshots and coordinate seams. |
| P2: hot reload silently changes stored energy | False rebound, invalid checkpoint or wiped damage | New trial/transaction and law/layout pins; compatible presentation changes only; GP-20. |
| P3: advanced soil/caster models outstrip evidence/cost | Complexity without credible realism | Optional capability/law, measured incremental benefit, bounded state and separate gates; GP-21/22. |
| P3: shared-host benchmarks or low-resolution evidence mislead | Unqualified frame pacing/audio glitches | Isolated target host, raw per-tick/frame traces, 1080p-first evidence; GP-22. |

### 14.3 Explicit open questions with decision owners

1. **Physical data:** aircraft/GP owners must identify actual wheel/tire construction, static gear deflection, damping, travel and mount/leg strength for each reference route. Until then retain estimated qualification labels; do not block mathematically testable foundations.
2. **Inventory partition:** AS/GP must confirm whether each existing generated inertia includes wheel axial inertia and identify its mass owner. GP-09 cannot assume an extra rotor is absent from the tensor. If source inventory cannot distinguish it, document and bound the estimate before migration.
3. **Moving mechanisms:** GP/SF must qualify prescribed axle/door kinematics with work accounting or an explicit inertial approximation before enabling load-bearing motion. The selected stage architecture is fixed; the fidelity of individual mechanism models depends on hardware evidence.
4. **Brittle event timing/topology:** CR/SF must choose fixed reserved component slots with active masks first. Layout-changing transitions require a generic atomic new-model transaction preserving physical flight and observer identity; a normal player reset is not a substitute. Located fracture timing is required if tick-boundary uncertainty cannot pass refinement.
5. **Target performance hardware/count caps:** performance owners must pin the supported host/settings and maximum authored contacts/bodies before accepting the proposed budgets. Historical benchmark data remain observations, not a universal hardware promise.
6. **Statistics/AUD current implementation:** UI-FS/AUD must reconcile their concurrently evolving modules with GP-14/19 before edits. Preserve existing services and mechanical sound work rather than create replacements based on an earlier audit snapshot.

These are bounded evidence/contract tasks assigned in the roadmap. The implementation agent need not redesign the architecture: it must resolve each at its stated gate, retain provenance and keep unsupported capabilities unavailable or explicitly experimental.
