# Visual quality: implementation guide and open work

2026-10-12 · Revision 2 · Step prefix: **VQ-**

**Status:** VQ-01a/b and VQ-04a are delivered. VQ-02/03/04b/05/06/07 remain open; L6c owner readability review and Gates L/2 remain independent acceptance points.

**Owns:** visual-quality coordination and its VQ steps. Landscape implementation lives in [LANDSCAPE-PLAN](LANDSCAPE-PLAN.md); field composition and time of day live in [FIELD-WORLD-PLAN](FIELD-WORLD-PLAN.md) and [TIME-OF-DAY-PLAN](TIME-OF-DAY-PLAN.md). Aircraft appearance stays with each model team.

## Current implementation

The app uses Godot 4.7.2 with the Compatibility renderer. A validated field and shared builder serve Home and flight. The visual capture harness records case, renderer, backend and frame-time context; llvmpipe results establish repeatability, not target-GPU performance. See [VQ-01a](research/visual-quality-implementation/VQ-01a/README.md), [VQ-01b](research/visual-quality-implementation/VQ-01b/README.md), and the landscape implementation evidence.

VQ-04a derives an opaque projected silhouette from each aircraft's visible mesh and model datum, then places a soft receiver on the flat ground. Field silhouettes cover the fence, pilot station, windsock, nearby scenery and people. Isolated 256² mask viewports avoid changing Compatibility shadow blending or aircraft paint; the legacy mask remains an empty-model fallback. The implementation caps field masks at 16 maps and 8,388,608 pixels; default optional scenery uses 10 maps and 4,784,128 pixels. The all-aircraft and field evidence includes native captures, an independent GPU projection oracle, lifecycle checks, a frame-time budget and unchanged flight samples: [VQ-04a evidence](research/visual-quality-implementation/VQ-04a/README.md). A separate shadow-map comparison is still optional.

## Open work

| ID | Work | Status and proof |
| --- | --- | --- |
| VQ-02 | Improve one aircraft material at a time with matched lighting and distances. Coordinate with model owners. | Open; use 20/50/100 m and close views; previews are not flight validation. |
| VQ-03 | Optional horizon-aware camera composition experiment. | Open; reject it if tracking delay or readability worsens. |
| VQ-04b | Compare native shadow maps with the projected silhouette. | Open and optional; keep the existing projection if colour, contact or cost regresses. |
| VQ-05 | Derive propeller blur from live RPM and the existing auxiliary source. | Open; pause, crash, reset and captures must agree without changing traces. |
| VQ-06a/b | Apply renderer quality settings and expose saved presets through the menu. | Open with the UI-22…24 theme/display/Settings work; include repeated apply, invalid settings, restore and frame-time evidence. |
| VQ-07 | Compare Forward+ in an isolated build. | Open; no renderer migration or Ultra preset until colour, shaders, export and recovery are measured. |

## Evidence and acceptance

The 2026-10-05 visual baseline used 1280×720 and llvmpipe; it predates Home and is not a current performance baseline. Keep the empty atmosphere fixture separate from full-field views. The original capture protocol and limits remain in [VQ-01a](research/visual-quality-implementation/VQ-01a/README.md) and [VQ-01b](research/visual-quality-implementation/VQ-01b/README.md). For tree readability, use the [L6c evidence and blinded kit](research/visual-quality-implementation/L6c/README.md); the owner's score is still pending.

Keep cockpit/pilot information, scale, contrast and horizon legible before adding expensive effects. Do not present a model preview, synthetic fixture, software meter or headless render as owner flight or target-hardware acceptance. Gate L remains in [LANDSCAPE-PLAN](LANDSCAPE-PLAN.md); Gate 2 remains in [ROADMAP](../ROADMAP.md).

Research and asset provenance remain in [visual-quality implementation](research/visual-quality-implementation/), [tree resource review](research/tree-resource-review-2026-10-06/README.md), and [landscape investigations](research/landscape-investigations/README.md).
