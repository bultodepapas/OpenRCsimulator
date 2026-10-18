# Tree and forest quality: sources and project audit

2026-10-17. Research for the [tree/forest implementation plan](../plans/tree-forest-quality.md). Scope: current repository source/configuration, retained source-package inventory, Godot 4.7 documentation, downloadable assets, GitHub tooling and skill discovery. **No new assets were downloaded/imported, no trees were modeled, no plugin or skill was installed, and no runtime benchmark or new visual acceptance was performed.**

Repository HEAD during inspection: `f3e1539b`, with pre-existing grass-plan/index changes preserved. The existing knowledge graph located the original tree code; newer scenery coverage was incomplete, so current files were read directly for those seams. Counts below are code/catalog/manifest findings, not measurements from a newly rendered session. Web prices, licenses and popularity are dated observations; recheck the exact selected package during intake.

## Current project findings

| Finding | Evidence and implication |
| --- | --- |
| Engine/backend | [Engine pin](../../app/get-godot.sh): `4.7.2-stable`. [Project configuration](../../app/project.godot): `gl_compatibility`, 4× MSAA. Recommendations must work on this backend without requiring an engine/renderer migration. |
| Existing forest | [Tree pipeline](../../tools/trees/README.md), [renderer](../../app/render/treeline.gd): 480 near-ring + 1,200 far-ring trees, eight azimuth groups; three crossed quads per tree, one scissored surface, shadows off. The far population already uses clusters rather than wholly uniform scatter. |
| Existing variation | [CPU/GPU identity](../../app/render/tree_identity.gdshaderinc) derives three shapes, 12–25 m height and yaw from quantized coordinates. [Shader](../../app/render/treeline.gdshader) adds tint, crown normals, backlight, base darkening and far alpha compensation. These are existing features, not new recommendations to implement from zero. |
| Atlas contract | [Asset validator](../../app/render/tree_assets.gd) checks fixed atlas/tile dimensions and known species rectangles. Renderer/shader tables and collision crown fractions also assume the current family. Additional shapes require coordinated contract changes; existing exact-byte custom-data encoding must survive any extension. |
| Source reuse opportunity | Inspected ZIP member names in `assets/landscape/vegetation/source/quaternius_stylized_nature_megakit_standard.zip`: `CommonTree_1..5`, `Pine_1..5`, `DeadTree_1..5`, `TwistedTree_1..5` all have glTF entries. Only three tree assets are selected in the current vegetation catalog. Unselected files were inventoried, not rendered or triangle-counted in this task. |
| Exact retained license | [Vegetation catalog](../../app/assets/landscape/vegetation/catalog.json) records archive SHA-256 `298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9`, retrieval 2026-10-13, embedded `License_Standard.txt` CC0-1.0 and license hash. Preserve this evidence; a later download may have different terms. |
| Imported 3D trees | Same catalog: CommonTree_1 6,265 triangles, CommonTree_3 3,505, Pine_1 3,947; two material surfaces each, source bark/leaf maps, automatic Godot glTF LOD import. [Library](../../app/scenery/imported_vegetation.gd) batches per asset part, not per spatial cell, and enables shadows. These are source counts, not frame submissions. |
| Motion distinction | [Scenery assembly](../../app/scenery/scenery.gd) calls `ImportedVegetation.build(vegetation_batches)` with default `enable_wind=false`. Field cards read the shared shader uniforms. [Main](../../app/main.gd) supplies session wind via `_render_wind()` to `World.update()` during interactive flight; scripted mode returns zero. Some retained documentation/comments predate that wiring. |
| Material extension risk | Imported wind adaptation copies selected albedo/UV/vertex-color/normal/roughness/metallic/scissor properties. It is not a general lossless adapter for every third-party PBR material. New textures, masks or wind must verify the effective material, including other vegetation consumers. |
| Placement/contact limits | [Loader](../../app/data/field_loader.gd): 1,680 max field-tree positions, radius 250–1,500 m, 15 m card clearance envelope and 35 m flight-corridor half-width. [Collision world](../../app/scenery/collision_world.gd) consumes tree identity and imported placement dimensions for trunk/crown proxies. Shape, height and density changes are not necessarily render-only. |

The [2026-10-06 tree review](tree-resource-review-2026-10-06/README.md) remains useful historical evidence: it compared KayKit/Quaternius/Kenney and retained exact package licenses. Its L6a statement that source meshes stay offline applies to that atlas family; later LU integration also ships selected 3D vegetation. Do not extend the older statement to all current trees.

## Free assets and licensing

