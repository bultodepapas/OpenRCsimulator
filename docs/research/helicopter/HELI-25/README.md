# HELI-25a: HX-700 source audit and binding candidate

**Date:** 2026-10-13. **Scope:** read-only audit of the supplied Blender source and PDF, plus a static export candidate. The model is not flight-ready, is not a qualified catalog preview, and has no validated pairing with the simulator's X-Cell physics reference.

## Finding

Reuse the existing `Helicopter 3d acrobatic/HX-700_Helicoptero_RC.blend` and its embedded `generar_hx700.py` and `LEEME`; do not recreate the helicopter or resize it to match another aircraft. The source is a procedural flybarless 700-class visual design by its own embedded description. That design claim does not establish external authorship, provenance, or license. Its source SHA-256 is `cc2301bbc4fd6aa84474fb0a33de37fe721fd2ecab6e806ceafbcc6953a795cb` (1,587,270 bytes).

The identified physics reference remains the MIT X-Cell .60 SE research configuration, which has a flybar whose effects are lumped into its published model. HX-700 is flybarless. The adjacent PDF is an IlGoblin Piuma Competizione [SG779] assembly manual, not an HX-700 manual: PDF page 3 (printed page 2) identifies that model and gives nominal main/tail rotor diameters of 1,580/292 mm. HX-700's measured mesh diameters are close to those nominal figures, but this is dimension evidence only, not identity or physical-pairing evidence. The PDF has 48 pages, 47,104 extracted text characters, two pages with no native text (cover and final page), no extraction errors, and no detected license language. PDF SHA-256: `cf503309897149ca72012654cd95fea65bf407f5d8285e92d032db6619d41d9e`.

## Measured source and binding candidates

Blender 5.2.2 opens the source in metric units with `scale_length=1.0` and millimeter display. The authored values are meters. The root `HX-700` has identity transform and scale `(1, 1, 1)`. Axes in the source are +X nose-forward, +Y left, +Z up. Its hierarchy contains 25 objects including the root: 22 meshes and two empty rotor pivots. There are 21 scene materials. There are no armatures or shape keys.

| Candidate channel | Source nodes | Pivot center (source world, m) | Source spin axis (unsigned) | Measured diameter |
| --- | --- | --- | --- | --- |
| Main rotor | `Pivote_Rotor_Principal`; `Pala_Principal_A/B`; `Rotor_Cabeza` | `(0, 0, 0.345)` | `(0, 0, 1)` | 1.58273473 m (generator nominal 1.580 m) |
| Tail rotor | `Pivote_Rotor_Cola`; `Pala_Cola_A/B`; `Rotor_Cola_Buje` | `(-0.942, 0, 0.197)` | `(0, 1, 0)` | 0.29486438 m (generator nominal 0.292 m) |

The main pivot's rest Euler rotation is approximately `(0, 0, 32.0003°)`; the tail pivot is `(90.0000°, 35.0003°, 0°)`. The tail blade geometry center is `(-0.942, -0.062, 0.197) m`, offset 62 mm along -Y from its pivot center. The aircraft mesh AABB at frame 1 is min `(-1.02721608, -0.66327804, 0.0002) m`, max `(0.45807338, 0.66327798, 0.36250001) m`, size `(1.48528945, 1.32655603, 0.36230001) m`. Main blades are parked at 32°, so the AABB's Y extent is not a rotor-disk diameter.

The two driver expressions spin the main and tail pivots from the root `velocidad_rotor` custom property; the tail expression multiplies this presentation control by 4.6. They do not provide calibrated RPM, a verified physical gear ratio, or rotor physics. Missing articulation includes main-blade feathering and collective/cyclic pitch controls, swashplate lift/tilt linkage, blade flap/teeter, and tail-blade pitch control. Swashplate/link and tail-servo/link meshes are static. Thus these two spin pivots are only candidate presentation bindings.

