# Ventage Jet: Blender model and P100-RX integration

Checked 2026-10-19. Catalog aircraft `sebart-avanti-s-a200-p100rx` uses the supplied Avanti S A200 Blender model through the common version-2 imported-scene contract. Its experimental preset has continuous P100-RX RPM, finite main-tank fuel, retracts and flight flaps. This guide owns asset/build instructions; the [aircraft guide/plan](../../../docs/AVANTI-S-PLAN.md) owns current scope, pending verification and remaining work. [AV-31](../../../docs/research/avanti-blender/AV-31/README.md) is dated model/package evidence.

## Authoritative files

| File | Purpose |
| --- | --- |
| [source/avanti_s.blend](source/avanti_s.blend) | Immutable copy of the user-supplied detailed master, with packed textures. |
| [source/geometry_blender.json](source/geometry_blender.json) | Supplied visual study and authoring estimates; original delivery bytes. |
| [export_blender.py](export_blender.py) | Reproducible preparation/export with Blender 5.2.2 LTS, build `d13f752e3b9c`. |
| [game/avanti_s_game.blend](game/avanti_s_game.blend) | Prepared editable game model: neutral controls, stowed gear, sections and packed textures. Regenerated from the master. |
| [runtime GLB](../../../app/assets/aircraft/avanti-s-a200/avanti_s.glb) | Self-contained game asset, 146,652 triangles in 38 mesh nodes; no demo animation. |
| [blender-geometry.json](blender-geometry.json) | Generated articulation rest transforms, physical-control sign mapping, model bounds, outlet observation and collision witnesses. |
| [source-manifest.json](source-manifest.json) | Master, sidecar, exporter and GLB identities; export settings and mesh counts. |
| [compile_blender.py](compile_blender.py) | Checks source/asset identity and compiles `app/aircraft/avanti_s_blender_geometry.gd`. |
| [geometry.json](geometry.json) | Existing AV-02 physical-surrogate geometry, still consumed by AV-06. Its separate compiler remains available for historical research. |

The original delivery directory `assets/source-deliveries/ventage-jet/` is preserved. The lighter supplied GLB omitted the turbine; the prepared model therefore derives from the complete master. Internal cables and small concealed equipment are omitted from the game mesh, with the turbine, pipe, fuel tank, cockpit, skin, paint and moving surfaces retained. Simplification preserves the measured outer bounds within 2 mm; actual checks are much tighter. UVs round to six decimal places to remove one-ULP averaging differences between Blender processes. Maximum image dimension is 2048 pixels. There are 105 material surfaces and 26 materials; this is a recorded budget, not a universal fleet target.

## Coordinates, controls and configuration

Native source coordinates map to Godot metres as `(-x, z, y)`: nose −Z, right +X, up +Y. This is a proper rotation without scaling or reflection. The declared datum remains wing-root leading edge / estimated root midplane. The measured visible span is 1.996400 m and total longitudinal extent 2.235400 m; manufacturer nominal values remain 2.00 m and 2.22 m. The difference is disclosed rather than hidden by nonuniform scaling.

The common importer supplies root `airplane` and an empty `propeller` compatibility marker. Seven stable `*_hinge` nodes use local +X and a rigid rest basis. `range_deg` uses app-command degrees; `app_sign` converts those degrees into the authored axis rotation. Positive conventional commands raise both aileron/elevator trailing edges or move the rudder right. The two elevator meshes share the existing single logical elevator command. Flap poses use positive down angles and clamp to 0–50°.

AV-09 binds three retracts, nose steering, wheel spin, lower-strut compression and assumed main brakes. The exporter samples all twelve carriers in `GearRetract` from frame 211 (stowed) to 129 (deployed); 83 normalized poses drive the common rig from accepted physical extension. Flap rendering follows the session's actual angle. Flight controls and flap/mix behavior belong to the [aircraft guide](../../../docs/AVANTI-S-PLAN.md#1-identity-and-scope) and [First launch](../../../docs/FIRST-LAUNCH.md). The [gear](../../../docs/research/avanti-gear/AV-09/README.md) and [flap](../../../docs/research/avanti-flaps/AV-09/README.md) records retain dated software proof and physical limits.

