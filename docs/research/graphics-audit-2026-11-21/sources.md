# Primary sources and applicability

Research date: **2026-11-21**. Technical guidance below comes from project source/artifacts and official engine/vendor/tool documentation. Public documentation can change; the audited application and CI evidence are bound to immutable source/run identities. No external source supplies a measured OpenRC improvement. The suggestions are inferences to be tested through [platform validation](platform-validation.md).

## Application and empirical evidence

| Source | Use in this audit | Limit |
| --- | --- | --- |
| [Audited application tree](https://github.com/bultodepapas/OpenRCsimulator/tree/57abea025f62b20233ca281d58d2acbee4ab8b8e) | Exact triggers, guards, resources, clocks and formulas | Source confirms behavior, not its elapsed cost on every target |
| [Repo subagent guide](https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/docs/SUBAGENTS.md) | Specialist briefs, review and lead ownership | Requested routing is distinct from verified effective runtime |
| [Current failed CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44833680915) | Exact baseline UID/preflight failure and skipped jobs | Not a GPU failure |
| [Earlier successful CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44747723262) | Actual jobs, software-renderer log, native CPU artifact | Older source; not current qualification |
| [RCV-41](../rc-monster-truck/RCV-41/README.md) | Previously measured Nitro identity overhead and repaired cache | Older Godot/Windows/headless/concurrent host; no current FPS prediction |
| [AFC-00-R4](../ai-companions/AFC-00-R4/README.md) | Prior fleet frame/callback evidence and counts | Older 720p/Windows case; not current native-per-agent attribution |
| [Tick observer experiment](../visual-quality-implementation/VQ-01c/tick-observers-2026-10-27/README.md) | Why complete observers matter | Older headless/shared-host attribution ceiling, not additive savings |
| [UHD 630 comparison](../visual-quality-implementation/VQ-07/igpu-uhd630-2026-11-20/README.md) | Counterexample to universal Mobile-faster assumption | Linux/Mesa/LXC/headless Weston, scripted High, no panel presentation |
| [RTX 3090 matrix](../visual-quality-implementation/VQ-07/rtx3090-matrix-2026-11-17/README.md) | Existing setting evidence and timing-freshness limits | Native 4× versus FSR2 Native AA does not isolate same-AA provider cost |
| [Graphics ladder](../../../research/performance/graphics_ladder/README.md) | Real Home → Fly route, profiles, effective settings, thermal/reference drift | Bridge intervals remain process timing; historical external Mac output is not native Retina |
| [Previous optimization audit](../performance-audit-2026-11-19/README.md) | Known findings and already-fixed resolution table | Historical bodies must be reconciled with current source |

## Engine mechanisms

| Official source | Mechanism used | Application boundary |
| --- | --- | --- |
| [Godot beta2 release](https://github.com/godotengine/godot-builds/releases/tag/4.8-beta2) | Engine release/source identity | Exact upstream source files were not retrievable; local binary checksum and version were verified |
| [Texture2D `get_image`](https://docs.godotengine.org/en/stable/classes/class_texture2d.html#class-texture2d-method-get-image) | Image copy and GPU fetch can have a synchronization cost | R5 is an occasional cold/seed-miss path, not an every-frame call |
| [Image formats](https://docs.godotengine.org/en/stable/classes/class_image.html#enum-image-format) | RGH has two half-float channels | Logical base-texel calculation excludes real allocation/transients |
| [MultiMesh optimization](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html) | Bulk native buffers and whole-batch visibility | Finer batches trade draw/CPU cost against vertex waste |
| [GPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html) | Attribute CPU/driver/GPU work and bandwidth | General guidance; no universal per-device ranking |
| [Resolution scaling](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html) | Internal pixel count and reconstruction tradeoffs | Quadratic pixel count is not quadratic total frame time |
| [Sky shaders](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/sky_shader.html) | Background/radiance/subpasses and half-resolution experiment | Latest docs; confirm exact beta2 feature behavior and visual contracts |
| [Screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html) | Back-buffer/screen capture dependencies | Removing one water consumer may not remove shared copies required elsewhere |
| [Pipeline compilation](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html) | Forward+/Mobile precompilation differs from Compatibility; first-use permutations matter | Latest docs, not exact-pin proof; do not treat zero Compatibility counters as no compile work |
| [Thread-safe APIs](https://docs.godotengine.org/en/latest/tutorials/performance/thread_safe_apis.html) | Active tree ownership and GPU synchronization | No permission to move arbitrary live simulation/render state to workers |
| [Engine physics-step cap](https://docs.godotengine.org/en/stable/classes/class_engine.html#class-engine-property-max-physics-steps-per-frame) | Catch-up ceiling relation | Application's 240/12 values govern the arithmetic; special clock modes change inference |

## Native hardware instrumentation

| Official source | Use | Caveat that changes the experiment |
| --- | --- | --- |
| [PresentMon README](https://github.com/GameTechDev/PresentMon/blob/main/README.md) and [capture definitions](https://github.com/GameTechDev/PresentMon/blob/main/README-CaptureApplication.md) | Windows process/GPU/display event distinctions | OpenGL/Vulkan instrumentation and HWS caveats; no invented missing metrics or input-to-photon result |
| [Apple Metal HUD](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance) and [metric definitions](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics) | Per-frame logs, layer dimensions, command-buffer/encoder time and presentation interval | Encoder tracking can add overhead; actual target OS/runtime availability must be checked |
| [NVIDIA Nsight Graphics](https://developer.nvidia.com/nsight-graphics) and [current requirements](https://developer.nvidia.com/nsight-graphics/get-started) | Supported native Vulkan/OpenGL traces on Windows/Linux | Feature and GPU/API support vary by installed version; not a universal capture path |
| [AMD RGP manual](https://gpuopen.com/manuals/rgp_manual/) | Queue/barrier/wave and pass attribution for supported explicit APIs | No Compatibility/OpenGL; Linux RADV and Developer Panel capture paths differ |

## Research dispositions

**Adopt:** native engine bulk APIs, real pass attribution, correct workload identity, instrumented/uninstrumented controls, actual backend counters and explicit presentation scope.

**Test conditionally:** half-resolution clouds, cheaper water variants, finer grass batches, lazy shadow construction, validated GPU-resident/offline cloud publication, individual native companions and bounded immutable diagnostic writers.

**Reject as unsupported conclusions:** “all dedicated GPUs hold 60,” “Mobile is always faster,” “native stage speedup equals FPS gain,” “an FPS counter measures display presentation,” “positive root polls are fresh whole frames,” “Off always means zero allocated shared resources,” or “a recent green workflow qualifies a different source.” These are conclusions that the inspected evidence cannot support, rather than claims that the opposite is universally true.
