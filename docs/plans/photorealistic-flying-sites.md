# Photorealistic flying sites

Initial study: 2026-11-18. Strengthened: 2026-11-19.
**Status: research and adversarial review complete; implementation proposed.**
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

The [2026-11-19 adversarial review](../research/photorealistic-flying-sites/2026-11-19/README.md)
checks that plan against main `1188f1d4a1e31fd8263336b645db86535bca062f` and
adds 18 concrete corrections, 25 retained web queries and a reproducible optical
calculation. Its [implementation contracts](../research/photorealistic-flying-sites/2026-11-19/implementation-contracts.md)
and [qualification protocol](../research/photorealistic-flying-sites/2026-11-19/qualification-protocol.md)
take precedence over the corresponding initial design and E1–E5 details. No
runtime, import/export or hardware test is implied by this stronger plan.

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

This branch owns research documentation and analytical fixtures only. Future implementation paths below are
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
records the initial metadata and rendering choices. The strengthened
[contracts](../research/photorealistic-flying-sites/2026-11-19/implementation-contracts.md)
define the current proposal without changing the simulation kernel.

## Decisions from the adversarial review

| Decision | Intended result and required proof |
| --- | --- |
| First composition: same-eye panorama plus per-fragment photo-projected opaque proxies | One declared NED/image convention; synthetic cardinal/rotation/seam tests before real capture |
| Calibration depends on zoom and independently measured depth | The old four-pixel wide-view error can become 258 pixels at 1°; critical occlusion/landing features need per-view limits and held-out range evidence |
| Projected cue initially owns the photo-ground shadow | No fade toward an unqualified native receiver; preserve requested settings and qualify native aircraft self-shadow separately |
| Independent color reference | Background and proxy must each match the intended output transform, not merely match each other |
| Static photo obstacles remain nondestructible | Existing `none` scenery damage policy retains normal contacts; breakable photo objects need a later synchronized representation |
| Separate runway-start and Natural Random capabilities | A valid new runway must not expose the default-field-only random scenario route |
| Warn outside surveyed coverage | Observe accepted state, preserve flight physics and make unqualified area explicit; no automatic world swap |
| One preparation group and one activation owner | Coalesce requests, drain stale work and prevent a stale rollback from overwriting a newer World owner |
| Explicit cold-start recovery | Retry, choose another validated site or quit; no hidden field substitution and no requirement for a previous Home |
| Separate authoring, physical and export identities/budgets | Imported resources, required notices, peak memory, package size and installed size each have their own check |
| Defined GPU comparison and inconclusive result | Real GPU timing, matched workloads and a named paired statistic; normal live-flight pacing remains a separate gate |

The review's [finding-to-contract-to-test map](../research/photorealistic-flying-sites/2026-11-19/qualification-protocol.md#traceability)
assigns all 18 findings to existing steps. Research findings are addressed in the
plan; their implementation proof remains pending below.

## Delivery sequence and authoritative status

This table is the sole step-status ledger. Detailed research describes designs
and evidence requirements, not duplicate implementation status.

