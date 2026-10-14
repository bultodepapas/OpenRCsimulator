# Turbo Timber Evolution — game build r2 (OpenRC Simulator)

Delivery against *Blender aircraft delivery for OpenRC Simulator — 2026-10-13 · Revision 2*.
r2 keeps every r1 pivot (names, parents, rest transforms) and replaces the single merged `airframe`
with sibling **crash-section meshes** tagged `openrc_section`.

| | |
|---|---|
| Blender | **5.2.2 LTS** (build d13f752e3b9c, used as the `bpy` 5.2.2 Python module); glTF exporter `io_scene_gltf2` **5.2.40** |
| Game file | `export/aircraft.glb` — sha256 `d75ae605aa3afdf3f417a0ec535c3bd3126c2a5a4eb7827393727152245c6722` |
| Demo file | `export/aircraft_demo.glb` — articulation reference only (one `control_demo` animation, one control at a time) |
| Editable source | `source/aircraft_game.blend` |
| Triangles / surfaces / materials | **42,519** / 49 (see "Budgets") / 10 shared, no textures |
| Verification | `verification.json` — **PASS** (4 advisory items, listed below); negative tests PASS |

## Package layout

```
r2/
  README.md  CHANGELOG.md  LICENSE.txt  metadata.json  export-map.json  verification.json
  export/aircraft.glb            game asset (no cameras, lights or animation)
  export/aircraft_demo.glb       same model + control_demo animation
  previews/                      front, side_right, top, underside, three_quarter(_rear), control_extremes,
                                 exploded_sections(_rear) (closure faces in cyan, preview only),
                                 silhouette_master_vs_game
  source/aircraft_game.blend     opens on the neutral assembled aircraft; collection EXPORT_aircraft;
                                 text block README_export (export command, frames, control names)
  source/stl_juego_r2/           lightweight tessellation of the master (input of the build) + _report.json
  source/inputs/                 ok.json, escena.json (master v17 data), r1_aircraft.glb, r1_metadata.json
  source/_export_data.json       measurements taken in the export scene (landmarks, pivots, counts)
  source/verification_negative/  reports of the deliberately broken copies
  source/scripts/                build, export, validation and documentation tools
```
`textures/` is not shipped: no textures are used.

## Open, edit, re-export

Open `source/aircraft_game.blend` in Blender 5.2.2. Everything that is exported lives in the collection
**EXPORT_aircraft**; the Outliner shows the hierarchy below. Keep the pivots at their rest rotation when saving.

Re-export (the documented preset — identical bytes to the shipped GLB were verified):

```
blender -b source/aircraft_game.blend --python source/scripts/exporta_desde_blend.py -- export/aircraft.glb
```
or `python3 source/scripts/exporta_desde_blend.py source/aircraft_game.blend export/aircraft.glb` with the bpy module.

Manual equivalent: *File › Export › glTF 2.0*: Format **glTF Binary (.glb)**; Include › **Active Collection**
(EXPORT_aircraft active), Custom Properties **on**, Cameras off, Punctual Lights off; Transform › **+Y Up on**;
Data › Mesh › Apply Modifiers on; Material › Export; Compression **off**; Animation **off**.

Full rebuild from the package (clean copy, no CAD needed; verified byte-identical):

```
python3 source/scripts/exporta_r2.py --pkg .              # .blend + both GLBs + source/_export_data.json
python3 source/scripts/verifica_r2.py --pkg . [--master-stl <master STL dir>]   # verification.json + previews, exit 1 on failure
python3 source/scripts/valida_glb.py export/aircraft.glb --r1 source/inputs/r1_aircraft.glb   # structural, pure Python
python3 source/scripts/pruebas_negativas.py export/aircraft.glb <scratch dir> --r1 source/inputs/r1_aircraft.glb \
        --blender-verifier "python3 source/scripts/verifica_r2.py --pkg ."
python3 source/scripts/documenta_r2.py --pkg .            # metadata.json + export-map.json
```
**CAD rebuild: unsupported from this package.** `retesela_r2.py` (tessellation of the master, then `--paint-only` for the
base-colour split of wings and tail) needs the master
BREP caches (`modelo_v15.py.brep`, `modelo_v17.py.brep`, 376 MB, build123d 0.13.0) which are not shipped; its
output is shipped in `source/stl_juego_r2`, so every later step runs from a clean copy.

## Configuration

Landplane, stock-style foam main wheels, steerable tailwheel, flaps at 0°, **no floats, no slats** (only the
small fixed slat brackets), neutral controls, **no ground attitude**. Base colours only (no logos, no text).

## Coordinates and datum

* Units: metres. Blender authoring frame +X right, +Y nose, +Z up.
  GLB / Godot: `godot = (blender.x, blender.z, -blender.y)` (+X right, +Y up, nose toward −Z).
* Root `TurboTimberEvolution` = identity at **D0** = symmetry plane × wing-root leading-edge station ×
  CAD thrust-axis height.
* Pivots: local **+X is the hinge axis**; a control angle is applied as `rest * rot(+X, angle)`. All node
  scales are (1,1,1); names are unique ASCII, no `.001`.

## Hierarchy and sections

