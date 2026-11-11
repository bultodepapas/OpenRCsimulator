# OpenRacer frame visual — source and licence notice

`openrc_fpv5_frame.glb` is a modified work derived from OpenRacer, an open-source 5-inch FPV racing frame.

- Source: [github.com/OpenRacer/OpenRacer](https://github.com/OpenRacer/OpenRacer), commit [`15477b200a569dad9d4107e77fdb7cac5acfffd9`](https://github.com/OpenRacer/OpenRacer/tree/15477b200a569dad9d4107e77fdb7cac5acfffd9) (2026-03-13).
- Authors: OpenRacer contributors. The README names no individual frame or canopy designer. Per-file commit history is in the [receipt](../../../../research/drone-racing/DR-29/receipt.json).
- Licence: GNU General Public License version 3. Its text is in the pinned [LICENSE](https://github.com/OpenRacer/OpenRacer/blob/15477b200a569dad9d4107e77fdb7cac5acfffd9/LICENSE) file (Git blob `f288702d2fa16d3cdf0035b15a9fcbc552cd88e7`, SHA-256 `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`). A byte-identical copy is kept beside this file as [LICENSE-GPL-3.0.txt](LICENSE-GPL-3.0.txt). The simulator's MIT code licence does not apply to this asset.

## Source files

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `cad/Carbon/2.5mm_BottomPlate.dxf` | 16912 | `7713ec5f7aec281a3a0ebf0831a557f3ec1a5ed4f1b10cf59493719cfaa61b92` |
| `cad/Carbon/2.5mm_MidPlate.dxf` | 14269 | `cad1e3467f42cfee3d0bd9a16a4880ab66310cfaf0a878edd2cbb45b631880c3` |
| `cad/Carbon/Arms/5mm_Arm_Fatty4Holes.dxf` | 9171 | `f5828a71fa3f8ddbbda6440f84200f11c1d11e0901b7eac163592db2c2b1ae30` |
| `cad/AnalogSmoothClassic/Canopy.stl` | 2966384 | `6f0535d6ee55e518e73d1e8f0ae46efa15a30f07e9565864d11de10680267bfc` |

## Modifications (2026-11-11, DR-29)

- Extruded the 2D DXF outlines by the plate thicknesses from the README: 2.5 mm for the plates and 5 mm for the arms.
- Reduced the countersink circles to their through-holes.
- Placed the arm four times by rotation and stacked the parts.
- Decimated the canopy from 59,280 to 30,000 triangles.
- Converted millimetres to metres and reoriented the model to +Y up with the nose on −Z.
- Added two plain materials, plus empty nodes for the motors, propellers and camera pivot.

No geometry from outside the source files was added.

Output: `openrc_fpv5_frame.glb`, 822056 bytes, SHA-256 `e6c649e6123c66afc8546f940aefc5047cc4e52730d53f5fc039d007a29376e3`.

## Corresponding source

[research/drone-racing/DR-29/build_fpv5_glb.py](../../../../research/drone-racing/DR-29/build_fpv5_glb.py) regenerates the GLB from the unmodified files listed above. [README.md](../../../../research/drone-racing/DR-29/README.md) gives the steps.

This notice records facts. It does not decide how the project distributes this asset.
