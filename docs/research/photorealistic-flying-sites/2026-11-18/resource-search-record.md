# Free-resource search and repository audit record

Research date: **2026-11-18, America/Bogota**. This is the third research wave,
answering the request for at least twenty additional investigations of free
resources/utilities and integration of the results into the existing branch.
The deliverable is [24 resource dossiers](free-resources.md), not a claim that
every candidate is ready to ship or that 24 new dependencies should be installed.

## Search design and accounting

The research was split into three independent questions: useful asset/geodata
sources, offline mesh/material utilities, and image/delivery/diagnostic tools.
A separate read-only repository audit checked prior adoption and existing
scripts. An adversarial reviewer checked the resulting recommendations against
source. The lead inspected the primary evidence and integrated the findings.

This log preserves **78 exact search strings** retained from that work: 24
resource-linked starting queries and 54 follow-ups. The tables/blocks group
queries by investigation, not by wall-clock interleaving of parallel research.
The asset researcher's handoff identified its strings as the retained key
queries rather than an exhaustive raw event transcript. No stronger completeness
claim is made. Direct page opens, PDF/text finds and repository reads are not
counted as additional queries or as new investigations.

The earlier required **ten searches followed by ten adaptive searches** remain
in [their original record](search-rounds.md). This follow-up adds resource
selection and verification; it does not rewrite that sequence or inflate the
count by treating multiple URLs for one tool as different resources.

## Resource-linked starting queries

