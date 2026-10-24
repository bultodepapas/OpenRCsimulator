# 06 · Birds and sky life: web survey (SC-BIRD)

2026-10-24 · Research snapshot for [the birds plan](../../plans/birds-sky-life.md). Supersedes nothing: [02 §5](02-flora-and-ambience.md#5--birds) remains the SC-20 rationale.

**Question:** which techniques, data, free resources and prior art should shape a richer bird layer for Godot 4.7 Compatibility with deterministic captures?

**Method:** 29 web searches and 5 direct page reads on 2026-10-24 (Google-style search, GitHub, Godot docs/forum/asset library, Reddit, hobby forums, primary literature). Marks: **[V-page]** read on the page itself; **[V-search]** taken from search summaries, not read in full; **[U]** unverified; **[est]** our estimate. **Reddit:** five Reddit-targeted queries returned no Reddit threads; equivalent hobby-forum threads were used instead. Nothing was downloaded.

## 1 · Rendering and engine techniques

| # | Source | Finding | Verdict for the plan |
| --- | --- | --- | --- |
| R1 | Godot docs, *Animating thousands of fish* [V-page] | Bones-free vertex animation on a MultiMesh: side-to-side, pivot, travelling wave and twist, each a cosine on `VERTEX`; a `smoothstep` mask along the body; rotations blended with `mix()` (multiplying by the mask shrinks the mesh); per-instance phase `TAU · INSTANCE_CUSTOM.x`, speed `0.5 + INSTANCE_CUSTOM.y`. Fish do not travel; moving instances from CPU each frame is called costly | **Adopt** the mask + `mix()` rules in the shader rig; keep per-species speed spread small (±10 % [est]) |
| R2 | three.js `webgl_gpgpu_birds` [V-page] (MIT library [U]) | 3 triangles per bird (body keel + two wings), 9 vertices; only the two wing-tip vertices move, `y = sin(phase) · 5`; phase advances with speed; 1,024 birds; O(n²) neighbour scan in a fragment shader; predator pushes birds within 150 units and raises their speed limit | **Adopt** the 3-triangle T0 (a keel reads better side-on than today's 2 triangles) and "flap rate rises with speed"; **adopt** the predator model for startle; **reject** GPU state (driver-dependent floats) |
| R3 | three.js forum on the same example [V-search] | Slows at ~16k triangles because of flocking cost, not geometry | Confirms flocking, not drawing, is the cost; bake it |
| R4 | Godot docs, *Optimization using MultiMeshes* [V-search] | One MultiMesh is culled as a whole; `visible_instance_count` shows a prefix of the allocated instances; `multimesh_set_buffer()` for bulk updates | **Adopt:** density preset = `visible_instance_count` (no rebuild); split populations per region so off-screen groups cull |
| R5 | Godot forum, INSTANCE_CUSTOM reads zero (4.4) [V-search] | Users report default custom data; order matters (`use_custom_data` before `instance_count`) | SC-20 already reads custom data in Compatibility with the `use_colors` trick ([birds.gd](../../../app/scenery/birds.gd)); keep that pattern and test it |
| R6 | Godot forum/itch on `texelFetch`, WebGL 2 [V-search] | `texelFetch` gives exact float reads on GLES3; old GLES2 lacked it; one web regression of screen-texture sampling (4.1→4.2) and an unopened issue #91717 [U]; devices with zero vertex texture units cannot sample in the vertex stage | Baked flocks need the SC-BIRD-01 web spike; **fallback** without textures (§4 F1) |
| R7 | Godot renderer table [V-page] | Compatibility: no compute shaders, no particle trails, no SDF collision; low base cost, high scaling cost | Keeps everything in vertex shaders; few draws |
| R8 | GPUParticles3D class reference [V-search] | `use_fixed_seed`, `seed`, `request_particles_process()` exist in 4.x docs; Compatibility behaviour not stated | **Reject** for birds: state lives on the GPU; exact seeking and capture repeatability unproven [U] |
| R9 | VAT: Godot instancing VAT shader, OpenVAT (GPL-3.0 tool, PNG16/EXR), Godot_VAT3 port, VAT forum (lossless import, no mipmaps) [V-search] | Works with instancing; Compatibility halves per-instance precision and has no blending | T2 fallback only, as in revision 1 |
| R10 | Vertex-colour animation (Andreas Glad tutorial; a 140-vertex ArtStation bird; Unity mirrored-mask thread) [V-search] | Sine waves weighted by vertex colour give wing flap plus body undulation with no skeleton; mirrored masks need a symmetric term | Confirms the shader rig; use `abs(x)` symmetry as SC-20 already does |
| R11 | Commercial distant-bird packs (Fab: seagulls/crows; Unreal sparrow/pigeon flocking) [V-search] | Mesh particles with "UV snapshot" (flipbook) wing frames; vertex colours for tint; fear response: birds take off when characters approach | **Reject** flipbooks (alpha-scissor sparkle; no alpha-to-coverage in Compatibility); **adopt** the take-off-on-approach idea for ground birds |
| R12 | Octahedral impostors (SIsilicon; hdrsniped LOD addon targets Forward+/Mobile, "Custom/Proprietary" licence) | Static meshes only | Reject, as in revision 1 |
| R13 | O'Hara 2002, *Hierarchical impostors for flocking* [V-search] | Groups sub-flocks to cut behaviour cost | Use sub-flock hierarchy in the offline murmuration tool |

## 2 · Flocking code and determinism

| # | Source | Finding | Verdict |
| --- | --- | --- | --- |
| C1 | 90-008/godot_boids (MIT, Godot 4.3) [V-search] | 2D/3D boids addon | Read as reference; runtime use only for engine C (reactive) if it can be stepped per tick |
| C2 | Shmupo/GodotBoids [V-page] | Godot 4.2; V3 = spatial hash + MultiMesh, "2k at 100 fps"; accuracy suffers at grid lines; **no licence stated** | Reference only; do not copy code |
| C3 | Vahkiin *Boids Predator Simulation Lab* (Godot 4.5.1, browser) [V-search] | Grid hashing, pooling, time-slicing across frames, a predator | Time-slicing is unnecessary for ≤ 48 reactive agents (2,304 pairs per tick) |
| C4 | Determinism notes (bugnet RNG guide, GDQuest glossary, Klotho fixed-point framework) [V-search] | Seeded per-system RNG, fixed timestep; floats limit cross-platform determinism | Engine C: own `RandomNumberGenerator` seeded from the session, stepped on simulation ticks, float64; claim same-build replay, not cross-platform bit identity |
| C5 | Reynolds boids (02 §5); starling topology: 6–7 nearest neighbours (Ballerini 2008; Young et al. 2013) [V-search] | Topological, anisotropic interaction | Offline tool uses k = 7 topological neighbours |

## 3 · Bird biology (numbers for the species data)

| # | Source | Finding | Use |
| --- | --- | --- | --- |
| B1 | Williams et al. 2018, *J. Exp. Biol.* (Gyps vultures, magnetometers) [V-search] | Bank 25–35° early in the climb, decreasing with height; constant airspeed while radius-limited | Kettle bank schedule |
| B2 | Gyps glide studies (Sci. Rep. 2016 and related) [V-search] | Theoretical best glide ≈ 13.7–14.4 m/s, minimum sink ≈ 8.7–9.2 m/s; airspeed falls ≈ 3 m/s through an inter-thermal glide; informed birds leave faster | Circling at ≈ 9 m/s gives r = v²/(g tan φ) ≈ 12–18 m for φ = 35–25°, 8–12 s per turn [calc]; glides start at ≈ 14 m/s and slow to ≈ 11 |
| B3 | Wikipedia, Eurasian griffon [V-search] | Span 2.3–2.8 m; mass 6.2–10.5 kg | Species data |
| B4 | Flack et al. 2018, *Science* (27 white storks) [V-search] | A few leaders find and explore thermals, repeatedly leaving and re-entering to find the core; followers leave earlier and lower and flap more | Kettles get a wandering leader and lagging followers that peel off low and flap |
| B5 | Ákos et al. 2008 (birds vs paragliders) and Model Aviation RC-soaring column (1998: "hawks are lift-finding heroes") [V-search] | Pilots use thermalling birds to find lift | Strong case for thermal marking (SC-BIRD-13) |
| B6 | Videler & Groenewold 1991; Videler et al. 1983 (kestrels) [V-search]; RMIT/Bristol 2024 [V-page, rev. 1] | Hanging without wingbeats in 8.7 ± 1.5 m/s wind, 6.5 ± 1.5 m above a windward slope; mixing flaps with short glides saves ≈ ¼ of hover cost; head motion < 5 mm | Hover mode by wind: flapping hover in light wind, flap-glide hover in moderate wind, hanging only with strong wind plus slope/edge lift |
| B7 | Tobalske 2001 review and woodpecker study [V-search] | Birds > ~300 g do not flap-bound; 35–158 g flap-glide when slow and flap-bound when fast; < 20 g low-aspect birds flap-bound at all speeds | Validator rule: allowed gaits follow body mass |
| B8 | Pennycuick 1990 (32 species), 1996 (47), Bruderer et al. radar (153 species) [V-search] | Wingbeat regressions and species tables | Read full tables in SC-BIRD-00; revision-1 wingbeats stay [est, U] |
| B9 | Barn swallow: Doppler radar mean 8 m/s (n = 821); field prey 4.2–10.6 m/s, swallows ≥ 9.9 m/s; low coursing exploits the near-ground wind gradient [V-search] | Speed 6–10 m/s, 1–8 m high [est] |
| B10 | Red kite (field guides, Swiss tourism, Naturalis) [V-search] | Constant forked-tail twisting even in light wind is diagnostic; low glides over open, low vegetation; walks on freshly mown grass for worms | Tail-twist always on; low quartering over the field |
| B11 | Common swift (Wikipedia, BOU blog, Dokter et al. 2013 via ScienceDaily) [V-search] | Screaming parties of 10–20 round the nest area on summer evenings; after sunset many climb fast to ≈ 2.5–3 km | Swifts leave the scene by climbing at dusk: a natural despawn |
| B12 | Goodenough et al. 2017, *PLOS ONE* (> 3,000 murmurations) [V-search] | Mean 26 min; mean 30,082 birds (max 750,000); growing Oct→early Feb, ending in March; raptors at 29.6 % of displays, linked to larger and longer displays and to ending in a mass descent to roost | Murmuration only Oct–Mar on the existing calendar; ≈ 26 min around sunset; ends with a dive into the roost; an optional falcon makes it larger |
| B13 | Pipistrelle emergence (Dutch maternity-roost study) [V-search] | Onset ≈ 17 min after sunset, optimum ≈ 36 min, end ≈ 55 min; earlier in low wind and warm weather | Bat window |

## 4 · Behaviour prior art in games and sims

| # | Source | Finding | Verdict |
| --- | --- | --- | --- |
| G1 | GDC 2020, *Animating the animals of Red Dead Redemption 2* (listing) [V-search] | Planned ecosystem evolved from GTA V systems | Inspiration for the ecology director; talk not watched |
| G2 | *Ghost of Tsushima* (press; GDC wind talk overview) [V-search] | Golden birds lead the player to points of interest; wind drives everything | Optional diegetic guidance idea (for example Natural Random or a tutorial); owner decision |
| G3 | FS Birds for MSFS (SouthOak listings, review) [V-search] | Soaring raptors, circling gulls, goose formations, pigeon flocks, ground birds at airports; random tracks surface–11,000 ft; LOD; one review saw a large FPS drop | Same species mix; budget every slice |
| G4 | MSFS 2024 fauna (Steam, flightsim.to) [V-search] | Frame drops looking at animals; players turn fauna off | Budget gate and an Off setting are mandatory |
| G5 | RealFlight, Aerofly RC, PicaSim [V-search] | No bird feature found; PicaSim models thermals and slopes | Birds that behave would differentiate OpenRC [U] |
| G6 | Aerosoft glider sim forum mention; Condor [V-search] | Birds marking thermals advertised in one glider sim; not found for Condor | Precedent for SC-BIRD-13 |
| G7 | Procedural bird in Godot 4.5 (forum, kiri01) [V-page] | Live parameters: flap speed, wing length, amplitude, sway, body shape; no code or licence | Inspiration only |

## 5 · Birds and model aircraft (anecdotal)

| # | Source | Finding | Verdict |
| --- | --- | --- | --- |
| A1 | Komenda-Zehnder, *Ornithologischer Beobachter* 2010 [V-search] | A golden eagle dived on a 2.5 m model glider and grabbed its wing after raptors had ignored gliders in the same thermals for 20 years | Raptor attacks are real but very rare |
| A2 | Albany Advertiser (sea-eagle vs ridge-soaring models); KTVU (hawk injured by a 4 ft model); PetaPixel (hawk vs quadcopter); raven vs RC plane video [V-search] | Attacks and collisions happen, mostly near nests or territories; raptors strike from above | Rare event, with an above-and-behind approach |
| A3 | DJI/Phantom forums [V-search] | Gulls mob drones in nesting season; swallows circle or touch props | Gulls and swallows are the reactive candidates |
| A4 | Forum advice [V-search] | Climb away: raptors descend better than they climb | Escape logic for reactive raptors |

## 6 · Assets and audio licences

| # | Source | Finding | Verdict |
| --- | --- | --- | --- |
| L1 | Quaternius Animal Pack Vol. 2 (eagle, CC0 per OGA page) [V-search]; BlendSwap low-poly seagull (CC0, rigged) [V-search] | The only free CC0 flying birds found | T2 candidates; record archive hashes in SC-BIRD-00 |
| L2 | Fab packs, itch.io voxel birds, VertexCat common birds, CGTrader pigeon [V-search] | Paid or unclear licences | Not used |
| L3 | No CC0 vulture, stork, kite or kestrel model found [V-search] | **Corrected by [SC-BIRD-00](SC-BIRD-00/README.md#1--3d-models-40-files):** CC-BY animated stork, vulture, gulls and a kestrel exist on Sketchfab behind a login; CC0 animated raven and pigeon are on OpenGameArt | Parametric generator still needed for vulture, kites, swift, swallow, heron and starling |
| L4 | xeno-canto terms [V-search]; recordings of red kite, swift, gull calls are CC BY-NC-SA / BY-NC-ND [V-search] | Non-commercial licences | **Not usable** |
| L5 | Freesound clips cited by a natural-history site: buzzard CC-BY-3.0, swift and gull CC-BY-NC [V-search]; Sonniss red-kite pack (paid) [V-search] | Few permissive calls found | Prefer synthesis, as SC-19a already does; CC0 Freesound check in SC-BIRD-00 |

## 7 · Alternatives considered

| Option | Why not (or when) |
| --- | --- |
| GPU flocking (ping-pong textures, compute) | No compute in Compatibility; GPU float state is not byte-repeatable |
| GPUParticles3D flocks | GPU-side state; trails missing in Compatibility; exact seek unproven |
| Skinned models for many birds | CPU skinning cost; overkill under 40 px |
| Flipbook billboards | Alpha-scissor sparkle; no alpha-to-coverage |
| Octahedral impostors | Static meshes only |
| **F1 · procedural murmuration** (fallback if vertex texture fetch fails on web) | A flock centre and shape (deformed ellipsoid) as Fourier series in uniforms plus per-bird hashed offsets, with travelling density bands; less faithful than a bake but texture-free |

## 8 · Open items

Items 1–4 of the first snapshot were worked in [SC-BIRD-00](SC-BIRD-00/README.md) on 2026-10-24: measured climb rates, circling and wingbeats from open data (Bruderer 2010 and Pennycuick 1990/1996 stayed behind publisher walls); three.js is MIT and godot_boids an MIT Rust GDExtension; 92 sounds and 40 models hashed with licences. Still open: the listening pass and the owner decisions in SC-BIRD-00 §8.

## Sources

- Godot: <https://docs.godotengine.org/en/stable/tutorials/performance/vertex_animation/animating_thousands_of_fish.html>, <https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html>, <https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html>, <https://docs.godotengine.org/en/latest/classes/class_gpuparticles3d.html>, <https://forum.godotengine.org/t/cant-transmit-custom-data-to-mesh-instances-in-multimesh/110612>, <https://forum.godotengine.org/t/weird-texelfetch-behaviour/18401>, <https://godotforums.org/d/22990-texelfetch-equivalent-in-gles2>, <https://forum.godotengine.org/t/procedural-animated-bird-in-godot-4-5/130776>
- Flocking code: <https://github.com/mrdoob/three.js/blob/dev/examples/webgl_gpgpu_birds.html>, <https://discourse.threejs.org/t/buffergeometry-and-performance-comparison/3291>, <https://godotengine.org/asset-library/asset/edit/19618>, <https://github.com/Shmupo/GodotBoids>, <https://vahkiin.itch.io/boids-predator-simulation-lab>, <https://bugnet.io/blog/fix-godot-rng-randomize-not-called-deterministic>, <https://www.gdquest.com/library/glossary/deterministic_simulation>, <https://diglib.eg.org/handle/10.2312/8700>
- VAT and shaders: <https://godotshaders.com/?p=11698>, <https://extensions.blender.org/add-ons/openvat/>, <https://github.com/G4ND44/Godot_VAT3>, <https://80.lv/articles/tutorial-vertex-color-based-animation-basics/>, <https://rachelpascalethomas.artstation.com/projects/eaRqwZ>
- Commercial references: <https://www.fab.com/listings/18c4c296-685c-40a8-8a60-8b482f7c93b8>, <https://forums.unrealengine.com/t/vfx4game-sparrow-flocking-system/2741522>
- Biology: <https://hal.umontpellier.fr/hal-02393999>, <https://link.springer.com/10.1038/srep27865>, <https://en.wikipedia.org/wiki/Eurasian_griffon_vulture>, <https://exc.uni-konstanz.de/collective-behaviour/news-and-events/news/details/science-storks-on-the-wing-1>, <https://ar5iv.arxiv.org/html/0902.0312>, <https://library.modelaviation.com/article/radio-control-soaring-240>, <https://cob.silverchair.com/jeb/article/155/1/519/6382/Field-Measurements-Of-Hanging-Flight-Aerodynamics>, <https://bioone.org/journals/american-zoologist/volume-41/issue-2/0003-1569(2001)041[0177:MVAIFI]2.0.CO;2/Morphology-Velocity-and-Intermittent-Flight-in-Birds1/10.1668/0003-1569(2001)041[0177:MVAIFI]2.0.CO;2.full>, <https://biewenerlab.oeb.harvard.edu/publications/foraging-edge-world-low-altitude-high-speed-maneuvering-barn-swallows>, <https://sicb.org/?p=12385>, <https://www.myswitzerland.com/en-ae/experiences/summer-autumn/excursions/wildlife-watching/wildlife-watching/red-kite/>, <https://en.wikipedia.org/wiki/Common_swift>, <https://bou.org.uk/blog-nilsson-common-swift-twilight-ascents/>, <https://eprints.glos.ac.uk/4726/>, <https://natuurtijdschriften.nl/pub/712990>, <https://tethys.pnnl.gov/publications/wing-beat-characteristics-birds-recorded-tracking-radar-cine-camera>
- Games and sims: <https://gdconf.com/article/learn-how-rockstar-breathed-life-into-the-wildlife-of-red-dead-redemption-2-at-gdc/>, <https://gdcvault.com/play/1027124/Blowing-from-the-West-Simulating>, <https://digitaltrends.com/?p=2526147>, <https://msfsmarket.place/world/southoakco-fsbirdssabr>, <https://www.simflight.com/?p=111904>, <https://steamcommunity.com/app/2537590/discussions/1/676200171205303768>, <https://www.modelaviation.com/picasim-slope-simulator>, <https://forums.flightsimulator.com/t/what-glidersimulator-do-will-you-use/405323>
- Birds and models: <https://www.ala-schweiz.ch/images/stories/pdf/ob/2010_107/OrnitholBeob_2010_107_111_Komenda-Zehnder.pdf>, <https://www.albanyadvertiser.com.au/news/albany-advertiser/eagles-takes-on-model-plane-in-dog-fight-ng-b88774516z>, <https://ktvu.com/news/injured-hawk-recovers-after-crash-with-model-airplane>, <https://petapixel.com/2014/10/11/hawk-attacks-camera-drone-knocks-air/>, <https://mavicpilots.com/threads/seagulls.86344/post-975973>, <https://phantompilots.com/threads/bird-attacks-do-they-happen.743/>
- Assets and audio: <https://opengameart.org/content/animated-animales-low-poly>, <https://blendswap.com/blend/7419>, <https://vertexcat.itch.io/common-birds-set/purchase>, <https://xeno-canto.org/about/terms>, <https://seafordnaturalhistory.org.uk/QuizNotes.htm>, <https://sonniss.com/product/red-kite>
