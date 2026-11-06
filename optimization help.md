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


other out of the box thinkgin: 
## The strongest direction is to eliminate unnecessary shading—and preserve native detail around the aircraft

I built and ran **five isolated experiments**, read the latest OpenRC source at [`93ffbb1`](https://github.com/bultodepapas/OpenRCsimulator/commit/93ffbb101917dff86ecc2632f07e2e45c450a178), and inspected the Metal implementation in the project’s pinned Godot version.

**My priorities are now:**

1. **Stop evaluating cloud noise as soon as the remaining octaves cannot change the result.**
2. **Store noise’s integer lattice values and use texture filtering to perform its interpolation.**
3. **Render a native-resolution region around the aircraft while reducing background shading.**
4. **Investigate Apple’s native rasterization-rate maps as the larger engine-level opportunity.**

One apparently attractive idea—caching the three cloud-lighting samples together—performed poorly in the numerical experiments. That result helped narrow the direction.

**Download the runnable experiments, results, shader sketches, camera tests, source references and engine logs:**  
[OpenRC_Apple_Silicon_Experimental_Kit_2026-11-05.zip](https://chatgpt.com/library?file_id=libfile_96be4c46e2348191a2a39474f708e767&account_id=personal)

The evidence below includes CPU numerical experiments, actual Godot camera-method tests, and shader-language compilation. **There are no new Metal performance measurements:** the documented M1 access key was unavailable in this environment. The prototypes are outside the application checkout, which remains unchanged.

### What the experiments established

| Experiment | Result obtained | Assessment |
|---|---|---|
| Conservative cloud-noise bounds | **105,144,320 parameterized float32 comparisons**, with zero differing outputs; one representative grid avoided **44.9% of fBm noise evaluations** | Strong first candidate for a native GPU trial |
| High-octave lattice atlas | Maximum incremental density difference ≈ **0.000134**; active-cloud scalar-lighting difference ≈ **0.000247** against the modeled current path | Promising arithmetic-to-texture trade |
| Native-resolution aircraft crop | **96 camera configurations**; maximum projection mismatch **0.00869 pixels** | Geometry works in the tested engine; rendering and performance remain to be tested |
| Packed cloud-relief cache | At 2048², maximum scalar-lighting error **0.0425–0.0496**, with **32 MiB** per parameter combination | Deprioritize the tested design |
| Warped solar-halo lookup | **1 KB** table; maximum normalized halo error **0.00067842** over 820,197 sampled float32 inputs | Numerically interesting, but lower priority after inspecting integration costs |

The quantities in this table have different meanings. Density and lighting-factor differences are not displayed pixel errors, and avoided noise evaluations are not predicted FPS gains.

---

## 1. Start from the corrected, working cloud implementation

The latest commit changes an important conclusion from the earlier investigation.

The earlier flattened-cloud failure was caused by the Mobile/Metal sky shader reading a `ViewportTexture` as black. The current implementation bakes into an HDR viewport and publishes a stable **RG16F `ImageTexture`**. Its channels serve ground shadows and the low-frequency portion of cloud relief, while the cloud silhouette remains analytic.

The repository’s retained M1 diagnostic reports **26.20 ms → 23.45 ms GPU time** with C2+C5b enabled at 2560×1600, a 2.75 ms saving in that particular comparison. Separate 1920×1080 pilot and aircraft-ground stills differed by no more than 2/255. These are existing project measurements, from one profiled run per configuration and separate still captures—not results produced by this new investigation. [Pinned evidence report](https://github.com/bultodepapas/OpenRCsimulator/blob/93ffbb101917dff86ecc2632f07e2e45c450a178/docs/research/desktop-delivery-investigations/DT-MAC-00-R4/README.md).

That makes the next question more specific: **what expensive work remains after the current cache succeeds?**

The source points to repeated high-octave hashes, exact silhouette evaluation, cloud-lighting samples, and the amount of screen space shaded at full resolution.

---

## 2. First experiment: prove that a cloud pixel is clear before finishing its noise

**This is the first shader change I would take to the M1.** It adds no texture memory and exploits the mathematical structure already present in [`cloud_field.gdshaderinc`](https://github.com/bultodepapas/OpenRCsimulator/blob/93ffbb101917dff86ecc2632f07e2e45c450a178/app/render/cloud_field.gdshaderinc).

The shader combines five noise octaves with weights:

\[
\frac12,\quad \frac14,\quad \frac18,\quad \frac1{16},\quad \frac1{32}
\]

Their sum is \(31/32\). Each octave is bounded between zero and one in exact arithmetic.

Consequently, after evaluating only part of the noise, we know how much the unfinished portion could possibly contribute:

| Octaves already evaluated | Maximum remaining normalized contribution |
|---|---:|
| Two | \(7/31\) |
| Three | \(3/31\) |
| Four | \(1/31\) |

The final density is a smooth threshold:

\[
\rho=\operatorname{smoothstep}(1-c,\;1.25-c,\;N)
\]

Here, \(c\) is the existing cluster-adjusted coverage.

Suppose the largest possible final noise value is still below the clear-sky threshold. The remaining octaves cannot change the answer: density will be zero. Similarly, if the smallest possible final value already exceeds the opaque threshold, density will be one.

**Only ambiguous samples need the remaining octaves.**

### What I tested

The prototype computes the existing clustering adjustment first, evaluates two or three octaves, and checks the remaining interval. Samples near the threshold continue through the original calculation.

Across the three numerical screens:

- **105,144,320 parameterized float32 comparisons** produced zero differing outputs.
- The cases included multiple seeds, coverage levels, clustering strengths, periodic seams and threshold-focused inputs.
- Two shader variants passed the pinned Godot shader-language compiler: a check after three octaves, and checks after both two and three.

That comparison count includes repeated coordinates under different parameters. It is evidence about the numerical implementation, not 105 million independent hardware observations.

On a 256×256 periodic grid with seed 1253, coverage 0.35 and clustering 0.35:

| Check placement | fBm noise evaluations avoided | All noise hashes avoided, including clustering |
|---|---:|---:|
| After three octaves | 31.638% | 26.365% |
| After two octaves | 39.778% | 33.148% |
| After two and three octaves | **44.897%** | **37.415%** |

### Why this could win—and where it could lose

The opportunity is substantial because the shader is currently calculating detail even where that detail cannot affect the thresholded result.

However, the benefit depends on how neighboring GPU lanes behave. If some lanes exit and others continue, the GPU may still execute much of the remaining work. Extra branches can also increase register pressure or interfere with compiler optimization. The uniform coordinate grid used here is not the actual distribution of sky pixels in a pilot view.

There is also a numerical qualification still to complete: the prototype uses an empirical `1e-5` guard around threshold decisions. The interval argument is exact in real arithmetic; that guard has not been proved sufficient for every shader backend and fast-math configuration.

**My implementation choice:** benchmark the two-and-three variant against the simpler three-only variant. More checks are not automatically better, especially in dense cloud conditions.

Under the current tile-enabled implementation, this targets exact sky-body evaluation and exact fallbacks. It does **not** automatically accelerate the cached ground-shadow or relief paths. That distinction matters when selecting the comparison.

---

## 3. Second experiment: make the texture sampler do the noise interpolation

**This is the most interesting new data representation I found.**

The current value-noise function hashes four integer lattice corners, then blends those values using a quintic interpolation weight. Instead of storing a sampled picture of the resulting noise, the proposed texture stores the **original corner hashes**.

For a coordinate \(p\):

\[
i=\lfloor p\rfloor,\qquad f=p-i
\]

\[
u(f)=f^3\left(f(6f-15)+10\right)
\]

A linear texture sample at the appropriately wrapped coordinate

\[
\frac{i+0.5+u(f)}{P}
\]

can perform the same four-corner weighted interpolation in ideal arithmetic. The half-texel offset places integer lattice values at texel centers.

Lookup-based noise and using texture operations to substitute for arithmetic have established graphics precedents. The particular corner-lattice mapping here is derived from OpenRC’s value-noise implementation; it is not a claim that an older Perlin-noise example already validates this shader on Apple GPUs. [NVIDIA Developer](https://developer.nvidia.com/gpugems/gpugems2/part-iii-high-quality-rendering/chapter-26-implementing-improved-perlin-noise?utm_source=chatgpt.com)

### The version I actually tested

The isolated prototype keeps the existing low-octave C5b cache and adds a **1024×1024 RG16F atlas**:

- R contains the octave-3 corner hashes, with their 512-cell period repeated across the atlas.
- G contains the octave-4 corner hashes, with a 1024-cell period.
- The shader retains the existing quintic interpolation weights.
- A missing, unready or incorrectly seeded atlas uses the analytic fallback.

For a fully evaluated three-offset cloud-relief branch, the source-level trade is:

**24 corner-hash calls removed, six additional texture samples introduced.**

That is a source-operation count. A GPU compiler may already share or simplify some arithmetic, while each filtered lookup has a real cache and bandwidth cost.

### Numerical results

The screen covered 65,536 coordinates across five seeds, including negative coordinates, periodic seams, large float32 coordinates and different cloud conditions. It evaluated the three existing relief offsets.

Against the modeled current C5b path:

| Quantity | Maximum observed incremental difference |
|---|---:|
| Cloud density | ≈ **0.000134** |
| Scalar relief lighting on active cloud points | ≈ **0.000247** |

An independent scalar integer/double implementation checked the float32 noise reference on 1,024 binary-exact inputs. Deliberately omitting the half-texel offset or using the wrong seed produced large, detectable errors.

The proposed persistent atlas is **4 MiB per seed**, excluding its bake target, staging and upload lifetime.

Actual sampler behavior remains important. A deliberately hypothetical model that rounded interpolation weights to eight fractional bits increased the error. That sensitivity experiment is useful precisely because we should not assume ideal interpolation matches the M1 sampler.

### The more aggressive extension: use a mip chain as an octave dictionary

The next version would store all five independently generated lattices in one texture:

| Mip level | Contents |
|---|---|
| 0 | 1024² corner hashes for octave 4 |
| 1 | 512² corner hashes for octave 3 |
| 2 | 256² corner hashes for octave 2 |
| 3 | 128² corner hashes for octave 1 |
| 4 | 64² corner hashes for octave 0 |

Those five useful levels total approximately **2.664 MiB in R16F per seed**, before smaller mip tails and allocation overhead.

This is an unusual use of mipmaps: **each level is a different independently seeded lattice**. Automatically generating the mipmaps by downsampling would destroy the intended data. Godot supports loading supplied mip data through `Image.create_from_data`; the sampler must also enable mip access, with explicit integral LOD selection. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/classes/class_image.html?utm_source=chatgpt.com)

This full pyramid is a proposal, not the tested two-octave atlas. It could eventually replace more of the current cache infrastructure, but it must prove that extra sampling beats arithmetic and that all consumers retain acceptable agreement.

R32F is another precision option, but its filtering support must be queried rather than assumed. Apple exposes `supports32BitFloatFiltering` for exactly that distinction. [Apple Developer Documentation](https://developer.apple.com/la/documentation/metal/mtldevice/supports32bitfloatfiltering?utm_source=chatgpt.com)

**My recommendation:** take the smaller two-octave atlas to Metal first. If it wins, the full pyramid becomes a justified second experiment.

---

## 4. The biggest architectural bet: native-resolution detail around the aircraft

The simulator has a clear visual priority: the pilot must read the aircraft’s silhouette, attitude, motion and control response.

That suggests a rendering strategy with **different spatial budgets for different parts of the image**.

### Proposed rendering arrangement

Render the background at a reduced internal scale. Then render a tightly cropped, native-pixel region around the aircraft using a second camera with the same world position and orientation, but an off-axis frustum.

The second view must include **the complete visible scene inside that rectangle**:

- The aircraft and propeller.
- Smoke, lights and other relevant effects.
- Trees, terrain and objects that can occlude the aircraft.
- The sky and background needed to composite the region correctly.

Composite that crop into the reconstructed background, then draw the native-resolution UI.

Godot supplies `SubViewport`, shared world access and off-axis camera configuration through `Camera3D.set_frustum`. The project’s existing [magnifier](https://github.com/bultodepapas/OpenRCsimulator/blob/93ffbb101917dff86ecc2632f07e2e45c450a178/app/render/camera/magnifier.gd) provides useful infrastructure, but its aircraft-only layers and different camera setup do not already implement this crop. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/classes/class_camera3d.html?utm_source=chatgpt.com)

### Why this is worth testing

A simple shading-area model is:

\[
\text{relative area}\approx s^2+p
\]

where \(s\) is the background’s linear resolution scale and \(p\) is the native crop’s fraction of the output area.

For example, a background scale of 0.75 and a crop covering 10% of the output gives:

\[
0.75^2+0.10=0.6625
\]

That is about two-thirds of the full-screen fragment area **before** duplicated scene work and compositing. It is not a prediction of a one-third frame-time improvement.

The actual implementation can duplicate culling, draw submissions, shadows and other passes. Those costs may erase the saving. The architectural attraction is that it offers a way to reduce background shading while explicitly protecting the detail that matters for flying.

### What I validated in the real engine

The headless geometry experiment used the actual pinned Godot camera methods:

| Check | Result |
|---|---|
| Crop/FOV/aspect/transform configurations | **96 passed** |
| World-to-crop projection comparisons | **3,168**, maximum mismatch **0.00869 px** |
| Near/far and crop-edge inclusion checks | **1,152 passed** |
| Inverse-projection ray comparisons | **1,056**, maximum vector difference **2.885×10⁻⁶** |
| Deliberately reversed offset controls | All detected |

This establishes the sampled camera geometry. It does not establish rendered seams, sky behavior, depth-texture agreement or performance.

### A concrete engine trap discovered during the experiment

In the pinned version, calling `project_ray_normal()` on the off-axis crop camera did not produce the corresponding main-camera ray in **792 of 1,056** samples.

I then checked the [pinned Camera3D implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/3d/camera_3d.cpp). Its ray helper constructs a centered ray from viewport half-extents, which is consistent with the observed off-axis discrepancy.

The tested workaround is:

```gdscript
main_camera.project_ray_normal(crop_origin + crop_local_pixel)
```

Reconstruction through the inverse crop projection matrix also matched in the sampled cases.

That matters for picking and any later reconstruction work: successful image projection does not guarantee that every camera helper respects the same off-axis geometry.

### How I would develop the rendered version

Use a padded crop that covers aircraft motion and effects, with hysteresis so small movements do not constantly resize targets. Synchronize the two cameras to the same render pose. Match exposure, fog, lighting and postprocessing, and account for internal versus output pixel coordinates.

The decisive scenes are a fast pan, an aircraft passing behind trees, a spinning propeller near the crop edge, and a changing sky/exposure. At 1920×1080 output, the patch must remain visually seamless while total frame cost falls.

**This is the large project-level experiment I would pursue before committing to an engine fork.**

---

## 5. Go further with Apple’s native rasterization-rate maps

The native Metal version of selective-resolution rendering is potentially more efficient because it can reduce physical fragments within the principal scene pass.

Apple’s `MTLRasterizationRateMap` maps logical screen coordinates onto a nonuniform physical render target. The rendered image is subsequently reconstructed into the final output. Its rates are defined separately along the horizontal and vertical axes, so it is not an arbitrary two-dimensional quality mask. Actual supported rates and physical dimensions must be queried. [Apple Developer](https://developer.apple.com/videos/play/tech-talks/608/?utm_source=chatgpt.com)

For OpenRC, the map could follow a padded aircraft region:

- Preserve high sampling density where the aircraft and nearby effects appear.
- Reduce density farther away.
- Keep the HUD at output resolution.
- Change the map conservatively as the region moves.

### The useful source discovery

The pinned Godot Metal backend already contains relevant machinery:

- `texture_create_from_extension` recognizes an actual native rasterization-rate-map object.
- The framebuffer path retains the map.
- The Metal render-pass setup assigns it to the render-pass descriptor.
- The XR interface exposes a related map format and import route.

These are concrete integration points in the pinned [Metal driver](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/rendering_device_driver_metal.cpp) and [Metal render-pass implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/metal3_objects.cpp).

**What remains unresolved is getting that native map safely into the existing desktop scene-rendering path.** An ordinary Godot desktop VRS texture does not automatically become an Apple rasterization-rate-map object.

I would stage this work as follows:

1. Query support on the target device and create a small native map.
2. Prove import and reconstruction in an isolated framebuffer.
3. Establish how the built-in desktop scene pass can consume it.
4. Validate screen/depth readers, MSAA, transparency, scaling and the final composite.
5. Compare complete frames against the simpler crop approach.

Apple’s **metal-cpp** provides a low-overhead C++ interface suitable for a native experiment. It is a practical option for a GDExtension investigation; it does not itself solve ownership of Godot’s built-in scene passes. [Apple Developer](https://developer.apple.com/metal/cpp/?utm_source=chatgpt.com)

This is the highest-upside engine-level candidate in the research, with correspondingly greater integration risk.

---

## 6. An aggressive idea I tested and would deprioritize: cache all cloud-relief samples

The cloud-relief shader evaluates density at three positions along the light direction, using offsets 0.10, 0.28 and 0.62. Those values feed transmission, illumination and the shoulder term. [Current relief source](https://github.com/bultodepapas/OpenRCsimulator/blob/93ffbb101917dff86ecc2632f07e2e45c450a178/app/render/cloud_relief.gdshaderinc).

The tempting optimization was to bake the three resulting densities into RGB. One filtered texture sample would then supply all three inputs.

It also offered temporal reuse: if wind only translates a periodic cloud field, lookup coordinates can move without rebuilding the field.

### The numerical screen showed the problem

For the unclustered coverage-0.35 case:

| Cache size | Persistent RGBA16F storage | Maximum active-cloud scalar-lighting error |
|---|---:|---:|
| 512² | 2 MiB | **0.366** |
| 1024² | 8 MiB | **0.160** |
| 2048² | 32 MiB | **0.0425** |

The clustered low-sun case reached **0.0496** at 2048².

These are raw scalar-lighting differences, not final RGB errors. Nevertheless, they are much larger than those of the lattice experiment, and the memory cost is substantial.

The mechanism is clear: **interpolating already-thresholded density loses sub-texel structure**. The shoulder term then uses a difference between the exact cloud body and an interpolated neighboring density, which can amplify the discrepancy.

Light changes create another problem. In one controlled stale-cache test, changing the light-ray x component by 0.05 without rebuilding increased the maximum error from 0.0425 to 0.0878.

**I would stop this particular design here.** A future cache could retain only a smoother, low-frequency lighting component, but that would be a different experiment requiring its own error analysis.

---

## 7. A small mathematical trick: a 1 KB solar-halo table

The sky contains a broad solar halo of the form:

\[
H(\mu)=e^{-18\arccos(\mu)}
\]

where \(\mu\) is the view/sun dot product.

A table sampled uniformly in \(\mu\) wastes most of its resolution away from the steep region near the sun. I tested a change of variable:

\[
t=\sqrt{\frac{1-\mu}{2}}=\sin\left(\frac{\theta}{2}\right)
\]

The stored function becomes:

\[
H(t)=e^{-36\arcsin(t)}
\]

This places useful table resolution around the steep part of the halo.

### Result

A **512-entry R16F table—1,024 bytes—** produced a maximum normalized halo error of **0.00067842** over 820,197 unique float32 inputs, including every float32 dot value between approximately 0.99 and 1.

A naive 512-entry table uniformly spaced in the dot product produced a maximum error around **0.351** in the same screen.

That is a useful example of improving an approximation through its coordinate system rather than simply making the texture larger.

### The source review also exposed a limitation

The current [sky shader](https://github.com/bultodepapas/OpenRCsimulator/blob/93ffbb101917dff86ecc2632f07e2e45c450a178/app/render/sky.gdshader) shares the `acos` result with the analytic solar-disc edge.

Therefore, replacing the halo alone does **not** remove that shared angle calculation. It replaces the halo exponential while adding a square root and a lookup.

Removing most angle evaluations would require a separate, conservatively bounded disc-support path that preserves the analytic disc and cubemap behavior. That restructuring has not been implemented here.

**I would keep this below the cloud experiments in priority.** Its numerical behavior is attractive; its integrated performance case is still weak.

---

## 8. Additional source-specific opportunities

### Hoist the pilot’s ground-color anchor out of fragment work

The shared [grass-surface shader](https://github.com/bultodepapas/OpenRCsimulator/blob/93ffbb101917dff86ecc2632f07e2e45c450a178/app/render/grass_surface.gdshaderinc) evaluates three value-noise terms at the uniform `pilot_xz` inside the relevant near-pilot region.

That anchor depends on the station, not on each fragment.

I would test computing it in a shared GPU or vertex-stage path and passing the result to the ground and near-grass shading. First inspect what the compiler already does: some uniform-expression work may already be optimized.

A direct GDScript replacement needs care because the float hash contains operations such as `fract`; CPU double precision and GPU float arithmetic can produce different hash values. This is a case where moving an expression to a “cheaper” stage can quietly change the image.

### Cache terrain material channels, with lighting kept live

The terrain shader contains procedural fields at several spatial scales. Slowly varying material channels are candidates for a bounded world-space cache.

I would cache the underlying broad variation, while keeping near detail, footprint filtering, pilot-specific adjustments, weather and lighting live. Begin with a bounded texture for the current field; introduce clipmaps only if travel extent makes them necessary.

The distinction is important: caching the final shaded color would make the cache dependent on far more changing inputs.

### Use front-to-back reasoning for layered clouds

The layered sky currently computes multiple decks. Front-to-back accumulation exposes how much later layers can still contribute:

\[
C \mathrel{+}=T\alpha C_{\text{layer}},\qquad
T\mathrel{*}=1-\alpha
\]

This permits an error-bounded decision to skip some hidden upper-layer shading.

A conservative first version would still compute density for solar occlusion, while selectively skipping expensive relief on almost-hidden decks. Arbitrary opacity cutoffs are unsuitable because the omitted contribution can matter near a bright sun.

This opportunity is weather-specific. The classic single-deck case has no inter-layer work to eliminate.

### Publish read-mostly textures deliberately

Apple documents texture optimization and lossless compression opportunities associated with private storage and appropriate usage flags. Permanently writable resources can have different optimization opportunities from read-mostly ones. [Apple Developer](https://developer.apple.com/videos/play/tech-talks/10580/?utm_source=chatgpt.com)

The pinned Godot Metal backend already places eligible textures in private storage, so simply recommending “use private textures” would repeat existing behavior.

For a future compute-built lattice cache, the useful experiment is narrower: compare a writable bake resource against publishing a read-mostly texture, accounting for the copy and synchronization cost. That decision should follow measurements.

---

## 9. Tools and experiments I would use next

The project already has useful infrastructure. I would extend its existing probes and checked runner for these candidates.

| Tool or facility | Specific purpose |
|---|---|
| Existing cloud-shadow probe | Compare reference and candidate values through actual canvas, spatial **and sky** consumers |
| Existing checked Godot runner | Retain logs, catch shader/engine errors and require explicit completion markers |
| Existing debug bridge and capture workflow | Reproduce flight views, motion, transitions and application behavior |
| Xcode Metal debugger and available GPU counters | Determine whether a candidate reduces arithmetic pressure or merely shifts the bottleneck to texture access, occupancy or bandwidth |
| Godot `Image` and explicit mip sampling | Build the independently authored lattice pyramid without adding a runtime library |
| metal-cpp/native GDExtension experiment | Test native rasterization-rate-map support, import and reconstruction |
| NumPy reference harnesses in the kit | Reject inaccurate mathematical ideas before spending time integrating them into rendering |

Apple’s profiling guidance emphasizes examining the GPU timeline together with occupancy, limiter and bandwidth information. Those measurements are what distinguish a useful arithmetic reduction from a trade that slows the complete frame. [Apple Developer Documentation](https://developer.apple.com/documentation/xcode/optimizing-gpu-performance?utm_source=chatgpt.com)

### The order I would execute

**First, qualify the bounded-density variants.** Compare them with the current implementation at actual 1920×1080 output, across sparse and dense clouds. Check raw GPU output near thresholds and seams before judging speed.

**Second, qualify the two-octave lattice atlas.** Include texture readiness, wrong-seed fallback and actual sky sampling. Measure the additional resident memory and bake/transition cost as well as steady-state frames.

**Third, build the rendered native-aircraft crop.** The geometry groundwork is complete. The next test must show that foreground occlusion, propellers, fog, lighting and crop edges remain correct during motion.

**Fourth, investigate the native Metal rate-map path.** Use a small extension-level proof before committing to modifications of the built-in desktop renderer.

For each, compare paired complete-frame runs under matched settings, retain moving image evidence, and measure transition hitches and sustained behavior. The 240 Hz float64 RK4 simulation, input timing and deterministic replay remain fixed.

**My strongest immediate bet is the combination of conservative cloud evaluation and the lattice atlas. My strongest architectural bet is aircraft-centered rendering.** The experiments now provide concrete code and evidence for pursuing both—and a clear reason to drop the first version of the full relief cache.