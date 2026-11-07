# Apple Silicon optimization research for OpenRC Simulator

I investigated **36 distinct official resources: 22 from Godot and 14 from Apple**, then checked their applicability against OpenRC’s code and its pinned engine. The annotated resource catalogue is below, with an application to OpenRC for every source.

**The strongest direction is to refine and qualify the existing ARM64 / Mobile / Metal path, remove avoidable work around the simulation, and investigate the GPU passes responsible for expensive frames.** The research supports several focused experiments; it does not justify a wholesale renderer change, a lower physics frequency, or a broad rewrite in native code.

I read and cross-checked [`external Audits/CONSOLIDATED-AUDITS.md`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/external%20Audits/CONSOLIDATED-AUDITS.md). Shader baking, vegetation partitioning, MetalFX, resource lifetimes, and native-kernel work already appear in the project’s research. I identify those as existing work below. The additions here are **version-specific clarification, implementation guidance, and discriminating validation steps**.

This was research and source analysis. **I did not obtain new Apple Silicon benchmarks or change production files.** Existing repository measurements retain their original hardware, build, workload, and instrumentation limits.

## 1. The configuration these recommendations actually target

I rechecked the configuration and principal code paths through GitHub at revision **`347905cafed505cad758107f2790fab2b018e4c6`**.

