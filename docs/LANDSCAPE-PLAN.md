# Landscape plan: from a flat green plane to a real flying field

Written **2026-10-05**. Evidence and sources: [docs/research/landscape-research.md](research/landscape-research.md). Follows the [ROADMAP](../ROADMAP.md) rules: one small step per change, one objective proof per step, guessed numbers labeled, lessons to LEARNINGS.md.

## Why, in one picture

Today the pilot view at 30 m is **~98 % flat blue sky** with a 10 px green strip at the bottom. The scripted circle shows no ground at all. The camera tracks the airplane upward, so **the sky is the background of nearly every frame**, and today it carries no information.

So the order is the reverse of the usual "build terrain first":

1. **Sky and light** (what the pilot sees 90 % of the time).
2. **Horizon ring** (treeline, hills, haze: attitude and distance at low level).
3. **The field itself** (runway, known-size objects, ground texture: height and speed cues for takeoff and landing).
4. **Terrain relief and obstacles in physics** (only when M2 ground contact needs it).

**Design goal:** cues before beauty. Research says object density and contrast help pilots more than detail (Kleiss & Hubbard 1993; Lintern et al.). Each step is judged by what it adds to *flyability* and by a capture, not by "looks nicer".

## Decisions this plan makes

| Decision | Choice | Why | Revisit when |
| --- | --- | --- | --- |
| Renderer | Stay on **Compatibility** | Web export, software-GL captures; everything below works there (sky shaders, depth/height fog, PSSM shadows, MultiMesh, MSAA, mesh LOD) | A Gate says the look needs SSR/volumetrics |
| Scene type | **3D near field + far ring**, not a photo panorama | Keeps the chase/inspect cameras, sun shadows, collision and determinism consistent; downloads stay small. Photo fields break every non-fixed camera and need hand-aligned collision proxies (RealFlight/Aerofly complaints) | Optional photo sky in L12 |
| Sky | **Our own sky shader** (procedural gradient + sun + clouds from noise computed in the cubemap pass) | `PhysicalSkyMaterial` and HDR panoramas have open brightness bugs in Compatibility; a shader costs no download; no `TIME`, so it stays deterministic | — |
| Terrain | **DIY heightmap chunks** from one committed, quantised grid; float64 triangle-exact sampler in `sim/` | Physics height == rendered height by construction; no binary dependency; works on web. Terrain3D's `get_height` is bilinear and single precision | We need large-scale sculpting/painting → Terrain3D gate (L13) |
| Generation | **Offline, seeded, committed with SHA-256**; the runtime only loads data | FastNoiseLite is float32 and not guaranteed bit-identical across OS/arch | — |
| Assets | **CC0 first** (Poly Haven, ambientCG, Kenney, Quaternius); CC-BY only with an in-game credit; never Textures.com or GPL art. Every file gets a provenance entry (URL, license, author, date, SHA-256) | Open-source repo and redistributed builds | — |
| Field data | `app/data/fields/*.json`, format `openrc-field v1`, every value `{value, unit, kind, source}` like the aircraft data; the loader refuses invalid data | Same discipline as physics data; layout distances come from AMA/BMFA documents, not guesses | — |

## Budgets (measured, not hoped)

These come from ROADMAP rule 7.

- **Frame time:** p95 measured on the owner's slowest machine at each gate. llvmpipe numbers are never used for performance.
- **Draw calls and primitives:** measured headlessly from `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` / `RENDER_TOTAL_PRIMITIVES_IN_FRAME` in fixed capture views. These are deterministic, so they can be checked in tests. **Starting budget** (estimated, to be revised at Gate L): ≤ 150 draw calls and ≤ 1 M primitives in the pilot view.
- **Download:** landscape assets add ≤ 15 MB to a desktop build. Textures ≤ 2048 px (≤ 4096 for one sky backdrop at most), so the web stays possible.
- **Physics:** the terrain height query adds ≤ 10 µs/tick (from `bench_physics.gd`).

## Steps

Step IDs are `L*`. Each row is one small change that keeps `app/test.sh` green.

### Phase L-A: Look up (sky, light, haze)

