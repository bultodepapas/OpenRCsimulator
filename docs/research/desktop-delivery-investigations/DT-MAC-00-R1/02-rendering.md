# DT-MAC-00-R1 — Rendering investigations I08–I14

2026-10-24 · Research only. No Apple Silicon renderer timing, exported launch, or visual qualification was performed.

## I08 — Native Metal, MoltenVK, OpenGL, and OS version

**Question.** Which rendering path should the Mac comparison measure on pinned Godot 4.7.2-stable?

**Verified facts.** Godot separates rendering method from driver: Compatibility uses OpenGL; Mobile and Forward+ use RenderingDevice with Metal or Vulkan. Godot 4.7 supports native Metal on Apple Silicon and Vulkan through MoltenVK. Its guide says Metal is generally faster in CPU-bound cases; that is not an OpenRC result. Godot uses Metal 4 on macOS 26+ and Metal 3 earlier. The documented Apple Silicon export floor is macOS 13. OpenRC selects Compatibility in [project.godot](../../../../app/project.godot); its [graphics launcher](../../../../tools/graphics/launch.py) exposes profiles, not backend overrides. ([Godot renderer architecture](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html), [Godot requirements](https://docs.godotengine.org/en/4.7/about/system_requirements.html), [dated source review](../../apple-silicon-performance-2026-10-24.md))

**Inference and plan change.** Keep Compatibility/OpenGL as control; compare Mobile/Metal and Forward+/Metal separately. Use Vulkan/MoltenVK only as a same-method driver control. Record requested and effective method, driver, OS build, and fallback. A renderer change must not be presented as a Metal-only comparison.

**Test and limits.** On the named M1 at 1920×1080, hold project, scene, OS, pacing, and settings constant; capture full-session frame distributions. Qualify macOS 13+ and 26+ separately if both are targets. No speed ranking is measured, and the physical M1 GPU-core/RAM SKU remains unknown.

## I09 — Mobile versus Forward+ feature coverage

**Question.** Can Mobile/Metal serve as the M1 profile while preserving the visual contract?

**Verified facts.** Godot describes Mobile as a lower-base-cost renderer for simple scenes with most features; Forward+ has all features and receives new features first. Both can use Metal. Mobile lacks SSAO, TAA, FSR2 and Forward+ directional PCSS. OpenRC High explicitly adds SSAO, solar-angle PCSS, a four-cascade 8192-pixel directional-shadow atlas and sky reflections. Standard remains Compatibility. ([Godot 4.7 renderer comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html), [OpenRC High profile](../../../../tools/graphics/README.md))

**Inference and plan change.** Keep Mobile/Metal as the first efficiency candidate, but compare it first with Forward+/Metal on a declared common feature set. Treat High as a separate quality profile; record every unavailable or changed effect as a product choice before timing. Mobile’s lower base cost is a hypothesis, not a workload guarantee.

**Test.** At 1080p, compare the same aircraft, field, camera, hour, shadows, lake/reflection view, smoke and moving approach. Inspect sky/exposure, shadow softness, terrain and aircraft readability. Include requested/effective renderer and effect settings in receipts; qualify 1440p/4K after 1080p and 720p last.

**Limits.** Feature tables do not establish parity of OpenRC shaders or assets. If an M1 release requires High’s SSAO or PCSS, Mobile cannot claim equivalent output without a reviewed substitute. No M1 comparison ran.

## I10 — MetalFX support in Godot 4.7.2 and M1–M5

**Question.** Does the pinned engine run MetalFX spatial or temporal reconstruction on Apple GPUs?

**Verified facts.** Godot 4.7.2 documents both modes as Metal-driver-only. Tagged source gates capability probes at macOS 13 and calls `SpatialScalerDescriptor::supportsDevice(device)`; temporal is queried only when `METAL_MFXTEMPORAL_ENABLED`, otherwise disabled. The temporal minimum input scale is a device limit (queried on macOS 14+). In pinned source, `renderer_scene_render_rd.cpp` routes spatial through shared RenderingDevice post-processing; Mobile leaves its subpass shortcut when scaling, then calls that shared path. `render_forward_clustered.cpp` implements temporal. Spatial is the shared RD candidate for Mobile/Forward+; temporal is Forward+-only. Apple lists M1–M5 as GPU families Apple7–Apple10; minimum families are Apple3 for spatial and Apple7 for temporal. CPU model is identity metadata, not Godot’s eligibility predicate: OS availability and actual `MTLDevice` checks decide. ([Godot Viewport API](https://docs.godotengine.org/en/4.7/classes/class_viewport.html), [pinned Metal device checks](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/metal/metal_device_properties.cpp#L1264-L1285), [shared spatial path](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/renderer_scene_render_rd.cpp#L2889-L2905), [Mobile scaling path](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp#L880-L916), [Forward+ temporal path](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L2248-L2273), [Apple Metal feature table](https://developer.apple.com/metal/capabilities/))

**Inference and plan change.** Replace enum-presence checks in DT-MAC-07 with a method/device/OS/build capability matrix. Record CPU/SoC identity, OS build, effective renderer/driver, both feature flags, temporal minimum scale and Native fallback. OpenRC’s [reconstruction adapter](../../../../app/render/reconstruction.gd) does not expose MetalFX today.

**Test and limits.** After native 1080p parity, compare Native with spatial at 0.85 scale, then temporal only when reported. Inspect propeller, distant aircraft, foliage, smoke, camera cuts and history reset. Apple family thresholds are not per-device proof or OpenRC benchmarks; all M1–M5 generations still need native runs.

## I11 — Pipeline compilation stutter and caches

**Question.** Which first-use hitches could be mistaken for steady-state renderer cost?

**Verified facts.** Godot’s 4.7 guide says Mobile and Forward+ use ubershaders and pipeline precompilation; Compatibility/OpenGL needs legacy preloading. Pipeline state includes more than shader source. Driver caches are local and can be invalidated by driver updates. Precompilation only covers witnessed resources/features; runtime-loaded meshes, materials or MSAA changes may compile later. The debugger exposes pipeline count and trigger monitors. ([Godot pipeline compilation guide](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html))

**Inference and plan change.** Split import-cache, process-cold, first-use pipeline work and warm steady state in DT-MAC-03/05. Do not combine a cold Compatibility run with warm Mobile data or call a fresh import a cold driver cache. Use existing pipeline monitors before adding a warmup path.

**Test.** On one M1/OS, capture first launch, field entry and first smoke-heavy pass, then repeat the same path warm. Label process and driver state; treat OS/driver updates as separate cache invalidation conditions.

**Limits.** The docs and repository do not identify a safe macOS operation to clear only this game’s Metal pipeline cache. Do not delete system caches to manufacture a cold result. Target-Mac behavior remains unknown.

## I12 — Tile bandwidth, MSAA, shadows, and reflections

**Question.** Which OpenRC passes may pressure Apple GPU bandwidth or transient memory?

**Verified facts.** Apple Silicon GPUs use tile-based deferred rendering. Tile memory is fast; transient depth/MSAA attachments can avoid system-memory traffic when they need not survive the pass. Apple documents efficient MSAA. Godot 4.7.2 `RenderSceneBuffersRD` allocates multisampled color/depth buffers and retains a TODO to mark suitable attachments transient. OpenRC sets 4× MSAA; High adds SSAO, a large cascaded shadow atlas and sky reflections. These identify costs to measure, not proof of a Metal bottleneck. ([Apple tile-based GPU guidance](https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering), [Apple storage modes](https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus), [pinned Godot render buffers](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp), [OpenRC MSAA](../../../../app/project.godot), [High profile](../../../../tools/graphics/README.md))

**Inference and plan change.** Keep 4× MSAA as measured baseline; test 2× and off separately. Change one shadow-atlas/cascade or reflection update/resolution setting per candidate. Include world transitions because Forward+ has a known reflection-probe lifetime issue.

**Test and limits.** Measure 1080p first using actual drawable pixels, GPU capture/counters if available, render-buffer memory, frame distributions and visual checks during fast approach. Godot’s TODO does not prove M1 attachment placement. Tile architecture predicts neither a speedup nor a slowdown; no M1 pass attribution exists.

## I13 — ASTC/BC texture formats and Godot imports

**Question.** Can texture imports reduce unified-memory traffic, and which format does the Mac actually use?

**Verified facts.** Godot 4.7 says VRAM compression often cuts GPU texture memory 4–6× and bandwidth. Format depends on import settings and target: high-quality uses BPTC on desktop and ASTC on mobile; standard uses S3TC on desktop and ETC2 on mobile/web. Apple lists ASTC from Apple2 and BC at Apple9, with selected Apple7/8 iPadOS exceptions. That is not a Mac M1/M2 verdict: Godot 4.7.2 queries `supportsBCTextureCompression()` on the actual device, and its OS/driver result should decide. OpenRC sets `textures/vram_compression/import_etc2_astc=true`; this flag does not prove the Mac import/runtime format. ([Godot image import guide](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html), [Apple Metal table](https://developer.apple.com/metal/capabilities/), [pinned Godot BC query](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/metal/metal_device_properties.cpp), [project setting](../../../../app/project.godot))

**Inference and plan change.** Make actual imported/runtime formats and resident texture memory evidence for DT-MAC-06; retain the project-wide override until that evidence exists. Review color, normal, ORM and cutout masks separately because compression can damage markings or foliage edges. Keep source assets and the import pipeline intact.

**Test.** Reimport a disposable project copy on the named M1, inspect representative textures in a Metal capture, compare edges/color, then measure memory pressure in a 1080p field session. Higher output resolutions follow; 720p last.

**Limits.** Family tables do not prove per-device support; OS/driver can expose other formats. Disk size and RSS do not identify GPU format or unified-memory benefit.

## I14 — Vegetation, smoke, MultiMesh, and open-terrain culling

**Question.** Should M1 work reduce instance count, transparency overdraw or visibility range first?

**Verified facts.** OpenRC near grass uses opaque triangle clumps; tree cards are alpha-scissored three-plane cards. Flight smoke uses `GPUParticles3D` alpha-blended billboards and distance-based emission LOD. Godot says MultiMesh cuts submission overhead but culls a whole batch by one AABB, so spread-out batches can draw hidden instances. Alpha scissor can be cheaper for cutouts; smoke needs blending. Occlusion value depends on blockers, costs CPU and is usually lower in open views. ([OpenRC grass](../../../../app/render/near_grass.gd), [tree cards](../../../../app/render/tree_assets.gd), [smoke LOD](../../../../app/render/smoke/profile_smoke.gd), [Godot MultiMesh](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html), [transparency limits](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_rendering_limitations.html), [occlusion guide](https://docs.godotengine.org/en/4.7/tutorials/3d/occlusion_culling.html))

**Inference and plan change.** Profile existing representations first. If submission dominates, test spatially bounded MultiMesh groups and existing LOD ranges. If smoke fill dominates, test screen coverage or particle distance/amount while preserving airflow cues; keep smoke blended. Require counters before adding open-terrain occlusion.

**Test.** At 1080p, compare the same low approach, treeline and smoke-heavy circuit with fixed population, wind and camera. Record CPU/GPU frame distributions, transparent-pass cost, cull counts and aircraft/landing-cue readability. Higher resolutions follow; 720p last.

**Limits.** Existing LOD logic has not been qualified on M1. MultiMesh draw-call savings may enlarge visible batches and GPU work. No vegetation or smoke bottleneck has been measured on Apple hardware.
