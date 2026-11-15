# Current-source audit and evidence boundaries

Baseline: [`e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`](https://github.com/bultodepapas/OpenRCsimulator/commit/e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc), observed as the GitHub default branch `main` through both the Git remote and repository API on 2026-11-15. The audit uses an isolated worktree and changes documentation only.

## 1. What the project actually ships or experiments with

The repository has several engine families. Combining their features into a single claim about “the Godot build” would be incorrect.

| Path | Source identity and entry point | Implemented scope | Qualification boundary |
| --- | --- | --- | --- |
| Official cross-platform application | `app/get-godot.sh:4–5`: Godot `4.8-beta2`, `4.8.beta2.official.cafc17a19`; `app/project.godot:54–73` | Compatibility default; Mobile override for the supported Apple ARM64 package; optional Forward+ High; stock reconstruction capabilities | Actual renderer/driver, drawable size and tested host determine support. A project setting is not proof of dispatch or performance. |
| Windows NVIDIA application | `tools/graphics/native/build.py:24–31`: engine fork `135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`, Streamline `2.11.1`, FidelityFX SDK `1.1.4`; `tools/graphics/native/product.py` | Separate Forward+/Vulkan package, DLSS/DLAA, FSR 3.1.4 and real Reflex integration; runtime capability checks and Standard recovery | Does not replace the official engine pin. Older fork capabilities and import behavior differ. The [native guide](../../../tools/graphics/native/README.md) records missing features, known workarounds and retained native trials. |
| AMD SDK 2.4 candidate | `tools/graphics/native/sdk24.py`, `build_sdk24.py`, `product_sdk24.py` | Separate signed runtime intake and upscaler candidate, provider identity and failure/reset reporting | Candidate and analytical/ML modes are not a qualified player release. Validation warnings and hardware/provider acceptance remain explicit in the [FSR evidence](../advanced-graphics-2026-10-21/amd-fsr-2026-10-28.md). |
| Apple MetalFX engine candidate | `tools/graphics/metalfx/engine.py:23`: official source commit `cafc17a192acf67903910a68aeb3c076c0907a4b` plus the named local patch stack | Instrumented allocation/failure/history paths, temporal and presentation experiments, bounded Metal ray-query and scene-input prerequisites | Isolated engine/template/capture identities matter. Read the latest dated follow-ups in [DT-MAC-11a](../desktop-delivery-investigations/DT-MAC-11a/README.md), rather than treating its earliest section as current status. |

Godot 4.8 beta 3 was published on 2026-11-09, after the project's beta 2 pin. This audit does not recommend an automatic upgrade: reproduce relevant fixes against a separately pinned candidate and preserve matched export templates. Sources: [official beta 2 release](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/), [official beta 3 release](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-3/), checked 2026-11-15.

## 2. Code-to-behavior map

Line locations refer to the audited commit, not moving `main`.

| Boundary | Evidence | Audit interpretation |
| --- | --- | --- |
| Requested preferences and persistence | `app/app_state/display_preferences.gd`: reconstruction, sharpness, Reflex, VSync, frame limit and AA validation/save/load | Reuse this contract. New DRS policy must preserve saved user intent, recovery, Keep/Revert and defaults. |
| Graphics UI and display trial | `app/ui/settings_screen.gd`, `DISPLAY_TRIAL_KEYS`, `_reflex_picker`, reconstruction controls | A selectable option must have a capability reason and observable effective state. Do not equate saved selection with execution. |
| Reconstruction providers | `app/render/reconstruction.gd:7–37,78–187,246–279` | Fixed named scales, per-provider gates and temporal AA ownership already exist. Use one scale writer rather than adding a second independent settings path. |
| Automatic reconstruction | `app/render/reconstruction.gd:38–43,160–166,238–255` | `Auto` chooses MetalFX Spatial only above its minimum input-height threshold, otherwise Native. It is capability/output-size selection, not a GPU feedback controller. |
| Temporal continuity and failure | `app/render/reconstruction.gd` history/reset and runtime-failure methods; `app/render/metalfx_policy.gd`; native reset patches | Camera changes, resize, provider fallback and future scale changes need consistent history ownership and acknowledgement. |
| NVIDIA latency adapter | `app/render/nvidia_reflex.gd:6–8,19–53,83–96`; `tools/graphics/native/reflex_lifecycle.patch`, `reflex_sync.patch` | The application requests a mode; the custom engine owns SDK scheduling, state and frame markers. The ordinary official engine cannot acquire this feature from the GDScript label alone. |
| Renderer/effect selection | `app/render/high_graphics_profile.gd:19–23,68–80,98–139` | High follows actual Forward+ startup and adds selected raster effects. Restart and fallback must remain explicit; renderer switching is not a per-frame quality adjustment. |
| Viewport diagnostics | `app/render/frame_diagnostics.gd:45–105,135–175` | Records renderer, hardware and limited viewport timings; correctly labels delayed/zero ambiguity and absent physical presentation timing. |
| Interactive GPU observations | `app/debug/render_probe.gd:33–54,68–102` | Existing root and subviewport observations are useful diagnostic inputs, but explicitly do not establish fresh per-frame whole-GPU samples. |
| Simulation isolation | `app/project.godot:43–48`, the [kernel boundary](../../STACK.md#boundaries-and-data-flow) | Preserve fixed 240 Hz simulation and catch-up policy. Graphics changes consume detached presentation state and must not change aerodynamic, input, physics or replay laws. |

## 3. Findings and decisions

Finding IDs below identify this audit only; they do not create a new implementation track.

### F01 — Dynamic resolution is missing as a control loop

**Class:** confirmed capability gap, not a regression. **Priority:** high for the requested feature.

The runtime holds named constant scales in `SCALES`; `auto_mode()` considers only capability and output height. `apply()` sets the chosen scale when configuration is applied. There is no target GPU budget, sample age, deadband, asymmetric recovery or continuous scale policy in those production paths. Existing reconstruction and settings tests establish fixed-mode behavior, not adaptive regulation.

**Decision:** add an optional controller through the current reconstruction boundary after timing and scale-transition qualification. Keep fixed modes fully usable. Do not market the existing Auto mode as dynamic resolution.

### F02 — GPU timing ownership can interfere across diagnostic consumers

**Class:** confirmed source-level ownership hazard; no live overlap reproduction performed in this audit. **Priority:** high before adding a persistent controller.

`FrameDiagnostics.start()` enables `viewport_set_measure_render_time(root_rid, true)` at line 88, and `stop()` disables it at line 142. Independently, `RenderProbe.set_measure()` writes the same per-RID boolean through `_enable()` at line 44. If both consumers are active, stopping one can disable measurement while the other still considers itself enabled.

**Decision:** coordinate timing through one shared owner with acquire/release semantics, and test both stop orders plus freed/recreated viewports. A future DRS controller must detect stale or missing observations independently; a positive cached value is not sufficient evidence of fresh GPU work.

### F03 — Existing observations are not yet a reliable DRS actuator input

**Class:** documented measurement limitation. **Priority:** high.

The current diagnostic code explicitly labels root timing `root_only_freshness_unverified`; secondary readings may belong to a viewport that did not draw. `FrameDiagnostics` records no presentation timestamps and notes that a zero GPU value can mean unavailable. Driving DRS directly from `_process(delta)`, overall FPS, or these unqualified samples can lower image quality during CPU stalls, frame-cap waits, minimized windows or stale GPU observations.

**Decision:** require source/render-frame identity, viewport generation, sample age/validity, and a defined measured scope. Distinguish root scalable work, fixed rendering work, other viewports, CPU simulation and presentation waits. Hardware-specific tests must determine which signals are actually obtainable without a stall.

### F04 — Reflex is implemented in a separate native path; its benefit is unmeasured

**Class:** implemented functionality with an open acceptance gate. **Priority:** high for honest feature claims.

The current helper, preferences, UI, engine patches and retained RTX 3090 trials demonstrate more than a placeholder. The [October 28 integration evidence](../visual-quality-implementation/VQ-07/native-reconstruction-2026-10-24/README.md#follow-up-usable-nvidia-package-and-reflex-integration--2026-10-28) records successful Sleep calls and mode/marker behavior, while explicitly leaving latency and hardware breadth open.

**Decision:** extend and qualify this implementation. Keep requested, accepted and failed states distinct. Measure complete input-to-display behavior before claiming a number, and evaluate Boost's power/thermal cost separately.

### F05 — RT prerequisites exist; a complete normal-flight RT effect is not established

**Class:** partial infrastructure and open feature work. **Priority:** medium, after the basic performance contract.

The Metal patch stack includes a triangle-query subset and scene-input diagnostics. Upstream Godot has low-level Vulkan ray-tracing APIs. Those foundations do not establish whole-scene geometry/material coverage, a valid motion/history chain, denoising, scalable memory use or a default-off production effect. Existing raster shadows, SSAO and reflections are not evidence of a hardware RT implementation.

**Decision:** prototype one optional effect on explicit capabilities. Reuse the existing Apple producer plan and upstream Vulkan APIs; preserve a raster fallback. The topic report defines the narrower integration and acceptance boundary.

### F06 — Build families and evidence dates need to remain visible

**Class:** integration and reporting risk. **Priority:** high when releasing new options.

Official beta 2, the older NVIDIA fork, the AMD loader candidate and the Apple patch stack do not have identical features or packages. A setting name, generic current documentation, or a historical 720p trial cannot qualify all of them at 1080p. The source already contains several strong capability/failure receipts; reuse those instead of creating a marketing-only support matrix.

**Decision:** record engine hash, patch/SDK identity, actual renderer/driver, package identity and effective mode in every benchmark and support decision. Preserve real/generated/presented frame distinctions. Newer upstream releases are investigation candidates until their exact dependencies and regressions are checked.

## 4. Search method and limits

The code graph tools named in repository guidance were not exposed in this session. The audit therefore used tracked-file inventory, literal `rg`/`git grep`, current-source reads, engine patch/build inspection, existing tests and retained evidence. Searches covered production `app/` source, graphics/build tools, relevant tests, plans and dated graphics/desktop evidence. Terms included `scaling_3d_scale`, reconstruction providers, `dynamic_resolution`, Reflex/Streamline/low-latency markers, `ray_query`, ray-tracing APIs, MetalFX and GPU measurement calls.

Negative findings mean no complete implementation was established in that inspected scope. They are not a claim that no occurrence exists in every historical commit, unmerged branch, external engine binary or local experiment. The supplied aircraft-plan image is unrelated to these rendering questions and was not used.

No runtime implementation, engine upgrade, defaults change, release publication, physical-flight test or native GPU benchmark is part of this documentation branch. Retained measurements are attributed to their original source and hardware; they are not fresh measurements of this audit commit.
