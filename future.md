# Optimization priorities by return on effort

Reviewed **2026-10-28**, source `f1e877d54`. Planning only: this review ran no new benchmarks.

**Implementation follow-up, 2026-10-28:** immediate Fly now overlaps numeric launch preparation with world construction. Five alternating native 1080p pairs reduce median first readiness from **3.789 to 3.531 s (6.8%)** on the measured Windows host; warm readiness is essentially unchanged. [UI-34c / DT-11a evidence and limits](docs/research/menu-investigations/UI-34c-R5/immediate-fly-2026-10-28/README.md). This is editor loading evidence, not release or flight-performance qualification.

**Second delivery, 2026-10-28:** NK-2a now reuses battery type and block-size queries within each physics tick. Three paired complete-session runs per case reduce CPU callback cost by a median **6.4% for P-51 trim** and **6.1% for Timber pack trim**; Stik runway idle is effectively unchanged. [Exact-state comparisons, lifecycle checks and limits](docs/research/native-kernel/NK-2a/battery-queries-2026-10-28/README.md). These are GDScript headless CPU measurements, not rendered-frame or native-backend qualification.

**Recommended next delivery:** establish a current release baseline at 1080p, then remove one measured observer, physics or loading cost. Prefer a small change with complete-workload evidence over a new scheduler, renderer or vendor SDK.

