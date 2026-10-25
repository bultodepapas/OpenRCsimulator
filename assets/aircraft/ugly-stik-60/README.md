# Jensen Ugly Stik 60: source and model guide

Checked 2026-10-19. `60` is the nominal Jensen wingspan in inches. This page owns visual authoring and commands; the [model guide/plan](../../../docs/UGLY-STIK-PLAN.md) owns delivered US work and remaining acceptance.

## Sources and pipeline

Edit [geometry.json](geometry.json) for measured/estimated geometry and [appearance.json](appearance.json) for the artistic finish. Coordinates are metres, +X right, +Y up, −Z nose. The assembly datum is not a measured CG. The [model manifest](../../../app/data/aircraft_models/jensen-das-ugly-stik-60.json) supplies the LE/thrust datum to the shared presentation contract.

| Source → generated output | Tool / home |
| --- | --- |
| Geometry → `app/aircraft/ugly_stik_geometry.gd` | [compile_geometry.py](compile_geometry.py) |
| Appearance and geometry → `app/aircraft/livery.svg`, `ugly_stik_appearance.gd` | [compile_appearance.py](compile_appearance.py) |
| Procedural grain recipe → `app/aircraft/ugly_stik_grain.res` | [bake_grain.gd](bake_grain.gd); see DT-11a below |
| Owner's Blender O.S. 61 delivery → `app/assets/aircraft/ugly-stik-60/os61_engine.glb`, [engine-build.json](engine/engine-build.json) | [engine/build_engine.py](engine/build_engine.py); see US-V13 below |
| Changed sources/dependencies → model / Workshop identities | [Model pipeline](../../../docs/AIRCRAFT_CONTRACT.md#model-and-package-contract), [Workshop standard](../../../docs/AIRCRAFT_CONTRACT.md#workshop-authoring-standard) |

Appearance controls exhaust residue, tail spray and belly wear; disable the corresponding fields and regenerate for a clean finish. Hatch seams remain geometry. The atlas is rasterized once from embedded SVG with mipmaps, without an editor-import dependency. Grain is a separate pinned baked resource. These visual sources do not generate flight coefficients.

## Routine verification

Run from the repository root after [developer setup](../../../docs/TOOLS.md#developer-setup). Use a Linux LF checkout for Bash runners; native Windows uses `python` and the matching pinned engine. Import resources first on a fresh checkout.

```bash
python3 assets/aircraft/ugly-stik-60/compile_geometry.py --check
python3 assets/aircraft/ugly-stik-60/compile_appearance.py --check
python3 research/aircraft-standardization/build_models.py --check
python3 research/aircraft-editor/build_descriptors.py --check
GODOT="$(app/get-godot.sh)"
"$GODOT" --headless --path app --audio-driver Dummy --script res://aircraft/verify_model.gd
"$GODOT" --headless --path app --audio-driver Dummy --script res://tests/test_stik_grain.gd
python3 research/ugly-stik/model-v4/check_atlas.py --godot "$GODOT" --log /tmp/stik-atlas-check.log
```

These checks preserve source artifacts; the atlas checker writes a log and uses disposable import/mutation fixtures. Inspect engine errors as well as exit codes. `app/test.sh` owns broader integration, including gear-flex, prop-strike and soft-contact checks. [Current focused results](../../../docs/research/ugly-stik-finish-v6.md#2026-10-19-documentation-recheck) are separate from historical passing counts.

For intentional changes, run the affected compilers without `--check` in dependency order, then regenerate model/Workshop bindings. Never hand-edit generated output. Research helpers can write retained evidence: `model-v3/check_dimensions.py` rewrites its report, so use a disposable copy when preserving a baseline. Winding/rod mutations also belong in disposable copies with imported dependencies.

## Generated propeller grain (DT-11a)

[ugly_stik_finish.gd](../../../app/aircraft/ugly_stik_finish.gd) owns `generate_grain_image()`. The compressed Image resource retains every RGB8 pixel and mip level, avoiding startup noise generation. To regenerate after changing that recipe:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/assets/aircraft/ugly-stik-60/bake_grain.gd"
python research/aircraft-standardization/build_models.py
python research/aircraft-editor/build_descriptors.py
# Read-only freshness check:
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/assets/aircraft/ugly-stik-60/bake_grain.gd" -- --check
```

Commit the image and regenerated identities together. The finish helper has a procedural fallback, while the aircraft registry rejects missing/modified pinned dependencies before flight. `test_stik_grain.gd` checks pixel/mip parity. [DT-11a evidence](../../../docs/research/visual-quality-implementation/VQ-01c/loading/grain/README.md) records loading/export results.

## O.S. 61 SF engine (US-V13)

The engine is the owner's Blender model of an O.S. MAX 61 SF Special Edition on an O.S. 905 radial mount, delivered in the untracked `glow_engine_61_trabajo_completo/` folder at the repository root. [engine/source-manifest.json](engine/source-manifest.json) pins its real-time engine GLB and its aircraft-mount GLB by SHA-256. The generator keeps the delivered meshes and baked textures, then:

- splits off the carburettor lever and the propeller drive;
- decimates the screws and silicone lines;
- moves the line grommets into F1's free strip above the mount (inside the 1/4 in sides, under the hatch, clear of the throttle tube) and fails the build if a moved grommet or bent line overlaps the mount or engine;
- repairs the 21 triangles whose winding opposed their shading normals;
- halves the body atlas and writes every map as WebP;
- adds empties for the lever ball link, intake bore, silencer outlet, washer face, firewall face and the fuel and pressure grommets (where the installation's tank lines start).

```bash
.tools/blender-5.2.2-linux-x64/blender --background --factory-startup \
  --python assets/aircraft/ugly-stik-60/engine/build_engine.py            # rewrite GLB + engine-build.json
.tools/blender-5.2.2-linux-x64/blender --background --factory-startup \
  --python assets/aircraft/ugly-stik-60/engine/build_engine.py -- --check # byte-identical rebuild
```

After a rebuild, import resources and regenerate the model, customization and Workshop pins. The builder seats the mount's flange on F1. The physics-bound `prop_z` stays, so the drive hub sits 6.0 mm inside the wooden propeller hub, and the drive turns with `propeller`. Moving the hub forward the remaining 6.4 mm would be a physics change. Smoke uses the silencer-outlet anchor (4.2 mm bore), and the appearance's oil residue starts at that outlet. The throttle cable tube crosses F1 at `equipment.servo_tray.throttle_f1` (28.5, 26) mm; `verify_controls.gd` probes the exposed cable over the full throttle range, and the tube where it passes F1, against the engine. The asset costs about 150k of the model's 179k visible triangles (the native engine was 27k of 51k). Godot generates its LODs on import.

## Native builder and model interfaces

[ugly_stik_model.gd](../../../app/aircraft/ugly_stik_model.gd) builds native meshes; its raw result is `{root, propeller, hinges, gear, controls}`. Stable `airplane`, `propeller` and surface-hinge nodes feed the version-1 `euler_hinges` manifest. Static wing frames carry dihedral; child hinges carry deflection.

The [render adapter](../../../app/render/airplane.gd) updates links after surface poses, wheel spin/steering and inspector maintenance visibility. `apply_throttle()` drives the base model's carburettor/servo linkage; finite-glow visuals have a separate route. `set_maintenance()` exposes internal equipment without relocating it: the servo tray, cable tube, fuel tank and lines, receiver battery, receiver and leads ([ugly_stik_installation.gd](../../../app/aircraft/ugly_stik_installation.gd), laid out by `equipment.installation`). Gear compression, fracture details and contact scuffs use shared presentation consumers. [Installation evidence](../../../docs/research/ugly-stik-model-v3-installation.md) records frame conversions; the model does not implement contact forces.

## Captures

Use fresh destinations. These Linux runners require Xvfb/OpenGL and the pinned Godot:

```bash
bash research/ugly-stik/model-v4/capture.sh --output-dir /tmp/stik-review-new
bash research/ugly-stik/model-v4/capture-detail.sh --output-dir /tmp/stik-detail-new
# Only engine/exhaust closeups:
bash research/ugly-stik/model-v4/capture-detail.sh --engine --output-dir /tmp/stik-engine-new
# Production-lighting bench:
bash research/ugly-stik/finish-v6/capture.sh /tmp/stik-finish-new
```

The full v4 runner captures inspection, orientation, detail, movement and beauty views, then repeats 36 orientation PNGs for hash comparison. Its gallery/differences require exact [Pillow 11.3.0](../../../research/ugly-stik/model-v4/requirements.txt). The detail runner creates a 28-image tour at 2560×1440 (11 with `--engine`); its gallery uses the standard library. Existing artifacts and protected historical destinations are rejected by the relevant runners.

Third-party drawings/photos remain in ignored `references/`; committed metrology and source hashes preserve provenance. Optional scan overlays require that local cache. [Research evidence](../../../docs/research/ugly-stik-finish-v6.md) retains visual limits. Pixel repeatability and headless geometry checks do not establish pilot readability or target-GPU cost.
