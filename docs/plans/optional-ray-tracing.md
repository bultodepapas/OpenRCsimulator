# Optional ray tracing: implementation and qualification plan

**Status:** proposed implementation contract; no production RT feature is implemented or qualified by this document.  
**Research date:** 19 November 2026, America/Bogota.  
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
2. Identify reusable geometry by mesh resource plus surface, topology/vertex generation and caster-material variant. Share a BLAS across rigid instances of identical geometry. Distinct hinge parts use the actual visible articulation transforms; movement alone does not rebuild their vertex data.
3. Static geometry enters once during staged preparation. Maintain dirty sets for transforms, topology, deformation, material/alpha, visibility, LOD, instance count and layer/cull-mask changes. A normal RT-off flight never populates these sets through an RT-specific scene walk.
4. Use engine-owned scene/storage information and the same native caster rules as the selected sun. Static CPU mesh extraction is permitted once when no reusable AS-ready stream exists; charge it to loading. Ordinary raster vertex buffers must not be assumed to have AS-input/device-address usage. Build dedicated verified buffers where necessary.
5. Initial implementation uses real `blas_build`/`tlas_build` operations. Reuse unchanged BLAS; rebuild a TLAS when its instance state changes. Deformation requires a measured same-frame BLAS rebuild or native fallback. A future refit/compaction change needs its own API, barriers, quality/performance proof and receipt.
6. A camera-frustum list is not a sun-caster list. Include objects outside the view that can shadow visible receivers. First use a conservative **whole relevant sun region** admission decision: sweep receiver bounds through the registered scene bounds over the union of all directions in the finite solar disk, the full validated `t_max`, and receiver/origin uncertainty. A center-ray sweep alone is insufficient for Soft. Derive `t_max` from the complete registered caster bounds, not the camera far plane; invalidate coverage when direction, angular size, bounds or the view changes. A ray miss is never proof that omitted geometry cannot cast.
7. When capacity, memory, geometry support, readiness or coverage is uncertain, use native shadows for the whole affected viewport. Per-receiver optimization is allowed later only with a conservative coverage structure proving that unsupported casters cannot affect that receiver. Never truncate an instance list and call it complete.
8. Preserve visibility, `cast_shadow`, layers, light masks, front/back-face semantics, negative/nonuniform transforms, LOD transitions, material overrides and alpha mip/sampler behavior. Collision proxies are not substitutes for visual shadow geometry without an explicit silhouette-error qualification.
9. Match the rendered coordinate convention. Do not introduce a new origin-rebasing system or change physical coordinates. If the renderer's origin/projection changes, change both RT and raster inputs consistently and invalidate history.
10. Preserve all inputs used by in-flight builds/traces. Changing or freeing a mesh, material, texture, BLAS or TLAS schedules retirement; it cannot invalidate a previously submitted frame. Frame-count delays are not a substitute for the renderer's real completion/fence mechanism.

**Alpha lookup prerequisite:** ray-query candidate IDs and barycentrics must resolve through a generation-matched GPU table to the correct surface indices, vertex UVs, material parameters, texture and sampler. Use a bounded dense instance index, explicit surface/primitive ranges and material IDs; validate the 24-bit Vulkan instance custom-index limit before upload. Shared BLAS does not imply identical instance material overrides. The initial Vulkan adapter uses fixed-capacity, fully populated texture/sampler descriptor arrays with an immutable descriptor generation while in flight. Check and enable any required sampled-image non-uniform indexing feature and all per-stage/set limits; do not assume it follows from `rayQuery`, or require update-after-bind/partially-bound features unnecessarily. If the table or device cannot represent the field, select native fallback. Register/retire texture and material generations with the same completion ownership as geometry. Alpha evaluation in compute has no implicit raster derivatives: phase 08 must define a conservative ray-cone/footprint-to-LOD policy, test it against native shadow silhouettes at distance, and cover wrap, filtering, mip levels and cutoff/hash behavior. Do not select mip zero everywhere as an unmeasured shortcut.

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

### 3.6 Hard and soft sampling

**Hard prototype:** one deterministic ray toward the sun center, no temporal accumulation. Terminating at the first accepted opaque/alpha-approved hit is sufficient for binary visibility. Record `t_min`, `t_max`, culling and origin-offset policy. Derive a scale-aware offset from geometric position/normal error; do not hide self-intersections with a large constant bias. Test millimeter-scale gear gaps, grazing surfaces and two-sided leaves.

**Soft mode:** sample the sun's angular disk once per covered pixel per real rendered frame. The existing `0.53°` full angular diameter corresponds to a `0.265°` half-angle, approximately `0.004625` radians. Read the effective light angular size; do not hard-code this when the policy changes. A degree value must never be passed to an SDK parameter that expects radians or an angular radius. Preserve the direct-light energy/BRDF contract; only visibility sampling changes.

Use a pinned, licensed deterministic sample sequence with per-pixel decorrelation. The index advances with real RT submissions, not simulated ticks or generated frames. Reset/seed it reproducibly for qualification. Do not add a second ray per pixel to the FidelityFX packed binary-mask contract without a separately specified estimator and adapter change.

