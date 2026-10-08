# Crash, damage and destruction plan

2026-10-08 · revision 4 · **Status: CR-00, CR-01a diagnostics and CR-01b crossing reconstruction verified. CR-01 rendered crossing pose and reference-aircraft labels remain open. Report 03 (material and structure thresholds) is pending under CR-07.** Step-ID prefix **CR-**, gate **Gate CR**. Brief: [prompt](prompts/CRASH-DAMAGE-ROADMAP-PROMPT.md). Research: [crash-damage-investigations/](research/crash-damage-investigations/README.md) (01, 02, 04, 05; 03 pending). Evidence: [`research/crash-damage/`](../research/crash-damage/).

**Long-term goal:** explain crash outcomes from observed contacts and validated airframe evidence. The next step is narrower: identify the triggering contact and show its available kinematics. It does not diagnose pilot error, classify structural damage, or establish material strength.

**Owns:** `docs/CRASH-DAMAGE-PLAN.md`, `docs/research/crash-damage-investigations/`, `research/crash-damage/`, and, when their steps start, `app/render/crash/` (presentation), `app/assets/audio/crash/` (sounds with `sources.json`) and `app/tests/test_crash_*.gd`. **Shared through interfaces:** simulation-side steps (`app/physics/impact.gd`, `app/physics/structure.gd`, `FlightSession`) are built by the physics line under these CR IDs; visual sections are added by each aircraft's model team; the crash report lives in `app/ui/` with the menu track.

## 1. What exists, and what is missing

