# Birds: species, behaviour and sky life

2026-10-24 · Revision 1 · **Planning draft** · Step prefix: **SC-BIRD** (Scenery subtrack; not yet in the [registry](../README.md#tracks-plans-and-step-ids)) · Gate: **SC**

**Status:** proposal only. Nothing is implemented. Owner decisions D1–D7 (§9) are open.

**Owner:** Scenery and field life ([SCENERY-PLAN](../SCENERY-PLAN.md)), which owns today's SC-20 flock. Coordination: VQ/LU (scene budget, Scene detail preset, aerial perspective), FW/TOD (sun, sky, time of day, weather), M5 (wind, future spatial thermals), AUD (wildlife calls), UI (preference), CR/physics (bird strike, only if D4 is accepted).

**Proposed ownership:** `app/scenery/birds*.gd|gdshader` (existing), new `app/scenery/birds/`, `app/data/scenery/birds/`, `tools/scenery/birds/`, `app/tests/test_birds_*.gd`, evidence in `docs/research/scenery-implementation/SC-BIRD-*/`. Shared hooks stay with their owners.

## 1. Goal

Make the sky above the field feel alive and believable: different species with real silhouettes, real gaits and real behaviour (vultures circling in thermals, a kestrel hanging in the wind, swallows skimming the grass, a starling murmuration at dusk). Fit everything into the Compatibility renderer, keep it deterministic, and never make it harder to see the model airplane.

Non-goals: skinned animals everywhere, an ornithology simulator, birds that change flight physics by default.

## 2. Current baseline (SC-20)

| Fact | Where |
| --- | --- |
| 12 identical "V" birds, 2 triangles, 0.9 m span, black albedo | [birds.gd](../../app/scenery/birds.gd) |
| One closed analytic loop (radius 140 m, 128 s lap) at 32 m altitude, NE of the pilot; flap at 4 Hz in the vertex shader | [birds.gdshader](../../app/scenery/birds.gdshader) |
| Stateless: position and flap depend only on `sim_clock` (wraps at 1024 s; frequencies are k/1024 Hz) | [shader_clock.gd](../../app/render/shader_clock.gd) |
| On in the Home launch profile; off in reference captures (`OPENRC_SCENERY_BIRDS=off`) | [scenery.gd](../../app/scenery/scenery.gd), [capture.sh](../../app/capture.sh) |
| Budget `scenery_Birds`: 1,000 primitives / 2 draws per view class | [scene_budget.json](../../tools/scenery/scene_budget.json) |
| Earlier research chose analytic motion and our own tiny mesh; Quaternius eagle rejected as overkill at ≤ 5 px | [02-flora-and-ambience §5](../research/scenery-investigations/02-flora-and-ambience.md#5--birds) |

Hard constraints: Godot 4.7 **Compatibility** (no compute shaders, no particle trails, no alpha-to-coverage); web export; no shader `TIME`; captures must repeat byte for byte; vertical pilot FOV 50° with auto-zoom down to 6° ([spec.gd](../../app/spec.gd)).

## 3. How big a bird is on screen (1080p first)

`px = span × 1080 / (2 d tan(fov/2))` ([`PilotCamera.projected_px`](../../app/render/pilot_camera.gd)). At FOV 50°: `px ≈ 1158 · span / d`.

| Bird | Span | Typical distance | px at 1080p | px at 2160p |
| --- | --- | --- | --- | --- |
| Griffon vulture | 2.6 m | 300 m / 1,000 m | 10 / 3.0 | 20 / 6.0 |
| White stork | 1.9 m | 250 m | 8.8 | 17.6 |
| Red kite | 1.8 m | 120 m | 17 | 35 |
| Kestrel (hovering) | 0.75 m | 40 m | 22 | 43 |
| Barn swallow | 0.33 m | 15 m | 25 | 51 |
| Starling (one bird) | 0.4 m | 300 m | 1.5 | 3.1 |
| Murmuration (whole cloud) | ~150 m | 600 m | ~290 | ~580 |
| Ugly Stik 60 (comparison) | ~1.6 m | 225 m | 8.2 | 16.5 |

Spans are typical field-guide values [est]; verify in SC-BIRD-00.

**Consequences.** (1) A vulture or stork at a few hundred metres is the same size as the model: silhouette shape and gait, not size, must tell them apart. (2) Auto-zoom at 6° magnifies by tan 25°/tan 3° ≈ **8.9×**, so a bird near the line of sight to the model can be drawn at 50–200 px. LOD must use projected pixels, not distance. (3) 4K doubles every value, so the near tier matters more at secondary resolutions. (4) Starlings read only as a cloud; their shape is irrelevant, their density is everything.

## 4. Inspiration: who flies over an RC field

The "ethogram" each species needs. Wingbeat values are rough [est, U] and must be checked against Bruderer et al. (2010) and Pennycuick (1990, 1996) in SC-BIRD-00; shader frequencies are then rounded to k/1024 Hz.

| Species (es) | Silhouette keys | Gait / behaviour | Where / when | Why it is good here |
| --- | --- | --- | --- | --- |
| **Griffon vulture** (buitre leonado) | Huge plank wing, 7 deep "fingers", short square tail, small head | Thermal soaring in groups ("kettles"); bank 25–35° low in the climb, shallower higher up (Williams et al. 2018); flaps rarely | Midday, sunny, over ridges and warm fields | Big, slow, unmistakable; kettle drift shows the wind aloft |
| **Golden / booted eagle** (águila real / calzada) | Long broad wing, fingered, slight dihedral | Soaring, long glides, occasional stoop | Midday; ridges | Hero bird; dramatic stoop |
| **Red / black kite** (milano real / negro) | Long angled wing, **deeply forked tail** that twists constantly | Slow low quartering over fields, tail-steering, following mowing | Day; open fields | Reads clearly at 10–30 px; tail twist is a free "alive" cue |
| **Common buzzard** (ratonero) | Medium broad wing, short fan tail | Soars, circles, mews | Day | Common filler raptor |
| **Kestrel** (cernícalo) | Pointed wing, long tail | **Wind hovering**: head almost fixed (< 5 mm in RMIT/Bristol wind-tunnel work) while wings and tail trim; then drop | Over grass, 10–30 m, in wind | Iconic, close to the pilot, couples to wind speed |
| **White stork** (cigüeña blanca) | Black flight feathers, white body, neck and legs extended | Thermal soaring, slow flaps, migration skeins | Day; fields, nests on towers | Distinct silhouette at long range |
| **Grey heron** (garza real) | Arched wing, neck folded, legs trailing | Slow deep flaps, straight crossings | Lake landscapes | Slow, calm motion near water |
| **Gulls** (gaviotas) | Narrow angled "M" wing, white | Flap-glide, lake circuits; mob drones in nesting season (forum reports) | Lake / coast | Bright accent; candidate reactive bird |
| **Pigeons** (palomas) | Compact, pointed wings | Fast flock circuits, wing claps, settle on roofs | Buildings | Mid-size flock cue |
| **Jackdaws / crows** (grajillas / cuervos) | Black, fingered | Tumbling play; **mob raptors** | Treeline | Interaction between species |
| **Barn swallow / swift** (golondrina / vencejo) | Swept wing, forked tail / scythe wing | Erratic hawking 1–8 m over grass; swifts' "screaming parties" round buildings at evening | Day / summer evening | Closest birds to the pilot; speed and agility |
| **Starling** (estornino) | Small triangle | **Murmuration**: each bird follows its 6–7 nearest neighbours (topological interaction, Ballerini et al. 2008; Young et al. 2013) | Dusk, over reeds/trees | The showpiece; depends on time of day |
| **Bats** (murciélagos, bonus) | Small, jerky | Erratic flutter | Late dusk | Natural hand-over to the night ambience (owls already exist in audio) |

Real interactions worth borrowing (anecdotal forum reports, not data): gulls and swallows circle or hit drones; hawks have attacked gliders; pilots climb away because birds strike from above. Glider sims (Aerosoft's) advertise birds that mark thermals; Condor models thermals but no bird marking was found.

## 5. Architecture

### 5.1 Three visual tiers, chosen by projected pixels

| Tier | When | Representation | Cost |
| --- | --- | --- | --- |
| **T0 speck** | < 4 px | Current idea, improved: 2–8 triangle species-tinted silhouette, flap in vertex shader | One MultiMesh, 1 draw for all specks |
| **T1 silhouette** | 4–40 px | **Parametric planform mesh** per species, 16–48 triangles, generated by our tool: span, aspect, arm/hand split, finger count and depth, tail shape (forked, wedge, fan, square), neck/legs. Joint weights in vertex colour | One MultiMesh per species group, ≤ 6 draws |
| **T2 near** (optional, D5) | > 40 px (kestrel, swallow, auto-zoom) | A downloaded CC0 model (Quaternius eagle, BlendSwap CC0 seagull) re-weighted to the same shader rig; VAT only if the rig is not enough | ≤ 8 instances, a few draws |

Tier switches use `visibility_range` hysteresis or shader-side vertex collapse (collapsed triangles are free after the vertex stage). No octahedral impostors: they help static meshes, not flapping ones, and the current addon targets Forward+/Mobile.

### 5.2 Shader rig instead of skeletons

Each wing vertex stores weights for shoulder, elbow/wrist and tip in `COLOR`; the vertex shader rotates them around two hinge axes with a phase lag between arm and hand (the hand trails), folds the hand on the upstroke and adds tip curl when soaring. Tail vertices twist and fan (kite steering, kestrel trimming). Gaits are parameter sets:

| Gait | Parameters | Species |
| --- | --- | --- |
| Flap | Frequency, amplitude, downstroke/upstroke ratio, hand lag | Pigeon, heron, stork |
| Glide / soar | Dihedral, tip curl, small sway; rare flap bursts | Vulture, eagle, stork |
| Flap-glide | Flap n beats, glide m s | Gull, kite, buzzard |
| Bounding | Flap bursts with folded wings between | Finches, woodpeckers (later) |
| Hover | Fast flap or wind hover; body and head fixed, tail fanned | Kestrel |
| Hawk | Swept wings, sharp banks, fast | Swallow, swift |

This keeps one mesh per species group, works with `MultiMesh` + `INSTANCE_CUSTOM` in Compatibility, has no CPU cost and is still a pure function of `sim_clock`. VAT (OpenVAT: Blender extension, GPL-3.0 tool, 16-bit PNG/EXR output; Godot instancing VAT shader limited to 16-bit per-instance data and no blending under Compatibility) is the fallback for T2 only.

### 5.3 Motion: three engines, chosen per behaviour

| Engine | How | Use for | Determinism |
| --- | --- | --- | --- |
| **A. Analytic** (current) | Closed-form paths with k/1024 Hz frequencies and per-bird hash offsets | Kettles (helix: r = v²/(g tan φ); 12 m/s at 30° ≈ 25 m), kestrel hover/drop, kite quartering, stork skeins, heron crossings, swallow Lissajous paths | Exact, stateless |
| **B. Baked** | Offline topological-boids simulation (7 neighbours, our stdlib Python tool) stored as a looping float data texture (e.g. 512 birds × 256 keys, RGBA16F ≈ 1 MiB) and read in the vertex shader with `texelFetch` and Catmull-Rom interpolation; loop period divides 1024 s | Murmuration, pigeon and jackdaw flocks | Exact; asset is generated and hashed, never hand-edited |
| **C. Reactive** (D3) | Small CPU boids (≤ 48 agents) stepped once per simulation tick from the session seed, reading the airplane's render-side state read-only | Startle/flee, swallows chasing the model, gulls/crows mobbing | Same tape → same frames; presentation only, never in the kernel |

Wind: kettles drift with the **mean** configured wind at altitude (not gusts), so drift stays a pure function of time and the pilot can read the wind aloft from the circling vultures. Kestrel hover appears only when mean wind is above about 3 m/s [est].

GPU ping-pong flocking through a SubViewport is rejected: GPU float results are not guaranteed identical across drivers, which breaks byte-identical captures.

### 5.4 Ecology director

A deterministic schedule picks which populations exist, from: time of day (vultures and storks only with warm daytime sun; swifts at evening; murmuration at dusk; bats late dusk; none at night), weather (rain thins birds; storms clear the sky; strong wind favours hovering and ridge soaring), landscape habitat tags (lake → gulls, heron; ridge → vultures, eagles; buildings → pigeons, swifts; fields → kites, kestrel) and the Scene detail preset. Habitat tags belong to landscape data; this plan requests them from the landscape owners.

### 5.5 Looks

- **Aerial perspective:** distant birds take the atmosphere's fog/sky colour as terrain does, instead of pure black; this also removes sub-pixel sparkle naturally.
- **Lighting:** underside lit by ground bounce; backlit primaries glow at the rim near the sun (cheap view·sun term); species colour at T1/T2 (stork black-and-white, kite rufous, gull white).
- **Sun:** birds crossing the sun disappear in the SUN veil like the model does; no special case.
- **Shadows:** none, except an optional blob shadow for the low kestrel (budget decision).

## 6. Readability guard (non-negotiable)

1. **Exclusion cone:** no bird path passes within a set angle of the pilot→model line of sight (start at 3°, tuned by owner); reactive birds steer out of it.
2. **Gait is a signature:** no species glides like a model airplane on a straight line for long; even soarers sway and curl.
3. **Pixel-based LOD** handles auto-zoom (§3).
4. Births and deaths happen outside the view frustum or far away, never by pop-in.
5. Captures and reference tests keep `--scenery_birds=off` unless they test birds.

## 7. Performance budget (proposal)

| Population | Instances | Triangles each | Primitives | Draws |
| --- | --- | --- | --- | --- |
| Raptors and storks (T1) | 24 | 40 | 960 | 2 |
| Small birds: swallows, pigeons, gulls (T1) | 40 | 24 | 960 | 2 |
| Murmuration (T0) | 600 | 6 | 3,600 | 1 |
| Near tier (T2) | ≤ 8 | 300 | 2,400 | 2 |
| **Total worst view** | | | **≈ 8,000** | **7** |

That is under 1 % of the pilot class limit (1,307,000 primitives / 360 draws), but the pilot growth reserve is spent, so the `scenery_Birds` raise goes through the LU-34 budget process with measured numbers. Measure at **1080p first**, then 1440p and 4K, 720p last. Murmuration count scales with the Scene detail preset.

## 8. Steps

| ID | Work | Proof / status |
| --- | --- | --- |
| SC-BIRD-00 | Register prefix; source audit: spans, wingbeats (Bruderer 2010 tables, Pennycuick), vulture bank angles, licences and archive hashes of candidate CC0 models; reference silhouette URLs kept local under `references/` with a tracked manifest | Research README with verified/unverified marks · pending |
| SC-BIRD-01 | Compatibility spike: MultiMesh + `INSTANCE_CUSTOM` + vertex `texelFetch` of a float data texture, native opengl3 and web | Byte-identical repeat captures; draw/primitive counts · pending |
| SC-BIRD-02 | Species data schema (`app/data/scenery/birds/`) and validator: planform, gaits, k/1024 Hz frequencies, colours, habitats, time windows | Unit test rejects invalid data · pending |
| SC-BIRD-03 | Parametric silhouette generator (T0/T1) with joint weights | Owner overlay of silhouettes on reference photos; triangle test · pending |
| SC-BIRD-04 | Shader rig and the six gaits | Fixed-clock contact sheet per gait; flap-phase unit test · pending |
| SC-BIRD-05 | Analytic behaviours: kettles with wind drift, kestrel hover/drop, kite quartering, stork skein, heron, gulls, swallows; terrain/tree clearance check | Path tests (period divides 1024 s, clearance, exclusion cone) · pending |
| SC-BIRD-06 | Baked murmuration and flock tool; seamless loop; dusk window | Generator hash; loop-seam test; dusk capture · pending |
| SC-BIRD-07 | Looks: aerial perspective, ground bounce, backlit rim, species colour | Captures against sky at noon/sunset · pending |
| SC-BIRD-08 | Ecology director (time, weather, habitat, detail preset) | Schedule unit test; per-landscape capture · pending |
| SC-BIRD-09 | Readability guard and pixel LOD with auto-zoom | Test: no bird inside the cone over a recorded flight; auto-zoom capture · pending |
| SC-BIRD-10 | Audio coupling with AUD: positional calls tied to the same positions | AUD bench · pending (AUD owner) |
| SC-BIRD-11 | T2 near tier from downloaded CC0 models (D5) | Provenance record; close-up capture · pending |
| SC-BIRD-12 | Reactive birds (D3): flee, chase, mobbing | Same tape → identical frames; flight log · pending |
| SC-BIRD-13 | Thermal marking: kettles centre on M5 spatial thermals | Blocked: needs an M5 spatial thermal field |
| SC-BIRD-14 | Bird strike as an opt-in hazard through the session/contact contract (D4) | CR/physics owners · parked |
| SC-BIRD-15 | Budget revision and Gate SC flight judgement at 1080p, then ≥ 1440p, then 720p | `attribute_views.gd`; owner flight notes · pending |

Recommended first slice: **00 → 01 → 02 → 03 → 04 → 05** with three species (vulture kettle, kite, swallows). That alone replaces the single black loop with recognisable life at low cost. Murmuration (06) is the second slice.

## 9. Owner decisions

| ID | Question | Recommendation |
| --- | --- | --- |
| D1 | Species set | Iberian/Mediterranean set of §4, data-driven so other regions are new data files |
| D2 | Default density | "Normal" tied to the Scene detail preset, plus an Off/Few/Normal/Lots preference (UI owner) |
| D3 | Reactive birds | Yes, after the analytic slice, ≤ 48 agents, presentation only |
| D4 | Bird strike | Off by default; separate opt-in step through existing contracts |
| D5 | Near tier | Downloaded CC0 models re-weighted to the shader rig; no skinning |
| D6 | Murmuration timing | Dusk only (realistic); a trailer/postcard override for CAM/cinematic |
| D7 | Thermal marking | Request a spatial thermal model from M5; birds follow it, never invent lift |

## 10. Risks

1. **Confusion with the model** (prior risk 5): §6 guard plus owner judgement.
2. **Sub-pixel sparkle** of specks: aerial-perspective fade and a minimum-size cull, not an alpha fade.
3. **Clock wrap:** every period must divide 1024 s or birds jump at the wrap.
4. **Float textures on WebGL 2:** sampling RGBA16F in the vertex shader must be confirmed in SC-BIRD-01; import lossless, no mipmaps (VAT forum lesson).
5. **Fauna cost:** MSFS 2024 players reported frame drops from fauna; budget and measure every slice.
6. **Licences:** Quaternius QAL limits pack redistribution; keep only used files, record hashes.
7. **Repository size:** no reference photos or contact sheets committed unless they are the evidence (JPEG, small).

## Sources

- Godot renderer feature table (no compute shaders or particle trails in Compatibility): <https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html>
- Godot MultiMesh: <https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html>
- Boids addon for Godot 4 (MIT, 90-008/godot_boids): <https://godotengine.org/asset-library/asset/edit/19618>; flocking-shader devlog: <https://quietgodot.itch.io/013-flocking-shader>; Reynolds: <https://www.red3d.com/cwr/boids/>
- VAT: <https://extensions.blender.org/add-ons/openvat/>, <https://godotshaders.com/?p=11698>, <https://godotshaders.com/shader/vertex-animation-texture-uses-openvat-output/>, <https://forum.godotengine.org/t/looking-for-help-implementing-a-vat-animation/59028>, <https://github.com/G4ND44/Godot_VAT3>
- Impostors: <https://github.com/SIsilicon/Godot-Octahedral-Impostors>, <https://godotengine.org/asset-library/asset/5528>
- Models: Quaternius Animal Pack Vol.2 (CC0): <https://opengameart.org/content/animated-animales-low-poly>; CC0 seagull: <https://blendswap.com/blend/7419>
- Murmuration: <https://en.wikipedia.org/wiki/Flocking>, <https://pmc.ncbi.nlm.nih.gov/articles/PMC3561045>, <https://www.allaboutbirds.org/news/how-do-starling-flocks-create-those-mesmerizing-murmurations/>
- Wingbeat: Pennycuick 1990 <https://cob.silverchair.com/jeb/article/150/1/171/5695/Predicting-Wingbeat-Frequency-and-Wavelength-of>, 1996 <https://cob.silverchair.com/jeb/article-pdf/199/7/1613/3391219/jexbio_199_7_1613.pdf>; Bruderer et al. radar: <https://tethys.pnnl.gov/publications/wing-beat-characteristics-birds-recorded-tracking-radar-cine-camera>
- Vulture thermal soaring: <https://hal.umontpellier.fr/hal-02393999>, data <https://datarepository.movebank.org/handle/10255/move.688>
- Kestrel wind hovering: <https://bristol.ac.uk/news/2024/august/kestrels-aerial-safety.html>
- Raptor silhouettes: <https://singaporebirds.com/blog/rap201-how-to-identify-uncommon-raptors>
- Birds and drones (anecdotal): <https://mavicpilots.com/threads/seagulls.86344/post-975973>, <https://phantompilots.com/threads/bird-attacks-do-they-happen.743/>
- Glider sims: <https://www.condorsoaring.com/about/>, <https://forums.flightsimulator.com/t/what-glidersimulator-do-will-you-use/405323>
- MSFS 2024 fauna cost (community reports): <https://steamcommunity.com/app/2537590/discussions/1/676200171205303768>
