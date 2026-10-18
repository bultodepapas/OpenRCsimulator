# OpenGameArt Oak listing and source audit

## Listing and license

The [OpenGameArt Oak tree listing](https://opengameart.org/content/oak-tree) credits **lauris71** and says the model is from the Khayyam/Shinya game project. It lists both CC BY-SA 3.0 and GPL 3.0. This intake selects [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/legalcode); retain the attribution and share-alike notice in the canonical [LICENSE_OAK.txt](../../../../../../assets/landscape/vegetation/source/opengameart_oak_tree_lod_2026/LICENSE_OAK.txt).

The listing provides the [original ZIP](https://opengameart.org/sites/default/files/quercus_A_packed_v1_0.zip), downloaded without an account on 2026-10-18. The retained archive is `assets/landscape/vegetation/source/opengameart_oak_tree_lod_2026/quercus_A_packed_v1_0.zip` (2,222,050 bytes; SHA-256 `496f250c29eb1f56e391e55989530028e156ae43a3d1eb9f52ab09aa1bccbebf`). Its extracted `quercus_A_packed_v1.blend` is 2,856,188 bytes; SHA-256 `3b32573acd4e8eb5b7e0a96aa363932ec785a854d6e8c71f56f29b10f5abd37c`. The selected license notice SHA-256 is `1be8dab83f4107623eeba4d77e3d66091068e839e1a8b688ea1bf867c2b43e40`.

## Published LODs and retained geometry

The listing identifies a Blender 2.60 source and reports LOD0 as 4,407 vertices/2,791 faces, LOD1 as 645 vertices/442 faces, LOD2 as 21 vertices/7 faces, and trunk collision as 24 vertices/16 faces. It says LOD1/LOD2 use a separate texture with prerendered branches and foliage. This intake converts only the supplied LOD0; the other LODs remain in the retained source archive and are excluded from runtime use until their representation and transitions are qualified.

The source Collection 1 contains 36 supplied mesh parts using one material, `M_Quercus`. The deterministic conversion batches those existing parts into one glTF primitive and bakes their object transforms; it creates, edits, or decimates no tree geometry. The conversion proof records 4,407 vertices, 2,791 polygons, and 5,303 triangles, with zero maximum baked-position and UV error and a maximum loop-normal unit-vector error of `3.84625e-4`.

Before glTF axis conversion, the baked source bounds in Blender XYZ are 10.8311 × 9.1979 × 11.6512 m, with minimum `[-5.8280, -4.4254, -0.8581]` and maximum `[5.0031, 4.7724, 10.7930]`. The lowest vertex is about 0.858 m below the object origin; course terrain contact still requires an explicit check.

## Final converted material and pins

The supplied 1024×1024 image is the diffuse/alpha atlas. There are no authored normal or roughness maps. The current output is core glTF with the original base-color/alpha atlas, `BLEND`, double-sided, metallic factor 0, and scalar roughness factor 1. Roughness 1 is a reviewed scalar legacy-material adaptation, not authored texture data. The source legacy specular value is 0; core metallic-roughness glTF cannot encode it. A `KHR_materials_specular` test with `specularFactor: 0` imported into Godot with `StandardMaterial3D.metallic_specular` still at 0.5, so the production GLTF omits that extension and accepts Godot's default 0.5.

The canonical source folder contains the converter proof at `assets/landscape/vegetation/source/opengameart_oak_tree_lod_2026/CONVERSION-PROOF-LOD0.json`; the current converter is `tools/landscape/vegetation/convert_oak.py` (SHA-256 `4d0b04587e6944ea99cede3d145438f9a10c9f8720760b3259bb37bd4f245b36`). The captured canonical output pins are:

| File | Bytes | SHA-256 |
|---|---:|---|
| `gltf/lod0/oak_lod0.gltf` | 1,970 | `03f2c728f1b21f52d3278ee7abf81b91cf135d4cc4e4bc819e1b5a26b41491d7` |
| `gltf/lod0/oak_lod0.bin` | 341,388 | `61e23239d35d78f84693d15350b90961cc42185aac16660df0a4416668cfd93c` |
| `gltf/lod0/Quercus_A_1024.png` | 1,623,204 | `2f3b85071d918bc7ca69b7cc65e726d6fea4f5a3540ef67a8b930eb0f6bb4015` |

The current converter was run again to `tmp/tree-continuation-assets/repro-oak-final-converter-20261018/`; all three outputs matched these canonical hashes byte-for-byte. The fresh repeat proof is retained in `evidence/conversion/REPEAT-CONVERSION-PROOF-LOD0.json`. The final [Khronos validation report](evidence/validation/khronos-final-report.json) records zero errors, warnings, and unresolved resources. That format check does not establish visual, course, or runtime-performance qualification.
