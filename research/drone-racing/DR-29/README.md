# DR-29: OpenRacer frame intake for `openrc-fpv5`

Download-first visual for the experimental 5-inch FPV build, converted reproducibly from [OpenRacer](https://github.com/OpenRacer/OpenRacer) at commit `15477b200a569dad9d4107e77fdb7cac5acfffd9` (GPL-3.0). Full evidence: [receipt.json](receipt.json). Licence notice: [NOTICE.md](../../../app/assets/multirotors/openrc-fpv5/NOTICE.md).

## What was taken in

One variant of the original 5-inch frame:

- `cad/Carbon/2.5mm_BottomPlate.dxf` and `cad/Carbon/2.5mm_MidPlate.dxf`: plates, extruded 2.5 mm;
- `cad/Carbon/Arms/5mm_Arm_Fatty4Holes.dxf`: one arm, extruded 5 mm and placed four times by 90° rotation;
- `cad/AnalogSmoothClassic/Canopy.stl`: TPU canopy, decimated from 59,280 to 30,000 triangles.

Plate thicknesses come from the OpenRacer README. Output: `app/assets/multirotors/openrc-fpv5/openrc_fpv5_frame.glb`, 38,032 triangles, 0.82 MB. It contains two materials (carbon, printed TPU) and no textures.

Nodes: `airframe_root` contains the meshes `frame_carbon` and `canopy`, plus these empties:

- `motor_1`…`motor_4` and `propeller_1`…`propeller_4` at the motor-mount centres. Order: 1 rear-right, 2 front-right, 3 rear-left, 4 front-left.
- `camera_mount` on the canopy's camera side-screw axis.

The GLB is +Y up with the nose on −Z and right on +X. Its origin is the centre of the four hubs, in the motor-mount plane (top face of the arms).

## Reproduce

```sh
git init OpenRacer && cd OpenRacer
git fetch --depth 1 https://github.com/OpenRacer/OpenRacer 15477b200a569dad9d4107e77fdb7cac5acfffd9
git checkout FETCH_HEAD && cd ..
blender --background --factory-startup --python-exit-code 1 \
  --python research/drone-racing/DR-29/build_fpv5_glb.py -- OpenRacer out/openrc_fpv5_frame.glb --measure out/measure.json
```

The run used Blender 5.2.2 LTS on Windows. It is deterministic: two runs produced the same SHA-256. Compare the output hash with `receipt.json`, then copy the GLB into the asset folder. The script reads DXF and STL itself. It needs no CAD converter or Blender add-on.

## Measured (frame only)

| Quantity | Value |
| --- | --- |
| Layout | True square X |
| Motor diagonal | 205.32 mm; the physics data estimate is 215 mm |
| Adjacent hub spacing | 145.19 mm |
| Arm | 5 mm thick, 9.1–12.4 mm wide |
| Adjacent prop tip gap, 5.0 in / 5.1 in | 18.19 / 15.65 mm |
| Plan-view prop-to-canopy margin, 5.0 in / 5.1 in | 3.30 / 2.03 mm |

The canopy margin is measured in plan view. The nearest canopy point is 15.5 mm above the mount plane, so the 3D margin depends on the missing motor height.

## Limits

- Motors, propellers, electronics, the camera, the battery, standoffs, screws and the optional braces are not in the download. None were modelled.
- The asset sets no mass, CG or inertia, and it is not a complete or measured aircraft.
- `camera_mount` marks the camera pivot, not the lens.
- The GPL-3.0 distribution decision belongs to the project owner (see `redistribution` in the receipt).
