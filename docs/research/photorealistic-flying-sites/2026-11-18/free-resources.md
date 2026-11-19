# Twenty-four free-resource investigations

Research date: **2026-11-18, America/Bogota**. Research branch baseline:
`0f02635a47c2a83411bd6f153e49c9c914343827`. This third investigation adds
**24 resource dossiers**, FR-01–FR-24, to the earlier engine/capture study and
[twenty technique investigations](additional-techniques.md). The
[search record](resource-search-record.md) preserves the questions, source
conflicts, repository audit and retrieval limits. [F01–F24](sources.md#f01)
extend the primary-source register to 86 records.

These are additional investigations, not 24 newly discovered dependencies.
Several candidates already appear in older OpenRC research, and two are already
pinned in the tree toolchain. Hugin, Blender, ODM, QGIS/GDAL, Terrain3D,
Poly Haven and ambientCG remain useful baselines from the first study; they are
not counted again here. OSM with Geofabrik, meshoptimizer with gltfpack, and
KTX-Software with Basis Universal each count as one resource family.

## Recommendation

Keep the first pilot small: **our own calibrated photographs → Hugin → Blender
proxies → the pinned Godot application**. Add darktable when RAW development is
needed; add Luminance HDR only for a justified bracketed capture. Compare one
image-processing utility if reproducible variants or processing memory become
a problem. A photo background does not need a terrain service or a new mesh
optimizer before the rendering experiment can begin.

For the later 3D site, reuse ODM and Blender first. MeshLab can address a measured
mesh-cleanup problem; CloudCompare can help quantify geometry error; PDAL can
process an authorized point-cloud source. Reuse existing glTF Transform and
Validator packages before adding another conversion framework. Evaluate optional
compression on the **exported application and actual resident resources**, not
just on a smaller authoring file.

This workflow can start without buying additional software licenses. Capture
time, suitable photographs, survey work, storage and hardware still have costs.
No candidate was installed, no asset downloaded, and no import, export or device
benchmark was performed in this research task.

## Selection at a glance

The disposition is a research recommendation, not implementation status. Only
the [SC-PHOTO plan](../../../plans/photorealistic-flying-sites.md) owns that status.

| ID | Resource | Proposed contribution | Disposition |
| --- | --- | --- | --- |
| [FR-01](#fr-01) | CGBookcase | CC0 pavement and other material maps | Shortlist one exact asset |
| [FR-02](#fr-02) | ShareTextures | Free material catalog | Hold distribution: conflicting terms |
| [FR-03](#fr-03) | TextureCan | CC0 grass/material maps | Shortlist one exact asset |
| [FR-04](#fr-04) | Copernicus DEM GLO-30-F | Distant terrain context | Conditional on product/access/notice checks |
| [FR-05](#fr-05) | OpenTopography | Discover and process elevation/LiDAR | Conditional on dataset and service terms |
| [FR-06](#fr-06) | OpenAerialMap | Discover georeferenced overhead imagery | Discovery until exact image is selected |
| [FR-07](#fr-07) | OpenStreetMap + Geofabrik | Roads, footprints and land-use hints | Conditional offline use with ODbL review |
| [FR-08](#fr-08) | ESA WorldCover | Coarse categorical vegetation/ground masks | Distant context only |
| [FR-09](#fr-09) | MeshLab | Clean and simplify scanned meshes | Compare when Blender baseline needs help |
| [FR-10](#fr-10) | CloudCompare | Quantify point-cloud/mesh differences | Useful for a surveyed 3D site |
| [FR-11](#fr-11) | PDAL | Reproducible point-cloud filtering/rasterization | Conditional on point-cloud input |
| [FR-12](#fr-12) | OpenMVS | Alternative dense reconstruction | Same-data CPU/quality comparison |
| [FR-13](#fr-13) | Material Maker | Procedural material maps | Reassess existing offline candidate |
| [FR-14](#fr-14) | meshoptimizer / gltfpack | Geometry optimization and GLB experiments | Reuse native import first; conditional |
| [FR-15](#fr-15) | xatlas | UV atlas generation | Existing Blender/Godot unwrap first |
| [FR-16](#fr-16) | Tree It | Author original trees | Low priority; distribution-specific terms |
| [FR-17](#fr-17) | darktable | Consistent RAW development | Optional capture preparation |
| [FR-18](#fr-18) | Luminance HDR | Merge exposure brackets | Optional, only with appropriate capture |
| [FR-19](#fr-19) | libvips | Large-image variants and tile pyramids | Offline comparison if needed |
| [FR-20](#fr-20) | OpenImageIO | Image/channel/color inspection and processing | Offline inspection candidate |
| [FR-21](#fr-21) | KTX-Software + Basis Universal | Texture delivery/compression experiment | Defer until exact importer path is proven |
| [FR-22](#fr-22) | glTF Transform | Inspect and prepare glTF/GLB | Reuse already pinned packages |
| [FR-23](#fr-23) | Khronos glTF Validator | Structural asset checks | Reuse already pinned package |
| [FR-24](#fr-24) | RenderDoc | Attribute graphics work and inspect resources | Supported API/device diagnosis only |

## Rights and compatibility rules

Record four separate questions: the **tool's code license**, the **input asset or
dataset license**, any **service/access conditions**, and the **rights/notices for
the shipped output**. Free access does not establish permission to mirror a
catalog or publish its source files. A tool's GPL, AGPL, MIT or Apache label is
not the license of a photograph processed with it. Bundled samples, plugins,
community graphs and dependencies need their own notices where applicable.

The recommendations below are source-backed screening, not blanket clearance of
an unspecified download. Select an exact product/file, retain the applicable
terms and obtain its hash before admitting it. Prefer direct provider downloads
and offline build inputs; no new runtime subscription, public tile dependency or
embedded service key is proposed.

Godot compatibility has several separate levels: readable source format,
preserved material/geometry semantics, accepted OpenRC adapter, correct clean
export, and qualified target-device behavior. A valid GLB proves none of the
other levels by itself. A raster elevation sample is not surveyed runway truth,
and a render mesh is not automatically part of OpenRC's custom collision solver.

## FR-01

### CGBookcase: generic PBR material maps

**Evidence and free terms.** The provider publishes its textures under CC0 1.0
and does not require attribution; donations support the catalog. Resolution
availability is asset-specific. [Asphalt 02](https://www.cgbookcase.com/textures/asphalt-02)
lists base color, AO, height, roughness and **DirectX** normal maps, plus an
experimental packed workflow. Actual downloaded extensions and delivery limits
were not tested. [F01](sources.md#f01)

**OpenRC fit.** Use one material as an offline comparison for a generic 3D paved
surface. The older source catalog already mentions CGBookcase, so this is a
specific reassessment. Convert/verify the normal convention against OpenRC's
OpenGL +Y input convention; do not feed arbitrary packed channels into the
current shader. Texture appearance cannot change the maintained-turf contact
table into asphalt.

**First comparison.** Preserve the original maps and their terms; compare the
candidate at the same physical tile scale, lighting and camera angles as the
existing ground. Check normal orientation, seams, repetition, aircraft contrast,
imported map channels and resident memory. **Disposition:** shortlist for
SC-PHOTO-07/11, with surface physics handled by 04b if relevant.

## FR-02

### ShareTextures: useful catalog with unresolved distribution terms

**Evidence and free terms.** The site advertises free downloads without an
account and textures up to 4K. [Asphalt 10](https://www.sharetextures.com/textures/road/asphalt-10)
is a concrete lead. Its license page calls the grant a custom CC0-based license
and prohibits redistribution on other websites, in plugins or collections
without written permission. Its terms separately describe standard CC0 1.0
and permitted distribution, while restricting automated downloads, hotlinks
and bypassing its platform. These statements were both present when reviewed.
[F02](sources.md#f02)

**OpenRC fit.** An openly available GitHub source asset or scenery bundle could
fall within the disputed wording. Do not resolve the conflict by relying on a
CC0 badge. Use CGBookcase, TextureCan or existing cleared sources for the first
comparison; no scraper, mirror or download integration is proposed.

**First comparison.** If the exact intended source/binary packaging is later
cleared, retain that grant and then test map orientation, physical scale,
repetition and import cost. **Disposition:** researched but held from distributed
assets until the conflict is resolved; SC-PHOTO-01/07/10.

## FR-03

### TextureCan: grass and other raster materials

**Evidence and free terms.** The provider states CC0 1.0 terms for its PBR
textures, graphics and photos, including commercial use and redistribution with
projects/3D assets, without mandatory credit. Separate third-party rights can
remain in marks/logos. [Grassland Ground 0009](https://www.texturecan.com/details/130/)
offers 1K/2K/4K map links and an SBSAR. Exact archive contents, normal convention
and delivery limits were not tested. [F03](sources.md#f03)

**OpenRC fit.** Compare baked maps for generic 3D field grass; the SBSAR listing
does not establish native Godot support. Earlier EZ-Tree research mentions
TextureCan bark, but lacks a complete original-provider file hash chain. That
history does not clear a new grass asset or establish its visual quality.

**First comparison.** Select one map set, record its original URL/hash/terms,
verify channels and normal direction, and compare with the existing maintained
turf at close, grazing and pilot-zoom views. Assess aircraft visibility and
repetition before detail alone. **Disposition:** shortlist for SC-PHOTO-07/11;
no claim that a generic grass texture reproduces a measured field.

## FR-04

### Copernicus DEM GLO-30-F: distant elevation context

**Evidence and free terms.** GLO-30 is a roughly 30 m sampled **surface** model,
including buildings and vegetation, not a surveyed bare-earth runway. The
catalog describes registered public downloads and DGED/DTED formats. The
COP-DEM-GLO-30-**F** grant permits adaptation/distribution with prescribed
source/modified-product notices, liability language and other conditions.
Do not apply it to the separately restricted **-R** product. An August 2026
notice restricts the 30 m **View Service**; download and view-service access are
different channels and must be checked separately. [F04](sources.md#f04)

**OpenRC fit.** Select the eventual field's exact free/open tile for an offline
distant ridge comparison. Earlier research already considered Copernicus; the
delivered ridge precedent uses SRTM and is visual-only. A coarse DSM cannot
define runway roughness, obstacle geometry or a new physical height provider.

**First comparison.** Record product/version, access route, acquisition history,
CRS, vertical datum, no-data and notices. Crop/reproject through QGIS/GDAL into
the declared local frame; compare the skyline and independent height references.
**Disposition:** conditional context source for SC-PHOTO-07/11, never automatic
contact admission under 04b.

## FR-05

### OpenTopography: elevation and LiDAR discovery/processing

**Evidence and free terms.** OpenTopography distributes multiple datasets with
their own rights and adds service conditions. Free guest/registered access is
limited; the developer page lists 50 API calls per 24 hours for non-academics
and 200 for academics, with separate higher-access and enterprise arrangements.
API integration into commercial software requires enterprise terms. These are
dated service conditions, not a promised project entitlement. [F05](sources.md#f05)

**Concrete lead.** The catalog's [Swiss 0.5 m DTM/DSM](https://portal.opentopography.org/datasetMetadata?otCollectionID=OT.072026.2056.1)
covers Switzerland/Liechtenstein, with EPSG:2056 and LN02 vertical metadata.
The original swisstopo terms allow reuse with specified credit; availability of
that exact product on our eventual free access tier was not established. It is
an example to assess, not the selected OpenRC field.

**OpenRC fit.** A licensed local DTM/DSM crop could support the later 3D terrain
authoring comparison. The portal is neither a runtime landscape provider nor a
replacement for measured contacts; select a geographically relevant product first.

**First comparison.** Choose a geographically relevant, rights-cleared product,
check its actual access tier, retain provider and OpenTopography credits, and
compare a small offline crop with survey checkpoints. Grid spacing does not
equal vertical accuracy. Preserve DTM/DSM distinction, datum, age and processing
parameters. Do not ship personal API keys or add runtime service dependency.
**Disposition:** conditional for SC-PHOTO-01/07/11.

## FR-06

### OpenAerialMap: overhead imagery discovery

**Evidence and free terms.** Access is free. The legal page describes imagery
submitted under CC BY 4.0 with Open Imagery Network contributor attribution;
the newer FAQ directs users to each image's own license. Documentation describes
GeoTIFF/Cloud Optimized GeoTIFF imagery and metadata. Coverage, date, resolution
and registration vary. No image was selected from the
[map browser](https://map.openaerialmap.org/). [F06](sources.md#f06)

**OpenRC fit.** A selected, licensed overhead image could provide an orthophoto
context or mapping reference in the 3D authoring workflow. It cannot provide the
pilot-eye panorama, concealed obstacle surfaces or a legal right to another
provider's imagery merely because a tile can be displayed or traced.

**First comparison.** For one actual image, retain author/provider, capture date,
resolution, bounds, CRS, exact reuse grant and attribution/change requirements.
Check alignment against independently measured landmarks and inspect baked
shadows or duplicated trees before combining it with 3D content. **Disposition:**
discovery-only until the item and its rights are established; SC-PHOTO-01/07/11.

## FR-07

### OpenStreetMap and Geofabrik: vector context

**Evidence and free terms.** Geofabrik provides free regional OSM `.osm.pbf`
extracts and selected shapefiles, generally updated daily; custom services can
be paid. [Baden-Württemberg](https://download.geofabrik.de/europe/germany/baden-wuerttemberg.html)
is a concrete format/example page, not a chosen flying site. OSM data uses ODbL
with attribution and database obligations. Produced works and derivative
databases have different treatment; assess what the actual generated scenery
and source bundle contain. [F07](sources.md#f07)

**OpenRC fit.** Offline roads, water boundaries and building/vegetation hints can
guide an authored 3D background. Shapefile selections omit some information;
heights, completeness, dates and positions vary. The data neither establishes
rights in underlying aerial photographs nor supplies measured collision shapes.

**First comparison.** Retain one dated regional extract, crop/filter to the site,
validate tags and positions, document generated geometry and required ODbL
source/notice handling. Review missing buildings and misleading height defaults
against licensed references. **Disposition:** conditional for SC-PHOTO-07/10/11;
no reliance on public tile servers or live OSM APIs in the simulator.

## FR-08

### ESA WorldCover: broad land-cover masks

**Evidence and free terms.** WorldCover 2021 v200 is a global, nominal 10 m,
11-class land-cover product in EPSG:4326 tiled Cloud Optimized GeoTIFFs. It is
classification, not RGB photography or elevation. Dataset terms are CC BY 4.0;
the project's code-repository GPL label is separate. The official repository
documents public data access and requested citation. Global accuracy statistics
do not establish accuracy at one flying field. [F08](sources.md#f08)

**OpenRC fit.** Use a small offline crop as a possible hint for distant tree,
grass or water distribution after the real site is chosen. A class cannot define
runway dimensions, individual trees, friction or collision. Product year and
local changes matter.

**First comparison.** Retain tile identity/version, attribution, class legend,
transform and no-data handling. Use nearest-neighbor categorical resampling,
then compare class boundaries with a separately licensed recent reference and
manually authored runway exclusion. **Disposition:** conditional distant-context
input for SC-PHOTO-07/11; no automatic vegetation or physics generator is claimed.

## FR-09

### MeshLab: scanned-mesh cleanup

**Evidence and free terms.** The free GPL-3.0 application offers mesh processing,
including textured decimation, with Windows, Linux and macOS builds. Its current
site replaces the discontinued `meshlabserver` workflow with PyMeshLab for batch
filters; filter scripts can retain an operation sequence and parameters.
Tool/sample/input rights remain distinct. [F09](sources.md#f09)

**OpenRC fit.** Use it offline for a cleanup problem found in one ODM/other
authorized scan. Bring the resulting OBJ/PLY through Blender to the established
GLB path; do not create a runtime dependency or assume every export preserves
materials. Keep Blender as the control.

**First comparison.** Preserve the high-resolution landmark, reduce it with a
recorded textured filter sequence and compare triangles, UV seams, silhouette,
sampled surface error and material appearance after Godot import. Check the
scale and stable survey IDs through Blender. **Disposition:** useful conditional
comparison for SC-PHOTO-11 and PT-06; no new conversion framework until it helps.

## FR-10

### CloudCompare: measured geometry quality checks

**Evidence and free terms.** The free point-cloud/mesh tool provides comparison,
global shift/scale and command-line functions. Format support can depend on the
build/plugins. Its license records differ by component/version: the repository
file says GPL v2 or later, the README links GPL v3, and the wiki distinguishes
LGPL CCLib from GPL application components. Preserve the selected release's
actual notices before code redistribution. [F10](sources.md#f10)

**OpenRC fit.** Compare an authored surface with independently measured points
in a common frame. This can reveal a visible/contact mismatch but does not
implement a ground provider. Keep the global shift and inverse transform;
silently dropping a shift can relocate a georeferenced site.

**First comparison.** Compute actual cloud-to-mesh distances, not the preliminary
approximate values. Report median, 95th percentile, maximum and spatial error
pattern against held-out points; use adequate surface sampling. A mesh-to-mesh
comparison based only on sparse vertices can miss an interior discrepancy.
**Disposition:** useful QA for SC-PHOTO-04b/11 when measured geometry exists.

## FR-11

### PDAL: repeatable point-cloud processing

**Evidence and free terms.** PDAL is a free BSD-licensed library/CLI with
Windows, macOS and Linux installation routes and separately identified
dependencies. Its pipelines can filter and reproject point clouds; the GDAL
writer produces rasters. Input LiDAR rights are independent of this software
license. [F11](sources.md#f11)

**OpenRC fit.** For an authorized LAS/LAZ source, a pinned JSON pipeline can
produce a ground-classified GeoTIFF for offline inspection. Pass it through
QGIS/GDAL and the chosen visual terrain format only after its coordinate and
sampling metadata is retained. A raster writer does not establish bare-earth
truth or compatibility with OpenRC's ground/contact implementation.

**First comparison.** Record CRS and vertical datum, ground classification,
outlier policy, resolution, interpolation, no-data and local NED transform.
Compare the result against held-out surveyed elevations and an ODM/Blender
baseline. Check repeatability and processing memory on the intended authoring
machine. **Disposition:** conditional SC-PHOTO-04b/07/11 input processor, unnecessary
for a simple fixed-eye panorama.

## FR-12

### OpenMVS: alternative reconstruction route

**Evidence and free terms.** Upstream development documentation describes
COLMAP undistortion and `InterfaceCOLMAP`, then dense reconstruction, meshing,
refinement and texturing, with CPU and optional CUDA paths. It lists platform
builds including macOS ARM64. Development documents and older README material
differ on newer native SfM features: pin a released version and verify its
actual route. Software is AGPL-3.0 with separate third-party notices.
[F12](sources.md#f12)

**OpenRC fit.** An offline alternative could help when authoring hardware lacks
CUDA or the baseline reconstruction has a concrete deficiency. Test the CPU
path rather than promising fast Apple Silicon reconstruction. Photographs and
resulting assets still need their own rights records.

**First comparison.** Feed the same authorized image set and COLMAP alignment
to the comparison, record all settings, time and peak RAM, and compare geometric
completeness, landmark dimensions and texture seams. Convert a textured OBJ via
Blender to GLB and inspect in the pinned engine. **Disposition:** conditional
SC-PHOTO-11/PT-06 experiment; no replacement of ODM solely from vendor examples.

## FR-13

### Material Maker: procedural map authoring

**Evidence and free terms.** The free authoring tool has Windows, Linux and macOS
routes; repository files are MIT unless otherwise specified. It exports image
maps and supports batch export. Its export manual still refers to Godot
`SpatialMaterial`; this does not prove compatibility with 4.8.beta2. Community
graphs, brushes and input images need independent license checks.
[F13](sources.md#f13)

**OpenRC fit.** Earlier graphics research already treated it as an offline
candidate. Rebuild a compatible material from exported maps instead of assuming
a generated `.tres` is ready. The existing custom ground shader and shared
surface masks remain the owners; ground roughness alone does not create a
specular response where that shader disables it.

**First comparison.** Author one grass/shoulder or asphalt graph; retain the
graph, inputs and settings. Export base color, normal and roughness maps and
compare tiling, orientation, channel interpretation and grazing-view stability
against the existing material, on applicable renderers. **Disposition:**
conditional SC-PHOTO-07/11, particularly PT-12/PT-17 comparisons.

## FR-14

### meshoptimizer / gltfpack: conditional geometry optimization

**Evidence and free terms.** This MIT software family includes the gltfpack
CLI. Default output can add `KHR_mesh_quantization` and `KHR_texture_transform`;
compression, texture and instancing switches add other extensions. Unknown
extensions/attributes can be discarded, and extras require a preservation option.
Code licensing does not change source-model rights. [F14](sources.md#f14)

**OpenRC fit.** Godot and existing bake tools already use meshoptimizer. Prior
leaf-card gltfpack reductions failed their particular triangle target; retain
that topology-specific result. A Godot maintainer's 2026 discussion explains
that ordinary editor import re-encodes mesh data and normally omits source glTF
from the PCK. Smaller source GLB size therefore is not sufficient shipped-size
or performance evidence; runtime GLB loading is a different path.

**First comparison.** Start with the original GLB and a non-quantized `-noq`
variant, preserving required names/materials/extras. Test each desired extension
separately on the exact Godot build. Compare geometry/materials, import time,
exported package, runtime load/residency and frame time. **Disposition:**
conditional SC-PHOTO-07/09/11; no default optimizer pass on every asset.

## FR-15

### xatlas: UV atlas generation

**Evidence and free terms.** xatlas is a free MIT C++ library, not a turnkey
GLB converter. Its example OBJ converter explicitly does not copy materials;
UV seams can increase vertex count. Godot's upstream source already vendors
xatlas, and its documentation offers lightmap UV unwrapping. Verify the pinned
engine's actual feature before adding a separate integration. [F15](sources.md#f15)

**OpenRC fit.** This could address an identified UV/packing defect in a cleaned
building or a baked-lighting scene. First compare existing Blender UVs and Godot
import unwrapping. A UV atlas supplies neither measured geometry nor a complete
LightmapGI authoring/export path.

**First comparison.** On the same building, inspect overlaps, seams, texel
density, padding/light bleed, material preservation and final vertex count.
Carry the result through Blender/GLB and the real import/bake route.
**Disposition:** low-priority SC-PHOTO-11/PT-14 option only if existing tools
leave a demonstrated gap.

## FR-16

### Tree It: original trees under distribution-specific terms

**Evidence and free terms.** The supplier offers a free Windows-oriented tree
generator requiring older DirectX/runtime components. It exports OBJ and ASCII
FBX, among other formats. The website permits commercial tool use but prohibits
redistributing the tool, and permits selling one's own tree work. The separate
Steam EULA sets export-header/software credit conditions for commercial output
and restricts supplied model packs, including direct asset redistribution.
Do not assume standalone and Steam terms are identical, or bundles are CC0.
[F16](sources.md#f16)

**OpenRC fit.** Previous OpenRC research only partially inspected its archive;
sample rights were unresolved. If needed, author an original tree using
independently licensed bark/leaves, and retain the exact obtained package's
terms. Avoid supplied packs unless their intended public-source distribution
is expressly permitted.

**First comparison.** Export one original tree through Blender to GLB; inspect
silhouette, alpha, normals, LOD and material count. Wind information uses vertex
colors in particular FBX/DBO exports, so OBJ conversion must not be assumed to
preserve it. Keep any physical obstacle under its separate owner. **Disposition:**
low-priority, rights-conditional SC-PHOTO-07/11 candidate.

## FR-17

### darktable: consistent RAW preparation

**Evidence and free terms.** darktable is a free GPL-3.0-or-later RAW developer
with non-destructive edits and XMP settings. Official features list Windows,
macOS and Linux/Unix support and TIFF/PNG/JPEG plus linear HDR export options.
Current binary availability must be checked for the author's actual CPU/OS;
the project license does not license the photographs. [F17](sources.md#f17)

**OpenRC fit.** Before Hugin, develop the capture set with consistent white
balance, exposure and lens treatment. Retain the original RAW files and sidecars.
TIFF can be an intermediate master; it is not thereby an accepted runtime
texture. A stylistic tone curve can make seams and aircraft lighting harder
to match, so evaluate the stitched result.

**First comparison.** Process a small common capture subset, export controlled
high-bit-depth intermediates, and compare exposure seams, clipped highlights,
color and processing time against the camera-output baseline. Record applied
settings and output hashes. **Disposition:** optional SC-PHOTO-01/07 tool,
useful when the source is RAW; not required for an already suitable panorama.

## FR-18

### Luminance HDR: exposure-bracket merging

**Evidence and free terms.** This free HDR application can combine images of
the same scene at different exposures, retain HDR data and tone-map a display
version. Its project metadata says GPL-2.0-or-later; official install guidance
lists Windows, Linux and macOS routes. Formats include EXR, Radiance HDR and
high-bit-depth TIFF. Exact builds and dependencies remain authoring checks.
[F18](sources.md#f18)

**OpenRC fit.** Use only when exposure-bracket capture helps the site. Moving
clouds/leaves/people can produce ghosts. Keep a radiometric master separate
from the display panorama and the smaller lighting/reflection resource.
Saving an ordinary JPEG as EXR does not recover unclipped scene radiance.

**First comparison.** Merge a small tripod bracket sequence, inspect ghosting
and retained highlight/shadow information, then test a consistent tone-mapped
stitch and separate lighting candidate. Compare with a single-exposure capture
under the same Godot exposure. **Disposition:** optional SC-PHOTO-05/07;
no automatic relighting or physically calibrated illumination claim.

## FR-19

### libvips: image variants and tile-pyramid preparation

**Evidence and free terms.** libvips is a free LGPL-2.1-or-later image library
and command-line toolkit with Windows binaries and Unix/macOS installation
routes. Its `dzsave` operation writes multiresolution tile layouts with explicit
tile size, overlap and output options. Supported formats depend on the selected
build and optional codecs. Vendor memory/performance statements are not OpenRC
measurements. [F19](sources.md#f19)

**OpenRC fit.** Compare offline 4K/8K/16K variants or a future panorama pyramid
against the simplest existing image workflow. A DeepZoom/IIIF tile layout is
not a Godot panorama streaming implementation: projection, gutters, mip
selection, residency and upload scheduling still need SC-PHOTO work.

**First comparison.** Resize the same master with a pinned filter/color policy;
record time, peak RAM, dimensions and decoded-pixel differences. If PT-11 is
justified, additionally inspect wrap/pole/tile borders at each mip level.
**Disposition:** optional SC-PHOTO-07 authoring utility; runtime tiling remains
conditional under 03/07/08 and PT-11/PT-20.

## FR-20

### OpenImageIO: image inspection and explicit color processing

**Evidence and free terms.** OpenImageIO is free Apache-2.0 software. Its
`oiiotool`/inspection utilities expose dimensions, types, channels, metadata,
statistics, resizing and color transforms for available image plugins. The
manual distinguishes assigning a color-space label from transforming pixel
values; build plugins and a pinned OpenColorIO configuration matter.
[F20](sources.md#f20)

**OpenRC fit.** Use it offline to check masters and generated maps before Godot
import. Keep base color/display imagery separate from linear normal, roughness,
height and mask data. Its texture cache or `.tx` workflow does not become a
Godot streaming system simply by generating those files.

**First comparison.** Inspect one RGB panorama, one HDR master and one linear
data map, including alpha, dimensions, finite values and channel statistics.
Apply an explicit test transform only to color data and compare decoded output
with the intended Godot interpretation. Preserve input/output hashes and exact
commands. **Disposition:** useful SC-PHOTO-07 inspection candidate, selected
instead of an overlapping image toolkit unless both solve distinct needs.

## FR-21

### KTX-Software and Basis Universal: texture compression experiment

**Evidence and free terms.** KTX tooling writes texture containers and supports
Basis texture encodings/transcoding. Core KTX project files generally use
Apache-2.0, but its license lists other components and a non-open-source optional
ETC decoder; distribution requires the exact build's notices and choices.
Basis's encoder/transcoder is principally Apache-2.0 with separately listed
components. Codec/KTX2 interchange support varies with version.
[F21](sources.md#f21)

**OpenRC fit.** Treat this as an offline delivery comparison after the ordinary
Godot image-import path works. Container support, a glTF texture extension,
GPU block format and runtime transcoding are separate questions. Existing
S3TC/ETC2 import sidecars do not prove acceptance of arbitrary KTX2/Basis files,
new HDR codecs or every target renderer.

**First comparison.** For one panorama/material, verify exact importer/runtime
loader support, then compare clean exported size, load/transcode time, resident
format/bytes, alpha, color and mip seams with Godot's current import. Include
Compatibility, Mobile/Metal and applicable Forward+ paths. **Disposition:**
conditional SC-PHOTO-07/09 experiment; no shipped codec or dependency proposed.

## FR-22

### glTF Transform: reuse the existing asset SDK

**Evidence and free terms.** This free MIT SDK/CLI reads, inspects and edits
glTF/GLB. Individual operations can inspect, resize, prune or compress assets;
upstream warns that broad optimization defaults may not suit every scene.
Its Node tooling has image-processing dependencies with their own packaging
requirements. [F22](sources.md#f22)

**OpenRC fit.** `tools/trees/package.json` already pins core/extensions/functions
at **4.5.0**. Reuse that versioned foundation; do not install an unrelated global
latest CLI or claim the CLI itself is already an OpenRC dependency. Existing
tree scripts have asset-specific assumptions and need deliberate extension for
a building or external GLB.

**First comparison.** Inspect one source before changing it. Apply only a chosen
operation, preserve required names/transforms/materials/extras, and compare
validator output, repeat import/bake, rendered appearance and exported resource
cost. Draco/WebP/Basis/meshopt options need separate exact-loader checks.
**Disposition:** reuse for SC-PHOTO-07/11; prefer targeted authoring operations
over an unreviewed all-in-one optimization command.

## FR-23

### Khronos glTF Validator: reuse structural validation

**Evidence and free terms.** The free Apache-2.0 validator provides a CLI,
JavaScript API and browser-only hosted frontend. It can check glTF/GLB structure,
referenced resources and supported extension rules and emit JSON reports.
Its checks do not establish support for every possible extension.
[F23](sources.md#f23)

**OpenRC fit.** The tree toolchain already pins `gltf-validator`
**2.0.0-dev.3.10**. Its `validate_sources.mjs` wrapper accepts repository-local
JSON `.gltf` inputs and constrains external URIs to the repository; it is not
an arbitrary external-GLB importer. Use/extend the package's appropriate API
for a new input while retaining those intake boundaries.

**First comparison.** Retain the original-source validation report for intake
diagnosis. Require **zero validator errors and no resource-load errors** in the
accepted converted candidate; document narrow repairs and triage all warnings.
Then perform the separate Godot decode/import, visual, scale/material and export checks.
A validator pass cannot prove copyright permission, survey accuracy, correct
contact geometry or frame rate. **Disposition:** reuse under SC-PHOTO-07/10/11,
with no new validator dependency required.

## FR-24

### RenderDoc: graphics diagnosis on a supported path

**Evidence and free terms.** RenderDoc is a free MIT frame debugger whose
published support table includes Vulkan/OpenGL on Windows/Linux and other named
APIs/platforms. That table does not establish a macOS/Metal path; the development
build files contain an off-by-default Metal option, which is not a supported
OpenRC qualification result. Review the chosen release/API combination.
[F24](sources.md#f24)

**OpenRC fit.** Use it on our own application to inspect draw calls, resource
formats, depth/shadow composition and unexpected work. Existing graphics tools
and plans already mention it. Retain the established native Mac capture/profiling
route for Mobile/Metal. A captured frame is not an uninstrumented timing run or
a full-session frame-pacing measurement.

**First comparison.** Capture the same synthetic/photo scene on a supported
Windows/Linux renderer, identify suspect passes and actual texture resources,
then verify any improvement in a separate uncaptured session. Record renderer,
binary, GPU and output/drawable/internal dimensions. **Disposition:** conditional
SC-PHOTO-02/09 diagnosis; preserve the 1080p-first and Apple native-panel rules.

## Repository evidence and reuse

The bounded audit used tracked source at the baseline above. Paths missing from
the sparse checkout were read from Git. These are existing owners and histories,
not newly delivered integrations:

| Existing path | Consequence for this resource plan |
| --- | --- |
| [Ground importer](../../../../tools/ground/import_rc_ground.py) and [ground guide](../../../../tools/ground/README.md) | Reuse source/output hashes, license evidence, dimensions, map roles, normal conventions and import-setting checks as the intake precedent |
| [Tree packages](../../../../tools/trees/package.json), [validator wrapper](../../../../tools/trees/validate_sources.mjs) and [tree guide](../../../../tools/trees/README.md) | Reuse pinned SDK/validator, GLTFDocument decode, repeat bake and visual/import checks; respect wrapper input scope |
| [Scenery tools](../../../../tools/scenery/README.md) and [vegetation tools](../../../../tools/landscape/vegetation/README.md) | Extend existing source IDs, license records, conversions and checks before building another asset system |
| [Tree quality X10–X14](../../tree-forest-quality-2026-10-17.md) and [shadows](../../../plans/shadows.md) | glTF tooling and native meshoptimizer were already investigated; reassess rather than claim new discovery |
| [Earlier vegetation comparison](../../landscape-improvement-2026-10-07/02-vegetation.md) | Preserve the topology-specific gltfpack reduction result and prior visual acceptance limits |
| [Material tools study](../../visual-quality-tools-2026-10-05.md) and [graphics plan](../../../plans/advanced-graphics.md) | Material Maker is an existing conditional authoring candidate |
| [Tree It source options](../../visual-quality-implementation/L6c/house-tree/source-options.md) | Prior partial archive inspection did not qualify its executable or bundled samples |
| [Asset catalog](../../asset-sources-catalog-2026-10-06.md) and [EZ-Tree source review](../../tree-resource-review-2026-10-06/ez-tree/README.md) | Prior CGBookcase/TextureCan mentions do not replace exact new-download provenance |
| [Visual ridge evidence](../../landscape-upgrade/LU-16-R1/README.md) | Existing DEM ridge is visual-only; geodata intake is not an authoritative ground provider |
| [Graphics tools](../../../tools/graphics.md), [grass guide](../../../../tools/grass/README.md) | Reuse capture/profiling and visual/replay checks; diagnosis and acceptance remain separate |

The review also corrected [PT-16](additional-techniques.md#pt-16): the current
maple leaf atlas already enables coverage-preserving mipmaps at threshold 0.5.
[GDU-11a](../../engine-upgrade/GDU-11/README.md) records its bounded native
4.8-beta1 comparison and adoption. This is stronger evidence than the earlier
web-only uncertainty; it still does not qualify a new species, beta2 scene,
Mac execution, release or FPS result. Retain the accepted maple policy while
evaluating new foliage independently.

## A small adoption sequence

1. **SC-PHOTO-01/02:** choose a representable measured site and prove the
   synthetic fixed-eye rendering method. Use existing Hugin/Blender/Godot;
   evaluate RAW/HDR helpers only when capture needs them.
2. **SC-PHOTO-07:** produce ordinary image variants and one small proxy/model
   package. Reuse ground/tree provenance and validation patterns. Compare
   OpenImageIO or libvips only for a concrete inspection/processing need.
3. **SC-PHOTO-09/10:** measure actual target devices and export/offline behavior;
   package exact asset licenses and required credits. Optional RenderDoc
   diagnosis must be separated from timing acceptance.
4. **SC-PHOTO-11:** build one small ODM/Blender 3D scene. Introduce one cleanup,
   geometry-QA or reconstruction comparison at a time. Generic CC0 materials
   can be useful; geographic data is context until surveyed/qualified.
5. **Conditional follow-up:** texture codecs, gltfpack extensions, independent
   unwrap integration and Tree It advance only if they solve an observed problem
   and pass the existing renderer, physical-inventory and distribution gates.

For every admitted source, retain provider/author, exact asset/product ID and
version, original URL, retrieval date, license text/URL, source hash, geographic
and color/channel metadata, tool version/settings, transformations, output hash,
required notices and acceptance receipt. This is an authoring record checklist,
not a new accepted runtime descriptor schema. The [capture pipeline](capture-and-asset-pipeline.md)
owns the complete workflow and the [plan](../../../plans/photorealistic-flying-sites.md)
retains the sole implementation ledger.
