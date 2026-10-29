# Apple Silicon, Metal and MetalFX integration plan

Updated 2026-10-28 · **Owner:** desktop/performance maintainer (DT/PT), with VQ for rendering and SF/FL for numerical acceptance. **Prefix:** `DT-MAC-`. **Status:** source audit complete; Windows preparation implements native acquisition, bounded capture, isolated renderer trials and guarded MetalFX policy. Native Mac qualification and evidence-dependent engine/optimization work remain open. This is a production integration plan, not a production-readiness claim.

Deliver a shared native ARM64 path that works well across **M1, M2, M3, M4 and M5 Macs**, including their actually released chip/chassis variants. The common performance objective is **1920×1080 / 60 Hz**, with quality scaling to measured headroom. Preserve aircraft readability, controls and simulation behavior. This is an execution subtrack of [Desktop delivery](../DESKTOP-DELIVERY-PLAN.md), not a claim of measured speedup or already-qualified support.

**Hardware available:** the user confirmed a **MacBook Air M1 with 8 GB unified memory** on 2026-10-24. This is the intended low-memory/fanless baseline host. GPU core count (7 or 8), exact model identifier and macOS build remain to be recorded. Use it for DT-MAC-01–03; hardware availability is confirmed, but native performance qualification has not run.

The [2026-10-28 audit and primary-source refresh](../research/desktop-delivery-investigations/DT-MAC-00-R2/README.md) is the current research baseline, including Metal 4, 2026 MetalFX changes and newer hardware. The [initial source review](../research/apple-silicon-performance-2026-10-24.md) and [20 investigations, I01–I20](../research/desktop-delivery-investigations/DT-MAC-00-R1/README.md) retain the earlier findings. Existing [DT-00-R2 investigations](../research/desktop-delivery-investigations/DT-00-R2/README.md) retain packaging, input, audio and ARM64 numerical evidence. This plan owns `DT-MAC` status; parent DT gates retain their authority.

## 1. Scope and ownership

Owned documentation: this plan and its dated research. Future measurement scripts and evidence belong under `research/performance/` and `docs/research/desktop-delivery-investigations/`, using the step ID in each evidence directory. Create those outputs only when work executes.

Shared changes require the existing owner: `main.gd` and frame collection (PT/VQ), `app/render/` and graphics tooling (VQ/FW/LU/SM), display/preferences (UI), exports and engine pins (DT/GDU), simulation and replay (SF/FL). Keep implementation to one measured mechanism per change. Recheck Git status before integration; these paths already have parallel work.

