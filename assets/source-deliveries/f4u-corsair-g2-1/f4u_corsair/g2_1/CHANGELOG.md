# g2.1 — 2026-10-24

- F1: replaced triangle-assigned `blade_tip` with one textured blade material. The exact g1.24 1024×256 image supplies the yellow band, circular badge and stencil bars on both faces of all three blades. Linear axial U makes the tip boundary square to each blade.
- F2: restored the exact g1.24 wheel meshes, UVs and gear atlas: 5,752 triangles per main wheel, 3,320 on the tail. Axles and down-pose contacts are unchanged. Existing g2 torque and retraction links remain intact.
- F3: propeller rotor 35,811 → 16,473 triangles; canopy glass 6,431 → 3,427. Blade triangles are unchanged. The local hub reduction retains 5,047 protected vertices exactly; canopy protected vertices and projected convex hulls are unchanged. See outline reports for residual sampling differences. Engine remains at 13,940 triangles; optional engine work was not added.
- F4: packed the original AO into the ORM red channel, connected the relevant materials to that shared channel, removed the standalone AO image and file, and deduplicated identical glTF texture descriptors.

# Changelog

## g2.0 — Revision 4, locally validated (external acceptance pending)

- Delivers the Naval 308 g2 runtime asset from R59 while retaining the g1.24 articulation and retraction rig unchanged. The scene opens at native frame 0; `export/aircraft.glb` is exported at frame 100 with the gear stowed.
- Accounts for all 8,725 R59 source names exactly once. The visibility-led extraction uses 260 runtime geometry contributors and 42 bake-only donors excluded from runtime; every measured zero-ray source is excluded.
- Adds the requested visible engine, cockpit, gear, wing, fold, and flap details under Revision 4’s per-part geometry and bake policy. Gunsight and left-pitot proxies are visually reviewed; their placement bases and unclaimed historical dimensions are recorded in `PROVENANCE.md`.
- Resolves six flap-seat interfaces with buried local relief using the R57 continuous upper flap lips and the two R22 wheel-well roofs. The existing rig is unchanged; the final sampled control sweep is clear through neutral–50° flap positions.
- Uses structured wheel retopology fitted to the R59 tyre/rim envelope and accepted g1 axle/contact data. The wheel profiles are approximations; the R22 retraction guide/cylinder meshes are rigid visual approximations under existing fold carriers, not a solved hydraulic linkage.
- Final asset: **349,878 triangles, 61 surfaces, 16 materials, 21,868,200 bytes**. The shared 2048 UV audit found zero multiply-covered pixels; R59 normal/AO bakes use a 2-pixel margin. Final hashes and exact counts are in `metadata.json`.
- Local validation passed: Blender native audit 22/22, GLB preflight, Godot 4.7.2 import 16/16, standalone re-export checks, sampled motion/clearance, silhouette/deviation checks, and the refreshed 19-view Eevee set including exploded sections. The re-export has only the documented sub-tolerance MikkTSpace tangent rounding; see `README.md` and `checks/standalone_reexport.json`.
- External acceptance remains pending. This package covers Revision 4 request B; the separate all-livery g1 fuselage correction is not declared complete here.
