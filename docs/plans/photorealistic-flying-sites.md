# Photorealistic flying sites

Date: 2026-11-18. **Status: research complete; implementation proposed.**
Owner: scenery, with landscape, camera, field-world/time-of-day, UI, ground/contact,
native-backend, replay, graphics and desktop-delivery co-owners.
Prefix: **SC-PHOTO-00…15**. Parent gates: SC/VQ and the existing platform gates;
Gate P continues to own physics headroom.

## Recommendation

Build a **fixed-pilot photographic site in the existing Godot application first**.
Use a calibrated 360° panorama for appearance, the existing simulated aircraft,
independently authored ground/contact data, visual occlusion proxies and a matched
aircraft shadow. Then develop a **3D site assembled from photographs and optimized
geometry** for FPV, chase cameras and moving observers. Treat these as different
site capabilities in the same landscape system.

Keep Godot `4.8.beta2.official.cafc17a19` and OpenRC's float64, 240 Hz simulation
boundary. Native C++ is already an evaluator option; it is not an alternative
scenery renderer. Add native preparation or streaming only when a measured
bottleneck justifies it. A separate engine/renderer is a conditional investigation,
not a prerequisite for photographic scenery.

This interprets the request's “Onative” as native C++ or a native renderer; no
specific product with that name was established. The [options study](../research/photorealistic-flying-sites/2026-11-18/approaches-and-tools.md)
also covers Unreal, Unity and UNIGINE so the engine question remains reviewable.

The recommendation follows official RC simulator precedents and an audit of
`main` at `f7b348e40aa5a44c4cc091d540fbffb55016e583`. The
[dated research pack](../research/photorealistic-flying-sites/2026-11-18/README.md)
contains primary references, the exact source seams, asset workflow, experiments
and limitations. No panorama, addon, new landscape, runtime change or performance
result is delivered by this planning branch.

The follow-up [twenty technique investigations](../research/photorealistic-flying-sites/2026-11-18/additional-techniques.md), based on [ten searches followed by ten adaptive searches](../research/photorealistic-flying-sites/2026-11-18/search-rounds.md), extend this recommendation with game-production methods and explicit current-code comparisons. Their selected experiments are assigned to the existing steps below; they do not introduce twenty mandatory features.

The next [24 free-resource investigations](../research/photorealistic-flying-sites/2026-11-18/free-resources.md)
add asset/geodata sources, mesh/material tools, image preparation and delivery/
diagnostic utilities, with [78 retained search strings and a repository audit](../research/photorealistic-flying-sites/2026-11-18/resource-search-record.md).
Their source-specific licensing, existing-tool reuse and proposed trials refine
the workflow below. The research pack now contains 86 stable source records;
this does not mean 86 websites or 24 adopted dependencies.

## Product scope

| Site type | Intended experience | Camera and lighting contract |
| --- | --- | --- |
| Photographic pilot site | Recognizable real RC field; takeoff, landing and line-of-sight flight from one surveyed station | Rotation, tracking and zoom at one fixed eye. Captured lighting. No freely translating view or claim of stereo scenery |
| 3D photographic site | FPV, chase, inspection and later freely moving observers | Geometry supplies parallax; lighting changes only where materials/geometry support them |
| Multiple photographic stations | Later selection between separately captured viewpoints | Discrete calibrated stations; no invented continuous path between panoramas |
| Radiance-field experiment | Optional comparison of Gaussian splats/NeRF with the 3D baseline | Separate depth, collision, portability, rights and motion gates |

The first usable pilot covers one rights-cleared field and one synthetic
calibration fixture, fixed-wing aircraft, one pilot station, a surveyed flat
runway/contact region, a few meaningful obstacles, one captured daylight
condition, saved landscape selection and packaged offline use. Helicopter and
other vehicle support requires explicit admission. Existing FPV scenes have a
different construction route and are not enabled by registering an adapter.

Choose a field that fits the existing rectangular contact surfaces, runway
bearing, maintained-turf contact assumptions and supported obstacle primitives.
The current rectangles are aligned
with N/E and runway starts face east/west; Home also gates runway availability
on the legacy field ID. A new photo runway therefore needs explicit start
capability work, and an arbitrary real bearing needs a separately scoped format/
contact/start extension. Do not rename the new field `default`, rotate only the
photo, or relabel a rotated local frame as true NED to bypass these constraints.
Paved or materially different ground needs site-specific surface-table wiring
and physical identity/qualification; its texture alone cannot change friction
or the current estimated turf microrelief.
Reject a visibly sloping or irregular runway as the first
physical site unless ground/contact owners implement the missing representation.
A photograph of a hill does not provide a terrain solver. Distant scenery can be
decorative with its physical limits declared; obstacles reachable within the
admitted flight area need corresponding contact semantics.

