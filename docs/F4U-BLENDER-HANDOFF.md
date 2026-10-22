# F4U Corsair 1/5: Blender game-delivery request

2026-10-21 · Revision 1 · To the F4U Corsair model author · Request for game revision **g1**, derived from master **R59**

Thank you for R59. It is an exceptional master: gull wing, folding panels, sequenced retracts, cowl flaps, cockpit and engine are carefully built and documented. OpenRC Simulator cannot fly it directly, however. It is a full-size studio scene with millions of triangles, driver-based rigs and no game export. Please prepare a lightweight, editable **game version** at RC scale, as specified below. Keep R59 intact as the detailed master; this delivery is export preparation, simplification and separation into usable parts, not a rebuild.

This letter is self-contained. Repository links at the end are supporting evidence only.

## 1 What we found in R59

Reviewed 2026-10-21 with Blender 5.2.2 LTS (`d13f752e3b9c`), headless, scripts auto-run disabled. Source: `F4U_Corsair_R59_Blender_completo.zip` SHA-256 `e498cafc3bcffb8e215e7fbc06088c7e83c49085ffaa1018a9d51ee1425176cf`; `F4U_Corsair_R59.blend` SHA-256 `94edd59b44f578b5a1f7c1fe4004c736dff47a63e2866e4b8a04532851cf4dc3`. Measurements were taken in memory after posing the rig neutral (root at identity, demo actions unassigned, controls zero, wings spread and locked, gear down, stores off); the file was not saved.

| Item | R59 as delivered | Needed for g1 |
| --- | --- | --- |
| Scale | Full size: 12.500 m span, 10.718 m spinner tip to tail cone | 1:5, uniform: 2.500 m span |
| Frame | Root frame +X aft, +Y right, +Z up; origin near the ground plane, thrust axis at Z ≈ 2.420 m | Section 4 frame, root at D0 |
| Triangles | ≈5.66 M in 5,616 visible aircraft meshes, plus ≈0.63 M in studio, audit and store collections | 60,000–100,000 target, 150,000 ceiling |
| Heaviest parts | Propeller hub 946,448 (Subdivision); six exhaust manifolds 1.25 M; engine detail 1.71 M; cowl flaps 0.42 M; cockpit 0.38 M; wing mechanisms 0.32 M | Section 8 budgets |
| Scene content | 8,725 objects: 198 cameras, 17 lights, audit/diagnostic collections R31–R42, R51, R58 Zebra layers, superseded variants | One `EXPORT_aircraft` collection with the aircraft only |
| Materials | 160 materials (104 used by visible meshes), ≈5,800 mesh × material surfaces, 20 emission materials | ≤24 materials, ≤60 surfaces target |
| Images | 19 packed images. The 4096 × 3072 paint maps are each packed three times (`.006`, `.008`). Plan scans `F4U1D_RC_plano.png` and `Corsair_R11_plano_1.png` are packed | 2048 atlases, no duplicates, no plan scans or reference photos |
| Rig | 1,806 drivers on 938 objects (774 drive visibility), 132 constraints, custom-property controls on the root and seven control empties, three demo actions | Static pivots with local +X axes; one `GearRetract` action |
| Saved pose | Root pitched 14.49° (the root also stores 15.36°); elevators 18°, rudder 12°, trims −5°, cowl flaps 22°; demo actions assigned | Neutral, root identity |
| Names | 5,493 visible meshes contain ` \| `, 144 contain non-ASCII characters, 1,350 end in `.NNN` | ASCII, unique, no automatic suffixes |
| Crash tags | No `openrc_section` properties | Every exported mesh and pivot tagged |
| Other geometry | 622 visible curve objects (cables, hoses); the retract hose deforms during the cycle | Mesh only; rigid parts only |
| UVs | 4,869 visible meshes have no UV map | UVs on every painted exterior part |
| Variant | F4U-1D airframe without chin scoop, but the active propeller is the F4U-4 four-blade 13 ft 2 in reference; the three-blade set is hidden in `05A` | One stated variant (section 6) |
| Finish | Reno Racer "57" with an interpreted SOHIO logo | Original liveries (section 9) |

Neutral landmarks in the R59 root frame (full size, metres): spinner tip (−5.568, 0, 2.420); wingtips y = ±6.250; wing fold joint y = ±2.64; inner-panel leading edge minimum x = −2.923; rudder trailing edge x = 4.494; tail-cone end x = 5.150; main tyres 0.846 m diameter centred at (−2.650, ±1.940, 0.455); tailwheel 0.350 m centred at (3.430, 0, 1.770); propeller diameter 4.0132 m. The model is 5.5 % longer than the published F4U-1D length of 10.16 m while the span matches. Please check the nose and tail endpoints against your references and record the result; do not rescale nonuniformly to hide the difference.

