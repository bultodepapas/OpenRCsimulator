# R03 — AMD FSR sizing and temporal history

Investigated 2026-11-15 against OpenRC application baseline `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. This is source research, not a new hardware test.

**Question and decision.** Does AMD's existing FSR sample show how to vary render size safely, and is that automatically available in OpenRC? The sample demonstrates a context maximum and a per-dispatch render size with history signaling. It does **not** establish that either the stock Godot FSR2 path or OpenRC's separate FSR3 trial supports efficient dynamic transitions. Reuse the provider and engine path already owned by VQ-07.

## Sources inspected

- AMD FSR SDK 2.4.0, commit [`7539ae8b6568ad29ed78a753404351daf3b5cca7`](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/commit/7539ae8b6568ad29ed78a753404351daf3b5cca7), 2026-10-28: actual [sample render module](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/7539ae8b6568ad29ed78a753404351daf3b5cca7/Samples/Upscalers/FidelityFX_FSR/internal/fsrapirendermodule.cpp) and [FSR3 upscaler header](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/7539ae8b6568ad29ed78a753404351daf3b5cca7/Kits/FidelityFX/upscalers/fsr3/include/ffx_fsr3upscaler.h).
- AMD's [FSR 3.1.6 integration manual](https://gpuopen.com/manuals/fsr_sdk/techniques/super-resolution-upscaler/) and [API introduction](https://gpuopen.com/manuals/fsr_sdk/getting-started/ffx-api/) are authoritative context; the source identifies what the sample actually passes.
- OpenRC's [native build](../../../../tools/graphics/native/build.py) pins FidelityFX SDK 1.1.4 / FSR upscaler 3.1.4; stock Godot's FSR2 is a separate 2.2 implementation. The [FSR completion plan](../../../plans/amd-fsr-completion.md) and [current audit](../02-dynamic-resolution-and-upscaling.md) record their open validation.

## Concrete finding

In AMD's 2.4 sample, `CreateContextDescUpscale` sets `maxRenderSize` and `maxUpscaleSize`; for its `CustomDRS` preset it additionally sets `FFX_UPSCALE_ENABLE_DYNAMIC_RESOLUTION`. Switching into or out of that preset sets `m_NeedReInit`. Its frame dispatch supplies the actual `renderSize` and output `upscaleSize`, color, depth, motion vectors, jitter, motion-vector scale, frame delta in milliseconds and a reset flag derived from explicit request or camera reset. This is a concrete setup and dispatch sequence, not a proof that every scale change forces or avoids context recreation. The sample's `UpdatePreset` queries supported quality ratio instead of treating a preset number as universal.

The FSR3 header distinguishes maximum rendering dimensions in the context from the size used by a particular dispatch, and defines reset for a discontinuous camera. AMD's guide describes matching depth/motion-vector resolutions and conventions to the selected flags. A temporal transition needs coherent color, depth, velocity, exposure, jitter, mip selection and history; a resize by itself should not be conflated with a camera teleport. The precise rule for retaining history must be verified for the exact FSR version and implementation. Allocating at maximum size can trade memory for reduced churn; neither zero hitch nor quality follows from the API alone.

## OpenRC mapping and choice

[`reconstruction.gd`](../../../../app/render/reconstruction.gd) exposes fixed FSR2 choices and sends history requests. [`camera_rig.gd`](../../../../app/render/camera/camera_rig.gd) supplies discontinuity requests, but official or older engines can lack a provider reset endpoint; the [existing history fixture](../../../../app/tests/test_reconstruction_history.gd) covers the unavailable seam. [`tools/graphics/native`](../../../../tools/graphics/native/README.md) owns the Windows/Vulkan custom 3.1.4 trial and a distinct 2.4/3.1.6 candidate. These are not interchangeable with AMD's current sample or evidence of a production integration.

**Adopt:** query the actual provider, bound context dimensions, pass real per-frame extents and correct reset/motion/jitter metadata; preserve fixed-scale fallback and user selections. **Avoid:** calling a new FSR SDK an upgrade to stock Godot without a reviewed engine integration, assuming SDK dynamic support fixes the Godot allocation path, resetting temporal history blindly each frame, or adding a competing SDK wrapper. Frame generation is a different feature.

## Bounded next deliverable and stop

Under VQ-07, the [M0–M2 plan](../05-integrated-implementation-plan.md) budgets at most five total engineering days for a minimal existing-harness timing gate. If an FSR provider is selected for M1, choose one existing fixed-size history/transition defect and exercise the existing fixture plus a narrow native 1080p moving/camera-cut screen; require an observed accepted reset reaching the intended provider and correct fallback on failure. Only then, in conditional M2, compare two in-range input sizes, actual dispatch dimensions and context generations using existing diagnostics and debug bridge. Stop if validation warnings, missing reset acknowledgement, stale timing or visible aircraft/HUD artifacts remain. Do not enlarge the measurement stack; preserve 240 Hz float64 simulation.

## Limitations

Sample code and SDK documentation are not hardware measurements or a quality comparison. AMD 2.4 flags and API names must not be projected back onto the project's pinned 1.1.4 integration without source verification. This investigation ran no build or GPU test.
