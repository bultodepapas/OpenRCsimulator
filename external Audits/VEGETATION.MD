# OpenRC Simulator — vegetation audit and improvement plan

I completed the audit of **[bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator)** and researched **31 primary sources**, covering vegetation rendering, forest composition, plant structure, textures, downloadable assets, and Godot’s rendering constraints.

**The strongest opportunities are more distinct tree shapes, consistent materials across representations, richer woodland edges, and convincing depth from the cameras used during flight.** OpenRC already has substantial vegetation infrastructure; the plan builds on that work.

### Full report

[OpenRC_Vegetation_Audit_2026-11-09.pdf](https://chatgpt.com/library?file_id=libfile_fde3_f-23afa1307c348191acfe7de22953caec_ac5d15b10f548191b3cb750779cf7c10&account_id=personal)

The **24-page report** includes a map of all 1,680 field-tree positions, annotated historical comparisons, a phased roadmap, **12 proposed implementation tasks**, acceptance criteria, and references to both external research and the relevant repository files.

**Audit baseline:** commit `f47d1dc6cccb141936407d0217eafdc465558190`, reviewed on 9 November 2026. I inspected the current source, calculated the tree populations, and reviewed selected retained images and performance reports. **I did not run a fresh native simulator benchmark**, so current code findings, historical measurements, and proposed improvements are distinguished below.

---

## 1. What OpenRC already has

The current implementation is more advanced than some older project documents suggest. The audit accounts for the newer forest, meadow, wind, and texture-filtering work.

| Area | Current implementation | Implication |
|---|---|---|
| Field-tree layout | **1,680 positions:** 480 near and 1,200 far, using `groves-v2` | There is already a designed woodland structure to refine. |
| Detailed trees | High selects **127 imported 3D field trees**; Extreme selects **480** | Full 3D trees are already integrated. |
| Distant trees | Three atlas silhouettes, using crossed planes | Distant shape variety and angular depth remain limited. |
| Vegetation catalog | **30 assets:** 13 trees, 3 shrubs, 5 grasses, 2 herbs, 4 flowers, 2 crops, and 1 reed | Library variety does not establish how much variety appears in a particular view. |
| Woodland margins | High-tier default-field recipe: four patches, 220 plant cards, 472 source triangles including the floor | Ground-level layering already exists, but its visible coverage is localized. |
| Runway meadow | Colony placement, quality subsets, wind, and a saved On/Off preference | Clustering and a vegetation toggle are already implemented. |
| Tree materials | Roughness correction, qualified wind, asset-specific filtering, and selective coverage-preserving mipmaps | These accepted improvements should remain the baseline. |

Repository evidence: [field-tree selection](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/treeline.gd), [vegetation catalog](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/assets/landscape/vegetation/catalog.json), [woodland-edge implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/woodland_edge_habitat.gd), and [runway meadow](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/runway_meadow.gd).

### Where the 3D detail goes

These counts cover **field trees**, excluding separately placed scenery trees and smaller plants.

| Scene detail | 3D field trees | Card trees | Selection rule |
|---|---:|---:|---|
| Low | 0 | 1,680 | All field positions use cards |
| Medium | 0 | 1,680 | All field positions use cards |
| High | 127 | 1,553 | Within 600 m, in the pilot-facing sector |
| Extreme | 480 | 1,200 | Entire near ring in 3D |

This selection is based on the **pilot’s position and runway direction**, rather than continuously following the active camera. That matters for chase, rear, side, and overhead views: a camera can approach a tree that remains a flat representation.

Code evidence: [detail settings](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/scene_detail.gd) and [field-tree construction](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/field_tree_detail.gd).

---

## 2. The highest-priority visual improvements

### A. Expand recognizable tree shapes

The field renderer currently has **three fixed atlas slots**. Height varies between approximately **12 and 25 metres**, with rotation and restrained color variation, but those changes preserve the underlying branching pattern and crown openings.

The next asset pass should introduce forms that remain visibly different at ordinary flight distances:

- A broad, open-grown deciduous crown.
- A taller, narrower woodland-grown crown.
- A younger tree with a different branching structure.
- An irregular or asymmetric mature form.
- Distinct conifer proportions and crown density.

Research on tree structure supports treating crown differences as relationships between branches, light, and available space. For OpenRC, the practical application is to select suitable existing models with those differences and integrate them through the current pipeline. [algorithmicbotany.org](https://algorithmicbotany.org/papers/selforg.sig2009.html?utm_source=chatgpt.com)

**Proposed target:** gradually build a working set of **8–12 distinguishable tree forms** across a few coherent families. This is an artistic target to qualify in stages. The first delivery should introduce only **three clearly different forms** in one visible woodland.

OpenRC already has a distinct young-oak source, so the work should extend that approach. It should not assume that all existing young trees are scaled-down mature models.

Code evidence: [tree atlas definition](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/tree_assets.gd) and [imported vegetation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/imported_vegetation.gd).

### B. Keep trees convincing when the camera moves

The fixed pilot-sector approach is understandable for the main flying position. Broader camera coverage needs a bounded extension.

I recommend testing a representation hierarchy with:

| View condition | What should remain convincing |
|---|---|
| Close or visually large tree | Trunk, major branches, crown depth, leaf clusters, and openings |
| Middle distance | Crown volume, silhouette, and stable foliage coverage |
| Distant individual tree | Recognizable form, canopy mass, color, and stable edges |
| Distant woodland | Stand outline, gaps, height relationships, and atmospheric separation |

Selection should consider **projected size and camera zoom**, alongside distance. Godot’s mesh LOD documentation is relevant here, particularly because instanced batches share LOD decisions; batch design affects how efficiently detail can follow a view. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/3d/mesh_lod.html?utm_source=chatgpt.com)

A prototype should have a fixed upper limit on detailed trees, stable identities, and hysteresis to prevent repeated switching around a threshold. It must also avoid expensive scene construction during fast camera movement.

There is an existing identity mismatch to resolve first: **the atlas’s maple slot becomes beech in the detailed field-tree path**. A future transition between those representations would need a consistent source form.

Changing the selected model may also change its derived collision envelope. A visual substitution therefore needs either verified unchanged proxies and visual fit, or an explicitly updated world identity. **Field-tree collision must never switch with the camera.**

Evidence: [tree selection and aliases](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/treeline.gd) and [collision-world construction](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/collision_world.gd).

### C. Make mesh and card materials agree

The project already corrected the LandscapeLab leaf roughness to **0.85**. The retained October 22 comparison still describes a residual lighting/color difference between detailed trees and cards. That historical finding warrants a current controlled comparison; it does not establish the exact severity at the audited commit.

The material review should isolate:

1. Leaf and bark color.
2. Crown and leaf normals.
3. Ambient-light response.
4. Roughness and specular highlights.
5. Backlighting.
6. Opacity coverage at distance.

Use the same source tree, camera, exposure, weather, and initially zero wind. This makes it possible to determine whether a mismatch comes from the texture, geometry, or shading.

The intended result is a forest whose representations share the same visual identity across distance. Silhouette and light response both matter; detailed textures cannot compensate for a missing crown shape. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/3d/standard_material_3d.html?utm_source=chatgpt.com)

Historical evidence: [L8a-R2 material comparison](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/visual-quality-implementation/L8a-R2/README.md).

---

## 3. Make forests feel like places

OpenRC’s current layout already contains woods, hedgerows, solitary trees, and preserved skyline positions. The next improvement should strengthen the relationships within those groups.