## 2 Owner decisions for g1

- **Scale 1:5.** Apply one uniform factor of 0.2 to the full-size master. Expected values: span 2.500 m, length ≈2.144 m, propeller ≈0.803 m, main tyres ≈0.169 m, wheel track ≈0.776 m.
- **Retractable gear.** Deliver both main legs and the tailwheel as a sampled retraction (section 7).
- **Several liveries.** At least three original paint schemes on one shared UV layout (section 9).
- **Clean configuration.** No external stores, rockets, pylons, folding mechanism, parking struts or diagnostic content in the game file.

## 3 What to deliver

```text
f4u_corsair/g1/
  README.md                       Blender version, how to open and re-export, frame, changes from R59
  CHANGELOG.md
  LICENSE.txt                     authorship and asset terms (section 11)
  source/aircraft_game.blend      opens to the assembled neutral aircraft
  source/scripts/                 derivation, export and verifier scripts
  export/aircraft.glb             neutral runtime asset (default livery)
  export/aircraft_demo.glb        articulation and retraction reference only (optional)
  textures/liveries/<id>/         one folder per livery (section 9)
  metadata.json
  export-map.json
  verification.json
  previews/                       front, side, top, underside, three-quarter, control extremes,
                                  gear up/transit/down, exploded sections, each livery
```

1. **`source/aircraft_game.blend`** opens directly to the assembled, neutral aircraft in a framed three-quarter view. Parts are named and easy to select. It contains no drivers, constraints, linked libraries or missing caches, and includes a short text block with the export command, frame convention and node names.
2. **`export/aircraft.glb`** contains the same neutral aircraft, its pivots, materials and section tags. This is the file Godot imports.
3. **Derivation.** Preferably, a script in `source/scripts/` derives the game file from R59, so a later master revision can be re-derived. A documented manual derivation is acceptable; the game `.blend` then becomes the editable source for later revisions. Re-exporting the GLB from the game `.blend` must not require R59.

Use Blender 5.2.2 LTS and its bundled glTF exporter; do not migrate to a newer build for this delivery. The target is Godot 4.7.2 with the Compatibility renderer.

## 4 Scale, frame, datum and neutral pose

Use metres. Left and right always refer to the pilot looking forward.

| Frame | Right | Up | Nose direction |
| --- | --- | --- | --- |
| R59 root frame | +Y | +Z | −X |
| g1 Blender export scene | +X | +Z | +Y |
| GLB and Godot model | +X | +Y | −Z |

From R59 to the export scene, with D0 measured in the R59 root frame: `export = 0.2 × (r59.y, −(r59.x − D0.x), r59.z − D0.z)`. This is a proper rotation about Z plus uniform scale, without reflection. The Y-up glTF export then applies `godot = (blender.x, blender.z, −blender.y)` once.

**D0** is the symmetry plane × wing-root leading-edge station × thrust-axis height. Our estimate is x ≈ −2.923, z ≈ 2.420 in the R59 root frame; please measure it on the actual root section and record it. D0 is not the CG. The export root has zero translation and rotation and unit scale.

Apply the 0.2 factor to mesh data and pivot locations, never as an object scale. Exported node scales are exactly (1, 1, 1), without reflection or shear.

**Neutral pose:** root identity (no ground attitude baked in); all controls and trims 0, including the left aileron trim tab, elevator and rudder trims and both balance tabs; flaps 0; cowl flaps closed; wings spread and locked, fold hardware hidden; canopy closed; gear down and locked with zero oleo compression; tailhook stowed; stores and empty pylons removed; propeller at a recorded blade angle with zero visual pitch offset.

Record export-frame coordinates for: both wingtips, spinner tip, rudder trailing edge, tail-cone end, wing-root leading edge, propeller hub, every wheel centre and ground contact point, nav and landing light lenses and the exhaust stack exits. Include wheel radii, propeller diameter, hinge lines and thrust-axis direction. Measure transformed mesh vertices, not rotated bounding boxes.

## 5 Parts, crash sections and hierarchy

A moving part and a crash section serve different purposes. An aileron rotates on its own in flight but leaves with its wing in a crash. Set the string custom property **`openrc_section`** on every exported mesh and pivot, and export Custom Properties so it reaches glTF node `extras`. A collection or material name is not enough.

