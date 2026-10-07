# 02 · Vegetation: card shading, grounding, near LODs, colour, grass, wind, far forest

Date: 2026-10-07. Status: research only; no `app/` change. Input: [05 · landscape image review](../scenery-investigations/05-landscape-image-review.md) (finding 3, the card seam; finding 4, no ground contact; finding 9, red-brown trunks), `app/render/treeline.gd`, `treeline.gdshader`, `tree_identity.gdshaderinc`, `tree_assets.gd`, [LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md) (L6b, L7, L8, L11a/b, L15b/c), [tree resource review](../tree-resource-review-2026-10-06/README.md), [04 · trees and impostors](../landscape-investigations/04-trees-and-impostors.md).

Evidence tags: **[src]** read in the Godot 4.7.2-stable source; **[doc]** official documentation; **[measured]** measured here (scratch project or files); **[computed]** our arithmetic; **[sec]** secondary source; **[inference]**; **[unverified]**.

## Summary: recommendations, in order

1. **Fix a winding bug first (one line).** `tree_assets.card_mesh()` winds each quad counter-clockwise as seen from +Z, but gives it the normal +Z. Godot treats **clockwise** triangles as front faces [doc], and with `cull_disabled` it flips the normal on back faces (`DO_SIDE_CHECK`, `scene.glsl` L2243) [src]. So the face the viewer sees always gets a normal that points **away** from the viewer. Trees with the sun behind the pilot render dark, and trees against the sun render bright. A/B [measured]: the mean crown luminance was 10.7 (front-lit) vs 35.6 (backlit) in sRGB levels. With the winding fixed it is 40.2 vs 5.5. Fix: reverse the index order, or negate the normals.
2. **Remove the seam with a screen-space crown normal, written in `fragment()`.** The seam comes from the three crossed planes. Left of the axis, one plane's near wing covers the crown; right of it, another plane's wing does, and each is lit by its own plane normal. Instead, give every pixel the normal of an ellipsoid around the crown centre, taken in the **view plane**. Both cards then get the same normal at the same pixel, so the seam is gone by construction. The normal must be written in `fragment()`: user fragment code runs after Godot's back-face flip (L2303 vs L2243) [src]. A/B at 300 m, 6° FOV, four headings [measured]: the largest step between adjacent column means inside a crown fell from **47–79 levels** to **2.6–4.3**. Cost: 0 draws, 0 triangles, about 15 ALU per fragment.
3. **Add soft fill: `BACKLIGHT` ≈ 0.4 × albedo, a sky lean of the normal (`up_bias` ≈ 0.5), and a bounded underside (`q.y ≥ −0.5`).** All three work in Compatibility [src]. Avoid `diffuse_lambert_wrap` with roughness 1: Godot's energy-conserving wrap halves the lit side's peak, to 1/(1+w) [src].
4. **Do not bake the lighting into the atlas and render unlit.** Each tree has its own yaw from the hash, so baked light would point a different way on every tree. Phase 2, optional: bake a **view-space normal atlas** (RG8, 1024²) for leaf-cluster detail on top of the crown normal.
5. **Grounding, ranked by what the pilot actually sees.** A 5 m ground blob at 300 m covers only **0.15 px** vertically at 50° FOV and 1.3 px at 6° zoom [computed]. From the pilot's eye, the **vertical** cues carry the contact:
   - (a) darken the trunk base in the card shader (×0.65 at the base, back to ×1 at 25 % of the height);
   - (b) an **undergrowth skirt** baked into the atlas's **empty fourth tile** (512–1024, 512–1024: alpha max 0 [measured]), 2–3 low quads per tree in the same mesh: 0 extra draws;
   - (c) for raised views only, a baked canopy-AO/rough-grass mask sampled by the ground shader: 0 draws.