| Primary source | Verified finding | Recommendation and remaining proof |
| --- | --- | --- |
| [Quaternius Standard](https://quaternius.itch.io/stylized-nature-megakit), [current general license](https://quaternius.com/license.html), retained package above | Existing exact archive carries CC0. Current general QAL terms restrict redistribution of standalone assets; do not call all Quaternius downloads CC0. | Highest-confidence first source for extra shapes because files and package evidence are already retained. Preview additional variants in the same scene; stylized appearance remains a limitation for strict photorealism. |
| [Poly Haven Pine Tree 01](https://polyhaven.com/a/pine_tree_01), [Pine Forest](https://polyhaven.com/collections/pine_forest), [license](https://polyhaven.com/license) | CC0; realistic tree source and material maps, with glTF among download formats. Pine listing reports 17M triangles. | Offline source/bake comparison only at this size. Do not presume auto-LOD makes a multi-million-triangle asset affordable or preserves alpha foliage. Full source was not downloaded. |
| [Poly Haven Jacaranda Tree](https://polyhaven.com/a/jacaranda_tree) | CC0 model; glTF/FBX/Blend/USD options, separate branch/leaf/trunk maps, LOD tag, advertised 312K triangles and 24.2 m width. | Useful realistic broadleaf/material benchmark. LOD tag is not a measured runtime budget. Near use needs supplier-LOD inspection, native GPU/resource proof and a suitable biome; not a default addition to the current forest. |
| [Poly Haven Forest Floor](https://polyhaven.com/a/forest_floor), [license](https://polyhaven.com/license) | CC0 forest-floor texture with PBR maps and resolution choices. | Candidate leaf-litter/soil transition under canopy. Coordinate with ground/grass owners and avoid another expensive full-field material layer. |
| [ambientCG Bark 001](https://ambientcg.com/view?id=Bark001), [license](https://docs.ambientcg.com/license/) | CC0 texture, downloadable JPG/PNG resolutions; license permits redistribution, including raw files. | Candidate for a demonstrated bark mismatch with compatible UVs/scale; not a replacement tree mesh or a universal species texture. |
| [KayKit Forest Nature](https://kaylousberg.itch.io/kaykit-forest) | FREE package offers 100+ stylized assets in common 3D formats under CC0; EXTRA is separate. Prior local review retained archive/license and measured selected trees. | Low-cost comparison/fallback. Avoid treating the whole advertised paid+free catalog as the free package, or treating low-poly style as realistic foliage. |
| [klamtii Tree Sprites](https://klamtii.itch.io/tree-sprites), [retained review](tree-resource-review-2026-10-06/README.md) | 30 PNG views; prior downloaded license permits modification/redistribution but is not CC0. Existing shading is baked into the rendered views. | Far-view silhouette reference/reserve. Test changing light and camera before use; no close-view geometry. |
| [Lui Garcia Trees Library, original author release](https://forums.unrealengine.com/t/free-trees-library/63813) | Author advertises 100+ trees, 16 species, most with four LODs including billboard, plus OBJ/textures. | Attractive research lead, **not cleared for intake**: inspected author material did not establish explicit redistribution terms for the pack and its textures. Do not infer them from Tree It's tool terms or a free download button. |

This initial shortlist does not establish a newly downloaded realistic runtime-ready pack. Its strongest immediate result is unused, already-licensed variation plus realistic CC0 sources that need representation/cost qualification. The [second round](#second-round-25-additional-investigations) adds more plausible runtime candidates with supplied LODs. Prefer asset-specific license files and retain notices even where attribution is optional. Do not substitute AI-generated trees or a procedural modeling tool when a candidate fails intake.

## Godot techniques and research

| Primary source | Finding relevant to OpenRC | Application / limit |
| --- | --- | --- |
| [MultiMesh optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html) | Instancing reduces submission overhead, but visibility applies to the whole MultiMesh. | Reuse batching; compare bounded spatial partitions. Instancing does not remove leaf overdraw or shadow cost. |
| [Mesh LOD](https://docs.godotengine.org/en/4.7/tutorials/3d/mesh_lod.html) | All MultiMesh instances share one selected mesh LOD, based on the closest point of the node bounds. | Separate far-apart instances. A large near-camera batch can keep distant trees detailed; automatic LOD is not per-tree selection. |
| [Visibility ranges](https://docs.godotengine.org/en/4.7/tutorials/3d/visibility_ranges.html), [GeometryInstance3D](https://docs.godotengine.org/en/4.7/classes/class_geometryinstance3d.html) | Manual representations can be switched with ranges. API notes restrict Self/Dependencies fading to Forward+; Compatibility treats them as disabled without hysteresis. | Start with explicit disabled fade/hysteresis and matched silhouettes. Generic tutorial fading examples do not prove backend support. |
| [StandardMaterial3D](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html) | Alpha scissor/hash/blend have different coverage, sorting and cost behavior. Subsurface scattering is Forward+-only. | Keep scissored foliage as control; validate two-sided normal/backlight response and actual source channel bindings. Avoid a renderer migration for a leaf feature. |
| [Godot PR #114845](https://github.com/godotengine/godot/pull/114845) | Compatibility alpha-to-coverage implementation was still shown as open when checked. | Preserve the existing L6b-R1 support probe and baseline alpha compensation. 4× MSAA alone is not proof of leaf-edge coverage support. |
| [Bridson, Fast Poisson Disk Sampling, 2007](https://www.cs.ubc.ca/~rbridson/docs/bridson-siggraph07-poissondisk.pdf) | Provides efficient minimum-distance point sampling. | Use as a placement reference inside habitat patches; fixed-radius sampling alone does not produce woodland structure. No new plant mesh generator. |
| [Deussen et al., Realistic modeling and rendering of plant ecosystems, 1998](https://graphics.uni-konstanz.de/publikationen/Deussen1998RealisticModelingRendering/Deussen1998RealisticModelingRendering.pdf) | Treats population distribution and environmental relationships as part of convincing vegetation scenes. | Borrow clustered composition/competition ideas as art heuristics; no ecosystem simulation or physical/ecological validation is claimed. |
| [Sousa, GPU Gems 3 chapter 16](https://developer.nvidia.com/gpugems/gpugems3/part-iii-rendering/chapter-16-vegetation-procedural-animation-and-shading-crysis) | Separates broad vegetation bending from detail motion and discusses two-sided leaf shading. | Adapt the principle to existing downloadable meshes, deterministic render time and read-only session wind; do not import its whole renderer, interactions or authored mask workflow. |

## Reusable repositories

| Repository | License / compatibility evidence | Decision |
| --- | --- | --- |
| [ProtonScatter](https://github.com/HungryProton/scatter), now a mirror of [Codeberg upstream](https://codeberg.org/hungryproton/proton_scatter) | MIT Godot 4 placement addon: shapes, exclusions and modifier-based scattering. README separately restricts standalone redistribution of some demonstration textures. | First authoring-tool candidate if current placement editing becomes a bottleneck. Pin an upstream commit, use our licensed assets, test 4.7.2 Compatibility and export stable placements through current validation. No duplicate runtime scatter layer. |
| [Spatial Gardener](https://github.com/dreadpon/godot_spatial_gardener), [v1.4.1-stable release](https://github.com/dreadpon/godot_spatial_gardener/releases/tag/v1.4.1) | MIT brush-based scene planting. Inspected release targets Godot 4.4. | Optional manual woodland-edge/track authoring. Test save/reopen, source transforms, LOD, exported placement and native package on the pinned engine before adoption. Not required to improve the existing finite field. |
| [Octahedral Impostor LOD](https://github.com/hdrsniped/octahedral-impostor-lod-godot), [license](https://github.com/hdrsniped/octahedral-impostor-lod-godot/blob/main/LICENSE) | Custom permissive license requires visible credit to hdrsniped and retained notices; not plain MIT. README targets Godot 4.7+ and lists Compatibility support, but reports popping crossfades and no card self-shadowing there. | Conditional L8b prototype only. Captures MeshInstance3D, not MultiMesh inputs: bake a source before scattering. Needs a real window. View/depth/normal atlases consume memory; quoted demo speedups are not OpenRC benchmarks. Repository showed only one star/six commits, so treat it as experimental. |

Use existing tools only when they solve an observed authoring or representation problem. Free software can still add maintenance, import and export costs. No runtime dependency or plugin version is accepted by this review.

## Skills discovery

Checked the [skills.sh directory](https://skills.sh/) and ran `npx --yes skills find godot`; then inspected the named skill sources and repositories. Counts are approximate discovery-time snapshots, not quality guarantees. These are optional implementation references, not vegetation assets or verified project integrations.

| Skill / source | Discovery evidence | Fit and caveat |
| --- | --- | --- |
| [godot-gdscript-patterns](https://skills.sh/wshobson/agents/godot-gdscript-patterns), [source](https://github.com/wshobson/agents/blob/main/plugins/game-development/skills/godot-gdscript-patterns/SKILL.md) | About 17K skill installs; [repository](https://github.com/wshobson/agents) about 41K stars, MIT. Community source, not an official Godot package. | Optional resource/lifecycle/architecture review. Generic node/state patterns must defer to this project's existing Simulation, detached rendering and ownership contracts. |
| [godot-shaders](https://skills.sh/gamedev-skills/awesome-gamedev-agent-skills/godot-shaders), [source](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/main/skills/godot/godot-shaders/SKILL.md) | Roughly 4.7K installs; [repository](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) about 1.6K stars, Apache-2.0. Community source. | Secondary syntax/workflow reference only. It recommends built-in `TIME`, which conflicts with this repository's deterministic `sim_clock` rule; its general shader advice still needs current official API/backend verification. No automatic installation recommended. |

If selected later, review the exact revision first. The discovery commands for installing only those individual skills are:

```sh
npx skills add wshobson/agents --skill godot-gdscript-patterns
npx skills add gamedev-skills/awesome-gamedev-agent-skills --skill godot-shaders
```

Neither command was run. Existing source pipelines, project-specific tests and official Godot documentation are sufficient to begin the plan. No specialized forest skill was verified as a substitute for asset intake, Compatibility captures or GPU measurement.

## Second round: 25 additional investigations

2026-10-17 expansion, starting at repository HEAD `9e721d47`. These are **25 additional source investigations**, distinct from the initial shortlist: six asset/material resources, six repositories/tools, six rendering/import studies, four firsthand community reports, two woodland references and one skill. Each has a proposed application and a verification condition. Related links supporting the same investigation count once. These are research IDs, not new implementation steps.

Scope remains documentation only. Listings, documentation, repository files and author reports were inspected; no candidate archive was downloaded, no runtime was changed and no performance result was reproduced. Primary Sketchfab listings were available through page extraction and indexed copies, although direct reopening returned HTTP 403. Five listings identify LOLIPOP and link CC Attribution to [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Preserve attribution, model URL, license and a description of derivative changes during intake. Source listing counts are not imported/runtime counts. Sketchfab's [download documentation](https://sketchfab.com/developers/download-api/downloading-models) describes downloadable glTF; exact archive contents, access requirements and supplied LOD organization remain intake checks.

### X01 — Pine Trees Pack: realistic conifer family

[LOLIPOP's Pine Trees Pack](https://sketchfab.com/3d-models/pine-trees-pack-lowpoly-game-ready-lods-e1e9c07b8e2e445c943fec660beefba2) advertises 15 models from large trees to saplings, four representations including 16-triangle billboards, shared bark/branch maps and CC BY 4.0. Listed medium LOD0s are approximately 2.9–4.4k triangles; large forms are 10–12k. Vertex channels carry AO, a height gradient and branch/trunk blending data.

**Decision / proof:** prioritize two medium silhouettes and one actual sapling in **L6a-R1**, with supplier lower LODs under **L8a**. Verify file contents, per-part counts, height, alpha, vertex semantics and eight-angle views. A wind gradient can be reused under **L15b-R1**; it must not be interpreted as ordinary RGB tint. Listed LODs do not establish automatic Godot selection.

### X02 — Realistic Fir Trees Pack: size classes with supplied LODs

[LOLIPOP's Fir pack](https://sketchfab.com/3d-models/realistic-fir-trees-pack-lods-gameready-f58e8b6d733e4b0586e5b7db847b89e7) offers large, medium and small trees, LODs/billboards and CC BY 4.0. Listing counts are roughly 13k, 6.8k and 600 triangles at the first level, with heights near 10 m, 4 m and 1.5 m. Primary-page extraction and indexed descriptions disagree on texture resolutions; do not use either as an archive manifest.

**Decision / proof:** reserve for a coherent fir habitat or comparison if Pine lacks suitable profiles; do not add every conifer merely for variety. **L6a-R1/L8a** must verify actual map sizes, supplied levels, units, leaf backs, transitions and scene cost. Neither the word “gameready” nor a small sapling establishes the large tree's affordability.

### X03 — Maple Trees Pack: broadleaf maturity and open crowns

[LOLIPOP's Maple pack](https://sketchfab.com/3d-models/maple-trees-pack-lowpoly-game-ready-lods-b5d2833c258f4054a01ee2b4ef85adf0) lists 12 models: four size classes with three variants each, not four species. Shared bark and branch maps are 2K; billboards have individual 1K maps. Small LOD0s are approximately 1.7–3.4k triangles, medium 4.7–14.6k and large 13–22.5k. Vertex R contains AO and B supports bark blending. License: CC BY 4.0.

**Decision / proof:** first realistic broadleaf candidate for **L6a-R1**, starting with two suitable small/medium variants and a true sapling. Inspect crown height/width rather than shrinking a mature source into a young tree. Verify channel handling, original materials and lower-LOD crown retention before **L6b-R2/L8a**. Keep heavy large forms out of mass placement until measured.

### X04 — Five Birch Trees: secondary silhouette and bark contrast

[LOLIPOP's Birch pack](https://sketchfab.com/3d-models/five-birch-trees-pack-lowpoly-lods-08fe5117138e4fdaa7ca440ef1201e07) lists five silver birches and two shared 4K texture sets. It labels first reported counts as LOD1, approximately 7.6–20.6k polygons, with later levels described as percentages. Do not relabel those figures as measured LOD0 triangles. License: CC BY 4.0.

**Decision / proof:** secondary **L6a-R1** reference for narrow crowns, pale trunks and woodland edges if the habitat fits. Verify topology/count units, actual supplied levels, texture residency and crown coverage. It is a heavier candidate, not a mandatory extra species or an approved source for dense instancing.

### X05 — Bush Models Pack: forest margins and understory

[LOLIPOP's Bush pack](https://sketchfab.com/3d-models/bush-models-pack-gameready-lods-f2d9ffd3e6a94cf0b9464ccd66a4c2f8) advertises 15 variants across three sizes, supplied LODs/billboards and average LOD0 costs near 2k/500/200 triangles. Branch maps are 1K, bark 1024×128, with smaller per-model billboard maps. Vertex R stores AO and G a wind gradient. License: CC BY 4.0.

**Decision / proof:** optional edge patches in **L7-R1**, coordinated with existing shrub/grass ownership. Compare against already integrated understory before taking new assets. Check alpha, rooted motion, visibility from pilot/RC views and total material/instance cost. Do not silently count bushes as trees or create new collision obstacles through decorative placement.

### X06 — Knotted Pine Bark: species-relevant material alternative

[Poly Haven's Knotted Pine Bark](https://polyhaven.com/a/knotted_pine_bark) is CC0 and supplies color, roughness, AO/packed channels, normal and displacement maps, with 1K–8K choices. The listing states a 1.7 m physical texture width, useful for a scale check rather than arbitrary UV enlargement.

**Decision / proof:** **L6b-R2** reserve only where the original pine bark visibly fails. Compare 1K/2K using the same mesh, light and UV scale; preserve the supplier material as control. Verify normal orientation, channel mapping and memory. Do not add displacement or high-resolution maps by default; downloading a material does not make unrelated UVs/species match it.

### X07 — Godot Imposter: another existing octahedral baker

[zhangjt93/godot-imposter](https://github.com/zhangjt93/godot-imposter) describes Godot 4 support and verification on 4.5 beta 5; Compatibility support is unspecified. Its README warns about transformed inputs being reset during baking. README licensing says MIT, while the checked-in [LICENSE](https://github.com/zhangjt93/godot-imposter/blob/master/LICENSE) says Unlicense; it also credits adapted code from [an MIT predecessor](https://github.com/wojtekpil/Godot-Octahedral-Impostors/blob/v2.0-new-baker/LICENSE).

**Decision / proof:** conditional **L8b** comparison, after resolving the selected revision's license/provenance and passing an isolated 4.7.2 Compatibility bake with an existing licensed tree. Compare eight azimuths and intervening angles, top/underside, transforms, alpha, moving sun, atlas memory and exports against current cards and the previously researched baker. No custom baker or default dependency.

### X08 — Foliage3D: substantial ecosystem cost

[Foliage3D](https://github.com/caphindsight/Foliage3D) documents chunked foliage, LOD and per-chunk MultiMeshes for Godot 4.7. It requires Terrain3D, GD++ and a native build toolchain. The README licenses `addons/foliage_3d` under MIT but explicitly excludes demo assets from redistribution permission. A free repository is not a free tree library.

**Decision / proof:** defer under **L7-R2**; the existing finite field does not justify a terrain/native-extension migration just to improve trees. Reconsider only if that architecture is independently adopted. Any future trial must use licensed project assets and verify native build/export, Compatibility support, bounded lifetime and measured gains over current batching. Do not import the demo forest.

### X09 — YAMMS: bounded placement authoring

[YAMMS](https://github.com/Mattiny/yamms), [MIT license](https://github.com/Mattiny/yamms/blob/main/LICENSE), documents v1.2.0 for Godot 4.3+, polygon placement regions, exclusions, per-type proportions and seeded placement using MultiMesh. It is an authoring/distribution candidate; its description does not establish per-instance culling or LOD support.

**Decision / proof:** optional **L7-R1** alternative if editing current habitat patches becomes slow. Compare against existing placement tools before adoption. Require fixed-seed reproducibility, authoritative ground/exclusions, correct transforms, save/reopen/export and conversion into the current validated placement contract. Do not introduce a second runtime population or bypass collision-world identity.

### X10 — glTF Transform: inspect before optimizing

[glTF Transform](https://github.com/donmccurdy/glTF-Transform) is MIT; its [CLI](https://gltf-transform.dev/cli) documents 4.5.0 and inspection, deduplication, texture processing and geometry transforms. Its [simplifier documentation](https://gltf-transform.dev/modules/functions/functions/simplify) describes lossy reduction and topology/seam limitations. The CLI's combined optimization defaults can alter more than the intended problem.

**Decision / proof:** useful offline **L6a-R1** intake tool, beginning with `inspect`. Pin the adopted version and apply one necessary transform to a copy. Compare node/part names, units, materials, UVs, normals, vertex data and alpha in Godot. A smaller GLB alone is not a runtime pass; compression extensions need native import verification. No blanket optimize command on retained sources.

### X11 — meshoptimizer/gltfpack: conditional geometry reduction

[meshoptimizer](https://github.com/zeux/meshoptimizer), [gltfpack documentation](https://github.com/zeux/meshoptimizer/blob/master/gltf/README.md) and [MIT license](https://github.com/zeux/meshoptimizer/blob/master/LICENSE.md) provide existing geometry optimization tools; [v1.3](https://github.com/zeux/meshoptimizer/releases/tag/v1.3) was the latest published release checked. gltfpack can simplify, quantize, merge/prune scene content and optionally compress it. The [simplifier notes](https://github.com/zeux/meshoptimizer/blob/master/js/README.md) explain restrictions around topology and attribute seams.

**Decision / proof:** defer under **L8a** unless profiling identifies geometry cost and supplied/imported LODs fail. First trial a trunk/branch derivative; leaf cards need separate silhouette/UV scrutiny. Record exact version/options and preserve the original. Require eight-angle crown comparison, seam checks, actual reduction, native import and frame-time improvement. Avoid node merging that destroys material, wind or placement semantics.

### X12 — Khronos glTF Validator: structural import gate

[Khronos glTF Validator](https://github.com/KhronosGroup/glTF-Validator), [Apache-2.0 license](https://github.com/KhronosGroup/glTF-Validator/blob/main/LICENSE), validates glTF/GLB structure, accessors, buffers, references and supported extensions, emitting a machine-readable report. The checked published package is `2.0.0-dev.3.10`, a prerelease; its [changelog](https://github.com/KhronosGroup/glTF-Validator/blob/main/CHANGELOG.md) labels 3.11 unreleased. This is independent of the rendering backend and does not validate visual quality or performance.

**Decision / proof:** add a structural check to **L6a-R1/L8a** intake and any glTF transformation. Use `2.0.0-dev.3.10` as the initial evaluation pin; retain its report, require zero errors and explain relevant warnings. Still inspect materials and render in 4.7.2 Compatibility. Apply the format validator to glTF derivatives, not indiscriminately to baked PNGs or Godot resources. Its code license grants no rights over the assets it checks.

### X13 — glTF material semantics: preserve the source appearance

The [Khronos material specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#materials) distinguishes opaque, masked and blended alpha; `MASK` uses a cutoff. Base-color RGB is sRGB, alpha is linear and stored unpremultiplied. Metallic/roughness data is linear, with roughness in G and metalness in B. Double-sided lighting includes a back-face normal reversal.

**Decision / proof:** **L6b-R2/L15b-R1** need an explicit source-to-effective-material comparison, including vertex-channel meaning and supplier-specific packed maps. Do not assume an `MRAO` texture has glTF's ordering or switch every material to transparency. Inspect leaf fronts/backs, trunk opacity, AO/roughness and color in neutral, backlit and dusk views, including after enabling wind.

### X14 — Godot texture imports: memory and version traps

[Godot 4.7 image imports](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html) can automatically enable mipmaps and VRAM compression when a texture is detected in 3D. Disk compression alone does not lower VRAM use. Its RGBA8-with-mips example is 5.33 MiB at 1K versus 21.33 MiB at 2K before GPU compression. High-quality VRAM compression is documented for Forward+/Mobile.

**Decision / proof:** record effective importer/material settings and measured residency in **VQ-02a/L6b-R2**, not only PNG size. Compare map resolution and compression separately. The [latest guide](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html) describes alpha-test coverage preservation, but the inspected [4.7 importer API](https://docs.godotengine.org/en/4.7/classes/class_resourceimportertexture.html) does not list that option. Probe the pinned binary before proposing it; no engine upgrade or custom importer follows from this research.

### X15 — Alpha mipmaps: coverage is not crown shape

[Lisyarus's original experiments](https://lisyarus.github.io/blog/posts/exploring-ways-to-mipmap-alpha-tested-textures.html) compare several alpha-mipmap methods. In those examples, preserving total coverage can still lose thin features or fill holes; simply increasing alpha can reveal unwanted texels. SDF-derived approaches introduce other problems, including cross-tile leakage in atlases.

**Decision / proof:** strengthen **L6b-R1/R2** verification: compare crown outline, internal gaps and color fringe as well as total covered pixels at relevant projected sizes. Test every atlas tile with its neighbors, not a standalone crop only. The author's preferred experimental method is not a universal solution; keep the existing importer and defer a custom SDF/mipmap pipeline unless a named defect survives cheaper source/layout fixes.

### X16 — Hashed alpha testing: controlled fallback

[Wyman and McGuire, Hashed Alpha Testing (2017)](https://research.nvidia.com/labs/rtr/publication/wyman2017hashed/) addresses alpha-masked geometry disappearing under minification. A spatially hashed threshold can stabilize stochastic coverage, but adds noise; the paper does not promise perfect edges or free rendering.

**Decision / proof:** only if **L6b-R1** reproduces persistent scissor dropout, compare Godot's existing alpha-hash path with the current control. Use 720p/1080p slow pans, approach/retreat, dark backgrounds and changing sun under Compatibility/4×MSAA. Do not assume TAA will hide grain. Reject visible noise/flicker, density inflation or excess cost; no custom transparency framework is proposed.

### X17 — GPU cost attribution: count pixels as well as trees

[Godot GPU optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/gpu_optimization.html) distinguishes submission, geometry, fragment/texture and shadow cost. It recommends an uncapped resolution comparison to diagnose fill-rate sensitivity, and warns that spatially broad batches sacrifice culling. Small projected triangles also waste work.

**Decision / proof:** extend **VQ-01c/L7-R2** with separate resolution, simple-material and imported-tree-shadow controls while placements remain fixed. Record viewport/cap settings and restore the accepted configuration for final qualification. A resolution response suggests pixel/bandwidth sensitivity; it does not isolate foliage by itself. Require tree-hidden comparisons and scene timing. Fewer draws or triangles alone cannot justify a denser forest.

### X18 — Occlusion culling: porous canopies are not walls

[Godot 4.7 occlusion documentation](https://docs.godotengine.org/en/4.7/tutorials/3d/occlusion_culling.html) explains CPU occlusion and whole-AABB visibility tests. Automatic baking excludes MultiMeshInstance3D. It provides an occlusion-buffer debug view and a runtime toggle; useful occluders depend on the actual view.

**Decision / proof:** defer general forest occlusion under **L7-R2**. If existing solid buildings or terrain block enough scenery, test those with matching pilot, ground and elevated views, CPU cost and buffer captures. Never use a solid crown proxy to hide geometry visible through leaves, and do not animate occluders with wind. Spatial partitioning may help occludees, but does not establish a net win.

### X19 — Firsthand 10,000-tree experiment: batching is a tradeoff

[Cosmonaut Frog's Reddit post](https://www.reddit.com/r/godot/comments/1u5y61t/i_wrote_my_first_devlog_a_diary_of_optimizing_a/) links the author's [optimization diary](https://cosmonautfrog.es/blog/asset-optimization-in-godot/). It reports Godot 4.6.2 Forward+, a Ryzen 5 3600-class CPU/GTX 1660 Super and 1080p, comparing LOD, impostors, chunks and shadow policies. Lower draw counts did not reliably mean lower cost; some auto-LODs visibly removed foliage.

**Decision / proof:** supports **L8a/L7-R2** comparison controls, not a transferable tree-count or FPS target. Repeat at our current population, renderer and cameras; track crown retention, primitives, draws and timing. Its manual modeling, generated imagery and assumption of never seeing trees from below are outside this plan. Aerial/underside views remain mandatory here.

### X20 — Forest iteration devlog: visual reference with engine caveats

[ToniMacaroniy's second forest iteration](https://www.reddit.com/r/godot/comments/1ngzfl0/second_iteration_of_my_forest_environment_in_godot/) describes foliage variation, bending/wind, cloud shadows and revised assets/shaders. The author also describes extensive asset processing and engine changes. It is a firsthand visual report, not a controlled benchmark or a Compatibility recipe.

**Decision / proof:** link as a composition/motion reference for **L6a-R1/L15b-R1**, alongside actual woodland references. Compare distinct crown profiles, restrained shared gusts and foliage separation in matched views. Do not reproduce its engine fork or make cloud-shadow work a tree prerequisite; lighting stays with FW/TOD. Reference viewing conveys no asset redistribution license.

### X21 — Resolved tree-performance thread: isolate shadows

[SinaQadri's performance thread](https://www.reddit.com/r/godot/comments/1fn4mj6/how_do_i_render_alot_of_trees_without_lagging/) reports improvement after changes to shadow setup, vegetation distribution and texture resolution. Those changes were bundled and the claimed FPS gain lacks isolated before/after timings, so causation cannot be assigned to one setting.

**Decision / proof:** **VQ-01c/L8a** should separate imported-tree caster toggles, shadow-distance changes and texture-size changes; keep far-card shadows disabled and all placements fixed. Use alternating full-scene frame-time measurements with visual contact/readability checks. Do not copy an FPS percentage or change all directional shadows globally based on this anecdote.

### X22 — Realistic Forest in Godot 4.4: geometry counts need context

[WungielPolacz07's forest showcase](https://www.reddit.com/r/godot/comments/1jkk5ts/realistic_forest_in_godot_44/) reports roughly 2,500 triangles per tree, LOD/distance removal and over 60 FPS on an RTX 4060 at 1080p Ultra. It supplies neither a repeatable scene population nor a target-Compatibility profiling trace. A comment identifies overly regular bright grass as a visual weakness.

**Decision / proof:** useful **L6c** visual inspiration, not acceptance of a 2,500-triangle budget or any FPS promise. Judge whole-scene cost, foliage variation and ground transitions in our own captures. Forward the grass-composition concern to its owner rather than expanding tree scope. Distance removal must still preserve visible collidable obstacles here.

### X23 — NPS rainforest interpretation: layered canopy and gaps

[NPS Carbon River woodland interpretation](https://www.nps.gov/places/carbon-river-rainforest-trail-crowding-out-competition-exhibit-panel.htm) describes younger shade-tolerant trees beneath the upper canopy and regeneration openings after a tree falls. It supplies a real forest composition reference rather than a game-engine technique.

**Decision / proof:** use **L7-R1** references for height layers, occasional openings and younger growth in appropriate light. Borrow spatial relationships only: this rainforest is not the field's established biome or an instruction to mix its species into the simulator. Link the reference instead of republishing imagery. Qualify overhead crown structure and pilot/approach visibility at unchanged tree count.

### X24 — USFS heterogeneous woodland: groups, individuals and openings

[USFS RMRS-GTR-373 (2018)](https://research.fs.usda.gov/treesearch/55638), [full report](https://research.fs.usda.gov/download/treesearch/55638.pdf), describes landscape heterogeneity including tree groups, scattered individuals, openings, deadwood and riparian patches. Its dry mixed-conifer context differs from the rainforest reference above; these are alternative composition examples, not one combined ecosystem prescription.

**Decision / proof:** sharpen **L7-R1** review around interlocking crown groups, irregular gap sizes and isolated edge trees. First choose a coherent field habitat, then use the matching relationships as art guidance. Keep source images as linked references. Compare deterministic top-down layouts and skyline/pilot captures; more occupied area is not automatically more natural or clearer for flight.

### X25 — Performance-optimization skill: optional review aid

The [gamedev-skills performance-optimization skill](https://www.skills.sh/gamedev-skills/awesome-gamedev-agent-skills/performance-optimization), [source SKILL.md](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/main/skills/disciplines/performance-optimization/SKILL.md), gives a profile–isolate–change–remeasure workflow. Discovery showed about 5.5K installs and 1.6K repository stars, with an [Apache-2.0 repository license](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/main/LICENSE). These are dated popularity observations, not correctness evidence. The directory and `npx --yes skills find godot performance` were checked; source content was reviewed separately.

**Decision / proof:** optional **VQ-01c/L7-R2** review aid, not a dependency or tree asset. Generic advice about batching, pooling and budgets must defer to actual profiling, existing bounded lifetimes, Compatibility limitations and this project's shared budget. It must not change `sim_clock`, simulation state or collision contracts. Installation, only if later selected after revision review: `npx skills add gamedev-skills/awesome-gamedev-agent-skills --skill performance-optimization`. Not run.

## Resulting direction

Use retained extra silhouettes as the inexpensive control and prioritize a small **LOLIPOP Pine + Maple comparison** as the new realistic runtime-source candidate; qualify the exact CC BY files first. Fir/Birch and new bushes are conditional alternatives, not an instruction to load all packs. Keep high-resolution CC0 scans as material/offline references. Improve crown groups, isolated trees, gaps, edges and age/shape mix before population growth. Inspect source vertex/material semantics, supplied LOD selection, mip silhouette retention and actual shadow/pixel cost. Reuse existing validators and tools when needed; defer terrain migration, custom mip pipelines and octahedral tooling until a specific residual defect warrants them. All implementation gates remain pending.
