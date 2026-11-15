# R05 — MetalFX temporal dynamic input

Investigated 2026-11-15 against OpenRC application baseline `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. This is source research, not a new hardware test.

**Question and decision.** Does MetalFX expose a distinct dynamic-content contract and does OpenRC's existing trial automatically use it? Apple exposes descriptor configuration and per-frame content dimensions, but capability is not evidence that Godot's pinned bridge or the local patches implement, execute and preserve it across scale changes. Retain the existing guarded fixed-provider route and qualify it first.

## Sources inspected

- Apple's [official MetalFX sample](https://developer.apple.com/documentation/metalfx/applying-temporal-antialiasing-and-upscaling-using-metalfx), associated with WWDC22 session 10103, is identified in Apple's [sample index](https://developer.apple.com/metal/sample-code/). The page describes the project, jitter and motion-vector demonstration; the downloadable source archive was not accessible in this investigation, so its implementation was **not** independently inspected.
- Apple's [temporal scaler protocol](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscaler), [dynamic-content descriptor property](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerdescriptor/isinputcontentpropertiesenabled), and [input width property](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerbase/inputcontentwidth) define the relevant API.
- Apple-authored [integration code example](https://github.com/apple/game-porting-toolkit/blob/4f42344c90be22112f46becc3fb9687f423f2f88/game-porting-skills/skills/using-metalfx-temporal-upscaler/SKILL.md), commit `4f42344c90be22112f46becc3fb9687f423f2f88`, 2026-06-07, was inspected for descriptor creation, per-frame textures, jitter, motion scale, reset and encoding. This is an integration example, not the inaccessible sample source.
- Godot maintainer [allocation discussion](https://github.com/godotengine/godot/pull/52232#issuecomment-907850735) and [pinned RD buffer code](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp) triangulate the engine-side cost question.

## Concrete finding

Apple's descriptor says whether the created temporal scaler uses dynamic input-content properties; the scaler then receives `inputContentWidth` and `inputContentHeight` along with input/output textures before encoding. Supported device and content-scale limits, the creation descriptor, actual texture allocation and per-frame content region all need to agree. Output dimensions, texture formats and resources are separate from current active input. Query limits and device support on the executing platform; do not infer them from a product name.

The Apple example creates a descriptor from input/output sizes and formats, supplies jitter and motion conventions, tracks previous transforms, assigns per-frame resources and encodes to a command buffer. It explicitly treats output-size changes as a resize that recreates targets and scaler. Its code shows required plumbing; it does not demonstrate that OpenRC's Godot path preserves an existing context through input-size changes, nor prove completion or image quality on an M1. The original sample's unavailable source prevents a claim that it exercises dynamic content. Temporal history reset should follow a real discontinuity/provider contract, not blindly every frame.

## OpenRC mapping and choice

[`metalfx_policy.gd`](../../../../app/render/metalfx_policy.gd) gates actual Metal, device features and temporal trial; [`reconstruction.gd`](../../../../app/render/reconstruction.gd) handles selection, nominal input and reset receipts; [`renderer_guard.gd`](../../../../app/app_state/renderer_guard.gd) preserves a recovery path. The existing [MetalFX patch stack](../../../../tools/graphics/metalfx/README.md) provides isolated trials and generation/completion observation. Its actual descriptor and content settings must be inspected in the exact built revision, rather than inferred from Apple documentation. The existing retained M1 screen and its limitations are in the [parent audit](../02-dynamic-resolution-and-upscaling.md).

**Adopt:** actual queried bounds; a descriptor explicitly configured for dynamic content if supported; per-frame real dimensions and matching jitter, depth and motion; GPU-completed reset and safe lifetime. **Avoid:** applying a temporal API claim to Spatial, calling nominal dimensions actual allocation, assuming API encode equals GPU completion, or shipping a second MetalFX bridge. Keep 1080p first and do not modify 240 Hz float64 physics.

## Bounded next deliverable and stop

Within VQ-07, [M0–M2](../05-integrated-implementation-plan.md) reuse [`frame_diagnostics.gd`](../../../../app/render/frame_diagnostics.gd), [`render_probe.gd`](../../../../app/debug/render_probe.gd), [debug bridge](../../../../app/debug/debug_bridge.gd) and the existing MetalFX harness. M0 has a shared five-engineering-day ceiling; partial/stale timing is unavailable, so DRS stays off. If MetalFX is selected for M1, inspect descriptor creation and complete one fixed temporal reset/transition case on the actual device. M2 is conditional: show two supported input sizes on one bounded scaler generation with correct output, completion, reset and moving-aircraft image evidence. Stop if the bridge cannot expose the contract, device returns invalid limits, history or lifetime fails, or timing cannot be trusted.

## Limitations

The Apple sample archive was not inspected and this work performed no Metal execution. The Apple example and API permit a design, not a result on the project's beta engine or a universal performance benefit. Query support and independently verify any actual generation and output.
