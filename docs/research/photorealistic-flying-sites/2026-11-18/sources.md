# Primary-source register

Research date: **2026-11-18**. These are original vendor/project manuals,
documentation, published research and publisher-authored product descriptions.
The identifiers below are stable within this research pack. Claims, limitations
and OpenRC recommendations are separated in the linked studies; a listed tool
has not thereby been installed, benchmarked or approved for distribution.

The repository audit is tied to commit
`f7b348e40aa5a44c4cc091d540fbffb55016e583`; its code evidence is indexed in
[Current architecture](current-architecture.md). The authoritative proposed work
and status are in the [plan](../../../plans/photorealistic-flying-sites.md).

The [free-resource follow-up](free-resources.md) adds F01–F24, bringing this
register to **86 stable source records**. A record may contain several primary
URLs needed to separate functionality, software licensing and asset/service
terms; it is not a count of independent websites. Its repository baseline and
current-main check are in the [resource search record](resource-search-record.md).

## Reading and version limits

- Godot `stable`, vendor product pages and `latest` manuals can change. The
  project uses its pinned **4.8.beta2** binary, not an assumed stable release.
  Recheck exact APIs, addon binaries, formats and renderer behavior before work.
- Historical RealFlight manuals establish documented techniques in their named
  versions; they do not establish the current renderer's internals.
- Several original RealFlight product/knowledge-base URLs redirect to Horizon's
  general landing page. S05 uses the publisher's Steam description instead.
  RF9.5's large PDF was available through indexed text; a direct retrieval hit
  the search tool's PDF-size limit. No manual assets were copied into this repo.
- Blender's direct license page returned an access error in the final review;
  its official indexed page/manual supplied the license statement. UNIGINE's
  JavaScript pages were also checked through indexed official documentation.
- Tool licenses, input-image rights, site access and output redistribution are
  distinct. Recheck current terms when selecting or buying a tool. No pricing,
  supplier benchmark or minimum-hardware claim is a project commitment.

## S01

