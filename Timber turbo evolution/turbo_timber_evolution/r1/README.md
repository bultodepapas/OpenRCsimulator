# Turbo Timber Evolution — game delivery r1

Aircraft id: `eflite_turbo_timber_evolution` · revision `r1` · for OpenRC Simulator (Godot, glTF 2.0)

This is a game build made in parallel with the presentation model v12. Both come from the same
parametric CAD. The presentation model is unchanged.

## What is in r1

| Item | Status |
|---|---|
| Neutral export `export/aircraft.glb` | done (no animation, neutral body pose) |
| 4 primary controls: ailerons L/R, elevator, rudder | done |
| Flaps L/R | done (0° in the export) |
| Propeller: fixed thrust frame + spinning rotor | done |
| Main wheel axles, gear suspension, tailwheel steer + axle | done |
| Frame and landmark table | `metadata.json` → `frames`, `datum`, `landmarks` |
| Demo `export/aircraft_demo.glb` | one animation, `control_demo`: each control goes neutral → +max → neutral → −max; propeller and wheels spin |
| Round-trip verification | `verification.json`: 20/20 checks pass |
| Previews | `previews/`: front, side, top, underside, 3/4 front, 3/4 rear, `control_extremes.png` |

## Configuration

- Landplane on stock foam main wheels with a steerable tailwheel. **No floats.**
- **No slats.** Only the small grey slat brackets are modelled, as fixed airframe parts. Their real function is not certain.
- Flaps are present and exported at 0°.
- Nav and strobe lenses use emissive materials. No light objects are exported.
- These parts are estimated, not taken from a manual: a 15-size outrunner, an 11×7-equivalent 3-blade propeller and a 4S 3200 mAh battery.
- The livery uses plain solid colours. There are no logos, text or textures.

## Units, frames, datum

- Units are metres. Angles in the metadata are degrees, and the glTF quaternions are runtime rotations.
- **Simulator / glTF frame:** +X right (pilot view), +Y up, nose toward −Z. Left and right are as seen by the pilot.
- **Datum D0** is the root node `TurboTimberEvolution`, with an identity transform. It is the point where these three meet:
  - the symmetry plane
  - the wing-root leading-edge station
  - the CAD thrust-axis height
- D0 is a stable geometric point. The CG is **not** the origin. It is given as data in `metadata.json → mass_properties.cg`, at (0, −0.011, +0.061) m in the sim frame.
- Conversion formulas for the Blender authoring frame and the CAD frame are in `metadata.json → frames`.
- **Neutral body pose:** the export has no ground offset and no presentation pitch. These angles are built into the geometry:
  - 2° wing incidence
  - 2° dihedral
  - 2° downthrust
  - 2° right thrust
- The three-point ground attitude (9.8°) is supplied as data only.

## Articulations

Every pivot node uses the same rules:

- Its local **+X is the hinge axis**, and rotation follows the right-hand rule.
- Angle 0 is the rest orientation stored in the node.
- To apply a control, use `rest * axisAngle(+X, angle)`.
- Each moving mesh is a child of its pivot node with an identity local transform.
- The node's id, axis, positive direction, range and range source are also stored on the node as glTF extras.

| Node | Parent | Positive (+) | Range |
|---|---|---|---|
| aileron_left_hinge | root | trailing edge down | ±22° |
| aileron_right_hinge | root | trailing edge down | ±22° (differential 0.7 as mixing data) |
| flap_left_hinge / flap_right_hinge | root | trailing edge down | 0…40° |
| elevator_hinge | root | trailing edge down (nose-down) | ±22° |
| rudder_hinge | root | trailing edge to the pilot's right | ±30° |
| tailwheel_steer | root | same as rudder (coupled 1:1) | ±30° |
| tailwheel_axle | tailwheel_steer | forward rolling | continuous |
| thrust_frame | root | fixed: +X = thrust direction (2° down, 2° right) | — |
| propeller_spin | thrust_frame | clockwise seen from behind | continuous |
| gear_left_suspension / gear_right_suspension | root | leg swings outboard | 0…12° |
| wheel_left_axle / wheel_right_axle | gear_*_suspension | forward rolling | continuous |

