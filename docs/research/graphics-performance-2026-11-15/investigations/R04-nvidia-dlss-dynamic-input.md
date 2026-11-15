# R04 — Streamline DLSS input extents and reset

Investigated 2026-11-15 against OpenRC application baseline `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. This is source research, not a new hardware test.

**Question and decision.** Can the project's NVIDIA Godot trial already drive DLSS over subrectangles of a reusable maximum-size texture? The SDK describes that capability, but the inspected fork tags resources with a null extent. That is compatible with a whole-texture fixed-size interpretation and is **not** proof of a fixed-scale defect; it is a concrete reason not to claim the desired subrectangle contract is present. Verify the local patch stack and provider dispatch before any adaptive trial.

## Sources inspected

- The project's [native build script](../../../../tools/graphics/native/build.py) identifies NVIDIA Godot commit [`135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`](https://github.com/NVIDIA-RTX/godot/commit/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76) and Streamline **2.11.1**. Inspected the fork's [DLSS renderer implementation](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/servers/rendering/renderer_rd/effects/dlss.cpp), not just its README. Project patches may alter this upstream code.
- NVIDIA's [2.11.1 DLSS guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuideDLSS.md), [2.11.1 `sl_dlss.h`](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/include/sl_dlss.h), and [2.11.1 `sl_consts.h`](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/include/sl_consts.h) define the pinned SDK contract.
- Current upstream Streamline commit [`625db07d4bca5abc67d781c42af7e7fb0761f1b6`](https://github.com/NVIDIA-RTX/Streamline/commit/625db07d4bca5abc67d781c42af7e7fb0761f1b6), 2026-10-16, is version 2.14.16; its [DLSS guide](https://github.com/NVIDIA-RTX/Streamline/blob/625db07d4bca5abc67d781c42af7e7fb0761f1b6/docs/ProgrammingGuideDLSS.md) and [constants](https://github.com/NVIDIA-RTX/Streamline/blob/625db07d4bca5abc67d781c42af7e7fb0761f1b6/include/sl_consts.h) were compared. Current upstream is not the project pin.

## Concrete finding

Both SDK guides say to query optimal settings, including dynamic source-size minima and maxima when supported, and to provide an extent for every tagged resource when using dynamic resolution. The pinned header actually names the fields `optimalRenderWidth/Height` and `renderWidth/HeightMin/Max`; use the exact header rather than relying on illustrative guide variable names. Depth, motion, input color and output color are required with correct resource lifecycle. The SDK `reset` constant describes a frame with no valid temporal relationship to the previous one; it is not a generic instruction to reset on every scale step.

The fork's `dlss.cpp` asks for optimal settings and checks candidate dimensions against min/max. Its `assignResource` creates tags for input, output, depth and velocity with `nullptr` for the extent, and it sends `p_params.reset_accumulation` to `constants.reset` before `slSetConstants`. Those are real integration details. Supplying a null extent does not establish the explicit active region required when a larger resource contains a smaller frame. Conversely, reallocation to exact-size textures is not itself evidence that existing fixed DLSS is broken. Inspect the actual prepared local engine after patches; do not claim this upstream finding proves the locally built binary's exact behavior.

The local [frame-lifecycle patch](../../../../tools/graphics/native/dlss_frame_lifecycle.patch) switches to frame-based resource tagging and `eValidUntilEvaluate`, while the [failure-path patch](../../../../tools/graphics/native/dlss_failure_paths.patch) changes output layout handling. Source review found no addition of explicit dynamic `Extent` values in those patches. This strengthens the future-subrectangle concern without substituting source inspection for exact prepared-engine and runtime verification.

## OpenRC mapping and choice

[`reconstruction.gd`](../../../../app/render/reconstruction.gd) owns provider selection and reset requests; [`camera_rig.gd`](../../../../app/render/camera/camera_rig.gd) identifies camera cuts. The [native integration guide](../../../../tools/graphics/native/README.md) records build/runtime checks and prior Vulkan validation warnings. [`render_probe.gd`](../../../../app/debug/render_probe.gd), [`frame_diagnostics.gd`](../../../../app/render/frame_diagnostics.gd), and the [debug bridge](../../../../app/debug/debug_bridge.gd) are the existing observation surfaces.

**Adopt:** one correctly sized extent per tag, queried bounds for the exact SDK, explicit resource generation/lifecycle and tested camera reset delivery. **Avoid:** treating DLSS frame generation as render scale, assuming the current 2.14 SDK is interchangeable with 2.11.1, inferring successful GPU output from enum availability, or copying one extent indiscriminately to full-resolution output and lower-resolution inputs. Preserve saved preferences and 240 Hz float64 physics.

## Bounded next deliverable and stop

Within VQ-07 [M0–M2](../05-integrated-implementation-plan.md), limit M0 timing repairs to the shared five-engineering-day cap; missing or stale samples leave DRS off. If DLSS is selected for M1, inspect the prepared fork and local patches, then exercise the existing fixed DLSS history and validation fixture on the supported Windows/Vulkan configuration at 1080p. Acceptance requires unambiguous actual provider, input/output dimensions, successful reset evaluation and clean relevant validation. Conditional M2 can test two queried in-range extents with matching input tags, stable output, correct history and resource lifetime through the existing harness. Stop on absent bounds, invalid tags, validation errors or bad moving-aircraft readability; keep fixed provider or Native fallback.

## Limitations

This is source inspection, not a new execution or performance claim. A successful `slEvaluateFeature` submission is not proof of physical presentation, temporal quality or completion. Hardware, driver, DLL, editor/export and patch identity remain necessary for a real acceptance result.
