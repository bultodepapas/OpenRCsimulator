# HELI-25: HX-700 source audit and runtime visual binding

**Date:** 2026-10-13. **Scope:** read-only audit of the supplied Blender source and PDF, static GLB export, and in-app helicopter visual binding. The app can fly this experimental trainer with the X-Cell .60 SE flybar-lumped research configuration; this is an explicitly labeled surrogate, not evidence that HX-700 has those physical dynamics or a validated pairing.

## Finding

Reuse the existing `assets/source-deliveries/hx-700-original/HX-700_Helicoptero_RC.blend` and its embedded `generar_hx700.py` and `LEEME`; do not recreate the helicopter or resize the airframe to match another aircraft. The source is a procedural flybarless 700-class visual design by its own embedded description. That design claim does not establish external authorship, provenance, or license. Its source SHA-256 is `cc2301bbc4fd6aa84474fb0a33de37fe721fd2ecab6e806ceafbcc6953a795cb` (1,587,270 bytes); the authoring file remains unchanged.

The identified physics reference remains the MIT X-Cell .60 SE research configuration, which has a flybar whose effects are lumped into its published model. HX-700 is flybarless. The adjacent PDF is an IlGoblin Piuma Competizione [SG779] assembly manual, not an HX-700 manual: PDF page 3 (printed page 2) identifies that model and gives nominal main/tail rotor diameters of 1,580/292 mm. HX-700's measured mesh diameters are close to those nominal figures, but this is dimension evidence only, not identity or physical-pairing evidence. The PDF has 48 pages, 47,104 extracted text characters, two pages with no native text (cover and final page), no extraction errors, and no detected license language. PDF SHA-256: `cf503309897149ca72012654cd95fea65bf407f5d8285e92d032db6619d41d9e`.

## Measured source and binding candidates

Blender 5.2.2 opens the source in metric units with `scale_length=1.0` and millimeter display. The authored values are meters. The root `HX-700` has identity transform and scale `(1, 1, 1)`. Axes in the source are +X nose-forward, +Y left, +Z up. Its hierarchy contains 25 objects including the root: 22 meshes and two empty rotor pivots. There are 21 scene materials. There are no armatures or shape keys.

| Candidate channel | Source nodes | Pivot center (source world, m) | Source spin axis (unsigned) | Measured diameter |
| --- | --- | --- | --- | --- |
| Main rotor | `Pivote_Rotor_Principal`; `Pala_Principal_A/B`; `Rotor_Cabeza` | `(0, 0, 0.345)` | `(0, 0, 1)` | 1.58273473 m (generator nominal 1.580 m) |
| Tail rotor | `Pivote_Rotor_Cola`; `Pala_Cola_A/B`; `Rotor_Cola_Buje` | `(-0.942, 0, 0.197)` | `(0, 1, 0)` | 0.29486438 m (generator nominal 0.292 m) |

The main pivot's rest Euler rotation is approximately `(0, 0, 32.0003°)`; the tail pivot is `(90.0000°, 35.0003°, 0°)`. The tail blade geometry center is `(-0.942, -0.062, 0.197) m`, offset 62 mm along -Y from its pivot center. The aircraft mesh AABB at frame 1 is min `(-1.02721608, -0.66327804, 0.0002) m`, max `(0.45807338, 0.66327798, 0.36250001) m`, size `(1.48528945, 1.32655603, 0.36230001) m`. Main blades are parked at 32°, so the AABB's Y extent is not a rotor-disk diameter.

The two driver expressions spin the main and tail pivots from the root `velocidad_rotor` custom property; the tail expression multiplies this presentation control by 4.6. They do not provide calibrated RPM, a verified physical gear ratio, or rotor physics. Missing articulation includes main-blade feathering and collective/cyclic pitch controls, swashplate lift/tilt linkage, blade flap/teeter, and tail-blade pitch control. Swashplate/link and tail-servo/link meshes are static. Thus these two spin pivots are only candidate presentation bindings.

The source evaluates to 217,892 aircraft triangles including Blender modifier evaluation; its base meshes contain 103,348 triangles. The static GLB export leaves `export_apply=false` and contains the 103,348 base triangles. These counts are from different geometry stages and should not be conflated. The reviewed GLB contains three embedded PNG buffer views (one tail-bolt mask and two canopy/fuselage mask images), and Godot 4.7.2 decoded them during import. The Blender source still records unresolved external image paths; keep the GLB as the source of the exported texture bytes.

## Export and verification

