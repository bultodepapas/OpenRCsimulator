# F4U Corsair 1/4.5: sources and pipeline

Checked 2026-10-22. `f4u-corsair-250` is a proposed 2.778 m, 1/4.5-scale F4U-1D of the CARF-Models class, powered by a Moki S250 five-cylinder radial with a 30x18 three-blade. Nothing here is in the catalog yet. The author's accepted g1.3 visual model is frozen in `assets/source-deliveries/f4u-corsair-g1-3/` and identified by [source-manifest.json](source-manifest.json). The [F4U plan](../../../docs/F4U-PLAN.md) owns scope, steps and owner decisions.

## Sources

| File | Content |
| --- | --- |
| [source.json](source.json) | Authored inputs (format v2): D1 CARF-Models F4U-1D 1:4.5, D4 30x18 three-blade, D5 Moki S250; two mass anchors for this kit; the CARF manual's setup; three smaller Corsair setups for CG, low rates and expo; the Moki operating points; NACA full-size data; measured NACA 23012/23015 sections with XFOIL thickness trends; Roskam slotted-flap digitization. Edit only here. |
| [geometry-r59.json](geometry-r59.json) | Generated: 1/4.5 geometry measured on the R59 master (sections, control surfaces, fuselage, nose, hull points, gear and retraction paths). g1.3 landmarks agree within 0.3 mm (F4U-06). |
| [source-manifest.json](source-manifest.json) | Generated: SHA-256 and size of every g1.3 delivery file, key files by role, visual revision `g1.3-c69151b3c96c`. |

Coordinates are metres in the physics le frame, [x_aft, y_right, z_up], from the root leading edge on the centreline at thrust-line height. This is the delivery request's D0, so g1.3 model coordinates map as `[x_aft, y_right, z_up] = [z_model, x_model, y_model]`.

## Pipeline

| Step | Tool | Output |
| --- | --- | --- |
| R59 → 1/4.5 geometry | [extract_geometry_r59.py](../../../research/f4u-corsair/F4U-06/extract_geometry_r59.py) (Blender 5.2.2, headless, `-Y`) | `geometry-r59.json`; a research operation, R59 stays outside the repository |
| Gull-wing ground effect | [ground_effect_vlm.py](../../../research/f4u-corsair/F4U-07/ground_effect_vlm.py) | `research/f4u-corsair/F4U-07/vlm_ground_effect.json` |
| Propeller calibration | [fit_propeller.py](../../../research/f4u-corsair/F4U-07/fit_propeller.py) | `research/f4u-corsair/F4U-07/prop_calibration.json` |
| Physics derivation | [derive_physics.py](../../../research/f4u-corsair/F4U-07/derive_physics.py) | `research/f4u-corsair/F4U-07/f4u_corsair_250.json` (staged) and `derivation.md` |
| Loader and trim probe | [probe.gd](../../../research/f4u-corsair/F4U-07/probe.gd) | Console checks |
| Delivery preflight | [preflight_glb.py](../../../research/f4u-corsair/F4U-04/preflight_glb.py) | Pass/fail per delivery GLB |
| Delivery identity | [manifest.py](../../../research/f4u-corsair/F4U-03/manifest.py) | `source-manifest.json` |

```bash
blender -b -Y --factory-startup F4U_Corsair_R59.blend --python research/f4u-corsair/F4U-06/extract_geometry_r59.py -- \
  assets/aircraft/f4u-corsair-250/geometry-r59.json 94edd59b44f578b5a1f7c1fe4004c736dff47a63e2866e4b8a04532851cf4dc3
python3 research/f4u-corsair/F4U-03/manifest.py --check
python3 research/f4u-corsair/F4U-07/ground_effect_vlm.py --check
python3 research/f4u-corsair/F4U-07/fit_propeller.py --check
python3 research/f4u-corsair/F4U-07/derive_physics.py --check
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script "$PWD/research/f4u-corsair/F4U-07/probe.gd"
```

Run generators without `--check` in the order above after an intentional input change. Never hand-edit generated files. The physics sections stay with R59, of which g1.3 is a simplified copy; F4U-05 takes the visual model's own dimensions (propeller, contacts) from g1.3's metadata.

## Limits

Physics inputs are provisional: the geometry is a visual reconstruction, the Moki torque curve and the 30x18 propeller tables are estimated from published operating points, and no flight data calibrate trim or sideslip. [F4U-07 evidence](../../../docs/research/f4u-corsair/F4U-07/README.md) lists every estimate and borrowed value.