## Ownership and proposed paths

This branch owns documentation only. Future implementation paths below are
proposals and do not indicate that these files or interfaces already exist.

| Area | Proposed work and owner boundary |
| --- | --- |
| Site assets and metadata | `app/landscapes/<photo_site_id>/` and a validated presentation sidecar; use an explicit catalog entry. Keep `openrc-field v1` strict |
| Shared photo presentation | Small reusable components under `app/render/photo_site/`; coordinate `World` and field-lighting ownership before adding writers |
| Camera capabilities | Landscape metadata consumed by the existing rig, settings, shortcuts, launch/restore paths and secondary views; CAM retains camera laws. A future visual replay must obey the same capabilities |
| Ground and obstacles | Existing field/surface and collision owners; one stable physical identity independent of visual quality |
| Source pipeline | `assets/landscapes/<site_id>/` for compact authoring/provenance, `tools/landscapes/` for accepted conversion/validation; large masters outside ordinary Git history |
| Evidence | `docs/research/photorealistic-flying-sites/SC-PHOTO-*/`; scripts/data under root `research/` only when needed by an accepted experiment |
| Native/platform admission | Existing NK/DT owners; no bypass of field/world/start/binary guards |

The [architecture audit](../research/photorealistic-flying-sites/2026-11-18/current-architecture.md)
names existing methods and consumers. The [Godot design](../research/photorealistic-flying-sites/2026-11-18/godot-design.md)
defines the proposed metadata and rendering decisions without changing the
simulation kernel.

## Delivery sequence and authoritative status

This table is the sole step-status ledger. Detailed research describes designs
and evidence requirements, not duplicate implementation status.

| ID | Work and dependency | Required proof / status |
| --- | --- | --- |
| SC-PHOTO-00 | Audit current source, official simulator precedent, engines, tools, rights and implementation seams; register subtrack | **Research complete.** Initial pack, twenty technique investigations from two ordered rounds of ten searches, and 24 additional free-resource investigations with 78 retained query strings; 86 source records. Documentation checks recorded in its README; runtime and hardware evidence remain absent |
| SC-PHOTO-01 | Select pilot site, capture rights, camera station, runway measurements and platform baseline; depends on 00 | Pending. Rights/provenance record, measured versus estimated quantities, held-out landmarks, named hardware and agreed acceptance envelope |
| SC-PHOTO-02 | Disposable panorama + occlusion + shadow rendering spike on synthetic geometry; depends on 00, real photos optional | Pending. Same fixture in Compatibility, Mobile/Metal and applicable Forward+ configurations; choose a supported composition method before building a complete site |
| SC-PHOTO-03 | Validate a separate site descriptor and catalog capability lookup; depends on 01–02 | Pending. Existing adapters retain their contract; unknown versions, bad paths/transforms and mismatched field identities fail before scene replacement; bounded memory admission |
| SC-PHOTO-04 | Register the first field and calibrated contact inventory; depends on 01,03. Choose a representable existing prefab inventory or implement an SC/GP-owned validated measured-box/capsule input/builder | Pending. Explicit dimensions, transforms, stable response/damage IDs, duplicate/malformed rejection, bounded deterministic bins/hash, runway/landmark overlays, analytical hit/miss/contact fixtures, quality-invariant physical hashes, no inherited Club obstacles or lake |
| SC-PHOTO-04a | Admit the new field's validated runway starts through Home and session start rules; depends on 04 | Pending. Replace the relevant legacy-ID assumption with an owned capability; takeoff, reset, landing, launch choice and stale preferences work without forging a stock identity |
| SC-PHOTO-04b | Extend runway orientation, site-specific surface-table wiring or ground representation if the chosen real site cannot fit field v1 and current turf assumptions; depends on 01 and GP/AS/NK design | Conditional prerequisite to that site's physical acceptance. Versioned data, bearing/material/normal/start/replay semantics and backend parity, including material mismatch rejection; otherwise select a representable pilot site |
| SC-PHOTO-05 | Integrate photo lighting, aircraft grounding, occlusion and shadow policy with `World`; depends on 02–04 | Pending. No duplicate sun/clouds/static shadows; front/behind visibility and contact shadows survive refresh, pause and reset; no unsupported dynamic relighting |
| SC-PHOTO-06 | Admit fixed-pilot camera and supported activities across every entry point; depends on 03 | Pending. Keyboard cycling, direct selection, saved views, CLI/debug routes, crash camera, magnifier, Home and live restore paths cannot move the eye accidentally; clear recovery to a supported view/site |
| SC-PHOTO-07 | Reproducible capture/import, 4K/8K/16K variants and export resources; depends on 01–03 | Pending. Provenance, source/output hashes, import settings, dimensions/formats, memory checks, repeat conversion and clean-package asset resolution |
| SC-PHOTO-08 | Complete Home → flight → pause/reset → Home, technical restore/offline numerical replay checks and failure cleanup; depends on 04–07, including 04a and any required 04b | Pending. Club → photo → Green → Club; synchronous/staged/cancelled/superseded loads preserve nodes, selection and shared World/Atmosphere/appearance/cloud transport ownership; previous scene still updates and refreshes; resources release; no camera/reflection/contact residue |
| SC-PHOTO-09 | Target-device, pilot and backend qualification; depends on 08 | Pending. [Validation matrix](../research/photorealistic-flying-sites/2026-11-18/validation-and-budgets.md), readable aircraft/landings, native/reference admission receipts, full-session frame pacing and memory, independently scoped platform results |
| SC-PHOTO-10 | Package one usable photographic site and contributor recipe; depends on 09 | Pending. Offline export/install smoke, redistributable asset set, documented site limits and rollback; normal release gates still apply |
| SC-PHOTO-11 | Build one small 3D photographic site; compare ordinary meshes against Terrain3D 1.1.0; follows successful pilot or a documented early need for moving views | Conditional. Same measured ground/obstacle dataset; no arbitrary heightfield is admitted until GP/NK/replay contracts exist. Exact Metal, export, physics and renderer evidence required |
| SC-PHOTO-12 | Integrate the accepted 3D site into multirotor FPV and other selected activity routes; depends on 11 | Conditional. Explicit route plumbing, spawn/reset/race/contact/replay checks and rapid low-altitude traversal; a landscape catalog entry alone is insufficient |
| SC-PHOTO-13 | Multiple photo stations, additional captures/conditions and optional restricted panorama VR | Deferred. Each station calibrated; explicit switching and memory policy. VR has a separately accepted mono/stereo and head-translation design; no six-degree-of-freedom claim from one panorama |
| SC-PHOTO-14 | Bounded Gaussian splat/NeRF comparison against the accepted 3D mesh site | Deferred. Named implementation, distributable license, depth/aircraft/shadow/rapid-motion/stereo tests and measured benefit on required devices |
| SC-PHOTO-15 | Native preprocessing/runtime optimization, or separate-engine experiment if a demonstrated Godot limit remains | Conditional. Profiled bottleneck, simpler alternatives attempted, same-scene comparison, total integration/maintenance cost, project-owner decision before adopting an engine migration |

