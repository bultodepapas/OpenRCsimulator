# RC blimp 5 m: asset pipeline

Runtime visuals and physics geometry for the generic 5 m RC blimp of the [airship plan](../../../docs/plans/rc-airship.md) §8. The owner delivered one full-scale airship scene (envelope 72.65 m, Ø14.2 m) in three skins; it is frozen, byte for byte, in [`assets/source-deliveries/rc-blimp-5m/`](../../source-deliveries/rc-blimp-5m/README.md). "5 m" is defined as the **envelope length** (plan §3 assumption): uniform scale `s = 5.0 / 72.65 = 0.0688231`.

## Authoritative files

| File | Content |
| --- | --- |
| [export_blender.py](export_blender.py) | The only generator: rest pose, measurement, reduction, bake, hierarchy, GLB export; also assembles the manifest |
| [geometry.json](geometry.json) | Generated (`openrc-airship-geometry v1`, from `tiburon-blanco`): envelope volume, centroid, area, radius profile; fins, rotors, vectors, gondola, gear; collision witnesses; GLB node bindings |
| [source-manifest.json](source-manifest.json) | Generated: zip/source/exporter/GLB hashes and sizes, per-skin triangles, draw calls, materials, textures, bounds, reduction and bake records, export options, cross-skin geometry agreement |
| `app/assets/airships/rc-blimp-5m/{tiburon-blanco,historico,cromo-carbono-azul}.glb` | Self-contained runtime GLBs (textures embedded) |

Never edit generated files by hand; rerun the generator.

## Frames

- **GLB (Godot):** metres, nose −Z, right +X, up +Y, root scale 1. Origin = scaled Blender origin, on the hull axis. Source Blender `(x, y, z)` maps to Godot `s·(y, z, x)` (nose −X, starboard +Y, up +Z in the source).
- **geometry.json (physics FRD):** x forward = −X_blender, y right = +Y_blender, z down = −Z_blender, metres at 5 m, same datum. Godot ↔ FRD: `x_frd = −z_godot`, `y_frd = x_godot`, `z_frd = −y_godot`.

## Articulated nodes

All rest rotations are identity, so each `local_axis` equals the Godot axis at rest. Rule for every node: **CTRL value +θ (degrees) = rotate the node by +θ, right-handed, about `local_axis` relative to its rest transform.** Children follow their parents (each rotor sits under its vector pivot). Exact pivots and axes are in `geometry.json` → `glb_nodes`.

| Node | Parent | Source CTRL (property) | `local_axis` (Godot) | Travel | Meaning of + |
| --- | --- | --- | --- | --- | --- |
| `vector_port_hinge` | `airship` | `CTRL · vector lateral babor` (`Vector grados`) | (1, 0, 0) | 0…120° | rotor axis tilts from aft (0°) through vertical (90°, slipstream down) to 30° past vertical |
| `vector_starboard_hinge` | `airship` | `CTRL · vector lateral estribor` | (1, 0, 0) | 0…120° | as port |
| `vector_stern_hinge` | `airship` | `CTRL · vector popa` | (1, 0, 0) | 0…90° | tilts the axial stern rotor; the lateral stern rotor stays fixed |
| `rotor_port` | `vector_port_hinge` | `CTRL · rotor lateral babor` (`Giro grados`) | (0, 0, 1) | spin | delivered spin sense (demo 0→1800°) |
| `rotor_starboard` | `vector_starboard_hinge` | `CTRL · rotor lateral estribor` | (0, 0, 1) | spin | as port |
| `rotor_stern_axial` | `vector_stern_hinge` | `CTRL · rotor popa axial` | (0, 0, 1) | spin | as port |
| `rotor_stern_lateral` | `airship` | `CTRL · rotor popa transversal` | (1, 0, 0) | spin | slipstream to starboard |
| `rudder_dorsal_hinge` | `airship` | `CTRL · Aleta dorsal timón` (`Deflexión grados`) | (0, 0.9756, −0.2195) | ±20° | trailing edge to starboard |
| `fin_port_hinge` | `airship` | `CTRL · Aleta babor timón` | (−0.8449, −0.4878, −0.2195) | ±20° | trailing edge moves toward port and up (FRD −y, −z) |
| `fin_starboard_hinge` | `airship` | `CTRL · Aleta estribor timón` | (0.8449, −0.4878, −0.2195) | ±20° | trailing edge moves toward port and down (FRD −y, +z) |

The CTRL axes are not mirrored: equal + values on both lower surfaces move both trailing edges toward port (a rudder-like pair); elevator action needs opposite signs. The delivery calls the lower surfaces elevators.

