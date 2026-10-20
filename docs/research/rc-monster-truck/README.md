# RCV-00: repository and source investigation

**Date accessed/inspected:** 2026-10-13. **Scope:** research for the requested RC monster-truck plan. **Status:** documentation only; no truck implementation, model download/import qualification, physical measurement or benchmark was performed. The [active plan](../../plans/rc-monster-truck.md) owns recommendations, steps and acceptance gates, including the complete Blender developer letter.

Three Luna Max sub-agents investigated repository integration, vehicle/ground physics and Blender/reference assets. The lead inspected shared shell/catalog/camera code, checked primary sources and reconciled the recommendations. A second review examined mechanics and integration. Intermediate reports were working notes under ignored `tmp/`; the durable findings are consolidated here and in the plan.

Subsequent implementation evidence is recorded separately in [RCV-04a: suspension bench](RCV-04a/README.md), [RCV-04b: coupled four-corner support](RCV-04b/README.md) and [RCV-14a: MT8 visual intake](RCV-14a/README.md). This source-investigation snapshot retains its original planning scope.

Native evaluator build, ABI, parity and packaging instructions are in the [native ground-vehicle guide](../../../research/rc-monster-truck/native/README.md).

## Evidence method and boundaries

The initial repository commit was `fe4891bdccb8acff7e00975234a0d94106ef63c9`. This was a live, dirty workspace, not a clean immutable release. Other tracks changed flight, lake, crash, glow, menu and Workshop files during the investigation. No assertion here attributes those changes to RCV work. Recheck current files before implementation.

Discovery used the existing `C-DEVELOPMENT-OpenRCsimulator` codebase-memory graph with symbol search, call tracing and snippets. Some stored line ranges returned unrelated current source, so findings were verified against the live files. Links below use stable paths/functions rather than stale line numbers. Source hashes captured at the end of the investigation identify the inspected integration baseline separately from Git HEAD.

External sources are primary manufacturer pages, official software documentation/source, original papers and creator-hosted asset pages. Product dimensions and speed statements are manufacturer claims, not measurements made for this project. Library documentation is architecture/model evidence, not RC parameter calibration. Asset-page license labels were inspected; candidate meshes, embedded content and exact downloaded-license bundles still need review. No absence claim is exhaustive: the search did not establish a ready-to-ship, correctly articulated RC truck asset.

Godot documentation was checked at the **4.7** path and through Context7's 4.7 documentation branch, matching the repo's 4.7.2 pin. Chrono's online manual and Jolt's rolling source are research references; an implementation must pin exact versions/commits before copying code, compiling a reference or recording numerical outputs.

## Internal seam audit