The denoiser input specification must include hit-mask bit order, tile edges, valid-pixel mask, the pinned algorithm's exact depth representation, decoded normals, motion direction/units, projection/jitter convention, inverse matrices and history identity. The FidelityFX shadow implementation reconstructs/reprojects from projection-space depth and provides an inverted-depth configuration; do not substitute linear view depth for that input. Preserve Godot's reversed-Z depth where the validated adapter supports it, select the matching inverted-depth option, and supply matching inverse/projection matrices. Keep any linear depth needed for a separate validation step in a separately named resource. Do not silently substitute normal-map normals for required geometric normals or vice versa.

**Pinned first adapter:** FidelityFX SDK `v1.1.4`, commit `c6efa6bf7f2027b3ec94f28578bb5965eabb9e55`, embedded Denoiser `1.3.0`. This pins the shadow kernels; it does not select or merge the project's separate AMD SDK 2.4 upscaling candidate. The existing native intake records archive SHA-256 `9a19e1f20bf269163f052186ed563209c5a1d0f7b1cf7e567e643dee6cc61179`; recheck that exact artifact on acquisition and record the consumed file hashes. Source references are in Appendix C. Phase 11 must address the following inspected-source details explicitly:

| Adapter boundary | Required implementation |
| --- | --- |
| Mask polarity/layout | External input bit `1` means an occluder hit; the preparation stage converts to the internal lit mask. Lane order is `(y % 4) * 8 + (x % 8)`. Prove polarity with constant and partial-tile fixtures. |
| Depth and matrices | Supply device/NDC depth in `[0,1]`, the inverted-depth option for reversed-Z, and matching projection/inverse/reprojection matrices with verified packing and Y orientation. A depth format that compiles is not proof of reconstruction correctness. |
| Motion and normals | The inspected classifier uses `previous_uv = current_uv + velocity`; provide previous-minus-current normalized UV after its configured scale/Y convention. Normals and reconstructed positions/eye must share world-space coordinates. Verify jitter removal/application exactly once. |
| Moving receiver depth | Stock camera reprojection predicts prior depth from the current position; 2D object velocity alone does not correct depth motion. Add a current-sample previous-position/depth correspondence guide and adapt history rejection, or conservatively reject history for those receivers until proven. Test view-axis motion with zero XY velocity and depth-overlapping moving surfaces. Persistent rejection is acceptable only if the final quality/temporal gates still pass. |
| Explicit history reset | The public shadow dispatch lacks a reset parameter. Implement an adapter-owned epoch reset, first-frame/partial-invalid handling and initialized previous-depth/moment/history storage, or safe context recreation. Do not read uninitialized previous depth because a first-frame flag exists elsewhere. Retire old contexts/resources safely. |
| Receiver validity | The stock receiver predicate checks depth range, not OpenRC's material/coverage validity. Adapt classification, history and filtering so unsupported receivers/partial tiles neither contribute samples nor contaminate neighboring supported pixels. |
| Shader permutations/formats | Verify actual storage-image declarations versus bound formats, FP16 and subgroup requirements. The inspected non-`FFX_HALF` filter helpers contain compile-only zero-return stubs: compiling that permutation is not a usable f32 fallback. Require the proven half path or implement/qualify a real f32 adapter before enabling Soft. |
| Concrete format/dispatch review | The inspected GLSL callbacks use `rg32f`/`rgba32f` for resources whose stock host path allocates lower-precision formats. Choose explicitly compatible shader/view formats and charge their actual bytes. Also derive each pass's dispatch from its shader: packed rays use 8×4 tiles, while inspected classification/filter entry points use 8×8 workgroups. The stock host's common 8×4 dispatch arithmetic is a source-level red flag requiring GPU proof, not a rule to copy. Validate odd extents, last tiles and out-of-bounds guards in emitted SPIR-V and on the real device. |
| Filter transfer | The final filter includes a contrast remap. Visibility is consumed without sRGB/color-transfer encoding, but do not assume the result is an unbiased arithmetic mean. The independent visibility reference and fixed error gates judge the final output, including this remap. |

These are bounded adapter changes within phase 11. Do not discard the selected denoiser or tune the acceptance masks to conceal a failed boundary.

### 3.7 Frame order and temporal data

Required dependency order for Soft:

1. Publish the final displayed scene/part transforms and geometry generations for this real frame.
2. Upload/deform dirty geometry; build required BLAS; build TLAS. Preserve renderer graph dependencies.
3. Produce matching depth/normal/receiver-validity data and **current-frame** motion guides before denoising.
4. Trace sun visibility; convert to the pinned denoiser's packed input; reject invalid pixels/history.
5. Denoise in internal-render space; publish the current frame's mask and validity to the selected-sun lighting seam.
6. Run opaque lighting, existing sky/transparency/postprocessing, then the separately selected reconstruction path and UI.
7. Record submission/completion separately and retire resources only when safe.

Godot's stock motion pass is later than step 3. Phase 10 must implement a small explicit early velocity/validity producer, reusing the exact current/previous displayed transforms and shader motion conventions. Start with rigid and static admitted geometry. Include animated vertices only after their previous-position producer is proven. Do not use last frame's velocity texture and label it current. Do not change the existing upscaler's velocity output to make the RT path work.

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

## 4. Performance and quality gates

