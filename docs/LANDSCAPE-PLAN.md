# Landscape plan: from a flat green plane to a real flying field

Written **2026-10-05**, revised the same day after [11 focused investigations](research/landscape-investigations/README.md) (5 with spikes on scratch copies). Evidence and sources: [docs/research/landscape-research.md](research/landscape-research.md) and the investigations. Follows the [ROADMAP](../ROADMAP.md) rules: one small step per change, one objective proof per step, guessed numbers labeled, lessons to LEARNINGS.md.

## Why, in one picture

Today the pilot view at 30 m is **~98 % flat blue sky** with a 10 px green strip at the bottom. The scripted circle shows no ground at all. The camera tracks the airplane upward, so **the sky is the background of nearly every frame**, and today it carries no information. When the pilot watches an airplane in flight, only the ground within ~11 m of their feet is on screen ([05](research/landscape-investigations/05-grass-rendering.md), calculated).

So the order is the reverse of the usual "build terrain first":

1. **Sky and light** (what the pilot sees 90 % of the time).
2. **Horizon ring** (treeline, hills, haze: attitude and distance at low level).
3. **The field itself** (runway, known-size objects, ground texture: height and speed cues for takeoff and landing).
4. **Terrain relief and obstacles in physics** (only when M2 ground contact needs it).

**Design goal:** cues before beauty. Research says object density and contrast help pilots more than detail (Kleiss & Hubbard 1993; Lintern et al.). Each step is judged by what it adds to *flyability* and by a measured proof, not by "looks nicer".

**The pilot never moves.** This one fact simplifies most of the plan:
- each tree is seen from one fixed angle, so impostor systems add nothing;
- level of detail can be fixed per object by its distance from the pilot station, so nothing pops;
- distant terrain can be built once as rings.

Only the chase and inspect cameras need anything dynamic.

## What the 11 investigations changed

