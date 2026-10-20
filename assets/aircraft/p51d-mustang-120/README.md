# P-51D Mustang: source and model guide

Checked 2026-10-19. `p51d-mustang-120` is an experimental 2.82 m, 120 cc-class reference model. This page owns visual sources, the pipeline and model interfaces. The [aircraft guide/plan](../../../docs/P51-PLAN.md) owns flight scope and remaining acceptance; [fuel behavior](../../../docs/FUEL-SYSTEM.md) has a shared home.

## Sources and coordinates

Edit estimated dimensions in [source.json](source.json). Its measured groups come from [AN 01-60-3 metrology](../../../research/p51/p51-02/silhouette/README.md); regenerate those through `apply_metrology.py`, preserving later authored corrections. [appearance.json](appearance.json) owns the artistic finish. Drawings/photos remain in ignored `references/p51-mustang/`; routine compiler checks use committed inputs.

Coordinates are metres, +X right, +Y up, −Z nose. The origin is the centreline wing-root leading edge at spinner-axis height, not the physics CG. The [model manifest](../../../app/data/aircraft_models/p51d-mustang-120.json) declares this datum. Measured full-size outlines are separate from estimated RC dimensions, installation and concealed details.

## Pipeline and routine verification

| Source → output | Tool / home |
| --- | --- |
| Committed metrology → measured source groups | [apply_metrology.py](../../../research/p51/p51-02/silhouette/apply_metrology.py); research operation, not a routine rebuild |
| `source.json` → `geometry.json` | [build_geometry.py](build_geometry.py), scaled to the declared kit span |
| Geometry → `app/aircraft/p51d_geometry.gd` | [compile_geometry.py](compile_geometry.py) |
| Appearance → `app/aircraft/p51d_appearance.gd` | [compile_appearance.py](compile_appearance.py) |
| Wing/tail geometry → ground-effect table | [P51-20 VLM](../../../research/p51/p51-20/README.md) |
| Geometry and physics inputs → aircraft JSON / derivation | [P51-05 generator](../../../research/p51/p51-05/derive_physics.py) |
| Changed identities → model / Workshop bindings | [Model/package pipeline](../../../docs/AIRCRAFT_CONTRACT.md#model-and-package-contract), [Workshop standard](../../../docs/AIRCRAFT_CONTRACT.md#workshop-authoring-standard) |

From the repository root after [developer setup](../../../docs/TOOLS.md#developer-setup), these checks do not rewrite generated artifacts. Bash is shown; native Windows uses `python` and the matching engine described in setup.

```bash
python3 assets/aircraft/p51d-mustang-120/build_geometry.py --check
python3 assets/aircraft/p51d-mustang-120/compile_geometry.py --check
python3 assets/aircraft/p51d-mustang-120/compile_appearance.py --check
python3 research/p51/p51-20/ground_effect_vlm.py --check
python3 research/p51/p51-05/derive_physics.py --check
python3 research/p51/p51-15/test_inventory.py
GODOT="$(app/get-godot.sh)"
"$GODOT" --headless --path app --audio-driver Dummy --script res://aircraft/verify_p51.gd
"$GODOT" --headless --path app --audio-driver Dummy --script res://aircraft/verify_p51_clearance.gd
```

Import resources first on a fresh checkout; test runners do this automatically. Inspect engine errors as well as exit codes and bound long-running checks. The [audit tools](../../../research/p51/p51-15/README.md) own flight/probe commands; `app/test.sh` owns broader integration. [Evidence](../../../docs/research/p51-realism/README.md) records current rechecks separately from old passing counts.

For intentional changes, run affected generators without `--check` in dependency order. Refresh the VLM when its inputs change, then regenerate physics and dependent model/Workshop identities. Never hand-edit generated output. Reapplying original metrology can overwrite later source refinements; review its diff.

## Native model and finish

[p51d_model.gd](../../../app/aircraft/p51d_model.gd) is a native procedural builder selected by the version-1 `euler_hinges` manifest. Its raw `build()` result includes `{root, propeller, hinges, gear, frames, flaps, gear_rig}`. Stable `airplane`, `propeller` and hinge nodes feed the shared presentation contract. Static frames carry incidence, dihedral and hinge sweep.

`set_flaps()` articulates the flaps. `set_gear()` drives legs and sequenced doors from retraction geometry shared with physics contacts. The builder rests gear-down; the session selects the flight pose. Rudder geometry uses the aerodynamic hinge. Scale-light anchors follow the rudder and gear-gated landing lamp. The RC smoke outlet is separate from decorative full-size exhaust stacks.

The generic natural-metal finish has a red spinner/nose band, olive anti-glare panel and yellow tips/rudder, without unit markings. [p51d_finish.gd](../../../app/aircraft/p51d_finish.gd) uses object-space positions and generated appearance parameters. [Visual review](../../../docs/research/p51-visual-review-v2.md) records its estimates; owner paint selection remains open.

## Captures and metrology

Use a fresh output directory; the inspector refuses existing output. This Linux example needs Xvfb/OpenGL:

```bash
xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" \
  --path app --rendering-driver opengl3 --audio-driver Dummy \
  --script res://aircraft/inspect_p51.gd -- --output-dir=/tmp/p51-inspection --suite=inspection
```

The [silhouette method](../../../research/p51/p51-02/silhouette/README.md) owns optional drawing/photo comparisons and image dependencies. Rendered silhouette and hinge-clearance checks verify software geometry; they do not validate loaded airframe travel or flight behavior.