These are **proposed acceptance limits**, not measured results or a promise that the current scene fits them. Freeze them with the RT-00 baseline. A stricter existing platform gate wins. Do not relax them after seeing candidate results.

| Gate | Initial core requirement |
| --- | --- |
| Primary desktop resolution | Actual 1920×1080 output/drawable; first control has internal 3D and RT at 1920×1080. Record logical UI, window, drawable, internal 3D and RT dimensions independently. A launch argument alone is not proof. |
| Apple Silicon Retina exception | Qualify the physical panel's native pixel resolution and actual drawable/display mode, with internal 3D/RT pixels reported separately. A 1080p M1 result does not qualify a Retina panel. Follow the current Apple plan. |
| Target frame cadence | Real rendered 60 Hz workload: wall-frame p95 ≤18.333 ms and p99 ≤25 ms as this plan's initial limits; report missed-frame bursts and maximum. If baseline already fails, resolve/attribute it before claiming RT qualification. Generated frames do not count. |
| Whole-effect GPU cost | Paired incremental whole-frame GPU p95 ≤2.0 ms at core 1080p and within actual remaining frame headroom. Include guides, AS work, traversal, denoise, barriers and lighting overhead; never add independent pass p95 values as a substitute. |
| RT CPU cost | Incremental render/application CPU p95 ≤0.25 ms in the matched core workload, with simulation and loading measured separately. No per-frame full scene traversal or mesh readback. |
| Incremental peak GPU memory | ≤128 MiB for the initial 1080p effect, including duplicated geometry, BLAS/TLAS, scratch, guides/history, descriptors and in-flight retirement peak. Keep raster atlas memory in the control. This is the earlier research ceiling adopted as a strict initial gate, not a measured fit. |
| Off overhead | No recurring RT allocation/submission/scan counters. Same-build RT-off wall/GPU p95 increase must be within the larger of 0.10 ms or 1% of the matched control, with a paired uncertainty interval that does not support a larger regression. Also compare the patched engine RT-off with the official control for generic patch regressions. |
| Off retention | RT-owned live resource bytes and live owners return to zero after GPU-safe retirement. Report engine/driver caches separately; they cannot conceal retained RT AS/history/geometry. |
| Useful activity | In the declared daylight real-flight case, RT actually executes in ≥95% of eligible frames and covers ≥90% of each predeclared target receiver ROI. Freeze the denominator from the tape/viewport and only predeclared non-feature intervals such as Home/crash. Unsupported casters, preparing/suspended/failed states and raster fallback remain in the denominator. ROI coverage is valid RT receiver samples divided by all in-scope visible receiver samples across those frames; report empty-ROI frames separately. Requests/allocations are not valid RT output. |
| Hard correctness | Analytic hit/miss, masks and light-identity tests pass exactly away from documented geometric boundaries. Independent CPU reference uses the same geometry with float64 ray/triangle arithmetic; boundary exclusions are fixed before comparison. |
| Soft reference | Compare against a converged many-sample reference from the same geometry/light contract. Double reference samples until mean visibility changes <0.005 and p95 absolute change <0.02 in target ROIs; otherwise the reference is inconclusive. Candidate mean visibility error ≤0.02 and p95 absolute error ≤0.10 outside the predeclared silhouette/disocclusion band. |
| Temporal/readability | No missing wing/gear/hinge silhouette, detached moving shadow, stale-world shadow or persistent trail. After disocclusion, visibility must converge within three real frames to absolute error ≤0.10 in a controlled static-light fixture. Ordinary pilot-view video review is mandatory; scalar metrics do not substitute for readability. |
| Non-sun invariance | With the sun contribution disabled, RT on/off is identical in deterministic fixtures for ambient, emission, other lights and UI. Test cloud On/Off and another directional light independently. |
| Physics isolation | Matching deterministic input tape, seed, solver/backend and checkpoints retain exact within-build accepted state/events across RT modes. Cross-engine comparison follows existing qualified numerical tolerances; do not invent cross-platform byte equality or regenerate goldens. |

Secondary 1440p/4K and other frame-rate targets require separately budgeted rows after 1080p. 720p is a final compatibility objective. Do not silently reduce resolution, scene detail, physics work, active aircraft or weather to make a failing RT row pass. A qualified reconstruction combination is a separately named mode with its actual internal pixels.

## 5. Evidence, tests and measurement discipline

Every phase writes a compact evidence receipt under its proposed evidence home. Include application SHA/dirty state, engine source and ordered patch hashes, editor/template identity where applicable, shader/denoiser revision, OS/GPU/driver, renderer, settings, actual dimensions, scene/aircraft/material generations, input/camera/light sequence, commands, required case roster, exit/log verdict, metrics, exclusions and result scope. Empty/missing cases fail the reducer. `skipped`, `blocked`, `failed`, `passed` and `not_run` remain distinct.

