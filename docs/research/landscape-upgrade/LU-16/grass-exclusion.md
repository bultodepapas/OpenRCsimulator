# LU-18 — scenery-aware near-grass exclusions

Status: staged in `.tools/lu16-stage/app`; headless integration verified. [Owning plan](../../../plans/landscape-upgrade.md).

The field builder attaches eligible normalized scenery before building near grass. Scenery supplies rotated building, pit-slab, and gravel footprints; `NearGrass` omits clump centers inside them and within a 0.4 m edge clearance. Scenery-off and spatially ineligible fields receive no exclusions. This only filters visual grass placement; it does not change terrain or collision geometry.

From `.tools/lu16-stage/app`, Godot 4.7.2 `--headless --path . --script res://tests/test_landscape_scenery_grass_mask.gd` passed **33 checks, 0 failures**. The default field retained 4,794 clumps with scenery off and 4,488 with scenery enabled, removing 306 centers under or near footprints. A translated ineligible field kept 285 clump centers in the old pavilion footprint, confirming that no default-layout mask leaked into it. The test also checks the actual `NearGrass` instance counts against its clipped placement list.
