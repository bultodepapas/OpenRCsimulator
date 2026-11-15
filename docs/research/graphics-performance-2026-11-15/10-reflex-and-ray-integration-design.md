# Reflex and direct-sun ray tracing: senior implementation handoff

**Research, 2026-11-15.** Audit branch HEAD `725cb17585475999d3c5ef01f0af41643b3d0c36`; application baseline `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. This is a source-reading design, not a patch, hardware run, product commitment or claim of latency or rendering improvement. It extends [03](03-latency-reflex-and-boost.md), [04](04-ray-tracing-in-godot.md), [05](05-integrated-implementation-plan.md), [06](06-validation-and-benchmark-plan.md) and [R08–R20](08-twenty-external-investigations.md). Current decisions and evidence stay with VQ-07d/h, F6, GDU and the applicable DT owner. Read the actual final source and receipts again when implementing; the NVIDIA fork and official beta2 are different engines.

The next latency work is to qualify the **existing** Windows/Vulkan Reflex path with its pinned Streamline 2.11.1, not add a second pacer. The next RT decision is a **two-engineering-day feasibility review** on one available Vulkan device after a reproducible visual defect and baseline/headroom exist. A direct-sun shadow is an optional experiment: by the two-week checkpoint produce a useful, correct opaque-fixture image with cost and missing coverage, or stop. This does not replace the existing 2–4 week controlled-fixture estimate or the separate 6–12+ week normal-scene estimate. M0 remains five engineering days total, not a new measurement platform. A failed or unavailable RT route retains raster; no new player control is justified by this document.

## 1. Reflex: actual ownership and ordering

The regular application persists `off`, `on`, `boost` in [`display_preferences.gd`](../../../app/app_state/display_preferences.gd), defaulting to On, and [`reconstruction.gd`](../../../app/render/reconstruction.gd#L190) makes the request through [`nvidia_reflex.gd`](../../../app/render/nvidia_reflex.gd). The adapter checks the singleton, method, integer constant and status shape before sending a mode. Its receipt distinguishes `requested`, `accepted`, availability, pending and a reason. A valid `SetOptions` result is **SDK acceptance**, not a measurement. Unsupported On/Boost remain visible but disabled and the saved request survives; Off remains selectable. Settings preview/revert and Keep already have tests. Direct/technical launches use `OPENRC_NVIDIA_REFLEX` through `startup_config()`, whereas a Home flight reapplies saved display preferences. The historical trial-only [`reflex_startup.gd`](../../../tools/graphics/native/reflex_startup.gd) defaults Off and must not be confused with the regular product's default On.

The engine path is the pinned [NVIDIA fork `135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`](https://github.com/NVIDIA-RTX/godot/tree/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76), plus the **ordered** local stack in [`build.py`](../../../tools/graphics/native/build.py#L33): in particular [`dlss_frame_lifecycle.patch`](../../../tools/graphics/native/dlss_frame_lifecycle.patch), [`reflex_lifecycle.patch`](../../../tools/graphics/native/reflex_lifecycle.patch) and then [`reflex_sync.patch`](../../../tools/graphics/native/reflex_sync.patch). The final behavior is the composition of those patches, not the intermediate before-sync code in `reflex_lifecycle.patch` alone. The original [Windows loop](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/platform/windows/os_windows.cpp#L2353) pumps events then calls `Main::iteration`; the [original iteration](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/main/main.cpp#L4958) marks simulation start/end, synchronizes the prior draw and enqueues the next. The patches add the following effective sequence, after startup warm-up:

```text
end of iteration N-1, including the fixed-FPS branch:
    request a new Streamline frame token N
    if the Reflex plugin is supported: slReflexSleep(token N), even if mode Off
    # Sleep is outside the settings mutex; do not block the render thread with that lock.