Reuse the [checked runner](../tools/shared.md#one-godot-script), [debug bridge](../../tools/debug/README.md), [shadow tools](../../tools/shadows/README.md), [graphics tools](../tools/graphics.md), [performance tools](../../research/performance/README.md) and [test queue](../../tools/testqueue/README.md). On enrolled hosts obtain and retain the correct session/admission handle. Do not introduce a competing profiler, invoke unmanaged Godot sessions, or use headless/software results as GPU qualification.

For performance, use at least five independent matched A/B pairs, alternate ABBA/BAAB order, warm up 30 seconds, measure at least 60 seconds per eligible sample, and retain every excluded run with its reason. Use a fixed physics/input tape or existing controlled real-flight fixture; a scripted rendering circle remains a rendering fixture. Record foreground/focus, pause, thermals/power mode, compilation/cache state and concurrent-process exclusion. Report per-run distributions and paired differences with bootstrap confidence intervals, not a single averaged FPS. GPU validation/capture runs and final performance runs are separate; validation tools can perturb cost.

For life-cycle qualification, run 100 on/off cycles, 50 resize/reconstruction cycles, 25 world/flight restarts and a 30-minute active-flight soak on the selected candidate, with bounded counters and safe teardown. Run cold setup separately so warm-cache results do not hide first-enable work. A source/parser pass never closes these gates.

### 5.1 Test families

| ID | Required cases and oracle |
| --- | --- |
| T01 — API/device | Missing methods/constants; headless; Compatibility; Mobile; wrong backend; AS/query/pipeline combinations; disabled feature bits; unavailable entry points; device limits and selected physical adapter. No unsupported native call. |
| T02 — AS correctness | One triangle, indexed/nonindexed cube, known hit/miss, transforms, nonuniform/negative scale, invalid indices/format, zero/overflow capacity, same-frame two TLAS builds, failed later instance, masks and repeated create/free. Independent expected hit positions/visibility. |
| T03 — GPU ownership | Transfer/deform→BLAS→TLAS→trace→lighting barriers; multiple in-flight frames; generic buffer allocation failures; update/use/free ordering; stale callback rejection; device-loss restart. Validation logs plus completed GPU output. |
| T04 — Lighting isolation | Selected sun among two directional lights; direct diffuse/specular; emissive patch; local light; shadow opacity 0/0.5/1; range/fade; native/projected/off; contact shadows; cloud On/Off; twilight/night; source-disabled light. |
| T05 — Receiver/MSAA | Tiny wing/gear/leaf foreground against sky and ground; sloped terrain; grazing normals; reverse-Z reconstruction; sample-edge masks; 0×/2×/4×/8× MSAA; supported custom `light()` and rejected variants. |
| T06 — Scene coverage | Offscreen up-sun caster; distant tall object; all MultiMesh instances; changing visible count/LOD/material; hidden/removed/cast-off object; capacity overflow; unsupported caster inside/outside influence volume. Conservative fallback is part of the oracle. |
| T07 — Displayed motion | Aircraft translation/roll, hinges, flaps, retracting gear, negative-scale part, parked/spinning/blurred propeller, companion instance if admitted, camera pan/FOV/cut and paused/resumed picture. Compare against actual raster transforms. |
| T08 — Alpha/deformation | Alpha scissor/hash/mips, canopy variants, wind-driven leaf/flag/windsock, skinned mesh, topology changes, non-casting plume/smoke/rain, mixed materials/shared BLAS, descriptor limits/churn and runtime overrides. No opaque replacement of cutouts. |
| T09 — Denoiser/history | Packed tile polarity/partial tiles, depth/normal/motion conversion, first-frame and partial-invalid history, actual FP16/f32 permutation, stationary/fast/view-axis motion, depth-overlapping objects, disocclusion, sun movement, reset/resize/world replacement, jitter and repeatability. Independent converged visibility reference. |
| T10 — Settings/recovery | Absent/old/malformed preferences; explicit saved Off/On; Keep/Revert; canceled preparation; renderer restart refusal; nonwritable marker; crashed activation; stale completion; direct-flight arguments; Restore defaults; unavailable UI reason. |
| T11 — Memory/off | No off-state geometry extraction/AS/guide/trace/denoise work; safe release after last use; shared BLAS reference count; retained world detach/restore; repeated lifecycle and shutdown; peak and steady bytes separately. |
| T12 — Real flight | Club field and Green paradise, ordinary pilot view and existing zoom, approach/landing, aircraft on ground and low pass, shelter/trees, wind/clouds, alternate sun angles, crash fallback and return Home. Activity/coverage counters accompany timing. |
| T13 — Combinations | Native first; then FSR2, qualified vendor upscalers and MetalFX independently, MSAA/jitter/reset ownership, dynamic resolution off, generated frames off. No combo inherits another row's pass. |
| T14 — Delivery | Matched editor/template, clean import/export, packaged shaders/resources, engine ABI availability, runtime dependencies/notices, fresh user profile, saved recovery, missing/corrupt feature assets and official-build fallback. |
| T15 — Simulation | Existing relevant flight/replay/checkpoint suites and a matched accepted-state tape across RT modes; no physics-source/config change; frame stalls do not redefine step rate or input sampling. |

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
| 00.1 | Read current rules/ownership, record branch heads, compare current main to the audited SHA and classify every changed integration path. Pin the baseline before editing. | `baseline.json` records exact application/engine/patch/content identity, dirty paths and drift dispositions. Unexplained engine or renderer drift blocks the affected phase. |
| 00.2 | Select one repeatable real-flight shadow defect and three target ROIs: aircraft/gear, terrain contact and a field object. Freeze camera/input/weather/sun and tuned native PCSS control; include ordinary pilot view. | Matched native captures/video show the defect without changing aircraft readability or exposure. If no meaningful defect survives tuning, record no-go for production RT and keep the later fixtures research-only. |
| 00.3 | Implement the proposed evidence manifest, required-case rosters and thin wrapper/reducer CLI. Reuse checked runner, queue, debug bridge, shadow cost and performance collection. | Reducer rejects a missing case, wrong engine, stale source, fallback-only timing, invalid pixels and incomplete run. All successful cases include checked log verdicts. |
| 00.4 | Collect the official baseline at actual 1080p now; collect the candidate-Off baseline only after 01.4 produces that executable. Freeze section 4 limits/hardware rows and record shadow/light receipts and repeat noise. Phase 01 may start after 00.1/00.3 without waiting for this subphase. | Baseline portions of T12/T15 complete, including reusable input tapes and the pre-feature simulation control. RT-On comparisons are deferred to 14. Performance headroom and baseline failures are explicit. No source-based GPU estimate substitutes for timing. |

**Stop:** missing real image benefit, unusable baseline, or absent source identity. Continue only source/fixture research until the production prerequisite is resolved.

### Phase VQ-RT-01 — Create the isolated engine lane and repair source prerequisites

**Depends on:** 00.1/00.3. **Owned paths:** proposed intake/patch tooling and disposable engine trees. **No application default changes.**

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 01.1 | Pin official source commit/archive/hash and toolchain. Create distinct editor/template intakes and ordered patch manifests. Bring only the two reviewed Vulkan prerequisite patches from `0ccfa7d…`, retaining provenance and their tests. | Preparation recreates identical patched source and refuses unknown edits/hash mismatch. Existing NVIDIA/AMD/Apple intakes remain separate. |
| 01.2 | Revalidate AS reference addresses, recoverable creation/allocation/bind failure, scratch sizing/alignment and entry-point checks. Review generic buffer cleanup independently. | Source-bound fault tests and full affected translation-unit builds pass; non-AS buffer success/failure/cleanup tests pass. These are not GPU qualification. |
| 01.3 | Revalidate TLAS capacity arithmetic, fresh and reused same-frame reservation, type validation and dependency transaction. Define empty scene as no RT dispatch; reject zero-capacity creation unless deliberately supported and proven. | T02 invalid cases preserve the previously valid TLAS and dependency state. Two same-frame builds use disjoint instance-buffer regions. No unchecked integer overflow. |
| 01.4 | Build/link a complete editor and release template, then verify matching source/patch/compiler identities. Ensure Compatibility/Mobile compile and non-RT launch. | Full link and pair receipt, official-control comparison and minimal non-RT rendered smoke pass. A translation-unit-only result cannot close 01.4. |

**Stop:** a patch changes general raster behavior without an explained fix and regression evidence, or the full binary cannot be built reproducibly.

### Phase VQ-RT-02 — Prove the actual Vulkan query and AS contract

**Depends on:** 01. **Output:** native hit/miss/lifetime evidence and an explicit query-only decision.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 02.1 | Inspect selected-device extension/feature chains, AS geometry formats, limits and enabled entry points in the built binary. Use checked explicit buffer updates and sentinel output in the fixture; do not assume constructor upload success. | T01 matrix reports supported, enabled and actually exercised separately. Unsupported paths return a reason without calling unavailable functions. |
| 02.2 | First reproduce the existing-pin positive route on a device with both query and pipeline support: a real compatible minimal RT pipeline, an allocated/populated SBT range and a compute query. | Known hit/miss/mask/transform readback and synchronization validation pass. This control is mandatory on a both-feature device and explicitly not applicable on a query-only device; the latter must pass 02.3 instead. Never hard-code a nonzero SBT token. |
| 02.3 | Implement a narrowly scoped query-only TLAS construction mode/API in the engine adapter, with valid zero SBT offset semantics and explicit rejection if that TLAS is used by an incompatible trace-rays path. Do not weaken the existing pipeline validation globally. | A query-only test configuration proves no pipeline/SBT creation/call is needed; both-feature and pipeline-only negative/control cases retain correct behavior. Tests include missing entry points. If this cannot be proven, retain the legitimate pipeline/SBT route and advertise `requires_pipeline_support=true`; do not claim generic query-only support. |
| 02.4 | Run real-device failure/lifetime cases: allocation failure, failed second instance, capacity overflow, multiple frames in flight, delete/recreate, disabled query and clean teardown. | T02/T03 completed output plus validation/fault receipts. The device row remains blocked without real GPU execution. |

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
| 04.2 | Implement GPU retention across upload/build/trace/filter/lighting and safe retirement. Reuse the engine render graph/fences; never call device-wide idle per frame. | T03 multiple in-flight frames and intentional lifetime stress are validation-clean. Shared geometry remains alive until its last owner/use finishes. |
| 04.3 | Implement prepare/cancel/suspend/failure/off transitions with original raster binding restored before new work is stopped. Prevent stale callbacks from confirming replacement epochs. | T10/T11 cancellation at each preparation stage; 100 enable/disable cycles; no growth or stale binding. |
| 04.4 | Add debug-only allocation/build/dispatch failure injection and a persistent pre-activation marker tied to build/driver/device identity. | Marker-write failure refuses activation safely; induced crash recovers with effective RT Off next launch. Release builds omit fault controls. |

### Phase VQ-RT-05 — Define the registered scene and conservative coverage

**Depends on:** 03/04. **No flight-scene RT activation until the coverage proof exists.**

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 05.1 | Inventory native sun casters/receiver variants in Club field and Green paradise. Record every surface/instance category from section 3.4 and its native inclusion rule. | A source-bound scene manifest reports admitted, excluded-native-noncaster and unsupported-relevant categories. Unclassified objects block admission. |
| 05.2 | Implement event-driven mesh/instance/material/LOD generation tracking in the engine/world adapter. Snapshot render-thread data without SceneTree reads. | Add/remove/visibility/material/world-change cases update exactly once; unchanged frames do not rescan or extract meshes. |
| 05.3 | Compute the conservative receiver-to-sun influence region over the full solar cone and validated ray extent, including off-camera and distant tall casters. Recompute on view/sun/size/bounds changes; define capacity/memory limits. | T06 inserts unsupported center-ray and edge-of-disk blockers outside camera view but inside influence and forces native; one outside influence cannot affect the result. Overflow never silently drops geometry. |
| 05.4 | Implement whole-affected-viewport fallback for incomplete coverage and report coverage/activity. Keep partial-coverage optimization disabled. | A deliberately omitted caster cannot yield an apparently valid RT miss. All-raster fallback cannot satisfy the qualification reducer's active-RT gate. |

### Phase VQ-RT-06 — Build static scene geometry efficiently

**Depends on:** 05 and the native AS fixture.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 06.1 | Create AS-ready streams for exact static terrain, runway and opaque field structures. Reuse existing immutable mesh data where compatible; use checked dedicated streams otherwise. | GPU known-ray tests agree with independent world geometry; terrain remains visually/collision aligned without changing collision data. |
| 06.2 | Share BLAS across identical mesh/material-caster variants and separate instance transforms. Track material/geometry ownership, memory and stable IDs. | Repeated instances use one BLAS; different relevant geometry/alpha variants cannot alias. Per-instance mask/negative-scale tests pass. |
| 06.3 | Schedule bounded loading/warmup builds before activation. Reuse build/scratch arenas safely; no compaction/refit claim. | Cold setup time/peak memory are reported separately. Native display continues while preparing; no partial scene is exposed as RT. |
| 06.4 | Implement topology/material/LOD replacement as a generation transaction with old-resource retirement. | T06/T11 replacement/failed upload/unload cases retain correct raster fallback and free old generations after last use. |

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
| 08.2 | Admit all relevant MultiMesh instances, per-instance transforms/visibility and LOD/material generations. Bound upload/build work and instance metadata. | T06 changing visible count/transform/LOD cannot leave ghosts or miss an offscreen caster. Capacity failure produces native fallback. |
| 08.3 | Implement a same-clock displayed-geometry producer for required wind/windsock/flag/skinned categories, or leave the affected field unqualified. Reuse authored deformation math; measure full BLAS rebuild cost. | T08 current deformed raster silhouette agrees with ray geometry. No frozen wind, stale previous vertices or unmeasured assumed refit is accepted. |
| 08.4 | Re-run the coverage manifest for real Club/Green paradise flights and certify the actual supported field/model subset. | ≥95% eligible real-flight frame activity and ≥90% each target ROI coverage are attainable without hiding unsupported blockers. If not, do not expose the field as supported. |

### Phase VQ-RT-09 — Integrate deterministic hard sun visibility into lighting

**Depends on:** 02/04; fixture work can start before scene phases finish. Real-flight admission also requires 05–08.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 09.1 | Produce a hard-visibility texture for a known opaque scene using matching current-frame receiver depth/normals/validity. Establish reversed-Z reconstruction and numerical ray-origin limits. | T02/T05 analytic plane/box/grazing/gear-gap cases pass; no stale buffer is sampled. |
| 09.2 | Patch the selected-sun visibility seam before existing fade/opacity. Keep native maps and branch to native for invalid input/receiver. Preserve diffuse and specular, custom-light semantics where admitted, and other light identities. | T04 non-sun pixels/terms are unchanged; sun opacity/fade/two-light fixtures pass. Final-color multiplication fails the test. |
| 09.3 | Preserve native range and aircraft cue handoff under Auto/Native/Projected/Off, including shadow-source veto, cloud choice, night and low sun. | Existing shadow-control tests plus T04 show no double ground shadow or cue loss; RT never overrides Projected/Off. |
| 09.4 | Run actual fixed-wing hard-shadow captures and compare with tuned native hard shadows at equal conditions. Keep this mode a correctness milestone. | Complete scene/lighting/activity evidence; ordinary PCSS softness is not compared unfairly to a hard RT reference. No production promotion yet. |

### Phase VQ-RT-10 — Produce current guides before temporal shadow filtering

**Depends on:** 09.1/09.2 and the resource graph from 04. **Blocking fact:** the inspected engine's ordinary current motion output is too late for pre-opaque temporal shadows. This phase is an engine change, not a compositor flag.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 10.1 | Define a versioned guide contract: current projection-space depth with the pinned denoiser's inverted-depth option, separately named linear depth only if needed, normal convention, receiver validity, current-to-previous motion, jitter, viewport rectangle, internal dimensions, matrices and history epoch. Document units, sign, handedness, formats and clears. | T05/T07 independent projection fixtures map known 3D points to expected current/previous pixels and reconstruct near/far geometry correctly. Identity, camera-only, object-only and combined motion pass. No assumed compatibility with an upscaler's encoding. |
| 10.2 | Add an RT-only early guide producer to the existing depth/prepass route, including current/previous displayed rigid transforms and a previous-depth/correspondence guide for moving receivers. Force it only for an admitted active/preparing RT viewport. Share resources only when contents/lifetimes match exactly. | GPU event order proves guide writes precede trace/denoise reads. A fast thin wing has current vectors on its actual pixels; a centered aircraft moving in depth has correct prior depth despite zero XY motion. Off/excluded views have no extra pass, attachment or shader variant activation. |
| 10.3 | Extend early motion to each admitted deformation and alpha/LOD variant from 08, or invalidate affected receivers conservatively. Define MSAA sample validity: initially use native visibility for mixed depth/normal/coverage pixels; do not average different surfaces into one trace origin. | T05/T07/T08 tests cover 1×/2×/4×/8× where available, gear/wire silhouettes, disocclusion, wind and model changes. Invalid guides cannot contribute history. The fallback band still satisfies each ROI coverage floor. |
| 10.4 | Verify matrix/jitter history across pause, camera cuts, replay seek, viewport recreation and resolution changes. Compare RT Off and On ordinary motion outputs consumed by TAA/reconstruction. | T07/T09 history-reset receipts agree with actual resource contents and completed frames. Existing TAA/reconstruction guides remain correct. Measure all incremental early-pass cost in the RT budget. |

**Stop:** if a correct current guide cannot be produced within the owner boundary, Soft remains unavailable. Hard may continue as a research mode. Do not consume previous-frame motion, delay sun lighting by one frame, or silently replace the renderer.

### Phase VQ-RT-11 — Add finite-sun sampling and the pinned shadow denoiser

**Depends on:** 08–10 for real flights; 10 and the analytic fixture for isolated shader development. **Output:** qualified hard and soft modes under the existing softness preference.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 11.1 | Acquire and verify the section 3.6 exact denoiser pin and license; pin compiler and local adapters. Implement its format/permutation/FP16/subgroup checks and tracked resource bindings through the engine's existing device/graph. No second SDK-owned Vulkan device or untracked synchronization. | Reproducible shader build and constant/mixed-tile fixtures exercise the actual selected permutation; no compile-only zero stub can pass. Notices cover shipped files. A format/binding/lifetime table accounts for every temporary/history allocation. |
| 11.2 | Implement the sun-disk sampler and documented 8×4 binary-mask packing. Resolve actual sun angular diameter and use half as radius. Derive each preparation/classification/filter dispatch independently from its shader workgroup; validate odd sizes, edge guards, polarity and bit order. | T09 constant/checkerboard/tile-edge and format/bounds fixtures pass. The finite-light scene matches an independent converged reference. At zero sun size, raw pre-denoiser visibility/ray directions match Hard; the filtered result has its own quality gate. Rendering samples never touch simulation RNG. |
| 11.3 | Implement the section 3.6 adapter obligations: prior-depth correspondence, explicit epoch/partial-invalid reset, initialized histories, receiver-validity filtering and correct guide conversions. Preserve the pinned filter/remap contract and avoid color-transfer encoding. Reset on all section 3.8 events. | T09 first frame, invalid neighbors, stationary noise, moving/depth-overlapping aircraft, thin gear, contact hardening, pan/disocclusion, low sun and sudden light change meet the fixed limits. No stale shadow survives on sky or unrelated surfaces. |
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
| 14.1 | Run all required T01–T11 cases and independently review native-size image sequences. Compare tuned raster Hard with RT Hard, and tuned native PCSS with RT Soft. Use the frozen three ROIs and ordinary pilot view; preserve exposure/time/camera/material settings. | Analytic/reference limits, temporal limits and predeclared defect improvement all pass. Fixed masks and exclusions are published; manually choosing a more favorable crop or light after seeing results invalidates the run. |
| 14.2 | Execute T12 paired real-flight measurements using section 5's five independent pairs and recorded run order. Include both admitted fields, representative detailed/hinged aircraft, moving shadows, low sun, parked/startup, normal pilot view and the fixed adverse case. | Each required row meets p95/p99/headroom, incremental GPU/CPU, peak memory and ≥95% frame/≥90% per-ROI coverage limits. Warmup, loading, steady flight and failure recovery have separate numbers. A fallback-dominated run cannot pass as RT performance. |
| 14.3 | Run focused existing simulation, input/replay and aircraft-presentation checks on identical recorded inputs with RT Off/Hard/Soft. Cover pause/unpause, camera changes, crash and replay seek; include AI companions only where that engine is independently qualified. | T15 demonstrates unchanged simulation state within the existing same-build exact/cross-engine tolerance contract. No golden output is regenerated to hide drift. Render-only RNG and frame pacing do not change consumed input steps. |
| 14.4 | Reduce every frozen row into a machine-readable verdict and a short human report. Have a reviewer inspect selected captures, coverage receipts, matching engine identities, failed cases and the raw-to-summary calculation. | The reducer reports `qualified`, `failed`, `blocked` or `not-in-scope` per row, never a blanket GPU-vendor badge. Reviewer finds no unaccounted default changes or omitted failures. Qualification is bounded to the tested revision and configuration. |

### Phase VQ-RT-15 — Qualify Windows packages and the first distributable candidate

**Depends on:** 14 for each advertised mode/field/device row. **This is the core-delivery boundary.** Building a package is authorized implementation work; publishing a release remains a separate release-owner action.

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 15.1 | Produce matched custom editor/export templates from the qualified source/patch/shader manifest. Integrate with existing export/package helpers and the exact application snapshot. Keep native SDK variants separate. | T14 checks template/editor identity, ABI, imports, dependency notices, archive contents and startup. A successful editor session alone cannot qualify a release template. No engine binaries or SDK archives are committed to the application repository. |
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
| 17.1 | Start with reconstruction already supported by the beta2 candidate. For each native/temporal/spatial combination, record actual internal size, output/drawable size, jitter, motion, reactive/validity inputs, reset events and the final composition order. | T13 proves guide conventions and history separation, no doubled jitter or shadow trail, correct resize/reset and UI scale. Compare at both equal output and explicitly reported internal resolution; never count fewer traced pixels as an unexplained speedup. |
| 17.2 | Prepare a separate NVIDIA lane based on its own pinned fork and complete existing patch chain. Port the minimal reviewed RT changes by code review; do not cherry-pick beta2 assumptions blindly or replace the official baseline. Preserve DLSS/Reflex ownership and the existing AI-companion qualification gate. | Full editor/template builds plus T01–T11/T14/T15 rerun against the older fork. DLSS Super Resolution and Reflex behavior are checked independently. No Ray Reconstruction or frame-generation claim is inferred from successful DLSS SR. |
| 17.3 | Prepare the AMD SDK 2.4 upscaling candidate independently, using its verified intake and known limitations. Audit RT patch conflicts, guides, storage resources, synchronization and failure/reset paths. | Each AMD reconstruction combination receives its own T13/T14/real-flight row. FSR upscaling availability does not imply FSR Ray Regeneration or an RT-denoiser backend. A pre-existing storage warning is resolved or explicitly blocks the affected candidate. |
| 17.4 | Run paired Native-versus-combination quality/performance and lifecycle qualification at the established output sizes. Add 1440p/4K rows only with explicit budgets; 720p is a final diagnostic, not the primary acceptance target. | Report genuine rendered-frame latency/times separately from any later generated-frame metrics. DRS/Reflex states are fixed and recorded. Passing one lane does not enable the option in the others. Unsupported combinations retain the request and use native shadows with a precise reason. |

**Excluded here:** adding Ray Reconstruction, Ray Regeneration, frame generation, a new AI companion engine baseline, or merging the NVIDIA, AMD and Apple forks into one product. Each requires separate ownership and qualification.

### Phase VQ-RT-18 — Build a separately qualified Metal implementation

**Depends on:** 00.1/00.3, the frozen common scene/lighting/state contracts and the Metal source inventory. Isolated Metal source/fixture work may proceed without a completed Vulkan GPU phase; product qualification requires equivalent scene/ownership/coverage, guide, quality, lifetime and package gates. **Do not route Metal through Vulkan feature bits.**

| Subphase | Required work | Proof and exit condition |
| --- | --- | --- |
| 18.1 | Freeze the existing beta2 Metal intake, ordered patches and API/OS/SDK requirements. Audit `0005`, `0018`, `0021` and closed draft `0027` against the shared ABI. Separate API availability, `supportsRaytracing`, required resource support and hardware acceleration. | Capability receipts name the native Metal producer and proven workload. An M1 query/readback does not become a hardware-accelerated normal-flight claim; an M3-or-newer family label does not replace the runtime checks or timings. Mobile/standard startup remains unchanged. |
| 18.2 | Implement a renderer-owned native Metal scene/AS/query producer using current displayed transforms, exact geometry/material semantics and tracked command/resource lifetime. Replace diagnostic capture/readback/waits with proper frame-graph integration. | T02/T03/T06–T08 equivalents prove live geometry, alpha, off-camera/cone coverage and real GPU completion. No per-frame `device/queue idle`, CPU hit readback, stale completed capture or diagnostic environment flag is required for production flight. |
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

Phase 00 defines the JSON schemas and validates them. At minimum, each verdict contains: `schema_version`, `phase_id`, `case_id`, `status`, `reason`, application commit/dirty-state identity, engine/template/patch/shader hashes, OS/GPU/driver/renderer, requested/effective feature and mode, content/viewport/sun identities, dimensions, scene/history generations, submission/completion evidence, coverage denominator and numerator, sample/run roster, timing/peak-byte results, quality-mask/reference identities, log/error verdict and evidence locations. Missing mandatory values are an error; `null` is allowed only for a documented not-applicable field.

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