```
TurboTimberEvolution                     (untagged)
├─ fuselage_core        core              ├─ aileron_left_hinge  wing_left        → aileron_left
├─ wing_left_fixed      wing_left         ├─ aileron_right_hinge wing_right       → aileron_right
├─ wing_right_fixed     wing_right        ├─ flap_left_hinge     wing_left        → flap_left
├─ stabilizer_fixed     horizontal_tail   ├─ flap_right_hinge    wing_right       → flap_right
├─ fin_fixed            vertical_tail     ├─ elevator_hinge      horizontal_tail  → elevator
├─ cowl                 engine            ├─ rudder_hinge        vertical_tail    → rudder
├─ canopy_glass         canopy            ├─ thrust_frame (untagged) → propeller_spin propeller → propeller_rotor
├─ gear_cables          gear              ├─ gear_left_suspension gear → gear_left_leg, wheel_left_axle → wheel_left
                                          ├─ gear_right_suspension gear → gear_right_leg, wheel_right_axle → wheel_right
                                          └─ tailwheel_steer gear → tailwheel_fork, tailwheel_axle → tailwheel
```
Every mesh and every moving pivot carries the string extra `openrc_section`; one section per mesh, nothing welded
across a section boundary. Horns stay with their surface, nav lenses with their wing (left red lens → `wing_left`),
the beacon with `core`. The cowl/fuselage joint is cut at Blender y = +0.157 m (cowl, nose panel, fillet, stripes and
exhaust plates are split there). `wing_center` is unused (two plug-in wing halves). The rotor is not under any
engine-tagged node.

**Closure faces**: at wing roots, cowl joint, stabilizer and fin attachments the faces lying on the neighbouring
section are split off, given the plain foam colour (material `white`, unpainted EPO) and set **0.2 mm inside** their
own piece, so no two joint faces share a plane. See `previews/exploded_sections.png`.

## Controls (positive direction, ranges) and clearance

| Pivot | Positive | Authored | Simulator | Clear envelope (swept) |
|---|---|---|---|---|
| aileron_left/right_hinge | TE down | ±22° | ±34.5° (approx.) | ±34.5° clear |
| elevator_hinge | TE down | ±22° | ±17.8° (approx.) | ±22° clear |
| rudder_hinge | TE to the pilot's right | ±30° | ±18.2° (approx.) | ±30° clear (also with elevator ±22°) |
| flap_left/right_hinge | TE down | 0–40° | steps 0 / 20.7 / 36.6° | **0–39°** (contact with the wing at 40°); steps clear |
| tailwheel_steer | wheel to the right | ±30° | — | ±30° clear (swept with the rudder) |
| gear_left/right_suspension | leg outboard | 0–12° | — | **0–6°** (wire link meets its foam bracket from 7°) |
| propeller_spin | clockwise seen from behind | continuous | — | clear |
| wheel_*_axle, tailwheel_axle | forward roll | continuous | — | clear |

Ranges are reported, **not clamped**; the GLB carries no limits. Simulator values are kept next to the authored
ones in `metadata.json` (and as `sim_range_deg_approx` / `sim_flap_steps_deg` extras on the pivots).

## Landmarks (GLB / Godot frame, m)

Wingtips ±0.772752 (span **1.5455 m**); spinner tip z −0.283461; rudder TE z +0.832 (length **1.1155 m**);
wing-root LE (0.0013, 0.0974, 0); prop hub (−0.0003, 0.0003, −0.2421), prop Ø 0.2806 m; main wheel centres
(±0.13198, −0.198, 0.008), r 0.0580 m, contacts y −0.256; tailwheel centre (0, −0.112, 0.759), r 0.014 m.
Hinge lines and thrust axis: `metadata.json › hinge_lines / thrust`. Not rescaled (r1 1.5479 / 1.1166 m;
manual 1.555 / 1.040 m) — see CHANGELOG.

## Budgets

* Triangles 42,519 (target 30–50k). Dense foam parts were decimated only where the two-way deviation from the
  master tessellation stays ≤ 0.25 mm, with colour borders locked (per-part values in `metadata.json › meshes.decimation`).
* **Surfaces 49 > 40**: 21 meshes are needed by the crash split and each mesh needs one primitive per colour it shows
  (wings: foam, red, black, dark-grey brackets, nav lens). Reducing it would remove the paint scheme.
* 10 shared materials, base colour only, backface culling on every material; no textures.
* **Markings as base colour** on the wings and tail: the foam part is split in CAD by each marking (higher priority
  first), every piece keeps its colour, the hidden walls between pieces are removed and the pieces welded — no stacked
  shells there. Only the fuselage/cowl stripes and nose panel remain thin shells (single-sided, 0.12 mm × priority
  above the skin, seated ≥ 0.1 mm above the foam).
* Degenerate / duplicate faces 0; coplanar flicker area 0 mm².

## Mass

The 1.46 kg component ledger in `metadata.json` is a **non-flight placeholder**. The selected reference is the
manual value **2.190 kg**. The r2 geometry does not create new mass, CG or inertia values.

## Advisory items in verification.json

`surfaces_le_40` (49, reason above), `span_length_consistent_with_r1_1mm` (−2.4 mm / −1.1 mm, master change),
`clearance_authored_ranges` (flaps 40°, suspension > 6°). Every required check passes. `verification.json › release_checks` records the clean-copy rebuild and the
re-export from the .blend (both byte-identical), the negative tests and the untouched r1 hashes.
