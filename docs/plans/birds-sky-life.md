# Birds: species, behaviour and sky life

2026-10-24 · Revision 2 · **Planning draft** · Step prefix: **SC-BIRD** (Scenery subtrack; not yet in the [registry](../README.md#tracks-plans-and-step-ids)) · Gate: **SC**

**Status:** proposal only. Nothing is implemented. Owner decisions D1–D9 (§10) are open. Revision 2 adds the [web survey](../research/scenery-investigations/06-birds-sky-life-survey.md) (29 searches, 5 page reads): measured behaviour numbers, a 3-triangle speck, MultiMesh density control, a texture-free murmuration fallback, ground birds, seasons and an aircraft-as-predator startle model.

**Owner:** Scenery and field life ([SCENERY-PLAN](../SCENERY-PLAN.md)), which owns today's SC-20 flock. Coordination: VQ/LU (scene budget, Scene detail preset, aerial perspective), FW/TOD (sun, sky, calendar, weather), M5 (wind, future spatial thermals), AUD (calls, engine loudness), UI (preference), NR (optional events), CR/physics (bird strike, only if D4 is accepted).

**Proposed ownership:** `app/scenery/birds*.gd|gdshader` (existing), new `app/scenery/birds/`, `app/data/scenery/birds/`, `tools/scenery/birds/`, `app/tests/test_birds_*.gd`, evidence in `docs/research/scenery-implementation/SC-BIRD-*/`. Shared hooks stay with their owners.

## 1. Goal

Make the sky above the field feel alive and believable: species with real silhouettes, gaits and behaviour (vultures circling in thermals, a kestrel hanging in the wind, swallows skimming the grass, a winter murmuration at dusk, pigeons flushing from the runway). Fit it into the Compatibility renderer, keep it deterministic, and never make the model airplane harder to see.

Non-goals: skinned animals everywhere, an ornithology simulator, birds that change flight physics by default.

## 2. Current baseline (SC-20)

| Fact | Where |
| --- | --- |
| 12 identical "V" birds, 2 triangles, 0.9 m span, black albedo | [birds.gd](../../app/scenery/birds.gd) |
| One analytic loop (radius 140 m, 128 s lap) at 32 m, NE of the pilot; 4 Hz flap in the vertex shader | [birds.gdshader](../../app/scenery/birds.gdshader) |
| Stateless: position and flap depend only on `sim_clock` (wraps at 1024 s; frequencies are k/1024 Hz) | [shader_clock.gd](../../app/render/shader_clock.gd) |
| `INSTANCE_CUSTOM` already works in Compatibility (with `use_colors` set) | [birds.gd](../../app/scenery/birds.gd) |
| On in the Home launch profile; off in reference captures (`OPENRC_SCENERY_BIRDS=off`) | [scenery.gd](../../app/scenery/scenery.gd), [capture.sh](../../app/capture.sh) |
| Budget `scenery_Birds`: 1,000 primitives / 2 draws per view class | [scene_budget.json](../../tools/scenery/scene_budget.json) |
| A calendar date exists (`{year, month, day, hour}` for sun and moon), so seasons are possible | [lunar.gd](../../app/render/world/lunar.gd), [moon_config.gd](../../app/environment/moon_config.gd) |
| Wind presets are uniform; "Updraft" is a uniform vertical gust, not a spatial thermal | [wind_config.gd](../../app/physics/wind_config.gd) |

Hard constraints: Godot 4.7 **Compatibility** (no compute shaders, no particle trails, no alpha-to-coverage; low base cost, high scaling cost); web export; no shader `TIME`; captures repeat byte for byte; vertical pilot FOV 50° with auto-zoom down to 6° ([spec.gd](../../app/spec.gd)).

## 3. How big a bird is on screen (1080p first)

`px = span × 1080 / (2 d tan(fov/2))` ([`PilotCamera.projected_px`](../../app/render/pilot_camera.gd)). At FOV 50°: `px ≈ 1158 · span / d`.

| Bird | Span | Typical distance | px at 1080p | px at 2160p |
| --- | --- | --- | --- | --- |
| Griffon vulture | 2.3–2.8 m | 300 m / 1,000 m | 10 / 3.0 | 20 / 6.0 |
| White stork | ~1.9 m [est] | 250 m | 8.8 | 17.6 |
| Red kite | ~1.8 m [est] | 120 m | 17 | 35 |
| Kestrel (hovering) | ~0.75 m [est] | 40 m | 22 | 43 |
| Barn swallow | ~0.33 m [est] | 15 m | 25 | 51 |
| Starling (one bird) | ~0.4 m [est] | 300 m | 1.5 | 3.1 |
| Murmuration (whole cloud) | ~150 m [est] | 600 m | ~290 | ~580 |
| Ugly Stik 60 (comparison) | ~1.6 m | 225 m | 8.2 | 16.5 |

**Consequences.** (1) A vulture or stork a few hundred metres away is the size of the model: silhouette and gait, not size, tell them apart. (2) Auto-zoom at 6° magnifies by tan 25°/tan 3° ≈ **8.9×**, so a bird near the line of sight to the model can reach 50–200 px. LOD uses projected pixels, not distance. (3) 4K doubles every value. (4) Starlings read only as a cloud: density matters, shape does not.

## 4. Species and behaviour

Numbers come from the [survey §3](../research/scenery-investigations/06-birds-sky-life-survey.md#3--bird-biology-numbers-for-the-species-data) unless marked [est]. Wingbeat frequencies remain [est, U] until SC-BIRD-00 reads the Bruderer/Pennycuick tables; shader frequencies are then rounded to k/1024 Hz.

| Species (es) | Silhouette keys | Behaviour and numbers | When / where |
| --- | --- | --- | --- |
| **Griffon vulture** (buitre leonado) | Plank wing, 7 deep fingers, short square tail | Kettles: circle at ≈ 9 m/s (minimum sink), bank 25–35° low in the climb, shallower higher: r ≈ 12–18 m, 8–12 s per turn; glide out at ≈ 14 m/s, slowing ≈ 3 m/s before the next thermal | Warm daytime sun; ridges, warm fields |
| **White stork** (cigüeña blanca) | Black flight feathers, neck and legs extended | Kettles with **a wandering leader** that leaves and re-enters to find the core; followers lag, leave lower and flap more (Flack et al. 2018) | Day; season by calendar [est] |
| **Golden / booted eagle** (águila real / calzada) | Long broad fingered wing, slight dihedral | Soaring, long glides, rare stoop | Midday; ridges |
| **Red / black kite** (milano real / negro) | Long angled wing, deeply forked tail | **Constant tail twisting**, even in light wind; low glides over open, short vegetation | Day; open fields |
| **Common buzzard** (ratonero) | Broad wing, short fan tail | Soaring and circling | Day |
| **Kestrel** (cernícalo) | Pointed wing, long tail | Wind hover with a fixed head (< 5 mm). Light wind: flapping hover; moderate: flaps mixed with short glides (≈ ¼ cheaper); ≈ 7–10 m/s with slope or edge lift: **hanging** without wingbeats (Videler); then a drop | Over grass, 5–30 m |
| **Grey heron** (garza real) | Arched wing, folded neck, trailing legs | Slow deep flaps, straight crossings | Lake landscapes |
| **Gulls** (gaviotas) | Narrow angled "M" wing | Flap-glide; lake circuits; mob drones in nesting season | Lake / coast |
| **Pigeons, jackdaws** (palomas, grajillas) | Compact / black fingered | Flock circuits; jackdaws mob raptors; **flush from the ground** when approached | Buildings, treeline, runway grass |
| **Barn swallow** (golondrina) | Swept wing, forked tail | Low coursing 1–8 m [est] at 6–10 m/s (radar mean 8 m/s), using the near-ground wind gradient | Day, warm season |
| **Common swift** (vencejo) | Scythe wing | Screaming parties of 10–20 round buildings on summer evenings; after sunset **climb fast out of sight** (to ≈ 2.5–3 km) | Summer evening |
| **Starling** (estornino) | Small triangle | **Murmuration**: 7 topological neighbours; mean display ≈ 26 min; grows Oct → early Feb, ends Mar; with a raptor present (≈ 30 % of displays) it grows and ends in a **mass dive into the roost** | Oct–Mar, around sunset, over reeds or trees |
| **Bats** (murciélagos) | Small, jerky | Erratic flutter; emergence ≈ 17–55 min after sunset (optimum ≈ 36 min), earlier when calm and warm | Late dusk, warm season |

Gait rule from body mass (Tobalske): birds above ~300 g never flap-bound; 35–158 g flap-glide when slow and flap-bound when fast; small low-aspect birds flap-bound. The data validator enforces it.

Real bird–model interactions (anecdotal but repeated): gulls and swallows circle or hit drones; a golden eagle grabbed a 2.5 m model glider after 20 years of ignoring gliders in the same thermals; sea-eagles attacked ridge-soaring models; raptors strike from above, and pilots escape by climbing. RC soaring pilots call hawks "lift-finding heroes".

## 5. Architecture

### 5.1 Three visual tiers, chosen by projected pixels

| Tier | When | Representation | Cost |
| --- | --- | --- | --- |
| **T0 speck** | < 4 px | **3 triangles** (body keel + two wings; three.js birds layout), wing tips flap, species tint | One MultiMesh, 1 draw for all specks |
| **T1 silhouette** | 4–40 px | **Parametric planform mesh** per species, 16–48 triangles, from our generator: span, aspect, arm/hand split, finger count and depth, tail shape (forked, wedge, fan, square), neck/legs. Joint weights in vertex colour | One MultiMesh per species group, ≤ 6 draws |
| **T2 near** (optional, D5) | > 40 px (kestrel, swallow, auto-zoom) | A downloaded CC0 model (Quaternius eagle, BlendSwap CC0 seagull) re-weighted to the same rig; VAT only if the rig is not enough | ≤ 8 instances |

No free CC0 vulture, stork, kite or kestrel model exists ([survey L3](../research/scenery-investigations/06-birds-sky-life-survey.md#6--assets-and-audio-licences)), so the generator is required for those species. Tier switches use `visibility_range` hysteresis or vertex collapse in the shader. Flipbook billboards, octahedral impostors and skinning are rejected ([survey §7](../research/scenery-investigations/06-birds-sky-life-survey.md#7--alternatives-considered)).

### 5.2 Shader rig instead of skeletons

Wing vertices carry shoulder, wrist and tip weights in `COLOR`. The vertex shader rotates them round two hinges with a phase lag (the hand trails), folds the hand on the upstroke and curls the tips when soaring. Tail vertices twist and fan. Rules taken from Godot's fish tutorial: masks are `smoothstep` along the span; rotations are blended with `mix()` (multiplying by the mask shrinks the mesh); per-instance phase is `TAU · INSTANCE_CUSTOM.w`. Symmetry uses `abs(x)` as SC-20 does. **Flap rate rises with path speed** (three.js birds), so diving or chasing birds beat faster.

| Gait | Parameters | Species |
| --- | --- | --- |
| Flap | Frequency, amplitude, down/up ratio, hand lag | Pigeon, heron, stork |
| Glide / soar | Dihedral, tip curl, small sway; rare flap bursts | Vulture, eagle, stork |
| Flap-glide | n beats, then glide for m s | Gull, kite, buzzard, starling |
| Bounding | Flap bursts, then folded wings | Small birds only (mass rule) |
| Hover | Flapping, flap-glide or hanging by wind; body and head fixed, tail fanned | Kestrel |
| Hawk | Swept wings, sharp banks | Swallow, swift, bat |

### 5.3 Motion: three engines, chosen per behaviour

| Engine | How | Use for | Determinism |
| --- | --- | --- | --- |
| **A. Analytic** (current) | Closed-form paths, k/1024 Hz frequencies, hashed per-bird offsets | Kettles (§4 numbers), kestrel hover/drop, kite quartering, stork skeins, heron, gulls, swallows, swifts | Exact, stateless |
| **B. Baked** | Offline topological boids (k = 7, sub-flock hierarchy), stdlib Python tool, stored as a looping float data texture (e.g. 512 birds × 256 keys, RGBA16F ≈ 1 MiB) read with `texelFetch` + Catmull-Rom; loop period divides 1024 s. **Fallback F1** if web vertex texture fetch fails: a procedural murmuration (Fourier centre and shape in uniforms, hashed offsets, travelling density bands) | Murmuration, pigeon/jackdaw flocks | Exact; the asset is generated and hashed |
| **C. Reactive** (D3) | ≤ 48 CPU agents stepped on simulation ticks with their own `RandomNumberGenerator` seeded from the session; O(n²) is enough (2,304 pairs). **The airplane is a predator** (three.js model): birds within a startle radius flee and speed up. The radius grows with the model's speed and engine loudness from AUD, so a glow engine scatters birds further than an electric motor [est] | Ground-bird flushes, swallows round the model, gull/jackdaw mobbing, rare raptor dive from above and behind | Same build and tape → same frames; presentation only, never in the kernel |

Wind: kettles drift with the **mean** configured wind aloft (not gusts), so drift stays a pure function of time and the pilot can read the wind aloft from circling birds. Kestrel hover mode follows mean wind speed.

Rejected: GPU flocking (ping-pong or compute) and GPUParticles3D flocks. Their state lives on the GPU, so captures cannot be shown to repeat byte for byte (and Compatibility has no compute).

### 5.4 Ecology director

A deterministic schedule picks the populations from:

- **Calendar and time:** vultures and storks with warm daytime sun; swallows and swifts in the warm season; swifts climb away after sunset; murmuration Oct–Mar for ≈ 26 min around sunset, ending in a dive to the roost; bats 17–55 min after sunset; nothing at night (owls stay audio).
- **Weather:** rain thins birds; storms clear the sky; strong wind favours hovering and ridge soaring.
- **Landscape habitat tags:** lake → gulls, heron; ridge → vultures, eagles; buildings → pigeons, swifts; fields → kites, kestrel; runway grass → ground birds. The tags belong to landscape data and are requested from the landscape owners.
- **Scene detail preset:** sets `visible_instance_count` per MultiMesh (no rebuild).

### 5.5 Looks

- **Aerial perspective:** distant birds take the atmosphere's fog/sky colour instead of pure black; this also hides sub-pixel sparkle.
- **Lighting:** underside lit by ground bounce; backlit primaries glow at the rim near the sun (view·sun term); species colour at T1/T2.
- **Sun:** birds crossing the sun vanish in the SUN veil like the model.
- **Shadows:** none, except an optional blob for the low kestrel and ground birds.

### 5.6 MultiMesh practice

A MultiMesh is culled as a whole, so populations are split by region (kettle, lake, field, runway) and each gets a tight `custom_aabb` covering its path. Allocate the maximum count once and vary `visible_instance_count`. Set `use_custom_data` and `use_colors` before `instance_count`.

## 6. Readability guard (non-negotiable)

1. **Exclusion cone:** no bird path passes within a set angle of the pilot→model line of sight (start at 3°; owner tunes); reactive birds steer out of it.
2. **Gait is a signature:** no species flies a long straight glide like a model; soarers sway and curl, kites twist their tails.
3. **Pixel-based LOD** handles auto-zoom (§3).
4. Births and deaths happen off-screen or far away (swifts climb away; murmurations dive into the roost), never by pop-in.
5. Rare reactive events (raptor dive, mobbing) never cross the model's path in the last seconds before landing [est rule].
6. Captures and reference tests keep `--scenery_birds=off` unless they test birds.

## 7. Gameplay hooks (optional, later)

| Hook | Basis | Owner |
| --- | --- | --- |
| **Thermal marking:** kettles centre on real lift | RC and paraglider pilots use thermalling birds; needs a spatial thermal field | M5 (thermals), SC (birds) |
| **Ground-bird flush** on taxi and take-off | Common at real fields; Unreal flocking packs' fear response | SC |
| **Rare raptor interest** in the model (very low probability) | Documented eagle/hawk attacks | SC; damage only via D4 |
| **Diegetic guidance** (birds lead to a point) | *Ghost of Tsushima* | NR / tutorial owners |
| **Flight-log markers** for bird events | Debugging and replay review | FL owner |

## 8. Performance budget (proposal)

| Population | Instances | Triangles each | Primitives | Draws |
| --- | --- | --- | --- | --- |
| Raptors and storks (T1) | 24 | 40 | 960 | 2 |
| Small birds: swallows, pigeons, gulls (T1) | 40 | 24 | 960 | 2 |
| Murmuration (T0) | 600–2,000 by preset | 3 | 1,800–6,000 | 1 |
| Ground birds (T1) | 24 | 16 | 384 | 1 |
| Near tier (T2) | ≤ 8 | 300 | 2,400 | 2 |
| **Worst view** | | | **≈ 10,700** | **8** |

Under 1 % of the pilot class limit (1,307,000 primitives / 360 draws), but the pilot growth reserve is spent, so the `scenery_Birds` raise goes through the LU-34 budget process with measured numbers. MSFS 2024 players switch fauna off because of frame drops; every slice is measured at **1080p first**, then 1440p and 4K, 720p last.

## 9. Steps

| ID | Work | Proof / status |
| --- | --- | --- |
| SC-BIRD-00 | Register prefix; finish the survey's open items: wingbeat and span tables, climb rates, licences and hashes of CC0 models, CC0 Freesound calls; reference silhouette URLs kept local with a tracked manifest | Survey updated with [V-page] marks · pending |
| SC-BIRD-01 | Compatibility spike: 3-triangle T0 MultiMesh, `INSTANCE_CUSTOM`, `visible_instance_count`, vertex `texelFetch` of an RGBA16F texture; native opengl3 **and web** | Byte-identical repeat captures; draw/primitive counts; F1 decision · pending |
| SC-BIRD-02 | Species data schema (`app/data/scenery/birds/`) and validator: planform, mass, gaits (mass rule), k/1024 Hz frequencies, colours, habitats, calendar and time windows | Unit test rejects invalid data · pending |
| SC-BIRD-03 | Parametric silhouette generator (T0/T1) with joint weights | Owner overlay on reference photos; triangle test · pending |
| SC-BIRD-04 | Shader rig, six gaits, speed-linked flap | Fixed-clock contact sheet per gait; phase unit test · pending |
| SC-BIRD-05 | Analytic behaviours: kettles (leader/followers, mean-wind drift), kestrel by wind, kite quartering, stork skein, heron, gulls, swallows, swifts; terrain/tree clearance | Path tests (period divides 1024 s, clearance, exclusion cone) · pending |
| SC-BIRD-06 | Murmuration: baked tool (or F1), seasonal dusk window, roost dive | Generator hash; loop-seam test; dusk capture · pending |
| SC-BIRD-07 | Looks: aerial perspective, ground bounce, backlit rim, species colour | Noon/sunset captures against sky · pending |
| SC-BIRD-08 | Ecology director: calendar, time, weather, habitat tags, detail preset | Schedule unit test; per-landscape capture · pending |
| SC-BIRD-09 | Readability guard and pixel LOD with auto-zoom | No bird inside the cone over a recorded flight; auto-zoom capture · pending |
| SC-BIRD-10 | Audio with AUD: synthesized calls (kite whistle, kestrel "kee", swift screams, stork clatter, murmuration wing rush) at the same positions; xeno-canto NC recordings are not usable | AUD bench · pending (AUD owner) |
| SC-BIRD-11 | T2 near tier from downloaded CC0 models (D5) | Provenance record; close-up capture · pending |
| SC-BIRD-12 | Reactive engine C: airplane-as-predator startle, swallows, mobbing, rare raptor dive (D3) | Same tape → identical frames; flight-log markers · pending |
| SC-BIRD-13 | Thermal marking: kettles centre on M5 spatial thermals (D7) | Blocked: needs an M5 spatial thermal field |
| SC-BIRD-14 | Bird strike as an opt-in hazard through the session/contact contract (D4) | CR/physics owners · parked |
| SC-BIRD-15 | Budget revision and Gate SC flight judgement at 1080p, then ≥ 1440p, then 720p | `attribute_views.gd`; owner flight notes · pending |
| SC-BIRD-16 | Ground birds on runway grass and roofs: pecking idle, flush on approach (engine C), resettle later (D8) | Taxi capture; flush/resettle test · pending |

Recommended first slice: **00 → 01 → 02 → 03 → 04 → 05** with three species (vulture kettle, kite, swallows). Second slice: **06 + 08** (murmuration and the calendar). Third: **12 + 16** (reactive and ground birds).

## 10. Owner decisions

| ID | Question | Recommendation |
| --- | --- | --- |
| D1 | Species set | Iberian/Mediterranean set of §4, data-driven so other regions are new data files |
| D2 | Default density | "Normal" tied to the Scene detail preset, plus an Off/Few/Normal/Lots preference (UI owner) |
| D3 | Reactive birds | Yes, after the analytic slice, ≤ 48 agents, presentation only |
| D4 | Bird strike | Off by default; separate opt-in step through existing contracts |
| D5 | Near tier | Downloaded CC0 models re-weighted to the shader rig; no skinning |
| D6 | Murmuration timing | Realistic (Oct–Mar, dusk); a trailer/postcard override for CAM/cinematic |
| D7 | Thermal marking | Request a spatial thermal model from M5; birds follow it, never invent lift |
| D8 | Ground birds | Yes, on runway grass and roofs, flushing on taxi |
| D9 | Seasons | Use the existing calendar for migrants and murmurations |

## 11. Risks

1. **Confusion with the model** (02 risk 5): §6 guard plus owner judgement.
2. **Sub-pixel sparkle** of specks: aerial-perspective fade and a minimum-size cull, not an alpha fade.
3. **Clock wrap:** every period divides 1024 s, or birds jump at the wrap.
4. **Vertex texture fetch on web:** confirm in SC-BIRD-01; import lossless, no mipmaps; F1 is the fallback.
5. **Fauna cost:** measure every slice; Off must stay available.
6. **Reactive determinism:** same build and tape only; libm differences across platforms are not claimed away.
7. **Licences:** Quaternius QAL limits pack redistribution; three.js and godot_boids are reference only until their licences are checked; no NC audio.
8. **Repository size:** no reference photos or contact sheets committed unless they are the evidence (small JPEG).

## Sources

All sources, with verification marks, are in the [web survey](../research/scenery-investigations/06-birds-sky-life-survey.md#sources) and [02 §5](../research/scenery-investigations/02-flora-and-ambience.md#5--birds).
