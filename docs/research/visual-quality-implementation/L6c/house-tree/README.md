# Club broadleaf tree intake — L6c

Status: research and baseline captured; replacement is **not implemented or qualified**.
Checked 2026-10-18. The user confirmed the white club pavilion near the pilot, not the distant farm. See [source comparison](source-options.md).

## Placement and candidate

The pavilion is at N -22 m, E 0 m. Prefer replacing the existing oak at N -32 m, E 10.5 m (`prop:shade-trees:06`, seed 793949324) beside its rear corner. Start with a 14 m uniform target height; accept final position and rotation only after checking the downloaded canopy, parked cars, roof clearance and trunk contact in native views. Do not stretch the crown or generate a tree. Pines are excluded from this replacement.

The preferred source is [LOLIPOP's Maple Trees Pack](https://sketchfab.com/3d-models/maple-trees-pack-lowpoly-game-ready-lods-b5d2833c258f4054a01ee2b4ef85adf0), pending the original archive. The author lists large trees at 17–20 m and a third large variant at 12,987 / 5,541 / 2,825 triangles for LOD0/1/2, plus 2K PBR bark and branch maps. Published counts are not import measurements. Inspect its crown before accepting the third variant: efficient geometry alone is insufficient.

Sketchfab download authentication is required; no connected browser was available. The user has been asked to save the original ZIP under `tmp/house-tree-intake`.

The downloaded [Poly Haven Jacaranda 1K source](https://dl.polyhaven.org/file/ph-assets/Models/blend/1k/jacaranda_tree/jacaranda_tree_1k.blend) was rejected after inspection: complete LOD0 is 3,863,832 triangles and LOD1 is 1,845,603. The glTF descriptor independently matches LOD0; the website's published 312,356 count is not the complete exported mesh. Original BLEND: 180,228,496 bytes, MD5 `1b827c7c364c6ebb2cbbff0f02b52a15`. The [inspection](jacaranda-inspection.json) and [Blender inspection script](inspect_jacaranda.py) retain the evidence. To reproduce, put the linked BLEND at `tmp/house-tree-intake/source/jacaranda_tree_1k.blend`, then run the script from the repository root with Blender 5.2.2 in background mode and `--disable-autoexec`.

## Remaining implementation gates

1. Pin the original archive/hash, author, precise license and dependencies; retain an export attribution notice. Inspect geometry, source dimensions, UVs, maps and supplied LODs.
2. Convert only the selected supplied mesh and its materials through a reproducible source pipeline. Preserve source shape. Review leaf alpha, double-sided normals, bark normal/roughness and mip coverage in Compatibility rendering.
3. Integrate the one tree through imported vegetation. Keep render placement and coarse collision dimensions consistent; identify any changed world identity. Regenerate affected scenery/woodland data through its generators.
4. Reuse Godot imported LODs and cached materials. Keep a static source-material fallback if the wind adapter cannot preserve PBR channels. Measure alpha overdraw, shadows and draw calls rather than assuming a low triangle count proves performance.
5. Compare pilot, pavilion, club overview, side and close views. Run affected import, scenery, collision, deterministic-generator and budget checks. The existing oak is 5,303 source triangles; the listed 5,541-triangle maple would add 238, subject to verification. Do not raise the scenery budget silently.

## Native baseline

Godot 4.7.2, Compatibility/OpenGL 3.3, NVIDIA RTX 3090, 1280 x 720. No runtime edits were made for this intake.

- [Club overview](baseline-postcard_club.png)
- [Pavilion from the pilot line](baseline-postcard_pavilion.png)
- [Pilot looking south](baseline-pilot_south.png)
- [Counters](baseline-views.json) and [engine log](baseline-capture.log)

The baseline capture completed with exit 0 and no script error. The existing oak emits the known unsupported-BLEND wind warning. This single startup capture is not a frame-time benchmark or a performance pass; no candidate A/B measurement exists yet.
