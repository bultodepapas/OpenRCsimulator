# Visual quality: implementation guide and open work

2026-10-14 · Revision 17 · Step prefix: **VQ-**

Latest VQ-01c / DT-11a follow-up: [horizon construction](research/visual-quality-implementation/VQ-01c/loading/horizon-build/README.md) preserves vertices, normals, indices and bounds in 40 native pairs while reducing construction median about 20%. All 94 focused headless assertions pass. The native combined horizon/atmosphere test has texture shutdown errors reproduced on the reference; no teardown fix is adopted. [Earlier shadow blur](research/visual-quality-implementation/VQ-01c/loading/shadow-blur/README.md) retains separate evidence. Appearance, full-loading non-regression and native acceptance remain open.

[Audio teardown diagnostics](research/visual-quality-implementation/VQ-01c/loading/audio/README.md) now separate mixer retirement from persistent retention. The loading probe checks bounded cleanup on success/failure; packaged 50-cycle diagnostics finish without exit warnings but include one paused first draw. This does not close the native lifecycle/soak gates.

**Status:** VQ-01a/b, VQ-04a and VQ-05 are delivered. VQ-02/03/04b/06/07 remain open; L6c owner readability review and Gates L/2 remain independent acceptance points.

**Owns:** visual-quality coordination and its VQ steps. Landscape implementation lives in [LANDSCAPE-PLAN](LANDSCAPE-PLAN.md); field composition and time of day live in [FIELD-WORLD-PLAN](FIELD-WORLD-PLAN.md) and [TIME-OF-DAY-PLAN](TIME-OF-DAY-PLAN.md). Aircraft appearance stays with each model team.

The [global implementation sequence](plans/global-performance-visual-quality.md#3-order-dependencies-and-reviewable-deliveries) selects the current performance/visual delivery and resolves its research ideas. VQ-01c measurement tools and the read-only VQ-02a inventory foundation are implemented; their acceptance gaps remain below. VQ-07 and additional postprocessing remain outside that delivery.

The [advanced graphics plan](plans/advanced-graphics.md), added 2026-10-21, owns the proposed VQ-07a…h comparison steps and conditional High-profile decision. Its [source audit](research/advanced-graphics-2026-10-21/README.md) preserves the supplied research and independent checks. It does not expand the current Compatibility delivery or change the parent-step status below.

## Current implementation

The app uses Godot 4.7.2 with the Compatibility renderer. A validated field and shared builder serve Home and flight. The visual capture harness records case, renderer, backend and frame-time context; llvmpipe results establish repeatability, not target-GPU performance. See [VQ-01a](research/visual-quality-implementation/VQ-01a/README.md), [VQ-01b](research/visual-quality-implementation/VQ-01b/README.md), and the landscape implementation evidence.

VQ-04a derives an opaque projected silhouette from each aircraft's visible mesh and model datum, then places a soft receiver on the flat ground. Field silhouettes cover the fence, pilot station, windsock, nearby scenery and people. Isolated 256² mask viewports avoid changing Compatibility shadow blending or aircraft paint; the legacy mask remains an empty-model fallback. The implementation caps field masks at 16 maps and 8,388,608 pixels; default optional scenery uses 10 maps and 4,784,128 pixels. The all-aircraft and field evidence includes native captures, an independent GPU projection oracle, lifecycle checks, a frame-time budget and unchanged flight samples: [VQ-04a evidence](research/visual-quality-implementation/VQ-04a/README.md). A separate shadow-map comparison is still optional.

VQ-05 blurs every propeller from the live rotor speed. `app/render/propeller_blur.gd` measures the aircraft's own propeller meshes: the share of a revolution the blades cover at each radius (blade triangles rasterized in polar space), the blade colour along the radius, the blade count and the opaque hub (the Timber's spinner, backplate and bell share one mesh with its blades). It cross-fades by blade-passing frequency, 12 Hz to 48 Hz (perceptual estimates around flicker fusion), between the model's blades and a vertex-alpha disc lit like any other surface, so an idling glow engine shows a translucent disc while an electric motor spinning down shows its blades reappear. The node sits beside the model in the flight scene, follows the propeller each frame and only shows or hides the model's blade nodes: a stopped rotor renders byte-identically to the previous build, and the Home preview, projected silhouette and crash wreck duplicate are unchanged. Opacity is the measured time-averaged occlusion (gain 1.0, an art control). Evidence, probes and limits: [VQ-05](research/visual-quality-implementation/VQ-05/README.md).

