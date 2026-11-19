# Two-round search record

Research date: **2026-11-18, America/Bogota**. This follow-up answers the request
for at least twenty additional investigations of photographic/game-scenery
techniques, searched in two stages and checked against OpenRC's GitHub source.
The [twenty investigations](additional-techniques.md) contain the conclusions;
this document preserves how the questions and evidence were selected.

## Scope and sequence

Exactly **20 distinct search queries** were executed: ten in round 1, then ten
in round 2. Within each round the independent queries were dispatched in groups
of four, three and three. All ten first-round searches returned before round 2
was constructed and executed. Direct source opens and text finds were follow-up
verification, not extra searches counted toward twenty. Research helpers audited
repository evidence and reviewed conclusions; they did not add unlogged searches.

The unit of investigation is a technical question with a source, an OpenRC
integration assessment and a falsifiable experiment. A tool name, a second URL
for the same claim or an old technique described again is not an additional
implementation. Some questions deliberately reassess existing/rejected methods;
those histories are identified rather than advertised as new discoveries.

## Round 1: breadth, first ten searches

The initial questions cover image-based representation, terrain scale, material
repetition, scanned assets, distant detail and coordinate precision. Historical
papers establish methods; current vendor documentation supplies implementation
leads. Only primary sources support the resulting technical claims.