| Source / inspected symbols | Observation | Consequence |
| --- | --- | --- |
| [STACK](../../STACK.md), [project.godot](../../../app/project.godot), [get-godot.sh](../../../app/get-godot.sh) | Custom float64 flight state; Godot 4.7.2; Compatibility; 240 Hz and 12 catch-up steps | Preserve existing platform and float64 boundary; no engine migration required by the plan |
| [rigid_body.gd](../../../app/physics/rigid_body.gd), `derivative`; [integrator.gd](../../../app/physics/integrator.gd) | 13 body values: NED position, FRD velocity, body-to-world quaternion and body angular rate; six-entry symmetric inertia | Useful rigid-body substrate; dynamic hubs require more than a fixed inertia plus extra scalars |
| [simulation.gd](../../../app/sim/simulation.gd), `step`, `continuous_evaluate`, `checkpoint`, `can_restore_checkpoint` | Pure joint stage evaluation, tick-held aux/modes, continuous suffix and transactional/checkpoint machinery; four input values | Reuse only through an explicit truck contract and supported mechanical formulation |
| [flight_session.gd](../../../app/sim/flight_session.gd), `setup`, `_prepare_aircraft`, `_commit_aircraft`, `_physics_process`, `reset` | Aircraft ID/loader/control/trim/propulsion/ground/crash policy is intertwined | A sibling ground session avoids fake wing/aero/trim data and repeated truck branches |
| Same file, `_wheel_evaluate`, `_ground_evaluation` | Aircraft wheel continuous state is integrated with body state and propulsion | Useful lifecycle example; not an existing drive-axle interface |
| [ground_wheels.gd](../../../app/physics/ground_wheels.gd), `frame`, `evaluate` | Per-contact terrain, slip, rolling resistance, combined grip bound, rim-speed derivatives and brake input. Existing wheel law does not supply driven axle/differential mechanics or full gyro coupling | Retain equations/tests where compatible; truck contact orchestration and drive torque are new |
| [ground_contact.gd](../../../app/physics/ground_contact.gd), [ground_start.gd](../../../app/physics/ground_start.gd), [wheel_profiles.gd](../../../app/physics/wheel_profiles.gd) | Fixed body-relative gear contact inventory, static anchors and support solves; travel-limit detection tied to aircraft policy | Truck needs support initialization, real suspension coordinates/stops and nonterminal chassis contact |
| [ground_terrain.gd](../../../app/physics/ground_terrain.gd), [ground_surfaces.gd](../../../app/physics/ground_surfaces.gd), [surface_friction.json](../../../app/data/ground/surface_friction.json) | Deterministic field regions, material factors and small analytic relief | Reuse semantics/identities; not a jump course, soil mechanics or finite tire envelope |
| [GP-05 evidence](../ground-physics/GP-05/README.md) | Estimated 1/4/7 mm relief for runway/mown/rough surfaces; nearby render normals share the formula but coarse terrain is not displaced by it | Close-up RC obstacles require explicit rendered geometry that agrees with physical queries |
| [commands.gd](../../../app/input/commands.gd), [keyboard.gd](../../../app/input/keyboard.gd), [rc_input.gd](../../../app/input/rc_input.gd), [rc_calibration.gd](../../../app/input/rc_calibration.gd) | Aircraft channels, hold-throttle keyboard and low-throttle arming | Centered car triggers and brake/reverse need their own mappings, neutral recognition and state machine |
| [aircraft_catalog.gd](../../../app/app_state/aircraft_catalog.gd), `ENTRIES`, `flyable_ids`, `can_fly` | Seven configurations/five airframes in the inspected tree; existing consumers assume airplane data | Add a product catalog facade and ground catalog; preserve aircraft loops |
| [app_root.gd](../../../app/app_root.gd), `show_home`, `start_flight`, `set_aircraft` | Home and direct routes construct `main.tscn`; rejected starts restore Home; settings are interactive-only | Explicit vehicle dispatch and capability-aware preview/action/start choices |
| [home.gd](../../../app/ui/home.gd), [home_scene.gd](../../../app/ui/home_scene.gd), [preferences.gd](../../../app/app_state/preferences.gd) | Aircraft-specific card/preview/labels and schema-4 preferences validated against the aircraft catalog | Add compatible vehicle selection/preferences rather than reinterpreting existing aircraft fields |
| [screen_stack.gd](../../../app/ui/screen_stack.gd), `set_session`, `_sync_hold` | Accepts a Node, calls hold/release for `menu`; releasing a hold does not resume | Already reusable; no screen-stack redesign needed |
| [pause_menu.gd](../../../app/ui/pause_menu.gd), `show_for`, `refresh`, `status_text` | Reads `is_flyable`, `pause_reason`, `crash`, `crash_auto_restart` | Activity/pause-profile adapter must translate policy and labels |
| [app_root.gd](../../../app/app_root.gd), `open_pause`, `continue_flight`, `restart_flight`, `end_flight`, `_trace_saved_or_discarded` | Calibration, aircraft overlays/Workshop and recorder assumptions beyond menu holds | Generic hold/release alone is insufficient for full product integration |
| [trace.gd](../../../app/sim/trace.gd), [recorder.gd](../../../app/sim/recorder.gd), session `trace_meta`/`checkpoint` | `openrc-trace v3` base CSV is flight-specific; flight metadata/checkpoint versions are separate formats | Truck trace/checkpoint envelope must name actual controls and complete replay identity; share recorder lifecycle only |
| [camera_rig.gd](../../../app/render/camera/camera_rig.gd), [chase_view.gd](../../../app/render/camera/chase_view.gd) | Pilot/chase/orbit/close-up; wingspan-scaled boom, horizon lock, terrain-height clearance | New truck profile and obstacle clearance; no claim that full camera collision or FPV is already implemented |
| [frames.gd](../../../app/render/frames.gd), `ned_to_render`, `quat_to_render`, `root_transform` | Render `(x,y,z)=(east,-down,-north)` and CG offset | Keep the conversion; add truck datum bindings instead of a wing-reference origin |
| [collision_world.gd](../../../app/scenery/collision_world.gd), `build`, `nearby` | Scalar obstacle inventory, stable sorted IDs, bounded spatial bins and hash; queries return nearby proxies | Reuse collision discovery/data identity where compatible; sustained tire/chassis response remains new |
| [crash guide](../../CRASH-DAMAGE-PLAN.md), [crash director](../../../app/render/crash/director.gd) | Airplane crash and wreck presentation have separate authority | Ordinary truck rollover must stay in truck simulation, with no premature wreck handoff |
| [Timber asset guide](../../../assets/aircraft/turbo-lumber-evolution/README.md), [TT-02](../timber-integration/TT-02/README.md), [TT-05](../timber-integration/TT-05/README.md) | Imported GLB measurements and articulation witnesses; fixed mount plus identity driven pivot avoids rest-basis overwrite | Reuse authoring/import verification practices, not aircraft node contracts |

