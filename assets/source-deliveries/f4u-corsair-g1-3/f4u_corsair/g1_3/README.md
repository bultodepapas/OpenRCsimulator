# F4U Corsair g1.3 — request Revision 3, scale 1:4.5

22 October 2026. This delivery implements the supplied Revision 3 letter: uniformly scale the accepted g1.2 by **10/9**, and export the runtime GLB at **GearRetract frame 100**. It preserves g1.2's parts, topology, UVs, materials, all three livery files, node names, hierarchy and action rotations. The separate earlier paint-only delivery also named g1.3 is preserved outside this package; this package is identified by `request_revision: 3` and `scale_factor: 0.2222222222222222` in metadata.

Blender **5.2.2 LTS**, build **d13f752e3b9c**, bundled glTF exporter 5.2.40. Target: Godot 4.7.2 Compatibility. No application changes or physics data are included.

## Open and re-export

Open `source/aircraft_game.blend`. It opens in the assembled neutral editing pose with the gear down (frame 0), root identity, and a framed three-quarter viewport. Every runtime image is packed. No R59, external library or cache is needed.

Run from this package folder:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' -b source/aircraft_game.blend --disable-autoexec --python source/scripts/export.py
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' -b source/aircraft_game.blend --disable-autoexec --python source/scripts/verify.py
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' -b --disable-autoexec --python source/scripts/roundtrip.py
```

The export command explicitly selects frame 100 and passes `export_current_frame=True`. This option is necessary: otherwise this exporter uses frame 0 for static object transforms. `export/aircraft.glb` has the gear stowed and no animation, camera, light or compression extension. After export the source is saved back at frame 0 for editing. An independent folder containing only the blend, export script and metadata produced a byte-identical GLB.

## Dimensions and datum

| Quantity | Delivered value |
| --- | ---: |
| Span, transformed mesh vertices | 2.7777705 m |
| Spinner-tip to tail-cone landmarks | 2.3811179 m |
| Propeller diameter | 0.9003021 m |
| Main tyre nominal diameter | 0.1880000 m |
| Tail tyre nominal diameter | 0.0777778 m |
| Wheel-centre track | 0.8622222 m |
| Main nominal contact height below thrust axis, gear down | 0.5306667 m |
| Main oleo travel | 0.0222222 m |
| Tail authored oleo travel | 0.0277778 m |

Metres. Blender +X pilot-right, +Y nose, +Z up. GLB +X right, +Y up, -Z nose. D0 in the full-size R59 root frame is (-2.922903538, 0, 2.420000076) m. D0 defines the longitudinal wing-root leading-edge station at thrust-axis height, not the surface height or CG. The retained root-leading-edge surface point is recorded separately in landmarks.

From R59: `(1/4.5) * (old.y, -(old.x-D0.x), old.z-D0.z)`. The 10/9 migration scales mesh data, pivot locations, helper positions, parent-inverse translations and every location key and key handle, without changing object scales, orientations or UVs.

`wheels[*].ground_contact` is now the actual lowest transformed wheel-mesh vertex at frame 0; `nominal_ground_contact_m` retains the scaled authored centre-minus-radius point. Simplified tyre geometry puts the main lowest vertices 0.139–0.181 mm below that nominal height. Radius and tyre-size figures remain the accepted authored values. See `previews/dimensions.json` for both measurements. Source coordinates in `source_center` and D0 remain in the full-size R59 frame.

## Articulation and metadata

Controls rotate as `rest * rotation_about_local_X(angle)`. Positive aileron, elevator and flap moves the trailing edge down; positive rudder moves it toward pilot-right. The three flaps on each side have independent, tilted hinge lines. No control range is silently clamped.

`GearRetract` remains one slotted action: frames 0–100, 101 rigid samples, 17 animated carriers. Frame 0 is down and locked; frame 100 is stowed. Reverse playback extends the gear. The source has no drivers or constraints. Every wheel has compression and spin helpers; tail steering uses local +Y. Compression travel is an authored visual range, not an RC hardware strength specification.

`metadata.nodes` contains the **exported frame-100** world and local matrices. `metadata.nodes_down` separately stores frame-0 world and local matrices. `articulations[*].rest_matrix_local` describes each control's neutral hinge frame. Landmarks and wheel contacts are measured with gear down. Blender and GLB frame conversion is applied once. The root and thrust frame remain the only deliberately untagged nodes; every other mesh and pivot carries its existing `openrc_section`.

## Geometry and materials

**90,861 triangles; 54 mesh/material surfaces; 11 materials; 44 meshes; 80 named nodes in the GLB.** Geometry is the accepted g1.2 uniformly enlarged. Six upper fold covers remain closed and merged into wing_center_fixed; wings do not fold in this game delivery. The 0.35 mm g1.2 door bevel becomes 0.3888889 mm. No new mechanism, part or paint is introduced.

Midnight is the default; Coastal Three Tone and Scarlet 308 are alternatives on the same UV layout. The three livery directories, including editable OpenRaster sources and alpha markings, are byte-identical to g1.2. The runtime embeds only Midnight's 2048² atlas, shared by the paint materials. To switch a scheme, assign its sRGB basecolor.png to the image node on paint_body, paint_wing, paint_wing_tip and paint_tail together. Scarlet's 308 is fictional; no real sponsor, serial or squadron art is added.

## Verification

`verification.json` checks the source and GLB, including independent GLB node-transform reconstruction against the actual source at frame 100 and vertex-derived GLB span. `roundtrip.py` imports the GLB into an empty scene. The maximum reimport node-position error is 0.0001788 mm; orientation error is 0 degrees at the reported precision.

The scale witness compares all 80 object transforms at each of the 101 samples against g1.2 × 10/9. Maximum position error is 0.0002389 mm; rotation-matrix component difference is zero. Mesh topology, material assignments and UV fingerprints are identical. Negative tests reject a missing hinge, an invalid section tag, a scaled GLB exported with gear down, and the old 1:5 GLB.

Control clearances were re-run in 5° steps: ailerons/elevator ±25°, rudder ±35°, flaps 0–50°. The 21-pose door audit reports no triangle contact candidates against its listed neighbours. Propeller/wheel revolutions and tail steering witnesses pass. These are sampled geometric checks, not continuous collision detection. Actual runtime GLB renders, source orthographic views, gear down/transit/up, control extremes, exploded sections and all liveries are in previews. Selected R59-reference silhouette comparisons are regenerated at 1:4.5. Godot integration is left to the receiving team and has not been run here.

`previews/history_g1_2` holds the earlier door/cover work records at their original scale; they are not new measurements. Current numeric evidence is in scale-verification.json, dimensions.json, clearance.json, motion-witness.json, door-audit.json, roundtrip.json, surface-deviation.json and package-check.json.

## Derivation and limits

The saved game blend is authoritative. `scale_revision3.py` is a one-time migration for a full COPY of accepted g1.2; it refuses an already rescaled metadata file. Legacy derivation/detail scripts are retained for provenance, operate at the original 1:5 stage, and must not be rerun on the finished model. The paint UV raster uses the original design coordinate space so repainting does not change its proportions. The optional comparison cache used by compare.py is the original 1:5 G1_REFERENCE cache, rescaled in memory; it is not needed for export or verification.

The retained variant is F4U-1D-inspired with three propeller blades and the R49 hub/dome. The master-length discrepancy remains documented: selected simplified endpoints imply about 10.715 m full size versus cited family lengths of 10.16–10.20 m. No nonuniform scaling conceals it. Cockpit and engine are simplified. No mass, CG, inertia or strength values are inferred. R59 and all previous deliveries remain unchanged. Reference provenance and existing asset terms remain in PROVENANCE.md and LICENSE.txt.
