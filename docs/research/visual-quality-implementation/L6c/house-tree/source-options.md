# Broadleaf source for the white club building

Checked 2026-10-18. Target: one large, lush, realistic broadleaf beside/behind the white club building; approximately 12–18 m high and 10–18 m wide. Exclude pines. No source is accepted and no runtime change has been made. The original LOLIPOP archive is still pending for local inspection.

## Best remaining candidate: LOLIPOP Maple Trees Pack

[Original Sketchfab listing](https://sketchfab.com/3d-models/maple-trees-pack-lowpoly-game-ready-lods-b5d2833c258f4054a01ee2b4ef85adf0) · [Fab listing/specification](https://www.fab.com/listings/20abd5c9-8e44-430e-91da-a2872bd5d5ad)

The author lists 12 maple variants, large specimens at 17–20 m, supplied LODs and 2K bark/branch PBR maps. The third large variant is listed at 12,987 / 5,541 / 2,825 triangles for LOD0/1/2, plus a 36-triangle billboard; the pack is marked CC BY 4.0. These are published figures, not measurements of the pending archive, and the listing describes the style as low-poly. Inspect the actual crown shape, texture quality, LODs and license files before selection. The original Sketchfab download route is account-gated; no public author-hosted mirror was found. Sketchfab's [Download API guidance](https://sketchfab.com/developers/download-api/guidelines) confirms authenticated access for API downloads.

## Compared sources

| Source | License and route | Inspection / decision |
|---|---|---|
| [Poly Haven Jacaranda](https://polyhaven.com/a/jacaranda_tree) | CC0; direct package downloads | The page describes a 24.2 m wide tree and 312k triangles. Local inspection found 3,863,832 triangles in the 1K glTF and 1,845,603 in complete Blend LOD1; the published count is not representative of those imports. Too heavy. |
| [Innerscene Oak Street Tree](https://www.innerscene.com/tools/library/3d-parts/oak-street-tree-detailed-leaves-a273fef9) | CC0; direct GLB download | Viewer showed 213,372 triangles. Its upward, tiered crown did not read as a broad, lush tree. Reject for both scene fit and geometry cost. |
| [OpenGameArt Old Oak](https://opengameart.org/content/old-oak-tree) | Page offers a direct ZIP; lists GPL-2.0, GPL-3.0 and CC BY-SA 3.0 | Local preview/count: 555 triangles, very large leaves and low-resolution 256 px alpha texture. Reject. Confirm which listed license applies to any individual file before reuse. |
| [OpenGameArt Dim's Arboretum](https://opengameart.org/content/dims-arboretum) | CC BY 3.0; direct ZIP | Inspected candidate tree was 187 triangles and too sparse/low-detail. Reject. |
| [OpenGameArt Foliage_1](https://opengameart.org/content/foliage1) | CC0; direct asset bundles | Inspected preview has cartoon-like blob crowns, so it fails the realistic foliage requirement despite the modest published pack size. Reject. |
| [evolveduk Beech](https://sketchfab.com/3d-models/beech-tree-0983d8933531491f9be71c669e8a907b) | CC BY; Sketchfab listing, no independent download mirror verified | Listed at 6.6k triangles. Preview is narrow/open rather than broad/lush; scale and texture details are absent. Reject. |
| [Tree It official package](https://www.evolved-software.com/treeit/treeit) · [direct ZIP](https://www.evolved-software.com/treeit/TreeIt-7-5-2026.zip) | Direct official ZIP; sample license says “Creative Commons Attribution International” without version | Partial ZIP directory inspection (357.7 MB total; only a 523,466-byte range fetched, no executable run) found 47 `.tre` project samples and no `.obj`, `.fbx` or `.glb` exports. This is a tree-making tool/sample library, not a ready-to-import asset. The sample readme/license language also needs clarification before distributing derived sample media. Not a suitable fallback while downloadable tree assets are preferred. |

Previously considered alternatives are also unsuitable: the existing Lauris71 oak is only 5,303 triangles and does not meet the desired realism; the LOLIPOP-era beech sample, where inspected, has an open crown; and low-poly generator packs do not meet the request to use an existing realistic downloadable asset.

## Next gate

Inspect the user-provided LOLIPOP archive when it arrives. Record its hash, exact per-LOD triangle counts, source dimensions, materials/maps and applicable attribution, then check the selected crown in the club-building views. Do not implement a replacement or change the scenery budget until that candidate passes those checks. If it fails, continue looking for an existing downloadable asset rather than generating a new tree.
