# 04 · Godot techniques and prior art for populating the field

Date: 2026-10-07 · Step: SC-01 (research input for SC-04, SC-05, SC-09, SC-15, SC-18, SC-24) · **Question:** which Godot 4.7.2 Compatibility techniques keep a populated club field cheap, grounded and stable, and what do other RC and FPV sims teach about scenery?

Evidence tags: **[src]** Godot 4.7.2-stable source read; **[doc]** official doc or class reference read; **[meas]** measured here; **[calc]** computed here; **[sec]** secondary page read; **[snip]** search snippet only, page not readable (counts as not verified). Scratch work stayed in `/tmp/claude-1000/scenery-research/`. Nothing in `app/` was touched.

## Summary

- **Compatibility does no automatic 3D batching.** `rasterizer_scene_gles3.cpp` has no batching code; the docs say to join static meshes ahead of time. Godot 4 has no `MergeGroup` and no `MeshInstance3D` merge method. Two built-in tools merge meshes at runtime: `SurfaceTool.append_from` and `ImporterMesh.merge_importer_meshes`. The second fixes winding for negative scale and merges surfaces that share a name. Plugins are optional.
- **Palette atlas:** every Kenney Car Kit 3.1 model has 1 material and the same 512² `colormap.png` (32 px colour cells, CC0). glTF Transform 4.5.0, already pinned in `tools/trees`, has `palette()`, `flatten()` and `join()` to do the same to other assets.
- **Grounding:** an alpha-blended black quad with the engine's fog gives the right fogged shadow; `blend_mul` does not. The lift must grow with distance², because depth precision does. Lightmaps render in Compatibility, but baking needs a Forward+/Mobile device: not worth it here. AO baked into vertex colors (Blender Cycles "Active Color Attribute") is the cheap route.
- **Depth buffer is 24-bit, not 16-bit** (D24S8 render targets, GLX 24-bit). Godot's reverse-Z gains nothing here: GL keeps its −1…1 depth range, so precision stays hyperbolic. With near 0.1 m, one depth step is about **2.4 m at 2 km and 15 m at 5 km**. Turbine blades and tower will z-fight. Raise the near plane, or separate the parts along the view ray.
- **Motion:** use vertex shaders driven by a uniform (rotors, flags, rigid-part "pivot" animation), never `TIME`. Each `Skeleton3D` skin costs an extra transform-feedback pass per surface per frame, and skinned meshes can't merge. Vertex animation textures (VAT) work in Compatibility, but with fewer `INSTANCE_CUSTOM` channels.
- **Prior art:** photo fields win on looks and frame rate, but break moving cameras and collisions. 3D fields get called "dated" when trees and textures repeat. Aerofly's selling point is wind-driven motion: windsocks, flags, turbines, trees. Busy, sharp backgrounds hurt plane visibility.

## 1. Fewer draw calls: merging and the palette atlas

