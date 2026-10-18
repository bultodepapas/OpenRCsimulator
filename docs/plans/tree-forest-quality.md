# Tree and forest realism improvement plan

2026-10-17. **Status: proposed; no runtime changes, new asset integration or performance acceptance.** Owner: landscape **L**, coordinated with **SC/LU**, **VQ**, **M5**, **FW/TOD** and **RCV**. [Dated research and source audit](../research/tree-forest-quality-2026-10-17.md).

Improve tree silhouettes, bark and foliage materials, natural color variation, woodland composition and perceived density from pilot, chase and ground cameras. Use existing or freely downloadable trees and textures. **Do not model trees, generate new tree geometry, paint replacement tree textures or build a tree-authoring tool.** Importing, validating, converting and baking representations of licensed downloaded models are integration work; source assets remain intact.

The recommended first delivery compares the current three-tree family with additional shapes already present in the retained CC0 archive, plus a separate realistic-source comparison. Improve woodland composition at the existing count before increasing population. Select a coherent visual family from actual Godot captures; retaining stylized sources is a low-cost control, not proof of photorealism.

The [global visual/performance plan](global-performance-visual-quality.md) owns shared budgets and sequencing. This plan refines existing L6c/L15b and optional L8, and registers follow-ups in the [landscape registry](../LANDSCAPE-PLAN.md). The [grass plan](grass-quality.md) owns turf and grass; coordinate shared vegetation materials, habitat masks and ground transitions there.

## 1. Starting point and file ownership

