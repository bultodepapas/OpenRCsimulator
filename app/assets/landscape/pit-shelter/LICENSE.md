# Texture provenance and license

These source maps are from **Corrugated Iron 02** by Sergej Majboroda (photography) and Jenelle van Heerden (processing), downloaded from Poly Haven on 2026-10-20 at 2K resolution:

- Base color: `corrugated_iron_02_diff_2k.jpg`
- OpenGL tangent-space normal: `corrugated_iron_02_nor_gl_2k.png`
- Packed ambient occlusion, roughness, metallic: `corrugated_iron_02_arm_2k.jpg` (R = AO, G = roughness, B = metallic)

Asset page: <https://polyhaven.com/a/corrugated_iron_02>

Direct source maps:

- <https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/corrugated_iron_02/corrugated_iron_02_diff_2k.jpg>
- <https://dl.polyhaven.org/file/ph-assets/Textures/png/2k/corrugated_iron_02/corrugated_iron_02_nor_gl_2k.png>
- <https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/corrugated_iron_02/corrugated_iron_02_arm_2k.jpg>

SHA-256 (original downloaded files):

- `corrugated_iron_02_diff_2k.jpg`: `1bd2b9900e066d7e6cbacc5093aa4204db71c1bbe13b42a3d8ad23d04fa8075a`
- `corrugated_iron_02_nor_gl_2k.png`: `57966705714a10b718efc31368879c75fbf24ee3d3295106eada9094513f9cbc`
- `corrugated_iron_02_arm_2k.jpg`: `80ae7f8b9ff7521898049cb79b7cfb82a0bb95bf0cba312ffe1d0e5760f45dcb`

Poly Haven releases its assets under **CC0 1.0 Universal**. Use, modification, redistribution, and commercial use are permitted without attribution. The texture is 2.7 m wide; its image has the corrugations running along V and spaced across U, so the roof shader maps U across local X and V down local Z. Attribution is retained here as provenance.

License details: <https://polyhaven.com/license>

The structural-timber shader branch reuses the existing **Wood049** maps under
`app/assets/landscape/flightline/`; it does not add copies of those files. The
Wood049 CC0 source and per-file provenance are recorded in that folder's
`LICENSE.txt` and `PROVENANCE.json` (ambientCG asset page:
<https://ambientcg.com/view?id=Wood049>).
