# 04 · Procedural trees, low-poly tree assets and billboard impostors

Date: 2026-10-05. **Question:** what is the cheapest way to get a believable treeline 250–600 m from a fixed pilot, plus scattered trees, in Godot 4.7.2 Compatibility, with permissive licenses and repeatable captures?

## Findings

**1. What the pilot actually sees (pixel math)** [inference, from `Spec.CAMERA` fov 50°, 1280×720, `Spec.AUTO_ZOOM` min 6°]

| Tree 15 m tall at | 50° FOV (f ≈ 772 px) | 6° auto-zoom (f ≈ 6870 px) |
| --- | --- | --- |
| 250 m | 46 px | 412 px |
| 400 m | 29 px | 258 px |
| 600 m | 19 px | 172 px |

- Auto-zoom magnifies a far tree about 9×, so **billboard cells need 256–512 px of height**, not 64.
- **The pilot camera never moves.** Every tree is seen from one fixed azimuth and an almost level elevation (atan(13 m / 250 m) ≈ 3°). Octahedral views and LOD transitions buy nothing in the pilot view. Only the chase camera sees other angles.

**2. Alpha on Compatibility (this changes L11)**
- In 4.7.2 `drivers/gles3`, the alpha-to-coverage blend case is literally `// Do nothing for now.` ([src](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp)). The issue is still open ([#98173](https://github.com/godotengine/godot/issues/98173) [iss]), and the fix PR [#114845](https://github.com/godotengine/godot/pull/114845) is unmerged ([iss]).
- **Alpha hash is not implemented in GLES3 either.** `alpha_hash_scale` is declared but never read in `scene.glsl` ([src](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl)). Forward+ calls `compute_alpha_hash_threshold` ([src](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl)).
- MultiMesh instances are not sorted, so foliage must use **alpha scissor**.
- The texture importer's `process/fix_alpha_border` is **off by default for the 3D preset** ([src](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/import/resource_importer_texture.cpp)). Turn it on for baked atlases, or mipmaps get dark halos. Godot has no "preserve coverage" mip option, unlike Unity, so cut-out trees thin out with distance ([Golus](https://medium.com/@bgolus/anti-aliased-alpha-test-the-esoteric-alpha-to-coverage-8b177335ae4f) [sec]).

**3. What other sims do**
- **FlightGear** random trees: one instanced draw of **3 quads rotated around Z** (`NUM_QUADS = 3`, 6 triangles per tree, changed from 2 quads). Positions come from a per-tile text list ([TreeBin.cxx, LGPL-2.1](https://gitlab.com/flightgear/simgear/-/blob/next/simgear/scene/tgdb/TreeBin.cxx) [src]; [devel list 2025-01-24](https://sourceforge.net/p/flightgear/mailman/message/59122312/) [F]). Atlas: 4–8 varieties × 4 seasons; newer versions add normal maps for sun lighting ([wiki](https://wiki.flightgear.org/Random_Vegetation) [doc]). We copy the idea only, no code (LGPL).
- **FS2004** autogen: ≤ 600 trees per LOD-13 cell, drawn to about 6 nm ([FSDeveloper](https://www.fsdeveloper.com/forum/threads/autogen-radius.81821/) [F]).
- **PicaSim** is PolyForm Noncommercial ([repo](https://github.com/Rowlhouse/PicaSim) [repo]): no reuse.

**4. Octahedral impostors: not now**
- [godot-imposter](https://github.com/zhangjt93/godot-imposter) (MIT, last push 2025-08-15, "verified Godot v4.5.beta5") [repo]:
  - The shader defaults to 16×16 frames and samples albedo, normal, depth and ORM for 3 blended frames each.
  - Every atlas read is `textureLod(..., 0.0)`, so it **has no mipmaps** and will shimmer at 20 px [src].
- The original [wojtekpil plugin](https://github.com/wojtekpil/Godot-Octahedral-Impostors) (MIT, 2021) is Godot 3 only [repo].
- Hemi-octahedral experiments report frame popping and grazing-angle clipping at about 8×8 frames ([yummers.dev](https://www.yummers.dev/hemi-octahedral-impostors.html) [sec]).
- For a fixed pilot this is overkill [inference].

**5. Baking our own atlas in Godot**
- Use a `SubViewport` with `transparent_bg`, an orthographic `Camera3D` and `UPDATE_ONCE`. Then `await RenderingServer.frame_post_draw` before `get_texture().get_image()` (the docs warn the image is black or outdated otherwise) ([Viewport.xml](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/Viewport.xml) [doc]).
- `--headless` uses the dummy renderer, so the bake must run under `xvfb-run` like `capture.sh` [inference]. Bake offline and commit the PNG with a SHA-256, so the runtime never depends on the bake.

**6. Tree sources**
- **Poly Haven `fir_tree_01`** is CC0 but has **7.85 M polygons**, a 238 MB FBX and a 209 MB .blend ([api](https://api.polyhaven.com/info/fir_tree_01), [files](https://api.polyhaven.com/files/fir_tree_01) [measured]). It is only usable as an offline bake source in Blender.
- **Blender Sapling Tree Gen**: the add-on is GPL, but "what you create with Blender is your sole property" ([blender.org](https://www.blender.org/about/license/) [doc]). Its outputs are fine; the add-on itself must never be shipped.
- **proctree.js** (Paul Brunt): **BSD-3** in the file header, though the repo has no LICENSE file and was last pushed in 2019. It is 514 lines with its own deterministic RNG `abs(cos(a+a*a))` ([src](https://github.com/supereggbert/proctree.js/blob/master/proctree.js) [src]). It is small enough to port to an offline GDScript tool with credit.
- **ez-tree** (MIT, v1.1.0 released 2026-01-15, active 2026-07) [repo] ([repo](https://github.com/dgreenheck/ez-tree)):
  - LODs from one skeleton (about 40 % / 20 % of the triangles).
  - Leaf PNGs are MIT; the bark textures are ambientCG CC0 ([LICENSE.md](https://github.com/dgreenheck/ez-tree/blob/main/src/app/public/textures/LICENSE.md) [src]).
- **Tree3D / gdTree3D**: MIT, v1.1.0 released 2026-09-14, C++ GDExtension, Godot 4.5+, desktop only ([repo](https://github.com/JekSun97/gdTree3D) [repo]). Its release ships no web binary. At best an editor-only generator.
- **Kenney Nature Kit**: CC0, v1.0 (2020), 330 files ([kenney.nl](https://kenney.nl/assets/nature-kit) [doc]). One secondary source reports a median of about 166 triangles per tree, at 1.33 m tall ([shorepine/kenney](https://github.com/shorepine/kenney) [sec]). Flat-shaded, toy-like.
- **Quaternius Stylized Nature MegaKit**: CC0, July 2024, 40 trees, glTF ([page](https://quaternius.com/packs/stylizednaturemegakit.html) [doc]). 60–70 % free; no triangle counts listed.

**7. A Y-axis billboard for MultiMesh** (our own code, project license; untested [inference]: check that `INSTANCE_CUSTOM` and `CAMERA_POSITION_WORLD` behave in GLES3)

```glsl
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 cells = vec2(4.0, 2.0);       // atlas columns, rows
varying vec2 cell;
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;            // instance origin (per-instance transform)
	vec3 f = CAMERA_POSITION_WORLD - o; f.y = 0.0; f = normalize(f);
	vec3 r = vec3(f.z, 0.0, -f.x);
	float sx = length(MODEL_MATRIX[0].xyz), sy = length(MODEL_MATRIX[1].xyz);
	vec3 w = o + r * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(f, 0.0)).xyz; // TODO: baked normal map for sun shading
	float i = INSTANCE_CUSTOM.x * 255.0;     // variety index (use_custom_data = true)
	cell = vec2(mod(i, cells.x), floor(i / cells.x));
}
void fragment() {
	vec4 c = texture(atlas, (UV + cell) / cells);
	ALBEDO = c.rgb; ALPHA = c.a; ALPHA_SCISSOR_THRESHOLD = 0.5;
}
```

Far billboards: `cast_shadow = OFF` (the shadow pass would face them to the light; they are beyond L3's ~300 m anyway) [inference].

**8. Budget estimate** [inference]
- Horizontal FOV is about 79°, so 3 of 8 azimuth sectors (45° each) are visible.
- Per sector: 1 billboard MultiMesh, since all varieties share one atlas, plus 3D species × 2 surfaces for near trees. That comes to about **≤ 24 draw calls** for vegetation.
- About 600 treeline trees as billboards make 1.2 k triangles. 3D trees at ≤ 1 k triangles, about 150 visible, add about 150 k.

## Libraries / tools found

| Name | Version / last release | License | Compatibility / web? | Fit for us |
| --- | --- | --- | --- | --- |
| proctree.js | no release, push 2019-06 | BSD-3 (header) | n/a: port to an offline GDScript tool | **High**: small, deterministic, ours after the port |
| ez-tree | v1.1.0 (2026-01-15) | MIT (+ CC0 bark) | n/a: offline GLB export | **High** for quick realistic species; Node already pinned |
| Tree3D (gdTree3D) | v1.1.0 (2026-09-14) | MIT | GDExtension, no web build | Low: editor-only at most |
| godot-imposter | master 2025-08-15 | MIT | Unverified on 4.7 / GLES3; no mips | Low: skip |
| Kenney Nature Kit | 1.0 (2020) | CC0 | glTF | Medium: placeholder or scattered bushes |
| Quaternius MegaKit | 2024-07 | CC0 | glTF | Medium: stylized look |

## What this changes in LANDSCAPE-PLAN.md

1. **Split L6 into L6a and L6b, and do billboards first** (reorder L6 and L8):
   - **L6a, tree sources:** an offline tool outside `app/` produces 3–4 species meshes, each ≤ 1 k triangles with one 1K leaf texture, from a proctree port or ez-tree GLB. Every file goes in `PROVENANCE.json`. *Proof:* a triangle-count test per mesh, plus a SHA-256 for each file.
   - **L6b, billboard treeline:** an offline xvfb bake writes one atlas of 4×2 cells, 256×512 px per cell, 1024×1024 total, with `fix_alpha_border` on. The ring is built from 8 sector MultiMeshes using the shader above. *Proof:* atlas SHA-256; the 4 horizon captures; counters ≤ 24 vegetation draw calls.
2. **Redefine L8 as "3D trees near the pilot", with static LOD by distance from the pilot station, not `visibility_range`:**
   - Trees closer than X m from the pilot station use the 3D mesh; farther trees stay billboards forever.
   - The pilot view then never pops, the assignment is deterministic, and a test can check it from the placement file.
   - *Proof:* in the pilot view at 400 m, the billboard and 3D silhouettes of each species match (alpha-mask IoU ≥ 0.9, threshold to calibrate); the 10-frame chase strip shows no pop.
3. **Fix L11:** remove "MSAA 2× alpha-to-coverage" (a no-op in 4.7.2 GLES3) and use alpha scissor with `fix_alpha_border` mipmaps. *Proof:* a near-grass capture with grass coverage within ±10 % of the L0 baseline at 30 m.
4. **Add a far forest strip at 600–1500 m to L7:** one ring mesh with an alpha silhouette strip in the same draw call family as the hills. *Proof:* ≤ 1 extra draw call.
5. **L14:** a test checks billboard size equals the collision cylinder from the same placement file.

## Not confirmed

- `INSTANCE_CUSTOM` and `CAMERA_POSITION_WORLD` with `skip_vertex_transform` on a MultiMesh in GLES3 and on web; the [GLES3 billboard bug on web](https://github.com/godotengine/godot/issues/61642) is still open.
- Byte-identical SubViewport bakes across Mesa versions (the plan only shows that captures repeat on one machine).
- Quaternius triangle counts; the Kenney median (one secondary source).
- Whether ez-tree's GLB export runs headless in Node without a DOM.
