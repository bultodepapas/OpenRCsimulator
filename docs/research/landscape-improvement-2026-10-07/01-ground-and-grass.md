# 01 · Ground and grass: colour, anti-tiling, textures, near grass

Date: 2026-10-07. Status: research only; no `app/` change. Input: [05 · landscape image review](../scenery-investigations/05-landscape-image-review.md) (grass hue 104–110°, sat 0.69–0.74 vs photo 73–80°, 0.43–0.53; luminance spread 4.3 vs 9–14 levels; tile autocorrelation 0.49), [06 · anti-tiling](../landscape-investigations/06-ground-anti-tiling.md), [05 · grass rendering](../landscape-investigations/05-grass-rendering.md), LANDSCAPE-PLAN L9a–L9d, L11a. Runway, stripes and wear are covered in [04](04-runway-surfaces-benchmarks.md); this report only adds what 04 lacks.

Evidence tags: **[V]** read on the page, API or source file on 2026-10-07 · **[doc]** official docs · **[src]** engine source at `4.7.2-stable` · **[measured]** measured here (spike in a scratch copy of `app/`, llvmpipe, Mesa 25.2.8, 1280×720, `opengl3`) · **[computed]** · **[sec]** secondary · **[F]** forum · **[est]** estimate.

## Summary: recommendations

