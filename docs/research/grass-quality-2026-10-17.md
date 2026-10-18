# Grass appearance: source investigation

2026-10-17. Research snapshot for the [grass implementation plan](../plans/grass-quality.md). Source checkout: `f3e1539b3d3716c8715c19ef0a90b38286cbac46`, initially clean. This review inspected current source, retained captures and **44 investigations: the original 20 plus 24 additional investigations** requested in a second round. It did not run a new rendering benchmark, install a plugin or change the application.

## Project findings

| Observed implementation | Consequence for this proposal |
| --- | --- |
| [Project settings](../../app/project.godot) and [engine pin](../../app/get-godot.sh): Godot 4.7.2-stable, Compatibility, 720p default, 4x MSAA. | Evaluate all candidates in this renderer. Forward+ demonstrations are references, not drop-in solutions. |
| [Ground](../../app/render/ground.gd), [grass sampling](../../app/render/grass_surface.gdshaderinc) and [turf detail](../../app/render/turf_detail.gdshaderinc): a 256px procedural base plus packed turf detail; two-offset detiling, explicit gradients, macro variation and footprint/distance filtering already exist. | Do not propose adding these mechanisms as if absent. Investigate scale, contrast and effective sampling first. |
| [RC binder](../../app/render/rc_ground_material.gd) and [detail shader](../../app/render/rc_ground_detail.gdshaderinc) already bind ambientCG Grass001 at 2K, approximately 1.4 m per tile, only in RC activity. | Shared flight/Home adoption is new work. Reuse retained maps and their importer instead of commissioning or generating another texture. |
| [Imported near grass](../../app/scenery/imported_near_grass.gd): quality maxima 38/76/150 clumps, within the pilot's 30 m placement disk; three asset batches; 0.12–0.25 m target heights; shadows off; `PlantLibrary.build(batches, false)`. | This default scenery grass is static. Enabling wind requires material qualification; changing the fallback shader alone will not animate it. |
| [Vegetation catalog](../../app/assets/landscape/vegetation/catalog.json): short/tall/wispy source meshes have 155/326/622 triangles. High-quality maxima are 67/42/41 instances. | The nominal source total is 49,579 triangles, nearly the 50,000 cap. Wispy grass alone contributes 25,502. A density increase needs a different allocation, not an unexplained higher cap. These are source counts, not GPU measurements. |
| [Fallback](../../app/render/near_grass.gd) and [shader](../../app/render/near_grass.gdshader): up to 6,000 candidate clumps before clipping, seven triangles each, four quadrants, fixed-root wind and geometric shrink at 22–30 m. | Keep the two paths separate in evidence. The fallback's fade, wind and seam proof do not establish those properties for imported grass. |

The retained [RC low-orbit image](rc-ground-implementation-2026-10-15/verification/ground-closeup-final3-candidate-720/mt8-bisonte__start__low-orbit__day.png) shows useful near texture detail, a flat ground silhouette and isolated taller plants beyond the maintained area. The historical [L11a image](visual-quality-implementation/L11a/near-after.png) shows the earlier sparse opaque blades over softer turf. These observations concern those captures, not a fresh current-session visual test. Flatness inside the mown area is partly intentional; filling the runway with tall grass would be a regression.

The [RC implementation report](rc-ground-implementation-2026-10-15/README.md) already found no compelling 4K benefit in its limited comparison. It records 21.33 MiB of imported compressed payload across six soil/grass maps, not total VRAM residency. Its timing gate remains **unpassed/inconclusive**, and lower-end qualification is open. That result prevents treating shared phototexture adoption as a free improvement.

## Investigations

All linked primary pages were consulted on 2026-10-17. Official documentation describes APIs; papers describe methods; forum/Reddit posts are firsthand observations or suggestions, not controlled benchmarks for this project. Research IDs R01–R44 are citation keys, not new implementation-step namespaces. Each investigation addresses a distinct source or implementation question; supporting links do not inflate the count.

### R01 — Reuse the right free ground texture

