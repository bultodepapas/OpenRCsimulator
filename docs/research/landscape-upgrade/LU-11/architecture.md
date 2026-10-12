# Pavilion and shelter architecture details

Status: implementation and bounds verification complete; matched native image review remains with LU-14. Evidence date: 2026-10-12.

The LU-07 daylight views show the pavilion's broad, plain facade and roof edge, and the two pit shelters' exposed sheet ends ([pavilion](../LU-07/day/postcard_pavilion.png), [club](../LU-07/day/postcard_club.png)). Their existing prefab meshes are original vertex-coloured geometry emitted through [`MeshKit`](../../../../app/scenery/mesh_kit.gd) and the shared [`Palette`](../../../../app/scenery/palette.gd). The static prefabs are appended to their existing cell mesh; the renderer makes one surface per cell.

LU-12 adds pavilion window transoms, shallow door panels with hinge plates, a concrete entry threshold, subtle porch pour joints, roof eave boards, veranda fascia and side caps, and two rear rain leaders. Each shelter gets sloped roof-end caps, gutter returns and four fine slab joints. All details use the current palette and stay within the measured source AABBs. They add no material, texture, scene node, animation, light, collision proxy, or new draw surface. No external asset was added; the geometry remains original project content under the [MIT license](../../../../LICENSE). Window detail is non-emissive; AirfieldLighting retains the lighting interface.

The baseline was commit `8b2020f`, prefab blob `b6e4a28c9b7c8a6f73a2095066d76c07025d808a`. Using seed 1234, the baseline pavilion had 816 triangles and the shelter 1,830. The updated meshes have 1,206 and 1,918 triangles, respectively: +390 for the pavilion and +88 per shelter, or +566 for the default layout of one pavilion and two shelters, below LU-12's 3,000-triangle cap.

| Prefab | Baseline AABB min → max (m) | Updated AABB min → max (m) |
| --- | --- | --- |
| Pavilion | `(-5, 0, -6.2) → (5, 4.65, 3.5)` | unchanged |
| Pit shelter | `(-14.3175, 0, -2.901742) → (14.5317, 3.477413, 3.01)` | unchanged |

These observed bounds are asymmetric, especially the pavilion's front veranda. The test checks min and max per axis instead of assuming that the AABB is centred at the prefab origin.

The focused [`test_landscape_architecture.gd`](../../../../app/tests/test_landscape_architecture.gd) passes on Godot 4.7.2 with the production project path. It verifies the measured bounds, repeat-build determinism, no moving parts, one batched surface per prefab, and the default-layout triangle cap. The same source and test passed in an isolated draft before installation, including a Godot editor scan. Native before/after image review and scene-level performance remain in the lead-owned LU-14 integration run; this report makes no visual or timing acceptance claim.
