# Building roof textures (LU-33, 2026-10-20)

All six new files in this directory are unmodified 1K downloads from Poly Haven and are [CC0](https://polyhaven.com/license). The game fits them to its own roof geometry using the suppliers' physical tile widths. Godot's generated `.import` files describe the engine import and are not source artwork.

| Surface | Author and source | Physical tile | Files and SHA-256 |
| --- | --- | --- | --- |
| Weathered slate | [Roof Slates 03](https://polyhaven.com/a/roof_slates_03), Rob Tuytel | 3 m | `roof_slates_03_diff_1k.jpg` `ad7caff0fae22a67c2429021129840d3d9247ec4370bafadc2c031e1693fe8a9`; `roof_slates_03_nor_gl_1k.png` `0cb0e3539bcf0a9285f0f2395285e83d49384c7ebd4d08c0ee955f90b093c9d2`; `roof_slates_03_arm_1k.jpg` `9d9caa14a56f8861fb4ee97f3bcbccf1df7b819fdbe76fa2c2eeae8ff1e1dcd5` |
| Weathered clay | [Clay Roof Tiles](https://polyhaven.com/a/clay_roof_tiles), Amal Kumar | 4 m | `clay_roof_tiles_diff_1k.jpg` `aac0f4e742a2cce21afb5dfb523b47c720c6a8e2782a312b823608fe3f80eae6`; `clay_roof_tiles_nor_gl_1k.png` `c36aca4343b0e223ca7b4bc0f6600946c11a2e80ea995bc73abf30a109651956`; `clay_roof_tiles_arm_1k.jpg` `dc86408a71ded3d94b1ff1a7bf2253647118b07b83b611fea37a528dc41791cb` |

Each map was downloaded from `https://dl.polyhaven.org/file/ph-assets/Textures/{jpg|png}/1k/<asset>/<asset>_{diff|nor_gl|arm}_1k.{jpg|png}`. `diff` is color, `nor_gl` is OpenGL normal, and `arm` packs ambient occlusion, roughness and metalness. The pavilion veranda, shed and barns reuse the separately credited [Corrugated Iron 02](../pit-shelter/LICENSE.md) already shipped for pit shelters.
