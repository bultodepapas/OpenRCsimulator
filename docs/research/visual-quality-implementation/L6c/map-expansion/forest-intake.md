# Forest shrub intake (L6c)

Reviewed 2026-10-18. This intake retains one useful understory shrub from a licensed forest pack; it does not adopt the night-road scene or its pine-heavy tree set.

## Source and license

The selected source is [“a forest (3) with a road at night for game” by dasy444](https://sketchfab.com/3d-models/a-forest-3-with-a-road-at-night-for-game-61f8c7817fe6457fb26e4814cfc48a3f), licensed CC BY 4.0. The downloaded glTF archive contains the original `license.txt`; the source folder also carries the project attribution in `LICENSE_FOREST.txt`. Preserve that notice with redistributed builds. The duplicate 71 MB FBX archive did not include a license notice and is not used.

The retained source archive is `assets/landscape/vegetation/source/dasy_forest_2026/archive/a_forest_3_with_a_road_at_night_for_game.zip` (20,951,847 bytes, SHA-256 `7a6716d6e691838324e8270ec9c22b5f7793609342db579861626c3c8975bea3`). The converter pins hashes for the archive, extracted original files, and project attribution notice. The upstream source and its dependencies remain unchanged.

## Selected mesh

The selected mesh is `meshes[210]`, `3f84aea6648aa6cc5af5f07ee43c6056-no-bg-preview (carve.photos).003_Material_0`, on node 424. It has 96 vertices, 144 triangles and one material. Its 2048×2048 RGBA base-color map has an alpha channel; the supplied material is double-sided, `BLEND`, metallic 0 and roughness 0.82111456. The source material, alpha mode and image pixels are preserved.

`tools/landscape/vegetation/convert_forest_shrub.py` accumulates the original node chain, removes only the gallery translation, bakes the remaining uniform linear basis into positions and normals, and retains the mesh-local origin. It does not create, decimate, recenter or ground geometry. The standalone glTF bounds are 1.034859 m wide × 0.815313 m high × 0.952688 m deep. Because some source vertices extend 0.128152 m below the authored origin, placement integration must account for that source bound rather than silently moving the mesh.

The converted mesh and unchanged texture are under `assets/landscape/vegetation/derived/dasy_forest_2026/`. `conversion_manifest.json` records the source URL, license, selected source IDs, transform and bounds, geometry counts, source input hashes, and derived output hashes. One instance costs 144 source triangles; four instances cost 576 before importer or shadow-mesh costs.

## Verification and limits

Run `python tools/landscape/vegetation/convert_forest_shrub.py --check` to verify the pinned inputs and reproduce the manifest's deterministic output hashes. This verifies the offline extraction only. Native Godot material appearance, alpha sorting, instance placement and shadow cost remain part of the parent map-expansion review; no scene-wide forest import or new pine selection is included here.
