# Representations, tools and engine choices

2026-11-18. Primary references are indexed in [sources](sources.md). Statements
about another product describe the cited version; the recommendation and effort
assessment are engineering judgments, not comparative OpenRC benchmarks.

## What other RC simulators establish

| Reference | Source-supported observation | Lesson for OpenRC |
| --- | --- | --- |
| aerofly RC10 | Photo scenery uses an observer viewpoint; multipano offers several stations; 4D permits free movement and time-of-day changes ([S01](sources.md#s01)) | Expose representation capabilities instead of promising the same camera behavior everywhere |
| RC10 scenery workshop | A 16,384×8,192 panorama is converted into 32 files and packaged with starts and terrain/collision data ([S02](sources.md#s02)) | Author a complete site, not only a large image. The example does not reveal its internal tile layout or prescribe OpenRC's runtime format |
| RealFlight G3.5 | A documented depth-only proxy can hide aircraft behind a photographed object and participate in collision/shadows ([S03](sources.md#s03)) | Visual occlusion and contacts are feasible with separately authored geometry; Godot still needs its own verified composition path |
| RealFlight 9.5 | Documents 360°×180° equirectangular import, recommends 8000×4000 or larger, restricts movement in PhotoFields, and leaves photographed objects unaffected by some visibility settings ([S04](sources.md#s04)) | Image detail, fixed viewpoint and baked scene content are practical product constraints |
| RealFlight Evolution | Official product material distinguishes 3D fields and PhotoFields ([S05](sources.md#s05)) | The two representations can coexist in one simulator; an older manual is not proof of Evolution's internal renderer |

The photographic route is particularly suited to ordinary RC line-of-sight
flying because the pilot normally remains at one position while the model moves.
Its visual plausibility comes from real captured detail. This does not remove
the need for accurate contact surfaces, occlusion, scale and aircraft lighting.

## Representation decision matrix

Ratings below are qualitative estimates for this project's scope.

| Approach | Fixed pilot | FPV / moving observer | Dynamic lighting | Work and risks | Disposition |
| --- | --- | --- | --- | --- | --- |
| One panorama + calibrated proxies | Strong candidate | Inadequate nearby parallax | Photograph remains captured | Lowest initial geometry work; station/occlusion/shadow calibration still required | First pilot |
| Several calibrated panoramas | Strong at each station | Discrete stations only | One captured condition per asset set | More capture, calibration, memory and transitions | Later |
| Terrain/orthophoto + optimized meshes | Good | Suitable after route/terrain integration | Possible on modeled/cleaned content | Survey, cleanup, materials, LOD, physics alignment and device cost | Second track |
| Full raw photogrammetric mesh | Can look convincing | Coverage-dependent | Baked lighting limits relighting | High triangle/texture cost, holes, noisy ground and ugly closeups | Process into the optimized-mesh route |
| Hybrid 3D foreground + distant photo background | Good | Suitable within a defined camera volume | Mixed | Remove duplicated near objects; distant background still needs view-volume validation | Preferred composition for the 3D experiment |
| Gaussian splats / NeRF | Promising appearance | Requires sufficient captured views and a qualified renderer | Usually requires separate relighting work | Depth, motion, holes, collisions, stereo, portability and license uncertainty | Bounded later experiment |
| Streamed commercial geospatial tiles | Region-scale context | Service/integration dependent | Mostly captured | Online service, attribution, caching/redistribution constraints, runway-scale quality | Outside the offline pilot |

NeRF and splats are not the same implementation. The original Gaussian
Splatting research describes a radiance representation and rendering method
([X01](sources.md#x01)); it does not provide a drop-in Godot airfield, a contact
solver or OpenRC hardware measurements. The reference implementation's license
has noncommercial research/evaluation restrictions ([X02](sources.md#x02)).
Other implementations require their own inspection; the restriction is not a
claim about the mathematical technique as a whole.

## Recommended toolchain

Start with **Hugin + Blender + the current Godot project** for the photo pilot.
Add **OpenDroneMap/WebODM and QGIS/GDAL** when building the 3D site. Compare
Terrain3D with ordinary Godot meshes after the required physical-ground contract
is understood. Install only the tools required by the next experiment and pin
their selected versions; this research has installed none.

| Tool | Useful role | Limitation / selection rule |
| --- | --- | --- |
| Hugin | Open panorama stitching, exposure alignment, masks and HDR workflows ([C01](sources.md#c01)) | First choice for a repeatable fixed-station panorama; retain the stitch project and inspect near seams |
| PTGui | Commercial stitching alternative; documented Standard/Pro feature split ([C04](sources.md#c04)) | Evaluate on the same capture if Hugin costs significant manual effort; confirm required HDR/masking feature tier |
| Blender | Proxy authoring, scan cleanup, UV/bake/decimation, metric landmarks and GLB delivery ([G05](sources.md#g05), [P10](sources.md#p10)) | Treat export and in-engine import as separate checks; an attractive authoring render is not runtime qualification |
| OpenDroneMap / WebODM | Photo reconstruction with georeferenced point clouds, textured mesh, orthophoto and optional DTM/DSM ([P01](sources.md#p01)) | Good initial area-reconstruction candidate. Record capture/GCP/check-point quality, settings and computation cost; do not run a raw output as a finished game level |
| QGIS / GDAL | Inspect reference systems, georeference, crop/reproject/resample rasters and preserve transforms ([A03](sources.md#a03), [A04](sources.md#a04)) | Keep metre scale, vertical datum, no-data and raster orientation explicit during conversion |
| Terrain3D 1.1.0 | Optional Godot terrain/region/LOD authoring and rendering ([T01](sources.md#t01), [T04](sources.md#t04)) | Exact 4.8.beta2, renderer, export and physical-ground integration are unproven. Full Metal support is unclear in its platform docs; instanced foliage collision is not supplied automatically ([T02](sources.md#t02), [T03](sources.md#t03)) |
| Meshroom / AliceVision | Node-based photogrammetry, especially a small landmark study ([P04](sources.md#p04), [P05](sources.md#p05)) | Current reviewed 2025.1.0 binaries have CUDA requirements; CPU draft meshing is a different quality path. Do not promise equivalent Mac processing |
| COLMAP | Scriptable camera reconstruction and dense-reconstruction research ([P06](sources.md#p06)) | Current install docs describe CUDA and AMD HIP/ROCm, while FAQ wording still says CUDA for dense. Pin and test the actual build/backend; more asset processing remains |
| RealityScan desktop | Proprietary reconstruction alternative; distinguish it from RealityScan Mobile ([P07](sources.md#p07), [P08](sources.md#p08)) | Current desktop download page lists Windows/Linux and NVIDIA requirements. Review actual seat eligibility/terms; the tool's license does not supply image rights |
| Agisoft Metashape | Commercial alternative to evaluate for geospatial and Mac authoring workflows ([P09](sources.md#p09)) | Compare editions and supported acceleration for the actual dataset before buying; no speed advantage is established here |
| Poly Haven / ambientCG | CC0 sky, texture and model sources for replaceable 3D details ([A01](sources.md#a01), [A02](sources.md#a02)) | A generic HDRI is useful for a shader test but is not a surveyed RC field. Retain per-asset provenance |

### Terrain3D compatibility is a gate, not an assumption

Version 1.1.0 advertises Godot 4.5–4.8+ compatibility. Its versioned platform
page supports several rendering paths but does not establish full Metal
coverage. Therefore test OpenRC's actual Mobile/Metal route on Apple Silicon,
not only a Vulkan demo. A working plugin editor session also does not qualify
the final exported native library or simulator ground sampling.

Keep a small ordinary-mesh alternative for the same field. If a static near
runway plus distant meshes meets quality and memory budgets, Terrain3D may not
be worth its runtime/deployment surface. If larger terrain or editability is
valuable, benchmark the incremental benefit with the identical field, aircraft,
route and graphics settings. Its reported demo frame rates are not transferable.

### Rights and distribution

Track four independent things: authoring-tool license, source-image/dataset
rights, any processing-service terms, and the redistributable output package.
Using open-source software does not make proprietary input photographs free.
Blender's license guidance separates its application from created artwork
([P10](sources.md#p10)); that does not settle third-party asset rights.

Use owned captures or clearly licensed sources for the shipped field. Do not
extract RealFlight/aerofly assets based on similarity of technique. Preserve
attribution requirements and modification history. Current Google Map Tiles
policies constrain extraction, caching/offline use and attribution
([A05](sources.md#a05)); their photorealistic tiles are not a shortcut to an
offline redistributable OpenRC field. A future service-based integration would
have different requirements and costs.

## Godot, native C++ and another engine

The two primary questions are **how the site is represented** and **which
component renders it**. Changing the renderer does not recover camera positions,
missing geometry or source rights from a photograph.

| Option | What it can contribute | OpenRC-specific cost / trigger |
| --- | --- | --- |
| Existing Godot | Panorama and mesh rendering, materials, current UI, camera, loading, asset and release systems | Recommended. Verify new composition within current platform constraints |
| Godot + C++ GDExtension | Bounded parsing, conversion, preparation or runtime work through native shared libraries ([G06](sources.md#g06), [G07](sources.md#g07)) | Use only for a profiled bottleneck; preserve API/build/precision compatibility and fallback. It does not automatically improve GPU shading |
| Independent native C++ renderer | Direct ownership of platform graphics and rendering architecture | Requires importer, materials, terrain/LOD, UI, camera/XR, profiling, lifecycle and releases; no measured benefit currently justifies that program |
| Unreal | Nanite and a substantial 3D-content toolchain ([X03](sources.md#x03)) | Requires a new host integration and exact target-feature assessment; no automatic port of GDScript sessions, UI, replay or existing shaders |
| Unity | Alternative content pipelines including high-end HDRP ([X04](sources.md#x04)) | Host/asset/UI/physics boundary migration and platform-specific pipeline choices; compare only against a demonstrated requirement |
| UNIGINE | Simulation-oriented terrain and double-coordinate capability leads ([X05](sources.md#x05)) | Select a concrete supported release and inspect its terms/platforms before any bake-off; vendor future-branch docs are not an adopted dependency |

The existing native evaluator is not yet a complete engine-independent
application. Wrapping one C++ evaluator in another engine would still leave
session semantics, input, events, replay, scenery queries, presentation and UI
to implement. The [earlier engine study](../../moonshot/engine-world-2026-10-28.md)
already identifies that distinction. Reopen an engine decision only after
SC-PHOTO produces a reproducible failing requirement and a smaller fix is
insufficient.

## Decision outcome

Use two prototypes with one coordinate/provenance discipline: a fixed-eye
photographic site first, then a small optimized 3D site for moving views. Choose
tools through a representative dataset, not by popularity or a promotional
screenshot. Keep a synthetic fixture for renderer correctness and a surveyed
field for real visual/physical alignment; neither alone proves the other.