Ecological modeling research is useful because it combines environmental constraints with artistic control over density, age, and distribution. OpenRC can apply those composition principles through lightweight authored recipes. [algorithmicbotany.org](https://algorithmicbotany.org/papers/ecosys.sig98.html?utm_source=chatgpt.com)

### Recommended habitat structure

| Zone | Proposed visual treatment |
|---|---|
| **Maintained club grounds** | Short vegetation, clear paths, selected ornamental groups, convincing contact around landmark trees |
| **Meadow margin** | Existing grass and flower colonies with uneven heights, quieter stretches, and locally related dryness |
| **Woodland edge** | Herbs, shrubs, young trees, and mature canopy arranged in an irregular transition |
| **Woodland interior** | Dominant tree families, occasional gaps, selective low growth, and more visible litter |
| **Moist or shoreline pocket** | Localized reeds, suitable ferns, and damp ground where the existing habitat permits |
| **Dry or disturbed edge** | Less lush growth, restrained straw tones, exposed soil, and occasional weeds |

Forest-layer references support the distinction between canopy, understory, shrub, herb, and floor layers. They do not prescribe a universal density or spacing for this simulator. [Natural Resources Conservation Service](https://www.nrcs.usda.gov/conservation-basics/land/forests/woodlands-and-forestlands?utm_source=chatgpt.com)

### What would make the biggest visible difference?

**An irregular forest edge.** Some trees should project outward; others should sit behind shrubs or small gaps. A few places should expose trunks and darker interior space. Other stretches can carry denser low growth.

A demonstration edge could occupy roughly **5–20 metres of depth**, adjusted to the actual site and camera. That range is a proposed artistic starting point.

**Related variation.** Trees in one stand should share enough character to belong together, while differing in age, exposure, and crown development. Ground vegetation should respond to the same local conditions.

**Ground continuity.** Soil, litter, roots, and small plants should connect the tree to its surroundings. Avoid identical dark circles or identical fern arrangements beneath every trunk.

**Protected open space.** The runway, pilot area, sightlines, and useful flight corridors should retain their intended character. Green paradise is explicitly designed as an open landscape; its emptiness is not a vegetation defect.

Evidence: [current field data](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/data/fields/default.json), [tree placement pipeline](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/tools/trees/README.md), and [landscape definitions](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/LANDSCAPES.md).

---

## 4. Shrubs, flowers, grass, and smaller plants

### Shrubs

Shrubs should provide much of the missing transition between ground vegetation and mature trees.

My proposed initial vocabulary is **3–5 distinguishable shrub forms**, admitted gradually: a low spreading form, a rounded leafy form, a taller open form, and additional forms only where they serve a clear habitat role.

Their placement should create depth and partial occlusion. Continuous, equally spaced shrub borders would make an unmanaged woodland look landscaped.

### Flowers

Flowers should provide localized color and seasonal character. Their strongest improvement opportunities are:

- Irregular patch shapes.
- Mixtures of flowering and nonflowering stages.
- Uneven density within a patch.
- Occasional quiet areas with very little color.
- Scale that remains believable beside grass and aircraft.

The existing Empodium asset has a Namaqualand/South African source. That can work as an ornamental choice or within a deliberately fictional setting. A geographically literal landscape would need a documented plant palette. [Poly Haven](https://polyhaven.com/a/flower_empodium?utm_source=chatgpt.com)

### Ferns

OpenRC already uses a selected form of **Poly Haven Fern 02**. Other supplied clump forms are reasonable candidates for reducing repetition in a few suitable pockets. Their use should follow the chosen habitat rather than become universal ground decoration. [Poly Haven](https://polyhaven.com/a/fern_02?utm_source=chatgpt.com)

### Grass and meadow

The November 3 report records a final High meadow layout of **4,492 plants, 153,704 source triangles, and 22 batches**. A separately measured, smaller candidate had different counts. Its timing cannot be assigned to the final layout or today’s build.

The immediate opportunity is to improve the composition of the existing colonies: patch shape, height relationships, dryness, and the transition to the mown lip. Additional density should follow a demonstrated visual need and measured budget.

The imported near-grass route also has an enhanced material option that remains opt-in. Any proposed seam repair should first reproduce the defect in motion, under the actual lighting and camera route.

Evidence: [meadow research and configuration history](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/grass-meadow-techniques-2026-11-03.md) and [near-grass implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/imported_near_grass.gd).

---

## 5. Texture and shading plan

Texture resolution should follow the size of the plant on screen and its intended camera role.

### Proposed working policy

| Element | Improvement direction |
|---|---|
| Tree and plant textures | Start experiments around 1K–2K where the view supports that detail; justify larger maps with a close-up case |
| Bark | Check physical scale, normal response, trunk taper, and repetition |
| Leaves | Preserve recognizable clusters, clean opacity borders, and believable front/back behavior |
| Distant atlases | Size them for projected crown detail and stable coverage |
| Ground materials | Match soil, litter, and moisture to the surrounding habitat |
| Texture reuse | Share resources where appropriate and measure effective imported memory |

These are **starting points for experiments**, not fixed engine limits.

### Preserve the filtering work already accepted

The established maple textures already use coverage-preserving mipmaps. That work superseded an older restriction against enabling their mipmaps.

The field-tree atlas has a different configuration: it is mipmapped, coverage preservation is disabled, and its shader applies a distance-related alpha correction. A controlled comparison should examine the existing treatment against an alternative coverage treatment, checking every species tile and avoiding excessive compensation. Godot documents coverage preservation specifically for alpha-scissor use. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html?utm_source=chatgpt.com)

Evidence: [accepted maple work](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/engine-upgrade/GDU-11/README.md) and [field-tree shader](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/treeline.gdshader).

### Judge foliage while the aircraft is moving

Antialiasing changes need to be evaluated against both vegetation stability and aircraft readability. TAA can introduce blur or ghosting, while ordinary MSAA does not by itself resolve alpha-scissor texture edges. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/3d/3d_antialiasing.html?utm_source=chatgpt.com)

The relevant question is whether the pilot can still recognize aircraft attitude, landing cues, and movement against the richer background.

---

## 6. Wind, lighting, and immersion

The project already has wind support for qualified oak, pine, beech, and young-oak assets, with bounded deformation. The four protected maples remain static.

The next pass should refine the existing motion:

- Different stiffness and phase for different plant roles.
- Slow crown movement for distant trees.
- Restrained leaf movement where visible.
- Coherent broad wind direction across trees, grass, reeds, and the windsock.
- Fixed roots and verified deformation bounds.

The original Crysis and procedural-wind chapters support separating broad bending from smaller leaf motion. OpenRC should apply these principles within its existing weather and render-clock contracts. [NVIDIA Developer](https://developer.nvidia.com/gpugems/gpugems3/part-iii-rendering/chapter-16-vegetation-procedural-animation-and-shading-crysis?utm_source=chatgpt.com)

For lighting, prioritize readable crown volume, grounded trunks, and coherent backlighting. Renderer-specific effects need their own qualification: visibility fades and other advanced features do not behave identically across Compatibility, Mobile, and Forward+. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html?utm_source=chatgpt.com)

OpenRC’s pinned engine is **Godot 4.8-beta2**, so any proposed renderer feature should be checked against that exact build. [Godot Engine](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/?utm_source=chatgpt.com)

---

## 7. Assets worth evaluating

The first asset candidates should come from sources already integrated into OpenRC. This reduces uncertainty around style, scale, materials, and packaging.

| Candidate | Recommended role | Main condition |
|---|---|---|
| **Existing LandscapeLab trees** | Additional crown and age forms | Preserve material corrections, source identity, and qualified wind |
| **Existing LOLIPOP assets** | Retain landmarks; evaluate suitable supplied variants | Protect the four established maples and their approved resources |
| **Poly Haven Fern 02** | Additional clump forms | Compare selected variants within the same budget |
| **Poly Haven Flower Empodium** | Growth-stage or ornamental variation | Make its habitat role explicit |
| **Poly Haven Shrub 01** | Candidate shrub source | Inspect conversion, supplied LODs, and habitat suitability |
| **Poly Haven Grass Medium 01** | Maps or compact derived tufts | Qualify a selected runtime representation |
| **Poly Haven Fir Tree 01** | Crown reference or later conversion candidate | Establish a viable representation before wider integration |
| **ambientCG / cgbookcase** | Soil, litter, bark, and selected leaf materials | Verify scale, palette, maps, and normal conventions |

Some attractive sources are very heavy: the official listings describe approximately **282,000 source triangles** for Shrub 01, **2 million** for Grass Medium 01, and **8 million** for Fir Tree 01. These figures describe source assets, not OpenRC-ready runtime versions. [Poly Haven](https://polyhaven.com/a/shrub_01?utm_source=chatgpt.com)

Poly Haven asset files, ambientCG assets, and cgbookcase textures provide CC0 options. Existing repository assets still need their own notices and provenance preserved. [Poly Haven](https://polyhaven.com/license?utm_source=chatgpt.com)

Each admitted form should have a source URL, license, source hash, selected object/LOD, dimensions, runtime geometry counts, material maps, and derived representations recorded in the existing catalog.

---

## 8. Implementation roadmap

The report maps these deliveries to the existing L, VQ, and SC/LU work streams.

| Phase | Concrete delivery | Acceptance gate |
|---|---|---|
| **0. Baseline and visual direction** | Current 1080p camera matrix, inventory, chosen season/biome brief, and demonstration site | Reproducible source, engine, settings, and workload |
| **1. Material consistency** | Same-source mesh/card comparison and controlled atlas-filtering experiment | Improved continuity in stills and motion |
| **2. Tree-form variety** | Three clearly distinguishable supplied forms with matching distant representations | Better silhouettes, correct scale, usable LODs, and declared collision implications |
| **3. Richer woodland edge** | One edge combining shrubs, young trees, herbs, and ground treatment | Visible depth, preserved clearances, and acceptable cost |
| **4. Camera coverage** | Bounded camera-aware representation prototype | Convincing close passes without popping, hitches, or camera-dependent collision |
| **5. Combined qualification** | Native timing, readability, lifecycle, and packaging results | All applicable whole-profile gates pass |

Planning bands in the report are **1–2 days for small tasks, 3–5 days for medium tasks, and 1–2 weeks for larger experiments**. They are estimates, dependent on asset conversion, review, and target-hardware access.

### Best first implementation package

Use **one existing front grove and its visible edge**:

1. Freeze its current source, seed, cameras, and weather.
2. Improve mesh/card material agreement.
3. Introduce three distinguishable crown or age forms.
4. Refine one shrub–young-tree–herb transition.
5. Compare normal pilot view, zoomed pilot view, a close chase pass, and overhead.
6. Measure the combined change before expanding it.

This gives the project a concrete, reviewable example of the intended quality.

### Relevant implementation boundaries

The core changes belong in the existing systems:

- `app/render/treeline.gd` and `tree_assets.gd`
- `app/render/field_tree_detail.gd`
- `app/scenery/imported_vegetation.gd`
- `app/scenery/woodland_edge_habitat.gd`
- `app/scenery/runway_meadow.gd`
- Existing catalog, conversion, placement, and capture tools

Material-only changes, tree-representation changes, and actual world-layout changes should remain separate reviews. Existing scene-tier-dependent ornament collision rules should also be preserved.

---

## 9. Performance and acceptance criteria

The retained November 3 budget record already reports exceeded provisional view allocations before the meadow addition. That establishes a need to refresh the budget; it does not establish current frame time.

The older pooled 650,000-triangle cap has also been superseded. Source triangles, drawn primitives, draw calls, alpha overdraw, GPU time, and frame pacing need separate treatment.

Evidence: [current budget record](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/tools/scenery/scene_budget.json) and [LU-34 accounting](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/landscape-upgrade/LU-34/README.md).

### Retain the project’s existing gates

| Measure | Existing qualification requirement |
|---|---|
| Primary resolution | **1920 × 1080** |
| Frame time p95 | **≤18 ms** |
| Frame time p99 | **≤25 ms** |
| Simulation/wall-time ratio | **0.99–1.01** |
| Initial added visual cost | **≤+0.5 ms frame p95 for all new visual work combined**, while the whole profile passes |
| Tree comparisons | Five alternating baseline/candidate pairs under the tree plan’s protocol |

These are requirements from the project plans, **not results obtained in this audit**. Higher resolutions should follow primary qualification; 720p remains fallback coverage.

Acceptance should include:

- Pilot, zoom, chase, side, rear, and overhead views.
- Front light, backlight, low sun, dusk, and night.
- Panning, approach, retreat, gusts, and camera cuts.
- Aircraft attitude and landing-cue readability.
- Protected landmarks, clearances, collision, and affected replay behavior.
- Home/Fly/reset transitions and packaged-resource loading.

Use the existing capture and performance tools. Rendering-profiler results should be combined with whole-session measurements because they do not cover all simulation and script work. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/scripting/debug/debugger_panel.html?utm_source=chatgpt.com)

Performance-policy evidence: [global visual-quality plan](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/plans/global-performance-visual-quality.md) and [tree/forest plan](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/plans/tree-forest-quality.md).

---

## 10. The 31 primary sources researched

The report includes the purpose and limitations of each reference. The set comprises official documentation, original technical chapters, author-hosted research abstracts, government forest references, and official asset/license pages.

### Rendering and engine behavior

1. [Godot — Optimization using MultiMeshes](https://docs.godotengine.org/en/latest/tutorials/performance/using_multimesh.html)
2. [Godot — Mesh level of detail](https://docs.godotengine.org/en/latest/tutorials/3d/mesh_lod.html)
3. [Godot — Visibility ranges / HLOD](https://docs.godotengine.org/en/latest/tutorials/3d/visibility_ranges.html)
4. [Godot — StandardMaterial3D and ORMMaterial3D](https://docs.godotengine.org/en/latest/tutorials/3d/standard_material_3d.html)
5. [Godot — Importing images](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html)
6. [Godot — Overview of renderers](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html)
7. [Godot — GeometryInstance3D](https://docs.godotengine.org/en/latest/classes/class_geometryinstance3d.html)
8. [Godot — 3D lights and shadows](https://docs.godotengine.org/en/latest/tutorials/3d/lights_and_shadows.html)
9. [Godot — Occlusion culling](https://docs.godotengine.org/en/latest/tutorials/3d/occlusion_culling.html)
10. [Godot — Debugger and Visual Profiler](https://docs.godotengine.org/en/latest/tutorials/scripting/debug/debugger_panel.html)
11. [Godot — 3D antialiasing](https://docs.godotengine.org/en/latest/tutorials/3d/3d_antialiasing.html)
12. [GPU Gems 3 — Crysis vegetation animation and shading](https://developer.nvidia.com/gpugems/gpugems3/part-iii-rendering/chapter-16-vegetation-procedural-animation-and-shading-crysis)
13. [GPU Gems 3 — Procedural wind animation of trees](https://developer.nvidia.com/gpugems/gpugems3/part-i-geometry/chapter-6-gpu-generated-procedural-wind-animations-trees)
14. [GPU Gems 3 — Next-generation SpeedTree rendering](https://developer.nvidia.com/gpugems/gpugems3/part-i-geometry/chapter-4-next-generation-speedtree-rendering)
15. [Godot 4.8 beta 1 announcement](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/)
16. [Godot 4.8 beta 2 announcement](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/)

### Plant structure and landscape composition

17. [Deussen et al. — Realistic modeling and rendering of plant ecosystems](https://algorithmicbotany.org/papers/ecosys.sig98.html)
18. [Inria IMAGINE — EcoBrush](https://rex-radar.inria.fr/report/2017/imagine/uid76.html)
19. [Palubicki et al. — Self-organizing tree models](https://algorithmicbotany.org/papers/selforg.sig2009.html)
20. [Disney Research — Guided ecological simulation](https://studios.disneyresearch.com/2015/11/19/guided-ecological-simulation-for-artistic-editing-of-plant-distributions-in-natural-scenes/)
21. [USDA NRCS — Woodlands and Forestlands](https://www.nrcs.usda.gov/conservation-basics/land/forests/woodlands-and-forestlands)
22. [Minnesota DNR — Forest layers](https://www.dnr.state.mn.us/forestry/education/foresttreasures/layers.html)

### Assets, textures, and reuse

23. [Poly Haven — Asset license](https://polyhaven.com/license)
24. [ambientCG — License](https://docs.ambientcg.com/license/)
25. [cgbookcase — Texture catalog and license](https://www.cgbookcase.com/textures)
26. [Poly Haven — Fern 02](https://polyhaven.com/a/fern_02)
27. [Poly Haven — Shrub 01](https://polyhaven.com/a/shrub_01)
28. [Poly Haven — Flower Empodium](https://polyhaven.com/a/flower_empodium)
29. [Poly Haven — Fir Tree 01](https://polyhaven.com/a/fir_tree_01)
30. [Poly Haven — Grass Medium 01](https://polyhaven.com/a/grass_medium_01)
31. [cgbookcase — Green Leaf 09](https://www.cgbookcase.com/textures/green-leaf-09)

**My recommended first milestone is the front-grove demonstration:** distinct tree forms, consistent foliage shading, and one convincing layered edge, reviewed in motion at 1080p. Its results should determine which changes expand across the landscape and which require further work.
## Completed: 24 additional investigations, supported by 36 new primary references

This second round goes deeper into **leaf appearance, tree proportions, forest structure, flowers, habitat composition, texture processing, wind, and aircraft visibility**.

Each investigation includes a finding, a decision for OpenRC, a proposed comparison, and acceptance criteria. The new bibliography has **no URL overlap with the first report’s 31 references**. Some techniques and assets had already appeared in OpenRC’s own research; those cases are identified explicitly.

The complete **34-page supplement** contains all 24 investigations, the source register, implementation links, and a recommended sequence:

[OpenRC_Vegetation_24_New_Investigations_2026-11-09.pdf](https://chatgpt.com/library?file_id=libfile_fde3_f-ea69eb669a1881919f51179d64b78815_ac5d15b10f548191b3cb750779cf7c10&account_id=personal)

The project review is pinned to [commit f47d1dc6cc](https://github.com/bultodepapas/OpenRCsimulator/commit/f47d1dc6cccb141936407d0217eafdc465558190). These are completed research investigations and source inspections. The rendering, GPU, and pilot-recognition experiments described below remain proposed tests; the repository has not been changed.

**My main recommendation:** pursue a coherent vegetation upgrade built around credible plant forms, consistent foliage lighting, believable growth stages, and carefully composed habitat patches. Those improvements should guide where additional geometry, textures, and density are worth their cost.

---

## A. Eight new investigations into foliage rendering and tree appearance

### 1. Model light passing through leaves more selectively

The original leaf-rendering research distinguishes light reflected by a leaf from light transmitted through it. Leaf thickness, internal structure, and the relationship between the front and back surfaces affect the result; a uniform green backlight cannot represent all of those differences. [cg.tuwien.ac.at](https://www.cg.tuwien.ac.at/research/publications/2007/Habel_2007_RTT/Habel_2007_RTT-Preprint.pdf?utm_source=chatgpt.com)

**OpenRC decision:** investigate a restrained transmission mask for one existing broadleaf family. Compare front, side, and rear illumination at fixed exposure, looking for believable differences between the leaf body, veins, and opaque branches.

There is a concrete integration constraint: the [imported-tree material adapter](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/imported_vegetation.gd) currently rejects backlight and subsurface/transmittance features for its supported wind route. Any successful material candidate needs an explicit adapter extension and static/wind comparison.

**Accept it when:** backlit foliage gains depth without glowing crowns, light leaking through bark, or inconsistent appearance when wind is enabled.

### 2. Give crowns more convincing volume through their shading normals

Research on implicit foliage shapes uses a simplified representation of the crown to adjust shading normals. This can make the larger canopy structure easier to perceive, although it remains an appearance approximation and has limitations when preprocessing depends on relationships between different trees. [data.cgmi.workers.dev](https://data.cgmi.workers.dev/production/Luft2006ExpressiveIlluminationFoliage/Luft2006ExpressiveIlluminationFoliage.pdf?utm_source=chatgpt.com)

**OpenRC decision:** compare three treatments for one unprotected tree: original normals, a weak adjustment toward several crown lobes, and the existing distant-card appearance. Keep geometry, alpha, roughness, lighting, and placement unchanged.

The goal is to reveal groups of branches and foliage within the crown while preserving the finer leaf surface. A strong spherical normal treatment could produce a smooth, artificial canopy.

**Accept it when:** the crown reads as a collection of organic masses from multiple angles, with intact branch openings, correct leaf backfaces, and no new shading seams during wind.

### 3. Investigate normal-map filtering before further dulling the leaves

Normal-map detail can create unstable highlights when it becomes smaller than a pixel. LEAN Mapping and frequency-domain normal-filtering research explain why averaging normal directions does not necessarily preserve the resulting specular appearance. [userpages.cs.umbc.edu](https://userpages.cs.umbc.edu/olano/papers/lean/?utm_source=chatgpt.com)

**OpenRC decision:** retain the project’s accepted leaf roughness correction as the control. First compare the current material against a diagnostic version with its normal map disabled. That separates highlight noise from alpha-edge noise before introducing another shader feature.

If normal detail is responsible, evaluate a small preprocessing or roughness treatment before considering the additional channels and shader work of a full LEAN implementation. The existing correction is documented in [L8a-R2](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/visual-quality-implementation/L8a-R2/README.md).

**Accept it when:** slow camera movement produces less sparkle while close leaves retain their structure and overall brightness.

### 4. Test hashed alpha only against a demonstrated scissor failure

Hashed alpha testing replaces a fixed transparency cutoff with spatially varying thresholds. It can preserve minified foliage that would otherwise disappear, but it introduces noise; the hash design affects that noise’s temporal stability. [Research](https://research.nvidia.com/publication/2017-02_hashed-alpha-testing?utm_source=chatgpt.com)

**OpenRC decision:** make this a conditional experiment on one unprotected foliage source. Compare the accepted scissor route against a stable hashed candidate at native 1080p, including stationary views, slow pans, zoom, wind, and shadows.

Aircraft must cross the vegetation in the comparison. A crown that looks fuller could still create distracting grain around a small aircraft.

**Accept it when:** retained canopy coverage improves without crawling noise, glittering shadows, or poorer aircraft-attitude recognition. Keep the current scissor route if the overall result does not improve. The experiment should establish its value without depending on temporal antialiasing.

### 5. Revisit impostors with a smaller view domain and a fair control

Epic’s documented impostor system distinguishes full-sphere, upper-hemisphere, and fixed-view representations. Its guidance also identifies capture-pivot errors as a cause of doubled trunks during billboard transitions. [Epic Developer Community](https://dev.epicgames.com/documentation/en-us/unreal-engine/impostor-baker-plugin-in-unreal-engine?utm_source=chatgpt.com)

**OpenRC decision:** if a specific distant view still fails, compare current cards, a new full-sphere bake, and a new upper-hemisphere bake using **the same current tree, scale, pivot, and decoded texture-memory ceiling**.

This corrects an important comparison issue. The historical failed impostor used Quaternius `CommonTree_1`; the current oak slot uses a LandscapeLab source. The old result remains useful history, but cannot serve as an equivalent source control. See the [retained L8b experiment](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/visual-quality-implementation/L8b/2026-10-18/README.md).

**Accept it when:** angular coverage improves without trunk ghosts, disappearing crowns, underside failures, or hidden memory growth.

### 6. Evaluate volumetric forest proxies as a feasibility question

Volumetric-billboard research describes representations with parallax and improved filtering for complex objects, including overlapping vegetation. The published technique relies on a dedicated rendering approach and geometry-shader support. [Wiley Online Library](https://onlinelibrary.wiley.com/doi/abs/10.1111/j.1467-8659.2009.01354.x?utm_source=chatgpt.com)

**OpenRC decision:** defer implementation. The useful investigation is whether a compatible existing implementation could solve a concrete problem that source mesh LODs or bounded multi-view representations cannot solve.

A preliminary screen should identify texture formats, required shader stages, shadows, export support, memory, and loading behavior for one two-tree overlap example.

**Accept it when:** a later prototype demonstrates a worthwhile improvement against the best existing representation at comparable appearance and measured cost. A feasibility study that concludes “defer” is a valid outcome here. There is no evidence from this research that OpenRC needs a new forest-rendering architecture.

### 7. Inspect leaf orientation and crown gaps when selecting assets

LeafGen treats leaf size, orientation, and spatial density as separate distributions. Its model also states simplifying assumptions, so it provides useful inspection categories rather than a universal botanical rule. [Wiley Online Library](https://besjournals.onlinelibrary.wiley.com/doi/10.1111/2041-210X.70080?utm_source=chatgpt.com)

**OpenRC decision:** extend the asset gallery to include side, oblique, overhead, and backlit views at several projected sizes. A source that looks excellent from the ground may reveal aligned cards, hollow rings, or collapsed coverage from an aircraft camera.

Where possible, inspect triangle-normal orientation and projected crown occupancy. Treat these as mesh diagnostics: a triangle-normal histogram is not a measurement of real leaf angles.

**Accept it when:** selected trees retain recognizable crown forms, internal openings, and branch depth across the cameras that matter. This should become an asset-admission criterion before adding more species or larger textures.

### 8. Build coherent seasonal palettes with a clear scientific boundary

PROSPECT relates leaf reflectance and transmittance to pigments and internal structure. Its water parameter describes water within the leaf; it does not model a rain film on the surface. The model also simplifies aspects of front/back anatomy. [prospect](https://jbferet.gitlab.io/prospect/articles/prospect.html?utm_source=chatgpt.com)

**OpenRC decision:** create a small palette study for one deciduous family: healthy green, early senescence, and dry/brown stages. Apply each treatment consistently to both the imported mesh and its distant representation under fixed illumination.

The immediate deliverable should be a coherent art preset. A spectral model need not become part of the runtime simulator.

**Accept it when:** seasonal changes remain plausible, preserve species character, and agree between mesh and card views. Keep surface wetness, drought stress, and seasonal pigment changes as separate concepts in the material brief.

---

## B. Eight new investigations into vegetation variety, ecology, and composition

### 9. Vary tree proportions together

The USDA urban-tree database relates measured crown and trunk dimensions to age, species, and growing region. It supports checking those dimensions jointly; it does not provide a universal scaling law for forest trees. [US Forest Service Research and Development](https://research.fs.usda.gov/treesearch/52933?utm_source=chatgpt.com)

**OpenRC decision:** build a proportion gallery for young trees, mature open-grown trees, and mature trees from denser stands. Record crown width, crown depth, crown-base height, and trunk diameter where the source supports those measurements.

Choose an appropriate supplied form before applying bounded uniform scaling. Independently stretching width and height can create variety while weakening the tree’s structural credibility.

**Accept it when:** the selected growth classes remain visually distinct at intended placement sizes, with documented proportions and believable silhouettes. Any changed collision envelope must be reviewed alongside the visual change.

### 10. Give forest openings different regeneration states

Variable-density forestry guidance distinguishes retained patches, gaps, and the surrounding stand. Separate gap research found that some openings retained sparse tree regeneration for long periods, with differences between study sites. An opening therefore need not become a uniformly filled sapling patch. [US Forest Service Research and Development](https://research.fs.usda.gov/treesearch/60596?utm_source=chatgpt.com)

**OpenRC decision:** author three gap treatments: an herb-dominated opening, patchy young-tree recruitment, and an opening around a retained mature tree.

Compare one current grove with a candidate using the same overall tree count but a different internal arrangement. This isolates composition before increasing population.

**Accept it when:** the woodland gains readable depth and openings from pilot, chase, and overhead cameras. Keep frequencies as documented artistic choices; the cited regional forestry studies do not establish an exact ecological recipe for OpenRC’s setting.

### 11. Make hedgerows express maintenance history

UKCEH research separates effects on flowers and berries from effects on woody structure. Its experiments did **not** establish that cutting frequency alone changed woody structure over six years; rejuvenation treatments produced different structural responses. [NERC Open Research Archive](https://nora.nerc.ac.uk/id/eprint/532938/?utm_source=chatgpt.com)

**OpenRC decision:** compare a maintained clipped boundary, a taller free-growing section, and a small regrowth section using suitable supplied assets.

Keep flower and berry state fixed during the structural comparison. Then evaluate seasonal flowering separately. This prevents one visual parameter from standing in for several unrelated processes.

**Accept it when:** viewers can recognize different maintenance histories without labels, and the transitions feel like parts of one landscape. Use a controlled maximum obstacle envelope so richer boundary vegetation does not inadvertently change flight clearances.

### 12. Mix flowering, vegetative, and seed stages coherently

USA National Phenology Network definitions distinguish vegetative and reproductive phases, including overlapping or nested states. They also distinguish seasonal leaf color from stress-related color. Brown foliage alone does not establish autumn. [usanpn.org](https://www.usanpn.org/files/reports/usa-npn_plant_and_animal_phenophase_definitions_v2.0.pdf?utm_source=chatgpt.com)

**OpenRC decision:** give candidate plant variants simple authored state metadata: live foliage, colored foliage, buds, open flowers, and seeds. Choose a seasonal brief, then allow plausible overlap between states.

For one meadow patch, compare a full-bloom-heavy recipe with a mixture of flowering plants, quiet green forms, and post-flowering stems at the same overall cost allowance.

**Accept it when:** the patch has a recognizable seasonal character and enough nonflowering structure to make flower accents meaningful. These definitions provide a consistency framework; geographic and date-specific flowering calendars would require further species-level evidence.

### 13. Record how confidently each asset is identified

Kew recognizes multiple *Empodium* species and gives the genus a southern African range. Its *Fagus sylvatica* entry describes a European tree. Those references cannot establish the exact identity of assets named only “Flower Empodium” or “Fagus.” [powo.science.kew.org](https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:1446-1?utm_source=chatgpt.com)

**OpenRC decision:** classify catalog entries as confirmed species, genus-level, common-name-only, or fictional/stylized. Then choose whether the Club field represents a defined geographic palette or a coherent fictional landscape with ornamental planting.

The [current vegetation catalog](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/assets/landscape/vegetation/catalog.json) provides the starting point for that review.

**Accept it when:** botanical claims are traceable and uncertain assets remain explicitly uncertain. Native range should inform the brief; it does not prohibit ornamental cultivation elsewhere or identify a model from its filename.

### 14. Add selected deadwood forms with believable contact

Forestry guidance distinguishes standing and fallen deadwood, different decay conditions, and different relationships to the ground. These distinctions offer more visual possibilities than repeating one clean log. [cdn.forestresearch.gov.uk](https://cdn.forestresearch.gov.uk/2012/04/fcpg020.pdf?utm_source=chatgpt.com)

**OpenRC decision:** test a tightly bounded woodland pocket with a few suitable cues: a partly settled branch, an irregular stump, or a decayed fragment where an existing source asset fits.

Concentrate on scale, support, ground contact, and variation in exposed surfaces. The study should establish whether these details remain visible from relevant low cameras before allocating them widely.

**Accept it when:** the pocket gains a sense of age without floating wood, repeated cut faces, or excessive clutter. Declare which objects are decorative and which introduce physical obstacles; keep the agreed runway, pilot, and flight-clearance masks intact.

### 15. Shape shoreline planting with moisture pockets and local relief

Wet-woodland guidance describes localized wet areas, transitions to drier ground, and drier knolls within broader wet habitats. This supports a more varied arrangement than assigning plants solely by distance from water. [cdn.forestresearch.gov.uk](https://cdn.forestresearch.gov.uk/2022/02/fcpg008.pdf?utm_source=chatgpt.com)

**OpenRC decision:** compare one approved shoreline segment against a candidate with authored wet, intermittently wet, and dry patches. Combine those masks with local elevation and the existing water exclusions.

Keep the overall plant allowance and open-water area controlled. Include bare interruptions and dry islands where they improve the composition.

**Accept it when:** planting has credible breaks and transitions from low and overhead views, without floating vegetation or plants entering excluded water. This is an authored habitat treatment; it should not be presented as a hydrological simulation or a commitment to the British species used in the reference.

### 16. Assess dandelions and revisit the documented pine source

Poly Haven’s current listings describe Dandelion 01 at approximately 64K source triangles and Pine Sapling Small at approximately 398K. These are source-asset counts, not proposed runtime budgets. [Poly Haven](https://polyhaven.com/a/dandelion_01?utm_source=chatgpt.com)

**OpenRC decision:** inspect a selected dandelion object/LOD as a low rosette and flower accent. For pine, reuse the project’s prior intake evidence before doing more acquisition work.

Pine Sapling Small was already downloaded and inspected in [L6a-R1](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/visual-quality-implementation/L6a-R1/README.md): three roughly one-metre forms, 398,144 source triangles, and no supplier LOD or wind channel found in that inspection. Its geometry remained outside runtime.

**Accept either source when:** a converted representation adds a useful, recognizable form at the intended viewing distance and meets the existing packaging and performance constraints. No new download or native test was performed in this round.

---

## C. Eight new investigations into textures, performance, motion, and flight use

### 17. Qualify the compressed leaf texture, not just the source image

BC7 and ASTC encode color, alpha, and channel relationships differently. A format suitable for a color texture is not automatically the best treatment for masks or normal data. [GitHub](https://github.com/ARM-software/astc-encoder/blob/main/Docs/Encoding.md?utm_source=chatgpt.com)

**OpenRC decision:** compare one lossless reference against formats actually supported by the pinned importer and target device. Hold mip generation, alpha cutoff, geometry, and lighting fixed.

Record effective format, memory, surviving alpha area at each mip, and normal-direction error where applicable. Then inspect the moving crown at 1080p.

**Accept it when:** the smaller representation preserves leaf boundaries, crown mass, and shading without repeatable fringes or holes. Keep masks in the correct data space, and preserve the current wind-material contract. A generic ORM conversion is not a drop-in change for this adapter.

### 18. Diagnose atlas contamination before changing the texture architecture

Mipped atlases need sufficient separation between images. Texture arrays isolate layer mip chains, but impose their own resource constraints, including matching dimensions and mip counts. [NVIDIA Docs](https://developer.nvidia.com/docs/drive/drive-os/6.0.7/public/drive-os-linux-sdk/common/topics/graphics_content/Textures124.html?utm_source=chatgpt.com)

**OpenRC decision:** first use diagnostic border colors and inspect each slot through the current shader. Compare padding against a texture-array prototype only if contamination is reproduced.

The current source inspection found transparent margins and no border pixels passing the tested alpha threshold. It did not establish an existing bleed defect.

There is also a world-data boundary: [tree assets](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/tree_assets.gd) and [treeline selection](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/treeline.gd) use three identities. Adding slots or changing the mapping requires collision and replay review.

**Accept it when:** any demonstrated contamination disappears with the smallest justified change.

### 19. Measure transparent area alongside geometry cost

Arm’s engineering guidance explains that cutout rejection can occur after fragment work, while very small triangles can also waste shading work. Triangle count alone cannot determine the better representation. [developer.arm.com](https://developer.arm.com/community/arm-community-blogs/b/mobile-graphics-and-gaming-blog/posts/finding-and-fixing-hidden-performance-problems-in-mobile-games-with-arm-performance-studio?utm_source=chatgpt.com)

I performed a new calculation on the committed [source atlas](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/assets/landscape/trees/atlas.png), counting pixels with alpha ≥ 0.5 in each 512 × 512 tile:

| Source form | Pixels passing the threshold | Passing fraction |
|---|---:|---:|
| Oak | 75,448 | 28.78% |
| Maple | 48,328 | 18.44% |
| Pine | 19,664 | 7.50% |

These are **source-image occupancy measurements**. They do not quantify GPU waste or predict a speedup.

**OpenRC decision:** test tighter cards in an isolated single-species fixture. Integration must then account for the current shared mesh, UV/mask alignment, wind, pivots, bounds, and any additional batches.

**Accept it when:** measured limiting cost improves while silhouette and motion quality remain intact.

### 20. Check whether grass visibly stretches as it bends

AMD’s grass example and the original ResponsiveGrass implementation adjust Bézier control segments to approximately preserve blade length during deformation. This is a visual approximation, not a complete mechanical plant model. [AMD GPUOpen](https://gpuopen.com/learn/mesh_shaders/mesh_shaders-procedural_grass_rendering/?utm_source=chatgpt.com)

**OpenRC decision:** first reproduce visible stretching in a supported camera view. If it exists, compare the current bend against a restrained root-anchored treatment on one suitable supplied grass form.

Measure apparent root-to-tip length and displacement over a wind cycle, including translated, rotated, and uniformly scaled instances.

**Accept it when:** roots remain fixed, visible stretching decreases, and ground penetration or culling problems do not increase. If the current safe amplitude already looks convincing, retain it. The research does not justify importing AMD’s mesh-shader architecture or treating arbitrary shrubs as individual Bézier blades.

### 21. Test minimum spacing inside existing plant colonies

Bridson sampling efficiently enforces a chosen minimum separation. It does not encode ecological relationships or automatically provide consistent subsets for different quality levels. [cs.ubc.ca](https://www.cs.ubc.ca/~rbridson/docs/bridson-siggraph07-poissondisk.pdf?utm_source=chatgpt.com)

**OpenRC decision:** use it only for a bounded offline comparison where a real spacing problem has been identified. Preserve the existing colonies, density variation, exclusions, and species dominance.

This method is already referenced in project research. The [current meadow implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/runway_meadow.gd) uses a jittered Vogel spiral, so this investigation does not establish that OpenRC lacks a considered placement approach.

**Accept it when:** the candidate reduces unwanted overlaps while preserving clumps, repeatable identities, and nested quality behavior. Reject an arrangement that makes the landscape resemble an evenly spaced orchard. Woody movement also requires the corresponding world revision.

### 22. Verify motion history for the custom vegetation clock

Temporal reconstruction depends on valid current and previous motion, including vertex deformation. Camera discontinuities require suitable history reset behavior. Godot’s architecture documentation and the FSR2 integration manual establish those requirements, but do not prove how every custom uniform behaves in OpenRC’s exact engine build. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/engine_details/architecture/internal_rendering_architecture.html?utm_source=chatgpt.com)

**OpenRC decision:** investigate the optional temporal profile using static-camera/animated-wind, moving-camera/frozen-wind, combined motion, pause/resume, reset, and clock-wrap cases.

The project already has [reconstruction reset handling](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/reconstruction.gd). This is a hypothesis to test, not a diagnosed missing-reset bug.

**Accept it when:** foliage motion produces no persistent trails or stale silhouettes and aircraft readability remains acceptable. Preserve the deterministic simulation clock; changing to wall-clock animation would not resolve the underlying verification question.

### 23. Evaluate background clutter where the aircraft crosses vegetation

The CHI 2005 feature-congestion study relates perceived clutter to color and luminance-contrast distributions. Its experiment involved ranking printed maps; it did not validate an aircraft-control or dynamic flight-recognition metric. [p500-rosenholtz.doc](https://www.mit.edu/~yzli/clutter.pdf?utm_source=chatgpt.com)

**OpenRC decision:** use a local color/contrast diagnostic to help explain difficult backgrounds, alongside randomized human A/B clips of identical recorded approaches.

Ask concrete questions about roll, heading, and landing cues. Include two contrasting aircraft, an unchanged control, and a deliberately degraded control.

**Accept it when:** vegetation preference improves without a meaningful loss in recognition under a criterion defined before the comparison. The diagnostic should explain results, not become a universal numerical release gate.

This investigation should accompany denser crowns, brighter flowers, and more varied forest edges, because those changes alter the background against which the aircraft must be read.

### 24. Separate loading, scene insertion, and first visible GPU use

Godot’s threaded load retrieval can block if the resource is not ready. Its threading guidance also distinguishes background loading from active scene-tree operations and GPU-facing resource work. Background I/O alone does not establish hitch-free rendering. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/io/background_loading.html?utm_source=chatgpt.com)

**OpenRC decision:** preserve existing caches and measure three stages separately: resource readiness, main-thread scene admission, and first visible use.

Exercise cold Home/Fly entry, the first forest approach, a rapid reversal, reset, and repeated returns Home with a bounded set of forms.

**Accept it when:** richer vegetation introduces no recurring spikes, unbounded queues, resource growth, or shared-material corruption. A prefetch/admission queue is justified only by a reproduced problem or a proposed camera-aware detail feature. The existing grass first-use work should remain part of the same effort.

---

## What I would prioritize for the vegetation upgrade

The 24 investigations should narrow the implementation backlog. They should not all become mandatory features.

| Order | Work package | Investigations | Intended result |
|---|---|---|---|
| **1** | Establish a coherent plant palette | 7, 9, 12, 13 | Credible proportions, useful overhead silhouettes, identifiable plant roles, and believable flowering states. |
| **2** | Resolve foliage appearance | 1, 2, 3, 17 | Consistent crown lighting, controlled translucency, stable highlights, and intact leaf textures. |
| **3** | Improve one habitat pocket | 10, 11, 14, 15, with 23 | A woodland edge, boundary, or shoreline with recognizable structure and clear aircraft backgrounds. |
| **4** | Address demonstrated cost problems | 18, 19, 24 | Better card geometry or loading behavior supported by actual measurements. |
| **5** | Run conditional refinements | 4, 5, 8, 16, 20, 21, 22 | Targeted improvements for a specific angular, temporal, seasonal, asset, or placement need. |
| **6** | Keep architectural research deferred | 6 | Avoid a major rendering investment until simpler representations leave a concrete unmet requirement. |

### The first visual milestone

I would define the first milestone as **one convincing section of the Club woodland edge**, containing:

- Distinct young and mature crown forms with credible proportions.
- Consistent lighting between imported trees and distant representations.
- Selected leaves that respond convincingly to backlighting.
- Openings that reveal depth behind the front row.
- A restrained mixture of flowering, vegetative, and seed-stage plants.
- A few grounded forest-floor details visible from relevant cameras.
- Aircraft crossings that remain easy to interpret.

That scene would provide a concrete reference for expanding the approach elsewhere.

The existing project limits still apply: **1080p first**, frame **p95 ≤ 18 ms**, **p99 ≤ 25 ms**, simulation/wall ratio **0.99–1.01**, and the initial **+0.5 ms frame-p95 allowance shared by all new visual work combined**. Those are retained acceptance targets, not results achieved by this research. The governing requirements are in the [global performance and visual-quality plan](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/plans/global-performance-visual-quality.md) and [tree/forest plan](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/plans/tree-forest-quality.md).

The strongest direction from this second round is **greater coherence at every scale**: the structure of an individual leaf, the proportions of a tree, the arrangement of a grove, and the composition of the landscape seen behind the aircraft.The next visual upgrade should focus on the ground around the runway
I completed a focused follow-up covering 24 investigations and 27 external references, including real RC flying fields, turf research, game-development presentations, and forum discussions.

My recommendation is to make the Club field feel like one attractive, maintained place with a history of use: related shades of green, finer turf detail, restrained wear, believable access paths, uneven growth at fences, and a convincing transition into the RC track.

The complete 20-page illustrated brief includes real photographs, the generated concept board, current repository findings, implementation priorities, and acceptance criteria.

OpenRC_Ground_Realism_Runway_200m_2026-11-09.pdf

I audited source at commit f47d1dc6cccb141936407d0217eafdc465558190. The concept is an art-direction target; it is not an implemented engine result. This pass did not change simulator code or produce a new native 1080p capture.
1. The most important finding: OpenRC already has much of the necessary groundwork
The current Club field already uses photographic grass detail. The field setup enables it, and the shader uses that texture to modulate the underlying field palette. Imported grass plants follow a separate material path.

That changes the recommendation: the first work should examine base color, photographic detail, mowing brightness, and plant color separately, then bring them into agreement. Simply enabling another grass texture would not address that relationship. See the pinned Club ground setup and ground shader.

Several other features also exist already:
Area	What is already present	What I would improve
Runway	Directional mowing, subtle touchdown wear, and a mown-to-rough boundary	Their visual strength, continuity, and relationship to surrounding grass
Nearby vegetation	Separate imported grass, fallback blades, and runway-meadow systems	Ground agreement, silhouettes, grouping, and placement
Fence line	Bounded grass/clover planting around flightline posts	Variation between posts, openings, and less-used sections
RC circuit	A terrain-sampled track mesh, dirt coverage, surface detail, and vegetation exclusions	The appearance of the outer grass-to-soil transition
Paths	Authored pedestrian tracks, vehicle tracks, and gravel shoulders	Connections to destinations, edge color, and overly regular bands
Countryside	Cultivated parcels with crop rows and tramlines	Crop-to-soil contact, headlands, access, and field boundaries


These findings come from the current runway meadow, flightline planting, RC field integration, ground features, and countryside implementation record.

My main diagnosis is therefore an integration problem to investigate: different surface and vegetation systems can each contain useful detail while still producing an artificial-looking whole.

The specific “C” shapes remain unresolved. I have not identified their generating layer in a current native image, so I would not label them a confirmed noise, texture, or placement bug yet.
2. What the real photographs suggest
The strongest references were actual flying clubs and RC tracks. They show how maintained turf, human activity, and surrounding vegetation coexist.
A maintained runway can remain convincingly green
RC Wingers describes a regularly mown grass runway surrounded by hay. Triad and Dare County also document maintained grass flying areas. These are useful references for preserving a cared-for club atmosphere. rcwingers.com

The Brackenheim aerial photograph is particularly useful because the runway, pilot area, access road, and neighboring agricultural rows all have distinct visual structure within one landscape. mfvb.de
The strongest wear belongs around activity
The Stoney Creek photograph shows a clear relationship between parking, shelters, benches, fencing, and the access route. That is the kind of spatial logic I would carry into OpenRC. The photograph alone does not establish the cause of every pale patch. Home

Turf research also distinguishes damage to the plants from longer-term soil compaction. Several stresses can produce similar appearances, which is why the art should suggest plausible use without assigning a complicated explanation to every color change. umass.edu
RC track edges need their own treatment
The Arnprior track photograph shows exposed soil, sparse edge plants, and more established vegetation occupying different parts of the scene. It is a strong visual reference for an irregular transition with a clearly usable driving surface. Arnprior Radio Control Club

The direction I take from these references is a predominantly green field, with variation concentrated where mowing, traffic, boundaries, and cultivation give it meaning.
3. The changes I would prioritize visually
A. Give the grass a coherent family of greens
I would establish a restrained palette with several related roles:
- A dominant natural green for maintained turf.
- Slightly lighter or more olive variation within mown areas.
- Deeper greens in selected rougher pockets.
- Small amounts of pale or dry blades.
- Soil color where grass coverage actually becomes thin.
The important relationship is between those roles. A patch of turf, a nearby tuft, and the grass at a fence should look as though they belong to the same place and lighting.

I would review the base ground, photo modulation, runway brightness, imported grass, and meadow independently under a fixed camera and sun. The existing material separation makes that a more useful first experiment than a broad scene-wide color adjustment. The inspected ground path also has no general grass specular lobe, so the initial investigation should concentrate on color, scale, filtering, and plant integration. Current material implementation.
B. Find the repeated shapes before adding more variation
The current base system combines a repeating tile, translated samples, and several scales of procedural variation. That means a recognizable shape could come from a source texture, a blend, a broad procedural component, or their interaction. The distant parcel function begins well outside the first 200 m, so it should not automatically be blamed for a nearby mark. Grass surface implementation.

I would use one exact view containing the reported “C” and compare:
1. The normal material.
2. Reduced or neutralized broad color variation.
3. The existing detiling contribution changed in isolation.
4. Near photographic detail changed in isolation.
5. Relevant vegetation layers hidden.
The result should identify which component owns the shape. Only then would I alter that component’s contrast, source material, or spatial pattern.

This matters because extra noise can leave the original repetition visible while making the rest of the field busier.
C. Make close grass look fine-grained
The near surface should communicate a mixture of small blades, gaps, and occasional dry material. I would judge the texture’s apparent scale against known objects: runway width, benches, fence posts, and the RC vehicles.

At a low camera position, the surface can show individual detail. From the pilot position, that detail should combine into believable turf. Farther away, mowing and coverage should carry the image.

I would also avoid making every visible plant a conspicuous decorative tuft. The grass immediately outside a maintained strip needs a progression of heights and coverage, with taller clumps reserved for suitable locations.

The current photographic and procedural detail paths already have distance and footprint filtering, so this is a calibration task within an existing system. Turf detail and near material sampling.
D. Make mowing bands quieter and more responsive to the view
Real mowing stripes depend partly on leaf orientation, reflected light, and the observer’s position. Their apparent brightness is therefore more complex than alternating paint colors. Turfgrass Science

OpenRC already includes directional behavior. I would tune it using matched views from both ends of the runway and under different sun angles.

The target is:
- A runway that remains easy to recognize.
- Modest tonal differences within the same grass family.
- Plausible changes as the camera moves.
- No dominant fluorescent bands or overly crisp rectangular pattern.
This should retain the pleasing order of a mown flying field.
E. Add the restrained central wear you described by refining the existing wear
The shader already contains touchdown-related wear. I would start there and compare a slightly more natural treatment:
- Interrupted thinning through plausible used areas.
- Small amounts of fine soil showing between blades.
- Less uniform coverage within individual worn patches.
- Green turf continuing between those patches.
For the runway’s middle, I would test a subtle used strip that becomes clearer at close range. It should remain visually subordinate to the grass runway as a whole.

The wear should also be appropriate to the activity. Foot traffic around a gate, RC vehicle use on a circuit, and aircraft use on a flying strip should have distinct appearances.
F. Give the runway edge a gradual transition in height, coverage, and color
The shoulder is one of the highest-value places to improve because it is visible from the pilot and from low views.

I would coordinate four elements:
Element	Intended appearance
Mown turf	Short, relatively continuous grass
Outer shoulder	Small variations in coverage and tone
Fringe	Unequal small plants and slightly greater height
Rougher grass beyond	More varied groups, with open gaps


The transition should remain recognizable as a maintained mowing boundary. Its small irregularities should not form repeated scallops, identical crescents, or an uninterrupted dark outline.

OpenRC’s meadow already defines a mown lip and fringe, so the first step is to inspect that system together with the ground material. Existing meadow implementation.
G. Integrate the RC track through both material and vegetation
For the RC circuit, I would aim for this progression:

Used dirt surface → irregular mixed fringe → established grass.

The mixed fringe is where several changes need to agree:
- Soil coverage.
- Grass density.
- Surface color.
- Small-scale normal detail.
- Plant height and contact with the ground.
A soft color blend alone can still look artificial if the grass stops abruptly elsewhere. Equally, adding clumps will not fix a mismatched soil boundary.

The existing circuit uses a separate surface sampled from track and terrain data. Vegetation clearances must continue to follow that authority. The right experiment is to inspect straight sections, bends, and access transitions before changing the outer verge—not to relax every exclusion globally. Track integration and track mesh.
H. Make paths and marks connect actual destinations
I would trace a person’s plausible route through the existing Club layout:

Parking and access → shelters or benches → gate → pilot or runway area.

Then I would check that the authored paths actually connect those destinations.

Useful details include localized thinning where people stand, a more used gate opening, and modest variation around bench feet. Vehicle marks should follow the course or access route and have an appropriate scale.

This is also a good place to inspect the current path edges: some authored ground features use a fixed approximation of the field color, which could require adjustment if a mismatch is reproduced under the active lighting. Authored ground features.
I. Make fence growth uneven and believable
The flightline already has grass/clover planting around posts. I would vary that treatment selectively:
- A few posts with denser growth.
- Some relatively clear stretches.
- Shorter or thinner turf at regularly used openings.
- Occasional small soil exposure.
- Different group shapes and orientations.
Fence-line vegetation can vary with maintenance, so every fence segment does not need the same continuous tall border. blog-crop-news.extension.umn.edu

The result should preserve the openings and sightlines while making the fence feel established in the ground.
J. Improve roots, leaves, and small contact details
I would pay particular attention to the bottom of each grass clump. If the roots are visibly a different color from the ground, the plant can look placed on top of the terrain.

For a demonstrated mismatch, I would test a modest contribution from local ground color near the roots, fading toward the tips. Species and tip variation should remain visible.

This has a useful precedent in the REDengine 3 development presentation, which describes a terrain pigment map with a bottom-up influence on grass. It is inspiration for a bounded experiment in OpenRC. media.gdcvault.com

A few small leaves or dry blades could help near selected posts, benches, or tree edges. Their scale, contact, and distribution matter more than their quantity. I would keep these details quiet from the pilot’s normal view.
K. Use small shrubs and flowers as localized accents
A small shrub can add character at an outer fence corner, a less-maintained boundary, or a suitable transition toward the wider landscape.

I would place these accents deliberately and vary the surrounding grass with them. A shrub should look rooted in a small habitat pocket, with appropriate ground cover and space around it.

Near the runway, the composition should stay open. Small clover or flower accents can contribute to richness without producing a repeated scatter of bright dots.
L. Refine crops after the immediate Club ground works
Crops remain part of the plan, but the current source already includes substantial countryside work outside the central flying area.

The useful questions are now:
- Do the visible plants meet the intended cultivated soil?
- Do rows relate sensibly to parcel shape?
- Are field entrances and turning areas plausible?
- Do borders look managed?
- Does each parcel have a coherent plant state?
USDA material describes field borders as functional perennial vegetation that can support machinery movement and habitat. Those functions are useful design references; their regional dimensions and species prescriptions should not be copied automatically into OpenRC. nrcs.usda.gov
4. What other games and developers contribute
The useful lesson across these sources is to coordinate systems around a common landscape intent.
Source	Relevant lesson	Application to OpenRC
REDengine 3 / CD Projekt RED	Terrain color can influence grass from the roots upward	Test local root agreement where imported plants visibly separate from the ground
Call of Duty terrain rendering	Hiding repetition can require additional texture samples and different treatment at distance	Diagnose the current repetition first; measure the cost of any retained sampling change
Delta Force terrain and biome technology	Shared spatial information can coordinate terrain and vegetation; blending may need different behavior at distance	Reuse common field intent across grass, soil, and plants
GIANTS Editor	Field definitions, terrain, and foliage need to align	Treat cultivated parcels as coherent agricultural units
Riders Republic	Routes are designed in relation to terrain and intended use	Connect OpenRC’s paths and wear to the actual site layout


These are source-specific techniques and workflows. They do not establish OpenRC’s implementation cost or justify adopting another engine’s terrain system. media.gdcvault.com

The Polycount and Epic discussions were useful for recurring practical problems: mismatched ground colors, oversized clumps, obvious texture repetition, and grass transitions around roads. I treated these as artist observations that suggest experiments. polycount

One technical qualification matters: height-aware blending can help certain material joins, but it needs suitable height information. The official O3DE tutorial illustrates that approach; OpenRC’s retained grass/dirt set does not by itself establish a validated height map. Open 3D Engine
5. The 24 investigations completed in this focused pass
Each investigation in the report includes the current evidence, a recommended experiment, and an acceptance condition.
Group	Investigations
Color, pattern, and scale	1. Coherent green family; 2. reported C-shaped patterns; 3. detail scale
Mowing and runway wear	4. mowing response to light; 5. restrained central wear; 6. runway shoulder
Textures and plants	7. photographic detail strength; 8. map alignment and blending; 9. root-to-ground agreement
RC track and access	10. RC verge; 11. appropriate surface marks; 12. connected paths
Fence and nearby nature	13. fence and gate growth; 14. meadow grouping; 15. small contact details
Agriculture	16. current crop/soil integration; 17. headlands and row direction; 18. field borders
Distance and motion	19. the 200 m priority area; 20. filtering and temporal stability; 21. wind and plant identity
Delivery and validation	22. actual renderer behavior; 23. data reuse and budget; 24. realism and flight usability


6. How I would organize the implementation
First delivery: one connected, convincing part of the Club
I would use the pilot area, gate/fence, runway shoulder, and an RC track shoulder as the first review area.
Stage	Work	Required outcome
1. Establish the current reference	Capture matched native views; locate the C pattern; separate material and vegetation contributions	Each visible issue has a supported owner
2. Tune the field appearance	Adjust the responsible color/detail controls, mowing contrast, and existing wear	A convincing normal pilot view and reverse view
3. Integrate the edges	Refine RC verge, path connections, gate/post variation, and plant contact	Ground, plants, and routes agree from pilot and low-camera views
4. Validate and extend	Check motion, renderers, and performance; then refine farm details	An accepted first area before expanding coverage or species


I would keep this within the existing ground, grass, scenery, and RC code paths. The report maps the responsibilities to the exact repository files.
Treat 200 m as an art priority
For planning, these are useful viewing bands:
Approximate range	Detail that deserves attention
0–25 m	Fine turf, plant roots, small soil exposure, fence/gate contact
25–80 m	Coverage, clump grouping, mowing, paths, and surface transitions
80–200 m	Broad field structure, coherent color, rough/mown organization, and landscape composition


These are review bands, not proposed hard draw-distance rings. Camera height, field of view, zoom, and driving views can change which detail matters.

The existing near-grass patch is pilot-relative, while the meadow and RC views have different requirements. That distinction must remain visible in implementation planning. Near-grass source.
Define success through native images and motion
The first comparison should establish that:
- The field stays pleasantly green.
- Repeated shapes stop attracting attention.
- The runway remains easy to recognize.
- Wear looks localized and purposeful.
- Plants meet the ground naturally.
- Grass and soil transition convincingly around the RC circuit.
- Slow pans, zoom, and low driving views remain stable.
- Aircraft visibility and usable track space remain clear.
The current project uses multiple renderer paths, so the actual build, renderer, reconstruction setting, and input resolution need to be recorded with comparisons. The repository’s current stack and renderer decisions are the controlling references.

Performance qualification should retain the existing project gates, including the shared initial allowance of +0.5 ms at frame p95 for all new visual work, rather than allocating that amount independently to each grass improvement. No such timing result was measured in this audit. Global visual-performance plan.

The first milestone I would prioritize is a continuous, believable transition from the pilot’s turf to the fence and gate, across the runway shoulder, and into the RC track’s outer verge. That gives the project a concrete place to judge the qualities you asked for: finer grass, natural greens, modest wear, convincing soil contact, and an attractive landscape that feels used and maintained.