Read on 2026-10-06 (details and file references: [05 §What exists](research/crash-damage-investigations/05-architecture-impact-model.md#what-exists-and-what-each-cr-phase-reuses)).

| Exists | Missing |
| --- | --- |
| Crash detection: any `crash_hull` point at or below the ground, or a gear leg past its travel (D9d, E1) | A typed record of the trigger; a labelled point where the data support it; an impact-pose image |
| 1.5 s freeze, speed and sink in the panel, reset | A short, factual contact cause and available kinematics; audio, particles, marks and a moving wreck are later presentation work |
| Per-component mass inventory with CG and inertia (D1-R1) | Structural sections, joints and failure limits |
| Local wing and tail loads (D9-R1); strips planned (D11d) | Part loss feeding back into lift, mass and inertia (ROADMAP E7b, planned only) |
| Gear contacts, tyre friction, field surfaces (E1–E3a) | Frictional hull contacts (E3d1) and prop-strike events (E3d2): planned in M2 |
| Turbine spool model (AV-05a); the Avanti flies (AV-07) | ECU states (AV-05b), fuel burn (AV-10, G4a), fire and smoke |
| Deterministic 240 Hz replay, traces, goldens | Crash replay, causal debrief, and crash-specific event rows |
| Particle research for smoke (SM, Compatibility renderer) | Any particle, debris or decal code in `app/` |

**Limits that shape the plan:** contacts are soft springs (a 15 m/s nose-in would sink ≈ 0.6 m into a spring ground), so the flight solver cannot resolve a violent wreck. Keep Godot's default float32 physics downstream of the independent float64 flight simulation: the simulation owns impact decisions and replay, while Godot may present a later wreck. The old 501 µs/tick figure is a pre-H2/H3 baseline, not a current cost. The 2026-10-06 audit's shared-VM runs under concurrent workload measured trimmed / α=15° stalled costs of Stik 408/370, Extra 448/457, P-51 1,256/1,187 and Avanti 412/404 µs/tick. See the [audit measurement context](research/project-audit-2026-10-06/README.md#evidence-ledger) and per-aircraft [Stik](research/project-audit-2026-10-06/evidence/bench-jensen-das-ugly-stik-60.log), [Extra](research/project-audit-2026-10-06/evidence/bench-gp-extra-300s-60.log), [P-51](research/project-audit-2026-10-06/evidence/bench-p51d-mustang-120.log), and [Avanti](research/project-audit-2026-10-06/evidence/bench-sebart-avanti-s-a200-p100rx.log) logs. These exploratory host measurements do not certify a budget or performance on the owner's target hardware; the existing 500 µs target remains provisional until measured there. The renderer is gl_compatibility, and the development VM has no GPU, so visual cost is judged on the owner's machine.

## 2. Architecture in one page

The full architecture remains a proposal in [05](research/crash-damage-investigations/05-architecture-impact-model.md). CR-01 implements only the first diagnostic boundary.

1. **The simulation decides, presentation shows.** The near-term typed snapshot records a detected contact; the existing pause and reset behavior remains. Later presentation reads the record and never writes back into flight state.
2. **The simulation owns the airplane while it is an airplane.** Future C0–C2 damage requires contact response and persistent state. A structural wreck handoff is a later, separately validated boundary; neither behavior is part of CR-01.
3. **Effective mass ranks rigid-body contact response:** e = ½·m_eff·v_n², with m_eff = 1/(1/m + (r×n)ᵀI⁻¹(r×n)). The [CR-00 results](../research/crash-damage/cr-00/results.txt) show how the current inventories distribute that response by contact location. This calculation does not establish a material failure threshold, restitution, or structural realism.
4. **A structure resolver is future work.** Do not accept thresholds or implement the energy cascade until CR-07 has acquired the missing material/structure evidence (report 03; see the [research index](research/crash-damage-investigations/README.md)) and states its limits.
5. **Persistent damage has state and mass prerequisites.** H8 must define replayable persistent state before damage flags or failures are added. CR-13 must use the shared mass-update semantics established by G4b.
6. **Durability is a later multiplier**, usable only after evidence-backed thresholds exist; it is never a substitute for threshold evidence.

**Outcome classes:** C0 contact · C1 scrape · C2 damaged, still flying or rolling · C3 structural crash · C4 destroyed ([proposed table](research/crash-damage-investigations/05-architecture-impact-model.md#outcome-classes)). These are a future vocabulary, not CR-01 acceptance claims.

## 3. Phases and where they sit in the main roadmap

| Phase | What the player gets | Sits | Needs first |
| --- | --- | --- | --- |
| **CR-A** Impact diagnostics | First triggering contact, impact-pose freeze, and a concise factual cause with available kinematics | **Now, bounded to CR-01**; may proceed as a small diagnostic alongside Gate 2 | Existing detector; labelled contact data where available |
| **CR-A extensions** Presentation and wreck | Crash audio, engine rundown, particles, marks, moving wreck, extended report | Revisit after Gate 2 records pilot priorities and E3d contact semantics are settled; no “Now” commitment | CR-01; Gate 2 priority; relevant contact and render interfaces |
| **CR-B** Breakable airplane | Sections fail according to sourced, uncertainty-bounded material and joint evidence | After CR-01, contact foundations and CR-07 threshold research; schedule at a later owner-prioritized gate | Model teams' section groups; report 03 acquired under CR-07; E3d1/E3d2 |
| **CR-C** Damage you fly with | Scrapes, gear loss, prop strikes, lost tips and surfaces that keep the airplane flying or rolling, with physical aero, mass and engine effects | **M2 → M2+**, after E3d1/E3d2 and state/mass prerequisites; absorbs ROADMAP E7b | E3d1, E3d2, D11d, **H8 required for persistent damage**, **G4b required for any part-loss mass change** |
| **CR-D** Terrain, trees, fragments | Crashes on slopes and into trees (lodged in a crown), fragmentation for violent impacts, a debris field that stays | **M2+** with LANDSCAPE L12–L14 and E6b/E6c | L12a sampler, L14 obstacles |
| **CR-E** Fuel, turbines, fire | The turbine winds down after the ECU cuts fuel; gas and glow engines die their own ways; kerosene fire and smoke only when a tank ruptured with fuel left | **M4**, with AV-05b, AV-10/G4a and SM-00 | ECU states, fuel state, particle backend |
| **CR-F** Presentation | Instant replay from any camera, slow motion, an extended teaching report, honest camera rules, mixed and propagated crash audio, the durability setting | Revisit after Gate 2; replay depends on CR-04 and H8 trace/checkpoint semantics; audio polish with G3; settings with UI-07/08 | H8, G3a/G3d, UI-07/08, PERC; other prerequisites per step |
| **Gate CR** | The owner judges structural plausibility and damaged-flight feel | After CR-B, again after CR-C; distinct from Gate 2's product-priority decision | — |

Only CR-01 is the near-term crash deliverable. Its technical acceptance does not authorize the larger CR-A bundle: at Gate 2, the owner explicitly records whether crash presentation is a priority; schedule CR-02–CR-05 only if that feedback supports the work and E3d contact semantics are ready. Gate CR judges later structural plausibility and damaged-flight feel; it does not replace Gate 2. The other rows are researched options, not a commitment to build every crash effect. Recheck need, dependency readiness, evidence quality and target-machine cost at the gates before scheduling them.

## 4. Steps

Columns follow [docs/README.md](README.md#conventions-for-documents): ID, step, proof, dependencies, status. Every step also reports µs/tick or frame time where it adds cost, keeps goldens and `--trace` rows byte-identical unless it says otherwise, and adds a LEARNINGS entry. "Owner" names the team that builds it.

### CR-A — Impact diagnostics (bounded near-term scope)

| | |
| --- | --- |
| Objective | Replace the buried tick-end image with an impact-pose snapshot and a concise, factual contact cause while preserving current flight, pause and reset behavior |
| Systems | Existing crash detection (`FlightSession`), a small typed impact snapshot, labels for the reference aircraft's hull points, and the existing crash/pause readout |
| Approach | On an existing crash trigger, record one deterministic snapshot: tick, trigger kind (`hull_contact` or `gear_limit`), component id when known, crossing fraction/pose when derivable, and available contact kinematics. Use 64-bit scalar/packed-array values at the simulation boundary. Report unavailable data as unknown. Do not infer pilot error or structural failure. |
| Files | `app/sim/flight_session.gd`, a small pure snapshot builder under `app/physics/` only if needed, reference-aircraft labels in the owning data/generator path, existing crash readout, focused crash tests |
| Validation | Hand-computed hull and gear-trigger cases; exact linear crossing fraction; finite typed fields or explicit unknowns; readable text matches the typed cause; the rendered pose is at the crossing; undamaged trace rows, goldens and existing 1.5 s restart stay unchanged |
| Performance risks | Snapshot construction runs only after a crash trigger; measure it and confirm no new per-tick work in ordinary flight. Target-hardware cost remains unmeasured. |
| Read first | [05](research/crash-damage-investigations/05-architecture-impact-model.md), [04](research/crash-damage-investigations/04-audio-presentation-feel.md), and the [research index](research/crash-damage-investigations/README.md) |


| ID | Step | Proof | Depends on · owner | Status |
| --- | --- | --- | --- | --- |
| CR-00 | Plan, existing research 01/02/04/05, and effective-mass experiment; material-threshold research was not completed and is assigned to CR-07 | `research/crash-damage/cr-00/` reproduces `results.txt`; the research index lists present reports and the pending 03 deliverable without claiming its evidence exists | — · crash track | ✅ 2026-10-06 |
| CR-01 | **Typed impact snapshot and readable cause.** Keep the current trigger paths and reset. On hull contact, identify the earliest crossed labelled point within the detected tick and capture its crossing fraction, pose, point velocity and flat-ground normal if finite. On a gear-limit trigger, capture the trigger kind and leg id if available; use unknown for data the current model cannot support. Show a concise direct cause, such as “Airframe contact: left wingtip, 7.4 m/s at contact” or “Landing gear travel limit”; do not diagnose a stall or claim a structural failure. No effective-mass/energy calculation, resolver, event sidecar, new sound, particles, ground marks, wreck, or expanded crash report in this step | Hand-computed wingtip, nose and belly crossings plus a gear-limit case; exact fraction for linear descent; first-point selection is deterministic for ties; snapshot values are finite or explicitly unknown; readout reflects the typed cause; impact pose is captured; ordinary-flight trace rows and goldens and existing restart behavior stay unchanged | — · physics line (data/model owners add required point labels through their owned paths) | Partial: CR-01a/b verified; component labels, crossing-time kinematics and rendered crossing pose remain open |
| CR-01a | Typed tick-boundary diagnostic through the existing crash detector/readout: first hull point in data order or first over-travel gear name, owned state and hull rigid-point velocity; gear velocity explicitly unavailable. No sub-tick or structural claim | 42 focused checks; full isolated `app/test.sh` (133 sections); three mutations rejected; four unchanged three-second traces; crash-only snapshot medians 35–39 µs on shared host. [Evidence](research/crash-damage-investigations/CR-01a/README.md) | Existing detector · physics line | ✅ 2026-10-07 · Codex impact-diagnostics agent |
| CR-01b | Reconstruct earliest hull-plane crossing along the existing position-lerp/shortest-nlerp pose path; preserve detected snapshot separately and return explicit unknowns for pre-existing contact or ambiguous roots | 40 crossing + 42 snapshot checks; four mutations rejected; four unchanged traces; full isolated suite (138 sections, 180 s validation deadline after a baseline-confirmed 60 s timeout); crash-only medians 202–289 µs. [Evidence](research/crash-damage-investigations/CR-01b/README.md) | CR-01a · physics line | ✅ 2026-10-08 · Codex crossing-reconstruction agent |

### Deferred CR-A presentation and wreck work (existing CR-02–CR-05 IDs)

Reconsider these steps only after Gate 2 records the pilot's priorities and the relevant E3d contact semantics are settled. The rows preserve researched options; they are not part of the next delivery, and their estimates must be rechecked when scheduled.

| ID | Step | Proof | Depends on · owner | Status |
| --- | --- | --- | --- | --- |
| CR-02 | **Crash sound v1.** Add delayed impact sound and engine rundown, with licensed assets and deterministic variation. Energy classes and levels remain provisional until an evidenced mapping is justified; the immediate CR-01 cause readout is silent. | Pure selection, level and delay functions unit-tested (onset at t + r/c ± 1 ms at 30/100/150 m); an end-to-end crash plays exactly one impact voice with the expected id; the engine stream is never paused by a crash; a licence check fails on any non-CC0 entry; owner listening note | CR-01, Gate 2 priority, G3 audio interface · crash track | — |
| CR-03 | **Impact you can see.** Add a surface-appropriate dust/turf effect and a scuff mark that stays until restart. Keep the pilot view stable. Do not map particles to structural energy before that quantity has accepted evidence. | `capture.sh` crash case at fixed simulation times (runway and grass); first-crash frame time compared with a later crash; frame time on the owner's machine; normal-flight captures unchanged | CR-01, Gate 2 priority, E3d surface/contact semantics, SM-00 backend decision and landscape mark interface · crash track | — |
| CR-04 | **Wreck handoff.** At a later gate, hand a structurally classified impact to a visual Godot rigid body. Research 05's restitution and friction values are estimates, not accepted contact data; validate a bounded post-impact model before using it. The simulation remains stopped and never reads Godot physics back. | Independent impulse/energy checks under the chosen contact model; a tip hit produces the tested roll direction; effects-on/off flight traces match; menu hold freezes the wreck; reset restores a fresh node tree; capture sequence and target-machine frame time | CR-01, CR-07 threshold evidence, Gate 2 priority, E3d contact semantics; post-impact model evidence · crash track and physics line | — |
| CR-05 | **Extended crash report.** Add lead-up context (stall flag, bank, sink, throttle, last input) from recorded flight history. Keep direct contact facts separate from a labelled causal hypothesis; do not describe correlation as a proven cause. | Scripted tip-stall, vertical nose-in, hard-landing and slow-roll cases; report fields trace to recorded data; UI shows/dismisses; no effect on the flight trace | CR-01, Gate 2 priority, menu track (`app/ui/`) · crash track | — |

### CR-B — Breakable airplane

| | |
| --- | --- |
| Objective | Parts come off where and as hard as the impact says, and the outcome is validated against real crashes |
| Systems | Aircraft data (`structure`), loader, visual builders (sections), new `physics/structure.gd`, wreck presenter, audio and particles |
| Approach | Logical sections may own inventory items, hull points and joints once source-backed limits exist. CR-07 first obtains material/joint threshold evidence; only then may a resolver use those values. Presentation and any secondary visual contacts remain downstream. |
| Files | `app/physics/structure.gd`, `app/physics/aircraft_data.gd` (optional section), `app/data/aircraft/jensen_ugly_stik_60.json`, generators `research/*/derive_physics.py`, `app/aircraft/*_model.gd` + `verify_*.gd` (sections), `app/render/crash/{breakup,debris}.gd`, `research/crash-damage/cr-08/` |
| Validation | Source and uncertainty review for every threshold; five-situation scenario test; CR-08 as supplemental outcome evidence; Gate CR (1) |
| Performance risks | Body count after a C4 crash; convex shapes from procedural meshes; voice count in a many-break crash |
| Read first | [Research index](research/crash-damage-investigations/README.md) (report 03 is pending under CR-07), [01](research/crash-damage-investigations/01-simulators-games-damage-models.md), [02](research/crash-damage-investigations/02-godot-destruction-techniques.md) |


| ID | Step | Proof | Depends on · owner | Status |
| --- | --- | --- | --- | --- |
| CR-06 | **Visual sections contract.** Every builder returns `sections: { id: Node3D }`: wing halves (or panels), fuselage front and rear, stab halves, fin, canopy or hatch, cowl, engine with propeller, each gear leg. Break along these named parts, never by runtime cutting. Hinges stay inside their section; node names `airplane`, `propeller` and `*_hinge` stay unchanged (the P-51's single `wing` node needs splitting into halves). Convex hulls, if used, are computed at load without simplification (0.4–4.7 ms; simplified hulls cost 100–140 ms). A build without sections is one section, so the generic CR-04 handoff can remain possible | Each `verify_*.gd` checks that every mesh belongs to exactly one section and that the ids match the data; captures byte-identical (grouping only) | — · each model team (Stik first), after Gate 2 prioritization | — |
| CR-07 | **Threshold evidence, structure data and resolver.** First acquire missing report 03 under this existing ID: traceable material/joint impact evidence, aircraft construction details, applicable test conditions, source quality, and uncertainty/range for each candidate threshold. If evidence is insufficient, record the gap and leave that failure mode unmodelled; do not fill the schema with guessed values. Only after this evidence review may an optional `structure` section in aircraft data and a pure `physics/structure.gd` resolver be implemented. Sections can name parent, material, inventory items, hull points and joints; the loader rejects unknown or double-claimed items. Every accepted threshold carries `{value, unit, kind, source}` and an uncertainty note. A durability setting and energy cascade are downstream of accepted data, not a substitute for it. | CR-07 research output contains sources, construction applicability, measured/derived ranges, uncertainty and explicit non-results; a reviewer can trace every threshold to evidence. Resolver acceptance then uses five situations and mutations, but no numeric material-strength claim is made from CR-00 effective-mass results or CR-08 videos alone; loader refusals are tested | CR-01 and Gate 2 priority for research; E3d contact semantics before resolver integration · crash track and relevant aircraft/physics owners | — |
| CR-08 | **Reference crash set (supplemental outcome evidence).** 15–20 public RC crash videos (links only), each with visible first component, estimated impact speed/angle and observed outcome. Record frame rate, scale reference, ambiguity and uncertainty. Use the set to challenge outcome classes and identify missing scenarios, not as a replacement for material/joint threshold evidence. | Publish the observations, exclusions and uncertainty; explain disagreements. Any future class-agreement target is set only after the sample and threshold evidence are reviewed, and misses are listed rather than tuned away (rule 10) | CR-07 · crash track | — |
| CR-09 | **Visual breakup.** At C3/C4 the wreck splits along the resolver's broken joints: each detached section becomes its own body with v + ω × r, mass and inertia from its inventory share. Secondary Godot contacts feed the same resolver (presentation only). Pieces stay until restart, within a body budget | Captures of the five situations show different breakups; bodies ≤ budget; frame time on the owner's machine; trace rows unchanged | CR-04, CR-06, CR-07 · crash track | — |
| CR-10 | **Material sounds and particles.** Material × surface matrix (balsa and ply crack, foam crunch, composite shatter, metal clank; runway, mown, rough, later tree), one voice per break event, scrape loops for a sliding wreck, splinters, foam crumbs or glass-fibre shards by material | Selection table unit-tested (every pair has a sound or a declared fallback); voice limit holds in a 20-break crash; owner A/B note | CR-02, CR-09 · crash track | — |
| **Gate CR (1)** | **Does a crash look, sound and break plausibly?** The owner watches and flies the five situations on the Stik and one other aircraft, rating each −2 (too fragile) … +2 (too tough) and its readability | Record ratings as outcome and usability evidence. An out-of-band rating triggers review; change `absorb_energy` only when CR-07 evidence or a demonstrated model/data error supports it. Otherwise preserve the threshold and record the mismatch or revise presentation/scope. Owner feel alone cannot establish or tune physical strength values. | CR-05, CR-07 evidence, CR-09, CR-10 · owner | — |

### CR-C — Damage you fly with (M2 → M2+)

| | |
| --- | --- |
| Objective | After contact, state and mass semantics are settled, implement only evidence-backed damage that leaves the airplane flying or rolling |
| Systems | Hull contacts (E3d1), prop strike (E3d2), aero strips and tail surfaces, H8 persistent state, G4b shared mass semantics, propulsion states, servo stage, trace |
| Approach | No persistent damage before H8. E3d can first validate non-damaging contact behavior. Later damage changes are discrete `pre_step` state updates; part loss uses G4b's shared mass-property update and is re-referenced to the new CG. |
| Files | `app/sim/flight_session.gd`, `app/physics/{structure,aero,dynamics,ground_contact,propulsion}.gd`, a shared `mass_properties` function, `app/tests/test_crash_damage.gd`, `app/tests/golden/` (unchanged) |
| Validation | E3d1/E3d2 proofs, H8 state/replay proof, G4b shared mass-property proof, E7b strip-removal check, velocity-field continuity, scripted "fly home damaged" maneuvers, Gate CR (2) |
| Performance risks | Damage terms must cost nothing when undamaged; measure the current representative aircraft and stalled cases after Phase H on the intended target hardware before setting a budget |
| Read first | [05 §Damage back into the flight](research/crash-damage-investigations/05-architecture-impact-model.md#damage-back-into-the-flight-c2), knowledge base [04](research/roadmap-investigations/04-ground-handling-collisions.md), [02](research/roadmap-investigations/02-aerodynamics-rc-scale.md), [01](research/roadmap-investigations/01-numerics-architecture-performance.md) |


| ID | Step | Proof | Depends on · owner | Status |
| --- | --- | --- | --- | --- |
| CR-11 | **Continue after C0–C1.** E3d1's frictional hull contacts own nondamaging touch and scrape behavior. Persistent C2 damage is explicitly deferred until H8 and the applicable CR-07 evidence are complete. | E3d1 anchors pass (tip at walking pace rocks back; nose-in at 10 m/s crashes; belly at 1 m/s slides); C0/C1 cases continue or end according to the contact model; no persistent state is introduced | E3d1, CR-01 · physics line | — |
| CR-12 | **Gear and propeller damage.** After H8, a leg past its evidence-backed force/travel limit leaves the contact list; a prop strike (E3d2) changes thrust and engine state according to the accepted model. Any detached mass uses G4b's shared update semantics. | Hard-landing scenario: gear state and belly slide match the model; prop-strike state changes on the next tick; with G2a the unloaded rpm response matches shaft balance; replay reproduces the state; goldens unchanged without damage | H8, E3d2, G4b for detached-mass changes, CR-07 evidence for any failure limit · physics line | — |
| CR-13 | **Part loss with aero and mass feedback** (absorbs ROADMAP E7b): wingtip or outer panel, stab half, elevator or rudder, canopy, hatch, cowl. Strips or surfaces are removed; G4b's shared semantics recompute mass, CG and inertia from inventory; state is re-referenced to the new CG with a continuous velocity field. | E7b proof (lost-tip roll moment equals strip removal in `linearize.gd`); surviving-point velocity is continuous across separation to 1e-12; G4b mass properties match inventory without removed items to 1e-12; scripted damaged return remains controllable with computed trim | H8, D11d, CR-11, G4b shared update · physics line | — |
| CR-14 | **Control-system damage.** After H8 and only for evidence-backed hits, a stripped servo or popped linkage leaves a surface floating or stuck; optional failure injection for training is a separate owner decision. | Unit tests per mode; trace/replay show the persistent surface state; no effect without damage | H8, CR-13 · physics line | — |
| CR-15 | **In-flight structural failure.** After H8 and CR-07 threshold evidence, model a supported load-factor limit per joint; add flutter only if aircraft-specific evidence supports it. | A scripted pull above a sourced limit folds the wing, one below does not; uncertainty and sensitivity are reported; replay and goldens unchanged without failure | H8, CR-07, CR-13 · physics line | — |
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
| Read first | [Research index](research/crash-damage-investigations/README.md) (03 is pending under CR-07), [02](research/crash-damage-investigations/02-godot-destruction-techniques.md) (particles, lights), [SMOKE-PLAN](SMOKE-PLAN.md), [avanti-s-av05-turbine-dynamics](research/avanti-s-av05-turbine-dynamics.md) |


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
| CR-24 | **Instant replay and rewind** (slow motion plays recorded states; `Engine.time_scale` does not slow our simulation). A ring buffer of the last 30 s of simulation rows (≈ 2.3 MB) plus per-frame wreck and debris transforms recorded while they move; replay from the pilot, close-up, orbit or ground camera, slow motion (labelled) and scrub, with crash audio re-rendered from the events for the replay listener. **Rewind and take over:** re-simulate from an H8-defined checkpoint with recorded inputs, then hand the sticks back. This requires complete checkpointed simulation state; read-only cosmetic pose snapshots support viewing but cannot support rewind. | Replayed simulation poses equal the recording exactly; re-simulation reproduces the recorded rows bit for bit up to the handover; wreck replay frame for frame; memory within the budget | H8 checkpoint/replay semantics for complete simulation state, CR-04 · crash track + menu track | — |
| CR-25 | **Crash audio polish.** Own propagation (G3d: travel delay, Doppler, air absorption), debris rattle and settling ticks, the silence after, the turbine spool-down whine, a limiter on the SFX bus | Offline spectra and onset delay tests (G3d's); owner ABX note | G3a, G3d, CR-10 · crash track | — |
| CR-26 | **Camera rules.** Pilot view: no shake, freeze or slow motion; auto-zoom follows the wreck until it settles. Close-up view (today's second camera, fixed to the airplane): a rotational shake ≤ 0.5° only within ≈ 5 m of the impact (estimated). Freeze-frame and slow motion only inside a replay; a ground camera near the impact for replays | Unit test: the pilot camera never shakes or slows; owner rating | CR-04 · crash track + visual track | — |
| CR-27 | **Durability setting, crash log, rumble.** Only after CR-07 has evidence-backed thresholds: expose a realistic or forgiving multiplier in preferences and record it in the trace header; keep per-session contact facts distinct from later causal hypotheses; optional gamepad rumble on first contact only, off by default (a USB radio cannot vibrate) | UI-07 persistence test; header shows the multiplier; replay with a different multiplier is flagged; fake joypad: one rumble call per first contact, none in flight | CR-07 accepted threshold data, UI-07 · menu track + crash track | — |

## 5. Dependencies: what should move earlier or wait

**Do earlier (recommended):**
1. **CR-01 before E3d1.** E3d1 can reuse the reference aircraft's point labels and stable trigger vocabulary. CR-01 remains a diagnostic and does not change contact response.
2. **H8 before every persistent damage state.** This is required, not optional: gear/prop/part/control failures and their replay behavior must use the settled state and trace contract.
3. **G4b shared mass semantics before CR-13.** Part loss must call the same validated mass/CG/inertia update as fuel changes; CR-13 does not define a second mass model or API.
4. **Keep component IDs locally stable and small.** Reconcile them with DATA-8 if that proposal is selected; do not make CR-07 depend on a speculative aircraft-v2 component tree.
5. **SM-00 and CR-03 share one particle-backend decision**, recorded once, when CR-03 is reprioritized.

**Wait (do not pull forward):**
- Fragmentation (CR-18) before CR-07 evidence and CR-08 outcome review: shattering pieces on unsupported thresholds only hides the error.
- Fire (CR-21/22) before fuel state and ECU states exist: a fire without a fuel budget is a guess.
- Godot physics must not own flight-impact decisions or feed its float32 wreck contacts back into the float64 simulation. Keep the authority and replay boundary explicit; a fixed physics tick alone is not the reason.

## 6. Rules specific to this track

1. **No impact, no change:** every CR step keeps goldens and `--trace` rows byte-identical in undamaged flight, and adds no µs/tick there.
2. **Thresholds require evidence before data.** CR-07 must publish report 03 with traceable construction/material evidence and uncertainty before any structural limit is accepted. Effective mass ranks contact response; it is not a break limit. The durability multiplier never rewrites data.
3. **Honest presentation:** sound arrives late, as at the field; no explosions from balsa and glow fuel, no camera shake in the pilot view, no slow motion outside a replay, no fire without fuel and an ignition source, no auto-restart over the aftermath ([04](research/crash-damage-investigations/04-audio-presentation-feel.md)).
4. **Presentation is disposable, the simulation is not:** Godot physics may vary across builds and platforms and is never authoritative for flight outcomes; the float64 snapshot and any later resolver are tested at their own deterministic boundary.
5. **Budgets are measured** on the owner's machine (frame time p95 with the worst crash) before a step is called done. VM numbers are exploratory only.

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
| Structural thresholds lack evidence or dominate perceived fragility | CR-07 must acquire report 03 with uncertainty before limits are accepted; Gate CR ratings and CR-08 video observations supplement, but do not replace, that evidence |
| The visual wreck disagrees with the simulated impact | The handoff starts from the simulation's post-impact state; captures check direction of tumble |
| Frame spikes on the first crash (shader and material compilation) | Pre-warm crash materials and particles at load ([02](research/crash-damage-investigations/02-godot-destruction-techniques.md)); measure the first crash separately |
| Model teams' builders diverge in section names | One contract (CR-06), checked by each `verify_*.gd`, ids from the data |
| Physics budget | CR-01 does snapshot work only after an existing crash trigger; later persistent-damage costs require post-H8 profiling across the catalog. Audit VM readings, especially the P-51 outlier, are linked under §1 and are not target-machine certification. |
| Sound licences | CC0 or own recordings only, `sources.json` with hashes |
