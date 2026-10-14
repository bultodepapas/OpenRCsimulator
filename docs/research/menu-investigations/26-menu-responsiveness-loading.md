# 26 — faster aircraft selection without hiding stalls

2026-10-14. Internet research and current-source review for UI-05 follow-up. **Proposed experiments, not delivered optimizations.** Engine: pinned Godot 4.7.2, Compatibility. The [menu guide](../../MENU-PLAN.md) owns behavior; the [global plan](../../plans/global-performance-visual-quality.md) owns loading/texture gates. No runtime, import, asset or physics changes were made for this investigation.

Implementation follow-up: [UI-05-R3](UI-05-R3/README.md) delivers latest-selection handling and bounded loading of selected resources after attribution. Neighbor prefetch and texture/shader experiments below remain conditional. This dated investigation retains its original proposal scope; current behavior and measured limits live in the follow-up.

## What needs fixing

[UI-05-R2](UI-05-R2/README.md) already retains three recent visual models. Its small native campaign measured warm selection handlers around 4.9–5.9 ms and completion through `frame_post_draw` around 12.4–13.2 ms. First visits still cost 355 ms for Extra and 1415 ms for the jet in that run. These are different populations; neither measures physical input-to-display latency.

Current-source observations, against a shared tree whose HEAD was `c642a997b758d58b9eefefe6f6f3ab6b9ab44742` plus existing edits:

- [AppRoot.set_aircraft](../../../app/app_root.gd) updates preferences/card, synchronously builds/shows the preview, then saves preferences. Updating a label before a long call does not let the renderer present it during that call.
- [HomeScene.show_aircraft](../../../app/ui/home_scene.gd) builds cache misses, collects neutral shadow geometry and fits night lighting. A retained node avoids these stages. Home replacement invalidates that cache.
- [ImportedModel.build_checked](../../../app/aircraft/imported_model.gd) synchronously loads generated geometry and a `PackedScene`, instantiates it, then validates and constructs bindings. Resource loading is only one stage; procedural families need separate attribution.
- The retained [native verbose log](UI-05-R2/native-final.log) contains individual 2048² BasisU transcodes of 52, 46 and 55 ms. This is a lead, not a measured percentage of the selector's total time.
- The earlier [VQ-02a texture audit](../visual-quality-implementation/VQ-02a/README.md) predates the imported Avanti integration. Its zero assigned Avanti textures cannot describe today's jet. Reuse its inventory tools, not its consumer counts.

Graph discovery returned no HomeScene nodes; current source was read as fallback. Existing implementation evidence remains unchanged.

## Findings from Godot and the community

### Load resources early, with an explicit limit

Godot's [background-loading guide](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html) separates requesting a resource from retrieving it. Retrieving before completion blocks. The [4.7 ResourceLoader API](https://docs.godotengine.org/en/4.7/classes/class_resourceloader.html) recommends checking status across frames and warns that `use_sub_threads=true` can slow the main thread.

**Proposal:** start with one outstanding resource request, default subthreads off, and at most two retained prospective `PackedScene` references. Prefetch only after Home has presented, prioritizing the current request and then the next likely aircraft in the navigation direction. Stop speculative scheduling when selection changes or Home exits. Deduplicate paths; retrieve only `THREAD_LOAD_LOADED`, handle failure, and keep a request ledger for teardown. The documented API has no cancellation method: invalidating a result does not cancel its engine work. Completed obsolete results must be retrieved/released without applying them; ownership must survive a closing Home long enough to drain pending requests.

Godot's [Resource lifetime contract](https://docs.godotengine.org/en/4.7/classes/class_resource.html) removes cache entries when all references disappear. Hold bounded strong references deliberately; merely calling `load()` once is not a persistent prefetch cache. Resource references and the existing three instantiated previews are distinct memory costs.

