# Loading, caching and game presentation research

**Researched:** 2026-11-17. **Application baseline:** main 3c91936; Godot 4.8-beta2, engine commit cafc17a192acf67903910a68aeb3c076c0907a4b. These findings support the [implementation plan](../../../plans/vehicle-selection-performance.md); they do not demonstrate a speedup in OpenRC.

## 1. Separate the costs before choosing a technique

A vehicle switch can involve catalog lookup, validation/hash work, disk reads, decompression/transcoding, script loading, scene instantiation, binding/customization, geometry fitting, texture creation/upload, first-use shader/pipeline work, drawing, and retirement of old resources. Some stages overlap. Sum only exclusive phase spans; do not add nested timings or a separate attribution run to total wall time.

Threaded resource loading addresses part of that pipeline. Godot's [background-loading guide](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html) distinguishes request, status and retrieval; retrieval can block if called too early. The [thread-safety guide](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html) separately constrains tree/rendering work. The current OpenRC broker already uses this basic resource pattern; its later builder/fitting/skin work is the more useful next boundary to measure.

The [historical selector report](../UI-05-R3/README.md) describes a separate attribution run in which instantiation was much shorter than resource loading and subsequent model/shadow/night preparation. Its linked raw profile.log is absent from the pinned tree; this is reported historical evidence, not a new trace inspection. “Move instantiate to a thread” is therefore neither a demonstrated solution nor a safe default.

## 2. ResourceLoader contract on the pinned engine

