# Aircraft and field projected shadows

2026-10-11 · Revision 2 · Step prefix **VQ-04a**, scoped from
[VISUAL-QUALITY-PLAN](VISUAL-QUALITY-PLAN.md).

**Status: delivered and locally validated, 2026-10-11.** Hardware/pilot acceptance limits remain explicit below.

Owns `app/render/projected_shadow*`, the binding extension in `render/shadow.gd`,
`render/field_projected_shadows.gd`, both projected-shadow tests, `tools/shadows/`, and
[VQ-04a evidence](research/visual-quality-implementation/VQ-04a/README.md).
Shared integration is one binding call in `main.gd` and `ui/home_scene.gd`, before
the existing world night-light dressing, plus attach/lighting hooks in `field.gd`.
The field/UI integration tests and `capture_ui.gd` distinguish isolated mask
cameras from the one gameplay camera and environment. Aircraft models, lighting, field data,
menus and simulation behavior retain their existing owners.

| ID | Delivery | Proof | Status |
| --- | --- | --- | --- |
| VQ-04a | Derive each aircraft's projected silhouette from its visible neutral mesh; use its actual model datum and attitude; soften with height | All four aircraft, native before/after captures, independent GPU projection oracle, lifecycle tests, frame-time budget and unchanged flight samples | Delivered (2026-10-11) |
| VQ-04a-F1 | Extend the same technique to fence, pilot station, windsock and nearby scenery, including pilot figures | Native field pairs; visibility, lighting, fallback and allocation regressions; static-scene frame-time budget | Delivered (2026-10-11) |

The implementation uses one merged opaque silhouette in a 256² isolated viewport
and one soft alpha receiver on the flat ground. This avoids changing Compatibility
light/shadow blending or aircraft paint. The legacy mask remains an empty-model
fallback and its public transform API remains stable. No backend migration is
needed. VQ-04b native shadow-map evaluation remains separate.

Field masks use 256–1024² targets, no MSAA, a 16-map and 8,388,608-pixel cap,
and cached draws until lighting changes. Default optional scenery uses 10 maps
and 4,784,128 pixels. Far batches and unsupported/rejected casters retain their
legacy shadows. Scenery stays opt-in; no scenery-owned source is edited.

The retained evidence defines acceptance and distinguishes local engineering
proof from pilot acceptance. Neutral control geometry, omitted rotating blades,
flat receivers and limited mask resolution are explicit limits; there is no
claim of terrain occlusion, aircraft self-shadowing or full optical simulation.