The [aircraft contract](../../AIRCRAFT_CONTRACT.md) requires aircraft references and explicit capability modules. It is not an existing generic vehicle schema. The [helicopter](../../plans/helicopter.md) and [drone](../../plans/drone-racing.md) plans identify similar loading/session/input limitations. Their pending generalization is coordination context, not implemented truck support. The [Aircraft Workshop plan](../../plans/aircraft-editor.md) targets aircraft variants; live Workshop hooks appeared during the audit and must be preserved.

## Manufacturer reference

Source **M1** is Traxxas's [T-Maxx 3.3 product page, model 49077-3](https://traxxas.com/t-maxx-33-49077-3?learnmore=y#tab-label-specs). Source **M2** is the [49077-3 owner's manual, KC25005-R00](https://traxxas.com/media/productattach/C-49077-3/2/KC25005-R00-49077-3-T-Maxx-TQi-Owners.pdf). Browser retrieval of the product page was blocked and a rendered scrape omitted its specification tab. Both the reference sub-agent and the lead subsequently read the official static HTML successfully with PowerShell `Invoke-WebRequest -UseBasicParsing`; its table explicitly contains the numeric rows below. These are manufacturer-listed values, not measurements performed for this project. The sub-agent read the 32-page official manual for the nitro/eight-shock configuration. Reconfirm revision and operating conditions when freezing the reference.

| Field | Published reference | Interpretation |
| --- | --- | --- |
| Marketed scale | 1/10 | Distinct from the user's requested approximately 1/8 truck |
| Length / overall width / height | 539 / 417 / 277 mm | Reference package dimensions; not accepted dimensions of the new model |
| Front / rear track | 417 / 417 mm | Separate manufacturer-labelled rows; see the width/track consistency caveat below |
| Wheelbase | 335 mm | Candidate source dimension to cross-check against the chosen asset |
| Listed weight | 4.54 kg | Operating/fuel/accessory condition must be identified before physical use |
| Center clearance | 106 mm | Verify rest/preload/tire conditions before comparison |
| Suspension | Nearly 4 in travel; manual describes eight oil-filled shocks | Travel and shock count do not establish rate, damping or unsprung mass |
| Drivetrain / traction power | Shaft-driven 4WD, two-speed forward transmission, TRX 3.3 nitro | EZ-Start is a starter, not electric wheel propulsion |

Do not substitute overall width for mechanical center-to-center wheel track. The official table lists Width, Front Track and Rear Track separately but gives the same 417 mm for all three. Traxxas's [glossary](https://traxxas.com/support/glossary/) defines track between wheel centerlines. Preserve the published rows, flag their equality as a consistency question, and verify wheel-center hardpoints before using them for support geometry/SSF. Nominal scale labels also do not define an exact physical prototype. Neither `mass*1.25` nor an unqualified `mass*1.25^3` produces a calibrated 1/8 RC model.

Additional official reference links:

- **M3:** [parts list](https://traxxas.com/media/productattach/C-49077-3/3/49077-3_parts.pdf), for component names and assembly revision.
- **M4:** [front assembly](https://traxxas.com/media/productattach/C-49077-3/5/49077-3_TMaxx33_TQi_explodedviews-250825_49077-3%20Front%20Assembly.jpg) and [rear assembly](https://traxxas.com/media/productattach/C-49077-3/5/49077-3_TMaxx33_TQi_explodedviews-250825_49077-3%20Rear%20Assembly.jpg), for mechanical relationships; illustrations are not engineering tolerance drawings.
- **M5:** [driveshaft assembly](https://traxxas.com/media/productattach/C-49077-3/5/49077-3_TMaxx33_TQi_explodedviews-250825_49077-3%20Driveshafts%20Assembly.jpg), [chassis assembly](https://traxxas.com/media/productattach/C-49077-3/5/49077-3_TMaxx33_TQi_explodedviews-250825_49077-3%20Chassis%20Assembly.jpg) and [transmission](https://traxxas.com/media/productattach/C-49077-3/5/49077-3_TMaxx33_TQi_explodedviews-250825_49077-3%20Transmission%20Assembly.jpg).
- **M6:** [legacy model/manual index](https://traxxas.com/articles/PDF-Downloads-Legacy-Models), only when the selected reference is an older T-Maxx revision. Do not mix mechanisms across years without identifying the difference.

These documents establish appearance/configuration references, not redistribution rights for their photos, logos, drawings or CAD. They are linked rather than copied into runtime assets.

## Primary technical sources and conclusions

| ID / source | Evidence used | Decision supported / limit |
| --- | --- | --- |
| T1 — [Godot 4.7 VehicleBody3D](https://docs.godotengine.org/en/4.7/classes/class_vehiclebody3d.html) | Ray-based vehicle system; documented realism limitations; gearing is not supplied automatically | Compare as an available prototype; not the proposed laboratory solver |
| T2 — [Godot 4.7 VehicleWheel3D](https://docs.godotengine.org/en/4.7/classes/class_vehiclewheel3d.html) | Wheel node belongs to the engine vehicle system and carries the same realism warning | A node with a suspension property is not evidence of measured RC suspension |
| T3 — [Godot 4.7 precision](https://docs.godotengine.org/en/4.7/tutorials/physics/large_world_coordinates.html) | Scalar GDScript float is 64-bit; official-build vector types use 32-bit components | Preserve the project's scalar float64 simulation/render boundary |
| T4 — [Godot physics troubleshooting](https://docs.godotengine.org/en/4.7/tutorials/physics/troubleshooting_physics_issues.html) | High-speed vehicle instability/tunneling requires attention to spatial travel and physics rate | A 240 Hz setting does not prove small-obstacle capture |
| T5 — [Chrono tire models](https://api.projectchrono.org/wheeled_tire.html) | Distinguishes rigid, handling and deformable tires; terrain contact/enveloping and transient low-speed models have different purposes and limits | Separate force law, wheel geometry and soil; identify small-tire parameters independently |
| T6 — [Chrono suspension models](https://api.projectchrono.org/wheeled_suspension.html) | Bodies, spindle joints, force elements and simplified wishbone constraints form explicit subsystems | Reduced kinematics is viable, but hub mass/reaction cannot disappear from dynamics |
| T7 — [Chrono driveline models](https://api.projectchrono.org/wheeled_driveline.html) | Torque/speed connections, shaft-based 4WD and simpler kinematic differential models | Choose a declared drivetrain and enforce its constraints/power accounting |
| T8 — [Chrono powertrain models](https://api.projectchrono.org/vehicle_powertrain.html) | Explicit drive torque, shaft speed, gears and motor-block reaction | Motor/battery kernels need a vehicle installation, not a speed command applied to the chassis |
| T9 — [Chrono terrain](https://api.projectchrono.org/development/vehicle_terrain.html) | Rigid and deformable terrain families; geometry/contact and cost vary by representation | Rigid physical course first; soil deformation is a separate measured capability. Development documentation is not a pinned implementation |
| T10 — [Jolt repository/license](https://github.com/jrouwe/JoltPhysics) | Existing MIT vehicle/collision source is downloadable | Inspect/reuse appropriate bounded algorithms before inventing equivalents |
| T11 — [Jolt architecture](https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md) | Double-world positions coexist with float velocity/rotation and other calculations | A double-position build alone does not satisfy this repo's all-float64 simulation-state rule |
| T12 — [Jolt 5.6.0 cylinder wheel collision source](https://jrouwe.github.io/JoltPhysicsDocs/5.6.0/_vehicle_collision_tester_8h_source.html) | Wheel collision testers include a finite cylinder shape | Candidate geometric reference; not proof of RC tire deformation or multi-contact accuracy |
| T13 — [NHTSA rollover resistance proposal](https://www.nhtsa.gov/sites/nhtsa.gov/files/rolloverresistance.pdf), 2002 | Static stability factor uses half track divided by CG height; dynamic tests complement it | Static geometric oracle only. No current legal guidance or transfer of road-crash statistics is intended |
| T14 — [Pokhrel, Datar and Xiao, in-air vehicle maneuver](https://arxiv.org/abs/2503.19140), submitted 2025-03-24; [IROS DOI](https://doi.org/10.1109/IROS60139.2025.11246862) | Primary research demonstrates airborne attitude control through existing throttle/steering commands | Supports investigating wheel/shaft momentum; its learned/planning system and research platform are not this truck's calibration |
| T15 — [Elsermans and Steckel, TruggySense](https://arxiv.org/abs/2505.07399), submitted 2025-05-12 | Data acquisition on a Team Corally Kagama 1/8 RC vehicle; experiments examine measurement behavior | Particularly relevant measurement-platform precedent; no ready-made validated monster-truck parameter set is claimed |

The plan's suspension equations, contact policy, exact state layout, choice of electric-first configuration and acceptance numbers are engineering proposals. They are not prescribed by Godot, Chrono, Jolt, NHTSA or Traxxas. The 20 m/s → 83 mm/tick example is arithmetic (`v/240`) illustrating contact resolution; it is not the planned vehicle's promised speed.

## Free asset reuse candidates

Candidate-page review only. No archive was downloaded or imported during this planning task, and no candidate is selected as the final vehicle. Source the actual license bundle and inspect objects/materials before acceptance. The [Blender handoff](../../plans/rc-monster-truck.md#13-letter-and-delivery-contract-for-the-blender-developer) makes this the developer's first milestone.

| ID / creator source | Page evidence | Fit and unresolved work |
| --- | --- | --- |
| A1 — rgsdev, [Free Low Poly Vehicles Pack](https://opengameart.org/content/free-low-poly-vehicles-pack), published 2022-07-12 | Creator page labels CC0, lists a Bigfoot monster truck and separated wheels, and provides a ZIP | Strong first candidate for a reusable preview/prototype; RC chassis, independent suspension, pivots and dimensions unverified |
| A2 — [Kenney Car Kit](https://kenney.nl/assets/car-kit) | CC0, 45-file model kit with download available | Useful generic vehicle/components; does not establish a T-Maxx-like asset or working suspension |
| A3 — vvaris, [BlendSwap Monster Truck](https://blendswap.com/blend/3057) | CC0, Blender 2.5-era source listed | Editable source candidate; conversion, materials and articulation may require substantial work |
| A4 — Steel Cyclone Studios, [Free Monster Truck Model](https://sketchfab.com/3d-models/free-monster-truck-model-96d16754451d4ca3a0b4c5252452f0b5) | Reference sub-agent read a successful hosted scrape stating CC Attribution 4.0, downloadable FBX and about 177.3k triangles; lead browser fetch returned 403 | Secondary candidate requiring fresh page/file/license confirmation and simplification; not accepted or downloaded |
| A5 — [Poly Haven models](https://polyhaven.com/models), [license](https://polyhaven.com/license) | CC0 asset library | Look for suitable materials/props before authoring them; no matching RC truck established by this search |
| A6 — [ambientCG license](https://docs.ambientcg.com/license/) | CC0 assets | Surface/material source; no truck mesh identified |

Asset reuse is not restricted to entire vehicles. A downloaded tire, material or mechanical component can reduce authoring while retaining a coherent visual direction. Reused source licenses remain with their assets and are not relabelled MIT. A matching name/preview does not prove appropriate geometry, branding clearance, transforms or performance.

## Model/data gaps that research does not close

| Missing evidence | Why publication/reference imagery is insufficient | Next evidence |
| --- | --- | --- |
| Final 1/8 dimensions/mechanism | T-Maxx is a different scale and nominal RC scales vary | Dimensioned asset/reference proposal, physical hardpoints and source measurement |
| Ready-to-run mass, CG and tensor | Product weight and mesh volume omit inventory/distribution | Component/corner weighing, CG-height measurement, inertia experiment |
| Wheel/tire properties | Tire diameter/tread do not determine foam stiffness, loaded radius, friction or spin inertia | Identified tire/foam/load tests and inertia estimate/measurement |
| Spring/damper behavior | Travel, shock count and oil label do not establish force laws | Travel-force and force-speed data, motion ratios and rebound records |
| ESC/motor/gearing | Aircraft electric kernels and marketing speed do not identify car brake/reverse/current response | Selected hardware manuals plus voltage/current/RPM/torque/drive-mode tests |
| Grass/dirt coefficients | Surface names hide moisture, compaction, tire and speed effects | Controlled coast/brake/slip runs on identified surfaces |
| Jump/rollover handling | Geometry or a video alone cannot identify coupled inertia and contact impulse | Synchronized commands/video/telemetry with uncertainty and held-out trials |
| Fun/readability/performance | Headless equations and studio renders do not show control feel or native frame pacing | Novice/RC-user driving trial and target-machine full-scene measurements |

No calibrated tire curve, final body design, spring rate, damper coefficient, CG height, mass/inertia, motor specification or vehicle top speed is invented as a completed result. The active plan requires these values to be measured, sourced or explicitly estimated before they enter validated runtime data.

## Review outcome and verification of this delivery

The mechanics review clarified four points in the plan: P1 massless suspension must be constrained through a support/virtual-work formulation; dynamic hubs require their orbital as well as spin momentum; P2 lessons depend on contact/suspension/air-coupling/course gates; and refinement rates are offline/effective references while the production outer clock stays at 240 Hz.

The shell audit confirmed that ScreenStack already has the needed hold/release boundary. The additional adaptation belongs in the activity host and pause profile, because current callers assume aircraft airworthiness, calibration, crash, overlays and recorder behavior.

Delivery checks passed: 78 local Markdown links/anchors across the two new documents, the ordered RCV-00…34 step rows, paired code fences, and `git diff --check` on the edited tracked documentation. The physics suite, Blender import, physical experiments, exports and performance benchmarks were **not run** for this plan and are not reported as passing. Existing dirty runtime work was preserved.

## Inspected source-byte snapshot

Captured on 2026-10-13 after the source review. HEAD had advanced concurrently to `969c9feec15e0810bc3f7a5d8bbfe806bf6c500c`; these SHA-256 values identify working-tree bytes, including other tracks' edits, rather than asserting a clean checkout. They are a research snapshot, not generated runtime data.

| Path | SHA-256 |
| --- | --- |
| `app/project.godot` | `618f8592bffe8be27dd9611bba8e059e03aac2ac68e3c58ab903235b4d874b04` |
| `app/get-godot.sh` | `02f30a3bd644f85887a0bc6843f5a70645bd1e04aca47c38bf22a39d58054456` |
| `app/app_root.gd` | `a0ec35d0e2d8d6fd40a5fe33f267c6f62b267580cd791a52699d4e4874176ad0` |
| `app/app_state/aircraft_catalog.gd` | `dbebfa17638893990224370815975c81495ad85cb80dbc3e73c4fe8a4767c47b` |
| `app/app_state/preferences.gd` | `d7a2ddfa119acabc9c7fa1aee8e291937a6edeb8684c46294623289db486a4bf` |
| `app/sim/simulation.gd` | `4da92d66a613df03ddd1e7dc4257e97769199ccfb135223f0ef8aaeefe0d5404` |
| `app/sim/flight_session.gd` | `935c713d05e16e9e63964a7d83d8f2f1060eb46249a2b1bbd98377df5263b60f` |
| `app/physics/rigid_body.gd` | `b39f7041b05bf9f9ed8bef9b61eac123627e314cd994dcf529687b52cf4096a3` |
| `app/physics/ground_wheels.gd` | `76fbaefb1c1495493e89f947a6a017f46286719e56e9df1ebe0cb46ade353d14` |
| `app/physics/ground_terrain.gd` | `9373dfc3410ed1eb1dd129e8445f76598ee450c627155a4dd1f8da79b6a7d757` |
| `app/ui/home.gd` | `14e16121258b10669f5c8d085bc475dfcd5d9b530c866bea6231e2cc343cf744` |
| `app/ui/screen_stack.gd` | `3ca8ec8f07e372c8c4ecf6176a4368bf7f2cefaa2f0e44a2f5e61a94e47e1c0f` |
| `app/ui/pause_menu.gd` | `2d79fd65fa100111a482c86b665e2bc12785740b144ca17eecceb2c68e899f08` |
| `app/render/camera/camera_rig.gd` | `383d80da7103f09016af9f906c504bff3c52fa4634d1332500e533e58591581c` |
| `app/render/frames.gd` | `8ada0562ffaa7039676f0a8c222fcf5f1211d1c2e196a55f182b05fd25c34bc9` |
