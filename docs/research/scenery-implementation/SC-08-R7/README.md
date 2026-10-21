# SC-08-R7 — Pit shelter slab and frame joints

2026-10-20. This continues the two open RC pit shelters in [SC-08-R6](../SC-08-R6/README.md). The native close views showed a plain slab beneath a detailed roof and timber frame, plus unconnected-looking timber intersections at the eave.

## Changes

- The slab top samples the already installed [ambientCG Concrete034 CC0 set](../../../../app/assets/landscape/pilot-station/PROVENANCE.json): albedo, normal and roughness at the source's 1.1 × 0.55 m tile size. The low 0.32 normal strength keeps the floor level at viewing distance. Its edge and saw cuts retain their separate concrete colours.
- Rafters are 140 mm square instead of 100 mm across the 5 m roof depth. Each of the 18 frame seats per shelter has a thin steel plate and two visible fasteners; a small strapped fastener marks each brace-to-rail connection.
- Both knee-brace leans now use their own lengthwise grain projection rather than an X-only projection. The frame, roof, slab, drainage and furniture still use **one independent damage-aware surface per shelter**.

The two shelters add 648 triangles over R6. The prefab is 5,714 triangles, within its recorded bounds; the pavilion and both shelters add 5,576 structural triangles against the revised 5,600 allowance. The complete current scene is 724,657 triangles against its 725,000 ceiling. The shared shader samples the concrete only on the tagged slab top, with no extra material or draw surface. No new asset was created or downloaded.

## Native evidence and checks

The [accepted capture manifest](accepted/capture.json) records nine fixed Godot 4.7.2 Compatibility views on RTX 3090 at 1280 × 720 and 4× MSAA. Compare the R6 and R7 [post-foot close views](accepted/post_foot.png) for concrete and the [eave](accepted/eave_detail.png) and [underside](accepted/underside.png) for frame sections, steel connections and brace grain. The [roof](accepted/roof.png) and [context](accepted/context.png) show that the standing-seam silhouette and field scale remain intact.

The [intermediate capture](candidate/capture.json) records the slab material before the timber-joint work, isolating its visual contribution in [post foot](candidate/post_foot.png) and [context](candidate/context.png).

`test_landscape_architecture.gd` passes deterministic geometry, material tags and bounds. `test_landscape_collision.gd` passes 51 checks, `test_landscape_collision_support.gd` passes, and `test_scenery_destruction.gd` passes 78 checks. `test_scenery_build.gd` passes the one-surface/material/damage and triangle checks; its pre-existing 800 ms cold-build gate still fails (1,234.1 ms in this run). The native capture reported 1,637.1 ms in a separate, concurrently busy run, so these timings are diagnostics rather than a controlled comparison. The gate remains open; no threshold was raised. Gate SC target-device frame-time and owner readability acceptance remain open in the [scenery plan](../../../SCENERY-PLAN.md).

## Subsequent pavilion roof completion (v0.1.7 release check)

After this R7 capture, commit `2f812615` added five hip caps and veranda roof
seams; `147be977` reduced the seam count from 18 to 12. The current pavilion is
3,836 triangles and extends to X ±5.03209 m, Y 4.7375 m, Z 3.531777 m. These
details add 204 triangles to the R7 structure reference. The architecture check
now bounds the actual roof and allows 5,800 structural triangles for the pavilion
and two shelters; the measured total is 5,780. The separate 725,000 non-fleet
field limit remains unchanged and measures 724,884 in the v0.1.7 check.