**Source:** [ambientCG Grass001](https://ambientcg.com/view?id=Grass001), released 2021-03-28; [publisher CC0 terms](https://docs.ambientcg.com/license/).

**Finding:** The supplier gives approximately 1.4 x 1.4 m coverage and multiple resolutions. The project already retains this source with hashes and license evidence in its [asset intake](../../assets/landscape/rc-ground/README.md).

**Application/proof:** Compare the existing 2K material with current shared turf at the same physical scale, camera and exposure. Preserve visible blade scale near wheels and landing gear. Only reopen 4K if a specific supported camera demonstrates undersampling; a larger download does not add silhouette.

### R02 — A different grass surface is an art-direction choice

**Source:** [Poly Haven Leafy Grass](https://polyhaven.com/a/leafy_grass), Charlotte Baglioni, CC0, 2 m coverage.

**Finding:** The set includes diffuse, normal and roughness maps, with leaf/twig detail. It offers a different ground character, not inherently better turf.

**Application/proof:** Keep as one conditional rough-margin candidate if Grass001 fails the owner review. Compare actual leaf scale and repeated landmarks. Reject if debris dominates a maintained runway or requires a second full-field material pass. No download is needed until that trigger exists.

### R03 — Existing free geometry has a measurable budget

**Source:** [Quaternius Stylized Nature MegaKit](https://quaternius.itch.io/stylized-nature-megakit), official author page. Standard is the free CC0 download; Pro and Source are separate paid tiers.

**Finding:** Downloadable glTF models already supply this project's short, tall and wispy grass. The source project's stylized appearance may remain visible even with realistic ground textures.

**Application/proof:** Rebalance the existing three species and heights before adding instances. Use the [vegetation pipeline](../../tools/landscape/vegetation/README.md) and retain exact source geometry. Review side/top silhouettes, ground contact and root color at fixed instance/triangle limits; do not assume the paid Godot shader package is included in Standard.

### R04 — A realistic downloadable mesh can be the wrong runtime asset

**Source:** [Poly Haven Grass Medium 01](https://polyhaven.com/a/grass_medium_01), Rico Cilliers/Rob Tuytel, CC0.

**Finding:** The page advertises model formats, textures and LOD-related content, but lists about 7.3 m width and two million source triangles. This is not a lightweight scatter recommendation.

**Application/proof:** Reference-only shortlist unless the existing geometry demonstrably fails. Inspect a supplied low-detail representation before adoption; record actual imported surfaces, triangles, scale and transparency. Reject the full source representation for mass placement. No custom replacement mesh is needed merely because this download is too heavy.

### R05 — Filtering and compression solve different problems

**Source:** [Godot 4.7 image importing](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html).

**Finding:** Mips address minification; texture size should follow screen coverage; GPU compression reduces storage/bandwidth with content-dependent artifacts.

**Application/proof:** Inventory effective mips, format, channel semantics and anisotropy. Compare existing filtering with 8x, then 16x only if needed, on a grazing pan. Preserve packed slope data losslessly unless error is qualified. Test compressed alpha silhouettes separately. Record imported payload and measured residency separately; JPG/ZIP size is neither.

### R06 — Compatibility color handling needs an actual probe

**Sources:** [Godot 4.7 source-color rules](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html#using-source-color), [spatial shader built-ins](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html#global-built-ins).

**Finding:** Color and data samplers have distinct hints; `OUTPUT_IS_SRGB` differs between Compatibility and the other renderers. The existing RC report documents a clipped-color bug from dividing an encoded sample by a linear mean.

**Application/proof:** Preserve the existing renderer-aware normalization. Probe a known swatch and grass root/ground pair under day, dusk and night. Verify effective material overrides, not just a parameter written to an unused material. Do not add another gamma conversion by assumption.

### R07 — Better detiling can cost more than the texture

**Source:** Bart Wronski, [GPU Friendly Laplacian Texture Blending](https://research.nvidia.com/labs/rtr/publication/wronski2025laplacian/), JCGT, March 2025.

**Finding:** The method preserves local contrast using additional lower-mip samples without a precomputed statistics texture. It is an alternative to ordinary blending, not a free detail layer.

**Application/proof:** Continue the already-selected **L9e-R1** comparison on retained maps. Hold texture, scale and lighting fixed; inspect local contrast, repeated structures, distant color and GPU cost. Keep translation-only decorrelation and valid gradients. Reject blotches or excess cost; inspect the downloadable code license before reusing code.

### R08 — Histogram-preserving blending is a deferred alternative

**Sources:** Heitz/Neyret, [HPG 2018 author page](https://eheitzresearch.wordpress.com/722-2/), and Deliot/Heitz, [practical tiling-and-blending follow-up](https://eheitzresearch.wordpress.com/738-2/).

**Finding:** Statistical transforms can preserve texture distributions; the follow-up addresses mip color shifts and compressed data. Preprocessing and additional resources increase integration scope.

**Application/proof:** Defer under the existing global plan. Reconsider only after a failed, documented Laplacian experiment and an updated scope decision. A future comparison must include mip color stability and resource cost. The author pages were readable; the linked HAL PDF encountered an access barrier, so no full-paper verification is claimed.

### R09 — MultiMesh batches need spatial bounds

**Source:** [Godot 4.7 MultiMesh reference](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html).

**Finding:** Instancing reduces submission overhead, but each MultiMesh is a single culling unit. Custom data can vary instances without unique materials; manual bounds can avoid recalculation.

**Application/proof:** Compare current three material batches with a bounded spatial split, counting actual draws and submitted geometry. Expand each AABB for the full wind envelope. Stable quality subsets should keep retained plants fixed. Do not infer individual-instance culling from instancing, or treat shader-hidden geometry as free.

### R10 — Imported LOD and manual fades have different limits

**Sources:** [Godot 4.7 mesh LOD](https://docs.godotengine.org/en/4.7/tutorials/3d/mesh_lod.html#using-mesh-lod-with-multimesh-and-particles), [GeometryInstance3D](https://docs.godotengine.org/en/4.7/classes/class_geometryinstance3d.html).

**Finding:** A MultiMesh selects one mesh LOD for its batch. Visibility-range fade modes require Forward+; Compatibility does not provide the same fade. Per-instance transparency is also not a usable Compatibility fade path.

**Application/proof:** Separate batch culling, mesh LOD, density and the final visual transition. Start with a root-preserving geometry transition and explicit node culling beyond the invisible range. Sweep camera FOV, altitude and range boundaries; inspect disappearing tips, seams and batches held at excessive detail by one near bound.

### R11 — MSAA does not prove alpha-to-coverage support

**Sources:** [Godot 4.7 AA guide](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html), [material guide](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html#alpha-antialiasing), [engine issue 98173](https://github.com/godotengine/godot/issues/98173), [implementation PR 114845](https://github.com/godotengine/godot/pull/114845).

**Finding:** MSAA handles geometric edges, not general shader detail or alpha-test edges. The generic material guide describes alpha-to-coverage, but the Compatibility issue records missing support; the linked January 2026 implementation PR was still **open** when checked. TAA is unavailable in Compatibility.

**Application/proof:** Treat alpha-to-coverage as unavailable until the pinned binary proves otherwise. Run a small scissor/edge-antialiasing toggle at 2x/4x MSAA with edge crops and motion. If unchanged, record unsupported and stop. Keep opaque silhouettes or qualified alpha scissor; do not migrate renderer or pull an unmerged engine patch for grass.

### R12 — Overdraw can outweigh polygon savings

**Sources:** [Godot GPU optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/gpu_optimization.html), [Reddit author's alpha-transparency update](https://www.reddit.com/r/godot/comments/1n2d17w/need_help_for_multimesh_with_alpha_transparency/), August 28, 2025.

**Finding:** Large overlapping transparent areas repeatedly shade pixels. The Reddit author reports improvement from scissor and then a tighter blade-shaped mesh; no transferable controlled benchmark is supplied.

**Application/proof:** Compare source materials, a justified scissor candidate and an existing opaque asset at matched apparent coverage. Vary output resolution to help attribute fill cost. Count texture reads, draws and triangles together; reject a lower-triangle candidate that worsens GPU time or edge crawl.

### R13 — A forum chunking pattern is useful, but not a budget

**Source:** [Godot Forum: grass only around the player](https://forum.godotengine.org/t/how-to-dynamically-render-grass-only-around-the-player/6657), Zylann reply, April 6, 2022.

**Finding:** Nearby grid chunks with separate MultiMeshes permit coarse culling and distance transitions. The discussion predates this engine and provides no target-hardware timings.

**Application/proof:** Consider it only if RC movement exposes the pilot-centered coverage limit. Preserve stable world-cell identities and field exclusions. Measure chunk construction/upload spikes and visible batches during turns and teleports. More chunks can violate the existing five-draw grass gate; keep the simpler placement when it wins.

### R14 — A moving grid must not drag the world

**Source:** [Godot Forum: grass across individual planes, reply 71](https://forum.godotengine.org/t/transmit-grass-across-individual-unique-planes-meshes/141821/71), July 23, 2026.

**Finding:** A suggested shader grid snaps to world cells and hashes those cells for stable transforms; outer rings can use simpler representations. This is a proposal, not measured Compatibility proof.

**Application/proof:** Research-only alternative to CPU chunk updates. Reject any implementation where plants follow the car, reset their random shape at a cell boundary, or leak into tracks/lake masks. Do not move grass to the aircraft's projection during normal fixed-pilot flight. Compare submitted work even when the shader makes instances invisible.

### R15 — A grass demo explains shape, not production readiness

**Source:** [franos-cm/grass-demo](https://github.com/franos-cm/grass-demo), course project 2025.1, tested in Godot 4.4.1; Forward Plus project setting.

**Finding:** The author demonstrates curved blades, recomputed normals, view-dependent thickness, wind and density/mesh LOD, and discusses tile popping.

**Application/proof:** Use it as a shape/normal reference when inspecting the already-downloaded clumps. Near roots should stay planted and bent tips should retain plausible lighting. Do not copy code: no explicit repository license was identified in this review. View-facing thickening is deferred because it can make grass visibly turn during orbit; there is no need to generate a new blade system first.

### R16 — Wind should bend tips without moving roots

**Source:** [Godot 4.7 making trees](https://docs.godotengine.org/en/4.7/tutorials/shaders/making_trees.html).

**Finding:** The tutorial uses a spatially weighted vertex sway and discusses backlighting. Its complete material example is not proof that every feature works identically in Compatibility.

**Application/proof:** On imported grass, derive a normalized root-to-tip coordinate from source bounds, preserve existing texture UVs and weight displacement toward the tip. Reuse the project's `wind_vec` and `sim_clock`, with exact calm, pause/reset and clock-wrap checks. Do not enable unsupported subsurface scattering or substitute wall-clock `TIME` for the deterministic clock.

### R17 — A fast GPU still needs workload attribution

**Source:** [Reddit: Grass is EATING performance](https://www.reddit.com/r/godot/comments/1vm5ntn/grass_is_eating_performance/), August 12, 2026.

**Finding:** The poster reports a large grass-on/off cost on a Radeon 880M and little change after removing wind. The thread does not isolate a universal bottleneck.

**Application/proof:** Run separate grass-hidden, constant-material, wind-off and reduced-density ablations. Collect CPU/GPU time where available, resolution scaling and actual submissions. Choose the next optimization from those measurements. Do not quote the author's FPS as a target or assume shader arithmetic is the limiting factor.

### R18 — A flight-simulator example supports bounded near detail

**Sources:** [Reddit hang-gliding simulator author post](https://www.reddit.com/r/godot/comments/1wzwaqd/wind_over_real_terrain_computed_on_the_gpu_with/), October 7, 2026; [linked project](https://github.com/thegriglat/deltaplan).

**Finding:** The author describes camera-near grass, thinning at the edge and matching grass color to terrain. Their GPU timing is self-reported; their compute-based wind solution is not a Compatibility dependency we can adopt.

**Application/proof:** Keep far-ground appearance in the surface material and spend geometry where blades are visible. Compare color and apparent coverage across the transition during low passes. Reuse the existing wind service instead of introducing GPU wind simulation. Height/radius scaling remains conditional on a demonstrated camera need.

### R19 — A foliage library is an authoring decision

**Sources:** [Spatial Gardener repository](https://github.com/dreadpon/godot_spatial_gardener), [release history](https://github.com/dreadpon/godot_spatial_gardener/releases), [Godot Asset Library entry](https://godotengine.org/asset-library/asset/2037).

**Finding:** The MIT plugin supports painting vegetation/props for finite scenes. The inspected release is v1.4.1-stable, March 5, 2025, targeting Godot 4.4. This does not establish 4.7.2 Compatibility qualification.

**Application/proof:** Defer installation: deterministic placement and exclusions already exist here. If manual habitat painting becomes a real requirement, pin that exact release/commit in a disposable editor project and verify save/reopen, placement export, LOD, native package and Compatibility rendering. Reject a plugin that bypasses authoritative masks or requires a second runtime scatter system.

### R20 — Root shading must agree with the ground without flattening the plant

**Sources:** the lighting/normal discussion in [franos-cm's author demo](https://github.com/franos-cm/grass-demo), [Godot spatial shader coordinate contract](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html), and the project's [near-grass shader](../../app/render/near_grass.gdshader).

**Finding:** The fallback deliberately forces upward normals to match ground lighting. Imported grass retains its source materials. These are different approaches, so a dark seam or flat highlight cannot be diagnosed from albedo alone.

**Application/proof:** Compare source normals with a conservative root-only blend toward terrain normal while retaining blade normals near tips. Add only subtle, static root darkening if needed; grass shadows stay off. Test front/back lighting, noon, low sun and night. Reject glowing tips, uniformly flat lighting or a dark ring at the fade boundary.

## Second round: 24 additional investigations

R21–R30 examine technical methods, import contracts and measurement; R31–R38 examine four tools and four additional asset sources; R39–R44 examine three Godot Forum discussions and three Reddit discussions. None repeats a first-round investigation as a new entry. Related topics add a new mechanism, failure case or verification method. **Probe** means an isolated experiment only after its trigger; **defer/reference** does not authorize a new production dependency.

Two additional local findings shape the recommendations. The [vegetation material adapter](../../app/scenery/imported_vegetation.gd) copies selected albedo, UV, vertex-color, scalar roughness/metallic, normal-map and alpha-scissor properties; it is not a general lossless conversion of every source material. The [wind shader](../../app/scenery/imported_vegetation_wind.gdshader) fixes its own culling/filtering behavior. Missing properties are not automatically defects: inventory what the selected grass actually uses, then compare source material against zero-amplitude wind material. Also, [grass placement generation](../../tools/grass/place.py) already has a deliberately nonuniform radial density, approximately 1/r outside its central cap. A uniform blue-noise replacement would change that design.

### R21 — Progressive sample elimination can improve sparse quality subsets

**Sources:** Cem Yuksel, [Sample Elimination for Generating Poisson Disk Sample Sets](https://www.cemyuksel.com/research/sampleelimination/), 2015; author's [progressive sampling implementation guide](https://www.cemyuksel.com/cyCodeBase/soln/poisson_disk_sampling.html).

**Finding:** Weighted sample elimination selects a desired-size subset from candidate points; progressive ordering supports useful prefixes. It does not guarantee maximal coverage. Sampling a masked, nonuniform domain requires more care than applying a uniform bounding-box example.

**Decision/proof — conditional probe, L11a-R1:** If lower profiles show accidental holes, compare offline ranking of existing eligible rows with current selection. Preserve the radial density, habitat masks and stable identities; stratify the comparison by radial band. Check nested quality subsets, nearest-neighbor distributions, visible holes and deterministic output hashes. Do not claim a global Poisson distribution after stratification or add a runtime C++ dependency.

### R22 — Normal composition differs from material interpolation

**Source:** Colin Barré-Brisebois and Stephen Hill, [Blending in Detail](https://blog.selfshadow.com/publications/blending-in-detail/), July 10, 2012.

**Finding:** Naively averaging detail normals can flatten both contributions. Reoriented Normal Mapping composes a detail normal with a base surface normal; it addresses a different operation from interpolating alternative material samples.

**Decision/proof — conditional probe, L9e-R2:** Only evaluate RNM if the chosen design actually stacks two normal layers. Keep existing stochastic-sample interpolation separate. Verify flat-map identity, detail-disabled identity, both light directions and grazing response. Compare shader cost and reject exaggerated relief. The historical shader instruction counts are not estimates for this OpenGL target.

### R23 — Alpha mipmaps can remove blades without a geometry bug

**Sources:** Lisyarus, [Exploring ways to mipmap alpha-tested textures](https://lisyarus.github.io/blog/posts/exploring-ways-to-mipmap-alpha-tested-textures.html), January 5, 2025; Ignacio Castaño, [Computing Alpha Mipmaps](https://www.ludicon.com/castano/blog/articles/computing-alpha-mipmaps/).

**Finding:** Averaging alpha can push thin features below the cutout threshold. Coverage-preserving mip alpha scaling addresses that loss; filtered RGB at transparent borders and neighboring atlas cells can independently create fringes.

**Decision/proof — adopt diagnosis, defer custom importer:** For any card challenger, inspect mip levels, alpha coverage and border colors at the actual cutoff. Use distance sweeps and a no-mip diagnostic control, retaining motion evidence. Disabling mips is not the production fix; it can restore blades while introducing shimmer. Prefer existing importer settings or a better free source. The global plan explicitly excludes a custom mip importer from the initial slice; premultiplied filtering does not imply changing runtime blending to premultiplied transparency.

### R24 — Main bend and detail flutter need different constraints

**Source:** Tiago Sousa, Crytek, [GPU Gems 3, Chapter 16: Vegetation Procedural Animation and Shading in Crysis](https://developer.nvidia.com/gpugems/gpugems3/part-iii-rendering/chapter-16-vegetation-procedural-animation-and-shading-crysis), 2007.

**Finding:** The author separates whole-plant bending from local detail motion and limits stretching after main deformation. Height, stiffness and phase encode different behavior; vertex colors are an example storage choice, not a universal contract.

**Decision/proof — use as L15c design reference:** Begin with the existing low-amplitude root-weighted wind. If stretching is visible, compare a bounded bend correction before adding flutter. Track root displacement, tip reach and yaw/scale invariance. Preserve source vertex colors used for albedo; do not overwrite them with stiffness. Historic performance claims and Crysis material settings do not establish Compatibility results.

### R25 — Coverage compensation is transferable; mesh shaders are not

**Source:** AMD GPUOpen, [Procedural grass rendering with mesh shaders](https://gpuopen.com/learn/mesh_shaders/mesh_shaders-procedural_grass_rendering/), March 20, 2024.

**Finding:** The example uses curved blades, fractional blade counts and width compensation to reduce apparent coverage changes during LOD. Its mesh-shader pipeline is outside the project's OpenGL Compatibility architecture.

**Decision/proof — reference only, L11a-R2:** If a qualified density transition exposes a visible band, compare a small, bounded coverage adjustment using existing representations. Do not widen clumps automatically: it may destroy silhouette, increase overlap or breach exclusion clearances. Measure apparent coverage and temporal stability through the transition. No mesh-shader port, renderer migration or generated replacement blade library is proposed.

### R26 — Frame captures can identify the material actually submitted

**Source:** [RenderDoc repository and supported API list](https://github.com/baldurk/renderdoc), MIT.

**Finding:** RenderDoc captures graphics API state and supports OpenGL core on Windows/Linux. It can inspect a frame independently of what the application intended to bind. This is not a macOS/Metal capture recommendation.

**Decision/proof — optional diagnostic, VQ-02a:** If Godot material readback and rendered output disagree, capture a fixed grass frame and inspect actual draws, bound textures and shader state. Record tool version and preserve a grass-hidden control. Keep capture/replay outside timed runs; replay timing does not establish normal application frame time. Existing native evidence remains required on unsupported capture platforms. No tool was installed for this review.

### R27 — glTF material contracts expose incomplete shader adapters

**Source:** Khronos, [glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html).

**Finding:** glTF distinguishes opaque, mask and blend modes; masked alpha cutoff defaults to 0.5. Metallic/roughness use B/G channels respectively. Double-sided lighting reverses back-face normals; disabling culling alone is not equivalent. Units, normal data and vertex colors also have defined semantics.

**Decision/proof — adopt intake checklist, VQ-02a/L15c:** Record source → imported material → wind adapter for each property actually used. Inspect UV transforms, texture channels, alpha, vertex color, normal scale and face behavior. Zero-amplitude wind should preserve the accepted source appearance, except separately approved corrections. This specification guides inspection; it does not guarantee identical Godot import/shader output. Do not expand the shared adapter to support unused features.

### R28 — Open terrain is a poor default target for occlusion culling

**Source:** [Godot 4.7 occlusion culling guide](https://docs.godotengine.org/en/4.7/tutorials/3d/occlusion_culling.html).

**Finding:** Occlusion testing has CPU cost and works best when substantial bounds are fully hidden. Transparent meshes and MultiMesh instances do not become baked occluders through the normal bake path. An open field may offer little useful occlusion.

**Decision/proof — defer:** Do not add occluders per tuft or enable a field-wide occlusion system for grass. If existing pit buildings hide enough grass batches, test their existing occluder setup with deformed bounds and CPU/GPU attribution. Accept only a measured gain without missing grass at building edges. Frustum/range bounds and controlled submission remain the first tools.

### R29 — Compatibility shader warmup needs actual drawing

**Source:** [Godot 4.7 pipeline compilation guide](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html).

**Finding:** Forward+/Mobile pipeline precompilation and ubershader mechanisms do not apply to Compatibility. Its older warmup method requires rendering the relevant material in view for at least one frame; loading a resource alone is insufficient.

**Decision/proof — conditional loading experiment:** Only if first grass visibility produces a reproduced compile stall, coordinate bounded rendering during loading with the global loading owner. Match relevant material/render state and record cold/warm readiness and first-use spikes. Hidden nodes do not prove warmup. Preserve cancellation, scene isolation and readiness gates; do not add speculative warmup for every downloaded asset or claim the shader baker fixes OpenGL startup.

### R30 — Counter units can invalidate a performance conclusion

**Source:** [Godot 4.7 Performance reference](https://docs.godotengine.org/en/4.7/classes/class_performance.html).

**Finding:** Some monitors are debug-only or delayed; FPS updates are not a per-frame time series. The rendered-primitives counter describes submitted vertices/indices and can count geometry repeatedly across passes. It is not interchangeable with authored triangle count.

**Decision/proof — adopt measurement contract, VQ-01c:** Store counter name, unit, build mode, cadence and availability with results. Compute frame percentiles from raw frame durations. Keep the 50,000 source-triangle cap separate from the existing 100,000 rendered-primitives delta gate, and reproduce that gate's original harness semantics. Treat unsupported zero counters as unavailable. Separate compressed asset payload, engine allocation estimates and driver residency; none proves the others.

### R31 — ProtonScatter is an editor candidate with separate asset terms

**Sources:** [ProtonScatter Asset Library entry](https://godotengine.org/asset-library/asset/1866), listing version 4.1 for Godot 4.1, January 2, 2026; [author repository](https://github.com/HungryProton/scatter).

**Finding:** The MIT tool supplies procedural, non-destructive scattering and domain/modifier workflows. The demo's texture redistribution terms differ from the plugin's MIT code; bundled content is not automatically an unrestricted asset pack.

**Decision/proof — conditional authoring probe:** Use only if repeated manual habitat editing becomes a demonstrated need. Pin a commit and verify deterministic transforms, save/reopen and export in 4.7.2 Compatibility. Export through the project's existing placement/mask contract; do not introduce a second runtime scatter authority. Keep demo textures out of asset intake unless their own redistribution terms are satisfied. No 4.7.2 qualification is inferred from the catalog entry.

### R32 — SimpleGrassTextured has relevant renderer history, not a free pass

**Sources:** [IcterusGames/SimpleGrassTextured](https://github.com/IcterusGames/SimpleGrassTextured), MIT; [release history](https://github.com/IcterusGames/SimpleGrassTextured/releases).

**Finding:** The inspected latest release is v2.1.0. Release v2.0.7 added Compatibility support; v2.0.10 applied a distance-optimization fix; v2.1.0 fixes custom-mesh runtime/material issues. These are useful regression cases for a grass tool, not evidence of target-hardware speed.

**Decision/proof — isolated reference/probe:** If the existing authoring path cannot meet a named requirement, pin v2.1.0 and its resolved commit in a disposable project. Test custom mesh/material, distance optimization on/off, save/reopen, shutdown and native export using 4.7.2 Compatibility/4x MSAA. Disable interaction features outside scope. Keep production on existing placement unless an explicit cost/maintenance comparison favors adoption.

### R33 — Terrain3D foliage is coupled to a larger terrain choice

**Sources:** [Terrain3D releases](https://github.com/TokisanGames/Terrain3D/releases), inspected v1.0.2-stable; [author's foliage-instancing guide](https://github.com/TokisanGames/Terrain3D/blob/main/doc/docs/instancer.md).

**Finding:** The release advertises Godot 4.4–4.7 support and a Compatibility shader fix. Its instancer accepts cards and imported meshes, but does not supply a general wind/interaction shader. The documented large instance counts are not this simulator's benchmark.

**Decision/proof — defer:** A new terrain GDExtension is not justified by grass decoration alone. If terrain ownership independently selects it, qualify one card and one mesh against existing height/mask/contact contracts, then export and profile the exact binary. Do not infer vegetation quality or frame-time headroom from engine-version compatibility.

### R34 — An older scatter tool is a useful rejected option

**Sources:** [Zylann Scene Scattering Tool](https://github.com/Zylann/godot_scatter_plugin), MIT; [Godot Asset Library author catalog](https://godotengine.org/asset-library/asset?filter=zylann&sort=updated).

**Finding:** The inspected listing identifies v1.0.1 for Godot 3.1, dated September 25, 2019. Scene painting over colliders is a useful workflow, but the listing does not establish a Godot 4 release.

**Decision/proof — reject direct adoption:** Do not spend the grass slice porting a legacy editor plugin when modern free candidates and an existing deterministic pipeline are available. Reconsider only with a separately verified maintained Godot 4 version and a real authoring need. Parsing, painting, persistence and export would all need qualification; visual similarity of the editor UI is insufficient.

### R35 — A realistic grass atlas is a conditional silhouette challenger

**Source:** Lucas Anton Gomez, [3DTexel Wild Grass Green Atlas](https://3dtexel.com/product/wild-grass-green-atlas/), publisher-listed CC0; free download requires login/registration.

**Finding:** The asset supplies albedo, normal and opacity images at offered 2K/4K resolutions. It is a cutout atlas, not a seamless turf material or ready-made Godot plant.

**Decision/proof — conditional asset probe:** If retained opaque clumps fail the near-silhouette review, test this atlas on suitable freely downloadable card geometry through the existing source pipeline. Inspect UV fit, border fringes, mip coverage, back faces and silhouette under 4x MSAA. Retain 2K first and compare equal apparent coverage. Reject if source geometry is unsuitable or alpha stability/cost loses to the existing opaque plants; do not fabricate a new asset merely to use the atlas.

### R36 — Clover adds habitat specificity, not a replacement grass layer

**Source:** Lucas Anton Gomez, [3DTexel Clover Leaf Atlas](https://3dtexel.com/product/clover-leaf-atlas/), publisher-listed CC0; account required for the free download.

**Finding:** This separate atlas provides leaves/stem imagery with albedo, normal and opacity. It supplies neither a finished 3D clump nor evidence of local botanical accuracy.

**Decision/proof — defer until habitat review:** Consider only sparse rough-margin accents if a specific field reference supports them. Use suitable existing/free geometry and the same import/alpha qualification as grass cards. Verify physical leaf scale, variation and total batch/triangle budget. Do not add an independent full-field layer, another mandatory draw or clover to the mown runway merely to increase asset variety.

### R37 — Photorealistic Bermuda grass exceeds the entire geometry cap

**Source:** [Poly Haven Grass Bermuda 01](https://polyhaven.com/a/grass_bermuda_01), CC0 model.

**Finding:** The page lists approximately 224,000 triangles and 3.1 m width, with multiple model formats and PBR maps. One full-detail instance already exceeds the project's 50,000-triangle allowance for all imported near grass.

**Decision/proof — reference only:** Use the publisher's silhouette/material presentation as a reference, not blanket scatter or an unbudgeted hero clump. Only reopen runtime intake if an available lower-detail representation fits the total cap after actual import. Count surfaces, triangles, texture payload and alpha behavior; a free download or a smaller ZIP does not make the rendered asset inexpensive.

### R38 — A small GLB is a plausible control, not measured low cost

**Source:** [Innerscene Grass tuft medium](https://www.innerscene.com/tools/library/3d-parts/low-poly-nature-grass-tuft-medium-bad03f50), distributor-listed CC0, added October 7, 2026.

**Finding:** The listing offers a roughly 13 KB GLB, embedded materials and approximately 0.4 m dimensions. It does not publish a triangle count or claim Godot compatibility; it also gives an availability end date.

**Decision/proof — conditional low-poly control:** If retained silhouettes fail, inspect this downloadable clump before authoring another. Record source/provenance, file hash, actual topology, material modes, grounded bounds and imported scale. Compare its shorter scaled version against retained Quaternius plants in the same scene. Small download size is not a triangle, draw or visual-quality guarantee. Archive intake evidence only if the candidate is actually downloaded.

### R39 — World wind can accidentally rotate with the model

**Source:** [Godot Forum: World_vertex_coords problem](https://forum.godotengine.org/t/world-vertex-coords-problem/69942), July 2024, Godot 4.3 beta.

**Finding:** The author reports local-space wind changing with model rotation, then position distortion while experimenting with world coordinates. Their eventual approach converts a world direction into local space. This is firsthand debugging, not proof that its matrix code handles every scale convention.

**Decision/proof — adopt regression case, L15c:** Compare identical grass at the origin and at translated, 90/180-degree-yawed and supported uniformly scaled placements under one world wind. Assert fixed roots, consistent world bend direction and bounded displacement. Test the actual parent/instance transform chain. Do not substitute a transpose for a true inverse under arbitrary nonuniform scale; either support that case explicitly or reject it at intake.

### R40 — Equal albedo does not mean equal ground lighting

**Source:** [Godot Forum: Trying to replicate T3ssel8r grass shader](https://forum.godotengine.org/t/trying-to-replicate-t3ssel8r-grass-shader/123816), October 1, 2025, Godot 4.4-stable.

**Finding:** The author reports different grass/ground appearance with the same green color, particularly under an OmniLight3D. Adapting their toon-lighting logic made the basic effect work; remaining art tuning was unresolved. This toon example is not a prescribed PBR fix.

**Decision/proof — adopt diagnostic, L11a-R1:** Before tint compensation, compare effective lighting functions, normals and render modes under fixed directional and local lights. Include RC headlights/night. Accept consistent contact lighting while retaining blade shape. Do not force unshaded grass or bake one lighting condition into albedo to hide a mismatch.

### R41 — Shadow casting and receiving require separate checks

**Source:** [Godot Forum: MultiMeshInstance3D QuadMesh texture not affected by shadow](https://forum.godotengine.org/t/multimeshinstance3d-quadmesh-texture-not-affected-by-shadow/121800), September 2025, Godot 4.4.

**Finding:** The author reports grass remaining bright beneath an occluder. The posted shader combines alpha/depth settings, deformation and forced upward normals. The thread offers no confirmed solution, so it does not establish an engine bug or a fix.

**Decision/proof — adopt diagnostic if a mismatch appears:** In a small control, vary deformation and normal handling independently under one light and occluder. Check receiving shadows with normal source materials and the wind adapter. The project disables grass shadow casting; that does not justify ignoring incorrect received lighting. Preserve casting policy, and reject a candidate that introduces bright clumps beneath otherwise shadowed ground.

### R42 — Reddit's no-mip workaround is a diagnostic, not a shipping policy

**Source:** [Reddit: Transparency vs Alpha Scissors?](https://www.reddit.com/r/godot/comments/knb3yw/transparency_vs_alpha_scissors/), original Godot 3-era discussion with later 4.0/4.2.2 comments.

**Finding:** The original poster reports alpha/depth-prepass artifacts. A later commenter associates distant disintegration with mips and suggests disabling them. Neither the old timings nor that suggestion isolate a general Godot 4.7.2 cause.

**Decision/proof — adopt A/B control for R23:** Sweep a fixed cutout through distance and angle, changing one of mips, threshold or depth settings at a time. Compare missing-blade coverage and moving-edge shimmer together. Preserve mips in the accepted solution unless a separate evidence-backed exception passes all supported views. MSAA alone is not evidence of stable alpha coverage.

### R43 — Random card yaw can expose alternating light and dark clumps

**Source:** [Reddit: Porting a free grass shader from Unity to Godot 4](https://www.reddit.com/r/godot/comments/1vyrtpe/godot_porting_a_free_grass_shader_from_unity_to/), August 26, 2026; exact engine/renderer unspecified.

**Finding:** The author describes root-weighted motion, travelling gusts and tip detail. A commenter identifies alternating lighting; the author attributes it to randomized card orientation and plans a normal fix. Their low-cost claim is not a controlled benchmark.

**Decision/proof — adopt lighting regression case:** With fixed scatter seeds, orbit the camera and rotate the light around front/back faces before qualifying a card or wind material. Compare source normals and a limited root correction; retain tip shape. Do not copy unverified shader code or force every normal upward. Profile any extra gust/detail work independently.

### R44 — A smooth distance fade does not prove less submitted work

**Source:** [Reddit: MultiMesh grass chunk smoothly fading for distance culling](https://www.reddit.com/r/godot/comments/1k8p1g8/i_finally_got_multimesh_grass_chunk_to_smoothly/), April 26, 2025; engine version unspecified.

**Finding:** The post demonstrates a vertex transition. A comment supplies a separate vertical-sink approach and an informal cost observation; that snippet is not the original author's implementation. The discussion does not prove reduced GPU submission.

**Decision/proof — reference/control, L11a-R2:** Compare the planned root-preserving transition with the original hard boundary in forward, reverse and lateral motion. Detect sinking bases, a moving band and pop at eventual batch removal. Measure submitted work separately. Keep a visually successful fade only within budget; call it a culling optimization only when actual batch removal saves measured work.

## Decisions carried into the plan

Reuse the retained 2K Grass001 and free Quaternius geometry. Qualify shared ground appearance first; then address imported-grass silhouette/placement, bounded transitions and wind as separate changes. The second round adds source-to-wind material fidelity, alpha-mip diagnosis, transform/lighting controls, optional subset ranking, a constrained free-asset shortlist and explicit measurement semantics. The [plan's experiment queue](../plans/grass-quality.md#9-second-round-decisions-and-experiment-queue) maps these findings to existing owners and triggers. Preserve far-field tone and runway readability. No wholesale vegetation plugin, compute pipeline, shell-grass stack, parallax occlusion, tessellation, new terrain collision or renderer migration is justified by this review.

Inigo Quilez's original [texture repetition article](https://iquilezles.org/articles/texturerepetition/) could not be fetched in this session. The local shader already documents its two-offset influence; this inaccessible page is not counted among the 44 investigations. No runtime gains, current visual acceptance or physical realism are claimed by this research.
