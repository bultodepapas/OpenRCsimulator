# Monster Car 2 visual adapter

The runtime model uses the supplied `monster_truck_nitro_1.glb` geometry and the supplied `monster_truck_nitro_1.blend` rig. No replacement vehicle geometry was created. `visual_bake.py` samples the original Blender drivers into a compact transform table; the source `.blend` and GLB are not modified.

The source files were supplied with this task. The committed GLB and `datos_simulacion_1.json` copies are byte-identical to those supplied under `monster car 2/`; see [SOURCE.txt](../../../assets/vehicles/monster-car-2/SOURCE.txt) for the asset provenance record:

| Asset | SHA-256 |
| --- | --- |
| `monster_truck_nitro_1.glb` | `cd894dd4cc365934626d4b4d45c64a22521d0bc89fb9918b07afe546a7910759` |
| `datos_simulacion_1.json` | `510c3c822d4896174e26de930626b8abd6e3b232fd337c3348d7556fdc769ad0` |

No external model or free-download asset was used. The task supplied no separate redistribution license, so this records provenance rather than asserting public licensing terms.

## Coordinates and fit

The GLB uses +X forward, +Y up, and -Z left. `AuthoredCoordinates` applies a +90° rotation around app +Y and subtracts 0.087 m from source height. The visual root remains at the vehicle datum; the activity supplies its current CG offset to the adapter, so ballast changes move the model and its effects consistently.

The baked GLB wheel-node centers at rest are:

| Corner | App X right (m) | App Y up from datum (m) | App Z aft (m) |
| --- | ---: | ---: | ---: |
| FL | -0.199999988 | -0.000133405 | -0.199999988 |
| FR | +0.199999988 | -0.000133398 | -0.199999988 |
| RL | -0.200000003 | -0.000133405 | +0.200000018 |
| RR | +0.200000003 | -0.000133405 | +0.200000018 |

The supplied physics geometry places the tire centers at X/Z = ±0.2 m and 0.0005 m below the datum. The GLB's authored root translation places its wheel nodes 0.367 mm above that target height; lateral and longitudinal centers agree within 0.0001 mm. Maximum three-dimensional center error is 0.367 mm, inside the 1 mm render-fit tolerance.

## Rig and bindings

The bake covers 209 animated mesh/pivot transforms out of 441 GLB mesh nodes. Suspension travel uses 41 samples from -0.044 to +0.036 m at 0.002 m steps. Front wheel, steering, and linkage transforms use the authored suspension/steering driver results on a 41 × 43 grid. The signed inverse steering table maps the physical positive-right steering state to the supplied positive-left Blender control range. This keeps the physical steering limit inside the authored steering envelope.

Wheel roll uses state angles 25–28 around each authored tire axle. The authored crank pivot and flywheel meshes use the render-only `visual.engine_phase_rad` supplied by the activity. These phases are applied after suspension and steering transforms.

Bindings exposed to shared effects and damage code:

- `Body`: `Carroceria_Casco`; `body_nodes`: the 66 authored body/accessory meshes.
- `Bumper_F` / `Bumper_R`: the authored `Parachoques_Del.001` / `Parachoques_Tras.001` meshes. Godot imports Blender's `.001` suffix with `_001`; the adapter preserves the source alias.
- `FL_WheelMesh`, `FR_WheelMesh`, `RL_WheelMesh`, `RR_WheelMesh`: the four authored `Llanta_*` tire meshes.
- Headlight lenses: `Faros`, `Faros_Diurna`, `LED_Frontal`, `Focos_Antivuelco_LED`; tail/brake lenses: `Calaveras`.
- Exhaust outlet metadata: authored `Escape_Deflector` geometry.
- `damage_basis`: imported GLB local coordinates to vehicle right/up/aft coordinates.

## Rebuild and verification

From the repository root, use Blender 5.2.2 and the supplied source rig:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' -b 'monster car 2\monster_truck_nitro_1.blend' --python research/rc-monster-truck/monster-car-2/visual_bake.py -- --glb assets/vehicles/monster-car-2/monster_truck_nitro_1.glb --spec assets/vehicles/monster-car-2/datos_simulacion_1.json --out assets/vehicles/monster-car-2/visual_rig
```

The generated `visual_rig.bin` is SHA-256 `4127dc26b64ed2b4ddacd230cc073ec7bab273bb7a624416587264592bfb573d`. Its JSON manifest records the GLB/spec hashes, track layout, rest wheel centers, and authored effect bindings. The runtime copy under `app/assets/vehicles/monster-car-2/` must match the generated files. At runtime the adapter checks the bake binary hash and validates every track's bounds and samples. In a source checkout it also hashes the raw GLB; an exported PCK contains Godot's imported scene instead of those raw GLB bytes, so the GLB source hash is checked during baking/build validation and is not compared against the remapped scene.

From the repository root on the Windows workspace, run the focused check with:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_rcv_nitro_visual.gd
```

On Linux, run it from the `app/` directory with:

```sh
cd app
./.tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tests/test_rcv_nitro_visual.gd
```

It checks binding completeness, the 1 mm rest wheel-center fit, independent wheel and flywheel spin, suspension motion, and physical-limit steering mapping.

Check packaged copies, source hashes, bake integrity, and regenerated manifest provenance with:

```sh
python3 research/rc-monster-truck/monster-car-2/visual_verify.py --regenerated-prefix /path/to/fresh/visual_rig
```
