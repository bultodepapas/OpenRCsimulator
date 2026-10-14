# Landscape plan: current field and open work

2026-10-14 · Revision 3 · Step prefix: **L**

**Status:** the daytime field, treeline and visual cues are implemented. The separate LU-00…27 landscape integration is also delivered; its remaining cost and acceptance gates are summarized below. L9 ground review, L6c owner readability review, terrain work and wind integration remain open. Static tree and scenery contacts are gameplay estimates, not physical calibration. Gate L remains open.

**Owns:** field data, landscape rendering and tools listed in the [track registry](README.md#tracks-plans-and-step-ids). Field-world composition is coordinated in [FIELD-WORLD-PLAN](FIELD-WORLD-PLAN.md); selectable time is owned by [TIME-OF-DAY-PLAN](TIME-OF-DAY-PLAN.md). Scenery assets remain in [SCENERY-PLAN](SCENERY-PLAN.md).

## Current implementation

- L0–L7 provide the capture baseline, fixed-sun sky/haze/clouds, shared field builder, treeline cards and far landscape. L6 uses validated CC0 source packages and a small runtime atlas; detailed source meshes remain authoring inputs.
- L9 has filtered turf and field surfaces. L9e is engineering-verified; L9b's visual review and L9c's perceived stripe shimmer still need acceptance. Near grass is a separate opaque layer with no collision.
- L10 cues include the windsock, pilot station and flightline barrier, with soft contact grounding. L11a near grass is implemented. L11b reuses SC-16/17 flora through the scenery layer; it does not duplicate assets.
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

## Landscape integration

LU-00…27 adds licensed field assets, night lighting, imported vegetation and a finite lake. Use compatible existing distributable assets where available; record source, license and conversion steps. The [LU evidence index](research/landscape-upgrade/README.md) links the dated implementation and verification records.

| Remaining gate | Current status | Evidence |
| --- | --- | --- |
| Nearby scenery-query cost | The 100 µs target remains open; measured costs and the accepted bounds are recorded in the latest native reports. | [LU-21](research/landscape-upgrade/LU-21/README.md), [LU-22](research/landscape-upgrade/LU-22/README.md) |
| Pilot readability and lower-end hardware | Independent owner review and target-machine evidence remain open under Gate L and the scenery/world gates. | [L gates](#gates-and-evidence), [scenery guide](SCENERY-PLAN.md), [field-world guide](FIELD-WORLD-PLAN.md) |
| Lake impact and buoyancy | Current land aircraft stop on water entry; the sinking effect is visual. Water response and impact parameters are not physically validated. | [LU-22](research/landscape-upgrade/LU-22/README.md) |

L8 (near 3D tree models), L9d (photo grass), L16–18 (photo sky, owner's field and Terrain3D), and L20 (sky-grid aid) are optional and start only if a gate justifies them. L19's time-of-day work is owned by [TIME-OF-DAY-PLAN](TIME-OF-DAY-PLAN.md).

## Gates and evidence

Gate L asks whether a pilot can read the airplane, horizon and field while flying. The L6c kit and capture harness do not close that owner flight. Gate SC separately evaluates the default-on scenery for readability and performance. Target-machine frame-time evidence remains required; the original 2026-10-05 llvmpipe baseline is historical only.

Research that still informs implementation: [landscape research](research/landscape-research.md), [landscape investigations](research/landscape-investigations/README.md), [tree-resource review](research/tree-resource-review-2026-10-06/README.md), and the [LU-05 collision report](research/landscape-upgrade/LU-05/collision-report.md). Current LU status and remaining gates are owned by the [landscape integration section](LANDSCAPE-PLAN.md#landscape-integration) and [evidence index](research/landscape-upgrade/README.md).
