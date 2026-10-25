# Independent g2.1 acceptance audit

**Verdict:** PASS — 22/22 checks.

Read-only comparison of g2.1 against g2.0 and g1.24.

## Checks

- PASS — native g2.1 opens at frame 0
- PASS — candidate has 82 EXPORT_aircraft nodes
- PASS — all 82 node names preserved
- PASS — parents/tags/types preserved
- PASS — frame 0 and 100 matrices preserved within 1e-5
- PASS — all 101 world-matrix poses preserved within 1e-5
- PASS — all unaffected mesh geometry and UV signatures unchanged
- PASS — all three wheel mesh and UV signatures exact g1.24
- PASS — wheel radii and axle widths match g1.24 within 0.01 mm
- PASS — wheel matrices and ground contacts preserved within 0.01 mm
- PASS — three blades share naval_blade_paint and blade_tip is removed
- PASS — blade paint regions align with world axes 90 plus 120 degrees per blade
- PASS — blade paint explicitly uses NavalBladeUV second UV layer
- PASS — axial U mapping is linear from root to 0.9 at 0.42 m
- PASS — native blade image and shipped PNG bytes equal g1.24
- PASS — GLB has no blade_tip material
- PASS — GLB blade base color uses explicit TEXCOORD_1
- PASS — native AO inputs use the paint ORM red channel for all five materials
- PASS — GLB occlusion uses the same paint ORM texture index for all five required materials
- PASS — no standalone AO image in native file or GLB
- PASS — no stale standalone AO sidecar remains in the package
- PASS — GLB material count does not exceed 16

## Wheel contact deltas

- gear_wheel_left: 0.0 mm vs g2.0; 0.0 mm vs g1.24.
- gear_wheel_right: 0.0 mm vs g2.0; 0.0 mm vs g1.24.
- gear_wheel_tail: 0.0 mm vs g2.0; 0.0 mm vs g1.24.

## First issue

None.