1. **Regrade the grass albedo first (L9b, 1 line).** `Spec.GRASS` `#4a7a32` (H 100°, S 0.59) renders at H 104°, S 0.74. **`#657545`** (H 80°, S 0.41, linear Y 0.159, the same luminance as today's 0.156) renders at **H 77–79°, S 0.48–0.52**: inside the photo's window [measured]. It matches measured lawn spectra (USGS Lawn Grass GDS91 → H 79°, S 0.41 [computed]). Uniform, it reads olive; it needs the macro variation in point 3. A greener fallback for the owner's eye is `#5e7444` (screen H 86–88°).
2. **Anti-tiling: IQ technique 3 idea, own code, 2 `textureGrad` fetches, Hoskins hash, index noise at ~1.2 cycles per tile.** In the spike, the high-passed autocorrelation peak at the 6 m period (top view from 140 m) fell from **0.96 to 0.25** [measured]. Hex-tiling (3 fetches, MIT) stays the L9d choice for photo textures.
3. **Macro variation from shader value noise at 9, 37 and 160 m, amplitude 0.20–0.30, plus a dry tint over ~20 % of the area.** Spike: far-band luminance spread went from 3.3 to **10.9 levels** at amplitude 0.25, and 14.9 with a dry tint: the photo's 9–14 [measured]. No texture, no download.
4. **Keep the procedural 256 px tile for L9b.** Photo textures only for L9d, used as **detail** (`tex / tex_mean × target albedo`). Raw means of CC0 grass sets span linear Y 0.044–0.199 and hue 71–88° [measured]. Best fits: ambientCG **Grass001** (1.4 m) or **Grass004** for lawn, **Ground037** for rough, **Ground003** and Poly Haven **forrest_ground_01** for worn grass. As a macro source, Poly Haven **rocky_terrain_02** (90 m aerial pasture) is optional.
5. **Anisotropic filtering works here.** With `filter_linear_mipmap_anisotropic` on llvmpipe/Compatibility, far grass at 24–61 m keeps 1.5× the detail (sd 2.92 vs 1.90 levels) at the same mean [measured]; #123648 does not reproduce. Set `anisotropic_filtering_level = 3` (8×) as a candidate, after a frame-time check on the owner's GPU. The project-wide mipmap bias is ignored in Compatibility [doc]: use `texture(s, uv, bias)`.
6. **Near grass (L11a) as planned:** opaque blade clumps, a shrink-to-zero fade at 22–30 m, sway from `sim_clock`. New: the blades' **root colour comes from the same macro function as the ground**, so the 25–35 m seam proof can pass.

## 1. Anti-tiling techniques (Compatibility spatial shader)

| Technique | How | Cost (fetches) | Compatibility | Licence | Source | Verified? |
| --- | --- | --- | --- | --- | --- | --- |
| IQ technique 1 | Per-tile random offset/mirror, blend 4 tiles at the borders, `textureGrad` with the original derivatives | 4 | ✅ (GLSL ES 3.0 ops only) | article: no code licence → own code | [iquilezles.org](https://iquilezles.org/articles/texturerepetition/) | [V] |
| IQ technique 2 | Voronoi of randomly offset/rotated copies, Gaussian weights | 9 | ✅, but heavy on bandwidth | same | same | [V] |
| **IQ technique 3** | 8 virtual offsets chosen by a low-frequency index; blend 2 | **2** + index noise | ✅ (spike ran) | idea only; own code | same | [V] + [measured] |
| Mikkelsen hex-tiling | 3 hex-grid samples, random rotation, luminance-weighted contrast blend, no precompute | 3 | ✅ (port is GLSL ES) | code **MIT**; paper CC BY-ND | [mmikk/hextile-demo](https://github.com/mmikk/hextile-demo) (MIT, last push 2022-08-25); JCGT 11(3):5 | [V] repo; paper via [06] |
| Heitz–Neyret histogram-preserving | Gaussianise the input offline, blend 3, inverse LUT | 3 + LUT | ✅ but needs an offline tool | paper; no code licence on page | [eheitzresearch](https://eheitzresearch.wordpress.com/722-2/) (HPG 2018) | [V] |
| Texture bombing | Random stamps per grid cell, composited on a background | 4 (2-D), 8 (3-D); mip artefacts at cell edges | ✅ | GPU Gems text © Addison-Wesley | [GPU Gems ch. 20](https://developer.nvidia.com/gpugems/gpugems/part-iii-materials/chapter-20-texture-bombing) | [V] |
| Distance blend (two UV scales) | Same texture at a near and a far scale, blended by camera distance | +1 | ✅ | technique | [UDK terrain docs](https://docs.unrealengine.com/udk/Three/TerrainAdvancedTextures.html) | [sec] |
| Macro modulation | Low-frequency noise × albedo (section 4) | 0 (ALU) | ✅ | own code | spike | [measured] |

**Godot ports** (none run in the app; all use `fract(sin(x)·43758.5453)` hashes, so swap in Hoskins' "Hash without Sine", MIT):

| Shader | Licence | `TIME`? | Fetches | Notes | Verified? |
| --- | --- | --- | --- | --- | --- |
| [Stochastic Hex-Tiling (Mikkelsen port)](https://godotshaders.com/shader/stochastic-hex-tiling-mikkelsens-adaptation/) | MIT | no | 3 `textureGrad` | world space; sin hash | [V] |
| [Stochastic filter for hiding tiling](https://godotshaders.com/shader/stochastic-filter-for-hiding-texture-tiling/) | CC0 | no | 3 `textureGrad` | triangle grid; sin hash | [V] |
| [Seamless sampler (IQ tech. 3)](https://godotshaders.com/shader/seamless-texture-sampler-without-repeating-patterns-tiling/) | MIT | no | 2 + 1 noise texture | sin offsets | [V] |

**Spike** [measured]. Scratch copy of `app/`, `ground.gdshader` replaced; production field, top view from 140 m (`--look_el=-90 --look_alt=140`), 6 m tile = 33 px. Metric: luma minus a 24 px Gaussian blur, then the 2-D autocorrelation peak for lags of 20–120 px.

| Variant | Peak at the 33 px tile period |
| --- | --- |
| Today (`texture()`), same as plain shader | **0.96** |
| Technique 3, index noise 0.6 / tile | 0.38 |
| Technique 3, index noise 1.2 or 2.0 / tile | **0.25** |

Core (our code, MIT; `hash12`/`hash22` are Hoskins'):
```glsl
vec3 sample_norepeat(vec2 uv) {          // uv = world.xz / tile_m
	vec2 dx = dFdx(uv); vec2 dy = dFdy(uv);
	float l = vnoise(uv * 1.2) * 8.0;      // index: which of 8 virtual offsets
	float ia = floor(l); float f = fract(l);
	vec3 a = textureGrad(grass, uv + hash22(vec2(ia, 3.7)), dx, dy).rgb;
	vec3 b = textureGrad(grass, uv + hash22(vec2(ia + 1.0, 3.7)), dx, dy).rgb;
	return mix(a, b, smoothstep(0.2, 0.8, f - 0.1 * dot(a - b, vec3(1.0))));
}
```

## 2. Real grass colour and albedo

| Reference | Value | What it is | Source | Verified? |
| --- | --- | --- | --- | --- |
| **USGS Lawn Grass GDS91 green** (Kentucky bluegrass, picked 1991-06-18) | sRGB **(70, 80, 47)** `#46502f`, **H 79°, S 0.41**, linear Y 0.073 | Lab spectrum of picked blades → CIE 1931 under D65 [computed]. Reflectance 0.038 blue / 0.095 at 550 nm / 0.044 red, **0.70 in the NIR** | [USGS splib07 description](https://pubs.usgs.gov/of/2003/ofr-03-395/DESCRIPT/V/lawn_grass_gds91b.html); data mirrored in [chrislyonsKY/speclib](https://github.com/chrislyonsKY/speclib) | [V] + [computed] |
| USGS dry/green mixes and dry grass | 50/50 dry+green (118, 110, 78) H 49°; golden dry (130, 111, 81) H 37°, Y 0.17; cheatgrass field (103, 88, 73) H 30° | Same method | same | [computed] |
| **ColorChecker "Foliage"** | `#576c43` = (87, 108, 67), H 91°, S 0.38, Y 0.132 | Patch made to match "the front of a typical leaf" | [Wikipedia: ColorChecker](https://en.wikipedia.org/wiki/ColorChecker) | [V] |
| "Green grass 0.25" (Lagarde/DONTNOD 2011; Wikipedia) | 0.25 linear | **Broadband solar albedo, including the NIR.** Lagarde: "diffuse … should be a little less" | [Lagarde](https://seblagarde.wordpress.com/2011/08/17/feeding-a-physical-based-lighting-mode/) | [V] |
| rFactor 2 albedo chart | short green grass 0.20–0.25 linear (sRGB 122–136); tall wild grass 0.16–0.18; bare soil 0.17 | Grey levels, no source given: the same broadband trap | [Studio 397 docs](https://docs.studio-397.com/x/EgBDAg) | [V] |
| PhysicallyBased database | no grass, soil or foliage entry (86 materials) | — | [api.physicallybased.info](https://api.physicallybased.info/materials) | [V] |
| MSFS players | ground "too green", "cartoony", oversaturated; MSFS 2024 also too desaturated in places | Taste signal, not data | [MSFS forum](https://forums.flightsimulator.com/t/what-are-your-opinions-of-the-colors-of-the-sim/446079?page=2) | [F] |

**Trap:** grass is dark in the visible (Y ≈ 0.07–0.13) and bright in the NIR. A 0.25 "albedo" makes grass about 2× too bright. Our current Y 0.156 sits between the lab leaf and the 0.25 figure; keep it for readability continuity, and regrade hue and saturation. [computed / inference]

**Albedo → screen** (same pilot view, `--look_el=-12`, mean sRGB of boxes; near = x 700–1270, y 400–640; far = x 950–1270, y 205–255; ACES 0.6, sun and sky as shipped) [measured]:

| `Spec.GRASS` albedo | Albedo H / S / V / Y | Screen near H / S / V | Screen far H / S |
| --- | --- | --- | --- |
| `#4a7a32` (today) | 100° / 0.59 / 0.48 / 0.156 | 104° / 0.74 / 0.37 | 105° / 0.68 |
| `#576c43` (ColorChecker foliage) | 91° / 0.38 / 0.42 / 0.132 | 90° / 0.49 / 0.31 | 92° / 0.45 |
| `#46502f` (USGS lawn) | 78° / 0.41 / 0.31 / 0.072 | 76° / 0.57 / 0.18 | 79° / 0.48 |
| **`#657545`** | **80° / 0.41 / 0.46 / 0.159** | **77° / 0.52 / 0.35** | **79° / 0.48** |
| `#6a7a48` | 79° / 0.41 / 0.48 / 0.175 | 76° / 0.51 / 0.37 | 78° / 0.47 |
| `#5e7444` | 87° / 0.41 / 0.45 / 0.154 | 86° / 0.53 / 0.35 | 88° / 0.48 |

Rule of thumb for this pipeline: screen hue ≈ albedo hue − 2…3° (yellow-greens), screen S ≈ 1.15–1.35 × albedo S, screen V ≈ 0.76 × albedo V [measured]. The runway (`#6f9a4a`) renders at H 86°, S 0.57, V 0.64, so it must be regraded with the grass (04: same hue ±5°).

## 3. CC0 ground textures

Licences: **ambientCG: all CC0 1.0**, no attribution required ([docs.ambientcg.com/license](https://docs.ambientcg.com/license/)) [V]. **Poly Haven: all CC0**, no attribution required ([polyhaven.com/license](https://polyhaven.com/license)) [V]. Per-asset data comes from their APIs: ambientCG `full_json` (dimension in cm, zip sizes) and Poly Haven `/files` and `/info`. Mean colours were measured on the 1K colour map (linear average → sRGB) [measured].

| Asset | Tile | Maps | Download | Mean sRGB · H / S · linear Y | Fit | Verified? |
| --- | --- | --- | --- | --- | --- | --- |
| ambientCG **Grass001** (2021, procedural) | 1.4 m | Color, NormalGL/DX, Roughness, AO, Displacement | zip 1K 10.7 MB, 2K 38.9 MB (Color 1K JPG alone 1.76 MB) | (69, 93, 41) · 87° / 0.55 · 0.092 | (a) close lawn, as detail | [V] + [measured] |
| ambientCG Grass002 / Grass003 | 1.4 m | same | ~10.6 / 38.6 MB | (58, 77, 37) 88° · 0.063 / (67, 75, 31) 71° · 0.063 | darker lawn variants | [V] + [measured] |
| ambientCG **Grass004** | 1.4 m | same | 11.0 / 39.9 MB | (100, 112, 52) · 72° / 0.53 · 0.145; most texture (luma sd 22.6) | (a)/(c) yellower lawn | [V] + [measured] |
| ambientCG Grass005–008 (2025) | **not given** (dimension 0) | same | 10.0–10.4 / 36–40 MB | ~(100, 131, 43) · 81–83° / 0.66–0.68 · 0.18–0.20 | too saturated/bright raw; usable as detail | [V] + [measured] |
| ambientCG **Ground037** (photogrammetry) | 2.1 m | same | 10.6 / 37.9 MB | (156, 150, 94) · 55° / 0.40 · 0.297 | (c) rough/dry grass, as detail | [V] + [measured] |
| ambientCG **Ground003** | not given | same | 9.9 / 33.0 MB | (134, 129, 80) · 55° / 0.41 · 0.214 | (d) worn grass/dirt | [V] + [measured] |
| ambientCG Ground013 / Ground020 | not given | same | ~10 / 35 MB | greyish 42–55°, S 0.11–0.17 | (d) trampled, grey | [V] + [measured] |
| ambientCG Ground109 / Ground048 | 2.8 m / 1.4 m | same | 9.1 / 31.8; 10.7 / 38.9 MB | (127, 112, 86) 38° / (91, 67, 55) 20° | (d) dry soil / dark soil | [V] + [measured] |
| ambientCG Ground075 | 0.9 m | — | — | — | ❌ grass pavers (grid) | [V] |
| Poly Haven **forrest_ground_01** | 2.0 m | diff, nor_gl/dx, rough, AO, disp, arm | diff 1k JPG 0.83 MB, 2k 3.08 MB | (147, 137, 97) · 47° / 0.34 · 0.248 | (d) sparse grass on soil | [V] + [measured] |
| Poly Haven grass_ground / leafy_grass / sparse_grass / withered_grass | 2.51 / 2.0 / 2.0 / 2.0 m | same (+Mask) | 1k 0.88–1.2 MB, 2k 3.7–4.8 MB | all brown/dry, hue 31–43° | (c)/(d) dry or autumn only | [V] + [measured] |
| Poly Haven **rocky_terrain_02** (aerial) | **90 m** | diff, nor, rough, AO, disp, arm, Mask, spec | 1k 0.84 MB, 2k 3.23 MB | (81, 79, 31) · 57° / 0.62 · 0.075; green pasture with rock clusters | (b) macro luminance, blurred (rocks are atypical for a club lawn) | [V] + [measured] |
| Poly Haven aerial_grass_rock | 15 m | same | 1k 0.67 MB, 2k 2.62 MB | (115, 98, 47) · 45°; moss and rock | (b) only for rough edges | [V] + [measured] |
| cgbookcase / Texture Haven | — | — | — | — | not checked; Texture Haven is now Poly Haven | — |

**VRAM and download** [computed]: S3TC DXT1 is 0.5 B/px, so 1024² with mips = 0.67 MiB and 2048² = 2.67 MiB; BC7/ASTC 4×4 is 1 B/px (×2). One colour map at 1K stays far inside the 15 MB budget. Normal maps double that.

## 4. Macro variation and repetition at 100–500 m

| Technique | How | Cost | Compatibility | Licence | Source | Verified? |
| --- | --- | --- | --- | --- | --- | --- |
| **Shader value noise, 3 scales** | `m = 0.5·n(p/37) + 0.35·n(p/160) + 0.15·n(p/9)`; `albedo *= 1 + A·(m − 0.5)·2` | ~12 hashes (ALU), 0 fetches | ✅ deterministic, no `TIME` | own + Hoskins MIT | spike | [measured] |
| **Dry/yellow patches** | `dry = smoothstep(0.55, 0.85, n(p/60))·D`; `albedo *= mix(1, (1.25, 1.05, 0.80), dry)` | ~4 hashes | ✅ | own | spike | [measured] |
| Field colour map | One low-res texture per field (e.g. 512² over 2 km = 4 m/px), generated offline by the integer-only L13a generator or painted; it also carries the surface IDs | 1 fetch; 1 MB RGBA8 or 0.17 MB DXT1 | ✅ | own | plan L13/L17 | [est] |
| Aerial photo macro | `rocky_terrain_02` luminance, blurred, 90 m tile, × albedo | 1 fetch, 0.84 MB | ✅ | CC0 | Poly Haven | [V] |
| Mowing stripes | See [04](04-runway-surfaces-benchmarks.md): 1.5 m (decks 1.2–1.8 m; Toro Reelmaster 3575 2.5 m), view-dependent ±3–6 %, footprint-filtered | ~10 ALU | ✅ | own | 04; [Toro](https://www.toro.com/en-gb/product/Reelmaster-3555-3575-Series) | [sec] |

**Macro sweep** (technique 3 on; base colour unchanged) [measured]:

| Amplitude A / dry D | Pilot far band (x 950–1270, y 205–255) luma sd | Top 140 m: sd of 16 px block means |
| --- | --- | --- |
| 0 / 0 (today) | 3.3 | 0.9 |
| 0.15 / 0 | 7.5 | 4.3 |
| **0.25 / 0** | **10.9** | 7.0 |
| 0.35 / 0.5 | 14.9 | 10.1 |

- Repetition stays hidden at 100–500 m because the 160 m octave is aperiodic (a hash, not a tile) and the haze adds only 10 % at 600 m ([02](../landscape-investigations/02-atmosphere-aerial-perspective.md)) [inference].
- Value noise looks blobby from straight above. Mowing stripes, field borders and the stripes' direction break that up [visual].
- **Watch the pilot area:** with A = 0.25 the pilot's near box got 22 % darker (V 0.37 → 0.29), because the station sits in a dark patch. Pin the macro value near the pilot box (or pick the seed), and keep the L9b proof "mean band luminance ±5 %" [measured / est].

## 5. Godot 4.7 specifics

| Item | Fact | Status | Source | Verified? |
| --- | --- | --- | --- | --- |
| `rendering/textures/default_filters/anisotropic_filtering_level` | Default **2** (4×), power of two; 0 forces AF off; read at startup; runtime via `Viewport.anisotropic_filtering_level` | — | ProjectSettings.xml @4.7.2 | [V] [doc] |
| GLES3 AF path | Enabled only if `GL_EXT_texture_filter_anisotropic`; level = min(2^setting, GL max); applied for `*_MIPMAPS_ANISOTROPIC` | ✅ | `drivers/gles3/storage/config.cpp` L133–136, `texture_storage.h` L273–316 | [V] [src] |
| **AF on llvmpipe, Compatibility** | Far grass band (24–61 m): detail sd 1.90 (trilinear) → 2.92 (4×) → 3.12 (16×); horizontal gradient 0.088 → 0.239 → 0.411; mean ±0.6 level. llvmpipe has AF since Mesa 21.3 | ✅ works | spike; [Phoronix](https://www.phoronix.com/news/LLVMpipe-Lands-AF) | [measured] / [sec] |
| Issue #123648 "Linear Mipmap Anisotropic Not Working with 4.7 and 4.8" | Open, "needs testing"; one Vulkan user cannot reproduce; possible driver override | does not reproduce here | [godot#123648](https://github.com/godotengine/godot/issues/123648) | [V] |
| `texture_mipmap_bias` | "Only supported in Forward+ and Mobile … In Compatibility … treated as 0.0" | ❌ in Compatibility | ProjectSettings.xml | [V] [doc] |
| Per-sample bias | `texture(sampler2D s, vec2 p [, float bias])`; with `textureGrad`, scale the derivatives by 2^bias | ✅ | [shader functions](https://github.com/godotengine/godot-docs/blob/master/tutorials/shaders/shader_reference/shader_functions.rst) | [V] [doc] |
| VRAM compression | S3TC/BPTC (desktop) and ETC2/ASTC (web/mobile); the importer always also makes the host's format; the project already sets `import_etc2_astc=true`. GLES3 detects BPTC/ASTC/RGTC at runtime | ✅ | ProjectSettings.xml; `config.cpp` L87–113 | [V] |
| Runtime `ImageTexture` (today's grass) | 256² RGB8, uncompressed, mipmaps from `generate_mipmaps()` (sRGB-space averaging) | fine at this size | `app/render/ground.gd` | [V] |
| ORM packing | Not needed: ground is `ROUGHNESS 1`, `METALLIC 0`, `SPECULAR 0` (constants) | — | `ground.gdshader` | [V] |
| Normal maps on flat ground | `NORMAL_MAP` works in GLES3 spatial shaders; +1 fetch and 2× the texture bytes. Little gain beyond ~20 m at a 45° sun | defer to L9d | — | [inference] |
| Triplanar | Not needed: the ground is flat; world-space XZ UVs already | — | — | — |
| `SPECULAR = 0` | Removes the grazing-angle Fresnel sheen that makes real grass look paler toward the horizon. Worth one A/B at 0.2–0.5 | hypothesis | — | [inference] |

## 6. Near-field grass (L11a)

| Resource / technique | How | Cost | Compatibility | Licence | Source | Verified? |
| --- | --- | --- | --- | --- | --- | --- |
| **Opaque blade clumps in a MultiMesh** (plan) | 7 single-triangle blades per clump; ≤ 4 chunks; no shadow casting | +1 draw/MultiMesh; 12k clumps ≈ +68k primitives | ✅ (spike in [05]) | own | [05](../landscape-investigations/05-grass-rendering.md) | [measured] earlier |
| LOD fade without alpha | `VERTEX.y *= 1 − smoothstep(22, 30, d)` | ALU | ✅; `visibility_range_fade_mode` "acts like DISABLED" in Compatibility | own | GeometryInstance3D.xml @4.7.2 | [V] [doc] |
| Per-instance data | `INSTANCE_CUSTOM` and instance colour packed to **16 bits** in Compatibility: a phase or tint only, never a position | — | ⚠️ | — | MultiMesh.xml @4.7.2 | [V] [doc] |
| **Colour match to the ground** | In `vertex()`, evaluate the same macro function at the instance origin; root = ground albedo, tip ×1.10–1.15 and +3–5° yellower | ~12 ALU per vertex | ✅ | own | — | [est] |
| Wind | `sin(sim_clock·ω + phase)` with ω a multiple of 2π/1024; amplitude from `wind_vec` | ALU | ✅ (global uniforms) | own | plan decision "Animation clock" | [V] (plan) |
| Alpha cards | Aliased edges: A2C and alpha hash are no-ops in 4.7.2 Compatibility | ❌ | — | [05] | [measured] earlier |
| [SimpleGrassTextured](https://github.com/IcterusGames/SimpleGrassTextured) | Painted MultiMesh grass with a Compatibility mode; wind via global uniforms | heavy (SubViewports) | ✅ | MIT; v2.1.0 2026-04-03, pushed 2026-09-17 | GitHub API | [V] |
| [2Retr0/GodotGrass](https://github.com/2Retr0/GodotGrass) | Geometry blades, distance widening, clumping | Forward+; uses `TIME` | ⚠️ ideas only | MIT; last push 2024-08-16 | GitHub API | [V] |
| [ProtonScatter](https://github.com/HungryProton/scatter) / [Spatial Gardener](https://github.com/dreadpon/godot_spatial_gardener) | Editor scatter/painting | — | not checked | MIT; pushed 2026-09-27 / v1.4.1 2025-03-05 | GitHub API | [V] |

Every third-party grass shader found reads `TIME` (godotshaders "Grass Patch 3D", "Stylized grass with wind") [sec]. Take ideas only.

## Concrete targets

| Quantity | Target | Basis |
| --- | --- | --- |
| Grass albedo (sRGB) | **`#657545`**: H 80°, S 0.41, V 0.46, linear Y 0.159 (fallback `#5e7444`) | spike + USGS spectrum |
| Grass on screen (pilot view, near/far box means) | H **73–82°**, S **0.43–0.53** | owner's photo (review 05) |
| Macro patch range (albedo) | hue 70–90°, S 0.35–0.48, Y 0.10–0.20 | USGS green/dry mixes; ColorChecker |
| Luminance spread, pilot far band | **9–14** levels (today 3.3–4.3); macro A = 0.20–0.30, dry D ≤ 0.5 | spike sweep |
| Tile repeat, top view 140 m, high-passed autocorrelation at the 6 m period | **≤ 0.30** (today 0.96; technique 3 gave 0.25) | spike |
| Anti-tiling cost | 2 `textureGrad` fetches + ≤ 20 hashes per pixel | spike |
| Mean band luminance after L9b | ±5 % of L9a, incl. the pilot box | L9b proof; pilot-box caveat |
| Anisotropic level | 3 (8×) if the owner's GPU shows no p95 cost; else 2 | spike; [est] |
| Photo detail texture (L9d) | 1K colour only, ≤ 2 MB download, mean-normalised | ambientCG/Poly Haven data |
| Near grass | ≤ 30 m, fade 22–30 m, root colour from the macro function, seam: 25–35 m band mean within 3 % | [05], L11a |

## Not verified

- Frame time of AF 8×/16×, technique 3 and the macro noise on real GPUs (llvmpipe is no measure).
- Whether the target colour reads "natural" to the owner: the numbers match the photo, but uniform `#657545` looks olive. Gate L decides.
- USGS spectra are lab samples of picked blades, not canopies. A canopy is darker in the visible, from self-shadowing [inference].
- Real-world mean values of canopy visible albedo (MODIS VIS band) were not read.
- Mikkelsen's paper page (JCGT) did not render here; its licence comes from [06].
- The tile sizes of ambientCG Grass005–008, Ground003 and Ground013 (the API gives 0).
- cgbookcase was not checked.
- How the stripe amplitude works with the new albedo (see 04).
- How `SPECULAR` > 0 affects grazing-angle saturation.
- The cause of the earlier 23 % far-ground brightness gap ([06]) was not investigated.

## Reproduce

Scratch only (`/tmp/claude-1000/landscape-research/`): copy `app/` (without `captures/`), edit `Spec.GRASS` or `render/ground.gdshader` in the copy, then:
```bash
G=.tools/Godot_v4.7.2-stable_linux.x86_64
xvfb-run -a -s "-screen 0 1280x720x24" $G --path <copy>/app --rendering-driver opengl3 --audio-driver Dummy -- \
  --capture --t=1.5 --look_az=0 --look_el=-12 --hide_airplane --autozoom=0 --out=/tmp/x.png   # pilot view
#   top view: --look_el=-90 --look_alt=140 ; AF probe: --look_el=-3, swap filter hint / project setting
```
Spectra → sRGB: CIE 1931 2° (Wyman–Sloan–Shirley 2013 fit) × CIE D65 (10 nm), XYZ → linear sRGB; a flat 0.18 reflector checks to (118, 118, 118).

## Sources

- Quilez, texture repetition: https://iquilezles.org/articles/texturerepetition/
- Mikkelsen hex-tiling code: https://github.com/mmikk/hextile-demo · Heitz & Neyret 2018: https://eheitzresearch.wordpress.com/722-2/ · GPU Gems ch. 20: https://developer.nvidia.com/gpugems/gpugems/part-iii-materials/chapter-20-texture-bombing · UDK terrain: https://docs.unrealengine.com/udk/Three/TerrainAdvancedTextures.html
- godotshaders ports: links in section 1
- USGS Lawn Grass GDS91: https://pubs.usgs.gov/of/2003/ofr-03-395/DESCRIPT/V/lawn_grass_gds91b.html · spectra JSON: https://github.com/chrislyonsKY/speclib (licence: NOASSERTION in the repo; data is USGS public domain [inference])
- ColorChecker: https://en.wikipedia.org/wiki/ColorChecker · Lagarde 2011: https://seblagarde.wordpress.com/2011/08/17/feeding-a-physical-based-lighting-mode/ · Studio 397 albedo chart: https://docs.studio-397.com/x/EgBDAg · PhysicallyBased API: https://api.physicallybased.info/materials
- ambientCG licence: https://docs.ambientcg.com/license/ · API: `https://ambientcg.com/api/v2/full_json?id=Grass001&include=dimensionsData,downloadData` · Poly Haven licence: https://polyhaven.com/license · API: `https://api.polyhaven.com/files/<id>`
- Godot 4.7.2: `doc/classes/ProjectSettings.xml`, `GeometryInstance3D.xml`, `MultiMesh.xml`, `drivers/gles3/storage/config.cpp`, `texture_storage.h` at https://github.com/godotengine/godot/tree/4.7.2-stable · issue https://github.com/godotengine/godot/issues/123648
- llvmpipe AF: https://www.phoronix.com/news/LLVMpipe-Lands-AF
- MSFS colour opinions: https://forums.flightsimulator.com/t/what-are-your-opinions-of-the-colors-of-the-sim/446079?page=2
- Mower width: https://www.toro.com/en-gb/product/Reelmaster-3555-3575-Series
