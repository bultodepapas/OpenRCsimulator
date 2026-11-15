# Ray tracing: visible benefit, NVIDIA/AMD integration and delivery plan

**Research snapshot: 2026-11-15.** Continuation on `audit/graphics-performance-technologies-2026-11-15`, from documentation parent `e92db3654432f81fb3e666e1c0e7f59b94355002`. Application inspection remains pinned to `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`, official Godot `4.8.beta2.official.cafc17a19`; later `main` at `273a7e4c0617fdf4cacc39c360796fd79afa5f2c` is a separate [checkpoint](13-community-driven-execution-plan.md#4-newer-main-checkpoint-and-retained-project-results). This is source research and a proposed implementation sequence. No new rendered comparison, native GPU measurement, SDK integration or supported-device claim accompanies it.

## 1. Recommendation and product outcome

The first hardware-RT candidate is **one optional, correctly integrated sunlight-shadow effect**, admitted only after a repeatable pilot-visible defect and native 1080p headroom exist. Its intended value is a more stable relationship between aircraft, ground and nearby objects during landing and low flight. It must outperform the selected existing shadow configuration in a real viewing task; a successful triangle query alone is insufficient.

The next plausible RT effect is **selected reflections on water or nearby glossy surfaces**, after comparison with the simulator's existing probe and optional planar lake capture. Full-scene indirect illumination and path tracing have much greater scene/material and reconstruction scope. They should not lead the normal-flight implementation. Cloud and texture improvements have a parallel, simpler opportunity through existing atmospheric and material systems; neither requires hardware RT by definition.

This is an optional **quality** proposal. RT generally adds traversal, scene maintenance and shading work; smoother flight remains a separate optimization objective. Reconstruction can change that tradeoff, but cannot justify losing a small aircraft's attitude, markings or control response. Keep DRS, Reflex and frame generation fixed while evaluating the first RT effect. Qualify combinations only after their individual contracts pass.

Read the [NVIDIA/AMD implementation guide](ray-tracing/01-nvidia-amd-integration-guide.md) for API, SDK, licensing and tutorial choices, and [clouds, materials and water](ray-tracing/02-clouds-materials-and-water.md) for exact source seams and visual cases. The [baseline audit](04-ray-tracing-in-godot.md), [integration design](10-reflex-and-ray-integration-design.md#2-direct-sun-ray-tracing-real-seams-and-limits) and [five developer cases](community/03-ray-tracing-cases.md) retain the detailed engine risks. Existing VQ-04b/VQ-07/FW/GDU/DT owners retain acceptance and status; this chapter does not create another roadmap or change an accepted default.

## 2. Where the difference should be visible

The ranking below is an engineering estimate from source and the expected viewing task, **not a measured visual ranking or GPU benchmark**. A camera path must reproduce the proposed defect before work is selected. Compare at equal output size, camera/zoom, weather, exposure, materials and reconstruction.

| Candidate | Where a player could notice it | Existing comparison | Cost and priority judgment |
| --- | --- | --- | --- |
| Selected-sun shadows | Low approach, touchdown, wheels/landing gear near ground, aircraft or shelter casting on another surface; unstable shadow edges during motion. | Current native maps/PCSS, projected aircraft cue and selected quality/range. | First conditional RT candidate. One light limits shading scope, but complete moving casters and engine insertion are substantial work. No automatic improvement over current soft shadows. |
| Lake and glossy reflections | Low pass over the lake; aircraft reflected after leaving the main view; nearby polished paint, metal and canopy surroundings. | Probe/sky plus the optional High planar lake path, which already includes the moving aircraft. | Potentially conspicuous in selected scenes. More expensive and complex than binary visibility: hit materials, roughness, lighting, environment and temporal reconstruction are required. Later experiment. |
| Ambient/contact occlusion | Gear, hinges, pavilion joints and close Workshop inspection. | High SSAO plus existing contact cues; current direct sunlight remains separate. | Possible close-up improvement, lower normal-flight priority. Do not stack another darkening term or spend distant-flight budget on invisible creases. |
| Indirect illumination / GI | A model close to a shaded structure, under a pavilion or near a strongly colored surface; transitions between sun and shade. | Current ambient/sky/probes, material calibration and applicable Godot GI alternatives. | High integration and history cost; likely less leverage in open sky than in an enclosed scene. Require a specific visual failure before choosing it. |
| Cloud shape, lighting and cloud shadows | Large areas of overcast sky, sunset backlighting, horizon silhouette and coherent moving shade. | Current layered sky, relief, storm cards and projected cloud density. | Potentially valuable image work, but volume raymarching is a separate atmosphere technique. A bounded improvement to the current system can be cheaper than a new volume renderer. |
| Texture and material fidelity | Close paint/film/foam/metal, runway roughness, grass and tree texture filtering; stable distant aircraft markings. | Existing PBR maps, material detail tiers, mips and anisotropic filtering. | Inspect before RT. Correct data and filtering often have a smaller integration scope; a higher-resolution asset is not automatically worth memory or aliasing cost. |
| Full path tracing | Controlled cinematic or close showcase with many interacting light paths. | Current raster presentation and selected effect trials. | Separate research lane only. Whole-scene shading, convergence, motion and cross-device maintenance make this a poor first normal-flight deliverable. |

The source already provides **soft, contact-hardening sun shadows**: the default/current native soft [High configuration](../../../app/render/high_graphics_profile.gd) uses four cascades and a `0.53` degree sun angular diameter. [ShadowSettings](../../../app/render/shadow_settings.gd) owns quality, range, softness, native/projected selection and aircraft cues, and can override those defaults. Record its actual effective receipt for the control. RT is not uniquely capable of soft shadows, and shadow maps can also include off-camera casters. The question is whether RT fixes a demonstrated residual artifact at acceptable total cost.

An initial one-ray, point-sun fixture gives deterministic hard visibility. It proves a necessary correctness boundary; it can look worse than current PCSS and is not a shipping softness comparison. A finite-angular-size sun needs distributed samples and possibly denoising. Add that only after the visibility and lighting paths are correct, then compare with the same angular sun and a converged reference.

### Pilot scale is the deciding scale

[PilotCamera](../../../app/render/pilot_camera.gd) already calculates projected pixel size and auto FOV; [camera settings](../../../app/render/camera/camera_settings.gd) retain a 50-degree base FOV and configurable zoom. The constant auto-zoom law targets 30 pixels of a 1080-pixel reference height while its FOV limits permit. Therefore, a distant aircraft may occupy only a small number of pixels even when the landscape fills the image. A denoiser that produces a pleasing still but erases its wing edge or trails its shadow fails the simulator's task.

Use actual recorded camera projection and aircraft span, not a fixed hypothetical distance-to-pixels table. Review normal pilot view and zoom separately at 20/50/100 m and the accepted farther range; include rolling attitude, a tree/cloud background and approach/retreat. Workshop and low cinematic views are useful secondary cases. A close-up-only improvement may justify an explicitly scoped presentation feature later, but does not establish normal-flight benefit or permission to alter live-flight physics.

## 3. NVIDIA and AMD: one base effect, conditional extensions

Use a **shared Vulkan effect contract** for the first Windows/Linux NVIDIA and AMD candidates, then qualify each actual device, driver and package. Vulkan compatibility is an architectural target, not evidence that every RTX or Radeon device works. On the current official pin, low-level RT is not an OpenGL Compatibility feature, nor an automatically implemented D3D12/Metal effect. The [exact API audit](04-ray-tracing-in-godot.md#exact-version-and-technical-boundary) records both ray-query and pipeline checks, the real SBT allocation requirement, the query-only risk and missing demonstrated refit/compaction routes.

| Layer | Proposed use | Boundary that prevents wasted integration |
| --- | --- | --- |
| Vulkan acceleration structures and visibility query | Own the same effect meaning, scene identity and raster fallback on NVIDIA and AMD. Start with fixture-owned opaque geometry. | Resolve the [exact-pin source prerequisites](ray-tracing/03-vulkan-fixture-work-order.md#card-0--correct-a-pinned-vulkan-address-mismatch-first), then require known hit/miss/parameters and lifecycle on the actual corrected backend. The first positive fixture requires both query and pipeline plus legitimate SBT allocation until the query-only route is independently proven. |
| NVIDIA NRD / AMD FidelityFX denoiser | Evaluate one appropriate shadow denoiser only if finite-sun sampling creates an identified quality need. | Correct noisy signal, depth, motion, normals and history are prerequisites. Vendor source is not a ready-made Godot integration; do not integrate two libraries before one useful image. |
| NVIDIA DLSS Ray Reconstruction | Possible later reconstruction for a richer compatible NVIDIA ray-lighting path. | The existing DLSS upscaler/Reflex fork does not imply that Ray Reconstruction is wired. Its radiance/material/motion inputs and feature checks differ from a binary shadow mask. |
| AMD FSR Ray Regeneration | Separate later product/backend investigation if its richer reconstruction is justified. | The current [1.2.1 manual](https://gpuopen.com/manuals/fsr_sdk/techniques/denoising/) requires Windows 11, DirectX 12 + Shader Model 6.6 and Radeon RX 9000 or later. A Vulkan addition elsewhere in the FSR SDK does not make this technique a portable Vulkan denoiser. |
| NVIDIA RTXDI / ReSTIR | Research for a later demonstrated many-light sampling problem. | One sun does not justify a many-light reservoir system. Keep its source/material/history work out of the first effect. |
| Apple Metal work | Reuse the existing DT-MAC producer/qualification lane separately. | Its experimental scene-query witnesses do not prove stock Metal or normal-flight RT. Do not duplicate that owner or claim parity from a Vulkan result. |

The vendor appendix records release identities and the difference between the installed FidelityFX SDK **1.1.4 / FSR 3.1.4** fork and newer SDK candidates. Tutorials based on DirectX can teach scene and signal design without being code that the current Vulkan Godot path can simply import. Read each component's own license and binary/distribution terms before adding it; a repository's top-level license does not settle all SDK dependencies.

## 4. Implementation boundaries and pseudocode

### Scene representation and renderer insertion

A BLAS stores geometry for intersection; a TLAS references its instances and transforms. Reuse unchanged geometry. A moving rigid aircraft part can change its instance transform, whereas shader wind, skinned vertices, LOD changes and shader-generated forms may require different geometry and rebuild work. The exact pin exposes build operations; an `ALLOW_UPDATE` flag is not proof that the usable refit operation exists. Ordinary mesh buffers also lack the required AS input flags in the inspected path. Per-frame GPU mesh readback or a synchronous copy of the Metal diagnostic is unsuitable. See [10](10-reflex-and-ray-integration-design.md#2-direct-sun-ray-tracing-real-seams-and-limits).

For the fixture, own explicit AS-ready buffers and immutable material rules. For flight, first create a coverage manifest for aircraft body, hinges, propeller representation, ground, field structures, MultiMesh trees, alpha leaves, windsock, water and transparent effects. Record masks, visibility, transforms, vertex/material generations and supported receiver types. A conservative sun region must include relevant off-camera casters. Camera-frustum-only geometry is insufficient. Any unsupported relevant geometry or stale resource makes the **whole affected viewport retain raster**, rather than silently rendering an incomplete scene as RT.

The pinned Forward+ directional-light shading loop is the candidate place to replace the selected sun's visibility before direct diffuse/specular are accumulated. A compositor callback provides useful scheduling/resources but not automatic scene data or a separately shaded sun image. The required matching depth/prepass resources are not unconditional. Select the real Sun identity; lightning can create other directional lights. Do not assume light index zero or multiply a finished color buffer by a shadow mask.

Conceptually, with the existing opacity/fade policy preserved:

```text
final_surface = ambient_and_indirect + emission + other_lights
              + selected_sun_direct * geometry_visibility * cloud_transmission
```

Here `geometry_visibility` is the **effective** factor after the existing shadow-opacity/fade policy, not necessarily the raw binary ray result. A blocked ray removes all direct sun only at full shadow opacity without fade; otherwise its intended residual sun contribution remains. This equation describes separated contributions, not a new Godot API or an instruction to rewrite every shader. Some existing custom materials already apply cloud transmission, currently to every `LIGHT_IS_DIRECTIONAL` light. Preserve a second directional light's existing baseline while applying the selected Sun's transmission once. Choose raster **or** RT sun visibility for admitted receivers. A controlled fixture can delimit its receiver region; normal flight remains entirely raster until complete relevant coverage passes. A mixed spatial/material partition would require the separate seam and ownership proof described in [10](10-reflex-and-ray-integration-design.md#exact-lighting-insertion-point), and is not authorized by this proposal. Existing height/contact cues have a pilot purpose and need their own ownership decision; do not accidentally remove a useful cue or treat every cue as physical sun visibility.

### Proposed frame contract

The following is design pseudocode for the existing render/engine owner. None of these helper names is an implemented public API. The complete resource and native-oracle detail remains in RT-01–06 of [10](10-reflex-and-ray-integration-design.md#proposed-effect-tests-and-decision-thresholds).

```text
on_render_frame(context):
    if not user_requested_effect or not qualified_candidate(context):
        restore_existing_raster_sun_binding_for_viewport()
        invalidate_effect_history()
        request_safe_retirement_of_previous_submissions()
        return EXISTING_RASTER                # no new RT dispatch/allocation

    published = false
    scope = acquire_submission_owner()        # ownership metadata, not GPU work
    try:
        # Never borrow a snapshot across a world/viewport epoch.
        scene = acquire_current_scene_snapshot(context)
        if not scene.complete_for_selected_sun or not scene.matches(context):
            return EXISTING_RASTER
        if not matching_receiver_inputs_available(context):
            return EXISTING_RASTER            # no stale depth/normal fallback
        update = plan_geometry_and_instance_changes(scene)
        if update.requires_unsupported_operation or not update.fits_admitted_budget:
            return EXISTING_RASTER

        # Every helper registers resource retention BEFORE any GPU submission.
        # Dependencies include builds, traversal, filtering and final shading.
        ready = prepare_as_and_signal(scope, update, context)
        if not ready.valid or not ready.same_generation:
            return EXISTING_RASTER
        raw = trace_selected_sun(scope, ready, receiver_inputs)
        if not raw.contract_valid:
            return EXISTING_RASTER
        visibility = raw
        if qualified_finite_sun_filter_enabled:
            reject_invalid_history(scene, camera, size, light, material, weather)
            visibility = filter_valid_signal(scope, raw, matching_auxiliary_inputs)
            if not visibility.contract_valid:
                return EXISTING_RASTER

        # Commit before the consuming draw; failure leaves the raster binding intact.
        binding = commit_sun_binding_atomically(scope, visibility, scene.epoch)
        if not binding.applied_for_matching_draw:
            return EXISTING_RASTER
        published = true
        return EFFECTIVE_SELECTED_SUN_RT
    except expected_renderer_setup_or_resource_error:
        record_effect_failure_reason()
        return EXISTING_RASTER
    finally:
        if not published:
            restore_existing_raster_sun_binding_for_viewport()
            invalidate_effect_history()       # no history survives a raster gap
            scope.request_retirement()
        # Includes early returns and partial/failed submissions; never a CPU stall.
        scope.enforce_gpu_lifetimes_and_retire_when_obsolete_and_safe()
```

The state checks above are contract/metadata checks, not per-frame CPU readback of every ray. The shared submission owner enforces retention even when a build, dispatch, filter or binding fails partway through; published resources stay valid through their consuming draw and histories remain owned until replaced safely. Every return to raster restores its binding and invalidates temporal history before reentry. The disabled fast path must also restore that viewport's raster binding. The disabled control makes no new RT allocations or dispatches; deactivation may retain already-submitted resources until verified GPU completion. No fixed two/three-frame delay substitutes for that proof. The atomic binding commit must be proven at the engine seam before relying on this contract. Recoverable effect errors preserve raster on a usable renderer; actual device loss disables the effect and follows the engine's normal recovery/shutdown behavior, without promising a same-frame raster image from a lost device. A requested setting is not evidence of current execution. Do not add a player-facing switch before useful rendering and fallback have passed.

## 5. Texture, water and cloud work that should accompany it

**Materials first:** audit one aircraft skin and the affected receivers for correct albedo color space, roughness/metallic mapping, normal scale, mip choice, UV scale and filtering. [VehiclePaint](../../../app/render/vehicle_paint.gd) already supports these controls and deliberately reduces some detail at lower tiers. Preserve those decisions unless a matched view demonstrates a defect. A normal map changes shading and reflected-ray direction; it does not change a triangle hit or silhouette. RT will not add missing texels, correct an incorrect material, or make distant microdetail readable.

**Water:** preserve the custom wave geometry/normals, refraction, Fresnel, direct sun and linear-HDR convention in [water.gdshader](../../../app/render/lake/water.gdshader). Its probe excludes the moving aircraft; the optional planar capture includes it. Compare probe, planar and any later RT candidate separately. Use one selected reflection radiance source with a coherent fallback, not an accidental sum of three reflections. A ray that hits a plane still needs a material/light evaluation; a miss needs a specified sky/environment. Main-view depth alone cannot supply all off-camera hit materials. Waves, transparency, clipping and rough reflections make this a distinct later delivery.

**Clouds:** current [sky](../../../app/render/sky.gdshader) uses layered density and optional relief, with separate background/cubemap behavior; [storm cards](../../../app/render/weather/storm_bank.gd) provide localized impostors. Ground/grass already project cloud density into directional lighting. First investigate shape/lighting or transmission consistency with these inputs. If a specific scene warrants a volume experiment, bound its altitude region, sample count, reduced-resolution/history policy and fallback. Volume raymarching samples density along a ray; it is not the same task as hardware triangle intersection. Do not sell it as requiring an RTX card or substitute cosmetic cloud data for weather/flight physics.

An RT reflection's miss environment must agree with the chosen sky's time, sun/cloud contribution, linear radiance and exposure. Background-only relief and camera-facing storm cards do not automatically appear identically in a cubemap. Ray tracing will not resolve that mismatch without an explicit environment policy. The [atmosphere appendix](ray-tracing/02-clouds-materials-and-water.md) connects these boundaries to original-author Nubis presentations and Godot material/depth documentation.

## 6. Cost model and bounded acceptance

Count CPU scene extraction/change tracking and GPU build/update, scratch storage, ray work, material evaluation, filtering, history, composition and all in-flight resources. Report cold build/transition spikes separately from steady flight. Overlapped GPU tasks do not become free: use the measured whole-frame critical path and presentation behavior. Do not sum unrelated p95 values as though they were one frame or mistake a wall-time increase for measured ray-traversal time.

For scale intuition only, one query at every 1920×1080 pixel is **2,073,600** possible queries per frame; at 60 frames/s that is **124,416,000**. Sampling 960×540 gives **518,400**, one quarter as many receiver pixels. This is arithmetic, not a benchmark: background rejection, AS work, divergence, filtering and fixed costs change real execution. Half dimensions can lose a small aircraft/shadow, so reduced resolution is an experiment with a readability gate, not an assumed fourfold speedup.

The existing proposed RT screen ceilings remain **≤2.0 ms incremental GPU p95** and **≤128 MiB peak incremental allocated GPU resources for the entire effect**. They are rejection ceilings, not an allowance to spend when measured headroom is smaller, nor a prediction of NVIDIA or AMD cost. Count scratch/history/AS and in-flight copies; distinguish allocated bytes from residency and disclose observability gaps. Compatibility's existing combined `+0.5 ms` frame-p95 delivery ceiling and the separate High baseline still apply under [VQ-07](../../plans/advanced-graphics.md). RT cannot borrow time from physics or bypass renderer parity.

At 60 Hz, the existing full-flight screen requires process p95 ≤18 ms, p99 ≤25 ms and simulation/wall 0.99–1.01, with long intervals and real-render throughput reported. These are the owner's screening gates, not a guarantee of every frame meeting the nominal 16.67 ms interval. Higher refresh targets need their own tighter budget. A quality candidate need not make rendering 5% faster, but must show the selected visual gain inside cost and pilot-readability gates. A claimed optimization must meet the separate predeclared improvement/variation rule in [06](06-validation-and-benchmark-plan.md).

## 7. Work sequence, tests and exit decisions

This decomposes **existing M4** under the [integrated plan](05-integrated-implementation-plan.md). Measurement repair remains **five engineering days total for M0**. Its ownership, valid sample identity and overhead work already have file boundaries; do not add a second profiler, telemetry service or mandatory vendor-tool wrapper. Reuse existing native captures, frame diagnostics and scene oracles. If one concrete question needs a vendor capture, use Nsight or Radeon tools directly inside the existing attribution limit.

| Decision point | Concrete delivery for the senior engineer | Verification and stop condition |
| --- | --- | --- |
| Admission after the relevant baseline | One named shadow defect, fixed source/engine/templates, real 1080p camera path, selected raster control and measured headroom. | If current PCSS/settings/material repair solves it, deliver that correction. If no visible defect or headroom exists, defer RT. No new measurement sprint. |
| First two engineering days of M4 | Exact device/backend contract, compiled known-triangle and parameter fixture, legitimate SBT/AS path, proposed sun insertion and lifetime plan. | Hit/miss/distance/instance versus independent CPU reference; parameter variation; absent-feature/create-failure behavior. Missing scene or shader seam means raster/defer. This is a feasibility decision inside the broader capability work, not a promise of a complete feature in two days. |
| Visible checkpoint by two weeks | Correct opaque fixture, rigid moving caster, raw mask and integrated selected-sun image, bounded cost/memory and explicit missing coverage. | Ambient/emission/second light unchanged; sun diffuse/specular correct at visibility 0/1; cloud transmission once; off-camera caster; no detached shadow. If no useful correct result, stop. The existing 2–4-week fixture estimate is not a silent extension past this review. |
| Separately approved continuation within the existing owner | Real aircraft/field coverage, alpha/deformation policy, geometry/instance generations, stable motion and current data; optional finite-sun filter only when justified. | RT-03/04 lifecycle and coverage plus named pilot cases. Incomplete relevant geometry falls back for the viewport. Normal-flight integration remains a rough **6–12+ engineer-week** estimate with substantial uncertainty, not an automatic next commitment. |
| Candidate qualification and delivery | Default-off option only for exact eligible packages, truthful requested/effective reason and clean raster recovery; paired NVIDIA/AMD results for rows being offered. | Three alternating native A/B pairs, 10 s warmup + 60 s measured active flight per run; uncertainty/repeat policy from [06](06-validation-and-benchmark-plan.md). Finalist motion/lifecycle and owner export/endurance gates follow. Other devices/OS remain unqualified. |

Use the existing RT-01–06 tests, not six new duplicate frameworks. [test_shadow_settings.gd](../../../app/tests/test_shadow_settings.gd) and [test_high_graphics_profile.gd](../../../app/tests/test_high_graphics_profile.gd) are policy starting points. [shadow-energy tooling](../../../tools/graphics/test_shadow_energy.gd) supplies an existing small raster light-energy fixture; it must gain an actual candidate path before it can check RT, and its 512×256 diagnostic size does not qualify 1080p. Existing camera-history, lake, cloud, propeller and wind tests provide their respective contracts; select only those affected by an implementation. The [execution playbook](11-test-and-execution-playbook.md) retains verified commands and native-device ownership rules.

For image acceptance, predeclare four relevant paired cases: **landing/pilot**, **treeline/wind**, **Workshop**, and **sunset lake**. The first two select a flight-shadow candidate; the latter two are later material/reflection controls unless that code changes. Record attitude recognition, stable markings, correct occlusion and history under motion; a lower image-error number alone cannot authorize reduced readability. Retain raw and filtered images plus a compatible converged reference for stochastic effects. Vary camera cut, zoom, resize, pause/resume, world/aircraft switch and unsupported-scene entry where the implementation changes that behavior. Extend existing captures only when a specific oracle cannot be expressed; do not run the entire cross-product before a first candidate is useful.

## 8. Research-to-code handoff

Start reading in this order: exact [Godot seam audit](10-reflex-and-ray-integration-design.md#2-direct-sun-ray-tracing-real-seams-and-limits), Vulkan query/AS tutorial in the [vendor guide](ray-tracing/01-nvidia-amd-integration-guide.md), the existing shadow/High source, then the [cloud/material contract](ray-tracing/02-clouds-materials-and-water.md). Consult denoiser and richer reconstruction guides only when their input signals exist. Use original developer cases to choose negative tests: [driver parameter disagreement](community/03-ray-tracing-cases.md#c-rt-01--nvidia-push-constants-failed-while-an-amd-run-appeared-correct), [static-scene versus deformation limits](community/03-ray-tracing-cases.md#c-rt-02--reported-fast-rt-did-not-solve-deforming-geometry), [GPU timeout attribution](community/03-ray-tracing-cases.md#c-rt-03--a-lightmapgi-timeout-was-initially-confused-with-memory-pressure), [numerical/resource guidance](community/03-ray-tracing-cases.md#c-rt-04--self-intersection-attribution-and-an-external-allocation-improvement), and [cross-viewport ownership](community/03-ray-tracing-cases.md#c-rt-05--cross-viewport-texture-sharing-remained-unresolved). These remain reported cases with their original outcomes, not new simulator observations.

Expected first deliverable: an engineer can decide **implement a demonstrated raster/material correction**, **continue one correct RT sun fixture**, or **defer RT with a specific missing prerequisite**. Expected later product, only if evidence supports it: a bounded optional quality choice that preserves the existing 240 Hz float64 flight model, accepted input, `sim_clock`, pilot readability, raster fallback and package identity. This research does not promote a capability flag, SDK download, menu choice or attractive external demo into that result.
