# Jensen Ugly Stik .61 — visual model v3

`60` means the nominal 60-inch Jensen wing, not engine displacement. The target is a .61 nitro first; mini and giant are deferred.

Edit [geometry.json](geometry.json). Each parameter group records evidence and limitations. Coordinates are metres, +X right, +Y up, −Z nose. The assembly datum is not a measured center of gravity. Mass, inertia, thrust and aerodynamic coefficients belong to physics data.

From the repository root:

```bash
python3 assets/aircraft/ugly-stik-60/compile_geometry.py
python3 assets/aircraft/ugly-stik-60/compile_geometry.py --check
python3 research/ugly-stik/model-v3/check_dimensions.py
app/test.sh
bash research/ugly-stik/model-v3/capture.sh \
  --output-dir research/ugly-stik/model-v3/review-new
```

Choose a new capture output directory. The wrapper generates 36 orientation images twice and checks identical PNG hashes before publishing. `--overwrite` preserves an existing destination as a dated backup. Historical v1/v2 directories are protected. See [capture documentation](../../../docs/research/ugly-stik-model-v3-readability.md) for the separate nine-view inspection command, which also requires an explicit output directory.

The compiler writes [ugly_stik_geometry.gd](../../../app/aircraft/ugly_stik_geometry.gd); do not edit the generated copy. The [native builder](../../../app/aircraft/ugly_stik_model.gd) creates meshes and preserves `build()` → `{root, propeller, hinges}` with optional gear pivots. The [render adapter](../../../app/render/airplane.gd) retains surface commands and adds optional `apply_gear()` using raw local rotation radians. Static wing frames carry dihedral; child hinges carry commanded deflection.

The [v3 report](../../../docs/research/ugly-stik-model-v3.md) records the fuselage holdout, wing/tail traces, movement clearances, mutation proof and captures. [Installation handoff](../../../docs/research/ugly-stik-model-v3-installation.md) documents wheel contacts and axis/sign conversion; it does not implement ground forces. Equipment remains a generic .61 installation. Human readability and target-hardware performance are pending.

Godot primitives and `SurfaceTool` keep the model editable without an import dependency. The earlier GLB fixture remains an exchange experiment; its axis conversion does not apply to this native model. Third-party PDFs and derived scans stay in ignored `references/`; measured coordinates, hashes, code and selected model captures are in the repo. [Reference index](../../../docs/research/aircraft-reference-index.md).