| Investigation | Exact query | Retained source record |
| --- | --- | --- |
| FR-01 | `site:cgbookcase.com textures license CC0 download free commercial no attribution` | [F01](sources.md#f01) |
| FR-02 | `site:sharetextures.com license creative commons cc0 Patreon commercial texture` | [F02](sources.md#f02) |
| FR-03 | `site:texturecan.com license terms redistribution CC0 download commercial` | [F03](sources.md#f03) |
| FR-04 | `site:dataspace.copernicus.eu Copernicus DEM GLO-30 license free global download accuracy 30m attribution` | [F04](sources.md#f04) |
| FR-05 | `site:opentopography.org data access terms download API free commercial licenses attribution` | [F05](sources.md#f05) |
| FR-06 | `site:openaerialmap.org license imagery cc by geographic access download metadata attribution` | [F06](sources.md#f06) |
| FR-07 | `site:openstreetmap.org copyright ODbL attribution geofabrik extract license free shapefile pbf` | [F07](sources.md#f07) |
| FR-08 | `site:worldcover2021.esa.int license dataset 10 m download attribution` | [F08](sources.md#f08) |
| FR-09 | `MeshLab official GitHub README meshlabserver GPL license supported input output Windows Linux Mac` | [F09](sources.md#f09) |
| FR-10 | `CloudCompare official GitHub license GPL command line LAS PLY OBJ FBX texture export` | [F10](sources.md#f10) |
| FR-11 | `PDAL official docs license BSD Windows Mac Linux command line pipeline LAS LAZ` | [F11](sources.md#f11) |
| FR-12 | `OpenMVS official github README license AGPL MIT photogrammetry pipeline input output GPU` | [F12](sources.md#f12) |
| FR-13 | `Material Maker official GitHub license procedural PBR textures export Godot standalone Windows Linux macOS` | [F13](sources.md#f13) |
| FR-14 | `meshoptimizer gltfpack official github license EXT_meshopt_compression KHR_mesh_quantization glTF Godot` | [F14](sources.md#f14) |
| FR-15 | `xatlas official github license mesh uv atlas command line output` | [F15](sources.md#f15) |
| FR-16 | `Tree It Evolved Software original official license commercial use assets terms 3d tree generator` | [F16](sources.md#f16) |
| FR-17 | `site:darktable.org about license GPL supported platforms export formats` | [F17](sources.md#f17) |
| FR-18 | `site:github.com/LuminanceHDR/LuminanceHDR license HDR formats` | [F18](sources.md#f18) |
| FR-19 | `site:libvips.org license dzsave tile pyramid` | [F19](sources.md#f19) |
| FR-20 | `site:openimageio.readthedocs.io oiiotool license image formats` | [F20](sources.md#f20) |
| FR-21 | `site:github.com/KhronosGroup/KTX-Software license toktx Basis Universal` | [F21](sources.md#f21) |
| FR-22 | `site:gltf-transform.dev CLI license optimize inspect` | [F22](sources.md#f22) |
| FR-23 | `site:github.com/KhronosGroup/glTF-Validator license command line limitations` | [F23](sources.md#f23) |
| FR-24 | `site:renderdoc.org license supported APIs platforms Metal` | [F24](sources.md#f24) |

## Supplementary queries retained

These follow-ups address concrete gaps: exact asset maps, conflicting license
language, access tiers, software-versus-data licenses, old automation commands,
compression extensions, pinned-engine capability and misleading search results.
Multiple searches refining one resource remain one investigation.

### Asset, geodata and reuse terms: 18 additional strings

```text
site:cgbookcase.com "license" attribution redistribution CC0 commercial 2026
site:cgbookcase.com "Asphalt 01" texture maps PNG download
site:sharetextures.com "license" "CC0" terms attribution paid textures
site:sharetextures.com/textures "asphalt" sharetextures pbr asphalt
site:texturecan.com "license" "CC0" commercial redistribute download
site:texturecan.com/details "grass" texture seamless pbr material
site:dataspace.copernicus.eu Copernicus DEM GLO-30 license 2026 view service restricted download
site:opentopography.org "subscriptions" "free" "API" academic commercial dataset
site:opentopography.org "terms" "API" commercial software 2026 enterprise
site:opentopography.org dataset "Switzerland 50" 2026 license swisstopo
"OpenAerialMap" imagery license CC-BY 4.0 metadata download rights uploader
site:docs.openaerialmap.org "license" imagery open source license download
site:geofabrik.de data download licence daily pbf shapefiles ODbL attribution redistribution
site:openstreetmap.org/copyright ODbL databases produced works share alike attribution
"WorldCover" ESA 2021 "license" data distribution 2021 v200 citation
site:worldcover2021.esa.int WorldCover PUM v2 overall accuracy 2021 76.7 percent 10m classes
site:creativecommons.org/publicdomain/zero/1.0 CC0 public domain no conditions waiver other rights
site:creativecommons.org/licenses/by/4.0 attribution changes link license commercial remix
```

### Mesh, materials, geometry and tree tools: 28 additional strings

```text
site:github.com/cnr-isti-vclab/meshlab/LICENSE.txt GNU meshlabserver export PLY OBJ
site:cloudcompare.org GPL license CCLib LGPL CloudCompare core license
site:pdal.io license BSD GDAL output raster writers.gdal interpolation ground SMRF filter
site:github.com/cdcseacave/openMVS COPYRIGHT.md license commercial AGPL third party
site:pymeshlab.readthedocs.io python mesh filter script export windows linux mac license GPL PyMeshLab
site:github.com/PDAL/PDAL LICENSE BSD redistribution binary PDAL
site:github.com/CloudCompare/CloudCompare license GPL 2.0 license.txt
site:github.com/cdcseacave/openMVS/wiki InterfaceCOLMAP DensifyPointCloud TextureMesh CUDA CPU
site:github.com/cdcseacave/openMVS "InterfaceCOLMAP" "CUDA" texture OBJ
site:cloudcompare.org/doc/wiki CloudCompare cloud mesh distance tool registration point cloud shift scale
site:github.com/cnr-isti-vclab/meshlab filter quadric edge collapse decimation texture PLY OBJ
site:github.com/RodZill4/material-maker README MIT license materials CC0 export command line
site:rodzill4.github.io/material-maker-docs command line export png material texture command gpu
site:rodzill4.github.io/material-maker-docs export material Godot 4 glb input obj painting
site:github.com/jpcy/xatlas LICENSE MIT example OBJ output mesh unwrap
site:github.com/zeux/meshoptimizer/blob/master/LICENSE.md MIT license gltfpack
site:github.com/godotengine/godot xatlas unwrap lightmap unwrapping source thirdparty license
site:github.com/jpcy/xatlas "LICENSE" "MIT" git
site:docs.godotengine.org KHR_mesh_quantization EXT_meshopt_compression importer
site:docs.godotengine.org "EXT_meshopt_compression"
site:github.com/godotengine/godot "EXT_meshopt_compression" gltf Godot
site:github.com/godotengine/godot "KHR_mesh_quantization" GLTF extension
site:github.com/godotengine/godot "KHR_meshopt_compression" gltf
site:docs.godotengine.org/en/latest "KHR_mesh_quantization"
"Tree It model library license" "library" "commercial" evolved software
"Tree IT" "EULA" "Tree It model library license" "Tree It"
site:store.steampowered.com/eula/2386460_eula_0 "commercial" assets license
site:evolved-software.com/treeit "License" "redistribute" "tree"
```

### Lead verification of image, license and API gaps: 8 additional strings

```text
site:libvips.org LGPL 2.1 license
site:openimageio.readthedocs.io oiiotool stats colorconvert iscolorspace
site:github.com/baldurk/renderdoc supported APIs platforms MIT license Metal
site:github.com/donmccurdy/glTF-Transform LICENSE MIT
site:github.com/LuminanceHDR/LuminanceHDR "either version 2" "License"
site:store.steampowered.com/eula/2386460_eula_0 "Created by" "distribute"
"Tree It" "Created by Tree IT"
"2386460_eula_0"
```

## Retained evidence, conflicts and rejected shortcuts

Only original providers, project repositories, documentation and original license
publishers support the technical/resource conclusions. Search aggregators and
unrelated results were leads to discard or verify, not evidence of compatibility.
The [source register](sources.md#f01) links the retained pages and exact products.

| Case | Research outcome |
| --- | --- |
| CGBookcase | Inspected Asphalt 02 after the broader/asphalt queries; the actual page's DirectX map label matters more than a generic PBR badge |
| ShareTextures | Both conflicting official statements retained; no assumption that a public GitHub asset bundle is permitted |
| TextureCan | Raster-map candidate shortlisted; an SBSAR link is not an established Godot input |
| Copernicus | Read the explicitly free/open -F grant and distinguished restricted -R wording and View Service access from downloads |
| OpenTopography | Checked service tiers/API conditions separately from exact dataset and original-provider rights; no free-tier entitlement assumed for the example |
| OpenAerialMap | General legal page and current per-image-license FAQ retained together; no image chosen or cleared |
| OSM/Geofabrik | Dataset license and produced-work/database distinction retained; one resource family, no live public tile dependency |
| WorldCover | Direct official manual/repository used after the general access page timed out; nominal 10 m classification is not photographic/elevation data |
| MeshLab | Replaced stale meshlabserver advice with current PyMeshLab filter-script guidance |
| CloudCompare | Kept release/component GPL/LGPL distinctions and the preview-versus-real-distance distinction |
| OpenMVS | Moving development/automated pipeline documentation scoped as a lead; verify selected release and CPU route before adoption |
| Material Maker | Old SpatialMaterial export wording prevents a drop-in Godot 4.8 claim; explicit image maps are the proposed bridge |
| gltfpack | Traced extension insertion and custom-data loss; maintainer import comments motivate actual exported-package measurement |
| xatlas | Existing Godot vendoring/unwrap is the first comparison; sample OBJ conversion does not preserve materials |
| Tree It | Supplier terms, free standalone route and separately offered Steam edition distinguished; bundled packs are not cleared by tool-use rights |
| Tree It retrieval | Initial EULA retrieval failed and targeted search returned unrelated EULAs/aggregators. Those were discarded; the actual supplier-linked `//eula/2386460_eula_0` URL then opened successfully |
| Luminance HDR | Direct LICENSE fetch failed; project metadata explicitly establishes GPL-2.0+ rather than relying solely on the abbreviated GitHub badge |
| OpenImageIO | Search returned old/stable/development manuals; the opened stable manual identified 3.2.2. No current global tool upgrade is proposed |
| KTX/Basis | Checked third-party license exceptions and newer codec interchange limits; no universal container/importer/GPU-support claim |
| RenderDoc | Published platform/API table lacks an admitted Metal path; an off-by-default development flag does not qualify one |

The manual resolves WorldCover's geographic spacing as **1°/12000** for its
nominal 10 m Map product (at the equator), with a coarser InputQuality layer.
A helper handoff mistyped the denominator as 1200; the lead checked the original
manual and did not carry that error into the resource dossier.

## Repository baseline and compatibility checks

The research branch began this follow-up at
`0f02635a47c2a83411bd6f153e49c9c914343827`, retaining runtime ancestor
`f7b348e40aa5a44c4cc091d540fbffb55016e583`. Main was independently fetched at
`cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c`. The scoped diff from the runtime
ancestor to that main contained no changes in `app/landscapes`, `app/render`,
`app/scenery`, `app/environment`, `app/sim`, `app/physics`, `app/project.godot`,
the engine downloader, `tools/trees`, `tools/ground` or `AGENTS.md`.
The separately inspected `app/app_root.gd` delta is the previously observed
telemetry/Home-notice work. This is a scoped compatibility check, not a claim
that main is identical everywhere. No main merge/rebase was performed.

The [resource repository-evidence table](free-resources.md#repository-evidence-and-reuse)
names concrete scripts and prior results. Key consequences are:

- glTF Transform **4.5.0** and Validator **2.0.0-dev.3.10** are already pinned
  in the tree package. The existing wrapper accepts repository-local JSON
  `.gltf`, not an arbitrary external GLB. Reuse the package deliberately.
- Ground intake already records asset identity, hashes, licensing, dimensions,
  map roles, normal direction and importer settings. Reuse that pattern for
  new materials; an old provider mention does not clear a new file.
- Meshoptimizer, Material Maker, Tree It, CGBookcase, TextureCan, Copernicus,
  OpenTopography and RenderDoc have prior adoption or investigation history.
  The new dossiers identify it rather than present every name as new.
- DEM-derived ridge geometry remains visual-only. No geographic dataset, mesh
  conversion, Godot collider or graphics LOD supplies new authoritative contacts.
- The exact engine remains `4.8.beta2.official.cafc17a19`. Format, extension,
  renderer and export support need actual qualified paths; stock documentation
  and vendor examples cannot substitute for those results.

The checkout is sparse. Tracked scripts/data absent on disk were read from Git,
not reported as missing. When the workspace volume became full, documentation
editing continued in an isolated temporary checkout of the same branch/base,
reusing the existing Git object store. This changed neither the research baseline
nor any other working tree's source files.

## Independent review and integration decisions

The read-only adversarial review found two material points, both checked against
the tracked source by the lead:

1. **Validator acceptance must remain strict.** Preserve original intake errors
   for diagnosis, but require zero validator errors and no resource-load errors
   in the accepted candidate after documented repairs. An explained error is
   not a passing production asset.
2. **The maple foliage path was already adopted.** The earlier PT-16 description
   was too broad. Current import data enables coverage-preserving mipmaps with
   threshold 0.5, and [GDU-11a](../../engine-upgrade/GDU-11/README.md) records its
   bounded native beta1 evidence. PT-16, its source record and its search outcome
   now acknowledge this, while leaving beta2/new-asset/platform/release/FPS
   qualification open. The original query sequence is preserved.

The review added no external queries or runtime tests. The canonical plan keeps
its 18 step rows; this follow-up supplies source options, concrete trials and
priorities within them. The capture pipeline now links the proposed tool choices
and provenance/intake checks. No new runtime schema, dependency, licensed binary,
third-party asset or benchmark result is introduced.
