# F4U-17: folding wings

Built 2026-10-23 for the [F4U plan](../../../F4U-PLAN.md) at the owner's request ("movement of the wings"). The Corsair's outer panels fold up and over the fuselage on the ground, as on the full-size F4U and the CARF kit's optional hydraulic fold. Presentation with an interlock; the flight model is unchanged.

## Source: R59's own rig

The author's R59 master (SHA-256 `94edd59b…`, the same file F4U-06 measured) has a complete fold rig. `R51 | CONTROL ALAS` carries `plegado_*` (0–1) and `angulo_maximo` 112°. Each `R51 | PIVOTE panel *` turns about an axis-angle axis, driven by `angle = sign · 112° · clamp((q − 0.12) / 0.82, 0, 1)`: the locks release over the first 12 % of the mechanism, then the panel turns. [extract_wing_fold.py](../../../../research/f4u-corsair/F4U-17/extract_wing_fold.py) reads this read-only, folds both panels in memory and checks Blender's own evaluation against the analytic rotation: basis error ≤ 1.2 × 10⁻⁷, and each navigation lamp moves 5.68 m to above the fuselage within 0.6 µm of the prediction. Output: [wing-fold-r59.json](../../../../assets/aircraft/f4u-corsair-250/wing-fold-r59.json).

```sh
blender -b -Y --factory-startup F4U_Corsair_R59.blend --python research/f4u-corsair/F4U-17/extract_wing_fold.py -- \
  assets/aircraft/f4u-corsair-250/wing-fold-r59.json 94edd59b44f578b5a1f7c1fe4004c736dff47a63e2866e4b8a04532851cf4dc3
```

## Model frame

[compile_model.py](../../../../research/f4u-corsair/F4U-05/compile_model.py) maps the rig by the delivery's D0 and the 1:4.5 scale: pivot (±0.560, −0.141, 0.121) m, axis (0, 0.215, 0.977) (aft, tilted up 12.4°), sign −1 left and +1 right. The mapped R59 navigation lamp lands 1 µm from g1.13's own landmark, an independent check of the mapping. The game model has no fold pivot. Each fold group is the panel's crash section, three nodes at the model frame: `wing_*_fixed`, `aileron_*_hinge`, `flap_*_3_hinge`. The cycle time, 8 s, is an estimate; R59 has no timing.

## Runtime

- **Model contract:** optional `construction.folds` ([AIRCRAFT_CONTRACT](../../../AIRCRAFT_CONTRACT.md#model-and-package-contract)). `imported_model.gd` turns the members in place, so node paths, paint targets and crash sections are unchanged. A hinge on a folding panel composes its deflection with the fold.
- **Session:** `set_throttle_hold(reason, active)` holds the throttle at idle where commands become solver inputs. Recordings carry the held throttle and replay exactly.
- **Flight scene:** **O** folds or spreads the wings, only on the wheels with the airplane stopped (< 0.5 m/s). The throttle stays at idle from the first press until the wings are spread and locked again. The HUD shows the state, and restart spreads the wings. Spanish strings, the in-app controls reference and [FIRST-LAUNCH](../../../FIRST-LAUNCH.md) list the key.

## Verification (2026-10-23, Windows, Godot 4.7.2)

| Check | Result | Evidence |
| --- | --- | --- |
| `verify_f4u.gd` fold checks | Two groups of three; full fold carries each R59 lamp to Blender's folded evaluation within 0.1 µm; lock release (0° at q 0.12, 56° at q 0.53); an aileron deflected while folded rides on its panel and keeps its deflection when spread; spreading restores every node exactly. 33/33 overall | [checks/verify_f4u.log](checks/verify_f4u.log) |
| [fold_check.gd](../../../../research/f4u-corsair/F4U-17/fold_check.gd) on the production flight scene | 8/8: refused in the air; on the runway, full throttle commanded reaches the solver as 0 while folding; 112° in 8.6 s; the airplane stays put; HUD line; spreading releases the throttle | [checks/fold.json](checks/fold.json) |
| Parked-aircraft bakes | Rebaked for the importer pin; all six meshes byte-identical, `--check` 6/6 | [checks/parked-bake.log](checks/parked-bake.log) |
| Controls reference | `test_controls_reference.gd` passes with the O key | — |
| Regression over the shared importer, session and flight scene | 24 suites, 0 failures: model manifests, render contract, catalog, Avanti handling and keyboard, controller actions and integration, end-to-end input, flaps, flight log (3,247 checks, exact replay), rates, retracts (three suites), crash wreck and integration, UI, Workshop (two suites), customization, night kit, Timber ground, startup cleanup | — |

**Correction (F4U-16, same day):** the fold binding kept a two-way reference between each hinge record and its fold, so every Corsair build leaked those records; [checks/verify_f4u.log](checks/verify_f4u.log) ends with the resulting exit-time allocator error, which the shared test runner counts as a failure. Fold members now name their hinge by key; `verify_f4u.gd` passes 33/33 with no engine error ([F4U-16](../F4U-16/README.md)).

## Limits

- The fold is visual. Folded wings do not change the physics; the throttle hold keeps the airplane from flying folded.
- Night-kit lights and wingtip smoke stay where the spread wing put them.
- The fold time is an estimate.
- R59's struts and lock pins (`puntal`, `bloqueo`) are not modelled beyond the lock-release law.