| # | Step | Proof |
| --- | --- | --- |
| L0 | **Landscape review captures and counters.** `capture.sh` adds a fixed set: horizon views at 4 azimuths (pilot eye, 0° and 10° up), the 30 m trimmed view, the 3 m low pass, and a view toward the sun. A small helper prints draw calls and primitives per view. No visual change yet | Captures repeat byte for byte (two runs); baseline counters recorded in this file |
| L1 | **Sky shader**: vertical gradient (zenith → horizon), sun disc placed from `Spec.SUN` (same vector as the `DirectionalLight3D`), ordered dithering against LDR banding. Sky ambient and reflections, `Sky.process_mode = QUALITY`, Filmic or AgX tonemap. The spike already ran this (see research §0) | Captures byte-repeat; a pixel test: the zenith is darker than the horizon in every review view; the sun disc's screen position matches the projected light direction within 2 px; trace bytes unchanged (rendering only) |
| L2 | **Aerial perspective**: depth fog coloured like the sky's horizon, so the ground's far edge disappears into haze. Ground plane grows to ≥ 6 km (float32 is fine to 4–8 km). Fog colour comes from one constant shared with the sky | The 4 horizon captures show no hard ground edge (a pixel-row test: no step > N levels across the horizon line) |
| L3 | **Sun shadows**: `DirectionalLight3D` shadows on, PSSM 2 splits, Max Distance ~300 m (estimated); light energy re-tuned (shadows make lit surfaces brighter, Godot #90259). The vertical pilot-aid shadow stays as a toggle; the Gate decides which is default | Close-up capture shows the sun shadow offset by the sun angle; the low-pass capture shows it; frame counters within budget |
| L4 | **Clouds**: noise-based cloud layer in the sky shader, computed in `AT_CUBEMAP_PASS` (radiance cached, not per pixel per frame). A seed in `Spec`. Drift is driven by a uniform fed from **simulation time**, never `TIME` | Captures byte-repeat; the same sim time → the same sky; a capture pair at t and t+10 s differs only in the sky |

### Phase L-B: Look around (horizon ring)

| # | Step | Proof |
| --- | --- | --- |
| L5 | **Field data file**: `openrc-field v1` with runway, pilot station, safety line, pits, parking and flight box, values from AMA "Suggested Flying Site Specifications" (2022) and the BMFA handbook (each with `source`). The current `Spec.RUNWAY` moves into it; the loader refuses invalid data | Loader tests (valid, missing unit, wrong kind refused) as for the aircraft data; captures byte-identical (same numbers, new home) |
| L6 | **Treeline ring** 250–600 m from the pilot, with gaps: low-poly CC0 trees (Quaternius/Kenney) or our own procedural ones, in **MultiMesh chunks** per species. Heights 12–25 m (labeled estimate). Placement is seeded **offline** and committed as a list. It gives the horizon for attitude, a known-height reference, and the real "airplane lost against dark trees" problem | Horizon captures show an unbroken but varied silhouette; placement file SHA-256 test; draw calls within budget; Gate 2-style readability check: orientation at 100 m against sky *and* against trees |
| L7 | **Far hills ring** 2–5 km: one low-poly ring mesh, no collision, fogged into the sky colour. Its silhouette is offline-generated and committed | Horizon captures; ≤ 2 extra draw calls |
| L8 | **Distant-tree billboards**: trees beyond ~400 m switch to a 2–4 view billboard atlas by visibility range. Compatibility has no fade, so the switch distance sits where fog hides the pop | Primitive count drops by ≥ 50 % in the horizon views; pop not visible in a 10-frame capture strip |

### Phase L-C: Look down (the field)

| # | Step | Proof |
| --- | --- | --- |
| L9 | **Ground that does not tile**: grass shader mixing the current detail texture with a low-frequency macro variation (two scales), plus mown stripes on the runway with **distinct edges** and a darker rough beyond the mown area. CC0 ambientCG textures at 1K–2K, or keep the procedural ones | The low-pass and 30 m captures show no visible repeat at 6 m; a pixel test: runway edge contrast at 100 m stays above a threshold set from the L0 baseline (the colours differ by ~30 % in luminance, but texture and haze blur the edge at distance) |
| L10 | **Known-size objects** from the field file: pilot stations, orange safety fence, pit tables/canopy, 3–4 cars (Kenney Car Kit, CC0), flag pole, and a **windsock** pointing down-wind (static until M5 wind). Built from primitives in code where no CC0 model exists | Captures; each object's size is checked against the field file in a test; the provenance file lists every asset |
| L11 | **Grass tufts and bushes** near the pilot (≤ 60 m): MultiMesh chunks, alpha scissor + MSAA 2× alpha-to-coverage, vertex-shader sway from a sim-time uniform | Low-pass capture; counters within budget; byte-repeat |
| **Gate L** | **"Does the landscape help or hurt flying?"** The owner flies the Gate 2 maneuver list in the new field. Measured: orientation read correctly at 100 m against sky and against the treeline; landing approaches using the treeline as the turn reference; frame time p95 on the slowest machine; draw calls; download delta | Notes and ratings recorded; budgets adjusted in this file; anything that hurts readability is reverted or toned down |

### Phase L-D: The ground becomes physical (with M2)

| # | Step | Proof |
| --- | --- | --- |
| L12 | **`sim/terrain.gd`**: float64 height function over a committed grid (heights quantised to 1/256 m, fixed triangle diagonal, plane evaluated in float64). It **starts all-zero**, so the crash check `touches_ground` uses it with no behaviour change | Known-sample tests (vertices, cell centres, both triangles of the diagonal); checksum test; **golden flights and `--trace` bytes unchanged**; µs/tick reported |
| L13 | **Gentle relief**: an offline generator (seeded FastNoiseLite + a flat mask under the runway and pits) writes the grid; render chunks are built from the **same grid and diagonal**. Relief only outside the field; the flyable zone is LOD0 | A test reads mesh vertices back and compares them with `terrain.gd` at random points (≤ 1e-4 m); crash on a hillside caught in a scripted trace |
| L14 | **Trees as obstacles**: each placed tree becomes a float64 cylinder (trunk + crown) in `sim/`, read from the same placement file as the renderer | Scripted flight into a tree crashes at the right tick; a flight between trees does not |
| L15 | **Wind made visible** (after M5 wind): windsock angle and tree/grass sway from the simulated wind vector | Windsock angle = wind direction in captures with two wind settings |

### Optional tracks (only if a gate asks)

| # | Step | When |
| --- | --- | --- |
| L16 | **Photo sky option**: a CC0 Poly Haven `*_puresky` HDRI at ≤ 2k for lighting + an LDR ≤ 4k backdrop, selectable in the field file | If Gate L says the procedural sky looks too synthetic |
| L17 | **The owner's own field**: 360° panorama at 1.70 m eye height (Insta360/Theta/phone + Hugin), with collision and occlusion proxies; or a real DEM (CNIG MDT LiDAR PNOA, CC-BY 4.0 with the product's credit) for relief | When the owner wants to fly their club field |
| L18 | **Terrain3D gate** (MIT, v1.0.2): adopt only if we need sculpting/painting at scale. Pin zip + SHA; still export its heightmap into our own triangle-exact sampler; web stays experimental | If L13's DIY chunks become a bottleneck |
| L19 | Time of day and weather (sun path, overcast) | Playtest wish |