This document triages future optimization ideas. It introduces no new track or step IDs. The [global performance plan](docs/plans/global-performance-visual-quality.md) owns delivery gates; the [track registry](docs/README.md#tracks-plans-and-step-ids) assigns implementation ownership; [ROADMAP](ROADMAP.md#execution-order-and-release-gates) owns Gate P. Detailed status and evidence remain in those homes.

## 1. Actual starting point

Runtime/configuration take precedence over old plan headers. The global and Apple plans still contain 4.7.2-era assumptions; those do not authorize downgrading today's engine.

| Area | Verified starting point | Planning consequence |
| --- | --- | --- |
| Engine and default graphics | [Engine pin](app/get-godot.sh): official **4.8-beta1**, not stable 4.8. [Project settings](app/project.godot): Compatibility, 4x MSAA and a 1280x720 default viewport. | Qualify **1920x1080 first**, above-1080p second, 720p last. A configured viewport is not a product target. |
| Simulation | Float64 state, fixed 240 Hz, RK4 and one `VehicleModel` per session; [kernel contract](docs/STACK.md#boundaries-and-data-flow). | Keep precision, tick frequency, accepted-state/event order and replay contracts. The 500 microsecond Gate P remains open. |
| Fixed-wing native evaluation | [NK-3](research/native-kernel/README.md#optional-normal-flight-backend) is already requested by the app. Admission is limited to verified Linux x86_64, stock electric Ugly Stik and supported calm configurations. Other cases retain GDScript; low-level tools default to reference. | Verify actual backend and refusal reason. Native source files or a selector do not establish a qualified platform, aircraft or full native tick. |
| Prepared native data | NK-3 already decodes model/environment data at preparation boundaries and installs a joint stage evaluator. Its per-tick configuration guard does not reserialize/hash/decode the whole model. [Contract](research/native-kernel/README.md#contract). | Extend the existing boundary only when measured; do not propose a second prepared-model subsystem or remove mutation detection. |
| Tick/query repairs | [NK-2a](docs/research/native-kernel/NK-2a/README.md), [H18](docs/research/simulation-state/H18/README.md), [statistics](docs/research/flight-statistics/UI-FS-08-R1/README.md), [GP-19g](docs/research/ground-physics/GP-19/evidence/surface-table-check/README.md) and [LU-25-R7](docs/research/landscape-upgrade/LU-25-R7/README.md) already reduce capability, wake, observer and validation work. | Re-profile the remaining cost; historical hotspot lists are not an unfinished task list. |
| Glow root solver | [NITRO-06-R3](docs/research/glow-engines/NITRO-06-R3/README.md) already replaced the iterative carburettor root. Its 6.34 to 0.43 microseconds is a component result on a Linux dev VM. State fingerprints changed at round-off level. | Do not promise a 15x tick improvement or call this byte-exact. Further numerical changes need their own explicit physics rationale and replay evidence. |
| Loading | [UI-05-R3](docs/research/menu-investigations/UI-05-R3/README.md) implements bounded resource loading/latest selection. [UI-34c / DT-11a](docs/research/menu-investigations/UI-34c-R5/menu-preparation-2026-10-25/README.md) already prepares the selected flight while Home is visible. | Target immediate Fly and remaining construction stalls; do not rebuild generic asynchronous loading or speculative fleet prefetch. |
| Spatial/render batching | [Collision world](app/scenery/collision_world.gd) already uses 32 m cells and ordered candidates. [Treeline](app/render/treeline.gd) already uses bounded spatial MultiMeshes; [birds](app/scenery/birds.gd) are batched. | Integer keys, alternative indices and finer LOD/culling are experiments on existing systems, not missing foundations. |
| Reconstruction | Stock [High/FSR2 trials](docs/plans/advanced-graphics.md) and a separate [Windows/Vulkan DLSS/FSR 3.1.4 engine experiment](tools/graphics/native/README.md) exist. The latter uses a custom engine and prepared source snapshot. | Do not start another integration or imply these modes are qualified in the standard package. |

These corrections remove completed work from the future queue without discarding its evidence. Existing research remains linked in place; historical speedups must not be added together.

## 2. How ROI is ranked

Return means less CPU per simulated second, lower complete-session tick cost, smoother presented frames, shorter control-ready loading, or lower retained memory. Choose the metric before implementing. A faster helper alone is insufficient.

The order below is an engineering estimate, **not measured future speedup**. Prefer broad player benefit, strong attribution and small verification/maintenance cost. A current reproducible defect can move its row ahead of the others. Hardware qualification can proceed independently when its host is available.

Effort estimates cover **one bounded experiment, implementation if justified, and focused verification**, for one developer: **S = 1-3 days; M = 3-7 days; L = more than a week**. They exclude waiting for hardware/pilots and do not estimate an entire subsystem rewrite. Confidence describes the evidence for investigating the problem, not certainty that a candidate will win.

| Order | Existing owner/steps | Next bounded delivery | Expected return / effort | Confidence and dependency |
| --- | --- | --- | --- | --- |
| **0 - prerequisite** | **VQ-01c, DT-01/10a, NK-0** | Current release baseline: tick, observers, foreground 1080p pacing and Home/Fly phases, using existing tools. | High decision value; **S**. Avoids optimizing a repaired or irrelevant path. | High need; no performance gain claimed. Establish source, host and actual backend first. |
| **1** | **VQ-01c, GP-19, AUD, UI-FS** | Remove one remaining repeated observer calculation; consider cadence changes only for a measured presentation consumer. | Potentially high across ordinary flights; **S**, or **M** if its consumer contract changes. | Medium after several shipped repairs. Requires current observer attribution from 0. |
| **2** | **Gate P, H-series, NITRO** | One exact hot-path repair in the slowest current powered/flap/ground regime. First candidate: repeated clean-station terms in the flap coupling loop. | High on affected aircraft if still dominant; **S**. | Medium: repetition exists in source, but its current complete-tick saving is unmeasured. |
| **3** | **UI-34c, DT-11a, UI-05** | Immediate-Fly overlap delivered; next split one measured main-thread construction stall. | Visible launch/selection benefit; **M**. | Current overlap evidence above. Remaining construction hitches exceed 100 ms; preserve preparation ownership. |
| **4 - conditional** | **VQ-01c/d, VQ-02a, LU-10-R1, L/VQ owners** | Fix one attributed scenery query, texture-memory defect or expensive draw/material path. | Medium to high on affected scenes/hardware; **S-M**. | No universal GPU bottleneck established. Query and GPU candidates are separate experiments; visual work needs a motion/readability reference. |
| **5 - conditional** | **AFC-24/25** | Refresh 0-3 companion attribution at 1080p; remove one remaining planner/allocation/query/presentation cost. | High for companion users, limited solo benefit; **S-M**. | Historical degradation is established; current causes and supported counts are not. Existing R3/R5 repairs are already implemented. |
| **6 - gated** | **NK-1/4/8, SF-08, DT** | Qualify the existing native route on a named target/package; resolve Windows math identity before widening admission. | Potentially high but narrower reach and ongoing dual-source cost; **M-L**. | Linux evaluator benefit exists; target hardware and other platforms remain open. Stop expansion if the workload meets its budget. |

**Start with 0, then choose one of 1-3 from its findings.** Do not combine a data-layout rewrite, native batching and multirate presentation in one experiment: their individual value and regressions would be unidentifiable. Rows 4-6 open only when their workload or delivery requirement justifies them.

## 3. First implementation slices

### Remaining observers: retain behavior before changing frequency

The [2026-10-27 observer experiment](docs/research/visual-quality-implementation/VQ-01c/tick-observers-2026-10-27/README.md) removed observers and measured roughly 34% less main-thread CPU airborne and 23% on the runway. This was a headless shared VM, with a 30 fps cap, before subsequent repairs. It is an attribution ceiling, not achievable savings or an FPS forecast. `step_usec` excludes the emitted observers, so measure both boundaries.

GP-19f already reduced unloaded ground-audio work; UI-FS-08-R1 already optimized statistics sampling and speed-window sorting. Windsock/people-per-frame was tested and rejected for no measurable gain. Do not repeat these as new wins.

Re-profile remaining consumers, then reuse one accepted-state calculation or eliminate one proven redundant lookup. Changing the unloaded-wheel material lookup needs the existing audio contract resolved. Keep recorders, event detection, statistics accounting and touchdown/crash cues on their required samples. If a presentation consumer moves to frame cadence, preserve all intervening events, pause/reset/restore behavior and sound/visual continuity. A new event-journal framework is not a prerequisite for this slice.

### Aircraft hot path: reuse within one evaluation

The battery-query slice above is delivered using the existing per-tick facts. It also clears those facts before located-event and pause observers run. Keep native source-receipt checks intact; changed mirrored source requires native requalification. The flap loop below remains an unmeasured candidate.

Current [aero.gd](app/physics/aero.gd), `_local_loads`, recomputes `clean_angle_k`, `clean_weight_k` and `clean_source_k` inside each coupled flap station's inner loop. If a current powered/flap profile shows meaningful cost, calculate the station-only terms once within that invocation. Preserve reduction order, branch behavior and float64 grouping; include zero flow, reverse flow, stall and flap transitions in parity checks. Account for scratch allocation cost.

Do not reuse state-dependent results across RK4 stages. H18's existing wake reuse is not permission to cache every aerodynamic result. Coordinate mirrored-source hashes/refusal checks with NK-3. Profile glow/P-51 propulsion and fuel separately; a closed-form solver or changed arithmetic is a distinct physics change, not part of an exact performance patch.

### Immediate Fly and construction stalls

The [UI-34c preparation campaign](docs/research/menu-investigations/UI-34c-R5/menu-preparation-2026-10-25/README.md) measured first click-to-ready falling from 7.482 to 1.698 s with **5 s Home dwell**, on Windows/RTX 3090 at 1080p, Godot 4.7.2. Warm readiness barely changed; large loading frames remained. This does not establish immediate-Fly, current-engine or cold-cache performance.

The immediate-Fly overlap is now implemented: begin managed numeric preparation before world construction and finish once at the existing validation boundary. Exact initial-checkpoint, cancellation and raw-removal tests accompany the evidence above. The next loading slice should address a measured field/contact/sound/preview construction above 100 ms. Preserve latest-selection cancellation, failure recovery, bounded resources and responsive Quit; never move a stall to the first controlled flight frame. Reuse the current scene loader and preparation cache.

### Scene or companion cost only when attributed

For scenery, test a single change to existing query candidates or rendering chunks. Preserve earliest-hit/tie order, collision inventory and visible obstacles. For graphics, compare memory, draw calls, GPU time and moving aircraft readability before adopting texture/LOD/shader changes. The [pinned-engine scan](docs/research/godot-optimization-scan-2026-10-27.md) records that Compatibility alpha-to-coverage is ineffective and pipeline-compilation counters return zero; neither is a valid quick fix or shader-hitch diagnosis on this pin.

For companions, use [AFC-24/25](AI_FLIGHT_COMPANIONS_PLAN.md) and the existing [R4 evidence](docs/research/ai-companions/AFC-00-R4/README.md). Its roughly 52 ms frame p95 with three companions was an older 720p test; it neither identifies CPU cost nor qualifies 1080p. Re-measure after the promoted planner/observation repairs. Keep 240 Hz physics and deterministic decisions; AFC-27 workers/native batching require a demonstrated remaining solver/planner bottleneck.

## 4. Hardware work: measure capability, not brand promises

Use existing free tools and retained assets before creating replacements. Record CPU/GPU model, memory, OS/driver, power mode and engine/backend identity. A product name alone does not select an optimization.

| Target | First useful comparison | Gate for further work |
| --- | --- | --- |
| Available Windows/Linux reference host | Current release, verified 1080p output, actual reference/native physics, CPU/GPU attribution and presented-frame pacing. | Use the bottleneck to select rows 1-4; an RTX 3090 result is not minimum-hardware qualification. |
| MacBook Air M1, 8 GB | [DT-MAC-01-03](docs/plans/apple-silicon-performance.md): inventory, effective driver/collector checks, native ARM64 baseline, memory and sustained operation. Host availability was recorded; performance remains unmeasured. | DT-MAC-05 compares Compatibility, Mobile/Metal and Forward+/Metal with controlled quality after prerequisites. Use the current engine pin; verify on Mac rather than copying the plan's older pin. |
| Intel/AMD integrated GPU | Named laptop at 1080p; record shared-memory pressure, power/thermal state and CPU/GPU attribution. | One supported renderer, texture-budget or shader comparison if GPU/memory limited; report internal resolution separately from 1080p output. |
| Dedicated NVIDIA/AMD/Intel GPU | Current standard/High baseline and one expensive pass or pacing issue. | Reuse VQ-07 experiments. Reconstruction requires measured GPU benefit and aircraft-motion/readability acceptance. |

Higher resolutions follow primary 1080p qualification; 720p remains fallback evidence. Mac native physics remains reference-only under the current [NK owner decision](docs/research/native-kernel-scoping-2026-10-27.md#owner-decisions). A Metal rendering experiment does not change that policy.

## 5. Deferred ideas and explicit reopening conditions

| Idea | Why it is not in the first deliveries | Reopen only when |
| --- | --- | --- |
| Broad prepared-model/data-layout rewrite or aircraft-specialized plans | NK-2a and NK-3 already prepare/cache part of the path; public mutable data and fail-closed checks complicate global caching. | Current allocation/decoding cost dominates and NK-2's revision/invalidation boundaries are specified. Preserve [RCV-41](docs/research/rc-monster-truck/RCV-41/README.md) identity protections. |
| Dedicated simulation thread, deterministic jobs, fleet batching | State ownership, input latency, ordered events and reset/replay synchronization add substantial risk. | Smaller repairs still miss a named workload; an owner-reviewed contract and an isolated net-gain prototype justify AFC-27 or SF work. |
| Whole-tick C++ / internal Godot module | Current SF-08 admits an evaluator, not replacement of the kernel transaction. Maintaining two implementations has continuing cost. | NK-4 finds remaining need; NK-5 has an explicit SF-08 amendment. No blanket rewrite. |
| PGO/LTO, AVX2/AVX-512/NEON, custom allocators | No current whole-workload gain established; platform and exactness coverage expand. | A stable native hotspot/profile justifies one portable experiment with reference fallback. No global fast-math, FMA or ISA requirement. |
| QoS, fixed affinity, oneTBB/GCD scheduler integration | Work removal has broader benefit; OS placement and scheduling gains are unmeasured here. | A native trace proves scheduler contention after bounded existing work is optimized. Do not add a dependency for a speculative feature. |
| CUDA/ROCm/Metal Compute or NPU physics | No demonstrated benefit for the small float64 real-time workload; transfer/synchronization and numerical contracts must be included. | A separate, large offline batch workload proves value using existing tools. It cannot justify replacing live flight physics. |
| GPU-driven rendering, bindless, mesh shaders, async compute, render-pass forks | Engine-fork/platform maintenance exceeds the evidence available for this scene. | Pass/draw attribution shows existing Godot batching/LOD/material options cannot meet a named target. |
| More upscalers, dynamic resolution, frame generation, Reflex/XeLL/Anti-Lag | Existing reconstruction experiments are unqualified; these do not repair tick throughput. Input-to-photon latency has not been attributed. | VQ-07 has a named GPU-bound or measured latency need, supported APIs and complete image/control acceptance; retain the standard path. |
| Shader warmup, speculative prefetch, persistent caches | Loading already has bounded preparation; first-use stalls are not automatically shader compilation. | A reproducible cold/warm comparison identifies the exact remaining cause and a bounded cache/invalidation design. |

Do not schedule blanket Dictionary-to-RefCounted conversion, tiny RK4 buffer reuse, signal/lambda micro-optimization or the experimental separate render thread without new evidence: the [optimization scan](docs/research/godot-optimization-scan-2026-10-27.md) already records why these were not worthwhile. Vendor version announcements, chip-specific marketing claims, favicon citations and pasted chart fragments are not planning evidence.

## 6. Acceptance and stop rules

Use the [tool index](docs/tools/README.md), [performance tools](research/performance/README.md), [native tools](research/native-kernel/README.md) and [debug bridge](tools/debug/README.md). Extend them only for a demonstrated missing metric; do not build another benchmark/profiler framework.

1. **Freeze a comparable baseline.** Record commit plus dirty-source identity, engine/binary/build type, actual physics/render backend, aircraft/configuration, scenario/input tape, output/internal resolution and host conditions. Separate release from editor, native OS from VM, and process-cold from import/driver-cache cold. Do not benchmark concurrent heavy work.
2. **Measure the affected complete workload.** Default steady comparison: 10 s warmup + 60 s sample, at least three alternating baseline/candidate pairs. Loading: at least five fresh-process and five warm repetitions. Owning tracks keep stricter gates: AFC qualification uses three 120 s foreground runs after 30 s warmup and a 20-minute soak. Report tick/session/observer boundaries, p50/p95, frame p95/p99 and hitches, simulation/wall ratio, readiness and retained memory as applicable. Missing GPU/VRAM/input-to-photon data stays missing.
3. **Retain correctness.** Exact optimizations preserve existing oracle outputs, trajectories, events, checkpoint and replay identities, including invalid inputs and reset/restore. Keep NK backend admission and missing/mismatched-library fallback checks. For any intentional numerical/handling change, follow [flight logging](docs/FLIGHT-LOGGING.md): baseline `.orfl`, verified exact replay, one candidate on the same tape, `complete` and `solver_changed` checked. Do not update goldens to hide a difference. Software evidence is not physical validation.
4. **Adopt only a useful result.** Follow the global plan: exceed paired-run variation and improve at least 5% of the affected complete workload, or remove a named reproducible hitch/memory defect. Keep worst-case scenarios and perceptual checks. Process-loop targets remain p95 <=18 ms, p99 <=25 ms, simulation/wall 0.99-1.01; they are distinct from uncapped 16.67 ms throughput and displayed-frame evidence. Gate P remains 500 microseconds with its own target-host/regime definition. Loading targets remain Home <=5 s process-cold / <=3 s warm and Fly <=2 s. These are targets, not achieved claims.
5. **Stop or retain baseline when the gain is absent.** Record the candidate, paired results, correctness verdict and adoption/rejection in the owning evidence home. Re-rank from the new profile. If a workload meets its budget, do not expand its optimization project merely to consume the remaining ideas. Hardware/pilot gates stay open until actually exercised.

General methodology: [Godot optimization guidance](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html) supports profiling before changing code; [Godot 3D performance guidance](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html) describes existing LOD/instancing options. These are general references, checked 2026-10-28, not proof of a feature or speedup in the pinned OpenRC build.
