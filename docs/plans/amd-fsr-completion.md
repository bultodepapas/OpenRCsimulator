# AMD FSR completion plan

2026-10-28. Owner: VQ, under [VQ-07d/h](advanced-graphics.md), with UI, CAM, SM/FW/LU and DT/GDU owners. **Implementation is in progress; rendered validation and qualification remain open.** This is the authoritative remaining-work breakdown for AMD FSR; the parent retains renderer-wide gates. [Dated audit and implementation evidence](../research/advanced-graphics-2026-10-21/amd-fsr-2026-10-28.md).

## Outcome and scope

Finish the existing FSR2/FSR3 integration, adopt the latest verified AMD upscaling runtime on supported devices, and implement frame generation as a separately qualified presentation feature. Reuse Godot and AMD implementations and samples. Never author a replacement upscaler or infer support from an AMD GPU name alone.

The current SDK candidate is **AMD FSR SDK 2.4.0**, released on this plan's date. Start with **Windows/Forward+/Vulkan**, where OpenRC already has a native integration. SDK 2.4 removes the previous SDK 2.3 Vulkan blocker for upscaling and frame generation. DX12 is a separate later platform baseline, not a prerequisite for this first delivery. Preserve the official cross-platform engine and Standard recovery path while qualifying the custom engine.

"Ready" means usable settings, verified effective implementation, temporal correctness, failure recovery, reproducible packages, and named-hardware motion/performance/latency evidence. An SDK dispatch or a settings entry is insufficient. Do not describe the complete AMD family as implemented while any included component remains only a proposal.

| Component | Current OpenRC state | Planned disposition |
| --- | --- | --- |
| FSR1 spatial | Stock Godot capability; no app option | Add an explicitly spatial legacy option and qualify its usefulness on suitable hardware; it is not a substitute for temporal FSR |
| Stock FSR2 2.2 | Optional High controls, sharpening and persistence; custom engine reset wiring passed a bounded two-viewport rendered fixture | Validate motion, lifecycle and package behavior; stock engines cannot acknowledge the new explicit reset request, and remain unqualified for that contract |
| SDK FSR2 2.3.4 | Listed in SDK 2.4; not the stock Godot implementation | Inventory as a separate SDK provider; do not silently relabel embedded FSR2 or add a redundant default path |
| FSR3 analytical upscale | Existing custom Windows/Vulkan 3.1.4 path; SDK 2.4 feature-fix editor reports 3.1.6 dispatches but retains storage-format warnings | Resolve validation findings and qualify 3.1.6 before promotion |
| FSR4 ML upscale | Experimental SDK 2.4 candidate selector only; no ML dispatch or product setting established | Discover actual support and qualify 4.1.2 on eligible Radeon/APU hardware |
| Analytical / ML frame generation | Absent | Separate engine presentation work for 3.1.6 / 4.0.2 and swapchain 3.1.7 / 4.0.0 |
| Ray Regeneration 1.2.1 | Absent; no accepted ray-traced input pipeline for it | Separate conditional DX12/ray-tracing integration after raster and FG delivery; not required by upscaling |
| Radiance Caching 0.9.0 | Absent; AMD technical preview | Research-only until a compatible ray-tracing pipeline and production-suitable SDK exist; never include it in a completed production claim |

AFMF is a driver feature, not OpenRC's FSR integration. Dynamic resolution and AMD Anti-Lag 2 are separate optional work, not automatic consequences of FSR or FG.

## Verified starting point and ownership

Initial audit baseline: `a7b3a79bb185688aac6a91ecb3356e60bc1b8b7a`. Official engine: 4.8-beta1. Custom engine: NVIDIA fork `135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`, based on 4.8-dev. Historical FSR3 GPU evidence used an older isolated application candidate and does not qualify the current work.

Subsequent work added the shared reset path, SDK intake, matching isolated editor/template builds and a checked SDK 2.4 candidate package. A rendered FSR2 history fixture passed on the named test GPU; the FSR3 fixture and AMD's separate analytical sample both reported dispatches but failed Vulkan validation. A later feature-fix editor/template pair and candidate package passed their source and package checks, while FSR3 storage-format warnings remain. The package remains unqualified. Use source, build and package receipts for qualification; the [dated evidence](../research/advanced-graphics-2026-10-21/amd-fsr-2026-10-28.md#implementation-evidence-2026-10-28) separates these observations from missing GPU evidence.

