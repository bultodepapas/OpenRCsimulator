# Twenty additional scenery-technique investigations

2026-11-18. **Research and proposed experiments; no runtime implementation or
hardware qualification.** The [search record](search-rounds.md) preserves the
first ten queries, the findings used to select the second ten, and retrieval
limits. E01–E20 in the [source register](sources.md#e01) support this follow-up.
PT identifiers identify investigations, not additional implementation steps.
The [SC-PHOTO plan](../../../plans/photorealistic-flying-sites.md) owns work status.

## Findings and recommended direction

Keep the fixed-pilot photographic prototype as the first delivery. Refine its
calibrated projected geometry and color/shadow composition, then compare tiled
detail only if the captured source and zoom tests justify it. For the moving
3D site, prioritize scanned assets prepared for new lighting, controlled ground
material transitions, local surface details and stable material filtering.

Reuse existing bounded reflections, material controls and staged construction.
Consider authored HLOD only where measured scene cost warrants it. Large terrain
clipmaps, runtime virtual texturing, layered-depth view synthesis, shell vegetation
and a new atmosphere system are conditional experiments with distinct costs.
These results give no reason to change engines before the Godot prototype.

Several techniques already have OpenRC research or implementation. The new value
is the comparison with photographic sites, exact integration boundaries and
additional tests. Prior rejected candidates retain their recorded disposition;
a publication or a new engine version alone does not reverse an appearance gate.

## Compatibility meaning

**C** means Compatibility, **M** Mobile (including the Apple Silicon Metal target),
and **F** Forward+. These are renderer routes, not simulation backends. A normal
mesh/texture/shader adaptation is a plausible route across them, not a statement
that a new shader has compiled or passed. Named properties and import features
must be checked on `4.8.beta2.official.cafc17a19`; stable/latest manuals and old
4.7.2 experiments are supporting evidence with different version boundaries.

**Photo** means the admitted fixed pilot station. **3D** means a camera volume
with moving views. A photographic proxy can be correct from the pilot while
being incorrect in a reflection, shadow capture, magnifier or translated camera.
Every secondary view therefore belongs in the representation contract.

| ID | Technique | Best application | OpenRC route and disposition |
| --- | --- | --- | --- |
| PT-01 | Geometry-assisted photographic projection | Photo; bounded later views | Conventional meshes/shaders, C/M/F candidates; refine the existing prototype proposal |
| PT-02 | Layered depth images | Restricted movement experiment | Custom representation and renderer; defer pending measured coverage benefit |
| PT-03 | Geometry clipmaps | Larger 3D terrain | New terrain/LOD infrastructure; conditional, with authoritative CPU ground data |
| PT-04 | Runtime virtual texturing | Large layered 3D surfaces | Engine-specific source; substantial custom Godot work, defer |
| PT-05 | Histogram-preserving stochastic texturing | Repeated photographic materials | Existing simpler detiling is the control; compare only for a demonstrated defect |
| PT-06 | Scan lighting removal and material reconstruction | Relightable 3D landmarks and ground | Offline authoring, conventional runtime assets; prioritize |
| PT-07 | Octahedral impostors | Distant 3D vegetation/landmarks | Prior candidate rejected; a different representation needs new evidence |
| PT-08 | Authored HLOD proxies | Distant groups in a 3D site | Godot visibility ranges and existing spatial batches; conditional measurement |
| PT-09 | Parallax/height mapping | Close 3D dirt, gravel or pavement | Selective material experiment; visual depth has no contact authority |
| PT-10 | Survey-local coordinates and render precision | All surveyed sites | Preserve current float64-to-render boundary; no floating-origin system by default |
| PT-11 | Tiled multiresolution panoramas | Photo zoom/detail | Custom offline pyramid and bounded residency; conditional after source-detail test |
| PT-12 | Height-aware material blending | 3D runway shoulders and margins | Adapt the shared ground shader with a limited layer count |
| PT-13 | Decals and fitted mesh overlays | Local 3D markings/wear | Reuse capability probe and plane fallback; exact C/M/F behavior must be measured |
| PT-14 | Lightmaps and irradiance probes | Fixed-lighting authored 3D site | Editor bake plus dynamic-aircraft probes; conditional scene-authoring work |
| PT-15 | Local reflection probes | Aircraft/objects in a 3D lighting context | Reuse shared World/probe ownership; C/M/F limits differ |
| PT-16 | Coverage-aware foliage filtering | Trees, cards and grass in motion | Latest import feature unverified on pin; conditional comparison, preserve silhouette |
| PT-17 | Normal-guided roughness prefiltering | Materials with an effective specular response | Verify the actual material first; offline processing and the runtime limiter are separate routes |
| PT-18 | Atmosphere lookup tables | Larger 3D sky/distance cues | Shared FW-owned extension; retain existing haze for the first site |
| PT-19 | Shell-and-fin vegetation | Tiny close-view grass experiment | Mesh/shader adaptation of fur research; defer due to overdraw and silhouette risk |
| PT-20 | Threaded loading and bounded residency | Site entry; later tiles/chunks | Reuse loader lifecycle, add budgets and publication rules; no physical streaming by graphics quality |

## Repository evidence

The audited research commit is `03b028c58d953e603c42323e10529e29926b6fa0`, with
runtime parent `f7b348e40aa5a44c4cc091d540fbffb55016e583`. Main was separately
checked at `84e1caf0cc3db9c3b974f387aaf0dc3ed9259f6d`; the relevant renderer,
landscape, scenery, environment, physics and engine-pin paths were unchanged.
The [search record](search-rounds.md#github-compatibility-baseline) scopes that check.

| Existing evidence | Consequence for this investigation |
| --- | --- |
| [Shared grass shader](../../../../app/render/grass_surface.gdshaderinc), [turf detail](../../../../app/render/turf_detail.gdshaderinc), [RC ground detail](../../../../app/render/rc_ground_detail.gdshaderinc) | Two hashed photographic samples, explicit derivatives and filtered detail already exist; preserve shared masks and matched material-map coordinates |
| [Grass quality plan](../../../plans/grass-quality.md), [meadow investigations](../../grass-meadow-techniques-2026-11-03.md) | Detiling, vegetation groups and density masks have prior work. The Laplacian candidate used eight versus two fetches without clear five-pose improvement; no timing advantage was established |
| [Ridges](../../../../app/render/landscape_upgrade/ridges.gd), [ridge LOD evidence](../../landscape-upgrade/LU-16-R2/README.md) | Current mountains are visual-only, offline-derived chunks. Independently simplified LODs broke shared edges; any new terrain method needs seam and transition controls |
| [Countryside](../../../../app/render/landscape_upgrade/countryside.gd), [LU-28 evidence](../../landscape-upgrade/LU-28/README.md) | Photographic roads/crops do not imply physical ground shape or tire material |
| [RC circuit ground](../../../../app/physics/ground_vehicle/airfield_track.gd) | A bounded analytic float64 heightfield overlay already exists for canonical Club geometry. It is a useful interface precedent, not a generic imported/streamed terrain provider |
| [Trees](../../../../app/render/field_tree_detail.gd), [treeline](../../../../app/render/treeline.gd), [scenery batches](../../../../app/scenery/scenery.gd) | Spatial batching already exists. MultiMesh bounds and LOD operate on batches; alpha fading alone does not remove submissions |
| [Tree cell comparison](../../visual-quality-implementation/L6c/map-expansion/README.md), [impostor result](../../visual-quality-implementation/L8b/2026-10-18/README.md) | More cells were not uniformly faster; one impostor configuration failed its appearance gate. Both are specific recorded candidates, not universal results |
| [Crash ground marks](../../../../app/render/crash/effects.gd), [imported vegetation](../../../../app/scenery/imported_vegetation.gd) | Decals have a runtime capability check and plane fallback. Imported vegetation rejects unsupported triplanar source materials |
| [Field builder](../../../../app/render/field.gd), [World](../../../../app/render/world/world.gd) | Staged construction is ordered scene building, not a terrain/page cache; shared World state needs explicit failure/cancellation ownership |
| [Atmosphere](../../../../app/render/atmosphere.gd), [lake reflection](../../../../app/render/lake/lake_reflection.gd), [planar reflection](../../../../app/render/lake/lake_planar_reflection.gd) | Dynamic lighting and bounded reflection updates already have owners; creating another writer/capture loop would duplicate responsibilities |
| [Frame conversion](../../../../app/render/frames.gd) | Float64 NED becomes render coordinates `(E, -D, -N)` at the boundary. Survey coordinates and render origins must not alter simulation state |

The [current architecture](current-architecture.md) remains authoritative for
strict field v1, separate photo metadata, runway orientation/material/start
limitations, camera/activity admission and native evaluator domains. No terrain
rendering technique in this document bypasses those contracts.

## Round 1 investigations

## PT-01

### Geometry-assisted photographic projection and view-dependent textures

**Evidence.** Debevec and coauthors combine approximate geometry with photographs
from known viewpoints; their later method selects and blends source views for a
surface. This is a documented alternative between a flat panorama and a fully
authored conventional asset ([E01](sources.md#e01)).

**OpenRC fit.** For the first fixed eye, project the photograph onto surveyed
runway/obstacle meshes that provide correct visibility and depth. This refines
the existing SC-PHOTO-02 opaque-proxy candidate. Multi-view blending is a separate
extension: it needs registered cameras, visibility, exposure matching and coverage
of newly visible surfaces. Captured lighting remains baked into those images.
Collisions still use the independently validated physical inventory. A shadow or
reflection camera cannot assume a pilot-projected surface is correct from its
own position.

**Experiment.** Render a synthetic runway and one shed with known camera poses;
compare one-eye projection, ordinary UV texture and a small multi-view variant.
Measure landmark error, seam/occlusion behavior and color across the declared
view envelope. Include shadow, reflection and magnifier routes or disable them
explicitly. **Disposition: prioritize single-eye composition; defer moving-view
blending until it beats a simpler textured mesh.**

## PT-02

### Layered depth images for limited movement

**Evidence.** A layered depth image stores multiple surfaces along input-camera
rays, allowing disoccluded samples to participate in a reprojected view
([E02](sources.md#e02)). The 1998 performance demonstration is historical.

**OpenRC fit.** This could be studied for a small observer offset around a
captured station. It requires hidden-surface imagery/depth, a representation and
rendering path, and explicit hole handling. A depth estimate from one photograph
does not supply measured unseen geometry. It does not grant free FPV, stereo
accuracy or collision truth. C/M/F support is an unimplemented adaptation.

**Experiment.** Use a known synthetic scene with measured depth, then introduce
depth errors and omitted background layers. Sweep the intended camera volume
and record holes, foreground-edge error, upload/residency cost and aircraft depth
composition. Compare against PT-01 and a cleaned mesh. **Disposition: deferred;
admit only a clearly bounded view volume if it offers a demonstrated benefit.**

## PT-03

### Geometry clipmaps for terrain over distance

**Evidence.** GPU geometry clipmaps organize height samples in nested regular
grids that update around the viewer, with transition regions between levels
([E03](sources.md#e03)). They concern geometry detail, not automatic physical
ground integration or photographic texture paging.

**OpenRC fit.** Potentially useful for a larger moving-camera site after the
small finite field. Current ridges are static visual chunks, and the existing
RC circuit overlay is narrowly tied to Club geometry. An imported heightfield
needs agreed float64 CPU sampling, triangle/interpolation convention, material,
normal, bounds, no-data and native/replay behavior. Visual LOD cannot determine
contact height. Clipmap centering must account for aircraft, pilot and secondary
views rather than assuming one camera is the whole world.

**Experiment.** Compare one measured finite grid against a nested-grid version
on the same terrain. Test seams, rapid travel, zoom, camera cuts, reset and
triangles crossing cell boundaries. Measure full-flight time and contact parity.
**Disposition: conditional 3D follow-up; keep ordinary meshes as the baseline.**

## PT-04

### Runtime virtual texturing and surface caches

**Evidence.** Unreal RVT generates/caches shading data over large areas and
supports terrain-conforming contributions such as roads and surface layers
([E04](sources.md#e04)). This is engine-specific infrastructure rather than an
interchangeable texture file.

**OpenRC fit.** A comparable Godot system would need page tables/atlases, residency
selection, generation or upload scheduling, invalidation, filtering and fallbacks.
No general system was found in the inspected runtime. A finite RC field with
static markings may be better served by bounded offline textures and overlays.
C/M/F differences matter if the design requires compute, render targets or
feedback passes. Visual material caches must not select the physical surface.

**Experiment.** First measure a fixed material atlas on a representative large
site. Only if texture or repeated-shading cost is demonstrated should a tiny
virtual-texture comparison be built, with missing pages, rapid turns, cold loads
and peak residency included. **Disposition: defer a general runtime system.**

## PT-05

### Histogram-preserving stochastic material tiling

**Evidence.** Deliot and Heitz describe stochastic blending with histogram
transforms and filtering treatment to reduce repeated natural texture patterns
without washing out their distribution ([E05](sources.md#e05)). Their Unity
prototype is a method reference, not a Godot dependency.

**OpenRC fit.** This is a reassessment, not a first discovery: prior grass
research already discusses histogram methods and rejected a Laplacian candidate.
Current photographic turf uses two hashed samples and explicit derivatives.
Before adding lookup textures or samples, identify visible repetition that the
existing macro/detail controls cannot address. Rotate normals consistently with
rotated UVs and share selection across albedo, normal and roughness. Preserve
world anchoring and the pilot-area readability controls.

**Experiment.** Compare the retained blend with one histogram candidate using
the same source maps and fixed contrast/scale. Include grazing, aerial, zoomed
and moving views, mip transitions, compressed output and shader cost. Disabling
it must avoid extra sampling. **Disposition: conditional on a specific defect;
the current material remains the control.**

## PT-06

### Remove captured lighting before relighting scanned assets

**Evidence.** DICE's Battlefront production presentation documents extracting
material maps and using object-space normals plus AO/cavity information to help
remove captured lighting ([E06](sources.md#e06)). It describes an authored
production workflow, not a perfect automatic recovery of reflectance.

**OpenRC fit.** A strong candidate for the later 3D field: prepare a small set
of scanned rocks, sheds or ground patches with usable base color, normals and
roughness, then let the shared World lighting illuminate them. A fixed-eye
panorama deliberately retains its capture appearance; applying this workflow
to that background indiscriminately would change its photographic reference.
Surface appearance and contact material remain separate authored inputs.

**Experiment.** Process one owned capture in raw-texture and lighting-reduced
variants. Compare against reference photographs under two known light directions,
checking doubled shadows, bright rims, color drift and roughness response.
Retain source, masks and reversible authoring steps; do not use guessed missing
detail as survey evidence. **Disposition: prioritize a controlled offline asset
study when SC-PHOTO-11 begins.**

## PT-07

### Octahedral impostors for distant objects

**Evidence.** SideFX documents capture sheets and several impostor projections,
including octahedral forms ([E07](sources.md#e07)). Such views can replace a
detailed distant object with a smaller rendered representation.

**OpenRC fit.** The repository already rejected one pinned full-sphere bake:
24.75% bad pixels against a 10% screen limit, with 42.331 MiB of two-atlas image
data for one form. Those were Godot 4.7.2/Windows measurements, not actual GPU
residency or a rejection of every impostor method. Existing tree cards and near
meshes are the comparison. Multiple forms, depth/normal maps and edge sampling
can erase a triangle-count saving through texture bandwidth and alpha overdraw.

**Experiment.** Reopen only for a materially different capture/representation
or documented defect fix. Preserve the old appearance fixtures, add overhead
FPV and low-pass transition views, and compare total atlas memory, shadows and
full-session cost. Physical trees stay identical and visibly represented at
every quality level. **Disposition: prior candidate remains rejected.**

## PT-08

### Authored hierarchical LOD and distant scene proxies

**Evidence.** Unreal HLOD groups distant objects into proxy representations;
Godot visibility ranges provide a native route for authored hierarchical LOD
alongside ordinary mesh LOD ([E08](sources.md#e08)).

**OpenRC fit.** Use the concept for a cluster of static farm buildings or distant
landmarks, with a material-preserving proxy. Existing cells already merge static
scenery and batch vegetation; do not treat additional merging as automatically
faster. One tree-cell comparison increased overview draws, and independent ridge
LOD simplification introduced seams. Keep dynamic, damageable or interactive
objects out of a frozen proxy unless their state transitions are designed.
Distance-only switching also needs zoom-aware treatment for the 1° pilot view.

**Experiment.** Compare one authored group with the same current assets/batches.
Measure submissions, visible primitives, texture memory, silhouette and material
agreement across approach, departure, zoom and overhead views. Check bounds,
hysteresis, shadow continuity and contact identity. Verify fade mode support per
renderer; a simpler non-fading transition is a possible measured fallback.
**Disposition: conditional 3D optimization under SC-PHOTO-11.**

## PT-09

### Parallax and height mapping for close ground detail

**Evidence.** Godot material height mapping searches a height texture along the
view direction to create apparent relief; it does not create geometry or
collision shape ([E09](sources.md#e09)).

**OpenRC fit.** A selective experiment for dirt/gravel or a close runway edge,
where the existing normal/roughness detail visibly lacks depth. Current custom
ground shaders would need deliberate integration; a StandardMaterial option is
not a switch that automatically affects them. Triplanar and imported vegetation
restrictions also remain separate. Grazing camera angles and repeated samples
can make the shader expensive, while wheel contact and silhouettes remain tied
to real geometry. Do not make a flat runway appear to contain deep physical ruts.

**Experiment.** Compare flat, normal-only and height-mapped versions of one
small patch at landing/RC/FPV angles. Sweep effective depth and distance cutoff;
check wheel intersections, shadow mismatch, self-occlusion artifacts and GPU
time. **Disposition: optional close-view quality feature, not a global default.**

## PT-10

### Survey-local coordinates and presentation precision

**Evidence.** Godot documents vector precision, the cost and binary requirements
of double-precision engine builds, and origin shifting as a different approach
([E10](sources.md#e10)). The documented planetary/open-world use cases do not
establish a need to change a finite RC field's engine build.

**OpenRC fit.** Retain the measured site datum and convert geospatial input into
small local metric coordinates before ordinary render-vector construction.
Simulation already uses float64 NED and converts at `frames.gd`; this is distinct
from an engine-wide double build. No general floating-origin system was found.
Changing a render origin later must also transform camera, shadows, reflection
bounds and atmosphere inputs while preserving panorama UVs, vegetation hashes,
contacts and numerical recording identities. Imported vegetation instance data
also has an existing packed-coordinate constraint.

**Experiment.** Transform held-out survey landmarks into the local frame and
round-trip them; render near/far geometry with the exact pipeline and inspect
jitter at zoom. Consider origin shifts only after a measured precision defect
and a complete dependent-state design. **Disposition: retain the current local
frame and precision boundary.**

## Round 2 investigations

## PT-11

### Multiresolution panoramic tiles for zoom-dependent detail

**Evidence.** krpano's own reference documents image pyramids and tiled panorama
projections ([E11](sources.md#e11)). This is an established representation and
delivery pattern; adopting the pattern does not imply embedding its viewer.

**OpenRC fit.** A conditional way to display a larger owned capture without
keeping every full-resolution region resident. Start with a complete low-detail
background, then bounded higher-detail pages/patches for the current view. A
single PanoramaSkyMaterial texture does not provide this cache automatically;
the alternative needs its own shader/composition, atlas/array policy and package
manifest. Capture resolution remains the hard limit: tiles do not create missing
image detail or correct translated viewpoints. Keep illumination/reflection
inputs stable instead of rebuilding them on every visible-page change.

**Experiment.** Compare a conventional 8K/16K image with one tiled higher-detail
master of the same scene. Exercise the actual vertical FOV range, abrupt 180°
turns, seam/poles, failed tiles, reset and site changes. Record visible resolution,
edge gutters, filtering, resident/peak RAM and VRAM, and upload hitches. Show a
coarse valid background while detail is unavailable. **Disposition: strongest
conditional extension if the simple panorama fails zoom/detail or memory gates.**

## PT-12

### Height-aware terrain material transitions

**Evidence.** Epic's landscape material reference distinguishes weighted/alpha
layers from height-aware blending, which changes how materials meet based on
their local height pattern ([E12](sources.md#e12)).

**OpenRC fit.** Useful for a grass/dirt shoulder, gravel penetration or an uneven
visual boundary in the 3D site. The current field has consolidated runway/mown
masks and shared ground/grass behavior. Start with one boundary and reuse those
authoritative region masks; extra visual layers cannot move a friction boundary
or add physical height. A photographed fixed-eye runway already contains its
captured transitions, so adding them again is generally unnecessary. More layers
multiply normal/roughness sampling and blend-normal work.

**Experiment.** Compare the existing transition against a two-material version
on the same edge. Check zero-weight cases, normal normalization, repeating height
patterns, distance filtering and agreement with visible vegetation roots.
Retain a baseline path that does not sample disabled maps. **Disposition:
bounded ground-material comparison, coordinated with existing ground owners.**

## PT-13

### Decals and fitted mesh overlays for local surface features

**Evidence.** Godot documents projected decals and a flat-surface alternative
using Sprite3D; its retrieved stable page excludes Compatibility
([E13](sources.md#e13)). Current OpenRC source, however, explicitly documents a
4.8 Compatibility path and checks whether decal creation yields a valid RID.
This conflict requires exact-build evidence rather than copying a version claim.

**OpenRC fit.** Reuse that probe/fallback strategy for authored runway markings,
patches, tire wear and stains on a 3D surface. Flat or terrain-fitted geometry
can provide a lower-dependency route. Set receiver layers, offsets and lifecycle
ownership so a mark does not project onto aircraft, water or unrelated objects.
Use the existing damage/scuff owners for dynamic effects. Static capture content
should not be overpainted twice in a photo site.

The current crash allocator counts its own `openrc_crash_ground_decals` group;
unregistered static runway decals could compete for the same receiver limit.
[GDU-11b](../../engine-upgrade/GDU-11/implementation.md#gdu-11b--terrain-crash-marks)
reserves the bounded pool for crash owners. Require scene-wide, receiver-aware
allocation before sharing projected decals with authored scenery, or use baked/
fitted overlays that do not consume that pool. A valid decal RID is not a
reservation of rendering capacity. The earlier GDU-11b 4.8.beta1 native checks
establish its tested crash path, not acceptance of a new beta2 site combination.

**Experiment.** Compare one texture bake, one fitted overlay and one projected
decal on the exact C/M/F paths. Test low approach angles, depth bias, mipmaps,
receiver limits and simultaneous static/crash marks, including requests beyond
the current eight-slot receiver budget. **Disposition: reuse existing capability
handling and select the simplest measured representation per surface.**

## PT-14

### Baked indirect lighting and probes for moving aircraft

**Evidence.** Godot LightmapGI stores baked lighting for static surfaces and
uses probes for dynamic-object indirect lighting; baking is editor-side and
the baked result has fixed lighting ([E14](sources.md#e14)).

**OpenRC fit.** A candidate for a deliberately authored, fixed-daylight 3D
field with shelters and structures. OpenRC currently builds much of the scene
procedurally, and no production LightmapGI scene was found. The proposed route
must materialize stable authored geometry/UV2 and bake resources with matching
instance bindings before packaging. The aircraft still needs probes, direct
lighting and dynamic shadows. Do not light an already lit panorama/opaque photo
proxy a second time. Time-of-day changes invalidate a single baked condition.

**Experiment.** Bake one shelter plus ground in the editor; export it cleanly
and fly an aircraft through/around it. Check changing indirect illumination,
dark corners, probe bounds, shadow contact and appearance-policy refusal of
incompatible times. Verify the actual runtime renderer and separate bake-machine
requirements. **Disposition: conditional fixed-lighting 3D alternative.**

## PT-15

### Local reflection probes and matched environment lighting

**Evidence.** The current Godot ReflectionProbe reference documents captured
cubemaps, roughness levels, bounded update modes and different per-mesh limits
for Mobile and Compatibility ([E15](sources.md#e15)). Older documentation returned
by the same search excluded Compatibility, so it was not used as current proof.

**OpenRC fit.** The lake already has a refresh-on-change reflection owner and
Compatibility ambient handling. A site-specific probe must coordinate with
World exposure/time and exclude inappropriate subjects rather than introducing
another always-updating capture. A fixed-eye panorama may be useful as an
approximate distant lighting environment; its nearby photographed objects and
projected proxies are not correct from arbitrary probe or aircraft positions.
Box projection is useful only when its assumed local volume fits the scene.

The current [project configuration](../../../../app/project.godot) budgets a
two-slot reflection atlas, with the lake already an owner. Inventory all active
probes, including transitional scenes, before adding one. The
[existing renderer policy](../../../plans/menu-redesign.md#renderer-policy)
requires measuring update cost and memory before changing that capacity.

**Experiment.** Compare the shared sky alone with one bounded static probe on a
representative aircraft and structure. Check moving aircraft, rough surfaces,
site changes, lake/probe coexistence, atlas limits, light refresh, wrong
reflections and capture hitches. Keep probe
images/resources separate from physical wind or simulation state. **Disposition:
reuse existing ownership, qualify a small additional probe only for a visible gain.**

## PT-16

### Alpha-coverage-aware foliage filtering

**Evidence.** Newer Godot import documentation describes preserving alpha-test
coverage through mip levels; the antialiasing manual distinguishes geometry MSAA
from alpha-to-coverage and other filtering ([E16](sources.md#e16)). The import
setting was not established on OpenRC's exact binary in this research.

**OpenRC fit.** Prior tree work rejected ordinary leaf mipmaps because they
changed canopy gaps. Preserving a statistical alpha coverage does not guarantee
preserving those gaps or the perceived tree shape. First inspect the actual
material transparency mode: the documented import option targets alpha-tested
color textures, not an indiscriminate change to alpha-hash/blended materials.
Current engine/renderer support and the existing custom vegetation adapters need
verification. This is a controlled alternative to the prior candidate.

**Experiment.** Compare retained leaves with coverage-aware preprocessing only
if supported, keeping thresholds, source texture and density fixed. Measure
silhouette/gap change and moving-view shimmer at pilot, overhead and FPV angles;
review aircraft readability behind foliage. Test alpha-to-coverage separately
with the actual MSAA configuration and renderer. **Disposition: conditional
import experiment; preserve the existing default until appearance and cost pass.**

## PT-17

### Normal-guided roughness filtering against specular shimmer

**Evidence.** Godot documents normal-guided roughness preprocessing on import
separately from the runtime screen-space roughness limiter. The latter has
renderer restrictions; the former prepares texture data offline
([E17](sources.md#e17)).

**OpenRC fit.** A low-infrastructure candidate only where a material has a
demonstrated specular defect and actually uses the affected roughness. The
audited [ground shader](../../../../app/render/ground.gdshader) sets `SPECULAR = 0`
and supplies its custom direct specular lobe only for RC dirt; a bound grass
roughness map does not establish a general grass highlight response. Distinguish
that RC path, matte grass, roofs using ordinary materials and any newly imported
scan shader. Confirm effective roughness use before preprocessing, then check
packed-map channels, linear versus color data, mip use and normal convention.
Texture filtering does not solve geometry-edge aliasing or every highlight.
Avoid changing the intended material simply to hide an unattributed artifact.

**Experiment.** Compare original and processed maps with identical geometry,
lighting, exposure and motion; first vary roughness deliberately and use a
normal-disabled control to attribute the problem. If the target response is
absent, stop this candidate for that material. Check nearby detail, distant
shimmer and export-import equivalence.
Evaluate the runtime limiter separately where supported. **Disposition:
prioritize an offline comparison only for a confirmed responsive material.**

## PT-18

### Atmosphere lookup tables and aerial perspective

**Evidence.** Hillaire's production atmosphere work separates sky and aerial
perspective using compact lookup tables and a multiple-scattering approximation
([E18](sources.md#e18)). Its platform/scalability discussion is not an OpenRC
benchmark or an available Godot subsystem.

**OpenRC fit.** Potentially useful for coherent distant terrain and changing
lighting in a larger 3D site. The current atmosphere, ridge haze, cloud shadows,
World refresh and weather appearance already share ownership. A new LUT path
would need a matching update policy, precision, color/exposure conventions and
low-tier behavior. Applying distance fog to a background that already contains
photographed haze can double the effect. The photo site should retain its
captured condition unless a separately proven composition is introduced.

**Experiment.** Start with identical synthetic distances and sun angles against
the existing haze. Compare aircraft/background contrast, ground-horizon joins,
update cost and sunset transitions; keep physical weather identical. **Disposition:
defer to shared FW work if a measured 3D-site defect justifies the change.**

## PT-19

### Shell-and-fin representation for a vegetation patch

**Evidence.** Lengyel and coauthors render fur using offset textured shells and
silhouette fins ([E19](sources.md#e19)). Applying that idea to short vegetation
is an engineering hypothesis here; the paper does not validate an RC grass field.

**OpenRC fit.** A possible tiny maintained-grass patch comparison where individual
blades are costly and flat turf lacks volume. It would need surface-conforming
layers, consistent root anchoring, stable lighting and a carefully bounded view
range. Semi-transparent layers create overdraw; grazing runway views can expose
shell bands or poor silhouettes. Imported clumps and the current photographic
turf are strong baselines. Use ordinary authored geometry/shaders in a prototype
rather than assuming geometry-shader or compute support across C/M/F.

**Experiment.** Compare an equal-area patch of existing turf/clumps against a
small shell/fin sample. Sweep layer count, angles, shadows and motion, measure
overdraw/frame cost, and examine wheels/aircraft passing close to it. It supplies
no physical grass height or contact. **Disposition: deferred research option,
with no proposal to blanket the whole field.**

## PT-20

### Threaded resource loading and bounded scene residency

**Evidence.** Godot supports threaded resource requests, but retrieval can block
if completion is not checked; active scene-tree interaction has separate thread
safety rules ([E20](sources.md#e20)).

**OpenRC fit.** Existing staged field construction divides ordered main-thread
work; it is not runtime terrain/texture paging. Reuse that lifecycle for a site
pack, then add bounded queues for tiles or chunks only if required by PT-03/11.
Background decode does not eliminate GPU upload/first-use stalls. Publish scene
changes on the owning thread, reject stale generation results and release failed
requests. Detached World construction can mutate shared atmosphere ownership,
so thread work does not replace the existing prepare/rollback requirement.
Rendering residency must never remove an admitted collision obstacle or ground
sample from the physics world.

**Experiment.** Force slow I/O, missing/corrupt assets, rapid site changes,
cancellation and stale completion. Record request count, decoded bytes, resident
and peak RAM/VRAM, upload frames, first-use stalls and full-flight p95/p99. A
lower-resolution valid representation must remain available. **Disposition:
extend the existing lifecycle with bounded loading, not an unrestricted streamer.**

## Resulting experiment order

| Order | Proposed comparison | Existing implementation owner |
| --- | --- | --- |
| 1 | PT-01 single-eye projection, depth and matched shadow/color fixture | SC-PHOTO-02/05, CAM and FW |
| 2 | Source-detail/zoom review; PT-11 only if the simple image fails its agreed gate | SC-PHOTO-07, graphics and capture owners |
| 3 | PT-20 bounded pack load and failure recovery using the existing staged route | SC-PHOTO-03/07/08, UI/FW |
| 4 | PT-06 scan cleanup, PT-12 one shoulder blend, PT-13 local marks and PT-17 stable materials | SC-PHOTO-11, SC/L/ground material owners |
| 5 | PT-15 small reflection comparison; PT-14 only for an authored fixed-lighting scene | SC-PHOTO-05/11, FW/TOD |
| 6 | PT-08 HLOD and PT-16 foliage filtering when the actual 3D-site baseline exposes a problem | SC-PHOTO-09/11, SC/VQ |
| Later | PT-02/03/04/07/09/18/19 under their stated prerequisites; preserve PT-10's local frame and PT-05's existing control | Relevant SC-PHOTO, GP/NK, FW and platform owners |

These are comparisons to schedule within the current plan, not promises to ship
every technique. Different alternatives should not be stacked before attribution.

## Common acceptance and stop conditions

Use the [validation matrix](validation-and-budgets.md) for existing numerical
budgets and distinguish analytical correctness, appearance, pilot usability and
complete-session cost. Add technique-specific controls above without relabeling
older 720p screenshots, vendor timings or successful imports as new qualification.

- Freeze field/contact identity, camera path, aircraft/input tape, lighting,
  weather, resolution, backend, renderer and assets for each comparison. Report
  visible changes and p95/p99/frame-pacing, loading peaks, submissions, texture
  memory and simulation headroom separately.
- Use 1080p first, and the native physical panel on Apple Silicon Retina with
  output/drawable/internal dimensions recorded. A different renderer or device
  gets its own result; the 240 Hz/500 microsecond physics target is separate.
- Test the actual zoom extremes, low runway approach, distant tracking, abrupt
  camera turns, overhead FPV where admitted, and thin foliage against bright sky.
  Pilot attitude readability and landing cues remain acceptance criteria.
- Keep contact geometry, ground sampling/materials and stable physical IDs
  independent of quality, LOD, tile availability and visual streaming. Preserve
  native-domain qualification and same-backend numerical replay semantics.
- Check cold/warm loads, cancellation, failure, reset, site switching and clean
  offline exports. Disabled features must avoid their optional work/resources.
- Preserve per-asset rights, code licenses, source/tool versions and reproducible
  transforms. A paper or game-production talk permits study of a method; it does
  not grant rights to copy its game assets or arbitrary implementation code.

Stop or narrow a candidate when it breaks surveyed alignment, alters physical
behavior through a graphics choice, worsens pilot readability, exceeds the agreed
full-scene budget, or requires unsupported platform infrastructure. Record the
reason and retain the successful simpler representation.
