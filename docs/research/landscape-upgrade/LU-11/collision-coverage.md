# LU-14 — scenery collision coverage extension

Status: implementation installed and focused checks complete; lead review pending, 2026-10-12.

The collision inventory now widens the three field-tree crown proxies from occupied atlas data and replaces the pavilion's generic volume with measured structural parts. Tree trunks, impact response classes, the swept detector, and the collision-session interface are unchanged. The edit stays in [`collision_world.gd`](../../../../app/scenery/collision_world.gd); the new coverage regression is [`test_landscape_collision_coverage.gd`](../../../../app/tests/test_landscape_collision_coverage.gd).

## Field tree crowns

`TreeAssets.card_mesh` builds a card at the catalog's `frame_size_m`. The production treeline shader adjusts for species frame-size ratio and then multiplies the vertex by `Treeline.identity(...).height`; all current catalog entries use `1.125001 m`. The atlas card geometry is therefore `1.125001 × tree height`, before yaw and the bounded wind bend. The tree asset material uses alpha scissor `0.5`, matching the collision measurement threshold.

An image scan of each 512 × 512 species tile finds these largest occupied half-widths at alpha ≥ 0.5:

| Species | Widest occupied row | Topmost occupied row | Atlas half-width / tile | World half-width / tree height |
| --- | ---: | ---: | ---: | ---: |
| CommonTree_1 | 112 | 41 | 0.2294921875 | 0.25817894 |
| CommonTree_3 | 188 | 41 | 0.1708984375 | 0.19226091 |
| Pine_1 | 312 | 30 | 0.2900390625 | 0.32629424 |

The proxy horizontal half-extent is `frame_size_m × tree_height × atlas_half_width + 0.24 m`. The final allowance comes from the renderer's `TREE_WIND_LEAN_M` and is included radially. The proxy is a yaw-oriented square box: the crossed card silhouettes fit inside its inscribed horizontal circle at any yaw, while using the box avoids the vertical pinching that an enlarged capsule would cause at the Pine's low widest row and at the upper occupied rows. The square conservatively fills the empty gaps between card planes and can reach `√2` times its half-extent at a corner. Its vertical range remains the existing `0.32–1.00 × tree height`; the separate 0.18 m hard trunk capsule remains unchanged.

The regression reads the current atlas and catalog at runtime, checks the formula and renderer constants for every species, finds one deterministic field-tree identity per species, and sweeps at the widest occupied row and at the topmost occupied row. Those three selected identities do not exhaust every hash height in the renderer's 12–25 m range; the checked bound scales the measured card width directly by each identity height. It also checks a soft response beyond the former `0.18 × height` radius and a clear path beyond the square's corner radius. These are source-geometry coverage tests, not a leaf mesh or a wind-dynamics model. The source alpha mask and a single bounded lean allowance do not model filtering at every mip level or leaf-level motion.

## Pavilion

`Prefabs._pavilion` uses a ground-center origin and a front veranda toward local `−Z`. The collision inventory now has eleven proxies: the measured slab, wall block, a separate conservative AABB around the pitched main roof, four veranda posts, the thin porch-roof envelope, the built-in bench, and two interrupted top-rail segments. The central step bays stay open. The roof boxes intentionally include some empty space below the slopes; the two separate roof parts avoid turning the open veranda into a solid envelope.

Coverage checks compare proxy dimensions and offsets against the prefab recipe, then sweep through an open 1.2 m porch bay and independently contact a post, low rail, slab, and porch-roof underside. Repeated world builds retain a stable identity, while moving the pavilion changes it. The existing session regression covers mismatched checkpoint refusal and reset retaining the installed world identity.

The staged production builder with default field, default scenery, and high-quality retention produced collision identity `488c101fb9a4cb58cf8a281ca1be1f3e1438046979e1f613df9577e05ea075d9`: 3,877 proxies in 1,039 broadphase bins. Kind counts were 6 aircraft supports, 9 animals, 61 building parts, 56 equipment parts, 261 fence parts, 2 fixtures, 22 lamps, 39 landmarks, 4 parked aircraft, 13 people, 1,701 foliage proxies, 1,690 trunk proxies, and 13 vehicles. The trees include shade-tree parts, while foliage also includes hedges and bushes. The identity is from the normalized high-quality production setup; setup tests confirm repeated builds keep identity and IDs stable. The session test confirms a checkpoint with a different obstacle identity is rejected without mutating simulation state, and reset keeps the installed identity.

## Verification and limits

On Godot 4.7.2, the installed app results are: coverage 54/54, detector 51/51, independent detector oracle 326/326 across 160 differential sweeps, session 25/25, and setup-switch validation 22/22. The old detector fixture began at north 0 m while the synthetic tree was at north 5 m; after the measured canopy expanded, its initial pose overlapped the yaw-oriented square, so it no longer tested an entering hit. The fixture now starts beyond `√2 × crown_half_extent + 1 m` before crossing. Only the fixture path changed; severity and response assertions and runtime initial-overlap behavior are unchanged. The isolated editor parse scan exited successfully; the float64 guard and direct transcendental scan passed, and the guard's injected-call self-test passed under WSL. Per-script raw logs are in [`checks/`](checks/). No timed collision benchmark was repeated for this extension; the previous 100 μs nearby-query target remains open and whole-scene cost should be remeasured with the lead's integration snapshot. These focused checks do not establish structural damage calibration or human flight acceptance.
