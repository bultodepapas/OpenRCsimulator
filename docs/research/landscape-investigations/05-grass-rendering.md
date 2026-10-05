# 05 · Grass and ground cover in the Compatibility renderer

Date: 2026-10-05. **Question:** which grass technique works in Godot 4.7.2 Compatibility (WebGL 2), stays byte-repeatable in llvmpipe captures, and is worth drawing for a pilot standing at 1.7 m? How far out do 3D blades matter?

## Findings

**1. Alpha-to-coverage (A2C) does nothing in Compatibility 4.7.2, so L11 as written won't work.**
- In the GLES3 renderer, the A2C blend mode is a stub: `case BLEND_MODE_ALPHA_TO_COVERAGE: { // Do nothing for now. }` ([rasterizer_scene_gles3.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp)). [src]
- `alpha_antialiasing_edge` is declared in [scene.glsl](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl) and never read. A search of the engine code finds no `SAMPLE_ALPHA_TO_COVERAGE`. [src]
- Open issues: [#98173](https://github.com/godotengine/godot/issues/98173) and [#84242](https://github.com/godotengine/godot/issues/84242). Alpha hash isn't implemented either ([#103094](https://github.com/godotengine/godot/issues/103094)). [iss]
- The [material docs](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html) don't mention the gap. [doc]
- **[measured]** With MSAA 2× on (`project.godot`), three settings give the same capture byte for byte (`4fbe107d…`, 0 px differ): A2C off, `ALPHA_ANTIALIASING_EDGE = 0.3`, and `render_mode alpha_to_coverage`.
- Result: alpha-scissor foliage has aliased edges. MSAA only smooths real geometry edges.

**2. Opaque geometric blades look better than alpha cards here.** [measured]
- Setup: same 9,673 clumps within 40 m, runway left clear.
- Alpha cards (3 crossed 0.35 × 0.15 m quads with a generated texture) look blobby and dark. They also leave dark specks where low mip levels cross the alpha threshold.
- Blades (7 single-triangle blades per clump) get MSAA-smoothed edges and fade into the ground colour with distance. The comparison image is `compare_crop.png` in the scratch folder.
- GodotGrass does the same thing: geometry blades, no texture alpha. It also widens blades with distance and thickens blades seen edge-on ([grass.gdshader](https://github.com/2Retr0/GodotGrass/blob/main/assets/shaders/spatial/grass.gdshader), MIT). [src]
- Geometry also avoids "the high overdraw caused by transparent billboards" ([hexaquo](https://hexaquo.at/pages/grass-rendering-series-part-2-full-geometry-grass-in-godot/)). [sec]

**3. Spike numbers** (llvmpipe, 1280×720, `--alt=3 --autozoom=0`). [measured]

| Variant | Draw calls | Primitives | Ground px changed | Byte-repeat |
| --- | --- | --- | --- | --- |
| No grass | 107 | 27,910 | – | ✅ `b1f0c33b…` ×2 |
| 6k alpha clumps, 1 MultiMesh | 108 | 63,910 | 36.6 % | ✅ `4fbe107d…` ×2 |
| Same, 4×4 chunks | 114 | 48,736 | same image | ✅ same hash |
| 20k alpha clumps | 108 | 147,910 | 74.6 % | – |
| 12k alpha, runway clear | 108 | 85,948 | 26.8 % | ✅ `9b76d840…` ×2 |
| 12k blades, runway clear | 108 | 95,621 | 19.3 % | ✅ `b65170c3…` ×2 |

- One MultiMesh costs one draw call.
- Chunking culled 9 of 16 chunks: 42 % fewer grass triangles for 6 extra draw calls.
- **The baseline is already 107 draw calls**, mostly airplane parts. The ≤ 150 budget leaves ~40 for all landscape steps.
- Captures repeat because placement is seeded, `TIME` is never used, and sway comes from a `sim_time` uniform.
- In GLES3, the model matrix includes each instance's transform (`model_matrix = model_matrix * transpose(m)`, [scene.glsl L613](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl)) [src]. So the distance fade can use `CAMERA_POSITION_WORLD`, and it worked [measured].

**4. How far grass matters** (eye 1.7 m, 50° vertical FOV, 720 px). [inference: geometry, matched by captures]

| Distance | Pixels below horizon | 2 cm blade | 15 cm clump |
| --- | --- | --- | --- |
| 5 m | 262 | 3.1 px | 23 px |
| 10 m | 131 | 1.5 px | 12 px |
| 20 m | 66 | 0.8 px | 5.8 px |
| 40 m | 33 | 0.4 px | 2.9 px |
| 100 m | 13 | 0.15 px | 1.2 px |

- In the captures, the last visible grass row sits 32–37 px below the horizon, which matches 40 m. [measured]
- Single blades are only visible within ~15 m. Clumps add texture out to ~30 m. Beyond that, grass is just colour, which is L9's job.
- When the pilot looks at an airplane 16° above the horizon, the only ground on screen is within ~11 m. **3D grass is mainly a takeoff, landing and low-pass feature.**

**5. Grass draws the runway edge.** Leaving the mown rectangle without clumps gives a crisp runway border at 10–40 m, which a flat colour change doesn't (`g12k_mown.png`). [measured, visual]

**6. Rejected or limited options.**
- Shell texturing: shells show "visible layer gaps at grazing camera angles" ([80.lv](https://80.lv/articles/classic-video-games-trick-for-rendering-grass-fur), [godotshaders](https://godotshaders.com/shader/fur-grass-with-shell-texturing/)) [sec]. Our pilot sees the ground at 2–10°.
- GodotGrass: built for Forward+ on Godot 4.3, uses `TIME`, last push 2024-08-16 [repo].
- hexaquo: depends on `ALPHA_HASH_SCALE`, and its code is CC-BY-SA, so we don't copy it [sec].
- Ghost of Tsushima: generates blades in compute shaders. Its far tiles are 2× larger with the same blade count, so 3 of 4 blades are dropped ([GDC](https://gdcvault.com/play/1027033/Advanced-Graphics-Summit-Procedural-Grass), [summary](https://tigerabrodi.blog/grass-in-ghost-of-tsushima)) [sec]. We can borrow the density idea, not the method.
- Alpha mipmaps: thinning is fixed in **4.8**, not 4.7. [PR #104289](https://github.com/godotengine/godot/pull/104289) (merged 2026-08-31) adds `generate_mipmaps(…, preserve_alpha_test_coverage, threshold)` [rel]. On 4.7 we'd need [Castaño's](http://www.ludicon.com/castano/blog/articles/computing-alpha-mipmaps/) per-mip alpha scaling ourselves [sec].

Spike shader core (our code, MIT). Compatibility has no visibility-range fade, so blades shrink into the ground instead:
```glsl
shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform float sim_time = 0.0;      // fed from simulation time, never TIME
uniform float fade_start = 28.0;
uniform float fade_end = 40.0;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float top = 1.0 - UV.y;
	VERTEX.x += sin(sim_time * 1.7 + w.x * 0.6 + w.z * 0.4) * 0.04 * top;
	float d = length(w.xz - CAMERA_POSITION_WORLD.xz);
	VERTEX.y *= 1.0 - smoothstep(fade_start, fade_end, d);
	NORMAL = vec3(0.0, 1.0, 0.0); // ground-like lighting, no dark back faces
}
```

## Libraries / tools found

| Name | Version / last activity | License | Compatibility/web? | Fit |
| --- | --- | --- | --- | --- |
| [2Retr0/GodotGrass](https://github.com/2Retr0/GodotGrass) | no release; 2024-08-16 | MIT | Built for Forward+; shader is plain GLSL ES 3.0 + `TIME` [inference] | **Reference** for blades, distance thickening and clumping. Replace `TIME` |
| [SimpleGrassTextured](https://github.com/IcterusGames/SimpleGrassTextured) | v2.1.0, 2026-04-03 | MIT | Detects `gl_compatibility`; wind via global uniforms set from script | Too heavy (SubViewports redrawn every frame); copy the wind-uniform pattern |
| [Spatial Gardener](https://github.com/dreadpon/godot_spatial_gardener) / [ProtonScatter](https://github.com/HungryProton/scatter) | v1.4.1 (2025) / pushed 2026-09-27 | MIT | Not checked | Editor painting/scatter tools; we place from data |
| [Shell texturing](https://godotshaders.com/shader/fur-grass-with-shell-texturing/) | Godot 4.4 | CC0 | Yes | ❌ breaks at grazing angles |
| [Quaternius Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html) | – | CC0 | glTF | Bushes and flowers (L11b) |

## What this changes in LANDSCAPE-PLAN.md

1. **Rewrite L11 as "near-field grass blades".**
   - Opaque clumps of single-triangle blades. Placement is seeded offline and committed with a SHA-256.
   - Covers ≤ 30 m from the pilot, density ∝ 1/r, blades shrink to nothing between 22 and 30 m, and none on the runway from the field file.
   - At most 2×2 MultiMesh chunks, `cast_shadow = OFF`, colours derived from `Spec.GRASS`, and sway amplitude 0 until L15.
   - **Proofs:**
     - The `--alt=3` capture repeats byte for byte.
     - At most +5 draw calls and +100k primitives, read from `Performance` in a test.
     - In the 25–35 m band, mean colour is within 3 % of the no-grass capture (no visible seam).
     - Placement hash test.
2. **Add L11b, "bushes and flowers".** CC0 low-poly geometry, no alpha. Alpha cards wait for 4.8 **and** a fix for #98173.
3. **Reorder: L11 right after L9.** L9's runway-edge proof should be measured with and without grass, since the grass edge is a strong cue.
4. **Record the 107-draw-call baseline in L0.** Split the remaining ~40 between grass (≤ 5) and the treeline (L6).
5. **Add a risk:** A2C and alpha hash are no-ops in Compatibility, so foliage edges must be geometry.

## Not confirmed

- GPU frame time on the owner's hardware. llvmpipe numbers are not a performance measure.
- MSAA in the web build, given WebGL 2 sample limits and platform gaps like [#96275](https://github.com/godotengine/godot/issues/96275). Without it, blades shimmer and need distance thickening.
- Byte-identical captures across Mesa versions and thread counts.
- Shimmer in motion. Only still frames were checked.
- That only ~11 m of ground is in view during normal flight. This comes from geometry and wasn't measured with auto-zoom.
