# AI flight companions implementation plan

**Status: proposed; no runtime implementation authorized by this document.**
Inspection date: 2026-10-20. Baseline: `e1e8cd66`; working tree clean before this plan.
Owner: proposed Flight Companions track, prefix **AFC-00…32**. Register the track in
[docs/README.md](docs/README.md#tracks-plans-and-step-ids) before implementation.
Every step below is pending. Numeric targets are proposed engineering/gameplay gates,
not measured RC aircraft properties or claims of current performance.

## 1. Product outcome and scope

Let the player optionally share an RC field with independently piloted airplanes.
One companion may be taking off while others fly circuits, practice aerobatics,
make approved passes, wait for landing, or recover from a mistake. The aircraft must
fly through the existing flight dynamics and control surfaces. Their variety comes
from aircraft capabilities, routes, pilot decisions and control inputs.

Deliver a useful small population first, then qualify larger populations. Keep the
default **Off**. Preserve the current solo flight, radio setup, aircraft selection,
weather, camera and logging workflows. This feature does not close the project's
open physical-validation or target-hardware gates.

Initial support is the normal fixed-wing flight activity at Club field. Green
paradise gains airborne companions after its traffic layout is qualified; its
logical grass runway does not automatically qualify takeoffs or landings.
Helicopters, trucks, multirotors, multiplayer, AI flying the player's airplane,
combat and campaign economics are outside this plan. Natural Random is an explicit
later combination; Workshop trials and technical/golden routes remain opt-in only.

Reuse the bundled airplanes, scenery, audio, effects and free development tools.
No new aircraft model, voice pack, behavior-tree addon or paid service is required.
If an optional asset is later needed, first find a freely downloadable,
redistributable asset and retain its license and provenance.

### Player-facing settings

Add **Home → Flight companions** and **Pause → Flight companions**. Use the existing
screen stack, focus/navigation, theme and translation systems.

| Control | Defined behavior |
| --- | --- |
| Enabled | Off by default. Enabling validates the selected field, models, activities and count before committing. Invalid configuration leaves the running flight unchanged and explains the refusal. |
| Population | Integer target for active AI airplanes; excludes the player, parked scenery and wrecks. Show `airborne / active / requested`, with waiting and performance-limited counts separately. MVP: 1–3; eventual qualified range: 1–32. |
| Preset | **Relaxed:** 3 requested, circuits and runway operations, experienced pilots, incidents Off. **Club afternoon:** 8, mixed circuits/runway/passes, mixed pilots, Rare incidents. **Busy skies:** 16, all qualified activities, mixed pilots, Occasional incidents. **Airshow:** 24, experienced pilots, aerobatics/passes with runway recovery, Rare incidents. Custom up to 32; larger values only in development stress tests. Presets unlock only after their count/activity gates pass. |
| Aircraft | Checklist of catalog airplanes with positive integer selection weights 1–10, optional per-model maximum, and “same aircraft as player” shortcut. Resolve a concrete roster at launch using the traffic seed. Repeated models are allowed. Preserve catalog experimental labels. Exclude non-airplanes, preview/invalid data and unqualified AI profiles. |
| Activities | Independent enable switches and Off/Low/Normal/High weights mapped to 0/1/3/6: takeoff/landing cycles, circuits/general flight, aerobatics, low passes, flybys, overtaking. Weights influence opportunities, not promised concurrency. Circuits, holding, go-arounds and necessary recovery/landing remain available as safety transitions. |
| Pilot skill | Learner, Club, Experienced, or Mixed. Changes reaction delay, tracking precision, maneuver choices and decision consistency; never changes lift, thrust, servo limits, mass or collision rules. Mixed initially resolves 20/60/20 percent with a seeded draw. |
| Incidents | Off, Rare, Occasional, Lively; expected eligible *opportunities per entire fleet*: 0, 1 per 20, 1 per 8, or 1 per 3 simulation minutes. Add separate **Allow crash-prone mistakes**, default Off. These are opportunities, not guaranteed crashes. |
| Player interaction | **Yield to player** always governs AI intentions. **Aircraft contact:** Off in MVP, optional On after AFC-23 qualifies coupled contacts. Off means aircraft-to-aircraft contact is disabled; avoidance still operates and terrain/scenery contact still applies. Show this limitation plainly. |
| Traffic requests | Pause/menu actions **Request landing**, **Request takeoff**, **Clear the runway**, **Recall companions**, **Restart companions**, **Remove companions now**. Optional remappable actions use the existing input registry; do not claim unused keyboard keys without auditing bindings. |
| Presentation | Companion engine-volume slider; optional concise traffic notices and labels; label distance limit. No automatic camera switch or compulsory crash popup. |
| Performance | Auto within a qualified ceiling, or a fixed requested count with a visible supported ceiling. Show why an aircraft is waiting: runway, airspace, unsupported activity, weather, or performance. Do not call parked aircraft “active flights.” |
| Repeatability | Advanced seed entry, New seed and Repeat traffic. Repeat uses resolved models, profiles, weather identity and seed; repeating only a seed after source/data changes is not exact replay. |

**Apply semantics:** presentation edits apply immediately. Population decreases
retire aircraft after landing or a cleared departure exit; increases are admitted
gradually. Aircraft selections affect new sorties, without swapping an airborne
model. Disabling prevents new sorties and recalls existing aircraft; **Remove now**
removes them explicitly at a tick boundary, including their collision proxies.
Activity/skill/incident edits take effect at the next safe behavior boundary.
Emergency aborts are never delayed by settings changes. **Cancel** discards edits.
Home preferences and in-flight overrides are distinct; use **Save as default** for
the latter. Counts/settings appear in the launch summary before Fly.

An empty aircraft pool or all optional activity weights zero must have a defined
result: reject an empty pool; offer circuits-only when weights are all zero.
Do not silently replace a requested model. Ground aircraft already landing always
finish recovery even if landing cycles have just been disabled.

## 2. What the repository actually provides

Inspection used the codebase graph first. Its stored symbol ranges were stale for
several enlarged scripts, so current source was checked directly. This is a source
audit, not a benchmark or a claim that tests were run.

| Existing system and evidence | Reuse and required boundary work |
| --- | --- |
| [Engine settings](app/project.godot), [pin](app/get-godot.sh), [architecture](docs/STACK.md) | Godot 4.7.2-stable, GDScript, Compatibility renderer, 240 physics ticks/s and at most 12 catch-up ticks/render frame. Keep these pins and defaults. Godot rigid bodies do not solve flight. |
| [FlightSession](app/sim/flight_session.gd), [Simulation](app/sim/simulation.gd), [VehicleModel](app/sim/vehicle_model.gd) | Each session installs one model into its own kernel. `setup()`, `set_field()`, `set_collision_world()`, `setup_weather()`, `air_data()`, `trim_at()`, checkpoints and accepted-step signals are relevant seams. One kernel per aircraft is compatible with this contract; putting a fleet inside one aircraft model is not. |
| Session input/tick lifecycle | `FlightSession._physics_process()` currently samples input and performs some crash/prop-strike checks; `Simulation._physics_process()` advances its own tick. Merely calling `sim.step()` from an AI loop would omit some session behavior. Extract and verify an explicit session stepping seam first. |
| [Control mapping](app/input/commands.gd), session `_inputs()` / `flown_commands()` | Preserve trims, rates policy, actuator dynamics, propulsion, flaps and gear. AI supplies normalized pilot demands. Existing `set_flaps()` requires live-input conditions; `input_enabled = false` alone is not a sufficient AI equipment interface. |
| [Catalog](app/app_state/aircraft_catalog.gd), [aircraft contract](docs/AIRCRAFT_CONTRACT.md) | Eight airplane configurations across five visual families, plus the separate helicopter route. Use `airplane_flyable_ids()`, `data_for()`, `visual_family()` and capability checks. “Can fly” is not AI maneuver qualification. |
| [Main scene](app/main.tscn), [main controller](app/main.gd), [shell](app/app_root.gd) | Main is a small `Node3D` scene whose script builds the field, player session, camera and presentation. It is strongly single-player. Add one fleet child; do not instantiate a second Main per companion. |
| [Aircraft builder](app/render/airplane.gd), [frames](app/render/frames.gd) | Reuse `build()`, `datum()`, `apply_controls()`, `apply_flaps()` and CG-aware root conversion. Main already interpolates kernel states. Preserve `airplane`, `propeller`, and hinge names inside each instance. |
| [Parked fleet](app/scenery/fleet.gd) | Builds merged static snapshots through the real aircraft builder. Useful precedent for low-detail presentation; parked meshes have no flight AI and are not live companions. Respect its resource lifetime constraints. |
| [Takeoff pilot](app/scenery/takeoff_pilot.gd), [runway scenario](app/scenery/runway_scenario.gd) | A useful Stik fixture, with estimated fixed rotation speed and gains. It is not a fleet-ready controller. Keep the fixture's behavior stable while developing a separate AI controller. |
| [Landing pilot](app/sim/landing_maneuver.gd), [circuit pilot](research/landing/e3c2a/circuit_pilot.gd), [driver](research/landing/e3c2a/circuit_driver.gd) | Research for calm-air, wash-off Stik, including trim-relative commands and continuous circuit measurements. Reuse measurement techniques and lessons; production profiles must qualify the current accepted propulsion/wake/data configuration. |
| [Field guide](docs/LANDSCAPES.md), [Club data](app/data/fields/default.json), [landscape registry](app/landscapes/catalog.gd) | Field v1 defines surfaces, pilot position and objects, but no traffic slots/taxi graph. Club's runway is an estimated 100 × 12 m east–west strip at north 15 m. Derive geometry from loaded data; never embed these coordinates in controllers. |
| [Environment](app/sim/environment.gd), [scenery collision](app/sim/scenery_collision.gd) | Read-only physical environment queries and static obstacle inventory are reusable. Sessions own weather/turbulence state and scenery-damage masks. A coherent fleet clock and shared damage publication are new work. |
| [Crash director](app/render/crash/director.gd), [crash guide](docs/CRASH-DAMAGE-PLAN.md) | Impact snapshots, severity estimates, bounded wreck/effects/audio exist. `configure(scene, …)` accesses Main's private fields. Introduce an explicit presentation context rather than making AI nodes impersonate Main. No established coupled aircraft-to-aircraft contact path was identified. |
| [Flight audio](app/audio/flight_audio.gd) | Couples one aircraft to the field soundscape and player listener. Split reusable engine-source presentation from the one-per-field ambience/listener. Duplicating it for every companion would duplicate the field audio. |
| [Preferences](app/app_state/preferences.gd), [Home](app/ui/home.gd), [Pause](app/ui/pause_menu.gd) | Versioned preferences, future-schema protection, focus/navigation and session holds exist. AppRoot direct launches deliberately ignore Home preferences. Preserve that distinction. |
| [Failure system](app/failures/), [logging](docs/FLIGHT-LOGGING.md), [benchmarks](app/tests/bench_physics.gd) | Reuse supported per-session failures, read-only `.orfl` observations, exact/candidate comparisons and component timing. Current logs are not automatically a full fleet replay; legacy benchmark best-of averages are not fleet p95 latency evidence. |

The [Roadmap](ROADMAP.md) keeps Gate P, physical calibration and pilot validation
open. The 500 microsecond player-physics target must not be multiplied into a
claim that 32 airplanes fit a frame.

## 3. Architecture and explicit contracts

### Ownership and proposed file map

All paths in this table are **proposed**, unless marked existing. Create only the
files needed by the current phase; keep unparsed experiments outside `app/`.

| Path | Responsibility |
| --- | --- |
| `app/ai/companions/companions.tscn`, `companion_manager.gd` | One `Node` fleet root under Main. Roster, admission, pause/reset, event routing, lifecycle and bounded service ownership. |
| `app/ai/companions/companion_aircraft.tscn`, `companion_agent.gd` | One `Node3D` presentation/container per active AI; owns one FlightSession, pilot state and aircraft visual. No camera, input device or world environment. |
| `app/ai/companions/fleet_clock.gd` | Main-thread fixed-tick orchestration and common traffic clock. Calls the verified session interface; no aerodynamic laws. |
| `app/ai/companions/config.gd`, `profile_loader.gd` | Strict configuration and capability/profile validation; immutable resolved launch records. |
| `app/ai/companions/pilot.gd`, `guidance.gd`, `controller.gd` | Hierarchical state machine, path/energy targets and bounded pilot commands. Float64 data only. |
| `app/ai/companions/airspace.gd`, `runway_coordinator.gd`, `traffic_index.gd`, `avoidance.gd` | Field volumes/lanes, reservations, predictive spatial queries and feasible avoidance. |
| `app/ai/companions/activity_scheduler.gd`, `maneuvers.gd`, `incident_scheduler.gd` | Concurrent activity selection, qualified maneuver state machines and seeded incident opportunities. |
| `app/ai/companions/traffic_contacts.gd`, `world_state.gd` | Moving-aircraft contact adapter and shared committed obstacle/wreck state, with physics/CR owners. |
| `app/ai/companions/fleet_record.gd` | Versioned fleet checkpoint/event/input journal, reusing existing per-aircraft logging. |
| `app/render/companions/aircraft_view.gd`, `presentation_budget.gd`, `debug_overlay.gd` | Model binding, interpolation, visual quality, diagnostic lanes/intents. Debug geometry has no physics authority. |
| `app/audio/companion_audio.gd` | Voice allocator for aircraft engines/effects; reads snapshots, uses the existing listener. |
| `app/ui/companions_dialog.gd`, `companion_status.gd` | Programmatically built controls/status, matching existing UI style; no extra UI scene framework. |
| `app/data/ai/companions/profiles/<catalog-id>.json` | Pilot/controller qualification and activity envelopes tied to an exact aircraft configuration. |
| `app/data/ai/companions/fields/<landscape-id>.json` | Traffic geometry and limits tied to field/collision identities. |
| `app/tests/test_companions_*.gd`, `bench_companions.gd`, `capture_companions.gd` | Deterministic checks, native performance workloads and visual cases. |
| `research/ai-companions/`, `docs/research/ai-companions/AFC-xx/` | Offline qualification tools and accepted evidence, respectively. Scratch logs remain in `tmp/` or `output/`. |
| Existing `app/main.gd`, `app/app_root.gd`, `app/sim/flight_session.gd` | Small integration/session changes co-owned by physics and UI. Kernel changes require SF owner review and generic contracts. |
| Existing aircraft generators, crash/audio/UI/i18n/export files | Their owners retain authority. Never hand-edit generated geometry or physical aircraft data. |

No companion Autoload: the fleet dies with its flight. Share immutable meshes,
textures and validated definitions where safe; each session, controller, RNG,
material mutation, damage state and actuator history remains independently owned.
An instance ID is monotonic within a fleet; a new sortie also receives a generation
ID, so callbacks cannot affect a recycled slot.

### Fixed-step scheduling

**Decision:** keep every active flying/taxiing aircraft on the existing 240 Hz,
float64 kernel. Slow thinking and rendering independently. Do not use
`CharacterBody3D`, `RigidBody3D`, a spline transform or reduced integration rate as
the normal flight solver. Parked scenery/finished sorties need no flight solver.

Introduce proposed session methods `prepare_external_tick(pilot_command)`,
`finish_external_tick()` and an explicit external-driver mode. The names are new
API proposals, not present methods. Refactor existing input/contact work into
these seams without changing ordering on the solo path. Disable automatic physics
callbacks when externally driven; do not use `sim.paused = true` as a substitute
for an external driver because session guards use pause state.

When companions are enabled, the fleet clock coordinates the player session and
all AI sessions:

1. At global tick `k`, apply queued lifecycle/config changes. Snapshot all accepted
   poses, velocities, contact states and intents. Include the player as a traffic
   participant, never as an AI-controlled aircraft.
2. Update due planning jobs using this same snapshot, in stable ID order. Update
   reservation grants and avoidance constraints. No agent observes another's
   partially advanced tick.
3. Sample player input once through the existing path. Produce bounded AI demands;
   update session equipment demands through the new non-device command interface.
   Preserve model `pre_tick`, actuator, fuel, failure and event processing.
4. Step each active Simulation once and run the session completion/contact hooks.
   Buffer fleet-visible contact/world mutations until every participant is done.
5. Resolve accepted fleet events in deterministic order, then publish the next
   traffic snapshot, logs and presentation data. Render-only callbacks cannot
   change the accepted simulation.

Start single-threaded. The disabled path retains its existing callbacks. A
one-aircraft external-driver fixture must match the original session's complete
accepted state and contact behavior before Main adopts it.

| Work | Initial cadence and bound |
| --- | --- |
| Physics, equipment/failure state and urgent safety guards | 240 Hz per active aircraft. Emergency runway occupancy invalidation also checked each tick. |
| Inner pilot attitude/rate control | 60 Hz (every 4 ticks), held demands between updates; qualify higher rate only when a named maneuver needs it. |
| Path guidance and predictive avoidance | 20 Hz (every 12 ticks); near-conflict urgent guard every tick. |
| Runway requests and ordinary planning | 10 Hz (24 ticks); grants are invalidated immediately by occupancy/crash events. |
| Activity selection | 2 Hz (120 ticks), plus completion/abort events; stagger by stable ID. |
| Presentation | Every rendered frame from two accepted states; optional expensive detail updates at 30/15 Hz. |
| UI summaries | 5 Hz, event-driven warnings; no per-aircraft labels formatted at 240 Hz. |

Use integer tick deadlines. Record controller integrators, held commands,
observation delay buffers, phase, grants, RNG states and next-update ticks.
New sorties use an explicit global-time origin for weather/traffic while retaining
their own session tick/age. This requires an environment-time adapter and checkpoint
identity; spawning a new aircraft must not restart the day's gust cycle. Mean wind
and atmosphere are common; existing per-aircraft turbulence remains separately
seeded and is not claimed to be a spatially correlated wake field.

**Pause/fault policy:** menu, focus loss, calibration and player failsafe freeze the
whole fleet clock and incident timers. A companion crash stops only that aircraft.
A player terminal crash freezes traffic while the current player crash workflow
runs. Restart flight resets player and companions; Restart companions resets only
the fleet at a paused, checked boundary. An AI solver fault is logged as a fault,
quarantines that slot and releases its future grants; it is not converted into a
funny crash. Player solver faults retain the existing stop/recovery behavior.

### Validated configuration and profiles

Define versioned `openrc-companions v1`, `openrc-ai-aircraft v1`,
`openrc-ai-field v1` and `openrc-fleet-record v1` formats. These are AI-side schemas,
not an unreviewed extension of `openrc-aircraft v2`.

The resolved companion configuration contains: enabled state, requested/effective
ceiling, concrete roster, catalog/data/battery/fuel identities, activity weights,
skill distribution, incident policy, contact policy, field profile, weather identity,
seed, profile hashes and schema/controller versions. Reject unknown required
versions, nonfinite values, negative weights, duplicate slot IDs, out-of-range
counts and unsupported combinations. Preserve future preference files read-only.

Aircraft AI profiles must include:

- Catalog/configuration and source hashes, visual family, validation evidence,
  supported start/ground modes, and an explicit per-activity allowlist.
- Demonstrated stall/approach/cruise/entry-speed ranges and whether each uses TAS,
  EAS or ground speed; mass/density/fuel/battery coverage; bank/rate/load bounds,
  recovery altitude loss, turn radius, climb capability and propulsion lag.
- Controller gains with units, trim operating points, anti-windup limits, normal
  tracking tolerances, runway distance margins and crosswind/gust limits.
- Gear/flap/brake/fuel/propulsion capabilities read from accepted aircraft data,
  plus AI restrictions. Absence means unavailable, never an inferred feature.
- Bounds/proxies and reference datum for avoidance, tied to the generated model.
  Keep measured, derived and estimated values/provenance distinct. Use quantity
  metadata `{value, unit, kind, source}` for dimensional authored values.

The field profile identifies runway ends, preferred calm-wind direction, circuit
side, pilot/pit/spectator exclusion volumes, holding paths, departure/arrival gates,
taxi edges, staging spots, aerobatic boxes, pass corridors, incident areas and exit
gates. Store NED coordinates; derive runway frame and ground heights through the
validated field/environment. Validate route tubes against static obstacles and
ground, including full wingspan and turn/recovery margins. An unqualified field
offers no AI operation; do not guess a traffic layout from its name.

### Realistic control and aircraft selection

Use a hierarchical state machine with bounded transitions:
`staged → taxi/line_up → takeoff_roll → climb → join → activity → return →
approach → flare → rollout → vacate → parked → retire`.
Airborne MVP starts at `join`. `hold`, `go_around`, `recover`, `emergency_land`,
`crashed` and `faulted` are explicit branches with timeouts and exit criteria.

Guidance outputs course/altitude/airspeed or a maneuver attitude/rate target.
The inner controller maps these to trim-relative roll/pitch/yaw and absolute
throttle, plus supported equipment commands. Define trim addition once at the
session boundary; test against double trim/expo and wrong-axis sign. Use
air-relative velocity for stall/energy control, ground velocity for route progress,
and actual lowest-point clearance for flare/terrain protection.

Normal flight uses bank-limited coordinated turns, throttle/energy management,
rate damping and saturation-aware integrators. Never force a climb when the
aircraft lacks energy: lower the pitch target, widen the turn or abort. Recover
from stall with an appropriate unloading/power sequence instead of commanding
more elevator to regain altitude. Quaternions/rotations in pilot calculations use
the repository's float64 math, not Godot's render math.

Initial design margins to qualify: approach at least 1.3 times demonstrated
stall speed for the current configuration; normal turns at most 30 degrees bank;
stall reserve adjusted for bank/load; maneuver recovery height at least 1.5 times
measured worst recovery loss plus obstacle margin. These are starting policies,
not universal aircraft laws. A profile without successful evidence remains
ineligible; do not invent a stall speed from the display name.

| Aircraft/configuration | Intended qualification order and restrictions |
| --- | --- |
| `jensen-das-ugly-stik-60` | MVP calm circuits; then runway operations and basic loop/roll. Existing rudder/sideslip limitations remain visible; AI must not “repair” coefficients. |
| `turbo-lumber-evolution` | Slow circuits and pass variety after independent controller/finite-pack testing. Current catalog says fixed wheels, flaps up, assists off; do not script working flaps, SAFE/AS3X or hover/3D flight. |
| `gp-extra-300s-60` | Circuits/runway first, then qualified loop/roll/inverted segments. Fuel-feed and recovery limits constrain aerobatics; no automatic unlimited inverted flight. |
| `p51d-mustang-120` | Faster wider circuits, gear/flap sequencing only where simulated, conservative approach and overshoot margins. No generic trainer gains or default hovering/stall tricks. |
| `sebart-avanti-s-a200-p100rx` (Ventage Jet) | Later admission: turbine spool, braking/runway distance, larger turns and closure speeds must qualify. Airborne-only if the selected field cannot support ground operations. |
| `stik-glow-61fx-2t`, `stik-glow-55ax-2t`, `stik-glow-fs64v-4t` | Share visuals, not qualification receipts. Test each powertrain, finite fuel, trim and throttle response. |

Skill initially uses Learner/Club/Experienced reaction delays of 0.35/0.20/0.10 s
and bounded target-tracking variability, all estimates to validate. Delays affect
pilot observations/decisions; they do not delay the protective traffic supervisor.
No unbounded random stick noise. Pilot-specific quirks are smooth, low-frequency,
seeded biases with explicit amplitude/duration bounds.

## 4. Shared airspace, runway and avoidance

### Airspace allocation and simultaneous activities

Use field-defined route tubes and three-dimensional volumes rather than a ground
navigation mesh for flying. Allocate a circuit/holding lane and altitude band
before admission. Keep arrival, departure, aerobatic and pass volumes distinct
where the field permits it. A busy preset schedules multiple activities across
different agents; it does not make every airplane perform a synchronized cycle.

Start with at most one aerobatic aircraft per box, one pass per corridor and one
runway operation occupying its protected volume. Increase box count only with
nonoverlapping route/recovery volumes. For sufficient eligible aircraft, the
scheduler should maintain circuit traffic, a queued runway movement and a
separate maneuver activity concurrently. Log ineligibility and starvation reasons.

Select activities by weights, capability, available airspace, energy and cooldown.
Initial minimum activity duration 20 s, repeat cooldown 60 s; recovery/landing may
preempt immediately. A feasible queued activity must receive an opportunity within
120 s in the controlled test fixture; indefinite player runway occupation is an
explicit exception, displayed as a block.

### Runway coordination

Implement a reservation state machine:
`free → reserved → occupied → clearing → free`, plus `blocked`.
A grant includes owner, operation, direction, entry/deadline tick, protected
approach/departure volume and cancellation reason. Reservations expire; actual
occupancy never expires merely because a timer elapsed.

- Determine direction from wind projected onto runway heading. Calm threshold:
  1 m/s along-runway component; otherwise use the into-wind direction. Require
  10 s of consistent change before considering reversal; keep direction locked
  while occupied or an arrival is committed. Revalidate gust/crosswind envelopes.
- Priority: real occupancy and immediate emergencies, player request/observed
  approach, committed AI landing, ordinary landings, takeoffs, optional passes.
  Stable request-time/ID ordering and aging prevent ordinary AI starvation.
- The player is never physically constrained. Detect player runway presence and
  approach intent even without a request. Cancel AI entry, hold short or go around.
  A player request is advisory priority, not a guarantee of an empty strip.
- Release only after the entire swept aircraft footprint clears the runway and
  protected departure/arrival path. Include gear and wings, not CG alone.
- Touch-and-go, runway low pass and opposite-direction requests consume a runway
  grant. Do not allow a takeoff to overlap a “visual-only” runway pass.
- Before roll, verify acceleration/stopping distance, wind, equipment and energy.
  Abort below the profile's committed-roll gate when stopping distance fits.
  Beyond that gate, use the qualified climb/escape policy; do not demand an
  impossible stop.
- At the final-approach gate, require runway clearance, valid gear/flaps, speed,
  descent and alignment. Otherwise go around early, accounting for propulsion lag.
  A late incursion uses the qualified best-effort escape; collision avoidance
  cannot guarantee recovery from every player action.
- A runway wreck blocks new movements immediately. Disable optional low passes
  until cleared. **Clear runway** makes aircraft vacate/hold; removal of an existing
  wreck is an explicit cleanup action after its occupancy is removed atomically.

Taxi initially uses a small authored directed graph with hold-short nodes, edge
reservations and measured footprint clearance. Limit speed by the profile,
initially 2 m/s maximum; tighter turns require slower speed. Ground contact,
tailwheel/nosewheel behavior and brakes remain physical. If a model cannot turn
within an edge, do not rotate it in place: reject that route and use an airborne
sortie until a valid ground route is authored.

### Predictive collision avoidance

Use three layers: strategic lane/volume separation; tactical trajectory prediction;
and an urgent envelope/terrain escape guard.

1. Index traffic with a float64 spatial hash. Start at 50 m cells, but query every
   cell touched by the swept bounds over the horizon, expanded by uncertainty.
   Fast jets must not be restricted to adjacent cells. Static obstacles use the
   existing collision inventory and a separate conservative flight-volume query.
2. Predict closest approach over 6 s from ground-relative velocity and intent.
   Refine candidates with sampled feasible turns/climbs and reaction/propulsion
   delays. Zero relative speed, crossing, head-on and converging turns are explicit
   cases. Prediction is not an exact guarantee under unknown player inputs.
3. Initial normal desired center separation:
   `max(15 m, 3 × larger wingspan, closure_speed × combined_reaction_time)`.
   For player encounters use at least 30 m plus the same predictive margin.
   Expand by hull size, current turn uncertainty and latency. Ground/taxi uses
   footprint clearance, not the airborne separation formula.
4. Choose a maneuver within stall, bank/load, climb, terrain and exclusion limits.
   Prefer an early lateral offset/extended leg, then an assigned altitude change;
   don't send both aircraft through the same “climb away” solution.
5. Deterministic yielding: established/landing traffic has priority; overtaker
   yields; equal-priority pairs use stable IDs and a shared passing convention.
   Head-on avoidance turns to the designated right side only when clear.
   Maintain a 2 s maneuver latch and release hysteresis to prevent oscillation.
6. If no feasible path exists, stop issuing new takeoffs/maneuvers and take the
   safest reachable escape/recovery. Never teleport, stop an airborne airplane
   midair or secretly alter player controls.

An overtake requires positive speed advantage, an available outside lane, desired
separation throughout entry/pass/rejoin, and no runway/final conflict. Abort by
extending the leg if the slower airplane turns unexpectedly. No chase/combat
behavior, deliberate collision or passing through a stalled aircraft.

Do not substitute `NavigationAgent3D` crowd avoidance for aircraft dynamics.
Such methods do not supply this project's turn/energy/ground-contact guarantees.
Aircraft wake interaction is deferred: existing self-wake laws are not a shared
inter-aircraft wake model, and visual smoke must never produce aerodynamic forces.

## 5. Maneuvers, mistakes and believable incidents

### Activity definitions

| Behavior | Entry, execution and exit contract |
| --- | --- |
| Normal flight | Continuous circuit, large figure-eight or gentle cruising arc within reserved field volumes. Track airspeed/energy, vary route duration and altitude within profile bounds. Return for fuel/battery reserve. |
| Takeoff and landing | Complete physical ground roll, liftoff, climb, join, approach, flare, rollout and vacating. No teleport between phases. Permit go-arounds and delayed takeoff. |
| Flyby | A planned visible pass with entry/exit turns outside the pilot/pit exclusion zone; normally at least 15 m AGL, raised by aircraft/terrain margins. |
| Low pass | Qualified profile, stabilized straight entry, reserved corridor, initial minimum 5 m AGL plus terrain/hull/recovery constraints. No low pass over pilots/pits; late instability aborts before descending. This is a game starting limit, not real-world flying guidance. |
| Aerobatics | First one axial roll and one positive loop; then linked roll/loop, Cuban eight and limited inverted flight where qualified. Each maneuver has speed, altitude, fuel-feed, load/rate, box and recovery gates. Snap rolls/spins/knife-edge/3D hover stay disabled without separate evidence. |
| Overtake | Route-level pass on a reserved outside lane, using actual available speed and turn radius. Never force a slow trainer to match a jet. |
| Emergency recovery | Loss of climb margin, unstable approach, low energy or supported power loss triggers recovery/dead-stick planning. Intended touchdown surface and actual impact are logged separately. |

For every maneuver store entry/exit state bands, phase timeouts, progress measure,
normal control bounds, abort conditions and recovery path. The controller flies
the maneuver; animation only follows the resulting states. Completion means the
flight path and recovery satisfy the envelope, not merely that a timer expired.

### Incident scheduler

Separate ordinary tracking variation from discrete pilot mistakes and supported
hardware failures. Incidents Off disables scheduled error/failure episodes; it
does not make a player collision or a software/controller defect impossible.
Those outcomes must still be reported honestly.

Use independent seeded RNG streams for roster, activity, pilot variation and
incidents. Schedule exponential waiting times from the selected fleet-wide rate,
quantized to simulation ticks. Do not make probability depend on render frames or
multiply it by aircraft count. After an opportunity, recheck eligibility; cancel
and log ineligible attempts without creating a burst of postponed accidents.

Initial bounds: at most one scheduled incident active, at least 120 s between
fleet incidents and 180 s between incidents on one pilot. No incidents during the
first 60 s, inside the player protective volume, or when recovery space is already
occupied. “Allow crash-prone mistakes” permits at most 25% of eligible opportunities
to choose a crash-prone episode; physics and recovery determine the actual result.
This percentage and the UI wording require user testing.

Mistakes are finite command/decision episodes: late throttle reduction, delayed
flare, excessive but bounded bank, modest overshoot or premature maneuver entry.
They never directly set an impact flag, remove lift, move a model into the ground,
or bypass servo/engine response. A safety supervisor still protects the player and
people/pit exclusion zones. Crash-prone episodes may consume recovery margin only
inside a cleared incident area; abort injection if that area becomes unsafe.

Supported hardware failures use the existing per-session failure APIs and
availability rules, with an AI-specific seed/config and UI label. Do not share
the player's failure draw or assume all aircraft support engine/servo failures.
Energy depletion is a physical condition, not a random scripted malfunction.

### Unusual and funny scenario library

| Scenario | Physical mechanism and eligibility | Recovery/limit |
| --- | --- | --- |
| The endless landing | A learner floats past its touchdown target, goes around, and produces a sheepish traffic notice. | Actual approach/flare inputs; maximum two attempts before an extended circuit or alternate recovery. Never land beyond the usable strip just to finish the joke. |
| The patient jet | A fast aircraft extends its downwind while a slow trainer enjoys a long circuit. | Different real speeds/turn radii; the jet waits in its own lane, then makes a properly spaced pass. No impossible slow flight. |
| Overenthusiastic victory roll | An aerobatic pilot starts a roll with a small entry-energy error, exits crooked and spends another circuit straightening up. | High box and recoverable error bounds first; no low-altitude roll near the player. |
| The balloon-and-bounce | A slightly high flare produces a balloon or a small physical wheel bounce. | Gear/contact law creates the bounce; add power/go around when height or energy falls outside the profile. |
| The surprise photo visitor | A companion flyby briefly shares the player's camera composition. | Fly through an approved world-space corridor; no camera-relative teleport, chasing the view or obscuring the player deliberately. |
| The wrong invitation | Two pilots request the same show box, then one politely extends its circuit. | Reservation conflict produces the timing; never grant the box to both. |
| The ambitious climb | A heavy/low-energy aircraft starts a climb, runs out of useful margin and rolls out early into level flight. | Commands stay within the profile; preserve spool/battery/fuel effects. Do not assert the aircraft can hover. |
| The grass arrival | A supported power loss forces a dead-stick arrival on a cleared rough-grass patch; a rough touchdown may nose over. | Landing path and ground contact determine outcome; no spectators, traffic or player in the footprint. |
| One roll too many | With crash-prone incidents enabled, a qualified aerobat begins a recovery late in the remote box and may strike empty terrain. | Bounded delayed recovery; no guaranteed crash, no state injection, and no reroll until a crash happens. |
| The queue that never leaves | A pilot notices a bad takeoff setup, idles, vacates and lets the next aircraft go. | Equipment/energy checks and physical taxiing; bounded timeout prevents a permanently blocked runway. |

Humor comes from timing and recognizable pilot behavior. It must still look like
RC flight from the pilot station. Use optional short text notices before adding
any voice work. Aircraft, scenery and people are not targets.

### Crash/contact handling

Companion ground and obstacle crashes use accepted session contacts and impact
snapshots. A terminal companion incident transitions once to `crashed`, releases
future reservations, blocks occupied space, stops its propulsion audio and hands a
detached snapshot to presentation. Nonterminal prop strikes retain existing
continued-flight behavior and may trigger a dead-stick return.

Refactor the existing director to consume a typed context containing aircraft
visual/bindings, session snapshots, field/lighting/water references and audio
policy. Keep camera steering, player accident reports and `user://last_accident.json`
outside that reusable context. Companion accidents never overwrite the player's
report, trigger player auto-restart, charge a wallet, seize focus or change camera.

Moving aircraft contact is a separate AFC-23 gate. Use conservative swept broad
phase and qualified continuous hull-proxy tests in float64, including fast
crossings and rotation. Sparse existing ground crash points alone are not proof
of complete wing-to-wing coverage. Obtain proxies through the aircraft authoring
pipeline and preserve their datum/provenance.

The first contact implementation is a **terminal contact model**, not a deformable
two-body solver: locate the first pair impact within the common tick, generate
consistent event ID/time and opposing normals for both aircraft, and end both
flight simulations through session adapters. Preserve incoming state/energy for
aftermath. Do not invent post-impact flying velocities or claim elastic/momentum
accuracy from VFX. Any later survivable midair collision needs its own validated
impulse/structural model under physics/CR ownership.

Before publishing pair effects, stage and validate both participants' transitions.
Event ordering is earliest crossing time, then canonical pair IDs; a terminal
aircraft cannot receive another terminal event in that tick. Ground/scenery
contacts that precede a pair event win. The joint commit/rollback contract must
retain session modes, energy, contact/damage state and traffic state; raw body-array
restore is insufficient. If this seam cannot preserve existing kernel transaction
semantics, keep aircraft contact Off and leave AFC-23 open.

Debris remains presentation-only initially. Keep a conservative settled wreck
occupancy proxy for runway/traffic avoidance rather than hundreds of physical
debris bodies. Initial global caps: 2 detailed active wreck effects, 8 retained
wreck visuals/proxies, 128 cosmetic fragments and 4 impact voices. Extra crashes
get a simple bounded wreck marker. Never drop physical occupancy because an effect
budget is exhausted. Retire the oldest offscreen cleared wreck after 120 s;
runway obstruction requires explicit cleanup or a visible completed recovery.
Delayed respawn is a new sortie after at least 30 s and an admission check.

Shared scenery damage requires one world authority. Retain the immutable collision
inventory; merge accepted damage by obstacle ID after the fleet tick and publish
one mask to all sessions. Do not let one aircraft see a broken fence while another
still collides with its intact proxy. Rendering mutations happen after publication.

## 6. Performance, lifecycle and replay

### Budgets and admission

The player keeps full physics and control responsiveness. Count limits follow
measured total cost, model mix and airspace capacity, not a preset's marketing name.
At 60 frames/s, 240 Hz physics requires roughly four fleet ticks per frame.

Proposed initial target-host acceptance budgets:

| Measurement | Gate |
| --- | --- |
| Player physics | Preserve the existing 500 microsecond target and report actual per-regime p50/p95; a baseline miss remains an open baseline issue. |
| Complete fleet physics + AI + traffic + contact tick | p95 at most 2.0 ms; p99 at most 3.0 ms on the named target. At four ticks, 2.0 ms consumes about 8 ms of a 16.67 ms frame; report complete frame timing too. |
| Rendered workload at 1280×720/default Compatibility settings | p95 at most 16.67 ms, p99 at most 25 ms; record CPU/GPU attribution and simulation-time/wall-time ratio. A 30 fps fallback is separately labeled and measured, never called a 60 fps pass. |
| Simulation progress | After warmup, simulation/wall ratio within 0.99–1.01 over a 120 s foreground workload; no sustained catch-up saturation. |
| Companion toggle/retirement soak | After 50 enable/disable cycles and 20 min flight, no growing live-session/node/resource counts; stabilized memory drift at most 5% of post-warmup usage, with platform allocation noise explained. |
| Off path | No instantiated companion sessions, planners or voices. Same player trace bytes for the same accepted tape; performance change within baseline repeat-run noise. |

AFC-00 records the actual baseline and target CPU/GPU/OS/build before these gates
are used. If the baseline alone misses a frame gate, retain the measurement, fix or
coordinate the underlying issue, and do not advertise a higher-count pass.

Benchmark 0, 1, 2, 4, 8, 16, 24 and 32 companions, plus 48 only as overload stress.
Cover repeated Stiks, heterogeneous aircraft, jet closure, runway queues, low
altitude, stalled/local-aero regimes, finite-energy engines and simultaneous crash
effects. Count includes all active physics sessions, even offscreen.

Admission uses the lower of spatial capacity and qualified model-mix cost ceiling.
During overload, stop new admission, reduce cosmetic detail/audio, then retire
eligible distant sorties normally. Never silently lower physics Hz, skip collision
checks or teleport nearby aircraft. Report reduced active count. A tick-level
fixed update schedule remains unchanged by timing; wall-time-driven admission
decisions are journaled as external events. Deterministic tests use fixed limits.

### Optimization order

1. Measure exclusive buckets: player and each AI solver, controller, route queries,
   avoidance, static/dynamic contacts, mesh/pose/shadow, audio, effects and UI.
   Avoid double-counting callback work already in session timing.
2. Cache immutable validated profiles, bounds and shared mesh resources at flight
   scope. Reuse packed buffers and spatial-hash buckets; do no profile file reads,
   model construction or unbounded allocation in tick callbacks.
3. Stagger planning, not physics; narrow broad phase conservatively. Maintain an
   exhaustive pairwise oracle for correctness. Worst-case dense cells can still
   approach O(N²); measure them and cap admissions.
4. Render near aircraft with full hinges/gear/propeller state. For distant aircraft,
   use existing free source geometry to generate cheaper meshes through the asset
   pipelines, preserving silhouette and color. Initial LOD gates use projected
   wingspan: above 80 px full detail, 20–80 px reduced detail, below 20 px simplest
   qualified geometry; use 20% hysteresis. Pilot recognition tests may raise them.
5. Reduce shadow/light/particle detail and surface-update cadence with distance.
   Physics, control, contacts and proximity prediction remain active offscreen.
   Never derive simulation state from a rendered transform.
6. Start with individual shared-mesh instances. Probe MultiMesh only for identical
   distant visual families in spatial batches, after draw-call attribution.
   It culls the whole batch rather than each instance, so a world-sized batch is a
   poor default. Animated control surfaces and near crash binding stay independent.
   [Godot MultiMesh documentation](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)
   currently carries a 4.7 update caveat; validate on the pinned engine.
7. Allocate at most 8 AI engine voices initially, ranked by audibility/proximity
   with crossfades and hysteresis; always preserve the player's source/listener.
   Reuse propulsion-specific sound generation, attenuation and supported delay.
   Maintain one field ambience and bounded crash/smoke effects.
8. Only after profiling, probe `WorkerThreadPool` for pure planning over immutable
   snapshots with per-agent output buffers, fixed membership and deterministic
   main-thread reduction. Never call active scene-tree, mesh or shared mutable
   session code on workers. Reject a threaded candidate that is slower or changes
   decisions. [Godot thread-safety guidance](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html).
9. Native evaluator work is conditional on the existing
   [SF/Gate P policy](docs/STACK.md#boundaries-and-data-flow), with reference parity,
   ABI/toolchain receipts and owner decision. This plan does not authorize a
   wholesale native solver or engine/renderer migration.

Prewarm known resources at launch with progress feedback. Activate at most one new
sortie per 0.5 s after startup; geometry/resource preparation happens outside the
fixed tick and is measured for frame spikes. No repeated trim solving during
flight. Pool only objects whose reset contracts are proven; freeing a complete
session is preferable to leaking pilot/engine/failure state into another aircraft.

### Repeatability and evidence

Keep existing `.orfl` files per selected aircraft for physics analysis. Add a
versioned fleet record containing global tick/time origins, resolved roster and
identities, all session checkpoints, pilot buffers/integrators, reservations,
activity/incident RNG state, shared damage/wreck occupancy, external player input
and admission/settings events. Bound recording memory and surface disk/write errors.
Do not change the read-only recorder into a planner.

Two verification modes are required:

- **Accepted-input replay:** replay recorded per-tick aircraft inputs/equipment,
  external contacts and world changes without recomputing the AI. This isolates
  physics/session preservation.
- **Decision replay:** restore the full fleet checkpoint and rerun planning from
  the same inputs and seeds; compare commands, grants, transitions and accepted
  states. This checks the AI and orchestration.

Current standalone player `.orfl` replay cannot establish fleet equivalence when
another aircraft changes contact/world state. Link it to its fleet manifest;
refuse an “exact fleet replay” claim without that context. Reject mismatched
solver, profile, field, timestep or schema identities. Check `complete` and
`solver_changed`; recovered prefixes and candidate runs stay labeled accordingly.
Cross-platform byte identity is not presumed.

For tuning, preserve one complete baseline log, verify exact replay, then compare
one candidate using the same accepted input tape where applicable. A live feedback
controller may hide a changed force model by changing its controls, so keep both
open-loop physics and closed-loop pilot evidence. Use existing CSV tools and free
plotting tools; never rerecord golden flights merely to make an AI test pass.

## 7. Phased execution

Steps are ordered within each phase unless explicitly independent. Each row should
be a small, reviewable change with its own proof. No phase gate is closed solely by
compilation or a screenshot.

### Phase 0 — Feasibility and preserved session seam

**Outcome:** establish a safe implementation boundary and realistic count ceiling
before adding product behavior. Dependencies: physics/SF, UI, aircraft, LU/CR/AUD
owners; existing solo replay and baseline tooling. No new user-visible feature.

| ID | Concrete work | Proof / status |
| --- | --- | --- |
| AFC-00 | Register prefix/paths and this plan in docs/README; record source/engine/data identities, target hardware and baseline costs. Audit existing tick ordering, global/static caches, weather clocks, resource mutation, contacts and input callbacks. Build an offline 1/2/4-session feasibility harness in `research/ai-companions/`. | Pending: cost table, complete traces and isolation report; distinguish target-host measurements from headless throughput. |
| AFC-01 | Extract the explicit FlightSession external-driver and non-device command seams described in §3. Keep legacy default scheduling and input policy. Prove gear/flaps/brakes/failures still run with AI input disabled. | Pending: `test_companions_session.gd`; original versus external-driver state/aux/continuous/modes/loads/contact equality for 10,000 ticks per eligible initial configuration. |
| AFC-02 | Add config/profile/field validators and offline profile qualification harness. Establish Stik circuit envelope and derive a Club traffic layout, exclusions and airborne admission slots. Implement fleet-record skeleton and bounded diagnostics outside product UI. | Pending: malformed/unsupported data refusal, current-source profile receipt, route-clearance proof and deterministic two-session fixture. |

**Technical decision:** keep sessions and kernel laws intact; external orchestration
is the seam. Do not copy the old test pilot wholesale or relax the physics budget.
**Risks:** session work happens outside `sim.step()`; mutable caches or stale graph
results could hide coupling. **Exit gate:** one externally driven session is
equivalent to the original path, two sessions do not share control/weather/energy
state, and measured feasibility supports at least one companion without an
unexplained player regression.

**Tests:** existing `test_simulation.gd`, `test_session_guards.gd`,
`test_golden.gd`, `test_replay_integrity.gd`, relevant control/gear/fuel/battery tests;
new isolation fixture interleaves two different command tapes and compares each
against its standalone run. Test both processing modes to catch double stepping.

### Phase 1 — Playable airborne MVP

**Outcome:** player flies with 1–3 Stiks following believable, continuous circuits.
Dependencies: AFC-00…02; one qualified field/profile. No runway cycles,
aerobatics or scheduled incidents yet. Terrain/scenery contact remains real;
aircraft-to-aircraft physical contact is explicitly Off.

| ID | Concrete work | Proof / status |
| --- | --- | --- |
| AFC-03 | Add `companions.tscn`, manager, fleet clock, agent scene and one session per agent. Implement initial airborne join slots, ID/generation lifecycle, visibility-safe admission and common weather-time origin. | Pending: `test_companions_lifecycle.gd`; all participants receive exactly one tick, no startup overlaps, no input device reads by AI. |
| AFC-04 | Implement guidance/controller/pilot for straight flight, bank-limited turns, circuit/hold, energy guard and recovery. Add traffic index and conservative player/AI avoidance from the first playable version. | Pending: `test_companions_controller.gd`, `test_companions_avoidance.gd`; current-physics command/state traces and motion captures. |
| AFC-05 | Bind aircraft views through the real builder and float64 render boundary. Add limited spatial engine sources, pilot-camera preservation, optional labels and crash/fault cleanup fallback. | Pending: `capture_companions.gd`; correct hinges/CG/propeller, no duplicate sky/camera/ambience, no stuck audio on pause/removal. |
| AFC-06 | Add minimal Home/Pause controls: enabled, count, circuits, skill restricted to Experienced, seed, recall/remove. Persist only supported settings. Add explicit CLI `--companions=<0..3>` and `--companions-seed=<u32>` for deterministic developer launches; defaults remain Off. | Pending: `test_companions_ui.gd`; Home/direct-route isolation, restart, focus holds, invalid config refusal and keyboard/controller navigation. |

**Acceptance:** 20 seeded calm-air runs of 10 simulation minutes each, with three
companions, finish without AI-induced terrain contact, pilot/pit incursions or
unexplained command saturation. After joining, Stik circuit altitude error p95
≤3 m, airspeed error p95 ≤2 m/s, route cross-track p95 ≤8 m; revise targets only
with recorded rationale. The scripted player-crossing case causes early avoidance;
no claim of avoiding every arbitrary player maneuver. Count never exceeds the
requested or qualified cap. Off retains identical player accepted-state traces.

**Risks/decisions:** full-fidelity count may initially stop at one; show the actual
ceiling. Initial spawn/reset placement is allowed only at explicit lifecycle
boundaries, with full trim/propulsion state and collision checks. Continuous flight
uses no position correction. **Tests:** pause/focus/restart at every lifecycle
state; 30/60/144 fps and jittered-render decision replay on the same engine; corrupt
profile and solver-fault isolation; selected existing UI, field and log regressions.

### Phase 2 — Runway life and complete sorties

**Outcome:** companions taxi, take off, join, land, vacate and repeat while other
companions remain airborne. Dependencies: stable MVP plus ground/field owners and
qualified ground profiles. Initial scope is Stik/Club in calm and mild wind.

| ID | Concrete work | Proof / status |
| --- | --- | --- |
| AFC-07 | Implement runway reservation/occupancy states, approach/departure volumes, player requests, implicit player occupancy, queue fairness and blocked-runway state. | Pending: `test_companions_runway.gd`; simultaneous requests, stale grants, both directions, player incursion and crash occupancy. |
| AFC-08 | Author and validate Club staging/taxi edges and hold-short locations against visible scenery/collision proxies. Implement physical taxi and line-up with edge reservations and timeout recovery. | Pending: `test_companions_taxi.gd`; footprint clearance, deadlock/blocked edge, inability to turn, and no in-place rotation. |
| AFC-09 | Qualify takeoff/climb, arrival/flare/rollout, early abort and go-around using current Stik physics. Use existing research drivers for measurements; implement production state machines in the new pilot/maneuver files. | Pending: `test_companions_sortie.gd`; complete rollout metrics and unchanged aircraft data. |
| AFC-10 | Add energy reserve/return policy, sortie turnaround, recall, population increase/decrease and takeoff/landing activity controls. Reserve enough modeled endurance for two circuits and one go-around; deny a sortie when the profile cannot establish this. | Pending: fuel/battery reserve, depleted/ideal-energy distinctions, lineup readiness and population lifecycle evidence. |

**Acceptance:** 50 complete Stik sorties, split across runway directions and the
qualified weather matrix, with no reserved-volume overlaps. Successful landing
requires wheel contact inside the runway bounds, speed ≤0.5 m/s for 2 s while
supported, no terminal damage, then vacating; merely stopping on nearby grass
fails the landing criterion. Ten deliberate runway incursions each produce the
expected hold/abort/go-around without granting a conflicting operation.
Queued ordinary operations receive a turn within 120 s when the player/field is
not blocking and enough energy is available.

**Risks/decisions:** small-field taxi space and runway stopping distance may rule out
some aircraft; unsupported ground routes stay airborne-only. Wind reversal never
changes an occupied strip underneath aircraft. **Tests:** collision/ground-start
and scenery-scenario regressions, bounce/late flare, tailwind rejection, low fuel,
failed departure, blocked exit and pause during runway occupation. Require a
native pilot-view capture of overlapping circuit and runway activity.

### Phase 3 — Mixed aircraft and robust traffic

**Outcome:** different aircraft fly together with independent activity/skill
choices. Qualify 4–8 active aircraft before enabling the Club afternoon preset.
Dependencies: complete sorties; each model owner supplies current configuration
identity and evidence bounds.

| ID | Concrete work | Proof / status |
| --- | --- | --- |
| AFC-11 | Qualify Turbo Lumber, Extra, P-51, Jet and Stik powertrain variants individually. Add profile inheritance only for proven common controller fields; bind every resolved profile to its exact source hash. | Pending: `test_companions_profiles.gd`; per-model speed/turn/energy/equipment matrices; explicit unsupported activity reasons. |
| AFC-12 | Upgrade avoidance with intent trajectories, model-specific reachable turns, hysteresis, player priority and overtaking preparation. Maintain brute-force oracle and dense/fast crossing fixtures. | Pending: minimum-clearance reports, oracle equality, zero-distance/zero-relative-speed and 32-agent synthetic stress checks. |
| AFC-13 | Add activity scheduler, independent skill/quirks, model weights/maxima, fair slot allocation and full aircraft/activity settings. Keep incidents Off for this gate. | Pending: deterministic roster, no activity starvation in feasible fixtures, mixed-pilot stable control, UI labels and persistence checks. |
| AFC-14 | Qualify airborne traffic at Green paradise; make field-specific activity availability explicit. Add opt-in Natural Random composition with independent seeds and resolved briefing identity. Keep Workshop/rotorcraft/ground routes excluded. | Pending: landscape switching, unsupported ground-operation refusal, NR repeatability and no companions in unrelated activities. |

**Acceptance:** ten 20-minute mixed-fleet seeds at the qualified count, with no
unintended collisions or exclusion-volume entries in the controlled player tape.
Each advertised model completes its allowed activities; a jet unavailable for a
ground route is explained before launch. Independent activity overlap appears in
the event log, not only a staged screenshot. Weather outside profile bounds
blocks new sorties and invokes the tested airborne escape/return policy.

**Risks/decisions:** heterogeneous speed, unvalidated physics and long turbine lag
make a generic controller unsafe. Quirks cannot override limits. **Tests:**
head-on/crossing/overtake/landing-priority matrices, a sudden player turn, two
aircraft sharing a visual family, per-aircraft gear/flap state isolation and
model/field/profile hash mismatch rejection.

### Phase 4 — Aerobatics, passes and humorous recoveries

**Outcome:** visibly varied, simultaneous flight without making every airplane
an aerobat. Dependencies: stable mixed traffic and qualified maneuver boxes.

| ID | Concrete work | Proof / status |
| --- | --- | --- |
| AFC-15 | Implement loop and roll state machines with entry gates, progress, recovery and timeout aborts; then qualify linked maneuvers/inverted segments per model. | Pending: `test_companions_maneuvers.gd`; state/command/energy/rate/altitude traces for success and abort. |
| AFC-16 | Add flyby, low-pass and overtake route contracts, runway-linked reservations and separated entry/exit turns. | Pending: `test_companions_passes.gd`; speed/height/clearance bounds, player incursion abort and no rejoin conflict. |
| AFC-17 | Implement activity concurrency quotas/cooldowns and recoverable humorous scenarios from §5. Add optional notices and debug intent visualization. | Pending: `test_companions_scheduler.gd`; busy scenario contains circuits, a runway movement and a separate qualified maneuver concurrently. |
| AFC-18 | Conduct independent RC pilot review of trajectories and recognition from the existing pilot camera; tune controller profiles using baseline/candidate logs. | Pending: review card, build identity, shortcomings and accepted/rejected scenarios; software passes do not substitute for this gate. |

**Acceptance:** each enabled maneuver has 30 successful seeds across its qualified
entry envelope and 10 deliberately invalid entries that are refused or aborted.
All cases maintain finite bounded controls; intended inverted segments are
distinguished from stalls. Low passes meet their recorded minimum clearance and
do not enter pilot/pit volumes. Overtakes preserve separation through rejoin.
Three different activities overlap for at least 30 s in the scripted six-aircraft
fixture without runway double-booking.

**Risks/decisions:** physical envelopes may rule out entertaining ideas; disable
them instead of adding force boosts. Humor is optional and does not require new
assets. **Tests:** adverse wind/low energy/missing flaps/low entry altitude,
quaternion wrap/inverted control, interrupted maneuver pause/replay, and deliberate
planner deadlock or limit-removal mutations on disposable copies.

### Phase 5 — Mistakes, occasional crashes and shared aftermath

**Outcome:** believable error episodes and bounded companion crash handling,
including optional aircraft contact. Dependencies: reliable normal/recovery flight,
CR/EM/SF owners and full fleet recording.

| ID | Concrete work | Proof / status |
| --- | --- | --- |
| AFC-19 | Implement fleet-wide incident timing, eligibility/cooldowns, bounded mistake episodes and supported per-aircraft hardware-failure adapters. Add incident controls and clear opportunity-versus-outcome wording. | Pending: `test_companions_incidents.gd`; deterministic schedules, rates independent of render fps and aircraft count, cancellation logging and exact Off behavior. |
| AFC-20 | Extract explicit crash presentation context; reuse impact/wreck/audio/effects with global budgets. Separate companion events from player UI/reports and retain continuing-flight prop-strike behavior. | Pending: `test_companions_crashes.gd`; multiple incidents without focus/camera/report theft or duplicate events. |
| AFC-21 | Implement shared world damage publication, settled wreck occupancy, blocked-runway cleanup, delayed respawn and bounded resource retirement. | Pending: `test_companions_world.gd`; one damaged obstacle view for all sessions, safe cleanup, no collision proxy left after removal. |
| AFC-22 | Complete fleet checkpoint/journal and both replay modes, including incidents, admission decisions, world changes and global/local time origins. Wire diagnostics to existing flight-log tooling. | Pending: `test_companions_replay.gd`; mid-maneuver and mid-incident continuation, malformed/partial record refusal and complete exact comparisons. |
| AFC-23 | Implement and qualify optional moving-aircraft terminal contacts with swept proxies and joint event commit. Include the player only when contact is explicitly enabled. | Pending: `test_companions_contacts.gd`; opposing/parallel/wingtip/rotating/fast contacts, time ordering and failed-commit rollback. |

**Acceptance:** at least 30 injected opportunities per incident family demonstrate
both successful recovery and, where qualified, physical failure without directly
forcing a crash. A long headless scheduler run of 100,000 eligible simulated
minutes matches the configured opportunity rate within a predeclared statistical
interval; cooldown censoring is reported separately. Actual crash rate is measured,
not asserted equal to opportunity rate. Eight rapid terminal-event fixtures obey
effect caps while retaining every occupied wreck region. AI crashes never pause
the player's continuing flight or touch its accident archive.

**Risks/decisions:** paired contacts and shared damage are the largest coupling
risks. AFC-23 may remain explicitly unavailable while ground/scenery incident
features ship. No survivable midair/structural model is implied. **Tests:** existing
crash integration/snapshot/warmup and failure/replay tests, coincident ground/pair
events, rejected second participant commit, repeated event delivery, clearing a
runway during pause, stale pooled-generation callbacks and complete teardown.

### Phase 6 — Busy skies and measured scaling

**Outcome:** qualify 16/24/32 companions where the target hardware and field can
support them. Dependencies: stable feature workloads and profiling; optimization
must preserve accepted behavior.

| ID | Concrete work | Proof / status |
| --- | --- | --- |
| AFC-24 | Add reproducible headless and rendered count/model/regime matrix; integrate frame-time and per-system diagnostics. Run warm/cold, all-visible, offscreen, queue and multi-crash cases. | Pending: `bench_companions.gd`, raw samples and p50/p95/p99 reports; no “best run” substitution. |
| AFC-25 | Apply measured allocation/query/planner improvements and visual LOD/resource sharing; probe spatial MultiMesh batching only if justified. Preserve silhouette/control animation at useful viewing sizes. | Pending: state/decision equivalence, collision-oracle equality, before/after timing and pilot-view captures on the pinned renderer. |
| AFC-26 | Add bounded engine voices, shadows/lights/smoke/wreck presentation and startup preparation; implement cost-aware admission and visible overload recovery. | Pending: worst-case spawn/crash spike measurements, player audio priority, deterministic recorded admission and 50-cycle soak. |
| AFC-27 | Conditionally probe pure planning workers. If solver cost still prevents a named target count, evaluate the SF native-evaluator decision separately; otherwise omit that branch. Unlock only presets whose full mixed workload passes. | Pending: worker/single-thread decision equality and net speedup; per-platform supported-count matrix or explicit lower ceiling. |

**Acceptance:** pass §6 budgets for each advertised hardware/profile/count,
using three repeated 120 s foreground runs after 30 s warmup, plus a 20-minute
soak. Report startup separately. Use fixed source/seed/camera/player tapes and
separate user settings for each run. Overload stress at 48 requested aircraft must
remain bounded and visibly cap/retire traffic. GPU or Software-rendered captures
alone do not establish native performance.

**Risks/decisions:** 32 full flight models may not fit; the released count is the
highest qualified value, not a reason to silently switch to fake distant flight.
No multiplayer or multirate physics expansion in this phase. **Tests:** broad-phase
oracle under dense population, geometry/LOD transition captures, voice priority,
resource lifetimes, canceled async jobs on exit and exact replay across supported
quality settings.

### Phase 7 — Product polish and release qualification

**Outcome:** understandable controls, readable traffic, repeatable bug reports and
qualified native packages. Dependencies: all enabled feature gates and UI/AUD/DT
owner review.

| ID | Concrete work | Proof / status |
| --- | --- | --- |
| AFC-28 | Finish full settings/presets, supported/unsupported explanations, focus order, controller navigation, translations, scaled layouts and concise traffic notices. Update in-game Help/controls references. | Pending: `test_companions_ui.gd`; keyboard/controller-only journey, small/large UI, locale and corrupt/future preferences. |
| AFC-29 | Tune ambience balance, distant readability, notice frequency and funny-scenario repetition with RC pilots. Verify player aircraft remains easy to identify in busy traffic without mandatory labels. | Pending: pilot task results and motion/audio captures, including quiet/incident-Off sessions. |
| AFC-30 | Add registered AI JSON/scenes/resources to export checks where needed; run full parser/tests, targeted captures and clean-clone Windows/Linux/macOS package smoke. Add opt-in reproducible bug-report export. | Pending: qualified package/source IDs, fresh-import evidence, refusal of missing profiles and native platform results. |
| AFC-31 | Complete feature/field/model/count compatibility matrix and current user/developer instructions. Record accepted decisions in DECISIONS and only reusable lessons in LEARNINGS. | Pending: documented limits and evidence links; no pending phase claimed delivered. |
| AFC-32 | Perform final regression and owner acceptance, including full-session reset/end-flight and solo preservation. Consolidate this plan into the canonical companion guide and retain its evidence when completed/superseded. | Pending: acceptance ledger naming build, platforms, pilot reviews, supported presets and remaining restrictions. |

**Acceptance:** a new user can enable three companions, select allowed aircraft,
change activities/skill/incidents, request a landing, remove traffic and restore
Off without instructions outside the UI. All settings have predictable Apply,
Cancel and persistence behavior. No hidden dependency on development files.
Full app checks and native package runs pass for supported platforms; hardware or
pilot acceptance unavailable on a platform stays explicitly unqualified.

**Risks/decisions:** clutter and menu complexity can outweigh added life.
Prioritize clear defaults, minimal notices and coherent engine sound.
**Tests:** end-to-end Home → flight → pause → modify → resume → crash/recall →
restart → Home → relaunch, direct CLI independence, unsupported activity routes,
exported resources and companion Off equivalence.

## 8. Verification matrix and execution guidance

Use the [checked Godot runner](tools/godot/README.md) and
[tooling index](docs/TOOLS.md) for commands. Future focused tests follow:

```powershell
python tools/godot/run_checked.py --timeout 180 -- $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_companions_session.gd
```

`$GodotWindows` must be set to the repository-pinned installed engine as documented
in TOOLS. The companion scripts named here do not exist yet. Add them to the
normal runner when implemented; run `app/test.sh` through the documented Bash/WSL
workflow. Inspect engine errors as well as exit status. No implementation tests
were required or run for this planning-only change.

| Area | Required evidence and negative cases |
| --- | --- |
| Data/contracts | Missing/changed aircraft ID, stale profile hash, invalid units, NaN/Inf, unsupported feature, field mismatch, empty pool, too-large count and future schema. |
| Numerical/session | Complete-state parity for extracted session hooks; accepted control mapping once; per-session energy/gear/flap/actuator independence; deterministic clocks and random streams. |
| Flight | Continuous airborne and whole-sortie traces; actual trim, airflow, contact and energy paths; maneuver entry/recovery envelopes; no pose edits between lifecycle boundaries. |
| Traffic | Head-on/crossing/overtake, player incursion, simultaneous requests, stuck taxi edge, blocked runway, wind reversal, emergency priority, timeout and no-feasible-escape reporting. |
| Spatial | Swept broad phase versus exhaustive oracle; moving/rotating hull contact, empty and dense cells, fast aircraft, terrain discontinuities and no-fly volumes. |
| Lifecycle | Enable/disable/remove/recall, spawn refusal, late async callback, individual crash/fault, all holds, restart/reload, player crash and end-flight teardown. |
| Replay | Full restored continuation, accepted-input and decision replay, mid-flight spawn/global weather origin, incidents/world damage, mismatched sources and incomplete recordings. |
| Performance | All count/model/regime mixes, foreground CPU/GPU frame cost, per-tick tails, total simulation progress, cold start, effect spikes and bounded memory/voices/resources. |
| Presentation | Correct model/physics binding, CG, hinges and equipment; LOD silhouette, no teleport/pop during normal flight, spatial sound, no player camera/report theft. |
| Product | Save/Cancel, future-schema read-only behavior, Home/direct isolation, remapping, localization, keyboard/controller focus, disabled activity explanations and package resources. |

Maintain explicit invariants in diagnostics: finite accepted state, inputs in bounds,
one step per live session per global tick, no duplicate IDs/grants/events,
no unannounced count cap, bounded queues, no autonomous transition through a hold,
and no direct pose mutation outside spawn/reset/restore/terminal presentation.
Failure must name aircraft ID, generation, global/session tick, activity and source
identities. A test that only checks an exit code or final position is insufficient.

## 9. Unknowns and decisions that must be closed

These are execution gates with default dispositions, not open-ended invitations to
guess during implementation.

| Unknown / risk | Owner and resolving step | Default if unresolved |
| --- | --- | --- |
| How many current full aircraft solvers fit the target host? | Physics/performance, AFC-00/24; measure complete mixed sessions. | Ship only the lower qualified count; larger presets unavailable. |
| Exact ordering needed for external stepping, nonterminal contacts and player input | Physics/SF, AFC-01; parity and contact fixtures. | No Main integration until preserved. |
| Safe global-weather origin and session-local turbulence continuation | Environment/physics, AFC-02/03/22; spawn/restore tests at nonzero ticks. | Static launch roster only until time-origin semantics qualify. |
| Which current aircraft envelopes/gains are trustworthy? | Aircraft/physics, AFC-02/11/18; current data, independent traces and pilots. | Conservative circuits only for qualified models; no blanket catalog enablement. |
| Taxi, approach and recovery spaces at each field | LU/SC/ground/aircraft owners, AFC-07…09/14. | Airborne-only, model/field-specific restrictions; no fabricated runway fit. |
| Mutable material/resource caches and model-builder startup cost | Render/model owners, AFC-00/05/25. | Per-instance mutable state; prebuild at launch; cap count. |
| Existing crash director and soundscape coupling to Main | CR/AUD, AFC-05/20/26. | Minimal bounded companion presentation; no Main duplication. |
| Transactional paired contacts and shared scenery damage | SF/CR/LU, AFC-21…23; event-order/rollback evidence. | Physical aircraft contact Off; no exact fleet replay claim without needed context. |
| Can “funny” errors remain readable and credible? | RC pilot/product review, AFC-18/29. | Disable rejected scenario; keep ordinary traffic. |
| Night/strong wind/turbulence availability | Aircraft/FW/M5, AFC-11/29; per-profile visibility/weather checks. | Daylight and qualified weather only; explain unsupported conditions. |
| Native platform count/resource ceilings and quality | DT/performance, AFC-24…30. | Publish platform-specific qualified limits; no extrapolation from another OS. |
| Full fleet recording storage cost | FL/physics, AFC-22/24; bounded telemetry measurements. | Opt-in diagnostic recording with explicit limits; never block a physics tick on disk. |

Implementation is complete only when the chosen released scope has its data,
behavior, interaction, replay, performance, UI and native package evidence.
Features with open gates stay disabled and documented. A successful AI circuit
demonstrates a working controller in this simulator; it does not establish that
the underlying airplane has been physically validated.
