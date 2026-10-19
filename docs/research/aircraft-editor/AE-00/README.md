# AE-00 — Workbench customization investigation

**Date:** 2026-10-19. **Status:** partial investigation; no production feature implemented. **Runtime:** Godot 4.7.2 stable, Compatibility. The [AE plan](../../../plans/aircraft-editor.md#55-presentation-contract-to-implement) owns the proposed contract, subphases and acceptance tests. The [Workshop guide](../../../AIRCRAFT-WORKSHOP.md) owns current behavior. This record preserves source findings, primary references and diagnostic evidence.

## Source audit

The codebase graph is indexed, but targeted Workshop/smoke symbol searches returned no nodes. Direct source inspection supplied the missing coverage. The shared tree changed during this work: diagnostic work began with HEAD `f8c08f5a7`; later review saw `a04ba1ec4`. Other work changed and committed runtime/docs concurrently. These runs do not represent one frozen checkout. [Review-time source hashes](source-review.sha256) identify a later inspection snapshot, not every test's input bytes. This investigation did not stage, commit, push or change Git history.

| Current source | Finding and implication for future work |
| --- | --- |
| [parameters.gd](../../../../app/workshop/parameters.gd), [compiler.gd](../../../../app/workshop/compiler.gd) | Recipe keys and supported physical transforms are closed. No paint, emitter or timeline fields exist; keep a separate presentation validator/profile. |
| [trial.gd](../../../../app/workshop/trial.gd) | Physical trial identity already binds source, normalized recipe, descriptor, resolved model manifest, dependencies and compiler. Appearance must get a separate identity without removing these pins or rebinding historical builds. |
| [store.gd](../../../../app/workshop/store.gd), [workshop.gd](../../../../app/ui/workshop.gd) | Variant v1 has no appearance payload. First publication can strand an unreadable UUID; delete lacks expected revision and the confirmation reads the current selection; restore selects a sorted trash generation. Locks fail closed after process termination. AE-03 still needs transaction/recovery/delete-target proof before expanding saved records. |
| [workshop_preview.gd](../../../../app/ui/workshop_preview.gd) | An isolated World3D, `UPDATE_ONCE`, ignored mouse input and no flight/clock. Playback, orbit and animated smoke are new work; they need bounded rendering and input/clock ownership. |
| [model_manifest.gd](../../../../app/aircraft/model_manifest.gd) | The current manifest allowlist has control/rotor/gear/crash bindings, no generic paint/effect slots. Extend the owned schema/generator/consumer seam, never inject unchecked metadata. |
| [exhaust.gd](../../../../app/render/smoke/exhaust.gd), [process.gdshader](../../../../app/render/smoke/process.gdshader) | One configured anchor, 96 exhaust + 768 pump slots, 1.25/6 s life, explicit world endpoints, seeded swept births and manual presented intervals. Shader assigns RGB at birth and updates alpha afterward. Bounds/history use the fixed 6 s pump life. Longer life and more mounts need budget, history and lifecycle changes. |
| [main.gd](../../../../app/main.gd), [engine smoke tests](../../../../app/tests/test_engine_smoke.gd) | Flight bootstrap requires a valid source-compatible outlet. Static Home/capture routes have no operating history. Existing tests do not qualify a multi-mount show-effect profile or timed palette editor. |
| [compiler tests](../../../../app/tests/test_workshop_compiler.gd), [integration tests](../../../../app/tests/test_workshop_integration.gd) | Extra is now finite glow and explicitly refuses legacy size/weight/power edits. Common-workflow acceptance must use supported operations; two-airframe legacy scaling proof remains a separate unresolved fixture gate. |

## Official sources and resulting decisions

All references were accessed on 2026-10-19. Documentation is the 4.7 series; renderer implementation references use the exact `4.7.2-stable` tag. Engine API facts support the proposals below; they do not establish product acceptance or aircraft physics.

| Primary source | Engine fact | Proposed project response |
| --- | --- | --- |
| [Resource](https://docs.godotengine.org/en/4.7/classes/class_resource.html) | Resources are cached by path; deep duplication does not guarantee isolation of every nested Resource. | Clone the editable material or use an instance override. Test preview A/B/trial/source isolation; keep shared textures read-only. |
| [Color](https://docs.godotengine.org/en/4.7/classes/class_color.html) | Color RGB is normally sRGB unless an API says otherwise; alpha is linear. | Canonical sRGB swatches, documented shader boundary, one conversion; rendered mid-gray/alpha round trip. |
| [JSON](https://docs.godotengine.org/en/4.7/classes/class_json.html), [4.7.2 JSON parser](https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/json.cpp) | Parsing produces Variant data, accepts documented syntax deviations and assigns object values by key, losing earlier duplicate-key values. | Strict portable profiles need bounded pre-parse syntax/duplicate-key/nesting validation; keep post-parse schema/node/depth bounds. Parser success alone does not validate a profile or bound parser work. |
| [ResourceLoader](https://docs.godotengine.org/en/4.7/classes/class_resourceloader.html) | Registered loaders resolve resource files; plain text can use FileAccess. | Import profile bytes as data. Imported strings never choose `load`/ResourceLoader inputs; only registered bundled assets resolve after validation. This is an application boundary, not an engine sandbox claim. |
| [SubViewport](https://docs.godotengine.org/en/4.7/classes/class_subviewport.html), [Engine](https://docs.godotengine.org/en/4.7/classes/class_engine.html) | Input forwarding and update modes need explicit ownership; global time scale affects processing. | Separate deterministic preview playhead with bounded steps; test focus/drag, idle redraw and unchanged live session/time scale. |
| [GPUParticles3D](https://docs.godotengine.org/en/4.7/classes/class_gpuparticles3d.html) | Capacity, amount ratio and lifetime affect births; changing capacity restarts. A lower amount ratio does not remove total allocation/processing cost. | One measured total allocation across mounts. Separate burst scheduler from puff lifetime; prove residual aging and reset on the actual backend. |
| [Particle shader reference](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/particle_shader.html) | Per-particle state persists; built-in TIME is global and does not stop with pause. | Keep birth RGB and existing CUSTOM meanings. Use presented flight/preview time, not TIME, for events and aging. |
| [Renderer comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html), [4.7.2 GLES3 particle storage](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/particles_storage.cpp), [GLES3 shader](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/particles.glsl) | Compatibility has a GLES3 particle path. Its implementation excludes manual emit_particle, subemitters, built-in trails and 3D SDF particle colliders; transform-feedback state includes particle color/custom values. | Retain the existing swept-birth approach. A future fan/ribbon is a qualified plume shape, not a dependency on unsupported ribbon APIs. Test new scheduling against actual queued GPU processing. |
| [BaseMaterial3D](https://docs.godotengine.org/en/4.7/classes/class_basematerial3d.html) | Alpha transparency has sorting/overdraw costs; other transparency modes change rendering behavior. | Native sky/ground/airframe overlap and dense-cloud checks, with a total frame-cost gate; do not assume an alpha-mode swap is a free improvement. |

## Diagnostic checks

Run from the repository root with the pinned native console build. [Combined raw output](diagnostic-checks.log) retains import and six suites; [generator output](generator-checks.log) records the later read-only freshness checks. Both generator commands also passed earlier in this investigation.

Documentation verification checked relative targets, anchors, exact path case, 13 command/source paths, six suite filenames and every AE-00…26 acceptance row. It passed for 12 related documents: 894 local link checks and 898 against a fresh no-checkout clone's HEAD plus overlaid candidate documentation. This validates documentation paths, not an exported application or the full app suite.

```powershell
python research/aircraft-standardization/build_models.py --check
python research/aircraft-editor/build_descriptors.py --check
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --editor --import
Get-ChildItem app/tests/test_workshop_*.gd | Sort-Object Name | ForEach-Object {
    & .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ("res://tests/" + $_.Name)
}
```

| Check | Observed result |
| --- | --- |
| Model manifests / descriptors | PASS: 5 visual families / 8 descriptors current |
| Native import | Exit 0; no script/import errors in the retained output |
| Descriptor / Store | PASS: 102 / 108 checks, zero failures |
| UI / Integration | PASS: both report zero failed assertions; no script-error entries in the retained logs |
| Compiler | FAIL: 313 checks, 1 failure — finite-glow tank-capacity-only estimate reports `Glow dry fuel carrier mass properties are invalid` |
| Trial | FAIL: 37 checks, 2 failures — saved v1 descriptor launch and legacy trial identity binding the resolved manifest. The stale-presentation warning is a deliberate negative case; it is not the explanation for waiving these failures |

These failures need source/fixture diagnosis by the owning implementation tracks. They are not fixes delivered by this documentation change. The [earlier October 19 diagnostics](../AE-01-10/README.md#source-checks--2026-10-19) retain their original, different counts; integration has since passed in the run above. No full app suite, checkout-fixture test, exported package, long soak, other GPU/platform, real-radio or physical/pilot acceptance ran in this investigation.

## Native particle probe

The junior verification agent ran an isolated native project using byte-identical copies of the existing smoke script/shader. The lead reviewed the harness, logs and mixed-color capture. It uses an orthographic camera, black background, unshaded alpha draw material, a valid glow/pump fixture, automatic exhaust hidden and a fixed 0.05 s presentation path. Red tint changes to blue without restart. This isolates birth-color persistence; it does not reproduce production lighting, actual exhaust installation or flight physics.

Godot reports `v4.7.2.stable.official.ed1daf0bf`, OpenGL 3.3.0 NVIDIA 617.42, Compatibility, RTX 3090. The captured [smoke source](palette-probe/exhaust.gd.txt) and [shader](palette-probe/process.gdshader.txt) preserve the tested bytes; [review hashes](source-review.sha256) include their current counterparts.

| Assertion | Observation |
| --- | --- |
| Red before switch | PASS: 956 red / 0 blue classified pixels; [capture](palette-probe/red-only.png) |
| Old red plus new blue | PASS: 2,637 red / 366 blue classified pixels; [capture](palette-probe/red-blue-after-switch.png) |
| Same-clock pause pixels unchanged | FAIL: [capture](palette-probe/same-clock-pause.png) differed after additional draw boundaries |
| Reset visually clear | FAIL: 3,080 red / 661 blue classified pixels remained; [capture](palette-probe/reset-cleared.png) |

Final exit code was **1**, with two failures; [engine log](palette-probe/final-godot-run.log), [stdout](palette-probe/final-godot-run.stdout.log) and [stderr](palette-probe/final-godot-run.stderr.log) are retained. The [first attempt](palette-probe/godot-run.log) called camera look-at before attaching the camera and failed color checks; one correction moved look-at after attachment. [First stdout](palette-probe/godot-run.stdout.log) and [stderr](palette-probe/godot-run.stderr.log) remain beside it. No further correction/rerun was made.

The pause/reset results remain **uninvestigated harness/backend observations**, not confirmed production defects and not passes. The next SM/AE clock slice must distinguish queued GPU completion, paused age, residual requests and visibility from CPU reset flags, then reproduce with the actual production draw material. Do not weaken pause/reset acceptance or describe the whole probe as successful.

The captured [harness](palette-probe/harness.gd.txt) and [project configuration](palette-probe/project.godot.txt) are evidence, not an installed application tool. To reproduce, create an isolated ignored project, copy those files as `probe.gd` and `project.godot`, and place the captured source/shader at `render/smoke/exhaust.gd` and `render/smoke/process.gdshader`. Change only the harness's absolute `CAPTURE_DIR` to an existing empty output directory. It does not write player variants. The tested command was:

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --path tmp/workbench-plan-research-20261019/project --script res://probe.gd --rendering-method gl_compatibility --audio-driver Dummy --log-file C:/DEVELOPMENT/OpenRCsimulator/tmp/workbench-plan-research-20261019/final-godot-run.log
```

The actual native process was launched with `Start-Process -WindowStyle Hidden` and a 75 s external timeout; the command above shows its executable arguments. Use an isolated display-capable run; headless assertion suites cannot establish GPU pixels. Treat a different result as another observation requiring a harness/backend explanation, not automatic closure of the unresolved assertions.

## Planning outcome and limits

The investigation advances AE-00: it identifies the existing storage/binding/preview seams, removes the need to invent a new birth-color mechanism, and supplies executable work packages and negative tests in the [plan](../../../plans/aircraft-editor.md#56-implementation-packages-and-order). It does not close AE-03, AE-06/07, AE-10, AE-19, AE-24 or SM-10…15. Profile versions/caps, author-approved slots, the second legacy-compatible airframe, pause/reset diagnosis, minimum hardware, performance headroom and physical/pilot acceptance remain explicit gaps.
