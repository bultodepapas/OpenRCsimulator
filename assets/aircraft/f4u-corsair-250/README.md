# F4U Corsair 1/5: sources and pipeline

Checked 2026-10-22. `f4u-corsair-1-5` is a proposed 2.500 m, 1/5-scale F4U-1D for DLE-111-class gasoline power. Nothing here is in the catalog yet; the visual model waits for the author's g1 delivery. The [F4U plan](../../../docs/F4U-PLAN.md) owns scope, steps and owner decisions.

## Sources

| File | Content |
| --- | --- |
| [source.json](source.json) | Authored inputs (format v2): provisional hardware choices (D1 FokkeRC 1/5, D4 three-blade, D5 DLE-111), four Corsair mass anchors, three Corsair setups (Black Horse, Seagull, Phoenix), the DLE-111 static-rpm anchor, NACA full-size data, measured NACA 23012/23015 sections with XFOIL thickness trends, Roskam slotted-flap digitization. Edit only here. |
| [geometry-r59.json](geometry-r59.json) | Generated: 1/5 geometry measured on the R59 master (sections, control surfaces, fuselage, nose, hull points, gear and retraction paths). Provisional until g1 metrology. |

Coordinates are metres in the physics le frame, [x_aft, y_right, z_up], from the root leading edge on the centreline at thrust-line height. This is the delivery request's D0, so g1 model coordinates map as `[x_aft, y_right, z_up] = [z_model, x_model, y_model]`.

## Pipeline

| Step | Tool | Output |
| --- | --- | --- |
| R59 → 1/5 geometry | [extract_geometry_r59.py](../../../research/f4u-corsair/F4U-06/extract_geometry_r59.py) (Blender 5.2.2, headless, `-Y`) | `geometry-r59.json`; a research operation, R59 stays outside the repository |
| Gull-wing ground effect | [ground_effect_vlm.py](../../../research/f4u-corsair/F4U-07/ground_effect_vlm.py) | `research/f4u-corsair/F4U-07/vlm_ground_effect.json` |
| Physics derivation | [derive_physics.py](../../../research/f4u-corsair/F4U-07/derive_physics.py) | `research/f4u-corsair/F4U-07/f4u_corsair_1_5.json` (staged) and `derivation.md` |
| Loader and trim probe | [probe.gd](../../../research/f4u-corsair/F4U-07/probe.gd) | Console checks |

```bash
blender -b -Y --factory-startup F4U_Corsair_R59.blend --python research/f4u-corsair/F4U-06/extract_geometry_r59.py -- \
  assets/aircraft/f4u-corsair-1-5/geometry-r59.json 94edd59b44f578b5a1f7c1fe4004c736dff47a63e2866e4b8a04532851cf4dc3
python3 research/f4u-corsair/F4U-07/ground_effect_vlm.py --check
python3 research/f4u-corsair/F4U-07/derive_physics.py --check
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script "$PWD/research/f4u-corsair/F4U-07/probe.gd"
```

Run generators without `--check` in the order above after an intentional input change. Never hand-edit generated files. When g1 arrives, its metrology replaces `geometry-r59.json` through a new extraction (F4U-05/06); the physics generator then reads that file instead.

## Limits

Physics inputs are provisional: hardware choices await the owner, the geometry is a visual reconstruction, and no flight data calibrate trim or sideslip. [F4U-07 evidence](../../../docs/research/f4u-corsair/F4U-07/README.md) lists every estimate and borrowed value.