Windows event pump -> simulation start N -> one or more physics ticks / process -> simulation end N
RenderingServer.sync()  # drains prior CPU render commands; not proof GPU finished
AFTER_RENDER_SYNC: refresh Reflex state; apply pending/forced options serially
queue (token N, captured numeric ID N), then queue draw N
render thread: install queued token N -> render-submit start/end -> present start/end
```

On startup a token or marker can be absent before the first normal cycle; in low-processor/minimized/no-draw paths there need not be a present for each simulation iteration. The frame token labels an engine/render iteration, not each of OpenRC's 240 Hz physics ticks, each OS input event, or a physical scanout. The [frame-token patch](../../../tools/graphics/native/dlss_frame_lifecycle.patch#L75) keeps each draw's token from accidentally following the main thread into N+1 and checks the bounded SDK token ring before the render marker. The [fixed-FPS patch](../../../tools/graphics/native/dlss_frame_lifecycle.patch#L458) adds the otherwise skipped message-loop-tail marker; fixed-FPS is a functional stress fixture, not an F6 measurement. Changing mode during N's simulation is applied after render sync and its effect on Sleep begins no earlier than the next call. Do not claim each asynchronous status field is an atomic, coherent snapshot of a single frame.

The pinned [Reflex header](https://github.com/NVIDIA-RTX/Streamline/blob/019994e18d256a3e92347888deb527feb7f58bc0/include/sl_reflex.h#L148) declares `GetState` and `SetOptions` not thread safe and Sleep thread safe; the [PCL header](https://github.com/NVIDIA-RTX/Streamline/blob/019994e18d256a3e92347888deb527feb7f58bc0/include/sl_pcl.h#L114) says PCL `SetOptions` is not thread safe and `SetMarker` is thread safe. The patch uses the prior-draw sync to serialize non-thread-safe SDK operations against prior render/present callbacks. That synchronization can itself affect pacing. The SDK [2.11.1 guide](https://github.com/NVIDIA-RTX/Streamline/blob/019994e18d256a3e92347888deb527feb7f58bc0/docs/ProgrammingGuideReflex.md#L118) treats PCL and Reflex as separate features and calls supported Sleep/markers even when Off. Do not substitute a new direct `VK_NV_low_latency2` pacer in the same frame.

### State-machine contract to preserve or strengthen

The following pseudocode describes desired observables and failure handling around the existing implementation; `token N`, event records and the test hook are concepts, not new shipped APIs. An unavailable capability is different from a latched call failure.

```text
on player_request(mode):
    validate mode in {Off, On, Boost}; retain saved request independently
    if API/status absent or invalid: report unavailable or unconfirmed; no false success
    otherwise enqueue native request even if capability is currently pending

on device created:
    discover Reflex and PCL independently; load exact SDK entry points
    stage PCL options and initial Reflex Off/options; accepted = unknown

on AFTER_RENDER_SYNC, on the serialized owner:
    apply dirty PCL options; latch failure if call or required entry point fails
    if Reflex feature exists:
        state = GetState(); latch API failure, but a successful lowLatencyAvailable=false
            is an availability withdrawal, not an SDK call failure
        desired = request if state available and PCL ready and no latch else Off
        if request/availability changed or a forced-off is pending:
            result = SetOptions(desired)
            if result succeeds: accepted = desired
            else: latch failure; attempt SetOptions(Off) once; accepted = Off on
                successful fallback, otherwise unknown; never rewrite saved request
    report unsupported, pending, accepted or runtime_failure honestly

on BEFORE_MESSAGE_LOOP:
    token = get_new_frame_token()  # null/failed token is a failure, not frame zero
    if Reflex plugin exists: Sleep(token), including when Off
    latch a failed Sleep and force Off at the next serialized update
on PCL callback:
    simulation uses main token; queued render/present uses draw-captured token + ID
    if null at startup: skip; if captured token expired or marker call fails:
        latch PCL failure and request Off; do not silently attribute it to a later frame
on session teardown/device change:
    stop further callbacks before destroying SDK resources; report any unknown Off
    do not assume a prior failure latch or asynchronous request recovered on recreation
    until a fresh device/session is explicitly checked
