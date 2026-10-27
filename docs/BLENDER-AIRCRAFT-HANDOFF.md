# Turbo Lumber Evolution r2 Blender aircraft delivery for OpenRC Simulator

2026-10-13 · Revision 2 · To the aircraft model developer · Delivery specification for Turbo Lumber Evolution r2

For new airplanes and their skins, use the [reusable Blender handoff](BLENDER-AIRCRAFT-DELIVERY.md). This document retains the Turbo Lumber Evolution-specific dimensions, rig, budgets and accepted-delivery corrections; it is not a template for other aircraft.

**Delivery status, 2026-10-13:** r2 `d75ae605aa3a` has been received and integrated. The requirements below remain the authoring contract; do not recreate the accepted package. The [TT-19 review](research/timber-integration/TT-19/README.md) records its source identity, native Godot captures, accepted behavior and remaining source corrections, including cowl marking seating and assembled closure-face visibility.

For the next source revision, preserve the accepted shape, pivots and section IDs. Fix the remaining white cowl foam showing through the black/red marking shells; make the coating conform to the skin or use material regions, and fail verification when covered foam still protrudes. Keep the separation caps, but ensure the white wing-root closure faces are hidden when assembled. Review the 49 material surfaces against the soft budget of 40. Keep the suspension link and bracket identifiable if checking their clearance: intersecting a whole merged leg with the entire fuselage also includes its mechanical attachment. OpenRC currently leaves suspension static and uses a temporary 0.8 mm render-only offset on the cowl's two marking materials; a corrected source should make that offset unnecessary. These are incremental corrections to r2.

Please prepare a lightweight, editable game version of the existing precise aircraft. Preserve its silhouette, proportions, control surfaces and recognizable finish. The requested work is export preparation, simplification and separation into usable parts. Keep the detailed master intact.

The aircraft is called **Turbo Lumber Evolution** in OpenRC Simulator and **Turbo Timber Evolution** in the source package. The simulator already imports and flies the r1 model. We now need a convenient `.blend`, a self-contained `.glb`, correctly articulated controls and real sections that can detach in a crash. This specification includes everything needed to prepare that delivery; repository links at the end are supporting evidence only.

## 1 What to deliver

Deliver a new `r2/` package with these three usable entry points:

1. **`source/aircraft_game.blend`** opens directly to the assembled, neutral aircraft. Parts are named and easy to select. Geometry and materials are editable without rebuilding the CAD first.
2. **`export/aircraft.glb`** contains the same neutral aircraft, its pivots, materials and section tags. This is the file Godot imports and the game ships.
3. **`README.md`** gives the exact Blender version, how to open and re-export, the configuration, coordinate convention and changes from r1. One documented export command or saved preset must reproduce the delivery.

Reuse the existing model and exporter. Use Blender's existing glTF exporter and available tools. Further aircraft reconstruction, custom destruction software and extra presentation detail are outside this delivery.

The target is the project's pinned **Godot 4.7.2, Compatibility renderer**. Blender is an authoring tool, not a requirement for running the simulator. Deliver with the exact Blender/exporter build you have verified; do not migrate the source merely to use a newer version.

## 2 What already works and what needs to change

The accepted r1 GLB has **64,291 triangles, 15 mesh nodes, 36 material surfaces and 10 materials**. It already has six control-surface hinges, propeller spin, wheel spin, tailwheel steering and main-gear suspension pivots. Preserve that work.

The main limitation is the single `airframe` mesh: it combines the fuselage, fixed wings, tail, glazing and cowl in **36,691 triangles**. The simulator currently reconstructs crash sections from a generated triangle map. The cowl skin is welded into the fuselage, so it cannot detach cleanly. For r2, export those structural sections as separate objects with explicit tags.

The original v12 spring meshes contained 765,356 triangles. r1 already replaced them with 112 cosmetic triangles. Keep that simplification; detailed coils, screws and hidden electronics add little to a flight view.

## 3 Parts and crash sections

**A movable object and a crash section serve different purposes.** The aileron rotates independently while flying, but belongs to its wing when that wing detaches. Several separate objects can share one crash section.

Set the string custom property **`openrc_section` on exported Blender objects**, including the corresponding moving pivots. Export Custom Properties so it reaches glTF node `extras`. A Blender collection name, material name or loose island inside one mesh is insufficient.