| Investigation | Question area | Exact query | Retained source record |
| --- | --- | --- | --- |
| [PT-01](additional-techniques.md#pt-01) | Geometry-assisted photographic reprojection and view-dependent textures | `Debevec Modeling and Rendering Architecture from Photographs hybrid geometry image based approach view dependent texture mapping paper` | [E01](sources.md#e01) |
| [PT-02](additional-techniques.md#pt-02) | Layered depth images for limited viewpoint movement | `site:microsoft.com/en-us/research "Layered Depth Images"` | [E02](sources.md#e02) |
| [PT-03](additional-techniques.md#pt-03) | Geometry clipmaps for terrain detail over distance | `site:developer.nvidia.com/gpugems2 terrain rendering GPU based geometry clipmaps` | [E03](sources.md#e03) |
| [PT-04](additional-techniques.md#pt-04) | Virtual texturing for large photographic terrain materials | `site:dev.epicgames.com runtime virtual texturing landscape` | [E04](sources.md#e04) |
| [PT-05](additional-techniques.md#pt-05) | Stochastic texture tiling and blending | `"Procedural Stochastic Textures by Tiling and Blending" Heitz Deliot` | [E05](sources.md#e05) |
| [PT-06](additional-techniques.md#pt-06) | Game production photogrammetry and lighting removal | `Photogrammetry Star Wars Battlefront GDC 2016 DICE delighting materials` | [E06](sources.md#e06) |
| [PT-07](additional-techniques.md#pt-07) | Octahedral impostors for distant photographed or scanned objects | `"octahedral impostors" "Ryan Brucks"` | [E07](sources.md#e07) |
| [PT-08](additional-techniques.md#pt-08) | Hierarchical LOD and merged distant scene proxies | `site:dev.epicgames.com world partition hierarchical level of detail HLOD meshes` | [E08](sources.md#e08) |
| [PT-09](additional-techniques.md#pt-09) | Parallax occlusion and height mapping for close surfaces | `site:docs.godotengine.org "Deep Parallax" "triplanar"` | [E09](sources.md#e09) |
| [PT-10](additional-techniques.md#pt-10) | Precision and camera-relative presentation for geospatial scenery | `site:docs.godotengine.org "large world coordinates" rendering precision` | [E10](sources.md#e10) |

## What round 1 changed

- Image-based methods trade measured geometry, capture coverage and supported
  movement against source detail. They do not make a single panorama an arbitrary
  FPV scene. This made zoom/detail residency a separate second-round question.
- Clipmaps and virtual textures are different systems: one manages terrain
  geometry; the other manages/caches surface data. OpenRC has finite static
  chunks and staged construction, so either would add real infrastructure.
- The DICE production source documents removal of captured lighting before new
  lighting is applied. This led to separate baked-lighting and reflection questions.
- Source review found existing hashed photographic turf, filtered material detail,
  bounded vegetation batches, failed ridge LOD seams and a rejected specific
  impostor bake. Repeating those proposals without controls would be unhelpful.
- Current source uses feature probes and renderer-specific paths. Old Godot
  results cannot establish capability on the pinned 4.8 beta build, so round 2
  includes alpha coverage, decals and material filtering with version checks.

## Round 2: ten adaptive searches

These questions were selected after round 1 and the first repository findings.
They address remaining image-detail, surface, lighting, edge-stability and
resource-lifecycle questions rather than adding more engine names.

| Investigation | Question area | Exact query | Retained source record |
| --- | --- | --- | --- |
| [PT-11](additional-techniques.md#pt-11) | Multiresolution panorama pyramids and bounded tile residency | `site:krpano.com documentation multiresolution cube tiles level` | [E11](sources.md#e11) |
| [PT-12](additional-techniques.md#pt-12) | Height-aware terrain material blending | `site:dev.epicgames.com landscape material layer height blend` | [E12](sources.md#e12) |
| [PT-13](additional-techniques.md#pt-13) | Decals and mesh overlays for local surface detail | `site:docs.godotengine.org decals Compatibility mesh plane` | [E13](sources.md#e13) |
| [PT-14](additional-techniques.md#pt-14) | Baked lighting and probes for moving aircraft | `site:docs.godotengine.org LightmapGI dynamic objects probes Compatibility rendering` | [E14](sources.md#e14) |
| [PT-15](additional-techniques.md#pt-15) | Localized reflection probes and image-based lighting | `site:docs.godotengine.org ReflectionProbe box projection update once Mobile Compatibility` | [E15](sources.md#e15) |
| [PT-16](additional-techniques.md#pt-16) | Coverage-aware foliage textures and alpha antialiasing | `site:docs.godotengine.org alpha antialiasing alpha coverage mipmaps MSAA foliage` | [E16](sources.md#e16) |
| [PT-17](additional-techniques.md#pt-17) | Normal/roughness prefiltering to reduce specular shimmer | `site:docs.godotengine.org normal map roughness limiter specular aliasing` | [E17](sources.md#e17) |
| [PT-18](additional-techniques.md#pt-18) | Atmospheric lookup tables and aerial perspective | `"A Scalable and Production Ready Sky and Atmosphere Rendering Technique" Hillaire` | [E18](sources.md#e18) |
| [PT-19](additional-techniques.md#pt-19) | Shell-and-fin vegetation representation | `"Real-Time Fur over Arbitrary Surfaces" shells fins` | [E19](sources.md#e19) |
| [PT-20](additional-techniques.md#pt-20) | Threaded asset loading and bounded scenery residency | `site:docs.godotengine.org background loading load_threaded_request get_status resource` | [E20](sources.md#e20) |

### Why each second-round query was selected

- **PT-11:** Round 1 image-based methods preserve source-detail limits; the existing 1-degree zoom needs a memory-aware solution.
- **PT-12:** Stochastic tiling does not solve runway shoulders and mud/grass transitions; current rectangular masks need a separate surface-boundary comparison.
- **PT-13:** A large texture or virtual texture is excessive for runway markings, stains and local wear; compare bounded overlays and renderer fallback.
- **PT-14:** DICE reconstruction requires lighting decisions; evaluate a fixed-lighting scene with dynamic aircraft instead of adding unrestricted runtime GI.
- **PT-15:** Photographed/scanned scenery and a moving aircraft must share a plausible lighting environment without assuming panorama color equals radiance.
- **PT-16:** Impostors and HLOD can fail at moving foliage edges; ordinary leaf mipmaps already have a documented rejection in this repository.
- **PT-17:** Close-surface height and photo textures can shimmer at RC view scales; investigate material filtering separately from added geometry.
- **PT-18:** Large terrain and HLOD need consistent distance cues; compare structured atmospheric rendering with the existing haze and photographed atmosphere.
- **PT-19:** Investigate a different vegetation representation rather than repeating the previously rejected impostor baker or increasing tree density.
- **PT-20:** Clipmaps, HLOD and panorama tiles require safe loading; test the fit with the existing staged World lifecycle and physical-world independence.

## Source selection and retrieval limits

The search engine was asked for original author/project or vendor material.
Search results alone were not treated as proof of the intended source/version.
The retained sources include Berkeley/Microsoft research, NVIDIA's authored
technical chapters, the DICE GDC presentation, Epic, Godot, SideFX, krpano and
original paper authors. Each E01–E20 record links the supporting primary pages.

The following cases affected interpretation:

- **PT-07:** the impostor query returned secondary discussion. The retained
  evidence is SideFX's own tool documentation; no secondhand blog quote or claim
  of a drop-in Godot addon is adopted.
- **PT-11:** the targeted krpano query returned third-party summaries/packages.
  Those were discarded as technical evidence. The vendor XML reference was
  opened directly and its multiresolution image/tile sections checked.
- **PT-13:** stable Godot decal guidance excludes Compatibility, while current
  OpenRC source documents a 4.8 Compatibility path and probes decal creation.
  The outcome is exact-build capability verification plus the existing fallback,
  not a blanket supported/unsupported declaration based on either text alone.
- **PT-15:** search returned both 4.0 and 4.5 reflection-probe documentation with
  different Compatibility descriptions. The current stable class reference was
  opened to check its renderer limits. The old exclusion was not retained.
- **PT-16:** the initial web search found the alpha-coverage setting in latest
  documentation, not the retrieved stable page; the pinned importer fetch was
  unavailable. The later resource audit corrected the initial conclusion using
  [GDU-11a](../../engine-upgrade/GDU-11/README.md) and the tracked maple import:
  OpenRC already adopted coverage-preserving maple mipmaps with bounded native
  beta1 evidence. Exact beta2, new-asset and platform behavior still need their
  own qualification. The original twenty query/order records above are unchanged.
- The DICE PDF's lighting-removal section was inspected as text. No slides,
  imagery, game assets, addons or binaries were downloaded into the repository.

## GitHub compatibility baseline

The branch reviewed was `03b028c58d953e603c42323e10529e29926b6fa0`, whose runtime
parent is `f7b348e40aa5a44c4cc091d540fbffb55016e583`. GitHub main was also fetched
at `84e1caf0cc3db9c3b974f387aaf0dc3ed9259f6d`. The diff contained no changes in
`app/landscapes`, `app/render`, `app/scenery`, `app/environment`, `app/sim`,
`app/physics`, `app/project.godot` or the engine downloader. The inspected
`app_root.gd` delta concerns telemetry and Home notices, not scenery construction
or camera routing. The research branch was not rebased or merged with that main
update; the checked identities remain explicit.

Tracked shaders/data missing on disk were read from Git's tree. The main
[architecture audit](current-architecture.md) remains the entry point; the
[follow-up compatibility audit](additional-techniques.md#repository-evidence)
adds the material, LOD, precision and resource-lifecycle findings needed here.

## Recorded outcomes

| Investigation | Outcome |
| --- | --- |
| PT-01 | Adapt projected geometry; defer free-view blending until measured. |
| PT-02 | Defer to a bounded viewpoint experiment; missing surfaces remain a problem. |
| PT-03 | Conditional 3D terrain work; preserve shared edges and authoritative contact sampling. |
| PT-04 | Defer a new runtime page-cache system; compare simpler baked materials first. |
| PT-05 | Retain the current blend as baseline; earlier detiling investigations already exist. |
| PT-06 | Prioritize a controlled scan/material authoring comparison for the 3D site. |
| PT-07 | Retain the documented candidate rejection; require a materially different proposal. |
| PT-08 | Use Godot-native visibility ranges and authored proxies if measured draw cost warrants it. |
| PT-09 | Restrict to a small close-view material experiment; never substitute it for physical relief. |
| PT-10 | Keep the surveyed local frame; no global-coordinate or engine-precision migration by default. |
| PT-11 | Compare tiled detail only if capture detail and the simple panorama's limits justify it. |
| PT-12 | Compare one runway shoulder transition before extending the full ground shader. |
| PT-13 | Reuse the renderer capability probe and plane fallback; resolve documentation/version differences. |
| PT-14 | Conditional authored fixed-lighting 3D scene; account for editor-only baking and dynamic aircraft probes. |
| PT-15 | Reuse bounded probe refresh ownership; verify the actual renderer rather than old documentation. |
| PT-16 | Retain the already-adopted maple coverage recipe and its bounded beta1 evidence; qualify new assets, beta2 and platforms separately. |
| PT-17 | Compare offline roughness filtering only after confirming the target material's specular response, with a normal-map control. |
| PT-18 | Keep existing haze initially; any LUT atmosphere change belongs to the shared world owner. |
| PT-19 | Defer a bounded grass-patch experiment; the source demonstrates fur, grass is an adaptation. |
| PT-20 | Extend staged loading deliberately; threaded resource loading alone is not a scenery streaming system. |

The [implementation plan](../../../plans/photorealistic-flying-sites.md) remains
the only work-status ledger. These searches are completed research. Their
suggested experiments have not been run and no compatibility/performance result
is claimed from publication of this record.
