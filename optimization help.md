## Main conclusion

**OPEN RC SIMULATOR’s strongest Apple Silicon opportunity is reducing GPU work in ground and cloud rendering, then qualifying frame pacing at actual 1080p output.** The existing measurements support that direction much more strongly than an immediate native ARM64 physics rewrite.

I reviewed the recent GitHub history, the Apple performance plan and recorded investigations, the relevant application and benchmark code, and the exact Godot engine implementation. I also researched current Apple, Godot, LLVM, Arm, and Khronos documentation and tools.

A new commit landed during the review. I incorporated it: the latest audited revision is [**`fc018b38`**](https://github.com/bultodepapas/OpenRCsimulator/commit/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab), following the larger `e9bb602` change.

The complete **16-page report, with 55 source references**, is available here:

[OpenRC_Apple_Silicon_Audit_2026-11-05.pdf](https://chatgpt.com/library?file_id=libfile_9454ec9136788191b9a0e58d8a730b1b\&account_id=personal)

**Evidence boundary:** I performed a source audit, internet research, and targeted synthetic checks of benchmark validation. The Mac performance numbers below come from the repository’s recorded campaigns; I did not run new native Mac benchmarks.

---

## 1. What the latest commits actually changed

The project already contains substantial Apple Silicon work. Several common recommendations are implemented, so the next effort should build on them.

| Revision                | Relevant work                                                                                                           | Assessment                                                                                                   |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| **`fc018b38` — Nov. 5** | Enables the cloud cache by default in graphical runs; changes headless cleanup and tests.                               | Material expansion of exposure. It needs current-source visual, lifecycle, and cross-renderer qualification. |
| **`e9bb602` — Nov. 5**  | Cloud cache, geometric shoreline cut, incremental sky processing, renderer recovery, MetalFX policy, benchmark changes. | Contains useful optimizations, but some recorded measurements describe earlier candidates.                   |
| **`a57af99` — Nov. 5**  | Apple research refresh and scale/MSAA sweep infrastructure.                                                             | Valuable attribution work; benchmark validation still has gaps.                                              |
| **`a0a289e` — Nov. 3**  | Godot 4.8 beta2 migration.                                                                                              | Historical beta1 results must remain identified separately.                                                  |
| **`178a41f` — Nov. 3**  | Host-state supervision.                                                                                                 | Existing power, thermal, and workload monitoring should be reused.                                           |
| **`b438f95` — Nov. 2**  | Bounded shader optimizations.                                                                                           | Preserve the accepted work and evaluate subsequent changes independently.                                    |

These changes are documented in the [recent source and research record](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/docs/research/desktop-delivery-investigations/DT-MAC-00-R4/README.md).

The current configuration selects **Mobile/Metal for Apple Silicon**, while the existing Intel/Rosetta configuration retains Compatibility. Spatial MetalFX is available through the project’s capability and policy layer; **Native reconstruction remains the default**. Temporal MetalFX remains a separate trial requiring Forward+ and additional history/lifecycle handling. The engine is pinned to **`4.8.beta2.official.cafc17a19`**. See the [project configuration](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/app/project.godot) and [MetalFX policy](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/app/render/metalfx_policy.gd).

**The newest cloud-cache default is broader than Apple Silicon.** It activates whenever the display server is not headless. Consequently, normal graphical Compatibility/OpenGL and other desktop paths also encounter it. `OPENRC_CLOUD_SHADOW_MAP=0` now selects the analytic baseline. [Current implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/app/render/cloud_shadow_map.gd).

---

## 2. What the measurements tell us

The most useful attribution screen identifies an **M1 MacBook Air with a seven-core GPU and 8 GiB RAM**, using Mobile/Metal, Medium scenery, a pilot camera, and a 2560×1600 display.

The short sweep used a ten-second warmup followed by twenty seconds of observation per configuration. Its results are strong clues about that workload, rather than sustained product qualification.

| Recorded experiment                                | Result                                           | Interpretation                                                |
| -------------------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------- |
| Internal 3D scale **1.0 → 0.5**, retaining 4× MSAA | **38.3 → 89.6 FPS**, approximately **2.34×**     | Pixel-related GPU work is a major constraint.                 |
| Main-thread sampling                               | Approximately **57%** waiting for GPU completion | Supports investigating GPU work before rewriting the solver.  |
| GPU pass attribution                               | **28.42 ms** total; **22.34 ms** opaque          | The opaque rendering workload is substantial.                 |
| Hide ground material                               | Approximately **11.08 ms** less GPU time         | Ground shading deserves first-class attention.                |
| Disable ground cloud shadows                       | Approximately **3.55 ms** less GPU time          | Repeated cloud-noise evaluation is a justified target.        |
| Separate sky diagnostic: disable clouds            | Approximately **7.59 ms** less GPU time          | Sky rendering is another significant target.                  |
| Hide the tested vegetation group                   | Approximately **0.06 ms** difference             | Vegetation was a low-priority target in that particular view. |

These are recorded in the [R4 attribution investigation](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/docs/research/desktop-delivery-investigations/DT-MAC-00-R4/README.md). The savings are **not additive**: removing one component changes visibility, workload overlap, and the remaining bottleneck.

There are also two useful comparisons:

- **Five short beta2 Metal-versus-GL pairs:** Mobile/Metal delivered **32.2–36.3% higher FPS** in the recorded circuit.
- **An earlier beta1 sustained campaign:** three thirty-minute runs per role reported **17.64–23.17% higher paired FPS** for a seven-file bundle comprising six shaders and lighting WeakRef reuse. All 73 common complete state/input hash windows matched. However, the candidate’s p95 was approximately **31.2–31.8 ms**, and p99 approximately **43.8–44.4 ms**. That remained outside the intended pacing target. [Sustained evidence](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/docs/research/desktop-delivery-investigations/DT-MAC-02/README.md).

**My interpretation:** the existing optimizations are producing meaningful gains, but the repository does not yet establish sustained 1080p/60 product performance for the latest default configuration.

### Resolution needs precise accounting

Several configurations can look similar in prose while rendering different pixel counts:

| Output and scale                            | Internal 3D dimensions |
| ------------------------------------------- | ---------------------- |
| 2560×1600 at Native                         | 2560×1600              |
| 2560×1600 at 0.75 scale                     | **1920×1200**          |
| 2560×1600 at approximately two-thirds scale | **1707×1067**          |
| Actual 1080p output at Native               | **1920×1080**          |

The 0.75 attribution sweep and the two-thirds MetalFX experiment are different tests. Neither automatically qualifies a 1920×1080 output flight. Godot’s scale operates on each axis, so pixel count changes quadratically. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html?utm_source=chatgpt.com)

---

## 3. Audit findings to resolve before the next optimization campaign

### A. The latest commit’s CI is failing

I checked the actual GitHub Actions result for `fc018b38`.

[CI run 42120685263](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42120685263/job/127571913297) fails release preflight because five required UID sidecars are missing:

```
app/app_state/renderer_guard.gd.uid
app/render/cloud_shadow_map.gd.uid
app/render/cloud_shadow_map.gdshader.uid
app/tests/test_cloud_shadow_map.gd.uid
app/tests/test_renderer_guard.gd.uid
```

The application, visual-capture, native-qualification, and release-build jobs were consequently skipped.

**Action:** generate the sidecars with the pinned editor, commit them with their source files, and rerun the existing gate.

### B. The current cloud cache is different from the measured candidate

The recorded C2 experiment describes an **RGBA8 tile for ground and near-grass shadows**, with GPU time improving from **28.09 to 25.72 ms**.

The current implementation uses **RG16F** and also feeds a low-octave approximation into sky-cloud relief, identified as C5b. The newest commit then makes this implementation the graphical default.

That means the old timing and image comparisons cannot qualify the exact implementation now enabled by default. See the [recorded candidate](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/docs/research/desktop-delivery-investigations/DT-MAC-00-R4/README.md) and [current cache shader](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/app/render/cloud_shadow_map.gdshaderinc).

**Action:** separate ground caching and sky-relief caching into independently identifiable experiments, then evaluate their combination.

### C. The cache enables its texture before the bake succeeds

The current code creates a zero-filled texture and immediately enables sampling. After three process callbacks, it attempts readback, conversion, and upload.

If the graphical readback is empty or invalid, the temporary viewport is freed, but the placeholder remains cached and enabled. There is no retry or analytic fallback in that failure path.

This is a **source-derived conditional risk**, not a reproduced Mac incident. It now matters to normal graphical sessions because of the new default. [Cache lifecycle](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/app/render/cloud_shadow_map.gd).

**Action:** keep analytic rendering active until a validated bake is available; define failed-bake and retry behavior explicitly. Headless tests cannot establish graphical bake success.

The memory cost also deserves accounting: a 2048² RG16F tile occupies **16 MiB**, and four retained tiles occupy **64 MiB**, before temporary render targets, readback buffers, and other overhead.

### D. Benchmark acceptance can disagree with actual rendering

I reproduced two narrow problems using synthetic receipts:

1. A request for MetalFX Spatial can still receive `performance_pass=true` when the recorded effective configuration says **Native fallback**.
2. A checked engine invocation containing **`--gpu-profile`** can also receive `performance_pass=true`.

The fixture records effective rendering, but the reducer checks the requested override and drops the effective-state record from its normalized scenario. Its diagnostic-option exclusions also omit the GPU profiler flag. [Fixture](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/research/performance/sustained_flight.gd) · [Reducer](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/research/performance/native_summary.py).

These defects **do not prove that historical measurements used an unintended renderer**. They show that the acceptance gate cannot reliably reject those conditions.

**Action:** reconcile requested and effective renderer, provider, scale, MSAA, and fallback state; classify instrumented runs as diagnostics.

### E. Benchmark identity misses the newest rendering change

The fixture hashes sixteen named inputs, but excludes the cloud-cache implementation and shaders. Its normalized scenario also omits the cache environment setting and effective bake state.

As a result, `e9bb602` and `fc018b38` can retain the same fixture identity despite different rendering defaults. A separately retained full-source manifest can distinguish them, but the fixture’s identity check alone cannot. [Source-hash list and scenario validation](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/research/performance/sustained_flight.gd).

**Action:** bind the full rendering source identity and record explicit cache off/on and successful bake state. An unset variable no longer means “cache disabled.”

### F. Recovery and shoreline handling have bounded correctness risks

The renderer guard confirms progress by counting `_process` callbacks for a minimum period. It does not prove that valid images reached the display. There is also an on/off/on MetalFX activation race: an older confirmer can clear a newer activation’s pending marker. [Recovery guard](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/app/app_state/renderer_guard.gd).

Separately, shoreline clipping explicitly rejects an interior hole contained within one source triangle. Lake attachment can log the failure and continue publishing the lake and its physics metadata. A suitable custom lake could therefore leave ground covering a physically active lake. This requires a focused fixture; it is not evidence that the default lake is broken. [Clipping limitation](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/app/render/horizon.gd) · [Attachment behavior](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/app/render/lake/lake_world.gd).

---

## 4. The optimization techniques I would prioritize

### 1. Qualify the cloud cache, with separate ground and sky experiments

This remains one of the strongest ideas because it targets measured cost: repeated periodic noise calculations across large numbers of pixels.

The useful design is to cache spatially coherent, lower-frequency work while retaining enough higher-frequency evaluation to preserve detail. Current C5b follows that general approach.

There is an important applicability limit: the sky tile is bound to the base cloud seed, while configured weather layers derive distinct seeds. The shader falls back to analytic noise on a mismatch. **A legacy single-deck improvement therefore cannot be generalized to layered weather.** [Layer seed derivation](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/app/render/weather/sky_appearance.gd).

Test cloud coverage, periodic seams, low sun, night, moving shadows, multiple seeds, and relief contrast. Density agreement alone is insufficient because relief responds to local differences.

### 2. Test half-resolution sky clouds using stock Godot features

This is the clearest additional project-level experiment.

Godot exposes:

- `use_half_res_pass`
- `AT_HALF_RES_PASS`
- `HALF_RES_COLOR`

These permit expensive cloud calculations at half width and height, followed by full-resolution composition. The current sky shader does not use this path. Preserve full-resolution sun/moon detail, horizon treatment, and the established reflection/IBL behavior. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/sky_shader.html?utm_source=chatgpt.com)

