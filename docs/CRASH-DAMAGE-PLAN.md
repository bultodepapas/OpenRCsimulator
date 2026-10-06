# Crash, damage and destruction plan

2026-10-06 · revision 1 · **Status: plan; CR-00 (this plan, its research and the effective-mass experiment) done. Next: CR-01 impact event.** Step-ID prefix **CR-**, gate **Gate CR**. Brief: [prompt](prompts/CRASH-DAMAGE-ROADMAP-PROMPT.md). Research: [crash-damage-investigations/](research/crash-damage-investigations/README.md) (01–05). Evidence: [`research/crash-damage/`](../research/crash-damage/).

**Goal:** a crash that answers *how* it happened. Impact speed, angle, location, mass, structure, surface, aircraft type and the energy left over decide the outcome. A wingtip scrape, a collapsed gear leg, a hard landing, a tip-stall cartwheel and a 40 m/s turbine-jet impact must end differently, for physical reasons that a test can show.

**Owns:** `docs/CRASH-DAMAGE-PLAN.md`, `docs/research/crash-damage-investigations/`, `research/crash-damage/`, and, when their steps start, `app/render/crash/` (presentation), `app/assets/audio/crash/` (sounds with `sources.json`) and `app/tests/test_crash_*.gd`. **Shared through interfaces:** simulation-side steps (`app/physics/impact.gd`, `app/physics/structure.gd`, `FlightSession`) are built by the physics line under these CR IDs; visual sections are added by each aircraft's model team; the crash report lives in `app/ui/` with the menu track.

## 1. What exists, and what is missing

