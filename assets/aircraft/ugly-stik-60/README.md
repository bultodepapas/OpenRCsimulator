# Jensen Ugly Stik .61 — visual model v1

`60` in this directory means the nominal 60-inch Jensen wing, not engine displacement. The owner's target is a .61 nitro first; mini and giant are deferred.

The editable visual record is [geometry.json](geometry.json). Each parameter group carries its evidence and limitations. Coordinates are metres, +X right, +Y up, −Z nose. The origin is an assembly datum near the wing, not a measured center of gravity. Mass, inertia, thrust and aerodynamic coefficients are deliberately outside this visual record.

```bash
python3 assets/aircraft/ugly-stik-60/compile_geometry.py
python3 assets/aircraft/ugly-stik-60/compile_geometry.py --check
python3 research/ugly-stik/model-v1/measure_assembly.py
$(app/get-godot.sh) --headless --path app --script res://aircraft/verify_model.gd
research/ugly-stik/model-v1/capture.sh
```

The compiler writes [ugly_stik_geometry.gd](../../../app/aircraft/ugly_stik_geometry.gd); do not edit that generated copy. The [native Godot builder](../../../app/aircraft/ugly_stik_model.gd) creates the exterior geometry. The [render adapter](../../../app/render/airplane.gd) preserves the original `build()` / `apply_surfaces()` interface. Static wing frames carry dihedral while their child hinges carry only commanded rotation.

This first model uses Godot's native mesh primitives and `SurfaceTool`, which keeps it editable without adding an import dependency. The earlier GLB fixture remains a verified option for future exchange; its axis conversion is not applied to this native model.

Third-party PDFs and derived scan images remain under ignored `references/`. Our measurement coordinates, source hashes, code and captures are in the repository. See the [execution report](../../../docs/research/ugly-stik-model-v1.md), [calibration record](../../../docs/research/ugly-stik-model-v1-calibration.md), [rig checks](../../../docs/research/ugly-stik-model-v1-rig.md) and [visual inspection](../../../docs/research/ugly-stik-model-v1-visual.md).