| Boundary | Existing source / owner | Required change |
| --- | --- | --- |
| Reconstruction contract | [reconstruction.gd](../../app/render/reconstruction.gd), VQ | Explicit spatial/temporal/provider capabilities, SDK version selection, effective identity and bounded fallback |
| Persistence and UI | [display_preferences.gd](../../app/app_state/display_preferences.gd), [settings_screen.gd](../../app/ui/settings_screen.gd), UI/VQ | Backward-compatible saved requests, separate FG choice, EN/ES labels and Keep/Revert including failure |
| Startup and routes | [app_root.gd](../../app/app_root.gd), [main.gd](../../app/main.gd), UI/session owners | Preserve Home versus direct-launch semantics, runtime failure guard, camera/reset history events, all enabled vehicle routes |
| Native engine adapter | [engine.patch](../../tools/graphics/native/engine.patch), [fsr3.cpp](../../tools/graphics/native/fsr3.cpp), [fsr3_prepare.glsl](../../tools/graphics/native/fsr3_prepare.glsl), VQ | New SDK API/runtime, resource transitions, actual provider queries, history reset, correct motion/reactivity; later swapchain hooks |
| Native build/package | [build.py](../../tools/graphics/native/build.py), [build_sdk24.py](../../tools/graphics/native/build_sdk24.py), [product_sdk24.py](../../tools/graphics/native/product_sdk24.py), DT/GDU | Separate candidate cache, exact SDK hashes, signed runtime and notices, matching editor/templates, dependency/failure fixtures |
| Telemetry and evidence | [frame_diagnostics.gd](../../app/render/frame_diagnostics.gd), [graphics tools](../../tools/graphics/README.md), VQ/PT | Actual render/output sizes, provider/version/model where exposed, real/generated/presented rates, timing and memory, history-reset receipts |

No changes to float64 simulation state, tick/input ownership, aircraft generators or goldens. A generated display frame never advances the 240 Hz kernel, flight recorder, input sampler or audio/session clocks. Coordinate render-only previous-pose data with CAM/model owners.

## Design contracts to implement

**Capabilities and names.** Query the actual graphics device, renderer, API, runtime and effect. Record SDK version separately from the selected effect/provider version and its bundled/driver origin. A successful 3.1.6 analytical fallback on NVIDIA is not FSR4. Extend the existing adapter rather than creating parallel settings or launch machinery. Keep legacy `fsr2_*`, `fsr3_*` and sharpening preferences readable; migrate aliases transactionally only if necessary.

**Version policy.** The isolated candidate's `OPENRC_FSR_IMPLEMENTATION` selects `analytical` (default, requested 3.1.6), `ml` (requested 4.1.2), or `auto`. It enumerates device-supported IDs and requires the created context to report the selected ID for explicit overrides. These are candidate controls, not qualified product options. Qualification records the effective provider ID, version and origin. Accepting future driver-selected versions requires an explicit policy and renewed evidence. Pinning dependencies alone does not pin a driver-selected effect.

**SDK migration.** The candidate stages the signed `amd_fidelityfx_loader_vk.dll` and `amd_fidelityfx_upscaler_vk.dll` with matching headers; the existing SDK1.1.4 build remains separate. Its adapter uses the nested Vulkan `deviceContext`, upscaler API-version descriptor, provider query and fail-closed resource requirements. The bounded native FSR3 fixture reported analytical 3.1.6 dispatches but failed Vulkan validation. Verify actual exposure, resource transitions and failure behavior on the built candidate. The existing adapter requests automatic exposure rather than passing Godot's average-luminance texture as exposure.

**AA and scale.** Replace `provider != native` as the temporal test with provider metadata. Temporal reconstruction owns AA; spatial FSR retains suitable AA. Restore saved MSAA and scale 1 on fallback. Retain Native AA, Quality, Balanced, Performance and the separately named custom 85% trial only where supported. Use SDK quality queries for new providers. At 1080p, record exact rounded input dimensions; 2/3 is not the rounded literal 0.67. Do not add Ultra Performance as a default. Preserve native-resolution HUD/menus and independent lake/preview viewports.

**History.** The custom engine patch wires viewport reset generations to FSR2 and FSR3, with acknowledgement only after successful dispatch; fake-SDK and headless application checks cover the handoff. A bounded FSR2 rendered fixture covers deferred/coalesced requests and camera/scenario replacement on two viewports. The analogous FSR3 fixture reached its reset counters but failed Vulkan validation; moving-image and wider lifecycle proof remain open. Trigger on discontinuous camera/FOV/projection changes, scene/aircraft replacement, reset/restore/seek, provider/size change and recovery from invalid history. Continuous camera movement is not a cut. Pause/resume, minimization and long frame gaps need a declared policy. Reset previous matrices, object/deformation motion and jitter consistently; `reset_physics_interpolation()` alone is not an upscaler-history reset. Do not reset every frame.

