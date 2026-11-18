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