```

`reflex_sync.patch` refreshes `lowLatencyAvailable` on every synchronized frame. A successful temporary withdrawal requests Off; a later return can reapply the unchanged player request. A Reflex/PCL error is latched in this session; fallback itself can fail, leaving `applied_mode = -1` (unknown). Sleep continues to be attempted while the feature is reported present even after a latch; the code does not turn its counter into proof of successful recovery. Verify shutdown and device recreation before promising automatic recovery.

**A specific flash gap.** The pinned SDK guide says that when `flashIndicatorDriverControlled` is true, the application should send a trigger-flash marker for left mouse clicks; `sl_pcl.h` defines `eTriggerFlash`. The inspected [fork's marker switch](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/drivers/streamline/streamline.cpp#L142) and local patch map simulation/render/present and `ePCLatencyPing`, but a search of `app/` and `tools/graphics/native/` found no trigger-flash mapping or `flashIndicatorDriverControlled` handling. The local F13 key-down-only ping is **not** the flash trigger. This is a bounded source-inspection gap, not a reproduced device failure or proof about SDK internals. Inspect the actual prepared source/build for any additional path, and, if missing and applicable, make one small engine integration change under VQ-07h: react only to the relevant click edge, honor the SDK state, attach the correct current frame token, and avoid double triggers/repeats. Then use the pinned SDK's Verification HUD/Test Utility and flash path. If the utility, necessary hardware, fullscreen mode or flash path is unavailable, keep full SDK verification open; a correctly documented F6 optical comparison and ordinary player-setting comparison may still proceed independently.

### Proposed focused tests and discriminating oracles

Use existing tests and their owners; test IDs below are proposed additions, not existing passing tests. An isolated fake SDK seam should call the **actual patched** owner/marker methods and record bounded event tuples `(kind, frame_id, result)` in a fixture, not create a new shipping telemetry service. Keep vendor calls and production scheduling intact; inject failures only in a disposable native test build. A result unavailable to that seam is an explicit hardware/manual gap, not a passing fake.

| ID / extension | Stimulus | Required oracle |
| --- | --- | --- |
| **RX-01** · extend `test_nvidia_reflex.gd` | Valid Off/On/Boost, malformed status type/range, missing method/constant; unavailable → available → unavailable without changing requested Boost. | Never invoke an invalid API; Off selectable; saved/requested Boost unchanged; `pending`, `accepted`, `reason` track the actual fake reports. Existing script already covers many individual cases; add transition assertions only where missing. |
| **RX-02** · extend `test_advanced_graphics_settings.gd` | Preview Boost, backend withdraws or fails, Revert and Keep; simulate late acceptance after preview was reverted. | No unsupported mode becomes selectable or silently saved; latest request wins; old acceptance is shown pending/unconfirmed until the backend reports current state; no unwanted preference rewrite. |
| **RX-03** · extend native `repro/reflex.gd` or a narrow native fixture | Off → On → Boost → Off with default and separate render thread; include fixed FPS in the dedicated functional run. | Successful options, state/Sleep and simulation/render/present progress per drawn phase; zero expired tokens and SDK/validation errors. Existing counters establish progress, not paired same-frame identity. |
| **RX-04** · native fake/event seam | Delay render N until main owns N+1; exercise no-draw/minimize/startup, then resume; use a deliberately recycled token. | For each actually drawn frame, render and present markers use that draw's captured token/ID, ordered starts before ends; skipped draws do not fabricate a present. An expired token produces a latched failure/Off request, never a marker attributed to N+1. Do not compare independently sampled `last_*_frame_id` values as though they were a coherent event trace. |
| **RX-05** · native fault seam | Independently fail missing Reflex/PCL function, PCL options, `GetState`, first `SetOptions`, Off fallback, Sleep, or PCL marker. | Preserve request; first relevant error is reported; force Off at the synchronized boundary; failed mode change + successful Off reports Off, failed Off reports unknown. No repeated warning storm; no deadlock while Sleep waits. The current failure-result atomics can be overwritten by later failures, so use fixture call records to identify the first failure; do not assume the status preserves it. Keep a physical driver/device-loss trial separate from this fake. |
| **RX-06** · native availability seam | `lowLatencyAvailable`: false → true → false → true with successful SDK calls; then a genuine call failure. | The first changes gate and reapply the saved request without latching; call failure latches and must not be mistaken for recovery when availability returns. |
| **RX-07** · F13 and flash test | F13 press/release/repeat, left mouse down/up/repeat with driver-controlled flash state both true and false, and no initial token. | One ping per non-echo F13 down; flash trigger semantics follow exact SDK state and one actual click edge, with a valid consuming frame token. F13/release must not trigger flash. Verify utility flash separately on real NVIDIA hardware. |
| **RX-08** · lifecycle and export | Resize/minimize/restore, render-thread mode change in fixture where supported, exit, device/session recreation; verify matching editor/template/runtime receipts. | No marker against retired token/device, hang, invalid SDK call or silent active mode after failure. On recreation, prove initialized state and fresh status rather than assuming the old latch reset. |
| **F6-01** · existing `test_latency_patch*.gd` | Run option, actual main route and CLI rejection checks. | Raw axis after flight poll; disconnected/paused/fault/invalid is gray; read-only physics checkpoints match; forbidden combinations are rejected before creating trace output. These tests do not measure radio-to-photon latency. |

### Executable checks already present

Run from the repository root on the named host with its project imports prepared. These commands are **proposals to run**; none was run in this research. [`tools/godot/run_checked.py`](../../../tools/godot/README.md) scans engine/script/shader errors as well as the required literal and exit status; retain its full report/log. Shared hosts use [test-queue admission](../../../tools/testqueue/README.md), their session handle and verified teardown. The pool classifies script paths containing `latency` as performance work and rejects them from the functional pool, even though these particular F6 tests are software checks; the ordinary checked runner sends them through the existing same-host admitted path. Do not rename them to evade classification.

```powershell
# On a configured test pool: these two independent headless policy/UI checks
# use the official configured engine, and do not establish native SDK support.
python tools/testqueue/testctl.py pool run --source . --platform windows --timeout 180 --require '0 failed' --script res://tests/test_nvidia_reflex.gd --script res://tests/test_advanced_graphics_settings.gd