6. **Colour.** The atlas leaves are fully saturated (CommonTree_1 mean sRGB 88,123,0, S = 1.00) and the bark is a bright red-brown (138,88,67, hue 18°, V 0.54) [measured]. Grade them in the shader, not in the atlas: leaves to about sRGB (70–90, 95–115, 40–60), bark to about (90,80,68). Add a ±10 % per-tree tint from a second hash step.
7. **L8 near LODs are not a priority:** the nearest committed tree stands at **272 m** (31 trees < 300 m, 152 < 400 m) [measured], so no tree is within L8's ~150 m.
   - Automatic decimation of the chosen Quaternius deciduous trees **cannot reach ≤ 1k triangles**. gltfpack 1.3 `-si 0.15 -sa -sp` stops at **2,336** (CommonTree_1) and **1,496** (CommonTree_3), because the leaves are disconnected clusters. Pine_1 reaches 806 [measured].
   - When a near tree is needed, build a crown hull plus leaf cards, or use the Kenney Nature Kit (CC0, **50–402 triangles** [measured]).
8. **Grass (L11a/b):** keep the DIY opaque blade clumps measured in [05](../landscape-investigations/05-grass-rendering.md). Every Godot grass add-on checked reads `TIME` or targets Forward+. Reuse the scenery track's SC-16 flower cushions (~21 triangles) for L11b instead of a second flower system.
9. **Wind (L15b/c):** Crysis main bending, which preserves length, driven by `sim_clock` and `wind_vec`, at frequencies rounded to k/1024 Hz (the `sim_clock` wrap). The per-tree phase comes from the existing hash. Cards get main bending only.
10. **Far forest (L7):** first, put **forest patches** (dense card clusters, 600–1,500 m) into the **same 8 sector MultiMeshes**: 0 extra draws, 6 triangles per tree. Two catches:
    - the quarter-metre packing reaches only **−600 m** south and west (`qn = 4n + 2400 ≥ 0`) [computed], so the offset must grow, and the hash must keep its own constant so today's identities stay the same;
    - use alpha-to-mip scaling so far cards do not thin out.

## 1. The card seam: cause, fix, alternatives

**What we measured.** A scratch Godot 4.7.2 Compatibility project (outside the repo) uses the atlas, the identity include and the production shader unchanged. It has a gradient sky as ambient source, ACES at 0.6 and a sun at azimuth 225°, elevation 45°. Five trees stand at 300–312 m in each of four headings; the frames are 640×360 at 6° FOV, rendered with llvmpipe and `LP_NUM_THREADS=1`. Metric: the column-mean luminance of the upper half of each tree; the largest step between adjacent columns inside the crown.

| Variant | Largest column step (4 headings) | Front-lit / backlit crown luma | Notes |
| --- | --- | --- | --- |
| A: production shader | 47.5–79.2 | 10.7 / 35.6 (inverted) | the seam and the winding bug |
| F: A with flipped normals | 18.5–58.8 | 40.2 / 5.5 | correct light direction, seam remains |
| B: screen-space crown normal | 3.6–7.3 | — | trunks black (underside normal) |
| **C: B + up_bias 0.5, BACKLIGHT 0.4, underside clamp 0.5, base AO 0.35** | **2.6–4.3** | 62.0 / 25.8 | recommended starting point |
| D: C + colour grade (leaf sat 0.6, gain 0.67; bark luma × 0.65 × (1.22,0.96,0.70)) | 1.6–1.9 | 29.2 / 9.1 | gain too low under this test sky; tune against the real grass |

This proves that the seam goes away in this renderer and setup. It does not prove the final look: the production sky radiance, fog and L6c readability must be re-measured with the real app.

**The fix, as drafted (variant C).** The species constants come from the atlas: the crown centre height, half-width and half-height as fractions of tree height [measured]:

| Species | Crown centre | Half-width | Half-height | Crown bottom |
| --- | --- | --- | --- | --- |
| CommonTree_1 | 0.71 | 0.26 | 0.29 | 0.42 |
| CommonTree_3 | 0.67 | 0.20 | 0.34 | 0.33 |
| Pine_1 | 0.63 | 0.34 | 0.34 | 0.35 |