**Inputs and transparency.** Verify linear HDR/pre-exposure, reverse-Z depth/range, motion-vector decode/sign/units and jitter, resource dimensions/formats and frame time against the exact new headers. Preserve Vulkan image layouts, stencil/depth aspects and render-graph dependencies. Inspect reactive/composition masks for canopy, propeller/rotor discs, smoke, water, clouds and lightning. Previous/current custom `sim_clock` deformation requires explicit motion validation; replacing it with nondeterministic shader `TIME` is not an acceptable repair. Do not blindly carry old SDK patches into signed binaries.

**Failure.** Preserve saved requests, show an actionable unavailable reason, and retain the existing safe Native fallback with restored AA. Context/dispatch failures must be latched and avoid an endless retry loop. SDK availability does not guarantee successful execution. Destroy only after GPU consumers finish. Test missing/wrong DLL, unsupported device/API, allocation failure, resize/minimize, device/swapchain loss and shutdown. Never let an optional provider prevent basic flight.

**FG presentation.** FG is independent of upscaling, defaults Off, and has one owner/provider at a time. Reuse AMD's swapchain implementation. Integrate device/queue creation, acquire/present replacements, synchronization, pacing and shutdown in the engine. Choose an explicit HUD-less image plus native UI composition strategy; test text, cursor, overlays and pause menus. Match SDK frame IDs to real rendered frames, including dropped/skipped frames. Disable/suspend generation for invalid history, inactive/minimized windows and unsafe transitions. Preserve existing DLSS/Reflex behavior and test provider switching; Anti-Lag is a separate capability.

Configure, PrepareV2 and generation use the same ID for one real frame; consecutive FG frames advance that ID by exactly one. A gap invalidates FG history. Define skipped/non-presented-frame handling explicitly rather than passing an engine counter that silently jumps; restore consistent history before generating again.

The cached Vulkan driver requests at most one queue per family. Audit game/present/acquire/async queue requirements before context creation and define lock ordering with Godot's submission mutex; do not assume a second queue exists. Serialize prepare/present/destruction and wait for outstanding presents before teardown. Existing upscaler flush logic is insufficient for FG worker lifetime. Maintain separate upscaler/FG failure state so FG can turn off while a healthy upscaler continues.

Native + FG must explicitly request valid depth/motion buffers and MSAA resolves even with temporal AA/upscaling disabled. Upscaling is before tonemapping; presentation sees the final composed viewport. Investigate a post-tonemap, display-sized HUD-less capture before foreground canvas drawing, respecting background-canvas ordering, and retain the UI resource through asynchronous composition. This crosses `render_forward_clustered.cpp`, `renderer_viewport.cpp`, `renderer_compositor_rd.cpp`, `rendering_device.cpp` and `drivers/vulkan/rendering_device_driver_vulkan.cpp`; a callback inside `FSR3Effect::upscale()` cannot own the entire feature.

## Reviewable delivery sequence

These IDs are substeps of VQ-07d/h, not a new owner namespace. Each row is a separate reviewable slice; split renderer/platform changes further when required. No production dependency changes are authorized by this document's status alone.