### Milestone A: prove the rendering method

Complete 02 before committing to panorama-specific art production. Generate a
small compass/latitude/longitude test texture and known box/runway geometry in
an isolated experiment. Test the material, background color, photo-projected
opaque proxies and the shadow receiver together. A transparent object with alpha
zero is not proof of a correct depth-only pass. `OccluderInstance3D` for culling
is not a substitute for pixels that hide the aircraft.

Advance only with captures and measured errors at the specified eye, seam, poles,
view headings and zooms. If one renderer fails, either implement and prove a
supported composition path or explicitly limit site availability. Dropping
essential occlusion while retaining invisible physical obstacles is unacceptable.

### Milestone B: make one site correct through normal use

Complete 03–08 in small reviewable changes. Attach one immutable descriptor to
the selected landscape, validate before allocating high-resolution resources,
and keep contact data under its existing owner. Introduce a deliberate photo
presentation policy in `World`; replacing a sky material only inside an adapter
will not survive the existing sky/exposure/time updates.

The default photo experience preserves the captured time and appearance. The
player may change physical wind within the existing weather contract; explain
that the photograph remains static. Settings that cannot change photographed
clouds, trees, sunlight or surface wetness must not suggest that they can.
Restoring the prior site restores its own normal visual controls and saved
preferences. Do not silently overwrite global preferences to enforce a site
restriction.

Unsupported moving camera requests should retain or restore the fixed pilot
view with a short reason. Changing to a separate 3D site occurs through the
existing session transition, not through an unannounced mid-flight world swap.
Explicit automation/test requests should return a clear capability refusal.
Home currently forwards field paths into some activities that bypass landscape
adapters. Block those incompatible activity/field pairs before launch; leaving
them selectable would combine mismatched presentation and contacts. The
independently positioned magnifier and `--look_alt` also need explicit handling.

### Milestone C: qualify the experience and the release