Supported values: `core`, `wing_left`, `wing_right`, `wing_center`, `horizontal_tail`, `vertical_tail`, `engine`, `propeller`, `gear`, `canopy`. R59 already separates the outer wing panels at the fold joint, so use it: the inverted-gull inner panels are `wing_center`, and each outer panel from the fold joint outward is `wing_left` or `wing_right`.

```text
F4UCorsair                          identity root at D0, untagged
  fuselage_core                     [core]          fuselage, windshield, cockpit interior, antenna, stowed tailhook
  canopy_glass                      [canopy]        sliding canopy glazing, closed
  canopy_frame                      [canopy]
  wing_center_fixed                 [wing_center]   both inner gull panels, root intakes, wheel-well liners
  wing_left_fixed                   [wing_left]     outer panel, tip, nav lens, landing lamp if outboard
  wing_right_fixed                  [wing_right]
  stabilizer_fixed                  [horizontal_tail]
  fin_fixed                         [vertical_tail]
  cowl                              [engine]        cowl, closed cowl flaps, engine face, exhaust stacks
  aileron_left_hinge                [wing_left]
    aileron_left                    [wing_left]     includes trim and balance tabs at neutral
  aileron_right_hinge               [wing_right]
    aileron_right                   [wing_right]
  flap_left_1_hinge                 [wing_center]
    flap_left_1                     [wing_center]
  flap_left_2_hinge                 [wing_center]
    flap_left_2                     [wing_center]
  flap_left_3_hinge                 [wing_left]
    flap_left_3                     [wing_left]
  flap_right_1_hinge … flap_right_3 (mirror, sections wing_center / wing_center / wing_right)
  elevator_hinge                    [horizontal_tail]  one common axis
    elevator                        [horizontal_tail]  both halves and horn
  rudder_hinge                      [vertical_tail]
    rudder                          [vertical_tail]    includes trim tab at neutral
  thrust_frame                      untagged; fixed shaft orientation
    propeller_spin                  [propeller]
      propeller_rotor               [propeller]     blades, spinner, hub
  gear nodes                        [gear]          section 7
```

Keep different sections as sibling branches. Never parent the rotor under `cowl`: the crash collector takes a detachable section's whole subtree. Never weld across a section boundary. Keep horns, paint, lamps and small details with their own part; for example, the left nav lens leaves with the left outer panel. Several meshes may share a section; merge pieces only when motion, section and material all permit it.

Add simple closure faces at the fold joints, wing roots, tail attachments and cowl cut where separation would otherwise reveal an empty shell. Assign each to the piece it closes, keep a small hidden gap to avoid coplanar flicker, and keep them concealed when assembled. No ribs, splinters or pre-broken debris are needed.

Node names above are the requested g1 names. Keep them unique and ASCII, with no `.001` suffixes. The Godot adapter supplies the public `airplane` root and `propeller` wrapper; do not add competing wrappers.

## 6 Articulation

Each pivot rotates about its **local +X axis**, with angle zero at its saved rest orientation: `rest × rotation_about_local_X(angle)`. Keep the actual hinge line, dihedral and shaft tilt; do not reset a correctly tilted pivot to make the transform panel read zero. The three flaps per side may have different hinge lines; each gets its own pivot, and the simulator drives all three from one flap command per side.

| Articulation | Positive direction in the delivered asset | Check range |
| --- | --- | --- |
| Ailerons | Trailing edge down | R59 ±18°; check clearance to ±25° |
| Elevator | Trailing edge down | Check to ±25° |
| Rudder | Trailing edge toward the pilot's right | Check to ±35° |
| Flaps | Trailing edge down | 0–50°; demonstrate 0°, 20°, 40° and 50° |
| Propeller | Clockwise viewed from behind toward the nose | Full revolution about the shaft |
| Wheels | Forward rolling | Full revolution about each axle |
| Tailwheel steering | Same sense as rudder | Neutral and ±30° |

These ranges are geometric clearance cases; the simulator's throws come from its aircraft data. Report the clearance envelope; do not silently clamp a surface to hide an intersection. Cowl flaps, canopy, tailhook, wing fold and trim tabs stay fixed at neutral in g1.

**Variant.** The airframe follows the F4U-1D (no chin scoop), but the active propeller is the F4U-4 four-blade reference. State which variant g1 represents. We suggest the F4U-1D three-blade propeller you already preserved in `05A`, unless the owner prefers the four-blade.

## 7 Retractable gear

