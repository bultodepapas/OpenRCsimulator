# Great Planes Extra 300S .60: source and model guide

Checked 2026-10-19. `gp-extra-300s-60` is an experimental GPMA0236 aircraft with a native Godot model. This page owns geometry, finish, model interfaces and their tools. The [aircraft guide/plan](../../../docs/EXTRA-300-PLAN.md) owns current flight scope, pending checks and remaining EX work; [glow](../../../docs/GLOW-ENGINES.md) and [fuel](../../../docs/FUEL-SYSTEM.md) own shared runtime behavior.

## Sources and frames

[geometry.json](geometry.json) is editable visual geometry with evidence kinds; [appearance.json](appearance.json) is the editable artistic finish. Plan/manual measurements come from [EX-01 metrology](../../../research/extra-300/ex01/metrology.json); estimated gear, propeller and rounded-section details remain labeled. Source PDFs/photos stay in ignored `references/extra-300/`; a fresh checkout does not include them.

Model coordinates are metres, +X right, +Y up, −Z nose. The origin is the nominal manual CG station at spinner-axis height. It is not the live physics CG. The [model manifest](../../../app/data/aircraft_models/gp-extra-300s-60.json) declares the model-to-LE datum; shared frames belong to the [aircraft contract](../../../docs/AIRCRAFT_CONTRACT.md#coordinates-signs-and-units).

## Pipeline and routine verification

| Source / generated output | Pipeline |
| --- | --- |
| Plan/manual picks → [metrology.json](../../../research/extra-300/ex01/metrology.json) | `research/extra-300/ex01/measure.py`; needs local PDF sources, Poppler `pdfimages`, Pillow and NumPy |
| [geometry.json](geometry.json) → [extra_300s_geometry.gd](../../../app/aircraft/extra_300s_geometry.gd) | [compile_geometry.py](compile_geometry.py); validates structure and metrology consistency |
| [appearance.json](appearance.json) → [extra_300s_appearance.gd](../../../app/aircraft/extra_300s_appearance.gd) | [compile_appearance.py](compile_appearance.py) |
| Geometry and attributed flight inputs → aircraft JSON / derivation | [EX-05 generator](../../../research/extra-300/ex05/derive_physics.py); includes the finite-glow installation selector |
| Changed source/dependency identities → model and Workshop bindings | [Shared model/package pipeline](../../../docs/AIRCRAFT_CONTRACT.md#model-and-package-contract), [Workshop standard](../../../docs/AIRCRAFT_CONTRACT.md#workshop-authoring-standard) |

From the repository root after [developer setup](../../../docs/TOOLS.md#developer-setup), these checks do not regenerate source artifacts. Bash is shown; native Windows uses `python` and the matching engine as described in setup.

```bash
python3 assets/aircraft/extra-300s-60/compile_geometry.py --check
python3 assets/aircraft/extra-300s-60/compile_appearance.py --check
python3 research/extra-300/ex05/derive_physics.py --check
GODOT="$(app/get-godot.sh)"
"$GODOT" --headless --path app --audio-driver Dummy --script res://aircraft/verify_extra.gd
"$GODOT" --headless --path app --audio-driver Dummy --script res://tests/test_extra_installation.gd
"$GODOT" --headless --path app --audio-driver Dummy --script res://tests/test_extra_handling.gd
"$GODOT" --headless --path app --audio-driver Dummy --script res://tests/test_extra_runway.gd
```

Import first on a fresh checkout; test/capture runners do it automatically. Inspect engine errors as well as exit codes and bound probe runtimes. The [evidence record](../../../docs/research/extra-300-realism/README.md) distinguishes checks actually completed from pending verification; `app/test.sh` owns the broader suite.

For an intentional source change, run the appropriate compilers without `--check`, then regenerate EX-05 whenever geometry it consumes changes. Rebuild affected model manifests/Workshop descriptors through their generators and verify their pins. Glow installation/profile changes use the [glow authoring pipeline](../../../docs/GLOW-ENGINES.md). Never hand-edit generated `.gd`, aircraft JSON or glow data.

Rebuilding EX-01 metrology is separate from routine checks: `python3 research/extra-300/ex01/measure.py --check` requires the ignored source PDFs and its image tools. The committed metrology remains usable by the geometry compiler without those downloads.

## Native builder and finish

[extra_300s_model.gd](../../../app/aircraft/extra_300s_model.gd) is selected by the version-1 model manifest (`euler_hinges`); it builds native geometry rather than importing a scene. Its raw `build()` result contains `{root, propeller, hinges, gear}`. Stable `airplane`, `propeller` and hinge nodes remain bound through the common presentation contract. Static `aileron_frame_*` parents carry the swept hinge direction; commanded deflection acts on the child hinges.

The [finish](../../../app/aircraft/extra_300s_finish.gd) uses model-space UVs and shared shaders for the estimated red/white/blue scheme. The plan-derived pilot sits under a tinted canopy; `appearance.json` controls its alpha. [EX-10 visual evidence](../../../docs/research/extra-300-visual-review-v1.md) records orientation checks and limits.

The verifier checks posed control clearance at manual travel and 45° using [extra_clearance.gd](../../../app/aircraft/extra_clearance.gd). Those are software geometry checks, not measured loaded-airframe travel. The visual propeller is nominal 12×6 with estimated outline/section; the shaft frame has the plan's 2° right / 0.5° down angles. [EX-05](../../../research/extra-300/ex05/derivation.md) derives the physical axis and force arm from that frame and hub. Aerodynamics, mass/inertia and the active glow profile remain separately attributed estimates.

## Captures and research probes

```bash
bash research/extra-300/ex02/capture.sh --suite inspection
```

The capture runner needs Xvfb/OpenGL and writes a new ignored output directory. Suites are `inspection`, `orbit`, `detail`, `distance`, `scale` or `all`. `all` also renders high-resolution scale views and runs `review.py`; its image analysis needs Pillow/NumPy. Plan overlays are skipped when the local raster cache is absent. The runner refuses to overwrite captures.

The [EX-06/08 probe guide](../../../research/extra-300/ex06/README.md) owns signed-control, ground/envelope and 240/480 Hz comparison commands. Preserve baseline source/configuration and input tapes with the [flight logging workflow](../../../docs/FLIGHT-LOGGING.md). Historical probe success, predicted roll/loop metrics and rendered orientation do not establish physical flight validation.
