# Apple Silicon M1–M5 performance plan

2026-10-24 · **Owner:** desktop/performance maintainer (DT/PT), with VQ for rendering and SF/FL for numerical acceptance. **Prefix:** `DT-MAC-`. **Status:** research complete; implementation and native Mac qualification open.

Deliver a shared native ARM64 path that works well across **M1, M2, M3, M4 and M5 Macs**, including their actually released chip/chassis variants. The common performance objective is **1920×1080 / 60 Hz**, with quality scaling to measured headroom. Preserve aircraft readability, controls and simulation behavior. This is an execution subtrack of [Desktop delivery](../DESKTOP-DELIVERY-PLAN.md), not a claim of measured speedup or already-qualified support.

**Hardware available:** the user confirmed a **MacBook Air M1 with 8 GB unified memory** on 2026-10-24. This is the intended low-memory/fanless baseline host. GPU core count (7 or 8), exact model identifier and macOS build remain to be recorded. Use it for DT-MAC-01–03; hardware availability is confirmed, but native performance qualification has not run.

The [initial source review](../research/apple-silicon-performance-2026-10-24.md) records inspected repository state. The follow-up [20 internet investigations, I01–I20](../research/desktop-delivery-investigations/DT-MAC-00-R1/README.md) cover every requested generation, renderer/capability differences and execution tools. Their index maps findings to changed plan steps. Existing [DT-00-R2 investigations](../research/desktop-delivery-investigations/DT-00-R2/README.md) retain packaging, input, audio and ARM64 numerical evidence. This plan owns `DT-MAC` status; parent DT gates retain their authority.

## 1. Scope and ownership

Owned documentation: this plan and its dated research. Future measurement scripts and evidence belong under `research/performance/` and `docs/research/desktop-delivery-investigations/`, using the step ID in each evidence directory. Create those outputs only when work executes.

Shared changes require the existing owner: `main.gd` and frame collection (PT/VQ), `app/render/` and graphics tooling (VQ/FW/LU/SM), display/preferences (UI), exports and engine pins (DT/GDU), simulation and replay (SF/FL). Keep implementation to one measured mechanism per change. Recheck Git status before integration; these paths already have parallel work.

