# LU-33 — building roof finish

**Date:** 2026-10-20. **Target:** Godot 4.7.2 Compatibility, default Club field. This step addresses the formerly flat, broad pavilion and veranda roofs visible from the flightline and extends the finish to the shed, barns, farmhouses, village houses and church.

## Construction

- [Poly Haven Roof Slates 03](https://polyhaven.com/a/roof_slates_03) covers the pavilion hip roof, church and selected houses. [Clay Roof Tiles](https://polyhaven.com/a/clay_roof_tiles) covers farmhouses and the remaining village houses. Both are CC0. The veranda, shed and barns reuse the existing Corrugated Iron 02 maps. [Runtime source and hashes](../../../../app/assets/landscape/building-roofs/LICENSES.md).
- Each existing roof keeps its structure, soffit and trim. A fitted opaque skin sits 18 mm above its upper face. Explicit UVs follow the eave and downhill slope, with 3 m slate, 4 m clay and 2.7 m metal repeats. The four hip planes and four gambrel planes each use their own slope mapping. Color, OpenGL normal and ambient-occlusion/roughness/metal maps are sampled with mipmaps and anisotropic filtering. A roughness floor suppresses implausible glare in the pilot view.
- The pavilion has slim capped hip/ridge joints and raised veranda sheet seams. The shed's existing seams sit above the new surface. Roof skins share their source building's damage id and disappear/reappear with it. Original cell meshes and the pit-shelter PBR material stay in their existing batches.

## Native visual and cost evidence

The [capture script](../../../../tools/landscape/capture_building_roofs.gd) renders the production field from flightline, aerial, shed and farm cameras without altering simulation state. [Before](before/) and [accepted](accepted/) contain PNGs and SHA-256/draw-call records (`capture.json`). The closest matched views are [pavilion before](before/pavilion_roof.png) and [after](accepted/pavilion_roof.png), [pilot before](before/pavilion_pilot.png) and [after](accepted/pavilion_pilot.png), and [shed before](before/shed_roof.png) and [after](accepted/shed_roof.png).

| 1280×720 view | Before draws | Accepted draws |
| --- | ---: | ---: |
| Club aerial | 147 | 150 |
| Pavilion pilot | 148 | 159 |
| Pavilion roof | 131 | 134 |
| Shed roof | 65 | 74 |
| Farm roofs | 37 | 41 |

The 2026-10-20 native capture used an RTX 3090 with OpenGL Compatibility. The scene is still batched into 60 ordinary cells and two separate pit-shelter surfaces. The scenery build test reports **724,961 triangles**, within its **725,000** cap. The pre-roof snapshot at `100c4fcd`, loaded against the same current dependencies, measured **724,657 triangles**, so this change adds **304** triangles.

The scenery test verifies one mapped PBR surface per roof, valid UV counts, source texture assignment, and roof hide/restore when its building is broken. All functional checks and the triangle gate pass. Its fixed **800 ms cold-build gate** fails on this machine: the pre-roof snapshot measured **902.5 ms**, and two current samples measured **843.2/861.9 ms**. Warm scene builds in the current test measured **349.7/177.6 ms**. The existing cold-time gate therefore remains open; these measurements do not support a claim of a performance improvement or regression from this change alone.

The native captures establish the installed visual result on this renderer. Lower-end GPU frame cost and independent visual review remain open.