The simulator replays a **sampled** retraction. It interpolates rigid carrier transforms between gear-up and gear-down; the Ventage Jet uses the same route. Please provide:

1. One action named **`GearRetract`** in the game `.blend`: frame 0 = down and locked (the neutral pose), frame 100 = fully up with doors closed, with progress uniform in frame. Include the 86° aft fold, the 90° wheel twist and the door sequence. Extension reverses the same path.
2. **Rigid carriers only.** Every moving gear part follows an object whose transform the action animates: location and rotation, unit scale. Bake drivers and constraints into the action. Replace the deforming hose with rigid segments or omit it.
3. Per wheel (`left`, `right`, `tail`), helper nodes that are correct when deployed:
   - `gear_compression_<role>`: slides along the strut axis and carries the lower oleo, axle and wheel.
   - `gear_spin_<role>`: local +X is the axle.
   - `gear_wheel_<role>`: tyre and hub mesh.
   - Tailwheel only, `gear_steer_tail`: local +Y is the steering axis, between the tail carrier and the compression node.
4. Record the authored oleo travel and the tyre radii. Doors and links that are hidden when the gear is down may be omitted from the down pose only if the action still shows them correctly.

Name carriers `gear_*`, tag them `gear`, and keep the gear subtree outside every other section. Keep the carrier count reasonable, roughly 20 or fewer.

## 8 Detail and rendering budget

The model is seen from 5 to 150 m. Protect the gull-wing outline, airfoil thickness, rounded tips, tail outlines, cowl profile, canopy profile, propeller silhouette and wheel size. Simplify hidden structure, fasteners, bevels, tubes and mechanisms first. Prefer controlled retessellation or local simplification to a global decimation that moves hinge boundaries or ruins shading.

| Group | Guide budget (triangles) |
| --- | --- |
| Fuselage, wings, tail and control surfaces | ≈40,000 |
| Propeller with spinner and hub | ≤6,000 |
| Engine face seen through the cowl (front cylinder row and gearbox only) | ≤8,000 |
| Exhaust stacks | ≤2,000 |
| Cockpit (seat, panel, stick, gunsight) plus one closed canopy glass shell | ≤8,000 |
| Gear, doors and wheels, all three legs | ≤20,000 |

Aim for 60,000–100,000 in total. 150,000 is a ceiling, not a target. Omit the engine's rear row, harnesses and mounts, internal ribs, flap actuators, hinge hardware, wing-fold mechanism, intake honeycomb geometry (use a texture or simple recess), stores and every diagnostic object. A pilot figure is not required.

## 9 Materials, UVs and liveries

Use exportable Principled materials; bake procedural appearance. Share material datablocks. Aim for **24 or fewer materials and 60 or fewer mesh × material surfaces**; report the actual count and the reason if section separation exceeds it. Keep glass to the glazing, avoid overlapping transparent shells, and enable backface culling on closed opaque shells. Verify normals, winding, smooth shading and assignments after export. Use geometry only for real relief; paint and markings belong in textures, not stacked decal shells.

**Paint regions.** Split the painted skin into separate materials so the simulator's solid-paint slots can target them: `paint_body` (fuselage and cowl), `paint_wing` (wing panels, flaps, ailerons), `paint_wing_tip`, `paint_tail` (stabilizer, fin, elevator, rudder). All regions sample the active livery's texture.

**Liveries.** Deliver at least three original schemes. Suggestions for owner review: an overall glossy dark blue, a wartime-style three-tone blue and white, and a red and ivory air-racer style with a fictional number. Mark one as the default.

- One shared, non-overlapping UV layout (`UVMap`) on every painted exterior part, identical for all liveries.
- Per livery, in `textures/liveries/<id>/`: a 2048 × 2048 sRGB base-colour atlas, an optional shared roughness/metal map, the editable layered source, and markings as separate alpha PNG layers.
- The GLB embeds only the default livery. Record each livery's `id`, name and description in `metadata.json`.
- Optionally place two empties, `marking_fuselage_left` and `marking_fuselage_right`, where a short registration of up to 12 characters fits: local +Z out of the skin, +X along the reading direction.

No real sponsor logos (including SOHIO), no real race number on a racer scheme, no real serials, squadron badges, nose art or copies of an individual photographed aircraft. If national insignia are used, keep them on a separate layer so the owner can turn them off.

## 10 Metadata, verification and package

