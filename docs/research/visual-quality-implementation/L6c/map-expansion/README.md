# Downloaded vegetation expansion — L6c

Implemented 2026-10-18. Reuses the user's downloaded maple, grass and forest packs. No plant geometry was modeled or decimated. Download originals remain in Downloads; retained source copies, conversion receipts and runtime attribution are in the vegetation pipeline.

## Changes

| Placement | Result |
|---|---|
| White club | Original 14 m maple retained; four smaller broadleaf saplings remain behind the club. |
| Farm edge | Two maples at N/E (555, 295) and (580, 280), about 10.01 / 10.21 m tall, 29.15 m apart. |
| Southwest forest gap | Maple at (−480, −770), about 11.52 m tall. |
| Club, meadow, farm margins | 60 downloaded grass tufts in five unequal elliptical clusters, heights 0.22–0.65 m. |
| Understory accents | Four downloaded leafy shrubs, heights 0.65–0.95 m. |

There are still 17 imported tree placements and eight placed tree forms. Three former CommonTree_1 saplings are replaced by the landscape maples, saving 2,172 tree triangles. The new small plants add 1,986 triangles. With changed contact shadows, full scenery is **648,448 / 650,000 triangles**, 240 fewer than the previous club-only maple scene. The ceiling is unchanged. Habitat batches grow from 11 to 14; small-plant instances grow from 221 to 285.

The scenery generator owns tree coordinates and stable group IDs. Shared render/collision dimensions retain uniform scaling and crown offsets. Moving trees changes the collision-world identity and some compacted sapling row identities; previous flight recordings are not exact replays of this world. Habitat seeds use a separate 200000+ range, preserving existing flowers/crops/shore plants. Ground sampling, path/foundation/runway exclusions and quality subsets are reused.

## Downloads inspected and selected

- LOLIPOP maple: existing supplied `Acer_large_3_LOD1`, 5,541 triangles per instance. [Original intake](../house-tree/README.md).
- [LOLIPOP Grass pack](https://sketchfab.com/3d-models/grass-pack-lowpoly-game-ready-422f42f618d342c6958b02613dc57403), CC BY 4.0: small fresh tuft, 26 triangles; tall low tuft, 20. The licensed glTF ZIP is SHA-256 `304b2ea5c62f6dc635dc5d895534d5bd3812d58e25815d43fcd5ff7783a65fe4`. Original texture pixels/UVs are retained; authored BLEND is adapted to double-sided MASK at 0.5.
- [dasy444 forest scene](https://sketchfab.com/3d-models/a-forest-3-with-a-road-at-night-for-game-61f8c7817fe6457fb26e4814cfc48a3f), CC BY 4.0: one leafy shrub, 144 triangles, source BLEND/double-sided material and 2K RGBA atlas retained. [Exact source IDs, hashes and audit](forest-intake.md). The night road and conifers were not imported.

Duplicate FBX/glTF/GLB/USDZ deliveries were inspected as alternatives rather than installed repeatedly. The library now contains 24 assets from seven sources. Runtime notices `LICENSE_MAPLE.txt`, `LICENSE_GRASS.txt` and `LICENSE_FOREST.txt` are covered by the existing export presets.

## Native review and filtering

Godot 4.7.2, Compatibility/OpenGL 3.3, RTX 3090, 1280 × 720. [Farm trees](candidate/farm_maples.png), [southwest tree](candidate/forest_maple.png), [club understory](candidate/club_understory.png), [meadow tufts](candidate/meadow_tufts.png), [farm understory](candidate/farm_understory.png), [forest shrub](candidate/forest_shrub.png), [club overview](candidate/postcard_club.png). [Counters](candidate/views.json), [capture log](capture.log).

New grass/shrub maps use VRAM compression and mipmaps. The maple retains compressed bark/normal/ORM mipmaps, but its leaf color/alpha atlas is now **unmipped**: averaging alpha made the smaller farm/forest crowns dissolve at distance. [Mipped comparison](comparison/farm-maples-mipped.png) and [retained coverage](candidate/farm_maples.png) record that decision. Source alpha cutoff/pixels are unchanged; fine-leaf shimmer remains a tradeoff. This supersedes the six-mipped-map policy in the earlier club-only evidence. Maples retain static source PBR materials because the current wind adapter does not support their full feature set.

Spatial tree cells were compared at 0 and 128 m. They helped some views but increased the club overview from 170 to 178 draw calls and from 312,297 to 318,549 reported primitives. The default remains 0; no universal performance improvement is claimed. [Comparison counters](comparison/cells.json) retain both samples. Frame pacing in these fixed views is not a flight benchmark or cross-GPU guarantee.

## Reproduction and checks

```powershell
python tools/landscape/vegetation/convert_grass_pack.py --check
python tools/landscape/vegetation/convert_forest_shrub.py --check
python tools/landscape/vegetation/build_library.py --check
python tools/scenery/place.py --check
python tools/trees/place_woodland_edges.py --check
& ./.tools/Godot_v4.7.2-stable_win64.exe --headless --path app --editor --import
& ./.tools/Godot_v4.7.2-stable_win64.exe --path app --rendering-driver opengl3 --resolution 1280x720 --script "$PWD/docs/research/visual-quality-implementation/L6c/map-expansion/capture_expansion.gd" -- "--out=$PWD/tmp/map-expansion-review"
```

The converters are CPU-only and reproduce selected supplied geometry/maps. Grass also passed independent scratch-output byte comparison. Five Python suites, nine focused Godot suites, native material checks and the scene-build check pass; [results and logs](verification/results.json) retain outcomes. Coverage includes deterministic layout, geometry ceilings, placement clearances, collisions and destruction. Full aircraft/physics validation and export packaging were not rerun.

The final [scene-build check](verification/scenery-build.log) passed at 638.5 ms, with warm builds of 204.4 / 204.3 ms. The 800 ms threshold is unchanged; prior runs on this machine exceeded it, so this sample does not establish a universal startup guarantee. The capture's full world construction and this scenery-only test measure different scopes.
