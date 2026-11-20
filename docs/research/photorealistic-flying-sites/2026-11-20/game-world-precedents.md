# Games, simulators and terrain techniques

Reviewed: 2026-11-20. This follow-up adds **24 investigations backed by 72 distinct search queries**. Numbering continues the [32-option study](global-scenery-options.md). These entries distinguish documented behavior from proposed OpenRC adaptations. They are source reviews, not runtime or performance results. The [integration decisions](README.md) map the useful lessons to the existing SC-PHOTO sequence; the [search record](search-record.md) preserves every query.

A visible repository or public tutorial does not establish production readiness. Code, dependencies, data services, photographs and generated assets can have different licenses. Reusing a technique does not require adopting its engine or shipping its assets.

## Games that build real places

### 33 Arnis: staged world generation and terrain repair

**Documented mechanism.** Arnis combines OSM, elevation and land cover to build a Minecraft/Luanti world. Its ground-generation guide describes conditional median filtering to remove anomalous elevations while retaining rough terrain, hole filling and diagnostic comparisons. Large selections can coarsen the elevation grid. [Repository](https://github.com/louis-e/arnis) · [Ground-generation guide](https://github.com/louis-e/arnis/wiki/Ground-Generation).

**OpenRC adaptation and limit.** Use explicit preparation stages and record every repair in a mask with original values and parameters. Runway and steep-slope control points should challenge a proposed repair. Arnis may compress relief to fit game height limits; OpenRC must retain metric scale. The guide supports the filtering description; this review did not establish exact implementation thresholds or validate its output.

### 34 BuildTheEarth Terra++: geographic spawn and provider adapters

**Documented mechanism.** Terra++ assembles a geographic Minecraft environment from elevation and map sources, with configurable providers and caching. Geographic teleport commands connect latitude/longitude to the generated world. It depends on the Minecraft Forge/CubicChunks ecosystem. [Repository and documentation](https://github.com/BuildTheEarth/terraplusplus).

**OpenRC adaptation and limit.** Keep provider access behind a versioned preparation interface and store the origin with the site. A coordinate-based selector can resolve to a prepared package and validated spawn. Geographic anchoring alone does not prove correct physical scale, altitude or runway support. The MIT code license does not replace OSM data obligations or the terms of individual elevation providers.

### 35 maps4fs: rules that turn map tags into game assets

**Documented mechanism.** The inspected maps4fs fork produces Farming Simulator authoring inputs: terrain, surface masks, fields, splines and background meshes. Its texture schema supplies OSM filters, default widths and drawing priorities; generation information records several component settings and bounds. [Inspected fork](https://github.com/ZenJakey/maps4fs) · [FS25 texture schema](https://github.com/ZenJakey/maps4fs/blob/main/data/fs25-texture-schema.json).

**OpenRC adaptation and limit.** Put tag-to-material, width, exclusion and precedence rules in versioned data rather than scattered renderer code. Label inferred widths as defaults. The original URL was unavailable during this review; the fork is an inspected example, not a maintenance endorsement. Its editor templates and background seams can need manual finishing. Component-specific generation information is not proof of a complete provenance manifest.

### 36 GeoMapgen: compile GIS inputs into bounded chunks

**Documented mechanism.** GeoMapgen converts GeoTIFF terrain and optional cover/river data into an indexed database for a Minetest world generator. Its configuration externalizes the legend that maps land-cover classes to game biomes. [Source](https://github.com/gaelysam/geo-mapgen) · [Example configurations](https://github.com/gaelysam/geo-mapgen-demos).

**OpenRC adaptation and limit.** Precompute bounded site chunks and keep classification rules inspectable. Runtime loading should consume prepared data rather than reinterpret a global GIS dataset. This is a historical experimental project with game-specific scale choices; neither current Luanti compatibility nor RC-scale fidelity was established. Its database layout is inspiration, not a proposed OpenRC runtime dependency.

### 37 Blosm: assemble features against one terrain reference

**Documented mechanism.** Blosm imports terrain and OSM context into Blender, using building attributes for procedural shapes and curves/profiles for roads. Its terrain workflow provides a reference surface for feature placement. [Project](https://github.com/vvoovv/blosm) · [Documentation](https://github.com/vvoovv/blosm/wiki).

**OpenRC adaptation and limit.** Use a shared origin, datum and named terrain source while placing buildings, trees and roads. Preserve whether geometry came from a measured height, an OSM tag or a default. Coarse elevation and procedural buildings provide context, not surveyed collision geometry. Optional premium features and third-party photogrammetry have separate access and redistribution terms; public plugin source does not grant rights to those assets.

### 38 BeamNG Terrain and Road Importer: bake road grading

**Documented mechanism.** BeamNG's guide combines a 16-bit heightmap with road nodes and widths. The importer conforms roads to terrain, flattens road cross-sections and blends shoulders through a configurable influence region. The documented importer ignores road-node Z values. [Official walkthrough](https://documentation.beamng.com/beamng_tech/tools/terrainandroadimporter/).

**OpenRC adaptation and limit.** Use this as a runway-authoring model: preview a centerline/profile, width, crossfall, shoulder and grading region, then save an explicit new physical surface. Do not assume this importer preserves surveyed grades or creates bridges. Preserve the original terrain and quantify the edit. This is a proprietary-tool workflow precedent; no BeamNG dependency or engine migration is proposed.

### 39 cs-mapgen: manifests and artifact hashes

**Documented mechanism.** This Cities: Skylines generator describes a pipeline from geographic extent and configuration to heightmaps, road GeoJSON and a manifest containing input identity and artifact hashes. [Repository](https://github.com/KarlCarriere/cs-map-generator).

**OpenRC adaptation and limit.** Reuse the manifest pattern: hash licensed inputs, transforms, rule versions, seeds and generated products. State axis order explicitly at every interface. The project's reproducibility claim was not benchmarked here; matching hashes in one pinned environment does not establish cross-platform determinism. Its early CS2 scale/sea-level questions and road-guide output need qualification. MIT code and map-data rights remain separate.

### 40 SC4Mapper 2026: water is a semantic layer

**Documented mechanism.** SC4Mapper combines real-world elevation with optional OSM water masks for SimCity 4 regions. Its documentation addresses dry land below sea level and adapts terrain to the game's single water-plane model. [Repository](https://github.com/caspervg/SC4Mapper-2026).

**OpenRC adaptation and limit.** Retain separate elevation, water classification, water-surface height and validity channels. A negative elevation is not automatically water. Do not copy the terrain deformation used to accommodate SimCity's water model. Web Mercator coverage and selection limits also require explicit handling; a convenient web-map projection is not proof of full polar support.

## Simulators and globe applications

### 41 OSM Drone Simulator: bounded visual streaming

**Documented mechanism.** The browser simulator documents an aircraft-centered tile ring, a default 3×3 neighborhood, distance-prioritized loads and memory/IndexedDB caches. It uses Terrarium terrain and map-derived context. [Repository](https://github.com/OlivierB-OB/osm-drone-simulator) · [Tile-ring design](https://github.com/OlivierB-OB/osm-drone-simulator/blob/main/docs/tile-ring-system.md).

**OpenRC adaptation and limit.** Borrow bounded visual prefetch, cancellation and cache accounting. Its [elevation sampler](https://github.com/OlivierB-OB/osm-drone-simulator/blob/main/docs/data/elevation-sampler.md) returns zero for unloaded terrain; OpenRC must return an explicit unavailable result instead. The [detailed decoder](https://github.com/OlivierB-OB/osm-drone-simulator/blob/main/docs/data/elevations.md) includes the offset omitted by the simplified README formula. This MIT prototype's frame-driven movement is not a replacement for OpenRC's flight integrator.

### 42 CARLA: an intermediate semantic road representation

**Documented mechanism.** CARLA's OSM workflow converts map data into OpenDRIVE and then generates a world mesh. Parameters control mesh detail and junction handling; the guide recommends zero wall height to avoid overlapping road walls in this workflow. [Official guide](https://carla.readthedocs.io/en/latest/tuto_G_openstreetmap/).

**OpenRC adaptation and limit.** Keep geographic features in an intermediate representation before generating visual and physical products. Validate crossings, widths and terrain registration. A road network is not a complete landscape. Converter behavior varies with version: [current source](https://carla.org/Doxygen/html/d1/dcd/OSM2ODR_8cpp_source.html) warns about a highway filter not being honored. CARLA code, assets, Unreal and SUMO-derived tooling have distinct licensing scopes.

### 43 Eclipse SUMO: typemaps and explicit inference

**Documented mechanism.** SUMO's OSM wizard and netconvert build road scenarios with configurable typemaps. Elevation options can read node ele tags or estimate relative levels from layer tags; its documentation describes limitations of 3D elevation. [Import guide](https://sumo.dlr.de/docs/Networks/Import/OpenStreetMap.html) · [Wizard tutorial](https://sumo.dlr.de/docs/Tutorials/OSMWebWizard.html).

**OpenRC adaptation and limit.** Preserve bridge, tunnel, layer, road class and projection metadata through preparation. Layer is relative ordering, not measured bridge clearance. Mark inferred heights and refuse unsupported structures for contact until reviewed. Check image registration when projection settings change. SUMO's EPL-2.0/secondary-license arrangements require exact component review; it is not a blanket MIT dependency.

### 44 Gazebo Sim: a shared source for visual and collision terrain

**Documented mechanism.** Gazebo's DEM tutorial clips and inspects a GeoTIFF, then references the terrain from separate SDF collision and visual heightmaps. The guide distinguishes heightfields from meshes needed for caves or overhangs. [Official DEM walkthrough](https://gazebosim.org/api/sim/10/heightmap_dem.html).

**OpenRC adaptation and limit.** Compile visual meshes and the physical sampler from one canonical, versioned surface, while allowing independent visual simplification. Read physical dimensions from the geotransform and units; pixel counts do not generally equal meters. Bridge decks and overhangs need separate geometry. This is an architectural lesson from an Apache-2.0 simulator, not a proposal to replace OpenRC's solver with Gazebo.

### 45 Webots: configurable imports and registration checks

**Documented mechanism.** Webots' OSM importer exposes independent feature classes and an optional elevation mode. The guide recommends relatively small areas for interactive performance. [Importer documentation](https://github.com/cyberbotics/webots/blob/master/docs/automobile/openstreetmap-importer.md).

**OpenRC adaptation and limit.** Let authors select roads, buildings, barriers and vegetation, then verify projected control points and draping before compilation. An [issue report](https://github.com/cyberbotics/webots/issues/6948) describes a rotated elevation grid and undraped objects in one case; that is a useful fixture, not evidence that all imports fail. Webots' Apache-2.0 code and separately licensed assets need distinct review.

### 46 NASA WorldWind Java: ingest once and query prepared tiles

**Documented mechanism.** InstallElevations uses TiledElevationProducer to prepare a file cache and configure an elevation model. Its local-source API can explicitly signal missing data when the needed high-resolution tile is absent. [Example](https://worldwind.arc.nasa.gov/java/latest/javadoc/gov/nasa/worldwindx/examples/dataimport/InstallElevations.html) · [Elevation model API](https://worldwind.arc.nasa.gov/java/latest/javadoc/gov/nasa/worldwind/terrain/BasicElevationModel.html).

**OpenRC adaptation and limit.** Separate expensive ingestion from fast lookup, retaining level, bounds, resolution and availability. Require a complete physical neighborhood before flight admission. This Java globe SDK is not a Godot plugin or aircraft simulator. Review the exact release and dependencies; later Java releases use Apache-2.0, while historical versions have different context.

### 47 OpenSpace: coarse global terrain with local overrides

**Documented mechanism.** OpenSpace layers imagery and elevation on a globe. Its local DEM guide describes checking alignment, reprojecting a patch and presenting it through GDAL VRT metadata. [Local-patch guide](https://docs.openspaceproject.com/latest/building-content/globebrowsing/creation/build-local-dem-patches.html) · [Globe reference](https://docs.openspaceproject.com/latest/reference/asset-components/Renderable/RenderableGlobe.html).

**OpenRC adaptation and limit.** Express coverage and precedence explicitly: a high-detail airfield patch can override a coarse visual background. Avoid requests outside actual coverage. The documented workaround may load empty tiles beyond the patch; do not copy that behavior uncritically. The MIT visualization application does not establish collision accuracy or flight-simulation timing.

### 48 Cesium for Unreal: georeferencing is separate from physics residency

**Documented mechanism.** Cesium combines globe coordinates, a local georeference and view-dependent terrain streaming. Its tutorial explicitly warns that frustum-culled tiles cease to participate in physics. [Object-placement tutorial](https://cesium.com/learn/unreal/unreal-placing-objects/).

**OpenRC adaptation and limit.** Retain persistent geographic identity and render locally, but pin physical coverage independently of camera visibility and visual LOD. Turning the camera must never remove supporting ground. An Apache-2.0 Unreal plugin is not a Godot drop-in; engine, content-service, imagery and offline rights remain separate. Global travel also needs an explicit evolving local-frame and gravity design.

## Terrain algorithms and practical guides

### 49 Geometry clipmaps: a bounded visual terrain budget

**Documented mechanism.** Geometry clipmaps use nested grids around the viewer, with coarser outer rings, incremental updates and transitions between levels. [GPU Gems 2 implementation chapter](https://developer.nvidia.com/gpugems/gpugems2/part-i-geometric-complexity/chapter-2-terrain-rendering-using-gpu-based-geometry).

**OpenRC adaptation and limit.** This is a useful explanation of predictable terrain rendering cost and a reference when assessing existing terrain plugins. Regular grids may spend triangles on flat regions. Keep the canonical contact surface independent of camera-centered geometry. The chapter's implementation is not a supported Godot addon, and its public availability does not by itself establish a permissive code-copying license.

### 50 CDLOD: adaptive terrain patches

**Documented mechanism.** CDLOD organizes terrain in a quadtree and applies a consistent distance-based LOD and morphing scheme. The repository includes the paper and an older DirectX demonstration under MIT. [Source and paper](https://github.com/fstrugar/CDLOD).

**OpenRC adaptation and limit.** Compare adaptive patches only if an existing plugin or mesh pipeline cannot meet a measured need. Evaluate altitude changes, long views and transition behavior on the same prepared terrain. This algorithm is a rendering candidate, not a contact representation; porting an old API demonstration would add maintenance and renderer qualification work.

### 51 MARTINI: error-controlled terrain meshes

**Documented mechanism.** MARTINI builds RTIN terrain meshes from a regular grid and selects a mesh with a specified elevation error. The ISC-licensed project is described as experimental. [Source](https://github.com/mapbox/martini) · [Interactive explanation](https://observablehq.com/@mourner/martin-real-time-rtin-terrain-mesh).

**OpenRC adaptation and limit.** Try offline simplification of distant visual terrain before adding a new runtime renderer. The example's error setting is not an RC contact tolerance. Neighboring independently simplified tiles can disagree along edges; [the project discussion](https://github.com/mapbox/martini/issues/7) makes this a concrete integration issue. Constrain shared edges. Skirts can hide visual gaps but do not define a valid physical seam.

### 52 Quantized-mesh: an existing terrain interchange format

**Documented mechanism.** Cesium's quantized-mesh specification encodes tile meshes with per-tile bounds and quantized coordinates. Tooling exists to generate this format; the inspected Docker wrapper uses the mesh-capable terrain-builder fork. [Specification](https://github.com/CesiumGS/quantized-mesh) · [Builder wrapper](https://github.com/tum-gis/cesium-terrain-builder-docker).

**OpenRC adaptation and limit.** Use an established interchange format if a compatible client or globe pipeline creates a concrete requirement. Pin the actual fork, revision and container rather than assuming every similarly named builder supports Mesh output. Quantized delivery is not lossless canonical terrain storage. Preserve input elevations, encoding ranges and decoder tests; dependency licenses and build provenance remain to be checked before adoption.

### 53 OGC 3D Tiles: sparse hierarchies and screen-space error

**Documented mechanism.** 3D Tiles implicit tiling describes quadtree/octree structure through templates and availability data. Geometric error supports view-dependent refinement. [OGC specification](https://docs.ogc.org/cs/22-025r4/22-025r4.html) · [Implicit-tiling guide](https://github.com/CesiumGS/3d-tiles/blob/main/specification/ImplicitTiling/README.adoc) · [Official samples](https://github.com/CesiumGS/3d-tiles-samples).

**OpenRC adaptation and limit.** Reuse the format and sparse-coverage ideas for a later large photogrammetry library. Derive tile bounds from the root and integer level/index instead of accumulating recursive floating-point error. This machinery is unnecessary for the first local offline field, and visual screen-space error must not select the physical contact surface.

### 54 Godot large-world coordinates: isolate the precision decision

**Documented mechanism.** Godot documents double-precision engine builds, corresponding export templates and extension compatibility, with a large-world demonstration. [Engine guide](https://docs.godotengine.org/en/latest/tutorials/physics/large_world_coordinates.html) · [Demo](https://godotengine.org/asset-library/asset/2786).

**OpenRC adaptation and limit.** Keep geodesy and simulation state in their existing high-precision domain and render near a local origin first. OpenRC's pinned stock build must not be described as a double-precision engine. A custom engine/export/GDExtension rebuild is a separate experiment after a measured failure, with shader and platform checks. Current upstream documentation is not certification of OpenRC's exact beta build.

### 55 gltfpack and meshoptimizer: optimize a prepared visual package

**Documented mechanism.** gltfpack documents mesh/vertex optimization, quantization, optional simplification, texture compression and preservation switches. Output extensions depend on selected options. [Official usage guide](https://github.com/zeux/meshoptimizer/blob/master/gltf/README.md).

**OpenRC adaptation and limit.** Begin with the existing pinned asset pipeline. Trial one tree and one hangar, then compare names, materials, transforms, metadata, appearance and size before expanding. Check supported extensions on the exact Godot build and actually import/export the candidate. Preservation flags do not replace semantic verification. Optimized visual geometry must not silently become the new authoritative contact model.

### 56 Unreal Landscape Splines: preview and bake linear earthworks

**Documented mechanism.** Landscape Splines can raise/lower a heightfield over a width and falloff region and paint a material layer. [Official guide](https://dev.epicgames.com/documentation/en-us/unreal-engine/landscape-splines-in-unreal-engine).

**OpenRC adaptation and limit.** Adapt this authoring interaction for runway strips, shoulders and drainage: preview the changed region, retain the original, and commit a versioned terrain edit. Save elevation encoding, scale, georeference and separate surface semantics together. The workflow is useful without moving OpenRC to Unreal. Public documentation is not a license to redistribute engine code or third-party assets.

## RC-specific cross-check: PicaSim

PicaSim's [parallax panorama notes](https://github.com/Rowlhouse/PicaSim/blob/main/ParallaxPanorama.md) discuss depth-aware reprojection and cubemap-border treatment. This reinforces the existing fixed-eye/hybrid research but does not make a single panorama a complete moving-camera world. Its [current README](https://github.com/Rowlhouse/PicaSim) identifies PolyForm Noncommercial 1.0.0 and separately limits reuse of contributed models/images. Treat it as a source-readable reference requiring rights review, not an unrestricted open-source asset/code pool. This cross-check is included in the 72 searches but is not counted as a twenty-fifth new investigation.

## What this round changes

The reusable design is a staged site compiler, versioned semantic rules, explicit repair/provenance data, authored runway grading and a bounded visual loader. Ordinary meshes remain the first moving-view control. Terrain plugins, alternative LOD algorithms and globe formats are conditional candidates with measured admission criteria. The source examples expose practical failure modes—zero returned for missing terrain, height compression, inferred bridge levels, water-plane deformation and view-dependent collision—that the OpenRC integration must deliberately avoid. See the [decision and fixture matrix](README.md#qualification-fixtures).
