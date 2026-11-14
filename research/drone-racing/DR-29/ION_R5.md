# DR-29/30: ION R5 supplied visual

The owner-supplied [FPV/ION_R5.blend](../../../FPV/ION_R5.blend) is the default
visual for the experimental FPV racer, named **ION R5** in Home, the pause menu
and the OSD. Home preview, free flight and local gate races share the same
adapter. The stable vehicle ID `openrc-fpv5-x1` and direct route
`--multirotor=openrc-fpv5-x1` are preserved, including existing preferences and
recordings. The [earlier OpenRacer intake](README.md) remains a separate asset.

## Source and reproduction

The blend's `ION R5 - BUILD NOTES` describes an illustrative original concept:
220 mm true-X diagonal, 127 mm tri-blade props, metres, +Y forward, +X right,
+Z up. Its editable frame, motors, camera, electronics, harnesses, battery,
lights and markings are used. Studio objects, cameras, lights and hidden sweep
gauges are excluded. The delivery is never saved over.

Run from the repository root with Blender 5.2.2 LTS:

```sh
blender --background --factory-startup --python-exit-code 1 \
  --python research/drone-racing/DR-29/build_ion_r5.py
blender --background --factory-startup --python-exit-code 1 \
  --python research/drone-racing/DR-29/build_ion_r5.py -- --check
```

The [generator](build_ion_r5.py) produces
[ion_r5.glb](../../../app/assets/multirotors/ion-r5/ion_r5.glb) and its
[manifest](../../../app/assets/multirotors/ion-r5/manifest.json), recording
source/physics/output hashes, adaptation factors and mesh budgets. `--check`
regenerates to a temporary directory and compares both outputs byte for byte.
The [notice](../../../app/assets/multirotors/ion-r5/NOTICE.txt) records the
supplied-source scope; it does not invent a redistribution licence.

## Presentation contract

- GLB in metres, +Y up, front −Z. `airframe_root` contains one fixed body and
  `motor_1…4`, `propeller_1…4`, `camera_mount`. Rotor order: rear-right,
  front-right, rear-left, front-left. Markers retain the old motor-mount plane,
  20 mm below the physics prop plane.
- The source frame is adapted horizontally to the unchanged 205.32 mm hub
  diagonal, and vertically to the unchanged hub-to-foot span. Blade radii are
  independently fitted to the configured 129.54 mm discs and handedness is
  mirrored where needed to match the configured spin. These are visual fitting
  operations, not measurements of a real ION R5.
- Each rotating assembly has separate bell and blade meshes. The adapter moves
  those meshes onto its RPM-driven pivots, retaining static markers for audits.
  It adds no procedural motors or blades to this complete model. The shared
  propeller blur measures the actual tri-blades; motor hardware stays opaque.
  Legacy frame-only imports and the missing-model lab fixture remain supported.
  Partial complete-model exports without the camera or a bell/blade mesh also
  select the labelled lab fixture. Imported mesh ownership is cleared before
  reparenting so the instantiated scene remains consistent.
- `camera_mount` is at the adapted front optical element, with 2 mm forward/up
  clearance. The activity uses that visual mount for FPV, with existing adjustable
  tilt/FOV and its single interpolated pose. The previous data camera pivot is
  retained only for frame-only/fallback visuals. This never changes flight state.
- Output: 56,548 triangles, nine meshes, 32 materials, about 2 MB. Geometry is
  grouped by moving part; Godot's importer generates distance LODs. Native PBR
  colours, metal, roughness and race-state emission remain; Blender procedural
  weave/bump nodes are reduced to constants, with no added textures.

## Verification and limits

Verified on **2026-11-14**, Windows x86_64, Godot
`4.8.beta2.official.cafc17a19`, Compatibility/OpenGL 3.3, GeForce RTX 3090:

- Generator `--check`: byte-identical GLB and manifest; original blend unchanged.
- `test_mr_activity.gd`: **96 checks, 0 failed**, with warnings treated as errors.
  Includes Home/direct routing, every hub, camera, authored bells/tri-blades,
  disc radii, achieved RPM/spin/blur, missing geometry, controls and restart.
- `test_mr_activity_race.gd`: **19 checks, 0 failed**, also without warnings.
- Owned rendered debug session: **1920×1080** Home preview, pad, unobstructed
  FPV, stopped and powered chase views. Four achieved speeds around
  1,842–1,858 rad/s drove the imported rotor presentations; no fixture was used.
  Day and evening were reviewed. Normal Quit: no crash, zero leaked objects.

The final admitted source digest was
`74dee3d1a254a0b0c0d37fff9f9e9a327f8f8755ebcb6a8776ac792ff4df8367`.
Retained local snapshots, checked reports and captures are under
`D:\OpenRCsimulator-evidence\ion-r5-20261114\` (host-local evidence, not CI).
Scope is the visual adapter and its Home/free-flight/race consumers. This
integration does not change camera projection math, input laws or the solver.
Concurrent controller/focus changes were retained in the shared tree after the
capture; the results bind the recorded snapshot. The ION visual, HUD, catalog,
roster, activity test, flight data and GLB matched the live files; the activity's
separate focus-loss handler had changed, while its ION camera mount was intact.
The broad suite,
fresh export/package checks and required CI were not run in this local pass.

This is a visual integration over the existing estimated FPV flight model.
It does not establish ION R5 mass/inertia, powertrain, controller tuning,
real-world handling, complete collision-envelope agreement, pilot acceptance
or target-hardware performance qualification. The shared simulation kernel
and generated flight document are unchanged.