Complete 09–10 on named physical hardware. The main target is 1920×1080; on Apple
Silicon Retina displays the target is the native physical panel, recording
output, drawable and internal 3D dimensions separately. Higher PC resolutions
follow the shared priority; 720p is a final compatibility fallback. Refer to
[AGENTS](../../AGENTS.md#display-resolution-priorities) and the
[Apple plan](apple-silicon-performance.md), not historical screenshot dimensions.

Record renderer and simulation backend independently. A photo-site result on
the reference evaluator is not evidence that an unqualified native domain is
admitted. Conversely, a native numerical pass is not a visual or frame-rate pass.
Same-physical-scene visual toggles must preserve accepted simulation state and
contact inventory; comparisons between different physical sites are not expected
to produce identical trajectories.

### Milestone D: add moving-camera realism

For 11–12, use photographs to build a small optimized 3D field: runway and near
terrain, a few scanned structures, reconstructed or authored trees, and a distant
background that is valid across the admitted camera volume. Keep a plain-mesh
baseline. Terrain3D is optional, with exact engine/renderer/build checks and a
separate ground-sampling contract if required.

A panorama containing nearby buildings cannot simply become an infinite-distance
sky for chase/FPV. Remove or replace its near objects, use only sufficiently
distant sky/horizon content, and test disocclusions. Raw photogrammetry also
contains baked shadows and incomplete geometry. Cleanup and contact calibration
are part of the work, not optional postprocessing.

## Priorities from the twenty-technique follow-up

The [comparison and proposed tests](../research/photorealistic-flying-sites/2026-11-18/additional-techniques.md) refine the sequence without changing step status:

- **02/05 — composition:** prioritize PT-01 single-eye photographic projection onto measured proxy geometry. Qualify shadow/reflection/secondary-view behavior separately from the pilot image; multi-view reconstruction is a later option.
- **07 — source detail:** retain ordinary panorama variants as the first baseline. Compare PT-11 multiresolution tiles only when the captured detail and actual zoom/memory results justify a custom page representation. Tiling cannot create missing image information.
- **03/07/08 — loading:** PT-20 reuses staged construction and adds bounded resource requests, stale-result rejection and measured upload/residency costs as needed. It cannot stream physical ground or contacts according to graphics quality.
- **11 — 3D asset quality:** first compare PT-06 lighting-reduced scans, PT-12 a controlled shoulder material blend, PT-13 local markings/overlays and PT-17 normal-guided roughness filtering where the actual material has a confirmed specular response. Use existing ground/world/asset owners and shared material conventions; binding a grass roughness map alone does not create that response.
- **05/11 — lighting:** PT-15 reuses bounded reflection ownership; PT-14 baked lighting is conditional on an authored, fixed-lighting 3D scene and an editor-bake/export path.
- **09/11 — measured detail cost:** PT-08 HLOD and extensions of PT-16 foliage filtering need a demonstrated baseline defect and separate moving-view/zoom evidence. Retain the already-adopted maple coverage recipe and its bounded GDU-11a beta1 evidence; qualify new assets/beta2/platforms separately. Preserve the earlier rejected impostor, ordinary-mipmap and ridge-LOD candidate records.

Clipmaps, runtime virtual texturing, layered-depth rendering, shell vegetation,
new atmosphere LUTs and a general floating origin remain conditional research.
Exact engine capability checks take precedence over old or moving documentation;
the follow-up found version differences in decals, reflection probes and foliage
import options. These choices require no engine migration or dependency upgrade
to be assumed during planning.

## Resource adoption within the existing steps

The [24 dossiers](../research/photorealistic-flying-sites/2026-11-18/free-resources.md)
are a screened set of options. Start with the shortest working authoring chain
and add a tool only to resolve a measured deficiency or a reproducibility need.
These are proposed choices, not another implementation-status ledger.

| Existing work | Resource decision | Evidence before adoption |
| --- | --- | --- |
| 01/02/05/07: first photographic pilot | Retain Hugin/Blender/Godot; darktable (FR-17) for RAW and Luminance HDR (FR-18) for justified brackets | Controlled capture/master, no ghosting or unexplained color/exposure seams, separate display/lighting resources |
| 07: reproducible imagery and models | Compare OpenImageIO or libvips (FR-20/19) as needed; reuse pinned glTF Transform and Validator (FR-22/23) | Exact versions/configuration, source/output hashes, accepted candidate with zero validator and resource-load errors, correct repeat import and clean export |
| 07/11: material candidates | Shortlist one exact CGBookcase or TextureCan asset (FR-01/03); Material Maker (FR-13) remains optional | Per-file terms/hash, map channels/normal convention, physical tile scale, visual improvement and actual imported resource cost |
| 01/07/11: real-world context | Copernicus, OpenTopography, OpenAerialMap, OSM/Geofabrik and WorldCover (FR-04…08) remain product/site-specific | Actual geographic coverage, data/service rights, attribution, date/CRS/datum/resolution, independent alignment checks; context does not establish contact truth |
| 04b/11: measured 3D scene | ODM/Blender baseline first; MeshLab, CloudCompare, PDAL and OpenMVS (FR-09…12) only for a specific cleanup/QA/input/reconstruction comparison | Same small input set, retained transforms/settings, held-out survey errors, completeness, processing cost, supported authoritative contacts |
| 07/09/11: optimization | Inspect existing native meshoptimizer/unwrap first; gltfpack, xatlas and KTX/Basis (FR-14/15/21) are conditional | Required names/materials/metadata preserved, each extension/codec tested on pinned Godot and exported targets, measured shipped size/residency/frame behavior |
| 02/09: graphics diagnosis | RenderDoc (FR-24) on a confirmed API/device path; existing native Mac tools for Metal | Inspect actual passes/resources, then measure frame pacing outside capture; keep platform results separate |
| 01/07/10: distribution exclusions | Hold ShareTextures (FR-02) while its terms conflict; Tree It (FR-16) is low priority with distribution-specific and sample-rights checks | Exact intended source/binary packaging grant; no assumption that a free download or tool license clears a public asset bundle |

Reuse [ground intake](../../tools/ground/README.md) and the
[tree pipeline](../../tools/trees/README.md), including their asset-specific
limitations. The existing validator wrapper accepts repository-local JSON glTF;
a new external GLB route needs deliberate intake/API work. No new service key,
online runtime terrain dependency, tool installation or engine upgrade is
required by this plan. The [capture pipeline](../research/photorealistic-flying-sites/2026-11-18/capture-and-asset-pipeline.md)
defines the per-source and per-output records needed to make the selected chain
reproducible and redistributable.

## Planning ranges and staffing

These ranges retain the original scope. The resource choices above add optional
comparisons within the existing steps, not a requirement to adopt every tool.

These are engineering estimates, not measured delivery dates or vendor quotes.
Assume one experienced Godot developer and part-time photo/3D support, access to
a modest flat site, and access to the stated test devices.

| Work package | Initial effort range | Main uncertainty |
| --- | --- | --- |
| Synthetic rendering/capability proof | 4–8 developer days | Cross-renderer occlusion/shadow/color behavior |
| Usable one-site pilot after that proof | Another 10–20 developer days, plus 2–5 capture/asset days | Field survey quality, lifecycle integration and platform fixes |
| Small 3D/FPV proof after site data is available | Another 15–30 developer days, plus 10–25 asset days | Terrain/contact extension, scan cleanup, native admission and moving-camera performance |
| Multiple stations, VR, splats or another renderer | Estimate after a bounded experiment | These are independent expansions, not included in the pilot |

Capture scheduling, permissions, missing hardware and review waits add calendar
time. Existing equipment and open tools can cover the initial pipeline; do not
purchase software or hardware before a representative dataset demonstrates a
specific need. Optional paid reconstruction/stitching tools are compared in the
research, with their terms checked again at selection.

## Main risks and decisions to resolve during implementation

| Risk | First control / evidence that resolves it |
| --- | --- |
| Impressive photo but wrong runway scale or eye height | Survey station and independent landmarks before tuning geometry; show overlays and errors |
| Aircraft renders in front of photographed obstacles | SC-PHOTO-02 front/behind fixture and calibrated visual proxies |
| Collisions do not match pictures | Distinct visual/contact representations with one surveyed transform; debug overlays and analytical trajectories |
| Camera or World updates invalidate the panorama | Central capability and presentation policy, exercised by all lifecycle routes |
| Zoom reveals a blurry background | Source-detail calculation and actual zoom review; allow measured texture tiers without claiming invented detail |
| Memory or shader-loading spikes | Bounded texture admission, one active site, staged loading and measured cold/warm peaks |
| Terrain plugin bypasses the simulator | Shared authoritative ground/obstacle data; no use of Godot rigid bodies as a second flight solver |
| Mac/native path is incorrectly described as supported | Exact engine/binary/site-domain receipt and reference fallback; physical-device qualification remains separate |
| Unclear source rights or enormous Git assets | Per-asset provenance and redistribution record; compact manifests and external large masters |

The first implementation action is **SC-PHOTO-02**, while collecting the
SC-PHOTO-01 site brief. This produces a concrete visual proof cheaply and resolves
the highest-risk renderer assumptions before commissioning a complete airfield.
