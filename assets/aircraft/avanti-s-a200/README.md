# Ventage Jet: Blender model and P100-RX integration

The catalog aircraft `sebart-avanti-s-a200-p100rx` uses the supplied Avanti S A200 Blender model through the common version-2 imported-scene contract. The experimental flight preset retains its existing JetCat P100-RX turbine with continuous RPM integration. The 13 terminal-contact witnesses now follow the imported, gear-up mesh. [AV-31 inspection and qualification](../../../docs/research/avanti-blender/AV-31/README.md) records the evidence and limitations.

## Authoritative files

| File | Purpose |
| --- | --- |
| [source/avanti_s.blend](source/avanti_s.blend) | Immutable copy of the user-supplied detailed master, with packed textures. |
| [source/geometry_blender.json](source/geometry_blender.json) | Supplied visual study and authoring estimates; original delivery bytes. |
| [export_blender.py](export_blender.py) | Reproducible preparation/export with Blender 5.2.2 LTS, build `d13f752e3b9c`. |
| [game/avanti_s_game.blend](game/avanti_s_game.blend) | Prepared editable game model: neutral controls, stowed gear, sections and packed textures. Regenerated from the master. |
| [runtime GLB](../../../app/assets/aircraft/avanti-s-a200/avanti_s.glb) | Self-contained game asset, 130,710 triangles in 19 mesh nodes; no demo animation. |
| [blender-geometry.json](blender-geometry.json) | Generated articulation rest transforms, physical-control sign mapping, model bounds, outlet observation and collision witnesses. |
| [source-manifest.json](source-manifest.json) | Master, sidecar, exporter and GLB identities; export settings and mesh counts. |
| [compile_blender.py](compile_blender.py) | Checks source/asset identity and compiles `app/aircraft/avanti_s_blender_geometry.gd`. |
| [geometry.json](geometry.json) | Existing AV-02 physical-surrogate geometry, still consumed by AV-06. Its separate compiler remains available for historical research. |

The original delivery directory `JET VENTAGE BLENDER/` is preserved. The lighter supplied GLB omitted the turbine; the prepared model therefore derives from the complete master. Internal cables and small concealed equipment are omitted from the game mesh, with the turbine, pipe, fuel tank, cockpit, skin, paint and moving surfaces retained. Simplification preserves the measured outer bounds within 2 mm; actual checks are much tighter. UVs round to six decimal places to remove one-ULP averaging differences between Blender processes. Maximum image dimension is 2048 pixels. There are 75 material surfaces and 26 materials; this is a recorded budget, not a universal fleet target.

## Coordinates, controls and configuration

Native source coordinates map to Godot metres as `(-x, z, y)`: nose −Z, right +X, up +Y. This is a proper rotation without scaling or reflection. The declared datum remains wing-root leading edge / estimated root midplane. The measured visible span is 1.996400 m and total longitudinal extent 2.235400 m; manufacturer nominal values remain 2.00 m and 2.22 m. The difference is disclosed rather than hidden by nonuniform scaling.

The common importer supplies root `airplane` and an empty `propeller` compatibility marker. Seven stable `*_hinge` nodes use local +X and a rigid rest basis. `range_deg` uses app-command degrees; `app_sign` converts those degrees into the authored axis rotation. Positive conventional commands raise both aileron/elevator trailing edges or move the rudder right. The two elevator meshes share the existing single logical elevator command. Inspector-only flaps move down at positive angles and clamp to 0–50°.

`GearRetract` frame 211 supplies the stowed geometry. The runtime does not play the source demonstration actions. Physical gear remains `locked_up`, flaps remain `not_simulated`, and the existing airborne start remains selected. These settings keep rendered geometry consistent with the admitted flight configuration. Ground contact is a terminal crash; this model integration does not enable taxiing, landing, retract controls or flap aerodynamics.

All mesh nodes and control pivots carry `openrc_section` glTF extras. Wings, horizontal/vertical tail, canopy, engine/pipe and gear can be collected by the existing crash presentation. Parts from different sections are siblings, and each control belongs to its corresponding section. These labels do not introduce structural failure physics.

## Turbine and physical boundary

The installed turbine is the existing **JetCat P100-RX, 2017 non-BL reference**: 44,000–154,000 RPM, nominal static 2–100 N, existing estimated installation loss and spool schedules. RPM, thrust, ram effects and rotor gyroscopy use the existing physics route; sound already selects turbine whine and jet roar from that telemetry. The imported turbine mesh adds no extra engine mass or force. The fixed 11.705089 kg inventory, 1.28 kg prescribed fuel, aerodynamic coefficients and physical thrust line retain their previous values.

The Blender installation and planform are visual estimates. Its engine/pipe height differs from the physical surrogate. `turbine.outlet_position` is a presentation observation from the supplied sidecar, not a validated force point; no new plume or physical thrust arm is inferred from it. Updating that installation, aerodynamic reference geometry, finite fuel or ECU behavior requires the separate [turbine plan](../../../docs/plans/turbine-realism.md) and physical identification. The current integration deliberately updates contact geometry only: AV-06 validates the 13 stable IDs and converts measured model positions to the physics LE frame.

## Regenerate and verify

From the repository root, with the exact project Godot build and Blender 5.2.2:

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
python research/aircraft-standardization/conformance.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out .tools/av31-conformance --models-only
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --path app --script ../research/avanti-s/av31/capture.gd -- --out=C:/DEVELOPMENT/OpenRCsimulator/.tools/av31-new-captures
```

Capture output must be fresh. Inspect the real rendered rest/full-travel views and turbine cutaway. Select **Ventage Jet** in the aircraft catalog, or launch with `-- --aircraft=sebart-avanti-s-a200-p100rx --quick-flight`. Source hash changes require regeneration of model manifests and Workshop descriptors; an already frozen trial refuses a changed visual dependency.

For package qualification, use the project's full Windows export, retaining its external `openrc_ground_vehicle.dll` beside the executable. A bare `--export-pack` result omits that native sidecar: `conformance.py --package` must run with the matching DLL beside its Godot executable. AV-31's [package evidence](../../../docs/research/avanti-blender/AV-31/README.md#package-qualification) records both the initial omission and successful isolated reruns; the native dependency is shared by the project, not supplied by this aircraft.
