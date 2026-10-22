# LU-33 — building roof finish

**Date:** 2026-10-20. **Target:** Godot 4.7.2 Compatibility, default Club field. This step addresses the formerly flat, broad pavilion and veranda roofs visible from the flightline and extends the finish to the shed, barns, farmhouses, village houses and church.

## Construction

- [Poly Haven Roof Slates 03](https://polyhaven.com/a/roof_slates_03) covers the pavilion hip roof, church and selected houses. [Clay Roof Tiles](https://polyhaven.com/a/clay_roof_tiles) covers farmhouses and the remaining village houses. Both are CC0. The veranda, shed and barns reuse the existing Corrugated Iron 02 maps. [Runtime source and hashes](../../../../app/assets/landscape/building-roofs/LICENSES.md).
- Each existing roof keeps its structure, soffit and trim. A fitted opaque skin sits 18 mm above its upper face. Explicit UVs follow the eave and downhill slope, with 3 m slate, 4 m clay and 2.7 m metal repeats. The four hip planes and four gambrel planes each use their own slope mapping. Color, OpenGL normal and ambient-occlusion/roughness/metal maps are sampled with mipmaps and anisotropic filtering. The slate and clay maps only received mipmaps in [VQ-02a-R1](../../visual-quality-implementation/VQ-02a/roof-mipmaps/README.md); this step's captures predate that import fix. A roughness floor suppresses implausible glare in the pilot view.
- The pavilion has slim capped hip/ridge joints and raised veranda sheet seams. The shed's existing seams sit above the new surface. Roof skins share their source building's damage id and disappear/reappear with it. Original cell meshes and the pit-shelter PBR material stay in their existing batches.

## Native visual and cost evidence

The [capture script](../../../../tools/landscape/capture_building_roofs.gd) renders the field from flightline, aerial, shed and farm cameras without altering simulation state. [Before](before/) and [accepted](accepted/) contain matched PNGs and SHA-256/draw-call records (`capture.json`). The closest matched views are [pavilion before](before/pavilion_roof.png) and [after](accepted/pavilion_roof.png), [pilot before](before/pavilion_pilot.png) and [after](accepted/pavilion_pilot.png), and [shed before](before/shed_roof.png) and [after](accepted/shed_roof.png). The accepted capture uses the `2f812615` field, scenery loader and layout snapshot with the final roof source so simultaneous parked-aircraft authoring cannot change the comparison. A separate [current-field capture](production/) verifies the roof appearance with the new parked fleet; its draw counts are not compared to the older field. The capture script refuses to record an empty scenery field.

| 1280×720 view | Before draws | Accepted draws |
| --- | ---: | ---: |
| Club aerial | 147 | 149 |
| Pavilion pilot | 148 | 158 |
| Pavilion roof | 131 | 133 |
| Shed roof | 65 | 73 |
| Farm roofs | 37 | 41 |

The 2026-10-20 native capture used an RTX 3090 with OpenGL Compatibility. The scene is still batched into 60 ordinary cells and two separate pit-shelter surfaces. The scenery build test reports **724,961 triangles**, within its **725,000** cap. The pre-roof snapshot at `100c4fcd`, loaded against the same current dependencies, measured **724,657 triangles**, so this change adds **304** triangles.

The scenery test verifies one mapped PBR surface per roof, valid UV counts, source texture assignment, and roof hide/restore when its building is broken. The independent [roof geometry check](../../../../tools/landscape/check_building_roofs.gd) also verifies map availability, finite UVs, face winding and all six building forms; it passed with 7 sample surfaces and 32 triangles. All functional checks and the triangle gate pass. Its fixed **800 ms cold-build gate** fails on this machine: the pre-roof snapshot measured **902.5 ms**, two roof-era samples measured **843.2/861.9 ms**, and the current field with the new fleet measured **929.0 ms**. The current field reports **993,709 total triangles**, of which **724,961** are non-fleet scenery; the test gates the latter against 725,000. The existing cold-time gate remains open; these measurements do not support a claim of a performance improvement or regression from this change alone.

The native captures establish the fitted roof appearance on this renderer. The isolated matched recapture logged an unrelated woodland placement JSON error while parked-aircraft authoring was in progress; the main scenery and all five roof images rendered, and their hashes were verified. The current-field capture also rendered all five views and verified their hashes, but Godot logged null-texture errors from the new parked-aircraft resources. Those fleet materials are outside LU-33 and require their owning track's follow-up. Lower-end GPU frame cost and independent visual review remain open.