The free MIT [official threaded-loading demo](https://godotengine.org/asset-library/asset/2778), with its [4.2 repository example](https://github.com/godotengine/godot-demo-projects/tree/4.2/loading/threads), is a pattern reference. It is not a 4.7 performance qualification or a reason to adopt another framework.

### Make the latest selection win

**Project-specific proposal:** separate requested aircraft ID, displayed preview ID and request generation. Update text/focus immediately. Replace pending preview intent instead of queueing every intermediate aircraft. A completion may replace the model only if its generation, Home instance and presentation context still match. Cached hits remain immediate; no mandatory debounce delay.

Keep the previous image while preparing, with a translated loading state that makes any card/image mismatch explicit. Do not show resource progress as overall preview readiness: instantiation, validation, shadow setup and first draw remain. Fly always resolves the latest requested, valid aircraft; it must never launch the last displayed model by accident. Back, rapid reversal, language changes and Home replacement invalidate obsolete UI completions.

[`Object.call_deferred`](https://docs.godotengine.org/en/stable/classes/class_object.html#class-object-method-call-deferred) schedules idle work, not a worker thread. Deferred calls can drain in the same idle cycle. Use explicit frame boundaries for genuinely incremental work; one monolithic `instantiate()` or builder call cannot be interrupted by an outer time budget. Showing a spinner before that call will not animate through its stall.

### Remove repeated texture conversion if measurements support it

The [image import guide](https://github.com/godotengine/godot-docs/blob/master/tutorials/assets_pipeline/importing_images.rst) describes Basis Universal as transcoded at load time, whereas VRAM Compressed stores a GPU format prepared during import. Its disk-size and image-quality tradeoffs differ. The [3D import options](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html) allow extracting embedded glTF images to external files with their own import settings.

**Proposal:** on a disposable, frozen Avanti snapshot, compare current embedded BasisU against extracted original textures imported with desktop VRAM compression. Preserve source pixels, dimensions, mipmaps, color-space roles, normal channels, alpha and material bindings. Regenerate through the accepted pipeline; do not hand-edit generated aircraft geometry or replace textures with new artwork. Follow existing VQ-01c/d and VQ-02a gates before production adoption.

[Engine issue #120000](https://github.com/godotengine/godot/issues/120000), opened 2026-06-03 and open when read, discusses BasisU target-format preference. The [exact 4.7.2 transcoder source](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/basis_universal/image_compress_basisu.cpp) checks BPTC before ASTC/S3TC for RGB/RGBA, consistent with our log. This does not establish a bug in our application or a universal 2× VRAM saving. Inspect actual output formats and images: ordinary Compatibility compression may change quality. Do not assume the high-quality import checkbox makes all paths equivalent.

### Warm the actual render path only when first draw is the problem

Godot's [stutter guide](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html) explicitly distinguishes Compatibility: it requires rendering the relevant meshes/effects in camera for a frame to warm shaders; solid 2D UI can cover that frame. Hidden nodes alone are not the stated Compatibility recipe. The [pipeline guide](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html) says shader baking only affects Forward+/Mobile, not Compatibility.

**Conditional proposal:** if first-draw timing is material after CPU/loading repairs, test a bounded warmup using the real aircraft, material features, lights, shadow path and MSAA. Preserve the ready model when useful. Measure startup cost as well as later selection. A generic sphere or 1×1 ColorRect does not demonstrate coverage of this 3D path. Shader warmup does not remove validation or BasisU conversion costs.

### Community reports are hypotheses, not engine guarantees

- [Godot Forum, 2024-04-06, 4.2.1](https://forum.godotengine.org/t/background-loading-freezing-main-thread/54782): the author reports stalls with subthreads both on and off, even without scene switching. Therefore “set subthreads false” is a benchmark variant, not a proven cure. The current API independently documents possible contention.
- [Reddit first-instance discussion, 2024](https://www.reddit.com/r/godot/comments/1bjpm9m/godot_411_stutterfreeze_when_loading_in/): useful advice is to isolate `instantiate()` from `add_child()`. Later advice to instantiate/free during startup is anecdotal; it does not prove GPU warmup or retention after resource release.
- [Reddit shader-preload discussion, 2025-07-24](https://www.reddit.com/r/godot/comments/1m8fhh0/preload_your_shaders/): small warmup scenes are a useful idea, but the renderer and exact feature combinations decide applicability. Prefer the official Compatibility instructions above.

## Ordered experiments and acceptance

These are ordered probes within the existing UI-05 follow-up, not new delivered step IDs. Each candidate is independently reversible. A failed probe returns to the measured baseline; it does not justify accumulating more loaders or caches.

| Order | Experiment and boundary | Acceptance before adoption |
| --- | --- | --- |
| 1 | Attribute misses: catalog/manifest/data validation, resource load, instantiate, binding construction, shadow collection, tree insertion, save and first draw. Observer outside `app/`; inspect CPU and frame timing separately. | Fixed source/imports; fresh-process first visits, warm resource loads, retained-node hits and post-eviction misses reported separately. Identify the dominant stage before changing it. |
| 2 | UI intent/apply separation and latest-selection handling in AppRoot/Home. | Burst forward/back and rapid reversal end on the exact requested ID; no obsolete model appears. Immediate Fly, double Fly, Back, Home replacement, invalid data, EN/ES and keyboard/controller navigation preserve correctness. Show selection feedback within the next normally rendered frame; record remaining blocking phases explicitly. |
| 3 | Resource-only asynchronous loading and bounded directional prefetch through the imported-model boundary. Keep validation and the existing procedural path. | Compare selected-only versus one-neighbor prefetch and subthreads off/on. No premature blocking get, duplicate loads or late access to freed Home. Bound active requests/references and measure memory after full-fleet traversal and exit. Adopt only if frame stalls improve without worsening startup or cached hits. |
| 4 | Texture import A/B in the aircraft/VQ pipeline, after attribution and its existing gates. | Lower first-visit load time across fresh processes; same source identity and bindings; day/night close-up and moving flight image review; clean import/export from a fresh clone; package size and actual formats recorded. No unsupported VRAM claim. |
| 5 | Split only demonstrated CPU-heavy stages into bounded work, or prepare immutable CPU data on one worker. | State and validation equivalent; main-thread render/tree changes; each chunk measured. If a single operation exceeds the frame budget, refactor that operation rather than claiming the scheduler solved it. |
| 6 | Actual-render shader warmup, only with an attributed first-draw stall. | Native Compatibility evidence, unchanged appearance, startup/selection tradeoff measured; driver-cache state declared. No renderer migration bundled into this repair. |

Suggested experiment targets, **not current guarantees**: cached selection handler remains under 8 ms median on the existing host; selection feedback does not wait for model readiness; report p95/max frame intervals and counts over 33/50/100 ms during traversal. Use at least 20 warm transitions per case for useful distributions and five fresh-process samples per candidate; retain every sample and alternate candidate order. A fresh process is not a cold OS or GPU cache. Do not clear the user's driver caches; use an isolated profile/machine if true shader-cold qualification becomes necessary. `frame_post_draw` remains a rendering milestone, not scanout latency.

## Other ideas and disposition

| Idea | Decision and reason |
| --- | --- |
| Keep the three recent model/shadow entries | Already delivered; preserve the bound and lifecycle tests. Add a byte-aware policy only after credible memory accounting. |
| Predict from navigation direction or focused aircraft | Trial with probe 3; keyboard/controller intent matters as much as mouse hover. Avoid prefetching the entire catalog. |
| Coalesce preference writes | Measure save cost first. Consider only with explicit flush-on-navigation/quit and error handling; deferred writing changes crash durability. |
| Precompute invariant shadow/geometry data in the authoring pipeline | Conditional on probe 1. Hash/version inputs and verify full arrays against runtime output; never remove provenance or physics validation. |
| Preserve the field while replacing only an aircraft | Already the normal selection path. Investigate world rebuilds on conditions/Workshop separately, with lighting and weather owners. |
| Render a static Home background only when dirty | Separate idle-GPU experiment, not a first-load fix. A SubViewport needs invalidation for aircraft, light, field, size and presentation changes; avoid synchronous image readback per click. |
| Low-detail temporary aircraft or baked thumbnails | Deferred: extra asset lifecycle, visible substitution and identity/lighting mismatch. First test full-quality loading repairs with existing assets. |
| Short interruptible UI motion | UI-28 owns it. Motion must not delay selection/application or block controls; it cannot hide a blocked main thread. |
| Put the whole builder on a worker / disable thread checks | Reject. [Thread-safe API guidance](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html) distinguishes detached data from active tree access and warns about rendering/GPU synchronization and shared resource mutation. |
| Preload or instantiate the entire fleet at startup | Reject as default: moves the wait and raises memory, including aircraft the user never selects. |
| Enable Shader Baker, switch renderer, turn off VSync or raise physics ticks | Reject for this slice: baker is ineffective on Compatibility; the others do not remove measured synchronous model construction and broaden validation substantially. |

## Scope and next action

Start with probe 1, then implement the smallest supported UI/load repair. Keep texture changes under VQ ownership and retain all aircraft-contract checks. Reuse the existing cache, aircraft-route, shadow, language and controller regressions; add asynchronous lifecycle/burst cases only when that behavior is introduced. Headless checks establish logic, not native GPU performance. No new timing run, game test, import or export was performed for this documentation-only research.

Sources were accessed on 2026-10-14. The 4.7 API and exact 4.7.2 engine source are version-specific; `stable`, `master`, issues and community discussions can change. Community reports inform experiments, while official contracts and local measurements determine acceptance.