| Area | Verified configuration | Consequence |
|---|---|---|
| Engine | **Godot `4.8.beta2.official.cafc17a19`**, pinned in [`get-godot.sh`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/get-godot.sh#L1-L6) | Older documentation needs checking against this engine revision. |
| Standard Apple Silicon renderer | ARM64 override requests **Mobile**; the base renderer is Compatibility in [`project.godot`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/project.godot#L60-L74) | Profile the effective renderer after startup and recovery, because configuration alone does not establish which path ran. |
| Graphics API | The pinned engine’s macOS RenderingDevice default is **native Metal** on Apple Silicon | Advice that assumes Godot must use Vulkan through MoltenVK does not describe this default. |
| macOS export | **Universal ARM64 + x86_64**, ad hoc signing, notarization disabled, in [`export_presets.cfg`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/export_presets.cfg#L48-L72) | Verify the delivered executable, loaded libraries, and running process independently. |
| Export execution | [`export.sh`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/export.sh#L116-L139) uses `--export-release` through a **headless** editor invocation | Relevant to shader-baker feasibility, discussed below. |
| Flight simulation | **240 Hz**, maximum **12 catch-up steps**, jitter fix **0**, custom interpolation | Rendering and power policies must preserve this timing contract. |
| Graphics defaults | **4× MSAA**, VSync enabled, `max_fps = 0`, reconstruction **Auto** in [`display_preferences.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/app_state/display_preferences.gd#L40-L49) | Zero means no explicit frame cap; VSync still affects pacing. Persisted preferences may override defaults. |
| Native flight-stage evaluator | [`native_stage.gd:305–307`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/sim/native_stage.gd#L305-L307) admits **Linux x86_64 only** | An ARM64 Godot process on macOS currently uses the reference flight-physics path. This does not imply Rosetta execution. |

The engine’s Metal default is explicit in its [pinned project-setting definition](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/ProjectSettings.xml#L3387-L3392). Godot’s official macOS export documentation confirms Universal 2 support. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html?utm_source=chatgpt.com)

A useful distinction throughout this review is:

- **Architecture:** Is the running process ARM64 or translated x86_64?
- **Renderer:** Is it Mobile, Forward+, or Compatibility?
- **Driver:** Is it Metal, Vulkan/MoltenVK, or OpenGL?
- **Physics backend:** Is it the reference evaluator or an admitted native evaluator?

Each belongs in the benchmark manifest.

## 2. How I would apply the research

### A. Measure the complete frame and accepted simulation tick

**Priority: prerequisite. Status: already planned; the research sharpens attribution.**

OpenRC’s [`simulation.gd:515–519`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/sim/simulation.gd#L515-L519) updates `step_usec` **before** remembering valid state and emitting event and `stepped` signals. Subscriber work therefore sits outside that measurement.

The useful decomposition is:

\[
T_{\text{accepted tick}}
=
T_{\text{integration and validation}}
+
T_{\text{state publication}}
+
T_{\text{observers}}.
\]

The application also performs input, camera, scenery, audio, UI, submission, and presentation work. A faster evaluator may leave the limiting frame cost unchanged.

Use Godot’s script profiler to identify GDScript work, then correlate it with Instruments’ CPU/thread and GPU timelines. A main thread waiting for GPU completion should lead to a different investigation from a main thread executing expensive observer code. Godot explicitly cautions that profiling can obscure waiting and server-side costs. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html?utm_source=chatgpt.com)

**An additional Apple-specific profiling concern:** periodic sampling can misrepresent periodic workloads. A 240 Hz simulation is a reason to check sampling bias, not evidence that bias has occurred. Where available, use Instruments’ CPU Profiler alongside repeatable script measurements. Apple’s Processor Trace requires **M4 or later on Mac**, so it is not part of an M1 procedure. [Apple Developer](https://developer.apple.com/videos/play/wwdc2025/308/?utm_source=chatgpt.com)

**Validation:** retain complete-tick distributions, observer costs, CPU thread states, GPU times, displayed-frame intervals, and observer-off controls. Keep diagnostic profiles separate from clean performance comparisons.

### B. Remove discarded observer work before changing numerical algorithms

**Priority: focused CPU candidate. Status: connected to the preceding review, not a newly discovered audit issue.**

The statistics adapter currently evaluates `_consumer.call(sample())` in [`fixed_wing_adapter.gd:38–48`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/statistics/fixed_wing_adapter.gd#L38-L48). Its sample includes array slices, rotations, air and terrain queries, contact interpretation, and dictionary construction. The service can subsequently discard that sample in [`service.gd:140–143`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/statistics/service.gd#L140-L143).

A service-owned eligibility check before constructing the sample is a concrete application of the literature’s recommendation to eliminate unnecessary work.

Illustrative design, **not an applied patch**:

```gdscript
# Service: owns the observation policy.
func wants_observation() -> bool:
    return not _suspended and not _branch and detector != null

# Adapter: receives this callable from the service.
func _publish_observation() -> void:
    if _wants_observation.call():
        _consumer.call(sample())
```

Both the accepted-step and terminal-contact paths should use the guarded publication, while retaining their existing conditions. Keep the service’s defensive guard and preserve signal subscription order.

If one discarded sample costs \(C_s\) milliseconds, its ordinary 240 Hz contribution is approximately:

\[
240C_s\ \text{milliseconds of CPU work per simulated second}.
\]

That is a cost model, not a measured saving.

**Validation:** compare fresh flight, checkpoint branching, suspend/resume, reset, terminal contact, and statistics persistence. Verify physical state, events, replay, and credited statistics; then measure complete-session CPU and frame tails on the Mac. The earlier isolated probe does not establish a MacBook FPS improvement.

### C. Keep native build changes conditional on a demonstrated CPU bottleneck

**Priority: verification now; native-kernel expansion remains conditional.**

Universal packaging is already present. On the actual Mac, inspect the executable and every loaded native module, and record the running architecture. Apple’s porting guidance distinguishes universal files from the architecture selected for a process; native and translated libraries cannot be mixed arbitrarily in that process. [Apple Developer](https://developer.apple.com/videos/play/wwdc2020/10214/?utm_source=chatgpt.com)

There is also a version-specific build detail worth preserving:

- Pinned Godot [`SConstruct:552–559`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/SConstruct#L552-L559) resolves automatic optimization to **`speed` for release**, versus `speed_trace` for debug/editor.
- Its [macOS build configuration](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/platform/macos/detect.py#L185-L190) resolves automatic LTO to **disabled**.

Those are engine defaults; the actual template build recipe remains the authority for a particular binary. Do not infer that adding `production=yes` enables macOS LTO. Debug symbols and debug features are separate settings, so an optimized diagnostic build with symbols can help attribution without becoming the shipping benchmark. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/introduction_to_the_buildsystem.html?utm_source=chatgpt.com)

A native evaluator port should follow measured complete-workload benefit. Amdahl’s law illustrates the limit:

\[
S=\frac{1}{(1-p)+p/s}.
\]

If an evaluator accounts for 20% of CPU time and becomes four times faster, the corresponding CPU-workload speedup is only about **1.18×**. A GPU-limited frame may gain less still. These are illustrative assumptions, not OpenRC measurements.

### D. Qualify spatial MetalFX at the resolutions where Auto actually selects it

**Priority: strong GPU experiment. Status: implemented policy, existing qualification work.**

OpenRC already has capability checks in [`metalfx_policy.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/render/metalfx_policy.gd#L11-L67). The pinned [viewport implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_viewport.cpp#L140-L165) rejects **FSR1, FSR2, and temporal MetalFX on Mobile**. Spatial MetalFX is not rejected by that branch.

The current Auto policy tries two-thirds scale, then 0.85, requiring at least **1,000 input rows**. Its consequences are:

| Output dimensions supplied to the policy | Auto selection when supported | Nominal 3D input |
|---|---|---|
| 1920 × 1080 | Native | 1920 × 1080 |
| 2560 × 1440 | Spatial MetalFX at 0.85 | 2176 × 1224 |
| 2560 × 1600 | Spatial MetalFX at two-thirds | Approximately 1706 × 1066 |
| 3840 × 2160 | Spatial MetalFX at two-thirds | 2560 × 1440 |

These are **policy-derived estimates**, not observed SDK execution sizes. The implementation labels that distinction explicitly in [`reconstruction.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/render/reconstruction.gd#L27-L58).

The mathematical opportunity is substantial:

\[
N_{\text{input pixels}}=s^2WH.
\]

At \(s=0.85\), input pixel count is 72.25% of native; at \(s=2/3\), it is approximately 44.44%. Total GPU time also contains geometry, shadows, fixed pass costs, and reconstruction:

\[
T_{\mathrm{GPU}}(s)\approx A+Bs^2+U(s).
\]

Consequently, pixel reduction is not an equivalent frame-time reduction. Resolution scaling is most useful when pixel work materially limits the frame. [Godot Engine (4.6) documentation in English](https://docs.godotengine.org/en/4.6/tutorials/3d/resolution_scaling.html?utm_source=chatgpt.com)

**Concrete experiment:** compare Native and the existing supported spatial modes at identical output dimensions, weather, aircraft, camera, and quality settings. At 1080p, a spatial comparison requires an explicit selection because Auto chooses Native.

Preserve antialiasing in the initial comparison: Apple expects spatial upscaling input to be antialiased. Evaluate moving distant aircraft, thin wings, propellers, runway markings, foliage, and night lights. Excessively aggressive mip bias can introduce flicker. [Apple Developer](https://developer.apple.com/videos/play/wwdc2022/10103/?utm_source=chatgpt.com)

### E. Investigate render-pass dependencies, vegetation, and AA separately

**Priority: after GPU attribution. Status: mostly existing investigations, with a focused Mobile foliage experiment.**

Three source paths are useful capture targets:

- [`lake/water.gdshader:14–15`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/render/lake/water.gdshader#L9-L19): screen and depth textures.
- [`sun_glare.gdshader:17`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/render/landscape_upgrade/sun_glare.gdshader#L12-L23): depth sampling.
- [`sun_afterimage.gdshader:9`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/render/sun/sun_afterimage.gdshader#L5-L13): mipmapped screen sampling.

On Apple’s tile-based GPUs, render-pass boundaries and attachment loads/stores can consume significant bandwidth. Capture the actual dependencies before changing an effect. Apple’s guidance also explains why opaque rendering, alpha testing, and transparency have different hidden-surface-removal behavior. [Apple Developer](https://developer.apple.com/videos/play/wwdc2020/10632/?utm_source=chatgpt.com)

A diagnostic comparison with one consumer absent can identify its marginal cost. It does not establish that removing the effect is an acceptable product change. Lake refraction, glare occlusion, and afterimages have intentional behavior.

**Memoryless attachments require engine work and lifetime proof.** An attachment needed by a later pass must remain available. A memoryless multisample attachment can still be useful when a supported resolve writes a separate persistent result; MSAA is not inherently incompatible with memoryless storage.

For vegetation, OpenRC already has substantial batching and LOD work. [`field_tree_detail.gd:9–14`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/render/field_tree_detail.gd#L9-L14) uses **256 m cells** and separate bark-detail policy. Smaller cells can improve culling and LOD while increasing submission cost. The project has already investigated 128 m versus 256 m.

One measurement trap is concrete: the pinned [Mobile LOD primitive-count branch](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp#L2338-L2359) does not apply the instance multiplier that appears in the non-LOD branch. Use GPU evidence or correctly account for instances when comparing geometry.

For foliage AA, [`treeline.gdshader:92–98`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/render/treeline.gdshader#L92-L98) uses alpha scissor and mip-dependent coverage adjustment. A **Mobile-specific alpha-to-coverage shader variant** is worth a controlled quality experiment. It requires shader changes, including `alpha_to_coverage`, `ALPHA_ANTIALIASING_EDGE`, and suitable `ALPHA_TEXTURE_COORDINATE`; a StandardMaterial checkbox does not alter this custom shader. [Godot Engine (4.6) documentation in English](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html?utm_source=chatgpt.com)

Keep 4× MSAA fixed initially. Measure foliage density, wind motion, camera-pan shimmer, and GPU cost. This is a possible quality improvement with an unknown performance tradeoff.

Similarly, use the existing [`shadow_settings.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/render/shadow_settings.gd#L19-L29) controls to isolate atlas size, cascades, filtering, distance, and depth format individually.

### F. Audit actual texture formats and peak resource residency

**Priority: especially relevant to the 8 GB floor host. Status: existing memory work; runtime verification required.**

Unified memory does not eliminate allocation, bandwidth, ownership, or synchronization costs. Metal’s shared and private modes both use system memory on Apple GPUs, but they differ in CPU accessibility; memoryless storage has a different lifetime. [Apple Developer Documentation](https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus?changes=_1\&utm_source=chatgpt.com)

For each expensive resource, trace:

**Source asset → import or runtime generation → decoded image → GPU texture → retained owners.**

That matters because OpenRC creates some textures at runtime. For example, [`ground.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/render/ground.gd#L65-L89) already generates mipmaps, while other systems create `ImageTexture` resources. Project-wide ETC2/ASTC import support does not prove that these runtime textures use block compression.

For an uncompressed RGBA8 texture with a complete mip chain:

\[
M\approx4WH\left(1+\frac14+\frac1{16}+\cdots\right)
=\frac{16}{3}WH.
\]

A hypothetical 4096² texture therefore occupies approximately **85.3 MiB** before implementation-specific overhead. That is an illustrative allocation calculation, not an inventory finding.

Prioritize large, frequently sampled resources. Smaller JPEG/PNG files do not necessarily reduce GPU residency. GPU block compression can reduce residency and sampling bandwidth, but normal maps, alpha masks, HDR data, and aircraft markings need format-specific quality checks. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html?utm_source=chatgpt.com)

Also separate **ASTC/BC-style block compression** from Apple’s **lossless texture optimization**. The latter has usage/format restrictions and can slightly increase footprint through metadata while reducing bandwidth. [Apple Developer Documentation](https://developer.apple.com/documentation/metal/optimizing-texture-data?changes=_11\&utm_source=chatgpt.com)

**Validation:** use Game Memory, Metal Resource Events, and VM tracks across loading and repeated Home/Fly/Workshop transitions. Allocations alone omits private Metal resources. Avoid adding overlapping process and GPU memory figures into a fabricated total. [Apple Developer Documentation](https://developer.apple.com/documentation/xcode/analyzing-the-memory-usage-of-your-metal-app?utm_source=chatgpt.com)

### G. Improve the remaining loading and first-use stalls

**Priority: named hitches. Status: loaders already implemented; remaining stages need attribution.**

[`home_preview_resources.gd:88–118`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/ui/home_preview_resources.gd#L88-L118) already requests threaded loading and polls completion. [`flight_scene_load.gd:18–36`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/ui/flight_scene_load.gd#L18-L36) already uses a worker and avoids joining it while alive.

Measure the remaining phases separately:

1. Resource acquisition and decoding.
2. Scene construction and publication.
3. GPU resource creation/upload.
4. Pipeline preparation.
5. First drawn frame.
6. First interactive frame.

Godot warns that an early `load_threaded_get()` blocks. Threading also does not make arbitrary active-scene-tree or GPU resource operations safe or inexpensive. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/tutorials/io/background_loading.html?utm_source=chatgpt.com)

The earlier review’s recording-start/stop bundle-hash path remains a concrete asynchronous-work candidate. Preserve its required checks and recording boundaries; use bounded worker ownership and generation-checked publication so a completion cannot affect an abandoned session.

**Shader baking:** current documentation says it requires a supported graphical export environment and does not work with `--headless`. The pinned baker additionally requires RenderingDevice/material-storage singletons. A controlled macOS Metal export should inspect the resulting artifact and cold first-use behavior. Baking intermediate shaders does not guarantee that every final hardware pipeline is ready. This work is already tracked in the audit. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html?utm_source=chatgpt.com)

### H. Use threading and power policies that respect simulation deadlines

**Priority: conditional on measured contention or background cost.**

The RK4 stages in [`integrator.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/app/physics/integrator.gd#L19-L35) depend on each other:

\[
k_1=f(y),\quad
k_2=f(y+\tfrac h2k_1),\quad
k_3=f(y+\tfrac h2k_2),\quad
k_4=f(y+hk_3).
\]

They are not four independent jobs. Parallel opportunities must come from sufficiently expensive independent work, with explicit ownership and deterministic publication. Apple warns that tiny jobs, excessive wakeups, and busy waits can lose performance and thermal headroom. [Apple Developer](https://developer.apple.com/videos/play/tech-talks/110147/?utm_source=chatgpt.com)

The pinned [Godot Apple thread implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/apple/thread_apple.cpp#L97-L107) maps priorities as follows:

| Godot thread priority | Apple QoS |
|---|---|
| LOW | Utility |
| NORMAL | User initiated |
| HIGH | User interactive |

WorkerThreadPool’s `high_priority` is a pool scheduling choice, not a P-core affinity request. Existing speculative trim and audio workers have different latency needs; change them only after tracing contention, readiness, and audio continuity.

For frame pacing, retain custom interpolation and test actual 60 Hz and supported higher-refresh configurations. The relevant budgets are **16.67 ms at 60 Hz** and **8.33 ms at 120 Hz**.

A crucial power-policy constraint is:

\[
f_{\min}=\frac{240}{12}=20\ \text{render frames/s}.
\]

With the current catch-up limit, an **unpaused** 15 FPS cap permits at most 180 physics ticks per wall-second, potentially slowing simulated time to 75% of real time. Lower-frequency background presentation must therefore distinguish a genuinely paused session from active flight. Godot documents this relationship between physics frequency, catch-up limits, and slowdown. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_engine.html?utm_source=chatgpt.com)

After sustained headroom is demonstrated, test two versus three swapchain images as a separate latency experiment. Double buffering can reduce queueing but makes missed deadlines more costly. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/tutorials/rendering/jitter_stutter.html?utm_source=chatgpt.com)

For thermal and Low Power Mode responses, defer optional work and reduce unnecessary display updates while preserving control responsiveness and restoring user settings on resume. Apple provides notifications for these conditions; OpenRC’s host-state collection is evidence gathering, not proof that an in-game policy exists. [Apple Developer Documentation](https://developer.apple.com/documentation/xcode/responding-to-power-notifications?changes=l_4\&language=objc\&utm_source=chatgpt.com)

## 3. Reproducible Apple Silicon profiling campaign

Use the existing [Apple Silicon performance plan](https://github.com/bultodepapas/OpenRCsimulator/blob/347905cafed505cad758107f2790fab2b018e4c6/docs/plans/apple-silicon-performance.md#L157-L177) and repository collectors.

### Baseline manifest

Record these before comparing candidates:

| Category | Required identity |
|---|---|
| Hardware | Mac model, chip, RAM, display, actual refresh rate |
| Software | macOS, Xcode/Instruments, exact Godot binary/template, project and package hashes |
| Execution | ARM64/translation status, effective renderer/driver, physics backend |
| Rendering | Logical window size, viewport pixels, drawable pixels, internal 3D pixels, MSAA, reconstruction, shadows, scenery |
| Scenario | Aircraft, field, weather/seed, camera, input tape, companions, recording state |
| Conditions | AC/battery, Low Power Mode, thermal state, focus/minimization, cache state |
| Instrumentation | Profiler, HUD, frame diagnostics, resource collectors, helper processes |

**1080p remains the primary product target.** A 1920×1080 window request on a Retina display does not by itself establish a 1920×1080 drawable. The project’s built-in M1 panel campaign should be reported under its measured dimensions.

### Scenarios

Include cold and warm Home→Fly, runway/contact work, representative powered flight, dense foliage and lake views, first-use sun/crash effects, recording start/stop, repeated lifecycle transitions, and paused/unfocused/minimized states. Qualify companion workloads separately; the solo technical fixture does not establish companion performance.

### Instruments and evidence

| Tool | Question it answers |
|---|---|
| Godot script profiler / existing debug bridge | Which script functions and observers consume time? |
| CPU Profiler or Time Profiler plus thread trace | Is the CPU executing, blocked, preempted, or repeatedly waking? |
| Game Performance / Metal System Trace | What caused a particular delayed displayed frame? |
| Metal debugger and GPU counters | Which passes, shaders, dependencies, or resources limit the GPU? |
| Game Memory / VM / Metal Resource Events | What is allocated, resident, retained, or growing? |
| Metal HUD | What renderer/device, actual layer/scaler sizes, GPU time, and presentation behavior are observable? |

HUD GPU time, present delay, and on-glass frame interval are different quantities; its rolling averages cannot substitute for complete hitch distributions. [Apple Developer Documentation](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics?changes=__1\&utm_source=chatgpt.com)

Follow the Mac plan’s comparison protocol:

- **Five independent alternating baseline/candidate pairs**, initially 30 seconds warmup plus 120 seconds measured.
- **Five fresh-process and five warm loading trials**, with cache state identified.
- **Three independent 30-minute active-flight runs** for baseline and finalists, excluding warmup.
- Separate AC and battery claims; retain early/final five-minute behavior.
- Report p50/p95/p99, maxima, hitch counts and bursts, CPU/GPU attribution, simulation/wall ratio, readiness, memory pressure, and visual/control results.

Adopt a candidate when it exceeds run variation and meets the project’s practical improvement criterion, or removes a reproducible defect. Preserve the existing exact replay, physics, event-order, visual-readability, and release gates. Short rejected candidates do not need full sustained campaigns.

## 4. The 36 official resources and their OpenRC applications

These are distinct documents or video transcripts. Different versions or anchors of the same document are counted once. Godot manuals provide guidance; pinned engine source controls version-sensitive conclusions.

### Native execution, CPU, and threading

| # | Resource | Application to OpenRC |
|---:|---|---|
| 1 | [Godot — Exporting for macOS](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html) | Verify the existing Universal 2 package and delivered artifact; ARM64 packaging is already implemented. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html?utm_source=chatgpt.com) |
| 2 | [Godot — Compiling for macOS](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_for_macos.html) | Use ARM64/x86_64 template procedures if a custom engine becomes necessary; distinguish editor, debug, and release templates. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_for_macos.html?utm_source=chatgpt.com) |
| 3 | [Godot — Introduction to the buildsystem](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/introduction_to_the_buildsystem.html) | Separate optimization, symbols, and debug features. Check beta2 source before transferring documented defaults or enabling LTO. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/introduction_to_the_buildsystem.html?utm_source=chatgpt.com) |
| 4 | [Apple — Port your Mac app to Apple silicon](https://developer.apple.com/videos/play/wwdc2020/10214/) | Inspect process architecture and compatible loaded modules independently from universal packaging and physics-backend selection. [Apple Developer](https://developer.apple.com/videos/play/wwdc2020/10214/?utm_source=chatgpt.com) |
| 5 | [Godot — CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html) | Attribute the complete tick and frame, including observers and waiting, before optimizing evaluator internals. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html?utm_source=chatgpt.com) |
| 6 | [Apple — Optimize CPU performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/308/) | Check sampling bias in periodic 240 Hz work; use available CPU profiling tools without promising M4 Processor Trace on M1. [Apple Developer](https://developer.apple.com/videos/play/wwdc2025/308/?utm_source=chatgpt.com) |
| 7 | [Godot — Using multiple threads](https://docs.godotengine.org/en/stable/tutorials/performance/using_multiple_threads.html) | Preserve bounded worker lifetimes and completion-aware joins in trim and loading jobs. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/performance/using_multiple_threads.html?utm_source=chatgpt.com) |
| 8 | [Godot — Thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html) | Keep active scene mutation and result publication under their current ownership; isolate numeric and file work. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html?utm_source=chatgpt.com) |
| 9 | [Godot — WorkerThreadPool](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html) | Consider sufficiently coarse independent jobs; include dispatch, synchronization, and task cleanup costs. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html?utm_source=chatgpt.com) |
| 10 | [Apple — Tune CPU job scheduling for Apple silicon games](https://developer.apple.com/videos/play/tech-talks/110147/) | Investigate worker count, wakeups, contention, and busy waiting only where traces identify a cost. [Apple Developer](https://developer.apple.com/videos/play/tech-talks/110147/?utm_source=chatgpt.com) |
| 11 | [Apple — Prioritize Work at the Task Level](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheTaskLevel.html) | Apply QoS according to urgency. This archived guide explains semantics; pinned Godot source establishes the actual mapping. [developer.apple.com](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheTaskLevel.html?utm_source=chatgpt.com) |

### Rendering, reconstruction, geometry, and shaders

| # | Resource | Application to OpenRC |
|---:|---|---|
| 12 | [Godot — Overview of renderers](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html) | Evaluate features for the effective Mobile/Metal path; renderer selection and API selection are distinct. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html?utm_source=chatgpt.com) |
| 13 | [Godot — Resolution scaling](https://docs.godotengine.org/en/4.6/tutorials/3d/resolution_scaling.html) | Separate internal 3D resolution from UI/output resolution and quantify the pixel-work experiment. [Godot Engine (4.6) documentation in English](https://docs.godotengine.org/en/4.6/tutorials/3d/resolution_scaling.html?utm_source=chatgpt.com) |
| 14 | [Apple — Boost performance with MetalFX Upscaling](https://developer.apple.com/videos/play/wwdc2022/10103/) | Qualify spatial input quality and actual execution; temporal reconstruction requires additional inputs and renderer support. [Apple Developer](https://developer.apple.com/videos/play/wwdc2022/10103/?utm_source=chatgpt.com) |
| 15 | [Godot — 3D antialiasing](https://docs.godotengine.org/en/4.6/tutorials/3d/3d_antialiasing.html) | Preserve the 4× baseline while distinguishing geometry-edge, foliage-alpha, and shader aliasing. [Godot Engine (4.6) documentation in English](https://docs.godotengine.org/en/4.6/tutorials/3d/3d_antialiasing.html?utm_source=chatgpt.com) |
| 16 | [Godot — Spatial shaders](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html) | Implement any treeline alpha-to-coverage experiment in the custom shader with its required outputs. [Godot Engine (4.6) documentation in English](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html?utm_source=chatgpt.com) |
| 17 | [Godot — Optimization using MultiMeshes](https://docs.godotengine.org/en/4.6/tutorials/performance/using_multimesh.html) | Balance batching against group-wide visibility. Existing stars, vegetation, and grass already use batching. [Godot Engine (4.6) documentation in English](https://docs.godotengine.org/en/4.6/tutorials/performance/using_multimesh.html?utm_source=chatgpt.com) |
| 18 | [Godot — Mesh level of detail](https://docs.godotengine.org/en/4.6/tutorials/3d/mesh_lod.html) | Requalify tree-cell/LOD tradeoffs with camera zoom and correctly counted instance geometry. [Godot Engine (4.6) documentation in English](https://docs.godotengine.org/en/4.6/tutorials/3d/mesh_lod.html?utm_source=chatgpt.com) |
| 19 | [Godot — Visibility ranges / HLOD](https://docs.godotengine.org/en/4.6/tutorials/3d/visibility_ranges.html) | Use hysteresis for appropriate transitions; measure transparent overlap before introducing fades. [Godot Engine (4.6) documentation in English](https://docs.godotengine.org/en/4.6/tutorials/3d/visibility_ranges.html?utm_source=chatgpt.com) |
| 20 | [Godot — Optimizing 3D performance](https://docs.godotengine.org/en/4.6/tutorials/performance/optimizing_3d_performance.html) | Separate draw-call, geometry, and transparency costs. Forward+ automatic instancing guidance should not be assumed for Mobile. [Godot Engine (4.6) documentation in English](https://docs.godotengine.org/en/4.6/tutorials/performance/optimizing_3d_performance.html?utm_source=chatgpt.com) |
| 21 | [Godot — Reducing shader/pipeline compilation stutter](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html) | Investigate graphical Metal shader baking and first-use pipeline readiness as separate stages. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html?utm_source=chatgpt.com) |
| 22 | [Apple — Optimize Metal Performance for Apple silicon Macs](https://developer.apple.com/videos/play/wwdc2020/10632/) | Capture lake/glare/afterimage attachment dependencies, resolves, and bandwidth before proposing engine changes. [Apple Developer](https://developer.apple.com/videos/play/wwdc2020/10632/?utm_source=chatgpt.com) |
| 23 | [Apple — Performance best practices for Metal shaders](https://developer.apple.com/videos/play/tech-talks/111373/) | Investigate register pressure, precision, and specialization only for measured shaders; distinguish newer GPU-family examples from M1 behavior. [Apple Developer](https://developer.apple.com/videos/play/tech-talks/111373/?utm_source=chatgpt.com) |
| 24 | [Apple — Optimize Metal apps and games with GPU counters](https://developer.apple.com/videos/play/wwdc2020/10603/) | Correlate occupancy, bandwidth, texture/ALU limits, and overdraw. A single counter does not establish the bottleneck. [Apple Developer](https://developer.apple.com/videos/play/wwdc2020/10603/?utm_source=chatgpt.com) |

### Memory, loading, pacing, and power

| # | Resource | Application to OpenRC |
|---:|---|---|
| 25 | [Godot — Importing images](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html) | Distinguish disk compression from GPU residency; preserve normal-map channels, alpha quality, and mip behavior. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html?utm_source=chatgpt.com) |
| 26 | [Godot — ResourceImporterTexture](https://docs.godotengine.org/en/stable/classes/class_resourceimportertexture.html) | Inspect each relevant import recipe instead of treating the global ETC2/ASTC setting as proof of runtime compression. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/classes/class_resourceimportertexture.html?utm_source=chatgpt.com) |
| 27 | [Apple — Choosing a resource storage mode for Apple GPUs](https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus) | Inspect actual GPU resource ownership and lifetime; unified memory does not make access and synchronization free. [Apple Developer Documentation](https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus?changes=_1\&utm_source=chatgpt.com) |
| 28 | [Apple — Optimizing texture data](https://developer.apple.com/documentation/metal/optimizing-texture-data) | Evaluate lossless GPU texture optimization separately from imported block compression and CPU readback requirements. [Apple Developer Documentation](https://developer.apple.com/documentation/metal/optimizing-texture-data?changes=_11\&utm_source=chatgpt.com) |
| 29 | [Apple — Analyzing memory usage of your Metal app](https://developer.apple.com/documentation/xcode/analyzing-the-memory-usage-of-your-metal-app) | Measure loading peaks and retained resources using allocation, Metal, and VM evidence together. [Apple Developer Documentation](https://developer.apple.com/documentation/xcode/analyzing-the-memory-usage-of-your-metal-app?utm_source=chatgpt.com) |
| 30 | [Godot — Background loading](https://docs.godotengine.org/en/4.7/tutorials/io/background_loading.html) | Preserve the existing completion-polling loaders; investigate publication and first-use stages rather than adding another generic loader. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/tutorials/io/background_loading.html?utm_source=chatgpt.com) |
| 31 | [Godot — Optimization using Servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html) | Consider lower-level submission only for measured node overhead, with explicit RID and resource lifetime management. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html?utm_source=chatgpt.com) |
| 32 | [Apple — Analyzing performance of your Metal app](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app) | Trace an actual delayed displayed frame through CPU scheduling, GPU execution, and presentation. [Apple Developer Documentation](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app/?utm_source=chatgpt.com) |
| 33 | [Apple — Understanding Metal Performance HUD metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics) | Observe architecture, layer dimensions, scaler dimensions, GPU time, and presentation delay without conflating them. [Apple Developer Documentation](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics?utm_source=chatgpt.com) |
| 34 | [Godot — Fixing jitter, stutter, and input lag](https://docs.godotengine.org/en/4.7/tutorials/rendering/jitter_stutter.html) | Test queue-depth and latency tradeoffs after headroom exists; preserve OpenRC’s custom interpolation. [Godot Engine (4.7) documentation in English](https://docs.godotengine.org/en/4.7/tutorials/rendering/jitter_stutter.html?utm_source=chatgpt.com) |
| 35 | [Godot — Engine class](https://docs.godotengine.org/en/latest/classes/class_engine.html) | Validate frame caps against 240 Hz physics and the 12-step catch-up limit, especially in background modes. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_engine.html?utm_source=chatgpt.com) |
| 36 | [Apple — Responding to power notifications](https://developer.apple.com/documentation/xcode/responding-to-power-notifications) | Design optional-work policies for Low Power Mode and thermal pressure, then measure sustained behavior on each claimed power profile. [Apple Developer Documentation](https://developer.apple.com/documentation/xcode/responding-to-power-notifications?changes=l_4\&language=objc\&utm_source=chatgpt.com) |