# L9d: RC ground material implementation

2026-10-15. Godot 4.7.2 official, Windows, Compatibility, NVIDIA GeForce RTX 3090. The [audit](../rc-ground-closeup-2026-10-15/README.md) identified the procedural dirt lattice, mismatched shoulders and scratch-like turf. The [active plan](../../plans/rc-ground-closeup.md) retains remaining qualification gates.

## Implemented behavior

RC sessions bind downloaded CC0 **Poly Haven Dirt** and **ambientCG Grass001**, each using 2K albedo, OpenGL normal and roughness maps. Dirt repeats at the supplier's 2 m scale; short grass at approximately 1.4 m. Translation-only decorrelation uses identical offsets and explicit gradients for each map. Imported mipmaps and anisotropic sampling suppress unresolved detail; fine normals and the new grass detail fade with projected footprint and distance.

The track duplicates the field's actual ground material. Coverage stays in vertex alpha as metadata, and the opaque shoulder converges to the same turf color/normal/lighting as the adjacent ground. The track retains its sampled physical normals and does not add the field micro-relief normal twice. Dry soil uses a weak dielectric reflection with the downloaded roughness. The underlying mesh and contact sampler are unchanged.

The [material binder](../../../app/render/rc_ground_material.gd) opts in only during RC scene construction. The shared ground shader's default remains off for Home and aircraft. Existing runway masks, stripes, cloud/haze lighting and distant palette remain authoritative. The phototexture's color variation is normalized around its mean to preserve the field palette. No new grass meshes, collision objects, terrain displacement, grip changes, camera tuning or renderer migration were introduced.

Source intake/reproduction: [asset README](../../../assets/landscape/rc-ground/README.md), [source hashes](../../../assets/landscape/rc-ground/manifest.json), [packaged manifest](../../../app/assets/landscape/rc-ground/manifest.json), [CC0 notice](../../../app/assets/landscape/rc-ground/LICENSES.txt). The six original 4K maps are research inputs outside `app/`; only 2K textures are assigned in production. Sparse Grass was rejected because its brown soil and roots did not suit a maintained runway.

## Visual evidence

The final 720p static matrix covers both vehicles, runway start, dirt start and rollers, in chase and low orbit: **12 paired cases**. All pairs retain exact serialized physical state, model/course/solver identities and mesh geometry. Native logs contain no shader errors. See [baseline receipt](verification/ground-closeup-final3-baseline-720/manifest.json) and [candidate receipt](verification/ground-closeup-final3-candidate-720/manifest.json); these are production-scene views, with physics paused for matching.

| View | Before | After |
| --- | --- | --- |
| Dirt, Bisonte chase | [baseline](verification/ground-closeup-final3-baseline-720/mt8-bisonte__track_start__chase__day.png) | [candidate](verification/ground-closeup-final3-candidate-720/mt8-bisonte__track_start__chase__day.png) |
| Runway turf, Bisonte chase | [baseline](verification/ground-closeup-final3-baseline-720/mt8-bisonte__start__chase__day.png) | [candidate](verification/ground-closeup-final3-candidate-720/mt8-bisonte__start__chase__day.png) |
| Dirt, low orbit | [baseline](verification/ground-closeup-final3-baseline-720/mt8-bisonte__track_rollers__low-orbit__day.png) | [candidate](verification/ground-closeup-final3-candidate-720/mt8-bisonte__track_rollers__low-orbit__day.png) |
| Nitro vehicle, chase | [baseline](verification/ground-closeup-final3-baseline-720/monster-car-2__track_start__chase__day.png) | [candidate](verification/ground-closeup-final3-candidate-720/monster-car-2__track_start__chase__day.png) |

The dirt now has small stones and irregular soil structure instead of large lattice patches. The near runway has short-grass texture instead of bright procedural strokes. Outer shoulders match the field rather than a separate green palette band. Static views alone do not qualify temporal aliasing or low-end hardware.

## Excluded verification runs

Initial inal, smoke-baseline and first timing outputs do not establish a valid grass baseline: the harness set a per-surface override while the field instance retained a higher-priority material override. The corrected harness updates the effective material and verifies parameter readback with a hard failure on mismatch. The switch-check PNG hashes differ and the final3 pair uses the corrected harness. Final2 is excluded because a shader comment changed its source hash between paired runs. None of those earlier timings is used as performance evidence.

## Color-space repair found during integration

The first native candidate exposed severely clipped turf despite successful parsing and geometry tests. Dividing Compatibility's encoded color sample by a linear-RGB source mean amplified almost every channel. The corrected shader selects the measured encoded mean when `OUTPUT_IS_SRGB` is true and the linear mean otherwise. Both measured means are retained in the include; no source image was repainted. The [corrected isolated view](verification/color-fix-trial/mt8-bisonte__start__chase__day.png) and final pairs demonstrate the repaired result.

This follows the actual renderer contract, rather than assuming `source_color` implies the same internal sample representation everywhere. Godot documents the [optional Compatibility hint](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html#using-source-color) and [OUTPUT_IS_SRGB](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html#global-built-ins). Forward+/Mobile are not qualified by these Windows captures.

## Software checks and limits

[Check receipts](checks/results.json) record a successful import and eight passing suites: new RC material bindings/mesh invariance (24 assertions), track view (11), physical track (19), grass image cache, ground terrain, near grass, Bisonte activity and Nitro activity. The new material test verifies exact vertex/normal/color/index buffers, private material copies, preserved coverage metadata, absence of new collision objects, all six 2K bindings and imported mipmaps. The offline asset integrity checker also passes.

Commands for the actual-scene visual harness are in [its README](../../../research/rc-monster-truck/ground-closeup/README.md). Source and texture hashes accompany the captures. This is a shared working tree with unrelated concurrent changes, not a clean-release qualification. Target lower-end hardware, independent owner playtest and full Home/flight release qualification remain separate gates.
