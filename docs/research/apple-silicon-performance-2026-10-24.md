# Apple Silicon performance: source review

2026-10-24 · DT-MAC-00 · **Documentation and source inspection only. No Mac benchmark, thermal soak, exported launch or performance gain was measured.**

The [execution plan](../plans/apple-silicon-performance.md) owns work and acceptance. This snapshot supplements the [2026-10-07 Apple Silicon investigations](desktop-delivery-investigations/DT-00-R2/README.md); it does not replace their packaging, trust, controller, audio or numerical evidence.

**Same-day follow-up:** [twenty M1–M5 investigations](desktop-delivery-investigations/DT-MAC-00-R1/README.md) expand this initial review. The user has now confirmed a MacBook Air M1 with 8 GB for testing; its GPU variant/macOS and all benchmark results remain pending. The earlier hardware-availability question below describes this initial snapshot, not the current plan.

## Repository evidence inspected

The working tree contained unrelated aircraft, rendering and native reconstruction edits. This review records observed behavior, not a frozen benchmark baseline; DT-MAC-01 must freeze source and package hashes before measurements. The graph index returned no relevant reconstruction symbols, so known source/config paths and tool READMEs were inspected directly.

| Source | Observation relevant to the plan |
| --- | --- |
| [project.godot](../../app/project.godot), [engine downloader](../../app/get-godot.sh) | 4.7.2-stable pin; Compatibility, 1280×720 viewport, 4× MSAA; downloader selects Linux x86_64 |
| [export presets](../../app/export_presets.cfg), [STACK](../STACK.md) | Universal macOS preset, shared float64/240 Hz simulation and separate native evaluator policy |
| [main.gd](../../app/main.gd), [frame diagnostics](../../app/render/frame_diagnostics.gd), [performance guide](../../research/performance/README.md#cpu-gpu-and-memory-diagnosis) | Method/adapter/API metadata is not explicit driver identity; boolean VSync loses mode detail; duration/sample bounds prevent a general continuous soak; Mac Compatibility GPU timing is unavailable |
| [High launcher](../../tools/graphics/launch.py), [graphics guide](../../tools/graphics/README.md) | Standard/High only; explicit driver/method overrides rejected; High adds effects beyond the backend change |
| [reconstruction](../../app/render/reconstruction.gd), [native experiment](../../tools/graphics/native/README.md) | No OpenRC MetalFX provider; FSR3/DLSS experiment is Windows/Vulkan and a separate engine build |
| [Desktop plan](../DESKTOP-DELIVERY-PLAN.md), [global performance sequence](../plans/global-performance-visual-quality.md) | M1 8 GB qualification already planned, 1080p primary; native launch, sustained performance and pilot gates remain separate |

## Findings and implications

**Renderer/API distinction.** Compatibility uses OpenGL; Mobile and Forward+ can use Metal. Mobile is also a desktop option. A renderer experiment must hold feature coverage constant before comparing a richer profile. This supports a Mobile/Metal-first hypothesis for the M1 floor, not a prediction that it wins. [Godot renderer overview](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html).

**Native Metal versus translation.** Godot documents native Metal on Apple Silicon and Vulkan through MoltenVK as a separate route. It documents Metal 4 selection with macOS 26+, falling back to Metal 3 on older supported systems. An OS upgrade is therefore a confounder in a driver comparison. [Godot 4.7 architecture](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html). The documented Apple Silicon export minimum is macOS 13, not proof that OpenRC passes on it. [Engine requirements](https://docs.godotengine.org/en/4.7/about/system_requirements.html).

**M1 is not one performance tier.** Apple's Air specification distinguishes 7/8 GPU cores and 8/16 GB memory. Its fanless design makes sustained load especially relevant; a short run on an actively cooled Pro is insufficient evidence for the Air. Later chips and higher memory configurations need named results. [M1 Air specifications](https://support.apple.com/en-us/111883), [Apple's fanless Air announcement](https://www.apple.com/newsroom/2020/11/introducing-the-next-generation-of-mac/).

**GPU architecture suggests questions, not automatic fixes.** Apple describes tile-based deferred rendering, shared memory access and the cost of moving render attachments between tile storage and memory. Investigate redundant render targets, bandwidth, pass boundaries and shader cost through existing engine settings first. Engine-level memoryless attachments, encoder merging or precision changes require an attributed engine bottleneck and a separate proposal. [Apple Silicon optimization](https://developer.apple.com/videos/play/wwdc2020/10632/), [high-end game optimization](https://developer.apple.com/videos/play/wwdc2021/10148/).

**MetalFX is available to investigate without an engine-upgrade prerequisite.** The tagged 4.7.2 `Viewport.xml` contains Spatial and Temporal modes and their Metal-driver restriction. Temporal has a queried minimum scale and can operate at native resolution. Actual renderer/device availability and OpenRC integration still require verification; this finding does not authorize enabling it globally. [Pinned API source](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Viewport.xml), [4.7 Viewport reference](https://docs.godotengine.org/en/4.7/classes/class_viewport.html).

**Shader preparation is backend-specific.** Mobile/Forward+ have pipeline precompilation/ubershader mechanisms; Compatibility needs its own first-use preparation. Fresh-process and shader-cache-cold are different experiments. Use native pipeline evidence before adding a loading warmup that could itself increase startup cost. [Godot pipeline guide](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html).

**Geometry and transparency need whole-frame checks.** Godot's frustum/occlusion/LOD tools and material organization can reduce unnecessary work. Open terrain may offer little occlusion, and transparent overlap can remain expensive after draw-call reduction. These are bounded candidates against the retained landscape, not a request for new scenery. [Godot 3D performance](https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html).

## Native diagnostic tools

| Primary source | Practical use / scope |
| --- | --- |
| [Apple: analyzing Metal performance](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app) | Instruments Game Performance combines threading/system activity and Metal System Trace; examine CPU/GPU scheduling and frame disruption |
| [Apple: Metal developer workflows](https://developer.apple.com/documentation/xcode/metal-developer-workflows) | Metal debugger/counters and API/Shader Validation; distinguish correctness instrumentation from release timings |
| [Apple: Metal Performance HUD](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance) | Overlay/logging exposes GPU time and intervals; use transient environment configuration and separately measure observer overhead |
| [Apple: GPU counters](https://developer.apple.com/videos/play/wwdc2020/10603/) | Diagnose limiting GPU stages; counters vary by GPU/tool version, so preserve availability and units |
| [Apple: power modes](https://support.apple.com/en-us/101613) | Record the mode actually offered/selected on each host; do not assume all Macs provide the same controls |

Use the Xcode/Instruments versions compatible with the selected OS. Tool availability on a newer GPU/OS must not be assumed on M1 or the oldest supported system. Existing [Mac diagnostic guidance](desktop-delivery-investigations/DT-00-R2/12-macos-diagnostics-symbols.md) owns symbol UUIDs, native crash reports and local collection. Developer tools are not a requirement for pilots.

## Recommended order and unresolved questions

1. Fix the measurement prerequisites: native editor/package identity, real backing pixels, explicit driver, truthful frame/presentation semantics and continuous bounded collection.
2. Attribute the unmodified M1 1080p workload before choosing CPU, memory, GPU or pacing work. Preserve the same-host replay baseline.
3. Compare plain Mobile/Metal and Forward+/Metal with common features; benchmark High effects separately. Review the known reflection leak on Mac.
4. Test MetalFX only after renderer correctness and a demonstrated pixel-cost bottleneck, including distant-aircraft temporal readability.
5. Qualify sustained flight, transitions and final release bytes; then expand resolution and host coverage.

Unresolved: physical Mac availability/SKU, current driver behavior, renderer-specific shader differences, actual memory ceiling, MetalFX method/device support and benefit, sustained battery performance and pilot acceptance. No synthetic score, Windows GPU measurement or source statement answers these questions.

All external references above are primary Apple/Godot sources consulted for this review. Godot references are versioned to 4.7 or tagged 4.7.2 where possible. The future upgrade remains with [GDU](../plans/godot-4.8-upgrade.md); refresh upstream defect status when executing a candidate. No downloaded third-party assets, benchmark images or new runtime dependencies were added.
