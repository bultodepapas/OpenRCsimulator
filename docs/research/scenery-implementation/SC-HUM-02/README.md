# SC-HUM-02 — One mesh, one material per person pose

Status: **implemented and software-verified, 2026-10-24.** Owner: Scenery and field life. Plan: [field people plan](../../../plans/field-people.md). Toolchain and reproduction: [SC-HUM-00](../SC-HUM-00/README.md).

## Why

The scene budget's pilot view at High measured 350 of 360 draws, and the population subsystem 49 draws ([VQ-06b](../../visual-quality-implementation/VQ-06b-scene-detail/README.md)). Each LU-21 pose had 6–7 mesh parts, and each part was its own MultiMesh draw: 19 draw surfaces for 13 people. More character variety would multiply that.

## What changed

| Item | Before (LU-21) | After |
| --- | --- | --- |
| People draw surfaces (default field, High) | 19 | **3** |
| People triangles, all instances at LOD0 | 96,415 | 96,415 |
| Mesh parts / materials per pose | 6–7 / 6–7 | 1 / 1 |
| Human textures | 7 separate images (4×1024², 512², 2×256²), lossless, **no mipmaps** | 2112² diffuse atlas + 1056² normal atlas, shared by all poses, **VRAM-compressed with mipmaps** |

Pipeline: `generate_people.py` (unchanged) → new [merge_people_atlas.py](../../../../tools/scenery/population/merge_people_atlas.py) → `package_population.py` (unchanged). The merge keeps every vertex position, normal, UV and index, and remaps UVs into the atlas. The atlas uses guillotine packing with 16 px edge-extended gutters, so mipmaps do not bleed between parts. The normal atlas is flat outside the clothing. A second UV set carries the shading class (skin, fabric, plain, eyes, flat transmitter) and the roughness. With them, one material reproduces the old per-part shading: shirt tint on fabric, skin tone on skin, roughness per part. Every atlas reserves the transmitter's swatch, so all three poses share one diffuse atlas file by hash. PNGs are written directly with zlib, so the output is deterministic.

Runtime: [population.gd](../../../../app/scenery/population.gd) marks the `Human.atlas` material as merged. `head_rig()` now works per vertex, finding the eyes by name (separate parts) or by UV2 class (merged). [population_person.gdshader](../../../../app/scenery/population_person.gdshader) reads the class and roughness from UV2. Old separate-part poses still work.

Manifests: [RUNTIME_MANIFEST.json](../../../../assets/scenery/population/RUNTIME_MANIFEST.json) changes only the human entries; car entries are untouched. [HUMAN_SOURCES.json](../../../../assets/scenery/population/HUMAN_SOURCES.json) gains `sc_hum_02_merged_runtime`, listing the pipeline, the merged export hashes and the retired textures.

## Verification

| Check | Result |
| --- | --- |
| Head rig, separate vs merged | Pivot and eye height agree within 0.06 mm |
| `test_field_people_gaze` (class-aware head mask: eyes rigid, shoes and transmitter fixed, ≤6 % clothing, skin below the band fixed; shader-mirror signs) | PASS on both the old parts and the merged poses, headless and native |
| `test_landscape_population_assets` (headless and native under Xvfb), `test_field_population_collection` 54/0, `test_landscape_population`, `test_scenery_build`, `test_field_projected_shadows` 59/0 | All pass |
| `capture_population_assets` (native, llvmpipe) | 5/15/40/120 m views; motion changes; paused = held, reset = wrap = start for all three poses |
| Before/after render of the same head-pose scene at 1920×1080 | Mean absolute difference 0.65–0.96 levels; 0.28–0.47 % of pixels differ by more than 24 levels (mipmaps and texture compression). Slight block compression is visible on the shirt logo at 2 m |
| Import | First reimport reports stale UIDs of the removed textures; a second import is clean |

The work was staged and tested in a disposable full copy of `app/` before being applied to the tree in one step. The copy was deleted afterwards.

## Limits

- Scene-budget totals per view were not re-measured with `budget.sh`; the 16 fewer draw surfaces are a structural count.
- VRAM block compression softens fine texture edges at very close range; the logo shirts are replaced in SC-HUM-07.
- The project transmitter is still the primitive box until the owner's models arrive (SC-HUM-01).
