# R02 — Unity's public adaptive-resolution system

Investigated 2026-11-15 against OpenRC application baseline `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. This is source research, not a new hardware test.

**Question and decision.** Is there a real, reusable implementation of adaptive resolution rather than just a sketch? **Yes.** Unity publishes both a pipeline handler and a separate working feedback sample. Study their division of responsibilities and asymmetrical control, but do not transplant C# or assume its render-target lifetime applies to Godot. OpenRC should make an implementation-first decision after its small existing-harness measurement gate, not build a duplicate control platform.

## Sources inspected

- Unity Graphics [DynamicResolutionHandler.cs](https://github.com/Unity-Technologies/Graphics/blob/0efc28ea742b1966b9dd9cc4489e58b986a13faf/Packages/com.unity.render-pipelines.core/Runtime/Common/DynamicResolutionHandler.cs), repository head `0efc28ea742b1966b9dd9cc4489e58b986a13faf`, 2026-10-26; implementation inspected.
- Unity's [DynamicResolution.cs sample](https://github.com/Unity-Technologies/DynamicResolutionSample/blob/9677fbd4d890f809d95aa1c3c266966646bb23c6/DynamicResolution.cs), repository head `9677fbd4d890f809d95aa1c3c266966646bb23c6`, 2022-09-16; code and [sample README](https://github.com/Unity-Technologies/DynamicResolutionSample/tree/9677fbd4d890f809d95aa1c3c266966646bb23c6) inspected.
- Unity HDRP [dynamic resolution](https://github.com/Unity-Technologies/Graphics/blob/0efc28ea742b1966b9dd9cc4489e58b986a13faf/Packages/com.unity.render-pipelines.high-definition/Documentation~/Dynamic-Resolution.md) and [asset reference](https://github.com/Unity-Technologies/Graphics/blob/0efc28ea742b1966b9dd9cc4489e58b986a13faf/Packages/com.unity.render-pipelines.high-definition/Documentation~/HDRP-Asset.md) describe pipeline behavior. Godot maintainer [allocation discussion](https://github.com/godotengine/godot/pull/52232#issuecomment-907850735) is the practical portability check.

## Concrete finding

The handler is already-built infrastructure: it tracks per-camera state, supports user/system scaler delegates, clamps either a returned percentage or an interpolation factor to configured bounds, resolves scaled sizes, and drives `ScalableBufferManager.ResizeBuffers` when hardware dynamic resolution is active. HDRP documents a software route using maximum-sized targets with a smaller viewport, as well as hardware scaling where available. The handler does **not**, by itself, define how to infer GPU pressure; its delegate must supply a policy. Pipeline, platform and camera participation matter.

The separate sample registers a delegate after an initialization delay, samples `FrameTimingManager`, and compares GPU time and its change to a target. It lowers scale promptly when over budget or expected to exceed it, and uses a counter, headroom and delta thresholds for slower increases. It resets scale when disabled, tests timing frequency on supported non-Metal paths, and logs CPU alongside GPU. These are useful engineering patterns, not proven OpenRC thresholds. In particular the inspected 2022 sample requests one timing and does not check the return count of `GetLatestTimings`; checking the preallocated array's length alone cannot establish freshness. Do not copy that assumption into a safety gate.

Unity's system is not a Godot plugin and its examples rely on Unity's timing and allocation contracts. The same-looking viewport operation in the [pinned Godot server](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_viewport.cpp) can reconfigure targets. A controller that is stable in Unity may cause resource churn in OpenRC, and does not remove CPU, pacing or shader compilation bottlenecks.

## OpenRC mapping and choice

The existing [`reconstruction.gd`](../../../../app/render/reconstruction.gd) owns provider and scale, [`frame_diagnostics.gd`](../../../../app/render/frame_diagnostics.gd) observes viewport timing, and [`render_probe.gd`](../../../../app/debug/render_probe.gd) already offers a half-resolution diagnostic. [`debug_bridge.gd`](../../../../app/debug/debug_bridge.gd) provides the control surface. A future controller belongs alongside the reconstruction owner; it must distinguish requested/effective/actual values and keep its writes from being overwritten on reapply. Existing saved user overrides remain authoritative.

**Adopt:** camera-specific eligibility, min/max constraints, fresh GPU sample checks, fast bounded reduction and slower recovery, plus a clear off/fallback path. **Avoid:** blindly importing Unity constants, assuming one timing equals a fresh completed frame, or creating another standalone controller before proving the engine can vary input safely. Render-scale policy must not modify 240 Hz float64 physics.

## Bounded next deliverable and stop

Under VQ-07, [M0](../05-integrated-implementation-plan.md) is at most five engineering days total across the effort: repair the existing shared measurement ownership and identify fresh versus unavailable readings using the current bridge and harness. A native 1080p fixed-scale ablation should show whether work is sufficiently GPU/pixel sensitive to justify a scale implementation. M1 selects one fixed-provider transition correction; M2 admits a default-off adaptive trial only if timing, safe extent/lifetime, and temporal transition evidence pass. If timing remains partial or fixed scales show no actionable pixel sensitivity, stop at fixed settings. No new telemetry application is required.

## Limitations

This is a code/design comparison, not an OpenRC benchmark or claim that Unity's thresholds or timing APIs are portable. Vendor/provider transitions and moving-aircraft readability still need real-device evidence, initially at 1080p.
