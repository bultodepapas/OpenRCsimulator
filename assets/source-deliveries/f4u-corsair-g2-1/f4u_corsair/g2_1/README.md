# F4U Corsair g2.1

Scoped update to accepted g2.0, Naval 308 only. Local author checks completed; simulator integration and external acceptance remain with the OpenRC team. Optional I1 is not completed.

## Deliverables and current figures

- `source/aircraft_game.blend`: authoritative editable Blender 5.2.2 source, frame 0, gear down; six runtime images packed.
- `export/aircraft.glb`: frame 100, gear stowed; **337,664 triangles, 82 nodes, 46 mesh nodes, 57 surfaces, 14 materials, six embedded images, 18,950,912 bytes**.
- Scale 1:4.5; span 2.77777791 m. Main tyre diameter 188.30 mm; tail 77.78 mm. Exact g1.24 wheels include their source tail count of 3,320 triangles.
- `textures/liveries/midnight/`: unchanged Naval 308 albedo and editable 15-layer ORA; ORM green/blue retained, red now carries the original AO.
- `textures/shared/`: unchanged R59 normal map and exact g1 propeller image. `textures/gear/`: unchanged g1 gear atlas. There is no separate AO image.
- `previews/index.html`: Eevee comparisons, two-sided blade views, wheels beside g1.24/g2.0, nose at 1.5 m, three-quarter view, and all eight F4U-18 Godot camera comparisons at 1920×1080.
- `checks/`: team preflight, orientation, shading, independent contract audit, native/GLB verifiers, sampled clearance, motion, R59 deviation, outline checks and portable re-export evidence.

## F1–F4

F1 uses one blade material and linear axial `NavalBladeUV`; the tip boundary and decal locations no longer depend on triangle material assignments. All original blade triangles are retained. F2 imports exact g1.24 wheel datablocks and their atlas while retaining the g2 links. F3 reduces only the hub interior and canopy; budgets are 16,473 and 3,427 triangles respectively. F4 uses the same ORM image and texture descriptor for AO across cockpit, alloy, engine_dark, gear_inner_coat and naval_blade_paint.

All 82 node identities, parents, section tags and transforms are preserved. The independent audit compares all 101 poses against g2.0; down-pose wheel contact delta is 0.000 mm. Airframe UV and paint signatures are unchanged. Source and runtime hashes are recorded in metadata.

## Verification and limits

The team's `f4u-g2` preflight passes without warnings. The fuselage outward share remains 0.8154. The native verifier passes 22/22; independent scoped audit 22/22; sidecar verifier 17/17; Godot GLTFDocument 16/16; negative preflight cases 3/3. The 17 gear carriers match 1,717 samples. Clearance has no surface intersections at the 138 tested control poses; this is sampled collision checking, not continuous collision detection.

Blade geometry is identical. At 4096² raster resolution, hub silhouette overlap exceeds 99.9992% in each principal view; canopy overlap exceeds 99.9986%. Protected contour vertices are unchanged, but the reduced hub's sampled projected envelope has up to 0.123 mm residual difference and the canopy up to 0.0015 mm. Thus a mathematically identical continuous hub outline is **not claimed**; the exact-outline clause remains a small qualification for external review. Reports retain the raw measurements. Canopy deviation against R59 is 0.4478 mm sampled maximum; other airframe skins are unchanged. The local hub surface deviation from g2.0 is at most 0.306 mm in the sampled check.

I1's requested under-10% dihedral criterion is not met: fuselage 23.7%, canopy 13.1%, cowl 22.9%. Reprojection/smoothing trials did not produce a safe complete correction; no optional skin change or rebake was included. The F3 canopy reduction alone lowers its measured share from 26.1% to 13.1%.

The Godot bench is visual evidence, using ten captured frames per view; it is not a controlled performance acceptance run. Production freeze, model compilation, `verify_f4u.gd`, livery suite and production retract/flap/fold checks have not been run or integrated by this author.

## Re-export and audit

From a relocated package, run Blender 5.2.2 with `--background source/aircraft_game.blend --python source/scripts/export_g2.py`. The native source and this one script suffice; R59 is not needed. The script exports frame 100, restores frame 0 in memory and canonicalizes identical glTF texture descriptors. A clean relocated export/import passes: positions, UVs, normals, indices, images and glTF metadata match. A few MikkTSpace tangent components can differ by up to 0.000100017; byte-identical export hashes are not promised.

R59 comparison and derivation scripts require the external accepted master/evidence libraries documented in the script headers. They are audit provenance, not the portable export path. `build_g21.py` likewise records author-side integration; the saved native scene is the authoritative delivery. The previous g1.24, g2.0 and R59 files were not overwritten.

`SHA256SUMS.txt` covers every packaged file except itself. The ZIP has an external SHA-256 file; every ZIP member and CRC is checked after creation.