The current implementation already contains two distinct tree systems. Details and current-source qualifications are in the [audit](../research/tree-forest-quality-2026-10-17.md#current-project-findings).

| System | Current behavior | Consequence for this plan |
| --- | --- | --- |
| Field treeline | 480 trees at 270–570 m and 1,200 farther trees at 600–1,500 m; eight sector MultiMeshes, six triangles per tree, three shapes in one 1024² atlas | Preserve this inexpensive control. More convincing silhouettes and placement may help before adding geometry. Eight draws describe the treeline main-pass contract, not the whole scene. |
| Imported scenery trees | `CommonTree_1`, `CommonTree_3`, `Pine_1`; 6,265 / 3,505 / 3,947 source triangles, two material surfaces each, automatic imported LODs | Already-downloadable 3D assets are integrated. Measure source parts, surface submissions, shadows and batch extent before replacing or multiplying them. |
| Variation | Field cards use three identities, 12–25 m heights, yaw and bounded tint; scenery aliases select the same three source models | Variation exists, but changing tint alone cannot create new branch structure, crown gaps or age classes. |
| Placement/contact | Field loader caps treeline positions at 1,680. Collision proxies derive from field identity and imported placement dimensions | Moving trees or changing crown envelopes can change the physical world. Treat those changes separately from material-only comparisons. |
| Wind | Field cards consume shared `wind_vec`/`sim_clock`; interactive flight supplies session wind. Main imported scenery calls `build()` with wind disabled | Preserve the working card route; investigate imported-tree motion as a separate change. Older comments saying all production tree wind is zero are stale. |

| Owned area | Existing paths / owner coordination |
| --- | --- |
| Far trees and atlas | [treeline](../../app/render/treeline.gd), [shader](../../app/render/treeline.gdshader), [identity](../../app/render/tree_identity.gdshaderinc), [asset factory](../../app/render/tree_assets.gd), [tree pipeline](../../tools/trees/README.md); L/VQ |
| Imported sources/materials | [vegetation pipeline](../../tools/landscape/vegetation/README.md), [catalog](../../app/assets/landscape/vegetation/catalog.json), [library](../../app/scenery/imported_vegetation.gd), [placement](../../app/scenery/vegetation_placement.gd), [scenery assembly](../../app/scenery/scenery.gd); SC/LU |
| World layout and contacts | [field loader](../../app/data/field_loader.gd), [placement generator](../../tools/trees/place.py), [collision world](../../app/scenery/collision_world.gd); coordinate L/SC/LU and simulation owners |
| Weather/time | [shader clock](../../app/render/shader_clock.gd), existing tree-wind include and imported vegetation wind shader; M5 owns weather, FW/TOD owns lighting |
| Ground/understory | Existing botanical habitats, shrubs, reeds and grass. Reuse their sources and exclusions; grass/RC owners retain terrain materials and vehicle-clearance rules. |

Preserve unrelated work. All candidates begin outside `app/`; integrate only parsed, licensed and reproducible derivatives. No changes to the shared simulation kernel, vehicle models or aircraft physics are needed for tree rendering.

## 2. Resource shortlist and intake order

The [research](../research/tree-forest-quality-2026-10-17.md#free-assets-and-licensing) records sources, licenses, limitations and inspection scope. Free price, source availability and permission to redistribute raw files are separate checks.

| Priority | Resource | Intended use / decision |
| --- | --- | --- |
| 1 | Retained [Quaternius Stylized Nature MegaKit Standard](https://quaternius.itch.io/stylized-nature-megakit) | Extract and preview `CommonTree_2`, `CommonTree_4`, `Pine_2`, `Pine_3` beside current sources; optionally one sparse dead-tree variant. These exact glTF members already exist locally. Use the archived CC0 license, not a blanket assumption about current Quaternius products. |
| 2 | [Poly Haven Pine Tree 01](https://polyhaven.com/a/pine_tree_01) and [Pine Forest collection](https://polyhaven.com/collections/pine_forest) | Realistic conifer reference/source for a baked far-tree comparison. Pine Tree 01 advertises 17M triangles: keep the full source out of runtime. Prefer supplier LODs if present; inspect actual files before making any LOD claim. |
| 2, separate reference | [Poly Haven Jacaranda Tree](https://polyhaven.com/a/jacaranda_tree) | Realistic broadleaf/material benchmark with glTF and a LOD tag; listing says 312K triangles. Not approved for mass placement or as a near-tree default. Keep it out of a temperate species mix unless the chosen field setting supports it. |
| 3 | [ambientCG Bark 001](https://ambientcg.com/view?id=Bark001), [Poly Haven Forest Floor](https://polyhaven.com/a/forest_floor) | CC0 bark and leaf-litter materials. Test only where existing UVs, species appearance and ground ownership fit. Prefer the model's matching original textures; a bark swap is not automatically an improvement. |
| Reserve | [KayKit Forest Nature FREE](https://kaylousberg.itch.io/kaykit-forest) | Lightweight CC0 stylized alternative for constrained hardware/reference. Paid recolors/EXTRA content are excluded. Not the first choice for increased realism. |
| Far-view reserve | [klamtii Tree Sprites](https://klamtii.itch.io/tree-sprites) | Existing review retains 30 rendered views and permissive custom license evidence. Useful silhouette comparison; baked lighting and lack of 3D parallax limit dynamic day/night and aerial use. Not CC0. |

No newly researched pack is yet qualified here as a realistic, lightweight, redistributable drop-in forest. The practical approach is source selection plus measured integration, not a promise that any free download is game-ready. Unclear-license libraries remain research leads, not dependencies.

For each selected intake, retain URL, creator, retrieval date, exact archive/file SHA-256, license text, asset IDs, units, source bounds, texture channels, material/part counts and source/supplied-LOD triangle counts. Separate tool licenses from model/texture licenses. Store sources in the existing landscape source pipeline and export only required runtime derivatives with notices. Pin exact tool versions or commits when adopting them; this plan installs nothing.

## 3. Visual specification

**Coherent woodland.** Start with the current mixed broadleaf/conifer setting. Choose 4–6 distinguishable crown forms for the first comparison: broad/spreading, upright/narrow, irregular/open, and two conifer profiles. Add young growth and occasional deadwood only where suitable supplied assets exist. Generic `CommonTree` assets are shape variants, not identified botanical species. The first objective is a believable family at a consistent level of detail; do not mix cartoon crowns, scanned bark and unrelated tropical species indiscriminately.

**Shape before recolor.** Use actual downloaded variants for different branching, crown density and maturity. Apply stable yaw and modest uniform size variation around each selected asset's intended age/height class. A small scaled mature tree is not necessarily a convincing sapling. Preserve grounded pivots and trunk thickness; avoid extreme nonuniform scaling or rotations that lean trees unnaturally.

**Color with structure.** Establish species/shape palettes from neutral-lit source comparisons: restrained yellow-green, olive, cool green and dark conifer tones. Use one broad patch tint plus a smaller per-tree variation, stable in world space. Initial comparison ranges may use approximately ±5% foliage value and a few degrees of hue; these are art hypotheses, not calibrated reflectance. Tint leaves independently of bark using supplied material IDs/maps. A derived atlas mask is conditional on reproducible baking from those original material IDs, without hand painting. The current atlas test `red > green` is not a reliable universal leaf/bark classifier for new sources or autumn colors.

**Materials.** Preserve albedo/alpha, normal and roughness maps actually supplied. Use correct color/data imports, appropriate normal-map convention, leaf alpha edges and source physical scale. Compare 1K/2K maps before considering 4K; more resolution does not cure flat crowns. Keep trunks opaque, leaf cards scissored where suitable, leaf normals credible on both sides, and roughness matte enough to avoid plastic highlights. Use bounded backlighting only after front/back/noon/dusk/night comparisons. Do not depend on Forward+-only subsurface scattering.

**Near-to-far consistency.** A model and its card must match height, pivot, overall shape, mean color, apparent foliage coverage and directional-light response. Extend the existing unlit source bake and alpha-border/mip checks; no sun should be baked into albedo. A larger atlas is conditional: retaining six 512² views cannot fit the current four-tile layout unchanged. Measure a candidate 2048² layout against the 1024² control, including actual GPU residency, export size and bleed at every mip. Use silhouette coverage tests so reducing foliage to nothing cannot pass alias checks.

Expanding beyond three card variants requires a coordinated catalog/validator, CPU/GPU identity, UV-layout, crown-parameter and collision-mapping revision, not just a replacement PNG or a different modulo. Preserve the original identities in the control fixture. The current four custom-data channels carry exact position bytes through Compatibility's reduced-precision instance path; do not overwrite them with unchecked variant/phase data. Reuse the real-renderer identity readback tests when changing the layout.

## 4. Forest composition and density

Use **patches, gaps and habitat transitions**, then controlled sampling within them. Pure uniform randomness or a uniformly spaced Poisson field can still resemble a plantation. [Bridson's sampling method](https://www.cs.ubc.ca/~rbridson/docs/bridson-siggraph07-poissondisk.pdf) provides minimum spacing; [Deussen et al.'s ecosystem research](https://graphics.uni-konstanz.de/publikationen/Deussen1998RealisticModelingRendering/Deussen1998RealisticModelingRendering.pdf) motivates spatially structured populations. This plan borrows distribution ideas only, not plant modeling or a growth simulation.

1. Define a small number of irregular woodland areas with a dominant tree family, denser cores, lighter margins and deliberate clearings. Break the repeated equal-radius cluster outline without filling the protected flight gaps.
2. Sample stable world-space candidates using a fixed seed and spatial neighbor lookup. Use crown/age-aware minimum spacing, allowing plausible canopy overlap while preventing coincident trunks. Reuse the placement pipeline; avoid rejection loops with unbounded retry counts.
3. Make a transition from mature canopy to small trees, shrubs and existing grass/herbs at the edge. Coordinate leaf-litter patches beneath canopy with the grass owner; do not put decorative grass uniformly inside dense shade or blanket every shoreline with trees.
4. Preserve runway/mown areas, approaches, pilot sightlines, paths, lake exclusions and RC courses using authoritative predicates and full crown/wind envelopes. Distance to the pilot alone is not a sufficient exclusion. Current landscape relief is not an authoritative tree-ground heightfield.
5. First compare **the same total of 1,680 field trees** with different grouping. Report local stems per hectare of eligible area, nearest-neighbor distribution, canopy occupancy and skyline gaps; whole-map count alone hides empty or overcrowded patches. Population values are artistic design parameters, not ecological measurements.
6. Only if the new layout remains visibly sparse and timing allows it, compare bounded increments, initially +25% and then +50%, one at a time. These are experimental upper candidates, not new defaults. Exceeding 1,680 requires an intentional loader/generator/test update and a newly identified field/collision world. Reject an increase that mainly adds hidden leaves and overdraw.

Rendering quality must not change physical obstacles. For any *new accepted layout*, low/medium/high settings share tree IDs, positions and contact envelopes; vary LOD, textures and shadows. Density reduction may remove only explicitly non-colliding decorative understory, or must retain a visible proxy for every obstacle. Never hide a collidable tree merely to meet a quality budget.

## 5. Representation, batching and lighting

Choose representation from projected size, camera FOV and view angle, not only distance from the fixed pilot. A chase camera can approach trees that are far from the pilot. Initial experiments can inspect full meshes at 0–80 m, reduced supplier/import LOD at 80–250 m and cards beyond that; these are camera-relative trial bands, not accepted thresholds or changes to the current 250 m placement constraint. Zoomed pilot views, overhead flight and ground-level views must qualify the result.

Godot selects a single automatic mesh LOD for an entire MultiMesh and cannot cull its instances individually. Separate distant groups spatially; keep batches keyed by cell, asset/part, effective material, representation and shadow policy. First compare the existing eight sectors with a bounded grid, for example 64/128/256 m cells, using identical placements. Count actual visible material surfaces and shadow submissions; cell × species × parts can erase instancing gains. [Godot mesh LOD](https://docs.godotengine.org/en/4.7/tutorials/3d/mesh_lod.html), [MultiMesh guidance](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html).

Keep current cards and their eight-draw baseline until an alternative wins. Do not claim that more cells retain eight draws. Avoid a per-tree `_process()`, per-frame world rebuild, runtime tree generation or mandatory streaming framework for this finite field. If scene creation becomes expensive, measure staged construction outside active play before introducing background lifetime complexity.

Start LOD transitions with matching representations and hysteresis. Compatibility does not provide `visibility_range_fade_mode` Self/Dependencies blending; those modes lose hysteresis there. Dither is a conditional motion experiment and cannot assume TAA. Keep the existing alpha-scissor path; the separately owned **L6b-R1** tests coverage only if a defect is reproduced. MSAA enabled does not establish alpha-to-coverage support. [GeometryInstance3D contract](https://docs.godotengine.org/en/4.7/classes/class_geometryinstance3d.html), [upstream Compatibility alpha-to-coverage work](https://github.com/godotengine/godot/pull/114845).

For shadows, retain far-card shadow casting off. Qualify nearby imported-tree shadows and distance limits, with separate cost measurements for geometry and shadow passes. Preserve roots/contact cues and existing atmosphere for distance separation. Do not hide silhouette defects with excessive fog, add per-tree lights, or expect porous foliage to be a reliable solid occluder. If occlusion is useful, use suitable existing terrain/buildings and compare from elevated cameras.

Octahedral impostors remain a **conditional L8b experiment**, consistent with the global plan's deferral. First demonstrate that existing cards/mesh LOD fail a named view or cost requirement. Then evaluate an existing baker using one downloaded tree, rotating camera and sun, underside/top views and changing exposure. Keep baking offline. Do not implement a custom impostor framework as this project's first solution.

## 6. Motion and integration contracts

Reuse detached session wind and `sim_clock`, including pause/reset and the 1,024 s clock wrap. Root movement must be zero; trunk/crown sway should be slow and bounded, with smaller leaf detail only if the supplied geometry supports it. Neighborhoods should share gust direction with stable phase variation, not move in lockstep or jitter independently. The main/detail separation in [GPU Gems 3, chapter 16](https://developer.nvidia.com/gpugems/gpugems3/part-iii-rendering/chapter-16-vegetation-procedural-animation-and-shading-crysis) is a technique reference, not a request to paint new wind masks or reproduce CryEngine.

Enable imported-tree wind only after confirming that the adapter preserves every active source material feature. Its current copy supports a subset of material properties; new PBR assets may use additional maps/channels. Qualify instance-color behavior, part-local transforms and deformation bounds under Compatibility. Keep the shader shared with grass intact unless the coordinated change preserves all consumers.

**Render-only slices:** same placements, IDs, dimensions and collision envelopes; require exact state/contact parity using accepted input/ticks and the [flight-log workflow](../FLIGHT-LOGGING.md). No golden-flight rerecording.

**World-changing slices:** new positions, heights, species envelopes or density can change collisions. Update generation, validation, proxy dimensions and world/source identity together through their authoritative pipelines. Keep the old world as baseline, establish exact replay within each world, and label cross-world runs as candidate comparisons. Check `complete` and `solver_changed`; do not call them exact equivalence. Existing trunk/foliage responses remain gameplay estimates. LOD and shadows must never drive collision availability.

## 7. Reviewable implementation sequence

All implementation rows are pending. The two documents produced by this planning task are research/design inputs, not completion of these steps. New evidence belongs under `docs/research/visual-quality-implementation/<STEP-ID>/`; scripts extend existing tree/vegetation tools. Existing steps retain their canonical evidence homes.

| ID | Work | Required proof / dependency |
| --- | --- | --- |
| VQ-01c/01d, VQ-02a tree slice | Freeze the actual scene baseline, import/material inventory, sources, camera tracks and measured headroom | Existing global owners; both card and imported routes included, with current wind rather than stale comments. |
| **L6a-R1** | Preview retained unused tree variants; compare one realistic downloadable source family; select first additional silhouettes and prepare licensed derivatives | Same lighting/cameras and fixed placements; source manifests, native import, material/silhouette views, source and derived costs. Reject unsuitable assets before broad integration. |
| **L6b-R2** | Qualify tree-only material/palette changes and matching near/far source representations | After intake and VQ-02a; bounded leaf/bark variation, source-map preservation, mip/coverage tests and day/night motion. L6b-R1 remains the separate alpha experiment. |
| **L7-R1** | Replace visibly artificial grouping with habitat patches, variable margins and clearings at the existing field count | After accepted family/envelopes; generator determinism, exclusions, layout/identity update, proxy alignment, pilot sightlines and same-count timing. |
| **L8a** | Qualify a bounded downloaded-mesh/supplied-LOD/card route for views where current cards flatten | Conditional on captured defect; projected-size/FOV sweep, stable transitions and aggregate geometry/shadow budget. Existing imported LU trees are controls, not automatic L8 acceptance. |
| **L7-R2** | Compare spatial batching, then increase density only if composition and measured headroom justify it | Batching first with identical instances; count/world changes separate. Report submissions, CPU/GPU cost, load time and query cost; explicit loader limit revision if needed. |
| **L15b-R1** | Add qualified imported-tree wind while preserving field-card behavior and shared grass materials | Calm/gust/reversal, pause/reset/wrap, roots/normals/bounds, no physical-wind change; coordinate M5 and grass L15c. |
| **L8b** | Evaluate an existing octahedral impostor baker for one remaining representation problem | Optional after L8a/L7-R2 evidence. Exact plugin commit/license, real Compatibility renderer, angle/light/LOD/export and memory checks; keep current cards on failure. |
| L6c, Gate L/SC, VQ-06c | Qualify the accepted combination in actual flight, RC and Home views and exported builds | Combined performance, independent owner readability/preference and named target hardware. Software checks alone do not close pilot gates. |

Keep each material, representation, placement and wind delivery independently selectable in research fixtures. Adopt only the winning comparison; do not stack several unmeasured candidates and then attempt to attribute the result. No promised delivery date precedes the baseline and asset intake.

## 8. Acceptance and rollback

Retain the global 60 Hz profile targets: **frame p95 ≤18 ms, p99 ≤25 ms, simulation/wall ratio 0.99–1.01**, and initial **+0.5 ms frame-p95 for all new visual work combined**, shared with grass and other active work. The LU **650k source-geometry cap**, Gate P and scenery-query objectives remain in force. This proposal allocates no extra budget automatically. The historical optional L8 target of 1,000 triangles per near tree is not met merely because a heavier LU model is already imported; any proposed revision needs explicit resource/cost evidence before adoption.

| Gate | Evidence required |
| --- | --- |
| Realism/variety | Randomized before/after captures at matched exposure: pilot normal/zoom, close trunk/crown, side-on, underside, overhead and full skyline. Owner can identify improved silhouettes, materials and coherent woodland without distracting repetition. Include a realistic-source candidate, not only recolors of the old family. |
| Temporal quality | Native 720p/1080p clips: slow pan, approach/retreat through every transition, lateral flight, fast chase pass and camera cut. No recurring shimmer, black leaf backs, atlas bleed, rotated-card seams, floating roots or obvious transition flashes. |
| Readability | Existing contrasting-aircraft tests at 20/50/100 m and farther accepted ranges, tree/sky backgrounds, noon/low sun/dusk/night. Preserve attitude recognition, runway edge and approach gaps; obtain independent owner flight evidence. |
| Placement | Stable output hashes; crown/wind clearance; no water/runway/path/course overlap; no density-dependent position shifts; visible representation for every collidable tree. Review both top-down layout and pilot sightlines. |
| Performance | At least five alternating baseline/candidate pairs, 10 s warmup + 60 s measurement, frozen camera/input/weather/time/build/GPU/driver/resolution/cap. Record frame p50/p95/p99, available CPU/GPU timings, draws, primitives, shadow passes, memory/residency and cold/warm construction. Separate captures from timed runs; mark unavailable GPU metrics. |
| Attribution | Tree-hidden, shadows-off, simple-material, wind-off and reduced-density controls. A lower triangle count without better full-scene timing is not an optimization pass. |
| State/contact | Exact replay for render-only changes; separately identified worlds for changed populations/envelopes. Visual and proxy bounds agree, including maximum wind. Keep physical validation claims separate. |
| Lifecycle/export | Fresh-clone regeneration/import, native shader logs, bundled textures/licenses, repeated Home/Fly/RC/reset transitions and bounded caches. Retain the global 20-cycle check and separate DT soak requirements. |

Use the [tree pipeline and rendered checks](../../tools/trees/README.md), [vegetation source checks](../../tools/landscape/vegetation/README.md), L6c visibility kit and [repository test/export workflows](../TOOLS.md). After runtime integration, run `app/test.sh` plus relevant tree assets/placement/wind/bounds and collision checks. Headless success cannot qualify shader behavior. New tests should cover real contracts and reproduced failures, not mirror candidate implementation.

Rollback must restore the previous complete asset/atlas/catalog/material set. A layout change must also restore its generator output, field identity and collision envelopes; mixing new visuals with old proxy dimensions is not a valid rollback. Record adopted decisions in DECISIONS and consolidate completed plan details into the landscape/scenery guides after the evidence is accepted.
