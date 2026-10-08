# Landscape improvement: a phased proposal

Date: **2026-10-07**. Status: **proposal for the landscape and visual-quality tracks; Phases 0–4 and the far-field patchwork implemented and measured the same day ([implementation](implementation/README.md)), review pending; Phase 5 engineering-verified in [L7](../visual-quality-implementation/L7/README.md); Phase 6 implemented and engineering-verified in [L4b](../visual-quality-implementation/L4b/README.md), with L15d wind integration pending; Phase 7 required grass scope engineering-verified in [L11a](../visual-quality-implementation/L11a/README.md), existing flowers reused opt-in and L9d deferred; Phase 8 has an engineering-verified [L15b rendering preparation](../visual-quality-implementation/L15b/README.md), with M5 integration and full Phase 8 pending** ([LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md), [VISUAL-QUALITY-PLAN](../../VISUAL-QUALITY-PLAN.md)).
- **Basis:** the measured problems of [review 05](../scenery-investigations/05-landscape-image-review.md) and four research reports with Godot 4.7.2 Compatibility spikes.
- **Step IDs:** it adds none. Every phase maps to existing **L** steps, or proposes a sub-step for the landscape owner to accept.
- **Scope:** it does not change the ROADMAP or any plan by itself.

| Report | Topic |
| --- | --- |
| [01](01-ground-and-grass.md) | Ground colour, anti-tiling, macro variation, CC0 textures, Godot filtering, near grass |
| [02](02-vegetation.md) | Tree card shading (winding bug, seam fix), grounding, colour, LODs, grass, wind, far forest |
| [03](03-terrain-sky-lighting.md) | G-1, hills, DEM, sky and clouds, grading in Compatibility, atmosphere |
| [04](04-runway-surfaces-benchmarks.md) | Runway in the ground shader, mown stripes, paved option, markings, filtering, benchmarks |

## Where we start (measured)

| Problem | Today | Real / target | Evidence |
| --- | --- | --- | --- |
| Grass colour | Hue 104–110°, S 0.69–0.74 ("billiard table") | Hue 73–82°, S 0.43–0.53 | Review 05; owner's photo; USGS lawn spectrum (01) |
| Ground variation | Far-band luminance spread 3.3–4.3 levels | 9–14 | 01 spike |
| Tile repetition | Autocorrelation 0.96 at the 6 m period (top view from 140 m) | ≤ 0.30 | 01 spike |
| Tree cards | Seam of 47–79 levels; front-lit trees **dark**, backlit trees bright (winding bug) | Seam ≤ 5 levels; front-lit bright | 02 A/B |
| Leaf / bark colour | Leaves fully saturated (S 1.00); bark bright red-brown (138, 88, 67) | Leaves S 0.4–0.5; bark ≈ (90, 80, 68) | 02 |
| Runway | Flat lime band, hue 87°, S 0.57, V 0.63; hard, unfiltered edges | Same hue as the grass ±5°, mown stripes, soft borders | 04 |
| Ground mesh | One plane of 2 triangles, 40 km: hides lifted surfaces in raised views (4 of 12 views at 30 m) | Subdivided; no lifted overlay past ~300 m | SC-01, 03 |
| Horizon | A flat plain ending in an even haze band | Layered silhouettes: hedges, forest, hills, a field patchwork | 03 |
| Sky | Good. Clouds slightly uniform in scale | Clusters with gaps, cirrus | 03 |

**Benchmark lessons (04):**
- **RC players** praise photo fields and fault 3D fields for repetitive texturing, primitive trees and flat ground.
- **Full-scale sims** (MSFS) draw complaints about lime-green, over-saturated grass and runways that look like the fields around them.

Our list is the same.

## Rules every phase keeps

1. **Compatibility renderer only:**
   - no `TIME` (animate with `sim_clock` and `wind_vec`);
   - no decals until 4.8;
   - alpha-to-coverage and alpha-hash do nothing: foliage is opaque or alpha scissor.
