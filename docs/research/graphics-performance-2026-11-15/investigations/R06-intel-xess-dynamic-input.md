# R06 — XeSS-SR dynamic input and public sample

Investigated 2026-11-15 against OpenRC application baseline `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. This is source research, not a new hardware test.

**Question and decision.** Does Intel's current public XeSS-SR support varying input resolution, and should OpenRC add it now? The current guide says yes within queried bounds, but the inspected Vulkan sample uses a fixed-resolution flow and OpenRC has no XeSS provider. Defer a new integration: validate an existing provider and a shared render-scale contract first.

## Sources inspected

- Intel XeSS repository commit [`de0fb9c1c510661c571164e1418ceca8101dab69`](https://github.com/intel/xess/commit/de0fb9c1c510661c571164e1418ceca8101dab69), 2026-09-09: [XeSS-SR developer guide 2.0](https://github.com/intel/xess/blob/de0fb9c1c510661c571164e1418ceca8101dab69/doc/xess_sr_developer_guide_english.md) and the actual [basic Vulkan triangle sample](https://github.com/intel/xess/blob/de0fb9c1c510661c571164e1418ceca8101dab69/samples/basic_sample_super_resolution_vk/triangle.cpp) were inspected.
- Intel's [older web guide](https://www.intel.cn/content/www/cn/zh/developer/articles/guide/xe-super-sampling-developer-guide.html) says dynamic resolution is unsupported. This conflicts with the newer versioned guide; it is not evidence that the current SDK lacks the feature.
- Godot's [maintainer discussion](https://github.com/godotengine/godot/pull/52232#issuecomment-907850735) and the [pinned viewport server](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_viewport.cpp) constrain engine applicability independently of vendor support.

## Concrete finding

The current guide describes fixed output with dynamic input inside `pInputResolutionMin` to `pInputResolutionMax`, passing the actual width and height in each `xess_*_execute_params_t`. It recommends preserving target aspect ratio and updating texture mip bias with changing input. It advises querying optimum and range rather than hardcoding ratios; presets changed beginning with XeSS 1.3. These are SDK-level statements, conditional on exact runtime, API and device support. They do not establish an automatic controller, compatible Godot bridge or OpenRC results.

The sample is a useful counterweight to an overly broad claim: `triangle.cpp` creates and initializes a Vulkan context, queries a single `xessInputResolution` with the older `xessGetInputResolution`, allocates input attachments and passes that size to `xessVKExecute`, along with jitter and resource descriptions. The current guide deprecates that query since 1.2 in favor of `xessGetOptimalInputResolution`. The sample demonstrates dispatch plumbing at a fixed queried size; no feedback controller or changing-size behavior was established from that file. The newer guide supports the feature, while the historical page's contrary statement should retain its older scope.

Temporal reconstruction uses color, depth, motion and jitter and needs sound history handling; the SDK guide's Vulkan requirements include extension and device-feature queries. Version, platform, quality setting, resource states, velocity convention, history discontinuities and actual output remain mandatory integration work. Cross-vendor SDK language is not evidence of universal working support.

## OpenRC mapping and choice

[`reconstruction.gd`](../../../../app/render/reconstruction.gd) has no XeSS mode. Existing stock FSR2, trial FSR3/DLSS, and guarded MetalFX paths already need their own reset, lifetime and moving-aircraft validation. [`frame_diagnostics.gd`](../../../../app/render/frame_diagnostics.gd) and [`render_probe.gd`](../../../../app/debug/render_probe.gd) plus [debug bridge](../../../../app/debug/debug_bridge.gd) are the existing measurement path; their viewport ownership/freshness issue must be fixed before feedback. Adding another SDK does not fix the pinned Godot reconfiguration path.

**Adopt:** queried per-version resolution bounds, current input dimensions, coherent jitter/mip bias and an explicit invalid-capability fallback as provider-neutral requirements. **Avoid:** claiming the older guide describes current XeSS, claiming Intel's fixed triangle sample proves dynamic rendering, hardcoding preset scales, or building a second provider now merely to add a vendor label. Keep simulation and its 240 Hz float64 state independent.

## Bounded next deliverable and stop

Under existing VQ-07 ownership, the [M0–M2 plan](../05-integrated-implementation-plan.md) first spends at most five total engineering days on the minimal existing timing/ownership seam; unavailable or stale data fails DRS closed. M1 completes one existing provider's fixed transition and reset evidence at 1080p. M2 considers bounded adaptive input only if fresh timing, actual extent/lifetime and temporal correctness are established. XeSS remains deferred unless an existing cross-vendor path is insufficient and a separately scoped decision identifies a maintained engine integration, exact SDK/device capability, export/licensing and clear incremental benefit. Stop rather than create a new controller or benchmark stack.

## Limitations

No XeSS build, hardware execution or quality/performance comparison occurred. The guide and sample come from one inspected repository snapshot; runtime and driver behavior must be queried and checked on each candidate device.
