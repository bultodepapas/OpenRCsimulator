# Great Planes Extra 300S .60: source and model guide

Checked 2026-11-16. `gp-extra-300s-60` is an experimental GPMA0236 aircraft with a native Godot model. This page owns geometry, finish, model interfaces and their tools. The [aircraft guide/plan](../../../docs/EXTRA-300-PLAN.md) owns current flight scope, pending checks and remaining EX work; [glow](../../../docs/GLOW-ENGINES.md) and [fuel](../../../docs/FUEL-SYSTEM.md) own shared runtime behavior.

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

E300-11 replaces the separate head, nose, ears and neck with one closed skin loft. Monotone sections pass through the plan's chin, nose and head-back points; the cap crown now follows its recorded side-view point. Joined curved eyewear follows the face, with an intermediate lens ring providing more separation from the emitted skin. A small mouth line is projected onto the actual head triangles. Projection uses millimetres internally for the ray helper and rejects triangles outside the mouth's XY bounds; the authored model remains in metres. The original torso, harness, visor point and `pilot_head` consumer name are retained.

The face, low-relief ears, eyewear and intermediate cap/skin sections remain artistic estimates. The integrated ears are deliberately less prominent than the old separate ovals. Paired 1920×1080 front, profile, rear, cockpit and overall views show connected skin/clothing and no visible new glass/seat penetration. The detail test adds closed-head, side-profile/crown landmarks, triangle-interior canopy samples and an emitted-mesh eyewear depth check. The final sampled lens margin is about 0.61 mm. Static captures do not establish continuous moving-view clearance. Raw source identities, preview preload substitution, studio settings and 22 image checksums remain in ignored `tmp/extra300-pilot-20261115/visual-manifest.json`.

The E300-11 native Windows checked run passed **202 checks, zero errors and zero warnings** (`T-d02ca404372743b68389eb7eabc0a4ee`). It contains 44 meshes and 25,367 triangles: four fewer meshes and 896 fewer triangles than E300-10. The check total varies with the verifier's per-mesh assertions. The extent remains 1.624 × 0.552 × 1.386 m and minimum control clearance remains 1.75 mm at manual high rates. The eight recorded source hashes match the captured candidate, frozen input and checked attempt; logs and identity proof are in the scratch folder's `verification/` directory. No checked-attempt Godot processes remained after completion.

E300-12 refines the nose assembly. The spinner uses the existing lathe profile with denser sampling and analytic normals, including an axial normal at its collapsed tip; this removes the former arbitrary upward apex normal. Its final 0.8 mm is a separate metal-finish backplate rim, ending on the original back plane and sharing the cone boundary. This finish and thickness are artistic estimates. The axisymmetric cone and backplate remain siblings of the rotating blades, preserving diameter selection, shadow and prop-strike behavior.

The cooling openings gain curved painted lips tangent to the front face and recessed duct walls. Their explicit plain-body finish avoids applying side graphics according to the curved normals. Both lips and the spinner participate in the body paint slot with independent per-aircraft material copies. The blade outline retains its previous sections through 98.60% radius, then closes through estimated elliptical tip stations. Diameter, pitch, camber and the thrust frame remain unchanged. The geometry compiler permits zero chord only at the terminal chord-table row; the builder retains small tip triangles with a local cutoff and axial endpoint normals. The satin blade material remains compatible with the existing fade and measured blur-disc pipeline. No additional bitmap texture is required.

E300-12 verification is pending. Scratch source identities, matched studio views, posed controls and stopped/blurred propeller captures belong in ignored `tmp/extra300-nose-20261116/`. These are asset presentation checks; global lighting and flight physics are outside this revision.

The verifier checks posed control clearance at manual travel and 45° using [extra_clearance.gd](../../../app/aircraft/extra_clearance.gd). Those are software geometry checks, not measured loaded-airframe travel. The visual propeller is nominal 12×6 with estimated outline/section; the shaft frame has the plan's 2° right / 0.5° down angles. [EX-05](../../../research/extra-300/ex05/derivation.md) derives the physical axis and force arm from that frame and hub. Aerodynamics, mass/inertia and the active glow profile remain separately attributed estimates.

## Visual self-audit and improvement plan

2026-11-15 · EX-10 / E300-10 · **Visual verdict: SHIP WITH NOTES.** Reviewed native Windows Compatibility captures on an RTX 3090 at 1920×1080: front, side, top, underside, oblique, wing/tail details and two distance views. The measured outline and contrasting upper/lower scheme remain readable. Geometry checks qualify software interfaces and clearances; this audit does not establish flight realism or target-hardware performance.