VQ-04a-F2 adds a moving windsock silhouette in one 512² map, sharing the visible sleeve deformation and basket yaw. Pause and negligible calm settling retain the cached mask; light-strength changes update opacity. [Sources, captures and verification](research/visual-quality-implementation/VQ-04a/windsock/README.md) distinguish component evidence from full-session and hardware gates.

## Open work

| ID | Work | Status and proof |
| --- | --- | --- |
| VQ-01c | Freeze current full-session, loading and native-render baseline with DT-01/10a; extend only missing measurement coverage. | In progress: [measurement foundation and Windows evidence](research/visual-quality-implementation/VQ-01c/README.md). 18 CPU runs / nine matching observer pairs; native pacing campaign fails. [Lake reuse/bake](research/visual-quality-implementation/VQ-01c/loading/README.md) and [exact grain precomputation/package repairs](research/visual-quality-implementation/VQ-01c/loading/grain/README.md) have evidence. Cold/first-Fly budgets, full flight coverage, observer-cost uncertainty and native/package qualification remain open. |
| VQ-01d | Extend L6c/CAM visibility evidence with matched motion, projected size and orientation results. | [Moving-reference foundation](research/visual-quality-implementation/VQ-01d/README.md): four native lossless clips / 240 frames on the frozen VQ-02a source, existing pilot autozoom on/off, projected geometry and camera metadata. Full matrix, background qualification, owner orientation and controlled response-time results remain open. No camera-law or HUD change. |
| VQ-02 | Improve one aircraft material at a time with matched lighting and distances. Coordinate with model owners. | Open; use 20/50/100 m and close views; previews are not flight validation. |
| VQ-02a | Inventory imports and correct demonstrated channel/color/filter errors before material comparisons. | [Expanded read-only inventory](research/visual-quality-implementation/VQ-02a/README.md): frozen source has 100 texture sidecars and 25 inspected embedded images; native default-day/five-family probe records 39 assigned texture resources. Pixel/provenance qualification, conditional runtime coverage and two probe teardown warnings remain open. Corrections remain gated by VQ-01c/d; no production asset/import change. |
| VQ-02b | One affected aircraft's marking/skin or specular repair. | Conditional on VQ-01d/VQ-02a evidence; preserve geometry and default appearance unless the paired result supports a change. |
| VQ-03 | Optional horizon-aware camera composition experiment. | Open; reject it if tracking delay or readability worsens. |
| VQ-04b | Compare native shadow maps with the projected silhouette. | Open and optional; keep the existing projection if colour, contact or cost regresses. |
| VQ-06a/b | Apply renderer quality settings and expose saved presets through the menu. | Open with the UI-22…24 theme/display/Settings work; include repeated apply, invalid settings, restore and frame-time evidence. |
| VQ-06c | Integrate the selected changes and qualify the exact packaged visual/performance slice with DT/L/FW/CAM. | Planned after selected probe outcomes and qualified settings; does not close unavailable native/pilot gates or the whole DT program. |
| VQ-07 | Compare Forward+ in an isolated build; [VQ-07a…h execution plan](plans/advanced-graphics.md#4-vq-07-isolated-renderer-comparison). | Open; no renderer migration or Ultra preset until colour, shaders, export and recovery are measured. |

## Evidence and acceptance

The 2026-10-05 visual baseline used 1280×720 and llvmpipe; it predates Home and is not a current performance baseline. Keep the empty atmosphere fixture separate from full-field views. The original capture protocol and limits remain in [VQ-01a](research/visual-quality-implementation/VQ-01a/README.md) and [VQ-01b](research/visual-quality-implementation/VQ-01b/README.md). For tree readability, use the [L6c evidence and blinded kit](research/visual-quality-implementation/L6c/README.md); the owner's score is still pending.

Keep cockpit/pilot information, scale, contrast and horizon legible before adding expensive effects. Do not present a model preview, synthetic fixture, software meter or headless render as owner flight or target-hardware acceptance. Gate L remains in [LANDSCAPE-PLAN](LANDSCAPE-PLAN.md); Gate 2 remains in [ROADMAP](../ROADMAP.md).

Research and asset provenance remain in [visual-quality implementation](research/visual-quality-implementation/), [tree resource review](research/tree-resource-review-2026-10-06/README.md), and [landscape investigations](research/landscape-investigations/README.md).