The source evaluates to 217,892 aircraft triangles including Blender modifier evaluation; its base meshes contain 103,348 triangles. The static GLB export leaves `export_apply=false` and contains the 103,348 base triangles. These counts are from different geometry stages and should not be conflated. Two packed PNG image records refer to absent external paths and report `has_data=false` (packed sizes 46,623 and 40,510 bytes); visual texture portability should be checked before packaging.

## Export and verification

The read-only inventory script is [inventory_hx700.py](../../../../research/helicopter/assets/inventory_hx700.py). It hashes the source, inventories objects/hierarchy/materials/meshes/drivers/images, measures rotor planes from their meshes, renders orthographic views, and can export the current source hierarchy as a static preview under ignored `.tools/`. It extracts embedded texts but does not execute the source generator. It never saves the Blender source file. The concrete node/pivot mapping is [hx700_binding_candidate.json](../../../../research/helicopter/assets/hx700_binding_candidate.json).

The optional static GLB is `.tools/heli25/hx700-preview.glb` (3,086,608 bytes, SHA-256 `88424432c8cbfbc7c7278aa9c72e2188e138aa3551c2c1cf815494db281ce764`). It includes the 25 source hierarchy nodes, 22 mesh objects and both rotor pivots; it has zero animation tracks, excludes camera/light/studio geometry, and carries an `openrc_presentation_only` root marker. Blender converted the source Z-up coordinates to glTF Y-up. The [native preflight](../../../../research/helicopter/verify_hx700_preview.gd) passed 83 checks with 0 failures on Godot 4.7.2 Windows and Ubuntu/WSL: 26 nodes including import wrapper, 22 mesh instances, 62 surfaces and 103,348 triangles. It checked imported metric pivot centers and independent pivot transforms only; it does not qualify flight behavior or presentation budgets. The logs are `.tools/heli25/native-preview.log` and `native-preview-linux.log`.

The source was inspected in a separate Blender 5.2.2 background process opened with `--factory-startup`; the source file was not saved. The working-tree visual evidence is `.tools/heli25/renders/hx700-oblique.png` and the orthographic views `hx700-top.png`, `hx700-side_x.png`, and `hx700-front_x.png`. The PDF evidence includes `.tools/heli25/pdf/page-01.png`, `page-03.png`, and `page-33.png`. Generated renders and preview are ignored evidence artifacts, not committed dependencies.

From the repository root, regenerate the inventory and preview with:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup 'Helicopter 3d acrobatic\HX-700_Helicoptero_RC.blend' --python research/helicopter/assets/inventory_hx700.py -- --out .tools/heli25 --export-preview --replace-preview
python research/helicopter/assets/audit_reference_pdf.py --out .tools/heli25/pdf
$Hx700Preview = (Resolve-Path .tools/heli25/hx700-preview.glb).Path
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/helicopter/verify_hx700_preview.gd -- --glb="$Hx700Preview"
```

The source itself and the derived JSON inventory remain separate. The audit output `.tools/heli25/hx700-inventory.json` records the source hash, exact transforms, counts, driver expressions, image records, embedded-source hashes, render paths, and GLB hash.

## Open gates

- Confirm author/origin and source plus texture license before distribution or public catalog use; current provenance and license are unknown.
- Keep the supplied IlGoblin manual and HX-700 identity distinct. Do not infer that similar rotor dimensions prove the source's lineage.
- Keep HX-700 flybarless geometry distinct from the X-Cell flybar-lumped physics model. A pairing or explicitly labeled research surrogate needs separate evidence and measured alignment; no inertia, CG, aerodynamic coefficients, or gearing are inferred here.
- Add control-articulation bindings only if the source gains the corresponding real joints/rig; static meshes cannot represent those controls.
- Validate texture decode/portability and presentation budgets before packaging the GLB. The static preview is not a catalog entry and cannot fly.

See the [helicopter plan](../../../plans/helicopter.md) and [HELI-01 research record](../HELI-01/README.md) for the distinct X-Cell reference and helicopter track context.
