# Changelog — eflite_turbo_timber_evolution

## r1 — first game delivery (parallel to presentation model v12)

Built from the same parametric CAD as presentation model v12; the presentation model is unchanged.

- New export frame: metres, +X right, +Y up, nose toward −Z (glTF / simulator). Root node at datum D0.
- Neutral body pose: the 9.8° ground presentation pitch and ground offset of the v12 scene are removed.
  Wing incidence (2°), dihedral (2°), downthrust (2°) and right thrust (2°) stay built in.
- Articulations as named pivot nodes (local +X = hinge axis, right-hand rule): aileron_left_hinge,
  aileron_right_hinge, flap_left_hinge, flap_right_hinge, elevator_hinge, rudder_hinge, tailwheel_steer,
  tailwheel_axle, thrust_frame (fixed) → propeller_spin, gear_left/right_suspension → wheel_left/right_axle.
- Moving parts carry their horns and markings (rudder stripes, elevator top colours).
- Re-tessellated at 0.3 mm / 0.35 rad: 64k triangles, 36 mesh surfaces (v12 STL set: ~1.13M triangles).
- CAD tension springs (765,356 triangles, 67.5 % of the STL set) replaced by 112-triangle cosmetic cables/springs.
- Hidden or tiny parts removed (internal electronics, motor mount, shaft, screws, servo arms, pins,
  eyelets); every exclusion is listed in export-map.json.
- Overlapping decals resolved (the higher-priority marking is subtracted from the lower one, and from hull
  pieces it intrudes into), then offset 0.12 mm per priority level to remove coplanar z-fighting.
- Materials reduced to 10 glTF-safe Principled materials; one transparent (glass), two emissive (nav lights).
- Added metadata.json, export-map.json, verification.json, previews, and a demo GLB with one
  `control_demo` animation.

## Known gaps carried to r2

- Length 1.117 m vs 1.040 m reference (see README "Dimensions"). Not rescaled.
- Masses, CG, control ranges, spring stiffness are estimates.
- No inertia tensor, no textures, no LODs, no collision meshes.
