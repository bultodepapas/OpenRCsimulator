# R9 — car physics, mathematical consistency and integration

Date: **22 November 2026, America/Bogota**. Reviewed source: [`77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b`](https://github.com/bultodepapas/OpenRCsimulator/tree/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b). Work continues on `audit/physics-math-aero-2026-11-21`, within [draft PR 17](https://github.com/bultodepapas/OpenRCsimulator/pull/17). [Audit home](README.md) · [RC owner plan](../../plans/rc-monster-truck.md) · [Ground-vehicle operating guide](../../../research/rc-monster-truck/README.md).

## Result and evidence boundary

This pass establishes **two new, bounded contact defects**, with independent arithmetic and accepted reference-session ticks. It also quantifies the nitro flywheel consequence of the already-open **RCV-12 shaft/body coupling** work. These are investigation results and repair proposals; this pass changes no production simulation law, vehicle parameter, native binary or accepted golden.

| Item | Result | Classification and reach |
| --- | --- | --- |
| **R9-F01 — P2, wall/contact composition** | Wall force is applied after the tyre/brake constraint solve. A 1 N constructed contact leaves `0.2021599285 m/s²` tyre-slip acceleration and `0.3139519255 rad/s²` relative wheel acceleration with ample holding capacity. | Confirmed implementation defect. Stock Bisonte, flat component witness; a separate synthetic box passes actual airfield preparation, a braked tick and checkpoint admission/restore. No recorded player collision or physical braking-distance error claimed. |
| **R9-F02 — P2, heading-dependent rest shortcut** | An otherwise identical stationary truck receives different tyre forces at 0° and 90° yaw. The initial suspension-acceleration difference reaches `0.3581546994 m/s²`. | Confirmed mathematical/optimization defect for an admitted non-equilibrium start. Full course parsing and real sessions also commit differing neutral ticks; maximum suspension-rate difference is `0.00030491636 m/s`. Ordinary airfield occurrence remains unmeasured. |
| **RCV-12 — stronger nitro evidence** | With the clutch open, full throttle changes the stock flywheel by `+0.00050295298 N·m·s` in one 240 Hz tick, while the entire 31-value body state is byte-identical to idle. | Quantified existing coupling gap, conditional on shaft-frame/inertia/torque-port interpretation. Component refinement, empty-fuel rundown and accepted elevated-session controls are retained. No new duplicate defect ID or predicted real pitch angle. |

The [portable reproducer](probes/reproduce_ninth_pass.py) reconstructs **172 exact Git source/resource blobs without production stubs**, imports them with official Godot `4.8.beta2.official.cafc17a19`, and executes eight checked jobs. [Retained evidence](ninth-pass-evidence.json) includes **85 new observation checks**, **77 unchanged baseline checks**, full small logs, checked verdicts, source/engine hashes, and three independent mathematical families in [one Python oracle](probes/ninth_pass_oracles.py). All eight jobs and the oracles pass; all source bytes remain unchanged. The new probes explicitly use `gdscript_reference`; no new native, rendered, controller-hardware or measured-vehicle qualification follows.

## What is actually connected

The inspection followed the production owners, rather than treating a standalone suspension demonstration as the playable truck.

| Layer | Connected implementation | Consequence for this audit |
| --- | --- | --- |
| Vehicle selection | Bisonte MT8 electric and MONSTER CAR 2 nitro are separate selectable ground vehicles; `vehicle_catalog.gd` and `ground_scene.gd` select/configure the activity. | The two drivetrains share body/contact mechanics, but nitro has additional state and input adaptation. This pass does not execute the rendered selector. |
| Controls and session | `ground_scene.gd` supplies samples to `sim/ground_vehicle/session.gd`; its `tick_once` validates, applies damage control scaling and steps the shared `Simulation`/`VehicleModel` transaction. | A component discrepancy must also be checked at this boundary before calling it an accepted session effect. |
| Electric mechanics | `vehicle_dynamics.gd` owns 31 float64 values: body state, four suspension travels/rates, four wheel speeds/angles, and steering angle/rate. | The active model includes coupled hub translation and wheel/body inertia; it is more than a point mass or target-speed controller. |
| Nitro mechanics | `nitro_dynamics.gd` appends flywheel speed and fuel, then supplies a whole-tick policy to the same session/kernel. | Its 33-state composite delegates only the original 31 values to body evaluation, including an optional native evaluator. |
| Terrain and obstacles | `prepare_airfield` constructs `AirfieldCourse`, using shared field surfaces/terrain, the optional lake, course walls and the installed scenery inventory converted to car AABBs. | These cars are connected to the shared field. R9-F01 concerns how loads are composed after that connection succeeds. |
| Water | `vehicle_environment.gd` supplies estimated still-water buoyancy/drag as generalized forces before the tyre solve. | This existing ordering provides a useful contrast with the wall path. Water drag does not establish an air-drag or wind model. |
| Reduced research benches | `quarter_car.gd` and `four_corner.gd` have separate state definitions and guides. | Their analytic checks do not qualify the playable 31/33-state vehicle. |

Source anchors: [session tick and transaction](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/sim/ground_vehicle/session.gd#L469), [model stage/tick policy](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/sim/ground_vehicle/session.gd#L2215), [body state/model](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/vehicle_dynamics.gd#L1), [airfield bridge](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/airfield_course.gd#L1), [scenery conversion](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/scenery_walls.gd#L1).

## R9-F01 — wall force invalidates the previously solved tyre/brake response

### Source trace

`VehicleDynamics._evaluate_active` applies wet/environmental generalized loads, then selects the reference or native body evaluator. The body evaluator adds external loads to its right-hand side **before** `_solve_tangent_friction`. After that evaluator returns, the shared wrapper calls `_apply_wall_contacts`, assembles a new wall generalized force, factors the mass matrix again, and adds the resulting acceleration to the previously solved acceleration. It does not re-solve tyre or brake reactions.

Relevant source: [dispatch and final wall call](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/vehicle_dynamics.gd#L724), [wall acceleration addition](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/vehicle_dynamics.gd#L897), [external force and friction solve](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/vehicle_dynamics.gd#L1439), [tyre/brake acceleration targets](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/vehicle_dynamics.gd#L1812).

The [RC track evidence](../rc-monster-truck/RCV-track/README.md) already describes additive wall loads. This finding identifies a previously untested consequence of that design; it does not claim walls are absent. It is also distinct from the repaired A6 F6 positive tyre/brake-work issue and the known finite-iteration convergence limitation.

### Why the arithmetic fails

At a zero-velocity state, write the existing solve schematically as

\[
M a_0=f+J^T\lambda_0+B^T\tau_0,
\qquad J a_0=0,\quad B a_0=0,
\]

when the unsaturated tyre and brake reactions can meet their zero-slip/zero-relative-spin targets. Here `J` maps generalized acceleration into tangential patch acceleration, and `B` selects the held relative wheel accelerations. The implemented final addition is

\[
a=a_0+M^{-1}f_{wall}.
\]

Its residual is therefore

\[
\begin{bmatrix}J\\B\end{bmatrix}a
=\begin{bmatrix}J\\B\end{bmatrix}a_0
+\begin{bmatrix}J\\B\end{bmatrix}M^{-1}f_{wall}.
\]

The second term is generally nonzero. Linear addition of an unconstrained response does not preserve a constrained response. This is a derivation for this code and fixture. The general requirement that a constrained system supply derivatives satisfying its differentiated constraints is also described by [Drake's simulator contract](https://drake.mit.edu/doxygen_cxx/classdrake_1_1systems_1_1_simulator.html).

This argument does **not** require the chassis to remain motionless: compliant normal support can accelerate the body. The tested requirements are the specific tyre-slip and brake targets with sufficient available reactions.

### Reproduction and negative controls

[ninth_pass_walls.gd](probes/ninth_pass_walls.gd) loads the unchanged stock Bisonte. It constructs supported rest on a flat `mu=0.8`, zero-rolling road, applies full brakes, and positions a stationary wall against the front hull probe. The overlap is `1/15000 m`, so the stock `15000 N/m` hull stiffness gives approximately **1 N**. There is one hull-wall contact and four terrain tyre contacts; each tyre carries `13.533177 N`.

| Quantity | Actual wall after solve | Same generalized load before solve |
| --- | ---: | ---: |
| Maximum tangential patch-acceleration residual | `0.202159928488 m/s²` | `0.000217692703 m/s²` |
| Maximum relative wheel-acceleration residual | `0.313951925490 rad/s²` | `0.000035789842 rad/s²` |
| Adaptive sweeps | 1 | 128 |

The second column uses the existing `external_generalized_force` input with the same force and moment, isolating ordering without changing the production source. Its nonzero residual and 128-sweep cap are retained honestly; it is a much smaller discrepancy, not an exact solved reference or a finished repair. Forcing 128 sweeps on the wall-after case does not remove its defect.

The independent NumPy oracle reconstructs the 14-DOF mass matrix and patch/brake Jacobians directly from the stock JSON. It reproduces the actual wall response and finds a simultaneous linear reaction solution with maximum constraint residual below `5e-14`. The required tyre forces are about `0.228 N` in magnitude against `9.74388744 N` capacity per tyre. Required brake torque is about `0.01703 N·m`, against `2.295 N·m` front and `0.405 N·m` rear. Both are below 10% of available capacity. This proves feasibility for the frozen-normal stage, not exact nonlinear time integration.

The no-wall equilibrium control has negligible acceleration. Raising the truck clear of the ground and releasing the brakes produces the same unconstrained wall acceleration increment, confirming that the missing operation is the ground/brake response rather than the construction of the wall load itself.

### Actual session boundary

[ninth_pass_session.gd](probes/ninth_pass_session.gd) supplies a declared synthetic normalized scenery box through real `Session.prepare_airfield` on the stock field and Bisonte. It does not replace the session's road callback or mutate committed state. The supported initial state equals the matched no-wall preparation. Adding the wall changes the final stage acceleration while the solved ground forces and brake torques remain byte-identical.

The session accepts a neutral sample, explicit resume and one braked 240 Hz tick. The front-left relative wheel speed after the tick is `−0.04356367 rad/s`, versus `−0.00713848 rad/s` in the matched no-wall session. These contain the stock terrain's settling transient and nonlinear intermediate stages; neither should be substituted for the perfectly flat analytic fixture. The resulting checkpoint passes admission and restores the same state exactly. This is not continuation replay or an observed player encounter.

### Repair options and acceptance

**Preferred:** compute validated wall generalized loads before the ground/brake solve, combine them with other applied loads, and solve the coupled response once. Preserve the existing wall spring, damping, friction, energy and telemetry accounting while making load ownership explicit. The shared wrapper must pass the same combined force to reference and native evaluation.

**Alternative:** perform a correction solve after adding wall loads, using the same contacts, factorization, bounds and convergence policy. This has more state/iteration bookkeeping and must replace the old reactions, rather than count them twice. Treating walls as a separate approximate operator split would require a declared error contract and refinement qualification; the present instantaneous post-addition is not such a demonstrated scheme.

Acceptance should include the 1 N unsaturated witness, no-wall and airborne controls, braking against front/side/corner walls, driven contact, slopes and wet ground, high-speed impact/refinement, per-element work, bounded solver residuals, both backends, and real session rollback/recording/replay. Preserve no-wall behavior where mathematically unchanged and explicitly version changed solver/qualification identities. The duplicate geometry/mass-factor work is also an optimization opportunity, but no runtime saving is measured here.

## R9-F02 — a rest optimization makes tyre physics depend on heading

### Faulty assumption

The evaluator computes `quiescent_level_state` before constructing tyre contacts. With neutral controls, exact zero velocities/rates and no external generalized force, `_is_quiescent_level_state` accepts only a quaternion near `(±1,0,0,0)`. Ground tyre rows are then omitted on level normals. The predicate does not establish force equilibrium or zero required tangential reaction.

Source: [shortcut selection](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/vehicle_dynamics.gd#L1195), [contact omission](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/vehicle_dynamics.gd#L1308), [predicate](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/vehicle_dynamics.gd#L2149). The [native source](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/research/rc-monster-truck/native/src/ground_vehicle_kernel.hpp#L413) contains the corresponding predicate/omission; its R9 execution remains untested.

A stationary configuration can have nonzero acceleration. In this suspension, vertical compression changes the hubs' lateral positions through the finite arm geometry. Consequently, an unbalanced vertical normal/spring load can require lateral tyre reactions even though every current velocity is zero. Being upright and momentarily motionless does not prove those reactions are unnecessary.

### Matched rotational test

[ninth_pass_heading.gd](probes/ninth_pass_heading.gd) uses public `Vehicle.make_state`, unchanged stock parameters and a homogeneous horizontal road. Both starts are `10 µm` below the supported CG height: `0.174832439435897 m`. They have identical suspension travel, zero rates and neutral controls. Only yaw changes, from 0° to 90°. No artificial force or direct state edit is used.

Since gravity and this road have no preferred compass direction, the same body-frame generalized accelerations and wheel-relative forces should result. Instead:

| Quantity | 0° heading | 90° heading |
| --- | ---: | ---: |
| Normal load per tyre | `13.598177 N` | `13.598177 N` |
| Friction sweeps | 0 | 112, converged before cap |
| Lateral tyre force | 0 | alternating approximately `±0.667623 N` |
| Maximum patch-acceleration residual | `0.03032176045 m/s²` | `8.0373e-7 m/s²` |
| Initial suspension-travel acceleration | approximately `0.358159013 m/s²` | approximately `4–5e-6 m/s²` |

The force capacity is `9.79068744 N` per tyre, so these reactions use less than 10% of available grip. The maximum difference in **travel acceleration**, rather than a mixed-unit norm, is `0.3581546994 m/s²`.

The oracle independently assembles the extra generalized load: lowering the unchanged pose by `delta=10 µm` adds `k_t*delta=0.065 N` normal load per tyre. Its body-up force and suspension generalized components reproduce the zero-heading acceleration. Adding the measured rotated-case tyre reactions closes the same matrix equation and yields the small patch residual.

Two negative controls reject an ordinary coordinate-conversion explanation: at zero grip, the yaw-related generalized-acceleration difference is exactly zero; at true supported equilibrium with grip, it is below `4e-13`. This is not the older generic finite-iteration/yaw observation: one branch omits the rows altogether, while the other converges before the cap.

### Accepted custom-session effect

The session probe changes only the stock practice course's start heading and CG height, plus honest provenance annotations. Each variant passes `Course.parse_text`, obtains its own content identity and passes public `Session.prepare`. Both accept one neutral tick. The maximum difference in committed suspension rate is **`0.00030491635952 m/s`**.

The initial derivative difference is not maintained for the whole tick. Subsequent RK stages acquire nonzero velocities and can stop meeting the shortcut predicate. The measured end-state comparison, rather than multiplying the initial acceleration by time, is the relevant integration evidence.

These are constructed course starts through real APIs. Ordinary airfield preparation uses `make_terrain_state`; normal player occurrence, long-run handling error and visible severity have not been measured. The normal nitro path supplies preload as an external generalized force, so this particular shortcut is disabled there.

### Repair options and acceptance

The straightforward correctness repair is to remove this shortcut and use the normal contact solve. If its cost matters, retain an optimization only after proving that **all nonfriction loads together** require zero reaction in the skipped rows. Use a frame-independent condition or projected residual, and include suspension geometry, preload, normal support and other loads in that proof.

Simply broadening the quaternion predicate to accept every yaw would make the incorrect no-reaction behavior consistent in more headings; it would not repair the physical assumption. Conversely, tiny fake forces or artificial velocity thresholds should not select the physically correct branch.

Acceptance should cover yaw rotations, true rest and small support/suspension perturbations, zero grip, preload, full/native/reference symmetry, accepted ticks/refinement, and versioned session/replay behavior. Measure the cost of the corrected path on representative supported/airborne/wall/water states before selecting a replacement optimization. This pass measures no speedup or target frame budget.

## RCV-12 — nitro flywheel evidence, with the existing owner preserved

The [owner plan's shaft/body requirement](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/docs/plans/rc-monster-truck.md#L228) requires a disjoint chassis, hub, wheel and shaft momentum inventory. RCV-12 remains pending, and explicit differential/shaft topology is outside the delivered compact model. This section strengthens that existing work instead of introducing a duplicate gap ID.

The nitro adapter updates its engine speed, derives clutch torque and advances only the 31-state body slice. With the clutch disengaged, idle and full throttle produce the same zero wheel drive torque and the same body controls. The body matrix couples wheel rotors but not the appended engine rotor. The strict physical schema has an estimated engine inertia but no shaft axis/sign or explicit relative-versus-inertial speed convention. Source: [nitro update](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/nitro_dynamics.gd#L104), [body adapter](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/nitro_dynamics.gd#L224), [strict powertrain fields](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/physics/ground_vehicle/vehicle_data.gd#L16).

For stock inertia `J_e=0.0001 kg·m²`, [the component probe](probes/ninth_pass_nitro.gd) observes:

| Case over 1/240 s | Flywheel result | Body result |
| --- | --- | --- |
| Idle from 4,500 rpm | Remains 4,500 rpm; scalar `J_e*delta_omega=0` | Reference body result |
| Full throttle from the same state | `4,548.02847173 rpm`; `J_e*delta_omega=+0.00050295297983 N·m·s` | All 31 body values byte-identical to idle |
| Same elapsed time, 2/4/8 subdivisions | Full-throttle scalar changes `0.000502635499`, `0.000502555528`, `0.000502535460 N·m·s` | Paired body values remain identical at each resolution |
| Empty-fuel rundown from 700 rad/s | Zero combustion/clutch output; scalar change `−0.000071245546875 N·m·s` | Same body bytes as a fuelled case whose flywheel accelerates |

All compared component cases are airborne and below clutch engagement. Independent scalar midpoint calculations from the shipped JSON match these numbers. The real session probe also accepts a tick in each stock-nitro practice session with an explicit `+5 m` preparation height offset. It reproduces the 4,500-to-4,548 rpm result and byte-identical paired body states. Common suspension/body motion produces nonzero body rates in both cases; the result is **zero differential body response**, not a motionless chassis.

For a declared body-fixed shaft, internal torque changes rotor and chassis momentum together; [MIT's reaction-wheel example, slide 21](https://ocw.mit.edu/courses/16-83x-space-systems-engineering-spring-2002-spring-2003/f36ac5cd49a5c5980721d5897c125293_form_flight_cont.pdf#page=21) illustrates that principle. Applying it quantitatively here requires the installed physical shaft axis/sign, speed frame, nonoverlapping inertia inventory and external torque/flux ports. The render animation axis is insufficient. Combustion/exhaust and engine drag cannot silently be assumed to be purely internal torque, and `J_e*delta_omega` is not a complete vector momentum ledger for a rotating body.

A repair should define that inventory and couple shaft/body dynamics inside the existing atomic tick, including body-rate transport, gyro effects and both clutch power-flow directions. Adding only `−J_e*alpha_e` as a body torque risks omitting transport or counting existing inertia twice. Required follow-up includes no-external-torque balances, rundown, driven/back-driven clutch work, timestep refinement, native/reference agreement, rollback and replay identities. The separate existing R3-G01 fuel mass/CG/inertia omission remains unchanged by this evidence.

## Realism and optimization work that should retain existing ownership

| Area | Current limit or opportunity | Useful next proof |
| --- | --- | --- |
| Air drag and wind | The car body law has no atmospheric/wind-relative load path. The RC plan explicitly makes a separately sourced aerodynamic model conditional on its speed/jump envelope. This is an existing scope gap, not a new absent-feature bug. | Measure coast-down/high-speed/jump behavior; establish a defensible `C_D A` and aerodynamic center before fitting. Then test still-air, headwind, tailwind and crosswind with stage air-relative velocity. |
| Tyres and finite geometry | Combined friction, relaxation and finite-arm coupling exist; the model remains an estimate. Finite-width contact, load/slip calibration and independent obstacle/impact refinement remain owned RC work. | Measured tyre/load data; split-grip and one-wheel-airborne fixtures; contact-footprint and time refinement separately. Avoid importing full-size-road-car coefficients without evidence. |
| Differential, ESC and battery | Equal wheel drive torque and simplified electric drive are declared compact-model choices. An explicit differential/shaft inventory and calibrated car power/resource models remain open. | State power-flow direction, losses and limited-slip/open/locked semantics; test airborne wheels, reversal, braking, depletion and thermal limits under the chosen model. |
| Fuel mass and thermal behavior | R3-G01 already covers changing nitro fuel without body mass/CG/inertia updates; richer thermal/resource behavior is not calibrated. | Reconcile structural and fuel inventories, then include continuity and restart/refuel/recording boundaries. Do not count this again as a new R9 defect. |
| Wall solve cost | Current wall handling reconstructs geometry and factors another generalized mass matrix after the base solve. R9-F01 repair may permit reuse. | Measure complete accepted-tick cost and residual quality on paired states, including validation and telemetry. An avoided factorization is an opportunity, not a measured saving. |
| Rest fast path | R9-F02 shows why skipping a mathematically necessary operation is not an acceptable optimization. | Prove an invariant or residual bound first; benchmark only the corrected behavior. |
| Allocation/history | Nitro model/control copies are already R3-O01; input-tape/checkpoint growth is already A31. | Use allocation and sustained-session measurements with owned-state/replay checks; avoid treating immutable artifact identity checks as disposable overhead. |

For an eventual drag extension, the scalar reference is `D = rho*C_D*A*V_rel²/2`, with direction opposing relative airflow and a separately declared moment arm. [NASA's drag equation guidance](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/drag-equation/) also emphasizes matching the coefficient to its reference area. No RC coefficient, real top-speed error or tuned value is inferred from that equation alone. Integrate any accepted air load before the tyre/brake solve, so the wall-composition mistake is not repeated.

### Lower-priority candidates not promoted

Source tracing found a nitro input/readiness question: after a recognized gamepad has already supplied neutral and remains armed, a newly held B/Circle reverse flag can be cleared by the nitro adapter before the garage's neutral readiness check. With neutral triggers this may permit resume despite the “release controls” contract. With B still held, throttle maps to brake, so this is not evidence of unintended propulsion. Initial connection/modal rearming still requires actual neutral. The composed rendered activity was not executed; keep it as a source-only follow-up, not a reproduced defect count. Source: [input adaptation](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/vehicles/ground/ground_scene.gd#L539), [ready/resume logic](https://github.com/bultodepapas/OpenRCsimulator/blob/77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b/app/vehicles/ground/ground_scene.gd#L905).

A reduced fixed-chassis calculation also suggested first-order coupled-clutch error from the nitro update's frozen initial wheel speed. The implementation describes a midpoint **engine** update, not a proven globally second-order coupled method. No material integrated error was established, so it is not promoted as another defect. Likewise, pre-existing still-water limits, parallel steering, the 128-sweep cap and unmeasured physical parameters are not new R9 discoveries.

## Verification, current CI and repair sequence

The [source manifest](ninth-pass-sources.json) pins all runtime/test files used by the portable reconstruction. The executed jobs are:

| Checked job | Checks / result |
| --- | --- |
| Clean import | Passed; zero errors/warnings |
| Wall witness | 25 checks passed |
| Heading witness | 7 checks passed |
| Nitro witness | 14 checks passed |
| Real session boundaries | 39 checks passed |
| Unchanged `test_rcv_vehicle_data.gd` | 35 printed assertions passed |
| Unchanged `test_rcv_obstacle_contacts.gd` | 14 checks passed |
| Unchanged `test_rcv_nitro_session.gd` | 28 checks passed, including its existing recording/replay cases |

The new checkpoint check is same-state admission/restoration; broader replay evidence belongs to the unchanged nitro baseline and future repairs. Observation probes intentionally assert the current discrepancy. A successful audit probe means the finding is reproducible, not that production physics has been corrected.

The [separate CI snapshot](ninth-pass-ci-snapshot.json) records associated run [44968787343](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44968787343) as **failed**. RC native Linux/Windows build and production-check jobs passed in that run. The six inspected failed-job logs instead report synthetic PR merge checkout `07c52c1e766c1b2457cc18c0534eeee6ef03d50c`, merging this branch head into `1f24cb067ca73cc20963f65ad613e7deb4c3899b`; those results must not be described as exact-branch R9 executions.

Observed failures include fixed-wing rate-derivative provenance, companion solver qualification mismatches, a Home-flight assertion whose cause is not established by the preceding native-library warning, and missing `psutil` in the separate Windows testqueue run. They are not first-failure reports from the RC truck tests, but they still prevent whole-project CI acceptance. MetalFX source controls passed. No failed job was rerun or bypassed during this investigation.

Recommended order is to repair **R9-F01 load composition** and **R9-F02 the unjustified shortcut**, then qualify both through the shared/native transaction and replay contracts. Advance the existing RCV-12 shaft inventory next, while physical tyre, drivetrain and aero calibration follow their owning experimental plan. Keep changes independently reviewable: numerical correctness, source/backend identity, regression behavior, physical validation and runtime cost require different evidence.

Three independent helper tracks reviewed contact mathematics, drivetrain/resource mechanics and adversarial integration/deduplication. The adversarial review accepted the two bounded contact findings and session evidence, retained RCV-12 ownership, and rejected stronger ordinary-gameplay, physical-pitch, native-execution, perfect-convergence and measured-speedup claims. Preliminary scratch assertions that equated the real airfield's settling state with the exact flat equilibrium were corrected to compare matched prepared states; the retained final reproducer uses that distinction.

### Reproduce

Use a checkout containing the reviewed Git objects and unchanged reviewed checked-runner tooling, the official pinned Linux x86-64 executable, Python 3 and NumPy (captured version **2.3.5**). From the repository root:

```sh
python3 -B docs/research/project-audit-2026-11-21/probes/reproduce_ninth_pass.py \
  --repo-root "$PWD" \
  --godot "$PWD/.tools/Godot_v4.8-beta2_linux.x86_64" \
  --out /absolute/new/r9-evidence-directory
```

The output directory must not exist. The runner preserves pool/testqueue admission settings and uses `run_checked` for every engine job, with warnings treated as errors and required completion markers. Require `R9_REPRODUCTION_COMPLETE`, final `ok: true`, eight clean reports and successful independent oracles. A child exit code of zero alone is insufficient. No source or user profile is overwritten, and the original A36 PDF/ZIP remain untouched.
