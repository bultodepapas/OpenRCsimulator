# L10d: Flight-cue contact shadows

Status: renderer and structural checks verified against the L10c default cue; rendered ablation checks passed; human Gate L remains open.

These footprints help the windsock, pilot station and flightline barrier sit against the flat ground. They are a visual scale cue, not projected sunlight or physical ambient occlusion. Their radii, spread and opacity are artistic estimates.

| Cue | Geometry | Fade |
| --- | --- | --- |
| Windsock | Ground ellipse, 0.23 m radius, centered at the mast base | 12 segments; inner opacity 0.18, middle ring 0.10, outer ring 0 |
| Pilot station | Rectangle matching its field-data pad; feather extends 0.14 m beyond each edge | Core sits under the opaque pad; two perimeter rings fade 0.18 → 0.10 → 0 |
| Flightline barrier | Ground discs, 0.14 m radius at every centre from the barrier's `post_positions` helper | 12 segments; inner opacity 0.18, middle ring 0.10, outer ring 0 |

The vertices sit at y = 0.012 m to clear the validated flat ground. One unshaded `StandardMaterial3D` reads vertex color alpha, blends with depth testing, and disables face culling. It has no texture. The mesh casts no shadows and has no collider, processing callback, or wind response. A field with cues adds one mesh surface and one draw; a field without cues gets an empty mesh that the field builder omits.

Each circular footprint uses 60 triangles; the station uses 18. The default barrier has 20 posts, so the current default mesh uses 1,278 triangles (`60 + 18 + 20 × 60`), under the 1,500-triangle limit. Vertex colors store opacity in normalized 8-bit steps: 0.18 is stored as 45/255 (about 0.176), and 0.10 as 25/255 (about 0.098).

The focused test reads the generated vertex and color arrays for placement, finite ground coordinates, alpha bounds and fade-to-zero, material state, deterministic independent builds, and the triangle budget. Command: `godot --headless --path app --script res://tests/test_flight_cue_shadows.gd` (20 checks, 0 failed in a clean snapshot with the L10c default field and helper). This proves the mesh contract, not whether the cue reads naturally at pilot eye height; the rendered review is recorded in [L10d evidence](README.md).

Dimensions and placement follow the validated [default field cues](../../../../app/data/fields/default.json) and [barrier geometry helper](../../../../app/render/flightline_barrier.gd). The footprint sizes and alpha values are estimates, not field measurements or safety standards.