`metadata.json` records: Blender and exporter versions, export settings, GLB SHA-256, scale factor, D0 in the R59 frame, landmarks (section 4), per-mesh and total triangle and surface counts, material and texture counts, and a `sections` list with each section's nodes. For each articulation record node, parent, member meshes, pivot, axis, local rest transform, positive direction and checked range with units. For the gear, record carriers, helper nodes, action frames, oleo travel and tyre radii.

`export-map.json` accounts for every R59 object exactly once as included, simplified or excluded, with a reason. Pattern or collection rules are acceptable if they resolve to the exact object list.

The verifier (`source/scripts/`) checks the GLB and the game `.blend` and exits nonzero when a mandatory check fails: root identity; unit node scales; ASCII unique names; every mesh and pivot carries a valid `openrc_section`; no detachable ancestor captures another section; all named pivots and gear helpers exist; no cameras, lights, drivers or constraints; `GearRetract` animates only listed carriers; counts within the stated budgets.

Export glTF 2.0 binary, Y-up, selected collection `EXPORT_aircraft` only, with Custom Properties enabled (`export_extras=True`). Disable cameras, lights and animation in `aircraft.glb`. Do not add compression extensions or material features that Godot 4.7.2 does not import. Pack all runtime images into the GLB; keep paths in the `.blend` relative or packed.

## 11 Rights and provenance

- `LICENSE.txt` states authorship and the asset terms the owner chooses. Terms left "not set" block public distribution.
- List every reference used for R59 and g1: the Royal RC F4U-1D plan, the CARF Corsair manual, photographs, museum and archive sources. Say which were only consulted and which were traced or digitized.
- Remove packed plan scans and reference photographs from the game `.blend` and GLB. They may stay in the master.
- All paint and textures in g1 are original or carry their own compatible licence and attribution.

No mass, CG, inertia or strength data are required. The simulator team chooses the physical RC hardware reference and derives the flight data. Geometry volume and material names must not be presented as mass data.

## 12 Acceptance checklist

- [ ] A clean machine opens `aircraft_game.blend` and re-exports the GLB with the documented command, without R59 or missing files.
- [ ] A clean Blender scene re-imports `aircraft.glb` at 2.500 m span with the same hierarchy, neutral pose and materials.
- [ ] Orthographic views of R59 (scaled 0.2) and g1 match in silhouette; markings stay readable in flight views.
- [ ] Root identity, metres, D0, left/right and axis conversion are correct; metadata and exported pivots and landmarks agree within 0.1 mm and 0.01°.
- [ ] Every control and gear pivot exists with the expected parent and moves its own meshes, including horns and markings.
- [ ] Positive and negative witness poses and the clearance sweep pass, and returning to zero restores neutral.
- [ ] `GearRetract` frames 0, 50 and 100 show down, transit and up with doors correct and no rigid part deforming.
- [ ] Every exported mesh and pivot carries a valid `openrc_section`; the exploded preview shows complete sections and closure faces with nothing left floating.
- [ ] Triangle, surface, material and texture counts are reported; no studio content, stores or duplicate aircraft reach the GLB.
- [ ] Each livery renders on the same UVs; the default is embedded; markings follow section 9.
- [ ] The verifier rejects a deliberately removed hinge and a missing or invalid section tag in disposable copies, with a nonzero exit.
- [ ] The package carries a revision, changelog, licence, source mapping, tool versions and GLB hash. R59 bytes are unchanged.

## 13 What we do after delivery

We will import g1 with Godot 4.7.2, verify `extras`, poses and landmarks, bind the controls, sample `GearRetract` into the retractable-gear rig, and check crash separation of each wing panel, tail, cowl, canopy, propeller and gear. We will choose the 1:5 RC hardware reference, derive flight data through our own generator, and add paint-slot and livery bindings. None of that requires changes to the Godot application from you.

## Supporting references

- [Blender aircraft delivery specification](BLENDER-AIRCRAFT-HANDOFF.md): the general authoring contract this request adapts.
- [Model and package contract](AIRCRAFT_CONTRACT.md#model-and-package-contract): imported-model construction, retraction rig and `gltf_extras` crash sections.
- [Ventage Jet asset guide](../assets/aircraft/avanti-s-a200/README.md): the sampled-retraction precedent.
- [Aircraft Workshop](AIRCRAFT-WORKSHOP.md): current paint slots and registration markings.
- [Aircraft licensing guide](AIRCRAFT-LICENSING.md): Corsair row and warbird guidance.
- R59 review scripts: [inspect_blend.py](../research/f4u-corsair/F4U-00/inspect_blend.py) and [measure_neutral.py](../research/f4u-corsair/F4U-00/measure_neutral.py).
