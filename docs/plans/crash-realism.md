# Crash realism plan: causes, proportional outcomes, fire and cost

**Date:** 2026-10-13. **Status:** decisions D1–D5 taken; CR-08b, CR-01d and CR-09b implemented ([CR-08b](../research/crash-damage-investigations/CR-08b/README.md), [CR-01d](../research/crash-damage-investigations/CR-01d/README.md), [CR-09b](../research/crash-damage-investigations/CR-09b/README.md)); soft hull contacts ([E3d1](../research/crash-damage-investigations/E3d1/README.md)) implemented at the owner's request; CR-03b/CR-02b effects and sound ([evidence](../research/crash-damage-investigations/CR-03b/README.md)) and CR-01e causes ([evidence](../research/crash-damage-investigations/CR-01e/README.md)) implemented; CR-22b energy sources, CR-09c real-part breakup for imported models (with TT-13c for the Turbo Lumber Evolution) and the CPU part of CR-22c implemented ([CR-22b](../research/crash-damage-investigations/CR-22b/README.md), [CR-09c](../research/crash-damage-investigations/CR-09c/README.md), [CR-22c](../research/crash-damage-investigations/CR-22c/README.md)). Open: rendered cost and captures on the owner's host, distance LOD, continuous post-terminal wreck-slide audio, owner review of the Turbo Lumber Evolution section overlay. **Prefix:** CR- (new slices of existing crash steps; see the [registry](../README.md#tracks-plans-and-step-ids)). **Parent:** [CRASH-DAMAGE-PLAN](../CRASH-DAMAGE-PLAN.md). When this plan is complete, consolidate it into the parent plan and delete this file.
**Owner:** crash track. **Owns:** `app/render/crash/`, `app/tests/test_crash_*.gd`, `docs/research/crash-damage-investigations/`, `research/crash-damage/`.

**2026-10-14 cost follow-up:** [CR-22c-R1](../research/crash-damage-investigations/CR-22c-R1/README.md) implements prepared BVH scuff queries, Compatibility shader warmup and selective emitter startup, with native ground-impact evidence across all eight airplane configurations. The earlier pre-warm action is implemented; residual frame spikes, the full class/distance matrix, LOD and visual acceptance remain open.

**2026-10-14 repeated-work follow-up:** [CR-22c-R2](../research/crash-damage-investigations/CR-22c-R2/README.md) consumes soft-contact feedback once per tick, suppresses it during holds, caches unchanged wreck shadow projections and caches scenery sort distances. This prevents duplicate touch sounds. Later GP-19 work supplies accepted live-hull scrape grains; continuous post-terminal wreck-slide audio remains separate work.
**2026-10-25 contact follow-up (physics line):** [GP-07](../research/ground-physics/GP-07/README.md) replaces the Stik's 8 sparse hull points with 26 generated from the drawn model (closing the E3d1 "edge between points passes through the ground" limit for the Stik), sets airframe friction per field surface for soft contacts, and makes crash presentation treat the runway strip as turf (`severity.gd`, `effects.gd`, `crash_audio.gd`, `airframe_scuffs.gd`; paving cases now use `asphalt`).
**Coordinated, not owned:** `app/physics/impact_snapshot.gd` (physics), `app/sim/scenery_collision.gd` (landscape LU-05), `app/sim/flight_session.gd` and `app/main.gd` (main line), aircraft data and generators (model owners, [AIRCRAFT_CONTRACT](../AIRCRAFT_CONTRACT.md)).

Goal: a crash looks and sounds like what hit, how hard and why. Contact can produce a near miss, a brief touch, sustained scraping, local damage or terminal escalation according to §9's evidence and continuation rules. Fire requires a supported or explicitly estimated source/rupture/ignition policy. Nothing explodes by default. Effects cost scales with the event and its visibility. The twenty research investigations in §10 extend this direction without enabling new runtime behavior.

## 1. Historical baseline: code on 13 October 2026

The values below were read from the code on 2026-10-13. They are retained as the motivation for the delivered slices, not a description of current HEAD. In particular, F8 predates E3d1; GP-07 later expanded Stik hull coverage. The current recoverable-contact audit and implementation contract are in §9.

| # | Finding | Where | Effect |
| --- | --- | --- | --- |
| F1 | Ground hits use the **whole aircraft mass**. Report 05 measured that a wingtip engages 5–7 % of it. Scenery hits already use effective mass. | [director.gd:104](../../app/render/crash/director.gd#L104), [scenery_collision.gd:203](../../app/sim/scenery_collision.gd#L203), [report 05](../research/crash-damage-investigations/05-architecture-impact-model.md) | Light tip and tail contacts are overrated. Ground hits and scenery hits disagree for the same impact. |
| F2 | **Sliding speed counts as impact energy** (×0.15–0.35 of tangential KE). | [severity.gd](../../app/render/crash/severity.gd) `_estimate_core` | A belly slide is graded like a structural crash. |
| F3 | The **class cuts are absolute joules** (1 / 8 / 100 / 2000 J). | [severity.gd:6](../../app/render/crash/severity.gd#L6) | The grade depends on aircraft size. A Stik cannot reach C4 below about 45 m/s on grass. A P-51 belly landing reaches C3. |
| F4 | The **struck component is guessed** from hull-point geometry (span × 0.28, ±chord). Hull points carry no labels. | [director.gd:95](../../app/render/crash/director.gd#L95) | There is no "propeller", "fin" or "canopy" outcome. Prop strikes cannot exist. |
| F5 | **Every crash bursts.** The dust is a one-shot spherical puff (explosiveness 0.94, spread 82°) for every class ≥ C1. Splinters fly out as a random upward fountain. C4 releases every section at t = 0 with an outward push from the core centre. Glow aircraft on asphalt also throw sparks. | [effects.gd:37](../../app/render/crash/effects.gd#L37), [:186](../../app/render/crash/effects.gd#L186), [:200](../../app/render/crash/effects.gd#L200), [wreck.gd:602](../../app/render/crash/wreck.gd#L602), [:745](../../app/render/crash/wreck.gd#L745) | Crashes read as explosions even without fire. Wood and foam airframes do not spark. |
| F6 | **Fire** is limited to a hot turbine with declared kerosene. Fuel is found by matching the inventory name prefix `kerosene +`. | [director.gd:43](../../app/render/crash/director.gd#L43), [:130](../../app/render/crash/director.gd#L130) | The fire rule is correct but fragile. Glow, gasoline and LiPo have no fluid or smoke outcome. |
| F7 | **No cause is recorded.** The crash card shows class, speed, surface and component. | [director.gd:174](../../app/render/crash/director.gd#L174) | The pilot does not learn why the crash happened: stall, spin, dive, hard landing, tree, failsafe or dead stick. |
| F8 | **Every contact ends the flight.** A C0 "Contact" still freezes the flight and restarts it ([DECISIONS 2026-10-05](../DECISIONS.md)). | [flight_session.gd](../../app/sim/flight_session.gd) `touches_ground` | A touch-and-go wingtip brush ends the flight. Fixing this needs E3d1 frictional hull contacts. |
| F9 | **Cost:** all 556 particles are allocated and every emitter restarts on each crash. Splinters update in GDScript for 12 s. There is no distance LOD. Budgets were measured on one Windows host at 720p. | [effects.gd](../../app/render/crash/effects.gd), [CR-22a](../research/crash-damage-investigations/CR-22a/README.md) | A distant C1 costs as much setup as a C4. There is no Linux or low-end data. |

Same cases under the CR-08a estimator and CR-08b as implemented (§3.1; values from `test_crash_proportional.gd`). Inputs: point speeds, the CR-00 effective-mass ratios, surface transfer and a durability factor of 1. The slapdown term is not supplied here; with it the cartwheel entry grades C3.

| Case | CR-08a | CR-08b (ε, class) |
| --- | --- | --- |
| Stik wingtip brush in a low pass (v_n 0.5, v_t 15 m/s, grass) | 38 J → C2 | 0.007 J/kg → C0 |
| Stik firm belly touch (v_n 1.5, v_t 12) | 27 J → C2 | 0.88 J/kg → C1 |
| Stik wingtip, cartwheel entry (v_n 10, v_t 8) | 124 J → C3 | 2.7 J/kg → C2 |
| Stik vertical nose-in, 15 m/s | 254 J → C3 | 88 J/kg → C3 |
| Stik vertical nose-in, 30 m/s | 1014 J → C3 | 351 J/kg → C4 |
| P-51 belly landing (v_n 1, v_t 25, runway) | 1797 J → C3 | 0.45 J/kg → C0, abrasion 12.9 J/kg → C1 |
| P-51 vertical nose-in, 15 m/s | 1887 J → C3 | 88 J/kg → C3 |
| Vantage Jet wingtip on landing (v_n 1, v_t 30, runway) | 1407 J → C3 | 0.03 J/kg → C0, abrasion 1.2 J/kg → C1 |

## 2. Scope

**In scope:** proportional and size-consistent grading, cause analysis, momentum- and material-driven wreck, VFX and audio, a fire and smoke matrix by energy source, and a cost budget.

**Out of scope:**

- Accepted structural strength. CR-07 evidence is still required, and every threshold here stays a labelled estimate.
- Flyable damage (CR-11–15).
- Any change to flight before the first contact. Healthy-flight traces must stay identical and the goldens are not re-recorded.

The existing boundary stays: presentation reads the session and the impact snapshot, and never writes to them.

## 3. Design

### 3.1 Impact measure (CR-08b)

Use one pure float64 function for ground, gear and scenery contacts. Inputs are the body point r, the surface normal n, the point velocity, the mass m and the inertia I.

- **Effective mass:** m_eff = 1 / (1/m + (r×n)ᵀ I⁻¹ (r×n)). Extract the code already in `scenery_collision._event_at` into a shared helper, coordinated with LU-05, so both paths use the same number.
- **Normal channel (breakage):** E_n = ½ m_eff v_n². Grade it on the specific energy ε = E_n / (m · d). d is the aircraft durability factor: default 1.0, source `estimate` (decision D1). Provisional cuts: **C0 ≤ 0.5, C1 ≤ 2.5, C2 ≤ 25, C3 ≤ 150 J/kg, C4 above**. They replaced the joule bins in CR-08b and are not calibrated. Dividing by mass makes the grade independent of aircraft size for similarly built airframes.
- **Slapdown:** a contact off the CG stops only m_eff. The CG's remaining normal energy, (½ m v_cg,n² − E_n) × transfer, reaches the surface through a second contact and is graded on the same cuts. It is an upper bound with body rates ignored. Without it a long-nosed 45° dive (Vantage Jet, m_eff/m = 0.2) graded only C2.
- **Tangential channel (abrasion):** friction work during the impact, μ (m_eff v_n) v_t, capped at ½ m_eff v_t², per kilogram. At ≥ 1 J/kg it raises a contact to C1 at most. It drives marks, scrape audio, prop strikes and gear tear-off, and never drives section breakup. μ values are estimates.
- **Several contacts in one tick:** take the worst normal channel. The wreck's secondary contacts feed the existing `accumulate_damage`, so damage only grows.

### 3.2 Named contact points (CR-01d)

Each `crash_hull` point gets a semantic `component` label: `wing_tip_left`, `spinner`, `propeller`, `fin`, `stab_left`, `canopy`, `belly`, `nose`, `tail_end`. The labels come from each aircraft's generator, never hand edits, and the loader validates them. The geometric guess stays only as a marked fallback. This also closes the CR-01 component-label gap.

Limitation: hull points are sparse (8–14 per aircraft), so a leading edge between two points can contact the ground unlabelled. Report it as `nearest_component` with its distance.

### 3.3 Proportional outcome ladder (CR-09b, CR-03b, CR-02b)

| Class | Breakage | Wreck motion | VFX | Audio | Card |
| --- | --- | --- | --- | --- | --- |
| C0 Touch | none | one body, slides or settles | small scuff, no dust burst | soft thud | "Touch, no damage" |
| C1 Scrape | prop if it strikes while turning; otherwise none | one body | mark along the slide, low spray along the slide direction | scrape held for the slide | "Scrape: <component>" |
| C2 Damage | the struck component only (tip, stab, prop, gear leg) | core plus one part | chips from that part only | crack light, part rattle | "Damaged: <component>" |
| C3 Structural | struck component, then its load-path neighbours (wing half at the root, tail boom) in order of distance from the contact | parts inherit point velocity; release delay grows with distance | debris trail along the momentum; dust is material-driven | crack heavy, tear, debris | "Broken: <list>" |
| C4 Destroyed | every section, still released in order from the contact | momentum-directed; outward push ≤ the existing 12 % / 600 J cap | as C3, denser | full layers | "Destroyed" |

Rules that remove the "always explosion" look:

- Emit at the contact point. Shape the dust as a cone along the reflected slide direction; remove the spherical burst. Particle count follows ε (and the abrasion level for sliding contacts).
- Surface decides the material. Grass throws clippings and turf. Dirt throws dust. Runway throws no dust, only paint, fibreglass or balsa chips. **Sparks** appear only when a metal component (engine, turbine, spinner backplate) slides on a hard surface above about 10 m/s.
- Debris colour and shape come from the aircraft. Sample the struck section's material colour instead of the fixed brown. Construction sets the shape: balsa slivers, fibreglass shards or foam crumbs.
- No section receives a radial impulse from the core centre. Parts keep their point velocity. Any remaining scatter is bounded and points along the momentum.
- Scorch marks only appear with fire. There is no camera shake (kept).

### 3.4 Energy sources: fire, fluid and smoke (CR-22b)

Fire requires all three: an energy source in the inventory, an estimated rupture of its section, and an ignition source. Inventory items get an explicit `energy_source` kind instead of the name match (contract change, D1). A detonation effect does not exist and is not added.

| Source | Outcome | Gate |
| --- | --- | --- |
| Kerosene, turbine hot | fire, smoke drifting with the wind (exists) | rupture estimate, as today |
| Glow fuel (methanol/nitro) | wet fuel stain, no fire | D3 |
| Gasoline, hot exhaust | rare fire, gated by rupture plus engine run time | D3 |
| LiPo pack | damaged pack vents grey or white smoke after 5–30 s; flare only in the worst band | C3+ hit on the battery section; delay is an estimate |
| none | nothing | — |

Before thresholds are set, CR-22b writes a short research note with primary sources (hobby safety bulletins, LiPo abuse tests, incident videos). The note records the uncertainty.

### 3.5 Causes (CR-01e)

A pre-impact ring buffer holds the last 5 s at 20 Hz. It is filled from session state by the director, read-only, and has no effect on the simulation. Each sample keeps airspeed, α, β, bank, pitch, yaw rate, height above ground, sink, throttle, rpm, failsafe flag and gust contribution. At impact, a rule-based classifier returns a primary cause, contributing factors and the numbers behind them. Thresholds come from aircraft data (stall α, gear travel) and are never constants tuned per aircraft.

Rules, in order: radio failsafe → engine stopped or out of fuel (dead stick) → scenery strike (obstacle id) → gear collapse or hard landing (sink against gear travel) → prop strike or nose-over on the ground roll → spin (stalled with high yaw rate) → tip stall (stalled with a fast roll-off) → stall → overspeed or vertical dive → controlled flight into terrain (normal α, descending, low) → unknown.

The crash card shows, for example, "Tip stall at 4 m: α 17°, 8.2 m/s, bank 35° → left wingtip". A log line records the same.

### 3.6 Cost (CR-22c)

- **Proportional setup:** start only the emitters a class uses. Size counts with `amount_ratio` if the pinned Godot 4.7.2 supports it on `CPUParticles3D` (verify first); otherwise use per-class emitter pools. Never re-allocate during a crash.
- **Distance LOD:** scale particle and splinter counts by the crash's projected size from the active camera. The pilot station is often 100–200 m away.
- **First-crash hitch:** pre-warm crash materials and shaders while the flight loads. The 50 ms first-impact budget suggests compilation cost.
- **Per-class budget:** p95 frame and script time per class and distance. Rerun `research/crash-damage/cr-22a/qualify.py` on the owner's Windows host, the reference hardware. The dev VM has no GPU, so it can only check counts and script time.
- **Classifier cost:** buffer write < 5 µs per frame. Classification runs once per crash, < 1 ms.

## 4. Steps

| ID | Work | Proof |
| --- | --- | --- |
| CR-01d | Semantic `crash_hull_components` per hull point, from each aircraft's generator; loader validation | **Done 2026-10-13.** 112 checks incl. geometry consistency on all nine files, 11/11 mutations killed; Turbo Lumber Evolution needs an owner `--check` on its reference machine; [evidence](../research/crash-damage-investigations/CR-01d/README.md) |
| CR-08b | Shared effective-mass helper; normal, slapdown and abrasion channels; J/kg class cuts; durability argument | **Done 2026-10-13.** 49 + 44 focused checks, fleet table, 9/9 mutations killed, scenery parity 1e-12; [evidence](../research/crash-damage-investigations/CR-08b/README.md) |
| E3d1 | Soft hull contacts: spring-damper and friction per hull point; only C2-grade new impacts or deep crushes end an interactive flight; touch marks, puff and scrape | **Done 2026-10-13.** 26 + 10 checks, 13/13 mutations killed, goldens unchanged; [evidence](../research/crash-damage-investigations/E3d1/README.md) |
| CR-01e | Pre-impact buffer, cause classifier, crash card and log line | **Done 2026-10-13:** 29 checks incl. two real production flights, 9/9 mutations killed; per-sample cost not yet measured (CR-22c); [evidence](../research/crash-damage-investigations/CR-01e/README.md) |
| CR-09b | Contact-ordered, momentum-directed breakup; C2 single-part release; no radial scatter | **Done 2026-10-13** (software): 27 checks, 7/7 mutations killed; rendered capture sequence still open; [evidence](../research/crash-damage-investigations/CR-09b/README.md) |
| CR-03b | Directional, surface- and material-aware dust, chips and sparks; counts by ε | **Done 2026-10-13** (software): 39 checks, 9/9 mutations killed; rendered captures on the owner's host still open; [evidence](../research/crash-damage-investigations/CR-03b/README.md) |
| CR-02b | Audio layers mapped to the ladder; scrape held while the wreck slides | **Ladder done 2026-10-13** (pure `layers_for`, tested per class); held scrape during the wreck slide and the native peak capture remain open |
| CR-22b | Energy-source research note; `energy_source` kind; fire, fluid and LiPo smoke matrix | **Done 2026-10-13:** [source review](../research/crash-damage-investigations/CR-22b/research.md), 33 checks, 10/10 mutations killed, kerosene rule unchanged; [evidence](../research/crash-damage-investigations/CR-22b/README.md) |
| CR-09c | Real-part breakup for imported models: `openrc_section` extras, generated section maps for merged meshes, release fallback; TT-13c Turbo Lumber Evolution map | **Done 2026-10-13:** 33 checks, 9/9 mutations killed, overlay captures for owner review; [evidence](../research/crash-damage-investigations/CR-09c/README.md) |
| CR-22c | Emitter pools or ratios, distance LOD, pre-warm, per-class budgets | **CPU part done 2026-10-13** (script-cost table, contact-check early-out, 700-particle budget pinned); rendered p95, pre-warm and LOD open on the owner's host; [evidence](../research/crash-damage-investigations/CR-22c/README.md) |
| CR-09e | Parts by contact (separate gear legs), `tail_boom` section with carried tail, builder meshes in section maps, hidden fracture detail (`crash_reveal`) | **Done 2026-10-13** (Stik): splinters, end grain and spar stubs; [evidence](../research/crash-damage-investigations/CR-09e/README.md) |
| CR-09f | Explicit-only hinged-surface and wheel kinds, `CARRIERS` (attached parts ride with their released section), balsa lining and root ribs, torn CA hinges | **Done 2026-10-13** (Stik): `test_crash_fracture` 24/0, 8/8 mutations killed, breakup contract updated; [evidence](../research/crash-damage-investigations/CR-09e/README.md) |

Order: CR-08b → CR-01d → CR-09b → CR-03b and CR-02b → CR-22b → CR-22c. CR-01e can run in parallel after CR-08b. CR-08b goes first because it needs only hull-point positions, not labels. Each step is a separate commit with its proof.

## 5. Acceptance

- **Software:** the proofs above; four-aircraft healthy-trace parity; existing crash tests updated, never deleted.
- **Owner review:** eight reference captures: the §1 table cases, plus a tree strike and a LiPo hit. The owner judges "proportional and believable" at the pilot station and in the inspection view (picture first, numbers second).
- **Not claimed:** physical validation. Gate CR stays open until CR-07 evidence exists.

## 6. Decisions

The owner delegated these on 2026-10-13 ("you choose"); each took the recommended option.

| ID | Question | Decision |
| --- | --- | --- |
| D1 | Add `durability` and the inventory `energy_source` kind to aircraft data (contract change)? | Yes, with CR-01d through the generators. Default 1.0, `source: estimate`. Until then the estimator takes durability as an argument (default 1.0). |
| D2 | C0/C1 should not end the flight. Wait for E3d1, or add an interim exception? | Superseded 2026-10-13 by the owner ("start working in the soft crash wing tips"): E3d1 soft hull contacts are implemented for interactive flights; scripted, capture and trace routes keep D9d. |
| D3 | Glow and gasoline fire: never, or rare and gated? | Glow never; gasoline rare and gated; LiPo delayed venting. |
| D4 | "Cost" as a repair list: list the broken parts, or put a price on them? | Parts list only. Prices would be invented data. |
| D5 | Where the cause appears: crash card only, or also a flight log? | Card plus a log line now; a log screen later with the menu track. |

## 7. Risks

- Provisional cuts may be mistaken for calibration. Every output keeps `*_is_estimate` and a source basis.
- `main.gd`, the session and the aircraft data are shared. Read `git status` first and stage only this track's paths.
- Changing the bins changes the existing focused-test expectations. Update them in the same step as the reason, and never re-record flight goldens.

## 8. Round 3: analysis and next steps (2026-10-13)

After E3d1, CR-01e, CR-03b, CR-09c and CR-22b, the largest remaining realism gaps, ranked by how often a pilot sees them and how feasible each is now:

| Rank | Gap | Why it matters | Step | Status |
| ---: | --- | --- | --- | --- |
| 1 | A nose-over kept the propeller turning inside the ground | The most common RC mishap; soft contacts made it visible | E3d2 prop strike | **Done** ([evidence](../research/crash-damage-investigations/E3d2/README.md)) |
| 2 | Wreck sections collide as boxes, slide equally on grass and asphalt, and carry fixed mass shares | Tumbling and slide length decide whether a wreck looks real | CR-09d: section masses from the inventory (heavy motor and battery nose), surface-aware friction and bounce, convex shapes from the real section meshes | **CR-09d1 masses and CR-09d2 surface contact done** (wreck CoM on the CG; grass 4.95 m vs concrete 4.17 m slide; [evidence](../research/crash-damage-investigations/CR-09d/README.md)); d3 shapes next, which also unblocks realistic air damping |
| 3 | A fuel fire starts as flames only | Kerosene or gasoline mist ignites as a brief fireball in a hard hit; glow and electric never do | CR-22d ignition flash, gated by CR-22b fire outcomes | **Done** (Roberts-sized flash, renders reviewed; [evidence](../research/crash-damage-investigations/CR-22d/README.md)) |
| 4 | Continuing post-terminal wreck contact lacks its complete held-audio/dust response | A sliding wreck should keep scraping and trailing dust; accepted live-hull scrape grains already exist through GP-19 | CR-02c / CR-03c slide continuity from wreck contact observations | Planned; separate from GP-19 live scraping |
| 5 | Sustained wingtip contact, snagging and cartwheel progression lack a qualified general response | Current new-impact and deep-crush rules can already terminate; duration alone does not establish failure | E3d3 with GP-10/14/16/17; L12 for general terrain | Open; geometry/time/observation work can proceed before general terrain or calibrated damage (§9) |
| 6 | Damage never carries into flight | A lost tip or stab should change handling | CR-11–15 | Waits for H8/G4b/CR-07 |

Order: CR-09d (inventory masses, then surface friction, then convex shapes), CR-22d, CR-02c/CR-03c. Each step is one commit with tests and mutations.

## 9. Recoverable contact and near misses — 19 November 2026

**Status: audited and integrated into the existing work; proposed response extensions are not enabled.** The [nonfatal-contact review](../research/crash-damage-investigations/CR-AUD-2026-11-17/nonfatal-contact-review-2026-11-19.md) and its [verification](../research/crash-damage-investigations/CR-AUD-2026-11-17/nonfatal-contact-verification-2026-11-19.md) pin application source `d736ee8a2eab0b59b0fa2c561a1eef07f5fae396`. This section owns the crash-side acceptance of brushes, scrapes and near misses. The [advanced ground physics plan](advanced-ground-flight-physics.md) remains authoritative for GP-10 support geometry, GP-14 accepted lifecycle, GP-16/17 component work/damage and GP-19 observations/audio. CR-07 and CR-11–15 retain structural and damaged-flight gates. No second damage solver, physics clock or event owner is introduced.

### 9.1 Preserve the implemented foundation

Interactive fixed-wing E3d1 already provides spring/damper/friction hull contact and continuation below its estimated new-impact/deep-crush rules. E3d2 already supplies a nonterminal powered ground-prop strike with engine stop. These are bounded policies, not proof of undamaged components or recovered controllability. Hard scenery, raised track dirt and selected water contacts have different policies; do not describe E3d1 as universal across surfaces or vehicle families.

GP-19d and its follow-ups already collect same-law loaded hull friction at accepted endpoints, bind stable contact/material IDs, preserve short brushes between render frames and play repeated grains through the existing bounded crash pool. The observation explicitly means **instantaneous endpoint power**, not integrated friction work, temperature, wear or fracture. Dry contacts outside actual lake coverage can be observed in a lake-configured field; covered/mixed samples remain outside that collector's scope. Existing scuffs and paced ground marks remain presentation. The [audio plan](../AUDIO-PLAN.md) records later bounded native Stik scrape output; listening, combined Master/fleet coverage and target budgets remain open. CR-02c/03c concern post-terminal wreck continuity.

### 9.2 Outcome contract

| Outcome | Required physical evidence | Continuation and feedback |
| --- | --- | --- |
| True near miss | All relevant physical geometry stays beyond the represented physical/compliant boundary and its declared uncertainty over the accepted interval | No contact impulse, component damage, accident cost, scrape sound or contact mark. Existing flyby sound may continue. Proximity is a separate read-only observation. |
| Vegetation brush | Contact with explicitly authored compliant vegetation, distinct from load-bearing soil | Only the qualified vegetation force/material response and local cue. Rendered grass density, wind animation or graphics quality cannot decide physical contact. |
| Brief solid touch | Actual component/feature contact, relative normal/tangent motion and bounded local response | Continue when the accepted state remains supported. A small scuff or touch cue does not certify structural damage or perfect health. |
| Sustained scrape | Accepted contact duration, slip path and force/work provenance | Friction changes motion and can induce roll/yaw or another contact. Marks/audio follow loading and stop or decay on release. Wear remains unknown until a material-pair rule is qualified. |
| Local damage with continuation | Accepted component/mount transition supported by CR-07/GP-16/17 evidence | Update propulsion/control/aerodynamics and mass properties when affected; expose any substantiated change in authority, without inventing a reduction for a noncritical or unresolved nick. A low presentation class alone cannot authorize this state. |
| Terminal escalation | Qualified loss of supported continuation, or an explicitly versioned conservative fallback | Preserve actual terminal cause and contact identity; use existing terminal presentation. No fatal outcome merely because total speed or proximity is high. |

This ladder is not a mandatory sequence: a prop strike can escalate directly, a wingtip can release and recover, and a shallow contact can snag an edge and induce a later severe impact. A nonterminal tick is not a demonstrated recovery. Recovery qualification must specify a post-contact maneuver/command, a declared follow-on interval and an observable supported end state. Check airspeed/energy, attitude/rates, altitude/clearance and configuration against the admitted model domain for the chosen sustained flight or landing, with secondary contacts accounted for. Finite dynamics or a responding control alone can still describe an unrecoverable descent; a simulation witness is not real-world recovery certification.

### 9.3 Contact geometry and timing before severity

Use point velocity `v_point = v_reference + omega × r`, expressing all terms in one frame, and subtract the other body's actual contact velocity. The kinematic arm runs from the chosen velocity reference to the contact; the effective-mass/impulse arm runs from the live CG to the contact, with inertia about that CG. Separate positive normal closing speed, tangential slip and component spin. For two supported dynamic bodies, effective mass includes both masses and inertias; a parked-aircraft proxy is not proof of aircraft-to-aircraft momentum exchange.

At 300 km/h, a reference point travels about 0.3472 m per 240 Hz tick. A continuous 1 mm positive gap to an ideal static plane is no collision. A 1° downward path at that speed closes the same gap in about 0.688 ms. Those arithmetic scales are not an aircraft speed clearance or survival qualification. Test whole-interval hull/edge, prop/rotor, gear and object coverage within the installed model's domain. Explicitly separate the represented compliant-contact envelope from candidate-search padding and numerical uncertainty. A proven near miss clears the physical/compliant boundary plus its admitted uncertainty; inside an unresolved tolerance band, report a bounded/unknown result or use the explicitly qualified contact law, rather than claim precision the geometry does not supply.

Keep conservative expansion for candidate discovery. Before committing an impact/impulse/damage cue, refine the actual swept feature against the uninflated physical geometry or return a bounded unresolved result. The audit's rotating-point counterexample is a direct component witness, not a complete-aircraft flight. Do not fix it by simply deleting conservative bounds and reopening tunneling. The current earliest-anchored tie rules belong separately to the scenery and lake queries; the session has its own ground/scenery/lake/raised-dirt precedence and unresolved-order refusal. Preserve each contract and witness identity while qualifying any explicit change; do not assume a global common anchor.

For a nonterminal hit at fraction `f`, either integrate the remaining `(1-f)*dt` with the accepted response and requery, or define and verify another explicit time-consistent method. The current scenery path can return the contact-time body with an end-of-tick clock. A positional separation is a stabilization choice, not material deformation; bound its displacement and energy effect. Bound iterations, event count and minimum progress; on exhaustion, use an explicit existing fault/unsupported policy rather than silently dropping time, contacts or physical work. Any new solver identity belongs in configuration, checkpoints and replay/native admission.

### 9.4 Duration, rubbing and progressive damage

An impact estimate and a scrape history answer different questions. Normal incident energy can remain a diagnostic; it is not a material failure law. For supported solid-contact episodes, retain normal impulse, tangent impulse, slip distance and duration, and obtain dissipative friction work from accepted solver pieces: `W_f = integral(-F_t dot v_t_relative) dt`. Define the frame and external-work terms. Endpoint power times a full tick is only an explicitly labeled approximation and can miss an entire brief contact.

Sum each accepted solver-piece work increment once per physical patch/episode. Do not duplicate it per renderer, hull sample or rejected RK stage. Refine or coalesce generated probes with a shared force/work budget so adding mesh detail cannot multiply strength, friction or damage. Start with a bounded per-component receipt and deterministic entry/persistence/release/recontact rules. GP-14 owns incident counting independently of pause. CR-40 consumes its admitted evidence; a near miss never creates repair cost, and an unknown water/prop exposure never becomes an invented zero or total-loss amount.

Evaluate abrasion against material pair, contact area/pressure, construction and measured uncertainty. Keep coating scuffs, local deformation, structural weakening and detachment separate. The older CR-08 impulse-times-slip abrasion proxy is not GP-19 measured integrated work; it cannot silently become a physical wear budget. The historical E3d3 speed-duration cartwheel heuristic remains an estimate to challenge. Actual snag torque, loss of support, attitude evolution and subsequent contacts must justify escalation.

### 9.5 Propeller/rotor and water branches

**Propellers and rotors.** First close the existing CR-AUD-03 source-off rotating-disc gap and CR-AUD-24 variable-terrain rim coverage, preserving coupled shaft/source state. The current powered ground guard uses a 300 rpm estimate and positive sampled depth; even micrometre penetration has its binary strike response. It does not qualify partial nicks or safe penetration. Ground-strike payload reference velocity is also insufficient as blade-contact velocity. A component model needs translation, body rotation, shaft rotation, strike radius, target response and mount/shaft work. Distinguish running, coasting, windmilling and truly stopped blades. If blade phase/shape is unavailable, disclose envelope conservatism; do not infer a stopped-phase hit or miss. Partial blade loss/imbalance requires qualified shaft, vibration, thrust and retained-mass changes, with explicit unsupported outcomes outside that scope. Helicopter main/tail rotors and quad props need their own adapters and controls.

**Brief water contact.** Current selected fixed-wing water events are terminal, including calm-water tangency. Introduce a versioned transient-water response only with a defined wet feature, penetration/wetted-area evolution, duration, hydrodynamic impulse/drag and continuation domain. Wingtip, prop, wheel and fuselage entries are different cases. A shallow, fast leading edge can create a large local load; depth or total speed alone cannot grade it. Separate the time-dependent interface gap derivative from modeled fluid-particle velocity/current. A rising wave can contact a stationary body and transfer work; static-ground energy checks must account for that boundary work.

Nonterminal wet cues must not call terminal water aftermath, hide the aircraft, end the incident twice or manufacture fracture. Update typed contact events and all checkpoint/replay/economics/presentation consumers together; changing `terminal` alone is insufficient. Sustained floats, boats, hydrostatic support/righting, planing and buoyancy remain separately authored capabilities. Full-scale water-entry literature informs mechanisms, not unvalidated RC thresholds.

### 9.6 Existing owners and implementation order

| Priority and existing IDs | Concrete slice | Evidence needed to advance |
| --- | --- | --- |
| First — E3d3, GP-07/10, CR-01; LU/SF/session coordination | Exact contact admission, point/surface kinematics, selected witness, bounded remaining-time handling; retain current ordering fixes and older geometry regressions | Whole-interval clear and penetrating controls, low normal/high tangential speed, rotation, thin targets, no-event state parity, multipoint order, explicit exhaustion, replay/rollback. |
| Next — E3d3, GP-14/19, CR-02/03/08 | Accepted scrape episode and work provenance, local cues, release and recontact; reuse current observation/audio pools | Sub-tick brush, sustained slide, unloaded silence, duplicate/render-rate invariance, observer on/off state identity, one incident and bounded receipt cost. |
| Then — E3d2/3, GP-16/17, CR-07/20 with propulsion/rotor owners | Powered/coasting/stopped coverage and qualified local prop/rotor response | Matched actual shaft-state controls, disc/phase declaration, terrain and target geometry, normal/tangent/spin accounting, reset/replay and explicit continuation limits. |
| Separate staged slice — E3d3, GP-10/14/16/17 with lake owner | Transient water contact and wet feedback | Calm and moving-water clearance/touch controls, wave interface rate, independently bounded hydrodynamic response, defined release/recovery and terminal positive controls. |
| After evidence — GP-16/17/18, CR-07 and CR-11–15 | Progressive wear, physical component damage, snag/cartwheel escalation and supported damaged flight | Material/joint uncertainty, work sharing, mass/inertia and momentum partition, aero/control/propulsion effects and continued-contact qualification. |

General terrain still coordinates with L12; fixed-plane admission, time accounting and observation tests need not wait for it. Do not enable a new policy across vehicles by changing a shared threshold. The helicopter nonterminal scenery adapter (CR-AUD-02), quad/blimp lake composition (CR-AUD-01), quad disc/impulse boundaries (CR-AUD-21/25), car scenery support (CR-AUD-14) and aircraft gear/scenery gap (CR-AUD-27) remain separately evidenced prerequisites. Bodies, rotors, skids/wheels and people/parked vehicles require honest capability declarations.

### 9.7 Qualification matrix and efficiency

Use matched cases, not a full Cartesian product. Within each admitted vehicle/model domain, vary tangent speed independently of normal approach (including 0, 15, 41.67 and 83.33 m/s as appropriate), roll/pitch/yaw rate, incidence direction, clear/tangent/penetrating geometry, contact duration and release/recontact. Include left/right wingtip, leading/trailing edge, belly/tail, extended/partial/retracted gear and prop/rotor. Use numerical gaps on both sides of the declared error bound; a 1 mm test does not itself prove 1 mm fleet accuracy.

Cover static flat ground, slope/edge, hard obstacle, breakable vegetation, separately authored grass canopy, calm water and rising/receding waves. Repeat representative cases through source-on/off, live mass/fuel, reset, checkpoint/replay, rejected candidates and existing native/reference admission where affected. Prove correct physical impulses/continuation separately from scuffs/audio, accounting, and full-aircraft visual clearance. Human review uses pilot and inspection views to assess whether a mild contact reads as mild and a release reads as release.

Retain immutable prepared geometry, current spatial bins and cheap proven-clear rejection. Subdivide adaptively near candidate contact using translation, rotation, curvature and time bounds; do not globally raise 240 Hz to chase millimetres. Reuse buffers and stable IDs; cap candidate/iteration/episode/queue sizes with disclosed overflow. Physics and damage must not change with camera distance or graphics settings; only presentation density/LOD may scale. Measure paired no-contact, first-contact, sustained scrape and many-contact cases on target hardware, including p95/p99 tick/frame time, allocations, broad/narrow candidates and exhaustion counts. Headless check duration is not a frame-rate benchmark. Keep stock activation, structural validation and performance acceptance as separate gates.

## 10. Research integration: twenty investigations — 19 November 2026

**Status: research integrated; proposed increments are not implemented.** The [twenty-investigation report](../research/crash-damage-investigations/CR-AUD-2026-11-17/crash-inspiration-20-2026-11-19.md) reviews application `a866d880d8edbe84d2c59780624c35c8c7f107fc`, with [43 primary-source reference records](../research/crash-damage-investigations/CR-AUD-2026-11-17/crash-inspiration-sources-2026-11-19.json) and explicit source/transfer limits. It compares experiments, manufacturer construction, destruction algorithms, contact models, particle techniques and audio with existing code. The numbering below identifies research questions, not new step IDs. §9 remains the nonfatal acceptance contract; the [GP plan](advanced-ground-flight-physics.md), [smoke plan](smoke-system-overhaul.md), [audio plan](../AUDIO-PLAN.md) and existing CR owners retain implementation authority.

### 10.1 Selected additions and existing owners

| Research | Concrete addition to investigate | Existing owner and prerequisite |
| --- | --- | --- |
| 01 — Continuous grazing | Prepared conservative sweep followed by bounded physical-feature refinement; detect interior entry/exit with clear endpoints and retain remaining-tick motion | E3d3, GP-08/10/14, CR-01; preserve scenery/lake/session ordering and CR-AUD-31/32 controls |
| 02 — Contact patches | Stable bounded witnesses, then optional force/moment distribution over a qualified patch; one force/work budget | GP-10/14/16/19 with GP-12 coordination; GP-21 owns optional patch refinement, which is not a prerequisite for exact admission |
| 03 — Rebound and dissipation | Component/geometry/material response cards; separate elastic release, actual dissipation and stabilization | GP-11/12 and E3d1/3; CR-09d3 for the separate visual wreck. Reuse potential/damper work and avoid stacking restitution |
| 04 — Water skim | One authored transient wet-feature model with entry, release/recontact and localized wet cues | E3d3, GP-10/14/16/17 and lake owner; CR-AUD-33/34, explicit flow/geometry domain and recovery gates |
| 05 — Prop/rotor strike | Phase-aware where supported, spin-aware local kinematics, finite shaft work and tangential fragment birth | E3d2/3, GP-16/17/18, CR-20 and rotor/propulsion owners; CR-AUD-03/21/24/25 and admitted shaft state |
| 06 — Attachment topology | Small authored bond graph with stable IDs, alternative connections and deterministic separated sets | CR-06/07, GP-16/17; connectivity is not a stress law, rigid grouping or proof of flyability |
| 07 — Material failure modes | Construction-specific grain, foam/core, layup/interface and test evidence; outcome-driven fracture visuals | CR-07 with aircraft generators; coordinate CR-33a measurements without making economics the physical authority |
| 08 — Gradual attached response | Opt-in reversible deflection/permanent-set/damaged constitutive trial with accepted-only persistent mutation | GP-16/17 and CR-07/11–15; extends experimental fixed-hub failed-attached work, not stock activation |
| 09 — Consistent fragment birth | Atomic visual mass/COM/inertia/shape ownership at delayed release; separately timed authoritative detachment | CR-09 and CR-AUD-06/07/08; GP-18 plus agreed shared topology contract for actual flight continuation |
| 10 — Partial connections and seams | Explicit rigid/hinged/tethered/separate visual state, paired interior reveals and correct local anchors | CR-06/09, extending delivered CR-09e/f; physical load-bearing connections separately require GP-17/18 and CR-11–15 |
| 11 — Fragment motion | Bounded optional film/chip/foam/heavy-part aero archetypes using relative wind and stable IDs | CR-03/09/22c after 12; coefficients remain visual estimates, not new flight forces |
| 12 — Support and settling | Prepared simple/convex proxies, support-aware chip rest and qualified terrain/secondary contacts | CR-09d3/19 and CR-AUD-05/09–11; qualify support before reducing protective in-air damping |
| 13 — Contact trails | Distance-spaced scuffs, short local puffs and gated sparks from accepted loaded contact/release | E3d3, GP-14/19; separate CR-02c/03c wreck observations and qualified water inputs; endpoint power is not wear |
| 14 — Particle representation | Capability-probed CPU/GPU adapters, optional soft fade/flipbooks and bounded secondary effects | CR-22c with SM-19/21; adapter to 20's shared budget, retaining useful fallback cues |
| 15 — Crash plume transport | Adapt existing SM-19/20 wind entrainment, curl, growth/dilution and lighting to crash profiles | CR-22b/c and SM-19–21; consumes 18's proposed source/aftermath timeline, never the paused live-flight path unchanged |
| 16 — Finite fuel effects | One estimated released-fuel partition for mist/spill/flash/fire, separate from retained onboard fuel | CR-22b/d; correct CR-AUD-13 first. A luminous fireball does not authorize physical blast |
| 17 — Battery sequences | Deterministic authored quiet/vent/flare/residual alternatives with finite delayed pulses | CR-22b, using 18's timeline; actual thermal damage remains GP/CR evidence, with CR-40 an independent consumer |
| 18 — Source lifetime and attachment | One proposed source receipt and aftermath timeline, stable part anchor, finite emission and residual aging | CR-22b/d with SM owners; CR-AUD-12/13 prerequisites; existing normal exhaust keeps its own qualified behavior |
| 19 — Material/contact audio | Event-driven impact/tear/rattle tails, wreck scrape release and listener-aware transient delay | GP-14/19, CR-02c/03c, AUD-11/15/16; accepted physical observations and visual wreck contacts remain distinguished |
| 20 — Combined budgets | Scene-wide accounting for local pools, importance/culling adapters, bounded lifecycle and native qualification | CR-22c/e, GP-22, SM-21 and AUD/PT; same accepted flight and incident state across presets |

The source report states the current foundation, rejected alternative, computational tradeoff and acceptance gate for each row. Delivered CR-01d/e, CR-02/03b, CR-09b/c/d1/d2/e/f, CR-22b/d and optimization slices retain their delivered status. These proposals extend their parent steps; they do not relabel existing functionality as missing or close Gate CR. Closed SF-00–09 IDs are not repurposed.

### 10.2 Dependency order and reviewable slices

1. **Contact and accounting prerequisites.** Preserve the prior audit controls and repair the relevant witness, family-composition, remaining-time, wreck ownership, clock and fuel-source inconsistencies in focused changes. Start 01 and the admitted observations for 13/19 under §9. Exact flat-plane contact and stable event identity do not wait for full terrain, optional patches or calibrated fracture. Capture cold/warm baselines and shared resource accounting early through 20.
2. **Convincing touches and supported aftermath.** Build 13/19 on existing GP-19 dry live-hull observations; qualify any added scenery/wet/wreck inputs separately. Develop 12's simple/convex support and secondary-contact tests, then compare lower damping and 11's optional fragment motion. Keep earlier CR-09 surface response and pools; adding particles is not the repair for sliding/levitating bodies.
3. **One source lifecycle, then richer effects.** Resolve CR-AUD-12/13; define 18's proposed common source/timeline contract and 16's finite fuel allocation. Implement the selected source rules before 15's crash adapter to SM-19/20. Add 17's alternatives first as explicit fixtures. Use 14's renderer adapter and 20's one budget owner throughout. Quiet battery damage and source-less impacts remain legitimate outcomes.
4. **Evidence-backed attached damage and release.** Author/test 06/07 in parallel with the earlier slices. Qualify 08's single component response, then physical 09/10 with GP-18, the shared topology contract and damaged-flight owners. Optional visual seams/tethers may precede physical articulation only with a strictly one-way presentation boundary. The visual release schedule cannot delay actual physical mass loss or preserve failed support.
5. **Separate advanced capability trials.** Investigate 02's patch law, 03's calibrated response, 04's transient water and 05's local blade damage within declared domains. Use matched supported and unsupported controls. A wet visual effect, a new blade mesh or a numerical fixture does not activate a fleet capability. Expand only after contact, energy, recovery, replay and physical-evidence gates pass.

These are dependency slices, not a promise to ship every effect or a reason to hold useful contact feedback until all structural research finishes. Each implementation PR declares its source pin, chosen existing owner, preserved defaults and narrowly sufficient checks. Target-host rendered and physical validation gates remain separate from software tests.

### 10.3 Shared contracts that prevent duplicated systems

**Contact and work.** A new patch response replaces the corresponding point response rather than adding another force. Trial-stage force evaluation cannot mutate persistent damage; accepted pieces commit episode work once. GP-07c numerical rate bounds are not force/work calibration. For moving water, interface gap rate and water-particle velocity are distinct inputs; unsupported fluid motion cannot be synthesized from wave height alone. For blades, body rate and signed shaft-relative rate are transformed once into a common frame; RPM alone need not be an energy-bearing shaft state.

**Structure and release.** Authored bonds distinguish rigid, hinged, tethered and separated states. Connectivity alone supplies no capacity or safe-flight claim. Keep mass, moments, inertia and collision ownership consistent through the visual delayed-release schedule. Authoritative detachment occurs at its independently qualified committed time, with retained/detached resources and angular/linear momentum accounted in one frame. Godot joints never apply reactions to the active flight body; decorative chips do not remove physical mass.

**Aftermath source and clock.** Investigation 18 owns the proposed immutable source receipt and shared aftermath lifecycle; 16 supplies fuel estimates, 17 battery sequence policy, 15 plume transport, 19 sound and 20 presentation allocation. Bind incident/event/source ID, evidence/estimate provenance, part-local anchor or explicit world fallback, source kind, start/expiry and residual-particle lifetime. Distinguish terminal flight freeze from manual pause/holds. Anchor a bounded presentation elapsed time to the accepted event; do not advance flight state or use shader wall time. Define low-FPS catch-up, culling, reset, replay and discontinuity behavior so elapsed time is not lost and expired sources do not restart. Live SM-19/20 relies on advancing accepted presentation time, so it cannot be connected unchanged to a terminally paused session.

**Finite sources and independent consumers.** Sampled onboard fuel bounds an explicitly estimated release; it is not proof of leakage. Separate retained/unknown, unburnt spill/mist, flash and continuing fire without double-counting. A refused fuel sample has an explicit fallback, never an invented full or empty tank. Flame stops when its qualified/estimated source expires; admitted residual smoke and existing puffs can age afterward. Battery vent timing and propagation remain authored presentation estimates until a physical model exists. None of these effects creates repair charges or physical blast. CR-40 continues to consume independently admitted evidence.

**One presentation budget.** Local limits (24 wreck bodies, 700 crash particles, 160 chips and 768 profile-smoke particles per respective instance) are retained unless changed with evidence. They do not establish a scene/fleet ceiling. Investigation 20 accounts for concurrent sources, geometry, particles, decals, lights, voices and memory; 14 implements capability-aware allocation. Culling/quality may reduce appearance work and density while logical source expiry and accepted physics remain unchanged. Disabled features avoid unnecessary allocation. Keep causal onset and disclose bounded drops/overflow rather than deferring the physical event.

### 10.4 Fleet, performance and visual acceptance

Qualify representative construction and energy types, then each supported vehicle adapter. Fixed-wing balsa/foam/composite configurations, jet/fuel cases, helicopter main/tail rotor and skids, quad props, blimp hull/gondola and car body/wheel contacts have different evidence and unsupported domains. Extend tests across the authored fixed-wing routes without assuming one aircraft proves the fleet. CR-AUD-01/02/14/21/24/25/27 remain relevant composition/geometry prerequisites. Actual contact identity must distinguish people, vehicles, parked aircraft, foliage and solid structures; proximity alone cannot assign a person/object impact (CR-AUD-30). Static proxies do not establish mutual dynamic-body response; future aircraft-to-aircraft exchange coordinates with AFC-23 and the shared physics design.

Use the report's twelve matched acceptance scenarios: true clear pass, loaded tip release, material-seam scrape, prop/rotor variants, qualified wet entry/exit, repeated attached load, asymmetric separation, supported rest/reimpact, fragment wind response, finite fuel, battery alternatives and concurrent cold/warm stress. Capture pilot and inspection views plus sound. A mild touch should read locally; release should stop rubbing; a supported wreck should stop naturally. The smoke emission origin follows its source while emitting; released puffs advect and disperse immediately and continue aging after emission ends. These are human acceptance questions, not conclusions from this research pass.

Measure p50/p95/p99 and worst tick/frame, cold first impact, sustained contact, no-contact overhead, native solver/mixer/GPU work, transparent coverage, allocations, RAM/VRAM, body/particle/voice counts, overflows and repeated-session resource growth. Ordinary systems qualify at **1920×1080 first**, then higher resolutions, then 720p fallback. The reviewed current-source [resolution policy](https://github.com/bultodepapas/OpenRCsimulator/blob/a866d880d8edbe84d2c59780624c35c8c7f107fc/AGENTS.md) separately requires Apple Silicon Retina at native panel resolution; record output, drawable and internal 3D pixels under the [Apple plan](apple-silicon-performance.md). Qualify the actual pinned engine and renderer, including Compatibility/CPU fallback and the Apple Metal path; a Godot version string does not prove particle/joint/decal support. Paired effects-off/low/high runs must preserve accepted state, incidents and independent economics. This documentation pass executes no runtime or performance campaign.

## 11. Game-source integration: two rounds of ten — 20 November 2026

**Status: twenty additional game studies integrated; implementation and qualification remain open.** The [game research report](../research/crash-damage-investigations/CR-AUD-2026-11-17/game-collision-studies-20-2026-11-20.md), [109 source anchors](../research/crash-damage-investigations/CR-AUD-2026-11-17/game-collision-sources-2026-11-20.json) and [provenance](../research/crash-damage-investigations/CR-AUD-2026-11-17/game-collision-provenance-2026-11-20.json) review application `48580b75a796fc6048fb77cdd69875c94ebb69e0`. The first ten were completed before the second ten were selected from their gaps. Eighteen entries inspect pinned public game code; BeamNG.drive and Teardown use first-party documentation only. PicaSim is source-available with noncommercial terms. Supporting engines and multiple source files do not count as additional games.

G01–G20 are research labels, not new step IDs. These studies extend §10's earlier twenty general investigations and §9's recoverable-contact contract. Existing GP/CR/SM/AUD owners retain authority. No source, assets, new solver, runtime threshold or performance setting is imported. The audit branch contains older divergent runtime files; application integration must take only this documentation delta, not merge that stale runtime.

### 11.1 Accepted increments and ownership

| Study | Increment selected for the existing plan | Existing owner and qualification boundary |
| --- | --- | --- |
| G01 — PicaSim | Explicit component/capability observations; distinguish candidate overlap from a physical witness | E3d2/3, GP-10/14/16/17, CR-20; no any-overlap failure or low-RPM safety rule |
| G02 — Rigs of Rods | Directional elastic/plastic/failure diagnostics for one authored component | GP-11/12/16/17/19, CR-07; endpoint power is not integrated work; no beam-solver transplant |
| G03 — BeamNG.drive | Typed trigger/follower attachment validation and a small graph/debug fixture | CR-06/07, GP-16/17; forbid spurious cross-side damage without forbidding real transmitted loads |
| G04 — VDrift | Configuration/build/caller receipts; account for retained, pending and active parts at release | CR-09, GP-18, CR-AUD-06/07/08; its guarded fracture code is not evidence of an active current feature |
| G05 — SuperTuxKart | Local material cues and exact duplicate-request handling that preserves patches, layers and recontacts | GP-14/19, CR-02c/03c, AUD-11/15/16; extend existing scrape grains |
| G06 — Pioneer | Local relative normal/tangential diagnostics and response without automatic terminal damage | E3d1/3, GP-10/14/19; AFC-23 for future mutual dynamic exchange; reject whole-body slide damping |
| G07 — OpenClonk | Bounded construction-specific cosmetic mixtures and explicit secondary-birth identity | CR-06/07/09/22c/e; extend existing splinters/interiors; cosmetic counts do not remove physical mass |
| G08 — OpenRA: Red Alert | Distinct local damage cues and source handoff/retirement through wreck creation | CR-09/22b/d, SM-19/20, AUD; no scripted arc for important parts or generic smoke from paint damage |
| G09 — Teardown | Separate intact disconnection from removed material; support-aware decorative chip transitions | CR-06/09/19/22c/e; public API only, no arbitrary structural collision grace or forced freeze |
| G10 — Space Station 14 | Explicit spawned-piece receipts and backlog/overflow accounting | CR-09/22c/e, GP-22, SM-21, AUD; synthetic concurrency fixture, no deferred authoritative damage |
| G11 — FlightGear | Moving-support/wet/rotor capability matrix and comparison with independent blade geometry | E3d2/3, GP-10/14/16/17/18, CR-20 and lake/rotor owners; preserve existing fast-disc terrain query |
| G12 — DOOM 3 | Remaining-step-time control and support/COM/rest diagnostics | E3d3, GP-08/10/14 for live motion; CR-09d3/19 and CR-02c/03c/AUD for wreck settling/audio |
| G13 — Overgrowth | Preserve actual contacted entity/region/material and avoid proximity-based person attribution | CR-AUD-30, GP-14/19, CR-02c/03c/AUD; no combat multipliers or unqualified articulated-body claim |
| G14 — Beyond All Reason | Prioritize major-part readability and retain evidence-bearing source identity | CR-09/19/22b/c/e, GP-14; distinguish visual estimates from physical failure; game/compiled script/engine pairing unverified |
| G15 — Veloren | Bounded fractional emission, explicit expiry/debt and measured upload/allocation work | CR-22c/d/e, SM-19–21; reuse existing smoke timing; per-chunk rate limit is not a scene cap |
| G16 — Endless Sky | Different source/emission velocity policies and qualified fractional birth age | CR-09/22b/c/d, SM-19/20; endpoint-only observations retain their provenance; no draw-driven emission |
| G17 — Warzone 2100 | Explicit important-body versus expiring-chip roles; separate rest from reimpact cues | CR-09d3/19, CR-02c/03c, CR-22c/e; animated bounce/expiry does not repair physical support |
| G18 — Mindustry | Separate source kind, released-quantity estimate, finite allocation and visual demand | CR-22b/c/d/e, SM-21; source refresh/handoff must not refill fuel or authorize blast |
| G19 — The Powder Toy | Finite emission/residual states and persistent material appearance after cooling | CR-07/22b/c/d, SM-19–21; appearance is not calibrated thermal damage or repair-cost evidence |
| G20 — VoxeLibre | Explicit material-query roles and known/unknown causal provenance through delayed effects | GP-10/14, CR-09/19/22b/d; water/contact/shielding are separate questions; no inferred culprit |

The report supplies one discriminating proposed experiment per game, primary source paths and rejected shortcuts. The application comparison preserves delivered foundations: E3d1 live-hull continuation, GP-11/12, experimental fixed-layout GP-16/17, GP-19 scrape grains, the fast-rotor disc terrain query, pooled wreck bodies/CCD/sleep, CR-09e/f visual details, existing fuel-kind effects and SM-19/20 transport. None is relabeled as missing.

### 11.2 Concrete next slices

1. **Contact correctness and local evidence:** retain the CR-AUD-31/32 geometry/time controls and CR-AUD-30 entity attribution. Use qualified point-relative motion, component, surface and patch/episode identity; preserve unavailable evidence rather than inventing a witness, shaft state or exact timestamp. Extend existing GP-19 feedback only after admission. Physical damage still requires its own accepted work/state contract.
2. **Major fragments before cosmetic density:** inspect parent plus pending/active parts across each release in one declared frame, including caps, damping, external impulse/torque and scatter. Current visual accounting is a diagnostic baseline, not an already-conserved handoff. Qualify support/secondary contacts before lowering damping or changing shape detail. Preserve recontact/wake and source anchors when render representations change.
3. **The one aftermath lifecycle:** extend §10 investigation 18 under CR-22b/d and smoke owners. Resolve CR-AUD-12/13; bind known event/source/part IDs, evidence/estimate status, finite start/expiry and residual policy. Treat manual pause, terminal freeze, reset, replay, hide/show and frame stalls explicitly. Preserve existing normal exhaust behavior while qualifying the crash adapter.
4. **The one combined presentation budget:** extend §10 investigation 20 under CR-22c/e, GP-22, SM-21 and AUD/PT. Include queued births and callbacks alongside local body/particle/light/voice pools. Preserve useful onset/major-part readability and expose bounded drops. Ten synthetic concurrent sources test the component budget, not production fleet crash attachment. Quality/culling must not move accepted physical damage in time.
5. **Independent advanced trials:** qualify a transient wet feature, blade contact/shaft-work model and single component permanent-set/failure trial separately. Existing fast-rotor disc terrain coverage is not general blade-phase CCD; the slow phase proxy has separate limits. A sparse FlightGear rim test does not improve that coverage by itself. Broader vehicle/people/dynamic-contact behavior retains its own adapter gates.

These slices refine §10's dependency order. Contact cues can improve before a full attachment graph or wet-continuation model. Every implementation change declares its existing owner and the narrow acceptance case it resolves; no new track or competing fire/budget system is created.

### 11.3 Acceptance additions from the game studies

**Intermediate outcomes.** At equal total speed, compare clear pass, vegetation brush, loaded tangential scrape, steep local impact and release/recontact. Qualified clearance produces no contact damage/cue. Rendered grass and a solid ground proxy are different geometries. Stopped, coasting and powered blade cases need actual signed shaft/feature evidence; no universal millimetre/RPM survival threshold is inferred. Keep transient water separate from the current terminal-only policy. If a query is unresolved, preserve that status.

**Identity and timing.** Duplicate suppression uses an explicit request/birth or transition identity, including source, layer and patch/episode as applicable. Permit simultaneous patches, paced grains and real reimpacts. Preserve only causal/source identity actually supplied; an inferred flight-cause label is not a verified human/attacker identity. For a qualified sub-tick event, preserve its fraction; for accepted endpoints, do not fabricate an earlier instant. Check remaining-tick motion independently of presentation.

**Hitches and finite sources.** Add 200-ms and 250-ms stalls, culling re-entry, manual pause and reset. Current crash-effect dt clamping loses elapsed source age; live profile smoke deliberately rebases on larger discontinuities. The proposed aftermath policy must account for elapsed age and admitted/dropped/expired births, bound pending work and prevent stale catch-up/restart. Onboard inventory bounds a separately estimated release; keep unknown/refused samples explicit. Source handoff does not refill fuel, and finite residual smoke does not create new ignition or physical damage.

**Support and cost.** Compare an important fragment with cheap cosmetic chips on qualified flat/sloped support, including wake and reimpact. Fixed-wing terminal water currently clears the wreck pool; water-body trajectories require an explicit future adapter or labeled synthetic fixture. Measure native work and memory as in §10.4, with the same display-resolution priorities. Matching accepted state/incident/economics across effects settings is required; equal cosmetic counts or pooled instance IDs are not. Numerical tolerances are declared before experiments, which remain unexecuted by this documentation pass.