All mesh nodes and control pivots carry `openrc_section` glTF extras. Wings, horizontal/vertical tail, canopy, engine/pipe and gear can be collected by the existing crash presentation. Parts from different sections are siblings, and each control belongs to its corresponding section. These labels do not introduce structural failure physics.

## Turbine and physical boundary

The reference is the **2017 non-BL JetCat P100-RX**. Continuous RPM, thrust, intake momentum and rotor gyro use the physics route; audio reads turbine telemetry. The imported turbine mesh adds no engine mass or force. The current aircraft consumes its declared main-tank fuel through `turbine_map_v1`; mass, CG and inertia vary with accepted fuel state. [Shared fuel behavior](../../../docs/FUEL-SYSTEM.md) owns the fixed datum, start-fill, depletion and reset contracts. Older fixed-mass figures in AV-31 describe that integration snapshot.

The Blender installation and planform are visual estimates; engine/pipe height differs from the physical surrogate. `turbine.outlet_position` is a presentation observation, not a validated force point. AV-06 validates the 13 gear-up terminal-contact IDs and converts measured model positions to the physics LE frame; retract wheel witnesses also come from the source mesh. Aerodynamic geometry and physical thrust arms remain separately authored estimates. The [turbine plan](../../../docs/plans/turbine-realism.md) tracks unimplemented ECU/thermal/pump mechanisms and remaining physical identification.

## Regenerate and verify

From the repository root, use [developer setup](../../../docs/TOOLS.md#developer-setup) and the pinned Blender 5.2.2 build. The following commands regenerate outputs for an intentional source/binding revision; routine verification uses `--check` below.

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python assets/aircraft/avanti-s-a200/export_blender.py
python assets/aircraft/avanti-s-a200/compile_blender.py
python research/avanti-s/av06/derive_physics.py
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --editor --import
python research/aircraft-standardization/build_models.py
python research/aircraft-editor/build_descriptors.py
```

Import precedes manifest generation so the `.glb.import` dependency is included. Its checked settings disable mesh compression, import no animation, and retain textures inside the imported scene as Basis Universal; no extracted PNG cache is required. The source `.blend` and GLB remain self-contained.

```powershell
python assets/aircraft/avanti-s-a200/compile_blender.py --check
python research/avanti-s/av06/derive_physics.py --check
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --script res://aircraft/verify_avanti.gd
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --script res://tests/test_retractable_gear.gd
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --script res://tests/test_retractable_gear_ground.gd
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --script res://tests/test_retractable_gear_trace.gd
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --script res://tests/test_retractable_gear_input.gd
python research/aircraft-standardization/conformance.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out tmp/avanti-conformance --models-only
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --path app --script "$PWD/research/avanti-s/av31/capture.gd" -- --out="$PWD/tmp/avanti-new-captures"
```

Capture output must be fresh. Inspect the real rendered rest/full-travel views and turbine cutaway. Select **Ventage Jet** in the aircraft catalog, or launch with `-- --aircraft=sebart-avanti-s-a200-p100rx --quick-flight`. Source hash changes require regeneration of model manifests and Workshop descriptors; an already frozen trial refuses a changed visual dependency.

For gear-specific captures, run `research/avanti-s/av09/capture_gear.gd` using the same Godot command and a fresh absolute `--out` directory. It captures accepted session fractions 0, 0.5 and 1, then nose steering; [AV-09](../../../docs/research/avanti-gear/AV-09/README.md) retains source and packaged results.

For package qualification, use the project's full Windows export, retaining its external `openrc_ground_vehicle.dll` beside the executable. A bare `--export-pack` result omits that native sidecar: `conformance.py --package` must run with the matching DLL beside its Godot executable. AV-31's [package evidence](../../../docs/research/avanti-blender/AV-31/README.md#package-qualification) records both the initial omission and successful isolated reruns; the native dependency is shared by the project, not supplied by this aircraft.