[IKARUS — aerofly RC10 manual](https://www.ikarus.net/en/rc10-manual/).
Describes fixed-viewpoint photo scenery, multipano stations and 4D free movement;
time-of-day controls depend on the scenery class. Supports the representation
and camera distinction, not OpenRC performance or a particular renderer design.

## S02

[IKARUS — RC10 scenery workshop](https://www.ikarus.net/rc10-szenerie-workshop/).
Authoring example uses a 16384×8192 TIFF panorama converted to 32 texture files,
start positions and terrain/collision authoring, including Blender guidance.
Neither its conversion output nor its print-DPI setting prescribes OpenRC's
runtime format; the internal tile arrangement is not inferred here.

## S03

[Knife Edge — RealFlight G3.5 manual](https://forums.realflight.com/downloads/RealFlight%20G3.5%20Manual.pdf).
Historical airport-editor instructions describe depth-only objects for photo
scenery, including aircraft occlusion, collisions and shadows. This establishes
prior art for proxy geometry, not a working Godot material recipe.

## S04

[Horizon Hobby — RealFlight 9.5 manual](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/dw6b391a4f/Manuals/RealFlight-9.5-Manual.pdf).
Documents equirectangular 360°×180° panorama import, 8000×4000-or-larger guidance,
PhotoField viewpoint restrictions and limitations of baked photographic objects.
Version 9.5 and indexed-PDF retrieval limits apply; this is not an Evolution API.

## S05

[RealFlight Evolution — publisher description on Steam](https://store.steampowered.com/app/2069310/RealFlight_Evolution/).
The product description explicitly distinguishes 3D fields and PhotoFields,
including Triple Tree's main flightline. Used only to establish coexistence in
the product, not to infer its engine, asset format or implementation internals.

## G01

[Godot — PanoramaSkyMaterial](https://docs.godotengine.org/en/stable/classes/class_panoramaskymaterial.html).
Defines an equirectangular sky panorama and recommends HDR inputs for accurate
image-based illumination. An ordinary exposed photograph can supply a backdrop
without becoming physically measured HDR radiance.

## G02

[Godot — spatial shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html).
Documents depth modes, alpha/transparent-path behavior and `shadow_to_opacity`.
Individual mechanisms do not prove the combined photo, aircraft, proxy and
shadow composition on each selected renderer; SC-PHOTO-02 must establish that.

## G03

[Godot — renderers](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html).
Describes Compatibility, Mobile and Forward+ feature differences, including
Compositor support. A solution relying on advanced rendering hooks must not be
assumed to run on the project's Compatibility route.

## G04

[Godot — importing images](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html).
Explains import modes, GPU compression, mipmaps and image-format tradeoffs.
File size and GPU residency differ; actual format, device limits, transient
copies and export behavior must be measured on the exact build.

## G05

[Godot — available 3D import formats](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html).
Recommends glTF 2.0 and documents `.gltf`/`.glb` and Blender import behavior.
Supports a controlled Blender-to-GLB delivery pipeline; importing a scene does
not admit its geometry into OpenRC's custom contact system.

## G06

[Godot — what is GDExtension?](https://docs.godotengine.org/en/stable/engine_details/engine_api/gdextension/what_is_gdextension.html).
Describes native shared-library integration without recompiling the engine.
Supports a bounded native extension option, not an automatic GPU-performance
improvement or a substitute for a complete native application host.

## G07

[Godot — about godot-cpp](https://docs.godotengine.org/en/stable/tutorials/scripting/cpp/about_godot_cpp.html).
Documents C++ bindings and version/build compatibility considerations. Any new
extension must match the project's engine and precision/build requirements and
ship tested binaries for the intended platforms.

## C01

[Hugin — project manual](https://hugin.sourceforge.io/docs/manual/Hugin.html).
Documents panorama alignment/stitching and exposure/HDR workflows. A suitable
starting point for an open authoring pipeline; manual pages may reflect older
UI terminology and do not establish reconstruction quality for an untested site.

## C02

[PanoTools — photography guidelines](https://wiki.panotools.org/Photography_Guidelines).
Project guidance covers camera rotation, overlap, motion, focus and exposure.
Used as panorama-capture guidance; overlap and equipment choices must still fit
the actual lens, near objects and desired detail.

## C03

[Hugin — parallax](https://hugin.sourceforge.io/docs/manual/Parallax.html).
Explains panorama parallax and rotation around the lens entrance pupil. Supports
measuring and preserving the photographic viewpoint; stitching cannot recover
an arbitrary translated view with correct nearby-object geometry.

## C04

[PTGui — features](https://www2.ptgui.com/features.html).
Vendor comparison of Standard/Pro stitching, masking and HDR-related features.
A commercial alternative to compare on the same input set; confirm current
edition requirements and terms before a purchase.

## T01

[Terrain3D — releases](https://github.com/TokisanGames/Terrain3D/releases).
Reviewed **v1.1.0-stable**, release commit prefix `629bbd6`, advertising Godot
4.5–4.8+ support. That range is a candidate-compatibility statement, not evidence
for OpenRC's exact 4.8.beta2 binary, exports or custom physical ground.

## T02

[Terrain3D 1.1 — supported platforms](https://terrain3d.readthedocs.io/en/1.1/docs/platforms.html).
Documents renderer/platform support and uncertainty around full Metal support.
Compatibility and Mobile/Forward+ paths require separate qualification; do not
translate a Vulkan result into an Apple Silicon Metal acceptance claim.

## T03

[Terrain3D 1.1 — instancer](https://terrain3d.readthedocs.io/en/1.1/docs/instancer.html).
Documents instanced-mesh behavior and the current collision limitation. Visible
foliage does not automatically become an OpenRC obstacle; explicit stable
physical inventory and matching representation remain necessary.

## T04

[Terrain3D 1.1 — importing and exporting data](https://terrain3d.readthedocs.io/en/1.1/docs/import_export.html).
Describes heightmap formats, height scaling and import/export. Retain metric
scale and raster orientation; successful visual import alone does not validate
ground height/normal/material sampling for simulation.

## T05

[Terrain3D 1.1 — heightmaps](https://terrain3d.readthedocs.io/en/1.1/docs/heightmaps.html).
Recommends properly scaled 16/32-bit height inputs in EXR or R16. Supports
preserving measured height precision; dataset licenses and source accuracy
remain separate from the terrain tool's ability to read a file.

## P01

[OpenDroneMap — outputs](https://docs.opendronemap.org/outputs/).
Reviewed documentation identifies point clouds, textured mesh, orthophoto and
optional DTM/DSM products. These are reconstruction outputs requiring cleanup,
scale checks and game delivery preparation, not finished flying-site packages.

## P02

[OpenDroneMap — ground control points](https://docs.opendronemap.org/gcp/).
Explains measured control, reference systems and image observations. The retrieved
page identified 3.5.4 while other pages identified 3.6.0; pin the actual tool.
Independently held-out checkpoints are an OpenRC validation recommendation.

## P03

[OpenDroneMap — flying tips](https://docs.opendronemap.org/flying/).
Distinguishes full-3D and 2D/2.5D collection patterns, including nadir and oblique
coverage and overlap. These are starting guidelines, not a guarantee of accuracy
or instructions to conduct an unauthorized flight.

## P04

[AliceVision Meshroom — releases](https://github.com/alicevision/meshroom/releases).
Reviewed 2025.1.0 release material specifies CUDA 12 and compute capability 5.0
for its distributed CUDA processing route. Use this version-specific evidence
instead of older generic manual numbers when selecting the reconstruction host.

## P05

[Meshroom — requirements](https://meshroom-manual.readthedocs.io/en/latest/first-steps/install/requirements.html).
The retrieved manual identifies **2023.1.0** despite its `latest` URL and describes
CPU draft meshing without CUDA. Draft meshing is a different path; its old CUDA
3.0 requirement must not override the newer release information in P04.

## P06

[COLMAP — installation](https://colmap.github.io/install.html) and
[FAQ](https://colmap.github.io/faq.html).
Current installation guidance includes CUDA and AMD HIP/ROCm paths; FAQ dense
reconstruction wording still assumes CUDA. This inconsistency requires pinning
and testing a specific build/backend, not claiming equivalent support everywhere.

## P07

[RealityScan — license](https://www.realityscan.com/license) and
[EULA](https://www.realityscan.com/eula).
Vendor terms govern free/paid eligibility and seats. No purchase or eligibility
determination is made here. Tool availability does not grant permission to use
someone else's photography or redistribute a commercial simulator's scenery.

## P08

[RealityScan — desktop download](https://www.realityscan.com/download) and
[export documentation](https://rshelp.capturingreality.com/en-US/tools/export.htm).
Distinguishes desktop reconstruction from the mobile product and documents
current Windows/Linux and NVIDIA requirements and output processing. Evaluate
the exact release on a separate authoring machine if the runtime target differs.

## P09

[Agisoft Metashape — edition comparison](https://www.agisoft.com/features/compare/),
[system requirements](https://www.agisoft.com/downloads/system-requirements/) and
[licensing options](https://www.agisoft.com/buy/licensing-options/).
Commercial alternative with documented Apple hardware and GPU-acceleration
considerations. Edition checkmarks can be lost in text extraction; verify the
actual desired function in the selected edition before purchase or automation.

## P10

[Blender — license](https://www.blender.org/about/license/) and
[manual explanation](https://docs.blender.org/manual/en/dev/getting_started/about/license.html).
The GPL applies to Blender software, not automatically to artwork produced with
it. This distinction does not remove licenses attached to third-party input
assets, addons, copied code or embedded components. See retrieval limits above.

## A01

[Poly Haven — asset license](https://polyhaven.com/license).
Assets are offered under CC0. Retain the original item URL, author, downloaded
file/hash and license evidence for anything actually used; a generic HDRI is
useful for a rendering experiment but does not establish surveyed site geometry.

## A02

[ambientCG — license](https://docs.ambientcg.com/license/).
Describes CC0 asset availability. Source provenance should travel with derived
textures even when attribution is not a license condition. These generic assets
do not supply real-site measurements.

## A03

[GDAL — gdalwarp](https://gdal.org/en/stable/programs/gdalwarp.html).
Official reprojection/warping/resampling tool reference. Record source/destination
reference systems, no-data handling, resolution and transforms when preparing
orthophotos or height rasters; default settings are not calibration evidence.

## A04

[QGIS 3.44 — georeferencer](https://docs.qgis.org/3.44/en/docs/user_manual/managing_data_source/georeferencer.html).
Documents georeferencing and transformation workflows. Useful for checking survey
and image alignment before conversion into the local metric OpenRC frame.

## A05

[Google Maps Platform — Map Tiles policies](https://developers.google.com/maps/documentation/tile/policies) and
[Photorealistic 3D Tiles](https://developers.google.com/maps/documentation/tile/3d-tiles).
The service has access, attribution and caching/use conditions. Its visual
availability is not permission to extract a redistributable offline scenery
pack. No Google imagery or tiles are proposed for import in the pilot.

## X01

[Kerbl et al. — 3D Gaussian Splatting for Real-Time Radiance Field Rendering](https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/).
Original SIGGRAPH 2023 project/paper supports novel-view radiance rendering as a
research direction. Its benchmark does not establish Godot integration, contact
geometry, relighting, aircraft depth composition or OpenRC frame-time results.

## X02

[Original 3D Gaussian Splatting implementation — license](https://github.com/graphdeco-inria/gaussian-splatting/blob/main/LICENSE.md).
The reference implementation has noncommercial research/evaluation conditions.
Do not confuse publication of an algorithm with permissive redistribution of
every implementation. Any chosen library needs its own license review.

## X03

[Epic Games — Nanite virtualized geometry](https://dev.epicgames.com/documentation/en-us/unreal-engine/nanite-virtualized-geometry-in-unreal-engine).
Documents streamed, detailed mesh rendering and practical platform/content
constraints. A useful alternative-engine capability reference, not evidence
that replacing OpenRC's host or porting its application would be inexpensive.

## X04

[Unity — High Definition Render Pipeline](https://docs.unity3d.com/Manual/com.unity.render-pipelines.high-definition.html).
Official pipeline documentation, redirected to the Unity 6000.6 manual during
review. Establishes an alternative rendering pipeline; a migration would still
require explicit host, platform, physics, input, UI and content work.

## X05

[UNIGINE — Landscape Terrain](https://developer.unigine.com/en/docs/2.21/objects/objects/terrain/landscape_terrain/),
[2.22 streaming configuration](https://developer.unigine.com/en/docs/2.22/objects/objects/terrain/landscape_terrain/settings) and
[double-precision coordinate usage](https://developer.unigine.com/en/docs/future/code/double_precision/usage).
Documents terrain streaming and double-coordinate capability leads. Sources span
named releases and a `future` branch; select one supported SDK and verify terms,
precision, platform and required features before any implementation comparison.

## M01

[Microsoft — block compression](https://learn.microsoft.com/en-us/windows/win32/direct2d/block-compression).
Explains GPU block compression and illustrative 4/8-bit-per-pixel storage.
The mip-chain and field-of-view tables in [Validation](validation-and-budgets.md)
are explicitly derived arithmetic, not vendor or OpenRC benchmark results.

## Research gaps retained

No source establishes the correct Godot shadow/occlusion composition for this
application, a surveyed candidate site, rights for a particular capture, a
cross-platform export, or native contact admission for a new field. Those are
implementation and field-work gates in SC-PHOTO-01…10. No exact source/tool
release has been added as a project dependency by this research.

## Additional technique sources

E01–E20 support the [twenty follow-up investigations](additional-techniques.md).
They were selected through the [two ordered search rounds](search-rounds.md),
with primary-page opens/finds to resolve specific gaps. Historical methods and
current documentation are explicitly distinguished from the pinned runtime.
The register now has **62 records**, including the original 42.

## E01

[Debevec, Taylor and Malik — Modeling and Rendering Architecture from Photographs](https://www2.eecs.berkeley.edu/Pubs/TechRpts/1996/5357.html), 1996, and
[Debevec, Borshukov and Yu — Efficient View-Dependent Image-Based Rendering with Projective Texture-Mapping](https://www.pauldebevec.com/Research/VDTM/), 1998.
Original research on combining photographic views with approximate geometry.
Supports PT-01's representation comparison; no present-day hardware or Godot
performance is inferred from these papers.

## E02

[Shade, Gortler, He and Szeliski — Layered Depth Images](https://www.microsoft.com/en-us/research/publication/layered-depth-images/), 1998.
Original representation of multiple samples/depths along source-view rays.
Supports restricted novel-view research, with missing data and physical geometry
remaining separate problems. No LDI renderer is installed by this plan.

## E03

[Asirvatham and Hoppe — Terrain Rendering Using GPU-Based Geometry Clipmaps](https://developer.nvidia.com/gpugems/gpugems2/part-i-geometric-complexity/chapter-2-terrain-rendering-using-gpu-based-geometry), GPU Gems 2.
Authored explanation of nested terrain grids, incremental updates and LOD
transitions. Historical demonstration sizes/timings are not OpenRC budgets or
proof of contact, shader, driver or multi-camera compatibility.

## E04

[Epic Games — Runtime Virtual Texturing](https://dev.epicgames.com/documentation/unreal-engine/runtime-virtual-texturing-in-unreal-engine).
Documents on-demand cached surface shading and landscape integration in Unreal.
Used as a system-design reference. It does not establish an equivalent available
Godot subsystem or authorize copying an Unreal implementation into OpenRC.

## E05

[Deliot and Heitz — Procedural Stochastic Textures by Tiling and Blending](https://eheitzresearch.wordpress.com/738-2/) and
[Unity Labs — procedural stochastic texturing prototype](https://github.com/UnityLabs/procedural-stochastic-texturing).
Primary research/prototype on histogram-aware texture blending and filtering.
Compare with OpenRC's retained two-sample method and earlier investigations;
the prototype's engine integration and any copied code need separate review.

## E06

[Hamilton and Brown, EA DICE — Photogrammetry and Star Wars Battlefront](https://media.gdcvault.com/gdc2016/Presentations/Brown_Kenneth_Hamilton_Andrew_PhotogrammetryStarWars.pdf), GDC 2016; [session page](https://www.gdcvault.com/play/1023272/Photogrammetry-and-Star-Wars-Battlefront).
Original production presentation; inspected map-generation and lighting-removal
sections. Supports deliberate scan/material preparation. Game imagery is
reference evidence only and supplies no reusable licensed site asset.

## E07

[SideFX — Game Tools: Imposter Textures](https://www.sidefx.com/tutorials/game-tools-imposter-textures/).
Vendor authoring guidance for capture-sheet representations, including octahedral
impostors. No SideFX/UE tool or output is adopted here; OpenRC's recorded failed
candidate remains the stronger evidence about that particular tested package.

## E08

[Epic Games — World Partition HLOD](https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition---hierarchical-level-of-detail-in-unreal-engine) and
[Godot — visibility ranges (HLOD)](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html).
The first explains grouped static proxies; the second provides a Godot-native
implementation lead. Check fade mode, zoom behavior, bounds, materials and
actual scene costs; neither establishes an automatic win over existing batching.

## E09

[Godot — StandardMaterial3D height mapping](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html#height).
Documents apparent relief from a height texture and its distinction from real
geometry. OpenRC's custom ground shader would need its own bounded adaptation;
no displacement/contact or triplanar compatibility is inferred.

## E10

[Godot — large world coordinates](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html).
Documents engine precision, build/export implications and rendering limitations.
Supports keeping a measured local coordinate frame and evaluating a precision
change only against a demonstrated problem; OpenRC's float64 simulation boundary
is already a different, established contract.

## E11

[krpano — XML reference, image and multiresolution sections](https://krpano.com/docu/xml/#image).
Vendor reference documents tiled image levels and panoramic projections.
Primary page was opened directly after the targeted search returned third-party
summaries. This is a representation example; no viewer, tile service or krpano
license is adopted, and tiled delivery does not increase captured information.

## E12

[Epic Games — landscape materials](https://dev.epicgames.com/documentation/unreal-engine/landscape-materials-in-unreal-engine) and
[landscape material expressions](https://dev.epicgames.com/documentation/en-us/unreal-engine/landscape-material-expressions-in-unreal-engine).
Documents layer weights and height-aware material transitions. Supports a
small shader comparison, not a new physical heightfield or a wholesale port of
the vendor's landscape system.

## E13

[Godot — using decals](https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html).
The retrieved stable manual describes projected decals and a flat-surface
alternative, but excludes Compatibility. The inspected OpenRC 4.8 path probes
decal creation and retains a plane fallback. GDU-11b has older 4.8.beta1 crash-path
evidence; the new beta2 site combination remains untested. Preserve the probe,
receiver-aware shared capacity and plane fallback when qualifying the site.

## E14

[Godot — LightmapGI](https://docs.godotengine.org/en/stable/classes/class_lightmapgi.html) and
[using lightmap global illumination](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_lightmap_gi.html).
Documents static lighting, editor-side baking, UV/scene requirements and dynamic
object probes. Current generated scene construction needs an explicit authored
bake/export path; no scene was baked or qualified for any renderer in this task.

## E15

[Godot — ReflectionProbe](https://docs.godotengine.org/en/stable/classes/class_reflectionprobe.html).
Current reference includes Compatibility and Mobile with different per-mesh
limits, bounded updates and environment sourcing. Earlier 4.0 search results
excluded Compatibility. The current source and OpenRC's existing probe owner
guide the proposal; exact renderer and appearance still require testing.

## E16

[Godot latest — preserve alpha-test coverage on image import](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html#mipmaps-preserve-alpha-test-coverage),
[latest importer reference](https://docs.godotengine.org/en/latest/classes/class_resourceimportertexture.html) and
[3D antialiasing](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html).
Separate mip coverage from alpha-to-coverage/MSAA and material transparency mode.
The setting was absent from the retrieved stable image page; the pinned engine
source fetch was unavailable. The later repository audit found the already
enabled maple import and [GDU-11a's bounded native beta1 adoption](../../engine-upgrade/GDU-11/README.md).
That evidence corrects the initial broad uncertainty; new assets, beta2 scene
behavior and other platform/release results are not inferred from it.

## E17

[Godot — texture roughness limiter on import](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html#texture-roughness-limiter-on-import) and
[image import options](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html).
Documents an offline normal-guided roughness treatment and distinguishes it from
the runtime screen-space limiter. A material-specific comparison is required;
this does not establish removal of every form of shimmer or edge aliasing.

## E18

[Hillaire — A Scalable and Production Ready Sky and Atmosphere Rendering Technique](https://diglib.eg.org/items/8a3e5350-18b3-46bd-9274-3add5af88c75), Eurographics Symposium on Rendering 2020, [DOI](https://doi.org/10.1111/cgf.14050).
Original sky/aerial-perspective LUT method. A possible shared-atmosphere design
reference, not an OpenRC implementation, timing result or reason to apply more
haze to an already photographed atmosphere.

## E19

[Lengyel, Praun, Finkelstein and Hoppe — Real-Time Fur over Arbitrary Surfaces](https://pixl.cs.princeton.edu/pubs/Lengyel_2001_RFO/index.php), I3D 2001; [author's project page](https://hhoppe.com/proj/fur/).
Original shell/fin representation. Grass is an explicitly proposed adaptation,
not a result established by this fur paper. Contemporary low-altitude RC views,
overdraw and contact appearance require their own comparison.

## E20

[Godot — background loading](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html),
[ResourceLoader](https://docs.godotengine.org/en/stable/classes/class_resourceloader.html) and
[thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html).
Documents threaded resource requests, blocking retrieval and scene-tree safety.
Resource loading is one component of a bounded scenery-residency design; no
automatic cancellation, hitch-free upload or isolated World globals are inferred.

## F01

[CGBookcase — catalog and CC0 statement](https://www.cgbookcase.com/textures),
[Asphalt 02 maps](https://www.cgbookcase.com/textures/asphalt-02), and
[Creative Commons — CC0 legal text](https://creativecommons.org/publicdomain/zero/1.0/legalcode.en).
The selected asset page explicitly labels DirectX normal maps. Resolution and
archive contents must be checked per download; catalog filters do not establish
every asset's available sizes. No downloaded file was inspected.

## F02

[ShareTextures — license](https://www.sharetextures.com/p/license),
[terms](https://www.sharetextures.com/p/terms),
[about/free access](https://www.sharetextures.com/about), and
[Asphalt 10](https://www.sharetextures.com/textures/road/asphalt-10).
The custom-CC0 redistribution restriction and standard-CC0 distribution wording
conflict. Retain both, and hold public source/bundle distribution rather than
declaring unrestricted CC0. Access restrictions also prohibit automated and
bypassing download integration. No asset was acquired.

## F03

[TextureCan — terms](https://www.texturecan.com/terms/) and
[Grassland Ground 0009](https://www.texturecan.com/details/130/).
Terms describe CC0 and redistribution with projects/3D assets. The product page
lists 1K/2K/4K maps and SBSAR; it does not prove engine SBSAR support, downloaded
archive contents, normal handedness or suitability for maintained RC turf.

## F04

[Copernicus — DEM product catalog](https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM),
[GLO-30-F license](https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf),
[combined DEM licenses including restricted variants](https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf), and
[2026-08-25 View Service update](https://dataspace.copernicus.eu/news/2026-8-25-copernicus-dem-30m-view-service-update).
Distinguish DSM from bare-earth survey, -F from -R, and registered download
access from the restricted view service. Reuse requires the applicable exact
product notices and conditions; no download/eligibility was tested.

## F05

[OpenTopography — usage terms](https://opentopography.org/usageterms),
[access tiers](https://opentopography.org/about/subscriptions),
[developer/API conditions](https://www.opentopography.org/developers),
[Swiss 0.5 m dataset metadata](https://portal.opentopography.org/datasetMetadata?otCollectionID=OT.072026.2056.1), and
[swisstopo — original OGD terms](https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices).
Dataset rights and processing-service access are separate. Quotas are dated,
and exact free-tier eligibility for the example dataset is unverified. A 0.5 m
grid does not establish 0.5 m vertical accuracy or runway survey adequacy.

## F06

[OpenAerialMap — legal terms](https://openaerialmap.org/legal/),
[current FAQ](https://docs.imagery.hotosm.org/about/faq/),
[imagery format/metadata documentation](https://docs.openaerialmap.org/ecosystem/imagery-data/),
[browser guide](https://docs.openaerialmap.org/browser/user-guide/), and
[Creative Commons — CC BY 4.0](https://creativecommons.org/licenses/by/4.0/legalcode).
The older general CC BY statement and current instruction to check each image
require item/provider-specific verification. No particular image, resolution,
site coverage or reuse grant was selected. Orthophotos are not pilot-eye images.

## F07

[Geofabrik — free downloads and formats](https://www.geofabrik.de/en/data/download.html),
[example regional extract](https://download.geofabrik.de/europe/germany/baden-wuerttemberg.html),
[OSM — copyright/license](https://www.openstreetmap.org/copyright/en), and
[OSMF — Produced Work guideline](https://osmfoundation.org/wiki/Licence/Community_Guidelines/Produced_Work_-_Guideline).
Supports dated offline vector inputs and the distinction between produced work
and derivative database obligations. It does not decide the classification of
an unspecified generated 3D package or clear underlying third-party imagery.

## F08

[ESA WorldCover — official dataset repository](https://github.com/ESA-WorldCover/esa-worldcover-datasets) and
[2021 v200 product user manual, version 2.0](https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/docs/WorldCover_PUM_V2.0.pdf).
The manual defines categorical classes, nominal 10 m sampling, EPSG:4326 COG
tiles and product limitations; dataset CC BY 4.0 terms are distinct from the
repository code's GPL label. The general site access page timed out during
research; the repository/manual were available. No tiles were downloaded.

## F09

[MeshLab — official site](https://www.meshlab.net/),
[GPL-3.0 license](https://github.com/cnr-isti-vclab/meshlab/blob/main/LICENSE.txt),
[textured mesh filters](https://github.com/cnr-isti-vclab/meshlab/blob/main/docs/dox/filter.dox), and
[PyMeshLab — filter scripts](https://pymeshlab.readthedocs.io/en/latest/filter_scripts.html).
The site explicitly replaces meshlabserver with PyMeshLab for batch processing.
Mesh reduction/material preservation on our scan remains a proposed comparison,
not a successful import or quality result.

## F10

[CloudCompare — repository](https://github.com/CloudCompare/CloudCompare),
[versioned license file](https://github.com/CloudCompare/CloudCompare/blob/master/license.txt),
[component license wiki](https://www.cloudcompare.org/doc/wiki/index.php/License),
[cloud-to-mesh distances](https://cloudcompare.org/doc/wiki/index.php/Cloud-to-Mesh_Distance),
[global shift/scale](https://cloudcompare.org/doc/wiki/index.php/Global_Shift_and_Scale), and
[CLI](https://cloudcompare.org/doc/wiki/index.php/Command_line_mode).
GPL version statements differ across project surfaces; preserve exact release,
component and plugin notices. Approximate preview distances are not final
measurement values; compared mesh vertices alone can undersample a surface.

## F11

[PDAL — license](https://github.com/PDAL/PDAL/blob/master/LICENSE.txt),
[installation routes](https://pdal.io/en/latest/download.html),
[pipelines](https://pdal.io/en/stable/pipeline.html), and
[GDAL raster writer](https://pdal.io/en/stable/stages/writers.gdal.html).
Documents BSD software and reproducible point-cloud/raster operations, not
input-data rights, guaranteed classification accuracy or an OpenRC ground API.
Preserve selected build dependencies and geospatial processing metadata.

## F12

[OpenMVS — COLMAP interchange/usage](https://github.com/cdcseacave/openMVS/blob/develop/docs/wiki/Usage.md),
[development pipeline description](https://github.com/cdcseacave/openMVS/blob/develop/docs/pipelines.md),
[architecture/formats](https://github.com/cdcseacave/openMVS/blob/develop/docs/architecture.md), and
[copyright/third-party notices](https://github.com/cdcseacave/openMVS/blob/develop/COPYRIGHT.md).
Development docs describe CPU/CUDA paths and newer functionality that can differ
from older README/released versions. The pipeline document identifies automated
codebase analysis as its origin. Pin a release and verify the actual route;
neither documentation nor AGPL licensing supplies OpenRC performance/output rights.

## F13

[Material Maker — project and licensing](https://github.com/RodZill4/material-maker/blob/master/README.md),
[license file](https://github.com/RodZill4/material-maker/blob/master/LICENSE.md),
[export documentation](https://rodzill4.github.io/material-maker/doc/export.html),
[painting inputs](https://rodzill4.github.io/material-maker/doc/user_interface_paint_panel.html), and
[command line](https://rodzill4.github.io/material-maker/doc/command_line.html).
The export page still names SpatialMaterial; use explicit image-map interchange
and verify the current build rather than infer 4.8 material compatibility.
The repository MIT default does not clear arbitrary community/input resources.

## F14

[meshoptimizer — gltfpack options/extensions](https://github.com/zeux/meshoptimizer/blob/master/gltf/README.md),
[MIT license](https://github.com/zeux/meshoptimizer/blob/master/LICENSE.md), and
[Godot maintainer discussion of imported glTF storage](https://github.com/godotengine/godot-proposals/discussions/14857).
The optimizer can introduce extensions and discard unknown/custom data.
The maintainer comment is dated contextual evidence, not a formal guarantee
for every import/export mode. Measure the real exported resources and distinguish
editor-imported assets from runtime GLB loading.

## F15

[xatlas — project](https://github.com/jpcy/xatlas),
[MIT license](https://github.com/jpcy/xatlas/blob/master/LICENSE),
[OBJ example](https://github.com/jpcy/xatlas/blob/master/source/examples/example.cpp),
[Godot vendored source](https://github.com/godotengine/godot/blob/master/thirdparty/xatlas/xatlas.cpp), and
[Godot — lightmap UV workflow](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_lightmap_gi.html).
The example does not retain input materials. Upstream vendoring is a reason to
check the pinned engine first, not proof of a tested OpenRC bake/export pipeline.

## F16

[Evolved Software — commercial-use/tool distribution statement](https://www.evolved-software.com/),
[Tree It — formats, free access and FAQ](https://www.evolved-software.com/treeit/treeit),
[supplier Steam EULA](https://store.steampowered.com//eula/2386460_eula_0), and
[Steam product page](https://store.steampowered.com/app/2386460/).
Standalone and Steam terms must not be conflated. The EULA's supplied-pack and
attribution conditions require exact-distribution review. Direct EULA retrieval
initially failed; the supplier-linked double-slash URL was then opened successfully.
Unrelated EULA/search-aggregator results were discarded. No executable or
sample package was obtained, run or admitted for public source redistribution.

## F17

[darktable — about/license](https://www.darktable.org/about/),
[features and formats](https://www.darktable.org/about/features/),
[installation/build availability](https://www.darktable.org/install/), and
[export workflow](https://docs.darktable.org/usermanual/development/en/overview/workflow/export/).
Documents GPL-3.0-or-later, non-destructive development and explicit exports.
Current binaries and moving development manuals require version/OS checks;
no capture processing or installed-tool claim is made.

## F18

[Luminance HDR — project/formats](https://github.com/LuminanceHDR/LuminanceHDR),
[install guidance](https://github.com/LuminanceHDR/LuminanceHDR/blob/master/INSTALL.md), and
[project-license metadata](https://github.com/LuminanceHDR/LuminanceHDR/blob/master/net.sourceforge.qtpfsgui.LuminanceHDR.appdata.xml).
The metadata explicitly says GPL-2.0+; a direct LICENSE fetch failed and the
GitHub badge alone omits the later-version qualifier. Bracket merging and
tone mapping are documented, but radiometric quality and ghosting need a trial.

## F19

[libvips — overview/license](https://www.libvips.org/),
[installation](https://www.libvips.org/install.html), and
[dzsave tile-pyramid operation](https://www.libvips.org/API/current/method.Image.dzsave.html).
Documents LGPL-2.1-or-later and offline image/pyramid processing. File formats
depend on compiled plugins; a generated tile layout is not a Godot loader or
a measured memory/performance improvement for this project.

## F20

[OpenImageIO — introduction/license](https://openimageio.readthedocs.io/en/stable/oiiointro.html),
[stable oiiotool manual](https://openimageio.readthedocs.io/en/stable/oiiotool.html), and
[installation/build guidance](https://github.com/AcademySoftwareFoundation/OpenImageIO/blob/main/INSTALL.md).
The stable manual retrieved identified 3.2.2; search also returned older and
development manuals. Pin the selected tool/config. Assigning color-space metadata
and changing pixel values are distinct; processing a JPEG cannot restore lost HDR.

## F21

[KTX-Software — official tools](https://github.com/KhronosGroup/KTX-Software/blob/main/README.md),
[license/component exceptions](https://github.com/KhronosGroup/KTX-Software/blob/main/LICENSE.md),
[Khronos KTX developer guide](https://github.com/KhronosGroup/3D-Formats-Guidelines/blob/main/KTXDeveloperGuide.md), and
[Basis Universal — codecs/license/interchange limits](https://github.com/BinomialLLC/basis_universal).
KTX's optional ETC unpack decoder is expressly listed as non-open-source and
can be excluded from a build; do not label the entire dependency tree Apache.
New codec interchange claims do not establish pinned-Godot importer or GPU support.

## F22

[glTF Transform — CLI](https://gltf-transform.dev/cli),
[SDK](https://github.com/donmccurdy/glTF-Transform), and
[MIT license](https://github.com/donmccurdy/glTF-Transform/blob/main/LICENSE.md).
Supports inspection and selective transforms. OpenRC's exact 4.5.0 package pins
come from its repository, not from an assumed latest global CLI. Compression
examples require independently qualified loader extensions and asset semantics.

## F23

[Khronos glTF Validator — usage and supported checks](https://github.com/KhronosGroup/glTF-Validator/blob/main/README.md),
[JavaScript API](https://github.com/KhronosGroup/glTF-Validator/blob/main/node/README.md), and
[Apache-2.0 license](https://github.com/KhronosGroup/glTF-Validator/blob/main/LICENSE).
The general tool supports glTF/GLB, but OpenRC's existing wrapper has narrower
repository-local JSON glTF input constraints. Structural validity does not prove
appearance, scale, provenance, physical accuracy or engine compatibility.

## F24

[RenderDoc — project, MIT license and API/platform table](https://github.com/baldurk/renderdoc) and
[development build flags](https://github.com/baldurk/renderdoc/blob/v1.x/CMakeLists.txt).
The advertised support table does not admit Metal; a disabled development Metal
flag was found and is not a tested release/support promise. Use a confirmed
Windows/Linux API path for our application; keep Mac diagnosis with its existing
tools and measure final timing outside the frame-capture session.
