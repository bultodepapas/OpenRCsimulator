# Community cases: ray tracing and renderer integration

2026-11-15 · Source research, not native execution. Application baseline: `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`; official Godot: `cafc17a192acf67903910a68aeb3c076c0907a4b`. These five cases refine [the existing RT design](../10-reflex-and-ray-integration-design.md#2-direct-sun-ray-tracing-real-seams-and-limits). They do not add five projects or change the owning VQ-04b/GDU/DT gates.

First-person observations are attributed to their authors. A merged fix, a source contract, a proposed test and an OpenRC measurement are different evidence. No linked reproduction archive or third-party binary was executed in this round. Unknown hardware, workload or sampling details stay unknown.

| Case | Practical lesson | Disposition for OpenRC |
| --- | --- | --- |
| C-RT-01 | A ray shader can receive incorrect parameters on one driver while another appears to work. | Reuse a differential push-constant/UBO check; the upstream fix is already in the official pin. |
| C-RT-02 | Attractive static-scene RT timings can exclude the animated geometry that matters in flight. | Separate rigid transforms from vertex deformation and admit only complete scene coverage. |
| C-RT-03 | A suspected memory problem can actually be excessive GPU work per submission. | Bound build/dispatch work; retain the corrected engine and normal timeout policy. |
| C-RT-04 | Precision workarounds and repeated allocation can conceal the actual problem. | Reuse a reviewed numerical reference and existing attribution tools, with the correct API scope. |
| C-RT-05 | A plausible texture-sharing fix can remain unresolved after several replies. | Require viewport, generation, format, extent and ordering evidence before binding a borrowed buffer. |

## C-RT-01 — NVIDIA push constants failed while an AMD run appeared correct

### Report and observed resolution

[Godot issue #121285](https://github.com/godotengine/godot/issues/121285), opened 2026-07-12, reports a black ray-generation result on Godot 4.7 stable, Windows 11, RTX 4070 Ti, driver `32.0.15.9621`. The same tint supplied through a uniform buffer produced the expected green triangle. A contributor reported success with both paths on Fedora/RADV/RX 9070 XT at `2c089e9bf`, while the original author still reproduced the failure at that same engine commit. These are different OS/driver/device observations, not a controlled vendor ranking. A maintainer later reproduced the problem on Linux/NVIDIA and reported correct output with [PR #122051](https://github.com/godotengine/godot/issues/121285#issuecomment-5168442343).

[PR #122051](https://github.com/godotengine/godot/pull/122051) merged on 2026-08-04 as `f3b471af78baf59144922f7d48416574ce49b19b`, closing this and other RT defects. The inspected [pinned shader reflection](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_shader_container.cpp#L306) uses the ray-stage bit flags. GitHub's commit comparison confirms that the merge is an ancestor of the official pin. **This is a historical defect already addressed in that pin**, not a new OpenRC patch request.

### Application and smallest useful check

Add one parameter-transport case to **RT-01's admitted native triangle fixture**, not a separate RT framework. Dispatch the same known triangle with a distinctive tint through push constants and then through a UBO. Check hit and background pixels, then change the tint and require a corresponding result. A constant green output must fail the control. Inspect validation errors as well as the process result. This protects against a custom engine or shader-cache mismatch when changing build families; it does not prove the separate query-only/SBT route works.

For the first available qualified device, run this as part of the existing two-day feasibility decision. A later actual AMD or NVIDIA package row repeats the relevant check under M5; no extra hardware matrix is required before beginning M1. Preserve exact shader, engine and driver identities in the existing receipt. Avoid adding a permanent UBO workaround or modifying reflection code simply because an old issue exists. The NVIDIA fork and Apple custom builds require their own prepared-source verification; an official-pin ancestor check does not cover them.

## C-RT-02 — Reported fast RT did not solve deforming geometry

### Report, limits and corroboration

In [proposal #15180](https://github.com/godotengine/godot-proposals/issues/15180), opened 2026-07-12 and still open when checked, a developer using Godot 4.7/GDExtension reports approximately **0.8 ms** for an experimental RT lighting stack versus **1.85 ms** for cascaded shadows in one procedural scene. The same report says that full BLAS rebuilds and dependent TLAS rebuilds made vertex animation costly enough to restrict RT shadows to static objects. Another developer reports trouble with animated actors; a [follow-up](https://github.com/godotengine/godot-proposals/issues/15180#issuecomment-4978162189) distinguishes rigid transforms from changing vertex positions. The timing paragraph does not supply a complete hardware, resolution, scene, warm-up or distribution record. Hardware from a separate bug report cannot fill those gaps. No speedup is transferred to OpenRC.

The exact [RenderingDevice implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp#L495) invalidates dependent TLAS objects when rebuilding a BLAS. The [pinned Vulkan driver](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.cpp) uses build mode in this path; creation flags do not expose a usable refit or compaction operation by themselves. The proposal is useful evidence of a real integration boundary, not an accepted implementation specification. Apple separately [documents refit and its quality tradeoff](https://developer.apple.com/documentation/metal/mtlaccelerationstructurecommandencoder/refit(sourceaccelerationstructure:descriptor:destinationaccelerationstructure:scratchbuffer:scratchbufferoffset:)); that API does not automatically exist in Godot's Metal bridge.

### Application and smallest useful check

Within **RT-03/04**, label each caster by its actual update requirement. A rigid aircraft body or hinge can retain geometry while updating its instance transform; [vegetation wind](../../../../app/scenery/motion.gdshader) changes vertices. [MultiMesh vegetation](../../../../app/scenery/imported_vegetation.gd) also requires the actual instance and material coverage. Treating every moving object as a BLAS rebuild is wasteful; treating every animated object as a rigid instance is incorrect.

The controlled fixture needs one rigid transform change and one deliberate vertex change. Verify hit identity/position and generation after each. For the vertex case, either use a proven admitted update/rebuild path or produce an explicit unsupported-scene result and retain raster. A stale but visually plausible shadow is failure. Add one off-camera caster so camera visibility cannot silently become caster eligibility.

The first opaque fixture can exclude vegetation with a visible scope statement. Normal-flight promotion still requires complete relevant coverage as [10 specifies](../10-reflex-and-ray-integration-design.md#geometry-materials-and-lifetimes). **Do not begin a general BLAS-refit engine project because this proposal exists.** Use the two-day feasibility outcome to choose a useful bounded fixture or defer. Estimate the actual build and trace work together; a low trace time alone is insufficient.

## C-RT-03 — A LightmapGI timeout was initially confused with memory pressure

### Report and resolution

[Godot issue #101391](https://github.com/godotengine/godot/issues/101391), opened 2025-01-10, reports baking crashes after transparency support. Reports include Windows/GTX 1070 and Windows/RTX 3080; a Linux/RTX 4090 run did not reproduce the crash and raised a VRAM hypothesis. Smaller scenes and region settings did not consistently solve it. A maintainer reproduced the direct-light crash and diagnosed Windows TDR; this is a maintainer diagnosis, not this audit's measured timeout. The first [PR artifact](https://github.com/godotengine/godot/pull/102257#issuecomment-2628405339) stopped the crash but introduced a shadowmask regression. After revision, [both reporters confirmed working shadows](https://github.com/godotengine/godot/pull/102257#issuecomment-2628685760). A separate pre-existing tunnel issue remained. The intermediate result demonstrates why completion and image correctness must be checked separately.

[PR #102257](https://github.com/godotengine/godot/pull/102257) splits direct-light baking across regions/submissions. It merged on 2025-02-03 as `3d25533d0ce43f7bf37f3cde81d2bab515ad61e7`; comparison confirms ancestry in the official OpenRC pin. Its explanation identifies the growth in work from antialiasing and transparency. The patch uses a separate baking device with submission and synchronization. **This is an offline lightmapper case, not a hardware-RT gameplay benchmark or a reproduced OpenRC failure.**

### Application and smallest useful check

Carry the diagnostic method into **RT-05/06**, not the baking synchronization code. In an admitted optional effect, predeclare bounded scene admission and build work, cap per-frame work at the existing effect/full-frame budget, and retain raster while required data is incomplete. Test an over-budget scene or intentionally failed allocation through controlled admission/failure injection; do not intentionally hang a GPU. Classify the observed failure as validation, memory/allocation, timeout/device loss, or image correctness only when evidence supports that classification.

If native evidence shows unexpectedly long setup work, use one existing profiler capture under the one-day attribution review limit. First distinguish allocation, AS build and query/lighting; do not immediately add an allocator, denoiser or monitoring service. Retain a useful error reason in the existing incident bundle.

Do not ask players to alter Windows timeout settings, disable driver recovery or use per-frame `sync()` to make the effect appear stable. Reuse engine-managed asynchronous dependencies and verified retirement from [the lifetime design](../10-reflex-and-ray-integration-design.md#proposed-render-thread-ownership-and-failure-contract). The old upstream fix does not need another local patch. Its baking region size is not a correct gameplay dispatch budget.

## C-RT-04 — Self-intersection, attribution and an external allocation improvement

### What the discussion actually established

In a [February 2024 NVIDIA developer thread](https://forums.developer.nvidia.com/t/how-do-i-avoiding-hitting-the-same-triangle-when-calling-tracing-another-ray/281669), an OptiX user reports self-intersection and asymmetric forward/backward traces. After discussion, the user identifies another bug behind the sensitivity. A later performance investigation leads to a reported roughly **3× improvement** after addressing repeated allocation. The final hardware description is “RTX 6000,” without a precise generation, OS or driver; the thread also changes triangle counts during its investigation. The timings are not a frozen reproducible benchmark. NVIDIA's replies distinguish broad timing attribution from kernel analysis and warn that unnecessary any-hit work can have a cost. This is a useful first-person outcome, not an OpenRC estimate or a reason to add CUDA to Godot.

The independent [NVIDIA numerical explanation](https://developer.nvidia.com/blog/solving-self-intersection-artifacts-in-directx-raytracing/) describes error-bounded origin offsets and the role of coordinate magnitude and transforms. Its primary [GLSL reference at `5a5c45b`](https://github.com/NVIDIA/self-intersection-avoidance/blob/5a5c45bc61aca5d095032860058481e0497350e0/SelfIntersectionAvoidance.glsl) and [BSD-3-Clause license](https://github.com/NVIDIA/self-intersection-avoidance/blob/5a5c45bc61aca5d095032860058481e0497350e0/LICENSE) are available for reuse. The sample takes triangle vertices, barycentrics and transforms; it is not a generic replacement for bias on a depth-reconstructed receiver. Driver/API numerical assumptions still require validation on the actual target.

### Application and smallest useful check

Extend **RT-02/03** with two related controls inside the same fixture: a receiver that must not shadow itself, and a nearby independent thin occluder that must remain visible to the ray. Exercise representative small geometry, nonuniform transforms and a declared translated-scene stress case. Compare known geometric hit/miss decisions and rendered shadow/contact behavior. A larger arbitrary epsilon that removes acne by erasing the nearby occluder fails.

The scene producer must use the same [NED-to-render and CG transform boundary](../../../../app/render/frames.gd) as visible geometry. Rendering precision work never changes the 240 Hz float64 physics state. If the chosen light integration knows the hit triangle, evaluate the existing numerical reference with its license and assumptions. If it only has depth/normal data, first derive and test that reconstruction's error bound; do not invent unavailable barycentrics or claim the reference applies unchanged. A camera-relative RT scene is a possible later presentation-only change, not a prerequisite for the first fixture.

Inspect allocation reuse only if the named native capture identifies churn. Keep existing memory and full-frame limits, including in-flight resources. Do not copy `CUDA_LAUNCH_BLOCKING`, OptiX allocation code, generic rays-per-second thresholds or a new profiler into the simulator. The external 3× result justifies a concrete attribution question, not a promised improvement.

## C-RT-05 — Cross-viewport texture sharing remained unresolved

### Report and rejected advice

The [Godot forum thread of 2026-08-14–15](https://forum.godotengine.org/t/the-proper-way-to-transmit-a-texture-between-compositor-effects/143037) concerns 4.7.1 and an auxiliary viewport feeding another compositor. OS, GPU and driver are unspecified. The author reports a black color result while depth works, especially after adding multiple editor viewports and scene switching. A suggested `texture_copy` failed because the source lacked the required copy usage. Guards against empty handles did not solve the black image. The retrieved thread ends with further diagnosis, not a demonstrated fix or verified resize root cause. Do not label the borrowed-RID explanation as its established cause.

The exact pin independently supplies the engineering contract: [RenderData](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/RenderData.xml) is scoped to one viewport render; [buffer reconfiguration/cleanup](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp#L128) frees named textures. [Color/depth usage bits](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp#L796) vary by MSAA, resolve and storage path; ordinary non-MSAA color does not universally have copy-from permission. A live handle alone proves neither provenance nor producer completion.

### Application and smallest useful check

For **RT-05 and the M2 transition finalist**, validate each resource against actual viewport/render-target identity, generation, view index, internal/output extent, format and permitted access. Acquire borrowed scene resources inside the relevant render callback. An owned intermediate still needs a producer/consumer ordering contract and a lifetime that survives in-flight use; owning it does not establish freshness. Prefer one render sequence for the first fixture instead of adding an auxiliary camera as an assumed shortcut.

Inject a donor-generation mismatch and an absent donor result into the proposed fixture; neither may submit stale bindings or partially darken the player viewport. Resize output, change the admitted internal scale, and replace the world; either the matching generation produces a valid result or the complete raster path remains. Zero dimensions skip dispatch. A shader must bound invocations by the actual bound extents, including any declared input-to-output mapping.

Do not fix unknown usage by toggling flags on a borrowed engine texture, retain `RenderData` after its callback, or traverse/mutate the scene tree from the render thread because a forum reply shows how to obtain its pointer. Use detached producer snapshots and the existing render-thread lifetime design. A copy/compute intermediate is justified only by the selected algorithm and measured cost, not by the failed suggestion in this thread.

## Integration and evidence boundary

These cases add discriminating controls to the existing **RT-01–06** fixture and M2 finalist; they do not require new production probes. The existing [shadow-energy fixture](../../../../tools/graphics/test_shadow_energy.gd) provides a useful native image/report pattern, but its 512 × 256 scene and current raster-only assertions are not an existing ray test or 1080p performance qualification. Extend only the relevant owning fixture after a real implementation exists; exact runnable commands then belong in its README.

Reuse the [test playbook](../11-test-and-execution-playbook.md), [M0–M5 sequence](../12-senior-developer-handoff.md#proposed-reviewable-change-sequence) and [community execution plan](../13-community-driven-execution-plan.md). No observed community result changes the five-day M0 cap, the two-day RT feasibility decision, the two-week visible-fixture checkpoint, or normal-flight coverage requirements. Sources and software/document checks are recorded in the new continuation receipt; native execution and all proposed fixture outcomes remain unperformed.