| Export object or assembly | Keep separate for | `openrc_section` |
| --- | --- | --- |
| `fuselage_core` | Main fuselage and fixed central structure | `core` |
| `wing_left_fixed`, `wing_right_fixed` | Each fixed half-wing, including its tip, markings and light lenses | `wing_left`, `wing_right` |
| `aileron_left`, `aileron_right` and their hinges | Independent roll controls; detach with the matching wing | `wing_left`, `wing_right` |
| `flap_left`, `flap_right` and their hinges | Independent flaps; detach with the matching wing | `wing_left`, `wing_right` |
| `stabilizer_fixed`, `elevator` and `elevator_hinge` | Fixed horizontal tail plus independently rotating elevator | `horizontal_tail` |
| `fin_fixed`, `rudder` and `rudder_hinge` | Fixed fin plus independently rotating rudder | `vertical_tail` |
| `cowl` and any visible fixed motor details | Cowl must separate from fuselage and rotor | `engine` |
| `propeller_rotor` and `propeller_spin` | Blades, spinner and actual rotating hardware | `propeller` |
| `canopy_glass` and any detachable glazing frame | Glazing assembly | `canopy` |
| Existing gear legs, wheels, fork, cables and their pivots | Separate articulation; current crash system groups them together | `gear` |

The complete supported vocabulary is `core`, `wing_left`, `wing_right`, `wing_center`, `horizontal_tail`, `vertical_tail`, `engine`, `propeller`, `gear`, `canopy`. Use `wing_center` only if a distinct removable center panel actually exists. No extra cut is required. `engine` is the simulator's nose-assembly category; it does not mean the cowl spins.

Use one section per exported mesh. Merge small pieces only when **motion, section and material treatment all permit it**. Never weld across a section boundary. Keep horns, paint, lamps and attached details with their correct part. For example, the left navigation lens must leave with the left wing.

Keep different crash sections as sibling branches. Do not put the rotor under an object tagged `engine`: the crash collector takes the first detachable section's whole subtree. Leave the aircraft root and `thrust_frame` untagged. `core` objects remain with the fuselage; the collector can still inspect their tagged children.

**Visible break faces:** add simple closure faces at the wing roots, tail attachments and cowl cut where detachment would otherwise reveal an empty shell. Assign each closure to the piece it closes; leave a small hidden separation to avoid coplanar flicker. Keep them concealed inside the assembled airplane. A plain foam/interior material is enough. No internal rib network, splinters, pre-shattered debris or alternate damaged model is required.

The current system groups all `gear` objects into one crash section, and the horizontal tail into one section. Separate wheel or elevator objects do not automatically create independent damage events. The simulator controls release timing, debris motion, contact and effects. This delivery enables section separation; it does not implement flying with a broken wing or physically validated fracture strength.

## 4 Preserve the hierarchy and articulation

Retain the r1 pivot names, parent relationships and rest transforms. Replace the merged fixed `airframe` with sibling section meshes. This avoids changing the meaning of the working controls. The minimum structure is below; bracketed values are object properties, not parts of the names.

```text
TurboTimberEvolution                         identity root at D0
  fuselage_core                             [core]
  wing_left_fixed                           [wing_left]
  wing_right_fixed                          [wing_right]
  stabilizer_fixed                          [horizontal_tail]
  fin_fixed                                 [vertical_tail]
  cowl                                      [engine]
  canopy_glass                              [canopy]
  aileron_left_hinge                         [wing_left]
    aileron_left                            [wing_left]
  aileron_right_hinge                        [wing_right]
    aileron_right                           [wing_right]
  flap_left_hinge                            [wing_left]
    flap_left                               [wing_left]
  flap_right_hinge                           [wing_right]
    flap_right                              [wing_right]
  elevator_hinge                            [horizontal_tail]
    elevator                                [horizontal_tail]
  rudder_hinge                              [vertical_tail]
    rudder                                  [vertical_tail]
  thrust_frame                              fixed shaft orientation
    propeller_spin                          [propeller]
      propeller_rotor                       [propeller]
  gear_left_suspension                      [gear]
    gear_left_leg                           [gear]
    wheel_left_axle                         [gear]
      wheel_left                            [gear]
  gear_right_suspension                     [gear]
    gear_right_leg                          [gear]
    wheel_right_axle                        [gear]
      wheel_right                           [gear]
  tailwheel_steer                            [gear]
    tailwheel_fork                          [gear]
    tailwheel_axle                          [gear]
      tailwheel                             [gear]
  gear_cables                               [gear]
```