```glsl
// vertex(), after the existing yaw and scale (model space, tree height ≈ identity.y):
crown_view   = (MODELVIEW_MATRIX * vec4(0.0, crown.x * identity.y, 0.0, 1.0)).xyz;
crown_radius = crown.yz * identity.y;
up_view      = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
height_frac  = VERTEX_Y_BEFORE_SCALE;              // 0 at the base, about 1 at the top
// fragment(): written AFTER Godot's back-face flip, so both sides and all three cards agree.
vec2 q = (VERTEX.xy - crown_view.xy) / crown_radius;
q /= max(1.0, length(q));
q.y = max(q.y, -0.5);                               // the underside and trunk keep some sky
NORMAL = normalize(vec3(q, sqrt(max(0.0, 1.0 - dot(q, q)))) + 0.5 * up_view);
ALBEDO *= mix(0.65, 1.0, smoothstep(0.0, 0.25, height_frac));   // trunk-base contact darkening
BACKLIGHT = 0.4 * ALBEDO;                           // leaf translucency (LIGHT_BACKLIGHT_USED in GLES3)
```

With L15b bending, compute `crown_view` from the bent position.

| Technique | How | Cost | Compatibility 4.7.2 | Source | Verified? |
| --- | --- | --- | --- | --- | --- |
| **Screen-space ellipsoid normal** (sphere-impostor normal from the crown centre) | above | ~15 ALU/fragment, 2 varyings | works; fragment `NORMAL` overrides the side flip | our design; same idea as foliage "spherified" normals | measured (A/B above) |
| Mesh-space spherical normals (normals from the crown centre, set per vertex) | Blender Data Transfer from a hull, "Spherify Normals", Airborn's "bubble" transfer | 0 runtime | works for meshes. For crossed cards it still flips on back faces, and the 4 corner normals of a quad don't follow the crown | [Simon Schreibt, Airborn trees](https://simonschreibt.de/?p=45); [Foliage Normals add-on](https://superhivemarket.com/products/foliage-normals) | verified (articles) |
| Winding fix | reverse the indices or negate the normals in `card_mesh` | 0 | — | [ArrayMesh docs](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/arraymesh.html): "Godot renders in a clockwise direction" | verified [doc], measured |
| `BACKLIGHT` (translucency) | `diffuse += light·(1/π − diffuse_NL)·backlight` | ~3 ALU | implemented (`LIGHT_BACKLIGHT_USED`) | `scene.glsl` L1655 | verified [src] |
| `diffuse_lambert_wrap` | `(N·L + r)/(1 + r)²`, with r = ROUGHNESS | 0 | implemented; peak 1/(1+r) | `scene.glsl` L1635 | verified [src] |
| Custom `light()` | e.g. Crysis back-face term `−N·L·0.6 + 0.4` | small | implemented (`LIGHT_CODE_USED`) | `scene.glsl` L1575; [GPU Gems 3 ch. 16](https://developer.nvidia.com/gpugems/gpugems3/part-iii-rendering/chapter-16-vegetation-procedural-animation-and-shading-crysis) | verified [src], [doc] |
| Baked light, unlit | light painted into the atlas | 0 | works | rejected: per-instance yaw, and a sun change would need a rebake | inference |
| Baked normal atlas (SpeedTree/impostor style) | a second atlas with normals; billboards lit dynamically | +1 sampler, ~1.4 MB | works (mipmapped) | [SpeedTree LOD](https://docs.unity3d.com/speedtree-runtime-sdk/manual/level-of-detail.html): "billboards have no pre-baked lighting"; [godot-imposter](https://github.com/zhangjt93/godot-imposter) bakes normal/depth/ORM | verified [doc]; phase 2 |
| Octahedral impostors | 16×16-view atlas | high texture cost | godot-imposter 4.5.beta5 only, `textureLod(…, 0)`: no mips | [04](../landscape-investigations/04-trees-and-impostors.md); MIT, last push 2025-08-15 | verified (repo); overkill for a fixed pilot |

X-Plane does the same for its trees: the 2D trees are double-sided and alpha-tested at 0.5, and the 3D trees use a translucency channel (normal-map blue) [doc: [forest spec](https://developer.x-plane.com/article/forest-for-file-format-specification), [custom 3D trees](https://developer.x-plane.com/article/building-custom-3-d-trees/)].

## 2. Grounding the trees

Pixel math [computed]: the screen height of a flat ground patch of radius R at distance d, eye height h, is ≈ f·h·2R/d², with f = 772 px/rad at 50° and 6,870 px/rad at 6°.

| Patch | Pilot 1.7 m, 50° | Pilot, 6° zoom | Camera 30 m up, 50° |
| --- | --- | --- | --- |
| R = 5 m at 300 m | 0.15 px | 1.3 px | 2.6 px |
| 2 m tall shrub at 300 m (vertical) | 5.1 px | 46 px | — |

| Technique | How | Cost | Compatibility | License | Source | Verified? |
| --- | --- | --- | --- | --- | --- | --- |
| **Trunk-base darkening** | multiply the albedo by 0.65 → 1 over the bottom 25 % of the height (also models the shade under the crown) | 0 | works | ours | scratch A/B (visual) | measured (visual only) |
| **Undergrowth skirt in atlas tile 4** | bake brambles, shrubs and tall grass (1.5–3 m × 4–8 m) into the empty tile; add 2 crossed low quads per tree to the card mesh, or as separate instances between trees | +6 triangles per tree, 0 draws (same surface) | works (alpha scissor) | CC0 bake sources: Kenney `plant_bush*` (16–104 triangles) | [Kenney Nature Kit](https://kenney.nl/assets/nature-kit) | measured (tile empty, counts) |
| **Ground mask in the ground shader** | an offline 1–2 k² texture over the treeline area (~0.6 m/px). R = canopy AO, G = unmown/rough tint, sampled once | 1 sampler, 0 draws | works | ours | CryEngine "Terrain Ambient Occlusion": "a dense forest has less ambient light near the ground" | verified [doc] ([CryEngine 3](https://www.cryengine.com/docs/static/engines/cryengine-3/categories/1114113/pages/1048830)) |
| Multiply-blend footprint quads | `render_mode blend_mul, unshaded, depth_draw_never`: order-independent, so it is safe in unsorted MultiMeshes | +1 draw per group | `BLEND_MODE_MUL` → `GL_DST_COLOR, GL_ZERO` | ours | `rasterizer_scene_gles3.cpp` L3431 | verified [src]. Risk: coplanar with the two-triangle ground until G-1; fade with the fog |
| Alpha-blend contact quads (scenery SC-05) | footprint along the fixed sun, lifted 2 cm | ≤ 1 draw per cell | measured clean by the scenery track | ours | [SCENERY-PLAN SC-05](../../SCENERY-PLAN.md) | measured by the scenery track |
| Root flare | already in the Quaternius trunks | — | — | — | atlas | — |
| SSAO | engine SSAO (Compatibility since 4.6, per [03](03-terrain-sky-lighting.md)) | full-screen pass | available | — | — | not verified here; negligible at 270+ m |

## 3. Near-tree LODs (L8) and impostor tools

| Resource | Triangles (measured) | Surfaces | License | Fit | Verified? |
| --- | --- | --- | --- | --- | --- |
| Quaternius CommonTree_1 / _3 / Pine_1 (our sources) | 6,265 / 3,505 / 3,947 | 2 | CC0 (exact Standard archive) | source only | [validation.json](../../../assets/landscape/trees/validation.json) |
| Same, gltfpack 1.3 `-si 0.16 -noq` | 2,942 / 2,313 / 1,230 | 2 | — | above budget | measured |
| Same, `-si 0.15 -sa -sp` | 2,336 / 1,496 / **806** | 2 | — | only Pine_1 fits ≤ 1k | measured |
| Kenney Nature Kit (zip SHA-256 `fa7974a0…4d9d`, License.txt "Nature Kit (2.1)", CC0) | tree_default 114, tree_oak 196, tree_detailed 402, tree_pineDefaultA 230, tree_fat 50 (1.15–1.71 m tall) | 2–3 | CC0 | toy-like; good as bush and undergrowth sources | measured |
| KayKit Forest Nature | 530, 336, 978, 404 | 1 | CC0 (downloaded archive) | stylized | [tree review](../tree-resource-review-2026-10-06/README.md) |
| Poly Pizza | — | — | mixed CC0 / CC-BY per model (secondary sources) | check each file | unverified (license page 404) |
| ez-tree v1.1.0 | Oak Large 22,566; LODs from one skeleton | — | MIT (code); leaf texture provenance open | offline only | [ez-tree](https://github.com/dgreenheck/ez-tree), last push 2026-07-16 |
| gdTree3D | — | — | MIT (LICENSE file; the API reports NOASSERTION) | editor-only GDExtension | [repo](https://github.com/JekSun97/gdTree3D), push 2026-10-06 |
| meshoptimizer / gltfpack | — | — | MIT, v1.3 (2026-09-25) | offline decimation (`-si`, `-sa`, `-sp`, `-noq` verified in the source) | [repo](https://github.com/zeux/meshoptimizer) |

Recommended L8 recipe (when a near tree exists, e.g. a scenery hedgerow tree or a chase view):
- a crown hull (~150–300 triangles, spherified normals, opaque) plus 12–24 leaf cards cut from the same atlas (alpha scissor), with the trunk from the source decimated to ≤ 200 triangles;
- or Pine_1 at 806 triangles as is.

## 4. Colour targets

Leaf reflectance is ~5 % at 400 nm, a ~15 % peak at 550 nm and 5–6 % at 675 nm [sec, Purdue LARS LTR 071380 via search excerpt]. Bark rises monotonically from blue to red, and most species are alike in the visible except white birch ([Juola et al. 2022, PMC8928865](https://pmc.ncbi.nlm.nih.gov/articles/PMC8928865/)) [doc]. Broadband canopy albedo: summer foliage 0.09–0.12, conifer forest 0.08–0.12 ([Studio 397 table](https://docs.studio-397.com/x/EgBDAg)) [sec; includes near-infrared, so the visible value is lower].

| Item | Now (atlas mean, sRGB) [measured] | Target albedo (sRGB) [computed from the spectra] | Shader grade |
| --- | --- | --- | --- |
| Deciduous leaves | 88,123,0 (H 77°, S 1.00, V 0.48) | 70–90, 95–115, 40–60 (H ≈ 85–100°, S 0.4–0.5) | `mix(luma, c, 0.6) × 0.67` gives ≈ 81,98,58 |
| Pine needles | 50,88,0 (S 1.00, V 0.34) | 45–60, 65–80, 40–50 | same grade |
| Bark | 138,88,67 (H 18°, S 0.51, V 0.54) | ≈ 90,80,68 (H ≈ 30°, S ≈ 0.25, V ≈ 0.35); linear ≈ 0.10, 0.08, 0.058 | `luma × 0.65 × (1.22, 0.96, 0.70)` for pixels where `r > g` |
| Scenery palette, for alignment | trunk `#5d4532`, leaf `#4b7833` | share one trunk value with scenery | — |
| Per-tree variation | none | ±10 % R, ±6 % G, ∓8 % B | second LCG step of `tree_hash` (h % 3 and h % 1024 are already used) |

Seasons: FlightGear keeps 4–8 varieties × 4 seasons in the atlas ([wiki](https://wiki.flightgear.org/Random_Vegetation)) [doc]. For us, a season is a uniform grade (autumn: hue toward 40–60°, more saturation), not new art. Gate: re-run L6c, because darker, greyer trees change the airplane's contrast.

## 5. Grass and flowers near the pilot (L11a/L11b)

| Project | License | Last push | `TIME` | Renderer | Fit | Verified? |
| --- | --- | --- | --- | --- | --- | --- |
| [SimpleGrassTextured](https://github.com/IcterusGames/SimpleGrassTextured) | MIT | 2026-09-17 | **yes** (`sin(TIME + rand)`, `grass.gdshaderinc` L106–110) | Compatibility unknown | idea only (global wind uniforms) | verified (clone 88ff153) |
| [Spatial Gardener](https://github.com/dreadpon/godot_spatial_gardener) | MIT | 2025-03-05 | none found | editor painter | not needed: placement is committed | verified (clone) |
| [ProtonScatter](https://github.com/HungryProton/scatter) | MIT | 2026-09-27 | demo shaders yes | — | not needed | verified (clone) |
| [GodotGrass](https://github.com/2Retr0/GodotGrass) | MIT | 2024-08-16 | yes | no renderer set → Forward+ | ideas: wider blades with distance, edge-on thickening | verified (clone) |

Measured before ([05](../landscape-investigations/05-grass-rendering.md)): 12k opaque 7-blade clumps add +67.7k primitives and **1 draw**, byte-repeatable. Blades are visible to ~15 m and clumps to ~30 m. L11b: reuse the scenery track's opaque flower cushions (`app/scenery/flowers.gd`, ~21 triangles, colour in `INSTANCE_CUSTOM`). Kenney bushes (16–104 triangles, CC0) cover the rest.

## 6. Wind without `TIME` (L15b/c)

| Technique | How | Cost | Source | Verified? |
| --- | --- | --- | --- | --- |
| Main bending (Crysis) | `bf = h·k + 1; bf *= bf; bf = bf·bf − bf; p.xz += wind.xz·bf; p = normalize(p)·len` (length preserved) | ~10 ALU per vertex | [GPU Gems 3 ch. 16](https://developer.nvidia.com/gpugems/gpugems3/part-iii-rendering/chapter-16-vegetation-procedural-animation-and-shading-crysis) | verified [doc] |
| Detail bending | vertex colours: R edge stiffness, G phase, B leaf stiffness; smoothed triangle waves at 1.975, 0.793, 0.375 and 0.193 Hz | meshes only | same | verified [doc] |
| `sim_clock` quantisation | round every frequency to k/1024 Hz: 2022/1024, 812/1024, 384/1024, 198/1024 | 0 | `app/render/shader_clock.gd` (wrap 1024 s) | computed |
| Per-tree phase | `float(tree_hash) / 65521.0`; frequency 0.2–0.5 Hz by height (estimate, [11](../landscape-investigations/11-wind-animation-ambience.md)) | 0 | ours | inference |
| X-Plane weights | `w_stiffness`, `w_edge_stiffness`, `w_phase` vertex weights | meshes only | [X-Plane 3D trees](https://developer.x-plane.com/article/building-custom-3-d-trees/) | verified [doc] |
| Pivot Painter 2 | pivots and hierarchy in textures, up to 4 levels | +1 UV set and textures | [Unreal docs](https://dev.epicgames.com/documentation/unreal-engine/pivot-painter-tool-2.0-in-unreal-engine) | verified [doc]; overkill |

Cards: main bending only (the top vertices shear; the crown normal centre follows them), tip amplitude ≤ 0.3 m at 10 m/s (estimate, [11](../landscape-investigations/11-wind-animation-ambience.md)).

## 7. Distant forest as a mass (L7)

| Technique | How | Cost | Compatibility | Source | Verified? |
| --- | --- | --- | --- | --- | --- |
| **Forest patches in the existing sector MultiMeshes** | 1,000–2,000 more card positions in clusters of 20–200, 600–1,500 m | 0 draws, +6 triangles per tree | works. The packing offset must grow (today `n ≥ −600 m`); keep the hash constant so existing identities stay the same | ours | computed |
| Alpha-to-mip scaling | raise alpha by mip level (`dFdx` → level) so far cards keep coverage | ~6 ALU | `dFdx`/`fwidth` work in GLES3 | [Golus, A2C article](https://medium.com/@bgolus/anti-aliased-alpha-test-the-esoteric-alpha-to-coverage-8b177335ae4f) | verified (article, in 04) |
| Silhouette strip ring | one ring mesh with an alpha-scissor forest-edge strip (a dense row of the 3 species), noise-varied height, gaps | 1 draw, ~720 triangles | works | [04](../landscape-investigations/04-trees-and-impostors.md), [03](03-terrain-sky-lighting.md) | inference; beyond ~1.5 km, with the hills |
| Volumetric textures | slices of a 3D texture over aperiodic tiles | high | 3D textures exist; too complex | [Decaudin & Neyret 2004](https://evasion.inrialpes.fr/Publications/2004/DN04) | verified [doc]; not recommended |
| Reading as a mass | darker, cooler base row; lighter crown tops toward the sun; let fog do the aerial perspective | 0 | — | inference | — |

Pixel math [computed]: a 15 m tree at 1,000 m is 11.6 px tall at 50° and 103 px at 6° zoom. Card detail (512 px tiles) is therefore still needed at zoom, and a strip texture would repeat about 26 times around the ring.

## Not verified

- The look under the production sky radiance, fog and ACES: the A/B used a simplified gradient sky. Re-capture with `app/capture.sh`, L6c and the golden captures (all tree pixels will change).
- Poly Pizza's license terms; the Kenney page says v1.0 while its License.txt says "Nature Kit (2.1)".
- The leaf reflectance numbers come from a search excerpt (Purdue LARS), not a read paper; the bark values are qualitative.
- SimpleGrassTextured and Spatial Gardener in Compatibility (not run).
- Whether the leaf-card-plus-hull L8 recipe holds IoU ≥ 0.9 against the card (L8 proof).

## Reproduce (scratch, not in the repo)

The scratch project holds a copy of the atlas and `tree_identity.gdshaderinc`, plus `main.gd`, which builds the card mesh exactly like `tree_assets.card_mesh()`. The shaders sit beside it: `a_current`, `a_flip`, `b_crown` and `d_graded`.

`LP_NUM_THREADS=1 xvfb-run -a <godot> --path <scratch> --rendering-driver opengl3 --resolution 640x360 --script res://main.gd -- --shader=<file> --az=<0|90|180|270> --fov=6 --uniforms=up_bias=0.5,back_light=0.4,trunk_floor=0.5,base_ao=0.35 --out=<png>`

Seam metric: per tree, the column mean of the upper half of the non-sky pixels; the largest step between adjacent columns that are ≥ 60 % of the tree's width.

## Sources

- Godot 4.7.2-stable source: [scene.glsl](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl), [material_storage.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/material_storage.cpp) (`cull_disabled` → `DO_SIDE_CHECK`, `BACKLIGHT`, `diffuse_lambert_wrap`), [rasterizer_scene_gles3.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp) (`blend_mul`): verified.
- [Godot ArrayMesh docs](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/arraymesh.html) (clockwise front faces); [Godot "Making trees"](https://docs.godotengine.org/en/stable/tutorials/shaders/making_trees.html) (uses `TIME`, vertex-colour sway): verified.
- [GPU Gems 3 ch. 16, Crysis vegetation](https://developer.nvidia.com/gpugems/gpugems3/part-iii-rendering/chapter-16-vegetation-procedural-animation-and-shading-crysis): verified.
- [Simon Schreibt, Airborn trees](https://simonschreibt.de/?p=45); [Foliage Normals](https://superhivemarket.com/products/foliage-normals): verified (articles).
- [SpeedTree runtime LOD](https://docs.unity3d.com/speedtree-runtime-sdk/manual/level-of-detail.html); [X-Plane forest spec](https://developer.x-plane.com/article/forest-for-file-format-specification); [X-Plane custom 3D trees](https://developer.x-plane.com/article/building-custom-3-d-trees/); [CryEngine terrain AO](https://www.cryengine.com/docs/static/engines/cryengine-3/categories/1114113/pages/1048830); [Unreal Pivot Painter 2](https://dev.epicgames.com/documentation/unreal-engine/pivot-painter-tool-2.0-in-unreal-engine): verified [doc].
- [Kenney Nature Kit](https://kenney.nl/assets/nature-kit): downloaded to scratch, License.txt CC0, counts measured.
- GitHub (license and last push via the API, 2026-10-07): SimpleGrassTextured, Spatial Gardener, ProtonScatter, GodotGrass, godot-imposter, SIsilicon and wojtekpil octahedral impostors (MIT, 2020/2021, Godot 3), ez-tree, gdTree3D, meshoptimizer v1.3 (gltfpack-ubuntu.zip SHA-256 `0666d9dc…6017`).
- [Juola et al., bark spectra](https://pmc.ncbi.nlm.nih.gov/articles/PMC8928865/); [Studio 397 albedo table](https://docs.studio-397.com/x/EgBDAg) [sec]; [Decaudin & Neyret 2004](https://evasion.inrialpes.fr/Publications/2004/DN04); [FlightGear Random Vegetation](https://wiki.flightgear.org/Random_Vegetation).