## Ownership and parallel work

- **Who owns which files:**
  - Rendering of the world (`main.gd` `_build_world`, `render/ground.gd`, new `render/sky.gd`, `render/field.gd`, `render/vegetation.gd`) belongs to the main line.
  - `sim/terrain.gd` (L12+) is physics: it follows the 64-bit rules and is reviewed with Phase E (ground contact E1–E3 will query it).
  - Do not touch the model team's `airplane`/hinge interface. Field props are separate nodes.
- **New landscape assets:** they go in `assets/landscape/`, with `assets/landscape/PROVENANCE.json` (one entry per file).
- **Drafts:** sky and grass shaders are drafted **outside `app/`** until they parse: `test.sh` parses every script, and a broken draft breaks everyone's run.

## Risks we already know

- **LDR banding** in sky gradients and fog (Compatibility outputs RGBA8, no debanding). Dither in the shader.
- **Brighter lit surfaces once shadows are on** (Godot #90259). Re-tune in L3, check against the L0 captures.
- **No visibility-range fade** in Compatibility: LOD pops. Hide switches inside fog distance.
- **No decals until 4.8.** Runway markings are geometry or texture.
- **Radiance updates:** `TIME` in a sky shader forces them every frame. Never use it; drive animation from simulation time.
- **The treeline makes the airplane harder to see.** That is realistic and part of RC flying, but Gate L must check it does not make the sim unfun (auto-zoom helps).
- **Software-GL captures prove repeatability, not performance.** Frame time is judged only on the owner's hardware.