# Same-host F6 software checks, with the pinned official editor and imports.
$Godot = (Resolve-Path '.tools/Godot_v4.8-beta2_win64_console.exe').Path
python tools/godot/run_checked.py --out-dir tmp/f6-handoff --label f6-unit --timeout 180 --require-text '0 failed' -- $Godot --headless --path app --audio-driver Dummy --script res://tests/test_latency_patch.gd
python tools/godot/run_checked.py --out-dir tmp/f6-handoff --label f6-route --timeout 180 --require-text '0 failed' -- $Godot --headless --path app --audio-driver Dummy --script res://tests/test_latency_patch_route.gd
python tools/godot/run_checked.py --out-dir tmp/f6-handoff --label f6-cli --timeout 180 --require-text '0 failed' -- $Godot --headless --path app --audio-driver Dummy --script res://tests/test_latency_patch_cli.gd
```

For the existing rendered NVIDIA fixture, use the actual receipt-matched custom **editor**, a fresh copy of `tools/graphics/native/repro` and the installed Vulkan validation layer as described in its [README](../../../tools/graphics/native/repro/README.md). With `$Godot` and `$Project` set as there, run these separately on an exclusive native display:

```powershell
python tools/godot/run_checked.py --out-dir tmp/reflex-handoff --label reflex-modes --timeout 150 --require-text 'REFLEX_SMOKE|COMPLETE' -- $Godot --verbose --path $Project --audio-driver Dummy --script res://reflex.gd
python tools/godot/run_checked.py --out-dir tmp/reflex-handoff --label reflex-separate-fixed --timeout 150 --require-text 'REFLEX_SMOKE|COMPLETE' -- $Godot --verbose --render-thread separate --fixed-fps 60 --path $Project --audio-driver Dummy --script res://reflex.gd
```

The fixture exits 2 when headless, missing the patched API or unsupported. Require `REFLEX_SMOKE|COMPLETE`, zero engine/validation errors and review warnings; do not turn unavailable into pass. Where an owned **debug-template** app session exists, the existing `python tools/debug/debugctl.py run tools/graphics/native/reflex-smoke.txt --fail-on-error` exercises the actual app's backend; its session port and queue handle must belong to the caller. The regular `product.py` package uses a release template, so do not assume it exposes the debug bridge. Verify the product and its editor/template/runtime receipts with `python tools/graphics/native/product.py --verify`; package and launch commands are in the [native guide](../../../tools/graphics/native/README.md).

### Physical F6 comparison

[F6a](../radio-input/F6a/README.md) reads the live `FlightSession` raw axis after its poll at physics priority 1, displays a 192-pixel threshold square, and never changes physics. The direct technical route rejects `--scripted`, `--frametimes`, `--trace`, `--capture` and `--visual_pose`; collect those diagnostics only in separate matched runs. A concrete Windows example using a verified NVIDIA package is:

```powershell
$Exe = (Resolve-Path 'dist/windows-nvidia/OpenRC Simulator.exe').Path
$env:OPENRC_NVIDIA_REFLEX = 'off'
& $Exe --resolution 1920x1080 -- --latency-patch --latency-axis=0 --latency-threshold=0
```

Repeat the same verified executable and route with the environment value `on` and then `boost`; alternate/counterbalance order and reset the variable afterward. This direct route uses startup configuration rather than Home's saved preferences. Record actual renderer/driver, drawable size, mode acceptance and presentation condition; if SDK acceptance cannot be observed in the release direct route, do not infer it from the environment variable—use the regular Home settings/accepted status or a separately validated instrumented build and label the distinction. A Home flight has an existing **Latency camera marker** switch in the overlays dialog and uses saved player settings; it defaults to axis 0/threshold 0 when enabled there. Use the CLI for another validated raw axis/threshold. Do not alter the physics or remove the parser guard.

Predeclare the primary endpoint and useful threshold, exclusions and no-regression limits. Film the physical stick reference and patch together with known acquisition rate, fixed exposure/scan position, radio/USB/RF/firmware, refresh, VSync, cap, frame rate, camera and scenario. At least 100 valid transitions per condition across repeated sessions is a starting target, with uncertainty/session variation and a predeclared repeat for one named confounder; more data is needed or the result is inconclusive when uncertainty exceeds the threshold. F6a's older 20-transition procedure is a minimum screen, not this study's tail-precision claim; [06](06-validation-and-benchmark-plan.md#reflex-and-boost) asks for at least 30 as a screen. At 240 fps one camera interval is about 4.17 ms, before exposure/rolling-shutter/mark uncertainty. Report stick-to-patch and stick-to-first-visible-control-response separately; a black/white marker reports sampled raw axis, not servo or aircraft response. PCL/flash is a software/vendor endpoint, not RC latency. Measure Boost clocks, power and thermals and actual frame distributions separately. One predeclared repeat at most, then recommend a mode or retain an inconclusive outcome.

## 2. Direct-sun ray tracing: real seams and limits

### Exact lighting insertion point

For official beta2 `cafc17a192acf67903910a68aeb3c076c0907a4b`, the [Forward+ shader](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl#L2373) computes directional shadows and later reconstructs per-light `shadow`, applies shadow opacity and passes it as attenuation to [`light_compute`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl#L2728). Diffuse and direct specular are accumulated separately from ambient/indirect and emission. This is a concrete **candidate engine patch seam**, not a public compositor input. Do not assume directional-light index zero is always the sun: OpenRC creates [`Sun`](../../../app/render/atmosphere.gd#L962), while [lightning](../../../app/render/weather/lightning.gd#L272) and other scenes can create other directional lights. The engine needs a verified stable light identity/mask and matching per-viewport generation. The selected sun's raster shadow must be **replaced**, not multiplied again, by the experimental visibility within the admitted scope. Keep the sun's cloud transmission, light energy, shadow-opacity/fade semantics and any defined lightmap/contact-shadow policy explicit; [ground's custom `light()`](../../../app/render/ground.gdshader#L391) consumes `ATTENUATION` and applies cloud transmission. A separate specular buffer is not a separate sun buffer. Never darken the already combined frame, sky, ambient, emissive or other lights.

The [actual Forward+ order](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L2199) is optional depth prepass → pre-opaque compositor → opaque pass → post-opaque compositor. If there is no depth prepass, the source warns that pre-opaque resolved depth is unavailable; pre-opaque color has not been rendered. Normal/roughness is a specially encoded prepass buffer, not proof of every material's matching sample. [CompositorEffect](https://docs.godotengine.org/en/4.7/classes/class_compositoreffect.html) runs on the render thread and its `RenderData` is valid only for that callback; [RenderData](https://docs.godotengine.org/en/4.7/classes/class_renderdata.html) and [RenderSceneData](https://docs.godotengine.org/en/4.7/classes/class_renderscenedata.html) expose buffers/camera data, not a complete scene BLAS/TLAS/material inventory. A local RenderingDevice cannot share the global device's resources or draw to its screen ([RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)); a separate local device is not a shortcut to this viewport.

**Smallest candidate:** in a controlled single-sun opaque floor/occluder fixture, either (A) use an engine-owned pre-opaque query/visibility pass only after proving a matching depth/normal prepass, then explicitly bind its result into the selected sun's lighting path; or (B) investigate a direct query at that per-light point without a history/denoiser. Both need engine-side bindings and scene inputs. A compositor by itself cannot make Godot's lighting shader sample the result. No existing API is asserted for supplying such a mask. For A, verify projection, reverse depth, view index, viewport origin, internal/output extent, jitter, MSAA/sample coverage, material discard and the receiver's depth match; reject unsupported transparent, displaced or mismatched samples. For B, verify query shader capability, correct normal/bias/light direction and actual compiled variants. Either route must be rendered and timed before being preferred.

```text
# Intent only; no proposed function below is an existing Godot API.
for each eligible receiver / actual designated sun in the admitted fixture:
    raster_visibility = existing selected sun raw-shadow calculation
    if current_generation.valid AND receiver_sample_matches AND
       complete_relevant_caster_set AND scene_materials_supported:
        selected_visibility = ray_visibility  # replace, do not multiply by raster
    else:
        selected_visibility = raster_visibility
    sun_attenuation = apply_selected_sun_opacity_and_approved_range_fade_once(
        selected_visibility)
    shade this sun once with sun_attenuation and its existing material/cloud policy
    preserve all other light, ambient, indirect and emission terms
