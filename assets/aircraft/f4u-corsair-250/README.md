# F4U Corsair 1/4.5: sources and pipeline

Checked 2026-10-23. `f4u-corsair-250` is an experimental catalog aircraft: a 2.778 m, 1/4.5-scale F4U-1D of the CARF-Models class, powered by a Moki S250 five-cylinder radial with a 30x18 three-blade. The author's g1.13 visual model (F4U-15) is frozen in `assets/source-deliveries/f4u-corsair-g1-13/` and identified by [source-manifest.json](source-manifest.json); the earlier g1.3 freeze stays for the F4U-04…12 evidence. The [F4U plan](../../../docs/F4U-PLAN.md) owns scope, steps and owner decisions.

## Sources

| File | Content |
| --- | --- |
| [source.json](source.json) | Authored inputs (format v2): D1 CARF-Models F4U-1D 1:4.5, D4 30x18 three-blade, D5 Moki S250; two mass anchors for this kit; the CARF manual's setup; three smaller Corsair setups for CG, low rates and expo; the Moki operating points; NACA full-size data; measured NACA 23012/23015 sections with XFOIL thickness trends; Roskam slotted-flap digitization. Edit only here. |
| [geometry-r59.json](geometry-r59.json) | Generated: 1/4.5 geometry measured on the R59 master (sections, control surfaces, fuselage, nose, hull points, gear and retraction paths). g1.3 landmarks agree within 0.3 mm (F4U-06). |
| [source-manifest.json](source-manifest.json) | Generated: SHA-256 and size of every frozen g1.13 delivery file, the author's hashes of the files deliberately not copied, key files by role, the five livery GLBs, visual revision `g1.13-03d66d8dc142`. |
| [gear-samples.json](gear-samples.json) | Generated in Blender from the frozen game source: 101 parent-local `GearRetract` carrier poses (sample 0 stowed), wheel-centre paths, midpoint error. |
| [wing-fold-r59.json](wing-fold-r59.json) | Generated: R59's wing-fold rig in R59 coordinates (pivots, axis, sign, 112°, lock-release law) and Blender's folded navigation-lamp check (F4U-17). |
| [model-geometry.json](model-geometry.json) | Generated: the model family's geometry source (control hinges, thrust frame, gear rig, wing folds, the five liveries), compiled into `app/aircraft/f4u_corsair_geometry.gd`. |

Coordinates are metres in the physics le frame, [x_aft, y_right, z_up], from the root leading edge on the centreline at thrust-line height. This is the delivery request's D0, so g1.13 model coordinates map as `[x_aft, y_right, z_up] = [z_model, x_model, y_model]`.

## Pipeline

| Step | Tool | Output |
| --- | --- | --- |
| R59 → 1/4.5 geometry | [extract_geometry_r59.py](../../../research/f4u-corsair/F4U-06/extract_geometry_r59.py) (Blender 5.2.2, headless, `-Y`) | `geometry-r59.json`; a research operation, R59 stays outside the repository |
| Gull-wing ground effect | [ground_effect_vlm.py](../../../research/f4u-corsair/F4U-07/ground_effect_vlm.py) | `research/f4u-corsair/F4U-07/vlm_ground_effect.json` |
| Propeller calibration | [fit_propeller.py](../../../research/f4u-corsair/F4U-07/fit_propeller.py) | `research/f4u-corsair/F4U-07/prop_calibration.json` |
| Physics derivation | [derive_physics.py](../../../research/f4u-corsair/F4U-07/derive_physics.py) | `app/data/aircraft/f4u_corsair_250.json` and `research/f4u-corsair/F4U-07/derivation.md` |
| Crash-economics costing | [costing_entry.py](../../../research/f4u-corsair/F4U-11/costing_entry.py), then `research/crash-economics/build_runtime.py` | the Corsair entry in `research/crash-economics/aircraft-costing.json`, `app/data/economy/catalog.json` |
| Loader and trim probe | [probe.gd](../../../research/f4u-corsair/F4U-07/probe.gd) | Console checks |
| Delivery preflight | [preflight_glb.py](../../../research/f4u-corsair/F4U-04/preflight_glb.py) | Pass/fail per delivery GLB |
| Delivery identity | [manifest.py](../../../research/f4u-corsair/F4U-03/manifest.py) | `source-manifest.json` |
| Gear sampling | [sample_gear.py](../../../research/f4u-corsair/F4U-05/sample_gear.py) (Blender 5.2.2, headless, `--disable-autoexec`) | `gear-samples.json` |
| Wing-fold rig | [extract_wing_fold.py](../../../research/f4u-corsair/F4U-17/extract_wing_fold.py) (Blender 5.2.2, headless, `-Y`) | `wing-fold-r59.json`; R59 stays outside the repository |
| Runtime livery GLBs | [install_liveries.py](../../../research/f4u-corsair/F4U-16/install_liveries.py) | The four other g1.13 livery GLBs in `app/assets/aircraft/f4u-corsair-250/`, byte for byte, with the default model's import settings (F4U-16) |
| Model compile | [compile_model.py](../../../research/f4u-corsair/F4U-05/compile_model.py) | `model-geometry.json`, `app/aircraft/f4u_corsair_geometry.gd` |
| Model contract | [verify_f4u.gd](../../../app/aircraft/verify_f4u.gd), run by `app/test.sh` | Console checks: frozen asset, controls, flaps, throws inside the clearance envelopes, gear rig, oleo compression, propeller size, exhaust, paint slots, contacts, crash release, wing folds |
| Flight-test card | `research/flight-test/run.py --aircraft f4u-corsair-250 --out <new directory>` | Profile and summary ([F4U-12](../../../docs/research/f4u-corsair/F4U-12/README.md)) |
| Ground handling | [ground_handling.gd](../../../research/f4u-corsair/F4U-12/ground_handling.gd) | JSON: tail lift and lift-off against the CARF take-off note |
| Retracts, flaps and smoke | [systems_check.gd](../../../research/f4u-corsair/F4U-12/systems_check.gd) with the windowed Godot and `--rendering-driver opengl3` | `checks.json` and screenshots in a new directory outside the repository |
| Wing fold in the flight scene | [fold_check.gd](../../../research/f4u-corsair/F4U-17/fold_check.gd) with the windowed Godot and `--rendering-driver opengl3` | `checks.json` and screenshots in a new directory outside the repository |
| Software baseline | [record_baseline.gd](../../../research/f4u-corsair/F4U-12/record_baseline.gd) `-- --out=<new .orfl>`, then `tools/flight_log/flight_log.py replay` | Scripted 10 s `.orfl` for candidate comparisons |

