# Jensen Ugly Stik 60: source and model guide

Checked 2026-10-19. `60` is the nominal Jensen wingspan in inches. This page owns visual authoring and commands; the [model guide/plan](../../../docs/UGLY-STIK-PLAN.md) owns delivered US work and remaining acceptance.

## Sources and pipeline

Edit [geometry.json](geometry.json) for measured/estimated geometry and [appearance.json](appearance.json) for the artistic finish. Coordinates are metres, +X right, +Y up, −Z nose. The assembly datum is not a measured CG. The [model manifest](../../../app/data/aircraft_models/jensen-das-ugly-stik-60.json) supplies the LE/thrust datum to the shared presentation contract.

| Source → generated output | Tool / home |
| --- | --- |
| Geometry → `app/aircraft/ugly_stik_geometry.gd` | [compile_geometry.py](compile_geometry.py) |
| Appearance and geometry → `app/aircraft/livery.svg`, `ugly_stik_appearance.gd` | [compile_appearance.py](compile_appearance.py) |
| Procedural grain recipe → `app/aircraft/ugly_stik_grain.res` | [bake_grain.gd](bake_grain.gd); see DT-11a below |
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

## Native builder and model interfaces

[ugly_stik_model.gd](../../../app/aircraft/ugly_stik_model.gd) builds native meshes; its raw result is `{root, propeller, hinges, gear, controls}`. Stable `airplane`, `propeller` and surface-hinge nodes feed the version-1 `euler_hinges` manifest. Static wing frames carry dihedral; child hinges carry deflection.

The [render adapter](../../../app/render/airplane.gd) updates links after surface poses, wheel spin/steering and inspector maintenance visibility. `apply_throttle()` drives the base model's carburettor/servo linkage; finite-glow visuals have a separate route. `set_maintenance()` exposes internal equipment without relocating it. Gear compression, fracture details and contact scuffs use shared presentation consumers. [Installation evidence](../../../docs/research/ugly-stik-model-v3-installation.md) records frame conversions; the model does not implement contact forces.

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