Each node's meshes are one child `<node>_mesh` (one primitive per material). Parts the delivery documents as fixed (`carcasa FIJA`, `cono FIJO`, gear, doors, blade-pitch roots) keep their real parent: casings stay on `airship`; the `torpedo NO giratorio` tilts with its vector but does not spin. Blade pitch (`Paso visual grados`), doors and gear are exported at rest and are not articulated. The same bindings are written as node extras (`openrc_local_axis`, `openrc_travel_deg`, `openrc_source_ctrl`).

Rotor `axis_rest` in `geometry.json` is the slipstream direction for the delivered positive spin; thrust on the vehicle is `−axis_rest`. Blade sections are symmetric, so the leading edge is inferred from that spin sense (chord pitched about 20° at 0.7 R). If a different spin sense is chosen at integration, the slipstream reverses too.

## What the export contains

- Exactly the render-visible geometry of the delivered scene (render-enabled, non-excluded collections, `hide_render` off, camera-visible), with modifiers and curve geometry evaluated at render settings. Cameras, lights, empties, demo (`06D`, `ANIM ·`), texts, reference and annotation collections are excluded. All CTRL values are 0 and the demo toggle is off; drivers and animation are not exported.
- Reduction (all at 5 m; per-object records in the manifest): parts whose largest side is < 2 mm are dropped (hinge bolts, cone screws, latches); bevel modifiers narrower than 0.5 mm are not applied (sharp edges marked at 30° instead); glass panes are single sheets without their solidify thickness; meshes with ≥ 2000 triangles are collapse-decimated to the smallest ratio whose two-sided vertex deviation stays ≤ 0.25 mm, with material-border vertices protected and every material keeping its area within 10 % (so blade bands and stripes survive).
- Materials: plain Principled materials keep base colour, metallic, roughness and emission. The Mix/Transparent/Glossy glass becomes Principled glass (dark blue tint, alpha 0.35, `BLEND`, double-sided). Procedural materials are baked with Cycles on one joined world-space proxy (EMIT pass of each channel, 16 samples, 8 px margin; each part's object-space coordinates are carried as an attribute so the shaders see the original coordinates): base colour and roughness, and metallic where it varies. The envelope uses a cylindrical UV (u = station, v = angle, seam on the dorsal line) at 2048×1024; other materials use a shared smart projection at ≤ 1024². A bake whose p0.05…p99.95 range is below 0.025 (colour) or 0.03 (data) collapses to a constant. Colour is embedded as JPEG q90, data as PNG. No normal maps: the procedural bumps are sub-millimetre at 5 m.

## Regenerate and verify

```sh
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"   # Blender 5.2.2
S=assets/source-deliveries/rc-blimp-5m
X=assets/aircraft/rc-blimp-5m/export_blender.py
"$B" -b $S/04_Tiburon_Blanco/Tiburon_Blanco_V1.blend --factory-startup --python $X -- --skin tiburon-blanco \
    --out app/assets/airships/rc-blimp-5m/tiburon-blanco.glb --geometry assets/aircraft/rc-blimp-5m/geometry.json \
    --report <tmp>/report_tiburon-blanco.json --work-dir <tmp>/tiburon-blanco
"$B" -b $S/05_Historico/Zeppelin_Historico_V1.blend --factory-startup --python $X -- --skin historico \
    --out app/assets/airships/rc-blimp-5m/historico.glb --geometry <tmp>/geometry_historico.json \
    --report <tmp>/report_historico.json --work-dir <tmp>/historico
"$B" -b $S/06_Cromo_Carbono_Azul/Zeppelin_Cromo_Carbono_Azul_V1.blend --factory-startup --python $X -- \
    --skin cromo-carbono-azul --out app/assets/airships/rc-blimp-5m/cromo-carbono-azul.glb \
    --geometry <tmp>/geometry_cromo-carbono-azul.json --report <tmp>/report_cromo-carbono-azul.json --work-dir <tmp>/cromo
python3 $X --assemble-manifest assets/aircraft/rc-blimp-5m/source-manifest.json --zip-dir <dir with the three zips> \
    --source-dir $S --reports <tmp>/report_*.json --geometries assets/aircraft/rc-blimp-5m/geometry.json \
    <tmp>/geometry_historico.json <tmp>/geometry_cromo-carbono-azul.json --reference-skin tiburon-blanco
```

Each export takes about 2–4 minutes on CPU. The bake and texture files land in `--work-dir`; keep it outside the repository.

VERIFICATION_PLACEHOLDER

## Known omissions and open items

- Not yet imported or rendered in Godot: no `.import` sidecars, import settings, LODs or in-app 1080p captures exist. Godot frame cost, VRAM and draw calls on target hardware are unmeasured.
- Doors, gear suspension, wheel spin, caster and blade pitch are static at rest. The demo animation is not exported.
- The chrome skin relies on reflections; without reflection probes or a sky in the scene it renders darker than in Blender.
- The envelope volume is the delivered visual hull (closed manifold). Fill shape, inflation and gas data are not part of this asset (plan §3).
- Display names are working names; no licence file accompanies the delivery.
