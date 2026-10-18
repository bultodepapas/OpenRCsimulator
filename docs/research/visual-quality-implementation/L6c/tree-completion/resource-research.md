# Woodland ground texture intake

2026-10-18. Intake for the woodland-edge vegetation continuation. This compares two downloadable, CC0 forest-floor textures for a restrained ground layer beneath the shrub and fern groups. Forest Leaves 02 was subsequently adopted; Forest Leaves 04 remains a temporary review input. The [implementation and qualification](vegetation-refinement/README.md) record the final disposition.

## Existing constraints

At intake, the L6c scene had 1,680 field trees (480 near coordinates and 1,200 far cards in twelve irregular patches). The source-scene triangle ceiling is 650,000, with 81 triangles remaining after the retained oak and four woodland margins. These assets are opaque floor photographs, not canopy atlases or transparent shrub sprites. The adopted texture uses 32 additional triangles for four small terrain-sampled overlays, leaving 49 triangles below the ceiling.

The far-card tree atlas and seven retained close-tree forms come from Quaternius's Stylized Nature MegaKit Standard archive under CC0. The eighth close form, `oak_tree`, comes from lauris71's OpenGameArt Oak Tree under CC BY-SA 3.0 and has 5,303 triangles. The existing intake and license evidence lives in [L6a-R1](../../L6a-R1/README.md), [mature oak](../../L6a-R1/mature-oak/README.md), and the source [provenance manifest](../../../../../assets/landscape/PROVENANCE.json). This makes a ground texture a complementary change that avoids adding another tree family or changing the source budget.

## Candidates

| Asset | Fit | Poly Haven page and license | Exact 1K diffuse download | Bytes | SHA-256 | API MD5 |
| --- | --- | --- | ---: | ---: | --- | --- |
| **Forest Leaves 02** | Moss, green ground and mixed leaf litter; best match for green woodland margins. API physical tile: 3.00097 × 3.00098 m. | [Asset page](https://polyhaven.com/a/forest_leaves_02); author Rob Tuytel; [API dimensions](https://api.polyhaven.com/info/forest_leaves_02); [Poly Haven CC0 terms](https://polyhaven.com/license). | [forest_leaves_02_diffuse_1k.jpg](https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/forest_leaves_02/forest_leaves_02_diffuse_1k.jpg) | 437,891 | `2BAC85CDC76927FA7DC311037BBBC4DFA2633EA56EB0A24C9CABE163A68C9AA5` | `13e9bfac07cb72ca143e153cc2f589a8` |
| **Forest Leaves 04** | Dry brown leaves, twigs and dirt; a drier or autumnal alternative. API physical tile: 1.50000 × 1.50000 m. | [Asset page](https://polyhaven.com/a/forest_leaves_04); author Rob Tuytel; [API dimensions](https://api.polyhaven.com/info/forest_leaves_04); [Poly Haven CC0 terms](https://polyhaven.com/license). | [forest_leaves_04_diff_1k.jpg](https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/forest_leaves_04/forest_leaves_04_diff_1k.jpg) | 423,500 | `A898E6EF0668A40FAAF1BCBC6B024F6EF437EC424A10FA47AA6D35D013C9DADE` | `4ab1368d2d0d7fee652caa5f71f706bf` |

Both asset pages identify the maps as 1K diffuse and link CC0. Poly Haven's license page states that all hosted assets are CC0 and permits use, redistribution and commercial use without required attribution. The API records the exact download URLs, byte sizes and MD5 values: [Forest Leaves 02 files](https://api.polyhaven.com/files/forest_leaves_02) and [Forest Leaves 04 files](https://api.polyhaven.com/files/forest_leaves_04). SHA-256 values above were computed from the downloaded files.

The retained review files are:

- `tmp/vegetation-refinement-intake/forest_leaves_02_diffuse_1k.jpg`
- `tmp/vegetation-refinement-intake/forest_leaves_04_diff_1k.jpg`

## Recommendation

Use Forest Leaves 02 for four bounded 4 × 4 m leaf-litter patches beneath the shrub groups. The implementation rounds the API-verified 3.00097 × 3.00098 m physical tile to 3 m and uses a localized, softly irregular alpha blend into the grass. Forest Leaves 04 remains an alternate if the field palette calls for visibly drier litter.

The source maps are square 1K JPGs under 0.5 MB each. The accepted original JPG, download hash, license and physical scale are retained in `app/assets/landscape/vegetation/woodland/`. Godot imports the selected map at 512² with opaque mipmaps; native readback measures 1,048,575 decoded bytes. This is texture data size, not total GPU residency.