Fixed section mesh names above are the r2 naming request; existing moving names are compatibility requirements. Keep identifiers unique, ASCII and without automatic `.001` suffixes. The Godot adapter supplies the public `airplane` root and `propeller` wrapper; do not add competing wrappers in Blender.

Preserve **local +X as each pivot's rotation axis**, with angle zero at its saved rest orientation. Apply a local rotation after that rest orientation: `rest * rotation_about_local_X(angle)`. Keep the actual hinge line, dihedral and shaft tilt. Do not reset a correctly tilted pivot's rotation just to make the transform panel read zero. Apply unwanted scale or mirror transforms to export geometry before finalizing the pivots; exported node scales should be `(1, 1, 1)` without reflections or shear.

| Articulation | Positive direction in the delivered asset | Check range |
| --- | --- | --- |
| Ailerons | Trailing edge down | r1 authored ±22°; also test the current simulator's approximately ±34.5° |
| Elevator | Trailing edge down | r1 authored ±22°; current simulator approximately ±17.8° |
| Rudder | Trailing edge toward the pilot's right | r1 authored ±30°; current simulator approximately ±18.2° |
| Flaps | Trailing edge down | 0–40°; demonstrate 0°, 20.7° and 36.6° |
| Propeller | Clockwise viewed from behind toward the nose | Full revolution about the tilted shaft |
| Wheels | Forward rolling | Full revolution about each actual axle |
| Tailwheel steering | Same steering sense as r1 and rudder | Neutral and ±30° |
| Main suspension | Leg swings outboard | r1 authored 0–12° |

The simulator's angular throws come from manual linear travel at assumed measurement stations. They are geometric clearance cases, not new measured hardware limits. In particular, resolve the aileron ±22° versus ±34.5° discrepancy in the metadata: preserve both sources and report the clearance envelope. Do not silently clamp the flight controls to hide an intersection.

Keep wheel rotation independent of steering and suspension. Keep motor mounts and the cowl outside the spin subtree. The one-piece elevator remains one articulated assembly. Flaps and suspension need usable pivots, but their demo does not imply live flight or suspension support. Static gear cables may remain cosmetic if that limitation is stated.

## 5 Units origin and neutral pose

Use metres throughout the game scene and GLB. Left/right always refer to the pilot looking forward.

| Frame | Right | Up | Nose direction |
| --- | --- | --- | --- |
| r1 Blender export scene | +X | +Z | +Y |
| GLB and Godot aircraft model | +X | +Y | −Z |

Retain the existing conversion **`godot = (blender.x, blender.z, -blender.y)`**, applied once by the Y-up export. If CAD inputs remain in millimetres with X aft, Y right, Z up, their conversion is `godot = (cad.y, cad.z, cad.x) / 1000`.

Keep **D0 at the symmetry plane, wing-root leading-edge station and the original CAD thrust-axis height before thrust-angle rotation**. The root has zero translation/rotation and unit scale. D0 is not the CG. Preserve authored wing incidence, dihedral and down/right thrust; do not bake the approximately 9.8° three-point ground attitude or a floor offset into the export. Controls and flaps are neutral, wheels installed, no floats and no slats.

Record root-frame coordinates for both wingtips, spinner tip, rudder trailing edge, wing-root leading edge, all wheel centers/contact points and the propeller hub. Include wheel radii, propeller diameter, hinge lines and thrust-axis direction. Measure transformed mesh vertices, not the corners of rotated bounding boxes.

The measured r1 span is **1.5479 m including lenses**, and length is **1.1166 m from spinner tip to rudder trailing edge**. The selected manual reference gives 1.555 m and 1.040 m. Preserve r1 scale while preparing the game asset. A nose correction requires a separately documented, calibrated reference and endpoint comparison; do not uniformly rescale the aircraft to remove the length difference or change its geometry to fit an estimated CG.

## 6 Detail and rendering budget

Protect the wing and tail outlines, airfoil thickness, leading edges, wingtip shape, canopy profile, propeller silhouette and wheel diameter. Simplify hidden structure, tiny bevels, fasteners, dense tubes, tread and ornamental mechanisms first. Prefer controlled CAD retessellation or local simplification to a global decimation that moves hinge boundaries or destroys shading.