```

This is an opaque controlled-fixture rule. Normal-flight acceptance requires complete relevant scene coverage; until then retain the entire player viewport's raster result, not a plausible mask with silently absent casters. If an explicitly designed spatial/material partition is ever considered, its disjoint ownership and seam must be proven independently; it is not authorized by this pseudocode. Coordinate with [`shadow_settings.gd`](../../../app/render/shadow_settings.gd) and projected aircraft/field cues so the same occluder is not double applied; current `auto` can retain both native and projected techniques for their existing coverage.

### Geometry, materials and lifetimes

The pinned [mesh storage](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp#L372) creates ordinary vertex/index buffers with storage flags as appropriate but, in those examined paths, **not** the RD AS-build-input creation flag. Its [`mesh_get_surface`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp#L671) obtains surface bytes through `buffer_get_data`; it is not a free per-frame CPU scene feed. Compressed formats, index LODs and transformed or deformed GPU vertices need explicit conversion/ownership. The pinned [`RenderingDevice::blas_create`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp#L352) consumes RD vertex/index buffer RIDs, not arbitrary scene nodes. A fixture can create its own vertex/index buffers with both `BUFFER_CREATION_DEVICE_ADDRESS_BIT` and `BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT`: the pinned Vulkan BLAS path obtains their [device addresses](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.cpp#L6378). Validate all format/usage and actual device requirements; sharing stock scene buffers would require a proven compatible engine path or an engine change with explicit lifetime and usage flags. Do not read back all surfaces or scan the scene every frame.

| Scene input | Bounded first fixture | Normal-flight dependency and fail-safe |
| --- | --- | --- |
| Static opaque mesh | Explicit floor and one off-camera triangle/box, stable source + owned buffers, one BLAS per immutable mesh/LOD. | Track resource identity, topology/LOD/material and visibility revisions; include casters outside the camera frustum that can reach an admitted receiver along the light ray. Bounds/caster-distance truncation must be explicit and visually validated. |
| Rigid aircraft and hinged parts | One independently transformed rigid part; `sim_clock`/accepted presentation transform, never write simulation. | Track each actual current airplane, propeller and hinge transform plus instance mask; change TLAS instance transform or rebuild TLAS. Verify coordinate handedness, scale, winding/cull flags and large/negative transforms against CPU hits. |
| MultiMesh and vegetation | Exclude from the controlled fixture and label it. | Enumerate real instance transforms, LOD and shadow flags without assuming the camera's visible list is the full caster list. [Imported vegetation](../../../app/scenery/imported_vegetation.gd#L219) uses MultiMesh and can cast shadows; [motion shader](../../../app/scenery/motion.gdshader#L20) deforms vertices. Reproduce the same accepted `sim_clock`/wind deformation into AS-compatible data or reject that viewport; a rigid source mesh is insufficient. |
| Alpha-cut surface | Add one controlled textured card only in a later coverage test. | Mark cutout geometry non-opaque; at each candidate obtain instance/geometry/primitive and barycentrics, interpolate actual UV, sample the matching alpha/material rule and confirm only a solid hit. Match cull/two-sided behavior and texture/LOD policy. Unknown material, invalid index, missing texture or shader-defined discard rejects the affected normal-flight scene. Khronos [ray traversal](https://docs.vulkan.org/spec/latest/chapters/raytraversal.html) separates candidate from confirmed hits; blindly treating leaf cards opaque creates solid rectangles. |
| Transparent, smoke, water, rotor blur, particles | Exclude and document in the fixture. | Define actual cast/receive/transmission policy per material; if a relevant effect cannot match the baseline or has no valid receiver sample, retain raster. Do not pretend opaque motion vectors cover them. |
| Changes, removal and failure | Deliberately alter one mesh and instance at a time, including a removed off-camera caster. | New world/aircraft, mesh edit, LOD, skin/wind, material, mask, camera cut, resolution and device loss invalidate the matching generation. The pinned [`blas_build`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp#L495) invalidates dependent TLASes: rebuild them after a BLAS rebuild. `ALLOW_UPDATE` is not proof of an exposed refit path; the inspected Vulkan backend builds with BUILD mode. |

The project already has a **separate experimental Metal** 0018 one-shot scene diagnostic: it expands certain inputs, searches beyond the camera frustum, rejects unsupported materials/deformation, and intentionally flushes/stalls for trace/readback ([guide](../../../tools/graphics/metalfx/README.md#renderer-owned-scene-geometry-diagnostic)). It is useful evidence about candidate enumeration and failure handling, not a reusable asynchronous per-frame Vulkan scene feed. Its M1 witness does not establish a shipping effect or stock Metal support. Official beta2's [Metal RT methods](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/rendering_device_driver_metal.cpp#L2380) are stubs; the local 0005/0018 prototype and real Apple API/device capability are separate facts.

### Proposed render-thread ownership and failure contract

```text
DISABLED: no scene scan, AS, history or RT dispatch; retire prior generations safely
PROBING: verify actual renderer=Forward+, driver=Vulkan, feature bits, formats,
         shader compilation, AS/SBT creation, and a known hit and miss
