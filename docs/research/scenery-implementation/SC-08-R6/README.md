# SC-08-R6 — Pit shelter construction finish and load cost

2026-10-20. This continues [SC-08-R5](../SC-08-R5/README.md) on the same two open RC pit shelters. The earlier roof and timber finish remains; this pass corrects the remaining construction details and measures the material's cold-load cost.

## Construction changes

- Both post rows now carry knee braces into their longitudinal rails. Their lean reverses at the shelter centre, avoiding the previous one-way pattern across the 28 m elevation.
- The low roof edge has a shallow open steel gutter with end caps. Two 90 mm bottom apertures feed round, strapped downpipes at the back corner posts. Each discharge shoe reaches past the concrete slab edge.
- Folded rake caps cover the long ends of the sheet; a front drip lip closes the high eave above the timber fascia. The roof, framing, drainage, slab and furniture still form **one damage-aware mesh surface per shelter**.

The prefab is 5,390 triangles, 398 more than R5. It remains inside its previously recorded mesh bounds. The pavilion and two shelters together add 4,928 structural triangles against the revised 5,000 allowance; the complete current scene is 724,009 against the 725,000-triangle ceiling.

## Material load finding

The R5 source maps are unchanged. Their Godot import presets now use **VRAM Compressed** with mipmaps, a standard 3D texture mode supported by the [Godot image import guide](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html). The three imported roof maps shrink from 19.45 MB to 8.39 MB in total. In a fresh-process probe, their combined `load()` time fell from about **266 ms** to **4–5 ms**. Close native roof and eave captures were compared before accepting the compressed version; corrugation, weathering and seam readability remain intact at these view scales. The original downloaded maps and SHA-256 provenance remain in [the asset license record](../../../../app/assets/landscape/pit-shelter/LICENSE.md). The repeatable probe is [`tools/ground/bench_pit_shelter_load.gd`](../../../../tools/ground/bench_pit_shelter_load.gd).

The build now reports `cell_meshes`, `shelter_material`, and `shelter_meshes` spans inside the existing `build_ms` timer. Three final fresh-process runs spent **37–68 ms** loading the shelter material and **2.0–2.3 ms** creating both shelter meshes. Total cold builds varied from **824.5 to 1,112.5 ms** on this busy shared workstation and still exceed the existing 800 ms gate. The gate was not raised. These samples are diagnostic, not a controlled performance acceptance run; concurrent field and other track changes are active.

## Native evidence and checks

The [accepted capture manifest](accepted/capture.json) records nine fixed Godot 4.7.2 Compatibility views on RTX 3090 at 1280 × 720 and 4× MSAA:

| Construction | Capture |
| --- | --- |
| Balanced elevation bracing | [front](accepted/front.png) |
| Folded sheet and rake caps | [roof](accepted/roof.png), [end](accepted/end.png) |
| Roof structure | [underside](accepted/underside.png), [eave connection](accepted/eave_detail.png) |
| Open gutter and strapped downpipe | [gutter](accepted/gutter_detail.png), [downpipe](accepted/downpipe.png) |
| Post standoff and field context | [post foot](accepted/post_foot.png), [context](accepted/context.png) |

`test_landscape_architecture.gd` passes with deterministic geometry and recorded bounds. `test_landscape_collision.gd` passes 51 checks, `test_landscape_collision_support.gd` passes, and `test_scenery_destruction.gd` passes 78 checks. `test_scenery_build.gd` passes its shelter material, batching, damage-range and triangle checks; only its cold build-time check fails. Gate SC target-device frame-time and owner readability acceptance remain open in [the scenery plan](../../../SCENERY-PLAN.md).
