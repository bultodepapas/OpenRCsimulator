# 03 · Terrain relief, horizon, sky and lighting

Date: 2026-10-07. Status: research only; no `app/` change. Input: [05 · landscape image review](../scenery-investigations/05-landscape-image-review.md) (flat world, uniform haze band, G-1, sky fine), [LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md) (L7, L12–L13, L15d, L16–L19), `app/render/atmosphere.gd`, `sky.gdshader`, `ground.gdshader`, `field.gd`, and landscape investigations [02](../landscape-investigations/02-atmosphere-aerial-perspective.md), [03](../landscape-investigations/03-terrain-mesh-gdscript.md), [07](../landscape-investigations/07-open-source-sims-scenery-code.md), [08](../landscape-investigations/08-terrain-generation-tools.md) and [09](../landscape-investigations/09-lighting-color-lookdev.md). Constraints: Godot 4.7.2 Compatibility only, no `TIME`, deterministic, the fixed pilot, a float64 exact height sampler, CC0 or permissive licences first.

Evidence tags: **[src]** read in the 4.7.2-stable source; **[doc]** official documentation; **[computed]** our arithmetic (formula given); **[measured]** a measurement in this repo; **[inference]**; **[unverified]**.

## Summary: recommendations, in order

1. **G-1 now: subdivide the rough ground.** Set `PlaneMesh.subdivide_width/depth = 63` (64 × 64 quads of 625 m, 8,192 triangles, still one draw call). SC-01 measured that 10 × 10 already brings the runway back; 64 × 64 gives 6× margin, and the pilot then stands on a vertex. Rule: **no coplanar overlay farther than ~300 m from the camera.** The 24-bit depth step is 5 cm at 300 m and 0.6 m at 1 km [computed]. So runway, mown and gravel surfaces belong in the ground shader (L9c), not in lifted planes.
2. **The "uniform haze band" is mostly an albedo problem, not a haze problem.** From 30–140 m up, the whole band within ~8° of the horizon is ground between 0.2 and 20 km, all the same green. Real farmland breaks it with a **macro patchwork of fields** (100–400 m parcels in green, straw, stubble and ploughed brown) and with woodland blocks. Add a far-field land-cover layer to the ground shader: low-res texture or integer-hash Voronoi; one draw call, no new geometry. It pairs with L9b.
3. **L7 hills as part of one polar ring mesh, built once.** Use 1,440 azimuth steps (0.25°) × ~24 radial rows from 1.5 to 6 km, then a flat annulus to 20 km: ~70k + ~12k triangles, 1–2 draw calls. Heights come from the L13a integer generator. Hills 30–120 m high at 2–6 km rise 0.5–1.5° (7–22 px at 720p) [computed]. **Never stack a separate hill mesh on the flat plane:** at 2–5 km the depth step is 2.4–15 m, so shallow hill feet would z-fight. Hills are vertices of the ground, the L12c design.
4. **Optional real skyline (L17-lite):** build the 5–30 km ring from **Copernicus GLO-30** of the owner's region, with earth-curvature drop (27 m at 20 km, 62 m at 30 km [computed]). Redistribution is allowed with the exact licence notices (below). The near field stays procedural.
5. **Atmosphere:** keep 23 km visibility as the default. Add presets for a hazy summer day (12 km) and a clear post-frontal day (40 km). Layer the horizon (table in §7) so every distance band has its own silhouette and contrast.
6. **Sky:** add (a) a low-frequency coverage octave so clouds come in clusters with clear gaps, (b) a thin **cirrus** deck with stretched noise, (c) a cheap silver lining. Then do **L15d cloud shadows** in the ground shader's `light()`, using the same hash noise with the deck put at 1.5 km. Sky3D (MIT) is the best reference: `TIME` only for star twinkle, clouds driven by uniforms. Do not adopt it as a dependency.
7. **Lighting:** 4.7.2 Compatibility **does** run brightness/contrast/saturation, 1D/3D LUT, glow and a new SSAO (S4AO, since 4.6) [src]. Older docs that say otherwise are outdated. Still, **fix colours at the source** (grass albedo, L9b) rather than with a global grade, which also changes the airplane's livery and the L6c readability. A "golden hour" needs per-pixel Hosek-Wilkie (L19); a LUT alone cannot do it.
8. **Terrain add-ons:** stay DIY (decision unchanged). Terrain3D 1.0.2 (MIT, C++ GDExtension) now fully supports Compatibility, but its heights are bilinear float32 on a camera-centred clipmap. HTerrain (MIT, GDScript, master needs Godot 4.6+) samples bilinearly too. Neither is a float64 triangle-exact sampler.

