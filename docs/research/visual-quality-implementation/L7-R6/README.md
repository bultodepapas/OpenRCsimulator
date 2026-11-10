# L7-R6 Woodland plants with depth

2026-11-09 · Landscape **L**. Continues the vegetation audit's bounded habitat improvement after [root contrast](../L7-R5/README.md). Selected woodland cutouts now use existing downloaded 3D plants, preserving the 220 placement IDs and their original positions/yaw. No asset was modeled or downloaded for this pass.

| Reused source | Mesh instances at High | Placement |
| --- | ---: | --- |
| LOLIPOP Small grass | 14 | Existing tall-grass paths; one upright card remains in each fern pocket |
| Poly Haven Fern 02 A | 2 | First fern path in the east-north and northwest pockets |
| dasy444 leafy shrub | 2 | First flowering-shrub path in east-south and southwest; six flowering cards remain |

The denser Small grass retains visible blade mass and a tapered base in the field. The first Tall-mesh trial was too sparse, even under diagnostic LOD/texture controls, and was rejected. The accepted models keep their source materials, textures, geometry and import settings. Their supplied scales are fitted to the old height and conservative card radius; this is an authored presentation scale, not botanical calibration. Every transformed source-part corner and its ground contact are checked.

Each pocket has its own mesh group for culling. Selection happens before quality filtering, keeping Balanced a stable subset. Low and custom-world inputs skip this decoration before loading its mesh parts. Missing imported parts retain their original cards. `OPENRC_WOODLAND_MESHES=off` restores the all-card rendering and avoids constructing the new mesh groups. This switch affects rendering only; collision data, tree identities, physics and saved settings are unchanged.

## Cost and verification

High uses **202 cards + 18 mesh plants**, **2,656 source triangles** and **13 render batches**. The all-card fallback remains **472 triangles / five batches**. The generated v3 recipe's 472-triangle figure remains provenance for its certified card layout; it is not the mixed renderer's cost. Independently counted complete-scene `other` allocation rises **4,220 → 6,404 / 8,000**, with and without lake context. No allowance or subsystem classification changes. Source [licenses and conversion receipts](../../../../tools/landscape/vegetation/README.md) remain authoritative.

[Machine-readable receipt](shape-review.json) records source identities, checked commands, effective inventories and native image hashes. Godot `4.8.beta2.official.cafc17a19`, native Windows Compatibility/OpenGL, RTX 3090, NVIDIA `617.42`, primary images at **1920×1080**:

- The habitat regression passes **44 headless checks**, and **48 natively** including frame/yaw readback. It independently counts geometry, tests the exact all-card layout, preserves quality subsets/IDs/yaw, checks actual source bounds/ground contact and shadow/collision settings, and exercises unavailable-source fallback. Low/custom input tests confirm no mesh-source loading.
- The complete-scene vegetation consumer passes **38 checks**, including the existing source allowances. Placement generator `--check` and its **six Python tests** pass without regenerating data. Every new mesh has shadow casting disabled.
- **33 matched pairs at 1920×1080** cover the four pockets, eye/overhead/reverse views and field-wide pilot/zoom/aerial controls, plus noon, low sun and night. The fallback matches all **15 pre-change baseline views** exactly, and all six night pairs have identical pixels.
- **192 native orbit frames** compare one fern and one shrub pocket with meshes off/on. Camera poses match per frame. Sampled angles retain visible, grounded grass mass. Loop endpoints differ in eight/nine pixels (maximum channel differences 22/14), so bit-exact temporal parity is not claimed. The MP4 preview is downsampled/lossy; original PNGs remain authoritative.
- Shared renderer edits interrupted the first orbit's source check. That run is excluded. The completed still pairs and the four fresh motion runs have separate source records; the accepted motion input hashes match before/after. Static timing was deferred when the preflight found other Godot work active; no frame-time result is claimed.

Raw frames/logs stay under ignored `tmp/vegetation-shape-20261109/`; no screenshot is added to Git. [Tool commands and controls](../../../../tools/trees/README.md#woodland-mesh-review-l7-r6).

The habitat still mixes detailed plants with stylized cards. These replacements improve selected forms, not the entire forest's appearance or density. Native review does not establish human flight readability, other-GPU behavior, exports or the combined whole-flight frame-time allowance. The historical per-view attribution gate refuses the current 4.8 engine identity; source-allowance checks and local diagnostics do not close that gate. Shared-workspace HEAD advanced during this work; source hashes identify the examined inputs and unrelated edits remain outside this verification.
