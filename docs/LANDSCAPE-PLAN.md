# Landscape plan: current field and open work

2026-10-20 · Revision 12 · Step prefix: **L**

**Status:** the daytime field, treeline and visual cues are implemented. The separate LU-00…30 landscape integration is also delivered; its remaining cost and acceptance gates are summarized below. L9 ground review, L6c owner readability review, terrain work and wind integration remain open. Static tree and scenery contacts are gameplay estimates, not physical calibration. Gate L remains open.

**Owns:** field data, landscape rendering and tools listed in the [track registry](README.md#tracks-plans-and-step-ids). Field-world composition is coordinated in [FIELD-WORLD-PLAN](FIELD-WORLD-PLAN.md); selectable time is owned by [TIME-OF-DAY-PLAN](TIME-OF-DAY-PLAN.md). Scenery assets remain in [SCENERY-PLAN](SCENERY-PLAN.md).

## Current implementation

Home selects Club field or Green paradise through the explicit landscape catalog. The scenery, lake and vegetation work below describes Club field; Green uses one flat grass mesh without those layers. [Contributor guide](LANDSCAPES.md), [selection plan and remaining gates](plans/landscape-selection.md), [L21–L24 verification](research/landscape-upgrade/L21-24/README.md).

- L0–L7 provide the capture baseline, fixed-sun sky/haze/clouds, shared field builder, treeline cards and far landscape. L6 uses validated CC0 source packages and a small runtime atlas; detailed source meshes remain authoring inputs.
- LU-16-R2 refines Club's downloaded Colombian SRTM mountains at 1.6–8.6 km north. Four chunks now use 27,648 triangles, source-derived relief/habitat textures and two compressed CC0 photographs for rock and vegetation variation. These mountains remain visual-only. [Sources, captures and repeated cost measurements](research/landscape-upgrade/LU-16-R2/README.md).
- LU-28 adds 50 agricultural parcels, a divided highway, connected village/farm roads, eight houses, a second farmyard, fences, shrub crop rows and cattle. Offline geometry uses 24 spatial batches and 6,380 triangles; the road photograph is downloaded CC0 and other assets are reused. Surfaces remain visual-only; added structures use the existing scenery collision pipeline. [Research, captures, checks and cost](research/landscape-upgrade/LU-28/README.md).
- LU-29 adds synchronized turbine/antenna markers, twelve hillside homes and warm regional lighting at houses, farms, gates, junctions and the church. It uses 157 optical instances, zero new dynamic lights and about 9.5k triangles. New distant houses/towers remain visual-only. [Research, native captures, tests and measured cost](research/landscape-upgrade/LU-29/README.md).
- L9 has filtered turf and field surfaces. L9e is engineering-verified; L9b's visual review and L9c's perceived stripe shimmer still need acceptance. Near grass is a separate opaque layer with no collision.
- L10 cues include the windsock, pilot station and flightline barrier, with soft contact grounding. [L10a-R1](research/visual-quality-implementation/L10a/README.md) adds textured fabric, seams, folds and mast fittings. [L10b-R1](research/visual-quality-implementation/L10b/README.md) renews the station with textured timber, powder-coated framing and fitted hardware. [L10c-R1/R2/R3](research/visual-quality-implementation/L10c/README.md) add beveled timber, fitted steel saddles and caps, downloaded wood/metal textures, weathering and bounded grass/clover at post feet. L11a near grass is implemented. L11b reuses SC-16/17 flora through the scenery layer; it does not duplicate assets.
- L14 static obstacle contacts now use the shared float64 LU-05 collision world, built from field, scenery and light data. Its inventory includes field-tree trunk/crown proxies and nearby structures, vehicles, parked aircraft, lights and field objects. The [LU-05 collision report](research/landscape-upgrade/LU-05/collision-report.md) records coverage and limits. Proxy sizes, foliage responses and impact thresholds are gameplay estimates, not sourced structural strength; the nearby-query cost gate remains open.
- L15b tree sway and L15d cloud-shadow rendering are implemented. Their physical wind integration remains with M5. Dynamic wind and foliage sound is delivered by [AUD-01…05](AUDIO-PLAN.md), rather than pending L15e work.

The static collision world does not supply a heightfield. Until L12 terrain is implemented, distant visual ridges remain non-colliding. L14's current proxies also do not make trees deform, break or hold a wreck.

## Open steps

| ID | Remaining work | Status / acceptance |
| --- | --- | --- |
| L6c | Owner readability review against trees and near grass. | Numbers and blinded kit are prepared; owner score pending. See [L6c evidence](research/visual-quality-implementation/L6c/README.md). |
| L9a/b/c | Ground parity, macro variation, field-surface transitions and stripe shimmer. | L9b is implemented with review pending; L9c engineering checks pass but perceptual acceptance is open. L9a remains in the visual sequence. |
| L11b | Accept or revise the reused bushes and flowers. | Gate SC/readability decision; implementation remains in the scenery layer. |
| L12a/b/c, L13a/b | Add the larger terrain grid, matching near/far mesh and generated relief. | Not implemented. GP already provides per-wheel float64 micro-relief and matching normal cues; it does not supply a displaced landscape heightfield. Do not treat visual hills as physical slopes. |
| L15a/c | Extend calibrated windsock, grass/bush/flag response from M5. | Physical cue/advection acceptance remains open; wind/foliage audio is delivered by AUD. |
| L15b/d | Connect the verified rendering to M5 wind. | Rendering is complete; integration remains open. |

### Selected implementation follow-ups

The [global implementation plan](plans/global-performance-visual-quality.md#3-order-dependencies-and-reviewable-deliveries) owns sequencing and acceptance details for this bounded delivery. These rows register unused follow-up IDs; all remain unimplemented. Existing L6c and L15a/c continue under their original IDs.

| ID | Work | Status / acceptance |
| --- | --- | --- |
| LU-10-R1 | Attribute current scenery/lake query cost and repair one demonstrated bottleneck. | [Empty hull-envelope repair and oracle/session parity](research/landscape-upgrade/LU-10-R1/README.md) delivered; local query gain demonstrated, full-flight cost acceptance remains open. |
| L9e-R1 | Compare current turf blending with one Laplacian candidate on retained maps. | Planned after VQ-02a and visibility reference; preserve masks/gradients/cues and pass combined visual/cost gates. |
| L6b-R1 | Compare existing atlas alpha coverage with native alpha-to-coverage when a motion defect is reproduced. | Planned probe after VQ-02a; MSAA/scissor/edge compatibility, motion and cost proof. Custom mip importer excluded. |
| LU-22-R1 | Correct one confirmed shore/material discontinuity using existing boundary/depth data. | Conditional on pilot/overview review after ground work; visual/contact alignment and no new water physics or general authoring system. |

The L15a windsock now consumes committed M5 wind with a swiveling basket and damped fabric response; [sources and software/visual evidence](research/wind-implementation/M5-W04b-R1/README.md). Independent physical cue calibration remains open. This delivery does not reopen completed foliage/audio work.

The [grass quality plan](plans/grass-quality.md) refines texture, silhouette, placement and motion work under the existing global budgets, with [44 dated source investigations](research/grass-quality-2026-10-17.md), including 24 additional technical, asset, tool and community investigations. It owns the pending details for the following reserved follow-ups; existing VQ-02a, L9e-R1, L15c and L9d-05/06 retain their original owners. Default imported near grass remains static. The implemented `OPENRC_GRASS_QUALITY=enhanced` preview adds shared photographic turf, a 100/30/20 species allocation and bounded imported wind; [native comparisons, tests and unresolved full-session gates](research/visual-quality-implementation/grass-quality/README.md). The scenery-off fallback's wind/fade proof does not establish imported-route acceptance.

| ID | Work | Status / acceptance home |
| --- | --- | --- |
| L9e-R2 | Compare a grass-only binding of retained 2K Grass001 in shared flight/Home after the L9e-R1 outcome. | [Grass implementation sequence](plans/grass-quality.md#3-reviewable-implementation-sequence). |
| L11a-R1 | Qualify imported-grass silhouette, species allocation, root/ground match and habitat placement using retained free assets. | [Grass implementation sequence](plans/grass-quality.md#3-reviewable-implementation-sequence). |
| L11a-R2 | Repair a demonstrated grass batch-culling or transition defect within measured budgets. | [Grass implementation sequence](plans/grass-quality.md#3-reviewable-implementation-sequence). |

The [tree and forest quality plan](plans/tree-forest-quality.md) owns source selection, tree materials, woodland composition and density work, supported by the [source/code audit and 25 additional investigations](research/tree-forest-quality-2026-10-17.md). The [completion evidence](research/visual-quality-implementation/L6c/tree-completion/README.md) records eight downloaded mature forms, same-count irregular far patches, source-preserving imported-tree wind, bark-only mipmaps, material-derived foliage variation and four decorative woodland margins. The complete high-quality scenery contains 649,919 source triangles. Five alternating 720p live-flight pairs meet the numerical frame-time and simulation/wall targets under the recorded desktop load; the frozen suite, final overlay checks and three-platform export-resource checks pass. Measured spatial batching and the tested octahedral impostor configuration were not adopted; density growth and supplier oak LOD replacement remain unqualified. Independent owner readability/preference, lower-end target hardware and combined grass/tree release acceptance remain open. Physical tree envelopes and changed world identities stay coordinated with SC/LU.

| Reserved IDs | Scope | Acceptance home |
| --- | --- | --- |
| L6a-R1, L6b-R2 | Additional downloaded silhouettes and qualified material/palette changes; L6b-R1 retains the separate alpha experiment. | [Tree implementation sequence](plans/tree-forest-quality.md#7-reviewable-implementation-sequence). |
| L7-R1, L7-R2 | Same-count woodland composition, then measured batching/density changes with explicit world identity. | [Tree implementation sequence](plans/tree-forest-quality.md#7-reviewable-implementation-sequence). |
| L8a, L8b | Optional downloaded mesh/LOD/card qualification; existing impostor tooling only for a demonstrated residual need. | [Tree implementation sequence](plans/tree-forest-quality.md#7-reviewable-implementation-sequence). |
| L15b-R1 | Imported-tree wind qualification, preserving field cards and shared grass consumers. | [Tree implementation sequence](plans/tree-forest-quality.md#7-reviewable-implementation-sequence). |

## Landscape integration

LU-00…30 adds licensed field assets, night lighting, imported vegetation, a finite lake, agricultural surroundings and downloaded transmission-line assets. [LU-30-R1](research/landscape-upgrade/LU-30-R1/README.md) brings the nearest transmission tower to 652 m from the field origin, expands the corridor to nine towers, reduces insulator geometry and adds 17 batched red markers. Use compatible existing distributable assets where available; record source, license and conversion steps. The [LU evidence index](research/landscape-upgrade/README.md) links the dated implementation and verification records.

[LU-31](research/landscape-upgrade/LU-31/README.md) reduces botanical placement
and mesh-accounting CPU work without changing the rendered landscape. Matched
captures are pixel-identical; existing grass-mask integration failures and the
limits of shared-machine timing are recorded in its evidence.

| Remaining gate | Current status | Evidence |
| --- | --- | --- |
| Nearby scenery-query cost | The 100 µs target remains open; measured costs and the accepted bounds are recorded in the latest native reports. | [LU-21](research/landscape-upgrade/LU-21/README.md), [LU-22](research/landscape-upgrade/LU-22/README.md) |
| Pilot readability and lower-end hardware | Independent owner review and target-machine evidence remain open under Gate L and the scenery/world gates. | [L gates](#gates-and-evidence), [scenery guide](SCENERY-PLAN.md), [field-world guide](FIELD-WORLD-PLAN.md) |
| Lake impact and buoyancy | Current land aircraft stop on water entry; the sinking effect is visual. Water response and impact parameters are not physically validated. | [LU-22](research/landscape-upgrade/LU-22/README.md) |

L9d now has a bounded [RC ground close-view plan](plans/rc-ground-closeup.md): the [2026-10-15 audit](research/rc-ground-closeup-2026-10-15/README.md) documents dirt detail, shoulder continuity and grass limitations from native captures. L9d-01…04 now have an RC-local 2K CC0 dirt/grass implementation with shared shoulders and exact mesh/state checks; see the [implementation evidence](research/rc-ground-implementation-2026-10-15/README.md). L9d-05 remains conditional vegetation work; L9d-06 retains lower-end hardware, owner playtest and shared Home/flight qualification. Shared field adoption retains VQ/flight-readability gates.

L8 (near 3D tree models), L16–18 (photo sky, owner's field and Terrain3D), and L20 (sky-grid aid) are optional and start only if a gate justifies them. L19's time-of-day work is owned by [TIME-OF-DAY-PLAN](TIME-OF-DAY-PLAN.md).

## Gates and evidence

Gate L asks whether a pilot can read the airplane, horizon and field while flying. The L6c kit and capture harness do not close that owner flight. Gate SC separately evaluates the default-on scenery for readability and performance. Target-machine frame-time evidence remains required; the original 2026-10-05 llvmpipe baseline is historical only.

Research that still informs implementation: [landscape research](research/landscape-research.md), [landscape investigations](research/landscape-investigations/README.md), [tree-resource review](research/tree-resource-review-2026-10-06/README.md), and the [LU-05 collision report](research/landscape-upgrade/LU-05/collision-report.md). Current LU status and remaining gates are owned by the [landscape integration section](LANDSCAPE-PLAN.md#landscape-integration) and [evidence index](research/landscape-upgrade/README.md).