Primary references: [ResourceLoader API XML](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/ResourceLoader.xml), [request implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/io/resource_loader.cpp#L700-L810), and [collection implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/io/resource_loader.cpp#L932-L1000).

Use a normalized absolute resource path and one central request ledger. Check request errors. Poll across frames rather than a busy loop. Collect a loaded or failed owned token once; an invalid status is an ownership/error case, not permission to blindly call get again. Duplicate request calls can increment token ownership in the pinned implementation, so deduplicate at admission. The public API offers no cancellation operation: cancel the consumer/generation, drain active engine work, and discard stale results. Keep the owner alive through controlled teardown.

Retain subthreads false initially. More parallel tasks can compete for CPU, disk, decompression and main-thread callbacks. The existing dedicated main-scene loader is a separate proven application workaround; this proposal does not replace it with another threaded call without equivalent lifecycle evidence.

[Issue 120661](https://github.com/godotengine/godot/issues/120661) documents loader-token leak reports beginning with 4.7, including later nested-preload reports; [issue 123775](https://github.com/godotengine/godot/issues/123775) reports alias-path problems. These are upstream leads, not confirmed defects in this OpenRC beta2 route. Reproduce the actual asset graph on the pinned engine before changing its workaround. An issue's open/closed status is not a performance measurement.

### Progress is local to a phase

The pinned [progress calculation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/io/resource_loader.cpp#L856-L881) combines task/dependency progress. It is not a count of total switch bytes or all remaining work. OpenRC should distinguish resource loading, preview preparation and first requested draw. Keep existing stage-based launch progress; show an indeterminate state when no defensible denominator exists. Never reach “100% ready” merely because the GLB resource is returned.

## 3. Cache ownership and safe appearance reuse

The pinned [Resource contract](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/Resource.xml) describes reference-counted lifetime and path caching. CACHE_MODE_REUSE shares existing resources, including dependencies; ordinary loading followed by dropping every reference is not a persistent application cache. CACHE_MODE_REPLACE refreshes cached instances and is not an eviction strategy. A material or mesh retained by a node remains an owner even when a broker drops its own reference.

For skins, the application design should reuse immutable meshes/textures while keeping mutable appearance overrides private. Duplicate the material being changed, not the entire texture/geometry graph. Scene-local resources must be configured appropriately before instantiation; changing that flag afterwards does not retrofit existing shared objects. Existing OpenRC paint origins, skin identity checks and atomic CustomSkin commit behavior are useful foundations, but a fast reusable preview path still needs explicit base restoration and validation.

### Application keys do not override the engine's path cache

A new cache key containing a content hash does not force ResourceLoader or a downstream builder's ordinary load(path) to read new bytes at the same path. For imported mutable content, prefer immutable content-versioned storage paths and bind the complete dependency closure to that revision. Publish the new revision atomically. Retire old runtime references after their consumers drain; persisted source revisions remain subject to the library's retention policy, not cache eviction.

If the library contract requires in-place replacement, define a deliberate reload boundary that handles both the broker and all builder/dependency loads, with no mutation of an old live accepted instance. Preserve the old visual on failure. Test replacement at the same path while old references are retained, including skin textures, generated geometry and manifest dependencies. Do not use a global cache replacement mode to mutate a live preview or flight indirectly.

## 4. Useful game-loading techniques and their OpenRC fit

| Technique | Application here | Limitation / acceptance condition |
| --- | --- | --- |
| Metadata catalog with soft asset references | Search and display 100+ entries without loading their full scenes | Listing must not expand heavy dependencies or inspect every custom archive |
| Immediate static thumbnail, detailed selected preview later | Respond to selection while real work runs; preserve correct identity | Thumbnail must represent the declared vehicle/skin; missing image uses a truthful placeholder |
| Keep recent useful resources | Fast return to a recently used vehicle or appearance | Retain explicit owners within measured budget; avoid resource churn and hidden growth |
| Appearance-only update | Preserve geometry/pose for proven compatible skins | Atomic target validation, independent mutable materials and complete reset to default |
| Prepare during natural idle time | Reuse the existing Home scene/trim adoption mechanism | Count dwell and post-click time; never block new browsing with avoidable new speculation |
| Directional/focus prediction | Trial one likely next resource after selected work is satisfied | Active engine I/O cannot be preempted; memory reservation and useful-hit rate matter |
| Generated preview metadata | Remove repeated vertex scans and scene work from user input | Versioned source/generator/pose identities, equivalent output and fallback |
| Smaller preview asset tier | Keep oversized imports browsable while selecting a detailed view explicitly | Clearly separate preview tier from flight quality; bound node/surface/texture complexity |
| Selected-path GPU warmup | Move an attributed first-use draw into a controlled transition | Renderer-specific, actually rendered, and included in total latency; no fleet warmup |
| Short interruptible visual transition | Make a successful swap visually coherent | A fade does not fix a blocked main thread and cannot delay a cache hit |

These are architectural techniques, not claims about the internal implementation of a named commercial simulator. Epic's [asynchronous asset-loading documentation](https://dev.epicgames.com/documentation/unreal-engine/asynchronous-asset-loading-in-unreal-engine) separates searchable unloaded metadata from soft references and actual loads. The transferable idea is the metadata/asset boundary, not installing Unreal's APIs into Godot.

Unity's [Addressables memory documentation](https://docs.unity3d.com/Packages/com.unity.addressables@1.21/manual/MemoryManagement.html) explains reference ownership and asset churn caused by unloading content immediately before needing shared dependencies again. That supports measuring useful retention and dependency lifetimes. Unity AssetBundle release semantics are not Godot's implementation contract.

## 5. RAM and VRAM: what the numbers mean

Disk compression, decoded CPU data and GPU residency are different quantities. For a simple RGBA8 image with a complete mip chain, an ideal estimate is width × height × 4 × 4/3 bytes. For a block-compressed texture, count blocks per mip and bytes per block; small mip alignment changes the exact total. These estimates exclude metadata, alignment, staging copies, duplicated images, driver overhead and mesh buffers.

| Illustrative single square texture | RGBA8 plus full mips | 8-bit-per-pixel block format plus mips, approximate |
| --- | ---: | ---: |
| 1024×1024 | 5.33 MiB | 1.33 MiB |
| 2048×2048 | 21.33 MiB | 5.33 MiB |
| 4096×4096 | 85.33 MiB | 21.33 MiB |

The right column is a format example, not a claim that OpenRC uses that format on every platform. Multiplying the 4096 RGBA8 example by 100 gives approximately 8.33 GiB for only one texture per vehicle, before meshes and other maps. This illustrates why loading the whole catalog is a poor scaling policy; it is not an estimate of the current fleet's memory.

Use a ledger for unique content/resources and their owners, with reservations for pending decode/build/upload and retiring resources. Compare estimates with process RSS, system available memory, renderer texture/buffer counters and platform GPU tools. Renderer allocation counters do not necessarily report driver residency; static allocator memory is not RSS. On unified-memory systems, avoid summing overlapping CPU/GPU figures. Bound unknown/oversized imports before construction or fall back to a static/lower-detail preview.

Evict unpinned speculative/recent entries before disturbing current selection. Keep a short retirement allowance in the budget because deferred frees and GPU work do not end exactly when a dictionary entry is erased. Use separate admission/eviction watermarks to prevent repeated unloading/reloading near the limit. The [plan](../../../plans/vehicle-selection-performance.md#9-ram-vram-and-cache-accounting) deliberately defers final full-preview byte budgets until target-host measurements exist.

## 6. Texture formats and renderer-specific work

Godot's [image import guide](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html) distinguishes disk-oriented lossless/lossy storage from GPU compression and Basis Universal's load-time transcoding. Keep mipmaps for appropriate 3D sampling. A smaller source JPEG/PNG does not prove lower texture residency, and deleting mipmaps can trade memory for distance aliasing. Compare actual imported formats, quality, package bytes and load phases on each supported renderer.

The pinned [ResourceImporterTexture API](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/ResourceImporterTexture.xml#L77-L86) describes mipmaps/limit as unimplemented. Do not use that property as a claimed residency cap.

Godot's [pipeline-compilation guide](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html) restricts modern precompilation/ubershader techniques to Forward+/Mobile. Compatibility requires representative content to be rendered in a camera frustum to warm its path. A hidden node or loaded shader alone is insufficient. Use the selected model and actual relevant MSAA/material/light features; a separate viewport with mismatched settings is not proof of coverage. Measure the preparation and the subsequent real draw, preserving driver-cache conditions.

### Godot 4.8 texture streaming

The exact [beta2 implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/modules/texture_streaming/texture_streaming.cpp#L224-L286) defaults streaming and budget enforcement off and refuses Compatibility. The [upstream implementation discussion](https://github.com/godotengine/godot/pull/113429) and [4.8 feature announcement](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-5/) describe a streamed texture import type for supported renderers. This is a separate optional Mobile/Forward+ experiment, not the primary plan or evidence that every texture streams automatically. Test the application's actual Metal/Mobile route before claiming a benefit there.

## 7. Imported content requires its own preparation path

The normal ResourceLoader API expects engine-imported resources. Godot's [runtime-loading guide](https://docs.godotengine.org/en/stable/tutorials/io/runtime_file_loading_and_saving.html) describes raw image and glTF routes using Image and GLTFDocument/GLTFState. An exported application cannot assume that dropping a raw file into user storage creates the editor's imported-resource cache. Use the existing Creator admission and library work, not an invented second importer.

After admission, publish an immutable catalog record and bounded preview derivatives. Keep dimensions, nodes, surfaces, dependency bytes and decompression limits under the importer owner's contract. User-defined script execution is not required for browsing a vehicle. Store derived thumbnails/preview data under content and tool-version identity; recover interrupted writes, missing/corrupt derivatives and upgrades without modifying source assets. An indexed availability flag is a hint for the UI, never a substitute for current launch admission and binding verification.

## 8. Alternatives intentionally deferred or rejected

| Idea | Decision |
| --- | --- |
| Preload or instantiate all 100 vehicles | Reject as default; moves the wait to startup and increases unrelated allocations |
| Just increase the three-model cache to 100 | Reject; count says nothing about texture/geometry size or transition peaks |
| Put the full current builder on a worker | Reject without a proven ownership/purity redesign; tree, shared resources and GPU interactions are constrained |
| Call deferred and describe it as background loading | Reject; deferred main-thread work can still monopolize a frame |
| Clear all caches on every change | Reject; creates avoidable reload/transcode/upload churn and can discard useful shared resources |
| Raise thread count or trust LOW priority | Conditional measurement only; scheduling, main callbacks and platform behavior differ |
| Use fast approximate preview to skip validity/provenance | Reject; preview optimization cannot make invalid content launchable |
| Keep a whole live flight/world behind Home | Separate high-risk lifecycle proposal, unnecessary for this catalog plan |
| Switch renderer to get shader baking/streaming | Out of scope; main Compatibility path still needs a valid solution |
| Recompress artwork blindly | Reject; change only an attributed import/preview tier through its source pipeline, with visual and package checks |
| Delay preference writes immediately | Defer until save cost is measured and durability/error semantics are designed |
| Introduce SQLite for 100 entries | Defer; a bounded metadata array/index is sufficient to test the actual need |

## Source scope

Pinned GitHub source links identify the checked beta2 loader, resource-cache and texture-streaming behavior. Stable/latest documentation, announcements and issues were read on 2026-11-17 and may change; the numbered 4.8 documentation route was unavailable during research. Compatibility shader-warmup guidance comes from current official documentation and still requires application qualification on beta2; this review did not inspect every renderer implementation line. Cross-engine sources supply design comparisons only. Repository measurements retain their original engine/hardware/resolution and must not be relabeled current results.
