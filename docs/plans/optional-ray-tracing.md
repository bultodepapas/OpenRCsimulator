# Optional ray tracing: implementation and qualification plan

**Status:** proposed implementation contract; no production RT feature is implemented or qualified by this document.  
**Research date:** 19 November 2026, America/Bogota.  
**Research revision:** strengthened by [twenty follow-up investigations](../research/ray-tracing/2026-11-19-twenty-investigations.md), completed as ten broad investigations followed by ten targeted investigations selected from their findings. Source findings and proposed tests are distinguished throughout; no GPU result is inferred from this revision.  
**Application baseline:** `bultodepapas/OpenRCsimulator`, `main` at `e0a733937e255bacfe95ff09db0fb3838697239f`, application version `0.2.9`.  
**Official engine baseline:** Godot `4.8.beta2.official.cafc17a19`, full source commit `cafc17a192acf67903910a68aeb3c076c0907a4b`.  
**Plan branch:** `ray-tracing`. Git does not permit the requested space-containing name `ray tracing`.  
**Owner:** VQ; coordinated owners: GDU/DT for engine and packages, VQ-04b for shadows, FW/TOD/SUN for lighting, L/LU/SC for scenery, CAM for displayed transforms/history, UI for preferences, and vehicle presentation owners.  
**Step prefix:** `VQ-RT-00` through `VQ-RT-19`. These are proposed VQ subtrack steps, not replacements for existing track IDs.  
**Authoritative scope:** this document owns the new RT execution sequence. Existing [shadow](shadows.md), [advanced graphics](advanced-graphics.md), [Apple MetalFX](apple-metalfx.md), [Apple performance](apple-silicon-performance.md), [architecture](../STACK.md), and [verification](../tools/shared.md#verification-scope) contracts retain their existing ownership.

**Navigation:** [Decisions and scope](#1-outcome-and-instructions-to-the-executing-agent) · [Research findings](#2-research-findings-that-determine-the-design) · [Architecture](#3-architecture-and-ownership-contracts) · [Acceptance limits](#4-performance-and-quality-gates) · [Evidence/tests](#5-evidence-tests-and-measurement-discipline) · [Commands](#6-implementation-command-contract) · [20 phases](#7-phases-and-subphases) · [Dependencies](#8-dependency-order-parallel-work-and-stopping-boundaries) · [Completion checklist](#9-final-acceptance-and-agent-handoff) · [Deferred scope](#10-explicitly-deferred-effects-and-optimizations) · [All branches](#appendix-a--complete-github-branch-inventory) · [Repository sources](#appendix-b--repository-evidence-and-source-provenance) · [External sources](#appendix-c--official-documentation-guides-and-firsthand-engineering-discussions).

## 1. Outcome and instructions to the executing agent

Implement an **optional hybrid ray-traced sun-shadow feature** while preserving the existing raster renderer, flight behavior, settings, and recovery paths. Rasterization continues to produce primary visibility, materials, sky, transparency and UI. Replace only the selected sun's geometric visibility on qualified receivers. First prove deterministic hard visibility; then add finite-sun soft shadows and their denoising. The first player-facing release requires a measurable benefit during an ordinary fixed-wing flight, not merely a successful triangle query or a showcase screenshot.

This is a quality feature with a cost budget. Existing native PCSS already produces soft shadows. Do not promise that RT improves frame rate, fixes unrelated stutter, or makes every scene more realistic.

### 1.1 Execution rules

1. Execute the phase dependency order in section 7. Finish each subphase's specified proof before treating its output as an input to the next dependent subphase. Independent source-only work may proceed in parallel; GPU measurements may not share a host with another benchmark.
2. At task start, compare the working revision with this baseline. Re-read changed integration files and the current repository rules. Record a concise drift table; do not silently apply old line numbers or cherry-pick a whole research branch.
3. All new paths, interfaces and commands explicitly labeled **proposed** below are work to implement. They do not exist merely because this plan names them. Existing commands must be checked against their owning README before execution.
4. Preserve `app/sim/`, `app/physics/`, the 240 Hz fixed step, float64 state, RK4 order, input sampling, aircraft data, collision queries and replay semantics. Rendering consumes already displayed transforms. Do not change these systems to recover an RT budget.
5. Never promote `source-reviewed`, `compiled`, `submitted`, `GPU-completed`, `image-correct`, `performance-qualified`, and `package-qualified` into one interchangeable status. Record each separately.
6. Keep the ordinary official build usable. Build custom editors, templates, imports, caches and player profiles in isolated, named locations using existing intake/packaging patterns. Do not point the production import cache at another engine.
7. Keep RT off by default, including Automatic graphics and Restore graphics defaults. A saved request is distinct from effective execution. Unsupported or failed requests use the existing raster result and retain the user's saved request.
8. If a prerequisite fails, repair that prerequisite within its phase. After two materially different failed approaches to the same gate, write the counterexample and a bounded follow-up; leave that capability blocked and continue independent work. Do not replace the renderer, adopt a new engine fork, change SDKs, or lower acceptance thresholds to escape a failed gate.
9. A blocked hardware row is not a pass. Complete available source, unit, image, package and other-device work; leave the unavailable row explicitly unqualified. Do not extrapolate from an RTX 3090, an M1 diagnostic, software Vulkan, or CI to an untested device.
10. Every implementation commit must name its phase/subphase, changed boundary, verification and unresolved gate. Stage only assigned paths. Do not import historical logs, engine binaries or unnecessary images into Git.
11. Core work is phases 00–15. Phases 16–18 extend the qualified matrix independently. Phase 19 closes the delivered matrix and remaining gates. The effects in section 10 are excluded from this execution unless separately commissioned.
12. This planning change adds documentation only. It does not authorize claims that the proposed code, tests, APIs, hardware support or performance results already exist.

### 1.2 Product contract

| Item | Required decision |
| --- | --- |
| First effect | One selected directional sun; hard and finite-disk soft geometric shadows. No RT point lights, GI, AO, reflections or full path tracing in the core scope. |
| Initial runtime | Fixed-wing flight, main viewport, Forward+/Vulkan, a separately built beta2-based RT candidate. Qualify Windows first. |
| Existing shadow controls | RT is an enhancement only while native sun shadows are effective under `shadow_technique=auto` or `native`. `projected` and `off` remain effective and suppress RT. Preserve the native range, fade, opacity, source veto and aircraft cue handoff. |
| User control | Proposed additive Boolean `ray_traced_sun_shadows`, default `false`. Existing `shadow_softness` resolves hard versus soft sampling; its automatic choice follows the effective shadow policy. Existing quality/range controls retain raster-fallback meaning. |
| Scope exclusions | Home, Workshop previews/trials, reflection/magnifier auxiliary viewports, XR/multiview, other vehicle activities, photographic/baked scenery and unsupported shader variants remain raster until individually admitted. No hidden RT work in an excluded viewport. |
| Fallback | Keep the original native shadow maps available. Replace native visibility only where all required caster and receiver contracts are satisfied. Uncertain coverage selects original native visibility. |
| Initial ray rate | Hard: one deterministic visibility ray per covered internal-render pixel. Soft: one independently sampled solar-disk visibility ray per covered internal-render pixel and temporal/spatial denoising. Full internal resolution first. |
| Denoiser | First implementation candidate: the MIT FidelityFX shadow denoiser, pinned and adapted to the verified engine resource contract. No mandatory NVIDIA SDK. A failed integration leaves Soft unqualified; it does not trigger an automatic switch to another denoiser. |
| Sampling ownership | Frame-indexed rendering-only sequence. Never consume a simulation/weather random generator or advance simulation time. |
| Reconstruction/latency | Native rendering is the first qualification control. FSR2/DLSS/FSR3/MetalFX combinations receive separate rows later. Keep DRS, Reflex mode and frame generation fixed during effect comparisons; frame generation is off in the initial qualification. |
| Disable behavior | No recurring RT scene scan, geometry extraction, AS build, trace, denoise, history allocation, RT-only guide pass or readback after safe retirement. Existing raster work remains. |
| Release support | Per tested OS, driver, GPU, renderer, engine/template pair and feature combination. A GPU name, vendor, API bit or successful allocation alone grants no product support. |

## 2. Research findings that determine the design

### 2.1 Repository and branch findings

The initial **50 remote branch heads** and the final refreshed **52-branch snapshot** were enumerated. Each received at least tip-commit/changed-path screening; directly relevant branches received document and source review. Appendix A records all final heads and the late delta. This is not a claim that every historical commit or unrelated aircraft file was semantically audited.

| Finding | Evidence and consequence |
| --- | --- |
| Current runtime has a recoverable renderer/settings architecture | `app/project.godot`, `app/render/high_graphics_profile.gd`, `app/app_state/renderer_preference.gd`, `renderer_guard.gd`, and `display_preferences.gd`. Standard defaults to Compatibility outside native Apple Silicon; native Apple Silicon uses Mobile/Metal; High is Forward+. Reuse these owners rather than introduce another launcher/preferences system. |
| Reconstruction already distinguishes request and provider state | `app/render/reconstruction.gd` and `metalfx_policy.gd` use capability queries and fallback receipts. Extend the same principle for RT, but do not equate upscaler availability with ray tracing or denoising. |
| Shadow ownership was repaired after the original audit | Current [shadow plan](shadows.md) records the native-to-planar aircraft handoff, hinge/rotor caster behavior, material classification, cloud toggle and atlas retirement. The branch audit is historical evidence, not a list of still-open source defects. |
| Native shadows are already relatively inexpensive in one measured scene | [Shadow closeout](../research/visual-quality-implementation/VQ-04b/shadow-audit-closure-2026-11-18/README.md) records approximately 0.5–0.7 ms additional GPU time for native shadows in the RTX 3090 High 1080p fixtures. These are fixture medians, not complete-flight p95 or universal costs. RT must justify its added work with a visible improvement. |
| Apple measurements need careful scope | The same closeout contains later M1 1080p rows despite older summary text saying Mac/Mobile were unmeasured. Use the dated rows and their limits. Overlapping Metal viewport GPU timings cannot be summed; the report uses wall/frame comparisons. These rows do not qualify a Retina panel at native resolution. |
| A substantial RT handoff exists only on a research branch | `audit/graphics-performance-technologies-2026-11-15@0ccfa7d…` contains the RT guides and two Vulkan prerequisite patches listed in Appendix B. Recorded evidence covers source-bound tests and two translation-unit builds, not a linked engine, GPU image, exported game or cross-vendor result. |
| The two Vulkan patches do not finish the engine prerequisites | They address AS device addresses/creation failure and TLAS reservation/dependency mutation. They do not settle query-only SBT behavior, zero-capacity policy, every device limit, synchronization, retirement or actual GPU execution. Patch 0001 also touches generic buffer allocation failure, requiring non-RT regression checks. |
| Apple has a separate experimental producer path | Main includes Metal patches `0005`, `0018`, `0021`, and `0027`. A bounded M1 hit/readback and a separate private opaque RT/denoiser experiment exist. Patch `0018` is a diagnostic capture with blocking work; `0027` is a closed-gate source draft. Neither is a qualified normal-flight implementation. |
| NVIDIA and AMD candidates are different engine products | [Native graphics guide](../../tools/graphics/native/README.md): NVIDIA fork `135dff3887a3d2ccf45cafbd9bdffa7b718e1e76` predates beta2 and has its own patches/templates. AMD SDK 2.4 is a separate upscaling candidate. Their DLSS, Reflex or FSR capability does not establish RT/Ray Reconstruction/Ray Regeneration support. |
| Other research adds concrete restrictions | Photo-scenery contracts prohibit recasting shadows already baked into photographs; SUN-10 separates cloud beam transmission from displayed cloud alpha; afterburner research treats the additive plume as non-casting; vehicle-selector research exposes Home preview/projector lifetime costs. These are reasons to preserve existing ownership and admit content explicitly. |

The [architecture contract](../STACK.md#boundaries-and-data-flow) and `app/render/frames.gd` map NED to rendering axes as `(east, -down, -north)`. Aircraft rendering also applies model/CG offsets. Trace the **actual rendered part transforms after interpolation and articulation**, not a fresh conversion of raw physical position.

### 2.2 Exact engine audit

The following were checked in source at the full official pin, not inferred from latest documentation:

| Pinned source | Observed behavior | Implementation consequence |
| --- | --- | --- |
| [`rendering_device.h`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.h) | Exposes `blas_create`, `tlas_create`, `blas_build`, `tlas_build`, RT pipeline/SBT APIs. No usable public refit/compaction operation was found in this inspected surface. | Budget builds. `ALLOW_UPDATE` and `ALLOW_COMPACTION` flags do not prove an update/compaction execution route. |
| [`rendering_device.cpp`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp) | `tlas_build` requires a nonzero hit-SBT range for a valid BLAS. The fresh instance-buffer path and validation/dependency ordering are the subjects of the branch patch. | Initial positive fixture uses a legitimate pipeline/SBT and both required capabilities. True query-only operation is a separately validated API repair, never a fabricated integer range. |
| [`rendering_device_driver_vulkan.cpp`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.cpp) | Requests `VK_KHR_ray_query`, queries and enables `rayQuery`, and reports query support together with AS support. BLAS/TLAS creation sets `BUILD_KHR`. | The older 4.7 feature-enable issue is not assumed to remain here. Verify the actual built binary nevertheless. Full builds and their scratch/lifetime costs remain in the initial budget. |
| [`render_forward_clustered.cpp`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp) | PRE_OPAQUE follows the optional depth prepass. Current opaque/motion-pass vectors are generated later. | A pre-opaque temporal shadow pass needs an explicit current-motion producer. `needs_motion_vectors` alone is insufficient. |
| [`scene_forward_clustered.glsl`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl) | Directional visibility passes through range/lightmap fade, contact-shadow handling and opacity before `light_compute` accumulates diffuse/specular. | Insert a qualified selected-sun visibility substitution at that boundary; retain surrounding policies. Explicitly exclude unproved lightmap/vertex-lighting/transmission variants. |

The existing bugfix patches must be re-read against this exact source and the chosen fork. A patch applying cleanly proves textual compatibility only.

### 2.3 External research decisions

Primary references and firsthand issue reports are indexed in Appendix C. The implementation decisions are:

- Use **Vulkan ray queries** for binary sun visibility. They execute within compute/graphics shaders and do not intrinsically require a ray-tracing pipeline/SBT; the latter is a limitation of the inspected Godot API path, not a Vulkan requirement. Enable the actual AS/query feature chain and respect the selected device's limits.
- Prefer the **FidelityFX shadow denoiser** for the first soft-shadow candidate. Its documented contract uses a 32-bit visibility mask for an 8×4 tile and at most one jittered ray per pixel. Implement its real signal conventions rather than feeding it an arbitrary grayscale image.
- Keep **NRD SIGMA** as a documented alternative, not a second parallel integration. Its occluder-distance/penumbra contract differs from binary visibility, and its NVIDIA RTX SDK license is not MIT. An arbitrary first hit is not an adequate closest-distance input. A change of denoiser requires an explicit design update and renewed input/license review.
- Do not use **DLSS Ray Reconstruction, FSR Ray Regeneration, or MetalFX temporal denoised scaling** as a generic shadow-mask filter. They have different radiance/guide/backend contracts; an installed upscaler does not satisfy them.
- On Apple, distinguish **Metal RT API support** from hardware acceleration. `supportsRaytracing` alone does not imply dedicated RT hardware; Apple family 9 introduced hardware-accelerated intersectors. M1 API experiments remain useful evidence without becoming a hardware-RT performance claim.
- Treat community forks and issue reports as implementation leads. Confirm consequential claims in the pinned source and an actual native fixture. Do not replace the pinned application engine with a complete path-tracing fork.

### 2.4 Follow-up research incorporated into this contract

The [twenty-investigation record](../research/ray-tracing/2026-11-19-twenty-investigations.md) preserves questions, primary sources, forum/Reddit leads, rejected claims and Round 2 selection. Read its decision table during 00.1; this plan remains the authoritative execution sequence. The accepted changes are concrete:

| Finding | Required consequence |
| --- | --- |
| A compositor flag or texture RID does not establish fresh guides; Forward+ layouts vary by pass | Force the actual RT guide producer, including without an Environment, and validate the proposed binding across disabled as well as active shader variants. |
| AS inputs use typed RD owners; scratch belongs to each AS; BLAS mutation invalidates dependent TLAS state | Use typed storage-capable geometry buffers, per-AS scratch first, retained generations and the explicit dependency matrix below. |
| Tree wind can differ per instance; Green and Club have different source populations | Build the field/deformation feasibility ledger before a complete effects pipeline. Do not infer shared deformed geometry from a mesh ID. |
| FidelityFX's stock preparation, formats, history reads and depth copy need adaptation | Implement the specified single-writer conversion, R32F depth conversion, validity/correspondence rules and concrete format set. |
| Static receiver motion does not encode a moving shadow | Apply independent moving-caster references to denoiser-only, reconstruction-only and combined paths. |
| Raster-depth error differs from a ray-hit error bound | Test unbiased intended geometry, actual represented geometry, gap preservation and native facing policies. |
| Metal diagnostics and provider/reset implementations have narrower contracts than their API names imply | Close the source-specific per-lane prerequisites in 3.9 before qualifying a combination. |
| Internally consistent package hashes and asynchronously polled times can still describe the wrong inputs | Verify the feature roster before receipts and join timing to immutable submitted-work identity. |

The 20 phases, 80 subphases, 15 test families and frozen acceptance limits remain. Early feasibility or variant tests may block a field/mode before expensive implementation; they do not permit weaker coverage, lower scene detail or a different renderer.

## 3. Architecture and ownership contracts

### 3.1 File map

| Existing owner/path | Required integration or preservation |
| --- | --- |
| `app/render/shadow_settings.gd` | Remains the sole owner of native directional quality/range/filter allocation and per-light receipts. Expose its effective policy to RT; preserve source veto, native enable and projected cue ownership. |
| `app/render/high_graphics_profile.gd` | Supplies actual High/Forward+ status and sun defaults. Do not add another global atlas writer. |
| `app/render/world/world.gd`, `atmosphere.gd`, `time_of_day_lighting.gd` | Bind the actual world's sun, environment and lifetime. Keep weather/cloud/exposure independent. Handle retained-world restoration through the existing context boundary. |
| `app/main.gd`, `render/frames.gd`, aircraft presentation | Publish post-interpolation, post-hinge displayed transforms. Preserve model origins, scale, mirror transforms and existing node names. No 240 Hz RT callback. |
| `app/render/flight_cue_shadows.gd`, `vehicle_shadow_cue.gd`, `projected_shadow.gd` | Preserve the current native-to-projected transition. Do not render another near-aircraft ground shadow on top of RT. Preserve the explicit Vertical pilot aid. |
| `app/render/reconstruction.gd`, `metalfx_policy.gd` | Coordinate resize, jitter, internal resolution and temporal discontinuities. RT owns its own history; shared notifications do not conflate provider reset acknowledgements. |
| `app/app_state/display_preferences.gd`, `app_root.gd`, `ui/settings_screen.gd` | Add one validated optional preference, Keep/Revert integration, requested/effective information and Restore defaults behavior. Preserve direct-flight/Home preference separation. |
| `app/app_state/renderer_guard.gd`, `renderer_preference.gd` | Reuse persisted recovery conventions and renderer restart ownership. Add a separately scoped RT activation latch; process responsiveness alone is not proof that an RT GPU frame succeeded. |
| `app/render/render_timing_lease.gd`, `frame_diagnostics.gd`, `frame_samples.gd`, `auto_graphics_report.gd` | Reuse timing leases and validity classifications. Report actual RT activity, fallback and memory alongside the existing frame stream. Never treat cached timing polls as new samples. |
| `app/export.sh`, build-info/export addons, `tools/graphics/native/`, `tools/graphics/metalfx/` | Bind editor/template/patch/import/runtime identities; isolate products. Revalidate engine-sensitive presentation and companion admission. |

**Proposed new homes:**

| Path | Responsibility |
| --- | --- |
| `app/render/ray_tracing/settings.gd` | Pure normalization and effective-policy resolver; no RenderingDevice allocation. |
| `app/render/ray_tracing/capabilities.gd` | Method/ABI/backend capability adapter with typed unknown/unsupported reasons. |
| `app/render/ray_tracing/controller.gd` | World/viewport activation, request lifecycle and history notifications; render-only consumer. |
| `app/render/ray_tracing/scene_contract.gd` | Content admission metadata and invalidation generations, not a second scene graph or physics database. |
| `app/tests/test_rt_*.gd` | Pure policy, preferences, world/lifecycle and binding checks; native-only tests must not pass as headless skips. |
| `tools/graphics/raytracing/` | Reproducible engine intake/build/verify wrappers, ordered patch manifests, shader adapter and qualification reducers. Reuse existing helper logic where its contract fits. |
| `research/performance/raytracing/` | Native GPU fixtures, fixed camera/input cases and bounded experimental producers. |
| `docs/research/ray-tracing/<phase>/` | Small evidence manifests, decisions, metrics and justified captures. Raw builds/profiles remain outside Git. |

Renderer implementation belongs in a small **patched Godot renderer service**, with a dedicated `openrc_rt_sun` module/effect and driver adapters. GDScript coordinates product policy; it does not issue untracked native commands, create a second Vulkan device, read GPU geometry every frame, or duplicate the renderer's synchronization system. Keep the patch set separable from vendor upscalers. Preserve Compatibility and Mobile compilation paths.

### 3.2 Proposed engine ABI

The following names are **new interfaces to implement and document**, not current Godot methods. Use a versioned ABI, `openrc_rt_sun_v1`; reject a different version rather than guessing method compatibility.

| Interface | Contract |
| --- | --- |
| `RenderingServer.get_openrc_rt_sun_capabilities()` | Immutable typed facts for the active rendering device: ABI, driver/backend, enabled AS/query/pipeline features, limits, supported sampling/receiver modes, build identity and explicit reason codes. Unsupported official builds are detected through `has_method` before any call. |
| `viewport_set_openrc_rt_sun_request(viewport, sun, request)` | Copies a validated request and world generation to the render owner. It cannot mutate simulation or user preferences. A request is not an execution receipt. |
| `viewport_get_openrc_rt_sun_status(viewport)` | Bounded snapshot: requested/effective state, fallback reason, world/view/sun/history generations, submitted/completed frame IDs, admitted coverage, AS/trace/denoise counters and bytes. Unknown measurements remain unknown. |
| `viewport_reset_openrc_rt_sun_history(viewport, epoch, reason)` | Idempotent history invalidation scoped to the current viewport/world. A stale epoch cannot reset a replacement world or confirm a newer activation. |
| `viewport_release_openrc_rt_sun(viewport, epoch)` | Stops future RT submissions immediately and retires GPU resources after their last dependent completion. Repeated release and late callbacks are safe. |

Keep per-frame data inside native renderer structures. Do not serialize mesh arrays, large Dictionaries or JSON across this ABI every frame. Application-side event metadata must be copied before crossing to the rendering thread; no SceneTree traversal from a render callback.

### 3.3 Scene and acceleration-structure contract

1. A world has a monotonic `world_epoch`; a viewport has a separate lifetime/generation. Every geometry, instance, material, AS and history record carries its owning epoch. Object IDs alone are insufficient because IDs/resources may be reused.
2. Identify reusable geometry by mesh resource plus surface, topology/vertex/LOD generation, facing policy and caster-material variant. Share a BLAS across rigid instances of identical geometry. Deformed instances share only when their actual output geometry is proven equivalent at the used precision; source mesh/material equality is insufficient. Distinct hinge parts use the actual visible articulation transforms; rigid movement alone does not rebuild their vertex data.
3. Static geometry enters once during staged preparation. Maintain dirty sets for transforms, topology, deformation, material/alpha, visibility, LOD, instance count and layer/cull-mask changes. A normal RT-off flight never populates these sets through an RT-specific scene walk.
4. Use engine-owned scene/storage information and the same native caster rules as the selected sun. Static CPU mesh extraction is permitted once when no reusable AS-ready stream exists; charge it to loading. Ordinary raster vertex buffers must not be assumed to have AS-input/device-address usage. At this pin, BLAS vertices must belong to the RD vertex-buffer owner and indices to the index-buffer owner. For compute deformation, create a typed vertex buffer with `BUFFER_CREATION_AS_STORAGE_BIT` plus verified device-address/build-input usage, bind that RID as storage, end the compute list, then build. A generic storage-buffer RID is not a substitute.
5. Initial implementation uses real `blas_build`/`tlas_build` operations. Reuse unchanged BLAS; rebuild a TLAS when its instance state changes. Deformation requires a measured same-frame BLAS rebuild or native fallback. A future refit/compaction change needs its own API, barriers, quality/performance proof and receipt.
6. A camera-frustum list is not a sun-caster list. Include objects outside the view that can shadow visible receivers. First use a conservative **whole relevant sun region** admission decision: sweep receiver bounds through the registered scene bounds over the union of all directions in the finite solar disk, the full validated `t_max`, and receiver/origin uncertainty. A center-ray sweep alone is insufficient for Soft. Derive `t_max` from the complete registered caster bounds, not the camera far plane; invalidate coverage when direction, angular size, bounds or the view changes. A ray miss is never proof that omitted geometry cannot cast.
7. When capacity, memory, geometry support, readiness or coverage is uncertain, use native shadows for the whole affected viewport. Per-receiver optimization is allowed later only with a conservative coverage structure proving that unsupported casters cannot affect that receiver. Never truncate an instance list and call it complete.
8. Preserve visibility, `cast_shadow`, layers, light masks, front/back-face semantics, negative/nonuniform transforms, LOD transitions, material overrides and alpha mip/sampler behavior. The initial lightward query uses `CullBackFacingTrianglesKHR`; derive each group's instance-facing flip from native raster shadow culling, including the opposite light-view/query direction and actual baked/instance transforms, not a blanket determinant rule. Use instance cull-disable for double-sided groups. Initially group surfaces with uniform instance-facing policy; separate opaque/alpha candidate groups as required. Geometry-level opacity flags may differ, but instance cull-disable/flip cannot independently represent incompatible per-surface facing. Preserve non-opaque alpha candidates, share input storage where safe and charge added AS entries/builds. Test rays from both sides. Collision proxies require a silhouette-error qualification.
9. Match the rendered coordinate convention. Do not introduce a new origin-rebasing system or change physical coordinates. If the renderer's origin/projection changes, change both RT and raster inputs consistently and invalidate history.
10. Preserve all inputs used by in-flight builds/traces. Changing or freeing a mesh, material, texture, BLAS or TLAS schedules retirement; it cannot invalidate a previously submitted frame. Frame-count delays are not a substitute for the renderer's real completion/fence mechanism.

**Alpha lookup prerequisite:** ray-query candidate IDs and barycentrics must resolve through a generation-matched GPU table to the correct surface indices, vertex UVs, material parameters, texture and sampler. Use a bounded dense instance index, explicit surface/primitive ranges and material IDs; validate the 24-bit Vulkan instance custom-index limit before upload. Shared BLAS does not imply identical instance material overrides. The initial Vulkan adapter uses fixed-capacity, fully populated texture/sampler descriptor arrays with an immutable descriptor generation while in flight. Check and enable any required sampled-image non-uniform indexing feature and all per-stage/set limits; do not assume it follows from `rayQuery`, or require update-after-bind/partially-bound features unnecessarily. If the table or device cannot represent the field, select native fallback. Register/retire texture and material generations with the same completion ownership as geometry. Alpha evaluation in compute has no implicit raster derivatives: phase 08 must define a conservative ray-cone/footprint-to-LOD policy, test it against native shadow silhouettes at distance, and cover wrap, filtering, mip levels and cutoff/hash behavior. Do not select mip zero everywhere as an unmeasured shortcut.

#### 3.3.1 AS generation and synchronization rules

The source findings and exact paths are recorded in [I02/I12](../research/ray-tracing/2026-11-19-twenty-investigations.md#i12--typed-deformation-buffers-per-as-scratch-and-publication). The first implementation retains the pin's **one scratch allocation per AS**. Shared build/scratch arenas, refit and compaction are deferred optimizations.

For changed geometry, prepare an independently owned candidate generation: geometry inputs, BLAS, referencing TLAS/instances, material tables and scratch. Previously submitted frames retain their old generations. Publish a current mask only after candidate preparation and the required graph ordering succeed. If preparation fails or current coverage is incomplete, the current frame uses native visibility; keeping an old AS alive does not make it valid for changed current geometry. Reuse a generation only after all prior dependent GPU uses complete. This may use a bounded set of retained generations, but its simultaneous peak counts toward memory.

| Producer → consumer | Required stage/access relationship in the Vulkan adapter |
| --- | --- |
| Geometry upload → BLAS input | Transfer / transfer-write → AS-build / shader-read |
| Compute deformation → BLAS input | Compute-shader / shader-write → AS-build / shader-read |
| BLAS build → referencing TLAS build | AS-build / AS-write → AS-build / AS-read |
| Transferred TLAS instances → TLAS build | Transfer / transfer-write → AS-build / shader-read |
| TLAS build → compute query | AS-build / AS-write → compute-shader / AS-read |
| Query/filter image → lighting | Compute-shader / shader-write → fragment-shader / shader-read and the actual image-layout transition |

These are native relationships to verify in the RD graph, not invented public API methods. For the pin's host-coherent mapped TLAS instances, complete host writes before submission and reserve nonoverlapping in-flight ranges. Source inspection found global AS memory barriers; do not “repair” a presumed same-AS scratch defect merely because a separate buffer barrier is absent. Conversely, a TLAS descriptor's tracking alone is not proof that its indirectly referenced BLAS can be overwritten/freed. Any later shared scratch pool needs an explicit shared hazard and cross-frame proof; unordered concurrent builds may not alias scratch.

#### 3.3.2 Field and deformation feasibility gate

[I13](../research/ray-tracing/2026-11-19-twenty-investigations.md#i13--actual-clubgreen-workload-and-an-early-feasibility-ledger) finds one grass-plane field subtree in Green paradise and a 17-tree bundled source census in Club: 4 Fagus, 5 Pine, 2 Quercus, 2 Quercus 2 and 4 Maple. The source total is 116,962 triangles, with 94,798 across 13 potentially wind-enabled placements. These are source/test expectations, not live caster/LOD counts or a measured BVH budget. Inventory aircraft and other world-level casters in both fields.

After 05.1–05.4, create `scene-feasibility.json` before implementing the complete 06–11 path. For each frozen tape and relevant content generation, record actual native caster admission, source/surface/LOD/index format, displayed transform, active primitive count, alpha/facing policy and exact deformation key. The wind key includes topology, phase, actual basis/scale/local wind, displayed clock and plant parameters; reduce it to shared output coefficients only after proving equality. Normal-only flutter does not require a geometry rebuild.

Use the native build-size query for the actual geometry/flags/max-primitive configuration; record AS size, build scratch, required alignment and allocator commitment. Maintain a timeline of **unique simultaneously live allocations**, including old generations, rather than adding unrelated peaks or estimating BVH bytes from triangle counts. Add the proposed 3.6 image/guide layout before claiming a projected fit. Implement only the minimal extraction/deformation/build microfixture needed to measure this ledger; this early feasibility work does not activate the feature.

If known minimum allocations already exceed the budget, or measured geometry preparation makes the required active coverage unattainable, stop that field/mode before full integration. Uncertain sizes remain unresolved, not zero. Geometry partitioning is permitted only after counters identify a traversal/overlap problem and must preserve the represented triangles, alpha and native casting. Green can advance independently where its actual content qualifies; it never substitutes for Club qualification.

### 3.4 Content admission matrix

| Content | Required representation and initial rule |
| --- | --- |
| Terrain/runway/opaque buildings | Exact visible terrain geometry and native caster subset. Static shared BLAS; independent collision remains untouched. Include terrain elevation and receiving surfaces. |
| Aircraft body, gear and control surfaces | Real visible surfaces, per-part transforms and current articulation. Preserve CG/model offset. Use parked/blurred blade visibility exactly as native; do not turn a blur disc into an opaque disk. |
| Installed visual assemblies, if present in the qualifying revision | AE-27 is a separate proposed feature. When it becomes flight-eligible, register the actual installed parts atomically before observers cache targets; invalidate bounds/material/geometry generations and retire replaced resources after GPU completion. Test stock restoration, failed swaps, instance isolation, wheel/prop handles, root scale, tilted attachment frames and crash/reset. Do not implement attachments as part of RT or admit draft/import-only aircraft. |
| MultiMesh trees/people/scenery | All relevant instances, current transform, visible count, mesh/material/LOD generation and per-instance semantics. No assumption that the parent transform describes the whole batch. |
| Alpha scissor/hash foliage | Match actual texture, UV, sampler, threshold/coverage and native casting semantics. Opaque-only traversal is invalid. Candidate hits require the validated opacity decision. Hash/temporal coverage requires a separate native comparison. |
| Shader wind, flags, windsock, skinned meshes | Use the same displayed deformation and clock, through shared shader math or an explicit verified geometry producer. Rebuild costs count. If unsupported, the conservative sun-region gate selects native. Do not freeze animation to qualify RT. |
| Blended canopies, smoke, rain, additive flames/plumes | Follow native non-casting behavior unless that specific material is explicitly forced opaque or uses a different validated native caster route. Do not infer behavior solely from alpha being below one. |
| Water and custom `light()` shaders | Preserve current raster receiver until the selected-sun attenuation, cloud multiplier and guide semantics are proven. Water reflection/refraction remains unchanged. |
| Crash debris, broken parts and temporary meshes | Invalidate/remove old instances at the existing presentation lifecycle boundary. The first release may suspend RT during crash aftermath; it must never retain flying-aircraft ghosts or modify crash physics. |
| Photograph/baked shadowmask/vertex-lit variants | Raster fallback. Recasting baked illumination or replacing an unseparated light contribution is prohibited. |
| Other vehicles and auxiliary views | Raster fallback with zero RT allocation/submission until separately covered by a named matrix row. |

### 3.5 Lighting and receiver contract

At a qualified receiver, compute one raw geometric visibility value for the actual selected sun. Choose the RT value **or** the original native value, then execute the existing light fade, shadow opacity and qualified contact-shadow policy exactly once. Apply the resulting attenuation to both direct diffuse and direct specular from that sun. Preserve ambient/indirect light, emission, other lights, exposure and existing cloud transmission.

Do not assume directional-light index zero is the sun: lightning can create another directional light. Bind a verified light RID/identity and recheck its mapping each rendered frame. Use the native light/receiver masks.

The candidate shader insertion is immediately before the existing directional fade handling in `scene_forward_clustered.glsl`, after native geometric visibility is available. Leave the raster map computation in place for fallback. Start with opaque non-baked fragment lighting only. Test the custom-light path explicitly before admitting it. The existing screen-space contact term is preserved in the initial comparison, with its setting fixed; do not accidentally apply it twice.

A prepass-generated visibility texture is valid only for the matching visible surface and frame. Verify depth, normal, material/instance identity and sample coverage before substitution. With MSAA, mixed foreground/background samples must use native visibility for the entire ambiguous edge pixel until a sample-correct path is qualified. A single resolved shadow texel must not darken background through a one-pixel wing or leaf.

RT does not extend the native shadow range in V1. Keep the native fade and projected aircraft cue unchanged. A future range extension must jointly redesign cue ownership and prove no double shadow; it is excluded from the core plan.

#### 3.5.1 Concrete Forward+ insertion candidate

At the audited pin, sets 0/1/2/3 are scene/render-pass/transforms/material; the ordinary set-1 declarations use bindings 0–38. The **proposed first insertion is set 1, binding 39**, using the matching mono/array mask view and existing sampler. This is an inspected unused slot, not a compiled compatibility guarantee. Keep C++/GLSL implementation-UBO fields for enable and selected directional index explicitly aligned and checked. [I11](../research/ray-tracing/2026-11-19-twenty-investigations.md#i11--exact-forward-descriptor-and-selected-light-insertion) records the exact source paths.

1. Resolve the requested sun's render-light instance to the index actually emitted in the current viewport's light buffer. Reordering, a sky-only light, a skipped/disabled light or absence clears RT enable. A saved array index is invalid.
2. Reset RT enable on **every** environment/pass setup. Set it only for the admitted opaque and motion color passes after current guide/scene/mask validation. Shadow, depth, transparent, reflection and unqualified lightmap/transmission/vertex-lighting paths retain native behavior.
3. Bind an existing engine default texture of the correct reflected type on inactive paths. Do not leave a descriptor unbound because a shader branch is false, allocate an RT-only dummy while Off, or sample nonexistent layers of a one-layer default array.
4. Inspect reflection and the uniform-set cache key for normal, depth, SDFGI, motion, mono/multiview, separate-specular, uber and specialized variants. Update each set builder only as its real reflected layout requires. Compile/bind excluded variants with enable false so RT cannot break ordinary rendering.
5. Substitute geometric visibility before the existing fade/contact/opacity chain, then retain native light accumulation. Test the existing 8-bit shadow packing as part of the final Soft error budget. Store mask/validity/identity in explicitly compatible bindings; if a second existing guide binding cannot safely supply validation, reserve an additional unused binding with the same reflection proof and charge its resource cost. Do not compress identity into an unproved float encoding.

The added shared binding/branch may have a small ordinary-render cost even while RT allocates nothing. Measure it against the Off limits rather than declaring it free.

### 3.6 Hard and soft sampling

**Hard prototype:** one deterministic ray toward the sun center, no temporal accumulation. Terminating at the first accepted opaque/alpha-approved hit is sufficient for binary visibility. Record `t_min`, `t_max`, culling and origin-offset policy. Derive a scale-aware offset from geometric position/normal error; do not hide self-intersections with a large constant bias. Test millimeter-scale gear gaps, grazing surfaces and two-sided leaves.

**Soft mode:** sample the sun's angular disk once per covered pixel per real rendered frame. The existing `0.53°` full angular diameter corresponds to a `0.265°` half-angle, approximately `0.004625` radians. Read the effective angular size. The first product sampler is uniform in solid angle: for independent `u,v` in `[0,1)`, use `q=2*sin(alpha/2)^2`, `t=u*q`, `cos(theta)=1-t`, `sin(theta)=sqrt(t*(2-t))` and `phi=2*pi*v` in an orthonormal basis around the sun direction. This avoids cancellation in a naive `1-cos(alpha)`. Use full-precision angle arithmetic, handle `alpha=0` exactly as Hard, and verify the emitted direction distribution against independent float64 quadrature. Do not confuse diameter/radius or degrees/radians. Preserve direct-light energy/BRDF; only visibility sampling changes.

Use a pinned, licensed deterministic sample sequence with per-pixel decorrelation. The index advances with real RT submissions, not simulated ticks or generated frames. Reset/seed it reproducibly for qualification. Do not add a second ray per pixel to the FidelityFX packed binary-mask contract without a separately specified estimator and adapter change.

The denoiser input specification must include hit-mask bit order, tile edges, valid-pixel mask, the pinned algorithm's exact depth representation, decoded normals, motion direction/units, projection/jitter convention, inverse matrices and history identity. The FidelityFX shadow implementation reconstructs/reprojects from projection-space depth and provides an inverted-depth configuration; do not substitute linear view depth for that input. Preserve Godot's reversed-Z depth where the validated adapter supports it, select the matching inverted-depth option, and supply matching inverse/projection matrices. Keep any linear depth needed for a separate validation step in a separately named resource. Do not silently substitute normal-map normals for required geometric normals or vice versa.

**Pinned first adapter:** FidelityFX SDK `v1.1.4`, commit `c6efa6bf7f2027b3ec94f28578bb5965eabb9e55`, embedded Denoiser `1.3.0`. This pins the shadow kernels; it does not select or merge the project's separate AMD SDK 2.4 upscaling candidate. The existing native intake records archive SHA-256 `9a19e1f20bf269163f052186ed563209c5a1d0f7b1cf7e567e643dee6cc61179`; recheck that exact artifact on acquisition and record the consumed file hashes. Source references are in Appendix C. Phase 11 must address the following inspected-source details explicitly:

| Adapter boundary | Required implementation |
| --- | --- |
| Mask polarity/layout | External input bit `1` means an occluder hit; internal bit `1` means lit. Bit order is `(y % 4) * 8 + (x % 8)`. Use the single-writer preparation in 3.6.1, not an assumed 32-wide subgroup. |
| Depth and matrices | Supply device/NDC depth in `[0,1]`, the inverted-depth option for reversed-Z, and matching projection/inverse/reprojection matrices with verified packing and Y orientation. Sample the actual Godot depth aspect into current R32F projection depth; maintain previous R32F through same-format copies/ping-pong. Do not copy a D32/D24 depth-stencil image directly to the SDK's R32F color history. Record actual source format/MSAA resolve; conversion cannot recover lost precision. |
| Motion and normals | The inspected classifier uses `previous_uv = current_uv + velocity`; provide previous-minus-current normalized UV after its configured scale/Y convention. Normals and reconstructed positions/eye must share world-space coordinates. Verify jitter removal/application exactly once. |
| Moving receiver depth | Stock camera reprojection predicts prior depth from the current position; 2D object velocity alone does not correct depth motion. Add a current-sample previous-position/depth correspondence guide and adapt history rejection, or conservatively reject history for those receivers until proven. Test view-axis motion with zero XY velocity and depth-overlapping moving surfaces. Persistent rejection is acceptable only if the final quality/temporal gates still pass. |
| Explicit history reset | The public shadow dispatch lacks a reset parameter. Implement an adapter-owned epoch reset, first-frame/partial-invalid handling and initialized previous-depth/moment/history storage, or safe context recreation. Do not read uninitialized previous depth because a first-frame flag exists elsewhere. Retire old contexts/resources safely. |
| Receiver validity | The stock predicate checks depth range, not OpenRC material/coverage validity. Exclude invalid neighbors from moments and weights, normalize valid samples, and disable the homogeneous shortcut for neighborhoods containing invalid pixels. Use each receiver's own velocity, not the stock nearest-depth 2×2 neighbor's vector. Reject incompatible prior identity/depth/normal/epoch before history access. |
| Shader permutations/formats | Verify actual storage-image declarations versus bound formats, FP16 and subgroup requirements. The non-`FFX_HALF` filter helpers contain compile-only zero-return stubs, not a usable f32 fallback. The initial adapter requires the proven/enabled FP16 path; otherwise Soft is unavailable. A real f32 adapter needs a separate scoped design update and qualification. |
| Concrete format/dispatch review | Use the explicit first format set in 3.6.1 and matching shader declarations/views. Packed input uses 8×4 tiles; classification/filter entry points use 8×8 workgroups. Derive each dispatch from its shader, not the stock host's common 8×4 arithmetic. Verify odd extents, final tiles, barrier participation and bounds in emitted SPIR-V and on the physical device. |
| Filter transfer | The final filter includes a contrast remap. Visibility is consumed without sRGB/color-transfer encoding, but do not assume the result is an unbiased arithmetic mean. The independent visibility reference and fixed error gates judge the final output, including this remap. |

These are bounded adapter changes within phase 11. Do not discard the selected denoiser or tune the acceptance masks to conceal a failed boundary.

#### 3.6.1 First adapter: dispatch, formats and initialized history

[I04/I14/I16](../research/ray-tracing/2026-11-19-twenty-investigations.md#i14--minimal-subgroup-independent-fidelityfx-adaptation) provide source evidence. Implement these decisions in order:

1. The trace/packing producer writes a complete `R32_UINT` hit word and receiver-validity word per 8×4 tile. Define unique write ownership or a separately proven reduction; no racing non-atomic bit updates.
2. Set `tw=ceil(W/8)`, `th=ceil(H/4)`. Preparation uses local size 8×8 and dispatch `ceil(tw/8)×ceil(th/8)`. One in-range invocation owns one tile, loads both words and stores `lit_word=(~hit_word)&valid_word` once. No subgroup operation, clamped duplicate edge store or FP16 arithmetic is needed in preparation.
3. Classification and filtering consume validity. Invalid/padded zero bits do not count as shadowed samples. Use per-receiver motion and previous-position/depth correspondence. For each shared Boolean reduction, use lane-0 clear → workgroup barrier → shared atomic OR of failed predicates → barrier → every lane caches the result locally → a third barrier → return the cached result. The helper is called more than once; the final barrier prevents a later reset racing a prior reader. Invocation/branching must be workgroup-uniform. All lanes reach required barriers; out-of-range lanes contribute neutral predicates and suppress image writes.
4. Derive classification/filter dispatch from their actual 8×8 pixel entry points. Inspect remaining subgroup operations and require their actual capabilities; subgroup-independent preparation does not prove every SDK kernel is subgroup-independent.
5. Apply the format table below to both declarations and resources. Query each required storage, sampling and linear-filter feature. Require/enable the actual FP16 arithmetic capability used by the filter; storage image precision does not itself establish `shaderFloat16` or every 16-bit buffer/storage feature. Check additional features only if emitted SPIR-V uses them.
6. On a new/reset epoch, initialize both moments and both scratch/history parities, initialize previous R32F depth from current converted depth, and mark prior correspondence invalid. The invalid-epoch shader path must not fetch prior values before initialization. Preserve frame parity; retire replaced resources after completion.
7. Validate the complete reprojected sampling footprint. The initial adapter **rejects history unless every nonzero-weight tap of its bilinear footprint is in bounds, valid and receiver/depth/normal/epoch compatible**; a footprint extending outside the image is rejected before clamp sampling can conceal it. Compute the actual texel-center weights, then use the original linear sample only when the entire footprint passes. Apply corresponding checks to actual moment/previous-depth footprints before reads. Rejected history uses initialized current-frame information; it does not silently disable the current ray. More permissive weighted gathering is deferred.

| Resource | Initial declaration/view | Count | Payload per internal pixel |
| --- | --- | ---: | ---: |
| Moments | `rgba16f` / `R16G16B16A16_SFLOAT` | 2 | 16 bytes |
| Scratch/history | `rg16f` / `R16G16_SFLOAT` | 2 | 8 bytes |
| Converted current and previous projection depth | `r32f` / `R32_SFLOAT` | 2 | 8 bytes |
| Filtered visibility output | `r32f` / `R32_SFLOAT` | 1 | 4 bytes |

These seven payloads total **36 bytes/pixel, approximately 71.19 MiB at 1920×1080**. This is a design calculation, not measured memory. Masks, guides/identity, geometry, AS, descriptors, alignment, allocator overhead and simultaneous old generations are additional. The moments format differs from the stock host's packed format and requires the independent precision/reference test. Unsupported format/features or a failed initial-1080p 128 MiB peak gate leave that Soft row unavailable; do not silently widen formats, lower resolution or switch denoisers.

T09 must include every one-hot and one-clear bit pattern, mixed-validity masks, 1×1/7×3/8×4/9×5/31×15/33×17 dimensions, canaries, repeated shared reductions alternating true/false, two receiver IDs moving differently within a 2×2 quad, and two distinct poisoned-history patterns on both reset parities. Add half-texel history shifts across receiver/sky/image boundaries with rejected taps independently poisoned. Lit valid pixels beside invalid neighbors must remain lit like the all-valid control. Test the exact compiled permutation.

The moment format also changes stored history-count precision. Run a mixed-visibility/static-penumbra fixture for at least 4,096 real submissions, record actual count/moments/variance, then move and hold the caster under the unchanged response gates. The stock count can be damped or reset, so do not assume it reaches a particular value in flight. Separately seed a controlled diagnostic history around 2,047/2,048 with unit damping to verify the selected RGBA16F storage round trip, finite variance and response. Document quantization behavior; no hard count cap or alternate filter is introduced without a measured need and renewed quality proof.

#### 3.6.2 Independent numerical and moving-shadow fixtures

**Numerical oracle.** Build expected intersections from unbiased float64 intended receiver positions and transformed triangles, before the candidate's normal offset or `t_min`. Independently compare the raster-represented and AS-represented geometry so float quantization cannot silently redefine the expected scene. Record actual engine precision, D32/D24/R32 depth path, projection/inverse matrices, jitter/sample location and deformation generation. Float64 physics or split-translation raster shaders do not imply float64 TLAS transforms.

Bound depth quantization, inverse-projection arithmetic, coordinate representation and raster/AS mismatch. Obtain the oriented geometric normal explicitly; a normal/roughness texture may contain interpolated or normal-mapped shading normals and is not automatic proof of that normal. Keep denoiser-normal and ray-offset-normal semantics separately named, even if a qualified fixture shares their value. Use outward representable rounding. NVIDIA's triangle-hit derivation is a reference, not a universal hardware constant for raster receivers.

Test parallel blocker gaps of 0.25/0.5/1/2/5 mm, grazing rays, mixed sidedness, mirrored geometry and instances, nonuniform transforms, and scene translations 0/1,000/10,000/100,000 m. Large translations delimit the supported envelope; they do not require unlimited advertised coordinates. In the simplified parallel-plane fixture, let unit geometric normal `n` point from receiver toward the blocker, unit ray direction `d` point toward the light, `c=dot(n,d)>0`, `gap>0`, and offset/error/`t_min` be nonnegative. Check `delta + E_normal + t_min*c < gap` and the expected hit's `t_max`. Include outward-rounding error; this is sufficient only for the stated plane model. Orient two-sided normals for the tested ray; `c<=0` and ill-conditioned directions need the separately defined facing/fallback path, not this inequality. Nonfinite/singular/mismatched receivers use native. Do not hide ordinary-flight failures inside a stress-only classification or add origin rebasing.

**Moving-shadow oracle.** Fix camera, ground and sun while an opaque strip moves at height 10 m over a receiver projected at 100 pixels/m, with a 0.265° solar half-angle. Test widths 2/8/32 pixels; velocities 0.25/1/4/12 pixels per real frame; both directions; reversal; step-and-hold; and an oblique-sun offscreen-caster case. [I15](../research/ray-tracing/2026-11-19-twenty-investigations.md#i15--an-independent-moving-shadow-oracle) supplies a closed-form slope-disk unit oracle. For the product's solid-angle sampler, use independent deterministic quadrature of the actual measure and the section 4 convergence criterion. Never compare mismatched sampling distributions.

Apply the three-frame/0.10 response gate separately to newly lit and newly shadowed ground after the reference reaches its held value. Preserve a continuous-motion test without reset. Track leading/trailing edge displacement, integrated thin-shadow deficit and visibility error; a narrow blocker need not reach full darkness. Freeze ROIs/boundaries before results. Compare raw mask, denoised visibility and calibrated linear pre-tonemap sun lighting. For each later temporal provider, run denoiser-only, reconstruction-only fed a converged reference, and the combined path. Only a demonstrated failure can justify a bounded new history-rejection or provider-mask change.

### 3.7 Frame order and temporal data

Required dependency order for Soft:

1. Publish the final displayed scene/part transforms and geometry generations for this real frame.
2. Upload/deform dirty geometry; build required BLAS; build TLAS. Preserve renderer graph dependencies.
3. Produce matching depth/normal/receiver-validity data and **current-frame** motion guides before denoising.
4. Trace sun visibility; convert to the pinned denoiser's packed input; reject invalid pixels/history.
5. Denoise in internal-render space; publish the current frame's mask and validity to the selected-sun lighting seam.
6. Run opaque lighting, existing sky/transparency/postprocessing, then the separately selected reconstruction path and UI.
7. Record submission/completion separately and retire resources only when safe.

Phase 09.1 first implements base current depth/normal/receiver-validity production and required resolve for Hard. Make `rt_needs_guides` participate in both depth/normal mode selection and the force-prepass decision independently of Environment validity; verify graph writes/resolves before consumption. Godot's stock motion pass is later than step 3, so phase 10 **extends that existing producer** with early velocity, prior-position/depth correspondence and R32F denoiser history, reusing actual current/previous displayed transforms and shader conventions. Start with rigid/static geometry; add animated vertices only after their previous-position producer is proven. Never label prior-frame motion current or alter ordinary upscaler velocity to accommodate RT.

Hard mode can prove the lighting seam before this work. Soft cannot be marked qualified without correct temporal guides; if that gate fails, retain the hard research result and leave the player-facing soft request on native fallback.

### 3.8 State, failure and history

| State | Allowed work and transition |
| --- | --- |
| `off` | Lightweight user/policy checks only; no RT owner/resources/scene scan. A capability menu query may inspect immutable engine facts without allocating GPU work. |
| `unavailable` | Retain request and a stable reason. No repeated allocation/probe attempt every frame. Retry only after relevant device/build/context change or explicit user action. |
| `preparing` | Persist an activation marker first; build/warm bounded resources while displaying raster. Cancel safely on setting/world change. |
| `active` | Same-epoch producer and lighting binding with ordered GPU work. Receipt distinguishes submitted from completed; visual correctness remains separate evidence. |
| `suspended` | Temporary unsupported world/receiver/sun/size condition; original raster remains. Invalidate incompatible history; resume only on a validated event/generation change. |
| `failed_latched` | Recoverable RT failure stops new RT work, switches the lighting binding to native and retires resources. Preserve request; expose reason and explicit retry. |
| `retiring` | No new RT work. Hold previous resources until completion, then reach `off`/fallback. Late callbacks cannot activate or confirm a newer epoch. |
| `device_lost` | Do not promise an in-process raster recovery from a lost device. Stop the affected renderer through its existing failure path and use the persisted RT-off recovery latch on restart. |

Invalidate temporal history on camera cut, FOV/projection discontinuity, viewport recreation, internal/output resize, reconstruction change, world/landscape switch, aircraft/material/topology/LOD change that breaks correspondence, teleport/reset/replay seek, crash transition, origin change, sun discontinuity, RT quality/mode change and prior producer failure. For continuous camera/sun movement use validated reprojection; for a pause with unchanged camera and world retain stable history, but invalidate after a discontinuity on resume. Never bridge two retained Workshop/world lifetimes accidentally.

Record a history reset as requested, encoded and GPU-completed separately when those stages are observable. Do not claim that a CPU method return proves a successful GPU reset or displayed frame.

### 3.9 Source-specific platform, provider and package prerequisites

These constraints come from [I17–I19](../research/ray-tracing/2026-11-19-twenty-investigations.md#i17--metal-retain-replace-and-re-prove). They qualify separate rows and do not expand the core selected-sun effect.

**Provider conversion ownership.** For each consumer, record the producer path and conversion owner, motion sign/units/Y orientation, active versus allocated extent, current/previous matrices, jitter inclusion/removal, frame/token identity and independent history epoch. Record actual reset request, successful dispatch/CPU encoding and observable GPU completion separately. Use a static scene with alternating jitter at two internal resolutions, known camera/object motion, the 3.6.2 moving-shadow fixture and failed/delayed reset callbacks.

| Lane | Inspected boundary at its pin | Required gate before its RT combination |
| --- | --- | --- |
| Beta2 native/early RT guides | Camera jitter is normalized by internal dimensions; ordinary motion removes jitter and writes previous-minus-current UV, but too late for early shadows. | Produce early guides with an explicit conversion contract. Keep ordinary TAA/upscaler outputs unchanged and compare them Off/On. |
| Beta2 FSR2 | Receives pixel-scaled jitter and an alpha-derived reactive view; transparency/composition is empty. Stock accumulation reset is false with a FIXME. | Implement or narrowly port/re-prove the existing per-view reset contract before qualifying this combination. Do not assume the separate vendor-lane patch is already in beta2. |
| NVIDIA/SDK24 FSR lanes | Existing FSR2 reset patch acknowledges successful dispatch. FSR3 preparation decodes motion and copies alpha-derived reactivity or zero. | Validate actual per-view generations, extent and resource ordering. Neither alpha-derived input is proof of a shadow-specific reactive mask. |
| NVIDIA DLSS/Reflex | Uses its own engine pin, unjittered matrices and captured draw token for tagging/constants/evaluation. | Preserve token consistency and existing latency ownership. Check DLSS, Reflex and native RT independently. No RR/FG claim. |
| MetalFX Temporal | Inspected beta2 passes half normalized jitter with Y flip without FSR2's internal-size multiplier, while Apple documents pixel offsets. Reset receipts do not establish per-reset GPU completion. | Derive projected sample displacement/sign and compare exact scaler arguments at two resolutions; prove image behavior before deciding a fix. Treat this as a source-level mismatch candidate, not an observed GPU bug. |

Do not automatically add a new reactive mask. First isolate a temporal defect, identify which provider owns it, and prove that a documented input can correct it without suppressing valid shadow detail. If that work is unavailable, leave the combination blocked while the independent Native row continues.

**Metal producer disposition.** Phase 18 starts rebuild-only and records a retain/replace/re-prove table:

| Existing experiment | Required disposition |
| --- | --- |
| 0005 immutable, opaque, nonindexed float3 and one-shot AS | Replace the one-shot lifecycle with retained generations; prove every newly admitted geometry form. Refit is optional later. |
| 0018 startup-flag source capture; later buffer access/update invalidates cached source without regeneration | Replace with runtime-owned acquisition for already-loaded assets, event-driven invalidation and safe Off release. Do not require diagnostic readback or startup capture. |
| 0018 indexed expansion and excluded compressed/skinned/blend-shape/LOD inputs | Choose an exact bounded source route and prove each admitted category. Unsupported relevant content forces native. |
| Cumulative, non-refunded source/AS counters | Replace diagnostic process-lifetime accounting with live, retiring and peak bytes, preserving bounded admission. |
| 0027 static camera/scene, exact constant shader, ≤16 surfaces, no visible lights/jitter/TAA/MSAA/upscaler and missing guide receipt | Keep closed. Do not import its primary-ray/flat-normal producer as the selected-sun implementation. |
| Existing residency declarations, leases, epochs/serials and logical TLAS→BLAS→source release | Retain these safety ideas and re-prove actual graph completion and allocator behavior. No mandatory shared heap or arbitrary frame-delay retirement. |

**Combination package completeness.** The native helper already hashes the Streamline archive and verifies listed package files. Its inspected extraction/receipt path can describe whatever DLLs remain in a stamped extracted directory; this does not independently prove the feature roster was complete. Extend the existing manifest, not the packaging architecture: backend/feature, required or disabled component, archive/member/staged hash, matching headers/ABI, license and applicable signature policy. Verify required staged members against the pinned archive before generating a new receipt. For the NVIDIA interposer, follow the applicable signature check and bind it to the path actually loaded. The separate AMD SDK24 intake already has staged-tree/signature checks; locally rebuilt legacy AMD binaries use their own build identity rather than an invented vendor-signature requirement.

T14 has three distinct fault stages: omit/alter a required intake member before receipt creation; remove/change a listed post-package file; and run isolated diagnostic copies to observe provider-specific startup/fallback. Cover interposer/common, the DLSS plugin/runtime pair, Reflex/PCL/Vulkan latency components, wrong SDK version, and disabled RR/FG libraries. The fork still requests RR/NIS and game-session DLSS-G in its feature list, so absence is a test question, not automatically harmless. The supported package must refuse an incomplete manifest; diagnostic failures must not report a missing provider active. An independent RT path is not relabeled unsupported solely because DLSS fails.

## 4. Performance and quality gates

These are **proposed acceptance limits**, not measured results or a promise that the current scene fits them. Freeze them with the RT-00 baseline. A stricter existing platform gate wins. Do not relax them after seeing candidate results.

| Gate | Initial core requirement |
| --- | --- |
| Primary desktop resolution | Actual 1920×1080 output/drawable; first control has internal 3D and RT at 1920×1080. Record logical UI, window, drawable, internal 3D and RT dimensions independently. A launch argument alone is not proof. |
| Apple Silicon Retina exception | Qualify the physical panel's native pixel resolution and actual drawable/display mode, with internal 3D/RT pixels reported separately. A 1080p M1 result does not qualify a Retina panel. Follow the current Apple plan. |
| Target frame cadence | Real rendered 60 Hz workload: wall-frame p95 ≤18.333 ms and p99 ≤25 ms as this plan's initial limits; report missed-frame bursts and maximum. If baseline already fails, resolve/attribute it before claiming RT qualification. Generated frames do not count. |
| Whole-effect GPU cost | Paired incremental whole-frame GPU p95 ≤2.0 ms at core 1080p and within actual remaining frame headroom, evaluated by the frozen statistic/uncertainty rule in 5.2. Include guides, AS work, traversal, denoise, barriers and lighting overhead; never add independent pass p95 values as a substitute. |
| RT CPU cost | Incremental render/application CPU p95 ≤0.25 ms in the matched core workload, with simulation and loading measured separately. No per-frame full scene traversal or mesh readback. |
| Incremental peak GPU memory | ≤128 MiB for the initial 1080p effect, including duplicated geometry, BLAS/TLAS, scratch, guides/history, descriptors and in-flight retirement peak. Keep raster atlas memory in the control. This is the earlier research ceiling adopted as a strict initial gate, not a measured fit. |
| Off overhead | No recurring RT allocation/submission/scan counters. Same-build RT-off wall/GPU p95 increase must be within the larger of 0.10 ms or 1% of the matched control, with a paired uncertainty interval that does not support a larger regression. Also compare the patched engine RT-off with the official control for generic patch regressions. |
| Off retention | RT-owned live resource bytes and live owners return to zero after GPU-safe retirement. Report engine/driver caches separately; they cannot conceal retained RT AS/history/geometry. |
| Useful activity | In the declared daylight real-flight case, RT actually executes in ≥95% of eligible frames and covers ≥90% of each predeclared target receiver ROI. Freeze the denominator from the tape/viewport and only predeclared non-feature intervals such as Home/crash. Unsupported casters, preparing/suspended/failed states and raster fallback remain in the denominator. ROI coverage is valid RT receiver samples divided by all in-scope visible receiver samples across those frames; report empty-ROI frames separately. Requests/allocations are not valid RT output. |
| Hard correctness | Analytic hit/miss, masks and light-identity tests pass exactly away from documented geometric boundaries. Independent CPU reference uses unbiased intended geometry with float64 ray/triangle arithmetic; separately verify represented raster/AS agreement. Never copy the candidate bias into the oracle. Boundary exclusions and validated coordinate envelope are fixed before comparison. |
| Soft reference | Compare against a converged many-sample reference from the same geometry/light contract. Double reference samples until mean visibility changes <0.005 and p95 absolute change <0.02 in target ROIs; otherwise the reference is inconclusive. Candidate mean visibility error ≤0.02 and p95 absolute error ≤0.10 outside the predeclared silhouette/disocclusion band. |
| Temporal/readability | No missing wing/gear/hinge silhouette, detached moving shadow, stale-world shadow or persistent trail. After disocclusion or a held lighting transition on a static receiver, visibility must converge within three real frames to absolute error ≤0.10 in the controlled static-light fixture. Test newly lit and newly shadowed regions independently and continuous caster motion without forced reset. Ordinary pilot-view video review remains mandatory. |
| Non-sun invariance | With the sun contribution disabled, RT on/off is identical in deterministic fixtures for ambient, emission, other lights and UI. Test cloud On/Off and another directional light independently. |
| Physics isolation | Matching deterministic input tape, seed, solver/backend and checkpoints retain exact within-build accepted state/events across RT modes. Cross-engine comparison follows existing qualified numerical tolerances; do not invent cross-platform byte equality or regenerate goldens. |

Secondary 1440p/4K and other frame-rate targets require separately budgeted rows after 1080p. 720p is a final compatibility objective. Do not silently reduce resolution, scene detail, physics work, active aircraft or weather to make a failing RT row pass. A qualified reconstruction combination is a separately named mode with its actual internal pixels.

## 5. Evidence, tests and measurement discipline

Every phase writes a compact evidence receipt under its proposed evidence home. Include application SHA/dirty state, engine source and ordered patch hashes, editor/template identity where applicable, shader/denoiser revision, OS/GPU/driver, renderer, settings, actual dimensions, scene/aircraft/material generations, input/camera/light sequence, commands, required case roster, exit/log verdict, metrics, exclusions and result scope. Empty/missing cases fail the reducer. `skipped`, `blocked`, `failed`, `passed` and `not_run` remain distinct.

Reuse the [checked runner](../tools/shared.md#one-godot-script), [debug bridge](../../tools/debug/README.md), [shadow tools](../../tools/shadows/README.md), [graphics tools](../tools/graphics.md), [performance tools](../../research/performance/README.md) and [test queue](../../tools/testqueue/README.md). On enrolled hosts obtain and retain the correct session/admission handle. Do not introduce a competing profiler, invoke unmanaged Godot sessions, or use headless/software results as GPU qualification.

For performance, follow the exact paired protocol in 5.2: five matched pairs initially, 30-second warmup, at least 60 seconds measured per run, and retained attempts/exclusions. Use a fixed physics/input tape or existing controlled real-flight fixture; a scripted rendering circle remains a rendering fixture. Record foreground/focus, pause, thermals/power mode, compilation/cache state and concurrent-process exclusion. GPU validation/capture runs and final performance runs are separate; deep geometry captures can alter AS build time and memory. Community FPS examples with different internal pixels, wind or caster exclusions are not comparable baselines.

For life-cycle qualification, run 100 on/off cycles, 50 resize/reconstruction cycles, 25 world/flight restarts and a 30-minute active-flight soak on the selected candidate, with bounded counters and safe teardown. Run cold setup separately so warm-cache results do not hide first-enable work. A source/parser pass never closes these gates.

### 5.1 Test families

| ID | Required cases and oracle |
| --- | --- |
| T01 — API/device | Missing methods/constants; headless; Compatibility; Mobile; wrong backend; AS/query/pipeline combinations; disabled feature bits; unavailable entry points; device limits and selected physical adapter. No unsupported native call. |
| T02 — AS correctness | One triangle, indexed/nonindexed cube, known hit/miss, typed vertex/storage RID acceptance, nonzero push constants with UBO control, transforms, facing groups, invalid indices/format, zero/overflow capacity, same-frame two TLAS builds, failed candidate after BLAS preparation, masks and repeated create/free. Independent unbiased expected intersections. |
| T03 — GPU ownership | The 3.3.1 dependency matrix; multiple in-flight generations; per-AS scratch reuse; generic allocation failure; candidate publication failure; indirect BLAS lifetime; stale callback rejection; device-loss restart; asynchronous timing identity calibration. Validation logs plus completed GPU output. |
| T04 — Lighting isolation | Selected sun among two directional lights; direct diffuse/specular; emissive patch; local light; shadow opacity 0/0.5/1; range/fade; native/projected/off; contact shadows; cloud On/Off; twilight/night; source-disabled light. |
| T05 — Receiver/MSAA | Tiny wing/gear/leaf foreground; absent Environment/ordinary prepass; current guide stamps; actual D32/D24/R32 depth conversion and reverse-Z reconstruction; unbiased gap/precision/facing envelope; sample-edge masks; MSAA Off/2×/4×/8×; supported custom `light()` and rejected variants. |
| T06 — Scene coverage | Offscreen up-sun caster; distant tall object; all MultiMesh instances; changing visible count/LOD/material; hidden/removed/cast-off object; capacity overflow; unsupported caster inside/outside influence volume. Conservative fallback is part of the oracle. |
| T07 — Displayed motion | Aircraft translation/roll, hinges, flaps, retracting gear, negative-scale part, parked/spinning/blurred propeller, companion instance if admitted, camera pan/FOV/cut and paused/resumed picture. Compare against actual raster transforms. |
| T08 — Alpha/deformation | Alpha scissor/hash/mips/UV/color, canopy variants, differently phased/yawed/scaled tree instances, geometry displacement versus normal flutter, flags/windsock/skin, topology, native noncasters, facing/material groups, descriptor limits/churn and overrides. No opaque replacement or frozen wind. |
| T09 — Denoiser/history | The exact 3.6.1 bit/extent/validity/subgroup/format/poisoned-parity fixtures; per-pixel versus mixed-quad correspondence; moving/depth-overlapping receivers; the 3.6.2 static-receiver moving-shadow oracle; disocclusion, light change, reset/resize/world replacement, jitter and repeatability. Independent converged reference and stage isolation. |
| T10 — Settings/recovery | Absent/old/malformed preferences; explicit saved Off/On; Keep/Revert; canceled preparation; renderer restart refusal; nonwritable marker; crashed activation; stale completion; direct-flight arguments; Restore defaults; unavailable UI reason. |
| T11 — Memory/off | No off-state geometry extraction/AS/guide/trace/denoise work; safe release after last use; shared BLAS reference count; retained world detach/restore; repeated lifecycle and shutdown; peak and steady bytes separately. |
| T12 — Real flight | Separate Club and Green content rosters, ordinary pilot view/zoom, approach/landing, aircraft on ground and low pass, Club shelter/trees, actual field wind/clouds, alternate sun angles, crash fallback and Home. Match 3.3.2 feasibility to live content; activity/coverage accompany 5.2 timings. |
| T13 — Combinations | Native first; each FSR2/vendor/MetalFX lane separately proves 3.9 inputs, units, token and actual reset implementation, including alternating jitter at two resolutions and stage-isolated moving shadows. DRS and generated frames off. No inherited pass. |
| T14 — Delivery | Matched editor/template, clean import/export, packaged resources/ABI, required feature roster against pinned archive before receipts, actual loaded-module identity, license/signature policy where applicable, missing/corrupt/mismatched intake and post-package cases, provider-specific fallback, fresh/upgrade/recovery profile. |
| T15 — Simulation | Existing relevant flight/replay/checkpoint suites and a matched accepted-state tape across RT modes; no physics-source/config change; frame stalls do not redefine step rate or input sampling. |

### 5.2 Frozen sampling, statistics and activation protocol

This is a proposed executable reducer contract, derived from [I10/I20](../research/ray-tracing/2026-11-19-twenty-investigations.md#i20--submitted-frame-identity-and-a-reproducible-qualification-reducer). Implement its synthetic fixtures in 00.3 and calibrate actual GPU identity as soon as 02 supplies a device fixture.

**Sample identity and timing ownership**

1. Acquire/release the existing `RenderTimingLease`. Do not write the shared viewport timing flag directly or disable another diagnostic consumer when RT stops.
2. Freeze a submission receipt with `run_id`, viewport generation, logical render frame, state/history epochs, query slot and slot generation, actual internal/output dimensions, submitted RT mode and content generation. Join asynchronous results to this receipt. Store the engine-reported profile frame separately until its mapping is proven; do not label a result with the frame polling it.
3. Validate timestamp support for the actual queue, valid bits, native period/units and wrap handling. Read results without adding waits or readbacks to ordinary flight. Different queues and overlapping viewport/pass intervals do not form a summable whole-frame duration. Use one justified whole-frame timing domain and retain phase timers as diagnostic attribution.
4. An asynchronously unavailable result stays pending under its original submission identity; a later poll is not a new sample. At collection close, missing, duplicate, stale-epoch, wrong-extent or incomplete intervals are invalid with a reason, never zero or reused. Unexpected loss/identity mismatch blocks the run. Calibrate with alternating known GPU work, toggled epochs, more than one frame in flight, delayed results and viewport recreation. Test wrong-slot and wrap cases synthetically.

**Matched process runs and fixed reducer**

1. For each required row, A is its native-raster control and B is requested RT with otherwise identical content, internal/output pixels, scene settings, renderer/presentation configuration and input tape. Start independent processes. Use five pairs in the order **AB, BA, AB, BA, AB**, producing ten runs. Keep pair IDs; do not reinterpret this as five frames or five measurements from one process.
2. Warm each run for 30 seconds, then measure at least 60 seconds of the predeclared tape interval. Preparing/suspended/failed/fallback frames inside that interval remain in the RT activity denominator. Record the complete caster/wind/material/LOD roster and view conditions. Preserve every failed/excluded attempt and the predeclared reason; no removal because its timing is unfavorable.
3. Calculate each run's p95/p99 by nearest rank: sorted sample index `ceil(p*N)-1` for `p=0.95/0.99`. For pair `i`, define `d_i=p95(B_i)-p95(A_i)`. Report every `d_i`, their median (mean of the two middle values for an even count), and a two-sided 95% percentile bootstrap interval of that median, resampling **whole pairs** 10,000 times with seed `20261119` and a pinned recorded RNG implementation/version. Use the same nearest-rank rule at 0.025/0.975 for the interval endpoints. Do not bootstrap individual correlated frames as independent runs or subtract unrelated global percentiles.
4. The upper endpoint of the paired interval must meet the section 4 incremental limit; apply the same method to RT CPU and Off regression. Each valid candidate run must also meet the absolute cadence/activity/coverage requirements. Report maxima, bursts and all distributions; a favorable median does not erase a failed absolute gate.
5. If the initial interval straddles an incremental limit without an independent correctness failure, one preregistered extension to ten pairs is permitted, retaining the first five. Reverse the alternating orientation for the added sequence, recompute once, and classify a remaining straddle as inconclusive/blocked. An interval wholly above the limit fails. Changing code starts a new revision/roster; it does not remove the prior result.
6. Collect GPU-cost/headroom comparisons with the same controlled uncapped presentation mode for A and B; collect product 60 Hz cadence separately with the intended presentation settings. The 60 Hz target corresponds to 16.667 ms; the section 4 p95/p99 limits are allowed tail bounds, not a claim that 18.333 ms equals 60 Hz. Keep driver/power policy fixed and reported; do not assume a fixed-clock diagnostic represents normal player behavior.

**Cold and warm activation**

Measure first requested enable, first submitted RT frame, first observed completed result and first valid displayed effect separately, with cache state and compile-counter deltas. Add an actual counter for new RT kernels where existing engine monitors do not cover them. A general engine precompilation feature does not guarantee custom kernels are warmed. Keep native display while preparing; do not allocate, compile/warm RT GPU pipelines or retain RT data before an eligible On request to conceal activation cost. Retain cold setup, warm re-enable, cancellation and after-retirement memory as separate receipts. Normal engine code/driver caches remain separately identified.

## 6. Implementation command contract

Existing focused commands use the current documented runner. Example Bash, after required host admission and import, with `RT_GODOT` set to the exact verified candidate executable:

```sh
python3 tools/godot/run_checked.py --label rt-policy --timeout 90 -- \
  "$RT_GODOT" --headless --path app --script res://tests/test_rt_policy.gd

python3 tools/godot/run_checked.py --label rt-parse --timeout 90 -- \
  "$RT_GODOT" --headless --path app --check-only \
  --script res://render/ray_tracing/controller.gd
```

These two named GDScript files are **proposed phase outputs**, so the commands become valid only after they are created. On managed hosts, prefer `sim_test_launch`/`sim_test_status` and its retained request ID for eligible checks, or the existing queue CLI fallback; preserve OS requirements. GPU fixtures use rendered admission, not that headless batch path.

Phase 00 must implement the following **proposed** bounded CLI interfaces by adapting existing helpers. Every command rejects unknown options, existing output directories, missing cases and source mismatch. It must not silently download/upgrade a dependency or start a broad suite.

```sh
python3 tools/graphics/raytracing/engine.py prepare --manifest <pin-manifest> --out <fresh-intake>
python3 tools/graphics/raytracing/engine.py build --intake <verified-intake> --target editor
python3 tools/graphics/raytracing/engine.py build --intake <separate-verified-intake> --target template_release
python3 tools/graphics/raytracing/engine.py pair --editor <receipt> --template <receipt> --out <new-pair.json>

python3 tools/graphics/raytracing/verify.py --suite api --godot <candidate> --app <snapshot/app> --out <fresh-dir>
python3 tools/graphics/raytracing/verify.py --suite gpu-fixture --godot <candidate> --app <snapshot/app> --out <fresh-dir>
python3 tools/graphics/raytracing/verify.py --suite lighting --godot <candidate> --app <snapshot/app> --out <fresh-dir>
python3 tools/graphics/raytracing/verify.py --suite motion --godot <candidate> --app <snapshot/app> --out <fresh-dir>
python3 tools/graphics/raytracing/verify.py --suite lifecycle --godot <candidate> --app <snapshot/app> --out <fresh-dir>
python3 tools/graphics/raytracing/verify.py --suite package --pair <pair.json> --package <candidate-package> --out <fresh-dir>
python3 tools/graphics/raytracing/qualify.py --matrix <frozen-matrix.json> --evidence <evidence-root> --out <new-verdict.json>
```

The wrappers delegate launch, logs, capture and frame collection to existing tools. `qualify.py` reduces evidence; it does not launch a test or rewrite a failed baseline. Pin the required suite case list so a renamed/skipped test cannot manufacture a green result.

## 7. Phases and subphases

All implementation subphases start **not started**. The research in sections 2 and the appendices is completed analysis, not execution of these phases.

### Phase VQ-RT-00 — Freeze scope, baseline and reproducible evidence

**Depends on:** none. **Output:** a concrete source/engine/content/budget matrix and working evidence wrappers. **Do not change runtime rendering yet.**

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 00.1 | Read current rules/ownership and the twenty-investigation decision record; record branch heads, compare current main to the audited SHA and classify changed integration paths. Pin before editing. | `baseline.json` records exact source/engine/patch/content identity, dirty paths, drift and accepted research dispositions. Unexplained engine/renderer drift blocks the affected phase. |
| 00.2 | Select a repeatable real-flight defect and freeze three existing receiver ROIs per field: aircraft/gear, terrain contact and a field object where present. For Green's absent field-object category, declare that absence now and choose another existing in-scope receiver ROI; do not invent scenery or count an empty ROI as a pass. Freeze camera/input/weather/sun and tuned PCSS. | Native captures/video show the benefit opportunity in ordinary pilot view. Each field has its own nonempty predeclared ROI roster. If no meaningful defect survives tuning, production RT is no-go for that row; later fixtures remain research-only. |
| 00.3 | Implement the proposed manifest, required-case rosters and thin CLI, including 5.2 submission identity, exact pair order/quantiles/bootstrap and bounded extension. Reuse checked runner, queue, timing leases and existing collectors. | Synthetic fixtures reject missing/duplicate/stale/wrong-epoch samples, bad units/wrap, wrong engine, fallback-only timing and incomplete runs; known quantile/paired datasets reproduce their expected result. Actual GPU identity calibration remains required in 02. |
| 00.4 | Collect the official baseline at actual 1080p now; collect the candidate-Off baseline only after 01.4 produces that executable. Freeze section 4 limits/hardware rows and record shadow/light receipts and repeat noise. Phase 01 may start after 00.1/00.3 without waiting for this subphase. | Baseline portions of T12/T15 complete, including reusable input tapes and the pre-feature simulation control. RT-On comparisons are deferred to 14. Performance headroom and baseline failures are explicit. No source-based GPU estimate substitutes for timing. |

**Stop:** missing real image benefit, unusable baseline, or absent source identity. Continue only source/fixture research until the production prerequisite is resolved.

### Phase VQ-RT-01 — Create the isolated engine lane and repair source prerequisites

**Depends on:** 00.1/00.3. **Owned paths:** proposed intake/patch tooling and disposable engine trees. **No application default changes.**

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 01.1 | Pin official source commit/archive/hash and toolchain. Create distinct editor/template intakes and ordered patch manifests. Bring only the two reviewed Vulkan prerequisite patches from `0ccfa7d…`, retaining provenance and their tests. | Preparation recreates identical patched source and refuses unknown edits/hash mismatch. Existing NVIDIA/AMD/Apple intakes remain separate. |
| 01.2 | Revalidate AS addresses, recoverable allocation/bind failure, per-AS scratch alignment, entry points and typed vertex/index creation/usage flags. Review generic cleanup independently and map 3.3.1 to graph access tracking. | Source-bound faults and affected translation units pass; generic buffers retain correct success/failure/cleanup. Document existing global AS barriers and coherent uploads accurately. No GPU qualification claim. |
| 01.3 | Revalidate TLAS arithmetic, fresh/reused same-frame reservation, type validation and dependency transaction. Define empty scene as no dispatch; reject unproved zero capacity. Include prior BLAS mutation when defining atomicity. | Invalid TLAS input preserves its prior valid state where inputs remain unchanged. Changed geometry uses the candidate-generation/native-fallback contract, not a stale old TLAS. Same-frame instance ranges do not overlap; no overflow. |
| 01.4 | Build/link a complete editor and release template, then verify matching source/patch/compiler identities. Ensure Compatibility/Mobile compile and non-RT launch. | Full link and pair receipt, official-control comparison and minimal non-RT rendered smoke pass. A translation-unit-only result cannot close 01.4. |

**Stop:** a patch changes general raster behavior without an explained fix and regression evidence, or the full binary cannot be built reproducibly.

### Phase VQ-RT-02 — Prove the actual Vulkan query and AS contract

**Depends on:** 01. **Output:** native hit/miss/lifetime evidence and an explicit query-only decision.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 02.1 | Inspect selected-device extension/feature chains, AS geometry formats, limits and enabled entry points in the built binary. Use checked explicit buffer updates and sentinel output in the fixture; do not assume constructor upload success. | T01 matrix reports supported, enabled and actually exercised separately. Unsupported paths return a reason without calling unavailable functions. |
| 02.2 | Reproduce the existing-pin positive route on a both-feature device: real compatible RT pipeline/SBT and a compute query. Include nonzero push-constant results and a UBO control; historical push-constant reports are regressions to guard, not assumed current bugs. | Known hit/miss/mask/transform/readback and validation pass. Mandatory on both-feature devices; not applicable on query-only devices, which must pass 02.3. Never fabricate an SBT token or accept a sentinel-only result. |
| 02.3 | Implement a narrowly scoped query-only TLAS construction mode/API in the engine adapter, with valid zero SBT offset semantics and explicit rejection if that TLAS is used by an incompatible trace-rays path. Do not weaken the existing pipeline validation globally. | A query-only test configuration proves no pipeline/SBT creation/call is needed; both-feature and pipeline-only negative/control cases retain correct behavior. Tests include missing entry points. If this cannot be proven, retain the legitimate pipeline/SBT route and advertise `requires_pipeline_support=true`; do not claim generic query-only support. |
| 02.4 | Run allocation/capacity/lifetime faults, typed storage-capable vertex deformation→build→query, candidate failure after BLAS preparation, multiple in-flight frames and teardown. Calibrate asynchronous timing identity with alternating known work. | T02/T03 completed output, actual barrier/slot receipts and faults pass. Generic storage RID fails input validation as expected; no stale current-scene publication or timing attribution. Hardware remains blocked without execution. |

**Decision is bounded:** query-only implementation is preferred. The only permitted fallback is the proven real-pipeline/SBT route with explicit additional admission. Neither feature bits nor CPU mocks close the native gate.

Freeze these conditional case rules in the required-case roster. A query-only device passes only through the repaired no-pipeline path plus its own query/AS/lifetime GPU cases. If 02.3 is not proven and the implementation retains `requires_pipeline_support=true`, that device is unavailable. An unsupported pipeline control is not a failed query test, and an inappropriate not-applicable label must never erase a genuinely required case.

### Phase VQ-RT-03 — Add pure capability and effective-policy resolution

**Depends on:** 00 and the ABI facts from 02; can be drafted while native work runs.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 03.1 | Implement proposed settings/capabilities adapters with dynamic method/constant discovery. Parse on the unmodified official engine without referencing unavailable enums/classes at load time. | T01 on official, custom, headless, Compatibility, Mobile and unknown facts. No RenderingDevice is created solely to render a menu explanation. |
| 03.2 | Resolve request, actual renderer/driver, ABI, native-shadow policy, view/activity, sun identity and admitted engine/device row into an effective mode and stable reason code. | Pure truth-table tests cover every state and missing field; GPU-name matching is not a capability oracle. Off/projected/source veto always suppress RT. |
| 03.3 | Keep saved intent immutable under fallback. Define hard/soft from existing effective softness; a missing soft capability returns native fallback, not an undisclosed hard downgrade. | Old/absent preferences resolve Off; malformed values follow current preference validation/recovery. Automatic graphics never enables RT. |
| 03.4 | Define the bounded status ABI, counters and rate-limited diagnostics. Separate request/selection/submission/completion and unknown timing. | Schema tests reject ambiguous units/epochs and manufactured zero timings. No per-frame log/JSON spam. |

### Phase VQ-RT-04 — Establish resource ownership and the inert Off state

**Depends on:** 02/03. **Do this before building the full scene.**

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 04.1 | Implement one native RT owner per admitted viewport/world with monotonic activation/retirement epochs. Defer owner/resource creation until an eligible On request. | T11 cold Off counters are zero; opening Settings and unsupported requests do not allocate AS/history/guide resources. |
| 04.2 | Implement 3.3.1 retention and dependencies for geometry, indirect BLAS references, TLAS, each AS scratch, filtering and lighting. Use graph/fences and bounded reusable generations; no per-frame device idle. | T03 multiple in-flight generations and injected publication failures are validation-clean. Inputs/scratch/AS remain valid through last use; current changed geometry never selects an old mask. |
| 04.3 | Implement prepare/cancel/suspend/failure/off transitions with original raster binding restored before new work is stopped. Prevent stale callbacks from confirming replacement epochs. | T10/T11 cancellation at each preparation stage; 100 enable/disable cycles; no growth or stale binding. |
| 04.4 | Add debug-only allocation/build/dispatch failure injection and a persistent pre-activation marker tied to build/driver/device identity. | Marker-write failure refuses activation safely; induced crash recovers with effective RT Off next launch. Release builds omit fault controls. |

### Phase VQ-RT-05 — Define the registered scene and conservative coverage

**Depends on:** 03/04. **No flight-scene RT activation until the coverage proof exists.**

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 05.1 | Inventory actual native casters/receivers separately for Club and Green using 3.3.2, including source versus active LOD counts, facing/alpha and per-instance wind keys. Include aircraft/world content outside each field subtree. | Source census is reconciled with live manifests; admitted, native-noncaster and unsupported-relevant categories are explicit. Source triangles are never labeled measured AS memory or active primitives. |
| 05.2 | Implement event-driven mesh/instance/material/LOD generation tracking in the engine/world adapter. Snapshot render-thread data without SceneTree reads. | Add/remove/visibility/material/world-change cases update exactly once; unchanged frames do not rescan or extract meshes. |
| 05.3 | Compute the conservative receiver-to-sun influence region over the full solar cone and validated ray extent, including off-camera and distant tall casters. Recompute on view/sun/size/bounds changes; define capacity/memory limits. | T06 inserts unsupported center-ray and edge-of-disk blockers outside camera view but inside influence and forces native; one outside influence cannot affect the result. Overflow never silently drops geometry. |
| 05.4 | Implement whole-viewport fallback for incomplete influence coverage; keep partial optimization disabled. Produce 3.3.2 `scene-feasibility.json` with actual build-size queries and the minimal geometry microfixture before full 06–11 integration. | Omitted influential casters force native. Ledger includes unique live/retiring AS/input/scratch plus the planned guide/denoiser layout; unknown values are unresolved. Known budget impossibility blocks the field/mode; fallback cannot pass activity. |

### Phase VQ-RT-06 — Build static scene geometry efficiently

**Depends on:** 05 and the native AS fixture.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 06.1 | Create AS-ready streams for exact static terrain, runway and opaque field structures. Reuse existing immutable mesh data where compatible; use checked dedicated streams otherwise. | GPU known-ray tests agree with independent world geometry; terrain remains visually/collision aligned without changing collision data. |
| 06.2 | Share identical output geometry with compatible facing/caster policies; separate transforms and stable IDs. Split incompatible per-instance facing groups while sharing input storage. Deformed sharing requires the exact 3.3.2 key/equivalence proof. | Identical rigid instances share; differing deformations/material/facing cannot alias incorrectly. Mirrors and mixed sidedness pass; added AS entries count. Partition geometry only for an evidenced traversal issue without removing content. |
| 06.3 | Schedule bounded preparation after an eligible On request. Keep per-AS scratch ownership; reuse a generation only after completion. Shared scratch, compaction and refit remain deferred. | Cold/warm activation and actual simultaneous peak fit the ledger; native display continues while preparing. No hidden Off warmup or partially published scene. |
| 06.4 | Implement topology/material/LOD replacement through retained candidate generations and graph-ordered publication. Inject failure between candidate BLAS and TLAS readiness. | Old submitted work remains correct, changed current frames use native on failure, and T06/T11 retirement frees old inputs/AS/scratch only after last dependent use. |

### Phase VQ-RT-07 — Track moving aircraft and rigid instances

**Depends on:** 06. **Owned boundary:** displayed presentation, not physical state.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 07.1 | Capture the actual root/part transforms after `_render_pose` and hinge/mechanism updates, including CG/model origin and scale. Use current and previous rendered transforms. | T07 independently compares raster node transforms and uploaded instance transforms across interpolation fractions; no extra simulation query changes state. |
| 07.2 | Update TLAS instances for rigid movement without re-uploading unchanged vertices. Keep steady instance capacity and stable IDs; charge actual builds. | Translation/roll/gear/fold cases show expected hit movement. Instrumented unchanged BLAS builds remain zero; TLAS cost is measured. |
| 07.3 | Mirror native visibility transitions for parked blades, rotating visible blades, blur-hidden geometry and wreck replacement. | T07/T08 image sequences have no stale blades, opaque blur discs or flying-aircraft shadow after crash. Unsupported aftermath suspends RT. |
| 07.4 | Run fixed-wing catalog structural coverage plus representative detailed/hinged aircraft native views. Do not regenerate assets manually. | Fleet manifest identifies unsupported models explicitly; supported model changes remain presentation-only. Existing aircraft/replay checks pass. |

### Phase VQ-RT-08 — Resolve alpha, batching and deformation before real-scene admission

**Depends on:** 06/07. **This phase is mandatory for a vegetation-containing supported field.**

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 08.1 | Implement the section 3.3 GPU candidate-to-material lookup, bounded fully populated descriptors, feature/limit checks, generation retirement and explicit footprint-to-mip policy. Then implement alpha-tested candidate-hit evaluation; distinguish native blended noncasters from scissor/hash/depth-prepass casters. | T08 cutout holes stay open at distance/oblique angles; negative tests detect force-opaque leaves. Mixed surfaces, shared BLAS with different overrides, 24-bit index overflow, missing descriptors and material/texture churn select correct alpha or native fallback. Compare uniform/textured alpha separately. |
| 08.2 | Admit relevant MultiMesh instances with actual visibility/LOD/material and exact deformation metadata. Preserve UV transforms, color/custom data and native caster rules; reconcile the live count with 05's ledger. | Changed count/transform/LOD cannot leave ghosts or miss offscreen influence. Differently phased/yawed/scaled copies stay distinct where geometry differs. Capacity failure uses native. |
| 08.3 | Implement the same-clock authored deformation for required categories using typed storage-capable vertex inputs and 3.3.1 generation ordering. Separate position displacement from normal flutter and include alpha/mip semantics. | T08 current silhouettes agree; actual full-build/retirement cost fits the ledger. No frozen wind, source-mesh-only sharing, stale vertices or assumed refit. An unsupported influential caster leaves its field unqualified. |
| 08.4 | Reconcile the complete caster/receiver/deformation manifest and geometry feasibility for each candidate field/model. Mark source/content admission separately from actual RT output; do not label a field product-supported here. | No influential unsupported blocker or unresolved source category is hidden. Record feasibility projections as projections. Actual ≥95% frame/≥90% ROI activity is measured after the lighting seam in 09.4 for Hard, 11.4 for Soft and finally 14; it is not claimed before those phases. |

### Phase VQ-RT-09 — Integrate deterministic hard sun visibility into lighting

**Depends on:** 02/04; fixture work can start before scene phases finish. Real-flight admission also requires 05–08.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 09.1 | Implement base current depth/normal/receiver-validity production and resolve, making RT force the required prepass independently of Environment. Produce hard visibility and establish actual format/precision plus the unbiased 3.6.2 bias/facing envelope. | T02/T05 plane/box/grazing/gap/mirror and absent-Environment/prepass-disabled cases pass. Frame stamps and graph order prove freshness before phase 10 adds motion/history. Out-of-envelope native coverage remains counted. |
| 09.2 | Implement the concrete 3.5.1 binding/UBO/light-index seam and per-pass resets. Keep native maps; substitute only qualified selected-sun geometric visibility before fade/contact/opacity. | Actual reflected layouts compile/bind across active and disabled variants; no invalid default descriptor. Reordered/skipped lights, opacity/fade and non-sun terms pass T01/T04. Added Off cost is measured. |
| 09.3 | Preserve native range and aircraft cue handoff under Auto/Native/Projected/Off, including shadow-source veto, cloud choice, night and low sun. | Existing shadow-control tests plus T04 show no double ground shadow or cue loss; RT never overrides Projected/Off. |
| 09.4 | Run actual fixed-wing hard-shadow captures and compare with tuned native hard shadows at equal conditions. Keep this mode a correctness milestone. | Complete scene/lighting/activity evidence; ordinary PCSS softness is not compared unfairly to a hard RT reference. No production promotion yet. |

### Phase VQ-RT-10 — Produce current guides before temporal shadow filtering

**Depends on:** 09.1/09.2 and the resource graph from 04. **Blocking fact:** the inspected engine's ordinary current motion output is too late for pre-opaque temporal shadows. This phase is an engine change, not a compositor flag.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 10.1 | Specify depth aspect/format and R32F conversion, inverted projection depth, separately named offset/denoiser normals, identity/validity, prior depth, previous-minus-current UV, matrices/jitter/extents and history epoch. Use 3.6/3.9 per-consumer conversion ownership. | T05/T07 reconstruct known points from actual D32/D24/resolved paths, with no depth-to-color copy. Camera/object/combined motion and normal spaces pass; no assumption of provider compatibility. |
| 10.2 | Extend 09.1's already proven base guide producer with current/previous rigid transforms, early velocity and prior-position/depth correspondence; implement tracked R32F denoiser conversion/history. Preserve its Environment-independent force-prepass policy. | New writes/conversion precede denoise; no-Environment/prepass-disabled cases remain fresh. Thin wing and pure depth motion have correct correspondence. Off/excluded views have no extra guide pass/attachment. |
| 10.3 | Extend early motion to each admitted deformation and alpha/LOD variant from 08, or invalidate affected receivers conservatively. Define MSAA sample validity: initially use native visibility for mixed depth/normal/coverage pixels; do not average different surfaces into one trace origin. | T05/T07/T08 tests cover 1×/2×/4×/8× where available, gear/wire silhouettes, disocclusion, wind and model changes. Invalid guides cannot contribute history. The fallback band still satisfies each ROI coverage floor. |
| 10.4 | Verify independent history/guide epochs across pause, cuts, seek, view/size replacement. Compare ordinary motion outputs Off/On and record the 3.9 actual provider producer/reset boundaries. | T07/T09 stage acknowledgements match observed contents/completion; no false GPU-reset claim. Existing guides stay correct. Actual FSR/MetalFX gaps block their later combination rows rather than being assumed fixed. |

**Stop:** if a correct current guide cannot be produced within the owner boundary, Soft remains unavailable. Hard may continue as a research mode. Do not consume previous-frame motion, delay sun lighting by one frame, or silently replace the renderer.

### Phase VQ-RT-11 — Add finite-sun sampling and the pinned shadow denoiser

**Depends on:** 08–10 for real flights; 10 and the analytic fixture for isolated shader development. **Output:** qualified hard and soft modes under the existing softness preference.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 11.1 | Verify the exact denoiser pin/license/compiler and implement 3.6.1 formats/features/reflection through the existing device/graph. Use two RGBA16F moments, two RG16F scratch and three R32F depth/output images; no compiled zero-stub fallback. | Actual selected shaders compile; SPIR-V and device feature/view receipts agree. Precision reference and allocation ledger include the 71.19 MiB nominal payload plus every additional live resource. No second device or hidden SDK synchronization. |
| 11.2 | Implement uniform-solid-angle solar sampling, 8×4 hit/valid packing and single-writer tile conversion. Derive classification/filter 8×8 dispatch separately; remove duplicate clamped tile stores and prove remaining subgroup requirements. | All bit/odd-size/canary cases in 3.6.1 pass. Independent same-measure quadrature converges; zero-angle raw visibility matches Hard. No simulation RNG or racing tile updates. |
| 11.3 | Implement per-receiver correspondence, initialized reset parities, validity-normalized neighborhoods and barrier-safe shared reductions from 3.6.1. Preserve filter/remap and add 3.6.2 moving-caster stage isolation. | Poisoned-history parity tests and mixed-ID quads pass. Static-ground newly-lit/newly-shadowed response meets three-frame/0.10, with continuous motion, thin-shadow deficit and all fixed reference gates. No sky/world ghosts. |
| 11.4 | Measure complete Hard and Soft work on native-resolution real flights, including guide, AS, mask packing, classifier, filters, copies and barriers. Decide each mode's qualification separately. | Soft improves the predeclared native-PCSS defect without reducing ordinary pilot-view readability. Both quality and budget gates pass; a rejected Soft request has an explicit native fallback reason and is never silently reported as RT Hard. |

**Stop:** unsupported shader compilation, incompatible guide semantics or failed quality/budget leaves Soft unqualified. Record the failure. NRD, a custom denoiser, half-resolution tracing and alternate ray rates require a separate scoped design decision; none is an automatic escape from this gate.

### Phase VQ-RT-12 — Integrate preferences, UI and transactional application

**Depends on:** 03/04 and at least one fully proven mode from 09–11. Player-facing enablement requires the final mode/field/device qualification, not just this phase's UI completion.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 12.1 | Add `ray_traced_sun_shadows=false` to the existing display preference schema, graphics-default key set, loading/migration and serialization. Preserve unknown/old profile behavior. Do not alter `shadow_technique`, softness, quality, reconstruction or renderer choice when saving the request. | T10 fresh/legacy/malformed profiles, round-trip, Restore graphics defaults and command-line precedence pass. Default profiles do not allocate RT resources. Source/enum coverage tests use the existing preference test patterns. |
| 12.2 | Add one normal graphics control and a concise effective-state explanation. Show whether the current renderer/device/field/mode can execute the request. Use existing Apply/Keep/Revert behavior and renderer restart flow. | UI reflects saved request and effective state independently. Switching to Compatibility/Mobile preserves the request but displays native effective shadows; cancellation/revert restores both prior request and resource state. No separate RT restart dialog or new quality-preset family. |
| 12.3 | Apply changes as generation transactions: request validation, warmup, valid first result, then activation; reverse through native selection and retirement. Keep ordinary flight responsive while preparing. Treat a requested Soft mode without a qualified denoiser as unavailable. | T10 rapid repeated changes, Escape/back navigation, preview cancellation, world launch during Apply, direct-flight startup and renderer restart cannot expose partially prepared textures or orphan resources. Saved request persistence follows the existing confirmation boundary. |
| 12.4 | Add bounded diagnostics to existing graphics/timing receipts: request/effective/reason, ABI/pin, viewport/sun IDs, scene/history generations, completion status, actual dimensions, ray/mode/coverage and memory/timing counters. Keep technical fields out of ordinary user copy. | T10/T12 receipts distinguish unavailable, preparing, active and fallback frames. Collection is opt-in or follows existing diagnostics policy; no new network telemetry, per-frame string building or expensive status dictionary is required during ordinary flight. |

### Phase VQ-RT-13 — Close recovery, lifetime and Off regressions

**Depends on:** 04 and 09–12. **Output:** tested failure paths, resource retirement and an inert disabled feature.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 13.1 | Exercise supported injected failures: allocation, geometry upload, AS build preparation, shader/descriptor setup, missing guide, stale generation and world destruction during preparation/submission. Use bounded debug hooks; remove production-triggerable injection controls. | T03/T10 native fallback appears at the next safe lighting boundary without invalid resource access. The failure is latched with its original reason; automatic per-frame retries do not occur. Invalid receipts cannot be mistaken for completed RT. |
| 13.2 | Test the pre-activation marker, clean shutdown and next-launch recovery. For genuine device loss or a process crash, use the existing renderer guard/restart path; do not promise in-process restoration of a dead GPU device. Provide explicit retry after recovery. | Interrupted activation never causes a restart loop. Requested preference survives; effective RT remains inhibited until the established recovery/retry boundary. A deliberate test crash is isolated to a disposable profile and records expected exit/log handling. |
| 13.3 | Run the frozen lifetime workload: 100 On/Off cycles, 50 dimension/scale changes, 25 world unload/reload cycles and 30 minutes of representative flight. Include rapid sun/softness changes, alt-tab/minimize and shutdown with work in flight. | T03/T11 validation reports no relevant hazards/leaks. Resource counters return to the documented post-retirement baseline. Retired generations are bounded by actual in-flight work; no queue-idle/device-idle stall is introduced into steady flight. |
| 13.4 | Compare official baseline against custom candidate Off, and the same candidate before/after RT use with Off effective. Inspect scene subscriptions, passes, counters, resident bytes and timing, not just FPS. | Section 4 Off limits pass. RT scene scans, per-frame geometry work, AS/trace/denoise/guide work and RT-owned resident resources are zero after safe retirement. Any retained immutable CPU code/shader cache is separately named and does not disguise live GPU allocations. |

**Stop:** a lifetime/fallback/Off failure blocks every release row sharing that implementation. Do not label such a failure device-specific without a minimized counterexample and independent evidence.

### Phase VQ-RT-14 — Qualify quality, real-flight performance and simulation isolation

**Depends on:** 00.4 and 05–13. **Initial control:** Windows, Forward+/Vulkan, Native, real rendered frames, fixed DRS/latency settings. Hard and Soft are separate rows.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 14.1 | Run T01–T11, the unbiased numerical fixtures and static-ground moving-shadow stages; review native-size sequences and ordinary pilot view. Compare raster Hard/RT Hard and tuned PCSS/RT Soft under frozen conditions. | Fixed analytic/reference/temporal/benefit gates pass, including both lighting-transition directions. Publish masks, boundaries and thin-shadow metrics. No favorable crop or reset conceals continuous-motion lag. |
| 14.2 | Execute each frozen T12 field/model/mode row using 5.2's ten initial runs, submission-aware joins and fixed reducer. Separate unprofiled GPU cost, normal 60 Hz cadence and cold/warm activation; preserve actual caster/wind/internal-pixel identity. | Absolute and paired-uncertainty limits, full live-memory peak and ≥95%/≥90% activity/ROI coverage pass. Required case set and any single extension are explicit; fallback, missing samples or captured-geometry overhead cannot masquerade as performance. |
| 14.3 | Run focused existing simulation, input/replay and aircraft-presentation checks on identical recorded inputs with RT Off/Hard/Soft. Cover pause/unpause, camera changes, crash and replay seek; include AI companions only where that engine is independently qualified. | T15 demonstrates unchanged simulation state within the existing same-build exact/cross-engine tolerance contract. No golden output is regenerated to hide drift. Render-only RNG and frame pacing do not change consumed input steps. |
| 14.4 | Reduce every frozen row into a machine-readable verdict and a short human report. Have a reviewer inspect selected captures, coverage receipts, matching engine identities, failed cases and the raw-to-summary calculation. | The reducer reports `qualified`, `failed`, `blocked` or `not-in-scope` per row, never a blanket GPU-vendor badge. Reviewer finds no unaccounted default changes or omitted failures. Qualification is bounded to the tested revision and configuration. |

### Phase VQ-RT-15 — Qualify Windows packages and the first distributable candidate

**Depends on:** 14 for each advertised mode/field/device row. **This is the core-delivery boundary.** Building a package is authorized implementation work; publishing a release remains a separate release-owner action.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 15.1 | Produce matched editor/templates and packages from the qualified manifest using existing helpers. Apply 3.9 feature-roster/member/loaded-path checks only to applicable SDK variants; preserve stronger existing AMD checks. | T14 checks ABI/imports/notices and completeness before receipts, then detects missing/corrupt listed files. Applicable signature policy and actual loaded identity agree. Clean release-template startup is required; no SDK/engine binaries in Git. |
| 15.2 | Test a clean Windows profile and an upgrade from the current ordinary profile: first boot, renderer choice/restart, request persistence, direct flight, settings revert, clean exit, and restart after interrupted activation. Run from the packaged executable outside the editor. | Native default behavior and fallback remain usable on a non-RT or unsupported device. Qualified RT rows reproduce the fixture and a real flight from the package; no development-only resource path is used. |
| 15.3 | Execute the core rendered matrix on at least one NVIDIA and one AMD RT-capable device before claiming both vendor families. Treat Intel and other available devices as their own rows. Re-run on each actual driver/compiler combination being advertised. | Publish concrete tested device/OS/driver rows. If only one vendor is available, deliver a clearly limited candidate for those passing rows and leave the other vendor blocked. No hardware-name allowlist substitutes for runtime feature/ABI checks. |
| 15.4 | Assemble a reviewable candidate: exact commit/pair/package hashes, supported field/model/mode matrix, user-facing option/fallback description, known limitations and rollback to the ordinary official package. | T14 and section 9's package-relevant checklist items pass for the core matrix; 19 then closes the overall delivery. The candidate remains opt-in and off by default. Notes do not promise universal RT, a frame-rate gain, GI/reflections, or unsupported reconstruction/platform combinations. |

### Phase VQ-RT-16 — Extend Vulkan qualification to Linux and additional devices

**Depends on:** the shared core gates through 15; source/toolchain preparation may run earlier. **Independent extension:** failure does not revoke a separately passing Windows row unless it reveals a shared correctness defect.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 16.1 | Build matched Linux editor/templates from the same reviewed source and patch set with a pinned toolchain. Record loader, ICD, driver, kernel, window system and actual selected physical device. Keep caches/imports/profiles isolated. | T01/T02/T14 pass in the linked package. The runtime device matches the recorded renderer; accidental software Vulkan or another GPU is rejected as the hardware qualification target. |
| 16.2 | Repeat source-specific AS/query/material/guide fixtures and validation on each additional NVIDIA, AMD or Intel device. Include actual descriptor features, scratch alignment, memory limits, MSAA and driver behavior. | No vendor-name inference, unsupported extension assumption or lowered accuracy requirement. Driver-specific workarounds are minimized, documented and retested on the original device. Shared changes reopen impacted core rows. |
| 16.3 | Run the unchanged native-resolution real-flight/quality/lifetime matrix, including foreground/window behavior, pause/minimize and recovery. Use the same input/camera/sun cases and measurement rules. | T03–T12/T15 and all section 4 limits pass per new row. CPU scheduling/window-system differences are reported; driver version is part of the support identity. |
| 16.4 | Export and exercise clean-profile/upgrade packages and rollback. Add only passing rows to the delivered matrix and existing platform instructions. | T14 package behavior matches its measured editor/source identity. Unavailable or failing Linux/vendor combinations remain visibly unqualified; no default renderer or OS minimum changes are introduced implicitly. |

### Phase VQ-RT-17 — Qualify reconstruction and the separate NVIDIA/AMD engine lanes

**Depends on:** the Native control through 14 for the first engine, and a reproducible non-RT baseline editor/package for each separate lane before porting. The integrated RT/reconstruction candidate is built and package-tested within this phase before promotion. **Independent extension:** no RT-only source result grants upscaler interoperability.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 17.1 | Close the exact 3.9 producer/reset prerequisite for each beta2 combination, including FSR2 reset support. Record units/sign/Y/jitter/extent and separate epochs; run denoiser-only, reference-fed reconstruction and combined moving-shadow paths. | T13 passes alternating jitter at two resolutions, known motion, held lighting changes, delayed/failed resets and resize. A mask is added only for a demonstrated provider-specific need. Actual internal/output pixels are always reported. |
| 17.2 | Prepare the separate NVIDIA pin/patch chain and port minimal RT changes by review. Preserve DLSS draw-token/Reflex ownership and companion gate; close 3.9's Streamline feature/member/signature and isolated failure matrix. | Full builds and T01–T11/T14/T15 rerun on that fork. Missing/mismatched DLSS, Reflex/PCL and disabled-feature components have observed receipts; independent RT capability is preserved where valid. No RR/FG support inference. |
| 17.3 | Prepare the AMD SDK 2.4 upscaling candidate independently, using its verified intake and known limitations. Audit RT patch conflicts, guides, storage resources, synchronization and failure/reset paths. | Each AMD reconstruction combination receives its own T13/T14/real-flight row. FSR upscaling availability does not imply FSR Ray Regeneration or an RT-denoiser backend. A pre-existing storage warning is resolved or explicitly blocks the affected candidate. |
| 17.4 | Run paired Native-versus-combination quality/performance and lifecycle qualification at the established output sizes. Add 1440p/4K rows only with explicit budgets; 720p is a final diagnostic, not the primary acceptance target. | Report genuine rendered-frame latency/times separately from any later generated-frame metrics. DRS/Reflex states are fixed and recorded. Passing one lane does not enable the option in the others. Unsupported combinations retain the request and use native shadows with a precise reason. |

**Excluded here:** adding Ray Reconstruction, Ray Regeneration, frame generation, a new AI companion engine baseline, or merging the NVIDIA, AMD and Apple forks into one product. Each requires separate ownership and qualification.

### Phase VQ-RT-18 — Build a separately qualified Metal implementation

**Depends on:** 00.1/00.3, the frozen common scene/lighting/state contracts and the Metal source inventory. Isolated Metal source/fixture work may proceed without a completed Vulkan GPU phase; product qualification requires equivalent scene/ownership/coverage, guide, quality, lifetime and package gates. **Do not route Metal through Vulkan feature bits.**

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 18.1 | Freeze Metal intake/patches/API/OS/SDK and complete the 3.9 retain/replace/re-prove table for 0005/0018/0021/0027. Distinguish API support, required resource features, actual workload and hardware acceleration. | Every diagnostic guard has a disposition; static/constant-shader/missing-guide evidence stays closed. M1 or later-family labels do not replace native producer/timing proof. Ordinary Mobile/standard startup is unchanged. |
| 18.2 | Implement runtime-owned source acquisition/invalidation for already-loaded assets and a rebuild-first retained-generation AS/query route. Replace startup-only capture and cumulative counters with actual live/retiring peak accounting; preserve residency and graph ordering. | T02/T03/T06–T08 prove admitted indexed/deformed/alpha sources, offscreen/cone coverage, multi-frame invalidation/faults and Off release. No diagnostic flag, per-frame idle/readback, static-camera requirement or assumed refit. |
| 18.3 | Implement the same selected-sun lighting seam and early current guides for the admitted Metal renderer. Port and qualify the pinned FidelityFX kernels through a supported shader path or a separately reviewed faithful MSL adapter. Do not feed a shadow mask into MetalFX's HDR radiance denoiser. | T04/T05/T07/T09 compare Metal and Vulkan analytic/reference behavior within the frozen numerical contract. Every adapted shader has provenance and matching inputs/outputs. If the denoiser/guide path is incomplete, Metal Soft stays unqualified; the existing private opaque experiment is not substituted as proof. |
| 18.4 | Run Metal lifetime, Off, quality, simulation-isolation and editor/export package gates on actual Apple devices. Record physical drawable, logical window and internal sizes separately. Use the repository's native Retina policy as the primary Apple target; retain 1080p only as a labeled diagnostic/control. | Native-panel real-flight gates pass with explicit pixel-scaled budgets fixed before measurement. Existing M1 Mobile/Forward+ Off behavior remains intact. Each OS/SDK/device/renderer/MetalFX combination gets its own verdict; `0027` remains closed until actual guide, image, flight and package proof replaces its missing receipt. |

**Stop:** a diagnostic-only producer, unsupported shader translation, missing current guides or unavailable target hardware leaves the Metal row blocked. It must not delay an independently qualified Windows/Vulkan opt-in candidate or change Apple defaults.

### Phase VQ-RT-19 — Close the delivered scope and hand over reproducible evidence

**Depends on:** 15 and every optional row actually included in the delivery. Unexecuted extensions stay blocked or not in scope; they do not acquire a pass through core completion.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 19.1 | Reconcile every subphase/case and device/content/mode row with evidence. State completed work, remaining gates, exclusions and the exact delivered scope. Re-run only impacted gates after final edits. | No `TODO`, unchecked placeholder, stale source pin or “supported” label remains in an included row. Missing evidence produces a blocked verdict. Failed runs and superseding fixes remain discoverable. |
| 19.2 | Update the relevant plan/status index, graphics option documentation, platform/engine intake instructions and third-party notices. Link this authoritative plan rather than copying its contracts into competing documents. | Documentation accurately describes the shipped default, selected-sun effect, supported fields/modes and fallback. Branch-only research uses immutable links and is not represented as main code. |
| 19.3 | Prepare a focused PR or review bundle of implementation changes with package/evidence identities, regression impact and rollback. Keep implementation and qualification evidence in their designated homes; retain large captures externally using repository conventions. | A reviewer can reproduce one fixture, one real flight, an unsupported-device fallback, an Off check and package startup from the documented commands without guessing paths or flags. Repository checks pass at the exact proposed merge commit. |
| 19.4 | Apply section 9's completion checklist and issue the final per-row qualification report. Record release-owner disposition separately from technical readiness. | Every advertised row is package-qualified and all shared correctness/Off/physics gates pass. The executing agent reports concrete results and blockers, stops at the authorized delivery boundary, and does not publish or silently broaden the release. |

## 8. Dependency order, parallel work and stopping boundaries

The numbered phases provide ownership and evidence grouping; the explicit dependencies govern execution. In particular, 00.4's candidate-Off control follows the build in 01.4. Do not wait for all of phase 00 before starting the engine build, and do not run later RT-On controls before their feature exists.

| Work group | Earliest valid start | Required completion before promotion |
| --- | --- | --- |
| Baseline and tooling | 00.1–00.3 immediately; official baseline first | Candidate-Off portion of 00.4 after 01.4; no performance verdict before both controls exist |
| Engine and true GPU fixture | 01 after 00.1/00.3; 02 after linked engine | 02 positive/negative/query/SBT/lifetime proof before relying on AS results |
| Policy and inert ownership | 03 after ABI/capability design; pure rules can use mocks | 04 uses the actual renderer/device; mocks cannot qualify GPU lifetime |
| Scene admission | 05 after ownership; 06–08 in that order | Every relevant caster category admitted or explicit whole-region fallback; target field coverage gates before real-flight support |
| Lighting and guides | 09 analytic fixture after 02/04; 10 after its matching depth/light seam | Real-flight 09 needs scene admission; Soft needs 10 and 11 |
| Preferences and recovery | Pure UI/schema tests can start from 03; real application after active mode | 12/13 must pass before qualification or a player-facing enablement |
| First product row | 14 after completed controls/scene/quality/recovery; 15 after its row passes | Native Windows package at the exact tested source/driver/configuration |
| Extra Vulkan platforms | 16 after the shared core; toolchain prep may overlap | Repeat all affected source/GPU/flight/package gates on each included row |
| Reconstruction/forks | 17 after a valid Native control for that exact engine | Own guide, physics, timing, reset, package and content proof; no cross-fork inheritance |
| Metal | Research/build preparation after common scope contracts | All equivalent producer/guide/flight/Off/Retina/package gates before support claims |
| Final delivery | 19 after every included row is package-qualified | Accurate support matrix, reproducible evidence and section 9 checklist |

Use separate agents or branches for disjoint source review, fixture mathematics, material inventory, documentation and platform preparation. One renderer owner integrates shared engine changes. Do not have several agents edit the scene ABI or the same shader simultaneously. GPU benchmarking on a host is serialized through existing admission/queue tools. Code review can parallelize; performance measurement cannot share the device.

### 8.1 Required risk dispositions

| Observed problem | Required disposition | Forbidden shortcut |
| --- | --- | --- |
| Query API still requires SBT | Prove the bounded query-only repair or retain a legitimate pipeline/SBT and capability requirement | Fake nonzero SBT range; assuming Vulkan query capability alone satisfies this Godot implementation |
| Incomplete caster/alpha/deformation coverage | Complete the missing producer/lookup or leave the affected field on native shadows | Opaque vegetation, stale animated BLAS, camera-only caster list, omitted offscreen/cone blocker |
| Current motion/depth contract unavailable | Implement/verify the early guide adapter; leave Soft unavailable meanwhile | Prior-frame vectors, arbitrary linear depth in a projection-depth SDK input, single-frame proof for temporal correctness |
| Peak memory/setup/build cost too high | Reduce proven redundant storage/builds within the same scene contract; remeasure | Hide scratch/retirement bytes, assume refit exists, silently lower resolution/geometry or change physics |
| Soft quality fails | Fix the verified sampler/guide/history/denoiser boundary; retain Native fallback | Compare with deliberately poor native settings, increase rays without updating estimator/budget, switch SDKs opportunistically |
| No measured image benefit | Leave production RT unqualified and report the result | Ship an expensive toggle solely because rays execute |
| Device lost/process crash | Preserve preference, use existing safe restart/recovery and explicit retry | Claim in-process fallback can recover a dead device; retry every frame |
| Hardware unavailable | Complete independent work and mark the exact row blocked | Treat headless/software Vulkan, another vendor or a compile as GPU/product evidence |
| Main/engine drift | Rebase deliberately, record impacted boundaries and repeat their gates | Silently apply outdated snippets, inherit old benchmark numbers or upgrade several SDKs to make patches fit |

After two materially different failed attempts at one gate, preserve both receipts, identify the smallest remaining question, and stop the dependent row. This rule bounds exploratory work; it never turns a failed test into acceptance or prevents completing unrelated authorized work.

## 9. Final acceptance and agent handoff

The executing agent must deliver all of the following for the scope it claims:

- [ ] One authoritative source/engine/template/shader/content identity; all patches ordered and reproducible.
- [ ] Each subphase marked not started, in progress, passed, failed, blocked or not in scope, with an evidence link and reason. “Done” without a proof receipt is invalid.
- [ ] Real query/AS GPU results, including required negative/capacity/synchronization cases; source tests and successful compilation remain separately labeled.
- [ ] Exact native shadow ownership, selected-sun direct-light substitution, preserved fade/cues/cloud/other-light behavior and qualified receiver/MSAA semantics.
- [ ] Complete admitted caster geometry, material lookup, alpha/deformation, offscreen solar-cone coverage and live aircraft/part transforms.
- [ ] Correct pinned depth/normal/motion/jitter/packing contract and temporal resets for every Soft row; no unproven guide receipt.
- [ ] Predeclared quality improvement, independently converged reference checks, native-size temporal review and actual activity/ROI coverage above the fixed floors.
- [ ] Paired real-flight GPU/CPU/frame/memory results with the original run roster, raw evidence, uncertainty, failures and separate startup/steady-state numbers.
- [ ] No change to simulation/input/replay semantics, with existing focused checks and same-input Off/On evidence.
- [ ] Default Off, correct saved/effective-state UI, unsupported-device behavior, transactional apply/revert, recovery and bounded safe retirement.
- [ ] Verified Off resources/work and timing before and after active use; lifecycle workload completed on the included implementation.
- [ ] Matched export templates and clean/upgrade packaged executable checks on each advertised OS/driver/device/engine combination.
- [ ] Third-party notices, truthful user documentation, support matrix, ordinary-package rollback and a focused reviewable implementation change.
- [ ] Explicit blocked/unavailable extensions and excluded future effects; release publication remains recorded separately from technical qualification.

### 9.1 Required machine-readable verdict fields

Phase 00 defines the JSON schemas and validates them. At minimum, each verdict contains: `schema_version`, `phase_id`, `case_id`, `status`, `reason`, application commit/dirty-state identity, engine/template/patch/shader hashes, OS/GPU/driver/renderer, requested/effective feature and mode, content/viewport/sun identities, dimensions, scene/history generations, submission/completion evidence, coverage denominator and numerator, sample/run roster, timing/peak-byte results, quality-mask/reference identities, log/error verdict and evidence locations. Include the 3.3.2 feasibility identity, 3.6 format/permutation/guide contract, 3.9 provider/package identities when applicable, and 5.2 query-slot/submission joins, pair order, quantile/RNG definition, interval and extension decision. Missing mandatory values are an error; `null` is allowed only for a documented not-applicable field.

Separate **capability** (the runtime can attempt the workload), **qualification** (this exact row passed), and **effective execution** (this frame actually used valid RT). Qualification restrictions must be representable without replacing runtime feature checks. A newer untested driver can remain capable while losing the claim that it is the measured row; document the product's conservative rollout policy rather than asserting that every driver update breaks or automatically qualifies support.

### 9.2 Implementation completion report format

The final implementation report must state: what is actually playable; exactly which rows are package-qualified; source/package/evidence links; native control versus RT quality and cost; Off and simulation-regression results; unresolved failures/blocked hardware; and the smallest next authorized step. Include real measurements or say unmeasured. Do not restate the plan as if it were implemented.

## 10. Explicitly deferred effects and optimizations

These are follow-up proposals, not hidden completion requirements for optional sun shadows:

| Possible follow-up | New prerequisite before planning implementation |
| --- | --- |
| RT reflections, including water/canopy | A demonstrated raster reflection defect, material/roughness/hit-lighting contract, transparent/refraction policy, separate radiance denoising and real-flight benefit/budget |
| RT ambient occlusion/contact effects | A demonstrated gap remaining after existing AO/contact shadows, distance/scale ownership and proof against double darkening |
| RT GI/path tracing | New indirect-light/material/radiance architecture, a scalable sampling/denoising plan, major memory/performance evidence and explicit product scope approval |
| RT cloud/volumetric shadows | A physical beam-transmission contract with SUN/weather owners; no substitution of cloud image alpha for transmittance |
| Ray Reconstruction/Ray Regeneration/MetalFX radiance denoising | Exact backend/SDK availability, complete radiance/guide producer, license/distribution terms and separate comparative qualification |
| Half-resolution tracing, checkerboarding, adaptive ray rates | Proven full-resolution baseline; a specified estimator/reconstruction and edge/disocclusion error budget that preserves aircraft readability |
| AS refit, compaction, async compute or hardware-specific traversal tuning | A real public/internal execution API, resource/synchronization proof and measured whole-frame benefit; flags and vendor marketing are insufficient |
| Native shadow-map removal in RT mode | Complete receiver/caster/light/failure coverage and new fallback availability proof; cannot remove the only valid fallback to improve V1 timing |
| Longer RT shadow range or other lights | Joint fade/aircraft-cue/light-identity redesign and evidence against double shadow or missing cues |
| XR, multiview, other vehicles, Home/Workshop and photo scenery | Dedicated lifecycle/guide/content/comfort or baked-lighting contracts and separate per-viewport performance gates |

The first implemented feature remains opt-in hybrid sun shadows. A smaller set of honestly qualified rows is a valid delivery. A broad toggle backed by incomplete geometry, hidden raster fallback or unmeasured performance is not.

## Appendix A — Complete GitHub branch inventory

The initial pass enumerated 50 remote heads. A final refresh found two additional branches and one advanced head, giving **52 existing branches before creating `ray-tracing`**. The table freezes that final observed snapshot; it is not a promise that GitHub cannot change afterward. `main` remained at the audited commit. Every row received at least tip-commit/changed-path screening. **Deep** means relevant documents/patches were read; **Runtime** means the current implementation was also examined; **Screen** does not claim semantic review of every unrelated file. **Delta** identifies the newly added/advanced heads receiving a final targeted review. The previous ClearView head was `4c9da3b052f09f0e12eaf508cdb8ed0b732b5952`.

| Branch | Observed commit | Review | Relevance/disposition |
| --- | --- | --- | --- |
| `audit/aircraft-import-closeout-2026-11-17` | [`efc93d079fe856fb727f4f7ca7faac9f9f5d56bc`](https://github.com/bultodepapas/OpenRCsimulator/commit/efc93d079fe856fb727f4f7ca7faac9f9f5d56bc) | Screen | Aircraft import/presentation boundary; no RT runtime implementation inferred. |
| `audit/collision-damage-2026-11-17` | [`2be972a698098b760e564377bd7df1548cfaeb6c`](https://github.com/bultodepapas/OpenRCsimulator/commit/2be972a698098b760e564377bd7df1548cfaeb6c) | Screen | Crash/collision work; preserve simulation and suspend unqualified aftermath. |
| `audit/consolidated-review-2026-11-15` | [`92e426013ebc5b54eba7c7fe6eb7ab0eb01de38f`](https://github.com/bultodepapas/OpenRCsimulator/commit/92e426013ebc5b54eba7c7fe6eb7ab0eb01de38f) | Deep | Consolidated current-state research; graphics detail must not alter collisions. |
| `audit/cpu-gpu-optimization-2026-11-19` | [`dbdd5eddceb4a4e36d58e4b83919303a70707a79`](https://github.com/bultodepapas/OpenRCsimulator/commit/dbdd5eddceb4a4e36d58e4b83919303a70707a79) | Deep | Performance audit F04–F09; actual dimensions, timing scope and graphics pipeline. |
| `audit/fpv-drone-racing-2026-11-16` | [`a92598fd5c69bde3b9e4edcd5267a0be2e3ba91a`](https://github.com/bultodepapas/OpenRCsimulator/commit/a92598fd5c69bde3b9e4edcd5267a0be2e3ba91a) | Screen | Other-vehicle research; FPV remains outside initial content admission. |
| `audit/graphics-performance-technologies-2026-11-15` | [`0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836`](https://github.com/bultodepapas/OpenRCsimulator/commit/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836) | Deep | Principal RT design, Vulkan patches, source tests and fixture handoff. |
| `audit/impact-scoped-local-tests-20261103` | [`031b2888f225c758a4da715a67d72cb97fbdd200`](https://github.com/bultodepapas/OpenRCsimulator/commit/031b2888f225c758a4da715a67d72cb97fbdd200) | Screen | Verification scope/history; use current checked-runner contracts. |
| `audit/mcp-queue-resilience-2026-11-15` | [`4b4a9fe24b8603f54bb94a4a2e772498cc3979b7`](https://github.com/bultodepapas/OpenRCsimulator/commit/4b4a9fe24b8603f54bb94a4a2e772498cc3979b7) | Screen | Host admission/queue behavior; reuse existing infrastructure. |
| `audit/performance-consolidation-2026-11-15` | [`2961387f105b0c362776d2afdb8236eed1593c6e`](https://github.com/bultodepapas/OpenRCsimulator/commit/2961387f105b0c362776d2afdb8236eed1593c6e) | Deep | Historical performance report; measurements cannot qualify current main. |
| `audit/shadows-2026-11-17` | [`f5d3c92059a1de0d5741619e9964449c1cb5f037`](https://github.com/bultodepapas/OpenRCsimulator/commit/f5d3c92059a1de0d5741619e9964449c1cb5f037) | Deep | Shadow source/caster/cost research, compared with main's subsequent fixes. |
| `audit/telemetry-release-readiness-20261118` | [`e9683dcfc12acce33e5e333a63214adcb58c30f1`](https://github.com/bultodepapas/OpenRCsimulator/commit/e9683dcfc12acce33e5e333a63214adcb58c30f1) | Screen | Release/telemetry boundaries; no new RT network telemetry scope. |
| `audit/ugly-stik-flight-physics-2026-11-15` | [`5a37347a7e397d82ff1ebdb97e5dd83fef308bac`](https://github.com/bultodepapas/OpenRCsimulator/commit/5a37347a7e397d82ff1ebdb97e5dd83fef308bac) | Screen | Aircraft physics research; preserve numerical behavior. |
| `audit/windows-testqueue-20261114` | [`7226470ff3feadd3f9a1df79b5b889b8feeade94`](https://github.com/bultodepapas/OpenRCsimulator/commit/7226470ff3feadd3f9a1df79b5b889b8feeade94) | Screen | Windows test execution history; use current queue admission. |
| `ci/local-checks` | [`d48dbeb9f3fc5ec3d798bf04760d6e90fc17f6c3`](https://github.com/bultodepapas/OpenRCsimulator/commit/d48dbeb9f3fc5ec3d798bf04760d6e90fc17f6c3) | Screen | Local verification infrastructure, not GPU evidence. |
| `codex/apple-silicon-native-default-20261113` | [`c6e81947b105c6cd0b8797620ce1f3e8cb9a9e75`](https://github.com/bultodepapas/OpenRCsimulator/commit/c6e81947b105c6cd0b8797620ce1f3e8cb9a9e75) | Screen | Apple defaults; current main's renderer/Retina policy controls. |
| `codex/godot-4-8-beta2` | [`14a43859f8922c412d3dbd728a8ff56648e7fcd3`](https://github.com/bultodepapas/OpenRCsimulator/commit/14a43859f8922c412d3dbd728a8ff56648e7fcd3) | Screen | Upgrade history; main's exact beta2 pin was audited directly. |
| `codex/m1-native-validation-20261106` | [`8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd`](https://github.com/bultodepapas/OpenRCsimulator/commit/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd) | Screen | Historical native validation, not RT flight qualification. |
| `codex/tools-review-20261107` | [`644f4e7370fc4d0cb4efe254b25cebd4ea329b70`](https://github.com/bultodepapas/OpenRCsimulator/commit/644f4e7370fc4d0cb4efe254b25cebd4ea329b70) | Screen | Tool history; current owning READMEs govern commands. |
| `docs/aeris-120-3d-gas-plan-20261115` | [`fb779ba1eefa2c879c5a2891ad4c49a2c38ff0ed`](https://github.com/bultodepapas/OpenRCsimulator/commit/fb779ba1eefa2c879c5a2891ad4c49a2c38ff0ed) | Screen | Vehicle plan; no additional rendering scope. |
| `docs/agent-instructions-audit-2026-11-19` | [`718335245a1822611dbde6725fbf7c31dc59f369`](https://github.com/bultodepapas/OpenRCsimulator/commit/718335245a1822611dbde6725fbf7c31dc59f369) | Delta/deep | Documentation-only instruction audit; optional visuals, unchanged physics and built-in/external Retina policy confirmed. |
| `docs/clarify-asset-licenses-2026-11-16` | [`71df295b572caa97e33cf11de059a07a07c05ff4`](https://github.com/bultodepapas/OpenRCsimulator/commit/71df295b572caa97e33cf11de059a07a07c05ff4) | Deep | Asset/engine/SDK licensing distinctions and notices. |
| `docs/clearview-import-guide` | [`41f35e59d85c741a937cf260e7664457332f28ce`](https://github.com/bultodepapas/OpenRCsimulator/commit/41f35e59d85c741a937cf260e7664457332f28ce) | Delta/deep | Advanced documentation-only head; independent geometry/material/transform validation, with ClearView flight still refused pending qualification. |
| `docs/glider-soaring-plan-20261115` | [`9cfd3aacfd7fa16cf79ca876465e86a2ce78f059`](https://github.com/bultodepapas/OpenRCsimulator/commit/9cfd3aacfd7fa16cf79ca876465e86a2ce78f059) | Screen | Flight-model plan; no solver changes allowed for RT. |
| `docs/senior-agent-orchestration` | [`0342765a2b3c49828b3d37705c3fee44129dbf38`](https://github.com/bultodepapas/OpenRCsimulator/commit/0342765a2b3c49828b3d37705c3fee44129dbf38) | Screen | Agent execution/ownership guidance; current AGENTS.md remains authoritative. |
| `docs/sun-atmosphere-realism-20261115` | [`3c9aa2e981b87349ae3c4c2b4b9e4c60917940d0`](https://github.com/bultodepapas/OpenRCsimulator/commit/3c9aa2e981b87349ae3c4c2b4b9e4c60917940d0) | Deep | SUN-10 beam transmission, atmosphere and lighting ownership. |
| `dt-mac-04n-r1` | [`7dbc30243fd1a9efb5e3152be7ea34011100ca85`](https://github.com/bultodepapas/OpenRCsimulator/commit/7dbc30243fd1a9efb5e3152be7ea34011100ca85) | Screen | Mac delivery history; current package/engine identity retained. |
| `fix/controller-profile-error-reset` | [`f7bb3bdb3e7ed7d2287edcb3ac545589ad1c844c`](https://github.com/bultodepapas/OpenRCsimulator/commit/f7bb3bdb3e7ed7d2287edcb3ac545589ad1c844c) | Screen | Input-profile fix; unrelated to RT settings schema. |
| `fix/external-project-audit-20261115` | [`85faa626be69a11d1c96f9ed9d4c880b97b7bf0f`](https://github.com/bultodepapas/OpenRCsimulator/commit/85faa626be69a11d1c96f9ed9d4c880b97b7bf0f) | Screen | General audit fixes; inspect current integration boundaries instead of merging branch. |
| `fix/fpv-battery-power-2026-11-16` | [`4212dbb1ed518fa30fa5e9dd1529507e92105165`](https://github.com/bultodepapas/OpenRCsimulator/commit/4212dbb1ed518fa30fa5e9dd1529507e92105165) | Screen | FPV power behavior; outside RT runtime scope. |
| `fix/robust-game-bughunt-20261031` | [`da4cff78021a59488ffedee7e0b0d5c3e31d1a13`](https://github.com/bultodepapas/OpenRCsimulator/commit/da4cff78021a59488ffedee7e0b0d5c3e31d1a13) | Screen | Older bug-hunt changes; current main supersedes historical findings. |
| `gh-pages` | [`833d3170e619922f2b9822497135f84155e90d76`](https://github.com/bultodepapas/OpenRCsimulator/commit/833d3170e619922f2b9822497135f84155e90d76) | Screen | Published site branch; no engine/runtime RT source. |
| `guidance/impact-scoped-agent-tests-20261103` | [`83a94873552d00d2109037f03d32a78aacb97785`](https://github.com/bultodepapas/OpenRCsimulator/commit/83a94873552d00d2109037f03d32a78aacb97785) | Screen | Focused verification guidance; no broad suite by default. |
| `integrate/branch-recovery-20261106` | [`cef56fa3ad517ec7078bd1eae05cb9693d5d34ec`](https://github.com/bultodepapas/OpenRCsimulator/commit/cef56fa3ad517ec7078bd1eae05cb9693d5d34ec) | Screen | Integration history; no blanket research-branch merge. |
| `integrate/pr1-controls-and-research` | [`8bf96b54e5ac60fdc25c30721cb73e6710ee4309`](https://github.com/bultodepapas/OpenRCsimulator/commit/8bf96b54e5ac60fdc25c30721cb73e6710ee4309) | Screen | Controls/research integration history; retain main boundaries. |
| `main` | [`e0a733937e255bacfe95ff09db0fb3838697239f`](https://github.com/bultodepapas/OpenRCsimulator/commit/e0a733937e255bacfe95ff09db0fb3838697239f) | Runtime | Deep current source, ownership, settings, shaders, build/intake and verification review. |
| `perf/bounded-memory-reuse-2026-11-07` | [`7171aef8111aa7005267d3eb2bff64caa311ffdb`](https://github.com/bultodepapas/OpenRCsimulator/commit/7171aef8111aa7005267d3eb2bff64caa311ffdb) | Screen | Memory-reuse history; RT lifetime measured independently. |
| `perf/engine-efficiency-20261024` | [`2a1f9d410096642af14be2fdb5fdeee50d4e8b4d`](https://github.com/bultodepapas/OpenRCsimulator/commit/2a1f9d410096642af14be2fdb5fdeee50d4e8b4d) | Screen | Older engine performance work; no imported RT timing claim. |
| `perf/stutter-diagnostics-2026-11-17` | [`6116c77e38d61892e3c70c7bcc409e9df46df2d2`](https://github.com/bultodepapas/OpenRCsimulator/commit/6116c77e38d61892e3c70c7bcc409e9df46df2d2) | Screen | Stutter diagnostics; separate existing baseline noise from new RT cost. |
| `plan/flight-simulator-aircraft-import-2026-11-16` | [`0e8bdd0361e134533d880f967113c8ba137daff0`](https://github.com/bultodepapas/OpenRCsimulator/commit/0e8bdd0361e134533d880f967113c8ba137daff0) | Screen | Import planning; visual geometry/materials require content admission. |
| `plan/multiplayer-zero-budget-2026-11-15` | [`2f656ebf66c450d48cdb1db5e1b3930529f25343`](https://github.com/bultodepapas/OpenRCsimulator/commit/2f656ebf66c450d48cdb1db5e1b3930529f25343) | Screen | Networking scope excluded; rendering remains local and simulation-independent. |
| `plan/photorealistic-flying-sites-2026-11-18` | [`e1cb8f67c3cd5b78a2fa80ca7136dd3341d4ec1a`](https://github.com/bultodepapas/OpenRCsimulator/commit/e1cb8f67c3cd5b78a2fa80ca7136dd3341d4ec1a) | Deep | Implementation contract C04; baked shadows and cue ownership. |
| `plan/radio-display-edgetx-2026-11-18` | [`2e4b6bc06f0519d1ca09afb2d02eba7b4ab0965f`](https://github.com/bultodepapas/OpenRCsimulator/commit/2e4b6bc06f0519d1ca09afb2d02eba7b4ab0965f) | Screen | Radio/display integration; no RT ownership change. |
| `plan/sponsor-decal-workshop-2026-11-18` | [`edd8a476f50410d3583df0f166e4a513a5ef8b8c`](https://github.com/bultodepapas/OpenRCsimulator/commit/edd8a476f50410d3583df0f166e4a513a5ef8b8c) | Screen | Material/decal scope; changing caster-relevant materials invalidates RT generations. |
| `plan/vehicle-selector-performance-2026-11-17` | [`add7ddaeaa47c333ca15fa79d5edb25bbb8778e1`](https://github.com/bultodepapas/OpenRCsimulator/commit/add7ddaeaa47c333ca15fa79d5edb25bbb8778e1) | Deep | Home/preview/projection lifetime and performance; excluded initial viewports. |
| `plan/workshop-aircraft-attachments-2026-11-19` | [`5228fc60d3cbad5bd54ebc6e50db9ea2bdf6e394`](https://github.com/bultodepapas/OpenRCsimulator/commit/5228fc60d3cbad5bd54ebc6e50db9ea2bdf6e394) | Delta/deep | Documentation-only AE-27 proposal; atomic visible assemblies, transforms/materials, observer invalidation and resource lifetime. |
| `release/v0.1.0` | [`0a631b52242cdc5c243668865d4bed3d1e22aa98`](https://github.com/bultodepapas/OpenRCsimulator/commit/0a631b52242cdc5c243668865d4bed3d1e22aa98) | Screen | Historical release; not the implementation baseline. |
| `release/v0.1.1` | [`7302c57242904b014a79084b66011370794a080c`](https://github.com/bultodepapas/OpenRCsimulator/commit/7302c57242904b014a79084b66011370794a080c) | Screen | Historical release; not the implementation baseline. |
| `release/v0.1.7` | [`98d98522aad4aeb33148bdd1c20db0ce5275a0ec`](https://github.com/bultodepapas/OpenRCsimulator/commit/98d98522aad4aeb33148bdd1c20db0ce5275a0ec) | Screen | Historical release; not the implementation baseline. |
| `research/agent-storage-lifecycle-2026-11-15` | [`066b57097f539c6800315c915d1ee29469902bd2`](https://github.com/bultodepapas/OpenRCsimulator/commit/066b57097f539c6800315c915d1ee29469902bd2) | Deep | Storage-lifecycle research; no runtime renderer implementation to adopt. |
| `research/github-updates-20261117` | [`048e85ede5b660db3a3a905c90db082b9a418e0b`](https://github.com/bultodepapas/OpenRCsimulator/commit/048e85ede5b660db3a3a905c90db082b9a418e0b) | Deep | Desktop delivery research; preserve package identity and updater ownership. |
| `research/jet-afterburner-2026-11-15` | [`324416ebbdba0e0246324a951a4331d135054c73`](https://github.com/bultodepapas/OpenRCsimulator/commit/324416ebbdba0e0246324a951a4331d135054c73) | Deep | Additive plume/transparency and effect ownership; native non-caster semantics. |
| `setup/coderabbit-oss-review` | [`8a67da2845383cded6fd754e881f27325d9bb35b`](https://github.com/bultodepapas/OpenRCsimulator/commit/8a67da2845383cded6fd754e881f27325d9bb35b) | Screen | Review automation setup; not rendering capability evidence. |

Branch names are discovery aids; immutable commit links above and Appendix B's paths establish provenance. The final plan branch is new work based on main, not a merge of the research branches.

## Appendix B — Repository evidence and source provenance

### B.1 Principal RT research branch

All links in this subsection are pinned to `0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836`, the audited graphics-performance branch. These files are **branch evidence**, not files assumed to exist on the main baseline.

| Document or patch | What it contributes |
| --- | --- |
| [Research index](https://github.com/bultodepapas/OpenRCsimulator/blob/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836/docs/research/graphics-performance-2026-11-15/README.md) | Study map and the distinction between investigated technologies and implemented features. |
| [04 — Ray tracing in Godot](https://github.com/bultodepapas/OpenRCsimulator/blob/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836/docs/research/graphics-performance-2026-11-15/04-ray-tracing-in-godot.md) | Low-level engine API, effect choices and integration constraints. |
| [10 — Reflex and ray integration](https://github.com/bultodepapas/OpenRCsimulator/blob/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836/docs/research/graphics-performance-2026-11-15/10-reflex-and-ray-integration-design.md) | Separate latency and RT ownership; no inferred RT support from Reflex. |
| [14 — RT quality and delivery](https://github.com/bultodepapas/OpenRCsimulator/blob/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836/docs/research/graphics-performance-2026-11-15/14-ray-tracing-quality-and-delivery-plan.md) | Quality-first hybrid design, measured budgets and real-flight release gates. |
| [15 — Fixture handoff](https://github.com/bultodepapas/OpenRCsimulator/blob/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836/docs/research/graphics-performance-2026-11-15/15-ray-tracing-fixture-handoff.md) | Bounded next-engine work, prerequisites and outstanding GPU validation. |
| [NVIDIA/AMD integration guide](https://github.com/bultodepapas/OpenRCsimulator/blob/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836/docs/research/graphics-performance-2026-11-15/ray-tracing/01-nvidia-amd-integration-guide.md) | Distinct device/engine lanes, capability and SDK limits. |
| [Clouds, materials and water](https://github.com/bultodepapas/OpenRCsimulator/blob/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836/docs/research/graphics-performance-2026-11-15/ray-tracing/02-clouds-materials-and-water.md) | Content and signal ownership; preserve clouds/transparency/water until separately qualified. |
| [Vulkan fixture work order](https://github.com/bultodepapas/OpenRCsimulator/blob/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836/docs/research/graphics-performance-2026-11-15/ray-tracing/03-vulkan-fixture-work-order.md) | Exact fixture sequence and source-to-GPU proof boundary. |
| [Recorded prerequisite validation](https://github.com/bultodepapas/OpenRCsimulator/blob/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836/docs/research/graphics-performance-2026-11-15/evidence/vulkan-prerequisite-validation.json) | Six source-bound test methods and affected translation-unit compilation; no full-engine GPU/image/package qualification. |
| [Vulkan patch handoff](https://github.com/bultodepapas/OpenRCsimulator/blob/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836/research/performance/graphics_handoff/vulkan/README.md) | Patch provenance, validation limits and intended intake. |
| [0001 — AS addresses and creation](https://github.com/bultodepapas/OpenRCsimulator/blob/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836/research/performance/graphics_handoff/vulkan/0001-as-address-and-creation.patch) | Correct native AS address acquisition, creation failure and generic buffer cleanup; requires non-RT regression coverage. |
| [0002 — TLAS instance reservation](https://github.com/bultodepapas/OpenRCsimulator/blob/0ccfa7d11cb5f24f8d84cf71738a7cdd4e8a6836/research/performance/graphics_handoff/vulkan/0002-tlas-instance-reservation.patch) | Checked reservation arithmetic, fresh-buffer usage accounting and prevalidation/dependency transaction. |

### B.2 Current main and related branch documents

Main-relative links below refer to the pinned application baseline unless the executing agent deliberately updates it. Keep the drift record when a later main changes their conclusions.

| Evidence | Design consequence |
| --- | --- |
| [AGENTS.md](../../AGENTS.md), [CLAUDE.md](../../CLAUDE.md), [subagent guidance](../SUBAGENTS.md), [CONTRIBUTING](../../CONTRIBUTING.md) | Existing ownership, focused tests, source identity, preservation of simulation and review responsibilities. |
| [STACK](../STACK.md), [shadow plan](shadows.md), [advanced graphics plan](advanced-graphics.md) | Runtime boundaries, current shadow controls, renderer/settings integration and track ownership. |
| [Current shadow closeout](../research/visual-quality-implementation/VQ-04b/shadow-audit-closure-2026-11-18/README.md) | Dated RTX 3090/M1 measurements and repaired shadow behavior; fixture scope and unresolved limitations remain explicit. |
| [Native NVIDIA/AMD guide](../../tools/graphics/native/README.md), [MetalFX guide](../../tools/graphics/metalfx/README.md) | Reproducible intake, exact fork/SDK pairs, ordered patches, diagnostics and missing qualification. |
| [Graphics tool ownership](../tools/graphics.md), [shared verification](../tools/shared.md), [shadow tools](../../tools/shadows/README.md), [performance evidence](../../research/performance/README.md) | Reuse checked runners/queue/capture/collection and preserve raw-to-verdict provenance. |
| [CPU/GPU audit](https://github.com/bultodepapas/OpenRCsimulator/blob/dbdd5eddceb4a4e36d58e4b83919303a70707a79/docs/research/performance-audit-2026-11-19/README.md) | Historical F04–F09 dimension/reconstruction/timing findings. Recheck actual output/drawable/internal sizes on current main; do not claim historical policy estimates are current measured GPU results. |
| [Photo-scenery implementation contracts](https://github.com/bultodepapas/OpenRCsimulator/blob/e1cb8f67c3cd5b78a2fa80ca7136dd3341d4ec1a/docs/research/photorealistic-flying-sites/2026-11-19/implementation-contracts.md) | C04 baked-shadow and aircraft-cue ownership; photo scenery is outside initial RT admission. |
| [SUN-10 investigations](https://github.com/bultodepapas/OpenRCsimulator/blob/3c9aa2e981b87349ae3c4c2b4b9e4c60917940d0/docs/research/sun/SUN-10/investigations.md) | Beam transmission is distinct from displayed cloud alpha; keep sun/cloud ownership intact. |
| [Afterburner graphics study](https://github.com/bultodepapas/OpenRCsimulator/blob/324416ebbdba0e0246324a951a4331d135054c73/docs/research/afterburner/2026-11-15/round2/graphics.md) | Additive transparent plume semantics; no opaque RT caster by default. |
| [Consolidated project state](https://github.com/bultodepapas/OpenRCsimulator/blob/92e426013ebc5b54eba7c7fe6eb7ab0eb01de38f/docs/research/project-audit-2026-11-09/current-state-2026-11-15.md) | Historical ownership/integration constraints, including independent collision versus visual detail. |
| [Vehicle-selector code study](https://github.com/bultodepapas/OpenRCsimulator/blob/add7ddaeaa47c333ca15fa79d5edb25bbb8778e1/docs/research/menu-investigations/vehicle-selection-2026-11-17/deep-code-analysis.md) | Home/preview/projector lifetimes and cost; these viewports stay raster initially. |
| [Asset licensing guidance](https://github.com/bultodepapas/OpenRCsimulator/blob/71df295b572caa97e33cf11de059a07a07c05ff4/docs/ASSET-LICENSING-AND-PARTNERSHIPS.md) | Engine, code, SDK and assets have separate distribution terms; retain actual notices. |
| [Storage research](https://github.com/bultodepapas/OpenRCsimulator/blob/066b57097f539c6800315c915d1ee29469902bd2/docs/research/agent-storage/README.md) | Reviewed research branch; storage infrastructure is not an RT runtime dependency. |
| [Desktop update research](https://github.com/bultodepapas/OpenRCsimulator/blob/048e85ede5b660db3a3a905c90db082b9a418e0b/docs/research/desktop-delivery-investigations/DT-UPD-00/README.md) | Preserve updater/package identity and use current delivery owners; do not build a new updater for RT. |
| [Earlier performance report](https://github.com/bultodepapas/OpenRCsimulator/blob/2961387f105b0c362776d2afdb8236eed1593c6e/docs/research/performance-report-2026-11-09.md) | Historical optimization evidence; not an RT support or current-main benchmark. |
| [AE-27 aircraft attachment plan](https://github.com/bultodepapas/OpenRCsimulator/blob/5228fc60d3cbad5bd54ebc6e50db9ea2bdf6e394/docs/plans/workshop-aircraft-attachments.md) | Late research addition. If adopted in the implementation baseline, ordinary-flight installed visual assemblies join the same transaction/transform/material/bounds/caster lifecycle; this plan does not implement AE-27. |
| [Refreshed ClearView import plan](https://github.com/bultodepapas/OpenRCsimulator/blob/41f35e59d85c741a937cf260e7664457332f28ce/docs/plans/clearview-aircraft-import.md) | Preview/drafts do not imply flight or RT admission. Validate hierarchy, units, handedness/winding, normals/UV/opacity, pivots and independent instances; refuse unsupported transforms. |
| [Instruction-audit branch](https://github.com/bultodepapas/OpenRCsimulator/blob/718335245a1822611dbde6725fbf7c31dc59f369/AGENTS.md), [its Apple policy clarification](https://github.com/bultodepapas/OpenRCsimulator/blob/718335245a1822611dbde6725fbf7c31dc59f369/docs/plans/apple-silicon-performance.md) | Late documentation-only delta; confirms scalable optional graphics and native physical pixels for built-in and external Retina displays. Current main rules remain the execution authority until deliberately updated. |

### B.3 Engine lane identities and evidence limits

| Lane | Audited identity | Evidence boundary |
| --- | --- | --- |
| Official beta2 base | Godot `cafc17a192acf67903910a68aeb3c076c0907a4b`; source ZIP SHA-256 recorded by the MetalFX intake: `83cf257bc53427f2b1ea07015dbad298252c20546e916c5daa30a1cf78c45c1e` | Source pin for the first Vulkan candidate; existing source patches do not qualify a linked RT engine. Revalidate consumed artifact hashes. |
| NVIDIA native candidate | Fork `135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`; source ZIP `8f9d9604270ccca92d14cc57afca142079476cbe050e0486a90b84da17ce907a`; Streamline 2.11.1 archive `0c1d562e59557434cabfb8997157cb8c04fc7d23f077c8bdf5260975b73dfb89` | Older fork with its own complete patch order, matching templates/imports and companion gate. DLSS/Reflex results do not prove RT/Ray Reconstruction. |
| AMD SDK 2.4 candidate | Commit `7539ae8b6568ad29ed78a753404351daf3b5cca7`; archive `27120e3bbe0d0b30213825ad40f19077563f04f04572e252109a392d5fb522cb`; recorded tree digest `3215b1a40247bf042f64c76a846ab495979ba15d26b14e51659f57ac8caf2f9e` | Separate reconstruction intake, not the shadow-denoiser source choice or an automatic Vulkan Ray Regeneration backend. |
| Metal experimental patches | Beta2 base; ordered `0001`–`0019` stack with later extension patches. `0027` catalog digest `a4754c95a2ed6163f3648562287155e89f11001c8cb3bd5281dab178d5cd9707` | `0005` bounded query/readback; `0018` diagnostic scene capture; `0021` ABI; `0027` closed source draft with `GUIDE_INPUT_RECEIPT_IMPLEMENTED=false`. A separate private opaque/denoiser experiment does not close this missing normal-flight receipt. |

Do not reconstruct a patch order from the short table. Read the corresponding intake README/manifest, verify every prerequisite and archive, and record the exact ordered list consumed. No SDK/fork is installed or newly built by this documentation change.

## Appendix C — Official documentation, guides and firsthand engineering discussions

These sources informed the architecture and the questions the implementation must prove. Rolling documentation and forum reports are contextual; exact inspected source pins take precedence for the chosen engine/denoiser. A benchmark or demo from another project is not OpenRC qualification. Community statements are treated as dated firsthand reports where applicable, not as substitutes for API contracts.

| ID | Source | Use in this plan |
| --- | --- | --- |
| C01 | [Godot 4.8 beta 2 announcement](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/) | Engine release identity; the implementation still pins the full commit. |
| C02 | [RenderingDevice reference](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html), with the exact engine files linked in section 2.2 | Low-level experimental AS/query/pipeline surface; API availability alone is not a game effect. |
| C03 | [CompositorEffect reference](https://docs.godotengine.org/en/stable/classes/class_compositoreffect.html) | Callback timing and guide requests; pinned source establishes that ordinary motion output is too late for the proposed pre-opaque temporal pass. |
| C04 | [RenderSceneBuffersRD reference](https://docs.godotengine.org/en/stable/classes/class_renderscenebuffersrd.html) | Internal versus target buffers/dimensions and resource ownership. |
| C05 | [Godot advanced postprocessing and reversed-Z reconstruction](https://docs.godotengine.org/en/4.3/tutorials/shaders/advanced_postprocessing.html) | Depth is nonlinear/reversed-Z; verify the current pin and the denoiser adapter's exact convention. |
| C06 | [VK_KHR_ray_query](https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_ray_query.html), [rayQuery feature](https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDeviceRayQueryFeaturesKHR.html) | Queries in existing shader stages; distinguish native Vulkan requirements from Godot's inspected SBT restriction. |
| C07 | [VK_KHR_acceleration_structure](https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_acceleration_structure.html), [AS device properties](https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDeviceAccelerationStructurePropertiesKHR.html), [AS destruction](https://docs.vulkan.org/refpages/latest/refpages/source/vkDestroyAccelerationStructureKHR.html) | Dependencies, device limits, scratch alignment and safe destruction after completed use. |
| C08 | [Vulkan ray tracing guide](https://docs.vulkan.org/guide/latest/extensions/ray_tracing.html) | Separation of acceleration structures, query and pipeline extensions. |
| C09 | [Khronos alpha-tested ray-query shadow tutorial](https://docs.vulkan.org/tutorial/latest/courses/18_Ray_tracing/05_Shadow_transparency.html) | Candidate-hit geometry/UV/material lookup and non-opaque traversal. Its simplified mip-zero example is not OpenRC's distance-quality policy. |
| C09a | [Vulkan storage images and texel buffers](https://docs.vulkan.org/guide/latest/storage_image_and_texel_buffers.html) | Storage-image shader formats and bound view formats must have the specified compatibility; compiling an SDK shader does not validate its host allocations. |
| C10 | [AMD FidelityFX Denoiser overview/license](https://gpuopen.com/fidelityfx-denoiser/), [Denoiser 1.3 technique documentation](https://gpuopen.com/manuals/fidelityfx_sdk/techniques/denoiser/) | Selected MIT shadow-denoising candidate and documented signal contract; shader/resource adaptation remains necessary. |
| C11 | [Pinned SDK v1.1.4 denoiser public header](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/include/FidelityFX/host/ffx_denoiser.h), [pinned host orchestration](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/src/components/denoiser/ffx_denoiser.cpp) | Exact Denoiser 1.3.0 identity, inverted-depth flag, resources, first-frame behavior and missing public shadow-reset parameter. |
| C12 | [Pinned classifier](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/include/FidelityFX/gpu/denoiser/ffx_denoiser_shadows_tileclassification.h), [GLSL callbacks](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/include/FidelityFX/gpu/denoiser/ffx_denoiser_shadows_callbacks_glsl.h), [filter](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/c6efa6bf7f2027b3ec94f28578bb5965eabb9e55/sdk/include/FidelityFX/gpu/denoiser/ffx_denoiser_shadows_filter.h) | Source-specific mask polarity, projection depth, motion/normal conventions, validity/reset adaptations, FP16 stub and output remap concerns. |
| C13 | [NRD integration guide](https://github.com/NVIDIA-RTX/NRD/blob/master/README.md), [NRD license](https://github.com/NVIDIA-RTX/NRD/blob/master/LICENSE.txt) | Alternative SIGMA signal/hit-distance requirements and distinct license. An alternative requiring a nearest blocker cannot reuse binary first-hit termination unexamined. |
| C14 | [Apple supportsRaytracing](https://developer.apple.com/documentation/metal/mtldevice/supportsraytracing), [Metal acceleration-structure ray tracing](https://developer.apple.com/documentation/metal/ray-tracing-with-acceleration-structures) | Native Metal API capability and AS workflow, separate from Vulkan and from proof of hardware acceleration/performance. |
| C15 | [Explore GPU advancements in M3 and A17 Pro](https://developer.apple.com/videos/play/tech-talks/111375/) | Apple GPU family and hardware ray tracing background; no automatic product allowlist. |
| C16 | [MetalFX denoised-scaler support query](https://developer.apple.com/documentation/metalfx/mtlfxtemporaldenoisedscalerdescriptor/supportsdevice%28_%3A%29), [Apple WWDC26 session 359](https://developer.apple.com/videos/play/wwdc2026/359/) | Radiance/guide reconstruction and availability are distinct from the single-channel shadow signal. |
| C17 | [Godot issue 121286](https://github.com/godotengine/godot/issues/121286), [fix 122051](https://github.com/godotengine/godot/pull/122051) | Firsthand feature-enable defect and fix history. Rechecked beta2 source; do not copy the historical 4.7 failure as a current fact. |
| C18 | [Godot AS refit proposal 15180](https://github.com/godotengine/godot-proposals/issues/15180) | Firsthand discussion of missing update/refit functionality. The exact inspected API and build implementation determine current budgeting. |
| C19 | [Godot ray tracing engineering discussion 5162](https://github.com/godotengine/godot-proposals/discussions/5162) | Maintainer/contributor discussion of low-level plumbing, bindless limitations and native Metal direction. Dated comments are checked against source rather than treated as a release matrix. |
| C20 | [Godot Forum: NVIDIA path-tracing demonstrations](https://forum.godotengine.org/t/godot-rtx-nvidia-fork-path-tracing/135657) | Firsthand demo/development reports and links; useful for identifying integration risks, not evidence that an OpenRC export or non-NVIDIA denoiser is qualified. |
| C21 | [Antonio Caggiano's GodotCon 2026 RT integration talk](https://talks.godotengine.org/godotcon-ams-2026/talk/JDYVQ3/), [LunarG presentation](https://www.lunarg.com/wp-content/uploads/2026/02/Antonio-Caggiano-LunarG.pdf) | Implementer explanation of Godot's native Vulkan RT plumbing and tool-facing APIs. |
| C22 | [NVIDIA Godot source](https://github.com/NVIDIA-RTX/godot), [community RTX fork](https://github.com/bailaiOWO/rtx-godot), [experimental Metal path-tracing source](https://github.com/josephsmithberger/godot-metal-path-tracing) | Alternative implementations screened for architecture/evidence limits. None is adopted wholesale or assumed compatible with the project's engine/template/import contract. |
| C23 | [NVIDIA practical RT optimization guide](https://developer.nvidia.com/blog/practical-tips-for-optimizing-ray-tracing/) | Geometry, AS and traversal tradeoffs; optimizations require measured whole-frame benefit and correct offscreen coverage. |
| C24 | [Apple Metal window management](https://developer.apple.com/documentation/metal/managing-your-game-window-for-metal-in-macos), [CAMetalLayer drawableSize](https://developer.apple.com/documentation/quartzcore/cametallayer/drawablesize) | Distinguish logical UI/window dimensions from actual drawable pixels and the repository's Retina target policy. |
| C25 | [Godot large-world precision documentation](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html) | CPU/render precision boundaries; RT does not justify changing the simulator's numerical or coordinate contracts. |

**Planning verification:** this document's work consists of repository/branch/source inspection, official and firsthand external research, independent design criticism, dependency/contract reconciliation and documentation checks. No new RT engine build, GPU fixture, performance measurement, gameplay validation or release package was executed for this planning commit. All phase execution and qualification results remain to be produced.