The read-only inventory script is [inventory_hx700.py](../../../../research/helicopter/assets/inventory_hx700.py). It hashes the source, inventories objects/hierarchy/materials/meshes/drivers/images, measures rotor planes from their meshes, renders orthographic views, and can export the current source hierarchy as a static preview under ignored `.tools/`. It extracts embedded texts but does not execute the source generator. It never saves the Blender source file. The concrete node/pivot mapping is [hx700_binding_candidate.json](../../../../research/helicopter/assets/hx700_binding_candidate.json).

The optional static GLB is `.tools/heli25/hx700-preview.glb` (3,086,608 bytes, SHA-256 `88424432c8cbfbc7c7278aa9c72e2188e138aa3551c2c1cf815494db281ce764`). It includes the 25 source hierarchy nodes, 22 mesh objects and both rotor pivots; it has zero animation tracks, excludes camera/light/studio geometry, and carries an `openrc_presentation_only` root marker. Blender converted the source Z-up coordinates to glTF Y-up. The [native preflight](../../../../research/helicopter/verify_hx700_preview.gd) passed 83 checks with 0 failures on Godot 4.7.2 Windows and Ubuntu/WSL: 26 nodes including import wrapper, 22 mesh instances, 62 surfaces and 103,348 triangles. It checked imported metric pivot centers and independent pivot transforms only; it does not qualify flight behavior or presentation budgets. The logs are `.tools/heli25/native-preview.log` and `native-preview-linux.log`.

The source was inspected in a separate Blender 5.2.2 background process opened with `--factory-startup`; the source file was not saved. The working-tree visual evidence is `.tools/heli25/renders/hx700-oblique.png` and the orthographic views `hx700-top.png`, `hx700-side_x.png`, and `hx700-front_x.png`. The PDF evidence includes `.tools/heli25/pdf/page-01.png`, `page-03.png`, and `page-33.png`. Generated renders and the preview are ignored evidence artifacts, not committed dependencies.

## Runtime visual adapter

The installed GLB is `assets/aircraft/hx-700/hx-700.glb` and its runtime copy is `app/assets/aircraft/hx-700/hx-700.glb`; both match the reviewed 3,086,608-byte preview hash above. `assets/aircraft/hx-700/rotor_profiles.json` and its runtime copy contain the 3,480-byte, GLB-bound measured coverage cache used by the blur adapter. Its rotor-local geometry stays independent of the runtime radius scale; the blur copies inherit the mount transform after the accepted aircraft data selects the physical radii. `copy_hx700_runtime_asset.py` verifies the source, GLB, profile, and manifest hashes before installing both assets and never opens or writes the `.blend` file. The manifest records source provenance, surrogate identity, axes, rotor scale adapters, profile algorithm, and the open distribution gate.

`app/aircraft/hx700_model.gd` returns the stable `{root, propeller, hinges, gear}` builder shape and adds named main/tail mount and spin pivots, model-frame axes/radii, the source root, and four skid support points relative to the measured CG. The airframe stays at scale 1.0. The axis conversion maps glTF +X/+Y/+Z to model −Z/+Y/+X. In model coordinates the X-Cell physics main shaft is −Y and tail shaft is +X; the authored visual shafts are +Y and −X, so `HeliRotorVisual` maps signed shaft telemetry through explicit negative phase signs.

The authored main radius is 0.791367 m versus the X-Cell reference radius 0.775 m. The builder exposes an idempotent alignment method for the main rotor; runtime aligns it from loaded aircraft data. The authored tail radius is 0.147432 m versus the X-Cell reference 0.13 m; the integrated route likewise aligns it from runtime data before attaching the visual driver. Neither ratio establishes a real HX-700 fit. Four lowest source skid vertices map to CG-relative contacts at about x ±0.0858 m, y −0.1098 m, and z ±0.0974 m.

`app/render/rotor/heli_rotor_visual.gd` consumes signed main/tail shaft speeds plus `a1`, `b1`, and collective in radians. It spins the two pivots, aligns the main visual shaft to MainRotor's first-harmonic normal, and preserves collective in telemetry because the source has no blade-feather hinge. Its rotor-specific crossfade reuses `PropellerBlur.blur_fraction()` and the GLB-hash-bound `PropellerBlur.profile()` coverage output; it does not route either shaft through airplane propeller animation. The sidecar cache includes blade count, coverage rings, material references, rotor-local surface paths and measured radii. Runtime verifies sidecar and GLB hashes, algorithm version, radius frame, and surface mapping before using it; a stale cache falls back to source measurement with a warning. The source profiles average 7.7% main and 11.1% tail annulus coverage, so the render adapter applies a 2.5× opacity gain to vertex coverage, clamped at full opacity; this is presentation only and does not alter cached coverage or physics. The 25-check `app/tests/test_heli_visual.gd` passes on Godot 4.7.2, including the exact shaft normal at mixed cyclic angles, both runtime radii, non-empty measured disc geometry, and the tail's own-speed blade crossfade.