PREPARING(g): capture an immutable, bounded scene-description generation g on the
         correct owner; upload compatible buffers and build changed BLASes
         outside an open RD draw/compute/raytracing list; rebuild dependent TLAS
READY(g): submit build -> query -> any denoise -> selected-sun shade through the
         main RD graph with known dependencies; publish g only for the matching
         viewport, camera/depth, light, dimensions and geometry/material versions
REJECTED / STALE / FAILURE: use complete raster for that viewport; retain reason,
         invalidate current and previous history, and stop publishing old g
RETIRING: stop new submissions and keep every referenced source buffer, BLAS,
         TLAS, SBT range, uniform set, image and history alive until actual safe
         completion; retire on device/render owner, then release in dependency order
```

This is a required ownership contract, **not** a claim that a public main-RD completion/fence API is already available. The pin's RD graph records AS build trackers and a read tracker for an AS uniform; [`free_rid`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp#L7846) queues AS disposal per frame. Those mechanisms are relevant evidence, not proof that every external buffer, shader binding, concurrent rebuild and cross-frame history is safe. Vulkan requires build-write → query-read and the appropriate resource/stage dependencies; see the [Khronos synchronization guide](https://docs.vulkan.org/guide/latest/extensions/ray_tracing.html#_synchronization_for_ray_tracing). Prove graph dependencies and actual completion/retirement on the exact engine/backend with validation and repeated in-flight destruction; if no safe bounded mechanism is available, stop or propose the minimal engine change as a separately costed dependency. Do not call local-RD `sync()` on the main flight loop, block every frame on CPU readback, assume a fixed number of frame delays is a fence, or allow an unbounded pending generation queue. A stale or partial result must never shade the next world.

### Query-only / SBT feasibility: a real decision, not a workaround

The exact beta2 [`tlas_build`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp#L582) rejects a zero `hit_sbt_range` for an instance with a BLAS. [`hit_sbt_create`](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp#L692) looks up a real ray-tracing pipeline. The [documented normal range](https://docs.godotengine.org/en/4.7/classes/class_renderingdevice.html#class-renderingdevice-method-hit-sbt-range-alloc) is allocated from an SBT and initialized, not fabricated. Source inspection establishes a query-only risk, not a reproduced Vulkan failure; the check itself does not prove ownership validation. The local Metal patch's exception is not a stock Vulkan capability. There is an additional **possible crash**, not merely an expected error: the RD [`raytracing_pipeline_create` front-end](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp#L5267) admits query **or** pipeline support; the [Vulkan driver](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.cpp#L1582) initializes the [function pointer to null](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.h#L135), loads `vkCreateRayTracingPipelinesKHR` only if its extension was enabled and [calls the pointer](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.cpp#L6701) with no evident null check. A query-only device does not by itself prove that pointer is null, but a configuration lacking the enabled extension can reach a dangerous route. This source argument is not a reproduced crash; never intentionally call a known-null entry point.

Within the two-day review, in an isolated fixture on the **exact** stock pin:

1. Record both `SUPPORTS_RAY_QUERY` and `SUPPORTS_RAYTRACING_PIPELINE`, actual backend/device/driver, compile status and validation-layer identity. No RD in headless or Compatibility is an expected unavailable result.
2. On a device reporting **both** capabilities, create a legitimate minimal pipeline and allocated/initialized hit-SBT range using the documented RD route; build an owned triangle BLAS from buffers with the required build-input and device-address flags, one-instance TLAS, and execute a query shader. Check analytically known hit, miss, instance identity and distance against CPU geometry. If the actual pin cannot create or run this route, stop; a feature bit is not execution.
3. If an actual query-only device (query true, pipeline false) is available, first inspect which Vulkan extensions/features were actually enabled. In a disposable process, a known BLAS instance with a zero range can exercise the expected `tlas_build` rejection; retain the checked child failure and validation record as a **negative** test, not a successful ray. The existing checked runner deliberately fails on engine error records, so an outer test must assert that expected child result rather than mislabel its report as passing. Do not call pipeline creation with the extension or required feature absent, even though the RD front-end predicate admits the query bit; do not fabricate a nonzero range. No such device means **untested**, not failure or pass. Consider a narrowly reviewed engine fix only as a separate dependency if its native Vulkan semantics, lifetime and tests are established. Until then require both features plus a legitimate SBT for this stock-pin experiment, or mark the query-only row unsupported.
4. Independently prove the designated-sun insertion and bounded scene input/retirement seam. If either is absent, no headroom exists, or the triangle result fails, document retain-raster/defer at the two-day decision. No invented public `get_scene_tlas` or `get_direct_sun_buffer` exists in this handoff.

### Proposed effect tests and decision thresholds

The IDs specify future additions to the smallest existing graphics/native harnesses and checked runner; there is currently no executable stock Vulkan RT fixture in this audit. Do not present the following as already-passing tests or offer a fabricated command for it.

| ID | Controlled stimulus | Oracle and stop condition |
| --- | --- | --- |
| **RT-01 capability** | Query/pipeline false, independently true/false, invalid shader/allocation, valid triangle hit/miss and instance IDs. | False or failed operation produces unavailable/raster with an exact reason and no bogus RID; the both-true path passes a CPU hit/distance oracle and zero engine/Vulkan validation errors. Query-only remains unknown without that device. |
| **RT-02 light energy** | Fixed opaque plane/occluder; known sun, independently nonzero ambient, emission and a second light. Render raster/reference and raw visibility. | Sun diffuse **and** direct specular change according to ray visibility once; other terms remain within a predeclared floating-point/image tolerance. Visibility 1 reproduces the unoccluded sun, 0 removes only its direct contribution; never raster × ray or final-color multiplication. Include cloud transmission and shadow-opacity case. |
| **RT-03 coverage** | Camera sees receiver but not caster; move a rigid off-camera caster and one hinged part; compare TLAS generation and CPU intersection. | Correct current shadow and hit identity after each update; no stale frame or missing off-camera caster; source removal/LOD change invalidates and rebuilds as required. |
| **RT-04 materials** | Opaque, alpha-cut card with holes/cull modes, relevant MultiMesh/wind and the explicitly excluded transparent/propeller cases. | Per-candidate UV/alpha decisions match an independent raster/CPU reference; any unsupported relevant content rejects the whole normal-flight viewport instead of a partial RT scene. No physics changes. |
| **RT-05 lifetime and fallback** | Build failure, missing depth prepass, mismatched MSAA/extent, resize, pause/resume, world/aircraft replacement, resource invalidation, device loss, off/on and 20 warm cycles. | Complete raster returned without stale history, leaked/live resource growth, deadlock or use-after-free; actual GPU completion/retirement verified on exact backend, not inferred from a CPU callback. Reset any eventual temporal history on cuts, zoom and generation changes. |
| **RT-06 cost and usefulness** | Freeze 1080p native raster vs candidate, at least three alternating A/B pairs of 10 s warmup + 60 s measured active flight under the owning VQ protocol. | Predeclare the pilot-visible defect and compare raw visibility plus controlled higher-sample reference. Entire additional effect **≤2.0 ms GPU p95** and **≤128 MiB incremental peak allocated GPU resources**, including scene data, BLAS/TLAS, scratch, query, history/denoise, composition and in-flight duplication; the stricter measured whole-frame headroom wins. Report transients, memory observability and 60 Hz p95/p99/real-frame/readability guards from [04](04-ray-tracing-in-godot.md#budgets-and-acceptance). If no reliable cost or meaningful image/readability benefit, retain raster. |

The existing renderer commands, captures, `--frametimes` and VQ evidence format should be reused for compatible **separate** effect runs; do not combine them with a live F6 marker. Exact new fixture commands can be added to its owning README only after a real implementation establishes arguments and completion markers. The two-week checkpoint is a correct, useful, bounded result or a stop, not permission to claim full-flight alpha/deformation or support across operating systems.

## 3. Source record and limits

Newly inspected primary source beyond the earlier study: exact beta2 [Forward+ render order](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L2199), [directional-light shader](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl#L2728), [mesh buffer creation and readback](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp#L372), [RD AS build/dependencies](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp#L495), [NVIDIA Windows loop](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/platform/windows/os_windows.cpp#L2353), and pinned 2.11.1 [`sl_reflex.h`](https://github.com/NVIDIA-RTX/Streamline/blob/019994e18d256a3e92347888deb527feb7f58bc0/include/sl_reflex.h#L148), [`sl_pcl.h`](https://github.com/NVIDIA-RTX/Streamline/blob/019994e18d256a3e92347888deb527feb7f58bc0/include/sl_pcl.h#L114) and [verification guide](https://github.com/NVIDIA-RTX/Streamline/blob/019994e18d256a3e92347888deb527feb7f58bc0/docs/ProgrammingGuideReflex.md#L254). Versioned Godot 4.7 API documentation and current Khronos documentation describe contracts; exact beta2 source determines the pinned implementation. Search for absent flash or scene APIs is limited to the named inspected source and paths. No source check proves a device, shader, image, physical display, performance, export or release gate passed. Existing historical evidence remains historical.
