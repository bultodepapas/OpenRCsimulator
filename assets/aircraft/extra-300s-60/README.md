# Great Planes Extra 300S .60: source and model guide

Checked 2026-11-15. `gp-extra-300s-60` is an experimental GPMA0236 aircraft with a native Godot model. This page owns geometry, finish, model interfaces and their tools. The [aircraft guide/plan](../../../docs/EXTRA-300-PLAN.md) owns current flight scope, pending checks and remaining EX work; [glow](../../../docs/GLOW-ENGINES.md) and [fuel](../../../docs/FUEL-SYSTEM.md) own shared runtime behavior.

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

E300-07 adds twin recessed cooling openings inside the measured nose outline and rounded tire shoulders with separate metal hubs. Opening dimensions, 18 mm duct depth and tire sections are visual estimates. The hub and tire share each existing wheel pivot. The new `cowl_face` participates in the fuselage paint slot. General kit-shape references remain the Great Planes plans/manual and the .60 photographs credited to [Outerzone oz10977](https://outerzone.co.uk/plan_details.asp?ID=10977).

[test_extra_visual_details.gd](../../../app/tests/test_extra_visual_details.gd) checks open intake centers, duct depth, wheel dimensions, outward cap winding and isolated body paint, then runs the existing Extra geometry/articulation verifier. Submit this script through the checked test pool on enrolled hosts. The E300-07 visual review used paired front, side, top, oblique, cowl and gear views at 1920×1080 in the native Windows Compatibility renderer on an RTX 3090. Scratch captures and their source/checksum manifest remain under ignored `tmp/extra300-model-20261115/`.

The E300-07 native Windows checked run passed 151 checks with zero errors or warnings on 2026-11-15. That revision contains 37 meshes and 21,346 triangles, with a 1.624 × 0.552 × 1.386 m extent. Minimum control clearance is 1.75 mm at the manual high rates.

E300-08 refines the pilot's face and eyewear, seats the visor on its plan point, and adds a seat back, harness, instrument hood and three dials. The painted canopy perimeter follows the body paint slot. Glass reads its tint and alpha from `appearance.json` and uses a nonmetallic plastic finish. The shirt and cap use rougher materials, while the covering has a 0.34 roughness. A narrow antialiased cowl joint and four screw heads complete the exterior pass. Interior fittings and fastener dimensions are artistic estimates.

The E300-08 review uses paired front, side, top, underside and detail views at 1920×1080 under the same three-point studio rig. Its light settings, raw source hashes, explicit preview preload-path substitutions and PNG checksums are retained in ignored `tmp/extra300-lookdev-20261115/visual-manifest.json`. The opaque canopy fallback was also exercised. The detail test includes curved-canopy containment for the pilot/interior, visor placement, source-driven glass tint and independent frame paint.

The E300-08 native Windows checked run passed 180 checks with zero errors or warnings. It contains 48 meshes and 24,687 triangles, with a 1.624 × 0.552 × 1.386 m extent and 1.75 mm minimum control clearance at the manual high rates.

E300-09 adds five thickness sections to each terminal wing panel and a 1.5 mm leading-edge radius to the fixed stabilizer. These are visual estimates contained inside the previous geometry. The measured wing planform, span, stabilizer outline, square hinge plane and moving-surface bevels remain unchanged. Existing materials and paint coordinates are retained; upper and lower patterns wrap onto their respective rounded shoulders. Paired detail, orthographic and overall views at 1920×1080 use the same studio rig; source hashes, preload-path substitution and image checksums remain in ignored `tmp/extra300-wing-20261115/visual-manifest.json`. The detail test also checks closed surfaces, finite unit normals, tip paint coordinates and containment within the original stabilizer envelope.

The E300-09 native Windows checked run passed 190 checks with zero errors or warnings on 2026-11-15 (`T-d14915e991d94b50a1c096c820ca9ce2`). It contains 48 meshes and 25,287 triangles, 600 more triangles than E300-08. The extent remains 1.624 × 0.552 × 1.386 m and minimum control clearance remains 1.75 mm at the manual high rates. The checked source matches the captured candidate; the report and identity comparison remain in that scratch folder's `verification/` directory.

The verifier checks posed control clearance at manual travel and 45° using [extra_clearance.gd](../../../app/aircraft/extra_clearance.gd). Those are software geometry checks, not measured loaded-airframe travel. The visual propeller is nominal 12×6 with estimated outline/section; the shaft frame has the plan's 2° right / 0.5° down angles. [EX-05](../../../research/extra-300/ex05/derivation.md) derives the physical axis and force arm from that frame and hub. Aerodynamics, mass/inertia and the active glow profile remain separately attributed estimates.

## Captures and research probes

```bash
bash research/extra-300/ex02/capture.sh --suite inspection
```

The capture runner needs Xvfb/OpenGL and writes a new ignored output directory. Suites are `inspection`, `orbit`, `detail`, `distance`, `scale` or `all`. `all` also renders high-resolution scale views and runs `review.py`; its image analysis needs Pillow/NumPy. Plan overlays are skipped when the local raster cache is absent. The runner refuses to overwrite captures.

The [EX-06/08 probe guide](../../../research/extra-300/ex06/README.md) owns signed-control, ground/envelope and 240/480 Hz comparison commands. Preserve baseline source/configuration and input tapes with the [flight logging workflow](../../../docs/FLIGHT-LOGGING.md). Historical probe success, predicted roll/loop metrics and rendered orientation do not establish physical flight validation.