| Finding (source) | Consequence for the plan |
| --- | --- |
| `render_mode use_debanding` works in Compatibility **sky** shaders, is deterministic, and cut the longest flat-pixel run from 7 to 2 px ([01](research/landscape-investigations/01-sky-shaders.md), measured). It weakens once glow, SSAO or adjustments are on | L1a uses it instead of hand-made dithering. Ground materials get no debanding |
| A sky shader with gradient, sun and in-shader cloud noise, no `TIME`: captures repeat byte for byte, sun disc 0.6 px from its projected position ([01](research/landscape-investigations/01-sky-shaders.md), measured). Drawing the background from `RADIANCE` comes out blurry and 30/255 brighter | L1a draws the sky per pixel and uses the cached radiance only for lighting |
| Compatibility never runs the sky's half- and quarter-resolution passes. **Every third-party sky checked reads `TIME`** (Sky3D v2.1.0, Universal Sky, godotshaders) ([01](research/landscape-investigations/01-sky-shaders.md), [07](research/landscape-investigations/07-open-source-sims-scenery-code.md), src) | We write our own sky; third-party shaders are ideas only. A test bans `TIME` (L0d) |
| **`fog_aerial_perspective` is commented out** in the 4.7.2 GLES3 fog code; the sky gets one fog amount in every direction; the object fog colour has a ×π sun-scatter term, and `LIGHT0_COLOR` in sky shaders is sRGB ([02](research/landscape-investigations/02-atmosphere-aerial-perspective.md), src) | L2 makes the sky's horizon band reproduce the engine's fog formula exactly, from one source of truth, with a headless equality test |
| Hosek-Wilkie (BSD-3) at our 45° sun: zenith `#4e6893`, horizon `#c9e3ed`; a `pow(1−y, k)` gradient fits it with k ≈ 2.6 ([02](research/landscape-investigations/02-atmosphere-aerial-perspective.md), computed) | L1a colours come from a physical model, not taste; L19 can evaluate Hosek per pixel later |
| Real clear-day haze (23 km visibility) is only 10 % at 600 m and 64 % at 6 km ([02](research/landscape-investigations/02-atmosphere-aerial-perspective.md)) | **Fog cannot hide LOD pops at 400 m, nor the ground's edge.** The ground needs its own rim fade (L2), and LOD is fixed per object (L8) |
| Tonemapper barely changes airplane readability (Weber contrast −0.48…−0.55 everywhere), but Filmic/ACES at exposure 1.0 whiten the horizon and AgX greys the sky. **Filmic at exposure 0.8** keeps the sky blue at contrast −0.52. Glow captures still repeat byte for byte ([09](research/landscape-investigations/09-lighting-color-lookdev.md), measured) | L1b settings fixed with numbers. Sun colour `#ffe9d7` (5200 K at 45°, Godot's own formula) in L3 |
| **Alpha-to-coverage does nothing in Compatibility 4.7.2** (`// Do nothing for now.`; three settings gave byte-identical captures); alpha hash is not implemented either ([04](research/landscape-investigations/04-trees-and-impostors.md), [05](research/landscape-investigations/05-grass-rendering.md), src and measured; #98173, PR #114845 open) | Foliage is either **opaque geometry** (grass blades) or **alpha scissor** with `fix_alpha_border` (tree cards). L11 is rewritten |
| Opaque geometric grass clumps (7 triangles) look better than alpha cards; one MultiMesh = +1 draw call; 6,000 clumps = +36k primitives; captures repeat ([05](research/landscape-investigations/05-grass-rendering.md), measured) | L11a: near-field blades only (≤ 30 m) |
| FlightGear trees: 3 crossed quads each; the only per-tree data is its position (rotation, scale and variety are derived from it in the shader); a 60/30/10 % staggered appearance instead of a fade ([04](research/landscape-investigations/04-trees-and-impostors.md), [07](research/landscape-investigations/07-open-source-sims-scenery-code.md), GPL/LGPL: idea only) | L6: tree placement files store positions only; staggered ranges for the moving cameras |
| proctree.js (BSD-3) and ez-tree v1.1.0 (MIT, bark CC0) are good offline tree sources; Poly Haven `fir_tree_01` has 7.85 M polygons; godot-imposter has no mipmaps ([04](research/landscape-investigations/04-trees-and-impostors.md)) | L6c: offline tree meshes ≤ 1k triangles; no impostor plugin |
| Ground spike (anti-tiling + macro variation + mown runway stripes): captures repeat byte for byte. **The far runway edge step is only 6 % today**, and stripes (±7 %) eat into it ([06](research/landscape-investigations/06-ground-anti-tiling.md), measured). Tiling must be measured from straight above | L9 is split; a top-down review view is added; stripe amplitude ≤ half the edge step |
| Float64 sampler vs rendered mesh: **0.0 m difference at 100,000 random points** with the same triangle diagonal; the other diagonal is off by 2.5 cm. 256² vertices build in ~0.1 s; sampler 1.1–1.8 µs per call ([03](research/landscape-investigations/03-terrain-mesh-gdscript.md), measured) | L12 design confirmed and split into sampler, near mesh and far rings |
| Integer-only generator (`lowbias32` hash, Unlicense): plain Python and NumPy give the **same SHA-256** for a 1251² grid; NumPy random and float noise do not guarantee that ([08](research/landscape-investigations/08-terrain-generation-tools.md), measured) | L13a generator is `tools/terrain/gen_terrain.py`, integers only. No erosion (hills 2 km away sit in haze) |
| `app/export_presets.cfg` exports only `data/*.json`; a binary terrain file would be missing from release builds ([08](research/landscape-investigations/08-terrain-generation-tools.md)) | L12a widens the export filter, proved by the export smoke test |
| **Render counters read 0 under `--headless`** (dummy renderer); CI does not pin Mesa; llvmpipe's thread count defaults to the core count; mean image metrics miss a small airplane (a changed 16×16 block scored mean FLIP 0.0004) ([10](research/landscape-investigations/10-visual-testing-tools.md), measured and src) | L0b–L0d: pin thread count and Mesa, key golden hashes by renderer string, compare by FLIP bad-pixel count |
| FAA AC 150/5345-27E windsock Size 1: 2.5 m long, 0.45 m throat, full extension at 15 kt; Canada AIM droop table: 6 kt → 30°, 10 kt → 5°, ≥ 15 kt horizontal. `float`/`vec3` global shader uniforms work in Compatibility; `INSTANCE_CUSTOM` is packed to 16 bits ([11](research/landscape-investigations/11-wind-animation-ambience.md)) | L10 windsock dimensions are sourced data; L15 is split into five testable steps driven by a sim clock |

## Decisions this plan makes

| Decision | Choice | Why | Revisit when |
| --- | --- | --- | --- |
| Renderer | Stay on **Compatibility** | Web export, software-GL captures; sky shaders, fog, PSSM shadows, MultiMesh, MSAA and mesh LOD all work there | A Gate says the look needs SSR/volumetrics |
| Scene type | **3D near field + far rings**, not a photo panorama | Keeps the chase/inspect cameras, sun shadows, collision and determinism consistent; downloads stay small. Photo fields break every non-fixed camera and need hand-aligned collision proxies (RealFlight/Aerofly complaints) | Optional photo sky in L16 |
| Sky | **Our own sky shader**: Hosek-fitted gradient + 0.53° sun disc + flat cloud layer from in-shader integer-hash noise; `use_debanding`; `Sky.process_mode = QUALITY` | Built-in physical sky and HDR panoramas have open brightness bugs; every third-party sky reads `TIME` or needs passes Compatibility lacks; a shader costs no download | — |
| Atmosphere | **One source of truth**: `Spec.ATMOSPHERE` (visibility, haze colour, sun) → `render/atmosphere.gd` sets sky uniforms, `Environment` fog and the `DirectionalLight3D` together | Aerial perspective is a no-op in 4.7.2 Compatibility, so the sky must reproduce the engine's fog term exactly or the horizon shows a seam | — |
| Animation clock | **Never `TIME`.** A global `sim_clock` uniform = simulation time wrapped to [0, 1024) s on the CPU in float64; every animation frequency is a multiple of 1/1024 Hz, so the wrap is seamless. Wind arrives as the global `wind_vec` | Byte-identical captures; animation follows paused, replayed and fixed-fps runs like the physics | — |
| Foliage | **Opaque geometry near, alpha-scissor cards far**; no alpha-to-coverage, no alpha hash | Neither works in Compatibility 4.7.2 | 4.8+ if PR #114845 lands |
| Level of detail | **Fixed per object by its distance from the pilot station**; staggered 60/30/10 % ranges only for chase/inspect cameras | The pilot never moves; Compatibility has no visibility-range fade; haze is too thin to hide pops | — |
| Terrain | **DIY heightmap chunks** from one committed, quantised grid; float64 triangle-exact sampler in `sim/` | Measured exact (0.0 m); no binary dependency; works on web. Terrain3D's `get_height` is bilinear and single precision | Large-scale sculpting/painting → Terrain3D gate (L18) |
| Terrain data | **`openrc-terrain v1`**: int16 little-endian `.bin` (height × 256, i.e. 1/256 m steps) + JSON sidecar (size, spacing, origin, diagonal rule, min/max, SHA-256, seed, parameters, source, license) | Exact in float32 and float64; 3.1 MB for 5 km at 4 m; `FileAccess` reads little-endian | — |
| Generation | **Offline, integer-only Python** (`tools/terrain/gen_terrain.py`, stdlib only, NumPy optional with identical bytes); output committed with SHA-256; CI re-runs it with `--check` | FastNoiseLite is float32 and not guaranteed bit-identical across OS/arch | — |
| Trees | **Offline-generated meshes** (proctree.js port, BSD-3; or ez-tree v1.1.0, MIT) ≤ 1k triangles; far trees as crossed-quad cards from a 1024² atlas baked offline; placement files store positions only | Small, deterministic, ours; no impostor plugin needed for a static pilot | — |
| Assets | **CC0 first** (Poly Haven, ambientCG, Kenney, Quaternius); CC-BY only with an in-game credit; never Textures.com, GPL/AGPL art or tools in the build. Every file gets a provenance entry (URL, license, author, date, SHA-256) | Open-source repo and redistributed builds | — |
| Field data | `app/data/fields/*.json`, format `openrc-field v1`, every value `{value, unit, kind, source}`; each object carries `visible` and `collides` flags (CRRCSim's separation); surface rectangles (runway, mown, rough) feed both the ground shader and later ground physics | Same discipline as physics data; layout distances from AMA/BMFA; one source for what is drawn and what is hit | — |
| Visual testing | **Two tiers:** SHA-256 when the renderer string matches the golden's; otherwise FLIP 1.7 bad-pixel count (FLIP > 0.1). Readability measured as the airplane's contrast against its local background | Byte equality only holds for one pinned Mesa and thread count; mean metrics miss a 15 px airplane | — |

## Budgets (measured, not hoped)

These come from ROADMAP rule 7.

- **Frame time:** p95 measured on the owner's slowest machine at each gate, with the frame-time logger from L0e. llvmpipe numbers are never used for performance.
- **Draw calls and primitives:** read from `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` / `RENDER_TOTAL_PRIMITIVES_IN_FRAME` **in the Xvfb + `opengl3` capture run** (they read 0 under `--headless`, which uses the dummy renderer) in fixed capture views. They are deterministic, so they can be checked in tests.
  - **Starting budget** (estimated, to be revised at Gate L), revised 2026-10-05 after the L0 count (the owner asked why 150 was so low): the **landscape alone ≤ 300 draw calls and ≤ 1 M primitives**, measured in views without the airplane.
  - The **airplane is budgeted separately.** It alone uses ~100 draw calls and ~46,500 primitives; the model team can merge meshes or share materials.
  - Draw calls are only a proxy. On a desktop, Godot's OpenGL renderer handles several hundred per frame comfortably; 150 was a worst-case guess for web and low-end machines.
  - **The real budget is frame time p95 on the owner's slowest machine (F3 overlay) at Gate L.** The draw-call numbers are raised or lowered to match what that machine does.
- **Vegetation alone:** ≤ 24 draw calls for trees ([04](research/landscape-investigations/04-trees-and-impostors.md), estimate) and ≤ 5 for grass ([05](research/landscape-investigations/05-grass-rendering.md), from the measured +1 per MultiMesh).
- **Video memory:** `RENDER_VIDEO_MEM_USED` is Godot's own tally in Compatibility, so it repeats and can be checked. The budget is set from the L0b manifest plus 64 MB (estimate).
- **Download:** landscape assets add ≤ 15 MB to a desktop build. Textures ≤ 2048 px (≤ 4096 for one sky backdrop at most), so the web stays possible.
- **Physics:** the terrain height query adds ≤ 10 µs/tick (from `bench_physics.gd`). The spike measured 1.1–1.8 µs per call, and the query is skipped when the airplane is above the highest terrain.

## L0 baseline (2026-10-05, llvmpipe, 1280×720)

| View | Draw calls | Primitives | What it shows |
| --- | --- | --- | --- |
| Horizon, az 90/180/270, el 0 or 10 (no airplane in view) | 5–6 | ~870 | flat sky colour; the 1 km ground edge as a hard horizon line |
| Horizon az 0 (airplane in view), 30 m view, 3 m low pass | 105–107 | ~47,300 | same, plus the airplane; the runway is a pale band without edges |
| Toward the sun (az 225, el 25) | 4 | 868 | sky only: no sun, no gradient |

**Budget finding:** the airplane alone costs ~100 draw calls and ~46,500 primitives (the model team's mesh), so the first ≤ 150 draw-call budget would have left ~50 for the whole landscape. Budgets above now count the landscape on its own; the model team is asked whether the airplane's surfaces can share materials or be merged into fewer meshes.

**Readability baseline** (spike, 3 m view, [09](research/landscape-investigations/09-lighting-color-lookdev.md)): airplane Weber contrast −0.53, 13 % of its pixels below |0.1| contrast (the white livery against the bright horizon), ΔE 38.1. L0c re-measures it in the real harness.

## Steps

Step IDs are `L*`. Each row is one small change that keeps `app/test.sh` green. Investigation numbers in brackets point to the evidence.

### Phase L-A: Look up (sky, light, haze)

| # | Step | Proof |
| --- | --- | --- |
| L0 ✅ | **Landscape review captures and counters.** `capture.sh` adds a fixed set: horizon views at 4 azimuths (pilot eye, 0° and 10° up), the 30 m trimmed view, the 3 m low pass, and a view toward the sun. A small helper prints draw calls and primitives per view. No visual change yet | Captures repeat byte for byte (two runs); baseline counters recorded in this file. ✅ 2026-10-05: `capture.sh` adds 11 `capture-land-*` views (`--look_az/--look_el` fixed views from the pilot's eye) and writes `captures/landscape-counters.txt`; all 19 captures + counters byte-identical across two runs. Baseline above |
| L0b | **Determinism probe and manifest** [10]. Each capture also writes `<view>.json` with: SHA-256, visible and shadow-pass draw calls, primitives, objects, video memory, `get_video_adapter_name()`, Godot version and `LP_NUM_THREADS`. Compare `LP_NUM_THREADS=1` against the default, on this VM and in CI; pin the winning value in `capture.sh`; pin or log the Mesa version (`libgl1-mesa-dri=<ver>`, this VM has `25.2.8-0ubuntu0.24.04.2`). Add a **top-down view** of the ground [06] | Two runs give identical manifests with non-zero counters; a recorded byte-match table (threads × machine) |
| L0c | **Two-tier compare and readability metric** [09][10]. `tests/compare_captures.py` with a pinned, hashed `requirements-visual.txt` (flip-evaluator 1.7, numpy 2.5.3, pillow 12.3.0). Tier 1: SHA-256 when the renderer string matches. Tier 2: count pixels with FLIP > 0.1 (≤ 50, estimate set from L0b noise). Readability: capture each review view with and without the airplane, then compute Weber contrast against the surrounding pixels, the share of pixels with \|contrast\| < 0.1, and ΔE | On a copy, a 16×16 mutation fails and ±1-level noise passes; baseline readability numbers recorded here |
| L0d | **Sim clock and `TIME` ban** [11]. `test.sh` fails on any `TIME` in a shader under `app/`. Global shader uniforms `sim_clock` (float64 sim time wrapped to [0, 1024) s) and `wind_vec` (zero for now) are registered and fed by the session | A scratch-copy mutation that adds `TIME` fails `test.sh`; `sim_clock` equals the simulation's time mod 1024 at three ticks; captures unchanged |
| L0e | **Frame-time logger** [10]: p50/p95/p99 frame time over a fixed scripted flight, written to a file, for Gate L on real hardware | Runs on the owner's machine; numbers recorded here (llvmpipe numbers marked as not performance) |
| L1a ✅ | **Sky background shader** [01][02]: `render/sky.gdshader` + `render/atmosphere.gd`. Gradient `pow(1−y, 2.6)` from zenith `#4e6893` to horizon `#c9e3ed` (Hosek-Wilkie at 45° sun), sun disc 0.53° from `Spec` (not `LIGHT0_SIZE`, which defaults to 0), `render_mode use_debanding`, background drawn per pixel, radiance only for lighting, `Sky.process_mode = QUALITY`. Drafted outside `app/` until it parses | Captures byte-repeat; the zenith is darker than the horizon in every review view; the sun disc's centre is within 2 px of the projected light direction (spike: 0.6 px); the longest run of equal pixels down a sky column is ≤ 3 px; `--trace` bytes unchanged. ✅ 2026-10-05 (done before L0b–L0e; it began as an earlier L1 draft and was aligned to this spec when the plan was revised): `render/sky.gdshader` (Hosek-fitted gradient, 0.53° disc + halo from `LIGHT0`, `use_debanding`, no `TIME`) + `render/atmosphere.gd` (environment, sky uniforms and the sun light from one `Spec.ATMOSPHERE`; `Spec.SUN` removed); grass and runway matte. `tests/check_landscape_captures.py` (run by `capture.sh`, which now also fails on engine errors): zenith darker in all 11 views, longest equal run 2 px, sun disc 0.71 px off. Byte-identical captures; `--trace` identical to HEAD. Mutations: inverted gradient → fails in every view; no `use_debanding` → runs of 6–16 px, fails. Tonemap still Linear: L1b sets Filmic 0.8 with its readability proof |
| L1b | **Sky light and tonemap** [09]: ambient and reflections from the sky, Filmic, exposure 0.8, white 1.0, glow off. Sky ambient lightens the grass, so this step sets new capture baselines | At the 3 m view: airplane contrast ≤ −0.40, \|contrast\| < 0.1 on ≤ 15 % of its pixels, ΔE ≥ 30; sky saturation ≥ 25 (not grey); bytes repeat |
| L2 | **Haze and the horizon** [02][07]. Exponential fog, density = 3.912 / 23,000 m⁻¹ (23 km clear-day visibility, MODTRAN; labeled). The sky's lower half and horizon band equal the engine's object fog colour, `fog_light_color·energy + sun·π·pow(dot(view, sun), 8)·fog_sun_scatter`, using linear colours (`LIGHT0_COLOR` is sRGB). `fog_sky_affect = 0`, `fog_aerial_perspective = 0` (a no-op anyway). Instead of only growing the plane: a coarse **outer ground ring** to ~6 km with a **rim fade** in the ground shader, and `Spec.CAMERA.far` ≥ ring radius + 5 % | A headless test (no GPU): fog colour == haze, `fog_sun_scatter` == the sky uniform, sun direction == light basis within 1e-6. A pixel-row test in the 4 horizon views: no step larger than N levels across the horizon line, from the pilot's eye and from 100 m up |
| L3 | **Sun shadows** [09]: `DirectionalLight3D` shadows on, PSSM 2 splits, Max Distance ~300 m (estimate). Sun colour `#ffe9d7` (5200 K at 45°, Godot's formula; physical light units stay off). Re-tune the light energy: shadows make lit surfaces brighter in Compatibility (#90259). The vertical pilot-aid shadow stays as a toggle; Gate L decides which is default | Close-up capture shows the sun shadow offset by the sun angle; a sunlit white wing stays at L < 0.95 (no clipping); the L1b readability numbers still pass; counters within budget |
| L4 | **Clouds** [01]: a flat cloud layer in the sky shader, from in-shader value noise over an integer hash (no textures). Seed in `Spec`. Drift = wind aloft × `sim_clock`, quantised to at most one sky update per second (each update re-renders the radiance) | Captures byte-repeat; the same sim time → the same sky; a capture pair at t and t + 10 s differs only in the sky (FLIP mask) |

### Phase L-B: Look around (horizon ring)

| # | Step | Proof |
| --- | --- | --- |
| L5 | **Field data file**: `openrc-field v1` with runway, pilot station, safety line, pits, parking and flight box. Values come from AMA "Suggested Flying Site Specifications" (2022) and the BMFA handbook, each with `source`. Objects carry `visible`/`collides` flags [07]. **Surface rectangles** (runway, mown, rough) feed the ground shader (L9c) and later ground physics. The current `Spec.RUNWAY` moves in; the loader refuses invalid data | Loader tests (valid, missing unit, wrong kind refused) as for the aircraft data; captures byte-identical (same numbers, new home) |
| L6a | **Tree sources** [04]: `tools/trees/` ports proctree.js (BSD-3, its own deterministic random) to an offline tool, or exports ez-tree v1.1.0 (MIT) species as GLB. Each mesh ≤ 1k triangles, 3–4 species. Then a **1024² card atlas** is baked offline under Xvfb from those meshes, with alpha scissor and `fix_alpha_border` | SHA-256 and provenance entry per file; triangle counts tested; the atlas re-bakes byte-identically |
| L6b | **Treeline ring** 250–600 m from the pilot, with gaps [04][07]. Crossed-quad cards (3 quads each, FlightGear's idea), in **8 azimuth-sector MultiMeshes**. The placement file stores **positions only**; the shader derives rotation, scale (12–25 m, labeled estimate) and species from a hash of the position. Placement is generated offline and committed | Placement file SHA-256 test; horizon captures show an unbroken but varied silhouette; ≤ 24 vegetation draw calls |
| L6c | **Readability against trees** [09]: the L0c metric with the airplane in front of the treeline and low over grass (red over green is the weakest pairing: about −0.18 brightness contrast, estimated from flat colours, so ΔE carries it) | Numbers recorded; Gate L thresholds proposed from them |
| L7 | **Far rings** [04][07]: a forest strip at 600–1500 m (~1 draw call) and a low-poly hill ring at 2–5 km, both without collision, faded into the horizon colour by L2's fog. The hill silhouette is generated by the L13a tool and committed | Horizon captures; ≤ 3 extra draw calls |
| L8 | **3D trees near the pilot** [04][07]. Within ~150 m, the L6a meshes replace cards. Each tree's form (mesh or card) is **fixed by its distance from the pilot station**, so the pilot view never pops. For chase and inspect cameras, use staggered ranges (60 % of trees at r, 30 % at 1.5 r, 10 % at 2 r) instead of a fade | Card and mesh silhouettes match (IoU ≥ 0.9 in an offline render); a 10-frame pilot-view strip has no change across the switch distance |

### Phase L-C: Look down (the field)

| # | Step | Proof |
| --- | --- | --- |
| L9a | **Ground shader at parity** [06]: a `ShaderMaterial` that reproduces today's grass look | Mean brightness per screen-region band within ±1 level of the L0 captures |
| L9b | **Anti-tiling and macro variation** [06]: a 2-fetch anti-tiling sampler (our own code, from the Quilez "technique 3" idea), macro colour variation at 37 m and 160 m, and Hoskins' "Hash without Sine" (MIT) instead of `sin()` hashes | Top-down capture: the autocorrelation peak at the 6 m tile period drops by a threshold set from L0b; bytes repeat |
| L9c | **Field surfaces in the shader** [06], from the L5 rectangles: runway with mown stripes, a mown area and a darker rough beyond it. The separate runway mesh is removed. Stripe amplitude ≤ half the runway edge step. First find out why the far edge step is only 6 % today (the same texture through a shader gives 27 %) | Edge-contrast pixel test at 100 m above an L0c-derived threshold; low-pass capture |
| L11a | **Near-field grass blades** [05] (moved up so the runway proof is measured with and without grass). Opaque 7-blade clumps (no alpha) within 30 m of the pilot, shrinking to nothing between 22 and 30 m, none on the runway, ≤ 4 chunks, no shadow casting. Placement generated offline and committed with a SHA-256; sway from `sim_clock` and `wind_vec` | ≤ +5 draw calls and ≤ +100k primitives; bytes repeat; no visible seam in the 25–35 m band (FLIP mask) |
| L10 | **Known-size objects** from the field file: pilot stations, orange safety fence, pit tables/canopy, 3–4 cars (Kenney Car Kit, CC0), flag pole and a **windsock built to FAA AC 150/5345-27E Size 1** (2.5 m × 0.45 m throat, 5 stripe segments [11]), static until L15a. Built from primitives in code where no CC0 model exists | Captures; each object's size is checked against the field file in a test; provenance lists every asset |
| L11b | **Bushes and flowers** [05]: CC0 low-poly geometry (Quaternius/Kenney), no alpha | Counters within budget; bytes repeat |
| L9d | *(Optional)* **Photo grass**: ambientCG Grass001–004 (CC0, 1.4 m tile) with Mikkelsen hex-tiling (MIT) [06] | Only if Gate L says the procedural ground looks too synthetic; the L9b repeat test still passes |
| **Gate L** | **"Does the landscape help or hurt flying?"** The owner flies the Gate 2 maneuver list in the new field. Measured: orientation read correctly at 100 m against sky and against the treeline; landing approaches using the treeline as the turn reference; frame time p95 with the L0e logger on the slowest machine; draw calls; video memory; download delta | Notes and ratings recorded; budgets adjusted in this file; anything that hurts readability is reverted or toned down |

### Phase L-D: The ground becomes physical (with M2)

| # | Step | Proof |
| --- | --- | --- |
| L12a | **`sim/terrain.gd` and `openrc-terrain v1`** [03][08]. A float64 height function over the committed grid: pick the cell with `floor`, pick the triangle by the documented diagonal rule, evaluate the plane in float64. The loader refuses a bad SHA-256, size or type. The query is skipped when the airplane is above the highest terrain. Add `data/terrain/*` to `include_filter` in both export presets. **The grid starts all-zero**, so `touches_ground` uses it with no behaviour change | Known-sample tests (vertices, cell centres, both triangles); checksum test; **golden flights and `--trace` bytes unchanged**; µs/tick reported; the export smoke test loads the terrain |
| L12b | **Near mesh** [03]: ±512 m as 4 × 4 chunks of 64 quads (≤ 65,536 vertices each, so 16-bit indices), built from the same grid and diagonal at startup (~0.1 s measured); no vertex compression (it would break exactness) | A headless test reads the mesh back and compares it with `terrain.gd` at 100,000 random points: difference 0.0 m (spike result) |
| L12c | **Far terrain rings** [03] to ~2.5 km, built once (the pilot never moves, so there is no LOD switching); outer border heights linearised offline so there are no cracks and no skirts. **Out-of-range boundary at ±512 m**, so physics never needs the far rings | Crack test along each ring border; out-of-range behaviour in a scripted flight |
| L13a | **Terrain generator** [08]: `tools/terrain/gen_terrain.py`, plain Python 3.12 stdlib, integers only (`lowbias32` hash, `isqrt` masks, heights in 1/256 m). NumPy 2.5.3 optional with identical bytes. Flat masks under the runway, pits and parking; gentle swales; the hill ring. It writes the grid, its JSON sidecar and a heightmap PNG for review. CI re-runs it with `--check`, like `compile_geometry.py --check`. No erosion | Stdlib and NumPy outputs have the same SHA-256; `--check` fails on an edited grid in a scratch copy |
| L13b | **Relief in the world**: the generated grid replaces the zero grid; the renderer and physics read the same file | Crash on a hillside caught in a scripted trace; the L12b read-back test still gives 0.0 m |
| L14 | **Trees as obstacles**: each placed tree with `collides` becomes a float64 cylinder (trunk + crown) in `sim/`, read from the same placement file as the renderer | A scripted flight into a tree crashes at the right tick; a flight between trees does not |
| L15a | **Windsock dynamics** [11] (after M5 wind): it points along the air velocity from `air_data.gd`; droop from the Canada AIM table (6 kt → 30°, 10 kt → 5°, ≥ 15 kt horizontal), first-order lag τ ≈ 0.6 s (estimate), 5 segments | Unit tests against the table; captures with two wind settings show the matching angle |
| L15b | **Tree bending** [11]: whole-plant bending only (GPU Gems 3 ch. 16 idea), from `wind_vec` and `sim_clock` | A pixel-displacement test at a set wind speed (about 1 px at 400 m without zoom, ~5 px at 10° auto-zoom: calculated) |
| L15c | **Grass, bushes and flags** follow the same wind uniforms | Captures differ only in the vegetation between two wind settings |
| L15d | **Cloud shadows** on the ground, in the ground shader's `light()`, offset by wind aloft × `sim_clock` | The same sim time gives the same shadow pattern; byte-repeat |
| L15e | **Wind sound** synthesised like `engine_sound.gd` (testable without a sound card) | A unit test on the generated samples, as for the engine sound |

### Optional tracks (only if a gate asks)

| # | Step | When |
| --- | --- | --- |
| L16 | **Photo sky option**: a CC0 Poly Haven `*_puresky` HDRI at ≤ 2k for lighting + an LDR ≤ 4k backdrop, selectable in the field file. **It carries its own sun direction** [07], which drives the light and shadow | If Gate L says the procedural sky looks too synthetic |
| L17 | **The owner's own field**: either a 360° panorama at 1.70 m eye height (Insta360/Theta/phone + Hugin) with collision and occlusion proxies, or a real DEM. The DEM path: CNIG MDT LiDAR PNOA, CC-BY 4.0 with the product's credit, through GDAL 3.13.3 (`gdal raster reproject`) or rasterio 1.5.2, into the same integer grid and flat masks as L13a [08] | When the owner wants to fly their club field |
| L18 | **Terrain3D gate** (MIT, v1.0.2): adopt only if we need sculpting/painting at scale. Pin zip + SHA; still export its heightmap into our own triangle-exact sampler; web stays experimental | If L13's DIY chunks become a bottleneck |
| L19 | **Time of day and weather**: per-pixel Hosek-Wilkie (the CPU computes 27 coefficients when the sun moves), with `fog_light_color` taken from the same evaluation [02]. **Sun glare**: glow plus a CC0 flare on a CanvasLayer, hidden behind terrain and trees by our own float64 ray test [09]. **Birds**: off by default and in tests [11] | Playtest wish; the L2 equality test at 5 sun elevations |
| L20 | **Sky-grid pilot aid** (orientation circles on the sky dome; PicaSim idea) [07] | If Gate L shows orientation is lost in clear sky |

## Libraries and tools chosen (pin exact versions)

| Name | Version | License | Use |
| --- | --- | --- | --- |
| Godot built-ins (`use_debanding`, Filmic, MultiMesh, global uniforms) | 4.7.2-stable | MIT | sky, light, vegetation, animation clock |
| Hosek-Wilkie RGB data | 1.4a | BSD-3 | L1a colours (fitted), L19 per-pixel sky |
| Hoskins "Hash without Sine" | — | MIT | shader noise (L4, L9b) |
| proctree.js (port) / ez-tree | 2019 / v1.1.0 | BSD-3 / MIT (bark CC0) | offline tree meshes (L6a) |
| `lowbias32` hash (hash-prospector) | 2024-03 | Unlicense | terrain generator (L13a) |
| Python stdlib / NumPy | 3.12 / 2.5.3 | PSF / BSD-3 | generator, compare scripts |
| flip-evaluator / Pillow | 1.7 / 12.3.0 | BSD-3 / MIT-CMU | two-tier capture compare, readability (L0c) |
| GDAL / rasterio | 3.13.3 / 1.5.2 | MIT / BSD-3 | real DEM path (L17) only |
| Mikkelsen hex-tiling | 2022 | MIT | optional photo grass (L9d) |
| RenderDoc | v1.46 | MIT | manual frame inspection, never in CI |

**Excluded:**
- Sky3D, Universal Sky, MMqd Nishita: they read `TIME`, need passes Compatibility lacks, or need textures. Ideas only.
- godot-imposter: no mipmaps, unverified on 4.7.
- Gaea and World Machine: non-commercial licenses.
- Blender A.N.T.: GPL, sketching only.
- opensimplex: archived.
- SimpleHydrology: no license.
- dssim: AGPL.
- FlightGear, CRRCSim and PicaSim code: GPL / PolyForm NC, ideas only.

## Ownership and parallel work

- **Who owns which files:**
  - Rendering of the world belongs to the main line: `main.gd` `_build_world`, `render/ground.gd`, and the new `render/sky.gdshader`, `render/atmosphere.gd`, `render/field.gd` and `render/vegetation.gd`.
  - `sim/terrain.gd` (L12+) is physics: it follows the 64-bit rules and is reviewed with Phase E (ground contact E1–E3 will query it).
  - Do not touch the model team's `airplane`/hinge interface. Field props are separate nodes. The model team is asked about merging the airplane's ~100 draw calls.
- **New landscape assets:** they go in `assets/landscape/`, with `assets/landscape/PROVENANCE.json` (one entry per file). Offline tools go in `tools/terrain/` and `tools/trees/`; their outputs are committed with SHA-256.
- **Drafts:** shaders are drafted **outside `app/`** until they parse: `test.sh` parses every script, and a broken draft breaks everyone's run.

## Risks we already know

- **Banding:** the output is LDR RGBA8. Sky debanding (`use_debanding`) weakens once glow, SSAO or adjustments are on, and ground materials get none.
- **Aerial perspective is a no-op in 4.7.2 Compatibility.** If L2's equality test is skipped, the horizon shows a seam between sky and fog.
- **Alpha-to-coverage and alpha hash do nothing** (#98173, #103094; fix PR #114845 open). Foliage is opaque geometry or alpha scissor.
- **Thin haze hides nothing at 400 m.** LOD must be fixed per object, never "hidden in fog".
- **Brighter lit surfaces once shadows are on** (Godot #90259). Re-tune in L3 and check against the L1b readability numbers.
- **No decals until 4.8.** Runway markings are shader or geometry.
- **`TIME` anywhere** forces radiance updates and breaks byte-identical captures. The L0d test bans it; every third-party shader we found uses it.
- **Packing limits:** `INSTANCE_CUSTOM` is 16-bit in Compatibility. It can carry a phase per plant, never a position.
- **Mesa or thread-count drift** changes capture bytes. L0b pins them, and L0c's FLIP tier keeps CI meaningful across Mesa versions.
- **Export filter:** binary data outside `data/*.json` is silently missing from release builds unless `include_filter` is widened (L12a).
- **The treeline makes the airplane harder to see.** That is realistic and part of RC flying, but Gate L must check it does not make the sim unfun (auto-zoom helps).
- **Software-GL captures prove repeatability, not performance.** Frame time is judged only on the owner's hardware.
