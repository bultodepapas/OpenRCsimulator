# Glider acceptance, implementation boundaries, and delivery

**Owner:** SG lead with each shared-track owner.  
**Status:** proposed acceptance plan. No tests in this matrix have been executed for a glider implementation.  
**Baseline:** `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`, reviewed 15 November 2026.  
The [master plan](../glider-soaring.md#7-delivery-sequence-and-canonical-step-status) is the only authority for SG step status; this document defines the proof each work package needs.

## 1. Definition of a usable delivery

A milestone is usable when its declared aircraft, start, weather, controls, replay and end condition work together. A successful force calculation, a menu item or a rendered glider is not that milestone.

The minimum solo story is: select the unpowered configuration → choose calm air start → see actual resolved conditions → start in a descending trim → control the aircraft → land → inspect the basic accepted outcome and complete recording → restart and replay. Comparative debrief and scored lessons are later SG-15 work.

The complete requested story adds: choose manual tug → glider AI maintains its own aircraft → fly and climb within the pair's envelope → invoke release-and-take-glider → retain glider control without an axis surprise → tug continues its recovery → glider soars and lands → the entire sequence restores/replays with the same ownership and line events.

Separate the following claims in every result:

| Evidence category | What it can establish | What it cannot establish alone |
| --- | --- | --- |
| Source review | Exact present interfaces and constraints | Executed behavior or physical fidelity |
| Unit/analytic mechanics | Correct equations, units, limits and invariants in fixtures | Calibrated RC aircraft |
| Numerical refinement | Error and event behavior for a stated case/envelope | Real-world model validity |
| Same-identity replay | Reproducible accepted simulation and recorded decisions | Correct aerodynamics or human usability |
| Independent physical data | Agreement within uncertainty for an exact RC build | Every weather, speed, pilot or modification |
| Pilot evaluation | Learnability, handling judgments and observed failure cases | Independent coefficient calibration by itself |
| Native/platform tests | The exact installed engine/backend/package on a named host | Other devices, builds or graphics settings |
| Rendered/controller evaluation | Real viewport readability and device behavior | Invisible state or numerical equivalence |

## 2. Work boundaries and proposed file homes

These are proposed homes to review against the current tree at implementation time. A path marked “new” is not evidence that code exists. Generated data and meshes must follow their source pipelines.

| Work package | Existing seams to inspect or extend | Proposed new homes / evidence | Shared owner |
| --- | --- | --- | --- |
| SG-01 absent propulsion | `app/physics/aircraft_modules.gd`, `aircraft_data.gd`, `physical_identity.gd`, schema registry/compiler, `app/sim/aircraft_propulsion_runtime.gd`; observation, contact rotor identity, trace/log, audio and Workshop consumers | Versioned absence/identity/observation contract through all consumers; evidence `docs/research/glider-soaring/SG-01/` | AS + physics, SF/FL/AE/AUD |
| SG-02 trainer | Aircraft inventory, geometry/control manifests, catalog, conformance; authored intended hull support and physical identity | New `research/glider-soaring/aircraft/` and aircraft asset/source directories chosen by AS; generated runtime output | Aircraft + AS/asset owners, GP/UI-FS |
| SG-03 glide | `aero.gd`, `wing_polar.gd`, trim/scenario and actuator paths | Polar/measurement reducer and bounded flight cards in owning research path | Physics/FT |
| SG-04/05 starts | `app/sim/flight_session.gd`, `app/app_root.gd`, shared launch resolver, input and staged-start tests; `app/physics/intended_hull_support.gd`, `app/statistics/profiles.gd`, `fixed_wing_adapter.gd` | Glider start adapter/recipe; accepted belly/skid outcome and minimum solo record/replay slice | Physics/UI/input/GP/UI-FS/FL |
| SG-06 environment | `wind_config.gd`, `wind_spatial_config.gd`, `wind_spatial_presets.gd`, `wind_thermal_field.gd` | Soaring scenario authoring using existing weather schema; no second wind engine | M5 + scenarios |
| SG-07 pair foundation | `vehicle_model.gd`, `simulation.gd`, `integrator.gd`, event/contact contracts | New `app/sim/soaring/` pair adapter/session if approved; generic SF extensions remain SF-owned | SF + physics |
| SG-08 line | Joint force evaluator and generic event boundary | New `app/physics/soaring/tow_line.gd` or agreed equivalent; analytic fixture and measurement source | Physics/SF |
| SG-09 tow installations | Per-aircraft inventory, generated mount/release and visual bindings | Source-owned FunCub/approved tug and glider hook data; no stock-hook invention | AS/aircraft/GP |
| SG-10/11 AI and handoff | Sampled-frame protocol and existing AI observation/controller utilities | New `app/ai/soaring/` guidance and actor ownership, with explicit admission profiles | AFC/input/session |
| SG-12 ground | Shared contact, point/hull geometry, prepared runway state, collision and event composition | Pair ground/abort evidence and qualified configuration bounds | GP/CR/SF |
| SG-13 UI/camera/audio | Shell, profile/actions, camera facade, HUD, localization, flight sound | Narrow integrations, optional glider presentation modules | UI/input/CAM/HUD/AUD |
| SG-14 failure | Existing failure adapters, physical propulsion source loss, release events | Tow-specific fault recipes with declared physical versus scripted semantics | EM/CR/SF |
| SG-15 logs/scoring | `app/sim/flight_log.gd`, trace/readers, statistics and debrief | Minimum solo outcome/record with SG-04; pair envelope/actor channels/replay before SG-10/11; richer debrief/scoring later | FL/UI-FS |
| SG-16/17 qualification | Existing tools, test queue, CI, source receipts and export/runtime admission | Evidence under SG steps; generated packages through existing release workflow | FT/PT/DT/NK |

Do not add all these files in one change. Start by proving one boundary with a synthetic fixture and the smallest relevant regression set. Coordinate mixed-purpose files whose hash changes invalidate AI/native source admission.

### Decisions that unblock parallel work

Use the bounded SG-07 experiment to choose the primary/secondary body layout, trial-rotation convention, both quaternion projections, per-stage validation, controller sampling, event arbitration and full-frame publication. Settle that design before production adoption or pair admission, not before the experiment that supplies its evidence. Before SG-10/11, freeze the minimum paired record's actor IDs, named inputs, version, accepted events and restoration semantics with FL. Before SG-12, demonstrate the policy for both contacts, ground release, the line, propulsion events and substeps.

The [proposed interface contracts](06-interface-contracts.md) also require an owner-approved effective-time/cadence convention, intent/result identity and duplicate handling, kernel-owned or proved transactional sidecar state, guarded ordinary pair publication, and declared replay comparison domains. Existing reset/restore guards and checkpoint serialization do not establish these ordinary-tick guarantees. The [implementation packets](05-implementation-packets.md) allocate the work; the [scenario cards](07-acceptance-scenarios.md) specify concrete stimuli and expected results without claiming tests already exist.

These are technical design deliverables, not new requests for user permission. Record accepted decisions in the existing decision log and link the proof.

## 3. Aircraft and environment test matrix

Test combinations must cover actual declared behavior. Do not weaken existing guards to make a scenario enter the matrix.

| ID | Case | Required observable result |
| --- | --- | --- |
| A01 | Valid pure glider and contradictory propulsion fields | AS-versioned absence passes registry, PhysicalIdentity and normalized model without invented motor/rotor IDs; invalid or incompatible combinations refuse before publication; old powered identities remain valid |
| A02 | Receiver battery, servos and absent propulsion | Installed masses/inertia and declared supply remain; absent propulsion observations, rotor/contact identity, trace/log/replay and audio agree without phantom fuel/shaft/RPM data; finite-battery behavior is separately qualified |
| A03 | Units, axes, wing area and CG | Authored quantities convert once; FAI wing-plus-tail area is not substituted for aerodynamic reference area |
| A04 | Calm descending trim across supported speeds | Force/moment residuals meet predeclared tolerances; actual sink and trim converge; no hidden altitude hold |
| A05 | Whole-aircraft polar | Best glide, minimum sink and their airspeeds are separately derived; transients are excluded or identified |
| A06 | Stall, sideslip, reversal and recovery | Supported loads are finite and continuous as specified; no fabricated post-stall measurements |
| A07 | Controls/servo limits, differential and optional braking surfaces | Commanded versus achieved response, signs and physical lift/drag/moment are consistent |
| A08 | Inventory/CG/ballast | Mass, CG, inertia and trim update consistently; out-of-envelope settings refuse |
| A09 | Airborne reset in head/tail/crosswind | Airspeed-derived initial state adds wind once and preserves valid descent |
| A10 | Hand release, cancellation and held action | Correct ground-relative release state, one accepted release, no continuing hand force or duplicate credit |
| A11 | Thermal core, positive-lift boundary and sink annulus | Analytical sign/amplitude and lifecycle match; no extra vertical force |
| A12 | Finite thermal expiry, offset and restart | Correct phase at start, expiry after the remaining lifetime, explicit repeat/new recipe |
| A13 | Equal position/time queried by either actor | Identical shared-field answer, independent of query order; no separate OU realization for the pair |
| A14 | Both-wing/tail station domain and finite horizon | All required queries valid; unsupported boundary rejects the whole candidate and explains the failure |
| A15 | Energy/TE/netto in calm, updraft and shear | Correct signs/work ledger, speed-height exchange and stated estimator biases/filter lag |
| A16 | Belly/skid accepted support and landing outcome | Matching authored hull identity/pose and soft-contact law feed accepted support/accident observations and UI-FS statistics; distinguish intended support, wrong-pose/incidental contact, touchdown, stop and incident; no duplicate outcome on restart/restore. Current observer scope is flat solid/no lake; unsupported terrain is refused or yields an unavailable result until separately qualified |

Weather correctness checks precede pilot difficulty claims. A preset's configured peak is not its actual lift at a particular altitude, radius, time, bank or aircraft sink rate.

The five base recipes in the [aircraft/weather dossier](03-aircraft-and-weather.md) are not runtime-ready JSON. Full-schema validation, serialized equality and flown tests remain required before they can be registered. A simple single-cell exercise must be solvable with the selected glider; do not compensate for a weak/unreachable thermal by secretly adding lift.

## 4. Coupled mechanics and event matrix

| ID | Case | Required observable result |
| --- | --- | --- |
| T01 | Two free masses, no external forces, taut line | Pair momentum preserved to the declared numerical tolerance; both equal/opposite forces present |
| T02 | Rotating off-center hooks | Correct hook velocity and moments; total angular-momentum accounting includes orbital and body terms |
| T03 | Slack, coincident endpoints and line shortening | No compression or zero-length normalization fault; damping/storage power remains non-generating |
| T04 | Elastic/damped analytic fixture | Frequency, decay and energy error match an independent equation or high-accuracy oracle |
| T05 | 1/2/4/8 substep refinement in an admitted envelope | Trajectory, tension peaks and event times meet predeclared tolerances; no clipping/softening to hide failure |
| T06 | Secondary quaternion in every relevant path | Trial q-to-rotation/inverse convention, stage validation, substep/event/accepted projection, reset and restore remain consistent; verify hook power and convergence without silently altering stored RK trial states |
| T07 | Failure injected in either body at each RK stage | Accepted pair, clock, controller/RNG/owner state and intent consumption unchanged; no accepted sample, physical event or score escapes. Diagnostic attempt/pause/fault/footer output may identify rejection at the unchanged accepted boundary |
| T08 | Commanded release at each admitted boundary | Exactly one event; no unexplained impulse or reattachment; SG-12 includes release during slack take-up and ground roll with defined contact, abort and ownership outcomes |
| T09 | Physical break if strength/event law qualified | Within-step threshold policy and timing are tested, including peaks missed by endpoint-only logic |
| T10 | Concurrent release/contact/source-loss events | Defined ordering/composition; unsupported overlap refuses without partial publication |
| T11 | Whole-pair checkpoint before/after release and transfer | Both aircraft, line, controls, sampled memories, weather and ownership restore consistently |
| T12 | Old/mismatched log or layout/backend | Explicit refusal or declared read-only compatibility; no silent one-aircraft replay |
| T13 | Airframe proximity and crossing trajectories | Tested pair exclusion/incident policy; no unnoticed pass-through reported as successful training |
| T14 | Ground take-up and glider/tug takeoff order | Both contact states, line geometry, clearance and abort outcome remain coherent |
| T15 | Tug or glider fault/crash, connected or separated | Defined whole-activity lifecycle and both final states; no frozen endpoint, discarded actor or false successful outcome |
| T16 | Post-release continuation and recovery failure | Physical state and one command source continue for both actors; released AI glider free-flight, later takeover, tug recovery/fallback and finish semantics are bounded and recorded |

Test the publication boundary separately from T07: an observer failing after commit leaves the new pair and event accepted, with an explicit fault/incomplete-record outcome. It cannot be reported as a rejected step or retried physical action. The baseline protects prepared reset/restore publication only; ordinary pair publication must be implemented and qualified. SC-08/09 cover both sides, including mutation/reentry and recorder failure.

T13 is a release blocker for credible paired training even if fully resolved aircraft-to-aircraft impact mechanics are deferred. The minimum acceptable alternative is a geometry-based exclusion/terminal incident policy whose checks are qualified across each simulation interval. It must prevent a success score for airframes intersecting. It does not establish structural crash realism. Reuse GP/CR collision infrastructure where applicable.

Carry the airborne T13 policy into SG-07/10/11 before an interactive pair milestone; retain the strictly separated SG-07 solver-fixture exception stated in the launch guide. SG-12 adds T14's ground/contact cases. A clear rendered rope cannot resolve an unknown slack path: test a candidate conservative enclosure that intersects an obstacle with clear endpoints, and require the [declared refusal/pause/terminal outcome without tow-success credit](01-launch-and-control.md#5-the-tow-activity-state-machine). Do not record a proved impact from an enclosure alone.

For a massless line with omitted weight, drag, sag and entanglement, retain that scope in scenario metadata. An independently measured force-extension curve and a declared weak-link experiment support the physical line; a guessed spring constant and a plausible render do not. Initial hook-kinematics and conservation fixtures use constant mass, fixed CG and rigid hooks. Finite-fuel tugs require a separate moving-mass/fixed-datum proof, including hook velocity and efflux bookkeeping; changing the CG sample alone does not pass it.

### Numerical tolerances

Declare tolerances before evaluating a candidate. Separate force and moment units, absolute/relative errors, position/angle/velocity error, energy drift, event-time error and the physical measurement uncertainty. Near zero use a justified absolute floor. Compare quaternion orientation consistently, including the q/−q representation.

A stability inequality is only a screen. Refine actual loaded cases with damping, hook rotation, slack transition and events. Verify expected convergence behavior where the equations are smooth; do not demand fourth-order behavior across every discontinuity or count a finer run as physical truth. If the tested stiffness envelope cannot meet cost and accuracy, narrow admission or adopt a separately reviewed solver policy. Do not silently change the application's configured 240 Hz rate; declared refinement experiments may select other fixed rates.

## 5. AI, ownership and workflow matrix

Start with a deterministic set of canonical trajectories, then a versioned multi-seed campaign. Keep failures and cancelled runs rather than replacing them with successful seeds.

| ID | Case | Required observable result |
| --- | --- | --- |
| C01 | AI tug / human glider, straight and banked tow | Both full dynamics run; adequate speed, geometry, terrain and tension margins |
| C02 | Human tug / AI glider | Follower uses actual surfaces and records saturation; no hidden kinematic position constraint |
| C03 | Release only, transfer only if admitted, combined command | The three semantics remain distinct and exactly replayable |
| C04 | Transfer with high/low throttle, inverted brake axis and different mixes | Actor-specific pickup prevents surprise deployment; actual actuator states stay continuous |
| C05 | Transfer during a turn, slack line and marginal recovery state | Defined admission/refusal and recovery; no control-writer conflict |
| C06 | Pause, focus loss, unplug and reconnect in every role | Entire world holds; correct profile/owner and pickup restored |
| C07 | Restart, pending preferences, Cancel and failed start | Accepted flight and unapplied draft semantics preserved |
| C08 | Tug engine failure, commanded emergency release and glider landing | Physical source loss and mission outcome use the proper owners |
| C09 | Same seed with different camera/render FPS/quality | Physical results do not depend on presentation settings |
| C10 | Wrong source receipt, unsupported weather and unavailable native | Clear refusal or existing qualified fallback; guards remain effective |
| C11 | Restore midway through takeover blending or axis pickup | Correct held command, ownership and remaining policy state |
| C12 | Both actors outside/near visible view | Useful feedback/camera action without unrequested control transfer |
| C13 | Combined transfer refused → release-only → later Take glider | Released glider has bounded AI free flight or whole-pair hold; readiness can recover; later atomic takeover preserves line state and emits no duplicate release or credit; replay/restore agrees |
| C14 | Recovery controller fault or unsafe encounter after takeover | Qualified fallback or one recorded whole-activity pause/fault/terminal outcome; both accepted states and current owner remain complete; no recovery-success claim |

A proposed first automated tow campaign should cover both human-role variants, two turn directions, calm and admitted nonzero wind, low/high admitted mass, nominal and boundary line configurations, and deliberately invalid starts. Add seeded turbulence only after deterministic conditions pass. The final number of seeds and success criteria should be chosen from the supported envelope and observed failure modes; a handful of successful sorties cannot justify a broad reliability claim.

The complete activity's device qualification includes keyboard, a supported gamepad and at least one actual RC transmitter profile. A narrower experimental playtest exposes only its verified control methods and identifies its support limits; this does not close the full SG-13 device scope. Record OS, device identity, calibration, axis polarity, deadband/rates/expo, mapping and connection sequence. Mocked axes establish software behavior only and cannot qualify an advertised radio.

## 6. Physical calibration and held-out validation

For the exact build, collect a configuration receipt: mass inventory; all-up mass; CG; inertia method/uncertainty; wing-only geometry; control throws and servo timing; installed hook location; receiver battery; surface/roughness assumptions; source model and date.

Use independent observations to estimate a limited set of parameters:

- Still-air or wind-corrected glide segments at several airspeeds, long enough to identify near-steady descent.
- Aileron/elevator/rudder responses and small perturbation recovery at known mass/CG.
- Stall onset and recovery within the evidence's supported regime.
- Hand-release motion from time-resolved video or appropriate lightweight instrumentation.
- Towline extension versus force, damping/repeated loading and release operation.
- Tug low-speed climb and turning capacity with the actual towing installation.

Select those measurements for the mode and physical claim being qualified. A solo airborne claim needs its glider/trim/control/landing evidence, but does not wait for measured hand-release behavior or the separate tug/rope program. Every installed component still belongs to that glider's mass/geometry receipt.

Separate calibration, model-selection and final held-out validation flights. Inspecting a holdout to choose or revise a model consumes its independence for the selected model even without coefficient refitting; classify those data as development and reserve a fresh final flight set. Freeze the selected model and metrics before final evaluation. Record wind, atmospheric density, sensor calibration and uncertainty. A sensor payload can materially change a small glider; reweigh the instrumented configuration. Video/photogrammetry is a method to evaluate, not assumed error-free truth.

Report residuals and uncertainty, not a single “realistic” score. If measurements are unavailable, ship only the specifically labelled experimental model and do not invent a measured sink rate, glide ratio, stall speed or weak-link force.

Use the existing flight logging and reducers. Preserve baseline `.orfl`, exact replay and candidate identity. Same-input candidate replay is open-loop: it does not recreate changed pilot adaptation, re-trim or a new physical controller. Human handling assessment needs a new recorded flight under stated conditions.

## 7. Recording, telemetry and debrief schema

Plan a versioned paired envelope that identifies:

| Group | Required contents |
| --- | --- |
| Identity | Source commit, engine build, backend/law/layout/protocol versions, both aircraft source hashes, hook/line and controller identities |
| World | Complete weather/terrain configuration, seed, resolved agenda, datum, epoch offset, bounds and horizon |
| Physical state | Both positions, orientations, ground/body velocities, rates, systems, actual actuators, line modes and any stored energy |
| Commands | Per-actor named final control commands at an explicit boundary for each accepted interval; human/AI owner, assistance/pickup state, cadence phase and requested inputs/intents kept distinct |
| Events | Start, release, break if admitted, transfer, contact, fault, pause/restart/restore and terminal reason with actor/request IDs, sampled/effective/publication time and order; external interventions distinguished from endogenous physical events |
| Replay | Complete initial pair checkpoint and identities; timed external interventions; final-command physics projection or full decision replay as declared below; explicit compatibility, incomplete-record and refusal policy |
| Observation | TAS/groundspeed, height definitions, energy/instrument signals, tension and geometric errors at declared sample times |
| Outcome | Complete/incomplete, stopped actor, any missing segment, assistance and challenge identity |

Do not label a collection of independent companion logs as an atomic fleet replay. Both replay modes need a complete initial pair checkpoint, the admitted source/build/backend/law/layout identities and an explicit command/event time convention. A noninitial current fixed-wing log row records inputs for the interval ending at that row's tick, while its k1 loads belong to the interval start; pair records must name an equally precise convention.

**Final-command physics replay** applies the named per-interval command tape plus authoritative timed external release/transfer interventions or their equivalent accepted-transition data. Final actuator commands alone cannot reconstruct those interventions. Recompute and compare endogenous contact/break events instead of also injecting them as commands. If AI is bypassed, compare a declared, versioned physical-state projection and its events; unchanged initial controller memory does not reproduce evolving integrators, pickup or cadence state. An exact result is exact within that declared comparison domain, not proof of full pair continuation.

**Decision replay** restores controller/arbiter and intent-ledger state, guidance phase, held commands, world/RNG identities and external input/intent tape; it re-executes the decision process and compares decisions, accepted events and the complete declared pair frame. A separate deterministic mechanism would need qualification before a solver-only mode could claim the same complete state. Refuse unsupported identities or label changed-candidate comparisons explicitly. A missing sample, failed observer or truncated prefix is incomplete, never exact complete replay. See [the interface record contract](06-interface-contracts.md#7-checkpoint-tapes-and-replay) and SC-10/13.

Debrief scores must read accepted events. Restored checkpoints, paused time, rejected steps and abandoned previews must not duplicate airtime, launch count, duration records or landing points. Store exact unrounded inputs; render rounding is presentation only.

## 8. Performance, UI, native and release gates

Measure the complete solo and paired activity at actual **1920×1080 first**, including controls, AI, both physics bodies, weather queries, rope, recorder, views and audio. Test higher resolutions after that and 720p as fallback. Record source/package, actual viewport/renderer, host/GPU, power state, warmup, timing windows and configuration.

Retain the existing 500 µs physics acceptance policy unless its owner explicitly adopts a measured pair-specific budget. A 240 Hz period of approximately 4.17 ms is not permission to consume all of it. Report full tick and frame p50/p95/p99/max, simulation-to-wall-time ratio, missed catch-up behavior, memory growth and sustained operation. Measure observers separately as well as the whole activity.

No cost claim follows from having only two aircraft: local station weather, substeps, event searches and recording can dominate. Disabled diagnostics, thermal visualization and companion systems should avoid unnecessary work. Graphics quality must not alter physical time, polar fidelity, weather or controller decisions.

For native adoption, pin the correct complete new law and all data/layout contracts, maintain reference fallback, and follow the current parity/source/target-host policy. A pre-existing fixed-wing native binary does not establish a glider/tow backend. Qualify Windows, Linux and macOS packages through their existing owners; do not infer packaged success from an editor test.

Roll out by capabilities: solo experimental, then hand/thermal, then airborne pair, then ground pair. Apply SG-17's applicable cost, CI, export and platform checks to each distributed slice; it is not an end-only task. Advertise only tested support and retain the repository's required gates. Lessons can ship as exercises after their usability and stated model-scope checks; controlled learner studies are required for causal learning-effect claims, not as a universal package prerequisite. Update availability/help/catalog text only for admitted modes. Maintain read-only access to old logs where feasible and refuse incompatible restoration without silently rewriting data. Rollback removes the experimental capability/preset exposure while preserving saved user data and diagnostic evidence.

## 9. Risk register and unresolved decisions

| Risk | Consequence | Mitigation / proof owner |
| --- | --- | --- |
| Incomplete pure-glider mass/polar | Plausible-looking but wrong sink and stall | Exact build data and held-out flights; AS/FT |
| Published FAI area used as wing S | Incorrect wing loading and derived speeds | Planform measurement and provenance; AS |
| Second-body projection/event gap | Drift, incorrect impulses or partial rollback | SG-07 proof and SF contract decision |
| Rope too stiff for timestep | Unstable tension or hidden energy injection | Admission, convergence and qualified policy; physics/SF |
| No credible low-altitude lift | Hand-launch lesson becomes impossible | Short-glide lesson; air/tow thermal starts; M5/product |
| Actor-specific wind or epoch reset | Pair experiences inconsistent atmosphere | Shared pure field and complete identity; M5/session |
| Axis remapping at handoff | Unexpected full brakes/flaps | Named roles, pickup and real-device tests; input/UI |
| Unqualified AI recovery | Tug collides or freezes after transfer | Bounded controller/admission and geometry incident policy; AFC/CR |
| Implicit aircraft/rope contacts | False successful towing through obstacles | Explicit contact scope and exclusion/terminal checks; GP/CR |
| Unclear asset/data rights | Model cannot be distributed | Per-file source/license review before import; asset owner |
| Mixed schema/backend/log versions | Replay silently changes meaning | Complete receipts, versioned format and fail-closed restore; AS/FL/NK |
| Scope expansion into DLG/winch/ridge/network | Delays the requested useful core | Keep each later capability behind its own evidence and owner |

Decisions still needed include exact measured build, asset license, receiver-power fidelity, spoileron/airbrake support, selected line and release hardware, SG-07 representation, incident policy, supported initial weather envelope, instrument filter settings, and real-device/hardware test coverage. The plan provides recommended defaults where evidence allows; remaining measurements are not replaced with guesses.

## 10. Handoff and verification protocol

For each implementation increment, provide: intended behavior; affected owner/step; exact source/config identity; scope of changes; smallest relevant existing checks plus new boundary tests; accepted output/refusal cases; retained failures; physical/visual/device limitations; and the next release gate.

Start with the [team entry point](README.md). Use [WP-01…15](05-implementation-packets.md) for bounded issue/PR scope, [proposed interface contracts](06-interface-contracts.md) for cross-owner decisions, [SC-01…20](07-acceptance-scenarios.md) for test design, and the [data/evidence kit](08-data-and-evidence-kit.md) for collection and claim receipts. These refine this guide; they do not create another SG status table, new runtime APIs or passed tests.

Start with existing checks such as `test_aircraft_contract.gd`, `test_aircraft_modules.gd`, `test_trim.gd`, `test_hand_launch.gd`, `test_flight_session_staged.gd`, `test_sf_vehicle_model.gd`, `test_sf_framed_sampled.gd`, `test_sf_event_protocol.gd`, `test_sf_event_refinement.gd` and `test_sf_contact_substeps.gd`. Relevant source links and additional log/companion seams are in the [review](../../research/glider-soaring/2026-11-15-source-review.md). Their current existence is not coverage for the new feature.

Use the [tool index](../../tools/README.md), [physics checks](../../tools/physics.md), [flight logging](../../FLIGHT-LOGGING.md) and repository test-queue instructions. Run broader coverage only for the shared boundaries actually changed or the required release gates.

This documentation-only handoff is verified by content, cross-reference, numeric-example and published-diff checks. It does not need a flight-simulation run and makes no claim of runtime, physical, native, controller or CI qualification.

## 11. Research-driven acceptance additions

The [24-investigation index](../../research/glider-soaring/2026-11-15-investigations.md) and its four source volumes retain the rationale. The rows below extend the existing A/T/C matrices and SG gates; they do not mark any check complete or require implementing every researched alternative. Choose thresholds from intended use, measurement uncertainty and the admitted domain before examining candidate results.

| Research | Owning gate | Additional observable acceptance |
| --- | --- | --- |
| GI-01 | A05; SG-03/16 | Withhold entire flights/runs and bound vertical-air/sensor timing bias; a synthetic updraft-contaminated measurement must not be accepted as an unbiased sink polar. |
| GI-02 | A04/A06; SG-03 | Record source dimensionality, Re and transition/finish; validate conversion/interpolation and regime boundaries; keep model-selection data separate from the selected model's final independent flight holdout. |
| GI-03 | A03/A08; SG-02/16 | Compare inventory with independent CG/inertia and identifiable control-response measurements; report suspension/fixture and parameter-correlation uncertainty. |
| GI-04 | A07; SG-13 | Sweep simultaneous roll/brake commands through saturation; compare left/right applied commands, achieved angles, pitch/yaw/drag and render bindings. |
| GI-05 | A10; SG-05 | Reconstruct correlated release state, transform tracked markers to CG, and compare the initial trajectory/rates without added post-release hand energy. |
| GI-06 | A06; SG-16 | Retain the evidenced rigid-airframe domain and deformation/modal limits; ordinary-flight agreement never creates an unmeasured strength/flutter threshold. |
| GI-07 | T03/T04/T09; SG-08/09 | For a physically supported line installation, fit installed loading/unloading histories and reserve whole histories for validation; compare loop work, rate, set and conditioning. Qualify weak-link failure separately. |
| GI-08 | T02; SG-09 | Establish joint trim and attainable transitions with hook moments, actual surfaces and excess tug power; record margins, not only overlapping speed ranges. |
| GI-09 | T01/T04/T07; SG-07 | Compare lagged exchange and same-stage coupling with independent per-hook work, energy and event residuals, including one-sided release/failure mutations. |
| GI-10 | T05/T06/T10; SG-08/17 | Compare credible numerical references over stiffness/damping/mass/closure boundaries, including hidden within-step events and bounded failure/cost. Distinguish a different constraint law. |
| GI-11 | T13: SG-07/10/11; T14: SG-12 | Qualify airborne swept aircraft exclusion before interactive pair admission, then ground expansion; test conditional rope bounds and conservative false positives. Inconclusive slack/contact clearance invokes the declared refusal/pause/terminal policy without successful-tow credit. |
| GI-12 | C01/C02; SG-10/11/14 | Exercise feasible turns/climbs, slack take-up, saturation and power loss in both human-role modes; label idealized sensors and retain ordered release/abort outcomes. |
| GI-13 | A11/A12; SG-06, M5 | Test actual provider boundary semantics and density-weighted flux against the expected volume term, with zero-cell/constant-density controls and refinement. |
| GI-14 | A13/A14; SG-06/07 | Compare multi-point covariance and complex coherence/phase across both wings/tails and aircraft; use analytic field and query-order controls before seeded statistics. |
| GI-15 | SG-03/06/15 | Compare bank/speed/offset/drift with measured banked sink, actual energy and remaining return/expiry margin; preserve weak-lift negative controls. |
| GI-16 | A15; SG-06/13 | Separate truth, sensor-derived and assisted channels; verify declared sampling/filter response, anti-aliasing, dropout, warmup, reset and restore. |
| GI-17 | SG-09/10/11 | Declare wake omission independently of collision clearance; do not use the 3D measurement extent as a runtime clearance rule. Future wake claims require exact-installation evidence. |
| GI-18 | A04/A09/A14; SG-06 | Pin atmosphere/polar/field/epoch/sensor identity and reject incompatible changes; include actual remaining world horizon and all station-domain limits. |
| GI-19 | SG-11/13 | Match each controller's real output boundary while preserving servo state; test saturation/lag/trims/flight modes and actual-device reconnect with one effective writer. |
| GI-20 | SG-13/17 | Evaluate native 1080p attitude/alignment/approach tasks over intended distances and backgrounds; record camera aids and the complete timestamped response chain. |
| GI-21 | T11/T12; SG-15/17 | Exact same-identity pair replay must survive cosmetic/RNG-query-order isolation checks; changed build/backend/law remains an explicitly classified comparison. |
| GI-22 | SG-16 | Freeze model selection and calibration before final independent prediction; predeclare intended-use metrics and separately report measurement, numerical and model error; investigate sensitive/confounded parameters. |
| GI-23 | SG-02/17 | Trace each imported mesh/texture/data/code file to exact origin/hash/notices, reviewed intended use and physical fit; generic repository licensing is insufficient evidence. |
| GI-24 | SG-15/16 | Predeclare accepted lesson outcomes, assistance/abort/refusal/reset rules and held-out scenarios; use comparison/repeated-baseline design for causal learning claims. |

### Required evidence package

For every admitted aircraft/mode/weather combination, retain configuration and source/build/law identity, declared scope and claim, question and metric, assumptions and limitations, applicable software/numerical checks and reference/refinement, retained failures and the actual result. Include hardware/controller/camera and release evidence where advertised. For a physical-fidelity claim or use of physical measurements, additionally retain the exact build/installation, raw synchronized measurement method, uncertainty/exclusions and calibration, selection and final-independent-validation split. For a purely synthetic fixture or experimental slice without physical measurements, mark those physical collection fields `not applicable: synthetic-only` and leave the physical claim unsupported. This does not waive applicable numerical, input, clearance, lifecycle, replay or release gates. The [evidence kit](08-data-and-evidence-kit.md) provides fill-in records for both scopes.

Record unknown distributions as bounded assumptions rather than invented probabilities. Use sensitivity to select the next useful measurement instead of broadening tests without a concrete question.

Pair logs distinguish requested intent, post-limit/arbiter actuator command and achieved actuator position. Instrument truth, sensor estimates and assistance are separately identified. Model, physical and learning claims use different evidence categories from section 1. A task refused for unsupported conditions is not a successful training sortie; an appropriate deliberate abort can satisfy a separately defined lesson objective.

The research changes impose no NASA organizational approval process and no mandatory MATLAB/SciPy/OpenFAST dependency. Their methods inform project-owned criteria. All simulator, bench, flight, real-device, display, performance and learner experiments above remain unperformed in this documentation change.

## 12. Select gates for the declared milestone and claim

The [master milestone table](../glider-soaring.md#milestones-and-dependencies) owns order and status. The slices below allocate this guide's evidence; they do not create new SG IDs or mark an entire cross-cutting step complete. State the aircraft/mode/weather/controls/platform and claim before selecting checks. Every applicable earlier check remains required.

| Delivery slice | Required software and user-flow evidence | Additional evidence when making the claim |
| --- | --- | --- |
| M0 / first data contract | A01–A03; generated-source consistency, explicit absence through all consumers and powered-aircraft compatibility | Independent mass/CG/inertia and geometry before a named physical-build claim |
| M1a / calm solo | A04–A09 as applicable; A16; input/focus/restart behavior; basic accepted outcome, complete recording and same-identity replay; first SG-13/15/17 slices | Held-out polar/control and actual build evidence for advertised physical fidelity; real devices/1080p and package gates for advertised playtest support |
| M1b / hand launch | A10 plus solo gates; correlated release state, cancellation/held-action and first-trajectory evidence | Measured release distribution and actual device exercise before realistic launch/device claims |
| M1c / finite thermal | A11–A15 plus solo gates; complete schema, epoch/domain, instrument and return/expiry checks for each admitted recipe | Weather/instrument and task-feasibility evidence for that recipe; learning gains need their own study |
| M2a / coupled feasibility fixture | T01–T08 and T10–T12 applicable synthetic cases; bounded solver/events, trial/accepted orientation, whole-pair rollback and minimum state/record envelope | A fixture establishes software evidence only; no physical installation or collision qualification follows |
| M2b / AI tug and player glider | Pair mechanics; airborne T13; T15/T16; C01 and applicable C03–C14; bounded recovery; full pair record/restore/replay and SG-13/17 slices | Installed aircraft/line and held-out pair-flight evidence for physical towing claims; wake omission remains explicit |
| M2c / manual tug and transfer | M2b plus C02/C04/C05/C11/C13/C14, both takeover paths and released AI glider fallback; full ownership/event replay | Actual radio/profile/platform and usable transition evidence for advertised support; no assumed training transfer |
| M3 / ground and richer lessons | T14, ground T08/T10, dual contact and aborts, applicable failures; accepted-event scoring/debrief; all airborne prerequisites | Installed ground/contact/line evidence and any independently claimed failure/break law; controlled study only for a learning-effect claim |
| M4 / selected release candidate | Applicable prior slices and required CI/export/backend/platform checks; native 1080p evidence, complete limitation text and source/package identities | SG-16 evidence for each advertised physical, instrument or learning claim; a narrower release cannot waive existing repository gates |

Engineering parameters may remain explicitly estimated/synthetic within a bounded experimental slice. Missing physical evidence keeps the corresponding physical claim open; it does not erase numerical, input, contact, observer, event, replay or release requirements. Solo physical qualification is independent of the tug/rope dossier. The full SG-16 record lists each claim as supported, unsupported or outside scope instead of demanding a learner study for every exercise package.