| ID | Work and dependencies | Required proof / current status |
| --- | --- | --- |
| VQ-07d-FSR-00 | Freeze current app/package and retained evidence identities; run baseline tools; record available host inventory. Reconcile concurrent package edits. | Exact source/engine/runtime/driver receipts; actual 1080p and known baseline errors. Pending |
| VQ-07d-FSR-01 | Intake SDK 2.4.0 exact tag/artifacts in an isolated cache. Verify hashes, license/notices, signatures, headers and component matrix; run AMD analytical upscale sample with FG off on available hardware. Keep Streamline and engine base fixed. | **Partial:** SDK intake verified; patched FG-off-default sample completed on RTX 3090 and reported analytical 3.1.6, but Vulkan validation reported errors. A pinned-DXC comparison was interrupted; validation-clean sample evidence remains open. Radeon ML proof belongs to 04. |
| VQ-07d-FSR-02 | Finish current FSR2/3 history invalidation and render input contracts before changing SDK behavior. Extend existing native smoke/capture tools with cuts/reset/seek and motion cases. | **Partial:** reset generation wiring and bounded fake-SDK/headless checks exist. A two-viewport rendered FSR2 fixture passed on RTX 3090; FSR3 reached its counters but failed validation. Post-cut motion, previous transforms, wider Vulkan/lifecycle checks and fallback remain open. |
| VQ-07d-FSR-03 | Migrate existing C++ upscale adapter to SDK 2.4; first force analytical 3.1.6 with FG off. Update loader/headers/query/diagnostics and matching package receipts. | **Partial:** isolated editor/template builds, signed-runtime staging, source/binary receipts, selector tests and a checked feature-fix candidate package pass. A 1080p editor smoke exercised five modes and Native restoration; storage-format warnings remain. Paired controls, failure recovery and validation-clean sequences remain open. |
| VQ-07d-FSR-04 | Add ML 4.1.2 capability and exact provider reporting; qualify Native AA/Quality first, then other supported modes. | **Partial:** the candidate's unsupported ML request fell back to Native on the tested RTX 3090 while preserving the request. Actual ML dispatch and moving output on eligible Radeon, broader fallback and capability reporting remain open. |
| VQ-07d-FSR-05 | Complete settings and legacy spatial coverage after capability contracts stabilize. Add FSR1 separately with correct AA; preserve FSR2/3 requests and native defaults. | Persistence/migration, Keep/Revert/timeout/restart/failure, EN/ES at 100/200%, all launch paths; spatial performance/readability evidence. Pending |
| VQ-07h-FSR-06 | With upscale correctness passing, reproduce SDK analytical FG sample; design Vulkan swapchain ownership and UI composition. Integrate analytical FG 3.1.6/swapchain 3.1.7 into an isolated engine. | Actual extra presents, real-frame counters, legal callback/resource lifecycle, correct HUD, resize/minimize/fullscreen/VSync/cap/shutdown, Native+FG and FSR+FG. Pending |
| VQ-07h-FSR-07 | Add ML FG 4.0.2/swapchain 4.0.0 on Windows 11/RX9000-class hardware. Preserve analytical selection elsewhere. | Effective FG/swapchain identities, mandatory configure/prepare/dispatch ordering, pacing/latency evidence and supported-driver comparison. Pending |
| VQ-07h-FSR-08 | Complete repeatable 1080p qualification, then 1440p/4K, finally 720p; run actual current-source exports and recovery tests. Coordinate DT/GDU before promoting any custom build. | Matrix and gates below; reproducible build receipts, full app checks, no unlabeled hardware gaps. Pending |
| VQ-07h-FSR-09 | Separately investigate DX12/ray-tracing inputs for RR 1.2.1, and RC preview applicability. Start with AMD samples on eligible hardware; require accepted renderer/input contracts before a game prototype. | Written feasibility/budget and explicit supported/deferred result. RR requires its own denoising quality/performance and package gates; RC remains preview research. Pending, not on raster/FG delivery critical path |

Dependency order for qualification: `00 → 01`; `00 → 02`; `01 + 02 → 03 → 04 → 05`; `03 + temporal correctness → 06 → 07`; every included feature → `08`. Candidate source was prepared while earlier evidence gates remain open. Row 09 is independent renderer research after the first usable raster delivery. If a sample or SDK integration fails, retain the known provider and fix or document that named blocker; do not replace measured gates with a version claim.

The arrows sequence implementation contracts, not access to every test device. Missing Radeon hardware keeps 04/07 ML qualification and promotion open; it does not block analytical integration, capability/failure tests, UI implementation or analytical FG work once their software prerequisites pass.

Resolve the analytical sample's validation findings and complete temporal evidence before promotion or FG integration. This plan does not estimate performance or an engineering calendar from marketing numbers.

## Qualification matrix and acceptance

