# Landscape research: sky, horizon, terrain, vegetation and field (2026-10-05)

**Question:** how do we turn the flat 2 km grass plane and solid-blue sky into a landscape that looks good *and* helps the pilot read attitude, distance, height and speed, while staying on Godot 4.7's **Compatibility** renderer (web export, software-GL captures)?

The plan built on this research is [docs/LANDSCAPE-PLAN.md](../LANDSCAPE-PLAN.md). Eleven deeper follow-up investigations (with spikes) are in [landscape-investigations/](landscape-investigations/README.md); where they correct this summary (aerial perspective is a no-op in 4.7.2 Compatibility, alpha-to-coverage does nothing, render counters read 0 headless), they take precedence.

**Evidence labels:** **[doc]** official documentation · **[rel]** release notes · **[src]** engine or plugin source read at a pinned tag · **[iss]** GitHub issue/PR · **[OM]** official product manual · **[AP]** academic paper · **[F]** forum (community opinion) · **[sec]** secondary source · **[measured]** run on this repo · **[inference]** our reasoning, not sourced.

Most of this is documentation research by four sub-agents, checked against each other. Only the spike in §0 was run here.

---

## 0. What the pilot sees today, and a first spike [measured]

Captures from `app/` at `4.7.2-stable` under Xvfb/llvmpipe, 1280×720, no auto-zoom:

- **Trimmed flight at 30 m (`--t=1.5 --autozoom=0`):** the frame is ~98 % flat sky. The ground is a 10 px strip at the bottom edge.
- **Scripted circle:** no ground is visible at all.
- **Conclusion:** the camera tracks the airplane upward, so **the sky is the background of almost every frame**. The current sky (one flat colour) gives no attitude, heading or motion cue at all.
- This matches the D7 finding already in LEARNINGS: auto-zoom at altitude pushes the ground out of the frame.

**Spike (scratch copy, never in `app/`):** `ProceduralSkyMaterial` (top `#3d74c4`, horizon `#c9dcef`), sky ambient and reflections, Filmic tonemap, depth fog from 150 m to 1500 m.

- Two runs of `--capture --t=1.5 --alt=3 --autozoom=0` gave **byte-identical PNGs** (SHA-256 `11a22b69…71d48a`).
- At 30 m the vertical sky gradient alone shows which way is up, even with no ground in the frame.
- At 3 m the fog softens the horizon.
- **Defects the spike exposed:**
  - the 1 km edge of the ground plane shows as a grey line on the horizon;
  - the runway (`#6f9a4a`) is ~30 % lighter than the grass (`#4a7a32`), but it has no edges or markings, and at a grazing angle it reads as a pale band rather than a runway.

## 1. Godot 4.7 Compatibility renderer: what we can use