From a fresh checkout, regenerate the static GLB and cached rotor coverage from the tracked source, then install the verified pair:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup 'assets/source-deliveries/hx-700-original\HX-700_Helicoptero_RC.blend' --python research/helicopter/assets/export_hx700_static.py -- --out .tools/heli25
$Hx700Profile = Join-Path (Resolve-Path .tools/heli25).Path 'hx700-rotor-profiles.json'
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --audio-driver Dummy --script ../research/helicopter/assets/export_heli_rotor_profiles.gd -- "--out=$Hx700Profile"
python research/helicopter/assets/copy_hx700_runtime_asset.py --preview .tools/heli25/hx700-preview.glb --profiles .tools/heli25/hx700-rotor-profiles.json
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --audio-driver Dummy --script res://tests/test_heli_visual.gd
```

If `.tools/heli25/hx700-preview.glb` already exists, add `--replace-preview` to the Blender command. If an installed asset differs, review it and then add `--replace` to the installer. The static exporter uses the audited inventory export routine, verifies the source and exact reviewed GLB hashes, and never saves the Blender project. The profile exporter derives its two coverage records with Godot's current `PropellerBlur.profile()` implementation and writes only under ignored `.tools`. The installer verifies hashes from the source manifest before updating either tracked asset tree. On 2026-10-13, all three steps ran successfully from a previously absent `.tools/heli25-fresh-pipeline-20261013` output directory: the export reproduced the exact reviewed GLB hash, profile JSON matched the manifest hash, and the installer verified both runtime copies; the source hash remained unchanged. The separate full audit command remains available to recreate `.tools/heli25/hx700-inventory.json`, source renders, and embedded texts.

## Integrated runtime captures

Both captures use `app/helicopter_main.tscn` with Godot 4.7.2 on Ubuntu/WSL, Mesa llvmpipe OpenGL 4.5, 1280×720. The route advanced the live session for 1.5 s before saving the frame; the HUD read altitude 3.00 m, speed 0.00 m/s, rotor 1602 rpm, collective 49%, normal mode, trainer on. The profile cache loaded without fallback warnings. The closeup shows the full main and tail swept discs; the vertical tail fin remains distinct from the tail rotor disc. The pilot view shows the same hover from the field station, where the main rotor plane is nearly edge-on.

| Capture | View | SHA-256 |
| --- | --- | --- |
| [closeup.png](../HELI-16/closeup.png) | Closeup | `5d581bcd535be0a6be98e3ca82c312178cf1f5803446a297fd272051c485b180` |
| [pilot.png](../HELI-16/pilot.png) | Pilot | `f04d4cdc0deb8114b54d0b2c2c64a989a20c7a03a5bbee70e489aa0687d16dcb` |

The full-resolution source files and command logs remain in ignored `.tools/heli-fly/` as `helicopter-closeup-final.png`, `helicopter-pilot-final.png`, `capture-closeup-final.log`, and `capture-pilot-final.log`. Both were captured with `--capture --t=1.5`; the view argument was `--view=closeup` or `--view=pilot`. Godot reported successful PNG writes and printed no missing-profile-cache warnings. This is runtime rendering evidence, not physical validation.

## Open gates

- Confirm author/origin and source plus texture license before distribution or public catalog use; current provenance and license are unknown.
- Keep the supplied IlGoblin manual and HX-700 identity distinct. Do not infer that similar rotor dimensions prove the source's lineage.
- Keep HX-700 flybarless geometry distinct from the X-Cell flybar-lumped physics model. The current flight is explicitly a research surrogate; no inertia, CG, aerodynamic coefficients, or gearing is inferred from the HX-700 source.
- Add control-articulation bindings only if the source gains the corresponding real joints/rig; static meshes cannot represent those controls.
- Confirm source/texture license and provenance before distribution. Check the integrated production capture and export dependency graph before wider packaging; Godot's successful import verifies decoding only.

See the [helicopter plan](../../../plans/helicopter.md) and [HELI-01 research record](../HELI-01/README.md) for the distinct X-Cell reference and helicopter track context.
