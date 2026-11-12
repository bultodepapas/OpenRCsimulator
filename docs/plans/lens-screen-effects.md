# Lens and screen effects: impact blood, rain on the lens, impact grime

2026-11-12 · Revision 3 · **Active plan** · Step prefix: **LENS-** (camera subtrack, [registered](../README.md#tracks-plans-and-step-ids)) · Gate: **LENS**

**Status:** first implementation delivered 2026-11-12; see [§16](#16-implementation-status-2026-11-12) for what exists, how it was verified and what remains open. Sections 0–15 keep the design and research; line references may drift.

**Revision 2** follows an independent Good Enemy review (2026-11-12, read-only, no shared context). The lead verified its main claims against the source and corrected the plan:

- Contact events carry `material` only for lakes.
- Speed and energy sit under `measure`.
- The FPV quad publishes no contact events.
- Physics runs at 240 Hz, not 60 Hz.
- Crash effects use `CPUParticles3D`.
- CAM-12 forbids a screen copy in its FPV path.
- The curtain timings in Revision 1 contradicted its own comfort rules.
- Drop determinism was overstated.

**Proposed ownership:** `app/render/lens/`, `app/tests/test_lens_*.gd`, `docs/research/lens-effects/`. Everything else is coordinated with its owner (see [§10](#10-ownership-and-seams)).

---

## 0. One-paragraph summary

Add one presentation-only **lens stack**: a single `CanvasLayer` drawn over the finished 3D image and under the HUD, with three channels that share one screen read, one lifecycle and one settings block.

1. **Impact blood** — a classic red curtain that runs down from the top of the screen with drips, in the spirit of late-1990s console shooters. It fires when the aircraft (or quad) strikes a **person** and, at full strength, when it strikes **the pilot** (the player).
2. **Rain on the lens** — drops that land, bead, merge, slide and get blown off the camera, driven by a rain rate, the camera's velocity through the rain, gravity and wind. Thunderstorms and the future tornado modulate it.
3. **Impact grime** (my choice) — mud, dust, grass, water spray and, for FPV, a cracked lens, stamped from the surface the aircraft actually hit. Glow-engine oil film builds up slowly on onboard cameras.

Phase 1 touches neither `app/sim/` nor `app/physics/`. For **fixed-wing** flights, blood and grime triggers read accepted contact events that already exist. Blood and grime events are tick-seeded and replay-identical; rain drops are presentation that follows the camera and is not replay-identical (§4.2). The **FPV quad publishes no typed contact events today**, so quad blood and grime need a coordinated evidence record first (LENS-02b). Until then, quad blood and grime are out of scope; rain works on the quad from day one.

---

## 1. Goals, non-goals and principles

### Goals

- **Readable and beautiful first, then realistic.** The blood curtain is deliberately stylised and nostalgic. Rain and grime follow physical drivers (rain rate, drop size distribution, relative airspeed, surface material) and then an explicit art gain.
- **Zero cost when off.** Disabled channels allocate no nodes, materials, textures or per-frame work ([AGENTS.md](../../AGENTS.md) graphics rule).
- **Deterministic where it matters.** Shaders never read `TIME` (the [shader clock](../../app/render/shader_clock.gd) rule, enforced by `app/test.sh`); the CPU passes presentation time as uniforms, so pause holds every effect. Each accepted event reseeds the random stream with its own identity, like [storm events](../../app/environment/storm_events.gd); see §4.2 for what a replay repeats.
- **1080p first.** Budgets and acceptance are set at 1920×1080, then 1440p/4K, then 720p ([display priorities](../../AGENTS.md#display-resolution-priorities)).
- **Player choice.** Every channel has its own switch. Blood has a content switch independent of graphics quality.

### Non-goals

- No physical effect of rain (lift, drag, ingestion, electronics, tyre friction). The [sky plan](sky-clouds-weather.md#8-distant-storms-night-lightning-and-the-later-tornado) already excludes precipitation physics; this plan keeps that boundary.
- No injury model, ragdolls, bleeding people or persistent gore in the world. Blood exists **only on the screen** and only for a few seconds.
- No recreation of any specific game's assets, timing curves or look. Section 2 lists inspiration; shapes, colours and timings here are our own.
- No new physics collision in phase 1. The optional pilot body proxy (LENS-05b) is a separate, coordinated physics change.

### Principles we copy from the repository

| Repository precedent | What we reuse |
| --- | --- |
| [SUN-03 afterimage](../../app/render/sun/sun_afterimage.gdshader) mounted by [sun_glare.gd](../../app/render/landscape_upgrade/sun_glare.gd) on `CanvasLayer` −10 | Screen-fixed `canvas_item` shader with `hint_screen_texture`, drawn over the 3D image and under the interface; pilot view is an *eye*, the other views are *lenses* |
| [Crash presentation](../CRASH-DAMAGE-PLAN.md) and its [director](../../app/render/crash/director.gd) | Presentation-only consumer of accepted contacts; `--crash-effects=off`; scripted/capture/trace routes allocate nothing |
| [CR-22c-R1 shader warm-up](../../app/render/crash/shader_warmup.gd) | Compile the blood/drop/grime draw variants during flight setup so the first hit does not hitch |
| [Storm events FW-84](../../app/environment/storm_events.gd) | Event identity from seed + tick, never render cadence or a global RNG |
| [Shader clock](../../app/render/shader_clock.gd) | `sim_clock` global uniform, wrapped at 1024 s; animations follow pause and replay |

---

## 2. Research and inspiration

### 2.1 The classic blood curtain

The reference most players remember is the N64 shooter era (GoldenEye 007, 1997; later Perfect Dark): on death, a red sheet descends from the top edge with uneven drips while the view keeps playing behind it. Retrospectives describe that curtain coming down the screen at each death ([Pixelfix, *One More Hit: GoldenEye 007*](https://pixelfix.substack.com/p/one-more-hit-goldeneye-007)). Developer accounts say the in-world blood was negotiated with Nintendo and reduced to a red vertex tint where characters are hit ([MEL Magazine oral history](https://melmagazine.com/en-us/story/an-oral-history-of-goldeneye-007-on-the-n64); [Mental Floss](https://www.mentalfloss.com/article/63239/15-deadly-facts-about-goldeneye-007)). I found **no primary technical description** of how the curtain was rendered; treat any "how they did it" claims as unknown.

What makes that curtain work, and what we keep:

| Quality | Why it works | Our version |
| --- | --- | --- |
| Top-down motion | Reads as liquid under gravity; never covers the centre instantly | Front descends at a speed tied to strength; centre stays readable for ~0.6 s |
| Uneven drips | A straight wipe looks like a menu transition | Per-column hashed drip lengths, bulbous drip heads, a few long runners |
| Transparency | The world keeps playing behind it | Beer–Lambert absorption over the live image, not an opaque red quad |
| Brevity | Punctuation, not punishment | 3–6 s total including drain and fade |

Modern variants (regenerating-health shooters, damage vignettes) layer a pulsing vignette, splats and drips, and often keep a clear radial centre so the game stays playable ([Polycount damage-screen collection](https://polycount.com/discussion/235532/documentation-damage-screen-collection-for-unreal-engine); [Unreal forum: health-driven overlay](https://forums.unrealengine.com/t/red-screen-connected-to-health/97392/3)). See also a [Godot walkthrough of full-screen `hint_screen_texture` effects](https://uhiyama-lab.com/en/notes/godot/postprocess-screen-shaders/).

### 2.2 Rain on a lens

| Source | Lesson |
| --- | --- |
| [Shawn Hargreaves, *MotoGP: raindrops keep falling on my lens*](https://www.shawnhargreaves.com/blog/motogp-raindrops-keep-falling-on-my-lens.html) | Shipped racing game: drops are particles that appear at random, then fade, slide down, or are **pushed outward when the camera moves fast**. Behaviour sells it more than optics. |
| [Codrops, *Rain & Water Effect Experiments* (Lucas Bebber, 2015)](https://tympanus.net/codrops/2015/11/04/rain-water-effect-experiments/), code at [github.com/codrops/RainEffect](https://github.com/codrops/RainEffect) | Draw drop shapes into a texture whose colour encodes a normal; the shader refracts the background through it. A drop on glass shows the scene **flipped**. Licence permits use in projects but not republishing as-is: study, do not copy. |
| BigWings' *Heartfelt* (Shadertoy, 2017) | The best-known procedural "rain on window". Reported as **CC BY-NC-SA 3.0** ([licence discussion](https://godotshaders.com/shader-license/shadertoy_port/)); non-commercial and share-alike, so **do not port it**. |
| [godotshaders: *Rain on Glass*](https://godotshaders.com/shader/rain-on-glass/), [*Raindrops on glass*](https://godotshaders.com/shader/raindrops-on-glass/), [*Rain drops on screen – notexture*](https://godotshaders.com/shader/rain-drops-on-screen-notexture/) | Godot 4 canvas shaders: egg-shaped SDF drops with tails, refraction from SDF normals, extra blur where trails are dense. Licences vary (MIT adaptation with unclear upstream; CC BY 3.0 port). Reference only unless LENS-00 clears provenance. |
| Racing games with celebrated cockpit rain (e.g. Driveclub, recent F1/GT titles) and broadcast motorsport footage | Wipers aside, viewers accept: drops bead when slow, streak at speed, are flung sideways in corners, flash in headlights. Use real FPV DVR footage in rain as the primary visual reference for the quad. |

### 2.3 Rain physics we use as drivers

- **Intensity classes** (convention-dependent; NWS/METAR style): light ≤ 2.5 mm/h, moderate 2.6–7.6 mm/h, heavy > 7.6 mm/h. Thunderstorm cores reach tens of mm/h.
- **Drop size distribution**: Marshall–Palmer exponential, `N(D) = N0·exp(−Λ·D)`, `N0 = 8000 m⁻³ mm⁻¹`, `Λ = 4.1·R^−0.21 mm⁻¹` ([Marshall & Palmer 1948](https://www.radartutorial.eu/15.weather/pubs/marshall-palmer-1948.pdf); [Stull, *Practical Meteorology* §7.7](https://geo.libretexts.org/Bookshelves/Meteorology_and_Climate_Science/Practical_Meteorology_(Stull)/07%3A_Precipitation_Processes/7.07%3A_Precipitation_Characteristics)). Heavier rain has larger drops; mass-weighted mean diameter ~0.9 mm light, ~1.6 mm heavy ([NASA TM](https://ntrs.nasa.gov/api/citations/20180002207/downloads/20180002207.pdf)).
- **Terminal fall speed**: use a standard power law such as Atlas–Ulbrich `v(D) ≈ 3.78·D^0.67 m/s` (D in mm). **LENS-00 must confirm coefficients against a primary source**; the search did not return one.
- Exponential fits are averages; real rain is bursty. A slow seeded modulation (gusts of heavier rain every 20–60 s) is more believable than a constant rate.

**Worked example (moderate rain, R = 5 mm/h):** `Λ = 4.1·5^−0.21 ≈ 2.92 mm⁻¹`; total number density `N0/Λ ≈ 2 700 drops/m³`. A forward-facing FPV lens (front glass ≈ 12 mm, area ≈ 1.1·10⁻⁴ m²) at 30 m/s sweeps `2 700 × 30 × 1.1·10⁻⁴ ≈ 9 drops/s`. At rest it catches only what falls on it, well under 1 drop/s. That ratio, not the absolute number, is what we keep: **drops arrive in proportion to airspeed into the rain**. An art gain then scales the count to what looks right on a 1080p screen.

### 2.4 Grime and lens damage

Real FPV DVR crash footage routinely ends with grass blades or mud on the lens, a dust veil that lowers contrast, or a cracked lens with a hard line through the image. Glow engines throw castor/synthetic oil exhaust residue across the airframe; an onboard camera behind the engine slowly hazes, which every glow modeller recognises. These give the third effect a factual base and use data the repository already has (surface materials on contacts, [CR-08b severity](../research/crash-damage-investigations/CR-08b/README.md), the engine source kind in the [smoke path](../../app/render/smoke/)).

### 2.5 Free assets (download, do not draw)

Repository rule: do not create what can be downloaded. Candidates for LENS-00 intake, all reported CC0 by their pages (verify each page, record hash and URL):

- [Liquid Splatter Pixel Texture](https://opengameart.org/content/liquid-splatter-pixel-texture) — 512² splatter, usable for blood, oil or water.
- [Blood Splatters (AntumDeluge)](https://opengameart.org/content/blood-splatters) — small red/green splats.
- [Horror Texture Pack (Screaming Brain Studios)](https://opengameart.org/content/horror-texture-pack) — "Stains" with alpha.
- [Mini Texture Pack 3: Liquids / 140 liquid textures](https://opengameart.org/content/140-liquid-textures) — liquids in several colours.
- Avoid the [Splatter Pack](https://opengameart.org/content/splatter-pack) unless we accept CC BY 3.0 attribution.
- Drop normals, dust and crack overlays: search ambientCG/Poly Haven/OpenGameArt in LENS-00; fall back to a shader-generated SDF only if nothing redistributable fits.

---

## 3. What already exists (ground truth, 2026-11-12)

| Fact | Where | Consequence |
| --- | --- | --- |
| Physics ticks at **240 Hz** (up to 12 catch-up steps per frame); the flight presents its own interpolation | [app/project.godot:46-50](../../app/project.godot#L46-L50) | Per-tick work must be tiny; presentation interpolates between ticks (CAM-25) |
| Desktop and web default to the **Compatibility renderer** (`gl_compatibility`); Apple Silicon uses Mobile; the Product High profile uses Forward+ | [app/project.godot:60-70](../../app/project.godot#L60-L70) | Qualify all three paths. `CompositorEffect` is **not available** in Compatibility ([Godot renderer table](https://github.com/godotengine/godot-docs/blob/master/tutorials/rendering/renderers.rst)). Use the documented `CanvasLayer` + `canvas_item` + `hint_screen_texture` post-process ([Godot docs: custom post-processing](https://github.com/godotengine/godot-docs/blob/master/tutorials/shaders/custom_postprocessing.rst)). No depth or normal buffer in that path, which is fine: lens effects are screen-space by nature. |
| Godot copies the screen texture to the back buffer the first time a node reads it, unless a `BackBufferCopy` ran earlier | [Godot docs: screen-reading shaders](https://github.com/godotengine/godot-docs/blob/master/tutorials/shaders/screen-reading_shaders.rst) | Put all three channels in **one** layer. **Unverified:** whether Compatibility copies again per `CanvasLayer` (the sun afterimage on −10 already reads the screen). Also unverified: whether the back buffer has mipmaps for `textureLod` blur. LENS-01 must measure both before the budgets in §9 are trusted. |
| A screen-fixed overlay precedent exists on layer **−10** | [sun_glare.gd:28](../../app/render/landscape_upgrade/sun_glare.gd#L28) | Lens layer goes just above it (proposed **−9**) so lens drops refract the afterimage too, and stays under HUD layers (2, 4, 11+). If a second copy proves costly, consider merging the afterimage into the lens layer in pilot view. |
| People are collision capsules of kind `"person"` (pilot, standing, sitting, working; radius 0.325–0.34 m) with response class `soft_foliage_impulse` | [collision_world.gd:390-394, 681-687](../../app/scenery/collision_world.gd#L681-L687), [prefabs.gd:37-40](../../app/scenery/prefabs.gd#L37-L40) | A fixed-wing person strike already reaches the contact pipeline. No new physics for third-party people. |
| Flight-line `person_pilot` placements exist (role `pilot`, zone `pilot_line`) | [population.gd:194-196](../../app/scenery/population.gd#L194-L196) | LENS-05 must state where they stand relative to the player's station, so a strike on a neighbouring pilot and the player-strike detector never double-fire. |
| Accepted contacts are detached records. Top level: `obstacle_kind`, `probe_source` (hull/gear/propeller), `lifecycle`, `point_ned`, `velocity_ned`. **`speed_mps` and `impact_energy_j` sit under `measure`.** **`material` exists only on lake events** (`water`, `bank_ground`). Scenery events are formed only for terminal or dissipative responses. | [aircraft_contact_events.gd:121-146, 410, 430-467](../../app/sim/aircraft_contact_events.gd#L410), signal `contact_events_changed` in [flight_session.gd:1218](../../app/sim/flight_session.gd#L1218); consumer precedent `_on_accident_contacts` in [main.gd:2834](../../app/main.gd#L2834) | Blood triggers are pure filters over `session.contact_events()`. Grime gets the ground surface from the event point through the crash director's read-only `surface_at(field, north, east)` ([director.gd:217](../../app/render/crash/director.gd#L217)), the same lookup crash scuffs and audio use. |
| The FPV quad builds the same obstacle inventory but reports a strike only as `crashed(reason)` with the text "Obstacle strike". There is no obstacle id, kind, point or speed. | [multirotor_scene.gd:136](../../app/vehicles/multirotor/multirotor_scene.gd#L136), [multirotor/session.gd:60](../../app/sim/multirotor/session.gd#L60), [controlled_plant.gd:567-572](../../app/physics/multirotor/controlled_plant.gd#L567-L572) | Quad blood and grime need **LENS-02b**: a typed strike record agreed with the multirotor and physics owners. Those files are pinned, so the change is theirs. Phase 1 is fixed-wing only. |
| Camera views: `pilot`, `chase`, `flyby`, `orbit`, `closeup`; FPV camera for the quad. CAM-12 proposes an FPV barrel warp in a supersampled `SubViewport` and requires **no screen-texture copy** on that path. | [camera_rig.gd:20](../../app/render/camera/camera_rig.gd#L20), [multirotor_camera.gd](../../app/vehicles/multirotor/multirotor_camera.gd), [camera-views plan](camera-views.md) | View policy table in §6. With CAM-12, drops must be drawn **after** the warp and on a layer above wherever the warped image is displayed. CAM-12's no-copy rule is about the warp itself; lens drops add one deliberate read. Agree on this with CAM before LENS-08. |
| Weather: nine sky presets; FW-83/84 distant storm towers, rain **curtains** anchored ~9 km away, lightning flash radiance; **no local precipitation at the field**; tornado FW-89 pending | [weather_presets.json](../../app/data/sky/weather_presets.json), [storm_events.gd](../../app/environment/storm_events.gd), [rain_curtain.gdshader](../../app/render/weather/rain_curtain.gdshader), [sky plan](sky-clouds-weather.md) | Rain on the lens needs a **local precipitation channel** that does not exist yet. LENS-06 asks the FW owner for it; until then a debug/CLI override drives it. |
| Shaders may not read `TIME` | [shader_clock.gd](../../app/render/shader_clock.gd) | Animation runs on CPU-driven presentation time (curtain age, wet clock, integrated rain travel) passed as uniforms. |
| Particles: crash effects use `CPUParticles3D` (bounded, hundreds); smoke uses `GPUParticles3D` | [effects.gd](../../app/render/crash/effects.gd), [smoke/exhaust.gd](../../app/render/smoke/exhaust.gd) | There is no precedent for thousands of particles in Compatibility. LENS-07 must measure `GPUParticles3D` streaks against a `MultiMesh` streak field before choosing. |
| Physics source bytes are pinned | project memory and [STACK.md](../STACK.md#boundaries-and-data-flow) | Phase 1 adds **no** collision proxy for the player. |

---

## 4. Architecture

### 4.1 Node layout

```text
Main (flight scene)                         app/main.gd seam (main-line owner)
└─ LensStack : Node                         app/render/lens/lens_stack.gd   (LENS-01)
   ├─ owns LensSettings (resolved preset + overrides)
   ├─ ImpactTrigger      (RefCounted, pure)  person/pilot strike admission     (LENS-02/05)
   ├─ RainDriver         (RefCounted, pure)  rate → arrivals, drop sizes       (LENS-08)
   ├─ DropPool           (RefCounted)        CPU drop sim, bounded pool        (LENS-08)
   ├─ GrimeTrigger       (RefCounted, pure)  material/severity → splats        (LENS-10)
   └─ LensLayer : CanvasLayer (layer −9)     created only if any channel is on
      ├─ DropsMesh  : MultiMeshInstance2D    one instance per live drop/splat  (first screen reader)
      ├─ GrimeMesh  : MultiMeshInstance2D    mud/dust/grass/crack stamps        (optional)
      └─ Curtain    : ColorRect (full rect)  blood curtain; visible only while active
   └─ RainStreaks : GPUParticles3D           follows the camera, world space    (LENS-07)
```

- **One screen copy.** The first node in tree order that samples `hint_screen_texture` triggers the copy; the others reuse it. Drops refract the 3D image; the curtain absorbs the same image. Drops do not refract the curtain; that ordering is intentional (blood sits on top).
- **Coverage-proportional cost.** Drops and splats are small quads in a `MultiMeshInstance2D`; each quad runs its own drop SDF and refraction. A full-screen shader that loops over 64 drops per pixel would cost ~2 M px × 64 SDF evaluations at 1080p; the instanced approach only pays for pixels a drop covers.
- **The curtain is the only full-screen quad**, and it exists only while active (3–6 s). When inactive it is `visible = false` and its material is not drawn.
- **No allocation when off.** If all channels are off, `LensStack` creates nothing and returns from `_process` immediately. Turning a channel on mid-flight creates its nodes at the next frame boundary, outside physics callbacks (same rule as the accident report).

### 4.2 Data flow and determinism

```text
accepted tick ──► session.contact_events()  ──► ImpactTrigger / GrimeTrigger ──► event queue (tick, seed)
accepted tick ──► pose, velocity, wind      ──► RainDriver (Poisson arrivals per tick, seeded) ──► DropPool
render frame  ──► interpolated camera pose  ──► DropPool.advance(render dt from sim clock) ──► MultiMesh buffers
render frame  ──► sim_clock (global)        ──► Curtain shader (start_clock, strength, impact_uv)
```

- **Replay-identical:** which blood and grime events happen, their strength, and their random draws: each accepted event reseeds the stream with `hash(seed, event id, "LENS")`. Splat placement still follows the active camera (the impact's screen projection), so another view places the same splats elsewhere.
- **Not replay-identical:** rain drops. Arrivals depend on the active view's camera motion, and motion integrates per render frame. View switches and frame cadence change the drop pattern, but not its statistics. This is acceptable for presentation and is stated in captures.
- Drop motion advances by the **interpolated visual clock** (the same presentation time CAM-25 uses), not by raw 240 Hz tick deltas, so drops neither judder between ticks nor run during pause. Some routes fall back to wall time ([main.gd:1377-1379](../../app/main.gd#L1377-L1379)); there, drops follow that clock as the rest of the presentation does.
- Reset, checkpoint restore and aircraft change clear all channels (`main.gd` `_on_resetting` and the restore path; the quad scene connects `session.resetting`). Restoring a checkpoint passes its tick as the admission floor, so it does not replay old blood.
- Captures, traces and scripted routes: off unless `--lens-effects=on` is passed explicitly. CLI: `--lens-effects=off|on`, `--impact-fx=off|curtain|splatter`, `--lens-rain-mmph=<value>` (debug override until LENS-06).

### 4.3 Render-boundary types

`app/render/lens/` is presentation code. It may use `Vector2`/`Vector3`/`Basis`. It converts from the float64 NED records at the boundary, as the crash director does, and never writes back to the session.

---

## 5. Effect 1 — Impact blood

### 5.1 Triggers

| Trigger | Evidence | Strength `s` (0…1) | Presentation |
| --- | --- | --- | --- |
| **Person struck** (any spectator, crew or companion pilot); fixed-wing in phase 1 | Contact event with `obstacle_kind == "person"`, `lifecycle == "new"` | `s = clamp(measure.impact_energy_j / E_full)` (fall back to `measure.speed_mps` when energy is absent) with `E_full` an authored constant (start: 60 J ≈ 1.5 kg at 9 m/s); propeller strikes add +0.25 | Splash at the projected impact side + partial curtain. Below `s_min` (~0.08, a slow brush), only a red edge flash. |
| **Pilot struck** (the player) | Phase 1: presentation-only proximity test (§5.4). Phase 2: a real `person_player` proxy (LENS-05b) | Always ≥ 0.85 | Full classic curtain, hold, drain. Optional "PILOT HIT" card and audio stinger (AUD-owned). |
| **Repeated strikes** | Further person events within 2 s | `s = max(s, s_new)`; restart descent from current front | Never stack more than one curtain. |

**Distance and view.** In the pilot view a spectator struck 80 m away should not paint the whole screen like the player's own death. Strength is multiplied by a view factor: `1.0` for the player; for others `clamp(1.5 − d/60 m, 0.35, 1.0)` in pilot view, `1.0` in onboard/FPV (the camera is on the aircraft that hit them). This is an art rule; LENS-03 tunes it in owner review.

**Safety framing (optional, recommended).** The [crash cause card](../../app/render/crash/cause.gd) can add a line such as "Spectator struck — never fly over or toward people" after a person strike. Real model-flying safety codes prohibit flying over spectators; LENS-00 cites the exact current wording of a national code (e.g. AMA) before any text ships. This turns a gory moment into the most useful lesson a simulator can teach.

### 5.2 Timeline (state machine)

```text
IDLE ─trigger─► SPLASH (0–0.15 s) ─► DESCENT (0.6–1.6 s) ─► HOLD (0–1.2 s) ─► DRAIN (1.5–3 s) ─► IDLE
```

| Phase | What the viewer sees | Parameters (start values) |
| --- | --- | --- |
| SPLASH | 2–5 splats stamped near the impact side (screen-projected `point_ned`, or top for the pilot), plus a soft red edge pulse (no full-screen white or red flash) | splat count `2 + 3s`, radius 6–14 % of screen height |
| DESCENT | Front runs down from the top; uneven drips; the screen centre stays clear for ≥ 0.6 s | constant front speed **0.8 screen-heights/s** (centre reached at ≈ 0.63 s); depth `d(s) = 0.35 + 0.65s`, applied **once** (not multiplied by `s` again) |
| HOLD | Curtain stays, drips keep creeping, slight darkening | ≥ 90 % coverage for at most **1.5 s** in total, unless the flight has ended (§8.3) |
| DRAIN | Sheet thins from the top, runners keep going, colour shifts toward dark brown-red as it "dries", opacity falls | thinning `1/2.5` per s; colour mix to `(0.30, 0.03, 0.02)` |

Two styles, selected in settings:

- **Classic curtain** (default when blood is on): the stylised sheet above, in every view.
- **Lens splatter**: diegetic splats and runners only, on cameras that physically exist (onboard, FPV, chase). In the pilot (eye) view it falls back to a soft red edge vignette. For players who want "realistic" over "arcade".

### 5.3 Shader sketch (Compatibility, `canvas_item`)

Sketch for design review, not final code. It follows the repo rules (no `TIME`, `sim_clock` wrap). Before implementation, fix three known portability defects:

- `smoothstep` with `edge0 ≥ edge1` is undefined in GLSL ES; use `1.0 − smoothstep(lo, hi, x)`.
- `dFdx/dFdy` of a field with per-column `floor()` steps gives 2×2-block spikes at column edges. Derive the gradient analytically from the front function, or from a smoothed field.
- Replace the `sin` hash with the repository's integer hash.

`max_depth` already contains `s`; do not multiply by `strength` again.

```glsl
shader_type canvas_item;
render_mode unshaded;

global uniform float sim_clock;                    // seconds, wrapped to [0, 1024)
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float start_clock;                         // sim_clock at trigger
uniform float strength = 0.0;                      // 0…1
uniform float descent_speed = 1.0;                 // screen heights per second
uniform float max_depth = 1.0;                     // 0…1 of screen height
uniform float drain_start = 99.0;                  // seconds after trigger
uniform float drain_rate = 0.4;
uniform vec3 sigma = vec3(0.55, 8.0, 9.0);         // absorption per unit thickness: blood passes red, eats green/blue
uniform vec3 dry_tint = vec3(0.30, 0.03, 0.02);
uniform float columns = 46.0;                      // drip columns across the screen (aspect-corrected below)
uniform float seed = 0.0;

float h1(float n) { return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453); } // replace with the repo's integer hash

void fragment() {
	float t = mod(sim_clock - start_clock + 1024.0, 1024.0);
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv = SCREEN_UV;                            // y = 0 at the top

	// Uneven front: a slow wave plus per-column drips that grow faster than the sheet.
	float c = floor(uv.x * columns * aspect);
	float f = fract(uv.x * columns * aspect);
	float r = h1(c);
	float drip = pow(r, 4.0) * 0.45 * smoothstep(0.0, 1.2, t);          // a few long runners
	float lobe = 1.0 - pow(abs(f - 0.5) * 2.0, 2.0);                    // rounded drip tip across the column
	float sheet = min(t * descent_speed, 1.0) * max_depth * strength;
	float front = sheet * (0.92 + 0.08 * sin(uv.x * 9.0 + seed)) + drip * lobe * strength;
	float drained = max(t - drain_start, 0.0) * drain_rate;             // the top empties first

	// Film thickness: thick near the top, thin at the front, a bead at drip heads.
	float inside = smoothstep(front, front - 0.015, uv.y) * smoothstep(drained, drained + 0.05, uv.y);
	float thick = inside * mix(1.0, 0.35, clamp(uv.y / max(front, 1e-3), 0.0, 1.0));
	thick += inside * 0.6 * smoothstep(0.03, 0.0, abs(uv.y - front)) * lobe;

	// Optics: a thin liquid film refracts a little, absorbs per Beer–Lambert, and has a wet highlight.
	vec2 grad = vec2(dFdx(thick), dFdy(thick));
	vec3 behind = textureLod(screen_texture, uv - grad * 0.8, 1.0 + 2.0 * thick).rgb;
	vec3 col = behind * exp(-sigma * thick);
	float dry = clamp((t - drain_start) / 3.0, 0.0, 1.0);
	col = mix(col, dry_tint * (0.4 + 0.6 * dot(behind, vec3(0.33))), dry * thick);
	float spec = pow(clamp(dot(normalize(vec3(-grad * 60.0, 1.0)), normalize(vec3(-0.4, -0.6, 1.0))), 0.0, 1.0), 48.0);
	col += spec * 0.35 * inside;

	COLOR = vec4(col, clamp(inside * 1.4, 0.0, 1.0));
}
```

Notes:

- **Beer–Lambert colour** (`exp(−σ·h)`, σ low for red, high for green/blue) gives darker red where the film is thick and lets bright sky glow through thin edges. A flat red tint looks like paint.
- `dFdx/dFdy` are available in GLES3/WebGL2. Check them on the Apple/ANGLE path in LENS-12.
- Drip columns are aspect-corrected so 1080p and 4K look the same and 21:9 does not stretch drips.
- **Colour-vision and contrast:** blood darkens luminance as well as hue, so it reads for red-blind players. An optional "Impact colour" setting (red / dark / desaturated) covers players who dislike red.

### 5.4 Pilot strike detection (phase 1, presentation only)

The player has no collision body today; adding one changes the obstacle inventory and therefore physics identity. Phase 1 detects the strike without touching physics:

- Pilot capsule: station position from [pilot_camera.gd](../../app/render/pilot_camera.gd) (eye height metadata), radius **0.335 m** (the existing `person_pilot` capsule, [prefabs.gd:40](../../app/scenery/prefabs.gd#L40)), from feet to eye + 0.12 m.
- **Source of poses:** the rendered aircraft pose that the presentation already holds each frame (the same interpolated pose the camera and crash director use). Transform the named crash-hull points ([CR-01d](../research/crash-damage-investigations/CR-01d/README.md)) and propeller disc centre by it. This reads no solver internals and adds no tick hook. Use a swept segment test from the previous frame's points: at 40 m/s a 60 FPS frame moves 0.67 m, and a 20 FPS frame moves 2 m.
- A flight-log-style **read-only tick observer** ([FLIGHT-LOGGING.md](../FLIGHT-LOGGING.md)) is the alternative if strike identity must be tick-exact for replay. It is chosen in LENS-05 with the physics owner. At 240 Hz a 40 m/s pass moves 0.167 m per tick.
- First crossing → pilot strike event with the closing speed. A strike already reported as a `person` contact at the same place within 0.5 s is the same event (de-duplication with neighbouring `person_pilot` placements).
- **Honest limitation:** the aircraft passes through the pilot physically. The card says "Pilot struck"; the flight continues unless physics also ends it. LENS-05b removes that limitation.

LENS-05b (optional, coordinated with physics, scenery and field owners): add a `person_player` capsule at the pilot station to the collision world with the `person` kind. That is a physics-visible inventory change: it requires the physics owner's approval, a check that no golden flight crosses the station, and companion airspace review. It is out of this plan's direct scope.

---

## 6. Effect 2 — Rain on the lens

### 6.1 View policy

| View | Has a lens? | Drops | Air shear | Streaks (3D) | Notes |
| --- | --- | --- | --- | --- | --- |
| `pilot` (the eye) | No | Off by default; optional **"Glasses"** setting shows sparse drops with strong defocus | None (head is still) | Yes | Matches SUN-03's eye/lens split. An eye blinks rain away; spectacles do not. |
| `chase`, `orbit`, `closeup` | Virtual camera | Yes, medium defocus | From camera velocity | Yes | Broadcast-camera look. |
| `flyby` | Fixed tripod camera | Yes | None; gravity only | Yes | Drops slide slowly and accumulate: a nice contrast with the moving views. |
| FPV / onboard | Real small lens | Yes, sharp-ish (wide-angle lenses keep near drops more in focus) | Strong, from airspeed | Yes | Prop wash clears the lens partially on pusher/tractor layouts; quads keep drops. |

### 6.2 Inputs

| Input | Source | Fallback |
| --- | --- | --- |
| Rain rate `R` (mm/h) | **New** FW precipitation channel (LENS-06): `precipitation.rate` as an `{value, unit, kind, source}` quantity per preset, plus a coverage flag (`field` or `distant`) | `--lens-rain-mmph` debug override; otherwise 0 |
| Rain burstiness | Seeded slow modulation from session seed + tick | — |
| Camera velocity | Interpolated camera pose difference (render), or aircraft velocity for mounted cameras | — |
| Wind | `_render_wind(clock)` in [main.gd](../../app/main.gd) | zero |
| Lightning flash | [storm events](../../app/environment/storm_events.gd) flash radiance | none |
| Tornado proximity | FW-89 field model (future) | none |

### 6.3 Arrival law

With `n(R) = N0/Λ(R)` the drop number density and `u` the rain velocity relative to the camera (`u = v_rain − v_cam`, where `v_rain = (wind_x, −v_t, wind_z)`):

```text
λ (drops/s on the lens) = gain_view × A_lens × n(R) × max(0, −u · n̂_lens)
```

- This uses total density times one relative velocity. Exact flux is `∫ N(D)·max(0, −u(D)·n̂) dD`, because fall speed depends on diameter (`v_t ≈ 3.78·D^0.67`). The approximation is fine for forward flight. It underestimates an up-facing lens at rest, which catches about 1 drop/s in moderate rain. LENS-08 may tabulate the integral per `R` once.
- Axes: computed in render axes (y up) at the boundary. Wind arrives from the simulation in NED (down positive); convert it once, as `_render_wind` already does.
- `n̂_lens` is the camera's forward axis. A camera looking up in the rain or flying forward collects drops; one facing downwind collects few.
- Arrivals per tick are Poisson with the seeded RNG; each drop diameter is sampled from the Marshall–Palmer exponential (clamped 0.5–4 mm) and mapped to a screen radius by a per-view `lens_scale`.
- `gain_view` is the explicit art gain. It is documented as an estimate, never as measured lens physics.

### 6.4 Drop behaviour (CPU pool, bounded)

Each drop: screen position, volume, radius, velocity, state (`beaded`, `sliding`), age, seed. Pool caps: Low 24, Medium 64, High 128, Ultra 192.

| Rule | Model | Visual result |
| --- | --- | --- |
| Pinning | A drop stays put until the driving force exceeds a pinning force ∝ radius (contact-angle hysteresis) | Small drops bead; big ones run |
| Driving force | `F = m·g_screen + k_air·‖u_air‖²·r²·dir_air` | Gravity projected into screen space (a rolled camera makes drops run sideways); air pushes drops radially away from the focus of expansion when moving forward |
| Focus of expansion | Screen projection of the camera-relative velocity direction | Drops stream outward from where the camera is heading, like MotoGP and real FPV footage |
| Merge | Spatial hash; overlapping drops merge (volume add, `r = ∛`), momentum conserved | Runners grow and accelerate |
| Trail | A sliding drop sheds micro-drops behind it at a rate ∝ speed; they bead | The "track" left on glass |
| Blow-off | When `‖u_air‖` exceeds a threshold, beaded small drops detach and vanish with a short streak | Clean lens centre at high speed |
| Evaporation / rain stop | Volume decays slowly; when rain stops, drops linger 20–60 s | Rain ending reads naturally |
| Lightning | Specular highlight and refraction brightness follow the flash radiance | Drops sparkle with each flash |

### 6.5 Drop rendering

Per instance (`MultiMeshInstance2D`, custom data = radius, elongation, wetness, focus):

- Shape: egg-shaped SDF with a tail along the slide direction.
- Normal: spherical-cap approximation, `n = (p, √(1−|p|²))`.
- Refraction: sample the screen texture at `SCREEN_UV − p·k·radius` so the image inside a drop is **inverted and minified**, like a real ball lens (the Codrops observation).
- Defocus: `textureLod(screen_texture, uv, focus_lod)` per view (pilot "glasses" heavily blurred; FPV nearly sharp).
- Rim: darker edge from total internal reflection, thin bright specular from the brightest sky direction.
- Micro-wetness: one tiled CC0 normal texture at low opacity across the frame when `R > 0`, scaled by quality. Off at Low.

### 6.6 Rain streaks in 3D (near-camera rain)

Lens drops without visible falling rain look wrong. A particle box (about 30 × 20 × 30 m) follows the camera in world space. It uses `GPUParticles3D` or a `MultiMesh` streak field, whichever LENS-07 measures cheaper on Compatibility. It emits velocity-aligned thin quads (`transform_align` to velocity) with velocity `v_rain`, so streak length and angle come from the camera's own motion. Amount scales with `R` and quality; heavy rain is shown by a little more density and a thicker haze in the [atmosphere](../../app/render/atmosphere.gd), not 50 000 particles. Ground collision (`GPUParticlesCollisionHeightField3D`) is optional at High only and must be verified on Compatibility before use. Splashes and puddles belong to FW.

### 6.7 Storm and tornado coupling

- **Electrical storm:** when the storm cell covers the field (LENS-06 coverage), rate bursts follow the cell; flashes light drops and streaks.
- **Gust fronts:** sudden wind changes shear drops sideways for a moment; this comes from the existing wind, not a new law.
- **Tornado (after FW-89):** rain sheets nearly horizontal near the funnel, heavy drop load, dust/debris grime from effect 3, strong sideways shear. All read from FW-89's accepted field; this plan adds no wind.

---

## 7. Effect 3 — Impact grime (mud, dust, grass, water, cracked lens, oil film)

### 7.1 Why this one

- It shares the lens stack: same layer, pool, renderer and lifecycle, at little extra cost.
- It uses evidence the repository already publishes:
  - the contact point, looked up through the crash director's `surface_at` (contact events carry no ground material);
  - `measure.speed_mps`;
  - the CR-08b severity class;
  - the engine source kind;
  - lake contacts, which do carry `material`.
- It is what real FPV crash footage looks like, and it makes the onboard/FPV views feel physical.

### 7.2 Triggers and looks

| Trigger | Condition | Look | Persistence |
| --- | --- | --- | --- |
| Grass contact | Hull/gear/prop contact on grass, camera on aircraft or within ~6 m | 2–6 green blade sprites (CC0), slight blur | Until reset, or blown off above ~20 m/s |
| Soil / mud | Contact on soil, wet ground (rain > 0 raises probability) | Opaque brown splats with refractive edges | Until reset |
| Dust / gravel | Contact on dry dirt, gravel or asphalt slide | Low-contrast veil (a contrast loss, like the sun veil), fine speckles | Decays over 10–20 s |
| Water | Lake contact (`source == "lake"`) or prop spray in rain | Inject water drops into the rain pool | Normal drop rules |
| Cracked lens | FPV/onboard camera, terminal contact at or above C2 severity | One crack overlay (CC0) with chromatic fringing along the crack | Until reset |
| Glow oil film | Glow engine running, onboard camera behind the exhaust | Very slow build-up of haze and bloom around bright sources | Until reset; cap at subtle |
| Pilot-near crash | Impact within ~5 m of the pilot | Dust veil + 1–2 specks; no blood unless a person was hit | Decays |

### 7.3 Alternatives considered for the third effect

| Candidate | Verdict |
| --- | --- |
| Analog FPV video breakup (snow, rolling lines, colour loss) | Very evocative, but the simulator has **no radio-link model** ([osd_model.gd](../../app/vehicles/multirotor/osd_model.gd) states it shows no RSSI). Faking breakup would misrepresent range. Revisit once a link model exists. |
| Lightning flash-blindness | Already partly covered by SUN optics and FW-84; full-screen flashes conflict with photosensitivity rules. |
| Heat haze behind turbines/exhaust | Good, but it is a 3D-space refraction effect, not a lens effect; belongs with turbine/smoke owners. |
| Speed lines / motion blur | Arcade look that conflicts with readable flight. |
| Condensation / fogged lens | Rare in RC flying; low value. |

---

## 8. Settings, presets and accessibility

### 8.1 Settings (menu-owned UI, persisted preferences)

| Setting | Values | Default |
| --- | --- | --- |
| Lens effects (master) | Off / On | On |
| Lens effects quality | Low / Medium / High / Ultra | From the graphics preset recommendation |
| Impact effects | Off / Classic curtain / Lens splatter | Classic curtain (owner decision D1, 2026-11-12) |
| Impact colour | Red / Dark / Desaturated | Red |
| Rain on lens | Off / On | On |
| Glasses in pilot view | Off / On | Off |
| Grime and lens damage | Off / On | On |
| Keep screen centre clear | Off / On | Off (On reduces curtain depth to 60 % and keeps a radial clear zone) |

### 8.2 Quality tiers

| Tier | Drops cap | Micro-wetness | Streak particles | Trails | Grime stamps cap | Curtain mip taps |
| --- | --- | --- | --- | --- | --- | --- |
| Low | 24 | off | 1 500 | off | 8 | 1 |
| Medium | 64 | on (half-res) | 4 000 | on | 16 | 1 |
| High | 128 | on | 8 000 | on | 24 | 2 |
| Ultra | 192 | on | 12 000 + ground collision | on | 32 | 2 |

Graphics settings never change physics. Turning a tier down frees its buffers.

### 8.3 Accessibility and comfort

- **Photosensitivity:** no full-screen flash; the edge pulse stays below WCAG 2.3.1's three-flashes threshold ([W3C Understanding 2.3.1](https://www.w3.org/WAI/WCAG21/Understanding/three-flashes-or-below-threshold.html)).
- **Playability:** the curtain never fully covers the screen for more than 1.5 s unless the flight has ended; the "keep centre clear" option exists for players who keep flying after a strike.
- **Content:** blood can be turned off without affecting anything else. Rating implications (human-injury blood) are an owner and release decision (D1), recorded in [DECISIONS.md](../DECISIONS.md) when made.
- **Motion comfort:** air-shear drop motion is bounded in speed to avoid strobing streaks at 30 FPS.

---

## 9. Performance budget and measurement

Targets are planning budgets, to be measured on real hardware in LENS-12 (1080p first):

| Case @ 1920×1080 | GPU budget | CPU budget (main thread) |
| --- | --- | --- |
| All channels on, no events, no rain | ≤ 0.02 ms (nothing drawn) | ≤ 0.01 ms |
| Moderate rain, Medium | ≤ 0.30 ms | ≤ 0.10 ms (pool sim + MultiMesh upload) |
| Heavy rain, High | ≤ 0.50 ms | ≤ 0.20 ms |
| Curtain active | ≤ 0.40 ms during 3–6 s | ≤ 0.02 ms |
| Grime, 24 stamps | ≤ 0.15 ms | ≤ 0.02 ms |

Rules:

- Warm the shaders of **enabled** channels only (disabled channels compile and allocate nothing) in the flight-setup warm-up, as [CR-22c-R1](../research/crash-damage-investigations/CR-22c-R1/README.md) does for crash shaders; verify no first-hit hitch with the debug bridge hitch tracker.
- Upload drop data with one `MultiMesh.buffer` write per frame; no per-drop node.
- Measure with the [debug bridge](../../tools/debug/README.md) frame diagnostics and profiler, not with ad-hoc probes. Never benchmark alongside other GPU work.
- Upscaling (FSR/MetalFX) runs on the 3D image; the canvas layer draws at output resolution, so drops stay crisp at 4K. Verify that the screen texture read happens after upscaling on each path.

---

## 10. Ownership and seams

| Seam | Owner | What this plan needs |
| --- | --- | --- |
| `app/main.gd` flight assembly | Main line | Instantiate `LensStack`, pass session, camera rig and settings; connect reset |
| Contact events, crash cause card | Crash (CR) | Read-only use of `contact_events()`; optional safety line on the cause card |
| Camera rig, view ids, CAM-12 distortion | Camera views (CAM) | View id and per-frame camera pose; ordering with CAM-12 |
| Weather presets, storm cell coverage, tornado | Field World (FW) | **New precipitation channel** (LENS-06); tornado field (FW-89) |
| People, collision inventory | Scenery (SC-HUM, LU) | Read-only; LENS-05b proxy only with their approval |
| Physics (pilot proxy) | Physics / SF | LENS-05b only; phase 1 has no physics change |
| FPV quad scene and session | Multirotor owner | Contact stream adapter if needed; FPV camera hook |
| Preferences, settings UI, i18n (8 locales) | Menu / UI | Settings rows and translations |
| Stingers (impact thud, tinnitus option) | Audio (AUD) | Optional; not required for the visual slices |
| Graphics presets and hardware recommendation | Visual quality (VQ) / performance (PT) | Tier mapping and measurement |

---

## 11. Steps and acceptance

Estimates are for one experienced developer, planning numbers only.

| Step | Scope | Acceptance (evidence) | Est. |
| --- | --- | --- | --- |
| **LENS-00** | Research record: sources above, Atlas–Ulbrich coefficients, safety-code citation, CC0 asset intake with URLs, hashes and licences under `docs/research/lens-effects/LENS-00/`; register prefix and paths | Record merged; every shipped asset has provenance; no NC/SA-derived code | 1 d |
| **LENS-01** | `LensStack`, `LensLayer` (layer −9), settings resolution, zero-allocation when off, reset/pause/checkpoint lifecycle, CLI flags, debug-bridge triggers (`lens.blood <s>`, `lens.rain <mmph>`, `lens.grime <material>`). **Spike:** measure back-buffer copy count with the sun afterimage present, and whether `textureLod` blur works on the screen texture, on Compatibility, Mobile and Forward+ | Lifecycle tests: off allocates no nodes; reset clears; pause freezes; capture/trace routes allocate nothing; parses. Spike results recorded with GPU timings at 1080p | 3 d |
| **LENS-02** | `ImpactTrigger`: pure admission from fixed-wing contact events (person kind, new lifecycle, `measure` energy/speed → strength, de-duplication, view factor) | Unit tests with synthetic events: brush below threshold, prop strike, repeat within 2 s, replay identity | 1.5 d |
| LENS-02b | Typed multirotor strike record (obstacle id, kind, point, speed), owned by the multirotor and physics owners, because `app/sim`/`app/physics` are pinned | Their tests; LENS then consumes it unchanged | owners |
| **LENS-03** | Classic curtain shader + state machine + splash stamps + warm-up | 1080p captures at fixed `sim_clock` steps (0, 0.3, 0.8, 1.5, 3, 5 s) in day, dusk and night. Measured checks: the centre stays clear ≥ 0.6 s; ≥ 90 % coverage lasts ≤ 1.5 s; no hitch on the first hit. Owner review | 3 d |
| **LENS-04** | Lens-splatter style; pilot-view vignette fallback; impact colour options | Captures per view; colour-vision check (simulated deuteranopia) | 1.5 d |
| **LENS-05** | Pilot strike detector (swept capsule vs hull points); placement audit of `person_pilot` near the player's station; de-duplication | Unit tests: head-on pass at 40 m/s detected at 20, 60 and 144 FPS; a near miss at 0.5 m is not detected; a neighbouring pilot strike does not double-fire | 1.5 d |
| LENS-05b | Optional physical `person_player` proxy | Physics owner approval; golden-flight check; separate PR | — |
| **LENS-06** | FW precipitation channel contract (`rate`, `coverage`), presets updated by FW | Contract tests in FW; LENS reads it; debug override removed from defaults | FW: 1–2 d |
| **LENS-07** | Near-camera rain streaks, velocity-aligned (`GPUParticles3D` vs `MultiMesh`, measured) | Captures at 0, 15, 40 m/s; Compatibility, Apple Mobile and Forward+ checks; budget | 2 d |
| **LENS-08** | Rain driver + drop pool + MultiMesh drop renderer + micro-wetness; CAM-12 layer agreement | Unit tests: rate ∝ airspeed into the rain; zero rate when there is no rain; merges conserve volume; same arrivals for the same seeded inputs. Captures per view; budget | 4 d |
| **LENS-09** | Storm coupling (flash, bursts, gust shear); tornado hooks stubbed until FW-89 | Night electrical-storm flown review | 1.5 d |
| **LENS-10** | Grime: grass, soil/mud, dust veil (surface from `surface_at` at the contact point), water injection from lake events | Tests: surface → stamp kind; reset clears; captures after scripted contacts | 2.5 d |
| **LENS-11** | Cracked lens, glow oil film | Captures; FPV owner review | 1.5 d |
| **LENS-12** | Qualification: 1080p budgets on target hardware, then 1440p/4K, then 720p; Apple/ANGLE `dFdx` check; accessibility review; i18n | Measured table in the research record; Good Enemy review; owner play review | 2 d |

Suggested PR boundaries: LENS-00+01, 02+03, 04+05, 06 (FW), 07, 08, 09, 10+11, 12.

---

## 12. Verification strategy

Follow the repository's [verification scope](../tools/shared.md#verification-scope): focused checks while editing; broad gates only for cross-cutting steps.

| Layer | Check |
| --- | --- |
| Pure laws (`ImpactTrigger`, `RainDriver`, drop pool, `GrimeTrigger`, pilot detector) | Focused `app/tests/test_lens_*.gd` through the checked runner |
| Lifecycle | Off/on/reset/pause/checkpoint tests; capture and trace routes allocate no lens nodes |
| Shader rule | No `TIME` in any lens shader (existing `app/test.sh` check) |
| Determinism | Replay a recorded `.orfl` twice with lens effects on; compare the blood/grime event lists (tick, id, strength). Drop pools are compared only on a fixed-fps capture route with a fixed view |
| Visual | Debug-bridge screenshots at fixed sim times in every view; 1080p first |
| Performance | Debug-bridge frame diagnostics/profiler; hitch tracker for the first strike |
| Physics unchanged | Golden flights untouched; `solver_changed == false` in flight-log comparisons (no physics files edited) |

---

## 13. Risks

| Risk | Mitigation |
| --- | --- |
| Blood changes the product's tone or rating | Separate content switch; owner decision D1 before default-on; safety-lesson framing |
| Drops look like stickers | Refraction with inversion, defocus, rim and behaviour (bead/slide/merge/blow-off) are mandatory, not polish |
| Full-screen cost on low-end GPUs | Instanced drops; curtain only while active; tiers; nothing allocated when off |
| First-strike hitch | Shader warm-up at flight setup |
| Rain without local precipitation looks fake | LENS-06 contract and 3D streaks ship before drops are enabled by default |
| Copying a licence-restricted shader | LENS-00 provenance gate; Heartfelt explicitly excluded |
| The quad has no typed strike evidence | Phase 1 fixed-wing only; LENS-02b with the pinned-file owners |
| Second full-screen copy (sun afterimage + lens) | LENS-01 spike measures it; merge layers in pilot view if needed |
| Translation collisions (all eight `.po` files are being edited by another track) | Add strings in one coordinated i18n pass at LENS-12 |
| Pilot strike without physics looks odd (aircraft passes through) | Honest card text; LENS-05b as the physical fix |

---

## 14. Owner decisions

| ID | Question | Proposal |
| --- | --- | --- |
| D1 | Is blood on by default? | **Decided by the owner, 2026-11-12:** on, "Classic curtain", with an Off switch (Settings → Lighting → Impact effects) |
| D2 | Does striking the pilot end the flight? | Phase 1: no (presentation only). Phase 2 with LENS-05b: yes, as a terminal contact |
| D3 | Glasses in pilot view by default? | Off |
| D4 | Safety line after a person strike? | Yes, with a cited safety code |
| D5 | Which presets get local rain first? | `overcast` (light), `prestorm` (moderate bursts), `electrical_storm` (heavy when the cell covers the field) |
| D6 | Cracked lens for fixed-wing onboard cameras too? | FPV only at first |
| D7 | Audio stinger on pilot strike? | Optional, AUD-owned, off until auditioned |

---

## 15. Glossary

- **Lens stack** — the single canvas layer and controller that hosts all three channels.
- **Curtain** — the stylised full-screen blood sheet.
- **Focus of expansion** — the screen point the camera is moving toward; drops stream away from it.
- **Pinning** — a drop staying put on glass until its driving force overcomes surface hysteresis.
- **Art gain** — an explicit, documented multiplier from a physical driver to what reads well on screen.

---

## 16. Implementation status (2026-11-12)

### What exists

| Step | Delivered | Where |
| --- | --- | --- |
| LENS-01 | Lens stack on `CanvasLayer` −9 with lazy nodes (nothing allocated until a channel draws), reset/restore floor tick, pause hold, CLI flags, debug helpers (`debug_blood`, `debug_rain`, `debug_grime`, `debug_oil`, `snapshot`) | [lens_stack.gd](../../app/render/lens/lens_stack.gd), [lens_settings.gd](../../app/render/lens/lens_settings.gd) |
| LENS-02 | Pure admission of fixed-wing contact events (person, ground, foliage, obstacle, lake) | [impact_trigger.gd](../../app/render/lens/impact_trigger.gd) |
| LENS-02b (interim) | The FPV quad still reports only `crashed(reason)`. Presentation asks the installed obstacle inventory, read-only, what lies at the accepted crash position (`CollisionWorld.nearby`). A typed strike record from the multirotor and physics owners remains open. | [multirotor_scene.gd](../../app/vehicles/multirotor/multirotor_scene.gd) `_lens_crash` |
| LENS-03/04 | Classic curtain (sheet, meniscus runners with round beads, Beer–Lambert absorption, refraction, drain residue, drying) and lens splatter; red/dark/desaturated; clear-centre option | [lens_film.gdshader](../../app/render/lens/lens_film.gdshader), [lens_stamp.gdshader](../../app/render/lens/lens_stamp.gdshader) |
| LENS-05 | Presentation-only pilot strike: swept segment against the pilot capsule, active within 15 m of the station | [pilot_strike.gd](../../app/render/lens/pilot_strike.gd) |
| LENS-06 (interim) | Local rain rate per sky preset, owned here until the FW precipitation channel exists: `prestorm` 1.6 mm/h, `electrical_storm` 14 mm/h, others dry; `--lens-rain-mmph` overrides | [rain_model.gd](../../app/render/lens/rain_model.gd) |
| LENS-07 | World-anchored rain streaks (MultiMesh, refracting the scene behind them); the volume grows in powers of two with the pilot view's auto-zoom | [rain_streaks.gdshader](../../app/render/lens/rain_streaks.gdshader) |
| LENS-08 | CPU drop pool (pinning, gravity on the image plane, airflow from the focus of expansion, merging, trails, blow-off, drying), ball-lens drop shader, and a fine-bead wetness layer | [drop_pool.gd](../../app/render/lens/drop_pool.gd), [lens_drop.gdshader](../../app/render/lens/lens_drop.gdshader) |
| LENS-09 | Lightning level (FW-84) brightens drops and streaks | `_lens_flash` in [main.gd](../../app/main.gd) |
| LENS-10/11 | Mud, grass, dust veil, lake spray, cracked lens (close-up/FPV, ≥ 12 m/s), glow oil film (close-up view) | [lens_stamp.gdshader](../../app/render/lens/lens_stamp.gdshader), [lens_film.gdshader](../../app/render/lens/lens_film.gdshader) |
| Settings | Six rows at the end of Settings → Lighting (quality Automatic by default), saved in `display.cfg` `[lens]`; "Glasses in pilot view" stays a file/CLI preference because the page has no room for a seventh row at 1080p | [display_preferences.gd](../../app/app_state/display_preferences.gd), [settings_screen.gd](../../app/ui/settings_screen.gd) |

### Reused work and licences

Following the owner's instruction not to reinvent proven techniques:

- **Splat shapes:** real photographed ink splatters from "~100 grunge brushstrokes and splatters set" by Dino0040 ([OpenGameArt](https://opengameart.org/content/100-grunge-brushstrokes-and-splatters-set), CC0). Eight brushes are packed into one 8-bit atlas (184 KB) by [build_splat_atlas.py](../../tools/lens/build_splat_atlas.py) with a recorded archive hash; provenance in [sources.json](../../app/assets/lens/sources.json). The Kenney Splat Pack (CC0) was the first choice, but its download requires a browser session and was not automated.
- **Cracked lens:** the radial Voronoi technique of "Impact Glass Shader" by Lord0Sanz ([godotshaders](https://godotshaders.com/shader/impact-glass-shader/), MIT).
- **Fine wet beads:** the `StaticDrops` layer of "Rain on Glass" by Gerardo LCDF ([godotshaders](https://godotshaders.com/shader/rain-on-glass/), MIT). Both MIT notices are in [IMPACT_GLASS_LICENSE.txt](../../app/render/lens/IMPACT_GLASS_LICENSE.txt).
- **Drop shape:** Inigo Quilez's 2D uneven-capsule distance function (MIT).
- **Behaviour:** drops bead, run and are pushed outward at speed, as in Shawn Hargreaves' MotoGP write-up; the ball-lens inversion follows the Codrops study. BigWings' *Heartfelt* (CC BY-NC-SA) was not used.

### Verification (2026-11-12, Windows, Godot 4.8-beta2, Compatibility, RTX 3090, 1920×1080)

| Check | Result |
| --- | --- |
| [test_lens_effects.gd](../../app/tests/test_lens_effects.gd) | 64 checks, 0 failed (one buffer-layout check is skipped under the headless dummy renderer and was verified with the real renderer). Covers settings, the rain law and worked example, triggers, pilot sweep at 20/60/144 FPS, drop-pool conservation and pinning, the no-TIME rule, preference save/load and lifecycle |
| [test_lens_person_strike.gd](../../app/tests/test_lens_person_strike.gd) | 8 checks, 0 failed. A real FlightSession flies into a spectator capsule; the accepted event starts the curtain once; a restored tick does not replay it |
| Affected suites | `test_settings_ui`, `test_ui_language` (all eight catalogues), `test_display_preferences`, `test_lighting_settings_ui`, `test_shadow_settings_ui`, `test_ui_settings_integration`, `test_advanced_graphics_settings`, `test_camera_settings`, `test_ui_pause`, `test_mr_activity`, `test_mr_activity_race`, `test_mr_camera`, `test_mr_osd`, `test_accident_integration`, `test_crash`: all passed |
| Visual review in the running app | Curtain (strike and drain), lens splatter, rain in the electrical-storm preset (pilot, chase and FPV), mud and grass, cracked lens. Screenshots stay under `tmp/` and are not committed |
| Cost, FPV in 14 mm/h rain | GPU median 2.04 ms with the lens vs 1.92 ms without (+0.13 ms). Root CPU 2.5 ms vs 2.0 ms. Both were measured before the review fixes: hidden-film skip, pilot watch radius, allocation-free drop grid, skipped uploads and the CPU-computed crack points. Vsync makes both readings noisy. A cracked lens and weaker GPUs are not yet measured |
| Physics | No file under `app/sim/` or `app/physics/` changed |

### Independent review (2026-11-12)

A second Good Enemy pass reviewed the code read-only. The fixes below were verified against the source:

- Rain streaks no longer jump when wind or the rain rate changes: the fall is integrated on the CPU.
- The cracked lens uses CPU-computed Voronoi points; it no longer runs a trigonometric and noise loop per pixel.
- Drop and stamp refraction now account for the UI's canvas stretch on 1440p and 4K screens (`canvas_scale`).
- Each event reseeds the random stream. The plan's determinism text now says what a replay repeats.
- The splat atlas loads only with the stamp channel.
- Enabled channels warm their shaders at flight setup with an invisible draw.
- The drop grid allocates nothing per frame, and the pool skips MultiMesh uploads when nothing moved.
- Ticks without contact events skip the detached copy, and the admitted-event set is trimmed with hysteresis.
- Crash grime no longer fires twice. Splatter dries, and reset clears dryness.
- The streaks' art speed factor is separate from the physical arrival law.
- Smoothstep edges are ordered, the German tooltip is fixed, and Inigo Quilez is credited in the licence file.

### Second round (2026-11-12)

| Area | Change |
| --- | --- |
| Coverage | The helicopter route now has the lens (rain, grime, and blood when a crash point lies at a person). The quad and helicopter share `LensStack.strike_from_crash`. |
| Options | Lens quality **Automatic** is the default. It follows Scene detail: low → Low, medium → Medium, high → High, extreme → Ultra. Settings changes made during a flight rebuild the lens at once on the airplane, quad and helicopter routes. |
| Feedback | A person or pilot strike shows a five-second caption on the lens layer with a safety lesson ("Never fly over or toward people."), in all eight languages. |
| Detail | Rain on the glass washes blood away: the curtain drains up to 1.6× faster and splats rinse off sooner. |
| Performance | The curtain's slope comes from screen derivatives (one curtain evaluation per pixel instead of three). Wet-bead slopes are computed only inside a bead. Drops reach the GPU in one MultiMesh buffer upload instead of two engine calls per drop; the layout was verified against `get_instance_transform_2d` with the real renderer. The active view is read once per frame. |
| Hygiene | The GDScript compiler warnings in the lens files are fixed (parameters named `seed`, an unused variable). |

A second read-only Good Enemy pass reviewed this round. It found no crasher and no simulation write; the fixes below are applied and tested:

- The caption always draws above the curtain.
- Lazily created materials receive the canvas scale.
- A lens rebuilt after a crash does not replay it.
- An Automatic lens rebuilds when Scene detail changes.
- A pilot strike already shown by the sweep is not repeated by the helicopter's crash lookup.
- The airplane caption no longer duplicates into the diagnostics line.
- The helicopter grades the strike by the impact's normal speed.
- The accumulated rain travel is rebased before float32 precision suffers.
- The bench's off baseline hides the lens layer.
- The derivative-based curtain slope was checked visually on Compatibility only; Mobile and Forward+ remain part of LENS-12.

Cost benchmarking was deferred: other tracks' Godot sessions were sharing the GPU (AGENTS.md: no benchmarks alongside competing workloads). A first run also left `time_scale` at 0.05, which produced a misleading 1 fps reading. [tools/lens/bench.py](../../tools/lens/bench.py) drives the debug bridge, so the 1080p table can be filled on an idle machine.

### Still open

- LENS-06: the Field World precipitation channel (rate and coverage per preset) replaces the interim mapping.
- LENS-02b and LENS-05b: a typed quad strike record, and a physical pilot proxy; both belong to the physics owners.
- Qualification on Mobile (Apple Silicon) and Forward+ (Product High); 1440p/4K and 720p captures; a low-end GPU budget run.
- Tornado coupling (after FW-89), the AUD stinger (D7), and a safety-code line after a person strike (D4).
