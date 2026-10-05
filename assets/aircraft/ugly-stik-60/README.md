# Jensen Ugly Stik .61 — geometry v3, classic red finish v4

`60` means the nominal 60-inch Jensen wing, not engine displacement. The target is a .61 nitro first; mini and giant are deferred.

Edit [geometry.json](geometry.json). Each parameter group records evidence and limitations. Coordinates are metres, +X right, +Y up, −Z nose. The assembly datum is not a measured center of gravity. Mass, inertia, thrust and aerodynamic coefficients belong to physics data.

Edit [appearance.json](appearance.json) for the classic red/white/black composition. These are artistic estimates informed by the owner's photographs, separate from geometry and flight data. `compile_appearance.py` generates both the original vector atlas `app/aircraft/livery.svg` and `ugly_stik_appearance.gd`. The latter embeds the same SVG for a single runtime rasterization with mipmaps: editor cache and third-party images are not needed to run or export the model.

From the repository root:

```bash
python3 assets/aircraft/ugly-stik-60/compile_geometry.py
python3 assets/aircraft/ugly-stik-60/compile_geometry.py --check
python3 assets/aircraft/ugly-stik-60/compile_appearance.py
python3 assets/aircraft/ugly-stik-60/compile_appearance.py --check
python3 research/ugly-stik/model-v3/check_dimensions.py
app/test.sh
python3 research/ugly-stik/model-v4/check_atlas.py --log /tmp/atlas-check.log
python3 research/ugly-stik/model-v4/check_mutations.py
bash research/ugly-stik/model-v4/capture.sh \
  --output-dir /tmp/ugly-stik-v4-review-new
```

Choose a new capture output directory. The v4 wrapper generates inspection, 36 orientation cases, detail, motion and beauty suites; repeats the orientation cases and compares all PNG hashes. It refuses existing outputs and protects historical v1/v2/v3. The offline gallery and image differences require the exact Pillow version in [requirements.txt](../../../research/ugly-stik/model-v4/requirements.txt); the runtime and compilers do not require Pillow.

For an automatic **28-image tour at 2560 × 1440**, including eleven engine views, run:

```bash
research/ugly-stik/model-v4/capture-detail.sh
```

It renders the current Godot model and writes PNGs, `manifest.json`, `capture.log`, and an offline `review.html` gallery into a new timestamped directory under `app/captures/`. Each run prints its gallery path. Use `--output-dir PATH` to choose a new destination; existing directories are rejected. Requires Python 3 and `xvfb-run`, with no gallery package installation. Categories cover the complete airplane, engine/exhaust, mounting hardware, servos, and controls. The `showcase` suite uses closer cameras and brighter fill lighting; the original comparison suites retain their cameras and resolution.

The compiler writes [ugly_stik_geometry.gd](../../../app/aircraft/ugly_stik_geometry.gd); do not edit the generated copy. The [native builder](../../../app/aircraft/ugly_stik_model.gd) creates meshes and preserves `build()` → `{root, propeller, hinges}` with optional gear pivots. The [render adapter](../../../app/render/airplane.gd) retains surface commands and adds optional `apply_gear()` using raw local rotation radians. Static wing frames carry dihedral; child hinges carry commanded deflection.

The [v3 report](../../../docs/research/ugly-stik-model-v3.md) records the fuselage holdout, wing/tail traces, movement clearances, mutation proof and captures. [Installation handoff](../../../docs/research/ugly-stik-model-v3-installation.md) documents wheel contacts and axis/sign conversion; it does not implement ground forces. Equipment remains a generic .61 installation. Human readability and target-hardware performance are pending.

The [v4 report](../../../docs/research/ugly-stik-model-v4.md) documents the atlas, scalloped trailing edge, gold-head engine and silencer, fixed-length control links, generic servos and mounting hardware. `apply_surfaces()` updates the mechanisms from existing hinge poses. `set_maintenance(airplane, true)` exposes the internal equipment; the inspector separately hides skin meshes and restores visibility per capture. It does not relocate installed components. Throttle hardware is static until the render interface receives a throttle signal.

Godot primitives and `SurfaceTool` keep the model editable without an import dependency. The earlier GLB fixture remains an exchange experiment; its axis conversion does not apply to this native model. Third-party PDFs and derived scans stay in ignored `references/`; measured coordinates, hashes, code and selected model captures are in the repo. [Reference index](../../../docs/research/aircraft-reference-index.md).