- Preserve float64 state, 240 Hz ticks, RK4 order, the shared `VehicleModel` boundary, collision identity and input sampling. Never lower physics frequency or precision to meet a graphics target.
- Use the currently adopted **official Godot 4.8-beta1**, exact editor/template hashes and source commit `4d10419ca`, for the first comparison. [GDU-03](godot-4.8-upgrade.md) records the owner's beta adoption. Godot's current stable release remains 4.7.2; beta adoption does not close Mac release gates. Any newer engine or upstream patch is a separate, pinned candidate; do not silently downgrade or advance the shared project. [Official beta release](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/), [release policy](https://docs.godotengine.org/en/stable/about/release_policy.html).
- Use official Godot binaries, Xcode/Instruments, existing project tooling and existing licensed assets. Download available free tools rather than building a profiler, renderer or asset replacement.
- Follow [resolution priority](../../AGENTS.md#display-resolution-priorities): 1080p first, above 1080p second, 720p last. A reconstructed 1080p output must disclose its lower internal resolution.
- Native ARM64, Intel under Rosetta, native Intel and hosted CI are separate results. This track qualifies named Apple Silicon configurations only.
- Keep a common distribution and baseline render path; chip-specific native instructions, hardware ray tracing, Metal 4-only features and M5-only GPU facilities cannot become mandatory for M1/M2. Optional paths require engine, OS and actual device support, not a chip-name match.

## 2. Starting point and decisions to test

The table below retains the pre-implementation audit. The subsequent
[DT-MAC-02 preparation evidence](../research/desktop-delivery-investigations/DT-MAC-02/README.md)
records the implemented changes and Windows checks. Current instructions live in
the [native Mac tooling guide](../../tools/godot/README.md#native-apple-silicon-setup-and-preflight-dt-mac-02a),
[isolated renderer guide](../../tools/graphics/README.md#isolated-mac-renderer-trials-dt-mac)
and [performance guide](../../research/performance/README.md). No native Mac
measurement is inferred from this preparation.

| Current source audit, 2026-10-28 | Consequence |
| --- | --- |
| [Project settings](../../app/project.godot) select Compatibility, a 1280×720 default viewport and 4× MSAA | Explicitly set and verify 1080p backing/render pixels; the default is not the target |
| [Engine downloader](../../app/get-godot.sh) supports Linux/Windows x86_64, rejects Darwin; [export preset](../../app/export_presets.cfg) is macOS universal | Add pinned native Mac acquisition and verify exported execution; an export preset is not a working Mac developer/CI path |
| [High trial](../../tools/graphics/README.md) changes renderer, SSAO, shadow atlas/cascades and reflections | Standard versus High is a product-profile comparison, not an isolated Metal benchmark |
| [Frame diagnosis](../../research/performance/README.md#cpu-gpu-and-memory-diagnosis) has a 300 s bound; Mac Compatibility viewport timing is disabled | Fix continuous soak collection first; missing GPU timing is not zero GPU cost |
| [Frame diagnostics](../../app/render/frame_diagnostics.gd) already report effective method/driver/adapter/API when enabled; top-level pacing identity and platform coverage remain incomplete | Preserve those fields; add requested-versus-effective selection, OS/API generation evidence, numeric VSync mode and present timing without treating callback intervals as displayed frames |
| Current [reconstruction adapter](../../app/render/reconstruction.gd) has Native/FSR2 and experimental FSR3/DLSS modes, no MetalFX mode | Engine support does not mean OpenRC exposes or qualifies MetalFX |
| [Scene detail Auto](../../app/render/scene_detail.gd) classifies `apple m` as integrated/Medium and unknown GPUs as High | Replace or retain this heuristic explicitly after measurement; the proposed capability policy is not existing behavior |
| [High guide](../../tools/graphics/README.md) retains version-specific reflection-resource investigations and a Windows custom-engine experiment | Revalidate the exact 4.8-beta1 Mac build; world-switch memory growth blocks adoption. Historical 4.7.2 defects are not automatically current Mac defects |

**Working hypothesis:** Mobile/Metal deserves the first renderer experiment for the M1 floor; Forward+/Metal remains a serious comparison for feature coverage and higher tiers. Compatibility remains the control and recovery path. The winner is determined by whole-session timing, power, memory and visual acceptance, not API reputation.

Godot supports both Mobile and Forward+ on native Metal; Vulkan on macOS uses MoltenVK. **The pinned 4.8-beta1 source constructs an `MTL3::RenderingDeviceDriverMetal` and its MetalFX callbacks use MTL3 command buffers.** This contradicts the earlier plan's inference from 4.7 documentation that macOS 26 automatically gives this build a Metal 4 command backend. OS/API labels are insufficient: record the actual engine implementation. MetalFX integration can proceed through this existing Metal path; full Metal 4 command submission is separate upstream work. [Pinned driver factory](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/drivers/metal/rendering_context_driver_metal.cpp), [pinned MetalFX callbacks](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/servers/rendering/renderer_rd/effects/metal_fx.cpp). The published Apple Silicon engine floor is macOS 13; OpenRC's product floor still needs final-package and hardware tests. [System requirements](https://docs.godotengine.org/en/4.7/about/system_requirements.html).

## 3. Hardware and workload matrix

| Priority | Host/profile | Purpose |
| --- | --- | --- |
| Available floor host | User's MacBook Air M1, 8 GB; GPU core count and macOS pending inventory | First native ARM64 baseline, memory-pressure tests and fanless thermal run; availability is confirmed, measurements are not |
| GPU variant coverage | Identify whether the available Air has 7 or 8 GPU cores | If it has 8 cores, retain the 7-core GPU coverage gap; the 8 GB/fanless host requirement is already met |
| Comparison | Actively cooled M1 Mac mini or 13-inch MacBook Pro; record RAM/GPU | Distinguish chassis/cooling effects; different RAM remains a confounder |
| Cross-generation coverage | At least one named M2, M3, M4 and M5 host, with available Pro/Max/Ultra variants recorded separately | Same release/reference cases on each generation; request shared tester reports when local hardware is unavailable, without assuming access |
| OS coverage | Oldest proposed OS actually supported by each Mac model and selected backend, plus a named newer OS build | Do not try macOS 13 on hardware that cannot install it. Metal 3/4 and OS changes are separate factors; Metal 4 is not the common-path requirement |
| Display | 1080p at 60 Hz first; then 1440p, Retina panel resolution and 4K; 720p last | Record window points, drawable pixels, internal 3D size, UI scale, refresh, VSync and cap separately |
| Power | AC normal mode baseline; battery normal and available Low Power Mode separate | Record battery state, thermal state, display brightness, ambient conditions and external displays |

### Generation coverage ledger

These are coverage requirements, not performance rankings. M1 Max versus base M5, for example, is not a controlled generational comparison. Metal families describe API features; memory, chassis and actual workload still determine quality. The [hardware investigations](../research/desktop-delivery-investigations/DT-MAC-00-R1/01-hardware-memory.md) retain primary evidence.

| Generation | Apple GPU family | Coverage emphasis | Current evidence |
| --- | --- | --- | --- |
| M1 | Apple7 | Common baseline, smallest memory configuration, older GPU feature path | Air with 8 GB available; GPU variant, macOS and results pending |
| M2 | Apple8 | Common-path regression and memory/chassis scaling | Hardware test pending |
| M3 | Apple9 | Newer GPU architecture/format paths without making them baseline requirements | Hardware test pending |
| M4 | Apple9 | Same family does not imply identical throughput; verify presets and display behavior | Hardware test pending |
| M5 | Apple10 | Optional neural/GPU capabilities, import formats and quality headroom | Hardware test pending |
| M6, separate latest-hardware extension | Not established by the retained May 2026 feature table; query the device | Follow the [dated availability/variant evidence](../research/desktop-delivery-investigations/DT-MAC-00-R2/apple-technologies.md); separate released from announced models and qualify a named host | Hardware test pending; no result inferred from M5 |

For each row retain model identifier, base/Pro/Max/Ultra suffix where applicable, CPU/GPU cores, memory, cooling class, OS/build, display, package hash, effective backend/preset and pass/fail/untested. Track three claims separately: **launches**, **passes software/visual checks**, **meets sustained performance/readability gates**. Initial acceptance is the available M1; completion of the M1–M5 release objective requires evidence for the other rows, not extrapolation.

Apple lists the M1 Air's 4 performance + 4 efficiency CPU cores, 7/8 GPU variants, 8/16 GB unified memory and 2560×1600 display. The panel has about **1.98×** the pixels of 1080p; 4K has **4×**. These are pixel-count ratios, not predicted frame-time ratios. [Apple specifications](https://support.apple.com/en-us/111883).

Freeze the aircraft, landscape, camera, weather/time, scenery tier, smoke and companion count for each case:

1. Cold process launch → Home → Fly; repeat warm and after a controlled fresh import/cache condition, labeling each separately.
2. Active normal circuit, low approach over grass/trees, distant aircraft against sky and terrain, and a detailed aircraft near the pilot.
3. Lake/reflection view, smoke-heavy maneuver and dusk/night lights. Include Club field and Green paradise.
4. Home ↔ flight ↔ Workshop transitions, aircraft/landscape changes and repeated world destruction; exercise at least 10 cycles after cache warmup.
5. Continuous 30-minute active flight, followed by separate minimize, focus-loss, display-change and sleep/resume cases. Paused time never counts as sustained flight.
6. Qualify helicopter/ground activities separately if included in the Mac release; do not generalize fixed-wing measurements. Companion-disabled and a declared companion workload are separate cases.

Reuse [flight logs](../FLIGHT-LOGGING.md) for physics comparisons and existing camera/capture cases for rendering. `--scripted` is a controlled rendering workload, **not** an exact replay or proof of active physics. Real pilot circuits remain a distinct acceptance task.

## 4. Tools and instrumentation

The [tool index](../tools/README.md) and linked READMEs own commands. Verify Mac compatibility of each runner before use; adapt the existing entry point instead of making a second harness.

| Tool | Use and limitation |
| --- | --- |
| [Debug bridge](../../tools/debug/README.md) | Launch/inspect the app, drive repeatable transitions, inspect frames/hitches, profile scripts and run smoke. Use its controls instead of mouse automation |
| [Frame diagnosis and reducers](../../research/performance/README.md#cpu-gpu-and-memory-diagnosis) | Existing CPU/GPU/counter schema and raw frame intervals; extend metadata/soak support here. Root-viewport timing excludes other viewports and can lag |
| [Process resource tools](../../tools/godot/README.md#process-ram-io-and-storage-pt1h-r4) | Process RAM/CPU/I/O and system memory context; verify supported Mac fields. Engine allocation estimates are not RSS or total unified-memory pressure |
| Godot Profiler / Visual Profiler | Attribute GDScript, render passes and pipeline compilation during diagnostic runs; final timing uses release exports with expensive observers off |
| Instruments: Time Profiler, Allocations, Game Performance / Metal System Trace | CPU stacks, allocation churn, CPU/GPU overlap, stalls and presentation. Attach to the actual native app with matching symbols where available. [Apple workflow](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app) |
| Xcode Metal debugger, GPU capture and counters | Inspect expensive passes, attachments, bandwidth and shader limiters. API/Shader Validation belongs in correctness runs, not timed acceptance. [Apple tools](https://developer.apple.com/documentation/xcode/metal-developer-workflows) |
| Metal Performance HUD | Quick Metal workload/interval/memory observations; `MTL_HUD_ENABLED=1` and optional `MTL_HUD_LOG_ENABLED=1` are diagnostic settings. Record overhead and remove them for final control runs. Not an OpenGL profiler. [Apple HUD](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance) |
| Activity Monitor and available macOS power diagnostics | Memory pressure, swap, Energy Impact, App Nap and process architecture; use `powermetrics` only where its host help/permissions expose the needed counters. Relative Energy Impact is not watts or battery-life proof |
| Newer Instruments / `metalperftrace` workflows | Optional local JSON/trace analysis when installed OS/Xcode support it; preserve a working M1/older-OS tool path. Do not raise the product OS floor or add telemetry just to use newer diagnostics. [Tool investigation I18](../research/desktop-delivery-investigations/DT-MAC-00-R1/03-runtime-validation.md#i18--free-profiling-tools-and-their-coverage-boundaries) |
| Existing capture/readability and lifecycle checks | Compare materials, aircraft orientation, temporal artifacts and resource recovery. Linux llvmpipe and headless checks cannot qualify M1 graphics |

Use bounded local traces, existing CSV reducers and free plotting tools. Keep raw traces/captures in ignored `tmp/`; retain compact reports, identities and regeneration instructions in evidence. No unnecessary images or new telemetry service.

## 5. Experiment protocol and acceptance

Before testing candidates, DT-MAC-01/02 freeze the workload manifest, numerical policy, timing definitions and a measured memory ceiling for the available 8 GB M1 Air plus OS headroom. Measure real memory pressure and swap on this host. An unavailable channel is explicitly unavailable; never substitute a zero.

- Record Git commit and dirty diff identity, package/editor/template hashes, import/config identities, architecture, macOS/Xcode versions, requested/effective renderer and driver, adapter/API, display/power state and cache conditions.
- Use one rendered application, no competing benchmark. Run at least five independent paired trials per short case, alternating A/B order with comparable initial thermal state. Use 30 s warmup and 120 s measured windows as the initial short-run protocol. Report per-run p50/p95/p99, worst frame, sample counts, exclusions and paired differences; do not treat correlated frames as independent trials.
- Separate uncapped throughput diagnosis from **60 Hz paced release acceptance**. Record frame intervals and presented-frame information separately. CPU and GPU overlap; do not add their times to estimate total frame time. A callback clock is not input-to-photon latency.
- Measure observer-on/off controls. Accept a speed claim only beyond observed run variation and instrumentation uncertainty. Proposed practical screening threshold: at least 5% improvement in the predeclared bottleneck metric, with no unexplained >5% regression in another required case; a proven gate repair can justify a smaller gain.
- Run at least three 30-minute release soaks per baseline/finalist on the floor machine, beginning from comparable conditions. This matches the existing summary tool's three-run campaign minimum; use its explicit 30/1800-second warmup/sample gates. Compare early and final five-minute windows, hitch bursts, memory/swap and thermal state. Do not concatenate six process restarts and call them one soak.
- Extend the existing collector with bounded streaming/chunks, continuity and completion metadata before that soak. At 60 Hz, 30 minutes already yields 108,000 frames; higher refresh exceeds the current 120,000-frame ceiling. Test truncation, interrupted writes and cleanup; preserve normal launch/exit behavior outside soak mode.
- Record effective Game Mode independently from fullscreen, power mode and focus; compare it on/off only as a separate experiment. Keep a supported baseline without relying on Game Mode. ProMotion/120 Hz and buffer-count changes require their own pacing/latency evidence after 60 Hz qualification. [Runtime/display investigations I16–I17](../research/desktop-delivery-investigations/DT-MAC-00-R1/03-runtime-validation.md).

| Gate | Required evidence / proposed target |
| --- | --- |
| 1080p flight pacing | Existing DT proposal: process-loop interval p95 ≤18 ms, p99 ≤25 ms at declared 60 Hz; report >33.3 ms and >50 ms events, maxima and burst lengths. Presentation trace and pilot review remain separate |
| Physics | Existing ≤500 µs tick budget on the target host; report sampling unit and distribution, not just best batch mean. Unpaused simulation/wall ratio 0.99–1.01 |
| Numerics | Same-host before/after exact replay/fingerprints for presentation-only changes; cross-platform agreement uses the existing [H9 policy](../research/simulation-state/H9/README.md). No golden re-record or tolerance widening |
| Loading | Existing DT proposals: Home ≤5 s cold / ≤3 s warm, Fly ≤2 s; state cache condition and end event, and retain first-use hitch evidence |
| Memory | Frozen floor-host ceiling; no sustained pressure/swap growth attributable to the candidate, no monotonic retained-resource growth across warm lifecycle cycles, and no unresolved resource leak. RSS and GPU allocations can overlap; do not sum them blindly |
| Visual/control | Aircraft orientation, ground obstacles, landing cues, UI text and smoke remain legible in motion/day/night. Camera changes, exposure and FOV are fixed unless separately accepted |
| Thermal/energy | Meet pacing and real-time gates through the final soak window. Publish AC/battery results separately; fixed-workload energy gain must use comparable measurements |
| Shipping | Same final exported bytes launch natively, recover safely and pass relevant tests/smoke. DT retains signing/notarization and downloaded-artifact acceptance; profiling entitlements/builds cannot substitute for final release checks |
| M1–M5 coverage | Complete the five generation rows with exact tested configurations and remaining SKU/OS gaps. No newly required optional feature may remove the M1/M2 baseline; repeat common-path tests when a newer-device optimization lands |

These are acceptance proposals/existing owner budgets, not measured results. Freeze any revisions before comparing candidates. Failed hardware or pilot gates stay open.

## 6. Renderer comparison

Run disposable project copies with separate import caches and the required sibling `assets/`. First establish shader/scene correctness, then time the candidates.

| Candidate | Role |
| --- | --- |
| A: Compatibility / OpenGL | Unmodified reference and recovery path |
| B: Mobile / native Metal | First M1 efficiency candidate, with the accepted common visual feature set |
| C: Forward+ / native Metal | Same common feature set before enabling additional High effects |
| D: same Mobile or Forward+ / Vulkan via MoltenVK | Conditional control to isolate native driver behavior or a Metal-specific regression; not a second OS comparison |
| E: High / native Metal | Separate product-quality trial after C; account for its effects and larger render targets |

Godot exposes method and driver separately. Candidate arguments include `--rendering-method mobile --rendering-driver metal` or `--rendering-method forward_plus --rendering-driver metal`; engine arguments precede the app's `--`. These are experiment definitions, not a claim that today's wrapper accepts them. The current [graphics launcher](../../tools/graphics/launch.py) only exposes Standard/High and rejects driver/method overrides: add a scoped research path through its owner, retaining truthful profile metadata and its normal safeguards.

Before benchmarking, compare sky/exposure, lake depth/refraction and reversed-Z handling, alpha foliage/MSAA, shadows, smoke/particles, global shader parameters, instancing, night lighting and all secondary viewports. Unsupported effects must be declared and reviewed, not silently disabled to win the benchmark. Reuse [VQ-07](advanced-graphics.md) parity work. Renderer selection happens before initialization; any shipped selection must reuse the existing restart/recovery UI, not add a second preference store.

If B/C cannot preserve the required look or outperform A's relevant gates, retain A and optimize the measured bottleneck. Native Metal support alone does not close DT-11d.

## 7. Optimization backlog, ordered by evidence

Choose only the row supported by the profiler, then remeasure the whole session. Apple GPU guidance motivates bandwidth/pass experiments; it does not justify rewriting Godot's render graph in this track. [Apple GPU optimization](https://developer.apple.com/videos/play/wwdc2021/10148/).

| Order / trigger | Bounded change to try | Proof and constraints |
| --- | --- | --- |
| 1. Accidental pixel load / poor pacing | Correct Retina backing size, render scale, display refresh and cap; compare windowed/fullscreen presentation | Same output/readability; 1080p native baseline retained. Do not mistake logical window points for GPU pixels |
| 2. GPU fill/bandwidth | Compare native 4×/2× MSAA, then one shadow/reflection resolution or update policy; reduce needless full-screen/secondary passes | Drawn GPU cost and memory plus moving-edge/shadow checks. Preserve existing reflection/radiance contracts |
| 3. Foliage/smoke overdraw | Profile the existing opaque near grass, alpha-scissored tree cards and blended GPU smoke; test one justified distance/coverage/geometry change | Preserve canopy density, wind, silhouette and smoke cues; benchmark actual overlap. Do not replace opaque grass with blended cards or convert smoke to cutouts |
| 4. Submission/geometry | Existing LOD/visibility ranges and spatially bounded MultiMesh groups; reduce duplicate material/surface state | Measure CPU submission and GPU vertex cost together. Giant MultiMeshes can defeat fine culling; occlusion must earn its CPU cost in open terrain |
| 5. Unified-memory pressure | Audit texture residency/mips/compression, retained worlds, duplicate resources, reflection buffers and temporary allocations | Inspect actual imported GPU format on M1 and newer families; never distribute a newer-family-only format without the baseline alternative. The ASTC import flag alone proves no memory saving. Retain color/normal/mask semantics and generated provenance |
| 6. First-use hitch | Reuse resources and reduce material variants; prepare required pipelines during bounded loading | Separate fresh-import, process-cold and warm-cache cases. Godot's pipeline precompilation path differs between Compatibility and Mobile/Forward+ |
| 7. CPU scripts / loading | Cache immutable validated data, eliminate demonstrated allocations/repeated work, batch presentation updates; use existing threaded loading only when attributed | Full callback/loading and invalid-input/lifecycle tests; do not block early on a pending resource, mutate the active tree from a worker or hide data changes |
| 8. CPU simulation / audio | Profile scenery queries, evaluators and audio on Mac; optimize the existing algorithm/allocation path first | Preserve evaluation order and exact same-host outcomes. [SF native-backend policy](../STACK.md#boundaries-and-data-flow) still governs any C++ proposal; no fast-math, GPU physics or blanket thread migration |
| 9. Sustained heat / idle power | After meeting flight gates, test sensible menu/occluded rendering limits and remove redundant background presentation work | Preserve focus-pause, audio and resume contracts; avoid global App Nap disabling or P/E-core affinity hacks |

Reuse Godot's existing LOD, MultiMesh, material and pipeline facilities. [3D performance](https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html), [pipeline compilation](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html).

### Conditional MetalFX trial

The pinned **4.8-beta1** API declares MetalFX Spatial and Temporal, restricted to Metal. Query the actual RenderingDevice feature and temporal scale limits; enum presence alone proves neither build support nor device availability. [Pinned capability/scale source](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/drivers/metal/rendering_device_driver_metal.cpp), [current compatibility audit](../research/desktop-delivery-investigations/DT-MAC-00-R2/godot-compatibility.md).

The current source audit confirms this method matrix; [I10](../research/desktop-delivery-investigations/DT-MAC-00-R1/02-rendering.md#i10--metalfx-support-in-godot-472-and-m1m5) retains the historical 4.7.2 investigation:

| Effective method / driver | Spatial | Temporal |
| --- | --- | --- |
| Compatibility / OpenGL | Unavailable | Unavailable |
| Mobile / Metal | Shared RD spatial path; require device/OS/build support | No Forward+ temporal path; keep unavailable |
| Forward+ / Metal | Require actual support | Require actual support and enabled engine build path; respect device scale limits |
| Mobile or Forward+ / Vulkan via MoltenVK | Not native MetalFX through this driver | Not native MetalFX through this driver |

Read `RenderingServer.get_rendering_device()` only on a supported RD path, then `has_feature(SUPPORTS_METALFX_SPATIAL / SUPPORTS_METALFX_TEMPORAL)`. Probe constants/methods dynamically for compatibility with other engine builds. Read `LIMIT_METALFX_TEMPORAL_SCALER_MIN_SCALE` and `MAX_SCALE` using `limit_get()` and divide by **1,000,000**; these are input/output scales, not Apple's inverse upscale ratios. Reject absent, nonfinite, zero or inverted ranges. Temporal is also engine-build-gated. The existing adapter gates every provider through High; Mobile spatial must gain its own eligibility without pretending to enable High effects.

The engine can substitute FSR1, FSR2, spatial scaling or bilinear when a MetalFX request is unsupported or out of range. OpenRC's policy remains explicit **Native at scale 1.0** on an unavailable request: preflight support and range, restore AA and record the reason. **Viewport mode/scale/MSAA/TAA getters describe requested inputs, not necessarily the effective render-buffer configuration.** A getter can still report Temporal while the engine privately selects Spatial or FSR2. Qualification therefore requires an engine-observed effective-pass diagnostic plus native capture; absent that seam, report effective execution as unknown and keep the unqualified candidate disabled. Do not promise automatic runtime-substitution detection from property readback or once-only warnings. [Pinned viewport fallback logic](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/servers/rendering/renderer_viewport.cpp), [property storage/getters](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/scene/main/viewport.cpp).

After native 1080p baseline and renderer parity, extend the existing reconstruction adapter only if GPU pixel work remains limiting. Verify the pinned engine's actual method/device support, effective mode and fallback. Compare Native against spatial reconstruction first, then temporal on supported Forward+; start at 0.85 scale only if allowed by the device, considering lower scales only if attitude/readability passes. Keep output/UI at 1080p and report internal dimensions. Repeat at higher output resolutions only after the primary gate.

Temporal review must include distant aircraft, propeller/hinges, wind-driven foliage, smoke, thin markings, camera cuts, reset/teleport, pause/resume and disocclusion. Account for history buffers, motion vectors, AA ownership and reconstruction overhead. Unsupported requests must resolve to Native with an honest effective-mode report. Keep FSR2 as a supported-method comparison; the Windows/Vulkan FSR3/DLSS engine experiment is not a Mac solution. Frame interpolation and newer neural inputs have separate conditional work packages below; neither blocks the supported baseline.

## 8. Execution steps and stop rules

| ID | Work / owner and dependency | Proof/status |
| --- | --- | --- |
| DT-MAC-00 | Research and repository audit; DT/VQ | Done: [2026-10-24 source review](../research/apple-silicon-performance-2026-10-24.md); no native measurements |
| DT-MAC-00-R1 | Twenty internet investigations and M1–M5 plan revision | Done: [I01–I20](../research/desktop-delivery-investigations/DT-MAC-00-R1/README.md); user confirms M1 availability, no hardware tests performed |
| DT-MAC-00-R2 | Refresh Apple 2026 technologies, audit exact adopted Godot source and map implementation gaps using three Terra 6.1 Max specialists | Done: [research and source audit](../research/desktop-delivery-investigations/DT-MAC-00-R2/README.md); no runtime changes or native qualification |
| DT-MAC-01 | Inventory the available M1 Air/8 GB; freeze OS/display/power matrix, package identity and budgets; DT-01a | Model family and RAM confirmed by user; GPU variant, OS/build and native ARM64 launch evidence pending |
| DT-MAC-02 | Native tooling and measurement gaps: driver/pacing metadata, bounded continuous soak, observer controls; PT with DT-02a/10a/10b; after 01 | Software prepared: ARM64 getter, template portability, preflight, v3 bounded stream and two reducers. Windows/WSL fixtures passed; native smoke, presentation/resource coverage and paired observer-overhead gate open |
| DT-MAC-03 | Unmodified 1080p baseline, numerical policy and bottleneck attribution; SF/FL + DT; after 02 | Open; paired short runs, baseline soak, exact local replay and H9 results |
| DT-MAC-04 | One highest-impact CPU/loading/memory fix if baseline calls for it; owner from §7 with DT-11a | Open/conditional; paired proof and full-workload regression checks |
| DT-MAC-05 | Isolated Mobile/Metal and Forward+/Metal parity/comparison, MoltenVK control only as needed; VQ + DT-11d; after 03 and a frozen 04 outcome | Preparation/launcher and identity fixtures implemented; native parity, effective-backend receipts, visual report and distributions open. Production default unchanged |
| DT-MAC-06 | One GPU/settings improvement at a time; VQ/LU/FW/SM + DT-11c; after attribution | Open/conditional; native 1080p performance and readability acceptance |
| DT-MAC-06a | Common capability policy and measured preset selection across M1–M5; VQ/UI; after 05/06 | Open; unsupported/unknown capabilities, saved-preference migration, effective-mode reporting and recovery tests (§9) |
| DT-MAC-07 | MetalFX capability/integration trial through reconstruction owner; native evaluation after 05/06 justify it | Opt-in Spatial/Temporal policy, settings and fallback fixtures implemented. Stock reset acknowledgement absent: Temporal falls back on camera discontinuity. Actual scaler execution, motion, resize/lifecycle and performance remain unqualified |
| DT-MAC-08 | Finalist 30-minute AC/battery soaks, lifecycle/input/audio/display recovery and native package checks; DT-10b/12, UI/AUD | Open; final artifact reports; then higher-resolution and lastly 720p compatibility results |
| DT-MAC-08a | Run the same release matrix on M2, M3, M4 and M5 and feed regressions back to the M1 control | Open; named physical tester artifacts and five-generation ledger, with explicit variant/OS gaps |
| DT-MAC-09 | Integrate accepted settings/backend policy, document tested M1–M5 configurations and recovery, retain baseline rollback; DT/VQ + DT-13 | Open; 06a/08/08a outcomes, focused/full relevant suites, final Mac package and owner/pilot acceptance |
| DT-MAC-10 | Upstream-first Metal 4 command backend, exact candidate engine and MTL3 recovery; GDU/VQ, after §11/13 prerequisites | Open/conditional; inspected current pin uses MTL3; no Metal 4 execution claim |
| DT-MAC-11 | Newer MetalFX temporal inputs/neural implementation exposure; VQ/GDU, after 07b | Open/conditional; exact SDK/OS/device integration and benefit unverified |
| DT-MAC-12 | Separate optional MetalFX frame interpolation/presentation path; VQ/DT/UI | Open/conditional; real-frame, latency, UI and recovery gates must pass independently |
| DT-MAC-13 | Conditional advanced GPU/memory/denoising/ML work with a concrete supported consumer | Open/conditional; record trigger absent where current raster application has no use case |

First native delivery is **01–03: a reproducible M1 baseline and ranked bottleneck report**. The user explicitly requested preparation on the current Windows PC for later Mac execution, so reusable tooling and disabled-by-default reconstruction trials were implemented ahead of those measurements. This does not waive the measurement prerequisites for adopting a renderer or optimization. Select the smallest justified branch after attribution.

Stop a candidate for numerical drift, missing visual features, unresolved leaks/crashes, slower sustained flight or benefit within measurement noise. Record **retain baseline** or **trigger absent** for conditional branches. M1 access is confirmed, so its next action is inventory and execution; M2–M5 coverage stays pending until actual test reports exist.

Each accepted change retains a before/after receipt: exact identities, single hypothesis/change, commands from the owning tool guide, complete raw-data location/hash, per-run statistics, visual/numerical checks, failures/exclusions, conclusion and rollback. Keep old renderer/settings recoverable until the final package passes. Consolidate completed rationale into the desktop/graphics guides when this plan is retired.

## 9. Shared capabilities and quality policy

One common ARM64 application should scale with the Mac rather than maintaining five chip-specific forks. Reuse existing graphics, scene-detail and reconstruction preferences. The policy names below are engineering labels, not a new menu or preferences store. [Capability/preset investigation I20](../research/desktop-delivery-investigations/DT-MAC-00-R1/03-runtime-validation.md#i20--capability-based-presets-and-a-defensible-m1m5-claim).

| Policy | Eligibility and behavior | Qualification |
| --- | --- | --- |
| Baseline 60 | Required path for every requested generation; conservative accepted effects, unchanged physics/collisions, Native reconstruction initially | Start on M1 at native 1080p; measured quality reductions must retain attitude, obstacle and landing cues |
| Higher quality | Supported effects plus measured CPU/GPU/memory headroom; any generation may qualify | Full-frame and 30-minute acceptance; no automatic `M5 = High` or `M1 = Low` assignment |
| Reconstructed output | Actual driver/method/scaler support and lower pixel work yielding net benefit | Internal/output resolution reported; moving aircraft/propeller/smoke checks; unsupported request resolves to Native |
| Recovery | Known-good Standard configuration and safe restart through existing UI | Failed backend launch, unknown saved mode and capability changes recover without restart loops or lost calibration |

At launch, record platform/architecture, effective method/driver, relevant engine capability results and usable memory context. GPU names are diagnostic labels, not feature gates. Do not add direct Metal queries in GDScript where Godot already owns the decision. If a necessary capability is unavailable through the engine, retain the baseline and resolve that single gap with the renderer owner.

This is the target policy: today's `scene_detail.gd` Auto still uses adapter-name heuristics, including `apple m → medium` and unknown → High. DT-MAC-06a must migrate that behavior explicitly with tests for existing saved Auto/manual settings and unknown devices. Keep manual overrides, avoid a universal preset based solely on unified memory, and do not confuse a provisional conservative default with a measured recommendation.

Keep quality fixed during the initial comparisons. A later automatic-quality experiment is conditional on sustained-load evidence: adjust only existing presentation controls, use hysteresis/cooldowns, preserve user override and record every transition. Prefer less costly effects before reducing aircraft visibility; exclude physics, collision populations and control sampling. Never auto-upgrade the renderer mid-flight. Reset adaptation after a hardware/backend change instead of trusting stale calibration. Do not collect cloud telemetry or run a surprise stress test at every launch.

## 10. First test session on the available M1

The immediate native deliverable is a local evidence bundle. The Windows-prepared commands are in the owning tool READMEs linked in §2; run them on the actual Mac before claiming support.

1. **Inventory (01):** record the confirmed M1 Air/8 GB, then obtain GPU core count, exact model identifier, macOS build, display/power modes and free storage. The low-memory/fanless host is available; 7-core GPU coverage depends on identification. Avoid collecting serial numbers or unrelated personal logs.
2. **Freeze (01/02):** choose one clean revision and matching pinned editor/templates/export; retain hashes and import identity. Verify ARM64 execution and package dependencies. Use new ignored output folders; do not modify the user's normal graphics/controller preferences.
3. **Compatibility control (03):** native 1080p/60 Hz, fixed landscape/aircraft/weather; run software/replay checks, short timing pairs and a Home/Fly/Workshop lifecycle pass. Verify active physics and readable controls before a long run.
4. **Attribution (03):** one short CPU profile and one supported GPU/timeline capture; prove the observer cost and identify the dominant missed budget. Preserve the uninstrumented reference.
5. **Sustained baseline (02/03):** three uninterrupted 30-minute runs with explicit AC/power/thermal conditions and the summary's 30/1800-second gates; battery cases only on a laptop. Report missing channels and incomplete runs.
6. **One candidate (04–07):** choose the top attributed fix or common-feature Metal trial, replay the same workload, and accept/reject with the frozen gates. Re-run the baseline after integration before sending the same package/cases to M2–M5 testers.

Completion receipt: host manifest, source/package identities, effective settings, logs, complete timing/resource summaries, replay result, lifecycle result, profiler attribution, actual test exclusions and the next single candidate. Work to date ran on Windows, including portable WSL fixtures. No Mac benchmark has run yet.

## 11. Implementation boundaries and reviewable deliveries

Priority means execution order, not predicted speedup: **P0** makes results trustworthy and enables native measurement/qualification; **P1** integrates and qualifies engine-supported rendering; **P2** adds optional engine capabilities only after their prerequisite exists. Each row is a separate reviewable change or evidence delivery. Detailed source locations and current limitations are in the [repository audit](../research/desktop-delivery-investigations/DT-MAC-00-R2/repository-audit.md).

| ID / priority / owner | Concrete work and file boundary | Dependency / acceptance / rollback |
| --- | --- | --- |
| DT-MAC-02a / P0 / DT | Extend `app/get-godot.sh` for Darwin with the official **`Godot_v4.8-beta1_macos.arm64.zip` editor**, exact independently verified checksum, executable/version verification and portable checksum/archive handling. The editor is architecture-specific; the universal export template is separate. Inspect `get-templates.sh`, export scripts and CI host assumptions; reuse existing tools | After 01 inventory. Native ARM64 editor/import/test invocation, cache hit, corrupt download, interrupted download and unsupported-host checks; no Rosetta substitution. Roll back downloader change independently |
| DT-MAC-02b / P0 / PT | Extend `app/render/frame_samples.gd` (duration/cap/continuity owner), `app/main.gd`, `app/render/frame_diagnostics.gd`, existing reducers and `tools/godot/` resource collection for bounded continuous recording and §12 metadata. Extend `app/tests/test_frame_samples.gd`, `tools/godot/test_frame_capture.py` and reducer tests; preserve existing effective-driver fields | Before any soak. Test cap reached, partial write, cancellation, viewport destruction, missing counters and monotonic timestamps; demonstrate observer overhead. No sample cap silently becomes a successful complete run |
| DT-MAC-03a / P0 / DT/SF/FL | Freeze the current Mac artifact and generate native launch, package, software/numerical and unmodified 1080p baseline receipts. Check GDU's pinned-template workaround and Compatibility shader-global regression | After 02a/b. Final exported bytes, same-host exact replay and H9 policy; engine errors invalidate a run even at exit 0. Missing GPU/physical data remains unqualified |
| DT-MAC-05a / P1 / VQ/PT | Add isolated method/driver experiments to `tools/graphics/launch.py` and its tests; keep import caches/preferences separate. Hold effects constant across Compatibility, Mobile/Metal and Forward+/Metal | After 03. Reject conflicting switches, preserve asset lookup, report actual method/driver, match native output size, audit all shader/viewports. Existing Standard/High product behavior remains the rollback |
| DT-MAC-05b / P1 / VQ/UI | After selecting a renderer, wire its allowed startup/restart/recovery policy through existing graphics preferences, shell and display menu. Renderer/backend selection and effect preset are separate concepts | Requires 05a native parity/performance. Failed initialization, malformed/obsolete preference, backend disappearance and repeated restart cannot trap the user. Safe Standard recovery preserves radio calibration |
| DT-MAC-06a / P1 / VQ/UI | Replace the Apple Auto name heuristic with a documented capability/default policy and measured quality decisions using `app/render/scene_detail.gd` and existing settings | After 05/06 evidence. Test M1 floor, unknown/new hardware, headless, changed driver and explicit user selection. No forced upgrade from a chip string; retain old manual settings |
| DT-MAC-07a / P1 / VQ | Add provider-specific capability, scale and AA policy to `app/render/reconstruction.gd`: MetalFX Spatial first, through stock engine APIs. Extend existing menu, settings normalization, labels/localization and adapter tests | After GPU-bound 05/06 result. Mobile/Metal and Forward+/Metal capability checks; unsupported enum/device/build/driver/scale → Native, honest reason. Spatial is **not temporal** and must not inherit temporal history or AA behavior |
| DT-MAC-07b / P1 / VQ/CAM | Add MetalFX Temporal with runtime scale range and correct history lifecycle. Extend existing camera discontinuity notifications and engine support only where the pinned API lacks a working reset | After 07a and Forward+ parity. Inspect actual depth, motion vectors, jitter, exposure and history reset in a native capture. The audited `b56eb5f` reset submission is DLSS-only; concurrent provider-advertisement/FSR work remains separate and proves no MetalFX reset. Failed/unqualified Temporal falls back automatically to Native; supported Spatial remains a separate user choice |
| DT-MAC-07c / P1 / VQ/UI/PT | Finish live availability/failure reporting, effective-mode verification, resize/fullscreen/Retina transitions and resource cleanup. Test repeat provider switches and restore saved native AA when leaving temporal | After 07a/b. No stale scaler textures, progressive allocation growth, fallback mislabeled as MetalFX or UI downscaling. All other providers retain their own capability and sharpening semantics |
| DT-MAC-06b / P1 / VQ/LU/SM | Apply one measured GPU change from §7: MSAA, shadows/probes, texture format/mips, bounded MultiMeshes or transparent coverage. Preserve generated-source ownership | Each change follows a capture identifying the limiter; paired native 1080p and moving-image acceptance plus lifecycle checks. Revert any unexplained >5% required-case regression |
| DT-MAC-08b / P1 / DT | Add native Mac CI/package checks and manual physical-host qualification to the existing export workflow. Verify ARM64 Mach-O slice, linked libraries, universal template swap workaround, signatures/notarization as applicable and packaged resources | After candidate selection. Run downloaded/quarantined final artifact on the floor and named newer OS; hosted/headless CI cannot qualify GPU, radio or thermals. Preserve current artifact and recovery recipe |
| DT-MAC-10 / P2 / GDU/VQ | Adopt or contribute a complete upstream Metal 4 command backend under §13; use an isolated exact engine revision, patch hashes, matching templates and symbols | After 05 attribution identifies a relevant engine limitation, or upstream provides a supported implementation worth evaluating. Full render-graph/queue correctness, MTL3 recovery and M1/newer-host regression required; never bundle with initial MetalFX |
| DT-MAC-11 / P2 / VQ/GDU | Evaluate 2026 MetalFX temporal inputs and neural path: OS-available descriptors, subrectangles and motion-vector conventions | After 07b and verified upstream/API support. Native SDK evidence on eligible hardware; source exposure and OS availability alone do not prove neural execution or benefit. Retain legacy Temporal and Native |
| DT-MAC-12 / P2 / VQ/DT/UI | Optional MetalFX frame interpolation feasibility and implementation under §13; independent of upscaling. Evaluate macOS 27 distortion-texture inputs only for this interpolator API | Requires real-frame pacing already meeting its gate, correct temporal inputs and engine presentation integration. End-to-end control latency, separate rendered/presented rates, UI composition and disable/recovery proof. Remains off until qualified |
| DT-MAC-13 / P2 / VQ | Conditional denoising, ray tracing, tensor/ML or engine memory/submission experiments from §13 | Only with a concrete supported renderer consumer and measured need. Record `trigger absent` for currently inapplicable techniques; do not create a ray tracer or ML workload merely to use an API |

First implement **02a → 02b → 03a**, with independent native-delivery and instrumentation work reviewable separately. Then **05a → 05b/06 → 07a → 07b/07c → 08/08b → 08a → 09**. P2 branches can be evaluated independently after their prerequisites, but cannot delay a qualified common baseline. Estimates remain relative: tooling/policy changes are bounded; Metal 4 command-backend and presentation work are engine projects. Estimate engineering days only after the baseline exposes the defect and the exact upstream delta is known.

Four implementation constraints refine those boundaries:

- **02a/08b delivery:** `app/export.sh` explicitly requires Linux and runs Linux x86_64/NK-3 acceptance. Retain those gates and split cross-export from Mac-native artifact checks, or introduce host-specific stages under DT. Replacing GNU `timeout` or checksum utilities alone does not make the complete exporter a Mac workflow. `app/test.sh` already uses the checked Python runner; inspect each script's actual host requirements.
- **02b/03a product coverage:** `--frametimes` selects direct flight, bypassing Home/display preferences, and `--scripted` disables input. Use explicitly matched effective settings for technical benchmarks and a separate real Home → Fly recording/soak route for product acceptance. Extend the existing collector into the shell route if necessary; do not count a scripted run as a pilot/input/preference test.
- **05b cold start:** GDScript reads `display.cfg` after renderer initialization; the current High restart is temporary and persists no backend. A durable choice needs a pre-engine launcher/bootstrap or an explicitly guarded two-stage restart with last-known-good choice, attempt marker, success acknowledgement and recovery from failed/hung initialization. Keep a direct Standard launch path, bound retries, clear stale attempts and preserve calibration. A settings-picker edit or 15-second display confirmation cannot recover a process that never initializes.
- **05a common effects:** an empty graphics-profile environment on Forward+ currently activates High. Define and test an explicit common-effects selection; simply clearing the environment would enable extra SSAO/shadow/reflection work and confound the comparison. Record effective effects for every candidate.

## 12. Capability, measurement and reconstruction contracts

Extend the existing diagnostics and reconstruction dictionaries rather than introducing another preferences store, profiler or render loop. This is the complete target contract; the Windows preparation implements a subset, described in DT-MAC-02 evidence. Unknown native command-backend/presentation status remains explicit.

| Contract | Required information / behavior |
| --- | --- |
| Identity | Source commit plus dirty patch hash, engine source/build/patch identity, editor/template/export hashes, import/config hashes, native architecture, host/model/CPU/GPU/RAM, macOS build, Xcode/tool versions |
| Backend | Requested/effective method and driver, fallback reason, adapter/API string, **verified command backend** (`MTL3`, `MTL4`, or unknown), capability source and query success. An OS advertising Metal 4 must not populate `MTL4` without implementation evidence |
| Display | Window points, drawable/output pixels, actual internal 3D dimensions when measurable (nominal estimate labeled otherwise), scale, display/refresh, VSync enum, FPS cap, fullscreen, UI scale, display changes |
| Provider | Requested/effective provider, availability and reason, engine enum, supported min/max scale, requested/applied scale, AA owner, provider-specific sharpening, engine substitution/failure, reset requested/submitted/acknowledged if supported |
| Performance | Frame-loop intervals, presented-frame evidence separately, viewport GPU/CPU scope and lag, tick time/unit and sim/wall ratio, pipeline-compilation counters, per-run distributions, hitch count/bursts, warm/cold/cache condition |
| Resources and power | Process RSS, engine texture/buffer estimates, system memory pressure/compression/swap with attribution limits, thermal/power state where available, AC/battery and Game Mode. Unavailable is null with reason, never zero; overlapping memory channels are not summed |
| Collection | Schema version, monotonic time origin and clock alignment uncertainty, sample capacity/drop count, chunks/sequence, start/end/expected duration, complete/interrupted/capped status, data hashes, diagnostic overhead and native trace references |

The existing frame collector and v2 reducers require stable finite numeric arrays. Preserve that format for old short-run reports; put missing-channel availability/reasons in separate metadata, or version and migrate readers before introducing nullable samples/chunks. Exercise 30-minute-equivalent synthetic streams at 60/120 Hz, missing/duplicate/out-of-order chunks, interrupted publication and old-format readers. At 1 Hz, configure more than 1,800 process-resource samples for a 30-minute run plus warmup and verify actual coverage/stop reason rather than accepting the default 600-sample cap.

Provider resolution is deterministic: normalize saved request → query actual capabilities → validate method/driver/scale → select a provider-specific AA and sharpening policy → apply → read back applied **inputs** → obtain engine-observed pass evidence → publish receipt. Keep requested policy, property readback and verified effective execution separate. The stock API does not guarantee visibility of every internal substitution or SDK failure; add a narrow upstream diagnostic if needed, or report unknown and disable the unqualified candidate. Preserve the saved request on temporary unavailability so the UI can explain the fallback; retain manual Native selection across restarts. Fail closed when the RD is absent or limits are invalid. Revalidate/recreate contexts when output size, backend or provider changes; resource retirement must wait for engine-owned GPU completion.

**Spatial:** preserve the accepted native AA policy and feed a resolved source texture; compare at 0.85 input scale first. **Temporal:** let the engine own jitter, velocity/depth conventions and its AA, while OpenRC signals real discontinuities and verifies their consumption. Do not apply FSR sharpness or DLSS-specific settings to MetalFX without a corresponding API. **History:** camera switch, teleport/reset, world/aircraft replacement, resize/scale change and resume after a discontinuity need a defined reset or context recreation. Ordinary camera movement must not reset every frame. Minimize/pause alone does not justify clearing valid history repeatedly.

Test injected policy fixtures for every supported/unsupported method-driver combination, absent RD/constants, invalid limits, persisted unknown values and engine substitution. Include rejected request → identical retry → restore Native → valid retry: a cached setter can skip an identical request after rejection. An absent RD disables optional providers while Native/Compatibility remains usable. Native Metal tests then establish allocation, SDK execution, motion and presentation correctness. A GPU capture qualifies its frozen configuration, not continuous runtime failure detection; that requires a tested engine status seam or an explicitly unobservable status. Use the existing checked GDScript tests, debug smoke, graphics checkers, frame reducers, lifecycle probe and flight-log workflow named by the [tool index](../tools/README.md); add focused cases to those tools. Fake capability tests do not close hardware gates.

## 13. Metal 4 and newest Apple features: integration decisions

The [Apple technology report](../research/desktop-delivery-investigations/DT-MAC-00-R2/apple-technologies.md) records dated API/device availability and sources. The [Godot compatibility report](../research/desktop-delivery-investigations/DT-MAC-00-R2/godot-compatibility.md) records what the exact engine implements. This separation is mandatory for every new feature.

| Technology | OpenRC action and implementation level | Entry and exit gates |
| --- | --- | --- |
| Native Metal rasterization | **Integrate/qualify now through stock Godot** after baseline; compare Mobile and Forward+ | Correct shaders, viewport parity, sustained cost and package recovery. Existing Metal support does not mean the default Compatibility renderer uses it |
| MetalFX Spatial / Temporal | **Implement application adapter**, reuse stock SDK integration | §7/§12. M1 remains a supported candidate; temporal requires Forward+, actual device feature and range |
| Metal 4 command allocators, argument tables, explicit synchronization and residency | **Engine-owned, upstream-first**, DT-MAC-10 | Driver must cover allocation reuse only after GPU completion, resource residency across in-flight frames, barriers and cross-queue events, native callbacks, presentation, shutdown/device errors and old-OS fallback. No direct GDScript implementation or second queue secretly sharing Godot resources |
| Metal 4 compiler, pipeline serialization and shader specialization | Prefer existing Godot caches/precompilation; expose newer paths only with upstream support and measured cold/first-use stalls | Version caches by engine/compiler/device/OS/config; test corruption, invalidation, cold and warm loads. Ship matching templates; do not distribute machine-specific cache blobs as universal binaries |
| 2026 neural MetalFX temporal scaler and new inputs | **Conditional engine exposure**, DT-MAC-11 | Apple documents newer neural behavior on M5 Pro/Max and macOS 27 inputs. Verify exact supported descriptors/hardware and compare legacy/scaler behavior with identical source frames. Do not generalize to every M5 or assume the pinned engine supplies the new inputs |
| MetalFX frame interpolation | **Separate optional presentation project**, DT-MAC-12 | Correct real-frame history/depth/motion, UI placement, drawable scheduling and variable refresh; cut/reset bypass, queue-depth/latency measurement, lower-power/unsupported fallback. Generated frames do not advance physics, sample controls or count toward the real-frame performance gate |
| MetalFX denoised upscaling / hardware ray tracing | **Defer until a rendering consumer exists**, DT-MAC-13 | Denoising needs appropriate noisy lighting/ray-tracing inputs and a matching renderer integration; it cannot be attached as a generic filter to the current raster image. Preserve M1/M2 raster baseline |
| GPU tensors, Metal ML and M5 Neural Accelerators | **No current simulator consumer**; use only if a future presentation workload justifies it | No flight-law migration, float64 reduction, fast-math policy change or inferred Neural Engine access from a Metal shader. Reuse supported models/tools rather than creating speculative neural effects |
| TBDR, memoryless attachments, heaps, residency, async compute and fast resource loading | Start with render-target/pass/texture savings exposed by Godot; engine patches only after bandwidth, synchronization or loading evidence | Track pass lifetime and store/resolve requirements, CPU/GPU hazards, upload rings and shared-memory pressure. Unified memory does not eliminate synchronization or make all storage modes equivalent |
| Mesh shading, indirect draws, tile shaders, raster-rate maps | Existing LOD/MultiMesh/culling first; engine work only for a proven compatible bottleneck | Correct visibility/velocity/shadows and hardware query; a feature in Apple's table is not an exposed Godot setting. No blanket foveation or variable-rate shading that harms distant-aircraft visibility |
| Metal display link / direct presentation, Game Mode, ProMotion and HDR | Profile Godot's current platform path; use supported pacing/window integration; investigate missing engine behavior upstream | 60 Hz/SDR baseline first, then 120 Hz/VRR/HDR as distinct display gates. Measure latency/color correctness and resume/monitor transitions; a fullscreen flag does not prove Game Mode or direct presentation |
| Xcode/Instruments, HUD, `gpucapture`/`gpudebug`, `metalperftrace`, GPTK 4 | **Reuse installed free tooling** with version/OS checks; integrate receipts into existing diagnosis workflow | New macOS 27 command-line GPU tools are optional developer aids, not a product OS requirement. Preserve older-host Instruments path; disable validation/HUD for final timings. GPTK is guidance/tooling, not a replacement runtime or D3D translation layer for this native Godot app |

Apple's 2026 guide introduces neural scaling, quantized tensor formats and newer MetalFX inputs; it does not establish OpenRC compatibility or speedups. [WWDC26 Metal guide](https://developer.apple.com/wwdc26/guides/metal/). The new capture/debug tools and porting workflows are described in [Apple's GPTK 4 session](https://developer.apple.com/videos/play/wwdc2026/357/). Use primary SDK availability and actual device queries over marketing family names.

**DT-MAC-10 sequence:** inspect the latest upstream implementation and open defects → pin one candidate/patch set → build native ARM64 editor/templates with symbols → run API/Shader Validation and resource/barrier tests → verify all OpenRC shaders/effects and lifecycle routes → pair MTL3/MTL4 at common features on the same OS/hardware → repeat uninstrumented floor/newer-host acceptance → promote only after DT/GDU/VQ review. If upstream lacks a maintainable implementation or no meaningful benefit is measured, record the unmet prerequisite and keep MTL3. An engine fork must name its maintainer, patch removal/upstream path, build inputs and security/update responsibility before adoption.

## 14. Release readiness, risks and completion definition

| Risk / severity | Mitigation / blocking evidence |
| --- | --- |
| Wrong claim of Metal 4 support / critical | Bind report to the actual command-backend source and native trace. Current pin is MTL3; OS capability labels cannot close DT-MAC-10 |
| Beta engine and stale historical assumptions / high | Recheck GDU issues against the exact binary. An upstream fix merged after the beta tag is absent unless explicitly patched; use tested template workaround and preserve release rollback |
| Small-aircraft temporal artifacts or added control latency / high | Moving-image pilot review plus native capture and latency evidence; reject faster output if orientation/landing cues degrade |
| M1/8 GB pressure or fanless throttling / high | Three uninterrupted 30-minute runs, warm transition cycles and pressure/swap attribution; keep common baseline and compare final five-minute windows |
| Native extension/package mismatch / high | Verify every delivered architecture and dynamic dependency; current NK-3 Mac admission is separate from universal engine packaging. Explicit GDScript fallback remains valid; no silent claim of native-solver parity |
| New API availability or SDK/OS mismatch / high | Runtime availability checks and actual support queries, weak-linking where an engine patch requires it, oldest-supported-host launch, missing-feature recovery |
| Render and presentation ownership violated / high | Engine owns queues, resources, frame graph and swapchain; use supported rendering boundaries or upstream code. A native texture handle alone is not a synchronization contract |
| Confounded measurements / medium | Freeze feature set, pixels, input/workload, cache/power state and engine separately; alternate paired runs and retain distributions/exclusions |
| Regressions from parallel renderer work / medium | Freeze commit plus dirty diff immediately before implementation/test; rerun provider policy and native checks after combined changes |

Release evidence is a matrix, not a single green checkbox: **build/import → native launch → software/numerical checks → shader/visual correctness → sustained performance → lifecycle/input/audio → final distribution trust**. All required stages must pass on each claimed host/OS/backend. The M1–M5 commitment remains explicit; newly released M6 hardware enters a separate coverage row with actual family/API/device queries and named results, without extrapolating from M5 or delaying the first M1 baseline. Do not claim unreleased variants or infer a GPU family absent from Apple's current table.

Completion of core integration means 02–09 accepted, Native fallback recoverable and final package evidence linked to its exact bytes. For conditional MetalFX work, either the trigger is present and its options are truthfully reported/tested, or the evidence records `trigger absent` and retains Native; the full MetalFX feature claim requires the former. Completion of an optional feature means its own 10–13 gates pass; otherwise publish it as unsupported/experimental/deferred with the missing prerequisite. Broad research is complete for this dated decision; implementation may reveal new defects. No Mac execution, speedup, thermal result, signed distribution or hardware qualification was produced by this documentation task.