Wheel rolling is kept separate from steering and suspension, so each wheel has its own parent pivot.
Pivot positions, axes, rest rotations and member part lists are in `metadata.json → articulations`.
Every control range is an **estimate**: no manufacturer manual was available to the modeller.
`verification.json → sign_checks` turns each joint +10° and confirms that the part moves in the stated positive direction.

## Moving-part membership

- Control horns move with their control surface.
- The rudder's red and black stripes move with the rudder.
- The elevator is one piece. Both halves, the torsion rod and the top colours share one hinge.
- `export-map.json` lists every CAD part, the node it went to, and the parts left out, each with a reason. Left-out parts include internal electronics, the motor mount and shaft, screws, servo arms and eyelets.

## Mesh budget and hygiene

The letter set provisional targets of ≤ 100,000 triangles and ≤ 40 surfaces.

- **64,291 triangles** in **15 mesh nodes** with **36 surfaces** (mesh × material).
- The CAD tension springs had 765,356 triangles, which was 67.5 % of the old STL set. They are replaced by 112 cosmetic triangles in `gear_cables`, shown in the rest pose. The cable endpoints are in the metadata so the simulator can redraw them.
- Clean on re-import: no zero-area faces, no duplicate faces and consistent normals.
- Overlapping decals were resolved by boolean subtraction and then offset 0.12 mm per priority level. What remains of coplanar same-direction overlap is 1.5 mm² in total. Contacts between back-to-back faces are hidden and are not an issue.
- There are 10 glTF-safe Principled materials. `glass` is the only transparent one (alpha blend 0.45). There are no textures.

## Dimensions: model vs reference

| | Model | Reference (letter) | Difference |
|---|---|---|---|
| Span | 1.548 m | 1.555 m | −7 mm (−0.5 %) |
| Length (spinner tip → rudder TE) | 1.117 m | 1.040 m | +77 mm (+7.4 %) |

The scale was **not changed**.

- The span matches, so the model is not uniformly mis-scaled. Scaling it to 1.040 m long would cut the span to about 1.44 m.
- Most of the extra length is ahead of the wing. In the top and side photos, the wing leading edge sits about 42–56 mm closer to the propeller than in the model, so the nose and cowl are about 50–60 mm too long.
- The remaining 15–25 mm is within the uncertainty of how the reference measures length, plus photo perspective.
- Shortening the nose moves the estimated CG close to the main axle. It should be done with a manufacturer drawing or CG figure, or a long-lens side photo with a scale. This is planned for r2.

## Masses (partial, estimated)

- Total mass is about 1.46 kg (±15 %), built from component estimates.
- The CG is at 28.5 % MAC (MAC 0.213 m).
- Wing area is 0.329 m².
- Every value carries `value / unit / evidence / source / uncertainty`.
- There is no inertia tensor and no spring stiffness yet.

## Tools and reproduction

- Python 3.13, build123d 0.13.0 (CAD), Blender 5.2.2 as the `bpy` module (export, verification, previews).
- Steps:
  1. `source/scripts/modelo_v12.py` builds the CAD and writes the BREP cache.
  2. `retesela.py <cache> stl_juego 0.3 0.35`
  3. `exporta_juego.py --pkg <dir>`
  4. `verifica_glb.py --pkg <dir>`
  5. `hoja_mandos.py <dir>`
  6. `documenta.py --pkg <dir>`
- The glTF export settings are recorded in `metadata.json → export`.
- `source/aircraft.blend` is the export scene: the `EXPORT_aircraft` collection with no lights, cameras, ground, reflectors or CG markers.
- The presentation model v12 is delivered separately (see `source/reference/PRESENTATION_MODEL.txt`) and is for reference only.

## Known limits

- Length discrepancy, explained above.
- Ranges, masses, CG and motor and propeller data are estimates.
- The gear cables are static and cosmetic.
- The small foam bump detail is left out.
- Decals sit about 1–2.5 mm proud of the skin (shell thickness plus the anti-z-fighting offset).
- There are no LODs and no collision meshes.
- The licence is not yet chosen; see `LICENSE.txt`.