For r2, aim for **30,000–50,000 visible triangles** if the outline and shading survive. Keeping approximately r1's 64,000 is acceptable when a lower count visibly damages the model. The previous 100,000-triangle allowance is an outer planning ceiling, not a target to fill. These are authoring budgets, not measured frame-rate guarantees.

Aim for **40 or fewer exported material surfaces**, counted as mesh × material primitives across the aircraft. Splitting the required sections can exceed that r1 target; report the resulting count and reason instead of welding the aircraft back together. Keep the existing ten materials or fewer where practical. Share material datablocks. A low object count alone does not establish low rendering cost.

Prefer base color or a shared texture atlas for paint stripes over stacked geometric decal shells. If textures are needed, start with one 2048 × 2048 atlas for opaque painted surfaces, with small separate glass/emission treatment as necessary. Include editable image sources and pack runtime images into the GLB. An atlas is optional; the existing solid-color approach is valid if it meets the surface budget and looks clean.

Use exportable Principled materials; bake necessary procedural appearance. Keep glass limited to glazing, avoid overlapping transparent shells, and check against both sky and ground. Verify normals, winding, smooth shading, UVs and material assignments after export. Enable backface culling for closed opaque shells; use two-sided rendering only where the shape needs it. Reject degenerate triangles, unintended duplicates and flickering paint.

Manual LODs are optional for a later measured optimization. If supplied, they must preserve silhouette, section assignments, pivots and neutral pose, and be separate named exports. Do not include several visible copies of the aircraft in the main GLB.

## 7 Make the Blender file easy to use

Keep one obvious `EXPORT_aircraft` collection containing the final assembled game asset. Use clearly named source/reference and preview collections outside it only when useful. Open the file in a framed three-quarter view with the Outliner organized, no hidden duplicate aircraft and all controls at zero. Include a short Blender text block with the export command, frame convention and control names.

Keep editable modifiers and source construction in the master where helpful; the game file must contain the usable geometry without missing CAD caches, add-ons or linked libraries. Store necessary paths relative to the package and pack or include all textures. Preserve a separate detailed master or reference its existing revision; do not duplicate large STEP/STL archives merely to repeat what was already delivered.

The export collection must exclude studio cameras, lights, floor, reflectors, dimension helpers, CG markers and physics bodies. Optional reference anchors belong in metadata or a non-export collection. The simulator already constructs flight contact data and wreck collision shapes; custom Blender collision objects are not required for r2.

## 8 Export and package

Export glTF 2.0 binary **GLB**, Y-up, only `EXPORT_aircraft`, with meshes, hierarchy, materials and **Custom Properties enabled** (`export_extras=True`). Disable cameras, lights and animation in `aircraft.glb`. Evaluate the intended mesh modifiers without flattening the object hierarchy or losing pivots. Do not add compression extensions or material features that have not been checked in the pinned Godot importer.

Provide the articulation demo separately. It should show one control at a time, neutral and both directions, wheels/propeller spinning, and return to neutral. A simple exploded preview should show the crash sections and their closure faces. A Blender animation is demonstration evidence; Godot drives the controls itself.

```text
turbo_timber_evolution/r2/
  README.md
  CHANGELOG.md
  LICENSE.txt
  source/aircraft_game.blend
  source/scripts/                  export, validation and required build tools
  export/aircraft.glb              neutral runtime asset
  export/aircraft_demo.glb         articulation reference only
  metadata.json
  export-map.json
  verification.json
  previews/                       front, side, top, underside, three-quarter,
                                  control extremes and exploded sections
  textures/                       only when image sources are needed
```

Keep the r1 metadata structure where practical. Add a `sections` list containing each section ID and its exported nodes. For each articulation retain node, parent, mesh members, pivot, axis, named coordinate frame, local rest transform, positive direction and range with units/source. Each visible object belongs to exactly one section. The export map must account for every source part exactly once as included, simplified or excluded, with a reason.

Record the GLB hash, exact tool versions, export settings and per-mesh/total triangle and surface counts. New metadata is delivery information, not a replacement for the simulator's `openrc-aircraft v2` physics file. Document renamed/deleted nodes and changes to dimensions, datum, hinges or materials in the changelog.

Document a complete r2 export path that works from a clean copy without files from the author's machine. Re-exporting the delivered game `.blend` must work independently of CAD regeneration. If r2 also retains the CAD rebuild pipeline, include the missing BREP-cache step and reconcile producer/consumer paths for that cache, `escena.json` and `stl_juego`; otherwise label CAD rebuilding unsupported and preserve the source as reference. The verifier must exit nonzero when a mandatory check fails.