| Technique / tool | How | Compatibility 4.7.2 status | Cost | Source | Verified? |
| --- | --- | --- | --- | --- | --- |
| Automatic 3D batching | None. Only 2D is batched | No batching code in the GLES3 scene renderer | Each surface of each visible instance is ≥ 1 draw | [rasterizer_scene_gles3.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp) [src]; [GPU optimization (4.7)](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html) [doc]: "join meshes ahead of time… several objects rendered as one cannot be individually culled" | Yes |
| `MergeGroup` / `MeshInstance3D` merge | Godot 3.6 only | Not in 4.x; `MeshInstance3D` has no merge method | — | [MeshInstance3D.xml](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/MeshInstance3D.xml) [doc]; [3.6 merge groups](https://docs.godotengine.org/en/3.6/tutorials/3d/merge_groups.html) [snip] | 4.x: yes |
| `SurfaceTool.append_from(mesh, surface, xform)` | Appends transformed vertices and indices to one surface; then `commit()` | Works; C++ | Load-time CPU only. Pitfalls [src]: normals use `basis` without inverse-transpose (wrong under non-uniform scale); **no winding fix for negative scale**; vertices from a mesh without colours keep `Color()` = **(0,0,0,1) black** once any mesh adds colours (inferred from source, not run) | [surface_tool.cpp L1021](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/surface_tool.cpp#L1021), [surface_tool.h](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/surface_tool.h) [src] | Yes |
| `ImporterMesh.merge_importer_meshes(meshes, xforms, dedupe=true)` | Merges meshes with relative transforms; surfaces with the same name and format are merged and keep the first one's material | Registered at runtime (not editor-only) | Load time. Normals re-normalized (still no inverse-transpose); **winding fixed for negative determinant**; drops blend shapes and LODs | [ImporterMesh.xml](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/ImporterMesh.xml), [importer_mesh.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/3d/importer_mesh.cpp), [register_scene_types.cpp L630](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/register_scene_types.cpp#L630) [src] | Yes |
| Offline merge in glTF Transform 4.5.0 (`flatten` → `palette` → `join`) | `palette()` turns solid-colour materials into palette textures and merges the materials; `join()` merges primitives with a compatible material | Output is a plain GLB; nothing extra at runtime | Build-time only; already pinned in `tools/trees/package.json` | [palette](https://gltf-transform.dev/modules/functions/functions/palette), [join](https://gltf-transform.dev/modules/functions/functions/join) [doc]; `palette`/`flatten`/`join` in [4.5.0 typings](https://unpkg.com/@gltf-transform/functions@4.5.0/dist/index.d.ts) [src] | Yes |
| Static Mesh Merger (EverettM12) | Editor plugin: merge selected → `.res` | MIT, "4.x", updated 2026-08 | Editor only; 3 stars | [asset 5429](https://godotengine.org/asset-library/asset/5429), GitHub API [sec] | License and date: yes; code: no |
| Merging Meshes Godot (EmberNoGlow) | `MergingMeshes` node with a list of `MeshInstance3D`s | CC0, Godot 4.4 | — | [asset 4538](https://godotengine.org/asset-library/asset/4538) [sec] | License: yes; code: no |
| MultiMesh for repeats | 1 draw per surface; per-instance colour and custom data | Works; colour and `INSTANCE_CUSTOM` **packed to 16-bit halfs** | +1 draw (landscape 05, measured) | [scene.glsl L688](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl#L688) [src]; [MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html) [doc] | Yes |
| Palette/colormap atlas | All props UV-map into colour cells of one texture, so one material serves all | Plain texture | 1 material for the whole zone | Kenney Car Kit 3.1 [meas]: 50 GLB, **1 material each, all pointing to `Textures/colormap.png` 512², 32 px cells** (2,330 unique colours), no vertex colours, 5–7 nodes per vehicle, 28–3,124 triangles, CC0 (`License.txt`). KayKit: one 1024² gradient atlas [snip] ([itch](https://kaylousberg.itch.io/resource-bits)). Pattern: [Papaya Games devlog](https://papaya-games.itch.io/duck-in-town/devlog/73530/blazing-fast-rendering-with-a-single-material-per-scene) [sec] | Kenney: yes; KayKit: no |

**Notes:**
- **Mipmap bleeding.** 32 px cells reach 1 texel at mip 5. Sample cell centres, or cap mips/LOD bias for the palette. Because LOD is fixed per object, the fix can be per zone.
- **Kenney vehicles are node trees** (body + wheels). Flatten them (glTF `flatten()`, or merge with node transforms) before joining. The kit also ships `debris-*` parts (doors, bumpers, tyres), a possible source for the crash track.

## 2. Grounding props without engine shadows

| Technique | How | Compatibility 4.7.2 status | Cost | Source | Verified? |
| --- | --- | --- | --- | --- | --- |
| Engine shadows (PSSM) | — | Avoided by the project: shadowed light is computed in sRGB (#90259, L3) | Shadow pass | [LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md) | Project decision |
| Decal node | Projected texture | **Not in 4.7.2.** Arrives in 4.8 (dev 4, 2026-08-26): ≤ 64 per frame (soft cap), ≤ 8 per surface (hard limit) | — | [Godot 4.8 dev 4](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-4/) [doc] | Yes |
| Contact shadow quad, alpha blend (`blend_mix`) | Black quad, alpha = footprint, projected along the fixed sun; one merged mesh per zone | Works | 1 draw per zone, transparent pass, sorted | [render/shadow.gd](../../../app/render/shadow.gd) (planar projected shadow in this repo) | Yes |
| Contact shadow quad, `blend_mul` | Multiplies the ground | Render mode exists in GLES3 and goes to the transparent pass | Same | [material_storage.cpp L3039, L3211](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/material_storage.cpp#L3039) [src] | Yes |
| Fog on the shadow quad | Engine fog shades the quad's black colour toward the fog colour | — | — | [calc]: the ground is already fogged, dst = mix(G, F, f); the quad's colour is mix(0, F, f) with alpha a, so blending gives G·(1−a)(1−f) + F·f. That equals a shadowed ground fogged correctly (in linear space). `blend_mul` gives dst·mix(0, F, f) instead, which is wrong at distance. Compatibility blends in sRGB, so it is only near-exact. Check with a capture | Formula: yes; render: no |
| Lift above ground vs z-fighting | Offset the quad up, or toward the camera | No depth-bias render mode for spatial shaders (none listed) | — | [calc] (§3 table): one depth step is 1.5 mm at 50 m, 2.4 cm at 200 m, 9.5 cm at 400 m. A fixed 2 cm lift **z-fights beyond about 180 m**. Scale the lift with d² per zone (the pilot never moves) | Calc |
| Baked AO in vertex colours | Blender Cycles bake type "Ambient Occlusion", Target **"Active Color Attribute"**; the shader multiplies albedo by `COLOR.r` | Plain vertex attribute | 0 draws, +4 B/vertex | [Blender 5.2 manual, baking](https://docs.blender.org/manual/en/latest/render/cycles/baking.html) [doc]; low-poly meshes may need extra loops for AO to read [sec] | Yes |
| LightmapGI | Baked lightmaps, UV2 | **Renders** in Compatibility (`USE_LIGHTMAP` in the GLES3 scene shader); **baking needs a Forward+/Mobile device** and the editor | Binary EXR plus UV2 per prop; can't bake on the GPU-less dev VM or in CI | [LightmapGI.xml](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/LightmapGI.xml) [doc], [scene.glsl L21](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl#L21) [src] | Yes |

**Recommendation for SC-05:**
- One alpha-blend footprint mesh per zone. Footprints are baked from each prefab's silhouette along `Spec.ATMOSPHERE`'s sun. Lift ∝ d².
- Vertex-colour AO inside the prefabs (under tables, roof undersides, wheel arches).
- No lightmaps.
- An alternative to the quads: the landscape track's ground shader could sample a baked shadow mask (no z-fighting at all). That is a request to that track, not an edit.

## 3. Distant landmarks, horizon cards, fog and depth precision

| Technique | How | Compatibility 4.7.2 status | Cost | Source | Verified? |
| --- | --- | --- | --- | --- | --- |
| Depth buffer format | — | **24-bit**: render targets `GL_DEPTH24_STENCIL8`; X11 context `GLX_DEPTH_SIZE 24` (16-bit only for a 4×4 dummy texture) | — | [texture_storage.cpp L2635](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/texture_storage.cpp#L2635), [gl_manager_x11.cpp L122](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/linuxbsd/x11/gl_manager_x11.cpp#L122) [src] | Yes |
| Reverse-Z | Godot flips Z (`set_depth_correction(flip_y, reverse_z=true, remap_z=false)`, `glDepthFunc(GL_GEQUAL)`) | Active, but GL keeps its −1…1 depth range (no remap, no clip control). With fixed-point depth, precision stays hyperbolic | — | [rasterizer_scene_gles3.cpp L1539, L2669](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp#L1539), [projection.cpp L787](https://github.com/godotengine/godot/blob/4.7.2-stable/core/math/projection.cpp#L787) [src]; precision consequence [calc] | Source: yes |
| Depth step Δz ≈ z²/(n·2²⁴), far 21 km | — | — | — | [calc] table below | Calc |
| Fog on landmarks | Standard exponential fog, density 3.912/visibility (L2) | Aerial perspective is a no-op; one fog for all objects | Free | [landscape 02](../landscape-investigations/02-atmosphere-aerial-perspective.md) | Yes (02) |
| Horizon card (silhouette quad) | One quad per landmark facing the fixed pilot; alpha scissor; atlas | Alpha scissor works; alpha-to-coverage and alpha hash are no-ops (landscape 04) | 1 draw per atlas | [landscape 04](../landscape-investigations/04-trees-and-impostors.md) | Yes (04) |
| Turbine rotor in a vertex shader | Blade vertices rotate about the hub pivot by `angle = 2π·f·sim_clock`; f a multiple of 1/1024 Hz | `float` global uniforms work (landscape 11) | 0 extra draws if merged with the tower | [landscape 11](../landscape-investigations/11-wind-animation-ambience.md); [Godot tree sway via vertex colour](https://docs.godotengine.org/en/stable/tutorials/shaders/making_trees.html) [snip] | Partly |

**Depth step (m) per 24-bit step** [calc], far = 21,000 m:

| near \ distance | 100 m | 400 m | 1 km | 2 km | 5 km | 20 km |
| --- | --- | --- | --- | --- | --- | --- |
| 0.1 m (today, `Spec.CAMERA`) | 0.006 | 0.095 | 0.60 | 2.4 | 14.9 | 238 |
| 0.5 m | 0.001 | 0.019 | 0.12 | 0.48 | 3.0 | 48 |
| 1.0 m | 0.0006 | 0.010 | 0.06 | 0.24 | 1.5 | 24 |

**Consequences** [calc and inference]:
- A turbine at 5 km has its rotor about 5–8 m in front of the tower: **less than one depth step at near 0.1 m**, so the blades and tower flicker where they cross.
- **Fixes, cheapest first:**
  1. Ask the visual track for a pilot-camera near of 0.5–1 m (the eye is 1.7 m above the ground; check the inspect camera).
  2. Because the pilot never moves, push far parts back along the view ray by ≥ 3 depth steps and scale them by the distance ratio. The angular size is unchanged; at 5 km, 45 m is a 0.9 % size change, invisible.
  3. Flat single-layer silhouettes, which can't z-fight internally.
- Writing `DEPTH` (log depth) disables early-Z: last resort.
- **Sub-pixel blades** [calc]: at 50° vertical FOV and 720 px (14.4 px/°), a 3 m wide blade at 5 km is 0.034°, about **0.5 px**. A 150 m tip height is about 25 px.
  - Geometry blades get MSAA edge AA (MSAA works in Compatibility); alpha-scissor card blades do not, and will shimmer.
  - Use geometry blades, widened to ≥ 1 px for their fixed distance (a labeled stylization).
  - Fog at 5 km with 23 km visibility: 1 − e^(−3.912·5/23) = 57 % [calc], so contrast is already low.
- **Speed:** a utility rotor turns at roughly 10–16 rpm [unverified, typical]. 14 rpm ≈ 239/1024 Hz.

## 4. Motion without `TIME`: flags, rotors, people

| Technique / tool | How | Compatibility 4.7.2 status | Cost | Source | Verified? |
| --- | --- | --- | --- | --- | --- |
| Flag / cloth wave | Sine shear growing along the flag's UV.x, phase from `sim_clock`, amplitude from `wind_vec` | Vertex shader | 0 extra draws if merged | [godotshaders 3D flag](https://godotshaders.com/?p=2821) [snip] (uses `TIME`; ideas only); landscape 11 for the L15c contract | Partly |
| Rigid-part "pivot" animation | Each rigid part stores its pivot (vertex colour, UV2 or CUSTOM0); the shader rotates the part around it (a head nodding, an arm waving, a cow grazing) | Vertex shader | 0 extra draws; mergeable | Concept: [UE Pivot Painter 2](https://dev.epicgames.com/documentation/unreal-engine/pivot-painter-tool-2.0-in-unreal-engine) [snip] | Concept |
| Vertex animation texture (VAT) | Positions and normals per frame in an RGBF texture; `texelFetch` by `VERTEX_ID` | Works; the godotshaders VAT shader says **no animation blending in Compatibility** (only 2 custom channels used); textures need lossless, no mipmaps, nearest filtering | 1 texture per clip; any number of instances in 1 MultiMesh draw | [VAT with instancing](https://godotshaders.com/shader/vertex-animation-with-instancing/) [sec] (MIT, uses `TIME` + `INSTANCE_ID`); [OpenVAT](https://extensions.blender.org/add-ons/openvat/) [snip] (Blender exporter, license not checked) | Partly |
| Per-instance phase in MultiMesh | `INSTANCE_CUSTOM.x` offsets the phase | Halfs (16-bit) | — | [fish tutorial 4.7](https://docs.godotengine.org/en/4.7/tutorials/performance/vertex_animation/animating_thousands_of_fish.html) [doc] (uses `TIME`; swap in `sim_clock`) | Yes |
| `Skeleton3D` skinning | CPU poses bones; GPU skins via **transform feedback** into per-instance vertex buffers | Works | +1 TF pass per surface per frame, a duplicate vertex buffer per instance, can't merge or MultiMesh, plus AnimationPlayer CPU time | [mesh_storage.cpp L1335](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/mesh_storage.cpp#L1335) [src] | Yes (mechanism); cost not measured |

**Recommendation:** SC-18 and SC-21 use rigid-part pivot animation first (fixed pilot view, figures 20–40 m away). Use VAT only if a gate wants real walk cycles. Use `Skeleton3D` only for ≤ 4 characters, measured.

## 5. Prior art: how RC and FPV sims populate fields

| Sim | Approach | What users and reviewers say | Source | Verified? |
| --- | --- | --- | --- | --- |
| Aerofly RC 10 | 22 sceneries: **8 "4D"** (3D, time of day, weather; includes **Muncie AMA Field**), 3 multi-panorama, 11 panorama | Marketing: wind-driven turbines, windsocks, flags, trees and leaves ("Virtual-Elements") | [Steam](https://store.steampowered.com/app/2394350/aerofly_RC_10__RC_Flight_Simulator/) [doc]; Virtual-Elements wording [snip] | List: yes |
| Aerofly RC 8 (review) | Same mix | "Photo-draped locales… can be breathtaking"; 3D scenes "often look dated" from "repetitive texturing and primitive tree and structure models"; photo scenes keep frame rates high; fixed viewpoint | [Tally Ho Corner](https://www.tallyhocorner.com/2021/02/aerofly-rc-8-review/) [sec] | Yes |
| Aerofly RC 8 panoramas | Invisible 3D collision behind photos | "I constantly crash into trees because they look to be far" (2024-04-01) | [Steam thread](https://steamcommunity.com/app/2394350/discussions/0/4354491868386005897/) [sec] | Yes |
| RealFlight Evolution | 3D fields and PhotoFields (Triple Tree as a PhotoField) | "Very dated graphics that look like they haven't changed in 15–20 years"; Aerofly RC8 "wins hands down" on graphics and VR (DX9 engine) | [Steam: price thread](https://steamcommunity.com/app/2069310/discussions/0/3469487093569690883/?ctp=2), [upgrade thread](https://steamcommunity.com/app/2069310/discussions/0/3728449142724092782/) [sec] | Yes |
| RealFlight (older forums) | Hybrid fields: photo backdrop plus 3D foreground objects; 3D fields with wind-moving leaves, breakable branches, knock-over objects | "Some of the really cool flying sites are just too distracting when they're as sharply focused as possible"; 3D backdrops "look shockingly bad and no one ever uses them" | RCUniverse threads ([G4.5](https://www.rcuniverse.com/forum/rc-flight-simulator-software-138/8130233-how-does-everyone-like-realflight-g4-5-a-3.html), [blurred scenery](https://www.rcuniverse.com/forum/rc-flight-simulator-software-138/9035431-realflight-g4-5-blurred-scenery-windows-7-a.html), [HUD](https://www.rcuniverse.com/forum/rc-jets-120/11617832-worlds-first-hud-rc-pilot.html)) [snip]: HTTP 403 | **No** |
| Custom RealFlight club field | A club rebuilt in 3D: tents, seating, fence, runway | "Most objects are represented by 3D models" (the gear can clip the fence) | [xinhaidude 2016](https://xinhaidude.com/2016/08/07/custom-realflight-airfields-bethpage-rc-model-airplane-field/) [sec] | Yes |
| ClearView | Equirectangular 2:1 panoramas (8160×4080) plus AC3D fly-behind objects with collision | — | [rcflightsim.com](https://rcflightsim.com/sceneries.html) [doc] | Yes |
| PicaSim (open) | Panoramas (fixed viewpoint) and 3D scenes; depth-only terrain | Developer: panoramic slope sites are "very hard" because the collision and wind terrain must match | [landscape research §3](../landscape-research.md); [forum](https://www.tapatalk.com/groups/picasim/viewtopic.php?p=902) [snip]: 403 | Partly |
| CRRCSim, Phoenix RC, neXt | 3D + XML population tag (CRRCSim); cube map + collision primitives (Phoenix); panorama + multi-panorama (neXt) | — | [landscape research §3](../landscape-research.md); neXt panorama list [snip] | Partly |
| VelociDrone | Many simple 3D sceneries, community track editor | Praised for physics and editor; graphics "basic and dated" but run on low-spec hardware | [velocidrone.com](https://www.velocidrone.com/) [doc]; low-spec claim [snip] | Partly |
| Liftoff / Uncrashed / DRL | Hand-built 3D maps (Unity for Liftoff); Uncrashed: "parks to abandoned places" plus an environment editor | Liftoff 95 % positive (7,108 reviews); Uncrashed 94 % | [Liftoff Steam](https://store.steampowered.com/app/410340/Liftoff_FPV_Drone_Racing/), [Uncrashed Steam](https://store.steampowered.com/app/1682970/Uncrashed__FPV_Drone_Simulator/) [doc]; engines [snip] | Partly |

### Design lessons from other RC sims

1. **Photo fields win on looks and frame rate, but lose on depth and collisions.** Our 3D field must avoid the "dated" signature named in reviews (repeated textures, primitive trees), not chase photorealism. A coherent low-poly family with one palette fits.
2. **Collision must match what is seen.** Aerofly's invisible-tree crashes are the top panorama complaint. Rule 3 (`collides=false` until L14) avoids that. When collisions come, they come from the same prefab geometry.
3. **Motion sells "alive".** Aerofly's marketing headline is wind-driven windsocks, flags, turbines and trees, not more objects. SC-18 matters more than prop count.
4. **Busy, sharp backgrounds hurt the airplane** [snip, unverified]. This matches the L6c measurements and our rule 2: calm in front, colour behind.
5. **Club realism comes from known pieces.** A real club rebuilt in RealFlight shows tents, seating, fence and runway; Aerofly ships a real AMA club field. People and parked aircraft are rarely mentioned in reviews (nothing found): low priority after shelters, cars and fences.
6. **Frame rate is a feature.** FPV racers prefer simple-looking sims that run fast. Keep the ≤ 40 draw budget and quality tiers (SC-24).
7. **Community and authoring.** Club-field sharing recurs (RealFlight, ClearView, VelociDrone). Our JSON placement format is a good base for "rebuild your own club" (parking lot idea).

## 6. Placement and authoring plugins

| Tool | What | License, 4.x status | Bake to static data? | Source | Verified? |
| --- | --- | --- | --- | --- | --- |
| ProtonScatter | Modifier-stack scatter (box/sphere/path shapes); outputs MultiMesh, copies or particles | MIT; Godot 4 rewrite; pushed 2026-09-27; last tagged release 4.0 (2023) | Partly: `ProtonScatterCache` saves transforms to a `.res`; `show_output_in_tree` writes nodes. Placement uses Godot RNG + `global_seed` (float32, not our integer hash). The plugin is needed to rebuild | [repo](https://github.com/HungryProton/scatter), [scatter_cache.gd](https://github.com/HungryProton/scatter/blob/main/addons/proton_scatter/src/cache/scatter_cache.gd), [scatter.gd](https://github.com/HungryProton/scatter/blob/main/addons/proton_scatter/src/scatter.gd) [src] | Yes |
| Spatial Gardener | Brush-paints plants and props on any surface (octree) | MIT; v1.4.1 (2025-03-05), "requires at least Godot 4.2" | Data stays in its own octree resources and nodes; runtime needs its scripts [inference] | [repo](https://github.com/dreadpon/godot_spatial_gardener) [doc] | License and version: yes |
| Terrain3D instancer | MultiMesh per 32 m cell per mesh; up to 10 LODs; shadow impostor | MIT; GDExtension (C++); v1.0.2 (2026-05-19); Compatibility "fully supported since Terrain3D 1.0 and Godot 4.4"; web "very experimental" | No: transforms live in its region files; needs the extension at runtime; no per-instance culling | [instancer](https://terrain3d.readthedocs.io/en/stable/docs/instancer.html), [platforms.md](https://github.com/TokisanGames/Terrain3D/blob/main/doc/docs/platforms.md) [doc] | Yes |
| Godot Road Generator | Spline roads with lanes; runtime API | MIT; 0.9.4 (2026-10-01) | Yes: "Export RoadContainers to glTF/glb" | [repo README](https://github.com/TheDuckCow/godot-road-generator) [doc] | Yes |

**Verdict:**
- None is needed. The plan's `tools/scenery/place.py` (integer hash, committed positions) meets the rule better than any plugin.
- Road Generator is the one worth a try for SC-06's dirt road: author it once, export a GLB, commit it with provenance.
- ProtonScatter is useful only as an ideas reference (shape stacks, edge placement).

## Consequences for SC steps

| Step | Consequence |
| --- | --- |
| SC-01c probe | Measure: (1) `ImporterMesh.merge_importer_meshes` vs `SurfaceTool.append_from` build time for one zone (budget ≤ 150 ms); (2) draws for the merged zone, expected 1 per material; (3) a turbine at 5 km with near 0.1 vs 0.5 m: flicker in a 2-frame diff; (4) the fogged alpha-blend shadow vs ground at 400 m |
| SC-04 pipeline | `adapt.mjs`: glTF Transform 4.5.0 `flatten` → `palette` (non-Kenney sources) → `join`; check that every vertex has a colour (avoid the black-default trap); refuse negative scales or merge with `ImporterMesh` (winding fix). Palette sampled at cell centres, mips capped |
| SC-05 grounding | Alpha-blend footprints (not `blend_mul`), lift ∝ d², 1 draw per zone; AO in vertex colours; no LightmapGI; offer a shadow-mask option to the landscape track |
| SC-09 parked fleet | Collect `MeshInstance3D` surfaces from the model builders and merge per material with `ImporterMesh.merge_importer_meshes` (`dedupe` by surface name). Normals are only right for uniform scale: check the builders for non-uniform scales before claiming IoU ≥ 0.98 |
| SC-15 landmarks | Geometry silhouettes, not alpha cards, for anything thin or moving. Request a pilot-camera near ≥ 0.5 m (visual track, owner decides), or separate parts along the view ray by ≥ 3 depth steps. Widen blades to ≥ 1 px. Fog from the engine only |
| SC-18 motion | Rotors and flags in vertex shaders from `sim_clock`/`wind_vec`; pivots stored per vertex; frequencies multiples of 1/1024 Hz |
| SC-21 people | Rigid-part pivot animation first; `Skeleton3D` only measured, ≤ 4 figures |
| SC-24 tiers | Tiers pick prefab subsets inside the merged zone meshes, so a tier change rebuilds the zone mesh at load (deterministic), not per frame |

## Not verified

- RCUniverse quotes (distracting sharp sites, hybrid photo+3D fields, "3D backdrops look shockingly bad"): HTTP 403, search snippets only.
- PicaSim developer quote on panorama terrain: HTTP 403.
- Aerofly "Virtual-Elements" feature list: wording from snippets (the Steam page lists the 4D sceneries only).
- KayKit single 1024² gradient atlas; Uncrashed engine (Unreal); VelociDrone runs on low-spec hardware.
- Cost of `Skeleton3D` in frame time, the actual flicker at 5 km, and the sRGB-blend error of fogged shadow quads: computed or inferred, not measured.
- Typical wind-turbine rotor speed (10–16 rpm) and dimensions.
- Whether Blender Cycles AO bakes repeat byte for byte with a fixed seed.

## Sources

**Godot 4.7.2-stable source** (read):
- [rasterizer_scene_gles3.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp)
- [scene.glsl](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl)
- [texture_storage.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/texture_storage.cpp)
- [mesh_storage.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/mesh_storage.cpp)
- [material_storage.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/material_storage.cpp)
- [projection.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/core/math/projection.cpp)
- [gl_manager_x11.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/linuxbsd/x11/gl_manager_x11.cpp)
- [surface_tool.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/surface_tool.cpp)
- [importer_mesh.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/3d/importer_mesh.cpp)
- [register_scene_types.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/register_scene_types.cpp)
- Class refs: [SurfaceTool](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/SurfaceTool.xml), [ImporterMesh](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/ImporterMesh.xml), [MeshInstance3D](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/MeshInstance3D.xml), [LightmapGI](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/LightmapGI.xml)

**Godot docs and news:**
- [GPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html)
- [MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)
- [Animating thousands of fish](https://docs.godotengine.org/en/4.7/tutorials/performance/vertex_animation/animating_thousands_of_fish.html)
- [4.8 dev 4](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-4/)

**Tools:**
- [glTF Transform palette](https://gltf-transform.dev/modules/functions/functions/palette), [join](https://gltf-transform.dev/modules/functions/functions/join), [4.5.0 typings](https://unpkg.com/@gltf-transform/functions@4.5.0/dist/index.d.ts)
- [Blender baking](https://docs.blender.org/manual/en/latest/render/cycles/baking.html)
- [Kenney Car Kit](https://kenney.nl/assets/car-kit) (CC0; zip inspected in scratch)
- [Kenney import guide](https://kenney.nl/knowledge-base/game-assets-3d/importing-3d-models-into-game-engines)
- [Papaya Games palette devlog](https://papaya-games.itch.io/duck-in-town/devlog/73530/blazing-fast-rendering-with-a-single-material-per-scene)
- [VAT with instancing](https://godotshaders.com/shader/vertex-animation-with-instancing/)
- [UE Pivot Painter 2](https://dev.epicgames.com/documentation/unreal-engine/pivot-painter-tool-2.0-in-unreal-engine)

**Plugins:**
- [ProtonScatter](https://github.com/HungryProton/scatter)
- [Spatial Gardener](https://github.com/dreadpon/godot_spatial_gardener)
- [Terrain3D](https://github.com/TokisanGames/Terrain3D), its [instancer doc](https://terrain3d.readthedocs.io/en/stable/docs/instancer.html)
- [Godot Road Generator](https://github.com/TheDuckCow/godot-road-generator)
- [Static Mesh Merger](https://godotengine.org/asset-library/asset/5429)
- [Merging Meshes Godot](https://godotengine.org/asset-library/asset/4538)

**Prior art:** links in §5, and [landscape research §3](../landscape-research.md).

**Reproduce the Kenney measurement:**
1. Download `kenney_car-kit.zip` from the kit page into an empty scratch folder.
2. Parse each GLB's JSON chunk (bytes 20…20+len) and count `materials`, `images[].uri` and triangles (`indices.count/3`).
3. Count colours in `colormap.png` (Pillow `getcolors`).