2. **Determinism and proof:**
   - captures repeat byte for byte;
   - every phase ships an A/B capture, the L6c readability re-run (colour changes move the airplane's contrast), and the runway scenario comparison (`tools/scenery/scenario.sh`, SC-25), which flags any unintended physics change.
3. **Budgets:**
   - landscape ≤ 300 draws and ≤ 1 M primitives; trees ≤ 24 draws, grass ≤ 5;
   - textures ≤ 2048 px; download ≤ +15 MB;
   - frame time judged on the owner's slowest machine.
4. **Colour at the source, not with a global grade:** a global grade also shifts the airplane's livery and the readability numbers.
5. **Licences:** CC0 first, with the exact file and its SHA-256 in `PROVENANCE.json`; code ideas are reimplemented, never copied from GPL sources.

## Phases

Effort figures are planning estimates for one developer who knows the repo.

### Phase 0 — Correctness fixes (≈ ½ day) · L6b follow-up, G-1

| Change | Where | Target and proof |
| --- | --- | --- |
| **Fix the card winding.** Reverse each quad's index order (or negate its normals) in `tree_assets.card_mesh()`. Today the face you see gets a normal pointing away from you | `render/tree_assets.gd` | Front-lit crowns brighter than backlit ones (02 A/B: 40.2 vs 5.5, from 10.7 vs 35.6 today) |
| **Subdivide the ground: 64 × 64 quads** (8,192 triangles, one draw). Then drop the scenery track's interim (`Scenery.subdivide_ground`) | `render/field.gd` (or `ground.gd`) | The SC-01 `groundbug` sweep: 0 of 36 views lose the runway |

**Why first:** both are correctness bugs, they are one-liners, and they cost nothing at runtime.

### Phase 1 — Colour truth (≈ 1 day) · L9b colour part, L6a grade

| Change | Value | Basis |
| --- | --- | --- |
| Grass albedo `Spec.GRASS` | `#4a7a32` → **`#657545`**: hue 80°, S 0.41, linear Y 0.159, the same brightness as today. Fallback for the owner's eye: `#5e7444` | 01 spike: renders hue 77–79°, S 0.48–0.52, inside the photo's window; USGS Lawn_Grass spectrum → hue 79°, S 0.41 |
| Runway turf | Hue = grass ±5°, saturation −0.05…−0.10, value +10–25 % | 04 |
| Leaves, in the card shader | `mix(luma, c, 0.6) × 0.67` → ≈ sRGB (81, 98, 58); pines ≈ (45–60, 65–80, 40–50) | 02, from leaf reflectance spectra |
| Bark | `luma × 0.65 × (1.22, 0.96, 0.70)` → ≈ (90, 80, 68); share this value with the scenery palette's `trunk` | 02 |
| Per-tree tint | ±10 % R, ±6 % G, ∓8 % B, from a second step of the tree hash | 02 |

- **Proof:** screen hue and saturation in the photo's window (pilot view, near and far boxes); L6c thresholds still met; A/B sheet.
- **Note:** the olive grass reads flat until Phase 2 adds variation, so ship Phases 1 and 2 together, or show the owner both.

### Phase 2 — Ground richness (≈ 2–3 days) · L9a, L9b

| Change | How | Target |
| --- | --- | --- |
| **Anti-tiling** | Inigo Quilez's "technique 3" idea, written as our own code: 2 `textureGrad` fetches selected by a hashed index noise (~1.2 cycles per tile), Hoskins "hash without sine" (MIT) | Autocorrelation at the 6 m period ≤ **0.30** (spike: 0.96 → **0.25**) |
| **Macro variation** | Shader value noise at **9, 37 and 160 m**, amplitude 0.20–0.30, plus a dry tint over ~20 % of the area (hue 70–90°, S 0.35–0.48, Y 0.10–0.20) | Far-band luminance spread **9–14** levels (spike: 3.3 → 10.9–14.9) |
| **Pilot box pinned** | Hold the macro noise near its mean around the pilot station | Mean band luminance ±5 % of L9a (the spike darkened the pilot area 22 % without it) |
| **Anisotropic filtering** | Project `anisotropic_filtering_level = 3` (8×), only after a p95 frame-time check on the owner's GPU (else 2); per-sample `texture(s, uv, bias)` (the project-wide mipmap bias is ignored in Compatibility) | Far grass keeps 1.5× the detail (spike: sd 1.90 → 2.92) |

- **Resources:** none to download. The 256 px procedural tile stays, and everything is shader maths.
- **Proof:** L9a parity first, then top-down autocorrelation, the luminance spread per band, byte repeat and L6c.

### Phase 3 — Trees that sit in the light (≈ 1–2 days) · L6b follow-up, L8 deferred

| Change | How | Target / cost |
| --- | --- | --- |
| **Crown normal per pixel** | Each pixel takes the normal of an ellipsoid around the crown centre in the view plane, written in `fragment()`, which runs after Godot's back-face flip. Both crossed cards then share one normal per pixel | Largest column step inside a crown **47–79 → 2.6–4.3** levels. 0 draws, ~15 ALU per fragment |
| **Soft fill** | `BACKLIGHT` ≈ 0.4 × albedo, normal leaned to the sky (`up_bias` ≈ 0.5), underside bounded (`q.y ≥ −0.5`). Not `diffuse_lambert_wrap` with roughness 1: it halves the lit side | Crowns read as volumes from every side |
| **Vertical grounding** | Trunk base darkened ×0.65, back to 1 at 25 % of the height; an **undergrowth skirt** in the atlas's empty 4th tile (512–1024 px), 2–3 low quads per tree in the same mesh | 0 extra draws. From the pilot's eye a 5 m ground blob at 300 m covers 0.15 px, so contact has to be vertical |
| **Raised views only** | A baked canopy-AO / rough-grass mask sampled by the ground shader | 0 draws |

- **Deferred:** L8 near-tree meshes. The nearest tree is 272 m away, beyond L8's ~150 m. Automatic decimation of the chosen Quaternius broadleaves stops at 1,496–2,336 triangles. When a near tree is needed, use a crown hull plus cards, or the Kenney Nature Kit (CC0, 50–402 triangles).
- **Proof:** the seam column metric, the A/B at four headings, the card draw count unchanged, and L6c ("trees" background).

### Phase 4 — Field surfaces in the ground shader (≈ 3–4 days) · L9c, O-6

The [L9c ground-pass follow-up](../visual-quality-implementation/L9c/README.md) integrates contained flat rectangles, retains custom-layout fallbacks, and verifies edge contrast, priority, flight and readability. [L9c-R1](../visual-quality-implementation/L9c-R1/README.md) adds a stripe-only sampling regression against supersampled references. Perceptual shimmer acceptance and the paved option remain open; canonical status stays in LANDSCAPE-PLAN.

| Change | How | Target |
| --- | --- | --- |
| **One shader for every surface** | Field rectangles as signed distances (uniform arrays, early-out on the field's bounding box). Remove the lifted `PlaneMesh` per surface in `field.gd` | No lifted overlay past ~300 m (24-bit depth step: 6 mm at 100 m, 5 cm at 300 m) |
| **Mown runway** | Stripes **1.5 m** wide (1.2–1.8 m: one ride-on deck) along the runway; view-dependent value `±(3–6 %)·dot(view_xz, bend_dir)`; stripe ripple ≤ ½ the runway edge step | Reads as mown turf from 10 to 100 m |
| **Borders and wear** | Mown→rough border broken by noise (amplitude 0.3–0.8 m, wavelength 2–6 m); rough value ×0.75–0.85, hue −3 to −8°; worn touchdown zones 10–30 m from each threshold; taxi paths 1–2 m | No ruler-straight edges |
| **Filtering** | An exact 1-D box filter for lines; a square-wave integral for stripes and dashes, by pixel footprint (`fwidth`); MSAA does not reach in-shader patterns. Formulas in 04 §6 | Reference-subtracted stripe-only error under a 0.5 px camera move, with raw-wave and erased-detail controls; zoomed (10°) views at 100 and 300 m. Raw frame differences include legitimate motion; owner/target-GPU shimmer acceptance remains separate |
| **Paved field `paved.json` (O-6)** | Poly Haven **`aerial_asphalt_01`** (CC0, 30 m tile, cracks and tyre marks) as **detail only**: texture / its mean × the albedo from the field data. Markings drawn analytically: dashed white centreline 0.3 m (dash = gap, ≈ 7.7 m period), yellow X ≈ sRGB (200, 167, 65) with a threshold bar, six black start-up pads | Photo match: fresh asphalt at 0.27× the grass luminance; white paint linear ≈ 0.7, worn 20–40 % in blotches |
| **Physics pair** | `asphalt` surface type in `surface_friction.json` (factors 1.0/1.0): the physics line's file | Same rectangles feed the drawing and the friction |

- **Calibration rule:** never trust a photo texture's mean. Ten CC0 asphalt sets span linear luminance 0.046–0.341, while real asphalt is 0.04–0.05 new and 0.10–0.20 aged.
- **Later shader surface types,** to replace the scenery's lifted meshes:
  - gravel: ambientCG Gravel043, Poly Haven `gravel_floor_02`;
  - dirt: ambientCG Ground048, Poly Haven `dry_mud_field_001`.
- **Proof:** the L9c edge-contrast test at 100 m, column profiles across both edges, the no-shimmer diff, the zoomed views, L6c, and the scenario comparison (runway frames change, physics must not).

### Phase 5 — A horizon with depth (≈ 4–6 days) · L7, L13a, far field

Implemented in [L7](../visual-quality-implementation/L7/README.md); verification and limitations are recorded there. The optional real skyline remains deferred. Canonical step status stays in LANDSCAPE-PLAN.

| Change | How | Target / cost |
| --- | --- | --- |
| **Far-field patchwork** | A land-cover layer in the ground shader beyond ~1 km: integer-hash Voronoi parcels of 100–400 m in green, straw, stubble and ploughed brown | Breaks the even haze band seen from 30–140 m up. 1 draw, no geometry |
| **Forest patches** | Dense card clusters at 600–1,500 m in the **same 8 sector MultiMeshes** | 0 extra draws, 6 triangles per tree. The packing offset must grow (today it reaches −600 m south and west only), with the hash kept stable so today's trees keep their identity |
| **Hill ring** | Hills as **vertices of the ground**, one polar ring mesh built once (1,440 azimuth × ~24 radial rows from 1.5 to 6 km, then flat to 20 km). Heights from the L13a integer generator; hills 30–120 m (Hammond "plains/tablelands" class) | ~82k triangles, 1–2 draws; hills 0.5–1.5° tall (7–22 px at 720p). Never a separate mesh on the plane: it z-fights at 2–5 km |
| **Optional real skyline (L17-lite)** | The 5–30 km ring from **Copernicus GLO-30** of the owner's region (licence notices kept), with earth-curvature drop (27 m at 20 km) | The owner's real horizon |
| **Visibility presets** | 23 km (default), 12 km hazy summer, 40 km post-frontal | The same fog = sky equality (L2) at each |

**Proof:** horizon captures from 1.7, 30 and 140 m with a horizon-band luminance spread; draw counts; the crack test along ring borders; L2's seam test (≤ 4 levels) at every preset.

### Phase 6 — Sky and light (≈ 2 days) · L4 extension, L15d, VQ A/B

Implemented in [L4b](../visual-quality-implementation/L4b/README.md), including [L15d rendering](../visual-quality-implementation/L15d/README.md). Grading remains a capture-only experiment; simulated wind integration remains M5-W04b work. Canonical status stays in LANDSCAPE-PLAN.

| Change | How |
| --- | --- |
| Cloud clusters | A low-frequency coverage octave, so clouds group with clear gaps |
| Cirrus | A thin, high deck of stretched noise |
| Silver lining | A cheap forward-scatter rim on sun-side clouds |
| **Cloud shadows (L15d)** | The same hash noise projected in the ground shader's `light()`, deck at 1.5 km, drift = wind aloft × `sim_clock` |
| Grading A/B | 4.7.2 Compatibility runs brightness/contrast/saturation, LUTs (only when adjustments are on), glow and the new SSAO (since 4.6). Run A/B tests only, never a default without the L6c proof |

**Reference:** Sky3D (MIT) is the best example to read, since it uses `TIME` only for star twinkle. Do not adopt it as a dependency. "Golden hour" needs per-pixel Hosek-Wilkie (L19).

### Phase 7 — The near field (≈ 2–3 days) · L11a, L11b, L9d

Required grass scope implemented and verified in [L11a](../visual-quality-implementation/L11a/README.md). SC-16/17 flowers and bushes are reused through the existing opt-in hook; O-2/Gate SC acceptance stays open. Optional L9d photo detail remains deferred until Gate L requests it. Canonical step status stays in LANDSCAPE-PLAN.

| Change | How |
| --- | --- |
| **Grass blades** | Opaque 7-blade clumps within 30 m, shrinking to zero at 22–30 m, sway from `sim_clock`. New: each blade's **root colour comes from the same macro function as the ground**, so the edge where blades end does not show (25–35 m band mean within 3 %) |
| **Flowers (L11b)** | Reuse the scenery track's SC-16 flower cushions (21 triangles, MultiMesh, colour per instance) instead of a second flower system |
| **Photo detail (L9d, optional)** | 1K colour maps as **detail** over the procedural colour, mean-normalised:<br>• lawn: ambientCG **Grass001** / **Grass004** (1.4 m tile, 1.76 MB);<br>• rough: **Ground037** (2.1 m);<br>• worn: **Ground003**, Poly Haven **forrest_ground_01** (2 m);<br>• macro source: Poly Haven **rocky_terrain_02** (90 m aerial, 0.84 MB).<br>Mikkelsen hex-tiling (MIT, 3 fetches) for photo textures |

**Checked and rejected:** every Godot grass add-on checked (SimpleGrassTextured, Spatial Gardener, ProtonScatter demos, several shaders) reads `TIME` or targets Forward+. Keep the DIY clumps.

### Phase 8 — Wind and life (after M5) · L15a–c

[L15b rendering preparation](../visual-quality-implementation/L15b/README.md) is verified (2026-10-08). Production remains calm until M5 supplies physical wind; this does not close L15a/c or Phase 8. Canonical step status stays in LANDSCAPE-PLAN.

| Change | How |
| --- | --- |
| Tree bending | L15b uses a small length-preserving rotation anchored at the root: nonlinear endpoint bending would move the root inside the current padded quads. Shared `wind_vec` and `sim_clock`, k/1024 Hz frequencies and existing hash phases; no branch/leaf detail. Nonlinear bending would need a different mesh |
| Grass, flowers, flags | The same uniforms (the scenery already animates its flag and rotors this way) |
| Windsock (L15a) | As planned: the Canada AIM droop table |

## Order and dependencies

| Phase | Depends on | Visible gain | Risk |
| --- | --- | --- | --- |
| 0 Correctness | — | High (trees lit right, no vanishing runway) | Very low |
| 1 Colour | 0 | Very high (every frame) | Low: L6c re-run |
| 2 Ground richness | 1 | Very high | Low–medium: pilot-box pin |
| 3 Trees | 0 | High | Low |
| 4 Field surfaces | 1–2, G-1 | High near the runway | Medium: filtering, shader cost |
| 5 Horizon | 2; L13a generator | Medium–high in raised views | Medium: ring cracks |
| 6 Sky and light | — | Medium | Low |
| 7 Near field | 2 | Medium (low views, Home) | Medium: draw budget |
| 8 Wind | M5 wind | Medium | Low |

**Recommended first delivery:** Phases 0 + 1 + 2 as one reviewed package. They cost about 4 days, add no downloads, and change every frame the owner sees.

## More ideas, for later gates

Each needs its own step and proof:
- **Crop rows:** in one or two far parcels, stripes in their own direction, which read strongly from the air.
- **Hay stubble after mowing:** a seasonal grade linked to the scenery's bale field (SC-12).
- **Morning ground mist:** a thin height-fog band at sunrise (with L19).
- **Wet runway after rain:** roughness down and a darker albedo on the asphalt option.
- **Molehills and tyre tracks:** sparse dark spots in the rough, tracks across the mown area to the pits.
- **A field-specific colour map:** a 512² painted texture per field (owner's club) under the procedural detail, for L17.

## What this proposal does not prove

The numbers come from llvmpipe renders and image statistics in scratch spikes (01–04); each phase must re-measure in the app.

Not yet tested:
- GPU frame time on the owner's machine;
- anisotropic cost on real hardware;
- whether 64 × 64 suffices on every driver;
- Terrain3D on 4.7.

The owner's eye decides at Gate L.