Half width and height produces one quarter of the subpass pixels, but the total gain depends on composition cost and visibility. Godot’s low-resolution sky subpass also processes pixels that geometry may hide in the final image.

**Discriminating experiment:** compare sky-heavy and ground-heavy camera views, with single and layered clouds, at actual 1080p output. Inspect moving edges and cloud occlusion of the sun.

### 3. Use a small number of deliberate shader variants

Apple recommends specialization where it removes unused work and reduces live register pressure. Godot’s shader preprocessor provides `#define`/\`#if\` and shared includes for project-level variants. [Apple Developer](https://developer.apple.com/videos/play/tech-talks/111373/?utm_source=chatgpt.com)

Useful candidates include:

- A simple cloud-deck variant versus a layered-weather variant.
- Ground variants with optional detail genuinely absent.
- Materials that entirely omit an unnecessary screen/depth dependency.

This requires comparing equivalent visible features. Uniform branches may already compile efficiently, so source-code simplification is not sufficient evidence of a gain.

Keep the variant count small and prepare them before flight to avoid replacing shader cost with first-use compilation hitches.

### 4. Extend screen-footprint-aware detail reduction

The ground already contains distance fades and derivative-based guards. Preserve that work.

The next experiment is to suppress cloud frequencies or remaining ground detail once their projected contribution becomes smaller than a pixel. Use smooth transitions and preserve coverage normalization; abrupt octave removal can create bands or change cloud shape.

The intended benefit is both lower calculation cost and less shimmer. Its success depends on camera height, field of view, weather, and threshold behavior, so the reference images must include motion and near/far transitions. The relevant existing implementations are the [ground shader](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/app/render/ground.gdshader) and [sky shader](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/app/render/sky.gdshader).

### 5. Measure the full-screen cost of screen/depth consumers

Water, sun glare, and afterimage effects can create costs beyond their own shader arithmetic: screen copies, depth resolves, additional attachments, or pass boundaries.

The existing R4 source investigation identifies these dependencies. A useful experiment must remove the relevant material from the scene, because merely hiding an already-created material may leave persistent renderer flags active. [R4 pass analysis](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/docs/research/desktop-delivery-investigations/DT-MAC-00-R4/README.md).

Start with the smallest feature that causes a costly global dependency. For example, an alternative glare-occlusion calculation may be worth testing if capture confirms that it eliminates substantial depth-related work.

Apple’s tile-based rendering guidance makes attachment lifetime and load/store behavior especially relevant. However, the exact savings require an on-device capture. [Apple Developer](https://developer.apple.com/videos/play/wwdc2020/10632/?utm_source=chatgpt.com)

### 6. Qualify MetalFX Spatial by net cost and aircraft readability

The recorded Retina experiment reports:

| Configuration                               | GPU time     |
| ------------------------------------------- | ------------ |
| Native                                      | **28.26 ms** |
| MetalFX Spatial at roughly two-thirds scale | **18.68 ms** |
| Bilinear at the same input scale            | **16.87 ms** |

MetalFX has a measurable reconstruction cost, while the recorded stills favored it for thin, distant aircraft details. The decision should combine performance and moving-image readability. [MetalFX experiment](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/docs/research/desktop-delivery-investigations/DT-MAC-00-R4/README.md).

At actual 1080p output, compare Native, Spatial 85%, and Spatial Quality. Record output and internal dimensions separately. Include propellers, landing gear, control surfaces, foliage, smoke, and fast camera movement.

The recorded MSAA sweep suggests that dropping 4× to 2× yielded only about 2% higher FPS in that workload; disabling it yielded about 10%. That makes cloud/pixel work a better first target than sacrificing thin-edge quality.

### 7. Add a correctly configured native Mac shader-baking stage

Shader baking is relevant to cold launch and earlier compilation stages. It does not remove every hardware-specific final pipeline creation.

Two details matter here:

- Metal shader baking requires exporting on macOS.
- Godot documents that `--headless` disables the baker. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html?utm_source=chatgpt.com)

The project’s shared export wrapper currently uses headless exports. Enabling a preset checkbox alone would therefore not establish a baked Metal package. [Export wrapper](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/app/export.sh).

Create a separately identified native Mac export path and measure cold launch, Home→Fly, and first use of lake, sun, particle, and crash effects.

### 8. Optimize presentation once sustained GPU headroom exists

Process FPS, GPU duration, and actual display intervals measure different things. Apple’s HUD distinguishes GPU execution time, present delay, and on-glass frame intervals. [Apple Developer Documentation](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics?changes=__1\&utm_source=chatgpt.com)

After achieving enough GPU headroom, compare Godot’s two-image swapchain setting with the default three-image configuration. A shorter queue can reduce latency but becomes less stable when refresh deadlines are missed. Godot explicitly documents that tradeoff. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/tutorials/rendering/jitter_stutter.html?utm_source=chatgpt.com)

For an RC simulator, control response and consistent presentation deserve their own acceptance checks. Average throughput alone cannot establish either.

---

## 5. Tools and libraries worth using

### Profiling and diagnosis

| Tool                                                                    | Best use in this project                                                   | Applicability                                                                             |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| **Existing collectors, debug bridge, script profiler, Perfetto export** | Correlate hitches with simulation, scripts, observers, and transitions.    | Already present; expand selectively.                                                      |
| **Xcode GPU capture and Metal counters**                                | Identify expensive draws, resources, resolves, and dependencies.           | Primary GPU attribution workflow.                                                         |
| **Instruments Game Performance / Metal System Trace**                   | Separate CPU waits, submission, GPU work, and presentation.                | Verify the installed templates and selected Xcode.                                        |
| **Time Profiler / `sample`**                                            | Find expensive or blocked CPU stacks.                                      | Sampling does not measure every 240 Hz invocation.                                        |
| **Allocations, VM, Metal resource views**                               | Investigate growth across repeated Home/Fly/Workshop cycles.               | CPU and GPU memory views can overlap.                                                     |
| **`gpucapture` and `gpudebug`**                                         | Script repeatable capture and inspection.                                  | Apple introduced these with macOS 27; installation remains to be checked on the test Mac. |
| **Metal HUD**                                                           | Quick diagnostic view of pacing, resolution, thermal state, and Game Mode. | Use separately from clean acceptance measurements.                                        |
| **Tracy / engine tracing**                                              | Expose engine phases missing from external samples.                        | Requires an appropriately configured engine build.                                        |

Apple’s current tool material documents the command-line GPU workflow and capture facilities; Godot documents its source-build profiling integrations. [Apple Developer](https://developer.apple.com/metal/tools/?utm_source=chatgpt.com)

Hardware limits are important:

- **Shader cost graphs and performance heat maps require M3 or later.** They should not become prerequisites for the M1 campaign. [Apple Developer Documentation](https://developer.apple.com/documentation/xcode/optimizing-gpu-performance?changes=latest_mi_1\&utm_source=chatgpt.com)
- **Processor Trace recording requires M4 or later**, with the corresponding OS/Instruments support. [Apple Developer Documentation](https://developer.apple.com/documentation/xcode/analyzing-cpu-usage-with-processor-trace?changes=_2\&utm_source=chatgpt.com)
- Apple’s current **Power Profiler** documentation lists iPhone/iPad support; it should not be prescribed as a Mac power-measurement tool. [Apple Developer Documentation](https://developer.apple.com/documentation/Xcode/measuring-your-app-s-power-use-with-power-profiler?changes=_1\&language=objc\&utm_source=chatgpt.com)

### Asset and native-code libraries

| Tool/library                              | Where it can help                                                       | Recommended priority                                                     |
| ----------------------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **Godot texture compression and mipmaps** | Texture residency, bandwidth, and minification quality.                 | Use the existing import pipeline first; inspect actual formats.          |
| **Arm `astcenc`**                         | Offline ASTC quality/bitrate experiments; native Apple Silicon tooling. | Conditional on measured texture pressure.                                |
| **KTX-Software / Basis Universal**        | Texture preparation, validation, and transcoding.                       | Asset-pipeline work, with pinned encoder versions and hosts.             |
| **meshoptimizer / `gltfpack`**            | Mesh layout, LOD, loading, and asset size.                              | Conditional on geometry/loading evidence. Preserve named aircraft parts. |
| **Accelerate / vDSP / vForce**            | Large native vector or transcendental batches.                          | Only after identifying a suitable CPU workload.                          |
| **LLVM PGO / ThinLTO**                    | Optimize a measured engine or native-extension workload.                | Later-stage build experiments with held-out validation.                  |

The primary projects document these capabilities. `gltfpack` offers options to preserve named nodes/materials, which matters for aircraft hinges and propellers. KTX releases also document cases of cross-platform encoding differences. [GitHub](https://github.com/arm-software/astc-encoder?utm_source=chatgpt.com)

For the cloud cache specifically, texture compression and mipmaps need separate correctness experiments: filtered noise passes through nonlinear thresholds and relief calculations. An optimization suitable for an albedo photograph may change cloud coverage.

---

## 6. Important boundaries the research uncovered

### The pinned engine uses Metal 3

The exact beta2 source constructs:

```
MTL3::RenderingDeviceDriverMetal
```

That is stronger evidence than the broader documentation statement suggesting Metal 4 support. The referenced Godot refactor PR describes preparation for future Metal 4 work. [Pinned driver factory](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/rendering_context_driver_metal.cpp). [GitHub](https://github.com/godotengine/godot/pull/114484?utm_source=chatgpt.com)

A Metal 4 port is an engine project requiring a measured reason, reproducible templates, and qualification.

### FP16 needs compiler evidence

The pinned Mobile renderer already selects explicit FP16 variants for some engine shaders when supported. A custom Godot `mediump` annotation does not, by itself, establish that the generated Metal performs the desired calculation in `half`.

Inspect generated code and timing, then restrict experiments to render values with justified error tolerance. Keep world coordinates, thresholds, sensitive HDR calculations, and the float64 simulation appropriately precise. [Pinned shader setup](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_mobile/scene_shader_forward_mobile.cpp). [GitHub](https://github.com/KhronosGroup/SPIRV-Cross/issues/1857?utm_source=chatgpt.com)

### Memoryless attachments require engine-level verification

Apple’s tile-memory guidance is relevant, but the pinned Godot render-buffer implementation still contains a transient-allocation TODO for normal main depth/MSAA buffers. This is not a project setting that can simply be enabled.

Any change must account for later sampling, copying, and resolving of those attachments. [Pinned render-buffer source](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp).

### Native ARM64 physics remains conditional

A native evaluator can become worthwhile after profiling establishes a CPU/tick bottleneck. Current NK-3 work has Linux x86-64 assumptions, including SSE2-related arithmetic choices. An Apple port requires deliberate compiler, math-library, exactness, and transaction validation. [Native-kernel research](https://github.com/bultodepapas/OpenRCsimulator/blob/fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab/research/native-kernel/README.md).

One concrete compiler trap: Clang documents that **`-fno-fast-math` can still leave `-ffp-contract=on`**. Where contraction must be disabled, the effective flags must explicitly preserve that requirement. Double precision alone does not guarantee reference-equivalent arithmetic. [Clang](https://clang.llvm.org/docs/UsersManual.html?utm_source=chatgpt.com)

---

## 7. Recommended order of work

I would organize the next campaign around these deliverables:

1. **Restore a valid baseline:** fix the five UID omissions, effective-render validation, profiler eligibility, and rendering-source identity.
2. **Qualify the new cloud default:** readiness/fallback handling, explicit off/on records, ground and sky separation, layered-weather coverage, and Compatibility checks.
3. **Test half-resolution sky clouds:** independently, at actual 1080p output, with moving visual review.
4. **Investigate pass dependencies and remaining ground detail:** use capture to select one small change at a time.
5. **Choose reconstruction and MSAA presets:** compare net frame cost with distant-aircraft readability.
6. **Qualify native Mac exports:** shader baking, first-use behavior, recovery, and actual Game Mode state.
7. **Run sustained acceptance on finalists:** alternating short pairs, followed by three thirty-minute runs per role, with thermal state, tail latency, memory trend, replay, and product-route checks.

Every candidate should preserve **float64 simulation state, 240 Hz RK4 behavior, replay and transaction contracts, and the supported desktop paths**.

**My first three investments would be benchmark integrity, cloud-cache qualification, and the half-resolution sky experiment.** They address the clearest findings in the current code and measurements, while giving the next round of Apple Silicon work a trustworthy basis for adoption.