## 1. Distant hills and the horizon for a static viewpoint

| Technique / resource | How | Cost | Compatibility | Licence | Source | Verified? |
| --- | --- | --- | --- | --- | --- | --- |
| **Polar ring mesh with heights (recommended)** | Built once around the pilot: radial rows spaced geometrically, azimuth step ≤ 0.25°. Fogged by the ground shader's own `FOG` (same formula as the sky) | 1,440 × 24 quads ≈ 69k tris, 1 draw; build ≈ 0.1 s per 65k verts (spike in 03) | ✅ plain ArrayMesh | ours, MIT | [03](../landscape-investigations/03-terrain-mesh-gdscript.md) (spike), GPU Gems 2 ch. 2 clipmap rings | measured (build), computed (counts) |
| Separate low-poly hill ring on the flat plane | Closed hill mesh sunk into the ground | ~5–20k tris, 1 draw | ✅ | ours | — | **rejected** [computed]: shallow feet z-fight (depth step 2.4–15 m at 2–5 km) |
| Silhouette card ring | Vertical cylinder of alpha-scissor quads at 1.5–5 km with a painted or rendered skyline | ~4k tris for 2,048 segments, 1 draw, 1 texture ≤ 4096 × 256 | ✅ (alpha scissor) | CC0/own art | CRRCSim Davis field: 4 panorama quads ~1.8 km out, 120 m tall ([07](../landscape-investigations/07-open-source-sims-scenery-code.md)) | verified (07, src) |
| Photo panorama + invisible depth terrain | Cubemap sky photo; the terrain drawn to depth only to occlude the plane and catch its shadow; VR parallax from scene depth | 1 skybox + depth pass | ✅ possible | PicaSim is **PolyForm NC**: ideas only | [PicaSim ParallaxPanorama.md](https://github.com/Rowlhouse/PicaSim/blob/main/ParallaxPanorama.md), [landscape-research](../landscape-research.md) | verified (repo doc) |
| RealFlight / Aerofly RC photo fields | 360° photo + invisible collision/"depth buffer objects"; separate full 3D fields | — | — | proprietary | [landscape-research](../landscape-research.md) (manuals, forums) | verified earlier; complaints of misaligned proxies |
| Real DEM skyline ring | GLO-30 resampled onto the polar ring, curvature drop `d²/(2R)·(1−k)`, k ≈ 0.13 | same as the polar ring | ✅ | Copernicus licence (notice) | [COPDEM licence](https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf) | verified (licence text) |

**Resolution targets [computed].** The pilot camera has a 50° vertical FOV at 1280 × 720, which is a 79.3° horizontal FOV and 14.4–16 px/°. A 0.25° azimuth step is a ≤ 4 px chord at native zoom. Auto-zoom magnifies it, so the hill wavelengths must be ≥ 4× the step: ≥ 200 m at 3 km.

## 2. Terrain generation and real DEM sources

| Resource | Resolution / datum | Licence and notice | Fit | Source | Verified? |
| --- | --- | --- | --- | --- | --- |
| **Copernicus DEM GLO-30** | 1″ (~30 m), DSM, EGM2008 | Free worldwide licence: reproduction, distribution, adaptation. Required notices: "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved", **plus** the no-liability sentence, which must bind sub-users | Far skyline ring (5–30 km). A DSM includes forest canopy, which suits a silhouette | [licence PDF](https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf), [GEE catalog](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_DEM_GLO30) | verified (licence text read) |
| SRTM GL1 v3 | 1″, void-filled | Public domain (NASA/USGS) | Fallback skyline | [data.gov](https://catalog.data.gov/dataset/nasa-shuttle-radar-topography-mission-global-1-arc-second-v003), [GEE](https://developers.google.com/earth-engine/datasets/catalog/USGS_SRTMGL1_003) | verified (search excerpts) |
| CNIG MDT02/MDT05 (PNOA LiDAR, Spain) | 2 m / 5 m DTM, ETRS89 UTM | CC BY 4.0; credit form like "MDT05 … CC-BY 4.0 ign.es" | Owner's own field, near field (L17) | [CNIG MDT02](https://centrodedescargas.cnig.es/CentroDescargas/modelo-digital-terreno-mdt02-segunda-cobertura), [IGN licence](https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf), [INSPIRE MDT05](https://inspire-geoportal.ec.europa.eu/srv/api/records/spaignMDT05) | verified (08 + search); exact credit wording unverified |
| OpenTopography | Distributor (API) of SRTM, COP30 and others | Per-dataset licence | Convenience only | [opentopography.org](https://opentopography.org) | unverified (not fetched) |
| GDAL 3.13.3 `gdal raster reproject` (since 3.11) | `--output-crs`, `--resolution`, `--bbox`, `--resampling`, `--target-aligned-pixels` | MIT | Reproject and crop to a Float32 GeoTIFF; **quantise in Python** with `round(h*256)` (integer rule of 08), not with `gdal_translate -scale` | [doc](https://gdal.org/en/stable/programs/gdal_raster_reproject.html), [gdal_translate](https://gdal.org/programs/gdal_translate.html) | verified (doc) |
| QGIS | inspection only | GPL-2+ (offline tool, never shipped) | Visual check of the crop and masks | — | inference |
| Integer generator `gen_terrain.py` (L13a) | `lowbias32` value noise, 1/256 m | MIT + Unlicense hash | Procedural relief and hill ring; same SHA-256 in stdlib and NumPy | [08](../landscape-investigations/08-terrain-generation-tools.md) | measured |

**Gentle farmland profile (targets).** Hammond (1964) classes, in the USGS port by Dikau et al. ([OFR 91-634](https://pubs.usgs.gov/of/1991/0634/report.pdf), verified): "gently sloping" means < 8 % slope; local relief is the maximum minus the minimum in a ~9.65 km window, in classes 0–30 m, 30–91 m and 91–152 m. Plains have > 80 % gentle slope. Proposed values:

| Zone | Distance from pilot | Relief | Max slope | Wavelength | Basis |
| --- | --- | --- | --- | --- | --- |
| Field (runway, pits) | 0–150 m | 0 (flat mask) | 0 | — | L13a masks |
| Swales | 150–1,200 m | ≤ 3–6 m | ≤ 3 % | 200–600 m | "flat plains" (relief ≤ 15 m) [estimate] |
| Rolling ring | 1.2–2.5 km | 10–30 m | ≤ 8 % | 400–1,200 m | "smooth plains" (relief ≤ 30 m) |
| Hill ring | 2.5–6 km | 40–120 m | ≤ 15–25 % | 800–2,500 m | "plains with hills" [estimate]; 0.5–1.5° tall |
| Far ridges (optional) | 10–30 km | 150–600 m (DEM) | — | — | contrast 0.18 → 0.03 at 23 km visibility |

## 3. Godot terrain add-ons (2026-10)

| Add-on | Version / activity | Licence | Compatibility | Web | Height sampler | Instancer | Source | Verified? |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Terrain3D** | v1.0.2-stable 2026-05-19, Godot 4.4–4.6+ (4.7 not stated); pushed 2026-10-07 | MIT | "fully supported since Terrain3D 1.0 and Godot 4.4" | "very experimental" | GPU clipmap, float heightmap, bilinear `get_height` (03); max 65.5 km world | yes, 10 LODs | [releases](https://github.com/TokisanGames/Terrain3D/releases), [platforms.md](https://github.com/TokisanGames/Terrain3D/blob/main/doc/docs/platforms.md), [double_precision.md](https://github.com/TokisanGames/Terrain3D/blob/main/doc/docs/double_precision.md) | verified (GitHub API + docs) |
| **HTerrain** (Zylann) | master 1.8.1-dev, "Godot 4.6+", pushed 2026-07-30 | MIT | not stated | unknown | GDScript, float32 heights, bilinear CPU height (03) | detail layers (grass) | [repo](https://github.com/Zylann/godot_heightmap_plugin) | verified (API, README); Compatibility **unverified** |
| DIY chunks + polar rings (chosen) | — | ours | ✅ | ✅ | **0.0 m vs the mesh at 100k points** | MultiMesh (trees L6) | [03](../landscape-investigations/03-terrain-mesh-gdscript.md) | measured |

Fit: both add-ons recentre a mesh on a moving camera; our pilot is fixed. Both would still need an export into our `openrc-terrain v1` grid for physics. Terrain3D needs native binaries per platform. **Keep L18 as a gate only.**

## 4. Sky and clouds in Compatibility

| Technique / resource | How | Cost per sky pixel | Compatibility / `TIME` | Licence | Source | Verified? |
| --- | --- | --- | --- | --- | --- | --- |
| Current deck (L4) | 5-octave integer-hash value noise on `dir.xz/dir.y` | ~20 hashes | ✅ / no TIME | ours | `sky.gdshader` | src |
| **Coverage octave (two scales)** | Multiply coverage by a 1-octave noise of period 4–8 deck units: clusters and clear gaps | +4 hashes | ✅ / no TIME | ours | inference | — |
| **Cirrus deck** | Second flat deck ~6× higher (cirrus 5–13 km vs low clouds < 2 km), noise stretched 4–8× along the wind, alpha ≤ 0.35, 3 octaves | +12 hashes | ✅ / no TIME | ours | [WMO Cloud Atlas étages](https://cloudatlas.wmo.int/en/clouds-definitions.html) | verified (heights) |
| Silver lining | `col += sun_lin · HG(cosθ, g≈0.6) · density·(1−density)` | ~5 ALU | ✅ | ours | inference | — |
| **Cloud shadows (L15d)** | Ground `light()`: project the fragment along `sun_dir` to deck height H; sample the same fbm (3 octaves); scale only the direct sun term. H = 1.5 km makes one noise cell H/`cloud_scale` = 250 m | +12 hashes per ground pixel | ✅ (`light()` exists in GLES3) | ours | [godotshaders overcast](https://godotshaders.com/shader/simple-overcast/) (ATTENUATION idea) | idea verified; numbers estimated |
| **Sky3D v2.1.0** (2026-05-19) | Physical-ish atmosphere; cumulus 10-step march × 4-octave fbm, 2 texture fetches each (~80 fetches); cirrus 2 fetches | heavy | "Forward, Mobile, and Compatibility"; `TIME` **only** for star twinkle; cloud positions are uniforms | MIT; star maps need credit | [repo](https://github.com/TokisanGames/Sky3D), `SkyMaterial.gdshader` | verified (source read) |
| Hosek-Wilkie per pixel (L19) | 9×3 coefficients from the CPU when the sun moves | 2 exp, 1 pow, 1 sqrt per channel | ✅ | BSD-3 | [02](../landscape-investigations/02-atmosphere-aerial-perspective.md) | verified (02) |
| Preetham | analytic | ~5 exp | ✅ | — | 02 | avoid (orange horizon at low sun) |
| Bruneton 2017 | 3 fetches of a ~8 MB 3D LUT | low ALU, 8 MB | ✅ (sampler3D) | BSD-3 | 02 | overkill for a slow sun |
| Sun glare / flare | Sky disc + glow; optional CC0 canvas flare, occlusion by our float64 ray | 1 quad | ✅ | CC0 | [09](../landscape-investigations/09-lighting-color-lookdev.md) | verified (09) |

## 5. Lighting and grading in 4.7.2 Compatibility (read from source)

| Feature | Status in GLES3 4.7.2 | Notes | Source | Verified? |
| --- | --- | --- | --- | --- |
| Tonemappers | Linear, Reinhard, Filmic, ACES, AgX | ACES at exposure 0.6 is today's choice (L1b) | [tonemap_inc.glsl](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/tonemap_inc.glsl) | src |
| Exposure | constant only; auto-exposure is Forward+ only | — | 09 | doc |
| **Adjustments (BCS)** | ✅ `USE_BCS`. Brightness on linear values; contrast and saturation on sRGB values with equal weights, which shifts the brightness of blues | Older 4.0–4.2 docs say "Forward+ and Mobile only": outdated | [post.glsl](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/effects/post.glsl) | src |
| **Colour LUT (1D/3D)** | ✅ but **only when `adjustment_enabled`**; sampled directly (`textureLod(lut, color)`) after `linear_to_srgb` | Build the LUT for direct-coordinate sampling | [rasterizer_scene_gles3.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp) | src |
| Glow | ✅ screen blend, before tonemapping; in an RGB10A2 target with glow the scene renders at ×0.25 luminance | Byte-repeat measured in 09 | post.glsl, rasterizer | src |
| **SSAO (S4AO)** | ✅ since commit 31ee691 (2025-08-08, Godot 4.6). Applied in post, multiplying the **final** linear colour before tonemapping (sky and sunlit areas included). Taps: very low 2, low 4, medium 12, high 30, ultra 60. The noise comes from the screen size, so it is deterministic | Could help tree bases (finding 4), but darkens globally. A/B with L6c | [s4ao_inc.glsl](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/s4ao_inc.glsl), [post_effects.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/effects/post_effects.cpp) | src |
| Post path switch | Glow, SSAO or BCS moves tonemapping into a post pass | Captures change: re-baseline goldens and L6c once | rasterizer L2410–2421 | src |
| Ambient from sky | ✅ (already used; radiance rendered once, QUALITY) | — | atmosphere.gd | src |
| SDFGI, SSIL, SSR, volumetric fog | ❌ | — | renderers doc | doc |

**Natural daylight targets** (sRGB, displayed):

| Target | Value | Basis |
| --- | --- | --- |
| Sunlit grass hue / HSV saturation | **75–90° / 0.40–0.55** (today 104–110° / 0.69–0.74) | Owner photo 73–80° / 0.43–0.53 (review 05); ColorChecker *Foliage* `#576c43` = 91° / 0.38, Y 0.13 [computed from [ColorChecker](https://en.wikipedia.org/wiki/ColorChecker)] |
| Zenith | Hosek `#4e6893` (L1a) | 02 |
| Colour temperature at a 45° sun | 5200 K `#ffe9d7` (L3) | 09 |
| Golden-hour preset | sun 8–10° (estimate), ~3500 K `#ffc78b`, shadows 6–7× object height; needs L19 per-pixel Hosek and haze from the same evaluation | Los Angeles: the sun stands 10–12° up an hour after sunrise ([Wikipedia](https://en.wikipedia.org/wiki/Golden_hour_(photography))); 09 table |
| Global saturation/contrast | leave at 1.0; fix albedos instead | protects livery readability (09, L6c) |

## 6. Ground subdivision and depth precision (G-1)

The Compatibility depth buffer is `GL_DEPTH24_STENCIL8` with no reverse-Z path ([texture_storage.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/texture_storage.cpp)) [src]. The step at distance d is ≈ d²·(f−n)/(f·n·2²⁴), with near 0.1 m and far 21 km [computed]:

| d (m) | 100 | 300 | 1,000 | 2,000 | 5,000 | 20,000 |
| --- | --- | --- | --- | --- | --- | --- |
| Depth step, near 0.1 m | 6 mm | 5.4 cm | 0.60 m | 2.4 m | 14.9 m | 238 m |
| Depth step, near 0.5 m | 1 mm | 1.1 cm | 0.12 m | 0.48 m | 3.0 m | 48 m |

- **Cause of G-1** [measured SC-01 + inference]: with a 3 cm lift, the runway at 100–300 m is above the depth step. The failure comes from the **two 40 km triangles clipped to the frustum**: the interpolated depth across them is off by more than the lift. SC-01 showed that 10 × 10 fixed it.
- **Fix now:** `PlaneMesh.subdivide_width = subdivide_depth = 63` in the rough surface (64 × 64 quads, 8,192 tris, 1 draw).
- **Later (L12b/c):** replace it with the near chunks plus the polar rings of §1, keeping each triangle edge ≤ ~10 % of its distance from the pilot [estimate].
- **Overlays:** surfaces live in the ground shader (L9c); contact quads keep the 2 cm lift only within 300 m (SC-05 measured).
- **Optional:** raise `Spec.CAMERA.near` to 0.25–0.5 m for 2.5–5× precision. The inspect camera sits ~2.5 m from the model; a camera-team decision, measure first.
- **Chunking references:** [CDLOD (Strugar 2010)](https://github.com/fstrugar/CDLOD) and geometry clipmaps (03) serve moving cameras. For a fixed pilot, rings built once avoid LOD pops and seams entirely.

## 7. Atmosphere at multi-km scale

Contrast left by haze, `C/C₀ = exp(−3.912·d/V)` [computed]:

| V \ d | 1 km | 2 km | 5 km | 10 km | 20 km |
| --- | --- | --- | --- | --- | --- |
| 12 km (hazy summer) | 0.72 | 0.52 | 0.20 | 0.04 | 0.00 |
| **23 km (today)** | 0.84 | 0.71 | 0.43 | 0.18 | 0.03 |
| 40 km (clear) | 0.91 | 0.82 | 0.61 | 0.38 | 0.14 |

Visibility classes run from "very poor" (1–4 km) to "excellent" (> 40 km) in the international code ([IALA](https://iala.int/wiki/dictionary/index.php/Meteorological_Visibility), [NOAA code table](https://www.ncei.noaa.gov/access/world-ocean-database/CODES/s_41_visibility.html)) [verified via search excerpts]. The haze colour against sun angle is already modelled: the anti-sun horizon is Hosek's `#c9e3ed`, with a pow-8 lobe giving ~1.2× toward the sun (L2). At low sun it must come from L19.

**Layered horizon targets** (each band must differ from its neighbours):

| Layer | Distance | Contrast at 23 km | Content | Step |
| --- | --- | --- | --- | --- |
| Near treeline | 100–400 m | 0.93–0.98 | cards (exists) | L6 |
| Hedgerows / field edges | 0.4–1.5 km | 0.77–0.93 | strip cards + patchwork albedo | L7 strip, far-ground land cover |
| Far forest / rolling ring | 1.5–3 km | 0.60–0.77 | ring mesh, darker green | L7/L12c |
| Hills | 3–6 km | 0.36–0.60 | ring mesh heights | L13a |
| Ridges / mountains (optional) | 10–30 km | 0.18–0.01 | DEM skyline; visible only at V ≥ 40 km beyond 15 km | L17-lite |

## Not verified

- Whether 64 × 64 fixes every SC-01 view on real GPUs as well as on llvmpipe. Proof needed: the SC-01 12-view sweep plus `capture.sh`.
- Terrain3D on Godot 4.7.x (its notes say 4.4–4.6+); HTerrain in Compatibility.
- Frame-time cost of the extra cloud octaves, cloud shadows and S4AO on the owner's slowest machine (llvmpipe numbers don't count).
- The exact CNIG credit string, OpenTopography terms, and the claim that SRTM GL1 is public domain (search excerpts only).
- The golden-hour sun elevation (8–10°) and the hill heights are estimates; the owner's eye decides at Gate L.
- Whether a direct-sampled 3D LUT needs a half-texel remap to be neutral (read from code, not tested).

## Sources

- Godot 4.7.2-stable source: [post.glsl](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/effects/post.glsl), [tonemap_inc.glsl](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/tonemap_inc.glsl), [rasterizer_scene_gles3.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp), [post_effects.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/effects/post_effects.cpp), [s4ao_inc.glsl](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/s4ao_inc.glsl), [texture_storage.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/texture_storage.cpp) (read 2026-10-07)
- [Godot 4.6 SSAO in GLES3 (news)](https://digitalproduction.com/2026/01/28/godot-4-6-arrives-with-major-cg-friendly-updates/); [Reverse-Z article](https://godotengine.org/article/introducing-reverse-z/)
- Terrain3D: [releases](https://github.com/TokisanGames/Terrain3D/releases), [platforms.md](https://github.com/TokisanGames/Terrain3D/blob/main/doc/docs/platforms.md); HTerrain: [repo](https://github.com/Zylann/godot_heightmap_plugin); Sky3D: [repo](https://github.com/TokisanGames/Sky3D)
- PicaSim: [ParallaxPanorama.md](https://github.com/Rowlhouse/PicaSim/blob/main/ParallaxPanorama.md); RealFlight/Aerofly/CRRCSim via [landscape-research](../landscape-research.md) and [07](../landscape-investigations/07-open-source-sims-scenery-code.md)
- DEMs: [Copernicus licence](https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf), [GLO-30 catalog](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_DEM_GLO30), [SRTM GL1](https://catalog.data.gov/dataset/nasa-shuttle-radar-topography-mission-global-1-arc-second-v003), [IGN licence](https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf), [GDAL reproject](https://gdal.org/en/stable/programs/gdal_raster_reproject.html)
- Landforms: [Dikau et al., USGS OFR 91-634 (Hammond classes)](https://pubs.usgs.gov/of/1991/0634/report.pdf); clouds: [WMO Cloud Atlas](https://cloudatlas.wmo.int/en/clouds-definitions.html); colour: [ColorChecker](https://en.wikipedia.org/wiki/ColorChecker); terrain LOD: [CDLOD](https://github.com/fstrugar/CDLOD)
