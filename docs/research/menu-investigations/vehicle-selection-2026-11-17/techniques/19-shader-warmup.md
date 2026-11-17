# T19 — First-use shader and pipeline warmup

**Research date:** 2026-11-17. **Status:** proposal; no runtime measurements. [Twenty-investigation index](README.md).

**Question.** If a real selected vehicle's first use is shown to stall on shader or pipeline work, can a bounded representative draw move that work into an appropriate transition without increasing total user wait or weakening selection identity?

**Searches actually run (2026-11-17):** `site:docs.godotengine.org pipeline compilations compatibility warm up render ubershader mobile specialization`; `site:docs.godotengine.org/en/stable/classes/class_performance.html PIPELINE_COMPILATIONS_MESH PIPELINE_COMPILATIONS_SPECIALIZATION compatibility`; and `site:developer.apple.com metal compile shader pipeline state cache asynchronous cost first use`.

## Evidence and limits

- [Godot's pipeline-compilation guide](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html) calls for an actual in-frustum draw on Compatibility. Forward+/Mobile have precompilation and background specialization; material overrides and MSAA can still change the required pipelines. Loading or hiding a model therefore does not prove warmup coverage. Qualify the pinned beta2 and target drivers independently.
- Godot's [RenderingServer statistics documentation](https://docs.godotengine.org/en/latest/classes/class_renderingserver.html) names separate compilation counters and actual renderer/driver queries. Latest documentation is unstable: use only counters available in the pinned executable, validate availability and treat positive deltas as correlation, not proof of the cause or duration of a particular frame. A fresh process does not guarantee a cold driver cache. Do not erase the user's driver cache; record its controlled or unknown state.

The same guide distinguishes optional intermediate shader baking for Mobile/Forward+ from final hardware pipelines; baking does not help Compatibility. A proposed warmup must therefore qualify the actual OpenRC path, rather than borrow another renderer's result. Future material, lighting and quality combinations remain separate coverage questions.

## OpenRC seam and proposed application

[Project settings](../../../../../app/project.godot#L61-L75) use Compatibility normally and Mobile for the Apple Silicon native route, with configured 3D MSAA. [HomeScene](../../../../../app/ui/home_scene.gd#L434-L485) constructs and prepares the accepted candidate, then publishes it under the current request generation. [AppRoot](../../../../../app/app_root.gd#L684-L695) already gives the newly built Home a first draw before the menu; [staged aircraft launch](../../../../../app/app_root.gd#L1644-L1654) also draws the configured paused candidate behind its opaque surface. Check whether those existing frames already cover the relevant work before inserting any more preparation; other activity launch paths require their own audit.

If attribution warrants an experiment, prepare **only the selected, still-current** vehicle/skin in a bounded transition. Exercise its actual mesh/material overrides and relevant lighting, shadow and MSAA state. For Compatibility, prove a representative in-frustum render occurred; if a separate viewport or overlay is used, demonstrate that it matches the relevant real path and does not expose the wrong vehicle. Do not warm all models or all possible permutations, invent a guarantee from a preloaded resource, or delay a cache hit by a fixed animation. On replacement or cancel, preserve current generation/ownership and release unused work. Existing texture upload and scene construction may coincide with the same frame; distinguish them before crediting shaders.

The [debug bridge](../../../../../app/debug/debug_bridge.gd#L1723-L1728) records a sum of five pipeline monitors per frame; it is useful for a lead, but the sum hides which category changed. If needed, add reviewed per-category diagnostics without altering hashed builders, and compare no-observer controls. GPU frame samples with unverified freshness remain context, not exact timing for that frame.

## Experiment and decision

Under [E0/E8](../benchmark-protocol.md), compare current first-draw behavior with one selected-path warmup, matched vehicle/skin, landscape, day/night, renderer, MSAA, GPU/driver and isolated profile. Test Compatibility and actual Apple Silicon Mobile/Metal separately, at 1080p first. Record pre-transition acknowledgement, warmup elapsed and CPU/GPU work, first correct detailed draw, first launch/control-ready frame, all frame-interval tails, compilation counter deltas, memory peak and discarded work after rapid reselection. Include immediate Fly, warm retained selection and post-eviction revisits. Screen five alternating fresh-process pairs and 20 warm transitions; follow protocol qualification for tails.

Reject if identity/visual behavior fails, any first-Home/launch or rapid-browse cost materially regresses, memory grows beyond the admitted budget, or end-to-end benefit does not exceed variation. **Recommendation:** optional **UI-VS-10**, only after **UI-VS-00** attributes a first-use cost and **UI-VS-02/05/07** provide admission, ownership and selected-path context. No present hitch or speedup is claimed.