```bash
blender -b -Y --factory-startup F4U_Corsair_R59.blend --python research/f4u-corsair/F4U-06/extract_geometry_r59.py -- \
  assets/aircraft/f4u-corsair-250/geometry-r59.json 94edd59b44f578b5a1f7c1fe4004c736dff47a63e2866e4b8a04532851cf4dc3
blender -b -Y --factory-startup F4U_Corsair_R59.blend --python research/f4u-corsair/F4U-17/extract_wing_fold.py -- \n  assets/aircraft/f4u-corsair-250/wing-fold-r59.json 94edd59b44f578b5a1f7c1fe4004c736dff47a63e2866e4b8a04532851cf4dc3
python3 research/f4u-corsair/F4U-03/manifest.py --check
python3 research/f4u-corsair/F4U-16/install_liveries.py --check
python3 research/f4u-corsair/F4U-05/compile_model.py --check
python3 research/f4u-corsair/F4U-07/ground_effect_vlm.py --check
python3 research/f4u-corsair/F4U-07/fit_propeller.py --check
python3 research/f4u-corsair/F4U-07/derive_physics.py --check
python3 research/f4u-corsair/F4U-11/costing_entry.py --check
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script "$PWD/research/f4u-corsair/F4U-07/probe.gd"
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://aircraft/verify_f4u.gd
```

Gear samples come from Blender on the frozen delivery: `blender -b --factory-startup --disable-autoexec assets/source-deliveries/f4u-corsair-g1-13/f4u_corsair/g1_13/source/aircraft_game.blend --python research/f4u-corsair/F4U-05/sample_gear.py -- assets/aircraft/f4u-corsair-250/gear-samples.json`. After a binding or model change, run `build_models.py`, `build_descriptors.py`, `build_customization.py` and the parked-aircraft bake in that order (see the [Avanti guide](../avanti-s-a200/README.md#regenerate-and-verify)).

Run generators without `--check` in the order above after an intentional input change. Never hand-edit generated files. The physics sections stay with R59, of which g1.13 is a simplified copy; F4U-05 takes the visual model's own dimensions (propeller, contacts) from g1.13's metadata. `compile_model.py` refuses a wing-fold file whose R59 hash differs from the metadata's master, and a livery GLB that is not the frozen file or not the same airframe as the default. After `install_liveries.py` writes a new sidecar, run Godot's `--import` once to assign its uid before compiling.

## Limits

Physics inputs are provisional: the geometry is a visual reconstruction, the Moki torque curve and the 30x18 propeller tables are estimated from published operating points, and no flight data calibrate trim or sideslip. [F4U-07 evidence](../../../docs/research/f4u-corsair/F4U-07/README.md) lists every estimate and borrowed value.