| ID | Work and dependency | Required proof / status |
| --- | --- | --- |
| SC-PHOTO-00 | Audit source, simulator precedent, engines, tools, rights and implementation seams; register subtrack and challenge the plan | **Research complete.** Initial study, ordered 10+10 technique searches, 24 resource dossiers/78 retained queries/86 source records; 2026-11-19 review adds 18 findings, 25 retained queries and an analytical fixture. Verification belongs in the dated READMEs; runtime/hardware proof is absent |
| SC-PHOTO-01 | Select site, rights, fixed station, runway and named hardware; depends on 00 | Pending. Representable simple turf field; separate fitting/held-out bearings/independent ranges; measured uncertainty, critical-feature visual envelope, survey coverage and per-host memory baseline under C02/Q02–03 |
| SC-PHOTO-02 | Synthetic panorama/proxy/color/shadow spike; depends on 00, real photos optional | Pending. C01/Q01 plus the synthetic disposable subsets of Q03–05: projection, seam/mips, clipping/depth, independent color and receiver-aware shadows on exact Compatibility, Mobile/Metal and applicable Forward+; real-site survey and full lifecycle proof remain in 04/05/09 |
| SC-PHOTO-03 | Separate validated descriptor, physical/presentation binding and catalog capabilities; depends on 01–02 | Pending. Strict versions/paths/transforms, named identity domains, conservative tier admission and stale-request rejection; define pure preparation, serialized activation and cold-start recovery seams under C05–07 |
| SC-PHOTO-04 | Register field and surveyed contacts; depends on 01,03. Choose supported prefabs or an SC/GP-owned measured-box/capsule builder | Pending. Deterministic bounded inventory/hash, normal impact response with nondestructible photo-baked obstacles, independent range/contact fixtures, coverage definition and reset/restore proof; no inherited Club/lake contacts, no quality-dependent physical data |
| SC-PHOTO-04a | Admit validated runway starts through Home/session; depends on 04 | Pending. Separate runway-start from Natural Random capability at UI and route boundaries; Q09 ordinary photo start succeeds, unsupported random briefing is refused, Club behavior and stale preferences remain correct |
| SC-PHOTO-04b | Extend bearing, material or ground if a real site cannot fit v1/turf assumptions; depends on 01 and GP/AS/NK design | Conditional prerequisite. Independently version material response and relief, plus bearing/normal/start/hash/replay/backend semantics; Q06 friction changes must not silently change support geometry. Otherwise choose a representable turf site |
| SC-PHOTO-05 | Integrate captured world, grounding and occlusion; depends on 02–04 | Pending. C03–04/Q04–05: independent color reference, one photo-ground shadow owner, explicit native fallback, pre-shadowed-ground crossing, refresh/pause/reset and restored preferences; no duplicate static lighting or unsupported relighting |
| SC-PHOTO-06 | Fixed-pilot and activity admission across entry points; depends on 03 | Pending. C02/C05/Q03 and Q09's camera/activity-refusal/coverage subset: fixed eye, near/far clearance, direct/saved/CLI/crash/secondary/Workshop guards and coverage notice; combined runway-start/scenario proof closes in 04a/08, camera laws unchanged |
| SC-PHOTO-07 | Reproducible capture/import and selected export variants; depends on 01–03 | Pending. C07/Q10: distinct source/derivative/physical/export identities, loader/format, notices in all presets, repeat conversion and steady/peak/download/install budgets; prequalified lowest tier (initially 4K where supported), 8K only where qualified, 16K after justification; clear refusal if no tier fits |
| SC-PHOTO-08 | Complete normal use, cold recovery, numerical replay and failure retirement; depends on 04–07, including 04a and required 04b | Pending. Q06–09: Club → photo → Green → Club, one activation owner, drained stale loads, correct continued World flow after rejection, explicit cold-start choices, save-failure handling, no residue; numerical equivalence does not claim identical material-report provenance |
| SC-PHOTO-09 | Named target-device, pilot and backend qualification; depends on 08 | Pending. [Q01–Q12 protocol](../research/photorealistic-flying-sites/2026-11-19/qualification-protocol.md): critical zoom/depth/readability, defined GPU paired statistic/noise verdict, normal live-flight pacing, peak/retired memory, native/reference admission and independently scoped platform receipts |
| SC-PHOTO-10 | Package one usable site and contributor recipe; depends on 09 | Pending. Q08/Q10/Q12: clean offline package and negative missing-resource cases, measured installed/download deltas, rights/notices, explicit supported site/device envelope and recovery; ordinary release gates remain |
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

Use the synthetic disposable subsets of the
[Q01/Q03–Q05 fixtures](../research/photorealistic-flying-sites/2026-11-19/qualification-protocol.md)
with independent color and known-depth oracles. Real-site Q02/Q03 evidence and
full World/lifecycle/pilot checks close later in 04/05/09. Exercise the current 1°–120°
vertical range, clipping and photographed-shadow overlap; a wide-view screenshot
cannot qualify telephoto occlusion. The analytical fixture in this branch is
only a convention/calculation check, not this renderer proof.

Advance only with captures and measured errors at the specified eye, seam, poles,
view headings and zooms. If one renderer fails, either implement and prove a
supported composition path or explicitly limit site availability. Dropping
essential occlusion while retaining invisible physical obstacles is unacceptable.

### Milestone B: make one site correct through normal use

Complete 03–08 in small reviewable changes. Attach one immutable descriptor to
the selected landscape, validate metadata and conservative resource estimates
before large loads, handle reported allocation failures, and keep contact data
under its existing owner. Preflight is not a free-VRAM guarantee. Prepare one
candidate group without publishing shared state; serialize activation and retire
stale requests without restoring over a newer owner. Add cold-start recovery
explicitly because no previous scene may exist. Introduce a deliberate photo
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

Use Q11's defined paired GPU statistic and noise/inconclusive decision, separately
from complete live-flight frame pacing. Q10 measures actual package and installed
size as well as resource residency. A texture variant can remain unloaded yet
still ship through the current all-resources presets. Required notices and
physical metadata must survive a clean export without developer originals.

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

The ranges below are retained **2026-11-18 baseline estimates, now low confidence**.
They have not been re-estimated for the strengthened World preparation,
cold-start recovery, load retirement, optical or device/export evidence work.
Re-estimate after SC-PHOTO-01/02 resolve site and rendering feasibility; do not
use the old totals as a delivery commitment. Optional resource comparisons do
not make every researched tool a prerequisite.

These are engineering estimates, not measured delivery dates or vendor quotes.
Assume one experienced Godot developer and part-time photo/3D support, access to
a modest flat site, and access to the stated test devices.

| Work package | Earlier effort range, not revalidated | Main uncertainty |
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