Read on 2026-10-06 (details and file references: [05 §What exists](research/crash-damage-investigations/05-architecture-impact-model.md#what-exists-and-what-each-cr-phase-reuses)).

| Exists | Missing |
| --- | --- |
| Crash detection: any `crash_hull` point at or below the ground, or a gear leg past its travel (D9d, E1) | Which point hit, how hard, on what surface; sub-tick order |
| 1.5 s freeze, speed and sink in the panel, reset | A picture that is not the airplane buried at the tick end; a sound; an engine that dies instead of freezing mid-buzz |
| Per-component mass inventory with CG and inertia (D1-R1) | Structural sections, joints and failure limits |
| Local wing and tail loads (D9-R1); strips planned (D11d) | Part loss feeding back into lift, mass and inertia (ROADMAP E7b, planned only) |
| Gear contacts, tyre friction, field surfaces (E1–E3a) | Frictional hull contacts (E3d1) and prop-strike events (E3d2): planned in M2 |
| Turbine spool model (AV-05a); the Avanti flies (AV-07) | ECU states (AV-05b), fuel burn (AV-10, G4a), fire and smoke |
| Deterministic 240 Hz replay, traces, goldens | Crash replay, crash report, event rows |
| Particle research for smoke (SM, Compatibility renderer) | Any particle, debris or decal code in `app/` |

**Limits that shape the plan:** contacts are soft springs (a 15 m/s nose-in would sink ≈ 0.6 m into a spring ground), so the simulation cannot resolve a violent crash and must hand the wreck to Godot physics. Godot physics is 32-bit and frame-synchronised, so it never decides the flight. The physics tick sits at ≈ 501 of its 500 µs budget, so nothing may add per-tick cost in undamaged flight. The renderer is gl_compatibility, and the development VM has no GPU, so visual cost is judged on the owner's machine.

## 2. Architecture in one page

Full design: [05](research/crash-damage-investigations/05-architecture-impact-model.md).

1. **The simulation decides, presentation shows.** Impact events, the structural outcome and the post-impact state are pure functions of the deterministic state. Sound, particles, debris, wreck, camera and replay read them, and nothing flows back.
2. **The simulation owns the airplane while it is an airplane.** A scrape or a broken part keeps it flying or rolling (C0–C2). A structural crash (C3/C4) stops the simulation and hands the wreck to Godot physics, starting from a deterministically computed post-impact state.
3. **Where and how it hits sets the energy:** e = ½·m_eff·v_n², with m_eff = 1/(1/m + (r×n)ᵀI⁻¹(r×n)). From our data, a wingtip hit vertically engages 5–7 % of the airplane's mass, a spinner hit 30–40 % and a vertical nose-in all of it ([cr-00 results](../research/crash-damage/cr-00/results.txt)).
4. **One resolver, two feeders:** `structure.resolve(event)` breaks joints in an energy cascade from the struck section inwards. The simulation feeds it first contacts; the wreck's Godot contacts feed it secondary hits.
5. **Damage reuses existing seams:** the inventory recomputes mass, CG and inertia after part loss; local surfaces and strips lose lift; gear contacts are a list; engine states come from G2d and AV-05b. A damage change happens only in `pre_step`.
6. **Durability is a multiplier**, a setting written in the trace header that never changes the data.

**Outcome classes:** C0 contact · C1 scrape · C2 damaged, still flying or rolling · C3 structural crash · C4 destroyed ([table](research/crash-damage-investigations/05-architecture-impact-model.md#outcome-classes)).

## 3. Phases and where they sit in the main roadmap

| Phase | What the player gets | Sits | Needs first |
| --- | --- | --- | --- |
| **CR-A** Crash you can read | The impact instant (not a buried airplane), the component and energy, a real impact sound, the engine dying, dust and a mark, a tumbling wreck, a crash report | **Now**, beside M2; no simulation behaviour change | Today's code only |
| **CR-B** Breakable airplane | Wings, tail, gear, engine and canopy come off according to where and how hard it hit; material sounds | After CR-A; before or beside E3d | Model teams' section groups; doc 03 thresholds |
| **CR-C** Damage you fly with | Scrapes, gear loss, prop strikes, lost tips and surfaces that keep the airplane flying or rolling, with real aero, mass and engine effects | **M2 → M2+**, after E3d1/E3d2; absorbs ROADMAP E7b | E3d1, E3d2, D11d, H8 (recommended), G4b (mass update, shared) |
| **CR-D** Terrain, trees, fragments | Crashes on slopes and into trees (lodged in a crown), fragmentation for violent impacts, a debris field that stays | **M2+** with LANDSCAPE L12–L14 and E6b/E6c | L12a sampler, L14 obstacles |
| **CR-E** Fuel, turbines, fire | The turbine winds down after the ECU cuts fuel; gas and glow engines die their own ways; kerosene fire and smoke only when a tank ruptured with fuel left | **M4**, with AV-05b, AV-10/G4a and SM-00 | ECU states, fuel state, particle backend |
| **CR-F** Presentation | Instant replay from any camera, slow motion, a teaching crash report, honest camera rules, mixed and propagated crash audio, the durability setting | Replay and the report can start after CR-04; audio polish with G3; settings with UI-07/08 | G3a/G3d, UI-07/08, PERC |
| **Gate CR** | The owner judges plausibility and feel | After CR-B, again after CR-C | — |

Each phase leaves a playable improvement. Nothing in CR-A or CR-B is thrown away later: the event, the resolver, the sections and the handoff are the pieces that CR-C to CR-F extend.

## 4. Steps

Columns follow [docs/README.md](README.md#conventions-for-documents): ID, step, proof, dependencies, status. Every step also reports µs/tick or frame time where it adds cost, keeps goldens and `--trace` rows byte-identical unless it says otherwise, and adds a LEARNINGS entry. "Owner" names the team that builds it.

### CR-A — Crash you can read

| | |
| --- | --- |
| Objective | Replace the frozen frame with a crash the pilot can hear, see and understand, without changing any flight behaviour |
| Systems | Crash detection (`FlightSession`), new `physics/impact.gd`, engine sound, new `render/crash/` presenter, captures, panel/UI |
| Approach | Name the hull points, compute ordered impact events with sub-tick timing and m_eff, publish them as a signal and a trace sidecar; presentation reacts (sound, dust, mark, whole-airplane wreck body, report) |
| Files | `app/physics/impact.gd`, `app/sim/flight_session.gd`, `app/data/aircraft/*.json` (labels), `app/render/crash/{crash_presenter,crash_audio,wreck}.gd`, `app/assets/audio/crash/`, `app/ui/crash_report.*`, `app/tests/test_crash_events.gd`, `app/capture.sh` (crash case) |
| Validation | Hand-computed events, m_eff against `cr-00`, impulse conservation tests, captures at fixed simulation times, owner listening note |
| Performance risks | Per-tick check must stay ≤ 5 µs; first-crash shader compilation hitch; one rigid body is negligible |
| Read first | [05](research/crash-damage-investigations/05-architecture-impact-model.md), [04](research/crash-damage-investigations/04-audio-presentation-feel.md), [02](research/crash-damage-investigations/02-godot-destruction-techniques.md), knowledge base [10](research/roadmap-investigations/10-audio-perception-presentation.md) |


| ID | Step | Proof | Depends on · owner | Status |
| --- | --- | --- | --- | --- |
| CR-00 | This plan, research 01–05, effective-mass experiment | `research/crash-damage/cr-00/` reproduces `results.txt`; links resolve | — · crash track | ✅ 2026-10-06 |
| CR-01 | **Impact event.** Labels for every `crash_hull` point (optional `labels` list next to `value`, the same ids E3d1's typed contacts keep; generators add them for the Extra, P-51 and Avanti). Pure `physics/impact.gd`: crossing fraction per point, ordered events, v_n, v_t, m_eff, e_normal, e_total, attitude, surface (fields in [05](research/crash-damage-investigations/05-architecture-impact-model.md#the-impact-event)). `FlightSession.impact` signal; events in a trace sidecar (`openrc-events v1`); the panel names the component, v_n and energy; the frozen frame shows the state at the crossing, not the buried tick end | Hand-computed events for a tip, a nose-in, a belly and a knife-edge state; crossing fraction exact for a linear descent; m_eff equals `cr-00/results.txt` to 1e-9; `test_crash.gd`'s 100 random crashes give finite, ordered events; mutation "total mass instead of m_eff" fails; goldens and trace rows identical | — · physics line | — |
| CR-02 | **Crash sound v1.** The crash is heard when its sound arrives: the engine keeps sounding until the impact's travel time (distance / 343 m/s: 0.29 s at 100 m) and then runs down (v1: rpm to 0 over a labelled estimate, later from G2d or AV-05), instead of today's `stream_paused` cut at the visual instant. One impact one-shot (transient plus body) chosen by energy class (3, level +10 dB per 10× energy) × surface group (soft, hard), its variation seeded by the event id so a replay sounds the same, Godot's Doppler and distance filter off; an `Impacts` bus (UI-08 adds its volume). CC0 samples only, with `sources.json`; then the silence | Pure selection, level and delay functions unit-tested (onset at t + r/c ± 1 ms at 30/100/150 m); an end-to-end crash plays exactly one impact voice with the expected id; the engine stream is never paused by a crash; a licence check fails on any non-CC0 entry; the owner's listening note | CR-01 · crash track | — |
| CR-03 | **Impact you can see.** A one-shot dust or turf puff at the point (`GPUParticles3D`, supported in Compatibility; surface-tinted, size from log e_normal), the airplane drawn at the impact instant, and a scuff mark that stays until restart. `Decal` is not drawn in Compatibility, so marks are a small fixed array of mark uniforms in `ground.gdshader` (an interface the landscape track adds). Every crash material and emitter is drawn once at load: Compatibility compiles shaders on first draw (0.8–1.15 s cold on the VM). No camera shake in the pilot view | `capture.sh` crash case at fixed simulation times (runway and grass); the energy-to-particle mapping is unit-tested; the first crash's frame time equals a later crash's within 10 % (no compile stall); frame time on the owner's machine; captures of normal flight unchanged | CR-01; SM-00 backend decision (or this step makes it, recorded for SM); mark interface from the landscape track · crash track | — |
| CR-04 | **Wreck handoff.** At C3, the simulation computes the post-impact state (plastic normal impulse with e ≈ 0.1 and a friction impulse; [05](research/crash-damage-investigations/05-architecture-impact-model.md#the-resolver-pure-deterministic)). A hidden copy of the airplane, built at flight start (≈ 8 ms; rebuilding at crash time costs 24–224 ms), becomes one `RigidBody3D` (GodotPhysics3D, the project's engine: Jolt caps speed at 500 m/s and spin at 47 rad/s) with that velocity and rate, mass and inertia from the data, box shapes from part bounds, CCD on, on a ground collider; it tumbles and settles. The flown airplane and its node names stay untouched. Godot physics and particles pause with every menu hold. The wreck settles, the silence plays, then the pilot restarts (owner decides the default) | Impulse unit tests: kinetic energy never rises, angular momentum about the contact point is conserved for the frictionless case, a tip hit produces roll (the cartwheel sign); `--trace` hash and goldens identical with effects on and off; a menu during the tumble freezes it; after reset the node tree equals a fresh build; capture sequence | CR-01 · crash track (impulse in `physics/impact.gd` by the physics line) | — |
| CR-05 | **Crash report v1.** What hit, how fast, at what angle, with how much energy, which class, and what led to it, read from the last 3 s of the simulation (stall flag, bank, sink, throttle, the last input). It teaches: "left wingtip at 7.4 m/s, 52° bank, 0.8 s after the stall" | The report function is tested on recorded scripted crashes (tip stall, vertical nose-in, hard landing, slow-roll into the ground); UI test that it shows and dismisses; no effect on the trace | CR-01 · crash track with the menu track (`app/ui/`) | — |

### CR-B — Breakable airplane

| | |
| --- | --- |
| Objective | Parts come off where and as hard as the impact says, and the outcome is validated against real crashes |
| Systems | Aircraft data (`structure`), loader, visual builders (sections), new `physics/structure.gd`, wreck presenter, audio and particles |
| Approach | Logical sections own inventory items, hull points and one joint each; the pure resolver breaks joints in an energy cascade; the presenter splits the wreck along the broken joints; Godot contacts feed secondary breaks through the same resolver |
| Files | `app/physics/structure.gd`, `app/physics/aircraft_data.gd` (optional section), `app/data/aircraft/jensen_ugly_stik_60.json`, generators `research/*/derive_physics.py`, `app/aircraft/*_model.gd` + `verify_*.gd` (sections), `app/render/crash/{breakup,debris}.gd`, `research/crash-damage/cr-08/` |
| Validation | Five-situation scenario test with mutations, the reference crash set (CR-08), Gate CR (1) |
| Performance risks | Body count after a C4 crash; convex shapes from procedural meshes; voice count in a many-break crash |
| Read first | [03](research/crash-damage-investigations/03-rc-construction-crash-physics.md), [01](research/crash-damage-investigations/01-simulators-games-damage-models.md), [02](research/crash-damage-investigations/02-godot-destruction-techniques.md) |


| ID | Step | Proof | Depends on · owner | Status |
| --- | --- | --- | --- | --- |
| CR-06 | **Visual sections contract.** Every builder returns `sections: { id: Node3D }`: wing halves (or panels), fuselage front and rear, stab halves, fin, canopy or hatch, cowl, engine with propeller, each gear leg. Break along these named parts, never by runtime cutting. Hinges stay inside their section; node names `airplane`, `propeller` and `*_hinge` stay unchanged (the P-51's single `wing` node needs splitting into halves). Convex hulls, if used, are computed at load without simplification (0.4–4.7 ms; simplified hulls cost 100–140 ms). A build without sections is one section, so CR-04 still works | Each `verify_*.gd` checks that every mesh belongs to exactly one section and that the ids match the data; captures byte-identical (grouping only) | — · each model team (Stik first) | — |
| CR-07 | **Structure data and resolver.** An optional `structure` section ([05](research/crash-damage-investigations/05-architecture-impact-model.md#structure-data-proposal-optional-section-of-openrc-aircraft-v1)): sections with parent, material, inventory items, hull points, and a joint with `absorb_energy` per failure mode (values from [03](research/crash-damage-investigations/03-rc-construction-crash-physics.md), each with a kind), plus surface factors. The loader refuses unknown or double-claimed inventory items. Pure `physics/structure.gd` resolver with the energy cascade and the durability multiplier. Stik by hand; generators add the section for the other aircraft | **The five-situation test** (minor wingtip strike, gear failure, hard landing, tip-stall crash, high-energy jet impact) gives five distinct classes and broken-section sets; mutations "ignore direction", "no cascade", "total mass instead of m_eff" each fail a row; loader refusals tested | CR-01 · physics line; generators by their tracks | — |
| CR-08 | **Reference crash set (independent validation, rule 6).** 15–20 public videos of real RC crashes (links only), each with estimated impact speed, angle and first component (frame counting, kind `measured (video)`) and the observed outcome (parts broken, class) | The resolver puts ≥ 80 % in the observed class and none more than one class away; the misses are listed and explained, never tuned away (rule 10) | CR-07 · crash track | — |
| CR-09 | **Visual breakup.** At C3/C4 the wreck splits along the resolver's broken joints: each detached section becomes its own body with v + ω × r, mass and inertia from its inventory share. Secondary Godot contacts feed the same resolver (presentation only). Pieces stay until restart, within a body budget | Captures of the five situations show different breakups; bodies ≤ budget; frame time on the owner's machine; trace rows unchanged | CR-04, CR-06, CR-07 · crash track | — |
| CR-10 | **Material sounds and particles.** Material × surface matrix (balsa and ply crack, foam crunch, composite shatter, metal clank; runway, mown, rough, later tree), one voice per break event, scrape loops for a sliding wreck, splinters, foam crumbs or glass-fibre shards by material | Selection table unit-tested (every pair has a sound or a declared fallback); voice limit holds in a 20-break crash; owner A/B note | CR-02, CR-09 · crash track | — |
| **Gate CR (1)** | **Does a crash look, sound and break plausibly?** The owner watches and flies the five situations on the Stik and one other aircraft, rating each −2 (too fragile) … +2 (too tough) and its readability | Ratings recorded; any rating beyond ±1 changes `absorb_energy` values (data, with the reason) or the plan | CR-05, CR-09, CR-10 · owner | — |

### CR-C — Damage you fly with (M2 → M2+)

| | |
| --- | --- |
| Objective | Minor and moderate impacts leave a damaged airplane that still flies or rolls, with physically correct consequences |
| Systems | Hull contacts (E3d1), prop strike (E3d2), aero strips and tail surfaces, mass properties, propulsion states, servo stage, trace |
| Approach | The resolver's class decides whether the flight continues; damage is applied in `pre_step` as a configuration change (later H8 extras); part loss removes inventory items and strips and re-references the state to the new CG |
| Files | `app/sim/flight_session.gd`, `app/physics/{structure,aero,dynamics,ground_contact,propulsion}.gd`, a shared `mass_properties` function, `app/tests/test_crash_damage.gd`, `app/tests/golden/` (unchanged) |
| Validation | E3d1/E3d2 proofs, E7b strip-removal check, velocity-field continuity, scripted "fly home damaged" maneuvers, Gate CR (2) |
| Performance risks | Damage terms must cost nothing when undamaged; a damaged airplane may run the stalled path (≈ 570 µs/tick) more often: Phase H headroom first |
| Read first | [05 §Damage back into the flight](research/crash-damage-investigations/05-architecture-impact-model.md#damage-back-into-the-flight-c2), knowledge base [04](research/roadmap-investigations/04-ground-handling-collisions.md), [02](research/roadmap-investigations/02-aerodynamics-rc-scale.md), [01](research/roadmap-investigations/01-numerics-architecture-performance.md) |


| ID | Step | Proof | Depends on · owner | Status |
| --- | --- | --- | --- | --- |
| CR-11 | **Continue after C0–C2.** With E3d1's frictional hull contacts, the resolver's class decides whether a touch ends the flight. Scrapes make marks and sounds while the airplane rolls or flies on | E3d1's anchors pass (tip at walking pace rocks back; nose-in at 10 m/s crashes; belly at 1 m/s slides); the five situations flown through the real loop end in their classes | E3d1, CR-07 · physics line | — |
| CR-12 | **Gear and propeller damage.** A leg past its force or travel limit leaves the contact list and becomes debris; the belly takes over. A prop strike (E3d2) breaks the prop: thrust factor 0 (or a fraction for one lost blade), and the engine stops at low rpm or over-revs without load | Hard-landing scenario: gear gone, belly slide, airframe intact; a prop strike stops the thrust on the next tick; with G2a the unloaded engine's rpm rise matches the shaft balance; event rows; goldens unchanged | E3d2, CR-11 · physics line | — |
| CR-13 | **Part loss with aero and mass feedback** (absorbs ROADMAP E7b): wingtip or outer panel, stab half, elevator or rudder, canopy, hatch, cowl. Strips or surfaces removed; mass, CG and inertia recomputed from the inventory; the state re-referenced to the new CG with a continuous velocity field | E7b's proof (the lost-tip roll moment equals the strip removal in `linearize.gd`); v at every surviving point is continuous across the separation to 1e-12; mass properties equal the inventory without the lost items to 1e-12; a scripted "fly home without a tip" stays controllable with the computed aileron trim | D11d, CR-11, G4b or a shared mass-update function · physics line | — |
| CR-14 | **Control-system damage.** A stripped servo or a popped linkage leaves a surface floating at 0 or stuck where it was, as the outcome of specific hits (aileron bay, tail); optional failure injection for training (owner decides) | Unit tests per mode; trace shows the frozen surface; no effect without damage | CR-13 · physics line | — |
| CR-15 | **In-flight structural failure.** A load-factor limit per joint (wing fold in a hard pull-out); for jets, a labelled flutter speed per surface | A scripted pull above the limit folds the wing, one below does not; the durability multiplier scales the limit; goldens unchanged | CR-13 · physics line | — |
| **Gate CR (2)** | **Does flying damaged feel right?** The owner flies home with a lost tip, lands without a leg, and dead-sticks after a prop strike | Ratings recorded; DECISIONS row | CR-11–CR-14 · owner | — |

### CR-D — Terrain, trees, fragments (M2+)

| | |
| --- | --- |
| Objective | Crashes respect the ground they happen on and the obstacles around the field; violent impacts fragment |
| Systems | Terrain sampler (L12a), obstacles (L14, E6c), wreck colliders, fragment pools, ground marks |
| Approach | Same events with a terrain normal and an obstacle surface; the wreck's colliders are built from the same float64 data; fragments are pre-split meshes in pools |
| Files | `app/sim/terrain.gd` (landscape track), `app/render/crash/{fragments,marks}.gd`, collider builders |
| Validation | Normals equal to the sampler, tree hits at the right tick, budgets in the worst case |
| Performance risks | Fragment counts; heightmap collider build time; mark memory |
| Read first | [02](research/crash-damage-investigations/02-godot-destruction-techniques.md), [LANDSCAPE-PLAN](LANDSCAPE-PLAN.md) L12–L14, knowledge base [04](research/roadmap-investigations/04-ground-handling-collisions.md) §7 |


| ID | Step | Proof | Depends on · owner | Status |
| --- | --- | --- | --- | --- |
| CR-16 | **Terrain-aware impacts.** The event normal and surface come from the L12a sampler; the wreck's collider is built from the same grid (visual only) | A hillside crash's event normal equals the sampler's to 1e-12; the wreck rests on the slope; an all-flat grid reproduces CR-01 events byte for byte | L12a, E6b · crash track + physics line | — |
| CR-17 | **Trees.** E6c's float64 trunks and crowns produce events with surface `tree`: a trunk hit breaks like a wall; a crown catches and holds the wreck (the classic RC tree landing), with leaf and branch particles | A scripted flight into a trunk crashes at the right tick ± 1; a crown hit leaves the wreck lodged; flying between trees changes nothing | E6c, L14 · crash track + physics line | — |
| CR-18 | **Fragmentation for C4.** Three tiers: ≤ 24 large parts as rigid bodies; hundreds of splinters and shards as one MultiMesh moved by our own simple integrator with drag (≈ 0.5 µs per piece per frame, measured on the VM); dust, smoke and sparks as particles. Pre-split section meshes cut at build time from the procedural meshes or offline; no fading by switching materials to transparent (a compile stall mid-crash) | Fragment and body budgets hold in the worst case; frame time on the owner's machine; captures | CR-09 · crash track | — |
| CR-19 | **The field remembers.** Gouges sized by slide distance, scattered parts and a wreck that stay until restart; an "inspect the wreck" camera | Capture; marks bounded in count and memory; reset clears everything | CR-09 · crash track | — |

### CR-E — Fuel, turbines and fire (M4)

| | |
| --- | --- |
| Objective | Each power plant ends a crash its own way; fire happens only when fuel, a ruptured tank and an ignition source say so |
| Systems | Engine and ECU states (G2d, AV-05b), fuel state (AV-10, G4a), resolver (tank section), particle backend (SM-00), wind (M5-W), audio |
| Approach | A deterministic decision table with a seeded draw; fire duration from the fuel budget; visuals by fuel type |
| Files | `app/physics/{turbine,propulsion}.gd` (states), `app/physics/structure.gd` (tank rupture), `app/render/crash/{fire,smoke}.gd` |
| Validation | Spool-down against the data, decision-table and frequency tests, captures, frame time |
| Performance risks | Smoke and fire overdraw (transparent particles) on low-end GPUs; lights in the Compatibility renderer |
| Read first | [03](research/crash-damage-investigations/03-rc-construction-crash-physics.md) (turbines, fuels), [02](research/crash-damage-investigations/02-godot-destruction-techniques.md) (particles, lights), [SMOKE-PLAN](SMOKE-PLAN.md), [avanti-s-av05-turbine-dynamics](research/avanti-s-av05-turbine-dynamics.md) |


| ID | Step | Proof | Depends on · owner | Status |
| --- | --- | --- | --- | --- |
| CR-20 | **Engines after an impact, per type.** Glow: dies (or keeps idling on a soft hit). Gas (P-51): ignition kill. Electric (M4b): ESC cut. Turbine: the ECU cuts fuel on crash or failsafe, the spool winds down on the AV-05a deceleration schedule with its whine, and the tailpipe smokes during cool-down | Spool-down time from the data ±5 %; the sound's pitch follows N; each type's state machine is unit-tested | AV-05b, G2d, CR-02 · physics line + crash track | — |
| CR-21 | **Fuel and fire decision.** Deterministic: tank section broken × fuel remaining (AV-10/G4a) × ignition source (hot turbine, gas ignition) × a seeded draw (seed in the trace header) → spill, smoulder or fire, with a duration from fuel mass and burn rate. Glow fuel burns almost invisibly; a LiPo vents smoke | Decision-table tests; the fire rate over a seeded batch of crashes matches the research frequency within its band; owner decides the default | CR-07, AV-10, G4a · physics line | — |
| CR-22 | **Fire and smoke visuals.** Sooty orange kerosene flame and a black smoke column that drifts with the wind (M5-W), a flickering light, LiPo white-grey smoke; same particle backend as smoke | Captures; frame time; particle count within budget; drifts with the wind once W lands | CR-21, SM-00 · crash track | — |
| CR-23 | **The high-energy jet impact.** Composite shell shatters, wing panels separate, the turbine casing tumbles as heavy debris, fire only when CR-21 says so: acceptance situation 5 | The scripted 40 m/s Avanti nose-in gives C4 with the expected sections; capture sequence; frame time | CR-18, CR-20–CR-22 · crash track | — |

### CR-F — Presentation

| | |
| --- | --- |
| Objective | A crash the pilot can review, rewind and learn from, with audio and camera that stay honest |
| Systems | Replay buffer, cameras, audio propagation (G3), preferences (UI-07/08), crash log |
| Approach | Exact replay of the deterministic part; recorded transforms for the wreck; camera rules by view; the durability multiplier as a recorded setting |
| Files | `app/render/crash/replay.gd`, `app/render/pilot_camera.gd` (visual track), `app/ui/` (menu track), audio buses |
| Validation | Exact replay equality, audio onset and spectra tests, owner ratings |
| Performance risks | Replay memory (30 s × 240 Hz × ≈ 40 floats ≈ 2.3 MB, plus wreck transforms per frame); re-simulation time for a rewind |
| Read first | [04](research/crash-damage-investigations/04-audio-presentation-feel.md), knowledge base [10](research/roadmap-investigations/10-audio-perception-presentation.md) |


| ID | Step | Proof | Depends on · owner | Status |
| --- | --- | --- | --- | --- |
| CR-24 | **Instant replay and rewind** (slow motion plays recorded states; `Engine.time_scale` does not slow our simulation). A ring buffer of the last 30 s of simulation rows (≈ 2.3 MB) plus per-frame wreck and debris transforms recorded while they move; replay from the pilot, close-up, orbit or ground camera, slow motion (labelled) and scrub, with crash audio re-rendered from the events for the replay listener. **Rewind and take over:** re-simulate from a checkpoint with the recorded inputs, then hand the sticks back | Replayed simulation poses equal the recording exactly; re-simulation reproduces the recorded rows bit for bit up to the handover; wreck replay frame for frame; memory within the budget | CR-04 · crash track + menu track | — |
| CR-25 | **Crash audio polish.** Own propagation (G3d: travel delay, Doppler, air absorption), debris rattle and settling ticks, the silence after, the turbine spool-down whine, a limiter on the SFX bus | Offline spectra and onset delay tests (G3d's); owner ABX note | G3a, G3d, CR-10 · crash track | — |
| CR-26 | **Camera rules.** Pilot view: no shake, freeze or slow motion; auto-zoom follows the wreck until it settles. Close-up view (today's second camera, fixed to the airplane): a rotational shake ≤ 0.5° only within ≈ 5 m of the impact (estimated). Freeze-frame and slow motion only inside a replay; a ground camera near the impact for replays | Unit test: the pilot camera never shakes or slows; owner rating | CR-04 · crash track + visual track | — |
| CR-27 | **Durability setting, crash log, rumble.** Realistic or forgiving multiplier in preferences, written in the trace header; per-session crash log (cause, component, energy) feeding training modes; optional gamepad rumble on first contact only, off by default (a USB radio cannot vibrate) | UI-07 persistence test; header shows the multiplier; replay with a different multiplier is flagged; fake joypad: one rumble call per first contact, none in flight | UI-07, CR-07 · menu track + crash track | — |

## 5. Dependencies: what should move earlier or wait

**Do earlier (recommended):**
1. **CR-01 before E3d1.** E3d1 then builds its typed contacts on the labels and the event, instead of inventing a second naming.
2. **H8 (extensible state) before CR-C.** Damage flags, the broken-prop state and the fuel state then live in the replayable state. Until then damage is session configuration recomputed on replay.
3. **One mass-update function for G4b and CR-13.** Whichever lands first writes `mass_properties.update(model, removed_items, fuel)`; the other reuses it.
4. **DATA-8 adopts the CR-07 section ids** as component ids, so the v2 migration renames nothing.
5. **SM-00 and CR-03 share one particle-backend decision**, recorded once.

**Wait (do not pull forward):**
- Fragmentation (CR-18) before CR-08 has validated the resolver: shattering pieces on wrong thresholds only hides the error.
- Fire (CR-21/22) before fuel state and ECU states exist: a fire without a fuel budget is a guess.
- Godot physics inside the simulation, ever (32-bit, frame-synced; [doc 04 of the knowledge base](research/roadmap-investigations/04-ground-handling-collisions.md)).

## 6. Rules specific to this track

1. **No impact, no change:** every CR step keeps goldens and `--trace` rows byte-identical in undamaged flight, and adds no µs/tick there.
2. **Thresholds are data with provenance**, never constants in code. The durability multiplier never rewrites data.
3. **Honest presentation:** sound arrives late, as at the field; no explosions from balsa and glow fuel, no camera shake in the pilot view, no slow motion outside a replay, no fire without fuel and an ignition source, no auto-restart over the aftermath ([04](research/crash-damage-investigations/04-audio-presentation-feel.md)).
4. **Presentation is disposable, the simulation is not:** anything Godot physics computes may vary between machines and is never tested for exact values; the events and the resolver are.
5. **Budgets are measured** on the owner's machine (frame time p95 with the worst crash) before a step is called done.

## 7. Decisions for the owner

Recommendation first; each becomes a DECISIONS row when taken.
1. **Default durability:** realistic (1.0), with a forgiving option. (Plan review #4, decision 10.)
2. **Prop strike at idle:** engine stops, airplane keeps rolling (not a crash).
3. **After a structural crash:** the wreck settles, the report shows, and the pilot restarts with a key; automatic restart after 4 s stays an option for practice.
4. **Fire:** on when the physics says so (rare), with an option to turn it off.
5. **Wreck persistence:** pieces stay until restart, like a real field, within the body budget.

## 8. Risks

| Risk | Mitigation |
| --- | --- |
| Thresholds decide fun more than physics does | Durability multiplier; Gate CR ratings; reference crash set (CR-08) before fragmentation |
| The visual wreck disagrees with the simulated impact | The handoff starts from the simulation's post-impact state; captures check direction of tumble |
| Frame spikes on the first crash (shader and material compilation) | Pre-warm crash materials and particles at load ([02](research/crash-damage-investigations/02-godot-destruction-techniques.md)); measure the first crash separately |
| Model teams' builders diverge in section names | One contract (CR-06), checked by each `verify_*.gd`, ids from the data |
| Physics budget | Event-only work; zero cost without damage; Phase H headroom |
| Sound licences | CC0 or own recordings only, `sources.json` with hashes |