The main confirmed defect was exposed red end-cap slivers at wing-panel joins. Full and shortened fixed panels sampled the same piecewise-linear airfoil at different chord fractions. Their boundary polylines differed by up to 0.431 mm. E300-10 includes every source section breakpoint at both ends of each panel, preserving equal ring counts, closed caps and the moving aileron bevel. Direct comparison of emitted render vertices reduces the worst join mismatch below 0.00001 mm. The regression rejects E300-09. It reads render arrays rather than the rounded faces returned by the collision-oriented mesh helper.

Wing normals now interpolate the section-knot normals independently of subdivision, account for taper/sweep and tip scaling, and meet the fixed panel tangentially at the first tip ring. Caps retain their flat normals. Matched views show smoother highlights and substantially fewer isolated red pixels. One inherited red pixel remains at (285, 271) in the wing detail; its cause remains unresolved. Do not claim a completely artifact-free finish. The shader and artistic palette are unchanged. A shader-distance defect was considered, but projected seams and the native geometry A/B supported the panel explanation.

The final native Windows checked run passed **204 checks, zero errors and zero warnings** (`T-253da60697cb437a82d5f580f39b98b9`). It contains 48 meshes and 26,263 triangles, 976 more triangles than E300-09. The extent remains 1.624 × 0.552 × 1.386 m and minimum control clearance remains 1.75 mm at manual high rates. The eight recorded runtime/test/package source hashes match the captured candidate, frozen input and checked attempt. The 16.9-second test duration is a functional-check observation, not a rendering-performance benchmark.

| Priority | Finding and status | Next bounded action | Acceptance evidence |
| --- | --- | --- | --- |
| P0 | Panel join mismatch: corrected in E300-10. One isolated raster speck remains. | Retain emitted-boundary and closed-surface regression; isolate the remaining pixel before broader livery changes. | Join error ≤0.01 mm on both surfaces and both wings; closed meshes, finite outward unit normals; matched top/underside detail captures. |
| P1 | Integrated head/neck, fitted eyewear and cap trace delivered in E300-11. The RC figure remains stylized. | Add further ear/clothing detail only when visible at the intended view size; continue with P2. | Current paired close/overall views and geometry checks; retain curved-canopy containment, landmark and depth checks; record geometry cost. |
| P2 | Fin/rudder and elevator outer edges remain prism-shaped. | Add small selective exterior radii only after separating exterior edges from hinge-relief cuts. | Original outlines and named moving meshes preserved; closed topology; clearance at manual throws, intermediate poses and 45°; both paint faces reviewed. |
| P3 | E300-12 refines spinner, backplate and intake lips. Control horns/linkages and motor-installation fittings remain absent; gear-root detail is sparse. Exact kit-build placement is not established. | Collect compatible .60 build references, then add only visible supported fittings. Keep guessed dimensions labeled. | Source/provenance record; linkage endpoints follow controls; no fuselage/gear/control collisions; front, side and posed detail views. |
| P4 | Studio and distance views support readability; this asset has no new in-flight frame-time/VRAM qualification from this audit. | Compare daylight and low sun in Home/flight at 1080p, including Low and normal presets; measure cost before increasing detail. | Actual viewport/renderer and hardware recorded; top/underside recognition at flight size; frame-time, draw and memory observations; preserved quality overrides. |

Scratch evidence lives in ignored `tmp/extra300-audit-20261115/`: paired images, `visual-manifest.json`, baseline/candidate `join-regression.json` and the native verification receipts. The studio rig is a presentation fixture. Global scene lighting is not part of this model revision. Planned work above remains open; details added in earlier passes remain artistic estimates where the guide identifies them.

## Captures and research probes

```bash
bash research/extra-300/ex02/capture.sh --suite inspection
```

The capture runner needs Xvfb/OpenGL and writes a new ignored output directory. Suites are `inspection`, `orbit`, `detail`, `distance`, `scale` or `all`. `all` also renders high-resolution scale views and runs `review.py`; its image analysis needs Pillow/NumPy. Plan overlays are skipped when the local raster cache is absent. The runner refuses to overwrite captures.

The [EX-06/08 probe guide](../../../research/extra-300/ex06/README.md) owns signed-control, ground/envelope and 240/480 Hz comparison commands. Preserve baseline source/configuration and input tapes with the [flight logging workflow](../../../docs/FLIGHT-LOGGING.md). Historical probe success, predicted roll/loop metrics and rendered orientation do not establish physical flight validation.