Keep authorship and the owner's chosen asset terms in `LICENSE.txt`; do not infer them from the simulator code license. Reuse supplied or suitably licensed assets instead of creating additional stock props or textures.

## 9 Physical information to preserve

For dimensions and any supplied physical quantity, state value, unit, evidence type and source; add uncertainty when known. Distinguish model measurements, manual values and estimates. Preserve the exact configuration and the station at which a millimetre control throw was measured.

The r1 **1.46 kg partial estimated ledger is not flight-ready mass data**. Label it explicitly as a non-flight placeholder if retained. The project's selected manual reference is 2.190 kg with the recommended battery, also not a measurement of this particular aircraft. Geometry volume, material names and crash-section labels must not create new mass, CG, inertia or strength values. Supply actual measurements if available; the simulator team owns flight-data derivation and validation.

## 10 Delivery acceptance checklist

- [ ] A clean machine can open the game `.blend`, inspect every part and export using the documented command without missing files.
- [ ] A clean Blender scene can reimport `aircraft.glb` with the same dimensions, neutral pose, hierarchy and materials.
- [ ] Matching orthographic views of the master and game model preserve the silhouette; top/bottom markings remain readable in representative flight views.
- [ ] Root identity, metres, D0, left/right and axis conversion are correct. Metadata and exported landmarks/pivots agree within 0.1 mm, and axes within 0.01°. These are export-consistency tolerances, not real-aircraft accuracy claims.
- [ ] All 13 existing moving pivots remain present with their expected parents; each moving mesh follows its correct pivot, including horns and markings.
- [ ] Positive/negative witness poses and the full requested clearance sweep pass. Returning to zero restores the delivered neutral pose.
- [ ] Every exported mesh and moving pivot has its valid `openrc_section`. Left/right wings, cowl, glazing, tail, propeller and gear remain separable after reimport.
- [ ] An exploded view shows complete sections, clean closure faces and no paint or hardware left floating at the original position.
- [ ] The report counts the exported triangles, surfaces, materials and textures, including closure faces. No studio content or duplicate aircraft reaches the GLB.
- [ ] The verifier rejects a deliberately missing hinge and missing/invalid section tag in disposable copies, with a nonzero process exit.
- [ ] The package has a revision, changelog, source mapping, tool versions, hash and known limits. No r1 delivery bytes are overwritten.

## 11 Simulator integration responsibilities

After delivery, we will import r2 in the pinned Godot build, verify `extras`, compare geometry/poses against r1, and run a crash that releases the left wing with its aileron/flap while leaving the right wing intact. We will also check cowl separation, gear articulation, propeller behavior, reset and independent instances, then measure rendering cost in flight and during a crash.

**r2 is not a drop-in replacement for the current hashed r1 file.** We will update the source manifest, measurements, generated geometry and adapter bindings, replace the r1 triangle-map path for the sectioned asset, and update checks that currently expect one `airframe` mesh. Blender delivery work does not require editing the Godot application or inventing a second merged flight model. Any physics changes caused by corrected geometry will be reviewed through the existing data generator separately.

## Supporting references

This revision restores the developer letter originally committed on 2026-10-08 (`6a3aac4b`, also present as `1504ed82`) and updates it for the imported r1 model and current section-based crash system. It is the current author-facing delivery specification. Step status stays in the Turbo Lumber Evolution plan; historical audits remain dated evidence.

- [Turbo Lumber Evolution integration plan](TIMBER-INTEGRATION-PLAN.md) and [current asset guide](../assets/aircraft/turbo-lumber-evolution/README.md).
- [Independent r1 contract review](research/timber-integration/TT-00-R1/contract-review.md), [articulation evidence](research/timber-integration/TT-05/README.md) and [real-part breakup evidence](research/crash-damage-investigations/CR-09c/README.md).
- [Current Turbo Lumber Evolution adapter](../app/aircraft/timber_model.gd) and [crash section consumer](../app/render/crash/wreck.gd).
- [Blender glTF exporter documentation](https://docs.blender.org/manual/en/latest/addons/scene_gltf2.html): custom properties export as glTF extras; supported material and collection-export options.
- [Godot 3D import documentation](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html): GLB delivery, direct Blender import dependencies and backface-culling behavior.