| Target | Required evidence |
| --- | --- |
| Windows / Vulkan / RTX 3090 available reference | Native, stock FSR2, old/new analytical FSR; analytical FG if admitted by queried capabilities; DLSS/Reflex coexistence regression. No FSR4 ML qualification |
| Windows / Vulkan / RX6000 and RX7000 | ML upscale 4.1.2 versus analytical/native; per-family timing/memory, fallback and driver-version evidence |
| Windows 11 / Vulkan / RX9000 | ML upscale plus ML FG and swapchain 4.0.0; driver-assisted pacing eligibility and fallback; real/displayed rates and latency |
| Supported Ryzen APU | Query actual supported device/model; memory bandwidth, power/thermal and sustained 1080p evidence. Do not generalize to all integrated GPUs |
| Intel and other eligible NVIDIA/AMD tiers | Analytical support, missing-ML behavior, lower-tier quality/cost and minimum-spec evidence |
| Linux / macOS stock packages | Preserve supported Native/FSR2 paths and safe unavailable states; Windows Vulkan DLLs do not establish native OS support for SDK 2.4 |
| Windows / DX12 future candidate | New engine/API baseline and export qualification before FSR/RR claims; do not infer from Vulkan results |

Reuse [VQ numerical/human gates](advanced-graphics.md#numerical-and-human-acceptance), [native graphics tools](../../tools/graphics/native/README.md), [debug bridge](../../tools/debug/README.md) and [performance collectors](../../research/performance/README.md). The VQ-01d historical capture fixture is not already a complete Forward+ motion harness: extend its bounded coverage and assert actual renderer, dimensions and active provider.

- Primary output is **actual 1920×1080**. Internal 1280×720 reconstructed to 1080p is a valid 1080p experiment; a 1920×1061 desktop drawable is not. Follow with 1440p/4K, then 720p fallback.
- Matched aircraft/world/tick-input tape/camera/light and device; within-build mode comparisons use the same binary. Old/new SDK adapter comparisons need separately identified engine/runtime binaries with the SDK integration as the only intentional variable. Minimum 10 s warmup plus 60 s samples, three alternating A/B pairs. Separate cold activation, import/loading and instrumentation overhead. No competing rendered workload.
- Keep existing 60 Hz gates: process-loop p95 ≤18 ms, p99 ≤25 ms, simulation/wall 0.99–1.01. Record GPU/render CPU/full-frame p50/p95/p99, hitches, allocation/residency where measurable, and thermal state. Generated FPS cannot close the real-frame gate.
- Randomized moving clips and pilot review: close and 20/50/100 m plus the existing farther range; projected aircraft pixels and attitude/landing cues. Both landscapes, bright/dark liveries, day/dusk/night/storm, propellers/rotors, smoke, foliage/windsock and water. Static converged captures supplement these.
- Native AA versus native conventional AA is a quality/overhead comparison; reduced-resolution modes require a measurable benefit without a repeatable new readability failure. Do not promote a mode solely because GPU time decreases while whole-frame time worsens.
- FG measures real rendered, generated, submitted/displayed and dropped frames separately where instrumentation supports them. Vulkan PresentMon support must be verified; SDK2.4's special PresentMon reporting is DX12-only. Missing counts remain unavailable. Use same radio/monitor/VSync/cap and a documented input-to-photon method and uncertainty; review latency with the pilot before acceptance.
- Exercise cuts/reset/restore/pause, Home/Fly/Workshop, enabled vehicle routes, display/provider changes and failed setup. VQ retains 20-cycle growth checks; DT retains its separate 50-cycle and 30-minute soak. Record baseline leaks separately from new regressions.
- Run relevant reconstruction, preferences, advanced-settings, restart, frame-diagnostics and native build/package tests, then required integrated app checks. Use existing checked Godot runner and inspect engine/Vulkan logs. Run `fsr3-smoke.txt` and extend it for new providers/FG rather than introducing another controller.

Each completed row links its source/engine/SDK/DLL hashes, actual provider versions, OS/GPU/driver/monitor, settings and dimensions, test commands/receipts, measurements, motion-review result and remaining limits under existing VQ evidence. Raw videos/images stay in ignored outputs unless a small necessary artifact meets repository evidence rules.

## Release decisions and explicit limits

Promote a named feature/platform only after its software, temporal, performance, latency where relevant, and package gates pass. Missing Radeon hardware is a test dependency, not a reason to omit its implementation or claim it works. Keep unavailable ML/FG states clear and recoverable. Determine final package branding with DT: the current `windows-nvidia` name is not proof that AMD-capable settings belong in an AMD-qualified release.

Do not combine this SDK update with an engine rebase, Streamline upgrade, new default graphics profile or ray-tracing migration. A later engine-base update is a separate GDU change with matching export templates. Do not drop the old working SDK baseline until the new analytical path and fallback pass.

The SDK 2.4 candidate is not a qualified product package. No current-candidate GPU benchmark, FSR4 ML qualification or frame-generation integration has been established. RR/RC require additional renderer work beyond the present raster simulator.
