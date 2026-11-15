# R07 — Reusable Vulkan targets and active render extents

Investigated 2026-11-15 against OpenRC application baseline `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. This is source research, not a new hardware test.

**Question and decision.** Is there a practical public implementation of scaling without reallocating the scene target for each scale? Yes: Vulkan Guide's author demonstrates retaining preallocated color/depth targets, rendering a bounded active region and blitting it to the swapchain. It is a useful model, not a drop-in Godot fix or temporal upscaler. Any OpenRC engine change must account for every consumer and prove resource lifetime.

## Sources inspected

- Original author's Vulkan Guide repository at [`1db9eee73cf1e56ce205f384312d3a02795ccf00`](https://github.com/vblanco20-1/vulkan-guide/commit/1db9eee73cf1e56ce205f384312d3a02795ccf00), 2025-10-14: actual code blocks in [window resizing](https://github.com/vblanco20-1/vulkan-guide/blob/1db9eee73cf1e56ce205f384312d3a02795ccf00/docs/new_chapter_3/resizing_window.md) and [render-loop setup](https://github.com/vblanco20-1/vulkan-guide/blob/1db9eee73cf1e56ce205f384312d3a02795ccf00/docs/new_chapter_2/vulkan_new_rendering.md); [published explanation](https://vkguide.dev/docs/new_chapter_3/resizing_window/). The article embeds implementation snippets; it is an educational example rather than a production engine repository.
- [Khronos Vulkan render-pass specification](https://docs.vulkan.org/spec/latest/chapters/renderpass.html) constrains render area to the attached image views. Godot maintainer [clayjohn's allocation discussion](https://github.com/godotengine/godot/pull/52232#issuecomment-907850735) is triangulated against the [pinned buffer implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp).

## Concrete finding

The guide creates a draw image with a recorded `imageExtent`, storage/color/transfer usages and a GPU-local VMA allocation; it stores a separate `_drawExtent`. The resize chapter retains draw and depth images at a preset size, calculates each active dimension as `min(swapchainExtent, drawImageExtent) * renderScale`, bounds the example slider to 0.3–1.0, and uses a scaled blit to the swapchain. ImGui is drawn separately at output resolution. On a changed swapchain it checks out-of-date results and, in this simple tutorial, waits for device idle before destroying and recreating swapchain resources. This is actual source-level logic, not a measured no-stall guarantee or feedback controller.

The active extent must fit its images; compute dispatch, raster viewport/scissor, copies and samples must use the correct region rather than stale pixels outside it. Reusing a large allocation saves repeated allocation at the cost of larger allocations and potentially greater residency, and excessive output size can be enlarged from a smaller input rather than remaining native. The tutorial's linear blit and HUD order do not solve temporal jitter, depth/velocity, image history, MSAA resolve, exposure, screen-space shaders, mip bias or all HDR/format issues. It also does not prove a continuously changing scale has acceptable frame pacing. A production implementation needs safe in-flight resource retirement, including resize and device loss; its coarse `vkDeviceWaitIdle` is an explanatory example, not a recommended per-frame mechanism.

## OpenRC mapping and choice

At beta2, Godot's [server scale setter](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_viewport.cpp) reconfigures RD buffers for a changed float. A max-allocation/active-extent approach would therefore require engine work across its renderer, not merely changing [`reconstruction.gd`](../../../../app/render/reconstruction.gd). Review viewport sampling, canvas/HUD, custom buffers, all scaling modes and vendor adapters before calling it portable to Godot. The [NVIDIA study](R04-nvidia-dlss-dynamic-input.md) identifies one specific subrect-tag requirement; the Metal and FSR paths have their own contracts.

**Adopt:** separate allocation, actual render, and output dimensions; bounded extent; synchronized resource generation; native-resolution UI; a maximum-memory budget and explicit fallback. **Avoid:** assuming Vulkan image views alone solve the transition, hardcoding the tutorial's 0.3 minimum as a quality choice, resizing the swapchain on every internal-scale change, or inventing another renderer. Keep 1920×1080 the first objective and the 240 Hz float64 simulation unchanged.

## Bounded next deliverable and stop

Under VQ-07's [M0–M2 sequence](../05-integrated-implementation-plan.md), M0 is capped at five engineering days total and reuses [`frame_diagnostics.gd`](../../../../app/render/frame_diagnostics.gd), [`render_probe.gd`](../../../../app/debug/render_probe.gd), the [debug bridge](../../../../app/debug/debug_bridge.gd) and existing harness. M1 first completes a fixed-provider transition correction. Conditional M2 can make one isolated engine prototype: two active sizes, one maximum target generation, verified actual dimensions and bounded VRAM, with validation-clean resize/fallback, 1080p moving-aircraft/HUD and temporal results. Stop if any required pass samples outside the active area, GPU lifetime is unclear, timing is stale, or a fixed-scale ablation shows no meaningful opportunity. A larger engine architecture remains deferred.

## Limitations

The guide is a small illustrative Vulkan renderer with source excerpts, not a Godot patch or measured OpenRC result. This investigation performed no GPU run or memory measurement; all speed and image-quality benefits remain device- and scene-dependent.