- Preserve float64 state, 240 Hz ticks, RK4 order, the shared `VehicleModel` boundary, collision identity and input sampling. Never lower physics frequency or precision to meet a graphics target.
- Keep Godot **4.7.2-stable** pinned during the initial comparison. The [4.8 upgrade](godot-4.8-upgrade.md) is a separate dependency change.
- Use official Godot binaries, Xcode/Instruments, existing project tooling and existing licensed assets. Download available free tools rather than building a profiler, renderer or asset replacement.
- Follow [resolution priority](../../AGENTS.md#display-resolution-priorities): 1080p first, above 1080p second, 720p last. A reconstructed 1080p output must disclose its lower internal resolution.
- Native ARM64, Intel under Rosetta, native Intel and hosted CI are separate results. This track qualifies named Apple Silicon configurations only.
- Keep a common distribution and baseline render path; chip-specific native instructions, hardware ray tracing, Metal 4-only features and M5-only GPU facilities cannot become mandatory for M1/M2. Optional paths require engine, OS and actual device support, not a chip-name match.

## 2. Starting point and decisions to test

| Observed on 2026-10-24 | Consequence |
| --- | --- |
| [Project settings](../../app/project.godot) select Compatibility, a 1280×720 default viewport and 4× MSAA | Explicitly set and verify 1080p backing/render pixels; the default is not the target |
| [Engine downloader](../../app/get-godot.sh) fetches a Linux x86_64 editor; [export preset](../../app/export_presets.cfg) is macOS universal | Supply a pinned native Mac editor and verify exported execution; do not run the Linux download recipe on macOS |
| [High trial](../../tools/graphics/README.md) changes renderer, SSAO, shadow atlas/cascades and reflections | Standard versus High is a product-profile comparison, not an isolated Metal benchmark |
| [Frame diagnosis](../../research/performance/README.md#cpu-gpu-and-memory-diagnosis) has a 300 s bound; Mac Compatibility viewport timing is disabled | Fix continuous soak collection first; missing GPU timing is not zero GPU cost |
| Frame reports name method/adapter/API but lack an explicit effective driver field; VSync is a boolean | Extend existing metadata to distinguish native Metal, MoltenVK, OpenGL, fallbacks and actual pacing mode |
| Current [reconstruction adapter](../../app/render/reconstruction.gd) has Native/FSR2 and experimental FSR3/DLSS modes, no MetalFX mode | Engine support does not mean OpenRC exposes or qualifies MetalFX |
| [High guide](../../tools/graphics/README.md) records a 4.7.2 Forward+ reflection-resource leak and a Windows-only backport experiment | Reproduce on Mac; world-switch memory growth blocks adoption. Do not silently import a custom engine |

**Working hypothesis:** Mobile/Metal deserves the first renderer experiment for the M1 floor; Forward+/Metal remains a serious comparison for feature coverage and higher tiers. Compatibility remains the control and recovery path. The winner is determined by whole-session timing, power, memory and visual acceptance, not API reputation.

Godot supports both Mobile and Forward+ on native Metal; Vulkan on macOS uses MoltenVK. Godot 4.7 documents Metal 4 on macOS 26+, with Metal 3 on older supported systems. Engine documentation gives macOS 13 as the Apple Silicon export floor; the product floor still needs package and hardware tests. [Godot rendering architecture](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html), [system requirements](https://docs.godotengine.org/en/4.7/about/system_requirements.html).

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
| M5 | Apple10 | Newest optional capabilities, import formats and quality headroom | Hardware test pending |

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
- Run at least two 30-minute release soaks per baseline/finalist on the floor machine, beginning from comparable conditions. Compare early and final five-minute windows, hitch bursts, memory/swap and thermal state. Do not concatenate six process restarts and call them one soak.
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

The tagged **4.7.2** API already declares MetalFX Spatial and Temporal, restricted to Metal. Temporal supports a capability-dependent minimum scale; enum presence alone does not prove a particular method/device supports the requested path. [Pinned Viewport API](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Viewport.xml).

The [pinned-source investigation I10](../research/desktop-delivery-investigations/DT-MAC-00-R1/02-rendering.md#i10--metalfx-support-in-godot-472-and-m1m5) sharpens the method matrix:

| Effective method / driver | Spatial | Temporal |
| --- | --- | --- |
| Compatibility / OpenGL | Unavailable | Unavailable |
| Mobile / Metal | Shared RD spatial path; require device/OS/build support | No Forward+ temporal path; keep unavailable |
| Forward+ / Metal | Require actual support | Require actual support and enabled engine build path; respect device scale limits |
| Mobile or Forward+ / Vulkan via MoltenVK | Not native MetalFX through this driver | Not native MetalFX through this driver |

Godot's [device checks](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/metal/metal_device_properties.cpp) call MetalFX `supportsDevice`; temporal is also build-gated. Read the engine's effective capability rather than inventing an M1–M5 name whitelist. The current adapter gates optional reconstruction through High; a Mobile spatial trial must refine that gate through its owner, not spoof High/effects metadata.

After native 1080p baseline and renderer parity, extend the existing reconstruction adapter only if GPU pixel work remains limiting. Verify the pinned engine's actual method/device support, effective mode and fallback. Compare Native against spatial reconstruction first, then temporal on supported Forward+; start at 0.85 scale only if allowed by the device, considering lower scales only if attitude/readability passes. Keep output/UI at 1080p and report internal dimensions. Repeat at higher output resolutions only after the primary gate.

Temporal review must include distant aircraft, propeller/hinges, wind-driven foliage, smoke, thin markings, camera cuts, reset/teleport, pause/resume and disocclusion. Account for history buffers, motion vectors, AA ownership and reconstruction overhead. Unsupported requests must resolve to Native with an honest effective-mode report. Keep FSR2 as a supported-method comparison; the separate Windows/Vulkan FSR3/DLSS engine experiment is not a Mac solution. No frame-generation work is included.

## 8. Execution steps and stop rules

| ID | Work / owner and dependency | Proof/status |
| --- | --- | --- |
| DT-MAC-00 | Research and repository audit; DT/VQ | Done: [2026-10-24 source review](../research/apple-silicon-performance-2026-10-24.md); no native measurements |
| DT-MAC-00-R1 | Twenty internet investigations and M1–M5 plan revision | Done: [I01–I20](../research/desktop-delivery-investigations/DT-MAC-00-R1/README.md); user confirms M1 availability, no hardware tests performed |
| DT-MAC-01 | Inventory the available M1 Air/8 GB; freeze OS/display/power matrix, package identity and budgets; DT-01a | Model family and RAM confirmed by user; GPU variant, OS/build and native ARM64 launch evidence pending |
| DT-MAC-02 | Native tooling and measurement gaps: driver/pacing metadata, bounded continuous soak, observer controls; PT with DT-02a/10a/10b; after 01 | Open; runner smoke, schema/limit/failure checks and overhead report |
| DT-MAC-03 | Unmodified 1080p baseline, numerical policy and bottleneck attribution; SF/FL + DT; after 02 | Open; paired short runs, baseline soak, exact local replay and H9 results |
| DT-MAC-04 | One highest-impact CPU/loading/memory fix if baseline calls for it; owner from §7 with DT-11a | Open/conditional; paired proof and full-workload regression checks |
| DT-MAC-05 | Isolated Mobile/Metal and Forward+/Metal parity/comparison, MoltenVK control only as needed; VQ + DT-11d; after 03 and a frozen 04 outcome | Open/conditional; effective-backend receipts, visual report and native distributions |
| DT-MAC-06 | One GPU/settings improvement at a time; VQ/LU/FW/SM + DT-11c; after attribution | Open/conditional; native 1080p performance and readability acceptance |
| DT-MAC-06a | Common capability policy and measured preset selection across M1–M5; VQ/UI; after 05/06 | Open; unsupported/unknown capabilities, saved-preference migration, effective-mode reporting and recovery tests (§9) |
| DT-MAC-07 | MetalFX capability/integration trial through reconstruction owner; after 05/06 justify it | Open/conditional; supported-method matrix, Native fallback and moving-image proof |
| DT-MAC-08 | Finalist 30-minute AC/battery soaks, lifecycle/input/audio/display recovery and native package checks; DT-10b/12, UI/AUD | Open; final artifact reports; then higher-resolution and lastly 720p compatibility results |
| DT-MAC-08a | Run the same release matrix on M2, M3, M4 and M5 and feed regressions back to the M1 control | Open; named physical tester artifacts and five-generation ledger, with explicit variant/OS gaps |
| DT-MAC-09 | Integrate accepted settings/backend policy, document tested M1–M5 configurations and recovery, retain baseline rollback; DT/VQ + DT-13 | Open; 06a/08/08a outcomes, focused/full relevant suites, final Mac package and owner/pilot acceptance |

First delivery is **01–03: a reproducible M1 baseline and ranked bottleneck report**. Then select the smallest justified branch. Estimate implementation effort after attribution rather than promising a speedup or fixed delivery date now.

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

Keep quality fixed during the initial comparisons. A later automatic-quality experiment is conditional on sustained-load evidence: adjust only existing presentation controls, use hysteresis/cooldowns, preserve user override and record every transition. Prefer less costly effects before reducing aircraft visibility; exclude physics, collision populations and control sampling. Never auto-upgrade the renderer mid-flight. Reset adaptation after a hardware/backend change instead of trusting stale calibration. Do not collect cloud telemetry or run a surprise stress test at every launch.

## 10. First test session on the available M1

The immediate deliverable is a local evidence bundle, not another research round. Use the owning tool READMEs for commands and add any necessary Mac adapter there once implemented.

1. **Inventory (01):** record the confirmed M1 Air/8 GB, then obtain GPU core count, exact model identifier, macOS build, display/power modes and free storage. The low-memory/fanless host is available; 7-core GPU coverage depends on identification. Avoid collecting serial numbers or unrelated personal logs.
2. **Freeze (01/02):** choose one clean revision and matching pinned editor/templates/export; retain hashes and import identity. Verify ARM64 execution and package dependencies. Use new ignored output folders; do not modify the user's normal graphics/controller preferences.
3. **Compatibility control (03):** native 1080p/60 Hz, fixed landscape/aircraft/weather; run software/replay checks, short timing pairs and a Home/Fly/Workshop lifecycle pass. Verify active physics and readable controls before a long run.
4. **Attribution (03):** one short CPU profile and one supported GPU/timeline capture; prove the observer cost and identify the dominant missed budget. Preserve the uninstrumented reference.
5. **Sustained baseline (02/03):** once continuous collection is ready, two uninterrupted 30-minute runs with explicit AC/power/thermal conditions; battery cases only on a laptop. Report missing channels and incomplete runs.
6. **One candidate (04–07):** choose the top attributed fix or common-feature Metal trial, replay the same workload, and accept/reject with the frozen gates. Re-run the baseline after integration before sending the same package/cases to M2–M5 testers.

Completion receipt: host manifest, source/package identities, effective settings, logs, complete timing/resource summaries, replay result, lifecycle result, profiler attribution, actual test exclusions and the next single candidate. Device access/remote transport has not been configured by this documentation task, and no Mac benchmark has run yet.