Sources: [renderers](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html), [environment](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html), [sky shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html), [lights and shadows](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html), [visibility ranges](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html), [MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html), [rendering limitations](https://docs.godotengine.org/en/stable/tutorials/3d/3d_rendering_limitations.html), [image import](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html), [web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html). Engine source at [4.7.2-stable `drivers/gles3`](https://github.com/godotengine/godot/tree/4.7.2-stable/drivers/gles3).

| Feature | Compatibility 4.7 | Notes for us |
| --- | --- | --- |
| Procedural / Physical / Panorama sky, custom sky shaders | ✅ [doc] | Physical sky renders too dark ([#84441](https://github.com/godotengine/godot/issues/84441)); HDR panoramas too dark or too bright ([#83788](https://github.com/godotengine/godot/issues/83788)). **Procedural sky or our own sky shader is the safe start** |
| Sky half/quarter-resolution passes | ❌ [src] | Not implemented in GLES3: an expensive sky shader costs full resolution. Put cloud maths in `AT_CUBEMAP_PASS` and read `RADIANCE` for the background |
| Sky ambient and reflections (radiance) | ✅ [src] | Low dynamic range cubemap (RGB10_A2). **`TIME` in a sky shader forces a radiance update every frame**; custom uniforms make it incremental (converges over several frames). Set `Sky.process_mode = QUALITY` for deterministic captures |
| Depth / height fog, sun scatter, aerial perspective | ✅ [doc][src] | Fog blending changed in 4.6 (`fog/use_legacy_blending`). Aerial perspective does not blend seamlessly into the sky ([#97803](https://github.com/godotengine/godot/issues/97803)) |
| Volumetric fog, SSR, SSIL, SDFGI, VoxelGI, auto exposure, DoF | ❌ [doc] | |
| SSAO | ✅ simplified, since 4.6 [rel] | Only radius and intensity |
| Glow | ⚠️ simplified [doc] | Blend mode is always Screen; levels ignored. Enough for a sun glare |
| Tonemap: Linear/Reinhard/Filmic/ACES/AgX | ✅ [src] | **RGBA8 output, no debanding**: sky gradients and fog can band, so add dithering in our sky shader [inference] |
| Directional shadows (PSSM 2/4 splits) | ✅ [src] | Shadow blur ignored ([#82504](https://github.com/godotengine/godot/issues/82504)). **Lit surfaces get brighter when shadows are on** ([#90259](https://github.com/godotengine/godot/issues/90259)): re-tune energy after enabling. Always set Max Distance; with PSSM4 the terrain is drawn 5× |
| Decals | ❌ in 4.7; ✅ in 4.8 dev4 [rel] | Runway markings must be geometry or texture, not decals, until 4.8 |
| LightmapGI | display only [doc] | Baking needs a Vulkan/D3D12/Metal machine; not needed for an open field |
| MultiMeshInstance3D | ✅ [doc] | **Main tool for trees and grass.** One draw call; no per-instance culling, so **chunk it** (one MultiMesh per area per species) |
| Visibility ranges (HLOD) | ✅ ranges, ❌ fade [src] | GLES3 never reads the fade settings: LOD switches **pop**. `GeometryInstance3D.transparency` does not work ([#76774](https://github.com/godotengine/godot/issues/76774)). Hide pops in fog distance |
| Automatic mesh LOD | ✅ [src] | |
| Occlusion culling | desktop ✅, **web ❌** [src] | Little gain for an open field anyway [doc] |
| MSAA 3D | ✅ | FXAA/TAA/SMAA ❌. Alpha-to-coverage for foliage needs MSAA. **Alpha hash not implemented** ([#103094](https://github.com/godotengine/godot/issues/103094)) |
| VRAM compression | S3TC desktop, ETC2 web [doc] | BPTC/ASTC always off in Compatibility, so **HDR textures stay uncompressed** (RGBE9995, 4 B/px) |
| Shader baker / ubershaders | ❌ (Forward+/Mobile only) [doc] | Show new materials for one frame at load to avoid hitches |

**Capture determinism:** TAA does not exist in Compatibility, so there is no projection jitter. Particles need `use_fixed_seed`. Skies should not read `TIME`; drive any animation from our own uniform fed from simulation time. Keep captures on a pinned Mesa/llvmpipe. Cross-thread-count bit-identity is not confirmed.

**Precision:** float32 step at 2–4 km from the origin is ≈ 0.2 mm, so a 5 km world centred on the pilot needs no large-world build ([large world coordinates](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html)).

**Web limits:** stay ≤ 4096 px per texture. Only 4096 is supported by 100 % of WebGL 2 devices; 8192 by 96 % ([web3dsurvey](https://web3dsurvey.com/webgl2/parameters/MAX_TEXTURE_SIZE), [sec]).

## 2. Terrain and vegetation tooling

| Option | Status (2026-10) | License | Compatibility / web | Physics height == rendered height? |
| --- | --- | --- | --- | --- |
| **DIY heightmap chunks** (`ArrayMesh` from one grid) | ours | ours | ✅ / ✅ (plain meshes) | **Exact by construction**, if the CPU sampler uses the mesh's triangle diagonal |
| [Terrain3D](https://github.com/TokisanGames/Terrain3D) (C++ GDExtension) | v1.0.2, 2026-05-19, active | MIT | ✅ "fully supported since 1.0 + Godot 4.4" ([platforms](https://terrain3d.readthedocs.io/en/stable/docs/platforms.html)) / web "very experimental", matching threads build + COOP/COEP headers ([#502](https://github.com/TokisanGames/Terrain3D/issues/502)) | ❌ `get_height()` is bilinear and single precision ([API](https://terrain3d.readthedocs.io/en/stable/api/class_terrain3ddata.html)); clipmap LOD and geomorphing differ further |
| [HTerrain](https://github.com/Zylann/godot_heightmap_plugin) (GDScript) | bug fixes only | MIT | undocumented; an old Godot 3 Web issue | ❌ bilinear |
| MTerrain, Terrainy, godot_voxel | alpha / generator / custom engine build | MIT | unknown / ? / ❌ | — |

- **Deterministic height for float64 physics** [inference, from the terrain report]:
  - one committed grid of heights, **quantised to multiples of 1/256 m** so they are exact in float32 and in the file;
  - render triangles with a fixed diagonal;
  - the sim picks the triangle by `fx + fz < 1` and evaluates the plane in float64.
- **Bilinear vs triangle-exact:** a bilinear sampler differs from the rendered triangles by up to ~Δh/4 inside a cell: invisible, but not exact.
- **LOD rule:** only LOD0 equals physics, so the whole flyable area must be LOD0.
- **Do not generate terrain at runtime for physics.** Godot's FastNoiseLite computes in float32 with `sqrtf`, and cross-OS/arch bit-identity is not guaranteed ([source](https://github.com/godotengine/godot/blob/master/thirdparty/misc/FastNoiseLite.h), [determinism note](https://gafferongames.com/post/floating_point_determinism/) [sec]).
  - Generate offline with a seeded tool and commit the result plus its SHA-256.
- **Godot heightmap import:** PNG imports as 8-bit only, so use EXR or raw R16/float32 read with `FileAccess` ([Terrain3D import doc](https://github.com/TokisanGames/Terrain3D/blob/main/doc/docs/import_export.md)).

**Vegetation:**
- **MultiMesh per chunk** (64–128 m) per species ([doc](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)).
- **Grass:** alpha scissor + alpha-to-coverage with MSAA 2×, and wind sway in the vertex shader (reference: [GodotGrass](https://github.com/2Retr0/GodotGrass), MIT).
- **Scatter tools:** [ProtonScatter](https://github.com/HungryProton/scatter) (MIT; fixed for 4.7 in 2026-07) and [Spatial Gardener](https://github.com/dreadpon/godot_spatial_gardener) (MIT). Both are editor-time scatter tools.
- **Distant trees:** a pre-baked 2–4-view billboard atlas is the low-risk choice. The octahedral impostor plugin for Godot 4 ([godot-imposter](https://github.com/zhangjt93/godot-imposter), MIT) is only verified on 4.5 beta.
- **Collision:** Jolt `HeightMapShape3D` exists ([class ref](https://github.com/godotengine/godot/blob/master/doc/classes/HeightMapShape3D.xml)), but **our physics is our own float64 code**. Trees become float64 cylinders in `sim/`, not Jolt bodies [inference].

## 3. How RC simulators do scenery

| Sim | Scenery approach | Occlusion and collision | Source |
| --- | --- | --- | --- |
| RealFlight | 360° photo panoramas (cube faces on import, up to 20000×10000) + 3D fields | Invisible "depth buffer objects" over photo trees; misaligned ones cause phantom crashes | [OM manual](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1314820/manuals/RealFlight_Help_Guide.pdf), [F](https://steamcommunity.com/app/1070820/discussions/0/2998795613912468705/) |
| Aerofly RC 10 | Photo, multi-pano and "4D" sceneries (animated windsocks/trees, weather, time of day) | Photo scenes: fixed camera only, plus a "landing assist" overlay; users crash into trees that "look far" | [OM manual](https://www.ikarus.net/downloads/service/aerofly-rc-7-manual-english.pdf), [F](https://steamcommunity.com/app/2394350/discussions/0/4354491868386005897/) |
| PicaSim (open) | Cube-face skybox (1024² per face, tiled at higher detail) + 513×513 heightmap at 5 m | Terrain drawn only to depth: invisible, but occludes the plane and catches its shadow; VR parallax from depth | [src](https://github.com/Rowlhouse/PicaSim), [ParallaxPanorama.md](https://github.com/Rowlhouse/PicaSim/blob/main/ParallaxPanorama.md) |
| SeligSIM | Equirectangular 8K–32K, tiled, streamed; **eye height 1.70 m** | `.ele` ground triangles with friction, `.col` obstacle triangles, `.dom` sun azimuth/elevation | [OM](https://www.seligsim.com/manual/documentation.html) |
| Phoenix RC | 6-face cube map | Collision primitives; a masking object "blocks out 3D objects behind it" | [OM (third-party host)](https://silo.tips/download/phoenixcreator-index-creating-a-custom-flying-site-creating-a-new-project) |
| ClearView, AccuRC, FMS | Equirectangular / spherical / 2048² BMP skyboxes | AC3D fly-behind objects; topography from mapping data | [ClearView](https://rcflightsim.com/sceneries.html), [AccuRC](https://accurcsimulator.com/scenery/) |
| CRRCSim (open) | 3D AC3D + XML; sun position and haze in the scenery file; a "population" tag scatters trees | Shadow volumes | [news](https://sourceforge.net/p/crrcsim/news/) |

**Photo panorama vs 3D for a static pilot:**

- **Panorama strengths:** photoreal and geometrically exact for one fixed eye, at almost no GPU cost.
- **What panoramas break:** chase, FPV and VR depth.
  - Lighting is baked into the photo, so there is no time of day.
  - Collision and occlusion proxies must be hand-aligned to the photo.
  - Ground shadows need an invisible receiver mesh.
- **3D strengths:** keeps every camera, shadow and collision consistent.
- **3D risk:** it looks "dated, tiled, primitive trees" when done cheaply ([review](https://tallyhocorner.com/2021/02/aerofly-rc-8-review/), [sec]).
- **Recommended hybrid** [inference]: near field (out to ~600 m) in 3D, far ring beyond 1–2 km as low-poly hills or a sky panorama.
  - A chase camera moving 10 m shifts an object at 500 m by only ~1.1°.

**Resolution arithmetic** [inference]:
- 1920 px across 60° is ~32 px/°; an 8K equirectangular gives 22.8 px/°.
- The Stik at 200 m subtends 0.43° (~14 px), so **background contrast matters more than background detail**.

## 4. Human factors: which landscape cues help an RC pilot

- **Distance bands (vista space beyond ~30 m):** the cues that work are occlusion, relative size, height in the visual field and aerial perspective. Stereo is useless beyond ~tens of metres, so VR adds little at 150–300 m. Source: Cutting & Vishton 1995 [AP] ([summary](https://www.semanticscholar.org/paper/Perceiving-Layout-and-Knowing-Distances-Cutting-Vishton/923b83e758da03419f83be1b1e3a059118e0e57b)).
- **Vertical objects and ground texture:**
  - **Density of vertical objects** (trees, posts) improved pilots' altitude-change detection; more detail per object did not help.
  - Ground texture helped but did not replace object density.
  - Source: Kleiss & Hubbard 1993 [AP] ([doi](https://doi.org/10.1177/001872089303500406)).
- **Scene detail and training transfer:** a low-detail scene transferred landing skill better than moderate detail. Source: Lintern et al. [AP] ([link](https://www.tandfonline.com/doi/abs/10.1207/s15327108ijap0702_4)). Detail is not the goal; cues are.
- **Moving shadows:** a moving cast shadow alone sets the perceived 3D path. Source: Kersten, Mamassian & Knill 1997 [AP] ([link](https://experts.umn.edu/en/publications/moving-cast-shadows-induce-apparent-motion-in-depth/)).
- **Pilot practice:**
  - A landmark lined up with the runway is the cue to start the final turn ([Model Aviation](https://www.modelaviation.com/LandingApproach), [sec]).
  - "Never fly across the sun" ([sec](https://www.rc-airplane-world.com/flying-your-rc-airplane)).
  - A plane is lost against dark trees and reads best as a silhouette against bright sky ([F](https://www.rcgroups.com/forums/showatt.php?attachmentid=9111816&d=1466630100)).
- **Community wishes** (full-scale sim forums, by analogy) [F]: windsocks and trees that move with the wind, so the wind can be read before landing ([MSFS](https://forums.flightsimulator.com/t/3d-trees-are-not-moving-sufficient-enough-in-wind/676664), [DCS](https://forum.dcs.world/topic/307126-a-windsock-that-adapts-to-the-strength-of-the-wind/)).
  - **Counterpoint:** latency, stick mapping and frame rate matter more for skill transfer than decoration.

## 5. A real RC club field (layout reference)

**AMA, "Suggested RC Flying Site Specifications" (2022) [OM]** ([PDF](https://www.modelaircraft.org/sites/default/files/documents/Suggested%20Flying%20Site%20Specifications.pdf)):
- Flight box 750 ft (229 m) deep beyond the safety line, 1000 ft (305 m) to each side, plus a 250 ft safety zone.
- The runway edge sits on the safety line.
- Distances behind the safety line: barrier 0–15 ft, pilot line 0–25 ft, pilot stations 0–45 ft, pits 0–65 ft, spectators 0–80 ft, then parking.
- Barriers are often orange plastic fence.

**BMFA handbook §11 [OM]** ([link](http://handbook.bmfa.org/11-r-c-power-flying-site-layout-and-flight-patterns)):
- Pits ≥ 30 m from the take-off and landing path.
- Car park ≥ 100 m away, behind the pits.
- "Dead airspace" over pits and cars.

**Runways [F]:**
- 300–400 ft long for 40–90 size models; 30–75 ft wide ([RCU](https://www.rcuniverse.com/forum/clubhouse-190/1798505-grass-runway-length.html)).
- Our 100 m × 12 m runway is in range.

No official rule on sun orientation was found. Clubs generally keep the sun behind the pilots [F].

## 6. Assets and data we may ship

| Source | License | Attribution | Commit and ship? | Use |
| --- | --- | --- | --- | --- |
| [Poly Haven](https://polyhaven.com/license) | CC0 | no | ✅ | HDRIs (`*_puresky` variants have no ground, e.g. `kloofendal_48d_partly_cloudy_puresky`, `autumn_field_puresky`, `farm_field_puresky`), ground textures, `modular_chainlink_fence`, `fir_tree_01` |
| [ambientCG](https://docs.ambientcg.com/license/) | CC0 | optional | ✅ | Grass001/004/005/008, Ground037, Gravel023, Asphalt031 (ship 1K–2K) |
| [Kenney](https://kenney.nl/support) | CC0 (no logo) | optional | ✅ | [Nature Kit](https://kenney.nl/assets/nature-kit), [Car Kit](https://kenney.nl/assets/car-kit) |
| [Quaternius](https://quaternius.com/faq.html) | CC0 | no | ✅ (free tier is partial) | [Ultimate Stylized Nature](https://quaternius.com/packs/ultimatestylizednature.html) trees and bushes |
| [Sky3D](https://github.com/TokisanGames/Sky3D) | MIT | notice | ✅ | Day/night sky; Compatibility needs settings tweaks |
| [godotshaders.com](https://godotshaders.com/license/) | per shader (CC0/MIT/GPL-3), **no default** | depends | CC0/MIT only | e.g. [Stylized Sky With Clouds](https://godotshaders.com/shader/stylized-sky-shader-with-clouds/) (CC0, noise generated in engine) |
| [OpenGameArt](https://opengameart.org/content/faq) | mixed | depends | case by case; avoid CC-BY-SA/GPL art | gap fillers |
| [Sketchfab CC-BY](https://sketchfab.com/developers/download-api/guidelines) | CC-BY | **yes, in-game credits** | ✅ with credits | one-off props |
| [Textures.com](https://www.textures.com/support/faq-license) | proprietary | — | ❌ **never** | — |

No CC0 windsock, pilot station or pit table was found. They are simple enough to build from primitives in code, like the airplane.

**Size budget:**
- Poly Haven `derelict_airfield_01` `.hdr`: 1k is 1.4 MB, 2k 5.7 MB, 4k 23 MB, 8k 94 MB ([API](https://api.polyhaven.com/files/derelict_airfield_01)).
- In Compatibility an HDR stays uncompressed: 4096×2048 is ≈ 32 MiB of VRAM [inference].
- LDR S3TC/ETC2 at 4096×2048 is ≈ 4 MiB.
- **Shader-generated skies and clouds cost almost nothing to download.**

**Real terrain, if we model a real field later:**

| Dataset | Resolution | License and attribution |
| --- | --- | --- |
| [Copernicus GLO-30](https://docs.sentinel-hub.com/api/latest/static/files/data/dem/resources/license/License-COPDEM-30.pdf) | 30 m | Free; an exact attribution notice is required |
| [SRTM](https://www.usgs.gov/centers/eros/science/usgs-eros-archive-digital-elevation-shuttle-radar-topography-mission-srtm-1) | 30 m | Public domain |
| [USGS 3DEP](https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits) | 1 m lidar | Public domain, US only |
| [CNIG MDT LiDAR PNOA](https://centrodedescargas.cnig.es/CentroDescargas/home) | 0.5–5 m | CC-BY 4.0, credited as e.g. "MDT05 [year] CC-BY 4.0 scne.es"; check each product's wording |
| [OpenStreetMap](https://www.openstreetmap.org/copyright) | vector | ODbL: derived *data files* stay ODbL |

- Convert with GDAL: `gdalwarp` to a metric CRS, then `gdal_translate -of EXR -co PIXEL_TYPE=FLOAT` ([GDAL EXR](https://gdal.org/en/stable/drivers/raster/exr.html)).

**Own-field panorama:**
- Cameras: Insta360 X5 (11904×5952; brackets limited to 18 MP), Ricoh Theta Z1 (RAW brackets), or phone/DSLR + [Hugin](https://en.wikipedia.org/wiki/Hugin_(software)) (GPL; the output is ours).
- Shoot at 1.70 m eye height with a separate nadir shot to remove the tripod ([PTGui tutorial](https://www.ptgui.com/examples/vptutorial.html)).
- Target 8192×4096 for desktop and ≤ 4096 for web.

## 7. Not confirmed / open

- Whether Compatibility glow, SSAO or MSAA vary frame to frame under llvmpipe.
- Whether llvmpipe output is bit-identical across thread counts.
- Whether Sky3D's clouds need bundled noise textures.
- Basis Universal transcoding on web.
- Exact CNIG credit wording per product.
- No numeric draw-call or instance budgets exist for web. **We measure our own** (plan step L0).
