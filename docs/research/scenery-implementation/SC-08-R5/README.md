# SC-08-R5 — Open pit shelter roof and structure

2026-10-20. The default field has two **open RC pit shelters**, sometimes called open hangars in the site copy. This pass keeps their 28 m by 5 m footprint, 18-post layout, furniture, collision proxies, and damage identity while refining their visible construction.

## Source and construction

The roofing uses the freely downloaded [Poly Haven Corrugated Iron 02](https://polyhaven.com/a/corrugated_iron_02) 2K color, OpenGL normal, and packed AO/roughness/metallic maps. Poly Haven publishes it under [CC0](https://polyhaven.com/license); exact files and hashes are in [`app/assets/landscape/pit-shelter/LICENSE.md`](../../../../app/assets/landscape/pit-shelter/LICENSE.md). The wood reuses the project's [ambientCG Wood049](https://ambientcg.com/view?id=Wood049) maps, with no duplicate texture files.

The former flat roof sheet and square imitation ribs are replaced by continuous folded sheet profiles with 0.75 m standing-seam spacing. A separate underside finish, three lengthwise purlins, existing fascia, gutter, barge boards, and pitched rafters provide visible depth and a plausible load path. The rafters now bear on the front and rear rails below the sheet. Posts use vertical grain; rails, braces, rafters, purlins, and fascia use grain along their length. Each post has a raised steel standoff, two 8 mm side plates, and visible flush fasteners at the concrete slab.

One shader material covers each complete shelter mesh: roof and structural-timber vertex tags select PBR maps; furniture and other surfaces keep their original vertex colors. Each shelter stays one surface and one damage range. The two shelter meshes add one visible draw call per photographed shelter view, while all ordinary props remain in their existing spatial cell batches.

## Native visual evidence

Godot 4.7.2 Compatibility on RTX 3090, 1280 × 720 with 4× MSAA. The fixed script is [`tools/ground/capture_pit_shelter.gd`](../../../../tools/ground/capture_pit_shelter.gd). The [before](before/capture.json) and [accepted](accepted/capture.json) manifests include camera positions, image hashes, rendering method, and draw counts. Visual comparison is for the shelter only: concurrent work changed some distant airfield detail between captures, so the build times are not an isolated benchmark.

| View | Before | Accepted |
| --- | --- | --- |
| Field front | [image](before/front.png) | [image](accepted/front.png) |
| Roof | [image](before/roof.png) | [image](accepted/roof.png) |
| Underside | [image](before/underside.png) | [image](accepted/underside.png) |
| Eave connection | — | [close view](accepted/eave_detail.png) |
| Post foot | — | [same image as the R6 close view](../SC-08-R6/accepted/post_foot.png) |
| End | [image](before/end.png) | [image](accepted/end.png) |
| Context | [image](before/context.png) | [image](accepted/context.png) |

The front/roof/underside/end/context views each show **one additional draw call** (one visible shelter material surface). The roof and underside no longer read as flat vertex-colored sheets. The shelter remains open and its proportions are unchanged.

## Checks and limits

- `test_landscape_architecture.gd`: passes. A shelter is 4,992 triangles versus 4,422 before this pass, +570 per shelter. The pavilion plus two shelters' structural additions total 4,132 against the revised 4,300-triangle allowance. The complete prefab remains within its recorded bounds, and roof/timber marker coverage is checked.
- `test_landscape_collision.gd`: 51 checks, 0 failures.
- `test_landscape_collision_support.gd`: 0 failures; the slab/support contract is unchanged.
- `test_scenery_destruction.gd`: 78 checks, 0 failures.
- `test_scenery_build.gd`: the new one-surface, PBR, and damage-range checks pass. The latest full scene is 723,213 triangles against a 725,000 limit. Its cold build-time check still fails at 1,279.9 ms against 800 ms; warm builds measured 715.0 and 253.6 ms. The pre-change capture also recorded a 1,202.95 ms cold build in the concurrently changing tree. The cold-time gate remains open and should be investigated against a stable scene baseline rather than increased solely for this roof pass.

These captures demonstrate rendered appearance and integration, not structural engineering or target-device frame-time acceptance. Gate SC still requires the owner review described in [the scenery plan](../../../SCENERY-PLAN.md).
